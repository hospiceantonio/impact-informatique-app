-- =========================================================
-- Masquer un produit (3.59.0)
--
-- Ce qu'on prouve :
--   1. l'administrateur de la boutique masque un produit ; la base garde
--      qui et quand ; il ne se commande plus ;
--   2. il le réaffiche : il se commande de nouveau ;
--   3. un modérateur de la boutique le masque aussi, même sans
--      l'habilitation aux produits ;
--   4. une autre boutique, un livreur, un client, un visiteur : non ;
--   5. personne ne déclare « masqué » en écrivant la colonne sans droit.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set MODO     '''afaf0000-0000-0000-0000-000000000001'''
\set VOISIN   '''afaf0000-0000-0000-0000-000000000002'''
\set LIV      '''afaf0000-0000-0000-0000-000000000003'''

select essai.titre('Le décor');
insert into auth.users (id, email) values (:MODO::uuid, 'modo.masque@essai.bj'),
  (:VOISIN::uuid, 'voisin.masque@essai.bj'), (:LIV::uuid, 'liv.masque@essai.bj')
on conflict do nothing;
update public.profils p set role = v.r, actif = true, boutique_id = v.b, nom = v.n, peut_modifier_produits = v.m
  from (values (:MODO::uuid, 'moderateur', 'bou_informatique', 'Modo', false),
               (:VOISIN::uuid, 'administrateur', 'bou_essai_voisine', 'Voisin', true),
               (:LIV::uuid, 'livreur', 'bou_informatique', 'Liv', false)) as v(i, r, b, n, m)
 where p.id = v.i;
update public.boutiques set actif = true, ouvertures = null where id = 'bou_informatique';
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_masque', 'bou_informatique', 'Clé USB', 4000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true, masque = false;

select essai.titre('1. L''administrateur le masque');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.egal(public.masquer_produit('prod_masque', true), true, 'masqué');
reset role; select essai.personne();
select essai.verifie((select masque and masque_par <> '' and masque_le is not null
                        from public.produits where id = 'prod_masque'), 'la base garde qui et quand');
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.refuse($$select public.creer_commande('{"nom":"Afi","tel":"97666011","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_masque","quantite":1}]'::jsonb, '', true, true)$$, 'il ne se commande plus');
reset role; select essai.personne();

select essai.titre('2. Il le réaffiche');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.egal(public.masquer_produit('prod_masque', false), false, 'réaffiché');
reset role; select essai.personne();
select essai.verifie((select not masque and masque_par = '' and masque_le is null
                        from public.produits where id = 'prod_masque'), 'plus de trace de masque');
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.verifie((public.creer_commande('{"nom":"Afi","tel":"97666011","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_masque","quantite":1}]'::jsonb, '', true, true) ->> 'id') is not null,
  'il se commande de nouveau');
reset role; select essai.personne();

select essai.titre('3. Le modérateur, même sans l''habilitation aux produits');
select essai.devenir(:MODO::uuid); set role authenticated;
select essai.egal(public.masquer_produit('prod_masque', true), true, 'il le masque');
select essai.egal(public.masquer_produit('prod_masque', false), false, 'et le réaffiche');
reset role; select essai.personne();

select essai.titre('4. Les autres : non');
select essai.devenir(:VOISIN::uuid); set role authenticated;
select essai.refuse($$select public.masquer_produit('prod_masque', true)$$, 'l''administrateur d''une autre boutique');
reset role; select essai.personne();
select essai.devenir(:LIV::uuid); set role authenticated;
select essai.refuse($$select public.masquer_produit('prod_masque', true)$$, 'un livreur');
reset role; select essai.personne();
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.refuse($$select public.masquer_produit('prod_masque', true)$$, 'un client');
reset role; select essai.personne();
set role anon;
select essai.refuse($$select public.masquer_produit('prod_masque', true)$$, 'un visiteur');
reset role;

select essai.titre('5. La colonne ne s''écrit pas sans droit');
select essai.devenir(:MODO::uuid); set role authenticated;
select essai.sans_effet($$update public.produits set masque = true where id = 'prod_masque'$$,
  'le modérateur sans habilitation n''écrit pas la table à la main');
reset role; select essai.personne();
select essai.egal((select masque from public.produits where id = 'prod_masque'), false, 'toujours visible');
