-- =========================================================
-- BIZZOO 4.6.0 — Les visiteurs de la boutique : combien, combien de
-- temps, ce qu'ils regardent
--
--   La boutique (le site et l'application) dit à la base, sans nom ni
--   numéro : « une visite a commencé », « elle dure encore », « ce
--   produit a été ouvert », « un article est allé au panier », « une
--   commande a été payée ». L'administration et le site du personnel
--   lisent les totaux : visiteurs par jour, temps passé, produits et
--   boutiques les plus consultés.
--
--   AUCUNE DONNÉE PERSONNELLE. Le visiteur est un identifiant tiré au
--   hasard par son appareil ; il n'est relié ni à un compte, ni à un
--   numéro, ni à une adresse. Les deux tables sont fermées : personne
--   ne les lit, seules ces deux fonctions y passent.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- Une ligne par visite (une suite d'écrans sans demi-heure de pause).
-- (4.1.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.rh_est_ceo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and ceo);
$$;


create or replace function public.rh_est_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and (administration or ceo));
$$;


create table if not exists public.visites (
  session    text primary key,
  visiteur   text not null,
  jour       date not null,
  plateforme text not null default 'web',
  debut      timestamptz not null default now(),
  dernier    timestamptz not null default now(),
  ecrans     int not null default 0,
  panier     boolean not null default false,
  commande   boolean not null default false
);
create index if not exists visites_jour on public.visites (jour);
create index if not exists visites_visiteur on public.visites (visiteur);

-- Les fiches ouvertes, comptées par jour : un produit, une boutique.
create table if not exists public.visites_vues (
  jour  date not null,
  genre text not null check (genre in ('produit', 'boutique')),
  cible text not null,
  vues  int not null default 0,
  primary key (jour, genre, cible)
);

alter table public.visites enable row level security;
alter table public.visites_vues enable row level security;
revoke all on public.visites, public.visites_vues from public, anon, authenticated;

-- La boutique note. Tout visiteur l'appelle, connecté ou non : la
-- fonction ne rend rien, ne lit rien pour lui, et borne ce qu'elle
-- accepte — un identifiant mal formé, une visite de plus de douze
-- heures ou de plus de 500 écrans ne s'écrivent pas. Une fiche qui
-- n'existe pas ne se compte pas.
create or replace function public.noter_visite(
  le_visiteur text, la_session text, la_plateforme text,
  des_ecrans int, des_vues jsonb, au_panier boolean, a_commande boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  p text := case when la_plateforme in ('web', 'android', 'ios') then la_plateforme else 'web' end;
  e int := greatest(0, least(coalesce(des_ecrans, 0), 20));
  deja int;
begin
  if le_visiteur is null or la_session is null
     or le_visiteur ~ '[^a-z0-9]' or length(le_visiteur) not between 12 and 40
     or la_session ~ '[^a-z0-9]' or length(la_session) not between 12 and 40 then
    return;
  end if;
  insert into public.visites as v (session, visiteur, jour, plateforme, ecrans, panier, commande)
  values (la_session, le_visiteur, aujourdhui, p, e, coalesce(au_panier, false), coalesce(a_commande, false))
  on conflict (session) do update
    set dernier = now(),
        ecrans = least(v.ecrans + excluded.ecrans, 500),
        panier = v.panier or excluded.panier,
        commande = v.commande or excluded.commande
    where v.debut > now() - interval '12 hours' and v.visiteur = excluded.visiteur
  returning v.ecrans into deja;
  -- Rien d'écrit (visite trop vieille, ou d'un autre) : rien à compter.
  if deja is null or deja >= 500 then
    return;
  end if;
  if jsonb_typeof(des_vues) = 'array' then
    insert into public.visites_vues as w (jour, genre, cible, vues)
    select aujourdhui, x.genre, x.cible, count(*)::int
      from (select y ->> 'g' as genre, y ->> 'c' as cible
              from jsonb_array_elements(des_vues) with ordinality as t(y, n)
             where t.n <= 20) x
     where (x.genre = 'produit' and exists (select 1 from public.produits pr where pr.id = x.cible))
        or (x.genre = 'boutique' and exists (select 1 from public.boutiques b where b.id = x.cible))
     group by x.genre, x.cible
    on conflict (jour, genre, cible) do update set vues = w.vues + excluded.vues;
  end if;
end $$;
revoke all on function public.noter_visite(text, text, text, int, jsonb, boolean, boolean) from public;
grant execute on function public.noter_visite(text, text, text, int, jsonb, boolean, boolean) to anon, authenticated;

-- Les totaux : le superadministrateur (BIZZOO Admin), l'administration
-- et le CEO (site du personnel). Des nombres seulement.
create or replace function public.statistiques_visiteurs(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  au_jour date := coalesce(jusqu, aujourdhui);
  du_jour date := coalesce(depuis, coalesce(jusqu, aujourdhui) - 29);
begin
  if auth.uid() is null or not (public.est_super() or public.rh_est_admin() or public.rh_est_ceo()) then
    raise exception 'Les statistiques des visiteurs sont réservées au superadministrateur et à l''administration.'
      using errcode = 'P0001';
  end if;
  if au_jour < du_jour then
    raise exception 'La fin de la période précède son début' using errcode = 'P0001';
  end if;
  if au_jour - du_jour > 1100 then
    raise exception 'Période trop longue : trois ans au plus' using errcode = 'P0001';
  end if;
  return jsonb_build_object(
    'periode', jsonb_build_object('depuis', du_jour, 'jusqu', au_jour),
    'total', (
      select jsonb_build_object(
        'visiteurs', count(distinct v.visiteur),
        'visites', count(*),
        -- Une visite compte trois heures au plus : un onglet oublié
        -- ouvert ne fait pas une visite d'une journée.
        'duree_moyenne_s', coalesce(round(avg(least(extract(epoch from v.dernier - v.debut), 10800)))::int, 0),
        'ecrans_moyens', coalesce(round(avg(v.ecrans)::numeric, 1), 0),
        'panier', count(*) filter (where v.panier),
        'commande', count(*) filter (where v.commande),
        'nouveaux', count(distinct v.visiteur) filter (where not exists (
          select 1 from public.visites a where a.visiteur = v.visiteur and a.jour < du_jour)))
      from public.visites v where v.jour between du_jour and au_jour),
    'jours', coalesce((
      select jsonb_agg(jsonb_build_object('jour', x.jour, 'visiteurs', x.visiteurs, 'visites', x.visites,
               'duree_moyenne_s', x.duree) order by x.jour)
        from (select v.jour, count(distinct v.visiteur) as visiteurs, count(*) as visites,
                     coalesce(round(avg(least(extract(epoch from v.dernier - v.debut), 10800)))::int, 0) as duree
                from public.visites v where v.jour between du_jour and au_jour group by v.jour) x), '[]'::jsonb),
    'plateformes', coalesce((
      select jsonb_object_agg(x.plateforme, x.n)
        from (select v.plateforme, count(*) as n from public.visites v
               where v.jour between du_jour and au_jour group by v.plateforme) x), '{}'::jsonb),
    'produits', coalesce((
      select jsonb_agg(jsonb_build_object('id', x.cible, 'nom', x.nom, 'boutique', x.boutique, 'vues', x.vues)
               order by x.vues desc, x.nom)
        from (select w.cible, pr.nom, coalesce(b.nom, '') as boutique, sum(w.vues)::int as vues
                from public.visites_vues w
                join public.produits pr on pr.id = w.cible
                left join public.boutiques b on b.id = pr.boutique_id
               where w.genre = 'produit' and w.jour between du_jour and au_jour
               group by w.cible, pr.nom, b.nom order by sum(w.vues) desc, pr.nom limit 30) x), '[]'::jsonb),
    'boutiques', coalesce((
      select jsonb_agg(jsonb_build_object('id', x.cible, 'nom', x.nom, 'vues', x.vues) order by x.vues desc, x.nom)
        from (select w.cible, b.nom, sum(w.vues)::int as vues
                from public.visites_vues w join public.boutiques b on b.id = w.cible
               where w.genre = 'boutique' and w.jour between du_jour and au_jour
               group by w.cible, b.nom order by sum(w.vues) desc, b.nom limit 30) x), '[]'::jsonb));
end $$;
revoke all on function public.statistiques_visiteurs(date, date) from public, anon;
grant execute on function public.statistiques_visiteurs(date, date) to authenticated;
