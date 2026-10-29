-- =========================================================
-- BIZZOO — changer le secteur d'une boutique : ses produits suivent
-- (3.70.0)
--
-- Avant : changer le secteur d'une boutique DÉCLASSAIT tout son
-- catalogue. Ses produits n'étaient plus sous aucune catégorie : dans
-- l'application cliente, la boutique n'apparaissait pas dans le
-- secteur qu'on venait de lui donner.
--
-- Désormais :
--   - chaque produit va dans le rayon du MÊME NOM du nouveau secteur,
--     s'il en a un ;
--   - les autres restent « à classer », mais DANS le nouveau secteur :
--     le client les voit sous la catégorie (« Tout voir ») ;
--   - « apercu_secteur() » dit, avant de confirmer, combien suivent et
--     combien resteront à ranger.
--
-- CE QUE CE FICHIER CHANGE LE JOUR OÙ VOUS L'EXÉCUTEZ : les produits
-- « à classer » de chaque boutique sont rangés dans le secteur de leur
-- boutique (sans rayon). Rien d'autre ne bouge.
--
-- Sans danger : relançable, et rien n'est supprimé.
-- =========================================================

-- Les colonnes dont ces fonctions se servent. Elles viennent d'ailleurs,
-- et sont répétées ici : un fichier qui pose une fonction pose aussi les
-- colonnes qu'elle touche.
alter table public.boutiques add column if not exists maj_le timestamptz not null default now();
alter table public.produits add column if not exists modifie_le timestamptz not null default now();
alter table public.produits add column if not exists sous_categorie_id text references public.sous_categories(id);
alter table public.produits
  add column if not exists boutique_id text references public.boutiques(id) on delete cascade;
alter table public.produits add column if not exists code text not null default '';
alter table public.produits add column if not exists note_moyenne numeric(3,2);
alter table public.produits add column if not exists nb_avis int not null default 0;
create sequence if not exists public.produits_code start with 100001;

-- ---------------------------------------------------------
-- 1. Un produit sans rayon reste dans le secteur de sa boutique
-- ---------------------------------------------------------
create or replace function public.produit_code() returns trigger
language plpgsql security definer set search_path = public as $$
declare rayon text; secteur text;
begin
  /* ---------- LE RAYON ----------
     La boutique choisit une SOUS-CATÉGORIE ; la catégorie s'en déduit.
     Ce que l'application envoie dans « categorie_id » n'est jamais
     écouté : deux colonnes qu'on laisserait se contredire, c'est un
     classement qui ment — le produit serait dans un rayon à l'écran et
     dans un autre dans les comptes. */
  if coalesce(new.sous_categorie_id, '') = '' then
    -- À CLASSER. Le produit reste en vente, dans sa boutique et dans la
    -- recherche ; il n'apparaît sous aucun rayon de BIZZOO.
    new.sous_categorie_id := null;
    -- (3.70.0) Mais il reste DANS LE SECTEUR de sa boutique : sans cela,
    -- une boutique qui change de secteur disparaissait du nouveau dans
    -- l'application cliente, ses produits n'étant plus nulle part.
    select b.categorie_id into secteur
      from public.boutiques b where b.id = new.boutique_id;
    new.categorie_id := secteur;
  else
    select sc.categorie_id into rayon
      from public.sous_categories sc where sc.id = new.sous_categorie_id;
    if rayon is null then
      raise exception 'Cette sous-catégorie n''existe pas';
    end if;
    /* ET ELLE DOIT ÊTRE DU SECTEUR DE LA BOUTIQUE. C'est tout l'objet
       de la liste de l'enseigne : une boutique de cosmétiques qui
       publierait sous « Pièces détachées » rendrait le classement
       inutilisable pour l'acheteur. */
    select b.categorie_id into secteur
      from public.boutiques b where b.id = new.boutique_id;
    if secteur is null then
      raise exception 'Cette boutique n''a pas encore de secteur : l''enseigne doit lui en donner un';
    end if;
    if rayon <> secteur then
      raise exception 'Un produit se range dans une sous-catégorie du secteur de sa boutique';
    end if;
    new.categorie_id := rayon;
  end if;

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

