-- =========================================================
-- Tous les superadministrateurs sont égaux (3.81.0 ; avant : « on ne
-- touche pas à son créateur », 3.59.0)
--
-- Ce qu'on prouve :
--   1. le superadministrateur A crée B, qui crée C ; la base retient qui
--      a créé qui ;
--   2. B, nommé par A, a tous les droits d'un superadministrateur, sur A
--      aussi : il le gère, le renomme, le désactive et le réactive ;
--   3. C de même, en remontant la chaîne ;
--   4. dans l'autre sens, rien ne change : A gère B, B gère C ;
--   5. le DERNIER superadministrateur actif ne se retire pas : ni
--      rétrogradé, ni désactivé, ni supprimé ;
--   6. un administrateur de boutique ne touche toujours pas à un
--      superadministrateur.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set A '''11111111-1111-1111-1111-111111111111'''
\set B '''acac0000-0000-0000-0000-000000000001'''
\set C '''acac0000-0000-0000-0000-000000000002'''

select essai.titre('1. A crée B, B crée C');
insert into auth.users (id, email) values (:B::uuid, 'b.createur@essai.bj') on conflict do nothing;
select essai.devenir(:A::uuid); set role authenticated;
update public.profils set role = 'superadministrateur', actif = true, boutique_id = null, nom = 'B'
 where id = :B::uuid;
reset role; select essai.personne();
insert into auth.users (id, email) values (:C::uuid, 'c.createur@essai.bj') on conflict do nothing;
select essai.devenir(:B::uuid); set role authenticated;
update public.profils set role = 'superadministrateur', actif = true, boutique_id = null, nom = 'C'
 where id = :C::uuid;
reset role; select essai.personne();
select essai.egal((select cree_par from public.profils where id = :B::uuid), :A::uuid, 'B a été créé par A');
select essai.egal((select cree_par from public.profils where id = :C::uuid), :B::uuid, 'C a été créé par B');

select nom as nom_a from public.profils where id = :A::uuid \gset
select essai.titre('2. B, nommé par A, a tous les droits sur A');
select essai.devenir(:B::uuid); set role authenticated;
select essai.verifie(not public.est_mon_createur(:A::uuid), 'A n''est plus un créateur protégé');
select essai.verifie(public.gere_le_compte(:A::uuid), 'A est sous sa responsabilité (mot de passe, retrait)');
update public.profils set nom = 'A (vu par B)' where id = :A::uuid;
update public.profils set actif = false where id = :A::uuid;
reset role; select essai.personne();
select essai.egal((select nom || '/' || actif from public.profils where id = :A::uuid), 'A (vu par B)/false',
  'B renomme A et le désactive');
select essai.devenir(:B::uuid); set role authenticated;
update public.profils set actif = true where id = :A::uuid;
reset role; select essai.personne();
select essai.egal((select role || '/' || actif from public.profils where id = :A::uuid), 'superadministrateur/true',
  'et le réactive');

select essai.titre('3. C de même, en remontant');
select essai.devenir(:C::uuid); set role authenticated;
select essai.verifie(public.gere_le_compte(:A::uuid) and public.gere_le_compte(:B::uuid), 'C gère A et B');
update public.profils set nom = 'B (vu par C)' where id = :B::uuid;
reset role; select essai.personne();
select essai.egal((select nom from public.profils where id = :B::uuid), 'B (vu par C)', 'C renomme B, son créateur');

select essai.titre('4. Dans l''autre sens, rien ne change');
select essai.devenir(:A::uuid); set role authenticated;
select essai.verifie(not public.est_mon_createur(:B::uuid), 'B n''est pas le créateur de A');
update public.profils set nom = 'B (vu par A)' where id = :B::uuid;
reset role; select essai.personne();
select essai.egal((select nom from public.profils where id = :B::uuid), 'B (vu par A)', 'A modifie B');
select essai.devenir(:B::uuid); set role authenticated;
update public.profils set nom = 'C (vu par B)' where id = :C::uuid;
update public.profils set nom = 'B lui-même' where id = :B::uuid;
reset role; select essai.personne();
select essai.egal((select nom from public.profils where id = :C::uuid), 'C (vu par B)', 'B modifie C');
select essai.egal((select nom from public.profils where id = :B::uuid), 'B lui-même', 'B modifie sa propre fiche');
update public.profils set nom = :'nom_a' where id = :A::uuid;

select essai.titre('5. Le dernier superadministrateur actif reste');
select coalesce(array_agg(id)::text, '{}') as autres from public.profils
 where role = 'superadministrateur' and actif and id <> :A::uuid \gset
update public.profils set actif = false where id = any(:'autres'::uuid[]);
select essai.egal((select count(*)::int from public.profils where role = 'superadministrateur' and actif), 1,
  'le décor : A est le seul superadministrateur actif');
select essai.devenir(:A::uuid); set role authenticated;
select essai.refuse(format($$update public.profils set role = 'administrateur' where id = %L::uuid$$, :A),
  'se rétrograder : refusé');
reset role; select essai.personne();
select essai.refuse(format($$update public.profils set actif = false where id = %L::uuid$$, :A),
  'le désactiver, même par la base : refusé');
select essai.refuse(format($$delete from public.profils where id = %L::uuid$$, :A), 'le supprimer : refusé');
update public.profils set actif = true where id = :B::uuid;
select essai.devenir(:B::uuid); set role authenticated;
update public.profils set actif = false where id = :A::uuid;
reset role; select essai.personne();
select essai.egal((select actif from public.profils where id = :A::uuid), false,
  'un autre superadministrateur actif : A peut être désactivé');
update public.profils set actif = true where id = :A::uuid;
update public.profils set actif = true where id = any(:'autres'::uuid[]);

select essai.titre('6. Un administrateur de boutique ne touche pas à un superadministrateur');
select essai.devenir('22222222-2222-2222-2222-222222222222'::uuid); set role authenticated;
select essai.sans_effet(format($$update public.profils set actif = false where id = %L::uuid$$, :B),
  'désactiver B : sans effet');
reset role; select essai.personne();

-- On remet tout en ordre pour les essais suivants.
update public.profils set actif = false where id in (:B::uuid, :C::uuid);
