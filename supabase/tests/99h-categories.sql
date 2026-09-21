-- =========================================================
-- La liste des catégories : celle de l'enseigne, et d'elle
-- seule.
--
-- Jusqu'ici chaque boutique inventait ses rayons. Sur une
-- vitrine unique c'était sans conséquence ; sur une place de
-- marché, cela donne autant de classements qu'il y a de
-- commerces — et l'écran « Catégories » de BIZZOO n'a plus
-- rien à montrer qui vaille pour tout le monde.
--
-- Cinq choses à prouver :
--
--   1. UNE BOUTIQUE N'ÉCRIT PAS LA LISTE. Ni en créer une
--      catégorie, ni en renommer, ni en supprimer ;
--   2. LE RAYON D'UN PRODUIT SE DÉDUIT de sa sous-catégorie.
--      Ce que l'application envoie dans « categorie_id » n'est
--      pas écouté : deux colonnes qui se contredisent, c'est
--      un classement qui ment ;
--   3. HORS DE SON SECTEUR, UN PRODUIT EST REFUSÉ. C'est tout
--      l'objet de la liste commune ;
--   4. LE SECTEUR NE CHANGE PAS SOUS LES PRODUITS. Même pour
--      l'enseigne : ce n'est pas une question de rang, mais de
--      cohérence ;
--   5. LA LISTE SE LIT SANS COMPTE. C'est le menu de la
--      vitrine ; un visiteur doit le voir.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set MODE     '''dddddddd-1111-1111-1111-111111111111'''

select essai.titre('Le décor : une boutique de mode, à côté de l''informatique');

-- UNE TROISIÈME BOUTIQUE, DANS UN AUTRE SECTEUR. Les autres essais
-- rangent tout leur monde dans « High-Tech » pour rester simples ;
-- celle-ci existe pour que « hors de son secteur » veuille dire
-- quelque chose.
insert into public.boutiques (id, nom, secteur, devise, actif, ordre, categorie_id)
values ('bou_essai_mode', 'BOUTIQUE DE MODE', 'Essai', 'FCFA', true, 92, 'cat_mode')
on conflict (id) do nothing;

-- Et une sans secteur du tout : c'est l'état de toute boutique le jour
-- où l'enseigne pose cette liste.
insert into public.boutiques (id, nom, secteur, devise, actif, ordre)
values ('bou_essai_sans', 'BOUTIQUE SANS SECTEUR', 'Essai', 'FCFA', true, 93)
on conflict (id) do nothing;

insert into auth.users (id, email) values (:MODE::uuid, 'mode@bizzoo.bj')
on conflict do nothing;
insert into public.profils (id, email, role, boutique_id, actif) values
  (:MODE::uuid, 'mode@bizzoo.bj', 'administrateur', 'bou_essai_mode', true)
on conflict (id) do update
   set role = 'administrateur', boutique_id = 'bou_essai_mode', actif = true;

select essai.egal((select count(*)::int from public.categories), 15,
  'les quinze catégories de BIZZOO sont là');
select essai.egal((select count(*)::int from public.sous_categories), 74,
  'et leurs soixante-quatorze rayons');
-- Les quinze ne tiennent pas sur un accueil : huit s'y montrent.
select essai.egal((select count(*)::int from public.categories where en_avant), 8,
  'huit sont mises en avant pour l''accueil');
select essai.verifie(
  (select bool_and(coalesce(boutique_id, '') = '') from public.categories),
  'aucune n''appartient à une boutique : elles sont à l''enseigne');

-- ---------------------------------------------------------
select essai.titre('UNE BOUTIQUE N''ÉCRIT PAS LA LISTE');
-- ---------------------------------------------------------
-- Le compte le plus fort d'une boutique : administrateur, actif, chez
-- lui. S'il ne peut pas, personne d'autre ne peut.
select essai.devenir(:MODE::uuid);
set role authenticated;

-- Une INSERTION refusée par RLS LÈVE : « new row violates row-level
-- security policy ». C'est donc « refuse » qui convient ici.
select essai.refuse(
  $$insert into public.categories (id, nom, ordre)
    values ('cat_pirate', 'Mon rayon à moi', 99)$$,
  'un administrateur crée une catégorie');
select essai.refuse(
  $$insert into public.sous_categories (id, categorie_id, nom, ordre)
    values ('sc_pirate', 'cat_mode', 'Mon rayon à moi', 99)$$,
  'ou une sous-catégorie');

-- UNE MODIFICATION, ELLE, NE LÈVE PAS. Une règle RLS ne refuse pas :
-- elle FILTRE. L'écriture ne trouve aucune ligne autorisée et réussit
-- en silence, sans rien toucher. Attendre un refus ferait échouer
-- l'essai pour la mauvaise raison — on constate que rien n'a bougé.
select essai.sans_effet(
  $$update public.categories set nom = 'Renommée par la boutique'
     where id = 'cat_mode'$$,
  'il renomme une catégorie');
