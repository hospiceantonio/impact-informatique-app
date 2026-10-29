-- =========================================================
-- BIZZOO Personnel : les contrôles (réglages sensibles, encaissements,
-- veille des livreurs)
--
-- 1. L'HISTORIQUE DES RÉGLAGES SENSIBLES. Chaque changement de
--    « paiement » (bac à sable, paiement fermé, agrégateur, code
--    MoMoPay, tarifs), de « reglages » (compte obligatoire) et des
--    numéros de réception des boutiques est gardé, champ par champ, avec
--    son auteur, l'ancienne et la nouvelle valeur. Il reste en alerte
--    rouge (accueil, menu Contrôles) tant que le CEO ou le
--    superadministrateur ne l'a pas dit « vu et approuvé ».
--    L'administration le lit ; les codes et numéros sont tronqués.
-- 2. LE CONTRÔLE DES ENCAISSEMENTS À LA LIVRAISON : MoMoPay pas encore
--    vérifié, espèces pas encore rendues, livraisons sans déclaration,
--    écarts et contestations, par livreur et avec leur ancienneté.
--    Montants : l'administration et le superadministrateur ; la clé
--    « controles » de Paramètres ouvre la version sans montants.
-- 3. LA VEILLE DES LIVREURS dans le suivi des commandes : « course sans
--    livreur » et « livreur muet » (en route, sans position), et le
--    livreur muet en orange sur la carte Localiser.
-- =========================================================
--
-- À coller tel quel dans l'éditeur SQL ; il se rejoue sans dommage.
-- =========================================================

alter table public.profils add column if not exists courses_bloquees boolean not null default false;

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

create or replace function public.coord_valable(valeur double precision, borne double precision)
returns double precision
language sql immutable as $$
  select case when valeur is null
                or valeur <> valeur              -- « NaN » ne s'égale pas lui-même
                or valeur < -borne or valeur > borne
              then null else valeur end;
$$;

create or replace function public.livreur_en_course(qui uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
     where l.livreur_id = qui and c.etat = 'payee'
       and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison'));
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

-- FIN DES AIDES

-- ---------- La clé « controles » dans Paramètres ----------
-- Elle ouvre le contrôle des encaissements SANS montants (nombres et
-- ancienneté) aux profils choisis, la logistique par exemple.
do $$
begin
  if to_regclass('public.rh_acces_menus') is null then
    return;
  end if;
  if exists (select 1 from pg_constraint where conname = 'rh_acces_menus_menu'
               and pg_get_constraintdef(oid) not like '%''controles''%') then
    alter table public.rh_acces_menus drop constraint rh_acces_menus_menu;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_acces_menus_menu') then
    alter table public.rh_acces_menus add constraint rh_acces_menus_menu check (menu in ('mails',
      'discussions', 'missions', 'rapports', 'depenses', 'suivi', 'livreurs', 'controles', 'paiements', 'audit', 'promos', 'qualite', 'caisse', 'stats_commandes',
      'stats_boutiques', 'stats_produits', 'stats_livraisons', 'stats_livreurs', 'stats_sav', 'employes'));
  end if;
end $$;

-- ---------- Les seuils, avec ceux du suivi ----------
-- Veille des livreurs, en minutes : une course payée que personne ne
-- prend, un livreur en route dont le téléphone se tait. Encaissements :
-- au-delà de combien d'heures un MoMoPay non vérifié ou des espèces non
-- rendues deviennent « anciens », et à combien d'anciens un livreur est
-- signalé (sa fiche propose alors le blocage, qui existe déjà).
alter table public.rh_reglages_suivi add column if not exists prise_course_min int not null default 30
  check (prise_course_min between 5 and 1440);
alter table public.rh_reglages_suivi add column if not exists position_min int not null default 15
  check (position_min between 2 and 720);
alter table public.rh_reglages_suivi add column if not exists momopay_h int not null default 48
  check (momopay_h between 1 and 720);
alter table public.rh_reglages_suivi add column if not exists especes_h int not null default 24
  check (especes_h between 1 and 720);
alter table public.rh_reglages_suivi add column if not exists plafond_nb int not null default 3
  check (plafond_nb between 1 and 100);

-- ---------- L'historique des réglages sensibles ----------
-- Un code MoMoPay changé envoie tous les restes payés à la livraison sur
-- un autre compte ; un « bac à sable » coché par erreur arrête toutes
-- les ventes réelles. Jusqu'ici seul « maj_le » bougeait, sans auteur ni
-- valeur d'avant. Chaque changement de « paiement », « reglages » et
-- « boutiques_reception » s'écrit ici, champ par champ, et attend que le
-- CEO ou le superadministrateur le dise « vu et approuvé ».
--
-- Table FIGÉE : on n'efface rien, on ne réécrit rien ; seule
-- l'approbation se pose, une fois. Personne ne la lit directement : les
-- valeurs entières (code MoMoPay, numéros) n'en sortent que tronquées,
-- par rh_audit_reglages_liste.
create table if not exists public.rh_audit_reglages (
  id            bigint generated always as identity primary key,
  le            timestamptz not null default now(),
  table_nom     text not null,
  cible         text not null default '',
  champ         text not null,
  avant         text,
  apres         text,
  par_compte    uuid,
  par_nom       text not null default '',
  critique      boolean not null default false,
  approuve_le   timestamptz,
  approuve_par  uuid,
  approuve_nom  text not null default ''
);
create index if not exists rh_audit_reglages_attente on public.rh_audit_reglages (le desc) where approuve_le is null;
alter table public.rh_audit_reglages enable row level security;
revoke all on table public.rh_audit_reglages from public, anon, authenticated;
revoke all on sequence public.rh_audit_reglages_id_seq from public, anon, authenticated;
grant all on table public.rh_audit_reglages to service_role;
grant usage, select on sequence public.rh_audit_reglages_id_seq to service_role;

create or replace function public.rh_audit_reglages_fige() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'L''historique des réglages ne s''efface pas';
  end if;
  if old.approuve_le is not null
     or (to_jsonb(new) - 'approuve_le' - 'approuve_par' - 'approuve_nom')
        is distinct from (to_jsonb(old) - 'approuve_le' - 'approuve_par' - 'approuve_nom') then
    raise exception 'L''historique des réglages ne se réécrit pas : un changement s''approuve, une fois';
  end if;
  return new;
end $$;
drop trigger if exists rh_audit_reglages_fige on public.rh_audit_reglages;
create trigger rh_audit_reglages_fige
  before update or delete on public.rh_audit_reglages
  for each row execute function public.rh_audit_reglages_fige();

/** Le nom de qui a fait le changement : l'employé, sinon le compte de la place de marché. */
create or replace function public.rh_audit_qui(compte uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select nullif(btrim(coalesce(e.prenoms, '') || ' ' || coalesce(e.nom, '')), '')
       from public.rh_employes e where e.compte_id = compte
      order by (e.etat = 'actif') desc limit 1),
    (select coalesce(nullif(btrim(p.nom), ''), p.email) from public.profils p where p.id = compte),
    'Compte ' || left(compte::text, 8));
