-- =========================================================
-- BIZZOO — état des lieux du STOCKAGE
--
-- Ce fichier ne modifie RIEN. Il répond en UNE SEULE requête,
-- donc en un seul tableau : l'éditeur SQL de Supabase n'affiche
-- que le résultat de la dernière requête d'un bloc, et tout ce
-- qui précède se perdrait en silence.
--
-- Ce qu'il montre, dans l'ordre :
--
--   1. SEAUX        les seaux qui existent, et ce qu'ils laissent passer
--   2. RÈGLES       qui a le droit de déposer, et où
--   3. DOSSIERS     combien de fichiers et quel poids, dossier par dossier
--   4. TYPES        photos et vidéos, combien de chaque et quel poids
--   5. TOTAL        le poids de tout le stockage, et la part du 1 Go gratuit
--   6. PLUS GROS    les quinze fichiers les plus lourds
--   7. ORPHELINS    ceux que plus aucune ligne de la base ne désigne
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : aucune écriture, aucune suppression.
-- =========================================================

with

-- Le poids d'un fichier est rangé par Supabase dans « metadata ».
-- Un fichier déposé autrement que par l'API peut n'y rien avoir :
-- il compte alors pour zéro plutôt que de faire échouer la lecture.
fichiers as (
  select o.bucket_id,
         o.name,
         o.created_at,
         coalesce((o.metadata->>'size')::bigint, 0) as poids,
         coalesce(o.metadata->>'mimetype', '?')     as type,
         -- Le premier segment du chemin dit à qui le fichier appartient :
         -- « enseigne/ » à BIZZOO, « slider/ » et « boutique(s)/ » à une
         -- boutique, le reste aux photos de produits.
         coalesce(nullif(split_part(o.name, '/', 1), o.name), '(produits)') as dossier
    from storage.objects o
),

-- Tout ce qu'une ligne de la base désigne encore. Ce qui n'y figure
-- pas est un orphelin : une photo retirée d'un produit reste dans le
-- seau, la base ne la suit plus, le stockage la garde.
--
-- Cette liste doit être COMPLÈTE. Un fichier oublié ici serait annoncé
-- « supprimable » alors qu'il est à l'écran — et une suppression ne se
-- rattrape pas. En cas de doute, mieux vaut garder un fichier de trop.
utilises as (
  select unnest(p.images) as chemin from public.produits p
  union select p.video from public.produits  p where coalesce(p.video, '') <> ''
  union select b.logo  from public.boutiques b where coalesce(b.logo,  '') <> ''
  union select b.video from public.boutiques b where coalesce(b.video, '') <> ''
  union select unnest(b.photos) from public.boutiques b
  union select s.image from public.slides    s where coalesce(s.image, '') <> ''
  union select s.video from public.slides    s where coalesce(s.video, '') <> ''
  -- La boutique d'origine, celle d'avant les boutiques multiples : elle
  -- existe toujours, et ses photos aussi.
  union select o.video from public.boutique  o where coalesce(o.video, '') <> ''
  union select unnest(o.photos) from public.boutique o
),

-- Les fichiers déposés pour une demande de modification que l'enseigne
-- n'a pas encore tranchée. Ils ne sont ENCORE dans aucune colonne — le
-- logo proposé n'est pas le logo en place — et disparaîtraient si on
-- suivait la liste ci-dessus. On les reconnaît en cherchant le nom du
-- fichier dans le texte de la demande : grossier, mais du bon côté.
en_attente as (
  select d.apres::text || coalesce(d.avant::text, '') as texte
    from public.demandes d
   where d.etat = 'en_attente'
),

