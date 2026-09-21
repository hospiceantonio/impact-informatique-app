-- =========================================================
-- BIZZOO — les comptes de l'enseigne
--
-- CE QUI MANQUAIT. Un compte de l'équipe était forcément
-- rattaché à UNE boutique, sauf le superadministrateur qui a
-- tout. Entre les deux, rien : personne ne pouvait suivre les
-- commandes de toutes les boutiques sans devenir maître de
-- l'enseigne entière.
--
-- CE QUE CE FICHIER AJOUTE. Un rang intermédiaire : un
-- administrateur ou un modérateur rattaché à AUCUNE boutique,
-- qui travaille au nom de BIZZOO. Ses droits ne viennent pas de
-- son rang mais d'INTERRUPTEURS, réglés un par un par le
-- superadministrateur.
--
--   peut_commandes  les commandes de toutes les boutiques
--   peut_modifier_produits  le catalogue de toutes les boutiques
--   peut_boutiques  créer, régler et fermer une boutique
--   peut_finances   le journal des versements et les chiffres
--
-- POURQUOI DES INTERRUPTEURS ET NON LE RANG. Parce que « admin
-- de BIZZOO » ne veut pas dire la même chose chez vous que la
-- semaine prochaine. Le rang nomme la personne ; les
-- interrupteurs disent ce qu'elle touche, et se relisent d'un
-- coup d'œil dans sa fiche.
--
-- CE QUE CES COMPTES NE PEUVENT PAS FAIRE, ET C'EST VOULU :
-- créer ou modifier d'autres comptes. Les règles de « profils »
-- exigent une boutique non nulle pour cela, ce qui les en exclut
-- sans qu'on ait à l'écrire. Seul le superadministrateur nomme —
-- et donc seul lui peut se donner des pairs.
--
-- CE QUE CE FICHIER NE DÉFAIT PAS. Aucun compte existant ne
-- change de droits : un compte de boutique garde sa boutique, le
-- superadministrateur garde tout. Les colonnes ajoutées ont des
-- valeurs par défaut qui ne donnent rien de plus à personne. On
-- peut le coller deux fois de suite sans conséquence.
-- =========================================================

-- ---------- Recopié de schema.sql ----------
-- Ce fichier doit pouvoir se coller seul sur une base d'avant : les
-- fonctions ci-dessous s'appuient sur ces deux-là, qui ne changent pas.
create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;
grant execute on function public.est_equipe() to authenticated;

create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils where id = auth.uid() and actif;
$$;
grant execute on function public.boutique_du_compte() to authenticated;

-- ---------- Ce qu'on sait d'une personne ----------
-- « profils » ne portait qu'une adresse e-mail. Un livreur qu'on
-- choisit dans une liste se reconnaît à son NOM, et se rattrape à
-- son NUMÉRO quand le client n'est pas chez lui.
alter table public.profils add column if not exists nom text not null default '';
alter table public.profils add column if not exists tel text not null default '';

-- ---------- Les interrupteurs de l'enseigne ----------
-- Ils ne servent QU'aux comptes d'enseigne : un compte de boutique
-- est déjà borné par sa boutique, et le superadministrateur passe
-- au-dessus. Les valeurs par défaut sont celles d'un compte qui
-- suit les commandes sans toucher à l'argent ni aux boutiques.
alter table public.profils
  add column if not exists peut_commandes boolean not null default true;
alter table public.profils
  add column if not exists peut_boutiques boolean not null default false;
alter table public.profils
  add column if not exists peut_finances  boolean not null default false;

-- ---------- Qui est un compte d'enseigne ----------
-- De l'équipe, actif, PAS superadministrateur, et rattaché à
-- aucune boutique. Les quatre conditions comptent :
--
--   « de l'équipe » écarte le livreur, qui a lui aussi une
--   boutique nulle quand on l'a créé sans en choisir une ;
--   « pas superadministrateur » parce que celui-là n'a pas besoin
--   d'interrupteurs — il passe au-dessus, et les lui appliquer
--   l'enfermerait dans sa propre maison.
create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false);
$$;
revoke all on function public.est_compte_enseigne() from public, anon;
grant execute on function public.est_compte_enseigne() to authenticated;

-- Un interrupteur de l'enseigne, lu sur la fiche du compte.
-- Il ne vaut VRAI que pour un compte d'enseigne : sur un compte de
-- boutique la colonne existe aussi, et sans cette condition elle
-- lui ouvrirait des portes que son rang ne lui donne pas.
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
revoke all on function public.droit_enseigne(text) from public, anon;
grant execute on function public.droit_enseigne(text) to authenticated;

