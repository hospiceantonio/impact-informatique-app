-- =========================================================
-- BIZZOO Personnel : la caisse
--
-- La caisse de la maison : quatre compartiments (espèces, MTN Mobile
-- Money, Moov Money, Celtiis Cash), dont la somme fait le solde. Un
-- gestionnaire, désigné par le CEO, la tient : lui seul décaisse les
-- dépenses approuvées et paie les salaires, en répartissant s'il le faut
-- entre les compartiments (20 000 en espèces + 30 000 sur MTN). Les
-- apports viennent du CEO ou d'une autre source nommée. Aucun
-- compartiment ne passe sous zéro ; aucun mouvement ne s'efface : le CEO
-- corrige par un ajustement motivé. La voient : le CEO, le gestionnaire,
-- le superadministrateur, et les profils à qui Paramètres l'ouvre.
-- =========================================================

-- ---------- Les aides (copies de schema.sql) ----------
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



-- ---------- La caisse et son gestionnaire ----------
create table if not exists public.rh_caisse (
  id              boolean primary key default true check (id),
  gestionnaire_id uuid references public.rh_employes(id) on delete set null,
  designe_par     uuid,
  designe_le      timestamptz
);
insert into public.rh_caisse (id) values (true) on conflict (id) do nothing;

-- ---------- Les mouvements : on n'y efface rien, on n'y corrige rien ----------
-- Une erreur se rattrape par un ajustement du CEO, avec son motif.
create table if not exists public.rh_caisse_mouvements (
  id            bigint generated always as identity primary key,
  le            timestamptz not null default now(),
  compte        text not null check (compte in ('especes', 'mtn', 'moov', 'celtiis')),
  sens          text not null check (sens in ('entree', 'sortie')),
  nature        text not null check (nature in ('apport_ceo', 'apport_autre', 'depense', 'salaire',
                                                 'transfert', 'frais', 'ajustement')),
  montant       bigint not null check (montant > 0),
  libelle       text not null default '',
  reference     text not null default '',
  depense_id    uuid references public.rh_depenses(id) on delete set null,
  fiche_id      uuid references public.rh_fiches_paie(id) on delete set null,
  par           uuid,
  solde_compte  bigint not null,   -- le compartiment, après ce mouvement
  solde_total   bigint not null    -- toute la caisse, après ce mouvement
);
create index if not exists rh_caisse_mouvements_le on public.rh_caisse_mouvements (le);

create or replace function public.rh_caisse_figee() returns trigger
language plpgsql as $$
begin
  raise exception 'Un mouvement de caisse ne se modifie ni ne s''efface : le CEO corrige par un ajustement';
end $$;
drop trigger if exists rh_caisse_figee on public.rh_caisse_mouvements;
create trigger rh_caisse_figee before update or delete on public.rh_caisse_mouvements
  for each row execute function public.rh_caisse_figee();

/** Qui voit la caisse : « gestion » (son gestionnaire), « ceo »,
    « super » (le superadministrateur de BIZZOO), « consultation »
    (un profil à qui Paramètres l'ouvre), ou rien. L'administration
    n'y entre pas d'office. */
create or replace function public.rh_caisse_acces() returns text
language plpgsql stable security definer set search_path = public as $$
declare
  v_moi uuid := public.rh_moi();
begin
  if v_moi is not null and exists (select 1 from public.rh_caisse where gestionnaire_id = v_moi) then
    return 'gestion';
  end if;
  if public.rh_est_ceo() then
    return 'ceo';
  end if;
  if public.est_super() then
    return 'super';
  end if;
  if v_moi is not null and exists (
       select 1 from public.rh_acces_menus a join public.rh_profils p on p.id = a.profil_id
        where a.menu = 'caisse'
          and (p.responsable_id = v_moi or (a.qui = 'membres' and p.id = public.rh_mon_profil()))) then
    return 'consultation';
  end if;
  return null;
end $$;

/** Un mouvement, la caisse verrouillée : le solde ne passe jamais sous
    zéro, compartiment par compartiment. Interne. */
