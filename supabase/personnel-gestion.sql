-- =========================================================
-- BIZZOO Personnel : bloquer, supprimer, et les statistiques internes
--
-- Le CEO et le superadministrateur de BIZZOO bloquent (l'accès est
-- coupé, la paie continue), débloquent et suppriment un employé. Une
-- suppression efface tout s'il n'a ni paie validée ni avance ; sinon
-- la fiche est archivée : identité, n° CNSS et paie gardés, accès,
-- messages, boîte mail et données personnelles effacés. Chaque geste
-- est noté dans rh_journal_employes.
--
-- rh_finances : salaires, dépenses, effectifs, missions et rapports
-- mois par mois pour l'administration ; revenus de BIZZOO et résultat
-- pour le CEO et le superadministrateur seuls.
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

-- ---------- Les états « bloqué » et « supprimé » ----------
-- Bloqué : l'accès est coupé (rh_moi() ne le reconnaît plus), la paie
-- continue, le blocage se lève. Supprimé : la fiche sort des listes,
-- l'accès et les données personnelles s'effacent ; ne restent que
-- l'identité (nom, matricule, n° CNSS) et la paie déjà validée.
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'rh_employes_etat_check'
               and pg_get_constraintdef(oid) not like '%supprime%') then
    alter table public.rh_employes drop constraint rh_employes_etat_check;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_employes_etat_check') then
    alter table public.rh_employes add constraint rh_employes_etat_check
      check (etat in ('en_attente', 'actif', 'refuse', 'sorti', 'bloque', 'supprime'));
  end if;
end $$;

-- Ce qui a été bloqué, débloqué, supprimé : par qui, quand, pourquoi.
-- Sans clé étrangère : la ligne survit à l'employé effacé.
create table if not exists public.rh_journal_employes (
  id          bigint generated always as identity primary key,
  employe_id  uuid not null,
  matricule   text not null default '',
  nom         text not null default '',
  action      text not null check (action in ('bloque', 'debloque', 'supprime', 'efface')),
  motif       text not null default '',
  par_compte  uuid,
  par_nom     text not null default '',
  le          timestamptz not null default now()
);
create index if not exists rh_journal_employes_employe on public.rh_journal_employes (employe_id, id);

/** Le CEO et le superadministrateur de BIZZOO, seuls. */
create or replace function public.rh_peut_bloquer() returns boolean
language sql stable security definer set search_path = public as $$
  select public.rh_est_ceo() or public.est_super();
$$;

