-- =========================================================
-- BIZZOO Personnel : l'équipe au travail
--
-- 1. « Ma file » (#/file) : chaque alerte du suivi, des contrôles, de
--    l'argent et de la qualité devient une tâche confiée à un profil
--    (routage réglé par l'administration, onglet « Routage ») : « Je
--    prends », note de relance datée, appeler ou écrire sur WhatsApp à la
--    boutique ou au livreur, « Terminé ». Personne ne l'a prise après le
--    délai : elle remonte au responsable du profil. L'alerte disparue, la
--    tâche s'efface d'elle-même.
-- 2. Les alertes sur le téléphone des employés (Mon compte) : une tâche
--    nouvelle ou une escalade sonne une fois, sans montant ni nom de
--    client, hors des heures de silence de chacun. L'envoi passe par la
--    fonction Edge « rh-push » (Web Push) : à déployer, avec ses clés.
-- 3. Le bilan du matin (#/bilans et l'Accueil) : chaque jour à 7 h (heure
--    du Bénin), le lundi avec la semaine comparée à la précédente ;
--    montants pour l'administration seule.
--
-- Rien n'est posé sur les tables de la place de marché : ni déclencheur,
-- ni colonne. pg_cron programme la file (5 min), les alertes (5 min) et le
-- bilan (7 h) ; sans lui, l'écran rattrape la file et le bilan.
--
-- Après ce fichier, pour les alertes sur le téléphone :
--   1. fabriquer les clés : node tools/vapid-cles.mjs ;
--   2. secrets de la fonction : VAPID_PUBLIQUE, VAPID_PRIVEE, VAPID_SUJET ;
--   3. supabase functions deploy rh-push --no-verify-jwt ;
--   4. update public.rh_push_reglage
--         set url = 'https://<projet>.supabase.co/functions/v1/rh-push',
--             cle_publique = '<VAPID_PUBLIQUE>';
--
-- À coller tel quel dans l'éditeur SQL ; il se rejoue sans dommage.
-- =========================================================

-- ---------- Les aides (copies de schema.sql) ----------
-- (les fonctions qu'il emprunte, recopiées telles quelles)

create or replace function public.rh_moi() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
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

create or replace function public.rh_statut_ligne(etat text, confirme timestamptz, terrain text, contestee boolean)
returns int
language sql immutable set search_path = public as $$
  select case
    when etat = 'annulee' then 11
    when terrain = 'retournee' then 13
    when terrain = 'retour_en_cours' then 12
    when terrain = 'echouee' then 9
    when contestee then 10
    when confirme is not null then 8
    when etat = 'remise' then 6
    when etat = 'en_livraison' then 5
    when terrain = 'recupere' then 4
    when etat = 'preparee' then 3
    when etat = 'vue' then 2
    else 1 end;
$$;

create or replace function public.rh_statut_libelle(rang int) returns text
language sql immutable set search_path = public as $$
  select case rang
    when 0 then 'En attente de paiement'
    when 1 then 'Nouvelle commande'
    when 2 then 'Confirmée'
    when 3 then 'Commande préparée'
    when 4 then 'Colis récupéré'
    when 5 then 'En cours de livraison'
    when 6 then 'Livraison effectuée — confirmation en attente'
    when 8 then 'Livré et confirmé'
    when 9 then 'Livraison échouée'
    when 10 then 'Livraison contestée'
    when 11 then 'Annulée'
    when 12 then 'Retour en cours'
    when 13 then 'Retournée au marchand'
    when 14 then 'Clôturée'
    when 15 then 'Paiement échoué'
    else '' end;
$$;

create or replace function public.restes_par_boutique(cible text)
returns table (boutique_id text, a_encaisser bigint)
language plpgsql stable security definer set search_path = public as $$
declare lp jsonb;
begin
  select c.parts into lp from public.commandes c where c.id = cible;
  -- UNE COMMANDE D'AVANT LES CONDITIONS PAR BOUTIQUE (« parts » vide) :
  -- l'ancienne règle, celle d'un acompte unique réparti au prorata.
  if lp is null then
    return query
  with commande as (
    select c.total::numeric as total,
           greatest(0, coalesce(c.frais_livraison, 0))::numeric as frais,
           coalesce(c.verse, c.acompte, c.total)::numeric as deja
      from public.commandes c
     where c.id = cible
  ), parts as (
    select l.boutique_id as boutique,
           sum(l.prix * l.quantite)::numeric as brut,
           coalesce(sum(l.prix * l.quantite) filter (where l.etat <> 'annulee'), 0)::numeric as servi
      from public.commande_lignes l
     where l.commande_id = cible
     group by l.boutique_id
  ), reste as (
    -- Ce que vaut ce qui sera livré, remise déduite au prorata, moins ce
    -- qui est déjà versé.
    -- LES FRAIS DE LIVRAISON ne se réduisent pas au prorata : tant qu'il
    -- reste quelque chose à livrer, la course a lieu et coûte son prix.
    -- Tout annulé, il n'y a pas de course, donc pas de frais.
    select greatest(0, coalesce(round((c.total - c.frais) * sum(p.servi) / nullif(sum(p.brut), 0)), 0)
                       + case when sum(p.servi) > 0 then c.frais else 0 end
                       - c.deja) as du,
           sum(p.servi) as servi
      from commande c, parts p
     group by c.total, c.frais, c.deja
  ), repartie as (
    select p.boutique,
           coalesce(floor(r.du * p.servi / nullif(r.servi, 0)), 0) as part,
           row_number() over (order by p.servi desc, p.boutique) as rang,
           r.du
      from parts p, reste r
  )
  select x.boutique,
         (x.part + case when x.rang = 1 then x.du - sum(x.part) over () else 0 end)::bigint
    from repartie x;
    return;
  end if;
  -- (3.59.0) CHAQUE BOUTIQUE ENCAISSE SA PART, moins SON acompte : ce
  -- que valent ses articles servis, remise déduite au prorata, plus ses
  -- frais tant qu'il y a quelque chose à livrer.
  --
  -- CE QUE LE CLIENT A VERSÉ N'EST JAMAIS PERDU POUR LUI. Chaque boutique
  -- déduit d'abord son propre acompte ; ce qui a été versé en plus — un
  -- surplus, ou l'acompte d'une part annulée — diminue les autres parts
  -- au prorata, l'arrondi à la plus grosse.
  return query
    with commande as (
      select greatest(0, coalesce(c.remise, 0))::numeric as remise,
             -- (3.64.0) Au kilomètre, les frais de livraison se paient en ligne
             -- avec l'acompte, hors des parts des boutiques : ce versement-là
             -- n'allège le reste d'aucune d'elles.
             greatest(0, coalesce(c.verse, c.acompte, c.total)
                         - case when c.livraison is not null
                                then coalesce(c.frais_livraison, 0) else 0 end)::numeric as paye
        from public.commandes c where c.id = cible
    ), lignes as (
      select l.boutique_id as bou,
             sum(l.prix * l.quantite)::numeric as brut,
             coalesce(sum(l.prix * l.quantite) filter (where l.etat <> 'annulee'), 0)::numeric as servi
        from public.commande_lignes l
       where l.commande_id = cible
       group by l.boutique_id
    ), tout as (
      select sum(x.brut) as s from lignes x
    ), brutes as (
      select x.bou,
             greatest(0, round(x.servi - k.remise * x.servi / nullif(t.s, 0))
                         + case when x.servi > 0 then coalesce((lp -> x.bou ->> 'frais')::numeric, 0) else 0 end) as du
        from lignes x, tout t, commande k
    ), propres as (
      select b.bou, b.du,
             least(b.du, coalesce((lp -> b.bou ->> 'acompte')::numeric, 0)) as sien
        from brutes b
    ), credit as (
      select greatest(0, k.paye - coalesce(sum(p.sien), 0)) as reste_credit,
             coalesce(sum(p.du - p.sien), 0) as a_couvrir
        from propres p, commande k
       group by k.paye
    ), allege as (
      select p.bou, p.du - p.sien as du,
             case when c.a_couvrir > 0
                  then floor(least(c.reste_credit, c.a_couvrir) * (p.du - p.sien) / c.a_couvrir)
                  else 0 end as moins,
             least(c.reste_credit, c.a_couvrir) as credit,
             row_number() over (order by p.du - p.sien desc, p.bou) as rang
        from propres p, credit c
    )
    select a.bou,
           greatest(0, a.du - a.moins
                       - case when a.rang = 1 then a.credit - sum(a.moins) over () else 0 end)::bigint
      from allege a;
end $$;

create or replace function public.rh_suivi_donnees(t1 timestamptz, t2 timestamptz, une text default null)
returns setof jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r public.rh_reglages_suivi;
  maintenant timestamptz := now();
  -- Les seuils de la veille et des encaissements (personnel-controles.sql)
  -- se lisent par to_jsonb : sur une base où leurs colonnes manquent
  -- encore, la valeur de départ vaut, au lieu d'une erreur.
  v_prise_min int;
  v_position_min int;
  v_momopay_h int;
begin
  select * into r from public.rh_reglages_suivi where id;
  v_prise_min := coalesce((to_jsonb(r) ->> 'prise_course_min')::int, 30);
  v_position_min := coalesce((to_jsonb(r) ->> 'position_min')::int, 15);
  v_momopay_h := coalesce((to_jsonb(r) ->> 'momopay_h')::int, 48);
  return query
  with cmd as (
    select c.* from public.commandes c
     where (une is not null and c.id = une)
        or (une is null and c.cree_le >= t1 and c.cree_le < t2)
     order by c.cree_le desc
     limit 2000
  ),
  lig as (
    select l.*, b.nom as boutique_nom, coalesce(nullif(b.tel, ''), '') as boutique_tel,
           coalesce(nullif(pl.nom, ''), pl.email) as livreur_nom, coalesce(pl.tel, '') as livreur_tel,
           s.statut as terrain, s.motif as terrain_motif,
           exists (select 1 from public.reclamations rc
                    where rc.commande_id = l.commande_id and rc.sujet = 'non_recu'
                      and (rc.boutique_id is null or rc.boutique_id = l.boutique_id)
                      and rc.etat not in ('resolue', 'tranchee')) as contestee,
           (select min(j.le) from public.rh_journal_lignes j
             where j.ligne_id = l.id and j.quoi = 'etat' and j.valeur = 'vue') as vue_le,
           (select min(j.le) from public.rh_journal_lignes j
             where j.ligne_id = l.id and j.quoi = 'etat' and j.valeur = 'preparee') as preparee_le,
           (select min(j.le) from public.rh_journal_lignes j
             where j.ligne_id = l.id and j.quoi = 'etat' and j.valeur = 'remise') as remise_le
      from public.commande_lignes l
      join cmd c on c.id = l.commande_id
      left join public.boutiques b on b.id = l.boutique_id
      left join public.profils pl on pl.id = l.livreur_id
      left join public.rh_suivi_lignes s on s.ligne_id = l.id
  ),
  lig2 as (
    select x.*, public.rh_statut_ligne(x.etat, x.confirme_le, x.terrain, x.contestee) as rang
      from lig x
  )
  select jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'cree_le', c.cree_le, 'paye_le', c.paye_le, 'etat', c.etat,
    -- (3.68.0) D'où vient la commande : passée dans l'application, ou prise
    -- sur WhatsApp et saisie par l'équipe (« Faire livrer »). Lue par
    -- « to_jsonb » : une base sans la colonne répond « Depuis APP ».
    'source', case when to_jsonb(c) ->> 'origine' = 'whatsapp' then 'Par whatsapp' else 'Depuis APP' end,
    'client', jsonb_build_object('nom', c.client_nom,
                                 'tel', btrim(case when coalesce(c.client_indicatif, '') <> '' and c.client_indicatif <> '229'
                                                   then '+' || c.client_indicatif || ' ' else '' end || coalesce(c.client_tel, '')),
                                 'adresse', c.client_adresse,
                                 'zone', coalesce(nullif(sc.zone, ''), public.rh_zone_de(c.client_adresse), ''),
                                 'zone_corrigee', coalesce(sc.zone, '') <> ''),
    'lignes', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', x.id, 'boutique_id', x.boutique_id, 'boutique', coalesce(x.boutique_nom, x.boutique_id),
                 'boutique_tel', x.boutique_tel, 'nom', x.nom, 'code', x.code, 'quantite', x.quantite,
                 'prix', x.prix, 'etat', x.etat, 'rang', x.rang, 'statut', public.rh_statut_libelle(x.rang),
                 'terrain', x.terrain, 'terrain_motif', coalesce(x.terrain_motif, ''),
                 'livreur', x.livreur_nom, 'livreur_tel', x.livreur_tel, 'livreur_id', x.livreur_id,
                 'confirme_le', x.confirme_le, 'vue_le', x.vue_le, 'remise_le', x.remise_le)
               order by x.boutique_nom, x.nom) from lig2 x where x.commande_id = c.id), '[]'),
    'articles', coalesce((select string_agg(x.quantite || ' × ' || x.nom
                                            || case when x.etat = 'annulee' then ' (annulé)' else '' end, ' ; '
                                            order by x.boutique_nom, x.nom)
                            from lig2 x where x.commande_id = c.id), ''),
    'marchands', coalesce((select string_agg(distinct coalesce(x.boutique_nom, x.boutique_id)
                                             || case when x.boutique_tel <> '' then ' / ' || x.boutique_tel else '' end, ' ; ')
                             from lig2 x where x.commande_id = c.id), ''),
    'livreurs', coalesce((select string_agg(distinct x.livreur_nom
                                            || case when x.livreur_tel <> '' then ' / ' || x.livreur_tel else '' end, ' ; ')
                            from lig2 x where x.commande_id = c.id and x.livreur_nom is not null), ''),
    'frais', coalesce(c.frais_livraison, 0), 'total', c.total,
    'reste', case when c.etat = 'payee' then
               coalesce((select sum(greatest(0, rr.a_encaisser - coalesce(e.montant, 0)))
                           from public.restes_par_boutique(c.id) rr
                           left join public.encaissements e on e.commande_id = c.id and e.boutique_id = rr.boutique_id), 0)
             else 0 end,
    'rang', st.rang, 'statut', public.rh_statut_libelle(st.rang),
    'confirmation', case
       when not exists (select 1 from lig2 x where x.commande_id = c.id and x.etat <> 'annulee') then '—'
       when not exists (select 1 from lig2 x where x.commande_id = c.id and x.etat <> 'annulee' and x.confirme_le is null) then 'Oui'
       when exists (select 1 from lig2 x where x.commande_id = c.id and x.confirme_le is not null) then 'Partielle'
       else 'Non' end,
    -- La durée du document : du « vu » du marchand au « je l'ai reçu » du client.
    'delai_h', (select round(max(extract(epoch from (x.confirme_le - x.vue_le)) / 3600)::numeric, 1)
                  from lig2 x where x.commande_id = c.id and x.confirme_le is not null and x.vue_le is not null),
    'observations', coalesce(sc.observations, ''),
    'incidents_ouverts', (select count(*) from public.rh_incidents i where i.commande_id = c.id and i.resolu_le is null),
    'cloturee_le', sc.cloturee_le,
    'alertes', case when c.etat <> 'payee' or sc.cloturee_le is not null then '[]'::jsonb else (
      select coalesce(jsonb_agg(a), '[]') from (
        select 'non_vue' as a where exists (select 1 from lig2 x where x.commande_id = c.id and x.etat = 'nouvelle')
                                 and maintenant - c.paye_le > make_interval(hours => r.vue_h)
        union all
        select 'retard_preparation' where exists (select 1 from lig2 x where x.commande_id = c.id and x.etat = 'vue'
                                 and maintenant - coalesce(x.vue_le, c.paye_le) > make_interval(hours => r.preparation_h))
        union all
        select 'retard_livraison' where exists (select 1 from lig2 x where x.commande_id = c.id and x.rang < 6)
                                 and maintenant - c.paye_le > make_interval(hours => r.livraison_h)
        union all
        select 'sans_confirmation' where exists (select 1 from lig2 x where x.commande_id = c.id and x.rang = 6
                                 and maintenant - coalesce(x.remise_le, c.paye_le) > make_interval(hours => r.confirmation_h))
        union all
        select 'contestee' where exists (select 1 from lig2 x where x.commande_id = c.id and x.contestee)
        union all
        select 'echec' where exists (select 1 from lig2 x where x.commande_id = c.id and x.rang in (9, 12))
        union all
        select 'incident' where exists (select 1 from public.rh_incidents i where i.commande_id = c.id and i.resolu_le is null)
        union all
        select 'refus_course' where exists (select 1 from public.refus_courses f where f.commande_id = c.id)
        union all
        select 'encaissement_conteste' where exists (select 1 from public.encaissements e
                                                     where e.commande_id = c.id and e.conteste_le is not null)
        union all
        -- Payée (ou préparée) et personne n'a pris la course : la demande
        -- part à tous les livreurs au paiement, elle devrait trouver preneur.
        select 'course_sans_livreur' where exists (select 1 from lig2 x where x.commande_id = c.id
                                 and x.etat in ('nouvelle', 'vue', 'preparee') and x.livreur_id is null
                                 and maintenant - coalesce(x.preparee_le, c.paye_le) > make_interval(mins => v_prise_min))
        union all
        -- En route, et son téléphone n'envoie plus rien : compté depuis sa
        -- dernière position, ou depuis qu'il a accepté la course.
        select 'livreur_muet' where exists (select 1 from lig2 x
                                 left join public.positions_livreurs pp on pp.profil_id = x.livreur_id
                                 where x.commande_id = c.id and x.etat = 'en_livraison' and x.livreur_id is not null
                                   and maintenant - greatest(pp.enregistre_le, x.recu_le, c.paye_le)
                                       > make_interval(mins => v_position_min))
        union all
        select 'momopay_non_verifie' where exists (select 1 from public.encaissements e
                                 where e.commande_id = c.id and e.mode = 'mobile_money' and e.remis_le is null
                                   and maintenant - e.encaisse_le > make_interval(hours => v_momopay_h))
        union all
        select 'encaissement_ecart' where exists (select 1 from public.encaissements e
                                 where e.commande_id = c.id and e.montant <> e.du)
      ) al)
    end)
  from cmd c
  left join public.rh_suivi_commandes sc on sc.commande_id = c.id
  cross join lateral (
    select case
      when sc.cloturee_le is not null then 14
      when c.etat = 'a_payer' then 0
      when c.etat = 'echouee' then 15
      when c.etat = 'annulee' then 11
      when not exists (select 1 from lig2 x where x.commande_id = c.id and x.rang <> 11) then 11
      when exists (select 1 from lig2 x where x.commande_id = c.id and x.rang = 10) then 10
      when exists (select 1 from lig2 x where x.commande_id = c.id and x.rang = 9) then 9
      when exists (select 1 from lig2 x where x.commande_id = c.id and x.rang = 12) then 12
      else (select min(x.rang) from lig2 x where x.commande_id = c.id and x.rang <> 11)
    end as rang) st
  order by c.cree_le desc;
