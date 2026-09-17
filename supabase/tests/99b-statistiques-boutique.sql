-- =========================================================
-- Les chiffres d'une boutique : les siens, et rien d'autre.
--
-- L'enseigne a déjà « statistiques_ventes() », qui porte le prix
-- de vente, le taux de marge et le bénéfice de BIZZOO sur TOUTES
-- les boutiques. Une boutique n'a rien à y lire.
--
-- Mais une boutique a besoin de savoir ce qu'elle vend. D'où une
-- seconde fonction, et quatre choses à prouver :
--
--   1. CHACUNE NE VOIT QUE LA SIENNE. C'est le constat de ce
--      fichier. Deux boutiques, une même commande, et chacune
--      n'y lit que sa part ;
--   2. LA BOUTIQUE NE SE CHOISIT PAS. Il n'y a pas de paramètre
--      « boutique » : c'est toujours celle du compte connecté.
--      Un paramètre serait une invitation à viser la voisine ;
--   3. LES CHIFFRES DE L'ENSEIGNE NE SORTENT PAS. Ni le prix
--      payé par le client, ni le taux de marge, ni le bénéfice.
--      Pas « cachés à l'écran » : ABSENTS du résultat. Une
--      colonne qu'on oublie de retirer se lit avec n'importe
--      quel outil — on l'a déjà vu sur les lignes de commande ;
--   4. LA PORTE DE L'ENSEIGNE RESTE FERMÉE. Une boutique ne
--      passe pas par « statistiques_ventes() ».
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set EQUIPE   '''33333333-3333-3333-3333-333333333333'''
\set KOFI     '''55555555-5555-5555-5555-555555555555'''

select essai.titre('Le décor : une commande qui traverse deux boutiques');

-- Un article de chaque côté. Les chiffres sont choisis pour qu'aucune
-- somme ne puisse se confondre avec une autre.
insert into public.produits
  (id, boutique_id, nom, prix, categorie_id, stock, disponible)
values ('prod_stat_a', 'bou_informatique', 'Article de la maison', 12000,
        'cat_accessoires', 50, true),
       ('prod_stat_b', 'bou_essai_voisine', 'Article du voisin', 5000,
        'cat_essai_voisine', 50, true)
on conflict (id) do update
   set prix = excluded.prix, stock = 50, disponible = true;

insert into public.produits_prive (produit_id, prix_grossiste)
values ('prod_stat_a', 9000), ('prod_stat_b', 3000)
on conflict (produit_id) do update set prix_grossiste = excluded.prix_grossiste;

-- Kofi achète chez les deux d'un coup. Une seule commande, deux
-- boutiques : c'est le cas qui sépare vraiment les deux comptes.
select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97222222"}'::jsonb,
  '[{"produit_id":"prod_stat_a","quantite":3},
    {"produit_id":"prod_stat_b","quantite":2}]'::jsonb) ->> 'id' as vente \gset
reset role;
select essai.personne();

select public.marquer_payee(:'vente', 'TRX-STAT-1',
  (select total from public.commandes where id = :'vente')) as encaisse \gset
select essai.egal((select etat from public.commandes where id = :'vente'),
  'payee', 'la commande est encaissée');

-- ---------------------------------------------------------
select essai.titre('Chaque boutique ne lit que sa part');
-- ---------------------------------------------------------
select essai.devenir(:CHEF::uuid);
set role authenticated;

select essai.egal((select count(*)::int from public.statistiques_boutique()
                    where produit_id = 'prod_stat_a'), 1,
  'le chef voit son article');
select essai.egal((select quantite from public.statistiques_boutique()
                    where produit_id = 'prod_stat_a'), 3::bigint,
  'avec les trois unités vendues');
select essai.egal((select prix_bizzoo from public.statistiques_boutique()
                    where produit_id = 'prod_stat_a'), 9000::bigint,
  'au prix BIZZOO qu''il avait annoncé');
select essai.egal((select total_bizzoo from public.statistiques_boutique()
                    where produit_id = 'prod_stat_a'), 27000::bigint,
  'et le total qui lui revient : 3 × 9 000');
select essai.egal((select nb_ventes from public.statistiques_boutique()
                    where produit_id = 'prod_stat_a'), 1::bigint,
  'sur une seule commande');

-- LE CONSTAT. La même commande porte l'article du voisin : le chef ne
-- doit pas le voir, ni savoir qu'il existe.
select essai.egal((select count(*)::int from public.statistiques_boutique()
                    where produit_id = 'prod_stat_b'), 0,
  'et PAS l''article du voisin, pourtant dans la même commande');
reset role;
select essai.personne();

select essai.devenir(:EQUIPE::uuid);
set role authenticated;
select essai.egal((select total_bizzoo from public.statistiques_boutique()
                    where produit_id = 'prod_stat_b'), 6000::bigint,
  'le voisin voit sa part : 2 × 3 000');
select essai.egal((select count(*)::int from public.statistiques_boutique()
                    where produit_id = 'prod_stat_a'), 0,
  'et pas celle de la maison');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Les chiffres de l''enseigne ne sortent pas');
