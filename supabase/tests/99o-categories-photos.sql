-- =========================================================
-- La photo d'une catégorie
--
-- CE QU'ON AJOUTE. Sur la DA, les ronds des catégories de
-- l'accueil portent une photo. Une colonne « image » la
-- range : un CHEMIN dans le seau, dans le seul dossier
-- « enseigne/categories/ ».
--
-- Cinq choses à prouver :
--
--   1. L'ENSEIGNE SEULE LA POSE, comme elle seule écrit la
--      liste. Une boutique ne change pas le rond de tout le
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
--      une suppression ne se rattrape pas.
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
-- LE JOUR DE LA MISE À JOUR, AUCUNE N'A DE PHOTO : le rond garde son
-- icône. Une valeur nulle obligerait chaque écran à s'en méfier.
select essai.verifie(
  not exists (select 1 from public.categories where image is null or image <> ''),
  'aucune n''a encore de photo, et aucune n''est nulle');

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

-- On rend la base comme on l'a trouvée.
delete from storage.objects where name like 'enseigne/categories/cat_mode_%';
update public.categories set image = '' where id = 'cat_mode';
