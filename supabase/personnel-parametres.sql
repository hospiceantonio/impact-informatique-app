-- =========================================================
-- BIZZOO Personnel : le menu Paramètres
--
-- Les accès aux menus, profil par profil (rh_acces_menus) : à qui
-- l'administration ouvre le suivi des commandes, chacun des six
-- sous-menus des statistiques, les missions, les rapports, les
-- dépenses, les mails, les discussions et l'annuaire des employés —
-- au responsable seul, ou à tous les membres du profil. Et
-- l'en-tête de l'entreprise imprimé sur les bulletins de paie.
--
-- La base applique elle-même ces accès : les règles RLS et les
-- fonctions des missions, des rapports, des dépenses, des discussions,
-- du suivi et des statistiques consultent rh_acces() et
-- rh_menu_ouvert(). Le premier passage reprend les droits d'avant :
-- rien ne se ferme pour personne ce jour-là.
-- =========================================================

alter table public.rh_profils
  add column if not exists statistiques text[] not null default '{}';

-- ---------- Les aides d'accès (copies de schema.sql) ----------
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

create or replace function public.rh_membre_de(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select cible is not null
     and (public.rh_mon_profil() = cible or public.rh_responsable_de(cible));
$$;

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

-- ---------- Les accès aux menus, profil par profil ----------
-- Une ligne = un menu ouvert à un profil : à son responsable seul, ou à
-- tous ses membres (le responsable compris). Pas de ligne = menu fermé.
-- L'administration (CEO compris) a toujours tout. Profils, Paie et
-- Paramètres ne s'ouvrent à personne d'autre : ils touchent aux
-- salaires et aux droits. « Employés » s'ouvre en lecture : l'annuaire,
-- sans salaire.
create table if not exists public.rh_acces_menus (
  profil_id    uuid not null references public.rh_profils(id) on delete cascade,
  menu         text not null,
  qui          text not null default 'membres',
  modifie_par  uuid references public.rh_employes(id) on delete set null,
  modifie_le   timestamptz not null default now(),
  primary key (profil_id, menu),
  constraint rh_acces_menus_menu check (menu in ('mails', 'discussions', 'missions', 'rapports',
    'depenses', 'suivi', 'stats_commandes', 'stats_boutiques', 'stats_produits',
    'stats_livraisons', 'stats_livreurs', 'stats_sav', 'employes')),
  constraint rh_acces_menus_qui check (qui in ('responsable', 'membres')),
  -- Une dépense se demande par le responsable du profil : c'est la règle.
  constraint rh_acces_depenses_responsable check (menu <> 'depenses' or qui = 'responsable')
);

-- Le premier passage reprend ce qui était vrai jusqu'ici : mails,
-- discussions, missions et rapports pour tous les membres, dépenses
-- pour le responsable, et les rubriques de statistiques et de suivi
-- déjà cochées dans la fiche du profil, pour son responsable.
do $$
begin
  if not exists (select 1 from public.rh_acces_menus) then
    insert into public.rh_acces_menus (profil_id, menu, qui)
    select p.id, d.menu, d.qui
      from public.rh_profils p,
           (values ('mails', 'membres'), ('discussions', 'membres'), ('missions', 'membres'),
                   ('rapports', 'membres'), ('depenses', 'responsable')) as d(menu, qui)
    union all
    select p.id, m.menu, 'responsable'
      from public.rh_profils p
      cross join lateral unnest(p.statistiques) as r(rubrique)
      cross join lateral unnest(case r.rubrique
          when 'commandes' then array['stats_commandes', 'stats_boutiques', 'stats_produits']
          when 'livraisons' then array['stats_livraisons', 'stats_livreurs']
          when 'sav' then array['stats_sav']
          when 'suivi' then array['suivi']
          else array[]::text[] end) as m(menu)
    on conflict do nothing;
  end if;
end $$;

/** Un profil qui naît reçoit les accès de base. */
create or replace function public.rh_profil_acces_defaut() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.rh_acces_menus (profil_id, menu, qui)
  values (new.id, 'mails', 'membres'), (new.id, 'discussions', 'membres'),
         (new.id, 'missions', 'membres'), (new.id, 'rapports', 'membres'),
         (new.id, 'depenses', 'responsable')
  on conflict do nothing;
  return null;
end $$;
drop trigger if exists rh_profil_acces_defaut on public.rh_profils;
create trigger rh_profil_acces_defaut after insert on public.rh_profils
  for each row execute function public.rh_profil_acces_defaut();

/** Régler les accès d'un profil : { "menu": "membres" | "responsable" | "ferme" }.
    Un menu absent du réglage ne change pas. L'administration seule. */
create or replace function public.rh_regler_acces(cible uuid, choix jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  k text;
  v text;
begin
  if not public.rh_est_admin() then
    raise exception 'Seule l''administration règle les accès aux menus';
  end if;
  if not exists (select 1 from public.rh_profils where id = cible) then
    raise exception 'Profil introuvable';
  end if;
  if jsonb_typeof(choix) is distinct from 'object' then
    raise exception 'Réglage illisible';
  end if;
  for k, v in select e.key, e.value #>> '{}' from jsonb_each(choix) as e loop
    if k not in ('mails', 'discussions', 'missions', 'rapports', 'depenses', 'suivi',
                 'stats_commandes', 'stats_boutiques', 'stats_produits', 'stats_livraisons',
                 'stats_livreurs', 'stats_sav', 'employes') then
      raise exception 'Menu inconnu : %', k;
    end if;
    if v is null or v = 'ferme' then
      delete from public.rh_acces_menus where profil_id = cible and menu = k;
    elsif v not in ('membres', 'responsable') then
      raise exception 'Réglage inconnu pour le menu %', k;
    elsif k = 'depenses' and v = 'membres' then
      raise exception 'Les dépenses se demandent par le responsable du profil seulement';
    else
      insert into public.rh_acces_menus (profil_id, menu, qui, modifie_par, modifie_le)
      values (cible, k, v, public.rh_moi(), now())
      on conflict on constraint rh_acces_menus_pkey do update
        set qui = excluded.qui, modifie_par = excluded.modifie_par, modifie_le = excluded.modifie_le
        where public.rh_acces_menus.qui is distinct from excluded.qui;
    end if;
  end loop;
end $$;

/** Les menus ouverts à mon compte, dans l'ordre du menu. */
create or replace function public.rh_mes_menus() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(x.m order by x.n), '{}')
    from unnest(array['mails', 'discussions', 'missions', 'rapports', 'depenses', 'suivi',
                      'stats_commandes', 'stats_boutiques', 'stats_produits', 'stats_livraisons',
                      'stats_livreurs', 'stats_sav', 'employes']) with ordinality as x(m, n)
   where public.rh_menu_ouvert(x.m);
$$;

-- ---------- L'entreprise ----------
-- L'en-tête des bulletins de paie. Rien n'est inventé : seuls le nom et
-- le site, déjà imprimés jusqu'ici, sont remplis d'avance.
create table if not exists public.rh_entreprise (
  id              boolean primary key default true check (id),
  raison_sociale  text not null default 'BIZZOO',
  site            text not null default 'bizzoomarket.com',
  adresse         text not null default '',
  telephone       text not null default '',
  email           text not null default '',
  ifu             text not null default '',
  rccm            text not null default '',
  cnss_employeur  text not null default '',
  modifie_par     uuid references public.rh_employes(id) on delete set null,
  modifie_le      timestamptz,
  constraint rh_entreprise_raison check (length(btrim(raison_sociale)) between 1 and 120),
  constraint rh_entreprise_longueurs check (greatest(length(site), length(adresse), length(telephone),
    length(email), length(ifu), length(rccm), length(cnss_employeur)) <= 200)
);
insert into public.rh_entreprise (id) values (true) on conflict (id) do nothing;

create or replace function public.rh_entreprise_trace() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.id := true;
  new.modifie_par := public.rh_moi();
  new.modifie_le := now();
  return new;
end $$;
drop trigger if exists rh_entreprise_trace on public.rh_entreprise;
create trigger rh_entreprise_trace before update on public.rh_entreprise
  for each row execute function public.rh_entreprise_trace();

-- ---------- Les règles d'accès ----------
alter table public.rh_acces_menus enable row level security;
alter table public.rh_entreprise enable row level security;
drop policy if exists "rh acces lecture" on public.rh_acces_menus;
-- Personne n'écrit la table directement : rh_regler_acces le fait.
create policy "rh acces lecture" on public.rh_acces_menus
  for select to authenticated using (public.rh_est_admin() or public.rh_membre_de(profil_id));
drop policy if exists "rh entreprise lecture" on public.rh_entreprise;
drop policy if exists "rh entreprise modification" on public.rh_entreprise;
create policy "rh entreprise lecture" on public.rh_entreprise
  for select to authenticated using (public.rh_moi() is not null);
create policy "rh entreprise modification" on public.rh_entreprise
  for update to authenticated using (public.rh_est_admin()) with check (public.rh_est_admin());

revoke all on table public.rh_acces_menus, public.rh_entreprise from public, anon, authenticated;
grant all on table public.rh_acces_menus, public.rh_entreprise to service_role;
grant select on public.rh_acces_menus, public.rh_entreprise to authenticated;
grant update (raison_sociale, site, adresse, telephone, email, ifu, rccm, cnss_employeur)
  on public.rh_entreprise to authenticated;

do $$
declare f text;
begin
  foreach f in array array['rh_regler_acces(uuid, jsonb)', 'rh_mes_menus()',
                           'rh_acces(uuid, text)', 'rh_menu_ouvert(text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
  foreach f in array array['rh_profil_acces_defaut()', 'rh_entreprise_trace()'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

-- ---------- Ce qui consulte désormais les accès (copies de schema.sql) ----------
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

create or replace function public.rh_statistiques(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  fin date := coalesce(jusqu, aujourdhui);
  debut date := coalesce(depuis, coalesce(jusqu, aujourdhui) - 29);
  t1 timestamptz;
  t2 timestamptz;
  v_ceo boolean := public.rh_est_ceo();
  v_admin boolean := public.rh_est_admin();
  argent boolean;
  marge boolean;
  rubriques text[];
  sous text[];
  commandes jsonb := null;
  livraisons jsonb := null;
  sav jsonb := null;
begin
  -- Les sous-menus ouverts par le menu Paramètres (tous pour
  -- l'administration), puis les blocs de calcul dont ils dépendent.
  select coalesce(array_agg(x.s order by x.n), '{}') into sous
    from unnest(array['commandes', 'boutiques', 'produits', 'livraisons', 'livreurs', 'sav'])
         with ordinality as x(s, n)
   where public.rh_menu_ouvert('stats_' || x.s);
  rubriques := array[]::text[];
  if sous && array['commandes', 'boutiques', 'produits'] then
    rubriques := rubriques || 'commandes'::text;
  end if;
  if sous && array['livraisons', 'livreurs'] then
    rubriques := rubriques || 'livraisons'::text;
  end if;
  if 'sav' = any(sous) then
    rubriques := rubriques || 'sav'::text;
  end if;
  if coalesce(array_length(rubriques, 1), 0) = 0 then
    raise exception 'Votre compte n''a pas accès aux statistiques';
  end if;
  argent := v_admin;
  marge := v_ceo;
  if fin < debut then
    raise exception 'La fin de la période précède son début';
  end if;
  if fin - debut > 1100 then
    raise exception 'Choisissez une période de trois ans au plus';
  end if;
  t1 := debut::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (fin + 1)::timestamp at time zone 'Africa/Porto-Novo';

  -- ---------- Les commandes ----------
  if 'commandes' = any(rubriques) then
    with payees as (
      select c.* from public.commandes c
       where c.etat = 'payee' and c.paye_le >= t1 and c.paye_le < t2
    ),
    lignes as (
      select l.*, c.paye_le from public.commande_lignes l
        join payees c on c.id = l.commande_id
       where l.etat <> 'annulee'
    )
    select jsonb_build_object(
      'creees', (select count(*) from public.commandes c where c.cree_le >= t1 and c.cree_le < t2),
      'payees', (select count(*) from payees),
      'a_payer', (select count(*) from public.commandes c
                   where c.etat = 'a_payer' and c.cree_le >= t1 and c.cree_le < t2),
      'echouees', (select count(*) from public.commandes c
                    where c.etat in ('echouee', 'annulee') and c.cree_le >= t1 and c.cree_le < t2),
      'revendeurs', (select count(*) from payees where revendeur),
      'articles', (select coalesce(sum(quantite), 0) from lignes),
      'montant', case when argent then (select coalesce(sum(total), 0) from payees) end,
      'panier_moyen', case when argent then (select coalesce(round(avg(total)), 0) from payees) end,
      'frais_livraison', case when argent then (select coalesce(sum(frais_livraison), 0) from payees) end,
      'remises', case when argent then (select coalesce(sum(remise), 0) from payees) end,
      'benefice', case when marge then
        (select coalesce(sum(greatest(0, prix - prix_bizzoo) * quantite), 0) from lignes) end,
      'reverse_boutiques', case when marge then
        (select coalesce(sum(prix_bizzoo * quantite), 0) from lignes) end,
      'par_jour', (select coalesce(jsonb_agg(jsonb_build_object(
                      'jour', j.jour, 'payees', j.nb,
                      'montant', case when argent then j.montant end) order by j.jour), '[]')
                     from (select (paye_le at time zone 'Africa/Porto-Novo')::date as jour,
                                  count(*) as nb, sum(total) as montant
                             from payees group by 1) j),
      'boutiques', (select coalesce(jsonb_agg(jsonb_build_object(
                       'boutique', b.nom, 'commandes', x.nb, 'articles', x.qte,
                       'ventes', case when argent then x.ventes end,
                       'benefice', case when marge then x.benefice end) order by x.qte desc), '[]')
                      from (select boutique_id, count(distinct commande_id) as nb, sum(quantite) as qte,
                                   sum(prix * quantite) as ventes,
                                   sum(greatest(0, prix - prix_bizzoo) * quantite) as benefice
                              from lignes group by boutique_id
                             order by sum(quantite) desc limit 10) x
                      left join public.boutiques b on b.id = x.boutique_id),
      'produits', (select coalesce(jsonb_agg(jsonb_build_object(
                      'produit', x.nom, 'code', x.code, 'articles', x.qte,
                      'ventes', case when argent then x.ventes end) order by x.qte desc), '[]')
                     from (select max(nom) as nom, max(code) as code, sum(quantite) as qte,
                                  sum(prix * quantite) as ventes
                             from lignes group by produit_id
                            order by sum(quantite) desc limit 10) x)
    ) into commandes;
  end if;

  -- ---------- Les livraisons ----------
  if 'livraisons' = any(rubriques) then
    with lignes as (
      select l.*, c.paye_le from public.commande_lignes l
        join public.commandes c on c.id = l.commande_id
       where c.etat = 'payee' and c.paye_le >= t1 and c.paye_le < t2
    )
    select jsonb_build_object(
      'par_etat', (select coalesce(jsonb_object_agg(etat, nb), '{}')
                     from (select etat, count(*) as nb from lignes group by etat) e),
      'livrees', (select count(*) from lignes where etat = 'remise'),
      'en_cours', (select count(*) from lignes where etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')),
      'annulees', (select count(*) from lignes where etat = 'annulee'),
      -- « confirme_le » : le client a dit « je l'ai bien reçu ». (« recu_le », lui,
      -- est le moment où le LIVREUR accepte la course : ce n'est pas une réception.)
      'delai_moyen_heures', (select round(avg(extract(epoch from (confirme_le - paye_le)) / 3600)::numeric, 1)
                               from lignes where confirme_le is not null and confirme_le >= paye_le),
      'confirmees', (select count(*) from lignes where confirme_le is not null),
      'livreurs', (select coalesce(jsonb_agg(jsonb_build_object(
                      'livreur', coalesce(nullif(pr.nom, ''), pr.email, 'Livreur'),
                      'commandes', x.nb, 'livrees', x.livrees,
                      'gains', case when argent then
                        (select coalesce(sum(g.montant), 0) from public.gains_livreurs g
                          where g.livreur_id = x.livreur_id and g.credite_le >= t1 and g.credite_le < t2) end)
                      order by x.livrees desc), '[]')
                     from (select livreur_id, count(distinct commande_id) as nb,
                                  count(*) filter (where etat = 'remise') as livrees
                             from lignes where livreur_id is not null
                            group by livreur_id order by 3 desc limit 20) x
                     left join public.profils pr on pr.id = x.livreur_id)
    ) into livraisons;
  end if;

  -- ---------- Le SAV et les avis ----------
  if 'sav' = any(rubriques) then
    select jsonb_build_object(
      'reclamations', (select count(*) from public.reclamations r where r.cree_le >= t1 and r.cree_le < t2),
      'par_etat', (select coalesce(jsonb_object_agg(etat, nb), '{}')
                     from (select etat, count(*) as nb from public.reclamations r
                            where r.cree_le >= t1 and r.cree_le < t2 group by etat) e),
      'par_sujet', (select coalesce(jsonb_object_agg(sujet, nb), '{}')
                      from (select sujet, count(*) as nb from public.reclamations r
                             where r.cree_le >= t1 and r.cree_le < t2 group by sujet) s),
      'avis', (select count(*) from public.avis a where a.cree_le >= t1 and a.cree_le < t2),
      'note_moyenne', (select round(avg(note)::numeric, 2) from public.avis a
                        where a.cree_le >= t1 and a.cree_le < t2 and not a.masque),
      'notes', (select coalesce(jsonb_object_agg(note, nb), '{}')
                  from (select note, count(*) as nb from public.avis a
                         where a.cree_le >= t1 and a.cree_le < t2 and not a.masque group by note) n),
      'avis_masques', (select count(*) from public.avis a
                        where a.cree_le >= t1 and a.cree_le < t2 and a.masque)
    ) into sav;
  end if;

  -- Chacun ne reçoit que ce que ses sous-menus montrent.
  if commandes is not null then
    if not 'boutiques' = any(sous) then
      commandes := commandes - 'boutiques';
    end if;
    if not 'produits' = any(sous) then
      commandes := commandes - 'produits';
    end if;
    if not 'commandes' = any(sous) then
      commandes := jsonb_strip_nulls(jsonb_build_object(
        'boutiques', commandes -> 'boutiques', 'produits', commandes -> 'produits'));
    end if;
  end if;
  if livraisons is not null then
    if not 'livreurs' = any(sous) then
      livraisons := livraisons - 'livreurs';
    end if;
    if not 'livraisons' = any(sous) then
      livraisons := jsonb_strip_nulls(jsonb_build_object('livreurs', livraisons -> 'livreurs'));
    end if;
  end if;

  return jsonb_build_object(
    'periode', jsonb_build_object('depuis', debut, 'jusqu', fin),
    'droits', jsonb_build_object('rubriques', to_jsonb(sous), 'argent', argent, 'marge', marge),
    'commandes', commandes, 'livraisons', livraisons, 'sav', sav);
end $$;

create or replace function public.rh_suivi_acces() returns text
language sql stable security definer set search_path = public as $$
  select case
    when public.rh_est_admin() then 'admin'
    when public.rh_menu_ouvert('suivi') then 'responsable'
  end;
$$;

-- ---------- Les règles qui consultent désormais les accès ----------
drop policy if exists "rh messages lecture" on public.rh_messages;
drop policy if exists "rh messages envoi" on public.rh_messages;
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
create policy "rh missions lecture" on public.rh_missions
  for select to authenticated using (public.rh_acces(profil_id, 'missions'));

drop policy if exists "rh rapports lecture" on public.rh_rapports;
drop policy if exists "rh rapports creation" on public.rh_rapports;
drop policy if exists "rh rapports modification" on public.rh_rapports;
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

drop policy if exists "rh depenses demande" on public.rh_depenses;
create policy "rh depenses demande" on public.rh_depenses
  for insert to authenticated
  with check (public.rh_responsable_de(profil_id) and public.rh_acces(profil_id, 'depenses'));
