-- Migration additive ; aucune suppression exécutée lors de l’installation.
BEGIN;
create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;
alter table public.commandes add column if not exists client_id uuid;
alter table public.commandes add column if not exists fournisseur_ref text not null default '';
alter table public.commandes add column if not exists revendeur boolean not null default false;
alter table public.commandes add column if not exists tentative_le timestamptz;
alter table public.commandes add column if not exists transaction_annoncee text not null default '';
alter table public.commandes add column if not exists compte_supprime boolean not null default false;

create or replace function public.client_commandes(client uuid)
returns table (
  id text, numero text, cree_le timestamptz, paye_le timestamptz,
  etat text, total bigint, revendeur boolean,
  articles bigint, boutiques text, rattachee boolean)
language plpgsql stable security definer set search_path = public as $$
declare mien public.clients%rowtype;
begin
  if not public.est_super() or client is null then return; end if;
  select * into mien from public.clients where clients.id = client;
  if not found then return; end if;
  return query
    select v.id, v.numero, v.cree_le, v.paye_le, v.etat,
           v.total::bigint, v.revendeur,
           count(l.id)::bigint,
           coalesce(string_agg(distinct b.nom, ', '), '')::text,
           v.client_id is not null
      from public.commandes v
      left join public.commande_lignes l on l.commande_id = v.id
      left join public.boutiques b on b.id = l.boutique_id
     where v.client_id = client
        or (v.client_id is null
            and not v.compte_supprime
            and mien.tel_verifie and coalesce(mien.tel, '') <> ''
            and v.client_tel = mien.tel
            and v.cree_le > now() - interval '18 months')
     group by v.id, v.numero, v.cree_le, v.paye_le, v.etat,
              v.total, v.revendeur, v.client_id
     order by v.cree_le desc
     limit 100;
end $$;

create or replace function public.commande_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- La base écrit pour elle-même : le total qui suit ses lignes, la
  -- monnaie posée à la création. Ces drapeaux n'existent que le temps de
  -- l'appel — ils ne s'attrapent pas depuis PostgREST.
  if coalesce(current_setting('bizzoo.interne', true), '') = 'oui' then
    return new;
  end if;
  if coalesce(current_setting('bizzoo.paiement', true), '') = 'oui' then
    return new;   -- l'agrégateur, ou l'enseigne qui se porte garante
  end if;

  if not public.est_equipe() then
    raise exception 'Seule l''équipe suit une commande';
  end if;

  -- L'équipe suit la commande, elle ne la réécrit pas.
  if new.total is distinct from old.total
  or new.client_nom is distinct from old.client_nom
  or new.client_tel is distinct from old.client_tel
  or new.client_adresse is distinct from old.client_adresse
  -- À qui appartient cette commande. La réattribuer, c'est offrir à
  -- quelqu'un l'historique, les avis et le SAV d'un autre.
  or new.client_id is distinct from old.client_id
  or new.compte_supprime is distinct from old.compte_supprime
  -- Et sous quel régime de prix elle est partie : la basculer après
  -- coup, c'est réécrire ce que la boutique a touché.
  or new.revendeur is distinct from old.revendeur
  or new.transaction_id is distinct from old.transaction_id
  or new.transaction_annoncee is distinct from old.transaction_annoncee
  -- La référence de l'agrégateur est ce avec quoi notre serveur ira lui
  -- demander si le versement a abouti. La laisser réécrire, c'est
  -- laisser désigner quel versement répond pour quelle commande.
  or new.fournisseur_ref is distinct from old.fournisseur_ref
  or new.tentative_le is distinct from old.tentative_le
  or new.confirme_par is distinct from old.confirme_par
  or new.paye_le is distinct from old.paye_le then
    raise exception 'Le montant et le paiement d''une commande ne se réécrivent pas';
  end if;

  -- Et surtout : elle n'invente pas un encaissement.
  if new.etat = 'payee' and old.etat <> 'payee' then
    raise exception 'Seul l''agrégateur de paiement déclare un paiement';
  end if;
  if old.etat = 'payee' and new.etat not in ('payee', 'annulee') then
    raise exception 'Une commande payée ne peut être qu''annulée';
  end if;
  return new;
end $$;

create or replace function public.suivre_commande(cible text, tel text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.commandes%rowtype;
begin
  select * into c from public.commandes
   where id = cible
     and not compte_supprime
     and client_tel = regexp_replace(coalesce(tel, ''), '\D', '', 'g');
  if not found then return null; end if;
  return jsonb_build_object(
    'numero', c.numero, 'etat', c.etat, 'total', c.total, 'devise', c.devise,
    'paye_le', c.paye_le, 'remarque', c.remarque);
end $$;

create or replace function public.commande_pour_paiement(cible text, tel text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.commandes%rowtype;
begin
  select * into c from public.commandes
   where id = coalesce(cible, '')
     and not compte_supprime
     and client_tel = regexp_replace(coalesce(tel, ''), '\D', '', 'g');
  if not found then return null; end if;
  return jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'etat', c.etat,
    'total', c.total, 'devise', c.devise,
    'nom', c.client_nom, 'tel', c.client_tel,
    'reference', c.fournisseur_ref,
    -- Pour que l'Edge Function refuse une relance AVANT d'appeler
    -- l'agrégateur : sinon le téléphone sonnerait quand même, et c'est
    -- seulement en rangeant la référence qu'on s'apercevrait du frein.
    'tentative_le', c.tentative_le);
end $$;

create or replace function public.rattacher_mes_commandes() returns int
language plpgsql security definer set search_path = public as $$
declare moi uuid := auth.uid(); mien public.clients%rowtype; combien int;
begin
  if moi is null then return 0; end if;
  select * into mien from public.clients where id = moi;
  if not found or not mien.tel_verifie or coalesce(mien.tel, '') = '' then
    raise exception 'Vérifiez votre numéro pour retrouver vos commandes';
  end if;

  perform set_config('bizzoo.interne', 'oui', true);
  update public.commandes
     set client_id = moi
   where client_id is null
     and not compte_supprime
     and client_tel = mien.tel
     and cree_le > now() - interval '18 months';
  get diagnostics combien = row_count;
  return combien;
end $$;

create or replace function public.supprimer_mon_compte(confirmation text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  ancien text := coalesce(current_setting('bizzoo.interne', true), '');
begin
  if moi is null or not exists (select 1 from auth.users where id = moi) then
    raise exception 'Connexion nécessaire';
  end if;
  if confirmation is distinct from 'SUPPRIMER' then
    raise exception 'Confirmez la suppression définitive';
  end if;
  -- Ne pas retirer le dernier responsable capable d'administrer la plateforme.
  if exists (select 1 from public.profils where id = moi and role = 'superadministrateur') then
    perform 1 from public.profils where role = 'superadministrateur' for update;
    if not exists (select 1 from public.profils where role = 'superadministrateur' and actif and id <> moi) then
      raise exception 'Transférez la responsabilité à un autre superadministrateur actif avant de supprimer ce compte';
    end if;
  end if;
  perform set_config('bizzoo.interne', 'oui', true);
  -- Les pièces commerciales restent dans leur périmètre métier, mais ne
  -- pourront plus être récupérées par un futur compte portant le même numéro.
  update public.commandes set compte_supprime = true where client_id = moi;
  delete from auth.users where id = moi;
  perform set_config('bizzoo.interne', ancien, true);
end $$;
revoke all on function public.supprimer_mon_compte(text) from public, anon;
grant execute on function public.supprimer_mon_compte(text) to authenticated;
COMMIT;
