-- =========================================================
-- BIZZOO 3.74.0 — La tournée : de boutique en boutique, puis au client
--
--   La distance d'une livraison ne part plus du point BIZZOO : elle suit
--   le trajet du livreur, boutique A → boutique B → … → client, dans
--   l'ordre le plus court, que la base choisit. Les frais :
--     forfait du véhicule jusqu'à 10 km
--     + prix du km au-delà (km entamé)
--     + 200 FCFA par boutique (réglable : livraison_supplement_boutique).
--   Une boutique sans position compte depuis le point BIZZOO.
--   Le livreur lit l'itinéraire, les frais, la part de BIZZOO et son gain.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

alter table public.paiement add column if not exists livraison_supplement_boutique int not null default 200;
alter table public.paiement drop constraint if exists paiement_supplement_borne;
alter table public.paiement add constraint paiement_supplement_borne
  check (livraison_supplement_boutique between 0 and 100000);

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.point_retrait_produit(produit text) returns text
language plpgsql stable security definer set search_path = public as $$
declare r text;
begin
  select case when pp.vendeur_id is not null and pp.taux_vendeur is not null and b.vendeurs = 'multiples'
              then 'v:' || pp.vendeur_id::text else p.boutique_id end
    into r
    from public.produits p
    join public.boutiques b on b.id = p.boutique_id
    left join public.produits_prive pp on pp.produit_id = p.id
   where p.id = produit;
  return r;
end $$;
revoke all on function public.point_retrait_produit(text) from public, anon, authenticated;

create or replace function public.points_commande(cible text) returns text[]
language plpgsql stable security definer set search_path = public as $$
begin
  return array(select distinct case when l.vendeur_id is not null and b.vendeurs = 'multiples'
                                    then 'v:' || l.vendeur_id::text else l.boutique_id end
                 from public.commande_lignes l
                 join public.boutiques b on b.id = l.boutique_id
                where l.commande_id = cible and l.boutique_id is not null);
end $$;
revoke all on function public.points_commande(text) from public, anon, authenticated;

create or replace function public.vendeur_ouvert(cible uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return coalesce((select public.boutique_ouverte(l.ouvertures) from public.vendeurs_lieux l
                    where l.vendeur_id = cible), true);
end $$;
grant execute on function public.vendeur_ouvert(uuid) to anon, authenticated;

create or replace function public.vendeurs_retrait(commande text, boutique text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'vendeur_id', l.vendeur_id,
             'nom', coalesce(nullif(btrim(vl.nom), ''), nullif(btrim(v.nom), ''), 'Vendeur'),
             'adresse', coalesce(vl.adresse, ''), 'tel', coalesce(nullif(vl.tel, ''), v.tel, ''),
             'indicatif', coalesce(vl.indicatif, '229'),
             'latitude', vl.latitude, 'longitude', vl.longitude,
             'articles', l.articles) order by l.vendeur_id)
      from (select x.vendeur_id,
                   jsonb_agg(jsonb_build_object('nom', coalesce(x.nom, ''), 'quantite', x.quantite)
                             order by x.id) as articles
              from public.commande_lignes x
             where x.commande_id = commande and x.boutique_id = boutique and x.vendeur_id is not null
               and x.etat <> 'annulee'
             group by x.vendeur_id) l
      join public.boutiques b on b.id = boutique and b.vendeurs = 'multiples'
      left join public.profils v on v.id = l.vendeur_id
      left join public.vendeurs_lieux vl on vl.vendeur_id = l.vendeur_id), '[]'::jsonb);
end $$;
revoke all on function public.vendeurs_retrait(text, text) from public, anon, authenticated;

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
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

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.boutique_ouverte(o jsonb, moment timestamptz default now())
returns boolean
language sql stable set search_path = public as $$
  with ici as (select (moment at time zone 'Africa/Porto-Novo') as t)
  select case
    when o is null then true
    else coalesce((
      select jsonb_typeof(o -> j.jour) = 'object'
         and to_char(ici.t, 'HH24:MI') >= (o -> j.jour ->> 'de')
         and to_char(ici.t, 'HH24:MI') <  (o -> j.jour ->> 'a')
        from ici, lateral (select (array['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'])
                                    [extract(isodow from ici.t)::int] as jour) j), false)
  end;
$$;
grant execute on function public.boutique_ouverte(jsonb, timestamptz) to anon, authenticated;

create or replace function public.code_normalise(brut text) returns text
language sql immutable as $$
  select left(regexp_replace(upper(coalesce(brut, '')), '[^A-Z0-9]', '', 'g'), 24);
$$;

create or replace function public.commande_total(cible text) returns void
language plpgsql security definer set search_path = public as $$
declare avant text := coalesce(current_setting('bizzoo.interne', true), '');
begin
  -- C'est la base qui écrit ce total, pas un client : le verrou de la
  -- section suivante doit le laisser passer. Le drapeau est ensuite
  -- rendu tel qu'il était, pour ne pas ouvrir la porte au reste de
  -- l'appel.
  perform set_config('bizzoo.interne', 'oui', true);
  update public.commandes c
     set total = greatest(0,
           coalesce((select sum(l.prix * l.quantite)
                       from public.commande_lignes l
                      where l.commande_id = cible), 0)
           - greatest(0, coalesce(c.remise, 0)))
           -- Les frais de livraison s'ajoutent APRÈS la remise : un code
           -- promo ne les touche pas.
           + greatest(0, coalesce(c.frais_livraison, 0))
   where c.id = cible;
  perform set_config('bizzoo.interne', avant, true);
end $$;
revoke all on function public.commande_total(text) from public, anon, authenticated;

create or replace function public.compte_exige() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select r.compte_obligatoire from public.reglages r where r.id = 1), false);
$$;
revoke all on function public.compte_exige() from public, anon, authenticated;
grant execute on function public.compte_exige() to anon, authenticated;

create or replace function public.gain_livreur(cible text) returns bigint
language plpgsql stable security definer set search_path = public as $$
declare g bigint; p numeric; t int;
begin
  select sum(x.montant)::bigint into g from public.gains_livreurs x
   where x.commande_id = cible and x.livreur_id = auth.uid();
  if g is not null then return g; end if;
  p := public.part_frais_livreur(cible, auth.uid());
  if coalesce(p, 0) <= 0 then return null; end if;
  select coalesce(x.taux_livreur, 80) into t from public.paiement x where x.id = 1;
  return floor(p * coalesce(t, 80) / 100.0)::bigint;
end $$;
revoke all on function public.gain_livreur(text) from public, anon, authenticated;

create or replace function public.grille_route(x double precision) returns numeric
language sql immutable as $$
  select (round((x * 2000)::numeric) / 2000)::numeric(9,4);
$$;

create or replace function public.livraison_active() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.livraison_latitude is not null and p.livraison_longitude is not null
                     from public.paiement p where p.id = 1), false);
$$;
revoke all on function public.livraison_active() from public;
grant execute on function public.livraison_active() to anon, authenticated;

create or replace function public.montant_lisible(n numeric, devise text default 'FCFA')
returns text
language sql immutable set search_path = public as $$
  select replace(to_char(coalesce(n, 0), 'FM999,999,999,990'), ',', ' ') || ' ' || coalesce(nullif(devise, ''), 'FCFA');
$$;
revoke all on function public.montant_lisible(numeric, text) from public, anon, authenticated;

create or replace function public.remise_du_code(
  brut text, sous_total bigint, marge bigint,
  qui uuid default null, tel text default '')
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c       public.codes_promo%rowtype;
  cle     text := public.code_normalise(brut);
  brute   bigint;
  plafond bigint := greatest(0, coalesce(marge, 0));
  combien int;
  -- PAS « numero » : « commandes » a une colonne de ce nom, et
  -- PostgreSQL refuserait la requête plus bas — « column reference
  -- numero is ambiguous ».
  tel_net text := left(regexp_replace(coalesce(tel, ''), '\D', '', 'g'), 20);
  refus   constant text := 'Ce code n''existe pas, ou n''est plus valable.';
