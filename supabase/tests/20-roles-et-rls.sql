-- =========================================================
-- Qui a le droit de quoi.
--
-- Trois rangs, et une enseigne qui réunit plusieurs
-- boutiques. Masquer un écran n'est qu'une politesse ; ce
-- fichier vérifie la serrure — les règles RLS et les
-- déclencheurs, tels qu'ils tournent sur le moteur.
--
-- Les comptes viennent du banc d'essai :
--   enseigne@bizzoo.bj       superadministrateur
--   chef-boutique@bizzoo.bj  administrateur (informatique)
--   equipe@bizzoo.bj         modérateur (autre boutique)
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set EQUIPE   '''33333333-3333-3333-3333-333333333333'''

select essai.titre('Le décor : une seconde boutique, et deux comptes');

-- ELLE A UN SECTEUR, comme toute boutique de BIZZOO : elle n'invente
-- plus ses rayons, elle choisit sa place dans la liste de l'enseigne.
-- On la met dans le MÊME secteur que la boutique d'à côté, pour que le
-- décor des autres essais reste simple. La règle « un produit d'un
-- autre secteur est refusé » s'éprouve dans « 99h-categories.sql », sur
-- une troisième boutique faite pour cela.
insert into public.boutiques (id, nom, secteur, devise, actif, ordre, categorie_id)
values ('bou_essai_voisine', 'BOUTIQUE VOISINE', 'Essai', 'FCFA', true, 91, 'cat_hightech')
on conflict (id) do nothing;

insert into public.produits
  (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_essai_voisin', 'bou_essai_voisine', 'Article du voisin',
        5000, 'sc_hightech_accessoires', 3, true)
on conflict (id) do nothing;

insert into public.produits_prive (produit_id, prix_grossiste)
values ('prod_essai_voisin', 3000) on conflict (produit_id) do nothing;

-- Une ligne d'historique, pour que « le visiteur n'en voit rien » veuille
-- dire quelque chose.
insert into public.journal (utilisateur, famille, action, libelle, boutique_id)
values ('enseigne@bizzoo.bj', 'produit', 'modification',
        'Ligne de décor', 'bou_informatique');

-- L'enseigne élève les deux comptes, comme elle le ferait à l'écran.
update public.profils set role = 'administrateur', actif = true,
       boutique_id = 'bou_informatique' where id = :CHEF::uuid;
update public.profils set role = 'moderateur', actif = true,
       boutique_id = 'bou_essai_voisine' where id = :EQUIPE::uuid;

select essai.egal((select role from public.profils where id = :ENSEIGNE::uuid),
  'superadministrateur', 'le premier compte est le superadministrateur');

-- ---------------------------------------------------------
select essai.titre('Un visiteur : il regarde, il n''écrit pas');
-- ---------------------------------------------------------
select essai.personne();
set role anon;

select essai.verifie((select count(*) > 0 from public.boutiques),
  'un visiteur voit les boutiques');
select essai.verifie((select count(*) > 0 from public.produits),
  'un visiteur voit les produits');
select essai.verifie((select count(*) >= 0 from public.slides),
  'un visiteur voit le slider');

select essai.refuse($$select count(*) from public.produits_prive$$,
  'un visiteur lit les prix grossistes');
select essai.refuse(
  $$insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id)
    values ('prod_pirate', 'bou_informatique', 'Pirate', 1, 'sc_hightech_accessoires')$$,
  'un visiteur ajoute un produit');
select essai.sans_effet($$update public.produits set prix = 1 where id = 'prod_hp15'$$,
  'un visiteur change un prix');
-- Une règle de lecture ne lève pas d'erreur : elle écarte les lignes.
-- Zéro ligne là où la base en contient, c'est la porte qui tient.
select essai.egal((select count(*)::int from public.journal), 0,
  'le journal ne montre rien à un visiteur');
reset role;

