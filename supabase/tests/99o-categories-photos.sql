-- =========================================================
-- La photo d'une catégorie
--
-- CE QU'ON AJOUTE. Une catégorie peut porter une photo, qui
-- prend la place de l'icône de sa tuile. Une colonne
-- « image » la range : un CHEMIN, dans le seau
-- (« enseigne/categories/ », une photo déposée depuis l'admin).
-- « img/categories/ », ce sont les illustrations en 3D d'avant
-- la 3.56, que la base en ligne garde pour les applications
-- déjà installées.
--
-- Sept choses à prouver :
--
--   1. L'ENSEIGNE SEULE LA POSE, comme elle seule écrit la
--      liste. Une boutique ne change pas la tuile de tout le
--      monde ;
--   2. UN CHEMIN, JAMAIS UNE ADRESSE, et dans ce dossier-là :
--      une adresse libre ferait charger à l'accueil de tous les
--      clients une image posée n'importe où ;
--   3. LE FICHIER AUSSI EST RÉSERVÉ : le stockage refuse le
--      dépôt à une boutique et à un visiteur ;
--   4. TOUT LE MONDE LA LIT, sans compte : c'est le menu de la
--      vitrine ;
--   5. LE MÉNAGE DU STOCKAGE NE LA PREND PAS POUR UN ORPHELIN.
--      L'état des lieux du stockage liste ce qui est
--      « supprimable » ; une photo de catégorie oubliée dans sa
--      liste y serait annoncée alors qu'elle est à l'écran — et
--      une suppression ne se rattrape pas ;
--   6. LES ICÔNES QUE LA BASE DÉSIGNE EXISTENT, en fichier dans
--      l'application cliente ET dans l'admin (« img/pictos/ ») —
--      sinon la tuile retombe sur un dessin d'un trait sans que
--      personne ne sache pourquoi ;
--   7. REJOUER LES FICHIERS NE DÉFAIT RIEN : ni une photo que
--      l'enseigne a retirée ou posée, ni une icône qu'elle a
--      choisie depuis — et celui des icônes ne touche jamais à
--      l'image que les applications installées montrent encore.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''

-- ---------------------------------------------------------
select essai.titre('Le décor : les catégories telles qu''elles sont');

select essai.verifie(
  exists (select 1 from public.categories where id = 'cat_mode'),
  'la catégorie « Mode » existe');
-- CHAQUE CATÉGORIE DE BIZZOO ARRIVE AVEC SON ICÔNE, et sans image :
-- depuis la 3.56, l'icône suffit. Une valeur nulle obligerait chaque
-- écran à s'en méfier.
create temp table essai_icones (id text primary key, icone text not null);
insert into essai_icones values
  ('cat_hightech', 'informatique'), ('cat_logiciels', 'informatique'), ('cat_energie', 'energie'),
  ('cat_securite', 'securite'), ('cat_bebe', 'bebe-enfant'), ('cat_livres', 'livres-education'),
  ('cat_formation', 'formation'), ('cat_maison', 'maison-deco'), ('cat_jardinage', 'jardinage'),
  ('cat_bricolage', 'bricolage'), ('cat_auto', 'auto-moto'), ('cat_transport', 'transport'),
  ('cat_mode', 'mode'), ('cat_bijoux', 'bijoux'), ('cat_beaute', 'beaute'),
  ('cat_supermarche', 'alimentation'), ('cat_restauration', 'restauration'),
  ('cat_agriculture', 'agriculture'), ('cat_animaux', 'animaux'), ('cat_sport', 'sport-loisirs'),
  ('cat_musique', 'musique'), ('cat_artisanat', 'artisanat'), ('cat_cadeaux', 'cadeau'),
  ('cat_evenementiel', 'evenementiel'), ('cat_bureau', 'bureau'), ('cat_materiel_pro', 'materiel-pro'),
  ('cat_imprimerie', 'imprimante'), ('cat_grossistes', 'grossistes'), ('cat_services', 'services');
select essai.egal(
  (select count(*)::text from public.categories c join essai_icones p using (id)
    where c.icone = p.icone),
  '29', 'les vingt-neuf de BIZZOO arrivent chacune avec son icône');
select essai.egal(
  (select count(*)::text from public.categories c join essai_icones p using (id)
    where c.image = ''),
  '29', 'et sans image : l''icône suffit');
select essai.verifie(
  not exists (select 1 from public.categories where image is null),
  'aucune image n''est nulle');

-- On garde les images telles qu'elles sont, pour les rendre à la fin.
create temp table essai_images_avant as select id, image from public.categories;

-- ---------------------------------------------------------
select essai.titre('1. L''enseigne seule pose la photo');

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.categories set image = 'enseigne/categories/cat_mode_1.jpg' where id = 'cat_mode';
select essai.egal(
  (select image from public.categories where id = 'cat_mode'),
  'enseigne/categories/cat_mode_1.jpg', 'le superadministrateur pose la photo');
reset role; select essai.personne();

-- UNE BOUTIQUE NE CHANGE PAS LE ROND DE TOUT LE MONDE. La règle ne lève
-- pas d'erreur : elle écarte la ligne, et rien n'est touché.
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.sans_effet(
  $$update public.categories set image = 'enseigne/categories/cat_mode_2.jpg' where id = 'cat_mode'$$,
  'l''administrateur d''une boutique ne la change pas');
select essai.sans_effet(
  $$update public.categories set image = '' where id = 'cat_mode'$$,
  'ni ne la retire');
reset role; select essai.personne();

set role anon;
select essai.sans_effet(
  $$update public.categories set image = '' where id = 'cat_mode'$$,
  'un visiteur non plus');
reset role;

select essai.egal(
  (select image from public.categories where id = 'cat_mode'),
  'enseigne/categories/cat_mode_1.jpg', 'la photo de l''enseigne est restée');

-- ---------------------------------------------------------
select essai.titre('2. Un chemin, jamais une adresse');

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
-- MÊME L'ENSEIGNE : ce n'est pas une question de droit, c'est la forme
-- de la donnée. L'application pose toujours un chemin de ce dossier.
select essai.refuse(
  $$update public.categories set image = 'https://pistage.example/pixel.png' where id = 'cat_mode'$$,
  'une adresse internet est refusée');
select essai.refuse(
  $$update public.categories set image = 'produits/photo.jpg' where id = 'cat_mode'$$,
  'un fichier d''un autre dossier aussi');
select essai.refuse(
  $$update public.categories set image = 'enseigne/logo.jpg' where id = 'cat_mode'$$,
  'même ailleurs chez l''enseigne');
select essai.refuse(
  $$update public.categories set image = 'enseigne/categories/../slider/x.jpg' where id = 'cat_mode'$$,
  'et on ne remonte pas d''un dossier');
select essai.refuse(
  $$update public.categories set image = 'enseigne/categories/..' where id = 'cat_mode'$$,
  'pas même avec « .. » tout seul');
select essai.refuse(
  $$update public.categories set image = 'enseigne/categories/' where id = 'cat_mode'$$,
  'ni avec le dossier sans fichier');
-- LE NOM QUE L'APPLICATION FABRIQUE, lui, passe : « cat_ » et des
-- lettres, des chiffres, un tiret.
update public.categories set image = 'enseigne/categories/cat_m2k9x-q4.jpg' where id = 'cat_mode';
select essai.egal(
  (select image from public.categories where id = 'cat_mode'),
  'enseigne/categories/cat_m2k9x-q4.jpg', 'le nom que fabrique l''application passe');
update public.categories set image = 'enseigne/categories/cat_mode_1.jpg' where id = 'cat_mode';
-- RETIRER LA PHOTO, C'EST LA VIDER : le rond retrouve son icône.
update public.categories set image = 'enseigne/categories/cat_maison_1.jpg' where id = 'cat_maison';
update public.categories set image = '' where id = 'cat_maison';
select essai.egal(
  (select image from public.categories where id = 'cat_maison'), '',
  'la retirer est permis : le rond retrouve son icône');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('2 bis. Le chemin d''une illustration d''avant la 3.56');

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
-- LA BASE EN LIGNE GARDE LES ILLUSTRATIONS EN 3D : les applications
-- déjà installées (3.54, 3.55) les montrent encore. Leur chemin reste
-- donc permis — les applications d'aujourd'hui ne le lisent plus.
update public.categories set image = 'img/categories/moto.jpg' where id = 'cat_auto';
select essai.egal(
  (select image from public.categories where id = 'cat_auto'),
  'img/categories/moto.jpg', 'le chemin d''une illustration d''avant reste permis');
-- LE DOSSIER DES APPLICATIONS, ET RIEN D'AUTRE : une application
-- d'avant lit ce chemin tel quel, à côté de sa page. Ni remonter vers
-- ses fichiers, ni sortir du dossier.
select essai.refuse(
  $$update public.categories set image = 'img/categories/../../index.html' where id = 'cat_auto'$$,
  'on ne remonte pas vers les fichiers de l''application');
select essai.refuse(
  $$update public.categories set image = 'img/categories/.moto.jpg' where id = 'cat_auto'$$,
  'ni vers un fichier caché');
select essai.refuse(
  $$update public.categories set image = 'img/categories/' where id = 'cat_auto'$$,
  'ni le dossier sans fichier');
select essai.refuse(
  $$update public.categories set image = 'img/moto.jpg' where id = 'cat_auto'$$,
  'ni un autre dossier de l''application');
select essai.refuse(
  $$update public.categories set image = 'icons/icon-512.png' where id = 'cat_auto'$$,
  'ni une autre image qu''elle contient');
update public.categories set image = '' where id = 'cat_auto';
reset role; select essai.personne();

-- UNE BOUTIQUE N'Y TOUCHE PAS DAVANTAGE.
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.sans_effet(
  $$update public.categories set image = 'img/categories/moto.jpg' where id = 'cat_auto'$$,
  'l''administrateur d''une boutique ne change pas l''illustration');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('3. Le fichier aussi est réservé');

select essai.devenir(:ENSEIGNE::uuid);
select essai.verifie(public.peut_deposer('enseigne/categories/cat_mode_1.jpg'),
  'le superadministrateur dépose dans « enseigne/categories/ »');
select essai.devenir(:CHEF::uuid);
select essai.verifie(not public.peut_deposer('enseigne/categories/cat_mode_1.jpg'),
  'l''administrateur d''une boutique, non');
select essai.personne();
select essai.verifie(not coalesce(public.peut_deposer('enseigne/categories/cat_mode_1.jpg'), false),
  'un visiteur non plus');

-- ---------------------------------------------------------
select essai.titre('4. Tout le monde la lit, sans compte');

set role anon;
select essai.egal(
  (select image from public.categories where id = 'cat_mode'),
  'enseigne/categories/cat_mode_1.jpg', 'un visiteur lit le chemin de la photo');
reset role;

-- ---------------------------------------------------------
select essai.titre('5. Le ménage du stockage ne la prend pas pour un orphelin');

-- Deux fichiers dans le dossier : la photo en place, et une ancienne
-- que plus rien ne désigne.
insert into storage.objects (bucket_id, name, metadata) values
  ('produits', 'enseigne/categories/cat_mode_1.jpg', '{"size": 41000, "mimetype": "image/jpeg"}'),
  ('produits', 'enseigne/categories/cat_mode_0.jpg', '{"size": 39000, "mimetype": "image/jpeg"}');

-- L'ÉTAT DES LIEUX TEL QU'IL PART CHEZ LE GÉRANT, lu dans le dépôt et
-- rangé dans une table : c'est SA liste qu'on éprouve, pas une copie.
\set rapport `cat "$RACINE/supabase/etat-du-stockage.sql"`
create temp table essai_rapport as :rapport

select essai.verifie(
  not exists (select 1 from essai_rapport
               where "section" = 'ORPHELINS'
                 and "quoi" = 'produits/enseigne/categories/cat_mode_1.jpg'),
  'la photo en place n''est pas « supprimable »');
select essai.verifie(
  exists (select 1 from essai_rapport
           where "section" = 'ORPHELINS'
             and "quoi" = 'produits/enseigne/categories/cat_mode_0.jpg'),
  'l''ancienne, que plus rien ne désigne, l''est');

delete from storage.objects where name like 'enseigne/categories/cat_mode_%';

-- ---------------------------------------------------------
select essai.titre('6. Les icônes désignées existent, dans les deux applications');

-- CE QUE CONTIENNENT LES DEUX DOSSIERS, lus sur le disque : une icône
-- que la base désigne et qu'aucune application n'embarque laisserait la
-- tuile sur un dessin d'un trait, sans que personne ne sache pourquoi.
\set icones_client `ls "$RACINE/client/img/pictos" | tr '\n' ' '`
\set icones_admin `ls "$RACINE/admin/img/pictos" | tr '\n' ' '`
select essai.verifie(
  not exists (select 1 from essai_icones i
               where position(' ' || i.icone || '.png ' in ' ' || :'icones_client') = 0),
  'chacune est un fichier de l''application cliente');
select essai.verifie(
  not exists (select 1 from essai_icones i
               where position(' ' || i.icone || '.png ' in ' ' || :'icones_admin') = 0),
  'et de l''admin');
select essai.egal(:'icones_client'::text, :'icones_admin'::text,
  'les deux applications ont les mêmes icônes');

-- ---------------------------------------------------------
select essai.titre('7. Rejouer les fichiers ne défait rien');

-- L'enseigne a retiré la photo de « Maison » (plus haut) et posé la
-- sienne sur « Mode ». Rejouer « categories-photos.sql » — ce que fait
-- quiconque le recolle — ne doit rien remettre.
update public.categories set image = 'enseigne/categories/cat_mode_1.jpg' where id = 'cat_mode';
\set fichier `echo "$RACINE/supabase/categories-photos.sql"`
\o /dev/null
set client_min_messages = warning;
\i :fichier
set client_min_messages = notice;
\o
select essai.egal(
  (select image from public.categories where id = 'cat_maison'), '',
  'la photo retirée ne revient pas');
select essai.egal(
  (select image from public.categories where id = 'cat_mode'),
  'enseigne/categories/cat_mode_1.jpg', 'la photo posée reste');

-- DEPUIS LA 3.56, IL NE POSE PLUS D'ILLUSTRATION : même sur une base qui
-- n'a encore aucune image, les tuiles montrent leur icône.
update public.categories set image = '';
\o /dev/null
set client_min_messages = warning;
\i :fichier
set client_min_messages = notice;
\o
select essai.egal(
  (select count(*)::text from public.categories where image <> ''),
  '0', 'sur une base sans image, il n''en pose aucune');

-- LA BASE EN LIGNE AVANT LA 3.56 : les icônes d'un trait, et les
-- illustrations en 3D par-dessus. « categories-icones.sql » doit donner
-- à chacune la sienne, sans toucher à l'image.
update public.categories c set icone = v.ancienne
  from (values ('cat_mode', 'tshirt'), ('cat_hightech', 'portable'), ('cat_auto', 'voiture'),
               ('cat_maison', 'maison'), ('cat_beaute', 'goutte'), ('cat_restauration', 'couverts'),
               ('cat_supermarche', 'chariot'), ('cat_logiciels', 'portable'), ('cat_bebe', 'cadeau'),
               ('cat_sport', 'ballon'), ('cat_bricolage', 'magasin'), ('cat_livres', 'livre'),
               ('cat_bijoux', 'diamant'), ('cat_animaux', 'patte'), ('cat_services', 'sacoche'))
       as v(id, ancienne)
 where c.id = v.id;
update public.categories set image = 'img/categories/robe.jpg' where id = 'cat_mode';
\set fichier `echo "$RACINE/supabase/categories-icones.sql"`
\o /dev/null
set client_min_messages = warning;
\i :fichier
set client_min_messages = notice;
\o
-- Bijoux et Bricolage reçoivent ici celles de Mode et d'Immobilier :
-- leurs icônes à elles viennent avec « categories-rangement.sql »
-- (voir 99s-categories-rangement.sql).
select essai.egal(
  (select count(*)::text from public.categories c join essai_icones i using (id)
    where c.icone = case c.id when 'cat_bijoux' then 'mode'
                              when 'cat_bricolage' then 'immobilier' else i.icone end),
  '29', 'chacune des quinze reçoit son icône, et les quatorze nouvelles gardent la leur');
select essai.egal(
  (select image from public.categories where id = 'cat_mode'),
  'img/categories/robe.jpg', 'l''illustration d''avant reste, pour les applications installées');

-- UNE ICÔNE CHOISIE DEPUIS DANS L'ADMIN NE SE DÉFAIT PAS : le fichier ne
-- touche qu'une catégorie qui a encore son ancienne icône.
update public.categories set icone = 'services' where id = 'cat_auto';
\o /dev/null
set client_min_messages = warning;
\i :fichier
set client_min_messages = notice;
\o
select essai.egal(
  (select icone from public.categories where id = 'cat_auto'),
  'services', 'rejoué, il ne défait pas un choix fait dans l''admin');

-- Les icônes telles que la base les a semées.
update public.categories c set icone = i.icone from essai_icones i where i.id = c.id;

-- On rend la base comme on l'a trouvée.
update public.categories c set image = a.image
  from essai_images_avant a where a.id = c.id;
