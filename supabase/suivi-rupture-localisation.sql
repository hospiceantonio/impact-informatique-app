-- =========================================================
-- BIZZOO 3.75.0 — Trois demandes de l'équipe
--
--   1. Commande en attente dont un produit est parti en rupture : la base
--      dit lesquels (manquants_commande), la fonction de paiement refuse
--      d'encaisser, l'application l'explique au client et propose de
--      refaire son panier sans eux.
--   2. Suivi des commandes (Personnel) : le temps de préparation de chaque
--      marchand, de « Commande vue » à « Préparée », jugé sur le délai
--      réglé (20 min convenues).
--   3. Le livreur coupe sa localisation pendant une course : la base le
--      sait (position_livreur reçoit l'état de la localisation et l'âge de
--      la mesure) ; chaque minute, alerter_localisations fait sonner BIZZOO
--      et prévient le livreur. Une course annulée après « Commande reçue »
--      le dit dans son titre.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
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

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
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

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
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

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
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

create or replace function public.montant_lisible(n numeric, devise text default 'FCFA')
returns text
language sql immutable set search_path = public as $$
  select replace(to_char(coalesce(n, 0), 'FM999,999,999,990'), ',', ' ') || ' ' || coalesce(nullif(devise, ''), 'FCFA');
$$;
revoke all on function public.montant_lisible(numeric, text) from public, anon, authenticated;

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
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

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
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

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
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

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
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

create or replace function public.rh_cle(t text) returns text
language sql immutable set search_path = public as $$
  select btrim(regexp_replace(
           translate(lower(coalesce(t, '')),
                     'àâäáãéèêëíìîïóòôöõúùûüçñ''’-_/.,;:()',
                     'aaaaaeeeeiiiiooooouuuucn            '),
           '\s+', ' ', 'g'));
$$;

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
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

create or replace function public.reproposer_course(commande text)
returns int
language plpgsql security definer set search_path = public as $$
begin
  -- (3.70.0) Comme au paiement : la cascade repart du plus proche (ceux
  -- qui l'ont refusée exceptés), puis à tous les livreurs de BIZZOO.
  return public.lancer_cascade(commande, true);
end $$;
revoke all on function public.reproposer_course(text) from public, anon, authenticated;

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

create or replace function public.rh_statut_libelle(rang int) returns text
language sql immutable set search_path = public as $$
  select case rang
    when 0 then 'En attente de paiement'
    when 1 then 'Nouvelle commande'
    when 2 then 'Confirmée'
    when 3 then 'Commande préparée'
    when 4 then 'Colis récupéré'
    when 5 then 'En cours de livraison'
    when 6 then 'Livraison effectuée — confirmation en attente'
    when 8 then 'Livré et confirmé'
    when 9 then 'Livraison échouée'
    when 10 then 'Livraison contestée'
    when 11 then 'Annulée'
    when 12 then 'Retour en cours'
    when 13 then 'Retournée au marchand'
    when 14 then 'Clôturée'
    when 15 then 'Paiement échoué'
    else '' end;
$$;

create or replace function public.rh_statut_ligne(etat text, confirme timestamptz, terrain text, contestee boolean)
returns int
language sql immutable set search_path = public as $$
  select case
    when etat = 'annulee' then 11
    when terrain = 'retournee' then 13
    when terrain = 'retour_en_cours' then 12
    when terrain = 'echouee' then 9
    when contestee then 10
    when confirme is not null then 8
    when etat = 'remise' then 6
    when etat = 'en_livraison' then 5
    when terrain = 'recupere' then 4
    when etat = 'preparee' then 3
    when etat = 'vue' then 2
    else 1 end;
$$;

create or replace function public.rh_zone_de(adresse text) returns text
language sql stable security definer set search_path = public as $$
  select z.nom || case when z.type <> 'commune' and z.commune <> '' and z.commune <> z.nom
                       then ' (' || z.commune || ')' else '' end
    from public.rh_zones z
   where length(public.rh_cle(z.nom)) >= 3
     and position(' ' || public.rh_cle(z.nom) || ' ' in ' ' || public.rh_cle(adresse) || ' ') > 0
   order by case z.type when 'ajout' then 0 when 'quartier' then 1 when 'village' then 1
                        when 'arrondissement' then 2 else 3 end,
            length(z.nom) desc
   limit 1;
$$;

create or replace function public.manquants_de_commande(cible text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'produit_id', x.pid, 'nom', x.nom, 'demande', x.q, 'reste', x.reste) order by x.nom), '[]'::jsonb)
    from (
      select l.produit_id as pid, min(coalesce(nullif(p.nom, ''), l.nom)) as nom, sum(l.quantite)::int as q,
             case when p.id is null or coalesce(p.masque, false) then 0
                  else greatest(coalesce(p.stock, 0), 0) end as reste,
             (p.id is null or coalesce(p.masque, false)) as retire,
             (coalesce(p.sur_commande, false) or (p.appro_le is not null and p.appro_le >= current_date)) as sans_plafond
        from public.commande_lignes l
        left join public.produits p on p.id = l.produit_id
       where l.commande_id = cible and l.etat <> 'annulee'
       group by l.produit_id, p.id, p.masque, p.stock, p.sur_commande, p.appro_le
    ) x
   where x.retire or (not x.sans_plafond and x.q > x.reste);
