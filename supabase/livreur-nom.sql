-- =========================================================
-- BIZZOO — choisir un livreur par son NOM
--
-- POURQUOI CE FICHIER EXISTE, ET C'EST UNE ERREUR DE MA PART.
-- La fonction « livreurs_boutique() » a été enrichie dans
-- « schema.sql » et « role-livreur.sql » — deux fichiers qu'une
-- base déjà en service n'a aucune raison de rejouer. Résultat :
-- les colonnes « nom » et « tel » sont bien arrivées sur les
-- comptes, mais la liste de « Confier à un livreur » continuait
-- de rendre des adresses e-mail. La fonctionnalité était posée
-- partout SAUF là où elle se voit.
--
-- CE QUE CE FICHIER FAIT : rien d'autre que remplacer cette
-- fonction. Aucune table, aucune règle, aucune donnée touchée.
-- On peut le coller deux fois de suite sans conséquence.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
-- =========================================================

-- ---------- Recopié de schema.sql ----------
-- Ce fichier doit pouvoir se coller seul : la fonction ci-dessous lit
-- ces colonnes et appelle ces fonctions-là.
alter table public.profils add column if not exists nom text not null default '';
alter table public.profils add column if not exists tel text not null default '';

create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;
grant execute on function public.est_equipe() to authenticated;

create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils where id = auth.uid() and actif;
$$;
grant execute on function public.boutique_du_compte() to authenticated;

create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false);
$$;
revoke all on function public.est_compte_enseigne() from public, anon;
grant execute on function public.est_compte_enseigne() to authenticated;

-- ---------- La liste des livreurs ----------
-- ON CHOISIT UN LIVREUR PAR SON NOM, pas par son adresse e-mail.
-- « porteur@impact.bj » ne dit pas qui c'est ; « Rohim » si. Et son
-- NUMÉRO part avec : quand le client n'est pas chez lui, c'est le
-- livreur qu'on rappelle, et on ne va pas le chercher ailleurs.
--
-- « drop » AVANT « create or replace » : changer les colonnes rendues
-- par une fonction n'est pas un remplacement aux yeux de PostgreSQL,
-- qui refuse net. Sans cette ligne, le fichier s'arrêterait sur une
-- base déjà en service — et seulement sur celle-là.
drop function if exists public.livreurs_boutique();
create or replace function public.livreurs_boutique()
returns table (id uuid, email text, nom text, tel text,
               actif boolean, bizzoo boolean)
language plpgsql stable security definer set search_path = public as $$
declare cible text := public.boutique_du_compte();
begin
  if not public.est_equipe() then return; end if;
  return query
    select p.id, coalesce(p.email, '')::text,
           coalesce(p.nom, '')::text, coalesce(p.tel, '')::text, p.actif,
           (p.boutique_id is null)
      from public.profils p
     where p.role = 'livreur'
       -- L'enseigne les voit tous, les comptes de BIZZOO aussi ;
       -- une boutique, les siens ET ceux de BIZZOO.
       and (public.est_super() or public.est_compte_enseigne()
            or (cible is not null
                and (p.boutique_id = cible or p.boutique_id is null)))
     -- Les siens d'abord, ceux de BIZZOO ensuite : on appelle son
     -- porteur avant de déranger celui de l'enseigne.
     -- Puis par nom quand il y en a un, par adresse sinon : une liste
     -- rangée par e-mail alors qu'on lit des noms paraît en désordre.
     order by (p.boutique_id is null), nullif(p.nom, '') nulls last, p.email;
end $$;
revoke all on function public.livreurs_boutique() from public, anon;
grant execute on function public.livreurs_boutique() to authenticated;

-- ---------- Un contrôle à la fin ----------
do $$
declare rendu text;
begin
  select pg_get_function_result(p.oid) into rendu
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'livreurs_boutique';
  if rendu is null then
    raise exception 'livreurs_boutique() est introuvable';
  end if;
  if rendu !~ 'nom text' or rendu !~ 'tel text' then
    raise exception 'livreurs_boutique() ne rend toujours pas le nom : %', rendu;
  end if;
  raise notice 'Les livreurs se choisissent maintenant par leur nom.';
end $$;
