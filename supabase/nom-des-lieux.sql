-- =========================================================
-- BIZZOO 3.76.0 — Le nom des lieux, et les frais de « Faire livrer »
--
--   1. Le nom d'un point de la carte (« Sèdomey, Togoudo, Godomey ») : la
--      fonction serveur « lieu » le demande à OpenStreetMap et le range ici,
--      à 50 m près — un quartier nommé une fois l'est pour tout le monde.
--      Il s'affiche sur le bon du livreur, pour chaque boutique et pour le
--      client, et devient l'adresse de livraison de la commande.
--   2. « Faire livrer » : le point posé sur la carte (ou trouvé par son nom)
--      donne les frais au kilomètre, comme une commande de l'application.
--      L'équipe peut encore les modifier.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- Puis :  supabase functions deploy lieu --no-verify-jwt
-- =========================================================

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.distance_trajet(
  de_lat double precision, de_lng double precision, a_lat double precision, a_lng double precision,
  out km numeric, out par_route boolean)
language plpgsql stable security definer set search_path = public as $$
declare
  m    int;
  dlat double precision;
  dlng double precision;
  h    double precision;
  coef numeric := coalesce((select p.livraison_coef from public.paiement p where p.id = 1), 1.3);
begin
  if public.grille_route(de_lat) = public.grille_route(a_lat)
     and public.grille_route(de_lng) = public.grille_route(a_lng) then
    km := 0; par_route := true;
    return;
  end if;
  select x.distance_m into m from public.distances_route x
   where x.o_lat = public.grille_route(de_lat) and x.o_lng = public.grille_route(de_lng)
     and x.d_lat = public.grille_route(a_lat) and x.d_lng = public.grille_route(a_lng);
  if m is not null then
    km := round(m / 1000.0, 3); par_route := true;
    return;
  end if;
  dlat := radians(a_lat - de_lat);
  dlng := radians(a_lng - de_lng);
  h := sin(dlat / 2) ^ 2 + cos(radians(de_lat)) * cos(radians(a_lat)) * sin(dlng / 2) ^ 2;
  km := round((2 * 6371 * asin(least(1, sqrt(h))) * coef)::numeric, 3);
  par_route := false;
end $$;
revoke all on function public.distance_trajet(double precision, double precision, double precision, double precision)
  from public, anon, authenticated;

create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false)
     and public.role_courant() is not null;
