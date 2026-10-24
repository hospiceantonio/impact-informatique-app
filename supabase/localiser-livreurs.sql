-- =========================================================
-- Localiser un livreur
--
-- BIZZOO Admin : pendant ses courses, le téléphone du livreur envoie sa
-- position (service Android, même application fermée ; la page, sinon),
-- avec un jeton de suivi qui ne permet que cela (position_en_course).
-- Il s'arrête de lui-même quand le livreur n'a plus de course.
--
-- BIZZOO Personnel : le menu « Localiser un livreur » (clé « livreurs »,
-- réglable dans Paramètres) lit les positions et les courses en cours
-- par rh_localiser_livreurs, avec la distance jusqu'au client.
-- =========================================================

-- ---------- Les aides (copies de schema.sql) ----------
create or replace function public.coord_valable(valeur double precision, borne double precision)
returns double precision
language sql immutable as $$
  select case when valeur is null
                or valeur <> valeur              -- « NaN » ne s'égale pas lui-même
                or valeur < -borne or valeur > borne
              then null else valeur end;
$$;

create or replace function public.est_livreur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'livreur', false);
$$;

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

-- ---------- Le livreur en course envoie sa position ----------
-- Le téléphone du livreur l'envoie toutes les 20 secondes environ, même
-- application fermée (service Android de BIZZOO Admin), tant qu'il a une
-- course en cours. Ce service ne tient pas la session du compte : une
-- session se renouvelle par un jeton à usage unique, et deux
-- renouvellements concurrents (la page et le service) déconnecteraient
-- le livreur. Il reçoit donc un JETON DE SUIVI : 64 caractères tirés au
-- hasard, gardés seulement en empreinte (sha256), valables 16 heures, qui
-- ne permettent QU'UNE chose : écrire la position de CE livreur.
create table if not exists public.suivis_livreurs (
  profil_id   uuid primary key references public.profils(id) on delete cascade,
  jeton_hash  text not null,
  expire_le   timestamptz not null,
  cree_le     timestamptz not null default now()
);
alter table public.suivis_livreurs enable row level security;
-- Aucune règle : personne ne lit ni n'écrit la table, sinon ces fonctions.
revoke all on table public.suivis_livreurs from public, anon, authenticated;
grant all on table public.suivis_livreurs to service_role;

/** Ce livreur a-t-il une course en cours ? Une ligne qu'on lui a
    confiée, d'une commande payée, pas encore remise ni annulée. */