$$;

/** Ce qui ouvre l'argent ou le ferme : l'alerte la plus haute. */
create or replace function public.rh_audit_critique(t text, c text) returns boolean
language sql immutable set search_path = public as $$
  select (t = 'paiement' and c in ('actif', 'bac_a_sable', 'fournisseur', 'cle_publique', 'momopay_code', 'momopay_nom'))
      or t in ('reglages', 'boutiques_reception');
$$;

/** Une valeur montrable : les codes, clés et numéros tronqués. */
create or replace function public.rh_audit_affiche(t text, c text, v text) returns text
language sql immutable set search_path = public as $$
  select case
    when v is null or v = '' then '(vide)'
    when c in ('momopay_code', 'cle_publique', 'tel') then
      case when length(v) <= 4 then left(v, 1) || '…' else left(v, 3) || '…' || right(v, 2) end
    when v = 'true' then 'oui'
    when v = 'false' then 'non'
    else v end;
$$;

/** Ce que le changement veut dire, en une phrase. */
create or replace function public.rh_audit_libelle(t text, c text, av text, ap text) returns text
language sql immutable set search_path = public as $$
  select case
    when t = 'paiement' and c = 'bac_a_sable' then
      case when ap = 'true' then 'Paiement passé en mode essai (bac à sable) : plus aucune vente réelle ne passe'
           else 'Paiement passé en production (argent réel)' end
    when t = 'paiement' and c = 'actif' then
      case when ap = 'true' then 'Paiement en ligne ouvert' else 'Paiement en ligne fermé' end
    when t = 'paiement' and c = 'fournisseur' then 'Agrégateur de paiement changé'
    when t = 'paiement' and c = 'momopay_code' then 'Code MoMoPay changé : les restes payés à la livraison partent sur ce compte'
    when t = 'paiement' and c = 'momopay_nom' then 'Nom du compte MoMoPay changé'
    when t = 'paiement' and c = 'cle_publique' then 'Clé publique de paiement changée'
    when t = 'paiement' and c = 'taux_acompte' then 'Acompte à la commande changé (en %)'
    when t = 'paiement' and c = 'taux_livreur' then 'Part du livreur changée (en %)'
    when t = 'paiement' and c = 'frais_livraison' then 'Frais de livraison changés'
    when t = 'paiement' and c = 'moto_forfait' then 'Tarif de livraison changé : forfait moto'
    when t = 'paiement' and c = 'moto_prix_km' then 'Tarif de livraison changé : prix au km en moto'
    when t = 'paiement' and c = 'tricycle_forfait' then 'Tarif de livraison changé : forfait tricycle'
    when t = 'paiement' and c = 'tricycle_prix_km' then 'Tarif de livraison changé : prix au km en tricycle'
    when t = 'paiement' and c = 'livraison_coef' then 'Coefficient de la route changé'
    when t = 'paiement' and c = 'livraison_rayon_km' then 'Rayon de livraison changé (km)'
    when t = 'paiement' and c in ('livraison_latitude', 'livraison_longitude', 'livraison_adresse') then 'Point de départ des livraisons changé'
    when t = 'reglages' and c = 'compte_obligatoire' then
      case when ap = 'true' then 'Compte obligatoire pour commander' else 'Commande sans compte de nouveau permise' end
    when t = 'boutiques_reception' and c = 'tel' then 'Numéro de réception des reversements changé'
    when t = 'boutiques_reception' and c = 'reseau' then 'Réseau de réception des reversements changé'
    when t = 'boutiques_reception' and c = 'titulaire' then 'Titulaire du numéro de réception changé'
    else 'Réglage « ' || c || ' » changé' end;
