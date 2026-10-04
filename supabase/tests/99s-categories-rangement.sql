-- =========================================================
-- Les catégories rangées (3.56)
--
-- La base en ligne avait dix-sept catégories, dont deux créées
-- depuis l'admin, des noms d'avant et des rayons en double d'une
-- catégorie à l'autre. « categories-rangement.sql » y ajoute les
-- quatorze des nouvelles planches de l'enseigne, renomme, fait
-- déménager les rayons vides, fond « Prestataires de services »
-- dans « Services & Prestataires », et range le tout par thème.
--
-- Six choses à prouver :
--
--   1. SUR LA BASE EN LIGNE D'AVANT, LE FICHIER ARRIVE À LA LISTE
--      DE schema.sql : les mêmes quatorze, les mêmes rayons, les
--      mêmes noms, les mêmes icônes, le même ordre ;
--   2. RIEN NE SE PERD : aucun produit ne change de rayon, aucune
--      boutique de secteur, les huit de l'accueil restent, et
--      chaque icône désignée existe dans les deux applications ;
--   3. LES APPLICATIONS INSTALLÉES gardent leurs illustrations, et
--      une nouvelle en reçoit une quand l'une dit la même chose ;
--   4. REJOUÉ, IL NE FAIT RIEN : ni un nom, ni un ordre, ni une
--      suppression décidés depuis dans l'admin ne sont défaits ;
--   5. CE QUE L'ENSEIGNE A DÉJÀ CHANGÉ RESTE : un nom qu'elle a
--      choisi n'est pas renommé ;
--   6. CE QUI EST OCCUPÉ NE BOUGE PAS : un rayon qui a des produits
--      ne déménage pas, une catégorie où une boutique se range ne
--      s'efface pas.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set fichier `echo "$RACINE/supabase/categories-rangement.sql"`
\set icones_client `ls "$RACINE/client/img/pictos" | tr '\n' ' '`
\set icones_admin `ls "$RACINE/admin/img/pictos" | tr '\n' ' '`

-- ---------------------------------------------------------
select essai.titre('Le décor : la liste de schema.sql, gardée pour comparer');

create temp table essai_cat_semee as select * from public.categories;
create temp table essai_sc_semee as select * from public.sous_categories;
create temp table essai_quatorze (id text primary key);
insert into essai_quatorze values
  ('cat_energie'), ('cat_securite'), ('cat_formation'), ('cat_jardinage'), ('cat_transport'),
  ('cat_agriculture'), ('cat_musique'), ('cat_artisanat'), ('cat_cadeaux'), ('cat_evenementiel'),
  ('cat_bureau'), ('cat_materiel_pro'), ('cat_imprimerie'), ('cat_grossistes');
select essai.egal(
  (select count(*)::int from essai_cat_semee join essai_quatorze using (id)), 14,
  'schema.sql pose les quatorze nouvelles');