end $$;

create or replace function public.rh_controles_seuils() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'prise_course_min', coalesce((x.j ->> 'prise_course_min')::int, 30),
    'position_min', coalesce((x.j ->> 'position_min')::int, 15),
    'momopay_h', coalesce((x.j ->> 'momopay_h')::int, 48),
    'especes_h', coalesce((x.j ->> 'especes_h')::int, 24),
    'plafond_nb', coalesce((x.j ->> 'plafond_nb')::int, 3))
    from (select coalesce((select to_jsonb(r) from public.rh_reglages_suivi r where r.id), '{}'::jsonb) as j) x;
$$;

create or replace function public.rh_argent_seuils() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'annonce_min', coalesce((x.j ->> 'annonce_min')::int, 30),
    'dette_j', coalesce((x.j ->> 'dette_j')::int, 5),
    'remboursement_j', coalesce((x.j ->> 'remboursement_j')::int, 7))
    from (select coalesce((select to_jsonb(r) from public.rh_reglages_suivi r where r.id), '{}'::jsonb) as j) x;
$$;

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

create or replace function public.rh_rembourse_du(cible text) returns bigint
language plpgsql stable security definer set search_path = public as $$
declare
  c public.commandes%rowtype;
  paye numeric;
  brut numeric;
  servi numeric;
  frais numeric;
begin
  select * into c from public.commandes where id = cible;
  if not found or c.paye_le is null then
    return 0;
  end if;
  paye := greatest(0, coalesce(c.verse, c.acompte, c.total));
  if c.etat = 'annulee' then
    return paye::bigint;
  end if;
  select coalesce(sum(l.prix::numeric * l.quantite), 0),
         coalesce(sum(l.prix::numeric * l.quantite) filter (where l.etat <> 'annulee'), 0)
    into brut, servi
    from public.commande_lignes l where l.commande_id = cible;
  if brut = 0 or servi >= brut then
    return 0;
  end if;
  frais := case
    when servi <= 0 then 0
    -- Frais par boutique (3.59.0) : ceux des boutiques qui livrent encore.
    when c.livraison is null and c.parts is not null then
      coalesce((select sum(coalesce((c.parts -> b.bou ->> 'frais')::numeric, 0))
                  from (select distinct l.boutique_id as bou from public.commande_lignes l
                         where l.commande_id = cible and l.etat <> 'annulee') b), 0)
    else greatest(0, coalesce(c.frais_livraison, 0)) end;
  return greatest(0, paye - (round(greatest(0, c.total - coalesce(c.frais_livraison, 0)) * servi / brut) + frais))::bigint;
end $$;

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

-- Les droits des copies, tels que schema.sql les pose : sur une base où
-- elles manquaient, une fonction neuve serait sinon ouverte à tous.
revoke all on function public.restes_par_boutique(text) from public, anon, authenticated;
revoke all on function public.rh_suivi_donnees(timestamptz, timestamptz, text) from public, anon, authenticated;
revoke all on function public.rh_zone_de(text) from public, anon, authenticated;
revoke all on function public.rh_statut_ligne(text, timestamptz, text, boolean) from public, anon, authenticated;
revoke all on function public.rh_statut_libelle(int) from public, anon, authenticated;
revoke all on function public.rh_cle(text) from public, anon, authenticated;
revoke all on function public.rh_controles_seuils() from public, anon;
grant execute on function public.rh_controles_seuils() to authenticated, service_role;
revoke all on function public.rh_argent_seuils() from public, anon;
grant execute on function public.rh_argent_seuils() to authenticated, service_role;
revoke all on function public.rh_qualite_seuils() from public, anon;
grant execute on function public.rh_qualite_seuils() to authenticated, service_role;
revoke all on function public.rh_rembourse_du(text) from public, anon, authenticated;
grant execute on function public.rh_rembourse_du(text) to service_role;
revoke all on function public.rh_sav_ouvertes() from public, anon, authenticated;
grant execute on function public.rh_sav_ouvertes() to service_role;
revoke all on function public.rh_ventes_30j() from public, anon, authenticated;
grant execute on function public.rh_ventes_30j() to service_role;

