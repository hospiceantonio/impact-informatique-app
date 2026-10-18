-- =========================================================
-- BIZZOO 3.59.0 — L'administrateur de BIZZOO gère livreurs et revendeurs
--
-- Un administrateur rattaché à aucune boutique (« administrateur de
-- BIZZOO ») peut désormais, comme le superadministrateur :
--   1. créer, modifier et retirer des comptes LIVREUR (et rien d'autre) ;
--   2. voir la position de tous les livreurs ;
--   3. créer un compte REVENDEUR (creer_fiche_revendeur) ;
--   4. voir les demandes de revendeur et les valider ou les refuser.
-- Les modérateurs de BIZZOO et les comptes de boutique : inchangés.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
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



create or replace function public.administre(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.droit_enseigne('boutiques')
      or (public.est_admin() and cible is not null
          and cible = public.boutique_du_compte());
$$;


create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;


create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false)
     and public.role_courant() is not null;
$$;


create or replace function public.numero_de_livreur(numero text) returns boolean
language sql stable security definer set search_path = public as $$
  select length(regexp_replace(coalesce(numero, ''), '\D', '', 'g')) >= 8
     and exists (
       select 1 from public.profils p
        where p.actif and p.role = 'livreur'
          and length(regexp_replace(coalesce(p.tel, ''), '\D', '', 'g')) >= 8
          and right(regexp_replace(p.tel, '\D', '', 'g'), 8)
            = right(regexp_replace(numero, '\D', '', 'g'), 8));
$$;
revoke all on function public.numero_de_livreur(text) from public, anon, authenticated;


create or replace function public.est_admin_bizzoo() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'administrateur', false)
     and public.est_compte_enseigne();
$$;
revoke all on function public.est_admin_bizzoo() from public, anon;
grant execute on function public.est_admin_bizzoo() to authenticated;

create or replace function public.revendeurs(filtre text default 'en_attente')
returns table (
  id uuid, nom text, email text, tel text, indicatif text,
  message text, etat text, demande_le timestamptz,
  decide_par text, decide_le timestamptz, motif text,
  adresse text, latitude double precision, longitude double precision)
language sql stable security definer set search_path = public as $$
  select c.id, c.nom, coalesce(u.email, '')::text, c.tel, c.indicatif,
         c.revendeur_message, c.revendeur_etat, c.revendeur_demande_le,
         c.revendeur_decide_par, c.revendeur_decide_le, c.revendeur_motif,
         c.revendeur_adresse, c.revendeur_latitude, c.revendeur_longitude
    from public.clients c
    left join auth.users u on u.id = c.id
   where (public.est_super() or public.est_admin_bizzoo())
     and c.revendeur_etat <> 'aucune'
     and (coalesce(filtre, '') = '' or c.revendeur_etat = filtre)
   order by c.revendeur_demande_le desc nulls last;
$$;
revoke all on function public.revendeurs(text) from public, anon, authenticated;
grant execute on function public.revendeurs(text) to authenticated;

create or replace function public.valider_revendeur(
  cible uuid, accord boolean, raison text default '')
returns text
language plpgsql security definer set search_path = public as $$
declare
  qui  text;
  etat text;
