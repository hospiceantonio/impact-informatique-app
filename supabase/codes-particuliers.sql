-- =========================================================
-- BIZZOO — les codes promo des particuliers
--
-- Le superadministrateur crée, pour une personne, un compte client et
-- un code promo à son nom : le client qui l'utilise a une remise, et la
-- personne touche un pourcentage de la commande, crédité à la LIVRAISON.
-- Elle voit son solde dans l'application client et demande un retrait
-- vers son numéro Mobile Money ; BIZZOO verse, puis marque « payé ».
--
-- Remplace « remise_du_code » (le propriétaire ne peut pas utiliser son
-- propre code) et ajoute deux tables : gains_parrain, retraits_parrain.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
-- Sans danger : relançable.
-- =========================================================

alter table public.clients add column if not exists revendeur_etat text not null default 'aucune';

create or replace function public.code_normalise(brut text) returns text
language sql immutable as $$
  select left(regexp_replace(upper(coalesce(brut, '')), '[^A-Z0-9]', '', 'g'), 24);
$$;

-- Le code d'un particulier : à qui il appartient, et ce qu'il lui rapporte.
alter table public.codes_promo add column if not exists parrain uuid;
alter table public.codes_promo add column if not exists commission numeric(5,2) not null default 0;

create or replace function public.remise_du_code(
  brut text, sous_total bigint, marge bigint,
  qui uuid default null, tel text default '')
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c       public.codes_promo%rowtype;
  cle     text := public.code_normalise(brut);
  brute   bigint;
  plafond bigint := greatest(0, coalesce(marge, 0));
  combien int;
  -- PAS « numero » : « commandes » a une colonne de ce nom, et
  -- PostgreSQL refuserait la requête plus bas — « column reference
  -- numero is ambiguous ».
  tel_net text := left(regexp_replace(coalesce(tel, ''), '\D', '', 'g'), 20);
  refus   constant text := 'Ce code n''existe pas, ou n''est plus valable.';
begin
  if cle = '' then
    return jsonb_build_object('ok', false, 'remise', 0, 'raison', refus);
  end if;
  -- UN REVENDEUR A DÉJÀ SA REMISE : il achète au prix BIZZOO, sur tout le
  -- catalogue. Un code s'y ajouterait, et sortirait une seconde fois de
  -- la même marge. La caisse passe alors la commande sans le code.
  if qui is not null and exists (select 1 from public.clients r
                                 where r.id = qui and r.revendeur_etat = 'validee') then
    return jsonb_build_object('ok', false, 'remise', 0,
      'raison', 'Votre compte revendeur achète déjà au prix BIZZOO : les codes promo ne s''y ajoutent pas.');
  end if;
  select * into c from public.codes_promo where code = cle;
  -- MÊME RÉPONSE pour « inconnu » et « fermé ». Distinguer les deux
  -- dirait à qui essaie des codes au hasard lesquels ont existé.
  if not found or not c.actif then
    return jsonb_build_object('ok', false, 'remise', 0, 'raison', refus);
  end if;
  if c.fin is not null and c.fin < current_date then
    return jsonb_build_object('ok', false, 'remise', 0,
      'raison', 'Ce code a expiré le ' || to_char(c.fin, 'DD/MM/YYYY') || '.');
  end if;
  if coalesce(sous_total, 0) < c.minimum then
    return jsonb_build_object('ok', false, 'remise', 0,
      'raison', 'Ce code s''applique à partir de ' || c.minimum::text || '.');
  end if;

  -- LES UTILISATIONS SE COMPTENT SUR LES COMMANDES PAYÉES. Compter les
  -- paniers déposés laisserait des commandes jamais réglées manger le
  -- quota, et refuserait le code à de vrais clients. Le risque inverse
  -- — quelques remises de plus si beaucoup paient en même temps — coûte
  -- bien moins cher qu'un client refusé à tort.
  if c.maximum > 0 then
    select count(*) into combien from public.commandes o
     where o.code_promo = cle and o.etat = 'payee';
    if combien >= c.maximum then
      return jsonb_build_object('ok', false, 'remise', 0,
        'raison', 'Ce code a atteint son nombre d''utilisations.');
    end if;
  end if;

  -- LE PROPRIÉTAIRE D'UN CODE NE S'EN SERT PAS : il toucherait une
  -- commission sur ses propres achats.
  if c.parrain is not null and qui is not null and qui = c.parrain then
    return jsonb_build_object('ok', false, 'remise', 0,
      'raison', 'C''est votre code : il sert à vos clients, pas à vous.');
  end if;

  -- « Une seule fois par client ». Un compte se reconnaît à son
  -- identifiant ; un visiteur sans compte, à son seul numéro — on le dit
  -- franchement plutôt que de laisser croire à une identification qui
  -- n'existe pas.
  if c.une_par_client and (qui is not null or tel_net <> '') then
    if exists (select 1 from public.commandes o
                where o.code_promo = cle and o.etat = 'payee'
                  and ((qui is not null and o.client_id = qui)
                       or (tel_net <> '' and o.client_tel = tel_net))) then
      return jsonb_build_object('ok', false, 'remise', 0,
        'raison', 'Vous avez déjà utilisé ce code.');
    end if;
  end if;

  brute := case when c.mode = 'montant' then round(c.valeur)::bigint
                else round(coalesce(sous_total, 0) * least(100, greatest(0, c.valeur)) / 100)::bigint end;
  brute := greatest(0, least(brute, greatest(0, coalesce(sous_total, 0))));

  -- LE PLAFOND. La boutique touche son prix BIZZOO en entier : la
  -- remise ne peut pas dépasser ce que l'enseigne gagne sur cette
  -- commande. On rabote sans rien dire de plus que le montant obtenu —
  -- la marge de l'enseigne ne regarde pas le client.
  if brute > plafond then brute := plafond; end if;

  -- UN CODE DE PARTICULIER VAUT MÊME SANS REMISE : il porte la commission
  -- de son propriétaire, et la commande doit le garder.
  if brute <= 0 and c.parrain is null then
    return jsonb_build_object('ok', false, 'remise', 0,
      'raison', 'Ce code ne s''applique pas à ce panier.');
  end if;
  return jsonb_build_object('ok', true, 'remise', brute, 'raison', '');
