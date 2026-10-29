-- =========================================================
-- BIZZOO 3.70.0 — Le livreur « disponible » : sa position, application fermée
--
--   La course va d'abord au livreur le plus proche (cascade-courses.sql).
--   Pour savoir qui est le plus proche, il faut des positions fraîches —
--   même quand le livreur n'a pas l'application ouverte :
--     - BIZZOO Admin → Livraisons : « Disponible pour les courses »
--       (allumé par défaut ; le livreur l'éteint en fin de journée) ;
--     - allumé, le service Android de BIZZOO Admin 3.70.0 envoie sa position
--       toutes les 3 minutes, application fermée (« position_livreur »),
--       toutes les 20 secondes pendant une course ;
--     - éteint, plus de position hors course, et il ne fait plus partie des
--       trois plus proches.
--   BIZZOO Admin 3.68.0 (déjà installé) n'appelle pas « position_livreur » :
--   rien ne change pour lui.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

alter table public.profils add column if not exists disponible boolean not null default true;

-- (3.70.0) Lues par les fonctions plus bas (déjà là sur une base en service).
create table if not exists public.refus_courses (
  id          bigserial primary key,
  commande_id text not null references public.commandes(id) on delete cascade,
  boutique_id text not null references public.boutiques(id) on delete cascade,
  livreur_id  uuid references public.profils(id) on delete set null,
  motif       text not null default '',
  refuse_le   timestamptz not null default now()
);
create index if not exists refus_courses_commande on public.refus_courses(commande_id, refuse_le desc);
alter table public.refus_courses enable row level security;
revoke all on public.refus_courses from anon, authenticated;
revoke all on sequence public.refus_courses_id_seq from anon, authenticated;

create table if not exists public.cascade_reglage (
  id            int primary key default 1 check (id = 1),
  actif         boolean not null default true,
  delai_s       int not null default 30 check (delai_s between 10 and 600),
  rangs         int not null default 3 check (rangs between 1 and 10),
  fraicheur_min int not null default 60 check (fraicheur_min between 5 and 1440)
);
insert into public.cascade_reglage (id) values (1) on conflict (id) do nothing;
alter table public.cascade_reglage enable row level security;
revoke all on public.cascade_reglage from anon, authenticated;

-- Où en est la course : qui a été alerté, dans quel ordre, et quand passer
-- au suivant. Une ligne par commande ; un nouveau tour (course annulée par
-- son livreur) la remet à zéro.
create table if not exists public.courses_cascade (
  commande_id text primary key references public.commandes(id) on delete cascade,
  ordre       uuid[] not null default '{}',
  etape       int not null default 0,
  tous        boolean not null default false,
  alertes     uuid[] not null default '{}',
  prochaine   timestamptz,
  lancee_le   timestamptz not null default now(),
  reprise     boolean not null default false
);
create index if not exists courses_cascade_prochaine on public.courses_cascade (prochaine)
  where prochaine is not null;
alter table public.courses_cascade enable row level security;
revoke all on public.courses_cascade from anon, authenticated;

-- Le point d'où l'on mesure : la boutique où récupérer (la première qui a
-- une position, en livraison groupée), sinon le point BIZZOO.

create table if not exists public.suivis_livreurs (
  profil_id   uuid primary key references public.profils(id) on delete cascade,
  jeton_hash  text not null,
  expire_le   timestamptz not null,
  cree_le     timestamptz not null default now()
);
alter table public.suivis_livreurs enable row level security;
-- Aucune règle : personne ne lit ni n'écrit la table, sinon ces fonctions.
revoke all on table public.suivis_livreurs from public, anon, authenticated;
-- (3.70.0) L'ancien jeton reste valable 10 minutes après un renouvellement.
alter table public.suivis_livreurs add column if not exists jeton_hash_precedent text;
alter table public.suivis_livreurs add column if not exists precedent_expire_le timestamptz;

-- (3.70.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.candidats_course(commande text)
returns uuid[]
language plpgsql stable security definer set search_path = public as $$
declare
  boutiques text[];
  qui       uuid[];
  besoin    text;
  vs        text[];
  v         text;
begin
  select array_agg(distinct l.boutique_id) into boutiques
    from public.commande_lignes l
   where l.commande_id = commande and l.etat <> 'annulee' and l.boutique_id is not null;
  if boutiques is null then return '{}'; end if;
  select c.livraison ->> 'vehicule' into besoin from public.commandes c where c.id = commande;
  vs := case besoin when 'tricycle' then array['tricycle']
                    when 'moto' then array['moto', 'tricycle']
                    else array[null::text] end;
  if array_length(boutiques, 1) = 1 then
    foreach v in array vs loop
      select array_agg(p.id order by p.id) into qui
        from public.profils p
       where p.role = 'livreur' and p.actif and not p.courses_bloquees and p.boutique_id = boutiques[1]
         and (v is null or p.vehicule = v)
         and exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id)
         -- (3.70.0) Ceux qui l'ont refusée ne comptent plus : si toute la
         -- boutique l'a refusée, elle passe aux tricycles, puis à BIZZOO.
         and not exists (select 1 from public.refus_courses r
                          where r.commande_id = commande and r.livreur_id = p.id);
      if qui is not null then return qui; end if;
    end loop;
  end if;
  foreach v in array vs loop
    select array_agg(p.id order by p.id) into qui
      from public.profils p
     where p.role = 'livreur' and p.actif and not p.courses_bloquees and p.boutique_id is null
       and (v is null or p.vehicule = v)
       and exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id)
       and not exists (select 1 from public.refus_courses r
                        where r.commande_id = commande and r.livreur_id = p.id);
    if qui is not null then return qui; end if;
  end loop;
  return '{}';
