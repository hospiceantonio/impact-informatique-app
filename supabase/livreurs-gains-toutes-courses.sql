-- =========================================================
-- BIZZOO 3.66.0 — Le livreur touche sa part de TOUTES ses courses
--
--   Jusqu'ici, seules les commandes au kilomètre créditaient le
--   livreur. Désormais, chaque course remise et payée lui rapporte
--   80 % (« taux_livreur ») des frais de livraison :
--     • au kilomètre : les frais entiers (un seul livreur) ;
--     • à l'ancien tarif par boutique : les frais des boutiques dont
--       il a livré les produits — deux livreurs, deux parts ;
--     • plus ancien encore : au prorata de ce qu'il a porté.
--
--   RATTRAPAGE : les courses remises des 30 derniers jours sont
--   créditées une fois, et chaque livreur reçoit UNE notification
--   avec le total.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable :
-- une course n'est jamais créditée deux fois.
-- =========================================================

-- ---------- Une ligne par commande ET par livreur ----------
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

-- Emprunté par les fonctions plus bas, recopié tel quel.
create or replace function public.est_livreur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'livreur', false);
$$;

-- Emprunté par les fonctions plus bas, recopié tel quel.
create or replace function public.montant_lisible(n numeric, devise text default 'FCFA')
returns text
language sql immutable set search_path = public as $$
  select replace(to_char(coalesce(n, 0), 'FM999,999,999,990'), ',', ' ') || ' ' || coalesce(nullif(devise, ''), 'FCFA');
$$;
revoke all on function public.montant_lisible(numeric, text) from public, anon, authenticated;

-- Emprunté par les fonctions plus bas, recopié tel quel.
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

-- Emprunté par les fonctions plus bas, recopié tel quel.
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

-- ---------- Les règles ----------
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

create or replace function public.crediter_livreur(cible text) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  c       public.commandes%rowtype;
  qui     uuid;
  t       int;
  part    numeric;
  gain    bigint;
  combien int;
begin
  select * into c from public.commandes where id = cible;
  if not found or c.etat <> 'payee' then return 0; end if;
  select coalesce(p.taux_livreur, 80) into t from public.paiement p where p.id = 1;
  for qui in select distinct l.livreur_id from public.commande_lignes l
              where l.commande_id = cible and l.etat = 'remise' and l.livreur_id is not null loop
    if exists (select 1 from public.commande_lignes l
                where l.commande_id = cible and l.livreur_id = qui
                  and l.etat not in ('remise', 'annulee')) then
      continue;
    end if;
    part := public.part_frais_livreur(cible, qui);
    if coalesce(part, 0) <= 0 then continue; end if;
    gain := floor(part * coalesce(t, 80) / 100.0)::bigint;
    insert into public.gains_livreurs (commande_id, livreur_id, frais, taux, montant)
    values (cible, qui, part::bigint, coalesce(t, 80), gain)
    on conflict (commande_id, livreur_id) do nothing;
    get diagnostics combien = row_count;
    -- Un rattrapage prévient une fois par livreur, pas une fois par course.
    if combien > 0 and coalesce(current_setting('bizzoo.rattrapage', true), '') <> 'oui' then
      perform public.notifier(array[qui], 'gain_livraison',
        'Course payée : + ' || public.montant_lisible(gain, c.devise),
        'Commande ' || coalesce(c.numero, '') || ' remise — ' || public.montant_lisible(gain, c.devise) ||
          ' ajoutés à votre solde.',
        '#/gains', cible, null, false);
    end if;
  end loop;
  return coalesce((select sum(g.montant) from public.gains_livreurs g where g.commande_id = cible), 0)::bigint;
end $$;
revoke all on function public.crediter_livreur(text) from public, anon, authenticated;