-- =========================================================
-- BIZZOO Personnel : l'équipe au travail (lot D)
-- =========================================================
-- 1. MA FILE DU JOUR. Les alertes du suivi, des contrôles, de l'argent et
--    de la qualité deviennent des TÂCHES (rh_taches), confiées à un profil
--    selon un routage que l'administration règle (rh_routage_alertes :
--    type d'alerte → profil, délai d'escalade). « Je prends », une note de
--    relance datée, « Terminé ». Une tâche que personne ne prend remonte au
--    responsable du profil après le délai ; une tâche dont l'alerte n'existe
--    plus disparaît d'elle-même. Aucun montant dans une tâche.
-- 2. LES ALERTES SUR LE TÉLÉPHONE. Chaque employé abonne son téléphone
--    (rh_push_abonnements), choisit ses types d'alerte et ses heures de
--    silence (rh_push_preferences). Une tâche nouvelle, ou une escalade,
--    part UNE fois par personne (rh_alertes_envoyees) : la fonction Edge
--    « rh-push » relit tout ici, avec la clé de service, et l'envoie en
--    Web Push. Le message ne porte ni montant ni nom de client.
-- 3. LE BILAN DU MATIN. Chaque jour à 7 h (heure du Bénin), un résumé dans
--    rh_bilans ; le lundi, la semaine écoulée comparée à la précédente.
--    Complet (montants) pour l'administration, le CEO et le
--    superadministrateur ; sans montants pour les responsables de profil.
--
-- Rien n'est posé sur les tables de la place de marché : ni déclencheur, ni
-- colonne. Tout se lit ; seules les tables rh_ s'écrivent. Sans pg_cron,
-- la file se recalcule à l'ouverture de « Ma file » et le bilan à la
-- première lecture après 7 h ; sans pg_net ou sans l'adresse de la
-- fonction Edge (rh_push_reglage), rien ne part et rien ne casse.

-- ---------- Le catalogue des alertes ----------
/** Les types d'alerte qu'on peut confier à un profil : clé, libellé, menu
    d'origine. Une seule liste, lue par le routage, la file et le push. */
create or replace function public.rh_alertes_types() returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_agg(jsonb_build_object('type', x.t, 'libelle', x.l, 'groupe', x.g) order by x.n)
    from (values
      (1, 'non_vue', 'Commande pas vue par la boutique', 'Suivi des commandes'),
      (2, 'retard_preparation', 'Préparation en retard', 'Suivi des commandes'),
      (3, 'retard_livraison', 'Livraison en retard', 'Suivi des commandes'),
      (4, 'sans_confirmation', 'Livrée, sans confirmation du client', 'Suivi des commandes'),
      (5, 'contestee', 'Livraison contestée', 'Suivi des commandes'),
      (6, 'echec', 'Échec ou retour de livraison', 'Suivi des commandes'),
      (7, 'incident', 'Incident ouvert', 'Suivi des commandes'),
      (8, 'course_sans_livreur', 'Course sans livreur', 'Suivi des commandes'),
      (9, 'livreur_muet', 'Livreur en route sans position', 'Suivi des commandes'),
      (10, 'momopay_non_verifie', 'MoMoPay pas vérifié', 'Suivi des commandes'),
      (11, 'encaissement_ecart', 'Écart d''encaissement', 'Suivi des commandes'),
      (12, 'encaissement_conteste', 'Encaissement contesté', 'Suivi des commandes'),
      (13, 'reglage_a_approuver', 'Réglage sensible à approuver', 'Contrôles'),
      (14, 'encaissement_ancien', 'Encaissement à la livraison qui attend', 'Contrôles'),
      (15, 'paiement_a_rapprocher', 'Paiement à rapprocher', 'Argent'),
      (16, 'remboursement_en_retard', 'Remboursement en retard', 'Argent'),
      (17, 'dette_ancienne', 'Demande d''argent qui attend', 'Argent'),
      (18, 'sav_sans_reponse', 'Réclamation sans réponse de la boutique', 'Qualité'),
      (19, 'sav_escalade', 'Réclamation escaladée à trancher', 'Qualité'),
      (20, 'rupture_a_appeler', 'Rupture d''un produit qui se vend', 'Qualité'),
      (21, 'file_en_retard', 'File d''Admin en retard', 'Qualité')) as x(n, t, l, g);
$$;

/** Le libellé d'un type d'alerte. */
create or replace function public.rh_alerte_libelle(v_type text) returns text
language sql immutable set search_path = public as $$
  select coalesce((select x ->> 'libelle' from jsonb_array_elements(public.rh_alertes_types()) x
                    where x ->> 'type' = v_type), v_type);
$$;

-- ---------- Les tables ----------
-- Le routage : quel profil reçoit quel type d'alerte, et au bout de combien
-- de minutes une tâche que personne n'a prise remonte. Sans profil : la
-- tâche reste à l'administration.
create table if not exists public.rh_routage_alertes (
  type          text primary key,
  profil_id     uuid references public.rh_profils(id) on delete set null,
  escalade_min  int not null default 30 check (escalade_min between 5 and 10080),
  actif         boolean not null default true,
  maj_le        timestamptz not null default now(),
  maj_par       text not null default ''
);
alter table public.rh_routage_alertes enable row level security;
revoke all on table public.rh_routage_alertes from public, anon, authenticated;
grant all on table public.rh_routage_alertes to service_role;
insert into public.rh_routage_alertes (type)
select x ->> 'type' from jsonb_array_elements(public.rh_alertes_types()) x
on conflict (type) do nothing;

-- Les tâches : une par alerte (sa clé), pour toujours ; elle se rouvre si
-- l'alerte revient après avoir disparu, même si elle avait été terminée.
create table if not exists public.rh_taches (
  id           bigserial primary key,
  cle          text not null unique,
  type         text not null,
  libelle      text not null,
  commande_id  text references public.commandes(id) on delete cascade,
  boutique_id  text,
  livreur_id   uuid,
  lien         text not null default '',
  profil_id    uuid references public.rh_profils(id) on delete set null,
  etat         text not null default 'ouverte' check (etat in ('ouverte', 'prise', 'terminee', 'disparue')),
  cree_le      timestamptz not null default now(),
  vue_le       timestamptz not null default now(),
  prise_par    uuid references public.rh_employes(id) on delete set null,
  prise_nom    text not null default '',
  prise_le     timestamptz,
  escalade_le  timestamptz,
  terminee_le  timestamptz,
  terminee_nom text not null default '',
  disparue_le  timestamptz
);
create index if not exists rh_taches_ouvertes on public.rh_taches (etat, profil_id) where etat in ('ouverte', 'prise');
-- « occurrence » : combien de fois l'alerte est revenue. Elle entre dans la
-- clé d'envoi des alertes poussées : une alerte revenue sonne de nouveau
-- (la première garde la clé nue, celle des envois déjà notés).
-- « confiee_le » : depuis quand la tâche attend son profil actuel. Le délai
-- d'escalade se compte de là : un profil qui reçoit une tâche par un
-- changement de routage a tout son délai pour la prendre.
alter table public.rh_taches add column if not exists occurrence int not null default 1;
alter table public.rh_taches add column if not exists confiee_le timestamptz;
update public.rh_taches set confiee_le = cree_le where confiee_le is null;
alter table public.rh_taches alter column confiee_le set default now();
alter table public.rh_taches alter column confiee_le set not null;
alter table public.rh_taches enable row level security;
revoke all on table public.rh_taches from public, anon, authenticated;
revoke all on sequence public.rh_taches_id_seq from public, anon, authenticated;
grant all on table public.rh_taches to service_role;
grant usage, select on sequence public.rh_taches_id_seq to service_role;

create table if not exists public.rh_taches_notes (
  id        bigserial primary key,
  tache_id  bigint not null references public.rh_taches(id) on delete cascade,
  le        timestamptz not null default now(),
  par       uuid references public.rh_employes(id) on delete set null,
  par_nom   text not null default '',
  note      text not null check (length(btrim(note)) between 1 and 500)
);
create index if not exists rh_taches_notes_tache on public.rh_taches_notes (tache_id, le desc);
alter table public.rh_taches_notes enable row level security;
revoke all on table public.rh_taches_notes from public, anon, authenticated;
revoke all on sequence public.rh_taches_notes_id_seq from public, anon, authenticated;
grant all on table public.rh_taches_notes to service_role;
grant usage, select on sequence public.rh_taches_notes_id_seq to service_role;

-- Quand la file a été recalculée pour la dernière fois.
create table if not exists public.rh_file_etat (
  id          int primary key default 1 check (id = 1),
  synchro_le  timestamptz
);
insert into public.rh_file_etat (id) values (1) on conflict (id) do nothing;
alter table public.rh_file_etat enable row level security;
revoke all on table public.rh_file_etat from public, anon, authenticated;
grant all on table public.rh_file_etat to service_role;

-- Le push : l'adresse de la fonction Edge « rh-push » et la clé publique
-- VAPID (celle que le téléphone donne à son navigateur). La clé PRIVÉE
-- n'est jamais ici : elle vit dans les secrets de la fonction.
create table if not exists public.rh_push_reglage (
  id            int primary key default 1 check (id = 1),
  url           text not null default '' check (url = '' or url ~ '^https://'),
  cle_publique  text not null default '' check (cle_publique ~ '^[A-Za-z0-9_-]*\Z')
);
insert into public.rh_push_reglage (id) values (1) on conflict (id) do nothing;
alter table public.rh_push_reglage enable row level security;
revoke all on table public.rh_push_reglage from public, anon, authenticated;
grant all on table public.rh_push_reglage to service_role;

-- Les téléphones abonnés (un abonnement Web Push par navigateur).
create table if not exists public.rh_push_abonnements (
  endpoint  text primary key check (endpoint ~ '^https://' and length(endpoint) <= 2000),
  compte    uuid not null references auth.users(id) on delete cascade,
  p256dh    text not null check (length(p256dh) between 40 and 200),
  auth      text not null check (length(auth) between 10 and 100),
  cree_le   timestamptz not null default now()
);
create index if not exists rh_push_abonnements_compte on public.rh_push_abonnements (compte);
alter table public.rh_push_abonnements enable row level security;
revoke all on table public.rh_push_abonnements from public, anon, authenticated;
grant all on table public.rh_push_abonnements to service_role;

-- Les choix de chacun : actif, types (null = tous ceux qui le concernent),
-- heures de silence (heure du Bénin). « depuis » : rien de plus ancien ne
-- part, pour qu'un abonnement neuf ne déverse pas toutes les vieilles tâches.
create table if not exists public.rh_push_preferences (
  compte         uuid primary key references auth.users(id) on delete cascade,
  actif          boolean not null default true,
  types          text[],
  silence_debut  int check (silence_debut between 0 and 23),
  silence_fin    int check (silence_fin between 0 and 23),
  depuis         timestamptz not null default now(),
  maj_le         timestamptz not null default now()
);
alter table public.rh_push_preferences enable row level security;
revoke all on table public.rh_push_preferences from public, anon, authenticated;
grant all on table public.rh_push_preferences to service_role;

-- Ce qui est parti, une fois par personne et par alerte (escalade à part).
create table if not exists public.rh_alertes_envoyees (
  id         bigserial primary key,
  compte     uuid not null references auth.users(id) on delete cascade,
  cle        text not null,
  titre      text not null,
  corps      text not null,
  lien       text not null default '',
  cree_le    timestamptz not null default now(),
  pousse_le  timestamptz,
  constraint rh_alertes_envoyees_une_fois unique (compte, cle)
);
alter table public.rh_alertes_envoyees enable row level security;
revoke all on table public.rh_alertes_envoyees from public, anon, authenticated;
revoke all on sequence public.rh_alertes_envoyees_id_seq from public, anon, authenticated;
grant all on table public.rh_alertes_envoyees to service_role;
grant usage, select on sequence public.rh_alertes_envoyees_id_seq to service_role;

