-- =========================================================
-- Le livreur : ce qu'il porte, et ce qu'il ne voit pas.
--
-- Un quatrième rang dans l'équipe, et le plus délicat : il a
-- un profil, donc la base lui répond — mais il ne TIENT rien.
--
-- LE PIÈGE PRINCIPAL. « est_equipe() » disait « n'importe quel
-- profil actif ». Le jour où le rang livreur arrive, cette
-- seule phrase lui ouvrirait d'un coup les commandes de toute
-- la boutique, le journal, les chiffres de vente et le dépôt
-- de photos. Rien de tout cela n'est son travail.
--
-- LE SECOND PIÈGE. « peut_modifier_produits » vaut VRAI par
-- défaut sur tout profil : un livreur fraîchement créé aurait
-- pu modifier le catalogue, parce que la colonne lui disait
-- oui.
--
-- Cinq choses à prouver :
--
--   1. UN LIVREUR N'EST PAS L'ÉQUIPE : ni catalogue, ni
--      commandes, ni chiffres ;
--   2. IL NE VOIT AUCUN MONTANT. Pas le prix BIZZOO, pas le
--      prix payé. Une règle RLS décide des lignes, jamais des
--      colonnes — seule une fonction peut les choisir ;
--   3. IL NE VOIT QUE SES COURSES, pas celles d'un collègue ;
--   4. LA BOUTIQUE CONFIE, et seulement à SON livreur ;
--   5. IL AVANCE DANS LE BON SENS, et sur deux étapes.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set KOFI     '''55555555-5555-5555-5555-555555555555'''
\set PORTEUR  '''cccccccc-1111-1111-1111-111111111111'''
\set AUTRE    '''cccccccc-2222-2222-2222-222222222222'''
\set VOISIN   '''cccccccc-3333-3333-3333-333333333333'''

select essai.titre('Le décor : deux livreurs ici, un chez la voisine');

insert into auth.users (id, email) values
  (:PORTEUR::uuid, 'porteur@impact.bj'),
  (:AUTRE::uuid,   'autre@impact.bj'),
  (:VOISIN::uuid,  'voisin@impact.bj')
on conflict do nothing;

insert into public.profils (id, email, role, boutique_id, actif) values
  (:PORTEUR::uuid, 'porteur@impact.bj', 'livreur', 'bou_informatique', true),
  (:AUTRE::uuid,   'autre@impact.bj',   'livreur', 'bou_informatique', true),
  (:VOISIN::uuid,  'voisin@impact.bj',  'livreur', 'bou_essai_voisine', true)
on conflict (id) do update
   set role = 'livreur', boutique_id = excluded.boutique_id, actif = true;

select essai.egal((select count(*)::int from public.profils where role = 'livreur'), 3,
  'trois livreurs existent');

insert into public.produits
  (id, boutique_id, nom, prix, categorie_id, stock, disponible)
values ('prod_course', 'bou_informatique', 'Imprimante', 80000,
        'cat_accessoires', 20, true)
on conflict (id) do update set prix = 80000, stock = 20, disponible = true;
insert into public.produits_prive (produit_id, prix_grossiste)
values ('prod_course', 60000)
on conflict (produit_id) do update set prix_grossiste = 60000;

select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97222222","adresse":"Akpakpa, rue 12"}'::jsonb,
  '[{"produit_id":"prod_course","quantite":1}]'::jsonb) ->> 'id' as vente \gset
reset role;
select essai.personne();
select public.marquer_payee(:'vente', 'TRX-COURSE-1',
  (select total from public.commandes where id = :'vente'), 'feexpay') as e1 \gset
select id as ligne from public.commande_lignes where commande_id = :'vente' \gset

-- ---------------------------------------------------------
select essai.titre('UN LIVREUR N''EST PAS L''ÉQUIPE');
-- ---------------------------------------------------------
-- LE CONSTAT. Il a un profil actif : l'ancienne définition de
-- « est_equipe() » lui aurait tout ouvert d'un coup.
select essai.devenir(:PORTEUR::uuid);
set role authenticated;
select essai.verifie(not public.est_equipe(), 'il n''est pas « l''équipe »');
select essai.verifie(public.est_livreur(), 'il est livreur');
select essai.verifie(not public.est_admin(), 'ni administrateur');

