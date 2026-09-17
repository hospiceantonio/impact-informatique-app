-- =========================================================
-- Le SAV : la boutique d'abord, BIZZOO en recours.
--
-- Cette promesse ne tient que par ce qu'elle refuse. Si l'on
-- peut appeler l'enseigne à la seconde même, « la boutique
-- d'abord » n'est qu'une phrase : tout le monde escalade, et
-- l'enseigne fait le travail de ses boutiques.
--
-- Quatre portes, et on les force toutes :
--
--   1. PAS DE RÉCLAMATION SANS COMMANDE PAYÉE, ET SIENNE ;
--   2. PAS D'ESCALADE IMMÉDIATE. Ni avant que la boutique ait
--      répondu, ni avant le délai qu'on lui laisse. C'est LE
--      constat de ce fichier ;
--   3. LA BOUTIQUE NE CLÔT PAS ce qui la met en cause ;
--   4. L'ENSEIGNE NE TRANCHE QUE CE QUI LUI EST REMONTÉ — lui
--      retirer le dossier des mains sans qu'on le lui demande
--      n'est pas un recours, c'est une mise sous tutelle.
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

select essai.titre('Le décor : une commande payée, une qui ne l''est pas');

insert into public.produits
  (id, boutique_id, nom, prix, categorie_id, stock, disponible)
values ('prod_sav', 'bou_informatique', 'Article à réclamer', 15000,
        'cat_accessoires', 50, true)
on conflict (id) do update set prix = 15000, stock = 50;

select essai.devenir(:AWA::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Awa","tel":"97111111"}'::jsonb,
  '[{"produit_id":"prod_sav","quantite":1}]'::jsonb) ->> 'id' as payee \gset
select public.creer_commande('{"nom":"Awa","tel":"97111111"}'::jsonb,
  '[{"produit_id":"prod_sav","quantite":1}]'::jsonb) ->> 'id' as impayee \gset
reset role;
select essai.personne();
select public.marquer_payee(:'payee', 'TRX-SAV-1',
  (select total from public.commandes where id = :'payee')) as encaisse \gset

select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97222222"}'::jsonb,
  '[{"produit_id":"prod_sav","quantite":1}]'::jsonb) ->> 'id' as celle_de_kofi \gset
reset role;
select essai.personne();
select public.marquer_payee(:'celle_de_kofi', 'TRX-SAV-2',
  (select total from public.commandes where id = :'celle_de_kofi')) as encaisse2 \gset

select essai.egal((select etat from public.commandes where id = :'payee'), 'payee',
  'la commande d''Awa est payée');
select essai.egal((select etat from public.commandes where id = :'impayee'), 'a_payer',
  'son autre commande ne l''est pas');

-- ---------------------------------------------------------
select essai.titre('On ne réclame que sur sa commande, et payée');
-- ---------------------------------------------------------
select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.refuse(
  format($$select public.ouvrir_reclamation(%L, null, 'non_recu', 'Rien reçu')$$, :'impayee'),
  'elle réclame sur une commande jamais réglée');
select essai.refuse(
  format($$select public.ouvrir_reclamation(%L, null, 'non_recu', 'Rien reçu')$$, :'celle_de_kofi'),
  'elle réclame sur la commande de Kofi');
select essai.refuse(
  format($$select public.ouvrir_reclamation(%L, 'prod_hp15', 'abime', 'Cassé')$$, :'payee'),
  'elle réclame sur un article absent de sa commande');
reset role;
select essai.personne();

set role anon;
select essai.refuse(
  format($$select public.ouvrir_reclamation(%L, null, 'non_recu', 'Rien')$$, :'payee'),
  'un visiteur ouvre une réclamation');
reset role;

select essai.egal((select count(*)::int from public.reclamations), 0,
  'aucune réclamation n''a été ouverte');

-- ---------------------------------------------------------
select essai.titre('Sur sa commande payée, elle réclame');
-- ---------------------------------------------------------
select essai.devenir(:AWA::uuid);
set role authenticated;
select public.ouvrir_reclamation(:'payee', 'prod_sav', 'abime',
  'L''écran est fendu à la livraison.') ->> 'id' as sav \gset
reset role;
select essai.personne();

select essai.egal((select etat from public.reclamations where id = :'sav'), 'ouverte',
  'elle est ouverte, et attend la boutique');
select essai.egal((select boutique_id from public.reclamations where id = :'sav'),
  'bou_informatique', 'et la boutique vient de la COMMANDE, pas de la requête');
