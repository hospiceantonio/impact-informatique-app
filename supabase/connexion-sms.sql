-- =========================================================
-- BIZZOO — la connexion confirmée par SMS, et qui a créé
-- quel compte (3.58.0)
--
-- CE QUE ÇA CHANGE.
--
--   1. L'ÉQUIPE REÇOIT UN CODE À CHAQUE CONNEXION — quand vous
--      l'exigez. Administrateurs, modérateurs, livreurs gardent
--      leur e-mail et leur mot de passe ; s'y ajoute un code envoyé
--      par SMS au numéro enregistré dans Comptes. Tant qu'il n'est
--      pas saisi, la session n'a AUCUN droit : la base le refuse,
--      pas seulement l'écran.
--
--   2. RIEN NE CHANGE TANT QUE VOUS N'ALLUMEZ PAS l'interrupteur
--      (admin → Réglages → Connexion de l'équipe par SMS). Il ne
--      s'allume qu'après avoir reçu et saisi votre propre code :
--      la preuve que le SMS arrive, avant de l'exiger de tous.
--
--   3. QUI A CRÉÉ QUEL COMPTE, ET QUAND. La base le note elle-même
--      au moment de la création. Pour les comptes d'avant, elle le
--      reprend du journal ; un compte créé hors de l'application
--      (tableau de bord Supabase) reste sans créateur, et l'écran
--      le dit.
--
-- En cas d'urgence — plus de crédit SMS, plus personne n'entre —,
-- ici même, dans l'éditeur SQL :
--     update public.securite_equipe set sms_exige = false;
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, et aucune donnée n'est supprimée.
-- =========================================================

-- (3.63.0) Les règles de « profils » lisent ces colonnes.
alter table public.profils add column if not exists cree_par uuid;
alter table public.profils add column if not exists a_valider boolean not null default false;

-- ---------- La session de l'équipe, confirmée par SMS ----------
-- Quand l'enseigne l'exige, un compte de l'équipe reçoit un code par SMS
-- à CHAQUE connexion, et n'a aucun droit tant qu'il ne l'a pas rendu.
-- Le détail — l'envoi, la saisie, l'interrupteur — est au chapitre « La
-- connexion de l'équipe confirmée par SMS », à la fin de ce fichier.
-- Seul ce qui suit doit vivre ICI, avant « role_courant() » : la base
-- vérifie déjà des droits pendant que ce fichier se charge, et la
-- fonction doit trouver tout ce qu'elle lit déjà posé.
--
-- L'INTERRUPTEUR VIT À PART, pas dans « reglages » : cette table-là n'est
-- posée que bien plus loin. Il part éteint — rien ne change tant qu'un
-- superadministrateur ne l'a pas allumé.
create table if not exists public.securite_equipe (
  id         int primary key default 1 check (id = 1),
  sms_exige  boolean not null default false,
  change_le  timestamptz,
  change_par text not null default ''
);
insert into public.securite_equipe (id) values (1) on conflict (id) do nothing;

-- Les sessions qui ont rendu leur code. « session_id » est celui que
-- GoTrue pose dans chaque jeton : une connexion, une session, un code.
create table if not exists public.sessions_sms (
  session_id   uuid primary key,
  utilisateur  uuid not null,
  confirmee_le timestamptz not null default now()
);

-- Invisibles depuis l'API : aucune règle de lecture, aucun droit. Seules
-- les fonctions de confiance y touchent.
alter table public.securite_equipe enable row level security;
alter table public.sessions_sms enable row level security;
revoke all on public.securite_equipe from public, anon, authenticated;
revoke all on public.sessions_sms from public, anon, authenticated;

-- La session du jeton en cours. Un jeton sans session — la clé de
-- service, un visiteur — n'en a pas, et rien ne le confirme.
-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
create or replace function public.est_mon_createur(cible uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return cible is not null and auth.uid() is not null and cible <> auth.uid() and exists (
  with recursive chaine(id, cran, vus) as (
    select p.cree_par, 1, array[p.id]
      from public.profils p
     where p.id = auth.uid() and p.cree_par is not null
    union all
    select p.cree_par, c.cran + 1, c.vus || p.id
      from chaine c
      join public.profils p on p.id = c.id
     where p.cree_par is not null and c.cran < 20 and not (p.id = any(c.vus))
  )
  select 1 from chaine where chaine.id = cible);
end $$;
revoke all on function public.est_mon_createur(uuid) from public, anon;
grant execute on function public.est_mon_createur(uuid) to authenticated;


create or replace function public.session_courante() returns uuid
language sql stable as $$
  select case when s ~* '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z'
              then s::uuid end
    from (select coalesce(auth.jwt() ->> 'session_id', '') as s) x;
$$;

-- L'enseigne exige-t-elle le code ? Une ligne absente répond « non » :
-- même règle que le compte obligatoire. Un accident ne doit pas enfermer
-- toute l'équipe dehors un samedi soir.
create or replace function public.sms_equipe_exige() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select s.sms_exige from public.securite_equipe s where s.id = 1), false);
$$;

