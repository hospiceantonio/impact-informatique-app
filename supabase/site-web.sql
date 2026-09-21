-- =========================================================
-- BIZZOO — l'adresse du site web
--
-- Une seule chose arrive avec ce fichier : la colonne
-- « site_web », sur l'enseigne et sur chaque boutique. Elle
-- porte ce que le gérant tape dans ses réglages — « bizzoo.bj »
-- aussi bien que « https://www.bizzoo.bj/boutique ». C'est
-- l'application qui en fait une adresse ouvrable, comme elle le
-- fait déjà pour Facebook ou Instagram.
--
-- CE QUE CE FICHIER NE DÉFAIT PAS : rien. Il ajoute deux
-- colonnes vides, avec « if not exists ». Aucun produit, aucune
-- commande, aucun réglage existant n'est touché, et on peut le
-- coller deux fois de suite sans conséquence.
--
-- QUI PEUT L'ÉCRIRE : personne de nouveau. La colonne suit les
-- règles déjà posées sur « boutique » et « boutiques » — le
-- superadministrateur pour l'enseigne, l'équipe d'une boutique
-- pour la sienne. Rien n'est ouvert ici.
--
-- QUI PEUT LA LIRE : tout le monde, comme le nom et l'adresse.
-- Un site web est fait pour être donné ; ce n'est pas une
-- coordonnée privée.
-- =========================================================

alter table public.boutique  add column if not exists site_web text not null default '';
alter table public.boutiques add column if not exists site_web text not null default '';

-- Un contrôle à la fin : les deux colonnes doivent être là.
do $$
declare manque text := '';
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'boutique'
                    and column_name = 'site_web') then
    manque := manque || ' boutique.site_web';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'boutiques'
                    and column_name = 'site_web') then
    manque := manque || ' boutiques.site_web';
  end if;
  if manque <> '' then
    raise exception 'Colonne(s) manquante(s) :%', manque;
  end if;
  raise notice 'Le site web est posé sur l''enseigne et sur les boutiques.';
end $$;
