-- =========================================================
-- BIZZOO — panier, commande et paiement KkiaPay
--
-- Le client remplit un panier, valide, paie par Mobile Money.
-- La commande se répartit ensuite entre les boutiques
-- concernées : chacune ne voit que SES lignes, et les prend en
-- charge depuis son compte administrateur.
--
-- TROIS RÈGLES TIENNENT TOUT LE RESTE :
--
--   1. LE CLIENT NE DÉCIDE PAS DU PRIX. Il envoie des produits
--      et des quantités, rien d'autre. La base relit le
--      catalogue, fige le nom, la référence et le prix du
--      moment, et calcule le total. Sans cela, on paierait un
--      ordinateur 100 francs.
--
--   2. LE CLIENT NE DÉCIDE PAS QU'IL A PAYÉ. Une commande naît
--      « à payer ». Le message de succès de KkiaPay arrive sur
--      le TÉLÉPHONE du client : c'est du code qu'on peut
--      modifier, donc on ne le croit pas. Seul KkiaPay, qui
--      détient le secret du webhook, fait passer une commande
--      à « payée » — en appelant la fonction Edge
--      « kkiapay-webhook », qui seule peut appeler
--      marquer_payee().
--
--   3. LE MONTANT QUI COMPTE EST CELUI ANNONCÉ PAR KKIAPAY,
--      jamais celui demandé par l'application. Sinon on
--      manipule le widget pour payer 100 et faire valider une
--      commande de 100 000.
--
-- Il n'y a AUCUNE clé privée là-dedans, ni ici ni dans l'APK :
-- la clé publique est faite pour être publique, et le secret du
-- webhook ne vit que dans les secrets Supabase.
--
-- Les prix sont figés sur la ligne de commande : une hausse de
-- tarif la semaine suivante ne réécrit pas ce qui a été vendu.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, aucune donnée existante modifiée.
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

-- Le compte connecté est-il un revendeur validé ? C'est ce que
-- « commande_a_l_ecriture » demande pour poser le régime de prix.
create or replace function public.est_revendeur() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.clients c
                  where c.id = auth.uid() and c.revendeur_etat = 'validee');
$$;
revoke all on function public.est_revendeur() from public, anon, authenticated;
grant execute on function public.est_revendeur() to authenticated;

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
-- 1. Les réglages du paiement
-- ---------------------------------------------------------
-- La clé publique vit EN BASE, pas dans le code : on passe du
-- bac à sable à la production sans reconstruire ni republier
-- les deux applications. Chez KkiaPay, test et production sont
-- deux mondes séparés — clés différentes, webhooks différents —
-- et les trois interrupteurs se poussent ENSEMBLE.
create table if not exists public.paiement (
  id           int primary key default 1 check (id = 1),
  actif        boolean not null default false,  -- tant que faux : commande sans paiement en ligne
  cle_publique text not null default '',
  bac_a_sable  boolean not null default true,   -- vrai = numéros de test seulement
  maj_le       timestamptz not null default now()
);
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

-- ---------------------------------------------------------
-- 2. Les commandes
-- ---------------------------------------------------------
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
  transaction_id text not null default '',     -- l'identifiant KkiaPay
  -- Vide quand c'est KkiaPay qui a confirmé (le cas normal) ; sinon
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
-- Le verrou réinstallé plus bas garde aussi ces deux colonnes-là. Un
-- fichier qui pose une fonction pose toutes les colonnes qu'elle lit ou
-- écrit, même celles d'un autre fichier : PostgreSQL ne relit le corps
-- d'une fonction qu'à l'exécution, et l'oubli ne se voit qu'au premier
-- passage, sur « record "new" has no field … ».
alter table public.commandes
  add column if not exists fournisseur_ref text not null default '';
alter table public.commandes
  add column if not exists tentative_le timestamptz;

-- À qui appartient cette commande. Le verrou posé plus bas la garde :
-- réattribuer une commande, c'est offrir à quelqu'un l'historique, les
-- avis et le SAV d'un autre. La clé étrangère, elle, est posée par
-- « comptes-clients.sql », seul fichier où la table des clients existe.
alter table public.commandes add column if not exists client_id uuid;

-- Sous quel régime de prix cette commande est partie : prix public, ou
-- prix BIZZOO pour un revendeur validé. Le verrou plus bas l'empêche de
-- basculer après coup. Posée par « comptes-revendeurs.sql », répétée
-- ici : la règle d'écriture ci-dessous la lit.
alter table public.commandes add column if not exists revendeur boolean not null default false;

