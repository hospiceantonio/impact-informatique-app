-- =========================================================
-- BIZZOO — la distance PAR LA ROUTE (Google Routes API) — 3.70.0
-- Fichier de mise à jour : à exécuter une fois sur la base en service.
-- Sans danger : relançable, et rien n'est supprimé.
--
-- Pose le cache des distances (« distances_route »), les deux fonctions
-- du serveur (« route_connue », « enregistrer_route ») et le devis qui
-- s'en sert. TANT QUE LA FONCTION « distance-route » N'A PAS SA CLÉ
-- GOOGLE, LE CACHE RESTE VIDE ET RIEN NE CHANGE : les frais restent à vol
-- d'oiseau × coefficient, au franc près comme avant.
-- =========================================================

-- Les colonnes dont le devis se sert. Elles viennent d'ailleurs, et sont
-- répétées ici : un fichier qui pose une fonction pose aussi les
-- colonnes qu'elle touche.
alter table public.paiement add column if not exists livraison_latitude double precision;
alter table public.paiement add column if not exists livraison_longitude double precision;
alter table public.paiement add column if not exists livraison_rayon_km int not null default 10;
alter table public.paiement add column if not exists livraison_coef numeric(4,2) not null default 1.3;
alter table public.paiement add column if not exists moto_forfait int not null default 1000;
alter table public.paiement add column if not exists moto_prix_km int not null default 100;
alter table public.paiement add column if not exists tricycle_forfait int not null default 4000;
alter table public.paiement add column if not exists tricycle_prix_km int not null default 500;

-- ---------- (3.70.0) La distance PAR LA ROUTE (Google Routes API) ----------
-- Le vol d'oiseau × 1,3 n'est qu'une moyenne : une lagune, un pont, et le
-- trajet réel double. La fonction serveur « distance-route » demande le
-- vrai trajet à Google (la clé GOOGLE_MAPS_KEY ne quitte jamais le
-- serveur) et l'écrit ici ; « devis_livraison » s'en sert quand il existe,
-- et retombe sur le vol d'oiseau × coefficient sinon. Sans clé, rien
-- n'est écrit ici : tout se passe comme avant.
--
-- UN CACHE À 50 MÈTRES PRÈS. Départ et arrivée sont ramenés à une grille
-- de 0,0005° (≈ 55 m) : un client qui recommande de chez lui ne coûte pas
-- un second appel à Google. Le point BIZZOO fait partie de la clé : le
-- déplacer rend les anciennes distances caduques, sans rien effacer.
--
-- PERSONNE D'AUTRE QUE LE SERVEUR N'Y ÉCRIT (ni l'application, ni un
-- administrateur) : une distance écrite à la main ferait payer moins.
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

-- Pour la fonction serveur seulement : y a-t-il déjà une distance pour ce
-- client ? Le point BIZZOO est-il réglé ? Le plafond du jour est-il
-- atteint ? (Le plafond protège la facture Google : la fonction est
-- ouverte aux clients sans compte, et chaque appel nouveau se paie.)
create or replace function public.route_connue(latitude double precision, longitude double precision)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r     public.paiement%rowtype;
  dm    int;
  a     double precision;
  plafond constant int := 1000;   -- appels nouveaux à Google par jour, au plus
begin
  select * into r from public.paiement where id = 1;
  if not found or r.livraison_latitude is null or r.livraison_longitude is null then
    return jsonb_build_object('point', false);
  end if;
  if latitude is null or longitude is null
     or latitude not between -90 and 90 or longitude not between -180 and 180
     or (latitude = 0 and longitude = 0) then
    return jsonb_build_object('point', true, 'invalide', true);
  end if;
  select x.distance_m into dm from public.distances_route x
   where x.o_lat = public.grille_route(r.livraison_latitude)
     and x.o_lng = public.grille_route(r.livraison_longitude)
     and x.d_lat = public.grille_route(latitude)
     and x.d_lng = public.grille_route(longitude);
  a := sin(radians(latitude - r.livraison_latitude) / 2) ^ 2
       + cos(radians(r.livraison_latitude)) * cos(radians(latitude))
         * sin(radians(longitude - r.livraison_longitude) / 2) ^ 2;
  return jsonb_build_object(
    'point', true,
    'origine', jsonb_build_object('latitude', r.livraison_latitude, 'longitude', r.livraison_longitude),
    'distance_m', dm,
    'vol_oiseau_km', round((2 * 6371 * asin(least(1, sqrt(a))))::numeric, 3),
    'plafond_atteint', dm is null and (select count(*) from public.distances_route x
                                         where x.cree_le > now() - interval '1 day') >= plafond);
end $$;
revoke all on function public.route_connue(double precision, double precision) from public, anon, authenticated;
grant execute on function public.route_connue(double precision, double precision) to service_role;

-- Pour la fonction serveur seulement : la distance que Google a rendue.
create or replace function public.enregistrer_route(
  latitude double precision, longitude double precision, distance_m int)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.paiement%rowtype;
begin
  select * into r from public.paiement where id = 1;
  if not found or r.livraison_latitude is null or r.livraison_longitude is null then
    return jsonb_build_object('ok', false);
  end if;
  if distance_m is null or distance_m <= 0 or distance_m > 1000000
     or latitude is null or longitude is null then
    raise exception 'Distance de route invalide';
  end if;
  insert into public.distances_route as x (o_lat, o_lng, d_lat, d_lng, distance_m, cree_le)
  values (public.grille_route(r.livraison_latitude), public.grille_route(r.livraison_longitude),
          public.grille_route(latitude), public.grille_route(longitude), distance_m, now())
  on conflict on constraint distances_route_pkey
  do update set distance_m = excluded.distance_m, cree_le = now();
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.enregistrer_route(double precision, double precision, int) from public, anon, authenticated;
grant execute on function public.enregistrer_route(double precision, double precision, int) to service_role;

-- LE DEVIS D'UNE LIVRAISON : la distance, les kilomètres facturés, les
-- frais. Null tant que la livraison au kilomètre n'est pas en service.
-- Ouverte à tous : l'écran de commande en montre l'aperçu, et elle ne
-- dit rien que les réglages publics ne disent déjà. « creer_commande »
-- l'appelle pour figer les frais : une seule règle, un seul endroit.
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
