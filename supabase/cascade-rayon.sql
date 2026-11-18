-- =========================================================
-- BIZZOO 4.7.0 — La course : les plus proches d'abord, puis ceux à moins
-- de 5 km, et tout le monde seulement en dernier recours
--
--   Depuis la 3.70.0, une commande payée sonne chez le livreur le plus
--   proche du retrait, puis le suivant, puis chez TOUS. Plus d'une fois sur
--   deux, elle finissait chez tous — y compris des livreurs très loin.
--
--   1. Le premier cercle s'élargit : les CINQ plus proches (c'était
--      trois), 45 secondes chacun (c'était 30).
--   2. Une étape de plus avant « tous » : les livreurs à moins de 5 km du
--      retrait (position récente), et ceux de la boutique, seuls pendant
--      60 secondes. Personne dans le rayon : on n'attend pas.
--   3. Tous les autres ne sont prévenus qu'ensuite.
--
--   Réglages (table « cascade_reglage », éditeur SQL) : rangs, delai_s,
--   rayon_km (0 : pas d'étape « rayon »), delai_rayon_s.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- (4.1.0) Empruntées plus bas, recopiées telles quelles.
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

create or replace function public.montant_lisible(n numeric, devise text default 'FCFA')
returns text
language sql immutable set search_path = public as $$
  select replace(to_char(coalesce(n, 0), 'FM999,999,999,990'), ',', ' ') || ' ' || coalesce(nullif(devise, ''), 'FCFA');
$$;
revoke all on function public.montant_lisible(numeric, text) from public, anon, authenticated;

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

create or replace function public.livreur_en_course(qui uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
     where l.livreur_id = qui and c.etat = 'payee'
       and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison'));
$$;
revoke all on function public.livreur_en_course(uuid) from public, anon, authenticated;

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
    -- (3.73.0) La touche ouvre CETTE course, pas la liste.
    '#/livraisons/' || commande, commande, null, true);
end $$;
revoke all on function public.alerter_course(text, uuid[], text, text) from public, anon, authenticated;

alter table public.cascade_reglage add column if not exists rayon_km numeric not null default 5
  check (rayon_km between 0 and 100);
alter table public.cascade_reglage add column if not exists delai_rayon_s int not null default 60
  check (delai_rayon_s between 10 and 600);
alter table public.cascade_reglage alter column rangs set default 5;
alter table public.cascade_reglage alter column delai_s set default 45;
-- Un réglage déjà changé à la main n'est pas touché.
update public.cascade_reglage set rangs = 5, delai_s = 45 where id = 1 and rangs = 3 and delai_s = 30;

alter table public.courses_cascade add column if not exists rayon boolean not null default false;

create or replace function public.livreurs_rayon_course(commande text, km numeric)
returns uuid[]
language plpgsql stable security definer set search_path = public as $$
declare
  pt     record;
  fraich int;
begin
  select * into pt from public.point_retrait_course(commande);
  if pt.lat is null or coalesce(km, 0) <= 0 then return '{}'; end if;
  select coalesce(r.fraicheur_min, 60) into fraich from public.cascade_reglage r where r.id = 1;
  return coalesce((
    select array_agg(distinct x.id) from (
      -- Les livreurs de la boutique elle-même (« candidats_course » rend
      -- ceux de BIZZOO quand elle n'en a pas : ceux-là passent par le rayon).
      select c.id
        from unnest(public.candidats_course(commande)) as c(id)
        join public.profils p on p.id = c.id and p.boutique_id is not null
      union
      select c.id
        from unnest(public.tous_livreurs_course(commande)) as c(id)
        join public.positions_livreurs pl on pl.profil_id = c.id
       where pl.enregistre_le > now() - make_interval(mins => coalesce(fraich, 60))
         and 2 * 6371 * asin(least(1, sqrt(
               sin(radians(pl.latitude - pt.lat) / 2) ^ 2
               + cos(radians(pt.lat)) * cos(radians(pl.latitude))
                 * sin(radians(pl.longitude - pt.lng) / 2) ^ 2))) <= km) x), '{}');
end $$;
revoke all on function public.livreurs_rayon_course(text, numeric) from public, anon, authenticated;

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

  -- (4.7.0) Personne (plus) dans l'ordre : d'abord ceux qui sont à moins
  -- de « rayon_km » du retrait, seuls, pendant « delai_rayon_s » — un
  -- livreur trop loin n'est dérangé qu'en dernier recours. Personne de
  -- nouveau dans le rayon : on n'attend pas.
  if coalesce(r.actif, true) and not k.rayon and coalesce(r.rayon_km, 0) > 0 then
    update public.courses_cascade x
       set etape = k.etape, rayon = true, prochaine = now() + make_interval(secs => coalesce(r.delai_rayon_s, 60))
     where x.commande_id = commande;
    n := public.alerter_course(commande, public.livreurs_rayon_course(commande, r.rayon_km), titre,
      'Vous êtes à moins de ' || trim(to_char(r.rayon_km, 'FM990D9'), '.,') || ' km du retrait : le premier qui touche « Commande reçue » la garde.');
    if n > 0 then return n; end if;
  end if;

  -- Personne non plus : à tous les livreurs de BIZZOO. Cascade
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
     set ordre = excluded.ordre, etape = 0, tous = false, rayon = false, alertes = '{}',
         prochaine = null, lancee_le = now(), reprise = excluded.reprise;
  return public.avancer_cascade(commande);
end $$;
revoke all on function public.lancer_cascade(text, boolean) from public, anon, authenticated;
