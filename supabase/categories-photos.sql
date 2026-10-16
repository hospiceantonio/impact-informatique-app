-- =========================================================
-- BIZZOO — la photo d'une catégorie
--
-- À exécuter UNE FOIS dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
-- Se rejoue sans dommage.
--
-- CE QUE ÇA AJOUTE. Chaque catégorie peut recevoir une photo,
-- facultative, que le superadministrateur choisit depuis
-- l'application admin (Catégories → Modifier). Elle prend la
-- place de l'icône de la tuile ; sans photo, l'icône reste.
--
-- UN CHEMIN, JAMAIS UNE ADRESSE, et dans l'un de deux dossiers :
--
--   « enseigne/categories/ », dans le seau : une photo déposée
--     depuis l'admin. Le stockage réserve déjà « enseigne/ » au
--     superadministrateur — depuis le slider de l'enseigne —, et
--     la liste des catégories aussi. Aucune règle de stockage
--     n'est donc à changer ;
--   « img/categories/ » : les illustrations en 3D qui voyageaient
--     avec les applications jusqu'à la 3.55. La base en ligne les
--     a reçues de ce fichier, et les garde pour les applications
--     déjà installées ; depuis la 3.56, ce fichier n'en pose plus
--     (les tuiles montrent leur icône, voir
--     « categories-icones.sql »).
-- =========================================================

alter table public.categories add column if not exists image text not null default '';
alter table public.categories drop constraint if exists categories_image_chemin;
alter table public.categories add constraint categories_image_chemin
  -- Le dossier, puis un nom qui commence par une lettre ou un chiffre
  -- et ne contient rien hors de [A-Za-z0-9._-] : ni « / » pour
  -- descendre, ni « : » pour une adresse, ni « .. » pour remonter.
  check (image = ''
         or (image like 'enseigne/categories/_%'
             and substr(image, 21, 1) ~ '[A-Za-z0-9]'
             and substr(image, 21) !~ '[^A-Za-z0-9._-]')
         or (image like 'img/categories/_%'
             and substr(image, 16, 1) ~ '[A-Za-z0-9]'
             and substr(image, 16) !~ '[^A-Za-z0-9._-]'));

-- Vérification : la colonne, la règle qui la garde, et les images
-- posées.
select
  exists (select 1 from information_schema.columns
           where table_schema = 'public' and table_name = 'categories'
             and column_name = 'image')                         as "Colonne image",
  exists (select 1 from pg_constraint
           where conname = 'categories_image_chemin'
             and conrelid = 'public.categories'::regclass
             and pg_get_constraintdef(oid) like '%img/categories/%') as "Chemin gardé",
  (select count(*) from public.categories where image <> '')      as "Catégories avec une image";
