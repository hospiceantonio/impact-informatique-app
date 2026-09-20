-- =========================================================
-- BIZZOO — ce que le client lit de SES commandes
--
-- Depuis que le client se connecte, il lit une partie de la
-- table des commandes : la sienne. C'est ce qui lui rend son
-- historique d'un téléphone à l'autre, et c'était bien le but.
--
-- Mais cela change la question posée à chaque colonne. « Est-ce
-- que l'équipe peut la voir ? » devient « et l'acheteur ? ». Or
-- deux colonnes de « commande_lignes » n'ont rien à faire sous
-- ses yeux :
--
--   « prix_bizzoo » — ce que la boutique a touché, c'est-à-dire
--                     SON PRIX D'ACHAT. Le montrer à l'acheteur,
--                     c'est lui montrer la marge de la boutique
--                     sur chaque article qu'il vient de payer ;
--   « taux_marge »  — celle de l'enseigne, pour la même raison.
--
-- UNE RÈGLE RLS NE LES FERME PAS. Elle décide des LIGNES qu'on
-- voit, jamais des COLONNES : la règle « lignes lecture client »
-- rend la ligne entière, prix d'achat compris. Il faut des
-- droits par colonne, et c'est tout l'objet de ce fichier.
--
-- Ce n'était pas une faute de la règle, mais une conséquence :
-- avant les comptes clients, personne hors de l'équipe ne
-- lisait cette table, et la question ne se posait pas. Le banc
-- l'a trouvée en éprouvant l'historique.
--
-- Ce que l'enseigne perd : rien. Ses chiffres passent par
-- « statistiques_ventes() », qui s'exécute avec les droits de
-- son propriétaire et ignore donc ces restrictions.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, et rien n'est supprimé.
-- =========================================================

-- Les colonnes visées existent-elles ? Sur une base d'avant la marge,
-- non — et « revoke » sur une colonne absente échouerait.
alter table public.commande_lignes
  add column if not exists prix_bizzoo int not null default 0;
alter table public.commande_lignes
  add column if not exists taux_marge numeric;
alter table public.commande_lignes
  add column if not exists code text not null default '';

-- ---------------------------------------------------------
-- Les droits, colonne par colonne
-- ---------------------------------------------------------
-- On retire d'abord le droit de lecture ENTIER, puis on redonne
-- colonne par colonne. L'ordre compte : un « grant » par colonne
-- posé sur un droit de table déjà accordé ne retire rien.
--
-- Effet de bord assumé et voulu : « select=* » ne fonctionne plus
-- pour un compte connecté. Les écrans nomment désormais ce qu'ils
-- demandent — ce qui est de toute façon la bonne façon de lire une
-- table dont toutes les colonnes ne les regardent pas.
-- L'accusé de réception du client. Répété ici : ce fichier pose la
-- liste des colonnes lisibles, et rejoué après le schéma il la
-- REFERMERAIT s'il ne la citait pas.
alter table public.commande_lignes add column if not exists confirme_le timestamptz;
revoke select on public.commande_lignes from authenticated;
grant select (
  id, commande_id, boutique_id, produit_id,
  nom, code, reference, prix, quantite, etat, cree_le, confirme_le
) on public.commande_lignes to authenticated;

-- « anon » n'a jamais rien eu ici, et n'aura jamais rien : une
-- commande ne se lit pas sans compte. On le réaffirme, parce que les
-- droits par défaut de Supabase sont généreux avec les tables neuves.
revoke all on public.commande_lignes from anon;

-- L'équipe garde ce qu'il lui faut pour préparer et suivre : écrire
-- l'état d'une ligne. Le verrou « ligne_verrous » continue de refuser
-- tout le reste — ce qui a été vendu est vendu.
-- LE RETRAIT D'ABORD, sans quoi la ligne suivante n'ajoute rien du
-- tout : une base Supabase donne « grant all » d'office à
-- « authenticated » sur toute table du schéma public, et un droit de
-- colonne posé par-dessus n'en retire aucun.
revoke update on public.commande_lignes from authenticated;
grant update (etat) on public.commande_lignes to authenticated;

-- ---------- Vérification ----------
-- Ce que « authenticated » peut lire, colonne par colonne. Les deux
-- colonnes de marge doivent être ABSENTES de cette liste.
select
  string_agg(column_name, ', ' order by column_name)                as "lisible par un compte connecté",
  case when bool_or(column_name in ('prix_bizzoo', 'taux_marge'))
       then 'FUITE : la marge est lisible'
       else 'la marge reste fermée' end                              as "verdict"
  from information_schema.column_privileges
 where table_schema = 'public'
   and table_name = 'commande_lignes'
   and grantee = 'authenticated'
   and privilege_type = 'SELECT';