-- Cette session a-t-elle rendu son code ?
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

-- L'équipe est-elle en service ? Oui quand rien n'est exigé ; sinon,
-- seulement avec une session confirmée.
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

-- Rôle du compte connecté. « security definer » : la fonction lit la table
-- sans repasser par les règles RLS — sinon les règles s'appelleraient elles-mêmes.
--
-- QUAND L'ENSEIGNE EXIGE LE CODE SMS, une session dont le code n'a pas
-- été rendu n'a AUCUN rang : ni superadministrateur, ni administrateur,
-- ni livreur. Tous les droits de l'équipe découlent d'ici — un seul
-- endroit à fermer, et tout est fermé.
create or replace function public.role_courant() returns text
language sql stable security definer set search_path = public as $$
  select role from public.profils
   where id = auth.uid() and actif and public.equipe_en_service();
$$;

-- ---------- Les deux fonctions qui lisent la fiche elles-mêmes ----------
-- Elles passent désormais par « role_courant() » : sans cela, un compte
-- de BIZZOO entré sans son code aurait gardé ses interrupteurs.
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

-- Lue par les règles plus bas (3.59.0), recopiée telle quelle.
create or replace function public.est_admin_bizzoo() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'administrateur', false)
     and public.est_compte_enseigne();
$$;
revoke all on function public.est_admin_bizzoo() from public, anon;
grant execute on function public.est_admin_bizzoo() to authenticated;



-- ---------- Un administrateur de boutique crée ses modérateurs ----------
-- « Créer un compte » passe par deux temps : l'inscription pose une
-- fiche en attente, SANS boutique, puis l'administrateur lui donne son
-- rang. Les règles exigeaient une fiche déjà de sa boutique, pour la lire
-- comme pour la modifier : l'administrateur d'une boutique ne pouvait
-- donc jamais finir de créer un modérateur — seul le superadministrateur
-- y arrivait. Elles lui ouvrent désormais la fiche toute fraîche, encore
-- en attente, née dans le quart d'heure ; ce qu'elle peut devenir ne
-- change pas : un modérateur de SA boutique.
alter policy "profils lecture" on public.profils
  to authenticated using (
    id = auth.uid()
    or public.est_super()
    or (public.est_admin() and boutique_id is not null
        and boutique_id = public.boutique_du_compte())
    or (public.est_admin() and role = 'moderateur' and not actif
        and boutique_id is null and cree_le > now() - interval '15 minutes')
    -- L'administrateur de BIZZOO voit tous les livreurs (3.59.0).
    or (public.est_admin_bizzoo() and role = 'livreur')
    -- (3.63.0) Et les modérateurs qu'il a créés. Les colonnes de la LIGNE,
    -- pas une relecture de la table : à la création, la ligne neuve doit se
    -- lire alors que la table garde encore l'ancienne.
    or (public.est_admin_bizzoo() and role = 'moderateur' and cree_par = auth.uid()));

alter policy "profils modification admin" on public.profils
  to authenticated
  using (
    -- (3.59.0) Le superadministrateur, sauf sur celui qui l'a créé.
    (public.est_super() and not public.est_mon_createur(id))
    or (public.est_admin() and role in ('moderateur', 'livreur')
        and boutique_id is not null and boutique_id = public.boutique_du_compte())
    or (public.est_admin() and role = 'moderateur' and not actif
        and boutique_id is null and cree_le > now() - interval '15 minutes')
    or (public.est_admin_bizzoo() and role = 'livreur')
    -- (3.63.0) Le modérateur qu'il a créé, tant qu'il attend sa validation.
    or (public.est_admin_bizzoo() and role = 'moderateur' and a_valider
        and cree_par = auth.uid()))
  with check (
    public.est_super()
    -- (3.59.0) Un modérateur ou un livreur de SA boutique — jamais un
    -- administrateur.
    or (public.est_admin() and role in ('moderateur', 'livreur')
        and boutique_id is not null and boutique_id = public.boutique_du_compte())
    -- Un livreur reste un livreur : l'administrateur de BIZZOO ne fait
    -- de personne un administrateur.
    or (public.est_admin_bizzoo() and role = 'livreur')
    -- (3.63.0) Un modérateur, mais INACTIF : c'est le superadministrateur
    -- qui l'active.
    or (public.est_admin_bizzoo() and role = 'moderateur' and not actif));