$$;
revoke all on function public.manquants_de_commande(text) from public, anon, authenticated;

create or replace function public.manquants_commande(cible text, tel text default '')
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.commandes%rowtype;
begin
  select * into c from public.commandes x
   where x.id = coalesce(cible, '') and not x.compte_supprime
     and ((auth.uid() is not null and x.client_id = auth.uid())
          or (coalesce(tel, '') <> '' and x.client_tel = regexp_replace(tel, '\D', '', 'g')));
  if not found or c.etat <> 'a_payer' then
    return jsonb_build_object('manquants', '[]'::jsonb, 'autres', '[]'::jsonb);
  end if;
  return jsonb_build_object(
    'manquants', public.manquants_de_commande(c.id),
    'autres', coalesce((select jsonb_agg(jsonb_build_object('produit_id', y.pid, 'quantite', y.q) order by y.pid)
                          from (select l.produit_id as pid, sum(l.quantite)::int as q
                                  from public.commande_lignes l
                                 where l.commande_id = c.id and l.etat <> 'annulee' and l.produit_id is not null
                                   and not exists (select 1 from jsonb_array_elements(public.manquants_de_commande(c.id)) m
                                                    where m ->> 'produit_id' = l.produit_id)
                                 group by l.produit_id) y), '[]'::jsonb));
end $$;
revoke all on function public.manquants_commande(text, text) from public;
grant execute on function public.manquants_commande(text, text) to anon, authenticated;

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
    'tentative_le', c.tentative_le,
    -- (3.75.0) Les produits partis en rupture depuis la commande : la
    -- fonction refuse alors de faire payer ce qu'on ne livrera pas.
    'manquants', case when c.etat = 'a_payer' then public.manquants_de_commande(c.id) else '[]'::jsonb end);
end $$;
revoke all on function public.commande_pour_paiement(text, text)
  from public, anon, authenticated;

create or replace function public.rh_suivi_donnees(t1 timestamptz, t2 timestamptz, une text default null)
returns setof jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r public.rh_reglages_suivi;
  maintenant timestamptz := now();
  -- Les seuils de la veille et des encaissements (personnel-controles.sql)
  -- se lisent par to_jsonb : sur une base où leurs colonnes manquent
  -- encore, la valeur de départ vaut, au lieu d'une erreur.
  v_prise_min int;
  v_position_min int;
  v_momopay_h int;
