-- =========================================================
-- Vérifier son numéro : ce que GoTrue décide, et nous pas.
--
-- Le banc précédent (60) simulait la vérification en posant le
-- drapeau à la main, faute de mécanisme réel. Il y en a un
-- maintenant, et c'est LUI qu'on éprouve ici :
-- « auth.users.phone_confirmed_at », écrit par GoTrue, dans un
-- schéma que l'application ne peut pas toucher.
--
-- Ce qui se joue :
--
--   1. LE DRAPEAU SUIT GoTrue, ET RIEN D'AUTRE. Confirmer un
--      numéro chez GoTrue doit poser « clients.tel_verifie » ;
--      l'application, elle, ne doit toujours pas pouvoir le
--      poser elle-même ;
--   2. LE DÉCLENCHEUR NE FAIT JAMAIS ÉCHOUER « verify ». Il
--      tourne dans SA transaction : une erreur ici, et le
--      client qui a reçu son SMS et tapé le bon code verrait
--      une panne. Quoi qu'on lui présente, il doit laisser
--      passer ;
--   3. UN NUMÉRO VÉRIFIÉ N'APPARTIENT QU'À UN COMPTE. Il donne
--      accès aux commandes passées avec lui : deux comptes qui
--      le revendiquent liraient les achats l'un de l'autre ;
--   4. LES OPÉRATEURS RECYCLENT LES NUMÉROS. Qui hérite d'une
--      ancienne ligne ne doit pas hériter des commandes de son
--      ancien titulaire.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
-- « notice » et pas « warning » : c'est par des notices que les constats
-- s'affichent. Les avis du déclencheur passent ici aussi, et c'est tant
-- mieux — ils disent tout haut ce qu'il a choisi de taire.
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set FATOU    '''88888888-8888-8888-8888-888888888888'''
\set IBRAHIM  '''99999999-9999-9999-9999-999999999999'''
\set VOLEUSE  '''aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'''

select essai.titre('Le numéro national, tel que BIZZOO le range');

-- Supabase range « 2290197121596 » ; le panier, lui, a toujours écrit
-- « 0197121596 ». Sans cette conversion, un compte ne retrouverait
-- jamais ses commandes d'avant.
select essai.egal(public.tel_national('2290197121596', '229'), '0197121596',
  'l''indicatif est retiré');
select essai.egal(public.tel_national('+229 01 97 12 15 96', '229'), '0197121596',
  'le « + » et les espaces aussi');
select essai.egal(public.tel_national('0197121596', '229'), '0197121596',
  'un numéro déjà national ne perd rien');
select essai.egal(public.tel_national('', '229'), '',
  'rien donne rien');
select essai.egal(public.tel_national('229', '229'), '229',
  'l''indicatif seul n''est pas un numéro vide');

-- ---------------------------------------------------------
select essai.titre('Entrer chez BIZZOO par son numéro');
-- ---------------------------------------------------------
-- Fatou n'a pas d'adresse e-mail. GoTrue crée son compte à la première
-- demande de code, puis confirme au code validé.
insert into auth.users (id, email, phone, raw_user_meta_data)
values (:FATOU::uuid, null, '2290197515151', '{"compte":"client","nom":"Fatou"}'::jsonb)
on conflict do nothing;

select essai.egal((select count(*)::int from public.profils where id = :FATOU::uuid), 0,
  'un compte sans e-mail n''atterrit pas dans la liste de l''équipe');
select essai.egal((select count(*)::int from public.clients where id = :FATOU::uuid), 0,
  'et rien n''est vérifié tant que le code n''est pas validé');

-- Le code est validé : GoTrue pose l'heure. Tout le reste en découle.
update auth.users set phone_confirmed_at = now() where id = :FATOU::uuid;

select essai.egal((select tel from public.clients where id = :FATOU::uuid), '0197515151',
  'la fiche naît avec le numéro national');
select essai.egal((select tel_verifie from public.clients where id = :FATOU::uuid), true,
  'et vérifiée');
select essai.egal((select nom from public.clients where id = :FATOU::uuid), 'Fatou',
  'avec le nom donné à l''inscription');

