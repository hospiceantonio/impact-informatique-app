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

-- (3.70.0) Lue par « candidats_course » plus bas (déjà là sur une base en service).
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

-- (3.70.0) Lues par la cascade des courses plus bas (déjà là sur une base en service).
create table if not exists public.cascade_reglage (
  id            int primary key default 1 check (id = 1),
  actif         boolean not null default true,
  delai_s       int not null default 30 check (delai_s between 10 and 600),
  rangs         int not null default 3 check (rangs between 1 and 10),
  fraicheur_min int not null default 120 check (fraicheur_min between 5 and 1440)
);
insert into public.cascade_reglage (id) values (1) on conflict (id) do nothing;
alter table public.cascade_reglage enable row level security;
revoke all on public.cascade_reglage from anon, authenticated;

-- Où en est la course : qui a été alerté, dans quel ordre, et quand passer
-- au suivant. Une ligne par commande ; un nouveau tour (course annulée par
-- son livreur) la remet à zéro.
create table if not exists public.courses_cascade (
  commande_id text primary key references public.commandes(id) on delete cascade,
  ordre       uuid[] not null default '{}',
  etape       int not null default 0,
  tous        boolean not null default false,
  alertes     uuid[] not null default '{}',
  prochaine   timestamptz,
  lancee_le   timestamptz not null default now(),
  reprise     boolean not null default false
);
create index if not exists courses_cascade_prochaine on public.courses_cascade (prochaine)
  where prochaine is not null;
alter table public.courses_cascade enable row level security;
revoke all on public.courses_cascade from anon, authenticated;

-- Le point d'où l'on mesure : la boutique où récupérer (la première qui a
-- une position, en livraison groupée), sinon le point BIZZOO.

-- (3.70.0) Lues par les fonctions plus bas (déjà là sur une base en service).
alter table public.profils add column if not exists disponible boolean not null default true;

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

