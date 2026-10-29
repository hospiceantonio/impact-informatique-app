-- =========================================================
-- BIZZOO 3.69.0 — La clôture automatique des commandes, et le menu
-- Incidents de BIZZOO Personnel
--
--   Une commande payée dont tous les articles sont livrés et confirmés
--   par le client se clôture d'elle-même 24 heures après le dernier
--   « Je l'ai reçu » (délai réglable dans Suivi → Réglages ; vide :
--   à la main). Même règle que la clôture à la main, qui refuse
--   désormais aussi un reste non encaissé. pg_cron passe chaque heure.
--
--   Le menu Incidents liste tous les incidents ouverts et ceux de la
--   période ; un incident se signale par le numéro de la commande.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

alter table public.rh_reglages_suivi add column if not exists cloture_auto_h int default 24
  check (cloture_auto_h is null or cloture_auto_h between 0 and 720);

-- (3.70.0) Lues par les fonctions plus bas (déjà là sur une base en service).
create table if not exists public.refus_courses (
  id          bigserial primary key,
  commande_id text not null references public.commandes(id) on delete cascade,
  boutique_id text not null references public.boutiques(id) on delete cascade,
  livreur_id  uuid references public.profils(id) on delete set null,
  motif       text not null default '',
  refuse_le   timestamptz not null default now()
);
create index if not exists refus_courses_commande on public.refus_courses(commande_id, refuse_le desc);
alter table public.refus_courses enable row level security;
revoke all on public.refus_courses from anon, authenticated;
revoke all on sequence public.refus_courses_id_seq from anon, authenticated;

-- Empruntées par les fonctions plus bas, recopiées telles quelles.
create or replace function public.rh_cle(t text) returns text
language sql immutable set search_path = public as $$
  select btrim(regexp_replace(
           translate(lower(coalesce(t, '')),
                     'àâäáãéèêëíìîïóòôöõúùûüçñ''’-_/.,;:()',
                     'aaaaaeeeeiiiiooooouuuucn            '),
           '\s+', ' ', 'g'));
$$;
create or replace function public.rh_mon_profil() returns uuid
language sql stable security definer set search_path = public as $$
  select profil_id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
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
create or replace function public.rh_est_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and (administration or ceo));
$$;
create or replace function public.rh_moi() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;
create or replace function public.rh_suivi_acces() returns text
language sql stable security definer set search_path = public as $$
  select case
    when public.rh_est_admin() then 'admin'
    when public.rh_menu_ouvert('suivi') then 'responsable'
  end;
$$;
create or replace function public.rh_suivi_donnees(t1 timestamptz, t2 timestamptz, une text default null)
returns setof jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r public.rh_reglages_suivi;
  maintenant timestamptz := now();
begin
  select * into r from public.rh_reglages_suivi where id;
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

/**
 * Ce qui empêche de clôturer une commande, ou rien (null) : un incident
 * ouvert, un client qui conteste, un article qui n'a pas fini son
 * parcours (confirmé, annulé, échoué ou retourné), un reste à encaisser.
 * La même règle pour la clôture à la main et pour la clôture automatique.
 */
create or replace function public.rh_suivi_cloturable(d jsonb) returns text
language sql stable set search_path = public as $$
  select case
    when d ->> 'cloturee_le' is not null then 'Cette commande est déjà clôturée'
    when (d ->> 'incidents_ouverts')::int > 0 then 'Un incident reste ouvert : résolvez-le avant de clôturer'
    when exists (select 1 from jsonb_array_elements(d -> 'lignes') l where (l ->> 'rang')::int = 10)
      then 'Le client conteste encore la livraison : la réclamation doit être réglée avant de clôturer'
    when d ->> 'etat' = 'payee' and exists (select 1 from jsonb_array_elements(d -> 'lignes') l
                                             where (l ->> 'rang')::int not in (8, 9, 11, 13))
      then 'Un article n''a pas fini son parcours (livré et confirmé, annulé, échoué ou retourné)'
    -- (3.69.0) L'argent d'abord : un reste dû à la livraison doit être encaissé.
    when coalesce((d ->> 'reste')::bigint, 0) > 0
      then 'Un reste à encaisser n''est pas réglé : encaissez-le avant de clôturer'
  end;
$$;

/**
 * Clôturer : le suivi est terminé. REFUSÉ tant qu'un incident reste
 * ouvert, qu'un client conteste encore, qu'un article n'a pas fini
 * son parcours (confirmé, annulé, échoué ou retourné) ou qu'un reste
 * n'est pas encaissé.
 */
