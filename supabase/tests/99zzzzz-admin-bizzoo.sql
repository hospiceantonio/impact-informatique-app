-- =========================================================
-- L'administrateur de BIZZOO gère livreurs et revendeurs (3.59.0)
--
-- Ce qu'on prouve :
--   1. il crée un livreur (fiche en attente → livreur actif), le voit,
--      voit sa position, le modifie, le retire ;
--   2. il ne nomme personne d'autre : ni administrateur, ni modérateur,
--      ni superadministrateur — et ne touche pas aux autres comptes ;
--   3. il crée la fiche d'un revendeur tout neuf (demande en attente) ;
--      pas sur un compte ancien, ni déjà client ;
--   4. il voit les demandes et valide celle qui a sa position ;
--   5. un modérateur de BIZZOO, un administrateur de boutique : non.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set CHEF      '''22222222-2222-2222-2222-222222222222'''
\set ADMBZ     '''cdcdcdcd-0000-0000-0000-000000000001'''
\set MODBZ     '''cdcdcdcd-0000-0000-0000-000000000002'''
\set NOUVLIV   '''cdcdcdcd-0000-0000-0000-000000000003'''
\set REVNEUF   '''cdcdcdcd-0000-0000-0000-000000000004'''
\set REVVIEUX  '''cdcdcdcd-0000-0000-0000-000000000005'''
\set CIBLE     '''cdcdcdcd-0000-0000-0000-000000000006'''

select essai.titre('Le décor : un administrateur et un modérateur de BIZZOO');
insert into auth.users (id, email) values
  (:ADMBZ::uuid, 'admin.bizzoo@essai.bj'), (:MODBZ::uuid, 'modo.bizzoo@essai.bj'),
  (:CIBLE::uuid, 'cible.equipe@essai.bj')
on conflict do nothing;
update public.profils set role = 'administrateur', boutique_id = null, actif = true where id = :ADMBZ::uuid;
update public.profils set role = 'moderateur', boutique_id = null, actif = true where id = :MODBZ::uuid;
update public.profils set role = 'moderateur', boutique_id = 'bou_informatique', actif = true
 where id = :CIBLE::uuid;

-- ---------------------------------------------------------
select essai.titre('1. Il crée un livreur, le voit, le modifie, le retire');
insert into auth.users (id, email) values (:NOUVLIV::uuid, 'nouveau.liv@essai.bj') on conflict do nothing;
select essai.devenir(:ADMBZ::uuid); set role authenticated;
select essai.egal(public.est_admin_bizzoo(), true, 'il est administrateur de BIZZOO');
insert into public.profils (id, email, role, actif, boutique_id, nom, tel)
values (:NOUVLIV::uuid, 'nouveau.liv@essai.bj', 'livreur', true, null, 'Sèna', '0196555001')
on conflict (id) do update set role = excluded.role, actif = excluded.actif,
  boutique_id = excluded.boutique_id, nom = excluded.nom, tel = excluded.tel;
select essai.egal((select role from public.profils where id = :NOUVLIV::uuid), 'livreur',
  'la fiche en attente devient celle d''un livreur');
select essai.egal((select count(*)::int from public.profils where role = 'livreur') > 0, true,
  'il voit les livreurs');
select essai.egal((select count(*)::int from public.profils where id = :NOUVLIV::uuid
                     and boutique_id is null), 1, 'un livreur de BIZZOO');
update public.profils set boutique_id = 'bou_informatique' where id = :NOUVLIV::uuid;
reset role; select essai.personne();
select essai.egal((select boutique_id from public.profils where id = :NOUVLIV::uuid), 'bou_informatique',
  'il le rattache à une boutique');

select essai.devenir(:NOUVLIV::uuid); set role authenticated;
select public.enregistrer_ma_position(6.37, 2.42, 'Cadjèhoun') as p \gset
reset role; select essai.personne();
select essai.devenir(:ADMBZ::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.positions_livreurs where profil_id = :NOUVLIV::uuid), 1,
  'il voit sa position');

-- ---------------------------------------------------------
select essai.titre('2. Il ne nomme personne d''autre');
select essai.refuse($$update public.profils set role = 'administrateur'
  where id = 'cdcdcdcd-0000-0000-0000-000000000003'::uuid$$,
  'faire d''un livreur un administrateur : refusé');
select essai.sans_effet($$update public.profils set role = 'livreur'
  where id = 'cdcdcdcd-0000-0000-0000-000000000006'::uuid$$,
  'toucher au modérateur d''une boutique : sans effet');
