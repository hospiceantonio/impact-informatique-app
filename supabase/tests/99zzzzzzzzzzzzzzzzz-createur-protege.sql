-- =========================================================
-- On ne touche pas à son créateur (3.59.0)
--
-- Ce qu'on prouve :
--   1. le superadministrateur A crée B, qui crée C ; la base retient qui
--      a créé qui ;
--   2. B ne modifie pas les droits de A : ni rôle, ni actif, ni droits,
--      ni mot de passe, ni suppression — pas même en passant sous les
--      règles de la table ;
--   3. C non plus, en remontant la chaîne : ni B, ni A ;
--   4. dans l'autre sens, rien ne change : A gère B, B gère C.
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

select essai.titre('2. B ne touche pas à A');
select essai.devenir(:B::uuid); set role authenticated;
select essai.verifie(public.est_mon_createur(:A::uuid), 'A est son créateur');
select essai.verifie(not public.gere_le_compte(:A::uuid), 'A n''est pas sous sa responsabilité');
select essai.sans_effet(format($$update public.profils set role = 'moderateur' where id = %L::uuid$$, :A),
  'rétrograder A : sans effet');
select essai.sans_effet(format($$update public.profils set actif = false where id = %L::uuid$$, :A),
  'désactiver A : sans effet');
select essai.sans_effet(format($$delete from public.profils where id = %L::uuid$$, :A),
  'supprimer la fiche de A : sans effet');
select essai.refuse(format($$select public.supprimer_compte(%L::uuid)$$, :A), 'supprimer le compte de A : refusé');
select essai.refuse(format($$select public.changer_mot_de_passe(%L::uuid, 'pris-en-main')$$, :A),
  'changer le mot de passe de A : refusé');
reset role;
-- Même hors des règles de la table, sous le nom de B : le déclencheur arrête.
select essai.refuse(format($$update public.profils set role = 'moderateur' where id = %L::uuid$$, :A),
  'même par une fonction de la base, sous le nom de B : refusé');
select essai.personne();
select essai.egal((select role || '/' || actif from public.profils where id = :A::uuid),
  'superadministrateur/true', 'A est intact');

select essai.titre('3. C non plus, en remontant');
select essai.devenir(:C::uuid); set role authenticated;
select essai.sans_effet(format($$update public.profils set actif = false where id = %L::uuid$$, :B),
  'C ne désactive pas B, son créateur');
select essai.sans_effet(format($$update public.profils set actif = false where id = %L::uuid$$, :A),
  'ni A, le créateur de son créateur');
reset role; select essai.personne();

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

-- On remet tout en ordre pour les essais suivants.
update public.profils set actif = false where id in (:B::uuid, :C::uuid);