create or replace function public.rh_suivi_cloturer(commande text) returns void
language plpgsql security definer set search_path = public as $$
declare
  d jsonb;
  refus text;
begin
  if public.rh_suivi_acces() is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  select x into d from public.rh_suivi_donnees(null, null, commande) x;
  if d is null then
    raise exception 'Commande introuvable';
  end if;
  refus := public.rh_suivi_cloturable(d);
  if refus is not null then
    raise exception '%', refus;
  end if;
  insert into public.rh_suivi_commandes as s (commande_id, cloturee_le, cloturee_par, maj_par, maj_le)
  values (commande, now(), public.rh_moi(), public.rh_moi(), now())
  on conflict on constraint rh_suivi_commandes_pkey do update
     set cloturee_le = now(), cloturee_par = public.rh_moi(), maj_par = public.rh_moi(), maj_le = now();
  insert into public.rh_journal_lignes (commande_id, quoi, valeur) values (commande, 'suivi', 'cloturee');
end $$;

/** (3.69.0) Le délai de la clôture automatique, en heures ; vide : manuelle. */
create or replace function public.rh_suivi_regler_cloture(heures int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_admin() then
    raise exception 'Seule l''administration règle la clôture automatique';
  end if;
  if heures is not null and (heures < 0 or heures > 720) then
    raise exception 'Le délai de clôture : de 0 à 720 heures (30 jours), ou vide pour clôturer à la main';
  end if;
  update public.rh_reglages_suivi set cloture_auto_h = heures where id;
end $$;

/**
 * (3.69.0) LA CLÔTURE AUTOMATIQUE. Une commande payée dont TOUS les
 * articles sont livrés et confirmés par le client (ou annulés) se
 * clôture d'elle-même, le délai réglé passé après le dernier « Je l'ai
 * reçu » — le temps qu'un client signale un problème. Elle passe la même
 * règle que la clôture à la main (rh_suivi_cloturable). Ce qui demande
 * un regard reste à l'équipe : un échec, un retour, une contestation, un
 * encaissement contesté, et une commande que l'administration a
 * rouverte. Appelée par pg_cron chaque heure ; rend le nombre clôturé.
 */
create or replace function public.rh_suivi_cloturer_auto() returns int
language plpgsql security definer set search_path = public as $$
declare
  heures int;
  cible record;
  d jsonb;
  n int := 0;
begin
  select r.cloture_auto_h into heures from public.rh_reglages_suivi r where r.id;
  if heures is null then
    return 0;
  end if;
  for cible in
    select c.id from public.commandes c
     where c.etat = 'payee'
       and not exists (select 1 from public.rh_suivi_commandes s
                        where s.commande_id = c.id and s.cloturee_le is not null)
       and not exists (select 1 from public.rh_journal_lignes j
                        where j.commande_id = c.id and j.quoi = 'suivi' and j.valeur = 'rouverte')
       and exists (select 1 from public.commande_lignes l where l.commande_id = c.id and l.etat <> 'annulee')
       and not exists (select 1 from public.commande_lignes l
                        where l.commande_id = c.id and l.etat <> 'annulee' and l.confirme_le is null)
       and (select max(l.confirme_le) from public.commande_lignes l where l.commande_id = c.id)
             <= now() - make_interval(hours => heures)
     order by c.cree_le
     limit 500
  loop
    select x into d from public.rh_suivi_donnees(null, null, cible.id) x;
    continue when d is null or public.rh_suivi_cloturable(d) is not null;
    continue when exists (select 1 from jsonb_array_elements(d -> 'lignes') l
                           where (l ->> 'rang')::int not in (8, 11));
    continue when coalesce(d -> 'alertes', '[]'::jsonb) ? 'encaissement_conteste';
    insert into public.rh_suivi_commandes as s (commande_id, cloturee_le, cloturee_par, maj_par, maj_le)
    values (cible.id, now(), null, null, now())
    on conflict on constraint rh_suivi_commandes_pkey do update
       set cloturee_le = now(), cloturee_par = null, maj_le = now();
    insert into public.rh_journal_lignes (commande_id, quoi, valeur) values (cible.id, 'suivi', 'cloturee_auto');
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.rh_incident_ouvrir(commande text, type text, description text,
                                                     boutique text default null, livreur uuid default null)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  nouveau bigint;
  cible   text;
begin
  if public.rh_suivi_acces() is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  -- (3.69.0) La commande, par son identifiant ou par son numéro (« BZ-… »),
  -- comme on le lit au client : le menu Incidents n'a que lui.
  select c.id into cible from public.commandes c where c.id = commande;
  if cible is null then
    select min(c.id) into cible from public.commandes c
     where upper(c.numero) = upper(btrim(coalesce(commande, '')));
  end if;
  if cible is null then
    raise exception 'Commande introuvable : vérifiez son numéro';
  end if;
  if length(btrim(coalesce(description, ''))) = 0 then
    raise exception 'Décrivez l''incident';
  end if;
  insert into public.rh_incidents (commande_id, boutique_id, livreur_id, type, description, cree_par)
  values (cible, nullif(boutique, ''), livreur, type, btrim(description), public.rh_moi())
  returning id into nouveau;
  return nouveau;
end $$;

/**
 * (3.69.0) LE MENU INCIDENTS : tous les incidents encore ouverts, quelle
 * que soit leur date, et ceux signalés sur la période. Pour qui suit les
 * commandes.
 */
create or replace function public.rh_incidents_liste(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  fin date := coalesce(jusqu, aujourdhui);
  debut date := coalesce(depuis, coalesce(jusqu, aujourdhui) - 29);
begin
  if public.rh_suivi_acces() is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  if fin < debut then
    raise exception 'La fin de la période précède son début';
  end if;
  if fin - debut > 400 then
    raise exception 'Choisissez une période d''un an au plus';
  end if;
  return jsonb_build_object(
    'periode', jsonb_build_object('depuis', debut, 'jusqu', fin),
    'incidents', coalesce((select jsonb_agg(jsonb_build_object(
        'id', i.id, 'type', i.type, 'description', i.description, 'cree_le', i.cree_le,
        'commande_id', i.commande_id, 'numero', c.numero, 'client', c.client_nom,
        'boutique', coalesce(b.nom, i.boutique_id), 'livreur', coalesce(nullif(p.nom, ''), p.email),
        'auteur', btrim(coalesce(ea.prenoms, '') || ' ' || coalesce(ea.nom, '')),
        'resolu_le', i.resolu_le, 'resolution', i.resolution,
        'resolu_par', btrim(coalesce(er.prenoms, '') || ' ' || coalesce(er.nom, '')),
        'cloturee', sc.cloturee_le is not null)
      order by (i.resolu_le is null) desc, i.cree_le desc)
      from public.rh_incidents i
      left join public.commandes c on c.id = i.commande_id
      left join public.boutiques b on b.id = i.boutique_id
      left join public.profils p on p.id = i.livreur_id
      left join public.rh_employes ea on ea.id = i.cree_par
      left join public.rh_employes er on er.id = i.resolu_par
      left join public.rh_suivi_commandes sc on sc.commande_id = i.commande_id
     where i.resolu_le is null
        or (i.cree_le >= debut::timestamp at time zone 'Africa/Porto-Novo'
            and i.cree_le < (fin + 1)::timestamp at time zone 'Africa/Porto-Novo')), '[]'));
end $$;

/** (3.69.0) Les incidents ouverts : la pastille du menu Incidents. */
create or replace function public.rh_incidents_ouverts_nb() returns int
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rh_suivi_acces() is null then
    return 0;
  end if;
  return (select count(*) from public.rh_incidents where resolu_le is null);
end $$;

do $$
declare f text;
begin
  foreach f in array array['rh_suivi_regler_cloture(int)', 'rh_incidents_liste(date, date)',
                           'rh_incidents_ouverts_nb()', 'rh_suivi_cloturer(text)',
                           'rh_incident_ouvrir(text, text, text, text, uuid)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
  foreach f in array array['rh_suivi_cloturable(jsonb)', 'rh_suivi_cloturer_auto()',
                           'rh_suivi_donnees(timestamptz, timestamptz, text)', 'restes_par_boutique(text)',
                           'rh_statut_libelle(int)', 'rh_statut_ligne(text, timestamptz, text, boolean)',
                           'rh_zone_de(text)', 'rh_cle(text)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

-- La clôture automatique passe chaque heure. Sans pg_cron, rien ne
-- casse : les commandes se clôturent à la main, comme avant.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('rh-suivi-cloture-auto', '23 * * * *', 'select public.rh_suivi_cloturer_auto()');
  end if;
exception when others then
  raise notice 'Clôture automatique non programmée (%) : les commandes se clôturent à la main', sqlerrm;
end $$;
