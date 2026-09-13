-- =========================================================
-- Les comptes clients : ce qu'un client peut, et surtout pas.
--
-- Jusqu'ici « authenticated » voulait dire « l'équipe ». À partir
-- du moment où un client se connecte, ce n'est plus vrai — et
-- chaque droit écrit pour l'équipe devient une question.
--
-- Deux choses tiennent tout le reste, et c'est ici qu'on les
-- force :
--
--   1. UN CLIENT CONNECTÉ N'EST PAS DE L'ÉQUIPE. Il ne doit pas
--      voir un franc de plus qu'un visiteur ;
--   2. LE NUMÉRO VÉRIFIÉ NE SE DÉCLARE PAS. C'est lui qui donne
--      accès aux commandes passées avec ce numéro : s'il
--      s'écrivait depuis l'application, il suffirait de taper le
--      numéro d'un voisin pour lire ses achats.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set AWA      '''44444444-4444-4444-4444-444444444444'''
\set KOFI     '''55555555-5555-5555-5555-555555555555'''

select essai.titre('Le décor : deux clients, et une commande d''avant');

insert into auth.users (id, email) values
  (:AWA::uuid,  'awa@client.bj'),
  (:KOFI::uuid, 'kofi@client.bj')
on conflict do nothing;

insert into public.clients (id, nom, tel) values
  (:AWA::uuid,  'Awa',  '97111111'),
  (:KOFI::uuid, 'Kofi', '97222222')
on conflict (id) do nothing;

select essai.egal((select count(*)::int from public.clients), 2, 'deux comptes clients');

-- Un numéro n'est jamais vérifié à la création, quoi qu'on insère.
insert into auth.users (id, email) values
  ('66666666-6666-6666-6666-666666666666', 'tricheur@client.bj')
on conflict do nothing;
insert into public.clients (id, nom, tel, tel_verifie) values
  ('66666666-6666-6666-6666-666666666666', 'Tricheur', '97333333', true)
on conflict (id) do nothing;
select essai.verifie(not exists (
  select 1 from public.clients where id = '66666666-6666-6666-6666-666666666666'
     and tel_verifie),
  'un compte naît non vérifié, même si l''insertion le prétend');
delete from public.clients where id = '66666666-6666-6666-6666-666666666666';

-- ---------------------------------------------------------
select essai.titre('Un client connecté n''est pas de l''équipe');
-- ---------------------------------------------------------
select essai.devenir(:AWA::uuid);
set role authenticated;

select essai.egal(public.est_equipe(), false, 'il n''est pas de l''équipe');
select essai.egal(public.est_super(), false, 'ni superadministrateur');
select essai.egal(public.est_client(), true, 'il est bien un client');

select essai.egal((select count(*)::int from public.profils), 0,
  'il ne voit aucun compte de l''équipe');
select essai.egal((select count(*)::int from public.journal), 0,
  'il ne lit pas le journal');
select essai.egal((select count(*)::int from public.produits_prive), 0,
  'il ne voit pas les prix grossistes');
select essai.egal((select count(*)::int from public.demandes), 0,
  'il ne voit pas les demandes de modification');

select essai.sans_effet(
  $$update public.produits set prix = 1 where id = 'prod_hp15'$$,
  'il ne change pas un prix');
select essai.refuse(
  $$insert into public.boutiques (id, nom) values ('bou_pirate', 'Pirate')$$,
  'il ne crée pas de boutique');

reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Un compte est de l''équipe OU d''un client');
-- ---------------------------------------------------------
select essai.refuse(
  $$insert into public.clients (id, nom) values
      ('11111111-1111-1111-1111-111111111111', 'L''enseigne qui achète')$$,
  'un compte de l''équipe devient client');

select essai.refuse(
  $$insert into public.profils (id, email, role) values
      ('44444444-4444-4444-4444-444444444444', 'awa@client.bj', 'moderateur')$$,
  'un compte client entre dans l''équipe');

-- ---------------------------------------------------------
select essai.titre('Le numéro vérifié ne se déclare pas');
-- ---------------------------------------------------------
select essai.devenir(:AWA::uuid);
set role authenticated;

select essai.refuse(
  $$update public.clients set tel_verifie = true where id = '44444444-4444-4444-4444-444444444444'$$,
  'le client se déclare vérifié lui-même');

select essai.refuse(
  $$update public.clients set nom = 'Awa', tel_verifie = true
     where id = '44444444-4444-4444-4444-444444444444'$$,
  'il glisse le drapeau au milieu d''une modification ordinaire');

-- Ce qu'il a le droit de faire, en revanche.
update public.clients set nom = 'Awa G.', adresse = 'Cotonou'
 where id = :AWA::uuid;
select essai.egal((select nom from public.clients where id = :AWA::uuid),
  'Awa G.', 'il modifie son nom et son adresse');

select essai.egal((select count(*)::int from public.clients), 1,
  'et il ne voit que son propre compte');

reset role;
select essai.personne();

-- La vérification par SMS, elle, a le droit — c'est la seule. Le drapeau
-- « bizzoo.verification » est LOCAL à la transaction : la vraie fonction
-- le pose et écrit dans le même appel, on la simule à l'identique.
begin;
select set_config('bizzoo.verification', 'oui', true);
update public.clients set tel_verifie = true where id = :AWA::uuid;
commit;
select essai.egal((select tel_verifie from public.clients where id = :AWA::uuid),
  true, 'la vérification par SMS pose le drapeau');

select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.refuse(
  $$update public.clients set tel = '97999999' where id = '44444444-4444-4444-4444-444444444444'$$,
  'un numéro vérifié se change ensuite');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Un numéro vérifié n''appartient qu''à un compte');
-- ---------------------------------------------------------
update public.clients set tel = '97111111' where id = :KOFI::uuid;

-- Le drapeau est posé DANS la transaction de l'essai, sinon le refus
-- viendrait du verrou et non de l'index — il passerait pour la mauvaise
-- raison, ce qui ne prouve rien.
begin;
select set_config('bizzoo.verification', 'oui', true);
select essai.refuse(
  $$update public.clients set tel_verifie = true
     where id = '55555555-5555-5555-5555-555555555555'$$,
  'un second compte revendique le même numéro vérifié');
commit;
update public.clients set tel = '97222222' where id = :KOFI::uuid;

-- ---------------------------------------------------------
select essai.titre('La commande porte son compte');
-- ---------------------------------------------------------
select essai.devenir(:AWA::uuid);
set role authenticated;
select (public.creer_commande(
  '{"tel":"97111111","nom":"Awa"}'::jsonb,
  '[{"produit_id":"prod_hp15","quantite":1}]'::jsonb) ->> 'id') as cmd_awa \gset
reset role;
select essai.personne();

select essai.egal((select client_id from public.commandes where id = :'cmd_awa'),
  :AWA::uuid, 'la commande d''un client porte son compte');

-- L'équipe, elle, ne commande pas pour elle-même : elle agirait avec les
-- droits d'une boutique sur une commande qui lui appartient.
select essai.devenir(:CHEF::uuid);
set role authenticated;
select (public.creer_commande(
  '{"tel":"97444444","nom":"Un chef"}'::jsonb,
  '[{"produit_id":"prod_hp15","quantite":1}]'::jsonb) ->> 'id') as cmd_chef \gset
reset role;
select essai.personne();
select essai.verifie(
  (select client_id from public.commandes where id = :'cmd_chef') is null,
  'une commande passée par l''équipe ne porte aucun compte client');

-- ---------------------------------------------------------
select essai.titre('Un client lit ses commandes, pas celles des autres');
-- ---------------------------------------------------------
select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.commandes), 1,
  'Awa voit sa commande');
select essai.egal((select count(*)::int from public.commande_lignes), 1,
  'et les lignes qui vont avec');
reset role;

select essai.devenir(:KOFI::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.commandes), 0,
  'Kofi ne voit pas celle d''Awa');
select essai.egal((select count(*)::int from public.commande_lignes), 0,
  'ni ses lignes');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('On ne réattribue pas une commande');
-- ---------------------------------------------------------
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.refuse(
  $$update public.commandes set client_id = '55555555-5555-5555-5555-555555555555'
     where id = $$ || quote_literal(:'cmd_awa'),
  'L''ENSEIGNE offre la commande d''Awa à Kofi');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Retrouver ses commandes d''avant le compte');
-- ---------------------------------------------------------
-- Une commande passée sans compte, avec le numéro d'Awa.
insert into public.commandes (id, client_tel, client_nom)
values ('cmd_avant_compte', '97111111', 'Awa');

-- Kofi, dont le numéro n'est pas vérifié, ne peut rien réclamer.
select essai.devenir(:KOFI::uuid);
set role authenticated;
select essai.refuse(
  $$select public.rattacher_mes_commandes()$$,
  'un numéro non vérifié réclame des commandes');
reset role;

-- Kofi tape le numéro d'Awa : sans vérification, cela ne lui donne rien.
select essai.devenir(:KOFI::uuid);
set role authenticated;
update public.clients set tel = '97111111' where id = :KOFI::uuid;
select essai.refuse(
  $$select public.rattacher_mes_commandes()$$,
  'il tape le numéro d''un autre et réclame ses commandes');
update public.clients set tel = '97222222' where id = :KOFI::uuid;
reset role;
select essai.personne();

select essai.verifie(
  (select client_id from public.commandes where id = 'cmd_avant_compte') is null,
  'la commande d''avant n''a changé de mains pour personne');

-- Awa, dont le numéro est vérifié, la retrouve.
select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.egal(public.rattacher_mes_commandes(), 1,
  'Awa retrouve sa commande d''avant le compte');
reset role;
select essai.personne();

select essai.egal((select client_id from public.commandes where id = 'cmd_avant_compte'),
  :AWA::uuid, 'et elle porte désormais son compte');

select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.egal(public.rattacher_mes_commandes(), 0,
  'rien à rattraper une seconde fois');
reset role;
select essai.personne();

-- Une commande passée par quelqu'un d'autre reste chez l'autre.
insert into public.commandes (id, client_tel, client_nom)
values ('cmd_dun_autre', '97555555', 'Un autre');
select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.egal(public.rattacher_mes_commandes(), 0,
  'et le numéro d''un autre ne lui rapporte rien');
reset role;
select essai.personne();