begin
  if cle = '' then
    return jsonb_build_object('ok', false, 'remise', 0, 'raison', refus);
  end if;
  -- UN REVENDEUR A DÉJÀ SA REMISE : il achète au prix BIZZOO, sur tout le
  -- catalogue. Un code s'y ajouterait, et sortirait une seconde fois de
  -- la même marge. La caisse passe alors la commande sans le code.
  if qui is not null and exists (select 1 from public.clients r
                                 where r.id = qui and r.revendeur_etat = 'validee') then
    return jsonb_build_object('ok', false, 'remise', 0,
      'raison', 'Votre compte revendeur achète déjà au prix BIZZOO : les codes promo ne s''y ajoutent pas.');
  end if;
  select * into c from public.codes_promo where code = cle;
  -- MÊME RÉPONSE pour « inconnu » et « fermé ». Distinguer les deux
  -- dirait à qui essaie des codes au hasard lesquels ont existé.
  if not found or not c.actif then
    return jsonb_build_object('ok', false, 'remise', 0, 'raison', refus);
  end if;
  if c.fin is not null and c.fin < current_date then
    return jsonb_build_object('ok', false, 'remise', 0,
      'raison', 'Ce code a expiré le ' || to_char(c.fin, 'DD/MM/YYYY') || '.');
  end if;
  if coalesce(sous_total, 0) < c.minimum then
    return jsonb_build_object('ok', false, 'remise', 0,
      'raison', 'Ce code s''applique à partir de ' || c.minimum::text || '.');
  end if;

  -- LES UTILISATIONS SE COMPTENT SUR LES COMMANDES PAYÉES. Compter les
  -- paniers déposés laisserait des commandes jamais réglées manger le
  -- quota, et refuserait le code à de vrais clients. Le risque inverse
  -- — quelques remises de plus si beaucoup paient en même temps — coûte
  -- bien moins cher qu'un client refusé à tort.
  if c.maximum > 0 then
    select count(*) into combien from public.commandes o
     where o.code_promo = cle and o.etat = 'payee';
    if combien >= c.maximum then
      return jsonb_build_object('ok', false, 'remise', 0,
        'raison', 'Ce code a atteint son nombre d''utilisations.');
    end if;
  end if;

  -- LE PROPRIÉTAIRE D'UN CODE NE S'EN SERT PAS : il toucherait une
  -- commission sur ses propres achats.
  if c.parrain is not null and qui is not null and qui = c.parrain then
    return jsonb_build_object('ok', false, 'remise', 0,
      'raison', 'C''est votre code : il sert à vos clients, pas à vous.');
  end if;

  -- « Une seule fois par client ». Un compte se reconnaît à son
  -- identifiant ; un visiteur sans compte, à son seul numéro — on le dit
  -- franchement plutôt que de laisser croire à une identification qui
  -- n'existe pas.
  if c.une_par_client and (qui is not null or tel_net <> '') then
    if exists (select 1 from public.commandes o
                where o.code_promo = cle and o.etat = 'payee'
                  and ((qui is not null and o.client_id = qui)
                       or (tel_net <> '' and o.client_tel = tel_net))) then
      return jsonb_build_object('ok', false, 'remise', 0,
        'raison', 'Vous avez déjà utilisé ce code.');
    end if;
  end if;

  brute := case when c.mode = 'montant' then round(c.valeur)::bigint
                else round(coalesce(sous_total, 0) * least(100, greatest(0, c.valeur)) / 100)::bigint end;
  brute := greatest(0, least(brute, greatest(0, coalesce(sous_total, 0))));

  -- LE PLAFOND. La boutique touche son prix BIZZOO en entier : la
  -- remise ne peut pas dépasser ce que l'enseigne gagne sur cette
  -- commande. On rabote sans rien dire de plus que le montant obtenu —
  -- la marge de l'enseigne ne regarde pas le client.
  if brute > plafond then brute := plafond; end if;

  -- UN CODE DE PARTICULIER VAUT MÊME SANS REMISE : il porte la commission
  -- de son propriétaire, et la commande doit le garder.
  if brute <= 0 and c.parrain is null then
    return jsonb_build_object('ok', false, 'remise', 0,
      'raison', 'Ce code ne s''applique pas à ce panier.');
  end if;
  return jsonb_build_object('ok', true, 'remise', brute, 'raison', '');
end $$;
revoke all on function public.remise_du_code(text, bigint, bigint, uuid, text)
  from public, anon, authenticated;

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
revoke all on function public.restes_par_boutique(text) from public, anon, authenticated;

create or replace function public.distance_trajet(
  de_lat double precision, de_lng double precision, a_lat double precision, a_lng double precision,
  out km numeric, out par_route boolean)
language plpgsql stable security definer set search_path = public as $$
declare
  m    int;
  dlat double precision;
  dlng double precision;
  h    double precision;
  coef numeric := coalesce((select p.livraison_coef from public.paiement p where p.id = 1), 1.3);
begin
  if public.grille_route(de_lat) = public.grille_route(a_lat)
     and public.grille_route(de_lng) = public.grille_route(a_lng) then
    km := 0; par_route := true;
    return;
  end if;
  select x.distance_m into m from public.distances_route x
   where x.o_lat = public.grille_route(de_lat) and x.o_lng = public.grille_route(de_lng)
     and x.d_lat = public.grille_route(a_lat) and x.d_lng = public.grille_route(a_lng);
  if m is not null then
    km := round(m / 1000.0, 3); par_route := true;
    return;
  end if;
  dlat := radians(a_lat - de_lat);
  dlng := radians(a_lng - de_lng);
  h := sin(dlat / 2) ^ 2 + cos(radians(de_lat)) * cos(radians(a_lat)) * sin(dlng / 2) ^ 2;
  km := round((2 * 6371 * asin(least(1, sqrt(h))) * coef)::numeric, 3);
  par_route := false;
end $$;
revoke all on function public.distance_trajet(double precision, double precision, double precision, double precision)
  from public, anon, authenticated;

create or replace function public.devis_tournee(
  boutiques text[], latitude double precision, longitude double precision, vehicule text default 'moto')
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r      public.paiement%rowtype;
  v      text := case when vehicule = 'tricycle' then 'tricycle' else 'moto' end;
  ids    text[] := '{}';
  noms   text[] := '{}';
  lats   double precision[] := '{}';
  lngs   double precision[] := '{}';
  sans   boolean[] := '{}';
  n      int;
  w      int;
  d      numeric[] := '{}';
  routes int := 0;
  tron   int := 0;
  t      record;
  i      int;
  j      int;
  k      int;
  a      int[];
  c      int[];
  meil   int[];
  cout   numeric;
  best   numeric;
  tmp    int;
  libre  boolean[];
  dist   numeric;
  km     int;
  forf   int;
  prix   int;
  sup    int;
  etapes jsonb := '[]'::jsonb;
  b      record;
