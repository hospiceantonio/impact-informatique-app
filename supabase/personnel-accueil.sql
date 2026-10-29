-- =========================================================
-- BIZZOO Personnel : la place de marché d'un coup d'œil, sur l'accueil
--
-- Une seule lecture, rh_accueil_chiffres() : le mois en cours et
-- aujourd'hui (heure du Bénin) pour les commandes, les livraisons, les
-- clients, les boutiques, les produits, les livreurs, les avis et le SAV.
-- Mêmes droits que les Statistiques :
--   - les nombres : l'administration, le superadministrateur, et les
--     profils à qui Paramètres ouvre les statistiques des commandes ;
--   - les montants (ventes, frais de livraison, panier moyen) :
--     l'administration et le superadministrateur ;
--   - la marge de BIZZOO : le CEO et le superadministrateur.
-- Les autres reçoivent null : leur accueil reste celui de leurs tâches.
-- =========================================================

-- (3.70.0) Lues par les fonctions plus bas (déjà là sur une base en service).
alter table public.profils add column if not exists disponible boolean not null default true;

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

create or replace function public.rh_accueil_chiffres() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  m1 timestamptz := date_trunc('month', aujourdhui)::timestamp at time zone 'Africa/Porto-Novo';
  j1 timestamptz := aujourdhui::timestamp at time zone 'Africa/Porto-Novo';
  argent boolean := public.rh_est_admin() or public.est_super();
  marge boolean := public.rh_est_ceo() or public.est_super();
begin
  if not (argent or public.rh_menu_ouvert('stats_commandes')) then
    return null;
  end if;
  return (
    with payees_mois as (
      select c.* from public.commandes c where c.etat = 'payee' and c.paye_le >= m1
    ),
    lignes_mois as (
      select l.* from public.commande_lignes l join payees_mois c on c.id = l.commande_id
       where l.etat <> 'annulee'
    ),
    -- Ce qui est en route aujourd'hui : les articles de commandes payées.
    lignes_ouvertes as (
      select l.* from public.commande_lignes l join public.commandes c on c.id = l.commande_id
       where c.etat = 'payee' and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')
    )
    select jsonb_build_object(
      'mois', date_trunc('month', aujourdhui)::date,
      'droits', jsonb_build_object('argent', argent, 'marge', marge),
      'commandes', jsonb_build_object(
        'recues_mois', (select count(*) from public.commandes c where c.cree_le >= m1),
        'payees_mois', (select count(*) from payees_mois),
        'payees_jour', (select count(*) from payees_mois where paye_le >= j1),
        'a_payer_mois', (select count(*) from public.commandes c where c.etat = 'a_payer' and c.cree_le >= m1),
        'annulees_mois', (select count(*) from public.commandes c where c.etat in ('annulee', 'echouee') and c.cree_le >= m1),
        'revendeurs_mois', (select count(*) from payees_mois where revendeur),
        'articles_mois', (select coalesce(sum(quantite), 0) from lignes_mois),
        'ventes_mois', case when argent then (select coalesce(sum(total), 0) from payees_mois) end,
        'ventes_jour', case when argent then (select coalesce(sum(total), 0) from payees_mois where paye_le >= j1) end,
        'panier_moyen', case when argent then (select coalesce(round(avg(total)), 0) from payees_mois) end,
        'frais_livraison_mois', case when argent then (select coalesce(sum(frais_livraison), 0) from payees_mois) end,
        'remises_mois', case when argent then (select coalesce(sum(remise), 0) from payees_mois) end,
        'marge_mois', case when marge then
          (select coalesce(sum(greatest(0, prix - prix_bizzoo) * quantite), 0) from lignes_mois) end),
      'livraisons', jsonb_build_object(
        'confirmees_mois', (select count(*) from public.commande_lignes l where l.confirme_le >= m1),
        'a_preparer', (select count(*) from lignes_ouvertes where etat in ('nouvelle', 'vue')),
        'pretes', (select count(*) from lignes_ouvertes where etat = 'preparee'),
        'en_livraison', (select count(*) from lignes_ouvertes where etat = 'en_livraison'),
        'livrees_sans_confirmation', (select count(*) from public.commande_lignes l join public.commandes c on c.id = l.commande_id
                                        where c.etat = 'payee' and l.etat = 'remise' and l.confirme_le is null),
        'livreurs', (select count(*) from public.profils p where p.role = 'livreur' and p.actif),
        'livreurs_en_course', (select count(distinct livreur_id) from lignes_ouvertes where livreur_id is not null and etat = 'en_livraison')),
      'clients', jsonb_build_object(
        'total', (select count(*) from public.clients),
        'nouveaux_mois', (select count(*) from public.clients k where k.cree_le >= m1),
        'nouveaux_jour', (select count(*) from public.clients k where k.cree_le >= j1),
        'verifies', (select count(*) from public.clients k where k.tel_verifie),
        'acheteurs_mois', (select count(distinct client_id) from payees_mois where client_id is not null),
        'revendeurs', (select count(*) from public.clients k where k.revendeur_etat = 'validee'),
        'revendeurs_en_attente', (select count(*) from public.clients k where k.revendeur_etat = 'en_attente')),
      'boutiques', jsonb_build_object(
        'total', (select count(*) from public.boutiques),
        'actives', (select count(*) from public.boutiques b where b.actif),
        'nouvelles_mois', (select count(*) from public.boutiques b where b.cree_le >= m1),
        'ayant_vendu_mois', (select count(distinct boutique_id) from lignes_mois)),
      'produits', jsonb_build_object(
        'total', (select count(*) from public.produits p where not p.masque),
        'disponibles', (select count(*) from public.produits p where not p.masque and p.disponible),
        'ruptures', (select count(*) from public.produits p where not p.masque and not p.sur_commande and p.stock = 0),
        'nouveaux_mois', (select count(*) from public.produits p where p.cree_le >= m1),
        'masques', (select count(*) from public.produits p where p.masque)),
      'avis', jsonb_build_object(
        'mois', (select count(*) from public.avis a where a.cree_le >= m1),
        'note_moyenne', (select round(avg(note)::numeric, 2) from public.avis a where not a.masque)),
      'sav', jsonb_build_object(
        'ouvertes', (select count(*) from public.reclamations r where r.etat in ('ouverte', 'escaladee')),
        'mois', (select count(*) from public.reclamations r where r.cree_le >= m1))
    ));
end $$;

-- ---------- Ce qui change (copies de schema.sql) ----------

revoke all on function public.rh_accueil_chiffres() from public, anon;
grant execute on function public.rh_accueil_chiffres() to authenticated, service_role;
