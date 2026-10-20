-- =========================================================
-- BIZZOO 3.59.0 — Le livreur refuse une course ; la boutique voit qui
-- livre
--
--   1. la boutique voit, sur chaque commande, le livreur qui a pris la
--      course — son nom, son numéro —, s'il l'a acceptée, et le dernier
--      refus : livraison_des_commandes ;
--   2. le livreur peut refuser une course tant que le colis n'est pas
--      parti avec lui : refuser_course. La boutique voit « Commande
--      refusée par le livreur » et la confie à nouveau ; la demande se
--      rouvre aux autres livreurs ; celui qui a refusé ne la revoit plus.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- À coller APRÈS livraison-parcours.sql.
-- =========================================================

alter table public.commande_lignes add column if not exists recu_le timestamptz;
alter table public.commande_lignes add column if not exists livreur_id uuid;

-- ---------- Le livreur refuse une course (3.59.0) ----------
--
-- Une course confiée — ou prise sur la demande — se refuse tant que le
-- colis n'est pas parti (« Je l'ai prise »). Elle redevient libre : la
-- boutique voit « Commande refusée par le livreur » et la confie à
-- nouveau, et la demande se rouvre aux autres livreurs. Celui qui a
-- refusé ne la revoit plus. Chaque refus est gardé.
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

-- Les colonnes que les fonctions plus bas lisent (3.59.0).
alter table public.commande_lignes add column if not exists confirme_le timestamptz;

-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
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
             greatest(0, coalesce(c.verse, c.acompte, c.total))::numeric as paye
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


create or replace function public.candidats_course(commande text)
returns uuid[]
language plpgsql stable security definer set search_path = public as $$
declare
  boutiques text[];
  qui       uuid[];
begin
  select array_agg(distinct l.boutique_id) into boutiques
    from public.commande_lignes l
   where l.commande_id = commande and l.etat <> 'annulee' and l.boutique_id is not null;
  if boutiques is null then return '{}'; end if;
  if array_length(boutiques, 1) = 1 then
    select array_agg(p.id order by p.id) into qui
      from public.profils p
     where p.role = 'livreur' and p.actif and p.boutique_id = boutiques[1]
       and exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id);
    if qui is not null then return qui; end if;
  end if;
  select array_agg(p.id order by p.id) into qui
    from public.profils p
   where p.role = 'livreur' and p.actif and p.boutique_id is null
     and exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id);
  return coalesce(qui, '{}');
end $$;
revoke all on function public.candidats_course(text) from public, anon, authenticated;

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


create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;


create or replace function public.est_livreur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'livreur', false);
$$;


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
  if c.parts is not null and c.parts ? boutique then
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
      'indicatif', coalesce(nullif(c.client_indicatif, ''), '229')),
    'devise', coalesce(c.devise, 'FCFA'),
    'frais', coalesce(frais, 0),
    'deja_paye', greatest(0, coalesce(part, 0) - coalesce(reste, 0)),
    'a_encaisser', coalesce(reste, 0),
    -- Ce que le livreur a déclaré en remettant le colis (3.59.0).
    'encaisse', (select jsonb_build_object('montant', x.montant, 'mode', x.mode,
                         'encaisse_le', x.encaisse_le, 'remis_le', x.remis_le)
                   from public.encaissements x
                  where x.commande_id = commande and x.boutique_id = boutique));
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
  return jsonb_build_object(
    'numero', premiere -> 'numero',
    'groupee', jsonb_array_length(retraits) > 1,
    'retraits', retraits,
    'livraison', premiere -> 'livraison',
    'devise', premiere -> 'devise',
    'frais', frais, 'deja_paye', paye, 'a_encaisser', reste);
end $$;
revoke all on function public.fiche_demande(text) from public, anon, authenticated;

create or replace function public.les_superadmins() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.role = 'superadministrateur';
$$;

revoke all on function public.equipe_de(text)            from public, anon, authenticated;
revoke all on function public.enseigne_des_commandes()   from public, anon, authenticated;
revoke all on function public.les_superadmins()          from public, anon, authenticated;

create or replace function public.montant_lisible(n numeric, devise text default 'FCFA')
returns text
language sql immutable set search_path = public as $$
  select replace(to_char(coalesce(n, 0), 'FM999,999,999,990'), ',', ' ') || ' ' || coalesce(nullif(devise, ''), 'FCFA');