begin
  select * into r from public.paiement where id = 1;
  if not found or r.livraison_latitude is null or r.livraison_longitude is null then
    return null;
  end if;
  if latitude is null or longitude is null
     or latitude not between -90 and 90 or longitude not between -180 and 180
     or (latitude = 0 and longitude = 0) then
    raise exception 'Position de livraison invalide : touchez « Utiliser ma position ».'
      using errcode = 'P0001';
  end if;
  -- Les boutiques, une fois chacune, dans un ordre fixe (leur identifiant) :
  -- à distances égales, la base et l'application choisissent la même.
  -- (3.78.0) Un lieu « v:<vendeur> » est un vendeur d'une boutique à
  -- vendeurs multiples : son nom, SA position (jamais celle de la boutique
  -- multivendeur), le point BIZZOO s'il n'en a pas encore. Un arrêt comme
  -- un autre, avec son supplément.
  for b in select k.cle as id,
                  case when k.vendeur then coalesce(nullif(btrim(vl.nom), ''), nullif(btrim(pv.nom), ''), 'Vendeur')
                       else x.nom end as nom,
                  case when k.vendeur then vl.latitude else x.latitude end as latitude,
                  case when k.vendeur then vl.longitude else x.longitude end as longitude
             from (select distinct u.cle0 as cle, u.cle0 like 'v:%' as vendeur
                     from unnest(coalesce(boutiques, '{}')) as u(cle0) where u.cle0 is not null) k
             left join public.boutiques x on not k.vendeur and x.id = k.cle
             left join public.profils pv on k.vendeur and pv.id::text = substr(k.cle, 3) and pv.role = 'vendeur'
             left join public.vendeurs_lieux vl on k.vendeur and vl.vendeur_id::text = substr(k.cle, 3)
            where x.id is not null or pv.id is not null
            order by k.cle collate "C" loop
    ids  := ids || b.id;
    noms := noms || coalesce(b.nom, '');
    if b.latitude is null or b.longitude is null or (b.latitude = 0 and b.longitude = 0)
       or b.latitude not between -90 and 90 or b.longitude not between -180 and 180 then
      lats := lats || r.livraison_latitude; lngs := lngs || r.livraison_longitude; sans := sans || true;
    else
      lats := lats || b.latitude; lngs := lngs || b.longitude; sans := sans || false;
    end if;
  end loop;
  n := coalesce(array_length(ids, 1), 0);
  if n = 0 then
    -- Aucune boutique connue : du point BIZZOO, comme avant, sans supplément.
    lats := array[r.livraison_latitude]; lngs := array[r.livraison_longitude];
    ids := array[null::text]; noms := array['BIZZOO']; sans := array[false];
  end if;
  w := greatest(n, 1);
  -- Les tronçons : d[(i-1)*(w+1)+j], j = w+1 étant le client.
  for i in 1 .. w loop
    for j in 1 .. w + 1 loop
      if j = i then
        d := d || 0::numeric;
      else
        select * into t from public.distance_trajet(lats[i], lngs[i],
          case when j <= w then lats[j] else latitude end,
          case when j <= w then lngs[j] else longitude end);
        d := d || t.km;
      end if;
    end loop;
  end loop;

  -- L'ordre le plus court.
  a := array(select generate_series(1, w));
  meil := a;
  if w <= 7 then
    -- Toutes les possibilités (algorithme de Heap) ; à égalité, la première.
    c := array_fill(0, array[w]);
    best := null;
    loop
      cout := 0;
      for k in 1 .. w - 1 loop cout := cout + d[(a[k] - 1) * (w + 1) + a[k + 1]]; end loop;
      cout := cout + d[(a[w] - 1) * (w + 1) + w + 1];
      if best is null or cout < best then best := cout; meil := a; end if;
      i := 1;
      while i < w and c[i + 1] >= i loop
        c[i + 1] := 0; i := i + 1;
      end loop;
      exit when i >= w;
      if i % 2 = 0 then
        tmp := a[1]; a[1] := a[i + 1]; a[i + 1] := tmp;
      else
        tmp := a[c[i + 1] + 1]; a[c[i + 1] + 1] := a[i + 1]; a[i + 1] := tmp;
      end if;
      c[i + 1] := c[i + 1] + 1;
    end loop;
  else
    -- Plus de 7 boutiques : de la plus proche en plus proche, en essayant
    -- chaque boutique de départ.
    best := null;
    for i in 1 .. w loop
      libre := array_fill(true, array[w]);
      a := array[i]; libre[i] := false; cout := 0;
      for k in 2 .. w loop
        tmp := null;
        for j in 1 .. w loop
          if libre[j] and (tmp is null or d[(a[k - 1] - 1) * (w + 1) + j] < d[(a[k - 1] - 1) * (w + 1) + tmp]) then
            tmp := j;
          end if;
        end loop;
        cout := cout + d[(a[k - 1] - 1) * (w + 1) + tmp];
        a := a || tmp; libre[tmp] := false;
      end loop;
      cout := cout + d[(a[w] - 1) * (w + 1) + w + 1];
      if best is null or cout < best then best := cout; meil := a; end if;
    end loop;
  end if;

  -- Les étapes, dans l'ordre, avec le tronçon qui mène à la suivante.
  dist := 0;
  for k in 1 .. w loop
    i := meil[k];
    j := case when k < w then meil[k + 1] else w + 1 end;
    dist := dist + d[(i - 1) * (w + 1) + j];
    tron := tron + 1;
    select * into t from public.distance_trajet(lats[i], lngs[i],
      case when j <= w then lats[j] else latitude end,
      case when j <= w then lngs[j] else longitude end);
    if t.par_route then routes := routes + 1; end if;
    if n > 0 then
      etapes := etapes || (jsonb_build_object(
        'boutique_id', case when ids[i] like 'v:%' then null else ids[i] end, 'nom', noms[i],
        'latitude', round(lats[i]::numeric, 6), 'longitude', round(lngs[i]::numeric, 6),
        'sans_position', sans[i],
        'vers_suivante_km', round(d[(i - 1) * (w + 1) + j], 1)) ||
        case when ids[i] like 'v:%' then jsonb_build_object('vendeur_id', substr(ids[i], 3))
             else '{}'::jsonb end);
    end if;
  end loop;

  km := case when dist > r.livraison_rayon_km then ceil(dist - r.livraison_rayon_km)::int else 0 end;
  forf := case when v = 'tricycle' then r.tricycle_forfait else r.moto_forfait end;
  prix := case when v = 'tricycle' then r.tricycle_prix_km else r.moto_prix_km end;
  -- (3.74.1) Le supplément ne vaut que pour une commande GROUPÉE (deux
  -- boutiques ou plus) ; une seule boutique : forfait + km, sans plus.
  sup  := case when n > 1 then coalesce(r.livraison_supplement_boutique, 0) else 0 end;
  return jsonb_build_object(
    'vehicule', v,
    'distance_km', round(dist, 1),
    'calcul', case when routes = tron then 'route' when routes = 0 then 'vol_oiseau' else 'mixte' end,
    'rayon_km', r.livraison_rayon_km,
    'km_factures', km,
    'forfait', forf,
    'prix_km', prix,
    'supplement_boutique', sup,
    'nb_boutiques', n,
    'supplements', n * sup,
    'frais', forf + km * prix + n * sup,
    'tournee', etapes,
    'point', jsonb_build_object('latitude', r.livraison_latitude, 'longitude', r.livraison_longitude),
    'destination', jsonb_build_object('latitude', round(latitude::numeric, 6),
                                      'longitude', round(longitude::numeric, 6)));
end $$;
revoke all on function public.devis_tournee(text[], double precision, double precision, text) from public;
grant execute on function public.devis_tournee(text[], double precision, double precision, text) to anon, authenticated;

create or replace function public.route_connue_trajet(
  de_lat double precision, de_lng double precision, a_lat double precision, a_lng double precision)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r       public.paiement%rowtype;
  dm      int;
  plafond constant int := 1000;
