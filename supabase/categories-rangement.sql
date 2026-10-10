-- =========================================================
-- BIZZOO — les catégories rangées (3.56)
--
-- À exécuter UNE FOIS dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
-- Se rejoue sans dommage : la seconde fois, il ne fait rien.
--
-- CE QUE ÇA CHANGE. L'enseigne a choisi deux nouvelles planches
-- d'icônes, et les catégories qui vont avec. Ce fichier les
-- rapproche de la liste existante et range le tout :
--
--   1. QUATORZE CATÉGORIES NOUVELLES, chacune avec son icône et
--      quelques rayons de départ, que l'enseigne retouche dans
--      l'admin : Énergie solaire & Électricité, Sécurité &
--      Surveillance, Formation & Cours, Jardinage & Espaces verts,
--      Transport & Location, Agriculture & Élevage, Musique &
--      Instruments, Artisanat & Produits locaux, Cadeaux & Fêtes,
--      Événementiel & Décoration, Équipements de bureau, Matériel
--      professionnel, Imprimerie & Communication, Grossistes &
--      Fournisseurs ;
--   2. LES NOMS DES PLANCHES pour celles qui existaient déjà
--      (« Bébé & Enfants », « Livres & Fournitures scolaires »,
--      « Bricolage & Matériaux »), et ceux qu'impose le rangement :
--      « Maison & Déco » (le jardinage a sa catégorie),
--      « Restauration » (l'alimentation, c'est le supermarché),
--      « Services & Prestataires » (les deux n'en font plus qu'une),
--      « Informatique & Électronique » (le « & » de toutes) ;
--   3. DES RAYONS VIDES CHANGENT DE CATÉGORIE, pour qu'un même rayon
--      ne se trouve pas à deux endroits : Électricité → Énergie
--      solaire & Électricité, Formations → Formation & Cours,
--      Jardinage → Jardinage & Espaces verts, Épicerie et Produits
--      frais → Supermarché & Épicerie. « Prestataires de services »
--      verse ses rayons dans « Services & Prestataires », puis
--      s'efface ; son « Informaticien » y remplace « Informatique » ;
--   4. DEUX ICÔNES À ELLES : Bijoux & Accessoires et Bricolage &
--      Matériaux portaient celles de Mode et d'Immobilier ;
--   5. UN ORDRE PAR THÈME : high-tech, enfants et école, maison,
--      mobilité, mode, alimentation, loisirs, professionnels,
--      services. Les huit de l'accueil restent les mêmes.
--
-- RIEN NE SE PERD. Un rayon qui a des produits ne bouge pas ; une
-- catégorie qui a des produits ou des boutiques ne s'efface pas.
-- Un nom ou une icône que l'enseigne a déjà changés ne sont pas
-- touchés : chaque changement attend l'ancienne valeur.
--
-- UNE SEULE FOIS. Dès que l'une des quatorze existe, le fichier ne
-- fait plus rien : le rejouer ne défait jamais un nom, un ordre ou
-- une suppression décidés depuis dans l'admin.
--
-- LES APPLICATIONS DÉJÀ INSTALLÉES (3.54, 3.55) n'ont pas les
-- nouvelles icônes. Elles montrent une illustration en 3D d'avant
-- (« img/categories/… ») quand l'une dit la même chose — un panier
-- tressé, une plante en pot, une mallette, des outils, une moto, des
-- livres —, sinon l'icône d'un trait du même nom (energie, cadeau,
-- imprimante) ; les applications 3.56 ne lisent pas ces chemins, et
-- montrent l'icône de la planche.
-- =========================================================

alter table public.categories add column if not exists icone    text not null default 'categories';
alter table public.categories add column if not exists couleur  text not null default '#0B5CF5';
alter table public.categories add column if not exists en_avant boolean not null default false;
alter table public.categories add column if not exists image    text not null default '';

do $$
declare
  nouvelles text[] := array[
    'cat_energie', 'cat_securite', 'cat_formation', 'cat_jardinage', 'cat_transport',
    'cat_agriculture', 'cat_musique', 'cat_artisanat', 'cat_cadeaux', 'cat_evenementiel',
    'cat_bureau', 'cat_materiel_pro', 'cat_imprimerie', 'cat_grossistes'];
  -- L'ORDRE PAR THÈME. « cat_muifjqpbju094q » est « Électro-ménagers &
  -- Cuisinière », créée depuis l'admin sur la base en ligne ; ailleurs,
  -- elle n'existe pas et sa place reste vide.
  rangement text[] := array[
    'cat_hightech', 'cat_logiciels', 'cat_muifjqpbju094q', 'cat_energie', 'cat_securite',
    'cat_bebe', 'cat_livres', 'cat_formation',
    'cat_maison', 'cat_jardinage', 'cat_bricolage',
    'cat_auto', 'cat_transport',
    'cat_mode', 'cat_bijoux', 'cat_beaute',
    'cat_supermarche', 'cat_restauration', 'cat_agriculture', 'cat_animaux',
    'cat_sport', 'cat_musique', 'cat_artisanat', 'cat_cadeaux', 'cat_evenementiel',
    'cat_bureau', 'cat_materiel_pro', 'cat_imprimerie', 'cat_grossistes',
    'cat_services'];
  suite int;
