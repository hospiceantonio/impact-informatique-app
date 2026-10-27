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
-- BIZZOO 3.59.0 — Chaque boutique : ses conditions de paiement, ses frais
--
-- Chaque boutique dit comment on la paie — tout à la commande, ou un
-- acompte (en %) à la commande et le reste à la livraison — et ce que
-- coûte sa livraison. À la commande, la base calcule la part de chaque
-- boutique, ce qui se paie maintenant et ce qui restera à la livraison ;
-- chaque livreur encaisse la part de SA boutique.
--
-- Les boutiques en service reçoivent les réglages qui s'appliquaient à
-- toutes jusqu'ici : acompte de 10 %, livraison 1 000 FCFA.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- La part de chaque boutique, figée sur la commande.
alter table public.commandes add column if not exists parts jsonb;
alter table public.commandes add column if not exists transaction_annoncee text not null default '';
alter table public.commandes add column if not exists fournisseur_ref text not null default '';
alter table public.commandes add column if not exists tentative_le timestamptz;

-- ---------- Les conditions de paiement de chaque boutique (3.59.0) ----------
-- CHAQUE BOUTIQUE DIT COMMENT ON LA PAIE, et ce que coûte sa livraison :
--   mode_paiement « total »   : tout se paie à la commande ;
--                 « acompte » : taux_acompte % à la commande, le reste à la
--                               livraison, à son livreur ;
--   frais_livraison           : en FCFA, ajoutés à sa part — aucun code
--                               promo ne les touche.
-- Une commande sur plusieurs boutiques additionne leurs conditions :
-- creer_commande calcule chaque part, et « parts » les garde. Les valeurs
-- par défaut sont celles que l'enseigne appliquait à toutes jusqu'ici
-- (10 %, 1 000 FCFA).
alter table public.boutiques add column if not exists mode_paiement text not null default 'acompte';
alter table public.boutiques add column if not exists taux_acompte int not null default 10;
alter table public.boutiques add column if not exists frais_livraison int not null default 1000;
alter table public.boutiques drop constraint if exists boutiques_mode_paiement;
alter table public.boutiques add constraint boutiques_mode_paiement
  check (mode_paiement in ('total', 'acompte'));
alter table public.boutiques drop constraint if exists boutiques_taux_acompte;
alter table public.boutiques add constraint boutiques_taux_acompte
  check (taux_acompte between 1 and 99);
alter table public.boutiques drop constraint if exists boutiques_frais_livraison;
alter table public.boutiques add constraint boutiques_frais_livraison
  check (frais_livraison between 0 and 100000);

-- Les boutiques déjà en service : ce que l'enseigne appliquait à toutes.
update public.boutiques b
   set taux_acompte = least(99, greatest(1, coalesce((select pa.taux_acompte from public.paiement pa where pa.id = 1), 10))),
       mode_paiement = case when coalesce((select pa.taux_acompte from public.paiement pa where pa.id = 1), 10) >= 100
                            then 'total' else 'acompte' end,
       frais_livraison = least(100000, greatest(0, coalesce((select pa.frais_livraison from public.paiement pa where pa.id = 1), 1000)))
 where b.cree_le < now() - interval '1 minute'
   and not exists (select 1 from public.commandes c where c.parts is not null);

-- Les colonnes que les fonctions plus bas lisent (3.59.0).
alter table public.commandes add column if not exists acompte int;
alter table public.commandes add column if not exists client_id uuid;
alter table public.commandes add column if not exists compte_supprime boolean not null default false;
alter table public.commandes add column if not exists frais_livraison bigint not null default 0;
alter table public.commandes add column if not exists revendeur boolean not null default false;
alter table public.commandes add column if not exists taux_acompte int;
alter table public.commandes add column if not exists verse int;

-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
create or replace function public.ouvertures_valides(o jsonb) returns boolean
language sql immutable set search_path = public as $$
  select jsonb_typeof(o) = 'object'
     and not exists (select 1 from jsonb_object_keys(o) k
                      where k not in ('lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'))
     and not exists (
       select 1 from jsonb_each(o) j
        where jsonb_typeof(j.value) not in ('null', 'object')
           or (jsonb_typeof(j.value) = 'object' and not (
                length(coalesce(j.value ->> 'de', '')) = 5
            and (j.value ->> 'de') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]'
            and length(coalesce(j.value ->> 'a', '')) = 5
            and ((j.value ->> 'a') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]' or (j.value ->> 'a') = '24:00')
            and (j.value ->> 'de') < (j.value ->> 'a'))))
     and exists (select 1 from jsonb_each(o) j where jsonb_typeof(j.value) = 'object');
$$;


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
grant execute on function public.ouvertures_valides(jsonb) to anon, authenticated;
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

create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;


create or replace function public.est_revendeur() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.clients c
                  where c.id = auth.uid() and c.revendeur_etat = 'validee');
$$;
revoke all on function public.est_revendeur() from public, anon, authenticated;
grant execute on function public.est_revendeur() to authenticated;

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


create or replace function public.commande_a_l_ecriture() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.etat := 'a_payer';
  new.transaction_id := '';
  new.transaction_annoncee := '';
  new.confirme_par := '';
  new.remarque := '';
  new.annonce_le := null;
  new.paye_le := null;
  -- L'acompte se pose APRÈS les lignes, par « creer_commande » : il se
  -- calcule sur un total que la base n'a pas encore. Rien ne l'apporte
  -- de dehors, pas plus que l'argent versé.
  new.taux_acompte := null;
  new.acompte := null;
  new.parts := null;
  new.verse := null;
  -- Les frais de livraison aussi : « creer_commande » les pose, d'après
  -- les réglages de l'enseigne. Le téléphone n'en décide pas.
  new.frais_livraison := 0;
  new.livraison := null;
  new.revendeur := public.est_revendeur();
  if coalesce(new.numero, '') = '' then
    new.numero := 'BZ-' || lpad(nextval('public.commandes_numero')::text, 6, '0');
  end if;
  return new;
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


drop function if exists public.creer_commande(jsonb, jsonb, text, boolean, boolean);
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
begin
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
  if au_km then
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
    devises := devises || coalesce(nullif((
      select b.devise from public.boutiques b where b.id = p.boutique_id), ''), 'FCFA');
    insert into public.commande_lignes (id, commande_id, produit_id, quantite)
    values ('lig_' || replace(gen_random_uuid()::text, '-', ''), nouvelle, p.id, qte);
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
    devis := public.devis_livraison(
      (destination ->> 'latitude')::double precision,
      (destination ->> 'longitude')::double precision,
      case when exists (select 1 from public.commande_lignes l
                          join public.produits pr on pr.id = l.produit_id
                         where l.commande_id = nouvelle and pr.vehicule = 'tricycle')
           then 'tricycle' else 'moto' end);
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