end $$;
revoke all on function public.candidats_course(text) from public, anon, authenticated;

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

create or replace function public.est_livreur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'livreur', false);
$$;
revoke all on function public.est_livreur() from public, anon, authenticated;
grant execute on function public.est_livreur() to authenticated;

create or replace function public.livreur_en_course(qui uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
     where l.livreur_id = qui and c.etat = 'payee'
       and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison'));
$$;
revoke all on function public.livreur_en_course(uuid) from public, anon, authenticated;

create or replace function public.point_retrait_course(commande text,
  out lat double precision, out lng double precision)
language plpgsql stable security definer set search_path = public as $$
begin
  select b.latitude, b.longitude into lat, lng
    from public.commande_lignes l join public.boutiques b on b.id = l.boutique_id
   where l.commande_id = commande and l.etat <> 'annulee'
     and b.latitude is not null and b.longitude is not null
   order by b.id limit 1;
  if lat is null then
    select p.livraison_latitude, p.livraison_longitude into lat, lng
      from public.paiement p where p.id = 1;
  end if;
end $$;
revoke all on function public.point_retrait_course(text) from public, anon, authenticated;

create or replace function public.tous_livreurs_course(commande text)
returns uuid[]
language plpgsql stable security definer set search_path = public as $$
declare besoin text;
begin
  select c.livraison ->> 'vehicule' into besoin from public.commandes c where c.id = commande;
  return coalesce((
    select array_agg(distinct x.id order by x.id) from (
      select unnest(public.candidats_course(commande)) as id
      union
      select p.id from public.profils p
       where p.role = 'livreur' and p.actif and not p.courses_bloquees and p.boutique_id is null
         and (besoin is null or besoin not in ('moto', 'tricycle')
              or p.vehicule = besoin or (besoin = 'moto' and p.vehicule = 'tricycle'))
         and exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id)
         and not exists (select 1 from public.refus_courses r
                          where r.commande_id = commande and r.livreur_id = p.id)) x), '{}');
end $$;
revoke all on function public.tous_livreurs_course(text) from public, anon, authenticated;

-- Empruntées par les fonctions plus bas, recopiées telles quelles.
-- ---------- Ce que ce fichier change ----------
create or replace function public.fermer_suivi_livreur(tout boolean default false)
returns boolean
language plpgsql security definer set search_path = public as $$
declare moi uuid := auth.uid();
begin
  if moi is null or not public.est_livreur() then return false; end if;
  if not coalesce(tout, false)
     and (public.livreur_en_course(moi)
          or exists (select 1 from public.profils p
                      where p.id = moi and p.disponible and not p.courses_bloquees)) then
    return false;
  end if;
  delete from public.suivis_livreurs where profil_id = moi;
  return found;
end $$;
revoke all on function public.fermer_suivi_livreur(boolean) from public, anon;
grant execute on function public.fermer_suivi_livreur(boolean) to authenticated;