-- Les bilans du matin : les nombres d'un côté, les montants de l'autre,
-- pour que la version sans montants ne soit qu'un retrait de colonne.
create table if not exists public.rh_bilans (
  id        bigserial primary key,
  jour      date not null unique,
  hebdo     boolean not null default false,
  chiffres  jsonb not null default '{}'::jsonb,
  montants  jsonb not null default '{}'::jsonb,
  cree_le   timestamptz not null default now()
);
alter table public.rh_bilans enable row level security;
revoke all on table public.rh_bilans from public, anon, authenticated;
revoke all on sequence public.rh_bilans_id_seq from public, anon, authenticated;
grant all on table public.rh_bilans to service_role;
grant usage, select on sequence public.rh_bilans_id_seq to service_role;

-- ---------- Les alertes en cours, toutes sources ----------
/**
 * Toutes les alertes en cours, une ligne chacune, avec une CLÉ stable (le
 * type et l'objet) : la tâche la retrouve d'un passage à l'autre. Les
 * règles sont celles des écrans (suivi, Contrôles, Qualité), mais lues
 * sans compte connecté : pg_cron n'en a pas. Aucun montant, aucun nom de
 * client dans les libellés. Interne.
 */
create or replace function public.rh_alertes_courantes()
returns table (a_cle text, a_type text, a_libelle text, a_commande text, a_boutique text, a_livreur uuid, a_lien text)
language plpgsql stable security definer set search_path = public as $$
declare
  sc jsonb := public.rh_controles_seuils();
  sa jsonb := public.rh_argent_seuils();
  sq jsonb := public.rh_qualite_seuils();