-- ---------------------------------------------------------
select essai.titre('Confirmer son numéro sur un compte e-mail');
-- ---------------------------------------------------------
-- Ibrahim s'est inscrit par e-mail. Il ajoute son numéro ensuite :
-- GoTrue envoie un code, et pose les deux colonnes d'un coup.
insert into auth.users (id, email, raw_user_meta_data)
values (:IBRAHIM::uuid, 'ibrahim@client.bj', '{"compte":"client"}'::jsonb)
on conflict do nothing;
insert into public.clients (id, nom, tel) values (:IBRAHIM::uuid, 'Ibrahim', '96606060')
on conflict (id) do nothing;

select essai.egal((select tel_verifie from public.clients where id = :IBRAHIM::uuid), false,
  'son numéro saisi à la main ne vaut rien');

update auth.users
   set phone = '2290196606060', phone_confirmed_at = now()
 where id = :IBRAHIM::uuid;

select essai.egal((select tel_verifie from public.clients where id = :IBRAHIM::uuid), true,
  'le code validé le vérifie');
select essai.egal((select tel from public.clients where id = :IBRAHIM::uuid), '0196606060',
  'et pose le numéro que GoTrue a confirmé, pas celui qui était saisi');

-- ---------------------------------------------------------
select essai.titre('L''application ne se déclare toujours pas vérifiée');
-- ---------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data)
values (:VOLEUSE::uuid, 'voleuse@client.bj', '{"compte":"client"}'::jsonb)
on conflict do nothing;
insert into public.clients (id, nom, tel) values (:VOLEUSE::uuid, 'Voleuse', '0197515151')
on conflict (id) do nothing;

select essai.devenir(:VOLEUSE::uuid);
set role authenticated;
select essai.refuse(
  $$update public.clients set tel_verifie = true
     where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'elle se déclare vérifiée sur le numéro de Fatou');
select essai.refuse($$select public.reconcilier_numeros_verifies()$$,
  'elle lance la réconciliation de l''enseigne');
reset role;
select essai.personne();

-- Et « auth.users » ne se touche pas davantage depuis l'application :
-- le schéma entier lui est fermé.
select essai.devenir(:VOLEUSE::uuid);
set role authenticated;
select essai.refuse(
  $$update auth.users set phone_confirmed_at = now()
     where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'elle se confirme elle-même chez GoTrue');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Un numéro vérifié n''appartient qu''à un compte');
-- ---------------------------------------------------------
-- La voleuse obtient d'une façon ou d'une autre un code sur le numéro
-- de Fatou — carte SIM récupérée, code lu par-dessus l'épaule. GoTrue
-- confirme ; BIZZOO, lui, refuse de transférer.
update auth.users
   set phone = '2290197515151', phone_confirmed_at = now()
 where id = :VOLEUSE::uuid;

select essai.egal((select tel_verifie from public.clients where id = :VOLEUSE::uuid), false,
  'son compte n''est pas vérifié sur un numéro déjà pris');
select essai.egal((select tel_verifie from public.clients where id = :FATOU::uuid), true,
  'et Fatou garde le sien');
select essai.egal(
  (select count(*)::int from public.clients where tel = '0197515151' and tel_verifie), 1,
  'un seul compte porte ce numéro vérifié');

-- ---------------------------------------------------------
select essai.titre('Le déclencheur ne fait jamais échouer « verify »');
-- ---------------------------------------------------------
-- C'est le point le plus délicat : ce code tourne DANS la transaction de
-- GoTrue. S'il lève quoi que ce soit, le client qui a reçu son SMS et
-- tapé le bon code voit une panne. On lui présente donc les trois cas
-- qui devraient le faire trébucher.

-- 1. Un compte de l'équipe confirme son numéro. Lui poser une fiche
--    client ferait de lui les deux à la fois, ce que la base refuse.
update auth.users set phone = '2290190000001', phone_confirmed_at = now()
 where id = :CHEF::uuid;
select essai.egal((select count(*)::int from public.clients where id = :CHEF::uuid), 0,
  'un compte d''équipe qui confirme son numéro ne devient pas client');
