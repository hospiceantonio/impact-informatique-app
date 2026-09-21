-- =========================================================
-- BIZZOO — la liste des catégories, celle de l'enseigne
--
-- Jusqu'ici, chaque boutique inventait ses rayons. Sur une
-- vitrine unique c'était sans conséquence ; sur une place de
-- marché, cela donne à l'acheteur autant de classements qu'il
-- y a de commerces — « Ordinateurs » chez l'un ne rejoint
-- jamais « Ordinateurs » chez l'autre, et aucune liste ne
-- peut plus les réunir.
--
-- CE QUE CE FICHIER POSE.
--
--   La liste de BIZZOO : quinze secteurs, soixante-quatorze
--   rayons, écrits par le SUPERADMINISTRATEUR SEUL. Une
--   boutique ne crée plus de catégorie : elle en choisit une.
--
--   Le SECTEUR d'une boutique. Elle appartient à une catégorie
--   et une seule, et ses produits ne se rangent que dans les
--   sous-catégories de celle-là.
--
--   Le RAYON d'un produit, déduit. La boutique choisit une
--   sous-catégorie ; la catégorie s'en déduit toute seule. Ce
--   que l'application envoie dans « categorie_id » n'est plus
--   écouté : deux colonnes qu'on laisserait se contredire,
--   c'est un classement qui ment.
--
-- CE QUE CE FICHIER DÉFAIT, ET IL FAUT LE LIRE AVANT DE LE
-- COLLER. Les anciens rayons des boutiques sont SUPPRIMÉS —
-- ils étaient à elles, la liste est maintenant à l'enseigne,
-- et les deux ne peuvent pas cohabiter.
--
--   Les produits qui s'y rangeaient deviennent « À CLASSER ».
--   Ils restent en vente, dans leur boutique et dans la
--   recherche ; ils n'apparaissent sous aucun rayon de BIZZOO
--   tant que la boutique ne leur a pas donné une
--   sous-catégorie de son secteur.
--
--   RIEN N'EST PERDU d'autre : ni un produit, ni une
--   commande, ni une photo, ni un prix. Seul le classement
--   est à refaire.
--
-- CE QU'IL FAUT FAIRE APRÈS, dans cet ordre :
--   1. Réglages → Boutiques : donner son SECTEUR à chaque
--      boutique. Sans secteur, elle ne peut rien classer.
--   2. Produits : rouvrir chaque produit et lui choisir sa
--      sous-catégorie. Le compte des produits à classer
--      s'affiche en haut de l'écran.
--
-- La dernière requête du fichier dit combien de produits
-- attendent d'être classés, boutique par boutique.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Relançable : la liste déjà retouchée n'est pas remise à
-- l'état d'usine, et les produits déjà classés ne bougent pas.
-- =========================================================

-- ---------- Les colonnes dont les règles ci-dessous se servent ----------
-- « create table if not exists » ne touche pas une table qui existe
-- déjà : toute colonne ajoutée après coup doit être répétée ici, sinon
-- elle n'arrive jamais dans une base en service.
alter table public.categories add column if not exists icone    text not null default 'categories';
alter table public.categories add column if not exists couleur  text not null default '#0B5CF5';
alter table public.categories add column if not exists en_avant boolean not null default false;
create index if not exists categories_en_avant
  on public.categories(en_avant) where en_avant;

-- Le secteur d'une boutique. « on delete set null » plutôt que
-- « cascade » : supprimer une catégorie ne doit pas emporter les
-- boutiques qui la tenaient — elles se retrouvent sans secteur, et
-- l'enseigne leur en redonne un.
alter table public.boutiques
  add column if not exists categorie_id text references public.categories(id) on delete set null;
create index if not exists boutiques_categorie on public.boutiques(categorie_id);

-- Un produit peut attendre d'être classé : la colonne portait un
-- « not null » qu'il faut retirer, sinon toute la reprise s'arrête là.
alter table public.produits   add column if not exists boutique_id text references public.boutiques(id) on delete cascade;
alter table public.produits   add column if not exists sous_categorie_id text references public.sous_categories(id);
alter table public.produits   add column if not exists note_moyenne numeric(3,2);
alter table public.produits   add column if not exists nb_avis int not null default 0;
alter table public.produits   add column if not exists code text not null default '';
alter table public.produits   alter column categorie_id drop not null;
alter table public.boutiques  add column if not exists note_moyenne numeric(3,2);
alter table public.boutiques  add column if not exists nb_avis int not null default 0;
alter table public.boutiques
  add column if not exists taux_marge numeric(6,2) not null default 20;
