-- =========================================================
-- Plus d'orange dans les couleurs des boutiques (4.4.0)
--
-- Ce qu'on prouve :
--   1. le fichier fait passer l'orange de l'ancienne charte et l'ocre au
--      turquoise de la palette, quelle que soit leur casse ;
--   2. il laisse les autres couleurs choisies ;
--   3. relancé, il ne change plus rien.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

select essai.titre('Le décor : une boutique orange, une catégorie ocre, une boutique rouge');
insert into public.boutiques (id, nom, secteur, devise, actif, ordre, categorie_id, couleur)
values ('bou_or2', 'BOUTIQUE ORANGE 2', 'Essai', 'FCFA', true, 99, 'cat_hightech', '#f96302'),
       ('bou_rouge', 'BOUTIQUE ROUGE', 'Essai', 'FCFA', true, 99, 'cat_hightech', '#E62329')
on conflict (id) do update set couleur = excluded.couleur;
insert into public.categories (id, nom, icone, ordre, couleur) values ('cat_ocre', 'Catégorie ocre', 'magasin', 99, '#9A6B00')
on conflict (id) do update set couleur = excluded.couleur;

\set fichier `echo "$RACINE/supabase/plus-d-orange.sql"`
\o /dev/null
\i :fichier
\o

select essai.titre('1. L''orange et l''ocre passent au turquoise');
select essai.egal((select couleur from public.boutiques where id = 'bou_or2'), '#0B7C8C', 'l''orange (en minuscules) : turquoise');
select essai.egal((select couleur from public.categories where id = 'cat_ocre'), '#0B7C8C', 'l''ocre : turquoise');

select essai.titre('2. Les autres couleurs ne bougent pas');
select essai.egal((select couleur from public.boutiques where id = 'bou_rouge'), '#E62329', 'le rouge choisi : intact');

select essai.titre('3. Plus aucun orange, et relancer ne change rien');
\o /dev/null
\i :fichier
\o
select essai.egal((select count(*)::int from public.boutiques where upper(couleur) in ('#F96302', '#9A6B00'))
  + (select count(*)::int from public.categories where upper(couleur) in ('#F96302', '#9A6B00')), 0,
  'aucune boutique ni catégorie (0)');
