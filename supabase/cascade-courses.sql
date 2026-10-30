-- =========================================================
-- BIZZOO 3.70.0 — La course au livreur le plus proche, puis à tous
--
--   À chaque commande payée, la course n'est plus proposée à tous les
--   livreurs d'un coup :
--     1. le livreur le plus proche de la boutique est alerté seul ; il a
--        30 secondes pour toucher « Commande reçue » ;
--     2. sinon le deuxième plus proche, puis le troisième (ceux d'avant
--        peuvent encore la prendre) ;
--     3. si aucun des trois ne l'a prise, elle part à TOUS les livreurs de
--        BIZZOO.
--   Même cascade quand un livreur annule sa course, ou que la boutique la
--   lui reprend. « Le plus proche » se lit sur une position récente (moins
--   d'une heure) : BIZZOO Admin ouvert l'envoie toutes les 3 minutes
--   (signaler_ma_position). Personne de récent : à tous tout de suite.
--   Une tâche pg_cron (« courses-cascade », toutes les 5 secondes) tient
--   l'horloge. Réglages (délai, nombre de rangs, interrupteur) :
--   table « cascade_reglage » (lisible par le seul serveur).
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- Lues par les fonctions plus bas (déjà là sur une base en service).
alter table public.commande_lignes add column if not exists livreur_id uuid;
alter table public.commande_lignes add column if not exists recu_le timestamptz;
alter table public.commande_lignes add column if not exists confirme_le timestamptz;
alter table public.profils add column if not exists courses_bloquees boolean not null default false;
alter table public.profils add column if not exists vehicule text not null default 'moto';
alter table public.commandes add column if not exists lieu_retrait text not null default '';
alter table public.paiement add column if not exists livraison_latitude double precision;
alter table public.paiement add column if not exists livraison_longitude double precision;

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

-- ---------- La course au plus proche, puis à tous (3.70.0) ----------
--
-- AVANT, la course payée sonnait chez TOUS les livreurs à la fois. Désormais
-- elle va d'abord au plus proche :
--   1. le livreur le plus proche du point de retrait est seul alerté ; il a
--      30 secondes pour toucher « Commande reçue » ;
--   2. sinon, le deuxième plus proche est alerté à son tour (le premier peut
--      encore la prendre), puis le troisième ;
--   3. si aucun des trois ne l'a prise, elle part à TOUS les livreurs de
--      BIZZOO — et à ceux qui pouvaient déjà la prendre (« candidats_course »).
--
-- « Le plus proche » : parmi les livreurs qui peuvent la prendre
-- (candidats_course : véhicule, livreurs de la boutique d'abord, refus
-- retirés), libres (sans course en cours), d'après leur dernière position —
-- les positions récentes (moins de 2 heures) d'abord, puis la distance à
-- vol d'oiseau jusqu'à la boutique (la première, en livraison groupée ; le
-- point BIZZOO si elle n'a pas de position).
--
-- C'est la BASE qui tient l'horloge : une tâche passe toutes les 5 secondes
-- (avancer_cascades), téléphones éteints ou non. Les réglages (délai, rangs,
-- fraîcheur, interrupteur) vivent dans « cascade_reglage », que seul le
-- serveur lit ; éteinte, la course part à tous d'un coup, comme avant.
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

-- (3.70.0) Lues par les fonctions plus bas (déjà là sur une base en service).
alter table public.profils add column if not exists disponible boolean not null default true;

-- (3.70.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;
revoke all on function public.est_equipe() from public, anon, authenticated;
grant execute on function public.est_equipe() to authenticated;

-- (3.70.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;
grant execute on function public.boutique_du_compte() to authenticated;

create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false)
     and public.role_courant() is not null;
$$;
revoke all on function public.est_compte_enseigne()  from public, anon;
grant execute on function public.est_compte_enseigne() to authenticated;

create or replace function public.peut_agir_sur(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.est_compte_enseigne()
      or (public.est_equipe() and cible is not null
          and cible = public.boutique_du_compte());
$$;
grant execute on function public.peut_agir_sur(text) to authenticated;

-- (3.70.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.coord_valable(valeur double precision, borne double precision)
returns double precision
language sql immutable as $$
  select case when valeur is null
                or valeur <> valeur              -- « NaN » ne s'égale pas lui-même
                or valeur < -borne or valeur > borne
              then null else valeur end;
$$;
revoke all on function public.coord_valable(double precision, double precision)
  from public, anon, authenticated;
grant execute on function public.coord_valable(double precision, double precision)
  to anon, authenticated;

-- (3.70.0) Empruntées plus bas, recopiées telles quelles.
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

-- (3.70.0) Empruntées plus bas, recopiées telles quelles.
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

-- (3.70.0) Empruntées plus bas, recopiées telles quelles.
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

create or replace function public.montant_lisible(n numeric, devise text default 'FCFA')
returns text
language sql immutable set search_path = public as $$
  select replace(to_char(coalesce(n, 0), 'FM999,999,999,990'), ',', ' ') || ' ' || coalesce(nullif(devise, ''), 'FCFA');
$$;
revoke all on function public.montant_lisible(numeric, text) from public, anon, authenticated;

-- (3.70.0) Empruntées plus bas, recopiées telles quelles.
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

create or replace function public.enseigne_des_commandes() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.boutique_id is null and p.peut_commandes
     and p.role in ('administrateur', 'moderateur');
$$;
revoke all on function public.enseigne_des_commandes()   from public, anon, authenticated;

create or replace function public.equipe_de(cible text) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and cible is not null and p.boutique_id = cible
     and p.role in ('administrateur', 'moderateur');
$$;
revoke all on function public.equipe_de(text)            from public, anon, authenticated;

create or replace function public.est_livreur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'livreur', false);
$$;
revoke all on function public.est_livreur() from public, anon, authenticated;
grant execute on function public.est_livreur() to authenticated;

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

create or replace function public.les_superadmins() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.role = 'superadministrateur';
$$;
revoke all on function public.les_superadmins()          from public, anon, authenticated;

create or replace function public.livreur_en_course(qui uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
     where l.livreur_id = qui and c.etat = 'payee'
       and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison'));
$$;
revoke all on function public.livreur_en_course(uuid) from public, anon, authenticated;

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

-- Le point d'où l'on mesure : la boutique où récupérer (la première qui a
-- une position, en livraison groupée), sinon le point BIZZOO.
-- Empruntées par les fonctions plus bas, recopiées telles quelles.
-- ---------- Ce que ce fichier change ----------
-- La boutique reprend la course à son livreur (« Confier » vide) : elle
-- repart en cascade.
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

create or replace function public.signaler_ma_position(
  lat double precision, lng double precision, precision_m int default null)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  la  double precision := public.coord_valable(lat, 90);
  lo  double precision := public.coord_valable(lng, 180);
begin
  if moi is null or not public.est_livreur() then return false; end if;
  if la is null or lo is null or (la = 0 and lo = 0) then return false; end if;
  -- (3.70.0) « Pas disponible » et sans course : sa position ne part pas.
  if exists (select 1 from public.profils p where p.id = moi and not p.disponible)
     and not public.livreur_en_course(moi) then
    return false;
  end if;
  update public.positions_livreurs
     set latitude = la, longitude = lo, precision_m = greatest(0, signaler_ma_position.precision_m),
         enregistre_le = now()
   where profil_id = moi and enregistre_le < now() - interval '30 seconds';
  return found;
end $$;
revoke all on function public.signaler_ma_position(double precision, double precision, int) from public, anon;
grant execute on function public.signaler_ma_position(double precision, double precision, int) to authenticated;

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

create or replace function public.avancer_cascades()
returns int
language plpgsql security definer set search_path = public as $$
declare
  cible text;
  n     int := 0;
begin
  for cible in
    select k.commande_id from public.courses_cascade k
     where k.prochaine is not null and k.prochaine <= now() and not k.tous
     order by k.prochaine
     limit 200
  loop
    begin
      perform public.avancer_cascade(cible);
      n := n + 1;
    exception when others then
      raise warning 'avancer_cascade(%) : %', cible, sqlerrm;
      update public.courses_cascade x set prochaine = null where x.commande_id = cible;
    end;
  end loop;
  return n;
end $$;
revoke all on function public.avancer_cascades() from public, anon, authenticated;

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

create or replace function public.alertes_course(commande text)
returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce((select k.alertes from public.courses_cascade k where k.commande_id = commande),
                  public.candidats_course(commande));
$$;
revoke all on function public.alertes_course(text) from public, anon, authenticated;

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

create or replace function public.reproposer_course(commande text)
returns int
language plpgsql security definer set search_path = public as $$
begin
  -- (3.70.0) Comme au paiement : la cascade repart du plus proche (ceux
  -- qui l'ont refusée exceptés), puis à tous les livreurs de BIZZOO.
  return public.lancer_cascade(commande, true);
end $$;
revoke all on function public.reproposer_course(text) from public, anon, authenticated;

create or replace function public.refuser_course(commande text, motif text default '')
returns int
language plpgsql security definer set search_path = public as $$
declare
  moi      uuid := auth.uid();
  pourquoi text := left(trim(coalesce(motif, '')), 300);
  parts    record;
  combien  int := 0;
  porteur  text;
  c        record;
  annonce  boolean;
  relances int := 0;
  texte    text;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Seul le livreur de la course la refuse';
  end if;
  -- (3.70.0) Un appel à la fois par commande, comme « prendre_course » :
  -- un double appui ne fait pas sonner deux fois les autres livreurs.
  perform 1 from public.commandes c0 where c0.id = commande for update;
  if not exists (select 1 from public.commande_lignes l
                  where l.commande_id = commande and l.livreur_id = moi
                    and l.etat in ('nouvelle', 'vue', 'preparee')) then
    if exists (select 1 from public.commande_lignes l
                where l.commande_id = commande and l.livreur_id = moi) then
      raise exception 'Le colis est déjà parti avec vous : vous ne pouvez plus refuser cette course.'
        using errcode = 'P0001';
    end if;
    raise exception 'Cette course ne vous est pas confiée';
  end if;
  -- (3.72.0) UNE COMMANDE GROUPÉE EST UNE SEULE COURSE. Un colis déjà
  -- récupéré dans une boutique : refuser le reste couperait la commande
  -- entre deux livreurs. Il la livre en entier, ou BIZZOO la reconfie.
  if exists (select 1 from public.commande_lignes l
              where l.commande_id = commande and l.livreur_id = moi and l.etat = 'en_livraison') then
    raise exception 'Vous avez déjà récupéré une partie de cette commande : livrez-la en entier, ou appelez BIZZOO.'
      using errcode = 'P0001';
  end if;
  select coalesce(nullif(p.nom, ''), 'Le livreur') into porteur from public.profils p where p.id = moi;
  select c0.numero, c0.client_id into c from public.commandes c0 where c0.id = commande;
  -- Le client savait-il déjà qui viendrait ?
  select exists (select 1 from public.commande_lignes l
                  where l.commande_id = commande and l.livreur_id = moi and l.recu_le is not null)
    into annonce;

  -- UNE NOUVELLE COURSE, DE NOUVELLES NOUVELLES. Chaque sorte de
  -- notification ne part qu'une fois par commande ; sans ceci, le client
  -- ne recevrait jamais le nom du livreur suivant. Les anciennes restent
  -- lisibles, mises de côté sous « …_avant_<n> » — le numéro, parce
  -- qu'une course peut être refusée plus d'une fois.
  update public.notifications n
     set type = n.type || '_avant_' || n.id
   where n.commande_id = commande
     and n.type in ('course_confiee', 'course_acceptee', 'course_refusee', 'course_annulee_livreur');

  perform set_config('bizzoo.livraison', 'oui', true);
  perform set_config('bizzoo.refus', 'oui', true);
  for parts in
    with liberees as (
      update public.commande_lignes l
         set livreur_id = null, recu_le = null
       where l.commande_id = commande and l.livreur_id = moi
         and l.etat in ('nouvelle', 'vue', 'preparee')
      returning l.boutique_id
    )
    select distinct boutique_id from liberees
  loop
    combien := combien + 1;
    insert into public.refus_courses (commande_id, boutique_id, livreur_id, motif)
    values (commande, parts.boutique_id, moi, pourquoi);
    perform public.notifier(public.equipe_de(parts.boutique_id), 'course_refusee',
      'Commande refusée par le livreur — ' || coalesce(c.numero, ''),
      porteur || ' a refusé la course' ||
        case when pourquoi <> '' then ' : « ' || pourquoi || ' »' else '' end || '.' ||
        E'\nConfiez-la à un autre livreur : la demande est aussi repartie vers les autres.',
      '#/commandes/' || commande, commande, parts.boutique_id, true);
  end loop;
  perform set_config('bizzoo.refus', '', true);
  perform set_config('bizzoo.livraison', '', true);

  if combien = 0 then return 0; end if;

  -- (3.70.0) LA COURSE REPART aux autres livreurs, avec sonnerie…
  relances := public.reproposer_course(commande);
  -- … ET BIZZOO L'ENTEND, même application fermée : le superadministrateur,
  -- les administrateurs et les modérateurs de BIZZOO (comptes sans
  -- boutique). Une sonnerie par annulation, pas une par boutique. Ceux
  -- qui n'ont pas l'écran des commandes l'ouvrent dans leurs notifications.
  texte := porteur || ' a annulé la course' ||
      case when pourquoi <> '' then ' : « ' || pourquoi || ' »' else '' end || '.' || E'\n' ||
      case when relances > 0
           then 'Elle repart vers les livreurs les plus proches, puis vers tous les livreurs de BIZZOO.'
           when relances < 0
           then 'Une partie de la commande est déjà en route ou portée par un autre livreur : ' ||
                'confiez à la main la part libérée.'
           else 'Aucun autre livreur disponible : confiez-la à la main.' end;
  perform public.notifier(public.enseigne_des_commandes() || public.les_superadmins(),
    'course_annulee_livreur', 'Course annulée par ' || porteur || ' — ' || coalesce(c.numero, ''),
    texte, '#/commandes/' || commande, commande, null, true);
  perform public.notifier(
    coalesce((select array_agg(p.id) from public.profils p
               where p.actif and p.boutique_id is null and not p.peut_commandes
                 and p.role in ('administrateur', 'moderateur')), '{}'::uuid[]),
    'course_annulee_livreur', 'Course annulée par ' || porteur || ' — ' || coalesce(c.numero, ''),
    texte, '#/notifications', commande, null, true);

  if annonce and c.client_id is not null then
    perform public.notifier(array[c.client_id], 'course_refusee',
      'Votre livreur a changé',
      'Commande ' || coalesce(c.numero, '') || ' : ' || porteur ||
        ' ne peut pas la livrer. Un autre livreur va la prendre ; vous recevrez son nom et son numéro.',
      '#/commande/' || commande, commande, null, true);
  end if;
  return combien;
end $$;
revoke all on function public.refuser_course(text, text) from public, anon;
grant execute on function public.refuser_course(text, text) to authenticated;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('courses-cascade', '5 seconds', 'select public.avancer_cascades()');
  end if;
exception when others then
  raise notice 'Cascade des courses non programmée (%)', sqlerrm;
end $$;
