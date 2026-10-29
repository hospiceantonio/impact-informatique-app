-- ---------- Le socle de la livraison au kilomètre (3.64.0) ----------
-- Répété dans chaque fichier qui s'en sert : collé seul, il doit se suffire.
-- Les colonnes de la livraison au kilomètre (3.64.0).
alter table public.produits add column if not exists vehicule text not null default 'moto';
alter table public.produits drop constraint if exists produits_vehicule;
alter table public.produits add constraint produits_vehicule check (vehicule in ('moto', 'tricycle'));
alter table public.profils add column if not exists vehicule text not null default 'moto';
alter table public.profils drop constraint if exists profils_vehicule;
alter table public.profils add constraint profils_vehicule check (vehicule in ('moto', 'tricycle'));
alter table public.commandes add column if not exists livraison jsonb;
alter table public.paiement add column if not exists livraison_latitude double precision;
alter table public.paiement add column if not exists livraison_longitude double precision;
alter table public.paiement add column if not exists livraison_adresse text not null default '';
alter table public.paiement add column if not exists livraison_rayon_km int not null default 10;
alter table public.paiement add column if not exists livraison_coef numeric(4,2) not null default 1.3;
alter table public.paiement add column if not exists moto_forfait int not null default 1000;
alter table public.paiement add column if not exists moto_prix_km int not null default 100;
alter table public.paiement add column if not exists tricycle_forfait int not null default 4000;
alter table public.paiement add column if not exists tricycle_prix_km int not null default 500;
alter table public.paiement add column if not exists taux_livreur int not null default 80;
alter table public.paiement drop constraint if exists paiement_livraison_bornes;
alter table public.paiement add constraint paiement_livraison_bornes check (
  (livraison_latitude is null) = (livraison_longitude is null)
  and (livraison_latitude is null or livraison_latitude between -90 and 90)
  and (livraison_longitude is null or livraison_longitude between -180 and 180)
  and livraison_rayon_km between 0 and 500
  and livraison_coef between 1 and 3
  and moto_forfait between 0 and 1000000 and moto_prix_km between 0 and 100000
  and tricycle_forfait between 0 and 1000000 and tricycle_prix_km between 0 and 100000
  and taux_livreur between 0 and 100
  and length(livraison_adresse) <= 200);

create table if not exists public.gains_livreurs (
  commande_id text primary key references public.commandes(id) on delete cascade,
  livreur_id  uuid references public.profils(id) on delete set null,
  frais       bigint not null default 0,
  taux        int not null default 80,
  montant     bigint not null default 0 check (montant >= 0),
  credite_le  timestamptz not null default now()
);
create index if not exists gains_livreur on public.gains_livreurs(livreur_id, credite_le desc);
alter table public.gains_livreurs enable row level security;
revoke all on public.gains_livreurs from anon, authenticated;
-- (3.66.0) UNE LIGNE PAR LIVREUR, et non plus par commande : une commande à
-- l'ancien tarif (frais par boutique) a parfois un livreur par boutique,
-- et chacun touche la part des boutiques qu'il a livrées.
alter table public.gains_livreurs add column if not exists id bigserial;
do $$
begin
  if exists (select 1 from pg_constraint
              where conname = 'gains_livreurs_pkey' and conrelid = 'public.gains_livreurs'::regclass
                and pg_get_constraintdef(oid) = 'PRIMARY KEY (commande_id)') then
    alter table public.gains_livreurs drop constraint gains_livreurs_pkey;
    alter table public.gains_livreurs add constraint gains_livreurs_pkey primary key (id);
  end if;
end $$;
create unique index if not exists gains_livreurs_une_fois on public.gains_livreurs(commande_id, livreur_id);
revoke all on sequence public.gains_livreurs_id_seq from anon, authenticated;

