-- =========================================================
-- BIZZOO Personnel : l'argent sous contrôle
--
-- Le menu Contrôles gagne cinq onglets :
-- 1. PAIEMENTS À RAPPROCHER : les clients peut-être débités dont la
--    commande ne le dit pas (l'agrégateur a dit « payé », versement en
--    conflit, incomplet ou inconnu, « j'ai payé » resté sans preuve), et
--    les paiements confirmés à la main. On y note qui a traité le dossier,
--    quand et comment. La confirmation du paiement reste dans BIZZOO Admin.
-- 2. À PAYER : ce que BIZZOO doit aux boutiques (reversements), aux
--    livreurs (gains) et aux parrains (retraits), demandes en attente avec
--    leur ancienneté, le réel à côté du théorique. On décide dans Admin.
-- 3. REMBOURSEMENTS : quand un article ou une commande déjà payés sont
--    annulés, le client à rembourser entre seul dans la file ; on y note
--    le remboursement fait (mode, référence) ; une alerte se lève s'il
--    tarde. Et les boutiques qui annulent après paiement.
-- 4. GESTES ADMIN : le journal de BIZZOO Admin, gestes sensibles en avant,
--    pour le CEO, le superadministrateur et la clé « audit ».
-- 5. CODES PROMO : usages, coût et rapport de chaque code, commissions et
--    retraits des parrains, abus probables ; numéros masqués aux 4
--    derniers chiffres.
--
-- Montants : l'administration et le superadministrateur seulement. Trois
-- clés nouvelles dans Paramètres ouvrent des versions sans montants :
-- « paiements » (paiements et remboursements), « promos » (codes), et
-- « audit » (le journal des gestes). La clé « caisse » ouvre « À payer »
-- en nombres et en ancienneté.
-- =========================================================
--
-- À coller tel quel dans l'éditeur SQL ; il se rejoue sans dommage.
-- =========================================================

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

create or replace function public.rh_audit_qui(compte uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select nullif(btrim(coalesce(e.prenoms, '') || ' ' || coalesce(e.nom, '')), '')
       from public.rh_employes e where e.compte_id = compte
      order by (e.etat = 'actif') desc limit 1),
    (select coalesce(nullif(btrim(p.nom), ''), p.email) from public.profils p where p.id = compte),
    'Compte ' || left(compte::text, 8));
$$;

-- (fin des aides)

-- Les seuils de l'argent, avec ceux du suivi et des contrôles :
--   annonce_min     : un client a dit « j'ai payé » et la commande reste
--                     « à payer » depuis plus de N minutes ;
--   dette_j         : une demande de reversement, de gains ou de retrait
--                     attend depuis plus de N jours ;
--   remboursement_j : un remboursement dû n'est pas noté après N jours.
alter table public.rh_reglages_suivi add column if not exists annonce_min int not null default 30
  check (annonce_min between 5 and 1440);
alter table public.rh_reglages_suivi add column if not exists dette_j int not null default 5
  check (dette_j between 1 and 60);
alter table public.rh_reglages_suivi add column if not exists remboursement_j int not null default 7
  check (remboursement_j between 1 and 60);

-- ---------- Ce qui a été fait d'un paiement à rapprocher ----------
-- Une ligne par geste (« client rappelé », « paiement retrouvé chez
-- FeexPay »…), jamais réécrite : la dernière dit où en est le dossier.
-- Pas de clé étrangère vers « commandes », comme « versements » : la
-- trace survit à la commande. La confirmation du paiement, elle, reste
-- dans BIZZOO Admin : ici, on note seulement qui a traité, et comment.
create table if not exists public.rh_rapprochements (
  id          bigint generated always as identity primary key,
  commande_id text not null,
  statut      text not null check (statut in ('en_cours', 'regle', 'sans_suite')),
  commentaire text not null default '',
  par         uuid,
  par_nom     text not null default '',
  le          timestamptz not null default now()
);
create index if not exists rh_rapprochements_commande on public.rh_rapprochements (commande_id, le desc);
alter table public.rh_rapprochements enable row level security;
revoke all on table public.rh_rapprochements from public, anon, authenticated;
revoke all on sequence public.rh_rapprochements_id_seq from public, anon, authenticated;
grant all on table public.rh_rapprochements to service_role;
grant usage, select on sequence public.rh_rapprochements_id_seq to service_role;

-- ---------- Qui a annulé, et quand ----------
-- « commande_lignes » ne dit pas qui a annulé un article, et sa lecture
-- est restreinte par colonne : on n'y ajoute rien. Cette table à part se
-- remplit par déclencheur, à chaque annulation d'un article ou d'une
-- commande entière, avec le compte qui l'a faite. Elle ne connaît que
-- les annulations faites après son installation.
create table if not exists public.rh_annulations (
  id             bigint generated always as identity primary key,
  commande_id    text not null,
  ligne_id       text,
  boutique_id    text,
  apres_paiement boolean not null default false,
  par_compte     uuid,
  par_nom        text not null default '',
  le             timestamptz not null default now()
);
create index if not exists rh_annulations_commande on public.rh_annulations (commande_id, le desc);
alter table public.rh_annulations enable row level security;
revoke all on table public.rh_annulations from public, anon, authenticated;
revoke all on sequence public.rh_annulations_id_seq from public, anon, authenticated;
grant all on table public.rh_annulations to service_role;
grant usage, select on sequence public.rh_annulations_id_seq to service_role;

-- ---------- Les remboursements faits ----------
-- Une ligne par remboursement (on peut rendre en deux fois). Le montant
-- dû n'est pas écrit ici : la base le recalcule (rh_rembourse_du), pour
-- qu'un article annulé demain change ce qui reste à rendre.
create table if not exists public.rh_remboursements (
  id          bigint generated always as identity primary key,
  commande_id text not null,
  montant     bigint not null check (montant > 0),
  mode        text not null check (mode in ('mobile_money', 'especes', 'virement', 'autre')),
  reference   text not null default '',
  note        text not null default '',
  par         uuid,
  par_nom     text not null default '',
  le          timestamptz not null default now()
);
create index if not exists rh_remboursements_commande on public.rh_remboursements (commande_id);
alter table public.rh_remboursements enable row level security;
revoke all on table public.rh_remboursements from public, anon, authenticated;
revoke all on sequence public.rh_remboursements_id_seq from public, anon, authenticated;
grant all on table public.rh_remboursements to service_role;
grant usage, select on sequence public.rh_remboursements_id_seq to service_role;

/* JAMAIS D'ERREUR VERS ADMIN NI CLIENT : ce déclencheur vit sur
   « commandes » et « commande_lignes ». Tout est dans un bloc qui avale
   ses propres échecs : une annulation manquée au journal se regrette,
   une annulation refusée à cause de lui, jamais. */
create or replace function public.rh_annulation_noter() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_qui uuid;
  v_nom text;
  v_paye timestamptz;
begin
  begin
    if new.etat = 'annulee' and old.etat is distinct from 'annulee' then
      v_qui := auth.uid();
      v_nom := case when v_qui is null then 'Système (aucun compte connecté)' else public.rh_audit_qui(v_qui) end;
      if tg_table_name = 'commande_lignes' then
        select c.paye_le into v_paye from public.commandes c where c.id = new.commande_id;
        insert into public.rh_annulations (commande_id, ligne_id, boutique_id, apres_paiement, par_compte, par_nom)
        values (new.commande_id, new.id, new.boutique_id, v_paye is not null, v_qui, coalesce(v_nom, ''));
      else
        insert into public.rh_annulations (commande_id, apres_paiement, par_compte, par_nom)
        values (new.id, new.paye_le is not null or old.etat = 'payee', v_qui, coalesce(v_nom, ''));
      end if;
    end if;
  exception when others then
    raise warning 'rh_annulation_noter : % (%)', sqlerrm, sqlstate;
  end;
  return null;
end $$;

drop trigger if exists rh_annulations_lignes on public.commande_lignes;
create trigger rh_annulations_lignes
  after update of etat on public.commande_lignes
  for each row execute function public.rh_annulation_noter();
drop trigger if exists rh_annulations_commandes on public.commandes;
create trigger rh_annulations_commandes
  after update of etat on public.commandes
  for each row execute function public.rh_annulation_noter();

