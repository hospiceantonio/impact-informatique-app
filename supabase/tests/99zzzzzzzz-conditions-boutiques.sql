-- =========================================================
-- Chaque boutique : ses conditions de paiement, ses frais (3.59.0)
--
-- Ce qu'on prouve :
--   1. les réglages sont bornés (mode, taux de 1 à 99 %, frais) ; la
--      boutique règle les siens ;
--   2. une commande sur deux boutiques : l'une se paie en entier à la
--      commande, l'autre par acompte de 30 % ; chacune ajoute SES frais ;
--      la base calcule ce qui se paie maintenant et ce qui reste ;
--   3. à la livraison, chaque livreur encaisse la part de SA boutique ;
--   4. la remise d'un code promo se répartit au prorata, sans toucher
--      aux frais.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''

select essai.titre('1. Les réglages de chaque boutique');
select essai.refuse($$update public.boutiques set mode_paiement = 'credit' where id = 'bou_informatique'$$,
  'un mode inconnu : refusé');
select essai.refuse($$update public.boutiques set taux_acompte = 0 where id = 'bou_informatique'$$,
  'un acompte de 0 % : refusé (c''est « tout à la livraison »)');
select essai.refuse($$update public.boutiques set taux_acompte = 100 where id = 'bou_informatique'$$,
  'un acompte de 100 % : refusé (c''est « tout à la commande »)');
select essai.refuse($$update public.boutiques set frais_livraison = -1 where id = 'bou_informatique'$$,
  'des frais négatifs : refusés');

select essai.devenir(:CHEF::uuid); set role authenticated;
update public.boutiques set mode_paiement = 'total', frais_livraison = 1500 where id = 'bou_informatique';
reset role; select essai.personne();
select essai.egal((select mode_paiement || '/' || frais_livraison from public.boutiques where id = 'bou_informatique'),
  'total/1500', 'l''administrateur de la boutique règle les siens');
update public.boutiques set mode_paiement = 'acompte', taux_acompte = 30, frais_livraison = 500,
       ouvertures = null where id = 'bou_essai_voisine';
update public.boutiques set ouvertures = null where id = 'bou_informatique';

select essai.titre('2. Deux boutiques, deux conditions');
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible) values
  ('prod_cond_a', 'bou_informatique', 'Écran', 10000, 'sc_hightech_accessoires', 50, true),
  ('prod_cond_b', 'bou_essai_voisine', 'Chaise', 20000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true;
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666004","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_cond_a","quantite":1},{"produit_id":"prod_cond_b","quantite":1}]'::jsonb,
  '', true, true) as c \gset
reset role; select essai.personne();
select essai.egal((:'c'::jsonb ->> 'frais_livraison')::bigint, 2000::bigint,
  'les frais : 1 500 + 500, ceux de chaque boutique');
select essai.egal((:'c'::jsonb ->> 'total')::bigint, 32000::bigint, 'total : 30 000 + 2 000');
select essai.egal((:'c'::jsonb -> 'parts' -> 'bou_informatique' ->> 'acompte')::bigint, 11500::bigint,
  'l''informatique se paie en entier à la commande : 10 000 + 1 500');
select essai.egal((:'c'::jsonb -> 'parts' -> 'bou_essai_voisine' ->> 'acompte')::bigint, 6150::bigint,
  'la voisine, 30 % de 20 500 : 6 150');
select essai.egal((:'c'::jsonb ->> 'acompte')::bigint, 17650::bigint, 'à payer maintenant : 17 650');
select essai.egal((:'c'::jsonb ->> 'reste')::bigint, 14350::bigint, 'à la livraison : 14 350');

select essai.titre('3. Chaque livreur encaisse la part de sa boutique');
select essai.egal((select a_encaisser from public.restes_par_boutique(:'c'::jsonb ->> 'id')
                    where boutique_id = 'bou_informatique'), 0::bigint,
  'l''informatique : rien à encaisser, tout est payé');
select essai.egal((select a_encaisser from public.restes_par_boutique(:'c'::jsonb ->> 'id')
                    where boutique_id = 'bou_essai_voisine'), 14350::bigint,
  'la voisine : 14 350 à la porte');
select public.marquer_payee(:'c'::jsonb ->> 'id', 'TRX-COND', 17650, 'feexpay') as p \gset
select essai.egal((select sum(a_encaisser) from public.restes_par_boutique(:'c'::jsonb ->> 'id')),
  14350::numeric, 'l''acompte payé, il reste toujours 14 350');

select essai.titre('4. Un code promo se répartit, les frais restent');
insert into public.codes_promo (code, libelle, mode, valeur, actif)
values ('COND10', 'Essai conditions', 'pourcent', 10, true)
on conflict (code) do update set actif = true, mode = 'pourcent', valeur = 10;
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666004","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_cond_a","quantite":1},{"produit_id":"prod_cond_b","quantite":1}]'::jsonb,
  'COND10', true, true) as d \gset
reset role; select essai.personne();
select essai.egal(
  (:'d'::jsonb -> 'parts' -> 'bou_informatique' ->> 'du')::bigint
  + (:'d'::jsonb -> 'parts' -> 'bou_essai_voisine' ->> 'du')::bigint,
  (:'d'::jsonb ->> 'total')::bigint, 'les parts font le total, remise déduite');
select essai.egal((:'d'::jsonb -> 'parts' -> 'bou_informatique' ->> 'frais')::bigint, 1500::bigint,
  'les frais ne bougent pas');

update public.boutiques set mode_paiement = 'acompte', taux_acompte = 10, frais_livraison = 1000
 where id in ('bou_informatique', 'bou_essai_voisine');