$$;
revoke all on function public.est_compte_enseigne()  from public, anon;
grant execute on function public.est_compte_enseigne() to authenticated;

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.devis_tournee(
  boutiques text[], latitude double precision, longitude double precision, vehicule text default 'moto')
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r      public.paiement%rowtype;
  v      text := case when vehicule = 'tricycle' then 'tricycle' else 'moto' end;
  ids    text[] := '{}';
  noms   text[] := '{}';
  lats   double precision[] := '{}';
  lngs   double precision[] := '{}';
  sans   boolean[] := '{}';
  n      int;
  w      int;
  d      numeric[] := '{}';
  routes int := 0;
  tron   int := 0;
  t      record;
  i      int;
  j      int;
  k      int;
  a      int[];
  c      int[];
  meil   int[];
  cout   numeric;
  best   numeric;
  tmp    int;
  libre  boolean[];
  dist   numeric;
  km     int;
  forf   int;
  prix   int;
  sup    int;
  etapes jsonb := '[]'::jsonb;
  b      record;
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
  -- Les boutiques, une fois chacune, dans un ordre fixe (leur identifiant) :
  -- à distances égales, la base et l'application choisissent la même.
  for b in select x.id, x.nom, x.latitude, x.longitude
             from public.boutiques x
            where x.id = any(coalesce(boutiques, '{}'))
            order by x.id collate "C" loop
    ids  := ids || b.id;
    noms := noms || coalesce(b.nom, '');
    if b.latitude is null or b.longitude is null or (b.latitude = 0 and b.longitude = 0)
       or b.latitude not between -90 and 90 or b.longitude not between -180 and 180 then
      lats := lats || r.livraison_latitude; lngs := lngs || r.livraison_longitude; sans := sans || true;
    else
      lats := lats || b.latitude; lngs := lngs || b.longitude; sans := sans || false;
    end if;
  end loop;
  n := coalesce(array_length(ids, 1), 0);
  if n = 0 then
    -- Aucune boutique connue : du point BIZZOO, comme avant, sans supplément.
    lats := array[r.livraison_latitude]; lngs := array[r.livraison_longitude];
    ids := array[null::text]; noms := array['BIZZOO']; sans := array[false];
  end if;
  w := greatest(n, 1);
  -- Les tronçons : d[(i-1)*(w+1)+j], j = w+1 étant le client.
  for i in 1 .. w loop
    for j in 1 .. w + 1 loop
      if j = i then
        d := d || 0::numeric;
      else
        select * into t from public.distance_trajet(lats[i], lngs[i],
          case when j <= w then lats[j] else latitude end,
          case when j <= w then lngs[j] else longitude end);
        d := d || t.km;
      end if;
    end loop;
  end loop;

  -- L'ordre le plus court.
  a := array(select generate_series(1, w));
  meil := a;
  if w <= 7 then
    -- Toutes les possibilités (algorithme de Heap) ; à égalité, la première.
    c := array_fill(0, array[w]);
    best := null;
    loop
      cout := 0;
      for k in 1 .. w - 1 loop cout := cout + d[(a[k] - 1) * (w + 1) + a[k + 1]]; end loop;
      cout := cout + d[(a[w] - 1) * (w + 1) + w + 1];
      if best is null or cout < best then best := cout; meil := a; end if;
      i := 1;
      while i < w and c[i + 1] >= i loop
        c[i + 1] := 0; i := i + 1;
      end loop;
      exit when i >= w;
      if i % 2 = 0 then
        tmp := a[1]; a[1] := a[i + 1]; a[i + 1] := tmp;
      else
        tmp := a[c[i + 1] + 1]; a[c[i + 1] + 1] := a[i + 1]; a[i + 1] := tmp;
      end if;
      c[i + 1] := c[i + 1] + 1;
    end loop;
  else
    -- Plus de 7 boutiques : de la plus proche en plus proche, en essayant
    -- chaque boutique de départ.
    best := null;
    for i in 1 .. w loop
      libre := array_fill(true, array[w]);
      a := array[i]; libre[i] := false; cout := 0;
      for k in 2 .. w loop
        tmp := null;
        for j in 1 .. w loop
          if libre[j] and (tmp is null or d[(a[k - 1] - 1) * (w + 1) + j] < d[(a[k - 1] - 1) * (w + 1) + tmp]) then
            tmp := j;
          end if;
        end loop;
        cout := cout + d[(a[k - 1] - 1) * (w + 1) + tmp];
        a := a || tmp; libre[tmp] := false;
      end loop;
      cout := cout + d[(a[w] - 1) * (w + 1) + w + 1];
      if best is null or cout < best then best := cout; meil := a; end if;
    end loop;
  end if;

  -- Les étapes, dans l'ordre, avec le tronçon qui mène à la suivante.
  dist := 0;
  for k in 1 .. w loop
    i := meil[k];
    j := case when k < w then meil[k + 1] else w + 1 end;
    dist := dist + d[(i - 1) * (w + 1) + j];
    tron := tron + 1;
    select * into t from public.distance_trajet(lats[i], lngs[i],
      case when j <= w then lats[j] else latitude end,
      case when j <= w then lngs[j] else longitude end);
    if t.par_route then routes := routes + 1; end if;
    if n > 0 then
      etapes := etapes || jsonb_build_object(
        'boutique_id', ids[i], 'nom', noms[i],
        'latitude', round(lats[i]::numeric, 6), 'longitude', round(lngs[i]::numeric, 6),
        'sans_position', sans[i],
        'vers_suivante_km', round(d[(i - 1) * (w + 1) + j], 1));
    end if;
  end loop;

  km := case when dist > r.livraison_rayon_km then ceil(dist - r.livraison_rayon_km)::int else 0 end;
  forf := case when v = 'tricycle' then r.tricycle_forfait else r.moto_forfait end;
  prix := case when v = 'tricycle' then r.tricycle_prix_km else r.moto_prix_km end;
  -- (3.74.1) Le supplément ne vaut que pour une commande GROUPÉE (deux
  -- boutiques ou plus) ; une seule boutique : forfait + km, sans plus.
  sup  := case when n > 1 then coalesce(r.livraison_supplement_boutique, 0) else 0 end;
  return jsonb_build_object(
    'vehicule', v,
    'distance_km', round(dist, 1),
    'calcul', case when routes = tron then 'route' when routes = 0 then 'vol_oiseau' else 'mixte' end,
    'rayon_km', r.livraison_rayon_km,
    'km_factures', km,
    'forfait', forf,
    'prix_km', prix,
    'supplement_boutique', sup,
    'nb_boutiques', n,
    'supplements', n * sup,
    'frais', forf + km * prix + n * sup,
    'tournee', etapes,
    'point', jsonb_build_object('latitude', r.livraison_latitude, 'longitude', r.livraison_longitude),
    'destination', jsonb_build_object('latitude', round(latitude::numeric, 6),
                                      'longitude', round(longitude::numeric, 6)));
