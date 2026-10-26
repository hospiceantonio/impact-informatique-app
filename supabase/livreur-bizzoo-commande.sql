-- ---------- Le socle de la livraison au kilomètre (3.64.0) ----------
-- Répété dans chaque fichier qui s'en sert : collé seul, il doit se suffire.
-- Les colonnes de la livraison au kilomètre (3.64.0).
alter table public.produits add column if not exists vehicule text not null default 'moto';
alter table public.produits drop constraint if exists produits_vehicule;
alter table public.produits add constraint produits_vehicule check (vehicule in ('moto', 'tricycle'));
alter table public.profils add column if not exists vehicule text not null default 'moto';
alter table public.profils drop constraint if exists profils_vehicule;
alter table public.profils add constraint profils_vehicule check (vehicule in ('moto', 'tricycle'));
alter table public.commandes add column if not exists livraison jsonb;
alter table public.paiement add column if not exists livraison_latitude double precision;
alter table public.paiement add column if not exists livraison_longitude double precision;
alter table public.paiement add column if not exists livraison_adresse text not null default '';
alter table public.paiement add column if not exists livraison_rayon_km int not null default 10;
alter table public.paiement add column if not exists livraison_coef numeric(4,2) not null default 1.3;
alter table public.paiement add column if not exists moto_forfait int not null default 1000;
alter table public.paiement add column if not exists moto_prix_km int not null default 100;
alter table public.paiement add column if not exists tricycle_forfait int not null default 4000;
alter table public.paiement add column if not exists tricycle_prix_km int not null default 500;
alter table public.paiement add column if not exists taux_livreur int not null default 80;
alter table public.paiement drop constraint if exists paiement_livraison_bornes;
alter table public.paiement add constraint paiement_livraison_bornes check (
  (livraison_latitude is null) = (livraison_longitude is null)
  and (livraison_latitude is null or livraison_latitude between -90 and 90)
  and (livraison_longitude is null or livraison_longitude between -180 and 180)
  and livraison_rayon_km between 0 and 500
  and livraison_coef between 1 and 3
  and moto_forfait between 0 and 1000000 and moto_prix_km between 0 and 100000
  and tricycle_forfait between 0 and 1000000 and tricycle_prix_km between 0 and 100000
  and taux_livreur between 0 and 100
  and length(livraison_adresse) <= 200);

create table if not exists public.gains_livreurs (
  commande_id text primary key references public.commandes(id) on delete cascade,
  livreur_id  uuid references public.profils(id) on delete set null,
  frais       bigint not null default 0,
  taux        int not null default 80,
  montant     bigint not null default 0 check (montant >= 0),
  credite_le  timestamptz not null default now()
);
create index if not exists gains_livreur on public.gains_livreurs(livreur_id, credite_le desc);
alter table public.gains_livreurs enable row level security;
revoke all on public.gains_livreurs from anon, authenticated;
-- (3.66.0) UNE LIGNE PAR LIVREUR, et non plus par commande : une commande à
-- l'ancien tarif (frais par boutique) a parfois un livreur par boutique,
-- et chacun touche la part des boutiques qu'il a livrées.
alter table public.gains_livreurs add column if not exists id bigserial;
do $$
begin
  if exists (select 1 from pg_constraint
              where conname = 'gains_livreurs_pkey' and conrelid = 'public.gains_livreurs'::regclass
                and pg_get_constraintdef(oid) = 'PRIMARY KEY (commande_id)') then
    alter table public.gains_livreurs drop constraint gains_livreurs_pkey;
    alter table public.gains_livreurs add constraint gains_livreurs_pkey primary key (id);
  end if;
end $$;
create unique index if not exists gains_livreurs_une_fois on public.gains_livreurs(commande_id, livreur_id);
revoke all on sequence public.gains_livreurs_id_seq from anon, authenticated;

create or replace function public.livraison_active() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.livraison_latitude is not null and p.livraison_longitude is not null
                     from public.paiement p where p.id = 1), false);
$$;
revoke all on function public.livraison_active() from public;
grant execute on function public.livraison_active() to anon, authenticated;

create or replace function public.devis_livraison(
  latitude double precision, longitude double precision, vehicule text default 'moto')
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r     public.paiement%rowtype;
  v     text := case when vehicule = 'tricycle' then 'tricycle' else 'moto' end;
  dlat  double precision;
  dlng  double precision;
  a     double precision;
  dist  numeric;
  km    int;
  forf  int;
  prix  int;
