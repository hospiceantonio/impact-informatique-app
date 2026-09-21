-- =========================================================
-- BIZZOO — chaque boutique voit ce qu'elle vend
--
-- Jusqu'ici, l'écran des ventes était réservé à l'enseigne :
-- il porte le prix payé par le client, le taux de marge et le
-- bénéfice de BIZZOO, sur TOUTES les boutiques à la fois. Une
-- boutique n'a rien à y lire — et la base le lui refusait.
--
-- Mais une boutique a besoin de savoir ce qu'elle vend. D'où
-- une SECONDE fonction, volontairement plus pauvre :
--
--   statistiques_ventes()    l'enseigne, toutes boutiques,
--                            avec marge et bénéfice
--   statistiques_boutique()  la sienne seulement, et
--                            uniquement ce qui lui revient
--
-- DEUX PRÉCAUTIONS, ET ELLES COMPTENT :
--
--   LES CHIFFRES DE L'ENSEIGNE NE SORTENT PAS. Ni le prix payé
--     par le client, ni le taux de marge, ni le bénéfice. Ils
--     ne sont pas « masqués à l'écran » : ils ne sont pas dans
--     le résultat. Une colonne qu'on se contente de cacher se
--     relit avec n'importe quel outil.
--   LA BOUTIQUE NE SE CHOISIT PAS. La fonction ne prend que
--     deux dates. Pas de paramètre « boutique » : c'est
--     toujours celle du compte connecté. Un paramètre serait
--     une invitation à viser la voisine, et il faudrait le
--     défendre à chaque appel.
--
-- CE QU'ELLE COMPTE : les commandes PAYÉES, et seulement les
-- lignes que la boutique n'a pas annulées. Un panier abandonné
-- ou une ligne qu'elle n'a pas pu fournir ne gonflent pas ses
-- chiffres. Les montants sont ceux du JOUR DE LA VENTE, figés
-- sur la ligne : changer une marge aujourd'hui ne réécrit pas
-- les comptes d'hier.
--
-- CE QUE CE FICHIER CHANGE LE JOUR OÙ VOUS L'EXÉCUTEZ : il
-- ouvre l'écran « Ce que vend votre boutique » à vos gérants.
-- Rien d'autre ne bouge : aucune donnée n'est touchée, et
-- l'écran de l'enseigne reste exactement ce qu'il était.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, et rien n'est supprimé.
-- =========================================================

-- Les colonnes que la fonction lit. Elles viennent d'ailleurs, et sont
-- répétées ici : un fichier qui pose une fonction pose aussi les
-- colonnes dont elle se sert. Sur une base qui les a déjà, ces lignes
-- ne font rien.
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


alter table public.commande_lignes
  add column if not exists code text not null default '';
alter table public.commande_lignes
  add column if not exists prix_bizzoo int not null default 0;

-- ---------- Ce qu'une boutique a vendu ----------
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

-- ---------- Vérification ----------
-- Ce que l'écran affichera à chacun de vos gérants. Une ligne par
-- boutique et par produit vendu, avec ce qui revient à la boutique.
--
-- Vous lisez ceci en tant qu'ENSEIGNE, donc toutes les boutiques à la
-- fois : c'est la requête de contrôle, pas la fonction. Chaque gérant,
-- lui, n'a accès qu'à la sienne — c'est ce que la fonction ci-dessus
-- garantit, et ce que le banc d'essai vérifie à chaque livraison.
--
-- Aucune vente encore encaissée ? Zéro ligne, et c'est normal.
select b.nom                                   as "Boutique",
       l.nom                                   as "Article",
       sum(l.quantite)                         as "Vendus",
       count(distinct l.commande_id)           as "Commandes",
       l.prix_bizzoo                           as "Prix BIZZOO",
       sum(l.quantite) * l.prix_bizzoo         as "Revient à la boutique"
  from public.commande_lignes l
  join public.commandes c on c.id = l.commande_id
  join public.boutiques  b on b.id = l.boutique_id
 where c.etat = 'payee' and l.etat <> 'annulee'
 group by b.nom, l.nom, l.prix_bizzoo
 order by 6 desc
 limit 20;
