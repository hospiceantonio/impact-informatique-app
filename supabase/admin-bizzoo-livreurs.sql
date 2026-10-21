-- =========================================================
-- BIZZOO 3.63.0 — Les comptes de l'administrateur de BIZZOO
--
--   1. SES LIVREURS, JUSQU'AU BOUT. Depuis la 3.59.0 il les crée et les
--      modifie ; « Redonner un mot de passe » et « Supprimer » lui
--      répondaient pourtant « Ce compte n'est pas sous votre
--      responsabilité » : « gere_le_compte » l'avait oublié.
--   2. LES MODÉRATEURS, VALIDÉS PAR LE SUPERADMINISTRATEUR (demande du
--      CEO). Il crée un compte modérateur — pour une boutique ou pour
--      BIZZOO ; le compte naît INACTIF et « à valider ». Il le retouche ou
--      le retire tant qu'il attend ; seul le superadministrateur l'active,
--      et l'activer le valide. Les superadministrateurs sont prévenus à
--      la création, le créateur à la validation.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- Les colonnes que les fonctions plus bas lisent.
alter table public.profils add column if not exists nom text not null default '';
alter table public.profils add column if not exists cree_par uuid;
alter table public.profils add column if not exists cree_par_nom text not null default '';
alter table public.profils add column if not exists a_valider boolean not null default false;

-- Emprunté par les fonctions plus bas (3.63.0), recopié tel quel.
create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;

-- Emprunté par les fonctions plus bas (3.63.0), recopié tel quel.
create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false)
     and public.role_courant() is not null;
$$;

-- Emprunté par les fonctions plus bas (3.63.0), recopié tel quel.
create or replace function public.est_admin_bizzoo() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'administrateur', false)
     and public.est_compte_enseigne();
$$;
revoke all on function public.est_admin_bizzoo() from public, anon;
grant execute on function public.est_admin_bizzoo() to authenticated;

-- Emprunté par les fonctions plus bas (3.63.0), recopié tel quel.
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

-- Emprunté par les fonctions plus bas (3.63.0), recopié tel quel.
create or replace function public.les_superadmins() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.role = 'superadministrateur';
$$;

-- Emprunté par les fonctions plus bas (3.63.0), recopié tel quel.
create or replace function public.nom_du_createur(qui uuid)
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(trim(p.nom), ''), nullif(p.email, ''), 'compte inconnu')
         || ' (' || p.role || ')'
    from public.profils p
   where p.id = qui;
$$;
revoke all on function public.nom_du_createur(uuid) from public, anon, authenticated;

-- Emprunté par les fonctions plus bas (3.63.0), recopié tel quel.
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

-- ---------- Le modérateur qu'il a créé (3.63.0) ----------
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

-- ---------- Ses livreurs et ses modérateurs à valider, sous sa responsabilité ----------
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

