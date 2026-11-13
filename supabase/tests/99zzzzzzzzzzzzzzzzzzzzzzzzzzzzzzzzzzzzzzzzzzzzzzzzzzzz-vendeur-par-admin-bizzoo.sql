-- =========================================================
-- L'administrateur de BIZZOO crée un vendeur (3.81.0)
--
-- Ce qu'on prouve :
--   1. l'administrateur de BIZZOO crée un vendeur : la fiche toute fraîche
--      de l'inscription devient un vendeur actif, sans boutique ; le
--      superadministrateur est prévenu, une fois, et la notification
--      mène à ce vendeur ;
--   2. il ne change pas en vendeur un livreur déjà en service ;
--   3. il ne modifie ni ne supprime un vendeur : c'est au
--      superadministrateur ;
--   4. l'administrateur d'une boutique ne crée pas de vendeur.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ADMBZ    '''cececece-0000-0000-0000-000000000001'''
\set VND      '''cececece-0000-0000-0000-000000000002'''
\set LIV      '''cececece-0000-0000-0000-000000000003'''
\set VND2     '''cececece-0000-0000-0000-000000000004'''

select essai.titre('Le décor : un administrateur de BIZZOO, un livreur en service');
insert into auth.users (id, email) values (:ADMBZ::uuid, 'admin.bz.vendeur@essai.bj') on conflict do nothing;
update public.profils set role = 'administrateur', boutique_id = null, actif = true, nom = 'Admin BZ V'
 where id = :ADMBZ::uuid;
insert into auth.users (id, email, phone, raw_user_meta_data) values
  (:LIV::uuid, '', '2290197800003', '{"compte":"equipe"}') on conflict do nothing;
update public.profils set role = 'livreur', boutique_id = null, actif = true, nom = 'Livreur L', tel = '0197800003'
 where id = :LIV::uuid;
-- Comme le fait l'écran : l'inscription par le numéro pose la fiche en
-- attente, puis l'écran lui donne son rang (« on conflict »).
create function pg_temp.creer(qui uuid, cible uuid, tel text, boutique text) returns void language plpgsql as $$
begin
  perform essai.devenir(qui);
  set local role authenticated;
  insert into public.profils (id, email, role, actif, boutique_id, nom, tel)
  values (cible, '', 'vendeur', true, boutique, 'Vendeur V', tel)
  on conflict (id) do update set role = excluded.role, actif = excluded.actif,
    boutique_id = excluded.boutique_id, nom = excluded.nom, tel = excluded.tel, email = excluded.email;
  reset role;
  perform essai.personne();
end $$;
insert into auth.users (id, email, phone, raw_user_meta_data) values
  (:VND::uuid, '', '2290197800002', '{"compte":"equipe"}') on conflict do nothing;
select essai.egal((select role || '/' || actif from public.profils where id = :VND::uuid), 'moderateur/false',
  'l''inscription pose une fiche en attente');

select essai.titre('1. Il crée un vendeur');
select pg_temp.creer(:ADMBZ::uuid, :VND::uuid, '0197800002', null);
select essai.egal((select role || '/' || actif || '/' || coalesce(boutique_id, '—') from public.profils where id = :VND::uuid),
  'vendeur/true/—', 'un vendeur actif, sans boutique');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ENSEIGNE::uuid and type = 'vendeur_cree'
                      and lien = '#/vendeurs/' || :VND and corps like 'Vendeur V, créé par Admin BZ V (administrateur).%'), 1,
  'le superadministrateur est prévenu, une fois : la notification mène à ce vendeur');
select essai.devenir(:ADMBZ::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.profils where id = :VND::uuid), 1, 'il voit le vendeur créé');
reset role; select essai.personne();
-- Une boutique demandée : il reste un vendeur de BIZZOO.
insert into auth.users (id, email, phone, raw_user_meta_data) values
  (:VND2::uuid, '', '2290197800004', '{"compte":"equipe"}') on conflict do nothing;
select pg_temp.creer(:ADMBZ::uuid, :VND2::uuid, '0197800004', 'bou_informatique');
select essai.egal((select role || '/' || coalesce(boutique_id, '—') from public.profils where id = :VND2::uuid),
  'vendeur/—', 'une boutique demandée : il reste sans boutique');

select essai.titre('2. Pas un compte déjà en service');
select essai.refuse(format('select pg_temp.creer(%L, %L, %L, null)', :ADMBZ, :LIV, '0197800003'),
  'un livreur en service ne devient pas vendeur');
select essai.egal((select role from public.profils where id = :LIV::uuid), 'livreur', 'il reste livreur');

select essai.titre('3. Modifier, supprimer : au superadministrateur');
select essai.devenir(:ADMBZ::uuid); set role authenticated;
select essai.sans_effet(format($$update public.profils set nom = 'Autre' where id = %L::uuid$$, :VND),
  'il ne renomme pas le vendeur');
select essai.sans_effet(format($$update public.profils set tel = '0197800099' where id = %L::uuid$$, :VND),
  'ni ne change son numéro');
select essai.sans_effet(format($$delete from public.profils where id = %L::uuid$$, :VND), 'ni ne le supprime');
reset role; select essai.personne();

select essai.titre('4. L''administrateur d''une boutique ne crée pas de vendeur');
delete from public.profils where id = :VND2::uuid;
insert into public.profils (id, email, role, actif) values (:VND2::uuid, '', 'moderateur', false);
select essai.refuse(format('select pg_temp.creer(%L, %L, %L, null)', :CHEF, :VND2, '0197800004'),
  'refusé');
select essai.egal((select role from public.profils where id = :VND2::uuid), 'moderateur', 'la fiche reste en attente');

delete from public.notifications where type = 'vendeur_cree';
delete from public.profils where id in (:VND::uuid, :VND2::uuid, :LIV::uuid, :ADMBZ::uuid);
delete from auth.users where id in (:VND::uuid, :VND2::uuid, :LIV::uuid, :ADMBZ::uuid);