begin
  select * into r from public.paiement where id = 1;
  if not found or r.livraison_latitude is null or r.livraison_longitude is null then
    return jsonb_build_object('point', false);
  end if;
  if de_lat is null or de_lng is null or a_lat is null or a_lng is null
     or de_lat not between -90 and 90 or de_lng not between -180 and 180
     or a_lat not between -90 and 90 or a_lng not between -180 and 180
     or (a_lat = 0 and a_lng = 0) then
    return jsonb_build_object('point', true, 'invalide', true);
  end if;
  if not ((public.grille_route(de_lat) = public.grille_route(r.livraison_latitude)
           and public.grille_route(de_lng) = public.grille_route(r.livraison_longitude))
          or exists (select 1 from public.boutiques b
                      where b.latitude is not null and b.longitude is not null
                        and public.grille_route(b.latitude) = public.grille_route(de_lat)
                        and public.grille_route(b.longitude) = public.grille_route(de_lng))) then
    return jsonb_build_object('point', true, 'invalide', true);
  end if;
  select x.distance_m into dm from public.distances_route x
   where x.o_lat = public.grille_route(de_lat) and x.o_lng = public.grille_route(de_lng)
     and x.d_lat = public.grille_route(a_lat) and x.d_lng = public.grille_route(a_lng);
  return jsonb_build_object(
    'point', true,
    'origine', jsonb_build_object('latitude', de_lat, 'longitude', de_lng),
    'distance_m', dm,
    'plafond_atteint', dm is null and (select count(*) from public.distances_route x
                                         where x.cree_le > now() - interval '1 day') >= plafond);
end $$;
revoke all on function public.route_connue_trajet(double precision, double precision, double precision, double precision)
  from public, anon, authenticated;
grant execute on function public.route_connue_trajet(double precision, double precision, double precision, double precision)
  to service_role;

create or replace function public.enregistrer_route_trajet(
  de_lat double precision, de_lng double precision, a_lat double precision, a_lng double precision,
  distance_m int)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if coalesce((public.route_connue_trajet(de_lat, de_lng, a_lat, a_lng) ->> 'invalide')::boolean, false)
     or not coalesce((public.route_connue_trajet(de_lat, de_lng, a_lat, a_lng) ->> 'point')::boolean, false) then
    return jsonb_build_object('ok', false);
  end if;
  if distance_m is null or distance_m <= 0 or distance_m > 1000000 then
    raise exception 'Distance de route invalide';
  end if;
  insert into public.distances_route as x (o_lat, o_lng, d_lat, d_lng, distance_m, cree_le)
  values (public.grille_route(de_lat), public.grille_route(de_lng),
          public.grille_route(a_lat), public.grille_route(a_lng), distance_m, now())
  on conflict on constraint distances_route_pkey
  do update set distance_m = excluded.distance_m, cree_le = now();
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.enregistrer_route_trajet(double precision, double precision, double precision, double precision, int)
  from public, anon, authenticated;
grant execute on function public.enregistrer_route_trajet(double precision, double precision, double precision, double precision, int)
  to service_role;

