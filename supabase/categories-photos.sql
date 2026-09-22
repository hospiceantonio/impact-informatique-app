-- =========================================================
-- BIZZOO — la photo d'une catégorie
--
-- À exécuter UNE FOIS dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
-- Se rejoue sans dommage.
--
-- CE QUE ÇA AJOUTE. Sur la DA, les ronds des catégories de
-- l'accueil portent une photo. Chaque catégorie en reçoit une,
-- facultative, posée par le superadministrateur depuis
-- l'application admin (Catégories → Modifier). Sans photo, le
-- rond garde son icône et sa couleur.
--
-- UN CHEMIN, JAMAIS UNE ADRESSE, et dans un seul dossier du
-- seau : « enseigne/categories/ ». Le stockage le réserve déjà
-- au superadministrateur — « enseigne/ » l'est depuis le slider
-- de l'enseigne —, et la liste des catégories aussi. Aucune
-- règle de stockage n'est donc à changer.
-- =========================================================

alter table public.categories add column if not exists image text not null default '';
alter table public.categories drop constraint if exists categories_image_chemin;
alter table public.categories add constraint categories_image_chemin
  -- Le dossier, puis un nom qui commence par une lettre ou un chiffre
  -- et ne contient rien hors de [A-Za-z0-9._-] : ni « / » pour
  -- descendre, ni « : » pour une adresse, ni « .. » pour remonter.
  check (image = '' or (image like 'enseigne/categories/_%'
                        and substr(image, 21, 1) ~ '[A-Za-z0-9]'
                        and substr(image, 21) !~ '[^A-Za-z0-9._-]'));

-- Vérification : la colonne, et la règle qui la garde.
select
  exists (select 1 from information_schema.columns
           where table_schema = 'public' and table_name = 'categories'
             and column_name = 'image')                         as "Colonne image",
  exists (select 1 from pg_constraint
           where conname = 'categories_image_chemin'
             and conrelid = 'public.categories'::regclass)     as "Chemin gardé";