end $$;
revoke all on function public.remise_du_code(text, bigint, bigint, uuid, text)
  from public, anon, authenticated;

-- =========================================================
-- Les codes des particuliers : une commission sur chaque vente
-- =========================================================
-- Un particulier reçoit un code. Le client qui le tape a sa remise ;
-- le propriétaire touche un pourcentage de la commande sur son compte
-- BIZZOO, qu'il voit dans l'application client et qu'il retire vers son
-- numéro Mobile Money.
--
-- QUAND : à la LIVRAISON. La commission naît quand toutes les parts de
-- la commande sont remises au client (les parts annulées ne comptent
-- pas). Une commande annulée, ou jamais livrée, ne rapporte rien : il n'y
-- a jamais de commission à reprendre.
--
-- COMBIEN : le taux du code, sur ce que le client a payé pour sa
-- commande (remise déduite). PLAFONNÉ par ce que l'enseigne gagne encore
-- sur la commande après la remise : la boutique touche son prix BIZZOO en
-- entier, et une commission ne fait jamais vendre à perte.
--
-- UNE FOIS : une commission par commande, au plus — la base le garantit
-- par une contrainte, pas par une précaution de l'application.
--
-- LES RETRAITS : le propriétaire DEMANDE ; le superadministrateur verse
-- sur le numéro Mobile Money, puis marque « payé ». Pendant la demande,
-- le montant n'est plus disponible : on ne retire pas deux fois la même
-- somme.

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

alter table public.codes_promo add column if not exists parrain uuid;
alter table public.codes_promo add column if not exists commission numeric(5,2) not null default 0;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'codes_promo_commission_borne') then
    alter table public.codes_promo
      add constraint codes_promo_commission_borne check (commission between 0 and 50);
  end if;
end $$;
create index if not exists codes_promo_parrain on public.codes_promo(parrain) where parrain is not null;

create table if not exists public.gains_parrain (
  id          bigserial primary key,
  parrain     uuid not null,
  commande_id text unique,
  code        text not null default '',
  base        bigint not null default 0,
  taux        numeric(5,2) not null default 0,
  montant     bigint not null check (montant >= 0),
  cree_le     timestamptz not null default now()
);
create index if not exists gains_parrain_qui on public.gains_parrain(parrain, cree_le desc);

create table if not exists public.retraits_parrain (
  id          bigserial primary key,
  parrain     uuid not null,
  montant     bigint not null check (montant > 0),
  numero      text not null,
  reseau      text not null default '',
  etat        text not null default 'demande' check (etat in ('demande', 'payee', 'refusee')),
  demande_le  timestamptz not null default now(),
  traite_le   timestamptz,
  traite_par  uuid,
  reference   text not null default '',
  motif       text not null default ''
);
create index if not exists retraits_parrain_qui on public.retraits_parrain(parrain, demande_le desc);