-- (3.70.0) Le devis plus bas lit la distance par la route : la grille
-- et le cache qu'il emprunte, recopiés tels quels.
create or replace function public.grille_route(x double precision) returns numeric
language sql immutable as $$
  select (round((x * 2000)::numeric) / 2000)::numeric(9,4);
$$;

create table if not exists public.distances_route (
  o_lat      numeric(9,4) not null,
  o_lng      numeric(9,4) not null,
  d_lat      numeric(9,4) not null,
  d_lng      numeric(9,4) not null,
  distance_m int not null check (distance_m > 0 and distance_m <= 1000000),
  cree_le    timestamptz not null default now(),
  primary key (o_lat, o_lng, d_lat, d_lng)
);
create index if not exists distances_route_jour on public.distances_route(cree_le);
alter table public.distances_route enable row level security;
revoke all on public.distances_route from public, anon, authenticated;

create or replace function public.livraison_active() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.livraison_latitude is not null and p.livraison_longitude is not null
                     from public.paiement p where p.id = 1), false);
$$;
revoke all on function public.livraison_active() from public;
grant execute on function public.livraison_active() to anon, authenticated;

create or replace function public.devis_livraison(
  latitude double precision, longitude double precision, vehicule text default 'moto')
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r     public.paiement%rowtype;
  v     text := case when vehicule = 'tricycle' then 'tricycle' else 'moto' end;
  dlat  double precision;
  dlng  double precision;
  a     double precision;
  dist  numeric;
  km    int;
  forf  int;
  prix  int;
  route_m int;
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
  -- (3.70.0) PAR LA ROUTE, quand la fonction serveur « distance-route » l'a
  -- demandée à Google pour ce client (à 50 m près) : le vrai trajet.
  select x.distance_m into route_m from public.distances_route x
   where x.o_lat = public.grille_route(r.livraison_latitude)
     and x.o_lng = public.grille_route(r.livraison_longitude)
     and x.d_lat = public.grille_route(latitude)
     and x.d_lng = public.grille_route(longitude);
  if route_m is not null then
    dist := round(route_m / 1000.0, 3);
  else
    -- Sinon, à vol d'oiseau (formule de haversine, rayon terrestre de
    -- 6 371 km), multipliée par le coefficient de la route ; au mètre près.
    dlat := radians(latitude - r.livraison_latitude);
    dlng := radians(longitude - r.livraison_longitude);
    a := sin(dlat / 2) ^ 2
         + cos(radians(r.livraison_latitude)) * cos(radians(latitude)) * sin(dlng / 2) ^ 2;
    dist := round((2 * 6371 * asin(least(1, sqrt(a))) * r.livraison_coef)::numeric, 3);
  end if;
  -- Le kilomètre ENTAMÉ compte : 10,001 km facturent un kilomètre de plus.
  km := case when dist > r.livraison_rayon_km then ceil(dist - r.livraison_rayon_km)::int else 0 end;
  forf := case when v = 'tricycle' then r.tricycle_forfait else r.moto_forfait end;
  prix := case when v = 'tricycle' then r.tricycle_prix_km else r.moto_prix_km end;
  return jsonb_build_object(
    'vehicule', v,
    'distance_km', round(dist, 1),
    -- (3.70.0) « route » : le trajet réel (Google) ; « vol_oiseau » : estimé.
    'calcul', case when route_m is not null then 'route' else 'vol_oiseau' end,
    'rayon_km', r.livraison_rayon_km,
    'km_factures', km,
    'forfait', forf,
    'prix_km', prix,
    'frais', forf + km * prix,
    'point', jsonb_build_object('latitude', r.livraison_latitude, 'longitude', r.livraison_longitude),
    'destination', jsonb_build_object('latitude', round(latitude::numeric, 6),
                                      'longitude', round(longitude::numeric, 6)));
end $$;
revoke all on function public.devis_livraison(double precision, double precision, text) from public;
grant execute on function public.devis_livraison(double precision, double precision, text) to anon, authenticated;

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