begin
  -- Le suivi : une tâche par commande et par alerte (la course refusée
  -- n'en est pas une : la pastille du suivi l'ignore aussi).
  return query
  select 'suivi:' || al.t || ':' || (d ->> 'id'), al.t,
         public.rh_alerte_libelle(al.t) || ' — ' || coalesce(d ->> 'numero', d ->> 'id'),
         d ->> 'id',
         (select l ->> 'boutique_id' from jsonb_array_elements(d -> 'lignes') l
           where l ->> 'etat' <> 'annulee' order by (l ->> 'rang')::int limit 1),
         (select (l ->> 'livreur_id')::uuid from jsonb_array_elements(d -> 'lignes') l
           where l ->> 'livreur_id' is not null limit 1),
         '#/suivi/commande/' || (d ->> 'id')
    from public.rh_suivi_donnees(now() - interval '60 days', now() + interval '1 day') d
    cross join lateral jsonb_array_elements_text(d -> 'alertes') al(t)
   where al.t <> 'refus_course';

  -- Contrôles : un réglage sensible pas encore approuvé.
  return query
  select 'reglage:' || a.id, 'reglage_a_approuver'::text,
         'Réglage sensible changé par ' || coalesce(nullif(a.par_nom, ''), 'un compte inconnu') || ', à approuver',
         null::text, case when a.table_nom = 'boutiques_reception' then a.cible end, null::uuid, '#/controles/reglages'::text
    from public.rh_audit_reglages a
   where a.approuve_le is null;

  -- Contrôles : un encaissement à la livraison pas rendu à temps, ou une
  -- livraison sans aucune déclaration (la règle de rh_controles_compteurs).
  return query
  select 'encaissement:' || x.commande_id || ':' || x.boutique_id, 'encaissement_ancien'::text,
         'Encaissement pas encore remis — ' || coalesce(c.numero, x.commande_id) || ' · ' || coalesce(b.nom, x.boutique_id),
         x.commande_id, x.boutique_id, x.livreur_id, '#/controles/encaissements'::text
    from public.encaissements x
    join public.commandes c on c.id = x.commande_id
    left join public.boutiques b on b.id = x.boutique_id
   where x.remis_le is null and x.montant > 0
     and now() - x.encaisse_le > make_interval(hours => case when x.mode = 'mobile_money'
                                                             then (sc ->> 'momopay_h')::int
                                                             else (sc ->> 'especes_h')::int end);
  return query
  select 'encaissement:' || d.commande_id || ':' || d.boutique_id, 'encaissement_ancien'::text,
         'Livraison sans déclaration d''encaissement — ' || coalesce(c.numero, d.commande_id) || ' · ' || coalesce(b.nom, d.boutique_id),
         d.commande_id, d.boutique_id, d.livreur_id, '#/controles/encaissements'::text
    from (select l.commande_id, l.boutique_id, (array_agg(l.livreur_id) filter (where l.livreur_id is not null))[1] as livreur_id
            from public.commande_lignes l
            join public.commandes k on k.id = l.commande_id and k.etat = 'payee'
           where l.etat = 'remise' and k.paye_le >= now() - interval '60 days'
             and not exists (select 1 from public.encaissements x
                              where x.commande_id = l.commande_id and x.boutique_id = l.boutique_id)
           group by l.commande_id, l.boutique_id) d
    join public.commandes c on c.id = d.commande_id
    left join public.boutiques b on b.id = d.boutique_id
   where exists (select 1 from public.restes_par_boutique(d.commande_id) rr
                  where rr.boutique_id = d.boutique_id and rr.a_encaisser > 0);

  -- Argent : un paiement à rapprocher (la règle « à traiter » de rh_paiements).
  return query
  select 'paiement:' || k.id, 'paiement_a_rapprocher'::text,
         'Paiement à rapprocher — ' || coalesce(k.numero, k.id) || ' (' || k.motif || ')',
         k.id, null::text, null::uuid, '#/controles/paiements'::text
    from (select c.id, c.numero, case
             when c.paye_le is null and c.etat <> 'payee' and coalesce(v.payee_chez, false) then 'client peut-être débité'
             when c.paye_le is null and c.etat <> 'payee' and coalesce(v.conflit, false) then 'versement en conflit'
             when c.paye_le is null and c.etat <> 'payee' and coalesce(v.incomplete, false) then 'versement incomplet'
             when c.etat = 'a_payer' and c.annonce_le is not null
                  and c.annonce_le < now() - make_interval(mins => (sa ->> 'annonce_min')::int) then '« j''ai payé » sans preuve'
             when c.paye_le is null and c.etat <> 'payee' and v.verdict = 'inconnue' then 'réponse inconnue'
           end as motif
            from public.commandes c
            left join lateral (select bool_or(x.verdict = 'payee') as payee_chez, bool_or(x.verdict = 'conflit') as conflit,
                                      bool_or(x.verdict = 'incomplete') as incomplete,
                                      (array_agg(x.verdict order by x.cree_le desc, x.id desc))[1] as verdict
                                 from public.versements x where x.commande_id = c.id) v on true
           where c.cree_le >= now() - interval '60 days'
             and (c.annonce_le is not null or exists (select 1 from public.versements x where x.commande_id = c.id))) k
   where k.motif is not null
     and coalesce((select r.statut from public.rh_rapprochements r where r.commande_id = k.id
                    order by r.le desc, r.id desc limit 1), '') not in ('regle', 'sans_suite');

  -- Argent : un remboursement dû qui tarde (la règle de rh_remboursements_liste).
  return query
  select 'remboursement:' || k.id, 'remboursement_en_retard'::text,
         'Remboursement en retard — ' || coalesce(k.numero, k.id),
         k.id, null::text, null::uuid, '#/controles/remboursements'::text
    from public.commandes k
   where k.paye_le is not null and k.paye_le >= now() - interval '365 days'
     and (k.etat = 'annulee'
          or exists (select 1 from public.commande_lignes l where l.commande_id = k.id and l.etat = 'annulee'))
     and now() - coalesce((select max(a.le) from public.rh_annulations a where a.commande_id = k.id),
                          (select max(j.le) from public.rh_journal_lignes j
                            where j.commande_id = k.id and j.valeur = 'annulee' and j.quoi in ('etat', 'commande')),
                          k.paye_le) > make_interval(days => (sa ->> 'remboursement_j')::int)
     and public.rh_rembourse_du(k.id)
         - coalesce((select sum(m.montant) from public.rh_remboursements m where m.commande_id = k.id), 0) > 0;

  -- Argent : une demande d'argent qui attend (boutique, livreur, parrain).
  -- Le parrain est un client : ni nom, ni numéro.
  return query
  select 'dette:boutique:' || v.id, 'dette_ancienne'::text,
         'Reversement demandé par ' || coalesce(b.nom, v.boutique_id) || ' le '
           || to_char(v.demande_le at time zone 'Africa/Porto-Novo', 'DD/MM'),
         null::text, v.boutique_id, null::uuid, '#/controles/dettes'::text
    from public.reversements v
    left join public.boutiques b on b.id = v.boutique_id
   where v.etat = 'en_attente' and v.demande_le < now() - make_interval(days => (sa ->> 'dette_j')::int);
  return query
  select 'dette:livreur:' || v.id, 'dette_ancienne'::text,
         'Gains demandés par ' || coalesce(nullif(btrim(v.nom_livreur), ''), 'un livreur') || ' le '
           || to_char(v.demande_le at time zone 'Africa/Porto-Novo', 'DD/MM'),
         null::text, null::text, v.livreur_id, '#/controles/dettes'::text
    from public.reversements_livreurs v
   where v.etat = 'en_attente' and v.demande_le < now() - make_interval(days => (sa ->> 'dette_j')::int);
  return query
  select 'dette:parrain:' || v.id, 'dette_ancienne'::text,
         'Retrait demandé par un parrain le ' || to_char(v.demande_le at time zone 'Africa/Porto-Novo', 'DD/MM'),
         null::text, null::text, null::uuid, '#/controles/dettes'::text
    from public.retraits_parrain v
   where v.etat = 'demande' and v.demande_le < now() - make_interval(days => (sa ->> 'dette_j')::int);

  -- Qualité : une réclamation qui attend la boutique, ou BIZZOO.
  return query
  select 'sav:' || s.reclamation_id || ':' || s.colonne,
         case when s.colonne = 'boutique' then 'sav_sans_reponse' else 'sav_escalade' end,
         case when s.colonne = 'boutique'
              then 'Réclamation sans réponse — ' || coalesce(b.nom, r.boutique_id, 'boutique')
              else 'Réclamation escaladée à trancher — ' || coalesce(b.nom, r.boutique_id, 'boutique') end
           || coalesce(' · ' || c.numero, ''),
         r.commande_id, r.boutique_id, null::uuid, '#/qualite/sav'::text
    from public.rh_sav_ouvertes() s
    join public.reclamations r on r.id = s.reclamation_id
    left join public.boutiques b on b.id = r.boutique_id
    left join public.commandes c on c.id = r.commande_id
   where (s.colonne = 'boutique' and now() - s.depuis_le > make_interval(hours => (sq ->> 'reponse_h')::int))
      or (s.colonne = 'bizzoo' and now() - s.depuis_le > make_interval(hours => (sq ->> 'decision_h')::int));

  -- Qualité : un produit qui se vend, épuisé, et la boutique pas appelée.
  return query
  select 'rupture:' || p.id, 'rupture_a_appeler'::text,
         'Rupture : ' || p.nom || ' · ' || coalesce(b.nom, p.boutique_id),
         null::text, p.boutique_id, null::uuid, '#/qualite/catalogue'::text
    from public.rh_ventes_30j() v
    join public.produits p on p.id = v.produit_id
    left join public.boutiques b on b.id = p.boutique_id
   where not p.masque and p.stock <= 0 and not p.sur_commande and v.qte >= (sq ->> 'populaire_min')::int
     and not exists (select 1 from public.rh_ruptures_suivi x
                      where x.produit_id = p.id and x.anomalie = 'rupture'
                        and x.appele_le > now() - interval '7 days');

  -- Qualité : une file d'Admin dont la plus ancienne demande dépasse son seuil.
  return query
  select 'file:' || w.cle, 'file_en_retard'::text,
         'File d''Admin en retard : ' || case w.cle
           when 'demandes' then 'demandes des boutiques'
           when 'revendeurs' then 'demandes de compte revendeur'
           when 'comptes' then 'comptes d''équipe à valider'
           when 'avis' then 'avis signalés'
           else 'produits signalés' end,
         null::text, null::text, null::uuid, '#/qualite/files'::text
    from (select z.cle, min(z.le) as le
            from (select 'demandes' as cle, d.demande_le as le from public.demandes d where d.etat = 'en_attente'
                  union all
                  select 'revendeurs', coalesce(c.revendeur_demande_le, c.maj_le) from public.clients c
                   where c.revendeur_etat = 'en_attente'
                  union all
                  select 'comptes', p.cree_le from public.profils p where p.a_valider
                  union all
                  select 'avis', s.cree_le from public.avis_signalements s where s.etat = 'ouvert'
                  union all
                  select 'produits', s.cree_le from public.produits_signalements s where s.etat = 'ouvert') z
           group by z.cle) w
   where w.le < now() - make_interval(hours => coalesce((sq #>> array['files_h', w.cle])::int, 48));
end $$;

-- ---------- Qui voit quelle tâche ----------
/** Une tâche confiée à ce profil m'est-elle visible ? L'administration et
    le superadministrateur voient tout ; un membre, celles de son profil ;
    un responsable, celles des profils qu'il dirige. Sans profil : à
    l'administration seule. */
create or replace function public.rh_tache_visible(v_profil uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.rh_est_admin() or public.est_super()
      or (v_profil is not null and public.rh_moi() is not null
          and (public.rh_mon_profil() = v_profil or public.rh_responsable_de(v_profil)));
$$;

/** « admin » (tout, routage compris), « equipe » (une alerte au moins est
    confiée à mon profil, ou à un profil que je dirige), ou rien. */
create or replace function public.rh_file_acces() returns text
language sql stable security definer set search_path = public as $$
  select case
    when public.rh_est_admin() or public.est_super() then 'admin'
    when public.rh_moi() is not null and exists (
      select 1 from public.rh_routage_alertes r
       where r.actif and r.profil_id is not null
         and (r.profil_id = public.rh_mon_profil() or public.rh_responsable_de(r.profil_id))) then 'equipe'
  end;
$$;

/** Le bilan : « complet » (administration, CEO, superadministrateur),
    « sans_montants » (un responsable de profil), ou rien. */
create or replace function public.rh_bilan_acces() returns text
language sql stable security definer set search_path = public as $$
  select case
    when public.rh_est_admin() or public.est_super() then 'complet'
    when public.rh_moi() is not null
         and exists (select 1 from public.rh_profils p where p.responsable_id = public.rh_moi()) then 'sans_montants'
  end;
$$;

/** Le nom de l'employé connecté, tel qu'il s'écrit dans une note. */
create or replace function public.rh_mon_nom() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select btrim(coalesce(e.prenoms, '') || ' ' || coalesce(e.nom, ''))
                     from public.rh_employes e where e.compte_id = auth.uid() and e.etat = 'actif'), '');
$$;

-- ---------- La file : recalcul, escalade ----------
/**
 * Recalcule la file : une tâche par alerte nouvelle (confiée au profil du
 * routage), la tâche d'une alerte disparue s'efface d'elle-même (« disparue »),
 * celle d'une alerte revenue se rouvre, et une tâche que personne n'a prise
 * après le délai du routage remonte (escalade). « v_forcer » à faux : rien
 * si le dernier calcul a moins de deux minutes (l'écran l'appelle à
 * l'ouverture). Un seul calcul à la fois. Interne (pg_cron, Ma file).
 */
create or replace function public.rh_taches_synchroniser(v_forcer boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_alertes jsonb;
  v_cles text[];
  v_creees int := 0;
  v_rouvertes int := 0;
  v_disparues int := 0;
  v_escaladees int := 0;
begin
  if not coalesce(v_forcer, true) and exists (select 1 from public.rh_file_etat e
                                               where e.id = 1 and e.synchro_le > now() - interval '2 minutes') then
    return null;
  end if;
  if not pg_try_advisory_xact_lock(hashtext('rh_taches_synchroniser')) then
    return null;
  end if;
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_alertes from public.rh_alertes_courantes() x;
  select coalesce(array_agg(distinct x ->> 'a_cle'), '{}') into v_cles from jsonb_array_elements(v_alertes) x;

  select count(*) filter (where t.id is null),
         count(*) filter (where t.etat = 'disparue' or (t.etat = 'terminee' and t.disparue_le is not null))
    into v_creees, v_rouvertes
    from unnest(v_cles) k(cle)
    left join public.rh_taches t on t.cle = k.cle;

  -- Les nouvelles, et celles qui reviennent : une ligne par clé (deux sources
  -- ne donnent jamais la même clé, mais distinct on par prudence). « Revient » :
  -- effacée d'elle-même, ou terminée puis son alerte partie (disparue_le posé
  -- plus bas) — sans quoi une file d'Admin ou une rupture, qui reviennent
  -- régulièrement, ne feraient plus jamais de tâche après un seul « Terminé ».
  with a as (
    select distinct on (y.a_cle) y.*
      from jsonb_to_recordset(v_alertes) as y(a_cle text, a_type text, a_libelle text, a_commande text,
                                              a_boutique text, a_livreur uuid, a_lien text)
     order by y.a_cle
  )
    insert into public.rh_taches as t (cle, type, libelle, commande_id, boutique_id, livreur_id, lien, profil_id)
    select a.a_cle, a.a_type, left(a.a_libelle, 300),
           case when exists (select 1 from public.commandes c where c.id = a.a_commande) then a.a_commande end,
           a.a_boutique, a.a_livreur, a.a_lien, r.profil_id
      from a
      left join public.rh_routage_alertes r on r.type = a.a_type
     where coalesce(r.actif, true)
    on conflict (cle) do update
       set vue_le = now(),
           libelle = excluded.libelle,
           etat = case when t.etat = 'disparue' or (t.etat = 'terminee' and t.disparue_le is not null)
                       then 'ouverte' else t.etat end,
           occurrence = case when t.etat = 'disparue' or (t.etat = 'terminee' and t.disparue_le is not null)
                             then t.occurrence + 1 else t.occurrence end,
           cree_le = case when t.etat = 'disparue' or (t.etat = 'terminee' and t.disparue_le is not null)
                          then now() else t.cree_le end,
           confiee_le = case when t.etat = 'disparue' or (t.etat = 'terminee' and t.disparue_le is not null)
                             then now() else t.confiee_le end,
           profil_id = case when t.etat = 'disparue' or (t.etat = 'terminee' and t.disparue_le is not null)
                            then excluded.profil_id else t.profil_id end,
           prise_par = case when t.etat = 'disparue' or (t.etat = 'terminee' and t.disparue_le is not null)
                            then null else t.prise_par end,
           prise_nom = case when t.etat = 'disparue' or (t.etat = 'terminee' and t.disparue_le is not null)
                            then '' else t.prise_nom end,
           prise_le = case when t.etat = 'disparue' or (t.etat = 'terminee' and t.disparue_le is not null)
                           then null else t.prise_le end,
           escalade_le = case when t.etat = 'disparue' or (t.etat = 'terminee' and t.disparue_le is not null)
                              then null else t.escalade_le end,
           terminee_le = case when t.etat = 'disparue' or (t.etat = 'terminee' and t.disparue_le is not null)
                              then null else t.terminee_le end,
           terminee_nom = case when t.etat = 'disparue' or (t.etat = 'terminee' and t.disparue_le is not null)
                               then '' else t.terminee_nom end,
           disparue_le = case when t.etat = 'disparue' or (t.etat = 'terminee' and t.disparue_le is not null)
                              then null else t.disparue_le end;

  update public.rh_taches t
     set etat = 'disparue', disparue_le = now()
   where t.etat in ('ouverte', 'prise') and not (t.cle = any(v_cles));
  get diagnostics v_disparues = row_count;
  -- Terminée et son alerte partie : elle reste « terminée » (l'historique
  -- garde qui l'a close), mais on note que l'alerte est partie, pour la
  -- rouvrir si elle revient.
  update public.rh_taches t
     set disparue_le = now()
   where t.etat = 'terminee' and t.disparue_le is null and not (t.cle = any(v_cles));

  -- L'escalade se compte depuis que la tâche attend son profil actuel.
  update public.rh_taches t
     set escalade_le = now()
   where t.etat = 'ouverte' and t.escalade_le is null
     and t.confiee_le < now() - make_interval(mins => coalesce((select r.escalade_min from public.rh_routage_alertes r
                                                             where r.type = t.type), 30));
  get diagnostics v_escaladees = row_count;

  update public.rh_file_etat set synchro_le = now() where id = 1;
  return jsonb_build_object('creees', v_creees, 'rouvertes', v_rouvertes,
                            'disparues', v_disparues, 'escaladees', v_escaladees);
end $$;

-- ---------- La file : lire et agir ----------
/** Les pastilles : ce qui attend dans ma file, et le bilan s'il m'est ouvert. */
create or replace function public.rh_file_compteurs() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_acces text := public.rh_file_acces();
  v_moi uuid := public.rh_moi();
  v_admin boolean := public.rh_est_admin() or public.est_super();
begin
  if v_acces is null then
    return jsonb_build_object('acces', null, 'bilan', public.rh_bilan_acces());
  end if;
  return jsonb_build_object(
    'acces', v_acces,
    'bilan', public.rh_bilan_acces(),
    'a_prendre', (select count(*) from public.rh_taches t
                   where t.etat = 'ouverte' and public.rh_tache_visible(t.profil_id)),
    'a_moi', (select count(*) from public.rh_taches t where t.etat = 'prise' and t.prise_par = v_moi),
    -- Les escalades qui me reviennent : celles des profils que je dirige
    -- (ou sans responsable, et alors à l'administration).
    'escalades', (select count(*) from public.rh_taches t
                   left join public.rh_profils p on p.id = t.profil_id
                  where t.etat = 'ouverte' and t.escalade_le is not null
                    and ((p.responsable_id is not null and p.responsable_id = v_moi)
                         or (p.responsable_id is null and v_admin))));
end $$;

/**
 * Ma file : les tâches à faire (« a_faire ») ou closes depuis 7 jours
 * (« terminees »), avec les numéros de la boutique et du livreur pour
 * appeler. Le client : l'administration seule. Aucun montant.
 */
create or replace function public.rh_ma_file(v_vue text default 'a_faire') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_acces text := public.rh_file_acces();
  v_admin boolean := public.rh_est_admin() or public.est_super();
  v_moi uuid := public.rh_moi();
begin
  if v_acces is null then
    raise exception 'Votre compte n''a pas de file : aucune alerte n''est confiée à votre profil';
  end if;
  if coalesce(v_vue, '') not in ('a_faire', 'terminees') then
    raise exception 'Choisissez les tâches à faire ou les tâches terminées';
  end if;
  perform public.rh_taches_synchroniser(false);
  return jsonb_build_object(
    'acces', v_acces,
    'moi', v_moi,
    'droits', jsonb_build_object('routage', v_admin, 'client', v_admin),
    'synchro_le', (select e.synchro_le from public.rh_file_etat e where e.id = 1),
    'taches', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', t.id, 'type', t.type, 'type_libelle', public.rh_alerte_libelle(t.type), 'libelle', t.libelle,
        'etat', t.etat, 'cree_le', t.cree_le, 'lien', t.lien, 'profil', p.nom,
        'prise_nom', nullif(t.prise_nom, ''), 'prise_le', t.prise_le, 'a_moi', t.prise_par = v_moi,
        'escalade_le', t.escalade_le, 'terminee_le', coalesce(t.terminee_le, t.disparue_le),
        'terminee_nom', nullif(t.terminee_nom, ''),
        'reprendre', v_admin or public.rh_responsable_de(t.profil_id),
        'commande', c.numero,
        'boutiques', (select coalesce(jsonb_agg(distinct jsonb_build_object('nom', b.nom, 'tel', b.tel)), '[]'::jsonb)
                        from public.boutiques b
                       where coalesce(b.tel, '') <> ''
                         and (b.id = t.boutique_id
                              or b.id in (select l.boutique_id from public.commande_lignes l
                                           where l.commande_id = t.commande_id and l.etat <> 'annulee'))),
        'livreurs', (select coalesce(jsonb_agg(distinct jsonb_build_object('nom', coalesce(nullif(pl.nom, ''), 'Livreur'),
                                                                           'tel', pl.tel)), '[]'::jsonb)
                       from public.profils pl
                      where coalesce(pl.tel, '') <> ''
                        and (pl.id = t.livreur_id
                             or pl.id in (select l.livreur_id from public.commande_lignes l
                                           where l.commande_id = t.commande_id and l.livreur_id is not null))),
        'client', case when v_admin and c.id is not null then
                    jsonb_build_object('nom', nullif(btrim(c.client_nom), ''),
                                       'tel', btrim(case when coalesce(c.client_indicatif, '') <> '' and c.client_indicatif <> '229'
                                                         then '+' || c.client_indicatif || ' ' else '' end || coalesce(c.client_tel, '')))
                  end,
        'notes', (select coalesce(jsonb_agg(jsonb_build_object('le', n.le, 'par', n.par_nom, 'note', n.note)
                                            order by n.le desc), '[]'::jsonb)
                    from (select * from public.rh_taches_notes n where n.tache_id = t.id
                           order by n.le desc limit 10) n))
        order by (t.escalade_le is not null) desc, t.cree_le), '[]'::jsonb)
      from (select * from public.rh_taches x
             where public.rh_tache_visible(x.profil_id)
               and case when v_vue = 'a_faire' then x.etat in ('ouverte', 'prise')
                        else x.etat in ('terminee', 'disparue')
                             and coalesce(x.terminee_le, x.disparue_le) > now() - interval '7 days' end
             order by x.cree_le
             limit 300) t
      left join public.rh_profils p on p.id = t.profil_id
      left join public.commandes c on c.id = t.commande_id));
