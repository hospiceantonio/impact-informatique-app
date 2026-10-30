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

-- (3.70.0) Le devis plus bas lit la distance par la route : la grille
-- et le cache qu'il emprunte, recopiés tels quels.
create or replace function public.grille_route(x double precision) returns numeric
language sql immutable as $$
  select (round((x * 2000)::numeric) / 2000)::numeric(9,4);
$$;

create table if not exists public.distances_route (
  o_lat      numeric(9,4) not null,
  o_lng      numeric(9,4) not null,
  d_lat      numeric(9,4) not null,
  d_lng      numeric(9,4) not null,
  distance_m int not null check (distance_m > 0 and distance_m <= 1000000),
  cree_le    timestamptz not null default now(),
  primary key (o_lat, o_lng, d_lat, d_lng)
);
create index if not exists distances_route_jour on public.distances_route(cree_le);
alter table public.distances_route enable row level security;
revoke all on public.distances_route from public, anon, authenticated;

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
  route_m int;
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
  -- (3.70.0) PAR LA ROUTE, quand la fonction serveur « distance-route » l'a
  -- demandée à Google pour ce client (à 50 m près) : le vrai trajet.
  select x.distance_m into route_m from public.distances_route x
   where x.o_lat = public.grille_route(r.livraison_latitude)
     and x.o_lng = public.grille_route(r.livraison_longitude)
     and x.d_lat = public.grille_route(latitude)
     and x.d_lng = public.grille_route(longitude);
  if route_m is not null then
    dist := round(route_m / 1000.0, 3);
  else
    -- Sinon, à vol d'oiseau (formule de haversine, rayon terrestre de
    -- 6 371 km), multipliée par le coefficient de la route ; au mètre près.
    dlat := radians(latitude - r.livraison_latitude);
    dlng := radians(longitude - r.livraison_longitude);
    a := sin(dlat / 2) ^ 2
         + cos(radians(r.livraison_latitude)) * cos(radians(latitude)) * sin(dlng / 2) ^ 2;
    dist := round((2 * 6371 * asin(least(1, sqrt(a))) * r.livraison_coef)::numeric, 3);
  end if;
  -- Le kilomètre ENTAMÉ compte : 10,001 km facturent un kilomètre de plus.
  km := case when dist > r.livraison_rayon_km then ceil(dist - r.livraison_rayon_km)::int else 0 end;
  forf := case when v = 'tricycle' then r.tricycle_forfait else r.moto_forfait end;
  prix := case when v = 'tricycle' then r.tricycle_prix_km else r.moto_prix_km end;
  return jsonb_build_object(
    'vehicule', v,
    'distance_km', round(dist, 1),
    -- (3.70.0) « route » : le trajet réel (Google) ; « vol_oiseau » : estimé.
    'calcul', case when route_m is not null then 'route' else 'vol_oiseau' end,
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
-- BIZZOO 3.59.0 — Le reste payé à la livraison
--
-- Le client paie l'acompte en ligne, et le reste au livreur. Jusqu'ici
-- ce reste passait de main en main sans laisser de trace. Désormais :
--
--   1. le livreur déclare ce qu'il a encaissé (montant, espèces ou
--      Mobile Money) en remettant le colis : remettre_course ;
--   2. le client le voit sur son reçu, en reçoit la nouvelle, et peut le
--      contester : suivre_commande, contester_encaissement ;
--   3. la caisse des livreurs : la boutique voit ce que chaque livreur a
--      encaissé pour ses colis et marque « Argent reçu du livreur » ;
--      BIZZOO voit tout : caisse_livreurs, marquer_remis, ma_caisse.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- À coller APRÈS livraison-parcours.sql.
-- =========================================================

alter table public.commande_lignes add column if not exists recu_le timestamptz;
alter table public.commande_lignes add column if not exists livreur_id uuid;
alter table public.commandes add column if not exists parts jsonb;

