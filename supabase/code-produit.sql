-- =========================================================
-- BIZZOO — le code d'un produit
--
-- Un numéro, rien que des chiffres, donné par la base au
-- moment où le produit est créé. Il ne se choisit pas, il ne
-- se corrige pas, il ne se réutilise pas — pas même par un
-- superadministrateur. C'est ce qui en fait un repère sûr :
-- un code dicté au téléphone, ou recopié dans un message,
-- désigne un seul produit, aujourd'hui et dans dix ans.
--
-- À ne pas confondre avec la RÉFÉRENCE, qui reste ce que la
-- boutique veut en faire : elle la choisit, la change, la
-- laisse vide. Deux choses différentes, deux colonnes.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable. Les produits déjà au catalogue
-- reçoivent leur code, du plus ancien au plus récent, et ne
-- le changent plus jamais.
-- =========================================================

-- ---------------------------------------------------------
-- 0. Les briques empruntées
-- ---------------------------------------------------------
-- Les fonctions de ce fichier en appellent d'autres, nées plus tard et
-- rangées dans d'autres fichiers. Or PostgreSQL ne relit le corps d'une
-- fonction qu'au moment de l'EXÉCUTER : si l'une manque, ce fichier
-- passe sans broncher et la base s'arrête à la première commande. On les
-- repose donc ici, à l'identique — les reposer ne coûte rien.

-- Le prix d'un revendeur validé : le prix d'achat plus une marge, ou le
-- prix public moins une remise — au choix de chaque boutique, jamais
-- sous le prix d'achat ni au-dessus du prix public.
-- « ligne_a_l_ecriture », plus bas, l'appelle.
-- L'ancienne règle ne prenait que DEUX arguments. La laisser en place
-- rendrait tout appel à deux arguments ambigu — PostgreSQL refuserait
-- « function is not unique », et plus aucune commande ne passerait.
drop function if exists public.prix_revendeur(int, int);
-- Les colonnes que cette règle lit. Une base d'avant la marge revendeur
-- ne les a pas, et PostgreSQL ne relit le corps d'une fonction qu'au
-- moment de l'exécuter : sans elles, le fichier passerait sans broncher
-- pour s'arrêter à la première vente.
alter table public.boutiques
  add column if not exists revendeur_mode text not null default 'bizzoo';
alter table public.boutiques
  add column if not exists taux_revendeur numeric(6,2) not null default 10;
alter table public.produits_prive
  add column if not exists taux_revendeur numeric(6,2);
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'boutiques_revendeur_mode') then
    alter table public.boutiques
      add constraint boutiques_revendeur_mode
      check (revendeur_mode in ('bizzoo', 'public'));
  end if;
end $$;

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

-- La règle « faut-il un compte pour commander ? », que « creer_commande »
-- consulte plus bas. Elle arrive ÉTEINTE et se bascule depuis
-- l'application admin ; la reposer ici ne la change pas.
create table if not exists public.reglages (
  id                 int primary key default 1 check (id = 1),
  compte_obligatoire boolean not null default false,
  maj_le             timestamptz not null default now()
);
alter table public.reglages
  add column if not exists compte_obligatoire boolean not null default false;
alter table public.reglages
  add column if not exists maj_le timestamptz not null default now();
insert into public.reglages (id) values (1) on conflict (id) do nothing;

alter table public.reglages enable row level security;
drop policy if exists "reglages lecture"  on public.reglages;
drop policy if exists "reglages ecriture" on public.reglages;
create policy "reglages lecture" on public.reglages
  for select to anon, authenticated using (true);
create policy "reglages ecriture" on public.reglages
  for update to authenticated
  using (public.est_super()) with check (public.est_super());
revoke all on public.reglages from anon, authenticated;
grant select on public.reglages to anon, authenticated;
grant update (compte_obligatoire, maj_le) on public.reglages to authenticated;

create or replace function public.compte_exige() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select r.compte_obligatoire from public.reglages r where r.id = 1), false);
$$;
revoke all on function public.compte_exige() from public, anon, authenticated;
grant execute on function public.compte_exige() to anon, authenticated;

-- ---------------------------------------------------------
-- 1. La colonne et le compteur
-- ---------------------------------------------------------
alter table public.produits add column if not exists code text not null default '';

-- Six chiffres, sans zéro en tête : un code se dicte au téléphone et se
-- recopie à la main. Le compteur ne revient jamais en arrière, même si
-- un produit est supprimé — un code retiré du catalogue reste retiré.
create sequence if not exists public.produits_code start with 100001;

-- ---------------------------------------------------------
-- 2. Les produits d'avant reçoivent le leur
-- ---------------------------------------------------------
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

-- ---------------------------------------------------------
-- 3. Le code ne se choisit pas, et ne se change plus
-- ---------------------------------------------------------
-- Les notes, tenues par « avis_recalcule() » et refusées à tout le
-- reste par la règle d'écriture ci-dessous. Posées par « avis.sql »,
-- répétées ici : un fichier qui pose une fonction pose aussi les
-- colonnes qu'elle touche.
alter table public.produits add column if not exists note_moyenne numeric(3,2);
alter table public.produits add column if not exists nb_avis int not null default 0;

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

-- ---------------------------------------------------------
-- 4. Le code suit le produit dans les commandes
-- ---------------------------------------------------------
-- Figé sur la ligne, comme le nom et le prix : c'est ce qui a été vendu.
alter table public.commande_lignes add column if not exists code text not null default '';
-- La règle d'écriture réinstallée plus bas remplit aussi ces deux-là. Un
-- fichier qui pose une fonction pose toutes les colonnes qu'elle écrit,
-- même celles d'un autre fichier : PostgreSQL ne relit le corps d'une
-- fonction qu'à l'exécution, et l'oubli ne se voit qu'à la première
-- commande, sur « record "new" has no field … ».
alter table public.commande_lignes
  add column if not exists prix_bizzoo int not null default 0;
alter table public.commande_lignes
  add column if not exists taux_marge numeric;

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

-- Le récapitulatif renvoyé au client porte le code, pour que le message
-- WhatsApp et le reçu désignent le produit sans ambiguïté.
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

-- ---------- Vérification ----------
-- 1. Tous les produits ont un code, et aucun ne le partage.
select count(*)                                   as "produits",
       count(*) filter (where code <> '')          as "avec un code",
       count(distinct code) filter (where code <> '') as "codes distincts"
  from public.produits;

-- 2. Le garde-fou est en place.
select t.tgname as "garde-fou"
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
 where not t.tgisinternal and c.relname = 'produits' and t.tgname = 'produits_code';

-- 3. Un aperçu.
select code, reference, nom from public.produits order by code limit 10;