begin
  select * into r from public.rh_reglages_suivi where id;
  v_prise_min := coalesce((to_jsonb(r) ->> 'prise_course_min')::int, 30);
  v_position_min := coalesce((to_jsonb(r) ->> 'position_min')::int, 15);
  v_momopay_h := coalesce((to_jsonb(r) ->> 'momopay_h')::int, 48);
  return query
  with cmd as (
    select c.* from public.commandes c
     where (une is not null and c.id = une)
        or (une is null and c.cree_le >= t1 and c.cree_le < t2)
     order by c.cree_le desc
     limit 2000
  ),
  lig as (
    select l.*, b.nom as boutique_nom, coalesce(nullif(b.tel, ''), '') as boutique_tel,
           coalesce(nullif(pl.nom, ''), pl.email) as livreur_nom, coalesce(pl.tel, '') as livreur_tel,
           s.statut as terrain, s.motif as terrain_motif,
           exists (select 1 from public.reclamations rc
                    where rc.commande_id = l.commande_id and rc.sujet = 'non_recu'
                      and (rc.boutique_id is null or rc.boutique_id = l.boutique_id)
                      and rc.etat not in ('resolue', 'tranchee')) as contestee,
           (select min(j.le) from public.rh_journal_lignes j
             where j.ligne_id = l.id and j.quoi = 'etat' and j.valeur = 'vue') as vue_le,
           (select min(j.le) from public.rh_journal_lignes j
             where j.ligne_id = l.id and j.quoi = 'etat' and j.valeur = 'preparee') as preparee_le,
           (select min(j.le) from public.rh_journal_lignes j
             where j.ligne_id = l.id and j.quoi = 'etat' and j.valeur = 'remise') as remise_le
      from public.commande_lignes l
      join cmd c on c.id = l.commande_id
      left join public.boutiques b on b.id = l.boutique_id
      left join public.profils pl on pl.id = l.livreur_id
      left join public.rh_suivi_lignes s on s.ligne_id = l.id
  ),
  lig2 as (
    select x.*, public.rh_statut_ligne(x.etat, x.confirme_le, x.terrain, x.contestee) as rang
      from lig x
  )
  select jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'cree_le', c.cree_le, 'paye_le', c.paye_le, 'etat', c.etat,
    -- (3.68.0) D'où vient la commande : passée dans l'application, ou prise
    -- sur WhatsApp et saisie par l'équipe (« Faire livrer »). Lue par
    -- « to_jsonb » : une base sans la colonne répond « Depuis APP ».
    'source', case when to_jsonb(c) ->> 'origine' = 'whatsapp' then 'Par whatsapp' else 'Depuis APP' end,
    'client', jsonb_build_object('nom', c.client_nom,
                                 'tel', btrim(case when coalesce(c.client_indicatif, '') <> '' and c.client_indicatif <> '229'
                                                   then '+' || c.client_indicatif || ' ' else '' end || coalesce(c.client_tel, '')),
                                 'adresse', c.client_adresse,
                                 'zone', coalesce(nullif(sc.zone, ''), public.rh_zone_de(c.client_adresse), ''),
                                 'zone_corrigee', coalesce(sc.zone, '') <> ''),
    'lignes', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', x.id, 'boutique_id', x.boutique_id, 'boutique', coalesce(x.boutique_nom, x.boutique_id),
                 'boutique_tel', x.boutique_tel, 'nom', x.nom, 'code', x.code, 'quantite', x.quantite,
                 'prix', x.prix, 'etat', x.etat, 'rang', x.rang, 'statut', public.rh_statut_libelle(x.rang),
                 'terrain', x.terrain, 'terrain_motif', coalesce(x.terrain_motif, ''),
                 'livreur', x.livreur_nom, 'livreur_tel', x.livreur_tel, 'livreur_id', x.livreur_id,
                 'confirme_le', x.confirme_le, 'vue_le', x.vue_le, 'remise_le', x.remise_le,
                 -- (3.75.0) Quand le marchand a touché « Préparée ».
                 'preparee_le', x.preparee_le)
               order by x.boutique_nom, x.nom) from lig2 x where x.commande_id = c.id), '[]'),
    -- (3.75.0) LE TEMPS DE PRÉPARATION de chaque marchand : de « Commande
    -- vue » à « Préparée » (tous ses articles), en minutes ; le délai réglé
    -- (preparation_min, 20 min convenues avec les marchands) pour juger.
    'preparation', coalesce((select jsonb_agg(jsonb_build_object(
                     'boutique', coalesce(y.bn, y.bid), 'vue_le', y.v, 'preparee_le', y.p,
                     'minutes', case when y.v is not null and y.p is not null
                                     then greatest(0, round(extract(epoch from (y.p - y.v)) / 60))::int end)
                   order by y.bn)
                   from (select x.boutique_id as bid, min(x.boutique_nom) as bn, min(x.vue_le) as v,
                                case when bool_and(x.preparee_le is not null) then max(x.preparee_le) end as p
                           from lig2 x where x.commande_id = c.id and x.etat <> 'annulee'
                          group by x.boutique_id) y), '[]'),
    'preparation_seuil_min', coalesce(r.preparation_min, r.preparation_h * 60),
    'articles', coalesce((select string_agg(x.quantite || ' × ' || x.nom
                                            || case when x.etat = 'annulee' then ' (annulé)' else '' end, ' ; '
                                            order by x.boutique_nom, x.nom)
                            from lig2 x where x.commande_id = c.id), ''),
    'marchands', coalesce((select string_agg(distinct coalesce(x.boutique_nom, x.boutique_id)
                                             || case when x.boutique_tel <> '' then ' / ' || x.boutique_tel else '' end, ' ; ')
                             from lig2 x where x.commande_id = c.id), ''),
    'livreurs', coalesce((select string_agg(distinct x.livreur_nom
                                            || case when x.livreur_tel <> '' then ' / ' || x.livreur_tel else '' end, ' ; ')
                            from lig2 x where x.commande_id = c.id and x.livreur_nom is not null), ''),
    'frais', coalesce(c.frais_livraison, 0), 'total', c.total,
    'reste', case when c.etat = 'payee' then
               coalesce((select sum(greatest(0, rr.a_encaisser - coalesce(e.montant, 0)))
                           from public.restes_par_boutique(c.id) rr
                           left join public.encaissements e on e.commande_id = c.id and e.boutique_id = rr.boutique_id), 0)
             else 0 end,
    'rang', st.rang, 'statut', public.rh_statut_libelle(st.rang),
    'confirmation', case
       when not exists (select 1 from lig2 x where x.commande_id = c.id and x.etat <> 'annulee') then '—'
       when not exists (select 1 from lig2 x where x.commande_id = c.id and x.etat <> 'annulee' and x.confirme_le is null) then 'Oui'
       when exists (select 1 from lig2 x where x.commande_id = c.id and x.confirme_le is not null) then 'Partielle'
       else 'Non' end,
    -- La durée du document : du « vu » du marchand au « je l'ai reçu » du client.
    'delai_h', (select round(max(extract(epoch from (x.confirme_le - x.vue_le)) / 3600)::numeric, 1)
                  from lig2 x where x.commande_id = c.id and x.confirme_le is not null and x.vue_le is not null),
    'observations', coalesce(sc.observations, ''),
    'incidents_ouverts', (select count(*) from public.rh_incidents i where i.commande_id = c.id and i.resolu_le is null),
    'cloturee_le', sc.cloturee_le,
    'alertes', case when c.etat <> 'payee' or sc.cloturee_le is not null then '[]'::jsonb else (
      select coalesce(jsonb_agg(a), '[]') from (
        select 'non_vue' as a where exists (select 1 from lig2 x where x.commande_id = c.id and x.etat = 'nouvelle')
                                 and maintenant - c.paye_le > make_interval(hours => r.vue_h)
        union all
        select 'retard_preparation' where exists (select 1 from lig2 x where x.commande_id = c.id and x.etat = 'vue'
                                 -- (3.72.0) En minutes quand il est réglé ainsi.
                                 and maintenant - coalesce(x.vue_le, c.paye_le)
                                     > make_interval(mins => coalesce(r.preparation_min, r.preparation_h * 60)))
        union all
        select 'retard_livraison' where exists (select 1 from lig2 x where x.commande_id = c.id and x.rang < 6)
                                 and maintenant - c.paye_le > make_interval(hours => r.livraison_h)
        union all
        select 'sans_confirmation' where exists (select 1 from lig2 x where x.commande_id = c.id and x.rang = 6
                                 and maintenant - coalesce(x.remise_le, c.paye_le) > make_interval(hours => r.confirmation_h))
        union all
        select 'contestee' where exists (select 1 from lig2 x where x.commande_id = c.id and x.contestee)
        union all
        select 'echec' where exists (select 1 from lig2 x where x.commande_id = c.id and x.rang in (9, 12))
        union all
        select 'incident' where exists (select 1 from public.rh_incidents i where i.commande_id = c.id and i.resolu_le is null)
        union all
        select 'refus_course' where exists (select 1 from public.refus_courses f where f.commande_id = c.id)
        union all
        select 'encaissement_conteste' where exists (select 1 from public.encaissements e
                                                     where e.commande_id = c.id and e.conteste_le is not null)
        union all
        -- Payée (ou préparée) et personne n'a pris la course : la demande
        -- part à tous les livreurs au paiement, elle devrait trouver preneur.
        select 'course_sans_livreur' where exists (select 1 from lig2 x where x.commande_id = c.id
                                 and x.etat in ('nouvelle', 'vue', 'preparee') and x.livreur_id is null
                                 and maintenant - coalesce(x.preparee_le, c.paye_le) > make_interval(mins => v_prise_min))
        union all
        -- En route, et son téléphone n'envoie plus rien : compté depuis sa
        -- dernière position, ou depuis qu'il a accepté la course.
        select 'livreur_muet' where exists (select 1 from lig2 x
                                 left join public.positions_livreurs pp on pp.profil_id = x.livreur_id
                                 where x.commande_id = c.id and x.etat = 'en_livraison' and x.livreur_id is not null
                                   -- (3.75.0) La position MESURÉE (« fix_le ») : le battement
                                   -- du téléphone ne la rajeunit plus ; localisation coupée :
                                   -- tout de suite.
                                   and ((to_jsonb(pp) ->> 'localisation_coupee_le') is not null
                                        or maintenant - greatest(coalesce((to_jsonb(pp) ->> 'fix_le')::timestamptz, pp.enregistre_le),
                                                                 x.recu_le, c.paye_le)
                                           > make_interval(mins => v_position_min)))
        union all
        select 'momopay_non_verifie' where exists (select 1 from public.encaissements e
                                 where e.commande_id = c.id and e.mode = 'mobile_money' and e.remis_le is null
                                   and maintenant - e.encaisse_le > make_interval(hours => v_momopay_h))
        union all
        select 'encaissement_ecart' where exists (select 1 from public.encaissements e
                                 where e.commande_id = c.id and e.montant <> e.du)
      ) al)
    end)
  from cmd c
  left join public.rh_suivi_commandes sc on sc.commande_id = c.id
  cross join lateral (
    select case
      when sc.cloturee_le is not null then 14
      when c.etat = 'a_payer' then 0
      when c.etat = 'echouee' then 15
      when c.etat = 'annulee' then 11
      when not exists (select 1 from lig2 x where x.commande_id = c.id and x.rang <> 11) then 11
      when exists (select 1 from lig2 x where x.commande_id = c.id and x.rang = 10) then 10
      when exists (select 1 from lig2 x where x.commande_id = c.id and x.rang = 9) then 9
      when exists (select 1 from lig2 x where x.commande_id = c.id and x.rang = 12) then 12
      else (select min(x.rang) from lig2 x where x.commande_id = c.id and x.rang <> 11)
    end as rang) st
  order by c.cree_le desc;
