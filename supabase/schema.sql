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
  couleur     text not null default '#1176D8',
  logo        text not null default '',        -- image dans le bucket (remplace l'icône)
  actif       boolean not null default true,   -- une boutique fermée disparaît du client
  ordre       int not null default 0,
  tel         text not null default '',
  whatsapp    text not null default '',
  indicatif   text not null default '229',
  devise      text not null default 'FCFA',
  adresse     text not null default '',
  horaires    text not null default '',
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
  cree_le     timestamptz not null default now(),
  maj_le      timestamptz not null default now()
);
alter table public.boutiques add column if not exists video text not null default '';
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
-- Les rayons appartiennent à une boutique : « Ordinateurs portables »
-- n'a rien à faire dans une boutique de cosmétiques.
create table if not exists public.categories (
  id          text primary key,
  boutique_id text references public.boutiques(id) on delete cascade,
  nom         text not null,
  ordre       int  not null default 0,
  cree_le     timestamptz not null default now()
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
  boutique_id       text references public.boutiques(id) on delete cascade,
  nom               text not null,
  reference         text not null default '',
  description       text not null default '',
  prix              bigint not null check (prix >= 0),
  ancien_prix       bigint,
  categorie_id      text not null references public.categories(id),
  sous_categorie_id text references public.sous_categories(id),
  stock             int not null default 0 check (stock >= 0),
  sur_commande      boolean not null default false, -- vendu sans stock : « Sur commande »
  disponible        boolean not null default true,  -- tenu à jour : sur_commande ou stock > 0
  en_avant          boolean not null default false,  -- 5 max (contrôlé par l'app admin)
  ordre_avant       int not null default 0,          -- ordre dans le slider client
  images            text[] not null default '{}',    -- chemins dans le bucket « produits »
  video             text not null default '',        -- vidéo de présentation (facultative)
  cree_le           timestamptz not null default now(),
  modifie_le        timestamptz not null default now()
);
-- Ajout des colonnes sur les bases déjà créées (sans risque).
alter table public.categories add column if not exists boutique_id text references public.boutiques(id) on delete cascade;
alter table public.produits   add column if not exists boutique_id text references public.boutiques(id) on delete cascade;
alter table public.produits add column if not exists reference text not null default '';
alter table public.produits add column if not exists video text not null default '';
alter table public.produits add column if not exists stock int not null default 0;
alter table public.produits add column if not exists sur_commande boolean not null default false;
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

create index if not exists produits_categorie on public.produits(categorie_id);
create index if not exists produits_en_avant on public.produits(en_avant) where en_avant;

-- ---------- Prix d'achat (table privée) ----------
-- Le prix grossiste ne regarde que la boutique : il vit dans sa propre
-- table, invisible avec la clé publique de l'application client. Le prix
-- affiché aux clients reste « produits.prix », calculé à partir d'ici.
--   prix public = prix_grossiste + taux %
--   taux_marge à null : c'est le taux de la boutique qui s'applique.
create table if not exists public.produits_prive (
  produit_id     text primary key references public.produits(id) on delete cascade,
  prix_grossiste bigint not null default 0 check (prix_grossiste >= 0),
  taux_marge     numeric(6,2),
  maj_le         timestamptz not null default now()
);

-- ---------- Slider de l'application client ----------
-- Les images que la boutique fait défiler en haut de l'écran d'accueil.
-- Elles sont choisies une par une : ce ne sont plus les produits mis en
-- avant. Une image peut renvoyer vers un produit (facultatif).
-- Chaque boutique compose le sien ; l'accueil du client les réunit tous.
create table if not exists public.slides (
  id          text primary key,
  boutique_id text references public.boutiques(id) on delete cascade,
  image       text not null default '',   -- chemin dans le bucket « produits »
  titre       text not null default '',   -- légende facultative posée sur l'image
  produit_id  text references public.produits(id) on delete set null,
  ordre       int not null default 0,
  actif       boolean not null default true,
  cree_le     timestamptz not null default now()
);
alter table public.slides add column if not exists boutique_id text references public.boutiques(id) on delete cascade;
create index if not exists slides_ordre on public.slides(ordre);

-- ---------- Tout le catalogue d'avant rejoint la première boutique ----------
-- Produits, rayons et images du slider : rien ne se perd, tout se range.
do $$
declare premiere text;
begin
  select id into premiere from public.boutiques order by ordre, cree_le limit 1;
  if premiere is null then return; end if;
  update public.categories set boutique_id = premiere where boutique_id is null;
  update public.produits   set boutique_id = premiere where boutique_id is null;
  update public.slides     set boutique_id = premiere where boutique_id is null;
end $$;

create index if not exists produits_boutique   on public.produits(boutique_id);
create index if not exists categories_boutique on public.categories(boutique_id);
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
          check (role in ('superadministrateur', 'administrateur', 'moderateur')),
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

-- Le rôle accepte désormais « superadministrateur ».
alter table public.profils drop constraint if exists profils_role_check;
alter table public.profils add constraint profils_role_check
  check (role in ('superadministrateur', 'administrateur', 'moderateur'));

-- Les administrateurs d'avant tenaient toute l'application : ils
-- deviennent superadministrateurs, sans quoi ils se retrouveraient
-- enfermés dans une boutique qu'ils n'ont pas.
update public.profils set role = 'superadministrateur'
 where role = 'administrateur' and boutique_id is null;

-- Rôle du compte connecté. « security definer » : la fonction lit la table
-- sans repasser par les règles RLS — sinon les règles s'appelleraient elles-mêmes.
create or replace function public.role_courant() returns text
language sql stable security definer set search_path = public as $$
  select role from public.profils where id = auth.uid() and actif;
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

-- Membre actif de l'équipe, quel que soit son rang.
create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select public.role_courant() is not null;
$$;

-- Peut-il retoucher un produit déjà au catalogue ? Les deux rangs
-- d'administrateur toujours ; le modérateur seulement si on le lui accorde.
create or replace function public.peut_modifier_produits() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role in ('superadministrateur', 'administrateur')
                       or peut_modifier_produits
                     from public.profils where id = auth.uid() and actif), false);