create or replace function public.position_en_course(jeton text, lat double precision,
  lng double precision, precision_m int default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  qui uuid;
  la double precision := public.coord_valable(lat, 90);
  lo double precision := public.coord_valable(lng, 180);
  derniere timestamptz;
begin
  select s.profil_id into qui from public.suivis_livreurs s
   where (s.jeton_hash = encode(sha256(convert_to(coalesce(jeton, ''), 'UTF8')), 'hex')
          and s.expire_le > now())
      -- (3.70.0) L'ancien jeton, 10 minutes après un renouvellement.
      or (s.jeton_hash_precedent = encode(sha256(convert_to(coalesce(jeton, ''), 'UTF8')), 'hex')
          and s.precedent_expire_le > now());
  if qui is null then
    raise exception 'Suivi expiré : ouvrez BIZZOO Admin pour le reprendre.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profils p where p.id = qui and p.actif and p.role = 'livreur') then
    delete from public.suivis_livreurs where profil_id = qui;
    return jsonb_build_object('continuer', false);
  end if;
  if not public.livreur_en_course(qui) then
    delete from public.suivis_livreurs where profil_id = qui;
    return jsonb_build_object('continuer', false);
  end if;
  if la is null or lo is null or (la = 0 and lo = 0) then
    return jsonb_build_object('continuer', true);
  end if;
  -- Pas plus d'une écriture toutes les 5 secondes.
  select enregistre_le into derniere from public.positions_livreurs where profil_id = qui;
  if derniere is null or derniere < now() - interval '5 seconds' then
    insert into public.positions_livreurs (profil_id, latitude, longitude, precision_m, adresse, enregistre_le)
    values (qui, la, lo, greatest(0, precision_m), '', now())
    on conflict (profil_id) do update
       set latitude = excluded.latitude, longitude = excluded.longitude,
           precision_m = excluded.precision_m, enregistre_le = now();
  end if;
  return jsonb_build_object('continuer', true);
end $$;
revoke all on function public.position_en_course(text, double precision, double precision, int) from public;
grant execute on function public.position_en_course(text, double precision, double precision, int)
  to anon, authenticated;

create or replace function public.signaler_ma_position(
  lat double precision, lng double precision, precision_m int default null)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  la  double precision := public.coord_valable(lat, 90);
  lo  double precision := public.coord_valable(lng, 180);
begin
  if moi is null or not public.est_livreur() then return false; end if;
  if la is null or lo is null or (la = 0 and lo = 0) then return false; end if;
  -- (3.70.0) « Pas disponible » et sans course : sa position ne part pas.
  if exists (select 1 from public.profils p where p.id = moi and not p.disponible)
     and not public.livreur_en_course(moi) then
    return false;
  end if;
  update public.positions_livreurs
     set latitude = la, longitude = lo, precision_m = greatest(0, signaler_ma_position.precision_m),
         enregistre_le = now()
   where profil_id = moi and enregistre_le < now() - interval '30 seconds';
  return found;
end $$;
revoke all on function public.signaler_ma_position(double precision, double precision, int) from public, anon;
grant execute on function public.signaler_ma_position(double precision, double precision, int) to authenticated;

create or replace function public.position_livreur(jeton text, lat double precision,
  lng double precision, precision_m int default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  qui uuid;
  p   public.profils%rowtype;
  la  double precision := public.coord_valable(lat, 90);
  lo  double precision := public.coord_valable(lng, 180);
  en_course boolean;
  derniere timestamptz;
  pas      interval;
begin
  select s.profil_id into qui from public.suivis_livreurs s
   where (s.jeton_hash = encode(sha256(convert_to(coalesce(jeton, ''), 'UTF8')), 'hex')
          and s.expire_le > now())
      or (s.jeton_hash_precedent = encode(sha256(convert_to(coalesce(jeton, ''), 'UTF8')), 'hex')
          and s.precedent_expire_le > now());
  if qui is null then
    raise exception 'Suivi expiré : ouvrez BIZZOO Admin pour le reprendre.' using errcode = '42501';
  end if;
  select * into p from public.profils x where x.id = qui;
  if not found or not p.actif or p.role <> 'livreur' then
    delete from public.suivis_livreurs where profil_id = qui;
    return jsonb_build_object('continuer', false, 'en_course', false);
  end if;
  en_course := public.livreur_en_course(qui);
  if not en_course and (not coalesce(p.disponible, true) or p.courses_bloquees) then
    -- Le suivi s'arrête : « Localiser un livreur » ne le montre plus actif.
    delete from public.suivis_livreurs where profil_id = qui;
    return jsonb_build_object('continuer', false, 'en_course', false);
  end if;
  -- APPLICATION FERMÉE DES JOURS DURANT : tant que le téléphone se manifeste,
  -- le jeton ne meurt pas (16 heures après le dernier signe ; une écriture
  -- par heure au plus).
  update public.suivis_livreurs set expire_le = now() + interval '16 hours'
   where profil_id = qui and expire_le < now() + interval '15 hours';
  if la is null or lo is null or (la = 0 and lo = 0) then
    return jsonb_build_object('continuer', true, 'en_course', en_course);
  end if;
  -- Pas plus d'une écriture toutes les 5 secondes en course, toutes les 30
  -- secondes libre. Seule une position déjà là (compte validé) se met à jour.
  select pl.enregistre_le into derniere from public.positions_livreurs pl where pl.profil_id = qui;
  pas := case when en_course then interval '5 seconds' else interval '30 seconds' end;
  if derniere is not null and derniere < now() - pas then
    update public.positions_livreurs
       set latitude = la, longitude = lo, precision_m = greatest(0, position_livreur.precision_m),
           enregistre_le = now()
     where profil_id = qui;
  end if;
  return jsonb_build_object('continuer', true, 'en_course', en_course);
end $$;
revoke all on function public.position_livreur(text, double precision, double precision, int) from public;
grant execute on function public.position_livreur(text, double precision, double precision, int)
  to anon, authenticated;

create or replace function public.regler_disponibilite(dispo boolean)
returns boolean
language plpgsql security definer set search_path = public as $$
declare moi uuid := auth.uid();
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Réservé aux livreurs.' using errcode = '42501';
  end if;
  update public.profils set disponible = coalesce(dispo, true) where id = moi;
  -- Éteint et sans course : le suivi s'arrête aussi en base.
  if not coalesce(dispo, true) and not public.livreur_en_course(moi) then
    delete from public.suivis_livreurs where profil_id = moi;
  end if;
  return coalesce(dispo, true);
end $$;
revoke all on function public.regler_disponibilite(boolean) from public, anon;
grant execute on function public.regler_disponibilite(boolean) to authenticated;

create or replace function public.ouvrir_suivi_livreur() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  jeton text;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Seul un livreur ouvre un suivi de position.' using errcode = '42501';
  end if;
  -- (3.70.0) Rien à suivre — ni course, ni « disponible » — : pas de jeton,
  -- et « Localiser un livreur » ne le montre pas suivi.
  if not public.livreur_en_course(moi)
     and not exists (select 1 from public.profils p
                      where p.id = moi and p.disponible and not p.courses_bloquees) then
    delete from public.suivis_livreurs where profil_id = moi;
    return jsonb_build_object('jeton', null, 'en_course', false, 'disponible', false);
  end if;
  jeton := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into public.suivis_livreurs as s (profil_id, jeton_hash, expire_le, cree_le)
  values (moi, encode(sha256(convert_to(jeton, 'UTF8')), 'hex'), now() + interval '16 hours', now())
  on conflict (profil_id) do update
     set jeton_hash = excluded.jeton_hash, expire_le = excluded.expire_le, cree_le = now(),
         -- (3.70.0) L'ancien reste bon 10 minutes, s'il l'était encore.
         jeton_hash_precedent = case when s.expire_le > now() then s.jeton_hash end,
         precedent_expire_le = case when s.expire_le > now() then now() + interval '10 minutes' end;
  return jsonb_build_object('jeton', jeton, 'en_course', public.livreur_en_course(moi),
                            -- (3.70.0) Libre mais disponible (et pas suspendu) : le
                            -- téléphone suit aussi. Une base d'avant ne le dit pas.
                            'disponible', coalesce((select p.disponible and not p.courses_bloquees
                                                      from public.profils p where p.id = moi), true),
                            'expire_le', now() + interval '16 hours');
end $$;
revoke all on function public.ouvrir_suivi_livreur() from public, anon;
grant execute on function public.ouvrir_suivi_livreur() to authenticated;

create or replace function public.plus_proches_course(commande text, combien int)
returns uuid[]
language plpgsql stable security definer set search_path = public as $$
declare
  pt     record;
  fraich int;
  boutq  uuid[];
begin
  select * into pt from public.point_retrait_course(commande);
  select coalesce(r.fraicheur_min, 60) into fraich from public.cascade_reglage r where r.id = 1;
  boutq := public.candidats_course(commande);
  return coalesce((
    select array_agg(x.id order by x.rang, x.km nulls last, x.id)
      from (select p.id,
                   -- Ceux qui pouvaient déjà la prendre (sa boutique) d'abord.
                   case when p.id = any(boutq) then 0 else 1 end as rang,
                   case when pt.lat is null then null else
                     2 * 6371 * asin(least(1, sqrt(
                       sin(radians(pl.latitude - pt.lat) / 2) ^ 2
                       + cos(radians(pt.lat)) * cos(radians(pl.latitude))
                         * sin(radians(pl.longitude - pt.lng) / 2) ^ 2))) end as km
              from unnest(public.tous_livreurs_course(commande)) as c(id)
              join public.profils p on p.id = c.id
              join public.positions_livreurs pl on pl.profil_id = p.id
             where pl.enregistre_le > now() - make_interval(mins => coalesce(fraich, 60))
               -- (3.70.0) « Pas disponible » : jamais parmi les plus proches.
               and p.disponible
               and not public.livreur_en_course(p.id)
             order by 2, 3 nulls last, 1
             limit greatest(coalesce(combien, 3), 0)) x), '{}');
end $$;
revoke all on function public.plus_proches_course(text, int) from public, anon, authenticated;
