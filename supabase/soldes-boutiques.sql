-- =========================================================
-- BIZZOO 3.59.0 — Le solde de chaque boutique, et ses reversements
--
--   Chaque boutique voit son SOLDE : ses ventes livrées, commission de
--   BIZZOO déduite (le prix BIZZOO de chaque article). L'administrateur
--   règle le numéro qui recevra les fonds et demande un reversement ; le
--   superadministrateur l'envoie et le valide (avec la référence de la
--   transaction), ou le refuse avec un motif.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- À coller APRÈS suivi-commandes.sql.
-- =========================================================

-- Les colonnes que les fonctions plus bas lisent.
alter table public.commande_lignes add column if not exists prix_bizzoo int not null default 0;

-- ---------- Le solde de chaque boutique, et ses reversements (3.59.0) ----------
--
-- TOUT L'ARGENT ARRIVE CHEZ BIZZOO : l'acompte en ligne, le reste par
-- MoMoPay. Chaque boutique a donc, chez BIZZOO, un SOLDE : ce que lui
-- rapportent ses ventes, commission de BIZZOO déduite — le prix BIZZOO de
-- chaque article, celui qu'elle a fixé en créant le produit.
--
--   GAGNÉ          ses articles REMIS au client (une vente n'est acquise
--                  qu'une fois livrée) ;
--   À VENIR        ses articles payés, pas encore remis ;
--   DÉJÀ ENCAISSÉ  le reste payé en espèces, du temps où le livreur le
--                  rendait à la boutique : elle a déjà cet argent en main ;
--   REVERSÉ        les reversements validés par BIZZOO ;
--   EN ATTENTE     les demandes pas encore tranchées ;
--   DISPONIBLE     gagné − déjà encaissé − reversé − en attente.
--
-- Les frais de livraison ne sont pas des ventes : ils n'y entrent pas.
--
-- LE NUMÉRO DE RÉCEPTION vit dans une table à part, fermée : la table des
-- boutiques se lit sans compte, et un numéro de paiement n'a pas à
-- traîner sous les yeux de tous. Chaque demande garde le numéro du moment
-- où elle a été faite.
create table if not exists public.boutiques_reception (
  boutique_id text primary key references public.boutiques(id) on delete cascade,
  tel         text not null default '',
  reseau      text not null default '' check (reseau in ('', 'MTN', 'MOOV', 'CELTIIS')),
  titulaire   text not null default '',
  maj_le      timestamptz not null default now(),
  maj_par     text not null default ''
);
alter table public.boutiques_reception enable row level security;
revoke all on public.boutiques_reception from anon, authenticated;

create table if not exists public.reversements (
  id          bigserial primary key,
  boutique_id text not null references public.boutiques(id) on delete cascade,
  montant     bigint not null check (montant > 0),
  tel         text not null default '',
  reseau      text not null default '',
  titulaire   text not null default '',
  etat        text not null default 'en_attente' check (etat in ('en_attente', 'valide', 'refuse')),
  demande_par text not null default '',
  demande_le  timestamptz not null default now(),
  decide_par  text not null default '',
  decide_le   timestamptz,
  reference   text not null default '',
  motif       text not null default ''
);
create index if not exists reversements_boutique on public.reversements(boutique_id, demande_le desc);
create index if not exists reversements_attente on public.reversements(demande_le) where etat = 'en_attente';
alter table public.reversements enable row level security;
revoke all on public.reversements from anon, authenticated;
revoke all on sequence public.reversements_id_seq from anon, authenticated;

-- Qui DEMANDE un reversement et règle le numéro : l'administrateur de la
-- boutique, ou le superadministrateur. Un modérateur, non : c'est de
-- l'argent.
-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false)
     and public.role_courant() is not null;
$$;



