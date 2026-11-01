-- =========================================================
-- BIZZOO 3.73.0 — Reversements dans BIZZOO Personnel : le CEO et la comptabilité
--
--   Le menu « Reversements » de BIZZOO Personnel est réservé au CEO et
--   aux membres du profil « Comptabilité » (posé ici, vide : le CEO y
--   placera le comptable). Eux seuls, avec le superadministrateur dans
--   BIZZOO Admin, voient les demandes et les tranchent.
--   Seul le CEO marque un profil « comptabilité » et y fait entrer ou
--   sortir un employé.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

alter table public.rh_profils add column if not exists comptabilite boolean not null default false;

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false)
     and public.role_courant() is not null;
$$;
revoke all on function public.est_compte_enseigne()  from public, anon;
grant execute on function public.est_compte_enseigne() to authenticated;

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;
grant execute on function public.boutique_du_compte() to authenticated;

create or replace function public.droit_enseigne(lequel text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_compte_enseigne() and coalesce((
    select case lequel
             when 'commandes' then p.peut_commandes
             when 'boutiques' then p.peut_boutiques
             when 'finances'  then p.peut_finances
             when 'produits'  then p.peut_modifier_produits
             else false
           end
      from public.profils p
     where p.id = auth.uid() and p.actif), false);
$$;
revoke all on function public.droit_enseigne(text)   from public, anon;
grant execute on function public.droit_enseigne(text)  to authenticated;

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.est_livreur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'livreur', false);
$$;
revoke all on function public.est_livreur() from public, anon, authenticated;
grant execute on function public.est_livreur() to authenticated;

create or replace function public.est_vendeur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'vendeur', false);
$$;
revoke all on function public.est_vendeur() from public, anon;
grant execute on function public.est_vendeur() to authenticated;

create or replace function public.montant_lisible(n numeric, devise text default 'FCFA')
returns text
language sql immutable set search_path = public as $$
  select replace(to_char(coalesce(n, 0), 'FM999,999,999,990'), ',', ' ') || ' ' || coalesce(nullif(devise, ''), 'FCFA');
$$;
revoke all on function public.montant_lisible(numeric, text) from public, anon, authenticated;

create or replace function public.nom_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select coalesce(nullif(p.nom, ''), nullif(p.email, ''), 'l''équipe')
                     from public.profils p where p.id = auth.uid()), '');
$$;
revoke all on function public.nom_du_compte() from public, anon, authenticated;

create or replace function public.notifier(
  qui uuid[], quoi text, le_titre text, le_corps text,
  le_lien text, la_commande text, la_boutique text, qui_sonne boolean)
returns int
language plpgsql security definer set search_path = public as $$
declare combien int := 0;
begin
  if qui is null or array_length(qui, 1) is null then return 0; end if;
  insert into public.notifications
    (destinataire, type, titre, corps, lien, commande_id, boutique_id, sonne)
  select u, quoi, coalesce(le_titre, ''), coalesce(le_corps, ''),
         coalesce(le_lien, ''), la_commande, la_boutique, coalesce(qui_sonne, false)
    from unnest(qui) as u
   where u is not null
  on conflict do nothing;
  get diagnostics combien = row_count;
  return combien;
end $$;
revoke all on function public.notifier(uuid[], text, text, text, text, text, text, boolean)
  from public, anon, authenticated;

create or replace function public.rh_est_ceo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and ceo);
$$;

create or replace function public.rh_mon_nom() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select btrim(coalesce(e.prenoms, '') || ' ' || coalesce(e.nom, ''))
                     from public.rh_employes e where e.compte_id = auth.uid() and e.etat = 'actif'), '');
$$;
revoke all on function public.rh_mon_nom() from public, anon;
grant execute on function public.rh_mon_nom() to authenticated, service_role;