select essai.sans_effet(
  $$delete from public.categories where id = 'cat_bijoux'$$,
  'il en supprime une');
select essai.sans_effet(
  $$update public.categories set en_avant = true where id = 'cat_animaux'$$,
  'ou s''en met une en avant');
select essai.sans_effet(
  $$delete from public.sous_categories where id = 'sc_mode_homme'$$,
  'et il ne retire pas davantage un rayon');

-- Il la LIT, en revanche : sans cela il ne pourrait pas classer ses
-- propres produits.
select essai.egal((select count(*)::int from public.categories), 15,
  'mais il la lit en entier');
reset role;
select essai.personne();

-- L'enseigne, elle, l'écrit.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
insert into public.categories (id, nom, icone, couleur, ordre)
values ('cat_essai_enseigne', 'Rayon de l''enseigne', 'etoile', '#0F9D58', 99);
select essai.egal(
  (select nom from public.categories where id = 'cat_essai_enseigne'),
  'Rayon de l''enseigne', 'l''enseigne en crée une');
delete from public.categories where id = 'cat_essai_enseigne';
select essai.egal((select count(*)::int from public.categories
                    where id = 'cat_essai_enseigne'), 0,
  'et la retire');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('LE RAYON D''UN PRODUIT SE DÉDUIT');
-- ---------------------------------------------------------
select essai.devenir(:MODE::uuid);
set role authenticated;

-- LE CONSTAT CENTRAL : on ne donne QUE la sous-catégorie, et la
-- catégorie apparaît toute seule.
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_robe', 'bou_essai_mode', 'Robe', 12000, 'sc_mode_femme', 5, true);
select essai.egal(
  (select categorie_id from public.produits where id = 'prod_robe'),
  'cat_mode', 'la catégorie se pose toute seule depuis la sous-catégorie');

-- ET UN MENSONGE DANS « categorie_id » N'EST PAS ÉCOUTÉ. Sans cela, le
-- produit serait dans un rayon à l'écran et dans un autre dans les
-- comptes.
insert into public.produits (id, boutique_id, nom, prix, categorie_id, sous_categorie_id, stock, disponible)
values ('prod_menteur', 'bou_essai_mode', 'Chemise', 9000,
        'cat_bijoux', 'sc_mode_homme', 3, true);
select essai.egal(
  (select categorie_id from public.produits where id = 'prod_menteur'),
  'cat_mode', 'la catégorie soufflée par l''application est écrasée');

-- SANS SOUS-CATÉGORIE : à classer. Le produit reste en vente.
insert into public.produits (id, boutique_id, nom, prix, stock, disponible)
values ('prod_aclasser', 'bou_essai_mode', 'Écharpe', 3000, 8, true);
select essai.verifie(
  (select categorie_id is null and sous_categorie_id is null
     from public.produits where id = 'prod_aclasser'),
  'sans sous-catégorie, le produit est « à classer »');
select essai.verifie(
  (select disponible from public.produits where id = 'prod_aclasser'),
  'mais il reste en vente : à classer n''est pas retiré');

-- Et on déclasse en retirant la sous-catégorie.
update public.produits set sous_categorie_id = null where id = 'prod_menteur';
select essai.verifie(
  (select categorie_id is null from public.produits where id = 'prod_menteur'),
  'retirer la sous-catégorie déclasse aussi la catégorie');

-- ---------------------------------------------------------
select essai.titre('HORS DE SON SECTEUR, UN PRODUIT EST REFUSÉ');
-- ---------------------------------------------------------
-- LE CONSTAT QUI JUSTIFIE TOUTE LA LISTE. Une boutique de mode qui
-- publierait sous « Pièces détachées » rendrait le classement
-- inutilisable pour l'acheteur.
select essai.refuse(
  $$insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock)
    values ('prod_hors', 'bou_essai_mode', 'Clavier', 5000,
            'sc_hightech_accessoires', 1)$$,
  'la boutique de mode publie sous un rayon High-Tech');
select essai.refuse(
  $$update public.produits set sous_categorie_id = 'sc_auto_pneus'
     where id = 'prod_robe'$$,
  'ou déplace un produit vers le secteur du voisin');
select essai.refuse(
  $$insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock)
    values ('prod_faux', 'bou_essai_mode', 'Fantôme', 5000, 'sc_inexistante', 1)$$,
  'ou invente une sous-catégorie');
reset role;
select essai.personne();