/** Les seuils de l'argent, valeurs de départ comprises. */
create or replace function public.rh_argent_seuils() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'annonce_min', coalesce((x.j ->> 'annonce_min')::int, 30),
    'dette_j', coalesce((x.j ->> 'dette_j')::int, 5),
    'remboursement_j', coalesce((x.j ->> 'remboursement_j')::int, 7))
    from (select coalesce((select to_jsonb(r) from public.rh_reglages_suivi r where r.id), '{}'::jsonb) as j) x;
$$;

/** Un numéro réduit à ses 4 derniers chiffres : de quoi reconnaître un
    client au téléphone, pas de quoi l'appeler. */
create or replace function public.rh_tel_masque(t text) returns text
language sql immutable set search_path = public as $$
  select case when length(regexp_replace(coalesce(t, ''), '\D', '', 'g')) < 4 then ''
              else '•••• ' || right(regexp_replace(t, '\D', '', 'g'), 4) end;
$$;

/**
 * Ce que chaque onglet d'argent ouvre au compte connecté : « admin »
 * (montants compris : l'administration, le CEO, le superadministrateur),
 * « equipe » (sans aucun montant, par une clé de Paramètres), ou rien.
 *   paiements, remboursements : la clé « paiements » (relation client, SAV) ;
 *   dettes : la clé « caisse » (consultation) ;
 *   codes  : la clé « promos » (marketing) ;
 *   gestes : le CEO, le superadministrateur et les profils à qui
 *            Paramètres ouvre EXPRESSÉMENT « audit » — l'administration
 *            n'y entre pas d'office : c'est elle que ce journal regarde.
 */
create or replace function public.rh_argent_acces() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  admin boolean := public.rh_est_admin() or public.est_super();
  v_moi uuid := public.rh_moi();
  v_profil uuid := public.rh_mon_profil();
  audit boolean := false;
begin
  if v_moi is not null and to_regclass('public.rh_acces_menus') is not null then
    select exists (select 1 from public.rh_acces_menus a
                     join public.rh_profils p on p.id = a.profil_id
                    where a.menu = 'audit'
                      and (p.responsable_id = v_moi or (a.qui = 'membres' and p.id = v_profil)))
      into audit;
  end if;
  return jsonb_build_object(
    'paiements', case when admin then 'admin' when public.rh_menu_ouvert('paiements') then 'equipe' end,
    'remboursements', case when admin then 'admin' when public.rh_menu_ouvert('paiements') then 'equipe' end,
    'dettes', case when admin then 'admin' when public.rh_menu_ouvert('caisse') then 'equipe' end,
    'codes', case when admin then 'admin' when public.rh_menu_ouvert('promos') then 'equipe' end,
    'gestes', public.rh_est_ceo() or public.est_super() or (audit and not public.rh_est_admin()),
    'seuils', admin);
end $$;

/** Régler les seuils de l'argent : l'administration et le superadministrateur. */
create or replace function public.rh_argent_regler(v_annonce_min int, v_dette_j int, v_remboursement_j int)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.rh_est_admin() or public.est_super()) then
    raise exception 'Seuls l''administration et le superadministrateur règlent les seuils de l''argent';
  end if;
  if coalesce(v_annonce_min, 0) not between 5 and 1440 then
    raise exception 'Un paiement annoncé se signale entre 5 et 1 440 minutes';
  end if;
  if coalesce(v_dette_j, 0) not between 1 and 60 or coalesce(v_remboursement_j, 0) not between 1 and 60 then
    raise exception 'Les délais se comptent en jours, de 1 à 60';
  end if;
  update public.rh_reglages_suivi
     set annonce_min = v_annonce_min, dette_j = v_dette_j, remboursement_j = v_remboursement_j
   where id;
end $$;

/**
 * Les paiements à rapprocher : le client a peut-être payé, mais la
 * commande ne le dit pas.
 *   debite_non_paye     : l'agrégateur a dit « payé », la commande n'est pas payée ;
 *   conflit, incomplet  : le versement ne correspond pas à la commande ;
 *   annonce_sans_preuve : le téléphone a dit « j'ai payé », rien n'a suivi ;
 *   inconnu             : l'agrégateur n'a pas su répondre ;
 *   manuel              : payée parce qu'un superadministrateur s'est porté
 *                         garant (confirmée à la main dans Admin) — pour mémoire.
 * Ce qui attend s'affiche quelle que soit la période (60 jours au plus) ;
 * le reste, celui de la période. Montants, transactions et numéro entier :
 * l'administration ; l'équipe a le nom, le numéro masqué et l'ancienneté.
 * Rien ne se confirme ici : la confirmation reste dans BIZZOO Admin.
 */