-- Lecture : chacun les siennes, le superadministrateur toutes. AUCUNE
-- écriture directe : tout passe par les fonctions plus bas.
alter table public.gains_parrain enable row level security;
alter table public.retraits_parrain enable row level security;
drop policy if exists "gains lecture" on public.gains_parrain;
create policy "gains lecture" on public.gains_parrain
  for select using (parrain = auth.uid() or public.est_super());
drop policy if exists "retraits lecture" on public.retraits_parrain;
create policy "retraits lecture" on public.retraits_parrain
  for select using (parrain = auth.uid() or public.est_super());
revoke insert, update, delete on public.gains_parrain from anon, authenticated;
revoke insert, update, delete on public.retraits_parrain from anon, authenticated;
grant select on public.gains_parrain to authenticated;
grant select on public.retraits_parrain to authenticated;

-- ---------- Créditer, à la livraison ----------
create or replace function public.crediter_parrain(cible text) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  c        public.commandes%rowtype;
  k        public.codes_promo%rowtype;
  restant  int;
  livrees  int;
  marge    bigint;
  brut     bigint;
  montant  bigint;
begin
  select * into c from public.commandes where id = cible;
  if not found or c.etat <> 'payee' or coalesce(c.code_promo, '') = '' then return 0; end if;
  select * into k from public.codes_promo where code = c.code_promo;
  if not found or k.parrain is null or coalesce(k.commission, 0) <= 0 then return 0; end if;
  if exists (select 1 from public.gains_parrain g where g.commande_id = cible) then return 0; end if;

  select count(*) filter (where l.etat not in ('remise', 'annulee')),
         count(*) filter (where l.etat = 'remise'),
         coalesce(sum(greatest(0, l.prix - l.prix_bizzoo) * l.quantite)
                    filter (where l.etat <> 'annulee'), 0)
    into restant, livrees, marge
    from public.commande_lignes l where l.commande_id = cible;
  if restant > 0 or livrees = 0 then return 0; end if;

  brut := round(greatest(0, c.total) * least(50, greatest(0, k.commission)) / 100)::bigint;
  montant := least(brut, greatest(0, marge - coalesce(c.remise, 0)));
  if montant <= 0 then return 0; end if;

  insert into public.gains_parrain (parrain, commande_id, code, base, taux, montant)
  values (k.parrain, cible, k.code, greatest(0, c.total), k.commission, montant)
  on conflict (commande_id) do nothing;
  if not found then return 0; end if;

  perform public.notifier(array[k.parrain], 'commission',
    'Commission créditée',
    'La commande ' || c.numero || ' a été livrée : ' || montant::text ||
      ' FCFA sur votre solde.',
    '#/compte', null, null, true);
  return montant;
end $$;
revoke all on function public.crediter_parrain(text) from public, anon, authenticated;

create or replace function public.lignes_creditent_parrain() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.etat is distinct from old.etat and new.etat in ('remise', 'annulee') then
    -- Jamais d'échec ici : une commission manquée se rattrape, une
    -- livraison refusée à cause d'elle, non.
    begin
      perform public.crediter_parrain(new.commande_id);
    exception when others then
      raise warning 'commission non créditée pour % : %', new.commande_id, sqlerrm;
    end;
  end if;
  return new;
end $$;
drop trigger if exists lignes_creditent_parrain on public.commande_lignes;
create trigger lignes_creditent_parrain
  after update of etat on public.commande_lignes
  for each row execute function public.lignes_creditent_parrain();

-- ---------- Ce que le propriétaire voit ----------
create or replace function public.mon_solde_parrain() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  moi     uuid := auth.uid();
  gagne   bigint;
  retire  bigint;
  attente bigint;
