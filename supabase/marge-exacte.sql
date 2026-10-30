-- =========================================================
-- BIZZOO — la marge réglée, exactement (3.70.0)
--
-- Prix de vente = prix BIZZOO + marge de l'enseigne. Le résultat
-- était arrondi au franc LE PLUS PROCHE : 2 273 + 10 % = 2 500,3,
-- arrondi à 2 500. BIZZOO ne gardait alors que 227 F, soit 9,99 %
-- au lieu des 10 % réglés dans l'admin.
--
-- Désormais l'arrondi se fait au franc SUPÉRIEUR : 2 501, soit
-- 228 F pour BIZZOO. La marge réglée est toujours tenue, jamais
-- rabotée par l'arrondi — c'est déjà la règle du prix revendeur.
--
-- CE QUE CE FICHIER CHANGE LE JOUR OÙ VOUS L'EXÉCUTEZ : les seuls
-- articles dont le prix venait de l'ancien arrondi et y perdaient
-- une fraction de franc prennent 1 F de plus. Un article dont le
-- prix suit une autre règle (saisi à la main avant le calcul
-- automatique) n'est pas touché. « modifie_le » ne bouge pas : pas
-- de notification « catalogue mis à jour » sur les téléphones.
--
-- Ce qui a été vendu ne bouge pas : la ligne de commande garde le
-- prix du jour de la vente.
--
-- Sans danger : relançable, et rien n'est supprimé.
-- =========================================================

-- Les colonnes dont le calcul se sert. Elles viennent d'ailleurs, et sont
-- répétées ici : un fichier qui pose une fonction pose aussi les
-- colonnes qu'elle touche.
alter table public.boutiques
  add column if not exists taux_marge numeric(6,2) not null default 20;
alter table public.produits_prive add column if not exists taux_marge numeric(6,2);

-- ---------------------------------------------------------
-- 1. Le calcul, arrondi au franc supérieur
-- ---------------------------------------------------------
create or replace function public.prix_public(prix_bizzoo bigint, taux numeric)
returns int
language sql immutable as $$
  -- Le même calcul, au franc près, que celui de l'application admin.
  -- Les deux doivent donner le même chiffre : sinon réenregistrer un
  -- produit déplacerait son prix sans que personne ne l'ait demandé.
  -- (3.70.0) Arrondi au franc SUPÉRIEUR : la marge réglée est toujours
  -- tenue. 2 273 + 10 % = 2 500,3 → 2 501 ; l'arrondi au plus proche
  -- donnait 2 500, soit 9,99 % pour BIZZOO au lieu des 10 % réglés.
  select case when coalesce(prix_bizzoo, 0) <= 0 then 0
              else ceil(prix_bizzoo * (1 + greatest(0, coalesce(taux, 0)) / 100))::int
         end;
$$;
revoke all on function public.prix_public(bigint, numeric) from public, anon, authenticated;
grant execute on function public.prix_public(bigint, numeric) to authenticated;

-- ---------------------------------------------------------
-- 2. Les articles qui perdaient une fraction de franc
-- ---------------------------------------------------------
-- Seulement ceux dont le prix est EXACTEMENT l'ancien arrondi : c'est la
-- preuve qu'il vient du calcul, et qu'il n'a pas été posé autrement.
-- Un prix barré qui ne serait plus au-dessus du nouveau prix tombe :
-- l'application refuse déjà un prix barré qui n'est pas l'ancien prix.
with nouveau as (
  select p.id,
         public.prix_public(pp.prix_grossiste,
                            coalesce(pp.taux_marge, b.taux_marge)) as prix
    from public.produits p
    join public.boutiques b on b.id = p.boutique_id
    join public.produits_prive pp on pp.produit_id = p.id
   where coalesce(pp.prix_grossiste, 0) > 0
     and p.prix = round(pp.prix_grossiste
                        * (1 + greatest(0, coalesce(pp.taux_marge, b.taux_marge, 0)) / 100))
)
update public.produits p
   set prix = n.prix,
       ancien_prix = case when p.ancien_prix is not null and p.ancien_prix <= n.prix
                          then null else p.ancien_prix end
  from nouveau n
 where n.id = p.id
   and p.prix is distinct from n.prix;

-- ---------- Vérification ----------
-- « À REMETTRE D'ACCORD » ne doit plus apparaître que pour un article
-- dont le prix ne venait pas du calcul.
select count(*) filter (where p.prix = public.prix_public(pp.prix_grossiste,
                          coalesce(pp.taux_marge, b.taux_marge))) as "Articles d'accord",
       count(*) filter (where p.prix <> public.prix_public(pp.prix_grossiste,
                          coalesce(pp.taux_marge, b.taux_marge))) as "À REMETTRE D'ACCORD"
  from public.produits p
  join public.boutiques b on b.id = p.boutique_id
  join public.produits_prive pp on pp.produit_id = p.id
 where coalesce(pp.prix_grossiste, 0) > 0;