alter table public.boutiques
  add column if not exists revendeur_mode text not null default 'bizzoo';
alter table public.boutiques
  add column if not exists taux_revendeur numeric(6,2) not null default 10;

-- ---------- Qui écrit la liste ----------
-- L'enseigne seule. Une boutique qui pouvait encore créer un rayon
-- créait un classement rien qu'à elle, et la liste commune cessait
-- d'en être une. Elle reste LUE par tout le monde, sans compte : c'est
-- le menu de la vitrine.
drop policy if exists "lecture publique"  on public.categories;
drop policy if exists "ecriture connectee" on public.categories;
drop policy if exists "ecriture enseigne" on public.categories;
create policy "lecture publique"  on public.categories for select using (true);
create policy "ecriture enseigne" on public.categories
  for all to authenticated
  using (public.est_super()) with check (public.est_super());

drop policy if exists "lecture publique"  on public.sous_categories;
drop policy if exists "ecriture connectee" on public.sous_categories;
drop policy if exists "ecriture enseigne" on public.sous_categories;
create policy "lecture publique"  on public.sous_categories for select using (true);
create policy "ecriture enseigne" on public.sous_categories
  for all to authenticated
  using (public.est_super()) with check (public.est_super());

-- ---------- Le rayon d'un produit se déduit de sa sous-catégorie ----------
create or replace function public.produit_code() returns trigger
language plpgsql security definer set search_path = public as $$
declare rayon text; secteur text;
begin
  /* ---------- LE RAYON ----------
     La boutique choisit une SOUS-CATÉGORIE ; la catégorie s'en déduit.
     Ce que l'application envoie dans « categorie_id » n'est jamais
     écouté : deux colonnes qu'on laisserait se contredire, c'est un
     classement qui ment — le produit serait dans un rayon à l'écran et
     dans un autre dans les comptes. */
  if coalesce(new.sous_categorie_id, '') = '' then
    -- À CLASSER. Le produit reste en vente, dans sa boutique et dans la
    -- recherche ; il n'apparaît sous aucun rayon de BIZZOO.
    new.sous_categorie_id := null;
    new.categorie_id := null;
  else
    select sc.categorie_id into rayon
      from public.sous_categories sc where sc.id = new.sous_categorie_id;
    if rayon is null then
      raise exception 'Cette sous-catégorie n''existe pas';
    end if;
    /* ET ELLE DOIT ÊTRE DU SECTEUR DE LA BOUTIQUE. C'est tout l'objet
       de la liste de l'enseigne : une boutique de cosmétiques qui
       publierait sous « Pièces détachées » rendrait le classement
       inutilisable pour l'acheteur. */
    select b.categorie_id into secteur
      from public.boutiques b where b.id = new.boutique_id;
    if secteur is null then
      raise exception 'Cette boutique n''a pas encore de secteur : l''enseigne doit lui en donner un';
    end if;
    if rayon <> secteur then
      raise exception 'Un produit se range dans une sous-catégorie du secteur de sa boutique';
    end if;
    new.categorie_id := rayon;
  end if;

  if tg_op = 'INSERT' then
    -- Ce que l'application envoie dans « code » n'est jamais écouté :
    -- la base le donne elle-même.
    new.code := nextval('public.produits_code')::text;
    -- Un produit neuf n'a pas d'avis, quoi qu'en dise l'insertion.
    new.note_moyenne := null;
    new.nb_avis := 0;
  else
    -- Et il ne bouge plus, quel que soit le rang de qui écrit. Un repère
    -- qu'on peut corriger n'est plus un repère.
    new.code := old.code;
    -- LA NOTE NE SE DÉCLARE PAS. Elle est calculée à partir des avis,
    -- par « avis_recalcule() », qui pose ce drapeau le temps de son
    -- écriture. Sans ce verrou, une boutique s'écrivait cinq étoiles et
    -- neuf cent quatre-vingt-dix-neuf avis — le règlement RLS lui laisse
    -- modifier ses propres produits, et ces deux colonnes en font
    -- partie. Le superadministrateur non plus : une note inventée par
    -- l'enseigne ne vaudrait pas mieux.
    if coalesce(current_setting('bizzoo.avis', true), '') <> 'oui' then
      if new.note_moyenne is distinct from old.note_moyenne
      or new.nb_avis      is distinct from old.nb_avis then
        raise exception 'La note d''un produit vient de ses avis, elle ne s''écrit pas';
      end if;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists produits_code on public.produits;
