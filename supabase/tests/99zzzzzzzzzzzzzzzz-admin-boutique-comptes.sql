-- =========================================================
-- L'administrateur d'une boutique crée livreurs et revendeurs,
-- jamais un administrateur (3.59.0)
--
-- Ce qu'on prouve :
--   1. il crée un livreur de SA boutique, le modifie, change son mot de
--      passe, le retire ; il garde ses modérateurs ;
--   2. il ne nomme pas d'administrateur ni de superadministrateur, ne
--      crée pas de livreur pour une autre boutique ni de livreur BIZZOO ;
--   3. il crée la fiche d'un revendeur tout neuf : la demande reste EN
--      ATTENTE, il ne la valide pas — BIZZOO seul ;
--   4. un modérateur de boutique ne crée rien de tout cela.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set CHEF   '''22222222-2222-2222-2222-222222222222'''
\set LIV    '''abab0000-0000-0000-0000-000000000001'''
\set AUTRE  '''abab0000-0000-0000-0000-000000000002'''
\set REV    '''abab0000-0000-0000-0000-000000000003'''
\set MODO   '''abab0000-0000-0000-0000-000000000004'''
\set REV2   '''abab0000-0000-0000-0000-000000000005'''

select essai.titre('1. Il crée un livreur de sa boutique');
-- Le compte vient de naître : sa fiche est en attente (modérateur inactif, sans boutique).
insert into auth.users (id, email) values (:LIV::uuid, 'liv.chef@essai.bj'), (:AUTRE::uuid, 'autre.chef@essai.bj'),
  (:MODO::uuid, 'modo.chef@essai.bj')
on conflict do nothing;
update public.profils set role = 'moderateur', boutique_id = 'bou_informatique', actif = true where id = :MODO::uuid;
select essai.egal((select role || '/' || actif from public.profils where id = :LIV::uuid), 'moderateur/false',
  'la fiche toute neuve est en attente');
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.profils set role = 'livreur', boutique_id = 'bou_informatique', actif = true,
       nom = 'Yao', tel = '0196700001' where id = :LIV::uuid;
reset role; select essai.personne();
select essai.egal((select role || '/' || boutique_id || '/' || actif from public.profils where id = :LIV::uuid),
  'livreur/bou_informatique/true', 'elle devient celle d''un livreur de sa boutique');
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.profils set nom = 'Yao K.' where id = :LIV::uuid;
-- Changer son mot de passe, le supprimer : il en a la charge.
select essai.verifie(public.gere_le_compte(:LIV::uuid), 'son livreur est sous sa responsabilité (mot de passe, suppression)');
select essai.verifie(not public.gere_le_compte(:CHEF::uuid), 'pas lui-même ni un administrateur');
reset role; select essai.personne();
select essai.egal((select nom from public.profils where id = :LIV::uuid), 'Yao K.', 'il le modifie');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse(format($$update public.profils set role = 'administrateur' where id = %L::uuid$$, :LIV),
  'faire de son livreur un administrateur : refusé');
select essai.refuse(format($$update public.profils set boutique_id = null where id = %L::uuid$$, :LIV),
  'en faire un livreur de BIZZOO : refusé');
select essai.refuse(format($$update public.profils set boutique_id = 'bou_essai_voisine' where id = %L::uuid$$, :LIV),
  'le donner à une autre boutique : refusé');
reset role; select essai.personne();

select essai.titre('2. Jamais un administrateur');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse(format($$update public.profils set role = 'administrateur', boutique_id = 'bou_informatique',
  actif = true where id = %L::uuid$$, :AUTRE), 'la fiche en attente : pas un administrateur');
select essai.refuse(format($$update public.profils set role = 'superadministrateur', actif = true
  where id = %L::uuid$$, :AUTRE), 'ni un superadministrateur');
select essai.refuse($$insert into public.profils (id, email, role, boutique_id, actif)
  values ('abab0000-0000-0000-0000-000000000099'::uuid, 'z@essai.bj', 'administrateur', 'bou_informatique', true)$$,
  'créer un administrateur : refusé');
select essai.refuse($$insert into public.profils (id, email, role, boutique_id, actif)
  values ('abab0000-0000-0000-0000-000000000098'::uuid, 'y@essai.bj', 'livreur', 'bou_essai_voisine', true)$$,
  'créer un livreur pour une autre boutique : refusé');
update public.profils set role = 'moderateur', boutique_id = 'bou_informatique', actif = true where id = :AUTRE::uuid;
reset role; select essai.personne();
select essai.egal((select role from public.profils where id = :AUTRE::uuid), 'moderateur',
  'il crée toujours ses modérateurs');

select essai.titre('3. Il crée un revendeur ; BIZZOO le valide');
insert into auth.users (id, email, phone, raw_user_meta_data) values
  (:REV::uuid, '', '2290161555001', '{"compte":"client","nom":"Sika"}')
on conflict do nothing;
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.egal(public.creer_fiche_revendeur(:REV::uuid, 'Sika', '0161555001', 'Pagnes', 'Dantokpa'),
  'en_attente', 'la fiche du revendeur naît, en attente');
select essai.refuse(format($$select public.valider_revendeur(%L::uuid, true, '')$$, :REV),
  'il ne la valide pas lui-même');
reset role; select essai.personne();
select essai.egal((select type_compte || '/' || revendeur_etat from public.clients where id = :REV::uuid),
  'revendeur/en_attente', 'revendeur en attente de BIZZOO');

select essai.titre('4. Un modérateur de boutique : rien de cela');
insert into auth.users (id, email, phone, raw_user_meta_data) values
  (:REV2::uuid, '', '2290161555002', '{"compte":"client","nom":"Kpè"}')
on conflict do nothing;
select essai.devenir(:MODO::uuid); set role authenticated;
select essai.refuse(format($$select public.creer_fiche_revendeur(%L::uuid, 'Kpè', '0161555002')$$, :REV2),
  'pas de revendeur');
select essai.refuse($$insert into public.profils (id, email, role, boutique_id, actif)
  values ('abab0000-0000-0000-0000-000000000097'::uuid, 'w@essai.bj', 'livreur', 'bou_informatique', true)$$,
  'pas de livreur');
reset role; select essai.personne();

select essai.devenir(:CHEF::uuid); set role authenticated;
delete from public.profils where id = :LIV::uuid;
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.profils where id = :LIV::uuid), 0, 'il retire son livreur');