select essai.sans_effet($$update public.profils set role = 'superadministrateur'
  where id = 'cdcdcdcd-0000-0000-0000-000000000001'::uuid$$,
  'se promouvoir lui-même : sans effet');
select essai.refuse($$insert into public.profils (id, email, role, boutique_id, actif)
  values ('cdcdcdcd-0000-0000-0000-000000000099'::uuid, 'x@bizzoo.bj', 'moderateur', null, true)$$,
  'créer un modérateur : refusé');
delete from public.profils where id = :NOUVLIV::uuid;
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.profils where id = :NOUVLIV::uuid), 0,
  'il retire un livreur');
select essai.egal((select role from public.profils where id = :CIBLE::uuid), 'moderateur',
  'le modérateur de la boutique est resté modérateur');

-- ---------------------------------------------------------
select essai.titre('3. Il crée la fiche d''un revendeur tout neuf');
insert into auth.users (id, email, phone, raw_user_meta_data) values
  (:REVNEUF::uuid, '', '2290161444001', '{"compte":"client","nom":"Boutique Sika"}')
on conflict do nothing;
insert into auth.users (id, email, created_at) values
  (:REVVIEUX::uuid, 'vieux.compte@essai.bj', now() - interval '3 days')
on conflict do nothing;
select essai.devenir(:ADMBZ::uuid); set role authenticated;
select essai.egal(public.creer_fiche_revendeur(:REVNEUF::uuid, 'Boutique Sika', '0161444001',
  'Accessoires téléphone', 'Dantokpa'), 'en_attente', 'la fiche naît : une demande en attente');
select essai.refuse(format($$select public.creer_fiche_revendeur(%L::uuid, 'X', '0161444002')$$, :REVNEUF),
  'une seconde fois sur le même compte : refusé');
select essai.refuse(format($$select public.creer_fiche_revendeur(%L::uuid, 'X', '0161444003')$$, :REVVIEUX),
  'sur un compte ancien : refusé');
select essai.refuse(format($$select public.creer_fiche_revendeur(%L::uuid, 'X', '0161444004')$$, :CIBLE),
  'sur un compte de l''équipe : refusé');
reset role; select essai.personne();
select essai.egal((select type_compte || '/' || revendeur_etat || '/' || revendeur_adresse
                     from public.clients where id = :REVNEUF::uuid),
  'revendeur/en_attente/Dantokpa', 'revendeur en attente, avec son adresse');

-- ---------------------------------------------------------
select essai.titre('4. Il voit les demandes et valide');
select essai.devenir(:ADMBZ::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.revendeurs('en_attente') where id = :REVNEUF::uuid), 1,
  'la demande est dans sa liste');
select essai.refuse(format($$select public.valider_revendeur(%L::uuid, true, '')$$, :REVNEUF),
  'sans la position du téléphone : pas encore validable');
reset role; select essai.personne();
select essai.devenir(:REVNEUF::uuid); set role authenticated;
update public.clients set revendeur_latitude = 6.356, revendeur_longitude = 2.433 where id = :REVNEUF::uuid;
reset role; select essai.personne();
select essai.devenir(:ADMBZ::uuid); set role authenticated;
select essai.egal(public.valider_revendeur(:REVNEUF::uuid, true, ''), 'validee',
  'position activée par le revendeur : il le valide');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('5. Un modérateur de BIZZOO, un administrateur de boutique : non');
insert into auth.users (id, email) values (:NOUVLIV::uuid, 'nouveau.liv@essai.bj') on conflict do nothing;
insert into public.profils (id, email, role, actif) values (:NOUVLIV::uuid, 'nouveau.liv@essai.bj', 'moderateur', false)
on conflict (id) do nothing;
select essai.devenir(:MODBZ::uuid); set role authenticated;
select essai.egal(public.est_admin_bizzoo(), false, 'le modérateur de BIZZOO n''est pas administrateur de BIZZOO');
select essai.refuse($$insert into public.profils (id, email, role, boutique_id, actif)
  values ('cdcdcdcd-0000-0000-0000-000000000098'::uuid, 'y@bizzoo.bj', 'livreur', null, true)$$,
  'il ne crée pas de livreur');
select essai.egal((select count(*)::int from public.revendeurs('toutes')), 0, 'il ne voit pas les demandes');
reset role; select essai.personne();
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse(format($$select public.valider_revendeur(%L::uuid, false, '')$$, :REVNEUF),
  'l''administrateur d''une boutique ne valide pas les revendeurs');
select essai.refuse(format($$select public.creer_fiche_revendeur(%L::uuid, 'X', '0161444009')$$, :NOUVLIV),
  'ni ne crée de revendeur');
reset role; select essai.personne();
