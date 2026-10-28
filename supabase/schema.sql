-- =========================================================
-- IMPACT INFORMATIQUE — base Supabase
--
-- À exécuter UNE FOIS dans le projet Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Ensuite :
--   1. Authentication → Users → Add user → créer le compte du
--      gérant (email + mot de passe, cocher « Auto Confirm »).
--   2. Récupérer Project Settings → API : « Project URL » et la
--      clé « anon public », à mettre dans config.js des deux
--      applications (ou dans l'écran de connexion de l'app admin).
--
-- Règles de sécurité (RLS) :
--   - tout le monde peut LIRE le catalogue (application client) ;
--   - seul un utilisateur CONNECTÉ (le gérant) peut écrire.
-- =========================================================

-- ---------- L'enseigne BIZZOO (une seule ligne) ----------
-- BIZZOO réunit les boutiques ; cette ligne porte SES coordonnées à
-- elle — celles de l'enseigne, pas celles d'un secteur. Chaque
-- boutique a les siennes dans la table « boutiques » plus bas.
create table if not exists public.boutique (
  id          int primary key default 1 check (id = 1),
  nom         text not null default 'IMPACT INFORMATIQUE',
  slogan      text not null default 'Nous sommes imbattables en prix',
  description text not null default '',
  tel         text not null default '',
  whatsapp    text not null default '69842516',
  indicatif   text not null default '229',
  devise      text not null default 'FCFA',
  adresse     text not null default '',
  horaires    text not null default '',
  site_web    text not null default '',       -- « bizzoo.bj », ou le lien entier
  facebook    text not null default '',
  instagram   text not null default '',
  tiktok      text not null default '',
  youtube     text not null default '',
  snapchat    text not null default '',
  latitude    double precision,               -- position de la boutique
  longitude   double precision,
  photos      text[] not null default '{}',   -- photos de la boutique
  -- Autres numéros et autres adresses, en plus des principaux ci-dessus.
  --   telephones : [{ "libelle": "Atelier", "numero": "0197…", "whatsapp": false }]
  --   adresses   : [{ "libelle": "Annexe", "texte": "Godomey…",
  --                   "latitude": 6.36, "longitude": 2.41 }]
  telephones  jsonb not null default '[]'::jsonb,
  adresses    jsonb not null default '[]'::jsonb,
  video       text not null default '',      -- vidéo de présentation
  -- Marge appliquée par défaut au prix grossiste pour obtenir le prix
  -- public. Chaque produit peut avoir son propre taux.
  taux_marge  numeric(6,2) not null default 20,
  maj_le      timestamptz not null default now()
);

-- Ajout des colonnes sur une base déjà créée (sans risque).
alter table public.boutique add column if not exists instagram text not null default '';
alter table public.boutique add column if not exists tiktok text not null default '';
alter table public.boutique add column if not exists youtube text not null default '';
alter table public.boutique add column if not exists snapchat text not null default '';
alter table public.boutique add column if not exists latitude double precision;
alter table public.boutique add column if not exists longitude double precision;
alter table public.boutique add column if not exists photos text[] not null default '{}';
alter table public.boutique add column if not exists telephones jsonb not null default '[]'::jsonb;
alter table public.boutique add column if not exists adresses jsonb not null default '[]'::jsonb;
alter table public.boutique add column if not exists taux_marge numeric(6,2) not null default 20;
alter table public.boutique add column if not exists video text not null default '';
alter table public.boutique add column if not exists site_web text not null default '';

-- ---------- Les boutiques ----------
-- L'application couvre plusieurs secteurs d'activité : une boutique par
-- secteur, avec son catalogue, ses catégories, son slider et ses
-- coordonnées. La table « boutique » du dessus reste la boutique
-- historique — elle sert de modèle à la première ligne d'ici.
create table if not exists public.boutiques (
  id          text primary key,
  nom         text not null,
  secteur     text not null default '',        -- « Informatique », « Cosmétiques »…
  slogan      text not null default '',
  description text not null default '',
  icone       text not null default 'magasin', -- icône affichée chez le client
  couleur     text not null default '#0B5CF5',
  logo        text not null default '',        -- image dans le bucket (remplace l'icône)
  actif       boolean not null default true,   -- une boutique fermée disparaît du client
  ordre       int not null default 0,
  tel         text not null default '',
  whatsapp    text not null default '',
  indicatif   text not null default '229',
  devise      text not null default 'FCFA',
  adresse     text not null default '',
  horaires    text not null default '',
  site_web    text not null default '',
  facebook    text not null default '',
  instagram   text not null default '',
  tiktok      text not null default '',
  youtube     text not null default '',
  snapchat    text not null default '',
  latitude    double precision,
  longitude   double precision,
  photos      text[] not null default '{}',
  telephones  jsonb not null default '[]'::jsonb,
  adresses    jsonb not null default '[]'::jsonb,
  video       text not null default '',      -- vidéo de présentation
  taux_marge  numeric(6,2) not null default 20,
  -- Ce que paie un revendeur validé. « bizzoo » : prix BIZZOO + N %.
  -- « public » : prix public − N %. Chaque boutique choisit sa façon de
  -- faire ; le taux, lui, se raffine produit par produit.
  revendeur_mode  text not null default 'bizzoo'
                  check (revendeur_mode in ('bizzoo', 'public')),
  taux_revendeur  numeric(6,2) not null default 10,
  cree_le     timestamptz not null default now(),
  maj_le      timestamptz not null default now()
);
alter table public.boutiques add column if not exists video text not null default '';
alter table public.boutiques add column if not exists site_web text not null default '';

-- ---------- Les jours et heures d'ouverture (3.59.0) ----------
-- Une boutique fermée ne montre pas ses produits, et ne reçoit pas de
-- commande : une commande passée la nuit tombait dans le vide.
--
--   {"lun": {"de": "08:00", "a": "19:00"}, …, "dim": null}
--
-- Un jour absent ou « null » : fermé ce jour-là. La colonne entière à
-- null : horaires pas encore renseignés — la boutique reste ouverte, comme
-- avant, et son administrateur est invité à les poser. Une boutique
-- CRÉÉE depuis l'application doit les avoir (voir plus bas).
alter table public.boutiques add column if not exists ouvertures jsonb;

-- Le format, vérifié : sept jours au plus, « HH:MM », l'ouverture avant
-- la fermeture, et au moins un jour ouvert.
create or replace function public.ouvertures_valides(o jsonb) returns boolean
language sql immutable set search_path = public as $$
  select jsonb_typeof(o) = 'object'
     and not exists (select 1 from jsonb_object_keys(o) k
                      where k not in ('lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'))
     and not exists (
       select 1 from jsonb_each(o) j
        where jsonb_typeof(j.value) not in ('null', 'object')
           or (jsonb_typeof(j.value) = 'object' and not (
                length(coalesce(j.value ->> 'de', '')) = 5
            and (j.value ->> 'de') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]'
            and length(coalesce(j.value ->> 'a', '')) = 5
            and ((j.value ->> 'a') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]' or (j.value ->> 'a') = '24:00')
            and (j.value ->> 'de') < (j.value ->> 'a'))))
     and exists (select 1 from jsonb_each(o) j where jsonb_typeof(j.value) = 'object');
$$;
alter table public.boutiques drop constraint if exists boutiques_ouvertures;
alter table public.boutiques add constraint boutiques_ouvertures
  check (ouvertures is null or public.ouvertures_valides(ouvertures));

-- Ouverte à cet instant, À L'HEURE DU BÉNIN — pas à celle du serveur,
-- qui tourne en UTC. Sans horaires : ouverte (voir plus haut).
create or replace function public.boutique_ouverte(o jsonb, moment timestamptz default now())
returns boolean
language sql stable set search_path = public as $$
  with ici as (select (moment at time zone 'Africa/Porto-Novo') as t)
  select case
    when o is null then true
    else coalesce((
      select jsonb_typeof(o -> j.jour) = 'object'
         and to_char(ici.t, 'HH24:MI') >= (o -> j.jour ->> 'de')
         and to_char(ici.t, 'HH24:MI') <  (o -> j.jour ->> 'a')
        from ici, lateral (select (array['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'])
                                    [extract(isodow from ici.t)::int] as jour) j), false)
  end;
$$;
grant execute on function public.ouvertures_valides(jsonb) to anon, authenticated;
grant execute on function public.boutique_ouverte(jsonb, timestamptz) to anon, authenticated;

-- UNE BOUTIQUE NAÎT AVEC SES HORAIRES quand on la crée depuis
-- l'application. Le schéma lui-même, et le tableau de bord de Supabase,
-- passent : ils ne tournent pas en « authenticated ».
create or replace function public.boutique_horaires_a_la_creation() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user in ('anon', 'authenticated') and new.ouvertures is null then
    raise exception 'Indiquez les jours et heures d''ouverture de la boutique.'
      using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists boutiques_horaires on public.boutiques;
create trigger boutiques_horaires
  before insert on public.boutiques
  for each row execute function public.boutique_horaires_a_la_creation();

-- ---------- Les conditions de paiement de chaque boutique (3.59.0) ----------
-- CHAQUE BOUTIQUE DIT COMMENT ON LA PAIE, et ce que coûte sa livraison :
--   mode_paiement « total »   : tout se paie à la commande ;
--                 « acompte » : taux_acompte % à la commande, le reste à la
--                               livraison, à son livreur ;
--   frais_livraison           : en FCFA, ajoutés à sa part — aucun code
--                               promo ne les touche.
-- Une commande sur plusieurs boutiques additionne leurs conditions :
-- creer_commande calcule chaque part, et « parts » les garde. Les valeurs
-- par défaut sont celles que l'enseigne appliquait à toutes jusqu'ici
-- (10 %, 1 000 FCFA).
alter table public.boutiques add column if not exists mode_paiement text not null default 'acompte';
alter table public.boutiques add column if not exists taux_acompte int not null default 10;
alter table public.boutiques add column if not exists frais_livraison int not null default 1000;
alter table public.boutiques drop constraint if exists boutiques_mode_paiement;
alter table public.boutiques add constraint boutiques_mode_paiement
  check (mode_paiement in ('total', 'acompte'));
alter table public.boutiques drop constraint if exists boutiques_taux_acompte;
alter table public.boutiques add constraint boutiques_taux_acompte
  check (taux_acompte between 1 and 99);
alter table public.boutiques drop constraint if exists boutiques_frais_livraison;
alter table public.boutiques add constraint boutiques_frais_livraison
  check (frais_livraison between 0 and 100000);
-- « create table if not exists » ne touche pas une table qui existe déjà :
-- une colonne ajoutée plus tard doit être répétée ici, sinon elle n'arrive
-- jamais dans une base en service. La marge de BIZZOO en fait partie —
-- sans elle, aucun prix de vente ne se calcule.
alter table public.boutiques
  add column if not exists taux_marge numeric(6,2) not null default 20;
-- La marge revendeur, pour la même raison. Une base d'avant vendait au
-- prix BIZZOO exact ; ces deux colonnes-ci posent 10 % de marge sur le
-- prix BIZZOO, que chaque boutique ajuste ensuite dans ses réglages.
alter table public.boutiques
  add column if not exists revendeur_mode text not null default 'bizzoo';
alter table public.boutiques
  add column if not exists taux_revendeur numeric(6,2) not null default 10;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'boutiques_revendeur_mode') then
    alter table public.boutiques
      add constraint boutiques_revendeur_mode
      check (revendeur_mode in ('bizzoo', 'public'));
  end if;
end $$;
-- La charte a changé : une boutique sans couleur choisie prend le bleu
-- BIZZOO. Celles déjà enregistrées gardent la leur.
alter table public.boutiques alter column couleur set default '#0B5CF5';
create index if not exists boutiques_ordre on public.boutiques(ordre);

-- La boutique d'origine devient la première du lot, avec tous ses réglages.
insert into public.boutiques (
  id, nom, secteur, slogan, description, icone, couleur, actif, ordre,
  tel, whatsapp, indicatif, devise, adresse, horaires,
  facebook, instagram, tiktok, youtube, snapchat,
  latitude, longitude, photos, telephones, adresses, taux_marge)
select 'bou_informatique', 'INFORMATIQUE ET ELECTRONIQUE', 'Informatique et électronique',
       b.slogan, b.description, 'magasin', '#1176D8', true, 1,
       b.tel, b.whatsapp, b.indicatif, b.devise, b.adresse, b.horaires,
       b.facebook, b.instagram, b.tiktok, b.youtube, b.snapchat,
       b.latitude, b.longitude, b.photos, b.telephones, b.adresses, b.taux_marge
  from public.boutique b where b.id = 1
on conflict (id) do nothing;

-- Base neuve, sans ligne « boutique » : on pose quand même la première.
insert into public.boutiques (id, nom, secteur, ordre)
select 'bou_informatique', 'INFORMATIQUE ET ELECTRONIQUE', 'Informatique et électronique', 1
where not exists (select 1 from public.boutiques);

-- ---------- Catégories et sous-catégories ----------
-- LA LISTE EST CELLE DE BIZZOO, PLUS CELLE D'UNE BOUTIQUE. Sur une
-- place de marché, laisser chaque commerce inventer ses rayons donne à
-- l'acheteur autant de classements qu'il y a de boutiques :
-- « Ordinateurs » chez l'un ne rejoint jamais « Ordinateurs » chez
-- l'autre, et aucune liste ne peut plus les réunir. L'enseigne pose
-- donc la liste, une fois, pour tout le monde.
--
-- Une boutique choisit SON SECTEUR parmi ces catégories, et ses
-- produits se rangent dans les SOUS-CATÉGORIES de ce secteur. Les
-- rayons d'une boutique ne sont plus des rayons à elle : ce sont les
-- sous-catégories de BIZZOO qu'elle tient effectivement.
--
-- « boutique_id » reste là, mais ne sert plus : elle vaut null sur
-- toute catégorie de l'enseigne. La colonne n'est pas retirée parce que
-- les fichiers déjà envoyés au gérant la nomment — la retirer les ferait
-- échouer en bloc chez lui.
create table if not exists public.categories (
  id          text primary key,
  boutique_id text references public.boutiques(id) on delete cascade,
  nom         text not null,
  -- L'icône de sa tuile, sur l'accueil et l'écran « Catégories » : une
  -- image DÉJÀ DANS les deux applications (« img/pictos/<icone>.png »,
  -- depuis la 3.56 ; avant, une icône d'un trait). Rien à téléverser,
  -- rien à stocker, et la liste s'affiche hors connexion. La couleur ne
  -- sert plus qu'aux applications d'avant la 3.56 : les tuiles ont
  -- toutes le même fond.
  icone       text not null default 'categories',
  couleur     text not null default '#0B5CF5',
  -- LA PHOTO DE LA TUILE, facultative (voir plus bas).
  image       text not null default '',
  -- Les trente ne tiennent pas sur un accueil. Celles-ci s'y montrent ;
  -- les autres attendent derrière « Voir toutes les catégories ».
  en_avant    boolean not null default false,
  ordre       int  not null default 0,
  cree_le     timestamptz not null default now()
);
alter table public.categories add column if not exists icone    text not null default 'categories';
alter table public.categories add column if not exists couleur  text not null default '#0B5CF5';
alter table public.categories add column if not exists en_avant boolean not null default false;

-- LA PHOTO DE LA TUILE : sur l'accueil et l'écran « Catégories », elle
-- prend la place de l'icône ; sans elle, l'icône reste — et elle
-- revient aussi quand la photo ne se charge pas (hors connexion).
--
-- UN CHEMIN, JAMAIS UNE ADRESSE, et dans l'un de deux dossiers :
--
--   « enseigne/categories/ », dans le seau : la photo que l'enseigne
--     dépose depuis l'admin. C'est le dossier que le stockage réserve
--     au superadministrateur (voir « peut_deposer »), comme la liste
--     elle-même lui est réservée ;
--   « img/categories/ » : les illustrations en 3D qui voyageaient avec
--     les applications jusqu'à la 3.55. La base en ligne les garde,
--     parce que les applications déjà installées les montrent encore ;
--     depuis la 3.56, les applications ne lisent plus ces chemins et
--     montrent l'icône. Seules les catégories nouvelles de la 3.56 en
--     reçoivent encore une (« categories-rangement.sql »), pour ces
--     mêmes applications installées.
--
-- Une adresse libre ferait charger à l'accueil de tous les clients une
-- image posée n'importe où.
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

create table if not exists public.sous_categories (
  id           text primary key,
  categorie_id text not null references public.categories(id) on delete cascade,
  nom          text not null,
  ordre        int  not null default 0
);
create index if not exists sous_categories_categorie
  on public.sous_categories(categorie_id);
create index if not exists categories_en_avant
  on public.categories(en_avant) where en_avant;

-- ---------- Le secteur d'une boutique ----------
-- Une boutique appartient à UNE catégorie de BIZZOO, et ses produits ne
-- se rangent que dans les sous-catégories de celle-là. Une boutique de
-- cosmétiques qui publierait sous « Pièces détachées » rendrait la
-- liste inutilisable pour l'acheteur — c'est exactement ce que la liste
-- de l'enseigne sert à empêcher.
--
-- La contrainte s'ajoute ici et non dans le « create table » : la table
-- des boutiques naît avant celle des catégories, et une clé étrangère
-- ne peut pas désigner ce qui n'existe pas encore.
--
-- « on delete set null » plutôt que « cascade » : supprimer une
-- catégorie ne doit pas emporter les boutiques qui la tenaient. Elles
-- se retrouvent sans secteur, et l'enseigne leur en redonne un.
alter table public.boutiques
  add column if not exists categorie_id text references public.categories(id) on delete set null;
create index if not exists boutiques_categorie on public.boutiques(categorie_id);

-- ---------- Produits ----------
create table if not exists public.produits (
  id                text primary key,
  boutique_id       text references public.boutiques(id) on delete cascade,
  nom               text not null,
  reference         text not null default '',
  description       text not null default '',
  prix              bigint not null check (prix >= 0),
  ancien_prix       bigint,
  -- LA SOUS-CATÉGORIE EST CE QUE LA BOUTIQUE CHOISIT ; la catégorie s'en
  -- déduit, et le déclencheur « produit_rayon » l'écrit. Deux colonnes
  -- pour un seul classement, oui — mais la catégorie sert à des
  -- centaines de lectures (un rayon, un compte, une liste) et la
  -- recalculer à chaque fois coûterait une jointure de plus partout.
  --
  -- Aucune des deux n'est obligatoire : un produit peut attendre d'être
  -- classé. Il reste alors dans sa boutique et dans la recherche, mais
  -- n'apparaît sous aucun rayon de BIZZOO.
  categorie_id      text references public.categories(id),
  sous_categorie_id text references public.sous_categories(id),
  stock             int not null default 0 check (stock >= 0),
  sur_commande      boolean not null default false, -- vendu sans stock : « Sur commande »
  -- Date d'arrivée attendue d'un réassort : « En approvisionnement,
  -- arrive dans 3 jours ». Le décompte se fait tout seul, et une date
  -- passée s'ignore — le produit redevient « En rupture ».
  appro_le          date,
  disponible        boolean not null default true,  -- tenu à jour : sur_commande ou stock > 0
  en_avant          boolean not null default false,  -- 5 max (contrôlé par l'app admin)
  ordre_avant       int not null default 0,          -- ordre dans le slider client
  images            text[] not null default '{}',    -- chemins dans le bucket « produits »
  video             text not null default '',        -- vidéo de présentation (facultative)
  cree_le           timestamptz not null default now(),
  modifie_le        timestamptz not null default now()
);
-- Ajout des colonnes sur les bases déjà créées (sans risque).
-- Sur une base en service, la colonne existe et porte encore son
-- « not null » : il faut le retirer explicitement, sinon un produit
-- laissé à classer serait refusé et toute la reprise s'arrêterait là.
alter table public.produits alter column categorie_id drop not null;
alter table public.categories add column if not exists boutique_id text references public.boutiques(id) on delete cascade;
alter table public.produits   add column if not exists boutique_id text references public.boutiques(id) on delete cascade;
alter table public.produits add column if not exists reference text not null default '';
alter table public.produits add column if not exists video text not null default '';
alter table public.produits add column if not exists stock int not null default 0;
alter table public.produits add column if not exists sur_commande boolean not null default false;
alter table public.produits add column if not exists appro_le date;
-- Vente flash : le produit y est tant que la date n'est pas passée.
-- À null, pas de vente flash. Aucun nettoyage à faire : une date
-- passée s'ignore d'elle-même.
alter table public.produits add column if not exists flash_fin timestamptz;
-- (3.64.0) COMMENT IL SE LIVRE : à moto, ou en tricycle pour ce qui ne
-- tient pas sur une moto. Une commande se livre en tricycle dès qu'UN
-- de ses produits l'exige, et ses frais suivent ce tarif-là. Les produits
-- d'avant se livrent à moto.
alter table public.produits add column if not exists vehicule text not null default 'moto';
alter table public.produits drop constraint if exists produits_vehicule;
alter table public.produits add constraint produits_vehicule check (vehicule in ('moto', 'tricycle'));

-- Passage à la gestion de stock : les produits jusque-là « en stock »
-- démarrent à 1 pour ne pas basculer d'un coup en « En rupture ».
-- Ne s'exécute qu'une fois : dès qu'un stock est saisi, on n'y touche plus.
do $$
begin
  if not exists (select 1 from public.produits where stock > 0 or sur_commande) then
    update public.produits set stock = 1 where disponible;
  end if;
end $$;

-- Le oui / non hérité suit les deux nouvelles colonnes.
update public.produits set disponible = (sur_commande or stock > 0)
where disponible <> (sur_commande or stock > 0);

-- LE STOCK NE DESCEND JAMAIS SOUS ZÉRO. Une base neuve porte la règle
-- dans son « create table » ; une base en service, qui a reçu la colonne
-- par l'« alter table » ci-dessus, ne la portait pas — c'était le cas de
-- la base en ligne. Même nom que sur une base neuve, pour que les deux
-- se ressemblent. Une boutique n'a pas « moins deux » pièces : un stock
-- négatif se ramène d'abord à zéro.
update public.produits set stock = 0 where stock < 0;
do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.produits'::regclass
                    and conname = 'produits_stock_check') then
    alter table public.produits add constraint produits_stock_check check (stock >= 0);
  end if;
end $$;

-- ---------- Le code d'un produit ----------
-- Un numéro, rien que des chiffres, donné par la base à la création.
-- Il ne se choisit pas, ne se corrige pas, ne se réutilise pas — pas
-- même par un superadministrateur. C'est ce qui en fait un repère :
-- un code dicté au téléphone désigne un seul produit, pour toujours.
-- À ne pas confondre avec la RÉFÉRENCE, que la boutique choisit et
-- change à sa guise.
alter table public.produits add column if not exists code text not null default '';

-- Six chiffres, sans zéro en tête : un code se dicte au téléphone et se
-- recopie à la main. Le compteur ne revient jamais en arrière, même si
-- un produit est supprimé — un code retiré du catalogue reste retiré.
create sequence if not exists public.produits_code start with 100001;

-- Le déclencheur est posé APRÈS ce rattrapage : il refuserait cette
-- écriture, puisqu'un code ne se change pas.
drop trigger if exists produits_code on public.produits;

do $$
declare p record;
begin
  for p in select id from public.produits
            where coalesce(code, '') = '' order by cree_le, id loop
    update public.produits set code = nextval('public.produits_code')::text
     where id = p.id;
  end loop;
end $$;

-- Deux produits ne partagent pas un code : sans cela, il ne désignerait
-- plus rien.
create unique index if not exists produits_code_unique
  on public.produits(code) where code <> '';

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

create trigger produits_code
  before insert or update on public.produits
  for each row execute function public.produit_code();

create index if not exists produits_categorie on public.produits(categorie_id);
create index if not exists produits_en_avant on public.produits(en_avant) where en_avant;

-- ---------- Prix d'achat (table privée) ----------
-- Le prix grossiste ne regarde que la boutique : il vit dans sa propre
-- table, invisible avec la clé publique de l'application client. Le prix
-- affiché aux clients reste « produits.prix », calculé à partir d'ici.
--   prix public = prix_grossiste + taux %
--   taux_marge à null : c'est le taux de la boutique qui s'applique.
--
-- « taux_revendeur » suit exactement la même règle, pour le prix des
-- revendeurs validés : à null, c'est le taux de la boutique. Il est ici
-- et non sur « produits » parce qu'il se déduit du prix BIZZOO, et que
-- le prix BIZZOO ne descend jamais dans l'application cliente.
create table if not exists public.produits_prive (
  produit_id     text primary key references public.produits(id) on delete cascade,
  prix_grossiste bigint not null default 0 check (prix_grossiste >= 0),
  taux_marge     numeric(6,2),
  taux_revendeur numeric(6,2),
  maj_le         timestamptz not null default now()
);
-- Sur une base déjà en service, le corps ci-dessus n'est jamais relu.
alter table public.produits_prive
  add column if not exists taux_revendeur numeric(6,2);

-- ---------- Slider de l'application client ----------
-- Ce qui défile en haut de l'écran : des photos et des vidéos choisies
-- une par une, chacune pouvant renvoyer vers un produit (facultatif).
--
-- Trois vitrines, que « portee » distingue :
--   'enseigne'  — le slider de BIZZOO, composé dans ses réglages. C'est
--                 lui, et lui seul, qui défile en haut de l'accueil.
--   'publicite' — ce que BIZZOO met en avant plus bas sur l'accueil :
--                 affiches et produits pris dans n'importe quelle
--                 boutique. Réservée au superadministrateur.
--   'boutique'  — le slider d'une boutique, sur son écran à elle.
-- Rien ne remonte plus d'une boutique vers l'accueil.
create table if not exists public.slides (
  id          text primary key,
  boutique_id text references public.boutiques(id) on delete cascade,
  portee      text not null default 'boutique',
  image       text not null default '',   -- chemin dans le bucket « produits »
  video       text not null default '',   -- ou une vidéo, à la place de la photo
  titre       text not null default '',   -- légende facultative posée sur l'écran
  produit_id  text references public.produits(id) on delete set null,
  ordre       int not null default 0,
  actif       boolean not null default true,
  cree_le     timestamptz not null default now()
);
alter table public.slides add column if not exists boutique_id text references public.boutiques(id) on delete cascade;
-- Sans « portee », la reprise plus bas rangerait le slider de l'enseigne
-- dans une boutique : ses écrans n'ont pas de boutique_id, comme ceux
-- d'avant les boutiques multiples.
alter table public.slides add column if not exists portee text not null default 'boutique';
alter table public.slides add column if not exists video text not null default '';
-- Un écran peut renvoyer vers un produit. C'est ce qui permet à la
-- publicité de BIZZOO de piocher dans le catalogue des boutiques.
alter table public.slides add column if not exists produit_id text references public.produits(id) on delete set null;
create index if not exists slides_ordre on public.slides(ordre);

-- ---------- Tout le catalogue d'avant rejoint la première boutique ----------
-- Produits, rayons et images du slider : rien ne se perd, tout se range.
do $$
declare premiere text;
begin
  select id into premiere from public.boutiques order by ordre, cree_le limit 1;
  if premiere is null then return; end if;
  -- LES CATÉGORIES NE SONT PLUS DE CE VOYAGE, et c'est un piège qu'il
  -- faut nommer : elles appartiennent désormais à l'enseigne, donc leur
  -- « boutique_id » vaut null POUR TOUJOURS. Cette ligne les rattachait
  -- toutes à la première boutique — à chaque relecture du fichier, et
  -- sans un mot. Le rattrapage ne concerne plus que les produits.
  update public.produits   set boutique_id = premiere where boutique_id is null;
  -- Ni le slider de l'enseigne ni sa publicité n'appartiennent à une
  -- boutique : ils resteraient rangés là où ils n'ont rien à faire.
  update public.slides     set boutique_id = premiere
   where boutique_id is null and portee not in ('enseigne', 'publicite');
end $$;

create index if not exists produits_boutique   on public.produits(boutique_id);
create index if not exists categories_boutique on public.categories(boutique_id);

-- ---------- Masquer un produit (3.59.0) ----------
-- Un produit MASQUÉ disparaît du catalogue des clients sans être
-- supprimé : sa fiche, ses photos, son code et ses ventes restent, et il
-- revient d'un geste. On garde qui l'a masqué, et quand.
alter table public.produits add column if not exists masque boolean not null default false;
alter table public.produits add column if not exists masque_par text not null default '';
alter table public.produits add column if not exists masque_le timestamptz;
create index if not exists slides_boutique     on public.slides(boutique_id);

-- ---------- Comptes de l'application admin et leurs rôles ----------
-- Trois rôles, du plus large au plus étroit :
--   superadministrateur — toute l'enseigne : il crée les boutiques, les
--                         comptes de tous rangs, et règle BIZZOO ;
--   administrateur      — TOUT sur SA boutique : produits, rayons,
--                         slider, réglages, et les modérateurs de
--                         celle-ci. Rien en dehors ;
--   moderateur          — produits et rayons de sa boutique, rien d'autre.
create table if not exists public.profils (
  id      uuid primary key references auth.users(id) on delete cascade,
  email   text not null default '',
  role    text not null default 'moderateur'
          check (role in ('superadministrateur', 'administrateur',
                          'moderateur', 'livreur')),
  actif   boolean not null default true,
  -- Droit accordé au cas par cas : modifier un produit déjà au catalogue.
  -- Sans lui, le modérateur peut en ajouter de nouveaux, pas toucher aux autres.
  peut_modifier_produits boolean not null default true,
  -- Boutique du compte : administrateur et modérateur n'agissent que sur
  -- celle-là. À null pour un superadministrateur, qui circule dans toutes.
  boutique_id text references public.boutiques(id) on delete set null,
  cree_le timestamptz not null default now()
);
alter table public.profils
  add column if not exists peut_modifier_produits boolean not null default true;
alter table public.profils
  add column if not exists boutique_id text references public.boutiques(id) on delete set null;

-- ---------- Ce qu'on sait d'une personne ----------
-- « profils » ne portait qu'une adresse e-mail. Un livreur qu'on choisit
-- dans une liste se reconnaît à son NOM, et se rattrape à son NUMÉRO
-- quand le client n'est pas chez lui.
alter table public.profils add column if not exists nom text not null default '';
alter table public.profils add column if not exists tel text not null default '';
-- (3.64.0) Le véhicule du livreur : une commande en tricycle ne se propose
-- qu'aux livreurs en tricycle. Sans objet pour le reste de l'équipe.
alter table public.profils add column if not exists vehicule text not null default 'moto';
alter table public.profils drop constraint if exists profils_vehicule;
alter table public.profils add constraint profils_vehicule check (vehicule in ('moto', 'tricycle'));
-- Le livreur bloqué par l'administration de BIZZOO (BIZZOO Personnel) :
-- il ne reçoit plus aucune course. Seul « rh_bloquer_livreur » le pose.
alter table public.profils add column if not exists courses_bloquees boolean not null default false;
-- (3.63.0) Qui l'a créé, et s'il attend sa validation : les règles de
-- « profils », plus bas, les lisent. Posées ici, avant elles — la suite
-- du fichier les répète là où elles sont expliquées.
alter table public.profils add column if not exists cree_par uuid;
alter table public.profils add column if not exists a_valider boolean not null default false;

-- ---------- Les interrupteurs des comptes d'enseigne ----------
-- Ils ne servent QU'aux comptes d'enseigne — administrateur ou
-- modérateur rattaché à aucune boutique. Un compte de boutique est déjà
-- borné par sa boutique ; le superadministrateur passe au-dessus.
alter table public.profils
  add column if not exists peut_commandes boolean not null default true;
alter table public.profils
  add column if not exists peut_boutiques boolean not null default false;
alter table public.profils
  add column if not exists peut_finances  boolean not null default false;

-- Le rôle accepte désormais « superadministrateur ».
alter table public.profils drop constraint if exists profils_role_check;
alter table public.profils add constraint profils_role_check
  check (role in ('superadministrateur', 'administrateur', 'moderateur', 'livreur'));

-- Les administrateurs d'avant tenaient toute l'application : ils
-- deviennent superadministrateurs, sans quoi ils se retrouveraient
-- enfermés dans une boutique qu'ils n'ont pas.
--
-- SOUS CONDITION, ET C'EST INDISPENSABLE DEPUIS LES COMPTES
-- D'ENSEIGNE. « administrateur sans boutique » ne veut plus dire « base
-- d'avant » : c'est désormais un ADMINISTRATEUR DE BIZZOO, créé
-- exprès, avec des droits volontairement limités. Sans le « if » qui
-- suit, un simple rejeu de ce fichier l'aurait promu superadministrateur
-- — il aurait gagné l'argent, les comptes et l'enseigne entière, en
-- silence. On ne rattrape donc que les bases où PERSONNE ne tient
-- encore l'enseigne, ce qui est exactement le cas qu'on visait.
-- ELLE PORTE UN NOM, ET CE N'EST PAS DU CONFORT. Écrite en « do $$ »
-- anonyme, cette garde ne s'éprouve pas : un banc ne peut que recopier
-- la même logique à côté, et il éprouve alors SA copie — il reste vert
-- pendant que le vrai fichier promeut tout le monde. Nommée, elle
-- s'appelle, et le banc éprouve celle qui s'exécutera vraiment.
create or replace function public.rattraper_anciens_admins() returns int
language plpgsql security definer set search_path = public as $$
declare combien int := 0;
begin
  -- Quelqu'un tient déjà l'enseigne : il n'y a rien à rattraper, et
  -- tout à perdre. On sort avant de toucher à quoi que ce soit.
  if exists (select 1 from public.profils
              where role = 'superadministrateur') then
    return 0;
  end if;
  update public.profils set role = 'superadministrateur'
   where role = 'administrateur' and boutique_id is null;
  get diagnostics combien = row_count;
  return combien;
end $$;
revoke all on function public.rattraper_anciens_admins()
  from public, anon, authenticated;
select public.rattraper_anciens_admins();

-- ---------- La session de l'équipe, confirmée par SMS ----------
-- Quand l'enseigne l'exige, un compte de l'équipe reçoit un code par SMS
-- à CHAQUE connexion, et n'a aucun droit tant qu'il ne l'a pas rendu.
-- Le détail — l'envoi, la saisie, l'interrupteur — est au chapitre « La
-- connexion de l'équipe confirmée par SMS », à la fin de ce fichier.
-- Seul ce qui suit doit vivre ICI, avant « role_courant() » : la base
-- vérifie déjà des droits pendant que ce fichier se charge, et la
-- fonction doit trouver tout ce qu'elle lit déjà posé.
--
-- L'INTERRUPTEUR VIT À PART, pas dans « reglages » : cette table-là n'est
-- posée que bien plus loin. Il part éteint — rien ne change tant qu'un
-- superadministrateur ne l'a pas allumé.
create table if not exists public.securite_equipe (
  id         int primary key default 1 check (id = 1),
  sms_exige  boolean not null default false,
  change_le  timestamptz,
  change_par text not null default ''
);
insert into public.securite_equipe (id) values (1) on conflict (id) do nothing;

-- Les sessions qui ont rendu leur code. « session_id » est celui que
-- GoTrue pose dans chaque jeton : une connexion, une session, un code.
create table if not exists public.sessions_sms (
  session_id   uuid primary key,
  utilisateur  uuid not null,
  confirmee_le timestamptz not null default now()
);

-- Invisibles depuis l'API : aucune règle de lecture, aucun droit. Seules
-- les fonctions de confiance y touchent.
alter table public.securite_equipe enable row level security;
alter table public.sessions_sms enable row level security;
revoke all on public.securite_equipe from public, anon, authenticated;
revoke all on public.sessions_sms from public, anon, authenticated;

-- La session du jeton en cours. Un jeton sans session — la clé de
-- service, un visiteur — n'en a pas, et rien ne le confirme.
create or replace function public.session_courante() returns uuid
language sql stable as $$
  select case when s ~* '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z'
              then s::uuid end
    from (select coalesce(auth.jwt() ->> 'session_id', '') as s) x;
$$;

-- L'enseigne exige-t-elle le code ? Une ligne absente répond « non » :
-- même règle que le compte obligatoire. Un accident ne doit pas enfermer
-- toute l'équipe dehors un samedi soir.
create or replace function public.sms_equipe_exige() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select s.sms_exige from public.securite_equipe s where s.id = 1), false);
$$;

-- Cette session a-t-elle rendu son code ?
create or replace function public.session_confirmee() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.sessions_sms s
     where s.session_id = public.session_courante()
       and s.utilisateur = auth.uid())
  /* UN LIVREUR ENTRÉ PAR SON NUMÉRO a déjà rendu un code : celui de
     Supabase (numéro, mot de passe, puis code — 3.59.0). Le jeton le
     dit, signé par GoTrue : méthode « otp », numéro confirmé. Lui
     redemander le code de l'équipe, ce serait deux SMS pour une seule
     porte. Les autres rangs gardent leur code d'équipe, inchangé. */
  or (coalesce(auth.jwt() ->> 'phone', '') <> ''
      and exists (select 1 from jsonb_array_elements(
                    case when jsonb_typeof(auth.jwt() -> 'amr') = 'array'
                         then auth.jwt() -> 'amr' else '[]'::jsonb end) a
                   where a ->> 'method' = 'otp')
      and exists (select 1 from public.profils p
                   where p.id = auth.uid() and p.role = 'livreur'));
$$;

-- L'équipe est-elle en service ? Oui quand rien n'est exigé ; sinon,
-- seulement avec une session confirmée.
--
-- (3.59.0) LE CODE NE VAUT PLUS QUE POUR LE SUPERADMINISTRATEUR. Les
-- administrateurs, modérateurs et livreurs entrent avec leur mot de passe
-- seul : un SMS à chaque connexion pesait sur tout le monde pour protéger
-- surtout le compte qui peut tout. On lit la table, pas « role_courant »,
-- qui s'appuie lui-même sur cette fonction.
create or replace function public.equipe_en_service() returns boolean
language sql stable security definer set search_path = public as $$
  select not public.sms_equipe_exige()
      or public.session_confirmee()
      or not exists (select 1 from public.profils p
                      where p.id = auth.uid() and p.role = 'superadministrateur');
$$;
revoke all on function public.session_courante() from public, anon;
revoke all on function public.sms_equipe_exige() from public, anon;
revoke all on function public.session_confirmee() from public, anon;
revoke all on function public.equipe_en_service() from public, anon;
grant execute on function public.session_courante() to authenticated;
grant execute on function public.sms_equipe_exige() to authenticated;
grant execute on function public.session_confirmee() to authenticated;
grant execute on function public.equipe_en_service() to authenticated;

-- Rôle du compte connecté. « security definer » : la fonction lit la table
-- sans repasser par les règles RLS — sinon les règles s'appelleraient elles-mêmes.
--
-- QUAND L'ENSEIGNE EXIGE LE CODE SMS, une session dont le code n'a pas
-- été rendu n'a AUCUN rang : ni superadministrateur, ni administrateur,
-- ni livreur. Tous les droits de l'équipe découlent d'ici — un seul
-- endroit à fermer, et tout est fermé.
create or replace function public.role_courant() returns text
language sql stable security definer set search_path = public as $$
  select role from public.profils
   where id = auth.uid() and actif and public.equipe_en_service();
$$;

-- Le superadministrateur : l'enseigne entière, boutiques comprises.
create or replace function public.est_super() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'superadministrateur', false);
$$;

-- « Droits d'administration » : le superadministrateur partout, et
-- l'administrateur dans sa boutique. Les règles qui appellent cette
-- fonction ajoutent, quand il le faut, la vérification de la boutique.
create or replace function public.est_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in ('superadministrateur', 'administrateur'), false);
$$;

-- Membre de l'équipe qui TIENT la boutique : catalogue, commandes,
-- avis, réclamations.
--
-- LE LIVREUR N'EN EST PAS, et c'est tout l'objet de cette liste. Il a un
-- profil, donc « role_courant() » lui répond — mais il ne tient rien. La
-- version d'avant disait « n'importe quel profil actif », et le jour où
-- le rang « livreur » est arrivé, cela lui aurait ouvert d'un coup :
-- les commandes de toute la boutique, le journal, les chiffres de
-- vente, le dépôt de photos. Rien de tout cela n'est son travail.
--
-- Une seule fonction à corriger plutôt que neuf endroits : c'est
-- justement pour cela qu'elle existe.
create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;

-- Celui qui porte la marchandise, et rien d'autre.
create or replace function public.est_livreur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'livreur', false);
$$;

-- ---------- Le compte d'enseigne ----------
-- Un rang entre la boutique et le superadministrateur : administrateur
-- ou modérateur rattaché à AUCUNE boutique, qui travaille au nom de
-- BIZZOO. Ses droits ne viennent pas de son rang mais d'interrupteurs,
-- réglés un par un par le superadministrateur.
--
-- LES QUATRE CONDITIONS COMPTENT. « de l'équipe » écarte le livreur,
-- qui a lui aussi une boutique nulle quand on l'a créé sans en choisir
-- une. « pas superadministrateur » parce que celui-là n'a pas besoin
-- d'interrupteurs : lui en poser l'enfermerait dans sa propre maison.
--
-- Elle lit la fiche elle-même : elle doit donc AUSSI passer par
-- « role_courant() », qui sait si la session a donné son code SMS.
-- Sans cela, un compte de BIZZOO entré sans son code aurait gardé ses
-- interrupteurs — et les commandes de toutes les boutiques avec eux.
create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false)
     and public.role_courant() is not null;
$$;

-- L'ADMINISTRATEUR DE BIZZOO : un administrateur rattaché à aucune
-- boutique (3.59.0). Il crée et gère les livreurs, crée les comptes
-- revendeurs et valide leurs demandes — comme le superadministrateur,
-- mais sans toucher au reste de l'équipe. Un modérateur de BIZZOO, non.
create or replace function public.est_admin_bizzoo() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'administrateur', false)
     and public.est_compte_enseigne();
$$;
revoke all on function public.est_admin_bizzoo() from public, anon;
grant execute on function public.est_admin_bizzoo() to authenticated;

-- Un interrupteur de l'enseigne, lu sur la fiche du compte. Il ne vaut
-- VRAI que pour un compte d'enseigne : sur un compte de boutique la
-- colonne existe aussi, et sans cette condition elle lui ouvrirait des
-- portes que son rang ne lui donne pas.
create or replace function public.droit_enseigne(lequel text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_compte_enseigne() and coalesce((
    select case lequel
             when 'commandes' then p.peut_commandes
             when 'boutiques' then p.peut_boutiques
             when 'finances'  then p.peut_finances
             when 'produits'  then p.peut_modifier_produits
             else false
           end
      from public.profils p
     where p.id = auth.uid() and p.actif), false);
$$;

-- Peut-il retoucher un produit déjà au catalogue ? L'administrateur
-- d'une boutique toujours ; le modérateur seulement si on le lui
-- accorde ; le compte d'enseigne selon SON interrupteur.
--
-- « est_equipe() » EN PREMIER, et ce n'est pas une précaution de style :
-- « peut_modifier_produits » vaut VRAI par défaut sur tout profil. Sans
-- cette condition, un livreur qu'on vient de créer pourrait modifier le
-- catalogue — la colonne lui aurait dit oui.
--
-- POUR UN COMPTE D'ENSEIGNE, LA COLONNE FAIT FOI quel que soit son
-- rang. La version d'avant disait « administrateur, donc oui » : un
-- administrateur de BIZZOO à qui on aurait fermé le catalogue l'aurait
-- gardé ouvert, et l'interrupteur n'aurait été qu'un dessin.
create or replace function public.peut_modifier_produits() returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when public.est_super() then true
    when public.est_compte_enseigne() then public.droit_enseigne('produits')
    -- L'HABILITATION VAUT POUR TOUS (3.59.0), administrateur de boutique
    -- compris : retirée, on ne crée, ne modifie ni ne supprime plus de
    -- produit. Seul le superadministrateur passe outre.
    else public.est_equipe()
     and coalesce((select peut_modifier_produits
                     from public.profils where id = auth.uid() and actif), false)
  end;
$$;

-- Qui a le droit de LIRE et de faire avancer les commandes.
create or replace function public.peut_voir_commandes() returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.droit_enseigne('commandes')
      or (public.est_equipe() and not public.est_compte_enseigne());
$$;

-- Le journal des versements et les chiffres de vente.
create or replace function public.peut_voir_finances() returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.droit_enseigne('finances')
      or (public.est_equipe() and not public.est_compte_enseigne());
$$;

-- La boutique à laquelle le compte est rattaché. Null pour un
-- administrateur : il n'est enfermé nulle part.
--
-- Null aussi pour une session qui n'a pas donné son code SMS quand
-- l'enseigne l'exige : partout où elle sert, une boutique nulle ferme
-- la porte au lieu de l'ouvrir.
create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;

-- A-t-il le droit de toucher à ce qui appartient à cette boutique-là ?
-- Le superadministrateur partout ; le compte d'enseigne partout aussi,
-- mais les droits FINS se posent par-dessus, table par table — le
-- catalogue par « peut_modifier_produits() », les commandes par
-- « peut_voir_commandes() ». Les comptes de boutique, dans la leur.
create or replace function public.peut_agir_sur(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.est_compte_enseigne()
      or (public.est_equipe() and cible is not null
          and cible = public.boutique_du_compte());
$$;

-- Droits d'administration SUR cette boutique-là : le superadministrateur
-- partout, le compte d'enseigne à qui on a donné l'interrupteur, et
-- l'administrateur uniquement chez lui.
create or replace function public.administre(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.droit_enseigne('boutiques')
      or (public.est_admin() and cible is not null
          and cible = public.boutique_du_compte());
$$;

-- Les règles de sécurité, y compris celles du stockage des photos,
-- appellent ces fonctions au nom du compte connecté.
grant execute on function public.peut_modifier_produits() to authenticated;
grant execute on function public.role_courant() to authenticated;
grant execute on function public.est_admin() to authenticated;
-- Fermée aux visiteurs, comme « categories-bizzoo.sql » la pose sur une
-- base en service : schema.sql seul la laissait ouverte à « anon », et
-- une base neuve n'arrivait pas où arrive la base en ligne. Les règles
-- qui l'appellent directement ne valent que pour un compte connecté ;
-- les autres passent par une fonction de confiance, qui l'exécute en
-- son nom propre.
revoke all on function public.est_equipe() from public, anon, authenticated;
grant execute on function public.est_equipe() to authenticated;
revoke all on function public.est_livreur() from public, anon, authenticated;
grant execute on function public.est_livreur() to authenticated;
grant execute on function public.boutique_du_compte() to authenticated;
grant execute on function public.peut_agir_sur(text) to authenticated;
grant execute on function public.est_super() to authenticated;
grant execute on function public.administre(text) to authenticated;
revoke all on function public.est_compte_enseigne()  from public, anon;
revoke all on function public.droit_enseigne(text)   from public, anon;
revoke all on function public.peut_voir_commandes()  from public, anon;
revoke all on function public.peut_voir_finances()   from public, anon;
grant execute on function public.est_compte_enseigne() to authenticated;
grant execute on function public.droit_enseigne(text)  to authenticated;
grant execute on function public.peut_voir_commandes() to authenticated;
grant execute on function public.peut_voir_finances()  to authenticated;

-- Tout compte créé (par l'application ou dans le tableau de bord Supabase)
-- reçoit une fiche en attente : l'administrateur l'active et lui donne son rôle.
create or replace function public.profil_nouveau_compte() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  /* LE NUMÉRO D'UN LIVREUR N'OUVRE PAS DE COMPTE CLIENT (3.59.0). Avant,
     un livreur qui entrait par son numéro dans l'application client y
     recevait un second compte, d'acheteur — d'où « Devenir revendeur »
     et « Mes commandes » sous ses yeux. Il entre avec SON compte. */
  if coalesce(new.raw_user_meta_data ->> 'compte', '') <> 'equipe'
     and coalesce(new.phone, '') <> ''
     and (coalesce(new.raw_user_meta_data ->> 'compte', '') = 'client' or coalesce(new.email, '') = '')
     and public.numero_de_livreur(new.phone) then
    raise exception 'NUMERO_LIVREUR : ce numéro est celui d''un livreur BIZZOO'
      using errcode = 'P0001';
  end if;
  /* UN CLIENT N'EST PAS UN COMPTE D'ÉQUIPE EN ATTENTE. L'application
     cliente s'inscrit en posant « compte: client » ; sans ce test, chaque
     acheteur apparaîtrait dans la liste des comptes de l'enseigne, et il
     suffirait d'un clic distrait pour donner à un client les droits d'un
     modérateur sur une boutique. */
  if coalesce(new.raw_user_meta_data ->> 'compte', '') = 'client' then
    return new;
  end if;
  /* Un compte qui n'a qu'un numéro est un acheteur, même si les
     métadonnées manquent — elles viennent du téléphone, après tout.
     SAUF « compte: equipe » : c'est un livreur que l'administrateur crée
     par son numéro (3.59.0). Il reçoit, comme les autres, sa fiche en
     attente — que l'administrateur active dans la foulée. */
  if coalesce(new.email, '') = '' and coalesce(new.phone, '') <> ''
     and coalesce(new.raw_user_meta_data ->> 'compte', '') <> 'equipe' then
    return new;
  end if;
  insert into public.profils (id, email, role, actif)
  values (new.id, coalesce(new.email, ''), 'moderateur', false)
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists profil_a_la_creation on auth.users;
create trigger profil_a_la_creation
  after insert on auth.users
  for each row execute function public.profil_nouveau_compte();

-- Les comptes qui existaient avant les rôles deviennent
-- superadministrateurs : personne ne se retrouve enfermé dehors.
insert into public.profils (id, email, role, actif)
select u.id, coalesce(u.email, ''), 'superadministrateur', true from auth.users u
on conflict (id) do nothing;

alter table public.profils enable row level security;

-- ---------- On ne touche pas à son créateur (3.59.0) ----------
-- Un compte créé par un autre ne modifie pas les droits de celui qui l'a
-- créé — ni du créateur de celui-ci, et ainsi de suite en remontant : un
-- superadministrateur nommé par un autre ne peut pas le rétrograder, le
-- désactiver, changer son mot de passe ni le supprimer. On remonte la
-- chaîne « cree_par » depuis le compte connecté (vingt crans au plus,
-- et jamais deux fois le même compte).
-- En plpgsql : « cree_par » n'est posée que plus bas, et une fonction SQL
-- serait vérifiée dès sa création.
create or replace function public.est_mon_createur(cible uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return cible is not null and auth.uid() is not null and cible <> auth.uid() and exists (
  with recursive chaine(id, cran, vus) as (
    select p.cree_par, 1, array[p.id]
      from public.profils p
     where p.id = auth.uid() and p.cree_par is not null
    union all
    select p.cree_par, c.cran + 1, c.vus || p.id
      from chaine c
      join public.profils p on p.id = c.id
     where p.cree_par is not null and c.cran < 20 and not (p.id = any(c.vus))
  )
  select 1 from chaine where chaine.id = cible);
end $$;
revoke all on function public.est_mon_createur(uuid) from public, anon;
grant execute on function public.est_mon_createur(uuid) to authenticated;

-- ---------- Le modérateur créé par l'administrateur de BIZZOO (3.63.0) ----------
-- Demande du CEO : l'administrateur de BIZZOO crée un compte modérateur,
-- et c'est le superadministrateur qui le valide. Le compte naît donc
-- inactif et « à valider » (voir « profil_validation ») ; son créateur le
-- voit, le retouche et peut le retirer tant qu'il attend — l'activer,
-- jamais.
--
-- Utilisée par « gere_le_compte » (mot de passe, retrait).
create or replace function public.mon_moderateur(cible uuid, en_attente boolean)
returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return public.est_admin_bizzoo() and exists (
    select 1 from public.profils p
     where p.id = cible and p.role = 'moderateur' and p.cree_par = auth.uid()
       and (not en_attente or p.a_valider));
end $$;
revoke all on function public.mon_moderateur(uuid, boolean) from public, anon;
grant execute on function public.mon_moderateur(uuid, boolean) to authenticated;

drop policy if exists "profils lecture" on public.profils;
drop policy if exists "profils ajout admin" on public.profils;
drop policy if exists "profils modification admin" on public.profils;
drop policy if exists "profils suppression admin" on public.profils;
-- Chacun voit sa fiche. Le superadministrateur voit toute l'enseigne ;
-- l'administrateur, l'équipe de sa boutique — et la fiche toute fraîche
-- qu'il est en train de créer : sans la voir, PostgreSQL ne le laisse
-- pas lui donner son rang (voir « profils modification admin »).
create policy "profils lecture" on public.profils
  for select to authenticated using (
    id = auth.uid()
    or public.est_super()
    or (public.est_admin() and boutique_id is not null
        and boutique_id = public.boutique_du_compte())
    or (public.est_admin() and role = 'moderateur' and not actif
        and boutique_id is null and cree_le > now() - interval '15 minutes')
    -- L'administrateur de BIZZOO voit tous les livreurs (3.59.0).
    or (public.est_admin_bizzoo() and role = 'livreur')
    -- (3.63.0) Et les modérateurs qu'il a créés. Les colonnes de la LIGNE,
    -- pas une relecture de la table : à la création, la ligne neuve doit se
    -- lire alors que la table garde encore l'ancienne.
    or (public.est_admin_bizzoo() and role = 'moderateur' and cree_par = auth.uid()));

-- Créer, modifier, supprimer un compte : le superadministrateur sans
-- limite ; l'administrateur seulement des MODÉRATEURS et des LIVREURS
-- (3.59.0) de SA boutique — il ne se nomme pas de pairs et ne touche pas
-- à ses supérieurs.
create policy "profils ajout admin" on public.profils
  for insert to authenticated with check (
    public.est_super()
    or (public.est_admin() and role in ('moderateur', 'livreur')
        and boutique_id is not null and boutique_id = public.boutique_du_compte())
    -- L'administrateur de BIZZOO crée des livreurs — et (3.63.0) des
    -- modérateurs INACTIFS, que le superadministrateur validera.
    or (public.est_admin_bizzoo() and role = 'livreur')
    or (public.est_admin_bizzoo() and role = 'moderateur' and not actif));
-- « Créer un compte » passe par deux temps : l'inscription pose une
-- fiche en attente, SANS boutique, puis l'administrateur lui donne son
-- rang. Le premier membre de « using » exigeait une fiche déjà de sa
-- boutique : l'administrateur d'une boutique ne pouvait donc jamais
-- finir de créer un modérateur — seul le superadministrateur y
-- arrivait. Le second lui ouvre la fiche toute fraîche, encore en
-- attente, née dans le quart d'heure ; « with check » ne change pas :
-- elle ne peut devenir qu'un modérateur de SA boutique.
create policy "profils modification admin" on public.profils
  for update to authenticated
  using (
    -- (3.59.0) Le superadministrateur, sauf sur celui qui l'a créé.
    (public.est_super() and not public.est_mon_createur(id))
    or (public.est_admin() and role in ('moderateur', 'livreur')
        and boutique_id is not null and boutique_id = public.boutique_du_compte())
    or (public.est_admin() and role = 'moderateur' and not actif
        and boutique_id is null and cree_le > now() - interval '15 minutes')
    or (public.est_admin_bizzoo() and role = 'livreur')
    -- (3.63.0) Le modérateur qu'il a créé, tant qu'il attend sa validation.
    or (public.est_admin_bizzoo() and role = 'moderateur' and a_valider
        and cree_par = auth.uid()))
  with check (
    public.est_super()
    -- (3.59.0) Un modérateur ou un livreur de SA boutique — jamais un
    -- administrateur.
    or (public.est_admin() and role in ('moderateur', 'livreur')
        and boutique_id is not null and boutique_id = public.boutique_du_compte())
    -- Un livreur reste un livreur : l'administrateur de BIZZOO ne fait
    -- de personne un administrateur.
    or (public.est_admin_bizzoo() and role = 'livreur')
    -- (3.63.0) Un modérateur, mais INACTIF : c'est le superadministrateur
    -- qui l'active.
    or (public.est_admin_bizzoo() and role = 'moderateur' and not actif));
create policy "profils suppression admin" on public.profils
  for delete to authenticated using (
    (public.est_super() and not public.est_mon_createur(id))
    or (public.est_admin() and role in ('moderateur', 'livreur')
        and boutique_id is not null and boutique_id = public.boutique_du_compte())
    or (public.est_admin_bizzoo() and role = 'livreur')
    or (public.est_admin_bizzoo() and role = 'moderateur' and a_valider
        and cree_par = auth.uid()));

-- ---------- Gestion des comptes par l'administrateur ----------
-- Supprimer un compte ou changer son mot de passe demande des droits que
-- l'application n'a pas : sa clé est publiable, et la clé « service_role »
-- ne doit jamais quitter le serveur. Ces deux fonctions font le travail à
-- sa place, en vérifiant elles-mêmes qui appelle.

-- crypt() / gen_salt() servent à chiffrer le mot de passe comme le fait
-- Supabase lui-même.
create extension if not exists pgcrypto with schema extensions;

-- Qui a le droit d'agir sur ce compte-là ? Le superadministrateur sur
-- tous ; l'administrateur seulement sur les modérateurs et les livreurs
-- (3.59.0) de sa boutique.
--
-- (3.63.0) ET L'ADMINISTRATEUR DE BIZZOO SUR TOUS LES LIVREURS. Les
-- règles de « profils » le lui permettaient déjà — créer, modifier,
-- retirer un livreur, de n'importe quelle boutique ou de BIZZOO — mais
-- cette fonction l'avait oublié : « Redonner un mot de passe » et
-- « Supprimer » lui répondaient « Ce compte n'est pas sous votre
-- responsabilité ». Un livreur, et rien d'autre : ni modérateur, ni
-- administrateur.
create or replace function public.gere_le_compte(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  -- (3.59.0) Jamais sur celui qui vous a créé, ni plus haut.
  select not public.est_mon_createur(cible) and (public.est_super()
      or (public.est_admin() and exists (
            select 1 from public.profils p
             where p.id = cible and p.role in ('moderateur', 'livreur')
               and p.boutique_id is not null
               and p.boutique_id = public.boutique_du_compte()))
      or (public.est_admin_bizzoo() and exists (
            select 1 from public.profils p
             where p.id = cible and p.role = 'livreur'))
      -- (3.63.0) Le modérateur qu'il a créé, tant qu'il attend sa validation.
      or public.mon_moderateur(cible, true));
$$;
grant execute on function public.gere_le_compte(uuid) to authenticated;

create or replace function public.supprimer_compte(cible uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.gere_le_compte(cible) then
    raise exception 'Ce compte n''est pas sous votre responsabilité';
  end if;
  if cible = auth.uid() then
    raise exception 'On ne supprime pas son propre compte';
  end if;
  delete from auth.users where id = cible;   -- la fiche profils suit (cascade)
  if not found then
    raise exception 'Compte introuvable';
  end if;
end $$;

create or replace function public.changer_mot_de_passe(cible uuid, nouveau text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.gere_le_compte(cible) then
    raise exception 'Ce compte n''est pas sous votre responsabilité';
  end if;
  if length(coalesce(nouveau, '')) < 6 then
    raise exception 'Le mot de passe doit faire 6 caractères au moins';
  end if;
  update auth.users
     set encrypted_password = extensions.crypt(nouveau, extensions.gen_salt('bf')),
         updated_at = now()
   where id = cible;
  if not found then
    raise exception 'Compte introuvable';
  end if;
  /* Les sessions ouvertes avec l'ancien mot de passe tombent. */
  delete from auth.sessions where user_id = cible;
end $$;

-- Personne d'autre qu'un compte connecté ne peut même tenter l'appel.
-- « anon » est nommé : Supabase lui accorde chaque fonction nommément,
-- et « retirer à public » ne lui retirait rien — un visiteur pouvait
-- tenter l'appel, que seul le contrôle du dedans arrêtait.
revoke all on function public.supprimer_compte(uuid) from public, anon;
revoke all on function public.changer_mot_de_passe(uuid, text) from public, anon;
grant execute on function public.supprimer_compte(uuid) to authenticated;
grant execute on function public.changer_mot_de_passe(uuid, text) to authenticated;

-- ---------- Journal des actions de l'application admin ----------
-- Qui a fait quoi, et quand. Lisible uniquement par l'administrateur.
-- ---------- Les comptes clients ----------
-- ---------------------------------------------------------
-- 1. Qui est le client
-- ---------------------------------------------------------
create table if not exists public.clients (
  id          uuid primary key references auth.users(id) on delete cascade,
  nom         text not null default '',
  -- Le numéro national, chiffres seulement — la même forme que
  -- « commandes.client_tel », sans quoi on ne pourrait pas les rapprocher.
  tel         text not null default '',
  indicatif   text not null default '229',
  -- Posé UNIQUEMENT par la vérification par SMS. Voir le verrou plus bas.
  tel_verifie boolean not null default false,
  adresse     text not null default '',
  cree_le     timestamptz not null default now(),
  maj_le      timestamptz not null default now()
);

-- Sur une base déjà en service, le corps du « create table » n'est pas relu.
alter table public.clients add column if not exists tel_verifie boolean not null default false;
alter table public.clients add column if not exists adresse text not null default '';
alter table public.clients add column if not exists indicatif text not null default '229';

-- Un numéro vérifié ne désigne qu'un compte. Deux comptes qui
-- revendiquent le même numéro se disputeraient les mêmes commandes.
create unique index if not exists clients_tel_verifie
  on public.clients(tel) where tel_verifie and tel <> '';

-- ---------- Client ordinaire, ou revendeur ----------
-- Un compte se crée en deux sortes. « client » paie le prix affiché en
-- vitrine ; « revendeur » achète pour revendre, et paie le PRIX BIZZOO
-- — celui que la boutique a annoncé à la création du produit.
--
-- Deux colonnes, et toute la sécurité tient dans leur différence :
--   « type_compte »    est la DEMANDE du client. Il l'écrit lui-même,
--                      et c'est voulu : une demande n'est pas un droit.
--   « revendeur_etat » est la RÉPONSE de BIZZOO. Seule
--                      valider_revendeur() l'écrit ; le verrou plus bas
--                      refuse qu'elle vienne d'ailleurs.
alter table public.clients add column if not exists type_compte text not null default 'client';
--   'aucune'     — compte client ordinaire, rien de demandé
--   'en_attente' — la demande attend le superadministrateur
--   'validee'    — le compte achète au prix BIZZOO
--   'refusee'    — refusée, avec un motif que le client lit
alter table public.clients add column if not exists revendeur_etat text not null default 'aucune';
-- Ce que le demandeur dit de son commerce : sans quoi valider
-- reviendrait à signer un nom et une adresse e-mail.
alter table public.clients add column if not exists revendeur_message text not null default '';
-- OÙ SE TROUVE CE COMMERCE. Un nom et une phrase ne suffisent pas à
-- décider : l'enseigne veut savoir si elle a affaire à une boutique de
-- Dantokpa ou à quelqu'un qui revend depuis son salon.
--
-- Les deux formes se complètent, et aucune n'est obligatoire :
--   l'ADRESSE ÉCRITE — au Bénin, c'est elle qui permet de trouver : un
--     quartier, un repère, « derrière la pharmacie » ;
--   les COORDONNÉES — relevées par le téléphone ou tirées d'un lien de
--     carte. Elles ouvrent l'itinéraire d'un seul geste.
--
-- Ce n'est PAS l'adresse de livraison du client (« adresse », plus
-- haut) : on peut se faire livrer chez soi et tenir boutique ailleurs.
alter table public.clients add column if not exists revendeur_adresse text not null default '';
alter table public.clients add column if not exists revendeur_latitude double precision;
alter table public.clients add column if not exists revendeur_longitude double precision;
alter table public.clients add column if not exists revendeur_demande_le timestamptz;
alter table public.clients add column if not exists revendeur_decide_par text not null default '';
alter table public.clients add column if not exists revendeur_decide_le timestamptz;
alter table public.clients add column if not exists revendeur_motif text not null default '';

alter table public.clients drop constraint if exists clients_type_compte;
alter table public.clients add constraint clients_type_compte
  check (type_compte in ('client', 'revendeur'));
alter table public.clients drop constraint if exists clients_revendeur_etat;
alter table public.clients add constraint clients_revendeur_etat
  check (revendeur_etat in ('aucune', 'en_attente', 'validee', 'refusee'));

create index if not exists clients_revendeur_attente
  on public.clients(revendeur_demande_le desc) where revendeur_etat = 'en_attente';

alter table public.clients enable row level security;

-- ---------------------------------------------------------
-- 2. Un compte est de l'équipe OU d'un client, jamais les deux
-- ---------------------------------------------------------
-- Le gérant d'une boutique qui veut acheter ailleurs crée un second
-- compte, avec une autre adresse. C'est un petit inconfort contre une
-- grande clarté : sans cette règle, chaque droit écrit pour l'équipe
-- devrait être relu en se demandant « et si c'était aussi un client ? ».
-- ---------- Ce numéro est-il celui d'un livreur ? ----------
-- Un livreur n'est ni un acheteur ni un revendeur (3.59.0). Son numéro
-- est sur sa fiche d'équipe ; on compare les HUIT DERNIERS CHIFFRES :
-- « 97 12 15 96 », « 01 97 12 15 96 » et « +229 01 97 12 15 96 » sont le
-- même téléphone — le Bénin est passé de 8 à 10 chiffres en ajoutant
-- « 01 » devant. Réservée aux fonctions du serveur : elle ne dit à
-- personne quels numéros sont ceux des livreurs.
create or replace function public.numero_de_livreur(numero text) returns boolean
language sql stable security definer set search_path = public as $$
  select length(regexp_replace(coalesce(numero, ''), '\D', '', 'g')) >= 8
     and exists (
       select 1 from public.profils p
        where p.actif and p.role = 'livreur'
          and length(regexp_replace(coalesce(p.tel, ''), '\D', '', 'g')) >= 8
          and right(regexp_replace(p.tel, '\D', '', 'g'), 8)
            = right(regexp_replace(numero, '\D', '', 'g'), 8));
$$;
revoke all on function public.numero_de_livreur(text) from public, anon, authenticated;

-- Le compte connecté, vu de l'application client : un livreur (son
-- propre compte), ou un compte client ouvert avec le numéro d'un
-- livreur (« double ») — avant la 3.59.0, entrer par son numéro dans
-- l'application client créait ce second compte. Ni l'un ni l'autre ne
-- voit les rubriques d'acheteur.
create or replace function public.mon_compte_livreur() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  livreur boolean;
  numero text;
begin
  if moi is null then return jsonb_build_object('livreur', false, 'double', false); end if;
  select exists (select 1 from public.profils p where p.id = moi and p.actif and p.role = 'livreur')
    into livreur;
  numero := coalesce(nullif(auth.jwt() ->> 'phone', ''),
                     (select c.tel from public.clients c where c.id = moi), '');
  return jsonb_build_object(
    'livreur', livreur,
    'double', not livreur
              and not exists (select 1 from public.profils p where p.id = moi and p.actif)
              and public.numero_de_livreur(numero));
end $$;
revoke all on function public.mon_compte_livreur() from public, anon;
grant execute on function public.mon_compte_livreur() to authenticated;

create or replace function public.compte_unique() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'clients' then
    /* Un profil EN ATTENTE ne vaut aucun droit : personne n'a encore
       décidé quoi que ce soit de ce compte. Les comptes créés hors de
       l'application cliente — dans le tableau de bord Supabase, par
       exemple — en reçoivent un ; devenir client l'efface, et rien n'est
       perdu. Un profil ACTIF, lui, porte de vrais droits sur une
       boutique : on ne le mélange pas avec un compte d'acheteur. */
    delete from public.profils p
     where p.id = new.id and not p.actif and p.role = 'moderateur';
    if exists (select 1 from public.profils p where p.id = new.id) then
      raise exception 'Ce compte est déjà un compte de l''équipe : un compte client demande une autre adresse';
    end if;
  else
    if exists (select 1 from public.clients c where c.id = new.id) then
      raise exception 'Ce compte est déjà un compte client : un compte d''équipe demande une autre adresse';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists clients_pas_equipe on public.clients;
create trigger clients_pas_equipe
  before insert or update on public.clients
  for each row execute function public.compte_unique();

drop trigger if exists profils_pas_client on public.profils;
create trigger profils_pas_client
  before insert or update on public.profils
  for each row execute function public.compte_unique();

-- Le compte connecté est-il un client ? « security definer » : la fonction
-- lit la table sans repasser par RLS, sinon les règles s'appelleraient
-- elles-mêmes.
create or replace function public.est_client() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.clients c where c.id = auth.uid());
$$;
grant execute on function public.est_client() to authenticated;

-- ---------------------------------------------------------
-- 3. Le client ne se déclare pas vérifié lui-même
-- ---------------------------------------------------------
-- C'est LE point de sécurité de ce fichier. Le drapeau « tel_verifie »
-- ouvrira l'accès aux commandes passées avec ce numéro : s'il s'écrivait
-- depuis l'application, il suffirait de taper le numéro d'un autre pour
-- lire ses commandes, ses adresses et ses achats.
--
-- Seule une fonction du serveur peut le poser, et elle pose du même coup
-- le numéro : on ne peut pas faire vérifier un numéro puis en changer.
-- Le statut de revendeur suit exactement la même règle, et pour la même
-- raison : demander reste libre — c'est le sens de « type_compte » —
-- mais la demande remet la décision à zéro. On ne se refait pas valider
-- en se déclarant client puis revendeur.
-- Une coordonnée hors de ses bornes n'est pas une coordonnée : c'est une
-- faute de frappe, un lien mal recopié, ou un « NaN » qu'un téléphone a
-- rendu sans le dire. On l'efface plutôt que de la garder — un point
-- faux sur une carte est pire que pas de point du tout.
create or replace function public.coord_valable(valeur double precision, borne double precision)
returns double precision
language sql immutable as $$
  select case when valeur is null
                or valeur <> valeur              -- « NaN » ne s'égale pas lui-même
                or valeur < -borne or valeur > borne
              then null else valeur end;
$$;
revoke all on function public.coord_valable(double precision, double precision)
  from public, anon, authenticated;
grant execute on function public.coord_valable(double precision, double precision)
  to anon, authenticated;

create or replace function public.client_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  decision boolean := coalesce(current_setting('bizzoo.revendeur', true), '') = 'oui';
begin
  if not decision then
    if new.revendeur_etat       is distinct from old.revendeur_etat
    or new.revendeur_decide_par is distinct from old.revendeur_decide_par
    or new.revendeur_decide_le  is distinct from old.revendeur_decide_le
    or new.revendeur_motif      is distinct from old.revendeur_motif then
      raise exception 'Un compte revendeur se valide chez BIZZOO, il ne se déclare pas';
    end if;
    if new.type_compte is distinct from old.type_compte then
      if new.type_compte = 'revendeur' then
        -- UN LIVREUR NE DEVIENT PAS REVENDEUR (3.59.0), même par un compte
        -- client ouvert avec son numéro.
        if public.numero_de_livreur(coalesce(nullif(new.tel, ''), auth.jwt() ->> 'phone', '')) then
          raise exception 'Un livreur BIZZOO ne devient pas revendeur.' using errcode = 'P0001';
        end if;
        -- Déjà validé : on ne redemande pas ce qu'on a.
        if old.revendeur_etat <> 'validee' then
          new.revendeur_etat       := 'en_attente';
          new.revendeur_demande_le := now();
          new.revendeur_decide_par := '';
          new.revendeur_decide_le  := null;
          new.revendeur_motif      := '';
        end if;
      else
        -- Redevenir client ordinaire rend le statut : le reprendre
        -- demandera une nouvelle décision.
        new.revendeur_etat       := 'aucune';
        new.revendeur_demande_le := null;
        new.revendeur_decide_par := '';
        new.revendeur_decide_le  := null;
        new.revendeur_motif      := '';
      end if;
    end if;
  end if;

  new.revendeur_message := left(coalesce(new.revendeur_message, ''), 300);
  -- La position du commerce, remise d'aplomb. Elle s'écrit librement —
  -- c'est la DÉCLARATION du demandeur, comme son message — mais elle ne
  -- part pas n'importe où : hors bornes, elle disparaît.
  new.revendeur_latitude  := public.coord_valable(new.revendeur_latitude, 90);
  new.revendeur_longitude := public.coord_valable(new.revendeur_longitude, 180);
  -- Une latitude sans longitude ne désigne rien. Et « 0, 0 » est un
  -- point au large du Ghana : c'est ce que rend un téléphone qui n'a
  -- rien trouvé, jamais une boutique de Cotonou.
  if new.revendeur_latitude is null or new.revendeur_longitude is null
     or (new.revendeur_latitude = 0 and new.revendeur_longitude = 0) then
    new.revendeur_latitude  := null;
    new.revendeur_longitude := null;
  end if;
  new.revendeur_adresse := left(coalesce(new.revendeur_adresse, ''), 200);

  if coalesce(current_setting('bizzoo.verification', true), '') = 'oui' then
    return new;   -- la vérification par SMS, et elle seule
  end if;
  if new.tel_verifie is distinct from old.tel_verifie then
    raise exception 'Un numéro se vérifie par SMS, il ne se déclare pas';
  end if;
  if old.tel_verifie and new.tel is distinct from old.tel then
    raise exception 'Un numéro vérifié ne se change pas : refaites une vérification';
  end if;
  return new;
end $$;

drop trigger if exists clients_verrous on public.clients;
create trigger clients_verrous
  before update on public.clients
  for each row execute function public.client_verrous();

-- Un compte client naît toujours non vérifié ET non validé, quoi qu'en
-- dise l'insertion. S'inscrire comme revendeur dépose une demande, rien
-- de plus : c'est ce que fait le formulaire d'inscription.
create or replace function public.client_a_l_ecriture() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('bizzoo.verification', true), '') <> 'oui' then
    new.tel_verifie := false;
  end if;
  new.tel := left(regexp_replace(coalesce(new.tel, ''), '\D', '', 'g'), 20);
  if coalesce(new.type_compte, '') <> 'revendeur' then
    new.type_compte          := 'client';
    new.revendeur_etat       := 'aucune';
    new.revendeur_demande_le := null;
  else
    if public.numero_de_livreur(coalesce(nullif(new.tel, ''), auth.jwt() ->> 'phone', '')) then
      raise exception 'Un livreur BIZZOO ne devient pas revendeur.' using errcode = 'P0001';
    end if;
    new.revendeur_etat       := 'en_attente';
    new.revendeur_demande_le := now();
  end if;
  new.revendeur_message    := left(coalesce(new.revendeur_message, ''), 300);
  -- La position du commerce, remise d'aplomb. Elle s'écrit librement —
  -- c'est la DÉCLARATION du demandeur, comme son message — mais elle ne
  -- part pas n'importe où : hors bornes, elle disparaît.
  new.revendeur_latitude  := public.coord_valable(new.revendeur_latitude, 90);
  new.revendeur_longitude := public.coord_valable(new.revendeur_longitude, 180);
  -- Une latitude sans longitude ne désigne rien. Et « 0, 0 » est un
  -- point au large du Ghana : c'est ce que rend un téléphone qui n'a
  -- rien trouvé, jamais une boutique de Cotonou.
  if new.revendeur_latitude is null or new.revendeur_longitude is null
     or (new.revendeur_latitude = 0 and new.revendeur_longitude = 0) then
    new.revendeur_latitude  := null;
    new.revendeur_longitude := null;
  end if;
  new.revendeur_adresse := left(coalesce(new.revendeur_adresse, ''), 200);
  new.revendeur_decide_par := '';
  new.revendeur_decide_le  := null;
  new.revendeur_motif      := '';
  return new;
end $$;

drop trigger if exists clients_ecriture on public.clients;
create trigger clients_ecriture
  before insert on public.clients
  for each row execute function public.client_a_l_ecriture();

-- ---------------------------------------------------------
-- 4. Ce qu'un client voit de lui-même
-- ---------------------------------------------------------
drop policy if exists "clients lecture" on public.clients;
create policy "clients lecture" on public.clients
  for select to authenticated
  using (id = auth.uid() or public.est_super());

drop policy if exists "clients creation" on public.clients;
create policy "clients creation" on public.clients
  for insert to authenticated with check (id = auth.uid());

drop policy if exists "clients modification" on public.clients;
create policy "clients modification" on public.clients
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- L'enseigne ne modifie pas un compte client : elle le voit, c'est tout.
-- Un compte se supprime depuis le compte lui-même, ou avec auth.users.

-- ---------------------------------------------------------
-- 5. Le prix d'un revendeur
-- ---------------------------------------------------------
-- L'écran et la caisse doivent dire le même prix, sinon le client voit
-- un montant et en paie un autre. La règle vit donc en un seul endroit,
-- et les deux la lisent : mes_prix() pour l'affichage,
-- ligne_a_l_ecriture() pour la facture.
--
-- Prix BIZZOO à zéro : la boutique ne l'a pas renseigné. Le produit
-- reste alors au prix public — pour personne il ne devient gratuit.
--
-- LA MARGE REVENDEUR. Vendre au prix BIZZOO exact ne rapportait rien à
-- L'ENSEIGNE : la boutique touchait bien ce qu'elle voulait toucher, et
-- BIZZOO ne prenait pas un franc au passage. Pire, le revendeur lisait
-- article par article ce que la boutique touche — ce que
-- « produits_prive » existe précisément pour cacher.
--
-- Le revendeur paie donc un prix CALCULÉ, de l'une des deux façons —
-- chaque boutique choisit la sienne, dans ses réglages :
--
--   'bizzoo'  prix BIZZOO + N %. L'enseigne gagne sur chaque vente, et
--             ce que la boutique touche cesse d'être lisible.
--   'public'  prix public − N %. C'est ainsi qu'un revendeur raisonne :
--             « j'ai N % de remise ».
--
-- Deux bornes, quel que soit le mode et quel que soit le taux saisi :
--
--   JAMAIS SOUS LE PRIX BIZZOO. Une remise de 60 % sur un produit dont
--   la marge est de 20 % ferait vendre à perte, sans que personne ne
--   s'en aperçoive avant les comptes.
--   JAMAIS AU-DESSUS DU PRIX PUBLIC. Un revendeur qui paierait plus cher
--   qu'un client de passage n'aurait aucune raison de rester.
--
-- Si le prix public est DÉJÀ sous le prix BIZZOO — une fin de série que
-- la boutique solde — les deux bornes se contredisent. C'est le plafond
-- qui l'emporte : la perte est déjà consentie en vitrine, et le
-- revendeur paie le prix public.
--
-- Arrondi à 5 FCFA, la plus petite pièce qui circule. Vers le HAUT en
-- mode « bizzoo » pour que la marge ne soit jamais rabotée, vers le BAS
-- en mode « public » pour que la remise annoncée soit toujours tenue.
--
-- L'ancienne règle ne prenait que deux arguments. La laisser en place
-- rendrait tout appel à deux arguments AMBIGU — PostgreSQL refuserait
-- alors « function is not unique », et plus aucune commande ne
-- passerait. On la retire donc avant de poser celle-ci.
drop function if exists public.prix_revendeur(int, int);
create or replace function public.prix_revendeur(
  prix_public int,
  prix_bizzoo int,
  taux        numeric default 0,
  mode        text    default 'bizzoo')
returns int
language sql immutable as $$
  with borne as (
    select greatest(0, coalesce(prix_public, 0))::numeric as public,
           greatest(0, coalesce(prix_bizzoo, 0))::numeric as achat,
           -- Un taux hors de [0, 100] est une faute de saisie, pas une
           -- intention : on le ramène, on ne refuse pas la vente.
           greatest(0, least(100, coalesce(taux, 0)))      as t,
           case when mode = 'public' then 'public' else 'bizzoo' end as m
  ),
  brut as (
    select public, achat, m,
           case when m = 'public' then public * (1 - t / 100)
                                  else achat  * (1 + t / 100) end as p
      from borne
  ),
  arrondi as (
    select public, achat,
           case when m = 'public' then floor(p / 5) * 5
                                  else ceil (p / 5) * 5 end as p
      from brut
  )
  select case when achat <= 0 then public::int
              -- plancher au prix BIZZOO, PUIS plafond au prix public :
              -- dans cet ordre, le plafond l'emporte quand les deux se
              -- contredisent.
              else least(public, greatest(p, achat))::int end
    from arrondi;
$$;
revoke all on function public.prix_revendeur(int, int, numeric, text)
  from public, anon, authenticated;

-- Le compte connecté est-il un revendeur VALIDÉ ? Demander ne suffit
-- pas : seul « validee » ouvre les prix.
create or replace function public.est_revendeur() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.clients c
                  where c.id = auth.uid() and c.revendeur_etat = 'validee');
$$;
revoke all on function public.est_revendeur() from public, anon, authenticated;
grant execute on function public.est_revendeur() to authenticated;

-- Les prix que ce compte-ci a le droit de voir.
--
-- « produits_prive » reste fermée : elle porte aussi les taux de marge
-- de chaque boutique, et un revendeur n'a rien à y lire. Il reçoit
-- d'ici une liste de prix, et rien qu'une liste de prix.
--
-- Qui n'est pas revendeur validé reçoit zéro ligne — pas une erreur :
-- l'application appelle la même fonction pour tout le monde.
create or replace function public.mes_prix()
returns table (produit_id text, prix int)
language sql stable security definer set search_path = public as $$
  select p.id,
         public.prix_revendeur(
           coalesce(p.prix, 0)::int,
           greatest(0, coalesce(pv.prix_grossiste, 0))::int,
           -- Le taux du produit l'emporte sur celui de la boutique ; à
           -- null, c'est celui de la boutique. Le mode, lui, reste une
           -- décision de boutique : une seule façon de faire par enseigne
           -- de quartier, sinon plus personne ne sait à quoi s'attendre.
           coalesce(pv.taux_revendeur, b.taux_revendeur, 0),
           coalesce(b.revendeur_mode, 'bizzoo'))
    from public.produits p
    left join public.produits_prive pv on pv.produit_id = p.id
    left join public.boutiques b on b.id = p.boutique_id
   where public.est_revendeur();
$$;
revoke all on function public.mes_prix() from public, anon, authenticated;
grant execute on function public.mes_prix() to authenticated;

-- ---------------------------------------------------------
-- 6. BIZZOO tranche
-- ---------------------------------------------------------
-- La liste que voit le superadministrateur. L'adresse e-mail vient de
-- « auth.users », que personne ne lit directement : c'est la fonction
-- qui va la chercher, après avoir vérifié qui appelle.
--
-- Elle rend aussi OÙ SE TROUVE le commerce : adresse écrite et
-- coordonnées. Décider sans savoir où revient à signer un nom et une
-- adresse e-mail.
--
-- « drop » avant « create » : ajouter une colonne au résultat d'une
-- fonction change son type de retour, et PostgreSQL refuse de le
-- changer sur place — « cannot change return type of existing
-- function ». Sans ce retrait, le fichier échouerait en entier.
drop function if exists public.revendeurs(text);
create or replace function public.revendeurs(filtre text default 'en_attente')
returns table (
  id uuid, nom text, email text, tel text, indicatif text,
  message text, etat text, demande_le timestamptz,
  decide_par text, decide_le timestamptz, motif text,
  adresse text, latitude double precision, longitude double precision)
language sql stable security definer set search_path = public as $$
  select c.id, c.nom, coalesce(u.email, '')::text, c.tel, c.indicatif,
         c.revendeur_message, c.revendeur_etat, c.revendeur_demande_le,
         c.revendeur_decide_par, c.revendeur_decide_le, c.revendeur_motif,
         c.revendeur_adresse, c.revendeur_latitude, c.revendeur_longitude
    from public.clients c
    left join auth.users u on u.id = c.id
   where (public.est_super() or public.est_admin_bizzoo())
     and c.revendeur_etat <> 'aucune'
     and (coalesce(filtre, '') = '' or c.revendeur_etat = filtre)
   order by c.revendeur_demande_le desc nulls last;
$$;
revoke all on function public.revendeurs(text) from public, anon, authenticated;
grant execute on function public.revendeurs(text) to authenticated;

-- ---------- La fiche d'un client ----------
-- Un client appelle : « j'ai commandé mardi, rien n'est arrivé ». Sans
-- cet écran, il fallait parcourir les commandes une à une. La liste se
-- cherche par nom ou par numéro, et chaque fiche porte ce que le compte
-- a fait : combien de commandes, combien payées, combien dépensé.
--
-- RÉSERVÉE À L'ENSEIGNE, et c'est délibéré. Une boutique voit déjà le
-- nom et le numéro sur SES commandes ; lui ouvrir la liste entière, ce
-- serait lui remettre le fichier clients de toutes les autres.
--
-- Zéro ligne plutôt qu'une erreur pour qui n'y a pas droit : l'écran
-- est déjà fermé côté application, et une erreur ne renseignerait que
-- celui qui la provoque.
create or replace function public.clients_liste(
  filtre text default '',
  cible  uuid default null)
returns table (
  id uuid, nom text, email text, tel text, indicatif text,
  tel_verifie boolean, adresse text, cree_le timestamptz,
  type_compte text, revendeur_etat text,
  revendeur_adresse text,
  revendeur_latitude double precision, revendeur_longitude double precision,
  commandes bigint, payees bigint, total_paye bigint, derniere timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare
  cherche  text := lower(trim(coalesce(filtre, '')));
  -- Un numéro se tape « 97 22 22 22 », « +229 97222222 » ou « 97222222 ».
  -- On ne garde que les chiffres des deux côtés pour les rapprocher.
  chiffres text := regexp_replace(cherche, '\D', '', 'g');
begin
  if not public.est_super() then return; end if;
  return query
    select c.id, c.nom, coalesce(u.email, '')::text, c.tel, c.indicatif,
           c.tel_verifie, c.adresse, c.cree_le,
           c.type_compte, c.revendeur_etat,
           c.revendeur_adresse, c.revendeur_latitude, c.revendeur_longitude,
           count(v.id)::bigint,
           count(v.id) filter (where v.etat = 'payee')::bigint,
           coalesce(sum(v.total) filter (where v.etat = 'payee'), 0)::bigint,
           max(v.cree_le)
      from public.clients c
      left join auth.users u on u.id = c.id
      left join public.commandes v on v.client_id = c.id
     where (cible is null or c.id = cible)
       -- Le « ou » du numéro n'ouvre RIEN quand la recherche ne contient
       -- aucun chiffre : sans cette garde, « like '%%' » serait vrai pour
       -- tout le monde et une recherche par nom rendrait toute la liste.
       and (cherche = ''
            or lower(c.nom) like '%' || cherche || '%'
            or (chiffres <> '' and c.tel like '%' || chiffres || '%')
            -- Un numéro se donne souvent avec son indicatif — « +229 97 22
            -- 22 22 » — alors que la colonne ne garde que le national. On
            -- retire l'indicatif DE CE COMPTE, pas une longueur devinée :
            -- tous les pays n'ont pas des numéros de huit chiffres.
            -- La condition de longueur est la même garde que plus haut :
            -- taper « 229 » seul ne doit pas vider le fichier.
            or (chiffres <> '' and coalesce(c.indicatif, '') <> ''
                and chiffres like c.indicatif || '%'
                and length(chiffres) > length(c.indicatif)
                and c.tel like '%' || substr(chiffres, length(c.indicatif) + 1) || '%'))
     group by c.id, u.email, c.nom, c.tel, c.indicatif, c.tel_verifie,
              c.adresse, c.cree_le, c.type_compte, c.revendeur_etat,
              c.revendeur_adresse, c.revendeur_latitude, c.revendeur_longitude
     -- Les plus récemment actifs d'abord : c'est de ceux-là qu'on parle
     -- au téléphone. Les comptes sans commande suivent, par ancienneté.
     order by max(v.cree_le) desc nulls last, c.cree_le desc
     limit 200;
end $$;
revoke all on function public.clients_liste(text, uuid) from public, anon;
grant execute on function public.clients_liste(text, uuid) to authenticated;

-- Les commandes d'un client — celles que la base lui a rattachées, ET
-- celles d'avant son compte.
--
-- CES DERNIÈRES SUIVENT EXACTEMENT LA RÈGLE DE rattacher_mes_commandes :
-- numéro VÉRIFIÉ, commande sans compte, moins de dix-huit mois. Pas une
-- règle voisine — la même. Un numéro non vérifié ne désigne personne :
-- deux clients peuvent taper le même, et l'un lirait les achats de
-- l'autre depuis cet écran.
create or replace function public.client_commandes(client uuid)
returns table (
  id text, numero text, cree_le timestamptz, paye_le timestamptz,
  etat text, total bigint, revendeur boolean,
  articles bigint, boutiques text, rattachee boolean)
language plpgsql stable security definer set search_path = public as $$
declare mien public.clients%rowtype;
begin
  if not public.est_super() or client is null then return; end if;
  select * into mien from public.clients where clients.id = client;
  if not found then return; end if;
  return query
    select v.id, v.numero, v.cree_le, v.paye_le, v.etat,
           v.total::bigint, v.revendeur,
           count(l.id)::bigint,
           coalesce(string_agg(distinct b.nom, ', '), '')::text,
           v.client_id is not null
      from public.commandes v
      left join public.commande_lignes l on l.commande_id = v.id
      left join public.boutiques b on b.id = l.boutique_id
     where v.client_id = client
        or (v.client_id is null
            and not v.compte_supprime
            and mien.tel_verifie and coalesce(mien.tel, '') <> ''
            and v.client_tel = mien.tel
            and v.cree_le > now() - interval '18 months')
     group by v.id, v.numero, v.cree_le, v.paye_le, v.etat,
              v.total, v.revendeur, v.client_id
     order by v.cree_le desc
     limit 100;
end $$;
revoke all on function public.client_commandes(uuid) from public, anon;
grant execute on function public.client_commandes(uuid) to authenticated;

-- Valider, ou refuser avec un motif. Le drapeau « bizzoo.revendeur »
-- est ce qui distingue cette fonction d'une requête ordinaire : sans
-- lui, le verrou ci-dessus refuserait l'écriture — y compris venant du
-- superadministrateur lui-même.
create or replace function public.valider_revendeur(
  cible uuid, accord boolean, raison text default '')
returns text
language plpgsql security definer set search_path = public as $$
declare
  qui  text;
  etat text;
begin
  -- Le superadministrateur, ou un administrateur de BIZZOO (3.59.0).
  if not (public.est_super() or public.est_admin_bizzoo()) then
    raise exception 'Seul BIZZOO valide un compte revendeur';
  end if;
  select coalesce(p.email, '') into qui from public.profils p where p.id = auth.uid();
  etat := case when accord then 'validee' else 'refusee' end;

  -- UN REVENDEUR VALIDE SON COMPTE EN ACTIVANT SA POSITION : la
  -- géolocalisation de son téléphone, ET son adresse écrite. Sans elles,
  -- BIZZOO ne l'accepte pas (il peut toujours refuser).
  if accord and not exists (
       select 1 from public.clients c
        where c.id = cible
          and c.revendeur_latitude is not null and c.revendeur_longitude is not null
          and length(trim(coalesce(c.revendeur_adresse, ''))) >= 3) then
    raise exception 'Ce revendeur n''a pas encore enregistré sa position : il doit activer la localisation de son téléphone dans son compte, et indiquer son adresse.'
      using errcode = 'P0001';
  end if;

  -- Une demande déposée avant la 3.59.0 avec le numéro d'un livreur ne
  -- se valide pas : un livreur n'est pas revendeur.
  if accord and exists (select 1 from public.clients c
                         where c.id = cible and public.numero_de_livreur(c.tel)) then
    raise exception 'Ce numéro est celui d''un livreur BIZZOO : un livreur ne devient pas revendeur.'
      using errcode = 'P0001';
  end if;

  perform set_config('bizzoo.revendeur', 'oui', true);
  update public.clients
     set revendeur_etat       = etat,
         type_compte          = case when accord then 'revendeur' else type_compte end,
         revendeur_decide_par = coalesce(qui, ''),
         revendeur_decide_le  = now(),
         revendeur_motif      = left(coalesce(raison, ''), 300),
         maj_le               = now()
   where id = cible;
  if not found then
    perform set_config('bizzoo.revendeur', '', true);
    raise exception 'Compte introuvable';
  end if;
  -- Le drapeau est rendu tel qu'il était : il ne vaut que pour la
  -- ligne qu'on vient d'écrire, pas pour la suite de l'appel.
  perform set_config('bizzoo.revendeur', '', true);
  return etat;
end $$;

revoke all on function public.valider_revendeur(uuid, boolean, text)
  from public, anon, authenticated;
grant execute on function public.valider_revendeur(uuid, boolean, text) to authenticated;

-- ---------- BIZZOO crée un compte revendeur (3.59.0) ----------
-- L'application admin inscrit le compte (numéro + mot de passe, comme le
-- client le ferait), puis pose ici sa fiche : une DEMANDE en attente,
-- avec le commerce et l'adresse. Le revendeur entre ensuite avec son
-- numéro, son mot de passe et le code reçu par SMS, active la position de
-- son téléphone dans « Mon compte » — et BIZZOO valide.
--
-- Seulement sur un compte tout neuf (moins d'une heure), qui n'est ni de
-- l'équipe ni déjà client : on ne réécrit pas la fiche de quelqu'un.
create or replace function public.creer_fiche_revendeur(
  cible uuid, nom text, tel text, message text default '', adresse text default '')
returns text
language plpgsql security definer set search_path = public as $$
begin
  -- (3.59.0) L'administrateur d'une boutique aussi : il crée la fiche, la
  -- demande reste EN ATTENTE, et BIZZOO seul la valide.
  if not (public.est_super() or public.est_admin_bizzoo() or public.est_admin()) then
    raise exception 'Seul un administrateur crée un compte revendeur';
  end if;
  if not exists (select 1 from auth.users u
                  where u.id = cible and u.created_at > now() - interval '1 hour') then
    raise exception 'Ce compte n''est pas un compte qu''on vient de créer';
  end if;
  if exists (select 1 from public.profils p where p.id = cible)
     or exists (select 1 from public.clients c where c.id = cible) then
    raise exception 'Ce compte a déjà sa fiche';
  end if;
  if length(regexp_replace(coalesce(tel, ''), '\D', '', 'g')) < 8 then
    raise exception 'Le numéro du revendeur est incomplet';
  end if;
  insert into public.clients (id, nom, tel, type_compte, revendeur_message, revendeur_adresse)
  values (cible, left(trim(coalesce(nom, '')), 120), tel, 'revendeur',
          left(trim(coalesce(message, '')), 300), left(trim(coalesce(adresse, '')), 200));
  return 'en_attente';
end $$;
revoke all on function public.creer_fiche_revendeur(uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.creer_fiche_revendeur(uuid, text, text, text, text) to authenticated;

create table if not exists public.journal (
  id          bigint generated always as identity primary key,
  fait_le     timestamptz not null default now(),
  utilisateur text not null default '',
  famille     text not null default 'autre',  -- produit | categorie | boutique | compte
  action      text not null default '',       -- ajout | modification | suppression | …
  libelle     text not null default '',       -- phrase lisible par le gérant
  cible       text not null default ''        -- nom du produit, de la catégorie…
);
-- Annuler une action : on garde de quoi remettre les choses en place.
--   retour = { "avant": [ { "table": "produits", "ligne": {…} } ],
--              "ids":   [ { "table": "produits", "id": "prod_x" } ] }
-- Une ligne présente dans « avant » est réécrite telle quelle ;
-- une ligne absente est supprimée — c'est ainsi qu'on annule un ajout.
alter table public.journal add column if not exists cible_table text not null default '';
alter table public.journal add column if not exists retour jsonb;
alter table public.journal add column if not exists annule_le timestamptz;
alter table public.journal add column if not exists annule_par text not null default '';
-- De quelle boutique parle cette ligne. C'est ce qui décide qui la lit :
-- l'administrateur des cosmétiques n'a pas à savoir ce qui se passe en
-- informatique. À null, la ligne parle de l'enseigne elle-même et ne se
-- montre qu'au superadministrateur.
alter table public.journal add column if not exists boutique_id text
  references public.boutiques(id) on delete set null;
create index if not exists journal_date on public.journal(fait_le desc);
create index if not exists journal_boutique on public.journal(boutique_id);

alter table public.journal enable row level security;

drop policy if exists "journal lecture connectee" on public.journal;
drop policy if exists "journal ecriture connectee" on public.journal;
-- Le journal n'est PAS public : l'administrateur le lit, l'équipe
-- l'alimente. Et chacun ne lit que SA boutique : l'administrateur des
-- cosmétiques n'a pas à savoir ce qui se passe en informatique — noms
-- de produits, prix, mouvements de comptes. Les lignes sans boutique
-- parlent de l'enseigne, et ne se montrent qu'au superadministrateur.
create policy "journal lecture connectee" on public.journal
  for select to authenticated using (
    public.est_super()
    or (public.est_admin() and boutique_id is not null
        and boutique_id = public.boutique_du_compte()));
-- (Les deux rangs d'administrateur lisent l'historique ; le modérateur non.)
create policy "journal ecriture connectee" on public.journal
  for insert to authenticated with check (public.est_equipe());
-- Marquer une action comme annulée : le superadministrateur seul. Lui
-- seul peut annuler, et l'annulation touche parfois une autre boutique
-- que la sienne.
drop policy if exists "journal annulation" on public.journal;
create policy "journal annulation" on public.journal
  for update to authenticated using (public.est_super()) with check (public.est_super());

-- ---------- Le journal ne se laisse pas forger ----------
-- Toute l'équipe écrit ici — il le faut bien. Mais « retour » dit au
-- bouton « annuler » quelles lignes réécrire et DANS QUELLE TABLE, et
-- c'est le superadministrateur qui clique : c'est donc SON compte qui
-- écrit. Sans garde-fou, un modérateur déposait une fausse ligne au
-- libellé anodin dont l'annulation le nommait superadministrateur.
--
-- Deux verrous : on ne signe que de son nom, et « retour » ne peut
-- viser que les tables du catalogue. « profils » n'y est pas.
-- « profils » manque volontairement : voir plus bas, elle n'est permise
-- qu'au superadministrateur, et seulement pour lui-même.
create or replace function public.journal_tables_permises() returns text[]
language sql immutable as $$
  select array['produits', 'produits_prive', 'categories', 'sous_categories',
               'slides', 'boutiques', 'boutique'];
$$;

create or replace function public.journal_verifie() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  t text;
begin
  -- Qui écrit est lu dans le jeton, jamais dans le corps de la requête.
  new.utilisateur := coalesce(
    (select p.email from public.profils p where p.id = auth.uid()), '');
  -- Qui n'est pas superadministrateur ne range sa trace que chez lui.
  if not public.est_super() then
    new.boutique_id := public.boutique_du_compte();
  end if;
  -- Une ligne naît toujours non annulée.
  new.annule_le  := null;
  new.annule_par := '';

  if new.retour is not null then
    if jsonb_typeof(new.retour) <> 'object' then
      raise exception 'Journal : « retour » doit être un objet';
    end if;
    for t in
      select x->>'table' from jsonb_array_elements(
        coalesce(new.retour->'avant', '[]'::jsonb)) x
      union all
      select x->>'table' from jsonb_array_elements(
        coalesce(new.retour->'ids', '[]'::jsonb)) x
    loop
      -- « profils » n'est acceptée que d'un superadministrateur : c'est
      -- par elle que passerait une prise de pouvoir, et un modérateur
      -- qui l'écrirait tendrait un piège à celui qui clique.
      if t = 'profils' then
        if not public.est_super() then
          raise exception 'Journal : une action sur les comptes ne s''annule qu''entre les mains du superadministrateur';
        end if;
      elsif t is null or not (t = any(public.journal_tables_permises())) then
        raise exception 'Journal : table interdite dans une annulation (%)',
          coalesce(t, 'aucune');
      end if;
    end loop;
  end if;
  return new;
end $$;

drop trigger if exists journal_a_l_ecriture on public.journal;
create trigger journal_a_l_ecriture
  before insert on public.journal
  for each row execute function public.journal_verifie();

-- Une ligne d'historique ne se réécrit pas : seule l'annulation s'y
-- inscrit. Sans cela, on pourrait récrire le passé.
create or replace function public.journal_immuable() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.fait_le     is distinct from old.fait_le
  or new.utilisateur is distinct from old.utilisateur
  or new.famille     is distinct from old.famille
  or new.action      is distinct from old.action
  or new.libelle     is distinct from old.libelle
  or new.cible       is distinct from old.cible
  or new.cible_table is distinct from old.cible_table
  or new.boutique_id is distinct from old.boutique_id
  or new.retour      is distinct from old.retour then
    raise exception 'Une ligne du journal ne se modifie pas : seule l''annulation s''y inscrit';
  end if;
  return new;
end $$;

drop trigger if exists journal_a_la_modification on public.journal;
create trigger journal_a_la_modification
  before update on public.journal
  for each row execute function public.journal_immuable();

-- ---------- Demandes de validation ----------
-- Une boutique ne change pas seule ce qui la représente auprès des
-- clients : nom, logo, description, adresse, contacts, et les écrans
-- de son slider. Elle dépose une demande ; l'enseigne tranche.
-- Le verrou est plus bas, sur « boutiques » et « slides » : sans lui
-- la validation ne serait qu'un détour poli.
create table if not exists public.demandes (
  id          text primary key,
  boutique_id text not null references public.boutiques(id) on delete cascade,
  -- 'reglages' : nom, logo, description, adresse, contacts.
  -- 'slider'   : un écran du slider de la boutique.
  type        text not null check (type in ('reglages', 'slider')),
  objet       text not null default '',   -- « Nom, adresse » : ce qui change, en clair
  avant       jsonb,                      -- l'état d'aujourd'hui, pour comparer
  apres       jsonb not null,             -- ce qui est demandé
  cible_id    text,                       -- l'écran de slider visé, s'il existe déjà
  demande_par text not null default '',
  demande_le  timestamptz not null default now(),
  etat        text not null default 'en_attente'
              check (etat in ('en_attente', 'approuvee', 'refusee')),
  decide_par  text not null default '',
  decide_le   timestamptz,
  motif       text not null default ''    -- pourquoi un refus
);
create index if not exists demandes_boutique on public.demandes(boutique_id);
create index if not exists demandes_etat on public.demandes(etat, demande_le desc);

alter table public.demandes enable row level security;

drop policy if exists "demandes lecture"     on public.demandes;
drop policy if exists "demandes depot"       on public.demandes;
drop policy if exists "demandes decision"    on public.demandes;
drop policy if exists "demandes retrait"     on public.demandes;

-- Vous voyez tout ; un administrateur voit les siennes, et leur sort.
create policy "demandes lecture" on public.demandes
  for select to authenticated using (
    public.est_super() or public.administre(boutique_id));

-- Déposer une demande : l'administrateur de la boutique concernée.
create policy "demandes depot" on public.demandes
  for insert to authenticated with check (public.administre(boutique_id));

-- Trancher : vous seul.
create policy "demandes decision" on public.demandes
  for update to authenticated
  using (public.est_super()) with check (public.est_super());

-- Retirer : vous, ou celui qui l'a déposée tant qu'elle attend.
create policy "demandes retrait" on public.demandes
  for delete to authenticated using (
    public.est_super()
    or (public.administre(boutique_id) and etat = 'en_attente'));

-- Une demande naît en attente, signée de qui la dépose. On ne
-- s'approuve pas soi-même en glissant « approuvee » dans la requête.
create or replace function public.demande_a_l_ecriture() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.demande_par := coalesce(
    (select p.email from public.profils p where p.id = auth.uid()), '');
  new.demande_le  := now();
  new.etat        := 'en_attente';
  new.decide_par  := '';
  new.decide_le   := null;
  new.motif       := '';
  return new;
end $$;

drop trigger if exists demandes_a_l_ecriture on public.demandes;
create trigger demandes_a_l_ecriture
  before insert on public.demandes
  for each row execute function public.demande_a_l_ecriture();

-- ---------- Ligne de l'enseigne ----------
insert into public.boutique (id) values (1) on conflict (id) do nothing;

-- Numéro WhatsApp de l'enseigne (rempli seulement s'il est vide :
-- la valeur saisie ensuite dans l'app admin est toujours prioritaire).
update public.boutique set whatsapp = '69842516', maj_le = now()
where id = 1 and whatsapp = '';

-- Une fois le catalogue déménagé dans « INFORMATIQUE ET ELECTRONIQUE »,
-- cette ligne ne désigne plus un secteur mais l'enseigne : elle prend
-- son nom. Ses coordonnées restent celles d'avant — un bon point de
-- départ, que le gérant ajuste ensuite.
update public.boutique
   set nom = 'BIZZOO',
       slogan = case when slogan = 'Nous sommes imbattables en prix'
                     then 'Toutes vos boutiques' else slogan end,
       maj_le = now()
 where id = 1 and nom in ('IMPACT INFORMATIQUE', 'INFORMATIQUE ET ELECTRONIQUE');

-- ---------- Sécurité : lecture publique, écriture selon le rôle ----------
-- Le catalogue se lit par tous (application client).
-- Écriture : produits et catégories pour toute l'équipe, le reste pour
-- le seul administrateur. Les règles ci-dessous s'appliquent aussi aux
-- appels directs à la base : ce n'est pas qu'un décor dans l'application.
alter table public.boutique        enable row level security;
alter table public.boutiques       enable row level security;
alter table public.categories      enable row level security;
alter table public.sous_categories enable row level security;
alter table public.produits        enable row level security;
alter table public.slides          enable row level security;

-- Les boutiques : tout le monde les voit (le client en affiche la liste),
-- seul l'administrateur en crée, en modifie ou en ferme.
drop policy if exists "lecture publique"   on public.boutiques;
drop policy if exists "ecriture connectee" on public.boutiques;
drop policy if exists "boutiques creation super"    on public.boutiques;
drop policy if exists "boutiques reglages"          on public.boutiques;
drop policy if exists "boutiques suppression super" on public.boutiques;
create policy "lecture publique"   on public.boutiques for select using (true);
-- Créer, fermer, supprimer une boutique : décision de l'enseigne.
-- L'administrateur peut en revanche régler la sienne.
create policy "boutiques creation super" on public.boutiques
  for insert to authenticated with check (public.est_super());
create policy "boutiques reglages" on public.boutiques
  for update to authenticated
  using (public.administre(id)) with check (public.administre(id));
create policy "boutiques suppression super" on public.boutiques
  for delete to authenticated using (public.est_super());

-- L'administrateur règle sa boutique — slogan, secteur, icône, couleur,
-- horaires, devise, marge, photos, vidéo, réseaux — mais ce qui la
-- représente auprès des clients demande l'accord de l'enseigne, et
-- elle ne s'ouvre ni ne se ferme d'elle-même. RLS ne sait pas parler
-- colonne par colonne ; ce garde-fou le fait à sa place, et c'est lui
-- qui rend la validation autre chose qu'une politesse d'écran.
create or replace function public.champs_sous_validation() returns text[]
language sql immutable as $$
  select array['nom', 'logo', 'description', 'adresse', 'latitude', 'longitude',
               'tel', 'whatsapp', 'indicatif', 'telephones', 'adresses'];
$$;

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

-- ---------- Changer le secteur d'une boutique ----------
-- Le verrou refuse ce changement, et il a raison : les produits sont
-- rangés dans des sous-catégories de l'ANCIEN secteur, qui n'existent
-- pas dans le nouveau. Cette fonction-ci fait les deux gestes dans le
-- bon ordre et le dit : elle déclasse d'abord, elle change ensuite.
--
-- Elle rend le nombre de produits déclassés, pour que l'application
-- puisse le montrer AVANT de l'appeler et après. Ce n'est pas une
-- politesse : c'est la seule façon pour l'enseigne de savoir ce qu'elle
-- s'apprête à défaire.
-- Le paramètre s'appelait « secteur », comme la colonne du même nom sur
-- « boutiques » : plpgsql répondait « column reference "secteur" is
-- ambiguous » et la fonction s'arrêtait là. Un paramètre ne se renomme
-- pas par « create or replace » — il faut retirer l'ancienne signature.
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

-- ---------- La marge change, les prix suivent ----------
-- Le modèle est « prix de vente = prix BIZZOO + marge ». Mais le prix de
-- vente était CALCULÉ PAR L'APPLICATION au moment d'enregistrer le
-- produit, puis figé dans la table. Changer la marge d'une boutique ne
-- touchait donc rien : il fallait rouvrir et réenregistrer chaque
-- article, un par un, pour que la nouvelle marge s'applique.
--
-- Personne ne fait cela sur deux cents articles. En pratique, la marge
-- affichée dans les réglages et celle réellement pratiquée divergeaient
-- en silence — et les comptes de l'enseigne avec elles.
--
-- La base s'en charge donc elle-même. Un article qui a SON PROPRE taux
-- n'est pas touché par celui de la boutique : c'est déjà la règle que
-- « produits_prive.taux_marge » suit partout ailleurs.
--
-- On ne touche PAS « modifie_le ». C'est lui qui déclenche la
-- notification « catalogue mis à jour » sur les téléphones : un
-- changement de marge doit rafraîchir les écrans ouverts, pas réveiller
-- toute la ville.
create or replace function public.prix_public(prix_bizzoo bigint, taux numeric)
returns int
language sql immutable as $$
  -- Le même calcul, au franc près, que celui de l'application admin.
  -- Les deux doivent donner le même chiffre : sinon réenregistrer un
  -- produit déplacerait son prix sans que personne ne l'ait demandé.
  select case when coalesce(prix_bizzoo, 0) <= 0 then 0
              else round(prix_bizzoo * (1 + greatest(0, coalesce(taux, 0)) / 100))::int
         end;
$$;
revoke all on function public.prix_public(bigint, numeric) from public, anon, authenticated;
grant execute on function public.prix_public(bigint, numeric) to authenticated;

create or replace function public.boutique_prix_a_jour() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.taux_marge is not distinct from old.taux_marge then return new; end if;

  update public.produits p
     set prix = public.prix_public(pp.prix_grossiste,
                                   coalesce(pp.taux_marge, new.taux_marge))
    from public.produits_prive pp
   where pp.produit_id = p.id
     and p.boutique_id = new.id
     and coalesce(pp.prix_grossiste, 0) > 0
     -- N'écrire que ce qui change vraiment : un article dont le prix
     -- tombe juste n'a pas à passer par les déclencheurs pour rien.
     and p.prix is distinct from public.prix_public(pp.prix_grossiste,
                                   coalesce(pp.taux_marge, new.taux_marge));
  return new;
end $$;

drop trigger if exists boutiques_prix_a_jour on public.boutiques;
create trigger boutiques_prix_a_jour
  after update of taux_marge on public.boutiques
  for each row execute function public.boutique_prix_a_jour();

drop policy if exists "lecture publique"  on public.slides;
drop policy if exists "ecriture connectee" on public.slides;
-- Une vitrine se compose par celui à qui elle appartient, et tout le
-- monde la voit. Le slider de l'enseigne ET sa publicité sont au
-- superadministrateur, comme le reste des réglages de BIZZOO ; le
-- slider d'une boutique est à son administrateur. Le modérateur, lui,
-- n'y touche pas. C'est cette règle qui ferme vraiment la porte :
-- l'écran ne fait que cacher le bouton.
create policy "lecture publique"   on public.slides           for select using (true);
create policy "ecriture connectee" on public.slides
  for all to authenticated
  using (case when portee in ('enseigne', 'publicite')
              then public.est_super() else public.administre(boutique_id) end)
  with check (case when portee in ('enseigne', 'publicite')
                   then public.est_super() else public.administre(boutique_id) end);

-- Le slider d'une boutique : ajouter ou modifier un écran demande
-- l'accord de l'enseigne. Retirer un écran ou changer l'ordre reste
-- à l'administrateur — c'est sa vitrine, il l'allège comme il veut.
create or replace function public.slide_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.est_super() then return new; end if;
  if tg_op = 'INSERT' then
    raise exception 'Ajouter un écran au slider demande l''accord de l''enseigne : enregistrez, la demande lui sera envoyée';
  end if;
  -- L'ordre et l'extinction restent libres ; l'image, la vidéo, la
  -- légende et le produit visé, non.
  if new.image      is distinct from old.image
  or new.video      is distinct from old.video
  or new.titre      is distinct from old.titre
  or new.produit_id is distinct from old.produit_id then
    raise exception 'Modifier un écran du slider demande l''accord de l''enseigne : enregistrez, la demande lui sera envoyée';
  end if;
  return new;
end $$;

drop trigger if exists slides_verrous on public.slides;
create trigger slides_verrous
  before insert or update on public.slides
  for each row execute function public.slide_verrous();

drop policy if exists "lecture publique"  on public.boutique;
drop policy if exists "ecriture connectee" on public.boutique;
create policy "lecture publique"   on public.boutique        for select using (true);
-- Les coordonnées de l'enseigne ne regardent que le superadministrateur.
create policy "ecriture connectee" on public.boutique
  for all to authenticated using (public.est_super()) with check (public.est_super());

-- LA LISTE EST CELLE DE BIZZOO : l'enseigne seule l'écrit. Une boutique
-- qui pouvait encore créer un rayon créait un classement rien qu'à
-- elle, et la liste commune cessait d'en être une. Elle reste lue par
-- tout le monde, sans compte : c'est le menu de la vitrine.
drop policy if exists "lecture publique"  on public.categories;
drop policy if exists "ecriture connectee" on public.categories;
drop policy if exists "ecriture enseigne" on public.categories;
create policy "lecture publique"  on public.categories for select using (true);
create policy "ecriture enseigne" on public.categories
  for all to authenticated
  using (public.est_super()) with check (public.est_super());

-- Une sous-catégorie suit le sort de son rayon, donc la même règle.
drop policy if exists "lecture publique"  on public.sous_categories;
drop policy if exists "ecriture connectee" on public.sous_categories;
drop policy if exists "ecriture enseigne" on public.sous_categories;
create policy "lecture publique"  on public.sous_categories for select using (true);
create policy "ecriture enseigne" on public.sous_categories
  for all to authenticated
  using (public.est_super()) with check (public.est_super());

-- Les produits se découpent en trois droits : ajouter, modifier, supprimer.
-- Toute l'équipe ajoute — dans sa boutique ; retoucher ou retirer un
-- produit déjà publié demande en plus le droit correspondant.
drop policy if exists "lecture publique"  on public.produits;
drop policy if exists "ecriture connectee" on public.produits;
drop policy if exists "produits ajout" on public.produits;
drop policy if exists "produits modification" on public.produits;
drop policy if exists "produits suppression" on public.produits;
create policy "lecture publique" on public.produits for select using (true);
-- CRÉER UN PRODUIT DEMANDE L'HABILITATION (3.59.0), comme le modifier.
-- Avant, il suffisait d'être de la boutique — ou d'un compte de BIZZOO,
-- même réduit aux commandes.
create policy "produits ajout" on public.produits
  for insert to authenticated
  with check (public.peut_modifier_produits() and public.peut_agir_sur(boutique_id));
create policy "produits modification" on public.produits
  for update to authenticated
  using (public.peut_modifier_produits() and public.peut_agir_sur(boutique_id))
  with check (public.peut_modifier_produits() and public.peut_agir_sur(boutique_id));
create policy "produits suppression" on public.produits
  for delete to authenticated
  using (public.peut_modifier_produits() and public.peut_agir_sur(boutique_id));

-- MASQUER OU RÉAFFICHER UN PRODUIT (3.59.0) : l'administrateur ou le
-- modérateur de SA boutique — même sans l'habilitation à retoucher les
-- produits : masquer n'efface rien et se défait —, BIZZOO sur toutes.
-- Un livreur, non.
create or replace function public.masquer_produit(cible text, cacher boolean)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  sa_boutique text;
  qui         text;
begin
  select p.boutique_id into sa_boutique from public.produits p where p.id = cible;
  if not found then
    raise exception 'Ce produit n''existe plus.';
  end if;
  if not public.peut_agir_sur(sa_boutique) then
    raise exception 'Ce produit n''est pas de votre boutique.';
  end if;
  select coalesce(nullif(p.nom, ''), nullif(p.email, ''), 'l''équipe') into qui
    from public.profils p where p.id = auth.uid();
  update public.produits
     set masque = coalesce(cacher, true),
         masque_par = case when coalesce(cacher, true) then coalesce(qui, '') else '' end,
         masque_le = case when coalesce(cacher, true) then now() else null end
   where id = cible;
  return coalesce(cacher, true);
end $$;
revoke all on function public.masquer_produit(text, boolean) from public, anon;
grant execute on function public.masquer_produit(text, boolean) to authenticated;

-- Les prix d'achat : jamais de lecture publique. La clé publiable de
-- l'application client n'a aucun droit dessus, pas même de lecture ;
-- seule l'équipe connectée y accède.
alter table public.produits_prive enable row level security;
revoke all on public.produits_prive from anon;
grant select, insert, update, delete on public.produits_prive to authenticated;

drop policy if exists "prix achat lecture"      on public.produits_prive;
drop policy if exists "prix achat ajout"        on public.produits_prive;
drop policy if exists "prix achat modification" on public.produits_prive;
drop policy if exists "prix achat suppression"  on public.produits_prive;
-- Un modérateur ne voit même pas les marges des autres boutiques.
create policy "prix achat lecture" on public.produits_prive
  for select to authenticated
  using (public.peut_agir_sur(
    (select p.boutique_id from public.produits p where p.id = produit_id)));
create policy "prix achat ajout" on public.produits_prive
  for insert to authenticated
  with check (public.peut_modifier_produits() and public.peut_agir_sur(
    (select p.boutique_id from public.produits p where p.id = produit_id)));
create policy "prix achat modification" on public.produits_prive
  for update to authenticated
  using (public.peut_modifier_produits() and public.peut_agir_sur(
    (select p.boutique_id from public.produits p where p.id = produit_id)))
  with check (public.peut_modifier_produits() and public.peut_agir_sur(
    (select p.boutique_id from public.produits p where p.id = produit_id)));
create policy "prix achat suppression" on public.produits_prive
  for delete to authenticated
  using (public.peut_modifier_produits() and public.peut_agir_sur(
    (select p.boutique_id from public.produits p where p.id = produit_id)));

-- Le slider reste la décision de qui administre la boutique : le
-- modérateur peut tout modifier d'un produit, sauf sa mise en avant.
create or replace function public.controle_mise_en_avant() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.administre(new.boutique_id) then return new; end if;
  if tg_op = 'INSERT' then
    if new.en_avant or coalesce(new.ordre_avant, 0) <> 0 then
      raise exception 'Seul l''administrateur de la boutique choisit les produits mis en avant';
    end if;
  elsif new.en_avant is distinct from old.en_avant
     or new.ordre_avant is distinct from old.ordre_avant then
    raise exception 'Seul l''administrateur de la boutique choisit les produits mis en avant';
  end if;
  return new;
end $$;

drop trigger if exists produits_mise_en_avant on public.produits;
create trigger produits_mise_en_avant
  before insert or update on public.produits
  for each row execute function public.controle_mise_en_avant();

-- ---------- Approuver ou refuser une demande ----------
-- L'application n'écrit pas elle-même la modification approuvée :
-- elle appelle cette fonction, qui vérifie qui l'appelle et n'écrit
-- QUE les colonnes prévues. Rien de dynamique, rien qui se déduise
-- du contenu de la demande : la leçon du journal.
create or replace function public.approuver_demande(cible text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  d public.demandes%rowtype;
  a jsonb;
begin
  if not public.est_super() then
    raise exception 'Seule l''enseigne approuve une demande';
  end if;
  select * into d from public.demandes where id = cible for update;
  if not found then raise exception 'Demande introuvable'; end if;
  if d.etat <> 'en_attente' then raise exception 'Cette demande a déjà été traitée'; end if;
  a := d.apres;

  if d.type = 'reglages' then
    update public.boutiques set
      nom         = coalesce(a->>'nom', nom),
      logo        = coalesce(a->>'logo', logo),
      description = coalesce(a->>'description', description),
      adresse     = coalesce(a->>'adresse', adresse),
      latitude    = case when a ? 'latitude'
                         then nullif(a->>'latitude', '')::double precision else latitude end,
      longitude   = case when a ? 'longitude'
                         then nullif(a->>'longitude', '')::double precision else longitude end,
      tel         = coalesce(a->>'tel', tel),
      whatsapp    = coalesce(a->>'whatsapp', whatsapp),
      indicatif   = coalesce(a->>'indicatif', indicatif),
      telephones  = coalesce(a->'telephones', telephones),
      adresses    = coalesce(a->'adresses', adresses),
      maj_le      = now()
    where id = d.boutique_id;

  elsif d.type = 'slider' then
    insert into public.slides
      (id, boutique_id, portee, image, video, titre, produit_id, ordre, actif)
    values (
      coalesce(d.cible_id, a->>'id'),
      d.boutique_id,
      'boutique',
      coalesce(a->>'image', ''),
      coalesce(a->>'video', ''),
      coalesce(a->>'titre', ''),
      nullif(a->>'produit_id', ''),
      coalesce((a->>'ordre')::int, 0),
      coalesce((a->>'actif')::boolean, true))
    on conflict (id) do update set
      image      = excluded.image,
      video      = excluded.video,
      titre      = excluded.titre,
      produit_id = excluded.produit_id,
      actif      = excluded.actif;
  else
    raise exception 'Type de demande inconnu : %', d.type;
  end if;

  update public.demandes
     set etat = 'approuvee',
         decide_par = coalesce(
           (select p.email from public.profils p where p.id = auth.uid()), ''),
         decide_le = now()
   where id = cible;
end $$;

create or replace function public.refuser_demande(cible text, raison text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.est_super() then
    raise exception 'Seule l''enseigne refuse une demande';
  end if;
  update public.demandes
     set etat = 'refusee',
         motif = coalesce(raison, ''),
         decide_par = coalesce(
           (select p.email from public.profils p where p.id = auth.uid()), ''),
         decide_le = now()
   where id = cible and etat = 'en_attente';
  if not found then raise exception 'Demande introuvable ou déjà traitée'; end if;
end $$;

-- « anon » nommé, pour la même raison que plus haut : sans cela, un
-- visiteur pouvait tenter l'appel.
revoke all on function public.approuver_demande(text) from public, anon;
revoke all on function public.refuser_demande(text, text) from public, anon;
grant execute on function public.approuver_demande(text) to authenticated;
grant execute on function public.refuser_demande(text, text) to authenticated;

-- ---------- Panier, commandes et paiement KkiaPay ----------
-- Le client remplit un panier, valide, paie par Mobile Money. La
-- commande se répartit ensuite entre les boutiques concernées :
-- chacune ne voit que SES lignes.
--
-- Trois règles tiennent tout le reste :
--   1. le client n'écrit pas les prix — la base relit le catalogue ;
--   2. le client ne déclare pas qu'il a payé — le message de succès
--      arrive sur SON téléphone, donc on ne le croit pas ; seul
--      KkiaPay, par la fonction Edge « kkiapay-webhook », fait passer
--      une commande à « payée » ;
--   3. le montant qui compte est celui annoncé par KkiaPay, jamais
--      celui demandé par l'application.
--
-- Aucune clé privée ici ni dans l'APK : la clé publique est faite
-- pour être publique, et le secret du webhook ne vit que dans les
-- secrets Supabase.

-- ---------- Les réglages du paiement ----------
-- La clé publique vit EN BASE, pas dans le code : on passe du
-- bac à sable à la production sans reconstruire ni republier
-- les deux applications. Chez KkiaPay, test et production sont
-- deux mondes séparés — clés différentes, webhooks différents —
-- et les trois interrupteurs se poussent ENSEMBLE.
create table if not exists public.paiement (
  id           int primary key default 1 check (id = 1),
  actif        boolean not null default false,  -- tant que faux : commande sans paiement en ligne
  -- Quel agrégateur encaisse. Le SUPERADMINISTRATEUR en change dans ses
  -- réglages, et cela vaut pour toutes les boutiques de BIZZOO — la
  -- politique d'écriture plus bas ne laisse personne d'autre y toucher.
  fournisseur  text not null default 'feexpay',
  -- KkiaPay seulement, et c'est la clé PUBLIQUE : elle est faite pour
  -- partir dans l'application. FeexPay, lui, exige un jeton porteur —
  -- un secret, qui reste donc dans les secrets Supabase et ne descend
  -- JAMAIS dans cette table, que « anon » a le droit de lire.
  cle_publique text not null default '',
  bac_a_sable  boolean not null default true,   -- vrai = numéros de test seulement
  maj_le       timestamptz not null default now()
);
-- Sur une base déjà en service, le corps ci-dessus n'est jamais relu.
alter table public.paiement
  add column if not exists fournisseur text not null default 'feexpay';
alter table public.paiement alter column fournisseur set default 'feexpay';
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'paiement_fournisseur_connu') then
    alter table public.paiement
      add constraint paiement_fournisseur_connu
      check (fournisseur in ('kkiapay', 'feexpay'));
  end if;
end $$;

-- L'ACOMPTE À LA COMMANDE, en pour cent du total. Le client le règle en
-- ligne pour que sa commande parte ; le reste se paie à la livraison.
-- C'est ce qui écarte les commandes fictives : commander engage déjà de
-- l'argent. Le superadministrateur seul le règle, par la même politique
-- d'écriture que l'agrégateur. 100 revient à tout faire payer en ligne,
-- comme avant.
alter table public.paiement
  add column if not exists taux_acompte int not null default 10;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'paiement_taux_acompte_borne') then
    alter table public.paiement
      add constraint paiement_taux_acompte_borne
      check (taux_acompte between 1 and 100);
  end if;
end $$;
insert into public.paiement (id) values (1) on conflict (id) do nothing;

-- LES FRAIS DE LIVRAISON, en FCFA, par commande. Fixes pour l'instant
-- (1 000) ; ils dépendront plus tard de la distance. Ils s'ajoutent au
-- montant des articles, et AUCUN code promo ne les touche. Le
-- superadministrateur seul les règle, comme l'acompte.
alter table public.paiement
  add column if not exists frais_livraison int not null default 1000;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'paiement_frais_livraison_borne') then
    alter table public.paiement
      add constraint paiement_frais_livraison_borne
      check (frais_livraison between 0 and 100000);
  end if;
end $$;

-- LE CODE MOMOPAY DE BIZZOO (3.59.0). Le reste d'une commande se paie à
-- la livraison par MoMoPay, sur le compte marchand de BIZZOO : le livreur
-- montre ce code et le montant, le client paie depuis son téléphone. Un
-- code marchand est fait pour être montré : il peut être lu par tous.
-- ---------- La livraison au kilomètre (3.64.0) ----------
-- UN SEUL POINT DE DÉPART, celui de BIZZOO, réglé par le
-- superadministrateur. Les frais d'une commande se comptent de ce point
-- jusqu'au client :
--   jusqu'à « livraison_rayon_km »  le forfait du véhicule ;
--   au-delà                          + le prix du kilomètre, par kilomètre
--                                      ENTAMÉ (10,1 km : un de plus).
-- La distance est à vol d'oiseau, multipliée par « livraison_coef »
-- (1,3) pour approcher le trajet par la route — gratuit et immédiat, sans
-- service de cartes payant. TANT QUE LE POINT N'EST PAS RÉGLÉ, RIEN NE
-- CHANGE : chaque boutique garde ses frais, comme avant. Régler le point,
-- c'est mettre la livraison au kilomètre en service.
--
-- Le livreur qui porte la commande en touche « taux_livreur » % (80) ;
-- le reste revient à BIZZOO.
alter table public.paiement add column if not exists livraison_latitude double precision;
alter table public.paiement add column if not exists livraison_longitude double precision;
alter table public.paiement add column if not exists livraison_adresse text not null default '';
alter table public.paiement add column if not exists livraison_rayon_km int not null default 10;
alter table public.paiement add column if not exists livraison_coef numeric(4,2) not null default 1.3;
alter table public.paiement add column if not exists moto_forfait int not null default 1000;
alter table public.paiement add column if not exists moto_prix_km int not null default 100;
alter table public.paiement add column if not exists tricycle_forfait int not null default 4000;
alter table public.paiement add column if not exists tricycle_prix_km int not null default 500;
alter table public.paiement add column if not exists taux_livreur int not null default 80;
alter table public.paiement drop constraint if exists paiement_livraison_bornes;
alter table public.paiement add constraint paiement_livraison_bornes check (
  (livraison_latitude is null) = (livraison_longitude is null)
  and (livraison_latitude is null or livraison_latitude between -90 and 90)
  and (livraison_longitude is null or livraison_longitude between -180 and 180)
  and livraison_rayon_km between 0 and 500
  and livraison_coef between 1 and 3
  and moto_forfait between 0 and 1000000 and moto_prix_km between 0 and 100000
  and tricycle_forfait between 0 and 1000000 and tricycle_prix_km between 0 and 100000
  and taux_livreur between 0 and 100
  and length(livraison_adresse) <= 200);

-- La livraison au kilomètre est-elle en service ? Oui dès que le point
-- BIZZOO est réglé.
create or replace function public.livraison_active() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.livraison_latitude is not null and p.livraison_longitude is not null
                     from public.paiement p where p.id = 1), false);
$$;
revoke all on function public.livraison_active() from public;
grant execute on function public.livraison_active() to anon, authenticated;

-- LE DEVIS D'UNE LIVRAISON : la distance, les kilomètres facturés, les
-- frais. Null tant que la livraison au kilomètre n'est pas en service.
-- Ouverte à tous : l'écran de commande en montre l'aperçu, et elle ne
-- dit rien que les réglages publics ne disent déjà. « creer_commande »
-- l'appelle pour figer les frais : une seule règle, un seul endroit.
create or replace function public.devis_livraison(
  latitude double precision, longitude double precision, vehicule text default 'moto')
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r     public.paiement%rowtype;
  v     text := case when vehicule = 'tricycle' then 'tricycle' else 'moto' end;
  dlat  double precision;
  dlng  double precision;
  a     double precision;
  dist  numeric;
  km    int;
  forf  int;
  prix  int;
begin
  select * into r from public.paiement where id = 1;
  if not found or r.livraison_latitude is null or r.livraison_longitude is null then
    return null;
  end if;
  if latitude is null or longitude is null
     or latitude not between -90 and 90 or longitude not between -180 and 180
     or (latitude = 0 and longitude = 0) then
    raise exception 'Position de livraison invalide : touchez « Utiliser ma position ».'
      using errcode = 'P0001';
  end if;
  -- À vol d'oiseau (formule de haversine, rayon terrestre de 6 371 km),
  -- multipliée par le coefficient de la route ; au mètre près.
  dlat := radians(latitude - r.livraison_latitude);
  dlng := radians(longitude - r.livraison_longitude);
  a := sin(dlat / 2) ^ 2
       + cos(radians(r.livraison_latitude)) * cos(radians(latitude)) * sin(dlng / 2) ^ 2;
  dist := round((2 * 6371 * asin(least(1, sqrt(a))) * r.livraison_coef)::numeric, 3);
  -- Le kilomètre ENTAMÉ compte : 10,001 km facturent un kilomètre de plus.
  km := case when dist > r.livraison_rayon_km then ceil(dist - r.livraison_rayon_km)::int else 0 end;
  forf := case when v = 'tricycle' then r.tricycle_forfait else r.moto_forfait end;
  prix := case when v = 'tricycle' then r.tricycle_prix_km else r.moto_prix_km end;
  return jsonb_build_object(
    'vehicule', v,
    'distance_km', round(dist, 1),
    'rayon_km', r.livraison_rayon_km,
    'km_factures', km,
    'forfait', forf,
    'prix_km', prix,
    'frais', forf + km * prix,
    'point', jsonb_build_object('latitude', r.livraison_latitude, 'longitude', r.livraison_longitude),
    'destination', jsonb_build_object('latitude', round(latitude::numeric, 6),
                                      'longitude', round(longitude::numeric, 6)));
end $$;
revoke all on function public.devis_livraison(double precision, double precision, text) from public;
grant execute on function public.devis_livraison(double precision, double precision, text) to anon, authenticated;

alter table public.paiement add column if not exists momopay_code text not null default '';
alter table public.paiement add column if not exists momopay_nom text not null default '';
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'paiement_momopay_borne') then
    alter table public.paiement
      add constraint paiement_momopay_borne
      check (length(momopay_code) <= 30 and length(momopay_nom) <= 60);
  end if;
end $$;

alter table public.paiement enable row level security;
drop policy if exists "paiement lecture"  on public.paiement;
drop policy if exists "paiement ecriture" on public.paiement;

-- La clé publique est faite pour être lue : l'application client
-- en a besoin pour ouvrir le paiement.
create policy "paiement lecture" on public.paiement
  for select to anon, authenticated using (true);
-- La changer engage l'argent de toute l'enseigne : vous seul.
create policy "paiement ecriture" on public.paiement
  for update to authenticated
  using (public.est_super()) with check (public.est_super());

-- ---------- Les commandes ----------
create table if not exists public.commandes (
  id           text primary key,
  numero       text not null default '',       -- « BZ-000123 », lisible au téléphone
  client_nom   text not null default '',
  client_tel   text not null default '',
  client_indicatif text not null default '229',
  client_adresse   text not null default '',   -- où livrer, ou « à retirer »
  note         text not null default '',       -- un mot du client
  total        int  not null default 0,        -- calculé par la base, jamais reçu
  devise       text not null default 'FCFA',
  etat         text not null default 'a_payer'
               check (etat in ('a_payer', 'payee', 'echouee', 'annulee')),
  transaction_id text not null default '',     -- l'identifiant du versement, chez l'agrégateur
  -- La référence que l'agrégateur donne à CETTE tentative de paiement.
  -- FeexPay ne signe aucune notification : c'est avec elle que notre
  -- serveur ira lui demander « ce versement a-t-il abouti ? ». Elle est
  -- donc la clé de tout l'encaissement FeexPay.
  fournisseur_ref text not null default '',
  -- Quand la dernière demande de paiement est partie. Sert de frein :
  -- sans lui, on pourrait faire sonner un téléphone en boucle.
  tentative_le timestamptz,
  -- Vide quand c'est l'agrégateur qui a confirmé (le cas normal) ; sinon
  -- l'adresse du superadministrateur qui s'est porté garant à la main.
  confirme_par text not null default '',
  remarque     text not null default '',       -- « reçu 5 000 sur 12 000 attendus »
  annonce_le   timestamptz,                    -- quand le téléphone a dit « j'ai payé »
  paye_le      timestamptz,
  cree_le      timestamptz not null default now()
);
-- Ce que le TÉLÉPHONE affirme, à ne jamais mélanger avec ce que KkiaPay
-- PROUVE. La preuve porte un index unique ; si une affirmation venue du
-- dehors pouvait s'y loger, il suffirait de réclamer la transaction d'un
-- autre pour bloquer son encaissement.
alter table public.commandes
  add column if not exists transaction_annoncee text not null default '';

-- Sur une base déjà en service, le corps du « create table » n'est pas
-- relu : la colonne doit être répétée ici pour y arriver.
alter table public.commandes
  add column if not exists fournisseur_ref text not null default '';
alter table public.commandes
  add column if not exists tentative_le timestamptz;

-- À qui appartient cette commande. « on delete set null » et non
-- « cascade » : un client qui ferme son compte n'efface pas les ventes de
-- la boutique. Les comptes d'hier ne se réécrivent pas.
alter table public.commandes add column if not exists client_id uuid;
alter table public.commandes add column if not exists compte_supprime boolean not null default false;

-- La clé étrangère à part : les fichiers de paiement posent la colonne
-- sans connaître la table des clients, et une contrainte ne s'ajoute pas
-- deux fois.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'commandes_client_fk') then
    alter table public.commandes
      add constraint commandes_client_fk foreign key (client_id)
      references public.clients(id) on delete set null;
  end if;
end $$;
create index if not exists commandes_client on public.commandes(client_id, cree_le desc);

create index if not exists commandes_etat on public.commandes(etat, cree_le desc);
-- Une transaction ne vaut que pour une commande : c'est ce qui rend le
-- paiement rejouable sans danger (KkiaPay réessaie 5 fois tant qu'il n'a
-- pas reçu un 200 ; côté FeexPay, c'est nous qui redemandons le statut).
create unique index if not exists commandes_transaction
  on public.commandes(transaction_id) where transaction_id <> '';
-- Et une référence d'agrégateur ne désigne qu'une commande : sans cela,
-- deux commandes pourraient se disputer le même versement.
create unique index if not exists commandes_fournisseur_ref
  on public.commandes(fournisseur_ref) where fournisseur_ref <> '';

-- Une ligne par produit commandé. Le nom, la référence et le prix
-- y sont FIGÉS : c'est ce qui a été vendu ce jour-là.
create table if not exists public.commande_lignes (
  id          text primary key,
  commande_id text not null references public.commandes(id) on delete cascade,
  boutique_id text references public.boutiques(id) on delete set null,
  produit_id  text references public.produits(id) on delete set null,
  nom         text not null default '',
  reference   text not null default '',
  prix        int  not null default 0,
  quantite    int  not null default 1 check (quantite > 0 and quantite <= 99),
  -- Le suivi côté boutique : elle avance sa propre ligne.
  etat        text not null default 'nouvelle'
              check (etat in ('nouvelle', 'vue', 'preparee',
                              'en_livraison', 'remise', 'annulee')),
  cree_le     timestamptz not null default now()
);

-- « en_livraison » est arrivé après coup : sur une base déjà en service,
-- le corps du « create table » n'est jamais relu, et la contrainte y
-- refuserait encore ce nouvel état. On la repose donc explicitement.
alter table public.commande_lignes drop constraint if exists commande_lignes_etat_check;
alter table public.commande_lignes add constraint commande_lignes_etat_check
  check (etat in ('nouvelle', 'vue', 'preparee', 'en_livraison', 'remise', 'annulee'));

-- QUAND LE CLIENT A DIT « JE L'AI BIEN REÇU ».
--
-- Une colonne à part, et pas un état de plus dans la chaîne ci-dessus :
-- ce ne sont pas les mêmes faits, ni les mêmes témoins. « remise » est
-- ce que la BOUTIQUE déclare ; « confirme_le » est ce que le CLIENT
-- constate. Les mêler dans une seule colonne reviendrait à laisser l'un
-- écrire la parole de l'autre — et la déclaration de la boutique n'a
-- plus de valeur si elle peut aussi signer l'accusé de réception.
alter table public.commande_lignes add column if not exists confirme_le timestamptz;

-- ---------- À qui cette livraison est confiée ----------
-- Sur la LIGNE, pas sur la commande : une commande peut traverser deux
-- boutiques, qui livrent chacune la sienne, chacune par son livreur.
alter table public.commande_lignes add column if not exists livreur_id uuid;
-- LE LIVREUR A ACCEPTÉ LA COURSE (3.59.0) : il a touché « Reçu ». C'est ce
-- moment-là qui révèle au client son nom et son numéro. Remis à zéro si
-- la course change de livreur.
alter table public.commande_lignes add column if not exists recu_le timestamptz;
create index if not exists lignes_livreur on public.commande_lignes(livreur_id)
  where livreur_id is not null;

-- Le code du produit, figé comme son nom et son prix : c'est ce qui a
-- été vendu.
alter table public.commande_lignes add column if not exists code text not null default '';
-- Ce que la boutique touche, et la marge de l'enseigne le jour de la
-- vente : figés eux aussi. Changer la marge demain ne réécrit pas les
-- comptes d'hier.
alter table public.commande_lignes
  add column if not exists prix_bizzoo int not null default 0;
alter table public.commande_lignes
  add column if not exists taux_marge numeric;

-- Sous quel régime de prix cette commande est partie. Figé comme le
-- reste : valider un revendeur demain ne réécrit pas les commandes
-- d'hier, et lui retirer son statut non plus.
alter table public.commandes add column if not exists revendeur boolean not null default false;

-- Le code promo utilisé, et ce qu'il a coûté. Sur la COMMANDE, jamais
-- sur les lignes : une remise sort de la marge de l'enseigne, et la
-- boutique touche son prix BIZZOO en entier. Toucher aux lignes
-- reviendrait à faire payer à la boutique une promotion qu'elle n'a pas
-- décidée.
alter table public.commandes add column if not exists code_promo text not null default '';
alter table public.commandes add column if not exists remise bigint not null default 0;

-- L'ACOMPTE, figé à la création comme les prix : changer le taux demain
-- ne réécrit pas les commandes d'hier.
--   taux_acompte : le taux du jour, en pour cent ;
--   acompte      : ce qui se paie en ligne pour que la commande parte ;
--   verse        : ce que l'agrégateur a réellement encaissé.
-- Le reste se paie à la livraison, à chaque boutique sa part
-- (« restes_par_boutique », plus bas). Les trois sont vides sur les
-- commandes d'avant : elles se payaient en entier.
alter table public.commandes add column if not exists taux_acompte int;
alter table public.commandes add column if not exists acompte int;
alter table public.commandes add column if not exists verse int;
-- Les frais de livraison de CETTE commande, figés à sa création. Ils
-- font partie du total (ce que le client paie) mais pas des articles :
-- ni la remise d'un code, ni la commission d'un particulier ne les
-- touchent. 0 sur les commandes d'avant.
alter table public.commandes add column if not exists frais_livraison bigint not null default 0;
-- CE QUE CHAQUE BOUTIQUE DEMANDE (3.59.0), figé à la commande :
--   { "bou_x": { "frais": 1000, "taux": 30, "du": 51000, "acompte": 15300 }, … }
-- « du » : sa part, remise déduite au prorata, plus ses frais ; « taux » :
-- 100 si elle se paie en entier à la commande. La somme des « acompte »
-- est l'acompte de la commande. Null : une commande d'avant, réglée
-- selon l'ancienne règle, celle de l'enseigne.
alter table public.commandes add column if not exists parts jsonb;
-- (3.64.0) LA LIVRAISON AU KILOMÈTRE, figée à la commande :
--   { "vehicule": "moto", "distance_km": 13.4, "rayon_km": 10, "km_factures": 4,
--     "forfait": 1000, "prix_km": 100, "frais": 1400,
--     "point": {…}, "destination": { "latitude": …, "longitude": … } }
-- Null : une commande d'avant, aux frais de chaque boutique. Non nulle,
-- les frais sont ceux de la COMMANDE entière, payés en ligne avec
-- l'acompte, et reviennent au livreur qui la porte (« gains_livreurs »).
alter table public.commandes add column if not exists livraison jsonb;

create index if not exists lignes_commande on public.commande_lignes(commande_id);
create index if not exists lignes_boutique on public.commande_lignes(boutique_id, etat);

-- Un numéro lisible, que le client peut dicter au téléphone.
create sequence if not exists public.commandes_numero;

-- ---------- Ce que personne ne peut écrire à la main ----------
-- Une commande naît « à payer », sans transaction et sans date.
-- Même si une règle d'écriture était ajoutée un jour par erreur,
-- ceci resterait vrai.
--
-- Le régime de prix se décide ici, sur le compte connecté, et il ne
-- bouge plus. Les lignes le liront ensuite sur leur commande : ajouter
-- une ligne demain à une commande partie au prix revendeur ne la fera
-- pas basculer au prix public.
create or replace function public.commande_a_l_ecriture() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.etat := 'a_payer';
  new.transaction_id := '';
  new.transaction_annoncee := '';
  new.confirme_par := '';
  new.remarque := '';
  new.annonce_le := null;
  new.paye_le := null;
  -- L'acompte se pose APRÈS les lignes, par « creer_commande » : il se
  -- calcule sur un total que la base n'a pas encore. Rien ne l'apporte
  -- de dehors, pas plus que l'argent versé.
  new.taux_acompte := null;
  new.acompte := null;
  new.parts := null;
  new.verse := null;
  -- Les frais de livraison aussi : « creer_commande » les pose, d'après
  -- les réglages de l'enseigne. Le téléphone n'en décide pas.
  new.frais_livraison := 0;
  new.livraison := null;
  new.revendeur := public.est_revendeur();
  if coalesce(new.numero, '') = '' then
    new.numero := 'BZ-' || lpad(nextval('public.commandes_numero')::text, 6, '0');
  end if;
  return new;
end $$;

drop trigger if exists commandes_a_l_ecriture on public.commandes;
create trigger commandes_a_l_ecriture
  before insert on public.commandes
  for each row execute function public.commande_a_l_ecriture();

-- Le nom, la référence, la boutique et le PRIX viennent du catalogue,
-- jamais de ce que le téléphone envoie.
create or replace function public.ligne_a_l_ecriture() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  p          public.produits%rowtype;
  achat      int;
  taux       numeric;
  taux_rev   numeric;   -- le taux propre à CE produit, s'il en a un
  mode_rev   text;
  revendeur  boolean;
begin
  select * into p from public.produits where id = new.produit_id;
  if not found then
    raise exception 'Produit introuvable : %', coalesce(new.produit_id, '(aucun)');
  end if;
  select greatest(0, coalesce(prix_grossiste, 0))::int, taux_revendeur
    into achat, taux_rev
    from public.produits_prive where produit_id = p.id;
  -- Le taux du produit l'emporte ; à null, celui de la boutique. Le mode
  -- est celui de la boutique, toujours.
  select coalesce(taux_marge, 0),
         coalesce(taux_rev, taux_revendeur, 0),
         coalesce(revendeur_mode, 'bizzoo')
    into taux, taux_rev, mode_rev
    from public.boutiques where id = p.boutique_id;
  -- Le régime de prix est celui de la commande, posé par la base à son
  -- ouverture. Le panier n'a pas voix au chapitre.
  select coalesce(c.revendeur, false) into revendeur
    from public.commandes c where c.id = new.commande_id;

  new.boutique_id := p.boutique_id;
  new.nom         := p.nom;
  new.code        := coalesce(p.code, '');
  new.reference   := coalesce(p.reference, '');
  new.prix        := case when coalesce(revendeur, false)
                          then public.prix_revendeur(coalesce(p.prix, 0)::int,
                                                     coalesce(achat, 0),
                                                     coalesce(taux_rev, 0),
                                                     coalesce(mode_rev, 'bizzoo'))
                          else coalesce(p.prix, 0)::int end;
  -- Ce que la boutique touche, et la marge du jour : figés avec le
  -- reste. Les comptes d'hier ne se réécrivent pas.
  new.prix_bizzoo := coalesce(achat, 0);
  new.taux_marge  := taux;
  new.etat        := 'nouvelle';
  return new;
end $$;

drop trigger if exists lignes_a_l_ecriture on public.commande_lignes;
create trigger lignes_a_l_ecriture
  before insert on public.commande_lignes
  for each row execute function public.ligne_a_l_ecriture();

-- Le total suit ses lignes, à l'ajout comme au retrait.
-- ---------- Ce que vaut une commande ----------
-- Le total, c'est la somme de ses lignes MOINS la remise d'un code
-- promo. La règle vit ici, en un seul endroit : le déclencheur des
-- lignes l'appelle, et l'application d'un code aussi. Deux endroits
-- finiraient par diverger, et un client paierait un montant que la
-- base n'aurait pas calculé.
create or replace function public.commande_total(cible text) returns void
language plpgsql security definer set search_path = public as $$
declare avant text := coalesce(current_setting('bizzoo.interne', true), '');
begin
  -- C'est la base qui écrit ce total, pas un client : le verrou de la
  -- section suivante doit le laisser passer. Le drapeau est ensuite
  -- rendu tel qu'il était, pour ne pas ouvrir la porte au reste de
  -- l'appel.
  perform set_config('bizzoo.interne', 'oui', true);
  update public.commandes c
     set total = greatest(0,
           coalesce((select sum(l.prix * l.quantite)
                       from public.commande_lignes l
                      where l.commande_id = cible), 0)
           - greatest(0, coalesce(c.remise, 0)))
           -- Les frais de livraison s'ajoutent APRÈS la remise : un code
           -- promo ne les touche pas.
           + greatest(0, coalesce(c.frais_livraison, 0))
   where c.id = cible;
  perform set_config('bizzoo.interne', avant, true);
end $$;
revoke all on function public.commande_total(text) from public, anon, authenticated;

create or replace function public.commande_recalcule() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.commande_total(coalesce(new.commande_id, old.commande_id));
  return null;
end $$;

drop trigger if exists lignes_recalculent on public.commande_lignes;
create trigger lignes_recalculent
  after insert or update or delete on public.commande_lignes
  for each row execute function public.commande_recalcule();

-- Le verrou central : QUI a le droit de dire « payée ».
--
-- Personne, sauf les deux fonctions nommées plus bas, qui posent
-- le drapeau « bizzoo.paiement ». Un drapeau de transaction ne
-- s'attrape pas depuis PostgREST : il n'existe que le temps de
-- l'appel, à l'intérieur de la fonction qui l'a posé.
create or replace function public.commande_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- La base écrit pour elle-même : le total qui suit ses lignes, la
  -- monnaie posée à la création. Ces drapeaux n'existent que le temps de
  -- l'appel — ils ne s'attrapent pas depuis PostgREST.
  if coalesce(current_setting('bizzoo.interne', true), '') = 'oui' then
    return new;
  end if;
  if coalesce(current_setting('bizzoo.paiement', true), '') = 'oui' then
    return new;   -- l'agrégateur, ou l'enseigne qui se porte garante
  end if;

  if not public.est_equipe() then
    raise exception 'Seule l''équipe suit une commande';
  end if;

  -- L'équipe suit la commande, elle ne la réécrit pas.
  if new.total is distinct from old.total
  or new.client_nom is distinct from old.client_nom
  or new.client_tel is distinct from old.client_tel
  or new.client_adresse is distinct from old.client_adresse
  -- À qui appartient cette commande. La réattribuer, c'est offrir à
  -- quelqu'un l'historique, les avis et le SAV d'un autre.
  or new.client_id is distinct from old.client_id
  or new.compte_supprime is distinct from old.compte_supprime
  -- Et sous quel régime de prix elle est partie : la basculer après
  -- coup, c'est réécrire ce que la boutique a touché.
  or new.revendeur is distinct from old.revendeur
  or new.transaction_id is distinct from old.transaction_id
  or new.transaction_annoncee is distinct from old.transaction_annoncee
  -- La référence de l'agrégateur est ce avec quoi notre serveur ira lui
  -- demander si le versement a abouti. La laisser réécrire, c'est
  -- laisser désigner quel versement répond pour quelle commande.
  or new.fournisseur_ref is distinct from old.fournisseur_ref
  or new.tentative_le is distinct from old.tentative_le
  or new.confirme_par is distinct from old.confirme_par
  -- L'acompte et ce qui a été versé. Les réécrire, c'est changer ce que
  -- le livreur va réclamer à la porte du client.
  or new.taux_acompte is distinct from old.taux_acompte
  or new.acompte is distinct from old.acompte
  or new.parts is distinct from old.parts
  or new.verse is distinct from old.verse
  or new.frais_livraison is distinct from old.frais_livraison
  -- (3.64.0) La distance, le véhicule et le tarif : ce que le livreur
  -- touchera.
  or new.livraison is distinct from old.livraison
  or new.paye_le is distinct from old.paye_le then
    raise exception 'Le montant et le paiement d''une commande ne se réécrivent pas';
  end if;

  -- Et surtout : elle n'invente pas un encaissement.
  if new.etat = 'payee' and old.etat <> 'payee' then
    raise exception 'Seul l''agrégateur de paiement déclare un paiement';
  end if;
  if old.etat = 'payee' and new.etat not in ('payee', 'annulee') then
    raise exception 'Une commande payée ne peut être qu''annulée';
  end if;
  return new;
end $$;

drop trigger if exists commandes_verrous on public.commandes;
create trigger commandes_verrous
  before update on public.commandes
  for each row execute function public.commande_verrous();

-- Une ligne de commande ne change que d'état : ce qui a été vendu
-- est vendu.
create or replace function public.ligne_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- LA CONFIRMATION DU CLIENT passe par « confirmer_reception », qui
  -- pose ce drapeau. Sans lui, la colonne est aussi verrouillée que le
  -- reste : ni la boutique ni le client ne peuvent l'écrire à la main.
  if coalesce(current_setting('bizzoo.reception', true), '') <> 'oui'
     and new.confirme_le is distinct from old.confirme_le then
    raise exception 'Un accusé de réception se pose depuis le compte du client';
  end if;

  -- CONFIER UNE LIVRAISON passe par « assigner_livreur », qui pose ce
  -- drapeau après avoir vérifié que celui qui confie tient bien la
  -- boutique, et que celui à qui l'on confie est bien son livreur.
  -- Sans lui, n'importe quelle écriture sur la ligne pourrait se
  -- désigner porteuse de la marchandise.
  if coalesce(current_setting('bizzoo.livraison', true), '') <> 'oui'
     and new.livreur_id is distinct from old.livreur_id then
    raise exception 'Une livraison se confie depuis le compte de la boutique';
  end if;
  -- « Reçu » se pose par « accepter_course », par le livreur lui-même.
  if coalesce(current_setting('bizzoo.livraison', true), '') <> 'oui'
     and new.recu_le is distinct from old.recu_le then
    raise exception 'Une course s''accepte depuis le compte du livreur';
  end if;

  if new.commande_id is distinct from old.commande_id
  or new.boutique_id is distinct from old.boutique_id
  or new.produit_id  is distinct from old.produit_id
  or new.nom         is distinct from old.nom
  or new.code        is distinct from old.code
  or new.reference   is distinct from old.reference
  or new.prix        is distinct from old.prix
  or new.prix_bizzoo is distinct from old.prix_bizzoo
  or new.taux_marge  is distinct from old.taux_marge
  or new.quantite    is distinct from old.quantite then
    raise exception 'Une ligne de commande ne change que d''état : ce qui a été vendu est vendu';
  end if;
  return new;
end $$;

drop trigger if exists lignes_verrous on public.commande_lignes;
create trigger lignes_verrous
  before update on public.commande_lignes
  for each row execute function public.ligne_verrous();

-- ---------- Qui voit quoi ----------
alter table public.commandes       enable row level security;
alter table public.commande_lignes enable row level security;

drop policy if exists "commandes depot"    on public.commandes;
drop policy if exists "commandes lecture"  on public.commandes;
drop policy if exists "commandes suivi"    on public.commandes;
drop policy if exists "lignes depot"       on public.commande_lignes;
drop policy if exists "lignes lecture"     on public.commande_lignes;
drop policy if exists "lignes suivi"       on public.commande_lignes;

-- AUCUNE règle d'écriture directe, pas même pour déposer : une
-- commande n'entre que par creer_commande(), qui relit les prix.
-- Et aucune règle de lecture pour le client : il n'est pas
-- connecté, il ne peut donc pas lire les commandes des autres.
-- Ce qui le concerne lui revient par suivre_commande().

-- L'enseigne voit tout ; une boutique voit les commandes qui la
-- concernent, et seulement ses lignes à elle.
--
-- LE COMPTE D'ENSEIGNE PASSE PAR SON INTERRUPTEUR, et la condition est
-- écrite deux fois exprès : « peut_agir_sur » lui répond déjà oui
-- partout, alors sans « peut_voir_commandes() » l'interrupteur éteint
-- n'aurait rien fermé. Un interrupteur qui ne ferme qu'à l'écran n'est
-- pas un droit, c'est une décoration.
create policy "commandes lecture" on public.commandes
  for select to authenticated using (
    public.est_super()
    or public.droit_enseigne('commandes')
    or (public.est_equipe() and not public.est_compte_enseigne() and exists (
          select 1 from public.commande_lignes l
           where l.commande_id = commandes.id
             and l.boutique_id = public.boutique_du_compte())));
create policy "lignes lecture" on public.commande_lignes
  for select to authenticated
  using (public.peut_agir_sur(boutique_id) and public.peut_voir_commandes());

-- Avancer une ligne — vue, préparée, remise — appartient à la boutique.
create policy "lignes suivi" on public.commande_lignes
  for update to authenticated
  using  (public.peut_agir_sur(boutique_id) and public.peut_voir_commandes())
  with check (public.peut_agir_sur(boutique_id) and public.peut_voir_commandes());
-- Annuler une commande entière : l'enseigne.
drop policy if exists "commandes lecture client" on public.commandes;
create policy "commandes lecture client" on public.commandes
  for select to authenticated
  using (client_id is not null and client_id = auth.uid());

-- « security definer » : la fonction lit la table SANS repasser par RLS.
-- Sans cela, la règle des lignes interrogerait les commandes, dont la règle
-- interroge les lignes — PostgreSQL s'arrête sur « infinite recursion
-- detected in policy ». Une règle ne doit jamais dépendre d'une règle qui
-- dépend d'elle.
create or replace function public.ma_commande(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.commandes c
     where c.id = cible
       and c.client_id is not null
       and c.client_id = auth.uid());
$$;
grant execute on function public.ma_commande(text) to authenticated;

-- ---------- Ce qui reste à payer à la livraison ----------
-- Le client verse l'acompte en ligne ; le reste se paie à la porte. Une
-- commande peut traverser plusieurs boutiques, qui livrent chacune SA
-- part : chacune encaisse donc sa part du reste. La somme des parts
-- tombe juste au franc près : l'arrondi va à la plus grosse.
--
-- CE QUI EST ANNULÉ NE SE PAIE PAS. Une boutique qui ne peut pas servir
-- un article annule sa ligne : le client ne doit plus que ce qu'il
-- recevra, remise comprise au prorata, moins ce qu'il a déjà versé. Une
-- boutique dont tout est annulé n'a rien à encaisser.
--
-- Avant le paiement, c'est le reste PRÉVU : le total moins l'acompte.
-- Une commande d'avant l'acompte s'est réglée en entier : il ne reste
-- rien.
--
-- Réservée aux fonctions de la base : elle lit n'importe quelle commande
-- sans demander qui appelle. Celles qui la servent au dehors vérifient
-- d'abord à qui elles répondent.
create or replace function public.restes_par_boutique(cible text)
returns table (boutique_id text, a_encaisser bigint)
language plpgsql stable security definer set search_path = public as $$
declare lp jsonb;
begin
  select c.parts into lp from public.commandes c where c.id = cible;
  -- UNE COMMANDE D'AVANT LES CONDITIONS PAR BOUTIQUE (« parts » vide) :
  -- l'ancienne règle, celle d'un acompte unique réparti au prorata.
  if lp is null then
    return query
  with commande as (
    select c.total::numeric as total,
           greatest(0, coalesce(c.frais_livraison, 0))::numeric as frais,
           coalesce(c.verse, c.acompte, c.total)::numeric as deja
      from public.commandes c
     where c.id = cible
  ), parts as (
    select l.boutique_id as boutique,
           sum(l.prix * l.quantite)::numeric as brut,
           coalesce(sum(l.prix * l.quantite) filter (where l.etat <> 'annulee'), 0)::numeric as servi
      from public.commande_lignes l
     where l.commande_id = cible
     group by l.boutique_id
  ), reste as (
    -- Ce que vaut ce qui sera livré, remise déduite au prorata, moins ce
    -- qui est déjà versé.
    -- LES FRAIS DE LIVRAISON ne se réduisent pas au prorata : tant qu'il
    -- reste quelque chose à livrer, la course a lieu et coûte son prix.
    -- Tout annulé, il n'y a pas de course, donc pas de frais.
    select greatest(0, coalesce(round((c.total - c.frais) * sum(p.servi) / nullif(sum(p.brut), 0)), 0)
                       + case when sum(p.servi) > 0 then c.frais else 0 end
                       - c.deja) as du,
           sum(p.servi) as servi
      from commande c, parts p
     group by c.total, c.frais, c.deja
  ), repartie as (
    select p.boutique,
           coalesce(floor(r.du * p.servi / nullif(r.servi, 0)), 0) as part,
           row_number() over (order by p.servi desc, p.boutique) as rang,
           r.du
      from parts p, reste r
  )
  select x.boutique,
         (x.part + case when x.rang = 1 then x.du - sum(x.part) over () else 0 end)::bigint
    from repartie x;
    return;
  end if;
  -- (3.59.0) CHAQUE BOUTIQUE ENCAISSE SA PART, moins SON acompte : ce
  -- que valent ses articles servis, remise déduite au prorata, plus ses
  -- frais tant qu'il y a quelque chose à livrer.
  --
  -- CE QUE LE CLIENT A VERSÉ N'EST JAMAIS PERDU POUR LUI. Chaque boutique
  -- déduit d'abord son propre acompte ; ce qui a été versé en plus — un
  -- surplus, ou l'acompte d'une part annulée — diminue les autres parts
  -- au prorata, l'arrondi à la plus grosse.
  return query
    with commande as (
      select greatest(0, coalesce(c.remise, 0))::numeric as remise,
             -- (3.64.0) Au kilomètre, les frais de livraison se paient en ligne
             -- avec l'acompte, hors des parts des boutiques : ce versement-là
             -- n'allège le reste d'aucune d'elles.
             greatest(0, coalesce(c.verse, c.acompte, c.total)
                         - case when c.livraison is not null
                                then coalesce(c.frais_livraison, 0) else 0 end)::numeric as paye
        from public.commandes c where c.id = cible
    ), lignes as (
      select l.boutique_id as bou,
             sum(l.prix * l.quantite)::numeric as brut,
             coalesce(sum(l.prix * l.quantite) filter (where l.etat <> 'annulee'), 0)::numeric as servi
        from public.commande_lignes l
       where l.commande_id = cible
       group by l.boutique_id
    ), tout as (
      select sum(x.brut) as s from lignes x
    ), brutes as (
      select x.bou,
             greatest(0, round(x.servi - k.remise * x.servi / nullif(t.s, 0))
                         + case when x.servi > 0 then coalesce((lp -> x.bou ->> 'frais')::numeric, 0) else 0 end) as du
        from lignes x, tout t, commande k
    ), propres as (
      select b.bou, b.du,
             least(b.du, coalesce((lp -> b.bou ->> 'acompte')::numeric, 0)) as sien
        from brutes b
    ), credit as (
      select greatest(0, k.paye - coalesce(sum(p.sien), 0)) as reste_credit,
             coalesce(sum(p.du - p.sien), 0) as a_couvrir
        from propres p, commande k
       group by k.paye
    ), allege as (
      select p.bou, p.du - p.sien as du,
             case when c.a_couvrir > 0
                  then floor(least(c.reste_credit, c.a_couvrir) * (p.du - p.sien) / c.a_couvrir)
                  else 0 end as moins,
             least(c.reste_credit, c.a_couvrir) as credit,
             row_number() over (order by p.du - p.sien desc, p.bou) as rang
        from propres p, credit c
    )
    select a.bou,
           greatest(0, a.du - a.moins
                       - case when a.rang = 1 then a.credit - sum(a.moins) over () else 0 end)::bigint
      from allege a;
end $$;
revoke all on function public.restes_par_boutique(text) from public, anon, authenticated;

-- ---------- Le reste, lu avec la commande ----------
-- « commandes?select=*,restes » : PostgREST lit cette fonction comme une
-- colonne de plus. Elle rend { "reste": …, "boutiques": { id: part } }.
--
-- À CHACUN CE QUI LE REGARDE, comme pour les lignes. L'enseigne et le
-- client voient toutes les parts ; une boutique, la sienne seulement :
-- c'est celle que son livreur ira encaisser. Les autres ne reçoivent
-- rien. La commande est relue par son identifiant : appelée en direct,
-- la fonction recevrait une ligne fabriquée, avec les montants qu'on
-- voudrait.
create or replace function public.restes(cmd public.commandes)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  o     public.commandes%rowtype;
  tout  boolean;
  chez  text;
  parts jsonb;
begin
  select * into o from public.commandes c where c.id = cmd.id;
  if not found then return null; end if;

  tout := public.est_super()
       or public.droit_enseigne('commandes')
       or (o.client_id is not null and o.client_id = auth.uid());
  if not tout then
    chez := public.boutique_du_compte();
    if chez is null or not public.est_equipe() or public.est_compte_enseigne()
       or not exists (select 1 from public.commande_lignes l
                       where l.commande_id = o.id and l.boutique_id = chez) then
      return null;
    end if;
  end if;

  select coalesce(jsonb_object_agg(r.boutique_id, r.a_encaisser), '{}'::jsonb)
    into parts
    from public.restes_par_boutique(o.id) r
   where r.boutique_id is not null and (tout or r.boutique_id = chez);

  return jsonb_build_object(
    'reste', (select coalesce(sum(r.a_encaisser), 0)
                from public.restes_par_boutique(o.id) r
               where tout or r.boutique_id = chez),
    'boutiques', parts);
end $$;
revoke all on function public.restes(public.commandes) from public, anon;
grant execute on function public.restes(public.commandes) to authenticated;

-- ---------- « Je l'ai bien reçu » ----------
-- LE CLIENT SEUL, et c'est tout l'intérêt. La boutique déclare avoir
-- remis la marchandise ; le client constate l'avoir reçue. Si l'un
-- pouvait signer pour l'autre, la déclaration de la boutique n'aurait
-- plus de valeur — et c'est justement ce qu'un litige vient interroger.
--
-- PAR BOUTIQUE, pas par commande entière : une commande peut traverser
-- deux boutiques qui livrent séparément, et le client ne peut pas
-- confirmer ce qu'il n'a pas encore vu arriver.
--
-- ON NE CONFIRME QUE CE QUI A ÉTÉ REMIS. Confirmer avant que la
-- boutique n'ait rien déclaré ne voudrait rien dire — et donnerait au
-- client un moyen de clore une commande qui n'est pas partie.
create or replace function public.confirmer_reception(commande text, boutique text)
returns int
language plpgsql security definer set search_path = public as $$
declare
  moi     uuid := auth.uid();
  combien int;
begin
  if moi is null then
    raise exception 'Connectez-vous pour confirmer une réception';
  end if;
  if not public.ma_commande(commande) then
    raise exception 'Cette commande n''est pas la vôtre';
  end if;

  perform set_config('bizzoo.reception', 'oui', true);
  update public.commande_lignes l
     set confirme_le = now()
   where l.commande_id = commande
     and l.boutique_id = boutique
     and l.etat = 'remise'
     and l.confirme_le is null;
  get diagnostics combien = row_count;
  perform set_config('bizzoo.reception', '', true);

  if combien = 0 then
    raise exception 'Rien à confirmer ici : la boutique n''a pas encore déclaré vous avoir remis cette commande.';
  end if;
  return combien;
end $$;
revoke all on function public.confirmer_reception(text, text) from public, anon;
grant execute on function public.confirmer_reception(text, text) to authenticated;
-- =========================================================
-- Le livreur
-- =========================================================
-- Il porte la marchandise, et c'est tout. Ce qu'il doit savoir : QUOI
-- porter, À QUI, et OÙ. Ce qu'il ne doit pas savoir : ce que la
-- boutique touche, ce que l'enseigne garde, ce que le client a payé.
--
-- D'OÙ UNE FONCTION, ET PAS UNE RÈGLE RLS. Une règle décide quelles
-- LIGNES on voit ; elle les rend alors ENTIÈRES, prix BIZZOO compris.
-- Seule une fonction « security definer » peut choisir les colonnes —
-- c'est la même raison qui avait imposé des droits par colonne pour
-- l'historique du client.

-- Les livreurs de la boutique, pour que celle-ci puisse choisir.
-- ON CHOISIT UN LIVREUR PAR SON NOM, pas par son adresse e-mail.
-- « porteur@impact.bj » ne dit pas qui c'est ; « Rohim » si. Et son
-- NUMÉRO part avec : quand le client n'est pas chez lui, c'est le
-- livreur qu'on rappelle, et on ne va pas le chercher ailleurs.
--
-- DEUX SORTES DE LIVREURS, et la liste les rend toutes les deux :
-- celui de la boutique, et CELUI DE BIZZOO — rattaché à aucune
-- boutique, il porte pour toutes. La colonne « bizzoo » dit lequel est
-- lequel, pour que l'écran puisse l'écrire : confier une course à
-- quelqu'un qui n'est pas de la maison se fait les yeux ouverts.
--
-- « drop » AVANT « create or replace » : changer les colonnes rendues
-- par une fonction n'est pas un remplacement aux yeux de PostgreSQL,
-- qui refuse net. Sans cette ligne, le fichier s'arrêterait sur une
-- base déjà en service — et seulement sur celle-là.
drop function if exists public.livreurs_boutique();
create or replace function public.livreurs_boutique()
returns table (id uuid, email text, nom text, tel text,
               actif boolean, bizzoo boolean)
language plpgsql stable security definer set search_path = public as $$
declare cible text := public.boutique_du_compte();
begin
  if not public.est_equipe() then return; end if;
  return query
    select p.id, coalesce(p.email, '')::text,
           coalesce(p.nom, '')::text, coalesce(p.tel, '')::text, p.actif,
           (p.boutique_id is null)
      from public.profils p
     where p.role = 'livreur'
       -- L'enseigne les voit tous, les comptes de BIZZOO aussi ;
       -- une boutique, les siens ET ceux de BIZZOO.
       and (public.est_super() or public.est_compte_enseigne()
            or (cible is not null
                and (p.boutique_id = cible or p.boutique_id is null)))
     -- Les siens d'abord, ceux de BIZZOO ensuite : on appelle son
     -- porteur avant de déranger celui de l'enseigne.
     -- Puis par nom quand il y en a un, par adresse sinon : une liste
     -- rangée par e-mail alors qu'on lit des noms paraît en désordre.
     order by (p.boutique_id is null), nullif(p.nom, '') nulls last, p.email;
end $$;
revoke all on function public.livreurs_boutique() from public, anon;
grant execute on function public.livreurs_boutique() to authenticated;

-- ---------- Confier une livraison ----------
-- LA BOUTIQUE CONFIE, à SON livreur ou à CELUI DE BIZZOO. Confier à
-- celui de la boutique d'à côté reste refusé : ce serait lui remettre
-- le nom, le numéro et l'adresse d'un client qui n'est pas le sien.
-- Un livreur de BIZZOO, lui, porte pour toute l'enseigne — c'est
-- exactement ce qu'on a voulu en ne le rattachant à aucune boutique.
--
-- (3.59.0) LE LIVREUR DE BIZZOO PORTE TOUTE LA COMMANDE : confié par une
-- boutique, il reçoit aussi les produits des autres boutiques de la
-- commande — ceux qu'aucun autre livreur ne porte déjà. Le livreur d'une
-- boutique, lui, ne reçoit que les produits de SA boutique.
create or replace function public.assigner_livreur(
  commande text, boutique text, livreur uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  combien  int;
  autres   int := 0;
  rang     text;
  bizzoo   boolean := false;
  numero   text;
  b        record;
  son_vehicule text;
  besoin   text;
  plusieurs boolean;
  au_km    boolean;
  bloque   boolean;
begin
  if not public.peut_agir_sur(boutique) then
    raise exception 'Cette commande ne concerne pas votre boutique';
  end if;
  -- (3.64.0) UN SEUL LIVREUR PAR COMMANDE AU KILOMÈTRE. Une telle
  -- commande de plusieurs boutiques se confie à un livreur de BIZZOO, qui
  -- les livre toutes ; et une commande en tricycle, à un livreur en
  -- tricycle. Les commandes d'avant (frais par boutique) gardent leur
  -- règle : un livreur par boutique.
  select c.livraison ->> 'vehicule', c.livraison is not null into besoin, au_km
    from public.commandes c where c.id = commande;
  au_km := coalesce(au_km, false);
  select au_km and count(distinct l.boutique_id) > 1 into plusieurs
    from public.commande_lignes l where l.commande_id = commande and l.etat <> 'annulee';

  -- « livreur » nul : on retire l'attribution. Une boutique doit pouvoir
  -- reprendre une course confiée par erreur.
  if livreur is not null then
    select p.role, (p.boutique_id is null), p.vehicule, p.courses_bloquees
      into rang, bizzoo, son_vehicule, bloque from public.profils p
     where p.id = livreur and p.actif
       and (public.est_super()
            or public.est_compte_enseigne()
            -- Le livreur de BIZZOO : aucune boutique, donc toutes.
            or p.boutique_id is null
            or p.boutique_id = public.boutique_du_compte());
    if rang is distinct from 'livreur' then
      raise exception 'Ce compte n''est pas un livreur de votre boutique ni de BIZZOO';
    end if;
    -- Bloqué par l'administration de BIZZOO : plus aucune course.
    if bloque then
      raise exception 'Ce livreur est bloqué par BIZZOO : il ne reçoit plus de course. Confiez-la à un autre.'
        using errcode = 'P0001';
    end if;
    if coalesce(plusieurs, false) and not coalesce(bizzoo, false) then
      raise exception 'Cette commande traverse plusieurs boutiques : confiez-la à un livreur de BIZZOO, qui les livre toutes.'
        using errcode = 'P0001';
    end if;
    if besoin = 'tricycle' and son_vehicule is distinct from 'tricycle' then
      raise exception 'Cette commande se livre en tricycle : confiez-la à un livreur en tricycle.'
        using errcode = 'P0001';
    end if;
    -- UN LIVREUR VALIDE SON COMPTE EN ENREGISTRANT SA POSITION. Tant
    -- qu'il ne l'a pas fait, on ne lui confie rien.
    if not exists (select 1 from public.positions_livreurs pl where pl.profil_id = livreur) then
      raise exception 'Ce livreur n''a pas encore validé son compte : il doit ouvrir BIZZOO Admin et enregistrer sa position.'
        using errcode = 'P0001';
    end if;
  end if;

  perform set_config('bizzoo.livraison', 'oui', true);
  update public.commande_lignes l
     set livreur_id = livreur,
         -- Un autre livreur doit accepter à son tour (3.59.0).
         recu_le = case when l.livreur_id is distinct from livreur then null else l.recu_le end
   where l.commande_id = commande
     -- (3.64.0) Au kilomètre, retirer le livreur le retire de toute la
     -- commande : une course, c'est la commande entière.
     and (l.boutique_id = boutique or (livreur is null and au_km))
     -- (3.59.0) En secours de la demande envoyée à tous les livreurs : la
     -- boutique peut confier dès le paiement, sans attendre le colis.
     and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')
     and exists (select 1 from public.commandes c where c.id = l.commande_id and c.etat = 'payee');
  get diagnostics combien = row_count;

  -- LE LIVREUR DE BIZZOO : les produits des autres boutiques aussi. Sans
  -- prendre une part déjà confiée au livreur d'une autre boutique —
  -- (3.64.0) sauf au kilomètre : un seul livreur par commande, il les
  -- prend toutes.
  if bizzoo and combien > 0 then
    update public.commande_lignes l
       set livreur_id = livreur, recu_le = null
     where l.commande_id = commande
       and l.boutique_id <> boutique
       and (l.livreur_id is null or (au_km and l.livreur_id is distinct from livreur))
       and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison');
    get diagnostics autres = row_count;
  end if;
  perform set_config('bizzoo.livraison', '', true);

  if combien = 0 then
    raise exception 'Rien à confier ici : la commande n''est pas encore payée, ou elle est déjà livrée.';
  end if;

  -- Les autres boutiques le savent : un livreur BIZZOO passera chez elles.
  if autres > 0 then
    select c.numero into numero from public.commandes c where c.id = commande;
    for b in select distinct l.boutique_id as id from public.commande_lignes l
              where l.commande_id = commande and l.boutique_id <> boutique and l.livreur_id = livreur
    loop
      perform public.notifier(public.equipe_de(b.id), 'course_confiee',
        'Un livreur BIZZOO passe récupérer vos produits',
        'Commande ' || coalesce(numero, '') || ' — il livre toute la commande. Préparez le colis.',
        '#/commandes/' || commande, commande, b.id, true);
    end loop;
  end if;
  return combien + autres;
end $$;
revoke all on function public.assigner_livreur(text, text, uuid) from public, anon;
grant execute on function public.assigner_livreur(text, text, uuid) to authenticated;

-- ---------- Ce que le livreur a à porter ----------
-- SES courses, et rien que les siennes. Pas celles de son collègue, pas
-- celles des autres boutiques — et UN SEUL montant : ce qu'il doit
-- encaisser à la porte, la part du reste qui revient à sa boutique. Ni
-- le prix BIZZOO, ni le prix des articles, ni l'acompte. Regardez la
-- liste des colonnes rendues : elle est la réponse entière à « que voit
-- un livreur ? ».
--
-- « drop » avant « create » : la fonction a gagné une colonne, et
-- PostgreSQL ne change pas ce qu'une fonction rend sans la retirer.
-- (3.59.0) Deux colonnes de plus encore : la fiche de la course et « Reçu ».
drop function if exists public.mes_livraisons();
create or replace function public.mes_livraisons()
returns table (
  commande_id text, numero text,
  boutique_id text, nom_boutique text,
  client_nom text, client_tel text, client_indicatif text,
  client_adresse text, note text,
  etat text, articles jsonb, paye_le timestamptz,
  a_encaisser bigint,
  fiche jsonb, recu_le timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare moi uuid := auth.uid();
begin
  if moi is null or not public.est_livreur() then return; end if;
  return query
    select c.id, c.numero,
           l.boutique_id,
           coalesce((select b.nom from public.boutiques b where b.id = l.boutique_id), '')::text,
           c.client_nom, c.client_tel, c.client_indicatif,
           c.client_adresse, c.note,
           -- L'étape la MOINS avancée de ses lignes : c'est elle qui dit
           -- ce qu'il lui reste à faire.
           -- (3.59.0) Par le rang, pas l'alphabet : une course prise dès le
           -- paiement est d'abord « nouvelle » ou « vue » — en préparation.
           (array['nouvelle','vue','preparee','en_livraison','remise'])[
             min(array_position(array['nouvelle','vue','preparee','en_livraison','remise'], l.etat))]::text,
           jsonb_agg(jsonb_build_object(
             'nom', l.nom, 'code', l.code, 'quantite', l.quantite)
             order by l.nom),
           c.paye_le,
           -- Ce qu'il réclame au client : la part du reste qui revient à
           -- SA boutique. Zéro quand tout a été payé en ligne.
           coalesce((select r.a_encaisser
                       from public.restes_par_boutique(c.id) r
                      where r.boutique_id is not distinct from l.boutique_id), 0)::bigint,
           -- Où récupérer, où livrer, les frais, le déjà-payé (3.59.0).
           public.fiche_course(c.id, l.boutique_id),
           min(l.recu_le)
      from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
     where l.livreur_id = moi
       and c.etat = 'payee'
       and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison', 'remise')
       -- Une course remise depuis plus de deux jours n'a plus à
       -- encombrer sa liste.
       and (l.etat <> 'remise' or c.paye_le > now() - interval '2 days')
     group by c.id, c.numero, l.boutique_id, c.client_nom, c.client_tel,
              c.client_indicatif, c.client_adresse, c.note, c.paye_le
     order by c.paye_le;
end $$;
revoke all on function public.mes_livraisons() from public, anon;
grant execute on function public.mes_livraisons() to authenticated;

-- ---------- Qui me livre ----------
-- LE CLIENT VOIT LE NOM ET LE NUMÉRO DU LIVREUR à qui chaque boutique a
-- confié sa part, pour l'appeler ou lui écrire sur WhatsApp. Rien de
-- plus : ni son e-mail, ni ses autres courses.
--
-- À QUI : au compte qui a passé la commande, ou à qui connaît son numéro
-- ET le numéro de téléphone donné à la commande — la même règle que
-- « suivre_commande », pour le client qui a commandé sans compte.
--
-- QUAND : une fois la commande payée, la course confiée, et tant que le
-- client n'a pas confirmé l'avoir reçue. Après, le numéro du livreur n'a
-- plus de raison de rester sous ses yeux. Une part annulée, un livreur
-- désactivé : rien.
--
-- D'OÙ UNE FONCTION : le client ne lit pas « profils », et ne doit pas.
drop function if exists public.livreurs_de_ma_commande(text, text);
create or replace function public.livreurs_de_ma_commande(cible text, tel text default '')
returns table (boutique_id text, nom text, telephone text, indicatif text)
language plpgsql stable security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  tel_donne text := regexp_replace(coalesce(tel, ''), '\D', '', 'g');
begin
  if not exists (
    select 1 from public.commandes c
     where c.id = cible
       and not c.compte_supprime
       and c.etat = 'payee'
       and ((moi is not null and c.client_id = moi)
            or (tel_donne <> '' and c.client_tel = tel_donne))) then
    return;
  end if;
  return query
    select distinct on (l.boutique_id)
           l.boutique_id::text, coalesce(p.nom, '')::text, coalesce(p.tel, '')::text,
           coalesce(nullif(b.indicatif, ''), '229')::text
      from public.commande_lignes l
      join public.profils p
        on p.id = l.livreur_id and p.role = 'livreur' and p.actif
      left join public.boutiques b on b.id = l.boutique_id
     where l.commande_id = cible
       and l.etat <> 'annulee'
       and l.confirme_le is null
       -- (3.59.0) Une fois que le livreur a ACCEPTÉ la course (« Reçu ») —
       -- ou l'a prise : avant, on ne sait pas encore qui viendra.
       and (l.recu_le is not null or l.etat in ('en_livraison', 'remise'))
     order by l.boutique_id;
end $$;
revoke all on function public.livreurs_de_ma_commande(text, text) from public;
grant execute on function public.livreurs_de_ma_commande(text, text) to anon, authenticated;

-- ---------- La fiche d'une course (3.59.0) ----------
-- CE QU'IL FAUT AU LIVREUR, et rien de plus, pour la part d'UNE boutique :
--   où récupérer le colis   — la boutique : nom, adresse, téléphone, position ;
--   où le livrer            — le nom, l'adresse et la note du client ;
--   le numéro du destinataire ;
--   les frais de livraison de cette boutique ;
--   ce que le client a DÉJÀ PAYÉ pour cette part ;
--   ce qu'il reste à récupérer auprès de lui (« a_encaisser »).
-- Ni le prix des articles, ni le prix BIZZOO, ni le total des autres
-- boutiques. Réservée aux fonctions de la base.
create or replace function public.fiche_course(commande text, boutique text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c   public.commandes%rowtype;
  b   public.boutiques%rowtype;
  pos record;
  brut numeric;
  tout numeric;
  part numeric;
  frais numeric;
  reste numeric;
begin
  select * into c from public.commandes where id = commande;
  if not found then return null; end if;
  select * into b from public.boutiques where id = boutique;
  select sum(l.prix * l.quantite) filter (where l.boutique_id = boutique),
         sum(l.prix * l.quantite)
    into brut, tout
    from public.commande_lignes l where l.commande_id = commande;
  select coalesce(r.a_encaisser, 0) into reste
    from public.restes_par_boutique(commande) r where r.boutique_id = boutique;
  if c.livraison is not null then
    -- (3.64.0) AU KILOMÈTRE, un seul livreur porte toute la commande : ses
    -- frais sont ceux de la commande entière.
    part  := (c.parts -> boutique ->> 'du')::numeric;
    frais := coalesce(c.frais_livraison, 0);
  elsif c.parts is not null and c.parts ? boutique then
    part  := (c.parts -> boutique ->> 'du')::numeric;
    frais := (c.parts -> boutique ->> 'frais')::numeric;
  else
    -- Une commande d'avant les conditions par boutique : sa part au
    -- prorata, frais compris.
    part  := round(c.total * coalesce(brut, 0) / nullif(tout, 0));
    frais := case when coalesce(brut, 0) = coalesce(tout, 0) then coalesce(c.frais_livraison, 0)
                  else round(coalesce(c.frais_livraison, 0) * coalesce(brut, 0) / nullif(tout, 0)) end;
  end if;
  return jsonb_build_object(
    'numero', c.numero,
    'retrait', jsonb_build_object(
      'boutique', coalesce(b.nom, ''), 'adresse', coalesce(b.adresse, ''),
      'tel', coalesce(nullif(b.tel, ''), b.whatsapp, ''), 'indicatif', coalesce(nullif(b.indicatif, ''), '229'),
      'latitude', b.latitude, 'longitude', b.longitude),
    'livraison', jsonb_build_object(
      'nom', coalesce(c.client_nom, ''), 'adresse', coalesce(c.client_adresse, ''),
      'note', coalesce(c.note, ''), 'tel', coalesce(c.client_tel, ''),
      'indicatif', coalesce(nullif(c.client_indicatif, ''), '229'),
      -- (3.64.0) Le point exact où livrer, quand le client l'a donné.
      'latitude', c.livraison -> 'destination' -> 'latitude',
      'longitude', c.livraison -> 'destination' -> 'longitude'),
    'devise', coalesce(c.devise, 'FCFA'),
    'frais', coalesce(frais, 0),
    -- (3.64.0) Le véhicule, la distance, et ce que le livreur y gagne.
    'trajet', case when c.livraison is null then null
                   else jsonb_build_object('vehicule', c.livraison ->> 'vehicule',
                                           'distance_km', c.livraison -> 'distance_km') end,
    -- (3.66.0) Au kilomètre ou à l'ancien tarif : sa part des frais.
    'gain', public.gain_livreur(c.id),
    'deja_paye', greatest(0, coalesce(part, 0) - coalesce(reste, 0)),
    'a_encaisser', coalesce(reste, 0),
    -- Ce que le livreur a déclaré en remettant le colis (3.59.0).
    'encaisse', (select jsonb_build_object('montant', x.montant, 'mode', x.mode,
                         'encaisse_le', x.encaisse_le, 'remis_le', x.remis_le,
                         'transaction', x.transaction_id)
                   from public.encaissements x
                  where x.commande_id = commande and x.boutique_id = boutique),
    -- Le code MoMoPay de BIZZOO, à montrer au client (3.59.0).
    'momopay', (select jsonb_build_object('code', p.momopay_code, 'nom', p.momopay_nom)
                  from public.paiement p where p.id = 1));
end $$;
revoke all on function public.fiche_course(text, text) from public, anon, authenticated;

-- Un montant lisible dans une notification : « 14 350 FCFA ».
create or replace function public.montant_lisible(n numeric, devise text default 'FCFA')
returns text
language sql immutable set search_path = public as $$
  select replace(to_char(coalesce(n, 0), 'FM999,999,999,990'), ',', ' ') || ' ' || coalesce(nullif(devise, ''), 'FCFA');
$$;
revoke all on function public.montant_lisible(numeric, text) from public, anon, authenticated;

-- ---------- « Reçu » : le livreur accepte la course (3.59.0) ----------
-- Le client est alors prévenu, avec le nom et le numéro de son livreur ;
-- la boutique aussi. Seulement SES courses, et une seule fois.
-- Le livreur de BIZZOO accepte d'un coup TOUTE la commande qu'il porte :
-- une seule nouvelle au client.
create or replace function public.accepter_course(commande text, boutique text)
returns int
language plpgsql security definer set search_path = public as $$
declare
  moi     uuid := auth.uid();
  combien int;
  bizzoo  boolean;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Cette course ne vous est pas confiée';
  end if;
  select (p.boutique_id is null) into bizzoo from public.profils p where p.id = moi;
  perform set_config('bizzoo.livraison', 'oui', true);
  if coalesce(bizzoo, false) then
    perform set_config('bizzoo.prise', 'oui', true);
  end if;
  update public.commande_lignes l
     set recu_le = now()
   where l.commande_id = commande
     and (l.boutique_id = boutique or coalesce(bizzoo, false))
     and l.livreur_id = moi
     and l.recu_le is null
     -- (3.59.0) Dès le paiement : la course s'accepte avant que le colis
     -- soit prêt.
     and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison');
  get diagnostics combien = row_count;
  perform set_config('bizzoo.livraison', '', true);
  perform set_config('bizzoo.prise', '', true);
  if combien = 0 and not exists (
       select 1 from public.commande_lignes l
        where l.commande_id = commande and l.boutique_id = boutique
          and l.livreur_id = moi and l.recu_le is not null) then
    raise exception 'Cette course ne vous est pas confiée';
  end if;
  return combien;
end $$;
revoke all on function public.accepter_course(text, text) from public, anon;
grant execute on function public.accepter_course(text, text) to authenticated;

-- ---------- La demande de course, envoyée à tous (3.59.0) ----------
--
-- Dès que la commande est payée, la course est PROPOSÉE à plusieurs
-- livreurs à la fois ; le premier qui touche « Commande reçue » la prend.
--
--   * Une commande d'UNE boutique : ses livreurs. Une boutique qui n'en
--     a aucun de validé passe la main aux livreurs de BIZZOO — sinon sa
--     commande attendrait un porteur qui n'existe pas.
--   * Une commande de PLUSIEURS boutiques : livraison groupée, aux seuls
--     livreurs de BIZZOO. Celui qui la prend récupère les colis dans
--     chaque boutique et livre le tout au client.
--
-- Un livreur est « validé » quand il a enregistré sa position (3.58.0).
-- (3.64.0) LE VÉHICULE COMPTE. Une commande en tricycle ne se propose
-- qu'aux livreurs en tricycle. Une commande à moto, aux livreurs à moto —
-- et, s'il n'y en a aucun dans le groupe, aux tricycles, qui la portent
-- aussi bien. Une commande d'avant (sans véhicule) va à tous, comme avant.
create or replace function public.candidats_course(commande text)
returns uuid[]
language plpgsql stable security definer set search_path = public as $$
declare
  boutiques text[];
  qui       uuid[];
  besoin    text;
  vs        text[];
  v         text;
begin
  select array_agg(distinct l.boutique_id) into boutiques
    from public.commande_lignes l
   where l.commande_id = commande and l.etat <> 'annulee' and l.boutique_id is not null;
  if boutiques is null then return '{}'; end if;
  select c.livraison ->> 'vehicule' into besoin from public.commandes c where c.id = commande;
  vs := case besoin when 'tricycle' then array['tricycle']
                    when 'moto' then array['moto', 'tricycle']
                    else array[null::text] end;
  if array_length(boutiques, 1) = 1 then
    foreach v in array vs loop
      select array_agg(p.id order by p.id) into qui
        from public.profils p
       where p.role = 'livreur' and p.actif and not p.courses_bloquees and p.boutique_id = boutiques[1]
         and (v is null or p.vehicule = v)
         and exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id);
      if qui is not null then return qui; end if;
    end loop;
  end if;
  foreach v in array vs loop
    select array_agg(p.id order by p.id) into qui
      from public.profils p
     where p.role = 'livreur' and p.actif and not p.courses_bloquees and p.boutique_id is null
       and (v is null or p.vehicule = v)
       and exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id);
    if qui is not null then return qui; end if;
  end loop;
  return '{}';
end $$;
revoke all on function public.candidats_course(text) from public, anon, authenticated;

-- La fiche de la demande : la fiche de chaque boutique, additionnée.
-- Une seule boutique : un seul lieu de retrait. Groupée : un par boutique.
create or replace function public.fiche_demande(commande text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  f        jsonb;
  b        text;
  retraits jsonb := '[]';
  premiere jsonb;
  frais    numeric := 0;
  paye     numeric := 0;
  reste    numeric := 0;
begin
  for b in select distinct l.boutique_id from public.commande_lignes l
            where l.commande_id = commande and l.etat <> 'annulee' and l.boutique_id is not null
            order by 1 loop
    f := public.fiche_course(commande, b);
    if f is null then continue; end if;
    premiere := coalesce(premiere, f);
    retraits := retraits || jsonb_build_array((f -> 'retrait') ||
      jsonb_build_object('boutique_id', b, 'a_encaisser', f -> 'a_encaisser'));
    frais := frais + coalesce((f ->> 'frais')::numeric, 0);
    paye  := paye  + coalesce((f ->> 'deja_paye')::numeric, 0);
    reste := reste + coalesce((f ->> 'a_encaisser')::numeric, 0);
  end loop;
  if premiere is null then return null; end if;
  -- (3.64.0) Au kilomètre, les frais sont ceux de la commande, pas la
  -- somme de chaque boutique : chaque fiche les porte déjà en entier.
  if premiere -> 'trajet' is not null and jsonb_typeof(premiere -> 'trajet') = 'object' then
    frais := coalesce((premiere ->> 'frais')::numeric, 0);
  end if;
  return jsonb_build_object(
    'numero', premiere -> 'numero',
    'groupee', jsonb_array_length(retraits) > 1,
    'retraits', retraits,
    'livraison', premiere -> 'livraison',
    'devise', premiere -> 'devise',
    'trajet', premiere -> 'trajet',
    'gain', premiere -> 'gain',
    'frais', frais, 'deja_paye', paye, 'a_encaisser', reste);
end $$;
revoke all on function public.fiche_demande(text) from public, anon, authenticated;

-- Le texte de l'alerte : le même pour tous les livreurs à qui on la
-- propose.
create or replace function public.texte_demande(f jsonb)
returns text
language plpgsql stable set search_path = public as $$
declare
  r     jsonb;
  texte text := '';
begin
  if coalesce((f ->> 'groupee')::boolean, false) then
    texte := 'Livraison groupée : ' || jsonb_array_length(f -> 'retraits') || ' boutiques.' || E'\n';
  end if;
  for r in select * from jsonb_array_elements(f -> 'retraits') loop
    texte := texte || 'Récupérer : ' || (r ->> 'boutique') ||
      coalesce(nullif(' — ' || (r ->> 'adresse'), ' — '), '') || E'\n';
  end loop;
  return texte ||
    'Livrer à : ' || coalesce(nullif(f -> 'livraison' ->> 'nom', ''), 'le client') ||
      coalesce(nullif(' — ' || (f -> 'livraison' ->> 'adresse'), ' — '), ' (adresse à demander)') || E'\n' ||
    'Destinataire : +' || (f -> 'livraison' ->> 'indicatif') || ' ' || (f -> 'livraison' ->> 'tel') || E'\n' ||
    -- (3.64.0) Le véhicule et la distance, puis ce qu'il y gagne.
    case when jsonb_typeof(f -> 'trajet') = 'object'
         then 'Véhicule : ' || case when f -> 'trajet' ->> 'vehicule' = 'tricycle' then 'tricycle' else 'moto' end ||
              ' — ' || replace(f -> 'trajet' ->> 'distance_km', '.', ',') || ' km' || E'\n'
         else '' end ||
    'Frais de livraison : ' || public.montant_lisible((f ->> 'frais')::numeric, f ->> 'devise') || E'\n' ||
    case when (f ->> 'gain') is not null
         then 'Votre gain : ' || public.montant_lisible((f ->> 'gain')::numeric, f ->> 'devise') || E'\n'
         else '' end ||
    'Déjà payé : ' || public.montant_lisible((f ->> 'deja_paye')::numeric, f ->> 'devise') || E'\n' ||
    case when (f ->> 'a_encaisser')::numeric > 0
         then 'À récupérer : ' || public.montant_lisible((f ->> 'a_encaisser')::numeric, f ->> 'devise')
         else 'Rien à récupérer : tout est payé.' end || E'\n' ||
    'Le premier qui touche « Commande reçue » prend la course.';
end $$;
revoke all on function public.texte_demande(jsonb) from public, anon, authenticated;

-- Au paiement : la demande part. Une panne ici ne doit jamais faire
-- échouer le paiement — elle se lit dans le journal, et la boutique
-- garde « Confier à un livreur ».
create or replace function public.proposer_course() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  f jsonb;
begin
  if new.etat is not distinct from old.etat or new.etat <> 'payee' then
    return null;
  end if;
  begin
    f := public.fiche_demande(new.id);
    if f is null then return null; end if;
    perform public.notifier(public.candidats_course(new.id), 'course_proposee',
      case when (f ->> 'groupee')::boolean
           then 'Livraison groupée — ' || coalesce(new.numero, '')
           else 'Nouvelle course — ' || coalesce(new.numero, '') end,
      public.texte_demande(f),
      '#/livraisons', new.id, null, true);
  exception when others then
    raise warning 'proposer_course(%) : %', new.id, sqlerrm;
  end;
  return null;
end $$;

drop trigger if exists commandes_proposent on public.commandes;
create trigger commandes_proposent
  after update of etat on public.commandes
  for each row execute function public.proposer_course();

-- Les demandes ouvertes que CE livreur peut prendre : payées, sans
-- livreur, et dont il fait partie des destinataires.
create or replace function public.courses_proposees()
returns table (commande_id text, numero text, paye_le timestamptz, fiche jsonb)
language plpgsql stable security definer set search_path = public as $$
declare moi uuid := auth.uid();
begin
  if moi is null or not public.est_livreur() then return; end if;
  if not exists (select 1 from public.positions_livreurs pl where pl.profil_id = moi) then return; end if;
  return query
    select c.id, c.numero, c.paye_le, public.fiche_demande(c.id)
      from public.commandes c
     where c.etat = 'payee'
       and exists (select 1 from public.commande_lignes l
                    where l.commande_id = c.id and l.etat <> 'annulee')
       -- Personne ne l'a encore prise, ni reçue en secours.
       and not exists (select 1 from public.commande_lignes l
                        where l.commande_id = c.id and l.etat <> 'annulee'
                          and l.livreur_id is not null)
       and not exists (select 1 from public.commande_lignes l
                        where l.commande_id = c.id
                          and l.etat in ('en_livraison', 'remise'))
       and c.paye_le > now() - interval '7 days'
       and moi = any(public.candidats_course(c.id))
       -- (3.59.0) Il l'a refusée : elle ne lui revient pas.
       and not exists (select 1 from public.refus_courses rc
                        where rc.commande_id = c.id and rc.livreur_id = moi)
     order by c.paye_le;
end $$;
revoke all on function public.courses_proposees() from public, anon;
grant execute on function public.courses_proposees() to authenticated;

-- « Commande reçue » : le premier qui touche prend TOUTE la commande —
-- toutes ses boutiques en livraison groupée. Le verrou sur la commande
-- range les livreurs en file : le second trouve la course déjà prise.
create or replace function public.prendre_course(commande text)
returns int
language plpgsql security definer set search_path = public as $$
declare
  moi     uuid := auth.uid();
  combien int;
  preneur text;
  numero  text;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Seul un livreur prend une course';
  end if;
  perform 1 from public.commandes c where c.id = commande and c.etat = 'payee' for update;
  if not found then
    raise exception 'Cette commande n''attend pas de livreur';
  end if;
  if not (moi = any(public.candidats_course(commande))) then
    raise exception 'Cette course n''est pas proposée à votre compte';
  end if;
  if exists (select 1 from public.refus_courses rc
              where rc.commande_id = commande and rc.livreur_id = moi) then
    raise exception 'Vous avez refusé cette course.' using errcode = 'P0001';
  end if;
  -- (3.59.0) On dit QUI l'a prise.
  select coalesce(nullif(p.nom, ''), 'un autre livreur') into preneur
    from public.commande_lignes l join public.profils p on p.id = l.livreur_id
   where l.commande_id = commande and l.etat <> 'annulee' and l.livreur_id is not null
   limit 1;
  if preneur is not null then
    raise exception 'Déjà pris par %.', preneur using errcode = 'P0001';
  end if;

  perform set_config('bizzoo.livraison', 'oui', true);
  perform set_config('bizzoo.prise', 'oui', true);
  update public.commande_lignes l
     set livreur_id = moi, recu_le = now()
   where l.commande_id = commande
     and l.livreur_id is null
     and l.etat in ('nouvelle', 'vue', 'preparee');
  get diagnostics combien = row_count;
  perform set_config('bizzoo.prise', '', true);
  perform set_config('bizzoo.livraison', '', true);
  if combien = 0 then
    raise exception 'Trop tard : un autre livreur a déjà pris cette course.'
      using errcode = 'P0001';
  end if;

  -- (3.59.0) LES AUTRES SONT PRÉVENUS TOUT DE SUITE : « Déjà pris par … ».
  -- La nouvelle arrive en temps réel sur leur téléphone, et leur
  -- sonnerie s'arrête. Leur demande d'avant passe « lue ».
  select coalesce(nullif(p.nom, ''), 'un autre livreur') into preneur
    from public.profils p where p.id = moi;
  select c.numero into numero from public.commandes c where c.id = commande;
  update public.notifications n
     set lue_le = now()
   where n.commande_id = commande and n.type = 'course_proposee'
     and n.destinataire <> moi and n.lue_le is null;
  perform public.notifier(
    array(select x from unnest(public.candidats_course(commande)) as x where x <> moi),
    'course_prise',
    'Déjà pris par ' || preneur,
    'Commande ' || coalesce(numero, '') || ' — ' || preneur || ' a pris la course. Elle n''est plus disponible.',
    '#/livraisons', commande, null, false);
  return combien;
end $$;
revoke all on function public.prendre_course(text) from public, anon;
grant execute on function public.prendre_course(text) to authenticated;

-- ---------- Le reste payé à la livraison (3.59.0) ----------
--
-- AVANT, LE RESTE PASSAIT DE MAIN EN MAIN SANS LAISSER DE TRACE : le
-- livreur touchait « Je l'ai remise », et l'application supposait que le
-- client avait payé. Désormais :
--
--   1. le livreur DÉCLARE ce qu'il a encaissé, et comment (espèces ou
--      Mobile Money), en remettant le colis (remettre_course). Un montant
--      différent de ce qui était dû demande un motif écrit ;
--   2. le client le voit sur son reçu (« Reste payé à la livraison »), en
--      reçoit la nouvelle, et peut le contester (contester_encaissement) ;
--   3. LA CAISSE : la boutique voit ce que chaque livreur a encaissé pour
--      SES colis et ne lui a pas encore rendu, et marque « Argent reçu du
--      livreur » (marquer_remis). BIZZOO voit tout.
--
-- Une ligne par boutique et par commande : c'est la part de CETTE
-- boutique que son livreur réclame à la porte. Personne n'y écrit
-- directement — seulement par les fonctions ci-dessous.
create table if not exists public.encaissements (
  id             bigserial primary key,
  commande_id    text not null references public.commandes(id) on delete cascade,
  boutique_id    text not null references public.boutiques(id) on delete cascade,
  livreur_id     uuid references public.profils(id) on delete set null,
  -- Ce que le client devait à cette boutique à la livraison, et ce que
  -- le livreur dit avoir reçu.
  du             bigint not null default 0,
  montant        bigint not null default 0,
  mode           text not null default 'aucun',
  motif          text not null default '',
  encaisse_le    timestamptz not null default now(),
  -- L'argent rendu par le livreur à la boutique (ou à BIZZOO).
  remis_le       timestamptz,
  remis_par      uuid references public.profils(id) on delete set null,
  -- Le client conteste ce qui a été déclaré.
  conteste_le    timestamptz,
  conteste_motif text not null default '',
  constraint encaissements_un_par_part unique (commande_id, boutique_id),
  constraint encaissements_mode check (mode in ('especes', 'mobile_money', 'aucun')),
  constraint encaissements_montant check (montant >= 0 and du >= 0)
);
-- (3.59.0) Le numéro de la transaction MoMoPay, lu sur le SMS du client :
-- c'est lui que BIZZOO retrouve dans son compte marchand.
alter table public.encaissements add column if not exists transaction_id text not null default '';
create index if not exists encaissements_livreur on public.encaissements(livreur_id) where remis_le is null;
create index if not exists encaissements_boutique on public.encaissements(boutique_id, encaisse_le desc);
alter table public.encaissements enable row level security;
revoke all on public.encaissements from anon, authenticated;
revoke all on sequence public.encaissements_id_seq from anon, authenticated;

-- Qui tient la caisse d'une boutique : le superadministrateur, un compte
-- de BIZZOO qui suit les commandes ou les finances, l'administrateur de
-- CETTE boutique. Un modérateur, non : c'est de l'argent.
create or replace function public.tient_la_caisse(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.droit_enseigne('commandes')
      or public.droit_enseigne('finances')
      or (public.est_admin() and cible is not null
          and cible = public.boutique_du_compte());
$$;
revoke all on function public.tient_la_caisse(text) from public, anon, authenticated;
grant execute on function public.tient_la_caisse(text) to authenticated;

-- « Je l'ai remise » (3.59.0) : PLUS D'ESPÈCES. Le reste se paie par
-- MoMoPay, sur le compte marchand de BIZZOO : le livreur montre le code et
-- le montant, le client paie depuis son téléphone et reçoit un SMS avec le
-- numéro de la transaction. Le livreur le saisit ici (« motif ») : sans
-- lui, le colis ne se remet pas. Le montant est celui qui était dû, au
-- franc près. BIZZOO vérifie ensuite chaque transaction dans son compte
-- MoMoPay (« Caisse ») ; d'ici là, le paiement est « à vérifier ».
create or replace function public.remettre_course(
  commande text, boutique text, montant bigint, mode text, motif text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  moi      uuid := auth.uid();
  combien  int;
  du       bigint;
  trans    text := upper(left(regexp_replace(coalesce(motif, ''), '[^A-Za-z0-9.-]', '', 'g'), 40));
  c        record;
  porteur  text;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Cette course ne vous est pas confiée';
  end if;
  if not exists (select 1 from public.commande_lignes l
                  where l.commande_id = commande and l.boutique_id = boutique
                    and l.livreur_id = moi and l.etat = 'en_livraison') then
    raise exception 'Rien à remettre ici : cette course n''en est pas là.';
  end if;
  select c0.numero, c0.client_id, coalesce(nullif(c0.devise, ''), 'FCFA') as devise
    into c from public.commandes c0 where c0.id = commande;
  select coalesce(r.a_encaisser, 0) into du
    from public.restes_par_boutique(commande) r where r.boutique_id = boutique;
  du := coalesce(du, 0);

  if du > 0 then
    if coalesce(mode, '') <> 'mobile_money' then
      raise exception 'Plus d''espèces : le client paie % par MoMoPay. Mettez l''application à jour.',
        public.montant_lisible(du, c.devise) using errcode = 'P0001';
    end if;
    if coalesce(montant, 0) <> du then
      raise exception 'Le client doit payer exactement % par MoMoPay.',
        public.montant_lisible(du, c.devise) using errcode = 'P0001';
    end if;
    if length(trans) < 4 then
      raise exception 'Saisissez le numéro de la transaction MoMoPay, lu sur le SMS du client.'
        using errcode = 'P0001';
    end if;
    if exists (select 1 from public.encaissements x
                where x.mode = 'mobile_money' and x.transaction_id = trans) then
      raise exception 'Cette transaction MoMoPay a déjà servi pour une autre commande : vérifiez le SMS du client.'
        using errcode = 'P0001';
    end if;
  end if;

  perform set_config('bizzoo.livraison', 'oui', true);
  update public.commande_lignes l
     set etat = 'remise',
         recu_le = coalesce(l.recu_le, now())
   where l.commande_id = commande
     and l.boutique_id = boutique
     and l.livreur_id = moi
     and l.etat = 'en_livraison';
  get diagnostics combien = row_count;
  perform set_config('bizzoo.livraison', '', true);

  if du = 0 then
    -- Rien n'était dû : la part est soldée, rien à vérifier.
    insert into public.encaissements (commande_id, boutique_id, livreur_id, du, montant, mode, remis_le)
    values (commande, boutique, moi, 0, 0, 'aucun', now())
    on conflict (commande_id, boutique_id) do nothing;
    return jsonb_build_object('lignes', combien, 'du', 0, 'montant', 0, 'mode', 'aucun');
  end if;

  -- Payé par MoMoPay : « remis_le » reste vide tant que BIZZOO n'a pas
  -- retrouvé la transaction dans son compte.
  insert into public.encaissements (commande_id, boutique_id, livreur_id, du, montant, mode, motif, transaction_id)
  values (commande, boutique, moi, du, du, 'mobile_money', 'MoMoPay — transaction ' || trans, trans)
  on conflict (commande_id, boutique_id) do nothing;

  select coalesce(nullif(p.nom, ''), 'votre livreur') into porteur from public.profils p where p.id = moi;
  if c.client_id is not null then
    perform public.notifier(array[c.client_id], 'reste_encaisse',
      'Reste payé : ' || public.montant_lisible(du, c.devise),
      'Commande ' || coalesce(c.numero, '') ||
        coalesce(' — ' || nullif((select b.nom from public.boutiques b where b.id = boutique), ''), '') || '.' ||
        E'\nPayé par MoMoPay (transaction ' || trans || '), remis par ' || porteur || '.' ||
        E'\nSi ce n''est pas exact, signalez-le depuis votre commande.',
      '#/commande/' || commande, commande, boutique, true);
  end if;
  perform public.notifier(public.equipe_de(boutique) || public.enseigne_des_commandes() || public.les_superadmins(),
    'reste_encaisse',
    'MoMoPay à vérifier : ' || public.montant_lisible(du, c.devise),
    'Commande ' || coalesce(c.numero, '') || ' — transaction ' || trans || ', remise par ' || porteur || '.' ||
      E'\nÀ retrouver dans le compte MoMoPay de BIZZOO.',
    '#/caisse', commande, boutique, true);

  return jsonb_build_object('lignes', combien, 'du', du, 'montant', du, 'mode', 'mobile_money',
    'transaction', trans);
end $$;
revoke all on function public.remettre_course(text, text, bigint, text, text) from public, anon;
grant execute on function public.remettre_course(text, text, bigint, text, text) to authenticated;

-- Le client conteste ce que le livreur a déclaré. Comme pour suivre sa
-- commande : son compte, ou son numéro.
create or replace function public.contester_encaissement(
  commande text, boutique text, motif text, tel text default '')
returns int
language plpgsql security definer set search_path = public as $$
declare
  combien  int;
  pourquoi text := left(trim(coalesce(motif, '')), 300);
  e        record;
begin
  if not (public.ma_commande(commande)
          or exists (select 1 from public.commandes c
                      where c.id = commande and not c.compte_supprime
                        and regexp_replace(coalesce(tel, ''), '\D', '', 'g') <> ''
                        and c.client_tel = regexp_replace(coalesce(tel, ''), '\D', '', 'g'))) then
    raise exception 'Cette commande n''est pas la vôtre';
  end if;
  if length(pourquoi) < 3 then
    raise exception 'Dites en quelques mots ce qui ne va pas.' using errcode = 'P0001';
  end if;
  update public.encaissements x
     set conteste_le = now(), conteste_motif = pourquoi
   where x.commande_id = commande and x.boutique_id = boutique and x.conteste_le is null;
  get diagnostics combien = row_count;
  if combien = 0 then
    if exists (select 1 from public.encaissements x
                where x.commande_id = commande and x.boutique_id = boutique) then
      raise exception 'Vous l''avez déjà signalé : la boutique et BIZZOO sont prévenus.' using errcode = 'P0001';
    end if;
    raise exception 'Aucun paiement à la livraison n''est enregistré pour cette commande.' using errcode = 'P0001';
  end if;

  select x.montant, x.mode, cm.numero, coalesce(nullif(cm.devise, ''), 'FCFA') as devise,
         coalesce(nullif(p.nom, ''), 'le livreur') as porteur
    into e
    from public.encaissements x
    join public.commandes cm on cm.id = x.commande_id
    left join public.profils p on p.id = x.livreur_id
   where x.commande_id = commande and x.boutique_id = boutique;
  perform public.notifier(public.equipe_de(boutique) || public.enseigne_des_commandes() || public.les_superadmins(),
    'encaissement_conteste',
    'Paiement contesté — ' || coalesce(e.numero, ''),
    'Le client conteste : « ' || pourquoi || ' ».' ||
      E'\nDéclaré : ' || public.montant_lisible(e.montant, e.devise) || ' encaissé par ' || e.porteur || '.',
    '#/caisse', commande, boutique, true);
  return combien;
end $$;
revoke all on function public.contester_encaissement(text, text, text, text) from public;
grant execute on function public.contester_encaissement(text, text, text, text) to anon, authenticated;

-- LA CAISSE : ce qui a été encaissé à la livraison, sur les boutiques que
-- l'on tient — rendu ou pas encore. Et les remises SANS déclaration
-- (faites depuis une application d'avant 3.59.0) alors qu'un reste était
-- dû : « declare » à faux, pour qu'elles ne passent pas inaperçues.
create or replace function public.caisse_livreurs()
returns table (
  id bigint, commande_id text, numero text, boutique_id text, nom_boutique text,
  livreur_id uuid, livreur_nom text, livreur_tel text,
  du bigint, montant bigint, mode text, motif text,
  encaisse_le timestamptz, remis_le timestamptz, remis_par_nom text,
  conteste_le timestamptz, conteste_motif text, declare boolean, devise text)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  return query
    select x.id, x.commande_id, c.numero::text, x.boutique_id,
           coalesce(b.nom, '')::text,
           x.livreur_id, coalesce(nullif(p.nom, ''), p.email, '')::text, coalesce(p.tel, '')::text,
           x.du, x.montant, x.mode, x.motif,
           x.encaisse_le, x.remis_le, coalesce(nullif(q.nom, ''), q.email, '')::text,
           x.conteste_le, x.conteste_motif, true,
           coalesce(nullif(c.devise, ''), 'FCFA')::text
      from public.encaissements x
      join public.commandes c on c.id = x.commande_id
      left join public.boutiques b on b.id = x.boutique_id
      left join public.profils p on p.id = x.livreur_id
      left join public.profils q on q.id = x.remis_par
     where public.tient_la_caisse(x.boutique_id)
       and (x.remis_le is null or x.encaisse_le > now() - interval '60 days')
    union all
    select null::bigint, l.commande_id, c.numero::text, l.boutique_id,
           coalesce(b.nom, '')::text,
           l.livreur_id, coalesce(nullif(p.nom, ''), p.email, '')::text, coalesce(p.tel, '')::text,
           r.a_encaisser, null::bigint, ''::text, ''::text,
           max(c.paye_le), null::timestamptz, ''::text,
           null::timestamptz, ''::text, false,
           coalesce(nullif(c.devise, ''), 'FCFA')::text
      from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id and c.etat = 'payee'
      left join public.boutiques b on b.id = l.boutique_id
      left join public.profils p on p.id = l.livreur_id
      join lateral (select rr.a_encaisser from public.restes_par_boutique(l.commande_id) rr
                     where rr.boutique_id = l.boutique_id) r on true
     where l.etat = 'remise'
       and public.tient_la_caisse(l.boutique_id)
       and c.paye_le > now() - interval '60 days'
       and r.a_encaisser > 0
       and not exists (select 1 from public.encaissements x
                        where x.commande_id = l.commande_id and x.boutique_id = l.boutique_id)
     group by l.commande_id, c.numero, l.boutique_id, b.nom, l.livreur_id, p.nom, p.email, p.tel,
              r.a_encaisser, c.devise
     order by 13 desc;
end $$;
revoke all on function public.caisse_livreurs() from public, anon;
grant execute on function public.caisse_livreurs() to authenticated;

-- « Argent reçu du livreur » : une ou plusieurs lignes à la fois. Le
-- livreur est prévenu de ce que la boutique a bien reçu de lui.
create or replace function public.marquer_remis(ids bigint[])
returns int
language plpgsql security definer set search_path = public as $$
declare
  faits jsonb;
  r     record;
begin
  if auth.uid() is null then raise exception 'Connectez-vous'; end if;
  with marques as (
    update public.encaissements x
       set remis_le = now(), remis_par = auth.uid()
     where x.id = any(ids) and x.remis_le is null and x.montant > 0
       and public.tient_la_caisse(x.boutique_id)
       -- (3.59.0) Un paiement MoMoPay arrive sur le compte de BIZZOO :
       -- BIZZOO seul peut dire l'y avoir trouvé.
       and (x.mode <> 'mobile_money' or public.est_super()
            or public.droit_enseigne('finances') or public.droit_enseigne('commandes'))
    returning x.livreur_id, x.boutique_id, x.montant, x.commande_id, x.mode
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'livreur', m.livreur_id, 'boutique', m.boutique_id, 'montant', m.montant, 'mode', m.mode,
           'devise', (select coalesce(nullif(c.devise, ''), 'FCFA') from public.commandes c
                       where c.id = m.commande_id))), '[]'::jsonb)
    into faits from marques m;
  if jsonb_array_length(faits) = 0 then
    raise exception 'Rien à marquer : ces encaissements sont déjà rendus, ou ne sont pas de votre boutique.'
      using errcode = 'P0001';
  end if;
  for r in select (f ->> 'livreur')::uuid as livreur, f ->> 'boutique' as boutique,
                  sum((f ->> 'montant')::bigint) as total, min(f ->> 'devise') as devise, count(*) as nb
             from jsonb_array_elements(faits) f
            where f ->> 'livreur' is not null
              -- MoMoPay : le livreur n'avait rien en main, rien à lui dire.
              and f ->> 'mode' <> 'mobile_money'
            group by 1, 2 loop
    perform public.notifier(array[r.livreur], 'caisse_remise',
      'Argent bien reçu : ' || public.montant_lisible(r.total, r.devise),
      coalesce((select b.nom from public.boutiques b where b.id = r.boutique), 'La boutique') ||
        ' a bien reçu de vous ' || public.montant_lisible(r.total, r.devise) ||
        ' (' || r.nb || ' course' || case when r.nb > 1 then 's' else '' end || ').',
      '#/livraisons', null, r.boutique, false);
  end loop;
  return jsonb_array_length(faits);
end $$;
revoke all on function public.marquer_remis(bigint[]) from public, anon;
grant execute on function public.marquer_remis(bigint[]) to authenticated;

-- Ce que le livreur a encaissé et n'a pas encore rendu, boutique par
-- boutique : il sait à qui il doit quoi.
create or replace function public.ma_caisse()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare moi uuid := auth.uid();
begin
  if moi is null or not public.est_livreur() then return null; end if;
  return jsonb_build_object(
    -- (3.59.0) Un paiement MoMoPay n'est jamais passé par ses mains.
    'a_remettre', coalesce((select sum(x.montant) from public.encaissements x
                             where x.livreur_id = moi and x.remis_le is null
                               and x.mode <> 'mobile_money'), 0),
    'courses', (select count(*) from public.encaissements x
                 where x.livreur_id = moi and x.remis_le is null and x.montant > 0
                   and x.mode <> 'mobile_money'),
    'boutiques', coalesce((
      select jsonb_agg(jsonb_build_object('boutique', coalesce(b.nom, ''), 'montant', t.total) order by b.nom)
        from (select x.boutique_id, sum(x.montant) as total from public.encaissements x
               where x.livreur_id = moi and x.remis_le is null and x.montant > 0
                 and x.mode <> 'mobile_money'
               group by x.boutique_id) t
        left join public.boutiques b on b.id = t.boutique_id), '[]'::jsonb));
end $$;
revoke all on function public.ma_caisse() from public, anon;
grant execute on function public.ma_caisse() to authenticated;

-- ---------- Le livreur refuse une course (3.59.0) ----------
--
-- Une course confiée — ou prise sur la demande — se refuse tant que le
-- colis n'est pas parti (« Je l'ai prise »). Elle redevient libre : la
-- boutique voit « Commande refusée par le livreur » et la confie à
-- nouveau, et la demande se rouvre aux autres livreurs. Celui qui a
-- refusé ne la revoit plus. Chaque refus est gardé.
create table if not exists public.refus_courses (
  id          bigserial primary key,
  commande_id text not null references public.commandes(id) on delete cascade,
  boutique_id text not null references public.boutiques(id) on delete cascade,
  livreur_id  uuid references public.profils(id) on delete set null,
  motif       text not null default '',
  refuse_le   timestamptz not null default now()
);
create index if not exists refus_courses_commande on public.refus_courses(commande_id, refuse_le desc);
alter table public.refus_courses enable row level security;
revoke all on public.refus_courses from anon, authenticated;
revoke all on sequence public.refus_courses_id_seq from anon, authenticated;

create or replace function public.refuser_course(commande text, motif text default '')
returns int
language plpgsql security definer set search_path = public as $$
declare
  moi      uuid := auth.uid();
  pourquoi text := left(trim(coalesce(motif, '')), 300);
  parts    record;
  combien  int := 0;
  porteur  text;
  c        record;
  annonce  boolean;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Seul le livreur de la course la refuse';
  end if;
  if not exists (select 1 from public.commande_lignes l
                  where l.commande_id = commande and l.livreur_id = moi
                    and l.etat in ('nouvelle', 'vue', 'preparee')) then
    if exists (select 1 from public.commande_lignes l
                where l.commande_id = commande and l.livreur_id = moi) then
      raise exception 'Le colis est déjà parti avec vous : vous ne pouvez plus refuser cette course.'
        using errcode = 'P0001';
    end if;
    raise exception 'Cette course ne vous est pas confiée';
  end if;
  select coalesce(nullif(p.nom, ''), 'Le livreur') into porteur from public.profils p where p.id = moi;
  select c0.numero, c0.client_id into c from public.commandes c0 where c0.id = commande;
  -- Le client savait-il déjà qui viendrait ?
  select exists (select 1 from public.commande_lignes l
                  where l.commande_id = commande and l.livreur_id = moi and l.recu_le is not null)
    into annonce;

  -- UNE NOUVELLE COURSE, DE NOUVELLES NOUVELLES. Chaque sorte de
  -- notification ne part qu'une fois par commande ; sans ceci, le client
  -- ne recevrait jamais le nom du livreur suivant. Les anciennes restent
  -- lisibles, mises de côté sous « …_avant_<n> » — le numéro, parce
  -- qu'une course peut être refusée plus d'une fois.
  update public.notifications n
     set type = n.type || '_avant_' || n.id
   where n.commande_id = commande
     and n.type in ('course_confiee', 'course_acceptee', 'course_refusee');

  perform set_config('bizzoo.livraison', 'oui', true);
  perform set_config('bizzoo.refus', 'oui', true);
  for parts in
    with liberees as (
      update public.commande_lignes l
         set livreur_id = null, recu_le = null
       where l.commande_id = commande and l.livreur_id = moi
         and l.etat in ('nouvelle', 'vue', 'preparee')
      returning l.boutique_id
    )
    select distinct boutique_id from liberees
  loop
    combien := combien + 1;
    insert into public.refus_courses (commande_id, boutique_id, livreur_id, motif)
    values (commande, parts.boutique_id, moi, pourquoi);
    perform public.notifier(public.equipe_de(parts.boutique_id), 'course_refusee',
      'Commande refusée par le livreur — ' || coalesce(c.numero, ''),
      porteur || ' a refusé la course' ||
        case when pourquoi <> '' then ' : « ' || pourquoi || ' »' else '' end || '.' ||
        E'\nConfiez-la à un autre livreur : la demande est aussi repartie vers les autres.',
      '#/commandes/' || commande, commande, parts.boutique_id, true);
  end loop;
  perform set_config('bizzoo.refus', '', true);
  perform set_config('bizzoo.livraison', '', true);

  if annonce and c.client_id is not null then
    perform public.notifier(array[c.client_id], 'course_refusee',
      'Votre livreur a changé',
      'Commande ' || coalesce(c.numero, '') || ' : ' || porteur ||
        ' ne peut pas la livrer. Un autre livreur va la prendre ; vous recevrez son nom et son numéro.',
      '#/commande/' || commande, commande, null, true);
  end if;
  return combien;
end $$;
revoke all on function public.refuser_course(text, text) from public, anon;
grant execute on function public.refuser_course(text, text) to authenticated;

-- CE QUE LA BOUTIQUE VOIT DE LA LIVRAISON de ses commandes : qui a pris
-- la course (nom, numéro), s'il l'a acceptée, et le dernier refus. Les
-- lignes de commande ne se lisent que colonne par colonne, et le livreur
-- n'en fait pas partie : c'est cette fonction qui le dit, et seulement
-- pour les boutiques que le compte tient.
create or replace function public.livraison_des_commandes(cibles text[])
returns table (commande_id text, boutique_id text,
               livreur_nom text, livreur_tel text, livreur_bizzoo boolean, recu_le timestamptz,
               refus_nom text, refus_motif text, refuse_le timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or not (public.est_equipe() or public.est_compte_enseigne()) then return; end if;
  return query
    select x.commande_id, x.boutique_id,
           coalesce(nullif(p.nom, ''), p.email, '')::text, coalesce(p.tel, '')::text,
           (p.id is not null and p.boutique_id is null), x.recu,
           coalesce(nullif(q.nom, ''), q.email, '')::text, coalesce(r.motif, '')::text, r.refuse_le
      from (select l.commande_id, l.boutique_id,
                   (array_agg(l.livreur_id) filter (where l.livreur_id is not null and l.etat <> 'annulee'))[1] as livreur,
                   min(l.recu_le) as recu
              from public.commande_lignes l
             where l.commande_id = any(cibles)
               and public.peut_agir_sur(l.boutique_id)
             group by l.commande_id, l.boutique_id) x
      left join public.profils p on p.id = x.livreur
      left join lateral (select rc.livreur_id, rc.motif, rc.refuse_le from public.refus_courses rc
                          where rc.commande_id = x.commande_id and rc.boutique_id = x.boutique_id
                          order by rc.refuse_le desc limit 1) r on true
      left join public.profils q on q.id = r.livreur_id;
end $$;
revoke all on function public.livraison_des_commandes(text[]) from public, anon;
grant execute on function public.livraison_des_commandes(text[]) to authenticated;

-- ---------- Le livreur avance sa course ----------
-- DEUX ÉTAPES, ET PAS D'AUTRES : « je l'ai prise » et « je l'ai
-- remise ». Préparer reste à la boutique ; annuler aussi.
--
-- Et seulement SES lignes. Un livreur qui pourrait avancer celles d'un
-- collègue déclarerait remises des commandes qu'il n'a jamais portées.
create or replace function public.avancer_livraison(
  commande text, boutique text, vers text)
returns int
language plpgsql security definer set search_path = public as $$
declare
  moi     uuid := auth.uid();
  combien int;
  depuis  text;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Cette course ne vous est pas confiée';
  end if;
  if vers not in ('en_livraison', 'remise') then
    raise exception 'Un livreur prend une course, ou la remet.';
  end if;
  -- On n'avance que dans le bon sens : « remise » ne se pose qu'après
  -- « en livraison ». Sans cela, une course se déclarerait remise sans
  -- jamais avoir été prise.
  depuis := case when vers = 'en_livraison' then 'preparee' else 'en_livraison' end;

  -- (3.59.0) PAS DE REMISE SANS LE RESTE PAYÉ PAR MOMOPAY. Ce chemin
  -- d'avant (« Je l'ai remise » sans rien déclarer) ne passe plus quand
  -- le client doit encore quelque chose : c'est remettre_course, avec le
  -- numéro de la transaction, qui remet le colis.
  if vers = 'remise'
     and coalesce((select r.a_encaisser from public.restes_par_boutique(commande) r
                    where r.boutique_id = boutique), 0) > 0
     and not exists (select 1 from public.encaissements x
                      where x.commande_id = commande and x.boutique_id = boutique
                        and x.mode = 'mobile_money') then
    raise exception 'Le client doit d''abord payer le reste par MoMoPay : touchez « Remettre le colis » et saisissez le numéro de la transaction.'
      using errcode = 'P0001';
  end if;

  -- Prendre la course sans avoir touché « Reçu » vaut acceptation.
  perform set_config('bizzoo.livraison', 'oui', true);
  update public.commande_lignes l
     set etat = vers,
         recu_le = coalesce(l.recu_le, now())
   where l.commande_id = commande
     and l.boutique_id = boutique
     and l.livreur_id = moi
     and l.etat = depuis;
  -- Le compte AVANT de rendre le drapeau : « row_count » parle de la
  -- dernière instruction, et ce serait alors celle-là.
  get diagnostics combien = row_count;
  perform set_config('bizzoo.livraison', '', true);

  if combien = 0 then
    raise exception 'Rien à avancer ici : cette course n''en est pas là.';
  end if;
  return combien;
end $$;
revoke all on function public.avancer_livraison(text, text, text) from public, anon;
grant execute on function public.avancer_livraison(text, text, text) to authenticated;


drop policy if exists "lignes lecture client" on public.commande_lignes;
create policy "lignes lecture client" on public.commande_lignes
  for select to authenticated
  using (public.ma_commande(commande_id));

-- ---------- Et une règle ne ferme pas une COLONNE ----------
-- La règle ci-dessus décide quelles LIGNES un client voit. Elle les
-- rend alors ENTIÈRES — prix d'achat de la boutique compris. Or
-- « prix_bizzoo » est ce que la boutique a touché, et « taux_marge »
-- la part de l'enseigne : montrer l'un ou l'autre à l'acheteur, c'est
-- lui donner la marge faite sur ce qu'il vient de payer.
--
-- Avant les comptes clients, personne hors de l'équipe ne lisait cette
-- table et la question ne se posait pas. Depuis, il faut des droits par
-- colonne — le banc l'a trouvé en éprouvant l'historique.
--
-- L'enseigne ne perd rien : ses chiffres passent par
-- « statistiques_ventes() », qui s'exécute avec les droits de son
-- propriétaire et ignore ces restrictions.
revoke select on public.commande_lignes from authenticated;
grant select (
  id, commande_id, boutique_id, produit_id,
  nom, code, reference, prix, quantite, etat, cree_le, confirme_le
) on public.commande_lignes to authenticated;
revoke all on public.commande_lignes from anon;
-- L'équipe avance l'état de sa ligne, et rien d'autre : « ligne_verrous »
-- refuse déjà le reste, ceci le refuse une seconde fois.
--
-- LE RETRAIT D'ABORD, sans quoi la ligne suivante n'ajoute rien du
-- tout. Une base Supabase pose « alter default privileges … grant all
-- … to anon, authenticated » : chaque table du schéma public naît avec
-- TOUS les droits pour « authenticated », et un droit de colonne posé
-- par-dessus n'en retire aucun. C'est la même raison qui a imposé le
-- « revoke select » plus haut — on l'avait vue pour la lecture, on
-- l'avait manquée pour l'écriture.
revoke update on public.commande_lignes from authenticated;
grant update (etat) on public.commande_lignes to authenticated;

create policy "commandes suivi" on public.commandes
  for update to authenticated
  using (public.est_super()) with check (public.est_super());

-- ---------- Les règles de la maison ----------
-- Une seule ligne, comme « paiement » : ce que l'enseigne décide et qui
-- vaut pour toutes ses boutiques. Pour l'instant une seule règle y vit,
-- mais elle a sa table plutôt qu'une colonne de plus chez « paiement » :
-- exiger un compte n'a rien à voir avec l'argent, et le jour où une
-- deuxième règle arrive, elle saura où se poser.
create table if not exists public.reglages (
  id                 int primary key default 1 check (id = 1),
  -- Faux = on commande sans compte, comme depuis le premier jour.
  -- Vrai = plus une commande sans compte. LE JOUR OÙ ON LE MET, il faut
  -- qu'une porte d'inscription soit ouverte pour de bon — sinon on ferme
  -- la caisse à qui n'a aucun moyen d'entrer.
  compte_obligatoire boolean not null default false,
  maj_le             timestamptz not null default now()
);
-- Sur une base déjà en service, le corps ci-dessus n'est jamais relu.
alter table public.reglages
  add column if not exists compte_obligatoire boolean not null default false;
alter table public.reglages
  add column if not exists maj_le timestamptz not null default now();
insert into public.reglages (id) values (1) on conflict (id) do nothing;

alter table public.reglages enable row level security;
drop policy if exists "reglages lecture"  on public.reglages;
drop policy if exists "reglages ecriture" on public.reglages;

-- L'application doit CONNAÎTRE la règle avant de dessiner son bouton :
-- elle se lit donc sans compte. Il n'y a rien de secret là-dedans.
create policy "reglages lecture" on public.reglages
  for select to anon, authenticated using (true);
-- La changer ferme ou rouvre la caisse de toute l'enseigne : vous seul.
create policy "reglages ecriture" on public.reglages
  for update to authenticated
  using (public.est_super()) with check (public.est_super());

-- Ni « insert » ni « delete » pour personne : la ligne est unique et ne
-- doit pas pouvoir disparaître. Une table sans ligne répondrait « pas de
-- règle », et la porte se rouvrirait toute seule.
revoke all on public.reglages from anon, authenticated;
grant select on public.reglages to anon, authenticated;
-- « revoke all » puis « grant » par colonne, dans cet ordre : un droit
-- par colonne posé sur un droit de table déjà accordé ne retire rien.
grant update (compte_obligatoire, maj_le) on public.reglages to authenticated;

-- La règle, lue par la base elle-même. « security definer » parce que
-- « creer_commande » l'appelle pour un visiteur sans compte, et qu'on
-- préfère ne dépendre d'aucun droit de lecture au moment de décider.
--
-- Si la ligne manquait malgré tout, la réponse est « non ». Ce choix est
-- délibéré : la règle force une inscription, elle ne protège rien. Un
-- accident doit laisser la boutique vendre, pas verrouiller la caisse un
-- samedi soir sans personne pour la rouvrir.
create or replace function public.compte_exige() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select r.compte_obligatoire from public.reglages r where r.id = 1), false);
$$;
revoke all on function public.compte_exige() from public, anon, authenticated;
grant execute on function public.compte_exige() to anon, authenticated;

-- ---------- Passer commande ----------
-- Le téléphone envoie ses coordonnées et une liste
-- { produit_id, quantite }. Rien d'autre n'est écouté : ni prix,
-- ni total, ni état. La base répond avec le montant à payer, et
-- c'est CE montant qui part chez KkiaPay.
-- ---------- Les codes promo ----------
-- UNE REMISE SORT DE LA MARGE DE L'ENSEIGNE, jamais de la poche d'une
-- boutique. La boutique touche son prix BIZZOO en entier, comme si le
-- code n'existait pas : elle n'a pas décidé cette promotion, elle n'a
-- pas à la payer. C'est pour cela que la remise vit sur la COMMANDE et
-- jamais sur les lignes.
--
-- Et c'est pour cela qu'il y a UN PLAFOND, plus bas : une remise ne
-- descend jamais en dessous de ce que les boutiques doivent toucher.
-- Sans lui, un code de 50 % sur un article vendu avec 20 % de marge
-- ferait payer la différence à l'enseigne — sur chaque vente, sans que
-- personne s'en aperçoive avant de faire les comptes.
create table if not exists public.codes_promo (
  code     text primary key,
  libelle  text not null default '',
  mode     text not null default 'pourcent'
           check (mode in ('pourcent', 'montant')),
  valeur   numeric(10,2) not null default 0,
  -- Montant minimum de commande. Sans lui, « 20 % » s'applique aussi à
  -- un panier de 500 francs.
  minimum  bigint not null default 0,
  -- 0 = sans limite. Voir « utilisations » plus bas : ce sont les
  -- commandes PAYÉES qui comptent, pas les paniers abandonnés.
  maximum  int not null default 0,
  une_par_client boolean not null default true,
  fin      date,
  actif    boolean not null default true,
  cree_le  timestamptz not null default now(),
  cree_par text not null default ''
);

alter table public.codes_promo enable row level security;
drop policy if exists "codes lecture" on public.codes_promo;
-- L'enseigne seule voit la liste. Un client ne doit PAS pouvoir lire la
-- table : il y trouverait tous les codes en cours, y compris ceux qui
-- ne lui étaient pas destinés. Il passe par « verifier_code », qui
-- répond sur un code qu'il connaît déjà et ne révèle rien d'autre.
create policy "codes lecture" on public.codes_promo
  for select to authenticated using (public.est_super());
revoke all on public.codes_promo from anon, authenticated;
grant select on public.codes_promo to authenticated;

-- Un code se tape à la main, sur un téléphone : « rentree2026 »,
-- « Rentrée 2026 », « RENTREE-2026 » doivent désigner le même code.
create or replace function public.code_normalise(brut text) returns text
language sql immutable as $$
  select left(regexp_replace(upper(coalesce(brut, '')), '[^A-Z0-9]', '', 'g'), 24);
$$;

-- LA RÈGLE, EN UN SEUL ENDROIT. L'écran du panier l'appelle pour
-- annoncer la remise ; la caisse l'appelle pour l'appliquer. Deux
-- calculs séparés finiraient par diverger, et le client verrait un
-- montant puis en paierait un autre — c'est déjà la règle que suivent
-- « mes_prix » et « ligne_a_l_ecriture » pour les prix revendeur.
--
-- Rend un objet : { ok, remise, raison }. « raison » est écrite pour
-- être montrée telle quelle au client.
-- Le code d'un particulier : à qui il appartient, et ce qu'il lui rapporte.
alter table public.codes_promo add column if not exists parrain uuid;
alter table public.codes_promo add column if not exists commission numeric(5,2) not null default 0;

create or replace function public.remise_du_code(
  brut text, sous_total bigint, marge bigint,
  qui uuid default null, tel text default '')
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c       public.codes_promo%rowtype;
  cle     text := public.code_normalise(brut);
  brute   bigint;
  plafond bigint := greatest(0, coalesce(marge, 0));
  combien int;
  -- PAS « numero » : « commandes » a une colonne de ce nom, et
  -- PostgreSQL refuserait la requête plus bas — « column reference
  -- numero is ambiguous ».
  tel_net text := left(regexp_replace(coalesce(tel, ''), '\D', '', 'g'), 20);
  refus   constant text := 'Ce code n''existe pas, ou n''est plus valable.';
begin
  if cle = '' then
    return jsonb_build_object('ok', false, 'remise', 0, 'raison', refus);
  end if;
  -- UN REVENDEUR A DÉJÀ SA REMISE : il achète au prix BIZZOO, sur tout le
  -- catalogue. Un code s'y ajouterait, et sortirait une seconde fois de
  -- la même marge. La caisse passe alors la commande sans le code.
  if qui is not null and exists (select 1 from public.clients r
                                 where r.id = qui and r.revendeur_etat = 'validee') then
    return jsonb_build_object('ok', false, 'remise', 0,
      'raison', 'Votre compte revendeur achète déjà au prix BIZZOO : les codes promo ne s''y ajoutent pas.');
  end if;
  select * into c from public.codes_promo where code = cle;
  -- MÊME RÉPONSE pour « inconnu » et « fermé ». Distinguer les deux
  -- dirait à qui essaie des codes au hasard lesquels ont existé.
  if not found or not c.actif then
    return jsonb_build_object('ok', false, 'remise', 0, 'raison', refus);
  end if;
  if c.fin is not null and c.fin < current_date then
    return jsonb_build_object('ok', false, 'remise', 0,
      'raison', 'Ce code a expiré le ' || to_char(c.fin, 'DD/MM/YYYY') || '.');
  end if;
  if coalesce(sous_total, 0) < c.minimum then
    return jsonb_build_object('ok', false, 'remise', 0,
      'raison', 'Ce code s''applique à partir de ' || c.minimum::text || '.');
  end if;

  -- LES UTILISATIONS SE COMPTENT SUR LES COMMANDES PAYÉES. Compter les
  -- paniers déposés laisserait des commandes jamais réglées manger le
  -- quota, et refuserait le code à de vrais clients. Le risque inverse
  -- — quelques remises de plus si beaucoup paient en même temps — coûte
  -- bien moins cher qu'un client refusé à tort.
  if c.maximum > 0 then
    select count(*) into combien from public.commandes o
     where o.code_promo = cle and o.etat = 'payee';
    if combien >= c.maximum then
      return jsonb_build_object('ok', false, 'remise', 0,
        'raison', 'Ce code a atteint son nombre d''utilisations.');
    end if;
  end if;

  -- LE PROPRIÉTAIRE D'UN CODE NE S'EN SERT PAS : il toucherait une
  -- commission sur ses propres achats.
  if c.parrain is not null and qui is not null and qui = c.parrain then
    return jsonb_build_object('ok', false, 'remise', 0,
      'raison', 'C''est votre code : il sert à vos clients, pas à vous.');
  end if;

  -- « Une seule fois par client ». Un compte se reconnaît à son
  -- identifiant ; un visiteur sans compte, à son seul numéro — on le dit
  -- franchement plutôt que de laisser croire à une identification qui
  -- n'existe pas.
  if c.une_par_client and (qui is not null or tel_net <> '') then
    if exists (select 1 from public.commandes o
                where o.code_promo = cle and o.etat = 'payee'
                  and ((qui is not null and o.client_id = qui)
                       or (tel_net <> '' and o.client_tel = tel_net))) then
      return jsonb_build_object('ok', false, 'remise', 0,
        'raison', 'Vous avez déjà utilisé ce code.');
    end if;
  end if;

  brute := case when c.mode = 'montant' then round(c.valeur)::bigint
                else round(coalesce(sous_total, 0) * least(100, greatest(0, c.valeur)) / 100)::bigint end;
  brute := greatest(0, least(brute, greatest(0, coalesce(sous_total, 0))));

  -- LE PLAFOND. La boutique touche son prix BIZZOO en entier : la
  -- remise ne peut pas dépasser ce que l'enseigne gagne sur cette
  -- commande. On rabote sans rien dire de plus que le montant obtenu —
  -- la marge de l'enseigne ne regarde pas le client.
  if brute > plafond then brute := plafond; end if;

  -- UN CODE DE PARTICULIER VAUT MÊME SANS REMISE : il porte la commission
  -- de son propriétaire, et la commande doit le garder.
  if brute <= 0 and c.parrain is null then
    return jsonb_build_object('ok', false, 'remise', 0,
      'raison', 'Ce code ne s''applique pas à ce panier.');
  end if;
  return jsonb_build_object('ok', true, 'remise', brute, 'raison', '');
end $$;
revoke all on function public.remise_du_code(text, bigint, bigint, uuid, text)
  from public, anon, authenticated;

-- Ce que le panier demande AVANT de commander : « ce code vaut-il
-- quelque chose sur ce panier-ci ? ». Les prix et la marge se
-- recalculent ICI, depuis la base : le panier ne les envoie pas, et le
-- prix BIZZOO ne sort toujours pas.
create or replace function public.verifier_code(brut text, articles jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  article    jsonb;
  qte        int;
  p          public.produits%rowtype;
  pv         public.produits_prive%rowtype;
  b          public.boutiques%rowtype;
  revendeur  boolean := public.est_revendeur();
  prix       bigint;
  achat      bigint;
  sous_total bigint := 0;
  marge      bigint := 0;
  moi        uuid := auth.uid();
begin
  if articles is null or jsonb_typeof(articles) <> 'array' then
    return jsonb_build_object('ok', false, 'remise', 0, 'raison', 'Panier vide.');
  end if;
  for article in select * from jsonb_array_elements(articles) loop
    qte := greatest(1, least(99, coalesce((article ->> 'quantite')::int, 1)));
    select * into p from public.produits where id = article ->> 'produit_id';
    continue when not found;
    select * into pv from public.produits_prive where produit_id = p.id;
    select * into b  from public.boutiques where id = p.boutique_id;
    achat := greatest(0, coalesce(pv.prix_grossiste, 0));
    prix  := case when revendeur and achat > 0
                  then public.prix_revendeur(coalesce(p.prix, 0)::int, achat::int,
                         coalesce(pv.taux_revendeur, b.taux_revendeur, 0),
                         coalesce(b.revendeur_mode, 'bizzoo'))
                  else coalesce(p.prix, 0) end;
    sous_total := sous_total + prix * qte;
    -- Ce que l'enseigne garde sur cette ligne. C'est lui, et lui seul,
    -- qui borne la remise.
    marge := marge + greatest(0, prix - achat) * qte;
  end loop;
  return public.remise_du_code(brut, sous_total, marge, moi,
    coalesce((select c.tel from public.clients c where c.id = moi), ''));
end $$;
revoke all on function public.verifier_code(text, jsonb) from public;
grant execute on function public.verifier_code(text, jsonb) to anon, authenticated;

-- ---------- Tenir les codes, côté enseigne ----------
-- Ce que chaque code a réellement coûté, et à combien de clients. Les
-- deux se comptent sur les commandes PAYÉES : un panier abandonné n'a
-- rien coûté à personne.
create or replace function public.codes_promo_liste()
returns table (
  code text, libelle text, mode text, valeur numeric,
  minimum bigint, maximum int, une_par_client boolean,
  fin date, actif boolean, cree_le timestamptz, cree_par text,
  utilisations bigint, coute bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.est_super() then return; end if;
  return query
    select c.code, c.libelle, c.mode, c.valeur, c.minimum, c.maximum,
           c.une_par_client, c.fin, c.actif, c.cree_le, c.cree_par,
           coalesce(u.combien, 0), coalesce(u.total, 0)
      from public.codes_promo c
      left join (select o.code_promo, count(*)::bigint as combien,
                        sum(o.remise)::bigint as total
                   from public.commandes o
                  where o.etat = 'payee' and o.code_promo <> ''
                  group by o.code_promo) u on u.code_promo = c.code
     order by c.actif desc, c.cree_le desc;
end $$;
revoke all on function public.codes_promo_liste() from public, anon;
grant execute on function public.codes_promo_liste() to authenticated;

-- Poser un code, ou le corriger. Le code lui-même ne se change jamais :
-- c'est la clé, et des commandes le portent déjà. Pour en changer, on
-- ferme celui-ci et on en pose un autre.
create or replace function public.enregistrer_code(
  brut text, libelle text, mode text, valeur numeric,
  minimum bigint default 0, maximum int default 0,
  une_par_client boolean default true,
  fin date default null, actif boolean default true)
returns text
language plpgsql security definer set search_path = public as $$
declare
  cle text := public.code_normalise(brut);
  qui text;
begin
  if not public.est_super() then
    raise exception 'Seule l''enseigne pose un code promo';
  end if;
  if cle = '' then
    raise exception 'Un code ne peut pas être vide : lettres et chiffres seulement.';
  end if;
  if mode not in ('pourcent', 'montant') then
    raise exception 'Un code se calcule en pourcentage ou en montant.';
  end if;
  if coalesce(valeur, 0) <= 0 then
    raise exception 'Un code sans valeur ne retire rien.';
  end if;
  if mode = 'pourcent' and valeur > 100 then
    raise exception 'Une remise ne dépasse pas 100 %%.';
  end if;

  select coalesce(p.email, '') into qui from public.profils p where p.id = auth.uid();
  insert into public.codes_promo
    (code, libelle, mode, valeur, minimum, maximum, une_par_client, fin, actif, cree_par)
  values (cle, left(coalesce(libelle, ''), 120), mode, valeur,
          greatest(0, coalesce(minimum, 0)), greatest(0, coalesce(maximum, 0)),
          coalesce(une_par_client, true), fin, coalesce(actif, true),
          coalesce(qui, 'enseigne'))
  on conflict (code) do update
     set libelle = excluded.libelle, mode = excluded.mode,
         valeur = excluded.valeur, minimum = excluded.minimum,
         maximum = excluded.maximum, une_par_client = excluded.une_par_client,
         fin = excluded.fin, actif = excluded.actif;
  return cle;
end $$;
revoke all on function public.enregistrer_code(text, text, text, numeric, bigint, int, boolean, date, boolean)
  from public, anon;
grant execute on function public.enregistrer_code(text, text, text, numeric, bigint, int, boolean, date, boolean)
  to authenticated;

-- ---------- Ce que les remises coûtent à l'enseigne ----------
-- LE PIÈGE QUE CETTE FONCTION FERME. « statistiques_ventes » calcule le
-- bénéfice LIGNE PAR LIGNE : prix de vente moins prix BIZZOO. Mais la
-- remise est sur la COMMANDE, pas sur les lignes — elle n'y apparaît
-- donc nulle part, et le bénéfice affiché serait surévalué de toutes
-- les remises accordées. Sur un mois de promotions, l'écart se compte
-- en dizaines de milliers.
--
-- La remise se répartit AU PRORATA de ce que chaque boutique pèse dans
-- la commande : c'est sur sa part de marge que l'enseigne a rogné.
create or replace function public.remises_periode(
  depuis date default null,
  jusqu  date default null,
  boutique text default null)
returns table (boutique_id text, remise bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.est_super() then return; end if;
  return query
    with payees as (
      select o.id, o.remise
        from public.commandes o
       where o.etat = 'payee' and coalesce(o.remise, 0) > 0
         and (depuis is null or o.paye_le >= depuis::timestamptz)
         and (jusqu  is null or o.paye_le <  (jusqu + 1)::timestamptz)
    ), parts as (
      select p.id as commande, p.remise as remise,
             l.boutique_id as bq,
             sum(l.prix * l.quantite)::numeric as part
        from payees p
        join public.commande_lignes l on l.commande_id = p.id
       group by p.id, p.remise, l.boutique_id
    ), entiers as (
      select parts.commande, sum(parts.part) as entier
        from parts group by parts.commande
    )
    select parts.bq,
           round(sum(parts.remise * parts.part / nullif(e.entier, 0)))::bigint
      from parts join entiers e on e.commande = parts.commande
     where boutique is null or parts.bq = boutique
     group by parts.bq;
end $$;
revoke all on function public.remises_periode(date, date, text) from public, anon;
grant execute on function public.remises_periode(date, date, text) to authenticated;

-- « drop » avant « create » : cette fonction a gagné des paramètres — le
-- code promo, puis l'acompte. Un paramètre par défaut n'en remplace pas
-- une, il en crée une seconde, et l'appel devient ambigu : « function is
-- not unique ».
drop function if exists public.creer_commande(jsonb, jsonb);
drop function if exists public.creer_commande(jsonb, jsonb, text);
drop function if exists public.creer_commande(jsonb, jsonb, text, boolean);
-- (3.64.0) Et « destination », la position du client : sans le retrait de
-- la signature à cinq paramètres, l'appel d'une application d'avant
-- deviendrait ambigu. Avec, il trouve celle-ci, « destination » à null.
drop function if exists public.creer_commande(jsonb, jsonb, text, boolean, boolean);
create or replace function public.creer_commande(
  client jsonb, articles jsonb, code text default '',
  avec_acompte boolean default false, avec_frais boolean default false,
  destination jsonb default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  -- (3.64.0) La livraison au kilomètre : en service dès que le point
  -- BIZZOO est réglé.
  au_km    boolean := public.livraison_active();
  devis    jsonb;
  frais_km bigint := 0;
  nouvelle text := 'cmd_' || replace(gen_random_uuid()::text, '-', '');
  article  jsonb;
  qte      int;
  p        public.produits%rowtype;
  devises  text[];
  sortie   jsonb;
  moi      uuid := auth.uid();
  equipe   boolean := false;   -- connecté, mais pas avec un compte client
  sous_total bigint;
  marge    bigint;
  verdict  jsonb;
  manque   record;
  taux     int;
  les_parts jsonb;
  manquant  bigint;
  -- (3.68.0) Les frais SAISIS par l'équipe pour une commande prise sur
  -- WhatsApp (« faire_livrer ») : ils remplacent le calcul à la distance.
  -- Les deux drapeaux ne s'attrapent pas depuis PostgREST.
  saisis   bigint := case when coalesce(current_setting('bizzoo.hors_appli', true), '') = 'oui'
                          then nullif(current_setting('bizzoo.frais_saisis', true), '')::bigint end;
  vehic    text;
begin
  -- Des frais saisis valent une livraison « au kilomètre » sans kilomètre :
  -- un seul frais pour la commande, un seul livreur, payé en ligne — et le
  -- livreur en touche sa part comme d'habitude.
  if saisis is not null then au_km := true; end if;
  if articles is null or jsonb_typeof(articles) <> 'array'
     or jsonb_array_length(articles) = 0 then
    raise exception 'Votre panier est vide.';
  end if;
  if jsonb_array_length(articles) > 40 then
    raise exception 'Un panier ne peut pas dépasser 40 articles différents.';
  end if;
  if coalesce(trim(client ->> 'tel'), '') = '' then
    raise exception 'Un numéro de téléphone est nécessaire pour vous joindre.';
  end if;
  -- (3.64.0) LA POSITION DU CLIENT EST OBLIGATOIRE quand la livraison se
  -- compte au kilomètre : sans elle, pas de distance, donc pas de frais.
  -- Une application d'avant ne l'envoie pas — on lui dit quoi faire.
  if au_km and saisis is null then
    if destination is null or jsonb_typeof(destination) <> 'object'
       or (destination ->> 'latitude') is null or (destination ->> 'longitude') is null then
      if coalesce(avec_frais, false) and destination is null then
        raise exception 'Mettez BIZZOO à jour pour commander : les frais de livraison se calculent désormais selon votre position.'
          using errcode = 'P0001';
      end if;
      raise exception 'Indiquez où livrer : touchez « Utiliser ma position ».' using errcode = 'P0001';
    end if;
  end if;

  -- Un compte de l'équipe ne passe pas commande pour lui-même : il agirait
  -- avec les droits d'une boutique sur une commande qui lui appartient.
  --
  -- (3.63.0) UN COMPTE SANS FICHE N'EST PAS UN COMPTE D'ÉQUIPE. Avant,
  -- tout compte connecté sans ligne « clients » était ramené à
  -- « personne » : la commande naissait sans compte, et son auteur ne la
  -- retrouvait nulle part — ni étapes, ni livreur, ni « J'ai bien
  -- reçu ». La fiche manque pourtant pour de bonnes raisons (un compte
  -- créé hors de l'application, une écriture retardée) : on la pose ici,
  -- avec ce que le client vient de donner, et la commande reste la
  -- sienne. Seul un VRAI compte d'équipe est écarté — une fiche d'équipe
  -- EN ATTENTE ne vaut aucun droit, et « compte_unique » l'efface en
  -- posant la fiche client, comme le fait l'application.
  if moi is not null and not exists (select 1 from public.clients c where c.id = moi) then
    -- (« eq », pas « p » : « p » est déjà la variable de la boucle des
    -- produits, et PostgreSQL ne saurait pas lequel des deux on désigne.)
    if exists (select 1 from public.profils eq
                where eq.id = moi and (eq.actif or eq.role <> 'moderateur')) then
      moi    := null;
      equipe := true;
    else
      begin
        insert into public.clients (id, nom, tel, indicatif, adresse)
        values (moi,
                left(coalesce(trim(client ->> 'nom'), ''), 120),
                left(regexp_replace(coalesce(client ->> 'tel', ''), '\D', '', 'g'), 20),
                left(coalesce(nullif(trim(client ->> 'indicatif'), ''), '229'), 6),
                left(coalesce(trim(client ->> 'adresse'), ''), 300))
        on conflict (id) do nothing;
      exception when others then
        -- Un verrou a refusé la fiche (un compte d'équipe apparu entre-temps,
        -- par exemple) : la commande part sans compte, comme avant — mais
        -- elle part.
        moi    := null;
        equipe := true;
      end;
    end if;
  end if;

  -- ---------- Le compte, quand l'enseigne l'exige ----------
  -- Tant que l'interrupteur est éteint, rien ne change : on commande sans
  -- compte, comme depuis le premier jour. Allumé, c'est ICI que la porte
  -- se ferme — dans la base, pas à l'écran. Un écran qui cache un bouton
  -- ne ferme rien : il suffit d'appeler la fonction directement.
  --
  -- Deux refus, parce que ce ne sont pas deux mêmes situations. Le
  -- visiteur n'a pas de compte : on lui dit d'en ouvrir un. Le vendeur en
  -- a un — mais c'est un compte de l'équipe, et on vient de le ramener à
  -- « personne » deux lignes plus haut. Lui répondre « connectez-vous »
  -- alors qu'il EST connecté lui ferait chercher longtemps.
  -- (3.68.0) Une commande prise sur WhatsApp, que l'équipe saisit pour le
  -- client (« faire_livrer ») : le client n'est pas là pour se connecter.
  -- Le drapeau ne s'attrape pas depuis PostgREST — seule « faire_livrer »,
  -- qui vérifie qui l'appelle, le pose.
  if moi is null and public.compte_exige()
     and coalesce(current_setting('bizzoo.hors_appli', true), '') <> 'oui' then
    if equipe then
      raise exception 'Ce compte est un compte de l''équipe BIZZOO, pas un compte client. Pour commander, ouvrez un compte client et connectez-vous avec.';
    end if;
    raise exception 'Il faut un compte BIZZOO pour commander. Sa création prend une minute, et c''est lui qui vous rendra cette commande depuis n''importe quel téléphone.';
  end if;

  perform set_config('bizzoo.interne', 'oui', true);

  insert into public.commandes
    (id, client_id, client_nom, client_tel, client_indicatif, client_adresse, note)
  values (
    nouvelle,
    moi,
    left(coalesce(trim(client ->> 'nom'), ''), 120),
    left(regexp_replace(coalesce(client ->> 'tel', ''), '\D', '', 'g'), 20),
    left(coalesce(nullif(trim(client ->> 'indicatif'), ''), '229'), 6),
    left(coalesce(trim(client ->> 'adresse'), ''), 300),
    left(coalesce(trim(client ->> 'note'), ''), 500));

  -- ---------- Les frais de livraison ----------
  -- AVANT les lignes : chaque ligne posée recalcule le total, qui les
  -- compte. Le montant est celui des réglages du jour, figé sur la
  -- commande.
  --
  -- UNE APPLICATION D'AVANT NE LES DEMANDE PAS, et n'en paie donc pas :
  -- elle ne saurait pas les montrer, et le client paierait un montant
  -- qu'on ne lui a jamais annoncé.
  -- (Le drapeau « interne » est déjà posé pour l'insertion, plus haut.)
  -- (3.59.0) Ils se posent désormais APRÈS les lignes, boutique par
  -- boutique : voir « Les conditions de chaque boutique », plus bas.

  for article in select * from jsonb_array_elements(articles) loop
    qte := greatest(1, least(99, coalesce((article ->> 'quantite')::int, 1)));
    select * into p from public.produits where id = article ->> 'produit_id';
    if not found then
      raise exception 'Un des produits de votre panier n''existe plus.';
    end if;
    -- (3.59.0) Un produit masqué ne se commande plus.
    if coalesce(p.masque, false) then
      raise exception '« % » n''est plus disponible : retirez-le du panier.', p.nom;
    end if;
    if coalesce(p.stock, 0) <= 0 and not coalesce(p.sur_commande, false)
       and (p.appro_le is null or p.appro_le < current_date) then
      raise exception '« % » n''est plus disponible : retirez-le du panier.', p.nom;
    end if;
    -- UNE BOUTIQUE FERMÉE NE REÇOIT PAS DE COMMANDE (3.59.0) : fermée par
    -- son interrupteur, ou en dehors de ses heures d'ouverture.
    if exists (select 1 from public.boutiques b
                where b.id = p.boutique_id
                  and (not b.actif or not public.boutique_ouverte(b.ouvertures))) then
      raise exception 'La boutique « % » est fermée en ce moment : « % » se commandera à sa réouverture.',
        (select b.nom from public.boutiques b where b.id = p.boutique_id), p.nom
        using errcode = 'P0001';
    end if;
    devises := devises || coalesce(nullif((
      select b.devise from public.boutiques b where b.id = p.boutique_id), ''), 'FCFA');
    insert into public.commande_lignes (id, commande_id, produit_id, quantite)
    values ('lig_' || replace(gen_random_uuid()::text, '-', ''), nouvelle, p.id, qte);
  end loop;

  -- LA QUANTITÉ TIENT DANS LE STOCK. Refuser un produit à zéro ne
  -- suffisait pas : dix pièces demandées quand il en restait trois
  -- passaient, et la boutique découvrait après le paiement qu'elle ne
  -- pourrait pas servir. On compte PAR PRODUIT, pas par ligne : deux
  -- lignes du même article ne font pas deux stocks. Un produit « sur
  -- commande » ou en approvisionnement n'a pas de plafond — la boutique
  -- le fait venir, c'est ce qu'elle annonce.
  --
  -- Ce contrôle ne RÉSERVE rien : entre la commande et le paiement, un
  -- autre client peut prendre les dernières pièces. C'est le paiement
  -- qui décompte, et il sait quoi faire s'il n'en reste plus assez
  -- (« commande_stock », plus bas).
  -- « pr » et non « p » : « p » est déjà la variable de la boucle, et
  -- PostgreSQL ne saurait pas lequel des deux on désigne.
  select pr.nom, greatest(coalesce(pr.stock, 0), 0) as reste
    into manque
    from public.commande_lignes l
    join public.produits pr on pr.id = l.produit_id
   where l.commande_id = nouvelle
     and not coalesce(pr.sur_commande, false)
     and (pr.appro_le is null or pr.appro_le < current_date)
   group by pr.id, pr.nom, pr.stock
  having sum(l.quantite) > greatest(coalesce(pr.stock, 0), 0)
   order by pr.nom
   limit 1;
  if found then
    raise exception 'Plus que % en stock pour « % » : réduisez la quantité dans votre panier.',
      manque.reste, manque.nom;
  end if;

  if (select count(distinct d) from unnest(devises) d) > 1 then
    raise exception 'Ces produits ne se paient pas dans la même monnaie : commandez boutique par boutique.';
  end if;
  update public.commandes set devise = coalesce(devises[1], 'FCFA') where id = nouvelle;

  -- ---------- Le code promo ----------
  -- APRÈS les lignes, et c'est obligatoire : la remise est bornée par la
  -- marge de l'enseigne, qui ne se connaît qu'une fois les prix et les
  -- prix BIZZOO figés sur les lignes. La calculer avant reviendrait à la
  -- deviner.
  --
  -- Un code refusé ne fait PAS échouer la commande : le panier est bon,
  -- c'est le code qui ne vaut rien. Refuser la vente parce qu'une
  -- promotion a expiré serait perdre un client pour une ristourne.
  if coalesce(trim(code), '') <> '' then
    select coalesce(sum(l.prix * l.quantite), 0),
           coalesce(sum(greatest(0, l.prix - l.prix_bizzoo) * l.quantite), 0)
      into sous_total, marge
      from public.commande_lignes l where l.commande_id = nouvelle;

    verdict := public.remise_du_code(code, sous_total, marge, moi,
      left(regexp_replace(coalesce(client ->> 'tel', ''), '\D', '', 'g'), 20));

    if (verdict ->> 'ok')::boolean then
      perform set_config('bizzoo.interne', 'oui', true);
      update public.commandes
         set code_promo = public.code_normalise(code),
             remise = (verdict ->> 'remise')::bigint
       where id = nouvelle;
      perform set_config('bizzoo.interne', '', true);
      -- Le total suit la remise. Même fonction que le déclencheur des
      -- lignes : une seule règle, un seul endroit.
      perform public.commande_total(nouvelle);
    end if;
  end if;

  -- ---------- L'acompte ----------
  -- APRÈS le code promo : l'acompte se prend sur ce que le client doit
  -- vraiment, remise déduite. Le taux est celui du jour, figé sur la
  -- commande.
  --
  -- UNE APPLICATION D'AVANT NE DEMANDE RIEN. Elle fait payer le total et
  -- dit « Payée » une fois le versement reçu : sa commande se règle donc
  -- en entier, comme elle l'annonce au client. Lui faire payer un acompte
  -- sans qu'elle sache le dire laisserait croire au client qu'il ne doit
  -- plus rien, et le livreur arriverait avec une somme à réclamer.
  --
  -- 100 francs au moins, l'encaissement minimum chez FeexPay, et jamais
  -- plus que le total.
  -- ---------- Les conditions de chaque boutique (3.59.0) ----------
  -- CHAQUE BOUTIQUE A SES FRAIS ET SON ACOMPTE. Sa part, c'est ce que
  -- valent ses articles, remise déduite au prorata, plus ses frais ;
  -- elle se paie en entier à la commande (« total ») ou par son taux
  -- d'acompte — le reste à la livraison, à son livreur.
  --
  -- UNE APPLICATION D'AVANT ne demande ni frais ni acompte : elle fait
  -- tout payer, et n'a pas de frais à annoncer. On ne change rien pour
  -- elle.
  -- ---------- La livraison au kilomètre (3.64.0) ----------
  -- UN SEUL FRAIS POUR LA COMMANDE, du point BIZZOO jusqu'au client, au
  -- tarif du véhicule : le tricycle dès qu'UN produit l'exige. Les frais
  -- de chaque boutique ne comptent plus. Ils se paient EN LIGNE, avec
  -- l'acompte : c'est BIZZOO qui les détient, et qui en doit sa part au
  -- livreur (« gains_livreurs »).
  if au_km then
    vehic := case when exists (select 1 from public.commande_lignes l
                                 join public.produits pr on pr.id = l.produit_id
                                where l.commande_id = nouvelle and pr.vehicule = 'tricycle')
                  then 'tricycle' else 'moto' end;
    if saisis is not null then
      -- (3.68.0) Les frais décidés par qui a pris la commande ; la position,
      -- si on l'a, pour que le livreur trouve le client.
      devis := jsonb_build_object('vehicule', vehic, 'distance_km', null, 'frais', greatest(0, saisis),
                 'saisie', true) ||
               case when destination is not null and jsonb_typeof(destination) = 'object'
                         and (destination ->> 'latitude') is not null and (destination ->> 'longitude') is not null
                    then jsonb_build_object('destination', jsonb_build_object(
                           'latitude', round((destination ->> 'latitude')::numeric, 6),
                           'longitude', round((destination ->> 'longitude')::numeric, 6)))
                    else '{}'::jsonb end;
    else
      devis := public.devis_livraison(
        (destination ->> 'latitude')::double precision,
        (destination ->> 'longitude')::double precision, vehic);
    end if;
    frais_km := coalesce((devis ->> 'frais')::bigint, 0);
    perform set_config('bizzoo.interne', 'oui', true);
    update public.commandes set frais_livraison = frais_km, livraison = devis where id = nouvelle;
    perform public.commande_total(nouvelle);
    perform set_config('bizzoo.interne', '', true);
  end if;

  if au_km or coalesce(avec_acompte, false) or coalesce(avec_frais, false) then
    perform set_config('bizzoo.interne', 'oui', true);
    if coalesce(avec_frais, false) and not au_km then
      update public.commandes
         set frais_livraison = coalesce((
               select sum(greatest(0, b.frais_livraison))
                 from public.boutiques b
                where b.id in (select l.boutique_id from public.commande_lignes l
                                where l.commande_id = nouvelle)), 0)
       where id = nouvelle;
      perform public.commande_total(nouvelle);
      perform set_config('bizzoo.interne', 'oui', true);
    end if;
    with brut as (
      select l.boutique_id as bou, sum(l.prix * l.quantite)::numeric as montant
        from public.commande_lignes l
       where l.commande_id = nouvelle
       group by l.boutique_id
    ), tout as (
      select sum(montant) as s from brut
    ), chacune as (
      select br.bou,
             -- Au kilomètre, la part d'une boutique n'a plus de frais : ceux
             -- de la commande s'ajoutent à part, plus bas.
             case when coalesce(avec_frais, false) and not au_km
                  then greatest(0, b.frais_livraison) else 0 end as frais,
             case when coalesce(avec_acompte, false) and b.mode_paiement = 'acompte'
                  then b.taux_acompte else 100 end as taux,
             greatest(0, round(br.montant - coalesce(c.remise, 0) * br.montant / nullif(t.s, 0))) as net
        from brut br
        join public.boutiques b on b.id = br.bou
        cross join tout t
        cross join (select remise from public.commandes where id = nouvelle) c
    )
    select jsonb_object_agg(x.bou, jsonb_build_object(
             'frais', x.frais, 'taux', x.taux, 'du', x.net + x.frais,
             'acompte', least(x.net + x.frais, ceil((x.net + x.frais) * x.taux / 100.0)::bigint)))
      into les_parts
      from chacune x;

    -- 100 francs au moins en ligne, l'encaissement minimum chez FeexPay :
    -- le manque va à la plus grosse part.
    select greatest(0, least(c.total, 100) - coalesce((
             select sum((v ->> 'acompte')::bigint) from jsonb_each(les_parts) e(k, v)), 0) - frais_km)
      into manquant
      from public.commandes c where c.id = nouvelle;
    if manquant > 0 and les_parts is not null then
      select jsonb_set(les_parts, array[k, 'acompte'],
               to_jsonb(least((v ->> 'du')::bigint, (v ->> 'acompte')::bigint + manquant)))
        into les_parts
        from jsonb_each(les_parts) e(k, v)
       order by (v ->> 'du')::bigint desc limit 1;
    end if;

    -- (3.64.0) Au kilomètre, l'acompte, c'est celui des boutiques PLUS les
    -- frais de livraison, payés en entier en ligne.
    update public.commandes c
       set parts = les_parts,
           acompte = least(c.total, coalesce((
                       select sum((v ->> 'acompte')::bigint) from jsonb_each(les_parts) e(k, v)), c.total)
                       + frais_km),
           -- Le taux affiché : ce que représente l'acompte du total.
           taux_acompte = case when c.total <= 0 then 100
                               else least(100, greatest(1, round(100.0 * least(c.total, coalesce((
                                 select sum((v ->> 'acompte')::bigint) from jsonb_each(les_parts) e(k, v)),
                                 c.total) + frais_km) / c.total)))::int end
     where c.id = nouvelle;
    perform set_config('bizzoo.interne', '', true);
  else
    perform set_config('bizzoo.interne', 'oui', true);
    update public.commandes c
       set taux_acompte = 100,
           acompte = c.total
     where c.id = nouvelle;
    perform set_config('bizzoo.interne', '', true);
  end if;

  select jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'total', c.total, 'devise', c.devise,
    'etat', c.etat,
    /* Ce que le code a retiré, et lequel. Le récapitulatif doit pouvoir
       le dire : un client qui a tapé un code et ne le voit nulle part
       croit qu'il n'a pas été pris. */
    'code_promo', c.code_promo, 'remise', c.remise,
    /* Les frais de livraison, à part : le récapitulatif les montre sur
       leur propre ligne. */
    'frais_livraison', c.frais_livraison,
    /* (3.64.0) Le véhicule, la distance, les kilomètres facturés. */
    'livraison', c.livraison,
    /* Ce qui se paie maintenant, et ce qui restera pour la livraison. */
    'taux_acompte', c.taux_acompte, 'acompte', c.acompte,
    'reste', greatest(0, c.total - c.acompte),
    'parts', c.parts,
    'boutiques', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', g.boutique_id,
               'nom', coalesce((select b.nom from public.boutiques b where b.id = g.boutique_id), ''),
               'whatsapp', coalesce((select b.whatsapp from public.boutiques b where b.id = g.boutique_id), ''),
               'indicatif', coalesce((select b.indicatif from public.boutiques b where b.id = g.boutique_id), '229'),
               'montant', g.montant,
               /* Ce que CETTE boutique encaissera à la livraison. */
               'a_encaisser', coalesce((select r.a_encaisser
                                          from public.restes_par_boutique(c.id) r
                                         where r.boutique_id is not distinct from g.boutique_id), 0),
               'lignes', g.lignes) order by g.montant desc)
        from (select l.boutique_id,
                     sum(l.prix * l.quantite) as montant,
                     jsonb_agg(jsonb_build_object('nom', l.nom, 'code', l.code,
                       'reference', l.reference, 'prix', l.prix,
                       /* L'identifiant du produit voyage avec la ligne :
                          c'est par lui que le SAV désignera l'article
                          qui pose problème. Le prix BIZZOO, lui, ne sort
                          toujours pas. */
                       'produit_id', l.produit_id,
                       'quantite', l.quantite) order by l.nom) as lignes
                from public.commande_lignes l
               where l.commande_id = c.id
               group by l.boutique_id) g), '[]'::jsonb))
    into sortie
    from public.commandes c where c.id = nouvelle;
  return sortie;
end $$;

revoke all on function public.creer_commande(jsonb, jsonb, text, boolean, boolean, jsonb) from public;
grant execute on function public.creer_commande(jsonb, jsonb, text, boolean, boolean, jsonb) to anon, authenticated;

-- ---------- Suivre sa commande ----------
-- Après le paiement, l'application ATTEND que l'état bouge, elle ne
-- l'annonce pas : il s'écoule quelques secondes entre la confirmation
-- chez KkiaPay et l'arrivée de sa notification. Il faut connaître à la
-- fois le numéro interne de la commande — 32 caractères tirés au sort —
-- et le numéro de téléphone qui l'a passée.
create or replace function public.suivre_commande(cible text, tel text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.commandes%rowtype;
begin
  select * into c from public.commandes
   where id = cible
     and not compte_supprime
     and client_tel = regexp_replace(coalesce(tel, ''), '\D', '', 'g');
  if not found then return null; end if;
  return jsonb_build_object(
    'numero', c.numero, 'etat', c.etat, 'total', c.total, 'devise', c.devise,
    'paye_le', c.paye_le, 'remarque', c.remarque,
    'frais_livraison', c.frais_livraison,
    -- (3.64.0) Le véhicule et la distance de la livraison.
    'livraison', c.livraison,
    -- L'acompte, ce qui a été versé, et ce qui reste à payer à la
    -- livraison, boutique par boutique. Une commande d'avant l'acompte
    -- se payait en entier : son acompte est son total.
    'taux_acompte', coalesce(c.taux_acompte, 100),
    'acompte', coalesce(c.acompte, c.total),
    'verse', c.verse,
    'reste', (select coalesce(sum(r.a_encaisser), 0)
                from public.restes_par_boutique(c.id) r),
    'restes', (select coalesce(jsonb_object_agg(r.boutique_id, r.a_encaisser), '{}'::jsonb)
                 from public.restes_par_boutique(c.id) r
                where r.boutique_id is not null),
    -- (3.59.0) Ce que le client a payé au livreur, boutique par boutique,
    -- d'après la déclaration du livreur — et s'il l'a contesté.
    'encaissements', (select coalesce(jsonb_object_agg(x.boutique_id, jsonb_build_object(
                         'montant', x.montant, 'mode', x.mode, 'encaisse_le', x.encaisse_le,
                         'livreur', coalesce(nullif(p.nom, ''), ''),
                         'conteste', x.conteste_le is not null)), '{}'::jsonb)
                        from public.encaissements x
                        left join public.profils p on p.id = x.livreur_id
                       where x.commande_id = c.id),
    'paye_livraison', (select coalesce(sum(x.montant), 0) from public.encaissements x
                        where x.commande_id = c.id),
    -- (3.63.0) OÙ EN EST CHAQUE BOUTIQUE, pour qui suit sa commande par
    -- son numéro : l'étape la MOINS avancée de ses lignes (une ligne
    -- annulée ne retient rien), et si le client a tout confirmé. Sans
    -- compte, c'était le seul morceau du suivi qui manquait — les lignes
    -- ne se lisent qu'avec un compte. La même règle que l'application
    -- applique aux commandes d'un compte.
    'etats', (select coalesce(jsonb_object_agg(e.boutique_id,
                       jsonb_build_object('etat', e.etat, 'confirme', e.confirme)), '{}'::jsonb)
                from (select l.boutique_id,
                             (array_agg(l.etat order by array_position(
                                array['nouvelle', 'vue', 'preparee', 'en_livraison', 'remise',
                                      'annulee'], l.etat)))[1] as etat,
                             bool_and(l.confirme_le is not null) as confirme
                        from public.commande_lignes l
                       where l.commande_id = c.id
                       group by l.boutique_id) e));
end $$;
revoke all on function public.suivre_commande(text, text) from public;
grant execute on function public.suivre_commande(text, text) to anon, authenticated;

-- Le téléphone dit « KkiaPay m'a répondu ceci ». On le NOTE — la
-- boutique saura quoi chercher dans son tableau de bord si la
-- notification se perd — mais on ne le croit pas : l'état ne bouge pas
-- d'un pouce. C'est toute la différence entre un indice et une preuve.
create or replace function public.signaler_transaction(cible text, transaction text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  -- C'est la base qui écrit, au nom d'un client qui n'est pas connecté :
  -- le verrou de « commandes » doit la reconnaître, sinon l'indice se
  -- perdrait en silence et la boutique n'aurait rien à chercher.
  perform set_config('bizzoo.interne', 'oui', true);
  update public.commandes
     set transaction_annoncee =
           left(regexp_replace(coalesce(transaction, ''), '[^A-Za-z0-9_-]', '', 'g'), 64),
         annonce_le = now()
   where id = cible and etat = 'a_payer' and transaction_annoncee = ''
     and coalesce(transaction, '') <> '';
end $$;
revoke all on function public.signaler_transaction(text, text) from public;
grant execute on function public.signaler_transaction(text, text) to anon, authenticated;

-- ---------- Encaisser — réservé au serveur ----------
-- Appelée UNIQUEMENT par la fonction Edge « kkiapay-webhook », qui
-- vérifie d'abord la signature de KkiaPay et se sert de la clé
-- service_role. Aucune application ne peut l'appeler : voir la
-- révocation juste après, et la vérification en fin de fichier.
--
-- Idempotente : KkiaPay réessaie cinq fois tant qu'il n'a pas reçu un
-- 200. Rejouer la même transaction ne fait rien de plus.
-- « drop » avant « create » : cette fonction a gagné un paramètre —
-- l'agrégateur qui notifie — pour le journal des versements. Un
-- paramètre par défaut ne remplace pas l'ancienne signature, il en crée
-- une seconde, et l'appel devient ambigu : « function is not unique ».
-- Sans ce retrait, chaque encaissement échouerait.
drop function if exists public.marquer_payee(text, text, int);
create or replace function public.marquer_payee(
  reference text, transaction text, montant int, qui text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c   public.commandes%rowtype;
  net text := left(regexp_replace(coalesce(transaction, ''), '[^A-Za-z0-9_-]', '', 'g'), 64);
  du  int;
begin
  if net = '' then return jsonb_build_object('ok', false, 'raison', 'transaction absente'); end if;

  -- On ne retrouve la commande QUE par la référence que nous avons
  -- nous-mêmes confiée à KkiaPay en ouvrant le paiement. Se rabattre sur
  -- la transaction annoncée par un téléphone laisserait le client
  -- choisir quel versement valide quelle commande — un versement de
  -- 100 000 réglant une commande de 100 francs. Sans référence, c'est la
  -- boutique qui tranche, à la main (confirmer_paiement), avec sous les
  -- yeux la transaction annoncée.
  select * into c from public.commandes where id = coalesce(reference, '');
  if not found then
    -- Un paiement qui ne nous concerne pas n'est pas une erreur. Mais il
    -- se note : un versement qui ne trouve pas sa commande est
    -- exactement ce qu'on veut voir au journal.
    perform public.noter_versement(null, 'inconnue', qui, '', coalesce(reference, ''),
      net, 0, coalesce(montant, 0),
      'Versement reçu pour une commande introuvable.');
    return jsonb_build_object('ok', true, 'raison', 'commande inconnue');
  end if;

  if c.etat = 'payee' then
    return jsonb_build_object('ok', true, 'deja', true, 'numero', c.numero);
  end if;

  -- CE QUI EST ATTENDU EN LIGNE, c'est l'acompte : le reste se paie à la
  -- livraison. Une commande d'avant l'acompte se payait en entier.
  du := coalesce(c.acompte, c.total);

  perform set_config('bizzoo.paiement', 'oui', true);

  -- Cette transaction est déjà rattachée à une autre commande. On le
  -- NOTE au lieu de lever une erreur : une erreur ferait réessayer
  -- KkiaPay cinq fois pour rien, et l'encaissement resterait bloqué.
  if exists (select 1 from public.commandes a
              where a.transaction_id = net and a.id <> c.id) then
    update public.commandes
       set remarque = 'Transaction ' || net || ' déjà rattachée à une autre commande.'
     where id = c.id;
    -- L'agrégateur et l'opérateur se reprennent tout seuls sur la ligne
    -- d'ouverture : c'est « noter_versement » qui s'en charge.
    perform public.noter_versement(c.id, 'conflit', qui, '',
      c.fournisseur_ref, net, du, coalesce(montant, 0),
      'Transaction déjà rattachée à une autre commande.');
    return jsonb_build_object('ok', true, 'conflit', true, 'numero', c.numero);
  end if;

  -- Le montant qui compte est celui que l'agrégateur annonce. S'il manque
  -- quelque chose, on ne valide pas : on écrit ce qu'on a reçu, et la
  -- boutique tranche. La preuve, elle, n'est pas posée : la commande
  -- n'est pas payée.
  if coalesce(montant, 0) < du then
    update public.commandes
       set remarque = 'Paiement incomplet : ' || coalesce(montant, 0)::text
                      || ' reçus sur ' || du::text || ' attendus'
                      || ' (transaction ' || net || ').'
     where id = c.id;
    perform public.noter_versement(c.id, 'incomplete', qui, '',
      c.fournisseur_ref, net, du, coalesce(montant, 0),
      'Reçu ' || coalesce(montant, 0)::text || ' sur ' || du::text || ' attendus.');
    return jsonb_build_object('ok', true, 'incomplet', true, 'numero', c.numero);
  end if;

  -- « verse » garde ce qui est RÉELLEMENT entré : c'est de lui que se
  -- déduit ce que le livreur réclamera. Un client qui a tout payé en
  -- ligne ne doit plus rien à la porte.
  update public.commandes
     set etat = 'payee', paye_le = now(), transaction_id = net,
         confirme_par = '', remarque = '', verse = coalesce(montant, 0)
   where id = c.id;
  -- La remarque vient d'être effacée sur la commande : c'est le journal,
  -- désormais, qui garde ce qui s'est passé avant cette réussite.
  perform public.noter_versement(c.id, 'payee', qui, '',
    c.fournisseur_ref, net, du, coalesce(montant, 0),
    case when du < c.total then 'Acompte encaissé.' else 'Versement encaissé.' end);
  return jsonb_build_object('ok', true, 'numero', c.numero, 'total', c.total,
                            'verse', coalesce(montant, 0));
end $$;

-- LE POINT À NE PAS MANQUER : révoquer du seul pseudo-rôle « public »
-- ne suffit pas. Supabase accorde d'office EXECUTE à « anon » et
-- « authenticated » sur toute fonction du schéma public. Sans ces deux
-- lignes, quiconque extrait la clé publiable de l'APK — et elle y est,
-- par construction — validerait ses commandes sans payer.
revoke all on function public.marquer_payee(text, text, int, text)
  from public, anon, authenticated;

-- ---------- Le journal des versements ----------
-- La commande ne garde que son ÉTAT ACTUEL : payée ou non. Ce qui s'est
-- passé en route — une demande partie sur un mauvais numéro, un versement
-- incomplet, un client qui s'y reprend à trois fois — n'était noté nulle
-- part. Pire : « marquer_payee » efface la remarque en réussissant, si
-- bien qu'un encaissement effaçait la trace de ses propres échecs.
--
-- D'où ce journal. UNE LIGNE PAR TENTATIVE, jamais modifiée ensuite :
-- c'est ce qui permet de répondre à « combien d'échecs cette semaine »
-- et « chez quel opérateur ». Un journal qu'on met à jour ne garde que
-- la fin de l'histoire, et la fin de l'histoire est déjà sur la commande.
--
-- PAS DE CLÉ ÉTRANGÈRE vers « commandes », et c'est voulu : effacer une
-- commande ne doit pas effacer la trace de l'argent. Le numéro est donc
-- recopié ici, figé, pour que la ligne se lise encore toute seule.
create table if not exists public.versements (
  id          bigint generated always as identity primary key,
  commande_id text,
  numero      text not null default '',
  -- Qui a encaissé : « feexpay », « kkiapay », ou « main » quand
  -- l'enseigne s'est portée garante elle-même. Figé au moment du fait :
  -- changer d'agrégateur demain ne réécrit pas les versements d'hier.
  fournisseur text not null default '',
  -- L'opérateur du client : MTN, MOOV, CELTIIS, CARTE. Connu seulement
  -- à l'ouverture de la demande — c'est le client qui l'a choisi.
  reseau      text not null default '',
  reference   text not null default '',
  transaction_id text not null default '',
  attendu     bigint not null default 0,
  recu        bigint not null default 0,
  verdict     text not null default 'ouverte'
              check (verdict in ('ouverte', 'payee', 'incomplete',
                                 'conflit', 'refusee', 'inconnue')),
  detail      text not null default '',
  cree_le     timestamptz not null default now()
);
create index if not exists versements_quand on public.versements(cree_le desc);
create index if not exists versements_commande on public.versements(commande_id);

alter table public.versements enable row level security;
drop policy if exists "versements lecture" on public.versements;
-- L'enseigne lit, personne n'écrit. AUCUNE règle d'écriture n'est posée
-- ici : les seules écritures viennent des fonctions « security definer »
-- ci-dessous, qui s'exécutent avec les droits du propriétaire et passent
-- donc au-dessus de RLS. Une règle d'écriture, même étroite, ouvrirait
-- au journal une porte par PostgREST.
create policy "versements lecture" on public.versements
  for select to authenticated using (public.est_super());
revoke all on public.versements from anon, authenticated;
grant select on public.versements to authenticated;

-- Poser une ligne. Appelée UNIQUEMENT par les fonctions du serveur —
-- jamais depuis une application, d'où la révocation qui suit.
create or replace function public.noter_versement(
  cible text, quoi text, qui text default '', ou text default '',
  ref text default '', trans text default '',
  du bigint default 0, recu bigint default 0, pourquoi text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare
  num     text := '';
  agregat text := left(regexp_replace(lower(coalesce(qui, '')), '[^a-z]', '', 'g'), 16);
  reseau  text := left(regexp_replace(upper(coalesce(ou,  '')), '[^A-Z]', '', 'g'), 16);
begin
  select c.numero into num from public.commandes c where c.id = cible;

  -- L'AGRÉGATEUR ET L'OPÉRATEUR NE SONT CONNUS QU'À L'OUVERTURE. Ni la
  -- notification ni la vérification ne les rappellent : elles n'ont
  -- qu'une référence. On les reprend donc sur la dernière ligne de la
  -- même commande qui les portait.
  --
  -- La règle vit ICI plutôt que chez chaque appelant : posée à trois
  -- endroits, elle finirait par diverger, et le journal dirait « MTN »
  -- d'un côté et rien de l'autre pour un même versement.
  if coalesce(cible, '') <> '' then
    if agregat = '' then
      select v.fournisseur into agregat from public.versements v
       where v.commande_id = cible and v.fournisseur <> ''
       order by v.cree_le desc, v.id desc limit 1;
    end if;
    if reseau = '' then
      select v.reseau into reseau from public.versements v
       where v.commande_id = cible and v.reseau <> ''
       order by v.cree_le desc, v.id desc limit 1;
    end if;
  end if;

  insert into public.versements
    (commande_id, numero, fournisseur, reseau, reference, transaction_id,
     attendu, recu, verdict, detail)
  values (
    nullif(coalesce(cible, ''), ''),
    coalesce(num, ''),
    coalesce(agregat, ''),
    coalesce(reseau, ''),
    left(regexp_replace(coalesce(ref, ''), '[^A-Za-z0-9_-]', '', 'g'), 96),
    left(regexp_replace(coalesce(trans, ''), '[^A-Za-z0-9_-]', '', 'g'), 64),
    greatest(0, coalesce(du, 0)),
    greatest(0, coalesce(recu, 0)),
    -- Un verdict inconnu ne fait pas échouer l'encaissement : il se range
    -- en « inconnue ». Le journal ne doit jamais empêcher l'argent
    -- d'entrer.
    case when quoi in ('ouverte', 'payee', 'incomplete', 'conflit',
                       'refusee', 'inconnue') then quoi else 'inconnue' end,
    left(coalesce(pourquoi, ''), 300));
end $$;
revoke all on function public.noter_versement(text, text, text, text, text, text, bigint, bigint, text)
  from public, anon, authenticated;

-- Une ancienne base peut porter « reseau_de_la_commande » : la règle
-- qu'elle tenait vit désormais DANS « noter_versement », une seule fois.
-- On la retire pour qu'il ne reste pas deux endroits où la lire.
drop function if exists public.reseau_de_la_commande(text);

-- ---------- Lire le journal ----------
-- Réservé à l'enseigne : c'est l'argent de BIZZOO qui transite, pas
-- celui d'une boutique. Une boutique voit ses ventes encaissées dans
-- « statistiques_boutique » ; par quel opérateur le client a payé ne la
-- regarde pas.
create or replace function public.versements_liste(
  depuis date default null,
  jusqu  date default null,
  filtre text default '')
returns table (
  id bigint, commande_id text, numero text,
  fournisseur text, reseau text, reference text, transaction_id text,
  attendu bigint, recu bigint, verdict text, detail text,
  cree_le timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare tri text := lower(trim(coalesce(filtre, '')));
begin
  if not public.est_super() then return; end if;
  return query
    select v.id, v.commande_id, v.numero, v.fournisseur, v.reseau,
           v.reference, v.transaction_id, v.attendu, v.recu,
           v.verdict, v.detail, v.cree_le
      from public.versements v
     where (depuis is null or v.cree_le >= depuis::timestamptz)
       and (jusqu  is null or v.cree_le <  (jusqu + 1)::timestamptz)
       -- « tout » et le filtre vide disent la même chose. Un verdict
       -- inconnu ne rend rien plutôt que tout : se tromper de mot ne
       -- doit pas donner l'impression que la période est vide.
       and (tri = '' or tri = 'tout' or v.verdict = tri)
     order by v.cree_le desc, v.id desc
     limit 300;
end $$;
revoke all on function public.versements_liste(date, date, text) from public, anon;
grant execute on function public.versements_liste(date, date, text) to authenticated;

-- Le résumé de la période. Il compte sur TOUTES les lignes, pas sur les
-- trois cents que la liste rend : « ce qui est entré cette semaine » ne
-- peut pas dépendre de la longueur d'un écran.
create or replace function public.versements_resume(
  depuis date default null,
  jusqu  date default null)
returns table (
  fournisseur text, reseau text, verdict text,
  combien bigint, total bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.est_super() then return; end if;
  return query
    select v.fournisseur, v.reseau, v.verdict,
           count(*)::bigint,
           -- On ne somme QUE ce qui est réellement entré. Additionner
           -- les tentatives ouvertes ferait un chiffre d'affaires
           -- imaginaire, et c'est exactement l'erreur qu'un journal doit
           -- empêcher.
           coalesce(sum(v.recu) filter (where v.verdict = 'payee'), 0)::bigint
      from public.versements v
     where (depuis is null or v.cree_le >= depuis::timestamptz)
       and (jusqu  is null or v.cree_le <  (jusqu + 1)::timestamptz)
     group by v.fournisseur, v.reseau, v.verdict;
end $$;
revoke all on function public.versements_resume(date, date) from public, anon;
grant execute on function public.versements_resume(date, date) to authenticated;

-- ---------- La référence que l'agrégateur donne à une tentative ----------
-- FeexPay ne signe aucune notification. Notre Edge Function ouvre donc
-- le paiement elle-même, reçoit une référence, et la range ICI — c'est
-- avec elle qu'elle ira ensuite demander à FeexPay si le versement a
-- abouti.
--
-- Réservée au « service_role », comme « marquer_payee » : si un
-- téléphone pouvait poser cette référence, il désignerait lui-même le
-- versement censé répondre pour sa commande, et n'importe quel paiement
-- de 100 francs réglerait n'importe quelle commande.
--
-- « drop » avant « create » : cette fonction a gagné deux paramètres —
-- l'agrégateur et l'opérateur — pour le journal des versements. Ajouter
-- des paramètres par défaut ne remplace pas l'ancienne signature, il en
-- crée une seconde, et l'appel devient ambigu : « function is not
-- unique ». Sans ce retrait, chaque paiement échouerait.
drop function if exists public.noter_reference(text, text);
create or replace function public.noter_reference(
  cible text, reference text,
  qui text default '', ou text default '')
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  net text := left(regexp_replace(coalesce(reference, ''), '[^A-Za-z0-9_-]', '', 'g'), 96);
  c   public.commandes%rowtype;
begin
  if net = '' then return false; end if;
  select * into c from public.commandes where id = coalesce(cible, '');
  if not found or c.etat <> 'a_payer' then return false; end if;

  -- Déjà prise par une autre commande : on ne la vole pas.
  if exists (select 1 from public.commandes a
              where a.fournisseur_ref = net and a.id <> c.id) then
    return false;
  end if;

  -- UN FREIN. Chaque appel fait sonner un téléphone : sans lui, on
  -- pourrait harceler n'importe quel numéro de demandes de paiement
  -- venues de l'enseigne — et c'est le compte marchand de BIZZOO qui
  -- en répondrait. Trente secondes laissent le temps de voir la
  -- demande arriver, et de se tromper de numéro sans être bloqué.
  if c.tentative_le is not null and c.tentative_le > now() - interval '30 seconds' then
    return false;
  end if;

  perform set_config('bizzoo.paiement', 'oui', true);
  -- Une commande non payée peut être retentée avec un autre numéro :
  -- la nouvelle tentative remplace alors l'ancienne référence.
  update public.commandes
     set fournisseur_ref = net, tentative_le = now()
   where id = c.id;

  -- Au journal. C'est ICI, et nulle part ailleurs, qu'on sait chez quel
  -- opérateur la demande est partie : ni la notification ni la
  -- vérification ne le rappellent. Ce qui est demandé, c'est l'acompte.
  perform public.noter_versement(c.id, 'ouverte', qui, ou, net, '',
    coalesce(c.acompte, c.total), 0, 'Demande de paiement envoyée.');
  return true;
end $$;

revoke all on function public.noter_reference(text, text, text, text)
  from public, anon, authenticated;

-- ---------- Ce que l'Edge Function a besoin de savoir ----------
-- Le MONTANT vient d'ici, jamais de la requête : c'est tout l'intérêt.
-- Un téléphone qui annoncerait le montant à encaisser paierait 100
-- francs une commande de 100 000.
--
-- Le numéro de téléphone du client fait office de mot de passe, comme
-- pour « suivre_commande » : sans lui, n'importe qui ferait sonner le
-- téléphone d'un inconnu avec une demande de paiement.
--
-- « total » EST CE QUE L'AGRÉGATEUR DOIT DEMANDER : l'acompte, depuis
-- qu'il existe. La fonction Edge « feexpay » demande ce champ-là, telle
-- qu'elle est déployée : elle n'a pas à changer. Le total de la commande
-- entière voyage à part, sous « total_commande ».
create or replace function public.commande_pour_paiement(cible text, tel text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.commandes%rowtype;
begin
  select * into c from public.commandes
   where id = coalesce(cible, '')
     and not compte_supprime
     and client_tel = regexp_replace(coalesce(tel, ''), '\D', '', 'g');
  if not found then return null; end if;
  return jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'etat', c.etat,
    'total', coalesce(c.acompte, c.total), 'devise', c.devise,
    'acompte', coalesce(c.acompte, c.total), 'total_commande', c.total,
    'nom', c.client_nom, 'tel', c.client_tel,
    'reference', c.fournisseur_ref,
    -- Pour que l'Edge Function refuse une relance AVANT d'appeler
    -- l'agrégateur : sinon le téléphone sonnerait quand même, et c'est
    -- seulement en rangeant la référence qu'on s'apercevrait du frein.
    'tentative_le', c.tentative_le);
end $$;

revoke all on function public.commande_pour_paiement(text, text)
  from public, anon, authenticated;

-- ---------- Retrouver une commande par la référence de l'agrégateur ----------
-- Le webhook de FeexPay ne connaît pas nos numéros de commande : il nous
-- rend SA référence, celle qu'on a rangée en ouvrant le paiement. C'est
-- par elle qu'on recolle le versement à la commande.
--
-- Réservée au « service_role ». La rendre lisible ailleurs donnerait, à
-- qui devine une référence, l'état et le montant d'une commande qui ne
-- le regarde pas.
create or replace function public.commande_par_reference(reference text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  net text := left(regexp_replace(coalesce(reference, ''), '[^A-Za-z0-9_-]', '', 'g'), 96);
  c   public.commandes%rowtype;
begin
  if net = '' then return null; end if;
  select * into c from public.commandes where fournisseur_ref = net;
  if not found then return null; end if;
  return jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'etat', c.etat,
    'total', c.total, 'reference', c.fournisseur_ref);
end $$;

revoke all on function public.commande_par_reference(text)
  from public, anon, authenticated;

-- Le filet de l'enseigne : si la notification de l'agrégateur se perd et
-- que le client a bien été débité, le superadministrateur vérifie dans
-- son tableau de bord KkiaPay et se porte garant. La commande porte
-- alors son nom — on voit d'un coup d'œil qu'elle n'a pas été
-- confirmée par la banque.
create or replace function public.confirmer_paiement(cible text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  qui    text;
  montant bigint;
begin
  if not public.est_super() then
    raise exception 'Seule l''enseigne peut confirmer un paiement à la main';
  end if;
  select coalesce(p.email, '') into qui from public.profils p where p.id = auth.uid();
  perform set_config('bizzoo.paiement', 'oui', true);
  -- Ce dont l'enseigne se porte garante, c'est de l'ACOMPTE : le reste
  -- se paie à la livraison, et reste dû.
  update public.commandes
     set etat = 'payee', paye_le = now(), confirme_par = coalesce(qui, 'enseigne'),
         verse = coalesce(acompte, total)
   where id = cible and etat <> 'payee'
  returning verse into montant;

  -- Au journal, et NOMMÉMENT « main ». Un encaissement à la main n'est
  -- pas un versement comme un autre : personne ne l'a vérifié chez
  -- l'agrégateur, quelqu'un s'en est porté garant. Des mois plus tard,
  -- c'est la première chose qu'on veut pouvoir distinguer.
  --
  -- « montant » ne vaut quelque chose que si la mise à jour a porté :
  -- une commande déjà payée ne se re-note pas.
  if montant is not null then
    perform public.noter_versement(cible, 'payee', 'main', '', '', '',
      montant, montant,
      'Confirmé à la main par ' || coalesce(nullif(qui, ''), 'l''enseigne') || '.');
  end if;
end $$;
revoke all on function public.confirmer_paiement(text) from public, anon;
grant execute on function public.confirmer_paiement(text) to authenticated;

-- ---------- Une commande prise sur WhatsApp (3.68.0) ----------
-- CERTAINS CLIENTS COMMANDENT PAR WHATSAPP au lieu de valider leur panier :
-- ils discutent avec l'équipe, paient, et la commande se passait hors de
-- l'application — sans trace, donc sans point possible.
--
-- « faire_livrer » la fait entrer par la MÊME PORTE que les autres :
--   1. « creer_commande » relit les prix, le stock, la boutique ouverte,
--      la monnaie ; les FRAIS DE LIVRAISON, eux, sont ceux que l'équipe a
--      convenus avec le client (décision de BIZZOO pour ces commandes) —
--      un seul frais, un seul livreur, qui en touche sa part comme
--      d'habitude ; la position du client est facultative ;
--   2. le client a DÉJÀ TOUT PAYÉ : pas d'acompte, rien à encaisser à la
--      porte — le livreur ne prend rien chez lui ;
--   3. elle est marquée payée avec la référence de la transaction
--      (jamais deux fois la même), au journal des versements sous
--      « whatsapp », au nom de qui l'a saisie ;
--   4. le paiement déclenche ce qu'il déclenche toujours : le stock
--      décompté, les boutiques prévenues, la course proposée aux livreurs.
--
-- Réservée au superadministrateur, et aux comptes de BIZZOO à qui il a
-- accordé le droit « Faire livrer » (ci-dessous).
alter table public.commandes add column if not exists origine text not null default 'application';
alter table public.commandes drop constraint if exists commandes_origine;
alter table public.commandes add constraint commandes_origine check (origine in ('application', 'whatsapp'));
alter table public.commandes add column if not exists saisie_par uuid references public.profils(id) on delete set null;

-- LE DROIT DE FAIRE LIVRER, que le superadministrateur SEUL accorde à un
-- administrateur ou un modérateur de BIZZOO (un compte d'enseigne). Éteint
-- par défaut : un compte qui ne l'a pas ne voit pas l'option, et la base
-- la lui refuse. Le droit « commandes » ne le donne pas.
alter table public.profils add column if not exists peut_faire_livrer boolean not null default false;

create or replace function public.peut_faire_livrer() returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return public.est_super() or (public.est_compte_enseigne() and exists (
    select 1 from public.profils p where p.id = auth.uid() and p.actif and p.peut_faire_livrer));
end $$;
revoke all on function public.peut_faire_livrer() from public, anon;
grant execute on function public.peut_faire_livrer() to authenticated;

-- Le verrou : la règle de « profils » laisse un administrateur toucher
-- certains comptes (les modérateurs de sa boutique, ceux qu'il a créés…).
-- Aucun d'eux ne doit pouvoir y glisser ce droit — ni se le donner.
-- (SANS « security definer », exprès : « current_user » doit rester celui
-- de l'appel — « authenticated » depuis une application. Les fonctions de
-- confiance, qui écrivent pour elles-mêmes, passent sous leur propriétaire.)
create or replace function public.profil_faire_livrer_verrou() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user in ('anon', 'authenticated')
     and coalesce(new.peut_faire_livrer, false) is distinct from
         (case when tg_op = 'INSERT' then false else coalesce(old.peut_faire_livrer, false) end)
     and not public.est_super() then
    raise exception 'Seul le superadministrateur accorde ou retire le droit « Faire livrer ».'
      using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists profils_faire_livrer_verrou on public.profils;
create trigger profils_faire_livrer_verrou
  before insert or update of peut_faire_livrer on public.profils
  for each row execute function public.profil_faire_livrer_verrou();

-- (3.68.0) Les frais de livraison sont SAISIS par qui a pris la commande
-- (BIZZOO l'a décidé pour ces commandes-là) ; la position du client est
-- facultative. « drop » : la signature a gagné « frais » — l'ancienne,
-- à côté, rendrait l'appel ambigu.
drop function if exists public.faire_livrer(jsonb, jsonb, jsonb, text, bigint, text);
create or replace function public.faire_livrer(
  articles jsonb, client jsonb, destination jsonb, frais bigint, transaction text,
  montant bigint, reseau text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  moi    uuid := auth.uid();
  qui    text;
  net    text := upper(left(regexp_replace(coalesce(transaction, ''), '[^A-Za-z0-9._-]', '', 'g'), 64));
  cle    text;
  res    text := upper(trim(coalesce(reseau, '')));
  g      jsonb;
  c      public.commandes%rowtype;
  compte uuid;
begin
  if moi is null or not public.peut_faire_livrer() then
    raise exception 'Faire livrer une commande prise sur WhatsApp demande le droit « Faire livrer », que le superadministrateur accorde.'
      using errcode = 'P0001';
  end if;
  if coalesce(trim(client ->> 'nom'), '') = '' then
    raise exception 'Indiquez le nom du client.' using errcode = 'P0001';
  end if;
  if coalesce(trim(client ->> 'adresse'), '') = '' then
    raise exception 'Indiquez l''adresse de livraison du client.' using errcode = 'P0001';
  end if;
  if length(net) < 4 then
    raise exception 'Saisissez la référence de la transaction du client, lue sur son reçu de paiement.'
      using errcode = 'P0001';
  end if;
  if res not in ('', 'MTN', 'MOOV', 'CELTIIS') then
    raise exception 'Le réseau du paiement : MTN, Moov ou Celtiis.' using errcode = 'P0001';
  end if;
  if coalesce(montant, 0) <= 0 then
    raise exception 'Indiquez le montant que le client a payé.' using errcode = 'P0001';
  end if;
  if frais is null or frais < 0 or frais > 1000000 then
    raise exception 'Indiquez les frais de livraison convenus avec le client (0 s''il n''y en a pas).'
      using errcode = 'P0001';
  end if;
  -- UNE TRANSACTION NE PAIE QU'UNE COMMANDE : ni une autre commande, ni un
  -- reste payé à la livraison. Comparées sans ponctuation ni casse : un
  -- reçu se recopie de plusieurs façons.
  cle := regexp_replace(net, '[^A-Z0-9]', '', 'g');
  if exists (select 1 from public.commandes x
              where regexp_replace(upper(x.transaction_id), '[^A-Z0-9]', '', 'g') = cle)
     or exists (select 1 from public.encaissements e
                 where regexp_replace(upper(e.transaction_id), '[^A-Z0-9]', '', 'g') = cle) then
    raise exception 'Cette transaction a déjà servi pour une autre commande : vérifiez la référence.'
      using errcode = 'P0001';
  end if;

  -- LE MONTANT D'ABORD, avant d'écrire quoi que ce soit : une commande
  -- refusée après coup aurait déjà pris un numéro « BZ- », et un trou
  -- dans les numéros fait croire au point qu'une commande manque.
  g := public.devis_faire_livrer(articles, null);
  if montant < (g ->> 'sous_total')::bigint + frais then
    raise exception 'Le client a payé %, mais la commande coûte % (dont % de livraison). Vérifiez le montant ou les articles.',
      public.montant_lisible(montant, g ->> 'devise'),
      public.montant_lisible((g ->> 'sous_total')::bigint + frais, g ->> 'devise'),
      public.montant_lisible(frais, g ->> 'devise')
      using errcode = 'P0001';
  end if;

  -- La commande, par le chemin de toutes les commandes : prix, stock,
  -- boutique ouverte, frais. Tout se paie d'un coup (pas d'acompte).
  perform set_config('bizzoo.hors_appli', 'oui', true);
  perform set_config('bizzoo.frais_saisis', frais::text, true);
  g := public.creer_commande(client, articles, '', false, false, destination);
  perform set_config('bizzoo.frais_saisis', '', true);
  perform set_config('bizzoo.hors_appli', '', true);
  select * into c from public.commandes where id = g ->> 'id';

  if montant < c.total then
    raise exception 'Le client a payé %, mais la commande coûte % (dont % de livraison). Vérifiez le montant ou les articles.',
      public.montant_lisible(montant, c.devise), public.montant_lisible(c.total, c.devise),
      public.montant_lisible(coalesce(c.frais_livraison, 0), c.devise)
      using errcode = 'P0001';
  end if;

  -- LE COMPTE DU CLIENT, s'il en a un à ce numéro (et un seul) : la
  -- commande apparaît dans son application, avec le suivi et « J'ai bien
  -- reçu », comme s'il l'avait passée lui-même.
  select min(k.id::text)::uuid into compte
    from public.clients k
   where regexp_replace(coalesce(k.tel, ''), '\D', '', 'g') = c.client_tel
     and coalesce(nullif(k.indicatif, ''), '229') = coalesce(nullif(c.client_indicatif, ''), '229')
  having count(*) = 1;

  select coalesce(nullif(trim(p.nom), ''), nullif(p.email, ''), 'l''équipe') into qui
    from public.profils p where p.id = moi;

  perform set_config('bizzoo.interne', 'oui', true);
  update public.commandes
     set origine = 'whatsapp', saisie_par = moi, client_id = coalesce(client_id, compte)
   where id = c.id;
  perform set_config('bizzoo.interne', '', true);

  -- Payée : le client a TOUT réglé, rien ne reste à encaisser à la porte.
  perform set_config('bizzoo.paiement', 'oui', true);
  update public.commandes
     set etat = 'payee', paye_le = now(), transaction_id = net,
         confirme_par = coalesce(qui, 'l''équipe'), remarque = '', verse = montant
   where id = c.id;
  perform set_config('bizzoo.paiement', '', true);
  perform public.noter_versement(c.id, 'payee', 'whatsapp', res, '', net, c.total, montant,
    'Commande WhatsApp saisie par ' || coalesce(qui, 'l''équipe') || '.');

  select * into c from public.commandes where id = c.id;
  return jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'total', c.total, 'devise', c.devise,
    'frais_livraison', c.frais_livraison, 'livraison', c.livraison,
    'verse', c.verse, 'client_relie', c.client_id is not null);
end $$;
revoke all on function public.faire_livrer(jsonb, jsonb, jsonb, bigint, text, bigint, text) from public, anon;
grant execute on function public.faire_livrer(jsonb, jsonb, jsonb, bigint, text, bigint, text) to authenticated;

-- Le devis de l'écran « Faire livrer » : ce que valent les articles, au
-- prix du catalogue, et le véhicule (le tricycle dès qu'un produit
-- l'exige). Les frais, eux, sont saisis par l'équipe. Rien n'est écrit :
-- pas de commande d'essai, donc pas de numéro « BZ- » perdu, qui ferait
-- croire au point qu'une commande manque. (« destination » n'est plus
-- lue ; elle reste dans la signature pour ne pas en changer.)
create or replace function public.devis_faire_livrer(articles jsonb, destination jsonb default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  sous   bigint;
  devise text;
  tri    boolean;
begin
  if auth.uid() is null or not public.peut_faire_livrer() then
    raise exception 'Réservé aux comptes qui ont le droit « Faire livrer ».' using errcode = 'P0001';
  end if;
  if articles is null or jsonb_typeof(articles) <> 'array' or jsonb_array_length(articles) = 0 then
    return jsonb_build_object('sous_total', 0, 'devise', 'FCFA', 'vehicule', 'moto');
  end if;
  with a as (
    select x ->> 'produit_id' as id,
           greatest(1, least(99, coalesce((x ->> 'quantite')::int, 1))) as q
      from jsonb_array_elements(articles) x
  )
  select coalesce(sum(coalesce(p.prix, 0) * a.q), 0)::bigint,
         min(coalesce(nullif(b.devise, ''), 'FCFA')),
         bool_or(p.vehicule = 'tricycle')
    into sous, devise, tri
    from a join public.produits p on p.id = a.id
    left join public.boutiques b on b.id = p.boutique_id;
  return jsonb_build_object('sous_total', sous, 'devise', coalesce(devise, 'FCFA'),
    'vehicule', case when coalesce(tri, false) then 'tricycle' else 'moto' end);
end $$;
revoke all on function public.devis_faire_livrer(jsonb, jsonb) from public, anon;
grant execute on function public.devis_faire_livrer(jsonb, jsonb) to authenticated;

-- ---------- Ce que chaque boutique rapporte ----------
-- Les ventes RÉELLEMENT encaissées, produit par produit. Rien d'autre
-- ne compte : une commande à payer n'est pas une vente.
--
-- Réservée à l'enseigne. Un administrateur de boutique verrait sinon
-- la commission que BIZZOO prend sur ses voisins.
create or replace function public.statistiques_ventes(
  depuis date default null,
  jusqu  date default null,
  boutique text default null)
returns table (
  boutique_id  text,
  nom_boutique text,
  produit_id   text,
  code         text,
  nom          text,
  quantite     bigint,
  prix_bizzoo  bigint,
  prix_vente   bigint,
  taux_marge   numeric,
  total_bizzoo bigint,
  total_vente  bigint,
  benefice     bigint
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.est_super() then
    raise exception 'Ces chiffres ne regardent que l''enseigne';
  end if;

  return query
    select l.boutique_id,
           coalesce(b.nom, '') as nom_boutique,
           l.produit_id,
           l.code,
           l.nom,
           sum(l.quantite)::bigint,
           l.prix_bizzoo::bigint,
           l.prix::bigint,
           l.taux_marge,
           (sum(l.quantite) * l.prix_bizzoo)::bigint,
           (sum(l.quantite) * l.prix)::bigint,
           (sum(l.quantite) * (l.prix - l.prix_bizzoo))::bigint
      from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
      left join public.boutiques b on b.id = l.boutique_id
     -- Payée, et la ligne pas annulée : c'est cela, une vente.
     where c.etat = 'payee'
       and l.etat <> 'annulee'
       and (depuis is null or c.paye_le >= depuis::timestamptz)
       and (jusqu  is null or c.paye_le <  (jusqu + 1)::timestamptz)
       and (boutique is null or boutique = '' or l.boutique_id = boutique)
     /* Les prix unitaires entrent dans le regroupement : un produit vendu
        à deux tarifs différents fait deux lignes, et non une moyenne qui
        ne correspondrait à aucune vente réelle. */
     group by l.boutique_id, b.nom, l.produit_id, l.code, l.nom,
              l.prix_bizzoo, l.prix, l.taux_marge
     order by (sum(l.quantite) * (l.prix - l.prix_bizzoo)) desc;
end $$;

revoke all on function public.statistiques_ventes(date, date, text) from public, anon;
grant execute on function public.statistiques_ventes(date, date, text) to authenticated;

-- ---------- Et ce que la BOUTIQUE, elle, a vendu ----------
-- La fonction ci-dessus est celle de l'enseigne : elle porte le prix de
-- vente, le taux de marge et le bénéfice de BIZZOO, sur toutes les
-- boutiques. Une boutique n'a rien à y lire — ni chez elle, ni surtout
-- chez les autres.
--
-- Mais une boutique a besoin de savoir ce qu'elle vend. Celle-ci lui
-- rend SES chiffres, et rien d'autre :
--
--   CE QU'ELLE A VENDU — quels articles, combien d'unités, sur combien
--     de commandes ;
--   CE QU'ELLE TOUCHE — le prix BIZZOO, celui qu'elle a elle-même
--     annoncé en créant le produit, et le total qui lui revient.
--
-- CE QU'ELLE NE REND PAS, et c'est délibéré : le prix payé par le
-- client, le taux de marge, le bénéfice de l'enseigne. Ce sont les
-- chiffres de BIZZOO. Les colonnes ne sont pas seulement cachées à
-- l'écran — elles ne sortent pas de la base.
--
-- LA BOUTIQUE NE SE CHOISIT PAS. Il n'y a pas de paramètre « boutique »
-- ici, contrairement à la fonction de l'enseigne : c'est toujours celle
-- du compte connecté. Un paramètre serait une invitation à viser la
-- boutique d'à côté, et il faudrait alors le défendre à chaque appel.
create or replace function public.statistiques_boutique(
  depuis date default null,
  jusqu  date default null)
returns table (
  produit_id   text,
  code         text,
  nom          text,
  quantite     bigint,
  nb_ventes    bigint,
  prix_bizzoo  bigint,
  total_bizzoo bigint
)
language plpgsql stable security definer set search_path = public as $$
declare
  cible text := public.boutique_du_compte();
begin
  -- Un compte sans boutique — un client, ou un profil désactivé — n'a
  -- aucun chiffre à lire. On rend zéro ligne plutôt qu'une erreur : le
  -- même appel sert à tout le monde, et l'écran n'a pas à savoir
  -- d'avance qui il sert.
  --
  -- Ce qui garde la porte ici, c'est « cible » : elle vient de
  -- boutique_du_compte(), qui exige un profil ACTIF. Sans profil, elle
  -- est nulle, et plus bas « l.boutique_id = cible » ne rend rien de
  -- toute façon. Le est_equipe() est une ceinture par-dessus les
  -- bretelles : il lit la même ligne, sous la même condition.
  if not public.est_equipe() or coalesce(cible, '') = '' then
    return;
  end if;

  return query
    select l.produit_id,
           l.code,
           l.nom,
           sum(l.quantite)::bigint,
           count(distinct l.commande_id)::bigint,
           l.prix_bizzoo::bigint,
           (sum(l.quantite) * l.prix_bizzoo)::bigint
      from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
     -- Payée, et la ligne pas annulée : c'est cela, une vente.
     where c.etat = 'payee'
       and l.etat <> 'annulee'
       and l.boutique_id = cible
       and (depuis is null or c.paye_le >= depuis::timestamptz)
       and (jusqu  is null or c.paye_le <  (jusqu + 1)::timestamptz)
     group by l.produit_id, l.code, l.nom, l.prix_bizzoo
     order by sum(l.quantite) * l.prix_bizzoo desc;
end $$;
revoke all on function public.statistiques_boutique(date, date) from public, anon;
grant execute on function public.statistiques_boutique(date, date) to authenticated;

-- =========================================================
-- Les notifications
--
-- UNE LIGNE PAR PERSONNE PRÉVENUE, et non une ligne par
-- événement. C'est plus de lignes, mais c'est la seule forme
-- où « lue » veut dire quelque chose : une commande payée
-- prévient le client, l'équipe de chaque boutique concernée,
-- les comptes de BIZZOO et le superadministrateur — chacun la
-- lit à son heure, et l'un ne décoche rien pour les autres.
--
-- PERSONNE N'ÉCRIT ICI, PAS MÊME L'APPLICATION. Aucune règle
-- d'insertion n'existe : les notifications naissent de
-- déclencheurs, qui posent ce que le cycle de la commande dit,
-- et rien d'autre. Un client ne peut donc pas s'inventer une
-- commande livrée, ni une boutique se fabriquer un accusé de
-- réception. La seule chose qu'on puisse écrire, c'est
-- « lue_le », et sur ses propres lignes.
--
-- AUCUN MONTANT N'Y ENTRE, et c'est voulu. Un livreur reçoit
-- « une course vous est confiée », pas « 385 000 FCFA ». La
-- règle des prix fermés ne servirait à rien si le texte d'une
-- notification les recopiait.
-- =========================================================

create table if not exists public.notifications (
  id           bigserial primary key,
  destinataire uuid not null references auth.users(id) on delete cascade,
  type         text not null,
  titre        text not null default '',
  corps        text not null default '',
  -- Où mène le doigt : « #/commande/… » chez le client,
  -- « #/commandes/… » chez la boutique, « #/livraisons » chez le livreur.
  lien         text not null default '',
  commande_id  text,
  boutique_id  text,
  -- Les trois bips. Tout ce qui touche une commande sonne ; le reste, non.
  sonne        boolean not null default false,
  lue_le       timestamptz,
  cree_le      timestamptz not null default now()
);

create index if not exists notifications_a_moi
  on public.notifications (destinataire, cree_le desc);
create index if not exists notifications_non_lues
  on public.notifications (destinataire) where lue_le is null;

-- UNE FOIS, ET UNE SEULE. Une commande de trois articles chez la même
-- boutique fait trois lignes qui passent à « préparée » : sans cet
-- index, la boutique recevrait trois fois la même nouvelle. Le
-- « coalesce » n'est pas décoratif — deux NULL sont DISTINCTS pour un
-- index unique, et la contrainte n'aurait rien retenu sur les
-- notifications sans boutique.
create unique index if not exists notifications_une_fois
  on public.notifications
     (destinataire, type, commande_id, coalesce(boutique_id, ''))
  where commande_id is not null;

alter table public.notifications enable row level security;
drop policy if exists "notifications a soi"      on public.notifications;
drop policy if exists "notifications marquer lues" on public.notifications;
-- Chacun les siennes. Il n'y a pas d'autre règle : ni insertion, ni
-- suppression, pour personne.
create policy "notifications a soi" on public.notifications
  for select to authenticated using (destinataire = auth.uid());
create policy "notifications marquer lues" on public.notifications
  for update to authenticated
  using (destinataire = auth.uid()) with check (destinataire = auth.uid());

-- UNE BASE SUPABASE DONNE TOUT PAR DÉFAUT : un « grant » posé
-- par-dessus n'enlève rien, il faut « revoke » d'abord. Et la mise à
-- jour se limite à « lue_le » — le titre et le lien d'une notification
-- ne se réécrivent pas après coup.
revoke all on public.notifications from anon, authenticated;
revoke all on sequence public.notifications_id_seq from anon, authenticated;
grant select on public.notifications to authenticated;
grant update (lue_le) on public.notifications to authenticated;

-- ---------- À qui l'on écrit ----------
-- Trois listes, et elles disent à elles seules qui est prévenu de quoi.

-- L'équipe d'une boutique : ceux qui la tiennent. PAS le livreur — il
-- reçoit ses courses, pas les nouvelles de la boutique.
create or replace function public.equipe_de(cible text) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and cible is not null and p.boutique_id = cible
     and p.role in ('administrateur', 'moderateur');
$$;

-- Les comptes de BIZZOO qui suivent les commandes. Leur interrupteur
-- décide : éteint, on ne les dérange pas pour ce qu'ils ne voient pas.
create or replace function public.enseigne_des_commandes() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.boutique_id is null and p.peut_commandes
     and p.role in ('administrateur', 'moderateur');
$$;

-- LE SUPERADMINISTRATEUR N'EST PAS PRÉVENU DE TOUT, et c'est un choix.
-- À dix boutiques et vingt commandes par jour, être prévenu de chaque
-- cran ferait plusieurs centaines de pastilles quotidiennes : une
-- pastille qui ne redescend jamais à zéro ne veut plus rien dire. Il
-- reçoit l'ARGENT qui entre, les INCIDENTS et (3.66.0) la COURSE PRISE
-- par un livreur ; les autres étapes restent lisibles sur l'écran des
-- commandes.
create or replace function public.les_superadmins() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.role = 'superadministrateur';
$$;

revoke all on function public.equipe_de(text)            from public, anon, authenticated;
revoke all on function public.enseigne_des_commandes()   from public, anon, authenticated;
revoke all on function public.les_superadmins()          from public, anon, authenticated;

-- ---------- Écrire la notification ----------
-- « on conflict do nothing » s'appuie sur l'index unique plus haut :
-- c'est lui qui fait qu'une commande de trois articles ne prévient
-- qu'une fois.
create or replace function public.notifier(
  qui uuid[], quoi text, le_titre text, le_corps text,
  le_lien text, la_commande text, la_boutique text, qui_sonne boolean)
returns int
language plpgsql security definer set search_path = public as $$
declare combien int := 0;
begin
  if qui is null or array_length(qui, 1) is null then return 0; end if;
  insert into public.notifications
    (destinataire, type, titre, corps, lien, commande_id, boutique_id, sonne)
  select u, quoi, coalesce(le_titre, ''), coalesce(le_corps, ''),
         coalesce(le_lien, ''), la_commande, la_boutique, coalesce(qui_sonne, false)
    from unnest(qui) as u
   where u is not null
  on conflict do nothing;
  get diagnostics combien = row_count;
  return combien;
end $$;
revoke all on function public.notifier(uuid[], text, text, text, text, text, text, boolean)
  from public, anon, authenticated;

-- ---------- Le paiement ----------
-- Le premier cran, et le seul qui réveille le superadministrateur :
-- c'est de l'argent qui entre.
create or replace function public.notifier_paiement() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  b        record;
  numero   text := coalesce(new.numero, '');
  client   uuid := new.client_id;
  devise   text := ' ' || coalesce(nullif(new.devise, ''), 'FCFA');
  reste    bigint;
begin
  if new.etat is not distinct from old.etat or new.etat <> 'payee' then
    return new;
  end if;

  -- CE QUI RESTE À PAYER À LA LIVRAISON. À zéro — tout réglé en ligne —
  -- les messages restent ceux d'avant l'acompte. Les montants s'écrivent
  -- comme dans les applications : « 13 500 FCFA ».
  select coalesce(sum(r.a_encaisser), 0) into reste
    from public.restes_par_boutique(new.id) r;

  -- Le client, s'il a un compte. Une commande passée sans compte n'a
  -- personne à prévenir — le reçu lui est déjà revenu par WhatsApp.
  if client is not null then
    perform public.notifier(array[client], 'commande_payee',
      case when reste > 0 then 'Acompte reçu' else 'Paiement reçu' end,
      'Votre commande ' || numero || ' est confirmée. Nous la préparons.' ||
        case when reste > 0
             then ' Reste à payer à la livraison : ' ||
                  replace(to_char(reste, 'FM999,999,999,990'), ',', ' ') || devise || '.'
             else '' end,
      '#/commande/' || new.id, new.id, null, true);
  end if;

  -- Chaque boutique concernée, une fois, avec CE QU'ELLE encaissera : sa
  -- part du reste, que son livreur réclamera à la porte.
  for b in select r.boutique_id, r.a_encaisser
             from public.restes_par_boutique(new.id) r
            where r.boutique_id is not null loop
    perform public.notifier(public.equipe_de(b.boutique_id), 'commande_payee',
      case when b.a_encaisser > 0 then 'Nouvelle commande confirmée' else 'Nouvelle commande payée' end,
      case when b.a_encaisser > 0
           then 'La commande ' || numero || ' est confirmée par son acompte. À préparer — ' ||
                replace(to_char(b.a_encaisser, 'FM999,999,999,990'), ',', ' ') || devise ||
                ' à encaisser à la livraison.'
           else 'La commande ' || numero || ' est payée. À préparer.' end,
      '#/commandes/' || new.id, new.id, b.boutique_id, true);
  end loop;

  perform public.notifier(public.enseigne_des_commandes(), 'commande_payee',
    case when reste > 0 then 'Nouvelle commande confirmée' else 'Nouvelle commande payée' end,
    'La commande ' || numero ||
      case when reste > 0 then ' vient d''être confirmée par son acompte.'
           else ' vient d''être payée.' end,
    '#/commandes/' || new.id, new.id, null, true);

  perform public.notifier(public.les_superadmins(), 'commande_payee',
    case when reste > 0 then 'Acompte encaissé' else 'Paiement encaissé' end,
    'La commande ' || numero ||
      case when reste > 0
           then ' : acompte de ' ||
                replace(to_char(coalesce(new.verse, new.acompte, 0), 'FM999,999,999,990'), ',', ' ') ||
                devise || ' encaissé, ' ||
                replace(to_char(reste, 'FM999,999,999,990'), ',', ' ') || devise ||
                ' à encaisser à la livraison.'
           else ' est payée.' end,
    '#/commandes/' || new.id, new.id, null, true);

  return new;
end $$;

drop trigger if exists commandes_notifient on public.commandes;
create trigger commandes_notifient
  after update on public.commandes
  for each row execute function public.notifier_paiement();

-- ---------- Le cycle de la ligne ----------
-- Préparée, confiée, en route, remise, confirmée, annulée. Un
-- déclencheur par LIGNE, mais l'index unique n'en laisse passer qu'une
-- par boutique et par cran.
create or replace function public.notifier_ligne() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  cmd      record;
  numero   text;
  client   uuid;
  equipe   uuid[];
  enseigne uuid[];
  fiche    jsonb;
  porteur  record;
begin
  select c.numero, c.client_id into cmd
    from public.commandes c where c.id = new.commande_id;
  numero   := coalesce(cmd.numero, '');
  client   := cmd.client_id;
  equipe   := public.equipe_de(new.boutique_id);
  enseigne := public.enseigne_des_commandes();

  -- ---- Une course confiée, ou reprise ----
  if new.livreur_id is distinct from old.livreur_id then
    -- Le livreur qui a pris la course lui-même (« Commande reçue »)
    -- connaît déjà sa fiche : l'alerte n'est que pour une course que la
    -- boutique lui CONFIE.
    if new.livreur_id is not null
       and coalesce(current_setting('bizzoo.prise', true), '') <> 'oui' then
      -- (3.59.0) L'ALERTE DIT TOUT CE QU'IL FAUT POUR PARTIR : où prendre
      -- le colis, où le livrer, le numéro du destinataire, les frais, ce
      -- qui est déjà payé, et ce qu'il reste à récupérer. Les montants de
      -- CETTE boutique seulement ; pas le prix des articles.
      fiche := public.fiche_course(new.commande_id, new.boutique_id);
      perform public.notifier(array[new.livreur_id], 'course_confiee',
        'Nouvelle course — ' || numero,
        'Récupérer : ' || (fiche -> 'retrait' ->> 'boutique') ||
          coalesce(nullif(' — ' || (fiche -> 'retrait' ->> 'adresse'), ' — '), '') || E'\n' ||
        'Livrer à : ' || coalesce(nullif(fiche -> 'livraison' ->> 'nom', ''), 'le client') ||
          coalesce(nullif(' — ' || (fiche -> 'livraison' ->> 'adresse'), ' — '), ' (adresse à demander)') || E'\n' ||
        'Destinataire : +' || (fiche -> 'livraison' ->> 'indicatif') || ' ' || (fiche -> 'livraison' ->> 'tel') || E'\n' ||
        'Frais de livraison : ' || public.montant_lisible((fiche ->> 'frais')::numeric, fiche ->> 'devise') || E'\n' ||
        'Déjà payé : ' || public.montant_lisible((fiche ->> 'deja_paye')::numeric, fiche ->> 'devise') || E'\n' ||
        case when (fiche ->> 'a_encaisser')::numeric > 0
             then 'Reste à payer par MoMoPay : ' || public.montant_lisible((fiche ->> 'a_encaisser')::numeric, fiche ->> 'devise') ||
                  ' (pas d''espèces)'
             else 'Rien à récupérer : tout est payé.' end || E'\n' ||
        'Touchez « Commande reçue » pour accepter la course.',
        '#/livraisons', new.commande_id, new.boutique_id, true);
    end if;
    if coalesce(current_setting('bizzoo.refus', true), '') <> 'oui' then
    perform public.notifier(enseigne, 'course_confiee',
      'Course confiée à un livreur',
      'Commande ' || numero || '.',
      '#/commandes/' || new.commande_id, new.commande_id, new.boutique_id, true);
    end if;
  end if;

  -- ---- « Reçu » : le livreur a accepté (3.59.0) ----
  -- LE CLIENT REÇOIT LE NOM ET LE NUMÉRO DE SON LIVREUR, pour le joindre
  -- si besoin. La boutique apprend que sa course est acceptée.
  if new.recu_le is not null and old.recu_le is null and new.livreur_id is not null then
    select coalesce(nullif(p.nom, ''), 'Votre livreur') as nom, coalesce(p.tel, '') as tel
      into porteur from public.profils p where p.id = new.livreur_id;
    if client is not null then
      -- Une commande prise d'un coup (« Commande reçue ») : UNE nouvelle
      -- pour toute la commande — toutes ses boutiques en livraison
      -- groupée —, pas une par boutique.
      perform public.notifier(array[client], 'course_acceptee',
        'Votre livreur : ' || porteur.nom,
        porteur.nom || ' livre votre commande ' || numero ||
          coalesce(' (' || nullif(
            case when coalesce(current_setting('bizzoo.prise', true), '') = 'oui'
                 then (select string_agg(distinct b.nom, ', ') from public.commande_lignes l2
                         join public.boutiques b on b.id = l2.boutique_id
                        where l2.commande_id = new.commande_id and l2.etat <> 'annulee')
                 else (select b.nom from public.boutiques b where b.id = new.boutique_id) end,
            '') || ')', '') || '.' ||
          case when porteur.tel <> ''
               then E'\nSon numéro : +' || coalesce(nullif((select b.indicatif from public.boutiques b where b.id = new.boutique_id), ''), '229') ||
                    ' ' || porteur.tel || ' — appelez-le si besoin.'
               else '' end,
        '#/commande/' || new.commande_id, new.commande_id,
        case when coalesce(current_setting('bizzoo.prise', true), '') = 'oui' then null
             else new.boutique_id end, true);
    end if;
    perform public.notifier(equipe, 'course_acceptee',
      'Course acceptée par ' || porteur.nom,
      'Commande ' || numero || ' — le livreur a accepté la course.',
      '#/commandes/' || new.commande_id, new.commande_id, new.boutique_id, true);
    -- (3.66.0) BIZZOO AUSSI L'ENTEND : ses administrateurs qui suivent les
    -- commandes et les superadministrateurs — une sonnerie par prise, pas
    -- une par boutique quand le livreur prend toute la commande d'un coup.
    perform public.notifier(enseigne || public.les_superadmins(), 'course_acceptee',
      'Course prise par ' || porteur.nom,
      'Commande ' || numero || ' — ' || porteur.nom || ' a pris la course.',
      '#/commandes/' || new.commande_id, new.commande_id,
      case when coalesce(current_setting('bizzoo.prise', true), '') = 'oui' then null
           else new.boutique_id end, true);
  end if;

  -- ---- L'accusé de réception du client ----
  -- C'est la boutique qui l'attend : elle a remis, elle veut savoir que
  -- c'est bien arrivé.
  if new.confirme_le is not null and old.confirme_le is null then
    perform public.notifier(equipe, 'reception_confirmee',
      'Le client a confirmé la réception',
      'Commande ' || numero || ' — le client déclare avoir tout reçu.',
      '#/commandes/' || new.commande_id, new.commande_id, new.boutique_id, true);
    perform public.notifier(enseigne, 'reception_confirmee',
      'Réception confirmée',
      'Commande ' || numero || '.',
      '#/commandes/' || new.commande_id, new.commande_id, new.boutique_id, true);
  end if;

  if new.etat is not distinct from old.etat then return new; end if;

  -- ---- Les crans du colis ----
  if new.etat = 'preparee' and client is not null then
    perform public.notifier(array[client], 'commande_preparee',
      'Votre colis est prêt',
      'Commande ' || numero || ' — il part bientôt.',
      '#/commande/' || new.commande_id, new.commande_id, new.boutique_id, true);
  end if;

  if new.etat = 'en_livraison' then
    if client is not null then
      perform public.notifier(array[client], 'commande_en_livraison',
        'Votre colis est en route',
        'Commande ' || numero || ' — tenez votre téléphone à portée.',
        '#/commande/' || new.commande_id, new.commande_id, new.boutique_id, true);
    end if;
    perform public.notifier(equipe, 'commande_en_livraison',
      'Colis parti',
      'Commande ' || numero || ' est en livraison.',
      '#/commandes/' || new.commande_id, new.commande_id, new.boutique_id, true);
  end if;

  if new.etat = 'remise' then
    if client is not null then
      perform public.notifier(array[client], 'commande_remise',
        'Votre colis est livré',
        'Commande ' || numero || ' — confirmez que vous avez bien reçu.',
        '#/commande/' || new.commande_id, new.commande_id, new.boutique_id, true);
    end if;
    perform public.notifier(equipe, 'commande_remise',
      'Colis remis',
      'Commande ' || numero || ' — en attente de la confirmation du client.',
      '#/commandes/' || new.commande_id, new.commande_id, new.boutique_id, true);
  end if;

  -- ---- Un incident : le superadministrateur, lui, veut le savoir ----
  if new.etat = 'annulee' then
    if client is not null then
      perform public.notifier(array[client], 'commande_annulee',
        'Une partie de votre commande est annulée',
        'Commande ' || numero || ' — ouvrez-la pour le détail.',
        '#/commande/' || new.commande_id, new.commande_id, new.boutique_id, true);
    end if;
    perform public.notifier(enseigne || public.les_superadmins(), 'commande_annulee',
      'Commande annulée',
      'Commande ' || numero || '.',
      '#/commandes/' || new.commande_id, new.commande_id, new.boutique_id, true);
  end if;

  return new;
end $$;

drop trigger if exists lignes_notifient on public.commande_lignes;
create trigger lignes_notifient
  after update on public.commande_lignes
  for each row execute function public.notifier_ligne();

-- ---------- Le stock suit les ventes ----------
-- UNE VENTE PAYÉE SORT DU STOCK, et c'est la base qui la sort : ni
-- l'application ni l'agrégateur n'ont à y penser, et le paiement à la
-- main par l'enseigne passe par le même chemin. Le décompte se fait au
-- passage à « payée », pas à la commande : une commande qu'on ne paie
-- jamais n'a rien pris à personne, et la réserver bloquerait la
-- dernière pièce pour un client parti.
--
-- CE QUI A ÉTÉ PRIS SE NOTE sur la ligne : c'est ce qui se rend si la
-- vente est annulée, ni plus ni moins. Sans cette trace, une annulation
-- rendrait ce qui avait été commandé — y compris des pièces qui
-- n'avaient jamais été là.
--
-- UN PAIEMENT NE S'ANNULE JAMAIS À CAUSE DU STOCK. L'argent est déjà
-- chez l'agrégateur : refuser l'écriture, ce serait un client débité et
-- une commande qui reste « à payer ». Deux clients peuvent payer la
-- dernière pièce à une seconde d'écart ; le second passe, le stock
-- s'arrête à zéro, et la boutique est prévenue qu'il manque des pièces.
alter table public.commande_lignes
  add column if not exists stock_pris int not null default 0 check (stock_pris >= 0);

-- Rendre au stock ce qu'une ligne avait pris. Une seule fois : la trace
-- repasse à zéro, et un second appel ne rend rien.
create or replace function public.stock_rendre(ligne text) returns int
language plpgsql security definer set search_path = public as $$
declare
  l record;
begin
  select cl.id, cl.produit_id, cl.stock_pris into l
    from public.commande_lignes cl
   where cl.id = ligne and cl.stock_pris > 0
   for update;
  if not found then return 0; end if;
  begin
    if l.produit_id is not null then
      update public.produits
         set stock = greatest(coalesce(stock, 0), 0) + l.stock_pris,
             disponible = true
       where id = l.produit_id;
    end if;
    update public.commande_lignes set stock_pris = 0 where id = l.id;
  exception when others then
    -- Une annulation ne se bloque pas pour autant : la trace reste, et
    -- l'on pourra rendre plus tard.
    raise warning 'stock_rendre(%) : %', ligne, sqlerrm;
    return 0;
  end;
  return l.stock_pris;
end $$;
-- Rien ni personne ne l'appelle de l'extérieur : rendre du stock sans
-- annulation, ce serait en fabriquer.
revoke all on function public.stock_rendre(text) from public, anon, authenticated;

create or replace function public.commande_stock() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  l        record;
  avant    int;
  pris     int;
  appro    boolean;
  numero   text := coalesce(new.numero, '');
  -- Par boutique, ce qu'il faudra lui dire. Une notification par
  -- boutique et par commande, pas une par produit : trois articles
  -- épuisés d'un coup se lisent en une ligne.
  epuises  jsonb := '{}'::jsonb;
  manques  jsonb := '{}'::jsonb;
  ratees   jsonb := '{}'::jsonb;
  b        text;
  liste    text;
begin
  -- ---- Annulée après paiement : tout ce qui avait été pris revient ----
  if old.etat = 'payee' and new.etat is distinct from 'payee' then
    for l in select cl.id from public.commande_lignes cl
              where cl.commande_id = new.id and cl.stock_pris > 0
              order by cl.produit_id, cl.id loop
      perform public.stock_rendre(l.id);
    end loop;
    return null;
  end if;

  if new.etat is distinct from 'payee' or old.etat = 'payee' then
    return null;
  end if;

  -- ---- Payée : on prend ----
  -- Dans l'ordre des produits : deux paiements simultanés verrouillent
  -- leurs produits dans le même ordre, et ne s'attendent jamais en croix.
  for l in select cl.id, cl.produit_id, coalesce(cl.boutique_id, '') as boutique,
                  cl.nom, cl.quantite
             from public.commande_lignes cl
            where cl.commande_id = new.id and cl.etat <> 'annulee'
              and cl.stock_pris = 0 and cl.produit_id is not null
            order by cl.produit_id, cl.id loop
    begin
      select greatest(coalesce(p.stock, 0), 0),
             (p.appro_le is not null and p.appro_le >= current_date)
        into avant, appro
        from public.produits p
       where p.id = l.produit_id and not coalesce(p.sur_commande, false)
       for update;
      -- « Sur commande » : la boutique le fait venir, il n'y a rien à compter.
      if not found then continue; end if;

      pris := least(avant, l.quantite);
      if pris > 0 then
        update public.produits
           set stock = avant - pris,
               disponible = (avant - pris) > 0
         where id = l.produit_id;
        update public.commande_lignes set stock_pris = pris where id = l.id;
      end if;

      -- En approvisionnement, ce qui manque ARRIVE : c'est ce que la
      -- boutique a annoncé, pas une vente de trop.
      if pris < l.quantite and not appro then
        manques := jsonb_set(manques, array[l.boutique],
          coalesce(manques -> l.boutique, '[]'::jsonb) ||
          to_jsonb(l.nom || ' (' || l.quantite || ' vendu' ||
                   case when l.quantite > 1 then 's' else '' end ||
                   ', ' || avant || ' en stock)'));
      elsif pris > 0 and avant - pris = 0 then
        epuises := jsonb_set(epuises, array[l.boutique],
          coalesce(epuises -> l.boutique, '[]'::jsonb) || to_jsonb(l.nom));
      end if;
    exception when others then
      -- Le produit refuse l'écriture — un rayon devenu incohérent, par
      -- exemple. Le paiement, lui, passe : on le dit à qui peut corriger.
      ratees := jsonb_set(ratees, array[l.boutique],
        coalesce(ratees -> l.boutique, '[]'::jsonb) || to_jsonb(l.nom));
      raise warning 'commande_stock(%) : % — %', new.id, l.nom, sqlerrm;
    end;
  end loop;

  -- ---- Ce que la boutique doit savoir ----
  -- Une notification ratée n'annule pas un paiement non plus.
  begin
    for b in select jsonb_object_keys(manques) loop
      select string_agg(x, ', ') into liste from jsonb_array_elements_text(manques -> b) x;
      perform public.notifier(
        public.equipe_de(nullif(b, '')) || public.enseigne_des_commandes() || public.les_superadmins(),
        'stock_insuffisant', 'Stock insuffisant',
        'Commande ' || numero || ' payée, mais il manque des pièces : ' || liste ||
          '. Voyez avec le client.',
        '#/commandes/' || new.id, new.id, nullif(b, ''), true);
    end loop;
    for b in select jsonb_object_keys(epuises) loop
      select string_agg(x, ', ') into liste from jsonb_array_elements_text(epuises -> b) x;
      perform public.notifier(public.equipe_de(nullif(b, '')),
        'stock_epuise', 'Rupture de stock',
        liste || ' : plus aucune pièce après la commande ' || numero ||
          '. Vos clients voient « En rupture ».',
        '#/stock?filtre=rupture', new.id, nullif(b, ''), false);
    end loop;
    for b in select jsonb_object_keys(ratees) loop
      select string_agg(x, ', ') into liste from jsonb_array_elements_text(ratees -> b) x;
      perform public.notifier(
        public.equipe_de(nullif(b, '')) || public.les_superadmins(),
        'stock_a_verifier', 'Stock à vérifier',
        'Commande ' || numero || ' payée, mais le stock de ' || liste ||
          ' n''a pas pu être décompté. Corrigez-le à la main.',
        '#/stock', new.id, nullif(b, ''), true);
    end loop;
  exception when others then
    raise warning 'commande_stock(%) notifications : %', new.id, sqlerrm;
  end;
  return null;
end $$;

-- « of etat » : le total qui suit ses lignes réécrit aussi la commande,
-- et ne doit rien décompter.
drop trigger if exists commandes_stock on public.commandes;
create trigger commandes_stock
  after update of etat on public.commandes
  for each row execute function public.commande_stock();

-- Une ligne annulée à part — une boutique qui ne peut pas servir sa
-- part — rend ce qu'elle avait pris.
create or replace function public.ligne_stock() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.etat = 'annulee' and old.etat is distinct from 'annulee' and new.stock_pris > 0 then
    perform public.stock_rendre(new.id);
  end if;
  return null;
end $$;

drop trigger if exists lignes_stock on public.commande_lignes;
create trigger lignes_stock
  after update of etat on public.commande_lignes
  for each row execute function public.ligne_stock();

-- ---------- Ce que l'application demande ----------
-- Combien n'ai-je pas lu ? Une seule question, une seule réponse : la
-- pastille ne compte pas les lignes elle-même.
create or replace function public.mes_notifications_non_lues() returns int
language sql stable security definer set search_path = public as $$
  select coalesce(count(*), 0)::int from public.notifications
   where destinataire = auth.uid() and lue_le is null;
$$;
revoke all on function public.mes_notifications_non_lues() from public, anon;
grant execute on function public.mes_notifications_non_lues() to authenticated;

-- Tout marquer lu d'un geste. Rend le nombre de lignes touchées, pour
-- que l'écran sache quoi dire.
create or replace function public.tout_marquer_lu() returns int
language plpgsql security definer set search_path = public as $$
declare combien int;
begin
  if auth.uid() is null then return 0; end if;
  update public.notifications set lue_le = now()
   where destinataire = auth.uid() and lue_le is null;
  get diagnostics combien = row_count;
  return combien;
end $$;
revoke all on function public.tout_marquer_lu() from public, anon;
grant execute on function public.tout_marquer_lu() to authenticated;

-- ---------- Le suivi des commandes en direct (3.59.0) ----------
-- CHAQUE MODIFICATION D'UNE COMMANDE PRÉVIENT TOUS CEUX QUI LA VOIENT :
-- le client qui l'a passée, l'administrateur et le modérateur de chaque
-- boutique concernée, BIZZOO, et le livreur qui la porte. Leur écran se
-- met à jour tout seul — étape, livreur, paiement à la livraison.
--
-- Pourquoi un « signal » plutôt que la commande elle-même : les lignes
-- de commande ont des colonnes que personne ne lit (le prix BIZZOO). Le
-- temps réel relit la ligne modifiée avec les droits de chacun ; on lui
-- donne donc une table qui ne porte RIEN d'autre que l'identifiant de la
-- commande et l'heure, et chaque écran relit ensuite ce qui le regarde
-- par ses chemins habituels.
create table if not exists public.commandes_signaux (
  commande_id text primary key references public.commandes(id) on delete cascade,
  maj_le      timestamptz not null default now()
);
alter table public.commandes_signaux enable row level security;
revoke all on public.commandes_signaux from anon, authenticated;
grant select on public.commandes_signaux to authenticated;

-- Qui voit cette commande : son client, l'équipe d'une boutique dont
-- elle porte un article (et BIZZOO), le livreur d'une de ses parts.
create or replace function public.voit_la_commande(cible text) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then return false; end if;
  return exists (select 1 from public.commandes c where c.id = cible and c.client_id = auth.uid())
      or exists (select 1 from public.commande_lignes l
                  where l.commande_id = cible
                    and (l.livreur_id = auth.uid() or public.peut_agir_sur(l.boutique_id)));
end $$;
revoke all on function public.voit_la_commande(text) from public, anon;
grant execute on function public.voit_la_commande(text) to authenticated;

drop policy if exists "signaux de mes commandes" on public.commandes_signaux;
create policy "signaux de mes commandes" on public.commandes_signaux
  for select to authenticated using (public.voit_la_commande(commande_id));

create or replace function public.signaler_commande() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.commandes_signaux (commande_id, maj_le) values (new.id, now())
  on conflict (commande_id) do update set maj_le = now();
  return null;
end $$;
revoke all on function public.signaler_commande() from public, anon, authenticated;

create or replace function public.signaler_ligne() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.commandes_signaux (commande_id, maj_le) values (new.commande_id, now())
  on conflict (commande_id) do update set maj_le = now();
  return null;
end $$;
revoke all on function public.signaler_ligne() from public, anon, authenticated;

create or replace trigger commandes_signalent
  after update on public.commandes
  for each row execute function public.signaler_commande();
create or replace trigger lignes_signalent
  after insert or update on public.commande_lignes
  for each row execute function public.signaler_ligne();
create or replace trigger encaissements_signalent
  after insert or update on public.encaissements
  for each row execute function public.signaler_ligne();

-- ---------- Le solde de chaque boutique, et ses reversements (3.59.0) ----------
--
-- TOUT L'ARGENT ARRIVE CHEZ BIZZOO : l'acompte en ligne, le reste par
-- MoMoPay. Chaque boutique a donc, chez BIZZOO, un SOLDE : ce que lui
-- rapportent ses ventes, commission de BIZZOO déduite — le prix BIZZOO de
-- chaque article, celui qu'elle a fixé en créant le produit.
--
--   GAGNÉ          ses articles REMIS au client (une vente n'est acquise
--                  qu'une fois livrée) ;
--   À VENIR        ses articles payés, pas encore remis ;
--   DÉJÀ ENCAISSÉ  le reste payé en espèces, du temps où le livreur le
--                  rendait à la boutique : elle a déjà cet argent en main ;
--   REVERSÉ        les reversements validés par BIZZOO ;
--   EN ATTENTE     les demandes pas encore tranchées ;
--   DISPONIBLE     gagné − déjà encaissé − reversé − en attente.
--
-- Les frais de livraison ne sont pas des ventes : ils n'y entrent pas.
--
-- LE NUMÉRO DE RÉCEPTION vit dans une table à part, fermée : la table des
-- boutiques se lit sans compte, et un numéro de paiement n'a pas à
-- traîner sous les yeux de tous. Chaque demande garde le numéro du moment
-- où elle a été faite.
create table if not exists public.boutiques_reception (
  boutique_id text primary key references public.boutiques(id) on delete cascade,
  tel         text not null default '',
  reseau      text not null default '' check (reseau in ('', 'MTN', 'MOOV', 'CELTIIS')),
  titulaire   text not null default '',
  maj_le      timestamptz not null default now(),
  maj_par     text not null default ''
);
alter table public.boutiques_reception enable row level security;
revoke all on public.boutiques_reception from anon, authenticated;

create table if not exists public.reversements (
  id          bigserial primary key,
  boutique_id text not null references public.boutiques(id) on delete cascade,
  montant     bigint not null check (montant > 0),
  tel         text not null default '',
  reseau      text not null default '',
  titulaire   text not null default '',
  etat        text not null default 'en_attente' check (etat in ('en_attente', 'valide', 'refuse')),
  demande_par text not null default '',
  demande_le  timestamptz not null default now(),
  decide_par  text not null default '',
  decide_le   timestamptz,
  reference   text not null default '',
  motif       text not null default ''
);
create index if not exists reversements_boutique on public.reversements(boutique_id, demande_le desc);
create index if not exists reversements_attente on public.reversements(demande_le) where etat = 'en_attente';
alter table public.reversements enable row level security;
revoke all on public.reversements from anon, authenticated;
revoke all on sequence public.reversements_id_seq from anon, authenticated;

-- Qui DEMANDE un reversement et règle le numéro : l'administrateur de la
-- boutique, ou le superadministrateur. Un modérateur, non : c'est de
-- l'argent.
create or replace function public.gere_les_fonds(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or (public.est_admin() and cible is not null and cible = public.boutique_du_compte());
$$;
revoke all on function public.gere_les_fonds(text) from public, anon, authenticated;
grant execute on function public.gere_les_fonds(text) to authenticated;

create or replace function public.nom_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select coalesce(nullif(p.nom, ''), nullif(p.email, ''), 'l''équipe')
                     from public.profils p where p.id = auth.uid()), '');
$$;
revoke all on function public.nom_du_compte() from public, anon, authenticated;

create or replace function public.solde_boutique(cible text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  gagne bigint; a_venir bigint; encaisse bigint; reverse bigint; attente bigint;
  r public.boutiques_reception%rowtype;
begin
  if not public.tient_la_caisse(cible) then
    raise exception 'Ce solde n''est pas celui de votre boutique.';
  end if;
  select coalesce(sum(l.prix_bizzoo::bigint * l.quantite) filter (where l.etat = 'remise'), 0),
         coalesce(sum(l.prix_bizzoo::bigint * l.quantite)
                    filter (where l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')), 0)
    into gagne, a_venir
    from public.commande_lignes l
    join public.commandes c on c.id = l.commande_id and c.etat = 'payee'
   where l.boutique_id = cible;
  select coalesce(sum(x.montant), 0) into encaisse from public.encaissements x
   where x.boutique_id = cible and x.mode = 'especes' and x.remis_le is not null;
  select coalesce(sum(v.montant) filter (where v.etat = 'valide'), 0),
         coalesce(sum(v.montant) filter (where v.etat = 'en_attente'), 0)
    into reverse, attente
    from public.reversements v where v.boutique_id = cible;
  select * into r from public.boutiques_reception where boutique_id = cible;
  return jsonb_build_object(
    'gagne', gagne, 'a_venir', a_venir, 'deja_encaisse', encaisse,
    'reverse', reverse, 'en_attente', attente,
    'disponible', greatest(0, gagne - encaisse - reverse - attente),
    'devise', coalesce((select nullif(b.devise, '') from public.boutiques b where b.id = cible), 'FCFA'),
    'reception', case when r.boutique_id is null or r.tel = '' then null
                      else jsonb_build_object('tel', r.tel, 'reseau', r.reseau, 'titulaire', r.titulaire,
                                              'maj_le', r.maj_le, 'maj_par', r.maj_par) end);
end $$;
revoke all on function public.solde_boutique(text) from public, anon;
grant execute on function public.solde_boutique(text) to authenticated;

-- LE NUMÉRO DE RÉCEPTION. Le changer prévient BIZZOO : c'est la porte
-- par laquelle on détournerait les reversements d'une boutique.
create or replace function public.regler_reception(cible text, tel text, reseau text, titulaire text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  national text := regexp_replace(coalesce(tel, ''), '\D', '', 'g');
  res      text := upper(coalesce(reseau, ''));
  qui      text := public.nom_du_compte();
begin
  if not public.gere_les_fonds(cible) then
    raise exception 'Seul l''administrateur de la boutique règle son numéro de réception.';
  end if;
  national := regexp_replace(national, '^229', '');
  if length(national) = 8 then national := '01' || national; end if;
  if length(national) <> 10 or national !~ '^01[0-9]+' then
    raise exception 'Ce numéro n''a pas la forme d''un numéro béninois : dix chiffres commençant par 01.'
      using errcode = 'P0001';
  end if;
  if res not in ('MTN', 'MOOV', 'CELTIIS') then
    raise exception 'Choisissez le réseau du numéro : MTN, Moov ou Celtiis.' using errcode = 'P0001';
  end if;
  insert into public.boutiques_reception (boutique_id, tel, reseau, titulaire, maj_le, maj_par)
  values (cible, national, res, left(trim(coalesce(titulaire, '')), 80), now(), qui)
  on conflict (boutique_id) do update
     set tel = excluded.tel, reseau = excluded.reseau, titulaire = excluded.titulaire,
         maj_le = now(), maj_par = excluded.maj_par;
  perform public.notifier(public.les_superadmins(), 'reception_reglee',
    'Numéro de réception changé — ' || coalesce((select b.nom from public.boutiques b where b.id = cible), cible),
    qui || ' a réglé le numéro de réception : ' || res || ' ' || national ||
      coalesce(' (' || nullif(trim(coalesce(titulaire, '')), '') || ')', '') || '.',
    '#/reversements', null, cible, false);
  return jsonb_build_object('tel', national, 'reseau', res);
end $$;
revoke all on function public.regler_reception(text, text, text, text) from public, anon;
grant execute on function public.regler_reception(text, text, text, text) to authenticated;

create or replace function public.demander_reversement(cible text, montant bigint)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  solde jsonb;
  r     public.boutiques_reception%rowtype;
  qui   text := public.nom_du_compte();
  nouv  bigint;
begin
  if not public.gere_les_fonds(cible) then
    raise exception 'Seul l''administrateur de la boutique demande un reversement.';
  end if;
  -- Une demande à la fois par boutique : on la tranche avant la suivante.
  perform 1 from public.boutiques b where b.id = cible for update;
  select * into r from public.boutiques_reception where boutique_id = cible;
  if r.boutique_id is null or r.tel = '' then
    raise exception 'Réglez d''abord le numéro qui recevra les fonds.' using errcode = 'P0001';
  end if;
  solde := public.solde_boutique(cible);
  if coalesce(montant, 0) <= 0 then
    raise exception 'Indiquez le montant à reverser.' using errcode = 'P0001';
  end if;
  if montant > (solde ->> 'disponible')::bigint then
    raise exception 'Le solde disponible est de % : vous ne pouvez pas demander plus.',
      public.montant_lisible((solde ->> 'disponible')::bigint, solde ->> 'devise') using errcode = 'P0001';
  end if;
  insert into public.reversements (boutique_id, montant, tel, reseau, titulaire, demande_par)
  values (cible, montant, r.tel, r.reseau, r.titulaire, qui)
  returning id into nouv;
  perform public.notifier(public.les_superadmins(), 'reversement_demande',
    'Reversement demandé : ' || public.montant_lisible(montant, solde ->> 'devise'),
    coalesce((select b.nom from public.boutiques b where b.id = cible), cible) || ' — à envoyer sur ' ||
      r.reseau || ' ' || r.tel || coalesce(' (' || nullif(r.titulaire, '') || ')', '') || '. Demandé par ' || qui || '.',
    '#/reversements', null, cible, true);
  return nouv;
end $$;
revoke all on function public.demander_reversement(text, bigint) from public, anon;
grant execute on function public.demander_reversement(text, bigint) to authenticated;

-- La liste : la boutique, les siens ; le superadministrateur, tous
-- (« cible » vide) ou ceux d'une boutique.
create or replace function public.reversements_liste(cible text default null)
returns table (id bigint, boutique_id text, nom_boutique text, montant bigint, tel text, reseau text,
               titulaire text, etat text, demande_par text, demande_le timestamptz, decide_par text,
               decide_le timestamptz, reference text, motif text, devise text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.est_super() or (cible is not null and public.tient_la_caisse(cible))) then
    return;
  end if;
  return query
    select v.id, v.boutique_id, coalesce(b.nom, '')::text, v.montant, v.tel, v.reseau, v.titulaire, v.etat,
           v.demande_par, v.demande_le, v.decide_par, v.decide_le, v.reference, v.motif,
           coalesce(nullif(b.devise, ''), 'FCFA')::text
      from public.reversements v left join public.boutiques b on b.id = v.boutique_id
     where cible is null or v.boutique_id = cible
     order by (v.etat = 'en_attente') desc, v.demande_le desc
     limit 200;
end $$;
revoke all on function public.reversements_liste(text) from public, anon;
grant execute on function public.reversements_liste(text) to authenticated;

-- LE SUPERADMINISTRATEUR TRANCHE. Validé : il a envoyé l'argent, et note
-- la référence de la transaction. Refusé : avec un motif ; le montant
-- revient au solde disponible.
create or replace function public.decider_reversement(cible bigint, accord boolean,
  reference text default '', motif text default '')
returns text
language plpgsql security definer set search_path = public as $$
declare
  v   public.reversements%rowtype;
  ref text := left(trim(coalesce(reference, '')), 60);
  pourquoi text := left(trim(coalesce(motif, '')), 300);
  dev text;
begin
  if not public.est_super() then
    raise exception 'Seul le superadministrateur valide un reversement.';
  end if;
  select * into v from public.reversements where id = cible for update;
  if not found then raise exception 'Demande introuvable.'; end if;
  if v.etat <> 'en_attente' then
    raise exception 'Cette demande est déjà tranchée.' using errcode = 'P0001';
  end if;
  if accord and length(ref) < 4 then
    raise exception 'Notez la référence de la transaction envoyée.' using errcode = 'P0001';
  end if;
  update public.reversements
     set etat = case when accord then 'valide' else 'refuse' end,
         decide_par = public.nom_du_compte(), decide_le = now(),
         reference = case when accord then ref else '' end, motif = pourquoi
   where id = cible;
  dev := coalesce((select nullif(b.devise, '') from public.boutiques b where b.id = v.boutique_id), 'FCFA');
  perform public.notifier(
    array(select p.id from public.profils p
           where p.actif and p.boutique_id = v.boutique_id and p.role = 'administrateur'),
    'reversement_decide',
    case when accord then 'Reversement envoyé : ' || public.montant_lisible(v.montant, dev)
         else 'Reversement refusé : ' || public.montant_lisible(v.montant, dev) end,
    case when accord then 'Envoyé sur ' || v.reseau || ' ' || v.tel || ' — référence ' || ref || '.'
         else 'BIZZOO a refusé la demande' || coalesce(' : « ' || nullif(pourquoi, '') || ' »', '') ||
              '. Le montant revient à votre solde.' end,
    '#/solde', null, v.boutique_id, true);
  return case when accord then 'valide' else 'refuse' end;
end $$;
revoke all on function public.decider_reversement(bigint, boolean, text, text) from public, anon;
grant execute on function public.decider_reversement(bigint, boolean, text, text) to authenticated;

-- =========================================================
-- Le solde des livreurs (3.64.0)
-- =========================================================
-- LES FRAIS DE LIVRAISON REVIENNENT AU LIVREUR qui porte la commande —
-- « taux_livreur » % (80) ; le reste à BIZZOO, qui a encaissé ces frais
-- en ligne avec l'acompte.
--
--   CRÉDITÉ   une fois la commande payée ET tout ce qu'il porte remis
--             (ses lignes « remise », ou annulées) : une ligne par
--             commande ET par livreur, au taux du jour, figée. Sans
--             attendre le « J'ai bien reçu » du client, qui peut ne
--             jamais venir. Depuis 3.66.0, TOUTES les courses comptent —
--             au kilomètre comme à l'ancien tarif par boutique ;
--   À VENIR   ses courses payées, pas encore remises ;
--   REVERSÉ   ses reversements validés par BIZZOO ;
--   EN ATTENTE ses demandes pas encore tranchées ;
--   DISPONIBLE crédité − reversé − en attente.
--
-- Comme pour les boutiques : il règle son numéro Mobile Money, demande
-- un montant, et le superadministrateur envoie l'argent puis valide avec
-- la référence de la transaction — ou refuse, avec un motif.
create table if not exists public.gains_livreurs (
  commande_id text primary key references public.commandes(id) on delete cascade,
  livreur_id  uuid references public.profils(id) on delete set null,
  frais       bigint not null default 0,
  taux        int not null default 80,
  montant     bigint not null default 0 check (montant >= 0),
  credite_le  timestamptz not null default now()
);
create index if not exists gains_livreur on public.gains_livreurs(livreur_id, credite_le desc);
alter table public.gains_livreurs enable row level security;
revoke all on public.gains_livreurs from anon, authenticated;
-- (3.66.0) UNE LIGNE PAR LIVREUR, et non plus par commande : une commande à
-- l'ancien tarif (frais par boutique) a parfois un livreur par boutique,
-- et chacun touche la part des boutiques qu'il a livrées.
alter table public.gains_livreurs add column if not exists id bigserial;
do $$
begin
  if exists (select 1 from pg_constraint
              where conname = 'gains_livreurs_pkey' and conrelid = 'public.gains_livreurs'::regclass
                and pg_get_constraintdef(oid) = 'PRIMARY KEY (commande_id)') then
    alter table public.gains_livreurs drop constraint gains_livreurs_pkey;
    alter table public.gains_livreurs add constraint gains_livreurs_pkey primary key (id);
  end if;
end $$;
create unique index if not exists gains_livreurs_une_fois on public.gains_livreurs(commande_id, livreur_id);
revoke all on sequence public.gains_livreurs_id_seq from anon, authenticated;

create table if not exists public.livreurs_reception (
  livreur_id uuid primary key references public.profils(id) on delete cascade,
  tel        text not null default '',
  reseau     text not null default '' check (reseau in ('', 'MTN', 'MOOV', 'CELTIIS')),
  titulaire  text not null default '',
  maj_le     timestamptz not null default now()
);
alter table public.livreurs_reception enable row level security;
revoke all on public.livreurs_reception from anon, authenticated;

create table if not exists public.reversements_livreurs (
  id          bigserial primary key,
  livreur_id  uuid references public.profils(id) on delete set null,
  nom_livreur text not null default '',
  montant     bigint not null check (montant > 0),
  tel         text not null default '',
  reseau      text not null default '',
  titulaire   text not null default '',
  etat        text not null default 'en_attente' check (etat in ('en_attente', 'valide', 'refuse')),
  demande_le  timestamptz not null default now(),
  decide_par  text not null default '',
  decide_le   timestamptz,
  reference   text not null default '',
  motif       text not null default ''
);
create index if not exists reversements_livreurs_livreur on public.reversements_livreurs(livreur_id, demande_le desc);
create index if not exists reversements_livreurs_attente on public.reversements_livreurs(demande_le) where etat = 'en_attente';
alter table public.reversements_livreurs enable row level security;
revoke all on public.reversements_livreurs from anon, authenticated;
revoke all on sequence public.reversements_livreurs_id_seq from anon, authenticated;

-- (3.66.0) LA PART DES FRAIS QUI REVIENT À UN LIVREUR sur une commande :
--   au kilomètre, les frais entiers — un seul livreur la porte ;
--   à l'ancien tarif, les frais des boutiques dont il livre les produits ;
--   plus ancienne encore (pas de frais par boutique), au prorata de ce
--   qu'il porte.
-- Une commande que personne n'a encore prise : celui qui la prendra la
-- portera entière. Une part annulée ne compte pas : pas de course, pas de
-- frais.
create or replace function public.part_frais_livreur(cible text, qui uuid) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare
  c          public.commandes%rowtype;
  f          numeric;
  siennes    int;
  confiees   int;
  part       numeric;
  brut_moi   numeric;
  brut_tout  numeric;
begin
  select * into c from public.commandes where id = cible;
  if not found then return 0; end if;
  f := greatest(0, coalesce(c.frais_livraison, 0));
  if f <= 0 then return 0; end if;
  select count(*) filter (where l.livreur_id = qui), count(*) filter (where l.livreur_id is not null)
    into siennes, confiees
    from public.commande_lignes l where l.commande_id = cible and l.etat <> 'annulee';
  if coalesce(siennes, 0) = 0 then
    return case when coalesce(confiees, 0) = 0 then f else 0 end;
  end if;
  if c.livraison is not null then return f; end if;
  if c.parts is not null and exists (select 1 from jsonb_each(c.parts) e(k, v)
                                      where coalesce((v ->> 'frais')::numeric, 0) > 0) then
    select coalesce(sum(coalesce((c.parts -> b.bou ->> 'frais')::numeric, 0)), 0) into part
      from (select distinct l.boutique_id as bou from public.commande_lignes l
             where l.commande_id = cible and l.livreur_id = qui and l.etat <> 'annulee') b;
    return least(f, part);
  end if;
  select coalesce(sum(l.prix * l.quantite) filter (where l.livreur_id = qui), 0),
         coalesce(sum(l.prix * l.quantite), 0)
    into brut_moi, brut_tout
    from public.commande_lignes l where l.commande_id = cible and l.etat <> 'annulee';
  if brut_tout <= 0 then return 0; end if;
  return round(f * brut_moi / brut_tout);
end $$;
revoke all on function public.part_frais_livreur(text, uuid) from public, anon, authenticated;

-- Ce que le livreur connecté gagne sur une commande : figé s'il est
-- crédité, sinon au taux du jour. Null quand il n'y a rien pour lui.
create or replace function public.gain_livreur(cible text) returns bigint
language plpgsql stable security definer set search_path = public as $$
declare g bigint; p numeric; t int;
begin
  select sum(x.montant)::bigint into g from public.gains_livreurs x
   where x.commande_id = cible and x.livreur_id = auth.uid();
  if g is not null then return g; end if;
  p := public.part_frais_livreur(cible, auth.uid());
  if coalesce(p, 0) <= 0 then return null; end if;
  select coalesce(x.taux_livreur, 80) into t from public.paiement x where x.id = 1;
  return floor(p * coalesce(t, 80) / 100.0)::bigint;
end $$;
revoke all on function public.gain_livreur(text) from public, anon, authenticated;

-- Créditer les livreurs d'une commande payée : chacun dès qu'il a remis
-- TOUT ce qu'il porte (3.66.0 : au kilomètre ou à l'ancien tarif).
-- Rejouable : une seule ligne par commande et par livreur. Rend ce que la
-- commande a rapporté à ses livreurs.
create or replace function public.crediter_livreur(cible text) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  c       public.commandes%rowtype;
  qui     uuid;
  t       int;
  part    numeric;
  gain    bigint;
  combien int;
begin
  select * into c from public.commandes where id = cible;
  if not found or c.etat <> 'payee' then return 0; end if;
  select coalesce(p.taux_livreur, 80) into t from public.paiement p where p.id = 1;
  -- Un compte livreur supprimé depuis n'a plus de solde : on le saute.
  for qui in select distinct l.livreur_id from public.commande_lignes l
              join public.profils p on p.id = l.livreur_id
              where l.commande_id = cible and l.etat = 'remise' loop
    if exists (select 1 from public.commande_lignes l
                where l.commande_id = cible and l.livreur_id = qui
                  and l.etat not in ('remise', 'annulee')) then
      continue;
    end if;
    part := public.part_frais_livreur(cible, qui);
    if coalesce(part, 0) <= 0 then continue; end if;
    gain := floor(part * coalesce(t, 80) / 100.0)::bigint;
    insert into public.gains_livreurs (commande_id, livreur_id, frais, taux, montant)
    values (cible, qui, part::bigint, coalesce(t, 80), gain)
    on conflict (commande_id, livreur_id) do nothing;
    get diagnostics combien = row_count;
    -- Un rattrapage prévient une fois par livreur, pas une fois par course.
    if combien > 0 and coalesce(current_setting('bizzoo.rattrapage', true), '') <> 'oui' then
      perform public.notifier(array[qui], 'gain_livraison',
        'Course payée : + ' || public.montant_lisible(gain, c.devise),
        'Commande ' || coalesce(c.numero, '') || ' remise — ' || public.montant_lisible(gain, c.devise) ||
          ' ajoutés à votre solde.',
        '#/gains', cible, null, false);
    end if;
  end loop;
  return coalesce((select sum(g.montant) from public.gains_livreurs g where g.commande_id = cible), 0)::bigint;
end $$;
revoke all on function public.crediter_livreur(text) from public, anon, authenticated;

-- À la remise de la dernière ligne, le livreur est crédité. Une panne ici
-- ne bloque jamais la remise : le solde se rattrape en rejouant
-- « crediter_livreur ».
create or replace function public.ligne_remise_credite() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.etat = 'remise' and old.etat is distinct from 'remise' then
    begin
      perform public.crediter_livreur(new.commande_id);
    exception when others then
      raise warning 'crediter_livreur(%) : %', new.commande_id, sqlerrm;
    end;
  end if;
  return null;
end $$;
drop trigger if exists lignes_creditent_livreur on public.commande_lignes;
create trigger lignes_creditent_livreur
  after update of etat on public.commande_lignes
  for each row execute function public.ligne_remise_credite();

-- Le solde d'un livreur : le sien, ou celui de n'importe lequel pour le
-- superadministrateur.
create or replace function public.solde_livreur(cible uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  qui uuid := coalesce(cible, auth.uid());
  gagne bigint; a_venir bigint; reverse bigint; attente bigint; t int;
  r public.livreurs_reception%rowtype;
begin
  if qui is null or not ((qui = auth.uid() and public.est_livreur()) or public.est_super()) then
    raise exception 'Ce solde n''est pas le vôtre.';
  end if;
  select coalesce(sum(g.montant), 0) into gagne from public.gains_livreurs g where g.livreur_id = qui;
  select coalesce(p.taux_livreur, 80) into t from public.paiement p where p.id = 1;
  select coalesce(sum(floor(public.part_frais_livreur(c.id, qui) * coalesce(t, 80) / 100.0)), 0)::bigint
    into a_venir
    from public.commandes c
   where c.etat = 'payee' and coalesce(c.frais_livraison, 0) > 0
     and not exists (select 1 from public.gains_livreurs g where g.commande_id = c.id and g.livreur_id = qui)
     and exists (select 1 from public.commande_lignes l
                  where l.commande_id = c.id and l.livreur_id = qui
                    and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison'));
  select coalesce(sum(v.montant) filter (where v.etat = 'valide'), 0),
         coalesce(sum(v.montant) filter (where v.etat = 'en_attente'), 0)
    into reverse, attente
    from public.reversements_livreurs v where v.livreur_id = qui;
  select * into r from public.livreurs_reception where livreur_id = qui;
  return jsonb_build_object(
    'gagne', gagne, 'a_venir', a_venir, 'reverse', reverse, 'en_attente', attente,
    'disponible', greatest(0, gagne - reverse - attente),
    'taux', coalesce(t, 80), 'devise', 'FCFA',
    'reception', case when r.livreur_id is null or r.tel = '' then null
                      else jsonb_build_object('tel', r.tel, 'reseau', r.reseau, 'titulaire', r.titulaire,
                                              'maj_le', r.maj_le) end,
    'courses', coalesce((select jsonb_agg(jsonb_build_object(
                  'commande_id', g.commande_id, 'numero', c.numero, 'frais', g.frais,
                  'taux', g.taux, 'montant', g.montant, 'credite_le', g.credite_le,
                  'vehicule', c.livraison ->> 'vehicule',
                  'distance_km', c.livraison -> 'distance_km') order by g.credite_le desc)
                 from (select * from public.gains_livreurs x where x.livreur_id = qui
                        order by x.credite_le desc limit 50) g
                 join public.commandes c on c.id = g.commande_id), '[]'::jsonb));
end $$;
revoke all on function public.solde_livreur(uuid) from public, anon;
grant execute on function public.solde_livreur(uuid) to authenticated;

-- SON NUMÉRO DE RÉCEPTION : le livreur le règle lui-même ; BIZZOO est
-- prévenu de chaque changement — c'est par là qu'on détournerait ses gains.
create or replace function public.regler_reception_livreur(tel text, reseau text, titulaire text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  moi      uuid := auth.uid();
  national text := regexp_replace(coalesce(tel, ''), '\D', '', 'g');
  res      text := upper(coalesce(reseau, ''));
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Seul un livreur règle son numéro de réception.';
  end if;
  national := regexp_replace(national, '^229', '');
  if length(national) = 8 then national := '01' || national; end if;
  if length(national) <> 10 or national !~ '^01[0-9]+' then
    raise exception 'Ce numéro n''a pas la forme d''un numéro béninois : dix chiffres commençant par 01.'
      using errcode = 'P0001';
  end if;
  if res not in ('MTN', 'MOOV', 'CELTIIS') then
    raise exception 'Choisissez le réseau du numéro : MTN, Moov ou Celtiis.' using errcode = 'P0001';
  end if;
  insert into public.livreurs_reception (livreur_id, tel, reseau, titulaire, maj_le)
  values (moi, national, res, left(trim(coalesce(titulaire, '')), 80), now())
  on conflict (livreur_id) do update
     set tel = excluded.tel, reseau = excluded.reseau, titulaire = excluded.titulaire, maj_le = now();
  perform public.notifier(public.les_superadmins(), 'reception_reglee',
    'Numéro de réception d''un livreur — ' || public.nom_du_compte(),
    public.nom_du_compte() || ' a réglé son numéro de réception : ' || res || ' ' || national ||
      coalesce(' (' || nullif(trim(coalesce(titulaire, '')), '') || ')', '') || '.',
    '#/reversements', null, null, false);
  return jsonb_build_object('tel', national, 'reseau', res);
end $$;
revoke all on function public.regler_reception_livreur(text, text, text) from public, anon;
grant execute on function public.regler_reception_livreur(text, text, text) to authenticated;

create or replace function public.demander_reversement_livreur(montant bigint)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  moi   uuid := auth.uid();
  solde jsonb;
  r     public.livreurs_reception%rowtype;
  qui   text := public.nom_du_compte();
  nouv  bigint;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Seul un livreur demande le reversement de ses gains.';
  end if;
  -- Une demande à la fois : on la tranche avant la suivante.
  perform 1 from public.profils p where p.id = moi for update;
  select * into r from public.livreurs_reception where livreur_id = moi;
  if r.livreur_id is null or r.tel = '' then
    raise exception 'Réglez d''abord le numéro qui recevra vos gains.' using errcode = 'P0001';
  end if;
  if coalesce(montant, 0) <= 0 then
    raise exception 'Indiquez le montant à reverser.' using errcode = 'P0001';
  end if;
  solde := public.solde_livreur(moi);
  if montant > (solde ->> 'disponible')::bigint then
    raise exception 'Votre solde disponible est de % : vous ne pouvez pas demander plus.',
      public.montant_lisible((solde ->> 'disponible')::bigint, 'FCFA') using errcode = 'P0001';
  end if;
  insert into public.reversements_livreurs (livreur_id, nom_livreur, montant, tel, reseau, titulaire)
  values (moi, qui, montant, r.tel, r.reseau, r.titulaire)
  returning id into nouv;
  perform public.notifier(public.les_superadmins(), 'reversement_demande',
    'Reversement demandé par un livreur : ' || public.montant_lisible(montant, 'FCFA'),
    qui || ' — à envoyer sur ' || r.reseau || ' ' || r.tel ||
      coalesce(' (' || nullif(r.titulaire, '') || ')', '') || '.',
    '#/reversements', null, null, true);
  return nouv;
end $$;
revoke all on function public.demander_reversement_livreur(bigint) from public, anon;
grant execute on function public.demander_reversement_livreur(bigint) to authenticated;

-- La liste : le livreur, les siennes ; le superadministrateur, toutes.
create or replace function public.reversements_livreurs_liste()
returns table (id bigint, livreur_id uuid, nom_livreur text, montant bigint, tel text, reseau text,
               titulaire text, etat text, demande_le timestamptz, decide_par text,
               decide_le timestamptz, reference text, motif text)
language plpgsql stable security definer set search_path = public as $$
declare moi uuid := auth.uid();
begin
  if moi is null or not (public.est_super() or public.est_livreur()) then return; end if;
  return query
    select v.id, v.livreur_id, v.nom_livreur, v.montant, v.tel, v.reseau, v.titulaire, v.etat,
           v.demande_le, v.decide_par, v.decide_le, v.reference, v.motif
      from public.reversements_livreurs v
     where public.est_super() or v.livreur_id = moi
     order by (v.etat = 'en_attente') desc, v.demande_le desc
     limit 200;
end $$;
revoke all on function public.reversements_livreurs_liste() from public, anon;
grant execute on function public.reversements_livreurs_liste() to authenticated;

create or replace function public.decider_reversement_livreur(cible bigint, accord boolean,
  reference text default '', motif text default '')
returns text
language plpgsql security definer set search_path = public as $$
declare
  v   public.reversements_livreurs%rowtype;
  ref text := left(trim(coalesce(reference, '')), 60);
  pourquoi text := left(trim(coalesce(motif, '')), 300);
begin
  if not public.est_super() then
    raise exception 'Seul le superadministrateur valide un reversement.';
  end if;
  select * into v from public.reversements_livreurs where id = cible for update;
  if not found then raise exception 'Demande introuvable.'; end if;
  if v.etat <> 'en_attente' then
    raise exception 'Cette demande est déjà tranchée.' using errcode = 'P0001';
  end if;
  if accord and length(ref) < 4 then
    raise exception 'Notez la référence de la transaction envoyée.' using errcode = 'P0001';
  end if;
  update public.reversements_livreurs
     set etat = case when accord then 'valide' else 'refuse' end,
         decide_par = public.nom_du_compte(), decide_le = now(),
         reference = case when accord then ref else '' end, motif = pourquoi
   where id = cible;
  perform public.notifier(array[v.livreur_id], 'reversement_decide',
    case when accord then 'Gains envoyés : ' || public.montant_lisible(v.montant, 'FCFA')
         else 'Reversement refusé : ' || public.montant_lisible(v.montant, 'FCFA') end,
    case when accord then 'Envoyé sur ' || v.reseau || ' ' || v.tel || ' — référence ' || ref || '.'
         else 'BIZZOO a refusé la demande' || coalesce(' : « ' || nullif(pourquoi, '') || ' »', '') ||
              '. Le montant revient à votre solde.' end,
    '#/gains', null, null, true);
  return case when accord then 'valide' else 'refuse' end;
end $$;
revoke all on function public.decider_reversement_livreur(bigint, boolean, text, text) from public, anon;
grant execute on function public.decider_reversement_livreur(bigint, boolean, text, text) to authenticated;

-- =========================================================
-- Les notifications push, application fermée (3.65.0)
-- =========================================================
-- UNE COURSE CONFIÉE, UNE COMMANDE PAYÉE : le téléphone doit sonner même
-- quand BIZZOO Admin est fermée ou en veille. L'application ouverte
-- sonne déjà toute seule (temps réel) ; fermée, il faut que la nouvelle
-- vienne de dehors — Firebase Cloud Messaging.
--
--   1. CHAQUE TÉLÉPHONE se déclare à la connexion : son jeton Firebase,
--      rattaché au compte connecté (« enregistrer_appareil ») ; il s'en
--      retire à la déconnexion (« oublier_appareil »).
--   2. UNE NOTIFICATION QUI SONNE (« sonne », posé par « notifier ») et
--      dont le destinataire a un téléphone déclaré déclenche un appel à
--      la fonction Edge « envoyer-push », par pg_net, APRÈS la
--      transaction : une notification annulée ne part pas.
--   3. LA FONCTION EDGE ne reçoit que le numéro de la notification. Elle
--      relit tout dans la base (« push_a_envoyer », serveur seul), qui
--      la marque envoyée au passage : un appel rejoué, ou forgé, ne fait
--      rien partir une seconde fois.
--
-- Sans pg_net, ou sans l'adresse de la fonction (« push_reglage »), rien
-- ne part et rien ne casse : les notifications s'écrivent comme avant.
create table if not exists public.appareils_push (
  jeton       text primary key check (length(jeton) between 20 and 4096),
  compte      uuid not null references auth.users(id) on delete cascade,
  application text not null default 'admin' check (application in ('admin', 'client')),
  maj_le      timestamptz not null default now()
);
create index if not exists appareils_push_compte on public.appareils_push(compte);
alter table public.appareils_push enable row level security;
revoke all on public.appareils_push from anon, authenticated;

-- L'adresse de la fonction Edge : propre à chaque projet Supabase.
create table if not exists public.push_reglage (
  id  int primary key default 1 check (id = 1),
  url text not null default '' check (url = '' or url ~ '^https://')
);
insert into public.push_reglage (id) values (1) on conflict (id) do nothing;
alter table public.push_reglage enable row level security;
revoke all on public.push_reglage from anon, authenticated;

alter table public.notifications add column if not exists push_le timestamptz;

-- Le téléphone se déclare. Un jeton passe d'un compte à l'autre quand on
-- change de compte sur le même téléphone : il suit le dernier connecté.
create or replace function public.enregistrer_appareil(jeton text, application text default 'admin')
returns boolean
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  moi uuid := auth.uid();
  j   text := trim(coalesce(jeton, ''));
  app text := case when application = 'client' then 'client' else 'admin' end;
begin
  if moi is null then return false; end if;
  if length(j) < 20 or length(j) > 4096 then
    raise exception 'Jeton de notification invalide.' using errcode = 'P0001';
  end if;
  insert into public.appareils_push (jeton, compte, application, maj_le)
  values (j, moi, app, clock_timestamp())
  on conflict (jeton) do update
     set compte = excluded.compte, application = excluded.application, maj_le = clock_timestamp();
  -- Dix téléphones au plus par compte : les plus anciens s'effacent.
  delete from public.appareils_push a
   where a.compte = moi
     and a.jeton not in (select x.jeton from public.appareils_push x
                          where x.compte = moi order by x.maj_le desc limit 10);
  return true;
end $$;
revoke all on function public.enregistrer_appareil(text, text) from public, anon;
grant execute on function public.enregistrer_appareil(text, text) to authenticated;

create or replace function public.oublier_appareil(jeton text)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return false; end if;
  delete from public.appareils_push a where a.jeton = trim(coalesce(oublier_appareil.jeton, ''))
     and a.compte = auth.uid();
  return found;
end $$;
revoke all on function public.oublier_appareil(text) from public, anon;
grant execute on function public.oublier_appareil(text) to authenticated;

-- Ce que la fonction Edge envoie : la notification et les téléphones de
-- son destinataire — une seule fois. Réservé au serveur.
create or replace function public.push_a_envoyer(cible bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare n public.notifications%rowtype;
begin
  update public.notifications x set push_le = now()
   where x.id = cible and x.push_le is null and x.sonne
     and x.cree_le > now() - interval '1 hour'
  returning * into n;
  if not found then return null; end if;
  return jsonb_build_object(
    'id', n.id, 'type', n.type, 'titre', n.titre, 'corps', n.corps, 'lien', n.lien,
    'commande_id', n.commande_id,
    'jetons', coalesce((select jsonb_agg(a.jeton order by a.maj_le desc)
                          from public.appareils_push a
                         where a.compte = n.destinataire and a.application = 'admin'), '[]'::jsonb));
end $$;
revoke all on function public.push_a_envoyer(bigint) from public, anon, authenticated;

-- Un jeton que Firebase ne connaît plus (application désinstallée) :
-- on l'oublie. Réservé au serveur.
create or replace function public.jeton_push_mort(jeton text)
returns void
language sql security definer set search_path = public as $$
  delete from public.appareils_push a where a.jeton = jeton_push_mort.jeton;
$$;
revoke all on function public.jeton_push_mort(text) from public, anon, authenticated;

-- LE DÉCLENCHEUR. Il ne fait qu'une demande, après la transaction ; il ne
-- bloque jamais l'écriture de la notification, quoi qu'il arrive.
create or replace function public.notification_pousse() returns trigger
language plpgsql security definer set search_path = public as $$
declare adresse text;
begin
  if not new.sonne then return null; end if;
  if to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then return null; end if;
  select r.url into adresse from public.push_reglage r where r.id = 1;
  if coalesce(adresse, '') = '' then return null; end if;
  if not exists (select 1 from public.appareils_push a
                  where a.compte = new.destinataire and a.application = 'admin') then
    return null;
  end if;
  begin
    perform net.http_post(adresse, jsonb_build_object('id', new.id),
      '{}'::jsonb, '{"Content-Type": "application/json"}'::jsonb, 10000);
  exception when others then
    raise warning 'notification_pousse(%) : %', new.id, sqlerrm;
  end;
  return null;
end $$;
drop trigger if exists notifications_poussent on public.notifications;
create trigger notifications_poussent
  after insert on public.notifications
  for each row execute function public.notification_pousse();

-- ---------- Temps réel ----------
-- Permet à l'application client d'être prévenue dès qu'un produit change,
-- sans avoir à être fermée et rouverte. Sans risque à ré-exécuter.
do $$
declare
  t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['boutique', 'boutiques', 'categories', 'sous_categories', 'produits',
                          'slides', 'commandes', 'commande_lignes', 'notifications',
                          'commandes_signaux'] loop
      if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
      ) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;

-- ---------- Stockage des photos ----------
insert into storage.buckets (id, name, public)
values ('produits', 'produits', true)
on conflict (id) do nothing;

-- Le seau est public : ce qu'on y dépose est servi depuis l'adresse du
-- projet. Une page HTML déposée là ressemblerait à une page de BIZZOO.
-- On n'y accepte donc que des images et des vidéos.
update storage.buckets
   set file_size_limit = 62914560,   -- 60 Mo, la limite des vidéos
       allowed_mime_types = array[
         'image/jpeg', 'image/png', 'image/webp', 'image/gif',
         'video/mp4', 'video/webm', 'video/quicktime']
 where id = 'produits';

drop policy if exists "photos lecture publique"   on storage.objects;
drop policy if exists "photos ecriture connectee" on storage.objects;
drop policy if exists "photos maj connectee"      on storage.objects;
drop policy if exists "photos suppression connectee" on storage.objects;
create policy "photos lecture publique" on storage.objects
  for select using (bucket_id = 'produits');

-- Le stockage suit les mêmes règles que les tables, dossier par dossier :
--   « enseigne/ »  — le slider et la publicité de BIZZOO, donc le
--                    superadministrateur seul. La table « slides » le
--                    réservait déjà ; les fichiers le sont maintenant
--                    aussi, sans quoi un administrateur de boutique
--                    pouvait remplacer ou effacer les affiches de
--                    l'enseigne ;
--   « slider/ »    — le slider d'une boutique : ses administrateurs ;
--   « boutique/ », « boutiques/ » — devantures et logos : idem ;
--   le reste       — les photos de produits : toute l'équipe.
create or replace function public.peut_deposer(chemin text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when chemin like 'enseigne/%'  then public.est_super()
    when chemin like 'slider/%'    then public.est_admin()
    when chemin like 'boutique/%'  then public.est_admin()
    when chemin like 'boutiques/%' then public.est_admin()
    else public.est_equipe()
  end;
$$;
grant execute on function public.peut_deposer(text) to authenticated;

create policy "photos ecriture connectee" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'produits' and public.peut_deposer(name));
create policy "photos maj connectee" on storage.objects
  for update to authenticated
  using (bucket_id = 'produits' and public.peut_deposer(name))
  with check (bucket_id = 'produits' and public.peut_deposer(name));
create policy "photos suppression connectee" on storage.objects
  for delete to authenticated
  using (bucket_id = 'produits' and public.peut_deposer(name));

-- ---------------------------------------------------------
-- 8. Retrouver ses commandes d'avant le compte
-- ---------------------------------------------------------
-- LE NUMÉRO DOIT ÊTRE VÉRIFIÉ. C'est toute la question : sans cela, il
-- suffirait de taper le numéro d'un voisin pour hériter de ses commandes,
-- de ses adresses et de ce qu'il achète.
create or replace function public.rattacher_mes_commandes() returns int
language plpgsql security definer set search_path = public as $$
declare moi uuid := auth.uid(); mien public.clients%rowtype; combien int;
begin
  if moi is null then return 0; end if;
  select * into mien from public.clients where id = moi;
  if not found or not mien.tel_verifie or coalesce(mien.tel, '') = '' then
    raise exception 'Vérifiez votre numéro pour retrouver vos commandes';
  end if;

  perform set_config('bizzoo.interne', 'oui', true);
  update public.commandes
     set client_id = moi
   where client_id is null
     and not compte_supprime
     and client_tel = mien.tel
     and cree_le > now() - interval '18 months';
  get diagnostics combien = row_count;
  return combien;
end $$;

revoke all on function public.rattacher_mes_commandes() from public, anon;
grant execute on function public.rattacher_mes_commandes() to authenticated;

-- ---------- Vérifier son numéro par SMS ----------
-- Un client entre chez BIZZOO par son NUMÉRO plutôt que par une adresse
-- e-mail, ou confirme le sien après s'être inscrit par e-mail. Dans les
-- deux cas c'est Supabase Auth qui envoie le code, le fait expirer et le
-- vérifie ; notre seul travail est de LIVRER le SMS (fonction Edge
-- « hook-sms-auth ») et d'en tirer les conséquences ici.
--
-- NOUS N'ÉCRIVONS AUCUN CODE : ni table, ni hachage, ni expiration, ni
-- compteur de tentatives. GoTrue sait déjà tout cela, et le fait dans un
-- schéma que l'application ne peut pas toucher. « clients.tel_verifie »
-- n'est que le reflet de « auth.users.phone_confirmed_at » — il n'existe
-- donc aucun chemin par lequel l'application pourrait se déclarer
-- vérifiée.

create or replace function public.tel_national(complet text, indicatif text default '229')
returns text
language sql immutable as $$
  select case
           when chiffres like indicatif || '%'
                and length(chiffres) > length(indicatif)
             then substr(chiffres, length(indicatif) + 1)
           else chiffres
         end
    from (select regexp_replace(coalesce(complet, ''), '\D', '', 'g') as chiffres) x;
$$;
revoke all on function public.tel_national(text, text) from public, anon, authenticated;

-- ---------- Quand GoTrue confirme un numéro ----------
-- LE POINT DÉLICAT : ce déclencheur tourne DANS la transaction de
-- « verify ». S'il lève quoi que ce soit, la vérification échoue alors
-- que le numéro vient d'être confirmé — et le client, qui a bien reçu
-- son SMS et bien tapé son code, voit une panne. Il avale donc tout.
--
-- Le prix de ce silence : une vérification peut aboutir chez GoTrue sans
-- que « clients » l'apprenne. D'où reconcilier_numeros_verifies(), plus
-- bas, qui rattrape.
create or replace function public.au_numero_confirme() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  national text;
begin
  -- Rien de neuf : ni une confirmation, ni un changement de numéro
  -- confirmé. On sort sans rien faire.
  if new.phone_confirmed_at is null then return new; end if;
  if tg_op = 'UPDATE'
     and old.phone_confirmed_at is not null
     and coalesce(old.phone, '') = coalesce(new.phone, '') then
    return new;
  end if;

  national := public.tel_national(new.phone, '229');
  if coalesce(national, '') = '' then return new; end if;

  -- Un compte de l'équipe qui confirme son numéro reste un compte
  -- d'équipe : lui poser une fiche client ferait de lui les deux à la
  -- fois, ce que « compte_unique » refuse — et à raison.
  if exists (select 1 from public.profils p where p.id = new.id and p.actif) then
    return new;
  end if;
  -- Un livreur créé par son numéro (« compte: equipe ») n'est pas un
  -- acheteur, même avant que sa fiche soit activée. Sans ce test, un
  -- Supabase réglé pour confirmer les numéros d'office lui poserait une
  -- fiche client à la création — et sa fiche d'équipe serait refusée.
  if coalesce(new.raw_user_meta_data ->> 'compte', '') = 'equipe' then
    return new;
  end if;

  -- Ce numéro est déjà vérifié ailleurs : on ne le vole pas. Le compte
  -- reste non vérifié, et l'application le dira en clair — mieux vaut un
  -- message qu'une contrainte violée au visage du client.
  if exists (select 1 from public.clients c
              where c.tel = national and c.tel_verifie and c.id <> new.id) then
    raise notice 'BIZZOO : le numéro % est déjà vérifié sur un autre compte', national;
    return new;
  end if;

  -- « bizzoo.verification » est ce qui distingue cette écriture d'une
  -- requête ordinaire : sans lui, le verrou de « clients » la refuserait.
  perform set_config('bizzoo.verification', 'oui', true);
  insert into public.clients (id, tel, indicatif, tel_verifie, nom)
  values (new.id, national, '229', true,
          left(coalesce(new.raw_user_meta_data ->> 'nom', ''), 120))
  on conflict (id) do update
    set tel = excluded.tel,
        indicatif = excluded.indicatif,
        tel_verifie = true,
        maj_le = now();
  perform set_config('bizzoo.verification', '', true);
  return new;
exception when others then
  /* On ne fait PAS échouer « verify » pour autant : le numéro est
     confirmé chez GoTrue, c'est ce qui compte. La réconciliation
     rattrapera. */
  raise notice 'BIZZOO : numéro confirmé mais fiche non mise à jour (%)', sqlerrm;
  return new;
end $$;

drop trigger if exists numero_confirme on auth.users;
create trigger numero_confirme
  after insert or update of phone, phone_confirmed_at on auth.users
  for each row execute function public.au_numero_confirme();

-- ---------- Rattraper ce que le silence aurait manqué ----------
-- Le déclencheur ci-dessus avale ses erreurs — il le faut. Cette
-- fonction rejoue le rapprochement pour tous les comptes dont GoTrue dit
-- le numéro confirmé et dont la fiche l'ignore. Réservée à l'enseigne,
-- relançable sans dommage.
create or replace function public.reconcilier_numeros_verifies() returns int
language plpgsql security definer set search_path = public as $$
declare
  u        record;
  national text;
  combien  int := 0;
begin
  if not public.est_super() then
    raise exception 'Réservé à BIZZOO';
  end if;
  perform set_config('bizzoo.verification', 'oui', true);
  for u in
    select au.id, au.phone, au.raw_user_meta_data
      from auth.users au
      join public.clients c on c.id = au.id
     where au.phone_confirmed_at is not null
       and (not c.tel_verifie
            or c.tel is distinct from public.tel_national(au.phone, '229'))
  loop
    national := public.tel_national(u.phone, '229');
    continue when coalesce(national, '') = '';
    continue when exists (select 1 from public.clients c
                           where c.tel = national and c.tel_verifie and c.id <> u.id);
    update public.clients
       set tel = national, indicatif = '229', tel_verifie = true, maj_le = now()
     where id = u.id;
    combien := combien + 1;
  end loop;
  perform set_config('bizzoo.verification', '', true);
  return combien;
end $$;

revoke all on function public.reconcilier_numeros_verifies()
  from public, anon, authenticated;
grant execute on function public.reconcilier_numeros_verifies() to authenticated;


-- =========================================================
-- Les avis des clients
--
-- Une note de 1 à 5 et quelques mots, sur un PRODUIT ou sur une
-- BOUTIQUE. Publics : un avis que personne ne lit ne sert à personne.
--
-- SEUL QUI A ACHETÉ DONNE SON AVIS, et seulement sur ce qu'il a acheté.
-- Sans cette règle, un avis ne vaut rien : un concurrent en poste dix
-- mauvais le matin, une boutique s'en écrit vingt bons l'après-midi, et
-- plus personne n'y croit — y compris pour les avis honnêtes.
--
-- ET L'ACHAT DOIT ÊTRE PAYÉ. Ouvrir une commande ne coûte rien et ne
-- prouve rien. C'est la ligne à ne pas retirer.
-- =========================================================

-- ---------- Les avis des clients ----------
create table if not exists public.avis (
  id          text primary key,
  client_id   uuid not null references public.clients(id) on delete cascade,
  -- Un avis porte sur un PRODUIT (« produit_id » rempli) ou sur la
  -- BOUTIQUE elle-même (« produit_id » à null). Dans les deux cas la
  -- boutique est connue : celle du produit, ou celle qu'on note.
  produit_id  text references public.produits(id) on delete cascade,
  boutique_id text not null references public.boutiques(id) on delete cascade,
  note        int not null check (note between 1 and 5),
  texte       text not null default '',
  -- Le nom affiché, figé le jour de l'avis. Changer de nom ne réécrit
  -- pas ce qu'on a signé — et « clients » reste fermée aux visiteurs,
  -- qui doivent pourtant lire les avis.
  auteur      text not null default '',
  -- La commande qui a servi de preuve. Gardée pour pouvoir répondre
  -- « cet avis vient bien d'un achat » le jour où on le conteste.
  commande_id text references public.commandes(id) on delete set null,
  -- La réponse de la boutique. Publique, comme l'avis.
  reponse     text not null default '',
  reponse_le  timestamptz,
  -- Le masquage, réservé à l'enseigne.
  masque      boolean not null default false,
  motif_masque text not null default '',
  cree_le     timestamptz not null default now(),
  maj_le      timestamptz not null default now()
);

alter table public.avis add column if not exists auteur text not null default '';
alter table public.avis add column if not exists commande_id text;
alter table public.avis add column if not exists reponse text not null default '';
alter table public.avis add column if not exists reponse_le timestamptz;
alter table public.avis add column if not exists masque boolean not null default false;
alter table public.avis add column if not exists motif_masque text not null default '';

-- UN SEUL AVIS PAR CIBLE. Deux index partiels plutôt qu'un seul : sur
-- un avis de boutique, « produit_id » est null — et null n'est égal à
-- rien, pas même à null. Un index unique ordinaire laisserait donc
-- passer autant d'avis de boutique qu'on veut.
create unique index if not exists avis_un_par_produit
  on public.avis(client_id, produit_id) where produit_id is not null;
create unique index if not exists avis_un_par_boutique
  on public.avis(client_id, boutique_id) where produit_id is null;

create index if not exists avis_produit on public.avis(produit_id, cree_le desc)
  where not masque;
create index if not exists avis_boutique on public.avis(boutique_id, cree_le desc)
  where not masque;

-- Les moyennes, là où le catalogue les lit déjà. L'application cliente
-- lit « produits » et « boutiques » avec la clé publiable, en un seul
-- appel : une étoile sur une carte ne doit pas coûter une requête de
-- plus par produit.
alter table public.produits  add column if not exists note_moyenne numeric(3,2);
alter table public.produits  add column if not exists nb_avis int not null default 0;
alter table public.boutiques add column if not exists note_moyenne numeric(3,2);
alter table public.boutiques add column if not exists nb_avis int not null default 0;

-- ---------- A-t-il acheté ? ----------
-- LE « payee » EST LA LIGNE À NE PAS RETIRER. Ouvrir une commande ne
-- coûte rien : sans lui, on en ouvre une, on ne la paie jamais, et l'on
-- écrit ce qu'on veut sur qui l'on veut.
create or replace function public.a_achete(cible_produit text, cible_boutique text)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
      from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
     where c.client_id = auth.uid()
       and c.etat = 'payee'
       and (cible_produit is null or l.produit_id = cible_produit)
       and (cible_boutique is null or l.boutique_id = cible_boutique)
  );
$$;
revoke all on function public.a_achete(text, text) from public, anon, authenticated;
grant execute on function public.a_achete(text, text) to authenticated;

-- La commande qui sert de preuve : la plus récente qui porte cet achat.
create or replace function public.commande_temoin(cible_produit text, cible_boutique text)
returns text
language sql stable security definer set search_path = public as $$
  select c.id
    from public.commande_lignes l
    join public.commandes c on c.id = l.commande_id
   where c.client_id = auth.uid()
     and c.etat = 'payee'
     and (cible_produit is null or l.produit_id = cible_produit)
     and (cible_boutique is null or l.boutique_id = cible_boutique)
   order by c.cree_le desc
   limit 1;
$$;
revoke all on function public.commande_temoin(text, text) from public, anon, authenticated;

-- ---------- Les moyennes suivent leurs avis ----------
-- Tenues par la base, jamais par un écran. Un avis masqué ne compte
-- plus : le masquer doit faire remonter la note, sinon masquer ne sert
-- à rien.
create or replace function public.avis_recalcule() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  p text := coalesce(new.produit_id, old.produit_id);
  b text := coalesce(new.boutique_id, old.boutique_id);
begin
  /* Ce drapeau est ce qui distingue ce calcul d'une écriture ordinaire :
     les verrous de « produits » et de « boutiques » refusent la note à
     tout le reste, y compris à l'enseigne. Il ne vaut que le temps de
     cette transaction, et ne s'attrape pas depuis PostgREST. */
  perform set_config('bizzoo.avis', 'oui', true);
  if p is not null then
    update public.produits x
       set note_moyenne = (select round(avg(a.note), 2) from public.avis a
                            where a.produit_id = x.id and not a.masque),
           nb_avis      = (select count(*) from public.avis a
                            where a.produit_id = x.id and not a.masque)
     where x.id = p;
  end if;
  if b is not null then
    /* La note d'une boutique est celle qu'on lui donne À ELLE — la
       livraison, l'accueil, le sérieux — pas la moyenne des notes de
       ses produits. Les deux questions sont différentes, et les
       mélanger rendrait les deux illisibles. */
    update public.boutiques x
       set note_moyenne = (select round(avg(a.note), 2) from public.avis a
                            where a.boutique_id = x.id and a.produit_id is null
                              and not a.masque),
           nb_avis      = (select count(*) from public.avis a
                            where a.boutique_id = x.id and a.produit_id is null
                              and not a.masque)
     where x.id = b;
  end if;
  -- Rendu tel qu'il était : il ne vaut que pour ce qu'on vient d'écrire.
  perform set_config('bizzoo.avis', '', true);
  return null;
end $$;

drop trigger if exists avis_moyennes on public.avis;
create trigger avis_moyennes
  after insert or update or delete on public.avis
  for each row execute function public.avis_recalcule();

-- ---------- Déposer un avis ----------
-- AUCUNE RÈGLE D'ÉCRITURE DIRECTE sur « avis » : tout passe par ici.
-- C'est ce qui permet de relire la boutique DANS LE CATALOGUE plutôt
-- que de la croire sur parole — sans quoi on achèterait un article à
-- trois francs chez l'un pour aller noter l'autre.
create or replace function public.deposer_avis(
  cible_produit text, cible_boutique text, note int, texte text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  moi       uuid := auth.uid();
  boutique  text;
  temoin    text;
  nom       text;
  identifie text;
  existant  text;
begin
  if moi is null then
    raise exception 'Connectez-vous pour donner votre avis';
  end if;
  if not exists (select 1 from public.clients c where c.id = moi) then
    raise exception 'Seuls les acheteurs donnent leur avis';
  end if;
  if note is null or note < 1 or note > 5 then
    raise exception 'Une note va de 1 à 5 étoiles';
  end if;

  -- La boutique vient du CATALOGUE. Ce que la requête en dit n'est lu
  -- que pour un avis de boutique, et vérifié juste après.
  if coalesce(cible_produit, '') <> '' then
    select p.boutique_id into boutique
      from public.produits p where p.id = cible_produit;
    if boutique is null then
      raise exception 'Ce produit n''existe plus';
    end if;
  else
    cible_produit := null;
    boutique := nullif(trim(coalesce(cible_boutique, '')), '');
    if boutique is null
       or not exists (select 1 from public.boutiques b where b.id = boutique) then
      raise exception 'Boutique inconnue';
    end if;
  end if;

  if not public.a_achete(cible_produit, boutique) then
    raise exception 'Seuls les acheteurs donnent leur avis : cet achat n''a pas été réglé';
  end if;
  temoin := public.commande_temoin(cible_produit, boutique);

  -- Le prénom seul : un avis se signe, il ne livre pas un annuaire.
  select coalesce(c.nom, '') into nom from public.clients c where c.id = moi;
  identifie := left(coalesce(nullif(split_part(trim(nom), ' ', 1), ''), 'Client'), 40);

  /* Un avis existe déjà ? On le remplace — on change d'avis, c'est le
     mot. « is not distinct from » et non « = » : sur un avis de
     boutique, « produit_id » est null, et null n'est égal à rien, pas
     même à null. Avec « = », on en déposerait un second à chaque fois. */
  select a.id into existant
    from public.avis a
   where a.client_id = moi
     and a.boutique_id = boutique
     and a.produit_id is not distinct from cible_produit;

  if existant is not null then
    update public.avis
       set note = deposer_avis.note,
           texte = left(coalesce(trim(deposer_avis.texte), ''), 1000),
           auteur = identifie,
           maj_le = now()
     where id = existant;
  else
    existant := 'avi_' || replace(gen_random_uuid()::text, '-', '');
    insert into public.avis
      (id, client_id, produit_id, boutique_id, note, texte, auteur, commande_id)
    values (existant, moi, cible_produit, boutique,
            deposer_avis.note, left(coalesce(trim(deposer_avis.texte), ''), 1000),
            identifie, temoin);
  end if;

  return jsonb_build_object('id', existant, 'note', deposer_avis.note);
end $$;

revoke all on function public.deposer_avis(text, text, int, text)
  from public, anon, authenticated;
grant execute on function public.deposer_avis(text, text, int, text) to authenticated;

-- Retirer son propre avis. On a le droit de se taire.
create or replace function public.retirer_mon_avis(cible text) returns boolean
language plpgsql security definer set search_path = public as $$
declare combien int;
begin
  if auth.uid() is null then return false; end if;
  delete from public.avis a where a.id = cible and a.client_id = auth.uid();
  get diagnostics combien = row_count;
  return combien > 0;
end $$;
revoke all on function public.retirer_mon_avis(text) from public, anon, authenticated;
grant execute on function public.retirer_mon_avis(text) to authenticated;

-- ---------- Ce que la boutique peut, et ce qu'elle ne peut pas ----------
-- ELLE RÉPOND. Elle ne supprime pas, elle ne modifie pas, elle ne
-- masque pas : une boutique qui efface ce qui la gêne rend tous les
-- avis sans valeur, y compris les bons.
create or replace function public.repondre_avis(cible text, texte text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare vise public.avis%rowtype;
begin
  select * into vise from public.avis where id = cible;
  if not found then raise exception 'Avis introuvable'; end if;
  if not public.peut_agir_sur(vise.boutique_id) then
    raise exception 'Cet avis ne concerne pas votre boutique';
  end if;
  /* « repondre_avis.texte » et non « texte » : la table porte une
     colonne du même nom, et PostgreSQL ne devine pas laquelle on veut.
     Il s'arrête sur « column reference is ambiguous » — à l'exécution,
     jamais à la création. */
  update public.avis
     set reponse = left(coalesce(trim(repondre_avis.texte), ''), 1000),
         reponse_le = case when coalesce(trim(repondre_avis.texte), '') = ''
                           then null else now() end,
         maj_le = now()
   where id = cible;
  return true;
end $$;
revoke all on function public.repondre_avis(text, text) from public, anon, authenticated;
grant execute on function public.repondre_avis(text, text) to authenticated;

-- MASQUER EST RÉSERVÉ À L'ENSEIGNE, et pour ce qui n'a pas sa place :
-- insultes, numéro de téléphone, règlement de comptes. Pas pour une
-- mauvaise note — une mauvaise note est une information.
create or replace function public.masquer_avis(cible text, cacher boolean, raison text default '')
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not public.est_super() then
    raise exception 'Seul BIZZOO masque un avis';
  end if;
  update public.avis
     set masque = coalesce(cacher, true),
         motif_masque = left(coalesce(trim(raison), ''), 300),
         maj_le = now()
   where id = cible;
  if not found then raise exception 'Avis introuvable'; end if;
  return true;
end $$;
revoke all on function public.masquer_avis(text, boolean, text)
  from public, anon, authenticated;
grant execute on function public.masquer_avis(text, boolean, text) to authenticated;

-- ---------- Qui lit quoi ----------
alter table public.avis enable row level security;

drop policy if exists "avis lecture publique" on public.avis;
drop policy if exists "avis lecture equipe"   on public.avis;

-- Les avis sont PUBLICS : un avis que personne ne lit ne sert à rien.
-- Les masqués disparaissent pour tout le monde sauf l'équipe, qui doit
-- pouvoir vérifier ce qu'elle a masqué.
create policy "avis lecture publique" on public.avis
  for select using (not masque);
create policy "avis lecture equipe" on public.avis
  for select to authenticated
  using (public.est_super() or public.peut_agir_sur(boutique_id));

-- AUCUNE règle d'écriture : ni pour le client, ni pour la boutique.
-- Tout passe par les fonctions ci-dessus, qui vérifient l'achat et
-- relisent la boutique dans le catalogue.
revoke all on public.avis from anon, authenticated;
grant select on public.avis to anon, authenticated;


-- =========================================================
-- Le service après-vente
--
-- LA BOUTIQUE D'ABORD, BIZZOO EN RECOURS.
--
-- La réclamation va à la boutique : c'est elle qui a vendu, elle qui a
-- la marchandise, elle qui peut remplacer le jour même. BIZZOO n'entre
-- qu'ensuite, et par deux portes seulement : la boutique a répondu et
-- le client n'est pas d'accord, ou elle n'a PAS répondu passé le délai.
--
-- Sans cette condition, « la boutique d'abord » ne serait qu'une
-- phrase : chacun escaladerait à la seconde même.
--
-- Et la boutique ne CLÔT pas ce qui la met en cause. Elle répond. C'est
-- le client qui dit « c'est réglé », ou l'enseigne qui tranche.
-- =========================================================

-- ---------- Le délai au bout duquel le silence vaut réponse ----------
-- Quarante-huit heures. Assez pour qu'une boutique fermée le
-- dimanche ne se fasse pas déborder ; assez court pour qu'un client
-- resté sans nouvelle ne soit pas prisonnier de ce silence.
--
-- Une fonction plutôt qu'un nombre écrit à dix endroits : le jour où
-- ce délai change, il change ici.
create or replace function public.delai_sav() returns interval
language sql immutable as $$ select interval '48 hours'; $$;

-- ---------- La réclamation ----------
create table if not exists public.reclamations (
  id          text primary key,
  client_id   uuid not null references public.clients(id) on delete cascade,
  -- Une réclamation SANS commande n'est pas une réclamation, c'est une
  -- question : elle a son chemin, le numéro WhatsApp de la boutique.
  commande_id text not null references public.commandes(id) on delete cascade,
  -- La boutique concernée, relue dans la COMMANDE. Jamais dans la
  -- requête : sinon on réclamerait chez l'une pour un achat fait chez
  -- l'autre.
  boutique_id text not null references public.boutiques(id) on delete cascade,
  -- L'article visé, quand il y en a un. À null, c'est toute la
  -- commande — « rien reçu » ne désigne aucun article en particulier.
  produit_id  text references public.produits(id) on delete set null,
  sujet       text not null default 'autre',
  --   'ouverte'   — la boutique doit répondre
  --   'repondue'  — elle a répondu, le client lit
  --   'resolue'   — le client dit que c'est réglé
  --   'escaladee' — BIZZOO est appelée en recours
  --   'tranchee'  — BIZZOO a décidé ; c'est fini
  etat        text not null default 'ouverte',
  escalade_le     timestamptz,
  escalade_motif  text not null default '',
  decision        text not null default '',
  decide_par      text not null default '',
  decide_le       timestamptz,
  -- Quand la boutique a répondu la première fois. C'est ce qui ouvre
  -- la porte du recours, avec le délai.
  repondu_le  timestamptz,
  cree_le     timestamptz not null default now(),
  maj_le      timestamptz not null default now()
);

alter table public.reclamations add column if not exists produit_id text
  references public.produits(id) on delete set null;
alter table public.reclamations add column if not exists escalade_le timestamptz;
alter table public.reclamations add column if not exists escalade_motif text not null default '';
alter table public.reclamations add column if not exists decision text not null default '';
alter table public.reclamations add column if not exists decide_par text not null default '';
alter table public.reclamations add column if not exists decide_le timestamptz;
alter table public.reclamations add column if not exists repondu_le timestamptz;

alter table public.reclamations drop constraint if exists reclamations_sujet;
alter table public.reclamations add constraint reclamations_sujet
  check (sujet in ('non_recu', 'abime', 'pas_conforme', 'incomplet', 'autre'));
alter table public.reclamations drop constraint if exists reclamations_etat;
alter table public.reclamations add constraint reclamations_etat
  check (etat in ('ouverte', 'repondue', 'resolue', 'escaladee', 'tranchee'));

create index if not exists reclamations_boutique
  on public.reclamations(boutique_id, cree_le desc);
create index if not exists reclamations_client
  on public.reclamations(client_id, cree_le desc);
create index if not exists reclamations_recours
  on public.reclamations(escalade_le desc) where etat = 'escaladee';

-- Une réclamation est une CONVERSATION, pas un formulaire. Un seul
-- champ « réponse » forcerait à écraser ce qui a été dit : le client
-- n'aurait plus de quoi montrer ce qu'on lui avait promis.
create table if not exists public.reclamation_messages (
  id             text primary key,
  reclamation_id text not null references public.reclamations(id) on delete cascade,
  -- 'client' | 'boutique' | 'enseigne' — écrit par la base, jamais
  -- envoyé par l'application.
  auteur_role    text not null default 'client',
  auteur_nom     text not null default '',
  texte          text not null default '',
  cree_le        timestamptz not null default now()
);
alter table public.reclamation_messages drop constraint if exists reclamation_messages_role;
alter table public.reclamation_messages add constraint reclamation_messages_role
  check (auteur_role in ('client', 'boutique', 'enseigne'));
create index if not exists reclamation_messages_fil
  on public.reclamation_messages(reclamation_id, cree_le);

-- ---------- Qui lit quoi ----------
-- « security definer » : sans elle, la règle des messages
-- interrogerait les réclamations, dont la règle interrogerait les
-- messages — PostgreSQL s'arrête sur « infinite recursion detected in
-- policy ». Même remède que pour les commandes.
create or replace function public.ma_reclamation(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.reclamations r
     where r.id = cible
       and (r.client_id = auth.uid()
            or public.est_super()
            or public.peut_agir_sur(r.boutique_id)));
$$;
revoke all on function public.ma_reclamation(text) from public, anon, authenticated;
grant execute on function public.ma_reclamation(text) to authenticated;

alter table public.reclamations         enable row level security;
alter table public.reclamation_messages enable row level security;

drop policy if exists "reclamations lecture"  on public.reclamations;
drop policy if exists "messages sav lecture"  on public.reclamation_messages;

-- Le client voit les siennes ; la boutique celles qui la concernent ;
-- l'enseigne toutes — c'est elle le recours, elle doit pouvoir juger
-- sur pièces, et voir venir ce qui va lui remonter.
create policy "reclamations lecture" on public.reclamations
  for select to authenticated
  using (client_id = auth.uid()
         or public.est_super()
         or public.peut_agir_sur(boutique_id));

create policy "messages sav lecture" on public.reclamation_messages
  for select to authenticated
  using (public.ma_reclamation(reclamation_id));

-- AUCUNE règle d'écriture, d'aucun côté : tout passe par les fonctions
-- ci-dessous, qui relisent la commande et vérifient l'état.
revoke all on public.reclamations         from anon, authenticated;
revoke all on public.reclamation_messages from anon, authenticated;
grant select on public.reclamations         to authenticated;
grant select on public.reclamation_messages to authenticated;

-- ---------- Ouvrir une réclamation ----------
create or replace function public.ouvrir_reclamation(
  commande text, produit text, sujet text, message text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  moi      uuid := auth.uid();
  c        public.commandes%rowtype;
  boutique text;
  nom      text;
  nouvelle text;
begin
  if moi is null then
    raise exception 'Connectez-vous pour ouvrir une réclamation';
  end if;

  select * into c from public.commandes where id = commande;
  if not found or c.client_id is distinct from moi then
    raise exception 'Cette commande n''est pas la vôtre';
  end if;
  -- MÊME RAISON QUE POUR LES AVIS : une commande ouverte et jamais
  -- réglée ne coûte rien, donc ne prouve rien.
  if c.etat <> 'payee' then
    raise exception 'Une réclamation se fait sur une commande payée';
  end if;

  -- La boutique vient de la COMMANDE. Un produit précisé doit en faire
  -- partie ; sinon on désignerait un article qu'on n'a pas acheté.
  if coalesce(produit, '') <> '' then
    select l.boutique_id into boutique
      from public.commande_lignes l
     where l.commande_id = c.id and l.produit_id = produit
     limit 1;
    if boutique is null then
      raise exception 'Cet article ne figure pas dans cette commande';
    end if;
  else
    produit := null;
    -- Une commande peut traverser plusieurs boutiques. Sans article
    -- précisé, la réclamation va à celle qui en a livré le plus —
    -- c'est la plus concernée, et le client peut en ouvrir une autre.
    select l.boutique_id into boutique
      from public.commande_lignes l
     where l.commande_id = c.id
     group by l.boutique_id
     order by sum(l.prix * l.quantite) desc
     limit 1;
    if boutique is null then
      raise exception 'Cette commande ne contient aucun article';
    end if;
  end if;

  if coalesce(sujet, '') not in ('non_recu', 'abime', 'pas_conforme', 'incomplet') then
    sujet := 'autre';
  end if;

  select coalesce(cl.nom, '') into nom from public.clients cl where cl.id = moi;
  nouvelle := 'sav_' || replace(gen_random_uuid()::text, '-', '');

  insert into public.reclamations
    (id, client_id, commande_id, boutique_id, produit_id, sujet, etat)
  values (nouvelle, moi, c.id, boutique, produit, sujet, 'ouverte');

  insert into public.reclamation_messages
    (id, reclamation_id, auteur_role, auteur_nom, texte)
  values ('msg_' || replace(gen_random_uuid()::text, '-', ''),
          nouvelle, 'client',
          left(coalesce(nullif(split_part(trim(nom), ' ', 1), ''), 'Client'), 40),
          left(coalesce(trim(message), ''), 2000));

  return jsonb_build_object('id', nouvelle, 'boutique', boutique);
end $$;

revoke all on function public.ouvrir_reclamation(text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.ouvrir_reclamation(text, text, text, text) to authenticated;

-- ---------- Répondre — des deux côtés ----------
-- Le client et la boutique écrivent dans le même fil. C'est la base
-- qui décide QUI parle, à partir du jeton : un rôle envoyé dans la
-- requête ne vaudrait rien.
create or replace function public.repondre_reclamation(cible text, message text)
returns text
language plpgsql security definer set search_path = public as $$
declare
  r     public.reclamations%rowtype;
  role  text;
  nom   text;
begin
  select * into r from public.reclamations where id = cible;
  if not found then raise exception 'Réclamation introuvable'; end if;
  if coalesce(trim(message), '') = '' then
    raise exception 'Écrivez votre message';
  end if;

  if r.client_id = auth.uid() then
    role := 'client';
    select coalesce(nullif(split_part(trim(coalesce(cl.nom, '')), ' ', 1), ''), 'Client')
      into nom from public.clients cl where cl.id = auth.uid();
  elsif public.est_super() then
    role := 'enseigne';
    select coalesce(p.email, 'BIZZOO') into nom
      from public.profils p where p.id = auth.uid();
  elsif public.peut_agir_sur(r.boutique_id) then
    role := 'boutique';
    select coalesce(b.nom, 'La boutique') into nom
      from public.boutiques b where b.id = r.boutique_id;
  else
    raise exception 'Cette réclamation ne vous concerne pas';
  end if;

  if r.etat in ('resolue', 'tranchee') then
    raise exception 'Cette réclamation est close';
  end if;

  insert into public.reclamation_messages
    (id, reclamation_id, auteur_role, auteur_nom, texte)
  values ('msg_' || replace(gen_random_uuid()::text, '-', ''),
          r.id, role, left(nom, 80), left(trim(message), 2000));

  /* La première réponse de la boutique ouvre la porte du recours : à
     partir de là, le client peut ne pas être d'accord. Avant, il n'a
     rien à contester — d'où « repondu_le », et non un simple état. */
  update public.reclamations
     set etat = case when role = 'boutique' and etat = 'ouverte' then 'repondue'
                     else etat end,
         repondu_le = case when role = 'boutique' and repondu_le is null
                           then now() else repondu_le end,
         maj_le = now()
   where id = r.id;

  return role;
end $$;

revoke all on function public.repondre_reclamation(text, text)
  from public, anon, authenticated;
grant execute on function public.repondre_reclamation(text, text) to authenticated;

-- ---------- Le recours — et ce qui l'ouvre ----------
-- LE CŒUR DE CE FICHIER. Deux portes seulement mènent à l'enseigne :
--
--   — la boutique a répondu, et le client n'est pas d'accord ;
--   — la boutique N'A PAS répondu passé le délai.
--
-- Sans cette condition, « la boutique d'abord » ne serait qu'une
-- phrase : chacun escaladerait à la seconde même, et l'enseigne ferait
-- le travail de ses boutiques.
create or replace function public.recours_possible(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.reclamations r
     where r.id = cible
       and r.client_id = auth.uid()
       and (r.etat = 'repondue'
            or (r.etat = 'ouverte' and r.cree_le < now() - public.delai_sav())));
$$;
revoke all on function public.recours_possible(text) from public, anon, authenticated;
grant execute on function public.recours_possible(text) to authenticated;

create or replace function public.escalader_reclamation(cible text, motif text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare r public.reclamations%rowtype;
begin
  select * into r from public.reclamations where id = cible;
  if not found then raise exception 'Réclamation introuvable'; end if;
  if r.client_id is distinct from auth.uid() then
    raise exception 'Seul le client appelle BIZZOO en recours';
  end if;
  if r.etat in ('resolue', 'tranchee') then
    raise exception 'Cette réclamation est close';
  end if;
  if r.etat = 'escaladee' then
    raise exception 'BIZZOO a déjà été saisie';
  end if;
  if not public.recours_possible(cible) then
    raise exception 'Laissez d''abord à la boutique le temps de répondre : BIZZOO n''intervient qu''ensuite';
  end if;

  update public.reclamations
     set etat = 'escaladee', escalade_le = now(),
         escalade_motif = left(coalesce(trim(motif), ''), 500), maj_le = now()
   where id = cible;
  return true;
end $$;
revoke all on function public.escalader_reclamation(text, text)
  from public, anon, authenticated;
grant execute on function public.escalader_reclamation(text, text) to authenticated;

-- ---------- Clore — et qui en a le droit ----------
-- LE CLIENT dit « c'est réglé ». Pas la boutique : celle-ci fermerait
-- ce qui la gêne, et le SAV ne serait plus qu'un formulaire.
create or replace function public.clore_reclamation(cible text) returns boolean
language plpgsql security definer set search_path = public as $$
declare r public.reclamations%rowtype;
begin
  select * into r from public.reclamations where id = cible;
  if not found then raise exception 'Réclamation introuvable'; end if;
  if r.client_id is distinct from auth.uid() then
    raise exception 'Seul le client dit que son problème est réglé';
  end if;
  if r.etat = 'tranchee' then
    raise exception 'BIZZOO a déjà tranché';
  end if;
  update public.reclamations set etat = 'resolue', maj_le = now() where id = cible;
  return true;
end $$;
revoke all on function public.clore_reclamation(text) from public, anon, authenticated;
grant execute on function public.clore_reclamation(text) to authenticated;

-- L'ENSEIGNE TRANCHE, et seulement ce qui lui a été remonté. Trancher
-- une réclamation que la boutique traite encore, ce serait lui retirer
-- le dossier des mains sans qu'on le lui ait demandé.
create or replace function public.trancher_reclamation(cible text, verdict text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  r   public.reclamations%rowtype;
  qui text;
begin
  if not public.est_super() then
    raise exception 'Seule BIZZOO tranche un recours';
  end if;
  select * into r from public.reclamations where id = cible;
  if not found then raise exception 'Réclamation introuvable'; end if;
  if r.etat <> 'escaladee' then
    raise exception 'BIZZOO ne tranche que ce qui lui est remonté';
  end if;
  if coalesce(trim(verdict), '') = '' then
    raise exception 'Dites votre décision : les deux parties la liront';
  end if;

  select coalesce(p.email, '') into qui from public.profils p where p.id = auth.uid();
  insert into public.reclamation_messages
    (id, reclamation_id, auteur_role, auteur_nom, texte)
  values ('msg_' || replace(gen_random_uuid()::text, '-', ''),
          r.id, 'enseigne', left(coalesce(qui, 'BIZZOO'), 80),
          left(trim(verdict), 2000));

  update public.reclamations
     set etat = 'tranchee', decision = left(trim(verdict), 2000),
         decide_par = coalesce(qui, ''), decide_le = now(), maj_le = now()
   where id = cible;
  return true;
end $$;
revoke all on function public.trancher_reclamation(text, text)
  from public, anon, authenticated;
grant execute on function public.trancher_reclamation(text, text) to authenticated;

-- =========================================================
-- Ce que le client garde pour lui
--
-- Trois choses appartiennent au client et à personne d'autre : ce
-- qu'il met de côté, les boutiques qu'il suit, et les adresses où il
-- se fait livrer.
--
-- CE N'EST PAS DE LA DONNÉE DE VENTE, C'EST DE LA DONNÉE DE VIE.
-- Une liste de favoris dit ce qu'on hésite à s'offrir ; une liste
-- d'adresses dit où l'on dort et où l'on travaille. L'enseigne n'en a
-- aucun besoin pour faire son métier, et « est_super() » n'ouvre donc
-- AUCUNE de ces trois portes — contrairement à presque toutes les
-- autres tables de ce fichier. Un superadministrateur curieux ne lit
-- pas les favoris de ses clients.
--
-- Ce qui sort de là ressort au moment de commander, et seulement
-- parce que le client l'a choisi lui-même à l'écran.
-- =========================================================

-- ---------- Les produits mis de côté ----------
create table if not exists public.favoris (
  client_id  uuid not null references public.clients(id) on delete cascade,
  produit_id text not null references public.produits(id) on delete cascade,
  cree_le    timestamptz not null default now(),
  primary key (client_id, produit_id)
);

-- ---------- Les boutiques qu'on suit ----------
create table if not exists public.boutiques_suivies (
  client_id   uuid not null references public.clients(id) on delete cascade,
  boutique_id text not null references public.boutiques(id) on delete cascade,
  cree_le     timestamptz not null default now(),
  primary key (client_id, boutique_id)
);

-- La liste se lit dans l'ordre où on l'a remplie, le dernier d'abord.
create index if not exists favoris_du_client
  on public.favoris(client_id, cree_le desc);
create index if not exists suivies_du_client
  on public.boutiques_suivies(client_id, cree_le desc);

-- ---------- Les adresses de livraison ----------
create table if not exists public.adresses (
  id         text primary key,
  client_id  uuid not null references public.clients(id) on delete cascade,
  libelle    text not null default '',        -- « Maison », « Bureau »
  texte      text not null default '',        -- ce qu'on dit au livreur
  ville      text not null default '',
  par_defaut boolean not null default false,
  cree_le    timestamptz not null default now(),
  maj_le     timestamptz not null default now()
);
create index if not exists adresses_du_client
  on public.adresses(client_id, cree_le desc);

-- UNE SEULE ADRESSE PAR DÉFAUT, et l'index le garantit plutôt que
-- l'application. Deux adresses par défaut, c'est un formulaire de
-- commande qui en choisit une au hasard — et un colis chez l'autre.
create unique index if not exists adresses_une_par_defaut
  on public.adresses(client_id) where par_defaut;

-- L'index REFUSE la deuxième ; le déclencheur fait en sorte qu'on n'ait
-- jamais à la refuser. Sans lui, cocher « par défaut » sur une nouvelle
-- adresse renverrait une erreur de contrainte au client, qui devrait
-- décocher l'ancienne lui-même. Les deux se complètent : le
-- déclencheur pour que ce soit utilisable, l'index pour que ce soit vrai.
create or replace function public.adresse_une_seule_defaut() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.par_defaut then
    update public.adresses
       set par_defaut = false, maj_le = now()
     where client_id = new.client_id
       and par_defaut
       and id <> new.id;
  end if;
  new.maj_le := now();
  return new;
end $$;
drop trigger if exists adresses_defaut on public.adresses;
create trigger adresses_defaut before insert or update on public.adresses
  for each row execute function public.adresse_une_seule_defaut();

-- ---------- Les portes ----------
-- CHACUN CHEZ SOI, sans exception. « client_id = auth.uid() » des deux
-- côtés de chaque règle : « using » décide ce qu'on voit et ce qu'on
-- peut effacer, « with check » ce qu'on a le droit d'écrire. Sans le
-- second, n'importe qui poserait un favori au nom d'un autre — et une
-- liste de favoris qu'un tiers peut garnir ne vaut plus rien.
alter table public.favoris            enable row level security;
alter table public.boutiques_suivies  enable row level security;
alter table public.adresses           enable row level security;

drop policy if exists "favoris a soi" on public.favoris;
create policy "favoris a soi" on public.favoris
  for all to authenticated
  using (client_id = auth.uid()) with check (client_id = auth.uid());

drop policy if exists "suivies a soi" on public.boutiques_suivies;
create policy "suivies a soi" on public.boutiques_suivies
  for all to authenticated
  using (client_id = auth.uid()) with check (client_id = auth.uid());

drop policy if exists "adresses a soi" on public.adresses;
create policy "adresses a soi" on public.adresses
  for all to authenticated
  using (client_id = auth.uid()) with check (client_id = auth.uid());

-- UNE BASE SUPABASE DONNE TOUT D'OFFICE. « alter default privileges »
-- accorde `all` à anon et authenticated sur toute table nouvelle : poser
-- un `grant` par-dessus n'enlève rien. Il faut RETIRER d'abord — sans
-- quoi un visiteur non connecté lirait ces trois tables, RLS ou pas,
-- puisque aucune règle ne s'applique à lui faute de `to anon`.
revoke all on public.favoris           from anon, authenticated;
revoke all on public.boutiques_suivies from anon, authenticated;
revoke all on public.adresses          from anon, authenticated;
grant select, insert, delete on public.favoris           to authenticated;
grant select, insert, delete on public.boutiques_suivies to authenticated;
grant select, insert, update, delete on public.adresses  to authenticated;

-- ---------- Ce qui se vend le mieux ----------
-- Le classement de l'accueil. Il lit les lignes de commande, que
-- personne ne peut lire — d'où « security definer ».
--
-- IL REND L'ORDRE, JAMAIS LES CHIFFRES. C'est toute la différence
-- entre « voici ce qui part le plus » et « voici combien chaque
-- boutique vend ». Le premier est un service au client ; le second
-- livrerait à chaque commerçant le carnet de commandes de son voisin,
-- et il suffirait d'un compte gratuit pour l'ouvrir.
--
-- Trois mois de recul : assez pour que le classement veuille dire
-- quelque chose, assez court pour qu'un succès de l'an dernier ne
-- tienne pas la première place pour toujours.
create or replace function public.produits_populaires(limite int default 8)
returns table (produit_id text)
language sql stable security definer set search_path = public as $$
  select l.produit_id
    from public.commande_lignes l
    join public.commandes c on c.id = l.commande_id
    join public.produits  p on p.id = l.produit_id
    join public.boutiques b on b.id = p.boutique_id
   where c.etat = 'payee'
     and c.cree_le > now() - interval '90 days'
     and l.produit_id is not null
     -- Un produit retiré de la vente, ou d'une boutique fermée, n'a
     -- rien à faire sur l'accueil : le client cliquerait dans le vide.
     and p.disponible
     and b.actif
   group by l.produit_id
   -- Le nombre sert à trier, et ne sort pas de la fonction.
   order by sum(l.quantite) desc, l.produit_id
   limit greatest(1, least(coalesce(limite, 8), 24));
$$;
revoke all on function public.produits_populaires(int)
  from public, anon, authenticated;
-- Ouverte à tous, y compris sans compte : c'est l'accueil de BIZZOO,
-- et il doit s'afficher avant qu'on se connecte.
grant execute on function public.produits_populaires(int) to anon, authenticated;

-- ---------- La liste de BIZZOO ----------
-- Vingt-neuf secteurs, cent vingt-trois rayons. Ils arrivent une fois ;
-- ensuite c'est le superadministrateur qui les tient depuis
-- l'application — renommer, réordonner, ajouter, retirer.
--
-- « on conflict do nothing » : une liste déjà retouchée par l'enseigne
-- ne doit pas être remise à l'état d'usine à chaque relecture du
-- fichier. Ce qui est posé reste posé.
--
-- « en_avant » désigne les huit de l'accueil. Les vingt-neuf ne
-- tiennent pas sur un premier écran, et les montrer toutes reviendrait
-- à n'en montrer aucune.
--
-- « ordre » range la liste par thème : high-tech, enfants et école,
-- maison, mobilité, mode, alimentation, loisirs, professionnels,
-- services. La place 3 est celle d'« Électro-ménagers & Cuisinière »,
-- créée depuis l'admin sur la base en ligne.
--
-- « icone » : l'icône de sa tuile, l'une de celles des planches
-- choisies par l'enseigne (« img/pictos/ », dans les deux
-- applications). Pas d'image : l'icône suffit. Une base déjà en place
-- reçoit les icônes par « categories-icones.sql », et la liste rangée
-- par « categories-rangement.sql ».
insert into public.categories (id, boutique_id, nom, icone, couleur, en_avant, ordre, image) values
  ('cat_hightech',     null, 'Informatique & Électronique',   'informatique',     '#0B5CF5', true,   1, ''),
  ('cat_logiciels',    null, 'Logiciels & Solutions pro',     'informatique',     '#0B7C8C', false,  2, ''),
  ('cat_energie',      null, 'Énergie solaire & Électricité', 'energie',          '#2550B7', false,  4, ''),
  ('cat_securite',     null, 'Sécurité & Surveillance',       'securite',         '#2550B7', false,  5, ''),
  ('cat_bebe',         null, 'Bébé & Enfants',                'bebe-enfant',      '#3F51B5', false,  6, ''),
  ('cat_livres',       null, 'Livres & Fournitures scolaires', 'livres-education', '#7A4A32', false, 7, ''),
  ('cat_formation',    null, 'Formation & Cours',             'formation',        '#2550B7', false,  8, ''),
  ('cat_maison',       null, 'Maison & Déco',                 'maison-deco',      '#0F9D58', true,   9, ''),
  ('cat_jardinage',    null, 'Jardinage & Espaces verts',     'jardinage',        '#2550B7', false, 10, ''),
  ('cat_bricolage',    null, 'Bricolage & Matériaux',         'bricolage',        '#546E7A', false, 11, ''),
  ('cat_auto',         null, 'Auto & Moto',                   'auto-moto',        '#001450', true,  12, ''),
  ('cat_transport',    null, 'Transport & Location',          'transport',        '#2550B7', false, 13, ''),
  ('cat_mode',         null, 'Mode & Vêtements',              'mode',             '#6C3FBF', true,  14, ''),
  ('cat_bijoux',       null, 'Bijoux & Accessoires',          'bijoux',           '#6C3FBF', false, 15, ''),
  ('cat_beaute',       null, 'Beauté & Bien-être',            'beaute',           '#D81B60', true,  16, ''),
  ('cat_supermarche',  null, 'Supermarché & Épicerie',        'alimentation',     '#E62329', true,  17, ''),
  ('cat_restauration', null, 'Restauration',                  'restauration',     '#F96302', true,  18, ''),
  ('cat_agriculture',  null, 'Agriculture & Élevage',         'agriculture',      '#2550B7', false, 19, ''),
  ('cat_animaux',      null, 'Animaux',                       'animaux',          '#0F9D58', false, 20, ''),
  ('cat_sport',        null, 'Sport & Loisirs',               'sport-loisirs',    '#9A6B00', false, 21, ''),
  ('cat_musique',      null, 'Musique & Instruments',         'musique',          '#2550B7', false, 22, ''),
  ('cat_artisanat',    null, 'Artisanat & Produits locaux',   'artisanat',        '#2550B7', false, 23, ''),
  ('cat_cadeaux',      null, 'Cadeaux & Fêtes',               'cadeau',           '#2550B7', false, 24, ''),
  ('cat_evenementiel', null, 'Événementiel & Décoration',     'evenementiel',     '#2550B7', false, 25, ''),
  ('cat_bureau',       null, 'Équipements de bureau',         'bureau',           '#2550B7', false, 26, ''),
  ('cat_materiel_pro', null, 'Matériel professionnel',        'materiel-pro',     '#2550B7', false, 27, ''),
  ('cat_imprimerie',   null, 'Imprimerie & Communication',    'imprimante',       '#2550B7', false, 28, ''),
  ('cat_grossistes',   null, 'Grossistes & Fournisseurs',     'grossistes',       '#2550B7', false, 29, ''),
  ('cat_services',     null, 'Services & Prestataires',       'services',         '#0B7C8C', true,  30, '')
on conflict (id) do nothing;

insert into public.sous_categories (id, categorie_id, nom, ordre) values
  ('sc_hightech_smartphones',  'cat_hightech', 'Smartphones',       1),
  ('sc_hightech_ordinateurs',  'cat_hightech', 'Ordinateurs',       2),
  ('sc_hightech_tablettes',    'cat_hightech', 'Tablettes',         3),
  ('sc_hightech_accessoires',  'cat_hightech', 'Accessoires',       4),
  ('sc_hightech_tv',           'cat_hightech', 'TV & audio',        5),

  ('sc_logiciels_gestion',     'cat_logiciels', 'Logiciels de gestion',      1),
  ('sc_logiciels_compta',      'cat_logiciels', 'Comptabilité',              2),
  ('sc_logiciels_caisse',      'cat_logiciels', 'Caisse/POS',                3),
  ('sc_logiciels_antivirus',   'cat_logiciels', 'Antivirus',                 4),
  ('sc_logiciels_licences',    'cat_logiciels', 'Licences',                  5),
  ('sc_logiciels_entreprises', 'cat_logiciels', 'Solutions pour entreprises', 6),

  ('sc_energie_solaire',        'cat_energie', 'Panneaux & kits solaires', 1),
  ('sc_energie_batteries',      'cat_energie', 'Batteries & onduleurs',    2),
  ('sc_energie_groupes',        'cat_energie', 'Groupes électrogènes',     3),
  ('sc_energie_eclairage',      'cat_energie', 'Éclairage',                4),
  ('sc_brico_electricite',      'cat_energie', 'Électricité',              5),

  ('sc_securite_cameras',       'cat_securite', 'Caméras de surveillance',      1),
  ('sc_securite_alarmes',       'cat_securite', 'Alarmes & détecteurs',         2),
  ('sc_securite_acces',         'cat_securite', 'Serrures & contrôle d''accès', 3),

  ('sc_bebe_vetements',        'cat_bebe', 'Vêtements',             1),
  ('sc_bebe_jouets',           'cat_bebe', 'Jouets',                2),
  ('sc_bebe_puericulture',     'cat_bebe', 'Puériculture',          3),
  ('sc_bebe_mobilier',         'cat_bebe', 'Mobilier enfant',       4),

  ('sc_livres_livres',         'cat_livres', 'Livres',               1),
  ('sc_livres_fournitures',    'cat_livres', 'Fournitures scolaires', 2),
  ('sc_livres_papeterie',      'cat_livres', 'Papeterie',            3),

  ('sc_livres_formations',      'cat_formation', 'Formations',                 1),
  ('sc_formation_cours',        'cat_formation', 'Cours particuliers',         2),
  ('sc_formation_langues',      'cat_formation', 'Langues',                    3),
  ('sc_formation_informatique', 'cat_formation', 'Informatique & bureautique', 4),

  ('sc_maison_meubles',        'cat_maison', 'Meubles',             1),
  ('sc_maison_decoration',     'cat_maison', 'Décoration',          2),
  ('sc_maison_electromenager', 'cat_maison', 'Électroménager',      3),
  ('sc_maison_cuisine',        'cat_maison', 'Cuisine',             4),

  ('sc_maison_jardinage',       'cat_jardinage', 'Jardinage',                  1),
  ('sc_jardinage_plantes',      'cat_jardinage', 'Plantes & fleurs',           2),
  ('sc_jardinage_outils',       'cat_jardinage', 'Outils de jardin',           3),
  ('sc_jardinage_entretien',    'cat_jardinage', 'Entretien d''espaces verts', 4),

  ('sc_brico_outillage',       'cat_bricolage', 'Outillage',                  1),
  ('sc_brico_materiaux',       'cat_bricolage', 'Matériaux de construction',  2),
  ('sc_brico_plomberie',       'cat_bricolage', 'Plomberie',                  4),
  ('sc_brico_quincaillerie',   'cat_bricolage', 'Quincaillerie',              5),

  ('sc_auto_vehicules',        'cat_auto', 'Véhicules',             1),
  ('sc_auto_motos',            'cat_auto', 'Motos',                 2),
  ('sc_auto_pieces',           'cat_auto', 'Pièces détachées',      3),
  ('sc_auto_pneus',            'cat_auto', 'Pneus',                 4),
  ('sc_auto_accessoires',      'cat_auto', 'Accessoires auto',      5),
  ('sc_auto_entretien',        'cat_auto', 'Entretien',             6),

  ('sc_transport_location',     'cat_transport', 'Location de véhicules',     1),
  ('sc_transport_demenagement', 'cat_transport', 'Déménagement',              2),
  ('sc_transport_marchandises', 'cat_transport', 'Transport de marchandises', 3),
  ('sc_transport_coursiers',    'cat_transport', 'Livraison & coursiers',     4),

  ('sc_mode_homme',            'cat_mode', 'Homme',                 1),
  ('sc_mode_femme',            'cat_mode', 'Femme',                 2),
  ('sc_mode_enfant',           'cat_mode', 'Enfant',                3),
  ('sc_mode_chaussures',       'cat_mode', 'Chaussures',            4),
  ('sc_mode_sacs',             'cat_mode', 'Sacs & accessoires',    5),

  ('sc_bijoux_bijoux',         'cat_bijoux', 'Bijoux',               1),
  ('sc_bijoux_montres',        'cat_bijoux', 'Montres',              2),
  ('sc_bijoux_lunettes',       'cat_bijoux', 'Lunettes',             3),
  ('sc_bijoux_accessoires',    'cat_bijoux', 'Accessoires',          4),

  ('sc_beaute_cosmetiques',    'cat_beaute', 'Cosmétiques',         1),
  ('sc_beaute_parfums',        'cat_beaute', 'Parfums',             2),
  ('sc_beaute_soins',          'cat_beaute', 'Soins',               3),
  ('sc_beaute_coiffure',       'cat_beaute', 'Coiffure',            4),
  ('sc_beaute_accessoires',    'cat_beaute', 'Accessoires beauté',  5),

  ('sc_super_alimentation',    'cat_supermarche', 'Alimentation',       1),
  ('sc_super_menagers',        'cat_supermarche', 'Produits ménagers',  2),
  ('sc_super_bebe',            'cat_supermarche', 'Produits pour bébé', 3),
  ('sc_super_hygiene',         'cat_supermarche', 'Hygiène',            4),
  ('sc_super_boissons',        'cat_supermarche', 'Boissons',           5),
  ('sc_resto_epicerie',        'cat_supermarche', 'Épicerie',           6),
  ('sc_resto_frais',           'cat_supermarche', 'Produits frais',     7),

  ('sc_resto_restaurants',     'cat_restauration', 'Restaurants',    1),
  ('sc_resto_fastfood',        'cat_restauration', 'Fast-food',      2),
  ('sc_resto_plats_locaux',    'cat_restauration', 'Plats locaux',   3),
  ('sc_resto_boissons',        'cat_restauration', 'Boissons',       4),

  ('sc_agri_semences',          'cat_agriculture', 'Semences & plants',     1),
  ('sc_agri_engrais',           'cat_agriculture', 'Engrais & traitements', 2),
  ('sc_agri_materiel',          'cat_agriculture', 'Matériel agricole',     3),
  ('sc_agri_elevage',           'cat_agriculture', 'Élevage',               4),
  ('sc_agri_produits',          'cat_agriculture', 'Produits de la ferme',  5),

  ('sc_animaux_alimentation',  'cat_animaux', 'Alimentation',        1),
  ('sc_animaux_accessoires',   'cat_animaux', 'Accessoires',         2),
  ('sc_animaux_hygiene',       'cat_animaux', 'Hygiène',             3),

  ('sc_sport_equipements',     'cat_sport', 'Équipements sportifs', 1),
  ('sc_sport_vetements',       'cat_sport', 'Vêtements de sport',   2),
  ('sc_sport_fitness',         'cat_sport', 'Fitness',              3),
  ('sc_sport_jeux',            'cat_sport', 'Jeux',                 4),
  ('sc_sport_loisirs',         'cat_sport', 'Loisirs',              5),

  ('sc_musique_instruments',    'cat_musique', 'Instruments de musique', 1),
  ('sc_musique_sono',           'cat_musique', 'Sonorisation',           2),
  ('sc_musique_accessoires',    'cat_musique', 'Accessoires',            3),

  ('sc_artisanat_objets',       'cat_artisanat', 'Objets d''art & artisanat', 1),
  ('sc_artisanat_tissus',       'cat_artisanat', 'Tissus & pagnes',           2),
  ('sc_artisanat_locaux',       'cat_artisanat', 'Produits locaux',           3),

  ('sc_cadeaux_cadeaux',        'cat_cadeaux', 'Cadeaux',             1),
  ('sc_cadeaux_fete',           'cat_cadeaux', 'Articles de fête',    2),
  ('sc_cadeaux_emballages',     'cat_cadeaux', 'Emballages & cartes', 3),

  ('sc_event_decoration',       'cat_evenementiel', 'Décoration d''événements',   1),
  ('sc_event_location',         'cat_evenementiel', 'Location de matériel',       2),
  ('sc_event_organisation',     'cat_evenementiel', 'Organisation d''événements', 3),

  ('sc_bureau_mobilier',        'cat_bureau', 'Mobilier de bureau',    1),
  ('sc_bureau_materiel',        'cat_bureau', 'Matériel de bureau',    2),
  ('sc_bureau_fournitures',     'cat_bureau', 'Fournitures de bureau', 3),

  ('sc_pro_restauration',       'cat_materiel_pro', 'Équipements de restauration',   1),
  ('sc_pro_salon',              'cat_materiel_pro', 'Équipements de salon & beauté', 2),
  ('sc_pro_machines',           'cat_materiel_pro', 'Machines professionnelles',     3),
  ('sc_pro_medical',            'cat_materiel_pro', 'Matériel médical',              4),

  ('sc_imprimerie_impression',  'cat_imprimerie', 'Impression',                1),
  ('sc_imprimerie_enseignes',   'cat_imprimerie', 'Enseignes & signalétique',  2),
  ('sc_imprimerie_objets',      'cat_imprimerie', 'Objets publicitaires',      3),
  ('sc_imprimerie_graphisme',   'cat_imprimerie', 'Graphisme & communication', 4),

  ('sc_gros_alimentation',      'cat_grossistes', 'Alimentation en gros',        1),
  ('sc_gros_boissons',          'cat_grossistes', 'Boissons en gros',            2),
  ('sc_gros_hygiene',           'cat_grossistes', 'Hygiène & entretien en gros', 3),
  ('sc_gros_emballages',        'cat_grossistes', 'Emballages',                  4),

  ('sc_services_reparation',   'cat_services', 'Réparation',              1),
  ('sc_services_installation', 'cat_services', 'Installation',            2),
  ('sc_services_maintenance',  'cat_services', 'Maintenance',             3),
  ('sc_services_informatique', 'cat_services', 'Informatique',            4),
  ('sc_services_nettoyage',    'cat_services', 'Nettoyage',               5),
  ('sc_services_pro',          'cat_services', 'Services professionnels', 6)
on conflict (id) do nothing;

-- ---------- LA REPRISE : les anciens rayons des boutiques s'en vont ----------
-- Ils étaient à chaque boutique ; la liste est maintenant à l'enseigne.
-- On ne peut pas les garder sans garder deux classements côte à côte.
--
-- CE QUE CELA FAIT AUX PRODUITS, en toutes lettres : ceux qui s'y
-- rangeaient deviennent « à classer ». Ils restent en vente, dans leur
-- boutique et dans la recherche ; ils n'apparaissent sous aucun rayon
-- de BIZZOO tant que la boutique ne leur a pas donné une sous-catégorie
-- de son secteur. Le décompte s'affiche à la fin de ce fichier.
--
-- On reconnaît un ancien rayon à son « boutique_id » : ceux de
-- l'enseigne l'ont toujours à null.
update public.produits set sous_categorie_id = null
 where sous_categorie_id in (
   select sc.id from public.sous_categories sc
     join public.categories c on c.id = sc.categorie_id
    where c.boutique_id is not null);
update public.produits set categorie_id = null
 where categorie_id in (select id from public.categories where boutique_id is not null);
delete from public.categories where boutique_id is not null;

-- La boutique d'exemple se range dans le secteur qui lui correspond.
-- LE DRAPEAU EST INDISPENSABLE ICI : ce fichier se colle dans l'éditeur
-- SQL de Supabase, où PERSONNE n'est connecté. Sans lui, le verrou des
-- boutiques répondrait « le secteur est fixé par l'enseigne » — ce qui
-- est vrai, mais ferait échouer le fichier entier, et le gérant
-- n'obtiendrait rien du tout.
do $$
begin
  perform set_config('bizzoo.secteur', 'oui', true);
  update public.boutiques set categorie_id = 'cat_hightech'
   where id = 'bou_informatique' and categorie_id is null;
  perform set_config('bizzoo.secteur', '', true);
end $$;

-- Références des produits d'exemple déjà en base (seulement si vides).
update public.produits set reference = 'IMP-0001' where id = 'prod_hp15' and reference = '';
update public.produits set reference = 'IMP-0002' where id = 'prod_epson_l3250' and reference = '';
update public.produits set reference = 'IMP-0003' where id = 'prod_apc650' and reference = '';
update public.produits set reference = 'IMP-0004' where id = 'prod_usb_kingston64' and reference = '';
update public.produits set reference = 'IMP-0005' where id = 'prod_toner_85a' and reference = '';
update public.produits set reference = 'IMP-0006' where id = 'prod_logitech_m185' and reference = '';

-- ---------- Produits d'exemple (supprimables depuis l'app admin) ----------
-- Aucun n'est « mis en avant » : le garde-fou de la mise en avant exige
-- un administrateur connecté, et ce fichier s'exécute depuis l'éditeur
-- SQL, où personne ne l'est. Une donnée de départ qui fait trébucher un
-- garde-fou de l'application rendrait tout le fichier non rejouable —
-- or l'éditeur de Supabase annule TOUT à la première erreur.
-- La boutique choisit elle-même ses produits en avant, depuis l'app.
insert into public.produits
  (id, boutique_id, nom, description, prix, ancien_prix, categorie_id, sous_categorie_id,
   stock, sur_commande, disponible, en_avant, ordre_avant) values
  ('prod_hp15', 'bou_informatique', 'Ordinateur portable HP 15',
   e'Écran 15,6" HD, processeur Intel Core i5, 8 Go de RAM, SSD 512 Go, Windows 11.\nIdéal pour le bureau, les études et la navigation.\nGarantie boutique, livraison possible à Cotonou.',
   385000, null, 'cat_hightech', 'sc_hightech_ordinateurs', 4, false, true, false, 0),
  ('prod_epson_l3250', 'bou_informatique', 'Imprimante Epson EcoTank L3250',
   e'Multifonction 3 en 1 (impression, copie, scan) à réservoirs d''encre rechargeables.\nWifi intégré, impression depuis le téléphone.\nJusqu''à 4 500 pages noir avec un seul flacon.',
   145000, 165000, 'cat_hightech', 'sc_hightech_accessoires', 2, false, true, false, 0),
  ('prod_apc650', 'bou_informatique', 'Onduleur APC Back-UPS 650 VA',
   e'Protège votre ordinateur des coupures et variations de courant.\nAutonomie suffisante pour enregistrer votre travail et éteindre proprement.\nPrises multiples, protection téléphone/ADSL.',
   42000, null, 'cat_hightech', 'sc_hightech_accessoires', 7, false, true, false, 0),
  ('prod_usb_kingston64', 'bou_informatique', 'Clé USB Kingston 64 Go',
   e'Clé USB 3.2 rapide et fiable pour vos documents, photos et vidéos.\nCompatible ordinateur, TV et autoradio.',
   6500, null, 'cat_hightech', 'sc_hightech_accessoires', 25, false, true, false, 0),
  ('prod_toner_85a', 'bou_informatique', 'Toner HP 85A (CE285A)',
   e'Cartouche de toner noir d''origine pour HP LaserJet P1102, M1132, M1212…\nEnviron 1 600 pages.',
   28000, 32000, 'cat_hightech', 'sc_hightech_accessoires', 0, false, false, false, 0),
  ('prod_logitech_m185', 'bou_informatique', 'Souris sans fil Logitech M185',
   e'Souris sans fil compacte avec récepteur USB nano.\nJusqu''à 12 mois d''autonomie avec une pile AA.',
   8500, null, 'cat_hightech', 'sc_hightech_accessoires', 12, false, true, false, 0)
on conflict (id) do nothing;


-- Suppression initiée par le titulaire : aucune cible choisie par le client.
create or replace function public.supprimer_mon_compte(confirmation text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  ancien text := coalesce(current_setting('bizzoo.interne', true), '');
begin
  if moi is null or not exists (select 1 from auth.users where id = moi) then
    raise exception 'Connexion nécessaire';
  end if;
  if confirmation is distinct from 'SUPPRIMER' then
    raise exception 'Confirmez la suppression définitive';
  end if;
  -- Ne pas retirer le dernier responsable capable d'administrer la plateforme.
  if exists (select 1 from public.profils where id = moi and role = 'superadministrateur') then
    perform 1 from public.profils where role = 'superadministrateur' for update;
    if not exists (select 1 from public.profils where role = 'superadministrateur' and actif and id <> moi) then
      raise exception 'Transférez la responsabilité à un autre superadministrateur actif avant de supprimer ce compte';
    end if;
  end if;
  perform set_config('bizzoo.interne', 'oui', true);
  -- Les pièces commerciales restent dans leur périmètre métier, mais ne
  -- pourront plus être récupérées par un futur compte portant le même numéro.
  update public.commandes set compte_supprime = true where client_id = moi;
  delete from auth.users where id = moi;
  perform set_config('bizzoo.interne', ancien, true);
end $$;
revoke all on function public.supprimer_mon_compte(text) from public, anon;
grant execute on function public.supprimer_mon_compte(text) to authenticated;

-- BIZZOO : préfiltrage et signalement des avis publics.
-- À appliquer après avis.sql. Les avis ordinaires restent immédiatement
-- visibles, y compris depuis l'ancien site web ; un texte manifestement
-- problématique est refusé avec une erreur lisible avant publication.

-- Le fichier peut aussi être appliqué seul à une base disposant déjà
-- de la table d'avis mais créée avant ces deux colonnes.
alter table public.avis add column if not exists auteur text not null default '';
alter table public.avis add column if not exists reponse text not null default '';

create or replace function public.avis_filtre_code(contenu text) returns text
language plpgsql immutable set search_path = public as $$
declare valeur text := coalesce(contenu, '');
begin
  if valeur ~* '(https?://|www[.]|[[:alnum:]._%+-]+@[[:alnum:].-]+[.][[:alpha:]]{2,})' or
     valeur ~* '(\m(tel|telephone|téléphone|whatsapp|contact|appeler|appelez)\M[^[:digit:]]{0,12}([0-9][ .-]?){8,10})' or
     valeur ~* '((\+|00)229[ .-]?([0-9][ .-]?){8,10})' then
    return 'coordonnees';
  end if;
  if valeur ~* '(\m(porno|pornographie|pornographique|onlyfans|nudes?)\M|kill[[:space:]]+yourself|va[[:space:]]+te[[:space:]]+tuer)' then
    return 'abus';
  end if;
  return '';
end $$;

create or replace function public.avis_filtrer_publication() returns trigger
language plpgsql set search_path = public as $$
declare code text;
begin
  if tg_op = 'INSERT' then
    code := public.avis_filtre_code(concat_ws(' ', new.texte, new.auteur, new.reponse));
  else
    -- Un ancien texte licite lors de sa publication ne doit pas empêcher
    -- une réponse ou une correction sans rapport avec ce texte.
    code := public.avis_filtre_code(concat_ws(' ',
      case when new.texte is distinct from old.texte then new.texte end,
      case when new.auteur is distinct from old.auteur then new.auteur end,
      case when new.reponse is distinct from old.reponse then new.reponse end));
  end if;
  if code = 'coordonnees' then
    raise exception 'Ne publiez ni lien, ni numéro, ni adresse e-mail dans un avis ou une réponse';
  end if;
  if code = 'abus' then
    raise exception 'Ce contenu ne peut pas être publié. Modifiez-le ou contactez BIZZOO';
  end if;
  return new;
end $$;

drop trigger if exists avis_prepublication on public.avis;
create trigger avis_prepublication
  before insert or update of texte, auteur, reponse on public.avis
  for each row execute function public.avis_filtrer_publication();

-- Un signalement est une demande de contrôle, jamais un masquage automatique.
-- La cible "auteur" permet de signaler le comportement d'une personne,
-- indépendamment du texte de l'avis choisi comme preuve.
create table if not exists public.avis_signalements (
  id           bigint generated always as identity primary key,
  avis_id      text not null references public.avis(id) on delete cascade,
  auteur_id    uuid not null references auth.users(id) on delete cascade,
  signale_par  uuid not null references auth.users(id) on delete cascade,
  cible        text not null check (cible in ('avis', 'auteur')),
  motif        text not null check (motif in
                 ('harcelement', 'haine', 'sexuel', 'donnees_personnelles', 'spam', 'autre')),
  details      text not null default '',
  etat         text not null default 'ouvert'
               check (etat in ('ouvert', 'traite', 'rejete')),
  cree_le      timestamptz not null default now(),
  traite_le    timestamptz,
  traite_par   uuid references auth.users(id) on delete set null,
  decision     text not null default ''
);
create unique index if not exists avis_signalements_une_demande_ouverte
  on public.avis_signalements(avis_id, signale_par, cible) where etat = 'ouvert';
create index if not exists avis_signalements_a_traiter
  on public.avis_signalements(cree_le) where etat = 'ouvert';

alter table public.avis_signalements enable row level security;
drop policy if exists "signalements lecture auteur et enseigne" on public.avis_signalements;
create policy "signalements lecture auteur et enseigne" on public.avis_signalements
  for select to authenticated
  using (signale_par = auth.uid() or public.est_super());
revoke all on public.avis_signalements from anon, authenticated;
grant select on public.avis_signalements to authenticated;

create or replace function public.signaler_avis(
  avis_cible text, cible_signalee text, motif_signalement text, precisions text default '')
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  auteur uuid;
  identifiant bigint;
begin
  if moi is null or not exists (select 1 from public.clients where id = moi) then
    raise exception 'Connectez-vous comme client pour signaler cet avis';
  end if;
  if cible_signalee not in ('avis', 'auteur') or
     motif_signalement not in
       ('harcelement', 'haine', 'sexuel', 'donnees_personnelles', 'spam', 'autre') then
    raise exception 'Choisissez un motif de signalement valide';
  end if;
  select client_id into auteur from public.avis
   where id = avis_cible and not masque;
  if auteur is null then raise exception 'Cet avis n''est plus public'; end if;
  if auteur = moi then raise exception 'Vous ne pouvez pas signaler votre propre avis'; end if;

  insert into public.avis_signalements
    (avis_id, auteur_id, signale_par, cible, motif, details)
  values (avis_cible, auteur, moi, cible_signalee, motif_signalement,
          left(trim(coalesce(precisions, '')), 500))
  on conflict (avis_id, signale_par, cible) where etat = 'ouvert'
  do update set motif = excluded.motif, details = excluded.details, cree_le = now()
  returning id into identifiant;
  return identifiant;
end $$;
revoke all on function public.signaler_avis(text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.signaler_avis(text, text, text, text)
  to authenticated;

-- Une sanction ciblée empêche un auteur abusif de déposer ou modifier
-- des avis, sans l'empêcher de consulter ses commandes ni d'acheter.
create table if not exists public.avis_auteurs_bloques (
  client_id  uuid primary key references auth.users(id) on delete cascade,
  auteur    text not null default '',
  motif     text not null,
  bloque_le timestamptz not null default now(),
  bloque_par uuid references auth.users(id) on delete set null
);
alter table public.avis_auteurs_bloques enable row level security;
drop policy if exists "auteurs bloqués lecture enseigne" on public.avis_auteurs_bloques;
create policy "auteurs bloqués lecture enseigne" on public.avis_auteurs_bloques
  for select to authenticated using (public.est_super());
revoke all on public.avis_auteurs_bloques from anon, authenticated;
grant select on public.avis_auteurs_bloques to authenticated;

create or replace function public.avis_interdire_auteur() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.avis_auteurs_bloques b
              where b.client_id = new.client_id) then
    raise exception 'Votre compte ne peut plus publier d''avis. Contactez BIZZOO';
  end if;
  return new;
end $$;
drop trigger if exists avis_auteur_interdit on public.avis;
create trigger avis_auteur_interdit
  before insert or update of note, texte, produit_id, boutique_id on public.avis
  for each row execute function public.avis_interdire_auteur();

create or replace function public.bloquer_auteur_avis(
  auteur_cible uuid, bloquer boolean, justification text default '')
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  raison text := left(trim(coalesce(justification, '')), 300);
  nom_public text;
begin
  if not public.est_super() then
    raise exception 'Seule l''enseigne peut bloquer les avis d''un auteur';
  end if;
  if coalesce(bloquer, false) then
    if not exists (select 1 from public.clients where id = auteur_cible) then
      raise exception 'Auteur introuvable';
    end if;
    if raison = '' then raise exception 'Indiquez pourquoi cet auteur est bloqué'; end if;
    select coalesce(a.auteur, '') into nom_public from public.avis a
     where a.client_id = auteur_cible order by a.cree_le desc limit 1;
    insert into public.avis_auteurs_bloques
      (client_id, auteur, motif, bloque_par)
    values (auteur_cible, coalesce(nom_public, ''), raison, auth.uid())
    on conflict (client_id) do update
      set auteur = excluded.auteur, motif = excluded.motif,
          bloque_le = now(), bloque_par = excluded.bloque_par;
  else
    delete from public.avis_auteurs_bloques where client_id = auteur_cible;
  end if;
  return true;
end $$;
revoke all on function public.bloquer_auteur_avis(uuid, boolean, text)
  from public, anon, authenticated;
grant execute on function public.bloquer_auteur_avis(uuid, boolean, text)
  to authenticated;

-- Le superadministrateur clôt une demande et, si elle est fondée,
-- masque l'avis. Le déclencheur existant le retire des moyennes.
create or replace function public.traiter_signalement_avis(
  signalement bigint, masquer boolean, justification text default '')
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  demande public.avis_signalements%rowtype;
  raison text := left(trim(coalesce(justification, '')), 300);
begin
  if not public.est_super() then
    raise exception 'Seule l''enseigne peut traiter un signalement';
  end if;
  select * into demande from public.avis_signalements
   where id = signalement and etat = 'ouvert' for update;
  if not found then raise exception 'Signalement déjà traité ou introuvable'; end if;
  if coalesce(masquer, false) and raison = '' then
    raise exception 'Indiquez pourquoi cet avis est masqué';
  end if;
  if coalesce(masquer, false) then
    update public.avis
       set masque = true, motif_masque = raison, maj_le = now()
     where id = demande.avis_id;
    if not found then raise exception 'Avis introuvable'; end if;
  end if;
  update public.avis_signalements
     set etat = case when coalesce(masquer, false) then 'traite' else 'rejete' end,
         traite_le = now(), traite_par = auth.uid(), decision = raison
   where id = signalement;
  return true;
end $$;
revoke all on function public.traiter_signalement_avis(bigint, boolean, text)
  from public, anon, authenticated;
grant execute on function public.traiter_signalement_avis(bigint, boolean, text)
  to authenticated;

-- Les fiches et médias des commerçants sont eux aussi visibles du public.
-- Un signalement n'interrompt jamais la vente automatiquement : la
-- plateforme examine la fiche, puis corrige ou retire si nécessaire.
create table if not exists public.produits_signalements (
  id           bigint generated always as identity primary key,
  produit_id   text not null references public.produits(id) on delete cascade,
  nom_produit  text not null default '',
  boutique_id  text not null default '',
  signale_par  uuid not null references auth.users(id) on delete cascade,
  motif        text not null check (motif in
                 ('trompeur', 'contrefacon', 'haine', 'sexuel',
                  'donnees_personnelles', 'spam', 'autre')),
  details      text not null default '',
  etat         text not null default 'ouvert'
               check (etat in ('ouvert', 'traite')),
  cree_le      timestamptz not null default now(),
  traite_le    timestamptz,
  traite_par   uuid references auth.users(id) on delete set null,
  decision     text not null default ''
);
create unique index if not exists produits_signalements_une_demande_ouverte
  on public.produits_signalements(produit_id, signale_par) where etat = 'ouvert';
create index if not exists produits_signalements_a_traiter
  on public.produits_signalements(cree_le) where etat = 'ouvert';
alter table public.produits_signalements enable row level security;
drop policy if exists "signalements produits lecture" on public.produits_signalements;
create policy "signalements produits lecture" on public.produits_signalements
  for select to authenticated
  using (signale_par = auth.uid() or public.est_super());
revoke all on public.produits_signalements from anon, authenticated;
grant select on public.produits_signalements to authenticated;

create or replace function public.signaler_produit(
  produit_cible text, motif_signalement text, precisions text default '')
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  fiche public.produits%rowtype;
  identifiant bigint;
begin
  if moi is null or not exists (select 1 from public.clients where id = moi) then
    raise exception 'Connectez-vous comme client pour signaler cette fiche';
  end if;
  if motif_signalement not in ('trompeur', 'contrefacon', 'haine', 'sexuel',
                               'donnees_personnelles', 'spam', 'autre') then
    raise exception 'Choisissez un motif de signalement valide';
  end if;
  select p.* into fiche from public.produits p
    left join public.boutiques b on b.id = p.boutique_id
   where p.id = produit_cible
     and (p.boutique_id is null or coalesce(b.actif, false));
  if not found then raise exception 'Cette fiche n''existe plus'; end if;
  insert into public.produits_signalements
    (produit_id, nom_produit, boutique_id, signale_par, motif, details)
  values (fiche.id, left(fiche.nom, 200), coalesce(fiche.boutique_id, ''),
          moi, motif_signalement, left(trim(coalesce(precisions, '')), 500))
  on conflict (produit_id, signale_par) where etat = 'ouvert'
  do update set motif = excluded.motif, details = excluded.details,
                nom_produit = excluded.nom_produit, cree_le = now()
  returning id into identifiant;
  return identifiant;
end $$;
revoke all on function public.signaler_produit(text, text, text)
  from public, anon, authenticated;
grant execute on function public.signaler_produit(text, text, text)
  to authenticated;

create or replace function public.traiter_signalement_produit(
  signalement bigint, justification text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare raison text := left(trim(coalesce(justification, '')), 300);
begin
  if not public.est_super() then
    raise exception 'Seule l''enseigne peut traiter un signalement de fiche';
  end if;
  if raison = '' then raise exception 'Indiquez la suite donnée au signalement'; end if;
  update public.produits_signalements
     set etat = 'traite', traite_le = now(), traite_par = auth.uid(),
         decision = raison
   where id = signalement and etat = 'ouvert';
  if not found then raise exception 'Signalement déjà traité ou introuvable'; end if;
  return true;
end $$;
revoke all on function public.traiter_signalement_produit(bigint, text)
  from public, anon, authenticated;
grant execute on function public.traiter_signalement_produit(bigint, text)
  to authenticated;

-- =========================================================
-- La connexion de l'équipe confirmée par SMS, et qui a créé
-- quel compte (3.58.0)
--
-- DEUX PORTES, DEUX MÉCANISMES, et le choix n'est pas un hasard.
--
--   LE CLIENT ENTRE PAR SON NUMÉRO : le code est celui de GoTrue, et
--   le numéro est l'identifiant. Rien à écrire ici — voir le chapitre
--   « Vérification du numéro ».
--
--   L'ÉQUIPE GARDE SON E-MAIL ET SON MOT DE PASSE, et reçoit EN PLUS un
--   code à chaque connexion. Ce code-là est le nôtre, et pour une
--   raison précise : GoTrue marque de la même étiquette (« otp ») une
--   session ouverte par un code SMS et une session ouverte par un lien
--   reçu par e-mail. La base ne saurait pas les distinguer. Le seul
--   témoin d'un SMS reçu est un code que NOUS avons envoyé, et que la
--   personne nous rend.
--
-- Le code est rattaché à la SESSION (« session_id » du jeton), pas au
-- compte : chaque connexion demande le sien, et un code rendu sur un
-- téléphone n'ouvre rien sur un autre. L'interrupteur, les sessions
-- confirmées et « equipe_en_service() » sont posés plus haut, avant
-- « role_courant() », qui les lit.
--
-- TANT QUE L'ENSEIGNE NE L'EXIGE PAS, rien ne change. L'interrupteur ne
-- s'allume qu'entre les mains d'un superadministrateur qui vient de
-- recevoir et de rendre son propre code : la preuve que le SMS arrive,
-- avant de fermer la porte à toute l'équipe.
-- =========================================================

-- ---------- Le numéro de l'équipe, et qui a créé le compte ----------
-- « tel » est répété ici : un fichier qui pose une règle d'écriture pose
-- aussi les colonnes qu'elle lit.
alter table public.profils add column if not exists tel text not null default '';
-- Vérifié par un code reçu, jamais déclaré : voir « profil_trace() ».
alter table public.profils add column if not exists tel_verifie boolean not null default false;
alter table public.profils add column if not exists tel_verifie_le timestamptz;
-- Qui a créé ce compte. SANS lien vers « auth.users » : la trace doit
-- survivre à la suppression du compte de celui qui l'a créé. Son nom est
-- figé au moment de la création, pour la même raison.
alter table public.profils add column if not exists cree_par uuid;
alter table public.profils add column if not exists cree_par_nom text not null default '';
-- (3.63.0) Un compte créé par l'administrateur de BIZZOO attend que le
-- superadministrateur le valide : voir « profil_validation ».
alter table public.profils add column if not exists a_valider boolean not null default false;

-- ---------- Les codes envoyés ----------
-- Hachés, jamais en clair : une copie de la base ne doit pas permettre
-- d'ouvrir une session à la place de quelqu'un. Les lignes ne
-- s'effacent pas — un code rendu, remplacé ou annulé change d'état — et
-- c'est ce qui permet de compter les envois de l'heure passée.
create table if not exists public.codes_connexion (
  id          bigint generated always as identity primary key,
  session_id  uuid not null,
  utilisateur uuid not null,
  tel         text not null default '',
  code_hache  text not null,
  envoye_le   timestamptz not null default now(),
  expire_le   timestamptz not null,
  essais      int not null default 0,
  etat        text not null default 'envoye'
              check (etat in ('envoye', 'remplace', 'annule', 'utilise', 'epuise'))
);
create index if not exists codes_connexion_session
  on public.codes_connexion(session_id, envoye_le desc);
create index if not exists codes_connexion_utilisateur
  on public.codes_connexion(utilisateur, envoye_le desc);
alter table public.codes_connexion enable row level security;
revoke all on public.codes_connexion from public, anon, authenticated;

-- ---------- Enregistrer un code, au nom de la fonction Edge ----------
-- C'est la fonction Edge « code-connexion » qui tire le code : elle seule
-- le connaît en clair, et elle n'en confie ici que l'empreinte. D'où les
-- droits : la clé de service, et personne d'autre. Ouverte à un compte
-- connecté, elle laisserait chacun inscrire l'empreinte d'un code qu'il
-- aurait choisi — et le rendre sans avoir rien reçu.
--
-- LE FREIN est ici, en base : trente secondes entre deux codes, cinq par
-- heure. Côté application, il se contournerait — et chaque code est un
-- SMS payé par l'enseigne.
create or replace function public.enregistrer_code_connexion(
  qui uuid, session uuid, hache text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p       public.profils%rowtype;
  numero  text;
  dernier timestamptz;
  recents int;
  nouveau bigint;
begin
  if qui is null or session is null or coalesce(hache, '') !~ '\A[0-9a-f]{64}\Z' then
    return jsonb_build_object('ok', false, 'raison', 'requete');
  end if;
  select * into p from public.profils where id = qui;
  if not found or not p.actif then
    return jsonb_build_object('ok', false, 'raison', 'hors_equipe');
  end if;
  if exists (select 1 from public.sessions_sms s
              where s.session_id = session and s.utilisateur = qui) then
    return jsonb_build_object('ok', false, 'raison', 'deja_confirmee');
  end if;
  -- Le numéro est celui que l'administrateur a enregistré, jamais un
  -- numéro tapé au moment de se connecter : sinon un mot de passe volé
  -- suffirait, le voleur donnerait le sien.
  numero := regexp_replace(coalesce(p.tel, ''), '\D', '', 'g');
  if length(numero) < 8 then
    return jsonb_build_object('ok', false, 'raison', 'sans_numero');
  end if;

  select max(c.envoye_le),
         count(*) filter (where c.envoye_le > now() - interval '1 hour')
    into dernier, recents
    from public.codes_connexion c
   where c.utilisateur = qui and c.etat <> 'annule';
  if dernier is not null and dernier > now() - interval '30 seconds' then
    return jsonb_build_object('ok', false, 'raison', 'trop_tot',
      'attente', greatest(1, ceil(extract(epoch from
        (dernier + interval '30 seconds' - now()))))::int);
  end if;
  if coalesce(recents, 0) >= 5 then
    return jsonb_build_object('ok', false, 'raison', 'trop_de_codes');
  end if;

  -- Un seul code vaut pour une session : le précédent cède.
  update public.codes_connexion set etat = 'remplace'
   where session_id = session and utilisateur = qui and etat = 'envoye';
  insert into public.codes_connexion (session_id, utilisateur, tel, code_hache, expire_le)
  values (session, qui, numero, lower(hache), now() + interval '10 minutes')
  returning id into nouveau;
  return jsonb_build_object('ok', true, 'id', nouveau, 'tel', numero);
end $$;
revoke all on function public.enregistrer_code_connexion(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.enregistrer_code_connexion(uuid, uuid, text) to service_role;

-- Le SMS n'est pas parti : le code ne compte pas. Sans cela, une
-- passerelle en panne ferait épuiser les cinq envois de l'heure sans
-- qu'un seul SMS ait coûté quoi que ce soit — ni servi à rien.
create or replace function public.annuler_code_connexion(code_id bigint)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.codes_connexion set etat = 'annule'
   where id = code_id and etat = 'envoye';
end $$;
revoke all on function public.annuler_code_connexion(bigint)
  from public, anon, authenticated;
grant execute on function public.annuler_code_connexion(bigint) to service_role;

-- ---------- Rendre le code ----------
-- UNE ERREUR NE SE LÈVE PAS ICI, ELLE SE RÉPOND. Lever ferait annuler
-- la transaction — et avec elle le compteur d'essais qu'on vient
-- d'augmenter : on pourrait alors essayer les un million de codes un par
-- un. Cinq essais par code, cinq codes par heure : vingt-cinq chances
-- sur un million.
create or replace function public.confirmer_code_connexion(code text)
returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  qui   uuid := auth.uid();
  sid   uuid := public.session_courante();
  c     public.codes_connexion%rowtype;
  saisi text := regexp_replace(coalesce(code, ''), '\D', '', 'g');
begin
  if qui is null or sid is null then
    return jsonb_build_object('ok', false, 'raison', 'sans_session');
  end if;
  if exists (select 1 from public.sessions_sms s
              where s.session_id = sid and s.utilisateur = qui) then
    return jsonb_build_object('ok', true, 'deja', true);
  end if;

  select * into c from public.codes_connexion
   where session_id = sid and utilisateur = qui and etat = 'envoye'
   order by envoye_le desc
   limit 1
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'raison', 'sans_code');
  end if;
  if c.expire_le < now() then
    update public.codes_connexion set etat = 'epuise' where id = c.id;
    return jsonb_build_object('ok', false, 'raison', 'expire');
  end if;

  -- L'empreinte porte la session : le même code tiré pour une autre
  -- connexion n'aurait pas la même.
  if length(saisi) <> 6
     or encode(digest(saisi || ':' || sid::text, 'sha256'), 'hex') <> c.code_hache then
    update public.codes_connexion
       set essais = essais + 1,
           etat = case when essais + 1 >= 5 then 'epuise' else etat end
     where id = c.id;
    return jsonb_build_object('ok', false, 'raison', 'code_faux',
      'restants', greatest(0, 4 - c.essais));
  end if;

  update public.codes_connexion set etat = 'utilise' where id = c.id;
  insert into public.sessions_sms (session_id, utilisateur)
  values (sid, qui)
  on conflict (session_id) do nothing;

  -- LE NUMÉRO EST VÉRIFIÉ : la personne a rendu le code qu'on y avait
  -- envoyé. À condition qu'il n'ait pas changé entre-temps — sinon c'est
  -- l'ancien qui a reçu le code, pas celui qu'on lirait maintenant.
  perform set_config('bizzoo.compte', 'oui', true);
  update public.profils
     set tel_verifie = true, tel_verifie_le = now()
   where id = qui and not tel_verifie
     and regexp_replace(coalesce(tel, ''), '\D', '', 'g') = c.tel;
  perform set_config('bizzoo.compte', '', true);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.confirmer_code_connexion(text) from public, anon;
grant execute on function public.confirmer_code_connexion(text) to authenticated;

-- ---------- Où en est la connexion ----------
-- Lue par l'application admin juste après le mot de passe : faut-il
-- demander un code, et vers quel numéro ? Elle répond MÊME à une session
-- sans droits — c'est tout son objet. Elle ne dit du numéro que ses deux
-- derniers chiffres : la personne connaît le sien, et une session
-- ouverte avec un mot de passe volé n'a pas à apprendre le reste.
create or replace function public.etat_connexion()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  p      public.profils%rowtype;
  numero text;
begin
  if auth.uid() is null then
    return jsonb_build_object('equipe', false, 'sms_exige', public.sms_equipe_exige());
  end if;
  select * into p from public.profils where id = auth.uid();
  if not found or not p.actif then
    return jsonb_build_object('equipe', false, 'sms_exige', public.sms_equipe_exige());
  end if;
  numero := regexp_replace(coalesce(p.tel, ''), '\D', '', 'g');
  return jsonb_build_object(
    'equipe', true,
    -- (3.59.0) Exigé de ce compte-ci : seul le superadministrateur
    -- rend un code.
    'sms_exige', public.sms_equipe_exige() and p.role = 'superadministrateur',
    'session_confirmee', public.session_confirmee(),
    'numero', length(numero) >= 8,
    'fin_numero', case when length(numero) >= 8 then right(numero, 2) else '' end,
    'tel_verifie', p.tel_verifie);
end $$;
revoke all on function public.etat_connexion() from public, anon;
grant execute on function public.etat_connexion() to authenticated;

-- ---------- L'interrupteur ----------
-- Au superadministrateur seul. ET POUR L'ALLUMER, IL FAUT AVOIR SOI-MÊME
-- REÇU ET RENDU SON CODE dans cette session : c'est la preuve que la
-- passerelle livre. Sans elle, allumer avec une clé SMS fausse ou un
-- crédit épuisé fermerait la porte à toute l'équipe — à commencer par
-- celui qui vient de l'allumer.
--
-- Pour l'éteindre en catastrophe, sans application : dans l'éditeur SQL
-- de Supabase, « update public.securite_equipe set sms_exige = false; ».
create or replace function public.regler_sms_equipe(exige boolean)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  voulu boolean := coalesce(exige, false);
  qui   text;
begin
  if not public.est_super() then
    raise exception 'Réservé au superadministrateur';
  end if;
  if voulu and not public.session_confirmee() then
    raise exception 'Recevez et saisissez d''abord votre propre code : c''est la preuve que le SMS arrive, avant de l''exiger des superadministrateurs.';
  end if;
  select coalesce(nullif(trim(p.nom), ''), p.email, '') into qui
    from public.profils p where p.id = auth.uid();
  insert into public.securite_equipe (id, sms_exige, change_le, change_par)
  values (1, voulu, now(), coalesce(qui, ''))
  on conflict (id) do update
    set sms_exige = excluded.sms_exige,
        change_le = excluded.change_le,
        change_par = excluded.change_par;
  -- Au journal, au nom de celui qui décide : la ligne y est écrite par
  -- la base, pas par l'écran.
  insert into public.journal (famille, action, libelle, cible)
  values ('compte', 'modification',
          case when voulu
               then 'Connexion du superadministrateur : code SMS exigé (sauf appareil de confiance)'
               else 'Connexion du superadministrateur : code SMS plus exigé' end,
          '');
  return voulu;
end $$;
revoke all on function public.regler_sms_equipe(boolean) from public, anon;
grant execute on function public.regler_sms_equipe(boolean) to authenticated;

-- ---------- Les appareils de confiance (3.59.0) ----------
--
-- Le superadministrateur qui coche « Faire confiance à cet appareil »
-- n'y rend plus son code pendant 30 jours. L'appareil garde un jeton
-- tiré au hasard ; la base n'en garde que l'EMPREINTE — une copie de la
-- base ne permet pas de se faire passer pour l'appareil. Le mot de passe
-- reste demandé à chaque connexion : la confiance ne remplace que le SMS.
create table if not exists public.appareils_confiance (
  id          bigserial primary key,
  utilisateur uuid not null references auth.users(id) on delete cascade,
  empreinte   text not null,
  appareil    text not null default '',
  cree_le     timestamptz not null default now(),
  expire_le   timestamptz not null,
  constraint appareils_confiance_un unique (utilisateur, empreinte)
);
alter table public.appareils_confiance enable row level security;
revoke all on public.appareils_confiance from public, anon, authenticated;
revoke all on sequence public.appareils_confiance_id_seq from public, anon, authenticated;

-- Après le code : cet appareil devient de confiance pour 30 jours.
create or replace function public.confier_appareil(jeton text, appareil text default '')
returns timestamptz
language plpgsql security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  fin timestamptz := now() + interval '30 days';
begin
  if moi is null then raise exception 'Connectez-vous'; end if;
  if length(coalesce(jeton, '')) < 32 then raise exception 'Jeton d''appareil invalide'; end if;
  if not public.session_confirmee() then
    raise exception 'Saisissez d''abord le code reçu par SMS.' using errcode = 'P0001';
  end if;
  insert into public.appareils_confiance (utilisateur, empreinte, appareil, expire_le)
  values (moi, encode(sha256(convert_to(jeton, 'UTF8')), 'hex'), left(coalesce(appareil, ''), 120), fin)
  on conflict (utilisateur, empreinte) do update
    set expire_le = excluded.expire_le, cree_le = now(), appareil = excluded.appareil;
  return fin;
end $$;
revoke all on function public.confier_appareil(text, text) from public, anon;
grant execute on function public.confier_appareil(text, text) to authenticated;

-- À la connexion : un appareil de confiance encore valable confirme la
-- session sans SMS. Faux sinon — l'écran demande alors le code.
create or replace function public.reconnaitre_appareil(jeton text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  moi     uuid := auth.uid();
  session uuid := public.session_courante();
begin
  if moi is null or session is null or length(coalesce(jeton, '')) < 32 then return false; end if;
  if not exists (select 1 from public.appareils_confiance a
                  where a.utilisateur = moi
                    and a.empreinte = encode(sha256(convert_to(jeton, 'UTF8')), 'hex')
                    and a.expire_le > now()) then
    return false;
  end if;
  insert into public.sessions_sms (session_id, utilisateur)
  values (session, moi) on conflict (session_id) do nothing;
  return true;
end $$;
revoke all on function public.reconnaitre_appareil(text) from public, anon;
grant execute on function public.reconnaitre_appareil(text) to authenticated;

-- « Oublier mes appareils de confiance » : le code sera redemandé
-- partout, à la prochaine connexion. On fait EXPIRER la confiance plutôt
-- que d'effacer la ligne : même effet, et la trace reste.
create or replace function public.oublier_appareils()
returns int
language plpgsql security definer set search_path = public as $$
declare combien int;
begin
  if auth.uid() is null then raise exception 'Connectez-vous'; end if;
  update public.appareils_confiance a
     set expire_le = now() - interval '1 second'
   where a.utilisateur = auth.uid() and a.expire_le > now();
  get diagnostics combien = row_count;
  return combien;
end $$;
revoke all on function public.oublier_appareils() from public, anon;
grant execute on function public.oublier_appareils() to authenticated;

-- Combien d'appareils de confiance encore valables : l'écran du compte
-- le dit, et propose de les oublier.
create or replace function public.mes_appareils_confiance()
returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from public.appareils_confiance a
   where a.utilisateur = auth.uid() and a.expire_le > now();
$$;
revoke all on function public.mes_appareils_confiance() from public, anon;
grant execute on function public.mes_appareils_confiance() to authenticated;

-- ---------- Qui a créé le compte ----------
-- Un nom lisible, figé au moment de la création : « Awa (superadministrateur) ».
create or replace function public.nom_du_createur(qui uuid)
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(trim(p.nom), ''), nullif(p.email, ''), 'compte inconnu')
         || ' (' || p.role || ')'
    from public.profils p
   where p.id = qui;
$$;
revoke all on function public.nom_du_createur(uuid) from public, anon, authenticated;

-- LA BASE ÉCRIT LA TRACE, L'APPLICATION NE FAIT QUE LA LIRE.
--
-- Le créateur, c'est le compte de l'équipe qui donne ses droits à une
-- fiche toute fraîche — encore en attente, née dans le quart d'heure.
-- C'est exactement ce que fait « Créer un compte » : l'inscription pose
-- la fiche, et une seconde plus tard l'administrateur lui donne son rang.
-- Une fiche réveillée plus tard — un compte inscrit hors de
-- l'application, qu'on active des jours après — n'a pas de créateur : on
-- ne prête pas à celui qui active un compte qu'il n'a pas créé.
--
-- Et ce qui ne se déclare pas : ni le créateur, ni la date, ni un numéro
-- vérifié. Changer de numéro annule sa vérification — sans quoi on
-- vérifierait un numéro, puis on le remplacerait par un autre.
--
-- « bizzoo.compte » est ce qui distingue les écritures de confiance —
-- le code rendu, le rattrapage plus bas — d'une requête ordinaire.
create or replace function public.profil_trace() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  qui  uuid := auth.uid();
  deja public.profils%rowtype;
begin
  if coalesce(current_setting('bizzoo.compte', true), '') = 'oui' then
    return new;
  end if;

  -- (3.59.0) ON NE TOUCHE PAS À SON CRÉATEUR, par aucun chemin : ni
  -- l'écran, ni l'Historique, ni une fonction de la base.
  if tg_op = 'UPDATE' and public.est_mon_createur(old.id) then
    raise exception 'Ce compte vous a créé : vous ne pouvez pas modifier ses droits.'
      using errcode = 'P0001';
  end if;

  if tg_op = 'INSERT' then
    -- UNE FICHE QUI EXISTE DÉJÀ NE NAÎT PAS UNE SECONDE FOIS. Une insertion
    -- qui la vise finit en mise à jour (« on conflict ») : c'est ainsi que
    -- l'Historique remet la fiche d'avant quand on annule, ENTIÈRE. Elle
    -- passe d'abord par ici, et « excluded » porte ce que cette règle y
    -- a mis : y nommer le créateur du moment faisait échouer toute
    -- annulation sur « la création ne se réécrit pas ». On y reporte donc
    -- la trace en place, et la règle de la mise à jour juge le reste.
    select * into deja from public.profils where id = new.id;
    if found then
      new.cree_par := deja.cree_par;
      new.cree_par_nom := deja.cree_par_nom;
      new.cree_le := deja.cree_le;
      new.tel_verifie := deja.tel_verifie;
      new.tel_verifie_le := deja.tel_verifie_le;
      return new;
    end if;

    new.cree_par := null;
    new.cree_par_nom := '';
    new.cree_le := now();
    new.tel_verifie := false;
    new.tel_verifie_le := null;
    if qui is not null and qui <> new.id
       and (public.est_super() or public.est_admin()) then
      new.cree_par := qui;
      new.cree_par_nom := coalesce(public.nom_du_createur(qui), '');
    end if;
    return new;
  end if;

  if new.cree_par is distinct from old.cree_par
     or new.cree_par_nom is distinct from old.cree_par_nom
     or new.cree_le is distinct from old.cree_le then
    raise exception 'La création d''un compte ne se réécrit pas';
  end if;
  if new.tel_verifie is distinct from old.tel_verifie
     or new.tel_verifie_le is distinct from old.tel_verifie_le then
    raise exception 'Un numéro ne se déclare pas vérifié : c''est le code reçu par SMS qui le vérifie';
  end if;

  if regexp_replace(coalesce(new.tel, ''), '\D', '', 'g')
     is distinct from regexp_replace(coalesce(old.tel, ''), '\D', '', 'g') then
    new.tel_verifie := false;
    new.tel_verifie_le := null;
  end if;

  if old.cree_par is null and not old.actif
     and old.cree_le > now() - interval '15 minutes'
     and qui is not null and qui <> old.id
     and (public.est_super() or public.est_admin()) then
    new.cree_par := qui;
    new.cree_par_nom := coalesce(public.nom_du_createur(qui), '');
  end if;
  return new;
end $$;

create or replace trigger profils_trace
  before insert or update on public.profils
  for each row execute function public.profil_trace();

-- ---------- Le compte à valider (3.63.0) ----------
-- Demande du CEO : l'administrateur de BIZZOO crée un compte modérateur,
-- le superadministrateur le valide.
--   — Créé ou retouché par l'administrateur de BIZZOO, un modérateur
--     reste INACTIF et « à valider », quoi que dise la requête.
--   — Seul le superadministrateur l'active ; l'activer le valide.
--   — Personne d'autre n'y touche : ni l'administrateur de la boutique
--     concernée, qui pourrait sinon l'activer par la porte d'à côté, ni
--     une requête qui écrirait « a_valider » elle-même.
-- Les superadministrateurs sont prévenus à la création ; le créateur, à
-- la validation.
-- Après « profils_trace » (ordre des noms) : « cree_par » est déjà posé.
create or replace function public.profil_validation() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  nouveau boolean;
begin
  if coalesce(current_setting('bizzoo.compte', true), '') = 'oui' then
    return new;
  end if;

  if public.est_admin_bizzoo() and new.role = 'moderateur' then
    new.actif := false;
    new.a_valider := true;
    -- L'écran pose le rang par « insert … on conflict » : PostgreSQL exige
    -- alors que la ligne PROPOSÉE soit lisible par son auteur, et elle ne
    -- l'est que par son créateur. Sur une fiche qui n'en a pas encore, il
    -- l'est ; « profil_trace » en fera autant sur la mise à jour.
    if tg_op = 'INSERT' and new.cree_par is null then
      new.cree_par := auth.uid();
    end if;
    -- Une insertion qui vise une fiche existante finira en mise à jour
    -- (« on conflict ») : on ne prévient qu'une fois, sur la mise à jour.
    nouveau := case when tg_op = 'INSERT'
                    then not exists (select 1 from public.profils p where p.id = new.id)
                    else not old.a_valider end;
    if nouveau then
      perform public.notifier(public.les_superadmins(), 'compte_a_valider',
        'Un compte modérateur à valider',
        coalesce(nullif(trim(new.nom), ''), nullif(new.email, ''), 'Un nouveau compte') ||
          ', créé par ' || coalesce(public.nom_du_createur(auth.uid()), 'un administrateur de BIZZOO') ||
          '. Activez-le dans Comptes pour le valider.',
        '#/comptes', null, null, false);
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.a_valider := false;
    return new;
  end if;

  if public.est_super() then
    -- Activer, c'est valider.
    new.a_valider := old.a_valider and not new.actif;
    if old.a_valider and not new.a_valider and old.cree_par is not null then
      perform public.notifier(array[old.cree_par], 'compte_valide',
        'Compte validé',
        coalesce(nullif(trim(new.nom), ''), nullif(new.email, ''), 'Le compte') ||
          ' a été validé : il peut travailler.',
        '#/comptes', null, null, false);
    end if;
  else
    new.a_valider := old.a_valider;
    if old.a_valider then new.actif := false; end if;
  end if;
  return new;
end $$;

drop trigger if exists profils_validation on public.profils;
create trigger profils_validation
  before insert or update on public.profils
  for each row execute function public.profil_validation();

-- ---------- Rattraper la trace des comptes d'avant ----------
-- Les comptes créés avant ce fichier n'ont pas de créateur en fiche,
-- mais le journal s'en souvient : « Modérateur ajouté : … », écrit au
-- nom de celui qui l'a créé. On le reprend — une seule fois par compte,
-- et seulement là où la fiche ne dit rien. Un compte né hors de
-- l'application n'a pas de ligne au journal : il reste sans créateur, et
-- l'écran le dit.
create or replace function public.rattraper_createurs() returns int
language plpgsql security definer set search_path = public as $$
declare combien int := 0;
begin
  perform set_config('bizzoo.compte', 'oui', true);
  update public.profils p
     set cree_par = c.id,
         cree_par_nom = case
           when c.id is not null
             then coalesce(nullif(trim(c.nom), ''), nullif(c.email, ''), j.utilisateur)
                  || ' (' || c.role || ')'
           else j.utilisateur end
    from (select distinct on (lower(x.cible)) lower(x.cible) as adresse,
                 x.utilisateur
            from public.journal x
           where x.famille = 'compte' and x.action = 'ajout'
             and x.cible <> '' and x.utilisateur <> ''
           order by lower(x.cible), x.fait_le) j
    left join public.profils c on lower(c.email) = lower(j.utilisateur)
   where p.cree_par is null and p.cree_par_nom = ''
     and lower(p.email) = j.adresse;
  get diagnostics combien = row_count;
  perform set_config('bizzoo.compte', '', true);
  return combien;
end $$;
revoke all on function public.rattraper_createurs() from public, anon, authenticated;
select public.rattraper_createurs();


-- =========================================================
-- Les codes des particuliers : une commission sur chaque vente
-- =========================================================
-- Un particulier reçoit un code. Le client qui le tape a sa remise ;
-- le propriétaire touche un pourcentage de la commande sur son compte
-- BIZZOO, qu'il voit dans l'application client et qu'il retire vers son
-- numéro Mobile Money.
--
-- QUAND : à la LIVRAISON. La commission naît quand toutes les parts de
-- la commande sont remises au client (les parts annulées ne comptent
-- pas). Une commande annulée, ou jamais livrée, ne rapporte rien : il n'y
-- a jamais de commission à reprendre.
--
-- COMBIEN : le taux du code, sur ce que le client a payé pour sa
-- commande (remise déduite). PLAFONNÉ par ce que l'enseigne gagne encore
-- sur la commande après la remise : la boutique touche son prix BIZZOO en
-- entier, et une commission ne fait jamais vendre à perte.
--
-- UNE FOIS : une commission par commande, au plus — la base le garantit
-- par une contrainte, pas par une précaution de l'application.
--
-- LES RETRAITS : le propriétaire DEMANDE ; le superadministrateur verse
-- sur le numéro Mobile Money, puis marque « payé ». Pendant la demande,
-- le montant n'est plus disponible : on ne retire pas deux fois la même
-- somme.

alter table public.codes_promo add column if not exists parrain uuid;
alter table public.codes_promo add column if not exists commission numeric(5,2) not null default 0;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'codes_promo_commission_borne') then
    alter table public.codes_promo
      add constraint codes_promo_commission_borne check (commission between 0 and 50);
  end if;
end $$;
create index if not exists codes_promo_parrain on public.codes_promo(parrain) where parrain is not null;

create table if not exists public.gains_parrain (
  id          bigserial primary key,
  parrain     uuid not null,
  commande_id text unique,
  code        text not null default '',
  base        bigint not null default 0,
  taux        numeric(5,2) not null default 0,
  montant     bigint not null check (montant >= 0),
  cree_le     timestamptz not null default now()
);
create index if not exists gains_parrain_qui on public.gains_parrain(parrain, cree_le desc);

create table if not exists public.retraits_parrain (
  id          bigserial primary key,
  parrain     uuid not null,
  montant     bigint not null check (montant > 0),
  numero      text not null,
  reseau      text not null default '',
  etat        text not null default 'demande' check (etat in ('demande', 'payee', 'refusee')),
  demande_le  timestamptz not null default now(),
  traite_le   timestamptz,
  traite_par  uuid,
  reference   text not null default '',
  motif       text not null default ''
);
create index if not exists retraits_parrain_qui on public.retraits_parrain(parrain, demande_le desc);

-- Lecture : chacun les siennes, le superadministrateur toutes. AUCUNE
-- écriture directe : tout passe par les fonctions plus bas.
alter table public.gains_parrain enable row level security;
alter table public.retraits_parrain enable row level security;
drop policy if exists "gains lecture" on public.gains_parrain;
create policy "gains lecture" on public.gains_parrain
  for select using (parrain = auth.uid() or public.est_super());
drop policy if exists "retraits lecture" on public.retraits_parrain;
create policy "retraits lecture" on public.retraits_parrain
  for select using (parrain = auth.uid() or public.est_super());
revoke insert, update, delete on public.gains_parrain from anon, authenticated;
revoke insert, update, delete on public.retraits_parrain from anon, authenticated;
grant select on public.gains_parrain to authenticated;
grant select on public.retraits_parrain to authenticated;

-- ---------- Créditer, à la livraison ----------
create or replace function public.crediter_parrain(cible text) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  c        public.commandes%rowtype;
  k        public.codes_promo%rowtype;
  restant  int;
  livrees  int;
  marge    bigint;
  brut     bigint;
  montant  bigint;
begin
  select * into c from public.commandes where id = cible;
  if not found or c.etat <> 'payee' or coalesce(c.code_promo, '') = '' then return 0; end if;
  select * into k from public.codes_promo where code = c.code_promo;
  if not found or k.parrain is null or coalesce(k.commission, 0) <= 0 then return 0; end if;
  if exists (select 1 from public.gains_parrain g where g.commande_id = cible) then return 0; end if;

  select count(*) filter (where l.etat not in ('remise', 'annulee')),
         count(*) filter (where l.etat = 'remise'),
         coalesce(sum(greatest(0, l.prix - l.prix_bizzoo) * l.quantite)
                    filter (where l.etat <> 'annulee'), 0)
    into restant, livrees, marge
    from public.commande_lignes l where l.commande_id = cible;
  if restant > 0 or livrees = 0 then return 0; end if;

  -- Sur les ARTICLES, remise déduite : les frais de livraison paient la
  -- course, ils ne rapportent rien au propriétaire du code.
  brut := round(greatest(0, c.total - coalesce(c.frais_livraison, 0))
                * least(50, greatest(0, k.commission)) / 100)::bigint;
  montant := least(brut, greatest(0, marge - coalesce(c.remise, 0)));
  if montant <= 0 then return 0; end if;

  insert into public.gains_parrain (parrain, commande_id, code, base, taux, montant)
  values (k.parrain, cible, k.code, greatest(0, c.total - coalesce(c.frais_livraison, 0)),
          k.commission, montant)
  on conflict (commande_id) do nothing;
  if not found then return 0; end if;

  perform public.notifier(array[k.parrain], 'commission',
    'Commission créditée',
    'La commande ' || c.numero || ' a été livrée : ' || montant::text ||
      ' FCFA sur votre solde.',
    '#/compte', null, null, true);
  return montant;
end $$;
revoke all on function public.crediter_parrain(text) from public, anon, authenticated;

create or replace function public.lignes_creditent_parrain() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.etat is distinct from old.etat and new.etat in ('remise', 'annulee') then
    -- Jamais d'échec ici : une commission manquée se rattrape, une
    -- livraison refusée à cause d'elle, non.
    begin
      perform public.crediter_parrain(new.commande_id);
    exception when others then
      raise warning 'commission non créditée pour % : %', new.commande_id, sqlerrm;
    end;
  end if;
  return new;
end $$;
drop trigger if exists lignes_creditent_parrain on public.commande_lignes;
create trigger lignes_creditent_parrain
  after update of etat on public.commande_lignes
  for each row execute function public.lignes_creditent_parrain();

-- ---------- Ce que le propriétaire voit ----------
create or replace function public.mon_solde_parrain() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  moi     uuid := auth.uid();
  gagne   bigint;
  retire  bigint;
  attente bigint;
begin
  if moi is null or not exists (select 1 from public.codes_promo where parrain = moi) then
    return null;
  end if;
  select coalesce(sum(montant), 0) into gagne from public.gains_parrain where parrain = moi;
  select coalesce(sum(montant) filter (where etat = 'payee'), 0),
         coalesce(sum(montant) filter (where etat = 'demande'), 0)
    into retire, attente
    from public.retraits_parrain where parrain = moi;
  return jsonb_build_object(
    'codes', (select coalesce(jsonb_agg(jsonb_build_object(
                'code', k.code, 'remise', k.valeur, 'mode', k.mode,
                'commission', k.commission, 'actif', k.actif) order by k.code), '[]'::jsonb)
                from public.codes_promo k where k.parrain = moi),
    'gagne', gagne, 'retire', retire, 'en_attente', attente,
    'solde', gagne - retire - attente,
    'gains', (select coalesce(jsonb_agg(jsonb_build_object(
                'numero', o.numero, 'montant', g.montant, 'taux', g.taux,
                'base', g.base, 'le', g.cree_le) order by g.cree_le desc), '[]'::jsonb)
                from (select * from public.gains_parrain where parrain = moi
                       order by cree_le desc limit 30) g
                left join public.commandes o on o.id = g.commande_id),
    'retraits', (select coalesce(jsonb_agg(jsonb_build_object(
                'id', r.id, 'montant', r.montant, 'numero', r.numero, 'reseau', r.reseau,
                'etat', r.etat, 'le', r.demande_le, 'traite_le', r.traite_le,
                'motif', r.motif) order by r.demande_le desc), '[]'::jsonb)
                from (select * from public.retraits_parrain where parrain = moi
                       order by demande_le desc limit 30) r));
end $$;
revoke all on function public.mon_solde_parrain() from public, anon;
grant execute on function public.mon_solde_parrain() to authenticated;

-- ---------- Demander un retrait ----------
create or replace function public.demander_retrait(montant bigint, numero text, reseau text default '')
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  moi     uuid := auth.uid();
  numero_net text := regexp_replace(coalesce(numero, ''), '\D', '', 'g');
  solde   bigint;
  nouveau bigint;
begin
  if moi is null or not exists (select 1 from public.codes_promo where parrain = moi) then
    raise exception 'Ce compte n''a pas de code promo.' using errcode = 'P0001';
  end if;
  if coalesce(montant, 0) < 500 then
    raise exception 'Un retrait est de 500 FCFA au moins.' using errcode = 'P0001';
  end if;
  if length(numero_net) < 8 then
    raise exception 'Indiquez le numéro Mobile Money qui recevra l''argent.' using errcode = 'P0001';
  end if;
  -- DEUX DEMANDES EN MÊME TEMPS ne retirent pas deux fois la même somme.
  perform pg_advisory_xact_lock(hashtext('retrait:' || moi::text));
  select (select coalesce(sum(g.montant), 0) from public.gains_parrain g where g.parrain = moi)
       - (select coalesce(sum(r.montant), 0) from public.retraits_parrain r
           where r.parrain = moi and r.etat in ('demande', 'payee'))
    into solde;
  if montant > solde then
    raise exception 'Votre solde disponible est de % FCFA.', solde using errcode = 'P0001';
  end if;
  insert into public.retraits_parrain (parrain, montant, numero, reseau)
  values (moi, montant, numero_net, upper(left(coalesce(reseau, ''), 20)))
  returning id into nouveau;
  perform public.notifier(
    array(select p.id from public.profils p where p.role = 'superadministrateur' and p.actif),
    'retrait_demande', 'Demande de retrait',
    montant::text || ' FCFA vers ' || numero_net || ' — code promo d''un particulier.',
    '#/codes', null, null, true);
  return nouveau;
end $$;
revoke all on function public.demander_retrait(bigint, text, text) from public, anon;
grant execute on function public.demander_retrait(bigint, text, text) to authenticated;

-- ---------- Côté superadministrateur ----------
-- Donner un code à un compte (créé juste avant, comme client).
create or replace function public.creer_code_parrain(
  compte uuid, le_code text, remise numeric, taux numeric, nom text default '')
returns text
language plpgsql security definer set search_path = public as $$
declare cle text := public.code_normalise(le_code);
begin
  if not public.est_super() then
    raise exception 'Réservé au superadministrateur.' using errcode = '42501';
  end if;
  if compte is null or not exists (select 1 from auth.users u where u.id = compte) then
    raise exception 'Ce compte n''existe pas.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.profils p where p.id = compte and p.role is not null
               and p.actif) then
    raise exception 'Un compte de l''équipe ne reçoit pas de code de particulier.' using errcode = 'P0001';
  end if;
  if length(cle) < 3 then
    raise exception 'Le code fait au moins 3 lettres ou chiffres.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.codes_promo where code = cle) then
    raise exception 'Le code % existe déjà.', cle using errcode = 'P0001';
  end if;
  if coalesce(taux, 0) <= 0 or taux > 50 then
    raise exception 'La commission va de 0,5 à 50 %%.' using errcode = 'P0001';
  end if;
  if coalesce(remise, 0) < 0 or remise > 50 then
    raise exception 'La remise du client va de 0 à 50 %%.' using errcode = 'P0001';
  end if;
  insert into public.codes_promo (code, libelle, mode, valeur, une_par_client, actif,
                                  parrain, commission, cree_par)
  values (cle, coalesce(nullif(trim(nom), ''), 'Code de particulier'), 'pourcent',
          coalesce(remise, 0), false, true, compte, taux,
          coalesce((select email from public.profils where id = auth.uid()), ''));
  return cle;
end $$;
revoke all on function public.creer_code_parrain(uuid, text, numeric, numeric, text) from public, anon;
grant execute on function public.creer_code_parrain(uuid, text, numeric, numeric, text) to authenticated;

create or replace function public.parrains_liste()
returns table (code text, libelle text, parrain uuid, email text, remise numeric,
               commission numeric, actif boolean, ventes int, gagne bigint,
               retire bigint, en_attente bigint, solde bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.est_super() then return; end if;
  return query
    select k.code, k.libelle, k.parrain, coalesce(u.email, '')::text, k.valeur, k.commission, k.actif,
           (select count(*)::int from public.gains_parrain g where g.code = k.code),
           coalesce((select sum(g.montant) from public.gains_parrain g where g.parrain = k.parrain), 0)::bigint,
           coalesce((select sum(r.montant) from public.retraits_parrain r
                      where r.parrain = k.parrain and r.etat = 'payee'), 0)::bigint,
           coalesce((select sum(r.montant) from public.retraits_parrain r
                      where r.parrain = k.parrain and r.etat = 'demande'), 0)::bigint,
           (coalesce((select sum(g.montant) from public.gains_parrain g where g.parrain = k.parrain), 0)
            - coalesce((select sum(r.montant) from public.retraits_parrain r
                         where r.parrain = k.parrain and r.etat in ('demande', 'payee')), 0))::bigint
      from public.codes_promo k
      left join auth.users u on u.id = k.parrain
     where k.parrain is not null
     order by k.code;
end $$;
revoke all on function public.parrains_liste() from public, anon;
grant execute on function public.parrains_liste() to authenticated;

create or replace function public.retraits_a_traiter()
returns table (id bigint, code text, email text, montant bigint, numero text, reseau text,
               etat text, demande_le timestamptz, traite_le timestamptz, reference text, motif text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.est_super() then return; end if;
  return query
    select r.id,
           coalesce((select string_agg(k.code, ', ') from public.codes_promo k
                      where k.parrain = r.parrain), '')::text,
           coalesce(u.email, '')::text, r.montant, r.numero, r.reseau, r.etat,
           r.demande_le, r.traite_le, r.reference, r.motif
      from public.retraits_parrain r
      left join auth.users u on u.id = r.parrain
     order by (r.etat = 'demande') desc, r.demande_le desc
     limit 100;
end $$;
revoke all on function public.retraits_a_traiter() from public, anon;
grant execute on function public.retraits_a_traiter() to authenticated;

create or replace function public.traiter_retrait(cible bigint, payee boolean,
  la_reference text default '', le_motif text default '')
returns text
language plpgsql security definer set search_path = public as $$
declare r public.retraits_parrain%rowtype;
begin
  if not public.est_super() then
    raise exception 'Réservé au superadministrateur.' using errcode = '42501';
  end if;
  select * into r from public.retraits_parrain where id = cible for update;
  if not found then raise exception 'Demande introuvable.' using errcode = 'P0001'; end if;
  if r.etat <> 'demande' then
    raise exception 'Cette demande est déjà traitée.' using errcode = 'P0001';
  end if;
  update public.retraits_parrain
     set etat = case when payee then 'payee' else 'refusee' end,
         traite_le = now(), traite_par = auth.uid(),
         reference = left(coalesce(la_reference, ''), 80),
         motif = left(coalesce(le_motif, ''), 300)
   where id = cible;
  perform public.notifier(array[r.parrain], 'retrait',
    case when payee then 'Retrait versé' else 'Retrait refusé' end,
    case when payee
      then r.montant::text || ' FCFA ont été envoyés au ' || r.numero || '.'
      else 'Votre demande de ' || r.montant::text || ' FCFA n''a pas été versée'
           || coalesce(' : ' || nullif(le_motif, ''), '.') end,
    '#/compte', null, null, true);
  return case when payee then 'payee' else 'refusee' end;
end $$;
revoke all on function public.traiter_retrait(bigint, boolean, text, text) from public, anon;
grant execute on function public.traiter_retrait(bigint, boolean, text, text) to authenticated;

-- =========================================================
-- LE LIVE TIKTOK (3.58.0)
-- =========================================================
-- Une boutique passe en direct sur TikTok : son administrateur touche
-- « Démarrer le live TikTok ». Tous les téléphones où l'application
-- BIZZOO est installée reçoivent une notification ; la toucher ouvre la
-- page TikTok de la boutique. Dans l'application et sur le site, un
-- bandeau « En live » le dit aussi tant que le live dure.
--
-- La base tient le live et décide QUI peut le lancer ; l'envoi de la
-- notification est l'affaire de la fonction Edge « annoncer-live », qui
-- seule détient le compte de service Firebase.
--
-- GARDE-FOUS. Une notification à tous les clients, c'est lourd : un live
-- déjà en cours ne se relance pas (pas de seconde notification), et une
-- boutique n'annonce pas plus de trois lives par jour. Un live oublié
-- s'éteint de lui-même au bout de quatre heures.

create table if not exists public.lives_tiktok (
  id          bigint generated always as identity primary key,
  boutique_id text not null references public.boutiques(id) on delete cascade,
  lien        text not null,
  debut       timestamptz not null default now(),
  fin         timestamptz,
  lance_par   uuid,
  annonce_le  timestamptz,
  annonce     text not null default ''
);
create index if not exists lives_tiktok_boutique on public.lives_tiktok(boutique_id, debut desc);

-- Personne ne lit la table directement : « lives_en_cours » en dit ce
-- qu'un client doit savoir, et rien de qui l'a lancé.
alter table public.lives_tiktok enable row level security;
revoke all on public.lives_tiktok from anon, authenticated;

-- Le lien TikTok d'une boutique, tel qu'un navigateur l'ouvre :
-- « @maboutique », « maboutique » ou une adresse complète.
create or replace function public.lien_tiktok(brut text) returns text
language sql immutable as $$
  select case
    when coalesce(trim(brut), '') = '' then ''
    when trim(brut) ~* '^https?://' then trim(brut)
    when trim(brut) ~* '^(www\.)?tiktok\.com/' then 'https://' || trim(brut)
    else 'https://www.tiktok.com/@' || regexp_replace(trim(brut), '^@+', '')
  end;
$$;

create or replace function public.lives_en_cours()
returns table (boutique_id text, nom text, lien text, debut timestamptz)
language sql stable security definer set search_path = public as $$
  select l.boutique_id, b.nom, l.lien, l.debut
    from public.lives_tiktok l
    join public.boutiques b on b.id = l.boutique_id and b.actif
   where l.fin is null and l.debut > now() - interval '4 hours'
   order by l.debut desc;
$$;
revoke all on function public.lives_en_cours() from public;
grant execute on function public.lives_en_cours() to anon, authenticated;

create or replace function public.demarrer_live(cible text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  b       public.boutiques%rowtype;
  lien    text;
  courant public.lives_tiktok%rowtype;
  nouveau bigint;
begin
  if not public.administre(cible) then
    raise exception 'Seul l''administrateur de la boutique lance son live.' using errcode = '42501';
  end if;
  select * into b from public.boutiques where id = cible;
  if not found then raise exception 'Boutique introuvable.' using errcode = 'P0001'; end if;
  if not b.actif then
    raise exception 'La boutique est fermée aux clients : ouvrez-la avant d''annoncer un live.'
      using errcode = 'P0001';
  end if;
  lien := public.lien_tiktok(b.tiktok);
  if lien = '' then
    raise exception 'Ajoutez d''abord le compte TikTok de la boutique (Réglages → Réseaux sociaux).'
      using errcode = 'P0001';
  end if;
  -- On ne lance pas deux fois le même live : pas de seconde notification.
  perform pg_advisory_xact_lock(hashtext('live:' || cible));
  select * into courant from public.lives_tiktok
   where boutique_id = cible and fin is null and debut > now() - interval '4 hours'
   order by debut desc limit 1;
  if found then
    return jsonb_build_object('id', courant.id, 'boutique', cible, 'nom', b.nom,
      'lien', courant.lien, 'deja', true);
  end if;
  if (select count(*) from public.lives_tiktok
       where boutique_id = cible and debut > now() - interval '24 hours') >= 3 then
    raise exception 'Trois lives annoncés en 24 heures : c''est le maximum, pour ne pas lasser les clients.'
      using errcode = 'P0001';
  end if;
  -- Un live oublié depuis plus de quatre heures se ferme ici.
  update public.lives_tiktok set fin = now() where boutique_id = cible and fin is null;
  insert into public.lives_tiktok (boutique_id, lien, lance_par)
  values (cible, lien, auth.uid()) returning id into nouveau;
  return jsonb_build_object('id', nouveau, 'boutique', cible, 'nom', b.nom,
    'lien', lien, 'deja', false);
end $$;
revoke all on function public.demarrer_live(text) from public, anon;
grant execute on function public.demarrer_live(text) to authenticated;

create or replace function public.arreter_live(cible text) returns int
language plpgsql security definer set search_path = public as $$
declare combien int;
begin
  if not public.administre(cible) then
    raise exception 'Seul l''administrateur de la boutique arrête son live.' using errcode = '42501';
  end if;
  update public.lives_tiktok set fin = now() where boutique_id = cible and fin is null;
  get diagnostics combien = row_count;
  return combien;
end $$;
revoke all on function public.arreter_live(text) from public, anon;
grant execute on function public.arreter_live(text) to authenticated;

-- La fonction Edge note ce qu'a répondu Firebase. Clé de service seule :
-- personne d'autre n'écrit qu'un live a été annoncé.
create or replace function public.noter_annonce_live(cible bigint, resultat text) returns void
language sql security definer set search_path = public as $$
  update public.lives_tiktok
     set annonce_le = now(), annonce = left(coalesce(resultat, ''), 300)
   where id = cible;
$$;
revoke all on function public.noter_annonce_live(bigint, text) from public, anon, authenticated;
grant execute on function public.noter_annonce_live(bigint, text) to service_role;

-- =========================================================
-- LA POSITION DES LIVREURS (3.58.0)
-- =========================================================
-- Un livreur VALIDE SON COMPTE en enregistrant sa position : la
-- géolocalisation de son téléphone, et son adresse écrite. BIZZOO Admin
-- le lui demande à la connexion, avant tout le reste ; tant qu'il ne
-- l'a pas fait, aucune course ne lui est confiée (« assigner_livreur »).
--
-- La position s'écrit par « enregistrer_ma_position », et par le livreur
-- lui-même : personne ne la pose à sa place, personne ne la retouche à
-- la main. L'enseigne les lit toutes ; une boutique, celles de ses
-- livreurs.

create table if not exists public.positions_livreurs (
  profil_id      uuid primary key references public.profils(id) on delete cascade,
  latitude       double precision not null,
  longitude      double precision not null,
  precision_m    int,
  adresse        text not null default '',
  enregistre_le  timestamptz not null default now()
);
alter table public.positions_livreurs enable row level security;
drop policy if exists "positions livreurs lecture" on public.positions_livreurs;
create policy "positions livreurs lecture" on public.positions_livreurs
  for select to authenticated
  using (profil_id = auth.uid()
         or public.est_super()
         or public.est_admin_bizzoo()
         or exists (select 1 from public.profils p
                     where p.id = positions_livreurs.profil_id
                       and public.administre(p.boutique_id)));
revoke all on public.positions_livreurs from anon;
revoke insert, update, delete on public.positions_livreurs from authenticated;
grant select on public.positions_livreurs to authenticated;

create or replace function public.enregistrer_ma_position(
  lat double precision, lng double precision, adresse text, precision_m int default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  la  double precision := public.coord_valable(lat, 90);
  lo  double precision := public.coord_valable(lng, 180);
  ad  text := left(trim(coalesce(adresse, '')), 200);
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Seul un livreur enregistre sa position ici.' using errcode = '42501';
  end if;
  -- « 0, 0 » : un téléphone qui n'a rien trouvé, jamais Cotonou.
  if la is null or lo is null or (la = 0 and lo = 0) then
    raise exception 'Position introuvable : activez la localisation du téléphone, puis réessayez.'
      using errcode = 'P0001';
  end if;
  if length(ad) < 3 then
    raise exception 'Indiquez aussi votre adresse : quartier, repère.' using errcode = 'P0001';
  end if;
  insert into public.positions_livreurs (profil_id, latitude, longitude, precision_m, adresse, enregistre_le)
  values (moi, la, lo, greatest(0, precision_m), ad, now())
  on conflict (profil_id) do update
     set latitude = excluded.latitude, longitude = excluded.longitude,
         precision_m = excluded.precision_m, adresse = excluded.adresse,
         enregistre_le = now();
  return jsonb_build_object('latitude', la, 'longitude', lo, 'adresse', ad, 'le', now());
end $$;
revoke all on function public.enregistrer_ma_position(double precision, double precision, text, int)
  from public, anon;
grant execute on function public.enregistrer_ma_position(double precision, double precision, text, int)
  to authenticated;


-- =========================================================
-- BIZZOO Personnel — la gestion interne des employés de BIZZOO
--
-- Une troisième application sur la même base : « personnel/ ».
-- Elle ne touche à AUCUNE table de la place de marché. Tout ce
-- qu'elle pose commence par « rh_ », pour qu'on ne confonde jamais
-- ses « profils » (Marketing, Logistique…) avec la table « profils »
-- des comptes d'équipe des boutiques.
--
-- Les rangs :
--   le CEO          — un seul ; il valide les employés, les rapports
--                     d'activité, les dépenses, les barèmes et la paie ;
--   l'administration — droits sur tous les profils : crée les
--                     employés (validés ensuite par le CEO), les
--                     missions, prépare la paie ;
--   le responsable  — d'un profil : accepte les missions, rend leurs
--                     rapports, publie les rapports d'activité,
--                     demande les dépenses ;
--   l'habilité      — décaisse ce que le CEO a approuvé, paie les
--                     fiches validées ;
--   chaque employé  — lit ses fiches de paie, ses mails, écrit aux
--                     membres de son profil.
--
-- Un employé ne vaut rien tant qu'il n'est pas « actif » : c'est
-- « rh_moi() » qui le dit, et toutes les règles en découlent.
--
-- Se colle tel quel dans l'éditeur SQL de Supabase, et se rejoue
-- sans rien casser.
-- =========================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- Les employés ----------
create sequence if not exists public.rh_matricule_seq;

create table if not exists public.rh_employes (
  id              uuid primary key default gen_random_uuid(),
  matricule       text not null unique
                  default 'BZ-' || lpad(nextval('public.rh_matricule_seq')::text, 4, '0'),
  -- Le compte de connexion. Rattaché après validation, par l'adresse
  -- professionnelle : jamais choisi dans une liste.
  compte_id       uuid unique references auth.users(id) on delete set null,
  nom             text not null check (length(btrim(nom)) > 0),
  prenoms         text not null default '',
  -- Vide tant que l'employé ne l'a pas dit (fiches importées d'un fichier).
  sexe            text check (sexe in ('M', 'F')),
  -- L'âge se calcule : une date de naissance ne vieillit pas de travers.
  date_naissance  date check (date_naissance > date '1930-01-01'),
  telephone       text not null default '',
  email_pro       text check (email_pro is null or email_pro ~* '^[^@\s]+@[^@\s]+\.[^@\s]+\Z'),
  email_perso     text not null default '',
  adresse         text not null default '',
  date_embauche   date not null,
  statut          text not null default 'employe' check (statut in ('stagiaire', 'employe')),
  niveau_etude    text not null default '',
  poste           text not null default '',
  salaire_base    bigint not null default 0 check (salaire_base >= 0),
  numero_cnss     text not null default '',
  mode_paiement   text not null default 'especes'
                  check (mode_paiement in ('especes', 'virement', 'mobile_money', 'cheque')),
  compte_paiement text not null default '',
  infos           text not null default '',
  profil_id       uuid,
  administration  boolean not null default false,
  ceo             boolean not null default false,
  peut_decaisser  boolean not null default false,
  etat            text not null default 'en_attente'
                  check (etat in ('en_attente', 'actif', 'refuse', 'sorti', 'bloque', 'supprime')),
  motif_refus     text not null default '',
  date_sortie     date,
  cree_par        uuid,
  cree_le         timestamptz not null default now(),
  valide_par      uuid,
  valide_le       timestamptz
);
-- Ce que la fiche du personnel de BIZZOO donne en plus (2026-10-25).
alter table public.rh_employes alter column sexe drop not null;
alter table public.rh_employes add column if not exists telephone_pro text not null default '';
alter table public.rh_employes add column if not exists equipement text not null default '';
alter table public.rh_employes add column if not exists langue text not null default '';
alter table public.rh_employes add column if not exists marie text not null default '';
alter table public.rh_employes add column if not exists moto boolean;
-- Une adresse professionnelle ne sert qu'à un employé : c'est par elle
-- qu'on rattache le compte et qu'on ouvre la boîte mail.
create unique index if not exists rh_employes_email_pro
  on public.rh_employes (lower(email_pro)) where email_pro is not null;
-- UN SEUL CEO. C'est lui qui valide tout : deux, et chacun validerait
-- ce que l'autre a refusé.
create unique index if not exists rh_employes_un_ceo
  on public.rh_employes (ceo) where ceo;

-- ---------- Les profils (Marketing, Logistique…) ----------
create table if not exists public.rh_profils (
  id             uuid primary key default gen_random_uuid(),
  nom            text not null check (length(btrim(nom)) > 0),
  description    text not null default '',
  responsable_id uuid references public.rh_employes(id) on delete set null,
  cree_le        timestamptz not null default now()
);
create unique index if not exists rh_profils_nom on public.rh_profils (lower(nom));

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'rh_employes_profil_fk') then
    alter table public.rh_employes add constraint rh_employes_profil_fk
      foreign key (profil_id) references public.rh_profils(id) on delete restrict;
  end if;
end $$;

-- ---------- Qui est connecté ----------
-- « security definer » : ces fonctions lisent les tables sans repasser
-- par les règles RLS — sinon les règles s'appelleraient elles-mêmes.

/** L'employé du compte connecté, s'il est ACTIF. Tout en découle. */
create or replace function public.rh_moi() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_est_ceo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and ceo);
$$;

/** L'administration, CEO compris : droits sur tous les profils. */
create or replace function public.rh_est_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and (administration or ceo));
$$;

/** Décaisser (dépenses, salaires), c'est tenir la caisse : le seul
    gestionnaire de caisse désigné par le CEO. Sans la table de la caisse
    (fichier rejoué seul sur une base plus ancienne), l'ancien droit. */
create or replace function public.rh_peut_decaisser() returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if to_regclass('public.rh_caisse') is null then
    return exists (select 1 from public.rh_employes
                    where compte_id = auth.uid() and etat = 'actif' and peut_decaisser);
  end if;
  return exists (select 1 from public.rh_caisse c
                   join public.rh_employes e on e.id = c.gestionnaire_id
                  where e.compte_id = auth.uid() and e.etat = 'actif');
end $$;

create or replace function public.rh_mon_profil() returns uuid
language sql stable security definer set search_path = public as $$
  select profil_id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_responsable_de(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select cible is not null and exists (
    select 1 from public.rh_profils p
     where p.id = cible and p.responsable_id is not null
       and p.responsable_id = public.rh_moi());
$$;

/** Membre du profil : y être rangé, ou le diriger. */
create or replace function public.rh_membre_de(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select cible is not null
     and (public.rh_mon_profil() = cible or public.rh_responsable_de(cible));
$$;

/** Ce menu est-il ouvert à mon compte POUR CE PROFIL ? L'administration
    voit tout ; sinon il faut une ligne de rh_acces_menus (menu Paramètres) :
    « membres » vaut pour qui est rangé dans le profil, et le responsable
    passe dans les deux cas. Sans la table (fichier rejoué seul sur une
    base plus ancienne), les règles d'avant : être membre du profil. */
create or replace function public.rh_acces(cible uuid, cle text) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rh_est_admin() then
    return true;
  end if;
  if cible is null or public.rh_moi() is null then
    return false;
  end if;
  if to_regclass('public.rh_acces_menus') is null then
    return public.rh_membre_de(cible);
  end if;
  return exists (
    select 1 from public.rh_acces_menus a
     where a.profil_id = cible and a.menu = cle
       and (public.rh_responsable_de(cible)
            or (a.qui = 'membres' and public.rh_mon_profil() = cible)));
end $$;

/** Ce menu est-il ouvert à mon compte, par l'un de mes profils ? Un
    employé sans profil (ni profil à diriger) garde sa boîte mail et ses
    messages directs. */
create or replace function public.rh_menu_ouvert(cle text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_moi uuid := public.rh_moi();
  v_profil uuid := public.rh_mon_profil();
begin
  if public.rh_est_admin() then
    return true;
  end if;
  if v_moi is null then
    return false;
  end if;
  if to_regclass('public.rh_acces_menus') is null then
    return cle in ('mails', 'discussions', 'missions', 'rapports');
  end if;
  if v_profil is null and not exists (select 1 from public.rh_profils p where p.responsable_id = v_moi) then
    return cle in ('mails', 'discussions', 'depenses');
  end if;
  return exists (
    select 1 from public.rh_acces_menus a
      join public.rh_profils p on p.id = a.profil_id
     where a.menu = cle
       and (p.responsable_id = v_moi or (a.qui = 'membres' and p.id = v_profil)));
end $$;

-- ---------- Les verrous de la fiche employé ----------
-- Les règles RLS disent QUI écrit ; ce déclencheur dit QUOI. Les
-- décisions (valider, refuser, faire sortir, rattacher un compte) ne
-- passent que par leurs fonctions, qui posent le drapeau « rh.decision ».
create or replace function public.rh_employe_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  decision boolean := coalesce(current_setting('rh.decision', true), '') = 'oui';
  -- Le superadministrateur de BIZZOO modifie une fiche comme le CEO.
  ceo_connecte boolean := public.rh_est_ceo() or public.est_super();
  admin_connecte boolean := public.rh_est_admin() or public.est_super();
  libres text[];
begin
  if tg_op = 'INSERT' then
    if decision then
      return new;
    end if;
    if not admin_connecte then
      raise exception 'Seule l''administration crée un employé';
    end if;
    new.compte_id := null;
    new.ceo := false;
    new.cree_par := public.rh_moi();
    new.cree_le := now();
    new.motif_refus := '';
    new.date_sortie := null;
    /* Les droits ne se proposent pas : le CEO les donne lui-même. */
    if not ceo_connecte then
      new.administration := false;
      new.peut_decaisser := false;
    end if;
    /* Le CEO n'a pas à valider ce qu'il crée lui-même. */
    if ceo_connecte then
      new.etat := 'actif';
      new.valide_par := public.rh_moi();
      new.valide_le := now();
    else
      new.etat := 'en_attente';
      new.valide_par := null;
      new.valide_le := null;
    end if;
    return new;
  end if;

  -- Modification
  if decision then
    return new;
  end if;
  if old.ceo and not ceo_connecte then
    raise exception 'La fiche du CEO ne se modifie que par lui';
  end if;

  if not admin_connecte then
    /* L'employé lui-même : ses coordonnées, rien d'autre. */
    /* Il complète ce qui le regarde. Son téléphone, non : c'est par lui
       qu'il se connecte ; l'administration le change. */
    libres := array['adresse', 'email_perso', 'sexe', 'date_naissance', 'langue', 'marie', 'moto'];
    if (to_jsonb(new) - libres) is distinct from (to_jsonb(old) - libres) then
      raise exception 'Vous ne pouvez modifier que votre adresse, votre e-mail, votre sexe, votre date de naissance, votre langue, votre situation et votre moto : le reste passe par l''administration';
    end if;
    return new;
  end if;

  if new.compte_id is distinct from old.compte_id
     or new.ceo is distinct from old.ceo
     or new.etat is distinct from old.etat
     or new.motif_refus is distinct from old.motif_refus
     or new.date_sortie is distinct from old.date_sortie
     or new.cree_par is distinct from old.cree_par
     or new.cree_le is distinct from old.cree_le
     or new.valide_par is distinct from old.valide_par
     or new.valide_le is distinct from old.valide_le
     or new.matricule is distinct from old.matricule then
    raise exception 'Cette information ne change que par une décision (valider, refuser, sortie, compte)';
  end if;

  if not ceo_connecte then
    if new.administration is distinct from old.administration
       or new.peut_decaisser is distinct from old.peut_decaisser then
      raise exception 'Seul le CEO accorde les droits d''administration et de décaissement';
    end if;
    /* Le salaire d'un employé en poste engage la paie : au CEO. */
    if old.etat = 'actif' and new.salaire_base is distinct from old.salaire_base then
      raise exception 'Le salaire d''un employé en poste ne change que par le CEO';
    end if;
    /* Une fiche refusée qu'on corrige repart chez le CEO. */
    if old.etat = 'refuse' then
      new.etat := 'en_attente';
      new.motif_refus := '';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists rh_employes_verrous on public.rh_employes;
create trigger rh_employes_verrous
  before insert or update on public.rh_employes
  for each row execute function public.rh_employe_verrous();

-- Un employé qui quitte son profil (ou l'entreprise) n'en reste pas
-- le responsable : il dirigerait des gens dont il ne voit plus rien.
create or replace function public.rh_employe_apres() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.profil_id is distinct from old.profil_id or new.etat not in ('actif', 'bloque') then
    update public.rh_profils set responsable_id = null
     where responsable_id = new.id
       and (new.etat not in ('actif', 'bloque') or id is distinct from new.profil_id);
  end if;
  return null;
end $$;

drop trigger if exists rh_employes_apres on public.rh_employes;
create trigger rh_employes_apres
  after update on public.rh_employes
  for each row execute function public.rh_employe_apres();

-- Le responsable d'un profil en est membre, et il est en poste.
create or replace function public.rh_profil_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.responsable_id is not null and not exists (
       select 1 from public.rh_employes e
        where e.id = new.responsable_id and e.etat = 'actif' and e.profil_id = new.id) then
    raise exception 'Le responsable doit être un employé en poste, membre de ce profil';
  end if;
  return new;
end $$;

drop trigger if exists rh_profils_verrous on public.rh_profils;
create trigger rh_profils_verrous
  before insert or update on public.rh_profils
  for each row execute function public.rh_profil_verrous();

-- ---------- Un compte du personnel n'est pas un compte de boutique ----------
-- Tout compte créé reçoit d'ordinaire une fiche d'équipe en attente
-- (« profil_nouveau_compte »). Un employé créé depuis BIZZOO Personnel
-- s'inscrit avec « compte: personnel » : sans ce ménage, il apparaîtrait
-- dans la liste des comptes de l'enseigne, à un clic d'un rang de
-- modérateur. Ce déclencheur s'exécute APRÈS celui-là (ordre des noms).
create or replace function public.rh_compte_personnel() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.raw_user_meta_data ->> 'compte', '') = 'personnel' then
    delete from public.profils p
     where p.id = new.id and not p.actif and p.role = 'moderateur';
  end if;
  return new;
end $$;

drop trigger if exists rh_compte_personnel on auth.users;
create trigger rh_compte_personnel
  after insert on auth.users
  for each row execute function public.rh_compte_personnel();

-- ---------- Les décisions sur un employé ----------
create or replace function public.rh_decider_employe(employe uuid, accepter boolean, motif text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO valide un employé';
  end if;
  if not accepter and length(btrim(coalesce(motif, ''))) = 0 then
    raise exception 'Dites pourquoi vous refusez';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_employes
     set etat = case when accepter then 'actif' else 'refuse' end,
         motif_refus = case when accepter then '' else btrim(motif) end,
         valide_par = public.rh_moi(), valide_le = now()
   where id = employe and etat = 'en_attente';
  if not found then
    raise exception 'Cet employé n''attend pas de validation';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

create or replace function public.rh_sortie_employe(employe uuid, le date, motif text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO enregistre la sortie d''un employé';
  end if;
  if exists (select 1 from public.rh_employes where id = employe and ceo) then
    raise exception 'Le CEO ne se fait pas sortir lui-même';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_employes
     set etat = 'sorti', date_sortie = coalesce(le, current_date),
         motif_refus = btrim(coalesce(motif, ''))
   where id = employe and etat in ('actif', 'bloque');
  if not found then
    raise exception 'Cet employé n''est pas en poste';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

/**
 * Rattache le compte de connexion dont l'adresse est l'e-mail
 * professionnel de l'employé. L'application crée le compte (inscription,
 * « compte: personnel ») puis appelle ceci : on ne rattache jamais un
 * compte choisi dans une liste, toujours celui de SA propre adresse.
 */
create or replace function public.rh_rattacher_compte(employe uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  e public.rh_employes;
  compte uuid;
begin
  if not public.rh_est_admin() then
    raise exception 'Seule l''administration rattache un compte';
  end if;
  select * into e from public.rh_employes where id = employe;
  if not found or e.etat <> 'actif' then
    raise exception 'Seul un employé validé reçoit un accès';
  end if;
  if e.ceo and not public.rh_est_ceo() then
    raise exception 'La fiche du CEO ne se modifie que par lui';
  end if;
  if coalesce(e.email_pro, '') = '' then
    raise exception 'Renseignez d''abord l''e-mail professionnel de l''employé';
  end if;
  select u.id into compte from auth.users u where lower(u.email) = lower(e.email_pro);
  if compte is null then
    raise exception 'AUCUN_COMPTE : aucun compte n''existe encore pour %', e.email_pro;
  end if;
  if exists (select 1 from public.rh_employes x where x.compte_id = compte and x.id <> e.id) then
    raise exception 'Ce compte est déjà celui d''un autre employé';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_employes set compte_id = compte where id = e.id;
  perform set_config('rh.decision', '', true);
  return compte;
end $$;

/**
 * Le premier CEO. Personne ne peut valider le premier employé : on
 * l'amorce. Seul un superadministrateur de BIZZOO le peut, et une seule
 * fois — dès qu'un CEO existe, la porte est fermée.
 */
create or replace function public.rh_devenir_ceo(nom text, prenoms text, sexe text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  courriel text;
  nouveau uuid;
begin
  if not public.est_super() then
    raise exception 'Seul un superadministrateur de BIZZOO peut désigner le premier CEO';
  end if;
  if exists (select 1 from public.rh_employes where ceo) then
    raise exception 'BIZZOO a déjà son CEO dans l''application';
  end if;
  select email into courriel from auth.users where id = auth.uid();
  perform set_config('rh.decision', 'oui', true);
  update public.rh_employes
     set ceo = true, administration = true, etat = 'actif', valide_le = now()
   where compte_id = auth.uid()
  returning id into nouveau;
  if nouveau is null then
    insert into public.rh_employes (compte_id, nom, prenoms, sexe, email_pro, date_embauche,
                                    statut, ceo, administration, etat, cree_le, valide_le)
    values (auth.uid(), btrim(nom), btrim(coalesce(prenoms, '')), sexe, courriel, current_date,
            'employe', true, true, 'actif', now(), now())
    returning id into nouveau;
  end if;
  perform set_config('rh.decision', '', true);
  return nouveau;
end $$;

/**
 * Désigner le CEO sans l'être. Le superadministrateur qui installe
 * l'application n'est pas toujours le CEO : il inscrit le CEO par son
 * adresse professionnelle — le compte de connexion doit déjà exister,
 * l'application le crée juste avant —, et peut s'inscrire lui-même dans
 * l'administration pour préparer profils et employés en attendant.
 * Même porte que « rh_devenir_ceo » : un superadministrateur, une seule
 * fois, tant qu'aucun CEO n'existe.
 */
create or replace function public.rh_designer_ceo(nom text, prenoms text, sexe text, email_pro text,
                                                  moi_nom text default null, moi_prenoms text default '',
                                                  moi_sexe text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  courriel text := lower(btrim(coalesce(email_pro, '')));
  compte uuid;
  moi_courriel text;
  nouveau uuid;
begin
  if not public.est_super() then
    raise exception 'Seul un superadministrateur de BIZZOO peut désigner le CEO';
  end if;
  if exists (select 1 from public.rh_employes where ceo) then
    raise exception 'BIZZOO a déjà son CEO dans l''application';
  end if;
  if courriel = '' then
    raise exception 'Indiquez l''adresse professionnelle du CEO';
  end if;
  select u.id into compte from auth.users u where lower(u.email) = courriel;
  if compte is null then
    raise exception 'AUCUN_COMPTE : aucun compte n''existe encore pour %', courriel;
  end if;
  if compte = auth.uid() then
    raise exception 'C''est votre propre adresse : choisissez « Je suis le CEO »';
  end if;
  if exists (select 1 from public.rh_employes x
              where x.compte_id = compte or lower(x.email_pro) = courriel) then
    raise exception 'Cette adresse est déjà celle d''un employé';
  end if;
  perform set_config('rh.decision', 'oui', true);
  insert into public.rh_employes (compte_id, nom, prenoms, sexe, email_pro, date_embauche,
                                  statut, ceo, administration, etat, cree_par, cree_le, valide_le)
  values (compte, btrim(nom), btrim(coalesce(prenoms, '')), sexe, courriel, current_date,
          'employe', true, true, 'actif', null, now(), now())
  returning id into nouveau;
  if btrim(coalesce(moi_nom, '')) <> '' then
    if exists (select 1 from public.rh_employes where compte_id = auth.uid()) then
      raise exception 'Votre compte a déjà une fiche employé';
    end if;
    select u.email into moi_courriel from auth.users u where u.id = auth.uid();
    insert into public.rh_employes (compte_id, nom, prenoms, sexe, email_pro, date_embauche,
                                    statut, administration, etat, cree_le, valide_par, valide_le)
    values (auth.uid(), btrim(moi_nom), btrim(coalesce(moi_prenoms, '')), moi_sexe, lower(moi_courriel),
            current_date, 'employe', true, 'actif', now(), nouveau, now());
  end if;
  perform set_config('rh.decision', '', true);
  return nouveau;
end $$;

/** L'annuaire : qui est qui, sans le salaire. Pour tout employé en poste. */
create or replace function public.rh_annuaire()
returns table (id uuid, matricule text, nom text, prenoms text, sexe text, poste text,
               profil_id uuid, profil text, email_pro text, telephone text,
               administration boolean, ceo boolean, responsable boolean, a_un_compte boolean)
language sql stable security definer set search_path = public as $$
  /* Un employé ordinaire n'y lit que ce qui sert à joindre un collègue :
     nom, poste, profil, e-mail et téléphone PROFESSIONNELS. Le matricule,
     le sexe et le numéro personnel (celui qui sert à se connecter) ne
     sortent que pour l'administration, le CEO et le superadministrateur. */
  select e.id,
         case when public.rh_est_admin() or public.est_super() then e.matricule end,
         e.nom, e.prenoms,
         case when public.rh_est_admin() or public.est_super() then e.sexe end,
         e.poste, e.profil_id, coalesce(p.nom, ''),
         e.email_pro,
         case when public.rh_est_admin() or public.est_super() then e.telephone else nullif(e.telephone_pro, '') end,
         e.administration, e.ceo,
         exists (select 1 from public.rh_profils r where r.responsable_id = e.id),
         e.compte_id is not null
    from public.rh_employes e
    left join public.rh_profils p on p.id = e.profil_id
   where e.etat = 'actif' and public.rh_moi() is not null
   order by e.nom, e.prenoms;
$$;

-- ---------- La messagerie interne ----------
create table if not exists public.rh_messages (
  id             bigint generated always as identity primary key,
  -- La discussion d'un profil, OU un message à une personne.
  profil_id      uuid references public.rh_profils(id) on delete cascade,
  destinataire_id uuid references public.rh_employes(id) on delete cascade,
  auteur_id      uuid not null references public.rh_employes(id) on delete cascade,
  texte          text not null check (length(btrim(texte)) between 1 and 4000),
  cree_le        timestamptz not null default now(),
  constraint rh_messages_une_cible check ((profil_id is null) <> (destinataire_id is null))
);
create index if not exists rh_messages_profil on public.rh_messages (profil_id, id);
create index if not exists rh_messages_prive on public.rh_messages (destinataire_id, auteur_id, id);
-- Le fil général, « Tout le monde » : un message n'a alors ni profil ni
-- destinataire. Une et une seule cible : un profil, une personne, ou tous.
alter table public.rh_messages add column if not exists general boolean not null default false;
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'rh_messages_une_cible'
               and pg_get_constraintdef(oid) not like '%general%') then
    alter table public.rh_messages drop constraint rh_messages_une_cible;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_messages_une_cible') then
    alter table public.rh_messages add constraint rh_messages_une_cible
      check (num_nonnulls(profil_id, destinataire_id) + case when general then 1 else 0 end = 1);
  end if;
end $$;
create index if not exists rh_messages_general on public.rh_messages (id) where general;

/** Peut-on écrire à cette personne ? À tout employé en poste, autre
    que soi : un message privé ne connaît pas les profils. */
create or replace function public.rh_peut_ecrire_a(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.rh_moi() is not null and cible <> public.rh_moi() and exists (
    select 1 from public.rh_employes c where c.id = cible and c.etat = 'actif');
$$;

/** A-t-on déjà écrit dans le fil de ce profil ? Qui écrit à un autre
    service que le sien en lit ensuite le fil, pour voir les réponses. */
create or replace function public.rh_a_ecrit_dans(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.rh_moi() is not null and exists (
    select 1 from public.rh_messages m where m.profil_id = cible and m.auteur_id = public.rh_moi());
$$;
revoke all on function public.rh_a_ecrit_dans(uuid) from public, anon;
grant execute on function public.rh_a_ecrit_dans(uuid) to authenticated, service_role;

create or replace function public.rh_message_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.auteur_id := public.rh_moi();
  new.cree_le := now();
  new.texte := btrim(new.texte);
  if new.auteur_id is null then
    raise exception 'Seul un employé en poste écrit';
  end if;
  return new;
end $$;

drop trigger if exists rh_messages_verrous on public.rh_messages;
create trigger rh_messages_verrous
  before insert on public.rh_messages
  for each row execute function public.rh_message_verrous();

create table if not exists public.rh_lectures (
  employe_id   uuid not null references public.rh_employes(id) on delete cascade,
  conversation text not null,
  lu_le        timestamptz not null default now(),
  primary key (employe_id, conversation)
);

/** « p:<profil> » ou « d:<personne> » : la discussion est lue jusqu'ici. */
create or replace function public.rh_marquer_lu(conversation text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.rh_moi() is null then
    raise exception 'Seul un employé en poste lit ses messages';
  end if;
  if conversation !~ '^([pd]:[0-9a-f-]{36}|g:tous)\Z' then
    raise exception 'Discussion inconnue';
  end if;
  insert into public.rh_lectures (employe_id, conversation, lu_le)
  values (public.rh_moi(), conversation, now())
  on conflict on constraint rh_lectures_pkey do update set lu_le = excluded.lu_le;
end $$;

/** Les discussions du compte connecté, la plus récente d'abord. */
create or replace function public.rh_conversations()
returns table (cle text, genre text, cible uuid, titre text, dernier_texte text,
               dernier_le timestamptz, non_lus int)
language sql stable security definer set search_path = public as $$
  with moi as (select public.rh_moi() as id, public.rh_est_admin() as admin),
  groupes as (
    select 'p:' || p.id as cle, 'profil'::text as genre, p.id as cible, p.nom as titre
      from public.rh_profils p, moi
     where moi.id is not null
       and (moi.admin or public.rh_acces(p.id, 'discussions')
            or (public.rh_menu_ouvert('discussions') and public.rh_a_ecrit_dans(p.id)))
  ),
  -- « Tout le monde » : tous les employés qui ont les discussions.
  general as (
    select 'g:tous' as cle, 'general'::text as genre, null::uuid as cible, 'Tout le monde' as titre
      from moi where moi.id is not null and public.rh_menu_ouvert('discussions')
  ),
  personnes as (
    select distinct case when m.auteur_id = moi.id then m.destinataire_id else m.auteur_id end as autre
      from public.rh_messages m, moi
     where m.destinataire_id is not null and (m.auteur_id = moi.id or m.destinataire_id = moi.id)
       and public.rh_menu_ouvert('discussions')
  ),
  prives as (
    select 'd:' || e.id as cle, 'personne'::text as genre, e.id as cible,
           btrim(e.prenoms || ' ' || e.nom) as titre
      from personnes x join public.rh_employes e on e.id = x.autre
  ),
  toutes as (select * from general union all select * from groupes union all select * from prives)
  select t.cle, t.genre, t.cible, t.titre, d.texte, d.cree_le,
         (select count(*)::int from public.rh_messages m, moi
           where m.auteur_id <> moi.id
             and m.cree_le > coalesce((select l.lu_le from public.rh_lectures l
                                        where l.employe_id = moi.id and l.conversation = t.cle),
                                      '-infinity')
             and ((t.genre = 'profil' and m.profil_id = t.cible)
               or (t.genre = 'general' and m.general)
               or (t.genre = 'personne' and m.auteur_id = t.cible and m.destinataire_id = moi.id)))
    from toutes t
    left join lateral (
      select m.texte, m.cree_le from public.rh_messages m, moi
       where (t.genre = 'profil' and m.profil_id = t.cible)
          or (t.genre = 'general' and m.general)
          or (t.genre = 'personne' and ((m.auteur_id = t.cible and m.destinataire_id = moi.id)
                                     or (m.auteur_id = moi.id and m.destinataire_id = t.cible)))
       order by m.id desc limit 1) d on true
   order by t.genre = 'general' desc, d.cree_le desc nulls last, t.titre;
$$;

-- ---------- Les missions ----------
create table if not exists public.rh_missions (
  id            uuid primary key default gen_random_uuid(),
  numero        bigint generated always as identity,
  titre         text not null check (length(btrim(titre)) > 0),
  description   text not null default '',
  profil_id     uuid not null references public.rh_profils(id) on delete restrict,
  date_debut    date not null default current_date,
  -- Le délai du rapport, fixé à la création.
  echeance      date not null,
  statut        text not null default 'proposee'
                check (statut in ('proposee', 'acceptee', 'refusee', 'rapport_remis',
                                  'a_reprendre', 'cloturee')),
  cree_par      uuid,
  cree_le       timestamptz not null default now(),
  reponse_par   uuid,
  reponse_le    timestamptz,
  motif_refus   text not null default '',
  rapport       text not null default '',
  rapport_par   uuid,
  rapport_le    timestamptz,
  decision_par  uuid,
  decision_le   timestamptz,
  commentaire   text not null default '',
  constraint rh_missions_dates check (echeance >= date_debut)
);

create or replace function public.rh_mission_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  libres text[] := array['titre', 'description', 'date_debut', 'echeance'];
begin
  if coalesce(current_setting('rh.decision', true), '') = 'oui' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.statut := 'proposee';
    new.cree_par := public.rh_moi();
    new.cree_le := now();
    new.reponse_par := null; new.reponse_le := null; new.motif_refus := '';
    new.rapport := ''; new.rapport_par := null; new.rapport_le := null;
    new.decision_par := null; new.decision_le := null; new.commentaire := '';
    return new;
  end if;
  if old.statut in ('refusee', 'cloturee') then
    raise exception 'Une mission refusée ou clôturée ne se modifie plus';
  end if;
  if (to_jsonb(new) - libres) is distinct from (to_jsonb(old) - libres) then
    raise exception 'Seuls le titre, la description et les dates se modifient ; le reste suit le circuit de la mission';
  end if;
  return new;
end $$;

drop trigger if exists rh_missions_verrous on public.rh_missions;
create trigger rh_missions_verrous
  before insert or update on public.rh_missions
  for each row execute function public.rh_mission_verrous();

create or replace function public.rh_repondre_mission(mission uuid, accepter boolean, motif text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare m public.rh_missions;
begin
  select * into m from public.rh_missions where id = mission for update;
  if not found or not public.rh_responsable_de(m.profil_id) then
    raise exception 'Seul le responsable du profil répond à cette mission';
  end if;
  if not public.rh_acces(m.profil_id, 'missions') then
    raise exception 'Le menu Missions n''est pas ouvert à votre profil';
  end if;
  if m.statut <> 'proposee' then
    raise exception 'Cette mission a déjà reçu sa réponse';
  end if;
  if not accepter and length(btrim(coalesce(motif, ''))) = 0 then
    raise exception 'Dites pourquoi vous refusez la mission';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_missions
     set statut = case when accepter then 'acceptee' else 'refusee' end,
         reponse_par = public.rh_moi(), reponse_le = now(),
         motif_refus = case when accepter then '' else btrim(motif) end
   where id = mission;
  perform set_config('rh.decision', '', true);
end $$;

create or replace function public.rh_rendre_rapport_mission(mission uuid, texte text)
returns void
language plpgsql security definer set search_path = public as $$
declare m public.rh_missions;
begin
  select * into m from public.rh_missions where id = mission for update;
  if not found or not public.rh_responsable_de(m.profil_id) then
    raise exception 'Seul le responsable du profil rend le rapport de mission';
  end if;
  if not public.rh_acces(m.profil_id, 'missions') then
    raise exception 'Le menu Missions n''est pas ouvert à votre profil';
  end if;
  if m.statut not in ('acceptee', 'a_reprendre') then
    raise exception 'Le rapport se rend sur une mission acceptée';
  end if;
  if length(btrim(coalesce(texte, ''))) < 10 then
    raise exception 'Le rapport est trop court';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_missions
     set statut = 'rapport_remis', rapport = btrim(texte),
         rapport_par = public.rh_moi(), rapport_le = now()
   where id = mission;
  perform set_config('rh.decision', '', true);
end $$;

create or replace function public.rh_cloturer_mission(mission uuid, valider boolean, commentaire text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_admin() then
    raise exception 'Seule l''administration clôture une mission';
  end if;
  if not valider and length(btrim(coalesce(commentaire, ''))) = 0 then
    raise exception 'Dites ce qu''il faut reprendre';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_missions
     set statut = case when valider then 'cloturee' else 'a_reprendre' end,
         decision_par = public.rh_moi(), decision_le = now(),
         commentaire = btrim(coalesce(rh_cloturer_mission.commentaire, ''))
   where id = mission and statut = 'rapport_remis';
  if not found then
    raise exception 'Aucun rapport n''attend sur cette mission';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

-- ---------- Les rapports d'activité ----------
create table if not exists public.rh_rapports (
  id             uuid primary key default gen_random_uuid(),
  profil_id      uuid not null references public.rh_profils(id) on delete restrict,
  auteur_id      uuid references public.rh_employes(id) on delete set null,
  titre          text not null check (length(btrim(titre)) > 0),
  periode_debut  date not null,
  periode_fin    date not null,
  contenu        text not null default '',
  statut         text not null default 'brouillon'
                 check (statut in ('brouillon', 'publie', 'valide', 'rejete')),
  cree_le        timestamptz not null default now(),
  publie_le      timestamptz,
  decision_par   uuid,
  decision_le    timestamptz,
  commentaire    text not null default '',
  constraint rh_rapports_periode check (periode_fin >= periode_debut)
);

create or replace function public.rh_rapport_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  libres text[] := array['titre', 'periode_debut', 'periode_fin', 'contenu'];
begin
  if coalesce(current_setting('rh.decision', true), '') = 'oui' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.auteur_id := public.rh_moi();
    new.statut := 'brouillon';
    new.cree_le := now();
    new.publie_le := null; new.decision_par := null; new.decision_le := null;
    new.commentaire := '';
    return new;
  end if;
  if old.statut not in ('brouillon', 'rejete') then
    raise exception 'Un rapport publié ne se modifie plus';
  end if;
  if (to_jsonb(new) - libres) is distinct from (to_jsonb(old) - libres) then
    raise exception 'Seuls le titre, la période et le contenu se modifient';
  end if;
  return new;
end $$;

drop trigger if exists rh_rapports_verrous on public.rh_rapports;
create trigger rh_rapports_verrous
  before insert or update on public.rh_rapports
  for each row execute function public.rh_rapport_verrous();

create or replace function public.rh_publier_rapport(rapport uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.rh_rapports;
begin
  select * into r from public.rh_rapports where id = rapport for update;
  if not found or r.auteur_id is distinct from public.rh_moi()
     or not public.rh_responsable_de(r.profil_id) then
    raise exception 'Seul le responsable du profil publie son rapport';
  end if;
  if not public.rh_acces(r.profil_id, 'rapports') then
    raise exception 'Le menu Rapports n''est pas ouvert à votre profil';
  end if;
  if r.statut not in ('brouillon', 'rejete') then
    raise exception 'Ce rapport est déjà publié';
  end if;
  if length(btrim(r.contenu)) < 10 then
    raise exception 'Le rapport est trop court pour être publié';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_rapports set statut = 'publie', publie_le = now() where id = rapport;
  perform set_config('rh.decision', '', true);
end $$;

create or replace function public.rh_decider_rapport(rapport uuid, valider boolean, commentaire text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO valide un rapport d''activité';
  end if;
  if not valider and length(btrim(coalesce(commentaire, ''))) = 0 then
    raise exception 'Dites pourquoi vous rejetez ce rapport';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_rapports
     set statut = case when valider then 'valide' else 'rejete' end,
         decision_par = public.rh_moi(), decision_le = now(),
         commentaire = btrim(coalesce(rh_decider_rapport.commentaire, ''))
   where id = rapport and statut = 'publie';
  if not found then
    raise exception 'Ce rapport n''attend pas de décision';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

-- ---------- Les demandes de dépense ----------
create table if not exists public.rh_depenses (
  id                 uuid primary key default gen_random_uuid(),
  numero             bigint generated always as identity,
  -- Le profil du demandeur ; vide pour un employé rangé dans aucun profil.
  profil_id          uuid references public.rh_profils(id) on delete restrict,
  demandeur_id       uuid references public.rh_employes(id) on delete set null,
  objet              text not null check (length(btrim(objet)) > 0),
  details            text not null default '',
  montant            bigint not null check (montant > 0),
  statut             text not null default 'demandee'
                     check (statut in ('demandee', 'validee_responsable', 'approuvee', 'refusee',
                                       'decaissee', 'annulee')),
  cree_le            timestamptz not null default now(),
  decision_par       uuid,
  decision_le        timestamptz,
  motif_decision     text not null default '',
  decaisse_par       uuid,
  decaisse_le        timestamptz,
  -- Le compartiment de la caisse d'où sort l'argent (« virement », « cheque »
  -- et « mobile_money » : les décaissements d'avant la caisse).
  mode_decaissement  text check (mode_decaissement in ('especes', 'mtn', 'moov', 'celtiis', 'mixte',
                                                       'virement', 'mobile_money', 'cheque')),
  reference          text not null default ''
);
-- La validation du responsable du profil, avant le CEO.
alter table public.rh_depenses add column if not exists responsable_par uuid;
alter table public.rh_depenses add column if not exists responsable_le timestamptz;
alter table public.rh_depenses add column if not exists motif_responsable text not null default '';

create or replace function public.rh_depense_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  libres text[] := array['objet', 'details', 'montant'];
begin
  if coalesce(current_setting('rh.decision', true), '') = 'oui' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.demandeur_id := public.rh_moi();
    -- Le profil du DEMANDEUR, jamais celui que l'écran propose.
    new.profil_id := public.rh_mon_profil();
    -- Son responsable valide d'abord. Sans responsable (pas de profil,
    -- profil sans responsable), ou s'il est lui-même le responsable,
    -- la demande va droit au CEO.
    new.statut := case
      when exists (select 1 from public.rh_profils p
                    where p.id = new.profil_id and p.responsable_id is not null
                      and p.responsable_id <> new.demandeur_id) then 'demandee'
      else 'validee_responsable' end;
    new.cree_le := now();
    new.responsable_par := null; new.responsable_le := null; new.motif_responsable := '';
    new.decision_par := null; new.decision_le := null; new.motif_decision := '';
    new.decaisse_par := null; new.decaisse_le := null; new.mode_decaissement := null;
    new.reference := '';
    return new;
  end if;
  -- Modifiable tant que personne ne l'a validée.
  if not (old.statut = 'demandee'
          or (old.statut = 'validee_responsable' and old.responsable_par is null)) then
    raise exception 'Une demande déjà validée ou tranchée ne se modifie plus';
  end if;
  if (to_jsonb(new) - libres) is distinct from (to_jsonb(old) - libres) then
    raise exception 'Seuls l''objet, le détail et le montant se modifient';
  end if;
  return new;
end $$;

drop trigger if exists rh_depenses_verrous on public.rh_depenses;
create trigger rh_depenses_verrous
  before insert or update on public.rh_depenses
  for each row execute function public.rh_depense_verrous();

create or replace function public.rh_decider_depense(depense uuid, approuver boolean, motif text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO approuve une dépense';
  end if;
  if not approuver and length(btrim(coalesce(motif, ''))) = 0 then
    raise exception 'Dites pourquoi vous refusez la dépense';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_depenses
     set statut = case when approuver then 'approuvee' else 'refusee' end,
         decision_par = public.rh_moi(), decision_le = now(),
         motif_decision = btrim(coalesce(motif, ''))
   where id = depense and statut = 'validee_responsable';
  if not found then
    raise exception 'Cette dépense n''attend pas la décision du CEO : son responsable doit d''abord la valider';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

create or replace function public.rh_decaisser_depense(depense uuid, mode text, reference text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_peut_decaisser() then
    raise exception 'Votre compte n''est pas habilité à décaisser';
  end if;
  if mode not in ('especes', 'mtn', 'moov', 'celtiis', 'mixte') then
    raise exception 'Choisissez le compartiment de la caisse : espèces, MTN, Moov ou Celtiis';
  end if;
  if exists (select 1 from public.rh_depenses where id = depense and demandeur_id = public.rh_moi()) then
    raise exception 'On ne décaisse pas sa propre demande : un autre habilité s''en charge';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_depenses
     set statut = 'decaissee', decaisse_par = public.rh_moi(), decaisse_le = now(),
         mode_decaissement = mode, reference = btrim(coalesce(rh_decaisser_depense.reference, ''))
   where id = depense and statut = 'approuvee';
  if not found then
    raise exception 'Seule une dépense approuvée par le CEO se décaisse';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

create or replace function public.rh_annuler_depense(depense uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('rh.decision', 'oui', true);
  update public.rh_depenses set statut = 'annulee'
   where id = depense and statut in ('demandee', 'validee_responsable') and demandeur_id = public.rh_moi();
  if not found then
    raise exception 'Seul le demandeur annule une demande encore en attente';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

-- =========================================================
-- La paie
--
-- AUCUN TAUX N'EST FOURNI, et c'est voulu : la CNSS, l'impôt (ITS)
-- et les autres cotisations sont saisis par l'administration et
-- VALIDÉS par le CEO. Tant qu'un barème n'est pas validé, la fiche
-- l'ignore : elle ne compte que le salaire, les primes, les avances
-- et les retenues.
-- =========================================================

create table if not exists public.rh_cotisations (
  id              uuid primary key default gen_random_uuid(),
  code            text not null check (code ~ '^[A-Z0-9_]{2,20}\Z'),
  libelle         text not null check (length(btrim(libelle)) > 0),
  taux_salarie    numeric(6,3) not null default 0 check (taux_salarie between 0 and 100),
  taux_employeur  numeric(6,3) not null default 0 check (taux_employeur between 0 and 100),
  -- Assiette plafonnée, par mois ; null = pas de plafond.
  plafond         bigint check (plafond is null or plafond > 0),
  stagiaires      boolean not null default false,
  actif           boolean not null default true,
  valide          boolean not null default false,
  saisi_par       uuid,
  saisi_le        timestamptz not null default now(),
  valide_par      uuid,
  valide_le       timestamptz
);
create unique index if not exists rh_cotisations_code on public.rh_cotisations (code);

create or replace function public.rh_cotisation_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('rh.decision', true), '') = 'oui' then
    return new;
  end if;
  /* Toute modification d'un taux repasse par le CEO. */
  new.valide := false;
  new.valide_par := null;
  new.valide_le := null;
  new.saisi_par := public.rh_moi();
  new.saisi_le := now();
  return new;
end $$;

drop trigger if exists rh_cotisations_verrous on public.rh_cotisations;
create trigger rh_cotisations_verrous
  before insert or update on public.rh_cotisations
  for each row execute function public.rh_cotisation_verrous();

create or replace function public.rh_valider_cotisation(cotisation uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO valide un barème';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_cotisations
     set valide = true, valide_par = public.rh_moi(), valide_le = now()
   where id = cotisation and not valide;
  if not found then
    raise exception 'Cette cotisation est déjà validée';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

-- L'impôt sur le salaire : un barème progressif, par tranches mensuelles.
create table if not exists public.rh_tranches_impot (
  id         uuid primary key default gen_random_uuid(),
  borne_inf  bigint not null check (borne_inf >= 0),
  borne_sup  bigint check (borne_sup is null or borne_sup > borne_inf),
  taux       numeric(6,3) not null check (taux between 0 and 100)
);

create table if not exists public.rh_reglages_paie (
  id                boolean primary key default true check (id),
  -- L'assiette de l'impôt : le brut imposable, ou ce brut moins les
  -- cotisations du salarié. Au comptable de dire laquelle.
  impot_sur         text not null default 'brut_imposable'
                    check (impot_sur in ('brut_imposable', 'brut_moins_cotisations')),
  impot_stagiaires  boolean not null default false,
  impot_valide      boolean not null default false,
  impot_valide_par  uuid,
  impot_valide_le   timestamptz
);
insert into public.rh_reglages_paie (id) values (true) on conflict (id) do nothing;

create or replace function public.rh_reglages_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('rh.decision', true), '') = 'oui' then
    return new;
  end if;
  new.impot_valide := false;
  new.impot_valide_par := null;
  new.impot_valide_le := null;
  return new;
end $$;

drop trigger if exists rh_reglages_paie_verrous on public.rh_reglages_paie;
create trigger rh_reglages_paie_verrous
  before update on public.rh_reglages_paie
  for each row execute function public.rh_reglages_verrous();

/* Une tranche qui change rend le barème à valider de nouveau. */
create or replace function public.rh_tranches_changent() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.rh_reglages_paie set impot_valide = false, impot_valide_par = null,
                                     impot_valide_le = null
   where id;
  return null;
end $$;

drop trigger if exists rh_tranches_impot_changent on public.rh_tranches_impot;
create trigger rh_tranches_impot_changent
  after insert or update or delete on public.rh_tranches_impot
  for each statement execute function public.rh_tranches_changent();

create or replace function public.rh_valider_bareme_impot() returns void
language plpgsql security definer set search_path = public as $$
declare
  t record;
  attendu bigint := 0;
  ouverte boolean := false;
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO valide un barème';
  end if;
  if not exists (select 1 from public.rh_tranches_impot) then
    raise exception 'Le barème n''a aucune tranche';
  end if;
  /* Des tranches qui se suivent, de 0 à l'infini, sans trou ni
     chevauchement : sinon un salaire tomberait entre deux. */
  for t in select * from public.rh_tranches_impot order by borne_inf loop
    if ouverte then
      raise exception 'Une seule tranche peut rester ouverte, et c''est la dernière';
    end if;
    if t.borne_inf <> attendu then
      raise exception 'Les tranches doivent se suivre : on attendait une tranche qui commence à %', attendu;
    end if;
    if t.borne_sup is null then
      ouverte := true;
    else
      attendu := t.borne_sup;
    end if;
  end loop;
  if not ouverte then
    raise exception 'La dernière tranche doit rester ouverte (sans borne supérieure)';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_reglages_paie
     set impot_valide = true, impot_valide_par = public.rh_moi(), impot_valide_le = now()
   where id;
  perform set_config('rh.decision', '', true);
end $$;

-- Primes, indemnités, retenues : par employé et par mois.
create table if not exists public.rh_elements_paie (
  id          uuid primary key default gen_random_uuid(),
  employe_id  uuid not null references public.rh_employes(id) on delete cascade,
  mois        date not null check (extract(day from mois) = 1),
  nature      text not null check (nature in ('prime', 'indemnite', 'retenue')),
  libelle     text not null check (length(btrim(libelle)) > 0),
  montant     bigint not null check (montant > 0),
  imposable   boolean not null default true,
  cree_par    uuid,
  cree_le     timestamptz not null default now()
);
create index if not exists rh_elements_paie_mois on public.rh_elements_paie (employe_id, mois);

-- Les avances sur salaire, remboursées sur une ou plusieurs paies.
create table if not exists public.rh_avances (
  id            uuid primary key default gen_random_uuid(),
  employe_id    uuid not null references public.rh_employes(id) on delete cascade,
  date_avance   date not null default current_date,
  montant       bigint not null check (montant > 0),
  mensualites   int not null default 1 check (mensualites between 1 and 24),
  premier_mois  date not null check (extract(day from premier_mois) = 1),
  motif         text not null default '',
  statut        text not null default 'active' check (statut in ('active', 'soldee', 'annulee')),
  cree_par      uuid,
  cree_le       timestamptz not null default now()
);

create table if not exists public.rh_fiches_paie (
  id                     uuid primary key default gen_random_uuid(),
  employe_id             uuid not null references public.rh_employes(id) on delete cascade,
  mois                   date not null check (extract(day from mois) = 1),
  statut                 text not null default 'calculee'
                         check (statut in ('calculee', 'validee', 'payee')),
  jours_payes            int not null,
  jours_du_mois          int not null,
  salaire_base           bigint not null,
  salaire_du             bigint not null,
  primes                 bigint not null default 0,
  brut                   bigint not null,
  brut_imposable         bigint not null,
  cotisations_salariales bigint not null default 0,
  impot                  bigint not null default 0,
  avances                bigint not null default 0,
  retenues               bigint not null default 0,
  net                    bigint not null,
  charges_patronales     bigint not null default 0,
  -- Le détail ligne à ligne, tel que la fiche l'imprime.
  lignes                 jsonb not null default '[]'::jsonb,
  -- Ce que la fiche figeait au calcul : un employé qui change de poste
  -- ne change pas ses fiches passées.
  employe                jsonb not null default '{}'::jsonb,
  calcule_le             timestamptz not null default now(),
  valide_par             uuid,
  valide_le              timestamptz,
  paye_par               uuid,
  paye_le                timestamptz,
  mode_paiement          text,
  reference              text not null default '',
  unique (employe_id, mois)
);
create index if not exists rh_fiches_paie_mois on public.rh_fiches_paie (mois);

-- Ce que chaque fiche a retenu sur chaque avance : le reste dû se lit ici.
create table if not exists public.rh_fiche_avances (
  fiche_id   uuid not null references public.rh_fiches_paie(id) on delete cascade,
  avance_id  uuid not null references public.rh_avances(id) on delete cascade,
  montant    bigint not null check (montant > 0),
  primary key (fiche_id, avance_id)
);

/**
 * Calcule (ou recalcule) la fiche d'un employé pour un mois. Une fiche
 * validée ou payée n'est JAMAIS recalculée : elle a été vue et signée.
 * Fonction interne : aucun compte ne l'appelle directement.
 */
create or replace function public.rh_calculer_fiche(qui uuid, quand date) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  e public.rh_employes;
  debut date := date_trunc('month', quand)::date;
  fin date := (date_trunc('month', quand) + interval '1 month - 1 day')::date;
  jours int;
  d1 date;
  d2 date;
  payes int;
  du bigint;
  lignes jsonb := '[]'::jsonb;
  el record;
  c record;
  a record;
  primes bigint := 0;
  imposable bigint;
  brut bigint;
  cot_sal bigint := 0;
  cot_pat bigint := 0;
  assiette bigint;
  part bigint;
  reglage public.rh_reglages_paie;
  base_impot bigint;
  impot bigint := 0;
  retenues bigint := 0;
  avances bigint := 0;
  reste bigint;
  disponible bigint;
  prise bigint;
  existante public.rh_fiches_paie;
  fiche uuid;
  prises jsonb := '[]'::jsonb;
begin
  jours := fin - debut + 1;
  select * into e from public.rh_employes where id = qui;
  if not found then
    return null;
  end if;
  select * into existante from public.rh_fiches_paie f
   where f.employe_id = qui and f.mois = debut;
  if found and existante.statut <> 'calculee' then
    return existante.id;
  end if;

  /* Payé du jour d'embauche au jour de sortie, au prorata des jours
     calendaires du mois. */
  d1 := greatest(debut, e.date_embauche);
  d2 := least(fin, coalesce(e.date_sortie, fin));
  if e.etat not in ('actif', 'bloque', 'sorti') or d2 < d1 then
    delete from public.rh_fiches_paie f
     where f.employe_id = qui and f.mois = debut and f.statut = 'calculee';
    return null;
  end if;
  payes := d2 - d1 + 1;
  du := round(e.salaire_base::numeric * payes / jours);
  lignes := lignes || jsonb_build_object('genre', 'base', 'libelle',
    case when payes < jours then 'Salaire de base (' || payes || ' jours sur ' || jours || ')'
         else 'Salaire de base' end, 'montant', du);
  imposable := du;

  for el in select * from public.rh_elements_paie x
             where x.employe_id = qui and x.mois = debut and x.nature in ('prime', 'indemnite')
             order by x.cree_le loop
    primes := primes + el.montant;
    if el.imposable then
      imposable := imposable + el.montant;
    end if;
    lignes := lignes || jsonb_build_object('genre', el.nature, 'libelle', el.libelle,
                                           'montant', el.montant, 'imposable', el.imposable);
  end loop;
  brut := du + primes;

  for c in select * from public.rh_cotisations x
            where x.valide and x.actif and (e.statut = 'employe' or x.stagiaires)
            order by x.code loop
    assiette := least(imposable, coalesce(c.plafond, imposable));
    part := round(assiette * c.taux_salarie / 100);
    cot_sal := cot_sal + part;
    cot_pat := cot_pat + round(assiette * c.taux_employeur / 100);
    lignes := lignes || jsonb_build_object('genre', 'cotisation', 'code', c.code,
      'libelle', c.libelle, 'assiette', assiette, 'taux', c.taux_salarie,
      'montant', part, 'taux_employeur', c.taux_employeur,
      'employeur', round(assiette * c.taux_employeur / 100));
  end loop;

  select * into reglage from public.rh_reglages_paie where id;
  if reglage.impot_valide and (e.statut = 'employe' or reglage.impot_stagiaires) then
    base_impot := imposable - case when reglage.impot_sur = 'brut_moins_cotisations'
                                   then cot_sal else 0 end;
    select coalesce(sum(round((least(base_impot, coalesce(t.borne_sup, base_impot)) - t.borne_inf)
                              * t.taux / 100)), 0)
      into impot
      from public.rh_tranches_impot t
     where base_impot > t.borne_inf;
    lignes := lignes || jsonb_build_object('genre', 'impot', 'libelle', 'Impôt sur le salaire',
                                           'assiette', base_impot, 'montant', impot);
  end if;

  for el in select * from public.rh_elements_paie x
             where x.employe_id = qui and x.mois = debut and x.nature = 'retenue'
             order by x.cree_le loop
    retenues := retenues + el.montant;
    lignes := lignes || jsonb_build_object('genre', 'retenue', 'libelle', el.libelle,
                                           'montant', el.montant);
  end loop;

  /* Les avances passent en dernier, et jamais au-delà de ce qui reste :
     une fiche ne descend pas sous zéro à cause d'une avance — le reste
     attend la paie suivante. */
  disponible := greatest(0, brut - cot_sal - impot - retenues);
  for a in select * from public.rh_avances x
            where x.employe_id = qui and x.statut = 'active' and x.premier_mois <= debut
            order by x.date_avance, x.cree_le loop
    select a.montant - coalesce(sum(fa.montant), 0) into reste
      from public.rh_fiche_avances fa
      join public.rh_fiches_paie f on f.id = fa.fiche_id
     where fa.avance_id = a.id and f.mois <> debut;
    prise := least(reste, ceil(a.montant::numeric / a.mensualites)::bigint, disponible);
    if prise > 0 then
      avances := avances + prise;
      disponible := disponible - prise;
      prises := prises || jsonb_build_object('avance', a.id, 'montant', prise);
      lignes := lignes || jsonb_build_object('genre', 'avance', 'libelle',
        'Avance du ' || to_char(a.date_avance, 'DD/MM/YYYY') ||
        case when reste - prise > 0 then ' (reste ' || (reste - prise) || ' FCFA)' else ' (soldée)' end,
        'montant', prise);
    end if;
  end loop;

  insert into public.rh_fiches_paie as f (employe_id, mois, statut, jours_payes, jours_du_mois,
      salaire_base, salaire_du, primes, brut, brut_imposable, cotisations_salariales, impot,
      avances, retenues, net, charges_patronales, lignes, employe, calcule_le)
  values (qui, debut, 'calculee', payes, jours, e.salaire_base, du, primes, brut, imposable,
      cot_sal, impot, avances, retenues, brut - cot_sal - impot - retenues - avances, cot_pat,
      lignes,
      jsonb_build_object('matricule', e.matricule, 'nom', e.nom, 'prenoms', e.prenoms,
        'poste', e.poste, 'statut', e.statut, 'date_embauche', e.date_embauche,
        'numero_cnss', e.numero_cnss, 'mode_paiement', e.mode_paiement,
        'profil', (select p.nom from public.rh_profils p where p.id = e.profil_id)),
      now())
  on conflict on constraint rh_fiches_paie_employe_id_mois_key do update
     set jours_payes = excluded.jours_payes, jours_du_mois = excluded.jours_du_mois,
         salaire_base = excluded.salaire_base, salaire_du = excluded.salaire_du,
         primes = excluded.primes, brut = excluded.brut, brut_imposable = excluded.brut_imposable,
         cotisations_salariales = excluded.cotisations_salariales, impot = excluded.impot,
         avances = excluded.avances, retenues = excluded.retenues, net = excluded.net,
         charges_patronales = excluded.charges_patronales, lignes = excluded.lignes,
         employe = excluded.employe, calcule_le = now()
   where f.statut = 'calculee'
  returning f.id into fiche;

  delete from public.rh_fiche_avances where fiche_id = fiche;
  insert into public.rh_fiche_avances (fiche_id, avance_id, montant)
  select fiche, (x ->> 'avance')::uuid, (x ->> 'montant')::bigint
    from jsonb_array_elements(prises) x;
  return fiche;
end $$;

/** Toutes les fiches d'un mois. Interne : la paie automatique l'appelle. */
create or replace function public.rh_generer_paie_interne(mois date) returns int
language plpgsql security definer set search_path = public as $$
declare
  debut date := date_trunc('month', mois)::date;
  fin date := (date_trunc('month', mois) + interval '1 month - 1 day')::date;
  e record;
  combien int := 0;
begin
  for e in select id from public.rh_employes
            where (etat in ('actif', 'bloque') or (etat = 'sorti' and date_sortie >= debut))
              and date_embauche <= fin loop
    if public.rh_calculer_fiche(e.id, debut) is not null then
      combien := combien + 1;
    end if;
  end loop;
  /* Un employé qui n'est plus à payer ce mois-là perd sa fiche non validée. */
  delete from public.rh_fiches_paie f
   where f.mois = debut and f.statut = 'calculee'
     and not exists (select 1 from public.rh_employes x
                      where x.id = f.employe_id
                        and (x.etat in ('actif', 'bloque') or (x.etat = 'sorti' and x.date_sortie >= debut))
                        and x.date_embauche <= fin);
  return combien;
end $$;

create or replace function public.rh_generer_paie(mois date) returns int
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_admin() then
    raise exception 'Seule l''administration prépare la paie';
  end if;
  if date_trunc('month', mois) > date_trunc('month', (now() at time zone 'Africa/Porto-Novo')) then
    raise exception 'On ne prépare pas la paie d''un mois à venir';
  end if;
  return public.rh_generer_paie_interne(mois);
end $$;

/**
 * La paie, sans que personne n'y pense : le 5 du mois (heure du Bénin),
 * les fiches du mois écoulé sont calculées, et attendent la validation
 * du CEO ; elles se versent le 10. Si le 5 a été manqué, le premier
 * passage d'après rattrape. Appelée par pg_cron chaque matin, et par
 * l'application à l'ouverture.
 */
create or replace function public.rh_generer_paie_auto() returns int
language plpgsql security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  precedent date := (date_trunc('month', aujourdhui) - interval '1 month')::date;
begin
  if extract(day from aujourdhui) >= 5
     and not exists (select 1 from public.rh_fiches_paie where mois = precedent) then
    return public.rh_generer_paie_interne(precedent);
  end if;
  return 0;
end $$;

/** Ce que l'application appelle à l'ouverture, pour l'administration. */
create or replace function public.rh_paie_a_jour() returns int
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_admin() then
    return 0;
  end if;
  return public.rh_generer_paie_auto();
end $$;

/* Une prime ou une avance qui change refait la fiche du mois, si elle
   n'est pas encore validée ; et l'interdit si elle l'est. */
create or replace function public.rh_element_paie_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  ligne record;
begin
  for ligne in
    select x.employe_id, x.mois from (
      select new.employe_id as employe_id, new.mois as mois where tg_op <> 'DELETE'
      union all
      select old.employe_id, old.mois where tg_op <> 'INSERT') x loop
    if exists (select 1 from public.rh_fiches_paie f
                where f.employe_id = ligne.employe_id and f.mois = ligne.mois
                  and f.statut <> 'calculee') then
      raise exception 'La fiche de ce mois est déjà validée : demandez au CEO de la rouvrir';
    end if;
    if exists (select 1 from public.rh_fiches_paie f
                where f.employe_id = ligne.employe_id and f.mois = ligne.mois) then
      perform public.rh_calculer_fiche(ligne.employe_id, ligne.mois);
    end if;
  end loop;
  return null;
end $$;

drop trigger if exists rh_elements_paie_change on public.rh_elements_paie;
create trigger rh_elements_paie_change
  after insert or update or delete on public.rh_elements_paie
  for each row execute function public.rh_element_paie_change();

create or replace function public.rh_element_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.cree_par := public.rh_moi();
  new.cree_le := now();
  return new;
end $$;

drop trigger if exists rh_elements_paie_verrous on public.rh_elements_paie;
create trigger rh_elements_paie_verrous
  before insert on public.rh_elements_paie
  for each row execute function public.rh_element_verrous();

drop trigger if exists rh_avances_verrous on public.rh_avances;
create trigger rh_avances_verrous
  before insert on public.rh_avances
  for each row execute function public.rh_element_verrous();

/* Une avance déjà retenue sur une fiche validée ne se modifie plus. */
create or replace function public.rh_avance_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  cible uuid := coalesce(new.id, old.id);
  f record;
begin
  if coalesce(current_setting('rh.decision', true), '') = 'oui' then
    return null;
  end if;
  if exists (select 1 from public.rh_fiche_avances fa
               join public.rh_fiches_paie x on x.id = fa.fiche_id
              where fa.avance_id = cible and x.statut <> 'calculee') then
    raise exception 'Cette avance est déjà retenue sur une paie validée : elle ne se modifie plus';
  end if;
  for f in select x.employe_id, x.mois from public.rh_fiches_paie x
            where x.employe_id = coalesce(new.employe_id, old.employe_id)
              and x.statut = 'calculee' loop
    perform public.rh_calculer_fiche(f.employe_id, f.mois);
  end loop;
  return null;
end $$;

drop trigger if exists rh_avances_change on public.rh_avances;
create trigger rh_avances_change
  after insert or update or delete on public.rh_avances
  for each row execute function public.rh_avance_change();

/** Le CEO valide la paie d'un mois : recalculée une dernière fois, puis figée. */
create or replace function public.rh_valider_paie(mois date) returns int
language plpgsql security definer set search_path = public as $$
declare
  debut date := date_trunc('month', mois)::date;
  combien int;
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO valide la paie';
  end if;
  perform public.rh_generer_paie_interne(debut);
  update public.rh_fiches_paie
     set statut = 'validee', valide_par = public.rh_moi(), valide_le = now()
   where rh_fiches_paie.mois = debut and statut = 'calculee';
  get diagnostics combien = row_count;
  /* Une avance remboursée en entier est soldée. */
  perform set_config('rh.decision', 'oui', true);
  update public.rh_avances a set statut = 'soldee'
   where a.statut = 'active'
     and a.montant <= (select coalesce(sum(fa.montant), 0)
                         from public.rh_fiche_avances fa
                         join public.rh_fiches_paie f on f.id = fa.fiche_id
                        where fa.avance_id = a.id and f.statut <> 'calculee');
  perform set_config('rh.decision', '', true);
  return combien;
end $$;

/** Le CEO rouvre une fiche validée mais pas encore payée, pour la corriger. */
create or replace function public.rh_rouvrir_fiche(fiche uuid) returns void
language plpgsql security definer set search_path = public as $$
declare f public.rh_fiches_paie;
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO rouvre une fiche de paie';
  end if;
  update public.rh_fiches_paie set statut = 'calculee', valide_par = null, valide_le = null
   where id = fiche and statut = 'validee'
  returning * into f;
  if f.id is null then
    raise exception 'Seule une fiche validée et pas encore payée se rouvre';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_avances a set statut = 'active'
   where a.statut = 'soldee'
     and exists (select 1 from public.rh_fiche_avances fa where fa.fiche_id = f.id and fa.avance_id = a.id);
  perform set_config('rh.decision', '', true);
  perform public.rh_calculer_fiche(f.employe_id, f.mois);
end $$;

/* Une fiche ne se paie plus de la main à la main : validée, elle se
   verse le 10 sur le solde de l'employé (personnel-solde.sql), qui le
   retire ensuite par Mobile Money ou à la caisse. Les deux portes
   d'avant restent, fermées, pour qu'un ancien écran reçoive une
   phrase claire plutôt qu'une fonction inconnue. */
create or replace function public.rh_payer_fiche(fiche uuid, mode text, reference text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Un salaire ne se paie plus ici : la fiche validée est versée le 10 sur le solde de l''employé, qui le retire depuis son compte (Mobile Money ou caisse)';
end $$;

-- ---------- La boîte mail professionnelle ----------
-- Le mot de passe de la boîte, CHIFFRÉ par la fonction Edge
-- « rh-messagerie » avec une clé qui ne quitte jamais le serveur.
-- Aucune règle RLS : aucun compte ne lit cette table, pas même le CEO.
-- Seule la fonction Edge (clé de service) y accède.
create table if not exists public.rh_boites_mail (
  employe_id     uuid primary key references public.rh_employes(id) on delete cascade,
  secret         text not null,
  iv             text not null,
  enregistre_le  timestamptz not null default now()
);

create or replace function public.rh_ma_messagerie() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'email', e.email_pro,
    'configuree', b.employe_id is not null,
    'enregistre_le', b.enregistre_le)
    from public.rh_employes e
    left join public.rh_boites_mail b on b.employe_id = e.id
   where e.id = public.rh_moi();
$$;

create or replace function public.rh_oublier_ma_messagerie() returns void
language sql security definer set search_path = public as $$
  delete from public.rh_boites_mail where employe_id = public.rh_moi();
$$;

-- ---------- Le tableau de bord ----------
-- Qui je suis, et ce qui m'attend. Un seul appel à l'ouverture.
create or replace function public.rh_tableau_de_bord() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  moi public.rh_employes;
  v_ceo boolean;
  v_admin boolean;
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  mes_profils uuid[];
begin
  select * into moi from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
  if not found then
    return jsonb_build_object(
      'moi', null,
      'en_attente', exists (select 1 from public.rh_employes where compte_id = auth.uid()),
      'bloque', exists (select 1 from public.rh_employes where compte_id = auth.uid() and etat = 'bloque'),
      'amorce_possible', not exists (select 1 from public.rh_employes where ceo)
                         and public.est_super());
  end if;
  v_ceo := moi.ceo;
  v_admin := moi.ceo or moi.administration;
  select coalesce(array_agg(id), '{}') into mes_profils
    from public.rh_profils where responsable_id = moi.id;
  return jsonb_build_object(
    'moi', jsonb_build_object(
      'id', moi.id, 'matricule', moi.matricule, 'nom', moi.nom, 'prenoms', moi.prenoms,
      'sexe', moi.sexe, 'poste', moi.poste, 'email_pro', moi.email_pro,
      'ceo', v_ceo, 'administration', v_admin, 'peut_decaisser', public.rh_peut_decaisser(),
      'super', public.est_super(),
      'profil_id', moi.profil_id,
      'profil', (select nom from public.rh_profils where id = moi.profil_id),
      'responsable_de', to_jsonb(mes_profils)),
    'compteurs', jsonb_build_object(
      'employes_a_valider', case when v_ceo then
        (select count(*) from public.rh_employes where etat = 'en_attente') else 0 end,
      'missions_a_repondre',
        (select count(*) from public.rh_missions where statut = 'proposee' and profil_id = any(mes_profils)
            and public.rh_acces(profil_id, 'missions')),
      'missions_en_cours',
        (select count(*) from public.rh_missions
          where statut in ('acceptee', 'a_reprendre')
            and (v_admin or ((profil_id = any(mes_profils) or profil_id = moi.profil_id)
                             and public.rh_acces(profil_id, 'missions')))),
      'missions_en_retard',
        (select count(*) from public.rh_missions
          where statut in ('acceptee', 'a_reprendre') and echeance < aujourdhui
            and (v_admin or (profil_id = any(mes_profils) and public.rh_acces(profil_id, 'missions')))),
      'missions_a_cloturer', case when v_admin then
        (select count(*) from public.rh_missions where statut = 'rapport_remis') else 0 end,
      'rapports_a_valider', case when v_ceo then
        (select count(*) from public.rh_rapports where statut = 'publie') else 0 end,
      'depenses_a_valider',
        (select count(*) from public.rh_depenses where statut = 'demandee' and profil_id = any(mes_profils)),
      'depenses_a_approuver', case when v_ceo then
        (select count(*) from public.rh_depenses where statut = 'validee_responsable') else 0 end,
      'depenses_a_decaisser', case when public.rh_peut_decaisser() then
        (select count(*) from public.rh_depenses where statut = 'approuvee') else 0 end,
      'baremes_a_valider', case when v_ceo then
        (select count(*) from public.rh_cotisations where actif and not valide)
        + (select count(*) from public.rh_reglages_paie r
            where not r.impot_valide and exists (select 1 from public.rh_tranches_impot)) else 0 end,
      'fiches_a_valider', case when v_ceo then
        (select count(*) from public.rh_fiches_paie
          where statut = 'calculee'
            and mois < date_trunc('month', aujourdhui + 1)::date) else 0 end,
      'fiches_a_payer', case when public.rh_peut_decaisser() then
        (select count(*) from public.rh_fiches_paie where statut = 'validee') else 0 end,
      'messages_non_lus', (select coalesce(sum(non_lus), 0) from public.rh_conversations())));
end $$;

-- =========================================================
-- Les règles d'accès
-- =========================================================
alter table public.rh_employes      enable row level security;
alter table public.rh_profils       enable row level security;
alter table public.rh_messages      enable row level security;
alter table public.rh_lectures      enable row level security;
alter table public.rh_missions      enable row level security;
alter table public.rh_rapports      enable row level security;
alter table public.rh_depenses      enable row level security;
alter table public.rh_cotisations   enable row level security;
alter table public.rh_tranches_impot enable row level security;
alter table public.rh_reglages_paie enable row level security;
alter table public.rh_elements_paie enable row level security;
alter table public.rh_avances       enable row level security;
alter table public.rh_fiches_paie   enable row level security;
alter table public.rh_fiche_avances enable row level security;
alter table public.rh_boites_mail   enable row level security;

drop policy if exists "rh employes lecture" on public.rh_employes;
drop policy if exists "rh employes ajout" on public.rh_employes;
drop policy if exists "rh employes modification" on public.rh_employes;
drop policy if exists "rh employes suppression" on public.rh_employes;
-- La fiche complète (salaire compris) : l'administration, et l'employé
-- lui-même. Les autres passent par l'annuaire.
create policy "rh employes lecture" on public.rh_employes
  for select to authenticated using (public.rh_est_admin() or public.est_super() or compte_id = auth.uid());
create policy "rh employes ajout" on public.rh_employes
  for insert to authenticated with check (public.rh_est_admin() or public.est_super());
create policy "rh employes modification" on public.rh_employes
  for update to authenticated
  using (public.rh_est_admin() or public.est_super() or (compte_id = auth.uid() and etat = 'actif'))
  with check (public.rh_est_admin() or public.est_super() or (compte_id = auth.uid() and etat = 'actif'));
create policy "rh employes suppression" on public.rh_employes
  for delete to authenticated
  using (public.rh_est_ceo() and etat in ('en_attente', 'refuse'));

drop policy if exists "rh profils lecture" on public.rh_profils;
drop policy if exists "rh profils ecriture" on public.rh_profils;
create policy "rh profils lecture" on public.rh_profils
  for select to authenticated using (public.rh_moi() is not null);
create policy "rh profils ecriture" on public.rh_profils
  for all to authenticated using (public.rh_est_admin()) with check (public.rh_est_admin());

drop policy if exists "rh messages lecture" on public.rh_messages;
drop policy if exists "rh messages envoi" on public.rh_messages;
-- Un message privé reste privé : l'administration lit les discussions
-- de tous les profils, pas les messages entre deux personnes.
create policy "rh messages lecture" on public.rh_messages
  for select to authenticated using (
    (profil_id is not null and (public.rh_acces(profil_id, 'discussions')
      or (public.rh_menu_ouvert('discussions') and public.rh_a_ecrit_dans(profil_id))))
    or (general and public.rh_menu_ouvert('discussions'))
    or (destinataire_id is not null
        and (auteur_id = public.rh_moi() or destinataire_id = public.rh_moi())
        and public.rh_menu_ouvert('discussions')));
create policy "rh messages envoi" on public.rh_messages
  for insert to authenticated with check (
    (profil_id is not null and (public.rh_acces(profil_id, 'discussions') or public.rh_menu_ouvert('discussions')))
    or (general and public.rh_menu_ouvert('discussions'))
    or (destinataire_id is not null and public.rh_peut_ecrire_a(destinataire_id)
        and public.rh_menu_ouvert('discussions')));

drop policy if exists "rh missions lecture" on public.rh_missions;
drop policy if exists "rh missions creation" on public.rh_missions;
drop policy if exists "rh missions modification" on public.rh_missions;
drop policy if exists "rh missions suppression" on public.rh_missions;
create policy "rh missions lecture" on public.rh_missions
  for select to authenticated using (public.rh_acces(profil_id, 'missions'));
create policy "rh missions creation" on public.rh_missions
  for insert to authenticated with check (public.rh_est_admin());
create policy "rh missions modification" on public.rh_missions
  for update to authenticated using (public.rh_est_admin()) with check (public.rh_est_admin());
create policy "rh missions suppression" on public.rh_missions
  for delete to authenticated using (public.rh_est_admin() and statut in ('proposee', 'refusee'));

drop policy if exists "rh rapports lecture" on public.rh_rapports;
drop policy if exists "rh rapports creation" on public.rh_rapports;
drop policy if exists "rh rapports modification" on public.rh_rapports;
drop policy if exists "rh rapports suppression" on public.rh_rapports;
create policy "rh rapports lecture" on public.rh_rapports
  for select to authenticated using (
    auteur_id = public.rh_moi()
    or (public.rh_est_admin() and statut <> 'brouillon')
    or (statut = 'valide' and public.rh_acces(profil_id, 'rapports')));
create policy "rh rapports creation" on public.rh_rapports
  for insert to authenticated
  with check (public.rh_responsable_de(profil_id) and public.rh_acces(profil_id, 'rapports'));
create policy "rh rapports modification" on public.rh_rapports
  for update to authenticated
  using (auteur_id = public.rh_moi() and public.rh_responsable_de(profil_id))
  with check (auteur_id = public.rh_moi() and public.rh_responsable_de(profil_id)
              and public.rh_acces(profil_id, 'rapports'));
create policy "rh rapports suppression" on public.rh_rapports
  for delete to authenticated using (auteur_id = public.rh_moi() and statut = 'brouillon');

drop policy if exists "rh depenses lecture" on public.rh_depenses;
drop policy if exists "rh depenses demande" on public.rh_depenses;
drop policy if exists "rh depenses modification" on public.rh_depenses;
create policy "rh depenses lecture" on public.rh_depenses
  for select to authenticated using (
    public.rh_est_admin()
    or demandeur_id = public.rh_moi()
    or (profil_id is not null and public.rh_responsable_de(profil_id))
    or (public.rh_peut_decaisser() and statut in ('approuvee', 'decaissee')));
create policy "rh depenses demande" on public.rh_depenses
  for insert to authenticated
  with check (public.rh_moi() is not null and public.rh_menu_ouvert('depenses'));
create policy "rh depenses modification" on public.rh_depenses
  for update to authenticated
  using (demandeur_id = public.rh_moi()) with check (demandeur_id = public.rh_moi());

drop policy if exists "rh cotisations administration" on public.rh_cotisations;
create policy "rh cotisations administration" on public.rh_cotisations
  for all to authenticated using (public.rh_est_admin()) with check (public.rh_est_admin());
drop policy if exists "rh tranches administration" on public.rh_tranches_impot;
create policy "rh tranches administration" on public.rh_tranches_impot
  for all to authenticated using (public.rh_est_admin()) with check (public.rh_est_admin());
drop policy if exists "rh reglages lecture" on public.rh_reglages_paie;
drop policy if exists "rh reglages modification" on public.rh_reglages_paie;
create policy "rh reglages lecture" on public.rh_reglages_paie
  for select to authenticated using (public.rh_est_admin());
create policy "rh reglages modification" on public.rh_reglages_paie
  for update to authenticated using (public.rh_est_admin()) with check (public.rh_est_admin());

drop policy if exists "rh elements administration" on public.rh_elements_paie;
create policy "rh elements administration" on public.rh_elements_paie
  for all to authenticated using (public.rh_est_admin()) with check (public.rh_est_admin());

drop policy if exists "rh avances lecture" on public.rh_avances;
drop policy if exists "rh avances ecriture" on public.rh_avances;
create policy "rh avances lecture" on public.rh_avances
  for select to authenticated using (public.rh_est_admin() or employe_id = public.rh_moi());
create policy "rh avances ecriture" on public.rh_avances
  for all to authenticated using (public.rh_est_admin()) with check (public.rh_est_admin());

drop policy if exists "rh fiches lecture" on public.rh_fiches_paie;
-- L'employé voit ses fiches une fois validées : un brouillon de paie
-- n'est pas une promesse. Personne d'autre que l'administration ne lit
-- la fiche d'un autre : la paie se verse sur le solde, la caisse ne la
-- paie plus.
create policy "rh fiches lecture" on public.rh_fiches_paie
  for select to authenticated using (
    public.rh_est_admin()
    or (statut <> 'calculee' and employe_id = public.rh_moi()));

-- ---------- Les droits ----------
-- Supabase accorde d'office tout à « anon » sur ce qui naît dans
-- « public » : on le lui retire nommément. Les tables se lisent et
-- s'écrivent sous les règles ci-dessus ; les décisions passent par
-- leurs fonctions.
do $$
declare t text;
begin
  foreach t in array array['rh_employes', 'rh_profils', 'rh_messages', 'rh_lectures',
    'rh_missions', 'rh_rapports', 'rh_depenses', 'rh_cotisations', 'rh_tranches_impot',
    'rh_reglages_paie', 'rh_elements_paie', 'rh_avances', 'rh_fiches_paie',
    'rh_fiche_avances', 'rh_boites_mail'] loop
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
    execute format('grant all on table public.%I to service_role', t);
  end loop;
end $$;
grant select, insert, update, delete on public.rh_employes, public.rh_profils,
  public.rh_missions, public.rh_rapports, public.rh_cotisations, public.rh_tranches_impot,
  public.rh_elements_paie, public.rh_avances to authenticated;
grant select, insert on public.rh_messages to authenticated;
grant select, update on public.rh_depenses, public.rh_reglages_paie to authenticated;
grant insert on public.rh_depenses to authenticated;
grant select on public.rh_fiches_paie to authenticated;
revoke all on sequence public.rh_matricule_seq from public, anon;
grant usage on sequence public.rh_matricule_seq to authenticated, service_role;

-- Les fonctions : aucune pour « anon » ; les décisions et les aides
-- des règles pour les comptes connectés ; le calcul de la paie pour
-- personne — il ne s'appelle que de l'intérieur.
do $$
declare f text;
begin
  foreach f in array array[
    'rh_moi()', 'rh_est_ceo()', 'rh_est_admin()', 'rh_peut_decaisser()', 'rh_mon_profil()',
    'rh_responsable_de(uuid)', 'rh_membre_de(uuid)', 'rh_peut_ecrire_a(uuid)',
    'rh_acces(uuid, text)', 'rh_menu_ouvert(text)',
    'rh_decider_employe(uuid, boolean, text)', 'rh_sortie_employe(uuid, date, text)',
    'rh_rattacher_compte(uuid)', 'rh_devenir_ceo(text, text, text)', 'rh_annuaire()',
    'rh_designer_ceo(text, text, text, text, text, text, text)',
    'rh_marquer_lu(text)', 'rh_conversations()',
    'rh_repondre_mission(uuid, boolean, text)', 'rh_rendre_rapport_mission(uuid, text)',
    'rh_cloturer_mission(uuid, boolean, text)',
    'rh_publier_rapport(uuid)', 'rh_decider_rapport(uuid, boolean, text)',
    'rh_decider_depense(uuid, boolean, text)', 'rh_decaisser_depense(uuid, text, text)',
    'rh_annuler_depense(uuid)',
    'rh_valider_cotisation(uuid)', 'rh_valider_bareme_impot()',
    'rh_generer_paie(date)', 'rh_paie_a_jour()', 'rh_valider_paie(date)',
    'rh_rouvrir_fiche(uuid)', 'rh_payer_fiche(uuid, text, text)',
    'rh_ma_messagerie()', 'rh_oublier_ma_messagerie()', 'rh_tableau_de_bord()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
  foreach f in array array[
    'rh_calculer_fiche(uuid, date)', 'rh_generer_paie_interne(date)', 'rh_generer_paie_auto()',
    'rh_employe_verrous()', 'rh_employe_apres()', 'rh_profil_verrous()', 'rh_compte_personnel()',
    'rh_message_verrous()', 'rh_mission_verrous()', 'rh_rapport_verrous()',
    'rh_depense_verrous()', 'rh_cotisation_verrous()', 'rh_reglages_verrous()',
    'rh_tranches_changent()', 'rh_element_paie_change()', 'rh_element_verrous()',
    'rh_avance_change()'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

-- ---------- La paie de fin de mois, toute seule ----------
-- pg_cron appelle la paie chaque soir du 28 au 31 à 18 h (heure du
-- Bénin, 17 h UTC) ; la fonction ne travaille que le dernier jour. Sans
-- pg_cron, rien ne casse : l'application rattrape à l'ouverture.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('rh-paie-fin-de-mois', '0 17 28-31 * *',
                          'select public.rh_generer_paie_auto()');
  end if;
exception when others then
  raise notice 'Paie automatique non programmée (%), l''application la rattrapera', sqlerrm;
end $$;

-- =========================================================
-- BIZZOO Personnel : les statistiques de l'entreprise
--
-- Commandes, livraisons, SAV et avis, sur une période, lus dans
-- BIZZOO Personnel. Rien de la place de marché n'est modifié :
-- une seule fonction de lecture, qui décide elle-même de ce que
-- chacun voit.
--
--   le CEO            — tout, la marge de BIZZOO comprise ;
--   l'administration  — tout, sauf la marge ;
--   un responsable    — les seules rubriques que l'administration a
--                       ouvertes à son profil (« Logistique » →
--                       livraisons, par exemple), et AUCUN montant ;
--   les autres        — rien.
--
-- Les montants et la marge ne sont pas cachés par l'écran : ils ne
-- sortent pas de la base pour qui n'y a pas droit.
--
-- Se colle tel quel dans l'éditeur SQL de Supabase, et se rejoue.
-- =========================================================

-- Les rubriques qu'un profil voit, réglées par l'administration.
alter table public.rh_profils
  add column if not exists statistiques text[] not null default '{}';
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'rh_profils_statistiques_check') then
    alter table public.rh_profils add constraint rh_profils_statistiques_check
      check (statistiques <@ array['commandes', 'livraisons', 'sav']::text[]);
  end if;
end $$;

/**
 * Les statistiques d'une période (par défaut, les 30 derniers jours,
 * heure du Bénin). Une commande compte au jour de son paiement ; une
 * ligne annulée ne compte jamais comme vente.
 */
create or replace function public.rh_statistiques(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  fin date := coalesce(jusqu, aujourdhui);
  debut date := coalesce(depuis, coalesce(jusqu, aujourdhui) - 29);
  t1 timestamptz;
  t2 timestamptz;
  v_ceo boolean := public.rh_est_ceo();
  v_admin boolean := public.rh_est_admin();
  argent boolean;
  marge boolean;
  rubriques text[];
  sous text[];
  commandes jsonb := null;
  livraisons jsonb := null;
  sav jsonb := null;
begin
  -- Les sous-menus ouverts par le menu Paramètres (tous pour
  -- l'administration), puis les blocs de calcul dont ils dépendent.
  select coalesce(array_agg(x.s order by x.n), '{}') into sous
    from unnest(array['commandes', 'boutiques', 'produits', 'livraisons', 'livreurs', 'sav'])
         with ordinality as x(s, n)
   where public.rh_menu_ouvert('stats_' || x.s);
  rubriques := array[]::text[];
  if sous && array['commandes', 'boutiques', 'produits'] then
    rubriques := rubriques || 'commandes'::text;
  end if;
  if sous && array['livraisons', 'livreurs'] then
    rubriques := rubriques || 'livraisons'::text;
  end if;
  if 'sav' = any(sous) then
    rubriques := rubriques || 'sav'::text;
  end if;
  if coalesce(array_length(rubriques, 1), 0) = 0 then
    raise exception 'Votre compte n''a pas accès aux statistiques';
  end if;
  argent := v_admin;
  marge := v_ceo;
  if fin < debut then
    raise exception 'La fin de la période précède son début';
  end if;
  if fin - debut > 1100 then
    raise exception 'Choisissez une période de trois ans au plus';
  end if;
  t1 := debut::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (fin + 1)::timestamp at time zone 'Africa/Porto-Novo';

  -- ---------- Les commandes ----------
  if 'commandes' = any(rubriques) then
    with payees as (
      select c.* from public.commandes c
       where c.etat = 'payee' and c.paye_le >= t1 and c.paye_le < t2
    ),
    lignes as (
      select l.*, c.paye_le from public.commande_lignes l
        join payees c on c.id = l.commande_id
       where l.etat <> 'annulee'
    )
    select jsonb_build_object(
      'creees', (select count(*) from public.commandes c where c.cree_le >= t1 and c.cree_le < t2),
      'payees', (select count(*) from payees),
      'a_payer', (select count(*) from public.commandes c
                   where c.etat = 'a_payer' and c.cree_le >= t1 and c.cree_le < t2),
      'echouees', (select count(*) from public.commandes c
                    where c.etat in ('echouee', 'annulee') and c.cree_le >= t1 and c.cree_le < t2),
      'revendeurs', (select count(*) from payees where revendeur),
      'articles', (select coalesce(sum(quantite), 0) from lignes),
      'montant', case when argent then (select coalesce(sum(total), 0) from payees) end,
      'panier_moyen', case when argent then (select coalesce(round(avg(total)), 0) from payees) end,
      'frais_livraison', case when argent then (select coalesce(sum(frais_livraison), 0) from payees) end,
      'remises', case when argent then (select coalesce(sum(remise), 0) from payees) end,
      'benefice', case when marge then
        (select coalesce(sum(greatest(0, prix - prix_bizzoo) * quantite), 0) from lignes) end,
      'reverse_boutiques', case when marge then
        (select coalesce(sum(prix_bizzoo * quantite), 0) from lignes) end,
      'par_jour', (select coalesce(jsonb_agg(jsonb_build_object(
                      'jour', j.jour, 'payees', j.nb,
                      'montant', case when argent then j.montant end) order by j.jour), '[]')
                     from (select (paye_le at time zone 'Africa/Porto-Novo')::date as jour,
                                  count(*) as nb, sum(total) as montant
                             from payees group by 1) j),
      'boutiques', (select coalesce(jsonb_agg(jsonb_build_object(
                       'boutique', b.nom, 'commandes', x.nb, 'articles', x.qte,
                       'ventes', case when argent then x.ventes end,
                       'benefice', case when marge then x.benefice end) order by x.qte desc), '[]')
                      from (select boutique_id, count(distinct commande_id) as nb, sum(quantite) as qte,
                                   sum(prix * quantite) as ventes,
                                   sum(greatest(0, prix - prix_bizzoo) * quantite) as benefice
                              from lignes group by boutique_id
                             order by sum(quantite) desc limit 10) x
                      left join public.boutiques b on b.id = x.boutique_id),
      'produits', (select coalesce(jsonb_agg(jsonb_build_object(
                      'produit', x.nom, 'code', x.code, 'articles', x.qte,
                      'ventes', case when argent then x.ventes end) order by x.qte desc), '[]')
                     from (select max(nom) as nom, max(code) as code, sum(quantite) as qte,
                                  sum(prix * quantite) as ventes
                             from lignes group by produit_id
                            order by sum(quantite) desc limit 10) x)
    ) into commandes;
  end if;

  -- ---------- Les livraisons ----------
  if 'livraisons' = any(rubriques) then
    with lignes as (
      select l.*, c.paye_le from public.commande_lignes l
        join public.commandes c on c.id = l.commande_id
       where c.etat = 'payee' and c.paye_le >= t1 and c.paye_le < t2
    )
    select jsonb_build_object(
      'par_etat', (select coalesce(jsonb_object_agg(etat, nb), '{}')
                     from (select etat, count(*) as nb from lignes group by etat) e),
      'livrees', (select count(*) from lignes where etat = 'remise'),
      'en_cours', (select count(*) from lignes where etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')),
      'annulees', (select count(*) from lignes where etat = 'annulee'),
      -- « confirme_le » : le client a dit « je l'ai bien reçu ». (« recu_le », lui,
      -- est le moment où le LIVREUR accepte la course : ce n'est pas une réception.)
      'delai_moyen_heures', (select round(avg(extract(epoch from (confirme_le - paye_le)) / 3600)::numeric, 1)
                               from lignes where confirme_le is not null and confirme_le >= paye_le),
      'confirmees', (select count(*) from lignes where confirme_le is not null),
      'livreurs', (select coalesce(jsonb_agg(jsonb_build_object(
                      'livreur', coalesce(nullif(pr.nom, ''), pr.email, 'Livreur'),
                      'commandes', x.nb, 'livrees', x.livrees,
                      'gains', case when argent then
                        (select coalesce(sum(g.montant), 0) from public.gains_livreurs g
                          where g.livreur_id = x.livreur_id and g.credite_le >= t1 and g.credite_le < t2) end)
                      order by x.livrees desc), '[]')
                     from (select livreur_id, count(distinct commande_id) as nb,
                                  count(*) filter (where etat = 'remise') as livrees
                             from lignes where livreur_id is not null
                            group by livreur_id order by 3 desc limit 20) x
                     left join public.profils pr on pr.id = x.livreur_id)
    ) into livraisons;
  end if;

  -- ---------- Le SAV et les avis ----------
  if 'sav' = any(rubriques) then
    select jsonb_build_object(
      'reclamations', (select count(*) from public.reclamations r where r.cree_le >= t1 and r.cree_le < t2),
      'par_etat', (select coalesce(jsonb_object_agg(etat, nb), '{}')
                     from (select etat, count(*) as nb from public.reclamations r
                            where r.cree_le >= t1 and r.cree_le < t2 group by etat) e),
      'par_sujet', (select coalesce(jsonb_object_agg(sujet, nb), '{}')
                      from (select sujet, count(*) as nb from public.reclamations r
                             where r.cree_le >= t1 and r.cree_le < t2 group by sujet) s),
      'avis', (select count(*) from public.avis a where a.cree_le >= t1 and a.cree_le < t2),
      'note_moyenne', (select round(avg(note)::numeric, 2) from public.avis a
                        where a.cree_le >= t1 and a.cree_le < t2 and not a.masque),
      'notes', (select coalesce(jsonb_object_agg(note, nb), '{}')
                  from (select note, count(*) as nb from public.avis a
                         where a.cree_le >= t1 and a.cree_le < t2 and not a.masque group by note) n),
      'avis_masques', (select count(*) from public.avis a
                        where a.cree_le >= t1 and a.cree_le < t2 and a.masque)
    ) into sav;
  end if;

  -- Chacun ne reçoit que ce que ses sous-menus montrent.
  if commandes is not null then
    if not 'boutiques' = any(sous) then
      commandes := commandes - 'boutiques';
    end if;
    if not 'produits' = any(sous) then
      commandes := commandes - 'produits';
    end if;
    if not 'commandes' = any(sous) then
      commandes := jsonb_strip_nulls(jsonb_build_object(
        'boutiques', commandes -> 'boutiques', 'produits', commandes -> 'produits'));
    end if;
  end if;
  if livraisons is not null then
    if not 'livreurs' = any(sous) then
      livraisons := livraisons - 'livreurs';
    end if;
    if not 'livraisons' = any(sous) then
      livraisons := jsonb_strip_nulls(jsonb_build_object('livreurs', livraisons -> 'livreurs'));
    end if;
  end if;

  return jsonb_build_object(
    'periode', jsonb_build_object('depuis', debut, 'jusqu', fin),
    'droits', jsonb_build_object('rubriques', to_jsonb(sous), 'argent', argent, 'marge', marge),
    'commandes', commandes, 'livraisons', livraisons, 'sav', sav);
end $$;

revoke all on function public.rh_statistiques(date, date) from public, anon;
grant execute on function public.rh_statistiques(date, date) to authenticated, service_role;

-- =========================================================
-- BIZZOO Personnel : le suivi des commandes
--
-- Le tableau de bord demandé par BIZZOO (« Tableau de bord de suivi
-- des commandes ») : une commande par ligne, un statut actualisé, des
-- alertes à part du statut, des incidents, une clôture, un bilan par
-- jour, semaine ou mois, et l'export pour Excel.
--
-- CE FICHIER NE TOUCHE À AUCUNE RÈGLE DE LA PLACE DE MARCHÉ. Il ajoute :
--   - un JOURNAL des étapes de chaque article (« rh_journal_lignes »),
--     tenu par un déclencheur qui ne bloque JAMAIS une commande : une
--     erreur du journal est avalée, la commande passe. C'est lui qui
--     donne les délais (vu → préparé → reçu par le client) ;
--   - ce que l'administration note elle-même : les étapes que le
--     terrain ne saisit pas encore (colis récupéré, livraison échouée,
--     retour en cours, retourné au marchand), la zone corrigée, les
--     observations, les incidents, la clôture ;
--   - les seuils des retards, réglables ;
--   - un référentiel des zones du Bénin, pour lire la zone dans
--     l'adresse libre du client.
--
-- QUI : le CEO et l'administration voient et agissent, montants
-- compris ; le responsable d'un profil coché « suivi » voit et agit,
-- SANS aucun montant. Les autres : rien.
--
-- Le journal ne connaît que ce qui arrive APRÈS son installation. Pour
-- les commandes d'avant, il reconstitue ce que la base avait daté
-- (commande, paiement, course acceptée, réception confirmée) et le
-- marque « reconstitué ».
--
-- Se colle tel quel dans l'éditeur SQL de Supabase, et se rejoue.
-- =========================================================

-- La rubrique « suivi » s'ajoute à celles qu'un profil peut ouvrir.
alter table public.rh_profils
  add column if not exists statistiques text[] not null default '{}';
alter table public.rh_profils drop constraint if exists rh_profils_statistiques_check;
alter table public.rh_profils add constraint rh_profils_statistiques_check
  check (statistiques <@ array['commandes', 'livraisons', 'sav', 'suivi']::text[]);

-- Qui est connecté : recopié de personnel.sql, pour que ce fichier se suffise.
create or replace function public.rh_moi() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_est_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and (administration or ceo));
$$;

/** Le droit au suivi : « admin » (montants compris), « responsable »
    (sans montant : un profil à qui le menu Paramètres l'ouvre), ou rien. */
create or replace function public.rh_suivi_acces() returns text
language sql stable security definer set search_path = public as $$
  select case
    when public.rh_est_admin() then 'admin'
    when public.rh_menu_ouvert('suivi') then 'responsable'
  end;
$$;

-- ---------- Le journal des étapes ----------
create table if not exists public.rh_journal_lignes (
  id           bigint generated always as identity primary key,
  commande_id  text not null,
  ligne_id     text,
  boutique_id  text,
  -- « etat » (valeur : le nouvel état), « livreur » (valeur : son id),
  -- « course_acceptee », « confirmee » (le client), « payee »,
  -- « commande » (valeur : le nouvel état de la commande).
  quoi         text not null,
  valeur       text not null default '',
  le           timestamptz not null default now(),
  -- Reconstitué depuis les dates que la base avait déjà : sans l'heure
  -- des étapes intermédiaires.
  reconstitue  boolean not null default false
);
create index if not exists rh_journal_lignes_commande on public.rh_journal_lignes (commande_id, le);

-- Les colonnes que le journal lit, posées comme le fait schema.sql.
alter table public.commande_lignes add column if not exists confirme_le timestamptz;
alter table public.commande_lignes add column if not exists livreur_id uuid;
alter table public.commande_lignes add column if not exists recu_le timestamptz;

/* JAMAIS D'ERREUR VERS LA COMMANDE : tout est dans un bloc qui avale
   ses propres échecs. Un journal manqué se regrette ; une commande
   bloquée par un journal, jamais. */
create or replace function public.rh_journaliser_ligne() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    if tg_op = 'INSERT' then
      insert into public.rh_journal_lignes (commande_id, ligne_id, boutique_id, quoi, valeur)
      values (new.commande_id, new.id, new.boutique_id, 'etat', coalesce(new.etat, ''));
      return null;
    end if;
    if new.etat is distinct from old.etat then
      insert into public.rh_journal_lignes (commande_id, ligne_id, boutique_id, quoi, valeur)
      values (new.commande_id, new.id, new.boutique_id, 'etat', coalesce(new.etat, ''));
    end if;
    if new.livreur_id is distinct from old.livreur_id then
      insert into public.rh_journal_lignes (commande_id, ligne_id, boutique_id, quoi, valeur)
      values (new.commande_id, new.id, new.boutique_id, 'livreur', coalesce(new.livreur_id::text, ''));
    end if;
    if new.recu_le is not null and old.recu_le is null then
      insert into public.rh_journal_lignes (commande_id, ligne_id, boutique_id, quoi, le)
      values (new.commande_id, new.id, new.boutique_id, 'course_acceptee', new.recu_le);
    end if;
    if new.confirme_le is not null and old.confirme_le is null then
      insert into public.rh_journal_lignes (commande_id, ligne_id, boutique_id, quoi, le)
      values (new.commande_id, new.id, new.boutique_id, 'confirmee', new.confirme_le);
    end if;
  exception when others then
    null;
  end;
  return null;
end $$;

drop trigger if exists rh_journal_lignes on public.commande_lignes;
create trigger rh_journal_lignes
  after insert or update on public.commande_lignes
  for each row execute function public.rh_journaliser_ligne();

create or replace function public.rh_journaliser_commande() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    if new.etat is distinct from old.etat then
      insert into public.rh_journal_lignes (commande_id, quoi, valeur, le)
      values (new.id, 'commande', coalesce(new.etat, ''),
              case when new.etat = 'payee' then coalesce(new.paye_le, now()) else now() end);
    end if;
  exception when others then
    null;
  end;
  return null;
end $$;

drop trigger if exists rh_journal_commandes on public.commandes;
create trigger rh_journal_commandes
  after update on public.commandes
  for each row execute function public.rh_journaliser_commande();

-- Les commandes d'avant le journal : ce que la base avait daté.
insert into public.rh_journal_lignes (commande_id, ligne_id, boutique_id, quoi, valeur, le, reconstitue)
select l.commande_id, l.id, l.boutique_id, 'etat', 'nouvelle', l.cree_le, true
  from public.commande_lignes l
 where not exists (select 1 from public.rh_journal_lignes j where j.ligne_id = l.id);
insert into public.rh_journal_lignes (commande_id, ligne_id, boutique_id, quoi, le, reconstitue)
select l.commande_id, l.id, l.boutique_id, 'course_acceptee', l.recu_le, true
  from public.commande_lignes l
 where l.recu_le is not null
   and not exists (select 1 from public.rh_journal_lignes j where j.ligne_id = l.id and j.quoi = 'course_acceptee');
insert into public.rh_journal_lignes (commande_id, ligne_id, boutique_id, quoi, le, reconstitue)
select l.commande_id, l.id, l.boutique_id, 'confirmee', l.confirme_le, true
  from public.commande_lignes l
 where l.confirme_le is not null
   and not exists (select 1 from public.rh_journal_lignes j where j.ligne_id = l.id and j.quoi = 'confirmee');
insert into public.rh_journal_lignes (commande_id, quoi, valeur, le, reconstitue)
select c.id, 'commande', 'payee', c.paye_le, true
  from public.commandes c
 where c.paye_le is not null
   and not exists (select 1 from public.rh_journal_lignes j
                    where j.commande_id = c.id and j.quoi = 'commande' and j.valeur = 'payee');

-- ---------- Ce que l'administration note ----------
-- Les étapes que le terrain ne saisit pas encore, article par article.
create table if not exists public.rh_suivi_lignes (
  ligne_id     text primary key,
  commande_id  text not null,
  statut       text not null check (statut in ('recupere', 'echouee', 'retour_en_cours', 'retournee')),
  motif        text not null default '',
  maj_par      uuid,
  maj_le       timestamptz not null default now()
);
create index if not exists rh_suivi_lignes_commande on public.rh_suivi_lignes (commande_id);

create table if not exists public.rh_suivi_commandes (
  commande_id   text primary key,
  zone          text not null default '',
  observations  text not null default '',
  cloturee_le   timestamptz,
  cloturee_par  uuid,
  maj_par       uuid,
  maj_le        timestamptz not null default now()
);

create table if not exists public.rh_incidents (
  id           bigint generated always as identity primary key,
  commande_id  text not null,
  boutique_id  text,
  livreur_id   uuid,
  type         text not null check (type in ('retard', 'colis_abime', 'colis_perdu', 'client_absent',
                                             'adresse', 'paiement', 'erreur_article', 'autre')),
  description  text not null default '',
  cree_par     uuid,
  cree_le      timestamptz not null default now(),
  resolu_le    timestamptz,
  resolu_par   uuid,
  resolution   text not null default ''
);
create index if not exists rh_incidents_commande on public.rh_incidents (commande_id);

-- Les seuils des retards, en heures. Des valeurs de départ, à régler.
create table if not exists public.rh_reglages_suivi (
  id              boolean primary key default true check (id),
  vue_h           int not null default 2 check (vue_h between 1 and 720),
  preparation_h   int not null default 24 check (preparation_h between 1 and 720),
  livraison_h     int not null default 48 check (livraison_h between 1 and 720),
  confirmation_h  int not null default 24 check (confirmation_h between 1 and 720)
);
insert into public.rh_reglages_suivi (id) values (true) on conflict (id) do nothing;

-- ---------- Les zones ----------
-- Communes (toutes) et quartiers ou arrondissements connus du
-- référentiel du découpage du Bénin. La liste des quartiers est
-- partielle : l'administration corrige la zone d'une commande, et peut
-- ajouter un nom (« ajout »).
create table if not exists public.rh_zones (
  id           bigint generated always as identity primary key,
  nom          text not null,
  type         text not null check (type in ('commune', 'arrondissement', 'quartier', 'village', 'ajout')),
  commune      text not null default '',
  departement  text not null default ''
);
create unique index if not exists rh_zones_unique on public.rh_zones (nom, type, commune);

/** Un nom sans accents ni ponctuation, en minuscules : « Fidjrossè » = « fidjrosse ». */
create or replace function public.rh_cle(t text) returns text
language sql immutable set search_path = public as $$
  select btrim(regexp_replace(
           translate(lower(coalesce(t, '')),
                     'àâäáãéèêëíìîïóòôöõúùûüçñ''’-_/.,;:()',
                     'aaaaaeeeeiiiiooooouuuucn            '),
           '\s+', ' ', 'g'));
$$;

insert into public.rh_zones (nom, type, commune, departement) values
  ('Banikoara', 'commune', 'Banikoara', 'Alibori'),
  ('Gogounou', 'commune', 'Gogounou', 'Alibori'),
  ('Kandi', 'commune', 'Kandi', 'Alibori'),
  ('Karimama', 'commune', 'Karimama', 'Alibori'),
  ('Malanville', 'commune', 'Malanville', 'Alibori'),
  ('Ségbana', 'commune', 'Ségbana', 'Alibori'),
  ('Boukoumbé', 'commune', 'Boukoumbé', 'Atacora'),
  ('Cobly', 'commune', 'Cobly', 'Atacora'),
  ('Kérou', 'commune', 'Kérou', 'Atacora'),
  ('Kouandé', 'commune', 'Kouandé', 'Atacora'),
  ('Matéri', 'commune', 'Matéri', 'Atacora'),
  ('Natitingou', 'commune', 'Natitingou', 'Atacora'),
  ('Péhunco', 'commune', 'Péhunco', 'Atacora'),
  ('Tanguiéta', 'commune', 'Tanguiéta', 'Atacora'),
  ('Toucountouna', 'commune', 'Toucountouna', 'Atacora'),
  ('Abomey-Calavi', 'commune', 'Abomey-Calavi', 'Atlantique'),
  ('Allada', 'commune', 'Allada', 'Atlantique'),
  ('Kpomassè', 'commune', 'Kpomassè', 'Atlantique'),
  ('Ouidah', 'commune', 'Ouidah', 'Atlantique'),
  ('Sô-Ava', 'commune', 'Sô-Ava', 'Atlantique'),
  ('Toffo', 'commune', 'Toffo', 'Atlantique'),
  ('Tori-Bossito', 'commune', 'Tori-Bossito', 'Atlantique'),
  ('Zè', 'commune', 'Zè', 'Atlantique'),
  ('Bembèrèkè', 'commune', 'Bembèrèkè', 'Borgou'),
  ('Kalalé', 'commune', 'Kalalé', 'Borgou'),
  ('N''Dali', 'commune', 'N''Dali', 'Borgou'),
  ('Nikki', 'commune', 'Nikki', 'Borgou'),
  ('Parakou', 'commune', 'Parakou', 'Borgou'),
  ('Pèrèrè', 'commune', 'Pèrèrè', 'Borgou'),
  ('Sinendé', 'commune', 'Sinendé', 'Borgou'),
  ('Tchaourou', 'commune', 'Tchaourou', 'Borgou'),
  ('Bantè', 'commune', 'Bantè', 'Collines'),
  ('Dassa-Zoumè', 'commune', 'Dassa-Zoumè', 'Collines'),
  ('Glazoué', 'commune', 'Glazoué', 'Collines'),
  ('Ouèssè', 'commune', 'Ouèssè', 'Collines'),
  ('Savalou', 'commune', 'Savalou', 'Collines'),
  ('Savè', 'commune', 'Savè', 'Collines'),
  ('Aplahoué', 'commune', 'Aplahoué', 'Couffo'),
  ('Djakotomey', 'commune', 'Djakotomey', 'Couffo'),
  ('Dogbo', 'commune', 'Dogbo', 'Couffo'),
  ('Klouékanmè', 'commune', 'Klouékanmè', 'Couffo'),
  ('Lalo', 'commune', 'Lalo', 'Couffo'),
  ('Toviklin', 'commune', 'Toviklin', 'Couffo'),
  ('Bassila', 'commune', 'Bassila', 'Donga'),
  ('Copargo', 'commune', 'Copargo', 'Donga'),
  ('Djougou', 'commune', 'Djougou', 'Donga'),
  ('Ouaké', 'commune', 'Ouaké', 'Donga'),
  ('Cotonou', 'commune', 'Cotonou', 'Littoral'),
  ('Athiémé', 'commune', 'Athiémé', 'Mono'),
  ('Bopa', 'commune', 'Bopa', 'Mono'),
  ('Comè', 'commune', 'Comè', 'Mono'),
  ('Grand-Popo', 'commune', 'Grand-Popo', 'Mono'),
  ('Houéyogbé', 'commune', 'Houéyogbé', 'Mono'),
  ('Lokossa', 'commune', 'Lokossa', 'Mono'),
  ('Adjarra', 'commune', 'Adjarra', 'Ouémé'),
  ('Adjohoun', 'commune', 'Adjohoun', 'Ouémé'),
  ('Aguégués', 'commune', 'Aguégués', 'Ouémé'),
  ('Akpro-Missérété', 'commune', 'Akpro-Missérété', 'Ouémé'),
  ('Avrankou', 'commune', 'Avrankou', 'Ouémé'),
  ('Bonou', 'commune', 'Bonou', 'Ouémé'),
  ('Dangbo', 'commune', 'Dangbo', 'Ouémé'),
  ('Porto-Novo', 'commune', 'Porto-Novo', 'Ouémé'),
  ('Sèmè-Kpodji', 'commune', 'Sèmè-Kpodji', 'Ouémé'),
  ('Adja-Ouèrè', 'commune', 'Adja-Ouèrè', 'Plateau'),
  ('Ifangni', 'commune', 'Ifangni', 'Plateau'),
  ('Kétou', 'commune', 'Kétou', 'Plateau'),
  ('Pobè', 'commune', 'Pobè', 'Plateau'),
  ('Sakété', 'commune', 'Sakété', 'Plateau'),
  ('Abomey', 'commune', 'Abomey', 'Zou'),
  ('Agbangnizoun', 'commune', 'Agbangnizoun', 'Zou'),
  ('Bohicon', 'commune', 'Bohicon', 'Zou'),
  ('Covè', 'commune', 'Covè', 'Zou'),
  ('Djidja', 'commune', 'Djidja', 'Zou'),
  ('Ouinhi', 'commune', 'Ouinhi', 'Zou'),
  ('Za-Kpota', 'commune', 'Za-Kpota', 'Zou'),
  ('Zagnanado', 'commune', 'Zagnanado', 'Zou'),
  ('Zogbodomey', 'commune', 'Zogbodomey', 'Zou'),
  ('Kotopounga', 'arrondissement', 'Natitingou', 'Atacora'),
  ('Kouandata', 'arrondissement', 'Natitingou', 'Atacora'),
  ('Natitingou Centre', 'arrondissement', 'Natitingou', 'Atacora'),
  ('Perma', 'arrondissement', 'Natitingou', 'Atacora'),
  ('Péporiyakou', 'arrondissement', 'Natitingou', 'Atacora'),
  ('Tchoumi-Tchoumi', 'arrondissement', 'Natitingou', 'Atacora'),
  ('Angaradébou', 'arrondissement', 'Kandi', 'Alibori'),
  ('Bensékou', 'arrondissement', 'Kandi', 'Alibori'),
  ('Donwari', 'arrondissement', 'Kandi', 'Alibori'),
  ('Kandi Centre', 'arrondissement', 'Kandi', 'Alibori'),
  ('Kassakou', 'arrondissement', 'Kandi', 'Alibori'),
  ('Saah', 'arrondissement', 'Kandi', 'Alibori'),
  ('Sam', 'arrondissement', 'Kandi', 'Alibori'),
  ('Abomey-Calavi Centre', 'arrondissement', 'Abomey-Calavi', 'Atlantique'),
  ('Adjagbo', 'quartier', 'Abomey-Calavi', 'Atlantique'),
  ('Akassato', 'arrondissement', 'Abomey-Calavi', 'Atlantique'),
  ('Arconville', 'quartier', 'Abomey-Calavi', 'Atlantique'),
  ('Aïtchédji', 'quartier', 'Abomey-Calavi', 'Atlantique'),
  ('Cococodji', 'quartier', 'Abomey-Calavi', 'Atlantique'),
  ('Cocotomey', 'quartier', 'Abomey-Calavi', 'Atlantique'),
  ('Glo-Djigbé', 'arrondissement', 'Abomey-Calavi', 'Atlantique'),
  ('Godomey', 'arrondissement', 'Abomey-Calavi', 'Atlantique'),
  ('Hêvié', 'arrondissement', 'Abomey-Calavi', 'Atlantique'),
  ('Kpanroun', 'arrondissement', 'Abomey-Calavi', 'Atlantique'),
  ('Missessinto', 'quartier', 'Abomey-Calavi', 'Atlantique'),
  ('Ouèdo', 'arrondissement', 'Abomey-Calavi', 'Atlantique'),
  ('Tankpè', 'quartier', 'Abomey-Calavi', 'Atlantique'),
  ('Togba', 'arrondissement', 'Abomey-Calavi', 'Atlantique'),
  ('Womey', 'quartier', 'Abomey-Calavi', 'Atlantique'),
  ('Zinvié', 'arrondissement', 'Abomey-Calavi', 'Atlantique'),
  ('Zogbadjè', 'quartier', 'Abomey-Calavi', 'Atlantique'),
  ('Avlékété', 'arrondissement', 'Ouidah', 'Atlantique'),
  ('Djègbadji', 'arrondissement', 'Ouidah', 'Atlantique'),
  ('Gakpé', 'arrondissement', 'Ouidah', 'Atlantique'),
  ('Houakpè-Daho', 'arrondissement', 'Ouidah', 'Atlantique'),
  ('Ouidah Centre', 'arrondissement', 'Ouidah', 'Atlantique'),
  ('Pahou', 'arrondissement', 'Ouidah', 'Atlantique'),
  ('Savi', 'arrondissement', 'Ouidah', 'Atlantique'),
  ('Albarika', 'quartier', 'Parakou', 'Borgou'),
  ('Amawignon', 'quartier', 'Parakou', 'Borgou'),
  ('Baka', 'quartier', 'Parakou', 'Borgou'),
  ('Banikanni', 'quartier', 'Parakou', 'Borgou'),
  ('Camp Adagbè', 'quartier', 'Parakou', 'Borgou'),
  ('Dépôt', 'quartier', 'Parakou', 'Borgou'),
  ('Guéma', 'quartier', 'Parakou', 'Borgou'),
  ('Kpébié', 'quartier', 'Parakou', 'Borgou'),
  ('Ladji Farani', 'quartier', 'Parakou', 'Borgou'),
  ('Madina', 'quartier', 'Parakou', 'Borgou'),
  ('Okédama', 'quartier', 'Parakou', 'Borgou'),
  ('Titirou', 'quartier', 'Parakou', 'Borgou'),
  ('Tourou', 'quartier', 'Parakou', 'Borgou'),
  ('Wansirou', 'quartier', 'Parakou', 'Borgou'),
  ('Zongo', 'quartier', 'Parakou', 'Borgou'),
  ('Bariénou', 'arrondissement', 'Djougou', 'Donga'),
  ('Bougou', 'arrondissement', 'Djougou', 'Donga'),
  ('Bèlèfoungou', 'arrondissement', 'Djougou', 'Donga'),
  ('Djougou Centre', 'arrondissement', 'Djougou', 'Donga'),
  ('Kolokondé', 'arrondissement', 'Djougou', 'Donga'),
  ('Onklou', 'arrondissement', 'Djougou', 'Donga'),
  ('Partago', 'arrondissement', 'Djougou', 'Donga'),
  ('Pélébina', 'arrondissement', 'Djougou', 'Donga'),
  ('Sérou', 'arrondissement', 'Djougou', 'Donga'),
  ('Agla', 'quartier', 'Cotonou', 'Littoral'),
  ('Akogbato', 'quartier', 'Cotonou', 'Littoral'),
  ('Akpakpa', 'quartier', 'Cotonou', 'Littoral'),
  ('Avotrou', 'quartier', 'Cotonou', 'Littoral'),
  ('Ayélawadjè', 'quartier', 'Cotonou', 'Littoral'),
  ('Aïbatin', 'quartier', 'Cotonou', 'Littoral'),
  ('Aïdjèdo', 'quartier', 'Cotonou', 'Littoral'),
  ('Cadjèhoun', 'quartier', 'Cotonou', 'Littoral'),
  ('Cocotiers', 'quartier', 'Cotonou', 'Littoral'),
  ('Dandji', 'quartier', 'Cotonou', 'Littoral'),
  ('Dantokpa', 'quartier', 'Cotonou', 'Littoral'),
  ('Djidjè', 'quartier', 'Cotonou', 'Littoral'),
  ('Enagnon', 'quartier', 'Cotonou', 'Littoral'),
  ('Fidjrossè', 'quartier', 'Cotonou', 'Littoral'),
  ('Fifadji', 'quartier', 'Cotonou', 'Littoral'),
  ('Ganhi', 'quartier', 'Cotonou', 'Littoral'),
  ('Gbédjromèdé', 'quartier', 'Cotonou', 'Littoral'),
  ('Gbégamey', 'quartier', 'Cotonou', 'Littoral'),
  ('Guinkomey', 'quartier', 'Cotonou', 'Littoral'),
  ('Haie Vive', 'quartier', 'Cotonou', 'Littoral'),
  ('Houéyiho', 'quartier', 'Cotonou', 'Littoral'),
  ('Jonquet', 'quartier', 'Cotonou', 'Littoral'),
  ('Jéricho', 'quartier', 'Cotonou', 'Littoral'),
  ('Kouhounou', 'quartier', 'Cotonou', 'Littoral'),
  ('Ladji', 'quartier', 'Cotonou', 'Littoral'),
  ('Midombo', 'quartier', 'Cotonou', 'Littoral'),
  ('Missèbo', 'quartier', 'Cotonou', 'Littoral'),
  ('Mènontin', 'quartier', 'Cotonou', 'Littoral'),
  ('Placodji', 'quartier', 'Cotonou', 'Littoral'),
  ('Saint-Jean', 'quartier', 'Cotonou', 'Littoral'),
  ('Saint-Michel', 'quartier', 'Cotonou', 'Littoral'),
  ('Sainte-Rita', 'quartier', 'Cotonou', 'Littoral'),
  ('Scoa Gbéto', 'quartier', 'Cotonou', 'Littoral'),
  ('Sikècodji', 'quartier', 'Cotonou', 'Littoral'),
  ('Sodjèatimè', 'quartier', 'Cotonou', 'Littoral'),
  ('Sègbèya', 'quartier', 'Cotonou', 'Littoral'),
  ('Tokpa', 'quartier', 'Cotonou', 'Littoral'),
  ('Vodjè', 'quartier', 'Cotonou', 'Littoral'),
  ('Vossa', 'quartier', 'Cotonou', 'Littoral'),
  ('Vèdoko', 'quartier', 'Cotonou', 'Littoral'),
  ('Xwlacodji', 'quartier', 'Cotonou', 'Littoral'),
  ('Zogbo', 'quartier', 'Cotonou', 'Littoral'),
  ('Zongo', 'quartier', 'Cotonou', 'Littoral'),
  ('Agatogbo', 'arrondissement', 'Comè', 'Mono'),
  ('Akodéha', 'arrondissement', 'Comè', 'Mono'),
  ('Comè Centre', 'arrondissement', 'Comè', 'Mono'),
  ('Oumako', 'arrondissement', 'Comè', 'Mono'),
  ('Ouèdèmè-Pédah', 'arrondissement', 'Comè', 'Mono'),
  ('Agamè', 'arrondissement', 'Lokossa', 'Mono'),
  ('Houin', 'arrondissement', 'Lokossa', 'Mono'),
  ('Koudo', 'arrondissement', 'Lokossa', 'Mono'),
  ('Lokossa Centre', 'arrondissement', 'Lokossa', 'Mono'),
  ('Adjina', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Agbokou', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Attaké', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Djassin', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Djègan-Daho', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Dowa', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Foun-Foun', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Gbokou', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Houinmè', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Kandévié', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Lokpodji', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Louho', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Ouando', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Tokpota', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Zèbou', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Agblangandan', 'arrondissement', 'Sèmè-Kpodji', 'Ouémé'),
  ('Aholouyèmè', 'arrondissement', 'Sèmè-Kpodji', 'Ouémé'),
  ('Djèffa', 'quartier', 'Sèmè-Kpodji', 'Ouémé'),
  ('Djèrègbé', 'arrondissement', 'Sèmè-Kpodji', 'Ouémé'),
  ('Ekpè', 'arrondissement', 'Sèmè-Kpodji', 'Ouémé'),
  ('Sèmè-Podji Centre', 'arrondissement', 'Sèmè-Kpodji', 'Ouémé'),
  ('Tohouè', 'arrondissement', 'Sèmè-Kpodji', 'Ouémé'),
  ('Agbokpa', 'arrondissement', 'Abomey', 'Zou'),
  ('Djègbé', 'arrondissement', 'Abomey', 'Zou'),
  ('Détohou', 'arrondissement', 'Abomey', 'Zou'),
  ('Hounli', 'arrondissement', 'Abomey', 'Zou'),
  ('Sèhoun', 'arrondissement', 'Abomey', 'Zou'),
  ('Vidolé', 'arrondissement', 'Abomey', 'Zou'),
  ('Zounzonmè', 'arrondissement', 'Abomey', 'Zou'),
  ('Agongointo', 'arrondissement', 'Bohicon', 'Zou'),
  ('Avogbanna', 'arrondissement', 'Bohicon', 'Zou'),
  ('Bohicon Centre', 'arrondissement', 'Bohicon', 'Zou'),
  ('Gnidjazoun', 'arrondissement', 'Bohicon', 'Zou'),
  ('Lissèzoun', 'arrondissement', 'Bohicon', 'Zou'),
  ('Ouassaho', 'arrondissement', 'Bohicon', 'Zou'),
  ('Passagon', 'arrondissement', 'Bohicon', 'Zou'),
  ('Saclo', 'arrondissement', 'Bohicon', 'Zou'),
  ('Sodohomè', 'arrondissement', 'Bohicon', 'Zou')
on conflict (nom, type, commune) do nothing;

/** La zone lue dans une adresse : le quartier si on le reconnaît, sinon la commune. */
create or replace function public.rh_zone_de(adresse text) returns text
language sql stable security definer set search_path = public as $$
  select z.nom || case when z.type <> 'commune' and z.commune <> '' and z.commune <> z.nom
                       then ' (' || z.commune || ')' else '' end
    from public.rh_zones z
   where length(public.rh_cle(z.nom)) >= 3
     and position(' ' || public.rh_cle(z.nom) || ' ' in ' ' || public.rh_cle(adresse) || ' ') > 0
   order by case z.type when 'ajout' then 0 when 'quartier' then 1 when 'village' then 1
                        when 'arrondissement' then 2 else 3 end,
            length(z.nom) desc
   limit 1;
$$;

-- ---------- Le statut ----------
/* L'ordre et les noms du document de BIZZOO. Les incidents ne
   remplacent jamais le statut : ils sont des alertes, à côté. */
create or replace function public.rh_statut_libelle(rang int) returns text
language sql immutable set search_path = public as $$
  select case rang
    when 0 then 'En attente de paiement'
    when 1 then 'Nouvelle commande'
    when 2 then 'Confirmée'
    when 3 then 'Commande préparée'
    when 4 then 'Colis récupéré'
    when 5 then 'En cours de livraison'
    when 6 then 'Livraison effectuée — confirmation en attente'
    when 8 then 'Livré et confirmé'
    when 9 then 'Livraison échouée'
    when 10 then 'Livraison contestée'
    when 11 then 'Annulée'
    when 12 then 'Retour en cours'
    when 13 then 'Retournée au marchand'
    when 14 then 'Clôturée'
    when 15 then 'Paiement échoué'
    else '' end;
$$;

/** Le rang d'un article, de ce que la base et l'administration en savent. */
create or replace function public.rh_statut_ligne(etat text, confirme timestamptz, terrain text, contestee boolean)
returns int
language sql immutable set search_path = public as $$
  select case
    when etat = 'annulee' then 11
    when terrain = 'retournee' then 13
    when terrain = 'retour_en_cours' then 12
    when terrain = 'echouee' then 9
    when contestee then 10
    when confirme is not null then 8
    when etat = 'remise' then 6
    when etat = 'en_livraison' then 5
    when terrain = 'recupere' then 4
    when etat = 'preparee' then 3
    when etat = 'vue' then 2
    else 1 end;
$$;

/**
 * Le suivi d'une liste de commandes : une ligne JSON par commande,
 * articles et marchands compris, alertes calculées. Interne : les
 * fonctions publiques vérifient d'abord qui appelle et ôtent les
 * montants à qui n'y a pas droit.
 */
create or replace function public.rh_suivi_donnees(t1 timestamptz, t2 timestamptz, une text default null)
returns setof jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r public.rh_reglages_suivi;
  maintenant timestamptz := now();
begin
  select * into r from public.rh_reglages_suivi where id;
  return query
  with cmd as (
    select c.* from public.commandes c
     where (une is not null and c.id = une)
        or (une is null and c.cree_le >= t1 and c.cree_le < t2)
     order by c.cree_le desc
     limit 2000
  ),
  lig as (
    select l.*, b.nom as boutique_nom, coalesce(nullif(b.tel, ''), '') as boutique_tel,
           coalesce(nullif(pl.nom, ''), pl.email) as livreur_nom, coalesce(pl.tel, '') as livreur_tel,
           s.statut as terrain, s.motif as terrain_motif,
           exists (select 1 from public.reclamations rc
                    where rc.commande_id = l.commande_id and rc.sujet = 'non_recu'
                      and (rc.boutique_id is null or rc.boutique_id = l.boutique_id)
                      and rc.etat not in ('resolue', 'tranchee')) as contestee,
           (select min(j.le) from public.rh_journal_lignes j
             where j.ligne_id = l.id and j.quoi = 'etat' and j.valeur = 'vue') as vue_le,
           (select min(j.le) from public.rh_journal_lignes j
             where j.ligne_id = l.id and j.quoi = 'etat' and j.valeur = 'preparee') as preparee_le,
           (select min(j.le) from public.rh_journal_lignes j
             where j.ligne_id = l.id and j.quoi = 'etat' and j.valeur = 'remise') as remise_le
      from public.commande_lignes l
      join cmd c on c.id = l.commande_id
      left join public.boutiques b on b.id = l.boutique_id
      left join public.profils pl on pl.id = l.livreur_id
      left join public.rh_suivi_lignes s on s.ligne_id = l.id
  ),
  lig2 as (
    select x.*, public.rh_statut_ligne(x.etat, x.confirme_le, x.terrain, x.contestee) as rang
      from lig x
  )
  select jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'cree_le', c.cree_le, 'paye_le', c.paye_le, 'etat', c.etat,
    -- (3.68.0) D'où vient la commande : passée dans l'application, ou prise
    -- sur WhatsApp et saisie par l'équipe (« Faire livrer »). Lue par
    -- « to_jsonb » : une base sans la colonne répond « Depuis APP ».
    'source', case when to_jsonb(c) ->> 'origine' = 'whatsapp' then 'Par whatsapp' else 'Depuis APP' end,
    'client', jsonb_build_object('nom', c.client_nom,
                                 'tel', btrim(case when coalesce(c.client_indicatif, '') <> '' and c.client_indicatif <> '229'
                                                   then '+' || c.client_indicatif || ' ' else '' end || coalesce(c.client_tel, '')),
                                 'adresse', c.client_adresse,
                                 'zone', coalesce(nullif(sc.zone, ''), public.rh_zone_de(c.client_adresse), ''),
                                 'zone_corrigee', coalesce(sc.zone, '') <> ''),
    'lignes', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', x.id, 'boutique_id', x.boutique_id, 'boutique', coalesce(x.boutique_nom, x.boutique_id),
                 'boutique_tel', x.boutique_tel, 'nom', x.nom, 'code', x.code, 'quantite', x.quantite,
                 'prix', x.prix, 'etat', x.etat, 'rang', x.rang, 'statut', public.rh_statut_libelle(x.rang),
                 'terrain', x.terrain, 'terrain_motif', coalesce(x.terrain_motif, ''),
                 'livreur', x.livreur_nom, 'livreur_tel', x.livreur_tel, 'livreur_id', x.livreur_id,
                 'confirme_le', x.confirme_le, 'vue_le', x.vue_le, 'remise_le', x.remise_le)
               order by x.boutique_nom, x.nom) from lig2 x where x.commande_id = c.id), '[]'),
    'articles', coalesce((select string_agg(x.quantite || ' × ' || x.nom
                                            || case when x.etat = 'annulee' then ' (annulé)' else '' end, ' ; '
                                            order by x.boutique_nom, x.nom)
                            from lig2 x where x.commande_id = c.id), ''),
    'marchands', coalesce((select string_agg(distinct coalesce(x.boutique_nom, x.boutique_id)
                                             || case when x.boutique_tel <> '' then ' / ' || x.boutique_tel else '' end, ' ; ')
                             from lig2 x where x.commande_id = c.id), ''),
    'livreurs', coalesce((select string_agg(distinct x.livreur_nom
                                            || case when x.livreur_tel <> '' then ' / ' || x.livreur_tel else '' end, ' ; ')
                            from lig2 x where x.commande_id = c.id and x.livreur_nom is not null), ''),
    'frais', coalesce(c.frais_livraison, 0), 'total', c.total,
    'reste', case when c.etat = 'payee' then
               coalesce((select sum(greatest(0, rr.a_encaisser - coalesce(e.montant, 0)))
                           from public.restes_par_boutique(c.id) rr
                           left join public.encaissements e on e.commande_id = c.id and e.boutique_id = rr.boutique_id), 0)
             else 0 end,
    'rang', st.rang, 'statut', public.rh_statut_libelle(st.rang),
    'confirmation', case
       when not exists (select 1 from lig2 x where x.commande_id = c.id and x.etat <> 'annulee') then '—'
       when not exists (select 1 from lig2 x where x.commande_id = c.id and x.etat <> 'annulee' and x.confirme_le is null) then 'Oui'
       when exists (select 1 from lig2 x where x.commande_id = c.id and x.confirme_le is not null) then 'Partielle'
       else 'Non' end,
    -- La durée du document : du « vu » du marchand au « je l'ai reçu » du client.
    'delai_h', (select round(max(extract(epoch from (x.confirme_le - x.vue_le)) / 3600)::numeric, 1)
                  from lig2 x where x.commande_id = c.id and x.confirme_le is not null and x.vue_le is not null),
    'observations', coalesce(sc.observations, ''),
    'incidents_ouverts', (select count(*) from public.rh_incidents i where i.commande_id = c.id and i.resolu_le is null),
    'cloturee_le', sc.cloturee_le,
    'alertes', case when c.etat <> 'payee' or sc.cloturee_le is not null then '[]'::jsonb else (
      select coalesce(jsonb_agg(a), '[]') from (
        select 'non_vue' as a where exists (select 1 from lig2 x where x.commande_id = c.id and x.etat = 'nouvelle')
                                 and maintenant - c.paye_le > make_interval(hours => r.vue_h)
        union all
        select 'retard_preparation' where exists (select 1 from lig2 x where x.commande_id = c.id and x.etat = 'vue'
                                 and maintenant - coalesce(x.vue_le, c.paye_le) > make_interval(hours => r.preparation_h))
        union all
        select 'retard_livraison' where exists (select 1 from lig2 x where x.commande_id = c.id and x.rang < 6)
                                 and maintenant - c.paye_le > make_interval(hours => r.livraison_h)
        union all
        select 'sans_confirmation' where exists (select 1 from lig2 x where x.commande_id = c.id and x.rang = 6
                                 and maintenant - coalesce(x.remise_le, c.paye_le) > make_interval(hours => r.confirmation_h))
        union all
        select 'contestee' where exists (select 1 from lig2 x where x.commande_id = c.id and x.contestee)
        union all
        select 'echec' where exists (select 1 from lig2 x where x.commande_id = c.id and x.rang in (9, 12))
        union all
        select 'incident' where exists (select 1 from public.rh_incidents i where i.commande_id = c.id and i.resolu_le is null)
        union all
        select 'refus_course' where exists (select 1 from public.refus_courses f where f.commande_id = c.id)
        union all
        select 'encaissement_conteste' where exists (select 1 from public.encaissements e
                                                     where e.commande_id = c.id and e.conteste_le is not null)
      ) al)
    end)
  from cmd c
  left join public.rh_suivi_commandes sc on sc.commande_id = c.id
  cross join lateral (
    select case
      when sc.cloturee_le is not null then 14
      when c.etat = 'a_payer' then 0
      when c.etat = 'echouee' then 15
      when c.etat = 'annulee' then 11
      when not exists (select 1 from lig2 x where x.commande_id = c.id and x.rang <> 11) then 11
      when exists (select 1 from lig2 x where x.commande_id = c.id and x.rang = 10) then 10
      when exists (select 1 from lig2 x where x.commande_id = c.id and x.rang = 9) then 9
      when exists (select 1 from lig2 x where x.commande_id = c.id and x.rang = 12) then 12
      else (select min(x.rang) from lig2 x where x.commande_id = c.id and x.rang <> 11)
    end as rang) st
  order by c.cree_le desc;
end $$;

/** Ôte les montants pour qui n'y a pas droit. */
create or replace function public.rh_suivi_sans_montants(d jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select (d - 'frais' - 'total' - 'reste')
         || jsonb_build_object('lignes', coalesce((select jsonb_agg(l - 'prix') from jsonb_array_elements(d -> 'lignes') l), '[]'));
$$;

/** Le tableau du suivi : les commandes passées sur une période (heure du Bénin). */
create or replace function public.rh_suivi(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  acces text := public.rh_suivi_acces();
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  fin date := coalesce(jusqu, aujourdhui);
  debut date := coalesce(depuis, coalesce(jusqu, aujourdhui) - 6);
  lignes jsonb;
begin
  if acces is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  if fin < debut then
    raise exception 'La fin de la période précède son début';
  end if;
  if fin - debut > 400 then
    raise exception 'Choisissez une période d''un an au plus';
  end if;
  select coalesce(jsonb_agg(case when acces = 'admin' then d else public.rh_suivi_sans_montants(d) end), '[]')
    into lignes
    from public.rh_suivi_donnees(debut::timestamp at time zone 'Africa/Porto-Novo',
                                 (fin + 1)::timestamp at time zone 'Africa/Porto-Novo') d;
  return jsonb_build_object(
    'periode', jsonb_build_object('depuis', debut, 'jusqu', fin),
    'montants', acces = 'admin',
    'reglages', (select to_jsonb(r) - 'id' from public.rh_reglages_suivi r where r.id),
    'commandes', lignes);
end $$;

/** Les alertes en cours, toutes périodes : le chiffre de la pastille. */
create or replace function public.rh_suivi_alertes_nb() returns int
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rh_suivi_acces() is null then
    return 0;
  end if;
  return (select count(*)::int
            from public.rh_suivi_donnees(now() - interval '60 days', now() + interval '1 day') d
           where jsonb_array_length(d -> 'alertes') > 0
             and (d -> 'alertes') <> '["refus_course"]'::jsonb);
end $$;

/** Une commande : le suivi, la chronologie, les incidents, les réclamations. */
create or replace function public.rh_suivi_commande(commande text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  acces text := public.rh_suivi_acces();
  d jsonb;
begin
  if acces is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  select x into d from public.rh_suivi_donnees(null, null, commande) x;
  if d is null then
    raise exception 'Commande introuvable';
  end if;
  if acces <> 'admin' then
    d := public.rh_suivi_sans_montants(d);
  end if;
  return d || jsonb_build_object(
    'montants', acces = 'admin',
    'journal', coalesce((select jsonb_agg(jsonb_build_object(
                  'le', j.le, 'quoi', j.quoi, 'valeur', j.valeur, 'boutique', coalesce(b.nom, j.boutique_id),
                  'article', l.nom, 'reconstitue', j.reconstitue,
                  'livreur', case when j.quoi = 'livreur' then coalesce(nullif(p.nom, ''), p.email) end)
                order by j.le, j.id)
                from public.rh_journal_lignes j
                left join public.commande_lignes l on l.id = j.ligne_id
                left join public.boutiques b on b.id = j.boutique_id
                left join public.profils p on j.quoi = 'livreur' and p.id::text = j.valeur
               where j.commande_id = commande), '[]'),
    'incidents', coalesce((select jsonb_agg(jsonb_build_object(
                  'id', i.id, 'type', i.type, 'description', i.description, 'cree_le', i.cree_le,
                  'boutique', coalesce(b.nom, i.boutique_id), 'livreur', coalesce(nullif(p.nom, ''), p.email),
                  'auteur', btrim(coalesce(ea.prenoms, '') || ' ' || coalesce(ea.nom, '')),
                  'resolu_le', i.resolu_le, 'resolution', i.resolution) order by i.cree_le)
                from public.rh_incidents i
                left join public.boutiques b on b.id = i.boutique_id
                left join public.profils p on p.id = i.livreur_id
                left join public.rh_employes ea on ea.id = i.cree_par
               where i.commande_id = commande), '[]'),
    'reclamations', coalesce((select jsonb_agg(jsonb_build_object(
                  'sujet', rc.sujet, 'etat', rc.etat, 'cree_le', rc.cree_le,
                  'boutique', coalesce(b.nom, rc.boutique_id)) order by rc.cree_le)
                from public.reclamations rc left join public.boutiques b on b.id = rc.boutique_id
               where rc.commande_id = commande), '[]'),
    'refus', coalesce((select jsonb_agg(jsonb_build_object(
                  'le', f.refuse_le, 'motif', f.motif, 'livreur', coalesce(nullif(p.nom, ''), p.email)) order by f.refuse_le)
                from public.refus_courses f left join public.profils p on p.id = f.livreur_id
               where f.commande_id = commande), '[]'));
end $$;

/** Le bilan d'une période : les indicateurs du document, par jour, semaine ou mois. */
create or replace function public.rh_suivi_bilan(depuis date default null, jusqu date default null, pas text default 'jour')
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  acces text := public.rh_suivi_acces();
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  fin date := coalesce(jusqu, aujourdhui);
  debut date := coalesce(depuis, coalesce(jusqu, aujourdhui) - 29);
  unite text := case pas when 'semaine' then 'week' when 'mois' then 'month' else 'day' end;
begin
  if acces is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  if fin < debut or fin - debut > 400 then
    raise exception 'Choisissez une période valable, d''un an au plus';
  end if;
  return (
    with d as (
      select x as j,
             date_trunc(unite, ((x ->> 'cree_le')::timestamptz at time zone 'Africa/Porto-Novo'))::date as periode
        from public.rh_suivi_donnees(debut::timestamp at time zone 'Africa/Porto-Novo',
                                     (fin + 1)::timestamp at time zone 'Africa/Porto-Novo') x
    ),
    l as (
      select d.periode, d.j ->> 'id' as commande, d.j ->> 'etat' as etat_commande, e as ligne
        from d, jsonb_array_elements(d.j -> 'lignes') e
    ),
    resume as (
      select periode,
             count(*) as recues,
             count(*) filter (where j ->> 'etat' = 'payee') as payees,
             count(*) filter (where (j ->> 'rang')::int in (8, 14) and j ->> 'confirmation' = 'Oui') as livrees_confirmees,
             count(*) filter (where j ->> 'etat' = 'payee' and (j ->> 'rang')::int between 1 and 6) as en_cours,
             count(*) filter (where (j -> 'alertes') ?| array['non_vue', 'retard_preparation', 'retard_livraison', 'sans_confirmation']) as en_retard,
             count(*) filter (where (j ->> 'rang')::int = 10) as contestees,
             count(*) filter (where (j ->> 'rang')::int = 11 or j ->> 'etat' in ('annulee')) as annulees,
             count(*) filter (where j ->> 'etat' = 'echouee') as paiements_echoues,
             count(*) filter (where (j ->> 'rang')::int in (9, 12, 13)) as echecs_retours,
             coalesce(sum((j ->> 'reste')::bigint) filter (where j ->> 'etat' = 'payee'), 0) as reste
        from d group by periode
    )
    select jsonb_build_object(
      'periode', jsonb_build_object('depuis', debut, 'jusqu', fin, 'pas', coalesce(pas, 'jour')),
      'montants', acces = 'admin',
      'total', (select jsonb_build_object(
          'recues', coalesce(sum(recues), 0), 'payees', coalesce(sum(payees), 0),
          'livrees_confirmees', coalesce(sum(livrees_confirmees), 0), 'en_cours', coalesce(sum(en_cours), 0),
          'en_retard', coalesce(sum(en_retard), 0), 'contestees', coalesce(sum(contestees), 0),
          'annulees', coalesce(sum(annulees), 0), 'paiements_echoues', coalesce(sum(paiements_echoues), 0),
          'echecs_retours', coalesce(sum(echecs_retours), 0),
          'reste', case when acces = 'admin' then coalesce(sum(reste), 0) end) from resume),
      'series', coalesce((select jsonb_agg(jsonb_build_object(
          'periode', periode, 'recues', recues, 'payees', payees, 'livrees_confirmees', livrees_confirmees,
          'en_cours', en_cours, 'en_retard', en_retard, 'contestees', contestees, 'annulees', annulees,
          'echecs_retours', echecs_retours,
          'reste', case when acces = 'admin' then reste end) order by periode) from resume), '[]'),
      'par_livreur', coalesce((select jsonb_agg(x order by (x ->> 'confirmees')::int desc) from (
          select jsonb_build_object(
            'livreur', coalesce(k.livreur, '—'),
            'articles', count(*),
            'confirmees', count(*) filter (where k.confirme is not null),
            'sans_confirmation', count(*) filter (where k.rang = 6),
            'echecs', count(*) filter (where k.rang in (9, 12, 13)),
            'contestees', count(*) filter (where k.rang = 10),
            'delai_moyen_h', round(avg(extract(epoch from (k.confirme - k.vue)) / 3600)
                                   filter (where k.confirme is not null and k.vue is not null)::numeric, 1),
            'refus', (select count(*) from public.refus_courses f join public.profils p on p.id = f.livreur_id
                       where coalesce(nullif(p.nom, ''), p.email) = k.livreur
                         and f.refuse_le >= debut::timestamp at time zone 'Africa/Porto-Novo'
                         and f.refuse_le < (fin + 1)::timestamp at time zone 'Africa/Porto-Novo'),
            'incidents', (select count(*) from public.rh_incidents i join public.profils p on p.id = i.livreur_id
                           where coalesce(nullif(p.nom, ''), p.email) = k.livreur
                             and i.cree_le >= debut::timestamp at time zone 'Africa/Porto-Novo'
                             and i.cree_le < (fin + 1)::timestamp at time zone 'Africa/Porto-Novo')) as x
            from (select ligne ->> 'livreur' as livreur, (ligne ->> 'rang')::int as rang,
                         (ligne ->> 'confirme_le')::timestamptz as confirme, (ligne ->> 'vue_le')::timestamptz as vue
                    from l where ligne ->> 'livreur' is not null and etat_commande = 'payee') k
           group by k.livreur) t), '[]'),
      'par_marchand', coalesce((select jsonb_agg(x order by (x ->> 'articles')::int desc) from (
          select jsonb_build_object(
            'marchand', k.marchand,
            'articles', count(*),
            'annules', count(*) filter (where k.rang = 11),
            'non_vus', count(*) filter (where k.rang = 1),
            'contestes', count(*) filter (where k.rang = 10),
            'delai_preparation_h', round(avg(extract(epoch from (k.preparee - k.vue)) / 3600)
                                         filter (where k.preparee is not null and k.vue is not null)::numeric, 1),
            'incidents', (select count(*) from public.rh_incidents i
                           where i.boutique_id = k.boutique_id
                             and i.cree_le >= debut::timestamp at time zone 'Africa/Porto-Novo'
                             and i.cree_le < (fin + 1)::timestamp at time zone 'Africa/Porto-Novo'),
            'reclamations', (select count(*) from public.reclamations rc
                              where rc.boutique_id = k.boutique_id
                                and rc.cree_le >= debut::timestamp at time zone 'Africa/Porto-Novo'
                                and rc.cree_le < (fin + 1)::timestamp at time zone 'Africa/Porto-Novo')) as x
            from (select ligne ->> 'boutique' as marchand, ligne ->> 'boutique_id' as boutique_id,
                         (ligne ->> 'rang')::int as rang, (ligne ->> 'vue_le')::timestamptz as vue,
                         (select min(jj.le) from public.rh_journal_lignes jj
                           where jj.ligne_id = ligne ->> 'id' and jj.quoi = 'etat' and jj.valeur = 'preparee') as preparee
                    from l where etat_commande = 'payee') k
           group by k.marchand, k.boutique_id) t), '[]'),
      'par_zone', coalesce((select jsonb_agg(jsonb_build_object('zone', zone, 'commandes', nb) order by nb desc) from (
          select coalesce(nullif(j #>> '{client,zone}', ''), 'Non reconnue') as zone, count(*) as nb
            from d where j ->> 'etat' = 'payee' group by 1) z), '[]'),
      'heures', coalesce((select jsonb_agg(jsonb_build_object('heure', h, 'commandes', nb) order by h) from (
          select extract(hour from ((j ->> 'cree_le')::timestamptz at time zone 'Africa/Porto-Novo'))::int as h, count(*) as nb
            from d group by 1) hh), '[]'),
      'jours_semaine', coalesce((select jsonb_agg(jsonb_build_object('jour', js, 'commandes', nb) order by js) from (
          select extract(isodow from ((j ->> 'cree_le')::timestamptz at time zone 'Africa/Porto-Novo'))::int as js, count(*) as nb
            from d group by 1) w), '[]'),
      'clients', (select jsonb_build_object(
          'distincts', count(distinct coalesce(c.client_id::text, c.client_tel)),
          'nouveaux', count(distinct coalesce(c.client_id::text, c.client_tel)) filter (where not exists (
              select 1 from public.commandes o
               where coalesce(o.client_id::text, o.client_tel) = coalesce(c.client_id::text, c.client_tel)
                 and o.etat = 'payee' and o.paye_le < debut::timestamp at time zone 'Africa/Porto-Novo')))
          from public.commandes c
         where c.etat = 'payee'
           and c.paye_le >= debut::timestamp at time zone 'Africa/Porto-Novo'
           and c.paye_le < (fin + 1)::timestamp at time zone 'Africa/Porto-Novo'),
      'annulations', coalesce((select jsonb_agg(jsonb_build_object('motif', motif, 'nombre', nb) order by nb desc) from (
          select case when etat_commande = 'annulee' then 'Commande annulée'
                      when etat_commande = 'echouee' then 'Paiement échoué'
                      else 'Article annulé par ' || coalesce(ligne ->> 'boutique', 'la boutique') end as motif,
                 count(distinct commande) as nb
            from l where (ligne ->> 'rang')::int = 11 or etat_commande in ('annulee', 'echouee')
           group by 1) m), '[]')
    ));
end $$;

-- ---------- Agir sur le suivi ----------
create or replace function public.rh_suivi_terrain(ligne text, statut text, motif text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare
  cmd text;
begin
  if public.rh_suivi_acces() is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  select l.commande_id into cmd from public.commande_lignes l where l.id = ligne;
  if cmd is null then
    raise exception 'Article introuvable';
  end if;
  if exists (select 1 from public.rh_suivi_commandes s where s.commande_id = cmd and s.cloturee_le is not null) then
    raise exception 'Cette commande est clôturée : rouvrez-la d''abord';
  end if;
  if coalesce(statut, '') = '' then
    delete from public.rh_suivi_lignes s where s.ligne_id = ligne;
    return;
  end if;
  if statut not in ('recupere', 'echouee', 'retour_en_cours', 'retournee') then
    raise exception 'Statut inconnu';
  end if;
  if statut = 'echouee' and length(btrim(coalesce(motif, ''))) = 0 then
    raise exception 'Dites pourquoi la livraison a échoué';
  end if;
  insert into public.rh_suivi_lignes as s (ligne_id, commande_id, statut, motif, maj_par, maj_le)
  values (ligne, cmd, statut, btrim(coalesce(motif, '')), public.rh_moi(), now())
  on conflict on constraint rh_suivi_lignes_pkey do update
     set statut = excluded.statut, motif = excluded.motif, maj_par = excluded.maj_par, maj_le = now();
  insert into public.rh_journal_lignes (commande_id, ligne_id, quoi, valeur)
  values (cmd, ligne, 'suivi', statut);
end $$;

create or replace function public.rh_suivi_noter(commande text, zone text default null, observations text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.rh_suivi_acces() is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  if not exists (select 1 from public.commandes c where c.id = commande) then
    raise exception 'Commande introuvable';
  end if;
  insert into public.rh_suivi_commandes as s (commande_id, zone, observations, maj_par, maj_le)
  values (commande, btrim(coalesce(zone, '')), btrim(coalesce(observations, '')), public.rh_moi(), now())
  on conflict on constraint rh_suivi_commandes_pkey do update
     set zone = case when rh_suivi_noter.zone is null then s.zone else btrim(rh_suivi_noter.zone) end,
         observations = case when rh_suivi_noter.observations is null then s.observations
                             else btrim(rh_suivi_noter.observations) end,
         maj_par = public.rh_moi(), maj_le = now();
end $$;

create or replace function public.rh_incident_ouvrir(commande text, type text, description text,
                                                     boutique text default null, livreur uuid default null)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  nouveau bigint;
begin
  if public.rh_suivi_acces() is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  if not exists (select 1 from public.commandes c where c.id = commande) then
    raise exception 'Commande introuvable';
  end if;
  if length(btrim(coalesce(description, ''))) = 0 then
    raise exception 'Décrivez l''incident';
  end if;
  insert into public.rh_incidents (commande_id, boutique_id, livreur_id, type, description, cree_par)
  values (commande, nullif(boutique, ''), livreur, type, btrim(description), public.rh_moi())
  returning id into nouveau;
  return nouveau;
end $$;

create or replace function public.rh_incident_resoudre(incident bigint, resolution text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.rh_suivi_acces() is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  if length(btrim(coalesce(resolution, ''))) = 0 then
    raise exception 'Dites comment l''incident a été résolu';
  end if;
  update public.rh_incidents
     set resolu_le = now(), resolu_par = public.rh_moi(), resolution = btrim(rh_incident_resoudre.resolution)
   where id = incident and resolu_le is null;
  if not found then
    raise exception 'Cet incident est déjà résolu';
  end if;
end $$;

/**
 * Clôturer : le suivi est terminé. REFUSÉ tant qu'un incident reste
 * ouvert, qu'un client conteste encore, ou qu'un article n'a pas fini
 * son parcours (confirmé, annulé, échoué ou retourné).
 */
create or replace function public.rh_suivi_cloturer(commande text) returns void
language plpgsql security definer set search_path = public as $$
declare
  d jsonb;
begin
  if public.rh_suivi_acces() is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  select x into d from public.rh_suivi_donnees(null, null, commande) x;
  if d is null then
    raise exception 'Commande introuvable';
  end if;
  if d ->> 'cloturee_le' is not null then
    raise exception 'Cette commande est déjà clôturée';
  end if;
  if (d ->> 'incidents_ouverts')::int > 0 then
    raise exception 'Un incident reste ouvert : résolvez-le avant de clôturer';
  end if;
  if exists (select 1 from jsonb_array_elements(d -> 'lignes') l where (l ->> 'rang')::int = 10) then
    raise exception 'Le client conteste encore la livraison : la réclamation doit être réglée avant de clôturer';
  end if;
  if d ->> 'etat' = 'payee' and exists (select 1 from jsonb_array_elements(d -> 'lignes') l
                                         where (l ->> 'rang')::int not in (8, 9, 11, 13)) then
    raise exception 'Un article n''a pas fini son parcours (livré et confirmé, annulé, échoué ou retourné)';
  end if;
  insert into public.rh_suivi_commandes as s (commande_id, cloturee_le, cloturee_par, maj_par, maj_le)
  values (commande, now(), public.rh_moi(), public.rh_moi(), now())
  on conflict on constraint rh_suivi_commandes_pkey do update
     set cloturee_le = now(), cloturee_par = public.rh_moi(), maj_par = public.rh_moi(), maj_le = now();
  insert into public.rh_journal_lignes (commande_id, quoi, valeur) values (commande, 'suivi', 'cloturee');
end $$;

create or replace function public.rh_suivi_rouvrir(commande text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_admin() then
    raise exception 'Seule l''administration rouvre une commande clôturée';
  end if;
  update public.rh_suivi_commandes set cloturee_le = null, cloturee_par = null, maj_par = public.rh_moi(), maj_le = now()
   where commande_id = commande and cloturee_le is not null;
  if not found then
    raise exception 'Cette commande n''est pas clôturée';
  end if;
  insert into public.rh_journal_lignes (commande_id, quoi, valeur) values (commande, 'suivi', 'rouverte');
end $$;

create or replace function public.rh_suivi_regler(vue_h int, preparation_h int, livraison_h int, confirmation_h int)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_admin() then
    raise exception 'Seule l''administration règle les délais';
  end if;
  update public.rh_reglages_suivi
     set vue_h = rh_suivi_regler.vue_h, preparation_h = rh_suivi_regler.preparation_h,
         livraison_h = rh_suivi_regler.livraison_h, confirmation_h = rh_suivi_regler.confirmation_h
   where id;
end $$;

create or replace function public.rh_zone_ajouter(nom_zone text, commune_zone text default '') returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_admin() then
    raise exception 'Seule l''administration ajoute une zone';
  end if;
  if length(btrim(coalesce(nom_zone, ''))) < 3 then
    raise exception 'Le nom de la zone est trop court';
  end if;
  insert into public.rh_zones (nom, type, commune) values (btrim(nom_zone), 'ajout', btrim(coalesce(commune_zone, '')))
  on conflict do nothing;
end $$;

-- ---------- Les droits ----------
do $$
declare t text;
begin
  foreach t in array array['rh_journal_lignes', 'rh_suivi_lignes', 'rh_suivi_commandes', 'rh_incidents',
                           'rh_reglages_suivi', 'rh_zones'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
    execute format('grant all on table public.%I to service_role', t);
  end loop;
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'rh_suivi_acces()', 'rh_suivi(date, date)', 'rh_suivi_alertes_nb()', 'rh_suivi_commande(text)',
    'rh_suivi_bilan(date, date, text)', 'rh_suivi_terrain(text, text, text)', 'rh_suivi_noter(text, text, text)',
    'rh_incident_ouvrir(text, text, text, text, uuid)', 'rh_incident_resoudre(bigint, text)',
    'rh_suivi_cloturer(text)', 'rh_suivi_rouvrir(text)', 'rh_suivi_regler(int, int, int, int)',
    'rh_zone_ajouter(text, text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
  foreach f in array array[
    'rh_journaliser_ligne()', 'rh_journaliser_commande()', 'rh_suivi_donnees(timestamptz, timestamptz, text)',
    'rh_suivi_sans_montants(jsonb)', 'rh_zone_de(text)', 'rh_statut_ligne(text, timestamptz, text, boolean)',
    'rh_statut_libelle(int)', 'rh_cle(text)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

-- =========================================================
-- BIZZOO Personnel : le menu Paramètres
--
-- Les accès aux menus, profil par profil (rh_acces_menus) : à qui
-- l'administration ouvre le suivi des commandes, chacun des six
-- sous-menus des statistiques, les missions, les rapports, les
-- dépenses, les mails, les discussions et l'annuaire des employés —
-- au responsable seul, ou à tous les membres du profil. Et
-- l'en-tête de l'entreprise imprimé sur les bulletins de paie.
--
-- La base applique elle-même ces accès : les règles RLS et les
-- fonctions des missions, des rapports, des dépenses, des discussions,
-- du suivi et des statistiques consultent rh_acces() et
-- rh_menu_ouvert(). Le premier passage reprend les droits d'avant :
-- rien ne se ferme pour personne ce jour-là.
-- =========================================================

-- ---------- Les accès aux menus, profil par profil ----------
-- Une ligne = un menu ouvert à un profil : à son responsable seul, ou à
-- tous ses membres (le responsable compris). Pas de ligne = menu fermé.
-- L'administration (CEO compris) a toujours tout. Profils, Paie et
-- Paramètres ne s'ouvrent à personne d'autre : ils touchent aux
-- salaires et aux droits. « Employés » s'ouvre en lecture : l'annuaire,
-- sans salaire.
create table if not exists public.rh_acces_menus (
  profil_id    uuid not null references public.rh_profils(id) on delete cascade,
  menu         text not null,
  qui          text not null default 'membres',
  modifie_par  uuid references public.rh_employes(id) on delete set null,
  modifie_le   timestamptz not null default now(),
  primary key (profil_id, menu),
  constraint rh_acces_menus_menu check (menu in ('mails', 'discussions', 'missions', 'rapports',
    'depenses', 'suivi', 'livreurs', 'caisse', 'stats_commandes', 'stats_boutiques', 'stats_produits',
    'stats_livraisons', 'stats_livreurs', 'stats_sav', 'employes')),
  constraint rh_acces_menus_qui check (qui in ('responsable', 'membres'))
);

-- Le premier passage reprend ce qui était vrai jusqu'ici : mails,
-- discussions, missions et rapports pour tous les membres, dépenses
-- pour le responsable, et les rubriques de statistiques et de suivi
-- déjà cochées dans la fiche du profil, pour son responsable.
do $$
begin
  if not exists (select 1 from public.rh_acces_menus) then
    insert into public.rh_acces_menus (profil_id, menu, qui)
    select p.id, d.menu, d.qui
      from public.rh_profils p,
           (values ('mails', 'membres'), ('discussions', 'membres'), ('missions', 'membres'),
                   ('rapports', 'membres'), ('depenses', 'membres')) as d(menu, qui)
    union all
    select p.id, m.menu, 'responsable'
      from public.rh_profils p
      cross join lateral unnest(p.statistiques) as r(rubrique)
      cross join lateral unnest(case r.rubrique
          when 'commandes' then array['stats_commandes', 'stats_boutiques', 'stats_produits']
          when 'livraisons' then array['stats_livraisons', 'stats_livreurs']
          when 'sav' then array['stats_sav']
          when 'suivi' then array['suivi']
          else array[]::text[] end) as m(menu)
    on conflict do nothing;
  end if;
end $$;

/** Un profil qui naît reçoit les accès de base. */
create or replace function public.rh_profil_acces_defaut() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.rh_acces_menus (profil_id, menu, qui)
  values (new.id, 'mails', 'membres'), (new.id, 'discussions', 'membres'),
         (new.id, 'missions', 'membres'), (new.id, 'rapports', 'membres'),
         (new.id, 'depenses', 'membres')
  on conflict do nothing;
  return null;
end $$;
drop trigger if exists rh_profil_acces_defaut on public.rh_profils;
create trigger rh_profil_acces_defaut after insert on public.rh_profils
  for each row execute function public.rh_profil_acces_defaut();

/** Régler les accès d'un profil : { "menu": "membres" | "responsable" | "ferme" }.
    Un menu absent du réglage ne change pas. L'administration seule. */
create or replace function public.rh_regler_acces(cible uuid, choix jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  k text;
  v text;
begin
  if not public.rh_est_admin() then
    raise exception 'Seule l''administration règle les accès aux menus';
  end if;
  if not exists (select 1 from public.rh_profils where id = cible) then
    raise exception 'Profil introuvable';
  end if;
  if jsonb_typeof(choix) is distinct from 'object' then
    raise exception 'Réglage illisible';
  end if;
  for k, v in select e.key, e.value #>> '{}' from jsonb_each(choix) as e loop
    if k not in ('mails', 'discussions', 'missions', 'rapports', 'depenses', 'suivi', 'livreurs', 'caisse',
                 'stats_commandes', 'stats_boutiques', 'stats_produits', 'stats_livraisons',
                 'stats_livreurs', 'stats_sav', 'employes') then
      raise exception 'Menu inconnu : %', k;
    end if;
    if v is null or v = 'ferme' then
      delete from public.rh_acces_menus where profil_id = cible and menu = k;
    elsif v not in ('membres', 'responsable') then
      raise exception 'Réglage inconnu pour le menu %', k;
    else
      insert into public.rh_acces_menus (profil_id, menu, qui, modifie_par, modifie_le)
      values (cible, k, v, public.rh_moi(), now())
      on conflict on constraint rh_acces_menus_pkey do update
        set qui = excluded.qui, modifie_par = excluded.modifie_par, modifie_le = excluded.modifie_le
        where public.rh_acces_menus.qui is distinct from excluded.qui;
    end if;
  end loop;
end $$;

/** Les menus ouverts à mon compte, dans l'ordre du menu. */
create or replace function public.rh_mes_menus() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(x.m order by x.n), '{}')
    from unnest(array['mails', 'discussions', 'missions', 'rapports', 'depenses', 'suivi', 'livreurs', 'caisse',
                      'stats_commandes', 'stats_boutiques', 'stats_produits', 'stats_livraisons',
                      'stats_livreurs', 'stats_sav', 'employes']) with ordinality as x(m, n)
   where public.rh_menu_ouvert(x.m);
$$;

-- ---------- L'entreprise ----------
-- L'en-tête des bulletins de paie. Rien n'est inventé : seuls le nom et
-- le site, déjà imprimés jusqu'ici, sont remplis d'avance.
create table if not exists public.rh_entreprise (
  id              boolean primary key default true check (id),
  raison_sociale  text not null default 'BIZZOO',
  site            text not null default 'bizzoomarket.com',
  adresse         text not null default '',
  telephone       text not null default '',
  email           text not null default '',
  ifu             text not null default '',
  rccm            text not null default '',
  cnss_employeur  text not null default '',
  modifie_par     uuid references public.rh_employes(id) on delete set null,
  modifie_le      timestamptz,
  constraint rh_entreprise_raison check (length(btrim(raison_sociale)) between 1 and 120),
  constraint rh_entreprise_longueurs check (greatest(length(site), length(adresse), length(telephone),
    length(email), length(ifu), length(rccm), length(cnss_employeur)) <= 200)
);
insert into public.rh_entreprise (id) values (true) on conflict (id) do nothing;

create or replace function public.rh_entreprise_trace() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.id := true;
  new.modifie_par := public.rh_moi();
  new.modifie_le := now();
  return new;
end $$;
drop trigger if exists rh_entreprise_trace on public.rh_entreprise;
create trigger rh_entreprise_trace before update on public.rh_entreprise
  for each row execute function public.rh_entreprise_trace();

-- ---------- Les règles d'accès ----------
alter table public.rh_acces_menus enable row level security;
alter table public.rh_entreprise enable row level security;
drop policy if exists "rh acces lecture" on public.rh_acces_menus;
-- Personne n'écrit la table directement : rh_regler_acces le fait.
create policy "rh acces lecture" on public.rh_acces_menus
  for select to authenticated using (public.rh_est_admin() or public.rh_membre_de(profil_id));
drop policy if exists "rh entreprise lecture" on public.rh_entreprise;
drop policy if exists "rh entreprise modification" on public.rh_entreprise;
create policy "rh entreprise lecture" on public.rh_entreprise
  for select to authenticated using (public.rh_moi() is not null);
create policy "rh entreprise modification" on public.rh_entreprise
  for update to authenticated using (public.rh_est_admin()) with check (public.rh_est_admin());

revoke all on table public.rh_acces_menus, public.rh_entreprise from public, anon, authenticated;
grant all on table public.rh_acces_menus, public.rh_entreprise to service_role;
grant select on public.rh_acces_menus, public.rh_entreprise to authenticated;
grant update (raison_sociale, site, adresse, telephone, email, ifu, rccm, cnss_employeur)
  on public.rh_entreprise to authenticated;

do $$
declare f text;
begin
  foreach f in array array['rh_regler_acces(uuid, jsonb)', 'rh_mes_menus()',
                           'rh_acces(uuid, text)', 'rh_menu_ouvert(text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
  foreach f in array array['rh_profil_acces_defaut()', 'rh_entreprise_trace()'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

-- =========================================================
-- BIZZOO Personnel : bloquer, supprimer, et les statistiques internes
--
-- Le CEO et le superadministrateur de BIZZOO bloquent (l'accès est
-- coupé, la paie continue), débloquent et suppriment un employé. Une
-- suppression efface tout s'il n'a ni paie validée ni avance ; sinon
-- la fiche est archivée : identité, n° CNSS et paie gardés, accès,
-- messages, boîte mail et données personnelles effacés. Chaque geste
-- est noté dans rh_journal_employes.
--
-- rh_finances : salaires, dépenses, effectifs, missions et rapports
-- mois par mois pour l'administration ; revenus de BIZZOO et résultat
-- pour le CEO et le superadministrateur seuls.
-- =========================================================

-- ---------- Les états « bloqué » et « supprimé » ----------
-- Bloqué : l'accès est coupé (rh_moi() ne le reconnaît plus), la paie
-- continue, le blocage se lève. Supprimé : la fiche sort des listes,
-- l'accès et les données personnelles s'effacent ; ne restent que
-- l'identité (nom, matricule, n° CNSS) et la paie déjà validée.
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'rh_employes_etat_check'
               and pg_get_constraintdef(oid) not like '%supprime%') then
    alter table public.rh_employes drop constraint rh_employes_etat_check;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_employes_etat_check') then
    alter table public.rh_employes add constraint rh_employes_etat_check
      check (etat in ('en_attente', 'actif', 'refuse', 'sorti', 'bloque', 'supprime'));
  end if;
end $$;

-- Ce qui a été bloqué, débloqué, supprimé : par qui, quand, pourquoi.
-- Sans clé étrangère : la ligne survit à l'employé effacé.
create table if not exists public.rh_journal_employes (
  id          bigint generated always as identity primary key,
  employe_id  uuid not null,
  matricule   text not null default '',
  nom         text not null default '',
  action      text not null check (action in ('bloque', 'debloque', 'supprime', 'efface')),
  motif       text not null default '',
  par_compte  uuid,
  par_nom     text not null default '',
  le          timestamptz not null default now()
);
create index if not exists rh_journal_employes_employe on public.rh_journal_employes (employe_id, id);

/** Le CEO et le superadministrateur de BIZZOO, seuls. */
create or replace function public.rh_peut_bloquer() returns boolean
language sql stable security definer set search_path = public as $$
  select public.rh_est_ceo() or public.est_super();
$$;

/** Bloquer (ou débloquer) l'accès d'un employé en poste. */
create or replace function public.rh_bloquer_employe(qui uuid, bloquer boolean, motif text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare
  e public.rh_employes;
  auteur text;
begin
  if not public.rh_peut_bloquer() then
    raise exception 'Seuls le CEO et le superadministrateur bloquent un employé';
  end if;
  select * into e from public.rh_employes where id = qui for update;
  if not found then
    raise exception 'Employé introuvable';
  end if;
  if e.ceo then
    raise exception 'Le CEO ne se bloque pas';
  end if;
  if e.compte_id is not null and e.compte_id = auth.uid() then
    raise exception 'Vous ne vous bloquez pas vous-même';
  end if;
  if bloquer and e.etat <> 'actif' then
    raise exception 'Seul un employé en poste se bloque';
  end if;
  if not bloquer and e.etat <> 'bloque' then
    raise exception 'Cet employé n''est pas bloqué';
  end if;
  if bloquer and length(btrim(coalesce(motif, ''))) = 0 then
    raise exception 'Dites pourquoi vous bloquez cet employé';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_employes set etat = case when bloquer then 'bloque' else 'actif' end where id = qui;
  perform set_config('rh.decision', '', true);
  select coalesce(btrim(x.prenoms || ' ' || x.nom), '') into auteur
    from public.rh_employes x where x.compte_id = auth.uid();
  insert into public.rh_journal_employes (employe_id, matricule, nom, action, motif, par_compte, par_nom)
  values (e.id, coalesce(e.matricule, ''), btrim(e.prenoms || ' ' || e.nom),
          case when bloquer then 'bloque' else 'debloque' end, btrim(coalesce(motif, '')),
          auth.uid(), coalesce(auteur, 'Superadministrateur'));
end $$;

/** Supprimer un employé. Sans paie validée ni avance : tout s'efface.
    Avec : la fiche est archivée (« supprime ») — identité et paie
    gardées pour la comptabilité et la CNSS, tout le reste effacé. */
create or replace function public.rh_supprimer_employe(qui uuid, motif text default '')
returns text
language plpgsql security definer set search_path = public as $$
declare
  e public.rh_employes;
  auteur text;
  garder boolean;
begin
  if not public.rh_peut_bloquer() then
    raise exception 'Seuls le CEO et le superadministrateur suppriment un employé';
  end if;
  select * into e from public.rh_employes where id = qui for update;
  if not found or e.etat = 'supprime' then
    raise exception 'Employé introuvable';
  end if;
  if e.ceo then
    raise exception 'Le CEO ne se supprime pas';
  end if;
  if e.compte_id is not null and e.compte_id = auth.uid() then
    raise exception 'Vous ne vous supprimez pas vous-même';
  end if;
  if length(btrim(coalesce(motif, ''))) = 0 then
    raise exception 'Dites pourquoi vous supprimez cet employé';
  end if;
  select coalesce(btrim(x.prenoms || ' ' || x.nom), '') into auteur
    from public.rh_employes x where x.compte_id = auth.uid();
  garder := exists (select 1 from public.rh_fiches_paie where employe_id = qui and statut <> 'calculee')
         or exists (select 1 from public.rh_avances where employe_id = qui);

  insert into public.rh_journal_employes (employe_id, matricule, nom, action, motif, par_compte, par_nom)
  values (e.id, coalesce(e.matricule, ''), btrim(e.prenoms || ' ' || e.nom),
          case when garder then 'supprime' else 'efface' end, btrim(motif),
          auth.uid(), coalesce(auteur, 'Superadministrateur'));

  update public.rh_profils set responsable_id = null where responsable_id = qui;
  if not garder then
    -- Ses messages, ses lectures, sa boîte mail et ses brouillons de
    -- paie partent avec lui (clés « on delete cascade »).
    delete from public.rh_employes where id = qui;
    return 'efface';
  end if;

  delete from public.rh_messages where auteur_id = qui or destinataire_id = qui;
  delete from public.rh_lectures where employe_id = qui;
  delete from public.rh_boites_mail where employe_id = qui;
  delete from public.rh_fiches_paie where employe_id = qui and statut = 'calculee';
  perform set_config('rh.decision', 'oui', true);
  update public.rh_employes
     set etat = 'supprime', compte_id = null, email_pro = null, telephone = '', email_perso = '',
         adresse = '', date_naissance = null, compte_paiement = '', infos = '', profil_id = null,
         administration = false, peut_decaisser = false,
         date_sortie = coalesce(date_sortie, (now() at time zone 'Africa/Porto-Novo')::date),
         motif_refus = btrim(motif)
   where id = qui;
  perform set_config('rh.decision', '', true);
  return 'archive';
end $$;

-- ---------- Les statistiques internes ----------
/** Salaires, dépenses, effectifs, missions et rapports, mois par mois ;
    et, pour le CEO et le superadministrateur seuls, les revenus de
    BIZZOO et le résultat. Les mois entiers qui couvrent la période. */
create or replace function public.rh_finances(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  m1 date := date_trunc('month', coalesce(depuis, aujourdhui - 330))::date;
  m2 date := date_trunc('month', coalesce(jusqu, aujourdhui))::date;
  fin date;
  t1 timestamptz;
  t2 timestamptz;
  v_admin boolean := public.rh_est_admin() or public.est_super();
  v_revenus boolean := public.rh_est_ceo() or public.est_super();
  salaires jsonb;
  depenses jsonb;
  effectifs jsonb;
  activite jsonb;
  revenus jsonb := null;
begin
  if not v_admin then
    raise exception 'Les statistiques internes sont réservées à l''administration';
  end if;
  if m2 < m1 then
    raise exception 'La fin de la période précède son début';
  end if;
  if m2 - m1 > 1100 then
    raise exception 'Choisissez une période de trois ans au plus';
  end if;
  fin := (m2 + interval '1 month - 1 day')::date;
  t1 := m1::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (fin + 1)::timestamp at time zone 'Africa/Porto-Novo';

  -- ---------- Les salaires (fiches validées ou payées) ----------
  with les_mois as (select generate_series(m1, m2, interval '1 month')::date as mois),
  f as (select * from public.rh_fiches_paie where mois between m1 and m2),
  pm as (
    select lm.mois,
           count(f.id) filter (where f.statut <> 'calculee') as fiches,
           coalesce(sum(f.brut) filter (where f.statut <> 'calculee'), 0) as brut,
           coalesce(sum(f.cotisations_salariales) filter (where f.statut <> 'calculee'), 0) as cotisations,
           coalesce(sum(f.impot) filter (where f.statut <> 'calculee'), 0) as impot,
           coalesce(sum(f.avances) filter (where f.statut <> 'calculee'), 0) as avances,
           coalesce(sum(f.retenues) filter (where f.statut <> 'calculee'), 0) as retenues,
           coalesce(sum(f.net) filter (where f.statut <> 'calculee'), 0) as net,
           coalesce(sum(f.charges_patronales) filter (where f.statut <> 'calculee'), 0) as charges,
           coalesce(sum(f.net) filter (where f.statut = 'payee'), 0) as paye,
           coalesce(sum(f.net) filter (where f.statut = 'validee'), 0) as a_payer,
           count(f.id) filter (where f.statut = 'calculee') as provisoires,
           coalesce(sum(f.net) filter (where f.statut = 'calculee'), 0) as net_provisoire
      from les_mois lm left join f on f.mois = lm.mois
     group by lm.mois)
  select jsonb_build_object(
    'par_mois', (select coalesce(jsonb_agg(jsonb_build_object(
        'mois', mois, 'fiches', fiches, 'brut', brut, 'cotisations', cotisations, 'impot', impot,
        'avances', avances, 'retenues', retenues, 'net', net, 'charges', charges, 'cout', brut + charges,
        'paye', paye, 'a_payer', a_payer, 'provisoires', provisoires, 'net_provisoire', net_provisoire)
        order by mois), '[]') from pm),
    'par_profil', (select coalesce(jsonb_agg(jsonb_build_object(
        'profil', x.profil, 'effectif', x.effectif, 'fiches', x.fiches, 'brut', x.brut, 'net', x.net, 'cout', x.cout)
        order by x.cout desc), '[]')
       from (select coalesce(nullif(f.employe ->> 'profil', ''), 'Sans profil') as profil,
                    count(distinct f.employe_id) as effectif, count(*) as fiches,
                    sum(f.brut) as brut, sum(f.net) as net, sum(f.brut + f.charges_patronales) as cout
               from f where f.statut <> 'calculee' group by 1) x),
    'par_statut', (select coalesce(jsonb_agg(jsonb_build_object(
        'statut', x.statut, 'effectif', x.effectif, 'brut', x.brut, 'cout', x.cout) order by x.statut), '[]')
       from (select coalesce(nullif(f.employe ->> 'statut', ''), 'employe') as statut,
                    count(distinct f.employe_id) as effectif, sum(f.brut) as brut,
                    sum(f.brut + f.charges_patronales) as cout
               from f where f.statut <> 'calculee' group by 1) x),
    'avances_accordees', (select coalesce(sum(a.montant), 0) from public.rh_avances a
                           where a.statut <> 'annulee' and a.date_avance between m1 and fin),
    'avances_nombre', (select count(*) from public.rh_avances a
                        where a.statut <> 'annulee' and a.date_avance between m1 and fin),
    'avances_encours', (select coalesce(sum(a.montant - coalesce((
                            select sum(fa.montant) from public.rh_fiche_avances fa
                              join public.rh_fiches_paie fp on fp.id = fa.fiche_id
                             where fa.avance_id = a.id and fp.statut <> 'calculee'), 0)), 0)
                          from public.rh_avances a where a.statut = 'active')
  ) into salaires;

  -- ---------- Les dépenses ----------
  with les_mois as (select generate_series(m1, m2, interval '1 month')::date as mois),
  d as (
    select dp.*, coalesce(p.nom, '—') as profil,
           date_trunc('month', dp.cree_le at time zone 'Africa/Porto-Novo')::date as mois_demande,
           date_trunc('month', dp.decaisse_le at time zone 'Africa/Porto-Novo')::date as mois_decaisse
      from public.rh_depenses dp left join public.rh_profils p on p.id = dp.profil_id)
  select jsonb_build_object(
    'par_mois', (select coalesce(jsonb_agg(jsonb_build_object(
        'mois', lm.mois,
        'demandees', (select count(*) from d where d.mois_demande = lm.mois),
        'montant_demande', (select coalesce(sum(montant), 0) from d where d.mois_demande = lm.mois),
        'approuvees', (select coalesce(sum(montant), 0) from d
                        where d.mois_demande = lm.mois and d.statut in ('approuvee', 'decaissee')),
        'refusees', (select count(*) from d where d.mois_demande = lm.mois and d.statut = 'refusee'),
        'decaissees', (select count(*) from d where d.mois_decaisse = lm.mois and d.statut = 'decaissee'),
        'montant_decaisse', (select coalesce(sum(montant), 0) from d
                              where d.mois_decaisse = lm.mois and d.statut = 'decaissee'))
        order by lm.mois), '[]') from les_mois lm),
    'par_profil', (select coalesce(jsonb_agg(jsonb_build_object(
        'profil', x.profil, 'nombre', x.nombre, 'montant', x.montant) order by x.montant desc), '[]')
       from (select d.profil, count(*) as nombre, sum(d.montant) as montant from d
              where d.statut = 'decaissee' and d.decaisse_le >= t1 and d.decaisse_le < t2 group by 1) x),
    'plus_grosses', (select coalesce(jsonb_agg(jsonb_build_object(
        'numero', x.numero, 'objet', x.objet, 'profil', x.profil, 'montant', x.montant, 'le', x.decaisse_le)
        order by x.montant desc), '[]')
       from (select * from d where d.statut = 'decaissee' and d.decaisse_le >= t1 and d.decaisse_le < t2
              order by d.montant desc limit 10) x),
    'en_attente', (select jsonb_build_object('nombre', count(*), 'montant', coalesce(sum(montant), 0))
                     from d where d.statut in ('demandee', 'validee_responsable')),
    'a_decaisser', (select jsonb_build_object('nombre', count(*), 'montant', coalesce(sum(montant), 0))
                      from d where d.statut = 'approuvee'),
    'delai_decision_jours', (select round(avg(extract(epoch from (d.decision_le - d.cree_le)) / 86400)::numeric, 1)
                               from d where d.decision_le is not null and d.cree_le >= t1 and d.cree_le < t2)
  ) into depenses;

  -- ---------- Les effectifs (aujourd'hui, et les mouvements) ----------
  with en_poste as (select * from public.rh_employes where etat in ('actif', 'bloque'))
  select jsonb_build_object(
    'par_etat', (select coalesce(jsonb_object_agg(etat, n), '{}')
                   from (select etat, count(*) as n from public.rh_employes group by etat) x),
    'en_poste', (select count(*) from en_poste),
    'par_statut', (select coalesce(jsonb_object_agg(statut, n), '{}')
                     from (select statut, count(*) as n from en_poste group by statut) x),
    'par_sexe', (select coalesce(jsonb_object_agg(coalesce(sexe, 'NR'), n), '{}')
                   from (select sexe, count(*) as n from en_poste group by sexe) x),
    'par_profil', (select coalesce(jsonb_agg(jsonb_build_object('profil', x.profil, 'effectif', x.n,
                       'masse_base', x.masse) order by x.n desc), '[]')
                     from (select coalesce(p.nom, 'Sans profil') as profil, count(*) as n,
                                  sum(e.salaire_base) as masse
                             from en_poste e left join public.rh_profils p on p.id = e.profil_id group by 1) x),
    'par_niveau', (select coalesce(jsonb_object_agg(niveau, n), '{}')
                     from (select coalesce(nullif(niveau_etude, ''), 'Non renseigné') as niveau, count(*) as n
                             from en_poste group by 1) x),
    'age_moyen', (select round(avg(extract(year from age(aujourdhui, date_naissance)))::numeric, 1)
                    from en_poste where date_naissance is not null),
    'anciennete_moyenne_mois', (select round(avg((aujourdhui - date_embauche) / 30.44)::numeric, 1) from en_poste),
    'masse_base', (select coalesce(sum(salaire_base), 0) from en_poste),
    'salaire_base_moyen', (select coalesce(round(avg(salaire_base)), 0) from en_poste),
    'mouvements', (select coalesce(jsonb_agg(jsonb_build_object(
        'mois', lm.mois,
        'embauches', (select count(*) from public.rh_employes e
                       where e.etat in ('actif', 'bloque', 'sorti', 'supprime')
                         and date_trunc('month', e.date_embauche)::date = lm.mois),
        'sorties', (select count(*) from public.rh_employes e
                     where e.date_sortie is not null and date_trunc('month', e.date_sortie)::date = lm.mois))
        order by lm.mois), '[]')
       from (select generate_series(m1, m2, interval '1 month')::date as mois) lm)
  ) into effectifs;

  -- ---------- Missions et rapports ----------
  with mi as (select m.*, coalesce(p.nom, '—') as profil from public.rh_missions m
                left join public.rh_profils p on p.id = m.profil_id
               where m.cree_le >= t1 and m.cree_le < t2),
  ra as (select * from public.rh_rapports where cree_le >= t1 and cree_le < t2)
  select jsonb_build_object(
    'missions', (select count(*) from mi),
    'missions_par_statut', (select coalesce(jsonb_object_agg(statut, n), '{}')
                              from (select statut, count(*) as n from mi group by statut) x),
    'cloturees_a_temps', (select count(*) from mi where statut = 'cloturee'
                            and (rapport_le at time zone 'Africa/Porto-Novo')::date <= echeance),
    'cloturees_en_retard', (select count(*) from mi where statut = 'cloturee'
                              and (rapport_le at time zone 'Africa/Porto-Novo')::date > echeance),
    'en_retard_aujourdhui', (select count(*) from public.rh_missions
                               where statut in ('acceptee', 'a_reprendre') and echeance < aujourdhui),
    'delai_reponse_heures', (select round(avg(extract(epoch from (reponse_le - cree_le)) / 3600)::numeric, 1)
                               from mi where reponse_le is not null),
    'missions_par_profil', (select coalesce(jsonb_agg(jsonb_build_object(
        'profil', x.profil, 'creees', x.creees, 'cloturees', x.cloturees, 'refusees', x.refusees,
        'en_cours', x.en_cours) order by x.creees desc), '[]')
       from (select profil, count(*) as creees,
                    count(*) filter (where statut = 'cloturee') as cloturees,
                    count(*) filter (where statut = 'refusee') as refusees,
                    count(*) filter (where statut in ('proposee', 'acceptee', 'rapport_remis', 'a_reprendre')) as en_cours
               from mi group by profil) x),
    'rapports', (select count(*) from ra where statut <> 'brouillon'),
    'rapports_par_statut', (select coalesce(jsonb_object_agg(statut, n), '{}')
                              from (select statut, count(*) as n from ra group by statut) x),
    'delai_validation_jours', (select round(avg(extract(epoch from (decision_le - publie_le)) / 86400)::numeric, 1)
                                 from ra where decision_le is not null and publie_le is not null)
  ) into activite;

  -- ---------- Les revenus de BIZZOO et le résultat (CEO, superadministrateur) ----------
  if v_revenus then
    with les_mois as (select generate_series(m1, m2, interval '1 month')::date as mois),
    c as (select co.*, date_trunc('month', co.paye_le at time zone 'Africa/Porto-Novo')::date as mois
            from public.commandes co
           where co.etat = 'payee' and co.paye_le >= t1 and co.paye_le < t2),
    cm as (select c.mois, count(*) as commandes, coalesce(sum(c.total), 0) as encaisse,
                  coalesce(sum(c.frais_livraison), 0) as frais, coalesce(sum(c.remise), 0) as remises
             from c group by c.mois),
    lm2 as (select c.mois,
                   coalesce(sum(greatest(0, l.prix - l.prix_bizzoo) * l.quantite), 0) as marge,
                   coalesce(sum(l.prix_bizzoo * l.quantite), 0) as reverse
              from public.commande_lignes l join c on c.id = l.commande_id
             where l.etat <> 'annulee' group by c.mois),
    g as (select date_trunc('month', credite_le at time zone 'Africa/Porto-Novo')::date as mois,
                 coalesce(sum(montant), 0) as gains
            from public.gains_livreurs where credite_le >= t1 and credite_le < t2 group by 1),
    s as (select mois, sum(brut + charges_patronales) as cout from public.rh_fiches_paie
           where statut <> 'calculee' and mois between m1 and m2 group by mois),
    dp as (select date_trunc('month', decaisse_le at time zone 'Africa/Porto-Novo')::date as mois,
                  sum(montant) as montant
             from public.rh_depenses where statut = 'decaissee' and decaisse_le >= t1 and decaisse_le < t2
            group by 1),
    pm as (select lm.mois,
                  coalesce(cm.commandes, 0) as commandes, coalesce(cm.encaisse, 0) as encaisse,
                  coalesce(cm.frais, 0) as frais, coalesce(cm.remises, 0) as remises,
                  coalesce(lm2.marge, 0) as marge, coalesce(lm2.reverse, 0) as reverse,
                  coalesce(g.gains, 0) as gains, coalesce(s.cout, 0) as cout_salaires, coalesce(dp.montant, 0) as montant_depenses
             from les_mois lm
             left join cm on cm.mois = lm.mois
             left join lm2 on lm2.mois = lm.mois
             left join g on g.mois = lm.mois
             left join s on s.mois = lm.mois
             left join dp on dp.mois = lm.mois)
    select coalesce(jsonb_agg(jsonb_build_object(
        'mois', mois, 'commandes', commandes, 'encaisse', encaisse, 'reverse_boutiques', reverse,
        'marge', marge, 'frais_livraison', frais, 'remises', remises, 'gains_livreurs', gains,
        'revenus', marge + frais - remises - gains,
        'salaires', cout_salaires, 'depenses', montant_depenses,
        'resultat', marge + frais - remises - gains - cout_salaires - montant_depenses) order by mois), '[]')
      into revenus from pm;
  end if;

  return jsonb_build_object(
    'periode', jsonb_build_object('depuis', m1, 'jusqu', fin),
    'droits', jsonb_build_object('revenus', v_revenus),
    'salaires', salaires, 'depenses', depenses, 'effectifs', effectifs, 'activite', activite,
    'revenus', revenus);
end $$;

-- ---------- Les droits ----------
alter table public.rh_journal_employes enable row level security;
drop policy if exists "rh journal employes lecture" on public.rh_journal_employes;
create policy "rh journal employes lecture" on public.rh_journal_employes
  for select to authenticated using (public.rh_est_admin() or public.est_super());
revoke all on table public.rh_journal_employes from public, anon, authenticated;
grant all on table public.rh_journal_employes to service_role;
grant select on public.rh_journal_employes to authenticated;

do $$
declare f text;
begin
  foreach f in array array['rh_peut_bloquer()', 'rh_bloquer_employe(uuid, boolean, text)',
                           'rh_supprimer_employe(uuid, text)', 'rh_finances(date, date)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
end $$;

-- =========================================================
-- BIZZOO Personnel : photos, vidéos et audio dans les discussions,
-- et tout message effacé au bout de 7 jours
--
-- Un message porte au plus une pièce, rangée dans le seau PRIVÉ
-- « rh-pieces », dans le dossier de son auteur. Elle se lit avec un
-- lien signé, que seule obtient une personne qui voit le message.
--
-- Chaque heure, pg_cron efface les messages de plus de 7 jours
-- (rh_purger_messages), puis appelle la fonction rh-menage, qui efface
-- du stockage les fichiers que plus aucun message ne cite.
-- =========================================================

-- ---------- Le seau des pièces jointes ----------
-- PRIVÉ : un fichier ne se lit qu'avec un lien signé, que seule obtient
-- une personne qui voit le message qui le porte.
insert into storage.buckets (id, name, public)
values ('rh-pieces', 'rh-pieces', false)
on conflict (id) do nothing;
update storage.buckets
   set public = false,
       file_size_limit = 52428800,   -- 50 Mo : une vidéo de téléphone d'une minute ou deux
       allowed_mime_types = array[
         'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic', 'image/heif',
         'video/mp4', 'video/webm', 'video/quicktime', 'video/3gpp',
         'audio/mpeg', 'audio/mp4', 'audio/aac', 'audio/ogg', 'audio/webm', 'audio/wav',
         'audio/x-wav', 'audio/x-m4a', 'audio/3gpp', 'audio/amr']
 where id = 'rh-pieces';

-- ---------- Le message porte au plus une pièce ----------
alter table public.rh_messages add column if not exists piece text;
alter table public.rh_messages add column if not exists piece_type text;
alter table public.rh_messages add column if not exists piece_nom text not null default '';
alter table public.rh_messages add column if not exists piece_taille bigint;
create index if not exists rh_messages_piece on public.rh_messages (piece) where piece is not null;
create index if not exists rh_messages_age on public.rh_messages (cree_le);

do $$
begin
  -- Un message sans texte est permis s'il porte une pièce.
  if exists (select 1 from pg_constraint where conname = 'rh_messages_texte_check') then
    alter table public.rh_messages drop constraint rh_messages_texte_check;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_messages_contenu') then
    alter table public.rh_messages add constraint rh_messages_contenu
      check (length(texte) <= 4000 and (piece is not null or length(btrim(texte)) >= 1));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_messages_piece_type') then
    alter table public.rh_messages add constraint rh_messages_piece_type
      check ((piece is null) = (piece_type is null)
             and (piece_type is null or piece_type in ('image', 'video', 'audio')));
  end if;
end $$;

/** La pièce d'un message : un fichier que SON AUTEUR a déposé (son
    dossier), présent dans le seau, cité par un seul message. Le type
    et le poids se lisent dans le stockage, jamais dans la requête.
    Après rh_messages_verrous (ordre alphabétique) : l'auteur est posé. */
create or replace function public.rh_message_piece() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  o storage.objects;
  mime text;
begin
  if new.piece is null then
    new.piece_type := null;
    new.piece_nom := '';
    new.piece_taille := null;
    return new;
  end if;
  select * into o from storage.objects
   where bucket_id = 'rh-pieces' and name = new.piece;
  if not found or split_part(new.piece, '/', 1) is distinct from new.auteur_id::text then
    raise exception 'Pièce jointe introuvable : envoyez-la de nouveau';
  end if;
  if exists (select 1 from public.rh_messages m where m.piece = new.piece) then
    raise exception 'Cette pièce jointe est déjà envoyée';
  end if;
  mime := lower(coalesce(o.metadata ->> 'mimetype', ''));
  new.piece_type := case
    when mime like 'image/%' then 'image'
    when mime like 'video/%' then 'video'
    when mime like 'audio/%' then 'audio'
  end;
  if new.piece_type is null then
    raise exception 'Seules les photos, les vidéos et les enregistrements audio s''envoient';
  end if;
  new.piece_taille := nullif(o.metadata ->> 'size', '')::bigint;
  new.piece_nom := left(btrim(coalesce(new.piece_nom, '')), 120);
  return new;
end $$;
drop trigger if exists rh_messages_verrous_piece on public.rh_messages;
create trigger rh_messages_verrous_piece
  before insert on public.rh_messages
  for each row execute function public.rh_message_piece();

-- ---------- Qui dépose, qui lit ----------
-- Chacun dépose dans SON dossier (son identifiant d'employé), s'il a
-- les discussions. On lit un fichier si l'on voit le message qui le
-- porte — les règles de rh_messages s'appliquent dans la sous-requête —
-- ou si c'est le sien. On retire le sien tant qu'aucun message ne le cite.
drop policy if exists "rh pieces depot" on storage.objects;
drop policy if exists "rh pieces lecture" on storage.objects;
drop policy if exists "rh pieces retrait" on storage.objects;
create policy "rh pieces depot" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'rh-pieces'
              and split_part(name, '/', 1) = public.rh_moi()::text
              and public.rh_menu_ouvert('discussions'));
create policy "rh pieces lecture" on storage.objects
  for select to authenticated
  using (bucket_id = 'rh-pieces'
         and (split_part(name, '/', 1) = public.rh_moi()::text
              or exists (select 1 from public.rh_messages m where m.piece = objects.name)));
create policy "rh pieces retrait" on storage.objects
  for delete to authenticated
  using (bucket_id = 'rh-pieces'
         and split_part(name, '/', 1) = public.rh_moi()::text
         and not exists (select 1 from public.rh_messages m where m.piece = objects.name));

-- ---------- Tout s'efface au bout de 7 jours ----------
/** Les messages de plus de 7 jours : texte et pièce partent ensemble. */
create or replace function public.rh_purger_messages() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  delete from public.rh_messages where cree_le < now() - interval '7 days';
  get diagnostics n = row_count;
  return n;
end $$;

/** Les fichiers à effacer du stockage : plus cités par aucun message
    (message effacé, ou envoi abandonné depuis plus d'une heure). */
create or replace function public.rh_pieces_perimees() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(o.name order by o.created_at), '{}')
    from storage.objects o
   where o.bucket_id = 'rh-pieces'
     and o.created_at < now() - interval '1 hour'
     and not exists (select 1 from public.rh_messages m where m.piece = o.name);
$$;

revoke all on function public.rh_message_piece() from public, anon, authenticated;
revoke all on function public.rh_purger_messages() from public, anon, authenticated;
revoke all on function public.rh_pieces_perimees() from public, anon, authenticated;
grant execute on function public.rh_purger_messages() to service_role;
grant execute on function public.rh_pieces_perimees() to service_role;

-- pg_cron, chaque heure : la base efface les messages elle-même ; la
-- fonction rh-menage efface ensuite les fichiers (par pg_net). Sans
-- pg_net, les messages partent quand même ; les fichiers attendent.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('rh-messages-7-jours', '7 * * * *', 'select public.rh_purger_messages()');
    if exists (select 1 from pg_available_extensions where name = 'pg_net') then
      create extension if not exists pg_net;
      perform cron.schedule('rh-pieces-menage', '12 * * * *',
        'select net.http_post(''https://rrwzegmrmvvkmzfoiitb.supabase.co/functions/v1/rh-menage'', ''{}''::jsonb, ''{}''::jsonb, ''{"Content-Type": "application/json"}''::jsonb, 60000)');
    end if;
  end if;
exception when others then
  raise notice 'Ménage des discussions non programmé (%)', sqlerrm;
end $$;

-- =========================================================
-- Localiser un livreur
--
-- BIZZOO Admin : pendant ses courses, le téléphone du livreur envoie sa
-- position (service Android, même application fermée ; la page, sinon),
-- avec un jeton de suivi qui ne permet que cela (position_en_course).
-- Il s'arrête de lui-même quand le livreur n'a plus de course.
--
-- BIZZOO Personnel : le menu « Localiser un livreur » (clé « livreurs »,
-- réglable dans Paramètres) lit les positions et les courses en cours
-- par rh_localiser_livreurs, avec la distance jusqu'au client.
-- =========================================================

-- ---------- Le livreur en course envoie sa position ----------
-- Le téléphone du livreur l'envoie toutes les 20 secondes environ, même
-- application fermée (service Android de BIZZOO Admin), tant qu'il a une
-- course en cours. Ce service ne tient pas la session du compte : une
-- session se renouvelle par un jeton à usage unique, et deux
-- renouvellements concurrents (la page et le service) déconnecteraient
-- le livreur. Il reçoit donc un JETON DE SUIVI : 64 caractères tirés au
-- hasard, gardés seulement en empreinte (sha256), valables 16 heures, qui
-- ne permettent QU'UNE chose : écrire la position de CE livreur.
create table if not exists public.suivis_livreurs (
  profil_id   uuid primary key references public.profils(id) on delete cascade,
  jeton_hash  text not null,
  expire_le   timestamptz not null,
  cree_le     timestamptz not null default now()
);
alter table public.suivis_livreurs enable row level security;
-- Aucune règle : personne ne lit ni n'écrit la table, sinon ces fonctions.
revoke all on table public.suivis_livreurs from public, anon, authenticated;
grant all on table public.suivis_livreurs to service_role;

/** Ce livreur a-t-il une course en cours ? Une ligne qu'on lui a
    confiée, d'une commande payée, pas encore remise ni annulée. */
create or replace function public.livreur_en_course(qui uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
     where l.livreur_id = qui and c.etat = 'payee'
       and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison'));
$$;

/** Le jeton de suivi du livreur connecté (un nouveau à chaque appel :
    l'ancien ne vaut plus rien). */
create or replace function public.ouvrir_suivi_livreur() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  jeton text;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Seul un livreur ouvre un suivi de position.' using errcode = '42501';
  end if;
  jeton := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into public.suivis_livreurs (profil_id, jeton_hash, expire_le, cree_le)
  values (moi, encode(sha256(convert_to(jeton, 'UTF8')), 'hex'), now() + interval '16 hours', now())
  on conflict (profil_id) do update
     set jeton_hash = excluded.jeton_hash, expire_le = excluded.expire_le, cree_le = now();
  return jsonb_build_object('jeton', jeton, 'en_course', public.livreur_en_course(moi),
                            'expire_le', now() + interval '16 hours');
end $$;

/** La position d'un livreur en course, par son jeton de suivi. Répond
    « continuer : false » quand il n'a plus de course : son téléphone
    s'arrête alors de la suivre. */
create or replace function public.position_en_course(jeton text, lat double precision,
  lng double precision, precision_m int default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  qui uuid;
  la double precision := public.coord_valable(lat, 90);
  lo double precision := public.coord_valable(lng, 180);
  derniere timestamptz;
begin
  select s.profil_id into qui from public.suivis_livreurs s
   where s.jeton_hash = encode(sha256(convert_to(coalesce(jeton, ''), 'UTF8')), 'hex')
     and s.expire_le > now();
  if qui is null then
    raise exception 'Suivi expiré : ouvrez BIZZOO Admin pour le reprendre.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profils p where p.id = qui and p.actif and p.role = 'livreur') then
    delete from public.suivis_livreurs where profil_id = qui;
    return jsonb_build_object('continuer', false);
  end if;
  if not public.livreur_en_course(qui) then
    delete from public.suivis_livreurs where profil_id = qui;
    return jsonb_build_object('continuer', false);
  end if;
  if la is null or lo is null or (la = 0 and lo = 0) then
    return jsonb_build_object('continuer', true);
  end if;
  -- Pas plus d'une écriture toutes les 5 secondes.
  select enregistre_le into derniere from public.positions_livreurs where profil_id = qui;
  if derniere is null or derniere < now() - interval '5 seconds' then
    insert into public.positions_livreurs (profil_id, latitude, longitude, precision_m, adresse, enregistre_le)
    values (qui, la, lo, greatest(0, precision_m), '', now())
    on conflict (profil_id) do update
       set latitude = excluded.latitude, longitude = excluded.longitude,
           precision_m = excluded.precision_m, enregistre_le = now();
  end if;
  return jsonb_build_object('continuer', true);
end $$;

revoke all on function public.livreur_en_course(uuid) from public, anon, authenticated;
revoke all on function public.ouvrir_suivi_livreur() from public, anon;
grant execute on function public.ouvrir_suivi_livreur() to authenticated;
-- Sans session : le jeton fait foi.
revoke all on function public.position_en_course(text, double precision, double precision, int) from public;
grant execute on function public.position_en_course(text, double precision, double precision, int)
  to anon, authenticated;

-- ---------- BIZZOO Personnel : le menu « Localiser un livreur » ----------
do $$
begin
  if to_regclass('public.rh_acces_menus') is null then
    return;  -- personnel-parametres.sql posera la table, « livreurs » compris
  end if;
  if exists (select 1 from pg_constraint where conname = 'rh_acces_menus_menu'
               and pg_get_constraintdef(oid) not like '%''livreurs''%') then
    alter table public.rh_acces_menus drop constraint rh_acces_menus_menu;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_acces_menus_menu') then
    alter table public.rh_acces_menus add constraint rh_acces_menus_menu check (menu in ('mails',
      'discussions', 'missions', 'rapports', 'depenses', 'suivi', 'livreurs', 'stats_commandes',
      'stats_boutiques', 'stats_produits', 'stats_livraisons', 'stats_livreurs', 'stats_sav', 'employes'));
  end if;
end $$;

/** Les livreurs sur la carte : leur dernière position, et pour chacun
    ses courses en cours, avec le point du client quand il l'a donné et
    la distance qui les sépare — à vol d'oiseau, multipliée par le
    coefficient de route de la livraison au kilomètre (« environ »).
    Sans aucun montant. */
create or replace function public.rh_localiser_livreurs() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  coef numeric := coalesce((select livraison_coef from public.paiement where id = 1), 1.3);
begin
  if not public.rh_menu_ouvert('livreurs') then
    raise exception 'Votre compte n''a pas accès à la localisation des livreurs';
  end if;
  return jsonb_build_object(
    'coef', coef,
    'maintenant', now(),
    'livreurs', (select coalesce(jsonb_agg(x.l order by (x.l ->> 'en_course')::boolean desc, x.l ->> 'nom'), '[]')
      from (
        select jsonb_build_object(
          'id', p.id,
          'nom', coalesce(nullif(btrim(p.nom), ''), p.email, 'Livreur'),
          'tel', coalesce(p.tel, ''),
          'vehicule', coalesce(p.vehicule, 'moto'),
          'boutique', (select b.nom from public.boutiques b where b.id = p.boutique_id),
          'position', case when pl.profil_id is null then null else jsonb_build_object(
              'latitude', pl.latitude, 'longitude', pl.longitude, 'precision', pl.precision_m,
              'adresse', pl.adresse, 'le', pl.enregistre_le) end,
          'en_course', public.livreur_en_course(p.id),
          'suivi_actif', exists (select 1 from public.suivis_livreurs s
                                  where s.profil_id = p.id and s.expire_le > now()),
          'courses', (select coalesce(jsonb_agg(jsonb_build_object(
              'commande', k.commande_id, 'numero', k.numero, 'client', k.client_nom,
              'adresse', k.client_adresse, 'etat', k.etat, 'boutique', k.boutique,
              'retrait', case when k.b_lat is null then null
                              else jsonb_build_object('latitude', k.b_lat, 'longitude', k.b_lng) end,
              'destination', case when k.d_lat is null then null
                                  else jsonb_build_object('latitude', k.d_lat, 'longitude', k.d_lng) end,
              'distance_km', case when k.d_lat is null or pl.profil_id is null then null else round((
                  2 * 6371 * asin(least(1, sqrt(
                    sin(radians(k.d_lat - pl.latitude) / 2) ^ 2
                    + cos(radians(pl.latitude)) * cos(radians(k.d_lat))
                      * sin(radians(k.d_lng - pl.longitude) / 2) ^ 2))) * coef)::numeric, 1) end)
              order by k.numero), '[]')
            from (
              select c.id as commande_id, c.numero, c.client_nom, c.client_adresse,
                     (array['nouvelle', 'vue', 'preparee', 'en_livraison'])[
                       min(array_position(array['nouvelle', 'vue', 'preparee', 'en_livraison'], l.etat))] as etat,
                     max(b.nom) as boutique, max(b.latitude) as b_lat, max(b.longitude) as b_lng,
                     public.coord_valable((c.livraison #>> '{destination,latitude}')::double precision, 90) as d_lat,
                     public.coord_valable((c.livraison #>> '{destination,longitude}')::double precision, 180) as d_lng
                from public.commande_lignes l
                join public.commandes c on c.id = l.commande_id
                left join public.boutiques b on b.id = l.boutique_id
               where l.livreur_id = p.id and c.etat = 'payee'
                 and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')
               group by c.id, c.numero, c.client_nom, c.client_adresse, c.livraison) k)
        ) as l
          from public.profils p
          left join public.positions_livreurs pl on pl.profil_id = p.id
         where p.role = 'livreur' and p.actif
      ) x));
end $$;
revoke all on function public.rh_localiser_livreurs() from public, anon;
grant execute on function public.rh_localiser_livreurs() to authenticated, service_role;

-- =========================================================
-- BIZZOO Personnel : le circuit des dépenses
--
-- Tout employé demande une dépense (motif, montant). Son responsable
-- de profil la valide, puis le CEO l'approuve, puis l'employé habilité
-- la décaisse (jamais sa propre demande). Statuts : « demandee » (chez
-- le responsable), « validee_responsable » (chez le CEO), « approuvee »
-- (à décaisser), « decaissee », « refusee », « annulee ». Sans
-- responsable (pas de profil, profil sans responsable, ou demandeur
-- responsable lui-même), la demande va droit au CEO.
-- =========================================================

-- ---------- La table : un statut de plus, trois colonnes, un profil facultatif ----------
alter table public.rh_depenses add column if not exists responsable_par uuid;
alter table public.rh_depenses add column if not exists responsable_le timestamptz;
alter table public.rh_depenses add column if not exists motif_responsable text not null default '';
alter table public.rh_depenses alter column profil_id drop not null;
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'rh_depenses_statut_check'
               and pg_get_constraintdef(oid) not like '%validee_responsable%') then
    alter table public.rh_depenses drop constraint rh_depenses_statut_check;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_depenses_statut_check') then
    alter table public.rh_depenses add constraint rh_depenses_statut_check
      check (statut in ('demandee', 'validee_responsable', 'approuvee', 'refusee', 'decaissee', 'annulee'));
  end if;
  -- Les dépenses ne sont plus réservées au responsable : tout employé
  -- demande, à qui Paramètres ouvre le menu (tous les membres d'office).
  if to_regclass('public.rh_acces_menus') is not null then
    alter table public.rh_acces_menus drop constraint if exists rh_acces_depenses_responsable;
    update public.rh_acces_menus set qui = 'membres' where menu = 'depenses' and qui = 'responsable';
  end if;
end $$;

/** Le responsable du profil valide (ou refuse, avec un motif) une
    demande de l'un de ses membres ; elle part alors chez le CEO. */
create or replace function public.rh_valider_depense(depense uuid, valider boolean, motif text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare d public.rh_depenses;
begin
  select * into d from public.rh_depenses where id = depense for update;
  if not found or d.profil_id is null or not public.rh_responsable_de(d.profil_id) then
    raise exception 'Seul le responsable du profil valide cette demande';
  end if;
  if d.statut <> 'demandee' then
    raise exception 'Cette demande n''attend pas la validation du responsable';
  end if;
  if not valider and length(btrim(coalesce(motif, ''))) = 0 then
    raise exception 'Dites pourquoi vous refusez la dépense';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_depenses
     set statut = case when valider then 'validee_responsable' else 'refusee' end,
         responsable_par = public.rh_moi(), responsable_le = now(),
         motif_responsable = btrim(coalesce(motif, ''))
   where id = depense;
  perform set_config('rh.decision', '', true);
end $$;
revoke all on function public.rh_valider_depense(uuid, boolean, text) from public, anon;
grant execute on function public.rh_valider_depense(uuid, boolean, text) to authenticated, service_role;

-- =========================================================
-- BIZZOO Personnel : la caisse
--
-- La caisse de la maison : quatre compartiments (espèces, MTN Mobile
-- Money, Moov Money, Celtiis Cash), dont la somme fait le solde. Un
-- gestionnaire, désigné par le CEO, la tient : lui seul décaisse les
-- dépenses approuvées et paie les salaires, en répartissant s'il le faut
-- entre les compartiments (20 000 en espèces + 30 000 sur MTN). Les
-- apports viennent du CEO ou d'une autre source nommée. Aucun
-- compartiment ne passe sous zéro ; aucun mouvement ne s'efface : le CEO
-- corrige par un ajustement motivé. La voient : le CEO, le gestionnaire,
-- le superadministrateur, et les profils à qui Paramètres l'ouvre.
-- =========================================================

-- ---------- La caisse et son gestionnaire ----------
create table if not exists public.rh_caisse (
  id              boolean primary key default true check (id),
  gestionnaire_id uuid references public.rh_employes(id) on delete set null,
  designe_par     uuid,
  designe_le      timestamptz
);
insert into public.rh_caisse (id) values (true) on conflict (id) do nothing;

-- ---------- Les mouvements : on n'y efface rien, on n'y corrige rien ----------
-- Une erreur se rattrape par un ajustement du CEO, avec son motif.
create table if not exists public.rh_caisse_mouvements (
  id            bigint generated always as identity primary key,
  le            timestamptz not null default now(),
  compte        text not null check (compte in ('especes', 'mtn', 'moov', 'celtiis')),
  sens          text not null check (sens in ('entree', 'sortie')),
  nature        text not null check (nature in ('apport_ceo', 'apport_autre', 'depense', 'salaire',
                                                 'transfert', 'frais', 'ajustement')),
  montant       bigint not null check (montant > 0),
  libelle       text not null default '',
  reference     text not null default '',
  depense_id    uuid references public.rh_depenses(id) on delete set null,
  fiche_id      uuid references public.rh_fiches_paie(id) on delete set null,
  par           uuid,
  solde_compte  bigint not null,   -- le compartiment, après ce mouvement
  solde_total   bigint not null    -- toute la caisse, après ce mouvement
);
create index if not exists rh_caisse_mouvements_le on public.rh_caisse_mouvements (le);

create or replace function public.rh_caisse_figee() returns trigger
language plpgsql as $$
begin
  raise exception 'Un mouvement de caisse ne se modifie ni ne s''efface : le CEO corrige par un ajustement';
end $$;
drop trigger if exists rh_caisse_figee on public.rh_caisse_mouvements;
create trigger rh_caisse_figee before update or delete on public.rh_caisse_mouvements
  for each row execute function public.rh_caisse_figee();

/** Qui voit la caisse : « gestion » (son gestionnaire), « ceo »,
    « super » (le superadministrateur de BIZZOO), « consultation »
    (un profil à qui Paramètres l'ouvre), ou rien. L'administration
    n'y entre pas d'office. */
create or replace function public.rh_caisse_acces() returns text
language plpgsql stable security definer set search_path = public as $$
declare
  v_moi uuid := public.rh_moi();
begin
  if v_moi is not null and exists (select 1 from public.rh_caisse where gestionnaire_id = v_moi) then
    return 'gestion';
  end if;
  if public.rh_est_ceo() then
    return 'ceo';
  end if;
  if public.est_super() then
    return 'super';
  end if;
  if v_moi is not null and exists (
       select 1 from public.rh_acces_menus a join public.rh_profils p on p.id = a.profil_id
        where a.menu = 'caisse'
          and (p.responsable_id = v_moi or (a.qui = 'membres' and p.id = public.rh_mon_profil()))) then
    return 'consultation';
  end if;
  return null;
end $$;

/** Un mouvement, la caisse verrouillée : le solde ne passe jamais sous
    zéro, compartiment par compartiment. Interne. */
create or replace function public.rh_caisse_mouvoir(p_compte text, p_sens text, p_nature text,
  p_montant bigint, p_libelle text, p_reference text default '', p_depense uuid default null,
  p_fiche uuid default null)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  dispo bigint;
  total bigint;
  nouveau bigint;
  ligne bigint;
begin
  if p_montant is null or p_montant <= 0 then
    raise exception 'Le montant doit être positif';
  end if;
  perform 1 from public.rh_caisse where id for update;
  select coalesce(sum(case when sens = 'entree' then montant else -montant end), 0) into dispo
    from public.rh_caisse_mouvements where compte = p_compte;
  select coalesce(sum(case when sens = 'entree' then montant else -montant end), 0) into total
    from public.rh_caisse_mouvements;
  if p_sens = 'sortie' and dispo < p_montant then
    raise exception 'Solde insuffisant en % : % FCFA disponibles, % FCFA demandés',
      case p_compte when 'especes' then 'espèces' when 'mtn' then 'MTN Mobile Money'
                    when 'moov' then 'Moov Money' else 'Celtiis Cash' end,
      replace(to_char(dispo, 'FM999G999G999G990'), ',', ' '), replace(to_char(p_montant, 'FM999G999G999G990'), ',', ' ');
  end if;
  nouveau := dispo + case when p_sens = 'entree' then p_montant else -p_montant end;
  insert into public.rh_caisse_mouvements (compte, sens, nature, montant, libelle, reference,
                                           depense_id, fiche_id, par, solde_compte, solde_total)
  values (p_compte, p_sens, p_nature, p_montant, left(btrim(coalesce(p_libelle, '')), 300),
          left(btrim(coalesce(p_reference, '')), 120), p_depense, p_fiche, public.rh_moi(), nouveau,
          total + case when p_sens = 'entree' then p_montant else -p_montant end)
  returning id into ligne;
  return ligne;
end $$;

/** La répartition d'un paiement entre les compartiments : { "especes":
    20000, "mtn": 30000 }. Sa somme doit faire le montant, exactement. */
create or replace function public.rh_caisse_repartition(brut jsonb, montant bigint) returns jsonb
language plpgsql immutable as $$
declare
  k text;
  v jsonb;
  somme bigint := 0;
  propre jsonb := '{}'::jsonb;
begin
  if brut is null or jsonb_typeof(brut) <> 'object' then
    raise exception 'Indiquez d''où sort l''argent : espèces, MTN, Moov ou Celtiis';
  end if;
  for k, v in select e.key, e.value from jsonb_each(brut) as e loop
    if k not in ('especes', 'mtn', 'moov', 'celtiis') then
      raise exception 'Compartiment de caisse inconnu : %', k;
    end if;
    if jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric <> round((v #>> '{}')::numeric) or (v #>> '{}')::numeric < 0 then
      raise exception 'Un montant en francs entiers, positif, pour %', k;
    end if;
    if (v #>> '{}')::bigint > 0 then
      propre := propre || jsonb_build_object(k, (v #>> '{}')::bigint);
      somme := somme + (v #>> '{}')::bigint;
    end if;
  end loop;
  if somme <> montant then
    raise exception 'La répartition fait % FCFA, pour un montant de % FCFA : elle doit tomber juste',
      replace(to_char(somme, 'FM999G999G999G990'), ',', ' '), replace(to_char(montant, 'FM999G999G999G990'), ',', ' ');
  end if;
  return propre;
end $$;

-- ---------- Ce qui sort : les dépenses et les salaires ----------
-- Un déclencheur, pour qu'AUCUN décaissement n'échappe à la caisse : il
-- lit la répartition posée par rh_decaisser / rh_payer (« rh.repartition »),
-- ou, à défaut, met tout le montant sur le compartiment choisi.
create or replace function public.rh_depense_sort_de_caisse() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  rep jsonb;
  k text;
  v jsonb;
begin
  if new.statut <> 'decaissee' or old.statut = 'decaissee' then
    return null;
  end if;
  rep := nullif(current_setting('rh.repartition', true), '')::jsonb;
  if rep is null then
    if new.mode_decaissement not in ('especes', 'mtn', 'moov', 'celtiis') then
      raise exception 'Une dépense sort de la caisse : espèces, MTN, Moov ou Celtiis';
    end if;
    rep := jsonb_build_object(new.mode_decaissement, new.montant);
  end if;
  rep := public.rh_caisse_repartition(rep, new.montant);
  for k, v in select e.key, e.value from jsonb_each(rep) as e order by e.key loop
    perform public.rh_caisse_mouvoir(k, 'sortie', 'depense', (v #>> '{}')::bigint,
      'D-' || lpad(new.numero::text, 4, '0') || ' · ' || new.objet, new.reference, new.id, null);
  end loop;
  return null;
end $$;
drop trigger if exists rh_depense_sort_de_caisse on public.rh_depenses;
create trigger rh_depense_sort_de_caisse after update of statut on public.rh_depenses
  for each row execute function public.rh_depense_sort_de_caisse();

create or replace function public.rh_salaire_sort_de_caisse() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  rep jsonb;
  k text;
  v jsonb;
begin
  if new.statut <> 'payee' or old.statut = 'payee' then
    return null;
  end if;
  /* Versée sur le solde de l'employé : rien ne sort encore de la caisse.
     L'argent en sortira au retrait, s'il le retire à la caisse. */
  if new.mode_paiement = 'solde' then
    return null;
  end if;
  rep := nullif(current_setting('rh.repartition', true), '')::jsonb;
  if rep is null then
    if new.mode_paiement not in ('especes', 'mtn', 'moov', 'celtiis') then
      raise exception 'Un salaire sort de la caisse : espèces, MTN, Moov ou Celtiis';
    end if;
    rep := jsonb_build_object(new.mode_paiement, new.net);
  end if;
  rep := public.rh_caisse_repartition(rep, new.net);
  for k, v in select e.key, e.value from jsonb_each(rep) as e order by e.key loop
    perform public.rh_caisse_mouvoir(k, 'sortie', 'salaire', (v #>> '{}')::bigint,
      'Salaire de ' || to_char(new.mois, 'MM/YYYY'), new.reference, null, new.id);
  end loop;
  return null;
end $$;
drop trigger if exists rh_salaire_sort_de_caisse on public.rh_fiches_paie;
create trigger rh_salaire_sort_de_caisse after update of statut on public.rh_fiches_paie
  for each row execute function public.rh_salaire_sort_de_caisse();

/** Décaisser une dépense, réparti entre les compartiments. */
create or replace function public.rh_decaisser(depense uuid, repartition jsonb, reference text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare
  d public.rh_depenses;
  rep jsonb;
begin
  select * into d from public.rh_depenses where id = depense;
  if not found then
    raise exception 'Dépense introuvable';
  end if;
  rep := public.rh_caisse_repartition(repartition, d.montant);
  perform set_config('rh.repartition', rep::text, true);
  perform public.rh_decaisser_depense(depense,
    case when (select count(*) from jsonb_object_keys(rep)) = 1 then (select k from jsonb_object_keys(rep) k) else 'mixte' end,
    reference);
  perform set_config('rh.repartition', '', true);
end $$;

/** Payer une fiche de paie, répartie entre les compartiments. */
create or replace function public.rh_payer(fiche uuid, repartition jsonb, reference text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Un salaire ne se paie plus ici : la fiche validée est versée le 10 sur le solde de l''employé, qui le retire depuis son compte (Mobile Money ou caisse)';
end $$;

-- ---------- Ce qui entre, ce qui se déplace, ce qui se corrige ----------
/** Désigner le gestionnaire de la caisse : le CEO seul. */
create or replace function public.rh_designer_gestionnaire_caisse(qui uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO désigne le gestionnaire de la caisse';
  end if;
  if not exists (select 1 from public.rh_employes where id = qui and etat = 'actif') then
    raise exception 'Le gestionnaire doit être un employé en poste';
  end if;
  update public.rh_caisse set gestionnaire_id = qui, designe_par = public.rh_moi(), designe_le = now() where id;
end $$;

/** Un apport : du CEO, ou d'une autre source qu'on nomme. Le gestionnaire
    ou le CEO l'enregistre. */
create or replace function public.rh_caisse_apport(compte text, montant bigint, provenance text,
  libelle text default '', reference text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.rh_caisse_acces() not in ('gestion', 'ceo') or public.rh_caisse_acces() is null then
    raise exception 'Seuls le gestionnaire de la caisse et le CEO enregistrent un apport';
  end if;
  if compte not in ('especes', 'mtn', 'moov', 'celtiis') then
    raise exception 'Compartiment de caisse inconnu';
  end if;
  if provenance not in ('ceo', 'autre') then
    raise exception 'D''où vient l''argent : du CEO, ou d''une autre source ?';
  end if;
  if provenance = 'autre' and length(btrim(coalesce(libelle, ''))) < 3 then
    raise exception 'Nommez la source de cet apport';
  end if;
  perform public.rh_caisse_mouvoir(compte, 'entree',
    case when provenance = 'ceo' then 'apport_ceo' else 'apport_autre' end, montant,
    coalesce(nullif(btrim(libelle), ''), 'Apport du CEO'), reference);
end $$;

/** Déplacer de l'argent d'un compartiment à l'autre (retrait Mobile
    Money en espèces, dépôt…), avec les frais de l'opérateur s'il y en a. */
create or replace function public.rh_caisse_transfert(de text, vers text, montant bigint,
  frais bigint default 0, libelle text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare
  nom text := case de when 'especes' then 'Espèces' when 'mtn' then 'MTN' when 'moov' then 'Moov' else 'Celtiis' end
              || ' → ' || case vers when 'especes' then 'Espèces' when 'mtn' then 'MTN' when 'moov' then 'Moov' else 'Celtiis' end;
begin
  if public.rh_caisse_acces() is distinct from 'gestion' then
    raise exception 'Seul le gestionnaire de la caisse déplace de l''argent entre les compartiments';
  end if;
  if de = vers or de not in ('especes', 'mtn', 'moov', 'celtiis') or vers not in ('especes', 'mtn', 'moov', 'celtiis') then
    raise exception 'Choisissez deux compartiments différents';
  end if;
  if coalesce(frais, 0) < 0 then
    raise exception 'Les frais ne sont pas négatifs';
  end if;
  perform public.rh_caisse_mouvoir(de, 'sortie', 'transfert', montant, nom || coalesce(' · ' || nullif(btrim(libelle), ''), ''));
  perform public.rh_caisse_mouvoir(vers, 'entree', 'transfert', montant, nom || coalesce(' · ' || nullif(btrim(libelle), ''), ''));
  if coalesce(frais, 0) > 0 then
    perform public.rh_caisse_mouvoir(de, 'sortie', 'frais', frais, 'Frais de l''opérateur · ' || nom);
  end if;
end $$;

/** Corriger une erreur ou un écart constaté au comptage : le CEO seul,
    avec un motif. Positif : de l'argent en plus ; négatif : en moins. */
create or replace function public.rh_caisse_ajustement(compte text, montant bigint, motif text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO ajuste la caisse';
  end if;
  if compte not in ('especes', 'mtn', 'moov', 'celtiis') then
    raise exception 'Compartiment de caisse inconnu';
  end if;
  if coalesce(montant, 0) = 0 then
    raise exception 'Un ajustement de zéro ne change rien';
  end if;
  if length(btrim(coalesce(motif, ''))) < 3 then
    raise exception 'Dites pourquoi vous ajustez la caisse';
  end if;
  perform public.rh_caisse_mouvoir(compte, case when montant > 0 then 'entree' else 'sortie' end,
    'ajustement', abs(montant), btrim(motif));
end $$;

/** La caisse : le solde à l'instant, par compartiment, et les mouvements
    d'une période. En consultation, un salaire ne dit pas de qui il est. */
create or replace function public.rh_caisse(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  acces text := public.rh_caisse_acces();
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  debut date := coalesce(depuis, date_trunc('month', aujourdhui)::date);
  fin date := coalesce(jusqu, aujourdhui);
  t1 timestamptz;
  t2 timestamptz;
begin
  if acces is null then
    raise exception 'Votre compte n''a pas accès à la caisse';
  end if;
  if fin < debut then
    raise exception 'La fin de la période précède son début';
  end if;
  t1 := debut::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (fin + 1)::timestamp at time zone 'Africa/Porto-Novo';
  return jsonb_build_object(
    'acces', acces,
    'periode', jsonb_build_object('depuis', debut, 'jusqu', fin),
    'gestionnaire', (select jsonb_build_object('id', e.id, 'nom', btrim(e.prenoms || ' ' || e.nom), 'le', c.designe_le)
                       from public.rh_caisse c join public.rh_employes e on e.id = c.gestionnaire_id),
    'comptes', (select jsonb_agg(jsonb_build_object(
        'compte', k.compte,
        'solde', coalesce((select sum(case when m.sens = 'entree' then m.montant else -m.montant end)
                             from public.rh_caisse_mouvements m where m.compte = k.compte), 0),
        'debut', coalesce((select sum(case when m.sens = 'entree' then m.montant else -m.montant end)
                             from public.rh_caisse_mouvements m where m.compte = k.compte and m.le < t1), 0),
        'entrees', coalesce((select sum(m.montant) from public.rh_caisse_mouvements m
                              where m.compte = k.compte and m.sens = 'entree' and m.le >= t1 and m.le < t2), 0),
        'sorties', coalesce((select sum(m.montant) from public.rh_caisse_mouvements m
                              where m.compte = k.compte and m.sens = 'sortie' and m.le >= t1 and m.le < t2), 0))
        order by k.n)
      from unnest(array['especes', 'mtn', 'moov', 'celtiis']) with ordinality as k(compte, n)),
    'mouvements', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', m.id, 'le', m.le, 'compte', m.compte, 'sens', m.sens, 'nature', m.nature, 'montant', m.montant,
        'libelle', case when acces = 'consultation' and m.nature in ('salaire', 'pret')
                          then split_part(m.libelle, ' · ', 1)
                        when m.nature = 'salaire' and m.fiche_id is not null
                          then m.libelle || coalesce(' · ' || (select f.employe ->> 'prenoms' || ' ' || (f.employe ->> 'nom')
                                                                 from public.rh_fiches_paie f where f.id = m.fiche_id), '')
                        else m.libelle end,
        'reference', m.reference, 'depense_id', m.depense_id,
        'par', (select btrim(e.prenoms || ' ' || e.nom) from public.rh_employes e where e.id = m.par),
        'solde_compte', m.solde_compte, 'solde_total', m.solde_total) order by m.id desc), '[]')
      from public.rh_caisse_mouvements m where m.le >= t1 and m.le < t2));
end $$;

-- ---------- Les droits ----------
alter table public.rh_caisse enable row level security;
alter table public.rh_caisse_mouvements enable row level security;
-- Aucune règle : tout passe par les fonctions ci-dessus.
revoke all on table public.rh_caisse, public.rh_caisse_mouvements from public, anon, authenticated;
grant all on table public.rh_caisse, public.rh_caisse_mouvements to service_role;

do $$
declare f text;
begin
  foreach f in array array['rh_caisse_acces()', 'rh_decaisser(uuid, jsonb, text)', 'rh_payer(uuid, jsonb, text)',
                           'rh_designer_gestionnaire_caisse(uuid)', 'rh_caisse_apport(text, bigint, text, text, text)',
                           'rh_caisse_transfert(text, text, bigint, bigint, text)', 'rh_caisse_ajustement(text, bigint, text)',
                           'rh_caisse(date, date)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
  foreach f in array array['rh_caisse_mouvoir(text, text, text, bigint, text, text, uuid, uuid)',
                           'rh_caisse_repartition(jsonb, bigint)', 'rh_depense_sort_de_caisse()',
                           'rh_salaire_sort_de_caisse()', 'rh_caisse_figee()'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

-- ---------- Le menu « caisse » dans Paramètres (consultation) ----------
do $$
begin
  if to_regclass('public.rh_acces_menus') is null then
    return;
  end if;
  if exists (select 1 from pg_constraint where conname = 'rh_acces_menus_menu'
               and pg_get_constraintdef(oid) not like '%''caisse''%') then
    alter table public.rh_acces_menus drop constraint rh_acces_menus_menu;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_acces_menus_menu') then
    alter table public.rh_acces_menus add constraint rh_acces_menus_menu check (menu in ('mails',
      'discussions', 'missions', 'rapports', 'depenses', 'suivi', 'livreurs', 'caisse', 'stats_commandes',
      'stats_boutiques', 'stats_produits', 'stats_livraisons', 'stats_livreurs', 'stats_sav', 'employes'));
  end if;
end $$;

-- Les décaissements d'avant la caisse gardent leur mode ; la colonne
-- accepte désormais les compartiments.
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'rh_depenses_mode_decaissement_check'
               and pg_get_constraintdef(oid) not like '%celtiis%') then
    alter table public.rh_depenses drop constraint rh_depenses_mode_decaissement_check;
    alter table public.rh_depenses add constraint rh_depenses_mode_decaissement_check
      check (mode_decaissement in ('especes', 'mtn', 'moov', 'celtiis', 'mixte', 'virement', 'mobile_money', 'cheque'));
  end if;
end $$;

-- =========================================================
-- BIZZOO Personnel : la fiche complète et la connexion par numéro
--
-- La fiche reçoit ce que le fichier du personnel de BIZZOO donne en plus :
-- contact pro, équipement, langue, situation, moto ; le sexe peut rester
-- vide jusqu'à ce que l'employé le dise. Ethnie et religion vont dans
-- une table à part, réservée au CEO et au superadministrateur.
--
-- Chaque employé se connecte avec son numéro (code par SMS) : le compte
-- rejoint la fiche qui porte ce numéro (rh_rattacher_par_telephone).
-- Le superadministrateur modifie une fiche comme le CEO ; l'employé
-- complète lui-même ce qui le regarde (adresse, e-mail, sexe, date de
-- naissance, langue, situation, moto) — pas son numéro.
-- =========================================================

-- ---------- La fiche s'enrichit ----------
alter table public.rh_employes alter column sexe drop not null;
alter table public.rh_employes add column if not exists telephone_pro text not null default '';
alter table public.rh_employes add column if not exists equipement text not null default '';
alter table public.rh_employes add column if not exists langue text not null default '';
alter table public.rh_employes add column if not exists marie text not null default '';
alter table public.rh_employes add column if not exists moto boolean;
-- Le téléphone sert à se connecter : un seul employé en poste par numéro.
create unique index if not exists rh_employes_telephone on public.rh_employes (telephone)
  where telephone <> '' and etat not in ('sorti', 'refuse', 'supprime');

-- ---------- Ce qui ne regarde que le CEO ----------
-- Données sensibles (Code du numérique) : à part, lisibles et
-- modifiables par le CEO et le superadministrateur seuls.
create table if not exists public.rh_employes_sensibles (
  employe_id  uuid primary key references public.rh_employes(id) on delete cascade,
  ethnie      text not null default '',
  religion    text not null default ''
);
alter table public.rh_employes_sensibles enable row level security;
drop policy if exists "rh sensibles ceo" on public.rh_employes_sensibles;
create policy "rh sensibles ceo" on public.rh_employes_sensibles
  for all to authenticated
  using (public.rh_est_ceo() or public.est_super())
  with check (public.rh_est_ceo() or public.est_super());
revoke all on table public.rh_employes_sensibles from public, anon, authenticated;
grant all on table public.rh_employes_sensibles to service_role;
grant select, insert, update, delete on public.rh_employes_sensibles to authenticated;

-- ---------- Se connecter par son numéro ----------
/** Ce numéro est-il celui d'un employé en poste ? Demandé AVANT
    d'envoyer le code par SMS : on n'envoie pas de SMS, et l'on ne crée
    pas de compte, pour un numéro qui n'est pas celui d'un employé. */
create or replace function public.rh_telephone_employe(tel text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where etat = 'actif' and telephone <> ''
                    and telephone = right(regexp_replace(coalesce(tel, ''), '[^0-9]', '', 'g'), 10));
$$;

/** Le compte connecté par son numéro rejoint la fiche de l'employé qui
    porte ce numéro. Une fiche déjà reliée à un AUTRE compte ne change
    pas de main : l'employé se connecte alors comme avant. */
create or replace function public.rh_rattacher_par_telephone() returns uuid
language plpgsql security definer set search_path = public as $$
declare
  numero text;
  e public.rh_employes;
begin
  /* Un compte ouvert par BIZZOO avec le mot de passe de départ n'est
     relié à sa fiche qu'une fois ce mot de passe changé (rh_activer_compte). */
  if to_regclass('public.rh_comptes_a_activer') is not null
     and exists (select 1 from public.rh_comptes_a_activer a where a.compte_id = auth.uid()) then
    raise exception 'Choisissez d''abord votre mot de passe' using errcode = 'P0001', hint = 'ACTIVATION';
  end if;
  select right(regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g'), 10) into numero
    from auth.users u where u.id = auth.uid();
  if coalesce(numero, '') = '' then
    raise exception 'Ce compte n''a pas de numéro de téléphone';
  end if;
  select * into e from public.rh_employes where etat = 'actif' and telephone = numero for update;
  if not found then
    raise exception 'Ce numéro n''est celui d''aucun employé en poste de BIZZOO';
  end if;
  if e.compte_id = auth.uid() then
    return e.id;
  end if;
  if e.compte_id is not null then
    raise exception 'Votre fiche est déjà reliée à un autre compte : connectez-vous avec votre adresse e-mail';
  end if;
  if exists (select 1 from public.rh_employes where compte_id = auth.uid()) then
    raise exception 'Ce compte est déjà relié à une autre fiche d''employé';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_employes set compte_id = auth.uid() where id = e.id;
  perform set_config('rh.decision', '', true);
  -- Un compte né de cette connexion n'est pas un compte de boutique.
  delete from public.profils p where p.id = auth.uid() and not p.actif and p.role = 'moderateur';
  return e.id;
end $$;

revoke all on function public.rh_telephone_employe(text) from public;
grant execute on function public.rh_telephone_employe(text) to anon, authenticated, service_role;
revoke all on function public.rh_rattacher_par_telephone() from public, anon;
grant execute on function public.rh_rattacher_par_telephone() to authenticated, service_role;

-- =========================================================
-- BIZZOO Personnel : le solde de chaque employé, les prêts, les retraits
--
-- Le calendrier de la paie :
--   - le 5, la base calcule seule les fiches du mois écoulé, qui
--     attendent la validation du CEO ;
--   - le 10, chaque fiche validée est versée sur le SOLDE de son
--     employé (une fiche validée après le 10 l'est aussitôt) ;
--   - l'employé retire ensuite son argent quand il veut, tout ou partie :
--     par Mobile Money (FeexPay, reversement validé par le gestionnaire
--     de la caisse) ou à la caisse.
--
-- Ce que verse la fiche : salaire + primes − retenues − prêt.
-- Le CEO accorde une prime ou impose une retenue sur la prochaine paie
-- d'un employé. L'employé demande un prêt : le CEO le valide, la caisse
-- le décaisse, et la paie suivante le reprend en une fois.
--
-- Rien ne s'efface : le solde est la somme de mouvements figés, et un
-- retrait refusé ou échoué revient sur le solde par un mouvement de
-- retour. Le jeton FeexPay ne vit que dans les secrets de Supabase : la
-- base ne fait que noter ce que la fonction Edge « rh-reversement » a
-- constaté chez FeexPay.
-- =========================================================

-- ---------- Le solde : des mouvements, jamais corrigés ----------
create table if not exists public.rh_solde_mouvements (
  id          bigint generated always as identity primary key,
  le          timestamptz not null default now(),
  employe_id  uuid not null references public.rh_employes(id) on delete cascade,
  sens        text not null check (sens in ('credit', 'debit')),
  nature      text not null check (nature in ('salaire', 'retrait', 'retour')),
  montant     bigint not null check (montant > 0),
  libelle     text not null default '',
  fiche_id    uuid references public.rh_fiches_paie(id) on delete set null,
  retrait_id  uuid,
  par         uuid,
  solde       bigint not null   -- le solde de l'employé, après ce mouvement
);
create index if not exists rh_solde_mouvements_employe on public.rh_solde_mouvements (employe_id, id);
-- Une fiche ne se verse qu'une fois.
create unique index if not exists rh_solde_mouvements_fiche on public.rh_solde_mouvements (fiche_id)
  where nature = 'salaire' and fiche_id is not null;

create or replace function public.rh_solde_fige() returns trigger
language plpgsql as $$
begin
  raise exception 'Un mouvement du solde ne se modifie ni ne s''efface';
end $$;
drop trigger if exists rh_solde_fige on public.rh_solde_mouvements;
create trigger rh_solde_fige before update or delete on public.rh_solde_mouvements
  for each row execute function public.rh_solde_fige();

-- ---------- Les retraits ----------
--   demande   : l'employé l'a demandé ; le montant a quitté son solde ;
--   envoi     : le gestionnaire a lancé le reversement, FeexPay n'a pas encore répondu ;
--   envoye    : FeexPay l'a accepté (référence notée), le versement est en cours ;
--   incertain : on ne sait pas si l'argent est parti (coupure, panne) :
--               le CEO tranche après avoir regardé le tableau de bord FeexPay ;
--   paye      : versé (FeexPay l'a confirmé, ou la caisse l'a remis) ;
--   echoue / refuse / annule : rien n'est parti, le montant est revenu sur le solde.
create table if not exists public.rh_retraits (
  id           uuid primary key default gen_random_uuid(),
  numero       bigint generated always as identity,
  employe_id   uuid not null references public.rh_employes(id) on delete cascade,
  montant      bigint not null check (montant > 0),
  moyen        text not null check (moyen in ('feexpay', 'caisse')),
  reseau       text check (reseau in ('mtn', 'moov', 'celtiis')),
  telephone    text not null default '',
  statut       text not null default 'demande'
               check (statut in ('demande', 'envoi', 'envoye', 'incertain', 'paye', 'echoue', 'refuse', 'annule')),
  motif        text not null default '',
  reference    text not null default '',
  demande_le   timestamptz not null default now(),
  traite_par   uuid,
  traite_le    timestamptz,
  conclu_le    timestamptz,
  -- Ce qu'on a envoyé à FeexPay et ce qu'il a répondu, jeton retiré.
  journal      jsonb not null default '[]'::jsonb
);
create index if not exists rh_retraits_employe on public.rh_retraits (employe_id, demande_le desc);
create index if not exists rh_retraits_statut on public.rh_retraits (statut);

-- ---------- Les prêts : les avances, demandées par l'employé ----------
alter table public.rh_avances add column if not exists valide_par uuid;
alter table public.rh_avances add column if not exists valide_le timestamptz;
alter table public.rh_avances add column if not exists motif_refus text not null default '';
alter table public.rh_avances add column if not exists decaisse_par uuid;
alter table public.rh_avances add column if not exists decaisse_le timestamptz;
alter table public.rh_avances add column if not exists reference_caisse text not null default '';
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'rh_avances_statut_check'
               and pg_get_constraintdef(oid) not like '%demandee%') then
    alter table public.rh_avances drop constraint rh_avances_statut_check;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_avances_statut_check') then
    alter table public.rh_avances add constraint rh_avances_statut_check
      check (statut in ('demandee', 'validee', 'active', 'soldee', 'annulee', 'refusee'));
  end if;
end $$;

-- La caisse décaisse aussi les prêts.
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'rh_caisse_mouvements_nature_check'
               and pg_get_constraintdef(oid) not like '%pret%') then
    alter table public.rh_caisse_mouvements drop constraint rh_caisse_mouvements_nature_check;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_caisse_mouvements_nature_check') then
    alter table public.rh_caisse_mouvements add constraint rh_caisse_mouvements_nature_check
      check (nature in ('apport_ceo', 'apport_autre', 'depense', 'salaire', 'pret',
                        'transfert', 'frais', 'ajustement'));
  end if;
end $$;

-- ---------- Le calendrier ----------
/** Aujourd'hui, à l'heure du Bénin. */
create or replace function public.rh_aujourdhui() returns date
language sql stable as $$
  select (now() at time zone 'Africa/Porto-Novo')::date;
$$;

/** Le jour où la paie d'un mois se verse : le 10 du mois suivant. */
create or replace function public.rh_date_versement(mois date) returns date
language sql immutable as $$
  select (date_trunc('month', mois) + interval '1 month 9 days')::date;
$$;

/** Le mois de la prochaine paie d'un employé : celui qu'une prime, une
    retenue ou un prêt accordé aujourd'hui touchera. C'est le mois écoulé
    tant que sa fiche n'est pas validée, sinon le mois en cours — jamais
    un mois d'avant son embauche. */
create or replace function public.rh_prochain_mois_paie(qui uuid) returns date
language plpgsql stable security definer set search_path = public as $$
declare
  depart date := (date_trunc('month', public.rh_aujourdhui()) - interval '1 month')::date;
  embauche date;
  m date;
begin
  select date_trunc('month', date_embauche)::date into embauche from public.rh_employes where id = qui;
  m := greatest(depart, coalesce(embauche, depart));
  while exists (select 1 from public.rh_fiches_paie f
                 where f.employe_id = qui and f.mois = m and f.statut <> 'calculee') loop
    m := (m + interval '1 month')::date;
  end loop;
  return m;
end $$;

-- ---------- Le solde ----------
/** Le solde d'un employé : la somme de ses mouvements. */
create or replace function public.rh_solde_de(qui uuid) returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce(sum(case when sens = 'credit' then montant else -montant end), 0)::bigint
    from public.rh_solde_mouvements where employe_id = qui;
$$;

/** Un mouvement sur le solde, l'employé verrouillé : deux retraits
    simultanés ne passent pas sur le même argent. Un retrait ne fait
    jamais passer le solde sous zéro. Interne. */
create or replace function public.rh_solde_mouvoir(qui uuid, p_sens text, p_nature text, p_montant bigint,
  p_libelle text, p_fiche uuid default null, p_retrait uuid default null)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  dispo bigint;
  ligne bigint;
begin
  if p_montant is null or p_montant <= 0 then
    raise exception 'Le montant doit être positif';
  end if;
  perform 1 from public.rh_employes where id = qui for update;
  dispo := public.rh_solde_de(qui);
  if p_sens = 'debit' and p_nature = 'retrait' and dispo < p_montant then
    raise exception 'Solde insuffisant : % FCFA disponibles, % FCFA demandés',
      replace(to_char(dispo, 'FM999G999G999G990'), ',', ' '), replace(to_char(p_montant, 'FM999G999G999G990'), ',', ' ');
  end if;
  insert into public.rh_solde_mouvements (employe_id, sens, nature, montant, libelle, fiche_id, retrait_id, par, solde)
  values (qui, p_sens, p_nature, p_montant, left(btrim(coalesce(p_libelle, '')), 300), p_fiche, p_retrait,
          public.rh_moi(), dispo + case when p_sens = 'credit' then p_montant else -p_montant end)
  returning id into ligne;
  return ligne;
end $$;

-- ---------- Le versement du 10 ----------
/** Verse une fiche validée sur le solde de son employé, si son jour est
    venu. Rend vrai si elle a été versée. Interne. */
create or replace function public.rh_crediter_fiche(fiche uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  f public.rh_fiches_paie;
begin
  select * into f from public.rh_fiches_paie where id = fiche for update;
  if not found or f.statut <> 'validee' or public.rh_aujourdhui() < public.rh_date_versement(f.mois) then
    return false;
  end if;
  update public.rh_fiches_paie
     set statut = 'payee', paye_le = now(), paye_par = null, mode_paiement = 'solde', reference = ''
   where id = fiche;
  /* Une fiche négative (des retenues plus fortes que le salaire) laisse
     une dette sur le solde : elle se reprend sur les versements suivants. */
  if f.net <> 0 then
    perform public.rh_solde_mouvoir(f.employe_id, case when f.net > 0 then 'credit' else 'debit' end,
      'salaire', abs(f.net), 'Salaire de ' || to_char(f.mois, 'MM/YYYY'), f.id, null);
  end if;
  return true;
end $$;

/** Toutes les fiches validées dont le 10 est passé. pg_cron l'appelle
    chaque matin ; c'est sans effet sur ce qui est déjà versé. */
create or replace function public.rh_crediter_salaires() returns int
language plpgsql security definer set search_path = public as $$
declare
  f record;
  combien int := 0;
begin
  for f in select id from public.rh_fiches_paie
            where statut = 'validee' and public.rh_date_versement(mois) <= public.rh_aujourdhui()
            order by mois, id loop
    if public.rh_crediter_fiche(f.id) then
      combien := combien + 1;
    end if;
  end loop;
  return combien;
end $$;

/* Une fiche validée après le 10 n'attend pas le mois suivant. */
create or replace function public.rh_fiche_validee_versee() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.statut = 'validee' and old.statut is distinct from 'validee' then
    perform public.rh_crediter_fiche(new.id);
  end if;
  return null;
end $$;
drop trigger if exists rh_fiche_validee_versee on public.rh_fiches_paie;
create trigger rh_fiche_validee_versee after update of statut on public.rh_fiches_paie
  for each row execute function public.rh_fiche_validee_versee();

-- ---------- Primes et retenues du CEO ----------
/** Le CEO (ou le superadministrateur) accorde une prime ou impose une
    retenue : elle s'inscrit sur la prochaine paie de l'employé. Rend le
    mois touché. */
create or replace function public.rh_octroyer(qui uuid, nature text, montant bigint, libelle text)
returns date
language plpgsql security definer set search_path = public as $$
declare
  m date;
begin
  if not (public.rh_est_ceo() or public.est_super()) then
    raise exception 'Seul le CEO accorde une prime ou impose une retenue';
  end if;
  if nature not in ('prime', 'retenue') then
    raise exception 'Une prime ou une retenue';
  end if;
  if coalesce(montant, 0) <= 0 then
    raise exception 'Le montant doit être positif';
  end if;
  if length(btrim(coalesce(libelle, ''))) < 3 then
    raise exception 'Dites pourquoi (le libellé figure sur la fiche de paie)';
  end if;
  if not exists (select 1 from public.rh_employes where id = qui and etat in ('actif', 'bloque')) then
    raise exception 'Cet employé n''est pas en poste';
  end if;
  m := public.rh_prochain_mois_paie(qui);
  insert into public.rh_elements_paie (employe_id, mois, nature, libelle, montant, imposable)
  values (qui, m, nature, btrim(libelle), montant, nature = 'prime');
  return m;
end $$;

/** Retirer une prime ou une retenue que la paie n'a pas encore validée. */
create or replace function public.rh_retirer_element(element uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.rh_est_ceo() or public.est_super()) then
    raise exception 'Seul le CEO retire une prime ou une retenue';
  end if;
  delete from public.rh_elements_paie where id = element;
  if not found then
    raise exception 'Élément introuvable';
  end if;
end $$;

-- ---------- Les prêts ----------
/** L'employé demande un prêt : le CEO le validera, la caisse le
    décaissera, la paie suivante le reprendra en une fois. */
create or replace function public.rh_demander_pret(montant bigint, motif text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_moi uuid := public.rh_moi();
  nouveau uuid;
begin
  if v_moi is null then
    raise exception 'Seul un employé en poste demande un prêt';
  end if;
  if coalesce(montant, 0) <= 0 then
    raise exception 'Le montant doit être positif';
  end if;
  if length(btrim(coalesce(motif, ''))) < 3 then
    raise exception 'Dites pourquoi vous demandez ce prêt';
  end if;
  if exists (select 1 from public.rh_avances where employe_id = v_moi and statut in ('demandee', 'validee')) then
    raise exception 'Vous avez déjà un prêt en attente : attendez qu''il soit décaissé ou refusé';
  end if;
  insert into public.rh_avances (employe_id, montant, mensualites, premier_mois, motif, statut)
  values (v_moi, montant, 1, public.rh_prochain_mois_paie(v_moi), btrim(motif), 'demandee')
  returning id into nouveau;
  return nouveau;
end $$;

/** L'employé retire sa demande, tant que le CEO ne l'a pas tranchée. */
create or replace function public.rh_annuler_pret(pret uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('rh.decision', 'oui', true);
  update public.rh_avances set statut = 'annulee'
   where id = pret and employe_id = public.rh_moi() and statut = 'demandee';
  if not found then
    raise exception 'Seule votre demande encore en attente du CEO s''annule';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

/** Le CEO valide ou refuse une demande de prêt. */
create or replace function public.rh_decider_pret(pret uuid, accepter boolean, raison text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.rh_est_ceo() or public.est_super()) then
    raise exception 'Seul le CEO valide un prêt';
  end if;
  if not accepter and length(btrim(coalesce(raison, ''))) < 3 then
    raise exception 'Dites pourquoi vous refusez ce prêt';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_avances
     set statut = case when accepter then 'validee' else 'refusee' end,
         valide_par = public.rh_moi(), valide_le = now(),
         motif_refus = case when accepter then '' else btrim(raison) end
   where id = pret and statut = 'demandee';
  if not found then
    raise exception 'Seule une demande de prêt en attente se tranche';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

/** Le gestionnaire de la caisse décaisse un prêt validé, réparti entre
    les compartiments ; il ne décaisse pas son propre prêt. Le prêt
    s'inscrit alors sur la prochaine paie de l'employé. */
create or replace function public.rh_decaisser_pret(pret uuid, repartition jsonb, reference text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare
  a public.rh_avances;
  rep jsonb;
  k text;
  v jsonb;
  qui_nom text;
begin
  if public.rh_caisse_acces() is distinct from 'gestion' then
    raise exception 'Seul le gestionnaire de la caisse décaisse un prêt';
  end if;
  select * into a from public.rh_avances where id = pret for update;
  if not found or a.statut <> 'validee' then
    raise exception 'Seul un prêt validé par le CEO se décaisse';
  end if;
  if a.employe_id = public.rh_moi() then
    raise exception 'Vous ne décaissez pas votre propre prêt : le CEO désigne quelqu''un d''autre';
  end if;
  rep := public.rh_caisse_repartition(repartition, a.montant);
  select btrim(e.prenoms || ' ' || e.nom) into qui_nom from public.rh_employes e where e.id = a.employe_id;
  for k, v in select e.key, e.value from jsonb_each(rep) as e order by e.key loop
    perform public.rh_caisse_mouvoir(k, 'sortie', 'pret', (v #>> '{}')::bigint,
      'Prêt du ' || to_char(public.rh_aujourdhui(), 'DD/MM/YYYY') || ' · ' || qui_nom, reference);
  end loop;
  /* Le prêt devient une avance active : la prochaine fiche le reprend
     (le déclencheur des avances la recalcule). */
  update public.rh_avances
     set statut = 'active', date_avance = public.rh_aujourdhui(),
         premier_mois = public.rh_prochain_mois_paie(a.employe_id),
         decaisse_par = public.rh_moi(), decaisse_le = now(),
         reference_caisse = left(btrim(coalesce(rh_decaisser_pret.reference, '')), 120)
   where id = pret;
end $$;

-- ---------- Les retraits ----------
/** Le numéro national à dix chiffres (01 + 8), ou une erreur. */
create or replace function public.rh_numero_national(tel text) returns text
language plpgsql immutable as $$
declare
  n text := regexp_replace(coalesce(tel, ''), '[^0-9]', '', 'g');
begin
  if length(n) = 13 and n like '229%' then
    n := right(n, 10);
  end if;
  if length(n) = 8 then
    n := '01' || n;
  end if;
  if length(n) <> 10 or n !~ '^01[0-9]{8}' then
    raise exception 'Numéro de téléphone : 01 suivi de 8 chiffres';
  end if;
  return n;
end $$;

/** L'employé demande un retrait de son solde : par Mobile Money
    (FeexPay) ou à la caisse. Le montant quitte aussitôt son solde ; il
    y revient si le retrait est refusé, annulé ou échoue. */
create or replace function public.rh_demander_retrait(montant bigint, moyen text, reseau text default null,
  telephone text default '')
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_moi uuid := public.rh_moi();
  nouveau uuid;
  num bigint;
  tel text := '';
begin
  if v_moi is null then
    raise exception 'Seul un employé en poste retire de son solde';
  end if;
  if coalesce(montant, 0) <= 0 then
    raise exception 'Le montant doit être positif';
  end if;
  if moyen not in ('feexpay', 'caisse') then
    raise exception 'Choisissez : Mobile Money ou la caisse';
  end if;
  if moyen = 'feexpay' then
    if reseau not in ('mtn', 'moov', 'celtiis') then
      raise exception 'Choisissez le réseau : MTN, Moov ou Celtiis';
    end if;
    -- FeexPay ne reverse pas moins de 50 francs.
    if montant < 50 then
      raise exception 'Un retrait Mobile Money fait au moins 50 FCFA';
    end if;
    tel := public.rh_numero_national(telephone);
  end if;
  insert into public.rh_retraits (employe_id, montant, moyen, reseau, telephone)
  values (v_moi, montant, moyen, case when moyen = 'feexpay' then reseau end, tel)
  returning id, numero into nouveau, num;
  perform public.rh_solde_mouvoir(v_moi, 'debit', 'retrait', montant,
    'Retrait R-' || lpad(num::text, 4, '0') || case when moyen = 'feexpay' then ' (Mobile Money)' else ' (caisse)' end,
    null, nouveau);
  return nouveau;
end $$;

/** Le montant d'un retrait qui n'a pas abouti revient sur le solde. Interne. */
create or replace function public.rh_retrait_rendre(r public.rh_retraits, pourquoi text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.rh_solde_mouvoir(r.employe_id, 'credit', 'retour', r.montant,
    'Retour du retrait R-' || lpad(r.numero::text, 4, '0') || ' · ' || pourquoi, null, r.id);
end $$;

/** L'employé annule son retrait tant que personne ne l'a traité. */
create or replace function public.rh_annuler_retrait(retrait uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  r public.rh_retraits;
begin
  update public.rh_retraits set statut = 'annule', conclu_le = now()
   where id = retrait and employe_id = public.rh_moi() and statut = 'demande'
  returning * into r;
  if r.id is null then
    raise exception 'Seul votre retrait encore en attente s''annule';
  end if;
  perform public.rh_retrait_rendre(r, 'annulé');
end $$;

/** Le gestionnaire de la caisse (ou le CEO) refuse un retrait, avec un motif. */
create or replace function public.rh_refuser_retrait(retrait uuid, raison text) returns void
language plpgsql security definer set search_path = public as $$
declare
  r public.rh_retraits;
begin
  if public.rh_caisse_acces() not in ('gestion', 'ceo', 'super') or public.rh_caisse_acces() is null then
    raise exception 'Seuls le gestionnaire de la caisse et le CEO refusent un retrait';
  end if;
  if length(btrim(coalesce(raison, ''))) < 3 then
    raise exception 'Dites pourquoi vous refusez ce retrait';
  end if;
  update public.rh_retraits
     set statut = 'refuse', motif = btrim(raison), traite_par = public.rh_moi(), traite_le = now(), conclu_le = now()
   where id = retrait and statut = 'demande'
  returning * into r;
  if r.id is null then
    raise exception 'Seul un retrait en attente se refuse';
  end if;
  perform public.rh_retrait_rendre(r, 'refusé');
end $$;

/** Le gestionnaire remet l'argent à la caisse, réparti entre les
    compartiments. Il peut servir ainsi un retrait demandé en Mobile
    Money (en l'envoyant lui-même depuis le compartiment MTN, par
    exemple). Il ne sert pas son propre retrait. */
create or replace function public.rh_servir_retrait(retrait uuid, repartition jsonb, reference text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare
  r public.rh_retraits;
  rep jsonb;
  k text;
  v jsonb;
  qui_nom text;
begin
  if public.rh_caisse_acces() is distinct from 'gestion' then
    raise exception 'Seul le gestionnaire de la caisse sert un retrait';
  end if;
  select * into r from public.rh_retraits where id = retrait for update;
  if not found or r.statut <> 'demande' then
    raise exception 'Seul un retrait en attente se sert';
  end if;
  if r.employe_id = public.rh_moi() then
    raise exception 'Vous ne servez pas votre propre retrait : le CEO désigne quelqu''un d''autre';
  end if;
  rep := public.rh_caisse_repartition(repartition, r.montant);
  select btrim(e.prenoms || ' ' || e.nom) into qui_nom from public.rh_employes e where e.id = r.employe_id;
  for k, v in select e.key, e.value from jsonb_each(rep) as e order by e.key loop
    perform public.rh_caisse_mouvoir(k, 'sortie', 'salaire', (v #>> '{}')::bigint,
      'Retrait de salaire R-' || lpad(r.numero::text, 4, '0') || ' · ' || qui_nom, reference);
  end loop;
  update public.rh_retraits
     set statut = 'paye', moyen = 'caisse', reference = left(btrim(coalesce(rh_servir_retrait.reference, '')), 120),
         traite_par = public.rh_moi(), traite_le = now(), conclu_le = now()
   where id = retrait;
end $$;

/** Le gestionnaire lance le reversement FeexPay d'un retrait. Appelée
    par la fonction Edge « rh-reversement » AVEC LE JETON DU
    GESTIONNAIRE : c'est la base qui vérifie son droit. Le retrait passe
    à « envoi » d'un coup : deux clics ne font pas deux virements. Rend
    ce que la fonction envoie à FeexPay — le montant vient d'ici. */
create or replace function public.rh_retrait_preparer(retrait uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r public.rh_retraits;
begin
  if public.rh_caisse_acces() is distinct from 'gestion' then
    raise exception 'Seul le gestionnaire de la caisse lance un reversement';
  end if;
  select * into r from public.rh_retraits where id = retrait;
  if found and r.employe_id = public.rh_moi() then
    raise exception 'Vous ne servez pas votre propre retrait : le CEO désigne quelqu''un d''autre';
  end if;
  update public.rh_retraits
     set statut = 'envoi', traite_par = public.rh_moi(), traite_le = now()
   where id = retrait and statut = 'demande' and moyen = 'feexpay'
  returning * into r;
  if r.id is null then
    raise exception 'Seul un retrait Mobile Money en attente se reverse';
  end if;
  return jsonb_build_object('id', r.id, 'numero', r.numero, 'montant', r.montant,
    'reseau', r.reseau, 'telephone', r.telephone);
end $$;

/** Ce que la fonction Edge a constaté chez FeexPay. Service seulement :
    aucun compte ne s'écrit « payé ». Les passages permis :
      envoi → demande (rien n'est parti), envoye (référence), incertain, echoue ;
      envoye / incertain → paye, echoue. */
create or replace function public.rh_retrait_resultat(retrait uuid, issue text, reference text default '',
  trace jsonb default '{}'::jsonb)
returns text
language plpgsql security definer set search_path = public as $$
declare
  r public.rh_retraits;
begin
  select * into r from public.rh_retraits where id = retrait for update;
  if not found then
    raise exception 'Retrait introuvable';
  end if;
  if not ((r.statut = 'envoi' and issue in ('demande', 'envoye', 'incertain', 'echoue'))
          or (r.statut in ('envoye', 'incertain') and issue in ('paye', 'echoue'))) then
    -- Déjà conclu, ou passage interdit : on ne change rien.
    update public.rh_retraits set journal = journal || jsonb_build_array(jsonb_build_object(
        'le', now(), 'ignore', issue, 'trace', coalesce(trace, '{}'::jsonb)))
     where id = retrait;
    return r.statut;
  end if;
  update public.rh_retraits
     set statut = issue,
         reference = case when coalesce(btrim(rh_retrait_resultat.reference), '') <> ''
                          then left(btrim(rh_retrait_resultat.reference), 120) else r.reference end,
         traite_par = case when issue = 'demande' then null else r.traite_par end,
         traite_le = case when issue = 'demande' then null else r.traite_le end,
         conclu_le = case when issue in ('paye', 'echoue') then now() else null end,
         journal = journal || jsonb_build_array(jsonb_build_object(
           'le', now(), 'issue', issue, 'trace', coalesce(trace, '{}'::jsonb)))
   where id = retrait;
  if issue = 'echoue' then
    perform public.rh_retrait_rendre(r, 'reversement échoué');
  end if;
  return issue;
end $$;

/** Les reversements à revérifier chez FeexPay. Service seulement. */
create or replace function public.rh_retraits_a_verifier() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'reference', reference, 'montant', montant)), '[]')
    from public.rh_retraits
   where statut in ('envoye', 'incertain') and reference <> '';
$$;

/** Le CEO tranche un reversement incertain (ou bloqué en envoi depuis
    plus de 10 minutes), après avoir regardé le tableau de bord FeexPay :
    payé, ou rien n'est parti (le montant revient alors sur le solde). */
create or replace function public.rh_retrait_trancher(retrait uuid, paye boolean, constat text) returns void
language plpgsql security definer set search_path = public as $$
declare
  r public.rh_retraits;
begin
  if not (public.rh_est_ceo() or public.est_super()) then
    raise exception 'Seul le CEO tranche un reversement incertain';
  end if;
  if length(btrim(coalesce(constat, ''))) < 3 then
    raise exception 'Dites ce que vous avez constaté chez FeexPay';
  end if;
  select * into r from public.rh_retraits where id = retrait for update;
  if not found or not (r.statut = 'incertain' or (r.statut = 'envoi' and r.traite_le < now() - interval '10 minutes')) then
    raise exception 'Seul un reversement incertain se tranche';
  end if;
  update public.rh_retraits
     set statut = case when paye then 'paye' else 'echoue' end, motif = btrim(constat), conclu_le = now(),
         journal = journal || jsonb_build_array(jsonb_build_object('le', now(), 'tranche_par', public.rh_moi(),
           'paye', paye, 'motif', btrim(constat)))
   where id = retrait;
  if not paye then
    perform public.rh_retrait_rendre(r, 'reversement non parti');
  end if;
end $$;

-- ---------- Ce que chacun lit ----------
/** Le compte d'un employé : son solde, ses mouvements, ses retraits, ses
    prêts, et ce qui attend sa prochaine paie. L'employé lit le sien ;
    le CEO et le superadministrateur, celui de chacun. */
create or replace function public.rh_compte_employe(qui uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  cible uuid := coalesce(qui, public.rh_moi());
  prochain date;
begin
  if cible is null then
    raise exception 'Seul un employé en poste a un solde';
  end if;
  if cible is distinct from public.rh_moi() and not (public.rh_est_ceo() or public.est_super()) then
    raise exception 'Vous ne lisez que votre propre solde';
  end if;
  prochain := public.rh_prochain_mois_paie(cible);
  return jsonb_build_object(
    'employe_id', cible,
    'solde', public.rh_solde_de(cible),
    'telephone', (select telephone from public.rh_employes where id = cible),
    'prochain_mois', prochain,
    'prochain_versement', public.rh_date_versement(prochain),
    'mouvements', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'le', m.le, 'sens', m.sens,
        'nature', m.nature, 'montant', m.montant, 'libelle', m.libelle, 'solde', m.solde) order by m.id desc), '[]')
      from (select * from public.rh_solde_mouvements where employe_id = cible order by id desc limit 100) m),
    'retraits', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'numero', r.numero, 'montant', r.montant,
        'moyen', r.moyen, 'reseau', r.reseau, 'telephone', r.telephone, 'statut', r.statut, 'motif', r.motif,
        'demande_le', r.demande_le, 'conclu_le', r.conclu_le) order by r.demande_le desc), '[]')
      from (select * from public.rh_retraits where employe_id = cible order by demande_le desc limit 50) r),
    'prets', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'montant', a.montant, 'motif', a.motif,
        'statut', a.statut, 'motif_refus', a.motif_refus, 'cree_le', a.cree_le, 'premier_mois', a.premier_mois,
        'decaisse_le', a.decaisse_le,
        'reste', a.montant - coalesce((select sum(fa.montant) from public.rh_fiche_avances fa
                                         join public.rh_fiches_paie f on f.id = fa.fiche_id
                                        where fa.avance_id = a.id and f.statut <> 'calculee'), 0))
        order by a.cree_le desc), '[]')
      from (select * from public.rh_avances where employe_id = cible and statut <> 'annulee'
             order by cree_le desc limit 50) a),
    'elements', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'mois', x.mois, 'nature', x.nature,
        'libelle', x.libelle, 'montant', x.montant) order by x.mois, x.cree_le), '[]')
      from public.rh_elements_paie x where x.employe_id = cible and x.mois >= prochain));
end $$;

/** Les prêts et les retraits à traiter : le CEO valide les prêts et
    tranche les reversements incertains ; le gestionnaire décaisse les
    prêts et sert les retraits. Le CEO et le superadministrateur voient
    aussi le solde de chacun. */
create or replace function public.rh_prets_retraits() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  acces text := public.rh_caisse_acces();
  chef boolean := public.rh_est_ceo() or public.est_super();
begin
  if not chef and acces is distinct from 'gestion' then
    raise exception 'Réservé au CEO et au gestionnaire de la caisse';
  end if;
  return jsonb_build_object(
    'gestion', acces = 'gestion',
    'chef', chef,
    'moi', public.rh_moi(),
    'prets', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'employe_id', a.employe_id,
        'nom', btrim(e.prenoms || ' ' || e.nom), 'montant', a.montant, 'motif', a.motif, 'statut', a.statut,
        'cree_le', a.cree_le, 'valide_le', a.valide_le) order by a.cree_le), '[]')
      from public.rh_avances a join public.rh_employes e on e.id = a.employe_id
     where a.statut in ('demandee', 'validee')),
    'retraits', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'numero', r.numero,
        'employe_id', r.employe_id, 'nom', btrim(e.prenoms || ' ' || e.nom), 'montant', r.montant,
        'moyen', r.moyen, 'reseau', r.reseau, 'telephone', r.telephone,
        'telephone_fiche', e.telephone, 'statut', r.statut, 'motif', r.motif, 'reference', r.reference,
        'demande_le', r.demande_le, 'traite_le', r.traite_le, 'conclu_le', r.conclu_le) order by r.demande_le desc), '[]')
      from (select * from public.rh_retraits
             where statut in ('demande', 'envoi', 'envoye', 'incertain')
                or conclu_le > now() - interval '30 days') r
      join public.rh_employes e on e.id = r.employe_id),
    'soldes', case when chef then (select coalesce(jsonb_agg(jsonb_build_object('employe_id', e.id,
        'nom', btrim(e.prenoms || ' ' || e.nom), 'solde', public.rh_solde_de(e.id)) order by e.nom, e.prenoms), '[]')
      from public.rh_employes e where e.etat in ('actif', 'bloque')
         or exists (select 1 from public.rh_solde_mouvements m where m.employe_id = e.id)) end);
end $$;

/** Les pastilles du menu « Prêts et retraits ». */
create or replace function public.rh_compteurs_solde() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  acces text := public.rh_caisse_acces();
  chef boolean := public.rh_est_ceo() or public.est_super();
  v_moi uuid := public.rh_moi();
begin
  return jsonb_build_object(
    'menu', chef or acces = 'gestion',
    'prets_a_valider', case when chef then (select count(*) from public.rh_avances where statut = 'demandee') else 0 end,
    'prets_a_decaisser', case when acces = 'gestion' then
      (select count(*) from public.rh_avances where statut = 'validee' and employe_id is distinct from v_moi) else 0 end,
    'retraits_a_servir', case when acces = 'gestion' then
      (select count(*) from public.rh_retraits where statut = 'demande' and employe_id is distinct from v_moi) else 0 end,
    'retraits_incertains', case when chef then
      (select count(*) from public.rh_retraits where statut = 'incertain'
          or (statut = 'envoi' and traite_le < now() - interval '10 minutes')) else 0 end);
end $$;

-- ---------- Les droits ----------
alter table public.rh_solde_mouvements enable row level security;
alter table public.rh_retraits enable row level security;
-- Aucune règle : tout passe par les fonctions ci-dessus.
revoke all on table public.rh_solde_mouvements, public.rh_retraits from public, anon, authenticated;
grant all on table public.rh_solde_mouvements, public.rh_retraits to service_role;

do $$
declare f text;
begin
  foreach f in array array['rh_octroyer(uuid, text, bigint, text)', 'rh_retirer_element(uuid)',
                           'rh_demander_pret(bigint, text)', 'rh_annuler_pret(uuid)',
                           'rh_decider_pret(uuid, boolean, text)', 'rh_decaisser_pret(uuid, jsonb, text)',
                           'rh_demander_retrait(bigint, text, text, text)', 'rh_annuler_retrait(uuid)',
                           'rh_refuser_retrait(uuid, text)', 'rh_servir_retrait(uuid, jsonb, text)',
                           'rh_retrait_preparer(uuid)', 'rh_retrait_trancher(uuid, boolean, text)',
                           'rh_compte_employe(uuid)', 'rh_prets_retraits()', 'rh_compteurs_solde()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
  foreach f in array array['rh_retrait_resultat(uuid, text, text, jsonb)', 'rh_retraits_a_verifier()'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
  foreach f in array array['rh_solde_mouvoir(uuid, text, text, bigint, text, uuid, uuid)',
                           'rh_crediter_fiche(uuid)', 'rh_crediter_salaires()', 'rh_fiche_validee_versee()',
                           'rh_retrait_rendre(public.rh_retraits, text)', 'rh_solde_fige()',
                           'rh_solde_de(uuid)', 'rh_prochain_mois_paie(uuid)', 'rh_aujourdhui()',
                           'rh_date_versement(date)', 'rh_numero_national(text)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

-- ---------- Le calendrier, tout seul ----------
-- Chaque matin à 7 h (heure du Bénin, 6 h UTC) : les fiches du mois
-- écoulé si l'on est le 5 ou après et qu'elles manquent, puis le
-- versement des fiches validées dont le 10 est passé. Toutes les
-- 10 minutes, s'il y a des reversements FeexPay en cours, la fonction
-- Edge va voir où ils en sont. Sans pg_cron, l'application rattrape la
-- paie à l'ouverture.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      perform cron.unschedule('rh-paie-fin-de-mois');
    exception when others then
      null;
    end;
    perform cron.schedule('rh-paie-quotidienne', '0 6 * * *',
      'select public.rh_generer_paie_auto(); select public.rh_crediter_salaires();');
    if exists (select 1 from pg_extension where extname = 'pg_net') then
      perform cron.schedule('rh-reversements-verifier', '*/10 * * * *',
        'select net.http_post(''https://rrwzegmrmvvkmzfoiitb.supabase.co/functions/v1/rh-reversement'', ''{"action":"verifier_tout"}''::jsonb, ''{}''::jsonb, ''{"Content-Type": "application/json"}''::jsonb, 60000) where exists (select 1 from public.rh_retraits where statut in (''envoye'', ''incertain'') and reference <> '''')');
    end if;
  end if;
exception when others then
  raise notice 'Calendrier de la paie non programmé (%), l''application la rattrapera', sqlerrm;
end $$;

-- =========================================================
-- BIZZOO Personnel : la place de marché d'un coup d'œil, sur l'accueil
--
-- Une seule lecture, rh_accueil_chiffres() : le mois en cours et
-- aujourd'hui (heure du Bénin) pour les commandes, les livraisons, les
-- clients, les boutiques, les produits, les livreurs, les avis et le SAV.
-- Mêmes droits que les Statistiques :
--   - les nombres : l'administration, le superadministrateur, et les
--     profils à qui Paramètres ouvre les statistiques des commandes ;
--   - les montants (ventes, frais de livraison, panier moyen) :
--     l'administration et le superadministrateur ;
--   - la marge de BIZZOO : le CEO et le superadministrateur.
-- Les autres reçoivent null : leur accueil reste celui de leurs tâches.
-- =========================================================

create or replace function public.rh_accueil_chiffres() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  m1 timestamptz := date_trunc('month', aujourdhui)::timestamp at time zone 'Africa/Porto-Novo';
  j1 timestamptz := aujourdhui::timestamp at time zone 'Africa/Porto-Novo';
  argent boolean := public.rh_est_admin() or public.est_super();
  marge boolean := public.rh_est_ceo() or public.est_super();
begin
  if not (argent or public.rh_menu_ouvert('stats_commandes')) then
    return null;
  end if;
  return (
    with payees_mois as (
      select c.* from public.commandes c where c.etat = 'payee' and c.paye_le >= m1
    ),
    lignes_mois as (
      select l.* from public.commande_lignes l join payees_mois c on c.id = l.commande_id
       where l.etat <> 'annulee'
    ),
    -- Ce qui est en route aujourd'hui : les articles de commandes payées.
    lignes_ouvertes as (
      select l.* from public.commande_lignes l join public.commandes c on c.id = l.commande_id
       where c.etat = 'payee' and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')
    )
    select jsonb_build_object(
      'mois', date_trunc('month', aujourdhui)::date,
      'droits', jsonb_build_object('argent', argent, 'marge', marge),
      'commandes', jsonb_build_object(
        'recues_mois', (select count(*) from public.commandes c where c.cree_le >= m1),
        'payees_mois', (select count(*) from payees_mois),
        'payees_jour', (select count(*) from payees_mois where paye_le >= j1),
        'a_payer_mois', (select count(*) from public.commandes c where c.etat = 'a_payer' and c.cree_le >= m1),
        'annulees_mois', (select count(*) from public.commandes c where c.etat in ('annulee', 'echouee') and c.cree_le >= m1),
        'revendeurs_mois', (select count(*) from payees_mois where revendeur),
        'articles_mois', (select coalesce(sum(quantite), 0) from lignes_mois),
        'ventes_mois', case when argent then (select coalesce(sum(total), 0) from payees_mois) end,
        'ventes_jour', case when argent then (select coalesce(sum(total), 0) from payees_mois where paye_le >= j1) end,
        'panier_moyen', case when argent then (select coalesce(round(avg(total)), 0) from payees_mois) end,
        'frais_livraison_mois', case when argent then (select coalesce(sum(frais_livraison), 0) from payees_mois) end,
        'remises_mois', case when argent then (select coalesce(sum(remise), 0) from payees_mois) end,
        'marge_mois', case when marge then
          (select coalesce(sum(greatest(0, prix - prix_bizzoo) * quantite), 0) from lignes_mois) end),
      'livraisons', jsonb_build_object(
        'confirmees_mois', (select count(*) from public.commande_lignes l where l.confirme_le >= m1),
        'a_preparer', (select count(*) from lignes_ouvertes where etat in ('nouvelle', 'vue')),
        'pretes', (select count(*) from lignes_ouvertes where etat = 'preparee'),
        'en_livraison', (select count(*) from lignes_ouvertes where etat = 'en_livraison'),
        'livrees_sans_confirmation', (select count(*) from public.commande_lignes l join public.commandes c on c.id = l.commande_id
                                        where c.etat = 'payee' and l.etat = 'remise' and l.confirme_le is null),
        'livreurs', (select count(*) from public.profils p where p.role = 'livreur' and p.actif),
        'livreurs_en_course', (select count(distinct livreur_id) from lignes_ouvertes where livreur_id is not null and etat = 'en_livraison')),
      'clients', jsonb_build_object(
        'total', (select count(*) from public.clients),
        'nouveaux_mois', (select count(*) from public.clients k where k.cree_le >= m1),
        'nouveaux_jour', (select count(*) from public.clients k where k.cree_le >= j1),
        'verifies', (select count(*) from public.clients k where k.tel_verifie),
        'acheteurs_mois', (select count(distinct client_id) from payees_mois where client_id is not null),
        'revendeurs', (select count(*) from public.clients k where k.revendeur_etat = 'validee'),
        'revendeurs_en_attente', (select count(*) from public.clients k where k.revendeur_etat = 'en_attente')),
      'boutiques', jsonb_build_object(
        'total', (select count(*) from public.boutiques),
        'actives', (select count(*) from public.boutiques b where b.actif),
        'nouvelles_mois', (select count(*) from public.boutiques b where b.cree_le >= m1),
        'ayant_vendu_mois', (select count(distinct boutique_id) from lignes_mois)),
      'produits', jsonb_build_object(
        'total', (select count(*) from public.produits p where not p.masque),
        'disponibles', (select count(*) from public.produits p where not p.masque and p.disponible),
        'ruptures', (select count(*) from public.produits p where not p.masque and not p.sur_commande and p.stock = 0),
        'nouveaux_mois', (select count(*) from public.produits p where p.cree_le >= m1),
        'masques', (select count(*) from public.produits p where p.masque)),
      'avis', jsonb_build_object(
        'mois', (select count(*) from public.avis a where a.cree_le >= m1),
        'note_moyenne', (select round(avg(note)::numeric, 2) from public.avis a where not a.masque)),
      'sav', jsonb_build_object(
        'ouvertes', (select count(*) from public.reclamations r where r.etat in ('ouverte', 'escaladee')),
        'mois', (select count(*) from public.reclamations r where r.cree_le >= m1))
    ));
end $$;

revoke all on function public.rh_accueil_chiffres() from public, anon;
grant execute on function public.rh_accueil_chiffres() to authenticated, service_role;

-- =========================================================
-- BIZZOO Personnel : la première connexion avec un mot de passe de départ
--
-- Les employés importés n'ont que leur numéro. BIZZOO leur ouvre un
-- compte « numéro + mot de passe de départ », le même pour tous et donné
-- de vive voix ; il n'est écrit nulle part dans ce dépôt public : le
-- fichier qui crée les comptes reste hors du dépôt.
--
-- Un mot de passe que tout le monde connaît ne doit rien ouvrir : le
-- compte n'est PAS relié à la fiche de l'employé tant que celui-ci n'a
-- pas choisi le sien. Sans fiche reliée, rh_moi() est vide et la base
-- ne lui accorde rien. rh_activer_compte() relie le compte, mais
-- seulement si le mot de passe enregistré n'est plus celui de départ
-- (on compare l'empreinte gardée à la création) ; ensuite, le mot de
-- passe de départ ne vaut plus rien pour ce compte.
-- =========================================================

create table if not exists public.rh_comptes_a_activer (
  compte_id   uuid primary key references auth.users(id) on delete cascade,
  employe_id  uuid not null references public.rh_employes(id) on delete cascade,
  -- L'empreinte du mot de passe de départ, telle que l'a rangée Supabase.
  empreinte   text not null,
  cree_le     timestamptz not null default now()
);
alter table public.rh_comptes_a_activer enable row level security;
-- Aucune règle : seules les deux fonctions ci-dessous y touchent.
revoke all on table public.rh_comptes_a_activer from public, anon, authenticated;
grant all on table public.rh_comptes_a_activer to service_role;

/** Ce compte doit-il encore choisir son mot de passe ? */
create or replace function public.rh_activation() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'a_activer', a.compte_id is not null,
    'prenoms', e.prenoms)
    from (select auth.uid() as id) moi
    left join public.rh_comptes_a_activer a on a.compte_id = moi.id
    left join public.rh_employes e on e.id = a.employe_id;
$$;

/** Le mot de passe est choisi : le compte rejoint enfin sa fiche. */
create or replace function public.rh_activer_compte() returns uuid
language plpgsql security definer set search_path = public as $$
declare
  a public.rh_comptes_a_activer;
  actuelle text;
  e public.rh_employes;
begin
  select * into a from public.rh_comptes_a_activer where compte_id = auth.uid() for update;
  if not found then
    raise exception 'Ce compte n''a rien à activer';
  end if;
  select encrypted_password into actuelle from auth.users where id = auth.uid();
  if actuelle is not distinct from a.empreinte then
    raise exception 'Choisissez un mot de passe à vous : celui donné par BIZZOO ne vaut que pour la première connexion';
  end if;
  select * into e from public.rh_employes where id = a.employe_id and etat = 'actif' for update;
  if not found then
    raise exception 'Votre fiche n''est pas (ou plus) celle d''un employé en poste : adressez-vous à l''administration';
  end if;
  if e.compte_id is not null and e.compte_id <> auth.uid() then
    raise exception 'Votre fiche est déjà reliée à un autre compte : adressez-vous à l''administration';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_employes set compte_id = auth.uid() where id = e.id;
  perform set_config('rh.decision', '', true);
  delete from public.rh_comptes_a_activer where compte_id = auth.uid();
  -- Un compte né de cette connexion n'est pas un compte de boutique.
  delete from public.profils p where p.id = auth.uid() and not p.actif and p.role = 'moderateur';
  return e.id;
end $$;

revoke all on function public.rh_activation() from public, anon;
grant execute on function public.rh_activation() to authenticated, service_role;
revoke all on function public.rh_activer_compte() from public, anon;
grant execute on function public.rh_activer_compte() to authenticated, service_role;

-- =========================================================
-- BIZZOO Personnel : l'administration redonne un mot de passe
--
-- Un employé a oublié son mot de passe : l'administration (CEO compris)
-- lui en donne un provisoire, depuis sa fiche. Changer le mot de passe
-- d'un autre compte demande la clé de service : la fonction Edge
-- « rh-mot-de-passe » le fait, la clé ne quitte jamais le serveur ; la
-- base, elle, décide qui en a le droit (rh_mdp_preparer, appelée avec la
-- session de l'administrateur).
--
-- Le mot de passe provisoire se traite comme le mot de passe de départ :
-- le compte est détaché de sa fiche jusqu'à ce que l'employé choisisse
-- le sien (rh_comptes_a_activer, rh_activer_compte) ; ses sessions
-- ouvertes sont fermées ; le geste va au journal de la fiche.
-- La fiche du CEO ne se traite que par le CEO ou le superadministrateur ;
-- personne ne traite la sienne ici (« Mon compte » est fait pour ça).
-- =========================================================

do $$
begin
  if exists (select 1 from pg_constraint where conname = 'rh_journal_employes_action_check'
               and pg_get_constraintdef(oid) not like '%mot_de_passe%') then
    alter table public.rh_journal_employes drop constraint rh_journal_employes_action_check;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_journal_employes_action_check') then
    alter table public.rh_journal_employes add constraint rh_journal_employes_action_check
      check (action in ('bloque', 'debloque', 'supprime', 'efface', 'mot_de_passe'));
  end if;
end $$;

/** Le compte de connexion d'un employé, si l'appelant a le droit de lui
    donner un mot de passe provisoire. Appelée par la fonction Edge avec
    la session de l'administrateur. */
create or replace function public.rh_mdp_preparer(qui uuid) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare
  e public.rh_employes;
  compte uuid;
begin
  if not (public.rh_est_admin() or public.est_super()) then
    raise exception 'Seule l''administration donne un mot de passe provisoire';
  end if;
  select * into e from public.rh_employes where id = qui and etat in ('actif', 'bloque');
  if not found then
    raise exception 'Seul un employé en poste reçoit un mot de passe';
  end if;
  if e.ceo and not (public.rh_est_ceo() or public.est_super()) then
    raise exception 'Le mot de passe du CEO ne se change que par lui ou le superadministrateur';
  end if;
  compte := coalesce(e.compte_id, (select a.compte_id from public.rh_comptes_a_activer a where a.employe_id = qui limit 1));
  if compte is null then
    raise exception 'Cet employé n''a pas encore de compte de connexion';
  end if;
  if compte = auth.uid() then
    raise exception 'Votre propre mot de passe se change dans « Mon compte »';
  end if;
  return compte;
end $$;

/** Le mot de passe provisoire est posé : le compte attend que l'employé
    choisisse le sien, ses sessions sont fermées, le geste est noté.
    Service seulement : la fonction Edge l'appelle après avoir changé le
    mot de passe. */
create or replace function public.rh_mdp_conclure(qui uuid, compte uuid, par uuid, motif text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare
  e public.rh_employes;
  auteur text;
begin
  select * into e from public.rh_employes where id = qui for update;
  if not found then
    raise exception 'Employé introuvable';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_employes set compte_id = null where id = qui and compte_id = compte;
  perform set_config('rh.decision', '', true);
  insert into public.rh_comptes_a_activer (compte_id, employe_id, empreinte)
  select compte, qui, u.encrypted_password from auth.users u where u.id = compte
  on conflict (compte_id) do update set employe_id = excluded.employe_id, empreinte = excluded.empreinte, cree_le = now();
  -- Qui était connecté avec l'ancien mot de passe ne l'est plus.
  if to_regclass('auth.sessions') is not null then
    execute format('delete from auth.sessions where user_id = %L', compte);
  end if;
  select coalesce(btrim(x.prenoms || ' ' || x.nom), '') into auteur from public.rh_employes x where x.compte_id = par;
  insert into public.rh_journal_employes (employe_id, matricule, nom, action, motif, par_compte, par_nom)
  values (e.id, coalesce(e.matricule, ''), btrim(e.prenoms || ' ' || e.nom), 'mot_de_passe',
          btrim(coalesce(motif, '')), par, coalesce(nullif(auteur, ''), 'Superadministrateur'));
end $$;

revoke all on function public.rh_mdp_preparer(uuid) from public, anon;
grant execute on function public.rh_mdp_preparer(uuid) to authenticated, service_role;
revoke all on function public.rh_mdp_conclure(uuid, uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.rh_mdp_conclure(uuid, uuid, uuid, text) to service_role;

-- =========================================================
-- BIZZOO Personnel : le menu Livreurs
--
-- La liste de tous les livreurs (de BIZZOO et des boutiques), avec ce
-- que chacun a fait sur la période ; un clic ouvre sa fiche et ses
-- statistiques (rh_livreurs, rh_livreur_fiche). Mêmes droits que la
-- carte et le classement des livreurs : l'administration, le
-- superadministrateur, et les profils à qui Paramètres ouvre
-- « Localiser un livreur » ou les statistiques des livreurs. Les
-- montants (gains, encaissements) : l'administration seulement.
--
-- BLOQUER UN LIVREUR (rh_bloquer_livreur) : l'administration seule, motif
-- obligatoire. Il ne reçoit plus aucune course : aucune demande ne lui
-- est proposée, il ne peut plus en prendre, et personne ne peut lui en
-- confier. Ses courses pas encore parties sont retirées et repartent
-- vers les boutiques, qui les confient à un autre ; celles qu'il a déjà
-- en route, il les termine. Il garde son compte : il voit ses courses
-- passées et rend ce qu'il a encaissé. Chaque blocage et chaque
-- déblocage est gardé, avec son auteur et son motif.
-- =========================================================

-- Personne ne pose ce drapeau à la main : seulement rh_bloquer_livreur.
-- Les comptes de boutique qui modifient leurs livreurs ne le peuvent pas.
create or replace function public.profils_garde_blocage() returns trigger
language plpgsql set search_path = public as $$
begin
  if coalesce(current_setting('bizzoo.blocage', true), '') = 'oui' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.courses_bloquees := false;
  elsif new.courses_bloquees is distinct from old.courses_bloquees then
    raise exception 'Le blocage d''un livreur se décide dans BIZZOO Personnel, par l''administration';
  end if;
  return new;
end $$;
drop trigger if exists profils_garde_blocage on public.profils;
create trigger profils_garde_blocage
  before insert or update on public.profils
  for each row execute function public.profils_garde_blocage();

-- L'historique des blocages : on ne l'efface pas, personne n'y écrit
-- directement.
create table if not exists public.livreurs_blocages (
  id          bigserial primary key,
  profil_id   uuid not null references public.profils(id) on delete cascade,
  bloque      boolean not null,
  motif       text not null default '',
  par_compte  uuid,
  par_nom     text not null default '',
  le          timestamptz not null default now()
);
create index if not exists livreurs_blocages_profil on public.livreurs_blocages(profil_id, le desc);
alter table public.livreurs_blocages enable row level security;
revoke all on public.livreurs_blocages from anon, authenticated;
revoke all on sequence public.livreurs_blocages_id_seq from anon, authenticated;
grant all on public.livreurs_blocages to service_role;
grant usage, select on sequence public.livreurs_blocages_id_seq to service_role;

/** Qui ouvre le menu Livreurs. */
create or replace function public.rh_voit_livreurs() returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super() or public.rh_menu_ouvert('livreurs') or public.rh_menu_ouvert('stats_livreurs');
$$;

/** Tous les livreurs, et ce que chacun a fait sur la période. */
create or replace function public.rh_livreurs(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  d1 date := coalesce(depuis, aujourdhui - 29);
  d2 date := coalesce(jusqu, aujourdhui);
  t1 timestamptz;
  t2 timestamptz;
  argent boolean := public.rh_est_admin() or public.est_super();
begin
  if not public.rh_voit_livreurs() then
    raise exception 'Votre compte n''a pas accès aux livreurs';
  end if;
  if d2 < d1 then
    raise exception 'La fin de la période précède son début';
  end if;
  if d2 - d1 > 1100 then
    raise exception 'Choisissez une période de trois ans au plus';
  end if;
  t1 := d1::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (d2 + 1)::timestamp at time zone 'Africa/Porto-Novo';
  return jsonb_build_object(
    'periode', jsonb_build_object('depuis', d1, 'jusqu', d2),
    'droits', jsonb_build_object('argent', argent, 'bloquer', argent),
    'livreurs', (select coalesce(jsonb_agg(x.j order by x.bloque, x.courses desc, x.nom), '[]') from (
      select p.courses_bloquees as bloque, k.courses,
             coalesce(nullif(btrim(p.nom), ''), p.email, 'Livreur') as nom,
             jsonb_build_object(
               'id', p.id,
               'nom', coalesce(nullif(btrim(p.nom), ''), p.email, 'Livreur'),
               'tel', coalesce(p.tel, ''),
               'vehicule', coalesce(p.vehicule, 'moto'),
               'boutique', (select b.nom from public.boutiques b where b.id = p.boutique_id),
               'actif', p.actif,
               'valide', exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id),
               'bloque', p.courses_bloquees,
               'en_course', public.livreur_en_course(p.id),
               'courses', k.courses,
               'livrees', k.livrees,
               'refus', (select count(*) from public.refus_courses r
                          where r.livreur_id = p.id and r.refuse_le >= t1 and r.refuse_le < t2),
               'derniere', (select max(c.paye_le) from public.commande_lignes l
                              join public.commandes c on c.id = l.commande_id
                             where l.livreur_id = p.id and c.etat = 'payee'),
               'gains', case when argent then
                 (select coalesce(sum(g.montant), 0) from public.gains_livreurs g
                   where g.livreur_id = p.id and g.credite_le >= t1 and g.credite_le < t2) end) as j
        from public.profils p
        cross join lateral (
          select count(distinct l.commande_id) as courses,
                 count(distinct l.commande_id) filter (where l.etat = 'remise') as livrees
            from public.commande_lignes l
            join public.commandes c on c.id = l.commande_id
           where l.livreur_id = p.id and c.etat = 'payee' and c.paye_le >= t1 and c.paye_le < t2) k
       where p.role = 'livreur') x));
end $$;

/** La fiche d'un livreur : qui il est, ses chiffres, ses courses, ses
    refus, et l'historique de ses blocages. */
create or replace function public.rh_livreur_fiche(livreur uuid, depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  d1 date := coalesce(depuis, aujourdhui - 29);
  d2 date := coalesce(jusqu, aujourdhui);
  t1 timestamptz;
  t2 timestamptz;
  argent boolean := public.rh_est_admin() or public.est_super();
  p public.profils;
  chiffres jsonb;
  courses jsonb;
begin
  if not public.rh_voit_livreurs() then
    raise exception 'Votre compte n''a pas accès aux livreurs';
  end if;
  if d2 < d1 then
    raise exception 'La fin de la période précède son début';
  end if;
  if d2 - d1 > 1100 then
    raise exception 'Choisissez une période de trois ans au plus';
  end if;
  select * into p from public.profils x where x.id = livreur and x.role = 'livreur';
  if not found then
    raise exception 'Livreur introuvable';
  end if;
  t1 := d1::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (d2 + 1)::timestamp at time zone 'Africa/Porto-Novo';

  -- Une course = une commande qu'il porte. Son étape : la moins avancée
  -- de ses articles encore valables.
  with k as (
    select c.id, c.numero, c.paye_le,
           min(l.recu_le) as recu_le, max(l.confirme_le) as confirme_le,
           coalesce((array['nouvelle', 'vue', 'preparee', 'en_livraison', 'remise'])[
             min(array_position(array['nouvelle', 'vue', 'preparee', 'en_livraison', 'remise'], l.etat))],
             'annulee') as etat,
           string_agg(distinct b.nom, ', ') as boutiques
      from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
      left join public.boutiques b on b.id = l.boutique_id
     where l.livreur_id = livreur and c.etat = 'payee' and c.paye_le >= t1 and c.paye_le < t2
     group by c.id, c.numero, c.paye_le
  )
  select jsonb_build_object(
           'courses', count(*),
           'livrees', count(*) filter (where etat = 'remise'),
           'en_cours', count(*) filter (where etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')),
           'annulees', count(*) filter (where etat = 'annulee'),
           'confirmees', count(*) filter (where confirme_le is not null),
           'delai_prise_minutes', round(avg(extract(epoch from (recu_le - paye_le)) / 60)
                                         filter (where recu_le >= paye_le)),
           'delai_livraison_heures', round((avg(extract(epoch from (confirme_le - paye_le)) / 3600)
                                         filter (where confirme_le >= paye_le))::numeric, 1)),
         coalesce(jsonb_agg(jsonb_build_object(
           'commande', id, 'numero', numero, 'paye_le', paye_le, 'boutiques', boutiques,
           'etat', etat, 'recu_le', recu_le, 'confirme_le', confirme_le,
           'gain', case when argent then
             (select sum(g.montant) from public.gains_livreurs g
               where g.commande_id = k.id and g.livreur_id = livreur) end)
           order by paye_le desc), '[]')
    into chiffres, courses
    from k;

  chiffres := chiffres || jsonb_build_object(
    'refus', (select count(*) from public.refus_courses r
               where r.livreur_id = livreur and r.refuse_le >= t1 and r.refuse_le < t2),
    'gains', case when argent then
      (select coalesce(sum(g.montant), 0) from public.gains_livreurs g
        where g.livreur_id = livreur and g.credite_le >= t1 and g.credite_le < t2) end,
    'encaisse', case when argent then
      (select coalesce(sum(e.montant), 0) from public.encaissements e
        where e.livreur_id = livreur and e.encaisse_le >= t1 and e.encaisse_le < t2) end,
    'contestes', (select count(*) from public.encaissements e
                   where e.livreur_id = livreur and e.conteste_le is not null
                     and e.encaisse_le >= t1 and e.encaisse_le < t2));

  return jsonb_build_object(
    'periode', jsonb_build_object('depuis', d1, 'jusqu', d2),
    'droits', jsonb_build_object('argent', argent, 'bloquer', argent),
    'livreur', jsonb_build_object(
      'id', p.id,
      'nom', coalesce(nullif(btrim(p.nom), ''), p.email, 'Livreur'),
      'tel', coalesce(p.tel, ''),
      'vehicule', coalesce(p.vehicule, 'moto'),
      'boutique', (select b.nom from public.boutiques b where b.id = p.boutique_id),
      'actif', p.actif,
      'valide', exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id),
      'bloque', p.courses_bloquees,
      'cree_le', p.cree_le,
      'en_course', public.livreur_en_course(p.id),
      'position', (select jsonb_build_object('adresse', pl.adresse, 'le', pl.enregistre_le)
                     from public.positions_livreurs pl where pl.profil_id = p.id)),
    'chiffres', chiffres,
    'courses', (select coalesce(jsonb_agg(x order by x ->> 'paye_le' desc), '[]')
                  from (select x from jsonb_array_elements(courses) x limit 50) y),
    'refus', (select coalesce(jsonb_agg(jsonb_build_object(
                 'numero', c.numero, 'boutique', b.nom, 'motif', r.motif, 'le', r.refuse_le)
                 order by r.refuse_le desc), '[]')
                from (select * from public.refus_courses r0
                       where r0.livreur_id = livreur and r0.refuse_le >= t1 and r0.refuse_le < t2
                       order by r0.refuse_le desc limit 20) r
                left join public.commandes c on c.id = r.commande_id
                left join public.boutiques b on b.id = r.boutique_id),
    'blocages', (select coalesce(jsonb_agg(jsonb_build_object(
                   'bloque', x.bloque, 'motif', x.motif, 'par', x.par_nom, 'le', x.le)
                   order by x.le desc, x.id desc), '[]')
                  from public.livreurs_blocages x where x.profil_id = livreur));
end $$;

/** Bloquer ou débloquer un livreur : l'administration seule. Bloqué, il
    ne reçoit plus de course ; ses courses pas encore parties retournent
    aux boutiques. Rend le nombre de parts de commande retirées. */
create or replace function public.rh_bloquer_livreur(livreur uuid, bloquer boolean, motif text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  pourquoi text := left(btrim(coalesce(motif, '')), 300);
  p        public.profils;
  auteur   text;
  porteur  text;
  c        record;
  parts    record;
  annonce  boolean;
  liberees int := 0;
begin
  if not (public.rh_est_admin() or public.est_super()) then
    raise exception 'Seule l''administration bloque ou débloque un livreur';
  end if;
  if bloquer is null then
    raise exception 'Bloquer ou débloquer ?';
  end if;
  select * into p from public.profils x where x.id = livreur and x.role = 'livreur' for update;
  if not found then
    raise exception 'Livreur introuvable';
  end if;
  if p.courses_bloquees = bloquer then
    raise exception '%', case when bloquer then 'Ce livreur est déjà bloqué' else 'Ce livreur n''est pas bloqué' end;
  end if;
  if bloquer and length(pourquoi) < 3 then
    raise exception 'Dites pourquoi vous bloquez ce livreur';
  end if;
  select nullif(btrim(e.prenoms || ' ' || e.nom), '') into auteur
    from public.rh_employes e where e.id = public.rh_moi();
  auteur := coalesce(auteur, (select nullif(btrim(x.nom), '') from public.profils x where x.id = auth.uid()),
                     'Superadministrateur');
  porteur := coalesce(nullif(btrim(p.nom), ''), 'Le livreur');

  perform set_config('bizzoo.blocage', 'oui', true);
  update public.profils set courses_bloquees = bloquer where id = livreur;
  perform set_config('bizzoo.blocage', '', true);
  insert into public.livreurs_blocages (profil_id, bloque, motif, par_compte, par_nom)
  values (livreur, bloquer, pourquoi, auth.uid(), auteur);

  if not bloquer then
    perform public.notifier(array[livreur], 'livreur_debloque', 'Courses rétablies',
      'BIZZOO vous propose de nouveau des courses.', '#/livraisons', null, null, true);
    return jsonb_build_object('liberees', 0);
  end if;

  -- SES COURSES PAS ENCORE PARTIES retournent aux boutiques, comme s'il
  -- les avait refusées (refuser_course) — sans les compter comme ses refus.
  for c in
    select distinct l.commande_id, cm.numero, cm.client_id
      from public.commande_lignes l
      join public.commandes cm on cm.id = l.commande_id
     where l.livreur_id = livreur and l.etat in ('nouvelle', 'vue', 'preparee')
  loop
    select exists (select 1 from public.commande_lignes l
                    where l.commande_id = c.commande_id and l.livreur_id = livreur and l.recu_le is not null)
      into annonce;
    -- Une nouvelle course, de nouvelles nouvelles (voir refuser_course).
    update public.notifications n
       set type = n.type || '_avant_' || n.id
     where n.commande_id = c.commande_id
       and n.type in ('course_confiee', 'course_acceptee', 'course_refusee');
    perform set_config('bizzoo.livraison', 'oui', true);
    perform set_config('bizzoo.refus', 'oui', true);
    for parts in
      with retirees as (
        update public.commande_lignes l
           set livreur_id = null, recu_le = null
         where l.commande_id = c.commande_id and l.livreur_id = livreur
           and l.etat in ('nouvelle', 'vue', 'preparee')
        returning l.boutique_id
      )
      select distinct boutique_id from retirees
    loop
      liberees := liberees + 1;
      perform public.notifier(public.equipe_de(parts.boutique_id), 'course_refusee',
        'Course à confier de nouveau — ' || coalesce(c.numero, ''),
        porteur || ' ne prend plus de course pour BIZZOO. Confiez-la à un autre livreur.',
        '#/commandes/' || c.commande_id, c.commande_id, parts.boutique_id, true);
    end loop;
    perform set_config('bizzoo.refus', '', true);
    perform set_config('bizzoo.livraison', '', true);
    if annonce and c.client_id is not null then
      perform public.notifier(array[c.client_id], 'course_refusee',
        'Votre livreur a changé',
        'Commande ' || coalesce(c.numero, '') || ' : ' || porteur ||
          ' ne peut pas la livrer. Un autre livreur va la prendre ; vous recevrez son nom et son numéro.',
        '#/commande/' || c.commande_id, c.commande_id, null, true);
    end if;
  end loop;

  perform public.notifier(array[livreur], 'livreur_bloque', 'Courses suspendues',
    'BIZZOO ne vous propose plus de course pour le moment. Rapprochez-vous de BIZZOO.' ||
      case when liberees > 0 then ' Vos courses pas encore parties ont été retirées.' else '' end,
    '#/livraisons', null, null, true);
  return jsonb_build_object('liberees', liberees);
end $$;

revoke all on function public.profils_garde_blocage() from public, anon, authenticated;
revoke all on function public.rh_voit_livreurs() from public, anon;
grant execute on function public.rh_voit_livreurs() to authenticated, service_role;
revoke all on function public.rh_livreurs(date, date) from public, anon;
grant execute on function public.rh_livreurs(date, date) to authenticated, service_role;
revoke all on function public.rh_livreur_fiche(uuid, date, date) from public, anon;
grant execute on function public.rh_livreur_fiche(uuid, date, date) to authenticated, service_role;
revoke all on function public.rh_bloquer_livreur(uuid, boolean, text) from public, anon;
grant execute on function public.rh_bloquer_livreur(uuid, boolean, text) to authenticated, service_role;
