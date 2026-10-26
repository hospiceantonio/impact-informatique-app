-- =========================================================
-- BIZZOO Personnel : la première connexion avec un mot de passe de départ
--
-- Les employés importés n'ont que leur numéro. BIZZOO leur ouvre un
-- compte « numéro + mot de passe de départ », le même pour tous et donné
-- de vive voix ; il n'est écrit nulle part dans ce dépôt public : le
-- fichier qui crée les comptes reste hors du dépôt.
--
-- Un mot de passe que tout le monde connaît ne doit rien ouvrir : le
-- compte n'est PAS relié à la fiche de l'employé tant que celui-ci n'a
-- pas choisi le sien. Sans fiche reliée, rh_moi() est vide et la base
-- ne lui accorde rien. rh_activer_compte() relie le compte, mais
-- seulement si le mot de passe enregistré n'est plus celui de départ
-- (on compare l'empreinte gardée à la création) ; ensuite, le mot de
-- passe de départ ne vaut plus rien pour ce compte.
-- =========================================================

create table if not exists public.rh_comptes_a_activer (
  compte_id   uuid primary key references auth.users(id) on delete cascade,
  employe_id  uuid not null references public.rh_employes(id) on delete cascade,
  -- L'empreinte du mot de passe de départ, telle que l'a rangée Supabase.
  empreinte   text not null,
  cree_le     timestamptz not null default now()
);
alter table public.rh_comptes_a_activer enable row level security;
-- Aucune règle : seules les deux fonctions ci-dessous y touchent.
revoke all on table public.rh_comptes_a_activer from public, anon, authenticated;
grant all on table public.rh_comptes_a_activer to service_role;

-- ---------- Ce qui change (copies de schema.sql) ----------

create or replace function public.rh_rattacher_par_telephone() returns uuid
language plpgsql security definer set search_path = public as $$
declare
  numero text;
  e public.rh_employes;
begin
  /* Un compte ouvert par BIZZOO avec le mot de passe de départ n'est
     relié à sa fiche qu'une fois ce mot de passe changé (rh_activer_compte). */
  if to_regclass('public.rh_comptes_a_activer') is not null
     and exists (select 1 from public.rh_comptes_a_activer a where a.compte_id = auth.uid()) then
    raise exception 'Choisissez d''abord votre mot de passe' using errcode = 'P0001', hint = 'ACTIVATION';
  end if;
  select right(regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g'), 10) into numero
    from auth.users u where u.id = auth.uid();
  if coalesce(numero, '') = '' then
    raise exception 'Ce compte n''a pas de numéro de téléphone';
  end if;
  select * into e from public.rh_employes where etat = 'actif' and telephone = numero for update;
  if not found then
    raise exception 'Ce numéro n''est celui d''aucun employé en poste de BIZZOO';
  end if;
  if e.compte_id = auth.uid() then
    return e.id;
  end if;
  if e.compte_id is not null then
    raise exception 'Votre fiche est déjà reliée à un autre compte : connectez-vous avec votre adresse e-mail';
  end if;
  if exists (select 1 from public.rh_employes where compte_id = auth.uid()) then
    raise exception 'Ce compte est déjà relié à une autre fiche d''employé';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_employes set compte_id = auth.uid() where id = e.id;
  perform set_config('rh.decision', '', true);
  -- Un compte né de cette connexion n'est pas un compte de boutique.
  delete from public.profils p where p.id = auth.uid() and not p.actif and p.role = 'moderateur';
  return e.id;
end $$;

/** Ce compte doit-il encore choisir son mot de passe ? */
create or replace function public.rh_activation() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'a_activer', a.compte_id is not null,
    'prenoms', e.prenoms)
    from (select auth.uid() as id) moi
    left join public.rh_comptes_a_activer a on a.compte_id = moi.id
    left join public.rh_employes e on e.id = a.employe_id;
$$;

/** Le mot de passe est choisi : le compte rejoint enfin sa fiche. */
create or replace function public.rh_activer_compte() returns uuid
language plpgsql security definer set search_path = public as $$
declare
  a public.rh_comptes_a_activer;
  actuelle text;
  e public.rh_employes;
begin
  select * into a from public.rh_comptes_a_activer where compte_id = auth.uid() for update;
  if not found then
    raise exception 'Ce compte n''a rien à activer';
  end if;
  select encrypted_password into actuelle from auth.users where id = auth.uid();
  if actuelle is not distinct from a.empreinte then
    raise exception 'Choisissez un mot de passe à vous : celui donné par BIZZOO ne vaut que pour la première connexion';
  end if;
  select * into e from public.rh_employes where id = a.employe_id and etat = 'actif' for update;
  if not found then
    raise exception 'Votre fiche n''est pas (ou plus) celle d''un employé en poste : adressez-vous à l''administration';
  end if;
  if e.compte_id is not null and e.compte_id <> auth.uid() then
    raise exception 'Votre fiche est déjà reliée à un autre compte : adressez-vous à l''administration';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_employes set compte_id = auth.uid() where id = e.id;
  perform set_config('rh.decision', '', true);
  delete from public.rh_comptes_a_activer where compte_id = auth.uid();
  -- Un compte né de cette connexion n'est pas un compte de boutique.
  delete from public.profils p where p.id = auth.uid() and not p.actif and p.role = 'moderateur';
  return e.id;
end $$;

revoke all on function public.rh_activation() from public, anon;
grant execute on function public.rh_activation() to authenticated, service_role;
revoke all on function public.rh_activer_compte() from public, anon;
grant execute on function public.rh_activer_compte() to authenticated, service_role;
