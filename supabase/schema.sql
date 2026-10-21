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
    or (public.est_admin_bizzoo() and role = 'livreur'));

-- Créer, modifier, supprimer un compte : le superadministrateur sans
-- limite ; l'administrateur seulement des MODÉRATEURS et des LIVREURS
-- (3.59.0) de SA boutique — il ne se nomme pas de pairs et ne touche pas
-- à ses supérieurs.
create policy "profils ajout admin" on public.profils
  for insert to authenticated with check (
    public.est_super()
    or (public.est_admin() and role in ('moderateur', 'livreur')
        and boutique_id is not null and boutique_id = public.boutique_du_compte())
    -- L'administrateur de BIZZOO crée des livreurs, et rien d'autre.
    or (public.est_admin_bizzoo() and role = 'livreur'));
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
    or (public.est_admin_bizzoo() and role = 'livreur'))
  with check (
    public.est_super()
    -- (3.59.0) Un modérateur ou un livreur de SA boutique — jamais un
    -- administrateur.
    or (public.est_admin() and role in ('moderateur', 'livreur')
        and boutique_id is not null and boutique_id = public.boutique_du_compte())
    -- Un livreur reste un livreur : l'administrateur de BIZZOO ne fait
    -- de personne un administrateur ni un modérateur.
    or (public.est_admin_bizzoo() and role = 'livreur'));
create policy "profils suppression admin" on public.profils
  for delete to authenticated using (
    (public.est_super() and not public.est_mon_createur(id))
    or (public.est_admin() and role in ('moderateur', 'livreur')
        and boutique_id is not null and boutique_id = public.boutique_du_compte())
    or (public.est_admin_bizzoo() and role = 'livreur'));

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
create or replace function public.gere_le_compte(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  -- (3.59.0) Jamais sur celui qui vous a créé, ni plus haut.
  select not public.est_mon_createur(cible) and (public.est_super()
      or (public.est_admin() and exists (
            select 1 from public.profils p
             where p.id = cible and p.role in ('moderateur', 'livreur')
               and p.boutique_id is not null
               and p.boutique_id = public.boutique_du_compte())));
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
             greatest(0, coalesce(c.verse, c.acompte, c.total))::numeric as paye
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
begin
  if not public.peut_agir_sur(boutique) then
    raise exception 'Cette commande ne concerne pas votre boutique';
  end if;

  -- « livreur » nul : on retire l'attribution. Une boutique doit pouvoir
  -- reprendre une course confiée par erreur.
  if livreur is not null then
    select p.role, (p.boutique_id is null) into rang, bizzoo from public.profils p
     where p.id = livreur and p.actif
       and (public.est_super()
            or public.est_compte_enseigne()
            -- Le livreur de BIZZOO : aucune boutique, donc toutes.
            or p.boutique_id is null
            or p.boutique_id = public.boutique_du_compte());
    if rang is distinct from 'livreur' then
      raise exception 'Ce compte n''est pas un livreur de votre boutique ni de BIZZOO';
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
     and l.boutique_id = boutique
     -- (3.59.0) En secours de la demande envoyée à tous les livreurs : la
     -- boutique peut confier dès le paiement, sans attendre le colis.
     and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')
     and exists (select 1 from public.commandes c where c.id = l.commande_id and c.etat = 'payee');
  get diagnostics combien = row_count;

  -- LE LIVREUR DE BIZZOO : les produits des autres boutiques aussi. Sans
  -- prendre une part déjà confiée au livreur d'une autre boutique.
  if bizzoo and combien > 0 then
    update public.commande_lignes l
       set livreur_id = livreur, recu_le = null
     where l.commande_id = commande
       and l.boutique_id <> boutique
       and l.livreur_id is null
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
  if c.parts is not null and c.parts ? boutique then
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
      'indicatif', coalesce(nullif(c.client_indicatif, ''), '229')),
    'devise', coalesce(c.devise, 'FCFA'),
    'frais', coalesce(frais, 0),
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
create or replace function public.candidats_course(commande text)
returns uuid[]
language plpgsql stable security definer set search_path = public as $$
declare
  boutiques text[];
  qui       uuid[];