create or replace function public.tient_la_caisse(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.droit_enseigne('commandes')
      or public.droit_enseigne('finances')
      or (public.est_admin() and cible is not null
          and cible = public.boutique_du_compte());
$$;
revoke all on function public.tient_la_caisse(text) from public, anon, authenticated;
grant execute on function public.tient_la_caisse(text) to authenticated;

/** Le compte connecté traite-t-il les reversements dans Personnel ? */
create or replace function public.rh_reversements_acces() returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return public.rh_est_ceo() or exists (
    select 1 from public.rh_employes e join public.rh_profils p on p.id = e.profil_id
     where e.compte_id = auth.uid() and e.etat = 'actif' and p.comptabilite);
exception when undefined_table or undefined_column then
  -- Une base d'avant BIZZOO Personnel ou d'avant la comptabilité :
  -- personne n'y a l'accès, et les listes restent au superadministrateur.
  return false;
end $$;
revoke all on function public.rh_reversements_acces() from public, anon;
grant execute on function public.rh_reversements_acces() to authenticated;

/** Qui tranche, en clair : son nom de compte BIZZOO, ou d'employé. */
create or replace function public.decideur_reversement() returns text
language sql stable security definer set search_path = public as $$
  select case when public.est_super() then public.nom_du_compte()
              else coalesce(nullif(public.rh_mon_nom(), ''), public.nom_du_compte()) end;
$$;
revoke all on function public.decideur_reversement() from public, anon, authenticated;

/** Le nom du compte MoMo des livreurs d'une liste, à qui traite les reversements. */
create or replace function public.noms_momo(ids uuid[])
returns table (id uuid, momo_nom text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.est_super() or public.rh_reversements_acces()) then return; end if;
  return query select p.id, p.momo_nom from public.profils p where p.id = any(ids) and p.role = 'livreur';
end $$;
revoke all on function public.noms_momo(uuid[]) from public, anon;
grant execute on function public.noms_momo(uuid[]) to authenticated;

-- Seul le CEO marque un profil « comptabilité ». (Sans compte connecté :
-- une mise à jour de la base, qui passe.)
create or replace function public.rh_profil_comptabilite_verrou() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'INSERT' and new.comptabilite) or (tg_op = 'UPDATE' and new.comptabilite is distinct from old.comptabilite) then
    if auth.uid() is not null and not public.rh_est_ceo() then
      raise exception 'Seul le CEO décide quel profil traite les reversements (comptabilité).';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists rh_profils_comptabilite on public.rh_profils;
create trigger rh_profils_comptabilite
  before insert or update on public.rh_profils
  for each row execute function public.rh_profil_comptabilite_verrou();

-- Seul le CEO fait entrer un employé dans un profil « comptabilité », ou
-- l'en fait sortir.
create or replace function public.rh_employe_comptabilite_verrou() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'INSERT' or new.profil_id is distinct from old.profil_id)
     and auth.uid() is not null and not public.rh_est_ceo()
     and exists (select 1 from public.rh_profils p
                  where p.comptabilite
                    and (p.id = new.profil_id or (tg_op = 'UPDATE' and p.id = old.profil_id))) then
    raise exception 'Seul le CEO place un employé dans le profil Comptabilité, ou l''en retire.';
  end if;
  return new;
end $$;
drop trigger if exists rh_employes_comptabilite on public.rh_employes;
create trigger rh_employes_comptabilite
  before insert or update of profil_id on public.rh_employes
  for each row execute function public.rh_employe_comptabilite_verrou();

-- Le profil « Comptabilité », vide : le CEO y placera le comptable.
insert into public.rh_profils (nom, description, comptabilite)
select 'Comptabilité', 'Traite les demandes de reversement (BIZZOO Personnel → Reversements).', true
 where not exists (select 1 from public.rh_profils where lower(nom) = lower('Comptabilité'));
update public.rh_profils set comptabilite = true
 where lower(nom) = lower('Comptabilité') and not comptabilite;

-- Les listes et les décisions : le CEO et la comptabilité y entrent.
create or replace function public.reversements_liste(cible text default null)
returns table (id bigint, boutique_id text, nom_boutique text, montant bigint, tel text, reseau text,
               titulaire text, etat text, demande_par text, demande_le timestamptz, decide_par text,
               decide_le timestamptz, reference text, motif text, devise text)
language plpgsql stable security definer set search_path = public as $$
begin
  -- (3.73.0) Toutes les boutiques : le superadministrateur, et dans BIZZOO
  -- Personnel le CEO et la comptabilité (rh_reversements_acces).
  if not (public.est_super() or (cible is null and public.rh_reversements_acces())
          or (cible is not null and public.tient_la_caisse(cible))) then
    return;
  end if;
  return query
    select v.id, v.boutique_id, coalesce(b.nom, '')::text, v.montant, v.tel, v.reseau, v.titulaire, v.etat,
           v.demande_par, v.demande_le, v.decide_par, v.decide_le, v.reference, v.motif,
           coalesce(nullif(b.devise, ''), 'FCFA')::text
      from public.reversements v left join public.boutiques b on b.id = v.boutique_id
     where cible is null or v.boutique_id = cible
     order by (v.etat = 'en_attente') desc, v.demande_le desc
     limit 200;
end $$;
revoke all on function public.reversements_liste(text) from public, anon;
grant execute on function public.reversements_liste(text) to authenticated;
create or replace function public.decider_reversement(cible bigint, accord boolean,
  reference text default '', motif text default '')