-- (3.70.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.horloge_cascade()
returns boolean
language plpgsql stable security definer set search_path = public as $$
declare ok boolean := false;
begin
  if to_regclass('cron.job') is null then return false; end if;
  execute 'select exists (select 1 from cron.job where jobname = ''courses-cascade'' and active)' into ok;
  return coalesce(ok, false);
exception when others then
  return false;
end $$;
revoke all on function public.horloge_cascade() from public, anon, authenticated;

-- (3.70.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.reproposer_course(commande text)
returns int
language plpgsql security definer set search_path = public as $$
begin
  -- (3.70.0) Comme au paiement : la cascade repart du plus proche (ceux
  -- qui l'ont refusée exceptés), puis à tous les livreurs de BIZZOO.
  return public.lancer_cascade(commande, true);
end $$;
revoke all on function public.reproposer_course(text) from public, anon, authenticated;

-- (3.70.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.alerter_course(commande text, qui uuid[], titre text, entete text default '')
returns int
language plpgsql security definer set search_path = public as $$
declare
  f    jsonb;
  deja uuid[];
begin
  select k.alertes into deja from public.courses_cascade k where k.commande_id = commande;
  qui := array(select distinct x from unnest(coalesce(qui, '{}'::uuid[])) as x
                where x is not null and not (x = any(coalesce(deja, '{}'::uuid[]))));
  if array_length(qui, 1) is null then return 0; end if;
  f := public.fiche_demande(commande);
  if f is null then return 0; end if;
  update public.notifications n
     set type = n.type || '_avant_' || n.id, lue_le = coalesce(n.lue_le, now())
   where n.commande_id = commande
     and n.type in ('course_proposee', 'course_prise')
     and n.destinataire = any(qui);
  update public.courses_cascade k set alertes = k.alertes || qui where k.commande_id = commande;
  return public.notifier(qui, 'course_proposee', titre,
    coalesce(nullif(entete, '') || E'\n', '') || public.texte_demande(f),
    '#/livraisons', commande, null, true);
end $$;
revoke all on function public.alerter_course(text, uuid[], text, text) from public, anon, authenticated;

create or replace function public.livreur_en_course(qui uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
     where l.livreur_id = qui and c.etat = 'payee'
       and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison'));
$$;
revoke all on function public.livreur_en_course(uuid) from public, anon, authenticated;

create or replace function public.point_retrait_course(commande text,
  out lat double precision, out lng double precision)
language plpgsql stable security definer set search_path = public as $$
begin
  select b.latitude, b.longitude into lat, lng
    from public.commande_lignes l join public.boutiques b on b.id = l.boutique_id
   where l.commande_id = commande and l.etat <> 'annulee'
     and b.latitude is not null and b.longitude is not null
   order by b.id limit 1;
  if lat is null then
    select p.livraison_latitude, p.livraison_longitude into lat, lng
      from public.paiement p where p.id = 1;
  end if;
end $$;
revoke all on function public.point_retrait_course(text) from public, anon, authenticated;

create or replace function public.tous_livreurs_course(commande text)
returns uuid[]
language plpgsql stable security definer set search_path = public as $$
declare besoin text;
begin
  select c.livraison ->> 'vehicule' into besoin from public.commandes c where c.id = commande;
  return coalesce((
    select array_agg(distinct x.id order by x.id) from (
      select unnest(public.candidats_course(commande)) as id
      union
      select p.id from public.profils p
       where p.role = 'livreur' and p.actif and not p.courses_bloquees and p.boutique_id is null
         and (besoin is null or besoin not in ('moto', 'tricycle')
              or p.vehicule = besoin or (besoin = 'moto' and p.vehicule = 'tricycle'))
         and exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id)
         and not exists (select 1 from public.refus_courses r
                          where r.commande_id = commande and r.livreur_id = p.id)) x), '{}');
end $$;
revoke all on function public.tous_livreurs_course(text) from public, anon, authenticated;

-- (3.70.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.avancer_cascade(commande text)
returns int
language plpgsql security definer set search_path = public as $$
declare
  k      public.courses_cascade%rowtype;
  r      public.cascade_reglage%rowtype;
  num    text;
  titre  text;
  qui    uuid;
  n      int := 0;
begin
  -- Même ordre de verrous que « prendre_course » (la commande, puis la
  -- cascade) : on n'alerte jamais le suivant d'une course en train d'être prise.
  perform 1 from public.commandes c where c.id = commande for update;
  select * into k from public.courses_cascade x where x.commande_id = commande for update;
  if not found or k.tous then return 0; end if;
  if public.course_a_prendre(commande) <> 1 then
    update public.courses_cascade x set prochaine = null where x.commande_id = commande;
    return 0;
  end if;
  select * into r from public.cascade_reglage x where x.id = 1;
  if not public.horloge_cascade() then r.actif := false; end if;
  select c.numero into num from public.commandes c where c.id = commande;
  if k.reprise then
    titre := 'Course à reprendre — ' || coalesce(num, '');
  elsif (select count(distinct l.boutique_id) from public.commande_lignes l
          where l.commande_id = commande and l.etat <> 'annulee') > 1 then
    titre := 'Livraison groupée — ' || coalesce(num, '');
  else
    titre := 'Nouvelle course — ' || coalesce(num, '');
  end if;

  -- Le suivant de l'ordre, s'il peut encore la prendre.
  while k.etape < coalesce(array_length(k.ordre, 1), 0) loop
    k.etape := k.etape + 1;
    qui := k.ordre[k.etape];
    if qui = any(public.tous_livreurs_course(commande)) and not public.livreur_en_course(qui) then
      update public.courses_cascade x
         set etape = k.etape, prochaine = now() + make_interval(secs => coalesce(r.delai_s, 30))
       where x.commande_id = commande;
      n := public.alerter_course(commande, array[qui], titre,
        'Vous êtes parmi les plus proches : touchez « Commande reçue » dans les ' ||
        coalesce(r.delai_s, 30) || ' secondes, sinon elle passe au livreur suivant.');
      if n > 0 then return n; end if;
    end if;
  end loop;

  -- Personne (plus) dans l'ordre : à tous les livreurs de BIZZOO. Cascade
  -- éteinte : à ceux qui pouvaient la prendre, d'un coup, comme avant.
  update public.courses_cascade x set etape = k.etape, tous = true, prochaine = null
   where x.commande_id = commande;
  return public.alerter_course(commande,
    case when coalesce(r.actif, true) then public.tous_livreurs_course(commande)
         else public.candidats_course(commande) end, titre);
end $$;
revoke all on function public.avancer_cascade(text) from public, anon, authenticated;

create or replace function public.course_a_prendre(commande text)
returns int
language plpgsql stable security definer set search_path = public as $$
declare c record;
begin
  select c0.etat, c0.paye_le into c from public.commandes c0 where c0.id = commande;
  if not found or c.etat <> 'payee' then return 0; end if;
  if not exists (select 1 from public.commande_lignes l
                  where l.commande_id = commande and l.etat <> 'annulee') then
    return 0;
  end if;
  if exists (select 1 from public.commande_lignes l
              where l.commande_id = commande and l.etat <> 'annulee'
                and (l.livreur_id is not null or l.etat in ('en_livraison', 'remise'))) then
    return -1;
  end if;
  if c.paye_le is null or c.paye_le <= now() - interval '7 days' then return 0; end if;
  return 1;
end $$;
revoke all on function public.course_a_prendre(text) from public, anon, authenticated;

create or replace function public.plus_proches_course(commande text, combien int)
returns uuid[]
language plpgsql stable security definer set search_path = public as $$
declare
  pt     record;
  fraich int;
  boutq  uuid[];
begin
  select * into pt from public.point_retrait_course(commande);
  select coalesce(r.fraicheur_min, 60) into fraich from public.cascade_reglage r where r.id = 1;
  boutq := public.candidats_course(commande);
  return coalesce((
    select array_agg(x.id order by x.rang, x.km nulls last, x.id)
      from (select p.id,
                   -- Ceux qui pouvaient déjà la prendre (sa boutique) d'abord.
                   case when p.id = any(boutq) then 0 else 1 end as rang,
                   case when pt.lat is null then null else
                     2 * 6371 * asin(least(1, sqrt(
                       sin(radians(pl.latitude - pt.lat) / 2) ^ 2
                       + cos(radians(pt.lat)) * cos(radians(pl.latitude))
                         * sin(radians(pl.longitude - pt.lng) / 2) ^ 2))) end as km
              from unnest(public.tous_livreurs_course(commande)) as c(id)
              join public.profils p on p.id = c.id
              join public.positions_livreurs pl on pl.profil_id = p.id
             where pl.enregistre_le > now() - make_interval(mins => coalesce(fraich, 60))
               -- (3.70.0) « Pas disponible » : jamais parmi les plus proches.
               and p.disponible
               and not public.livreur_en_course(p.id)
             order by 2, 3 nulls last, 1
             limit greatest(coalesce(combien, 3), 0)) x), '{}');
end $$;
revoke all on function public.plus_proches_course(text, int) from public, anon, authenticated;

-- (3.70.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.alertes_course(commande text)
returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce((select k.alertes from public.courses_cascade k where k.commande_id = commande),
                  public.candidats_course(commande));
$$;
revoke all on function public.alertes_course(text) from public, anon, authenticated;

create or replace function public.course_ouverte_a(commande text, qui uuid)
returns boolean
language plpgsql stable security definer set search_path = public as $$
declare k public.courses_cascade%rowtype;
begin
  select * into k from public.courses_cascade x where x.commande_id = commande;
  if not found then
    return qui = any(public.candidats_course(commande));
  end if;
  if exists (select 1 from public.profils p where p.id = qui and (p.courses_bloquees or not p.actif))
     or exists (select 1 from public.refus_courses r where r.commande_id = commande and r.livreur_id = qui) then
    return false;
  end if;
  if qui = any(k.alertes) then return true; end if;
  -- Étape « tous » passée (ou cascade arrêtée) : ouverte à ceux qui peuvent
  -- la prendre MAINTENANT — un livreur débloqué ou validé depuis la voit.
  if k.tous or k.prochaine is null then
    -- Cascade éteinte (ou sans horloge) : à ceux qui pouvaient la prendre,
    -- comme avant ; allumée : à tous les livreurs de BIZZOO aussi.
    if coalesce((select r.actif from public.cascade_reglage r where r.id = 1), true)
       and public.horloge_cascade() then
      return qui = any(public.tous_livreurs_course(commande))
          or qui = any(public.candidats_course(commande));
    end if;
    return qui = any(public.candidats_course(commande));
  end if;
  return false;
end $$;
revoke all on function public.course_ouverte_a(text, uuid) from public, anon, authenticated;

create or replace function public.lancer_cascade(commande text, reprise boolean default false)
returns int
language plpgsql security definer set search_path = public as $$
declare
  etat int;
  r    public.cascade_reglage%rowtype;
begin
  etat := public.course_a_prendre(commande);
  if etat <> 1 then return etat; end if;
  select * into r from public.cascade_reglage x where x.id = 1;
  if coalesce(r.actif, true) and not public.horloge_cascade() then
    -- Sans la tâche des 5 secondes, la cascade resterait au premier : à
    -- tous d'un coup, comme avant.
    r.actif := false;
  end if;
  if reprise then
    -- Les demandes du tour d'avant ne valent plus : la course repart du
    -- plus proche, et chacun la retrouvera à son tour.
    update public.notifications n set lue_le = coalesce(n.lue_le, now())
     where n.commande_id = commande and n.type = 'course_proposee';
  end if;
  insert into public.courses_cascade as k (commande_id, ordre, etape, tous, alertes, prochaine, lancee_le, reprise)
  values (commande,
          case when r.actif is not false
               then public.plus_proches_course(commande, coalesce(r.rangs, 3)) else '{}' end,
          0, false, '{}', null, now(), coalesce(reprise, false))
  on conflict (commande_id) do update
     set ordre = excluded.ordre, etape = 0, tous = false, alertes = '{}',
         prochaine = null, lancee_le = now(), reprise = excluded.reprise;
  return public.avancer_cascade(commande);
end $$;
revoke all on function public.lancer_cascade(text, boolean) from public, anon, authenticated;

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


-- =========================================================
-- BIZZOO 3.59.0 — Le parcours de livraison : le livreur sait tout, le
-- client connaît son livreur
--
--   1. L'ALERTE DU LIVREUR, quand une boutique lui confie une course :
--      où récupérer le colis, où le livrer, le numéro du destinataire,
--      les frais de livraison, ce que le client a déjà payé, et ce qu'il
--      reste à récupérer (fiche_course). Son écran « Mes courses » montre
--      la même chose ;
--   2. « REÇU » : le livreur accepte la course (accepter_course). Le
--      client reçoit alors le nom et le numéro de son livreur ; la
--      boutique apprend que la course est acceptée ;
--   3. le reçu du client montre son livreur à partir de ce moment-là ;
--   4. LA DEMANDE ENVOYÉE À TOUS, dès que la commande est payée
--      (proposer_course) : une commande d'une boutique part à tous ses
--      livreurs (à ceux de BIZZOO si elle n'en a aucun) ; une commande de
--      plusieurs boutiques — livraison groupée — part aux seuls livreurs
--      de BIZZOO. Le premier qui touche « Commande reçue » (prendre_course)
--      prend toute la commande ; les autres la voient disparaître. La
--      boutique garde « Confier à un livreur » en secours.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

alter table public.commande_lignes add column if not exists recu_le timestamptz;
alter table public.commande_lignes
  add column if not exists prix_bizzoo int not null default 0;
alter table public.commande_lignes add column if not exists taux_marge numeric;

-- Les colonnes que les fonctions plus bas lisent (3.59.0).
alter table public.commande_lignes add column if not exists code text not null default '';
alter table public.commande_lignes add column if not exists confirme_le timestamptz;
alter table public.commande_lignes add column if not exists livreur_id uuid;

-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;



create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;


create or replace function public.enseigne_des_commandes() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.boutique_id is null and p.peut_commandes
     and p.role in ('administrateur', 'moderateur');
$$;


create or replace function public.equipe_de(cible text) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and cible is not null and p.boutique_id = cible
     and p.role in ('administrateur', 'moderateur');
$$;


create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false)
     and public.role_courant() is not null;
$$;


create or replace function public.est_livreur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'livreur', false);
$$;


create or replace function public.les_superadmins() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.role = 'superadministrateur';
$$;

revoke all on function public.equipe_de(text)            from public, anon, authenticated;
revoke all on function public.enseigne_des_commandes()   from public, anon, authenticated;
revoke all on function public.les_superadmins()          from public, anon, authenticated;

create or replace function public.notifier(
  qui uuid[], quoi text, le_titre text, le_corps text,
  le_lien text, la_commande text, la_boutique text, qui_sonne boolean)
returns int
language plpgsql security definer set search_path = public as $$
declare combien int := 0;
begin
  if qui is null or array_length(qui, 1) is null then return 0; end if;
  insert into public.notifications
    (destinataire, type, titre, corps, lien, commande_id, boutique_id, sonne)
  select u, quoi, coalesce(le_titre, ''), coalesce(le_corps, ''),
         coalesce(le_lien, ''), la_commande, la_boutique, coalesce(qui_sonne, false)
    from unnest(qui) as u
   where u is not null
  on conflict do nothing;
  get diagnostics combien = row_count;
  return combien;
end $$;
revoke all on function public.notifier(uuid[], text, text, text, text, text, text, boolean)
  from public, anon, authenticated;

create or replace function public.peut_agir_sur(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.est_compte_enseigne()
      or (public.est_equipe() and cible is not null
          and cible = public.boutique_du_compte());
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
revoke all on function public.restes_par_boutique(text) from public, anon, authenticated;


create or replace function public.ligne_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- LA CONFIRMATION DU CLIENT passe par « confirmer_reception », qui
  -- pose ce drapeau. Sans lui, la colonne est aussi verrouillée que le
  -- reste : ni la boutique ni le client ne peuvent l'écrire à la main.
  if coalesce(current_setting('bizzoo.reception', true), '') <> 'oui'
     and new.confirme_le is distinct from old.confirme_le then
    raise exception 'Un accusé de réception se pose depuis le compte du client';
  end if;

  -- CONFIER UNE LIVRAISON passe par « assigner_livreur », qui pose ce
  -- drapeau après avoir vérifié que celui qui confie tient bien la
  -- boutique, et que celui à qui l'on confie est bien son livreur.
  -- Sans lui, n'importe quelle écriture sur la ligne pourrait se
  -- désigner porteuse de la marchandise.
  if coalesce(current_setting('bizzoo.livraison', true), '') <> 'oui'
     and new.livreur_id is distinct from old.livreur_id then
    raise exception 'Une livraison se confie depuis le compte de la boutique';
  end if;
  -- « Reçu » se pose par « accepter_course », par le livreur lui-même.
  if coalesce(current_setting('bizzoo.livraison', true), '') <> 'oui'
     and new.recu_le is distinct from old.recu_le then
    raise exception 'Une course s''accepte depuis le compte du livreur';
  end if;

  if new.commande_id is distinct from old.commande_id
  or new.boutique_id is distinct from old.boutique_id
  or new.produit_id  is distinct from old.produit_id
  or new.nom         is distinct from old.nom
  or new.code        is distinct from old.code
  or new.reference   is distinct from old.reference
  or new.prix        is distinct from old.prix
  or new.prix_bizzoo is distinct from old.prix_bizzoo
  or new.taux_marge  is distinct from old.taux_marge
  or new.quantite    is distinct from old.quantite then
    raise exception 'Une ligne de commande ne change que d''état : ce qui a été vendu est vendu';
  end if;
  return new;
end $$;


-- (BIZZOO Personnel) Le livreur bloqué : lu par la fonction qui suit.
alter table public.profils add column if not exists courses_bloquees boolean not null default false;

create or replace function public.assigner_livreur(
  commande text, boutique text, livreur uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  combien  int;
  autres   int := 0;
  rang     text;
  bizzoo   boolean := false;
  numero   text;
  b        record;
  son_vehicule text;
  besoin   text;
  plusieurs boolean;
  au_km    boolean;
  bloque   boolean;
begin
  if not public.peut_agir_sur(boutique) then
    raise exception 'Cette commande ne concerne pas votre boutique';
  end if;
  -- (3.64.0) UN SEUL LIVREUR PAR COMMANDE AU KILOMÈTRE. Une telle
  -- commande de plusieurs boutiques se confie à un livreur de BIZZOO, qui
  -- les livre toutes ; et une commande en tricycle, à un livreur en
  -- tricycle. Les commandes d'avant (frais par boutique) gardent leur
  -- règle : un livreur par boutique.
  select c.livraison ->> 'vehicule', c.livraison is not null into besoin, au_km
    from public.commandes c where c.id = commande;
  au_km := coalesce(au_km, false);
  select au_km and count(distinct l.boutique_id) > 1 into plusieurs
    from public.commande_lignes l where l.commande_id = commande and l.etat <> 'annulee';

  -- « livreur » nul : on retire l'attribution. Une boutique doit pouvoir
  -- reprendre une course confiée par erreur.
  if livreur is not null then
    select p.role, (p.boutique_id is null), p.vehicule, p.courses_bloquees
      into rang, bizzoo, son_vehicule, bloque from public.profils p
     where p.id = livreur and p.actif
       and (public.est_super()
            or public.est_compte_enseigne()
            -- Le livreur de BIZZOO : aucune boutique, donc toutes.
            or p.boutique_id is null
            or p.boutique_id = public.boutique_du_compte());
    if rang is distinct from 'livreur' then
      raise exception 'Ce compte n''est pas un livreur de votre boutique ni de BIZZOO';
    end if;
    -- Bloqué par l'administration de BIZZOO : plus aucune course.
    if bloque then
      raise exception 'Ce livreur est bloqué par BIZZOO : il ne reçoit plus de course. Confiez-la à un autre.'
        using errcode = 'P0001';
    end if;
    if coalesce(plusieurs, false) and not coalesce(bizzoo, false) then
      raise exception 'Cette commande traverse plusieurs boutiques : confiez-la à un livreur de BIZZOO, qui les livre toutes.'
        using errcode = 'P0001';
    end if;
    if besoin = 'tricycle' and son_vehicule is distinct from 'tricycle' then
      raise exception 'Cette commande se livre en tricycle : confiez-la à un livreur en tricycle.'
        using errcode = 'P0001';
    end if;
    -- UN LIVREUR VALIDE SON COMPTE EN ENREGISTRANT SA POSITION. Tant
    -- qu'il ne l'a pas fait, on ne lui confie rien.
    if not exists (select 1 from public.positions_livreurs pl where pl.profil_id = livreur) then
      raise exception 'Ce livreur n''a pas encore validé son compte : il doit ouvrir BIZZOO Admin et enregistrer sa position.'
        using errcode = 'P0001';
    end if;
  end if;

  perform set_config('bizzoo.livraison', 'oui', true);
  update public.commande_lignes l
     set livreur_id = livreur,
         -- Un autre livreur doit accepter à son tour (3.59.0).
         recu_le = case when l.livreur_id is distinct from livreur then null else l.recu_le end
   where l.commande_id = commande
     -- (3.64.0) Au kilomètre, retirer le livreur le retire de toute la
     -- commande : une course, c'est la commande entière.
     and (l.boutique_id = boutique or (livreur is null and au_km))
     -- (3.59.0) En secours de la demande envoyée à tous les livreurs : la
     -- boutique peut confier dès le paiement, sans attendre le colis.
     and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')
     and exists (select 1 from public.commandes c where c.id = l.commande_id and c.etat = 'payee');
  get diagnostics combien = row_count;

  -- LE LIVREUR DE BIZZOO : les produits des autres boutiques aussi. Sans
  -- prendre une part déjà confiée au livreur d'une autre boutique —
  -- (3.64.0) sauf au kilomètre : un seul livreur par commande, il les
  -- prend toutes.
  if bizzoo and combien > 0 then
    update public.commande_lignes l
       set livreur_id = livreur, recu_le = null
     where l.commande_id = commande
       and l.boutique_id <> boutique
       and (l.livreur_id is null or (au_km and l.livreur_id is distinct from livreur))
       and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison');
    get diagnostics autres = row_count;
  end if;
  perform set_config('bizzoo.livraison', '', true);

  if combien = 0 then
    raise exception 'Rien à confier ici : la commande n''est pas encore payée, ou elle est déjà livrée.';
  end if;

  -- Les autres boutiques le savent : un livreur BIZZOO passera chez elles.
  if autres > 0 then
    select c.numero into numero from public.commandes c where c.id = commande;
    for b in select distinct l.boutique_id as id from public.commande_lignes l
              where l.commande_id = commande and l.boutique_id <> boutique and l.livreur_id = livreur
    loop
      perform public.notifier(public.equipe_de(b.id), 'course_confiee',
        'Un livreur BIZZOO passe récupérer vos produits',
        'Commande ' || coalesce(numero, '') || ' — il livre toute la commande. Préparez le colis.',
        '#/commandes/' || commande, commande, b.id, true);
    end loop;
  end if;
  -- (3.70.0) Course reprise au livreur (« Confier » vide) : elle repart en
  -- cascade, du plus proche à tous (rien si une autre partie est portée).
  if livreur is null then
    perform public.reproposer_course(commande);
  end if;
  return combien + autres;
end $$;
revoke all on function public.assigner_livreur(text, text, uuid) from public, anon;
grant execute on function public.assigner_livreur(text, text, uuid) to authenticated;

create or replace function public.livreurs_de_ma_commande(cible text, tel text default '')
returns table (boutique_id text, nom text, telephone text, indicatif text)
language plpgsql stable security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  tel_donne text := regexp_replace(coalesce(tel, ''), '\D', '', 'g');
begin
  if not exists (
    select 1 from public.commandes c
     where c.id = cible
       and not c.compte_supprime
       and c.etat = 'payee'
       and ((moi is not null and c.client_id = moi)
            or (tel_donne <> '' and c.client_tel = tel_donne))) then
    return;
  end if;
  return query
    select distinct on (l.boutique_id)
           l.boutique_id::text, coalesce(p.nom, '')::text, coalesce(p.tel, '')::text,
           coalesce(nullif(b.indicatif, ''), '229')::text
      from public.commande_lignes l
      join public.profils p
        on p.id = l.livreur_id and p.role = 'livreur' and p.actif
      left join public.boutiques b on b.id = l.boutique_id
     where l.commande_id = cible
       and l.etat <> 'annulee'
       and l.confirme_le is null
       -- (3.59.0) Une fois que le livreur a ACCEPTÉ la course (« Reçu ») —
       -- ou l'a prise : avant, on ne sait pas encore qui viendra.
       and (l.recu_le is not null or l.etat in ('en_livraison', 'remise'))
     order by l.boutique_id;
end $$;
revoke all on function public.livreurs_de_ma_commande(text, text) from public;
grant execute on function public.livreurs_de_ma_commande(text, text) to anon, authenticated;

create or replace function public.montant_lisible(n numeric, devise text default 'FCFA')
returns text
language sql immutable set search_path = public as $$
  select replace(to_char(coalesce(n, 0), 'FM999,999,999,990'), ',', ' ') || ' ' || coalesce(nullif(devise, ''), 'FCFA');
$$;
revoke all on function public.montant_lisible(numeric, text) from public, anon, authenticated;

-- (3.70.0) Lue par « fiche_course » / « faire_livrer » plus bas.
alter table public.commandes add column if not exists lieu_retrait text not null default '';

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
      'latitude', b.latitude, 'longitude', b.longitude),
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
                                           'distance_km', c.livraison -> 'distance_km') end,
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

create or replace function public.accepter_course(commande text, boutique text)
returns int
language plpgsql security definer set search_path = public as $$
declare
  moi     uuid := auth.uid();
  combien int;
  bizzoo  boolean;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Cette course ne vous est pas confiée';
  end if;
  select (p.boutique_id is null) into bizzoo from public.profils p where p.id = moi;
  perform set_config('bizzoo.livraison', 'oui', true);
  if coalesce(bizzoo, false) then
    perform set_config('bizzoo.prise', 'oui', true);
  end if;
  update public.commande_lignes l
     set recu_le = now()
   where l.commande_id = commande
     and (l.boutique_id = boutique or coalesce(bizzoo, false))
     and l.livreur_id = moi
     and l.recu_le is null
     -- (3.59.0) Dès le paiement : la course s'accepte avant que le colis
     -- soit prêt.
     and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison');
  get diagnostics combien = row_count;
  perform set_config('bizzoo.livraison', '', true);
  perform set_config('bizzoo.prise', '', true);
  if combien = 0 and not exists (
       select 1 from public.commande_lignes l
        where l.commande_id = commande and l.boutique_id = boutique
          and l.livreur_id = moi and l.recu_le is not null) then
    raise exception 'Cette course ne vous est pas confiée';
  end if;
  return combien;
end $$;
revoke all on function public.accepter_course(text, text) from public, anon;
grant execute on function public.accepter_course(text, text) to authenticated;

create or replace function public.avancer_livraison(
  commande text, boutique text, vers text)
returns int
language plpgsql security definer set search_path = public as $$
declare
  moi     uuid := auth.uid();
  combien int;
  depuis  text;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Cette course ne vous est pas confiée';
  end if;
  if vers not in ('en_livraison', 'remise') then
    raise exception 'Un livreur prend une course, ou la remet.';
  end if;
  -- On n'avance que dans le bon sens : « remise » ne se pose qu'après
  -- « en livraison ». Sans cela, une course se déclarerait remise sans
  -- jamais avoir été prise.
  depuis := case when vers = 'en_livraison' then 'preparee' else 'en_livraison' end;

  -- (3.59.0) PAS DE REMISE SANS LE RESTE PAYÉ PAR MOMOPAY. Ce chemin
  -- d'avant (« Je l'ai remise » sans rien déclarer) ne passe plus quand
  -- le client doit encore quelque chose : c'est remettre_course, avec le
  -- numéro de la transaction, qui remet le colis.
  if vers = 'remise'
     and coalesce((select r.a_encaisser from public.restes_par_boutique(commande) r
                    where r.boutique_id = boutique), 0) > 0
     and not exists (select 1 from public.encaissements x
                      where x.commande_id = commande and x.boutique_id = boutique
                        and x.mode = 'mobile_money') then
    raise exception 'Le client doit d''abord payer le reste par MoMoPay : touchez « Remettre le colis » et saisissez le numéro de la transaction.'
      using errcode = 'P0001';
  end if;

  -- Prendre la course sans avoir touché « Reçu » vaut acceptation.
  perform set_config('bizzoo.livraison', 'oui', true);
  update public.commande_lignes l
     set etat = vers,
         recu_le = coalesce(l.recu_le, now())
   where l.commande_id = commande
     and l.boutique_id = boutique
     and l.livreur_id = moi
     and l.etat = depuis;
  -- Le compte AVANT de rendre le drapeau : « row_count » parle de la
  -- dernière instruction, et ce serait alors celle-là.
  get diagnostics combien = row_count;
  perform set_config('bizzoo.livraison', '', true);

  if combien = 0 then
    raise exception 'Rien à avancer ici : cette course n''en est pas là.';
  end if;
  return combien;
end $$;
revoke all on function public.avancer_livraison(text, text, text) from public, anon;
grant execute on function public.avancer_livraison(text, text, text) to authenticated;

drop function if exists public.mes_livraisons();
create or replace function public.mes_livraisons()
returns table (
  commande_id text, numero text,
  boutique_id text, nom_boutique text,
  client_nom text, client_tel text, client_indicatif text,
  client_adresse text, note text,
  etat text, articles jsonb, paye_le timestamptz,
  a_encaisser bigint,
  fiche jsonb, recu_le timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare moi uuid := auth.uid();
begin
  if moi is null or not public.est_livreur() then return; end if;
  return query
    select c.id, c.numero,
           l.boutique_id,
           coalesce((select b.nom from public.boutiques b where b.id = l.boutique_id), '')::text,
           c.client_nom, c.client_tel, c.client_indicatif,
           c.client_adresse, c.note,
           -- L'étape la MOINS avancée de ses lignes : c'est elle qui dit
           -- ce qu'il lui reste à faire.
           -- (3.59.0) Par le rang, pas l'alphabet : une course prise dès le
           -- paiement est d'abord « nouvelle » ou « vue » — en préparation.
           (array['nouvelle','vue','preparee','en_livraison','remise'])[
             min(array_position(array['nouvelle','vue','preparee','en_livraison','remise'], l.etat))]::text,
           jsonb_agg(jsonb_build_object(
             'nom', l.nom, 'code', l.code, 'quantite', l.quantite)
             order by l.nom),
           c.paye_le,
           -- Ce qu'il réclame au client : la part du reste qui revient à
           -- SA boutique. Zéro quand tout a été payé en ligne.
           coalesce((select r.a_encaisser
                       from public.restes_par_boutique(c.id) r
                      where r.boutique_id is not distinct from l.boutique_id), 0)::bigint,
           -- Où récupérer, où livrer, les frais, le déjà-payé (3.59.0).
           public.fiche_course(c.id, l.boutique_id),
           min(l.recu_le)
      from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
     where l.livreur_id = moi
       and c.etat = 'payee'
       and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison', 'remise')
       -- Une course remise depuis plus de deux jours n'a plus à
       -- encombrer sa liste.
       and (l.etat <> 'remise' or c.paye_le > now() - interval '2 days')
     group by c.id, c.numero, l.boutique_id, c.client_nom, c.client_tel,
              c.client_indicatif, c.client_adresse, c.note, c.paye_le
     order by c.paye_le;
end $$;
revoke all on function public.mes_livraisons() from public, anon;
grant execute on function public.mes_livraisons() to authenticated;

create or replace function public.notifier_ligne() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  cmd      record;
  numero   text;
  client   uuid;
  equipe   uuid[];
  enseigne uuid[];
  fiche    jsonb;
  porteur  record;
begin
  select c.numero, c.client_id into cmd
    from public.commandes c where c.id = new.commande_id;
  numero   := coalesce(cmd.numero, '');
  client   := cmd.client_id;
  equipe   := public.equipe_de(new.boutique_id);
  enseigne := public.enseigne_des_commandes();

  -- ---- Une course confiée, ou reprise ----
  if new.livreur_id is distinct from old.livreur_id then
    -- Le livreur qui a pris la course lui-même (« Commande reçue »)
    -- connaît déjà sa fiche : l'alerte n'est que pour une course que la
    -- boutique lui CONFIE.
    if new.livreur_id is not null
       and coalesce(current_setting('bizzoo.prise', true), '') <> 'oui' then
      -- (3.59.0) L'ALERTE DIT TOUT CE QU'IL FAUT POUR PARTIR : où prendre
      -- le colis, où le livrer, le numéro du destinataire, les frais, ce
      -- qui est déjà payé, et ce qu'il reste à récupérer. Les montants de
      -- CETTE boutique seulement ; pas le prix des articles.
      fiche := public.fiche_course(new.commande_id, new.boutique_id);
      perform public.notifier(array[new.livreur_id], 'course_confiee',
        'Nouvelle course — ' || numero,
        'Récupérer : ' || (fiche -> 'retrait' ->> 'boutique') ||
          coalesce(nullif(' — ' || (fiche -> 'retrait' ->> 'adresse'), ' — '), '') ||
          -- (3.70.0) Le numéro de la boutique, pour l'appeler s'il se perd.
          coalesce(' — Tél. boutique : +' || coalesce(nullif(fiche -> 'retrait' ->> 'indicatif', ''), '229') || ' ' ||
                   nullif(fiche -> 'retrait' ->> 'tel', ''), '') || E'\n' ||
        -- (3.70.0) Ce que l'équipe a précisé en saisissant la commande.
        coalesce('Où récupérer : ' || nullif(fiche ->> 'lieu_retrait', '') || E'\n', '') ||
        'Livrer à : ' || coalesce(nullif(fiche -> 'livraison' ->> 'nom', ''), 'le client') ||
          coalesce(nullif(' — ' || (fiche -> 'livraison' ->> 'adresse'), ' — '), ' (adresse à demander)') || E'\n' ||
        'Destinataire : +' || (fiche -> 'livraison' ->> 'indicatif') || ' ' || (fiche -> 'livraison' ->> 'tel') || E'\n' ||
        'Frais de livraison : ' || public.montant_lisible((fiche ->> 'frais')::numeric, fiche ->> 'devise') || E'\n' ||
        'Déjà payé : ' || public.montant_lisible((fiche ->> 'deja_paye')::numeric, fiche ->> 'devise') || E'\n' ||
        case when (fiche ->> 'a_encaisser')::numeric > 0
             then 'Reste à payer par MoMoPay : ' || public.montant_lisible((fiche ->> 'a_encaisser')::numeric, fiche ->> 'devise') ||
                  ' (pas d''espèces)'
             else 'Rien à récupérer : tout est payé.' end || E'\n' ||
        'Touchez « Commande reçue » pour accepter la course.',
        '#/livraisons', new.commande_id, new.boutique_id, true);
    end if;
    if coalesce(current_setting('bizzoo.refus', true), '') <> 'oui' then
    perform public.notifier(enseigne, 'course_confiee',
      'Course confiée à un livreur',
      'Commande ' || numero || '.',
      '#/commandes/' || new.commande_id, new.commande_id, new.boutique_id, true);
    end if;
  end if;

  -- ---- « Reçu » : le livreur a accepté (3.59.0) ----
  -- LE CLIENT REÇOIT LE NOM ET LE NUMÉRO DE SON LIVREUR, pour le joindre
  -- si besoin. La boutique apprend que sa course est acceptée.
  if new.recu_le is not null and old.recu_le is null and new.livreur_id is not null then
    select coalesce(nullif(p.nom, ''), 'Votre livreur') as nom, coalesce(p.tel, '') as tel
      into porteur from public.profils p where p.id = new.livreur_id;
    if client is not null then
      -- Une commande prise d'un coup (« Commande reçue ») : UNE nouvelle
      -- pour toute la commande — toutes ses boutiques en livraison
      -- groupée —, pas une par boutique.
      perform public.notifier(array[client], 'course_acceptee',
        'Votre livreur : ' || porteur.nom,
        porteur.nom || ' livre votre commande ' || numero ||
          coalesce(' (' || nullif(
            case when coalesce(current_setting('bizzoo.prise', true), '') = 'oui'
                 then (select string_agg(distinct b.nom, ', ') from public.commande_lignes l2
                         join public.boutiques b on b.id = l2.boutique_id
                        where l2.commande_id = new.commande_id and l2.etat <> 'annulee')
                 else (select b.nom from public.boutiques b where b.id = new.boutique_id) end,
            '') || ')', '') || '.' ||
          case when porteur.tel <> ''
               then E'\nSon numéro : +' || coalesce(nullif((select b.indicatif from public.boutiques b where b.id = new.boutique_id), ''), '229') ||
                    ' ' || porteur.tel || ' — appelez-le si besoin.'
               else '' end,
        '#/commande/' || new.commande_id, new.commande_id,
        case when coalesce(current_setting('bizzoo.prise', true), '') = 'oui' then null
             else new.boutique_id end, true);
    end if;
    perform public.notifier(equipe, 'course_acceptee',
      'Course acceptée par ' || porteur.nom,
      'Commande ' || numero || ' — le livreur a accepté la course.',
      '#/commandes/' || new.commande_id, new.commande_id, new.boutique_id, true);
    -- (3.66.0) BIZZOO AUSSI L'ENTEND : ses administrateurs qui suivent les
    -- commandes et les superadministrateurs — une sonnerie par prise, pas
    -- une par boutique quand le livreur prend toute la commande d'un coup.
    perform public.notifier(enseigne || public.les_superadmins(), 'course_acceptee',
      'Course prise par ' || porteur.nom,
      'Commande ' || numero || ' — ' || porteur.nom || ' a pris la course.',
      '#/commandes/' || new.commande_id, new.commande_id,
      case when coalesce(current_setting('bizzoo.prise', true), '') = 'oui' then null
           else new.boutique_id end, true);
  end if;

  -- ---- L'accusé de réception du client ----
  -- C'est la boutique qui l'attend : elle a remis, elle veut savoir que
  -- c'est bien arrivé.
  if new.confirme_le is not null and old.confirme_le is null then
    perform public.notifier(equipe, 'reception_confirmee',
      'Le client a confirmé la réception',
      'Commande ' || numero || ' — le client déclare avoir tout reçu.',
      '#/commandes/' || new.commande_id, new.commande_id, new.boutique_id, true);
    perform public.notifier(enseigne, 'reception_confirmee',
      'Réception confirmée',
      'Commande ' || numero || '.',
      '#/commandes/' || new.commande_id, new.commande_id, new.boutique_id, true);
  end if;

  if new.etat is not distinct from old.etat then return new; end if;

  -- ---- Les crans du colis ----
  if new.etat = 'preparee' and client is not null then
    perform public.notifier(array[client], 'commande_preparee',
      'Votre colis est prêt',
      'Commande ' || numero || ' — il part bientôt.',
      '#/commande/' || new.commande_id, new.commande_id, new.boutique_id, true);
  end if;

  if new.etat = 'en_livraison' then
    if client is not null then
      perform public.notifier(array[client], 'commande_en_livraison',
        'Votre colis est en route',
        'Commande ' || numero || ' — tenez votre téléphone à portée.',
        '#/commande/' || new.commande_id, new.commande_id, new.boutique_id, true);
    end if;
    perform public.notifier(equipe, 'commande_en_livraison',
      'Colis parti',
      'Commande ' || numero || ' est en livraison.',
      '#/commandes/' || new.commande_id, new.commande_id, new.boutique_id, true);
  end if;

  if new.etat = 'remise' then
    if client is not null then
      perform public.notifier(array[client], 'commande_remise',
        'Votre colis est livré',
        'Commande ' || numero || ' — confirmez que vous avez bien reçu.',
        '#/commande/' || new.commande_id, new.commande_id, new.boutique_id, true);
    end if;
    perform public.notifier(equipe, 'commande_remise',
      'Colis remis',
      'Commande ' || numero || ' — en attente de la confirmation du client.',
      '#/commandes/' || new.commande_id, new.commande_id, new.boutique_id, true);
  end if;

  -- ---- Un incident : le superadministrateur, lui, veut le savoir ----
  if new.etat = 'annulee' then
    if client is not null then
      perform public.notifier(array[client], 'commande_annulee',
        'Une partie de votre commande est annulée',
        'Commande ' || numero || ' — ouvrez-la pour le détail.',
        '#/commande/' || new.commande_id, new.commande_id, new.boutique_id, true);
    end if;
    perform public.notifier(enseigne || public.les_superadmins(), 'commande_annulee',
      'Commande annulée',
      'Commande ' || numero || '.',
      '#/commandes/' || new.commande_id, new.commande_id, new.boutique_id, true);
  end if;

  return new;
end $$;




drop trigger if exists lignes_notifient on public.commande_lignes;
create trigger lignes_notifient
  after update on public.commande_lignes
  for each row execute function public.notifier_ligne();

-- ---------- La demande de course, envoyée à tous (3.59.0) ----------
create or replace function public.candidats_course(commande text)
returns uuid[]
language plpgsql stable security definer set search_path = public as $$
declare
  boutiques text[];
  qui       uuid[];
  besoin    text;
  vs        text[];
  v         text;
begin
  select array_agg(distinct l.boutique_id) into boutiques
    from public.commande_lignes l
   where l.commande_id = commande and l.etat <> 'annulee' and l.boutique_id is not null;
  if boutiques is null then return '{}'; end if;
  select c.livraison ->> 'vehicule' into besoin from public.commandes c where c.id = commande;
  vs := case besoin when 'tricycle' then array['tricycle']
                    when 'moto' then array['moto', 'tricycle']
                    else array[null::text] end;
  if array_length(boutiques, 1) = 1 then
    foreach v in array vs loop
      select array_agg(p.id order by p.id) into qui
        from public.profils p
       where p.role = 'livreur' and p.actif and not p.courses_bloquees and p.boutique_id = boutiques[1]
         and (v is null or p.vehicule = v)
         and exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id)
         -- (3.70.0) Ceux qui l'ont refusée ne comptent plus : si toute la
         -- boutique l'a refusée, elle passe aux tricycles, puis à BIZZOO.
         and not exists (select 1 from public.refus_courses r
                          where r.commande_id = commande and r.livreur_id = p.id);
      if qui is not null then return qui; end if;
    end loop;
  end if;
  foreach v in array vs loop
    select array_agg(p.id order by p.id) into qui
      from public.profils p
     where p.role = 'livreur' and p.actif and not p.courses_bloquees and p.boutique_id is null
       and (v is null or p.vehicule = v)
       and exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id)
       and not exists (select 1 from public.refus_courses r
                        where r.commande_id = commande and r.livreur_id = p.id);
    if qui is not null then return qui; end if;
  end loop;
  return '{}';
end $$;
revoke all on function public.candidats_course(text) from public, anon, authenticated;

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
  for b in select distinct l.boutique_id from public.commande_lignes l
            where l.commande_id = commande and l.etat <> 'annulee' and l.boutique_id is not null
            order by 1 loop
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
         then 'Votre gain : ' || public.montant_lisible((f ->> 'gain')::numeric, f ->> 'devise') || E'\n'
         else '' end ||
    'Déjà payé : ' || public.montant_lisible((f ->> 'deja_paye')::numeric, f ->> 'devise') || E'\n' ||
    case when (f ->> 'a_encaisser')::numeric > 0
         then 'À récupérer : ' || public.montant_lisible((f ->> 'a_encaisser')::numeric, f ->> 'devise')
         else 'Rien à récupérer : tout est payé.' end || E'\n' ||
    'Le premier qui touche « Commande reçue » prend la course.';
end $$;
revoke all on function public.texte_demande(jsonb) from public, anon, authenticated;

create or replace function public.proposer_course() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.etat is not distinct from old.etat or new.etat <> 'payee' then
    return null;
  end if;
  begin
    -- (3.70.0) Au plus proche d'abord, puis aux suivants, puis à tous.
    perform public.lancer_cascade(new.id, false);
  exception when others then
    raise warning 'proposer_course(%) : %', new.id, sqlerrm;
  end;
  return null;
end $$;


create or replace function public.courses_proposees()
returns table (commande_id text, numero text, paye_le timestamptz, fiche jsonb)
language plpgsql stable security definer set search_path = public as $$
declare moi uuid := auth.uid();
begin
  if moi is null or not public.est_livreur() then return; end if;
  if not exists (select 1 from public.positions_livreurs pl where pl.profil_id = moi) then return; end if;
  return query
    select c.id, c.numero, c.paye_le, public.fiche_demande(c.id)
      from public.commandes c
     where c.etat = 'payee'
       and exists (select 1 from public.commande_lignes l
                    where l.commande_id = c.id and l.etat <> 'annulee')
       -- Personne ne l'a encore prise, ni reçue en secours.
       and not exists (select 1 from public.commande_lignes l
                        where l.commande_id = c.id and l.etat <> 'annulee'
                          and l.livreur_id is not null)
       and not exists (select 1 from public.commande_lignes l
                        where l.commande_id = c.id
                          and l.etat in ('en_livraison', 'remise'))
       and c.paye_le > now() - interval '7 days'
       -- (3.70.0) Ceux que la cascade a déjà alertés (avant : tous les candidats).
       and public.course_ouverte_a(c.id, moi)
       -- (3.59.0) Il l'a refusée : elle ne lui revient pas.
       and not exists (select 1 from public.refus_courses rc
                        where rc.commande_id = c.id and rc.livreur_id = moi)
     order by c.paye_le;
end $$;
revoke all on function public.courses_proposees() from public, anon;
grant execute on function public.courses_proposees() to authenticated;

create or replace function public.prendre_course(commande text)
returns int
language plpgsql security definer set search_path = public as $$
declare
  moi     uuid := auth.uid();
  combien int;
  preneur text;
  numero  text;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Seul un livreur prend une course';
  end if;
  perform 1 from public.commandes c where c.id = commande and c.etat = 'payee' for update;
  if not found then
    raise exception 'Cette commande n''attend pas de livreur';
  end if;
  -- (3.70.0) Ouverte à ceux que la cascade a déjà alertés.
  if not public.course_ouverte_a(commande, moi) then
    raise exception 'Cette course n''est pas proposée à votre compte';
  end if;
  if exists (select 1 from public.refus_courses rc
              where rc.commande_id = commande and rc.livreur_id = moi) then
    raise exception 'Vous avez refusé cette course.' using errcode = 'P0001';
  end if;
  -- (3.59.0) On dit QUI l'a prise.
  select coalesce(nullif(p.nom, ''), 'un autre livreur') into preneur
    from public.commande_lignes l join public.profils p on p.id = l.livreur_id
   where l.commande_id = commande and l.etat <> 'annulee' and l.livreur_id is not null
   limit 1;
  if preneur is not null then
    raise exception 'Déjà pris par %.', preneur using errcode = 'P0001';
  end if;

  perform set_config('bizzoo.livraison', 'oui', true);
  perform set_config('bizzoo.prise', 'oui', true);
  update public.commande_lignes l
     set livreur_id = moi, recu_le = now()
   where l.commande_id = commande
     and l.livreur_id is null
     and l.etat in ('nouvelle', 'vue', 'preparee');
  get diagnostics combien = row_count;
  perform set_config('bizzoo.prise', '', true);
  perform set_config('bizzoo.livraison', '', true);
  if combien = 0 then
    raise exception 'Trop tard : un autre livreur a déjà pris cette course.'
      using errcode = 'P0001';
  end if;

  -- (3.59.0) LES AUTRES SONT PRÉVENUS TOUT DE SUITE : « Déjà pris par … ».
  -- La nouvelle arrive en temps réel sur leur téléphone, et leur
  -- sonnerie s'arrête. Leur demande d'avant passe « lue ».
  select coalesce(nullif(p.nom, ''), 'un autre livreur') into preneur
    from public.profils p where p.id = moi;
  select c.numero into numero from public.commandes c where c.id = commande;
  update public.notifications n
     set lue_le = now()
   where n.commande_id = commande and n.type = 'course_proposee'
     and n.destinataire <> moi and n.lue_le is null;
  -- (3.70.0) La cascade s'arrête : la course a son livreur.
  update public.courses_cascade k set prochaine = null where k.commande_id = commande;
  perform public.notifier(
    array(select x from unnest(public.alertes_course(commande)) as x where x <> moi),
    'course_prise',
    'Déjà pris par ' || preneur,
    'Commande ' || coalesce(numero, '') || ' — ' || preneur || ' a pris la course. Elle n''est plus disponible.',
    '#/livraisons', commande, null, false);
  return combien;
end $$;
revoke all on function public.prendre_course(text) from public, anon;
grant execute on function public.prendre_course(text) to authenticated;



drop trigger if exists commandes_proposent on public.commandes;
create trigger commandes_proposent
  after update of etat on public.commandes
  for each row execute function public.proposer_course();