end $$;

/** Lire une tâche que je peux voir, et la verrouiller pour la changer. */
create or replace function public.rh_tache_a_moi(v_tache bigint) returns public.rh_taches
language plpgsql security definer set search_path = public as $$
declare
  t public.rh_taches;
begin
  if public.rh_moi() is null then
    raise exception 'Seul un employé en poste agit sur une tâche';
  end if;
  select * into t from public.rh_taches x where x.id = v_tache for update;
  if not found or not public.rh_tache_visible(t.profil_id) then
    raise exception 'Tâche introuvable';
  end if;
  if t.etat in ('terminee', 'disparue') then
    raise exception 'Cette tâche est déjà close';
  end if;
  return t;
end $$;

/** « Je prends » : la tâche est à moi, les autres le voient. Reprendre une
    tâche déjà prise : son responsable ou l'administration. */
create or replace function public.rh_tache_prendre(v_tache bigint, v_reprendre boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  t public.rh_taches := public.rh_tache_a_moi(v_tache);
  v_moi uuid := public.rh_moi();
begin
  if t.etat = 'prise' and t.prise_par = v_moi then
    raise exception 'Vous avez déjà pris cette tâche';
  end if;
  if t.etat = 'prise' and not coalesce(v_reprendre, false) then
    raise exception 'Déjà prise par % : voyez avec cette personne', coalesce(nullif(t.prise_nom, ''), 'un collègue');
  end if;
  if t.etat = 'prise' and not (public.rh_est_admin() or public.est_super() or public.rh_responsable_de(t.profil_id)) then
    raise exception 'Seuls le responsable du profil et l''administration reprennent une tâche déjà prise';
  end if;
  update public.rh_taches x
     set etat = 'prise', prise_par = v_moi, prise_nom = public.rh_mon_nom(), prise_le = now()
   where x.id = t.id;
  if t.etat = 'prise' then
    insert into public.rh_taches_notes (tache_id, par, par_nom, note)
    values (t.id, v_moi, public.rh_mon_nom(), 'Reprise à ' || coalesce(nullif(t.prise_nom, ''), 'un collègue'));
  end if;
  return jsonb_build_object('id', t.id, 'etat', 'prise', 'prise_nom', public.rh_mon_nom());
end $$;

/** Une note de relance, datée et signée (« boutique appelée, prêt dans 20 min »). */
create or replace function public.rh_tache_relancer(v_tache bigint, v_note text) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  t public.rh_taches := public.rh_tache_a_moi(v_tache);
  v_texte text := btrim(coalesce(v_note, ''));
  n bigint;
begin
  if length(v_texte) < 3 then
    raise exception 'Écrivez ce qui a été fait (boutique appelée, livreur relancé…)';
  end if;
  insert into public.rh_taches_notes (tache_id, par, par_nom, note)
  values (t.id, public.rh_moi(), public.rh_mon_nom(), left(v_texte, 500))
  returning id into n;
  return n;
end $$;

/** « Terminé » : par qui l'a prise, son responsable ou l'administration ;
    une tâche libre, par qui la voit. */
create or replace function public.rh_tache_terminer(v_tache bigint, v_note text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  t public.rh_taches := public.rh_tache_a_moi(v_tache);
  v_moi uuid := public.rh_moi();
  v_texte text := btrim(coalesce(v_note, ''));
begin
  if t.etat = 'prise' and t.prise_par is distinct from v_moi
     and not (public.rh_est_admin() or public.est_super() or public.rh_responsable_de(t.profil_id)) then
    raise exception 'Prise par % : elle seule, son responsable ou l''administration la termine',
      coalesce(nullif(t.prise_nom, ''), 'un collègue');
  end if;
  if v_texte <> '' then
    insert into public.rh_taches_notes (tache_id, par, par_nom, note)
    values (t.id, v_moi, public.rh_mon_nom(), left(v_texte, 500));
  end if;
  update public.rh_taches x
     set etat = 'terminee', terminee_le = now(), terminee_nom = public.rh_mon_nom()
   where x.id = t.id;
  return jsonb_build_object('id', t.id, 'etat', 'terminee');
end $$;

-- ---------- Le routage ----------
/** Le routage, pour l'administration : chaque type d'alerte, son profil,
    son délai d'escalade ; les profils pour le choisir. */
create or replace function public.rh_routage_lire() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.rh_est_admin() or public.est_super()) then
    raise exception 'Le routage des alertes se règle par l''administration';
  end if;
  return jsonb_build_object(
    'types', (select coalesce(jsonb_agg(jsonb_build_object(
        'type', x ->> 'type', 'libelle', x ->> 'libelle', 'groupe', x ->> 'groupe',
        'profil_id', r.profil_id, 'profil', p.nom, 'escalade_min', coalesce(r.escalade_min, 30),
        'actif', coalesce(r.actif, true), 'maj_le', r.maj_le, 'maj_par', nullif(r.maj_par, ''))
        order by o.n), '[]'::jsonb)
      from jsonb_array_elements(public.rh_alertes_types()) with ordinality as o(x, n)
      left join public.rh_routage_alertes r on r.type = o.x ->> 'type'
      left join public.rh_profils p on p.id = r.profil_id),
    'profils', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'nom', p.nom,
                                                             'responsable', p.responsable_id is not null)
                                          order by p.nom), '[]'::jsonb)
                  from public.rh_profils p));
end $$;

/** Confier un type d'alerte à un profil (null : à l'administration). Les
    tâches de ce type que personne n'a prises suivent le nouveau routage. */
create or replace function public.rh_routage_regler(v_type text, v_profil uuid, v_escalade_min int, v_actif boolean default true)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.rh_est_admin() or public.est_super()) then
    raise exception 'Le routage des alertes se règle par l''administration';
  end if;
  if not exists (select 1 from jsonb_array_elements(public.rh_alertes_types()) x where x ->> 'type' = v_type) then
    raise exception 'Type d''alerte inconnu';
  end if;
  if v_profil is not null and not exists (select 1 from public.rh_profils p where p.id = v_profil) then
    raise exception 'Profil introuvable';
  end if;
  if coalesce(v_escalade_min, 0) not between 5 and 10080 then
    raise exception 'Le délai d''escalade se compte en minutes, de 5 à 10 080 (une semaine)';
  end if;
  insert into public.rh_routage_alertes as r (type, profil_id, escalade_min, actif, maj_le, maj_par)
  values (v_type, v_profil, v_escalade_min, coalesce(v_actif, true), now(), public.rh_mon_nom())
  on conflict (type) do update
     set profil_id = excluded.profil_id, escalade_min = excluded.escalade_min, actif = excluded.actif,
         maj_le = excluded.maj_le, maj_par = excluded.maj_par;
  -- Le nouveau profil a tout son délai : l'escalade repart de maintenant.
  update public.rh_taches t
     set profil_id = v_profil, escalade_le = null, confiee_le = now()
   where t.type = v_type and t.etat = 'ouverte' and t.profil_id is distinct from v_profil;
end $$;

-- ---------- Les alertes sur le téléphone ----------
/** Mes alertes : la clé publique (le service est-il prêt ?), mes choix, mes
    téléphones abonnés, et les types d'alerte qui me concernent. */
create or replace function public.rh_push_etat() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_admin boolean := public.rh_est_admin() or public.est_super();
begin
  if public.rh_moi() is null then
    raise exception 'Les alertes sur le téléphone sont réservées aux employés en poste';
  end if;
  return jsonb_build_object(
    'cle_publique', nullif((select g.cle_publique from public.rh_push_reglage g where g.id = 1), ''),
    'appareils', (select count(*) from public.rh_push_abonnements a where a.compte = auth.uid()),
    'preferences', (select jsonb_build_object('actif', f.actif, 'types', f.types,
                                              'silence_debut', f.silence_debut, 'silence_fin', f.silence_fin)
                      from public.rh_push_preferences f where f.compte = auth.uid()),
    'types', (select coalesce(jsonb_agg(x order by o.n), '[]'::jsonb)
                from jsonb_array_elements(public.rh_alertes_types()) with ordinality as o(x, n)
                left join public.rh_routage_alertes r on r.type = o.x ->> 'type'
               where coalesce(r.actif, true)
                 and (case when r.profil_id is null then v_admin
                           else v_admin or r.profil_id = public.rh_mon_profil() or public.rh_responsable_de(r.profil_id) end)));
end $$;

