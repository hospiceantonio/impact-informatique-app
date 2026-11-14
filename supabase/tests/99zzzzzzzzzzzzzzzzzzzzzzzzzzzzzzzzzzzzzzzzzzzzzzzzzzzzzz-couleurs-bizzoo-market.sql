-- =========================================================
-- Plus rien de l'ancienne charte dans les couleurs (4.2.0)
--
-- Ce qu'on prouve :
--   1. une boutique et une catégorie créées sans couleur prennent le
--      turquoise de BIZZOO Market ;
--   2. le fichier fait passer les anciens bleus de BIZZOO au turquoise,
--      et laisse les couleurs choisies par les boutiques ;
--   3. il ne reste aucun ancien bleu.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

select essai.titre('1. Sans couleur choisie : le turquoise');
insert into public.boutiques (id, nom, secteur, devise, actif, ordre, categorie_id)
values ('bou_coul', 'BOUTIQUE COULEUR', 'Essai', 'FCFA', true, 98, 'cat_hightech') on conflict (id) do nothing;
select essai.egal((select couleur from public.boutiques where id = 'bou_coul'), '#007F7C',
  'une boutique créée sans couleur : #007F7C');
insert into public.categories (id, nom, icone, ordre) values ('cat_coul', 'Catégorie couleur', 'magasin', 98)
on conflict (id) do nothing;
select essai.egal((select couleur from public.categories where id = 'cat_coul'), '#007F7C',
  'une catégorie créée sans couleur : #007F7C');

select essai.titre('2. Les anciens bleus passent au turquoise, le reste ne bouge pas');
update public.boutiques set couleur = '#2550B7' where id = 'bou_coul';
update public.categories set couleur = '#0b5cf5' where id = 'cat_coul';
insert into public.boutiques (id, nom, secteur, devise, actif, ordre, categorie_id, couleur)
values ('bou_coul_or', 'BOUTIQUE ORANGE', 'Essai', 'FCFA', true, 99, 'cat_hightech', '#F96302') on conflict (id) do nothing;
\set fichier `echo "$RACINE/supabase/couleurs-bizzoo-market.sql"`
\o /dev/null
\i :fichier
\o
select essai.egal((select couleur from public.boutiques where id = 'bou_coul'), '#007F7C', 'l''ancien #2550B7 : turquoise');
select essai.egal((select couleur from public.categories where id = 'cat_coul'), '#007F7C', 'l''ancien #0B5CF5 (en minuscules) : turquoise');
select essai.egal((select couleur from public.boutiques where id = 'bou_coul_or'), '#F96302', 'l''orange choisi par une boutique : intact');

select essai.titre('3. Plus aucun ancien bleu');
select essai.egal((select count(*)::int from (
    select couleur from public.boutiques union all select couleur from public.categories) x
   where upper(x.couleur) in ('#2550B7', '#0B5CF5', '#1176D8', '#0047D9')), 0, 'aucune boutique ni catégorie');