-- Migration additive ; aucune suppression exécutée lors de l’installation.
BEGIN;
-- Les frais de livraison (3.58.0) : lus par les fonctions plus bas.
alter table public.commandes add column if not exists frais_livraison bigint not null default 0;
alter table public.paiement add column if not exists frais_livraison int not null default 1000;

-- Les colonnes que les fonctions plus bas lisent (3.59.0).
alter table public.commandes add column if not exists parts jsonb;

create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;
alter table public.commandes add column if not exists client_id uuid;
alter table public.commandes add column if not exists fournisseur_ref text not null default '';
alter table public.commandes add column if not exists revendeur boolean not null default false;
alter table public.commandes add column if not exists tentative_le timestamptz;
alter table public.commandes add column if not exists transaction_annoncee text not null default '';
alter table public.commandes add column if not exists compte_supprime boolean not null default false;
alter table public.commandes add column if not exists taux_acompte int;
alter table public.commandes add column if not exists acompte int;
alter table public.commandes add column if not exists verse int;

create or replace function public.client_commandes(client uuid)
returns table (
  id text, numero text, cree_le timestamptz, paye_le timestamptz,
  etat text, total bigint, revendeur boolean,
  articles bigint, boutiques text, rattachee boolean)
language plpgsql stable security definer set search_path = public as $$
declare mien public.clients%rowtype;
begin
  if not public.est_super() or client is null then return; end if;
  select * into mien from public.clients where clients.id = client;
  if not found then return; end if;
  return query
    select v.id, v.numero, v.cree_le, v.paye_le, v.etat,
           v.total::bigint, v.revendeur,
           count(l.id)::bigint,
           coalesce(string_agg(distinct b.nom, ', '), '')::text,
           v.client_id is not null
      from public.commandes v
      left join public.commande_lignes l on l.commande_id = v.id
      left join public.boutiques b on b.id = l.boutique_id
     where v.client_id = client
        or (v.client_id is null
            and not v.compte_supprime
            and mien.tel_verifie and coalesce(mien.tel, '') <> ''
            and v.client_tel = mien.tel
            and v.cree_le > now() - interval '18 months')
     group by v.id, v.numero, v.cree_le, v.paye_le, v.etat,
              v.total, v.revendeur, v.client_id
     order by v.cree_le desc
     limit 100;
end $$;

create or replace function public.commande_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- La base écrit pour elle-même : le total qui suit ses lignes, la
  -- monnaie posée à la création. Ces drapeaux n'existent que le temps de
  -- l'appel — ils ne s'attrapent pas depuis PostgREST.
  if coalesce(current_setting('bizzoo.interne', true), '') = 'oui' then
    return new;
  end if;
  if coalesce(current_setting('bizzoo.paiement', true), '') = 'oui' then
    return new;   -- l'agrégateur, ou l'enseigne qui se porte garante
  end if;

  if not public.est_equipe() then
    raise exception 'Seule l''équipe suit une commande';
  end if;

  -- L'équipe suit la commande, elle ne la réécrit pas.
  if new.total is distinct from old.total
  or new.client_nom is distinct from old.client_nom
  or new.client_tel is distinct from old.client_tel
  or new.client_adresse is distinct from old.client_adresse
  -- À qui appartient cette commande. La réattribuer, c'est offrir à
  -- quelqu'un l'historique, les avis et le SAV d'un autre.
  or new.client_id is distinct from old.client_id
  or new.compte_supprime is distinct from old.compte_supprime
  -- Et sous quel régime de prix elle est partie : la basculer après
  -- coup, c'est réécrire ce que la boutique a touché.
  or new.revendeur is distinct from old.revendeur
  or new.transaction_id is distinct from old.transaction_id
  or new.transaction_annoncee is distinct from old.transaction_annoncee
  -- La référence de l'agrégateur est ce avec quoi notre serveur ira lui
  -- demander si le versement a abouti. La laisser réécrire, c'est
  -- laisser désigner quel versement répond pour quelle commande.
  or new.fournisseur_ref is distinct from old.fournisseur_ref
  or new.tentative_le is distinct from old.tentative_le
  or new.confirme_par is distinct from old.confirme_par
  -- L'acompte et ce qui a été versé. Les réécrire, c'est changer ce que
  -- le livreur va réclamer à la porte du client.
  or new.taux_acompte is distinct from old.taux_acompte
  or new.acompte is distinct from old.acompte
  or new.parts is distinct from old.parts
  or new.verse is distinct from old.verse
  or new.frais_livraison is distinct from old.frais_livraison
  -- (3.64.0) La distance, le véhicule et le tarif : ce que le livreur
  -- touchera.
  or new.livraison is distinct from old.livraison
  or new.paye_le is distinct from old.paye_le then
    raise exception 'Le montant et le paiement d''une commande ne se réécrivent pas';
  end if;

  -- Et surtout : elle n'invente pas un encaissement.
  if new.etat = 'payee' and old.etat <> 'payee' then
    raise exception 'Seul l''agrégateur de paiement déclare un paiement';
  end if;
  if old.etat = 'payee' and new.etat not in ('payee', 'annulee') then
    raise exception 'Une commande payée ne peut être qu''annulée';
  end if;
  return new;
