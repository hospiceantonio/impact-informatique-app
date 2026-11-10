-- =========================================================
-- Les notifications dans le navigateur (3.80.0)
--
-- Ce qu'on prouve :
--   1. la clé publique se lit sans session ; elle est vide tant que
--      BIZZOO ne l'a pas réglée ;
--   2. un compte connecté abonne son navigateur ; un visiteur, un
--      abonnement illisible : refusés ; personne ne lit la table ;
--      cinq navigateurs au plus par compte et par application ;
--   3. une notification qui sonne part vers ses navigateurs, de la bonne
--      application (« #/commande/… » : le client ; le reste : l'admin),
--      même sans téléphone déclaré ;
--   4. un navigateur s'oublie sans session ; un abonnement mort ne
--      s'efface que par le serveur.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set CLIENT   '''ffffffff-2222-2222-2222-222222222222'''
\set PW       '''cacacaca-0000-0000-0000-000000000001'''

select essai.titre('Le décor : un compte de l''équipe, un client, un faux pg_net');
insert into auth.users (id, email) values (:PW::uuid, 'pw.navigateur@essai.bj') on conflict do nothing;
update public.profils set role = 'livreur', actif = true, boutique_id = null, nom = 'Paulin' where id = :PW::uuid;
create schema if not exists net;
create table if not exists net.appels (url text, corps jsonb, le timestamptz default now());
create or replace function net.http_post(url text, body jsonb default '{}', params jsonb default '{}',
  headers jsonb default '{}', timeout_milliseconds int default 5000) returns bigint
language sql as $$ insert into net.appels (url, corps) values (url, body); select 1::bigint $$;
truncate net.appels;
update public.push_reglage set url = 'https://essai.supabase.co/functions/v1/envoyer-push' where id = 1;
delete from public.appareils_push where compte in (:PW::uuid, :CLIENT::uuid);
delete from public.appareils_web where compte in (:PW::uuid, :CLIENT::uuid);
select coalesce(cle_publique, '') as cle_avant from public.rh_push_reglage where id = 1 \gset

create function pg_temp.abonner(qui uuid, point text, app text) returns boolean language plpgsql as $$
declare r boolean;
begin
  perform essai.devenir(qui);
  set local role authenticated;
  r := public.enregistrer_navigateur(point, repeat('B', 87), repeat('a', 22), app);
  reset role;
  perform essai.personne();
  return r;
end $$;

select essai.titre('1. La clé publique');
update public.rh_push_reglage set cle_publique = '' where id = 1;
set role anon;
select essai.egal(public.cle_push_web(), null::text, 'pas encore réglée : rien');
reset role;
update public.rh_push_reglage set cle_publique = 'BCleVapidPubliqueDEssai' where id = 1;
set role anon;
select essai.egal(public.cle_push_web(), 'BCleVapidPubliqueDEssai'::text, 'réglée : un visiteur la lit');
reset role;

select essai.titre('2. Le navigateur s''abonne');
set role anon;
select essai.refuse($$select public.enregistrer_navigateur('https://fcm.googleapis.com/fcm/send/x', repeat('B', 87), repeat('a', 22), 'client')$$,
  'un visiteur : refusé');
reset role;
select essai.verifie(pg_temp.abonner(:CLIENT::uuid, 'https://fcm.googleapis.com/fcm/send/client-1', 'client'),
  'le client abonne son navigateur');
select essai.refuse(format('select pg_temp.abonner(%L, %L, %L)', :CLIENT, 'http://pas-sur.bj/x', 'client'),
  'une adresse sans https : refusée');
select essai.devenir(:CLIENT::uuid); set role authenticated;
select essai.refuse($$select public.enregistrer_navigateur('https://fcm.googleapis.com/fcm/send/y', 'court', 'court', 'client')$$,
  'des clés absurdes : refusées');
select essai.refuse($$select * from public.appareils_web$$, 'il ne lit pas la table des navigateurs');
select essai.refuse($$select public.navigateurs_de(auth.uid(), 'client')$$, 'ni la fonction du serveur');
select essai.refuse($$select public.navigateur_mort('https://fcm.googleapis.com/fcm/send/client-1')$$,
  'ni n''efface un abonnement');
reset role; select essai.personne();
select essai.verifie(pg_temp.abonner(:CLIENT::uuid, 'https://fcm.googleapis.com/fcm/send/client-1', 'client'),
  'le redéclarer ne double rien');
select essai.egal((select count(*)::int from public.appareils_web where compte = :CLIENT::uuid), 1, 'un navigateur, une ligne');
select essai.verifie(pg_temp.abonner(:PW::uuid, 'https://fcm.googleapis.com/fcm/send/client-1', 'admin'),
  'le même navigateur, un autre compte connecté');
select essai.verifie((select compte = :PW::uuid and application = 'admin' from public.appareils_web
                       where endpoint = 'https://fcm.googleapis.com/fcm/send/client-1'),
  'l''abonnement le suit : il ne sonne plus pour le compte d''avant');
select count(pg_temp.abonner(:PW::uuid, 'https://updates.push.services.mozilla.com/wpush/v2/pw-' || i, 'admin'))
  from generate_series(1, 7) i \gset
select essai.egal((select count(*)::int from public.appareils_web where compte = :PW::uuid and application = 'admin'), 5,
  'huit navigateurs abonnés : les cinq derniers restent');
select essai.verifie((select array_agg(right(endpoint, 4) order by endpoint) from public.appareils_web
                       where compte = :PW::uuid) = array['pw-3', 'pw-4', 'pw-5', 'pw-6', 'pw-7'],
  'les plus anciens s''effacent');
select essai.verifie(pg_temp.abonner(:CLIENT::uuid, 'https://fcm.googleapis.com/fcm/send/client-1', 'client'),
  'le client reprend son navigateur');

select essai.titre('3. Une notification qui sonne part vers les navigateurs');
truncate net.appels;
select public.notifier(array[:CLIENT::uuid], 'commande_en_route', 'Votre commande arrive', 'BZ-WEB',
  '#/commande/BZ-WEB', null, null, true) as nc \gset
select essai.egal((select count(*)::int from net.appels), 1, 'sans téléphone déclaré, le client est réveillé');
select max(id) as nidc from public.notifications where destinataire = :CLIENT::uuid and type = 'commande_en_route' \gset
select public.push_a_envoyer(:nidc) as envoi \gset
select essai.egal(:'envoi'::jsonb ->> 'application', 'client'::text, 'l''application du client');
select essai.verifie(:'envoi'::jsonb -> 'web' @> '[{"endpoint":"https://fcm.googleapis.com/fcm/send/client-1"}]'::jsonb
                     and jsonb_array_length(:'envoi'::jsonb -> 'web') = 1
                     and (:'envoi'::jsonb -> 'web' -> 0 ->> 'p256dh') <> ''
                     and (:'envoi'::jsonb -> 'web' -> 0 ->> 'auth') <> '',
  'avec son navigateur, et de quoi chiffrer');
select essai.egal(jsonb_array_length(:'envoi'::jsonb -> 'jetons'), 0, 'et aucun téléphone');
select public.notifier(array[:PW::uuid], 'course_confiee', 'Nouvelle course', 'BZ-WEB',
  '#/livraisons', null, null, true) as nl \gset
select max(id) as nidl from public.notifications where destinataire = :PW::uuid and type = 'course_confiee' \gset
select essai.egal(jsonb_array_length(public.push_a_envoyer(:nidl) -> 'web'), 5,
  'le livreur : ses cinq navigateurs de l''administration');
select public.notifier(array[:PW::uuid], 'commande_en_route', 'Votre commande arrive', 'BZ-WEB2',
  '#/commande/BZ-WEB2', null, null, true) as np \gset
select essai.egal((select count(*)::int from net.appels), 2,
  'une notification « client » pour un compte abonné côté administration seulement : aucun appel');
truncate net.appels;
select public.notifier(array[:PW::uuid], 'gain_livraison', 'Gain', 'x', '#/gains', null, null, false) as ns \gset
select essai.egal((select count(*)::int from net.appels), 0, 'une notification qui ne sonne pas : aucun appel');

select essai.titre('4. Oublier un navigateur');
set role anon;
select essai.verifie(public.oublier_navigateur('https://fcm.googleapis.com/fcm/send/client-1'),
  'sans session, l''adresse d''abonnement suffit');
select essai.verifie(not public.oublier_navigateur('https://fcm.googleapis.com/fcm/send/inconnu'),
  'une adresse inconnue : rien');
select essai.refuse($$select public.navigateur_mort('https://updates.push.services.mozilla.com/wpush/v2/pw-7')$$,
  'un visiteur n''efface pas un abonnement mort');
reset role;
select essai.egal((select count(*)::int from public.appareils_web where compte = :CLIENT::uuid), 0, 'le client n''a plus de navigateur');
select public.navigateur_mort('https://updates.push.services.mozilla.com/wpush/v2/pw-7');
select essai.egal((select count(*)::int from public.appareils_web where compte = :PW::uuid), 4,
  'le serveur efface un abonnement mort');
delete from public.notifications where destinataire = :PW::uuid;
delete from public.profils where id = :PW::uuid;
delete from auth.users where id = :PW::uuid;
select essai.egal((select count(*)::int from public.appareils_web where compte = :PW::uuid), 0,
  'un compte supprimé : ses navigateurs partent avec lui');

update public.rh_push_reglage set cle_publique = :'cle_avant' where id = 1;
update public.push_reglage set url = '' where id = 1;