-- Le catalogue : la colonne « peut_modifier_produits » vaut VRAI par
-- défaut, et lui aurait dit oui sans la garde posée devant.
select essai.verifie(not public.peut_modifier_produits(),
  'et il ne modifie pas le catalogue, malgré la colonne qui dit oui');
select essai.verifie(not public.peut_deposer('produits/x.jpg'),
  'ni ne dépose de photo');

-- Les chiffres de la boutique ne le regardent pas.
select essai.egal((select count(*)::int from public.statistiques_boutique()), 0,
  'il ne lit aucun chiffre de vente');
-- Ni les commandes de la boutique par la table.
select essai.egal((select count(*)::int from public.commandes), 0,
  'ni les commandes de la boutique');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Tant qu''on ne lui a rien confié, il n''a rien');
-- ---------------------------------------------------------
select essai.devenir(:PORTEUR::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.mes_livraisons()), 0,
  'sa liste est vide');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('La boutique confie, et seulement à SON livreur');
-- ---------------------------------------------------------
select essai.devenir(:CHEF::uuid);
set role authenticated;

-- On ne confie pas ce qui n'est pas prêt.
select essai.refuse(
  format($$select public.assigner_livreur(%L, 'bou_informatique', %L::uuid)$$,
    :'vente', :PORTEUR),
  'on confie une commande pas encore préparée');

update public.commande_lignes set etat = 'vue' where id = :'ligne';
update public.commande_lignes set etat = 'preparee' where id = :'ligne';

-- Le livreur de la boutique d'à côté : ce serait lui remettre le nom,
-- le numéro et l'adresse d'un client qui n'est pas le sien.
select essai.refuse(
  format($$select public.assigner_livreur(%L, 'bou_informatique', %L::uuid)$$,
    :'vente', :VOISIN),
  'on confie au livreur de la boutique voisine');
-- Et pas davantage à quelqu'un qui n'est pas livreur.
select essai.refuse(
  format($$select public.assigner_livreur(%L, 'bou_informatique', %L::uuid)$$,
    :'vente', :KOFI),
  'ou à un client');

select public.assigner_livreur(:'vente', 'bou_informatique', :PORTEUR::uuid) as combien \gset
select essai.egal(:'combien'::int, 1, 'la course est confiée');
reset role;
select essai.personne();

-- Un livreur ne se confie pas une course à lui-même.
select essai.devenir(:PORTEUR::uuid);
set role authenticated;
select essai.refuse(
  format($$select public.assigner_livreur(%L, 'bou_informatique', %L::uuid)$$,
    :'vente', :PORTEUR),
  'un livreur se confie une course');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('IL NE VOIT AUCUN MONTANT');
-- ---------------------------------------------------------
-- LE CONSTAT DE CE FICHIER. Une règle RLS décide quelles LIGNES on
-- voit ; elle les rend alors ENTIÈRES. Seule une fonction peut choisir
-- les colonnes — et celle-ci n'en rend aucune qui porte de l'argent.
select essai.verifie(
  (select pg_get_function_result(p.oid) not like '%prix%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'mes_livraisons'),
  'aucun prix dans ce que la fonction rend');
select essai.verifie(
  (select pg_get_function_result(p.oid) not like '%total%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'mes_livraisons'),
  'ni aucun total');
select essai.verifie(
  (select pg_get_function_result(p.oid) not like '%marge%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'mes_livraisons'),
  'ni la marge');

select essai.devenir(:PORTEUR::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.mes_livraisons()), 1,
  'sa course est là');
select essai.egal((select client_nom from public.mes_livraisons()), 'Kofi',
  'avec le nom du client');
select essai.egal((select client_adresse from public.mes_livraisons()),
  'Akpakpa, rue 12', 'et où livrer');
select essai.verifie(
  (select articles::text like '%Imprimante%' from public.mes_livraisons()),
  'et ce qu''il porte');
-- LE MONTANT N'Y EST PAS, dans aucun sens : ni les 80 000 payés, ni les
-- 60 000 que la boutique touche.
select essai.verifie(
  (select articles::text not like '%80000%' and articles::text not like '%60000%'
     from public.mes_livraisons()),
  'mais aucun montant, ni payé ni reversé');

-- Et par la table, rien du tout : ce n'est pas une politesse d'écran.
select essai.refuse(
  $$select prix_bizzoo from public.commande_lignes$$,
  'il lit le prix BIZZOO dans la table');
select essai.egal((select count(*)::int from public.commande_lignes), 0,
  'et il ne lit aucune ligne de commande par la table');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('IL NE VOIT QUE SES COURSES');
-- ---------------------------------------------------------
select essai.devenir(:AUTRE::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.mes_livraisons()), 0,
  'le collègue de la même boutique n''en voit rien');
reset role;
select essai.personne();

select essai.devenir(:VOISIN::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.mes_livraisons()), 0,
  'et le livreur de la voisine non plus');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Il avance dans le bon sens, et sur deux étapes');
