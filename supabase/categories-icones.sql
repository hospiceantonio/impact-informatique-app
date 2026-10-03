-- =========================================================
-- BIZZOO — les icônes des catégories (3.56)
--
-- À exécuter UNE FOIS dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
-- Se rejoue sans dommage.
--
-- CE QUE ÇA CHANGE. Les tuiles des catégories prennent les icônes
-- de l'image choisie par l'enseigne — les douze telles quelles,
-- et quatre construites dans son style pour Bébé & Enfant,
-- Sport & Loisirs, Livres & Éducation et Animaux. Elles sont dans
-- les deux applications (« img/pictos/ ») ; la colonne « icone »
-- dit laquelle. Ce fichier donne la sienne à chaque catégorie de
-- BIZZOO.
--
-- L'IMAGE N'EST PAS TOUCHÉE. Les applications déjà installées
-- (3.54, 3.55) montrent leur illustration en 3D
-- (« img/categories/… ») PAR-DESSUS l'icône : pour elles, rien
-- ne change à l'écran. Les nouvelles ne lisent plus ces chemins,
-- et montrent l'icône.
--
-- UNE CATÉGORIE À LA FOIS, ET SEULEMENT SI ELLE A ENCORE SON
-- ANCIENNE ICÔNE : rejouer le fichier ne défait jamais une icône
-- choisie depuis dans l'admin.
-- =========================================================

alter table public.categories add column if not exists icone text not null default 'categories';

update public.categories c
   set icone = v.nouvelle
  from (values
    -- La liste de BIZZOO, telle que les fichiers d'avant l'ont semée
    -- (l'icône de la base en ligne quand l'enseigne l'avait changée).
    ('cat_hightech',       'portable',   'informatique'),
    ('cat_logiciels',      'portable',   'informatique'),
    ('cat_logiciels',      'ecran',      'informatique'),
    ('cat_auto',           'voiture',    'auto-moto'),
    ('cat_mode',           'tshirt',     'mode'),
    ('cat_maison',         'maison',     'maison-deco'),
    ('cat_beaute',         'goutte',     'beaute'),
    ('cat_restauration',   'couverts',   'restauration'),
    ('cat_supermarche',    'chariot',    'alimentation'),
    ('cat_bebe',           'cadeau',     'bebe-enfant'),
    ('cat_sport',          'ballon',     'sport-loisirs'),
    ('cat_bricolage',      'outils',     'immobilier'),
    ('cat_bricolage',      'magasin',    'immobilier'),
    ('cat_livres',         'livre',      'livres-education'),
    ('cat_bijoux',         'diamant',    'mode'),
    ('cat_animaux',        'patte',      'animaux'),
    ('cat_services',       'sacoche',    'services'),
    -- Deux catégories créées depuis l'admin sur la base en ligne :
    -- « Électro-ménagers & Cuisinière » et « Prestataires de
    -- services ». Ailleurs, ces lignes ne trouvent rien.
    ('cat_muifjqpbju094q', 'couverts',   'electromenager'),
    ('cat_muflx6zvfjj9u8', 'categories', 'services')
  ) as v(id, ancienne, nouvelle)
 where c.id = v.id
   and c.icone = v.ancienne;

-- Vérification : chaque catégorie, son icône, et son image d'avant
-- (gardée pour les applications installées).
select nom as "Catégorie", icone as "Icône", image as "Image d'avant"
  from public.categories
 where boutique_id is null
 order by ordre, nom;
