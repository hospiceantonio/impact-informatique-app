-- =========================================================
-- BIZZOO 3.59.0 — Créer un produit demande l'habilitation
--
-- Avant : retirer à un compte le droit « produits » l'empêchait de
-- RETOUCHER un produit, pas d'en CRÉER ; un administrateur de boutique
-- l'avait d'office ; un compte de BIZZOO réduit aux commandes créait
-- des produits quand même.
--
-- Désormais une seule habilitation — créer, modifier, supprimer — et elle
-- vaut pour tous : modérateur, administrateur de boutique, compte de
-- BIZZOO (interrupteur « Le catalogue »). Seul le superadministrateur
-- passe outre.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- Ce que les fonctions et règles plus bas empruntent, recopié tel quel.
create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;



create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;


create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false)
     and public.role_courant() is not null;
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


create or replace function public.peut_agir_sur(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.est_compte_enseigne()
      or (public.est_equipe() and cible is not null
          and cible = public.boutique_du_compte());
$$;



create or replace function public.peut_modifier_produits() returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when public.est_super() then true
    when public.est_compte_enseigne() then public.droit_enseigne('produits')
    -- L'HABILITATION VAUT POUR TOUS (3.59.0), administrateur de boutique
    -- compris : retirée, on ne crée, ne modifie ni ne supprime plus de
    -- produit. Seul le superadministrateur passe outre.
    else public.est_equipe()
     and coalesce((select peut_modifier_produits
                     from public.profils where id = auth.uid() and actif), false)
  end;
$$;




drop policy if exists "produits ajout" on public.produits;
create policy "produits ajout" on public.produits
  for insert to authenticated
  with check (public.peut_modifier_produits() and public.peut_agir_sur(boutique_id));
drop policy if exists "prix achat ajout" on public.produits_prive;
create policy "prix achat ajout" on public.produits_prive
  for insert to authenticated
  with check (public.peut_modifier_produits() and public.peut_agir_sur(
    (select p.boutique_id from public.produits p where p.id = produit_id)));
