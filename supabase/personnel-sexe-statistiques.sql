-- =========================================================
-- BIZZOO Personnel : les statistiques internes et le sexe non renseigné
--
-- Depuis l'import du personnel, le sexe d'un employé peut rester vide
-- jusqu'à ce qu'il le complète. La répartition par sexe de rh_finances
-- en faisait une clé nulle, et la base refusait tout le calcul
-- (« field name must not be null ») : Salaires, Dépenses, Effectifs,
-- Missions et Revenus restaient vides. Le sexe vide compte désormais
-- sous « NR » (non renseigné).
-- =========================================================

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
    'par_sexe', (select coalesce(jsonb_object_agg(coalesce(sexe, 'NR'), n), '{}')
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

