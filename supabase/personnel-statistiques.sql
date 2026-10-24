-- =========================================================
-- BIZZOO Personnel : les statistiques de l'entreprise
--
-- Commandes, livraisons, SAV et avis, sur une période, lus dans
-- BIZZOO Personnel. Rien de la place de marché n'est modifié :
-- une seule fonction de lecture, qui décide elle-même de ce que
-- chacun voit.
--
--   le CEO            — tout, la marge de BIZZOO comprise ;
--   l'administration  — tout, sauf la marge ;
--   un responsable    — les seules rubriques que l'administration a
--                       ouvertes à son profil (« Logistique » →
--                       livraisons, par exemple), et AUCUN montant ;
--   les autres        — rien.
--
-- Les montants et la marge ne sont pas cachés par l'écran : ils ne
-- sortent pas de la base pour qui n'y a pas droit.
--
-- Se colle tel quel dans l'éditeur SQL de Supabase, et se rejoue.
-- =========================================================

-- Les rubriques qu'un profil voit, réglées par l'administration.
alter table public.rh_profils
  add column if not exists statistiques text[] not null default '{}';
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'rh_profils_statistiques_check') then
    alter table public.rh_profils add constraint rh_profils_statistiques_check
      check (statistiques <@ array['commandes', 'livraisons', 'sav']::text[]);
  end if;
end $$;

-- Qui est connecté : recopié de personnel.sql, pour que ce fichier se suffise.
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

/**
 * Les statistiques d'une période (par défaut, les 30 derniers jours,
 * heure du Bénin). Une commande compte au jour de son paiement ; une
 * ligne annulée ne compte jamais comme vente.
 */
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
  commandes jsonb := null;
  livraisons jsonb := null;
  sav jsonb := null;
begin
  if v_admin then
    rubriques := array['commandes', 'livraisons', 'sav'];
  else
    select coalesce(array_agg(distinct r), '{}') into rubriques
      from public.rh_profils p, unnest(p.statistiques) r
     where p.responsable_id is not null and p.responsable_id = public.rh_moi();
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
      'delai_moyen_heures', (select round(avg(extract(epoch from (recu_le - paye_le)) / 3600)::numeric, 1)
                               from lignes where etat = 'remise' and recu_le is not null and recu_le >= paye_le),
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

  return jsonb_build_object(
    'periode', jsonb_build_object('depuis', debut, 'jusqu', fin),
    'droits', jsonb_build_object('rubriques', to_jsonb(rubriques), 'argent', argent, 'marge', marge),
    'commandes', commandes, 'livraisons', livraisons, 'sav', sav);
end $$;

revoke all on function public.rh_statistiques(date, date) from public, anon;
grant execute on function public.rh_statistiques(date, date) to authenticated, service_role;