create trigger produits_code
  before insert or update on public.produits
  for each row execute function public.produit_code();

-- ---------- Le secteur ne change pas sous les produits ----------
create or replace function public.boutique_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- LA NOTE NE SE DÉCLARE PAS, et ceci passe AVANT la sortie du
  -- superadministrateur : une note inventée par l'enseigne ne vaudrait
  -- pas mieux qu'une note inventée par la boutique. Seule
  -- « avis_recalcule() » l'écrit, et elle pose ce drapeau pour le dire.
  if coalesce(current_setting('bizzoo.avis', true), '') <> 'oui' then
    if new.note_moyenne is distinct from old.note_moyenne
    or new.nb_avis      is distinct from old.nb_avis then
      raise exception 'La note d''une boutique vient de ses avis, elle ne s''écrit pas';
    end if;
  end if;

  -- LE SECTEUR, ET LES DEUX RAISONS DE LE REFUSER. Ceci passe AVANT la
  -- sortie du superadministrateur, parce que la seconde raison n'est pas
  -- une question de rang mais de cohérence.
  --
  --   1. Il n'est pas à la boutique : il dit où elle se range dans
  --      BIZZOO, et c'est une décision de l'enseigne.
  --   2. En CHANGER déclasse tout le catalogue — les produits sont
  --      rangés dans des sous-catégories de l'ancien secteur, que le
  --      nouveau n'a pas. « changer_secteur() » fait les deux gestes
  --      dans l'ordre, déclasser puis changer, et pose ce drapeau.
  --
  -- Lui en donner un pour la PREMIÈRE fois ne déclasse rien : sans
  -- secteur, aucun produit n'a pu être classé.
  if coalesce(current_setting('bizzoo.secteur', true), '') <> 'oui'
     and new.categorie_id is distinct from old.categorie_id then
    if old.categorie_id is not null then
      raise exception 'Changer le secteur déclasse les produits : passez par le bouton prévu';
    end if;
    if not public.est_super() then
      raise exception 'Le secteur d''une boutique est fixé par l''enseigne';
    end if;
  end if;

  -- L'enseigne fait ce qu'elle veut : c'est elle qui approuve.
  if public.est_super() then return new; end if;

  if new.actif is distinct from old.actif then
    raise exception 'Ouvrir ou fermer une boutique est une décision de l''enseigne';
  end if;
  if new.ordre is distinct from old.ordre then
    raise exception 'L''ordre des boutiques est réglé par l''enseigne';
  end if;
  -- La marge dit ce que BIZZOO gagne sur cette boutique. La laisser à
  -- la boutique reviendrait à lui laisser fixer sa propre commission.
  if new.taux_marge is distinct from old.taux_marge then
    raise exception 'La marge de BIZZOO est fixée par l''enseigne à la création de la boutique';
  end if;
  -- La marge revendeur est de la même nature : elle fixe ce que rapporte
  -- une vente à un revendeur validé. La laisser à la boutique lui
  -- permettrait de la ramener à zéro et de revendre au prix BIZZOO.
  -- Le taux d'UN produit, lui, reste à la boutique — comme pour la marge
  -- ordinaire, elle seule connaît ses articles.
  if new.taux_revendeur is distinct from old.taux_revendeur
  or new.revendeur_mode is distinct from old.revendeur_mode then
    raise exception 'Le prix des revendeurs est fixé par l''enseigne';
  end if;

  -- Ce qui représente la boutique auprès des clients passe par une
  -- demande de validation.
  if new.nom         is distinct from old.nom
  or new.logo        is distinct from old.logo
  or new.description is distinct from old.description
  or new.adresse     is distinct from old.adresse
  or new.latitude    is distinct from old.latitude
  or new.longitude   is distinct from old.longitude
  or new.tel         is distinct from old.tel
  or new.whatsapp    is distinct from old.whatsapp
  or new.indicatif   is distinct from old.indicatif
  or new.telephones  is distinct from old.telephones
  or new.adresses    is distinct from old.adresses then
    raise exception 'Nom, logo, description, adresse et contacts demandent l''accord de l''enseigne : enregistrez, la demande lui sera envoyée';
  end if;

  return new;