/** Ce téléphone s'abonne (ou renouvelle son abonnement). Cinq au plus par compte. */
create or replace function public.rh_push_abonner(v_endpoint text, v_p256dh text, v_auth text) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_compte uuid := auth.uid();
begin
  if public.rh_moi() is null then
    raise exception 'Les alertes sur le téléphone sont réservées aux employés en poste';
  end if;
  if coalesce(v_endpoint, '') !~ '^https://' or length(v_endpoint) > 2000
     or length(coalesce(v_p256dh, '')) not between 40 and 200 or length(coalesce(v_auth, '')) not between 10 and 100 then
    raise exception 'Abonnement du téléphone illisible';
  end if;
  insert into public.rh_push_abonnements as a (endpoint, compte, p256dh, auth, cree_le)
  values (v_endpoint, v_compte, v_p256dh, v_auth, now())
  on conflict (endpoint) do update
     set compte = excluded.compte, p256dh = excluded.p256dh, auth = excluded.auth, cree_le = excluded.cree_le;
  delete from public.rh_push_abonnements a
   where a.compte = v_compte
     and a.endpoint not in (select x.endpoint from public.rh_push_abonnements x
                             where x.compte = v_compte order by x.cree_le desc limit 5);
  insert into public.rh_push_preferences (compte) values (v_compte) on conflict (compte) do nothing;
  return true;
end $$;

