-- =========================================================
-- La marge de l'enseigne, et ce que rapporte une boutique.
--
--   prix de vente = prix BIZZOO + marge
--   bénéfice      = prix de vente − prix BIZZOO
--
-- Ce qu'on éprouve ici :
--   1. une boutique ne fixe pas la commission que BIZZOO
--      prend sur elle ;
--   2. ce qui a été vendu garde ses chiffres — changer la
--      marge demain ne réécrit pas les comptes d'hier ;
--   3. ces chiffres ne se lisent que depuis l'enseigne.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''

select essai.titre('Le décor : une boutique à 25 % de marge');

-- L'enseigne pose la marge, comme elle le ferait en créant la boutique.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
update public.boutiques set taux_marge = 25 where id = 'bou_informatique';
reset role;
select essai.personne();

select essai.egal((select taux_marge from public.boutiques where id = 'bou_informatique'),
  25::numeric, 'l''enseigne fixe la marge de la boutique');

-- Un produit : la boutique veut toucher 8 000, l'enseigne vend 10 000.
insert into public.produits
  (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_marge', 'bou_informatique', 'Article à marge', 10000,
        'sc_hightech_accessoires', 10, true)
on conflict (id) do update set prix = 10000;
insert into public.produits_prive (produit_id, prix_grossiste)
values ('prod_marge', 8000)
on conflict (produit_id) do update set prix_grossiste = 8000;

-- ---------------------------------------------------------
select essai.titre('La marge appartient à l''enseigne');
-- ---------------------------------------------------------
select essai.devenir(:CHEF::uuid);
set role authenticated;

select essai.refuse(
  $$update public.boutiques set taux_marge = 0 where id = 'bou_informatique'$$,
  'une boutique se fixe une marge de zéro');
select essai.refuse(
  $$update public.boutiques set taux_marge = 200 where id = 'bou_informatique'$$,
  'une boutique gonfle la marge de l''enseigne');
reset role;
select essai.personne();

select essai.egal((select taux_marge from public.boutiques where id = 'bou_informatique'),
  25::numeric, 'la marge n''a pas bougé');

-- ---------------------------------------------------------
select essai.titre('Ce qui a été vendu garde ses chiffres');
-- ---------------------------------------------------------
set role anon;
select public.creer_commande('{"nom":"Acheteuse","tel":"97223344"}'::jsonb,
  '[{"produit_id":"prod_marge","quantite":3}]'::jsonb) ->> 'id' as vente \gset
reset role;

select essai.egal((select prix from public.commande_lignes where commande_id = :'vente'),
  10000, 'la ligne porte le prix de vente');
select essai.egal((select prix_bizzoo from public.commande_lignes where commande_id = :'vente'),
  8000, 'et le prix BIZZOO du jour');
select essai.egal((select taux_marge from public.commande_lignes where commande_id = :'vente'),
  25::numeric, 'et la marge du jour');

-- Le prix BIZZOO ne sort pas : le récapitulatif du client n'en dit rien.
set role anon;
select public.creer_commande('{"nom":"Curieux","tel":"97556677"}'::jsonb,
  '[{"produit_id":"prod_marge","quantite":1}]'::jsonb) as recu \gset
reset role;
select essai.verifie(
  ((:'recu'::jsonb -> 'boutiques' -> 0 -> 'lignes' -> 0) ->> 'prix_bizzoo') is null,
  'ce que la boutique touche ne part pas chez le client');

-- On encaisse, puis on change la marge : les comptes d'hier tiennent.
select public.marquer_payee(:'vente', 'TRX-MARGE',
  (select total from public.commandes where id = :'vente')) as encaisse \gset
select essai.egal((select etat from public.commandes where id = :'vente'),
  'payee', 'la vente est encaissée');

select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
update public.boutiques set taux_marge = 60 where id = 'bou_informatique';
reset role;
select essai.personne();

select essai.egal((select taux_marge from public.commande_lignes where commande_id = :'vente'),
  25::numeric, 'la marge passée à 60 % ne réécrit pas la vente d''hier');
select essai.refuse(
  format($$update public.commande_lignes set prix_bizzoo = 1 where commande_id = %L$$, :'vente'),
  'réécrire le prix BIZZOO d''une ligne vendue');

-- ---------------------------------------------------------
select essai.titre('La marge change, les prix de la vitrine suivent');
-- ---------------------------------------------------------
-- C'est le pendant exact de la ligne ci-dessus. Ce qui est VENDU ne
-- bouge plus ; ce qui est EN VITRINE, si.
--
-- Le prix de vente était calculé par l'application au moment
-- d'enregistrer le produit, puis figé dans la table. Changer la marge
-- d'une boutique ne touchait donc rien : il fallait rouvrir et
-- réenregistrer chaque article, un par un. Personne ne fait cela sur
-- deux cents articles — et la marge annoncée dans les réglages
-- divergeait en silence de celle réellement pratiquée.
select essai.egal((select prix from public.produits where id = 'prod_marge')::int,
  12800, 'la marge passée à 60 % déplace le prix : 8 000 + 60 %');