begin
  if moi is null or not exists (select 1 from public.codes_promo where parrain = moi) then
    return null;
  end if;
  select coalesce(sum(montant), 0) into gagne from public.gains_parrain where parrain = moi;
  select coalesce(sum(montant) filter (where etat = 'payee'), 0),
         coalesce(sum(montant) filter (where etat = 'demande'), 0)
    into retire, attente
    from public.retraits_parrain where parrain = moi;
  return jsonb_build_object(
    'codes', (select coalesce(jsonb_agg(jsonb_build_object(
                'code', k.code, 'remise', k.valeur, 'mode', k.mode,
                'commission', k.commission, 'actif', k.actif) order by k.code), '[]'::jsonb)
                from public.codes_promo k where k.parrain = moi),
    'gagne', gagne, 'retire', retire, 'en_attente', attente,
    'solde', gagne - retire - attente,
    'gains', (select coalesce(jsonb_agg(jsonb_build_object(
                'numero', o.numero, 'montant', g.montant, 'taux', g.taux,
                'base', g.base, 'le', g.cree_le) order by g.cree_le desc), '[]'::jsonb)
                from (select * from public.gains_parrain where parrain = moi
                       order by cree_le desc limit 30) g
                left join public.commandes o on o.id = g.commande_id),
    'retraits', (select coalesce(jsonb_agg(jsonb_build_object(
                'id', r.id, 'montant', r.montant, 'numero', r.numero, 'reseau', r.reseau,
                'etat', r.etat, 'le', r.demande_le, 'traite_le', r.traite_le,
                'motif', r.motif) order by r.demande_le desc), '[]'::jsonb)
                from (select * from public.retraits_parrain where parrain = moi
                       order by demande_le desc limit 30) r));
end $$;
revoke all on function public.mon_solde_parrain() from public, anon;
grant execute on function public.mon_solde_parrain() to authenticated;

-- ---------- Demander un retrait ----------
create or replace function public.demander_retrait(montant bigint, numero text, reseau text default '')
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  moi     uuid := auth.uid();
  numero_net text := regexp_replace(coalesce(numero, ''), '\D', '', 'g');
  solde   bigint;
  nouveau bigint;
begin
  if moi is null or not exists (select 1 from public.codes_promo where parrain = moi) then
    raise exception 'Ce compte n''a pas de code promo.' using errcode = 'P0001';
  end if;
  if coalesce(montant, 0) < 500 then
    raise exception 'Un retrait est de 500 FCFA au moins.' using errcode = 'P0001';
  end if;
  if length(numero_net) < 8 then
    raise exception 'Indiquez le numéro Mobile Money qui recevra l''argent.' using errcode = 'P0001';
  end if;
  -- DEUX DEMANDES EN MÊME TEMPS ne retirent pas deux fois la même somme.
  perform pg_advisory_xact_lock(hashtext('retrait:' || moi::text));
  select (select coalesce(sum(g.montant), 0) from public.gains_parrain g where g.parrain = moi)
       - (select coalesce(sum(r.montant), 0) from public.retraits_parrain r
           where r.parrain = moi and r.etat in ('demande', 'payee'))
    into solde;
  if montant > solde then
    raise exception 'Votre solde disponible est de % FCFA.', solde using errcode = 'P0001';
  end if;
  insert into public.retraits_parrain (parrain, montant, numero, reseau)
  values (moi, montant, numero_net, upper(left(coalesce(reseau, ''), 20)))
  returning id into nouveau;
  perform public.notifier(
    array(select p.id from public.profils p where p.role = 'superadministrateur' and p.actif),
    'retrait_demande', 'Demande de retrait',
    montant::text || ' FCFA vers ' || numero_net || ' — code promo d''un particulier.',
    '#/codes', null, null, true);
  return nouveau;
end $$;
revoke all on function public.demander_retrait(bigint, text, text) from public, anon;
grant execute on function public.demander_retrait(bigint, text, text) to authenticated;

-- ---------- Côté superadministrateur ----------
-- Donner un code à un compte (créé juste avant, comme client).
create or replace function public.creer_code_parrain(
  compte uuid, le_code text, remise numeric, taux numeric, nom text default '')
returns text
language plpgsql security definer set search_path = public as $$
declare cle text := public.code_normalise(le_code);
begin
  if not public.est_super() then
    raise exception 'Réservé au superadministrateur.' using errcode = '42501';
  end if;
  if compte is null or not exists (select 1 from auth.users u where u.id = compte) then
    raise exception 'Ce compte n''existe pas.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.profils p where p.id = compte and p.role is not null
               and p.actif) then
    raise exception 'Un compte de l''équipe ne reçoit pas de code de particulier.' using errcode = 'P0001';
  end if;
  if length(cle) < 3 then
    raise exception 'Le code fait au moins 3 lettres ou chiffres.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.codes_promo where code = cle) then
    raise exception 'Le code % existe déjà.', cle using errcode = 'P0001';
  end if;
  if coalesce(taux, 0) <= 0 or taux > 50 then
    raise exception 'La commission va de 0,5 à 50 %%.' using errcode = 'P0001';
  end if;
  if coalesce(remise, 0) < 0 or remise > 50 then
    raise exception 'La remise du client va de 0 à 50 %%.' using errcode = 'P0001';
  end if;
  insert into public.codes_promo (code, libelle, mode, valeur, une_par_client, actif,
                                  parrain, commission, cree_par)
  values (cle, coalesce(nullif(trim(nom), ''), 'Code de particulier'), 'pourcent',
          coalesce(remise, 0), false, true, compte, taux,
          coalesce((select email from public.profils where id = auth.uid()), ''));
  return cle;
