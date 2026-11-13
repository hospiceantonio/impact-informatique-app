-- =========================================================
-- BIZZOO 3.81.0 — Tous les superadministrateurs sont égaux
--
--   Un superadministrateur nommé par un autre a désormais tous les droits
--   d'un superadministrateur, y compris sur celui qui l'a nommé. BIZZOO
--   garde toujours au moins un superadministrateur actif.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- Les colonnes que les fonctions plus bas lisent.
alter table public.profils add column if not exists cree_par uuid;

-- Entre superadministrateurs, plus de créateur protégé.
create or replace function public.est_mon_createur(cible uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  -- (3.81.0) ENTRE SUPERADMINISTRATEURS, PLUS DE CRÉATEUR PROTÉGÉ : un
  -- superadministrateur nommé par un autre a tous les droits d'un
  -- superadministrateur, sur tous les comptes. Ce qui protège encore
  -- BIZZOO : il reste toujours au moins un superadministrateur actif
  -- (« profil_dernier_super »).
  if public.est_super() then
    return false;
  end if;
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

-- =========================================================
-- (3.81.0) TOUS LES SUPERADMINISTRATEURS SONT ÉGAUX
--
-- Un superadministrateur nommé par un autre ne pouvait pas modifier,
-- désactiver, supprimer ni changer le mot de passe de celui qui l'avait
-- nommé (ni des comptes au-dessus) : il n'avait pas tous les droits d'un
-- superadministrateur. Cette limite tombe entre superadministrateurs
-- (« est_mon_createur », plus haut). En échange, une seule règle, pour ne
-- jamais enfermer BIZZOO dehors : on ne retire pas le DERNIER
-- superadministrateur actif — ni rétrogradé, ni désactivé, ni supprimé.
-- =========================================================
create or replace function public.profil_dernier_super() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.role = 'superadministrateur' and old.actif
     and (tg_op = 'DELETE' or new.role is distinct from 'superadministrateur' or not new.actif)
     and not exists (select 1 from public.profils p
                      where p.id <> old.id and p.role = 'superadministrateur' and p.actif) then
    raise exception 'BIZZOO garde toujours au moins un superadministrateur actif : nommez-en un autre avant de retirer celui-ci.'
      using errcode = 'P0001';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
revoke all on function public.profil_dernier_super() from public, anon, authenticated;

drop trigger if exists profils_dernier_super on public.profils;
create trigger profils_dernier_super
  before update or delete on public.profils
  for each row execute function public.profil_dernier_super();
