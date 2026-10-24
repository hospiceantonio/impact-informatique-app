-- =========================================================
-- BIZZOO Personnel — la gestion interne des employés de BIZZOO
--
-- Une troisième application sur la même base : « personnel/ ».
-- Elle ne touche à AUCUNE table de la place de marché. Tout ce
-- qu'elle pose commence par « rh_ », pour qu'on ne confonde jamais
-- ses « profils » (Marketing, Logistique…) avec la table « profils »
-- des comptes d'équipe des boutiques.
--
-- Les rangs :
--   le CEO          — un seul ; il valide les employés, les rapports
--                     d'activité, les dépenses, les barèmes et la paie ;
--   l'administration — droits sur tous les profils : crée les
--                     employés (validés ensuite par le CEO), les
--                     missions, prépare la paie ;
--   le responsable  — d'un profil : accepte les missions, rend leurs
--                     rapports, publie les rapports d'activité,
--                     demande les dépenses ;
--   l'habilité      — décaisse ce que le CEO a approuvé, paie les
--                     fiches validées ;
--   chaque employé  — lit ses fiches de paie, ses mails, écrit aux
--                     membres de son profil.
--
-- Un employé ne vaut rien tant qu'il n'est pas « actif » : c'est
-- « rh_moi() » qui le dit, et toutes les règles en découlent.
--
-- Se colle tel quel dans l'éditeur SQL de Supabase, et se rejoue
-- sans rien casser.
-- =========================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- Les employés ----------
create sequence if not exists public.rh_matricule_seq;

create table if not exists public.rh_employes (
  id              uuid primary key default gen_random_uuid(),
  matricule       text not null unique
                  default 'BZ-' || lpad(nextval('public.rh_matricule_seq')::text, 4, '0'),
  -- Le compte de connexion. Rattaché après validation, par l'adresse
  -- professionnelle : jamais choisi dans une liste.
  compte_id       uuid unique references auth.users(id) on delete set null,
  nom             text not null check (length(btrim(nom)) > 0),
  prenoms         text not null default '',
  sexe            text not null check (sexe in ('M', 'F')),
  -- L'âge se calcule : une date de naissance ne vieillit pas de travers.
  date_naissance  date check (date_naissance > date '1930-01-01'),
  telephone       text not null default '',
  email_pro       text check (email_pro is null or email_pro ~* '^[^@\s]+@[^@\s]+\.[^@\s]+\Z'),
  email_perso     text not null default '',
  adresse         text not null default '',
  date_embauche   date not null,
  statut          text not null default 'employe' check (statut in ('stagiaire', 'employe')),
  niveau_etude    text not null default '',
  poste           text not null default '',
  salaire_base    bigint not null default 0 check (salaire_base >= 0),
  numero_cnss     text not null default '',
  mode_paiement   text not null default 'especes'
                  check (mode_paiement in ('especes', 'virement', 'mobile_money', 'cheque')),
  compte_paiement text not null default '',
  infos           text not null default '',
  profil_id       uuid,
  administration  boolean not null default false,
  ceo             boolean not null default false,
  peut_decaisser  boolean not null default false,
  etat            text not null default 'en_attente'
                  check (etat in ('en_attente', 'actif', 'refuse', 'sorti')),
  motif_refus     text not null default '',
  date_sortie     date,
  cree_par        uuid,
  cree_le         timestamptz not null default now(),
  valide_par      uuid,
  valide_le       timestamptz
);
-- Une adresse professionnelle ne sert qu'à un employé : c'est par elle
-- qu'on rattache le compte et qu'on ouvre la boîte mail.
create unique index if not exists rh_employes_email_pro
  on public.rh_employes (lower(email_pro)) where email_pro is not null;
-- UN SEUL CEO. C'est lui qui valide tout : deux, et chacun validerait
-- ce que l'autre a refusé.
create unique index if not exists rh_employes_un_ceo
  on public.rh_employes (ceo) where ceo;

-- ---------- Les profils (Marketing, Logistique…) ----------
create table if not exists public.rh_profils (
  id             uuid primary key default gen_random_uuid(),
  nom            text not null check (length(btrim(nom)) > 0),
  description    text not null default '',
  responsable_id uuid references public.rh_employes(id) on delete set null,
  cree_le        timestamptz not null default now()
);
create unique index if not exists rh_profils_nom on public.rh_profils (lower(nom));

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'rh_employes_profil_fk') then
    alter table public.rh_employes add constraint rh_employes_profil_fk
      foreign key (profil_id) references public.rh_profils(id) on delete restrict;
  end if;
end $$;

-- ---------- Qui est connecté ----------
-- « security definer » : ces fonctions lisent les tables sans repasser
-- par les règles RLS — sinon les règles s'appelleraient elles-mêmes.

/** L'employé du compte connecté, s'il est ACTIF. Tout en découle. */
create or replace function public.rh_moi() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_est_ceo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and ceo);
$$;

/** L'administration, CEO compris : droits sur tous les profils. */
create or replace function public.rh_est_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and (administration or ceo));
$$;

create or replace function public.rh_peut_decaisser() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and peut_decaisser);
$$;

