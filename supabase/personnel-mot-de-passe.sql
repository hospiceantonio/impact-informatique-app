-- =========================================================
-- BIZZOO Personnel : l'administration redonne un mot de passe
--
-- Un employé a oublié son mot de passe : l'administration (CEO compris)
-- lui en donne un provisoire, depuis sa fiche. Changer le mot de passe
-- d'un autre compte demande la clé de service : la fonction Edge
-- « rh-mot-de-passe » le fait, la clé ne quitte jamais le serveur ; la
-- base, elle, décide qui en a le droit (rh_mdp_preparer, appelée avec la
-- session de l'administrateur).
--
-- Le mot de passe provisoire se traite comme le mot de passe de départ :
-- le compte est détaché de sa fiche jusqu'à ce que l'employé choisisse
-- le sien (rh_comptes_a_activer, rh_activer_compte) ; ses sessions
-- ouvertes sont fermées ; le geste va au journal de la fiche.
-- La fiche du CEO ne se traite que par le CEO ou le superadministrateur ;
-- personne ne traite la sienne ici (« Mon compte » est fait pour ça).
-- =========================================================

do $$
begin
  if exists (select 1 from pg_constraint where conname = 'rh_journal_employes_action_check'
               and pg_get_constraintdef(oid) not like '%mot_de_passe%') then
    alter table public.rh_journal_employes drop constraint rh_journal_employes_action_check;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_journal_employes_action_check') then
    alter table public.rh_journal_employes add constraint rh_journal_employes_action_check
      check (action in ('bloque', 'debloque', 'supprime', 'efface', 'mot_de_passe'));
  end if;
end $$;

-- ---------- Ce qui change (copies de schema.sql) ----------

create or replace function public.rh_est_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and (administration or ceo));
$$;

create or replace function public.rh_est_ceo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and ceo);
$$;

/** Le compte de connexion d'un employé, si l'appelant a le droit de lui
    donner un mot de passe provisoire. Appelée par la fonction Edge avec
    la session de l'administrateur. */
create or replace function public.rh_mdp_preparer(qui uuid) returns uuid
language plpgsql stable security definer set search_path = public as $$
declare
  e public.rh_employes;
  compte uuid;
begin
  if not (public.rh_est_admin() or public.est_super()) then
    raise exception 'Seule l''administration donne un mot de passe provisoire';
  end if;
  select * into e from public.rh_employes where id = qui and etat in ('actif', 'bloque');
  if not found then
    raise exception 'Seul un employé en poste reçoit un mot de passe';
  end if;
  if e.ceo and not (public.rh_est_ceo() or public.est_super()) then
    raise exception 'Le mot de passe du CEO ne se change que par lui ou le superadministrateur';
  end if;
  compte := coalesce(e.compte_id, (select a.compte_id from public.rh_comptes_a_activer a where a.employe_id = qui limit 1));
  if compte is null then
    raise exception 'Cet employé n''a pas encore de compte de connexion';
  end if;
  if compte = auth.uid() then
    raise exception 'Votre propre mot de passe se change dans « Mon compte »';
  end if;
  return compte;
end $$;

/** Le mot de passe provisoire est posé : le compte attend que l'employé
    choisisse le sien, ses sessions sont fermées, le geste est noté.
    Service seulement : la fonction Edge l'appelle après avoir changé le
    mot de passe. */
create or replace function public.rh_mdp_conclure(qui uuid, compte uuid, par uuid, motif text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare
  e public.rh_employes;
  auteur text;
begin
  select * into e from public.rh_employes where id = qui for update;
  if not found then
    raise exception 'Employé introuvable';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_employes set compte_id = null where id = qui and compte_id = compte;
  perform set_config('rh.decision', '', true);
  insert into public.rh_comptes_a_activer (compte_id, employe_id, empreinte)
  select compte, qui, u.encrypted_password from auth.users u where u.id = compte
  on conflict (compte_id) do update set employe_id = excluded.employe_id, empreinte = excluded.empreinte, cree_le = now();
  -- Qui était connecté avec l'ancien mot de passe ne l'est plus.
  if to_regclass('auth.sessions') is not null then
    execute format('delete from auth.sessions where user_id = %L', compte);
  end if;
  select coalesce(btrim(x.prenoms || ' ' || x.nom), '') into auteur from public.rh_employes x where x.compte_id = par;
  insert into public.rh_journal_employes (employe_id, matricule, nom, action, motif, par_compte, par_nom)
  values (e.id, coalesce(e.matricule, ''), btrim(e.prenoms || ' ' || e.nom), 'mot_de_passe',
          btrim(coalesce(motif, '')), par, coalesce(nullif(auteur, ''), 'Superadministrateur'));
end $$;

revoke all on function public.rh_mdp_preparer(uuid) from public, anon;
grant execute on function public.rh_mdp_preparer(uuid) to authenticated, service_role;
revoke all on function public.rh_mdp_conclure(uuid, uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.rh_mdp_conclure(uuid, uuid, uuid, text) to service_role;