create index if not exists commandes_etat on public.commandes(etat, cree_le desc);
-- Une transaction KkiaPay ne vaut que pour une commande : c'est ce qui
-- rend le paiement rejouable sans danger (KkiaPay réessaie 5 fois tant
-- qu'il n'a pas reçu un 200).
create unique index if not exists commandes_transaction
  on public.commandes(transaction_id) where transaction_id <> '';

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
-- Le code du produit, ce que la boutique touche, et la marge du jour :
-- figés avec le nom et le prix. La règle d'écriture posée plus bas les
-- remplit — elle a donc besoin qu'ils existent.
alter table public.commande_lignes
  add column if not exists code text not null default '';
alter table public.commande_lignes
  add column if not exists prix_bizzoo int not null default 0;
alter table public.commande_lignes
  add column if not exists taux_marge numeric;

create index if not exists lignes_commande on public.commande_lignes(commande_id);
create index if not exists lignes_boutique on public.commande_lignes(boutique_id, etat);

-- Un numéro lisible, que le client peut dicter au téléphone.
create sequence if not exists public.commandes_numero;

-- ---------------------------------------------------------
-- 3. Ce que personne ne peut écrire à la main
-- ---------------------------------------------------------
-- Une commande naît « à payer », sans transaction et sans date.
-- Même si une règle d'écriture était ajoutée un jour par erreur,
-- ceci resterait vrai.
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

drop trigger if exists lignes_verrous on public.commande_lignes;
create trigger lignes_verrous
  before update on public.commande_lignes
  for each row execute function public.ligne_verrous();

-- ---------------------------------------------------------
-- 4. Qui voit quoi
-- ---------------------------------------------------------
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
create policy "commandes suivi" on public.commandes
  for update to authenticated
  using (public.est_super()) with check (public.est_super());

-- ---------------------------------------------------------
-- 5. Passer commande
-- ---------------------------------------------------------
-- Le téléphone envoie ses coordonnées et une liste
-- { produit_id, quantite }. Rien d'autre n'est écouté : ni prix,
-- ni total, ni état. La base répond avec le montant à payer, et
-- c'est CE montant qui part chez KkiaPay.
-- ---------------------------------------------------------
-- Ce dont les codes promo ont besoin, recopié ici
-- ---------------------------------------------------------
-- « creer_commande » applique désormais un code promo. Un fichier
-- qui pose une fonction pose aussi les fonctions qu'elle appelle :
-- collé seul sur une base d'avant les codes, celui-ci passerait sans
-- broncher et s'arrêterait à la première commande.
-- Sur une base qui les a déjà, ce bloc ne fait rien.

alter table public.commandes add column if not exists code_promo text not null default '';
alter table public.commandes add column if not exists remise bigint not null default 0;

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
   where c.id = cible;
  perform set_config('bizzoo.interne', avant, true);
end $$;
revoke all on function public.commande_total(text) from public, anon, authenticated;

-- LA RÈGLE, EN UN SEUL ENDROIT. L'écran du panier l'appelle pour
-- annoncer la remise ; la caisse l'appelle pour l'appliquer. Deux
-- calculs séparés finiraient par diverger, et le client verrait un
-- montant puis en paierait un autre — c'est déjà la règle que suivent
-- « mes_prix » et « ligne_a_l_ecriture » pour les prix revendeur.
--
-- Rend un objet : { ok, remise, raison }. « raison » est écrite pour
-- être montrée telle quelle au client.
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

  if brute <= 0 then
    return jsonb_build_object('ok', false, 'remise', 0,
      'raison', 'Ce code ne s''applique pas à ce panier.');
  end if;
  return jsonb_build_object('ok', true, 'remise', brute, 'raison', '');
end $$;
revoke all on function public.remise_du_code(text, bigint, bigint, uuid, text)
  from public, anon, authenticated;

-- « drop » avant « create » : cette fonction a gagné un paramètre — le
-- code promo. Un paramètre par défaut n'en remplace pas une, il en crée
-- une seconde, et l'appel devient ambigu : « function is not unique ».
drop function if exists public.creer_commande(jsonb, jsonb);
create or replace function public.creer_commande(
  client jsonb, articles jsonb, code text default '')
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

  select jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'total', c.total, 'devise', c.devise,
    'etat', c.etat,
    /* Ce que le code a retiré, et lequel. Le récapitulatif doit pouvoir
       le dire : un client qui a tapé un code et ne le voit nulle part
       croit qu'il n'a pas été pris. */
    'code_promo', c.code_promo, 'remise', c.remise,
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