-- ---------- Le reste payé à la livraison (3.59.0) ----------
--
-- AVANT, LE RESTE PASSAIT DE MAIN EN MAIN SANS LAISSER DE TRACE : le
-- livreur touchait « Je l'ai remise », et l'application supposait que le
-- client avait payé. Désormais :
--
--   1. le livreur DÉCLARE ce qu'il a encaissé, et comment (espèces ou
--      Mobile Money), en remettant le colis (remettre_course). Un montant
--      différent de ce qui était dû demande un motif écrit ;
--   2. le client le voit sur son reçu (« Reste payé à la livraison »), en
--      reçoit la nouvelle, et peut le contester (contester_encaissement) ;
--   3. LA CAISSE : la boutique voit ce que chaque livreur a encaissé pour
--      SES colis et ne lui a pas encore rendu, et marque « Argent reçu du
--      livreur » (marquer_remis). BIZZOO voit tout.
--
-- Une ligne par boutique et par commande : c'est la part de CETTE
-- boutique que son livreur réclame à la porte. Personne n'y écrit
-- directement — seulement par les fonctions ci-dessous.
create table if not exists public.encaissements (
  id             bigserial primary key,
  commande_id    text not null references public.commandes(id) on delete cascade,
  boutique_id    text not null references public.boutiques(id) on delete cascade,
  livreur_id     uuid references public.profils(id) on delete set null,
  -- Ce que le client devait à cette boutique à la livraison, et ce que
  -- le livreur dit avoir reçu.
  du             bigint not null default 0,
  montant        bigint not null default 0,
  mode           text not null default 'aucun',
  motif          text not null default '',
  encaisse_le    timestamptz not null default now(),
  -- L'argent rendu par le livreur à la boutique (ou à BIZZOO).
  remis_le       timestamptz,
  remis_par      uuid references public.profils(id) on delete set null,
  -- Le client conteste ce qui a été déclaré.
  conteste_le    timestamptz,
  conteste_motif text not null default '',
  constraint encaissements_un_par_part unique (commande_id, boutique_id),
  constraint encaissements_mode check (mode in ('especes', 'mobile_money', 'aucun')),
  constraint encaissements_montant check (montant >= 0 and du >= 0)
);
create index if not exists encaissements_livreur on public.encaissements(livreur_id) where remis_le is null;
create index if not exists encaissements_boutique on public.encaissements(boutique_id, encaisse_le desc);
alter table public.encaissements enable row level security;
revoke all on public.encaissements from anon, authenticated;
revoke all on sequence public.encaissements_id_seq from anon, authenticated;

-- Qui tient la caisse d'une boutique : le superadministrateur, un compte
-- de BIZZOO qui suit les commandes ou les finances, l'administrateur de
-- CETTE boutique. Un modérateur, non : c'est de l'argent.
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



create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
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


create or replace function public.est_livreur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'livreur', false);
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

create or replace function public.ma_commande(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.commandes c
     where c.id = cible
       and c.client_id is not null
       and c.client_id = auth.uid());
$$;
grant execute on function public.ma_commande(text) to authenticated;

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

