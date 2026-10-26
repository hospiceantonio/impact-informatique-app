-- =========================================================
-- BIZZOO Personnel : le circuit des dépenses
--
-- Tout employé demande une dépense (motif, montant). Son responsable
-- de profil la valide, puis le CEO l'approuve, puis l'employé habilité
-- la décaisse (jamais sa propre demande). Statuts : « demandee » (chez
-- le responsable), « validee_responsable » (chez le CEO), « approuvee »
-- (à décaisser), « decaissee », « refusee », « annulee ». Sans
-- responsable (pas de profil, profil sans responsable, ou demandeur
-- responsable lui-même), la demande va droit au CEO.
-- =========================================================

-- ---------- Les aides (copies de schema.sql) ----------

-- ---------- La table : un statut de plus, trois colonnes, un profil facultatif ----------
alter table public.rh_depenses add column if not exists responsable_par uuid;
alter table public.rh_depenses add column if not exists responsable_le timestamptz;
alter table public.rh_depenses add column if not exists motif_responsable text not null default '';
alter table public.rh_depenses alter column profil_id drop not null;
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'rh_depenses_statut_check'
               and pg_get_constraintdef(oid) not like '%validee_responsable%') then
    alter table public.rh_depenses drop constraint rh_depenses_statut_check;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_depenses_statut_check') then
    alter table public.rh_depenses add constraint rh_depenses_statut_check
      check (statut in ('demandee', 'validee_responsable', 'approuvee', 'refusee', 'decaissee', 'annulee'));
  end if;
  -- Les dépenses ne sont plus réservées au responsable : tout employé
  -- demande, à qui Paramètres ouvre le menu (tous les membres d'office).
  if to_regclass('public.rh_acces_menus') is not null then
    alter table public.rh_acces_menus drop constraint if exists rh_acces_depenses_responsable;
    update public.rh_acces_menus set qui = 'membres' where menu = 'depenses' and qui = 'responsable';
  end if;
end $$;

/** Le responsable du profil valide (ou refuse, avec un motif) une
    demande de l'un de ses membres ; elle part alors chez le CEO. */
create or replace function public.rh_valider_depense(depense uuid, valider boolean, motif text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare d public.rh_depenses;
begin
  select * into d from public.rh_depenses where id = depense for update;
  if not found or d.profil_id is null or not public.rh_responsable_de(d.profil_id) then
    raise exception 'Seul le responsable du profil valide cette demande';
  end if;
  if d.statut <> 'demandee' then
    raise exception 'Cette demande n''attend pas la validation du responsable';
  end if;
  if not valider and length(btrim(coalesce(motif, ''))) = 0 then
    raise exception 'Dites pourquoi vous refusez la dépense';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_depenses
     set statut = case when valider then 'validee_responsable' else 'refusee' end,
         responsable_par = public.rh_moi(), responsable_le = now(),
         motif_responsable = btrim(coalesce(motif, ''))
   where id = depense;
  perform set_config('rh.decision', '', true);
end $$;
revoke all on function public.rh_valider_depense(uuid, boolean, text) from public, anon;
grant execute on function public.rh_valider_depense(uuid, boolean, text) to authenticated, service_role;

create or replace function public.rh_moi() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
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

-- ---------- Ce qui change (copies de schema.sql) ----------

drop policy if exists "rh depenses lecture" on public.rh_depenses;
drop policy if exists "rh depenses demande" on public.rh_depenses;
create policy "rh depenses lecture" on public.rh_depenses
  for select to authenticated using (
    public.rh_est_admin()
    or demandeur_id = public.rh_moi()
    or (profil_id is not null and public.rh_responsable_de(profil_id))
    or (public.rh_peut_decaisser() and statut in ('approuvee', 'decaissee')));

create policy "rh depenses demande" on public.rh_depenses
  for insert to authenticated
  with check (public.rh_moi() is not null and public.rh_menu_ouvert('depenses'));

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
    -- Le profil du DEMANDEUR, jamais celui que l'écran propose.
    new.profil_id := public.rh_mon_profil();
    -- Son responsable valide d'abord. Sans responsable (pas de profil,
    -- profil sans responsable), ou s'il est lui-même le responsable,
    -- la demande va droit au CEO.
    new.statut := case
      when exists (select 1 from public.rh_profils p
                    where p.id = new.profil_id and p.responsable_id is not null
                      and p.responsable_id <> new.demandeur_id) then 'demandee'
      else 'validee_responsable' end;
    new.cree_le := now();
    new.responsable_par := null; new.responsable_le := null; new.motif_responsable := '';
    new.decision_par := null; new.decision_le := null; new.motif_decision := '';
    new.decaisse_par := null; new.decaisse_le := null; new.mode_decaissement := null;
    new.reference := '';
    return new;
  end if;
  -- Modifiable tant que personne ne l'a validée.
  if not (old.statut = 'demandee'
          or (old.statut = 'validee_responsable' and old.responsable_par is null)) then
    raise exception 'Une demande déjà validée ou tranchée ne se modifie plus';
  end if;
  if (to_jsonb(new) - libres) is distinct from (to_jsonb(old) - libres) then
    raise exception 'Seuls l''objet, le détail et le montant se modifient';
  end if;
  return new;
end $$;

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
   where id = depense and statut = 'validee_responsable';
  if not found then
    raise exception 'Cette dépense n''attend pas la décision du CEO : son responsable doit d''abord la valider';
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

create or replace function public.rh_annuler_depense(depense uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('rh.decision', 'oui', true);
  update public.rh_depenses set statut = 'annulee'
   where id = depense and statut in ('demandee', 'validee_responsable') and demandeur_id = public.rh_moi();
  if not found then
    raise exception 'Seul le demandeur annule une demande encore en attente';
  end if;
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
    if k not in ('mails', 'discussions', 'missions', 'rapports', 'depenses', 'suivi', 'livreurs', 'caisse',
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

create or replace function public.rh_profil_acces_defaut() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.rh_acces_menus (profil_id, menu, qui)
  values (new.id, 'mails', 'membres'), (new.id, 'discussions', 'membres'),
         (new.id, 'missions', 'membres'), (new.id, 'rapports', 'membres'),
         (new.id, 'depenses', 'membres')
  on conflict do nothing;
  return null;
end $$;

create or replace function public.rh_finances(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  m1 date := date_trunc('month', coalesce(depuis, aujourdhui - 330))::date;
  m2 date := date_trunc('month', coalesce(jusqu, aujourdhui))::date;
  fin date;
  t1 timestamptz;
  t2 timestamptz;
  v_admin boolean := public.rh_est_admin() or public.est_super();
  v_revenus boolean := public.rh_est_ceo() or public.est_super();
  salaires jsonb;
  depenses jsonb;
  effectifs jsonb;
  activite jsonb;
  revenus jsonb := null;
begin
  if not v_admin then
    raise exception 'Les statistiques internes sont réservées à l''administration';
  end if;
  if m2 < m1 then
    raise exception 'La fin de la période précède son début';
  end if;
  if m2 - m1 > 1100 then
    raise exception 'Choisissez une période de trois ans au plus';
  end if;
  fin := (m2 + interval '1 month - 1 day')::date;
  t1 := m1::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (fin + 1)::timestamp at time zone 'Africa/Porto-Novo';

  -- ---------- Les salaires (fiches validées ou payées) ----------
  with les_mois as (select generate_series(m1, m2, interval '1 month')::date as mois),
  f as (select * from public.rh_fiches_paie where mois between m1 and m2),
  pm as (
    select lm.mois,
           count(f.id) filter (where f.statut <> 'calculee') as fiches,
           coalesce(sum(f.brut) filter (where f.statut <> 'calculee'), 0) as brut,
           coalesce(sum(f.cotisations_salariales) filter (where f.statut <> 'calculee'), 0) as cotisations,
           coalesce(sum(f.impot) filter (where f.statut <> 'calculee'), 0) as impot,
           coalesce(sum(f.avances) filter (where f.statut <> 'calculee'), 0) as avances,
           coalesce(sum(f.retenues) filter (where f.statut <> 'calculee'), 0) as retenues,
           coalesce(sum(f.net) filter (where f.statut <> 'calculee'), 0) as net,
           coalesce(sum(f.charges_patronales) filter (where f.statut <> 'calculee'), 0) as charges,
           coalesce(sum(f.net) filter (where f.statut = 'payee'), 0) as paye,
           coalesce(sum(f.net) filter (where f.statut = 'validee'), 0) as a_payer,
           count(f.id) filter (where f.statut = 'calculee') as provisoires,
           coalesce(sum(f.net) filter (where f.statut = 'calculee'), 0) as net_provisoire
      from les_mois lm left join f on f.mois = lm.mois
     group by lm.mois)
  select jsonb_build_object(
    'par_mois', (select coalesce(jsonb_agg(jsonb_build_object(
        'mois', mois, 'fiches', fiches, 'brut', brut, 'cotisations', cotisations, 'impot', impot,
        'avances', avances, 'retenues', retenues, 'net', net, 'charges', charges, 'cout', brut + charges,
        'paye', paye, 'a_payer', a_payer, 'provisoires', provisoires, 'net_provisoire', net_provisoire)
        order by mois), '[]') from pm),
    'par_profil', (select coalesce(jsonb_agg(jsonb_build_object(
        'profil', x.profil, 'effectif', x.effectif, 'fiches', x.fiches, 'brut', x.brut, 'net', x.net, 'cout', x.cout)
        order by x.cout desc), '[]')
       from (select coalesce(nullif(f.employe ->> 'profil', ''), 'Sans profil') as profil,
                    count(distinct f.employe_id) as effectif, count(*) as fiches,
                    sum(f.brut) as brut, sum(f.net) as net, sum(f.brut + f.charges_patronales) as cout
               from f where f.statut <> 'calculee' group by 1) x),
    'par_statut', (select coalesce(jsonb_agg(jsonb_build_object(
        'statut', x.statut, 'effectif', x.effectif, 'brut', x.brut, 'cout', x.cout) order by x.statut), '[]')
       from (select coalesce(nullif(f.employe ->> 'statut', ''), 'employe') as statut,
                    count(distinct f.employe_id) as effectif, sum(f.brut) as brut,
                    sum(f.brut + f.charges_patronales) as cout
               from f where f.statut <> 'calculee' group by 1) x),
    'avances_accordees', (select coalesce(sum(a.montant), 0) from public.rh_avances a
                           where a.statut <> 'annulee' and a.date_avance between m1 and fin),
    'avances_nombre', (select count(*) from public.rh_avances a
                        where a.statut <> 'annulee' and a.date_avance between m1 and fin),
    'avances_encours', (select coalesce(sum(a.montant - coalesce((
                            select sum(fa.montant) from public.rh_fiche_avances fa
                              join public.rh_fiches_paie fp on fp.id = fa.fiche_id
                             where fa.avance_id = a.id and fp.statut <> 'calculee'), 0)), 0)
                          from public.rh_avances a where a.statut = 'active')
  ) into salaires;

  -- ---------- Les dépenses ----------
  with les_mois as (select generate_series(m1, m2, interval '1 month')::date as mois),
  d as (
    select dp.*, coalesce(p.nom, '—') as profil,
           date_trunc('month', dp.cree_le at time zone 'Africa/Porto-Novo')::date as mois_demande,
           date_trunc('month', dp.decaisse_le at time zone 'Africa/Porto-Novo')::date as mois_decaisse
      from public.rh_depenses dp left join public.rh_profils p on p.id = dp.profil_id)
  select jsonb_build_object(
    'par_mois', (select coalesce(jsonb_agg(jsonb_build_object(
        'mois', lm.mois,
        'demandees', (select count(*) from d where d.mois_demande = lm.mois),
        'montant_demande', (select coalesce(sum(montant), 0) from d where d.mois_demande = lm.mois),
        'approuvees', (select coalesce(sum(montant), 0) from d
                        where d.mois_demande = lm.mois and d.statut in ('approuvee', 'decaissee')),
        'refusees', (select count(*) from d where d.mois_demande = lm.mois and d.statut = 'refusee'),
        'decaissees', (select count(*) from d where d.mois_decaisse = lm.mois and d.statut = 'decaissee'),
        'montant_decaisse', (select coalesce(sum(montant), 0) from d
                              where d.mois_decaisse = lm.mois and d.statut = 'decaissee'))
        order by lm.mois), '[]') from les_mois lm),
    'par_profil', (select coalesce(jsonb_agg(jsonb_build_object(
        'profil', x.profil, 'nombre', x.nombre, 'montant', x.montant) order by x.montant desc), '[]')
       from (select d.profil, count(*) as nombre, sum(d.montant) as montant from d
              where d.statut = 'decaissee' and d.decaisse_le >= t1 and d.decaisse_le < t2 group by 1) x),
    'plus_grosses', (select coalesce(jsonb_agg(jsonb_build_object(
        'numero', x.numero, 'objet', x.objet, 'profil', x.profil, 'montant', x.montant, 'le', x.decaisse_le)
        order by x.montant desc), '[]')
       from (select * from d where d.statut = 'decaissee' and d.decaisse_le >= t1 and d.decaisse_le < t2
              order by d.montant desc limit 10) x),
    'en_attente', (select jsonb_build_object('nombre', count(*), 'montant', coalesce(sum(montant), 0))
                     from d where d.statut in ('demandee', 'validee_responsable')),
    'a_decaisser', (select jsonb_build_object('nombre', count(*), 'montant', coalesce(sum(montant), 0))
                      from d where d.statut = 'approuvee'),
    'delai_decision_jours', (select round(avg(extract(epoch from (d.decision_le - d.cree_le)) / 86400)::numeric, 1)
                               from d where d.decision_le is not null and d.cree_le >= t1 and d.cree_le < t2)
  ) into depenses;

  -- ---------- Les effectifs (aujourd'hui, et les mouvements) ----------
  with en_poste as (select * from public.rh_employes where etat in ('actif', 'bloque'))
  select jsonb_build_object(
    'par_etat', (select coalesce(jsonb_object_agg(etat, n), '{}')
                   from (select etat, count(*) as n from public.rh_employes group by etat) x),
    'en_poste', (select count(*) from en_poste),
    'par_statut', (select coalesce(jsonb_object_agg(statut, n), '{}')
                     from (select statut, count(*) as n from en_poste group by statut) x),
    'par_sexe', (select coalesce(jsonb_object_agg(sexe, n), '{}')
                   from (select sexe, count(*) as n from en_poste group by sexe) x),
    'par_profil', (select coalesce(jsonb_agg(jsonb_build_object('profil', x.profil, 'effectif', x.n,
                       'masse_base', x.masse) order by x.n desc), '[]')
                     from (select coalesce(p.nom, 'Sans profil') as profil, count(*) as n,
                                  sum(e.salaire_base) as masse
                             from en_poste e left join public.rh_profils p on p.id = e.profil_id group by 1) x),
    'par_niveau', (select coalesce(jsonb_object_agg(niveau, n), '{}')
                     from (select coalesce(nullif(niveau_etude, ''), 'Non renseigné') as niveau, count(*) as n
                             from en_poste group by 1) x),
    'age_moyen', (select round(avg(extract(year from age(aujourdhui, date_naissance)))::numeric, 1)
                    from en_poste where date_naissance is not null),
    'anciennete_moyenne_mois', (select round(avg((aujourdhui - date_embauche) / 30.44)::numeric, 1) from en_poste),
    'masse_base', (select coalesce(sum(salaire_base), 0) from en_poste),
    'salaire_base_moyen', (select coalesce(round(avg(salaire_base)), 0) from en_poste),
    'mouvements', (select coalesce(jsonb_agg(jsonb_build_object(
        'mois', lm.mois,
        'embauches', (select count(*) from public.rh_employes e
                       where e.etat in ('actif', 'bloque', 'sorti', 'supprime')
                         and date_trunc('month', e.date_embauche)::date = lm.mois),
        'sorties', (select count(*) from public.rh_employes e
                     where e.date_sortie is not null and date_trunc('month', e.date_sortie)::date = lm.mois))
        order by lm.mois), '[]')
       from (select generate_series(m1, m2, interval '1 month')::date as mois) lm)
  ) into effectifs;

  -- ---------- Missions et rapports ----------
  with mi as (select m.*, coalesce(p.nom, '—') as profil from public.rh_missions m
                left join public.rh_profils p on p.id = m.profil_id
               where m.cree_le >= t1 and m.cree_le < t2),
  ra as (select * from public.rh_rapports where cree_le >= t1 and cree_le < t2)
  select jsonb_build_object(
    'missions', (select count(*) from mi),
    'missions_par_statut', (select coalesce(jsonb_object_agg(statut, n), '{}')
                              from (select statut, count(*) as n from mi group by statut) x),
    'cloturees_a_temps', (select count(*) from mi where statut = 'cloturee'
                            and (rapport_le at time zone 'Africa/Porto-Novo')::date <= echeance),
    'cloturees_en_retard', (select count(*) from mi where statut = 'cloturee'
                              and (rapport_le at time zone 'Africa/Porto-Novo')::date > echeance),
    'en_retard_aujourdhui', (select count(*) from public.rh_missions
                               where statut in ('acceptee', 'a_reprendre') and echeance < aujourdhui),
    'delai_reponse_heures', (select round(avg(extract(epoch from (reponse_le - cree_le)) / 3600)::numeric, 1)
                               from mi where reponse_le is not null),
    'missions_par_profil', (select coalesce(jsonb_agg(jsonb_build_object(
        'profil', x.profil, 'creees', x.creees, 'cloturees', x.cloturees, 'refusees', x.refusees,
        'en_cours', x.en_cours) order by x.creees desc), '[]')
       from (select profil, count(*) as creees,
                    count(*) filter (where statut = 'cloturee') as cloturees,
                    count(*) filter (where statut = 'refusee') as refusees,
                    count(*) filter (where statut in ('proposee', 'acceptee', 'rapport_remis', 'a_reprendre')) as en_cours
               from mi group by profil) x),
    'rapports', (select count(*) from ra where statut <> 'brouillon'),
    'rapports_par_statut', (select coalesce(jsonb_object_agg(statut, n), '{}')
                              from (select statut, count(*) as n from ra group by statut) x),
    'delai_validation_jours', (select round(avg(extract(epoch from (decision_le - publie_le)) / 86400)::numeric, 1)
                                 from ra where decision_le is not null and publie_le is not null)
  ) into activite;

  -- ---------- Les revenus de BIZZOO et le résultat (CEO, superadministrateur) ----------
  if v_revenus then
    with les_mois as (select generate_series(m1, m2, interval '1 month')::date as mois),
    c as (select co.*, date_trunc('month', co.paye_le at time zone 'Africa/Porto-Novo')::date as mois
            from public.commandes co
           where co.etat = 'payee' and co.paye_le >= t1 and co.paye_le < t2),
    cm as (select c.mois, count(*) as commandes, coalesce(sum(c.total), 0) as encaisse,
                  coalesce(sum(c.frais_livraison), 0) as frais, coalesce(sum(c.remise), 0) as remises
             from c group by c.mois),
    lm2 as (select c.mois,
                   coalesce(sum(greatest(0, l.prix - l.prix_bizzoo) * l.quantite), 0) as marge,
                   coalesce(sum(l.prix_bizzoo * l.quantite), 0) as reverse
              from public.commande_lignes l join c on c.id = l.commande_id
             where l.etat <> 'annulee' group by c.mois),
    g as (select date_trunc('month', credite_le at time zone 'Africa/Porto-Novo')::date as mois,
                 coalesce(sum(montant), 0) as gains
            from public.gains_livreurs where credite_le >= t1 and credite_le < t2 group by 1),
    s as (select mois, sum(brut + charges_patronales) as cout from public.rh_fiches_paie
           where statut <> 'calculee' and mois between m1 and m2 group by mois),
    dp as (select date_trunc('month', decaisse_le at time zone 'Africa/Porto-Novo')::date as mois,
                  sum(montant) as montant
             from public.rh_depenses where statut = 'decaissee' and decaisse_le >= t1 and decaisse_le < t2
            group by 1),
    pm as (select lm.mois,
                  coalesce(cm.commandes, 0) as commandes, coalesce(cm.encaisse, 0) as encaisse,
                  coalesce(cm.frais, 0) as frais, coalesce(cm.remises, 0) as remises,
                  coalesce(lm2.marge, 0) as marge, coalesce(lm2.reverse, 0) as reverse,
                  coalesce(g.gains, 0) as gains, coalesce(s.cout, 0) as cout_salaires, coalesce(dp.montant, 0) as montant_depenses
             from les_mois lm
             left join cm on cm.mois = lm.mois
             left join lm2 on lm2.mois = lm.mois
             left join g on g.mois = lm.mois
             left join s on s.mois = lm.mois
             left join dp on dp.mois = lm.mois)
    select coalesce(jsonb_agg(jsonb_build_object(
        'mois', mois, 'commandes', commandes, 'encaisse', encaisse, 'reverse_boutiques', reverse,
        'marge', marge, 'frais_livraison', frais, 'remises', remises, 'gains_livreurs', gains,
        'revenus', marge + frais - remises - gains,
        'salaires', cout_salaires, 'depenses', montant_depenses,
        'resultat', marge + frais - remises - gains - cout_salaires - montant_depenses) order by mois), '[]')
      into revenus from pm;
  end if;

  return jsonb_build_object(
    'periode', jsonb_build_object('depuis', m1, 'jusqu', fin),
    'droits', jsonb_build_object('revenus', v_revenus),
    'salaires', salaires, 'depenses', depenses, 'effectifs', effectifs, 'activite', activite,
    'revenus', revenus);
end $$;