create or replace function public.rh_caisse_mouvoir(p_compte text, p_sens text, p_nature text,
  p_montant bigint, p_libelle text, p_reference text default '', p_depense uuid default null,
  p_fiche uuid default null)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  dispo bigint;
  total bigint;
  nouveau bigint;
  ligne bigint;
begin
  if p_montant is null or p_montant <= 0 then
    raise exception 'Le montant doit être positif';
  end if;
  perform 1 from public.rh_caisse where id for update;
  select coalesce(sum(case when sens = 'entree' then montant else -montant end), 0) into dispo
    from public.rh_caisse_mouvements where compte = p_compte;
  select coalesce(sum(case when sens = 'entree' then montant else -montant end), 0) into total
    from public.rh_caisse_mouvements;
  if p_sens = 'sortie' and dispo < p_montant then
    raise exception 'Solde insuffisant en % : % FCFA disponibles, % FCFA demandés',
      case p_compte when 'especes' then 'espèces' when 'mtn' then 'MTN Mobile Money'
                    when 'moov' then 'Moov Money' else 'Celtiis Cash' end,
      replace(to_char(dispo, 'FM999G999G999G990'), ',', ' '), replace(to_char(p_montant, 'FM999G999G999G990'), ',', ' ');
  end if;
  nouveau := dispo + case when p_sens = 'entree' then p_montant else -p_montant end;
  insert into public.rh_caisse_mouvements (compte, sens, nature, montant, libelle, reference,
                                           depense_id, fiche_id, par, solde_compte, solde_total)
  values (p_compte, p_sens, p_nature, p_montant, left(btrim(coalesce(p_libelle, '')), 300),
          left(btrim(coalesce(p_reference, '')), 120), p_depense, p_fiche, public.rh_moi(), nouveau,
          total + case when p_sens = 'entree' then p_montant else -p_montant end)
  returning id into ligne;
  return ligne;
end $$;

/** La répartition d'un paiement entre les compartiments : { "especes":
    20000, "mtn": 30000 }. Sa somme doit faire le montant, exactement. */
create or replace function public.rh_caisse_repartition(brut jsonb, montant bigint) returns jsonb
language plpgsql immutable as $$
declare
  k text;
  v jsonb;
  somme bigint := 0;
  propre jsonb := '{}'::jsonb;
