-- =========================================================
-- Le code SMS : le superadministrateur seul, et l'appareil de confiance
-- (3.59.0)
--
-- Ce qu'on prouve :
--   1. interrupteur allumé, seul le superadministrateur rend un code ;
--   2. on ne fait confiance à un appareil qu'APRÈS avoir rendu son code ;
--   3. une nouvelle session sur cet appareil est confirmée sans SMS ; un
--      autre jeton, un autre compte, ou une confiance expirée : non ;
--   4. « oublier mes appareils » : le code est redemandé ; la table ne se
--      lit ni ne s'écrit à la main.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set SUP      '''f2000000-0000-0000-0000-000000000001'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set T1       '''f1000000-0000-0000-0000-000000000001'''
\set T2       '''f1000000-0000-0000-0000-000000000002'''
\set T3       '''f1000000-0000-0000-0000-000000000003'''
\set T4       '''f1000000-0000-0000-0000-000000000004'''
\set JETON    '''aaaaaaaabbbbbbbbccccccccddddddddeeeeeeeeffffffff0000000011111111'''
\set AUTRE    '''9999999988888888777777776666666655555555444444443333333322222222'''

select essai.titre('1. Seul le superadministrateur rend un code');
insert into auth.users (id, email) values (:SUP::uuid, 'sup.confiance@essai.bj') on conflict do nothing;
update public.profils set role = 'superadministrateur', actif = true, boutique_id = null, nom = 'Sup',
       tel = '0197000077' where id = :SUP::uuid;
update public.securite_equipe set sms_exige = true;
select essai.devenir(:SUP::uuid, :T1::uuid); set role authenticated;
select essai.verifie(not public.est_super(), 'superadministrateur sans code : aucun droit');
select essai.egal((public.etat_connexion() ->> 'sms_exige')::boolean, true, 'l''écran lui demande le code');
reset role;
select essai.devenir(:CHEF::uuid, :T1::uuid); set role authenticated;
select essai.verifie(public.est_admin(), 'l''administrateur, lui, entre sans code');
reset role;

select essai.titre('2. La confiance se donne après le code');
select essai.devenir(:SUP::uuid, :T1::uuid); set role authenticated;
select essai.refuse(format($$select public.confier_appareil(%L)$$, :JETON),
  'sans code rendu : pas de confiance');
reset role;
select essai.envoyer(:SUP::uuid, :T1::uuid, '314159');
select essai.devenir(:SUP::uuid, :T1::uuid); set role authenticated;
select essai.egal((public.confirmer_code_connexion('314159') ->> 'ok')::boolean, true, 'le code rendu');
select essai.refuse($$select public.confier_appareil('court')$$, 'un jeton trop court : refusé');
select public.confier_appareil(:JETON, 'Téléphone d''essai') as fin \gset
select essai.verifie(:'fin'::timestamptz between now() + interval '29 days' and now() + interval '31 days',
  'confiance donnée pour un mois');
select essai.egal(public.mes_appareils_confiance(), 1, 'un appareil de confiance');
reset role;
select essai.verifie((select empreinte <> :JETON from public.appareils_confiance where utilisateur = :SUP::uuid),
  'la base ne garde que l''empreinte du jeton, pas le jeton');

select essai.titre('3. Une nouvelle connexion sur cet appareil : sans SMS');
select essai.devenir(:SUP::uuid, :T2::uuid); set role authenticated;
select essai.verifie(not public.est_super(), 'nouvelle session : rien encore');
select essai.egal(public.reconnaitre_appareil(:AUTRE), false, 'un autre jeton : pas reconnu');
select essai.verifie(not public.est_super(), 'toujours rien');
select essai.egal(public.reconnaitre_appareil(:JETON), true, 'le jeton de l''appareil : reconnu');
select essai.verifie(public.est_super(), 'le superadministrateur retrouve tout, sans SMS');
reset role;
select essai.devenir(:CHEF::uuid, :T3::uuid); set role authenticated;
select essai.egal(public.reconnaitre_appareil(:JETON), false, 'le même jeton sur un autre compte : rien');
reset role;
update public.appareils_confiance set expire_le = now() - interval '1 day' where utilisateur = :SUP::uuid;
select essai.devenir(:SUP::uuid, :T3::uuid); set role authenticated;
select essai.egal(public.reconnaitre_appareil(:JETON), false, 'un mois passé : le code est redemandé');
select essai.verifie(not public.est_super(), 'et la session reste fermée');
reset role;
update public.appareils_confiance set expire_le = now() + interval '30 days' where utilisateur = :SUP::uuid;

select essai.titre('4. Oublier ses appareils ; la table est fermée');
select essai.devenir(:SUP::uuid, :T2::uuid); set role authenticated;
select essai.refuse('select * from public.appareils_confiance', 'la table ne se lit pas');
select essai.refuse($$insert into public.appareils_confiance (utilisateur, empreinte, expire_le)
  values (auth.uid(), 'x', now() + interval '1 year')$$, 'ni ne s''écrit à la main');
select essai.egal(public.oublier_appareils(), 1, 'oublier mes appareils');
select essai.egal(public.mes_appareils_confiance(), 0, 'plus aucun');
reset role;
select essai.devenir(:SUP::uuid, :T4::uuid); set role authenticated;
select essai.egal(public.reconnaitre_appareil(:JETON), false, 'le code est redemandé partout');
reset role;

update public.securite_equipe set sms_exige = false;