returns text
language plpgsql security definer set search_path = public as $$
declare
  v   public.reversements%rowtype;
  ref text := left(trim(coalesce(reference, '')), 60);
  pourquoi text := left(trim(coalesce(motif, '')), 300);
  dev text;
begin
  -- (3.73.0) Le superadministrateur, et dans BIZZOO Personnel le CEO et la
  -- comptabilité (rh_reversements_acces).
  if not (public.est_super() or public.rh_reversements_acces()) then
    raise exception 'Seuls le superadministrateur, le CEO et la comptabilité valident un reversement.';
  end if;
  select * into v from public.reversements where id = cible for update;
  if not found then raise exception 'Demande introuvable.'; end if;
  if v.etat <> 'en_attente' then
    raise exception 'Cette demande est déjà tranchée.' using errcode = 'P0001';
  end if;
  if accord and length(ref) < 4 then
    raise exception 'Notez la référence de la transaction envoyée.' using errcode = 'P0001';
  end if;
  update public.reversements
     set etat = case when accord then 'valide' else 'refuse' end,
         decide_par = public.decideur_reversement(), decide_le = now(),
         reference = case when accord then ref else '' end, motif = pourquoi
   where id = cible;
  dev := coalesce((select nullif(b.devise, '') from public.boutiques b where b.id = v.boutique_id), 'FCFA');
  perform public.notifier(
    array(select p.id from public.profils p
           where p.actif and p.boutique_id = v.boutique_id and p.role = 'administrateur'),
    'reversement_decide',
    case when accord then 'Reversement envoyé : ' || public.montant_lisible(v.montant, dev)
         else 'Reversement refusé : ' || public.montant_lisible(v.montant, dev) end,
    case when accord then 'Envoyé sur ' || v.reseau || ' ' || v.tel || ' — référence ' || ref || '.'
         else 'BIZZOO a refusé la demande' || coalesce(' : « ' || nullif(pourquoi, '') || ' »', '') ||
              '. Le montant revient à votre solde.' end,
    '#/solde', null, v.boutique_id, true);
  return case when accord then 'valide' else 'refuse' end;
end $$;
revoke all on function public.decider_reversement(bigint, boolean, text, text) from public, anon;
grant execute on function public.decider_reversement(bigint, boolean, text, text) to authenticated;

create or replace function public.reversements_livreurs_liste()
returns table (id bigint, livreur_id uuid, nom_livreur text, montant bigint, tel text, reseau text,
               titulaire text, etat text, demande_le timestamptz, decide_par text,
               decide_le timestamptz, reference text, motif text)
language plpgsql stable security definer set search_path = public as $$
declare moi uuid := auth.uid();
begin
  -- (3.73.0) Le CEO et la comptabilité aussi (BIZZOO Personnel).
  if moi is null or not (public.est_super() or public.rh_reversements_acces() or public.est_livreur()) then return; end if;
  return query
    select v.id, v.livreur_id, v.nom_livreur, v.montant, v.tel, v.reseau, v.titulaire, v.etat,
           v.demande_le, v.decide_par, v.decide_le, v.reference, v.motif
      from public.reversements_livreurs v
     where public.est_super() or public.rh_reversements_acces() or v.livreur_id = moi
     order by (v.etat = 'en_attente') desc, v.demande_le desc
     limit 200;
end $$;
revoke all on function public.reversements_livreurs_liste() from public, anon;
grant execute on function public.reversements_livreurs_liste() to authenticated;
create or replace function public.decider_reversement_livreur(cible bigint, accord boolean,
  reference text default '', motif text default '')
returns text
language plpgsql security definer set search_path = public as $$
declare
  v   public.reversements_livreurs%rowtype;
  ref text := left(trim(coalesce(reference, '')), 60);
  pourquoi text := left(trim(coalesce(motif, '')), 300);