end $$;

drop trigger if exists boutiques_verrous on public.boutiques;
create trigger boutiques_verrous
  before update on public.boutiques
  for each row execute function public.boutique_verrous();

-- ---------- Changer le secteur, quand il le faut vraiment ----------
drop function if exists public.changer_secteur(text, text);
create or replace function public.changer_secteur(boutique text, vers text)
returns int
language plpgsql security definer set search_path = public as $$
declare combien int;
begin
  if not public.est_super() then
    raise exception 'Le secteur d''une boutique est fixé par l''enseigne';
  end if;
  if coalesce(boutique, '') = ''
     or not exists (select 1 from public.boutiques b where b.id = boutique) then
    raise exception 'Cette boutique n''existe pas';
  end if;
  -- Un secteur vide retire la boutique de la liste : elle n'apparaît
  -- plus sous aucune catégorie, et ne peut plus classer ses produits.
  if coalesce(vers, '') <> ''
     and not exists (select 1 from public.categories c where c.id = vers) then
    raise exception 'Cette catégorie n''existe pas';
  end if;

  update public.produits
     set sous_categorie_id = null, categorie_id = null, modifie_le = now()
   where boutique_id = boutique and sous_categorie_id is not null;
  get diagnostics combien = row_count;

  perform set_config('bizzoo.secteur', 'oui', true);
  update public.boutiques
     set categorie_id = nullif(coalesce(vers, ''), ''), maj_le = now()
   where id = boutique;
  perform set_config('bizzoo.secteur', '', true);
  return combien;
end $$;
revoke all on function public.changer_secteur(text, text) from public, anon, authenticated;
grant execute on function public.changer_secteur(text, text) to authenticated;

-- ---------- Qui est qui ----------
-- « produits_classes() » demande si l'appelant est de l'équipe. Sur une
-- base d'avant le rôle livreur, « est_equipe() » disait encore « un
-- rôle, n'importe lequel » — et un livreur y aurait lu le catalogue
-- d'une boutique. Un fichier qui appelle une fonction la pose aussi.
create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;
revoke all on function public.est_equipe() from public, anon, authenticated;
grant execute on function public.est_equipe() to authenticated;

-- Combien de produits perdrait-on à changer de secteur ? L'application
-- le demande AVANT d'ouvrir la confirmation.
create or replace function public.produits_classes(boutique text) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from public.produits p
   where public.est_equipe() and p.boutique_id = boutique
     and p.sous_categorie_id is not null;
$$;
revoke all on function public.produits_classes(text) from public, anon, authenticated;
grant execute on function public.produits_classes(text) to authenticated;

-- ---------- La liste de BIZZOO ----------
-- Quinze secteurs, soixante-quatorze rayons. « on conflict do nothing » :
-- une liste déjà retouchée par l'enseigne ne doit pas être remise à
-- l'état d'usine à chaque relecture. Ce qui est posé reste posé.
insert into public.categories (id, boutique_id, nom, icone, couleur, en_avant, ordre) values
  ('cat_mode',         null, 'Mode & Vêtements',                   'tshirt',   '#6C3FBF', true,   1),
  ('cat_hightech',     null, 'High-Tech & Électronique',           'portable', '#0B5CF5', true,   2),
  ('cat_auto',         null, 'Auto & Moto',                        'voiture',  '#001450', true,   3),
  ('cat_maison',       null, 'Maison & Jardin',                    'maison',   '#0F9D58', true,   4),
  ('cat_beaute',       null, 'Beauté & Bien-être',                 'goutte',   '#D81B60', true,   5),
  ('cat_restauration', null, 'Restauration & Alimentation',        'couverts', '#F96302', true,   6),
  ('cat_supermarche',  null, 'Supermarché & Épicerie',             'chariot',  '#E62329', true,   7),
  ('cat_logiciels',    null, 'Logiciels & Solutions professionnelles', 'ecran', '#0B7C8C', false, 8),
  ('cat_bebe',         null, 'Bébé & Enfant',                      'cadeau',   '#3F51B5', false,  9),
  ('cat_sport',        null, 'Sport & Loisirs',                    'ballon',   '#9A6B00', false, 10),
  ('cat_bricolage',    null, 'Bricolage & Matériaux',              'outils',   '#546E7A', false, 11),
  ('cat_livres',       null, 'Livres, Éducation & Fournitures',    'livre',    '#7A4A32', false, 12),
  ('cat_bijoux',       null, 'Bijoux & Accessoires',               'diamant',  '#6C3FBF', false, 13),
  ('cat_animaux',      null, 'Animaux',                            'patte',    '#0F9D58', false, 14),
  ('cat_services',     null, 'Services',                           'sacoche',  '#0B7C8C', true,  15)