/** Ce téléphone ne reçoit plus rien. */
create or replace function public.rh_push_desabonner(v_endpoint text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return false;
  end if;
  delete from public.rh_push_abonnements a where a.endpoint = v_endpoint and a.compte = auth.uid();
  return found;
end $$;

/** Mes choix : alertes en marche, types (null = tous les miens), heures de
    silence (heure du Bénin, de « début » à « fin »). Remis en marche, rien
    de plus ancien ne part. */
create or replace function public.rh_push_regler(v_actif boolean, v_types text[], v_silence_debut int, v_silence_fin int)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.rh_moi() is null then
    raise exception 'Les alertes sur le téléphone sont réservées aux employés en poste';
  end if;
  if v_types is not null and exists (select 1 from unnest(v_types) u(t)
                                      where not exists (select 1 from jsonb_array_elements(public.rh_alertes_types()) x
                                                         where x ->> 'type' = u.t)) then
    raise exception 'Type d''alerte inconnu';
  end if;
  if (v_silence_debut is null) <> (v_silence_fin is null)
     or coalesce(v_silence_debut, 0) not between 0 and 23 or coalesce(v_silence_fin, 0) not between 0 and 23 then
    raise exception 'Les heures de silence vont de 0 à 23 h, début et fin ensemble';
  end if;
  insert into public.rh_push_preferences as f (compte, actif, types, silence_debut, silence_fin, depuis, maj_le)
  values (auth.uid(), coalesce(v_actif, true), v_types, v_silence_debut, v_silence_fin, now(), now())
  on conflict (compte) do update
     set actif = excluded.actif, types = excluded.types, silence_debut = excluded.silence_debut,
         silence_fin = excluded.silence_fin, maj_le = now(),
         depuis = case when not f.actif and excluded.actif then now() else f.depuis end;
end $$;

/** Est-ce l'heure de silence de ce compte (heure du Bénin) ? */
create or replace function public.rh_push_en_silence(v_debut int, v_fin int, v_quand timestamptz default now()) returns boolean
language sql stable set search_path = public as $$
  select v_debut is not null and v_fin is not null and v_debut <> v_fin
     and case when v_debut < v_fin
              then extract(hour from v_quand at time zone 'Africa/Porto-Novo') >= v_debut
                   and extract(hour from v_quand at time zone 'Africa/Porto-Novo') < v_fin
              else extract(hour from v_quand at time zone 'Africa/Porto-Novo') >= v_debut
                   or extract(hour from v_quand at time zone 'Africa/Porto-Novo') < v_fin end;
$$;

/**
 * Ce qui doit partir maintenant : pour chaque tâche libre, ses destinataires
 * (les membres de son profil ; l'administration si elle n'a pas de profil),
 * et pour chaque escalade, le responsable du profil (l'administration s'il
 * n'en a pas). Seulement qui a un téléphone abonné, les alertes en marche,
 * ce type parmi ses choix, hors de ses heures de silence, et jamais deux
 * fois pour la même occurrence : la clé d'envoi porte le numéro
 * d'occurrence de la tâche (nue pour la première), si bien qu'une alerte
 * revenue sonne de nouveau. Le message : le type et la tâche, sans montant
 * ni nom de client ; le lien, celui de la tâche (la commande dans le
 * Suivi…), sinon « Ma file ». « quand » : depuis quand la tâche attend ce
 * profil, comparé au début de l'abonnement. Interne.
 */
create or replace function public.rh_alertes_a_pousser()
returns table (p_compte uuid, p_cle text, p_titre text, p_corps text, p_lien text)
language sql stable security definer set search_path = public as $$
  with t as (
    select x.*, p.responsable_id
      from public.rh_taches x
      left join public.rh_profils p on p.id = x.profil_id
     where x.etat = 'ouverte'
  ), dest as (
    select e.compte_id as compte, t.id, t.type, t.libelle, t.lien,
           t.cle || case when t.occurrence > 1 then '#' || t.occurrence else '' end as cle,
           t.confiee_le as quand, false as escalade
      from t join public.rh_employes e on e.etat = 'actif' and e.compte_id is not null
       and ((t.profil_id is not null and e.profil_id = t.profil_id)
            or (t.profil_id is null and (e.administration or e.ceo)))
    union
    select e.compte_id, t.id, t.type, t.libelle, t.lien,
           'escalade:' || t.cle || case when t.occurrence > 1 then '#' || t.occurrence else '' end,
           t.escalade_le, true
      from t join public.rh_employes e on e.etat = 'actif' and e.compte_id is not null
       and t.escalade_le is not null
       and ((t.responsable_id is not null and e.id = t.responsable_id)
            or (t.responsable_id is null and (e.administration or e.ceo)))
  )
  select d.compte, d.cle,
         case when d.escalade then 'Personne ne l''a prise : ' else '' end || public.rh_alerte_libelle(d.type),
         d.libelle, case when d.lien like '#/%' then d.lien else '#/file' end
    from dest d
    join public.rh_push_preferences f on f.compte = d.compte and f.actif
   where (f.types is null or d.type = any(f.types))
     and d.quand >= f.depuis
     and not public.rh_push_en_silence(f.silence_debut, f.silence_fin)
     and exists (select 1 from public.rh_push_abonnements a where a.compte = d.compte)
     and not exists (select 1 from public.rh_alertes_envoyees s where s.compte = d.compte and s.cle = d.cle);
$$;

/** Note ce qui part, une fois par personne et par alerte ; rend les numéros
    des envois neufs. Interne. */
create or replace function public.rh_alertes_enregistrer() returns bigint[]
language plpgsql security definer set search_path = public as $$
declare
  v_ids bigint[];
begin
  with neuf as (
    insert into public.rh_alertes_envoyees (compte, cle, titre, corps, lien)
    select a.p_compte, a.p_cle, a.p_titre, a.p_corps, a.p_lien from public.rh_alertes_a_pousser() a
    on conflict (compte, cle) do nothing
    returning id
  )
  select coalesce(array_agg(neuf.id order by neuf.id), '{}') into v_ids from neuf;
  return v_ids;
end $$;

/**
 * Pousse les alertes : la file d'abord, puis un appel à la fonction Edge
 * « rh-push » par envoi, avec son seul numéro. Sont appelés les envois
 * neufs ET ceux de la dernière heure pas encore partis (clés VAPID absentes,
 * appel pg_net perdu) : la fonction Edge ne consomme un envoi qu'en le
 * poussant, et la base ne le rend qu'une fois, d'où aucun doublon. Sans
 * pg_net ou sans l'adresse de la fonction, rien n'est noté (rien ne serait
 * parti) et rien ne casse. pg_cron l'appelle toutes les cinq minutes ; rend
 * le nombre d'appels.
 */
create or replace function public.rh_pousser_alertes() returns int
language plpgsql security definer set search_path = public as $$
declare
  v_adresse text;
  v_ids bigint[];
  v_id bigint;
begin
  select g.url into v_adresse from public.rh_push_reglage g where g.id = 1;
  if coalesce(v_adresse, '') = '' or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then
    return 0;
  end if;
  perform public.rh_taches_synchroniser(false);
  perform public.rh_alertes_enregistrer();
  select coalesce(array_agg(x.id order by x.id), '{}') into v_ids
    from public.rh_alertes_envoyees x
   where x.pousse_le is null and x.cree_le > now() - interval '1 hour';
  foreach v_id in array v_ids loop
    begin
      perform net.http_post(v_adresse, jsonb_build_object('id', v_id),
        '{}'::jsonb, '{"Content-Type": "application/json"}'::jsonb, 10000);
    exception when others then
      raise warning 'rh_pousser_alertes(%) : %', v_id, sqlerrm;
    end;
  end loop;
  return coalesce(cardinality(v_ids), 0);
end $$;

/** Ce que la fonction Edge envoie : le message et les téléphones de son
    destinataire — une seule fois, dans l'heure. « tache » : la clé de la
    tâche, sans « escalade: » ni numéro d'occurrence ; elle sert d'étiquette
    à la notification, pour qu'une même tâche ne s'empile pas sur le
    téléphone. Réservé au serveur. */
create or replace function public.rh_push_a_envoyer(cible bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s public.rh_alertes_envoyees;
begin
  update public.rh_alertes_envoyees x set pousse_le = now()
   where x.id = cible and x.pousse_le is null and x.cree_le > now() - interval '1 hour'
  returning * into s;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'id', s.id, 'titre', s.titre, 'corps', s.corps, 'lien', s.lien,
    'tache', regexp_replace(regexp_replace(s.cle, '^escalade:', ''), '#[0-9]+\Z', ''),
    'abonnements', coalesce((select jsonb_agg(jsonb_build_object('endpoint', a.endpoint, 'p256dh', a.p256dh, 'auth', a.auth)
                                              order by a.cree_le desc)
                               from public.rh_push_abonnements a where a.compte = s.compte), '[]'::jsonb));
end $$;

/** Un abonnement que le service de push ne connaît plus : on l'oublie. Réservé au serveur. */
create or replace function public.rh_push_abonnement_mort(v_endpoint text) returns void
language sql security definer set search_path = public as $$
  delete from public.rh_push_abonnements a where a.endpoint = v_endpoint;
$$;

-- ---------- Le bilan du matin ----------
/**
 * Le bilan du jour (heure du Bénin) : les alertes par type, les paiements
 * en litige, les MoMoPay pas vérifiés, les demandes d'argent en retard, les
 * réglages pas approuvés, les réclamations en souffrance, les ruptures de
 * produits qui se vendent, les commandes de la veille et la file ; le
 * lundi, la semaine écoulée comparée à la précédente. Les nombres dans
 * « chiffres », les montants à part. Une fois par jour (« v_forcer » le
 * refait). pg_cron l'appelle à 7 h. Interne.
 */
create or replace function public.rh_preparer_bilan(v_forcer boolean default false) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_jour date := (now() at time zone 'Africa/Porto-Novo')::date;
  v_hier timestamptz := (v_jour - 1)::timestamp at time zone 'Africa/Porto-Novo';
  v_aujourdhui timestamptz := v_jour::timestamp at time zone 'Africa/Porto-Novo';
  v_s1 timestamptz := (v_jour - 7)::timestamp at time zone 'Africa/Porto-Novo';
  v_s2 timestamptz := (v_jour - 14)::timestamp at time zone 'Africa/Porto-Novo';
  v_hebdo boolean := extract(isodow from v_jour) = 1;
  sc jsonb := public.rh_controles_seuils();
  sa jsonb := public.rh_argent_seuils();
  v_alertes jsonb;
  v_chiffres jsonb;
  v_montants jsonb;
  v_id bigint;
begin
  select b.id into v_id from public.rh_bilans b where b.jour = v_jour;
  if v_id is not null and not coalesce(v_forcer, false) then
    return v_id;
  end if;
  select coalesce(jsonb_object_agg(x.a_type, x.n), '{}'::jsonb) into v_alertes
    from (select a.a_type, count(*) as n from public.rh_alertes_courantes() a group by a.a_type) x;

  v_chiffres := jsonb_build_object(
    'alertes', v_alertes,
    'paiements_litige', coalesce((v_alertes ->> 'paiement_a_rapprocher')::int, 0),
    'momopay_non_verifies', (select count(*) from public.encaissements x
                              where x.mode = 'mobile_money' and x.remis_le is null and x.montant > 0
                                and now() - x.encaisse_le > make_interval(hours => (sc ->> 'momopay_h')::int)),
    'dettes_retard', coalesce((v_alertes ->> 'dette_ancienne')::int, 0),
    'reglages_non_approuves', (select count(*) from public.rh_audit_reglages a where a.approuve_le is null),
    'reclamations_souffrance', coalesce((v_alertes ->> 'sav_sans_reponse')::int, 0)
                               + coalesce((v_alertes ->> 'sav_escalade')::int, 0),
    'ruptures_vedettes', coalesce((v_alertes ->> 'rupture_a_appeler')::int, 0),
    'remboursements_retard', coalesce((v_alertes ->> 'remboursement_en_retard')::int, 0),
    'veille', jsonb_build_object(
      'creees', (select count(*) from public.commandes c where c.cree_le >= v_hier and c.cree_le < v_aujourdhui),
      'payees', (select count(*) from public.commandes c where c.paye_le >= v_hier and c.paye_le < v_aujourdhui),
      'jamais_payees', (select count(*) from public.commandes c
                         where c.cree_le >= v_hier and c.cree_le < v_aujourdhui and c.paye_le is null
                           and c.etat in ('a_payer', 'echouee')),
      'annulees', (select count(*) from public.commandes c
                    where c.cree_le >= v_hier and c.cree_le < v_aujourdhui and c.etat = 'annulee')),
    'file', jsonb_build_object(
      'ouvertes', (select count(*) from public.rh_taches t where t.etat = 'ouverte'),
      'prises', (select count(*) from public.rh_taches t where t.etat = 'prise'),
      'escaladees', (select count(*) from public.rh_taches t where t.etat = 'ouverte' and t.escalade_le is not null)));
  v_montants := jsonb_build_object(
    'momopay_non_verifies', (select coalesce(sum(x.montant), 0) from public.encaissements x
                              where x.mode = 'mobile_money' and x.remis_le is null and x.montant > 0
                                and now() - x.encaisse_le > make_interval(hours => (sc ->> 'momopay_h')::int)),
    'dettes_retard', (select coalesce(sum(v.montant), 0) from public.reversements v
                       where v.etat = 'en_attente' and v.demande_le < now() - make_interval(days => (sa ->> 'dette_j')::int))
                     + (select coalesce(sum(v.montant), 0) from public.reversements_livreurs v
                         where v.etat = 'en_attente' and v.demande_le < now() - make_interval(days => (sa ->> 'dette_j')::int))
                     + (select coalesce(sum(v.montant), 0) from public.retraits_parrain v
                         where v.etat = 'demande' and v.demande_le < now() - make_interval(days => (sa ->> 'dette_j')::int)),
    'ventes_veille', (select coalesce(sum(c.total), 0) from public.commandes c
                       where c.paye_le >= v_hier and c.paye_le < v_aujourdhui));
  if v_hebdo then
    v_chiffres := v_chiffres || jsonb_build_object('semaine', jsonb_build_object(
      'payees', (select count(*) from public.commandes c where c.paye_le >= v_s1 and c.paye_le < v_aujourdhui),
      'payees_avant', (select count(*) from public.commandes c where c.paye_le >= v_s2 and c.paye_le < v_s1),
      'jamais_payees', (select count(*) from public.commandes c
                         where c.cree_le >= v_s1 and c.cree_le < v_aujourdhui and c.paye_le is null
                           and c.etat in ('a_payer', 'echouee')),
      'jamais_payees_avant', (select count(*) from public.commandes c
                               where c.cree_le >= v_s2 and c.cree_le < v_s1 and c.paye_le is null
                                 and c.etat in ('a_payer', 'echouee')),
      'reclamations', (select count(*) from public.reclamations r where r.cree_le >= v_s1 and r.cree_le < v_aujourdhui),
      'reclamations_avant', (select count(*) from public.reclamations r where r.cree_le >= v_s2 and r.cree_le < v_s1)));
    v_montants := v_montants || jsonb_build_object(
      'ventes_semaine', (select coalesce(sum(c.total), 0) from public.commandes c
                          where c.paye_le >= v_s1 and c.paye_le < v_aujourdhui),
      'ventes_semaine_avant', (select coalesce(sum(c.total), 0) from public.commandes c
                                where c.paye_le >= v_s2 and c.paye_le < v_s1));
  end if;
  insert into public.rh_bilans as b (jour, hebdo, chiffres, montants, cree_le)
  values (v_jour, v_hebdo, v_chiffres, v_montants, now())
  on conflict (jour) do update
     set hebdo = excluded.hebdo, chiffres = excluded.chiffres, montants = excluded.montants, cree_le = excluded.cree_le
  returning b.id into v_id;
  return v_id;
end $$;

/** Les derniers bilans (le plus récent d'abord). Sans montants pour un
    responsable de profil. Sans pg_cron, le bilan du jour se prépare à la
    première lecture après 7 h (heure du Bénin). */
create or replace function public.rh_bilans_lire(v_nombre int default 1) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_acces text := public.rh_bilan_acces();
begin
  if v_acces is null then
    raise exception 'Le bilan du matin est réservé à l''administration et aux responsables de profil';
  end if;
  if coalesce(v_nombre, 0) not between 1 and 90 then
    raise exception 'De 1 à 90 bilans à la fois';
  end if;
  if extract(hour from now() at time zone 'Africa/Porto-Novo') >= 7
     and not exists (select 1 from public.rh_bilans b where b.jour = (now() at time zone 'Africa/Porto-Novo')::date) then
    perform public.rh_preparer_bilan(false);
  end if;
  return jsonb_build_object(
    'acces', v_acces,
    'montants', v_acces = 'complet',
    'bilans', (select coalesce(jsonb_agg(jsonb_build_object('jour', b.jour, 'hebdo', b.hebdo, 'cree_le', b.cree_le,
                                                            'chiffres', b.chiffres)
                                         || case when v_acces = 'complet' then jsonb_build_object('montants', b.montants)
                                                 else '{}'::jsonb end
                                         order by b.jour desc), '[]'::jsonb)
                 from (select * from public.rh_bilans x order by x.jour desc limit v_nombre) b));
end $$;

-- ---------- Les droits ----------
revoke all on function public.rh_alertes_types() from public, anon;
grant execute on function public.rh_alertes_types() to authenticated, service_role;
revoke all on function public.rh_alerte_libelle(text) from public, anon;
grant execute on function public.rh_alerte_libelle(text) to authenticated, service_role;
revoke all on function public.rh_alertes_courantes() from public, anon, authenticated;
grant execute on function public.rh_alertes_courantes() to service_role;
revoke all on function public.rh_tache_visible(uuid) from public, anon;
grant execute on function public.rh_tache_visible(uuid) to authenticated, service_role;
revoke all on function public.rh_file_acces() from public, anon;
grant execute on function public.rh_file_acces() to authenticated, service_role;
revoke all on function public.rh_bilan_acces() from public, anon;
grant execute on function public.rh_bilan_acces() to authenticated, service_role;
revoke all on function public.rh_mon_nom() from public, anon;
grant execute on function public.rh_mon_nom() to authenticated, service_role;
revoke all on function public.rh_taches_synchroniser(boolean) from public, anon, authenticated;
grant execute on function public.rh_taches_synchroniser(boolean) to service_role;
revoke all on function public.rh_file_compteurs() from public, anon;
grant execute on function public.rh_file_compteurs() to authenticated, service_role;
revoke all on function public.rh_ma_file(text) from public, anon;
grant execute on function public.rh_ma_file(text) to authenticated, service_role;
revoke all on function public.rh_tache_a_moi(bigint) from public, anon, authenticated;
grant execute on function public.rh_tache_a_moi(bigint) to service_role;
revoke all on function public.rh_tache_prendre(bigint, boolean) from public, anon;
grant execute on function public.rh_tache_prendre(bigint, boolean) to authenticated, service_role;
revoke all on function public.rh_tache_relancer(bigint, text) from public, anon;
grant execute on function public.rh_tache_relancer(bigint, text) to authenticated, service_role;
revoke all on function public.rh_tache_terminer(bigint, text) from public, anon;
grant execute on function public.rh_tache_terminer(bigint, text) to authenticated, service_role;
revoke all on function public.rh_routage_lire() from public, anon;
grant execute on function public.rh_routage_lire() to authenticated, service_role;
revoke all on function public.rh_routage_regler(text, uuid, int, boolean) from public, anon;
grant execute on function public.rh_routage_regler(text, uuid, int, boolean) to authenticated, service_role;
revoke all on function public.rh_push_etat() from public, anon;
grant execute on function public.rh_push_etat() to authenticated, service_role;
revoke all on function public.rh_push_abonner(text, text, text) from public, anon;
grant execute on function public.rh_push_abonner(text, text, text) to authenticated, service_role;
revoke all on function public.rh_push_desabonner(text) from public, anon;
grant execute on function public.rh_push_desabonner(text) to authenticated, service_role;
revoke all on function public.rh_push_regler(boolean, text[], int, int) from public, anon;
grant execute on function public.rh_push_regler(boolean, text[], int, int) to authenticated, service_role;
revoke all on function public.rh_push_en_silence(int, int, timestamptz) from public, anon;
grant execute on function public.rh_push_en_silence(int, int, timestamptz) to authenticated, service_role;
revoke all on function public.rh_alertes_a_pousser() from public, anon, authenticated;
grant execute on function public.rh_alertes_a_pousser() to service_role;
revoke all on function public.rh_alertes_enregistrer() from public, anon, authenticated;
grant execute on function public.rh_alertes_enregistrer() to service_role;
revoke all on function public.rh_pousser_alertes() from public, anon, authenticated;
grant execute on function public.rh_pousser_alertes() to service_role;
revoke all on function public.rh_push_a_envoyer(bigint) from public, anon, authenticated;
grant execute on function public.rh_push_a_envoyer(bigint) to service_role;
revoke all on function public.rh_push_abonnement_mort(text) from public, anon, authenticated;
grant execute on function public.rh_push_abonnement_mort(text) to service_role;
revoke all on function public.rh_preparer_bilan(boolean) from public, anon, authenticated;
grant execute on function public.rh_preparer_bilan(boolean) to service_role;
revoke all on function public.rh_bilans_lire(int) from public, anon;
grant execute on function public.rh_bilans_lire(int) to authenticated, service_role;

-- ---------- Le calendrier ----------
-- Toutes les 5 minutes : la file (nouvelles tâches, disparues, escalades),
-- puis, une minute après, les alertes poussées. Chaque matin à 7 h (heure du
-- Bénin, 6 h UTC) : le bilan. Sans pg_cron, l'écran fait le nécessaire à
-- l'ouverture (file, bilan) ; seul le push attend pg_cron.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('rh-file-taches', '*/5 * * * *', 'select public.rh_taches_synchroniser()');
    perform cron.schedule('rh-alertes-push', '1-59/5 * * * *', 'select public.rh_pousser_alertes()');
    perform cron.schedule('rh-bilan-matin', '0 6 * * *', 'select public.rh_preparer_bilan()');
  end if;
exception when others then
  raise notice 'File, alertes et bilan non programmés (%), l''écran les rattrapera', sqlerrm;
end $$;
