-- =========================================================
-- BIZZOO 3.59.0 — Le code SMS : seulement le superadministrateur, et
-- l'appareil de confiance
--
--   1. Le code SMS de connexion n'est plus demandé qu'aux
--      SUPERADMINISTRATEURS, quand l'interrupteur est allumé (Réglages →
--      Code SMS du superadministrateur). Administrateurs, modérateurs,
--      livreurs et clients entrent avec leur mot de passe seul ;
--   2. « Faire confiance à cet appareil pendant 1 mois » : coché, le code
--      n'est plus demandé sur cet appareil pendant 30 jours
--      (confier_appareil, reconnaitre_appareil, oublier_appareils).
--
-- Les clients et livreurs qui entrent par leur numéro ne reçoivent plus de
-- code à chaque connexion — c'est l'application qui change ; le code reste
-- pour confirmer le numéro à l'inscription, et pour « mot de passe oublié ».
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
create or replace function public.session_confirmee() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.sessions_sms s
     where s.session_id = public.session_courante()
       and s.utilisateur = auth.uid())
  /* UN LIVREUR ENTRÉ PAR SON NUMÉRO a déjà rendu un code : celui de
     Supabase (numéro, mot de passe, puis code — 3.59.0). Le jeton le
     dit, signé par GoTrue : méthode « otp », numéro confirmé. Lui
     redemander le code de l'équipe, ce serait deux SMS pour une seule
     porte. Les autres rangs gardent leur code d'équipe, inchangé. */
  or (coalesce(auth.jwt() ->> 'phone', '') <> ''
      and exists (select 1 from jsonb_array_elements(
                    case when jsonb_typeof(auth.jwt() -> 'amr') = 'array'
                         then auth.jwt() -> 'amr' else '[]'::jsonb end) a
                   where a ->> 'method' = 'otp')
      and exists (select 1 from public.profils p
                   where p.id = auth.uid() and p.role = 'livreur'));
$$;


create or replace function public.session_courante() returns uuid
language sql stable as $$
  select case when s ~* '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z'
              then s::uuid end
    from (select coalesce(auth.jwt() ->> 'session_id', '') as s) x;
$$;


create or replace function public.sms_equipe_exige() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select s.sms_exige from public.securite_equipe s where s.id = 1), false);
$$;



create or replace function public.equipe_en_service() returns boolean
language sql stable security definer set search_path = public as $$
  select not public.sms_equipe_exige()
      or public.session_confirmee()
      or not exists (select 1 from public.profils p
                      where p.id = auth.uid() and p.role = 'superadministrateur');
$$;
revoke all on function public.session_courante() from public, anon;
revoke all on function public.sms_equipe_exige() from public, anon;
revoke all on function public.session_confirmee() from public, anon;
revoke all on function public.equipe_en_service() from public, anon;
grant execute on function public.session_courante() to authenticated;
grant execute on function public.sms_equipe_exige() to authenticated;
grant execute on function public.session_confirmee() to authenticated;
grant execute on function public.equipe_en_service() to authenticated;

create or replace function public.etat_connexion()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  p      public.profils%rowtype;
  numero text;
begin
  if auth.uid() is null then
    return jsonb_build_object('equipe', false, 'sms_exige', public.sms_equipe_exige());
  end if;
  select * into p from public.profils where id = auth.uid();
  if not found or not p.actif then
    return jsonb_build_object('equipe', false, 'sms_exige', public.sms_equipe_exige());
  end if;
  numero := regexp_replace(coalesce(p.tel, ''), '\D', '', 'g');
  return jsonb_build_object(
    'equipe', true,
    -- (3.59.0) Exigé de ce compte-ci : seul le superadministrateur
    -- rend un code.
    'sms_exige', public.sms_equipe_exige() and p.role = 'superadministrateur',
    'session_confirmee', public.session_confirmee(),
    'numero', length(numero) >= 8,
    'fin_numero', case when length(numero) >= 8 then right(numero, 2) else '' end,
    'tel_verifie', p.tel_verifie);
end $$;
revoke all on function public.etat_connexion() from public, anon;
grant execute on function public.etat_connexion() to authenticated;

create or replace function public.regler_sms_equipe(exige boolean)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  voulu boolean := coalesce(exige, false);
  qui   text;
