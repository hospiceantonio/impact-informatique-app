-- =========================================================
-- Un revendeur n'a pas de code promo
--
-- Il achète déjà au prix BIZZOO. Un code s'ajouterait à cette
-- remise et sortirait une seconde fois de la même marge. La
-- base le refuse — à l'aperçu comme à la caisse —, et la
-- commande passe sans le code, au prix revendeur.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set REVENDEUR '''eeeeeeee-1111-1111-1111-111111111111'''
\set CLIENTE   '''eeeeeeee-2222-2222-2222-222222222222'''
\set ENSEIGNE  '''11111111-1111-1111-1111-111111111111'''

select essai.titre('Le décor : un code, un revendeur, une cliente');

insert into auth.users (id, email) values
  (:REVENDEUR::uuid, 'revendeur.code@essai.bj'),
  (:CLIENTE::uuid, 'cliente.code@essai.bj')
on conflict do nothing;
insert into public.clients (id, nom, tel, type_compte, revendeur_etat,
                            revendeur_decide_par, revendeur_motif)
values (:REVENDEUR::uuid, 'Grossiste', '97555001', 'revendeur', 'validee', 'essai', 'accordé'),
       (:CLIENTE::uuid, 'Adjoa', '97555002', 'client', 'aucune', '', '')
on conflict (id) do nothing;
-- LE STATUT SE DÉCIDE À L'ENSEIGNE : la base ignore celui qu'on écrit.
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select public.valider_revendeur(:REVENDEUR::uuid, true, '') as v \gset
reset role; select essai.personne();

insert into public.produits
  (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_sans_code', 'bou_informatique', 'Écran', 20000,
        'sc_hightech_accessoires', 50, true)
on conflict (id) do update set prix = 20000, stock = 50, disponible = true;
insert into public.produits_prive (produit_id, prix_grossiste)
values ('prod_sans_code', 12000)
on conflict (produit_id) do update set prix_grossiste = 12000;

insert into public.codes_promo (code, mode, valeur, une_par_client, actif)
values ('REVENDU10', 'pourcent', 10, false, true)
on conflict (code) do update set mode = 'pourcent', valeur = 10, actif = true,
                                 une_par_client = false, maximum = 0, minimum = 0, fin = null;

-- ---------------------------------------------------------
select essai.titre('1. La cliente : le code vaut');

select essai.devenir(:CLIENTE::uuid); set role authenticated;
select essai.verifie(
  (public.verifier_code('REVENDU10', '[{"produit_id":"prod_sans_code","quantite":1}]'::jsonb)
     ->> 'ok')::boolean,
  'à l''aperçu, le code s''applique');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('2. Le revendeur : refusé, et dit pourquoi');

select essai.egal((select revendeur_etat from public.clients where id = :REVENDEUR::uuid),
  'validee', 'le revendeur est validé');
select essai.devenir(:REVENDEUR::uuid); set role authenticated;
select essai.verifie(public.est_revendeur(), 'et la base le reconnaît comme revendeur');
select public.verifier_code('REVENDU10',
  '[{"produit_id":"prod_sans_code","quantite":1}]'::jsonb) as verdict \gset
select essai.verifie(not (:'verdict'::jsonb ->> 'ok')::boolean, 'à l''aperçu, le code est refusé');
select essai.verifie((:'verdict'::jsonb ->> 'raison') ~ 'revendeur',
  'et la raison parle de son compte revendeur');

select public.creer_commande('{"nom":"Grossiste","tel":"97555001","adresse":"Dantokpa"}'::jsonb,
  '[{"produit_id":"prod_sans_code","quantite":1}]'::jsonb, 'REVENDU10') as cmd \gset
reset role; select essai.personne();

select essai.egal(
  (select remise from public.commandes where id = :'cmd'::jsonb ->> 'id'), 0::bigint,
  'à la caisse : aucune remise');
select essai.egal(
  (select code_promo from public.commandes where id = :'cmd'::jsonb ->> 'id'), '',
  'et le code n''est pas inscrit sur la commande');
select essai.verifie(
  (select revendeur from public.commandes where id = :'cmd'::jsonb ->> 'id'),
  'la commande passe quand même, au prix revendeur');