begin
  select * into r from public.paiement where id = 1;
  if not found or r.livraison_latitude is null or r.livraison_longitude is null then
    return null;
  end if;
  if latitude is null or longitude is null
     or latitude not between -90 and 90 or longitude not between -180 and 180
     or (latitude = 0 and longitude = 0) then
    raise exception 'Position de livraison invalide : touchez « Utiliser ma position ».'
      using errcode = 'P0001';
  end if;
  -- À vol d'oiseau (formule de haversine, rayon terrestre de 6 371 km),
  -- multipliée par le coefficient de la route ; au mètre près.
  dlat := radians(latitude - r.livraison_latitude);
  dlng := radians(longitude - r.livraison_longitude);
  a := sin(dlat / 2) ^ 2
       + cos(radians(r.livraison_latitude)) * cos(radians(latitude)) * sin(dlng / 2) ^ 2;
  dist := round((2 * 6371 * asin(least(1, sqrt(a))) * r.livraison_coef)::numeric, 3);
  -- Le kilomètre ENTAMÉ compte : 10,001 km facturent un kilomètre de plus.
  km := case when dist > r.livraison_rayon_km then ceil(dist - r.livraison_rayon_km)::int else 0 end;
  forf := case when v = 'tricycle' then r.tricycle_forfait else r.moto_forfait end;
  prix := case when v = 'tricycle' then r.tricycle_prix_km else r.moto_prix_km end;
  return jsonb_build_object(
    'vehicule', v,
    'distance_km', round(dist, 1),
    'rayon_km', r.livraison_rayon_km,
    'km_factures', km,
    'forfait', forf,
    'prix_km', prix,
    'frais', forf + km * prix,
    'point', jsonb_build_object('latitude', r.livraison_latitude, 'longitude', r.livraison_longitude),
    'destination', jsonb_build_object('latitude', round(latitude::numeric, 6),
                                      'longitude', round(longitude::numeric, 6)));
end $$;
revoke all on function public.devis_livraison(double precision, double precision, text) from public;
grant execute on function public.devis_livraison(double precision, double precision, text) to anon, authenticated;

create or replace function public.part_frais_livreur(cible text, qui uuid) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare
  c          public.commandes%rowtype;
  f          numeric;
  siennes    int;
  confiees   int;
  part       numeric;
  brut_moi   numeric;
  brut_tout  numeric;
begin
  select * into c from public.commandes where id = cible;
  if not found then return 0; end if;
  f := greatest(0, coalesce(c.frais_livraison, 0));
  if f <= 0 then return 0; end if;
  select count(*) filter (where l.livreur_id = qui), count(*) filter (where l.livreur_id is not null)
    into siennes, confiees
    from public.commande_lignes l where l.commande_id = cible and l.etat <> 'annulee';
  if coalesce(siennes, 0) = 0 then
    return case when coalesce(confiees, 0) = 0 then f else 0 end;
  end if;
  if c.livraison is not null then return f; end if;
  if c.parts is not null and exists (select 1 from jsonb_each(c.parts) e(k, v)
                                      where coalesce((v ->> 'frais')::numeric, 0) > 0) then
    select coalesce(sum(coalesce((c.parts -> b.bou ->> 'frais')::numeric, 0)), 0) into part
      from (select distinct l.boutique_id as bou from public.commande_lignes l
             where l.commande_id = cible and l.livreur_id = qui and l.etat <> 'annulee') b;
    return least(f, part);
  end if;
  select coalesce(sum(l.prix * l.quantite) filter (where l.livreur_id = qui), 0),
         coalesce(sum(l.prix * l.quantite), 0)
    into brut_moi, brut_tout
    from public.commande_lignes l where l.commande_id = cible and l.etat <> 'annulee';
  if brut_tout <= 0 then return 0; end if;
  return round(f * brut_moi / brut_tout);
end $$;
revoke all on function public.part_frais_livreur(text, uuid) from public, anon, authenticated;

create or replace function public.gain_livreur(cible text) returns bigint
language plpgsql stable security definer set search_path = public as $$
declare g bigint; p numeric; t int;
begin
  select sum(x.montant)::bigint into g from public.gains_livreurs x
   where x.commande_id = cible and x.livreur_id = auth.uid();
  if g is not null then return g; end if;
  p := public.part_frais_livreur(cible, auth.uid());
  if coalesce(p, 0) <= 0 then return null; end if;
  select coalesce(x.taux_livreur, 80) into t from public.paiement x where x.id = 1;
  return floor(p * coalesce(t, 80) / 100.0)::bigint;
end $$;
revoke all on function public.gain_livreur(text) from public, anon, authenticated;


