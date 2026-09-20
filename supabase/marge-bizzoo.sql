-- =========================================================
-- BIZZOO — la marge de l'enseigne, et ce que rapporte chaque
-- boutique
--
-- Le modèle : la boutique annonce le PRIX BIZZOO — ce qu'elle
-- veut toucher. L'enseigne y ajoute SA MARGE, fixée au moment
-- où elle crée la boutique. La somme est le PRIX DE VENTE, le
-- seul que le client voie. La différence est le bénéfice de
-- l'enseigne.
--
--   prix de vente = prix BIZZOO + marge
--   bénéfice      = prix de vente − prix BIZZOO
--
-- Trois règles, et elles sont dans la base, pas à l'écran :
--
--   1. LA MARGE EST À L'ENSEIGNE. Une boutique ne la retouche
--      pas — sinon elle fixerait elle-même ce que BIZZOO
--      gagne sur elle.
--
--   2. LE PRIX BIZZOO NE SORT PAS. Il vit dans « produits_prive »,
--      hors de portée des clients : il dirait à chacun ce que
--      la boutique touche vraiment.
--
--   3. CE QUI A ÉTÉ VENDU EST FIGÉ. La ligne de commande garde
--      le prix BIZZOO et le taux du jour de la vente. Changer
--      la marge demain ne doit pas réécrire les comptes d'hier.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable.
-- =========================================================

-- ---------------------------------------------------------
-- 1. La marge appartient à l'enseigne
-- ---------------------------------------------------------
-- La colonne d'abord : une base déjà en service ne l'a pas. 20 % par
-- défaut, que l'enseigne ajuste boutique par boutique.
alter table public.boutiques
  add column if not exists taux_marge numeric(6,2) not null default 20;

-- Les notes, tenues par « avis_recalcule() » et refusées à tout le
-- reste par la règle d'écriture ci-dessous. Posées par « avis.sql »,
-- répétées ici : un fichier qui pose une fonction pose aussi les
-- colonnes qu'elle touche.
alter table public.boutiques add column if not exists note_moyenne numeric(3,2);
alter table public.boutiques add column if not exists nb_avis int not null default 0;

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

-- ---------------------------------------------------------
-- 2. Ce qui a été vendu garde ses chiffres
-- ---------------------------------------------------------
-- Un fichier qui installe une règle d'écriture installe AUSSI toutes les
-- colonnes que cette règle remplit — même celles qu'il n'a pas inventées.
-- PostgreSQL ne relit le corps d'une fonction qu'à l'exécution : sans ces
-- lignes, le fichier passe sans broncher et la base s'arrête à la
-- première commande, sur « record "new" has no field … ».
alter table public.commande_lignes
  add column if not exists code text not null default '';
alter table public.commande_lignes
  add column if not exists prix_bizzoo int not null default 0;
alter table public.commande_lignes
  add column if not exists taux_marge numeric;

-- Le rattrapage des commandes passées, au mieux : le prix BIZZOO
-- d'aujourd'hui. Approximation assumée — avant cette mise à jour, rien
-- n'était gardé. Le déclencheur est retiré le temps de l'écriture,
-- puisqu'il interdit précisément de toucher à ces colonnes.
drop trigger if exists lignes_verrous on public.commande_lignes;

update public.commande_lignes l
   set prix_bizzoo = greatest(0, coalesce(pp.prix_grossiste, 0))::int
  from public.produits_prive pp
 where pp.produit_id = l.produit_id and l.prix_bizzoo = 0;

-- Une brique empruntée : le prix d'un revendeur validé, né plus tard et
-- rangé dans « comptes-revendeurs.sql ». La règle d'écriture ci-dessous
-- l'appelle, et PostgreSQL ne relit le corps d'une fonction qu'au moment
-- de l'EXÉCUTER : sans elle, ce fichier passerait sans broncher et la
-- base s'arrêterait à la première vente. On la repose donc à
-- l'identique — la reposer ne coûte rien.
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

-- La colonne que « ligne_verrous » protège : l'accusé de réception du
-- client. Un fichier qui pose une fonction pose aussi les colonnes
-- qu'elle touche — sans elle, la règle s'installerait sans un mot et
-- la base s'arrêterait sur « record "new" has no field » à la
-- première ligne de commande avancée.
alter table public.commande_lignes add column if not exists confirme_le timestamptz;

-- À qui la livraison est confiée. « ligne_verrous » la protège : un
-- fichier qui pose une fonction pose aussi les colonnes qu'elle
-- touche, sinon la règle s'installe sans un mot et la base
-- s'arrête à la première ligne avancée.
alter table public.commande_lignes add column if not exists livreur_id uuid;

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

create trigger lignes_verrous
  before update on public.commande_lignes
  for each row execute function public.ligne_verrous();

-- ---------------------------------------------------------
-- 3. Ce que chaque boutique rapporte
-- ---------------------------------------------------------
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

-- ---------- Vérification ----------
-- 1. La marge est bien hors de portée des boutiques.
select t.tgname as "garde-fou de la boutique"
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
 where not t.tgisinternal and c.relname = 'boutiques';

-- 2. Les colonnes figées sur la ligne de commande.
select column_name as "colonne", data_type as "type"
  from information_schema.columns
 where table_schema = 'public' and table_name = 'commande_lignes'
   and column_name in ('prix', 'prix_bizzoo', 'taux_marge')
 order by 1;

-- 3. La marge de chaque boutique, telle qu'elle est aujourd'hui.
select nom as "boutique", taux_marge as "marge BIZZOO (%)" from public.boutiques order by ordre;

-- 4. Ce que les ventes ont rapporté jusqu'ici (vide au départ : normal).
--    On lit les lignes directement, sans passer par « statistiques_ventes » :
--    cette fonction est réservée à l'enseigne CONNECTÉE, et l'éditeur SQL
--    n'est connecté à aucun compte. L'appeler ici ferait échouer tout le
--    fichier — et l'éditeur annule TOUT le bloc à la première erreur.
select coalesce(b.nom, '(sans boutique)')             as "boutique",
       sum(l.quantite)                                as "articles vendus",
       sum(l.quantite * l.prix)                       as "encaissé",
       sum(l.quantite * l.prix_bizzoo)                as "reversé",
       sum(l.quantite * (l.prix - l.prix_bizzoo))     as "bénéfice BIZZOO"
  from public.commande_lignes l
  join public.commandes c on c.id = l.commande_id
  left join public.boutiques b on b.id = l.boutique_id
 where c.etat = 'payee' and l.etat <> 'annulee'
 group by 1 order by 5 desc;