$$;

/* JAMAIS D'ERREUR VERS ADMIN NI CLIENT : ce déclencheur vit sur des
   tables de la place de marché. Tout est dans un bloc qui avale ses
   propres échecs. Un historique manqué se regrette ; un réglage refusé
   à cause de lui, jamais. On compare la ligne entière, champ par champ :
   une colonne ajoutée demain sera suivie sans rien changer ici. */
create or replace function public.rh_audit_reglages_noter() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  avant jsonb;
  apres jsonb;
  v_cible text := '';
  v_qui uuid;
  v_nom text;
  k text;
begin
  begin
    avant := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else '{}'::jsonb end;
    apres := case when tg_op in ('UPDATE', 'INSERT') then to_jsonb(new) else '{}'::jsonb end;
    v_qui := auth.uid();
    v_nom := case when v_qui is null then 'Système (aucun compte connecté)' else public.rh_audit_qui(v_qui) end;
    if tg_table_name = 'boutiques_reception' then
      v_cible := coalesce(apres ->> 'boutique_id', avant ->> 'boutique_id', '');
    end if;
    for k in select x.cle from (select jsonb_object_keys(avant) as cle
                                union select jsonb_object_keys(apres)) x order by 1 loop
      continue when k in ('id', 'boutique_id', 'maj_le', 'maj_par');
      if coalesce(avant ->> k, '') is distinct from coalesce(apres ->> k, '') then
        insert into public.rh_audit_reglages (table_nom, cible, champ, avant, apres, par_compte, par_nom, critique)
        values (tg_table_name, v_cible, k, avant ->> k, apres ->> k, v_qui, coalesce(v_nom, ''),
                public.rh_audit_critique(tg_table_name, k));
      end if;
    end loop;
  exception when others then
    raise warning 'rh_audit_reglages_noter : % (%)', sqlerrm, sqlstate;
  end;
  return null;
end $$;

drop trigger if exists rh_audit_paiement on public.paiement;
create trigger rh_audit_paiement
  after update on public.paiement
  for each row execute function public.rh_audit_reglages_noter();
drop trigger if exists rh_audit_reglages on public.reglages;
create trigger rh_audit_reglages
  after update on public.reglages
  for each row execute function public.rh_audit_reglages_noter();
drop trigger if exists rh_audit_boutiques_reception on public.boutiques_reception;
create trigger rh_audit_boutiques_reception
  after insert or update or delete on public.boutiques_reception
  for each row execute function public.rh_audit_reglages_noter();

/** Qui ouvre le menu Contrôles : « admin » (l'administration et le
    superadministrateur : réglages sensibles et montants), « logistique »
    (un profil à qui Paramètres ouvre « controles » : les encaissements
    en nombres et en ancienneté), ou rien. */
