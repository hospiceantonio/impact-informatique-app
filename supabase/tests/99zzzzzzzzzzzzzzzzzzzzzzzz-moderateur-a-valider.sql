-- =========================================================
-- L'administrateur de BIZZOO crée un modérateur ; le superadministrateur
-- le valide (3.63.0, demande du CEO)
--
-- Ce qu'on prouve :
--   1. l'administrateur de BIZZOO crée un modérateur : la fiche naît
--      INACTIVE et « à valider », même s'il demande « actif » ; il en est
--      le créateur ; les superadministrateurs sont prévenus ;
--   2. il le voit, le retouche, l'a sous sa responsabilité — mais ne
--      l'active pas ; l'administrateur de la boutique non plus ;
--   3. le superadministrateur l'active : c'est la validation ; son
--      créateur est prévenu ;
--   4. validé, il n'est plus à son créateur ;
--   5. l'administrateur de BIZZOO ne crée toujours pas d'administrateur.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ADMBZ    '''a7a7a7a7-0000-0000-0000-000000000001'''
\set MODO1    '''a7a7a7a7-0000-0000-0000-000000000002'''
\set MODO2    '''a7a7a7a7-0000-0000-0000-000000000003'''

select essai.titre('Le décor : un administrateur de BIZZOO');
insert into auth.users (id, email) values (:ADMBZ::uuid, 'admin.bz.valide@essai.bj')
on conflict do nothing;
update public.profils set role = 'administrateur', boutique_id = null, actif = true, nom = 'Admin BZ'
 where id = :ADMBZ::uuid;
select essai.verifie((select role = 'superadministrateur' and actif from public.profils where id = :ENSEIGNE::uuid),
  'le compte d''enseigne est superadministrateur');

select essai.titre('1. Il crée un modérateur : à valider');
-- L'inscription pose la fiche en attente ; l'écran lui donne ensuite son
-- rang, comme le fait PostgREST (« on conflict »). Il demande « actif ».
insert into auth.users (id, email) values (:MODO1::uuid, 'modo.a.valider@essai.bj') on conflict do nothing;
select essai.devenir(:ADMBZ::uuid); set role authenticated;
insert into public.profils (id, email, role, actif, boutique_id, nom)
values (:MODO1::uuid, 'modo.a.valider@essai.bj', 'moderateur', true, 'bou_informatique', 'Fifamè')
on conflict (id) do update set role = excluded.role, actif = excluded.actif,
  boutique_id = excluded.boutique_id, nom = excluded.nom;
reset role; select essai.personne();
select essai.egal((select role || '/' || actif || '/' || a_valider || '/' || boutique_id
                     from public.profils where id = :MODO1::uuid),
  'moderateur/false/true/bou_informatique', 'modérateur de la boutique, INACTIF et à valider');
select essai.verifie((select cree_par = :ADMBZ::uuid from public.profils where id = :MODO1::uuid),
  'il en est le créateur');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ENSEIGNE::uuid and type = 'compte_a_valider'), 1,
  'le superadministrateur est prévenu, une fois');

select essai.titre('2. Il le retouche, sans l''activer');
select essai.devenir(:ADMBZ::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.profils where id = :MODO1::uuid), 1, 'il le voit');
select essai.verifie(public.gere_le_compte(:MODO1::uuid), 'il l''a sous sa responsabilité (mot de passe, retrait)');
update public.profils set nom = 'Fifamè D.' where id = :MODO1::uuid;
update public.profils set actif = true where id = :MODO1::uuid;
reset role; select essai.personne();
select essai.egal((select nom || '/' || actif || '/' || a_valider from public.profils where id = :MODO1::uuid),
  'Fifamè D./false/true', 'renommé ; l''activer ne prend pas');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ENSEIGNE::uuid and type = 'compte_a_valider'), 1,
  'et le superadministrateur n''est pas prévenu deux fois');
-- L'administrateur de la boutique ne l'active pas par la porte d'à côté.
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.profils set actif = true where id = :MODO1::uuid;
update public.profils set a_valider = false where id = :MODO1::uuid;
reset role; select essai.personne();
select essai.egal((select actif || '/' || a_valider from public.profils where id = :MODO1::uuid),
  'false/true', 'l''administrateur de la boutique ne le valide pas');

select essai.titre('3. Le superadministrateur le valide');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.profils set actif = true where id = :MODO1::uuid;
reset role; select essai.personne();
select essai.egal((select actif || '/' || a_valider from public.profils where id = :MODO1::uuid),
  'true/false', 'activé, il est validé');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ADMBZ::uuid and type = 'compte_valide'), 1,
  'son créateur est prévenu');

select essai.titre('4. Validé, il n''est plus à son créateur');
select essai.devenir(:ADMBZ::uuid); set role authenticated;
select essai.verifie(not public.gere_le_compte(:MODO1::uuid), 'plus sous sa responsabilité');
select essai.sans_effet(format($$update public.profils set nom = 'X' where id = %L::uuid$$, :MODO1),
  'il ne le retouche plus');
select essai.sans_effet(format($$delete from public.profils where id = %L::uuid$$, :MODO1),
  'il ne le retire plus');
reset role; select essai.personne();

select essai.titre('5. Toujours pas d''administrateur');
insert into auth.users (id, email) values (:MODO2::uuid, 'pas.admin@essai.bj') on conflict do nothing;
select essai.devenir(:ADMBZ::uuid); set role authenticated;
select essai.refuse(format($$update public.profils set role = 'administrateur', boutique_id = 'bou_informatique'
    where id = %L::uuid$$, :MODO2), 'en faire un administrateur : refusé');
select essai.refuse(format($$update public.profils set role = 'superadministrateur' where id = %L::uuid$$, :MODO2),
  'en faire un superadministrateur : refusé');
reset role; select essai.personne();
select essai.egal((select role || '/' || actif from public.profils where id = :MODO2::uuid), 'moderateur/false',
  'la fiche reste en attente, sans rang');
