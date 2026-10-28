-- =========================================================
-- BIZZOO Personnel : le menu Livreurs — la liste, la fiche et les
-- statistiques de chaque livreur ; l'administration peut le bloquer :
-- il ne reçoit plus de course.
--
-- À coller tel quel dans l'éditeur SQL ; il se rejoue sans dommage.
-- =========================================================

alter table public.profils add column if not exists courses_bloquees boolean not null default false;

-- (3.70.0) Lue par « fiche_course » plus bas.
alter table public.commandes add column if not exists lieu_retrait text not null default '';

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

-- ---------- Ce qui change (copies de schema.sql) ----------
create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
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

create or replace function public.peut_agir_sur(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.est_compte_enseigne()
      or (public.est_equipe() and cible is not null
          and cible = public.boutique_du_compte());
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

create or replace function public.equipe_de(cible text) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and cible is not null and p.boutique_id = cible
     and p.role in ('administrateur', 'moderateur');
$$;

create or replace function public.rh_moi() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_mon_profil() returns uuid
language sql stable security definer set search_path = public as $$
  select profil_id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_est_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and (administration or ceo));
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

create or replace function public.livreur_en_course(qui uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
     where l.livreur_id = qui and c.etat = 'payee'
       and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison'));
$$;

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
  return combien + autres;
end $$;


-- =========================================================
-- BIZZOO Personnel : le menu Livreurs
--
-- La liste de tous les livreurs (de BIZZOO et des boutiques), avec ce
-- que chacun a fait sur la période ; un clic ouvre sa fiche et ses
-- statistiques (rh_livreurs, rh_livreur_fiche). Mêmes droits que la
-- carte et le classement des livreurs : l'administration, le
-- superadministrateur, et les profils à qui Paramètres ouvre
-- « Localiser un livreur » ou les statistiques des livreurs. Les
-- montants (gains, encaissements) : l'administration seulement.
--
-- BLOQUER UN LIVREUR (rh_bloquer_livreur) : l'administration seule, motif
-- obligatoire. Il ne reçoit plus aucune course : aucune demande ne lui
-- est proposée, il ne peut plus en prendre, et personne ne peut lui en
-- confier. Ses courses pas encore parties sont retirées et repartent
-- vers les boutiques, qui les confient à un autre ; celles qu'il a déjà
-- en route, il les termine. Il garde son compte : il voit ses courses
-- passées et rend ce qu'il a encaissé. Chaque blocage et chaque
-- déblocage est gardé, avec son auteur et son motif.
-- =========================================================

-- Personne ne pose ce drapeau à la main : seulement rh_bloquer_livreur.
-- Les comptes de boutique qui modifient leurs livreurs ne le peuvent pas.
create or replace function public.profils_garde_blocage() returns trigger
language plpgsql set search_path = public as $$
begin
  if coalesce(current_setting('bizzoo.blocage', true), '') = 'oui' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.courses_bloquees := false;
  elsif new.courses_bloquees is distinct from old.courses_bloquees then
    raise exception 'Le blocage d''un livreur se décide dans BIZZOO Personnel, par l''administration';
  end if;
  return new;
end $$;
drop trigger if exists profils_garde_blocage on public.profils;
create trigger profils_garde_blocage
  before insert or update on public.profils
  for each row execute function public.profils_garde_blocage();

-- L'historique des blocages : on ne l'efface pas, personne n'y écrit
-- directement.
create table if not exists public.livreurs_blocages (
  id          bigserial primary key,
  profil_id   uuid not null references public.profils(id) on delete cascade,
  bloque      boolean not null,
  motif       text not null default '',
  par_compte  uuid,
  par_nom     text not null default '',
  le          timestamptz not null default now()
);
create index if not exists livreurs_blocages_profil on public.livreurs_blocages(profil_id, le desc);
alter table public.livreurs_blocages enable row level security;
revoke all on public.livreurs_blocages from anon, authenticated;
revoke all on sequence public.livreurs_blocages_id_seq from anon, authenticated;
grant all on public.livreurs_blocages to service_role;
grant usage, select on sequence public.livreurs_blocages_id_seq to service_role;

/** Qui ouvre le menu Livreurs. */
create or replace function public.rh_voit_livreurs() returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super() or public.rh_menu_ouvert('livreurs') or public.rh_menu_ouvert('stats_livreurs');
$$;

/** Tous les livreurs, et ce que chacun a fait sur la période. */
create or replace function public.rh_livreurs(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  d1 date := coalesce(depuis, aujourdhui - 29);
  d2 date := coalesce(jusqu, aujourdhui);
  t1 timestamptz;
  t2 timestamptz;
  argent boolean := public.rh_est_admin() or public.est_super();
begin
  if not public.rh_voit_livreurs() then
    raise exception 'Votre compte n''a pas accès aux livreurs';
  end if;
  if d2 < d1 then
    raise exception 'La fin de la période précède son début';
  end if;
  if d2 - d1 > 1100 then
    raise exception 'Choisissez une période de trois ans au plus';
  end if;
  t1 := d1::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (d2 + 1)::timestamp at time zone 'Africa/Porto-Novo';
  return jsonb_build_object(
    'periode', jsonb_build_object('depuis', d1, 'jusqu', d2),
    'droits', jsonb_build_object('argent', argent, 'bloquer', argent),
    'livreurs', (select coalesce(jsonb_agg(x.j order by x.bloque, x.courses desc, x.nom), '[]') from (
      select p.courses_bloquees as bloque, k.courses,
             coalesce(nullif(btrim(p.nom), ''), p.email, 'Livreur') as nom,
             jsonb_build_object(
               'id', p.id,
               'nom', coalesce(nullif(btrim(p.nom), ''), p.email, 'Livreur'),
               'tel', coalesce(p.tel, ''),
               'vehicule', coalesce(p.vehicule, 'moto'),
               'boutique', (select b.nom from public.boutiques b where b.id = p.boutique_id),
               'actif', p.actif,
               'valide', exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id),
               'bloque', p.courses_bloquees,
               'en_course', public.livreur_en_course(p.id),
               'courses', k.courses,
               'livrees', k.livrees,
               'refus', (select count(*) from public.refus_courses r
                          where r.livreur_id = p.id and r.refuse_le >= t1 and r.refuse_le < t2),
               'derniere', (select max(c.paye_le) from public.commande_lignes l
                              join public.commandes c on c.id = l.commande_id
                             where l.livreur_id = p.id and c.etat = 'payee'),
               'gains', case when argent then
                 (select coalesce(sum(g.montant), 0) from public.gains_livreurs g
                   where g.livreur_id = p.id and g.credite_le >= t1 and g.credite_le < t2) end) as j
        from public.profils p
        cross join lateral (
          select count(distinct l.commande_id) as courses,
                 count(distinct l.commande_id) filter (where l.etat = 'remise') as livrees
            from public.commande_lignes l
            join public.commandes c on c.id = l.commande_id
           where l.livreur_id = p.id and c.etat = 'payee' and c.paye_le >= t1 and c.paye_le < t2) k
       where p.role = 'livreur') x));
end $$;

/** La fiche d'un livreur : qui il est, ses chiffres, ses courses, ses
    refus, et l'historique de ses blocages. */
create or replace function public.rh_livreur_fiche(livreur uuid, depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  d1 date := coalesce(depuis, aujourdhui - 29);
  d2 date := coalesce(jusqu, aujourdhui);
  t1 timestamptz;
  t2 timestamptz;
  argent boolean := public.rh_est_admin() or public.est_super();
  p public.profils;
  chiffres jsonb;
  courses jsonb;
begin
  if not public.rh_voit_livreurs() then
    raise exception 'Votre compte n''a pas accès aux livreurs';
  end if;
  if d2 < d1 then
    raise exception 'La fin de la période précède son début';
  end if;
  if d2 - d1 > 1100 then
    raise exception 'Choisissez une période de trois ans au plus';
  end if;
  select * into p from public.profils x where x.id = livreur and x.role = 'livreur';
  if not found then
    raise exception 'Livreur introuvable';
  end if;
  t1 := d1::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (d2 + 1)::timestamp at time zone 'Africa/Porto-Novo';

  -- Une course = une commande qu'il porte. Son étape : la moins avancée
  -- de ses articles encore valables.
  with k as (
    select c.id, c.numero, c.paye_le,
           min(l.recu_le) as recu_le, max(l.confirme_le) as confirme_le,
           coalesce((array['nouvelle', 'vue', 'preparee', 'en_livraison', 'remise'])[
             min(array_position(array['nouvelle', 'vue', 'preparee', 'en_livraison', 'remise'], l.etat))],
             'annulee') as etat,
           string_agg(distinct b.nom, ', ') as boutiques
      from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
      left join public.boutiques b on b.id = l.boutique_id
     where l.livreur_id = livreur and c.etat = 'payee' and c.paye_le >= t1 and c.paye_le < t2
     group by c.id, c.numero, c.paye_le
  )
  select jsonb_build_object(
           'courses', count(*),
           'livrees', count(*) filter (where etat = 'remise'),
           'en_cours', count(*) filter (where etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')),
           'annulees', count(*) filter (where etat = 'annulee'),
           'confirmees', count(*) filter (where confirme_le is not null),
           'delai_prise_minutes', round(avg(extract(epoch from (recu_le - paye_le)) / 60)
                                         filter (where recu_le >= paye_le)),
           'delai_livraison_heures', round((avg(extract(epoch from (confirme_le - paye_le)) / 3600)
                                         filter (where confirme_le >= paye_le))::numeric, 1)),
         coalesce(jsonb_agg(jsonb_build_object(
           'commande', id, 'numero', numero, 'paye_le', paye_le, 'boutiques', boutiques,
           'etat', etat, 'recu_le', recu_le, 'confirme_le', confirme_le,
           'gain', case when argent then
             (select sum(g.montant) from public.gains_livreurs g
               where g.commande_id = k.id and g.livreur_id = livreur) end)
           order by paye_le desc), '[]')
    into chiffres, courses
    from k;

  chiffres := chiffres || jsonb_build_object(
    'refus', (select count(*) from public.refus_courses r
               where r.livreur_id = livreur and r.refuse_le >= t1 and r.refuse_le < t2),
    'gains', case when argent then
      (select coalesce(sum(g.montant), 0) from public.gains_livreurs g
        where g.livreur_id = livreur and g.credite_le >= t1 and g.credite_le < t2) end,
    'encaisse', case when argent then
      (select coalesce(sum(e.montant), 0) from public.encaissements e
        where e.livreur_id = livreur and e.encaisse_le >= t1 and e.encaisse_le < t2) end,
    'contestes', (select count(*) from public.encaissements e
                   where e.livreur_id = livreur and e.conteste_le is not null
                     and e.encaisse_le >= t1 and e.encaisse_le < t2));

  return jsonb_build_object(
    'periode', jsonb_build_object('depuis', d1, 'jusqu', d2),
    'droits', jsonb_build_object('argent', argent, 'bloquer', argent),
    'livreur', jsonb_build_object(
      'id', p.id,
      'nom', coalesce(nullif(btrim(p.nom), ''), p.email, 'Livreur'),
      'tel', coalesce(p.tel, ''),
      'vehicule', coalesce(p.vehicule, 'moto'),
      'boutique', (select b.nom from public.boutiques b where b.id = p.boutique_id),
      'actif', p.actif,
      'valide', exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id),
      'bloque', p.courses_bloquees,
      'cree_le', p.cree_le,
      'en_course', public.livreur_en_course(p.id),
      'position', (select jsonb_build_object('adresse', pl.adresse, 'le', pl.enregistre_le)
                     from public.positions_livreurs pl where pl.profil_id = p.id)),
    'chiffres', chiffres,
    'courses', (select coalesce(jsonb_agg(x order by x ->> 'paye_le' desc), '[]')
                  from (select x from jsonb_array_elements(courses) x limit 50) y),
    'refus', (select coalesce(jsonb_agg(jsonb_build_object(
                 'numero', c.numero, 'boutique', b.nom, 'motif', r.motif, 'le', r.refuse_le)
                 order by r.refuse_le desc), '[]')
                from (select * from public.refus_courses r0
                       where r0.livreur_id = livreur and r0.refuse_le >= t1 and r0.refuse_le < t2
                       order by r0.refuse_le desc limit 20) r
                left join public.commandes c on c.id = r.commande_id
                left join public.boutiques b on b.id = r.boutique_id),
    'blocages', (select coalesce(jsonb_agg(jsonb_build_object(
                   'bloque', x.bloque, 'motif', x.motif, 'par', x.par_nom, 'le', x.le)
                   order by x.le desc, x.id desc), '[]')
                  from public.livreurs_blocages x where x.profil_id = livreur));
end $$;

-- (3.70.0) Empruntée plus bas, recopiée telle quelle.
create or replace function public.reproposer_course(commande text)
returns int
language plpgsql security definer set search_path = public as $$
declare
  f   jsonb;
  qui uuid[];
  c   record;
begin
  select c0.numero, c0.etat, c0.paye_le into c from public.commandes c0 where c0.id = commande;
  if not found or c.etat <> 'payee' then return 0; end if;
  if exists (select 1 from public.commande_lignes l
              where l.commande_id = commande and l.etat <> 'annulee'
                and (l.livreur_id is not null or l.etat in ('en_livraison', 'remise'))) then
    return -1;
  end if;
  -- Plus vieille, elle n'apparaîtrait sur l'écran d'aucun livreur.
  if c.paye_le is null or c.paye_le <= now() - interval '7 days' then return 0; end if;
  select coalesce(array_agg(x), '{}') into qui
    from unnest(public.candidats_course(commande)) as x
   where not exists (select 1 from public.refus_courses r
                      where r.commande_id = commande and r.livreur_id = x);
  if array_length(qui, 1) is null then return 0; end if;
  f := public.fiche_demande(commande);
  if f is null then return 0; end if;
  -- Une demande ne part qu'une fois par livreur et par commande : les
  -- anciennes sont mises de côté (« …_avant_<n> »), comme au refus.
  update public.notifications n
     set type = n.type || '_avant_' || n.id, lue_le = coalesce(n.lue_le, now())
   where n.commande_id = commande
     and n.type in ('course_proposee', 'course_prise')
     and n.destinataire = any(qui);
  return public.notifier(qui, 'course_proposee',
    'Course à reprendre — ' || coalesce(c.numero, ''),
    public.texte_demande(f),
    '#/livraisons', commande, null, true);
end $$;
revoke all on function public.reproposer_course(text) from public, anon, authenticated;

/** Bloquer ou débloquer un livreur : l'administration seule. Bloqué, il
    ne reçoit plus de course ; ses courses pas encore parties retournent
    aux boutiques. Rend le nombre de parts de commande retirées. */
create or replace function public.rh_bloquer_livreur(livreur uuid, bloquer boolean, motif text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  pourquoi text := left(btrim(coalesce(motif, '')), 300);
  p        public.profils;
  auteur   text;
  porteur  text;
  c        record;
  parts    record;
  annonce  boolean;
  liberees int := 0;
begin
  if not (public.rh_est_admin() or public.est_super()) then
    raise exception 'Seule l''administration bloque ou débloque un livreur';
  end if;
  if bloquer is null then
    raise exception 'Bloquer ou débloquer ?';
  end if;
  select * into p from public.profils x where x.id = livreur and x.role = 'livreur' for update;
  if not found then
    raise exception 'Livreur introuvable';
  end if;
  if p.courses_bloquees = bloquer then
    raise exception '%', case when bloquer then 'Ce livreur est déjà bloqué' else 'Ce livreur n''est pas bloqué' end;
  end if;
  if bloquer and length(pourquoi) < 3 then
    raise exception 'Dites pourquoi vous bloquez ce livreur';
  end if;
  select nullif(btrim(e.prenoms || ' ' || e.nom), '') into auteur
    from public.rh_employes e where e.id = public.rh_moi();
  auteur := coalesce(auteur, (select nullif(btrim(x.nom), '') from public.profils x where x.id = auth.uid()),
                     'Superadministrateur');
  porteur := coalesce(nullif(btrim(p.nom), ''), 'Le livreur');

  perform set_config('bizzoo.blocage', 'oui', true);
  update public.profils set courses_bloquees = bloquer where id = livreur;
  perform set_config('bizzoo.blocage', '', true);
  insert into public.livreurs_blocages (profil_id, bloque, motif, par_compte, par_nom)
  values (livreur, bloquer, pourquoi, auth.uid(), auteur);

  if not bloquer then
    perform public.notifier(array[livreur], 'livreur_debloque', 'Courses rétablies',
      'BIZZOO vous propose de nouveau des courses.', '#/livraisons', null, null, true);
    return jsonb_build_object('liberees', 0);
  end if;

  -- SES COURSES PAS ENCORE PARTIES retournent aux boutiques, comme s'il
  -- les avait refusées (refuser_course) — sans les compter comme ses refus.
  for c in
    select distinct l.commande_id, cm.numero, cm.client_id
      from public.commande_lignes l
      join public.commandes cm on cm.id = l.commande_id
     where l.livreur_id = livreur and l.etat in ('nouvelle', 'vue', 'preparee')
  loop
    select exists (select 1 from public.commande_lignes l
                    where l.commande_id = c.commande_id and l.livreur_id = livreur and l.recu_le is not null)
      into annonce;
    -- Une nouvelle course, de nouvelles nouvelles (voir refuser_course).
    update public.notifications n
       set type = n.type || '_avant_' || n.id
     where n.commande_id = c.commande_id
       and n.type in ('course_confiee', 'course_acceptee', 'course_refusee');
    perform set_config('bizzoo.livraison', 'oui', true);
    perform set_config('bizzoo.refus', 'oui', true);
    for parts in
      with retirees as (
        update public.commande_lignes l
           set livreur_id = null, recu_le = null
         where l.commande_id = c.commande_id and l.livreur_id = livreur
           and l.etat in ('nouvelle', 'vue', 'preparee')
        returning l.boutique_id
      )
      select distinct boutique_id from retirees
    loop
      liberees := liberees + 1;
      perform public.notifier(public.equipe_de(parts.boutique_id), 'course_refusee',
        'Course à confier de nouveau — ' || coalesce(c.numero, ''),
        porteur || ' ne prend plus de course pour BIZZOO. Confiez-la à un autre livreur.',
        '#/commandes/' || c.commande_id, c.commande_id, parts.boutique_id, true);
    end loop;
    perform set_config('bizzoo.refus', '', true);
    perform set_config('bizzoo.livraison', '', true);
    -- (3.70.0) Et la course repart aux autres livreurs, avec sonnerie.
    perform public.reproposer_course(c.commande_id);
    if annonce and c.client_id is not null then
      perform public.notifier(array[c.client_id], 'course_refusee',
        'Votre livreur a changé',
        'Commande ' || coalesce(c.numero, '') || ' : ' || porteur ||
          ' ne peut pas la livrer. Un autre livreur va la prendre ; vous recevrez son nom et son numéro.',
        '#/commande/' || c.commande_id, c.commande_id, null, true);
    end if;
  end loop;

  perform public.notifier(array[livreur], 'livreur_bloque', 'Courses suspendues',
    'BIZZOO ne vous propose plus de course pour le moment. Rapprochez-vous de BIZZOO.' ||
      case when liberees > 0 then ' Vos courses pas encore parties ont été retirées.' else '' end,
    '#/livraisons', null, null, true);
  return jsonb_build_object('liberees', liberees);
end $$;

revoke all on function public.profils_garde_blocage() from public, anon, authenticated;
revoke all on function public.rh_voit_livreurs() from public, anon;
grant execute on function public.rh_voit_livreurs() to authenticated, service_role;
revoke all on function public.rh_livreurs(date, date) from public, anon;
grant execute on function public.rh_livreurs(date, date) to authenticated, service_role;
revoke all on function public.rh_livreur_fiche(uuid, date, date) from public, anon;
grant execute on function public.rh_livreur_fiche(uuid, date, date) to authenticated, service_role;
revoke all on function public.rh_bloquer_livreur(uuid, boolean, text) from public, anon;
grant execute on function public.rh_bloquer_livreur(uuid, boolean, text) to authenticated, service_role;
