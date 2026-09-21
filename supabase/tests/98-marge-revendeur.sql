-- =========================================================
-- La marge revendeur : ce que rapporte une vente à un revendeur.
--
-- Vendre au prix BIZZOO exact ne rapportait rien à l'enseigne,
-- et montrait au revendeur, article par article, ce que la
-- boutique touche. La marge répare les deux — à condition que
-- le calcul tienne debout dans tous les cas, et c'est ce que ce
-- fichier vérifie.
--
-- Cinq choses à prouver :
--
--   1. LES DEUX MODES CALCULENT CE QU'ILS ANNONCENT. « bizzoo »
--      ajoute au prix BIZZOO, « public » retranche au prix
--      public. Un mode qui mentirait d'un franc mentirait sur
--      chaque ligne de chaque commande ;
--   2. JAMAIS SOUS LE PRIX BIZZOO. C'est la borne qui protège la
--      boutique. Une remise de 60 % sur un article dont la marge
--      est de 20 % la ferait vendre à perte, et personne ne s'en
--      apercevrait avant les comptes ;
--   3. JAMAIS AU-DESSUS DU PRIX PUBLIC. C'est la borne qui rend
--      le compte revendeur crédible : payer plus cher qu'un
--      client de passage n'a aucun sens ;
--   4. LE TAUX D'UN PRODUIT L'EMPORTE sur celui de la boutique,
--      et un produit sans taux propre suit la boutique ;
--   5. L'ÉCRAN ET LA CAISSE DISENT LE MÊME PRIX. « mes_prix() »
--      affiche, « ligne_a_l_ecriture » facture. S'ils divergent,
--      le client voit un montant et en paie un autre — et c'est
--      le genre de faute qu'on ne découvre qu'en litige.
--
-- Et une sixième, qui n'est pas du calcul : LE TAUX NE SE FIXE
-- PAS DEPUIS UNE BOUTIQUE. Une boutique qui pourrait le ramener
-- à zéro revendrait au prix BIZZOO, et tout ceci n'aurait servi
-- à rien.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set AWA      '''44444444-4444-4444-4444-444444444444'''

select essai.titre('Le calcul, mode « bizzoo » : prix BIZZOO + N %');

-- On éprouve la règle seule, sans passer par une commande : c'est une
-- fonction pure, on peut lui poser toutes les questions d'un coup.
select essai.egal(public.prix_revendeur(10000, 8000, 10, 'bizzoo'), 8800,
  '8 000 + 10 %');
select essai.egal(public.prix_revendeur(10000, 8000, 0, 'bizzoo'), 8000,
  'sans marge, le prix BIZZOO nu');
select essai.egal(public.prix_revendeur(10000, 8000, 25, 'bizzoo'), 10000,
  '25 % dépasserait le prix public : on s''arrête au prix public');

-- L'arrondi : vers le HAUT, pour que la marge ne soit jamais rabotée.
select essai.egal(public.prix_revendeur(10000, 777, 10, 'bizzoo'), 855,
  '777 + 10 % = 854,7 → 855, arrondi vers le haut');
select essai.egal(public.prix_revendeur(10000, 1000, 10, 'bizzoo'), 1100,
  'un compte rond reste rond');

-- ---------------------------------------------------------
select essai.titre('Le calcul, mode « public » : prix public − N %');
-- ---------------------------------------------------------
select essai.egal(public.prix_revendeur(10000, 8000, 10, 'public'), 9000,
  '10 000 − 10 %');
select essai.egal(public.prix_revendeur(10000, 8000, 0, 'public'), 10000,
  'sans remise, le prix public');
select essai.egal(public.prix_revendeur(10000, 8000, 60, 'public'), 8000,
  '60 % passerait sous le prix BIZZOO : on s''arrête au prix BIZZOO');

-- L'arrondi : vers le BAS, pour que la remise annoncée soit tenue.
select essai.egal(public.prix_revendeur(9999, 1000, 10, 'public'), 8995,
  '9 999 − 10 % = 8 999,1 → 8 995, arrondi vers le bas');

-- ---------------------------------------------------------
select essai.titre('Les deux bornes tiennent, quel que soit le taux');
-- ---------------------------------------------------------
-- Un taux aberrant est une faute de saisie, pas une intention : on le
-- ramène dans ses bornes plutôt que de refuser la vente.
select essai.egal(public.prix_revendeur(10000, 8000, 500, 'bizzoo'), 10000,
  'un taux de 500 % ne dépasse pas le prix public');