create or replace function public.rh_controles_acces() returns text
language sql stable security definer set search_path = public as $$
  select case
    when public.rh_est_admin() or public.est_super() then 'admin'
    when public.rh_menu_ouvert('controles') then 'logistique'
  end;
$$;

/** Les seuils de la veille et des encaissements, valeurs de départ comprises. */
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

/** L'historique des réglages sensibles : l'administration le lit, le CEO
    et le superadministrateur l'approuvent. */
create or replace function public.rh_audit_reglages_liste(seulement_a_approuver boolean default false)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.rh_est_admin() or public.est_super()) then
    raise exception 'L''historique des réglages est réservé à l''administration et au superadministrateur';
  end if;
  return jsonb_build_object(
    'approuver', public.rh_est_ceo() or public.est_super(),
    'a_approuver', (select count(*) from public.rh_audit_reglages a where a.approuve_le is null),
    'changements', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', a.id, 'le', a.le, 'table', a.table_nom,
        'boutique', case when a.table_nom = 'boutiques_reception' then coalesce(b.nom, a.cible) end,
        'champ', a.champ,
        'libelle', public.rh_audit_libelle(a.table_nom, a.champ, a.avant, a.apres),
        'avant', public.rh_audit_affiche(a.table_nom, a.champ, a.avant),
        'apres', public.rh_audit_affiche(a.table_nom, a.champ, a.apres),
        'par', a.par_nom, 'critique', a.critique,
        'approuve_le', a.approuve_le, 'approuve_par', nullif(a.approuve_nom, ''))
        order by a.le desc, a.id desc), '[]')
      from (select * from public.rh_audit_reglages x
             where not coalesce(seulement_a_approuver, false) or x.approuve_le is null
             order by x.le desc, x.id desc limit 300) a
      left join public.boutiques b on b.id = a.cible));
end $$;

/** « Vu et approuvé » : le CEO ou le superadministrateur, une fois par changement. */
create or replace function public.rh_audit_approuver(ids bigint[]) returns int
language plpgsql security definer set search_path = public as $$
declare
  n int;
begin
  if not (public.rh_est_ceo() or public.est_super()) then
    raise exception 'Seuls le CEO et le superadministrateur approuvent un changement de réglage';
  end if;
  if ids is null or cardinality(ids) = 0 then
    raise exception 'Choisissez au moins un changement';
  end if;
  update public.rh_audit_reglages a
     set approuve_le = now(), approuve_par = auth.uid(), approuve_nom = coalesce(public.rh_audit_qui(auth.uid()), '')
   where a.id = any(ids) and a.approuve_le is null;
  get diagnostics n = row_count;
  if n = 0 then
    raise exception 'Rien à approuver : ces changements le sont déjà';
  end if;
  return n;
end $$;

/** Régler les seuils des encaissements : l'administration et le superadministrateur. */
create or replace function public.rh_controles_regler(v_momopay_h int, v_especes_h int, v_plafond_nb int)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.rh_est_admin() or public.est_super()) then
    raise exception 'Seuls l''administration et le superadministrateur règlent les seuils des contrôles';
  end if;
  if coalesce(v_momopay_h, 0) not between 1 and 720 or coalesce(v_especes_h, 0) not between 1 and 720 then
    raise exception 'Les délais se comptent en heures, de 1 à 720';
  end if;
  if coalesce(v_plafond_nb, 0) not between 1 and 100 then
    raise exception 'Le plafond se compte en encaissements, de 1 à 100';
  end if;
  update public.rh_reglages_suivi
     set momopay_h = v_momopay_h, especes_h = v_especes_h, plafond_nb = v_plafond_nb
   where id;
end $$;

/** Régler la veille des livreurs, avec les autres délais du suivi : l'administration. */
create or replace function public.rh_suivi_regler_veille(v_prise_course_min int, v_position_min int)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_admin() then
    raise exception 'Seule l''administration règle les délais';
  end if;
  if coalesce(v_prise_course_min, 0) not between 5 and 1440 then
    raise exception 'Une course sans livreur se signale entre 5 et 1 440 minutes';
  end if;
  if coalesce(v_position_min, 0) not between 2 and 720 then
    raise exception 'Un livreur muet se signale entre 2 et 720 minutes';
  end if;
  update public.rh_reglages_suivi
     set prise_course_min = v_prise_course_min, position_min = v_position_min
   where id;
end $$;