begin
  -- (3.73.0) Le superadministrateur, et dans BIZZOO Personnel le CEO et la
  -- comptabilité (rh_reversements_acces).
  if not (public.est_super() or public.rh_reversements_acces()) then
    raise exception 'Seuls le superadministrateur, le CEO et la comptabilité valident un reversement.';
  end if;
  select * into v from public.reversements_livreurs where id = cible for update;
  if not found then raise exception 'Demande introuvable.'; end if;
  if v.etat <> 'en_attente' then
    raise exception 'Cette demande est déjà tranchée.' using errcode = 'P0001';
  end if;
  if accord and length(ref) < 4 then
    raise exception 'Notez la référence de la transaction envoyée.' using errcode = 'P0001';
  end if;
  update public.reversements_livreurs
     set etat = case when accord then 'valide' else 'refuse' end,
         decide_par = public.decideur_reversement(), decide_le = now(),
         reference = case when accord then ref else '' end, motif = pourquoi
   where id = cible;
  perform public.notifier(array[v.livreur_id], 'reversement_decide',
    case when accord then 'Gains envoyés : ' || public.montant_lisible(v.montant, 'FCFA')
         else 'Reversement refusé : ' || public.montant_lisible(v.montant, 'FCFA') end,
    case when accord then 'Envoyé sur ' || v.reseau || ' ' || v.tel || ' — référence ' || ref || '.'
         else 'BIZZOO a refusé la demande' || coalesce(' : « ' || nullif(pourquoi, '') || ' »', '') ||
              '. Le montant revient à votre solde.' end,
    '#/gains', null, null, true);
  return case when accord then 'valide' else 'refuse' end;
end $$;
revoke all on function public.decider_reversement_livreur(bigint, boolean, text, text) from public, anon;
grant execute on function public.decider_reversement_livreur(bigint, boolean, text, text) to authenticated;

create or replace function public.reversements_vendeurs_liste()
returns table (id bigint, vendeur_id uuid, nom_vendeur text, montant bigint, tel text, reseau text,
               titulaire text, etat text, demande_le timestamptz, decide_par text,
               decide_le timestamptz, reference text, motif text)
language plpgsql stable security definer set search_path = public as $$
declare moi uuid := auth.uid();
begin
  -- (3.73.0) Le CEO et la comptabilité aussi (BIZZOO Personnel).
  if moi is null or not (public.est_super() or public.rh_reversements_acces() or public.est_vendeur()) then return; end if;
  return query
    select v.id, v.vendeur_id, v.nom_vendeur, v.montant, v.tel, v.reseau, v.titulaire, v.etat,
           v.demande_le, v.decide_par, v.decide_le, v.reference, v.motif
      from public.reversements_vendeurs v
     where public.est_super() or public.rh_reversements_acces() or v.vendeur_id = moi
     order by (v.etat = 'en_attente') desc, v.demande_le desc
     limit 200;
end $$;
revoke all on function public.reversements_vendeurs_liste() from public, anon;
grant execute on function public.reversements_vendeurs_liste() to authenticated;
create or replace function public.decider_reversement_vendeur(cible bigint, accord boolean,
  reference text default '', motif text default '')
returns text
language plpgsql security definer set search_path = public as $$
declare
  v   public.reversements_vendeurs%rowtype;
  ref text := left(trim(coalesce(reference, '')), 60);
  pourquoi text := left(trim(coalesce(motif, '')), 300);
begin
  -- (3.73.0) Le superadministrateur, et dans BIZZOO Personnel le CEO et la
  -- comptabilité (rh_reversements_acces).
  if not (public.est_super() or public.rh_reversements_acces()) then
    raise exception 'Seuls le superadministrateur, le CEO et la comptabilité valident un versement.';
  end if;
  select * into v from public.reversements_vendeurs where id = cible for update;
  if not found then raise exception 'Demande introuvable.'; end if;
  if v.etat <> 'en_attente' then
    raise exception 'Cette demande est déjà tranchée.' using errcode = 'P0001';
  end if;
  if accord and length(ref) < 4 then
    raise exception 'Notez la référence de la transaction envoyée.' using errcode = 'P0001';
  end if;
  update public.reversements_vendeurs
     set etat = case when accord then 'valide' else 'refuse' end,
         decide_par = public.decideur_reversement(), decide_le = now(),
         reference = case when accord then ref else '' end, motif = pourquoi
   where id = cible;
  perform public.notifier(array[v.vendeur_id], 'reversement_decide',
    case when accord then 'Gains envoyés : ' || public.montant_lisible(v.montant, 'FCFA')
         else 'Versement refusé : ' || public.montant_lisible(v.montant, 'FCFA') end,
    case when accord then 'Envoyé sur ' || v.reseau || ' ' || v.tel || ' — référence ' || ref || '.'
         else 'BIZZOO a refusé la demande' || coalesce(' : « ' || nullif(pourquoi, '') || ' »', '') ||
              '. Le montant revient à votre solde.' end,
    '#/ventes', null, null, true);
  return case when accord then 'valide' else 'refuse' end;
end $$;
revoke all on function public.decider_reversement_vendeur(bigint, boolean, text, text) from public, anon;
grant execute on function public.decider_reversement_vendeur(bigint, boolean, text, text) to authenticated;