end $$;

-- ---------- Ce qui reste à payer à la livraison ----------
-- Recopié de schema.sql, avec les colonnes qu'il lit : les fonctions
-- plus bas s'en servent depuis l'acompte à la commande (« acompte.sql »).
alter table public.commandes add column if not exists taux_acompte int;
alter table public.commandes add column if not exists acompte int;
alter table public.commandes add column if not exists verse int;
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

create or replace function public.suivre_commande(cible text, tel text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.commandes%rowtype;
begin
  select * into c from public.commandes
   where id = cible
     and not compte_supprime
     and client_tel = regexp_replace(coalesce(tel, ''), '\D', '', 'g');
  if not found then return null; end if;
  return jsonb_build_object(
    'numero', c.numero, 'etat', c.etat, 'total', c.total, 'devise', c.devise,
    'paye_le', c.paye_le, 'remarque', c.remarque,
    'frais_livraison', c.frais_livraison,
    -- (3.64.0) Le véhicule et la distance de la livraison.
    'livraison', c.livraison,
    -- L'acompte, ce qui a été versé, et ce qui reste à payer à la
    -- livraison, boutique par boutique. Une commande d'avant l'acompte
    -- se payait en entier : son acompte est son total.
    'taux_acompte', coalesce(c.taux_acompte, 100),
    'acompte', coalesce(c.acompte, c.total),
    'verse', c.verse,
    'reste', (select coalesce(sum(r.a_encaisser), 0)
                from public.restes_par_boutique(c.id) r),
    'restes', (select coalesce(jsonb_object_agg(r.boutique_id, r.a_encaisser), '{}'::jsonb)
                 from public.restes_par_boutique(c.id) r
                where r.boutique_id is not null),
    -- (3.59.0) Ce que le client a payé au livreur, boutique par boutique,
    -- d'après la déclaration du livreur — et s'il l'a contesté.
    'encaissements', (select coalesce(jsonb_object_agg(x.boutique_id, jsonb_build_object(
                         'montant', x.montant, 'mode', x.mode, 'encaisse_le', x.encaisse_le,
                         'livreur', coalesce(nullif(p.nom, ''), ''),
                         'conteste', x.conteste_le is not null)), '{}'::jsonb)
                        from public.encaissements x
                        left join public.profils p on p.id = x.livreur_id
                       where x.commande_id = c.id),
    'paye_livraison', (select coalesce(sum(x.montant), 0) from public.encaissements x
                        where x.commande_id = c.id),
    -- (3.63.0) OÙ EN EST CHAQUE BOUTIQUE, pour qui suit sa commande par
    -- son numéro : l'étape la MOINS avancée de ses lignes (une ligne
    -- annulée ne retient rien), et si le client a tout confirmé. Sans
    -- compte, c'était le seul morceau du suivi qui manquait — les lignes
    -- ne se lisent qu'avec un compte. La même règle que l'application
    -- applique aux commandes d'un compte.
    'etats', (select coalesce(jsonb_object_agg(e.boutique_id,
                       jsonb_build_object('etat', e.etat, 'confirme', e.confirme)), '{}'::jsonb)
                from (select l.boutique_id,
                             (array_agg(l.etat order by array_position(
                                array['nouvelle', 'vue', 'preparee', 'en_livraison', 'remise',
                                      'annulee'], l.etat)))[1] as etat,
                             bool_and(l.confirme_le is not null) as confirme
                        from public.commande_lignes l
                       where l.commande_id = c.id
                       group by l.boutique_id) e));