/**
 * Le contrôle des encaissements à la livraison. Ce qui attend (MoMoPay
 * pas encore retrouvé dans le compte de BIZZOO, espèces pas encore
 * rendues, livraisons sans déclaration alors qu'un reste était dû) quelle
 * que soit la période, et ce qui s'est mal passé sur la période (écarts
 * entre le dû et le déclaré, contestations). Par livreur et ligne par
 * ligne. Les montants et le numéro de transaction : l'administration et
 * le superadministrateur seulement ; la logistique a les nombres et
 * l'ancienneté. Rien ne s'écrit ici : « Vérifié » se touche dans BIZZOO
 * Admin, menu Caisse.
 */
create or replace function public.rh_encaissements(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  acces text := public.rh_controles_acces();
  argent boolean;
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  d1 date := coalesce(depuis, aujourdhui - 29);
  d2 date := coalesce(jusqu, aujourdhui);
  t1 timestamptz;
  t2 timestamptz;
  s jsonb;
  h_momo int;
  h_esp int;
  plafond int;
  resultat jsonb;
begin
  if acces is null then
    raise exception 'Votre compte n''a pas accès au contrôle des encaissements';
  end if;
  if d2 < d1 then
    raise exception 'La fin de la période précède son début';
  end if;
  if d2 - d1 > 400 then
    raise exception 'Choisissez une période d''un an au plus';
  end if;
  argent := acces = 'admin';
  s := public.rh_controles_seuils();
  h_momo := (s ->> 'momopay_h')::int;
  h_esp := (s ->> 'especes_h')::int;
  plafond := (s ->> 'plafond_nb')::int;
  t1 := d1::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (d2 + 1)::timestamp at time zone 'Africa/Porto-Novo';

  with e as (
    select x.id, x.commande_id, c.numero, x.boutique_id, x.livreur_id, x.du, x.montant, x.mode,
           x.transaction_id, x.encaisse_le as le, x.remis_le, x.conteste_le,
           case when x.mode = 'mobile_money' and x.remis_le is null then 'momopay_a_verifier'
                when x.mode <> 'mobile_money' and x.remis_le is null and x.montant > 0 then 'especes_non_remises'
                when x.conteste_le is not null then 'conteste'
                when x.montant <> x.du then 'ecart'
                else 'regle' end as statut,
           x.montant <> x.du as ecart
      from public.encaissements x
      join public.commandes c on c.id = x.commande_id
     where (x.remis_le is null and x.montant > 0)
        or (x.encaisse_le >= t1 and x.encaisse_le < t2)
    union all
    -- Livré alors qu'un reste était dû, sans rien déclarer (application
    -- d'avant 3.59.0) : la même règle que la caisse de BIZZOO Admin.
    select null::bigint, l.commande_id, c.numero, l.boutique_id, l.livreur_id, r.a_encaisser, 0::bigint, 'aucun'::text,
           ''::text, max(c.paye_le), null::timestamptz, null::timestamptz, 'non_declare'::text, false
      from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id and c.etat = 'payee'
      join lateral (select rr.a_encaisser from public.restes_par_boutique(l.commande_id) rr
                     where rr.boutique_id = l.boutique_id) r on true
     where l.etat = 'remise'
       and c.paye_le >= least(t1, now() - interval '60 days') and c.paye_le < t2
       and r.a_encaisser > 0
       and not exists (select 1 from public.encaissements x
                        where x.commande_id = l.commande_id and x.boutique_id = l.boutique_id)
     group by l.commande_id, c.numero, l.boutique_id, l.livreur_id, r.a_encaisser
  ),
  f as (
    select e.*,
           greatest(0, floor(extract(epoch from (now() - e.le)) / 3600))::int as heures,
           case e.statut when 'momopay_a_verifier' then now() - e.le > make_interval(hours => h_momo)
                         when 'especes_non_remises' then now() - e.le > make_interval(hours => h_esp)
                         when 'non_declare' then true
                         else false end as ancien,
           e.statut in ('momopay_a_verifier', 'especes_non_remises', 'non_declare') as en_attente,
           -- Ce qui attend s'affiche quelle que soit sa date ; un écart ou
           -- une contestation, seulement dans la période choisie (l'écran le
           -- dit). Sans cela, des espèces non rendues d'il y a trois mois
           -- gonflaient les écarts des « 7 derniers jours ».
           (e.ecart and e.le >= t1 and e.le < t2) as ecart_p,
           (e.conteste_le is not null and e.le >= t1 and e.le < t2) as conteste_p
      from e
  )
  select jsonb_build_object(
    'periode', jsonb_build_object('depuis', d1, 'jusqu', d2),
    'montants', argent,
    'seuils', s,
    'totaux', (select jsonb_build_object(
        'momopay_a_verifier', count(*) filter (where f.statut = 'momopay_a_verifier'),
        'momopay_anciens', count(*) filter (where f.statut = 'momopay_a_verifier' and f.ancien),
        'especes_non_remises', count(*) filter (where f.statut = 'especes_non_remises'),
        'especes_anciennes', count(*) filter (where f.statut = 'especes_non_remises' and f.ancien),
        'non_declares', count(*) filter (where f.statut = 'non_declare'),
        'ecarts', count(*) filter (where f.ecart_p),
        'contestes', count(*) filter (where f.conteste_p),
        'verifies', count(*) filter (where f.mode = 'mobile_money' and f.remis_le is not null),
        'plus_ancien', min(f.le) filter (where f.en_attente))
      || case when argent then jsonb_build_object(
        'montant_a_verifier', coalesce(sum(f.montant) filter (where f.statut = 'momopay_a_verifier'), 0),
        'montant_especes', coalesce(sum(f.montant) filter (where f.statut = 'especes_non_remises'), 0),
        'montant_non_declare', coalesce(sum(f.du) filter (where f.statut = 'non_declare'), 0),
        'ecart_total', coalesce(sum(f.du - f.montant) filter (where f.ecart_p), 0))
        else '{}'::jsonb end
      from f),
    'livreurs', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', g.livreur_id,
        'nom', coalesce(nullif(btrim(p.nom), ''), p.email, 'Livreur inconnu'),
        'tel', coalesce(p.tel, ''),
        'boutique', (select b.nom from public.boutiques b where b.id = p.boutique_id),
        'bloque', coalesce(p.courses_bloquees, false),
        'en_attente', g.en_attente, 'anciens', g.anciens, 'plus_ancien', g.plus_ancien,
        'ecarts', g.ecarts, 'contestes', g.contestes, 'au_plafond', g.anciens >= plafond)
        || case when argent then jsonb_build_object('montant', g.montant) else '{}'::jsonb end
        order by g.anciens desc, g.en_attente desc, p.nom), '[]')
      from (select f.livreur_id,
                   count(*) filter (where f.en_attente) as en_attente,
                   count(*) filter (where f.en_attente and f.ancien) as anciens,
                   min(f.le) filter (where f.en_attente) as plus_ancien,
                   count(*) filter (where f.ecart_p) as ecarts,
                   count(*) filter (where f.conteste_p) as contestes,
                   coalesce(sum(case when f.statut = 'non_declare' then f.du else f.montant end)
                              filter (where f.en_attente), 0) as montant
              from f
             group by f.livreur_id
            having count(*) filter (where f.en_attente or f.ecart_p or f.conteste_p) > 0) g
      left join public.profils p on p.id = g.livreur_id),
    'lignes', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', k.id, 'commande', k.commande_id, 'numero', k.numero,
        'boutique', coalesce(b.nom, k.boutique_id),
        'livreur_id', k.livreur_id, 'livreur', coalesce(nullif(btrim(p.nom), ''), p.email, 'Livreur inconnu'),
        'mode', k.mode, 'statut', k.statut, 'le', k.le, 'heures', k.heures, 'ancien', k.ancien,
        'ecart', k.ecart, 'conteste', k.conteste_le is not null, 'remis_le', k.remis_le)
        || case when argent then jsonb_build_object('du', k.du, 'montant', k.montant,
                                                   'transaction', k.transaction_id) else '{}'::jsonb end
        order by k.ancien desc, k.le), '[]')
      from (select * from f where f.en_attente or f.ecart_p or f.conteste_p
             order by f.ancien desc, f.le limit 500) k
      left join public.boutiques b on b.id = k.boutique_id
      left join public.profils p on p.id = k.livreur_id))
    into resultat;
  return resultat;