end $$;
revoke all on function public.creer_code_parrain(uuid, text, numeric, numeric, text) from public, anon;
grant execute on function public.creer_code_parrain(uuid, text, numeric, numeric, text) to authenticated;

create or replace function public.parrains_liste()
returns table (code text, libelle text, parrain uuid, email text, remise numeric,
               commission numeric, actif boolean, ventes int, gagne bigint,
               retire bigint, en_attente bigint, solde bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.est_super() then return; end if;
  return query
    select k.code, k.libelle, k.parrain, coalesce(u.email, '')::text, k.valeur, k.commission, k.actif,
           (select count(*)::int from public.gains_parrain g where g.code = k.code),
           coalesce((select sum(g.montant) from public.gains_parrain g where g.parrain = k.parrain), 0)::bigint,
           coalesce((select sum(r.montant) from public.retraits_parrain r
                      where r.parrain = k.parrain and r.etat = 'payee'), 0)::bigint,
           coalesce((select sum(r.montant) from public.retraits_parrain r
                      where r.parrain = k.parrain and r.etat = 'demande'), 0)::bigint,
           (coalesce((select sum(g.montant) from public.gains_parrain g where g.parrain = k.parrain), 0)
            - coalesce((select sum(r.montant) from public.retraits_parrain r
                         where r.parrain = k.parrain and r.etat in ('demande', 'payee')), 0))::bigint
      from public.codes_promo k
      left join auth.users u on u.id = k.parrain
     where k.parrain is not null
     order by k.code;
end $$;
revoke all on function public.parrains_liste() from public, anon;
grant execute on function public.parrains_liste() to authenticated;

create or replace function public.retraits_a_traiter()
returns table (id bigint, code text, email text, montant bigint, numero text, reseau text,
               etat text, demande_le timestamptz, traite_le timestamptz, reference text, motif text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.est_super() then return; end if;
  return query
    select r.id,
           coalesce((select string_agg(k.code, ', ') from public.codes_promo k
                      where k.parrain = r.parrain), '')::text,
           coalesce(u.email, '')::text, r.montant, r.numero, r.reseau, r.etat,
           r.demande_le, r.traite_le, r.reference, r.motif
      from public.retraits_parrain r
      left join auth.users u on u.id = r.parrain
     order by (r.etat = 'demande') desc, r.demande_le desc
     limit 100;
end $$;
revoke all on function public.retraits_a_traiter() from public, anon;
grant execute on function public.retraits_a_traiter() to authenticated;

create or replace function public.traiter_retrait(cible bigint, payee boolean,
  la_reference text default '', le_motif text default '')
returns text
language plpgsql security definer set search_path = public as $$
declare r public.retraits_parrain%rowtype;
begin
  if not public.est_super() then
    raise exception 'Réservé au superadministrateur.' using errcode = '42501';
  end if;
  select * into r from public.retraits_parrain where id = cible for update;
  if not found then raise exception 'Demande introuvable.' using errcode = 'P0001'; end if;
  if r.etat <> 'demande' then
    raise exception 'Cette demande est déjà traitée.' using errcode = 'P0001';
  end if;
  update public.retraits_parrain
     set etat = case when payee then 'payee' else 'refusee' end,
         traite_le = now(), traite_par = auth.uid(),
         reference = left(coalesce(la_reference, ''), 80),
         motif = left(coalesce(le_motif, ''), 300)
   where id = cible;
  perform public.notifier(array[r.parrain], 'retrait',
    case when payee then 'Retrait versé' else 'Retrait refusé' end,
    case when payee
      then r.montant::text || ' FCFA ont été envoyés au ' || r.numero || '.'
      else 'Votre demande de ' || r.montant::text || ' FCFA n''a pas été versée'
           || coalesce(' : ' || nullif(le_motif, ''), '.') end,
    '#/compte', null, null, true);
  return case when payee then 'payee' else 'refusee' end;
end $$;
revoke all on function public.traiter_retrait(bigint, boolean, text, text) from public, anon;
grant execute on function public.traiter_retrait(bigint, boolean, text, text) to authenticated;