-- SANS SECTEUR, RIEN NE SE CLASSE. C'est l'état de toute boutique le
-- jour où l'enseigne pose cette liste : elle doit d'abord lui en
-- donner un.
select essai.refuse(
  $$insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock)
    values ('prod_sans', 'bou_essai_sans', 'Article', 5000, 'sc_mode_femme', 1)$$,
  'une boutique sans secteur classe un produit');
-- Mais elle peut en poser un, à classer plus tard : on ne bloque pas
-- son catalogue en attendant.
insert into public.produits (id, boutique_id, nom, prix, stock, disponible)
values ('prod_sans', 'bou_essai_sans', 'Article', 5000, 2, true)
on conflict (id) do nothing;
select essai.egal((select count(*)::int from public.produits where id = 'prod_sans'), 1,
  'elle peut tout de même vendre, en attendant son secteur');

-- ---------------------------------------------------------
select essai.titre('LE SECTEUR NE CHANGE PAS SOUS LES PRODUITS');
-- ---------------------------------------------------------
-- Une boutique n'y touche pas : le secteur dit où elle se range dans
-- BIZZOO, et c'est une décision de l'enseigne.
select essai.devenir(:MODE::uuid);
set role authenticated;
select essai.refuse(
  $$update public.boutiques set categorie_id = 'cat_bijoux'
     where id = 'bou_essai_mode'$$,
  'la boutique change son propre secteur');
select essai.refuse(
  $$select public.changer_secteur('bou_essai_mode', 'cat_bijoux')$$,
  'ou passe par la fonction prévue pour l''enseigne');
reset role;
select essai.personne();

-- ET L'ENSEIGNE ELLE-MÊME NE LE CHANGE PAS À LA MAIN. Ce n'est pas une
-- question de rang : les produits sont rangés dans des sous-catégories
-- de l'ANCIEN secteur, que le nouveau n'a pas. Ils se retrouveraient
-- classés sous un rayon auquel ils n'appartiennent pas.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.refuse(
  $$update public.boutiques set categorie_id = 'cat_bijoux'
     where id = 'bou_essai_mode'$$,
  'L''ENSEIGNE ELLE-MÊME le change à la main');

-- Elle le voit venir avant de trancher.
select essai.egal(public.produits_classes('bou_essai_mode'), 1,
  'elle compte d''abord ce qu''elle s''apprête à déclasser');

-- Et la fonction fait les deux gestes dans l'ordre : déclasser, changer.
select public.changer_secteur('bou_essai_mode', 'cat_bijoux') as combien \gset
select essai.egal(:'combien'::int, 1, 'elle change le secteur, et dit ce qu''elle a déclassé');
select essai.egal(
  (select categorie_id from public.boutiques where id = 'bou_essai_mode'),
  'cat_bijoux', 'le secteur a bien changé');
select essai.verifie(
  (select bool_and(categorie_id is null and sous_categorie_id is null)
     from public.produits where boutique_id = 'bou_essai_mode'),
  'et plus aucun produit n''est rangé sous l''ancien');

-- Le catalogue se reclasse alors dans le NOUVEAU secteur, et pas dans
-- l'ancien.
update public.produits set sous_categorie_id = 'sc_bijoux_montres' where id = 'prod_robe';
select essai.egal(
  (select categorie_id from public.produits where id = 'prod_robe'),
  'cat_bijoux', 'les produits se reclassent dans le nouveau secteur');
select essai.refuse(
  $$update public.produits set sous_categorie_id = 'sc_mode_femme' where id = 'prod_menteur'$$,
  'et plus dans l''ancien');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('LA LISTE SE LIT SANS COMPTE');
-- ---------------------------------------------------------
-- C'est le menu de la vitrine : un visiteur qui ne le verrait pas
-- n'aurait plus d'écran « Catégories » du tout.
set role anon;
select essai.egal((select count(*)::int from public.categories), 15,
  'un visiteur lit les quinze catégories');
select essai.egal((select count(*)::int from public.sous_categories), 74,
  'et les soixante-quatorze rayons');
select essai.verifie(
  (select count(*) > 0 from public.categories where icone <> '' and couleur <> ''),
  'avec leur pastille : icône et couleur');

-- Mais il n'y touche pas.
select essai.refuse(
  $$insert into public.categories (id, nom, ordre) values ('cat_visiteur', 'À moi', 1)$$,
  'il en crée une');
select essai.sans_effet(
  $$update public.categories set nom = 'Volée' where id = 'cat_mode'$$,
  'il en renomme une');
reset role;

-- Et le compte des produits d'une boutique ne se lit pas sans être de
-- l'équipe : c'est un chiffre de la boutique.
set role anon;
select essai.refuse(
  $$select public.produits_classes('bou_essai_mode')$$,
  'un visiteur compte les produits classés d''une boutique');
reset role;
