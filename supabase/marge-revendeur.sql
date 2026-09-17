-- =========================================================
-- BIZZOO — la marge sur les ventes aux revendeurs
--
-- Jusqu'ici, un revendeur validé payait le PRIX BIZZOO EXACT —
-- ce que la boutique veut toucher. Deux conséquences, et les deux
-- vous coûtent :
--
--   1. L'ENSEIGNE NE GAGNAIT RIEN. La boutique touchait bien ce
--      qu'elle voulait toucher ; BIZZOO, lui, ne prenait pas un
--      franc au passage. Chaque vente à un revendeur sortait de la
--      marchandise et ne rapportait rien à l'enseigne.
--   2. CE QUE LA BOUTIQUE TOUCHE S'AFFICHAIT EN CLAIR. Le revendeur
--      lisait, article par article, le prix BIZZOO — ce que
--      « produits_prive » existe précisément pour cacher.
--
-- Ce fichier pose une marge. Le revendeur paie désormais un prix
-- CALCULÉ, de l'une des deux façons — chaque boutique choisit la
-- sienne, dans ses réglages :
--
--   « bizzoo »  prix BIZZOO + N %. L'enseigne gagne sur chaque
--               vente, et le prix BIZZOO cesse d'être lisible.
--   « public »  prix public − N %. C'est ainsi qu'un revendeur
--               raisonne : « j'ai N % de remise ».
--
-- DEUX BORNES, quel que soit le mode et quel que soit le taux :
-- jamais sous le prix BIZZOO (on ne vend pas à perte sans s'en
-- apercevoir), jamais au-dessus du prix public (un revendeur qui
-- paierait plus cher qu'un client de passage n'aurait aucune
-- raison de rester).
--
-- CE QUE CE FICHIER CHANGE LE JOUR OÙ VOUS L'EXÉCUTEZ : il pose
-- 10 % de marge sur le prix BIZZOO, pour toutes les boutiques.
-- Les prix revendeur montent donc de 10 % — c'était le but. Vous
-- ajustez ensuite le mode et le taux boutique par boutique, et le
-- taux produit par produit, depuis l'application admin.
--
-- Rien ne bouge pour les clients ordinaires : le prix public ne
-- change pas, et les commandes déjà passées gardent leurs
-- chiffres — ce qui a été vendu est vendu.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, et rien n'est supprimé.
-- =========================================================

-- ---------------------------------------------------------
-- 1. Où vivent le mode et les taux
-- ---------------------------------------------------------
-- Le MODE est une décision de boutique : une seule façon de faire par
-- boutique, sinon plus personne ne sait à quoi s'attendre. Le TAUX se
-- raffine ensuite produit par produit — un article à forte rotation ne
-- se négocie pas comme une pièce rare.
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

-- Le taux d'UN produit. À null — et c'est le cas de tous aujourd'hui —
-- c'est celui de la boutique qui s'applique. Exactement la règle que
-- « taux_marge » suit déjà dans cette table.
--
-- Il est ici, dans la table PRIVÉE, et non sur « produits » : il se
-- déduit du prix BIZZOO, et le prix BIZZOO ne descend jamais dans
-- l'application cliente.
alter table public.produits_prive
  add column if not exists taux_revendeur numeric(6,2);

-- ---------------------------------------------------------
-- 2. La règle de prix
-- ---------------------------------------------------------
-- L'ancienne règle ne prenait que DEUX arguments. La laisser en place
-- rendrait tout appel à deux arguments ambigu — PostgreSQL refuserait
-- « function is not unique », et plus aucune commande ne passerait. On
-- la retire donc avant de poser celle-ci.
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

-- ---------------------------------------------------------
-- 3. Les deux qui la lisent : l'écran et la caisse
-- ---------------------------------------------------------
-- Ils doivent dire le MÊME prix, sinon le client voit un montant et en
-- paie un autre. « mes_prix() » sert l'affichage, « ligne_a_l_ecriture »
-- la facture, et toutes deux appellent la règle ci-dessus.

-- Une brique empruntée à « comptes-revendeurs.sql », que « mes_prix »
-- appelle : demander à devenir revendeur ne suffit pas, seul « validee »
-- ouvre ces prix-là. Reposée ici avec la colonne qu'elle lit — un
-- fichier doit se suffire à lui-même.
alter table public.clients
  add column if not exists revendeur_etat text not null default 'aucune';

create or replace function public.est_revendeur() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.clients c
                  where c.id = auth.uid() and c.revendeur_etat = 'validee');
$$;
revoke all on function public.est_revendeur() from public, anon, authenticated;
grant execute on function public.est_revendeur() to authenticated;

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

-- Les colonnes que la règle d'écriture remplit. Une base d'avant la
-- marge BIZZOO ne les a pas, et PostgreSQL ne relit le corps d'une
-- fonction qu'au moment de l'exécuter : sans elles, ce fichier passerait
-- sans broncher pour s'arrêter à la première commande.
alter table public.commande_lignes
  add column if not exists code text not null default '';
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

drop trigger if exists lignes_a_l_ecriture on public.commande_lignes;
create trigger lignes_a_l_ecriture
  before insert on public.commande_lignes
  for each row execute function public.ligne_a_l_ecriture();

-- ---------------------------------------------------------
-- 4. Le taux ne se fixe pas depuis une boutique
-- ---------------------------------------------------------
-- Une boutique qui pourrait ramener sa marge revendeur à zéro
-- revendrait au prix BIZZOO, et on serait revenu au point de départ.
-- Le taux d'UN produit, lui, reste à la boutique — comme pour la marge
-- ordinaire, elle seule connaît ses articles.
--
-- La marge de BIZZOO et les notes sont posées ailleurs — « marge-bizzoo.sql »
-- et « avis.sql » — et répétées ici : un fichier qui pose une fonction
-- pose aussi les colonnes qu'elle touche.
alter table public.boutiques
  add column if not exists taux_marge numeric(6,2) not null default 20;
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

-- ---------- Vérification ----------
-- Ce que paierait un revendeur, boutique par boutique, sur trois
-- articles pris au hasard dans le catalogue. Comparez « prix public »,
-- « prix BIZZOO » et « prix revendeur » : le troisième doit tomber
-- entre les deux autres.
select b.nom                                                   as "Boutique",
       case b.revendeur_mode when 'public' then 'prix public − ' || b.taux_revendeur || ' %'
                             else 'prix BIZZOO + ' || b.taux_revendeur || ' %' end
                                                               as "Règle",
       p.nom                                                   as "Article",
       p.prix                                                  as "Prix public",
       coalesce(pv.prix_grossiste, 0)                          as "Prix BIZZOO",
       public.prix_revendeur(
         coalesce(p.prix, 0)::int,
         greatest(0, coalesce(pv.prix_grossiste, 0))::int,
         coalesce(pv.taux_revendeur, b.taux_revendeur, 0),
         coalesce(b.revendeur_mode, 'bizzoo'))                  as "Prix revendeur"
  from public.produits p
  join public.boutiques b on b.id = p.boutique_id
  left join public.produits_prive pv on pv.produit_id = p.id
 order by b.nom, p.nom
 limit 3;
