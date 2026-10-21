-- =========================================================
-- BIZZOO 3.59.0 — Qui crée quels comptes, et on ne touche pas à son
-- créateur
--
--   1. l'administrateur d'une boutique crée, modifie et retire les
--      LIVREURS de SA boutique (en plus de ses modérateurs) ; il ne nomme
--      ni administrateur ni superadministrateur, ni livreur d'une autre
--      boutique ou de BIZZOO ;
--   2. il crée la fiche d'un REVENDEUR : la demande reste en attente,
--      BIZZOO seul la valide ;
--   3. un compte créé par un autre — un superadministrateur nommé par un
--      autre, par exemple — ne modifie pas les droits de son créateur, ni
--      de ceux qui sont au-dessus : ni rôle, ni actif, ni mot de passe,
--      ni suppression.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- À coller APRÈS reste-momopay.sql.
-- =========================================================

-- (3.63.0) Les règles de « profils » lisent ces colonnes.
alter table public.profils add column if not exists cree_par uuid;
alter table public.profils add column if not exists a_valider boolean not null default false;

-- Les colonnes que les fonctions plus bas lisent.
alter table public.profils add column if not exists tel text not null default '';
alter table public.profils add column if not exists tel_verifie boolean not null default false;
alter table public.profils add column if not exists tel_verifie_le timestamptz;
alter table public.profils add column if not exists cree_par uuid;
alter table public.profils add column if not exists cree_par_nom text not null default '';

-- ---------- On ne touche pas à son créateur (3.59.0) ----------
-- Un compte créé par un autre ne modifie pas les droits de celui qui l'a
-- créé — ni du créateur de celui-ci, et ainsi de suite en remontant : un
-- superadministrateur nommé par un autre ne peut pas le rétrograder, le
-- désactiver, changer son mot de passe ni le supprimer. On remonte la
-- chaîne « cree_par » depuis le compte connecté (vingt crans au plus,
-- et jamais deux fois le même compte).
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


create or replace function public.est_admin_bizzoo() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'administrateur', false)
     and public.est_compte_enseigne();
$$;
revoke all on function public.est_admin_bizzoo() from public, anon;
grant execute on function public.est_admin_bizzoo() to authenticated;

create or replace function public.nom_du_createur(qui uuid)
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(trim(p.nom), ''), nullif(p.email, ''), 'compte inconnu')
         || ' (' || p.role || ')'
    from public.profils p
   where p.id = qui;
$$;
revoke all on function public.nom_du_createur(uuid) from public, anon, authenticated;


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

alter policy "profils ajout admin" on public.profils
  to authenticated with check (
    public.est_super()
    or (public.est_admin() and role in ('moderateur', 'livreur')
        and boutique_id is not null and boutique_id = public.boutique_du_compte())
    -- L'administrateur de BIZZOO crée des livreurs — et (3.63.0) des
    -- modérateurs INACTIFS, que le superadministrateur validera.
    or (public.est_admin_bizzoo() and role = 'livreur')
    or (public.est_admin_bizzoo() and role = 'moderateur' and not actif));

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

alter policy "profils suppression admin" on public.profils
  to authenticated using (
    (public.est_super() and not public.est_mon_createur(id))
    or (public.est_admin() and role in ('moderateur', 'livreur')
        and boutique_id is not null and boutique_id = public.boutique_du_compte())
    or (public.est_admin_bizzoo() and role = 'livreur')
    or (public.est_admin_bizzoo() and role = 'moderateur' and a_valider
        and cree_par = auth.uid()));

-- (3.63.0) « gere_le_compte » appelle désormais « mon_moderateur ».
alter table public.profils add column if not exists cree_par uuid;
alter table public.profils add column if not exists a_valider boolean not null default false;
create or replace function public.mon_moderateur(cible uuid, en_attente boolean)
returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return public.est_admin_bizzoo() and exists (
    select 1 from public.profils p
     where p.id = cible and p.role = 'moderateur' and p.cree_par = auth.uid()
       and (not en_attente or p.a_valider));
end $$;
revoke all on function public.mon_moderateur(uuid, boolean) from public, anon;
grant execute on function public.mon_moderateur(uuid, boolean) to authenticated;

-- Qui a le droit d'agir sur ce compte-là ? Le superadministrateur sur
-- tous ; l'administrateur seulement sur les modérateurs et les livreurs
-- (3.59.0) de sa boutique.
create or replace function public.gere_le_compte(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  -- (3.59.0) Jamais sur celui qui vous a créé, ni plus haut.
  select not public.est_mon_createur(cible) and (public.est_super()
      or (public.est_admin() and exists (
            select 1 from public.profils p
             where p.id = cible and p.role in ('moderateur', 'livreur')
               and p.boutique_id is not null
               and p.boutique_id = public.boutique_du_compte()))
      or (public.est_admin_bizzoo() and exists (
            select 1 from public.profils p
             where p.id = cible and p.role = 'livreur'))
      -- (3.63.0) Le modérateur qu'il a créé, tant qu'il attend sa validation.
      or public.mon_moderateur(cible, true));
$$;
grant execute on function public.gere_le_compte(uuid) to authenticated;

-- ---------- BIZZOO crée un compte revendeur (3.59.0) ----------
-- L'application admin inscrit le compte (numéro + mot de passe, comme le
-- client le ferait), puis pose ici sa fiche : une DEMANDE en attente,
-- avec le commerce et l'adresse. Le revendeur entre ensuite avec son
-- numéro, son mot de passe et le code reçu par SMS, active la position de
-- son téléphone dans « Mon compte » — et BIZZOO valide.
--
-- Seulement sur un compte tout neuf (moins d'une heure), qui n'est ni de
-- l'équipe ni déjà client : on ne réécrit pas la fiche de quelqu'un.
create or replace function public.creer_fiche_revendeur(
  cible uuid, nom text, tel text, message text default '', adresse text default '')
returns text
language plpgsql security definer set search_path = public as $$
begin
  -- (3.59.0) L'administrateur d'une boutique aussi : il crée la fiche, la
  -- demande reste EN ATTENTE, et BIZZOO seul la valide.
  if not (public.est_super() or public.est_admin_bizzoo() or public.est_admin()) then
    raise exception 'Seul un administrateur crée un compte revendeur';
  end if;
  if not exists (select 1 from auth.users u
                  where u.id = cible and u.created_at > now() - interval '1 hour') then
    raise exception 'Ce compte n''est pas un compte qu''on vient de créer';
  end if;
  if exists (select 1 from public.profils p where p.id = cible)
     or exists (select 1 from public.clients c where c.id = cible) then
    raise exception 'Ce compte a déjà sa fiche';
  end if;
  if length(regexp_replace(coalesce(tel, ''), '\D', '', 'g')) < 8 then
    raise exception 'Le numéro du revendeur est incomplet';
  end if;
  insert into public.clients (id, nom, tel, type_compte, revendeur_message, revendeur_adresse)
  values (cible, left(trim(coalesce(nom, '')), 120), tel, 'revendeur',
          left(trim(coalesce(message, '')), 300), left(trim(coalesce(adresse, '')), 200));
  return 'en_attente';
end $$;
revoke all on function public.creer_fiche_revendeur(uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.creer_fiche_revendeur(uuid, text, text, text, text) to authenticated;

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