begin
  select array_agg(distinct l.boutique_id) into boutiques
    from public.commande_lignes l
   where l.commande_id = commande and l.etat <> 'annulee' and l.boutique_id is not null;
  if boutiques is null then return '{}'; end if;
  if array_length(boutiques, 1) = 1 then
    select array_agg(p.id order by p.id) into qui
      from public.profils p
     where p.role = 'livreur' and p.actif and p.boutique_id = boutiques[1]
       and exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id);
    if qui is not null then return qui; end if;
  end if;
  select array_agg(p.id order by p.id) into qui
    from public.profils p
   where p.role = 'livreur' and p.actif and p.boutique_id is null
     and exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id);
  return coalesce(qui, '{}');
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
  return jsonb_build_object(
    'numero', premiere -> 'numero',
    'groupee', jsonb_array_length(retraits) > 1,
    'retraits', retraits,
    'livraison', premiere -> 'livraison',
    'devise', premiere -> 'devise',
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
    'Frais de livraison : ' || public.montant_lisible((f ->> 'frais')::numeric, f ->> 'devise') || E'\n' ||
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
create or replace function public.creer_commande(
  client jsonb, articles jsonb, code text default '',
  avec_acompte boolean default false, avec_frais boolean default false)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
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
begin
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

  -- Un compte de l'équipe ne passe pas commande pour lui-même : il agirait
  -- avec les droits d'une boutique sur une commande qui lui appartient.
  if moi is not null and not exists (select 1 from public.clients c where c.id = moi) then
    moi    := null;
    equipe := true;
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
  if moi is null and public.compte_exige() then
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
  if coalesce(avec_acompte, false) or coalesce(avec_frais, false) then
    perform set_config('bizzoo.interne', 'oui', true);
    if coalesce(avec_frais, false) then
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
             case when coalesce(avec_frais, false) then greatest(0, b.frais_livraison) else 0 end as frais,
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
             select sum((v ->> 'acompte')::bigint) from jsonb_each(les_parts) e(k, v)), 0))
      into manquant
      from public.commandes c where c.id = nouvelle;
    if manquant > 0 and les_parts is not null then
      select jsonb_set(les_parts, array[k, 'acompte'],
               to_jsonb(least((v ->> 'du')::bigint, (v ->> 'acompte')::bigint + manquant)))
        into les_parts
        from jsonb_each(les_parts) e(k, v)
       order by (v ->> 'du')::bigint desc limit 1;
    end if;

    update public.commandes c
       set parts = les_parts,
           acompte = least(c.total, coalesce((
                       select sum((v ->> 'acompte')::bigint) from jsonb_each(les_parts) e(k, v)), c.total)),
           -- Le taux affiché : ce que représente l'acompte du total.
           taux_acompte = case when c.total <= 0 then 100
                               else least(100, greatest(1, round(100.0 * coalesce((
                                 select sum((v ->> 'acompte')::bigint) from jsonb_each(les_parts) e(k, v)),
                                 c.total) / c.total)))::int end
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

revoke all on function public.creer_commande(jsonb, jsonb, text, boolean, boolean) from public;
grant execute on function public.creer_commande(jsonb, jsonb, text, boolean, boolean) to anon, authenticated;

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
                        where x.commande_id = c.id));
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
-- reçoit l'ARGENT qui entre et les INCIDENTS ; les étapes
-- intermédiaires restent lisibles sur l'écran des commandes.
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
  sexe            text not null check (sexe in ('M', 'F')),
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
                  check (etat in ('en_attente', 'actif', 'refuse', 'sorti')),
  motif_refus     text not null default '',
  date_sortie     date,
  cree_par        uuid,
  cree_le         timestamptz not null default now(),
  valide_par      uuid,
  valide_le       timestamptz
);
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

create or replace function public.rh_peut_decaisser() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and peut_decaisser);
$$;

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