end $$;
revoke all on function public.devis_tournee(text[], double precision, double precision, text) from public;
grant execute on function public.devis_tournee(text[], double precision, double precision, text) to anon, authenticated;

create or replace function public.peut_faire_livrer() returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return public.est_super() or (public.est_compte_enseigne() and exists (
    select 1 from public.profils p where p.id = auth.uid() and p.actif and p.peut_faire_livrer));
end $$;
revoke all on function public.peut_faire_livrer() from public, anon;
grant execute on function public.peut_faire_livrer() to authenticated;

-- (3.70.0) Empruntée plus bas, recopiée telle quelle.
create or replace function public.grille_route(x double precision) returns numeric
language sql immutable as $$
  select (round((x * 2000)::numeric) / 2000)::numeric(9,4);
$$;


-- ---------- Le nom des lieux ----------
create table if not exists public.lieux_noms (
  lat_g   numeric(9,4) not null,
  lng_g   numeric(9,4) not null,
  nom     text not null check (length(nom) between 1 and 200),
  cree_le timestamptz not null default now(),
  primary key (lat_g, lng_g)
);
create index if not exists lieux_noms_jour on public.lieux_noms(cree_le);
alter table public.lieux_noms enable row level security;
revoke all on public.lieux_noms from public, anon, authenticated;

create table if not exists public.lieux_recherches (
  jour date primary key default current_date,
  n    int not null default 0
);
alter table public.lieux_recherches enable row level security;
revoke all on public.lieux_recherches from public, anon, authenticated;

-- Le nom déjà connu d'un point (ou null), et si le plafond du jour est atteint.
create or replace function public.lieu_connu(latitude double precision, longitude double precision)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  n text;
  plafond constant int := 2000;   -- questions nouvelles à la source par jour, au plus
begin
  select x.nom into n from public.lieux_noms x
   where x.lat_g = public.grille_route(latitude) and x.lng_g = public.grille_route(longitude);
  return jsonb_build_object('nom', n,
    'plafond_atteint', n is null and
      (select count(*) from public.lieux_noms x where x.cree_le > now() - interval '1 day')
      + coalesce((select r.n from public.lieux_recherches r where r.jour = current_date), 0) >= plafond);
end $$;
revoke all on function public.lieu_connu(double precision, double precision) from public, anon, authenticated;
grant execute on function public.lieu_connu(double precision, double precision) to service_role;