end $$;

create or replace function public.commande_pour_paiement(cible text, tel text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.commandes%rowtype;
begin
  select * into c from public.commandes
   where id = coalesce(cible, '')
     and not compte_supprime
     and client_tel = regexp_replace(coalesce(tel, ''), '\D', '', 'g');
  if not found then return null; end if;
  return jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'etat', c.etat,
    'total', coalesce(c.acompte, c.total), 'devise', c.devise,
    'acompte', coalesce(c.acompte, c.total), 'total_commande', c.total,
    'nom', c.client_nom, 'tel', c.client_tel,
    'reference', c.fournisseur_ref,
    -- Pour que l'Edge Function refuse une relance AVANT d'appeler
    -- l'agrégateur : sinon le téléphone sonnerait quand même, et c'est
    -- seulement en rangeant la référence qu'on s'apercevrait du frein.
    'tentative_le', c.tentative_le);
end $$;

create or replace function public.rattacher_mes_commandes() returns int
language plpgsql security definer set search_path = public as $$
declare moi uuid := auth.uid(); mien public.clients%rowtype; combien int;
begin
  if moi is null then return 0; end if;
  select * into mien from public.clients where id = moi;
  if not found or not mien.tel_verifie or coalesce(mien.tel, '') = '' then
    raise exception 'Vérifiez votre numéro pour retrouver vos commandes';
  end if;

  perform set_config('bizzoo.interne', 'oui', true);
  update public.commandes
     set client_id = moi
   where client_id is null
     and not compte_supprime
     and client_tel = mien.tel
     and cree_le > now() - interval '18 months';
  get diagnostics combien = row_count;
  return combien;
end $$;

create or replace function public.supprimer_mon_compte(confirmation text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  ancien text := coalesce(current_setting('bizzoo.interne', true), '');
begin
  if moi is null or not exists (select 1 from auth.users where id = moi) then
    raise exception 'Connexion nécessaire';
  end if;
  if confirmation is distinct from 'SUPPRIMER' then
    raise exception 'Confirmez la suppression définitive';
  end if;
  -- Ne pas retirer le dernier responsable capable d'administrer la plateforme.
  if exists (select 1 from public.profils where id = moi and role = 'superadministrateur') then
    perform 1 from public.profils where role = 'superadministrateur' for update;
    if not exists (select 1 from public.profils where role = 'superadministrateur' and actif and id <> moi) then
      raise exception 'Transférez la responsabilité à un autre superadministrateur actif avant de supprimer ce compte';
    end if;
  end if;
  perform set_config('bizzoo.interne', 'oui', true);
  -- Les pièces commerciales restent dans leur périmètre métier, mais ne
  -- pourront plus être récupérées par un futur compte portant le même numéro.
  update public.commandes set compte_supprime = true where client_id = moi;
  delete from auth.users where id = moi;
  perform set_config('bizzoo.interne', ancien, true);
end $$;
revoke all on function public.supprimer_mon_compte(text) from public, anon;
grant execute on function public.supprimer_mon_compte(text) to authenticated;
COMMIT;