$$;

-- La boutique à laquelle le compte est rattaché. Null pour un
-- administrateur : il n'est enfermé nulle part.
create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils where id = auth.uid() and actif;
$$;

-- A-t-il le droit de toucher à ce qui appartient à cette boutique-là ?
-- Le superadministrateur partout ; les autres dans la leur seulement.
create or replace function public.peut_agir_sur(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or (public.est_equipe() and cible is not null
          and cible = public.boutique_du_compte());
$$;

-- Droits d'administration SUR cette boutique-là : le superadministrateur
-- partout, l'administrateur uniquement chez lui.
create or replace function public.administre(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or (public.est_admin() and cible is not null
          and cible = public.boutique_du_compte());
$$;

-- Les règles de sécurité, y compris celles du stockage des photos,
-- appellent ces fonctions au nom du compte connecté.
grant execute on function public.peut_modifier_produits() to authenticated;
grant execute on function public.role_courant() to authenticated;
grant execute on function public.est_admin() to authenticated;
grant execute on function public.est_equipe() to authenticated;
grant execute on function public.boutique_du_compte() to authenticated;
grant execute on function public.peut_agir_sur(text) to authenticated;
grant execute on function public.est_super() to authenticated;
grant execute on function public.administre(text) to authenticated;

-- Tout compte créé (par l'application ou dans le tableau de bord Supabase)
-- reçoit une fiche en attente : l'administrateur l'active et lui donne son rôle.
create or replace function public.profil_nouveau_compte() returns trigger
language plpgsql security definer set search_path = public as $$
begin
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

drop policy if exists "profils lecture" on public.profils;
drop policy if exists "profils ajout admin" on public.profils;
drop policy if exists "profils modification admin" on public.profils;
drop policy if exists "profils suppression admin" on public.profils;
-- Chacun voit sa fiche. Le superadministrateur voit toute l'enseigne ;
-- l'administrateur, l'équipe de sa boutique.
create policy "profils lecture" on public.profils
  for select to authenticated using (
    id = auth.uid()
    or public.est_super()
    or (public.est_admin() and boutique_id is not null
        and boutique_id = public.boutique_du_compte()));

-- Créer, modifier, supprimer un compte : le superadministrateur sans
-- limite ; l'administrateur seulement des MODÉRATEURS de SA boutique —
-- il ne se nomme pas de pairs et ne touche pas à ses supérieurs.
create policy "profils ajout admin" on public.profils
  for insert to authenticated with check (
    public.est_super()
    or (public.est_admin() and role = 'moderateur'
        and boutique_id is not null and boutique_id = public.boutique_du_compte()));
create policy "profils modification admin" on public.profils
  for update to authenticated
  using (
    public.est_super()
    or (public.est_admin() and role = 'moderateur'
        and boutique_id is not null and boutique_id = public.boutique_du_compte()))
  with check (
    public.est_super()
    or (public.est_admin() and role = 'moderateur'
        and boutique_id is not null and boutique_id = public.boutique_du_compte()));
create policy "profils suppression admin" on public.profils
  for delete to authenticated using (
    public.est_super()
    or (public.est_admin() and role = 'moderateur'
        and boutique_id is not null and boutique_id = public.boutique_du_compte()));

-- ---------- Gestion des comptes par l'administrateur ----------
-- Supprimer un compte ou changer son mot de passe demande des droits que
-- l'application n'a pas : sa clé est publiable, et la clé « service_role »
-- ne doit jamais quitter le serveur. Ces deux fonctions font le travail à
-- sa place, en vérifiant elles-mêmes qui appelle.

-- crypt() / gen_salt() servent à chiffrer le mot de passe comme le fait
-- Supabase lui-même.
create extension if not exists pgcrypto with schema extensions;

-- Qui a le droit d'agir sur ce compte-là ? Le superadministrateur sur
-- tous ; l'administrateur seulement sur les modérateurs de sa boutique.
create or replace function public.gere_le_compte(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or (public.est_admin() and exists (
            select 1 from public.profils p
             where p.id = cible and p.role = 'moderateur'
               and p.boutique_id is not null
               and p.boutique_id = public.boutique_du_compte()));
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
revoke all on function public.supprimer_compte(uuid) from public;
revoke all on function public.changer_mot_de_passe(uuid, text) from public;
grant execute on function public.supprimer_compte(uuid) to authenticated;
grant execute on function public.changer_mot_de_passe(uuid, text) to authenticated;

-- ---------- Journal des actions de l'application admin ----------
-- Qui a fait quoi, et quand. Lisible uniquement par l'administrateur.
create table if not exists public.journal (
  id          bigint generated always as identity primary key,
  fait_le     timestamptz not null default now(),
  utilisateur text not null default '',
  famille     text not null default 'autre',  -- produit | categorie | boutique | compte
  action      text not null default '',       -- ajout | modification | suppression | …
  libelle     text not null default '',       -- phrase lisible par le gérant
  cible       text not null default ''        -- nom du produit, de la catégorie…
);
create index if not exists journal_date on public.journal(fait_le desc);

alter table public.journal enable row level security;

drop policy if exists "journal lecture connectee" on public.journal;
drop policy if exists "journal ecriture connectee" on public.journal;
-- Le journal n'est PAS public : l'administrateur le lit, l'équipe l'alimente.
create policy "journal lecture connectee" on public.journal
  for select to authenticated using (public.est_admin());
-- (Les deux rangs d'administrateur lisent l'historique ; le modérateur non.)
create policy "journal ecriture connectee" on public.journal
  for insert to authenticated with check (public.est_equipe());

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

drop policy if exists "lecture publique"  on public.slides;
drop policy if exists "ecriture connectee" on public.slides;
-- La vitrine d'une boutique : son administrateur la compose, tout le
-- monde la voit. Le modérateur, lui, n'y touche pas.
create policy "lecture publique"   on public.slides           for select using (true);
create policy "ecriture connectee" on public.slides
  for all to authenticated
  using (public.administre(boutique_id)) with check (public.administre(boutique_id));

drop policy if exists "lecture publique"  on public.boutique;
drop policy if exists "ecriture connectee" on public.boutique;
create policy "lecture publique"   on public.boutique        for select using (true);
-- Les coordonnées de l'enseigne ne regardent que le superadministrateur.
create policy "ecriture connectee" on public.boutique
  for all to authenticated using (public.est_super()) with check (public.est_super());

-- Les rayons appartiennent à une boutique : le modérateur ne touche
-- qu'à ceux de la sienne, l'administrateur à tous.
drop policy if exists "lecture publique"  on public.categories;
drop policy if exists "ecriture connectee" on public.categories;
create policy "lecture publique"   on public.categories      for select using (true);
create policy "ecriture connectee" on public.categories
  for all to authenticated
  using (public.peut_agir_sur(boutique_id)) with check (public.peut_agir_sur(boutique_id));

-- Une sous-catégorie suit le sort de son rayon.
drop policy if exists "lecture publique"  on public.sous_categories;
drop policy if exists "ecriture connectee" on public.sous_categories;
create policy "lecture publique"   on public.sous_categories for select using (true);
create policy "ecriture connectee" on public.sous_categories
  for all to authenticated
  using (public.peut_agir_sur(
    (select c.boutique_id from public.categories c where c.id = categorie_id)))
  with check (public.peut_agir_sur(
    (select c.boutique_id from public.categories c where c.id = categorie_id)));

-- Les produits se découpent en trois droits : ajouter, modifier, supprimer.
-- Toute l'équipe ajoute — dans sa boutique ; retoucher ou retirer un
-- produit déjà publié demande en plus le droit correspondant.
drop policy if exists "lecture publique"  on public.produits;
drop policy if exists "ecriture connectee" on public.produits;
drop policy if exists "produits ajout" on public.produits;
drop policy if exists "produits modification" on public.produits;
drop policy if exists "produits suppression" on public.produits;
create policy "lecture publique" on public.produits for select using (true);
create policy "produits ajout" on public.produits
  for insert to authenticated with check (public.peut_agir_sur(boutique_id));
create policy "produits modification" on public.produits
  for update to authenticated
  using (public.peut_modifier_produits() and public.peut_agir_sur(boutique_id))
  with check (public.peut_modifier_produits() and public.peut_agir_sur(boutique_id));
create policy "produits suppression" on public.produits
  for delete to authenticated
  using (public.peut_modifier_produits() and public.peut_agir_sur(boutique_id));

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
  with check (public.peut_agir_sur(
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

-- ---------- Temps réel ----------
-- Permet à l'application client d'être prévenue dès qu'un produit change,
-- sans avoir à être fermée et rouverte. Sans risque à ré-exécuter.
do $$
declare
  t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['boutique', 'boutiques', 'categories', 'sous_categories', 'produits', 'slides'] loop
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
-- Photos de produits : toute l'équipe.
-- Dossiers « boutique/ », « boutiques/ » (logos) et « slider/ » :
-- administrateur seul.
create policy "photos ecriture connectee" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'produits' and
    (public.est_admin() or
     (public.est_equipe() and name not like 'boutique/%' and name not like 'boutiques/%'
                      and name not like 'slider/%')));
create policy "photos maj connectee" on storage.objects
  for update to authenticated using (
    bucket_id = 'produits' and
    (public.est_admin() or
     (public.est_equipe() and name not like 'boutique/%' and name not like 'boutiques/%'
                      and name not like 'slider/%')));
create policy "photos suppression connectee" on storage.objects
  for delete to authenticated using (
    bucket_id = 'produits' and
    (public.est_admin() or
     (public.est_equipe() and name not like 'boutique/%' and name not like 'boutiques/%'
                      and name not like 'slider/%')));

-- ---------- Rayons de départ d'une boutique informatique ----------
insert into public.categories (id, boutique_id, nom, ordre) values
  ('cat_ordinateurs',  'bou_informatique', 'Ordinateurs',            1),
  ('cat_imprimantes',  'bou_informatique', 'Imprimantes & scanners', 2),
  ('cat_consommables', 'bou_informatique', 'Consommables',           3),
  ('cat_accessoires',  'bou_informatique', 'Accessoires',            4),
  ('cat_stockage',     'bou_informatique', 'Stockage',               5),
  ('cat_reseau',       'bou_informatique', 'Réseau & énergie',       6)
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
  (id, boutique_id, nom, description, prix, ancien_prix, categorie_id, sous_categorie_id,
   stock, sur_commande, disponible, en_avant, ordre_avant) values
  ('prod_hp15', 'bou_informatique', 'Ordinateur portable HP 15',
   e'Écran 15,6" HD, processeur Intel Core i5, 8 Go de RAM, SSD 512 Go, Windows 11.\nIdéal pour le bureau, les études et la navigation.\nGarantie boutique, livraison possible à Cotonou.',
   385000, null, 'cat_ordinateurs', 'sc_portables', 4, false, true, true, 1),
  ('prod_epson_l3250', 'bou_informatique', 'Imprimante Epson EcoTank L3250',
   e'Multifonction 3 en 1 (impression, copie, scan) à réservoirs d''encre rechargeables.\nWifi intégré, impression depuis le téléphone.\nJusqu''à 4 500 pages noir avec un seul flacon.',
   145000, 165000, 'cat_imprimantes', 'sc_multifonctions', 2, false, true, true, 2),
  ('prod_apc650', 'bou_informatique', 'Onduleur APC Back-UPS 650 VA',
   e'Protège votre ordinateur des coupures et variations de courant.\nAutonomie suffisante pour enregistrer votre travail et éteindre proprement.\nPrises multiples, protection téléphone/ADSL.',
   42000, null, 'cat_reseau', 'sc_onduleurs', 7, false, true, true, 3),
  ('prod_usb_kingston64', 'bou_informatique', 'Clé USB Kingston 64 Go',
   e'Clé USB 3.2 rapide et fiable pour vos documents, photos et vidéos.\nCompatible ordinateur, TV et autoradio.',
   6500, null, 'cat_stockage', 'sc_cles_usb', 25, false, true, true, 4),
  ('prod_toner_85a', 'bou_informatique', 'Toner HP 85A (CE285A)',
   e'Cartouche de toner noir d''origine pour HP LaserJet P1102, M1132, M1212…\nEnviron 1 600 pages.',
   28000, 32000, 'cat_consommables', 'sc_toners', 0, false, false, true, 5),
  ('prod_logitech_m185', 'bou_informatique', 'Souris sans fil Logitech M185',
   e'Souris sans fil compacte avec récepteur USB nano.\nJusqu''à 12 mois d''autonomie avec une pile AA.',
   8500, null, 'cat_accessoires', 'sc_claviers_souris', 12, false, true, false, 0)
on conflict (id) do nothing;
