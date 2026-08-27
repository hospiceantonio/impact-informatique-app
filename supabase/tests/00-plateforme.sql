-- =========================================================
-- Le décor : ce que Supabase fournit, et que PostgreSQL nu
-- ne connaît pas.
--
-- Les rôles « anon » et « authenticated », le schéma « auth »
-- avec sa fonction uid(), le stockage, la publication temps
-- réel. Rien ici ne part chez le client : ce fichier n'existe
-- que pour éprouver schema.sql sur un vrai moteur.
--
-- On simule le décor, JAMAIS les règles qu'on veut éprouver :
-- RLS, déclencheurs et fonctions viennent tels quels de
-- schema.sql. C'est toute la différence avec une base
-- simulée en JavaScript, qui ne pouvait rien dire des
-- déclencheurs — ils ne s'exécutent que pour de vrai.
-- =========================================================

create extension if not exists pgcrypto;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end $$;

create schema if not exists auth;
create schema if not exists storage;

create table if not exists auth.users (
  id                 uuid primary key default gen_random_uuid(),
  email              text,
  encrypted_password text,
  cree_le            timestamptz not null default now()
);

-- Le compte connecté, tel que PostgREST le pose sur la session.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create table if not exists storage.buckets (
  id text primary key, name text, public boolean default false,
  file_size_limit bigint, allowed_mime_types text[]);
-- Les colonnes sont celles de Supabase, « metadata » comprise : c'est là
-- qu'est rangé le poids d'un fichier, et l'état des lieux du stockage le
-- lit. Une colonne oubliée ici, et le fichier passerait le banc pour
-- échouer chez le gérant.
create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text, name text, owner uuid,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  last_accessed_at timestamptz default now(),
  metadata jsonb,
  path_tokens text[] generated always as (string_to_array(name, '/')) stored);

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

grant usage on schema public, auth, storage to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables    to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;

-- ---------------------------------------------------------
-- Les outils de l'essai
-- ---------------------------------------------------------
create schema if not exists essai;
grant usage on schema essai to anon, authenticated, service_role;

-- Un échec porte son propre code : il ne doit jamais être confondu
-- avec le refus qu'on cherchait justement à provoquer.
create or replace function essai.echec(quoi text) returns void
language plpgsql as $$
begin
  raise exception '%', quoi using errcode = 'BZ001';
end $$;

/** Ce qui doit être vrai. */
create or replace function essai.verifie(vrai boolean, quoi text) returns void
language plpgsql as $$
begin
  if coalesce(vrai, false) then
    raise notice '  ok    %', quoi;
  else
    perform essai.echec('ÉCHEC : ' || quoi);
  end if;
end $$;

/** Deux valeurs qui doivent coïncider — le message dit lesquelles. */
create or replace function essai.egal(obtenu anyelement, attendu anyelement, quoi text)
returns void language plpgsql as $$
begin
  if obtenu is not distinct from attendu then
    raise notice '  ok    % (%)', quoi, obtenu;
  else
    perform essai.echec('ÉCHEC : ' || quoi || ' — obtenu ' ||
      coalesce(obtenu::text, 'null') || ', attendu ' || coalesce(attendu::text, 'null'));
  end if;
end $$;

/**
 * Ce que la base doit REFUSER. Le test ne passe que si la requête
 * échoue : une base qui laisse passer est un test qui échoue.
 */
create or replace function essai.refuse(requete text, quoi text) returns void
language plpgsql as $$
begin
  begin
    execute requete;
  exception
    when sqlstate 'BZ001' then raise;          -- notre propre échec, pas un refus
    when others then
      raise notice '  ok    % — refusé : %', quoi, left(sqlerrm, 66);
      return;
  end;
  perform essai.echec('ÉCHEC : ' || quoi || ' — la base a LAISSÉ PASSER');
end $$;

/**
 * Ce qui ne doit RIEN toucher. Une règle de sécurité ne lève pas
 * toujours d'erreur : sur une modification, elle écarte silencieusement
 * les lignes qu'on n'a pas le droit de voir. Zéro ligne touchée est donc
 * un succès, et non un aveu d'impuissance du test.
 */
create or replace function essai.sans_effet(requete text, quoi text) returns void
language plpgsql as $$
declare touchees int;
begin
  execute requete;
  get diagnostics touchees = row_count;
  if touchees = 0 then
    raise notice '  ok    % — sans effet', quoi;
  else
    perform essai.echec('ÉCHEC : ' || quoi || ' — ' || touchees || ' ligne(s) touchée(s)');
  end if;
exception
  when sqlstate 'BZ001' then raise;
  when others then
    raise notice '  ok    % — refusé : %', quoi, left(sqlerrm, 60);
end $$;

/** Se faire passer pour un compte donné, comme le ferait un jeton. */
create or replace function essai.devenir(compte uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(compte::text, ''), false);
end $$;

/** Redevenir un visiteur : personne, aucun jeton. */
create or replace function essai.personne() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', false);
end $$;

grant execute on all functions in schema essai to anon, authenticated, service_role;

create or replace function essai.titre(quoi text) returns void
language plpgsql as $$
begin
  raise notice '';
  raise notice '== %', quoi;
end $$;