end $$;

/** Les pastilles et l'alerte de l'accueil : un seul appel, à chaque relecture. */
create or replace function public.rh_controles_compteurs() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  acces text := public.rh_controles_acces();
  s jsonb;
begin
  if acces is null then
    return jsonb_build_object('acces', null);
  end if;
  s := public.rh_controles_seuils();
  return jsonb_build_object(
    'acces', acces,
    'approuver', public.rh_est_ceo() or public.est_super(),
    'reglages_a_approuver', case when acces = 'admin' then
      (select count(*) from public.rh_audit_reglages a where a.approuve_le is null) end,
    'dernier', case when acces = 'admin' then
      (select jsonb_build_object(
          'libelle', public.rh_audit_libelle(a.table_nom, a.champ, a.avant, a.apres)
                     || coalesce(' — ' || nullif(b.nom, ''), ''),
          'le', a.le, 'par', a.par_nom, 'critique', a.critique)
         from public.rh_audit_reglages a
         left join public.boutiques b on a.table_nom = 'boutiques_reception' and b.id = a.cible
        where a.approuve_le is null
        order by a.critique desc, a.le desc, a.id desc limit 1) end,
    -- Les « anciens » : la même règle que rh_encaissements, livrés sans
    -- déclaration compris (toujours anciens, sur 60 jours). Sans eux, un
    -- livreur s'affichait « Plafond atteint » pendant que la pastille et
    -- l'accueil disaient 0.
    'encaissements_anciens', (select count(*) from public.encaissements x
       where x.remis_le is null and x.montant > 0
         and now() - x.encaisse_le > make_interval(hours => case when x.mode = 'mobile_money'
                                                                 then (s ->> 'momopay_h')::int
                                                                 else (s ->> 'especes_h')::int end))
      + (select count(*) from (select distinct l.commande_id, l.boutique_id
                                 from public.commande_lignes l
                                 join public.commandes c on c.id = l.commande_id and c.etat = 'payee'
                                where l.etat = 'remise' and c.paye_le >= now() - interval '60 days'
                                  and not exists (select 1 from public.encaissements x
                                                   where x.commande_id = l.commande_id
                                                     and x.boutique_id = l.boutique_id)) d
          where exists (select 1 from public.restes_par_boutique(d.commande_id) rr
                         where rr.boutique_id = d.boutique_id and rr.a_encaisser > 0)));