begin
  -- Le superadministrateur, ou un administrateur de BIZZOO (3.59.0).
  if not (public.est_super() or public.est_admin_bizzoo()) then
    raise exception 'Seul BIZZOO valide un compte revendeur';
  end if;
  select coalesce(p.email, '') into qui from public.profils p where p.id = auth.uid();
  etat := case when accord then 'validee' else 'refusee' end;

  -- UN REVENDEUR VALIDE SON COMPTE EN ACTIVANT SA POSITION : la
  -- géolocalisation de son téléphone, ET son adresse écrite. Sans elles,
  -- BIZZOO ne l'accepte pas (il peut toujours refuser).
  if accord and not exists (
       select 1 from public.clients c
        where c.id = cible
          and c.revendeur_latitude is not null and c.revendeur_longitude is not null
          and length(trim(coalesce(c.revendeur_adresse, ''))) >= 3) then
    raise exception 'Ce revendeur n''a pas encore enregistré sa position : il doit activer la localisation de son téléphone dans son compte, et indiquer son adresse.'
      using errcode = 'P0001';
  end if;

  -- Une demande déposée avant la 3.59.0 avec le numéro d'un livreur ne
  -- se valide pas : un livreur n'est pas revendeur.
  if accord and exists (select 1 from public.clients c
                         where c.id = cible and public.numero_de_livreur(c.tel)) then
    raise exception 'Ce numéro est celui d''un livreur BIZZOO : un livreur ne devient pas revendeur.'
      using errcode = 'P0001';
  end if;

  perform set_config('bizzoo.revendeur', 'oui', true);
  update public.clients
     set revendeur_etat       = etat,
         type_compte          = case when accord then 'revendeur' else type_compte end,
         revendeur_decide_par = coalesce(qui, ''),
         revendeur_decide_le  = now(),
         revendeur_motif      = left(coalesce(raison, ''), 300),
         maj_le               = now()
   where id = cible;
  if not found then
    perform set_config('bizzoo.revendeur', '', true);
    raise exception 'Compte introuvable';
  end if;
  -- Le drapeau est rendu tel qu'il était : il ne vaut que pour la
  -- ligne qu'on vient d'écrire, pas pour la suite de l'appel.
  perform set_config('bizzoo.revendeur', '', true);
  return etat;
end $$;

revoke all on function public.valider_revendeur(uuid, boolean, text)
  from public, anon, authenticated;
grant execute on function public.valider_revendeur(uuid, boolean, text) to authenticated;

create or replace function public.creer_fiche_revendeur(
  cible uuid, nom text, tel text, message text default '', adresse text default '')
returns text
language plpgsql security definer set search_path = public as $$
begin
  if not (public.est_super() or public.est_admin_bizzoo()) then
    raise exception 'Seul BIZZOO crée un compte revendeur';
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



-- ---------- Les règles d'accès ----------
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
    or (public.est_admin_bizzoo() and role = 'livreur'));
drop policy if exists "profils ajout admin" on public.profils;
create policy "profils ajout admin" on public.profils
  for insert to authenticated with check (
    public.est_super()
    or (public.est_admin() and role = 'moderateur'
        and boutique_id is not null and boutique_id = public.boutique_du_compte())
    -- L'administrateur de BIZZOO crée des livreurs, et rien d'autre.
    or (public.est_admin_bizzoo() and role = 'livreur'));
drop policy if exists "profils modification admin" on public.profils;
create policy "profils modification admin" on public.profils
  for update to authenticated
  using (
    public.est_super()
    or (public.est_admin() and role = 'moderateur'
        and boutique_id is not null and boutique_id = public.boutique_du_compte())
    or (public.est_admin() and role = 'moderateur' and not actif
        and boutique_id is null and cree_le > now() - interval '15 minutes')
    or (public.est_admin_bizzoo() and role = 'livreur'))
  with check (
    public.est_super()
    or (public.est_admin() and role = 'moderateur'
        and boutique_id is not null and boutique_id = public.boutique_du_compte())
    -- Un livreur reste un livreur : l'administrateur de BIZZOO ne fait
    -- de personne un administrateur ni un modérateur.
    or (public.est_admin_bizzoo() and role = 'livreur'));
drop policy if exists "profils suppression admin" on public.profils;
create policy "profils suppression admin" on public.profils
  for delete to authenticated using (
    public.est_super()
    or (public.est_admin() and role = 'moderateur'
        and boutique_id is not null and boutique_id = public.boutique_du_compte())
    or (public.est_admin_bizzoo() and role = 'livreur'));
drop policy if exists "positions livreurs lecture" on public.positions_livreurs;
create policy "positions livreurs lecture" on public.positions_livreurs
  for select to authenticated
  using (profil_id = auth.uid()
         or public.est_super()
         or public.est_admin_bizzoo()
         or exists (select 1 from public.profils p
                     where p.id = positions_livreurs.profil_id
                       and public.administre(p.boutique_id)));
