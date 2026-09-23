-- =========================================================
-- BIZZOO — la photo d'une catégorie
--
-- À exécuter UNE FOIS dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
-- Se rejoue sans dommage.
--
-- CE QUE ÇA AJOUTE. Sur la DA, les ronds des catégories de
-- l'accueil portent une photo. Chaque catégorie en reçoit une,
-- facultative, que le superadministrateur choisit depuis
-- l'application admin (Catégories → Modifier). Sans photo, le
-- rond garde son icône et sa couleur.
--
-- UN CHEMIN, JAMAIS UNE ADRESSE, et dans l'un de deux dossiers :
--
--   « enseigne/categories/ », dans le seau : une photo déposée
--     depuis l'admin. Le stockage réserve déjà « enseigne/ » au
--     superadministrateur — depuis le slider de l'enseigne —, et
--     la liste des catégories aussi. Aucune règle de stockage
--     n'est donc à changer ;
--   « img/categories/ », dans l'application : les illustrations
--     qui voyagent avec elle, et s'affichent sans réseau.
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

-- LES ILLUSTRATIONS DE BIZZOO, une par catégorie de la liste.
--
-- UNE SEULE FOIS : tant qu'aucune catégorie n'a encore d'image. Dès
-- que l'enseigne en a posé, retiré ou changé une, ce bloc ne touche
-- plus à rien — rejouer le fichier ne doit jamais défaire un choix
-- fait dans l'admin.
update public.categories c
   set image = v.image
  from (values
    ('cat_mode',         'img/categories/robe.jpg'),
    ('cat_hightech',     'img/categories/ordinateur.jpg'),
    ('cat_auto',         'img/categories/voiture.jpg'),
    ('cat_maison',       'img/categories/maison.jpg'),
    ('cat_beaute',       'img/categories/rouge-a-levres.jpg'),
    ('cat_restauration', 'img/categories/marmite.jpg'),
    ('cat_supermarche',  'img/categories/chariot.jpg'),
    ('cat_logiciels',    'img/categories/ecran.jpg'),
    ('cat_bebe',         'img/categories/nounours.jpg'),
    ('cat_sport',        'img/categories/ballon.jpg'),
    ('cat_bricolage',    'img/categories/briques.jpg'),
    ('cat_livres',       'img/categories/livres.jpg'),
    ('cat_bijoux',       'img/categories/bague.jpg'),
    ('cat_animaux',      'img/categories/chien.jpg'),
    ('cat_services',     'img/categories/boite-a-outils.jpg')
  ) as v(id, image)
 where c.id = v.id
   and c.image = ''
   and not exists (select 1 from public.categories x where x.image <> '');

-- Vérification : la colonne, la règle qui la garde, et les ronds.
select
  exists (select 1 from information_schema.columns
           where table_schema = 'public' and table_name = 'categories'
             and column_name = 'image')                         as "Colonne image",
  exists (select 1 from pg_constraint
           where conname = 'categories_image_chemin'
             and conrelid = 'public.categories'::regclass
             and pg_get_constraintdef(oid) like '%img/categories/%') as "Chemin gardé",
  (select count(*) from public.categories where image <> '')      as "Catégories illustrées";
