-- =========================================================
-- Mes commandes : ce que le client lit de SES commandes.
--
-- Jusqu'ici l'historique vivait dans le téléphone, et la table
-- des commandes était fermée à tout ce qui n'était pas
-- l'équipe. Depuis que le client se connecte, il en lit une
-- partie — la sienne. Cela change la question posée à chaque
-- colonne : « l'équipe peut-elle la voir ? » devient « et
-- l'acheteur ? ».
--
-- Deux d'entre elles n'ont rien à faire sous ses yeux :
--
--   « prix_bizzoo » — ce que la boutique a touché, c'est-à-dire
--                     son PRIX D'ACHAT. Le montrer à l'acheteur,
--                     c'est lui montrer la marge de la boutique
--                     sur chaque article qu'il a payé ;
--   « taux_marge »  — celle de l'enseigne, pour la même raison.
--
-- Une règle RLS ne suffit pas à les fermer : elle décide des
-- LIGNES qu'on voit, pas des COLONNES. Il faut des droits par
-- colonne, et c'est ce qu'on force ici.
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

select essai.titre('Le décor : une commande d''Awa, à marge connue');

-- Awa a son compte et son numéro vérifié depuis le banc 60.
insert into public.produits
  (id, boutique_id, nom, prix, categorie_id, stock, disponible)
values ('prod_histo', 'bou_informatique', 'Article d''historique', 12000,
        'cat_accessoires', 10, true)
on conflict (id) do update set prix = 12000, stock = 10;
insert into public.produits_prive (produit_id, prix_grossiste)
values ('prod_histo', 9000)
on conflict (produit_id) do update set prix_grossiste = 9000;

select essai.devenir(:AWA::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Awa","tel":"97111111"}'::jsonb,
  '[{"produit_id":"prod_histo","quantite":2}]'::jsonb) ->> 'id' as mienne \gset
reset role;
select essai.personne();

select essai.egal((select client_id from public.commandes where id = :'mienne'),
  :AWA::uuid, 'la commande porte son compte');
select essai.egal((select prix_bizzoo from public.commande_lignes
                    where commande_id = :'mienne'), 9000,
  'et la ligne porte le prix BIZZOO, comme toujours');

-- ---------------------------------------------------------
select essai.titre('Elle lit ses commandes, et la forme que l''écran demande');
-- ---------------------------------------------------------
select essai.devenir(:AWA::uuid);
set role authenticated;

select essai.verifie((select count(*) from public.commandes) >= 1,
  'elle voit ses commandes');
select essai.egal((select count(*)::int from public.commandes
                    where id = :'mienne'), 1,
  'dont celle qu''on vient de passer');

-- Exactement ce que l'application demande : la commande et ses lignes
-- d'un seul coup. C'est cette requête-là qui doit passer, pas une
-- version simplifiée qui prouverait autre chose.
select essai.egal(
  (select count(*)::int from public.commande_lignes l
    join public.commandes c on c.id = l.commande_id
   where c.id = :'mienne'), 1,
  'avec les lignes qui vont avec');
select essai.egal((select l.nom from public.commande_lignes l
                    where l.commande_id = :'mienne'), 'Article d''historique',
  'le nom du produit, figé le jour de la vente');
select essai.egal((select l.prix from public.commande_lignes l
                    where l.commande_id = :'mienne'), 12000,
  'et le prix qu''elle a payé');

-- ---------------------------------------------------------
select essai.titre('Mais pas ce que la boutique a payé');
-- ---------------------------------------------------------
-- LE POINT DE CE FICHIER. Ces deux colonnes disent la marge de la
-- boutique sur chaque article que l'acheteur a acheté. Une règle de
-- lecture sur les LIGNES ne les ferme pas : il faut des droits par
-- COLONNE.
select essai.refuse(
  $$select prix_bizzoo from public.commande_lignes limit 1$$,
  'une acheteuse lit le prix d''achat de la boutique');
select essai.refuse(
  $$select taux_marge from public.commande_lignes limit 1$$,
  'elle lit la marge de l''enseigne');
select essai.refuse(
  $$select * from public.commande_lignes limit 1$$,
  'ou tout prendre d''un coup, sans nommer les colonnes');

reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('L''enseigne, elle, garde ses chiffres');
-- ---------------------------------------------------------
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.verifie(
  (select count(*) from public.statistiques_ventes(null, null, null)) >= 1,
  'ses statistiques de ventes répondent');
select essai.verifie(
  (select bool_or(prix_bizzoo > 0) from public.statistiques_ventes(null, null, null)),
  'et portent bien le prix BIZZOO');
reset role;
select essai.personne();

-- Et la boutique suit ses commandes comme avant : le prix payé, les
-- coordonnées, l'état. Ce qu'elle préparait hier, elle le prépare
-- encore.
select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.verifie((select count(*) from public.commande_lignes) >= 1,
  'la boutique voit ses lignes à préparer');
select essai.verifie(
  (select count(*) from public.commande_lignes where prix > 0) >= 1,
  'avec le prix payé');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Et toujours rien des commandes des autres');
-- ---------------------------------------------------------
select essai.devenir(:KOFI::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.commandes
                    where id = :'mienne'), 0,
  'Kofi ne voit pas la commande d''Awa');
select essai.egal((select count(*)::int from public.commande_lignes
                    where commande_id = :'mienne'), 0,
  'ni ses lignes, même en en devinant l''identifiant');
reset role;
select essai.personne();

-- Un visiteur non connecté ne lit toujours rien du tout.
set role anon;
select essai.egal((select count(*)::int from public.commandes), 0,
  'un visiteur ne lit aucune commande');
select essai.refuse($$select prix_bizzoo from public.commande_lignes limit 1$$,
  'ni le prix d''achat d''une boutique');
reset role;
