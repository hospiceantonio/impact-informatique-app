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
-- BIZZOO — revendeurs et livreurs valident leur compte par leur position
--
-- Un LIVREUR enregistre sa position (géolocalisation du téléphone +
-- adresse) à sa première connexion à BIZZOO Admin ; tant qu'il ne l'a
-- pas fait, aucune course ne lui est confiée.
-- Un REVENDEUR enregistre la sienne dans son compte ; tant qu'il ne l'a
-- pas fait, BIZZOO ne peut pas valider sa demande.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
-- Sans danger : relançable.
-- =========================================================

-- =========================================================
-- Un livreur VALIDE SON COMPTE en enregistrant sa position : la
-- géolocalisation de son téléphone, et son adresse écrite. BIZZOO Admin
-- le lui demande à la connexion, avant tout le reste ; tant qu'il ne
-- l'a pas fait, aucune course ne lui est confiée (« assigner_livreur »).
--
-- La position s'écrit par « enregistrer_ma_position », et par le livreur
-- lui-même : personne ne la pose à sa place, personne ne la retouche à
-- la main. L'enseigne les lit toutes ; une boutique, celles de ses
-- livreurs.

-- Les fonctions qu'appellent celles qui suivent, telles quelles.
-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
create or replace function public.equipe_de(cible text) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and cible is not null and p.boutique_id = cible
     and p.role in ('administrateur', 'moderateur');
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


create or replace function public.est_admin_bizzoo() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'administrateur', false)
     and public.est_compte_enseigne();
$$;
revoke all on function public.est_admin_bizzoo() from public, anon;
grant execute on function public.est_admin_bizzoo() to authenticated;


create or replace function public.numero_de_livreur(numero text) returns boolean
language sql stable security definer set search_path = public as $$
  select length(regexp_replace(coalesce(numero, ''), '\D', '', 'g')) >= 8
     and exists (
       select 1 from public.profils p
        where p.actif and p.role = 'livreur'
          and length(regexp_replace(coalesce(p.tel, ''), '\D', '', 'g')) >= 8
          and right(regexp_replace(p.tel, '\D', '', 'g'), 8)
            = right(regexp_replace(numero, '\D', '', 'g'), 8));
$$;
revoke all on function public.numero_de_livreur(text) from public, anon, authenticated;


