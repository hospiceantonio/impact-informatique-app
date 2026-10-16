-- =========================================================
-- BIZZOO — le live TikTok
--
-- « Démarrer le live TikTok » dans BIZZOO Admin : la base enregistre le
-- live, la fonction Edge « annoncer-live » envoie la notification à
-- tous les téléphones, et l'application montre un bandeau « En live ».
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
-- Sans danger : relançable.
-- =========================================================
-- =========================================================
-- Une boutique passe en direct sur TikTok : son administrateur touche
-- « Démarrer le live TikTok ». Tous les téléphones où l'application
-- BIZZOO est installée reçoivent une notification ; la toucher ouvre la
-- page TikTok de la boutique. Dans l'application et sur le site, un
-- bandeau « En live » le dit aussi tant que le live dure.
--
-- La base tient le live et décide QUI peut le lancer ; l'envoi de la
-- notification est l'affaire de la fonction Edge « annoncer-live », qui
-- seule détient le compte de service Firebase.
--
-- GARDE-FOUS. Une notification à tous les clients, c'est lourd : un live
-- déjà en cours ne se relance pas (pas de seconde notification), et une
-- boutique n'annonce pas plus de trois lives par jour. Un live oublié
-- s'éteint de lui-même au bout de quatre heures.

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

create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false)
     and public.role_courant() is not null;
$$;

create or replace function public.administre(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.droit_enseigne('boutiques')
      or (public.est_admin() and cible is not null
          and cible = public.boutique_du_compte());
$$;

create table if not exists public.lives_tiktok (
  id          bigint generated always as identity primary key,
  boutique_id text not null references public.boutiques(id) on delete cascade,
  lien        text not null,
  debut       timestamptz not null default now(),
  fin         timestamptz,
  lance_par   uuid,
  annonce_le  timestamptz,
  annonce     text not null default ''
);
create index if not exists lives_tiktok_boutique on public.lives_tiktok(boutique_id, debut desc);

-- Personne ne lit la table directement : « lives_en_cours » en dit ce
-- qu'un client doit savoir, et rien de qui l'a lancé.
alter table public.lives_tiktok enable row level security;
revoke all on public.lives_tiktok from anon, authenticated;

-- Le lien TikTok d'une boutique, tel qu'un navigateur l'ouvre :
-- « @maboutique », « maboutique » ou une adresse complète.
create or replace function public.lien_tiktok(brut text) returns text
language sql immutable as $$
  select case
    when coalesce(trim(brut), '') = '' then ''
    when trim(brut) ~* '^https?://' then trim(brut)
    when trim(brut) ~* '^(www\.)?tiktok\.com/' then 'https://' || trim(brut)
    else 'https://www.tiktok.com/@' || regexp_replace(trim(brut), '^@+', '')
  end;
$$;

create or replace function public.lives_en_cours()
returns table (boutique_id text, nom text, lien text, debut timestamptz)
language sql stable security definer set search_path = public as $$
  select l.boutique_id, b.nom, l.lien, l.debut
    from public.lives_tiktok l
    join public.boutiques b on b.id = l.boutique_id and b.actif
   where l.fin is null and l.debut > now() - interval '4 hours'
   order by l.debut desc;
$$;
revoke all on function public.lives_en_cours() from public;
grant execute on function public.lives_en_cours() to anon, authenticated;

create or replace function public.demarrer_live(cible text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  b       public.boutiques%rowtype;
  lien    text;
  courant public.lives_tiktok%rowtype;
  nouveau bigint;
begin
  if not public.administre(cible) then
    raise exception 'Seul l''administrateur de la boutique lance son live.' using errcode = '42501';
  end if;
  select * into b from public.boutiques where id = cible;
  if not found then raise exception 'Boutique introuvable.' using errcode = 'P0001'; end if;
  if not b.actif then
    raise exception 'La boutique est fermée aux clients : ouvrez-la avant d''annoncer un live.'
      using errcode = 'P0001';
  end if;
  lien := public.lien_tiktok(b.tiktok);
  if lien = '' then
    raise exception 'Ajoutez d''abord le compte TikTok de la boutique (Réglages → Réseaux sociaux).'
      using errcode = 'P0001';
  end if;
  -- On ne lance pas deux fois le même live : pas de seconde notification.
  perform pg_advisory_xact_lock(hashtext('live:' || cible));
  select * into courant from public.lives_tiktok
   where boutique_id = cible and fin is null and debut > now() - interval '4 hours'
   order by debut desc limit 1;
  if found then
    return jsonb_build_object('id', courant.id, 'boutique', cible, 'nom', b.nom,
      'lien', courant.lien, 'deja', true);
  end if;
  if (select count(*) from public.lives_tiktok
       where boutique_id = cible and debut > now() - interval '24 hours') >= 3 then
    raise exception 'Trois lives annoncés en 24 heures : c''est le maximum, pour ne pas lasser les clients.'
      using errcode = 'P0001';
  end if;
  -- Un live oublié depuis plus de quatre heures se ferme ici.
  update public.lives_tiktok set fin = now() where boutique_id = cible and fin is null;
  insert into public.lives_tiktok (boutique_id, lien, lance_par)
  values (cible, lien, auth.uid()) returning id into nouveau;
  return jsonb_build_object('id', nouveau, 'boutique', cible, 'nom', b.nom,
    'lien', lien, 'deja', false);
end $$;
revoke all on function public.demarrer_live(text) from public, anon;
grant execute on function public.demarrer_live(text) to authenticated;

create or replace function public.arreter_live(cible text) returns int
language plpgsql security definer set search_path = public as $$
declare combien int;
begin
  if not public.administre(cible) then
    raise exception 'Seul l''administrateur de la boutique arrête son live.' using errcode = '42501';
  end if;
  update public.lives_tiktok set fin = now() where boutique_id = cible and fin is null;
  get diagnostics combien = row_count;
  return combien;
end $$;
revoke all on function public.arreter_live(text) from public, anon;
grant execute on function public.arreter_live(text) to authenticated;

-- La fonction Edge note ce qu'a répondu Firebase. Clé de service seule :
-- personne d'autre n'écrit qu'un live a été annoncé.
create or replace function public.noter_annonce_live(cible bigint, resultat text) returns void
language sql security definer set search_path = public as $$
  update public.lives_tiktok
     set annonce_le = now(), annonce = left(coalesce(resultat, ''), 300)
   where id = cible;
$$;
revoke all on function public.noter_annonce_live(bigint, text) from public, anon, authenticated;
grant execute on function public.noter_annonce_live(bigint, text) to service_role;
