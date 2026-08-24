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
  (id, boutique_id, nom, prix, categorie_id, stock, disponible)
values ('prod_marge', 'bou_informatique', 'Article à marge', 10000,
        'cat_accessoires', 10, true)
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