/** Bloquer (ou débloquer) l'accès d'un employé en poste. */
create or replace function public.rh_bloquer_employe(qui uuid, bloquer boolean, motif text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare
  e public.rh_employes;
  auteur text;
begin
  if not public.rh_peut_bloquer() then
    raise exception 'Seuls le CEO et le superadministrateur bloquent un employé';
  end if;
  select * into e from public.rh_employes where id = qui for update;
  if not found then
    raise exception 'Employé introuvable';
  end if;
  if e.ceo then
    raise exception 'Le CEO ne se bloque pas';
  end if;
  if e.compte_id is not null and e.compte_id = auth.uid() then
    raise exception 'Vous ne vous bloquez pas vous-même';
  end if;
  if bloquer and e.etat <> 'actif' then
    raise exception 'Seul un employé en poste se bloque';
  end if;
  if not bloquer and e.etat <> 'bloque' then
    raise exception 'Cet employé n''est pas bloqué';
  end if;
  if bloquer and length(btrim(coalesce(motif, ''))) = 0 then
    raise exception 'Dites pourquoi vous bloquez cet employé';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_employes set etat = case when bloquer then 'bloque' else 'actif' end where id = qui;
  perform set_config('rh.decision', '', true);
  select coalesce(btrim(x.prenoms || ' ' || x.nom), '') into auteur
    from public.rh_employes x where x.compte_id = auth.uid();
  insert into public.rh_journal_employes (employe_id, matricule, nom, action, motif, par_compte, par_nom)
  values (e.id, coalesce(e.matricule, ''), btrim(e.prenoms || ' ' || e.nom),
          case when bloquer then 'bloque' else 'debloque' end, btrim(coalesce(motif, '')),
          auth.uid(), coalesce(auteur, 'Superadministrateur'));
end $$;

/** Supprimer un employé. Sans paie validée ni avance : tout s'efface.
    Avec : la fiche est archivée (« supprime ») — identité et paie
    gardées pour la comptabilité et la CNSS, tout le reste effacé. */
create or replace function public.rh_supprimer_employe(qui uuid, motif text default '')
returns text
language plpgsql security definer set search_path = public as $$
declare
  e public.rh_employes;
  auteur text;
  garder boolean;
begin
  if not public.rh_peut_bloquer() then
    raise exception 'Seuls le CEO et le superadministrateur suppriment un employé';
  end if;
  select * into e from public.rh_employes where id = qui for update;
  if not found or e.etat = 'supprime' then
    raise exception 'Employé introuvable';
  end if;
  if e.ceo then
    raise exception 'Le CEO ne se supprime pas';
  end if;
  if e.compte_id is not null and e.compte_id = auth.uid() then
    raise exception 'Vous ne vous supprimez pas vous-même';
  end if;
  if length(btrim(coalesce(motif, ''))) = 0 then
    raise exception 'Dites pourquoi vous supprimez cet employé';
  end if;
  select coalesce(btrim(x.prenoms || ' ' || x.nom), '') into auteur
    from public.rh_employes x where x.compte_id = auth.uid();
  garder := exists (select 1 from public.rh_fiches_paie where employe_id = qui and statut <> 'calculee')
         or exists (select 1 from public.rh_avances where employe_id = qui);

  insert into public.rh_journal_employes (employe_id, matricule, nom, action, motif, par_compte, par_nom)
  values (e.id, coalesce(e.matricule, ''), btrim(e.prenoms || ' ' || e.nom),
          case when garder then 'supprime' else 'efface' end, btrim(motif),
          auth.uid(), coalesce(auteur, 'Superadministrateur'));

  update public.rh_profils set responsable_id = null where responsable_id = qui;
  if not garder then
    -- Ses messages, ses lectures, sa boîte mail et ses brouillons de
    -- paie partent avec lui (clés « on delete cascade »).
    delete from public.rh_employes where id = qui;
    return 'efface';
  end if;

  delete from public.rh_messages where auteur_id = qui or destinataire_id = qui;
  delete from public.rh_lectures where employe_id = qui;
  delete from public.rh_boites_mail where employe_id = qui;
  delete from public.rh_fiches_paie where employe_id = qui and statut = 'calculee';
  perform set_config('rh.decision', 'oui', true);
  update public.rh_employes
     set etat = 'supprime', compte_id = null, email_pro = null, telephone = '', email_perso = '',
         adresse = '', date_naissance = null, compte_paiement = '', infos = '', profil_id = null,
         administration = false, peut_decaisser = false,
         date_sortie = coalesce(date_sortie, (now() at time zone 'Africa/Porto-Novo')::date),
         motif_refus = btrim(motif)
   where id = qui;
  perform set_config('rh.decision', '', true);
  return 'archive';
end $$;

-- ---------- Les statistiques internes ----------
/** Salaires, dépenses, effectifs, missions et rapports, mois par mois ;
    et, pour le CEO et le superadministrateur seuls, les revenus de
    BIZZOO et le résultat. Les mois entiers qui couvrent la période. */
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

-- ---------- Les droits ----------
alter table public.rh_journal_employes enable row level security;
drop policy if exists "rh journal employes lecture" on public.rh_journal_employes;
create policy "rh journal employes lecture" on public.rh_journal_employes
  for select to authenticated using (public.rh_est_admin() or public.est_super());
revoke all on table public.rh_journal_employes from public, anon, authenticated;
grant all on table public.rh_journal_employes to service_role;
grant select on public.rh_journal_employes to authenticated;

do $$
declare f text;
begin
  foreach f in array array['rh_peut_bloquer()', 'rh_bloquer_employe(uuid, boolean, text)',
                           'rh_supprimer_employe(uuid, text)', 'rh_finances(date, date)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
end $$;

-- ---------- Ce qui tient compte des nouveaux états (copies de schema.sql) ----------
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

create or replace function public.rh_employe_apres() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.profil_id is distinct from old.profil_id or new.etat not in ('actif', 'bloque') then
    update public.rh_profils set responsable_id = null
     where responsable_id = new.id
       and (new.etat not in ('actif', 'bloque') or id is distinct from new.profil_id);
  end if;
  return null;
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
   where id = employe and etat in ('actif', 'bloque');
  if not found then
    raise exception 'Cet employé n''est pas en poste';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

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
  if e.etat not in ('actif', 'bloque', 'sorti') or d2 < d1 then
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

create or replace function public.rh_generer_paie_interne(mois date) returns int
language plpgsql security definer set search_path = public as $$
declare
  debut date := date_trunc('month', mois)::date;
  fin date := (date_trunc('month', mois) + interval '1 month - 1 day')::date;
  e record;
  combien int := 0;
begin
  for e in select id from public.rh_employes
            where (etat in ('actif', 'bloque') or (etat = 'sorti' and date_sortie >= debut))
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
                        and (x.etat in ('actif', 'bloque') or (x.etat = 'sorti' and x.date_sortie >= debut))
                        and x.date_embauche <= fin);
  return combien;
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
      'ceo', v_ceo, 'administration', v_admin, 'peut_decaisser', moi.peut_decaisser,
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