-- =========================================================
-- La connexion de l'équipe confirmée par SMS, et qui a créé
-- quel compte (3.58.0)
--
-- DEUX PORTES, DEUX MÉCANISMES, et le choix n'est pas un hasard.
--
--   LE CLIENT ENTRE PAR SON NUMÉRO : le code est celui de GoTrue, et
--   le numéro est l'identifiant. Rien à écrire ici — voir le chapitre
--   « Vérification du numéro ».
--
--   L'ÉQUIPE GARDE SON E-MAIL ET SON MOT DE PASSE, et reçoit EN PLUS un
--   code à chaque connexion. Ce code-là est le nôtre, et pour une
--   raison précise : GoTrue marque de la même étiquette (« otp ») une
--   session ouverte par un code SMS et une session ouverte par un lien
--   reçu par e-mail. La base ne saurait pas les distinguer. Le seul
--   témoin d'un SMS reçu est un code que NOUS avons envoyé, et que la
--   personne nous rend.
--
-- Le code est rattaché à la SESSION (« session_id » du jeton), pas au
-- compte : chaque connexion demande le sien, et un code rendu sur un
-- téléphone n'ouvre rien sur un autre. L'interrupteur, les sessions
-- confirmées et « equipe_en_service() » sont posés plus haut, avant
-- « role_courant() », qui les lit.
--
-- TANT QUE L'ENSEIGNE NE L'EXIGE PAS, rien ne change. L'interrupteur ne
-- s'allume qu'entre les mains d'un superadministrateur qui vient de
-- recevoir et de rendre son propre code : la preuve que le SMS arrive,
-- avant de fermer la porte à toute l'équipe.
-- =========================================================

-- ---------- Le numéro de l'équipe, et qui a créé le compte ----------
-- « tel » est répété ici : un fichier qui pose une règle d'écriture pose
-- aussi les colonnes qu'elle lit.
alter table public.profils add column if not exists tel text not null default '';
-- Vérifié par un code reçu, jamais déclaré : voir « profil_trace() ».
alter table public.profils add column if not exists tel_verifie boolean not null default false;
alter table public.profils add column if not exists tel_verifie_le timestamptz;
-- Qui a créé ce compte. SANS lien vers « auth.users » : la trace doit
-- survivre à la suppression du compte de celui qui l'a créé. Son nom est
-- figé au moment de la création, pour la même raison.
alter table public.profils add column if not exists cree_par uuid;
alter table public.profils add column if not exists cree_par_nom text not null default '';

-- ---------- Les codes envoyés ----------
-- Hachés, jamais en clair : une copie de la base ne doit pas permettre
-- d'ouvrir une session à la place de quelqu'un. Les lignes ne
-- s'effacent pas — un code rendu, remplacé ou annulé change d'état — et
-- c'est ce qui permet de compter les envois de l'heure passée.
create table if not exists public.codes_connexion (
  id          bigint generated always as identity primary key,
  session_id  uuid not null,
  utilisateur uuid not null,
  tel         text not null default '',
  code_hache  text not null,
  envoye_le   timestamptz not null default now(),
  expire_le   timestamptz not null,
  essais      int not null default 0,
  etat        text not null default 'envoye'
              check (etat in ('envoye', 'remplace', 'annule', 'utilise', 'epuise'))
);
create index if not exists codes_connexion_session
  on public.codes_connexion(session_id, envoye_le desc);
create index if not exists codes_connexion_utilisateur
  on public.codes_connexion(utilisateur, envoye_le desc);
alter table public.codes_connexion enable row level security;
revoke all on public.codes_connexion from public, anon, authenticated;