create or replace function public.rh_mon_profil() returns uuid
language sql stable security definer set search_path = public as $$
  select profil_id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_responsable_de(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select cible is not null and exists (
    select 1 from public.rh_profils p
     where p.id = cible and p.responsable_id is not null
       and p.responsable_id = public.rh_moi());
$$;

/** Membre du profil : y être rangé, ou le diriger. */
create or replace function public.rh_membre_de(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select cible is not null
     and (public.rh_mon_profil() = cible or public.rh_responsable_de(cible));
$$;

/** Ce menu est-il ouvert à mon compte POUR CE PROFIL ? L'administration
    voit tout ; sinon il faut une ligne de rh_acces_menus (menu Paramètres) :
    « membres » vaut pour qui est rangé dans le profil, et le responsable
    passe dans les deux cas. Sans la table (fichier rejoué seul sur une
    base plus ancienne), les règles d'avant : être membre du profil. */
create or replace function public.rh_acces(cible uuid, cle text) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rh_est_admin() then
    return true;
  end if;
  if cible is null or public.rh_moi() is null then
    return false;
  end if;
  if to_regclass('public.rh_acces_menus') is null then
    return public.rh_membre_de(cible);
  end if;
  return exists (
    select 1 from public.rh_acces_menus a
     where a.profil_id = cible and a.menu = cle
       and (public.rh_responsable_de(cible)
            or (a.qui = 'membres' and public.rh_mon_profil() = cible)));
end $$;

/** Ce menu est-il ouvert à mon compte, par l'un de mes profils ? Un
    employé sans profil (ni profil à diriger) garde sa boîte mail et ses
    messages directs. */
create or replace function public.rh_menu_ouvert(cle text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_moi uuid := public.rh_moi();
  v_profil uuid := public.rh_mon_profil();
begin
  if public.rh_est_admin() then
    return true;
  end if;
  if v_moi is null then
    return false;
  end if;
  if to_regclass('public.rh_acces_menus') is null then
    return cle in ('mails', 'discussions', 'missions', 'rapports');
  end if;
  if v_profil is null and not exists (select 1 from public.rh_profils p where p.responsable_id = v_moi) then
    return cle in ('mails', 'discussions');
  end if;
  return exists (
    select 1 from public.rh_acces_menus a
      join public.rh_profils p on p.id = a.profil_id
     where a.menu = cle
       and (p.responsable_id = v_moi or (a.qui = 'membres' and p.id = v_profil)));
end $$;

-- ---------- Les verrous de la fiche employé ----------
-- Les règles RLS disent QUI écrit ; ce déclencheur dit QUOI. Les
-- décisions (valider, refuser, faire sortir, rattacher un compte) ne
-- passent que par leurs fonctions, qui posent le drapeau « rh.decision ».
create or replace function public.rh_employe_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  decision boolean := coalesce(current_setting('rh.decision', true), '') = 'oui';
  ceo_connecte boolean := public.rh_est_ceo();
  admin_connecte boolean := public.rh_est_admin();
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
    libres := array['telephone', 'adresse', 'email_perso'];
    if (to_jsonb(new) - libres) is distinct from (to_jsonb(old) - libres) then
      raise exception 'Vous ne pouvez modifier que votre téléphone, votre adresse et votre e-mail personnel';
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

drop trigger if exists rh_employes_verrous on public.rh_employes;
create trigger rh_employes_verrous
  before insert or update on public.rh_employes
  for each row execute function public.rh_employe_verrous();

-- Un employé qui quitte son profil (ou l'entreprise) n'en reste pas
-- le responsable : il dirigerait des gens dont il ne voit plus rien.
create or replace function public.rh_employe_apres() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.profil_id is distinct from old.profil_id or new.etat <> 'actif' then
    update public.rh_profils set responsable_id = null
     where responsable_id = new.id
       and (new.etat <> 'actif' or id is distinct from new.profil_id);
  end if;
  return null;
end $$;

drop trigger if exists rh_employes_apres on public.rh_employes;
create trigger rh_employes_apres
  after update on public.rh_employes
  for each row execute function public.rh_employe_apres();

-- Le responsable d'un profil en est membre, et il est en poste.
create or replace function public.rh_profil_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.responsable_id is not null and not exists (
       select 1 from public.rh_employes e
        where e.id = new.responsable_id and e.etat = 'actif' and e.profil_id = new.id) then
    raise exception 'Le responsable doit être un employé en poste, membre de ce profil';
  end if;
  return new;
end $$;

drop trigger if exists rh_profils_verrous on public.rh_profils;
create trigger rh_profils_verrous
  before insert or update on public.rh_profils
  for each row execute function public.rh_profil_verrous();

-- ---------- Un compte du personnel n'est pas un compte de boutique ----------
-- Tout compte créé reçoit d'ordinaire une fiche d'équipe en attente
-- (« profil_nouveau_compte »). Un employé créé depuis BIZZOO Personnel
-- s'inscrit avec « compte: personnel » : sans ce ménage, il apparaîtrait
-- dans la liste des comptes de l'enseigne, à un clic d'un rang de
-- modérateur. Ce déclencheur s'exécute APRÈS celui-là (ordre des noms).
create or replace function public.rh_compte_personnel() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.raw_user_meta_data ->> 'compte', '') = 'personnel' then
    delete from public.profils p
     where p.id = new.id and not p.actif and p.role = 'moderateur';
  end if;
  return new;
end $$;

drop trigger if exists rh_compte_personnel on auth.users;
create trigger rh_compte_personnel
  after insert on auth.users
  for each row execute function public.rh_compte_personnel();

-- ---------- Les décisions sur un employé ----------
create or replace function public.rh_decider_employe(employe uuid, accepter boolean, motif text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO valide un employé';
  end if;
  if not accepter and length(btrim(coalesce(motif, ''))) = 0 then
    raise exception 'Dites pourquoi vous refusez';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_employes
     set etat = case when accepter then 'actif' else 'refuse' end,
         motif_refus = case when accepter then '' else btrim(motif) end,
         valide_par = public.rh_moi(), valide_le = now()
   where id = employe and etat = 'en_attente';
  if not found then
    raise exception 'Cet employé n''attend pas de validation';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

create or replace function public.rh_sortie_employe(employe uuid, le date, motif text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO enregistre la sortie d''un employé';
  end if;
  if exists (select 1 from public.rh_employes where id = employe and ceo) then
    raise exception 'Le CEO ne se fait pas sortir lui-même';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_employes
     set etat = 'sorti', date_sortie = coalesce(le, current_date),
         motif_refus = btrim(coalesce(motif, ''))
   where id = employe and etat = 'actif';
  if not found then
    raise exception 'Cet employé n''est pas en poste';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

/**
 * Rattache le compte de connexion dont l'adresse est l'e-mail
 * professionnel de l'employé. L'application crée le compte (inscription,
 * « compte: personnel ») puis appelle ceci : on ne rattache jamais un
 * compte choisi dans une liste, toujours celui de SA propre adresse.
 */
create or replace function public.rh_rattacher_compte(employe uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  e public.rh_employes;
  compte uuid;
begin
  if not public.rh_est_admin() then
    raise exception 'Seule l''administration rattache un compte';
  end if;
  select * into e from public.rh_employes where id = employe;
  if not found or e.etat <> 'actif' then
    raise exception 'Seul un employé validé reçoit un accès';
  end if;
  if e.ceo and not public.rh_est_ceo() then
    raise exception 'La fiche du CEO ne se modifie que par lui';
  end if;
  if coalesce(e.email_pro, '') = '' then
    raise exception 'Renseignez d''abord l''e-mail professionnel de l''employé';
  end if;
  select u.id into compte from auth.users u where lower(u.email) = lower(e.email_pro);
  if compte is null then
    raise exception 'AUCUN_COMPTE : aucun compte n''existe encore pour %', e.email_pro;
  end if;
  if exists (select 1 from public.rh_employes x where x.compte_id = compte and x.id <> e.id) then
    raise exception 'Ce compte est déjà celui d''un autre employé';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_employes set compte_id = compte where id = e.id;
  perform set_config('rh.decision', '', true);
  return compte;
end $$;

/**
 * Le premier CEO. Personne ne peut valider le premier employé : on
 * l'amorce. Seul un superadministrateur de BIZZOO le peut, et une seule
 * fois — dès qu'un CEO existe, la porte est fermée.
 */
create or replace function public.rh_devenir_ceo(nom text, prenoms text, sexe text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  courriel text;
  nouveau uuid;
begin
  if not public.est_super() then
    raise exception 'Seul un superadministrateur de BIZZOO peut désigner le premier CEO';
  end if;
  if exists (select 1 from public.rh_employes where ceo) then
    raise exception 'BIZZOO a déjà son CEO dans l''application';
  end if;
  select email into courriel from auth.users where id = auth.uid();
  perform set_config('rh.decision', 'oui', true);
  update public.rh_employes
     set ceo = true, administration = true, etat = 'actif', valide_le = now()
   where compte_id = auth.uid()
  returning id into nouveau;
  if nouveau is null then
    insert into public.rh_employes (compte_id, nom, prenoms, sexe, email_pro, date_embauche,
                                    statut, ceo, administration, etat, cree_le, valide_le)
    values (auth.uid(), btrim(nom), btrim(coalesce(prenoms, '')), sexe, courriel, current_date,
            'employe', true, true, 'actif', now(), now())
    returning id into nouveau;
  end if;
  perform set_config('rh.decision', '', true);
  return nouveau;
end $$;

/**
 * Désigner le CEO sans l'être. Le superadministrateur qui installe
 * l'application n'est pas toujours le CEO : il inscrit le CEO par son
 * adresse professionnelle — le compte de connexion doit déjà exister,
 * l'application le crée juste avant —, et peut s'inscrire lui-même dans
 * l'administration pour préparer profils et employés en attendant.
 * Même porte que « rh_devenir_ceo » : un superadministrateur, une seule
 * fois, tant qu'aucun CEO n'existe.
 */
create or replace function public.rh_designer_ceo(nom text, prenoms text, sexe text, email_pro text,
                                                  moi_nom text default null, moi_prenoms text default '',
                                                  moi_sexe text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  courriel text := lower(btrim(coalesce(email_pro, '')));
  compte uuid;
  moi_courriel text;
  nouveau uuid;
begin
  if not public.est_super() then
    raise exception 'Seul un superadministrateur de BIZZOO peut désigner le CEO';
  end if;
  if exists (select 1 from public.rh_employes where ceo) then
    raise exception 'BIZZOO a déjà son CEO dans l''application';
  end if;
  if courriel = '' then
    raise exception 'Indiquez l''adresse professionnelle du CEO';
  end if;
  select u.id into compte from auth.users u where lower(u.email) = courriel;
  if compte is null then
    raise exception 'AUCUN_COMPTE : aucun compte n''existe encore pour %', courriel;
  end if;
  if compte = auth.uid() then
    raise exception 'C''est votre propre adresse : choisissez « Je suis le CEO »';
  end if;
  if exists (select 1 from public.rh_employes x
              where x.compte_id = compte or lower(x.email_pro) = courriel) then
    raise exception 'Cette adresse est déjà celle d''un employé';
  end if;
  perform set_config('rh.decision', 'oui', true);
  insert into public.rh_employes (compte_id, nom, prenoms, sexe, email_pro, date_embauche,
                                  statut, ceo, administration, etat, cree_par, cree_le, valide_le)
  values (compte, btrim(nom), btrim(coalesce(prenoms, '')), sexe, courriel, current_date,
          'employe', true, true, 'actif', null, now(), now())
  returning id into nouveau;
  if btrim(coalesce(moi_nom, '')) <> '' then
    if exists (select 1 from public.rh_employes where compte_id = auth.uid()) then
      raise exception 'Votre compte a déjà une fiche employé';
    end if;
    select u.email into moi_courriel from auth.users u where u.id = auth.uid();
    insert into public.rh_employes (compte_id, nom, prenoms, sexe, email_pro, date_embauche,
                                    statut, administration, etat, cree_le, valide_par, valide_le)
    values (auth.uid(), btrim(moi_nom), btrim(coalesce(moi_prenoms, '')), moi_sexe, lower(moi_courriel),
            current_date, 'employe', true, 'actif', now(), nouveau, now());
  end if;
  perform set_config('rh.decision', '', true);
  return nouveau;
end $$;

/** L'annuaire : qui est qui, sans le salaire. Pour tout employé en poste. */
create or replace function public.rh_annuaire()
returns table (id uuid, matricule text, nom text, prenoms text, sexe text, poste text,
               profil_id uuid, profil text, email_pro text, telephone text,
               administration boolean, ceo boolean, responsable boolean, a_un_compte boolean)
language sql stable security definer set search_path = public as $$
  select e.id, e.matricule, e.nom, e.prenoms, e.sexe, e.poste, e.profil_id, coalesce(p.nom, ''),
         e.email_pro, e.telephone, e.administration, e.ceo,
         exists (select 1 from public.rh_profils r where r.responsable_id = e.id),
         e.compte_id is not null
    from public.rh_employes e
    left join public.rh_profils p on p.id = e.profil_id
   where e.etat = 'actif' and public.rh_moi() is not null
   order by e.nom, e.prenoms;
$$;

-- ---------- La messagerie interne ----------
create table if not exists public.rh_messages (
  id             bigint generated always as identity primary key,
  -- La discussion d'un profil, OU un message à une personne.
  profil_id      uuid references public.rh_profils(id) on delete cascade,
  destinataire_id uuid references public.rh_employes(id) on delete cascade,
  auteur_id      uuid not null references public.rh_employes(id) on delete cascade,
  texte          text not null check (length(btrim(texte)) between 1 and 4000),
  cree_le        timestamptz not null default now(),
  constraint rh_messages_une_cible check ((profil_id is null) <> (destinataire_id is null))
);
create index if not exists rh_messages_profil on public.rh_messages (profil_id, id);
create index if not exists rh_messages_prive on public.rh_messages (destinataire_id, auteur_id, id);

/** Peut-on écrire à cette personne ? À son profil, à son responsable,
    à l'administration ; l'administration écrit à tous. */
create or replace function public.rh_peut_ecrire_a(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.rh_moi() is not null and cible <> public.rh_moi() and exists (
    select 1 from public.rh_employes c
     where c.id = cible and c.etat = 'actif'
       and (public.rh_est_admin()
            or c.administration or c.ceo
            or (c.profil_id is not null and c.profil_id = public.rh_mon_profil())
            or public.rh_responsable_de(c.profil_id)
            or exists (select 1 from public.rh_profils p
                        where p.id = public.rh_mon_profil() and p.responsable_id = c.id)));
$$;

create or replace function public.rh_message_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.auteur_id := public.rh_moi();
  new.cree_le := now();
  new.texte := btrim(new.texte);
  if new.auteur_id is null then
    raise exception 'Seul un employé en poste écrit';
  end if;
  return new;
end $$;

drop trigger if exists rh_messages_verrous on public.rh_messages;
create trigger rh_messages_verrous
  before insert on public.rh_messages
  for each row execute function public.rh_message_verrous();

create table if not exists public.rh_lectures (
  employe_id   uuid not null references public.rh_employes(id) on delete cascade,
  conversation text not null,
  lu_le        timestamptz not null default now(),
  primary key (employe_id, conversation)
);

/** « p:<profil> » ou « d:<personne> » : la discussion est lue jusqu'ici. */
create or replace function public.rh_marquer_lu(conversation text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.rh_moi() is null then
    raise exception 'Seul un employé en poste lit ses messages';
  end if;
  if conversation !~ '^[pd]:[0-9a-f-]{36}\Z' then
    raise exception 'Discussion inconnue';
  end if;
  insert into public.rh_lectures (employe_id, conversation, lu_le)
  values (public.rh_moi(), conversation, now())
  on conflict on constraint rh_lectures_pkey do update set lu_le = excluded.lu_le;
end $$;

/** Les discussions du compte connecté, la plus récente d'abord. */
create or replace function public.rh_conversations()
returns table (cle text, genre text, cible uuid, titre text, dernier_texte text,
               dernier_le timestamptz, non_lus int)
language sql stable security definer set search_path = public as $$
  with moi as (select public.rh_moi() as id, public.rh_est_admin() as admin),
  groupes as (
    select 'p:' || p.id as cle, 'profil'::text as genre, p.id as cible, p.nom as titre
      from public.rh_profils p, moi
     where moi.id is not null and (moi.admin or public.rh_acces(p.id, 'discussions'))
  ),
  personnes as (
    select distinct case when m.auteur_id = moi.id then m.destinataire_id else m.auteur_id end as autre
      from public.rh_messages m, moi
     where m.destinataire_id is not null and (m.auteur_id = moi.id or m.destinataire_id = moi.id)
       and public.rh_menu_ouvert('discussions')
  ),
  prives as (
    select 'd:' || e.id as cle, 'personne'::text as genre, e.id as cible,
           btrim(e.prenoms || ' ' || e.nom) as titre
      from personnes x join public.rh_employes e on e.id = x.autre
  ),
  toutes as (select * from groupes union all select * from prives)
  select t.cle, t.genre, t.cible, t.titre, d.texte, d.cree_le,
         (select count(*)::int from public.rh_messages m, moi
           where m.auteur_id <> moi.id
             and m.cree_le > coalesce((select l.lu_le from public.rh_lectures l
                                        where l.employe_id = moi.id and l.conversation = t.cle),
                                      '-infinity')
             and ((t.genre = 'profil' and m.profil_id = t.cible)
               or (t.genre = 'personne' and m.auteur_id = t.cible and m.destinataire_id = moi.id)))
    from toutes t
    left join lateral (
      select m.texte, m.cree_le from public.rh_messages m, moi
       where (t.genre = 'profil' and m.profil_id = t.cible)
          or (t.genre = 'personne' and ((m.auteur_id = t.cible and m.destinataire_id = moi.id)
                                     or (m.auteur_id = moi.id and m.destinataire_id = t.cible)))
       order by m.id desc limit 1) d on true
   order by d.cree_le desc nulls last, t.titre;
$$;

-- ---------- Les missions ----------
create table if not exists public.rh_missions (
  id            uuid primary key default gen_random_uuid(),
  numero        bigint generated always as identity,
  titre         text not null check (length(btrim(titre)) > 0),
  description   text not null default '',
  profil_id     uuid not null references public.rh_profils(id) on delete restrict,
  date_debut    date not null default current_date,
  -- Le délai du rapport, fixé à la création.
  echeance      date not null,
  statut        text not null default 'proposee'
                check (statut in ('proposee', 'acceptee', 'refusee', 'rapport_remis',
                                  'a_reprendre', 'cloturee')),
  cree_par      uuid,
  cree_le       timestamptz not null default now(),
  reponse_par   uuid,
  reponse_le    timestamptz,
  motif_refus   text not null default '',
  rapport       text not null default '',
  rapport_par   uuid,
  rapport_le    timestamptz,
  decision_par  uuid,
  decision_le   timestamptz,
  commentaire   text not null default '',
  constraint rh_missions_dates check (echeance >= date_debut)
);

create or replace function public.rh_mission_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  libres text[] := array['titre', 'description', 'date_debut', 'echeance'];
begin
  if coalesce(current_setting('rh.decision', true), '') = 'oui' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.statut := 'proposee';
    new.cree_par := public.rh_moi();
    new.cree_le := now();
    new.reponse_par := null; new.reponse_le := null; new.motif_refus := '';
    new.rapport := ''; new.rapport_par := null; new.rapport_le := null;
    new.decision_par := null; new.decision_le := null; new.commentaire := '';
    return new;
  end if;
  if old.statut in ('refusee', 'cloturee') then
    raise exception 'Une mission refusée ou clôturée ne se modifie plus';
  end if;
  if (to_jsonb(new) - libres) is distinct from (to_jsonb(old) - libres) then
    raise exception 'Seuls le titre, la description et les dates se modifient ; le reste suit le circuit de la mission';
  end if;
  return new;
end $$;

drop trigger if exists rh_missions_verrous on public.rh_missions;
create trigger rh_missions_verrous
  before insert or update on public.rh_missions
  for each row execute function public.rh_mission_verrous();

create or replace function public.rh_repondre_mission(mission uuid, accepter boolean, motif text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare m public.rh_missions;
begin
  select * into m from public.rh_missions where id = mission for update;
  if not found or not public.rh_responsable_de(m.profil_id) then
    raise exception 'Seul le responsable du profil répond à cette mission';
  end if;
  if not public.rh_acces(m.profil_id, 'missions') then
    raise exception 'Le menu Missions n''est pas ouvert à votre profil';
  end if;
  if m.statut <> 'proposee' then
    raise exception 'Cette mission a déjà reçu sa réponse';
  end if;
  if not accepter and length(btrim(coalesce(motif, ''))) = 0 then
    raise exception 'Dites pourquoi vous refusez la mission';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_missions
     set statut = case when accepter then 'acceptee' else 'refusee' end,
         reponse_par = public.rh_moi(), reponse_le = now(),
         motif_refus = case when accepter then '' else btrim(motif) end
   where id = mission;
  perform set_config('rh.decision', '', true);
end $$;

create or replace function public.rh_rendre_rapport_mission(mission uuid, texte text)
returns void
language plpgsql security definer set search_path = public as $$
declare m public.rh_missions;
begin
  select * into m from public.rh_missions where id = mission for update;
  if not found or not public.rh_responsable_de(m.profil_id) then
    raise exception 'Seul le responsable du profil rend le rapport de mission';
  end if;
  if not public.rh_acces(m.profil_id, 'missions') then
    raise exception 'Le menu Missions n''est pas ouvert à votre profil';
  end if;
  if m.statut not in ('acceptee', 'a_reprendre') then
    raise exception 'Le rapport se rend sur une mission acceptée';
  end if;
  if length(btrim(coalesce(texte, ''))) < 10 then
    raise exception 'Le rapport est trop court';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_missions
     set statut = 'rapport_remis', rapport = btrim(texte),
         rapport_par = public.rh_moi(), rapport_le = now()
   where id = mission;
  perform set_config('rh.decision', '', true);
end $$;

create or replace function public.rh_cloturer_mission(mission uuid, valider boolean, commentaire text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_admin() then
    raise exception 'Seule l''administration clôture une mission';
  end if;
  if not valider and length(btrim(coalesce(commentaire, ''))) = 0 then
    raise exception 'Dites ce qu''il faut reprendre';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_missions
     set statut = case when valider then 'cloturee' else 'a_reprendre' end,
         decision_par = public.rh_moi(), decision_le = now(),
         commentaire = btrim(coalesce(rh_cloturer_mission.commentaire, ''))
   where id = mission and statut = 'rapport_remis';
  if not found then
    raise exception 'Aucun rapport n''attend sur cette mission';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

-- ---------- Les rapports d'activité ----------
create table if not exists public.rh_rapports (
  id             uuid primary key default gen_random_uuid(),
  profil_id      uuid not null references public.rh_profils(id) on delete restrict,
  auteur_id      uuid references public.rh_employes(id) on delete set null,
  titre          text not null check (length(btrim(titre)) > 0),
  periode_debut  date not null,
  periode_fin    date not null,
  contenu        text not null default '',
  statut         text not null default 'brouillon'
                 check (statut in ('brouillon', 'publie', 'valide', 'rejete')),
  cree_le        timestamptz not null default now(),
  publie_le      timestamptz,
  decision_par   uuid,
  decision_le    timestamptz,
  commentaire    text not null default '',
  constraint rh_rapports_periode check (periode_fin >= periode_debut)
);

create or replace function public.rh_rapport_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  libres text[] := array['titre', 'periode_debut', 'periode_fin', 'contenu'];
begin
  if coalesce(current_setting('rh.decision', true), '') = 'oui' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.auteur_id := public.rh_moi();
    new.statut := 'brouillon';
    new.cree_le := now();
    new.publie_le := null; new.decision_par := null; new.decision_le := null;
    new.commentaire := '';
    return new;
  end if;
  if old.statut not in ('brouillon', 'rejete') then
    raise exception 'Un rapport publié ne se modifie plus';
  end if;
  if (to_jsonb(new) - libres) is distinct from (to_jsonb(old) - libres) then
    raise exception 'Seuls le titre, la période et le contenu se modifient';
  end if;
  return new;
end $$;

drop trigger if exists rh_rapports_verrous on public.rh_rapports;
create trigger rh_rapports_verrous
  before insert or update on public.rh_rapports
  for each row execute function public.rh_rapport_verrous();

create or replace function public.rh_publier_rapport(rapport uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.rh_rapports;
begin
  select * into r from public.rh_rapports where id = rapport for update;
  if not found or r.auteur_id is distinct from public.rh_moi()
     or not public.rh_responsable_de(r.profil_id) then
    raise exception 'Seul le responsable du profil publie son rapport';
  end if;
  if not public.rh_acces(r.profil_id, 'rapports') then
    raise exception 'Le menu Rapports n''est pas ouvert à votre profil';
  end if;
  if r.statut not in ('brouillon', 'rejete') then
    raise exception 'Ce rapport est déjà publié';
  end if;
  if length(btrim(r.contenu)) < 10 then
    raise exception 'Le rapport est trop court pour être publié';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_rapports set statut = 'publie', publie_le = now() where id = rapport;
  perform set_config('rh.decision', '', true);
end $$;

create or replace function public.rh_decider_rapport(rapport uuid, valider boolean, commentaire text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO valide un rapport d''activité';
  end if;
  if not valider and length(btrim(coalesce(commentaire, ''))) = 0 then
    raise exception 'Dites pourquoi vous rejetez ce rapport';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_rapports
     set statut = case when valider then 'valide' else 'rejete' end,
         decision_par = public.rh_moi(), decision_le = now(),
         commentaire = btrim(coalesce(rh_decider_rapport.commentaire, ''))
   where id = rapport and statut = 'publie';
  if not found then
    raise exception 'Ce rapport n''attend pas de décision';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

-- ---------- Les demandes de dépense ----------
create table if not exists public.rh_depenses (
  id                 uuid primary key default gen_random_uuid(),
  numero             bigint generated always as identity,
  profil_id          uuid not null references public.rh_profils(id) on delete restrict,
  demandeur_id       uuid references public.rh_employes(id) on delete set null,
  objet              text not null check (length(btrim(objet)) > 0),
  details            text not null default '',
  montant            bigint not null check (montant > 0),
  statut             text not null default 'demandee'
                     check (statut in ('demandee', 'approuvee', 'refusee', 'decaissee', 'annulee')),
  cree_le            timestamptz not null default now(),
  decision_par       uuid,
  decision_le        timestamptz,
  motif_decision     text not null default '',
  decaisse_par       uuid,
  decaisse_le        timestamptz,
  mode_decaissement  text check (mode_decaissement in ('especes', 'virement', 'mobile_money', 'cheque')),
  reference          text not null default ''
);

create or replace function public.rh_depense_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  libres text[] := array['objet', 'details', 'montant'];
begin
  if coalesce(current_setting('rh.decision', true), '') = 'oui' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.demandeur_id := public.rh_moi();
    new.statut := 'demandee';
    new.cree_le := now();
    new.decision_par := null; new.decision_le := null; new.motif_decision := '';
    new.decaisse_par := null; new.decaisse_le := null; new.mode_decaissement := null;
    new.reference := '';
    return new;
  end if;
  if old.statut <> 'demandee' then
    raise exception 'Une demande déjà tranchée ne se modifie plus';
  end if;
  if (to_jsonb(new) - libres) is distinct from (to_jsonb(old) - libres) then
    raise exception 'Seuls l''objet, le détail et le montant se modifient';
  end if;
  return new;
end $$;

drop trigger if exists rh_depenses_verrous on public.rh_depenses;
create trigger rh_depenses_verrous
  before insert or update on public.rh_depenses
  for each row execute function public.rh_depense_verrous();

create or replace function public.rh_decider_depense(depense uuid, approuver boolean, motif text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO approuve une dépense';
  end if;
  if not approuver and length(btrim(coalesce(motif, ''))) = 0 then
    raise exception 'Dites pourquoi vous refusez la dépense';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_depenses
     set statut = case when approuver then 'approuvee' else 'refusee' end,
         decision_par = public.rh_moi(), decision_le = now(),
         motif_decision = btrim(coalesce(motif, ''))
   where id = depense and statut = 'demandee';
  if not found then
    raise exception 'Cette dépense n''attend pas de décision';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

create or replace function public.rh_decaisser_depense(depense uuid, mode text, reference text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_peut_decaisser() then
    raise exception 'Votre compte n''est pas habilité à décaisser';
  end if;
  if mode not in ('especes', 'virement', 'mobile_money', 'cheque') then
    raise exception 'Mode de décaissement inconnu';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_depenses
     set statut = 'decaissee', decaisse_par = public.rh_moi(), decaisse_le = now(),
         mode_decaissement = mode, reference = btrim(coalesce(rh_decaisser_depense.reference, ''))
   where id = depense and statut = 'approuvee';
  if not found then
    raise exception 'Seule une dépense approuvée par le CEO se décaisse';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

create or replace function public.rh_annuler_depense(depense uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('rh.decision', 'oui', true);
  update public.rh_depenses set statut = 'annulee'
   where id = depense and statut = 'demandee' and demandeur_id = public.rh_moi();
  if not found then
    raise exception 'Seul le demandeur annule une demande encore en attente';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

-- =========================================================
-- La paie
--
-- AUCUN TAUX N'EST FOURNI, et c'est voulu : la CNSS, l'impôt (ITS)
-- et les autres cotisations sont saisis par l'administration et
-- VALIDÉS par le CEO. Tant qu'un barème n'est pas validé, la fiche
-- l'ignore : elle ne compte que le salaire, les primes, les avances
-- et les retenues.
-- =========================================================

create table if not exists public.rh_cotisations (
  id              uuid primary key default gen_random_uuid(),
  code            text not null check (code ~ '^[A-Z0-9_]{2,20}\Z'),
  libelle         text not null check (length(btrim(libelle)) > 0),
  taux_salarie    numeric(6,3) not null default 0 check (taux_salarie between 0 and 100),
  taux_employeur  numeric(6,3) not null default 0 check (taux_employeur between 0 and 100),
  -- Assiette plafonnée, par mois ; null = pas de plafond.
  plafond         bigint check (plafond is null or plafond > 0),
  stagiaires      boolean not null default false,
  actif           boolean not null default true,
  valide          boolean not null default false,
  saisi_par       uuid,
  saisi_le        timestamptz not null default now(),
  valide_par      uuid,
  valide_le       timestamptz
);
create unique index if not exists rh_cotisations_code on public.rh_cotisations (code);

create or replace function public.rh_cotisation_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('rh.decision', true), '') = 'oui' then
    return new;
  end if;
  /* Toute modification d'un taux repasse par le CEO. */
  new.valide := false;
  new.valide_par := null;
  new.valide_le := null;
  new.saisi_par := public.rh_moi();
  new.saisi_le := now();
  return new;
end $$;

drop trigger if exists rh_cotisations_verrous on public.rh_cotisations;
create trigger rh_cotisations_verrous
  before insert or update on public.rh_cotisations
  for each row execute function public.rh_cotisation_verrous();

create or replace function public.rh_valider_cotisation(cotisation uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO valide un barème';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_cotisations
     set valide = true, valide_par = public.rh_moi(), valide_le = now()
   where id = cotisation and not valide;
  if not found then
    raise exception 'Cette cotisation est déjà validée';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

-- L'impôt sur le salaire : un barème progressif, par tranches mensuelles.
create table if not exists public.rh_tranches_impot (
  id         uuid primary key default gen_random_uuid(),
  borne_inf  bigint not null check (borne_inf >= 0),
  borne_sup  bigint check (borne_sup is null or borne_sup > borne_inf),
  taux       numeric(6,3) not null check (taux between 0 and 100)
);

create table if not exists public.rh_reglages_paie (
  id                boolean primary key default true check (id),
  -- L'assiette de l'impôt : le brut imposable, ou ce brut moins les
  -- cotisations du salarié. Au comptable de dire laquelle.
  impot_sur         text not null default 'brut_imposable'
                    check (impot_sur in ('brut_imposable', 'brut_moins_cotisations')),
  impot_stagiaires  boolean not null default false,
  impot_valide      boolean not null default false,
  impot_valide_par  uuid,
  impot_valide_le   timestamptz
);
insert into public.rh_reglages_paie (id) values (true) on conflict (id) do nothing;

create or replace function public.rh_reglages_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('rh.decision', true), '') = 'oui' then
    return new;
  end if;
  new.impot_valide := false;
  new.impot_valide_par := null;
  new.impot_valide_le := null;
  return new;
end $$;

drop trigger if exists rh_reglages_paie_verrous on public.rh_reglages_paie;
create trigger rh_reglages_paie_verrous
  before update on public.rh_reglages_paie
  for each row execute function public.rh_reglages_verrous();

/* Une tranche qui change rend le barème à valider de nouveau. */
create or replace function public.rh_tranches_changent() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.rh_reglages_paie set impot_valide = false, impot_valide_par = null,
                                     impot_valide_le = null
   where id;
  return null;
end $$;

drop trigger if exists rh_tranches_impot_changent on public.rh_tranches_impot;
create trigger rh_tranches_impot_changent
  after insert or update or delete on public.rh_tranches_impot
  for each statement execute function public.rh_tranches_changent();

create or replace function public.rh_valider_bareme_impot() returns void
language plpgsql security definer set search_path = public as $$
declare
  t record;
  attendu bigint := 0;
  ouverte boolean := false;
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO valide un barème';
  end if;
  if not exists (select 1 from public.rh_tranches_impot) then
    raise exception 'Le barème n''a aucune tranche';
  end if;
  /* Des tranches qui se suivent, de 0 à l'infini, sans trou ni
     chevauchement : sinon un salaire tomberait entre deux. */
  for t in select * from public.rh_tranches_impot order by borne_inf loop
    if ouverte then
      raise exception 'Une seule tranche peut rester ouverte, et c''est la dernière';
    end if;
    if t.borne_inf <> attendu then
      raise exception 'Les tranches doivent se suivre : on attendait une tranche qui commence à %', attendu;
    end if;
    if t.borne_sup is null then
      ouverte := true;
    else
      attendu := t.borne_sup;
    end if;
  end loop;
  if not ouverte then
    raise exception 'La dernière tranche doit rester ouverte (sans borne supérieure)';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_reglages_paie
     set impot_valide = true, impot_valide_par = public.rh_moi(), impot_valide_le = now()
   where id;
  perform set_config('rh.decision', '', true);
end $$;

-- Primes, indemnités, retenues : par employé et par mois.
create table if not exists public.rh_elements_paie (
  id          uuid primary key default gen_random_uuid(),
  employe_id  uuid not null references public.rh_employes(id) on delete cascade,
  mois        date not null check (extract(day from mois) = 1),
  nature      text not null check (nature in ('prime', 'indemnite', 'retenue')),
  libelle     text not null check (length(btrim(libelle)) > 0),
  montant     bigint not null check (montant > 0),
  imposable   boolean not null default true,
  cree_par    uuid,
  cree_le     timestamptz not null default now()
);
create index if not exists rh_elements_paie_mois on public.rh_elements_paie (employe_id, mois);

-- Les avances sur salaire, remboursées sur une ou plusieurs paies.
create table if not exists public.rh_avances (
  id            uuid primary key default gen_random_uuid(),
  employe_id    uuid not null references public.rh_employes(id) on delete cascade,
  date_avance   date not null default current_date,
  montant       bigint not null check (montant > 0),
  mensualites   int not null default 1 check (mensualites between 1 and 24),
  premier_mois  date not null check (extract(day from premier_mois) = 1),
  motif         text not null default '',
  statut        text not null default 'active' check (statut in ('active', 'soldee', 'annulee')),
  cree_par      uuid,
  cree_le       timestamptz not null default now()
);

create table if not exists public.rh_fiches_paie (
  id                     uuid primary key default gen_random_uuid(),
  employe_id             uuid not null references public.rh_employes(id) on delete cascade,
  mois                   date not null check (extract(day from mois) = 1),
  statut                 text not null default 'calculee'
                         check (statut in ('calculee', 'validee', 'payee')),
  jours_payes            int not null,
  jours_du_mois          int not null,
  salaire_base           bigint not null,
  salaire_du             bigint not null,
  primes                 bigint not null default 0,
  brut                   bigint not null,
  brut_imposable         bigint not null,
  cotisations_salariales bigint not null default 0,
  impot                  bigint not null default 0,
  avances                bigint not null default 0,
  retenues               bigint not null default 0,
  net                    bigint not null,
  charges_patronales     bigint not null default 0,
  -- Le détail ligne à ligne, tel que la fiche l'imprime.
  lignes                 jsonb not null default '[]'::jsonb,
  -- Ce que la fiche figeait au calcul : un employé qui change de poste
  -- ne change pas ses fiches passées.
  employe                jsonb not null default '{}'::jsonb,
  calcule_le             timestamptz not null default now(),
  valide_par             uuid,
  valide_le              timestamptz,
  paye_par               uuid,
  paye_le                timestamptz,
  mode_paiement          text,
  reference              text not null default '',
  unique (employe_id, mois)
);
create index if not exists rh_fiches_paie_mois on public.rh_fiches_paie (mois);

-- Ce que chaque fiche a retenu sur chaque avance : le reste dû se lit ici.
create table if not exists public.rh_fiche_avances (
  fiche_id   uuid not null references public.rh_fiches_paie(id) on delete cascade,
  avance_id  uuid not null references public.rh_avances(id) on delete cascade,
  montant    bigint not null check (montant > 0),
  primary key (fiche_id, avance_id)
);

/**
 * Calcule (ou recalcule) la fiche d'un employé pour un mois. Une fiche
 * validée ou payée n'est JAMAIS recalculée : elle a été vue et signée.
 * Fonction interne : aucun compte ne l'appelle directement.
 */
create or replace function public.rh_calculer_fiche(qui uuid, quand date) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  e public.rh_employes;
  debut date := date_trunc('month', quand)::date;
  fin date := (date_trunc('month', quand) + interval '1 month - 1 day')::date;
  jours int;
  d1 date;
  d2 date;
  payes int;
  du bigint;
  lignes jsonb := '[]'::jsonb;
  el record;
  c record;
  a record;
  primes bigint := 0;
  imposable bigint;
  brut bigint;
  cot_sal bigint := 0;
  cot_pat bigint := 0;
  assiette bigint;
  part bigint;
  reglage public.rh_reglages_paie;
  base_impot bigint;
  impot bigint := 0;
  retenues bigint := 0;
  avances bigint := 0;
  reste bigint;
  disponible bigint;
  prise bigint;
  existante public.rh_fiches_paie;
  fiche uuid;
  prises jsonb := '[]'::jsonb;
begin
  jours := fin - debut + 1;
  select * into e from public.rh_employes where id = qui;
  if not found then
    return null;
  end if;
  select * into existante from public.rh_fiches_paie f
   where f.employe_id = qui and f.mois = debut;
  if found and existante.statut <> 'calculee' then
    return existante.id;
  end if;

  /* Payé du jour d'embauche au jour de sortie, au prorata des jours
     calendaires du mois. */
  d1 := greatest(debut, e.date_embauche);
  d2 := least(fin, coalesce(e.date_sortie, fin));
  if e.etat not in ('actif', 'sorti') or d2 < d1 then
    delete from public.rh_fiches_paie f
     where f.employe_id = qui and f.mois = debut and f.statut = 'calculee';
    return null;
  end if;
  payes := d2 - d1 + 1;
  du := round(e.salaire_base::numeric * payes / jours);
  lignes := lignes || jsonb_build_object('genre', 'base', 'libelle',
    case when payes < jours then 'Salaire de base (' || payes || ' jours sur ' || jours || ')'
         else 'Salaire de base' end, 'montant', du);
  imposable := du;

  for el in select * from public.rh_elements_paie x
             where x.employe_id = qui and x.mois = debut and x.nature in ('prime', 'indemnite')
             order by x.cree_le loop
    primes := primes + el.montant;
    if el.imposable then
      imposable := imposable + el.montant;
    end if;
    lignes := lignes || jsonb_build_object('genre', el.nature, 'libelle', el.libelle,
                                           'montant', el.montant, 'imposable', el.imposable);
  end loop;
  brut := du + primes;

  for c in select * from public.rh_cotisations x
            where x.valide and x.actif and (e.statut = 'employe' or x.stagiaires)
            order by x.code loop
    assiette := least(imposable, coalesce(c.plafond, imposable));
    part := round(assiette * c.taux_salarie / 100);
    cot_sal := cot_sal + part;
    cot_pat := cot_pat + round(assiette * c.taux_employeur / 100);
    lignes := lignes || jsonb_build_object('genre', 'cotisation', 'code', c.code,
      'libelle', c.libelle, 'assiette', assiette, 'taux', c.taux_salarie,
      'montant', part, 'taux_employeur', c.taux_employeur,
      'employeur', round(assiette * c.taux_employeur / 100));
  end loop;

  select * into reglage from public.rh_reglages_paie where id;
  if reglage.impot_valide and (e.statut = 'employe' or reglage.impot_stagiaires) then
    base_impot := imposable - case when reglage.impot_sur = 'brut_moins_cotisations'
                                   then cot_sal else 0 end;
    select coalesce(sum(round((least(base_impot, coalesce(t.borne_sup, base_impot)) - t.borne_inf)
                              * t.taux / 100)), 0)
      into impot
      from public.rh_tranches_impot t
     where base_impot > t.borne_inf;
    lignes := lignes || jsonb_build_object('genre', 'impot', 'libelle', 'Impôt sur le salaire',
                                           'assiette', base_impot, 'montant', impot);
  end if;

  for el in select * from public.rh_elements_paie x
             where x.employe_id = qui and x.mois = debut and x.nature = 'retenue'
             order by x.cree_le loop
    retenues := retenues + el.montant;
    lignes := lignes || jsonb_build_object('genre', 'retenue', 'libelle', el.libelle,
                                           'montant', el.montant);
  end loop;

  /* Les avances passent en dernier, et jamais au-delà de ce qui reste :
     une fiche ne descend pas sous zéro à cause d'une avance — le reste
     attend la paie suivante. */
  disponible := greatest(0, brut - cot_sal - impot - retenues);
  for a in select * from public.rh_avances x
            where x.employe_id = qui and x.statut = 'active' and x.premier_mois <= debut
            order by x.date_avance, x.cree_le loop
    select a.montant - coalesce(sum(fa.montant), 0) into reste
      from public.rh_fiche_avances fa
      join public.rh_fiches_paie f on f.id = fa.fiche_id
     where fa.avance_id = a.id and f.mois <> debut;
    prise := least(reste, ceil(a.montant::numeric / a.mensualites)::bigint, disponible);
    if prise > 0 then
      avances := avances + prise;
      disponible := disponible - prise;
      prises := prises || jsonb_build_object('avance', a.id, 'montant', prise);
      lignes := lignes || jsonb_build_object('genre', 'avance', 'libelle',
        'Avance du ' || to_char(a.date_avance, 'DD/MM/YYYY') ||
        case when reste - prise > 0 then ' (reste ' || (reste - prise) || ' FCFA)' else ' (soldée)' end,
        'montant', prise);
    end if;
  end loop;

  insert into public.rh_fiches_paie as f (employe_id, mois, statut, jours_payes, jours_du_mois,
      salaire_base, salaire_du, primes, brut, brut_imposable, cotisations_salariales, impot,
      avances, retenues, net, charges_patronales, lignes, employe, calcule_le)
  values (qui, debut, 'calculee', payes, jours, e.salaire_base, du, primes, brut, imposable,
      cot_sal, impot, avances, retenues, brut - cot_sal - impot - retenues - avances, cot_pat,
      lignes,
      jsonb_build_object('matricule', e.matricule, 'nom', e.nom, 'prenoms', e.prenoms,
        'poste', e.poste, 'statut', e.statut, 'date_embauche', e.date_embauche,
        'numero_cnss', e.numero_cnss, 'mode_paiement', e.mode_paiement,
        'profil', (select p.nom from public.rh_profils p where p.id = e.profil_id)),
      now())
  on conflict on constraint rh_fiches_paie_employe_id_mois_key do update
     set jours_payes = excluded.jours_payes, jours_du_mois = excluded.jours_du_mois,
         salaire_base = excluded.salaire_base, salaire_du = excluded.salaire_du,
         primes = excluded.primes, brut = excluded.brut, brut_imposable = excluded.brut_imposable,
         cotisations_salariales = excluded.cotisations_salariales, impot = excluded.impot,
         avances = excluded.avances, retenues = excluded.retenues, net = excluded.net,
         charges_patronales = excluded.charges_patronales, lignes = excluded.lignes,
         employe = excluded.employe, calcule_le = now()
   where f.statut = 'calculee'
  returning f.id into fiche;

  delete from public.rh_fiche_avances where fiche_id = fiche;
  insert into public.rh_fiche_avances (fiche_id, avance_id, montant)
  select fiche, (x ->> 'avance')::uuid, (x ->> 'montant')::bigint
    from jsonb_array_elements(prises) x;
  return fiche;
end $$;

/** Toutes les fiches d'un mois. Interne : la paie automatique l'appelle. */
create or replace function public.rh_generer_paie_interne(mois date) returns int
language plpgsql security definer set search_path = public as $$
declare
  debut date := date_trunc('month', mois)::date;
  fin date := (date_trunc('month', mois) + interval '1 month - 1 day')::date;
  e record;
  combien int := 0;
begin
  for e in select id from public.rh_employes
            where (etat = 'actif' or (etat = 'sorti' and date_sortie >= debut))
              and date_embauche <= fin loop
    if public.rh_calculer_fiche(e.id, debut) is not null then
      combien := combien + 1;
    end if;
  end loop;
  /* Un employé qui n'est plus à payer ce mois-là perd sa fiche non validée. */
  delete from public.rh_fiches_paie f
   where f.mois = debut and f.statut = 'calculee'
     and not exists (select 1 from public.rh_employes x
                      where x.id = f.employe_id
                        and (x.etat = 'actif' or (x.etat = 'sorti' and x.date_sortie >= debut))
                        and x.date_embauche <= fin);
  return combien;
end $$;

create or replace function public.rh_generer_paie(mois date) returns int
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_admin() then
    raise exception 'Seule l''administration prépare la paie';
  end if;
  if date_trunc('month', mois) > date_trunc('month', (now() at time zone 'Africa/Porto-Novo')) then
    raise exception 'On ne prépare pas la paie d''un mois à venir';
  end if;
  return public.rh_generer_paie_interne(mois);
end $$;

/**
 * La paie de fin de mois, sans que personne n'y pense : le dernier jour
 * du mois (heure du Bénin), les fiches du mois sont calculées ; et le
 * mois précédent l'est aussi s'il a été oublié. Appelée par pg_cron
 * chaque soir du 28 au 31, et par l'application à l'ouverture.
 */
create or replace function public.rh_generer_paie_auto() returns int
language plpgsql security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  courant date := date_trunc('month', aujourdhui)::date;
  precedent date := (date_trunc('month', aujourdhui) - interval '1 month')::date;
  combien int := 0;
begin
  if not exists (select 1 from public.rh_fiches_paie where mois = precedent) then
    combien := combien + public.rh_generer_paie_interne(precedent);
  end if;
  if extract(day from aujourdhui + 1) = 1 then
    combien := combien + public.rh_generer_paie_interne(courant);
  end if;
  return combien;
end $$;

/** Ce que l'application appelle à l'ouverture, pour l'administration. */
create or replace function public.rh_paie_a_jour() returns int
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_admin() then
    return 0;
  end if;
  return public.rh_generer_paie_auto();
end $$;

/* Une prime ou une avance qui change refait la fiche du mois, si elle
   n'est pas encore validée ; et l'interdit si elle l'est. */
create or replace function public.rh_element_paie_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  ligne record;
begin
  for ligne in
    select x.employe_id, x.mois from (
      select new.employe_id as employe_id, new.mois as mois where tg_op <> 'DELETE'
      union all
      select old.employe_id, old.mois where tg_op <> 'INSERT') x loop
    if exists (select 1 from public.rh_fiches_paie f
                where f.employe_id = ligne.employe_id and f.mois = ligne.mois
                  and f.statut <> 'calculee') then
      raise exception 'La fiche de ce mois est déjà validée : demandez au CEO de la rouvrir';
    end if;
    if exists (select 1 from public.rh_fiches_paie f
                where f.employe_id = ligne.employe_id and f.mois = ligne.mois) then
      perform public.rh_calculer_fiche(ligne.employe_id, ligne.mois);
    end if;
  end loop;
  return null;
end $$;

drop trigger if exists rh_elements_paie_change on public.rh_elements_paie;
create trigger rh_elements_paie_change
  after insert or update or delete on public.rh_elements_paie
  for each row execute function public.rh_element_paie_change();

create or replace function public.rh_element_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.cree_par := public.rh_moi();
  new.cree_le := now();
  return new;
end $$;

drop trigger if exists rh_elements_paie_verrous on public.rh_elements_paie;
create trigger rh_elements_paie_verrous
  before insert on public.rh_elements_paie
  for each row execute function public.rh_element_verrous();

drop trigger if exists rh_avances_verrous on public.rh_avances;
create trigger rh_avances_verrous
  before insert on public.rh_avances
  for each row execute function public.rh_element_verrous();

/* Une avance déjà retenue sur une fiche validée ne se modifie plus. */
create or replace function public.rh_avance_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  cible uuid := coalesce(new.id, old.id);
  f record;
begin
  if coalesce(current_setting('rh.decision', true), '') = 'oui' then
    return null;
  end if;
  if exists (select 1 from public.rh_fiche_avances fa
               join public.rh_fiches_paie x on x.id = fa.fiche_id
              where fa.avance_id = cible and x.statut <> 'calculee') then
    raise exception 'Cette avance est déjà retenue sur une paie validée : elle ne se modifie plus';
  end if;
  for f in select x.employe_id, x.mois from public.rh_fiches_paie x
            where x.employe_id = coalesce(new.employe_id, old.employe_id)
              and x.statut = 'calculee' loop
    perform public.rh_calculer_fiche(f.employe_id, f.mois);
  end loop;
  return null;
end $$;

drop trigger if exists rh_avances_change on public.rh_avances;
create trigger rh_avances_change
  after insert or update or delete on public.rh_avances
  for each row execute function public.rh_avance_change();

/** Le CEO valide la paie d'un mois : recalculée une dernière fois, puis figée. */
create or replace function public.rh_valider_paie(mois date) returns int
language plpgsql security definer set search_path = public as $$
declare
  debut date := date_trunc('month', mois)::date;
  combien int;
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO valide la paie';
  end if;
  perform public.rh_generer_paie_interne(debut);
  update public.rh_fiches_paie
     set statut = 'validee', valide_par = public.rh_moi(), valide_le = now()
   where rh_fiches_paie.mois = debut and statut = 'calculee';
  get diagnostics combien = row_count;
  /* Une avance remboursée en entier est soldée. */
  perform set_config('rh.decision', 'oui', true);
  update public.rh_avances a set statut = 'soldee'
   where a.statut = 'active'
     and a.montant <= (select coalesce(sum(fa.montant), 0)
                         from public.rh_fiche_avances fa
                         join public.rh_fiches_paie f on f.id = fa.fiche_id
                        where fa.avance_id = a.id and f.statut <> 'calculee');
  perform set_config('rh.decision', '', true);
  return combien;
end $$;

/** Le CEO rouvre une fiche validée mais pas encore payée, pour la corriger. */
create or replace function public.rh_rouvrir_fiche(fiche uuid) returns void
language plpgsql security definer set search_path = public as $$
declare f public.rh_fiches_paie;
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO rouvre une fiche de paie';
  end if;
  update public.rh_fiches_paie set statut = 'calculee', valide_par = null, valide_le = null
   where id = fiche and statut = 'validee'
  returning * into f;
  if f.id is null then
    raise exception 'Seule une fiche validée et pas encore payée se rouvre';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_avances a set statut = 'active'
   where a.statut = 'soldee'
     and exists (select 1 from public.rh_fiche_avances fa where fa.fiche_id = f.id and fa.avance_id = a.id);
  perform set_config('rh.decision', '', true);
  perform public.rh_calculer_fiche(f.employe_id, f.mois);
end $$;

create or replace function public.rh_payer_fiche(fiche uuid, mode text, reference text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_peut_decaisser() then
    raise exception 'Votre compte n''est pas habilité à payer';
  end if;
  if mode not in ('especes', 'virement', 'mobile_money', 'cheque') then
    raise exception 'Mode de paiement inconnu';
  end if;
  update public.rh_fiches_paie
     set statut = 'payee', paye_par = public.rh_moi(), paye_le = now(),
         mode_paiement = mode, reference = btrim(coalesce(rh_payer_fiche.reference, ''))
   where id = fiche and statut = 'validee';
  if not found then
    raise exception 'Seule une fiche validée par le CEO se paie';
  end if;
end $$;

-- ---------- La boîte mail professionnelle ----------
-- Le mot de passe de la boîte, CHIFFRÉ par la fonction Edge
-- « rh-messagerie » avec une clé qui ne quitte jamais le serveur.
-- Aucune règle RLS : aucun compte ne lit cette table, pas même le CEO.
-- Seule la fonction Edge (clé de service) y accède.
create table if not exists public.rh_boites_mail (
  employe_id     uuid primary key references public.rh_employes(id) on delete cascade,
  secret         text not null,
  iv             text not null,
  enregistre_le  timestamptz not null default now()
);

create or replace function public.rh_ma_messagerie() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'email', e.email_pro,
    'configuree', b.employe_id is not null,
    'enregistre_le', b.enregistre_le)
    from public.rh_employes e
    left join public.rh_boites_mail b on b.employe_id = e.id
   where e.id = public.rh_moi();
$$;

create or replace function public.rh_oublier_ma_messagerie() returns void
language sql security definer set search_path = public as $$
  delete from public.rh_boites_mail where employe_id = public.rh_moi();
$$;

-- ---------- Le tableau de bord ----------
-- Qui je suis, et ce qui m'attend. Un seul appel à l'ouverture.
create or replace function public.rh_tableau_de_bord() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  moi public.rh_employes;
  v_ceo boolean;
  v_admin boolean;
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  mes_profils uuid[];
begin
  select * into moi from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
  if not found then
    return jsonb_build_object(
      'moi', null,
      'en_attente', exists (select 1 from public.rh_employes where compte_id = auth.uid()),
      'amorce_possible', not exists (select 1 from public.rh_employes where ceo)
                         and public.est_super());
  end if;
  v_ceo := moi.ceo;
  v_admin := moi.ceo or moi.administration;
  select coalesce(array_agg(id), '{}') into mes_profils
    from public.rh_profils where responsable_id = moi.id;
  return jsonb_build_object(
    'moi', jsonb_build_object(
      'id', moi.id, 'matricule', moi.matricule, 'nom', moi.nom, 'prenoms', moi.prenoms,
      'sexe', moi.sexe, 'poste', moi.poste, 'email_pro', moi.email_pro,
      'ceo', v_ceo, 'administration', v_admin, 'peut_decaisser', moi.peut_decaisser,
      'profil_id', moi.profil_id,
      'profil', (select nom from public.rh_profils where id = moi.profil_id),
      'responsable_de', to_jsonb(mes_profils)),
    'compteurs', jsonb_build_object(
      'employes_a_valider', case when v_ceo then
        (select count(*) from public.rh_employes where etat = 'en_attente') else 0 end,
      'missions_a_repondre',
        (select count(*) from public.rh_missions where statut = 'proposee' and profil_id = any(mes_profils)
            and public.rh_acces(profil_id, 'missions')),
      'missions_en_cours',
        (select count(*) from public.rh_missions
          where statut in ('acceptee', 'a_reprendre')
            and (v_admin or ((profil_id = any(mes_profils) or profil_id = moi.profil_id)
                             and public.rh_acces(profil_id, 'missions')))),
      'missions_en_retard',
        (select count(*) from public.rh_missions
          where statut in ('acceptee', 'a_reprendre') and echeance < aujourdhui
            and (v_admin or (profil_id = any(mes_profils) and public.rh_acces(profil_id, 'missions')))),
      'missions_a_cloturer', case when v_admin then
        (select count(*) from public.rh_missions where statut = 'rapport_remis') else 0 end,
      'rapports_a_valider', case when v_ceo then
        (select count(*) from public.rh_rapports where statut = 'publie') else 0 end,
      'depenses_a_approuver', case when v_ceo then
        (select count(*) from public.rh_depenses where statut = 'demandee') else 0 end,
      'depenses_a_decaisser', case when moi.peut_decaisser then
        (select count(*) from public.rh_depenses where statut = 'approuvee') else 0 end,
      'baremes_a_valider', case when v_ceo then
        (select count(*) from public.rh_cotisations where actif and not valide)
        + (select count(*) from public.rh_reglages_paie r
            where not r.impot_valide and exists (select 1 from public.rh_tranches_impot)) else 0 end,
      'fiches_a_valider', case when v_ceo then
        (select count(*) from public.rh_fiches_paie
          where statut = 'calculee'
            and mois < date_trunc('month', aujourdhui + 1)::date) else 0 end,
      'fiches_a_payer', case when moi.peut_decaisser then
        (select count(*) from public.rh_fiches_paie where statut = 'validee') else 0 end,
      'messages_non_lus', (select coalesce(sum(non_lus), 0) from public.rh_conversations())));
end $$;

-- =========================================================
-- Les règles d'accès
-- =========================================================
alter table public.rh_employes      enable row level security;
alter table public.rh_profils       enable row level security;
alter table public.rh_messages      enable row level security;
alter table public.rh_lectures      enable row level security;
alter table public.rh_missions      enable row level security;
alter table public.rh_rapports      enable row level security;
alter table public.rh_depenses      enable row level security;
alter table public.rh_cotisations   enable row level security;
alter table public.rh_tranches_impot enable row level security;
alter table public.rh_reglages_paie enable row level security;
alter table public.rh_elements_paie enable row level security;
alter table public.rh_avances       enable row level security;
alter table public.rh_fiches_paie   enable row level security;
alter table public.rh_fiche_avances enable row level security;
alter table public.rh_boites_mail   enable row level security;

drop policy if exists "rh employes lecture" on public.rh_employes;
drop policy if exists "rh employes ajout" on public.rh_employes;
drop policy if exists "rh employes modification" on public.rh_employes;
drop policy if exists "rh employes suppression" on public.rh_employes;
-- La fiche complète (salaire compris) : l'administration, et l'employé
-- lui-même. Les autres passent par l'annuaire.
create policy "rh employes lecture" on public.rh_employes
  for select to authenticated using (public.rh_est_admin() or compte_id = auth.uid());
create policy "rh employes ajout" on public.rh_employes
  for insert to authenticated with check (public.rh_est_admin());
create policy "rh employes modification" on public.rh_employes
  for update to authenticated
  using (public.rh_est_admin() or (compte_id = auth.uid() and etat = 'actif'))
  with check (public.rh_est_admin() or (compte_id = auth.uid() and etat = 'actif'));
create policy "rh employes suppression" on public.rh_employes
  for delete to authenticated
  using (public.rh_est_ceo() and etat in ('en_attente', 'refuse'));

drop policy if exists "rh profils lecture" on public.rh_profils;
drop policy if exists "rh profils ecriture" on public.rh_profils;
create policy "rh profils lecture" on public.rh_profils
  for select to authenticated using (public.rh_moi() is not null);
create policy "rh profils ecriture" on public.rh_profils
  for all to authenticated using (public.rh_est_admin()) with check (public.rh_est_admin());

drop policy if exists "rh messages lecture" on public.rh_messages;
drop policy if exists "rh messages envoi" on public.rh_messages;
-- Un message privé reste privé : l'administration lit les discussions
-- de tous les profils, pas les messages entre deux personnes.
create policy "rh messages lecture" on public.rh_messages
  for select to authenticated using (
    (profil_id is not null and public.rh_acces(profil_id, 'discussions'))
    or (destinataire_id is not null
        and (auteur_id = public.rh_moi() or destinataire_id = public.rh_moi())
        and public.rh_menu_ouvert('discussions')));
create policy "rh messages envoi" on public.rh_messages
  for insert to authenticated with check (
    (profil_id is not null and public.rh_acces(profil_id, 'discussions'))
    or (destinataire_id is not null and public.rh_peut_ecrire_a(destinataire_id)
        and public.rh_menu_ouvert('discussions')));

drop policy if exists "rh missions lecture" on public.rh_missions;
drop policy if exists "rh missions creation" on public.rh_missions;
drop policy if exists "rh missions modification" on public.rh_missions;
drop policy if exists "rh missions suppression" on public.rh_missions;
create policy "rh missions lecture" on public.rh_missions
  for select to authenticated using (public.rh_acces(profil_id, 'missions'));
create policy "rh missions creation" on public.rh_missions
  for insert to authenticated with check (public.rh_est_admin());
create policy "rh missions modification" on public.rh_missions
  for update to authenticated using (public.rh_est_admin()) with check (public.rh_est_admin());
create policy "rh missions suppression" on public.rh_missions
  for delete to authenticated using (public.rh_est_admin() and statut in ('proposee', 'refusee'));

drop policy if exists "rh rapports lecture" on public.rh_rapports;
drop policy if exists "rh rapports creation" on public.rh_rapports;
drop policy if exists "rh rapports modification" on public.rh_rapports;
drop policy if exists "rh rapports suppression" on public.rh_rapports;
create policy "rh rapports lecture" on public.rh_rapports
  for select to authenticated using (
    auteur_id = public.rh_moi()
    or (public.rh_est_admin() and statut <> 'brouillon')
    or (statut = 'valide' and public.rh_acces(profil_id, 'rapports')));
create policy "rh rapports creation" on public.rh_rapports
  for insert to authenticated
  with check (public.rh_responsable_de(profil_id) and public.rh_acces(profil_id, 'rapports'));
create policy "rh rapports modification" on public.rh_rapports
  for update to authenticated
  using (auteur_id = public.rh_moi() and public.rh_responsable_de(profil_id))
  with check (auteur_id = public.rh_moi() and public.rh_responsable_de(profil_id)
              and public.rh_acces(profil_id, 'rapports'));
create policy "rh rapports suppression" on public.rh_rapports
  for delete to authenticated using (auteur_id = public.rh_moi() and statut = 'brouillon');

drop policy if exists "rh depenses lecture" on public.rh_depenses;
drop policy if exists "rh depenses demande" on public.rh_depenses;
drop policy if exists "rh depenses modification" on public.rh_depenses;
create policy "rh depenses lecture" on public.rh_depenses
  for select to authenticated using (
    public.rh_est_admin()
    or demandeur_id = public.rh_moi()
    or public.rh_responsable_de(profil_id)
    or (public.rh_peut_decaisser() and statut in ('approuvee', 'decaissee')));
create policy "rh depenses demande" on public.rh_depenses
  for insert to authenticated
  with check (public.rh_responsable_de(profil_id) and public.rh_acces(profil_id, 'depenses'));
create policy "rh depenses modification" on public.rh_depenses
  for update to authenticated
  using (demandeur_id = public.rh_moi()) with check (demandeur_id = public.rh_moi());

drop policy if exists "rh cotisations administration" on public.rh_cotisations;
create policy "rh cotisations administration" on public.rh_cotisations
  for all to authenticated using (public.rh_est_admin()) with check (public.rh_est_admin());
drop policy if exists "rh tranches administration" on public.rh_tranches_impot;
create policy "rh tranches administration" on public.rh_tranches_impot
  for all to authenticated using (public.rh_est_admin()) with check (public.rh_est_admin());
drop policy if exists "rh reglages lecture" on public.rh_reglages_paie;
drop policy if exists "rh reglages modification" on public.rh_reglages_paie;
create policy "rh reglages lecture" on public.rh_reglages_paie
  for select to authenticated using (public.rh_est_admin());
create policy "rh reglages modification" on public.rh_reglages_paie
  for update to authenticated using (public.rh_est_admin()) with check (public.rh_est_admin());

drop policy if exists "rh elements administration" on public.rh_elements_paie;
create policy "rh elements administration" on public.rh_elements_paie
  for all to authenticated using (public.rh_est_admin()) with check (public.rh_est_admin());

drop policy if exists "rh avances lecture" on public.rh_avances;
drop policy if exists "rh avances ecriture" on public.rh_avances;
create policy "rh avances lecture" on public.rh_avances
  for select to authenticated using (public.rh_est_admin() or employe_id = public.rh_moi());
create policy "rh avances ecriture" on public.rh_avances
  for all to authenticated using (public.rh_est_admin()) with check (public.rh_est_admin());

drop policy if exists "rh fiches lecture" on public.rh_fiches_paie;
-- L'employé voit ses fiches une fois validées : un brouillon de paie
-- n'est pas une promesse. L'habilité voit toutes les fiches validées :
-- c'est lui qui les paie.
create policy "rh fiches lecture" on public.rh_fiches_paie
  for select to authenticated using (
    public.rh_est_admin()
    or (statut <> 'calculee' and (employe_id = public.rh_moi() or public.rh_peut_decaisser())));

-- ---------- Les droits ----------
-- Supabase accorde d'office tout à « anon » sur ce qui naît dans
-- « public » : on le lui retire nommément. Les tables se lisent et
-- s'écrivent sous les règles ci-dessus ; les décisions passent par
-- leurs fonctions.
do $$
declare t text;
begin
  foreach t in array array['rh_employes', 'rh_profils', 'rh_messages', 'rh_lectures',
    'rh_missions', 'rh_rapports', 'rh_depenses', 'rh_cotisations', 'rh_tranches_impot',
    'rh_reglages_paie', 'rh_elements_paie', 'rh_avances', 'rh_fiches_paie',
    'rh_fiche_avances', 'rh_boites_mail'] loop
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
    execute format('grant all on table public.%I to service_role', t);
  end loop;
end $$;
grant select, insert, update, delete on public.rh_employes, public.rh_profils,
  public.rh_missions, public.rh_rapports, public.rh_cotisations, public.rh_tranches_impot,
  public.rh_elements_paie, public.rh_avances to authenticated;
grant select, insert on public.rh_messages to authenticated;
grant select, update on public.rh_depenses, public.rh_reglages_paie to authenticated;
grant insert on public.rh_depenses to authenticated;
grant select on public.rh_fiches_paie to authenticated;
revoke all on sequence public.rh_matricule_seq from public, anon;
grant usage on sequence public.rh_matricule_seq to authenticated, service_role;

-- Les fonctions : aucune pour « anon » ; les décisions et les aides
-- des règles pour les comptes connectés ; le calcul de la paie pour
-- personne — il ne s'appelle que de l'intérieur.
do $$
declare f text;
begin
  foreach f in array array[
    'rh_moi()', 'rh_est_ceo()', 'rh_est_admin()', 'rh_peut_decaisser()', 'rh_mon_profil()',
    'rh_responsable_de(uuid)', 'rh_membre_de(uuid)', 'rh_peut_ecrire_a(uuid)',
    'rh_acces(uuid, text)', 'rh_menu_ouvert(text)',
    'rh_decider_employe(uuid, boolean, text)', 'rh_sortie_employe(uuid, date, text)',
    'rh_rattacher_compte(uuid)', 'rh_devenir_ceo(text, text, text)', 'rh_annuaire()',
    'rh_designer_ceo(text, text, text, text, text, text, text)',
    'rh_marquer_lu(text)', 'rh_conversations()',
    'rh_repondre_mission(uuid, boolean, text)', 'rh_rendre_rapport_mission(uuid, text)',
    'rh_cloturer_mission(uuid, boolean, text)',
    'rh_publier_rapport(uuid)', 'rh_decider_rapport(uuid, boolean, text)',
    'rh_decider_depense(uuid, boolean, text)', 'rh_decaisser_depense(uuid, text, text)',
    'rh_annuler_depense(uuid)',
    'rh_valider_cotisation(uuid)', 'rh_valider_bareme_impot()',
    'rh_generer_paie(date)', 'rh_paie_a_jour()', 'rh_valider_paie(date)',
    'rh_rouvrir_fiche(uuid)', 'rh_payer_fiche(uuid, text, text)',
    'rh_ma_messagerie()', 'rh_oublier_ma_messagerie()', 'rh_tableau_de_bord()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
  foreach f in array array[
    'rh_calculer_fiche(uuid, date)', 'rh_generer_paie_interne(date)', 'rh_generer_paie_auto()',
    'rh_employe_verrous()', 'rh_employe_apres()', 'rh_profil_verrous()', 'rh_compte_personnel()',
    'rh_message_verrous()', 'rh_mission_verrous()', 'rh_rapport_verrous()',
    'rh_depense_verrous()', 'rh_cotisation_verrous()', 'rh_reglages_verrous()',
    'rh_tranches_changent()', 'rh_element_paie_change()', 'rh_element_verrous()',
    'rh_avance_change()'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

-- ---------- La paie de fin de mois, toute seule ----------
-- pg_cron appelle la paie chaque soir du 28 au 31 à 18 h (heure du
-- Bénin, 17 h UTC) ; la fonction ne travaille que le dernier jour. Sans
-- pg_cron, rien ne casse : l'application rattrape à l'ouverture.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('rh-paie-fin-de-mois', '0 17 28-31 * *',
                          'select public.rh_generer_paie_auto()');
  end if;
exception when others then
  raise notice 'Paie automatique non programmée (%), l''application la rattrapera', sqlerrm;
end $$;