-- =========================================================
-- BIZZOO 3.59.0 — Le livreur de BIZZOO porte toute la commande
--
--   1. confiée à un livreur de BIZZOO, la course lui donne TOUS les
--      produits de la commande — ceux des autres boutiques aussi, sauf
--      une part déjà confiée au livreur d'une autre boutique ; les autres
--      boutiques sont prévenues qu'il passe chez elles ;
--   2. il accepte d'un seul « Commande reçue » toute la commande ; le
--      client reçoit une seule nouvelle ;
--   3. confiée au livreur d'une boutique : les produits de CETTE
--      boutique seulement, comme avant.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- À coller APRÈS refus-course.sql.
-- =========================================================

-- ---------- Confier une livraison ----------
-- LA BOUTIQUE CONFIE, à SON livreur ou à CELUI DE BIZZOO. Confier à
-- celui de la boutique d'à côté reste refusé : ce serait lui remettre
-- le nom, le numéro et l'adresse d'un client qui n'est pas le sien.
-- Un livreur de BIZZOO, lui, porte pour toute l'enseigne — c'est
-- exactement ce qu'on a voulu en ne le rattachant à aucune boutique.
--
-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;



create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;


create or replace function public.equipe_de(cible text) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and cible is not null and p.boutique_id = cible
     and p.role in ('administrateur', 'moderateur');
$$;


create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false)
     and public.role_courant() is not null;
$$;


create or replace function public.est_livreur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'livreur', false);
$$;


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