create or replace function public.droit_enseigne(lequel text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_compte_enseigne() and coalesce((
    select case lequel
             when 'commandes' then p.peut_commandes
             when 'boutiques' then p.peut_boutiques
             when 'finances'  then p.peut_finances
             when 'produits'  then p.peut_modifier_produits
             else false
           end
      from public.profils p
     where p.id = auth.uid() and p.actif), false);
$$;


create or replace function public.enseigne_des_commandes() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.boutique_id is null and p.peut_commandes
     and p.role in ('administrateur', 'moderateur');
$$;


create or replace function public.equipe_de(cible text) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and cible is not null and p.boutique_id = cible
     and p.role in ('administrateur', 'moderateur');
$$;



create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;


create or replace function public.les_superadmins() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.role = 'superadministrateur';
$$;

revoke all on function public.equipe_de(text)            from public, anon, authenticated;
revoke all on function public.enseigne_des_commandes()   from public, anon, authenticated;
revoke all on function public.les_superadmins()          from public, anon, authenticated;

create or replace function public.montant_lisible(n numeric, devise text default 'FCFA')
returns text
language sql immutable set search_path = public as $$
  select replace(to_char(coalesce(n, 0), 'FM999,999,999,990'), ',', ' ') || ' ' || coalesce(nullif(devise, ''), 'FCFA');
$$;
revoke all on function public.montant_lisible(numeric, text) from public, anon, authenticated;

create or replace function public.notifier(
  qui uuid[], quoi text, le_titre text, le_corps text,
  le_lien text, la_commande text, la_boutique text, qui_sonne boolean)
returns int
language plpgsql security definer set search_path = public as $$
declare combien int := 0;
begin
  if qui is null or array_length(qui, 1) is null then return 0; end if;
  insert into public.notifications
    (destinataire, type, titre, corps, lien, commande_id, boutique_id, sonne)
  select u, quoi, coalesce(le_titre, ''), coalesce(le_corps, ''),
         coalesce(le_lien, ''), la_commande, la_boutique, coalesce(qui_sonne, false)
    from unnest(qui) as u
   where u is not null
  on conflict do nothing;
  get diagnostics combien = row_count;
  return combien;
end $$;
revoke all on function public.notifier(uuid[], text, text, text, text, text, text, boolean)
  from public, anon, authenticated;

create or replace function public.tient_la_caisse(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.droit_enseigne('commandes')
      or public.droit_enseigne('finances')
      or (public.est_admin() and cible is not null
          and cible = public.boutique_du_compte());
$$;
revoke all on function public.tient_la_caisse(text) from public, anon, authenticated;
grant execute on function public.tient_la_caisse(text) to authenticated;


create or replace function public.gere_les_fonds(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or (public.est_admin() and cible is not null and cible = public.boutique_du_compte());
$$;
revoke all on function public.gere_les_fonds(text) from public, anon, authenticated;
grant execute on function public.gere_les_fonds(text) to authenticated;

create or replace function public.nom_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select coalesce(nullif(p.nom, ''), nullif(p.email, ''), 'l''équipe')
                     from public.profils p where p.id = auth.uid()), '');
$$;
revoke all on function public.nom_du_compte() from public, anon, authenticated;

create or replace function public.solde_boutique(cible text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  gagne bigint; a_venir bigint; encaisse bigint; reverse bigint; attente bigint;
  r public.boutiques_reception%rowtype;
begin
  if not public.tient_la_caisse(cible) then
    raise exception 'Ce solde n''est pas celui de votre boutique.';
  end if;
  select coalesce(sum(l.prix_bizzoo::bigint * l.quantite) filter (where l.etat = 'remise'), 0),
         coalesce(sum(l.prix_bizzoo::bigint * l.quantite)
                    filter (where l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')), 0)
    into gagne, a_venir
    from public.commande_lignes l
    join public.commandes c on c.id = l.commande_id and c.etat = 'payee'
   where l.boutique_id = cible;
  select coalesce(sum(x.montant), 0) into encaisse from public.encaissements x
   where x.boutique_id = cible and x.mode = 'especes' and x.remis_le is not null;
  select coalesce(sum(v.montant) filter (where v.etat = 'valide'), 0),
         coalesce(sum(v.montant) filter (where v.etat = 'en_attente'), 0)
    into reverse, attente
    from public.reversements v where v.boutique_id = cible;
  select * into r from public.boutiques_reception where boutique_id = cible;
  return jsonb_build_object(
    'gagne', gagne, 'a_venir', a_venir, 'deja_encaisse', encaisse,
    'reverse', reverse, 'en_attente', attente,
    'disponible', greatest(0, gagne - encaisse - reverse - attente),
    'devise', coalesce((select nullif(b.devise, '') from public.boutiques b where b.id = cible), 'FCFA'),
    'reception', case when r.boutique_id is null or r.tel = '' then null
                      else jsonb_build_object('tel', r.tel, 'reseau', r.reseau, 'titulaire', r.titulaire,
                                              'maj_le', r.maj_le, 'maj_par', r.maj_par) end);
end $$;
revoke all on function public.solde_boutique(text) from public, anon;
grant execute on function public.solde_boutique(text) to authenticated;

-- LE NUMÉRO DE RÉCEPTION. Le changer prévient BIZZOO : c'est la porte
-- par laquelle on détournerait les reversements d'une boutique.
create or replace function public.regler_reception(cible text, tel text, reseau text, titulaire text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  national text := regexp_replace(coalesce(tel, ''), '\D', '', 'g');
  res      text := upper(coalesce(reseau, ''));
  qui      text := public.nom_du_compte();
begin
  if not public.gere_les_fonds(cible) then
    raise exception 'Seul l''administrateur de la boutique règle son numéro de réception.';
  end if;
  national := regexp_replace(national, '^229', '');
  if length(national) = 8 then national := '01' || national; end if;
  if length(national) <> 10 or national !~ '^01[0-9]+' then
    raise exception 'Ce numéro n''a pas la forme d''un numéro béninois : dix chiffres commençant par 01.'
      using errcode = 'P0001';
  end if;
  if res not in ('MTN', 'MOOV', 'CELTIIS') then
    raise exception 'Choisissez le réseau du numéro : MTN, Moov ou Celtiis.' using errcode = 'P0001';
  end if;
  insert into public.boutiques_reception (boutique_id, tel, reseau, titulaire, maj_le, maj_par)
  values (cible, national, res, left(trim(coalesce(titulaire, '')), 80), now(), qui)
  on conflict (boutique_id) do update
     set tel = excluded.tel, reseau = excluded.reseau, titulaire = excluded.titulaire,
         maj_le = now(), maj_par = excluded.maj_par;
  perform public.notifier(public.les_superadmins(), 'reception_reglee',
    'Numéro de réception changé — ' || coalesce((select b.nom from public.boutiques b where b.id = cible), cible),
    qui || ' a réglé le numéro de réception : ' || res || ' ' || national ||
      coalesce(' (' || nullif(trim(coalesce(titulaire, '')), '') || ')', '') || '.',
    '#/reversements', null, cible, false);
  return jsonb_build_object('tel', national, 'reseau', res);
end $$;
revoke all on function public.regler_reception(text, text, text, text) from public, anon;
grant execute on function public.regler_reception(text, text, text, text) to authenticated;

create or replace function public.demander_reversement(cible text, montant bigint)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  solde jsonb;
  r     public.boutiques_reception%rowtype;
  qui   text := public.nom_du_compte();
  nouv  bigint;
begin
  if not public.gere_les_fonds(cible) then
    raise exception 'Seul l''administrateur de la boutique demande un reversement.';
  end if;
  -- Une demande à la fois par boutique : on la tranche avant la suivante.
  perform 1 from public.boutiques b where b.id = cible for update;
  select * into r from public.boutiques_reception where boutique_id = cible;
  if r.boutique_id is null or r.tel = '' then
    raise exception 'Réglez d''abord le numéro qui recevra les fonds.' using errcode = 'P0001';
  end if;
  solde := public.solde_boutique(cible);
  if coalesce(montant, 0) <= 0 then
    raise exception 'Indiquez le montant à reverser.' using errcode = 'P0001';
  end if;
  if montant > (solde ->> 'disponible')::bigint then
    raise exception 'Le solde disponible est de % : vous ne pouvez pas demander plus.',
      public.montant_lisible((solde ->> 'disponible')::bigint, solde ->> 'devise') using errcode = 'P0001';
  end if;
  insert into public.reversements (boutique_id, montant, tel, reseau, titulaire, demande_par)
  values (cible, montant, r.tel, r.reseau, r.titulaire, qui)
  returning id into nouv;
  perform public.notifier(public.les_superadmins(), 'reversement_demande',
    'Reversement demandé : ' || public.montant_lisible(montant, solde ->> 'devise'),
    coalesce((select b.nom from public.boutiques b where b.id = cible), cible) || ' — à envoyer sur ' ||
      r.reseau || ' ' || r.tel || coalesce(' (' || nullif(r.titulaire, '') || ')', '') || '. Demandé par ' || qui || '.',
    '#/reversements', null, cible, true);
  return nouv;
end $$;
revoke all on function public.demander_reversement(text, bigint) from public, anon;
grant execute on function public.demander_reversement(text, bigint) to authenticated;

-- La liste : la boutique, les siens ; le superadministrateur, tous
-- (« cible » vide) ou ceux d'une boutique.
create or replace function public.reversements_liste(cible text default null)
returns table (id bigint, boutique_id text, nom_boutique text, montant bigint, tel text, reseau text,
               titulaire text, etat text, demande_par text, demande_le timestamptz, decide_par text,
               decide_le timestamptz, reference text, motif text, devise text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.est_super() or (cible is not null and public.tient_la_caisse(cible))) then
    return;
  end if;
  return query
    select v.id, v.boutique_id, coalesce(b.nom, '')::text, v.montant, v.tel, v.reseau, v.titulaire, v.etat,
           v.demande_par, v.demande_le, v.decide_par, v.decide_le, v.reference, v.motif,
           coalesce(nullif(b.devise, ''), 'FCFA')::text
      from public.reversements v left join public.boutiques b on b.id = v.boutique_id
     where cible is null or v.boutique_id = cible
     order by (v.etat = 'en_attente') desc, v.demande_le desc
     limit 200;
end $$;
revoke all on function public.reversements_liste(text) from public, anon;
grant execute on function public.reversements_liste(text) to authenticated;

-- LE SUPERADMINISTRATEUR TRANCHE. Validé : il a envoyé l'argent, et note
-- la référence de la transaction. Refusé : avec un motif ; le montant
-- revient au solde disponible.
create or replace function public.decider_reversement(cible bigint, accord boolean,
  reference text default '', motif text default '')
returns text
language plpgsql security definer set search_path = public as $$
declare
  v   public.reversements%rowtype;
  ref text := left(trim(coalesce(reference, '')), 60);
  pourquoi text := left(trim(coalesce(motif, '')), 300);
  dev text;
begin
  if not public.est_super() then
    raise exception 'Seul le superadministrateur valide un reversement.';
  end if;
  select * into v from public.reversements where id = cible for update;
  if not found then raise exception 'Demande introuvable.'; end if;
  if v.etat <> 'en_attente' then
    raise exception 'Cette demande est déjà tranchée.' using errcode = 'P0001';
  end if;
  if accord and length(ref) < 4 then
    raise exception 'Notez la référence de la transaction envoyée.' using errcode = 'P0001';
  end if;
  update public.reversements
     set etat = case when accord then 'valide' else 'refuse' end,
         decide_par = public.nom_du_compte(), decide_le = now(),
         reference = case when accord then ref else '' end, motif = pourquoi
   where id = cible;
  dev := coalesce((select nullif(b.devise, '') from public.boutiques b where b.id = v.boutique_id), 'FCFA');
  perform public.notifier(
    array(select p.id from public.profils p
           where p.actif and p.boutique_id = v.boutique_id and p.role = 'administrateur'),
    'reversement_decide',
    case when accord then 'Reversement envoyé : ' || public.montant_lisible(v.montant, dev)
         else 'Reversement refusé : ' || public.montant_lisible(v.montant, dev) end,
    case when accord then 'Envoyé sur ' || v.reseau || ' ' || v.tel || ' — référence ' || ref || '.'
         else 'BIZZOO a refusé la demande' || coalesce(' : « ' || nullif(pourquoi, '') || ' »', '') ||
              '. Le montant revient à votre solde.' end,
    '#/solde', null, v.boutique_id, true);
  return case when accord then 'valide' else 'refuse' end;
end $$;
revoke all on function public.decider_reversement(bigint, boolean, text, text) from public, anon;
grant execute on function public.decider_reversement(bigint, boolean, text, text) to authenticated;