-- LA BASE EN LIGNE D'AVANT, telle qu'elle était le 3 octobre : ses
-- noms, ses icônes, ses illustrations, son ordre, ses huit de
-- l'accueil, et les deux catégories créées depuis l'admin. Une
-- fonction, pour la refaire une seconde fois plus bas.
create function pg_temp.etat_en_ligne() returns void language plpgsql as $$
begin
  insert into public.categories (id, boutique_id, nom, icone, couleur, en_avant, ordre, image) values
    ('cat_muifjqpbju094q', null, 'Électro-ménagers & Cuisinière', 'electromenager', '#2550B7', true, 4,
     'img/categories/chariot.jpg'),
    ('cat_muflx6zvfjj9u8', null, 'Prestataires de services', 'services', '#0B5CF5', false, 17,
     'img/categories/poignee-de-main.jpg')
  on conflict (id) do update
     set nom = excluded.nom, icone = excluded.icone, couleur = excluded.couleur,
         en_avant = excluded.en_avant, ordre = excluded.ordre, image = excluded.image;
  insert into public.sous_categories (id, categorie_id, nom, ordre) values
    ('sc_essai_frigo',           'cat_muifjqpbju094q', 'Réfrigérateur', 1),
    ('sc_essai_cuisiniere',      'cat_muifjqpbju094q', 'Cuisinière',    2),
    ('sc_essai_electricien',     'cat_muflx6zvfjj9u8', 'Électricien',   1),
    ('sc_essai_informaticien',   'cat_muflx6zvfjj9u8', 'Informaticien', 2),
    ('sc_essai_vitrier',         'cat_muflx6zvfjj9u8', 'Vitrier',       3),
    ('sc_essai_plombier',        'cat_muflx6zvfjj9u8', 'Plombier',      4),
    ('sc_services_informatique', 'cat_services',       'Informatique',  4)
  on conflict (id) do update
     set categorie_id = excluded.categorie_id, nom = excluded.nom, ordre = excluded.ordre;
  -- Les rayons qui vont déménager, à leur place d'avant — AVANT que
  -- leurs nouvelles catégories ne s'en aillent avec eux.
  update public.sous_categories s set categorie_id = v.categorie, ordre = v.ordre
    from (values ('sc_brico_electricite', 'cat_bricolage',    3),
                 ('sc_livres_formations', 'cat_livres',       4),
                 ('sc_maison_jardinage',  'cat_maison',       5),
                 ('sc_resto_epicerie',    'cat_restauration', 5),
                 ('sc_resto_frais',       'cat_restauration', 6)) as v(id, categorie, ordre)
   where s.id = v.id;
  delete from public.categories where id in (select id from essai_quatorze);
  update public.categories c
     set nom = v.nom, icone = v.icone, image = v.image, en_avant = v.avant, ordre = v.ordre
    from (values
      ('cat_hightech',     'Informatique et électronique',    'informatique',     'img/categories/ecran.jpg',          true,   1),
      ('cat_bebe',         'Bébé & Enfant',                   'bebe-enfant',      'img/categories/nounours.jpg',       true,   2),
      ('cat_logiciels',    'Logiciels & Solutions pro',       'informatique',     'img/categories/ordinateur.jpg',     true,   3),
      ('cat_auto',         'Auto & Moto',                     'auto-moto',        'img/categories/voiture.jpg',        true,   5),
      ('cat_mode',         'Mode & Vêtements',                'mode',             'img/categories/robe.jpg',           false,  6),
      ('cat_maison',       'Maison & Jardin',                 'maison-deco',      'img/categories/maison.jpg',         true,   7),
      ('cat_beaute',       'Beauté & Bien-être',              'beaute',           'img/categories/rouge-a-levres.jpg', false,  8),
      ('cat_restauration', 'Restauration & Alimentation',     'restauration',     'img/categories/marmite.jpg',        false,  9),
      ('cat_supermarche',  'Supermarché & Épicerie',          'alimentation',     'img/categories/chariot.jpg',        false, 10),
      ('cat_sport',        'Sport & Loisirs',                 'sport-loisirs',    'img/categories/ballon.jpg',         false, 11),
      ('cat_bricolage',    'Btp et matériaux.',               'immobilier',       'img/categories/briques.jpg',        true,  12),
      ('cat_livres',       'Livres, Éducation & Fournitures', 'livres-education', 'img/categories/livres.jpg',         true,  13),
      ('cat_bijoux',       'Bijoux & Accessoires',            'mode',             'img/categories/bague.jpg',          false, 14),
      ('cat_animaux',      'Animaux',                         'animaux',          'img/categories/chien.jpg',          false, 15),
      ('cat_services',     'Services',                        'services',         'img/categories/boite-a-outils.jpg', false, 16)
    ) as v(id, nom, icone, image, avant, ordre)
   where c.id = v.id;
end $$;

select pg_temp.etat_en_ligne();
select essai.egal((select count(*)::int from public.categories), 17,
  'la base en ligne d''avant : dix-sept catégories');

create temp table essai_produits_avant as
  select id, categorie_id, sous_categorie_id from public.produits;
create temp table essai_boutiques_avant as
  select id, categorie_id from public.boutiques;
create temp table essai_accueil_avant as
  select id from public.categories where en_avant;

\o /dev/null
set client_min_messages = warning;
\i :fichier
set client_min_messages = notice;
\o

-- ---------------------------------------------------------
select essai.titre('1. Le fichier arrive à la liste de schema.sql');

select essai.egal((select count(*)::int from public.categories), 30,
  'trente catégories : seize d''avant, quatorze nouvelles');