begin
  if exists (select 1 from public.categories where id = any(nouvelles)) then
    raise notice 'Les catégories sont déjà rangées : rien à faire.';
    return;
  end if;

  -- ---------- 1. Les quatorze nouvelles ----------
  -- « image » : l'illustration d'avant qui dit la même chose, pour les
  -- applications 3.54 et 3.55 seules.
  insert into public.categories (id, boutique_id, nom, icone, couleur, en_avant, ordre, image) values
    ('cat_energie',      null, 'Énergie solaire & Électricité', 'energie',      '#2550B7', false,  4, ''),
    ('cat_securite',     null, 'Sécurité & Surveillance',       'securite',     '#2550B7', false,  5, ''),
    ('cat_formation',    null, 'Formation & Cours',             'formation',    '#2550B7', false,  8, 'img/categories/livres.jpg'),
    ('cat_jardinage',    null, 'Jardinage & Espaces verts',     'jardinage',    '#2550B7', false, 10, 'img/categories/plante.jpg'),
    ('cat_transport',    null, 'Transport & Location',          'transport',    '#2550B7', false, 13, 'img/categories/moto.jpg'),
    ('cat_agriculture',  null, 'Agriculture & Élevage',         'agriculture',  '#2550B7', false, 19, 'img/categories/plante.jpg'),
    ('cat_musique',      null, 'Musique & Instruments',         'musique',      '#2550B7', false, 22, ''),
    ('cat_artisanat',    null, 'Artisanat & Produits locaux',   'artisanat',    '#2550B7', false, 23, 'img/categories/panier.jpg'),
    ('cat_cadeaux',      null, 'Cadeaux & Fêtes',               'cadeau',       '#2550B7', false, 24, ''),
    ('cat_evenementiel', null, 'Événementiel & Décoration',     'evenementiel', '#2550B7', false, 25, ''),
    ('cat_bureau',       null, 'Équipements de bureau',         'bureau',       '#2550B7', false, 26, 'img/categories/mallette.jpg'),
    ('cat_materiel_pro', null, 'Matériel professionnel',        'materiel-pro', '#2550B7', false, 27, 'img/categories/outils.jpg'),
    ('cat_imprimerie',   null, 'Imprimerie & Communication',    'imprimante',   '#2550B7', false, 28, ''),
    ('cat_grossistes',   null, 'Grossistes & Fournisseurs',     'grossistes',   '#2550B7', false, 29, '')
  on conflict (id) do nothing;

  -- Leurs rayons de départ. La place 1 de Formation & Cours et de
  -- Jardinage & Espaces verts, et la 5 d'Énergie solaire, attendent le
  -- rayon qui y déménage (plus bas).
  insert into public.sous_categories (id, categorie_id, nom, ordre) values
    ('sc_energie_solaire',        'cat_energie',      'Panneaux & kits solaires',       1),
    ('sc_energie_batteries',      'cat_energie',      'Batteries & onduleurs',          2),
    ('sc_energie_groupes',        'cat_energie',      'Groupes électrogènes',           3),
    ('sc_energie_eclairage',      'cat_energie',      'Éclairage',                      4),
    ('sc_securite_cameras',       'cat_securite',     'Caméras de surveillance',        1),
    ('sc_securite_alarmes',       'cat_securite',     'Alarmes & détecteurs',           2),
    ('sc_securite_acces',         'cat_securite',     'Serrures & contrôle d''accès',   3),
    ('sc_formation_cours',        'cat_formation',    'Cours particuliers',             2),
    ('sc_formation_langues',      'cat_formation',    'Langues',                        3),
    ('sc_formation_informatique', 'cat_formation',    'Informatique & bureautique',     4),
    ('sc_jardinage_plantes',      'cat_jardinage',    'Plantes & fleurs',               2),
    ('sc_jardinage_outils',       'cat_jardinage',    'Outils de jardin',               3),
    ('sc_jardinage_entretien',    'cat_jardinage',    'Entretien d''espaces verts',     4),
    ('sc_transport_location',     'cat_transport',    'Location de véhicules',          1),
    ('sc_transport_demenagement', 'cat_transport',    'Déménagement',                   2),
    ('sc_transport_marchandises', 'cat_transport',    'Transport de marchandises',      3),
    ('sc_transport_coursiers',    'cat_transport',    'Livraison & coursiers',          4),
    ('sc_agri_semences',          'cat_agriculture',  'Semences & plants',              1),
    ('sc_agri_engrais',           'cat_agriculture',  'Engrais & traitements',          2),
    ('sc_agri_materiel',          'cat_agriculture',  'Matériel agricole',              3),
    ('sc_agri_elevage',           'cat_agriculture',  'Élevage',                        4),
    ('sc_agri_produits',          'cat_agriculture',  'Produits de la ferme',           5),
    ('sc_musique_instruments',    'cat_musique',      'Instruments de musique',         1),
    ('sc_musique_sono',           'cat_musique',      'Sonorisation',                   2),
    ('sc_musique_accessoires',    'cat_musique',      'Accessoires',                    3),
    ('sc_artisanat_objets',       'cat_artisanat',    'Objets d''art & artisanat',      1),
    ('sc_artisanat_tissus',       'cat_artisanat',    'Tissus & pagnes',                2),
    ('sc_artisanat_locaux',       'cat_artisanat',    'Produits locaux',                3),
    ('sc_cadeaux_cadeaux',        'cat_cadeaux',      'Cadeaux',                        1),
    ('sc_cadeaux_fete',           'cat_cadeaux',      'Articles de fête',               2),
    ('sc_cadeaux_emballages',     'cat_cadeaux',      'Emballages & cartes',            3),
    ('sc_event_decoration',       'cat_evenementiel', 'Décoration d''événements',       1),
    ('sc_event_location',         'cat_evenementiel', 'Location de matériel',           2),
    ('sc_event_organisation',     'cat_evenementiel', 'Organisation d''événements',     3),
    ('sc_bureau_mobilier',        'cat_bureau',       'Mobilier de bureau',             1),
    ('sc_bureau_materiel',        'cat_bureau',       'Matériel de bureau',             2),
    ('sc_bureau_fournitures',     'cat_bureau',       'Fournitures de bureau',          3),
    ('sc_pro_restauration',       'cat_materiel_pro', 'Équipements de restauration',    1),
    ('sc_pro_salon',              'cat_materiel_pro', 'Équipements de salon & beauté',  2),
    ('sc_pro_machines',           'cat_materiel_pro', 'Machines professionnelles',      3),
    ('sc_pro_medical',            'cat_materiel_pro', 'Matériel médical',               4),
    ('sc_imprimerie_impression',  'cat_imprimerie',   'Impression',                     1),
    ('sc_imprimerie_enseignes',   'cat_imprimerie',   'Enseignes & signalétique',       2),
    ('sc_imprimerie_objets',      'cat_imprimerie',   'Objets publicitaires',           3),
    ('sc_imprimerie_graphisme',   'cat_imprimerie',   'Graphisme & communication',      4),
    ('sc_gros_alimentation',      'cat_grossistes',   'Alimentation en gros',           1),
    ('sc_gros_boissons',          'cat_grossistes',   'Boissons en gros',               2),
    ('sc_gros_hygiene',           'cat_grossistes',   'Hygiène & entretien en gros',    3),
    ('sc_gros_emballages',        'cat_grossistes',   'Emballages',                     4)
  on conflict (id) do nothing;

  -- ---------- 2. Les noms ----------
  -- Seulement si la catégorie porte encore l'un de ses anciens noms :
  -- celui de la base en ligne, ou celui des fichiers d'avant.
  update public.categories c
     set nom = v.nouveau
    from (values
      ('cat_hightech',     'Informatique et électronique',           'Informatique & Électronique'),
      ('cat_hightech',     'High-Tech & Électronique',               'Informatique & Électronique'),
      ('cat_logiciels',    'Logiciels & Solutions professionnelles', 'Logiciels & Solutions pro'),
      ('cat_bebe',         'Bébé & Enfant',                          'Bébé & Enfants'),
      ('cat_livres',       'Livres, Éducation & Fournitures',        'Livres & Fournitures scolaires'),
      ('cat_maison',       'Maison & Jardin',                        'Maison & Déco'),
      ('cat_bricolage',    'Btp et matériaux.',                      'Bricolage & Matériaux'),
      ('cat_restauration', 'Restauration & Alimentation',            'Restauration'),
      ('cat_services',     'Services',                               'Services & Prestataires')
    ) as v(id, ancien, nouveau)
   where c.id = v.id
     and c.nom = v.ancien;

  -- ---------- 3. Deux icônes à elles ----------
  update public.categories c
     set icone = v.nouvelle
    from (values
      ('cat_bijoux',    'mode',       'bijoux'),
      ('cat_bijoux',    'diamant',    'bijoux'),
      ('cat_bricolage', 'immobilier', 'bricolage'),
      ('cat_bricolage', 'outils',     'bricolage'),
      ('cat_bricolage', 'magasin',    'bricolage')
    ) as v(id, ancienne, nouvelle)
   where c.id = v.id
     and c.icone = v.ancienne;

  -- ---------- 4. Les rayons qui déménagent ----------
  -- VIDES SEULEMENT : un produit est rangé dans le secteur de sa
  -- boutique, et ne doit pas en sortir sans qu'elle le sache.
  update public.sous_categories s
     set categorie_id = v.nouvelle, ordre = v.ordre
    from (values
      ('sc_brico_electricite', 'cat_bricolage', 'cat_energie',   5),
      ('sc_livres_formations', 'cat_livres',    'cat_formation', 1),
      ('sc_maison_jardinage',  'cat_maison',    'cat_jardinage', 1)
    ) as v(id, ancienne, nouvelle, ordre)
   where s.id = v.id
     and s.categorie_id = v.ancienne
     and not exists (select 1 from public.produits p where p.sous_categorie_id = s.id);

  -- Épicerie et Produits frais rejoignent le supermarché, après ses
  -- rayons à lui.
  select coalesce(max(ordre), 0) into suite
    from public.sous_categories where categorie_id = 'cat_supermarche';
  update public.sous_categories s
     set categorie_id = 'cat_supermarche', ordre = suite + v.rang
    from (values ('sc_resto_epicerie', 1), ('sc_resto_frais', 2)) as v(id, rang)
   where s.id = v.id
     and s.categorie_id = 'cat_restauration'
     and exists (select 1 from public.categories where id = 'cat_supermarche')
     and not exists (select 1 from public.produits p where p.sous_categorie_id = s.id);

  -- « Prestataires de services » (créée depuis l'admin sur la base en
  -- ligne) verse ses rayons dans « Services & Prestataires », à la
  -- suite, puis s'efface — si personne ne s'y range.
  if exists (select 1 from public.categories where id = 'cat_muflx6zvfjj9u8')
     and exists (select 1 from public.categories where id = 'cat_services')
     and not exists (select 1 from public.boutiques where categorie_id = 'cat_muflx6zvfjj9u8')
     and not exists (select 1 from public.produits where categorie_id = 'cat_muflx6zvfjj9u8')
     and not exists (select 1 from public.produits p
                       join public.sous_categories s on s.id = p.sous_categorie_id
                      where s.categorie_id = 'cat_muflx6zvfjj9u8') then
    select coalesce(max(ordre), 0) into suite
      from public.sous_categories where categorie_id = 'cat_services';
    update public.sous_categories s
       set categorie_id = 'cat_services', ordre = suite + r.rang
      from (select id, row_number() over (order by ordre, nom) as rang
              from public.sous_categories
             where categorie_id = 'cat_muflx6zvfjj9u8') r
     where s.id = r.id;
    delete from public.categories where id = 'cat_muflx6zvfjj9u8';
    -- « Informatique » et « Informaticien » côte à côte disent la même
    -- chose : le mot de l'enseigne reste.
    delete from public.sous_categories s
     where s.id = 'sc_services_informatique'
       and s.categorie_id = 'cat_services'
       and exists (select 1 from public.sous_categories d
                    where d.categorie_id = 'cat_services' and d.nom = 'Informaticien')
       and not exists (select 1 from public.produits p where p.sous_categorie_id = s.id);
  end if;

  -- ---------- 5. L'ordre par thème ----------
  -- Celles que la liste ne connaît pas (créées depuis l'admin) suivent,
  -- dans l'ordre où elles étaient. « en_avant » ne change pas.
  update public.categories c
     set ordre = array_length(rangement, 1) + r.rang
    from (select id, row_number() over (order by ordre, nom) as rang
            from public.categories
           where boutique_id is null and not (id = any(rangement))) r
   where c.id = r.id;
  update public.categories
     set ordre = array_position(rangement, id)
   where boutique_id is null and id = any(rangement);

  raise notice 'Catégories rangées : %, dont % sur l''accueil.',
    (select count(*) from public.categories where boutique_id is null),
    (select count(*) from public.categories where boutique_id is null and en_avant);
end $$;

-- Vérification : la liste dans son nouvel ordre, avec l'icône de
-- chacune et le nombre de ses rayons.
select c.ordre as "Ordre", c.nom as "Catégorie", c.icone as "Icône",
       case when c.en_avant then 'oui' else '' end as "Accueil",
       (select count(*) from public.sous_categories s where s.categorie_id = c.id) as "Rayons"
  from public.categories c
 where c.boutique_id is null
 order by c.ordre, c.nom;
