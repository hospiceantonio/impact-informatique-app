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
begin
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
  update public.categories set boutique_id = premiere where boutique_id is null;
  update public.produits   set boutique_id = premiere where boutique_id is null;
  -- Ni le slider de l'enseigne ni sa publicité n'appartiennent à une
  -- boutique : ils resteraient rangés là où ils n'ont rien à faire.
  update public.slides     set boutique_id = premiere
   where boutique_id is null and portee not in ('enseigne', 'publicite');
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
  /* UN CLIENT N'EST PAS UN COMPTE D'ÉQUIPE EN ATTENTE. L'application
     cliente s'inscrit en posant « compte: client » ; sans ce test, chaque
     acheteur apparaîtrait dans la liste des comptes de l'enseigne, et il
     suffirait d'un clic distrait pour donner à un client les droits d'un
     modérateur sur une boutique. */
  if coalesce(new.raw_user_meta_data ->> 'compte', '') = 'client' then
    return new;
  end if;
  /* Et l'équipe n'entre pas par SMS : elle a des adresses e-mail. Un
     compte qui n'a qu'un numéro est un acheteur, même si les
     métadonnées manquent — elles viennent du téléphone, après tout. */
  if coalesce(new.email, '') = '' and coalesce(new.phone, '') <> '' then
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
   where public.est_super()
     and c.revendeur_etat <> 'aucune'
     and (coalesce(filtre, '') = '' or c.revendeur_etat = filtre)
   order by c.revendeur_demande_le desc nulls last;
$$;
revoke all on function public.revendeurs(text) from public, anon, authenticated;
grant execute on function public.revendeurs(text) to authenticated;

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
  if not public.est_super() then
    raise exception 'Seul BIZZOO valide un compte revendeur';
  end if;
  select coalesce(p.email, '') into qui from public.profils p where p.id = auth.uid();
  etat := case when accord then 'validee' else 'refusee' end;

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

revoke all on function public.approuver_demande(text) from public;
revoke all on function public.refuser_demande(text, text) from public;
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
insert into public.paiement (id) values (1) on conflict (id) do nothing;

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
              check (etat in ('nouvelle', 'vue', 'preparee', 'remise', 'annulee')),
  cree_le     timestamptz not null default now()
);
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
create or replace function public.commande_recalcule() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  cible text := coalesce(new.commande_id, old.commande_id);
  avant text := coalesce(current_setting('bizzoo.interne', true), '');
begin
  -- C'est la base qui écrit ce total, pas un client : le verrou de la
  -- section suivante doit le laisser passer. Le drapeau est ensuite
  -- rendu tel qu'il était, pour ne pas ouvrir la porte au reste de
  -- l'appel.
  perform set_config('bizzoo.interne', 'oui', true);
  update public.commandes c
     set total = coalesce((select sum(l.prix * l.quantite)
                             from public.commande_lignes l
                            where l.commande_id = cible), 0)
   where c.id = cible;
  perform set_config('bizzoo.interne', avant, true);
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
create policy "commandes lecture" on public.commandes
  for select to authenticated using (
    public.est_super()
    or (public.est_equipe() and exists (
          select 1 from public.commande_lignes l
           where l.commande_id = commandes.id
             and l.boutique_id = public.boutique_du_compte())));
create policy "lignes lecture" on public.commande_lignes
  for select to authenticated using (public.peut_agir_sur(boutique_id));