-- ---------- Les verrous de la fiche employé ----------
-- Les règles RLS disent QUI écrit ; ce déclencheur dit QUOI. Les
-- décisions (valider, refuser, faire sortir, rattacher un compte) ne
-- passent que par leurs fonctions, qui posent le drapeau « rh.decision ».
create or replace function public.rh_employe_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  decision boolean := coalesce(current_setting('rh.decision', true), '') = 'oui';
  ceo_connecte boolean := public.rh_est_ceo();
  admin_connecte boolean := public.rh_est_admin();
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
    libres := array['telephone', 'adresse', 'email_perso'];
    if (to_jsonb(new) - libres) is distinct from (to_jsonb(old) - libres) then
      raise exception 'Vous ne pouvez modifier que votre téléphone, votre adresse et votre e-mail personnel';
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
  if new.profil_id is distinct from old.profil_id or new.etat <> 'actif' then
    update public.rh_profils set responsable_id = null
     where responsable_id = new.id
       and (new.etat <> 'actif' or id is distinct from new.profil_id);
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
   where id = employe and etat = 'actif';
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

/** L'annuaire : qui est qui, sans le salaire. Pour tout employé en poste. */
create or replace function public.rh_annuaire()
returns table (id uuid, matricule text, nom text, prenoms text, sexe text, poste text,
               profil_id uuid, profil text, email_pro text, telephone text,
               administration boolean, ceo boolean, responsable boolean, a_un_compte boolean)
language sql stable security definer set search_path = public as $$
  select e.id, e.matricule, e.nom, e.prenoms, e.sexe, e.poste, e.profil_id, coalesce(p.nom, ''),
         e.email_pro, e.telephone, e.administration, e.ceo,
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

/** Peut-on écrire à cette personne ? À son profil, à son responsable,
    à l'administration ; l'administration écrit à tous. */
create or replace function public.rh_peut_ecrire_a(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.rh_moi() is not null and cible <> public.rh_moi() and exists (
    select 1 from public.rh_employes c
     where c.id = cible and c.etat = 'actif'
       and (public.rh_est_admin()
            or c.administration or c.ceo
            or (c.profil_id is not null and c.profil_id = public.rh_mon_profil())
            or public.rh_responsable_de(c.profil_id)
            or exists (select 1 from public.rh_profils p
                        where p.id = public.rh_mon_profil() and p.responsable_id = c.id)));
$$;

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
  if conversation !~ '^[pd]:[0-9a-f-]{36}\Z' then
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
     where moi.id is not null and (moi.admin or public.rh_membre_de(p.id))
  ),
  personnes as (
    select distinct case when m.auteur_id = moi.id then m.destinataire_id else m.auteur_id end as autre
      from public.rh_messages m, moi
     where m.destinataire_id is not null and (m.auteur_id = moi.id or m.destinataire_id = moi.id)
  ),
  prives as (
    select 'd:' || e.id as cle, 'personne'::text as genre, e.id as cible,
           btrim(e.prenoms || ' ' || e.nom) as titre
      from personnes x join public.rh_employes e on e.id = x.autre
  ),
  toutes as (select * from groupes union all select * from prives)
  select t.cle, t.genre, t.cible, t.titre, d.texte, d.cree_le,
         (select count(*)::int from public.rh_messages m, moi
           where m.auteur_id <> moi.id
             and m.cree_le > coalesce((select l.lu_le from public.rh_lectures l
                                        where l.employe_id = moi.id and l.conversation = t.cle),
                                      '-infinity')
             and ((t.genre = 'profil' and m.profil_id = t.cible)
               or (t.genre = 'personne' and m.auteur_id = t.cible and m.destinataire_id = moi.id)))
    from toutes t
    left join lateral (
      select m.texte, m.cree_le from public.rh_messages m, moi
       where (t.genre = 'profil' and m.profil_id = t.cible)
          or (t.genre = 'personne' and ((m.auteur_id = t.cible and m.destinataire_id = moi.id)
                                     or (m.auteur_id = moi.id and m.destinataire_id = t.cible)))
       order by m.id desc limit 1) d on true
   order by d.cree_le desc nulls last, t.titre;
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
  profil_id          uuid not null references public.rh_profils(id) on delete restrict,
  demandeur_id       uuid references public.rh_employes(id) on delete set null,
  objet              text not null check (length(btrim(objet)) > 0),
  details            text not null default '',
  montant            bigint not null check (montant > 0),
  statut             text not null default 'demandee'
                     check (statut in ('demandee', 'approuvee', 'refusee', 'decaissee', 'annulee')),
  cree_le            timestamptz not null default now(),
  decision_par       uuid,
  decision_le        timestamptz,
  motif_decision     text not null default '',
  decaisse_par       uuid,
  decaisse_le        timestamptz,
  mode_decaissement  text check (mode_decaissement in ('especes', 'virement', 'mobile_money', 'cheque')),
  reference          text not null default ''
);

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
    new.statut := 'demandee';
    new.cree_le := now();
    new.decision_par := null; new.decision_le := null; new.motif_decision := '';
    new.decaisse_par := null; new.decaisse_le := null; new.mode_decaissement := null;
    new.reference := '';
    return new;
  end if;
  if old.statut <> 'demandee' then
    raise exception 'Une demande déjà tranchée ne se modifie plus';
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
   where id = depense and statut = 'demandee';
  if not found then
    raise exception 'Cette dépense n''attend pas de décision';
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
  if mode not in ('especes', 'virement', 'mobile_money', 'cheque') then
    raise exception 'Mode de décaissement inconnu';
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
   where id = depense and statut = 'demandee' and demandeur_id = public.rh_moi();
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
  if e.etat not in ('actif', 'sorti') or d2 < d1 then
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
            where (etat = 'actif' or (etat = 'sorti' and date_sortie >= debut))
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
                        and (x.etat = 'actif' or (x.etat = 'sorti' and x.date_sortie >= debut))
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
 * La paie de fin de mois, sans que personne n'y pense : le dernier jour
 * du mois (heure du Bénin), les fiches du mois sont calculées ; et le
 * mois précédent l'est aussi s'il a été oublié. Appelée par pg_cron
 * chaque soir du 28 au 31, et par l'application à l'ouverture.
 */
