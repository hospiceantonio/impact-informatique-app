-- =========================================================
-- BIZZOO 3.63.0 — L'administrateur de BIZZOO gère ses livreurs, jusqu'au bout
--
--   Depuis la 3.59.0, l'administrateur de BIZZOO crée et modifie tous les
--   livreurs. Mais « Redonner un mot de passe » et « Supprimer » lui
--   répondaient « Ce compte n'est pas sous votre responsabilité » : la
--   fonction qui garde ces deux gestes, « gere_le_compte », l'avait oublié.
--   Elle l'accepte désormais — pour un LIVREUR, et rien d'autre.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- Emprunté par la fonction plus bas (3.63.0), recopié tel quel.
create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;

-- Emprunté par la fonction plus bas (3.63.0), recopié tel quel.
create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false)
     and public.role_courant() is not null;
$$;

-- Emprunté par la fonction plus bas (3.63.0), recopié tel quel.
create or replace function public.est_admin_bizzoo() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'administrateur', false)
     and public.est_compte_enseigne();
$$;
revoke all on function public.est_admin_bizzoo() from public, anon;
grant execute on function public.est_admin_bizzoo() to authenticated;

-- Emprunté par la fonction plus bas (3.63.0), recopié tel quel.
create or replace function public.est_mon_createur(cible uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return cible is not null and auth.uid() is not null and cible <> auth.uid() and exists (
  with recursive chaine(id, cran, vus) as (
    select p.cree_par, 1, array[p.id]
      from public.profils p
     where p.id = auth.uid() and p.cree_par is not null
    union all
    select p.cree_par, c.cran + 1, c.vus || p.id
      from chaine c
      join public.profils p on p.id = c.id
     where p.cree_par is not null and c.cran < 20 and not (p.id = any(c.vus))
  )
  select 1 from chaine where chaine.id = cible);
end $$;
revoke all on function public.est_mon_createur(uuid) from public, anon;
grant execute on function public.est_mon_createur(uuid) to authenticated;

-- ---------- Le livreur, sous la responsabilité de BIZZOO (3.63.0) ----------
create or replace function public.gere_le_compte(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  -- (3.59.0) Jamais sur celui qui vous a créé, ni plus haut.
  select not public.est_mon_createur(cible) and (public.est_super()
      or (public.est_admin() and exists (
            select 1 from public.profils p
             where p.id = cible and p.role in ('moderateur', 'livreur')
               and p.boutique_id is not null
               and p.boutique_id = public.boutique_du_compte()))
      or (public.est_admin_bizzoo() and exists (
            select 1 from public.profils p
             where p.id = cible and p.role = 'livreur')));
$$;
grant execute on function public.gere_le_compte(uuid) to authenticated;