-- ---------------------------------------------------------
select essai.titre('Un modérateur : sa boutique, et rien d''autre');
-- ---------------------------------------------------------
select essai.devenir(:EQUIPE::uuid);
set role authenticated;

select essai.sans_effet(
  $$update public.produits set prix = 1 where id = 'prod_hp15'$$,
  'un modérateur change le prix d''un produit d''une AUTRE boutique');

select essai.verifie(
  (select count(*) = 1 from public.produits_prive where produit_id = 'prod_essai_voisin'),
  'un modérateur voit le prix grossiste de SA boutique');

select essai.verifie(
  (select count(*) = 0 from public.produits_prive where produit_id = 'prod_hp15'),
  'mais pas celui de la boutique voisine');

select essai.refuse(
  $$insert into public.boutiques (id, nom, ordre) values ('bou_pirate', 'Pirate', 99)$$,
  'un modérateur crée une boutique');

select essai.sans_effet(
  $$update public.profils set role = 'superadministrateur'
     where id = '33333333-3333-3333-3333-333333333333'::uuid$$,
  'un modérateur se promeut lui-même');
select essai.egal((select role from public.profils
                    where id = '33333333-3333-3333-3333-333333333333'::uuid),
  'moderateur', 'et il reste modérateur');

select essai.refuse(
  $$insert into public.slides (id, portee, titre, ordre)
    values ('slide_pirate', 'enseigne', 'Pirate', 1)$$,
  'un modérateur écrit dans le slider de BIZZOO');
reset role;

-- ---------------------------------------------------------
select essai.titre('Un administrateur : chez lui, sous le regard de l''enseigne');
-- ---------------------------------------------------------
select essai.devenir(:CHEF::uuid);
set role authenticated;

select essai.verifie(
  (select count(*) > 0 from public.produits where boutique_id = 'bou_informatique'),
  'un administrateur voit son catalogue');

select essai.sans_effet(
  $$update public.boutiques set actif = false where id = 'bou_informatique'$$,
  'un administrateur ferme sa propre boutique');

select essai.refuse(
  $$update public.boutiques set nom = 'AUTRE NOM' where id = 'bou_informatique'$$,
  'un administrateur change le nom de sa boutique sans demander');

select essai.refuse(
  $$update public.boutiques set logo = 'boutiques/pirate.jpg' where id = 'bou_informatique'$$,
  'un administrateur change son logo sans demander');

select essai.sans_effet(
  $$update public.boutique set nom = 'PIRATE' where id = 1$$,
  'un administrateur retouche l''enseigne');

select essai.refuse(
  $$insert into public.slides (id, boutique_id, portee, titre, ordre)
    values ('slide_dem', 'bou_informatique', 'boutique', 'Sans demander', 1)$$,
  'un administrateur ajoute un écran à son slider sans demander');

-- Ce qui lui appartient : le slogan, les horaires, sa marge, son catalogue.
update public.boutiques set slogan = 'Notre slogan' where id = 'bou_informatique';
select essai.egal((select slogan from public.boutiques where id = 'bou_informatique'),
  'Notre slogan', 'mais son slogan lui appartient');

-- Et il dépose une demande, que lui seul ne peut pas approuver.
insert into public.demandes (id, boutique_id, type, objet, avant, apres)
values ('dem_essai', 'bou_informatique', 'reglages', 'Nom',
        '{"nom":"INFORMATIQUE ET ELECTRONIQUE"}'::jsonb,
        '{"nom":"INFORMATIQUE DU BENIN"}'::jsonb);

select essai.egal((select etat from public.demandes where id = 'dem_essai'),
  'en_attente', 'sa demande part « en attente »');
select essai.verifie(
  (select demande_par <> '' from public.demandes where id = 'dem_essai'),
  'et elle est signée de son auteur par la base, pas par l''écran');

select essai.refuse($$select public.approuver_demande('dem_essai')$$,
  'un administrateur approuve sa propre demande');