create or replace function public.administre(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.droit_enseigne('boutiques')
      or (public.est_admin() and cible is not null
          and cible = public.boutique_du_compte());
$$;


create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;


create or replace function public.coord_valable(valeur double precision, borne double precision)
returns double precision
language sql immutable as $$
  select case when valeur is null
                or valeur <> valeur              -- « NaN » ne s'égale pas lui-même
                or valeur < -borne or valeur > borne
              then null else valeur end;
$$;
revoke all on function public.coord_valable(double precision, double precision)
  from public, anon, authenticated;
grant execute on function public.coord_valable(double precision, double precision)
  to anon, authenticated;

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


create or replace function public.peut_agir_sur(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.est_compte_enseigne()
      or (public.est_equipe() and cible is not null
          and cible = public.boutique_du_compte());
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



-- Les fonctions qu'appellent celles qui suivent, telles quelles.
create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;



create table if not exists public.positions_livreurs (
  profil_id      uuid primary key references public.profils(id) on delete cascade,
  latitude       double precision not null,
  longitude      double precision not null,
  precision_m    int,
  adresse        text not null default '',
  enregistre_le  timestamptz not null default now()
);
alter table public.positions_livreurs enable row level security;
drop policy if exists "positions livreurs lecture" on public.positions_livreurs;
create policy "positions livreurs lecture" on public.positions_livreurs
  for select to authenticated
  using (profil_id = auth.uid()
         or public.est_super()
         or public.est_admin_bizzoo()
         or exists (select 1 from public.profils p
                     where p.id = positions_livreurs.profil_id
                       and public.administre(p.boutique_id)));
revoke all on public.positions_livreurs from anon;
revoke insert, update, delete on public.positions_livreurs from authenticated;
grant select on public.positions_livreurs to authenticated;

create or replace function public.enregistrer_ma_position(
  lat double precision, lng double precision, adresse text, precision_m int default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  la  double precision := public.coord_valable(lat, 90);
  lo  double precision := public.coord_valable(lng, 180);
  ad  text := left(trim(coalesce(adresse, '')), 200);
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Seul un livreur enregistre sa position ici.' using errcode = '42501';
  end if;
  -- « 0, 0 » : un téléphone qui n'a rien trouvé, jamais Cotonou.
  if la is null or lo is null or (la = 0 and lo = 0) then
    raise exception 'Position introuvable : activez la localisation du téléphone, puis réessayez.'
      using errcode = 'P0001';
  end if;
  if length(ad) < 3 then
    raise exception 'Indiquez aussi votre adresse : quartier, repère.' using errcode = 'P0001';
  end if;
  insert into public.positions_livreurs (profil_id, latitude, longitude, precision_m, adresse, enregistre_le)
  values (moi, la, lo, greatest(0, precision_m), ad, now())
  on conflict (profil_id) do update
     set latitude = excluded.latitude, longitude = excluded.longitude,
         precision_m = excluded.precision_m, adresse = excluded.adresse,
         enregistre_le = now();
  return jsonb_build_object('latitude', la, 'longitude', lo, 'adresse', ad, 'le', now());
end $$;
revoke all on function public.enregistrer_ma_position(double precision, double precision, text, int)
  from public, anon;
grant execute on function public.enregistrer_ma_position(double precision, double precision, text, int)
  to authenticated;


create or replace function public.valider_revendeur(
  cible uuid, accord boolean, raison text default '')
returns text
language plpgsql security definer set search_path = public as $$
declare
  qui  text;
  etat text;
begin
  -- Le superadministrateur, ou un administrateur de BIZZOO (3.59.0).
  if not (public.est_super() or public.est_admin_bizzoo()) then
    raise exception 'Seul BIZZOO valide un compte revendeur';
  end if;
  select coalesce(p.email, '') into qui from public.profils p where p.id = auth.uid();
  etat := case when accord then 'validee' else 'refusee' end;

  -- UN REVENDEUR VALIDE SON COMPTE EN ACTIVANT SA POSITION : la
  -- géolocalisation de son téléphone, ET son adresse écrite. Sans elles,
  -- BIZZOO ne l'accepte pas (il peut toujours refuser).
  if accord and not exists (
       select 1 from public.clients c
        where c.id = cible
          and c.revendeur_latitude is not null and c.revendeur_longitude is not null
          and length(trim(coalesce(c.revendeur_adresse, ''))) >= 3) then
    raise exception 'Ce revendeur n''a pas encore enregistré sa position : il doit activer la localisation de son téléphone dans son compte, et indiquer son adresse.'
      using errcode = 'P0001';
  end if;

  -- Une demande déposée avant la 3.59.0 avec le numéro d'un livreur ne
  -- se valide pas : un livreur n'est pas revendeur.
  if accord and exists (select 1 from public.clients c
                         where c.id = cible and public.numero_de_livreur(c.tel)) then
    raise exception 'Ce numéro est celui d''un livreur BIZZOO : un livreur ne devient pas revendeur.'
      using errcode = 'P0001';
  end if;

  perform set_config('bizzoo.revendeur', 'oui', true);
  update public.clients
     set revendeur_etat       = etat,
         type_compte          = case when accord then 'revendeur' else type_compte end,
         revendeur_decide_par = coalesce(qui, ''),
         revendeur_decide_le  = now(),
         revendeur_motif      = left(coalesce(raison, ''), 300),
         maj_le               = now()
   where id = cible;
  if not found then
    perform set_config('bizzoo.revendeur', '', true);
    raise exception 'Compte introuvable';
  end if;
  -- Le drapeau est rendu tel qu'il était : il ne vaut que pour la
  -- ligne qu'on vient d'écrire, pas pour la suite de l'appel.
  perform set_config('bizzoo.revendeur', '', true);
  return etat;
end $$;

revoke all on function public.valider_revendeur(uuid, boolean, text)
  from public, anon, authenticated;
grant execute on function public.valider_revendeur(uuid, boolean, text) to authenticated;

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
    select p.role, (p.boutique_id is null), p.vehicule into rang, bizzoo, son_vehicule from public.profils p
     where p.id = livreur and p.actif
       and (public.est_super()
            or public.est_compte_enseigne()
            -- Le livreur de BIZZOO : aucune boutique, donc toutes.
            or p.boutique_id is null
            or p.boutique_id = public.boutique_du_compte());
    if rang is distinct from 'livreur' then
      raise exception 'Ce compte n''est pas un livreur de votre boutique ni de BIZZOO';
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