begin
  if brut is null or jsonb_typeof(brut) <> 'object' then
    raise exception 'Indiquez d''où sort l''argent : espèces, MTN, Moov ou Celtiis';
  end if;
  for k, v in select e.key, e.value from jsonb_each(brut) as e loop
    if k not in ('especes', 'mtn', 'moov', 'celtiis') then
      raise exception 'Compartiment de caisse inconnu : %', k;
    end if;
    if jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric <> round((v #>> '{}')::numeric) or (v #>> '{}')::numeric < 0 then
      raise exception 'Un montant en francs entiers, positif, pour %', k;
    end if;
    if (v #>> '{}')::bigint > 0 then
      propre := propre || jsonb_build_object(k, (v #>> '{}')::bigint);
      somme := somme + (v #>> '{}')::bigint;
    end if;
  end loop;
  if somme <> montant then
    raise exception 'La répartition fait % FCFA, pour un montant de % FCFA : elle doit tomber juste',
      replace(to_char(somme, 'FM999G999G999G990'), ',', ' '), replace(to_char(montant, 'FM999G999G999G990'), ',', ' ');
  end if;
  return propre;
end $$;

-- ---------- Ce qui sort : les dépenses et les salaires ----------
-- Un déclencheur, pour qu'AUCUN décaissement n'échappe à la caisse : il
-- lit la répartition posée par rh_decaisser / rh_payer (« rh.repartition »),
-- ou, à défaut, met tout le montant sur le compartiment choisi.
create or replace function public.rh_depense_sort_de_caisse() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  rep jsonb;
  k text;
  v jsonb;
begin
  if new.statut <> 'decaissee' or old.statut = 'decaissee' then
    return null;
  end if;
  rep := nullif(current_setting('rh.repartition', true), '')::jsonb;
  if rep is null then
    if new.mode_decaissement not in ('especes', 'mtn', 'moov', 'celtiis') then
      raise exception 'Une dépense sort de la caisse : espèces, MTN, Moov ou Celtiis';
    end if;
    rep := jsonb_build_object(new.mode_decaissement, new.montant);
  end if;
  rep := public.rh_caisse_repartition(rep, new.montant);
  for k, v in select e.key, e.value from jsonb_each(rep) as e order by e.key loop
    perform public.rh_caisse_mouvoir(k, 'sortie', 'depense', (v #>> '{}')::bigint,
      'D-' || lpad(new.numero::text, 4, '0') || ' · ' || new.objet, new.reference, new.id, null);
  end loop;
  return null;
end $$;
drop trigger if exists rh_depense_sort_de_caisse on public.rh_depenses;
create trigger rh_depense_sort_de_caisse after update of statut on public.rh_depenses
  for each row execute function public.rh_depense_sort_de_caisse();

create or replace function public.rh_salaire_sort_de_caisse() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  rep jsonb;
  k text;
  v jsonb;
begin
  if new.statut <> 'payee' or old.statut = 'payee' then
    return null;
  end if;
  /* Versée sur le solde de l'employé : rien ne sort encore de la caisse.
     L'argent en sortira au retrait, s'il le retire à la caisse. */
  if new.mode_paiement = 'solde' then
    return null;
  end if;
  rep := nullif(current_setting('rh.repartition', true), '')::jsonb;
  if rep is null then
    if new.mode_paiement not in ('especes', 'mtn', 'moov', 'celtiis') then
      raise exception 'Un salaire sort de la caisse : espèces, MTN, Moov ou Celtiis';
    end if;
    rep := jsonb_build_object(new.mode_paiement, new.net);
  end if;
  rep := public.rh_caisse_repartition(rep, new.net);
  for k, v in select e.key, e.value from jsonb_each(rep) as e order by e.key loop
    perform public.rh_caisse_mouvoir(k, 'sortie', 'salaire', (v #>> '{}')::bigint,
      'Salaire de ' || to_char(new.mois, 'MM/YYYY'), new.reference, null, new.id);
  end loop;
  return null;
end $$;
drop trigger if exists rh_salaire_sort_de_caisse on public.rh_fiches_paie;
create trigger rh_salaire_sort_de_caisse after update of statut on public.rh_fiches_paie
  for each row execute function public.rh_salaire_sort_de_caisse();

/** Décaisser une dépense, réparti entre les compartiments. */
create or replace function public.rh_decaisser(depense uuid, repartition jsonb, reference text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare
  d public.rh_depenses;
  rep jsonb;
begin
  select * into d from public.rh_depenses where id = depense;
  if not found then
    raise exception 'Dépense introuvable';
  end if;
  rep := public.rh_caisse_repartition(repartition, d.montant);
  perform set_config('rh.repartition', rep::text, true);
  perform public.rh_decaisser_depense(depense,
    case when (select count(*) from jsonb_object_keys(rep)) = 1 then (select k from jsonb_object_keys(rep) k) else 'mixte' end,
    reference);
  perform set_config('rh.repartition', '', true);
end $$;

/** Payer une fiche de paie, répartie entre les compartiments. */
create or replace function public.rh_payer(fiche uuid, repartition jsonb, reference text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Un salaire ne se paie plus ici : la fiche validée est versée le 10 sur le solde de l''employé, qui le retire depuis son compte (Mobile Money ou caisse)';
end $$;

-- ---------- Ce qui entre, ce qui se déplace, ce qui se corrige ----------
/** Désigner le gestionnaire de la caisse : le CEO seul. */
create or replace function public.rh_designer_gestionnaire_caisse(qui uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO désigne le gestionnaire de la caisse';
  end if;
  if not exists (select 1 from public.rh_employes where id = qui and etat = 'actif') then
    raise exception 'Le gestionnaire doit être un employé en poste';
  end if;
  update public.rh_caisse set gestionnaire_id = qui, designe_par = public.rh_moi(), designe_le = now() where id;
end $$;

/** Un apport : du CEO, ou d'une autre source qu'on nomme. Le gestionnaire
    ou le CEO l'enregistre. */
create or replace function public.rh_caisse_apport(compte text, montant bigint, provenance text,
  libelle text default '', reference text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.rh_caisse_acces() not in ('gestion', 'ceo') or public.rh_caisse_acces() is null then
    raise exception 'Seuls le gestionnaire de la caisse et le CEO enregistrent un apport';
  end if;
  if compte not in ('especes', 'mtn', 'moov', 'celtiis') then
    raise exception 'Compartiment de caisse inconnu';
  end if;
  if provenance not in ('ceo', 'autre') then
    raise exception 'D''où vient l''argent : du CEO, ou d''une autre source ?';
  end if;
  if provenance = 'autre' and length(btrim(coalesce(libelle, ''))) < 3 then
    raise exception 'Nommez la source de cet apport';
  end if;
  perform public.rh_caisse_mouvoir(compte, 'entree',
    case when provenance = 'ceo' then 'apport_ceo' else 'apport_autre' end, montant,
    coalesce(nullif(btrim(libelle), ''), 'Apport du CEO'), reference);
end $$;

/** Déplacer de l'argent d'un compartiment à l'autre (retrait Mobile
    Money en espèces, dépôt…), avec les frais de l'opérateur s'il y en a. */
create or replace function public.rh_caisse_transfert(de text, vers text, montant bigint,
  frais bigint default 0, libelle text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare
  nom text := case de when 'especes' then 'Espèces' when 'mtn' then 'MTN' when 'moov' then 'Moov' else 'Celtiis' end
              || ' → ' || case vers when 'especes' then 'Espèces' when 'mtn' then 'MTN' when 'moov' then 'Moov' else 'Celtiis' end;
begin
  if public.rh_caisse_acces() is distinct from 'gestion' then
    raise exception 'Seul le gestionnaire de la caisse déplace de l''argent entre les compartiments';
  end if;
  if de = vers or de not in ('especes', 'mtn', 'moov', 'celtiis') or vers not in ('especes', 'mtn', 'moov', 'celtiis') then
    raise exception 'Choisissez deux compartiments différents';
  end if;
  if coalesce(frais, 0) < 0 then
    raise exception 'Les frais ne sont pas négatifs';
  end if;
  perform public.rh_caisse_mouvoir(de, 'sortie', 'transfert', montant, nom || coalesce(' · ' || nullif(btrim(libelle), ''), ''));
  perform public.rh_caisse_mouvoir(vers, 'entree', 'transfert', montant, nom || coalesce(' · ' || nullif(btrim(libelle), ''), ''));
  if coalesce(frais, 0) > 0 then
    perform public.rh_caisse_mouvoir(de, 'sortie', 'frais', frais, 'Frais de l''opérateur · ' || nom);
  end if;
end $$;

/** Corriger une erreur ou un écart constaté au comptage : le CEO seul,
    avec un motif. Positif : de l'argent en plus ; négatif : en moins. */
create or replace function public.rh_caisse_ajustement(compte text, montant bigint, motif text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_ceo() then
    raise exception 'Seul le CEO ajuste la caisse';
  end if;
  if compte not in ('especes', 'mtn', 'moov', 'celtiis') then
    raise exception 'Compartiment de caisse inconnu';
  end if;
  if coalesce(montant, 0) = 0 then
    raise exception 'Un ajustement de zéro ne change rien';
  end if;
  if length(btrim(coalesce(motif, ''))) < 3 then
    raise exception 'Dites pourquoi vous ajustez la caisse';
  end if;
  perform public.rh_caisse_mouvoir(compte, case when montant > 0 then 'entree' else 'sortie' end,
    'ajustement', abs(montant), btrim(motif));
end $$;

/** La caisse : le solde à l'instant, par compartiment, et les mouvements
    d'une période. En consultation, un salaire ne dit pas de qui il est. */
create or replace function public.rh_caisse(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  acces text := public.rh_caisse_acces();
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  debut date := coalesce(depuis, date_trunc('month', aujourdhui)::date);
  fin date := coalesce(jusqu, aujourdhui);
  t1 timestamptz;
  t2 timestamptz;
begin
  if acces is null then
    raise exception 'Votre compte n''a pas accès à la caisse';
  end if;
  if fin < debut then
    raise exception 'La fin de la période précède son début';
  end if;
  t1 := debut::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (fin + 1)::timestamp at time zone 'Africa/Porto-Novo';
  return jsonb_build_object(
    'acces', acces,
    'periode', jsonb_build_object('depuis', debut, 'jusqu', fin),
    'gestionnaire', (select jsonb_build_object('id', e.id, 'nom', btrim(e.prenoms || ' ' || e.nom), 'le', c.designe_le)
                       from public.rh_caisse c join public.rh_employes e on e.id = c.gestionnaire_id),
    'comptes', (select jsonb_agg(jsonb_build_object(
        'compte', k.compte,
        'solde', coalesce((select sum(case when m.sens = 'entree' then m.montant else -m.montant end)
                             from public.rh_caisse_mouvements m where m.compte = k.compte), 0),
        'debut', coalesce((select sum(case when m.sens = 'entree' then m.montant else -m.montant end)
                             from public.rh_caisse_mouvements m where m.compte = k.compte and m.le < t1), 0),
        'entrees', coalesce((select sum(m.montant) from public.rh_caisse_mouvements m
                              where m.compte = k.compte and m.sens = 'entree' and m.le >= t1 and m.le < t2), 0),
        'sorties', coalesce((select sum(m.montant) from public.rh_caisse_mouvements m
                              where m.compte = k.compte and m.sens = 'sortie' and m.le >= t1 and m.le < t2), 0))
        order by k.n)
      from unnest(array['especes', 'mtn', 'moov', 'celtiis']) with ordinality as k(compte, n)),
    'mouvements', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', m.id, 'le', m.le, 'compte', m.compte, 'sens', m.sens, 'nature', m.nature, 'montant', m.montant,
        'libelle', case when acces = 'consultation' and m.nature in ('salaire', 'pret')
                          then split_part(m.libelle, ' · ', 1)
                        when m.nature = 'salaire' and m.fiche_id is not null
                          then m.libelle || coalesce(' · ' || (select f.employe ->> 'prenoms' || ' ' || (f.employe ->> 'nom')
                                                                 from public.rh_fiches_paie f where f.id = m.fiche_id), '')
                        else m.libelle end,
        'reference', m.reference, 'depense_id', m.depense_id,
        'par', (select btrim(e.prenoms || ' ' || e.nom) from public.rh_employes e where e.id = m.par),
        'solde_compte', m.solde_compte, 'solde_total', m.solde_total) order by m.id desc), '[]')
      from public.rh_caisse_mouvements m where m.le >= t1 and m.le < t2));
end $$;

-- ---------- Les droits ----------
alter table public.rh_caisse enable row level security;
alter table public.rh_caisse_mouvements enable row level security;
-- Aucune règle : tout passe par les fonctions ci-dessus.
revoke all on table public.rh_caisse, public.rh_caisse_mouvements from public, anon, authenticated;
grant all on table public.rh_caisse, public.rh_caisse_mouvements to service_role;

do $$
declare f text;
begin
  foreach f in array array['rh_caisse_acces()', 'rh_decaisser(uuid, jsonb, text)', 'rh_payer(uuid, jsonb, text)',
                           'rh_designer_gestionnaire_caisse(uuid)', 'rh_caisse_apport(text, bigint, text, text, text)',
                           'rh_caisse_transfert(text, text, bigint, bigint, text)', 'rh_caisse_ajustement(text, bigint, text)',
                           'rh_caisse(date, date)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
  foreach f in array array['rh_caisse_mouvoir(text, text, text, bigint, text, text, uuid, uuid)',
                           'rh_caisse_repartition(jsonb, bigint)', 'rh_depense_sort_de_caisse()',
                           'rh_salaire_sort_de_caisse()', 'rh_caisse_figee()'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

-- ---------- Le menu « caisse » dans Paramètres (consultation) ----------
do $$
begin
  if to_regclass('public.rh_acces_menus') is null then
    return;
  end if;
  if exists (select 1 from pg_constraint where conname = 'rh_acces_menus_menu'
               and pg_get_constraintdef(oid) not like '%''caisse''%') then
    alter table public.rh_acces_menus drop constraint rh_acces_menus_menu;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_acces_menus_menu') then
    alter table public.rh_acces_menus add constraint rh_acces_menus_menu check (menu in ('mails',
      'discussions', 'missions', 'rapports', 'depenses', 'suivi', 'livreurs', 'controles', 'caisse', 'stats_commandes',
      'stats_boutiques', 'stats_produits', 'stats_livraisons', 'stats_livreurs', 'stats_sav', 'employes'));
  end if;
end $$;

-- Les décaissements d'avant la caisse gardent leur mode ; la colonne
-- accepte désormais les compartiments.
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'rh_depenses_mode_decaissement_check'
               and pg_get_constraintdef(oid) not like '%celtiis%') then
    alter table public.rh_depenses drop constraint rh_depenses_mode_decaissement_check;
    alter table public.rh_depenses add constraint rh_depenses_mode_decaissement_check
      check (mode_decaissement in ('especes', 'mtn', 'moov', 'celtiis', 'mixte', 'virement', 'mobile_money', 'cheque'));
  end if;
end $$;

-- ---------- Ce qui change (copies de schema.sql) ----------
create or replace function public.rh_peut_decaisser() returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if to_regclass('public.rh_caisse') is null then
    return exists (select 1 from public.rh_employes
                    where compte_id = auth.uid() and etat = 'actif' and peut_decaisser);
  end if;
  return exists (select 1 from public.rh_caisse c
                   join public.rh_employes e on e.id = c.gestionnaire_id
                  where e.compte_id = auth.uid() and e.etat = 'actif');
end $$;

create or replace function public.rh_decaisser_depense(depense uuid, mode text, reference text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_peut_decaisser() then
    raise exception 'Votre compte n''est pas habilité à décaisser';
  end if;
  if mode not in ('especes', 'mtn', 'moov', 'celtiis', 'mixte') then
    raise exception 'Choisissez le compartiment de la caisse : espèces, MTN, Moov ou Celtiis';
  end if;
  if exists (select 1 from public.rh_depenses where id = depense and demandeur_id = public.rh_moi()) then
    raise exception 'On ne décaisse pas sa propre demande : un autre habilité s''en charge';
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

create or replace function public.rh_payer_fiche(fiche uuid, mode text, reference text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Un salaire ne se paie plus ici : la fiche validée est versée le 10 sur le solde de l''employé, qui le retire depuis son compte (Mobile Money ou caisse)';
end $$;

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
    return cle in ('mails', 'discussions', 'depenses');
  end if;
  return exists (
    select 1 from public.rh_acces_menus a
      join public.rh_profils p on p.id = a.profil_id
     where a.menu = cle
       and (p.responsable_id = v_moi or (a.qui = 'membres' and p.id = v_profil)));
end $$;

create or replace function public.rh_peut_ecrire_a(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.rh_moi() is not null and cible <> public.rh_moi() and exists (
    select 1 from public.rh_employes c where c.id = cible and c.etat = 'actif');
$$;

-- Le fil général, « Tout le monde » : un message n'a alors ni profil ni
-- destinataire. Une et une seule cible : un profil, une personne, ou tous.
alter table public.rh_messages add column if not exists general boolean not null default false;
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'rh_messages_une_cible'
               and pg_get_constraintdef(oid) not like '%general%') then
    alter table public.rh_messages drop constraint rh_messages_une_cible;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_messages_une_cible') then
    alter table public.rh_messages add constraint rh_messages_une_cible
      check (num_nonnulls(profil_id, destinataire_id) + case when general then 1 else 0 end = 1);
  end if;
end $$;
create index if not exists rh_messages_general on public.rh_messages (id) where general;

create or replace function public.rh_a_ecrit_dans(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.rh_moi() is not null and exists (
    select 1 from public.rh_messages m where m.profil_id = cible and m.auteur_id = public.rh_moi());
$$;

create or replace function public.rh_conversations()
returns table (cle text, genre text, cible uuid, titre text, dernier_texte text,
               dernier_le timestamptz, non_lus int)
language sql stable security definer set search_path = public as $$
  with moi as (select public.rh_moi() as id, public.rh_est_admin() as admin),
  groupes as (
    select 'p:' || p.id as cle, 'profil'::text as genre, p.id as cible, p.nom as titre
      from public.rh_profils p, moi
     where moi.id is not null
       and (moi.admin or public.rh_acces(p.id, 'discussions')
            or (public.rh_menu_ouvert('discussions') and public.rh_a_ecrit_dans(p.id)))
  ),
  -- « Tout le monde » : tous les employés qui ont les discussions.
  general as (
    select 'g:tous' as cle, 'general'::text as genre, null::uuid as cible, 'Tout le monde' as titre
      from moi where moi.id is not null and public.rh_menu_ouvert('discussions')
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
  toutes as (select * from general union all select * from groupes union all select * from prives)
  select t.cle, t.genre, t.cible, t.titre, d.texte, d.cree_le,
         (select count(*)::int from public.rh_messages m, moi
           where m.auteur_id <> moi.id
             and m.cree_le > coalesce((select l.lu_le from public.rh_lectures l
                                        where l.employe_id = moi.id and l.conversation = t.cle),
                                      '-infinity')
             and ((t.genre = 'profil' and m.profil_id = t.cible)
               or (t.genre = 'general' and m.general)
               or (t.genre = 'personne' and m.auteur_id = t.cible and m.destinataire_id = moi.id)))
    from toutes t
    left join lateral (
      select m.texte, m.cree_le from public.rh_messages m, moi
       where (t.genre = 'profil' and m.profil_id = t.cible)
          or (t.genre = 'general' and m.general)
          or (t.genre = 'personne' and ((m.auteur_id = t.cible and m.destinataire_id = moi.id)
                                     or (m.auteur_id = moi.id and m.destinataire_id = t.cible)))
       order by m.id desc limit 1) d on true
   order by t.genre = 'general' desc, d.cree_le desc nulls last, t.titre;
$$;

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
      'bloque', exists (select 1 from public.rh_employes where compte_id = auth.uid() and etat = 'bloque'),
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
      'ceo', v_ceo, 'administration', v_admin, 'peut_decaisser', public.rh_peut_decaisser(),
      'super', public.est_super(),
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
      'depenses_a_valider',
        (select count(*) from public.rh_depenses where statut = 'demandee' and profil_id = any(mes_profils)),
      'depenses_a_approuver', case when v_ceo then
        (select count(*) from public.rh_depenses where statut = 'validee_responsable') else 0 end,
      'depenses_a_decaisser', case when public.rh_peut_decaisser() then
        (select count(*) from public.rh_depenses where statut = 'approuvee') else 0 end,
      'baremes_a_valider', case when v_ceo then
        (select count(*) from public.rh_cotisations where actif and not valide)
        + (select count(*) from public.rh_reglages_paie r
            where not r.impot_valide and exists (select 1 from public.rh_tranches_impot)) else 0 end,
      'fiches_a_valider', case when v_ceo then
        (select count(*) from public.rh_fiches_paie
          where statut = 'calculee'
            and mois < date_trunc('month', aujourdhui + 1)::date) else 0 end,
      'fiches_a_payer', case when public.rh_peut_decaisser() then
        (select count(*) from public.rh_fiches_paie where statut = 'validee') else 0 end,
      'messages_non_lus', (select coalesce(sum(non_lus), 0) from public.rh_conversations())));
end $$;

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
    if k not in ('mails', 'discussions', 'missions', 'rapports', 'depenses', 'suivi', 'livreurs', 'controles', 'caisse',
                 'stats_commandes', 'stats_boutiques', 'stats_produits', 'stats_livraisons',
                 'stats_livreurs', 'stats_sav', 'employes') then
      raise exception 'Menu inconnu : %', k;
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
    from unnest(array['mails', 'discussions', 'missions', 'rapports', 'depenses', 'suivi', 'livreurs', 'controles', 'caisse',
                      'stats_commandes', 'stats_boutiques', 'stats_produits', 'stats_livraisons',
                      'stats_livreurs', 'stats_sav', 'employes']) with ordinality as x(m, n)
   where public.rh_menu_ouvert(x.m);
$$;