select essai.egal(public.prix_revendeur(10000, 8000, 500, 'public'), 8000,
  'ni ne descend sous le prix BIZZOO');
select essai.egal(public.prix_revendeur(10000, 8000, -50, 'bizzoo'), 8000,
  'un taux négatif vaut zéro');
select essai.egal(public.prix_revendeur(10000, 8000, null, 'bizzoo'), 8000,
  'un taux absent vaut zéro');

-- Le prix BIZZOO à zéro : la boutique ne l'a pas renseigné. Il n'y a
-- rien à calculer, et surtout rien à donner.
select essai.egal(public.prix_revendeur(5000, 0, 10, 'bizzoo'), 5000,
  'sans prix BIZZOO, le prix public — et non zéro');
select essai.egal(public.prix_revendeur(5000, 0, 90, 'public'), 5000,
  'même avec une remise de 90 %');

-- La fin de série : le prix public est DÉJÀ sous le prix BIZZOO. Les
-- deux bornes se contredisent, et c'est le plafond qui l'emporte — la
-- perte est déjà consentie en vitrine.
select essai.egal(public.prix_revendeur(7000, 8000, 10, 'bizzoo'), 7000,
  'une fin de série soldée : le revendeur paie le prix public');
select essai.egal(public.prix_revendeur(7000, 8000, 10, 'public'), 7000,
  'dans les deux modes');

-- Un mode inconnu ne fait pas tomber la vente : on retombe sur
-- « bizzoo », le mode par défaut.
select essai.egal(public.prix_revendeur(10000, 8000, 10, 'n''importe quoi'),
  public.prix_revendeur(10000, 8000, 10, 'bizzoo'),
  'un mode inconnu se comporte comme « bizzoo »');

-- ---------------------------------------------------------
select essai.titre('Le décor : une boutique, deux articles, une revendeuse');
-- ---------------------------------------------------------
insert into public.produits
  (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_rev_a', 'bou_informatique', 'Article revendeur A', 20000,
        'sc_hightech_accessoires', 50, true),
       ('prod_rev_b', 'bou_informatique', 'Article revendeur B', 20000,
        'sc_hightech_accessoires', 50, true)
on conflict (id) do update set prix = 20000, stock = 50, disponible = true;

-- A suit la boutique ; B a son taux à lui.
insert into public.produits_prive (produit_id, prix_grossiste, taux_revendeur)
values ('prod_rev_a', 10000, null),
       ('prod_rev_b', 10000, 50)
on conflict (produit_id) do update
   set prix_grossiste = excluded.prix_grossiste,
       taux_revendeur = excluded.taux_revendeur;

select essai.egal((select taux_revendeur from public.boutiques
                    where id = 'bou_informatique'), 10::numeric,
  'la boutique part à 10 %');
select essai.egal((select revendeur_mode from public.boutiques
                    where id = 'bou_informatique'), 'bizzoo',
  'et en mode « bizzoo »');

-- Awa a été validée puis REFUSÉE à la fin du banc précédent. On la
-- revalide — par la porte prévue, celle de l'enseigne : le verrou de
-- « clients » refuse qu'on écrive « revendeur_etat » directement, et il
-- a bien raison de le faire.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.egal(public.valider_revendeur(:AWA::uuid, true, ''), 'validee',
  'BIZZOO revalide Awa');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Le taux du produit l''emporte sur celui de la boutique');
-- ---------------------------------------------------------
select essai.devenir(:AWA::uuid);
set role authenticated;

select essai.egal(
  (select prix::int from public.mes_prix() where produit_id = 'prod_rev_a'),
  11000, 'A suit la boutique : 10 000 + 10 %');
select essai.egal(
  (select prix::int from public.mes_prix() where produit_id = 'prod_rev_b'),
  15000, 'B a son taux à lui : 10 000 + 50 %');

-- Et ce qu'elle ne voit toujours pas : le prix BIZZOO lui-même.
select essai.egal((select count(*)::int from public.produits_prive), 0,
  'elle ne lit pas la table des prix BIZZOO');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('L''écran et la caisse disent le même prix');