end $$;

revoke all on function public.rh_audit_reglages_fige() from public, anon, authenticated;
revoke all on function public.rh_audit_reglages_noter() from public, anon, authenticated;
revoke all on function public.rh_audit_qui(uuid) from public, anon, authenticated;
grant execute on function public.rh_audit_qui(uuid) to service_role;
revoke all on function public.rh_audit_critique(text, text) from public, anon;
grant execute on function public.rh_audit_critique(text, text) to authenticated, service_role;
revoke all on function public.rh_audit_affiche(text, text, text) from public, anon;
grant execute on function public.rh_audit_affiche(text, text, text) to authenticated, service_role;
revoke all on function public.rh_audit_libelle(text, text, text, text) from public, anon;
grant execute on function public.rh_audit_libelle(text, text, text, text) to authenticated, service_role;
revoke all on function public.rh_controles_acces() from public, anon;
grant execute on function public.rh_controles_acces() to authenticated, service_role;
revoke all on function public.rh_controles_seuils() from public, anon;
grant execute on function public.rh_controles_seuils() to authenticated, service_role;
revoke all on function public.rh_audit_reglages_liste(boolean) from public, anon;
grant execute on function public.rh_audit_reglages_liste(boolean) to authenticated, service_role;
revoke all on function public.rh_audit_approuver(bigint[]) from public, anon;
grant execute on function public.rh_audit_approuver(bigint[]) to authenticated, service_role;
revoke all on function public.rh_controles_regler(int, int, int) from public, anon;
grant execute on function public.rh_controles_regler(int, int, int) to authenticated, service_role;
revoke all on function public.rh_suivi_regler_veille(int, int) from public, anon;
grant execute on function public.rh_suivi_regler_veille(int, int) to authenticated, service_role;
revoke all on function public.rh_encaissements(date, date) from public, anon;
grant execute on function public.rh_encaissements(date, date) to authenticated, service_role;
revoke all on function public.rh_controles_compteurs() from public, anon;
grant execute on function public.rh_controles_compteurs() to authenticated, service_role;

-- ---------- Les menus réglables, « controles » compris (copies de schema.sql) ----------
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

-- ---------- Le suivi lève « course sans livreur », « livreur muet »,
-- ---------- « MoMoPay non vérifié » et « écart d'encaissement » (copie de schema.sql) ----------
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

-- ---------- La carte : le livreur muet (copie de schema.sql) ----------
create or replace function public.rh_localiser_livreurs() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  coef numeric := coalesce((select livraison_coef from public.paiement where id = 1), 1.3);
  seuil int;