select essai.egal((select count(*)::int from public.reclamation_messages
                    where reclamation_id = :'sav'), 1,
  'son message ouvre le fil');
select essai.egal((select auteur_role from public.reclamation_messages
                    where reclamation_id = :'sav'), 'client',
  'et le rôle est écrit par la base, pas envoyé par le téléphone');

-- ---------------------------------------------------------
select essai.titre('BIZZOO n''entre pas avant la boutique');
-- ---------------------------------------------------------
-- LE CONSTAT DE CE FICHIER. La réclamation vient d'être ouverte : la
-- boutique n'a pas encore eu le temps de la lire.
select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.egal(public.recours_possible(:'sav'), false,
  'le recours n''est pas encore ouvert');
select essai.refuse(
  format($$select public.escalader_reclamation(%L, 'Je veux BIZZOO')$$, :'sav'),
  'elle appelle BIZZOO à la seconde même');
reset role;
select essai.personne();
select essai.egal((select etat from public.reclamations where id = :'sav'), 'ouverte',
  'la réclamation est restée chez la boutique');

-- ---------------------------------------------------------
select essai.titre('La boutique répond, et le recours s''ouvre');
-- ---------------------------------------------------------
-- Une boutique VOISINE ne répond pas pour celle qui est mise en cause.
insert into public.boutiques (id, nom, secteur, actif, ordre)
values ('bou_voisine', 'Boutique voisine', 'Cosmétiques', true, 9)
on conflict (id) do nothing;
insert into auth.users (id, email) values
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'chef-voisine2@bizzoo.bj')
on conflict do nothing;
insert into public.profils (id, email, role, actif, boutique_id)
values ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'chef-voisine2@bizzoo.bj',
        'administrateur', true, 'bou_voisine')
on conflict (id) do update set boutique_id = 'bou_voisine', actif = true;

select essai.devenir('dddddddd-dddd-dddd-dddd-dddddddddddd'::uuid);
set role authenticated;
select essai.refuse(
  format($$select public.repondre_reclamation(%L, 'Ce n''est pas nous')$$, :'sav'),
  'une boutique voisine répond à la place de celle qui est visée');
select essai.egal((select count(*)::int from public.reclamations where id = :'sav'), 0,
  'et elle ne lit même pas la réclamation');
reset role;
select essai.personne();

select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.reclamations where id = :'sav'), 1,
  'la boutique visée, elle, la voit');
select essai.egal(
  public.repondre_reclamation(:'sav', 'Passez en boutique, on échange l''article.'),
  'boutique', 'et elle répond');
reset role;
select essai.personne();

select essai.egal((select etat from public.reclamations where id = :'sav'), 'repondue',
  'la réclamation passe à « répondue »');
select essai.verifie((select repondu_le is not null from public.reclamations where id = :'sav'),
  'et la date de réponse est posée');

select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.egal(public.recours_possible(:'sav'), true,
  'MAINTENANT le recours est ouvert : la boutique a répondu');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Le silence de la boutique ouvre aussi le recours');
-- ---------------------------------------------------------
-- L'autre porte. Sans elle, un client resté sans nouvelle serait
-- prisonnier de ce silence.
select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.ouvrir_reclamation(:'celle_de_kofi', null, 'non_recu',
  'Jamais livré.') ->> 'id' as sav_muet \gset
select essai.egal(public.recours_possible(:'sav_muet'), false,
  'tout de suite après l''ouverture : non');
reset role;
select essai.personne();

-- On recule l'ouverture de trois jours : la boutique n'a rien dit.
update public.reclamations set cree_le = now() - interval '3 days' where id = :'sav_muet';

select essai.devenir(:KOFI::uuid);
set role authenticated;
select essai.egal(public.recours_possible(:'sav_muet'), true,
  'passé le délai sans réponse : oui');
select essai.egal(public.escalader_reclamation(:'sav_muet', 'Aucune nouvelle depuis trois jours'),
  true, 'il appelle BIZZOO');
select essai.refuse(
  format($$select public.escalader_reclamation(%L, 'encore')$$, :'sav_muet'),
  'et il ne la saisit pas deux fois');
reset role;
select essai.personne();

select essai.egal((select etat from public.reclamations where id = :'sav_muet'), 'escaladee',
  'la réclamation est remontée');
select essai.verifie(
  (select escalade_le is not null from public.reclamations where id = :'sav_muet'),
  'avec la date, et le motif');