-- ---------------------------------------------------------
-- 2. Changer le secteur : les produits suivent
-- ---------------------------------------------------------
-- (3.70.0) ELLE NE DÉCLASSE PLUS TOUT. Chaque produit va dans le rayon
-- du MÊME NOM du nouveau secteur, s'il en a un ; les autres restent « à
-- classer », mais DANS le nouveau secteur (« produit_code » y range tout
-- produit sans rayon). Avant, tout le catalogue passait sous aucune
-- catégorie : dans l'application cliente, la boutique n'apparaissait
-- pas dans le secteur qu'on venait de lui donner.
-- Elle rend le nombre de produits restés « à classer ».
create or replace function public.changer_secteur(boutique text, vers text)
returns int
language plpgsql security definer set search_path = public as $$
declare combien int; ancien text; cible text := nullif(coalesce(vers, ''), '');
begin
  if not public.est_super() then
    raise exception 'Le secteur d''une boutique est fixé par l''enseigne';
  end if;
  if coalesce(boutique, '') = ''
     or not exists (select 1 from public.boutiques b where b.id = boutique) then
    raise exception 'Cette boutique n''existe pas';
  end if;
  -- Un secteur vide retire la boutique de la liste : elle n'apparaît
  -- plus sous aucune catégorie, et ne peut plus classer ses produits.
  if coalesce(vers, '') <> ''
     and not exists (select 1 from public.categories c where c.id = vers) then
    raise exception 'Cette catégorie n''existe pas';
  end if;

  select b.categorie_id into ancien from public.boutiques b where b.id = boutique;

  -- La boutique D'ABORD : « produit_code » range chaque produit dans le
  -- secteur de sa boutique, il faut qu'il y lise le nouveau.
  perform set_config('bizzoo.secteur', 'oui', true);
  update public.boutiques
     set categorie_id = cible, maj_le = now()
   where id = boutique;
  perform set_config('bizzoo.secteur', '', true);

  -- Puis ses produits : le rayon du même nom dans le nouveau secteur, ou
  -- « à classer ». « modifie_le » bouge : les téléphones relisent le
  -- catalogue, et y trouvent la boutique à sa nouvelle place.
  if cible is distinct from ancien then
    update public.produits p
       set sous_categorie_id = (
             select nv.id
               from public.sous_categories av
               join public.sous_categories nv
                 on nv.categorie_id = cible
                and lower(btrim(nv.nom)) = lower(btrim(av.nom))
              where av.id = p.sous_categorie_id
              order by nv.ordre, nv.id
              limit 1),
           modifie_le = now()
     where p.boutique_id = boutique;
  end if;

  select count(*)::int into combien
    from public.produits p
   where p.boutique_id = boutique and p.sous_categorie_id is null;
  return combien;
end $$;
revoke all on function public.changer_secteur(text, text) from public, anon, authenticated;
grant execute on function public.changer_secteur(text, text) to authenticated;

-- ---------------------------------------------------------
-- 3. L'aperçu, avant de confirmer
-- ---------------------------------------------------------
-- (3.70.0) Ce que ferait « changer_secteur(boutique, vers) », AVANT de
-- le faire : combien de produits trouvent un rayon du même nom dans le
-- nouveau secteur, combien resteront « à classer » (dans ce secteur).
create or replace function public.apercu_secteur(boutique text, vers text) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.est_super() then null else
    jsonb_build_object(
      'produits', count(*),
      'suivent', count(*) filter (where s.nv is not null),
      'a_classer', count(*) filter (where s.nv is null))
  end
    from public.produits p
    cross join lateral (
      select (select nv.id
                from public.sous_categories av
                join public.sous_categories nv
                  on nv.categorie_id = nullif(coalesce(vers, ''), '')
                 and lower(btrim(nv.nom)) = lower(btrim(av.nom))
               where av.id = p.sous_categorie_id
               limit 1) as nv) s
   where p.boutique_id = boutique;
$$;
revoke all on function public.apercu_secteur(text, text) from public, anon, authenticated;
grant execute on function public.apercu_secteur(text, text) to authenticated;

-- ---------------------------------------------------------
-- 4. La réparation des produits « à classer » d'avant
-- ---------------------------------------------------------
-- (3.70.0) LA RÉPARATION. Les produits « à classer » d'avant n'avaient
-- plus de secteur du tout : ceux d'une boutique qui avait changé de
-- secteur n'apparaissaient pas dans le nouveau, côté client. Les
-- toucher suffit — « produit_code » les range dans le secteur de leur
-- boutique. Relançable : ne touche que ce qui n'y est pas encore.
update public.produits p
   set modifie_le = now()
  from public.boutiques b
 where b.id = p.boutique_id
   and p.sous_categorie_id is null
   and p.categorie_id is distinct from b.categorie_id;
