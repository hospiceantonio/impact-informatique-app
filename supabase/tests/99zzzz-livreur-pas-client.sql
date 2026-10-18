-- =========================================================
-- Un livreur n'est ni acheteur ni revendeur (3.59.0)
--
-- Ce qu'on prouve :
--   1. le numéro d'un livreur n'ouvre pas de compte client — ni par
--      l'inscription (« compte: client »), ni par un code SMS ; les
--      huit derniers chiffres suffisent (« 01 » devant ou non) ;
--   2. un compte client ouvert AVANT avec ce numéro ne dépose pas de
--      demande de revendeur ; l'application le sait (« double ») ;
--   3. une demande déposée avant que le numéro soit celui d'un livreur
--      ne se valide pas ;
--   4. un client ordinaire, lui, demande et se fait valider comme avant.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set LIVREUR  '''bcbcbcbc-1111-1111-1111-111111111111'''
\set DOUBLE   '''bcbcbcbc-2222-2222-2222-222222222222'''
\set NEUF     '''bcbcbcbc-3333-3333-3333-333333333333'''
\set ANCIEN   '''bcbcbcbc-4444-4444-4444-444444444444'''
\set AFI      '''bcbcbcbc-5555-5555-5555-555555555555'''

select essai.titre('Le décor : un livreur, son numéro');
insert into auth.users (id, email) values
  (:LIVREUR::uuid, 'livreur.numero@essai.bj'),
  (:DOUBLE::uuid, 'double.client@essai.bj'),
  (:ANCIEN::uuid, 'ancien.revendeur@essai.bj'),
  (:AFI::uuid, 'afi.revendeuse@essai.bj')
on conflict do nothing;
-- Le compte client « double », ouvert avant que le numéro soit celui
-- d'un livreur ; et une demande de revendeur déjà déposée.
insert into public.clients (id, nom, tel, type_compte) values
  (:DOUBLE::uuid, 'Kossi (client)', '96777001', 'client'),
  (:ANCIEN::uuid, 'Kossi (revendeur)', '0196777001', 'revendeur'),
  (:AFI::uuid, 'Afi', '0161888002', 'revendeur')
on conflict (id) do nothing;
update public.clients set revendeur_latitude = 6.35, revendeur_longitude = 2.43,
       revendeur_adresse = 'Dantokpa' where id in (:ANCIEN::uuid, :AFI::uuid);
update public.profils set role = 'livreur', actif = true, boutique_id = 'bou_informatique',
       tel = '01 96 77 70 01' where id = :LIVREUR::uuid;
insert into public.profils (id, email, role, actif, boutique_id, tel)
select :LIVREUR::uuid, 'livreur.numero@essai.bj', 'livreur', true, 'bou_informatique', '01 96 77 70 01'
 where not exists (select 1 from public.profils where id = :LIVREUR::uuid);

select essai.titre('1. Le numéro d''un livreur n''ouvre pas de compte client');
select essai.refuse(format($$insert into auth.users (id, email, phone, raw_user_meta_data)
  values (%L::uuid, '', '2290196777001', '{"compte":"client","nom":"Kossi"}')$$, :NEUF),
  'inscription « compte: client » avec son numéro : refusée');
select essai.refuse(format($$insert into auth.users (id, email, phone)
  values (%L::uuid, '', '22996777001')$$, :NEUF),
  'premier code SMS avec son ancien numéro à 8 chiffres : refusé');
select essai.egal((select count(*)::int from auth.users where id = :NEUF::uuid), 0,
  'aucun compte n''est né');
insert into auth.users (id, email, phone, raw_user_meta_data)
  values (:NEUF::uuid, '', '2290161999003', '{"compte":"client"}') on conflict do nothing;
select essai.egal((select count(*)::int from auth.users where id = :NEUF::uuid), 1,
  'un autre numéro ouvre son compte, comme avant');

select essai.titre('2. Le compte client « double » ne devient pas revendeur');
select essai.devenir(:DOUBLE::uuid); set role authenticated;
select essai.refuse(format($$update public.clients set type_compte = 'revendeur' where id = %L::uuid$$, :DOUBLE),
  'demander à devenir revendeur : refusé');
select essai.egal((public.mon_compte_livreur() ->> 'double')::boolean, true,
  'l''application sait que c''est le numéro d''un livreur');
reset role; select essai.personne();
select essai.egal((select revendeur_etat from public.clients where id = :DOUBLE::uuid), 'aucune',
  'sa fiche reste celle d''un client ordinaire');

select essai.devenir(:LIVREUR::uuid); set role authenticated;
select essai.egal((public.mon_compte_livreur() ->> 'livreur')::boolean, true,
  'le compte du livreur se sait livreur');
select essai.egal((public.mon_compte_livreur() ->> 'double')::boolean, false,
  'et n''est pas un « double »');
reset role; select essai.personne();
select essai.devenir(:AFI::uuid); set role authenticated;
select essai.egal(public.mon_compte_livreur()::text, '{"double": false, "livreur": false}',
  'un client ordinaire : ni l''un ni l''autre');
reset role; select essai.personne();
set role anon;
select essai.refuse($$select public.numero_de_livreur('0196777001')$$,
  'personne ne demande à la base si un numéro est celui d''un livreur');
reset role;

select essai.titre('3. Une demande d''avant ne se valide pas');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse(format($$select public.valider_revendeur(%L::uuid, true, '')$$, :ANCIEN),
  'valider la demande d''un numéro de livreur : refusé');
select essai.egal(public.valider_revendeur(:ANCIEN::uuid, false, 'livreur'), 'refusee',
  'la refuser reste possible');

select essai.titre('4. Un client ordinaire, comme avant');
select essai.egal(public.valider_revendeur(:AFI::uuid, true, ''), 'validee',
  'la demande d''Afi est validée');
reset role; select essai.personne();
