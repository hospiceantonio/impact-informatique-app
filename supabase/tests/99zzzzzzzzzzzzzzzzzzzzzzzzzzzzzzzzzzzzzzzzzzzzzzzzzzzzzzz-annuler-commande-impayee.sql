-- =========================================================
-- Le client annule une commande qu'il n'a pas payée (4.4.0)
--
-- Ce qu'on prouve :
--   1. seule l'Edge Function l'annule : ni un compte ni un visiteur
--      n'appellent la fonction ;
--   2. une nouvelle demande de paiement partie entre-temps empêche
--      l'annulation ;
--   3. une commande « à payer » passe à « annulée », avec sa remarque ;
--      la seconde fois, rien ne change ;
--   4. une commande annulée ne rouvre plus de paiement ;
--   5. un versement qui arriverait malgré tout la remet à « payée » :
--      l'argent d'un client ne se perd pas ;
--   6. une commande payée ne s'annule pas ici.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''

select essai.titre('Le décor : deux commandes à payer');
insert into public.boutiques (id, nom, secteur, devise, actif, ordre, categorie_id)
values ('bou_ann', 'BOUTIQUE ANNULATION', 'Essai', 'FCFA', true, 96, 'cat_hightech') on conflict (id) do nothing;
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_ann', 'bou_ann', 'Poulet braisé', 3000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true, masque = false;
insert into public.produits_prive (produit_id, prix_grossiste) values ('prod_ann', 2500)
on conflict (produit_id) do nothing;

select essai.devenir(:ACHETEUR::uuid);
set role authenticated;
select public.creer_commande(jsonb_build_object('nom', 'Ablawa', 'tel', '97666089', 'adresse', 'Gbégamey'),
  '[{"produit_id":"prod_ann","quantite":1}]'::jsonb, '', true, true) as g1 \gset
select public.creer_commande(jsonb_build_object('nom', 'Ablawa', 'tel', '97666089', 'adresse', 'Gbégamey'),
  '[{"produit_id":"prod_ann","quantite":1}]'::jsonb, '', true, true) as g2 \gset
reset role;
select essai.personne();
select :'g1'::jsonb ->> 'id' as c1 \gset
select :'g2'::jsonb ->> 'id' as c2 \gset
select (select stock from public.produits where id = 'prod_ann') as stock_avant \gset

select essai.titre('1. Seule l''Edge Function annule');
select essai.devenir(:ACHETEUR::uuid);
set role authenticated;
select essai.refuse(format($$select public.annuler_commande_impayee(%L, '')$$, :'c1'),
  'le client lui-même n''appelle pas la fonction : c''est le serveur qui vérifie chez FeexPay d''abord');
reset role;
select essai.personne();
set role anon;
select essai.refuse(format($$select public.annuler_commande_impayee(%L, '')$$, :'c1'),
  'un visiteur non plus');
reset role;

select essai.titre('2. Une nouvelle demande partie entre-temps empêche l''annulation');
select essai.verifie(public.noter_reference(:'c1', 'ref_ann_001'), 'une demande de paiement part');
select essai.egal(public.annuler_commande_impayee(:'c1', '') ->> 'raison', 'nouvelle demande',
  'annuler sur la foi d''une vérification d''avant cette demande : refusé');
select essai.egal((select etat from public.commandes where id = :'c1'), 'a_payer', 'la commande attend toujours');

select essai.titre('3. La commande à payer passe à « annulée »');
select public.annuler_commande_impayee(:'c1', 'ref_ann_001') as r \gset
select essai.verifie((:'r'::jsonb ->> 'ok')::boolean, 'la référence vérifiée : annulée');
select essai.egal((select etat from public.commandes where id = :'c1'), 'annulee', 'son état le dit');
select essai.verifie((select remarque like 'Annulée par le client avant paiement%' from public.commandes where id = :'c1'),
  'et sa remarque dit qui l''a annulée');
select essai.egal((select stock from public.produits where id = 'prod_ann'), :'stock_avant'::int,
  'le stock n''a pas bougé : il ne suit que le paiement');
select essai.verifie((public.annuler_commande_impayee(:'c1', 'ref_ann_001') ->> 'deja')::boolean,
  'la seconde fois : déjà annulée, rien ne change');
select essai.verifie(public.annuler_commande_impayee(:'c2', '') ->> 'ok' = 'true',
  'une commande sans aucune demande de paiement s''annule aussi');

select essai.titre('4. Une commande annulée ne rouvre plus de paiement');
-- Le frein des trente secondes levé, à la main : la base écrit pour elle-même.
begin;
select set_config('bizzoo.interne', 'oui', true) \gset
update public.commandes set tentative_le = now() - interval '5 minutes' where id = :'c1';
commit;
select essai.verifie(not public.noter_reference(:'c1', 'ref_ann_002'), 'aucune nouvelle demande ne part');

select essai.titre('5. Un versement arrivé malgré tout : la commande est payée');
select public.marquer_payee(:'c1', 'TRX-ANN-1', (:'g1'::jsonb ->> 'acompte')::int, 'feexpay') as p \gset
select essai.egal((select etat from public.commandes where id = :'c1'), 'payee',
  'l''argent du client ne se perd pas dans une commande annulée');

select essai.titre('6. Une commande payée ne s''annule pas ici');
select essai.egal(public.annuler_commande_impayee(:'c1', 'ref_ann_001') ->> 'raison', 'etat',
  'payée : refusé');
select essai.egal((select etat from public.commandes where id = :'c1'), 'payee', 'elle reste payée');
