-- =========================================================
-- BIZZOO Personnel : la fiche complète et la connexion par numéro
--
-- La fiche reçoit ce que le fichier du personnel de BIZZOO donne en plus :
-- contact pro, équipement, langue, situation, moto ; le sexe peut rester
-- vide jusqu'à ce que l'employé le dise. Ethnie et religion vont dans
-- une table à part, réservée au CEO et au superadministrateur.
--
-- Chaque employé se connecte avec son numéro (code par SMS) : le compte
-- rejoint la fiche qui porte ce numéro (rh_rattacher_par_telephone).
-- Le superadministrateur modifie une fiche comme le CEO ; l'employé
-- complète lui-même ce qui le regarde (adresse, e-mail, sexe, date de
-- naissance, langue, situation, moto) — pas son numéro.
-- =========================================================

create or replace function public.rh_moi() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_est_ceo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and ceo);
$$;

create or replace function public.rh_est_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and (administration or ceo));
$$;



-- ---------- La fiche s'enrichit ----------
alter table public.rh_employes alter column sexe drop not null;
alter table public.rh_employes add column if not exists telephone_pro text not null default '';
alter table public.rh_employes add column if not exists equipement text not null default '';
alter table public.rh_employes add column if not exists langue text not null default '';
alter table public.rh_employes add column if not exists marie text not null default '';
alter table public.rh_employes add column if not exists moto boolean;
-- Le téléphone sert à se connecter : un seul employé en poste par numéro.
create unique index if not exists rh_employes_telephone on public.rh_employes (telephone)
  where telephone <> '' and etat not in ('sorti', 'refuse', 'supprime');

-- ---------- Ce qui ne regarde que le CEO ----------
-- Données sensibles (Code du numérique) : à part, lisibles et
-- modifiables par le CEO et le superadministrateur seuls.
create table if not exists public.rh_employes_sensibles (
  employe_id  uuid primary key references public.rh_employes(id) on delete cascade,
  ethnie      text not null default '',
  religion    text not null default ''
);
alter table public.rh_employes_sensibles enable row level security;
drop policy if exists "rh sensibles ceo" on public.rh_employes_sensibles;
create policy "rh sensibles ceo" on public.rh_employes_sensibles
  for all to authenticated
  using (public.rh_est_ceo() or public.est_super())
  with check (public.rh_est_ceo() or public.est_super());
revoke all on table public.rh_employes_sensibles from public, anon, authenticated;
grant all on table public.rh_employes_sensibles to service_role;
grant select, insert, update, delete on public.rh_employes_sensibles to authenticated;

-- ---------- Se connecter par son numéro ----------
/** Ce numéro est-il celui d'un employé en poste ? Demandé AVANT
    d'envoyer le code par SMS : on n'envoie pas de SMS, et l'on ne crée
    pas de compte, pour un numéro qui n'est pas celui d'un employé. */
create or replace function public.rh_telephone_employe(tel text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where etat = 'actif' and telephone <> ''
                    and telephone = right(regexp_replace(coalesce(tel, ''), '[^0-9]', '', 'g'), 10));
$$;

/** Le compte connecté par son numéro rejoint la fiche de l'employé qui
    porte ce numéro. Une fiche déjà reliée à un AUTRE compte ne change
    pas de main : l'employé se connecte alors comme avant. */
create or replace function public.rh_rattacher_par_telephone() returns uuid
language plpgsql security definer set search_path = public as $$
declare
  numero text;
  e public.rh_employes;
begin
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

revoke all on function public.rh_telephone_employe(text) from public;
grant execute on function public.rh_telephone_employe(text) to anon, authenticated, service_role;
revoke all on function public.rh_rattacher_par_telephone() from public, anon;
grant execute on function public.rh_rattacher_par_telephone() to authenticated, service_role;

-- ---------- Ce qui change (copies de schema.sql) ----------
drop policy if exists "rh employes lecture" on public.rh_employes;
drop policy if exists "rh employes ajout" on public.rh_employes;
drop policy if exists "rh employes modification" on public.rh_employes;
create policy "rh employes lecture" on public.rh_employes
  for select to authenticated using (public.rh_est_admin() or public.est_super() or compte_id = auth.uid());

