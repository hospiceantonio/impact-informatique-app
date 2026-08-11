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

-- ---------- La boutique (une seule ligne) ----------
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
  facebook    text not null default '',
  instagram   text not null default '',
  tiktok      text not null default '',
  youtube     text not null default '',
  snapchat    text not null default '',
  latitude    double precision,               -- position de la boutique
  longitude   double precision,
  photos      text[] not null default '{}',   -- photos de la boutique
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

-- ---------- Catégories et sous-catégories ----------
create table if not exists public.categories (
  id      text primary key,
  nom     text not null,
  ordre   int  not null default 0,
  cree_le timestamptz not null default now()
);

create table if not exists public.sous_categories (
  id           text primary key,
  categorie_id text not null references public.categories(id) on delete cascade,
  nom          text not null,
  ordre        int  not null default 0
);
create index if not exists sous_categories_categorie
  on public.sous_categories(categorie_id);

-- ---------- Produits ----------
create table if not exists public.produits (
  id                text primary key,
  nom               text not null,
  reference         text not null default '',
  description       text not null default '',
  prix              bigint not null check (prix >= 0),
  ancien_prix       bigint,
  categorie_id      text not null references public.categories(id),
  sous_categorie_id text references public.sous_categories(id),
  disponible        boolean not null default true,
  en_avant          boolean not null default false,  -- 5 max (contrôlé par l'app admin)
  ordre_avant       int not null default 0,          -- ordre dans le slider client
  images            text[] not null default '{}',    -- chemins dans le bucket « produits »
  video             text not null default '',        -- vidéo de présentation (facultative)
  cree_le           timestamptz not null default now(),
  modifie_le        timestamptz not null default now()
);
-- Ajout de la colonne sur les bases déjà créées (sans risque).
alter table public.produits add column if not exists reference text not null default '';
alter table public.produits add column if not exists video text not null default '';

create index if not exists produits_categorie on public.produits(categorie_id);
create index if not exists produits_en_avant on public.produits(en_avant) where en_avant;

-- ---------- Ligne boutique par défaut ----------
insert into public.boutique (id) values (1) on conflict (id) do nothing;

-- Numéro WhatsApp de la boutique (rempli seulement s'il est vide :
-- la valeur saisie ensuite dans l'app admin est toujours prioritaire).
update public.boutique set whatsapp = '69842516', maj_le = now()
where id = 1 and whatsapp = '';

-- ---------- Sécurité : lecture publique, écriture connectée ----------
alter table public.boutique        enable row level security;
alter table public.categories      enable row level security;
alter table public.sous_categories enable row level security;
alter table public.produits        enable row level security;

drop policy if exists "lecture publique"  on public.boutique;
drop policy if exists "ecriture connectee" on public.boutique;
create policy "lecture publique"   on public.boutique        for select using (true);
create policy "ecriture connectee" on public.boutique        for all to authenticated using (true) with check (true);

drop policy if exists "lecture publique"  on public.categories;
drop policy if exists "ecriture connectee" on public.categories;
create policy "lecture publique"   on public.categories      for select using (true);
create policy "ecriture connectee" on public.categories      for all to authenticated using (true) with check (true);

drop policy if exists "lecture publique"  on public.sous_categories;
drop policy if exists "ecriture connectee" on public.sous_categories;
create policy "lecture publique"   on public.sous_categories for select using (true);
create policy "ecriture connectee" on public.sous_categories for all to authenticated using (true) with check (true);

drop policy if exists "lecture publique"  on public.produits;
drop policy if exists "ecriture connectee" on public.produits;
create policy "lecture publique"   on public.produits        for select using (true);
create policy "ecriture connectee" on public.produits        for all to authenticated using (true) with check (true);

-- ---------- Temps réel ----------
-- Permet à l'application client d'être prévenue dès qu'un produit change,
-- sans avoir à être fermée et rouverte. Sans risque à ré-exécuter.
do $$
declare
  t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['boutique', 'categories', 'sous_categories', 'produits'] loop
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

drop policy if exists "photos lecture publique"   on storage.objects;
drop policy if exists "photos ecriture connectee" on storage.objects;
drop policy if exists "photos maj connectee"      on storage.objects;
drop policy if exists "photos suppression connectee" on storage.objects;
create policy "photos lecture publique" on storage.objects
  for select using (bucket_id = 'produits');
create policy "photos ecriture connectee" on storage.objects
  for insert to authenticated with check (bucket_id = 'produits');
create policy "photos maj connectee" on storage.objects
  for update to authenticated using (bucket_id = 'produits');
create policy "photos suppression connectee" on storage.objects
  for delete to authenticated using (bucket_id = 'produits');

-- ---------- Rayons de départ d'une boutique informatique ----------
insert into public.categories (id, nom, ordre) values
  ('cat_ordinateurs',  'Ordinateurs',            1),
  ('cat_imprimantes',  'Imprimantes & scanners', 2),
  ('cat_consommables', 'Consommables',           3),
  ('cat_accessoires',  'Accessoires',            4),
  ('cat_stockage',     'Stockage',               5),
  ('cat_reseau',       'Réseau & énergie',       6)
on conflict (id) do nothing;

insert into public.sous_categories (id, categorie_id, nom, ordre) values
  ('sc_portables',      'cat_ordinateurs',  'Ordinateurs portables',   1),
  ('sc_bureau',         'cat_ordinateurs',  'Ordinateurs de bureau',   2),
  ('sc_toutenun',       'cat_ordinateurs',  'Tout-en-un',              3),
  ('sc_jetencre',       'cat_imprimantes',  'Jet d''encre',            1),
  ('sc_laser',          'cat_imprimantes',  'Laser',                   2),
  ('sc_multifonctions', 'cat_imprimantes',  'Multifonctions',          3),
  ('sc_encres',         'cat_consommables', 'Encres & cartouches',     1),
  ('sc_toners',         'cat_consommables', 'Toners',                  2),
  ('sc_papier',         'cat_consommables', 'Papier & rames',          3),
  ('sc_claviers_souris','cat_accessoires',  'Claviers & souris',       1),
  ('sc_sacoches',       'cat_accessoires',  'Sacoches & sacs à dos',   2),
  ('sc_casques',        'cat_accessoires',  'Casques & audio',         3),
  ('sc_cles_usb',       'cat_stockage',     'Clés USB',                1),
  ('sc_disques',        'cat_stockage',     'Disques durs & SSD',      2),
  ('sc_cartes',         'cat_stockage',     'Cartes mémoire',          3),
  ('sc_wifi',           'cat_reseau',       'Routeurs & wifi',         1),
  ('sc_cables',         'cat_reseau',       'Câbles & adaptateurs',    2),
  ('sc_onduleurs',      'cat_reseau',       'Onduleurs',               3)
on conflict (id) do nothing;

-- Références des produits d'exemple déjà en base (seulement si vides).
update public.produits set reference = 'IMP-0001' where id = 'prod_hp15' and reference = '';
update public.produits set reference = 'IMP-0002' where id = 'prod_epson_l3250' and reference = '';
update public.produits set reference = 'IMP-0003' where id = 'prod_apc650' and reference = '';
update public.produits set reference = 'IMP-0004' where id = 'prod_usb_kingston64' and reference = '';
update public.produits set reference = 'IMP-0005' where id = 'prod_toner_85a' and reference = '';
update public.produits set reference = 'IMP-0006' where id = 'prod_logitech_m185' and reference = '';

-- ---------- Produits d'exemple (supprimables depuis l'app admin) ----------
insert into public.produits
  (id, nom, description, prix, ancien_prix, categorie_id, sous_categorie_id,
   disponible, en_avant, ordre_avant) values
  ('prod_hp15', 'Ordinateur portable HP 15',
   e'Écran 15,6" HD, processeur Intel Core i5, 8 Go de RAM, SSD 512 Go, Windows 11.\nIdéal pour le bureau, les études et la navigation.\nGarantie boutique, livraison possible à Cotonou.',
   385000, null, 'cat_ordinateurs', 'sc_portables', true, true, 1),
  ('prod_epson_l3250', 'Imprimante Epson EcoTank L3250',
   e'Multifonction 3 en 1 (impression, copie, scan) à réservoirs d''encre rechargeables.\nWifi intégré, impression depuis le téléphone.\nJusqu''à 4 500 pages noir avec un seul flacon.',
   145000, 165000, 'cat_imprimantes', 'sc_multifonctions', true, true, 2),
  ('prod_apc650', 'Onduleur APC Back-UPS 650 VA',
   e'Protège votre ordinateur des coupures et variations de courant.\nAutonomie suffisante pour enregistrer votre travail et éteindre proprement.\nPrises multiples, protection téléphone/ADSL.',
   42000, null, 'cat_reseau', 'sc_onduleurs', true, true, 3),
  ('prod_usb_kingston64', 'Clé USB Kingston 64 Go',
   e'Clé USB 3.2 rapide et fiable pour vos documents, photos et vidéos.\nCompatible ordinateur, TV et autoradio.',
   6500, null, 'cat_stockage', 'sc_cles_usb', true, true, 4),
  ('prod_toner_85a', 'Toner HP 85A (CE285A)',
   e'Cartouche de toner noir d''origine pour HP LaserJet P1102, M1132, M1212…\nEnviron 1 600 pages.',
   28000, 32000, 'cat_consommables', 'sc_toners', true, true, 5),
  ('prod_logitech_m185', 'Souris sans fil Logitech M185',
   e'Souris sans fil compacte avec récepteur USB nano.\nJusqu''à 12 mois d''autonomie avec une pile AA.',
   8500, null, 'cat_accessoires', 'sc_claviers_souris', true, false, 0)
on conflict (id) do nothing;