lignes as (

  -- 1. Les seaux ----------------------------------------------------
  select 1 as rang, 0::bigint as tri,
         'SEAUX'                                        as "section",
         b.id                                           as "quoi",
         case when b.public then 'lecture publique' else 'privé' end as "détail 1",
         coalesce(pg_size_pretty(b.file_size_limit), 'AUCUNE LIMITE') as "détail 2",
         coalesce(array_to_string(b.allowed_mime_types, ', '), 'TOUS LES TYPES') as "détail 3"
    from storage.buckets b

  -- 2. Qui peut faire quoi ------------------------------------------
  -- Les règles du stockage sont des politiques ordinaires, posées sur
  -- « storage.objects ».
  union all
  select 2, 0,
         'RÈGLES',
         p.polname,
         case p.polcmd when 'r' then 'lecture'      when 'a' then 'dépôt'
                       when 'w' then 'modification' when 'd' then 'suppression'
                       else 'tout' end,
         coalesce((select string_agg(r.rolname, ', ')
                     from pg_roles r where r.oid = any(p.polroles)), 'tous les rôles'),
         ''
    from pg_policy p
    join pg_class c     on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'storage' and c.relname = 'objects'

  -- 3. Ce qui est stocké, dossier par dossier -----------------------
  union all
  select 3, sum(f.poids),
         'DOSSIERS',
         f.dossier,
         f.bucket_id,
         count(*)::text || ' fichier(s)',
         pg_size_pretty(sum(f.poids))
    from fichiers f
   group by f.dossier, f.bucket_id

  -- 4. Par type de fichier -------------------------------------------
  -- C'est ce qui décide s'il faut un seau à part pour les vidéos : la
  -- limite de 60 Mo n'existe que pour elles, et elle s'applique
  -- aujourd'hui aussi aux photos de produits.
  union all
  select 4, sum(f.poids),
         'TYPES',
         f.type,
         count(*)::text || ' fichier(s)',
         pg_size_pretty(sum(f.poids)),
         'le plus gros : ' || pg_size_pretty(max(f.poids))
    from fichiers f
   group by f.type

  -- 5. Le total ------------------------------------------------------
  union all
  select 5, 0,
         'TOTAL',
         'tout le stockage',
         count(*)::text || ' fichier(s)',
         pg_size_pretty(coalesce(sum(f.poids), 0)),
         -- L'offre gratuite de Supabase s'arrête à 1 Go.
         'sur 1 Go (offre gratuite) : ' ||
           round(coalesce(sum(f.poids), 0) * 100.0 / 1073741824, 1)::text || ' %'
    from fichiers f

  -- 6. Les plus gros -------------------------------------------------
  -- C'est ici qu'on voit si une image est partie sans être compressée :
  -- l'application les réduit à 1100 px avant l'envoi, donc au-delà de
  -- 1 Mo, une image n'est pas passée par elle.
  union all
  select 6, g.poids,
         'PLUS GROS',
         g.name,
         g.type,
         pg_size_pretty(g.poids),
         g.created_at::date::text
    from (select * from fichiers order by poids desc limit 15) g

  -- 7. Ce que plus personne n'utilise --------------------------------
  union all
  select 7, o.poids,
         'ORPHELINS',
         -- LE SEAU EN TÊTE DU CHEMIN. Sans lui, le script de ménage doit
         -- deviner dans quel seau supprimer ; deux seaux peuvent porter
         -- le même chemin, et il effacerait un fichier bien vivant en
         -- croyant nettoyer l'autre. Une suppression ne se rattrape pas :
         -- on ne laisse rien à deviner.
         o.bucket_id || '/' || o.name,
         pg_size_pretty(o.poids),
         o.created_at::date::text,
         'plus référencé — supprimable'
    -- 200, et non 30 : une liste tronquee en silence donnerait
    -- l'impression d'avoir tout vu, et le menage serait a moitie fait.
    from (select * from fichiers f
           where f.name not in (select chemin from utilises where chemin is not null)
             and not exists (select 1 from en_attente a where a.texte like '%' || f.name || '%')
           order by f.poids desc limit 200) o
)

select "section", "quoi", "détail 1", "détail 2", "détail 3"
  from lignes
 order by rang, tri desc, "quoi";
