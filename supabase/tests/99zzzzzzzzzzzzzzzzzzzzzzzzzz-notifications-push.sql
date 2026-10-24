-- =========================================================
-- Les notifications push, application fermée (3.65.0)
--
-- Ce qu'on prouve :
--   1. un compte connecté déclare son téléphone ; un visiteur, non ; un
--      jeton absurde est refusé ; le jeton suit le dernier compte
--      connecté ; dix téléphones au plus par compte ;
--   2. personne ne lit les jetons, ni n'appelle la fonction du serveur ;
--   3. une notification qui SONNE, pour un compte qui a un téléphone,
--      appelle la fonction Edge — et rien d'autre ne l'appelle ; sans
--      adresse réglée, rien ne part ;
--   4. « push_a_envoyer » rend la notification et ses jetons UNE fois ;
--   5. à la déconnexion le téléphone s'oublie ; un jeton mort s'efface.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set LIV      '''c9c9c9c9-0000-0000-0000-000000000001'''
\set AUTRE    '''c9c9c9c9-0000-0000-0000-000000000002'''

select essai.titre('Le décor : un livreur, un autre compte, un faux pg_net');
insert into auth.users (id, email) values
  (:LIV::uuid, 'liv.push@essai.bj'), (:AUTRE::uuid, 'autre.push@essai.bj')
on conflict do nothing;
update public.profils set role = 'livreur', actif = true, boutique_id = null, nom = 'Pélagie'
 where id = :LIV::uuid;
-- pg_net n'existe pas ici : on le simule, et on note ce qu'on lui demande.
create schema if not exists net;
create table if not exists net.appels (url text, corps jsonb, le timestamptz default now());
create or replace function net.http_post(url text, body jsonb default '{}', params jsonb default '{}',
  headers jsonb default '{}', timeout_milliseconds int default 5000) returns bigint
language sql as $$ insert into net.appels (url, corps) values (url, body); select 1::bigint $$;
truncate net.appels;
update public.push_reglage set url = '' where id = 1;

select essai.titre('1. Le téléphone se déclare');
set role anon;
select essai.refuse($$select public.enregistrer_appareil('jeton-de-test-0000000000000001')$$,
  'un visiteur : refusé');
reset role;
select essai.devenir(:LIV::uuid); set role authenticated;
select essai.verifie(public.enregistrer_appareil('jeton-de-test-0000000000000001'), 'le livreur déclare son téléphone');
select essai.refuse($$select public.enregistrer_appareil('court')$$, 'un jeton absurde : refusé');
select essai.verifie(public.enregistrer_appareil('jeton-de-test-0000000000000001'), 'le redéclarer ne double rien');
select essai.refuse($$select * from public.appareils_push$$, 'il ne lit pas la table des jetons');
select essai.refuse($$select public.push_a_envoyer(1)$$, 'ni n''appelle la fonction du serveur');
select essai.refuse($$select public.jeton_push_mort('x')$$, 'ni n''efface un jeton');
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.appareils_push where compte = :LIV::uuid), 1, 'un téléphone, une ligne');

select essai.devenir(:AUTRE::uuid); set role authenticated;
select public.enregistrer_appareil('jeton-de-test-0000000000000001') as pris \gset
reset role; select essai.personne();
select essai.egal((select compte from public.appareils_push where jeton = 'jeton-de-test-0000000000000001'), :AUTRE::uuid,
  'le même téléphone, un autre compte connecté : le jeton le suit');
select essai.devenir(:LIV::uuid); set role authenticated;
select count(public.enregistrer_appareil('jeton-de-test-00000000000000' || lpad(i::text, 2, '0')))
  from generate_series(1, 12) i \gset
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.appareils_push where compte = :LIV::uuid), 10,
  'douze téléphones déclarés : les dix derniers restent');

select essai.titre('2. Une notification qui sonne appelle la fonction Edge');
select public.notifier(array[:LIV::uuid], 'course_confiee', 'Course', 'x', '#/livraisons', null, null, true) as n0 \gset
select essai.egal((select count(*)::int from net.appels), 0, 'adresse non réglée : rien ne part');
update public.push_reglage set url = 'https://essai.supabase.co/functions/v1/envoyer-push' where id = 1;
select essai.refuse($$update public.push_reglage set url = 'http://pas-sur.bj' where id = 1$$,
  'une adresse sans https : refusée');
select public.notifier(array[:LIV::uuid], 'course_confiee', 'Nouvelle course', 'Commande BZ-1',
  '#/livraisons', null, null, true) as n1 \gset
select essai.egal((select count(*)::int from net.appels), 1, 'une course confiée : un appel');
select essai.egal((select url from net.appels limit 1), 'https://essai.supabase.co/functions/v1/envoyer-push',
  'vers l''adresse réglée');
select essai.verifie((select (corps ->> 'id')::bigint = (select max(id) from public.notifications
                       where destinataire = :LIV::uuid) from net.appels limit 1),
  'avec le seul numéro de la notification');
select public.notifier(array[:LIV::uuid], 'gain_livraison', 'Gain', 'x', '#/gains', null, null, false) as n2 \gset
select essai.egal((select count(*)::int from net.appels), 1, 'une notification qui ne sonne pas : aucun appel');
select public.notifier(array[:CHEF::uuid], 'commande_payee', 'Nouvelle commande', 'x', '#/commandes', null, null, true) as n3 \gset
select essai.egal((select count(*)::int from net.appels), 1, 'un compte sans téléphone déclaré : aucun appel');

select essai.titre('3. La fonction du serveur : une fois, et une seule');
select max(id) as nid from public.notifications where destinataire = :LIV::uuid and type = 'course_confiee' \gset
select essai.egal((select (public.push_a_envoyer(:nid) ->> 'titre')), 'Nouvelle course', 'elle rend la notification');
update public.notifications set push_le = null where id = :nid;
select essai.egal((select jsonb_array_length(public.push_a_envoyer(:nid) -> 'jetons')), 10, 'et les dix téléphones du livreur');
select essai.egal(public.push_a_envoyer(:nid), null::jsonb, 'rappelée : rien une seconde fois');
select max(id) as nid2 from public.notifications where destinataire = :LIV::uuid and type = 'gain_livraison' \gset
select essai.egal(public.push_a_envoyer(:nid2), null::jsonb, 'une notification qui ne sonne pas : rien');

select essai.titre('4. Déconnexion, jeton mort');
select essai.devenir(:LIV::uuid); set role authenticated;
select essai.verifie(public.oublier_appareil('jeton-de-test-0000000000000012'), 'à la déconnexion, le téléphone s''oublie');
select essai.verifie(not public.oublier_appareil('jeton-de-test-0000000000000001'), 'pas celui d''un autre compte');
reset role; select essai.personne();
select public.jeton_push_mort('jeton-de-test-0000000000000011');
select essai.egal((select count(*)::int from public.appareils_push where compte = :LIV::uuid), 8,
  'le jeton mort est effacé : huit restent');

-- Le décor rendu.
update public.push_reglage set url = '' where id = 1;
drop schema net cascade;
