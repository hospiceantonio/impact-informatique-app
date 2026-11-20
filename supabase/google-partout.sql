-- =========================================================
-- BIZZOO 4.8.0 — Google partout : les adresses, les quartiers, les cartes
--
--   1. LES NOMS DE LIEUX. La fonction serveur « lieu » demande désormais à
--      Google (Geocoding, Places) le nom d'un quartier et les lieux d'une
--      recherche, et ne revient à OpenStreetMap que si Google ne répond
--      pas. Un nom venu de Google ne se garde que 30 jours (ses
--      conditions) : la mémoire « lieux_noms » retient d'où vient chaque
--      nom, et oublie ceux de Google passé ce délai.
--
--   2. LES CARTES. Les trois applications affichent les cartes de Google
--      quand une clé de cartes est réglée (BIZZOO Admin → Réglages →
--      « Cartes Google »), celles d'OpenStreetMap sinon. Cette clé-là est
--      PUBLIQUE par nature — le navigateur la joint à chaque image de
--      carte — : elle n'a rien à voir avec la clé du serveur (les secrets
--      de Supabase), elle se limite chez Google aux adresses de BIZZOO, et
--      elle vit dans une table que tout le monde lit. Seul le
--      superadministrateur l'écrit.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- ---------- 1. D'où vient le nom d'un lieu ----------
-- (4.1.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.grille_route(x double precision) returns numeric
language sql immutable as $$
  select (round((x * 2000)::numeric) / 2000)::numeric(9,4);
$$;


alter table public.lieux_noms add column if not exists source text not null default 'osm'
  check (source in ('osm', 'google'));

-- Connu : un nom d'OpenStreetMap, ou un nom de Google de moins de 30 jours.
create or replace function public.lieu_connu(latitude double precision, longitude double precision)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  n text;
  plafond constant int := 2000;   -- questions nouvelles à la source par jour, au plus
begin
  select x.nom into n from public.lieux_noms x
   where x.lat_g = public.grille_route(latitude) and x.lng_g = public.grille_route(longitude)
     and (x.source <> 'google' or x.cree_le > now() - interval '30 days');
  return jsonb_build_object('nom', n,
    'plafond_atteint', n is null and
      (select count(*) from public.lieux_noms x where x.cree_le > now() - interval '1 day')
      + coalesce((select r.n from public.lieux_recherches r where r.jour = current_date), 0) >= plafond);
end $$;
revoke all on function public.lieu_connu(double precision, double precision) from public, anon, authenticated;
grant execute on function public.lieu_connu(double precision, double precision) to service_role;

-- Noter : avec sa source. L'ancienne forme (trois arguments) s'en va : la
-- nouvelle la couvre (« la_source » vaut « osm » quand on ne la dit pas).
drop function if exists public.noter_lieu(double precision, double precision, text);
create or replace function public.noter_lieu(latitude double precision, longitude double precision, nom text,
  la_source text default 'osm')
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if latitude is null or longitude is null or coalesce(btrim(nom), '') = '' then return false; end if;
  insert into public.lieux_noms as x (lat_g, lng_g, nom, source)
  values (public.grille_route(latitude), public.grille_route(longitude), left(btrim(nom), 200),
          case when la_source = 'google' then 'google' else 'osm' end)
  on conflict (lat_g, lng_g) do update set nom = excluded.nom, source = excluded.source, cree_le = now();
  return true;
end $$;
revoke all on function public.noter_lieu(double precision, double precision, text, text) from public, anon, authenticated;
grant execute on function public.noter_lieu(double precision, double precision, text, text) to service_role;

-- ---------- 2. La clé des cartes ----------
create table if not exists public.cartes_reglage (
  id         int primary key default 1 check (id = 1),
  cle_tuiles text not null default '' check (length(cle_tuiles) <= 120),
  maj_le     timestamptz not null default now()
);
insert into public.cartes_reglage (id) values (1) on conflict (id) do nothing;
alter table public.cartes_reglage enable row level security;
revoke all on public.cartes_reglage from public, anon, authenticated;
grant select on public.cartes_reglage to anon, authenticated;
drop policy if exists "cartes lecture" on public.cartes_reglage;
create policy "cartes lecture" on public.cartes_reglage
  for select to anon, authenticated using (true);

-- Le superadministrateur seul la règle. Vide : les cartes d'OpenStreetMap.
-- Une clé de navigateur Google commence par « AIza » ; on refuse ce qui n'y
-- ressemble pas — surtout une clé secrète collée là par erreur.
create or replace function public.regler_cle_cartes(cle text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare c text := btrim(coalesce(cle, ''));
begin
  if auth.uid() is null or not public.est_super() then
    raise exception 'La clé des cartes est réglée par le superadministrateur.' using errcode = 'P0001';
  end if;
  if c <> '' and (length(c) not between 30 and 120 or left(c, 4) <> 'AIza' or c ~ '[^A-Za-z0-9_-]') then
    raise exception 'Cette clé ne ressemble pas à une clé de cartes Google (elle commence par « AIza »).'
      using errcode = 'P0001';
  end if;
  update public.cartes_reglage set cle_tuiles = c, maj_le = now() where id = 1;
  return c <> '';
end $$;
revoke all on function public.regler_cle_cartes(text) from public, anon;
grant execute on function public.regler_cle_cartes(text) to authenticated;