-- Et personne d'autre que le client n'appelle le recours.
select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.refuse(
  format($$select public.escalader_reclamation(%L, 'On préfère que BIZZOO tranche')$$, :'sav'),
  'la boutique se débarrasse du dossier sur l''enseigne');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('La boutique ne clôt pas ce qui la met en cause');
-- ---------------------------------------------------------
select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.refuse(
  format($$select public.clore_reclamation(%L)$$, :'sav'),
  'la boutique déclare le problème réglé');
select essai.refuse(
  format($$update public.reclamations set etat = 'resolue' where id = %L$$, :'sav'),
  'ou l''écrit directement dans la table');
select essai.refuse(
  format($$delete from public.reclamations where id = %L$$, :'sav'),
  'ou la fait disparaître');
reset role;
select essai.personne();
select essai.egal((select etat from public.reclamations where id = :'sav'), 'repondue',
  'la réclamation tient');

-- Le client, lui, en a le droit.
select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.egal(public.clore_reclamation(:'sav'), true,
  'le client dit que c''est réglé');
select essai.refuse(
  format($$select public.repondre_reclamation(%L, 'Encore une chose')$$, :'sav'),
  'et une réclamation close ne se rouvre pas par un message');
reset role;
select essai.personne();
select essai.egal((select etat from public.reclamations where id = :'sav'), 'resolue',
  'elle est résolue');

-- ---------------------------------------------------------
select essai.titre('L''enseigne tranche — ce qui lui est remonté, et cela seul');
-- ---------------------------------------------------------
select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.refuse(
  format($$select public.trancher_reclamation(%L, 'Je me donne raison')$$, :'sav_muet'),
  'une cliente tranche son propre recours');
reset role;
select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.refuse(
  format($$select public.trancher_reclamation(%L, 'On a raison')$$, :'sav_muet'),
  'une boutique tranche le recours qui la vise');
reset role;
select essai.personne();

-- Une réclamation que la boutique traite encore n'est pas un recours.
select essai.devenir(:AWA::uuid);
set role authenticated;
select public.ouvrir_reclamation(:'payee', null, 'incomplet', 'Il manque le chargeur.')
  ->> 'id' as sav_en_cours \gset
reset role;
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.refuse(
  format($$select public.trancher_reclamation(%L, 'Je tranche')$$, :'sav_en_cours'),
  'l''enseigne tranche un dossier que la boutique traite encore');
select essai.refuse(
  format($$select public.trancher_reclamation(%L, '')$$, :'sav_muet'),
  'elle tranche sans rien dire');
select essai.egal(
  public.trancher_reclamation(:'sav_muet',
    'Remboursement intégral à la charge de la boutique.'),
  true, 'mais elle tranche le recours qu''on lui a remonté');
reset role;
select essai.personne();

select essai.egal((select etat from public.reclamations where id = :'sav_muet'), 'tranchee',
  'la réclamation est tranchée');
select essai.verifie(
  (select decide_par <> '' from public.reclamations where id = :'sav_muet'),
  'la décision est signée');
select essai.verifie(
  (select count(*) from public.reclamation_messages
    where reclamation_id = :'sav_muet' and auteur_role = 'enseigne') = 1,
  'et elle s''inscrit dans le fil, que les deux parties liront');

-- ---------------------------------------------------------
select essai.titre('Chacun ne lit que ce qui le concerne');
-- ---------------------------------------------------------
select essai.devenir(:KOFI::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.reclamations where id = :'sav'), 0,
  'Kofi ne voit pas la réclamation d''Awa');
select essai.egal((select count(*)::int from public.reclamation_messages
                    where reclamation_id = :'sav'), 0,
  'ni les messages, même en devinant l''identifiant');
select essai.egal((select count(*)::int from public.reclamations where id = :'sav_muet'), 1,
  'mais il voit la sienne');
reset role;
select essai.personne();

-- La table entière est fermée à « anon » : il ne reçoit pas zéro ligne,
-- il reçoit un refus. Un SAV se lit connecté, ou pas du tout.
set role anon;
select essai.refuse($$select count(*) from public.reclamations$$,
  'un visiteur lit les réclamations');
select essai.refuse($$select count(*) from public.reclamation_messages$$,
  'un visiteur lit les messages');
reset role;

select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.verifie((select count(*) from public.reclamations) >= 3,
  'l''enseigne voit tout : c''est elle le recours');
reset role;
select essai.personne();