create or replace function public.restes_par_boutique(cible text)
returns table (boutique_id text, a_encaisser bigint)
language plpgsql stable security definer set search_path = public as $$
declare lp jsonb;
begin
  select c.parts into lp from public.commandes c where c.id = cible;
  -- UNE COMMANDE D'AVANT LES CONDITIONS PAR BOUTIQUE (« parts » vide) :
  -- l'ancienne règle, celle d'un acompte unique réparti au prorata.
  if lp is null then
    return query
  with commande as (
    select c.total::numeric as total,
           greatest(0, coalesce(c.frais_livraison, 0))::numeric as frais,
           coalesce(c.verse, c.acompte, c.total)::numeric as deja
      from public.commandes c
     where c.id = cible
  ), parts as (
    select l.boutique_id as boutique,
           sum(l.prix * l.quantite)::numeric as brut,
           coalesce(sum(l.prix * l.quantite) filter (where l.etat <> 'annulee'), 0)::numeric as servi
      from public.commande_lignes l
     where l.commande_id = cible
     group by l.boutique_id
  ), reste as (
    -- Ce que vaut ce qui sera livré, remise déduite au prorata, moins ce
    -- qui est déjà versé.
    -- LES FRAIS DE LIVRAISON ne se réduisent pas au prorata : tant qu'il
    -- reste quelque chose à livrer, la course a lieu et coûte son prix.
    -- Tout annulé, il n'y a pas de course, donc pas de frais.
    select greatest(0, coalesce(round((c.total - c.frais) * sum(p.servi) / nullif(sum(p.brut), 0)), 0)
                       + case when sum(p.servi) > 0 then c.frais else 0 end
                       - c.deja) as du,
           sum(p.servi) as servi
      from commande c, parts p
     group by c.total, c.frais, c.deja
  ), repartie as (
    select p.boutique,
           coalesce(floor(r.du * p.servi / nullif(r.servi, 0)), 0) as part,
           row_number() over (order by p.servi desc, p.boutique) as rang,
           r.du
      from parts p, reste r
  )
  select x.boutique,
         (x.part + case when x.rang = 1 then x.du - sum(x.part) over () else 0 end)::bigint
    from repartie x;
    return;
  end if;
  -- (3.59.0) CHAQUE BOUTIQUE ENCAISSE SA PART, moins SON acompte : ce
  -- que valent ses articles servis, remise déduite au prorata, plus ses
  -- frais tant qu'il y a quelque chose à livrer.
  --
  -- CE QUE LE CLIENT A VERSÉ N'EST JAMAIS PERDU POUR LUI. Chaque boutique
  -- déduit d'abord son propre acompte ; ce qui a été versé en plus — un
  -- surplus, ou l'acompte d'une part annulée — diminue les autres parts
  -- au prorata, l'arrondi à la plus grosse.
  return query
    with commande as (
      select greatest(0, coalesce(c.remise, 0))::numeric as remise,
             -- (3.64.0) Au kilomètre, les frais de livraison se paient en ligne
             -- avec l'acompte, hors des parts des boutiques : ce versement-là
             -- n'allège le reste d'aucune d'elles.
             greatest(0, coalesce(c.verse, c.acompte, c.total)
                         - case when c.livraison is not null
                                then coalesce(c.frais_livraison, 0) else 0 end)::numeric as paye
        from public.commandes c where c.id = cible
    ), lignes as (
      select l.boutique_id as bou,
             sum(l.prix * l.quantite)::numeric as brut,
             coalesce(sum(l.prix * l.quantite) filter (where l.etat <> 'annulee'), 0)::numeric as servi
        from public.commande_lignes l
       where l.commande_id = cible
       group by l.boutique_id
    ), tout as (
      select sum(x.brut) as s from lignes x
    ), brutes as (
      select x.bou,
             greatest(0, round(x.servi - k.remise * x.servi / nullif(t.s, 0))
                         + case when x.servi > 0 then coalesce((lp -> x.bou ->> 'frais')::numeric, 0) else 0 end) as du
        from lignes x, tout t, commande k
    ), propres as (
      select b.bou, b.du,
             least(b.du, coalesce((lp -> b.bou ->> 'acompte')::numeric, 0)) as sien
        from brutes b
    ), credit as (
      select greatest(0, k.paye - coalesce(sum(p.sien), 0)) as reste_credit,
             coalesce(sum(p.du - p.sien), 0) as a_couvrir
        from propres p, commande k
       group by k.paye
    ), allege as (
      select p.bou, p.du - p.sien as du,
             case when c.a_couvrir > 0
                  then floor(least(c.reste_credit, c.a_couvrir) * (p.du - p.sien) / c.a_couvrir)
                  else 0 end as moins,
             least(c.reste_credit, c.a_couvrir) as credit,
             row_number() over (order by p.du - p.sien desc, p.bou) as rang
        from propres p, credit c
    )
    select a.bou,
           greatest(0, a.du - a.moins
                       - case when a.rang = 1 then a.credit - sum(a.moins) over () else 0 end)::bigint
      from allege a;
end $$;
revoke all on function public.restes_par_boutique(text) from public, anon, authenticated;


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

