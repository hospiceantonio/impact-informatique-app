-- =========================================================
-- BIZZOO Personnel : la qualité du service
--
-- Un menu « Qualité » (#/qualite), en six onglets :
-- 1. SAV : les réclamations rangées en « la boutique doit répondre »,
--    « en attente du client », « à trancher par BIZZOO » ; le délai de
--    réponse de chaque boutique ; l'évolution de sa note, relevée chaque
--    jour dans rh_notes_boutiques. Alertes : réclamation sans réponse,
--    escalade non tranchée. La décision reste dans BIZZOO Admin.
-- 2. BOUTIQUES : la fiche qualité de chaque boutique, feu vert, orange ou
--    rouge : délai pour voir et préparer, annulations, réclamations,
--    ruptures, note, horaires. Les ventes : l'administration seule.
-- 3. CATALOGUE : les produits qui se vendaient et sont épuisés, les
--    réapprovisionnements dépassés, les fiches sans photo ou sans
--    catégorie, les produits masqués depuis longtemps ; « boutique
--    appelée » se coche.
-- 4. FILES : ce qui attend une décision dans Admin (demandes des
--    boutiques, revendeurs, comptes à valider, signalements).
-- 5. ZONES : le service par commune ou par quartier, sans montants.
-- 6. FIDÉLITÉ : cohortes de premier achat, réachat, clients perdus,
--    comptes supprimés ; la liste à relancer (administration seule,
--    numéros masqués).
--
-- Ouvert à l'administration, au superadministrateur, et aux profils à qui
-- Paramètres ouvre la clé « qualite » (sans aucun montant). Rien n'est
-- posé sur les tables de la place de marché : ni déclencheur, ni colonne.
--
-- À coller tel quel dans l'éditeur SQL ; il se rejoue sans dommage.
-- =========================================================

-- ---------- Les aides (copies de schema.sql) ----------
create or replace function public.rh_moi() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_mon_profil() returns uuid
language sql stable security definer set search_path = public as $$
  select profil_id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

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
    return cle in ('mails', 'discussions', 'depenses');
  end if;
  return exists (
    select 1 from public.rh_acces_menus a
      join public.rh_profils p on p.id = a.profil_id
     where a.menu = cle
       and (p.responsable_id = v_moi or (a.qui = 'membres' and p.id = v_profil)));
end $$;

create or replace function public.rh_tel_masque(t text) returns text
language sql immutable set search_path = public as $$
  select case when length(regexp_replace(coalesce(t, ''), '\D', '', 'g')) < 4 then ''
              else '•••• ' || right(regexp_replace(t, '\D', '', 'g'), 4) end;
$$;

create or replace function public.rh_cle(t text) returns text
language sql immutable set search_path = public as $$
  select btrim(regexp_replace(
           translate(lower(coalesce(t, '')),
                     'àâäáãéèêëíìîïóòôöõúùûüçñ''’-_/.,;:()',
                     'aaaaaeeeeiiiiooooouuuucn            '),
           '\s+', ' ', 'g'));
$$;

create or replace function public.rh_zone_de(adresse text) returns text
language sql stable security definer set search_path = public as $$
  select z.nom || case when z.type <> 'commune' and z.commune <> '' and z.commune <> z.nom
                       then ' (' || z.commune || ')' else '' end
    from public.rh_zones z
   where length(public.rh_cle(z.nom)) >= 3
     and position(' ' || public.rh_cle(z.nom) || ' ' in ' ' || public.rh_cle(adresse) || ' ') > 0
   order by case z.type when 'ajout' then 0 when 'quartier' then 1 when 'village' then 1
                        when 'arrondissement' then 2 else 3 end,
            length(z.nom) desc
   limit 1;
$$;

-- (fin des aides)

-- Les seuils de la qualité, avec ceux du suivi :
--   reponse_h             : une réclamation attend la boutique depuis plus de N h ;
--   decision_h            : une escalade attend BIZZOO depuis plus de N h ;
--   qualite_vue_h         : délai moyen pour VOIR une commande payée ;
--   qualite_preparation_h : délai moyen pour la PRÉPARER une fois vue ;
--   annulation_pct        : part des articles annulés ;
--   reclamation_pct       : réclamations pour 100 commandes ;
--   rupture_pct           : part des produits visibles en rupture ;
--   note_min              : note de la boutique en dessous de laquelle elle est signalée ;
--   note_chute            : baisse de la note en 30 jours qui fait un signal ;
--   populaire_min         : articles vendus en 30 jours pour qu'une rupture « coûte » ;
--   masque_j              : un produit masqué depuis plus de N jours ;
--   files_h               : par file d'attente d'Admin, l'attente qui fait rougir ;
--   zone_lent_h           : une livraison plus longue que N h est « lente » ;
--   inactif_j             : un client sans commande depuis N jours est à relancer.
alter table public.rh_reglages_suivi add column if not exists reponse_h int not null default 24
  check (reponse_h between 1 and 720);
alter table public.rh_reglages_suivi add column if not exists decision_h int not null default 48
  check (decision_h between 1 and 720);
alter table public.rh_reglages_suivi add column if not exists qualite_vue_h int not null default 4
  check (qualite_vue_h between 1 and 720);
alter table public.rh_reglages_suivi add column if not exists qualite_preparation_h int not null default 24
  check (qualite_preparation_h between 1 and 720);
alter table public.rh_reglages_suivi add column if not exists annulation_pct int not null default 10
  check (annulation_pct between 1 and 100);
alter table public.rh_reglages_suivi add column if not exists reclamation_pct int not null default 5
  check (reclamation_pct between 1 and 100);
alter table public.rh_reglages_suivi add column if not exists rupture_pct int not null default 30
  check (rupture_pct between 1 and 100);
alter table public.rh_reglages_suivi add column if not exists note_min numeric(2,1) not null default 3.5
  check (note_min between 1 and 5);
alter table public.rh_reglages_suivi add column if not exists note_chute numeric(2,1) not null default 0.3
  check (note_chute between 0.1 and 4);
alter table public.rh_reglages_suivi add column if not exists populaire_min int not null default 3
  check (populaire_min between 1 and 1000);
alter table public.rh_reglages_suivi add column if not exists masque_j int not null default 30
  check (masque_j between 1 and 365);
alter table public.rh_reglages_suivi add column if not exists files_h jsonb not null default '{}'::jsonb;
alter table public.rh_reglages_suivi add column if not exists zone_lent_h int not null default 4
  check (zone_lent_h between 1 and 720);
alter table public.rh_reglages_suivi add column if not exists inactif_j int not null default 90
  check (inactif_j between 30 and 365);

-- ---------- La note de chaque boutique, relevée chaque jour ----------
-- La base ne garde que la note du jour (boutiques.note_moyenne). Pour
-- dire « elle est passée de 4,5 à 3,8 en un mois », il faut l'avoir
-- notée : une ligne par boutique et par semaine, réécrite chaque jour de
-- la semaine (la dernière lecture de la semaine fait foi). Pas de clé
-- étrangère : la trace survit à la boutique.
create table if not exists public.rh_notes_boutiques (
  boutique_id  text not null,
  semaine      date not null,
  note         numeric(3,2),
  nb_avis      int not null default 0,
  releve_le    timestamptz not null default now(),
  primary key (boutique_id, semaine)
);
alter table public.rh_notes_boutiques enable row level security;
revoke all on table public.rh_notes_boutiques from public, anon, authenticated;
grant all on table public.rh_notes_boutiques to service_role;

-- ---------- « Boutique appelée » ----------
-- Une ligne par appel, jamais réécrite : qui a appelé la boutique au
-- sujet de quel produit, et pour quelle anomalie. Un appel vaut 7 jours :
-- passé ce délai, l'anomalie qui dure redevient « à appeler ».
create table if not exists public.rh_ruptures_suivi (
  id          bigint generated always as identity primary key,
  produit_id  text not null,
  anomalie    text not null check (anomalie in ('rupture', 'appro', 'photo', 'categorie', 'masque')),
  appele_le   timestamptz not null default now(),
  appele_par  uuid,
  note        text not null default ''
);
create index if not exists rh_ruptures_suivi_produit on public.rh_ruptures_suivi (produit_id, anomalie, appele_le desc);
alter table public.rh_ruptures_suivi enable row level security;
revoke all on table public.rh_ruptures_suivi from public, anon, authenticated;
revoke all on sequence public.rh_ruptures_suivi_id_seq from public, anon, authenticated;
grant all on table public.rh_ruptures_suivi to service_role;
grant usage, select on sequence public.rh_ruptures_suivi_id_seq to service_role;

/** Les seuils de la qualité, valeurs de départ comprises. */
create or replace function public.rh_qualite_seuils() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'reponse_h', coalesce((x.j ->> 'reponse_h')::int, 24),
    'decision_h', coalesce((x.j ->> 'decision_h')::int, 48),
    'qualite_vue_h', coalesce((x.j ->> 'qualite_vue_h')::int, 4),
    'qualite_preparation_h', coalesce((x.j ->> 'qualite_preparation_h')::int, 24),
    'annulation_pct', coalesce((x.j ->> 'annulation_pct')::int, 10),
    'reclamation_pct', coalesce((x.j ->> 'reclamation_pct')::int, 5),
    'rupture_pct', coalesce((x.j ->> 'rupture_pct')::int, 30),
    'note_min', coalesce((x.j ->> 'note_min')::numeric, 3.5),
    'note_chute', coalesce((x.j ->> 'note_chute')::numeric, 0.3),
    'populaire_min', coalesce((x.j ->> 'populaire_min')::int, 3),
    'masque_j', coalesce((x.j ->> 'masque_j')::int, 30),
    'files_h', jsonb_build_object(
      'demandes', coalesce((x.j #>> '{files_h,demandes}')::int, 48),
      'revendeurs', coalesce((x.j #>> '{files_h,revendeurs}')::int, 48),
      'comptes', coalesce((x.j #>> '{files_h,comptes}')::int, 48),
      'avis', coalesce((x.j #>> '{files_h,avis}')::int, 48),
      'produits', coalesce((x.j #>> '{files_h,produits}')::int, 48)),
    'zone_lent_h', coalesce((x.j ->> 'zone_lent_h')::int, 4),
    'inactif_j', coalesce((x.j ->> 'inactif_j')::int, 90))
    from (select coalesce((select to_jsonb(r) from public.rh_reglages_suivi r where r.id), '{}'::jsonb) as j) x;
$$;

/**
 * Ce que le menu Qualité ouvre au compte connecté : « admin » (montants,
 * ventes, noms des clients, liste à relancer, seuils : l'administration,
 * le CEO, le superadministrateur), « equipe » (la clé « qualite » de
 * Paramètres : délais, nombres et taux, aucun montant), ou rien.
 */
create or replace function public.rh_qualite_acces() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'acces', case when public.rh_est_admin() or public.est_super() then 'admin'
                  when public.rh_menu_ouvert('qualite') then 'equipe' end,
    'montants', public.rh_est_admin() or public.est_super());
$$;

/** Régler les seuils de la qualité : l'administration et le superadministrateur. */
create or replace function public.rh_qualite_regler(choix jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  k text;
  v jsonb;
  f text;
  n numeric;
  bornes jsonb := jsonb_build_object(
    'reponse_h', '[1, 720]'::jsonb, 'decision_h', '[1, 720]'::jsonb, 'qualite_vue_h', '[1, 720]'::jsonb,
    'qualite_preparation_h', '[1, 720]'::jsonb, 'annulation_pct', '[1, 100]'::jsonb,
    'reclamation_pct', '[1, 100]'::jsonb, 'rupture_pct', '[1, 100]'::jsonb, 'note_min', '[1, 5]'::jsonb,
    'note_chute', '[0.1, 4]'::jsonb, 'populaire_min', '[1, 1000]'::jsonb, 'masque_j', '[1, 365]'::jsonb,
    'zone_lent_h', '[1, 720]'::jsonb, 'inactif_j', '[30, 365]'::jsonb);
begin
  if not (public.rh_est_admin() or public.est_super()) then
    raise exception 'Seuls l''administration et le superadministrateur règlent les seuils de la qualité';
  end if;
  if jsonb_typeof(choix) is distinct from 'object' then
    raise exception 'Réglage illisible';
  end if;
  for k, v in select e.key, e.value from jsonb_each(choix) as e loop
    if k = 'files_h' then
      if jsonb_typeof(v) is distinct from 'object' then
        raise exception 'Les seuils des files se donnent file par file';
      end if;
      for f in select jsonb_object_keys(v) loop
        if f not in ('demandes', 'revendeurs', 'comptes', 'avis', 'produits') then
          raise exception 'File inconnue : %', f;
        end if;
        if jsonb_typeof(v -> f) is distinct from 'number' or (v ->> f)::numeric <> trunc((v ->> f)::numeric)
           or (v ->> f)::numeric not between 1 and 720 then
          raise exception 'L''attente d''une file se compte en heures, de 1 à 720';
        end if;
      end loop;
      update public.rh_reglages_suivi set files_h = files_h || v where id;
    elsif bornes ? k then
      if jsonb_typeof(v) is distinct from 'number' then
        raise exception 'Le seuil % doit être un nombre', k;
      end if;
      n := (v #>> '{}')::numeric;
      if n < (bornes #>> array[k, '0'])::numeric or n > (bornes #>> array[k, '1'])::numeric then
        raise exception 'Le seuil % va de % à %', k, bornes #>> array[k, '0'], bornes #>> array[k, '1'];
      end if;
      if k not in ('note_min', 'note_chute') and n <> trunc(n) then
        raise exception 'Le seuil % est un nombre entier', k;
      end if;
      execute format('update public.rh_reglages_suivi set %I = %L where id', k, n);
    else
      raise exception 'Seuil inconnu : %', k;
    end if;
  end loop;
end $$;

/**
 * Relève la note de chaque boutique notée : la ligne de la semaine en
 * cours est réécrite (la dernière lecture de la semaine fait foi).
 * pg_cron l'appelle chaque matin ; l'écran Qualité aussi, à l'ouverture,
 * si pg_cron n'est pas là. Sans compte connecté (pg_cron), ou pour qui a
 * le menu Qualité.
 */
create or replace function public.rh_notes_releve() returns int
language plpgsql security definer set search_path = public as $$
declare
  n int;
  semaine_courante date := date_trunc('week', now() at time zone 'Africa/Porto-Novo')::date;
begin
  if auth.uid() is not null and (public.rh_qualite_acces() ->> 'acces') is null then
    raise exception 'Votre compte n''a pas accès au menu Qualité';
  end if;
  insert into public.rh_notes_boutiques (boutique_id, semaine, note, nb_avis, releve_le)
  select b.id, semaine_courante, b.note_moyenne, b.nb_avis, now()
    from public.boutiques b
   where b.nb_avis > 0
  on conflict (boutique_id, semaine) do update
    set note = excluded.note, nb_avis = excluded.nb_avis, releve_le = excluded.releve_le;
  get diagnostics n = row_count;
  return n;
end $$;

/**
 * La note d'une boutique à un instant : le relevé le plus proche dans les
 * 7 jours qui précèdent (« releve »), sinon la moyenne des avis de la
 * boutique écrits avant cet instant et toujours visibles (« reconstituee » :
 * un avis masqué depuis compte comme s'il l'avait toujours été).
 */
create or replace function public.rh_note_boutique_au(cible text, instant timestamptz) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select jsonb_build_object('note', n.note, 'source', 'releve')
       from public.rh_notes_boutiques n
      where n.boutique_id = cible and n.releve_le <= instant and n.releve_le > instant - interval '7 days'
      order by n.releve_le desc limit 1),
    (select jsonb_build_object('note', round(avg(a.note), 2), 'source', 'reconstituee')
       from public.avis a
      where a.boutique_id = cible and a.produit_id is null and not a.masque and a.cree_le < instant
     having count(*) > 0),
    jsonb_build_object('note', null, 'source', 'aucune'));
$$;

/**
 * Les réclamations encore ouvertes, rangées : « boutique » (elle doit
 * répondre : jamais répondu, ou le client a réécrit après sa réponse),
 * « client » (la boutique a répondu, le client lit), « bizzoo » (escaladée,
 * à trancher). « depuis_le » : depuis quand on attend celui qui doit agir.
 * Interne : les fonctions publiques vérifient d'abord qui appelle.
 */
create or replace function public.rh_sav_ouvertes()
returns table (reclamation_id text, colonne text, depuis_le timestamptz)
language sql stable security definer set search_path = public as $$
  with o as (
    select r.id, r.etat, r.cree_le, r.repondu_le, r.escalade_le, r.maj_le,
           (select m.auteur_role from public.reclamation_messages m where m.reclamation_id = r.id
             order by m.cree_le desc, m.id desc limit 1) as dernier_role,
           (select max(m.cree_le) from public.reclamation_messages m
             where m.reclamation_id = r.id and m.auteur_role = 'client') as dernier_client,
           (select max(m.cree_le) from public.reclamation_messages m
             where m.reclamation_id = r.id and m.auteur_role <> 'client') as derniere_reponse
      from public.reclamations r
     where r.etat in ('ouverte', 'repondue', 'escaladee')
  ),
  c as (
    select o.*, case
      when o.etat = 'escaladee' then 'bizzoo'
      when o.etat = 'ouverte' then 'boutique'
      when o.dernier_role = 'client'
           and o.dernier_client > coalesce(o.derniere_reponse, o.repondu_le, o.cree_le) then 'boutique'
      else 'client' end as col
      from o
  )
  select c.id, c.col, case c.col
      when 'bizzoo' then coalesce(c.escalade_le, c.maj_le)
      when 'boutique' then case when c.etat = 'ouverte' then c.cree_le else c.dernier_client end
      else coalesce(c.derniere_reponse, c.repondu_le, c.maj_le) end
    from c;
$$;

/**
 * Le SAV et la satisfaction sur une période (30 jours par défaut, heure du
 * Bénin) : les réclamations ouvertes en trois colonnes, quelle que soit la
 * période ; par boutique, les réclamations de la période, le délai de
 * réponse, et l'évolution de la note sur 30 jours (8 semaines en courbe).
 * Le nom du client et le motif d'une escalade : l'administration seule.
 */
create or replace function public.rh_satisfaction(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  a jsonb := public.rh_qualite_acces();
  admin boolean := (a ->> 'acces') = 'admin';
  s jsonb := public.rh_qualite_seuils();
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  fin date := coalesce(jusqu, aujourdhui);
  debut date := coalesce(depuis, coalesce(jusqu, aujourdhui) - 29);
  t1 timestamptz;
  t2 timestamptz;
  rep_h int := (s ->> 'reponse_h')::int;
  dec_h int := (s ->> 'decision_h')::int;
  chute numeric := (s ->> 'note_chute')::numeric;
  liste_r jsonb;
  totaux jsonb;
  par_boutique jsonb;
begin
  if a ->> 'acces' is null then
    raise exception 'Votre compte n''a pas accès au menu Qualité';
  end if;
  if fin < debut then
    raise exception 'La fin de la période précède son début';
  end if;
  if fin - debut > 400 then
    raise exception 'Choisissez une période d''un an au plus';
  end if;
  t1 := debut::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (fin + 1)::timestamp at time zone 'Africa/Porto-Novo';

  with o as (
    select x.*, r.sujet, r.etat, r.cree_le, r.boutique_id, r.escalade_motif, c.numero, c.client_nom,
           b.nom as boutique_nom,
           round((extract(epoch from (now() - x.depuis_le)) / 3600)::numeric, 1) as heures
      from public.rh_sav_ouvertes() x
      join public.reclamations r on r.id = x.reclamation_id
      left join public.commandes c on c.id = r.commande_id
      left join public.boutiques b on b.id = r.boutique_id
  ),
  o2 as (
    select o.*, case
      when o.colonne = 'boutique' and o.heures > rep_h then 'sans_reponse'
      when o.colonne = 'bizzoo' and o.heures > dec_h then 'escalade_en_attente' end as alerte
      from o
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', o2.reclamation_id, 'commande', o2.numero, 'boutique_id', o2.boutique_id,
           'boutique', coalesce(o2.boutique_nom, o2.boutique_id), 'sujet', o2.sujet, 'etat', o2.etat,
           'colonne', o2.colonne, 'cree_le', o2.cree_le, 'depuis_le', o2.depuis_le, 'heures', o2.heures,
           'alerte', o2.alerte,
           'client', case when admin then o2.client_nom end,
           'motif', case when admin and o2.colonne = 'bizzoo' then left(o2.escalade_motif, 300) end)
           order by (o2.alerte is not null) desc, o2.depuis_le), '[]'),
         jsonb_build_object(
           'boutique', count(*) filter (where o2.colonne = 'boutique'),
           'client', count(*) filter (where o2.colonne = 'client'),
           'bizzoo', count(*) filter (where o2.colonne = 'bizzoo'),
           'sans_reponse', count(*) filter (where o2.alerte = 'sans_reponse'),
           'escalades_en_retard', count(*) filter (where o2.alerte = 'escalade_en_attente'))
    into liste_r, totaux
    from o2;

  totaux := totaux || (
    select jsonb_build_object(
      'creees', count(*),
      'repondues', count(*) filter (where r.repondu_le is not null),
      'delai_reponse_h', round((avg(extract(epoch from (r.repondu_le - r.cree_le)) / 3600)
                               filter (where r.repondu_le is not null))::numeric, 1),
      'escaladees', count(*) filter (where r.escalade_le is not null))
      from public.reclamations r where r.cree_le >= t1 and r.cree_le < t2)
    || (select jsonb_build_object(
      'tranchees', count(*),
      'delai_decision_h', round(avg(extract(epoch from (r.decide_le - r.escalade_le)) / 3600)::numeric, 1))
      from public.reclamations r
     where r.decide_le >= t1 and r.decide_le < t2 and r.escalade_le is not null);

  with periode as (
    select r.boutique_id, count(*) as nb,
           count(*) filter (where r.repondu_le is not null) as repondues,
           round((avg(extract(epoch from (r.repondu_le - r.cree_le)) / 3600)
                 filter (where r.repondu_le is not null))::numeric, 1) as delai_h,
           round((max(extract(epoch from (r.repondu_le - r.cree_le)) / 3600)
                 filter (where r.repondu_le is not null))::numeric, 1) as delai_max_h,
           count(*) filter (where r.escalade_le is not null) as escaladees
      from public.reclamations r where r.cree_le >= t1 and r.cree_le < t2
     group by r.boutique_id
  ),
  attente as (
    select r.boutique_id, count(*) as nb
      from public.rh_sav_ouvertes() x
      join public.reclamations r on r.id = x.reclamation_id
     where x.colonne = 'boutique' and now() - x.depuis_le > make_interval(hours => rep_h)
     group by r.boutique_id
  ),
  bq as (
    select b.id, b.nom, b.nb_avis,
           case when fin >= aujourdhui then jsonb_build_object('note', b.note_moyenne, 'source', 'du_jour')
                else public.rh_note_boutique_au(b.id, t2) end as note_fin,
           public.rh_note_boutique_au(b.id, t2 - interval '30 days') as note_avant,
           p.nb, p.repondues, p.delai_h, p.delai_max_h, p.escaladees, coalesce(att.nb, 0) as sans_reponse
      from public.boutiques b
      left join periode p on p.boutique_id = b.id
      left join attente att on att.boutique_id = b.id
     where p.boutique_id is not null or att.boutique_id is not null or b.nb_avis > 0
  ),
  bq2 as (
    select bq.*, (bq.note_fin ->> 'note')::numeric - (bq.note_avant ->> 'note')::numeric as variation
      from bq
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', bq2.id, 'boutique', bq2.nom, 'reclamations', coalesce(bq2.nb, 0),
           'repondues', coalesce(bq2.repondues, 0), 'delai_reponse_h', bq2.delai_h,
           'delai_reponse_max_h', bq2.delai_max_h, 'escaladees', coalesce(bq2.escaladees, 0),
           'sans_reponse', bq2.sans_reponse, 'nb_avis', bq2.nb_avis,
           'note', bq2.note_fin -> 'note', 'note_avant', bq2.note_avant -> 'note',
           'source_avant', bq2.note_avant ->> 'source', 'variation', bq2.variation,
           'chute', coalesce(bq2.variation <= -chute, false),
           'semaines', case when bq2.nb_avis > 0 then (
              select jsonb_agg(jsonb_build_object('jusqu', (fin - k * 7),
                       'note', public.rh_note_boutique_au(bq2.id, t2 - make_interval(days => k * 7)) -> 'note')
                       order by k desc)
                from generate_series(0, 7) k) else '[]'::jsonb end)
           order by coalesce(bq2.variation <= -chute, false) desc, bq2.sans_reponse desc,
                    coalesce(bq2.nb, 0) desc, bq2.nom), '[]')
    into par_boutique
    from bq2;

  return jsonb_build_object(
    'periode', jsonb_build_object('depuis', debut, 'jusqu', fin),
    'montants', admin,
    'seuils', jsonb_build_object('reponse_h', rep_h, 'decision_h', dec_h, 'note_chute', chute),
    'totaux', totaux,
    'reclamations', liste_r,
    'boutiques', par_boutique);
end $$;

/**
 * La fiche qualité de chaque boutique sur une période : comment elle sert
 * ses clients. Les commandes comptent au jour de leur paiement (même
 * annulées ensuite : c'est l'annulation qu'on mesure).
 *   delai_vue_h         : du paiement au « vu » de la boutique ;
 *   delai_preparation_h : du « vu » au « préparé » ;
 *   non_vues            : articles payés jamais vus depuis plus du seuil ;
 *   annulation_pct      : articles annulés sur articles payés ;
 *   reclamation_pct     : réclamations ouvertes sur la période pour 100 commandes ;
 *   rupture_pct         : produits visibles épuisés (hors « sur commande »), aujourd'hui ;
 *   note, horaires      : aujourd'hui.
 * Feu : rouge à deux signaux ou plus, orange à un, vert sinon. Les ventes
 * (prix payés par les clients, jamais le prix BIZZOO) : l'administration seule.
 */
create or replace function public.rh_qualite_boutiques(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  a jsonb := public.rh_qualite_acces();
  admin boolean := (a ->> 'acces') = 'admin';
  s jsonb := public.rh_qualite_seuils();
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  fin date := coalesce(jusqu, aujourdhui);
  debut date := coalesce(depuis, coalesce(jusqu, aujourdhui) - 29);
  t1 timestamptz;
  t2 timestamptz;
  liste jsonb;
begin
  if a ->> 'acces' is null then
    raise exception 'Votre compte n''a pas accès au menu Qualité';
  end if;
  if fin < debut then
    raise exception 'La fin de la période précède son début';
  end if;
  if fin - debut > 400 then
    raise exception 'Choisissez une période d''un an au plus';
  end if;
  t1 := debut::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (fin + 1)::timestamp at time zone 'Africa/Porto-Novo';

  with lig as (
    select l.id, l.boutique_id, l.commande_id, l.etat, l.quantite, l.prix, c.paye_le,
           (select min(j.le) from public.rh_journal_lignes j
             where j.ligne_id = l.id and j.quoi = 'etat' and j.valeur = 'vue') as vue_le,
           (select min(j.le) from public.rh_journal_lignes j
             where j.ligne_id = l.id and j.quoi = 'etat' and j.valeur = 'preparee') as preparee_le
      from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
     where c.paye_le >= t1 and c.paye_le < t2 and l.boutique_id is not null
  ),
  parl as (
    select g.boutique_id,
           count(distinct g.commande_id) as commandes,
           count(*) as lignes,
           sum(g.prix * g.quantite) filter (where g.etat <> 'annulee') as ventes,
           round((avg(extract(epoch from (coalesce(g.vue_le, g.preparee_le) - g.paye_le)) / 3600)
                 filter (where coalesce(g.vue_le, g.preparee_le) >= g.paye_le))::numeric, 1) as delai_vue_h,
           round((avg(extract(epoch from (g.preparee_le - coalesce(g.vue_le, g.paye_le))) / 3600)
                 filter (where g.preparee_le >= coalesce(g.vue_le, g.paye_le)))::numeric, 1) as delai_preparation_h,
           count(*) filter (where g.etat = 'nouvelle'
                              and now() - g.paye_le > make_interval(hours => (s ->> 'qualite_vue_h')::int)) as non_vues,
           count(*) filter (where g.etat = 'annulee') as annulees
      from lig g group by g.boutique_id
  ),
  recl as (
    select r.boutique_id, count(*) as nb from public.reclamations r
     where r.cree_le >= t1 and r.cree_le < t2 group by r.boutique_id
  ),
  prod as (
    select p.boutique_id, count(*) filter (where not p.masque) as visibles,
           count(*) filter (where not p.masque and p.stock <= 0 and not p.sur_commande) as ruptures
      from public.produits p where p.boutique_id is not null group by p.boutique_id
  ),
  bq as (
    select b.id, b.nom, b.actif, b.note_moyenne, b.nb_avis, b.ouvertures is not null as horaires,
           coalesce(pl.commandes, 0) as commandes, coalesce(pl.lignes, 0) as lignes, pl.ventes,
           pl.delai_vue_h, pl.delai_preparation_h, coalesce(pl.non_vues, 0) as non_vues,
           coalesce(pl.annulees, 0) as annulees,
           case when coalesce(pl.lignes, 0) > 0 then round(100.0 * pl.annulees / pl.lignes, 1) end as annulation_pct,
           coalesce(rc.nb, 0) as reclamations,
           case when coalesce(pl.commandes, 0) > 0 then round(100.0 * coalesce(rc.nb, 0) / pl.commandes, 1) end as reclamation_pct,
           coalesce(pr.visibles, 0) as produits, coalesce(pr.ruptures, 0) as ruptures,
           case when coalesce(pr.visibles, 0) > 0 then round(100.0 * pr.ruptures / pr.visibles, 1) end as rupture_pct
      from public.boutiques b
      left join parl pl on pl.boutique_id = b.id
      left join recl rc on rc.boutique_id = b.id
      left join prod pr on pr.boutique_id = b.id
     where b.actif or pl.boutique_id is not null
  ),
  bq2 as (
    select bq.*, array_remove(array[
      case when bq.delai_vue_h > (s ->> 'qualite_vue_h')::numeric then 'vue_lente' end,
      case when bq.non_vues > 0 then 'non_vues' end,
      case when bq.delai_preparation_h > (s ->> 'qualite_preparation_h')::numeric then 'preparation_lente' end,
      case when bq.annulation_pct > (s ->> 'annulation_pct')::numeric then 'annulations' end,
      case when bq.reclamation_pct > (s ->> 'reclamation_pct')::numeric then 'reclamations' end,
      case when bq.rupture_pct > (s ->> 'rupture_pct')::numeric then 'ruptures' end,
      case when bq.note_moyenne < (s ->> 'note_min')::numeric then 'note' end,
      case when not bq.horaires then 'horaires' end], null) as problemes
      from bq
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', x.id, 'boutique', x.nom, 'actif', x.actif, 'commandes', x.commandes, 'lignes', x.lignes,
           'ventes', case when admin then coalesce(x.ventes, 0) end,
           'delai_vue_h', x.delai_vue_h, 'delai_preparation_h', x.delai_preparation_h, 'non_vues', x.non_vues,
           'annulees', x.annulees, 'annulation_pct', x.annulation_pct,
           'reclamations', x.reclamations, 'reclamation_pct', x.reclamation_pct,
           'produits', x.produits, 'ruptures', x.ruptures, 'rupture_pct', x.rupture_pct,
           'note', x.note_moyenne, 'nb_avis', x.nb_avis, 'horaires', x.horaires,
           'problemes', to_jsonb(x.problemes),
           'feu', case when cardinality(x.problemes) >= 2 then 'rouge'
                       when cardinality(x.problemes) = 1 then 'orange' else 'vert' end)
           order by cardinality(x.problemes) desc, x.lignes desc, x.nom), '[]')
    into liste
    from bq2 x;

  return jsonb_build_object(
    'periode', jsonb_build_object('depuis', debut, 'jusqu', fin),
    'montants', admin,
    'seuils', s - 'files_h' - 'zone_lent_h' - 'inactif_j' - 'masque_j' - 'populaire_min',
    'boutiques', liste);
end $$;

/**
 * Les produits qui se vendaient (au moins « populaire_min » articles payés
 * en 30 jours, articles annulés exclus), avec leur rang parmi les ventes
 * des 30 derniers jours. Interne.
 */
create or replace function public.rh_ventes_30j()
returns table (produit_id text, qte bigint, rang bigint, derniere timestamptz)
language sql stable security definer set search_path = public as $$
  select v.produit_id, v.qte, rank() over (order by v.qte desc), v.derniere
    from (select l.produit_id, sum(l.quantite)::bigint as qte, max(c.paye_le) as derniere
            from public.commande_lignes l
            join public.commandes c on c.id = l.commande_id
           where c.paye_le >= now() - interval '30 days' and l.etat <> 'annulee' and l.produit_id is not null
           group by l.produit_id) v;
$$;

/**
 * La santé du catalogue, aujourd'hui. Aucun prix : ni celui du client,
 * ni celui d'achat.
 *   ruptures       : épuisés (stock 0, pas « sur commande », visibles) qui
 *                    se vendaient ; les mieux vendus en tête ;
 *   appro_depasse  : épuisés dont la date de réapprovisionnement est passée ;
 *   sans_photo, sans_categorie : fiches incomplètes, visibles ;
 *   masques       : masqués depuis plus de « masque_j » jours (ou depuis
 *                    une date inconnue : masqués avant 3.59.0).
 * Chaque produit porte le dernier appel « boutique appelée » de moins de 7 jours.
 */
create or replace function public.rh_catalogue_anomalies() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  a jsonb := public.rh_qualite_acces();
  s jsonb := public.rh_qualite_seuils();
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  pop int := (s ->> 'populaire_min')::int;
  masque_jours int := (s ->> 'masque_j')::int;
  res jsonb;
begin
  if a ->> 'acces' is null then
    raise exception 'Votre compte n''a pas accès au menu Qualité';
  end if;
  with v as (select * from public.rh_ventes_30j()),
  appels as (
    select distinct on (x.produit_id, x.anomalie) x.produit_id, x.anomalie, x.appele_le, x.note,
           coalesce((select nullif(btrim(coalesce(e.prenoms, '') || ' ' || coalesce(e.nom, '')), '')
                       from public.rh_employes e where e.id = x.appele_par), '') as par
      from public.rh_ruptures_suivi x
     where x.appele_le > now() - interval '7 days'
     order by x.produit_id, x.anomalie, x.appele_le desc
  ),
  p as (
    select pr.id, pr.nom, pr.code, pr.boutique_id, b.nom as boutique, pr.stock, pr.sur_commande, pr.appro_le,
           pr.masque, pr.masque_le, pr.masque_par, cardinality(pr.images) = 0 as sans_photo,
           pr.categorie_id is null and pr.sous_categorie_id is null as sans_categorie,
           v.qte, v.rang, v.derniere
      from public.produits pr
      left join public.boutiques b on b.id = pr.boutique_id
      left join v on v.produit_id = pr.id
  ),
  fiche as (
    select p.*, jsonb_build_object('id', p.id, 'produit', p.nom, 'code', p.code, 'boutique_id', p.boutique_id,
                                   'boutique', coalesce(p.boutique, p.boutique_id)) as base
      from p
  ),
  appel_de as (
    select f.id, an.anomalie,
           (select jsonb_build_object('le', ap.appele_le, 'par', ap.par, 'note', ap.note)
              from appels ap where ap.produit_id = f.id and ap.anomalie = an.anomalie) as appel
      from fiche f cross join (values ('rupture'), ('appro'), ('photo'), ('categorie'), ('masque')) an(anomalie)
  )
  select jsonb_build_object(
    'seuils', jsonb_build_object('populaire_min', pop, 'masque_j', masque_jours),
    'ruptures', coalesce((select jsonb_agg(f.base || jsonb_build_object(
                   'vendus_30j', f.qte, 'rang', f.rang, 'derniere_vente', f.derniere, 'appro_le', f.appro_le,
                   'retard_j', case when f.appro_le < aujourdhui then aujourdhui - f.appro_le end,
                   'appel', ad.appel) order by f.qte desc, f.rang)
                   from fiche f join appel_de ad on ad.id = f.id and ad.anomalie = 'rupture'
                  where not f.masque and f.stock <= 0 and not f.sur_commande and f.qte >= pop), '[]'),
    'appro_depasse', coalesce((select jsonb_agg(f.base || jsonb_build_object(
                   'appro_le', f.appro_le, 'retard_j', aujourdhui - f.appro_le, 'vendus_30j', coalesce(f.qte, 0),
                   'appel', ad.appel) order by f.appro_le)
                   from fiche f join appel_de ad on ad.id = f.id and ad.anomalie = 'appro'
                  where not f.masque and f.stock <= 0 and not f.sur_commande and f.appro_le < aujourdhui), '[]'),
    'sans_photo', coalesce((select jsonb_agg(f.base || jsonb_build_object('appel', ad.appel) order by f.boutique, f.nom)
                   from (select * from fiche f0 where not f0.masque and f0.sans_photo order by f0.boutique, f0.nom limit 300) f
                   join appel_de ad on ad.id = f.id and ad.anomalie = 'photo'), '[]'),
    'sans_categorie', coalesce((select jsonb_agg(f.base || jsonb_build_object('appel', ad.appel) order by f.boutique, f.nom)
                   from (select * from fiche f0 where not f0.masque and f0.sans_categorie order by f0.boutique, f0.nom limit 300) f
                   join appel_de ad on ad.id = f.id and ad.anomalie = 'categorie'), '[]'),
    'masques', coalesce((select jsonb_agg(f.base || jsonb_build_object(
                   'masque_le', f.masque_le, 'masque_par', f.masque_par,
                   'jours', case when f.masque_le is not null then aujourdhui - (f.masque_le at time zone 'Africa/Porto-Novo')::date end,
                   'appel', ad.appel) order by f.masque_le nulls first)
                   from (select * from fiche f0 where f0.masque
                            and (f0.masque_le is null or f0.masque_le < now() - make_interval(days => masque_jours))
                          order by f0.masque_le nulls first limit 300) f
                   join appel_de ad on ad.id = f.id and ad.anomalie = 'masque'), '[]'),
    'totaux', (select jsonb_build_object(
                 'ruptures', count(*) filter (where not f.masque and f.stock <= 0 and not f.sur_commande and f.qte >= pop),
                 'ruptures_a_appeler', count(*) filter (where not f.masque and f.stock <= 0 and not f.sur_commande and f.qte >= pop
                                                          and not exists (select 1 from appels ap where ap.produit_id = f.id and ap.anomalie = 'rupture')),
                 'epuises', count(*) filter (where not f.masque and f.stock <= 0 and not f.sur_commande),
                 'appro_depasse', count(*) filter (where not f.masque and f.stock <= 0 and not f.sur_commande and f.appro_le < aujourdhui),
                 'sans_photo', count(*) filter (where not f.masque and f.sans_photo),
                 'sans_categorie', count(*) filter (where not f.masque and f.sans_categorie),
                 'masques', count(*) filter (where f.masque and (f.masque_le is null
                                                or f.masque_le < now() - make_interval(days => masque_jours))))
                 from fiche f))
    into res;
  return res;
end $$;

/**
 * « Boutique appelée » : cocher (appele = true) note l'appel ; décocher
 * retire les appels de moins de 7 jours de ce produit pour cette anomalie.
 * Pour qui a le menu Qualité, montants ou pas : un appel n'en a pas.
 */
create or replace function public.rh_catalogue_appeler(cible_produit text, cible_anomalie text, appele boolean,
                                                       v_note text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if (public.rh_qualite_acces() ->> 'acces') is null then
    raise exception 'Votre compte n''a pas accès au menu Qualité';
  end if;
  if coalesce(cible_anomalie, '') not in ('rupture', 'appro', 'photo', 'categorie', 'masque') then
    raise exception 'Anomalie inconnue';
  end if;
  if not exists (select 1 from public.produits where id = cible_produit) then
    raise exception 'Produit introuvable';
  end if;
  if coalesce(appele, false) then
    insert into public.rh_ruptures_suivi (produit_id, anomalie, appele_par, note)
    values (cible_produit, cible_anomalie, public.rh_moi(), left(btrim(coalesce(v_note, '')), 300));
  else
    delete from public.rh_ruptures_suivi
     where produit_id = cible_produit and anomalie = cible_anomalie and appele_le > now() - interval '7 days';
  end if;
end $$;

/**
 * Les files qui attendent une décision dans BIZZOO Admin : une ligne par
 * file, combien, la plus ancienne, l'attente moyenne, et le délai moyen
 * des décisions des 30 derniers jours (quand la base le date). Rouge
 * quand la plus ancienne dépasse le seuil de sa file. Aucun nom, aucun
 * numéro : des nombres et des dates.
 */
create or replace function public.rh_files_attente() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  a jsonb := public.rh_qualite_acces();
  f jsonb := public.rh_qualite_seuils() -> 'files_h';
  res jsonb;
begin
  if a ->> 'acces' is null then
    raise exception 'Votre compte n''a pas accès au menu Qualité';
  end if;
  with attente as (
    select 'demandes' as cle, d.demande_le as le from public.demandes d where d.etat = 'en_attente'
    union all
    select 'revendeurs', coalesce(c.revendeur_demande_le, c.maj_le) from public.clients c where c.revendeur_etat = 'en_attente'
    union all
    select 'comptes', p.cree_le from public.profils p where p.a_valider
    union all
    select 'avis', s.cree_le from public.avis_signalements s where s.etat = 'ouvert'
    union all
    select 'produits', s.cree_le from public.produits_signalements s where s.etat = 'ouvert'
  ),
  decisions as (
    select 'demandes' as cle, extract(epoch from (d.decide_le - d.demande_le)) / 3600 as h
      from public.demandes d where d.decide_le > now() - interval '30 days'
    union all
    select 'revendeurs', extract(epoch from (c.revendeur_decide_le - c.revendeur_demande_le)) / 3600
      from public.clients c where c.revendeur_decide_le > now() - interval '30 days' and c.revendeur_demande_le is not null
    union all
    select 'avis', extract(epoch from (s.traite_le - s.cree_le)) / 3600
      from public.avis_signalements s where s.traite_le > now() - interval '30 days'
    union all
    select 'produits', extract(epoch from (s.traite_le - s.cree_le)) / 3600
      from public.produits_signalements s where s.traite_le > now() - interval '30 days'
  ),
  files(cle, libelle, ecran, route, ordre) as (
    values ('demandes', 'Demandes des boutiques (réglages, slider)', 'Validations', 'validations', 1),
           ('revendeurs', 'Demandes de compte revendeur', 'Revendeurs', 'revendeurs', 2),
           ('comptes', 'Comptes d''équipe à valider', 'Comptes', 'comptes', 3),
           ('avis', 'Avis signalés (harcèlement, haine…)', 'Avis', 'avis', 4),
           ('produits', 'Produits signalés (contrefaçon, trompeur…)', 'Avis', 'avis', 5)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'cle', x.cle, 'libelle', x.libelle, 'ecran', x.ecran, 'route', x.route,
           'nombre', x.nombre, 'plus_ancienne', x.plus_ancienne,
           'attente_moyenne_h', x.attente_h, 'delai_decision_h', x.delai_h,
           'seuil_h', x.seuil_h, 'en_retard', x.en_retard,
           'rouge', x.plus_ancienne is not null and x.plus_ancienne < now() - make_interval(hours => x.seuil_h))
           order by x.ordre), '[]')
    into res
    from (select fl.cle, fl.libelle, fl.ecran, fl.route, fl.ordre, (f ->> fl.cle)::int as seuil_h,
                 (select count(*) from attente w where w.cle = fl.cle) as nombre,
                 (select min(w.le) from attente w where w.cle = fl.cle) as plus_ancienne,
                 (select round(avg(extract(epoch from (now() - w.le)) / 3600)::numeric, 1)
                    from attente w where w.cle = fl.cle) as attente_h,
                 (select count(*) from attente w where w.cle = fl.cle
                     and w.le < now() - make_interval(hours => (f ->> fl.cle)::int)) as en_retard,
                 (select round(avg(dc.h)::numeric, 1) from decisions dc where dc.cle = fl.cle) as delai_h
            from files fl) x;
  return jsonb_build_object('files', res, 'seuils', f);
end $$;

/**
 * Le service par zone sur une période : les commandes payées, rangées par
 * commune (niveau « commune ») ou par quartier (« quartier »), selon la
 * zone du suivi (corrigée par l'administration, sinon lue dans l'adresse).
 * Aucun montant : des nombres, des délais, des distances.
 *   delai_moyen_h : du paiement à la livraison (réception confirmée par le
 *                   client, sinon remise déclarée), commandes entièrement livrées ;
 *   lentes        : livrées en plus de « zone_lent_h » heures ;
 *   echecs        : un article noté échoué, en retour ou retourné ;
 *   non_recus     : une réclamation « non reçu » ;
 *   distance, tricycle : la livraison au kilomètre (3.64.0), quand elle est connue.
 */
create or replace function public.rh_statistiques_zones(depuis date default null, jusqu date default null,
                                                         niveau text default 'commune')
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  a jsonb := public.rh_qualite_acces();
  lent int := (public.rh_qualite_seuils() ->> 'zone_lent_h')::int;
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  fin date := coalesce(jusqu, aujourdhui);
  debut date := coalesce(depuis, coalesce(jusqu, aujourdhui) - 29);
  t1 timestamptz;
  t2 timestamptz;
  zones jsonb;
begin
  if a ->> 'acces' is null then
    raise exception 'Votre compte n''a pas accès au menu Qualité';
  end if;
  if coalesce(niveau, '') not in ('commune', 'quartier') then
    raise exception 'Niveau inconnu : commune ou quartier';
  end if;
  if fin < debut then
    raise exception 'La fin de la période précède son début';
  end if;
  if fin - debut > 400 then
    raise exception 'Choisissez une période d''un an au plus';
  end if;
  t1 := debut::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (fin + 1)::timestamp at time zone 'Africa/Porto-Novo';

  with cmd as (
    select c.id, c.paye_le, c.livraison,
           coalesce(nullif(sc.zone, ''), public.rh_zone_de(c.client_adresse), '') as zone_brute
      from public.commandes c
      left join public.rh_suivi_commandes sc on sc.commande_id = c.id
     where c.etat = 'payee' and c.paye_le >= t1 and c.paye_le < t2
     order by c.paye_le desc
     limit 3000
  ),
  cz as (
    select x.*, case
      when x.zone_brute = '' then 'Zone inconnue'
      when niveau = 'commune' and x.zone_brute ~ '\([^()]+\)\Z' then substring(x.zone_brute from '\(([^()]+)\)\Z')
      else x.zone_brute end as zone
      from cmd x
  ),
  lig as (
    select l.commande_id, l.etat, l.confirme_le, s.statut as terrain,
           (select min(j.le) from public.rh_journal_lignes j
             where j.ligne_id = l.id and j.quoi = 'etat' and j.valeur = 'remise') as remise_le
      from public.commande_lignes l
      join cz on cz.id = l.commande_id
      left join public.rh_suivi_lignes s on s.ligne_id = l.id
  ),
  parc as (
    select cz.id, cz.zone,
           case when cz.livraison ->> 'distance_km' ~ '\A[0-9]+(\.[0-9]+)?\Z'
                then (cz.livraison ->> 'distance_km')::numeric end as distance,
           cz.livraison is not null as au_km,
           cz.livraison ->> 'vehicule' = 'tricycle' as tricycle,
           case when exists (select 1 from lig where lig.commande_id = cz.id and lig.etat <> 'annulee')
                 and not exists (select 1 from lig where lig.commande_id = cz.id and lig.etat <> 'annulee'
                                    and lig.confirme_le is null and lig.etat <> 'remise')
                then extract(epoch from ((select max(coalesce(lig.confirme_le, lig.remise_le)) from lig
                                           where lig.commande_id = cz.id and lig.etat <> 'annulee') - cz.paye_le)) / 3600
           end as delai_h,
           exists (select 1 from lig where lig.commande_id = cz.id
                     and lig.terrain in ('echouee', 'retour_en_cours', 'retournee')) as echec,
           exists (select 1 from public.reclamations r where r.commande_id = cz.id and r.sujet = 'non_recu') as non_recu
      from cz
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'zone', z.zone, 'commandes', z.commandes, 'livrees', z.livrees, 'delai_moyen_h', z.delai_moyen_h,
           'lentes', z.lentes, 'lentes_pct', case when z.livrees > 0 then round(100.0 * z.lentes / z.livrees, 1) end,
           'echecs', z.echecs, 'echecs_pct', round(100.0 * z.echecs / z.commandes, 1),
           'non_recus', z.non_recus, 'non_recus_pct', round(100.0 * z.non_recus / z.commandes, 1),
           'distance_moyenne_km', z.distance, 'au_km', z.au_km,
           'tricycle_pct', case when z.au_km > 0 then round(100.0 * z.tricycles / z.au_km, 1) end)
           order by z.commandes desc, z.zone), '[]')
    into zones
    from (select p.zone, count(*) as commandes,
                 count(*) filter (where p.delai_h is not null) as livrees,
                 round(avg(p.delai_h)::numeric, 1) as delai_moyen_h,
                 count(*) filter (where p.delai_h > lent) as lentes,
                 count(*) filter (where p.echec) as echecs,
                 count(*) filter (where p.non_recu) as non_recus,
                 round(avg(p.distance)::numeric, 1) as distance,
                 count(*) filter (where p.au_km) as au_km,
                 count(*) filter (where p.au_km and p.tricycle) as tricycles
            from parc p group by p.zone) z;

  return jsonb_build_object(
    'periode', jsonb_build_object('depuis', debut, 'jusqu', fin),
    'niveau', niveau, 'zone_lent_h', lent, 'zones', zones);
end $$;

/**
 * La fidélité des clients. Un client, c'est son compte, ou à défaut son
 * numéro (les 8 derniers chiffres : « 01 97… » et « 97… » se rejoignent).
 * Seules les commandes payées comptent.
 *   cohortes : les 12 mois qui finissent avec la période ; pour chaque mois
 *              de premier achat, combien de nouveaux clients, et combien ont
 *              racheté 1, 2, 3 mois plus tard (null : mois pas encore venu) ;
 *   perdus   : clients dont le dernier achat date de plus de 60 / 90 jours ;
 *   comptes supprimés : clients dont des commandes portent « compte_supprime ».
 * La valeur des cohortes et la liste à relancer (inactifs depuis
 * « inactif_j » jours, numéros masqués aux 4 derniers chiffres) :
 * l'administration seule. Les autres : des nombres et des taux.
 */
create or replace function public.rh_statistiques_clients(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  a jsonb := public.rh_qualite_acces();
  admin boolean := (a ->> 'acces') = 'admin';
  inactif int := (public.rh_qualite_seuils() ->> 'inactif_j')::int;
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  fin date := coalesce(jusqu, aujourdhui);
  debut date := coalesce(depuis, coalesce(jusqu, aujourdhui) - 29);
  t1 timestamptz;
  t2 timestamptz;
  mois_courant date := date_trunc('month', now() at time zone 'Africa/Porto-Novo')::date;
  mois_fin date;
  res jsonb;
begin
  if a ->> 'acces' is null then
    raise exception 'Votre compte n''a pas accès au menu Qualité';
  end if;
  if fin < debut then
    raise exception 'La fin de la période précède son début';
  end if;
  if fin - debut > 1100 then
    raise exception 'Choisissez une période de trois ans au plus';
  end if;
  t1 := debut::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (fin + 1)::timestamp at time zone 'Africa/Porto-Novo';
  mois_fin := date_trunc('month', fin)::date;

  with cm as (
    select c.id, c.numero, c.paye_le, c.total, c.client_nom, c.client_tel, c.client_id, c.compte_supprime,
           coalesce(c.client_id::text,
                    nullif('tel:' || right(regexp_replace(coalesce(c.client_tel, ''), '\D', '', 'g'), 8), 'tel:')) as cle,
           date_trunc('month', c.paye_le at time zone 'Africa/Porto-Novo')::date as mois
      from public.commandes c
     where c.paye_le is not null and c.etat = 'payee'
  ),
  cm2 as (select * from cm where cm.cle is not null),
  clients_ as (
    select x.cle, min(x.mois) as premier_mois, min(x.paye_le) as premier, max(x.paye_le) as dernier,
           count(*) as nb, sum(x.total) as depense, bool_or(x.compte_supprime) as supprime,
           (array_agg(x.client_nom order by x.paye_le desc))[1] as nom,
           (array_agg(x.client_tel order by x.paye_le desc))[1] as tel,
           (array_agg(x.numero order by x.paye_le desc))[1] as numero
      from cm2 x group by x.cle
  ),
  cohortes as (
    select k.premier_mois as mois, count(*) as nouveaux,
           case when k.premier_mois + interval '1 month' <= mois_courant then
             count(*) filter (where exists (select 1 from cm2 y where y.cle = k.cle
                                              and y.mois = (k.premier_mois + interval '1 month')::date)) end as m1,
           case when k.premier_mois + interval '2 months' <= mois_courant then
             count(*) filter (where exists (select 1 from cm2 y where y.cle = k.cle
                                              and y.mois = (k.premier_mois + interval '2 months')::date)) end as m2,
           case when k.premier_mois + interval '3 months' <= mois_courant then
             count(*) filter (where exists (select 1 from cm2 y where y.cle = k.cle
                                              and y.mois = (k.premier_mois + interval '3 months')::date)) end as m3,
           count(*) filter (where k.nb > 1) as revenus,
           sum(k.depense) as valeur
      from clients_ k
     where k.premier_mois > mois_fin - interval '12 months' and k.premier_mois <= mois_fin
     group by k.premier_mois
  )
  select jsonb_build_object(
    'periode', jsonb_build_object('depuis', debut, 'jusqu', fin),
    'montants', admin,
    'inactif_j', inactif,
    'cohortes', coalesce((select jsonb_agg(jsonb_build_object(
                    'mois', ch.mois, 'nouveaux', ch.nouveaux,
                    'm1', ch.m1, 'm2', ch.m2, 'm3', ch.m3,
                    'm1_pct', case when ch.m1 is not null then round(100.0 * ch.m1 / ch.nouveaux, 1) end,
                    'm2_pct', case when ch.m2 is not null then round(100.0 * ch.m2 / ch.nouveaux, 1) end,
                    'm3_pct', case when ch.m3 is not null then round(100.0 * ch.m3 / ch.nouveaux, 1) end,
                    'revenus', ch.revenus, 'revenus_pct', round(100.0 * ch.revenus / ch.nouveaux, 1),
                    'valeur', case when admin then ch.valeur end) order by ch.mois)
                   from cohortes ch), '[]'),
    'totaux', (select jsonb_build_object(
                 'clients', count(*),
                 'fideles', count(*) filter (where k.nb > 1),
                 'fideles_pct', case when count(*) > 0 then round(100.0 * count(*) filter (where k.nb > 1) / count(*), 1) end,
                 'actifs_periode', (select count(distinct y.cle) from cm2 y where y.paye_le >= t1 and y.paye_le < t2),
                 'nouveaux_periode', count(*) filter (where k.premier >= t1 and k.premier < t2),
                 'perdus_60', count(*) filter (where not k.supprime and k.dernier < now() - interval '60 days'),
                 'perdus_90', count(*) filter (where not k.supprime and k.dernier < now() - interval '90 days'),
                 'a_relancer', count(*) filter (where not k.supprime and k.dernier < now() - make_interval(days => inactif)),
                 'comptes_supprimes', count(*) filter (where k.supprime))
                 from clients_ k),
    'relance', case when admin then coalesce((select jsonb_agg(jsonb_build_object(
                   'nom', r.nom, 'tel', public.rh_tel_masque(r.tel), 'commandes', r.nb,
                   'premier', r.premier, 'dernier', r.dernier, 'derniere_commande', r.numero,
                   'jours', aujourdhui - (r.dernier at time zone 'Africa/Porto-Novo')::date,
                   'depense', r.depense) order by r.nb desc, r.dernier desc)
                   from (select * from clients_ k
                          where not k.supprime and k.dernier < now() - make_interval(days => inactif)
                          order by k.nb desc, k.dernier desc limit 200) r), '[]') end)
    into res;
  return res;
end $$;

/** Les pastilles du menu Qualité : un seul appel, à chaque relecture des compteurs. */
create or replace function public.rh_qualite_compteurs() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  a jsonb := public.rh_qualite_acces();
  s jsonb;
  pop int;
begin
  if a ->> 'acces' is null then
    return jsonb_build_object('acces', null);
  end if;
  s := public.rh_qualite_seuils();
  pop := (s ->> 'populaire_min')::int;
  return jsonb_build_object(
    'acces', a ->> 'acces',
    'sav_sans_reponse', (select count(*) from public.rh_sav_ouvertes() x
                          where x.colonne = 'boutique'
                            and now() - x.depuis_le > make_interval(hours => (s ->> 'reponse_h')::int)),
    'sav_escalades', (select count(*) from public.rh_sav_ouvertes() x
                       where x.colonne = 'bizzoo'
                         and now() - x.depuis_le > make_interval(hours => (s ->> 'decision_h')::int)),
    'ruptures_a_appeler', (select count(*) from public.rh_ventes_30j() v
                             join public.produits p on p.id = v.produit_id
                            where not p.masque and p.stock <= 0 and not p.sur_commande and v.qte >= pop
                              and not exists (select 1 from public.rh_ruptures_suivi x
                                               where x.produit_id = p.id and x.anomalie = 'rupture'
                                                 and x.appele_le > now() - interval '7 days')),
    'files_en_retard', (select count(*) from jsonb_array_elements(public.rh_files_attente() -> 'files') f
                         where (f ->> 'rouge')::boolean));
end $$;

revoke all on function public.rh_qualite_seuils() from public, anon;
grant execute on function public.rh_qualite_seuils() to authenticated, service_role;
revoke all on function public.rh_qualite_acces() from public, anon;
grant execute on function public.rh_qualite_acces() to authenticated, service_role;
revoke all on function public.rh_qualite_regler(jsonb) from public, anon;
grant execute on function public.rh_qualite_regler(jsonb) to authenticated, service_role;
revoke all on function public.rh_notes_releve() from public, anon;
grant execute on function public.rh_notes_releve() to authenticated, service_role;
revoke all on function public.rh_note_boutique_au(text, timestamptz) from public, anon, authenticated;
grant execute on function public.rh_note_boutique_au(text, timestamptz) to service_role;
revoke all on function public.rh_sav_ouvertes() from public, anon, authenticated;
grant execute on function public.rh_sav_ouvertes() to service_role;
revoke all on function public.rh_satisfaction(date, date) from public, anon;
grant execute on function public.rh_satisfaction(date, date) to authenticated, service_role;
revoke all on function public.rh_qualite_boutiques(date, date) from public, anon;
grant execute on function public.rh_qualite_boutiques(date, date) to authenticated, service_role;
revoke all on function public.rh_ventes_30j() from public, anon, authenticated;
grant execute on function public.rh_ventes_30j() to service_role;
revoke all on function public.rh_catalogue_anomalies() from public, anon;
grant execute on function public.rh_catalogue_anomalies() to authenticated, service_role;
revoke all on function public.rh_catalogue_appeler(text, text, boolean, text) from public, anon;
grant execute on function public.rh_catalogue_appeler(text, text, boolean, text) to authenticated, service_role;
revoke all on function public.rh_files_attente() from public, anon;
grant execute on function public.rh_files_attente() to authenticated, service_role;
revoke all on function public.rh_statistiques_zones(date, date, text) from public, anon;
grant execute on function public.rh_statistiques_zones(date, date, text) to authenticated, service_role;
revoke all on function public.rh_statistiques_clients(date, date) from public, anon;
grant execute on function public.rh_statistiques_clients(date, date) to authenticated, service_role;
revoke all on function public.rh_qualite_compteurs() from public, anon;
grant execute on function public.rh_qualite_compteurs() to authenticated, service_role;

-- Le premier relevé des notes, puis chaque matin à 6 h 15 (heure du
-- Bénin) par pg_cron. Sans pg_cron, l'écran Qualité relève à l'ouverture.
select public.rh_notes_releve();
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('rh-notes-boutiques', '15 5 * * *', 'select public.rh_notes_releve()');
  end if;
exception when others then
  raise notice 'Relevé des notes non programmé (%), l''écran Qualité le fera', sqlerrm;
end $$;

-- ---------- La clé « qualite » dans Paramètres ----------
-- Le menu Qualité, sans montants : responsable des boutiques, SAV,
-- catalogue, logistique, marketing.
do $$
begin
  if to_regclass('public.rh_acces_menus') is null then
    return;
  end if;
  if exists (select 1 from pg_constraint where conname = 'rh_acces_menus_menu'
               and pg_get_constraintdef(oid) not like '%''qualite''%') then
    alter table public.rh_acces_menus drop constraint rh_acces_menus_menu;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_acces_menus_menu') then
    alter table public.rh_acces_menus add constraint rh_acces_menus_menu check (menu in ('mails',
      'discussions', 'missions', 'rapports', 'depenses', 'suivi', 'livreurs', 'controles', 'paiements', 'audit',
      'promos', 'qualite', 'caisse', 'stats_commandes', 'stats_boutiques', 'stats_produits', 'stats_livraisons',
      'stats_livreurs', 'stats_sav', 'employes'));
  end if;
end $$;

-- ---------- Les menus réglables, « qualite » comprise (copies de schema.sql) ----------
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
    if k not in ('mails', 'discussions', 'missions', 'rapports', 'depenses', 'suivi', 'livreurs', 'controles', 'paiements', 'audit', 'promos', 'qualite', 'caisse',
                 'stats_commandes', 'stats_boutiques', 'stats_produits', 'stats_livraisons',
                 'stats_livreurs', 'stats_sav', 'employes') then
      raise exception 'Menu inconnu : %', k;
    end if;
    -- Le journal des gestes regarde l'administration : elle ne choisit pas
    -- qui la regarde. L'écran renvoie toutes les clés à chaque
    -- enregistrement : seule une clé « audit » qui CHANGE est refusée.
    if k = 'audit' and not (public.rh_est_ceo() or public.est_super())
       and coalesce(nullif(v, 'ferme'), '') is distinct from
           coalesce((select a.qui from public.rh_acces_menus a where a.profil_id = cible and a.menu = 'audit'), '') then
      raise exception 'Seul le CEO ouvre ou ferme le journal des gestes : c''est l''administration qu''il regarde';
    end if;
    if v is null or v = 'ferme' then
      delete from public.rh_acces_menus where profil_id = cible and menu = k;
    elsif v not in ('membres', 'responsable') then
      raise exception 'Réglage inconnu pour le menu %', k;
    else
      insert into public.rh_acces_menus (profil_id, menu, qui, modifie_par, modifie_le)
      values (cible, k, v, public.rh_moi(), now())
      on conflict on constraint rh_acces_menus_pkey do update
        set qui = excluded.qui, modifie_par = excluded.modifie_par, modifie_le = excluded.modifie_le
        where public.rh_acces_menus.qui is distinct from excluded.qui;
    end if;
  end loop;
end $$;

create or replace function public.rh_mes_menus() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(x.m order by x.n), '{}')
    from unnest(array['mails', 'discussions', 'missions', 'rapports', 'depenses', 'suivi', 'livreurs', 'controles', 'paiements', 'audit', 'promos', 'qualite', 'caisse',
                      'stats_commandes', 'stats_boutiques', 'stats_produits', 'stats_livraisons',
                      'stats_livreurs', 'stats_sav', 'employes']) with ordinality as x(m, n)
   where public.rh_menu_ouvert(x.m);
$$;

-- (menus)
revoke all on function public.rh_regler_acces(uuid, jsonb) from public, anon;
grant execute on function public.rh_regler_acces(uuid, jsonb) to authenticated, service_role;
revoke all on function public.rh_mes_menus() from public, anon;
grant execute on function public.rh_mes_menus() to authenticated, service_role;