-- ---------- Agir sur ce qui appartient à une boutique ----------
-- Une branche de plus : le compte d'enseigne agit sur TOUTES les
-- boutiques. Ce n'est pas un blanc-seing — les droits fins se
-- posent par-dessus, table par table : le catalogue passe encore
-- par « peut_modifier_produits() », les commandes par
-- « peut_voir_commandes() ».
create or replace function public.peut_agir_sur(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.est_compte_enseigne()
      or (public.est_equipe() and cible is not null
          and cible = public.boutique_du_compte());
$$;

-- Administrer une boutique — la régler, la fermer : le
-- superadministrateur partout, l'administrateur chez lui, et le
-- compte d'enseigne à qui on a donné l'interrupteur.
create or replace function public.administre(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.droit_enseigne('boutiques')
      or (public.est_admin() and cible is not null
          and cible = public.boutique_du_compte());
$$;

-- ---------- Le catalogue ----------
-- POUR UN COMPTE D'ENSEIGNE, LA COLONNE FAIT FOI, quel que soit
-- son rang. La version d'avant disait « administrateur, donc
-- oui » : un administrateur de BIZZOO à qui on aurait fermé le
-- catalogue l'aurait gardé ouvert, et l'interrupteur n'aurait
-- été qu'un dessin.
create or replace function public.peut_modifier_produits() returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when public.est_super() then true
    when public.est_compte_enseigne() then public.droit_enseigne('produits')
    else public.est_equipe()
     and coalesce((select role = 'administrateur' or peut_modifier_produits
                     from public.profils where id = auth.uid() and actif), false)
  end;
$$;

-- ---------- Les commandes ----------
-- Qui a le droit de LIRE et de faire avancer les commandes. Le
-- superadministrateur et l'équipe d'une boutique, toujours ; un
-- compte d'enseigne, si on lui a laissé l'interrupteur.
create or replace function public.peut_voir_commandes() returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.droit_enseigne('commandes')
      or (public.est_equipe() and not public.est_compte_enseigne());
$$;
revoke all on function public.peut_voir_commandes() from public, anon;
grant execute on function public.peut_voir_commandes() to authenticated;

-- Le journal des versements et les chiffres de vente.
create or replace function public.peut_voir_finances() returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.droit_enseigne('finances')
      or (public.est_equipe() and not public.est_compte_enseigne());
$$;
revoke all on function public.peut_voir_finances() from public, anon;
grant execute on function public.peut_voir_finances() to authenticated;

-- ---------- Les règles de lecture des commandes ----------
-- Refaites pour ouvrir au compte d'enseigne — et pour que
-- l'interrupteur « commandes » ferme vraiment quand il est éteint.
-- Sans la seconde condition, « peut_agir_sur » l'aurait déjà
-- ouvert : c'est l'erreur qu'un interrupteur d'écran seul aurait
-- laissée passer.
drop policy if exists "commandes lecture" on public.commandes;
create policy "commandes lecture" on public.commandes
  for select to authenticated using (
    public.est_super()
    or (public.est_compte_enseigne() and public.droit_enseigne('commandes'))
    or (public.est_equipe() and not public.est_compte_enseigne() and exists (
          select 1 from public.commande_lignes l
           where l.commande_id = commandes.id
             and l.boutique_id = public.boutique_du_compte())));

drop policy if exists "lignes lecture" on public.commande_lignes;
create policy "lignes lecture" on public.commande_lignes
  for select to authenticated
  using (public.peut_agir_sur(boutique_id) and public.peut_voir_commandes());

drop policy if exists "lignes suivi" on public.commande_lignes;
create policy "lignes suivi" on public.commande_lignes
  for update to authenticated
  using  (public.peut_agir_sur(boutique_id) and public.peut_voir_commandes())
  with check (public.peut_agir_sur(boutique_id) and public.peut_voir_commandes());

-- ---------- Un contrôle à la fin ----------
do $$
declare manque text := '';
begin
  if to_regprocedure('public.est_compte_enseigne()') is null then
    manque := manque || ' est_compte_enseigne';
  end if;
  if to_regprocedure('public.droit_enseigne(text)') is null then
    manque := manque || ' droit_enseigne';
  end if;
  if to_regprocedure('public.peut_voir_commandes()') is null then
    manque := manque || ' peut_voir_commandes';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'profils'
                    and column_name = 'peut_commandes') then
    manque := manque || ' profils.peut_commandes';
  end if;
  if manque <> '' then
    raise exception 'Manque :%', manque;
  end if;
  raise notice 'Les comptes d''enseigne sont posés.';
end $$;