-- Avancer une ligne — vue, préparée, remise — appartient à la boutique.
create policy "lignes suivi" on public.commande_lignes
  for update to authenticated
  using (public.peut_agir_sur(boutique_id))
  with check (public.peut_agir_sur(boutique_id));
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
  nom, code, reference, prix, quantite, etat, cree_le
) on public.commande_lignes to authenticated;
revoke all on public.commande_lignes from anon;
-- L'équipe avance l'état de sa ligne, et rien d'autre : « ligne_verrous »
-- refuse déjà le reste, ceci le refuse une seconde fois.
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
create or replace function public.creer_commande(client jsonb, articles jsonb)
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

  for article in select * from jsonb_array_elements(articles) loop
    qte := greatest(1, least(99, coalesce((article ->> 'quantite')::int, 1)));
    select * into p from public.produits where id = article ->> 'produit_id';
    if not found then
      raise exception 'Un des produits de votre panier n''existe plus.';
    end if;
    if coalesce(p.stock, 0) <= 0 and not coalesce(p.sur_commande, false)
       and (p.appro_le is null or p.appro_le < current_date) then
      raise exception '« % » n''est plus disponible : retirez-le du panier.', p.nom;
    end if;
    devises := devises || coalesce(nullif((
      select b.devise from public.boutiques b where b.id = p.boutique_id), ''), 'FCFA');
    insert into public.commande_lignes (id, commande_id, produit_id, quantite)
    values ('lig_' || replace(gen_random_uuid()::text, '-', ''), nouvelle, p.id, qte);
  end loop;

  if (select count(distinct d) from unnest(devises) d) > 1 then
    raise exception 'Ces produits ne se paient pas dans la même monnaie : commandez boutique par boutique.';
  end if;
  update public.commandes set devise = coalesce(devises[1], 'FCFA') where id = nouvelle;

  select jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'total', c.total, 'devise', c.devise,
    'etat', c.etat,
    'boutiques', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', g.boutique_id,
               'nom', coalesce((select b.nom from public.boutiques b where b.id = g.boutique_id), ''),
               'whatsapp', coalesce((select b.whatsapp from public.boutiques b where b.id = g.boutique_id), ''),
               'indicatif', coalesce((select b.indicatif from public.boutiques b where b.id = g.boutique_id), '229'),
               'montant', g.montant,
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

revoke all on function public.creer_commande(jsonb, jsonb) from public;
grant execute on function public.creer_commande(jsonb, jsonb) to anon, authenticated;

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
     and client_tel = regexp_replace(coalesce(tel, ''), '\D', '', 'g');
  if not found then return null; end if;
  return jsonb_build_object(
    'numero', c.numero, 'etat', c.etat, 'total', c.total, 'devise', c.devise,
    'paye_le', c.paye_le, 'remarque', c.remarque);
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
create or replace function public.marquer_payee(
  reference text, transaction text, montant int)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c   public.commandes%rowtype;
  net text := left(regexp_replace(coalesce(transaction, ''), '[^A-Za-z0-9_-]', '', 'g'), 64);
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
    -- Un paiement qui ne nous concerne pas n'est pas une erreur.
    return jsonb_build_object('ok', true, 'raison', 'commande inconnue');
  end if;

  if c.etat = 'payee' then
    return jsonb_build_object('ok', true, 'deja', true, 'numero', c.numero);
  end if;

  perform set_config('bizzoo.paiement', 'oui', true);

  -- Cette transaction est déjà rattachée à une autre commande. On le
  -- NOTE au lieu de lever une erreur : une erreur ferait réessayer
  -- KkiaPay cinq fois pour rien, et l'encaissement resterait bloqué.
  if exists (select 1 from public.commandes a
              where a.transaction_id = net and a.id <> c.id) then
    update public.commandes
       set remarque = 'Transaction ' || net || ' déjà rattachée à une autre commande.'
     where id = c.id;
    return jsonb_build_object('ok', true, 'conflit', true, 'numero', c.numero);
  end if;

  -- Le montant qui compte est celui que KkiaPay annonce. S'il manque
  -- quelque chose, on ne valide pas : on écrit ce qu'on a reçu, et la
  -- boutique tranche. La preuve, elle, n'est pas posée : la commande
  -- n'est pas payée.
  if coalesce(montant, 0) < c.total then
    update public.commandes
       set remarque = 'Paiement incomplet : ' || coalesce(montant, 0)::text
                      || ' reçus sur ' || c.total::text || ' attendus'
                      || ' (transaction ' || net || ').'
     where id = c.id;
    return jsonb_build_object('ok', true, 'incomplet', true, 'numero', c.numero);
  end if;

  update public.commandes
     set etat = 'payee', paye_le = now(), transaction_id = net,
         confirme_par = '', remarque = ''
   where id = c.id;
  return jsonb_build_object('ok', true, 'numero', c.numero, 'total', c.total);
end $$;

