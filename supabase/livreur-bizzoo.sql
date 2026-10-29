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

create table if not exists public.cascade_reglage (
  id            int primary key default 1 check (id = 1),
  actif         boolean not null default true,
  delai_s       int not null default 30 check (delai_s between 10 and 600),
  rangs         int not null default 3 check (rangs between 1 and 10),
  fraicheur_min int not null default 60 check (fraicheur_min between 5 and 1440)
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

alter table public.commandes add column if not exists lieu_retrait text not null default '';

-- (3.70.0) Lues par les fonctions plus bas (déjà là sur une base en service).
alter table public.profils add column if not exists disponible boolean not null default true;

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
  -- À vol d'oiseau (formule de haversine, rayon terrestre de 6 371 km),
  -- multipliée par le coefficient de la route ; au mètre près.
  dlat := radians(latitude - r.livraison_latitude);
  dlng := radians(longitude - r.livraison_longitude);
  a := sin(dlat / 2) ^ 2
       + cos(radians(r.livraison_latitude)) * cos(radians(latitude)) * sin(dlng / 2) ^ 2;
  dist := round((2 * 6371 * asin(least(1, sqrt(a))) * r.livraison_coef)::numeric, 3);
  -- Le kilomètre ENTAMÉ compte : 10,001 km facturent un kilomètre de plus.
  km := case when dist > r.livraison_rayon_km then ceil(dist - r.livraison_rayon_km)::int else 0 end;
  forf := case when v = 'tricycle' then r.tricycle_forfait else r.moto_forfait end;
  prix := case when v = 'tricycle' then r.tricycle_prix_km else r.moto_prix_km end;
  return jsonb_build_object(
    'vehicule', v,
    'distance_km', round(dist, 1),
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
-- BIZZOO — le livreur de l'enseigne
--
-- CE QUI MANQUAIT. Un livreur appartenait forcément à UNE
-- boutique. Un porteur qui fait la tournée de toutes les
-- boutiques de BIZZOO n'avait donc pas de place : il fallait
-- lui ouvrir un compte par boutique, avec un mot de passe par
-- boutique, et il recevait ses courses dans quatre listes.
--
-- CE QUE CE FICHIER AJOUTE. La même convention que pour les
-- comptes d'enseigne : AUCUNE BOUTIQUE VEUT DIRE TOUTES. Un
-- livreur rattaché à aucune boutique est un livreur de BIZZOO.
-- Toutes les boutiques le voient dans « Confier à un livreur »,
-- toutes peuvent lui confier une course, et ses courses
-- arrivent dans une seule liste, la sienne.
--
-- CE QUE CELA NE LUI DONNE PAS. Rien de plus. Un livreur de
-- BIZZOO reste un livreur : pas de catalogue, pas de commandes,
-- pas de chiffres, et AUCUN MONTANT — ni le prix payé, ni le
-- prix BIZZOO. Il ne voit d'ailleurs pas plus de courses qu'un
-- autre : seulement celles qu'on lui a confiées. « Aucune
-- boutique » ne le fait pas entrer dans l'équipe de BIZZOO —
-- « est_compte_enseigne() » écarte son rang exprès.
--
-- CE QUE CE FICHIER NE DÉFAIT PAS. Aucun livreur existant ne
-- change de main : celui qui a une boutique la garde, et sa
-- boutique reste la seule à le voir.
--
-- UNE SEULE CHOSE CHANGE POUR L'EXISTANT, et il faut la savoir.
-- Avant, un livreur créé SANS choisir de boutique se retrouvait
-- avec une boutique vide — par distraction, pas par décision —
-- et plus personne ne le voyait dans aucune liste. Ce compte-là
-- devient maintenant un livreur de BIZZOO, visible de toutes
-- les boutiques. Si vous en avez un dans ce cas, ouvrez sa
-- fiche et donnez-lui sa boutique.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
-- On peut le coller deux fois de suite sans conséquence.
-- =========================================================

-- ---------- Recopié de schema.sql ----------
-- Ce fichier doit pouvoir se coller seul : les deux fonctions
-- ci-dessous s'appuient sur celles-là, qui ne changent pas.
alter table public.profils add column if not exists nom text not null default '';
alter table public.profils add column if not exists tel text not null default '';

-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
create or replace function public.equipe_de(cible text) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and cible is not null and p.boutique_id = cible
     and p.role in ('administrateur', 'moderateur');
$$;


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


create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;
grant execute on function public.est_equipe() to authenticated;

create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;
grant execute on function public.boutique_du_compte() to authenticated;

-- « administrateur » ou « modérateur », actif, rattaché à AUCUNE
-- boutique. LE LIVREUR EN EST EXCLU PAR SON RANG, et c'est ce qui
-- permet à « aucune boutique » de vouloir dire deux choses
-- différentes sans les confondre : un compte qui gouverne toutes les
-- boutiques d'un côté, un porteur qui les sert toutes de l'autre.
create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false)
     and public.role_courant() is not null;
$$;
revoke all on function public.est_compte_enseigne() from public, anon;
grant execute on function public.est_compte_enseigne() to authenticated;

-- « assigner_livreur » s'ouvre là-dessus : le superadministrateur
-- partout, un compte de BIZZOO partout, une boutique chez elle.
create or replace function public.peut_agir_sur(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.est_compte_enseigne()
      or (public.est_equipe() and cible is not null
          and cible = public.boutique_du_compte());
$$;

-- ---------- La liste des livreurs ----------
-- DEUX SORTES DE LIVREURS, et la liste les rend toutes les deux :
-- celui de la boutique, et CELUI DE BIZZOO. La colonne « bizzoo » dit
-- lequel est lequel, pour que l'écran puisse l'écrire : confier une
-- course à quelqu'un qui n'est pas de la maison se fait les yeux
-- ouverts.
--
-- « drop » AVANT « create or replace » : changer les colonnes rendues
-- par une fonction n'est pas un remplacement aux yeux de PostgreSQL,
-- qui refuse net. Sans cette ligne, le fichier s'arrêterait ici, et
-- seulement sur une base déjà en service.
drop function if exists public.livreurs_boutique();
create or replace function public.livreurs_boutique()
returns table (id uuid, email text, nom text, tel text,
               actif boolean, bizzoo boolean)
language plpgsql stable security definer set search_path = public as $$
declare cible text := public.boutique_du_compte();
begin
  if not public.est_equipe() then return; end if;
  return query
    select p.id, coalesce(p.email, '')::text,
           coalesce(p.nom, '')::text, coalesce(p.tel, '')::text, p.actif,
           (p.boutique_id is null)
      from public.profils p
     where p.role = 'livreur'
       -- L'enseigne les voit tous, les comptes de BIZZOO aussi ;
       -- une boutique, les siens ET ceux de BIZZOO.
       and (public.est_super() or public.est_compte_enseigne()
            or (cible is not null
                and (p.boutique_id = cible or p.boutique_id is null)))
     -- Les siens d'abord, ceux de BIZZOO ensuite : on appelle son
     -- porteur avant de déranger celui de l'enseigne.
     -- Puis par nom quand il y en a un, par adresse sinon : une liste
     -- rangée par e-mail alors qu'on lit des noms paraît en désordre.
     order by (p.boutique_id is null), nullif(p.nom, '') nulls last, p.email;
end $$;
revoke all on function public.livreurs_boutique() from public, anon;
grant execute on function public.livreurs_boutique() to authenticated;

-- (BIZZOO Personnel) Le livreur bloqué : lu par la fonction qui suit.
alter table public.profils add column if not exists courses_bloquees boolean not null default false;

-- ---------- Confier une livraison ----------
-- LA BOUTIQUE CONFIE, à SON livreur ou à CELUI DE BIZZOO. Confier à
-- celui de la boutique d'à côté reste refusé : ce serait lui remettre
-- le nom, le numéro et l'adresse d'un client qui n'est pas le sien.
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

-- ---------- Un contrôle à la fin ----------
do $$
declare rendu text; corps text;
begin
  select pg_get_function_result(p.oid) into rendu
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'livreurs_boutique';
  if rendu is null then
    raise exception 'livreurs_boutique() est introuvable';
  end if;
  if rendu !~ 'bizzoo boolean' then
    raise exception 'livreurs_boutique() ne dit pas qui est de BIZZOO : %', rendu;
  end if;

  select p.prosrc into corps
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'assigner_livreur';
  if corps !~ 'boutique_id is null' then
    raise exception 'assigner_livreur() refuse encore le livreur de BIZZOO';
  end if;

  raise notice 'Un livreur peut maintenant porter pour toute l''enseigne.';
end $$;
