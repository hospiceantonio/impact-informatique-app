-- =========================================================
-- BIZZOO Personnel : un employé ne voit pas les informations des autres
--
-- Seuls l'administration, le CEO et le superadministrateur lisent les
-- informations des employés. Deux fuites refermées :
--   - l'annuaire (qui sert à choisir à qui écrire) donnait à tout
--     employé le matricule, le sexe et le numéro PERSONNEL de chacun :
--     il ne donne plus que le nom, le poste, le profil, l'e-mail et le
--     téléphone professionnels ;
--   - le gestionnaire de la caisse lisait les fiches de paie validées
--     de tout le monde : la paie se verse désormais sur le solde, il
--     n'en a plus besoin ; chacun ne lit que la sienne.
-- =========================================================

-- ---------- Ce qui change (copies de schema.sql) ----------

create or replace function public.rh_moi() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_est_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and (administration or ceo));
$$;

create or replace function public.rh_annuaire()
returns table (id uuid, matricule text, nom text, prenoms text, sexe text, poste text,
               profil_id uuid, profil text, email_pro text, telephone text,
               administration boolean, ceo boolean, responsable boolean, a_un_compte boolean)
language sql stable security definer set search_path = public as $$
  /* Un employé ordinaire n'y lit que ce qui sert à joindre un collègue :
     nom, poste, profil, e-mail et téléphone PROFESSIONNELS. Le matricule,
     le sexe et le numéro personnel (celui qui sert à se connecter) ne
     sortent que pour l'administration, le CEO et le superadministrateur. */
  select e.id,
         case when public.rh_est_admin() or public.est_super() then e.matricule end,
         e.nom, e.prenoms,
         case when public.rh_est_admin() or public.est_super() then e.sexe end,
         e.poste, e.profil_id, coalesce(p.nom, ''),
         e.email_pro,
         case when public.rh_est_admin() or public.est_super() then e.telephone else nullif(e.telephone_pro, '') end,
         e.administration, e.ceo,
         exists (select 1 from public.rh_profils r where r.responsable_id = e.id),
         e.compte_id is not null
    from public.rh_employes e
    left join public.rh_profils p on p.id = e.profil_id
   where e.etat = 'actif' and public.rh_moi() is not null
   order by e.nom, e.prenoms;
$$;

-- ---------- Les fiches de paie ----------
drop policy if exists "rh fiches lecture" on public.rh_fiches_paie;
create policy "rh fiches lecture" on public.rh_fiches_paie
  for select to authenticated using (
    public.rh_est_admin()
    or (statut <> 'calculee' and employe_id = public.rh_moi()));