select essai.egal(
  (select count(*)::int from (
     select id, nom, icone, couleur, en_avant, ordre from public.categories
      where id in (select id from essai_quatorze)
     except
     select id, nom, icone, couleur, en_avant, ordre from essai_cat_semee) d), 0,
  'les quatorze, comme schema.sql les pose : nom, icône, couleur, ordre');
select essai.egal(
  (select count(*)::int from (
     (select id, categorie_id, nom, ordre from public.sous_categories
       where categorie_id in (select id from essai_quatorze)
      except
      select id, categorie_id, nom, ordre from essai_sc_semee
       where categorie_id in (select id from essai_quatorze))
     union all
     (select id, categorie_id, nom, ordre from essai_sc_semee
       where categorie_id in (select id from essai_quatorze)
      except
      select id, categorie_id, nom, ordre from public.sous_categories
       where categorie_id in (select id from essai_quatorze))) d), 0,
  'et leurs rayons, ceux qui déménagent compris');
select essai.egal(
  (select count(*)::int from public.categories c join essai_cat_semee s using (id)
    where c.nom = s.nom and c.icone = s.icone
      and c.id in ('cat_hightech', 'cat_logiciels', 'cat_bebe', 'cat_livres', 'cat_maison',
                   'cat_bricolage', 'cat_restauration', 'cat_services', 'cat_bijoux')), 9,
  'les noms et les icônes d''avant deviennent ceux de schema.sql');
select essai.egal(
  (select string_agg(nom, ' | ' order by id) from public.categories
    where id in ('cat_bebe', 'cat_bricolage', 'cat_livres', 'cat_maison', 'cat_restauration',
                 'cat_services')),
  'Bébé & Enfants | Bricolage & Matériaux | Livres & Fournitures scolaires | Maison & Déco | Restauration | Services & Prestataires',
  'Bébé & Enfants, Bricolage & Matériaux, Livres & Fournitures scolaires…');
select essai.egal(
  (select string_agg(icone, ' ' order by id) from public.categories
    where id in ('cat_bijoux', 'cat_bricolage')), 'bijoux bricolage',
  'Bijoux et Bricolage ont chacune leur icône');
-- L'ORDRE PAR THÈME, le même que schema.sql ; « Électro-ménagers &
-- Cuisinière », créée depuis l'admin, prend la place 3 que la liste lui
-- garde.
select essai.egal(
  (select count(*)::int from public.categories c join essai_cat_semee s using (id)
    where c.ordre = s.ordre), 29, 'l''ordre par thème, celui de schema.sql');
select essai.egal(
  (select ordre from public.categories where id = 'cat_muifjqpbju094q'), 3,
  '« Électro-ménagers & Cuisinière » à la troisième place');
select essai.egal(
  (select count(distinct ordre)::int from public.categories), 30, 'chacune à sa place, sans ex æquo');
select essai.egal(
  (select string_agg(nom, ' | ' order by ordre) from public.categories where ordre <= 5),
  'Informatique & Électronique | Logiciels & Solutions pro | Électro-ménagers & Cuisinière | Énergie solaire & Électricité | Sécurité & Surveillance',
  'le high-tech d''abord');
-- « Électro-ménagers & Cuisinière » n'est pas renommée : c'est le nom
-- que l'enseigne lui a donné.
select essai.egal(
  (select nom from public.categories where id = 'cat_muifjqpbju094q'),
  'Électro-ménagers & Cuisinière', 'le nom donné par l''enseigne à sa catégorie reste');

-- « PRESTATAIRES DE SERVICES » VERSE SES RAYONS, puis s'efface.
select essai.verifie(
  not exists (select 1 from public.categories where id = 'cat_muflx6zvfjj9u8'),
  '« Prestataires de services » s''efface…');
select essai.egal(
  (select string_agg(nom || ':' || ordre, ' ' order by ordre) from public.sous_categories
    where categorie_id = 'cat_services'),
  'Réparation:1 Installation:2 Maintenance:3 Nettoyage:5 Services professionnels:6 Électricien:7 Informaticien:8 Vitrier:9 Plombier:10',
  '… et ses rayons rejoignent « Services & Prestataires », à la suite ; « Informaticien » remplace « Informatique »');
-- Les rayons en double d'une catégorie à l'autre ont déménagé.
select essai.egal(
  (select string_agg(nom, ' ' order by ordre) from public.sous_categories
    where categorie_id = 'cat_supermarche'),
  'Alimentation Produits ménagers Produits pour bébé Hygiène Boissons Épicerie Produits frais',
  'Épicerie et Produits frais rejoignent le supermarché');