-- ---------- Enregistrer un code, au nom de la fonction Edge ----------
-- C'est la fonction Edge « code-connexion » qui tire le code : elle seule
-- le connaît en clair, et elle n'en confie ici que l'empreinte. D'où les
-- droits : la clé de service, et personne d'autre. Ouverte à un compte
-- connecté, elle laisserait chacun inscrire l'empreinte d'un code qu'il
-- aurait choisi — et le rendre sans avoir rien reçu.
--
-- LE FREIN est ici, en base : trente secondes entre deux codes, cinq par
-- heure. Côté application, il se contournerait — et chaque code est un
-- SMS payé par l'enseigne.
create or replace function public.enregistrer_code_connexion(
  qui uuid, session uuid, hache text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p       public.profils%rowtype;
  numero  text;
  dernier timestamptz;
  recents int;
  nouveau bigint;
begin
  if qui is null or session is null or coalesce(hache, '') !~ '\A[0-9a-f]{64}\Z' then
    return jsonb_build_object('ok', false, 'raison', 'requete');
  end if;
  select * into p from public.profils where id = qui;
  if not found or not p.actif then
    return jsonb_build_object('ok', false, 'raison', 'hors_equipe');
  end if;
  if exists (select 1 from public.sessions_sms s
              where s.session_id = session and s.utilisateur = qui) then
    return jsonb_build_object('ok', false, 'raison', 'deja_confirmee');
  end if;
  -- Le numéro est celui que l'administrateur a enregistré, jamais un
  -- numéro tapé au moment de se connecter : sinon un mot de passe volé
  -- suffirait, le voleur donnerait le sien.
  numero := regexp_replace(coalesce(p.tel, ''), '\D', '', 'g');
  if length(numero) < 8 then
    return jsonb_build_object('ok', false, 'raison', 'sans_numero');
  end if;

  select max(c.envoye_le),
         count(*) filter (where c.envoye_le > now() - interval '1 hour')
    into dernier, recents
    from public.codes_connexion c
   where c.utilisateur = qui and c.etat <> 'annule';
  if dernier is not null and dernier > now() - interval '30 seconds' then
    return jsonb_build_object('ok', false, 'raison', 'trop_tot',
      'attente', greatest(1, ceil(extract(epoch from
        (dernier + interval '30 seconds' - now()))))::int);
  end if;
  if coalesce(recents, 0) >= 5 then
    return jsonb_build_object('ok', false, 'raison', 'trop_de_codes');
  end if;

  -- Un seul code vaut pour une session : le précédent cède.
  update public.codes_connexion set etat = 'remplace'
   where session_id = session and utilisateur = qui and etat = 'envoye';
  insert into public.codes_connexion (session_id, utilisateur, tel, code_hache, expire_le)
  values (session, qui, numero, lower(hache), now() + interval '10 minutes')
  returning id into nouveau;
  return jsonb_build_object('ok', true, 'id', nouveau, 'tel', numero);
end $$;
revoke all on function public.enregistrer_code_connexion(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.enregistrer_code_connexion(uuid, uuid, text) to service_role;

-- Le SMS n'est pas parti : le code ne compte pas. Sans cela, une
-- passerelle en panne ferait épuiser les cinq envois de l'heure sans
-- qu'un seul SMS ait coûté quoi que ce soit — ni servi à rien.
create or replace function public.annuler_code_connexion(code_id bigint)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.codes_connexion set etat = 'annule'
   where id = code_id and etat = 'envoye';
end $$;
revoke all on function public.annuler_code_connexion(bigint)
  from public, anon, authenticated;
grant execute on function public.annuler_code_connexion(bigint) to service_role;

-- ---------- Rendre le code ----------
-- UNE ERREUR NE SE LÈVE PAS ICI, ELLE SE RÉPOND. Lever ferait annuler
-- la transaction — et avec elle le compteur d'essais qu'on vient
-- d'augmenter : on pourrait alors essayer les un million de codes un par
-- un. Cinq essais par code, cinq codes par heure : vingt-cinq chances
-- sur un million.
create or replace function public.confirmer_code_connexion(code text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  qui   uuid := auth.uid();
  sid   uuid := public.session_courante();
  c     public.codes_connexion%rowtype;
  saisi text := regexp_replace(coalesce(code, ''), '\D', '', 'g');
begin
  if qui is null or sid is null then
    return jsonb_build_object('ok', false, 'raison', 'sans_session');
  end if;
  if exists (select 1 from public.sessions_sms s
              where s.session_id = sid and s.utilisateur = qui) then
    return jsonb_build_object('ok', true, 'deja', true);
  end if;

  select * into c from public.codes_connexion
   where session_id = sid and utilisateur = qui and etat = 'envoye'
   order by envoye_le desc
   limit 1
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'raison', 'sans_code');
  end if;
  if c.expire_le < now() then
    update public.codes_connexion set etat = 'epuise' where id = c.id;
    return jsonb_build_object('ok', false, 'raison', 'expire');
  end if;

  -- L'empreinte porte la session : le même code tiré pour une autre
  -- connexion n'aurait pas la même.
  if length(saisi) <> 6
     or encode(digest(saisi || ':' || sid::text, 'sha256'), 'hex') <> c.code_hache then
    update public.codes_connexion
       set essais = essais + 1,
           etat = case when essais + 1 >= 5 then 'epuise' else etat end
     where id = c.id;
    return jsonb_build_object('ok', false, 'raison', 'code_faux',
      'restants', greatest(0, 4 - c.essais));
  end if;

  update public.codes_connexion set etat = 'utilise' where id = c.id;
  insert into public.sessions_sms (session_id, utilisateur)
  values (sid, qui)
  on conflict (session_id) do nothing;

  -- LE NUMÉRO EST VÉRIFIÉ : la personne a rendu le code qu'on y avait
  -- envoyé. À condition qu'il n'ait pas changé entre-temps — sinon c'est
  -- l'ancien qui a reçu le code, pas celui qu'on lirait maintenant.
  perform set_config('bizzoo.compte', 'oui', true);
  update public.profils
     set tel_verifie = true, tel_verifie_le = now()
   where id = qui and not tel_verifie
     and regexp_replace(coalesce(tel, ''), '\D', '', 'g') = c.tel;
  perform set_config('bizzoo.compte', '', true);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.confirmer_code_connexion(text) from public, anon;
grant execute on function public.confirmer_code_connexion(text) to authenticated;

-- ---------- Où en est la connexion ----------
-- Lue par l'application admin juste après le mot de passe : faut-il
-- demander un code, et vers quel numéro ? Elle répond MÊME à une session
-- sans droits — c'est tout son objet. Elle ne dit du numéro que ses deux
-- derniers chiffres : la personne connaît le sien, et une session
-- ouverte avec un mot de passe volé n'a pas à apprendre le reste.
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

-- ---------- L'interrupteur ----------
-- Au superadministrateur seul. ET POUR L'ALLUMER, IL FAUT AVOIR SOI-MÊME
-- REÇU ET RENDU SON CODE dans cette session : c'est la preuve que la
-- passerelle livre. Sans elle, allumer avec une clé SMS fausse ou un
-- crédit épuisé fermerait la porte à toute l'équipe — à commencer par
-- celui qui vient de l'allumer.
--
-- Pour l'éteindre en catastrophe, sans application : dans l'éditeur SQL
-- de Supabase, « update public.securite_equipe set sms_exige = false; ».
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

-- ---------- Qui a créé le compte ----------
-- Un nom lisible, figé au moment de la création : « Awa (superadministrateur) ».
create or replace function public.nom_du_createur(qui uuid)
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(trim(p.nom), ''), nullif(p.email, ''), 'compte inconnu')
         || ' (' || p.role || ')'
    from public.profils p
   where p.id = qui;
$$;
revoke all on function public.nom_du_createur(uuid) from public, anon, authenticated;

-- LA BASE ÉCRIT LA TRACE, L'APPLICATION NE FAIT QUE LA LIRE.
--
-- Le créateur, c'est le compte de l'équipe qui donne ses droits à une
-- fiche toute fraîche — encore en attente, née dans le quart d'heure.
-- C'est exactement ce que fait « Créer un compte » : l'inscription pose
-- la fiche, et une seconde plus tard l'administrateur lui donne son rang.
-- Une fiche réveillée plus tard — un compte inscrit hors de
-- l'application, qu'on active des jours après — n'a pas de créateur : on
-- ne prête pas à celui qui active un compte qu'il n'a pas créé.
--
-- Et ce qui ne se déclare pas : ni le créateur, ni la date, ni un numéro
-- vérifié. Changer de numéro annule sa vérification — sans quoi on
-- vérifierait un numéro, puis on le remplacerait par un autre.
--
-- « bizzoo.compte » est ce qui distingue les écritures de confiance —
-- le code rendu, le rattrapage plus bas — d'une requête ordinaire.
create or replace function public.profil_trace() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  qui  uuid := auth.uid();
  deja public.profils%rowtype;
begin
  if coalesce(current_setting('bizzoo.compte', true), '') = 'oui' then
    return new;
  end if;

  -- (3.59.0) ON NE TOUCHE PAS À SON CRÉATEUR, par aucun chemin : ni
  -- l'écran, ni l'Historique, ni une fonction de la base.
  if tg_op = 'UPDATE' and public.est_mon_createur(old.id) then
    raise exception 'Ce compte vous a créé : vous ne pouvez pas modifier ses droits.'
      using errcode = 'P0001';
  end if;

  if tg_op = 'INSERT' then
    -- UNE FICHE QUI EXISTE DÉJÀ NE NAÎT PAS UNE SECONDE FOIS. Une insertion
    -- qui la vise finit en mise à jour (« on conflict ») : c'est ainsi que
    -- l'Historique remet la fiche d'avant quand on annule, ENTIÈRE. Elle
    -- passe d'abord par ici, et « excluded » porte ce que cette règle y
    -- a mis : y nommer le créateur du moment faisait échouer toute
    -- annulation sur « la création ne se réécrit pas ». On y reporte donc
    -- la trace en place, et la règle de la mise à jour juge le reste.
    select * into deja from public.profils where id = new.id;
    if found then
      new.cree_par := deja.cree_par;
      new.cree_par_nom := deja.cree_par_nom;
      new.cree_le := deja.cree_le;
      new.tel_verifie := deja.tel_verifie;
      new.tel_verifie_le := deja.tel_verifie_le;
      return new;
    end if;

    new.cree_par := null;
    new.cree_par_nom := '';
    new.cree_le := now();
    new.tel_verifie := false;
    new.tel_verifie_le := null;
    if qui is not null and qui <> new.id
       and (public.est_super() or public.est_admin()) then
      new.cree_par := qui;
      new.cree_par_nom := coalesce(public.nom_du_createur(qui), '');
    end if;
    return new;
  end if;

  if new.cree_par is distinct from old.cree_par
     or new.cree_par_nom is distinct from old.cree_par_nom
     or new.cree_le is distinct from old.cree_le then
    raise exception 'La création d''un compte ne se réécrit pas';
  end if;
  if new.tel_verifie is distinct from old.tel_verifie
     or new.tel_verifie_le is distinct from old.tel_verifie_le then
    raise exception 'Un numéro ne se déclare pas vérifié : c''est le code reçu par SMS qui le vérifie';
  end if;

  if regexp_replace(coalesce(new.tel, ''), '\D', '', 'g')
     is distinct from regexp_replace(coalesce(old.tel, ''), '\D', '', 'g') then
    new.tel_verifie := false;
    new.tel_verifie_le := null;
  end if;

  if old.cree_par is null and not old.actif
     and old.cree_le > now() - interval '15 minutes'
     and qui is not null and qui <> old.id
     and (public.est_super() or public.est_admin()) then
    new.cree_par := qui;
    new.cree_par_nom := coalesce(public.nom_du_createur(qui), '');
  end if;
  return new;
end $$;

create or replace trigger profils_trace
  before insert or update on public.profils
  for each row execute function public.profil_trace();

-- ---------- Rattraper la trace des comptes d'avant ----------
-- Les comptes créés avant ce fichier n'ont pas de créateur en fiche,
-- mais le journal s'en souvient : « Modérateur ajouté : … », écrit au
-- nom de celui qui l'a créé. On le reprend — une seule fois par compte,
-- et seulement là où la fiche ne dit rien. Un compte né hors de
-- l'application n'a pas de ligne au journal : il reste sans créateur, et
-- l'écran le dit.
create or replace function public.rattraper_createurs() returns int
language plpgsql security definer set search_path = public as $$
declare combien int := 0;
begin
  perform set_config('bizzoo.compte', 'oui', true);
  update public.profils p
     set cree_par = c.id,
         cree_par_nom = case
           when c.id is not null
             then coalesce(nullif(trim(c.nom), ''), nullif(c.email, ''), j.utilisateur)
                  || ' (' || c.role || ')'
           else j.utilisateur end
    from (select distinct on (lower(x.cible)) lower(x.cible) as adresse,
                 x.utilisateur
            from public.journal x
           where x.famille = 'compte' and x.action = 'ajout'
             and x.cible <> '' and x.utilisateur <> ''
           order by lower(x.cible), x.fait_le) j
    left join public.profils c on lower(c.email) = lower(j.utilisateur)
   where p.cree_par is null and p.cree_par_nom = ''
     and lower(p.email) = j.adresse;
  get diagnostics combien = row_count;
  perform set_config('bizzoo.compte', '', true);
  return combien;
end $$;
revoke all on function public.rattraper_createurs() from public, anon, authenticated;
select public.rattraper_createurs();