create or replace function public.rh_generer_paie_auto() returns int
language plpgsql security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  courant date := date_trunc('month', aujourdhui)::date;
  precedent date := (date_trunc('month', aujourdhui) - interval '1 month')::date;
  combien int := 0;
begin
  if not exists (select 1 from public.rh_fiches_paie where mois = precedent) then
    combien := combien + public.rh_generer_paie_interne(precedent);
  end if;
  if extract(day from aujourdhui + 1) = 1 then
    combien := combien + public.rh_generer_paie_interne(courant);
  end if;
  return combien;
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

create or replace function public.rh_payer_fiche(fiche uuid, mode text, reference text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_peut_decaisser() then
    raise exception 'Votre compte n''est pas habilité à payer';
  end if;
  if mode not in ('especes', 'virement', 'mobile_money', 'cheque') then
    raise exception 'Mode de paiement inconnu';
  end if;
  update public.rh_fiches_paie
     set statut = 'payee', paye_par = public.rh_moi(), paye_le = now(),
         mode_paiement = mode, reference = btrim(coalesce(rh_payer_fiche.reference, ''))
   where id = fiche and statut = 'validee';
  if not found then
    raise exception 'Seule une fiche validée par le CEO se paie';
  end if;
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
      'ceo', v_ceo, 'administration', v_admin, 'peut_decaisser', moi.peut_decaisser,
      'profil_id', moi.profil_id,
      'profil', (select nom from public.rh_profils where id = moi.profil_id),
      'responsable_de', to_jsonb(mes_profils)),
    'compteurs', jsonb_build_object(
      'employes_a_valider', case when v_ceo then
        (select count(*) from public.rh_employes where etat = 'en_attente') else 0 end,
      'missions_a_repondre',
        (select count(*) from public.rh_missions where statut = 'proposee' and profil_id = any(mes_profils)),
      'missions_en_cours',
        (select count(*) from public.rh_missions
          where statut in ('acceptee', 'a_reprendre')
            and (profil_id = any(mes_profils) or profil_id = moi.profil_id or v_admin)),
      'missions_en_retard',
        (select count(*) from public.rh_missions
          where statut in ('acceptee', 'a_reprendre') and echeance < aujourdhui
            and (profil_id = any(mes_profils) or v_admin)),
      'missions_a_cloturer', case when v_admin then
        (select count(*) from public.rh_missions where statut = 'rapport_remis') else 0 end,
      'rapports_a_valider', case when v_ceo then
        (select count(*) from public.rh_rapports where statut = 'publie') else 0 end,
      'depenses_a_approuver', case when v_ceo then
        (select count(*) from public.rh_depenses where statut = 'demandee') else 0 end,
      'depenses_a_decaisser', case when moi.peut_decaisser then
        (select count(*) from public.rh_depenses where statut = 'approuvee') else 0 end,
      'baremes_a_valider', case when v_ceo then
        (select count(*) from public.rh_cotisations where actif and not valide)
        + (select count(*) from public.rh_reglages_paie r
            where not r.impot_valide and exists (select 1 from public.rh_tranches_impot)) else 0 end,
      'fiches_a_valider', case when v_ceo then
        (select count(*) from public.rh_fiches_paie
          where statut = 'calculee'
            and mois < date_trunc('month', aujourdhui + 1)::date) else 0 end,
      'fiches_a_payer', case when moi.peut_decaisser then
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
  for select to authenticated using (public.rh_est_admin() or compte_id = auth.uid());
create policy "rh employes ajout" on public.rh_employes
  for insert to authenticated with check (public.rh_est_admin());
create policy "rh employes modification" on public.rh_employes
  for update to authenticated
  using (public.rh_est_admin() or (compte_id = auth.uid() and etat = 'actif'))
  with check (public.rh_est_admin() or (compte_id = auth.uid() and etat = 'actif'));
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
    (profil_id is not null and (public.rh_est_admin() or public.rh_membre_de(profil_id)))
    or (destinataire_id is not null
        and (auteur_id = public.rh_moi() or destinataire_id = public.rh_moi())));