-- « Je l'ai remise », avec ce qu'il a encaissé. Remettre et encaisser
-- tiennent dans UNE transaction : pas de colis remis sans sa déclaration.
create or replace function public.remettre_course(
  commande text, boutique text, montant bigint, mode text, motif text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  moi      uuid := auth.uid();
  combien  int;
  du       bigint;
  trans    text := upper(left(regexp_replace(coalesce(motif, ''), '[^A-Za-z0-9.-]', '', 'g'), 40));
  c        record;
  porteur  text;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Cette course ne vous est pas confiée';
  end if;
  if not exists (select 1 from public.commande_lignes l
                  where l.commande_id = commande and l.boutique_id = boutique
                    and l.livreur_id = moi and l.etat = 'en_livraison') then
    raise exception 'Rien à remettre ici : cette course n''en est pas là.';
  end if;
  select c0.numero, c0.client_id, coalesce(nullif(c0.devise, ''), 'FCFA') as devise
    into c from public.commandes c0 where c0.id = commande;
  select coalesce(r.a_encaisser, 0) into du
    from public.restes_par_boutique(commande) r where r.boutique_id = boutique;
  du := coalesce(du, 0);

  if du > 0 then
    if coalesce(mode, '') <> 'mobile_money' then
      raise exception 'Plus d''espèces : le client paie % par MoMoPay. Mettez l''application à jour.',
        public.montant_lisible(du, c.devise) using errcode = 'P0001';
    end if;
    if coalesce(montant, 0) <> du then
      raise exception 'Le client doit payer exactement % par MoMoPay.',
        public.montant_lisible(du, c.devise) using errcode = 'P0001';
    end if;
    if length(trans) < 4 then
      raise exception 'Saisissez le numéro de la transaction MoMoPay, lu sur le SMS du client.'
        using errcode = 'P0001';
    end if;
    if exists (select 1 from public.encaissements x
                where x.mode = 'mobile_money' and x.transaction_id = trans) then
      raise exception 'Cette transaction MoMoPay a déjà servi pour une autre commande : vérifiez le SMS du client.'
        using errcode = 'P0001';
    end if;
  end if;

  perform set_config('bizzoo.livraison', 'oui', true);
  update public.commande_lignes l
     set etat = 'remise',
         recu_le = coalesce(l.recu_le, now())
   where l.commande_id = commande
     and l.boutique_id = boutique
     and l.livreur_id = moi
     and l.etat = 'en_livraison';
  get diagnostics combien = row_count;
  perform set_config('bizzoo.livraison', '', true);

  if du = 0 then
    -- Rien n'était dû : la part est soldée, rien à vérifier.
    insert into public.encaissements (commande_id, boutique_id, livreur_id, du, montant, mode, remis_le)
    values (commande, boutique, moi, 0, 0, 'aucun', now())
    on conflict (commande_id, boutique_id) do nothing;
    return jsonb_build_object('lignes', combien, 'du', 0, 'montant', 0, 'mode', 'aucun');
  end if;

  -- Payé par MoMoPay : « remis_le » reste vide tant que BIZZOO n'a pas
  -- retrouvé la transaction dans son compte.
  insert into public.encaissements (commande_id, boutique_id, livreur_id, du, montant, mode, motif, transaction_id)
  values (commande, boutique, moi, du, du, 'mobile_money', 'MoMoPay — transaction ' || trans, trans)
  on conflict (commande_id, boutique_id) do nothing;

  select coalesce(nullif(p.nom, ''), 'votre livreur') into porteur from public.profils p where p.id = moi;
  if c.client_id is not null then
    perform public.notifier(array[c.client_id], 'reste_encaisse',
      'Reste payé : ' || public.montant_lisible(du, c.devise),
      'Commande ' || coalesce(c.numero, '') ||
        coalesce(' — ' || nullif((select b.nom from public.boutiques b where b.id = boutique), ''), '') || '.' ||
        E'\nPayé par MoMoPay (transaction ' || trans || '), remis par ' || porteur || '.' ||
        E'\nSi ce n''est pas exact, signalez-le depuis votre commande.',
      '#/commande/' || commande, commande, boutique, true);
  end if;
  perform public.notifier(public.equipe_de(boutique) || public.enseigne_des_commandes() || public.les_superadmins(),
    'reste_encaisse',
    'MoMoPay à vérifier : ' || public.montant_lisible(du, c.devise),
    'Commande ' || coalesce(c.numero, '') || ' — transaction ' || trans || ', remise par ' || porteur || '.' ||
      E'\nÀ retrouver dans le compte MoMoPay de BIZZOO.',
    '#/caisse', commande, boutique, true);

  return jsonb_build_object('lignes', combien, 'du', du, 'montant', du, 'mode', 'mobile_money',
    'transaction', trans);
end $$;
revoke all on function public.remettre_course(text, text, bigint, text, text) from public, anon;
grant execute on function public.remettre_course(text, text, bigint, text, text) to authenticated;

-- Le client conteste ce que le livreur a déclaré. Comme pour suivre sa
-- commande : son compte, ou son numéro.
create or replace function public.contester_encaissement(
  commande text, boutique text, motif text, tel text default '')
returns int
language plpgsql security definer set search_path = public as $$
declare
  combien  int;
  pourquoi text := left(trim(coalesce(motif, '')), 300);
  e        record;
begin
  if not (public.ma_commande(commande)
          or exists (select 1 from public.commandes c
                      where c.id = commande and not c.compte_supprime
                        and regexp_replace(coalesce(tel, ''), '\D', '', 'g') <> ''
                        and c.client_tel = regexp_replace(coalesce(tel, ''), '\D', '', 'g'))) then
    raise exception 'Cette commande n''est pas la vôtre';
  end if;
  if length(pourquoi) < 3 then
    raise exception 'Dites en quelques mots ce qui ne va pas.' using errcode = 'P0001';
  end if;
  update public.encaissements x
     set conteste_le = now(), conteste_motif = pourquoi
   where x.commande_id = commande and x.boutique_id = boutique and x.conteste_le is null;
  get diagnostics combien = row_count;
  if combien = 0 then
    if exists (select 1 from public.encaissements x
                where x.commande_id = commande and x.boutique_id = boutique) then
      raise exception 'Vous l''avez déjà signalé : la boutique et BIZZOO sont prévenus.' using errcode = 'P0001';
    end if;
    raise exception 'Aucun paiement à la livraison n''est enregistré pour cette commande.' using errcode = 'P0001';
  end if;

  select x.montant, x.mode, cm.numero, coalesce(nullif(cm.devise, ''), 'FCFA') as devise,
         coalesce(nullif(p.nom, ''), 'le livreur') as porteur
    into e
    from public.encaissements x
    join public.commandes cm on cm.id = x.commande_id
    left join public.profils p on p.id = x.livreur_id
   where x.commande_id = commande and x.boutique_id = boutique;
  perform public.notifier(public.equipe_de(boutique) || public.enseigne_des_commandes() || public.les_superadmins(),
    'encaissement_conteste',
    'Paiement contesté — ' || coalesce(e.numero, ''),
    'Le client conteste : « ' || pourquoi || ' ».' ||
      E'\nDéclaré : ' || public.montant_lisible(e.montant, e.devise) || ' encaissé par ' || e.porteur || '.',
    '#/caisse', commande, boutique, true);
  return combien;
end $$;
revoke all on function public.contester_encaissement(text, text, text, text) from public;
grant execute on function public.contester_encaissement(text, text, text, text) to anon, authenticated;

-- LA CAISSE : ce qui a été encaissé à la livraison, sur les boutiques que
-- l'on tient — rendu ou pas encore. Et les remises SANS déclaration
-- (faites depuis une application d'avant 3.59.0) alors qu'un reste était
-- dû : « declare » à faux, pour qu'elles ne passent pas inaperçues.
create or replace function public.caisse_livreurs()
returns table (
  id bigint, commande_id text, numero text, boutique_id text, nom_boutique text,
  livreur_id uuid, livreur_nom text, livreur_tel text,
  du bigint, montant bigint, mode text, motif text,
  encaisse_le timestamptz, remis_le timestamptz, remis_par_nom text,
  conteste_le timestamptz, conteste_motif text, declare boolean, devise text)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  return query
    select x.id, x.commande_id, c.numero::text, x.boutique_id,
           coalesce(b.nom, '')::text,
           x.livreur_id, coalesce(nullif(p.nom, ''), p.email, '')::text, coalesce(p.tel, '')::text,
           x.du, x.montant, x.mode, x.motif,
           x.encaisse_le, x.remis_le, coalesce(nullif(q.nom, ''), q.email, '')::text,
           x.conteste_le, x.conteste_motif, true,
           coalesce(nullif(c.devise, ''), 'FCFA')::text
      from public.encaissements x
      join public.commandes c on c.id = x.commande_id
      left join public.boutiques b on b.id = x.boutique_id
      left join public.profils p on p.id = x.livreur_id
      left join public.profils q on q.id = x.remis_par
     where public.tient_la_caisse(x.boutique_id)
       and (x.remis_le is null or x.encaisse_le > now() - interval '60 days')
    union all
    select null::bigint, l.commande_id, c.numero::text, l.boutique_id,
           coalesce(b.nom, '')::text,
           l.livreur_id, coalesce(nullif(p.nom, ''), p.email, '')::text, coalesce(p.tel, '')::text,
           r.a_encaisser, null::bigint, ''::text, ''::text,
           max(c.paye_le), null::timestamptz, ''::text,
           null::timestamptz, ''::text, false,
           coalesce(nullif(c.devise, ''), 'FCFA')::text
      from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id and c.etat = 'payee'
      left join public.boutiques b on b.id = l.boutique_id
      left join public.profils p on p.id = l.livreur_id
      join lateral (select rr.a_encaisser from public.restes_par_boutique(l.commande_id) rr
                     where rr.boutique_id = l.boutique_id) r on true
     where l.etat = 'remise'
       and public.tient_la_caisse(l.boutique_id)
       and c.paye_le > now() - interval '60 days'
       and r.a_encaisser > 0
       and not exists (select 1 from public.encaissements x
                        where x.commande_id = l.commande_id and x.boutique_id = l.boutique_id)
     group by l.commande_id, c.numero, l.boutique_id, b.nom, l.livreur_id, p.nom, p.email, p.tel,
              r.a_encaisser, c.devise
     order by 13 desc;
end $$;
revoke all on function public.caisse_livreurs() from public, anon;
grant execute on function public.caisse_livreurs() to authenticated;

-- « Argent reçu du livreur » : une ou plusieurs lignes à la fois. Le
-- livreur est prévenu de ce que la boutique a bien reçu de lui.
create or replace function public.marquer_remis(ids bigint[])
returns int
language plpgsql security definer set search_path = public as $$
declare
  faits jsonb;
  r     record;
begin
  if auth.uid() is null then raise exception 'Connectez-vous'; end if;
  with marques as (
    update public.encaissements x
       set remis_le = now(), remis_par = auth.uid()
     where x.id = any(ids) and x.remis_le is null and x.montant > 0
       and public.tient_la_caisse(x.boutique_id)
       -- (3.59.0) Un paiement MoMoPay arrive sur le compte de BIZZOO :
       -- BIZZOO seul peut dire l'y avoir trouvé.
       and (x.mode <> 'mobile_money' or public.est_super()
            or public.droit_enseigne('finances') or public.droit_enseigne('commandes'))
    returning x.livreur_id, x.boutique_id, x.montant, x.commande_id, x.mode
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'livreur', m.livreur_id, 'boutique', m.boutique_id, 'montant', m.montant, 'mode', m.mode,
           'devise', (select coalesce(nullif(c.devise, ''), 'FCFA') from public.commandes c
                       where c.id = m.commande_id))), '[]'::jsonb)
    into faits from marques m;
  if jsonb_array_length(faits) = 0 then
    raise exception 'Rien à marquer : ces encaissements sont déjà rendus, ou ne sont pas de votre boutique.'
      using errcode = 'P0001';
  end if;
  for r in select (f ->> 'livreur')::uuid as livreur, f ->> 'boutique' as boutique,
                  sum((f ->> 'montant')::bigint) as total, min(f ->> 'devise') as devise, count(*) as nb
             from jsonb_array_elements(faits) f
            where f ->> 'livreur' is not null
              -- MoMoPay : le livreur n'avait rien en main, rien à lui dire.
              and f ->> 'mode' <> 'mobile_money'
            group by 1, 2 loop
    perform public.notifier(array[r.livreur], 'caisse_remise',
      'Argent bien reçu : ' || public.montant_lisible(r.total, r.devise),
      coalesce((select b.nom from public.boutiques b where b.id = r.boutique), 'La boutique') ||
        ' a bien reçu de vous ' || public.montant_lisible(r.total, r.devise) ||
        ' (' || r.nb || ' course' || case when r.nb > 1 then 's' else '' end || ').',
      '#/livraisons', null, r.boutique, false);
  end loop;
  return jsonb_array_length(faits);
