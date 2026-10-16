-- =========================================================
-- Les frais de livraison
--
-- Ce qu'on prouve :
--   1. 1 000 FCFA par défaut, réglés par l'enseigne ;
--   2. la nouvelle application les demande : total = articles + frais ;
--      une application d'avant ne les demande pas, et ne les paie pas ;
--   3. un code promo ne touche pas les frais ;
--   4. l'acompte se prend sur le total, frais compris ;
--   5. le reste à encaisser : les frais ne se réduisent pas au prorata,
--      et disparaissent si tout est annulé ;
--   6. personne ne réécrit les frais d'une commande ;
--   7. la commission d'un particulier ne se calcule pas sur les frais.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set PORTEUR2 '''cccccccc-7777-7777-7777-777777777777'''
\set PARRAIN  '''ffffffff-1111-1111-1111-111111111111'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''

select essai.titre('Le décor : deux articles, deux boutiques, un code de 10 %');

insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_frais_a', 'bou_informatique', 'Clavier', 10000, 'sc_hightech_accessoires', 100, true),
       ('prod_frais_b', 'bou_essai_voisine', 'Souris', 5000, 'sc_hightech_accessoires', 100, true)
on conflict (id) do update set prix = excluded.prix, stock = 100, disponible = true;
insert into public.produits_prive (produit_id, prix_grossiste)
values ('prod_frais_a', 6000), ('prod_frais_b', 3000)
on conflict (produit_id) do update set prix_grossiste = excluded.prix_grossiste;
insert into public.codes_promo (code, mode, valeur, une_par_client, actif)
values ('FRAIS10', 'pourcent', 10, false, true)
on conflict (code) do update set mode = 'pourcent', valeur = 10, actif = true,
  une_par_client = false, maximum = 0, minimum = 0, fin = null;

-- ---------------------------------------------------------
select essai.titre('1. Le réglage de l''enseigne');
select essai.egal((select frais_livraison from public.paiement where id = 1), 1000,
  'les frais de livraison valent 1 000 FCFA par défaut');
select essai.refuse($$update public.paiement set frais_livraison = -5 where id = 1$$,
  'des frais négatifs sont refusés');

select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.sans_effet($$update public.paiement set frais_livraison = 0 where id = 1$$,
  'un client ne change pas les frais');
reset role; select essai.personne();
select essai.egal((select frais_livraison from public.paiement where id = 1), 1000,
  'ils valent toujours 1 000');

-- ---------------------------------------------------------
select essai.titre('2. Total = articles + frais ; l''application d''avant n''en paie pas');

select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666002","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_frais_a","quantite":1}]'::jsonb, '', false, true) as c1 \gset
select public.creer_commande('{"nom":"Afi","tel":"97666002","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_frais_a","quantite":1}]'::jsonb, '', false) as ancien \gset
reset role; select essai.personne();

select essai.egal((:'c1'::jsonb ->> 'frais_livraison')::bigint, 1000::bigint,
  'la commande porte 1 000 de frais');
select essai.egal((:'c1'::jsonb ->> 'total')::bigint, 11000::bigint,
  'total : 10 000 d''articles + 1 000 de frais');
select essai.egal((:'ancien'::jsonb ->> 'total')::bigint, 10000::bigint,
  'une application d''avant (sans « avec_frais ») : 10 000, sans frais');
select essai.egal((select frais_livraison from public.commandes where id = :'ancien'::jsonb ->> 'id'),
  0::bigint, 'et sa commande n''a pas de frais');

-- ---------------------------------------------------------
select essai.titre('3. Le code promo ne touche pas les frais');

select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666002","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_frais_a","quantite":1}]'::jsonb, 'FRAIS10', false, true) as c2 \gset
reset role; select essai.personne();
select essai.egal((:'c2'::jsonb ->> 'remise')::bigint, 1000::bigint,
  'la remise : 10 % des articles (1 000), pas des frais');
select essai.egal((:'c2'::jsonb ->> 'total')::bigint, 10000::bigint,
  'total : 10 000 − 1 000 de remise + 1 000 de frais');

-- ---------------------------------------------------------
select essai.titre('4. L''acompte, frais compris');

update public.paiement set taux_acompte = 10 where id = 1;
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666002","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_frais_a","quantite":1},{"produit_id":"prod_frais_b","quantite":1}]'::jsonb,
  '', true, true) as c3 \gset