-- Le nom qu'a rendu la source.
create or replace function public.noter_lieu(latitude double precision, longitude double precision, nom text)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if latitude is null or longitude is null or coalesce(btrim(nom), '') = '' then return false; end if;
  insert into public.lieux_noms as x (lat_g, lng_g, nom)
  values (public.grille_route(latitude), public.grille_route(longitude), left(btrim(nom), 200))
  on conflict (lat_g, lng_g) do update set nom = excluded.nom, cree_le = now();
  return true;
end $$;
revoke all on function public.noter_lieu(double precision, double precision, text) from public, anon, authenticated;
grant execute on function public.noter_lieu(double precision, double precision, text) to service_role;

-- Une recherche par nom de plus, aujourd'hui.
create or replace function public.compter_recherche_lieu() returns int
language plpgsql security definer set search_path = public as $$
declare v int;
begin
  insert into public.lieux_recherches as r (jour, n) values (current_date, 1)
  on conflict (jour) do update set n = r.n + 1
  returning n into v;
  return v;
end $$;
revoke all on function public.compter_recherche_lieu() from public, anon, authenticated;
grant execute on function public.compter_recherche_lieu() to service_role;

-- ---------- « Faire livrer » : les frais au kilomètre ----------
-- Le devis de l'écran « Faire livrer » : ce que valent les articles, au
-- prix du catalogue, et le véhicule (le tricycle dès qu'un produit
-- l'exige). Rien n'est écrit : pas de commande d'essai, donc pas de numéro
-- « BZ- » perdu, qui ferait croire au point qu'une commande manque.
-- (3.76.0) Avec le point de livraison (« destination ») : les frais au
-- kilomètre, calculés comme pour une commande de l'application
-- (« livraison ») ; l'équipe les retrouve dans la case, modifiables.
create or replace function public.devis_faire_livrer(articles jsonb, destination jsonb default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  sous   bigint;
  devise text;
  tri    boolean;
  bouts  text[];
  lat    double precision;
  lng    double precision;
  liv    jsonb;
begin
  if auth.uid() is null or not public.peut_faire_livrer() then
    raise exception 'Réservé aux comptes qui ont le droit « Faire livrer ».' using errcode = 'P0001';
  end if;
  if articles is null or jsonb_typeof(articles) <> 'array' or jsonb_array_length(articles) = 0 then
    return jsonb_build_object('sous_total', 0, 'devise', 'FCFA', 'vehicule', 'moto');
  end if;
  with a as (
    select x ->> 'produit_id' as id,
           greatest(1, least(99, coalesce((x ->> 'quantite')::int, 1))) as q
      from jsonb_array_elements(articles) x
  )
  select coalesce(sum(coalesce(p.prix, 0) * a.q), 0)::bigint,
         min(coalesce(nullif(b.devise, ''), 'FCFA')),
         bool_or(p.vehicule = 'tricycle'),
         array_agg(distinct p.boutique_id) filter (where p.boutique_id is not null)
    into sous, devise, tri, bouts
    from a join public.produits p on p.id = a.id
    left join public.boutiques b on b.id = p.boutique_id;
  -- Le point de livraison : lu s'il est un vrai point, ignoré sinon (les
  -- frais restent alors à saisir, comme avant).
  if destination is not null and jsonb_typeof(destination) = 'object' then
    begin
      lat := (destination ->> 'latitude')::double precision;
      lng := (destination ->> 'longitude')::double precision;
      if lat between -90 and 90 and lng between -180 and 180 and not (lat = 0 and lng = 0) then
        liv := public.devis_tournee(bouts, lat, lng,
                 case when coalesce(tri, false) then 'tricycle' else 'moto' end);
      end if;
    exception when others then
      liv := null;
    end;
  end if;
  return jsonb_build_object('sous_total', sous, 'devise', coalesce(devise, 'FCFA'),
    'vehicule', case when coalesce(tri, false) then 'tricycle' else 'moto' end,
    'livraison', liv);
end $$;
revoke all on function public.devis_faire_livrer(jsonb, jsonb) from public, anon;
grant execute on function public.devis_faire_livrer(jsonb, jsonb) to authenticated;