reset role;

-- ---------------------------------------------------------
select essai.titre('L''enseigne tranche');
-- ---------------------------------------------------------
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;

select public.approuver_demande('dem_essai');
reset role;

select essai.egal((select nom from public.boutiques where id = 'bou_informatique'),
  'INFORMATIQUE DU BENIN', 'approuvée, la modification s''applique');
select essai.egal((select etat from public.demandes where id = 'dem_essai'),
  'approuvee', 'et la demande est classée');

select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
update public.boutiques set actif = false where id = 'bou_essai_voisine';
select essai.egal((select actif from public.boutiques where id = 'bou_essai_voisine'),
  false, 'l''enseigne, elle, ferme une boutique');
update public.boutiques set actif = true where id = 'bou_essai_voisine';
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Les commandes : chaque boutique sa part');
-- ---------------------------------------------------------
-- Une commande qui couvre les deux boutiques.
set role anon;
select public.creer_commande('{"nom":"Cliente","tel":"95001122"}'::jsonb,
  '[{"produit_id":"prod_essai_voisin","quantite":2},
    {"produit_id":"prod_hp15","quantite":1}]'::jsonb) ->> 'id' as partagee \gset
reset role;

select essai.egal(
  (select count(*)::int from public.commande_lignes where commande_id = :'partagee'),
  2, 'la commande couvre bien deux boutiques');

select essai.devenir(:EQUIPE::uuid);
set role authenticated;
select essai.egal(
  (select count(*)::int from public.commande_lignes where commande_id = :'partagee'),
  1, 'le modérateur ne voit que la ligne de sa boutique');
select essai.egal(
  (select boutique_id from public.commande_lignes where commande_id = :'partagee'),
  'bou_essai_voisine', 'et c''est bien la sienne');

-- Il avance SA ligne, et seulement son état.
update public.commande_lignes set etat = 'vue'
 where commande_id = :'partagee' and boutique_id = 'bou_essai_voisine';
select essai.egal(
  (select etat from public.commande_lignes
    where commande_id = :'partagee' and boutique_id = 'bou_essai_voisine'),
  'vue', 'il fait avancer sa ligne');
reset role;

select essai.egal(
  (select etat from public.commande_lignes
    where commande_id = :'partagee' and boutique_id = 'bou_informatique'),
  'nouvelle', 'sans toucher à celle de la boutique voisine');

select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.egal(
  (select count(*)::int from public.commande_lignes where commande_id = :'partagee'),
  2, 'l''enseigne, elle, voit toute la commande');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Le journal ne se laisse pas forger');
-- ---------------------------------------------------------
select essai.devenir(:EQUIPE::uuid);
set role authenticated;
-- Sans « returning » : le modérateur alimente le journal, il ne le
-- relit pas. Le demander en même temps qu'on écrit, c'est demander à
-- lire — et la base a raison de refuser.
insert into public.journal (utilisateur, famille, action, libelle, boutique_id)
values ('quelqu-un-dautre@ailleurs.bj', 'produit', 'modification',
        'Signé du nom d''un autre', 'bou_essai_voisine');

select essai.egal((select count(*)::int from public.journal), 0,
  'un modérateur n''a pas accès à l''historique');
reset role;

select essai.verifie(
  (select utilisateur <> 'quelqu-un-dautre@ailleurs.bj' from public.journal
    where libelle = 'Signé du nom d''un autre'),
  'on ne signe le journal que de son propre nom');
select essai.devenir(:EQUIPE::uuid);
set role authenticated;

select essai.refuse(
  $$insert into public.journal (utilisateur, famille, action, libelle, cible_table, retour)
    values ('', 'produit', 'modification', 'Piège', 'pg_class',
            '{"avant":[],"ids":[{"table":"pg_class","id":"x"}]}'::jsonb)$$,
  'on ne tend pas un piège avec une table interdite');
reset role;
select essai.personne();