create policy "rh messages envoi" on public.rh_messages
  for insert to authenticated with check (
    (profil_id is not null and (public.rh_est_admin() or public.rh_membre_de(profil_id)))
    or (destinataire_id is not null and public.rh_peut_ecrire_a(destinataire_id)));

drop policy if exists "rh missions lecture" on public.rh_missions;
drop policy if exists "rh missions creation" on public.rh_missions;
drop policy if exists "rh missions modification" on public.rh_missions;
drop policy if exists "rh missions suppression" on public.rh_missions;
create policy "rh missions lecture" on public.rh_missions
  for select to authenticated using (public.rh_est_admin() or public.rh_membre_de(profil_id));
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
    or (public.rh_membre_de(profil_id) and statut = 'valide'));
create policy "rh rapports creation" on public.rh_rapports
  for insert to authenticated with check (public.rh_responsable_de(profil_id));
create policy "rh rapports modification" on public.rh_rapports
  for update to authenticated
  using (auteur_id = public.rh_moi() and public.rh_responsable_de(profil_id))
  with check (auteur_id = public.rh_moi() and public.rh_responsable_de(profil_id));
create policy "rh rapports suppression" on public.rh_rapports
  for delete to authenticated using (auteur_id = public.rh_moi() and statut = 'brouillon');

drop policy if exists "rh depenses lecture" on public.rh_depenses;
drop policy if exists "rh depenses demande" on public.rh_depenses;
drop policy if exists "rh depenses modification" on public.rh_depenses;
create policy "rh depenses lecture" on public.rh_depenses
  for select to authenticated using (
    public.rh_est_admin()
    or demandeur_id = public.rh_moi()
    or public.rh_responsable_de(profil_id)
    or (public.rh_peut_decaisser() and statut in ('approuvee', 'decaissee')));
create policy "rh depenses demande" on public.rh_depenses
  for insert to authenticated with check (public.rh_responsable_de(profil_id));
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
-- n'est pas une promesse. L'habilité voit toutes les fiches validées :
-- c'est lui qui les paie.
create policy "rh fiches lecture" on public.rh_fiches_paie
  for select to authenticated using (
    public.rh_est_admin()
    or (statut <> 'calculee' and (employe_id = public.rh_moi() or public.rh_peut_decaisser())));

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
    'rh_decider_employe(uuid, boolean, text)', 'rh_sortie_employe(uuid, date, text)',
    'rh_rattacher_compte(uuid)', 'rh_devenir_ceo(text, text, text)', 'rh_annuaire()',
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