-- ---------------------------------------------------------
-- PAS « cachés à l'écran » : ABSENTS du résultat. Une colonne oubliée
-- se lit avec n'importe quel outil — c'est exactement ce qui était
-- arrivé aux lignes de commande, où l'acheteur lisait la marge.
select essai.verifie(
  (select pg_get_function_result(p.oid) not like '%taux_marge%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'statistiques_boutique'),
  'le taux de marge n''est pas dans le résultat');
select essai.verifie(
  (select pg_get_function_result(p.oid) not like '%benefice%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'statistiques_boutique'),
  'le bénéfice de l''enseigne non plus');
select essai.verifie(
  (select pg_get_function_result(p.oid) not like '%prix_vente%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'statistiques_boutique'),
  'ni le prix payé par le client');
select essai.verifie(
  (select pg_get_function_result(p.oid) not like '%total_vente%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'statistiques_boutique'),
  'ni son total');

-- Et la boutique ne se choisit pas : la fonction ne prend QUE des dates.
select essai.egal(
  (select p.pronargs::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'statistiques_boutique'), 2,
  'deux paramètres seulement — deux dates, pas de boutique');

-- ---------------------------------------------------------
select essai.titre('La porte de l''enseigne reste fermée');
-- ---------------------------------------------------------
select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.refuse($$select count(*) from public.statistiques_ventes()$$,
  'un chef de boutique lit les comptes de l''enseigne');
select essai.refuse(
  $$select count(*) from public.statistiques_ventes(null, null, 'bou_essai_voisine')$$,
  'ou ceux de la boutique voisine');
reset role;
select essai.personne();

-- L'enseigne, elle, passe — et voit les deux boutiques.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.verifie(
  (select count(*) > 0 from public.statistiques_ventes()
    where produit_id = 'prod_stat_b'),
  'l''enseigne voit l''article du voisin');
select essai.verifie(
  (select count(*) > 0 from public.statistiques_ventes()
    where produit_id = 'prod_stat_a'),
  'et celui de la maison');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Qui n''est pas de l''équipe n''a rien à lire');
-- ---------------------------------------------------------
-- Zéro ligne, pas une erreur : le même appel sert à tout le monde, et
-- l'écran n'a pas à savoir d'avance qui il sert.
select essai.devenir(:KOFI::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.statistiques_boutique()), 0,
  'un client connecté ne lit aucun chiffre');
reset role;
select essai.personne();

-- Un visiteur, lui, n'a même pas le droit d'appeler.
set role anon;
select essai.refuse($$select count(*) from public.statistiques_boutique()$$,
  'un visiteur appelle la fonction');
reset role;

-- ---------------------------------------------------------
select essai.titre('Les dates bornent, et la vente d''aujourd''hui y entre');
-- ---------------------------------------------------------
select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.verifie(
  (select count(*) > 0 from public.statistiques_boutique(current_date, current_date)
    where produit_id = 'prod_stat_a'),
  'la vente du jour entre dans la période du jour');
select essai.egal(
  (select count(*)::int from public.statistiques_boutique(current_date + 1, current_date + 30)
    where produit_id = 'prod_stat_a'), 0,
  'et pas dans celle de demain');
select essai.egal(
  (select count(*)::int from public.statistiques_boutique(current_date - 30, current_date - 1)
    where produit_id = 'prod_stat_a'), 0,
  'ni dans celle du mois dernier');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Ce qui n''est pas une vente n''en est pas une');
-- ---------------------------------------------------------
-- Une commande ouverte et jamais payée ne compte pas : sinon les
-- chiffres d'une boutique enfleraient de paniers abandonnés.
select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97222222"}'::jsonb,
  '[{"produit_id":"prod_stat_a","quantite":7}]'::jsonb) ->> 'id' as impayee \gset
reset role;
select essai.personne();

select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.egal((select quantite from public.statistiques_boutique()
                    where produit_id = 'prod_stat_a'), 3::bigint,
  'la commande impayée ne gonfle pas les chiffres');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Une ligne annulée sort des chiffres');
-- ---------------------------------------------------------
-- Le cas coûteux : la commande, elle, a bien été payée. Mais la boutique
-- n'a pas pu fournir et a annulé SA ligne. Si elle restait comptée, la
-- boutique lirait un chiffre d'affaires qu'elle n'a pas fait — et le
-- réclamerait. C'est la boutique elle-même qui annule : le banc passe
-- donc par son compte, pas par un « update » de faveur.
select essai.devenir(:CHEF::uuid);
set role authenticated;
update public.commande_lignes set etat = 'annulee'
 where commande_id = :'vente' and produit_id = 'prod_stat_a';
select essai.egal((select count(*)::int from public.statistiques_boutique()
                    where produit_id = 'prod_stat_a'), 0,
  'la ligne annulée ne compte plus comme une vente');
reset role;
select essai.personne();

-- Et l'annulation d'une boutique ne touche pas la ligne de la voisine.
select essai.devenir(:EQUIPE::uuid);
set role authenticated;
select essai.egal((select total_bizzoo from public.statistiques_boutique()
                    where produit_id = 'prod_stat_b'), 6000::bigint,
  'le voisin garde la sienne, intacte');
reset role;
select essai.personne();
