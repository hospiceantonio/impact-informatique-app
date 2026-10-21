-- =========================================================
-- Créer un produit demande l'habilitation (3.59.0)
--
-- Ce qu'on prouve, pour chaque rang qui n'est pas superadministrateur :
-- sans l'habilitation « produits », on ne CRÉE pas de produit (ni son
-- prix d'achat) ; avec, on crée — dans sa boutique seulement.
--   1. le modérateur d'une boutique ;
--   2. l'administrateur d'une boutique — qui ne l'a plus d'office ;
--   3. l'administrateur de BIZZOO réduit aux commandes ;
--   4. le superadministrateur, lui, crée toujours.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set MODO     '''efefefef-0000-0000-0000-000000000001'''
\set ADMIN    '''efefefef-0000-0000-0000-000000000002'''
\set BZ       '''efefefef-0000-0000-0000-000000000003'''

select essai.titre('Le décor');
insert into auth.users (id, email) values
  (:MODO::uuid, 'modo.produits@essai.bj'), (:ADMIN::uuid, 'admin.produits@essai.bj'),
  (:BZ::uuid, 'bizzoo.commandes@essai.bj')
on conflict do nothing;
update public.profils set role = 'moderateur', boutique_id = 'bou_informatique', actif = true,
       peut_modifier_produits = false where id = :MODO::uuid;
update public.profils set role = 'administrateur', boutique_id = 'bou_informatique', actif = true,
       peut_modifier_produits = false where id = :ADMIN::uuid;
update public.profils set role = 'administrateur', boutique_id = null, actif = true,
       peut_modifier_produits = false, peut_commandes = true where id = :BZ::uuid;

-- Un produit neuf, au nom de qui on est.
create or replace function essai.nouveau_produit(id text) returns void
language sql as $$
  insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
  values (id, 'bou_informatique', 'Essai ' || id, 1000, 'sc_hightech_accessoires', 1, true);
$$;
grant execute on all functions in schema essai to anon, authenticated, service_role;

select essai.titre('1. Le modérateur sans habilitation ne crée rien');
select essai.devenir(:MODO::uuid); set role authenticated;
select essai.refuse($$select essai.nouveau_produit('hab_modo')$$, 'créer un produit : refusé');
reset role; select essai.personne();
update public.profils set peut_modifier_produits = true where id = :MODO::uuid;
select essai.devenir(:MODO::uuid); set role authenticated;
select essai.nouveau_produit('hab_modo');
select essai.egal((select count(*)::int from public.produits where id = 'hab_modo'), 1,
  'habilité : il crée dans sa boutique');
select essai.refuse($$insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id)
  values ('hab_ailleurs', 'bou_essai_voisine', 'Ailleurs', 1000, 'sc_hightech_accessoires')$$,
  'mais pas dans une autre boutique');
reset role; select essai.personne();

select essai.titre('2. L''administrateur de boutique ne l''a plus d''office');
select essai.devenir(:ADMIN::uuid); set role authenticated;
select essai.egal(public.peut_modifier_produits(), false, 'sans habilitation : non');
select essai.refuse($$select essai.nouveau_produit('hab_admin')$$, 'créer un produit : refusé');
select essai.refuse($$insert into public.produits_prive (produit_id, prix_grossiste)
  values ('hab_modo', 500)$$, 'poser un prix d''achat : refusé');
select essai.sans_effet($$update public.produits set prix = 1 where id = 'hab_modo'$$,
  'retoucher un produit : sans effet');
reset role; select essai.personne();
update public.profils set peut_modifier_produits = true where id = :ADMIN::uuid;
select essai.devenir(:ADMIN::uuid); set role authenticated;
select essai.nouveau_produit('hab_admin');
select essai.egal((select count(*)::int from public.produits where id = 'hab_admin'), 1,
  'habilité : il crée');
reset role; select essai.personne();

select essai.titre('3. L''administrateur de BIZZOO réduit aux commandes');
select essai.devenir(:BZ::uuid); set role authenticated;
select essai.egal(public.peut_voir_commandes(), true, 'il voit les commandes');
select essai.refuse($$select essai.nouveau_produit('hab_bz')$$,
  'il n''intègre pas de produit dans une boutique');
reset role; select essai.personne();

select essai.titre('4. Le superadministrateur crée toujours');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.nouveau_produit('hab_super');
select essai.egal((select count(*)::int from public.produits where id = 'hab_super'), 1,
  'le superadministrateur crée');
reset role; select essai.personne();

delete from public.produits where id in ('hab_modo', 'hab_admin', 'hab_super');
update public.profils set peut_modifier_produits = true where id in (:MODO::uuid, :ADMIN::uuid);