select essai.egal((select actif from public.profils where id = :CHEF::uuid), true,
  'et reste de l''équipe');

-- 2. Un numéro déjà pris — déjà vu plus haut, la transaction a tenu.
-- 3. Un numéro vide, que rien ne permet de ranger.
update auth.users set phone = '', phone_confirmed_at = now()
 where id = :VOLEUSE::uuid;
select essai.verifie(true, 'un numéro vide passe sans casser la transaction');

-- Et la confirmation reste acquise chez GoTrue dans tous les cas : c'est
-- lui la source de vérité, pas notre fiche.
select essai.egal(
  (select count(*)::int from auth.users
    where id = :CHEF::uuid and phone_confirmed_at is not null), 1,
  'la confirmation de GoTrue n''a pas été annulée');

-- ---------------------------------------------------------
select essai.titre('Rattraper ce que le silence a manqué');
-- ---------------------------------------------------------
-- Le déclencheur avale ses erreurs — il le faut. La réconciliation
-- rattrape, et elle n'est ouverte qu'à l'enseigne.
insert into auth.users (id, email, phone, phone_confirmed_at, raw_user_meta_data)
values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'oublie@client.bj',
        '2290195050505', now(), '{"compte":"client"}'::jsonb)
on conflict do nothing;
-- On simule le silence : la fiche existe, mais sans le numéro vérifié.
begin;
select set_config('bizzoo.verification', 'oui', true);
insert into public.clients (id, nom) values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Oublié')
on conflict (id) do update set tel = '', tel_verifie = false;
commit;

select essai.egal(
  (select tel_verifie from public.clients where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  false, 'sa fiche ignore que GoTrue a confirmé');

select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select public.reconcilier_numeros_verifies() as rattrapes \gset
reset role;
select essai.personne();

select essai.verifie(:'rattrapes'::int >= 1, 'l''enseigne rattrape');
select essai.egal(
  (select tel_verifie from public.clients where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  true, 'et la fiche rejoint GoTrue');
select essai.egal(
  (select tel from public.clients where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
  '0195050505', 'avec le bon numéro');
select essai.egal((select tel_verifie from public.clients where id = :VOLEUSE::uuid), false,
  'et la réconciliation ne vole pas plus que le déclencheur');

-- ---------------------------------------------------------
select essai.titre('Ce qu''un numéro vérifié ouvre — et pas plus loin');
-- ---------------------------------------------------------
-- Une commande d'hier, passée sans compte avec le numéro de Fatou.
set role anon;
select public.creer_commande('{"nom":"Fatou","tel":"0197515151"}'::jsonb,
  '[{"produit_id":"prod_marge","quantite":1}]'::jsonb) ->> 'id' as recente \gset
select public.creer_commande('{"nom":"Fatou","tel":"0197515151"}'::jsonb,
  '[{"produit_id":"prod_marge","quantite":1}]'::jsonb) ->> 'id' as ancienne \gset
reset role;

-- Celle-là date de deux ans. Les opérateurs béninois recyclent les
-- numéros : qui hérite d'une ligne ne doit pas hériter du passé lointain
-- de son ancien titulaire.
begin;
select set_config('bizzoo.interne', 'oui', true);
update public.commandes set cree_le = now() - interval '2 years' where id = :'ancienne';
commit;

select essai.devenir(:FATOU::uuid);
set role authenticated;
select public.rattacher_mes_commandes() as reprises \gset
reset role;
select essai.personne();

select essai.egal(:'reprises'::int, 1, 'elle retrouve sa commande récente');
select essai.egal((select client_id from public.commandes where id = :'recente'),
  :FATOU::uuid, 'qui porte désormais son compte');
select essai.egal((select client_id is null from public.commandes where id = :'ancienne'),
  true, 'la commande de l''avant-dernière année reste hors de portée');

-- Et un compte non vérifié ne réclame toujours rien.
select essai.devenir(:VOLEUSE::uuid);
set role authenticated;
select essai.refuse($$select public.rattacher_mes_commandes()$$,
  'un compte non vérifié réclame les commandes d''un numéro');
reset role;
select essai.personne();