reset role; select essai.personne();
select essai.egal((:'c3'::jsonb ->> 'total')::bigint, 16000::bigint,
  'deux boutiques, une seule course : 15 000 + 1 000');
select essai.egal((:'c3'::jsonb ->> 'acompte')::bigint, 1600::bigint,
  'l''acompte de 10 % se prend sur 16 000');
select essai.egal((:'c3'::jsonb ->> 'reste')::bigint, 14400::bigint,
  'il reste 14 400 à payer à la livraison');
select essai.egal((select sum((x ->> 'a_encaisser')::bigint)
                     from jsonb_array_elements(:'c3'::jsonb -> 'boutiques') x), 14400::numeric,
  'les deux boutiques encaissent 14 400 à elles deux, au franc près');

-- ---------------------------------------------------------
select essai.titre('5. Annulations : la course garde son prix, sauf s''il n''y a plus de course');

select public.marquer_payee(:'c3'::jsonb ->> 'id', 'TRX-FRAIS', 1600, 'feexpay') as p3 \gset
-- La souris (5 000) est annulée : il reste le clavier (10 000) + la course.
update public.commande_lignes set etat = 'annulee'
 where commande_id = :'c3'::jsonb ->> 'id' and produit_id = 'prod_frais_b';
select essai.egal((select coalesce(sum(a_encaisser), 0) from public.restes_par_boutique(:'c3'::jsonb ->> 'id')),
  9400::numeric, 'une ligne annulée : 10 000 + 1 000 − 1 600 versés = 9 400');
update public.commande_lignes set etat = 'annulee'
 where commande_id = :'c3'::jsonb ->> 'id';
select essai.egal((select coalesce(sum(a_encaisser), 0) from public.restes_par_boutique(:'c3'::jsonb ->> 'id')),
  0::numeric, 'tout annulé : rien à encaisser, pas de course');

-- ---------------------------------------------------------
select essai.titre('6. Personne ne réécrit les frais');

select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.sans_effet(format($$update public.commandes set frais_livraison = 0 where id = %L$$,
  :'c1'::jsonb ->> 'id'), 'une boutique ne retire pas les frais d''une commande');
reset role; select essai.personne();
-- Même l'enseigne, qui suit toutes les commandes : refusé par le verrou.
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse(format($$update public.commandes set frais_livraison = 0 where id = %L$$,
  :'c1'::jsonb ->> 'id'), 'l''enseigne non plus : les frais sont figés');
reset role; select essai.personne();
select essai.egal((select frais_livraison from public.commandes where id = :'c1'::jsonb ->> 'id'),
  1000::bigint, 'ils valent toujours 1 000');

-- ---------------------------------------------------------
select essai.titre('7. La commission d''un particulier, hors frais');

update public.paiement set taux_acompte = 100 where id = 1;
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666002","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_frais_a","quantite":2}]'::jsonb, 'RODRIGUE', false, true) ->> 'id' as c4 \gset
reset role; select essai.personne();
-- 20 000 − 5 % (1 000) + 1 000 de frais = 20 000 payés.
select essai.egal((select total::bigint from public.commandes where id = :'c4'), 20000::bigint,
  'la commande : 20 000 − 1 000 de remise + 1 000 de frais');
select public.marquer_payee(:'c4', 'TRX-FRAIS-4', 20000, 'feexpay') as p4 \gset
insert into public.positions_livreurs (profil_id, latitude, longitude, adresse)
  select p.id, 6.3703, 2.3912, 'Cotonou (essai)' from public.profils p where p.role = 'livreur'
  on conflict (profil_id) do nothing;  -- les livreurs ont validé leur position
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'preparee' where commande_id = :'c4';
select public.assigner_livreur(:'c4', 'bou_informatique', :PORTEUR2::uuid) as n4 \gset
reset role; select essai.personne();
select essai.devenir(:PORTEUR2::uuid); set role authenticated;
select public.avancer_livraison(:'c4', 'bou_informatique', 'en_livraison') as a4 \gset
select public.avancer_livraison(:'c4', 'bou_informatique', 'remise') as b4 \gset
reset role; select essai.personne();
select essai.egal((select montant::bigint from public.gains_parrain where commande_id = :'c4'), 380::bigint,
  '2 % de 19 000 (les articles, remise déduite) : 380 — pas 2 % de 20 000');
