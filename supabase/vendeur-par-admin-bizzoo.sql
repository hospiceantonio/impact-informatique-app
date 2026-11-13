-- =========================================================
-- BIZZOO 3.81.0 — L'administrateur de BIZZOO crée un vendeur
--
--   Seul le superadministrateur créait un vendeur. L'administrateur de
--   BIZZOO (sans boutique) en crée désormais, comme il crée des livreurs ;
--   le superadministrateur en est prévenu et règle ensuite le lieu du
--   vendeur et ses produits. Modifier ou supprimer un vendeur lui reste.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- Les colonnes que les fonctions plus bas lisent.
-- (3.81.0) Empruntées plus bas, recopiées telles quelles.
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

create or replace function public.nom_du_createur(qui uuid)
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(trim(p.nom), ''), nullif(p.email, ''), 'compte inconnu')
         || ' (' || p.role || ')'
    from public.profils p
   where p.id = qui;
$$;
revoke all on function public.nom_du_createur(uuid) from public, anon, authenticated;

create or replace function public.les_superadmins() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.role = 'superadministrateur';
$$;
revoke all on function public.les_superadmins()          from public, anon, authenticated;

create or replace function public.est_mon_createur(cible uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  -- (3.81.0) ENTRE SUPERADMINISTRATEURS, PLUS DE CRÉATEUR PROTÉGÉ : un
  -- superadministrateur nommé par un autre a tous les droits d'un
  -- superadministrateur, sur tous les comptes. Ce qui protège encore
  -- BIZZOO : il reste toujours au moins un superadministrateur actif
  -- (« profil_dernier_super »).
  if public.est_super() then
    return false;
  end if;
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

create or replace function public.est_admin_bizzoo() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'administrateur', false)
     and public.est_compte_enseigne();
$$;
revoke all on function public.est_admin_bizzoo() from public, anon;
grant execute on function public.est_admin_bizzoo() to authenticated;

create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;
grant execute on function public.boutique_du_compte() to authenticated;

alter table public.profils add column if not exists boutique_id text references public.boutiques(id) on delete set null;
alter table public.profils add column if not exists nom text not null default '';
alter table public.profils add column if not exists tel text not null default '';
alter table public.profils add column if not exists a_valider boolean not null default false;

-- Les règles des fiches de comptes : l'administrateur de BIZZOO lit les
-- vendeurs, et en crée (sans boutique).
drop policy if exists "profils lecture" on public.profils;
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
    or (public.est_admin_bizzoo() and role = 'moderateur' and cree_par = auth.uid())
    -- (3.81.0) Et les vendeurs : il en crée.
    or (public.est_admin_bizzoo() and role = 'vendeur'));

drop policy if exists "profils ajout admin" on public.profils;
create policy "profils ajout admin" on public.profils
  for insert to authenticated with check (
    public.est_super()
    or (public.est_admin() and role in ('moderateur', 'livreur')
        and boutique_id is not null and boutique_id = public.boutique_du_compte())
    -- L'administrateur de BIZZOO crée des livreurs — et (3.63.0) des
    -- modérateurs INACTIFS, que le superadministrateur validera.
    or (public.est_admin_bizzoo() and role = 'livreur')
    or (public.est_admin_bizzoo() and role = 'moderateur' and not actif)
    -- (3.81.0) Et des vendeurs, de BIZZOO (sans boutique).
    or (public.est_admin_bizzoo() and role = 'vendeur' and boutique_id is null));

drop policy if exists "profils modification admin" on public.profils;
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
    or (public.est_admin_bizzoo() and role = 'moderateur' and not actif)
    -- (3.81.0) Un vendeur, seulement à sa création (« profil_vendeur_cree »).
    or (public.est_admin_bizzoo() and role = 'vendeur' and boutique_id is null));

-- =========================================================
-- (3.81.0) L'ADMINISTRATEUR DE BIZZOO CRÉE UN VENDEUR
--
-- Seul le superadministrateur créait un vendeur. Désormais
-- l'administrateur de BIZZOO (sans boutique) en crée aussi, comme il crée
-- des livreurs : les règles de « profils » le lui ouvrent (plus haut), et
-- ce déclencheur en tient le reste :
--   - un vendeur NAÎT vendeur : la fiche toute fraîche de l'inscription,
--     jamais un livreur ou un modérateur déjà en service qu'on
--     changerait en vendeur ;
--   - il n'a pas de boutique (il vend dans les boutiques à vendeurs
--     multiples) ;
--   - le superadministrateur est prévenu : c'est lui qui règle le lieu du
--     vendeur, lui attribue ses produits et suit ses ventes.
-- Modifier ou supprimer un vendeur reste au superadministrateur.
-- =========================================================
create or replace function public.profil_vendeur_cree() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.role is distinct from 'vendeur' or public.est_super() or not public.est_admin_bizzoo() then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.role = 'vendeur' then
    return new;
  end if;
  if tg_op = 'UPDATE' and not (old.role = 'moderateur' and not old.actif and old.boutique_id is null
                              and not coalesce(old.a_valider, false)
                              and old.cree_le > now() - interval '15 minutes') then
    raise exception 'L''administrateur de BIZZOO crée un vendeur ; il ne change pas un compte existant en vendeur.'
      using errcode = 'P0001';
  end if;
  new.boutique_id := null;
  -- Une insertion qui vise une fiche existante finit en mise à jour
  -- (« on conflict ») : on ne prévient qu'une fois.
  if tg_op = 'UPDATE' or not exists (select 1 from public.profils p where p.id = new.id) then
    perform public.notifier(public.les_superadmins(), 'vendeur_cree', 'Nouveau vendeur à configurer',
      coalesce(nullif(trim(new.nom), ''), nullif(trim(new.tel), ''), 'Un vendeur') || ', créé par ' ||
        coalesce(public.nom_du_createur(auth.uid()), 'un administrateur de BIZZOO') ||
        '. Réglez son lieu et attribuez-lui ses produits.',
      '#/vendeurs/' || new.id, null, null, false);
  end if;
  return new;
end $$;
revoke all on function public.profil_vendeur_cree() from public, anon, authenticated;

drop trigger if exists profils_vendeur_cree on public.profils;
create trigger profils_vendeur_cree
  before insert or update on public.profils
  for each row execute function public.profil_vendeur_cree();
