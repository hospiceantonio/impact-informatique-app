-- =========================================================
-- L'administrateur de BIZZOO crée un vendeur (3.81.0, à valider en 4.5.0)
--
-- Ce qu'on prouve :
--   1. l'administrateur de BIZZOO crée un vendeur : la fiche toute fraîche
--      de l'inscription devient un vendeur sans boutique, INACTIF et « à
--      valider » (4.5.0) ; le superadministrateur est prévenu, une fois,
--      et la notification mène à ce vendeur ;
--   2. il ne change pas en vendeur un livreur déjà en service ;
--   3. il ne modifie ni ne supprime un vendeur : c'est au
--      superadministrateur ;
--   4. l'administrateur d'une boutique ne crée pas de vendeur ;
--   5. (4.5.0) il pose le lieu du vendeur qu'il vient de créer, sur
--      place ; un autre administrateur, non ;
--   6. (4.5.0) le superadministrateur le valide en l'activant : le
--      créateur est prévenu, et ne touche plus au lieu.
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
\set ADMBZ2   '''cececece-0000-0000-0000-000000000005'''

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
select essai.egal((select role || '/' || actif || '/' || a_valider || '/' || coalesce(boutique_id, '—')
                     from public.profils where id = :VND::uuid),
  'vendeur/false/true/—', '(4.5.0) un vendeur INACTIF, à valider, sans boutique');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ENSEIGNE::uuid and type = 'vendeur_cree' and titre = 'Un vendeur à valider'
                      and lien = '#/vendeurs/' || :VND and corps like 'Vendeur V, créé par Admin BZ V (administrateur).%'), 1,
  'le superadministrateur est prévenu, une fois : « Un vendeur à valider », qui mène à ce vendeur');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ENSEIGNE::uuid and type = 'compte_a_valider' and lien like '%' || :VND), 0,
  'et pas une seconde fois comme un modérateur');
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

select essai.titre('5. (4.5.0) Il pose le lieu du vendeur qu''il vient de créer, sur place');
insert into auth.users (id, email) values (:ADMBZ2::uuid, 'admin.bz2.vendeur@essai.bj') on conflict do nothing;
update public.profils set role = 'administrateur', boutique_id = null, actif = true, nom = 'Admin BZ 2'
 where id = :ADMBZ2::uuid;
select essai.devenir(:ADMBZ::uuid); set role authenticated;
select public.enregistrer_lieu_vendeur(:VND::uuid, '{"nom":"Pagnes Afi","tel":"0197800002","adresse":"Dantokpa, allée 4","latitude":6.3702,"longitude":2.4289}'::jsonb) as l \gset
select essai.verifie((:'l'::jsonb ->> 'connu')::boolean and :'l'::jsonb ->> 'adresse' = 'Dantokpa, allée 4'
                     and (:'l'::jsonb ->> 'latitude')::numeric = 6.3702,
  'son créateur pose son lieu : adresse et position');
reset role; select essai.personne();
select essai.devenir(:ADMBZ2::uuid); set role authenticated;
select essai.refuse(format($$select public.enregistrer_lieu_vendeur(%L::uuid, '{"adresse":"Ailleurs","latitude":6.4,"longitude":2.5}'::jsonb)$$, :VND),
  'un autre administrateur de BIZZOO, non');
reset role; select essai.personne();

select essai.titre('6. (4.5.0) Le superadministrateur le valide en l''activant');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.profils set actif = true where id = :VND::uuid;
reset role; select essai.personne();
select essai.egal((select actif || '/' || a_valider from public.profils where id = :VND::uuid), 'true/false',
  'actif, et plus à valider');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ADMBZ::uuid and type = 'compte_valide'), 1,
  'son créateur est prévenu : « Compte validé »');
select essai.egal((select adresse from public.vendeurs_lieux where vendeur_id = :VND::uuid), 'Dantokpa, allée 4',
  'le lieu posé sur place est resté');
select essai.devenir(:ADMBZ::uuid); set role authenticated;
select essai.refuse(format($$select public.enregistrer_lieu_vendeur(%L::uuid, '{"adresse":"Ailleurs","latitude":6.4,"longitude":2.5}'::jsonb)$$, :VND),
  'validé, son lieu revient au superadministrateur');
reset role; select essai.personne();

delete from public.notifications where type in ('vendeur_cree', 'compte_valide');
delete from public.profils where id in (:VND::uuid, :VND2::uuid, :LIV::uuid, :ADMBZ::uuid, :ADMBZ2::uuid);
delete from auth.users where id in (:VND::uuid, :VND2::uuid, :LIV::uuid, :ADMBZ::uuid, :ADMBZ2::uuid);