create or replace function public.fiche_course(commande text, boutique text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c   public.commandes%rowtype;
  b   public.boutiques%rowtype;
  pos record;
  brut numeric;
  tout numeric;
  part numeric;
  frais numeric;
  reste numeric;
begin
  select * into c from public.commandes where id = commande;
  if not found then return null; end if;
  select * into b from public.boutiques where id = boutique;
  select sum(l.prix * l.quantite) filter (where l.boutique_id = boutique),
         sum(l.prix * l.quantite)
    into brut, tout
    from public.commande_lignes l where l.commande_id = commande;
  select coalesce(r.a_encaisser, 0) into reste
    from public.restes_par_boutique(commande) r where r.boutique_id = boutique;
  if c.livraison is not null then
    -- (3.64.0) AU KILOMÈTRE, un seul livreur porte toute la commande : ses
    -- frais sont ceux de la commande entière.
    part  := (c.parts -> boutique ->> 'du')::numeric;
    frais := coalesce(c.frais_livraison, 0);
  elsif c.parts is not null and c.parts ? boutique then
    part  := (c.parts -> boutique ->> 'du')::numeric;
    frais := (c.parts -> boutique ->> 'frais')::numeric;
  else
    -- Une commande d'avant les conditions par boutique : sa part au
    -- prorata, frais compris.
    part  := round(c.total * coalesce(brut, 0) / nullif(tout, 0));
    frais := case when coalesce(brut, 0) = coalesce(tout, 0) then coalesce(c.frais_livraison, 0)
                  else round(coalesce(c.frais_livraison, 0) * coalesce(brut, 0) / nullif(tout, 0)) end;
  end if;
  return jsonb_build_object(
    'numero', c.numero,
    -- (3.70.0) Où récupérer la commande, tel que l'équipe l'a saisi
    -- (« Faire livrer ») ; vide pour une commande de l'application.
    'lieu_retrait', coalesce(c.lieu_retrait, ''),
    'retrait', jsonb_build_object(
      'boutique', coalesce(b.nom, ''), 'adresse', coalesce(b.adresse, ''),
      'tel', coalesce(nullif(b.tel, ''), b.whatsapp, ''), 'indicatif', coalesce(nullif(b.indicatif, ''), '229'),
      -- (3.70.0) Pour « Écrire à la boutique sur WhatsApp ».
      'whatsapp', coalesce(nullif(b.whatsapp, ''), b.tel, ''),
      'latitude', b.latitude, 'longitude', b.longitude,
      -- (3.78.0) Boutique à vendeurs multiples : chaque vendeur chez qui
      -- récupérer, avec SON lieu, son numéro et ses articles.
      'vendeurs', public.vendeurs_retrait(commande, boutique)),
    'livraison', jsonb_build_object(
      'nom', coalesce(c.client_nom, ''), 'adresse', coalesce(c.client_adresse, ''),
      'note', coalesce(c.note, ''), 'tel', coalesce(c.client_tel, ''),
      'indicatif', coalesce(nullif(c.client_indicatif, ''), '229'),
      -- (3.64.0) Le point exact où livrer, quand le client l'a donné.
      'latitude', c.livraison -> 'destination' -> 'latitude',
      'longitude', c.livraison -> 'destination' -> 'longitude'),
    'devise', coalesce(c.devise, 'FCFA'),
    'frais', coalesce(frais, 0),
    -- (3.64.0) Le véhicule, la distance, et ce que le livreur y gagne.
    'trajet', case when c.livraison is null then null
                   else jsonb_build_object('vehicule', c.livraison ->> 'vehicule',
                                           'distance_km', c.livraison -> 'distance_km',
                                           -- (3.74.0) La tournée : l'ordre des boutiques,
                                           -- et de quoi se composent les frais.
                                           'tournee', c.livraison -> 'tournee',
                                           'forfait', c.livraison -> 'forfait',
                                           'km_factures', c.livraison -> 'km_factures',
                                           'prix_km', c.livraison -> 'prix_km',
                                           'supplements', c.livraison -> 'supplements',
                                           'nb_boutiques', c.livraison -> 'nb_boutiques') end,
    -- (3.66.0) Au kilomètre ou à l'ancien tarif : sa part des frais.
    'gain', public.gain_livreur(c.id),
    'deja_paye', greatest(0, coalesce(part, 0) - coalesce(reste, 0)),
    'a_encaisser', coalesce(reste, 0),
    -- Ce que le livreur a déclaré en remettant le colis (3.59.0).
    'encaisse', (select jsonb_build_object('montant', x.montant, 'mode', x.mode,
                         'encaisse_le', x.encaisse_le, 'remis_le', x.remis_le,
                         'transaction', x.transaction_id)
                   from public.encaissements x
                  where x.commande_id = commande and x.boutique_id = boutique),
    -- Le code MoMoPay de BIZZOO, à montrer au client (3.59.0).
    'momopay', (select jsonb_build_object('code', p.momopay_code, 'nom', p.momopay_nom)
                  from public.paiement p where p.id = 1));
end $$;
revoke all on function public.fiche_course(text, text) from public, anon, authenticated;

create or replace function public.fiche_demande(commande text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  f        jsonb;
  b        text;
  retraits jsonb := '[]';
  premiere jsonb;
  frais    numeric := 0;
  paye     numeric := 0;
  reste    numeric := 0;
begin
  -- (3.74.0) Les boutiques dans l'ordre de la tournée, quand la commande en
  -- a une : le livreur les lit dans l'ordre où il doit passer.
  for b in select x.boutique_id from (
             select distinct l.boutique_id from public.commande_lignes l
              where l.commande_id = commande and l.etat <> 'annulee' and l.boutique_id is not null) x
            order by (select e.o from public.commandes c,
                        jsonb_array_elements(case when jsonb_typeof(c.livraison -> 'tournee') = 'array'
                                                  then c.livraison -> 'tournee' else '[]'::jsonb end)
                          with ordinality e(v, o)
                       where c.id = commande and e.v ->> 'boutique_id' = x.boutique_id) nulls last,
                     x.boutique_id loop
    f := public.fiche_course(commande, b);
    if f is null then continue; end if;
    premiere := coalesce(premiere, f);
    retraits := retraits || jsonb_build_array((f -> 'retrait') ||
      jsonb_build_object('boutique_id', b, 'a_encaisser', f -> 'a_encaisser'));
    frais := frais + coalesce((f ->> 'frais')::numeric, 0);
    paye  := paye  + coalesce((f ->> 'deja_paye')::numeric, 0);
    reste := reste + coalesce((f ->> 'a_encaisser')::numeric, 0);
  end loop;
  if premiere is null then return null; end if;
  -- (3.64.0) Au kilomètre, les frais sont ceux de la commande, pas la
  -- somme de chaque boutique : chaque fiche les porte déjà en entier.
  if premiere -> 'trajet' is not null and jsonb_typeof(premiere -> 'trajet') = 'object' then
    frais := coalesce((premiere ->> 'frais')::numeric, 0);
  end if;
  return jsonb_build_object(
    'numero', premiere -> 'numero',
    'groupee', jsonb_array_length(retraits) > 1,
    'retraits', retraits,
    'lieu_retrait', coalesce(premiere -> 'lieu_retrait', '""'::jsonb),
    'livraison', premiere -> 'livraison',
    'devise', premiere -> 'devise',
    'trajet', premiere -> 'trajet',
    'gain', premiere -> 'gain',
    'frais', frais, 'deja_paye', paye, 'a_encaisser', reste);
end $$;
revoke all on function public.fiche_demande(text) from public, anon, authenticated;

create or replace function public.texte_demande(f jsonb)
returns text
language plpgsql stable set search_path = public as $$
declare
  r     jsonb;
  texte text := '';
begin
  if coalesce((f ->> 'groupee')::boolean, false) then
    texte := 'Livraison groupée : ' || jsonb_array_length(f -> 'retraits') || ' boutiques.' || E'\n';
  end if;
  for r in select * from jsonb_array_elements(f -> 'retraits') loop
    texte := texte || 'Récupérer : ' || (r ->> 'boutique') ||
      coalesce(nullif(' — ' || (r ->> 'adresse'), ' — '), '') ||
      -- (3.70.0) Le numéro de la boutique, pour l'appeler s'il se perd.
      coalesce(' — Tél. boutique : +' || coalesce(nullif(r ->> 'indicatif', ''), '229') || ' ' ||
               nullif(r ->> 'tel', ''), '') || E'\n';
  end loop;
  -- (3.70.0) Ce que l'équipe a précisé en saisissant la commande.
  if coalesce(f ->> 'lieu_retrait', '') <> '' then
    texte := texte || 'Où récupérer : ' || (f ->> 'lieu_retrait') || E'\n';
  end if;
  -- (3.74.0) Le trajet à suivre, boutique après boutique, choisi par BIZZOO.
  if jsonb_typeof(f -> 'trajet' -> 'tournee') = 'array'
     and jsonb_array_length(f -> 'trajet' -> 'tournee') > 0 then
    texte := texte || 'Itinéraire : ' ||
      (select string_agg(coalesce(nullif(e ->> 'nom', ''), 'boutique'), ' → ' order by o)
         from jsonb_array_elements(f -> 'trajet' -> 'tournee') with ordinality x(e, o)) ||
      ' → client' || E'\n';
  end if;
  return texte ||
    'Livrer à : ' || coalesce(nullif(f -> 'livraison' ->> 'nom', ''), 'le client') ||
      coalesce(nullif(' — ' || (f -> 'livraison' ->> 'adresse'), ' — '), ' (adresse à demander)') || E'\n' ||
    'Destinataire : +' || (f -> 'livraison' ->> 'indicatif') || ' ' || (f -> 'livraison' ->> 'tel') || E'\n' ||
    -- (3.64.0) Le véhicule et la distance, puis ce qu'il y gagne.
    case when jsonb_typeof(f -> 'trajet') = 'object'
         then 'Véhicule : ' || case when f -> 'trajet' ->> 'vehicule' = 'tricycle' then 'tricycle' else 'moto' end ||
              -- (3.70.0) Sans distance (« Faire livrer » : frais saisis), pas
              -- de « — … km » : un NULL ici vidait TOUTE l'alerte.
              coalesce(' — ' || replace(f -> 'trajet' ->> 'distance_km', '.', ',') || ' km', '') || E'\n'
         else '' end ||
    'Frais de livraison : ' || public.montant_lisible((f ->> 'frais')::numeric, f ->> 'devise') || E'\n' ||
    case when (f ->> 'gain') is not null
         then 'Votre gain : ' || public.montant_lisible((f ->> 'gain')::numeric, f ->> 'devise') || E'\n' ||
              -- (3.74.0) Ce qui revient à BIZZOO, pour que tout soit clair.
              'Part BIZZOO : ' || public.montant_lisible(greatest(0, (f ->> 'frais')::numeric
                                   - (f ->> 'gain')::numeric), f ->> 'devise') || E'\n'
         else '' end ||
    'Déjà payé : ' || public.montant_lisible((f ->> 'deja_paye')::numeric, f ->> 'devise') || E'\n' ||
    case when (f ->> 'a_encaisser')::numeric > 0
         then 'À récupérer : ' || public.montant_lisible((f ->> 'a_encaisser')::numeric, f ->> 'devise')
         else 'Rien à récupérer : tout est payé.' end || E'\n' ||
    'Le premier qui touche « Commande reçue » prend la course.';
end $$;
revoke all on function public.texte_demande(jsonb) from public, anon, authenticated;

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
    when t = 'paiement' and c = 'livraison_supplement_boutique' then 'Tarif de livraison changé : supplément par boutique'
    when t = 'paiement' and c in ('livraison_latitude', 'livraison_longitude', 'livraison_adresse') then 'Point de départ des livraisons changé'
    when t = 'reglages' and c = 'compte_obligatoire' then
      case when ap = 'true' then 'Compte obligatoire pour commander' else 'Commande sans compte de nouveau permise' end
    when t = 'boutiques_reception' and c = 'tel' then 'Numéro de réception des reversements changé'
    when t = 'boutiques_reception' and c = 'reseau' then 'Réseau de réception des reversements changé'
    when t = 'boutiques_reception' and c = 'titulaire' then 'Titulaire du numéro de réception changé'
    else 'Réglage « ' || c || ' » changé' end;
$$;
revoke all on function public.rh_audit_libelle(text, text, text, text) from public, anon;
grant execute on function public.rh_audit_libelle(text, text, text, text) to authenticated, service_role;

create or replace function public.creer_commande(
  client jsonb, articles jsonb, code text default '',
  avec_acompte boolean default false, avec_frais boolean default false,
  destination jsonb default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  -- (3.64.0) La livraison au kilomètre : en service dès que le point
  -- BIZZOO est réglé.
  au_km    boolean := public.livraison_active();
  devis    jsonb;
  frais_km bigint := 0;
  nouvelle text := 'cmd_' || replace(gen_random_uuid()::text, '-', '');
  article  jsonb;
  qte      int;
  p        public.produits%rowtype;
  devises  text[];
  sortie   jsonb;
  moi      uuid := auth.uid();
  equipe   boolean := false;   -- connecté, mais pas avec un compte client
  sous_total bigint;
  marge    bigint;
  verdict  jsonb;
  manque   record;
  taux     int;
  les_parts jsonb;
  manquant  bigint;
  -- (3.68.0) Les frais SAISIS par l'équipe pour une commande prise sur
  -- WhatsApp (« faire_livrer ») : ils remplacent le calcul à la distance.
  -- Les deux drapeaux ne s'attrapent pas depuis PostgREST.
  saisis   bigint := case when coalesce(current_setting('bizzoo.hors_appli', true), '') = 'oui'
                          then nullif(current_setting('bizzoo.frais_saisis', true), '')::bigint end;
  vehic    text;
begin
  -- Des frais saisis valent une livraison « au kilomètre » sans kilomètre :
  -- un seul frais pour la commande, un seul livreur, payé en ligne — et le
  -- livreur en touche sa part comme d'habitude.
  if saisis is not null then au_km := true; end if;
  if articles is null or jsonb_typeof(articles) <> 'array'
     or jsonb_array_length(articles) = 0 then
    raise exception 'Votre panier est vide.';
  end if;
  if jsonb_array_length(articles) > 40 then
    raise exception 'Un panier ne peut pas dépasser 40 articles différents.';
  end if;
  if coalesce(trim(client ->> 'tel'), '') = '' then
    raise exception 'Un numéro de téléphone est nécessaire pour vous joindre.';
  end if;
  -- (3.64.0) LA POSITION DU CLIENT EST OBLIGATOIRE quand la livraison se
  -- compte au kilomètre : sans elle, pas de distance, donc pas de frais.
  -- Une application d'avant ne l'envoie pas — on lui dit quoi faire.
  if au_km and saisis is null then
    if destination is null or jsonb_typeof(destination) <> 'object'
       or (destination ->> 'latitude') is null or (destination ->> 'longitude') is null then
      if coalesce(avec_frais, false) and destination is null then
        raise exception 'Mettez BIZZOO à jour pour commander : les frais de livraison se calculent désormais selon votre position.'
          using errcode = 'P0001';
      end if;
      raise exception 'Indiquez où livrer : touchez « Utiliser ma position ».' using errcode = 'P0001';
    end if;
  end if;

  -- Un compte de l'équipe ne passe pas commande pour lui-même : il agirait
  -- avec les droits d'une boutique sur une commande qui lui appartient.
  --
  -- (3.63.0) UN COMPTE SANS FICHE N'EST PAS UN COMPTE D'ÉQUIPE. Avant,
  -- tout compte connecté sans ligne « clients » était ramené à
  -- « personne » : la commande naissait sans compte, et son auteur ne la
  -- retrouvait nulle part — ni étapes, ni livreur, ni « J'ai bien
  -- reçu ». La fiche manque pourtant pour de bonnes raisons (un compte
  -- créé hors de l'application, une écriture retardée) : on la pose ici,
  -- avec ce que le client vient de donner, et la commande reste la
  -- sienne. Seul un VRAI compte d'équipe est écarté — une fiche d'équipe
  -- EN ATTENTE ne vaut aucun droit, et « compte_unique » l'efface en
  -- posant la fiche client, comme le fait l'application.
  if moi is not null and not exists (select 1 from public.clients c where c.id = moi) then
    -- (« eq », pas « p » : « p » est déjà la variable de la boucle des
    -- produits, et PostgreSQL ne saurait pas lequel des deux on désigne.)
    if exists (select 1 from public.profils eq
                where eq.id = moi and (eq.actif or eq.role <> 'moderateur')) then
      moi    := null;
      equipe := true;
    else
      begin
        insert into public.clients (id, nom, tel, indicatif, adresse)
        values (moi,
                left(coalesce(trim(client ->> 'nom'), ''), 120),
                left(regexp_replace(coalesce(client ->> 'tel', ''), '\D', '', 'g'), 20),
                left(coalesce(nullif(trim(client ->> 'indicatif'), ''), '229'), 6),
                left(coalesce(trim(client ->> 'adresse'), ''), 300))
        on conflict (id) do nothing;
      exception when others then
        -- Un verrou a refusé la fiche (un compte d'équipe apparu entre-temps,
        -- par exemple) : la commande part sans compte, comme avant — mais
        -- elle part.
        moi    := null;
        equipe := true;
      end;
    end if;
  end if;

  -- ---------- Le compte, quand l'enseigne l'exige ----------
  -- Tant que l'interrupteur est éteint, rien ne change : on commande sans
  -- compte, comme depuis le premier jour. Allumé, c'est ICI que la porte
  -- se ferme — dans la base, pas à l'écran. Un écran qui cache un bouton
  -- ne ferme rien : il suffit d'appeler la fonction directement.
  --
  -- Deux refus, parce que ce ne sont pas deux mêmes situations. Le
  -- visiteur n'a pas de compte : on lui dit d'en ouvrir un. Le vendeur en
  -- a un — mais c'est un compte de l'équipe, et on vient de le ramener à
  -- « personne » deux lignes plus haut. Lui répondre « connectez-vous »
  -- alors qu'il EST connecté lui ferait chercher longtemps.
  -- (3.68.0) Une commande prise sur WhatsApp, que l'équipe saisit pour le
  -- client (« faire_livrer ») : le client n'est pas là pour se connecter.
  -- Le drapeau ne s'attrape pas depuis PostgREST — seule « faire_livrer »,
  -- qui vérifie qui l'appelle, le pose.
  if moi is null and public.compte_exige()
     and coalesce(current_setting('bizzoo.hors_appli', true), '') <> 'oui' then
    if equipe then
      raise exception 'Ce compte est un compte de l''équipe BIZZOO, pas un compte client. Pour commander, ouvrez un compte client et connectez-vous avec.';
    end if;
    raise exception 'Il faut un compte BIZZOO pour commander. Sa création prend une minute, et c''est lui qui vous rendra cette commande depuis n''importe quel téléphone.';
  end if;

  perform set_config('bizzoo.interne', 'oui', true);

  insert into public.commandes
    (id, client_id, client_nom, client_tel, client_indicatif, client_adresse, note)
  values (
    nouvelle,
    moi,
    left(coalesce(trim(client ->> 'nom'), ''), 120),
    left(regexp_replace(coalesce(client ->> 'tel', ''), '\D', '', 'g'), 20),
    left(coalesce(nullif(trim(client ->> 'indicatif'), ''), '229'), 6),
    left(coalesce(trim(client ->> 'adresse'), ''), 300),
    left(coalesce(trim(client ->> 'note'), ''), 500));

  -- ---------- Les frais de livraison ----------
  -- AVANT les lignes : chaque ligne posée recalcule le total, qui les
  -- compte. Le montant est celui des réglages du jour, figé sur la
  -- commande.
  --
  -- UNE APPLICATION D'AVANT NE LES DEMANDE PAS, et n'en paie donc pas :
  -- elle ne saurait pas les montrer, et le client paierait un montant
  -- qu'on ne lui a jamais annoncé.
  -- (Le drapeau « interne » est déjà posé pour l'insertion, plus haut.)
  -- (3.59.0) Ils se posent désormais APRÈS les lignes, boutique par
  -- boutique : voir « Les conditions de chaque boutique », plus bas.

  for article in select * from jsonb_array_elements(articles) loop
    qte := greatest(1, least(99, coalesce((article ->> 'quantite')::int, 1)));
    select * into p from public.produits where id = article ->> 'produit_id';
    if not found then
      raise exception 'Un des produits de votre panier n''existe plus.';
    end if;
    -- (3.59.0) Un produit masqué ne se commande plus.
    if coalesce(p.masque, false) then
      raise exception '« % » n''est plus disponible : retirez-le du panier.', p.nom;
    end if;
    -- (3.80.0) Ni un produit que son vendeur a mis « Non disponible ».
    if coalesce((to_jsonb(p) ->> 'en_pause')::boolean, false) then
      raise exception '« % » n''est pas disponible pour le moment : retirez-le du panier pour commander le reste.', p.nom
        using errcode = 'P0001';
    end if;
    if coalesce(p.stock, 0) <= 0 and not coalesce(p.sur_commande, false)
       and (p.appro_le is null or p.appro_le < current_date) then
      raise exception '« % » n''est plus disponible : retirez-le du panier.', p.nom;
    end if;
    -- UNE BOUTIQUE FERMÉE NE REÇOIT PAS DE COMMANDE (3.59.0) : fermée par
    -- son interrupteur, ou en dehors de ses heures d'ouverture.
    if exists (select 1 from public.boutiques b
                where b.id = p.boutique_id
                  and (not b.actif or not public.boutique_ouverte(b.ouvertures))) then
      raise exception 'La boutique « % » est fermée en ce moment : « % » se commandera à sa réouverture.',
        (select b.nom from public.boutiques b where b.id = p.boutique_id), p.nom
        using errcode = 'P0001';
    end if;
    -- (3.78.0) NI UN VENDEUR FERMÉ : dans une boutique à vendeurs multiples,
    -- chaque vendeur a ses jours et heures.
    if public.point_retrait_produit(p.id) like 'v:%'
       and not public.vendeur_ouvert(substr(public.point_retrait_produit(p.id), 3)::uuid) then
      raise exception '« % » est vendu par « % », fermé en ce moment : il se commandera à sa réouverture.',
        p.nom, coalesce((select coalesce(nullif(btrim(vl.nom), ''), nullif(btrim(v.nom), ''), 'son vendeur')
                           from public.profils v left join public.vendeurs_lieux vl on vl.vendeur_id = v.id
                          where v.id::text = substr(public.point_retrait_produit(p.id), 3)), 'son vendeur')
        using errcode = 'P0001';
    end if;
    devises := devises || coalesce(nullif((
      select b.devise from public.boutiques b where b.id = p.boutique_id), ''), 'FCFA');
    -- (3.80.0) Ses accompagnements choisis : la base les relit et en fait le
    -- prix (« lignes_zz_accompagnements »), le panier n'en dit que les
    -- quantités.
    insert into public.commande_lignes (id, commande_id, produit_id, quantite, accompagnements)
    values ('lig_' || replace(gen_random_uuid()::text, '-', ''), nouvelle, p.id, qte,
            case when jsonb_typeof(article -> 'accompagnements') = 'array'
                 then article -> 'accompagnements' else '[]'::jsonb end);
  end loop;

  -- LA QUANTITÉ TIENT DANS LE STOCK. Refuser un produit à zéro ne
  -- suffisait pas : dix pièces demandées quand il en restait trois
  -- passaient, et la boutique découvrait après le paiement qu'elle ne
  -- pourrait pas servir. On compte PAR PRODUIT, pas par ligne : deux
  -- lignes du même article ne font pas deux stocks. Un produit « sur
  -- commande » ou en approvisionnement n'a pas de plafond — la boutique
  -- le fait venir, c'est ce qu'elle annonce.
  --
  -- Ce contrôle ne RÉSERVE rien : entre la commande et le paiement, un
  -- autre client peut prendre les dernières pièces. C'est le paiement
  -- qui décompte, et il sait quoi faire s'il n'en reste plus assez
  -- (« commande_stock », plus bas).
  -- « pr » et non « p » : « p » est déjà la variable de la boucle, et
  -- PostgreSQL ne saurait pas lequel des deux on désigne.
  select pr.nom, greatest(coalesce(pr.stock, 0), 0) as reste
    into manque
    from public.commande_lignes l
    join public.produits pr on pr.id = l.produit_id
   where l.commande_id = nouvelle
     and not coalesce(pr.sur_commande, false)
     and (pr.appro_le is null or pr.appro_le < current_date)
   group by pr.id, pr.nom, pr.stock
  having sum(l.quantite) > greatest(coalesce(pr.stock, 0), 0)
   order by pr.nom
   limit 1;
  if found then
    raise exception 'Plus que % en stock pour « % » : réduisez la quantité dans votre panier.',
      manque.reste, manque.nom;
  end if;

  if (select count(distinct d) from unnest(devises) d) > 1 then
    raise exception 'Ces produits ne se paient pas dans la même monnaie : commandez boutique par boutique.';
  end if;
  update public.commandes set devise = coalesce(devises[1], 'FCFA') where id = nouvelle;

  -- ---------- Le code promo ----------
  -- APRÈS les lignes, et c'est obligatoire : la remise est bornée par la
  -- marge de l'enseigne, qui ne se connaît qu'une fois les prix et les
  -- prix BIZZOO figés sur les lignes. La calculer avant reviendrait à la
  -- deviner.
  --
  -- Un code refusé ne fait PAS échouer la commande : le panier est bon,
  -- c'est le code qui ne vaut rien. Refuser la vente parce qu'une
  -- promotion a expiré serait perdre un client pour une ristourne.
  if coalesce(trim(code), '') <> '' then
    select coalesce(sum(l.prix * l.quantite), 0),
           coalesce(sum(greatest(0, l.prix - l.prix_bizzoo) * l.quantite), 0)
      into sous_total, marge
      from public.commande_lignes l where l.commande_id = nouvelle;

    verdict := public.remise_du_code(code, sous_total, marge, moi,
      left(regexp_replace(coalesce(client ->> 'tel', ''), '\D', '', 'g'), 20));

    if (verdict ->> 'ok')::boolean then
      perform set_config('bizzoo.interne', 'oui', true);
      update public.commandes
         set code_promo = public.code_normalise(code),
             remise = (verdict ->> 'remise')::bigint
       where id = nouvelle;
      perform set_config('bizzoo.interne', '', true);
      -- Le total suit la remise. Même fonction que le déclencheur des
      -- lignes : une seule règle, un seul endroit.
      perform public.commande_total(nouvelle);
    end if;
  end if;

  -- ---------- L'acompte ----------
  -- APRÈS le code promo : l'acompte se prend sur ce que le client doit
  -- vraiment, remise déduite. Le taux est celui du jour, figé sur la
  -- commande.
  --
  -- UNE APPLICATION D'AVANT NE DEMANDE RIEN. Elle fait payer le total et
  -- dit « Payée » une fois le versement reçu : sa commande se règle donc
  -- en entier, comme elle l'annonce au client. Lui faire payer un acompte
  -- sans qu'elle sache le dire laisserait croire au client qu'il ne doit
  -- plus rien, et le livreur arriverait avec une somme à réclamer.
  --
  -- 100 francs au moins, l'encaissement minimum chez FeexPay, et jamais
  -- plus que le total.
  -- ---------- Les conditions de chaque boutique (3.59.0) ----------
  -- CHAQUE BOUTIQUE A SES FRAIS ET SON ACOMPTE. Sa part, c'est ce que
  -- valent ses articles, remise déduite au prorata, plus ses frais ;
  -- elle se paie en entier à la commande (« total ») ou par son taux
  -- d'acompte — le reste à la livraison, à son livreur.
  --
  -- UNE APPLICATION D'AVANT ne demande ni frais ni acompte : elle fait
  -- tout payer, et n'a pas de frais à annoncer. On ne change rien pour
  -- elle.
  -- ---------- La livraison au kilomètre (3.64.0) ----------
  -- UN SEUL FRAIS POUR LA COMMANDE, du point BIZZOO jusqu'au client, au
  -- tarif du véhicule : le tricycle dès qu'UN produit l'exige. Les frais
  -- de chaque boutique ne comptent plus. Ils se paient EN LIGNE, avec
  -- l'acompte : c'est BIZZOO qui les détient, et qui en doit sa part au
  -- livreur (« gains_livreurs »).
  if au_km then
    vehic := case when exists (select 1 from public.commande_lignes l
                                 join public.produits pr on pr.id = l.produit_id
                                where l.commande_id = nouvelle and pr.vehicule = 'tricycle')
                  then 'tricycle' else 'moto' end;
    if saisis is not null then
      -- (3.68.0) Les frais décidés par qui a pris la commande ; la position,
      -- si on l'a, pour que le livreur trouve le client.
      devis := jsonb_build_object('vehicule', vehic, 'distance_km', null, 'frais', greatest(0, saisis),
                 'saisie', true) ||
               case when destination is not null and jsonb_typeof(destination) = 'object'
                         and (destination ->> 'latitude') is not null and (destination ->> 'longitude') is not null
                    then jsonb_build_object('destination', jsonb_build_object(
                           'latitude', round((destination ->> 'latitude')::numeric, 6),
                           'longitude', round((destination ->> 'longitude')::numeric, 6)))
                    else '{}'::jsonb end;
    else
      -- (3.74.0) La tournée : de boutique en boutique, puis au client, dans
      -- l'ordre le plus court, plus le supplément de chaque boutique.
      -- (3.78.0) Un arrêt par lieu de retrait : chaque vendeur d'une
      -- boutique multivendeur, chaque autre boutique.
      devis := public.devis_tournee(
        public.points_commande(nouvelle),
        (destination ->> 'latitude')::double precision,
        (destination ->> 'longitude')::double precision, vehic);
    end if;
    frais_km := coalesce((devis ->> 'frais')::bigint, 0);
    perform set_config('bizzoo.interne', 'oui', true);
    update public.commandes set frais_livraison = frais_km, livraison = devis where id = nouvelle;
    perform public.commande_total(nouvelle);
    perform set_config('bizzoo.interne', '', true);
  end if;

  if au_km or coalesce(avec_acompte, false) or coalesce(avec_frais, false) then
    perform set_config('bizzoo.interne', 'oui', true);
    if coalesce(avec_frais, false) and not au_km then
      update public.commandes
         set frais_livraison = coalesce((
               select sum(greatest(0, b.frais_livraison))
                 from public.boutiques b
                where b.id in (select l.boutique_id from public.commande_lignes l
                                where l.commande_id = nouvelle)), 0)
       where id = nouvelle;
      perform public.commande_total(nouvelle);
      perform set_config('bizzoo.interne', 'oui', true);
    end if;
    with brut as (
      select l.boutique_id as bou, sum(l.prix * l.quantite)::numeric as montant
        from public.commande_lignes l
       where l.commande_id = nouvelle
       group by l.boutique_id
    ), tout as (
      select sum(montant) as s from brut
    ), chacune as (
      select br.bou,
             -- Au kilomètre, la part d'une boutique n'a plus de frais : ceux
             -- de la commande s'ajoutent à part, plus bas.
             case when coalesce(avec_frais, false) and not au_km
                  then greatest(0, b.frais_livraison) else 0 end as frais,
             case when coalesce(avec_acompte, false) and b.mode_paiement = 'acompte'
                  then b.taux_acompte else 100 end as taux,
             greatest(0, round(br.montant - coalesce(c.remise, 0) * br.montant / nullif(t.s, 0))) as net
        from brut br
        join public.boutiques b on b.id = br.bou
        cross join tout t
        cross join (select remise from public.commandes where id = nouvelle) c
    )
    select jsonb_object_agg(x.bou, jsonb_build_object(
             'frais', x.frais, 'taux', x.taux, 'du', x.net + x.frais,
             'acompte', least(x.net + x.frais, ceil((x.net + x.frais) * x.taux / 100.0)::bigint)))
      into les_parts
      from chacune x;

    -- 100 francs au moins en ligne, l'encaissement minimum chez FeexPay :
    -- le manque va à la plus grosse part.
    select greatest(0, least(c.total, 100) - coalesce((
             select sum((v ->> 'acompte')::bigint) from jsonb_each(les_parts) e(k, v)), 0) - frais_km)
      into manquant
      from public.commandes c where c.id = nouvelle;
    if manquant > 0 and les_parts is not null then
      select jsonb_set(les_parts, array[k, 'acompte'],
               to_jsonb(least((v ->> 'du')::bigint, (v ->> 'acompte')::bigint + manquant)))
        into les_parts
        from jsonb_each(les_parts) e(k, v)
       order by (v ->> 'du')::bigint desc limit 1;
    end if;

    -- (3.64.0) Au kilomètre, l'acompte, c'est celui des boutiques PLUS les
    -- frais de livraison, payés en entier en ligne.
    update public.commandes c
       set parts = les_parts,
           acompte = least(c.total, coalesce((
                       select sum((v ->> 'acompte')::bigint) from jsonb_each(les_parts) e(k, v)), c.total)
                       + frais_km),
           -- Le taux affiché : ce que représente l'acompte du total.
           taux_acompte = case when c.total <= 0 then 100
                               else least(100, greatest(1, round(100.0 * least(c.total, coalesce((
                                 select sum((v ->> 'acompte')::bigint) from jsonb_each(les_parts) e(k, v)),
                                 c.total) + frais_km) / c.total)))::int end
     where c.id = nouvelle;
    perform set_config('bizzoo.interne', '', true);
  else
    perform set_config('bizzoo.interne', 'oui', true);
    update public.commandes c
       set taux_acompte = 100,
           acompte = c.total
     where c.id = nouvelle;
    perform set_config('bizzoo.interne', '', true);
  end if;

  select jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'total', c.total, 'devise', c.devise,
    'etat', c.etat,
    /* Ce que le code a retiré, et lequel. Le récapitulatif doit pouvoir
       le dire : un client qui a tapé un code et ne le voit nulle part
       croit qu'il n'a pas été pris. */
    'code_promo', c.code_promo, 'remise', c.remise,
    /* Les frais de livraison, à part : le récapitulatif les montre sur
       leur propre ligne. */
    'frais_livraison', c.frais_livraison,
    /* (3.64.0) Le véhicule, la distance, les kilomètres facturés. */
    'livraison', c.livraison,
    /* Ce qui se paie maintenant, et ce qui restera pour la livraison. */
    'taux_acompte', c.taux_acompte, 'acompte', c.acompte,
    'reste', greatest(0, c.total - c.acompte),
    'parts', c.parts,
    'boutiques', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', g.boutique_id,
               'nom', coalesce((select b.nom from public.boutiques b where b.id = g.boutique_id), ''),
               'whatsapp', coalesce((select b.whatsapp from public.boutiques b where b.id = g.boutique_id), ''),
               'indicatif', coalesce((select b.indicatif from public.boutiques b where b.id = g.boutique_id), '229'),
               'montant', g.montant,
               /* Ce que CETTE boutique encaissera à la livraison. */
               'a_encaisser', coalesce((select r.a_encaisser
                                          from public.restes_par_boutique(c.id) r
                                         where r.boutique_id is not distinct from g.boutique_id), 0),
               'lignes', g.lignes) order by g.montant desc)
        from (select l.boutique_id,
                     sum(l.prix * l.quantite) as montant,
                     jsonb_agg(jsonb_build_object('nom', l.nom, 'code', l.code,
                       'reference', l.reference, 'prix', l.prix,
                       /* L'identifiant du produit voyage avec la ligne :
                          c'est par lui que le SAV désignera l'article
                          qui pose problème. Le prix BIZZOO, lui, ne sort
                          toujours pas. */
                       'produit_id', l.produit_id,
                       'quantite', l.quantite) order by l.nom) as lignes
                from public.commande_lignes l
               where l.commande_id = c.id
               group by l.boutique_id) g), '[]'::jsonb))
    into sortie
    from public.commandes c where c.id = nouvelle;
  return sortie;
end $$;
revoke all on function public.creer_commande(jsonb, jsonb, text, boolean, boolean, jsonb) from public;
grant execute on function public.creer_commande(jsonb, jsonb, text, boolean, boolean, jsonb) to anon, authenticated;