-- Deux articles pour éprouver ce que le recalcul ne doit PAS toucher.
insert into public.produits
  (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_taux_propre', 'bou_informatique', 'Article à taux propre', 9999,
        'sc_hightech_accessoires', 5, true),
       ('prod_sans_achat', 'bou_informatique', 'Article sans prix BIZZOO', 7000,
        'sc_hightech_accessoires', 5, true)
on conflict (id) do update set prix = excluded.prix, stock = 5, disponible = true;
insert into public.produits_prive (produit_id, prix_grossiste, taux_marge)
values ('prod_taux_propre', 5000, 10)
on conflict (produit_id) do update set prix_grossiste = 5000, taux_marge = 10;
delete from public.produits_prive where produit_id = 'prod_sans_achat';

select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
update public.boutiques set taux_marge = 30 where id = 'bou_informatique';
reset role;
select essai.personne();

select essai.egal((select prix from public.produits where id = 'prod_marge')::int,
  10400, 'et le suit encore : 8 000 + 30 %');
-- Un article qui a SON taux ne dépend pas de celui de la boutique.
-- C'est déjà la règle que « produits_prive.taux_marge » suit partout.
--
-- Son prix de départ est VOLONTAIREMENT faux (9 999) : ainsi la ligne
-- est forcément reprise, et c'est le CALCUL — et lui seul — qui décide
-- du résultat. Avec un prix déjà juste, un calcul cassé passerait
-- inaperçu, la ligne étant écartée avant même d'être recalculée. Le
-- banc l'a montré : sabotage posé, tout restait vert.
select essai.egal((select prix from public.produits where id = 'prod_taux_propre')::int,
  5500, 'un article à taux propre est recalculé au SIEN : 5 000 + 10 %');
-- Et sans prix BIZZOO, il n'y a rien à calculer : on n'invente pas.
select essai.egal((select prix from public.produits where id = 'prod_sans_achat')::int,
  7000, 'un article sans prix BIZZOO n''est pas touché');

-- Ce qui a été vendu, lui, n'a toujours pas bougé.
select essai.egal((select taux_marge from public.commande_lignes where commande_id = :'vente'),
  25::numeric, 'après deux changements de marge, la vente d''hier tient encore');

-- Et le calcul de la base est celui de l'application, au franc près :
-- s'ils divergeaient, réenregistrer un produit déplacerait son prix
-- sans que personne ne l'ait demandé.
select essai.egal(public.prix_public(8000, 30), 10400, '8 000 + 30 %');
select essai.egal(public.prix_public(7777, 20), 9332, '7 777 + 20 % = 9 332,4 → 9 332');
select essai.egal(public.prix_public(0, 30), 0, 'sans prix BIZZOO, zéro — et non un prix inventé');
select essai.egal(public.prix_public(5000, 0), 5000, 'sans marge, le prix BIZZOO nu');

-- ---------------------------------------------------------
select essai.titre('Ce que la boutique rapporte');
-- ---------------------------------------------------------
set role anon;
select essai.refuse($$select * from public.statistiques_ventes()$$,
  'un visiteur lit les comptes de l''enseigne');
reset role;

select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.refuse($$select * from public.statistiques_ventes()$$,
  'une boutique lit les comptes de l''enseigne');
reset role;

select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;

select quantite, prix_bizzoo, prix_vente, benefice, total_vente
  from public.statistiques_ventes() where produit_id = 'prod_marge' \gset

select essai.egal(:quantite::bigint, 3::bigint, 'trois exemplaires vendus');
select essai.egal(:prix_bizzoo::bigint, 8000::bigint, 'prix BIZZOO unitaire');
select essai.egal(:prix_vente::bigint, 10000::bigint, 'prix de vente unitaire');
select essai.egal(:total_vente::bigint, 30000::bigint, 'ce que le client a payé');
select essai.egal(:benefice::bigint, 6000::bigint,
  'le bénéfice de l''enseigne : (10 000 − 8 000) × 3');

-- La commande non payée ne compte pas : ce n'est pas une vente.
select essai.egal(
  (select coalesce(sum(quantite), 0)::bigint from public.statistiques_ventes()
    where produit_id = 'prod_marge'),
  3::bigint, 'une commande à payer n''entre pas dans les comptes');

-- Le filtre par boutique.
select essai.verifie(
  (select count(*) = 0 from public.statistiques_ventes(null, null, 'bou_essai_voisine')
    where produit_id = 'prod_marge'),
  'filtrée sur une autre boutique, la vente disparaît');
select essai.verifie(
  (select count(*) > 0 from public.statistiques_ventes(null, null, 'bou_informatique')
    where produit_id = 'prod_marge'),
  'filtrée sur la sienne, elle est là');

-- Le filtre par période.
select essai.verifie(
  (select count(*) > 0 from public.statistiques_ventes(current_date, current_date)
    where produit_id = 'prod_marge'),
  'la vente du jour entre dans la période du jour');
select essai.verifie(
  (select count(*) = 0 from public.statistiques_ventes(current_date + 1, current_date + 30)
    where produit_id = 'prod_marge'),
  'et pas dans celle de demain');
select essai.verifie(
  (select count(*) = 0 from public.statistiques_ventes(current_date - 30, current_date - 1)
    where produit_id = 'prod_marge'),
  'ni dans celle du mois dernier');
reset role;
select essai.personne();