-- Un client n'est pas connecté : c'est bien à lui que la fonction sert.
revoke all on function public.creer_commande(jsonb, jsonb, text) from public;
grant execute on function public.creer_commande(jsonb, jsonb, text) to anon, authenticated;

-- ---------------------------------------------------------
-- 6. Suivre sa commande
-- ---------------------------------------------------------
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

-- ---------------------------------------------------------
-- 7. Encaisser — réservé au serveur
-- ---------------------------------------------------------
-- ---------------------------------------------------------
-- Le journal des versements, recopié ici
-- ---------------------------------------------------------
-- Les fonctions de paiement ci-dessous y écrivent. Un fichier qui
-- pose une fonction pose aussi les fonctions qu'elle appelle :
-- collé seul sur une base d'avant le journal, ce fichier passerait
-- sans broncher et s'arrêterait au premier encaissement.
-- Sur une base qui l'a déjà, ce bloc ne fait rien.

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
      c.fournisseur_ref, net, c.total, coalesce(montant, 0),
      'Transaction déjà rattachée à une autre commande.');
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
    perform public.noter_versement(c.id, 'incomplete', qui, '',
      c.fournisseur_ref, net, c.total, coalesce(montant, 0),
      'Reçu ' || coalesce(montant, 0)::text || ' sur ' || c.total::text || ' attendus.');
    return jsonb_build_object('ok', true, 'incomplet', true, 'numero', c.numero);
  end if;

  update public.commandes
     set etat = 'payee', paye_le = now(), transaction_id = net,
         confirme_par = '', remarque = ''
   where id = c.id;
  -- La remarque vient d'être effacée sur la commande : c'est le journal,
  -- désormais, qui garde ce qui s'est passé avant cette réussite.
  perform public.noter_versement(c.id, 'payee', qui, '',
    c.fournisseur_ref, net, c.total, coalesce(montant, 0), 'Versement encaissé.');
  return jsonb_build_object('ok', true, 'numero', c.numero, 'total', c.total);
end $$;

-- LE POINT À NE PAS MANQUER : révoquer du seul pseudo-rôle « public »
-- ne suffit pas. Supabase accorde d'office EXECUTE à « anon » et
-- « authenticated » sur toute fonction du schéma public. Sans ces deux
-- lignes, quiconque extrait la clé publiable de l'APK — et elle y est,
-- par construction — validerait ses commandes sans payer.
revoke all on function public.marquer_payee(text, text, int, text)
  from public, anon, authenticated;

-- Le filet de l'enseigne : si la notification de KkiaPay se perd et
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
  update public.commandes
     set etat = 'payee', paye_le = now(), confirme_par = coalesce(qui, 'enseigne')
   where id = cible and etat <> 'payee'
  returning total into montant;

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

-- ---------------------------------------------------------
-- 8. Temps réel
-- ---------------------------------------------------------
-- La boutique voit arriver la commande sans rouvrir son application.
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['commandes', 'commande_lignes'] loop
      if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
      ) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;

-- ---------- Vérification ----------
-- 1. Seul service_role doit pouvoir encaisser.
--    « marquer_payee » ne doit apparaître QUE sur la ligne service_role.
select p.proname as "fonction", r.rolname as "qui peut l'appeler"
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 cross join lateral (
   select rolname from pg_roles
    where rolname in ('anon', 'authenticated', 'service_role')
      and has_function_privilege(rolname, p.oid, 'EXECUTE')
 ) r
 where n.nspname = 'public'
   and p.proname in ('marquer_payee', 'creer_commande', 'confirmer_paiement')
 order by 1, 2;

-- 2. Les tables sont fermées comme il faut.
select c.relname as "table",
       case when c.relrowsecurity then 'oui' else 'NON — à corriger' end as "RLS",
       count(p.polname) as "règles"
  from pg_class c
  left join pg_policy p on p.polrelid = c.oid
 where c.relname in ('commandes', 'commande_lignes', 'paiement')
 group by 1, 2 order by 1;

-- 3. Les garde-fous du prix et de l'état.
select c.relname as "table", t.tgname as "garde-fou"
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
 where not t.tgisinternal and c.relname in ('commandes', 'commande_lignes')
 order by 1, 2;

-- 4. Les commandes (aucune au départ : normal).
select etat, count(*) as "combien", coalesce(sum(total), 0) as "montant"
  from public.commandes group by 1 order by 1;
