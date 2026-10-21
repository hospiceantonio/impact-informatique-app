-- =========================================================
-- L'administrateur de BIZZOO gère ses livreurs, jusqu'au bout (3.63.0)
--
-- Il les modifiait déjà ; « Redonner un mot de passe » et « Supprimer »
-- lui répondaient « Ce compte n'est pas sous votre responsabilité ».
--
-- Ce qu'on prouve :
--   1. il modifie un livreur de boutique et un livreur de BIZZOO ;
--   2. les deux sont sous sa responsabilité (mot de passe, suppression) ;
--   3. un modérateur, un administrateur, lui-même : non ;
--   4. un administrateur de boutique, lui, ne gère toujours pas le livreur
--      d'une autre boutique.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ADMBZ    '''adad0000-0000-0000-0000-000000000001'''
\set LIVBOU   '''adad0000-0000-0000-0000-000000000002'''
\set LIVBZ    '''adad0000-0000-0000-0000-000000000003'''
\set MODOBZ   '''adad0000-0000-0000-0000-000000000004'''
\set LIVVOIS  '''adad0000-0000-0000-0000-000000000005'''

select essai.titre('Le décor : un administrateur de BIZZOO, des livreurs, un modérateur');
insert into auth.users (id, email) values
  (:ADMBZ::uuid, 'admin.bizzoo.liv@essai.bj'), (:LIVBOU::uuid, 'liv.bou.bz@essai.bj'),
  (:LIVBZ::uuid, 'liv.bizzoo.bz@essai.bj'), (:MODOBZ::uuid, 'modo.bou.bz@essai.bj'),
  (:LIVVOIS::uuid, 'liv.voisin.bz@essai.bj')
on conflict do nothing;
update public.profils set role = 'administrateur', boutique_id = null, actif = true, nom = 'Admin BZ'
 where id = :ADMBZ::uuid;
update public.profils set role = 'livreur', boutique_id = 'bou_informatique', actif = true, nom = 'Koffi'
 where id = :LIVBOU::uuid;
update public.profils set role = 'livreur', boutique_id = null, actif = true, nom = 'Sêna'
 where id = :LIVBZ::uuid;
update public.profils set role = 'moderateur', boutique_id = 'bou_informatique', actif = true
 where id = :MODOBZ::uuid;
update public.profils set role = 'livreur', boutique_id = 'bou_essai_voisine', actif = true
 where id = :LIVVOIS::uuid;

select essai.titre('1. Il modifie ses livreurs');
select essai.devenir(:ADMBZ::uuid); set role authenticated;
select essai.verifie(public.est_admin_bizzoo(), 'c''est bien un administrateur de BIZZOO');
update public.profils set nom = 'Koffi A.', actif = false where id = :LIVBOU::uuid;
update public.profils set nom = 'Sêna B.' where id = :LIVBZ::uuid;
reset role; select essai.personne();
select essai.egal((select nom || '/' || actif from public.profils where id = :LIVBOU::uuid), 'Koffi A./false',
  'le livreur d''une boutique : renommé, désactivé');
select essai.egal((select nom from public.profils where id = :LIVBZ::uuid), 'Sêna B.',
  'le livreur de BIZZOO : renommé');

select essai.titre('2. Mot de passe et suppression : ils sont sous sa responsabilité');
select essai.devenir(:ADMBZ::uuid); set role authenticated;
select essai.verifie(public.gere_le_compte(:LIVBOU::uuid), 'le livreur d''une boutique');
select essai.verifie(public.gere_le_compte(:LIVBZ::uuid), 'le livreur de BIZZOO');

select essai.titre('3. Un livreur, et rien d''autre');
select essai.verifie(not public.gere_le_compte(:MODOBZ::uuid), 'pas un modérateur');
select essai.verifie(not public.gere_le_compte(:CHEF::uuid), 'pas un administrateur');
select essai.verifie(not public.gere_le_compte(:ADMBZ::uuid), 'pas lui-même');
reset role; select essai.personne();

select essai.titre('4. L''administrateur d''une boutique reste chez lui');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.verifie(not public.gere_le_compte(:LIVVOIS::uuid), 'pas le livreur de la boutique voisine');
select essai.verifie(not public.gere_le_compte(:LIVBZ::uuid), 'ni celui de BIZZOO');
reset role; select essai.personne();