-- ---------------------------------------------------------
-- C'est LE constat de ce fichier. Deux règles qui divergeraient d'un
-- franc feraient payer au client autre chose que ce qu'il a lu.
select essai.devenir(:AWA::uuid);
set role authenticated;
select prix::int as affiche_a from public.mes_prix() where produit_id = 'prod_rev_a' \gset
select prix::int as affiche_b from public.mes_prix() where produit_id = 'prod_rev_b' \gset
select public.creer_commande('{"nom":"Awa","tel":"97111111"}'::jsonb,
  '[{"produit_id":"prod_rev_a","quantite":1},
    {"produit_id":"prod_rev_b","quantite":1}]'::jsonb) ->> 'id' as achat \gset
reset role;
select essai.personne();

select essai.egal((select prix from public.commande_lignes
                    where commande_id = :'achat' and produit_id = 'prod_rev_a'),
  :affiche_a, 'A : facturé au prix affiché');
select essai.egal((select prix from public.commande_lignes
                    where commande_id = :'achat' and produit_id = 'prod_rev_b'),
  :affiche_b, 'B : facturé au prix affiché');
select essai.egal((select total from public.commandes where id = :'achat'),
  (:affiche_a + :affiche_b)::int, 'et le total est la somme des deux');

-- Ce que la boutique touche n'a pas bougé : la marge est celle de
-- l'enseigne, elle ne se prend pas sur le dos de la boutique.
select essai.egal((select prix_bizzoo from public.commande_lignes
                    where commande_id = :'achat' and produit_id = 'prod_rev_a'),
  10000, 'la boutique touche toujours son prix BIZZOO');
select essai.verifie((select bool_and(prix > prix_bizzoo) from public.commande_lignes
                       where commande_id = :'achat'),
  'et l''enseigne gagne sur chaque ligne');

-- ---------------------------------------------------------
select essai.titre('Un client ordinaire ne voit rien de tout cela');
-- ---------------------------------------------------------
select essai.personne();
set role anon;
select public.creer_commande('{"nom":"Passant","tel":"97444444"}'::jsonb,
  '[{"produit_id":"prod_rev_a","quantite":1}]'::jsonb) ->> 'id' as passant \gset
reset role;
select essai.egal((select prix from public.commande_lignes where commande_id = :'passant'),
  20000, 'il paie le prix public, la marge revendeur ne le concerne pas');

-- ---------------------------------------------------------
select essai.titre('Le taux ne se fixe pas depuis une boutique');
-- ---------------------------------------------------------
-- Si une boutique pouvait le ramener à zéro, elle revendrait au prix
-- BIZZOO et tout ce fichier n'aurait servi à rien.
select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.refuse(
  $$update public.boutiques set taux_revendeur = 0 where id = 'bou_informatique'$$,
  'le chef d''une boutique ramène sa marge revendeur à zéro');
select essai.refuse(
  $$update public.boutiques set revendeur_mode = 'public' where id = 'bou_informatique'$$,
  'ou change de mode de calcul');
reset role;
select essai.personne();

select essai.egal((select taux_revendeur from public.boutiques
                    where id = 'bou_informatique'), 10::numeric,
  'le taux n''a pas bougé');

-- L'enseigne, elle, décide. C'est bien à elle que revient cette marge.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
update public.boutiques
   set revendeur_mode = 'public', taux_revendeur = 20
 where id = 'bou_informatique';
reset role;
select essai.personne();
select essai.egal((select revendeur_mode from public.boutiques
                    where id = 'bou_informatique'), 'public',
  'l''enseigne change le mode');

-- Et le changement se voit tout de suite à l'écran comme à la caisse.
select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.egal(
  (select prix::int from public.mes_prix() where produit_id = 'prod_rev_a'),
  16000, 'A passe à 20 000 − 20 %');
reset role;
select essai.personne();

-- Mais une commande DÉJÀ PASSÉE ne se réécrit pas : ce qui a été vendu
-- est vendu, au prix du jour de la vente.
select essai.egal((select prix from public.commande_lignes
                    where commande_id = :'achat' and produit_id = 'prod_rev_a'),
  :affiche_a, 'la commande d''avant garde son prix');

-- Le décor est rendu tel qu'on l'a trouvé, pour les fichiers suivants.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
update public.boutiques
   set revendeur_mode = 'bizzoo', taux_revendeur = 10
 where id = 'bou_informatique';
reset role;
select essai.personne();
select essai.egal((select revendeur_mode from public.boutiques
                    where id = 'bou_informatique'), 'bizzoo',
  'le banc se termine comme il a commencé');
