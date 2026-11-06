-- =========================================================
-- Le numéro d'un compte est son numéro de connexion (3.79.2)
--
-- Ce qu'on prouve :
--   1. le superadministrateur change le numéro d'un vendeur : le nouveau
--      devient le numéro de connexion, l'ancien n'ouvre plus rien ; le mot
--      de passe, le rôle, l'état du compte ne bougent pas ;
--   2. un numéro déjà pris par un autre compte (même écrit sur 8 chiffres)
--      est refusé — et alors rien ne change, ni fiche ni connexion ;
--   3. qui ne gère pas le compte ne change pas son numéro ;
--   4. un compte qui entre par e-mail garde son numéro comme simple contact ;
--   5. un compte qui entre par son numéro ne peut pas rester sans numéro ;
--   6. un compte déjà désaccordé (avant la 3.79.2) se répare ;
--   7. personne ne déclenche la synchronisation à la main.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set VA       '''c8c8c8c8-0000-0000-0000-00000000000a'''
\set VB       '''c8c8c8c8-0000-0000-0000-00000000000b'''
\set VC       '''c8c8c8c8-0000-0000-0000-00000000000c'''

select essai.titre('Le décor : deux vendeurs qui entrent par leur numéro');
insert into auth.users (id, email, phone, phone_confirmed_at, encrypted_password, raw_user_meta_data) values
  (:VA::uuid, '', '2290197700001', now(), 'mot-de-passe-A', '{"compte":"equipe"}'),
  (:VB::uuid, '', '2290197700002', now(), 'mot-de-passe-B', '{"compte":"equipe"}')
on conflict (id) do nothing;
-- Un modérateur qui entre par e-mail : son numéro n'est qu'un contact.
insert into auth.users (id, email) values (:VC::uuid, 'contact@bizzoo.bj') on conflict (id) do nothing;
update public.profils set role = 'moderateur', actif = true, boutique_id = 'bou_informatique', tel = ''
 where id = :VC::uuid;
update public.profils set role = 'vendeur', actif = true, boutique_id = null, nom = 'Vendeur A', tel = '0197700001'
 where id = :VA::uuid;
update public.profils set role = 'vendeur', actif = true, boutique_id = null, nom = 'Vendeur B', tel = '0197700002'
 where id = :VB::uuid;
select essai.egal((select phone from auth.users where id = :VA::uuid), '2290197700001',
  'au départ : la fiche et la connexion disent le même numéro');

create function pg_temp.comme(qui uuid, q text) returns void language plpgsql as $$
begin
  perform essai.devenir(qui);
  set local role authenticated;
  execute q;
  reset role;
  perform essai.personne();
end $$;
create function pg_temp.changer(qui uuid, cible uuid, tel text) returns void language plpgsql as $$
begin
  perform essai.devenir(qui);
  set local role authenticated;
  update public.profils set tel = changer.tel where id = cible;
  reset role;
  perform essai.personne();
end $$;
create function pg_temp.connexion(cible uuid) returns text language sql as $$
  select coalesce(phone, '') from auth.users where id = cible
$$;

select essai.titre('1. Le superadministrateur change le numéro : la connexion suit');
select pg_temp.comme(:ENSEIGNE::uuid, format($$update public.profils set tel = '01 97 70 09 99' where id = %L$$, :VA));
select essai.egal(pg_temp.connexion(:VA::uuid), '2290197700999', 'le nouveau numéro ouvre le compte');
select essai.verifie(not exists (select 1 from auth.users where phone = '2290197700001'),
  'l''ancien n''ouvre plus rien');
select essai.egal((select encrypted_password from auth.users where id = :VA::uuid), 'mot-de-passe-A',
  'le mot de passe reste le même');
select essai.verifie((select role = 'vendeur' and actif and nom = 'Vendeur A' from public.profils where id = :VA::uuid),
  'le rôle, l''état et le nom du compte ne bougent pas');
select essai.verifie((select phone_confirmed_at is not null from auth.users where id = :VA::uuid),
  'le numéro reste confirmé : il entre sans attendre de code');

select essai.titre('2. Un numéro déjà pris est refusé, et rien ne change');
select essai.refuse(format('select pg_temp.changer(%L, %L, %L)', :ENSEIGNE, :VA, '0197700002'),
  'le numéro d''un autre compte : refusé');
select essai.refuse(format('select pg_temp.changer(%L, %L, %L)', :ENSEIGNE, :VA, '97 70 00 02'),
  'le même, écrit sur 8 chiffres : refusé aussi');
select essai.egal((select tel from public.profils where id = :VA::uuid), '01 97 70 09 99', 'la fiche garde son numéro');
select essai.egal(pg_temp.connexion(:VA::uuid), '2290197700999', 'la connexion aussi');
select essai.egal(pg_temp.connexion(:VB::uuid), '2290197700002', 'et l''autre compte n''est pas touché');

select essai.titre('3. Qui ne gère pas le compte ne change pas son numéro');
select pg_temp.comme(:CHEF::uuid, format($$update public.profils set tel = '0197701234' where id = %L$$, :VA));
select essai.egal(pg_temp.connexion(:VA::uuid), '2290197700999',
  'l''administrateur d''une boutique : sans effet sur un vendeur');
select pg_temp.comme(:VA::uuid, format($$update public.profils set tel = '0197701234' where id = %L$$, :VA));
select essai.egal(pg_temp.connexion(:VA::uuid), '2290197700999', 'le vendeur lui-même : sans effet non plus');

select essai.titre('4. Un compte qui entre par e-mail : le numéro reste un contact');
select pg_temp.changer(:ENSEIGNE::uuid, :VC::uuid, '0197705555');
select essai.egal((select tel from public.profils where id = :VC::uuid), '0197705555', 'sa fiche prend le numéro');
select essai.egal(pg_temp.connexion(:VC::uuid), '', 'aucun numéro de connexion ne lui est donné');

select essai.titre('5. Un compte qui entre par son numéro ne reste pas sans numéro');
select essai.refuse(format('select pg_temp.changer(%L, %L, %L)', :ENSEIGNE, :VB, ''),
  'effacer son numéro : refusé');
select essai.refuse(format('select pg_temp.changer(%L, %L, %L)', :ENSEIGNE, :VB, '0197'),
  'un numéro trop court : refusé');
select essai.egal(pg_temp.connexion(:VB::uuid), '2290197700002', 'il entre toujours avec le sien');

select essai.titre('6. Un compte déjà désaccordé se répare');
update auth.users set phone = '2290197700777' where id = :VB::uuid;   -- comme avant la 3.79.2
select essai.verifie(public.synchroniser_numero_connexion(:VB::uuid, false), 'la réparation agit');
select essai.egal(pg_temp.connexion(:VB::uuid), '2290197700002', 'la connexion reprend le numéro de la fiche');
select essai.verifie(not public.synchroniser_numero_connexion(:VB::uuid, false), 'une seconde fois : rien à faire');

select essai.titre('7. Personne ne la déclenche à la main');
set role anon;
select essai.refuse(format($$select public.synchroniser_numero_connexion(%L::uuid)$$, :VA), 'un visiteur : refusé');
reset role;
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse(format($$select public.synchroniser_numero_connexion(%L::uuid)$$, :VA),
  'le superadministrateur non plus : il passe par la fiche');
reset role; select essai.personne();

delete from public.profils where id in (:VA::uuid, :VB::uuid, :VC::uuid);
delete from auth.users where id in (:VA::uuid, :VB::uuid, :VC::uuid);