select essai.egal(
  (select string_agg(nom, ' ' order by ordre) from public.sous_categories
    where categorie_id = 'cat_restauration'),
  'Restaurants Fast-food Plats locaux Boissons', 'la restauration garde ce qui est à elle');

-- ---------------------------------------------------------
select essai.titre('2. Rien ne se perd');

select essai.egal(
  (select count(*)::int from (
     select id, categorie_id, sous_categorie_id from public.produits
     except select id, categorie_id, sous_categorie_id from essai_produits_avant) d), 0,
  'aucun produit ne change de rayon ni de catégorie');
select essai.egal(
  (select count(*)::int from (
     select id, categorie_id from public.boutiques
     except select id, categorie_id from essai_boutiques_avant) d), 0,
  'aucune boutique ne change de secteur');
select essai.egal(
  (select string_agg(id, ' ' order by id) from public.categories where en_avant),
  (select string_agg(id, ' ' order by id) from essai_accueil_avant),
  'les huit de l''accueil restent les mêmes');
select essai.egal(
  (select count(*)::int from public.sous_categories where id in
     ('sc_essai_frigo', 'sc_essai_cuisiniere', 'sc_essai_electricien', 'sc_essai_informaticien',
      'sc_essai_vitrier', 'sc_essai_plombier')), 6,
  'les rayons créés depuis l''admin sont tous là');
select essai.verifie(
  not exists (select 1 from public.categories c
               where position(' ' || c.icone || '.png ' in ' ' || :'icones_client') = 0),
  'chaque icône désignée est un fichier de l''application cliente');
select essai.verifie(
  not exists (select 1 from public.categories c
               where position(' ' || c.icone || '.png ' in ' ' || :'icones_admin') = 0),
  'et de l''admin');

-- ---------------------------------------------------------
select essai.titre('3. Les applications installées');

-- ELLES MONTRENT L'ILLUSTRATION D'AVANT par-dessus l'icône : celles des
-- catégories d'avant restent ; une nouvelle en reçoit une quand l'une
-- dit la même chose, sinon rien (les applications 3.56 ne lisent pas
-- ces chemins).
select essai.egal(
  (select string_agg(id || '=' || image, ' ' order by id) from public.categories
    where id in ('cat_mode', 'cat_bricolage', 'cat_muifjqpbju094q')),
  'cat_bricolage=img/categories/briques.jpg cat_mode=img/categories/robe.jpg cat_muifjqpbju094q=img/categories/chariot.jpg',
  'les illustrations des catégories d''avant restent');
select essai.egal(
  (select string_agg(id || '=' || replace(image, 'img/categories/', ''), ' ' order by id)
     from public.categories where id in (select id from essai_quatorze) and image <> ''),
  'cat_agriculture=plante.jpg cat_artisanat=panier.jpg cat_bureau=mallette.jpg cat_formation=livres.jpg cat_jardinage=plante.jpg cat_materiel_pro=outils.jpg cat_transport=moto.jpg',
  'sept nouvelles reçoivent l''illustration d''avant qui dit la même chose');

-- ---------------------------------------------------------
select essai.titre('4. Rejoué, il ne fait rien');

-- L'enseigne retouche la liste dans l'admin : un nom d'avant remis, un
-- ordre changé, une catégorie nouvelle retirée.
update public.categories set nom = 'Maison & Jardin' where id = 'cat_maison';
update public.categories set ordre = 0 where id = 'cat_sport';
delete from public.categories where id = 'cat_musique';
create temp table essai_apres_admin as
  select id, nom, icone, image, en_avant, ordre from public.categories;
create temp table essai_sc_apres_admin as
  select id, categorie_id, nom, ordre from public.sous_categories;
\o /dev/null
set client_min_messages = warning;
\i :fichier
set client_min_messages = notice;
\o
select essai.egal(
  (select count(*)::int from (
     (select id, nom, icone, image, en_avant, ordre from public.categories
      except select * from essai_apres_admin)
     union all
     (select * from essai_apres_admin
      except select id, nom, icone, image, en_avant, ordre from public.categories)) d), 0,
  'rejoué, il ne défait ni le nom remis, ni l''ordre changé, ni la catégorie retirée');
