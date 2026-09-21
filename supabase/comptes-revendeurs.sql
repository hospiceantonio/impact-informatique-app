-- =========================================================
-- BIZZOO — les comptes revendeurs
--
-- Un compte client se crée désormais en deux sortes :
--
--   « client »    — l'acheteur ordinaire, qui paie le prix
--                   affiché en vitrine ;
--   « revendeur »  — le commerçant qui achète pour revendre, et
--                   qui paie le PRIX BIZZOO : celui que la
--                   boutique a annoncé à la création du produit.
--
-- Entre les deux, une décision humaine. Un compte revendeur se
-- DEMANDE depuis l'application ; il se valide dans le compte
-- superadministrateur de BIZZOO, et nulle part ailleurs.
--
-- CE QUI TIENT TOUT :
--
--   1. LE CLIENT NE S'ACCORDE PAS LE STATUT DE REVENDEUR.
--      « type_compte » est sa demande — il l'écrit librement, et
--      elle ne vaut rien de plus qu'une demande. « revendeur_etat »
--      est la réponse de BIZZOO : la base refuse qu'elle vienne
--      d'ailleurs que de valider_revendeur(), réservée au
--      superadministrateur ;
--   2. LE PRIX NE VIENT JAMAIS DU TÉLÉPHONE. Comme le nom et la
--      référence, il est relu dans le catalogue à l'écriture de
--      la ligne. Un revendeur qui bricolerait sa requête n'y
--      changerait rien ;
--   3. UN PRIX BIZZOO À ZÉRO N'EST PAS UN PRIX. Un produit dont
--      la boutique n'a pas renseigné le prix BIZZOO reste au
--      prix public pour tout le monde — sans quoi il partirait
--      gratuitement ;
--   4. LE REVENDEUR NE LIT PAS « produits_prive ». Cette table
--      porte aussi les taux de marge : elle reste fermée. Le
--      revendeur reçoit ses prix par mes_prix(), qui ne rend que
--      des prix.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, et rien n'est supprimé.
-- =========================================================

-- ---------------------------------------------------------
-- 1. Les colonnes que ce fichier remplit
-- ---------------------------------------------------------
-- Sur une base déjà en service, le corps d'un « create table »
-- n'est plus relu : chaque colonne se pose séparément.
-- ---------- Socle des comptes d'enseigne ----------
-- Recopié de schema.sql : les fonctions de droits ci-dessous s'appuient
-- dessus, et ce fichier doit pouvoir se coller seul sur une base d'avant.
alter table public.profils add column if not exists nom text not null default '';
alter table public.profils add column if not exists tel text not null default '';
alter table public.profils
  add column if not exists peut_commandes boolean not null default true;
alter table public.profils
  add column if not exists peut_boutiques boolean not null default false;
alter table public.profils
  add column if not exists peut_finances  boolean not null default false;

create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false);
$$;
revoke all on function public.est_compte_enseigne() from public, anon;
grant execute on function public.est_compte_enseigne() to authenticated;

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
revoke all on function public.droit_enseigne(text) from public, anon;
grant execute on function public.droit_enseigne(text) to authenticated;


create table if not exists public.clients (
  id          uuid primary key references auth.users(id) on delete cascade,
  nom         text not null default '',
  tel         text not null default '',
  indicatif   text not null default '229',
  tel_verifie boolean not null default false,
  adresse     text not null default '',
  cree_le     timestamptz not null default now(),
  maj_le      timestamptz not null default now()
);
alter table public.clients add column if not exists tel_verifie boolean not null default false;
alter table public.clients add column if not exists adresse text not null default '';
alter table public.clients add column if not exists indicatif text not null default '229';

-- Ce que le client demande : « client » ou « revendeur ». Il l'écrit
-- lui-même, et c'est voulu — une demande n'est pas un droit.
alter table public.clients add column if not exists type_compte text not null default 'client';
-- Ce que BIZZOO répond. Écrit par valider_revendeur(), et par elle seule.
--   'aucune'     — compte client ordinaire, rien de demandé
--   'en_attente' — la demande attend le superadministrateur
--   'validee'    — le compte achète au prix BIZZOO
--   'refusee'    — refusée, avec un motif que le client lit
alter table public.clients add column if not exists revendeur_etat text not null default 'aucune';
-- Ce que le demandeur dit de son commerce : sans quoi valider
-- reviendrait à signer un nom et une adresse e-mail.
alter table public.clients add column if not exists revendeur_message text not null default '';
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

-- La commande porte le régime de prix sous lequel elle est partie.
-- Figé comme le reste : valider un revendeur demain ne réécrit pas
-- les commandes d'hier, et lui retirer son statut non plus.
alter table public.commandes add column if not exists revendeur boolean not null default false;

-- Les colonnes que les règles d'écriture ci-dessous remplissent, et
-- qu'une base d'avant pourrait ne pas avoir.
alter table public.commandes add column if not exists client_id uuid;
alter table public.commande_lignes add column if not exists code text not null default '';
alter table public.commande_lignes add column if not exists prix_bizzoo int not null default 0;
alter table public.commande_lignes add column if not exists taux_marge numeric;
alter table public.commandes add column if not exists transaction_annoncee text not null default '';
alter table public.commandes add column if not exists fournisseur_ref text not null default '';
alter table public.commandes add column if not exists tentative_le timestamptz;