$$;
revoke all on function public.montant_lisible(numeric, text) from public, anon, authenticated;

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
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Seul le livreur de la course la refuse';
  end if;
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
     and n.type in ('course_confiee', 'course_acceptee', 'course_refusee');

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

-- CE QUE LA BOUTIQUE VOIT DE LA LIVRAISON de ses commandes : qui a pris
-- la course (nom, numéro), s'il l'a acceptée, et le dernier refus. Les
-- lignes de commande ne se lisent que colonne par colonne, et le livreur
-- n'en fait pas partie : c'est cette fonction qui le dit, et seulement
-- pour les boutiques que le compte tient.
create or replace function public.livraison_des_commandes(cibles text[])
returns table (commande_id text, boutique_id text,
               livreur_nom text, livreur_tel text, livreur_bizzoo boolean, recu_le timestamptz,
               refus_nom text, refus_motif text, refuse_le timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or not (public.est_equipe() or public.est_compte_enseigne()) then return; end if;
  return query
    select x.commande_id, x.boutique_id,
           coalesce(nullif(p.nom, ''), p.email, '')::text, coalesce(p.tel, '')::text,
           (p.id is not null and p.boutique_id is null), x.recu,
           coalesce(nullif(q.nom, ''), q.email, '')::text, coalesce(r.motif, '')::text, r.refuse_le
      from (select l.commande_id, l.boutique_id,
                   (array_agg(l.livreur_id) filter (where l.livreur_id is not null and l.etat <> 'annulee'))[1] as livreur,
                   min(l.recu_le) as recu
              from public.commande_lignes l
             where l.commande_id = any(cibles)
               and public.peut_agir_sur(l.boutique_id)
             group by l.commande_id, l.boutique_id) x
      left join public.profils p on p.id = x.livreur
      left join lateral (select rc.livreur_id, rc.motif, rc.refuse_le from public.refus_courses rc
                          where rc.commande_id = x.commande_id and rc.boutique_id = x.boutique_id
                          order by rc.refuse_le desc limit 1) r on true
      left join public.profils q on q.id = r.livreur_id;
end $$;
revoke all on function public.livraison_des_commandes(text[]) from public, anon;
grant execute on function public.livraison_des_commandes(text[]) to authenticated;

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
       and moi = any(public.candidats_course(c.id))
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
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Seul un livreur prend une course';
  end if;
  perform 1 from public.commandes c where c.id = commande and c.etat = 'payee' for update;
  if not found then
    raise exception 'Cette commande n''attend pas de livreur';
  end if;
  if not (moi = any(public.candidats_course(commande))) then
    raise exception 'Cette course n''est pas proposée à votre compte';
  end if;
  if exists (select 1 from public.refus_courses rc
              where rc.commande_id = commande and rc.livreur_id = moi) then
    raise exception 'Vous avez refusé cette course.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.commande_lignes l
              where l.commande_id = commande and l.etat <> 'annulee'
                and l.livreur_id is not null) then
    raise exception 'Trop tard : un autre livreur a déjà pris cette course.'
      using errcode = 'P0001';
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
  return combien;
end $$;
revoke all on function public.prendre_course(text) from public, anon;
grant execute on function public.prendre_course(text) to authenticated;

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
          coalesce(nullif(' — ' || (fiche -> 'retrait' ->> 'adresse'), ' — '), '') || E'\n' ||
        'Livrer à : ' || coalesce(nullif(fiche -> 'livraison' ->> 'nom', ''), 'le client') ||
          coalesce(nullif(' — ' || (fiche -> 'livraison' ->> 'adresse'), ' — '), ' (adresse à demander)') || E'\n' ||
        'Destinataire : +' || (fiche -> 'livraison' ->> 'indicatif') || ' ' || (fiche -> 'livraison' ->> 'tel') || E'\n' ||
        'Frais de livraison : ' || public.montant_lisible((fiche ->> 'frais')::numeric, fiche ->> 'devise') || E'\n' ||
        'Déjà payé : ' || public.montant_lisible((fiche ->> 'deja_paye')::numeric, fiche ->> 'devise') || E'\n' ||
        case when (fiche ->> 'a_encaisser')::numeric > 0
             then 'À récupérer : ' || public.montant_lisible((fiche ->> 'a_encaisser')::numeric, fiche ->> 'devise')
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