begin
  if not public.rh_menu_ouvert('livreurs') then
    raise exception 'Votre compte n''a pas accès à la localisation des livreurs';
  end if;
  -- Le seuil du « livreur muet » vit dans les réglages du suivi : sans
  -- eux (fichier rejoué seul sur une base plus ancienne), 15 minutes.
  begin
    select (to_jsonb(r) ->> 'position_min')::int into seuil from public.rh_reglages_suivi r where r.id;
  exception when others then
    seuil := null;
  end;
  seuil := coalesce(seuil, 15);
  return jsonb_build_object(
    'coef', coef,
    'maintenant', now(),
    'seuil_muet_min', seuil,
    'livreurs', (select coalesce(jsonb_agg(x.l order by (x.l ->> 'en_course')::boolean desc, x.l ->> 'nom'), '[]')
      from (
        select jsonb_build_object(
          'id', p.id,
          'nom', coalesce(nullif(btrim(p.nom), ''), p.email, 'Livreur'),
          'tel', coalesce(p.tel, ''),
          'vehicule', coalesce(p.vehicule, 'moto'),
          'boutique', (select b.nom from public.boutiques b where b.id = p.boutique_id),
          'position', case when pl.profil_id is null then null else jsonb_build_object(
              'latitude', pl.latitude, 'longitude', pl.longitude, 'precision', pl.precision_m,
              'adresse', pl.adresse, 'le', pl.enregistre_le) end,
          'en_course', public.livreur_en_course(p.id),
          -- (3.70.0) Actif : un jeton valable ET une position de moins de
          -- 15 minutes — un téléphone éteint ne passe plus pour suivi.
          'suivi_actif', exists (select 1 from public.suivis_livreurs s
                                  where s.profil_id = p.id and s.expire_le > now())
                         and coalesce(pl.enregistre_le > now() - interval '15 minutes', false),
          -- En route vers un client, et rien reçu de son téléphone depuis
          -- le seuil (compté depuis la course acceptée s'il n'a jamais rien envoyé).
          'muet', exists (select 1 from public.commande_lignes l
                            join public.commandes c on c.id = l.commande_id
                           where l.livreur_id = p.id and c.etat = 'payee' and l.etat = 'en_livraison'
                             and now() - greatest(pl.enregistre_le, l.recu_le, c.paye_le) > make_interval(mins => seuil)),
          'courses', (select coalesce(jsonb_agg(jsonb_build_object(
              'commande', k.commande_id, 'numero', k.numero, 'client', k.client_nom,
              'adresse', k.client_adresse, 'etat', k.etat, 'boutique', k.boutique,
              'retrait', case when k.b_lat is null then null
                              else jsonb_build_object('latitude', k.b_lat, 'longitude', k.b_lng) end,
              'destination', case when k.d_lat is null then null
                                  else jsonb_build_object('latitude', k.d_lat, 'longitude', k.d_lng) end,
              'distance_km', case when k.d_lat is null or pl.profil_id is null then null else round((
                  2 * 6371 * asin(least(1, sqrt(
                    sin(radians(k.d_lat - pl.latitude) / 2) ^ 2
                    + cos(radians(pl.latitude)) * cos(radians(k.d_lat))
                      * sin(radians(k.d_lng - pl.longitude) / 2) ^ 2))) * coef)::numeric, 1) end)
              order by k.numero), '[]')
            from (
              select c.id as commande_id, c.numero, c.client_nom, c.client_adresse,
                     (array['nouvelle', 'vue', 'preparee', 'en_livraison'])[
                       min(array_position(array['nouvelle', 'vue', 'preparee', 'en_livraison'], l.etat))] as etat,
                     max(b.nom) as boutique, max(b.latitude) as b_lat, max(b.longitude) as b_lng,
                     public.coord_valable((c.livraison #>> '{destination,latitude}')::double precision, 90) as d_lat,
                     public.coord_valable((c.livraison #>> '{destination,longitude}')::double precision, 180) as d_lng
                from public.commande_lignes l
                join public.commandes c on c.id = l.commande_id
                left join public.boutiques b on b.id = l.boutique_id
               where l.livreur_id = p.id and c.etat = 'payee'
                 and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')
               group by c.id, c.numero, c.client_nom, c.client_adresse, c.livraison) k)
        ) as l
          from public.profils p
          left join public.positions_livreurs pl on pl.profil_id = p.id
         where p.role = 'livreur' and p.actif
      ) x));
end $$;

revoke all on function public.rh_regler_acces(uuid, jsonb) from public, anon;
grant execute on function public.rh_regler_acces(uuid, jsonb) to authenticated, service_role;
revoke all on function public.rh_mes_menus() from public, anon;
grant execute on function public.rh_mes_menus() to authenticated, service_role;
revoke all on function public.rh_suivi_donnees(timestamptz, timestamptz, text) from public, anon, authenticated;
revoke all on function public.rh_localiser_livreurs() from public, anon;
grant execute on function public.rh_localiser_livreurs() to authenticated, service_role;