-- LE POINT À NE PAS MANQUER : révoquer du seul pseudo-rôle « public »
-- ne suffit pas. Supabase accorde d'office EXECUTE à « anon » et
-- « authenticated » sur toute fonction du schéma public. Sans ces deux
-- lignes, quiconque extrait la clé publiable de l'APK — et elle y est,
-- par construction — validerait ses commandes sans payer.
revoke all on function public.marquer_payee(text, text, int)
  from public, anon, authenticated;

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
create or replace function public.noter_reference(cible text, reference text)
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
  return true;
end $$;

revoke all on function public.noter_reference(text, text)
  from public, anon, authenticated;

-- ---------- Ce que l'Edge Function a besoin de savoir ----------
-- Le MONTANT vient d'ici, jamais de la requête : c'est tout l'intérêt.
-- Un téléphone qui annoncerait le montant à encaisser paierait 100
-- francs une commande de 100 000.
--
-- Le numéro de téléphone du client fait office de mot de passe, comme
-- pour « suivre_commande » : sans lui, n'importe qui ferait sonner le
-- téléphone d'un inconnu avec une demande de paiement.
create or replace function public.commande_pour_paiement(cible text, tel text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.commandes%rowtype;
begin
  select * into c from public.commandes
   where id = coalesce(cible, '')
     and client_tel = regexp_replace(coalesce(tel, ''), '\D', '', 'g');
  if not found then return null; end if;
  return jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'etat', c.etat,
    'total', c.total, 'devise', c.devise,
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
declare qui text;
begin
  if not public.est_super() then
    raise exception 'Seule l''enseigne peut confirmer un paiement à la main';
  end if;
  select coalesce(p.email, '') into qui from public.profils p where p.id = auth.uid();
  perform set_config('bizzoo.paiement', 'oui', true);
  update public.commandes
     set etat = 'payee', paye_le = now(), confirme_par = coalesce(qui, 'enseigne')
   where id = cible and etat <> 'payee';
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

-- ---------- Temps réel ----------
-- Permet à l'application client d'être prévenue dès qu'un produit change,
-- sans avoir à être fermée et rouverte. Sans risque à ré-exécuter.
do $$
declare
  t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['boutique', 'boutiques', 'categories', 'sous_categories', 'produits',
                          'slides', 'commandes', 'commande_lignes'] loop
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
   385000, null, 'cat_ordinateurs', 'sc_portables', 4, false, true, false, 0),
  ('prod_epson_l3250', 'bou_informatique', 'Imprimante Epson EcoTank L3250',
   e'Multifonction 3 en 1 (impression, copie, scan) à réservoirs d''encre rechargeables.\nWifi intégré, impression depuis le téléphone.\nJusqu''à 4 500 pages noir avec un seul flacon.',
   145000, 165000, 'cat_imprimantes', 'sc_multifonctions', 2, false, true, false, 0),
  ('prod_apc650', 'bou_informatique', 'Onduleur APC Back-UPS 650 VA',
   e'Protège votre ordinateur des coupures et variations de courant.\nAutonomie suffisante pour enregistrer votre travail et éteindre proprement.\nPrises multiples, protection téléphone/ADSL.',
   42000, null, 'cat_reseau', 'sc_onduleurs', 7, false, true, false, 0),
  ('prod_usb_kingston64', 'bou_informatique', 'Clé USB Kingston 64 Go',
   e'Clé USB 3.2 rapide et fiable pour vos documents, photos et vidéos.\nCompatible ordinateur, TV et autoradio.',
   6500, null, 'cat_stockage', 'sc_cles_usb', 25, false, true, false, 0),
  ('prod_toner_85a', 'bou_informatique', 'Toner HP 85A (CE285A)',
   e'Cartouche de toner noir d''origine pour HP LaserJet P1102, M1132, M1212…\nEnviron 1 600 pages.',
   28000, 32000, 'cat_consommables', 'sc_toners', 0, false, false, false, 0),
  ('prod_logitech_m185', 'bou_informatique', 'Souris sans fil Logitech M185',
   e'Souris sans fil compacte avec récepteur USB nano.\nJusqu''à 12 mois d''autonomie avec une pile AA.',
   8500, null, 'cat_accessoires', 'sc_claviers_souris', 12, false, true, false, 0)
on conflict (id) do nothing;
