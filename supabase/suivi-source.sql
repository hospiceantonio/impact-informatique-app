-- =========================================================
-- BIZZOO 3.68.0 — La colonne « Source » du suivi des commandes
--
--   BIZZOO Personnel affiche d'où vient chaque commande : « Depuis APP »
--   (passée dans l'application) ou « Par whatsapp » (saisie par l'équipe
--   avec « Faire livrer »). Seule la fonction interne du suivi change ;
--   aucune table, aucune donnée.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

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

-- Empruntées par la fonction plus bas, recopiées telles quelles.
create or replace function public.rh_cle(t text) returns text
language sql immutable set search_path = public as $$
  select btrim(regexp_replace(
           translate(lower(coalesce(t, '')),
                     'àâäáãéèêëíìîïóòôöõúùûüçñ''’-_/.,;:()',
                     'aaaaaeeeeiiiiooooouuuucn            '),
           '\s+', ' ', 'g'));
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

/**
 * Le suivi d'une liste de commandes : une ligne JSON par commande,
 * articles et marchands compris, alertes calculées. Interne : les
 * fonctions publiques vérifient d'abord qui appelle et ôtent les
 * montants à qui n'y a pas droit.
 */
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

-- Internes : seules les fonctions du suivi les appellent.
revoke all on function public.rh_suivi_donnees(timestamptz, timestamptz, text) from public, anon, authenticated;
revoke all on function public.restes_par_boutique(text) from public, anon, authenticated;
revoke all on function public.rh_statut_libelle(int) from public, anon, authenticated;
revoke all on function public.rh_statut_ligne(text, timestamptz, text, boolean) from public, anon, authenticated;
revoke all on function public.rh_zone_de(text) from public, anon, authenticated;
revoke all on function public.rh_cle(text) from public, anon, authenticated;