end $$;

alter table public.positions_livreurs add column if not exists fix_le timestamptz;
alter table public.positions_livreurs add column if not exists localisation_coupee_le timestamptz;

create table if not exists public.alertes_localisation (
  livreur    uuid primary key references public.profils(id) on delete cascade,
  raison     text not null check (raison in ('coupee', 'muette')),
  commande   text,
  alerte_le  timestamptz not null default now()
);
alter table public.alertes_localisation enable row level security;
revoke all on public.alertes_localisation from public, anon, authenticated;

drop function if exists public.position_livreur(text, double precision, double precision, int);
create or replace function public.position_livreur(jeton text, lat double precision,
  lng double precision, precision_m int default null, localisation boolean default null, age_s int default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  qui uuid;
  p   public.profils%rowtype;
  la  double precision := public.coord_valable(lat, 90);
  lo  double precision := public.coord_valable(lng, 180);
  en_course boolean;
  derniere timestamptz;
  pas      interval;
begin
  select s.profil_id into qui from public.suivis_livreurs s
   where (s.jeton_hash = encode(sha256(convert_to(coalesce(jeton, ''), 'UTF8')), 'hex')
          and s.expire_le > now())
      or (s.jeton_hash_precedent = encode(sha256(convert_to(coalesce(jeton, ''), 'UTF8')), 'hex')
          and s.precedent_expire_le > now());
  if qui is null then
    raise exception 'Suivi expiré : ouvrez BIZZOO Admin pour le reprendre.' using errcode = '42501';
  end if;
  -- Le service travaille encore avec l'ancien jeton (le nouveau attend que
  -- la page revienne à l'écran) : il le garde tant qu'il s'en sert.
  update public.suivis_livreurs set precedent_expire_le = now() + interval '10 minutes'
   where profil_id = qui
     and jeton_hash_precedent = encode(sha256(convert_to(coalesce(jeton, ''), 'UTF8')), 'hex')
     and precedent_expire_le < now() + interval '5 minutes';
  select * into p from public.profils x where x.id = qui;
  if not found or not p.actif or p.role <> 'livreur' then
    delete from public.suivis_livreurs where profil_id = qui;
    return jsonb_build_object('continuer', false, 'en_course', false);
  end if;
  en_course := public.livreur_en_course(qui);
  if not en_course and (not coalesce(p.disponible, true) or p.courses_bloquees) then
    -- Le suivi s'arrête : « Localiser un livreur » ne le montre plus actif.
    delete from public.suivis_livreurs where profil_id = qui;
    return jsonb_build_object('continuer', false, 'en_course', false);
  end if;
  -- APPLICATION FERMÉE DES JOURS DURANT : tant que le téléphone se manifeste,
  -- le jeton ne meurt pas (16 heures après le dernier signe ; une écriture
  -- par heure au plus).
  update public.suivis_livreurs set expire_le = now() + interval '16 hours'
   where profil_id = qui and expire_le < now() + interval '15 hours';
  -- (3.75.0) La localisation du téléphone : coupée, ou revenue. Retenu
  -- aussitôt, sans attendre une position valable.
  if localisation is not null then
    update public.positions_livreurs
       set localisation_coupee_le = case when localisation then null else now() end
     where profil_id = qui
       and ((localisation and localisation_coupee_le is not null)
            or (not localisation and localisation_coupee_le is null));
  end if;
  if la is null or lo is null or (la = 0 and lo = 0) then
    return jsonb_build_object('continuer', true, 'en_course', en_course);
  end if;
  -- Pas plus d'une écriture toutes les 5 secondes en course, toutes les 30
  -- secondes libre. Seule une position déjà là (compte validé) se met à jour.
  select pl.enregistre_le into derniere from public.positions_livreurs pl where pl.profil_id = qui;
  pas := case when en_course then interval '5 seconds' else interval '30 seconds' end;
  if derniere is not null and derniere < now() - pas then
    update public.positions_livreurs
       set latitude = la, longitude = lo, precision_m = greatest(0, position_livreur.precision_m),
           enregistre_le = now(),
           -- (3.75.0) Quand la position a vraiment été mesurée.
           fix_le = now() - make_interval(secs => greatest(0, least(coalesce(age_s, 0), 864000)))
     where profil_id = qui;
  end if;
  return jsonb_build_object('continuer', true, 'en_course', en_course);
end $$;
revoke all on function public.position_livreur(text, double precision, double precision, int, boolean, int) from public;
grant execute on function public.position_livreur(text, double precision, double precision, int, boolean, int)
  to anon, authenticated;

create or replace function public.alerter_localisations() returns int
language plpgsql security definer set search_path = public as $$
declare
  seuil   int := coalesce((select (to_jsonb(r) ->> 'position_min')::int from public.rh_reglages_suivi r limit 1), 15);
  x       record;
  raison  text;
  n       int := 0;
  equipe  uuid[];
  autres  uuid[];
begin
  equipe := public.enseigne_des_commandes() || public.les_superadmins();
  autres := coalesce((select array_agg(p.id) from public.profils p
                       where p.actif and p.boutique_id is null and not p.peut_commandes
                         and p.role in ('administrateur', 'moderateur')), '{}'::uuid[]);
  -- Ceux qui ne sont plus en course : l'épisode est clos, sans bruit.
  delete from public.alertes_localisation a where not public.livreur_en_course(a.livreur);
  for x in
    select pr.id, coalesce(nullif(btrim(pr.nom), ''), 'Un livreur') as nom,
           regexp_replace(regexp_replace(coalesce(pr.tel, ''), '\D', '', 'g'), '^229', '') as tel,
           pl.localisation_coupee_le as coupee,
           coalesce(pl.fix_le, pl.enregistre_le) as mesure,
           a.raison as deja,
           (select c.numero from public.commande_lignes l join public.commandes c on c.id = l.commande_id
             where l.livreur_id = pr.id and c.etat = 'payee'
               and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')
             order by l.recu_le desc nulls last limit 1) as numero,
           (select c.id from public.commande_lignes l join public.commandes c on c.id = l.commande_id
             where l.livreur_id = pr.id and c.etat = 'payee'
               and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')
             order by l.recu_le desc nulls last limit 1) as commande
      from public.profils pr
      join public.positions_livreurs pl on pl.profil_id = pr.id
      left join public.alertes_localisation a on a.livreur = pr.id
     where pr.role = 'livreur' and public.livreur_en_course(pr.id)
       -- Seulement après « Commande reçue » : avant, il n'est pas en route.
       and exists (select 1 from public.commande_lignes l join public.commandes c on c.id = l.commande_id
                    where l.livreur_id = pr.id and c.etat = 'payee' and l.recu_le is not null
                      and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison'))
  loop
    raison := case
      when x.coupee is not null and x.coupee < now() - interval '1 minute' then 'coupee'
      when x.mesure is null or x.mesure < now() - make_interval(mins => seuil) then 'muette'
      else null end;
    if raison is not null and x.deja is null then
      insert into public.alertes_localisation (livreur, raison, commande) values (x.id, raison, x.commande)
      on conflict (livreur) do nothing;
      perform public.notifier(equipe, 'livreur_sans_localisation',
        case when raison = 'coupee' then 'Localisation coupée — ' else 'Livreur sans position — ' end || x.nom,
        case when raison = 'coupee'
             then x.nom || ' a coupé la localisation de son téléphone pendant la course ' || coalesce(x.numero, '') || '.'
             else 'Aucune position de ' || x.nom || ' depuis plus de ' || seuil || ' min, pendant la course ' ||
                  coalesce(x.numero, '') || '.' end ||
        case when x.tel <> '' then E'\nAppelez-le : ' || x.tel || '.' else '' end,
        '#/livreurs/' || x.id, null, null, true);
      if cardinality(autres) > 0 then
        perform public.notifier(autres, 'livreur_sans_localisation',
          case when raison = 'coupee' then 'Localisation coupée — ' else 'Livreur sans position — ' end || x.nom,
          case when raison = 'coupee'
               then x.nom || ' a coupé la localisation de son téléphone pendant la course ' || coalesce(x.numero, '') || '.'
               else 'Aucune position de ' || x.nom || ' depuis plus de ' || seuil || ' min, pendant la course ' ||
                    coalesce(x.numero, '') || '.' end,
          '#/notifications', null, null, true);
      end if;
      perform public.notifier(array[x.id], 'localisation_a_reactiver', 'Réactivez votre localisation',
        'Course ' || coalesce(x.numero, '') || ' : BIZZOO ne voit plus où vous êtes. ' ||
        'Activez la localisation de votre téléphone.', '#/livraisons', null, null, true);
      n := n + 1;
    elsif raison is null and x.deja is not null then
      delete from public.alertes_localisation where livreur = x.id;
      perform public.notifier(equipe, 'livreur_localisation_retablie', 'Localisation rétablie — ' || x.nom,
        'BIZZOO voit de nouveau ' || x.nom || ' (course ' || coalesce(x.numero, '') || ').',
        '#/livreurs/' || x.id, null, null, false);
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.alerter_localisations() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('localisations-livreurs', '* * * * *', 'select public.alerter_localisations()');
  end if;
exception when others then
  raise notice 'Alerte de localisation non programmée (%) : Personnel la montre toujours', sqlerrm;
end $$;

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
    'course_annulee_livreur',
    -- (3.75.0) Après « Commande reçue », on le dit : il était en route.
    case when annonce then 'Course annulée après acceptation par ' else 'Course annulée par ' end ||
      porteur || ' — ' || coalesce(c.numero, ''),
    texte, '#/commandes/' || commande, commande, null, true);
  perform public.notifier(
    coalesce((select array_agg(p.id) from public.profils p
               where p.actif and p.boutique_id is null and not p.peut_commandes
                 and p.role in ('administrateur', 'moderateur')), '{}'::uuid[]),
    'course_annulee_livreur',
    -- (3.75.0) Après « Commande reçue », on le dit : il était en route.
    case when annonce then 'Course annulée après acceptation par ' else 'Course annulée par ' end ||
      porteur || ' — ' || coalesce(c.numero, ''),
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