-- ---------------------------------------------------------
-- 2. Le prix d'un revendeur, en un seul endroit
-- ---------------------------------------------------------
-- L'écran et la caisse doivent dire le même prix, sinon le client
-- voit un montant et en paie un autre. La règle vit donc ici, et les
-- deux la lisent : mes_prix() pour l'affichage, ligne_a_l_ecriture()
-- pour la facture.
--
-- Prix BIZZOO à zéro : la boutique ne l'a pas renseigné. Le produit
-- reste alors au prix public — pour personne il ne devient gratuit.
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

-- ---------------------------------------------------------
-- Qui est qui, recopié ici
-- ---------------------------------------------------------
-- « est_equipe() » a CHANGÉ DE SENS avec l'arrivée du rang livreur :
-- elle nomme désormais les trois rangs qui tiennent la boutique, et
-- le livreur n'en est pas. Les règles de ce fichier s'appuient sur
-- elle ; collé seul sur une base qui garde l'ancienne définition,
-- il laisserait un livreur passer pour un membre de l'équipe.
-- Sur une base déjà à jour, ce bloc ne fait rien.

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

-- Peut-il retoucher un produit déjà au catalogue ? Les deux rangs
-- d'administrateur toujours ; le modérateur seulement si on le lui accorde.
--
-- « est_equipe() » EN PREMIER, et ce n'est pas une précaution de style :
-- « peut_modifier_produits » vaut VRAI par défaut sur tout profil. Sans
-- cette condition, un livreur qu'on vient de créer pourrait modifier le
-- catalogue — la colonne lui aurait dit oui.
create or replace function public.peut_modifier_produits() returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when public.est_super() then true
    when public.est_compte_enseigne() then public.droit_enseigne('produits')
    else public.est_equipe()
     and coalesce((select role = 'administrateur' or peut_modifier_produits
                     from public.profils where id = auth.uid() and actif), false)
  end;
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
      or public.est_compte_enseigne()
      or (public.est_equipe() and cible is not null
          and cible = public.boutique_du_compte());
$$;

-- Droits d'administration SUR cette boutique-là : le superadministrateur
-- partout, l'administrateur uniquement chez lui.
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
grant execute on function public.est_equipe() to authenticated;
revoke all on function public.est_livreur() from public, anon, authenticated;
grant execute on function public.est_livreur() to authenticated;
grant execute on function public.boutique_du_compte() to authenticated;
grant execute on function public.peut_agir_sur(text) to authenticated;

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

-- ---------------------------------------------------------
-- 3. Le statut ne s'accorde pas soi-même
-- ---------------------------------------------------------
-- C'est LE point de sécurité de ce fichier, et il a la même forme que
-- celui du numéro vérifié : une fonction du serveur pose le drapeau,
-- et le client n'a la main que sur sa demande.
--
-- Demander reste libre — c'est le sens de « type_compte ». Mais la
-- demande remet la décision à zéro : on ne se refait pas valider en
-- se déclarant client puis revendeur.
-- Ce qui n'est pas une coordonnée. Les deux règles d'écriture ci-dessous
-- l'appellent pour remettre d'aplomb la position du commerce d'un
-- revendeur ; elle naît dans « position-revendeur.sql », plus récent que
-- ce fichier. Reposée ici à l'identique — la reposer ne coûte rien.
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

-- Un compte naît non vérifié ET non validé, quoi qu'en dise
-- l'insertion. S'inscrire comme revendeur dépose une demande, rien de
-- plus : c'est ce que fait le formulaire d'inscription.
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
-- 4. Les prix que ce compte-ci a le droit de voir
-- ---------------------------------------------------------
-- « produits_prive » reste fermée : elle porte les taux de marge de
-- chaque boutique, et un revendeur n'a rien à y lire. Il reçoit d'ici
-- une liste de prix, et rien qu'une liste de prix.
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
-- 5. La commande d'un revendeur
-- ---------------------------------------------------------
-- Le régime de prix se décide à l'ouverture de la commande, sur le
-- compte connecté, et il ne bouge plus. Les lignes le lisent ensuite
-- sur leur commande : ajouter une ligne demain à une commande partie
-- au prix revendeur ne la fera pas basculer au prix public.
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

-- Et le régime de prix ne se rejoue pas après coup : la boutique suit
-- la commande, elle ne la bascule pas au prix revendeur une fois
-- l'argent encaissé.
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

-- ---------------------------------------------------------
-- 6. BIZZOO tranche
-- ---------------------------------------------------------
-- La liste que voit le superadministrateur. L'adresse e-mail vient de
-- « auth.users », que personne ne lit directement : c'est la fonction
-- qui va la chercher, après avoir vérifié qui appelle.
-- « drop » avant « create » : ajouter des colonnes au résultat d'une
-- fonction change son type de retour, et PostgreSQL refuse de le changer
-- sur place — « cannot change return type of existing function ». Sans
-- ce retrait, le fichier entier échouerait.
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

-- ---------- Vérification ----------
select
  case when exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'clients'
                       and column_name = 'revendeur_etat')
       then 'en place' else 'MANQUANT' end                      as "clients.revendeur_etat",
  case when exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'commandes'
                       and column_name = 'revendeur')
       then 'en place' else 'MANQUANT' end                      as "commandes.revendeur",
  case when exists (select 1 from pg_proc where proname = 'mes_prix')
       then 'en place' else 'MANQUANT' end                      as "mes_prix()",
  case when exists (select 1 from pg_proc where proname = 'valider_revendeur')
       then 'en place' else 'MANQUANT' end                      as "valider_revendeur()",
  (select count(*)::int from public.clients
    where revendeur_etat = 'en_attente')                        as "demandes en attente",
  (select count(*)::int from public.clients
    where revendeur_etat = 'validee')                           as "revendeurs validés";