on conflict (id) do nothing;

insert into public.sous_categories (id, categorie_id, nom, ordre) values
  ('sc_mode_homme',            'cat_mode', 'Homme',                 1),
  ('sc_mode_femme',            'cat_mode', 'Femme',                 2),
  ('sc_mode_enfant',           'cat_mode', 'Enfant',                3),
  ('sc_mode_chaussures',       'cat_mode', 'Chaussures',            4),
  ('sc_mode_sacs',             'cat_mode', 'Sacs & accessoires',    5),

  ('sc_hightech_smartphones',  'cat_hightech', 'Smartphones',       1),
  ('sc_hightech_ordinateurs',  'cat_hightech', 'Ordinateurs',       2),
  ('sc_hightech_tablettes',    'cat_hightech', 'Tablettes',         3),
  ('sc_hightech_accessoires',  'cat_hightech', 'Accessoires',       4),
  ('sc_hightech_tv',           'cat_hightech', 'TV & audio',        5),

  ('sc_auto_vehicules',        'cat_auto', 'Véhicules',             1),
  ('sc_auto_motos',            'cat_auto', 'Motos',                 2),
  ('sc_auto_pieces',           'cat_auto', 'Pièces détachées',      3),
  ('sc_auto_pneus',            'cat_auto', 'Pneus',                 4),
  ('sc_auto_accessoires',      'cat_auto', 'Accessoires auto',      5),
  ('sc_auto_entretien',        'cat_auto', 'Entretien',             6),

  ('sc_maison_meubles',        'cat_maison', 'Meubles',             1),
  ('sc_maison_decoration',     'cat_maison', 'Décoration',          2),
  ('sc_maison_electromenager', 'cat_maison', 'Électroménager',      3),
  ('sc_maison_cuisine',        'cat_maison', 'Cuisine',             4),
  ('sc_maison_jardinage',      'cat_maison', 'Jardinage',           5),

  ('sc_beaute_cosmetiques',    'cat_beaute', 'Cosmétiques',         1),
  ('sc_beaute_parfums',        'cat_beaute', 'Parfums',             2),
  ('sc_beaute_soins',          'cat_beaute', 'Soins',               3),
  ('sc_beaute_coiffure',       'cat_beaute', 'Coiffure',            4),
  ('sc_beaute_accessoires',    'cat_beaute', 'Accessoires beauté',  5),

  ('sc_resto_restaurants',     'cat_restauration', 'Restaurants',    1),
  ('sc_resto_fastfood',        'cat_restauration', 'Fast-food',      2),
  ('sc_resto_plats_locaux',    'cat_restauration', 'Plats locaux',   3),
  ('sc_resto_boissons',        'cat_restauration', 'Boissons',       4),
  ('sc_resto_epicerie',        'cat_restauration', 'Épicerie',       5),
  ('sc_resto_frais',           'cat_restauration', 'Produits frais', 6),

  ('sc_super_alimentation',    'cat_supermarche', 'Alimentation',       1),
  ('sc_super_menagers',        'cat_supermarche', 'Produits ménagers',  2),
  ('sc_super_bebe',            'cat_supermarche', 'Produits pour bébé', 3),
  ('sc_super_hygiene',         'cat_supermarche', 'Hygiène',            4),
  ('sc_super_boissons',        'cat_supermarche', 'Boissons',           5),

  ('sc_logiciels_gestion',     'cat_logiciels', 'Logiciels de gestion',      1),
  ('sc_logiciels_compta',      'cat_logiciels', 'Comptabilité',              2),
  ('sc_logiciels_caisse',      'cat_logiciels', 'Caisse/POS',                3),
  ('sc_logiciels_antivirus',   'cat_logiciels', 'Antivirus',                 4),
  ('sc_logiciels_licences',    'cat_logiciels', 'Licences',                  5),
  ('sc_logiciels_entreprises', 'cat_logiciels', 'Solutions pour entreprises', 6),

  ('sc_bebe_vetements',        'cat_bebe', 'Vêtements',             1),
  ('sc_bebe_jouets',           'cat_bebe', 'Jouets',                2),
  ('sc_bebe_puericulture',     'cat_bebe', 'Puériculture',          3),
  ('sc_bebe_mobilier',         'cat_bebe', 'Mobilier enfant',       4),

  ('sc_sport_equipements',     'cat_sport', 'Équipements sportifs', 1),
  ('sc_sport_vetements',       'cat_sport', 'Vêtements de sport',   2),
  ('sc_sport_fitness',         'cat_sport', 'Fitness',              3),
  ('sc_sport_jeux',            'cat_sport', 'Jeux',                 4),
  ('sc_sport_loisirs',         'cat_sport', 'Loisirs',              5),

  ('sc_brico_outillage',       'cat_bricolage', 'Outillage',                  1),
  ('sc_brico_materiaux',       'cat_bricolage', 'Matériaux de construction',  2),
  ('sc_brico_electricite',     'cat_bricolage', 'Électricité',                3),
  ('sc_brico_plomberie',       'cat_bricolage', 'Plomberie',                  4),
  ('sc_brico_quincaillerie',   'cat_bricolage', 'Quincaillerie',              5),

  ('sc_livres_livres',         'cat_livres', 'Livres',               1),
  ('sc_livres_fournitures',    'cat_livres', 'Fournitures scolaires', 2),
  ('sc_livres_papeterie',      'cat_livres', 'Papeterie',            3),
  ('sc_livres_formations',     'cat_livres', 'Formations',           4),

  ('sc_bijoux_bijoux',         'cat_bijoux', 'Bijoux',               1),
  ('sc_bijoux_montres',        'cat_bijoux', 'Montres',              2),
  ('sc_bijoux_lunettes',       'cat_bijoux', 'Lunettes',             3),
  ('sc_bijoux_accessoires',    'cat_bijoux', 'Accessoires',          4),

  ('sc_animaux_alimentation',  'cat_animaux', 'Alimentation',        1),
  ('sc_animaux_accessoires',   'cat_animaux', 'Accessoires',         2),
  ('sc_animaux_hygiene',       'cat_animaux', 'Hygiène',             3),

  ('sc_services_reparation',   'cat_services', 'Réparation',              1),
  ('sc_services_installation', 'cat_services', 'Installation',            2),
  ('sc_services_maintenance',  'cat_services', 'Maintenance',             3),
  ('sc_services_informatique', 'cat_services', 'Informatique',            4),
  ('sc_services_nettoyage',    'cat_services', 'Nettoyage',               5),
  ('sc_services_pro',          'cat_services', 'Services professionnels', 6)
