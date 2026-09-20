-- =========================================================
-- Le cycle de vie d'une commande, et qui dit quoi.
--
-- Cinq étapes chez la boutique :
--
--   nouvelle → vue → préparée → en livraison → remise
--
-- Et un sixième fait, qui n'appartient PAS à la boutique :
-- l'accusé de réception du client.
--
-- C'est là tout l'objet de ce fichier. « remise » est ce que
-- la BOUTIQUE déclare ; « confirme_le » est ce que le CLIENT
-- constate. Si l'un pouvait signer pour l'autre, la
-- déclaration de la boutique n'aurait plus aucune valeur — et
-- c'est justement elle qu'un litige vient interroger.
--
-- Quatre choses à prouver :
--
--   1. LA BOUTIQUE AVANCE SA LIGNE, et rien d'autre ;
--   2. LE CLIENT NE LA FAIT PAS AVANCER à sa place ;
--   3. LA BOUTIQUE NE SIGNE PAS L'ACCUSÉ DE RÉCEPTION ;
--   4. ON NE CONFIRME PAS CE QUI N'A PAS ÉTÉ REMIS.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set EQUIPE   '''33333333-3333-3333-3333-333333333333'''
\set KOFI     '''55555555-5555-5555-5555-555555555555'''

select essai.titre('Le décor : une commande payée, chez deux boutiques');

insert into public.produits
  (id, boutique_id, nom, prix, categorie_id, stock, disponible)
values ('prod_cycle_a', 'bou_informatique', 'Souris sans fil', 7000,
        'cat_accessoires', 50, true),
       ('prod_cycle_b', 'bou_essai_voisine', 'Tapis de souris', 2000,
        'cat_essai_voisine', 50, true)
on conflict (id) do update
   set prix = excluded.prix, stock = 50, disponible = true;

select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97222222"}'::jsonb,
  '[{"produit_id":"prod_cycle_a","quantite":1},
    {"produit_id":"prod_cycle_b","quantite":1}]'::jsonb) ->> 'id' as vente \gset
reset role;
select essai.personne();

select public.marquer_payee(:'vente', 'TRX-CYCLE-1',
  (select total from public.commandes where id = :'vente'), 'feexpay') as encaisse \gset
select essai.egal((select etat from public.commandes where id = :'vente'),
  'payee', 'la commande est payée');
select essai.egal((select count(*)::int from public.commande_lignes
                    where commande_id = :'vente' and etat = 'nouvelle'), 2,
  'et ses deux lignes sont « nouvelles »');

-- ---------------------------------------------------------
select essai.titre('La boutique avance sa ligne, une étape à la fois');
-- ---------------------------------------------------------
select id as ligne_a from public.commande_lignes
 where commande_id = :'vente' and boutique_id = 'bou_informatique' \gset
select id as ligne_b from public.commande_lignes
 where commande_id = :'vente' and boutique_id = 'bou_essai_voisine' \gset

select essai.devenir(:CHEF::uuid);
set role authenticated;
update public.commande_lignes set etat = 'vue' where id = :'ligne_a';
select essai.egal((select etat from public.commande_lignes where id = :'ligne_a'),
  'vue', 'vue');
update public.commande_lignes set etat = 'preparee' where id = :'ligne_a';
select essai.egal((select etat from public.commande_lignes where id = :'ligne_a'),
  'preparee', 'préparée');
-- L'ÉTAPE NOUVELLE. Sans elle, la marchandise passait du comptoir au
-- client sans que rien ne dise qu'elle était partie.
update public.commande_lignes set etat = 'en_livraison' where id = :'ligne_a';
select essai.egal((select etat from public.commande_lignes where id = :'ligne_a'),
  'en_livraison', 'en livraison');
update public.commande_lignes set etat = 'remise' where id = :'ligne_a';
select essai.egal((select etat from public.commande_lignes where id = :'ligne_a'),
  'remise', 'remise au client');

-- Et elle ne touche pas à la ligne de la voisine.
--
-- ATTENTION À LA FORME DE CET ESSAI. Une règle RLS ne LÈVE PAS : elle
-- filtre. L'écriture ci-dessous ne trouve aucune ligne que le chef ait
-- le droit de toucher, et réussit donc en silence. Attendre un refus
-- ferait échouer l'essai pour la mauvaise raison — ce qu'il faut
-- constater, c'est que RIEN n'a bougé.
update public.commande_lignes set etat = 'remise'
 where boutique_id = 'bou_essai_voisine';
reset role;
select essai.personne();

select essai.egal((select etat from public.commande_lignes where id = :'ligne_b'),
  'nouvelle', 'la ligne du voisin n''a pas bougé d''un pouce');

-- ---------------------------------------------------------
select essai.titre('Un état qui n''existe pas n''entre pas');
-- ---------------------------------------------------------
select essai.devenir(:CHEF::uuid);
set role authenticated;
-- Ici la ligne EST visible au chef : la contrainte se prononce donc, et
-- elle lève pour de bon.
select essai.refuse(
  format($$update public.commande_lignes set etat = 'livree_peut_etre'
            where id = %L$$, :'ligne_a'),
  'un état inventé passe la contrainte');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('LE CLIENT NE FAIT PAS AVANCER LA PRÉPARATION');
-- ---------------------------------------------------------
-- Ce serait se livrer à soi-même. La boutique est seule à savoir ce
-- qu'elle a préparé.
-- Même forme que plus haut : RLS filtre, elle ne lève pas. On regarde
-- donc ce que la ligne vaut APRÈS, pas si l'appel a crié.
select essai.devenir(:KOFI::uuid);
set role authenticated;
update public.commande_lignes set etat = 'remise' where id = :'ligne_b';
reset role;
select essai.personne();
select essai.egal((select etat from public.commande_lignes where id = :'ligne_b'),
  'nouvelle', 'le client ne déclare pas sa commande remise');

-- ---------------------------------------------------------
select essai.titre('LA BOUTIQUE NE SIGNE PAS L''ACCUSÉ DE RÉCEPTION');
-- ---------------------------------------------------------
-- LE CONSTAT DE CE FICHIER. Si la boutique pouvait poser elle-même
-- « confirme_le », sa propre déclaration « remise » n'aurait plus de
-- contrepoids, et un litige n'aurait plus rien à interroger.
select essai.devenir(:CHEF::uuid);
set role authenticated;
-- Le verrou, lui, LÈVE : ce n'est pas RLS, c'est un déclencheur. La
-- ligne est bien visible au chef, et l'écriture est refusée en face.
select essai.refuse(
  format($$update public.commande_lignes set confirme_le = now() where id = %L$$,
    :'ligne_a'),
  'la boutique signe pour le client');
select essai.refuse(
  $$select public.confirmer_reception(
      (select id from public.commandes order by cree_le desc limit 1),
      'bou_informatique')$$,
  'ou passe par la fonction du client');
reset role;
select essai.personne();

-- L'enseigne non plus : ce n'est pas elle qui a reçu la marchandise.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.refuse(
  $$select public.confirmer_reception(
      (select id from public.commandes order by cree_le desc limit 1),
      'bou_informatique')$$,
  'l''enseigne signe à la place du client');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Le client confirme, et lui seul');
-- ---------------------------------------------------------
select essai.devenir(:KOFI::uuid);
set role authenticated;

-- D'abord ce qui ne se confirme PAS : la voisine n'a rien remis.
select essai.refuse(
  $$select public.confirmer_reception(
      (select commande_id from public.commande_lignes
        where boutique_id = 'bou_essai_voisine' order by cree_le desc limit 1),
      'bou_essai_voisine')$$,
  'on confirme une boutique qui n''a rien remis');

select public.confirmer_reception(:'vente', 'bou_informatique') as combien \gset
select essai.egal(:'combien'::int, 1, 'la boutique qui a remis se confirme');
reset role;
select essai.personne();

select essai.verifie(
  (select confirme_le is not null from public.commande_lignes where id = :'ligne_a'),
  'et l''accusé est posé sur sa ligne');
select essai.verifie(
  (select confirme_le is null from public.commande_lignes where id = :'ligne_b'),
  'la ligne du voisin reste sans accusé : il n''a rien livré');

-- Deux fois de suite ne double rien, et le dit.
select essai.devenir(:KOFI::uuid);
set role authenticated;
select essai.refuse(
  $$select public.confirmer_reception(
      (select id from public.commandes order by cree_le desc limit 1),
      'bou_informatique')$$,
  'confirmer deux fois passe en silence');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('La commande d''un autre ne se confirme pas');
-- ---------------------------------------------------------
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.refuse(
  $$select public.confirmer_reception('cmd_qui_nexiste_pas', 'bou_informatique')$$,
  'une commande inconnue se confirme');
reset role;
select essai.personne();

set role anon;
select essai.refuse(
  $$select public.confirmer_reception('x', 'bou_informatique')$$,
  'un visiteur confirme une réception');
reset role;

-- ---------------------------------------------------------
select essai.titre('Ce que le client voit, et ce qu''il ne voit pas');
-- ---------------------------------------------------------
-- L'avancement le regarde : c'est sa commande. La marge, non.
select essai.devenir(:KOFI::uuid);
set role authenticated;
select essai.egal((select etat from public.commande_lignes where id = :'ligne_a'),
  'remise', 'le client lit l''état de sa ligne');
select essai.verifie(
  (select confirme_le is not null from public.commande_lignes where id = :'ligne_a'),
  'et son propre accusé de réception');
-- LA COLONNE, PAS LA LIGNE. Une règle RLS décide quelles lignes on voit,
-- jamais quelles colonnes : seul un droit par colonne ferme celles-ci.
select essai.refuse(
  $$select prix_bizzoo from public.commande_lignes where commande_id =
      (select id from public.commandes order by cree_le desc limit 1)$$,
  'le client lit le prix BIZZOO de sa propre ligne');
reset role;
select essai.personne();