create or replace function public.livreur_en_course(qui uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
     where l.livreur_id = qui and c.etat = 'payee'
       and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison'));
$$;

/** Le jeton de suivi du livreur connecté (un nouveau à chaque appel :
    l'ancien ne vaut plus rien). */
create or replace function public.ouvrir_suivi_livreur() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  jeton text;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Seul un livreur ouvre un suivi de position.' using errcode = '42501';
  end if;
  jeton := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into public.suivis_livreurs (profil_id, jeton_hash, expire_le, cree_le)
  values (moi, encode(sha256(convert_to(jeton, 'UTF8')), 'hex'), now() + interval '16 hours', now())
  on conflict (profil_id) do update
     set jeton_hash = excluded.jeton_hash, expire_le = excluded.expire_le, cree_le = now();
  return jsonb_build_object('jeton', jeton, 'en_course', public.livreur_en_course(moi),
                            'expire_le', now() + interval '16 hours');
end $$;

/** La position d'un livreur en course, par son jeton de suivi. Répond
    « continuer : false » quand il n'a plus de course : son téléphone
    s'arrête alors de la suivre. */
create or replace function public.position_en_course(jeton text, lat double precision,
  lng double precision, precision_m int default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  qui uuid;
  la double precision := public.coord_valable(lat, 90);
  lo double precision := public.coord_valable(lng, 180);
  derniere timestamptz;
begin
  select s.profil_id into qui from public.suivis_livreurs s
   where s.jeton_hash = encode(sha256(convert_to(coalesce(jeton, ''), 'UTF8')), 'hex')
     and s.expire_le > now();
  if qui is null then
    raise exception 'Suivi expiré : ouvrez BIZZOO Admin pour le reprendre.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profils p where p.id = qui and p.actif and p.role = 'livreur') then
    delete from public.suivis_livreurs where profil_id = qui;
    return jsonb_build_object('continuer', false);
  end if;
  if not public.livreur_en_course(qui) then
    delete from public.suivis_livreurs where profil_id = qui;
    return jsonb_build_object('continuer', false);
  end if;
  if la is null or lo is null or (la = 0 and lo = 0) then
    return jsonb_build_object('continuer', true);
  end if;
  -- Pas plus d'une écriture toutes les 5 secondes.
  select enregistre_le into derniere from public.positions_livreurs where profil_id = qui;
  if derniere is null or derniere < now() - interval '5 seconds' then
    insert into public.positions_livreurs (profil_id, latitude, longitude, precision_m, adresse, enregistre_le)
    values (qui, la, lo, greatest(0, precision_m), '', now())
    on conflict (profil_id) do update
       set latitude = excluded.latitude, longitude = excluded.longitude,
           precision_m = excluded.precision_m, enregistre_le = now();
  end if;
  return jsonb_build_object('continuer', true);
end $$;

revoke all on function public.livreur_en_course(uuid) from public, anon, authenticated;
revoke all on function public.ouvrir_suivi_livreur() from public, anon;
grant execute on function public.ouvrir_suivi_livreur() to authenticated;
-- Sans session : le jeton fait foi.
revoke all on function public.position_en_course(text, double precision, double precision, int) from public;
grant execute on function public.position_en_course(text, double precision, double precision, int)
  to anon, authenticated;

-- ---------- BIZZOO Personnel : le menu « Localiser un livreur » ----------
do $$
begin
  if to_regclass('public.rh_acces_menus') is null then
    return;  -- personnel-parametres.sql posera la table, « livreurs » compris
  end if;
  if exists (select 1 from pg_constraint where conname = 'rh_acces_menus_menu'
               and pg_get_constraintdef(oid) not like '%''livreurs''%') then
    alter table public.rh_acces_menus drop constraint rh_acces_menus_menu;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_acces_menus_menu') then
    alter table public.rh_acces_menus add constraint rh_acces_menus_menu check (menu in ('mails',
      'discussions', 'missions', 'rapports', 'depenses', 'suivi', 'livreurs', 'stats_commandes',
      'stats_boutiques', 'stats_produits', 'stats_livraisons', 'stats_livreurs', 'stats_sav', 'employes'));
  end if;
end $$;

/** Les livreurs sur la carte : leur dernière position, et pour chacun
    ses courses en cours, avec le point du client quand il l'a donné et
    la distance qui les sépare — à vol d'oiseau, multipliée par le
    coefficient de route de la livraison au kilomètre (« environ »).
    Sans aucun montant. */
create or replace function public.rh_localiser_livreurs() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  coef numeric := coalesce((select livraison_coef from public.paiement where id = 1), 1.3);
begin
  if not public.rh_menu_ouvert('livreurs') then
    raise exception 'Votre compte n''a pas accès à la localisation des livreurs';
  end if;
  return jsonb_build_object(
    'coef', coef,
    'maintenant', now(),
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
          'suivi_actif', exists (select 1 from public.suivis_livreurs s
                                  where s.profil_id = p.id and s.expire_le > now()),
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
revoke all on function public.rh_localiser_livreurs() from public, anon;
grant execute on function public.rh_localiser_livreurs() to authenticated, service_role;

-- ---------- Les menus réglables, « livreurs » compris (copies de schema.sql) ----------
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
    if k not in ('mails', 'discussions', 'missions', 'rapports', 'depenses', 'suivi', 'livreurs',
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

create or replace function public.rh_mes_menus() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(x.m order by x.n), '{}')
    from unnest(array['mails', 'discussions', 'missions', 'rapports', 'depenses', 'suivi', 'livreurs',
                      'stats_commandes', 'stats_boutiques', 'stats_produits', 'stats_livraisons',
                      'stats_livreurs', 'stats_sav', 'employes']) with ordinality as x(m, n)
   where public.rh_menu_ouvert(x.m);
$$;

-- ---------- Le suivi des commandes donne l'identifiant du livreur (copie de schema.sql) ----------
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