end $$;
revoke all on function public.marquer_remis(bigint[]) from public, anon;
grant execute on function public.marquer_remis(bigint[]) to authenticated;

-- Ce que le livreur a encaissé et n'a pas encore rendu, boutique par
-- boutique : il sait à qui il doit quoi.
create or replace function public.ma_caisse()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare moi uuid := auth.uid();
begin
  if moi is null or not public.est_livreur() then return null; end if;
  return jsonb_build_object(
    -- (3.59.0) Un paiement MoMoPay n'est jamais passé par ses mains.
    'a_remettre', coalesce((select sum(x.montant) from public.encaissements x
                             where x.livreur_id = moi and x.remis_le is null
                               and x.mode <> 'mobile_money'), 0),
    'courses', (select count(*) from public.encaissements x
                 where x.livreur_id = moi and x.remis_le is null and x.montant > 0
                   and x.mode <> 'mobile_money'),
    'boutiques', coalesce((
      select jsonb_agg(jsonb_build_object('boutique', coalesce(b.nom, ''), 'montant', t.total) order by b.nom)
        from (select x.boutique_id, sum(x.montant) as total from public.encaissements x
               where x.livreur_id = moi and x.remis_le is null and x.montant > 0
                 and x.mode <> 'mobile_money'
               group by x.boutique_id) t
        left join public.boutiques b on b.id = t.boutique_id), '[]'::jsonb));