select essai.egal(
  (select count(*)::int from (
     (select id, categorie_id, nom, ordre from public.sous_categories
      except select * from essai_sc_apres_admin)
     union all
     (select * from essai_sc_apres_admin
      except select id, categorie_id, nom, ordre from public.sous_categories)) d), 0,
  'ni un rayon');

-- ---------------------------------------------------------
select essai.titre('5 et 6. Ce que l''enseigne a choisi, et ce qui est occupé, ne bougent pas');

-- LA BASE EN LIGNE D'AVANT, une seconde fois, avec trois différences :
-- un nom que l'enseigne a déjà changé, un produit dans un rayon qui
-- devait déménager, une boutique rangée dans « Prestataires ».
select pg_temp.etat_en_ligne();
update public.categories set nom = 'Restaurants & Maquis' where id = 'cat_restauration';
insert into public.boutiques (id, nom, secteur, devise, actif, ordre, categorie_id) values
  ('bou_essai_resto',  'MAQUIS D''ESSAI',  'Essai', 'FCFA', true, 94, 'cat_restauration'),
  ('bou_essai_presta', 'ARTISAN D''ESSAI', 'Essai', 'FCFA', true, 95, 'cat_muflx6zvfjj9u8');
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_essai_frais', 'bou_essai_resto', 'Tomates', 1500, 'sc_resto_frais', 4, true);

\o /dev/null
set client_min_messages = warning;
\i :fichier
set client_min_messages = notice;
\o

select essai.egal(
  (select nom from public.categories where id = 'cat_restauration'), 'Restaurants & Maquis',
  'un nom que l''enseigne a déjà changé n''est pas renommé');
select essai.egal(
  (select nom from public.categories where id = 'cat_maison'), 'Maison & Déco',
  'les autres le sont');
select essai.egal(
  (select categorie_id from public.sous_categories where id = 'sc_resto_frais'), 'cat_restauration',
  'un rayon qui a des produits ne déménage pas');
select essai.egal(
  (select categorie_id from public.produits where id = 'prod_essai_frais'), 'cat_restauration',
  'et son produit reste dans sa catégorie');
select essai.egal(
  (select categorie_id from public.sous_categories where id = 'sc_resto_epicerie'), 'cat_supermarche',
  'le rayon vide d''à côté déménage');
select essai.verifie(
  exists (select 1 from public.categories where id = 'cat_muflx6zvfjj9u8'),
  'une catégorie où une boutique se range ne s''efface pas');
select essai.egal(
  (select count(*)::int from public.sous_categories where categorie_id = 'cat_muflx6zvfjj9u8'), 4,
  'elle garde ses rayons');
select essai.egal(
  (select categorie_id from public.boutiques where id = 'bou_essai_presta'), 'cat_muflx6zvfjj9u8',
  'et la boutique son secteur');
select essai.egal(
  (select categorie_id from public.sous_categories where id = 'sc_services_informatique'), 'cat_services',
  '« Informatique » reste, puisque « Informaticien » n''est pas venu');
select essai.egal(
  (select ordre from public.categories where id = 'cat_muflx6zvfjj9u8'), 31,
  'une catégorie que la liste ne connaît pas suit les trente');

-- ---------------------------------------------------------
select essai.titre('On rend la base comme on l''a trouvée');

delete from public.produits where id = 'prod_essai_frais';
delete from public.boutiques where id in ('bou_essai_resto', 'bou_essai_presta');
delete from public.categories
 where boutique_id is null and id not in (select id from essai_cat_semee);
insert into public.categories select * from essai_cat_semee
on conflict (id) do update
   set boutique_id = excluded.boutique_id, nom = excluded.nom, icone = excluded.icone,
       couleur = excluded.couleur, image = excluded.image, en_avant = excluded.en_avant,
       ordre = excluded.ordre, cree_le = excluded.cree_le;
insert into public.sous_categories select * from essai_sc_semee
on conflict (id) do update
   set categorie_id = excluded.categorie_id, nom = excluded.nom, ordre = excluded.ordre;
delete from public.sous_categories where id not in (select id from essai_sc_semee);
select essai.egal(
  (select count(*)::int from (select * from public.categories except select * from essai_cat_semee) d) +
  (select count(*)::int from (select * from public.sous_categories except select * from essai_sc_semee) d), 0,
  'la liste est rendue telle que schema.sql l''a posée');