begin
  if not public.est_super() then
    raise exception 'Réservé au superadministrateur';
  end if;
  if voulu and not public.session_confirmee() then
    raise exception 'Recevez et saisissez d''abord votre propre code : c''est la preuve que le SMS arrive, avant de l''exiger des superadministrateurs.';
  end if;
  select coalesce(nullif(trim(p.nom), ''), p.email, '') into qui
    from public.profils p where p.id = auth.uid();
  insert into public.securite_equipe (id, sms_exige, change_le, change_par)
  values (1, voulu, now(), coalesce(qui, ''))
  on conflict (id) do update
    set sms_exige = excluded.sms_exige,
        change_le = excluded.change_le,
        change_par = excluded.change_par;
  -- Au journal, au nom de celui qui décide : la ligne y est écrite par
  -- la base, pas par l'écran.
  insert into public.journal (famille, action, libelle, cible)
  values ('compte', 'modification',
          case when voulu
               then 'Connexion du superadministrateur : code SMS exigé (sauf appareil de confiance)'
               else 'Connexion du superadministrateur : code SMS plus exigé' end,
          '');
  return voulu;
end $$;
revoke all on function public.regler_sms_equipe(boolean) from public, anon;
grant execute on function public.regler_sms_equipe(boolean) to authenticated;



-- ---------- Les appareils de confiance (3.59.0) ----------
--
-- Le superadministrateur qui coche « Faire confiance à cet appareil »
-- n'y rend plus son code pendant 30 jours. L'appareil garde un jeton
-- tiré au hasard ; la base n'en garde que l'EMPREINTE — une copie de la
-- base ne permet pas de se faire passer pour l'appareil. Le mot de passe
-- reste demandé à chaque connexion : la confiance ne remplace que le SMS.
create table if not exists public.appareils_confiance (
  id          bigserial primary key,
  utilisateur uuid not null references auth.users(id) on delete cascade,
  empreinte   text not null,
  appareil    text not null default '',
  cree_le     timestamptz not null default now(),
  expire_le   timestamptz not null,
  constraint appareils_confiance_un unique (utilisateur, empreinte)
);
alter table public.appareils_confiance enable row level security;
revoke all on public.appareils_confiance from public, anon, authenticated;
revoke all on sequence public.appareils_confiance_id_seq from public, anon, authenticated;

-- Après le code : cet appareil devient de confiance pour 30 jours.
create or replace function public.confier_appareil(jeton text, appareil text default '')
returns timestamptz
language plpgsql security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  fin timestamptz := now() + interval '30 days';
begin
  if moi is null then raise exception 'Connectez-vous'; end if;
  if length(coalesce(jeton, '')) < 32 then raise exception 'Jeton d''appareil invalide'; end if;
  if not public.session_confirmee() then
    raise exception 'Saisissez d''abord le code reçu par SMS.' using errcode = 'P0001';
  end if;
  insert into public.appareils_confiance (utilisateur, empreinte, appareil, expire_le)
  values (moi, encode(sha256(convert_to(jeton, 'UTF8')), 'hex'), left(coalesce(appareil, ''), 120), fin)
  on conflict (utilisateur, empreinte) do update
    set expire_le = excluded.expire_le, cree_le = now(), appareil = excluded.appareil;
  return fin;
end $$;
revoke all on function public.confier_appareil(text, text) from public, anon;
grant execute on function public.confier_appareil(text, text) to authenticated;

-- À la connexion : un appareil de confiance encore valable confirme la
-- session sans SMS. Faux sinon — l'écran demande alors le code.
create or replace function public.reconnaitre_appareil(jeton text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  moi     uuid := auth.uid();
  session uuid := public.session_courante();
begin
  if moi is null or session is null or length(coalesce(jeton, '')) < 32 then return false; end if;
  if not exists (select 1 from public.appareils_confiance a
                  where a.utilisateur = moi
                    and a.empreinte = encode(sha256(convert_to(jeton, 'UTF8')), 'hex')
                    and a.expire_le > now()) then
    return false;
  end if;
  insert into public.sessions_sms (session_id, utilisateur)
  values (session, moi) on conflict (session_id) do nothing;
  return true;
end $$;
revoke all on function public.reconnaitre_appareil(text) from public, anon;
grant execute on function public.reconnaitre_appareil(text) to authenticated;

-- « Oublier mes appareils de confiance » : le code sera redemandé
-- partout, à la prochaine connexion.
create or replace function public.oublier_appareils()
returns int
language plpgsql security definer set search_path = public as $$
declare combien int;
begin
  if auth.uid() is null then raise exception 'Connectez-vous'; end if;
  update public.appareils_confiance a
     set expire_le = now() - interval '1 second'
   where a.utilisateur = auth.uid() and a.expire_le > now();
  get diagnostics combien = row_count;
  return combien;
end $$;
revoke all on function public.oublier_appareils() from public, anon;
grant execute on function public.oublier_appareils() to authenticated;

-- Combien d'appareils de confiance encore valables : l'écran du compte
-- le dit, et propose de les oublier.
create or replace function public.mes_appareils_confiance()
returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from public.appareils_confiance a
   where a.utilisateur = auth.uid() and a.expire_le > now();
$$;
revoke all on function public.mes_appareils_confiance() from public, anon;
grant execute on function public.mes_appareils_confiance() to authenticated;