end $$;
revoke all on function public.ma_caisse() from public, anon;
grant execute on function public.ma_caisse() to authenticated;

-- (3.70.0) Lue par « fiche_course » / « faire_livrer » plus bas.
alter table public.commandes add column if not exists lieu_retrait text not null default '';

create or replace function public.fiche_course(commande text, boutique text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c   public.commandes%rowtype;
  b   public.boutiques%rowtype;
  pos record;
  brut numeric;
  tout numeric;
  part numeric;
  frais numeric;
  reste numeric;
begin
  select * into c from public.commandes where id = commande;
  if not found then return null; end if;
  select * into b from public.boutiques where id = boutique;
  select sum(l.prix * l.quantite) filter (where l.boutique_id = boutique),
         sum(l.prix * l.quantite)
    into brut, tout
    from public.commande_lignes l where l.commande_id = commande;
  select coalesce(r.a_encaisser, 0) into reste
    from public.restes_par_boutique(commande) r where r.boutique_id = boutique;
  if c.livraison is not null then
    -- (3.64.0) AU KILOMÈTRE, un seul livreur porte toute la commande : ses
    -- frais sont ceux de la commande entière.
    part  := (c.parts -> boutique ->> 'du')::numeric;
    frais := coalesce(c.frais_livraison, 0);
  elsif c.parts is not null and c.parts ? boutique then
    part  := (c.parts -> boutique ->> 'du')::numeric;
    frais := (c.parts -> boutique ->> 'frais')::numeric;
  else
    -- Une commande d'avant les conditions par boutique : sa part au
    -- prorata, frais compris.
    part  := round(c.total * coalesce(brut, 0) / nullif(tout, 0));
    frais := case when coalesce(brut, 0) = coalesce(tout, 0) then coalesce(c.frais_livraison, 0)
                  else round(coalesce(c.frais_livraison, 0) * coalesce(brut, 0) / nullif(tout, 0)) end;
  end if;
  return jsonb_build_object(
    'numero', c.numero,
    -- (3.70.0) Où récupérer la commande, tel que l'équipe l'a saisi
    -- (« Faire livrer ») ; vide pour une commande de l'application.
    'lieu_retrait', coalesce(c.lieu_retrait, ''),
    'retrait', jsonb_build_object(
      'boutique', coalesce(b.nom, ''), 'adresse', coalesce(b.adresse, ''),
      'tel', coalesce(nullif(b.tel, ''), b.whatsapp, ''), 'indicatif', coalesce(nullif(b.indicatif, ''), '229'),
      -- (3.70.0) Pour « Écrire à la boutique sur WhatsApp ».
      'whatsapp', coalesce(nullif(b.whatsapp, ''), b.tel, ''),
      'latitude', b.latitude, 'longitude', b.longitude),
    'livraison', jsonb_build_object(
      'nom', coalesce(c.client_nom, ''), 'adresse', coalesce(c.client_adresse, ''),
      'note', coalesce(c.note, ''), 'tel', coalesce(c.client_tel, ''),
      'indicatif', coalesce(nullif(c.client_indicatif, ''), '229'),
      -- (3.64.0) Le point exact où livrer, quand le client l'a donné.
      'latitude', c.livraison -> 'destination' -> 'latitude',
      'longitude', c.livraison -> 'destination' -> 'longitude'),
    'devise', coalesce(c.devise, 'FCFA'),
    'frais', coalesce(frais, 0),
    -- (3.64.0) Le véhicule, la distance, et ce que le livreur y gagne.
    'trajet', case when c.livraison is null then null
                   else jsonb_build_object('vehicule', c.livraison ->> 'vehicule',
                                           'distance_km', c.livraison -> 'distance_km') end,
    -- (3.66.0) Au kilomètre ou à l'ancien tarif : sa part des frais.
    'gain', public.gain_livreur(c.id),
    'deja_paye', greatest(0, coalesce(part, 0) - coalesce(reste, 0)),
    'a_encaisser', coalesce(reste, 0),
    -- Ce que le livreur a déclaré en remettant le colis (3.59.0).
    'encaisse', (select jsonb_build_object('montant', x.montant, 'mode', x.mode,
                         'encaisse_le', x.encaisse_le, 'remis_le', x.remis_le,
                         'transaction', x.transaction_id)
                   from public.encaissements x
                  where x.commande_id = commande and x.boutique_id = boutique),
    -- Le code MoMoPay de BIZZOO, à montrer au client (3.59.0).
    'momopay', (select jsonb_build_object('code', p.momopay_code, 'nom', p.momopay_nom)
                  from public.paiement p where p.id = 1));
end $$;
revoke all on function public.fiche_course(text, text) from public, anon, authenticated;

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
    'paye_le', c.paye_le, 'remarque', c.remarque,
    'frais_livraison', c.frais_livraison,
    -- (3.64.0) Le véhicule et la distance de la livraison.
    'livraison', c.livraison,
    -- L'acompte, ce qui a été versé, et ce qui reste à payer à la
    -- livraison, boutique par boutique. Une commande d'avant l'acompte
    -- se payait en entier : son acompte est son total.
    'taux_acompte', coalesce(c.taux_acompte, 100),
    'acompte', coalesce(c.acompte, c.total),
    'verse', c.verse,
    'reste', (select coalesce(sum(r.a_encaisser), 0)
                from public.restes_par_boutique(c.id) r),
    'restes', (select coalesce(jsonb_object_agg(r.boutique_id, r.a_encaisser), '{}'::jsonb)
                 from public.restes_par_boutique(c.id) r
                where r.boutique_id is not null),
    -- (3.59.0) Ce que le client a payé au livreur, boutique par boutique,
    -- d'après la déclaration du livreur — et s'il l'a contesté.
    'encaissements', (select coalesce(jsonb_object_agg(x.boutique_id, jsonb_build_object(
                         'montant', x.montant, 'mode', x.mode, 'encaisse_le', x.encaisse_le,
                         'livreur', coalesce(nullif(p.nom, ''), ''),
                         'conteste', x.conteste_le is not null)), '{}'::jsonb)
                        from public.encaissements x
                        left join public.profils p on p.id = x.livreur_id
                       where x.commande_id = c.id),
    'paye_livraison', (select coalesce(sum(x.montant), 0) from public.encaissements x
                        where x.commande_id = c.id),
    -- (3.63.0) OÙ EN EST CHAQUE BOUTIQUE, pour qui suit sa commande par
    -- son numéro : l'étape la MOINS avancée de ses lignes (une ligne
    -- annulée ne retient rien), et si le client a tout confirmé. Sans
    -- compte, c'était le seul morceau du suivi qui manquait — les lignes
    -- ne se lisent qu'avec un compte. La même règle que l'application
    -- applique aux commandes d'un compte.
    'etats', (select coalesce(jsonb_object_agg(e.boutique_id,
                       jsonb_build_object('etat', e.etat, 'confirme', e.confirme)), '{}'::jsonb)
                from (select l.boutique_id,
                             (array_agg(l.etat order by array_position(
                                array['nouvelle', 'vue', 'preparee', 'en_livraison', 'remise',
                                      'annulee'], l.etat)))[1] as etat,
                             bool_and(l.confirme_le is not null) as confirme
                        from public.commande_lignes l
                       where l.commande_id = c.id
                       group by l.boutique_id) e));
end $$;
revoke all on function public.suivre_commande(text, text) from public;
grant execute on function public.suivre_commande(text, text) to anon, authenticated;