-- ---------------------------------------------------------
select essai.devenir(:PORTEUR::uuid);
set role authenticated;

-- On ne remet pas ce qu'on n'a pas pris.
select essai.refuse(
  format($$select public.avancer_livraison(%L, 'bou_informatique', 'remise')$$, :'vente'),
  'il remet une course qu''il n''a pas prise');
-- Et il ne fait pas le travail de la boutique.
select essai.refuse(
  format($$select public.avancer_livraison(%L, 'bou_informatique', 'preparee')$$, :'vente'),
  'il prépare la commande à la place de la boutique');
select essai.refuse(
  format($$select public.avancer_livraison(%L, 'bou_informatique', 'annulee')$$, :'vente'),
  'ou l''annule');

select public.avancer_livraison(:'vente', 'bou_informatique', 'en_livraison') as p1 \gset
select essai.egal(:'p1'::int, 1, 'il prend la course');
reset role;
select essai.personne();
select essai.egal((select etat from public.commande_lignes where id = :'ligne'),
  'en_livraison', 'et la ligne passe en livraison');

-- Le collègue ne peut pas remettre la course d'un autre.
select essai.devenir(:AUTRE::uuid);
set role authenticated;
select essai.refuse(
  format($$select public.avancer_livraison(%L, 'bou_informatique', 'remise')$$, :'vente'),
  'un collègue remet la course d''un autre');
reset role;
select essai.personne();

select essai.devenir(:PORTEUR::uuid);
set role authenticated;
select public.avancer_livraison(:'vente', 'bou_informatique', 'remise') as p2 \gset
select essai.egal(:'p2'::int, 1, 'il la remet');
reset role;
select essai.personne();
select essai.egal((select etat from public.commande_lignes where id = :'ligne'),
  'remise', 'et la ligne est remise');

-- ---------------------------------------------------------
select essai.titre('Et le client garde le dernier mot');
-- ---------------------------------------------------------
-- Le livreur déclare avoir remis ; c'est toujours le CLIENT qui
-- confirme avoir reçu. Le livreur ne signe pas à sa place.
select essai.devenir(:PORTEUR::uuid);
set role authenticated;
select essai.refuse(
  format($$select public.confirmer_reception(%L, 'bou_informatique')$$, :'vente'),
  'le livreur signe l''accusé de réception');
reset role;
select essai.personne();

select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.confirmer_reception(:'vente', 'bou_informatique') as c1 \gset
select essai.egal(:'c1'::int, 1, 'le client, lui, confirme');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Un visiteur n''approche pas');
-- ---------------------------------------------------------
set role anon;
select essai.refuse($$select count(*) from public.mes_livraisons()$$,
  'un visiteur lit des livraisons');
select essai.refuse($$select count(*) from public.livreurs_boutique()$$,
  'ou la liste des livreurs');
select essai.refuse(
  $$select public.avancer_livraison('x', 'bou_informatique', 'remise')$$,
  'ou avance une course');
reset role;

-- Un client non plus : il n'est pas de l'équipe.
select essai.devenir(:KOFI::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.mes_livraisons()), 0,
  'un client ne lit aucune livraison');
select essai.egal((select count(*)::int from public.livreurs_boutique()), 0,
  'ni la liste des livreurs de la boutique');
reset role;
select essai.personne();
