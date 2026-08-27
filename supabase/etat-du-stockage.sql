-- =========================================================
-- BIZZOO — état des lieux du STOCKAGE
--
-- Ce fichier ne modifie RIEN. Il répond à quatre questions,
-- avant de décider quoi que ce soit sur les seaux (buckets) :
--
--   1. Quels seaux existent, et que laissent-ils passer ?
--   2. Qui a le droit d'y déposer, et où ?
--   3. Combien de fichiers, et quel poids, dossier par dossier ?
--   4. Quels sont les plus gros ?
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : aucune écriture, aucune suppression.
-- =========================================================

-- ---------------------------------------------------------
-- 1. Les seaux
-- ---------------------------------------------------------
-- « public » veut dire : servi à qui connaît l'adresse, sans compte.
-- C'est ce qu'il faut pour un catalogue — mais cela rend la liste des
-- types acceptés importante : ce qu'on y dépose est servi depuis
-- l'adresse du projet.
select b.id                                            as "seau",
       case when b.public then 'oui' else 'non' end     as "lecture publique",
       coalesce(pg_size_pretty(b.file_size_limit), 'aucune limite')
                                                        as "poids maximum",
       coalesce(array_to_string(b.allowed_mime_types, ', '), 'TOUS LES TYPES')
                                                        as "types acceptés"
  from storage.buckets b
 order by b.id;

-- ---------------------------------------------------------
-- 2. Qui peut faire quoi
-- ---------------------------------------------------------
-- Les règles du stockage sont des politiques ordinaires, posées sur
-- « storage.objects ». S'il n'y en a aucune pour l'écriture, personne
-- ne dépose — ou tout le monde, selon que RLS est actif.
select p.polname                                        as "règle",
       case p.polcmd when 'r' then 'lecture'
                     when 'a' then 'dépôt'
                     when 'w' then 'modification'
                     when 'd' then 'suppression'
                     else 'tout' end                    as "porte",
       coalesce(
         (select string_agg(r.rolname, ', ')
            from pg_roles r where r.oid = any(p.polroles)),
         'tous les rôles')                              as "pour qui"
  from pg_policy p
  join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'storage' and c.relname = 'objects'
 order by p.polcmd, p.polname;

-- ---------------------------------------------------------
-- 3. Ce qui est déjà stocké, dossier par dossier
-- ---------------------------------------------------------
-- Le premier segment du chemin dit à qui appartient le fichier :
--   « enseigne/ »  le slider et la publicité de BIZZOO
--   « slider/ »    le slider d'une boutique
--   « boutique(s)/ » devantures et logos
--   le reste       les photos de produits
--
-- Le poids est rangé par Supabase dans « metadata ». Un fichier déposé
-- autrement que par l'API peut ne rien y avoir : il compte alors pour 0.
select coalesce(nullif(split_part(o.name, '/', 1), o.name), '(produits)')
                                                        as "dossier",
       o.bucket_id                                      as "seau",
       count(*)                                         as "fichiers",
       pg_size_pretty(sum(coalesce((o.metadata->>'size')::bigint, 0)))
                                                        as "poids total",
       pg_size_pretty(
         (avg(coalesce((o.metadata->>'size')::bigint, 0)))::bigint)
                                                        as "poids moyen"
  from storage.objects o
 group by 1, 2
 order by sum(coalesce((o.metadata->>'size')::bigint, 0)) desc;

-- Le total, toutes catégories confondues.
select count(*)                                         as "fichiers en tout",
       pg_size_pretty(sum(coalesce((metadata->>'size')::bigint, 0)))
                                                        as "poids en tout"
  from storage.objects;

-- ---------------------------------------------------------
-- 4. Les vingt plus gros fichiers
-- ---------------------------------------------------------
-- C'est ici qu'on voit si une photo est partie sans être compressée :
-- l'application réduit les images à 1100 px avant de les envoyer, donc
-- au-delà de 1 Mo, une image n'est pas passée par elle.
select o.name                                           as "fichier",
       o.bucket_id                                      as "seau",
       coalesce(o.metadata->>'mimetype', '?')           as "type",
       pg_size_pretty(coalesce((o.metadata->>'size')::bigint, 0))
                                                        as "poids",
       o.created_at::date                               as "déposé le"
  from storage.objects o
 order by coalesce((o.metadata->>'size')::bigint, 0) desc
 limit 20;

-- ---------------------------------------------------------
-- 5. Les fichiers que plus personne n'utilise
-- ---------------------------------------------------------
-- Une photo retirée d'un produit reste dans le seau : la base ne la
-- suit plus, le stockage la garde. Voici celles que rien ne désigne
-- plus — elles se suppriment sans conséquence.
--
-- Le seau est nommé en dur (« produits ») comme dans l'application :
-- si vous en ajoutez d'autres, cette requête sera à revoir.
with utilises as (
  select unnest(p.images) as chemin from public.produits p
  union select p.video from public.produits  p where coalesce(p.video, '') <> ''
  union select b.logo  from public.boutiques b where coalesce(b.logo,  '') <> ''
  union select b.video from public.boutiques b where coalesce(b.video, '') <> ''
  union select unnest(b.photos) from public.boutiques b
  union select s.image from public.slides    s where coalesce(s.image, '') <> ''
  union select s.video from public.slides    s where coalesce(s.video, '') <> ''
)
select o.name                                           as "fichier orphelin",
       pg_size_pretty(coalesce((o.metadata->>'size')::bigint, 0))
                                                        as "poids",
       o.created_at::date                               as "déposé le"
  from storage.objects o
 where o.bucket_id = 'produits'
   and o.name not in (select chemin from utilises where chemin is not null)
 order by coalesce((o.metadata->>'size')::bigint, 0) desc
 limit 50;
