-- =========================================================
-- BIZZOO — la marge change, les prix suivent
--
-- Le modèle de l'enseigne est simple : prix de vente = prix
-- BIZZOO + marge. Mais le prix de vente était CALCULÉ PAR
-- L'APPLICATION au moment d'enregistrer le produit, puis figé
-- dans la table.
--
-- Conséquence : changer la marge d'une boutique ne touchait
-- RIEN. Il fallait rouvrir et réenregistrer chaque article, un
-- par un, pour que la nouvelle marge s'applique. Personne ne
-- fait cela sur deux cents articles — si bien que la marge
-- affichée dans les réglages et celle réellement pratiquée
-- divergeaient en silence, et les comptes de l'enseigne avec
-- elles.
--
-- La base s'en charge désormais elle-même : changer la marge
-- d'une boutique recalcule le prix de vente de tous ses
-- articles, à l'instant.
--
-- DEUX CHOSES QU'ELLE NE TOUCHE PAS :
--
--   UN ARTICLE QUI A SON PROPRE TAUX. C'est déjà la règle que
--     « produits_prive.taux_marge » suit partout ailleurs : son
--     prix se recalcule avec SON taux, jamais celui de la
--     boutique.
--   CE QUI A ÉTÉ VENDU. La ligne de commande garde le prix et
--     le taux du jour de la vente. Changer la marge aujourd'hui
--     ne réécrit pas les comptes d'hier.
--
-- Et elle ne touche pas « modifie_le » : c'est lui qui déclenche
-- la notification « catalogue mis à jour » sur les téléphones.
-- Un changement de marge doit rafraîchir les écrans ouverts, pas
-- réveiller toute la ville.
--
-- CE QUE CE FICHIER CHANGE LE JOUR OÙ VOUS L'EXÉCUTEZ : rien.
-- Il pose la règle ; elle ne s'appliquera qu'au prochain
-- changement de marge. Vos prix actuels restent tels quels.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, et rien n'est supprimé.
-- =========================================================

-- Les colonnes dont la règle se sert. Elles viennent d'ailleurs, et sont
-- répétées ici : un fichier qui pose une fonction pose aussi les
-- colonnes qu'elle touche.
alter table public.boutiques
  add column if not exists taux_marge numeric(6,2) not null default 20;
alter table public.boutiques add column if not exists note_moyenne numeric(3,2);
alter table public.boutiques add column if not exists nb_avis int not null default 0;
alter table public.boutiques
  add column if not exists revendeur_mode text not null default 'bizzoo';
alter table public.boutiques
  add column if not exists taux_revendeur numeric(6,2) not null default 10;
alter table public.produits_prive add column if not exists taux_marge numeric(6,2);

-- ---------------------------------------------------------
-- 1. Le calcul, le même que celui de l'application
-- ---------------------------------------------------------
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

-- ---------------------------------------------------------
-- 2. Et la règle qui l'applique
-- ---------------------------------------------------------
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

-- ---------- Vérification ----------
-- Ce que vaudrait chaque article si on rejouait le calcul aujourd'hui.
-- « Prix affiché » et « Prix recalculé » doivent être ÉGAUX : s'ils
-- diffèrent, c'est qu'une marge a été changée avant que ce fichier ne
-- soit posé — le prochain changement de marge les remettra d'accord.
select b.nom                                        as "Boutique",
       p.nom                                        as "Article",
       p.prix                                       as "Prix affiché",
       public.prix_public(pp.prix_grossiste,
         coalesce(pp.taux_marge, b.taux_marge))     as "Prix recalculé",
       case when p.prix = public.prix_public(pp.prix_grossiste,
              coalesce(pp.taux_marge, b.taux_marge))
            then 'd''accord' else 'À REMETTRE D''ACCORD' end as "Verdict"
  from public.produits p
  join public.boutiques b on b.id = p.boutique_id
  join public.produits_prive pp on pp.produit_id = p.id
 where coalesce(pp.prix_grossiste, 0) > 0
 order by 5 desc, b.nom, p.nom
 limit 10;