create or replace function public.rh_paiements(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  acces text := public.rh_argent_acces() ->> 'paiements';
  argent boolean;
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  d1 date := coalesce(depuis, aujourdhui - 29);
  d2 date := coalesce(jusqu, aujourdhui);
  t1 timestamptz;
  t2 timestamptz;
  borne timestamptz;
  annonce int := (public.rh_argent_seuils() ->> 'annonce_min')::int;
  resultat jsonb;
begin
  if acces is null then
    raise exception 'Votre compte n''a pas accès aux paiements à rapprocher';
  end if;
  if d2 < d1 then
    raise exception 'La fin de la période précède son début';
  end if;
  if d2 - d1 > 400 then
    raise exception 'Choisissez une période d''un an au plus';
  end if;
  argent := acces = 'admin';
  t1 := d1::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (d2 + 1)::timestamp at time zone 'Africa/Porto-Novo';
  borne := least(t1, now() - interval '60 days');

  with v as (
    select x.commande_id,
           count(*) as tentatives,
           bool_or(x.verdict = 'payee') as payee_chez,
           bool_or(x.verdict = 'conflit') as conflit,
           bool_or(x.verdict = 'incomplete') as incomplete,
           bool_or(x.verdict = 'inconnue') as inconnue,
           max(x.cree_le) as dernier,
           (array_agg(x.verdict order by x.cree_le desc, x.id desc))[1] as verdict,
           (array_agg(x.fournisseur order by x.cree_le desc, x.id desc))[1] as fournisseur,
           (array_agg(x.reseau order by x.cree_le desc, x.id desc))[1] as reseau,
           (array_agg(x.detail order by x.cree_le desc, x.id desc))[1] as detail,
           max(x.attendu) as attendu,
           max(x.recu) as recu,
           string_agg(distinct nullif(x.transaction_id, ''), ', ') as transactions
      from public.versements x
     where x.commande_id is not null and x.cree_le >= borne
     group by x.commande_id
  ), k as (
    select c.id, c.numero, c.etat, c.cree_le, c.annonce_le, c.paye_le, c.total, c.confirme_par, c.remarque,
           c.client_nom, c.client_tel, v.tentatives, v.verdict, v.fournisseur, v.reseau, v.detail,
           v.attendu, v.recu, v.transactions, v.dernier,
           -- paye_le reste posé quand une commande payée est annulée : sans lui,
           -- chaque annulation après paiement (son versement dit « payée »)
           -- reviendrait ici en « client débité », alors qu'elle est déjà
           -- dans les remboursements. Et « inconnu » ne regarde que la
           -- DERNIÈRE réponse : un refus venu ensuite tranche la question.
           case
             when c.paye_le is null and c.etat <> 'payee' and coalesce(v.payee_chez, false) then 'debite_non_paye'
             when c.paye_le is null and c.etat <> 'payee' and coalesce(v.conflit, false) then 'conflit'
             when c.paye_le is null and c.etat <> 'payee' and coalesce(v.incomplete, false) then 'incomplet'
             when c.etat = 'a_payer' and c.annonce_le is not null
                  and c.annonce_le < now() - make_interval(mins => annonce) then 'annonce_sans_preuve'
             when c.paye_le is null and c.etat <> 'payee' and v.verdict = 'inconnue' then 'inconnu'
             when c.etat = 'payee' and c.confirme_par <> '' then 'manuel'
           end as motif
      from public.commandes c
      left join v on v.commande_id = c.id
     where c.cree_le >= borne and c.cree_le < t2
       and (v.commande_id is not null or c.annonce_le is not null or c.confirme_par <> '')
  ), f as (
    select k.*, n.statut as note_statut, n.commentaire as note, n.par_nom as note_par, n.le as note_le,
           (k.motif <> 'manuel' and coalesce(n.statut, '') not in ('regle', 'sans_suite')) as a_traiter,
           greatest(0, floor(extract(epoch from (now() - coalesce(k.annonce_le, k.dernier, k.cree_le))) / 3600))::int as heures
      from k
      left join lateral (select r.statut, r.commentaire, r.par_nom, r.le from public.rh_rapprochements r
                          where r.commande_id = k.id order by r.le desc, r.id desc limit 1) n on true
     where k.motif is not null
  ), g as (
    -- Ce qui attend, quelle que soit sa date ; le reste, s'il touche la période.
    select * from f
     where f.a_traiter or f.cree_le >= t1 or (f.paye_le >= t1 and f.paye_le < t2)
  )
  select jsonb_build_object(
    'periode', jsonb_build_object('depuis', d1, 'jusqu', d2),
    'montants', argent,
    'seuils', public.rh_argent_seuils(),
    'totaux', (select jsonb_build_object(
        'a_traiter', count(*) filter (where g.a_traiter),
        'debite_non_paye', count(*) filter (where g.motif = 'debite_non_paye'),
        'conflit', count(*) filter (where g.motif = 'conflit'),
        'incomplet', count(*) filter (where g.motif = 'incomplet'),
        'annonce_sans_preuve', count(*) filter (where g.motif = 'annonce_sans_preuve'),
        'inconnu', count(*) filter (where g.motif = 'inconnu'),
        'manuel', count(*) filter (where g.motif = 'manuel'),
        'plus_ancien', min(coalesce(g.annonce_le, g.dernier, g.cree_le)) filter (where g.a_traiter))
      || case when argent then jsonb_build_object(
        'montant_a_traiter', coalesce(sum(g.total) filter (where g.a_traiter), 0),
        'montant_manuel', coalesce(sum(g.total) filter (where g.motif = 'manuel'), 0))
        else '{}'::jsonb end
      from g),
    'lignes', (select coalesce(jsonb_agg(jsonb_build_object(
        'commande', x.id, 'numero', x.numero, 'motif', x.motif, 'etat', x.etat,
        'cree_le', x.cree_le, 'annonce_le', x.annonce_le, 'paye_le', x.paye_le, 'heures', x.heures,
        'a_traiter', x.a_traiter, 'client', nullif(btrim(x.client_nom), ''),
        'tel', case when argent then x.client_tel else public.rh_tel_masque(x.client_tel) end,
        'fournisseur', nullif(x.fournisseur, ''), 'reseau', nullif(x.reseau, ''),
        'verdict', x.verdict, 'tentatives', coalesce(x.tentatives, 0),
        'confirme_par', nullif(x.confirme_par, ''),
        'traitement', case when x.note_statut is null then null
                           else jsonb_build_object('statut', x.note_statut, 'commentaire', x.note,
                                                   'par', x.note_par, 'le', x.note_le) end)
        || case when argent then jsonb_build_object(
             'total', x.total, 'attendu', x.attendu, 'recu', x.recu,
             'transactions', x.transactions, 'remarque', nullif(x.remarque, ''), 'detail', nullif(x.detail, ''))
           else '{}'::jsonb end
        order by x.a_traiter desc, x.heures desc), '[]')
      from (select * from g order by g.a_traiter desc, g.heures desc limit 500) x))
    into resultat;
  return resultat;
end $$;

/** Noter ce qui a été fait d'un paiement à rapprocher : qui, quand, comment. */
create or replace function public.rh_rapprocher(cible text, v_statut text, v_commentaire text)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  n bigint;
  texte text := btrim(coalesce(v_commentaire, ''));
begin
  if public.rh_argent_acces() ->> 'paiements' is null then
    raise exception 'Votre compte n''a pas accès aux paiements à rapprocher';
  end if;
  if not exists (select 1 from public.commandes c where c.id = cible) then
    raise exception 'Commande introuvable';
  end if;
  if coalesce(v_statut, '') not in ('en_cours', 'regle', 'sans_suite') then
    raise exception 'Choisissez où en est ce paiement : en cours, réglé ou sans suite';
  end if;
  if length(texte) < 3 then
    raise exception 'Dites en quelques mots ce qui a été fait (client rappelé, paiement retrouvé…)';
  end if;
  insert into public.rh_rapprochements (commande_id, statut, commentaire, par, par_nom)
  values (cible, v_statut, left(texte, 500), public.rh_moi(), coalesce(public.rh_audit_qui(auth.uid()), ''))
  returning id into n;
  return n;
end $$;

/**
 * Ce que BIZZOO doit rendre au client d'une commande payée : ce qu'il a
 * versé en ligne, moins ce que vaut ce qui sera encore servi (remise au
 * prorata, frais tant qu'il reste quelque chose à livrer). Toute la
 * somme si la commande entière est annulée. Zéro si rien n'est annulé.
 * Interne : les montants n'en sortent que par les écrans de
 * l'administration.
 */
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

/**
 * Les remboursements dus après une annulation : la file se remplit seule
 * (une commande payée dont un article, ou le tout, est annulé et pour
 * laquelle le client a versé plus que ce qui sera servi). « En retard »
 * au-delà du seuil (jours). Et, sur la période, les boutiques qui annulent
 * après paiement. Montants, modes et références : l'administration ;
 * l'équipe voit les dossiers, leur ancienneté et s'ils sont traités.
 */
create or replace function public.rh_remboursements_liste(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  acces text := public.rh_argent_acces() ->> 'remboursements';
  argent boolean;
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  d1 date := coalesce(depuis, aujourdhui - 29);
  d2 date := coalesce(jusqu, aujourdhui);
  t1 timestamptz;
  t2 timestamptz;
  retard interval := make_interval(days => (public.rh_argent_seuils() ->> 'remboursement_j')::int);
  resultat jsonb;
begin
  if acces is null then
    raise exception 'Votre compte n''a pas accès aux remboursements';
  end if;
  if d2 < d1 then
    raise exception 'La fin de la période précède son début';
  end if;
  if d2 - d1 > 400 then
    raise exception 'Choisissez une période d''un an au plus';
  end if;
  argent := acces = 'admin';
  t1 := d1::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (d2 + 1)::timestamp at time zone 'Africa/Porto-Novo';

  with c as (
    select k.id, k.numero, k.etat, k.paye_le, k.client_nom, k.client_tel,
           public.rh_rembourse_du(k.id) as du,
           -- Quand l'annulation a eu lieu : notre journal, sinon celui des
           -- étapes du suivi ; à défaut (annulation plus ancienne que les
           -- deux), le paiement.
           coalesce((select max(a.le) from public.rh_annulations a where a.commande_id = k.id),
                    (select max(j.le) from public.rh_journal_lignes j
                      where j.commande_id = k.id and j.valeur = 'annulee' and j.quoi in ('etat', 'commande'))) as annule_le,
           (select a.par_nom from public.rh_annulations a where a.commande_id = k.id
             order by a.le desc, a.id desc limit 1) as annule_par,
           (select string_agg(distinct coalesce(b.nom, l.boutique_id), ', ')
              from public.commande_lignes l left join public.boutiques b on b.id = l.boutique_id
             where l.commande_id = k.id and l.etat = 'annulee') as boutiques
      from public.commandes k
     where k.paye_le is not null and k.paye_le >= least(t1, now() - interval '365 days')
       and (k.etat = 'annulee'
            or exists (select 1 from public.commande_lignes l where l.commande_id = k.id and l.etat = 'annulee'))
  ), r as (
    select c.*,
           coalesce((select sum(m.montant) from public.rh_remboursements m where m.commande_id = c.id), 0) as rendu,
           (select max(m.le) from public.rh_remboursements m where m.commande_id = c.id) as rendu_le
      from c
  ), f as (
    select r.*, greatest(0, r.du - r.rendu) as reste,
           case when r.du - r.rendu > 0 and r.rendu = 0 then 'a_rembourser'
                when r.du - r.rendu > 0 then 'partiel'
                else 'rembourse' end as statut,
           greatest(0, floor(extract(epoch from (now() - coalesce(r.annule_le, r.paye_le))) / 86400))::int as jours
      from r
     where r.du > 0 or r.rendu > 0
  ), g as (
    select f.*, (f.reste > 0 and now() - coalesce(f.annule_le, f.paye_le) > retard) as en_retard
      from f
     where f.reste > 0 or (f.rendu_le >= t1 and f.rendu_le < t2)
  ), stats as (
    -- Les boutiques qui annulent APRÈS le paiement, sur la période : le
    -- journal des étapes, qui remonte plus loin que le nôtre.
    select j.boutique_id, count(distinct j.ligne_id) as lignes, count(distinct j.commande_id) as commandes,
           coalesce(sum(l.prix::bigint * l.quantite), 0) as valeur
      from public.rh_journal_lignes j
      join public.commandes k on k.id = j.commande_id and k.paye_le is not null and j.le >= k.paye_le
      left join public.commande_lignes l on l.id = j.ligne_id
     where j.quoi = 'etat' and j.valeur = 'annulee' and j.le >= t1 and j.le < t2
     group by j.boutique_id
  )
  select jsonb_build_object(
    'periode', jsonb_build_object('depuis', d1, 'jusqu', d2),
    'montants', argent,
    'seuils', public.rh_argent_seuils(),
    'totaux', (select jsonb_build_object(
        'a_rembourser', count(*) filter (where g.reste > 0),
        'en_retard', count(*) filter (where g.en_retard),
        'rembourses', count(*) filter (where g.reste = 0),
        'plus_ancien', min(coalesce(g.annule_le, g.paye_le)) filter (where g.reste > 0))
      || case when argent then jsonb_build_object(
        'reste_total', coalesce(sum(g.reste), 0),
        'rendu_periode', coalesce((select sum(m.montant) from public.rh_remboursements m
                                    where m.le >= t1 and m.le < t2), 0))
        else '{}'::jsonb end
      from g),
    'lignes', (select coalesce(jsonb_agg(jsonb_build_object(
        'commande', x.id, 'numero', x.numero, 'etat', x.etat, 'paye_le', x.paye_le,
        'annule_le', x.annule_le, 'annule_par', x.annule_par, 'boutiques', x.boutiques,
        'jours', x.jours, 'en_retard', x.en_retard, 'statut', x.statut,
        'client', nullif(btrim(x.client_nom), ''),
        'tel', case when argent then x.client_tel else public.rh_tel_masque(x.client_tel) end,
        'faits', (select coalesce(jsonb_agg(jsonb_build_object('le', m.le, 'mode', m.mode, 'par', m.par_nom)
                    || case when argent then jsonb_build_object('montant', m.montant, 'reference', nullif(m.reference, ''),
                                                                'note', nullif(m.note, '')) else '{}'::jsonb end
                    order by m.le), '[]')
                    from public.rh_remboursements m where m.commande_id = x.id))
        || case when argent then jsonb_build_object('du', x.du, 'rendu', x.rendu, 'reste', x.reste) else '{}'::jsonb end
        order by x.en_retard desc, (x.reste > 0) desc, x.jours desc), '[]')
      from (select * from g order by g.en_retard desc, (g.reste > 0) desc, g.jours desc limit 500) x),
    'boutiques', (select coalesce(jsonb_agg(jsonb_build_object(
        'boutique', coalesce(b.nom, s.boutique_id, 'Boutique inconnue'), 'lignes', s.lignes, 'commandes', s.commandes)
        || case when argent then jsonb_build_object('valeur', s.valeur) else '{}'::jsonb end
        order by s.lignes desc, s.commandes desc), '[]')
      from stats s left join public.boutiques b on b.id = s.boutique_id))
    into resultat;
  return resultat;
end $$;

/** Noter un remboursement fait : l'administration et le superadministrateur, jamais plus que ce qui reste dû. */
create or replace function public.rh_rembourser(cible text, v_montant bigint, v_mode text,
                                                v_reference text default '', v_note text default '')
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  du bigint;
  rendu bigint;
  ref text := btrim(coalesce(v_reference, ''));
  n bigint;
begin
  if not (public.rh_est_admin() or public.est_super()) then
    raise exception 'Seuls l''administration et le superadministrateur notent un remboursement';
  end if;
  if not exists (select 1 from public.commandes c where c.id = cible) then
    raise exception 'Commande introuvable';
  end if;
  if coalesce(v_mode, '') not in ('mobile_money', 'especes', 'virement', 'autre') then
    raise exception 'Choisissez comment le client a été remboursé';
  end if;
  if v_mode in ('mobile_money', 'virement') and length(ref) < 4 then
    raise exception 'Notez la référence de la transaction : c''est elle qui prouve le remboursement';
  end if;
  if coalesce(v_montant, 0) <= 0 then
    raise exception 'Le montant remboursé doit être positif';
  end if;
  -- Deux remboursements notés en même temps ne dépassent pas le dû.
  perform pg_advisory_xact_lock(hashtext('rh_rembourser:' || cible));
  du := public.rh_rembourse_du(cible);
  select coalesce(sum(m.montant), 0) into rendu from public.rh_remboursements m where m.commande_id = cible;
  if du - rendu <= 0 then
    raise exception 'Rien n''est dû au client sur cette commande';
  end if;
  if v_montant > du - rendu then
    raise exception 'Il ne reste que % FCFA à rendre sur cette commande', du - rendu;
  end if;
  insert into public.rh_remboursements (commande_id, montant, mode, reference, note, par, par_nom)
  values (cible, v_montant, v_mode, left(ref, 80), left(btrim(coalesce(v_note, '')), 300),
          public.rh_moi(), coalesce(public.rh_audit_qui(auth.uid()), ''))
  returning id into n;
  return n;
end $$;

/**
 * Ce que BIZZOO doit payer, aujourd'hui : les demandes de reversement des
 * boutiques, de gains des livreurs et de retrait des parrains qui
 * attendent (avec leur ancienneté), et ce qui est dû sans avoir encore été
 * demandé. À côté, le « théorique » de la période (ce que les boutiques
 * ont vendu au prix BIZZOO) et ce qui a vraiment été versé. Rien ne se
 * décide ici : on valide un reversement dans BIZZOO Admin.
 * Montants : l'administration ; la clé « caisse » donne les nombres et
 * l'ancienneté.
 */
create or replace function public.part_frais_livreur(cible text, qui uuid) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare
  c          public.commandes%rowtype;
  f          numeric;
  siennes    int;
  confiees   int;
  part       numeric;
  brut_moi   numeric;
  brut_tout  numeric;
begin
  select * into c from public.commandes where id = cible;
  if not found then return 0; end if;
  f := greatest(0, coalesce(c.frais_livraison, 0));
  if f <= 0 then return 0; end if;
  select count(*) filter (where l.livreur_id = qui), count(*) filter (where l.livreur_id is not null)
    into siennes, confiees
    from public.commande_lignes l where l.commande_id = cible and l.etat <> 'annulee';
  if coalesce(siennes, 0) = 0 then
    return case when coalesce(confiees, 0) = 0 then f else 0 end;
  end if;
  if c.livraison is not null then return f; end if;
  if c.parts is not null and exists (select 1 from jsonb_each(c.parts) e(k, v)
                                      where coalesce((v ->> 'frais')::numeric, 0) > 0) then
    select coalesce(sum(coalesce((c.parts -> b.bou ->> 'frais')::numeric, 0)), 0) into part
      from (select distinct l.boutique_id as bou from public.commande_lignes l
             where l.commande_id = cible and l.livreur_id = qui and l.etat <> 'annulee') b;
    return least(f, part);
  end if;
  select coalesce(sum(l.prix * l.quantite) filter (where l.livreur_id = qui), 0),
         coalesce(sum(l.prix * l.quantite), 0)
    into brut_moi, brut_tout
    from public.commande_lignes l where l.commande_id = cible and l.etat <> 'annulee';
  if brut_tout <= 0 then return 0; end if;
  return round(f * brut_moi / brut_tout);
end $$;
revoke all on function public.part_frais_livreur(text, uuid) from public, anon, authenticated;

create or replace function public.rh_dettes(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  acces text := public.rh_argent_acces() ->> 'dettes';
  argent boolean;
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  d1 date := coalesce(depuis, aujourdhui - 29);
  d2 date := coalesce(jusqu, aujourdhui);
  t1 timestamptz;
  t2 timestamptz;
  seuil interval := make_interval(days => (public.rh_argent_seuils() ->> 'dette_j')::int);
  resultat jsonb;
begin
  if acces is null then
    raise exception 'Votre compte n''a pas accès à ce que BIZZOO doit payer';
  end if;
  if d2 < d1 then
    raise exception 'La fin de la période précède son début';
  end if;
  if d2 - d1 > 400 then
    raise exception 'Choisissez une période d''un an au plus';
  end if;
  argent := acces = 'admin';
  t1 := d1::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (d2 + 1)::timestamp at time zone 'Africa/Porto-Novo';

  with gb as (
    -- La même règle que solde_boutique : gagné à la livraison, moins les
    -- espèces que la boutique a déjà touchées, moins ses reversements.
    select l.boutique_id as id,
           coalesce(sum(l.prix_bizzoo::bigint * l.quantite) filter (where l.etat = 'remise'), 0) as gagne,
           coalesce(sum(l.prix_bizzoo::bigint * l.quantite)
                      filter (where l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')), 0) as a_venir
      from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id and c.etat = 'payee'
     where l.boutique_id is not null
     group by l.boutique_id
  ), eb as (
    select x.boutique_id as id, coalesce(sum(x.montant), 0) as encaisse
      from public.encaissements x where x.mode = 'especes' and x.remis_le is not null
     group by x.boutique_id
  ), rb as (
    select v.boutique_id as id,
           coalesce(sum(v.montant) filter (where v.etat = 'valide'), 0) as verse,
           coalesce(sum(v.montant) filter (where v.etat = 'en_attente'), 0) as attente,
           count(*) filter (where v.etat = 'en_attente') as demandes,
           count(*) filter (where v.etat = 'en_attente' and v.demande_le < now() - seuil) as anciennes,
           min(v.demande_le) filter (where v.etat = 'en_attente') as plus_ancienne
      from public.reversements v group by v.boutique_id
  ), bou as (
    select 'boutique'::text as type, b.id::text as id, b.nom as nom,
           coalesce(rb.attente, 0) as attente,
           greatest(0, coalesce(gb.gagne, 0) - coalesce(eb.encaisse, 0) - coalesce(rb.verse, 0) - coalesce(rb.attente, 0)) as disponible,
           coalesce(gb.a_venir, 0) as a_venir,
           coalesce(rb.demandes, 0) as demandes, coalesce(rb.anciennes, 0) as anciennes, rb.plus_ancienne
      from public.boutiques b
      left join gb on gb.id = b.id
      left join eb on eb.id = b.id
      left join rb on rb.id = b.id
  ), rl as (
    select v.livreur_id as id,
           coalesce(sum(v.montant) filter (where v.etat = 'valide'), 0) as verse,
           coalesce(sum(v.montant) filter (where v.etat = 'en_attente'), 0) as attente,
           count(*) filter (where v.etat = 'en_attente') as demandes,
           count(*) filter (where v.etat = 'en_attente' and v.demande_le < now() - seuil) as anciennes,
           min(v.demande_le) filter (where v.etat = 'en_attente') as plus_ancienne
      from public.reversements_livreurs v where v.livreur_id is not null group by v.livreur_id
  ), avl as (
    -- La même règle que solde_livreur : sa part des frais (au taux du jour)
    -- des courses payées qu'il a en main et pas encore livrées.
    select x.livreur_id as id,
           coalesce(sum(floor(public.part_frais_livreur(x.commande_id, x.livreur_id)
                              * coalesce((select p.taux_livreur from public.paiement p where p.id = 1), 80) / 100.0)), 0)::bigint as a_venir
      from (select distinct c.id as commande_id, l.livreur_id
              from public.commandes c
              join public.commande_lignes l on l.commande_id = c.id
             where c.etat = 'payee' and coalesce(c.frais_livraison, 0) > 0
               and l.livreur_id is not null and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')
               and not exists (select 1 from public.gains_livreurs g
                                where g.commande_id = c.id and g.livreur_id = l.livreur_id)) x
     group by x.livreur_id
  ), liv as (
    select 'livreur'::text as type, q.id::text as id,
           coalesce(nullif(btrim(p.nom), ''), p.email, 'Livreur') as nom,
           coalesce(rl.attente, 0) as attente,
           greatest(0, coalesce((select sum(g.montant) from public.gains_livreurs g where g.livreur_id = q.id), 0)
                       - coalesce(rl.verse, 0) - coalesce(rl.attente, 0)) as disponible,
           coalesce(avl.a_venir, 0) as a_venir,
           coalesce(rl.demandes, 0) as demandes, coalesce(rl.anciennes, 0) as anciennes, rl.plus_ancienne
      from (select g.livreur_id as id from public.gains_livreurs g where g.livreur_id is not null
            union select rl.id from rl union select avl.id from avl) q
      left join rl on rl.id = q.id
      left join avl on avl.id = q.id
      left join public.profils p on p.id = q.id
  ), rp as (
    select v.parrain as id,
           coalesce(sum(v.montant) filter (where v.etat = 'payee'), 0) as verse,
           coalesce(sum(v.montant) filter (where v.etat = 'demande'), 0) as attente,
           count(*) filter (where v.etat = 'demande') as demandes,
           count(*) filter (where v.etat = 'demande' and v.demande_le < now() - seuil) as anciennes,
           min(v.demande_le) filter (where v.etat = 'demande') as plus_ancienne
      from public.retraits_parrain v group by v.parrain
  ), par as (
    -- Un parrain est un client : son nom ne sort que pour l'administration ;
    -- l'équipe le reconnaît à son code.
    select 'parrain'::text as type, q.id::text as id,
           coalesce((select string_agg(k.code, ', ' order by k.code) from public.codes_promo k where k.parrain = q.id), '')
             || case when argent then coalesce(' — ' || nullif(btrim(coalesce((select cl.nom from public.clients cl where cl.id = q.id),
                                                                             (select pf.nom from public.profils pf where pf.id = q.id), '')), ''), '')
                     else '' end as nom,
           coalesce(rp.attente, 0) as attente,
           greatest(0, coalesce((select sum(g.montant) from public.gains_parrain g where g.parrain = q.id), 0)
                       - coalesce(rp.verse, 0) - coalesce(rp.attente, 0)) as disponible,
           0::bigint as a_venir,
           coalesce(rp.demandes, 0) as demandes, coalesce(rp.anciennes, 0) as anciennes, rp.plus_ancienne
      from (select g.parrain as id from public.gains_parrain g union select rp.id from rp) q
      left join rp on rp.id = q.id
  ), tout as (
    select * from bou union all select * from liv union all select * from par
  ), d as (
    select 'boutique'::text as type, coalesce(b.nom, v.boutique_id) as nom, v.montant, v.demande_le
      from public.reversements v left join public.boutiques b on b.id = v.boutique_id
     where v.etat = 'en_attente'
    union all
    select 'livreur', coalesce(nullif(btrim(p.nom), ''), nullif(v.nom_livreur, ''), p.email, 'Livreur'), v.montant, v.demande_le
      from public.reversements_livreurs v left join public.profils p on p.id = v.livreur_id
     where v.etat = 'en_attente'
    union all
    select 'parrain', coalesce((select string_agg(k.code, ', ' order by k.code) from public.codes_promo k where k.parrain = v.parrain), 'Parrain'),
           v.montant, v.demande_le
      from public.retraits_parrain v where v.etat = 'demande'
  )
  select jsonb_build_object(
    'periode', jsonb_build_object('depuis', d1, 'jusqu', d2),
    'montants', argent,
    'seuils', public.rh_argent_seuils(),
    'totaux', (select jsonb_build_object(
        'demandes', count(*), 'anciennes', count(*) filter (where d.demande_le < now() - seuil),
        'demandes_boutiques', count(*) filter (where d.type = 'boutique'),
        'demandes_livreurs', count(*) filter (where d.type = 'livreur'),
        'demandes_parrains', count(*) filter (where d.type = 'parrain'),
        'plus_ancienne', min(d.demande_le))
      || case when argent then (select jsonb_build_object(
        'attente_boutiques', coalesce(sum(t.attente) filter (where t.type = 'boutique'), 0),
        'attente_livreurs', coalesce(sum(t.attente) filter (where t.type = 'livreur'), 0),
        'attente_parrains', coalesce(sum(t.attente) filter (where t.type = 'parrain'), 0),
        'disponible_boutiques', coalesce(sum(t.disponible) filter (where t.type = 'boutique'), 0),
        'disponible_livreurs', coalesce(sum(t.disponible) filter (where t.type = 'livreur'), 0),
        'disponible_parrains', coalesce(sum(t.disponible) filter (where t.type = 'parrain'), 0),
        'reel', coalesce(sum(t.attente + t.disponible), 0),
        'a_venir_boutiques', coalesce(sum(t.a_venir) filter (where t.type = 'boutique'), 0),
        'a_venir_livreurs', coalesce(sum(t.a_venir) filter (where t.type = 'livreur'), 0),
        -- Le « théorique » des statistiques : ce que valent au prix BIZZOO
        -- les articles payés sur la période, livrés ou non.
        'theorique_periode', (select coalesce(sum(l.prix_bizzoo::bigint * l.quantite), 0)
                                from public.commande_lignes l
                                join public.commandes c on c.id = l.commande_id and c.etat = 'payee'
                               where l.etat <> 'annulee' and c.paye_le >= t1 and c.paye_le < t2),
        'verse_periode', (select coalesce(sum(v.montant), 0) from public.reversements v
                           where v.etat = 'valide' and v.decide_le >= t1 and v.decide_le < t2)
                       + (select coalesce(sum(v.montant), 0) from public.reversements_livreurs v
                           where v.etat = 'valide' and v.decide_le >= t1 and v.decide_le < t2)
                       + (select coalesce(sum(v.montant), 0) from public.retraits_parrain v
                           where v.etat = 'payee' and v.traite_le >= t1 and v.traite_le < t2))
        from tout t) else '{}'::jsonb end
      from d),
    'demandes', (select coalesce(jsonb_agg(jsonb_build_object(
        'type', x.type, 'nom', x.nom, 'le', x.demande_le,
        'jours', greatest(0, floor(extract(epoch from (now() - x.demande_le)) / 86400))::int,
        'ancienne', x.demande_le < now() - seuil)
        || case when argent then jsonb_build_object('montant', x.montant) else '{}'::jsonb end
        order by x.demande_le), '[]')
      from (select * from d order by d.demande_le limit 300) x),
    'comptes', (select coalesce(jsonb_agg(jsonb_build_object(
        'type', t.type, 'nom', t.nom, 'demandes', t.demandes, 'anciennes', t.anciennes,
        'plus_ancienne', t.plus_ancienne)
        || case when argent then jsonb_build_object('attente', t.attente, 'disponible', t.disponible,
                                                   'a_venir', t.a_venir) else '{}'::jsonb end
        order by t.anciennes desc, t.demandes desc, t.attente + t.disponible desc, t.nom), '[]')
      from tout t
     where t.demandes > 0 or t.disponible > 0 or t.a_venir > 0))
    into resultat;
  return resultat;
end $$;

/** Pourquoi un geste d'Admin mérite qu'on le regarde. */
create or replace function public.rh_geste_raisons(j_famille text, j_action text, j_libelle text,
                                                   j_le timestamptz, j_annule timestamptz)
returns text[]
language sql stable set search_path = public as $$
  select array_remove(array[
    case when j_action in ('suppression', 'desactivation') then 'suppression' end,
    -- Se connecter n'est pas un geste sensible : chaque ouverture d'Admin
    -- noierait le filtre « sensibles ».
    case when j_famille = 'compte' and coalesce(j_action, '') not in ('connexion', 'deconnexion') then 'compte' end,
    -- Admin écrit « Produit modifié : X — 10 000 FCFA » sans le mot « prix » :
    -- la devise suffit à dire qu'un montant a changé.
    case when coalesce(j_libelle, '') ~* '(marge|prix|taux|commission|remise|reversement|paiement|momopay|r[eé]ception|f ?cfa|xof)' then 'argent' end,
    case when extract(hour from j_le at time zone 'Africa/Porto-Novo') >= 22
           or extract(hour from j_le at time zone 'Africa/Porto-Novo') < 6 then 'nuit' end,
    case when j_annule is not null then 'annule' end], null);
$$;

/**
 * Le journal des gestes faits dans BIZZOO Admin (table « journal », que
 * l'écran d'Admin remplit lui-même) : qui, quoi, quand, sur quelle
 * boutique. Les gestes sensibles portent leurs raisons (suppression,
 * compte, argent, nuit, annulé, rafale de 10 gestes ou plus dans l'heure).
 * L'état d'avant (« retour ») : le CEO et le superadministrateur seuls.
 * Ce qui s'écrit hors de l'écran d'Admin (éditeur SQL, fonctions du
 * serveur) n'y figure pas : l'écran le dit.
 */
create or replace function public.rh_gestes(depuis date default null, jusqu date default null,
                                            v_famille text default null, v_sensibles boolean default false)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  tout_voir boolean := public.rh_est_ceo() or public.est_super();
  -- Un nombre, avec ses séparateurs de milliers (espace, insécable, point, virgule).
  chiffre_re text := '[0-9]([0-9 .,' || chr(160) || chr(8239) || ']*[0-9])?';
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  d1 date := coalesce(depuis, aujourdhui - 6);
  d2 date := coalesce(jusqu, aujourdhui);
  t1 timestamptz;
  t2 timestamptz;
  resultat jsonb;
begin
  if not coalesce((public.rh_argent_acces() ->> 'gestes')::boolean, false) then
    raise exception 'Le journal des gestes est réservé au CEO, au superadministrateur et aux profils ouverts à « audit »';
  end if;
  if d2 < d1 then
    raise exception 'La fin de la période précède son début';
  end if;
  if d2 - d1 > 400 then
    raise exception 'Choisissez une période d''un an au plus';
  end if;
  t1 := d1::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (d2 + 1)::timestamp at time zone 'Africa/Porto-Novo';

  with j as (
    select x.id, x.fait_le, x.utilisateur, x.famille, x.action, x.libelle, x.cible, x.annule_le, x.annule_par,
           x.retour, b.nom as boutique,
           count(*) over (partition by x.utilisateur, date_trunc('hour', x.fait_le)) as dans_l_heure
      from public.journal x
      left join public.boutiques b on b.id = x.boutique_id
     where x.fait_le >= t1 and x.fait_le < t2
  ), r as (
    select j.*, public.rh_geste_raisons(j.famille, j.action, j.libelle, j.fait_le, j.annule_le)
                || case when j.dans_l_heure >= 10 then array['rafale'] else '{}'::text[] end as raisons
      from j
  ), s as (
    select * from r
     where (coalesce(v_famille, '') = '' or r.famille = v_famille)
       and (not coalesce(v_sensibles, false) or cardinality(r.raisons) > 0)
  )
  select jsonb_build_object(
    'periode', jsonb_build_object('depuis', d1, 'jusqu', d2),
    'tout_voir', tout_voir,
    'chiffres_masques', not tout_voir,
    'totaux', (select jsonb_build_object(
        'gestes', count(*),
        'sensibles', count(*) filter (where cardinality(r.raisons) > 0),
        'suppressions', count(*) filter (where 'suppression' = any(r.raisons)),
        'argent', count(*) filter (where 'argent' = any(r.raisons)),
        'nuit', count(*) filter (where 'nuit' = any(r.raisons)),
        'annules', count(*) filter (where r.annule_le is not null),
        'auteurs', count(distinct r.utilisateur))
      from r),
    'familles', (select coalesce(jsonb_agg(jsonb_build_object('famille', x.famille, 'nb', x.nb) order by x.nb desc), '[]')
      from (select r.famille, count(*) as nb from r group by r.famille) x),
    'auteurs', (select coalesce(jsonb_agg(jsonb_build_object('qui', x.qui, 'gestes', x.nb, 'sensibles', x.sensibles,
                                                             'dernier', x.dernier)
                                          order by x.sensibles desc, x.nb desc), '[]')
      from (select coalesce(nullif(r.utilisateur, ''), 'inconnu') as qui, count(*) as nb,
                   count(*) filter (where cardinality(r.raisons) > 0) as sensibles, max(r.fait_le) as dernier
              from r group by 1 order by 3 desc, 2 desc limit 30) x),
    'lignes', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', x.id, 'le', x.fait_le, 'qui', nullif(x.utilisateur, ''), 'famille', x.famille, 'action', x.action,
        'libelle', case when tout_voir then x.libelle else regexp_replace(x.libelle, chiffre_re, '•••', 'g') end,
        'cible', nullif(case when tout_voir then x.cible else regexp_replace(coalesce(x.cible, ''), chiffre_re, '•••', 'g') end, ''),
        'boutique', x.boutique,
        'annule_le', x.annule_le, 'annule_par', nullif(x.annule_par, ''), 'raisons', to_jsonb(x.raisons))
        || case when tout_voir and x.retour is not null then jsonb_build_object('retour', left(x.retour::text, 2000))
                else '{}'::jsonb end
        order by x.fait_le desc, x.id desc), '[]')
      from (select * from s order by s.fait_le desc, s.id desc limit 500) x))
    into resultat;
  return resultat;
end $$;

/**
 * Les codes promo et le parrainage sur la période : pour chaque code, ses
 * usages (commandes payées), ce qu'il a coûté (remises) et rapporté
 * (ventes, commissions) ; pour chaque parrain, ses commissions et ses
 * retraits ; et les abus probables :
 *   meme_lieu   : un même code, plusieurs comptes, une même position de
 *                 livraison (à 100 m près) ou une même adresse ;
 *   propre_code : le parrain achète avec son propre code (même compte ou
 *                 même numéro).
 * Les numéros n'en sortent que par leurs 4 derniers chiffres, pour tout le
 * monde. Montants, valeur des codes, noms des parrains : l'administration ;
 * la clé « promos » donne les usages et les abus.
 * Limite : un code expiré ou refusé qu'un client tente encore n'est noté
 * nulle part (verifier_code ne garde rien).
 */
create or replace function public.rh_codes_surveillance(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  acces text := public.rh_argent_acces() ->> 'codes';
  argent boolean;
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  d1 date := coalesce(depuis, aujourdhui - 29);
  d2 date := coalesce(jusqu, aujourdhui);
  t1 timestamptz;
  t2 timestamptz;
  resultat jsonb;
begin
  if acces is null then
    raise exception 'Votre compte n''a pas accès aux codes promo';
  end if;
  if d2 < d1 then
    raise exception 'La fin de la période précède son début';
  end if;
  if d2 - d1 > 400 then
    raise exception 'Choisissez une période d''un an au plus';
  end if;
  argent := acces = 'admin';
  t1 := d1::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (d2 + 1)::timestamp at time zone 'Africa/Porto-Novo';

  with cm as (
    select c.id, c.numero, c.code_promo as code, c.remise, c.total, c.client_id, c.client_tel, c.paye_le,
           coalesce(c.client_id::text, right(regexp_replace(c.client_tel, '\D', '', 'g'), 8)) as compte,
           case when jsonb_typeof(c.livraison #> '{destination,latitude}') = 'number'
                 and jsonb_typeof(c.livraison #> '{destination,longitude}') = 'number'
                then 'gps:' || round((c.livraison #>> '{destination,latitude}')::numeric, 3)::text || ','
                            || round((c.livraison #>> '{destination,longitude}')::numeric, 3)::text
                -- « À retirer » en boutique : tout le monde y passe, ce n'est pas un indice.
                when btrim(c.client_adresse) = '' or c.client_adresse ~* 'retir' then ''
                else 'adr:' || lower(regexp_replace(btrim(c.client_adresse), '\s+', ' ', 'g')) end as lieu
      from public.commandes c
     where c.etat = 'payee' and c.code_promo <> '' and c.paye_le >= t1 and c.paye_le < t2
  ), lieux as (
    select cm.code, cm.lieu, count(distinct cm.compte) as comptes, count(*) as commandes,
           coalesce(sum(cm.remise), 0) as remise,
           jsonb_agg(distinct public.rh_tel_masque(cm.client_tel)) as numeros,
           jsonb_agg(cm.numero order by cm.paye_le) as liste
      from cm where cm.lieu <> ''
     group by cm.code, cm.lieu
    having count(distinct cm.compte) >= 2
  ), soi as (
    select cm.* from cm
      join public.codes_promo k on k.code = cm.code and k.parrain is not null
      left join public.clients pc on pc.id = k.parrain
     where cm.client_id = k.parrain
        or (length(regexp_replace(coalesce(pc.tel, ''), '\D', '', 'g')) >= 8
            and right(regexp_replace(cm.client_tel, '\D', '', 'g'), 8) = right(regexp_replace(pc.tel, '\D', '', 'g'), 8))
  ), abus as (
    select 'meme_lieu'::text as type, l.code, l.comptes, l.commandes, l.remise, l.numeros, l.liste,
           case when l.lieu like 'gps:%' then 'Même position de livraison, comptes différents'
                else 'Même adresse de livraison, comptes différents' end as detail
      from lieux l
    union all
    select 'propre_code', s.code, 1::bigint, count(*), coalesce(sum(s.remise), 0),
           jsonb_agg(distinct public.rh_tel_masque(s.client_tel)), jsonb_agg(s.numero order by s.paye_le),
           'Le parrain achète avec son propre code'
      from soi s group by s.code
  ), u as (
    select cm.code, count(*) as usages, count(distinct cm.compte) as clients,
           coalesce(sum(cm.remise), 0) as cout, coalesce(sum(cm.total), 0) as ventes
      from cm group by cm.code
  ), com as (
    select g.code, coalesce(sum(g.montant), 0) as commissions
      from public.gains_parrain g where g.cree_le >= t1 and g.cree_le < t2 group by g.code
  ), codes as (
    select coalesce(k.code, u.code) as code, k.libelle, k.actif, k.fin, k.maximum, k.mode, k.valeur,
           k.parrain is not null as particulier,
           coalesce(u.usages, 0) as usages, coalesce(u.clients, 0) as clients,
           coalesce(u.cout, 0) as cout, coalesce(u.ventes, 0) as ventes, coalesce(com.commissions, 0) as commissions,
           (select count(*) from public.commandes c where c.etat = 'payee' and c.code_promo = coalesce(k.code, u.code)) as usages_total,
           (select count(*) from abus a where a.code = coalesce(k.code, u.code)) as signalements
      from public.codes_promo k
      full join u on u.code = k.code
      left join com on com.code = coalesce(k.code, u.code)
     where coalesce(u.usages, 0) > 0 or coalesce(k.actif, false)
  ), par as (
    select q.parrain,
           (select string_agg(k.code, ', ' order by k.code) from public.codes_promo k where k.parrain = q.parrain) as codes,
           (select coalesce(sum(u.usages), 0) from u join public.codes_promo k on k.code = u.code and k.parrain = q.parrain) as usages,
           (select coalesce(sum(g.montant), 0) from public.gains_parrain g
             where g.parrain = q.parrain and g.cree_le >= t1 and g.cree_le < t2) as commissions_periode,
           (select coalesce(sum(g.montant), 0) from public.gains_parrain g where g.parrain = q.parrain) as commissions_total,
           (select coalesce(sum(r.montant), 0) from public.retraits_parrain r where r.parrain = q.parrain and r.etat = 'payee') as retire,
           (select coalesce(sum(r.montant), 0) from public.retraits_parrain r where r.parrain = q.parrain and r.etat = 'demande') as demande,
           (select count(*) from public.retraits_parrain r where r.parrain = q.parrain and r.etat = 'demande') as demandes,
           (select cl.nom from public.clients cl where cl.id = q.parrain) as nom,
           (select cl.tel from public.clients cl where cl.id = q.parrain) as tel,
           exists (select 1 from soi s join public.codes_promo k on k.code = s.code where k.parrain = q.parrain) as propre_code
      from (select distinct k.parrain from public.codes_promo k where k.parrain is not null) q
  )
  select jsonb_build_object(
    'periode', jsonb_build_object('depuis', d1, 'jusqu', d2),
    'montants', argent,
    'totaux', (select jsonb_build_object('usages', count(*), 'codes', count(distinct cm.code),
                                         'clients', count(distinct cm.compte),
                                         'abus', (select count(*) from abus))
                      || case when argent then jsonb_build_object(
                           'cout', coalesce(sum(cm.remise), 0), 'ventes', coalesce(sum(cm.total), 0),
                           'commissions', (select coalesce(sum(com.commissions), 0) from com))
                         else '{}'::jsonb end
                 from cm),
    'codes', (select coalesce(jsonb_agg(jsonb_build_object(
        'code', x.code, 'libelle', nullif(x.libelle, ''), 'actif', coalesce(x.actif, false), 'fin', x.fin,
        'maximum', x.maximum, 'particulier', x.particulier, 'usages', x.usages, 'clients', x.clients,
        'usages_total', x.usages_total, 'signalements', x.signalements)
        || case when argent then jsonb_build_object('mode', x.mode, 'valeur', x.valeur, 'cout', x.cout,
                                                   'ventes', x.ventes, 'commissions', x.commissions)
                else '{}'::jsonb end
        order by x.signalements desc, x.usages desc, x.code), '[]')
      from codes x),
    'parrains', (select coalesce(jsonb_agg(jsonb_build_object(
        'codes', x.codes, 'usages', x.usages, 'demandes', x.demandes, 'propre_code', x.propre_code,
        'tel', public.rh_tel_masque(x.tel))
        || case when argent then jsonb_build_object(
             'nom', nullif(btrim(coalesce(x.nom, '')), ''), 'commissions_periode', x.commissions_periode,
             'commissions_total', x.commissions_total, 'retire', x.retire, 'demande', x.demande,
             'disponible', greatest(0, x.commissions_total - x.retire - x.demande))
           else '{}'::jsonb end
        order by x.propre_code desc, x.usages desc, x.codes), '[]')
      from par x),
    'abus', (select coalesce(jsonb_agg(jsonb_build_object(
        'type', a.type, 'code', a.code, 'detail', a.detail, 'comptes', a.comptes, 'commandes', a.commandes,
        'numeros', a.numeros, 'liste', a.liste)
        || case when argent then jsonb_build_object('remise', a.remise) else '{}'::jsonb end
        order by a.commandes desc), '[]')
      from abus a))
    into resultat;
  return resultat;
end $$;

/** Les pastilles de l'argent : un seul appel, à chaque relecture des compteurs. */
create or replace function public.rh_argent_compteurs() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  a jsonb := public.rh_argent_acces();
  j int := (public.rh_argent_seuils() ->> 'dette_j')::int;
  res jsonb;
begin
  res := jsonb_build_object('onglets', a);
  if a ->> 'paiements' is not null then
    res := res || jsonb_build_object('paiements_a_traiter', (public.rh_paiements() #>> '{totaux,a_traiter}')::int);
  end if;
  if a ->> 'remboursements' is not null then
    res := res || jsonb_build_object('remboursements_en_retard',
                                     (public.rh_remboursements_liste() #>> '{totaux,en_retard}')::int);
  end if;
  if a ->> 'dettes' is not null then
    res := res || jsonb_build_object('dettes_anciennes',
      (select count(*) from public.reversements v
        where v.etat = 'en_attente' and v.demande_le < now() - make_interval(days => j))
      + (select count(*) from public.reversements_livreurs v
          where v.etat = 'en_attente' and v.demande_le < now() - make_interval(days => j))
      + (select count(*) from public.retraits_parrain v
          where v.etat = 'demande' and v.demande_le < now() - make_interval(days => j)));
  end if;
  return res;
end $$;

revoke all on function public.rh_annulation_noter() from public, anon, authenticated;
revoke all on function public.rh_argent_seuils() from public, anon;
grant execute on function public.rh_argent_seuils() to authenticated, service_role;
revoke all on function public.rh_tel_masque(text) from public, anon;
grant execute on function public.rh_tel_masque(text) to authenticated, service_role;
revoke all on function public.rh_argent_acces() from public, anon;
grant execute on function public.rh_argent_acces() to authenticated, service_role;
revoke all on function public.rh_argent_regler(int, int, int) from public, anon;
grant execute on function public.rh_argent_regler(int, int, int) to authenticated, service_role;
revoke all on function public.rh_paiements(date, date) from public, anon;
grant execute on function public.rh_paiements(date, date) to authenticated, service_role;
revoke all on function public.rh_rapprocher(text, text, text) from public, anon;
grant execute on function public.rh_rapprocher(text, text, text) to authenticated, service_role;
revoke all on function public.rh_rembourse_du(text) from public, anon, authenticated;
grant execute on function public.rh_rembourse_du(text) to service_role;
revoke all on function public.rh_remboursements_liste(date, date) from public, anon;
grant execute on function public.rh_remboursements_liste(date, date) to authenticated, service_role;
revoke all on function public.rh_rembourser(text, bigint, text, text, text) from public, anon;
grant execute on function public.rh_rembourser(text, bigint, text, text, text) to authenticated, service_role;
revoke all on function public.rh_dettes(date, date) from public, anon;
grant execute on function public.rh_dettes(date, date) to authenticated, service_role;
revoke all on function public.rh_geste_raisons(text, text, text, timestamptz, timestamptz) from public, anon;
grant execute on function public.rh_geste_raisons(text, text, text, timestamptz, timestamptz) to authenticated, service_role;
revoke all on function public.rh_gestes(date, date, text, boolean) from public, anon;
grant execute on function public.rh_gestes(date, date, text, boolean) to authenticated, service_role;
revoke all on function public.rh_codes_surveillance(date, date) from public, anon;
grant execute on function public.rh_codes_surveillance(date, date) to authenticated, service_role;
revoke all on function public.rh_argent_compteurs() from public, anon;
grant execute on function public.rh_argent_compteurs() to authenticated, service_role;

-- ---------- Les clés « paiements », « audit » et « promos » dans Paramètres ----------
-- « paiements » : les paiements à rapprocher et les remboursements dus,
-- sans montants (relation client, SAV) ; « audit » : le journal des
-- gestes de BIZZOO Admin ; « promos » : les usages des codes et les abus,
-- sans montants (marketing).
do $$
begin
  if to_regclass('public.rh_acces_menus') is null then
    return;
  end if;
  if exists (select 1 from pg_constraint where conname = 'rh_acces_menus_menu'
               and pg_get_constraintdef(oid) not like '%''promos''%') then
    alter table public.rh_acces_menus drop constraint rh_acces_menus_menu;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_acces_menus_menu') then
    alter table public.rh_acces_menus add constraint rh_acces_menus_menu check (menu in ('mails',
      'discussions', 'missions', 'rapports', 'depenses', 'suivi', 'livreurs', 'controles', 'paiements', 'audit',
      'promos', 'caisse', 'stats_commandes', 'stats_boutiques', 'stats_produits', 'stats_livraisons', 'stats_livreurs',
      'stats_sav', 'employes'));
  end if;
end $$;

-- ---------- Les menus réglables, les trois clés comprises (copies de schema.sql) ----------
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
    if k not in ('mails', 'discussions', 'missions', 'rapports', 'depenses', 'suivi', 'livreurs', 'controles', 'paiements', 'audit', 'promos', 'caisse',
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
    from unnest(array['mails', 'discussions', 'missions', 'rapports', 'depenses', 'suivi', 'livreurs', 'controles', 'paiements', 'audit', 'promos', 'caisse',
                      'stats_commandes', 'stats_boutiques', 'stats_produits', 'stats_livraisons',
                      'stats_livreurs', 'stats_sav', 'employes']) with ordinality as x(m, n)
   where public.rh_menu_ouvert(x.m);
$$;

-- (menus)
revoke all on function public.rh_regler_acces(uuid, jsonb) from public, anon;
grant execute on function public.rh_regler_acces(uuid, jsonb) to authenticated, service_role;
revoke all on function public.rh_mes_menus() from public, anon;
grant execute on function public.rh_mes_menus() to authenticated, service_role;
revoke all on function public.rh_audit_qui(uuid) from public, anon, authenticated;
grant execute on function public.rh_audit_qui(uuid) to service_role;