on conflict (id) do nothing;


-- ---------- LA REPRISE : les anciens rayons des boutiques s'en vont ----------
-- On reconnaît un ancien rayon à son « boutique_id » : ceux de
-- l'enseigne l'ont toujours à null. Les produits qui s'y rangeaient
-- deviennent « à classer » — en vente, mais sous aucun rayon de BIZZOO.
update public.produits set sous_categorie_id = null
 where sous_categorie_id in (
   select sc.id from public.sous_categories sc
     join public.categories c on c.id = sc.categorie_id
    where c.boutique_id is not null);
update public.produits set categorie_id = null
 where categorie_id in (select id from public.categories where boutique_id is not null);
delete from public.categories where boutique_id is not null;

-- ---------- Ce qu'il vous reste à faire ----------
-- Une ligne par boutique. « Secteur » vide : allez d'abord lui en
-- donner un dans Réglages → Boutiques, sinon elle ne peut rien classer.
select b.nom                                        as "Boutique",
       coalesce(c.nom, '— AUCUN, à donner —')       as "Secteur",
       count(p.id) filter (where p.sous_categorie_id is null) as "Produits à classer",
       count(p.id)                                  as "Produits en tout"
  from public.boutiques b
  left join public.categories c on c.id = b.categorie_id
  left join public.produits   p on p.boutique_id = b.id
 group by b.nom, c.nom
 order by 3 desc, 1;
