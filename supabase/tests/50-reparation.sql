-- =========================================================
-- Le fichier de réparation, éprouvé sur la panne qu'il répare.
--
-- C'est arrivé pour de vrai, en production : marge-bizzoo.sql a
-- posé la règle qui fige sur la ligne vendue le code du produit,
-- sans poser la colonne qui le reçoit. PostgreSQL ne relit le
-- corps d'une fonction qu'au moment de l'exécuter : le fichier
-- est passé sans un mot, et la boutique s'est arrêtée à la
-- commande suivante, sur « record "new" has no field "code" ».
-- Pas un franc n'a été débité — la commande n'existait même pas.
--
-- On refait donc ici la base du gérant TELLE QU'ELLE ÉTAIT :
-- la règle en place, la colonne absente. On vérifie qu'elle est
-- bien à l'arrêt, on y colle le fichier qu'on lui envoie, et on
-- vérifie qu'elle repart — et que les commandes déjà passées
-- retrouvent le code qu'elles auraient dû porter.
--
-- Ce fichier passe en dernier : il retire une colonne pour
-- reproduire la panne.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

select essai.titre('Le décor : une boutique, un produit, une vente');

insert into public.boutiques (id, nom, secteur, devise, actif, ordre, categorie_id)
values ('bou_essai_repar', 'BOUTIQUE À RÉPARER', 'Essai', 'FCFA', true, 95, 'cat_hightech')
on conflict (id) do nothing;

insert into public.produits
  (id, boutique_id, nom, prix, sous_categorie_id, stock, sur_commande, disponible)
values ('prod_essai_repar', 'bou_essai_repar', 'Article à coder', 2500,
        'sc_hightech_accessoires', 10, false, true)
on conflict (id) do nothing;

-- Une vente d'avant la panne : c'est elle qui devra retrouver son code.
set role anon;
select public.creer_commande(
  '{"tel":"97000011","nom":"Avant la panne"}'::jsonb,
  '[{"produit_id":"prod_essai_repar","quantite":2}]'::jsonb) ->> 'id'
  as cmd_avant \gset
reset role;

select p.code as code_produit from public.produits p
 where p.id = 'prod_essai_repar' \gset

select essai.egal(
  (select l.code from public.commande_lignes l where l.commande_id = :'cmd_avant'),
  :'code_produit', 'la vente d''avant porte bien le code du produit');

-- ---------------------------------------------------------
select essai.titre('La base du gérant : la règle sans la colonne');
-- ---------------------------------------------------------
-- Retirer la colonne ne dérange PERSONNE : ni la fonction qui l'écrit,
-- ni celle qui la garde. C'est tout le piège — rien ne proteste tant
-- que la première commande n'arrive pas.
alter table public.commande_lignes drop column code;

select essai.verifie(not exists (
  select 1 from information_schema.columns
   where table_schema = 'public' and table_name = 'commande_lignes'
     and column_name = 'code'),
  'la colonne a disparu, et la base ne dit rien');

set role anon;
select essai.refuse(
  $$select public.creer_commande('{"tel":"97000022"}'::jsonb,
      '[{"produit_id":"prod_essai_repar","quantite":1}]'::jsonb)$$,
  'une commande sur la base du gérant');
reset role;

-- Rien n'a été encaissé, et rien n'a été laissé derrière : une commande
-- à moitié écrite empoisonnerait les comptes aussi sûrement que la panne.
select essai.egal(
  (select count(*)::int from public.commandes where client_tel = '97000022'),
  0, 'la commande refusée n''a rien laissé derrière elle');

-- ---------------------------------------------------------
select essai.titre('Le fichier qu''on envoie au gérant');
-- ---------------------------------------------------------
\ir ../reparer-code-ligne.sql

select essai.verifie(exists (
  select 1 from information_schema.columns
   where table_schema = 'public' and table_name = 'commande_lignes'
     and column_name = 'code'),
  'la colonne est de retour');

-- Un code ne bouge jamais : celui du produit aujourd'hui est celui qu'il
-- portait le jour de la vente. La commande d'avant retrouve donc le sien,
-- exactement.
select essai.egal(
  (select l.code from public.commande_lignes l where l.commande_id = :'cmd_avant'),
  :'code_produit', 'la vente d''avant a retrouvé son code');

-- Et le verrou est retourné à sa place : le fichier l'écarte le temps du
-- rattrapage. L'oublier ouvert laisserait réécrire ce qui a été vendu.
select essai.refuse(
  $$update public.commande_lignes set code = '000000'
     where commande_id = $$ || quote_literal(:'cmd_avant'),
  'réécrire le code d''une ligne vendue');

-- ---------------------------------------------------------
select essai.titre('La boutique repart');
-- ---------------------------------------------------------
set role anon;
select public.creer_commande(
  '{"tel":"97000033","nom":"Après la réparation"}'::jsonb,
  '[{"produit_id":"prod_essai_repar","quantite":1}]'::jsonb) ->> 'id'
  as cmd_apres \gset
reset role;

select essai.egal(
  (select l.code from public.commande_lignes l where l.commande_id = :'cmd_apres'),
  :'code_produit', 'la nouvelle vente porte le code du produit');

select essai.egal(
  (select c.total from public.commandes c where c.id = :'cmd_apres'),
  2500, 'et son total est celui du catalogue');