create or replace function public.solde_livreur(cible uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  qui uuid := coalesce(cible, auth.uid());
  gagne bigint; a_venir bigint; reverse bigint; attente bigint; t int;
  r public.livreurs_reception%rowtype;
begin
  if qui is null or not ((qui = auth.uid() and public.est_livreur()) or public.est_super()) then
    raise exception 'Ce solde n''est pas le vôtre.';
  end if;
  select coalesce(sum(g.montant), 0) into gagne from public.gains_livreurs g where g.livreur_id = qui;
  select coalesce(p.taux_livreur, 80) into t from public.paiement p where p.id = 1;
  select coalesce(sum(floor(public.part_frais_livreur(c.id, qui) * coalesce(t, 80) / 100.0)), 0)::bigint
    into a_venir
    from public.commandes c
   where c.etat = 'payee' and coalesce(c.frais_livraison, 0) > 0
     and not exists (select 1 from public.gains_livreurs g where g.commande_id = c.id and g.livreur_id = qui)
     and exists (select 1 from public.commande_lignes l
                  where l.commande_id = c.id and l.livreur_id = qui
                    and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison'));
  select coalesce(sum(v.montant) filter (where v.etat = 'valide'), 0),
         coalesce(sum(v.montant) filter (where v.etat = 'en_attente'), 0)
    into reverse, attente
    from public.reversements_livreurs v where v.livreur_id = qui;
  select * into r from public.livreurs_reception where livreur_id = qui;
  return jsonb_build_object(
    'gagne', gagne, 'a_venir', a_venir, 'reverse', reverse, 'en_attente', attente,
    'disponible', greatest(0, gagne - reverse - attente),
    'taux', coalesce(t, 80), 'devise', 'FCFA',
    'reception', case when r.livreur_id is null or r.tel = '' then null
                      else jsonb_build_object('tel', r.tel, 'reseau', r.reseau, 'titulaire', r.titulaire,
                                              'maj_le', r.maj_le) end,
    'courses', coalesce((select jsonb_agg(jsonb_build_object(
                  'commande_id', g.commande_id, 'numero', c.numero, 'frais', g.frais,
                  'taux', g.taux, 'montant', g.montant, 'credite_le', g.credite_le,
                  'vehicule', c.livraison ->> 'vehicule',
                  'distance_km', c.livraison -> 'distance_km') order by g.credite_le desc)
                 from (select * from public.gains_livreurs x where x.livreur_id = qui
                        order by x.credite_le desc limit 50) g
                 join public.commandes c on c.id = g.commande_id), '[]'::jsonb));
end $$;
revoke all on function public.solde_livreur(uuid) from public, anon;
grant execute on function public.solde_livreur(uuid) to authenticated;

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
    'retrait', jsonb_build_object(
      'boutique', coalesce(b.nom, ''), 'adresse', coalesce(b.adresse, ''),
      'tel', coalesce(nullif(b.tel, ''), b.whatsapp, ''), 'indicatif', coalesce(nullif(b.indicatif, ''), '229'),
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

-- ---------- Le rattrapage des 30 derniers jours ----------
do $$
declare
  c   record;
  l   record;
begin
  perform set_config('bizzoo.rattrapage', 'oui', true);
  for c in select x.id from public.commandes x
            where x.etat = 'payee' and coalesce(x.frais_livraison, 0) > 0
              and coalesce(x.paye_le, x.cree_le) > now() - interval '30 days'
              and exists (select 1 from public.commande_lignes y
                           where y.commande_id = x.id and y.etat = 'remise' and y.livreur_id is not null) loop
    perform public.crediter_livreur(c.id);
  end loop;
  perform set_config('bizzoo.rattrapage', '', true);
  -- Une notification par livreur, avec ce qui vient de lui être crédité
  -- (« credite_le » vaut l'heure de CETTE transaction : un second passage
  -- ne renvoie rien).
  for l in select g.livreur_id, sum(g.montant)::bigint as total, count(*) as n
             from public.gains_livreurs g
            where g.livreur_id is not null and g.credite_le = now()
            group by g.livreur_id having sum(g.montant) > 0 loop
    perform public.notifier(array[l.livreur_id], 'gain_livraison',
      'Vos courses sont créditées : + ' || public.montant_lisible(l.total, 'FCFA'),
      l.n || ' course(s) des 30 derniers jours ajoutée(s) à votre solde — ' ||
        public.montant_lisible(l.total, 'FCFA') || '.',
      '#/gains', null, null, false);
  end loop;
end $$;