create or replace function public.peut_agir_sur(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.est_compte_enseigne()
      or (public.est_equipe() and cible is not null
          and cible = public.boutique_du_compte());
$$;


-- (BIZZOO Personnel) Le livreur bloqué : lu par la fonction qui suit.
alter table public.profils add column if not exists courses_bloquees boolean not null default false;

-- (3.59.0) LE LIVREUR DE BIZZOO PORTE TOUTE LA COMMANDE : confié par une
-- boutique, il reçoit aussi les produits des autres boutiques de la
-- commande — ceux qu'aucun autre livreur ne porte déjà. Le livreur d'une
-- boutique, lui, ne reçoit que les produits de SA boutique.
create or replace function public.assigner_livreur(
  commande text, boutique text, livreur uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  combien  int;
  autres   int := 0;
  rang     text;
  bizzoo   boolean := false;
  numero   text;
  b        record;
  son_vehicule text;
  besoin   text;
  plusieurs boolean;
  au_km    boolean;
  bloque   boolean;
begin
  if not public.peut_agir_sur(boutique) then
    raise exception 'Cette commande ne concerne pas votre boutique';
  end if;
  -- (3.64.0) UN SEUL LIVREUR PAR COMMANDE AU KILOMÈTRE. Une telle
  -- commande de plusieurs boutiques se confie à un livreur de BIZZOO, qui
  -- les livre toutes ; et une commande en tricycle, à un livreur en
  -- tricycle. Les commandes d'avant (frais par boutique) gardent leur
  -- règle : un livreur par boutique.
  select c.livraison ->> 'vehicule', c.livraison is not null into besoin, au_km
    from public.commandes c where c.id = commande;
  au_km := coalesce(au_km, false);
  select au_km and count(distinct l.boutique_id) > 1 into plusieurs
    from public.commande_lignes l where l.commande_id = commande and l.etat <> 'annulee';

  -- « livreur » nul : on retire l'attribution. Une boutique doit pouvoir
  -- reprendre une course confiée par erreur.
  if livreur is not null then
    select p.role, (p.boutique_id is null), p.vehicule, p.courses_bloquees
      into rang, bizzoo, son_vehicule, bloque from public.profils p
     where p.id = livreur and p.actif
       and (public.est_super()
            or public.est_compte_enseigne()
            -- Le livreur de BIZZOO : aucune boutique, donc toutes.
            or p.boutique_id is null
            or p.boutique_id = public.boutique_du_compte());
    if rang is distinct from 'livreur' then
      raise exception 'Ce compte n''est pas un livreur de votre boutique ni de BIZZOO';
    end if;
    -- Bloqué par l'administration de BIZZOO : plus aucune course.
    if bloque then
      raise exception 'Ce livreur est bloqué par BIZZOO : il ne reçoit plus de course. Confiez-la à un autre.'
        using errcode = 'P0001';
    end if;
    if coalesce(plusieurs, false) and not coalesce(bizzoo, false) then
      raise exception 'Cette commande traverse plusieurs boutiques : confiez-la à un livreur de BIZZOO, qui les livre toutes.'
        using errcode = 'P0001';
    end if;
    if besoin = 'tricycle' and son_vehicule is distinct from 'tricycle' then
      raise exception 'Cette commande se livre en tricycle : confiez-la à un livreur en tricycle.'
        using errcode = 'P0001';
    end if;
    -- UN LIVREUR VALIDE SON COMPTE EN ENREGISTRANT SA POSITION. Tant
    -- qu'il ne l'a pas fait, on ne lui confie rien.
    if not exists (select 1 from public.positions_livreurs pl where pl.profil_id = livreur) then
      raise exception 'Ce livreur n''a pas encore validé son compte : il doit ouvrir BIZZOO Admin et enregistrer sa position.'
        using errcode = 'P0001';
    end if;
  end if;

  perform set_config('bizzoo.livraison', 'oui', true);
  update public.commande_lignes l
     set livreur_id = livreur,
         -- Un autre livreur doit accepter à son tour (3.59.0).
         recu_le = case when l.livreur_id is distinct from livreur then null else l.recu_le end
   where l.commande_id = commande
     -- (3.64.0) Au kilomètre, retirer le livreur le retire de toute la
     -- commande : une course, c'est la commande entière.
     and (l.boutique_id = boutique or (livreur is null and au_km))
     -- (3.59.0) En secours de la demande envoyée à tous les livreurs : la
     -- boutique peut confier dès le paiement, sans attendre le colis.
     and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')
     and exists (select 1 from public.commandes c where c.id = l.commande_id and c.etat = 'payee');
  get diagnostics combien = row_count;

  -- LE LIVREUR DE BIZZOO : les produits des autres boutiques aussi. Sans
  -- prendre une part déjà confiée au livreur d'une autre boutique —
  -- (3.64.0) sauf au kilomètre : un seul livreur par commande, il les
  -- prend toutes.
  if bizzoo and combien > 0 then
    update public.commande_lignes l
       set livreur_id = livreur, recu_le = null
     where l.commande_id = commande
       and l.boutique_id <> boutique
       and (l.livreur_id is null or (au_km and l.livreur_id is distinct from livreur))
       and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison');
    get diagnostics autres = row_count;
  end if;
  perform set_config('bizzoo.livraison', '', true);

  if combien = 0 then
    raise exception 'Rien à confier ici : la commande n''est pas encore payée, ou elle est déjà livrée.';
  end if;

  -- Les autres boutiques le savent : un livreur BIZZOO passera chez elles.
  if autres > 0 then
    select c.numero into numero from public.commandes c where c.id = commande;
    for b in select distinct l.boutique_id as id from public.commande_lignes l
              where l.commande_id = commande and l.boutique_id <> boutique and l.livreur_id = livreur
    loop
      perform public.notifier(public.equipe_de(b.id), 'course_confiee',
        'Un livreur BIZZOO passe récupérer vos produits',
        'Commande ' || coalesce(numero, '') || ' — il livre toute la commande. Préparez le colis.',
        '#/commandes/' || commande, commande, b.id, true);
    end loop;
  end if;
  return combien + autres;
end $$;
revoke all on function public.assigner_livreur(text, text, uuid) from public, anon;
grant execute on function public.assigner_livreur(text, text, uuid) to authenticated;

-- ---------- « Reçu » : le livreur accepte la course (3.59.0) ----------
-- Le client est alors prévenu, avec le nom et le numéro de son livreur ;
-- la boutique aussi. Seulement SES courses, et une seule fois.
-- Le livreur de BIZZOO accepte d'un coup TOUTE la commande qu'il porte :
-- une seule nouvelle au client.
create or replace function public.accepter_course(commande text, boutique text)
returns int
language plpgsql security definer set search_path = public as $$
declare
  moi     uuid := auth.uid();
  combien int;
  bizzoo  boolean;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Cette course ne vous est pas confiée';
  end if;
  select (p.boutique_id is null) into bizzoo from public.profils p where p.id = moi;
  perform set_config('bizzoo.livraison', 'oui', true);
  if coalesce(bizzoo, false) then
    perform set_config('bizzoo.prise', 'oui', true);
  end if;
  update public.commande_lignes l
     set recu_le = now()
   where l.commande_id = commande
     and (l.boutique_id = boutique or coalesce(bizzoo, false))
     and l.livreur_id = moi
     and l.recu_le is null
     -- (3.59.0) Dès le paiement : la course s'accepte avant que le colis
     -- soit prêt.
     and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison');
  get diagnostics combien = row_count;
  perform set_config('bizzoo.livraison', '', true);
  perform set_config('bizzoo.prise', '', true);
  if combien = 0 and not exists (
       select 1 from public.commande_lignes l
        where l.commande_id = commande and l.boutique_id = boutique
          and l.livreur_id = moi and l.recu_le is not null) then
    raise exception 'Cette course ne vous est pas confiée';
  end if;
  return combien;
end $$;
revoke all on function public.accepter_course(text, text) from public, anon;
grant execute on function public.accepter_course(text, text) to authenticated;