create policy "rh employes ajout" on public.rh_employes
  for insert to authenticated with check (public.rh_est_admin() or public.est_super());

create policy "rh employes modification" on public.rh_employes
  for update to authenticated
  using (public.rh_est_admin() or public.est_super() or (compte_id = auth.uid() and etat = 'actif'))
  with check (public.rh_est_admin() or public.est_super() or (compte_id = auth.uid() and etat = 'actif'));

create or replace function public.rh_employe_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  decision boolean := coalesce(current_setting('rh.decision', true), '') = 'oui';
  -- Le superadministrateur de BIZZOO modifie une fiche comme le CEO.
  ceo_connecte boolean := public.rh_est_ceo() or public.est_super();
  admin_connecte boolean := public.rh_est_admin() or public.est_super();
  libres text[];
begin
  if tg_op = 'INSERT' then
    if decision then
      return new;
    end if;
    if not admin_connecte then
      raise exception 'Seule l''administration crée un employé';
    end if;
    new.compte_id := null;
    new.ceo := false;
    new.cree_par := public.rh_moi();
    new.cree_le := now();
    new.motif_refus := '';
    new.date_sortie := null;
    /* Les droits ne se proposent pas : le CEO les donne lui-même. */
    if not ceo_connecte then
      new.administration := false;
      new.peut_decaisser := false;
    end if;
    /* Le CEO n'a pas à valider ce qu'il crée lui-même. */
    if ceo_connecte then
      new.etat := 'actif';
      new.valide_par := public.rh_moi();
      new.valide_le := now();
    else
      new.etat := 'en_attente';
      new.valide_par := null;
      new.valide_le := null;
    end if;
    return new;
  end if;

  -- Modification
  if decision then
    return new;
  end if;
  if old.ceo and not ceo_connecte then
    raise exception 'La fiche du CEO ne se modifie que par lui';
  end if;

  if not admin_connecte then
    /* L'employé lui-même : ses coordonnées, rien d'autre. */
    /* Il complète ce qui le regarde. Son téléphone, non : c'est par lui
       qu'il se connecte ; l'administration le change. */
    libres := array['adresse', 'email_perso', 'sexe', 'date_naissance', 'langue', 'marie', 'moto'];
    if (to_jsonb(new) - libres) is distinct from (to_jsonb(old) - libres) then
      raise exception 'Vous ne pouvez modifier que votre adresse, votre e-mail, votre sexe, votre date de naissance, votre langue, votre situation et votre moto : le reste passe par l''administration';
    end if;
    return new;
  end if;

  if new.compte_id is distinct from old.compte_id
     or new.ceo is distinct from old.ceo
     or new.etat is distinct from old.etat
     or new.motif_refus is distinct from old.motif_refus
     or new.date_sortie is distinct from old.date_sortie
     or new.cree_par is distinct from old.cree_par
     or new.cree_le is distinct from old.cree_le
     or new.valide_par is distinct from old.valide_par
     or new.valide_le is distinct from old.valide_le
     or new.matricule is distinct from old.matricule then
    raise exception 'Cette information ne change que par une décision (valider, refuser, sortie, compte)';
  end if;

  if not ceo_connecte then
    if new.administration is distinct from old.administration
       or new.peut_decaisser is distinct from old.peut_decaisser then
      raise exception 'Seul le CEO accorde les droits d''administration et de décaissement';
    end if;
    /* Le salaire d'un employé en poste engage la paie : au CEO. */
    if old.etat = 'actif' and new.salaire_base is distinct from old.salaire_base then
      raise exception 'Le salaire d''un employé en poste ne change que par le CEO';
    end if;
    /* Une fiche refusée qu'on corrige repart chez le CEO. */
    if old.etat = 'refuse' then
      new.etat := 'en_attente';
      new.motif_refus := '';
    end if;
  end if;
  return new;
end $$;