-- ---------- Les règles d'accès aux fiches ----------
drop policy if exists "profils lecture" on public.profils;
drop policy if exists "profils ajout admin" on public.profils;
drop policy if exists "profils modification admin" on public.profils;
drop policy if exists "profils suppression admin" on public.profils;
-- Chacun voit sa fiche. Le superadministrateur voit toute l'enseigne ;
-- l'administrateur, l'équipe de sa boutique — et la fiche toute fraîche
-- qu'il est en train de créer : sans la voir, PostgreSQL ne le laisse
-- pas lui donner son rang (voir « profils modification admin »).
create policy "profils lecture" on public.profils
  for select to authenticated using (
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

-- Créer, modifier, supprimer un compte : le superadministrateur sans
-- limite ; l'administrateur seulement des MODÉRATEURS et des LIVREURS
-- (3.59.0) de SA boutique — il ne se nomme pas de pairs et ne touche pas
-- à ses supérieurs.
create policy "profils ajout admin" on public.profils
  for insert to authenticated with check (
    public.est_super()
    or (public.est_admin() and role in ('moderateur', 'livreur')
        and boutique_id is not null and boutique_id = public.boutique_du_compte())
    -- L'administrateur de BIZZOO crée des livreurs — et (3.63.0) des
    -- modérateurs INACTIFS, que le superadministrateur validera.
    or (public.est_admin_bizzoo() and role = 'livreur')
    or (public.est_admin_bizzoo() and role = 'moderateur' and not actif));
-- « Créer un compte » passe par deux temps : l'inscription pose une
-- fiche en attente, SANS boutique, puis l'administrateur lui donne son
-- rang. Le premier membre de « using » exigeait une fiche déjà de sa
-- boutique : l'administrateur d'une boutique ne pouvait donc jamais
-- finir de créer un modérateur — seul le superadministrateur y
-- arrivait. Le second lui ouvre la fiche toute fraîche, encore en
-- attente, née dans le quart d'heure ; « with check » ne change pas :
-- elle ne peut devenir qu'un modérateur de SA boutique.
create policy "profils modification admin" on public.profils
  for update to authenticated
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
create policy "profils suppression admin" on public.profils
  for delete to authenticated using (
    (public.est_super() and not public.est_mon_createur(id))
    or (public.est_admin() and role in ('moderateur', 'livreur')
        and boutique_id is not null and boutique_id = public.boutique_du_compte())
    or (public.est_admin_bizzoo() and role = 'livreur')
    or (public.est_admin_bizzoo() and role = 'moderateur' and a_valider
        and cree_par = auth.uid()));

-- ---------- Le compte à valider ----------
create or replace function public.profil_validation() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  nouveau boolean;
begin
  if coalesce(current_setting('bizzoo.compte', true), '') = 'oui' then
    return new;
  end if;

  if public.est_admin_bizzoo() and new.role = 'moderateur' then
    new.actif := false;
    new.a_valider := true;
    -- L'écran pose le rang par « insert … on conflict » : PostgreSQL exige
    -- alors que la ligne PROPOSÉE soit lisible par son auteur, et elle ne
    -- l'est que par son créateur. Sur une fiche qui n'en a pas encore, il
    -- l'est ; « profil_trace » en fera autant sur la mise à jour.
    if tg_op = 'INSERT' and new.cree_par is null then
      new.cree_par := auth.uid();
    end if;
    -- Une insertion qui vise une fiche existante finira en mise à jour
    -- (« on conflict ») : on ne prévient qu'une fois, sur la mise à jour.
    nouveau := case when tg_op = 'INSERT'
                    then not exists (select 1 from public.profils p where p.id = new.id)
                    else not old.a_valider end;
    if nouveau then
      perform public.notifier(public.les_superadmins(), 'compte_a_valider',
        'Un compte modérateur à valider',
        coalesce(nullif(trim(new.nom), ''), nullif(new.email, ''), 'Un nouveau compte') ||
          ', créé par ' || coalesce(public.nom_du_createur(auth.uid()), 'un administrateur de BIZZOO') ||
          '. Activez-le dans Comptes pour le valider.',
        '#/comptes', null, null, false);
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.a_valider := false;
    return new;
  end if;

  if public.est_super() then
    -- Activer, c'est valider.
    new.a_valider := old.a_valider and not new.actif;
    if old.a_valider and not new.a_valider and old.cree_par is not null then
      perform public.notifier(array[old.cree_par], 'compte_valide',
        'Compte validé',
        coalesce(nullif(trim(new.nom), ''), nullif(new.email, ''), 'Le compte') ||
          ' a été validé : il peut travailler.',
        '#/comptes', null, null, false);
    end if;
  else
    new.a_valider := old.a_valider;
    if old.a_valider then new.actif := false; end if;
  end if;
  return new;
end $$;

drop trigger if exists profils_validation on public.profils;
create trigger profils_validation
  before insert or update on public.profils
  for each row execute function public.profil_validation();
