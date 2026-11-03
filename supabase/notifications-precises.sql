-- =========================================================
-- BIZZOO 3.73.0 — Chaque notification mène à l'écran exact
--
--   Toucher une notification (sur le téléphone, ou dans la cloche)
--   ouvre désormais ce qu'elle annonce, et non une liste :
--     - une course proposée → CETTE course (Mes courses) ;
--     - un produit épuisé ou à vérifier → la fiche de CE produit
--       (plusieurs d'un coup : la liste du stock) ;
--     - une demande de reversement → CETTE demande (Reversements) ;
--     - un compte à valider, un compte validé → la fiche de CE compte.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

alter table public.profils add column if not exists nom text not null default '';
alter table public.profils add column if not exists cree_par uuid;
alter table public.profils add column if not exists a_valider boolean not null default false;

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.droit_enseigne(lequel text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_compte_enseigne() and coalesce((
    select case lequel
             when 'commandes' then p.peut_commandes
             when 'boutiques' then p.peut_boutiques
             when 'finances'  then p.peut_finances
             when 'produits'  then p.peut_modifier_produits
             else false
           end
      from public.profils p
     where p.id = auth.uid() and p.actif), false);
$$;
revoke all on function public.droit_enseigne(text)   from public, anon;
grant execute on function public.droit_enseigne(text)  to authenticated;

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

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
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

create or replace function public.tient_la_caisse(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.droit_enseigne('commandes')
      or public.droit_enseigne('finances')
      or (public.est_admin() and cible is not null
          and cible = public.boutique_du_compte());
$$;
revoke all on function public.tient_la_caisse(text) from public, anon, authenticated;
grant execute on function public.tient_la_caisse(text) to authenticated;

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
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

create or replace function public.est_admin_bizzoo() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'administrateur', false)
     and public.est_compte_enseigne();
$$;
revoke all on function public.est_admin_bizzoo() from public, anon;
grant execute on function public.est_admin_bizzoo() to authenticated;

create or replace function public.est_livreur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'livreur', false);
$$;
revoke all on function public.est_livreur() from public, anon, authenticated;
grant execute on function public.est_livreur() to authenticated;

create or replace function public.est_vendeur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'vendeur', false);
$$;
revoke all on function public.est_vendeur() from public, anon;
grant execute on function public.est_vendeur() to authenticated;

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

create or replace function public.gere_les_fonds(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or (public.est_admin() and cible is not null and cible = public.boutique_du_compte());
$$;
revoke all on function public.gere_les_fonds(text) from public, anon, authenticated;
grant execute on function public.gere_les_fonds(text) to authenticated;

create or replace function public.les_superadmins() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.role = 'superadministrateur';
$$;
revoke all on function public.les_superadmins()          from public, anon, authenticated;

create or replace function public.montant_lisible(n numeric, devise text default 'FCFA')
returns text
language sql immutable set search_path = public as $$
  select replace(to_char(coalesce(n, 0), 'FM999,999,999,990'), ',', ' ') || ' ' || coalesce(nullif(devise, ''), 'FCFA');
$$;
revoke all on function public.montant_lisible(numeric, text) from public, anon, authenticated;

create or replace function public.nom_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select coalesce(nullif(p.nom, ''), nullif(p.email, ''), 'l''équipe')
                     from public.profils p where p.id = auth.uid()), '');
$$;
revoke all on function public.nom_du_compte() from public, anon, authenticated;

create or replace function public.nom_du_createur(qui uuid)
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(trim(p.nom), ''), nullif(p.email, ''), 'compte inconnu')
         || ' (' || p.role || ')'
    from public.profils p
   where p.id = qui;
$$;
revoke all on function public.nom_du_createur(uuid) from public, anon, authenticated;

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

create or replace function public.solde_boutique(cible text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  gagne bigint; a_venir bigint; encaisse bigint; reverse bigint; attente bigint;
  r public.boutiques_reception%rowtype;
begin
  if not public.tient_la_caisse(cible) then
    raise exception 'Ce solde n''est pas celui de votre boutique.';
  end if;
  select coalesce(sum(l.prix_bizzoo::bigint * l.quantite) filter (where l.etat = 'remise'), 0),
         coalesce(sum(l.prix_bizzoo::bigint * l.quantite)
                    filter (where l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')), 0)
    into gagne, a_venir
    from public.commande_lignes l
    join public.commandes c on c.id = l.commande_id and c.etat = 'payee'
   where l.boutique_id = cible
     -- (3.70.0) La part d'un vendeur va au vendeur, pas à la boutique.
     and l.vendeur_id is null;
  select coalesce(sum(x.montant), 0) into encaisse from public.encaissements x
   where x.boutique_id = cible and x.mode = 'especes' and x.remis_le is not null;
  select coalesce(sum(v.montant) filter (where v.etat = 'valide'), 0),
         coalesce(sum(v.montant) filter (where v.etat = 'en_attente'), 0)
    into reverse, attente
    from public.reversements v where v.boutique_id = cible;
  select * into r from public.boutiques_reception where boutique_id = cible;
  return jsonb_build_object(
    'gagne', gagne, 'a_venir', a_venir, 'deja_encaisse', encaisse,
    'reverse', reverse, 'en_attente', attente,
    'disponible', greatest(0, gagne - encaisse - reverse - attente),
    'devise', coalesce((select nullif(b.devise, '') from public.boutiques b where b.id = cible), 'FCFA'),
    'reception', case when r.boutique_id is null or r.tel = '' then null
                      else jsonb_build_object('tel', r.tel, 'reseau', r.reseau, 'titulaire', r.titulaire,
                                              'maj_le', r.maj_le, 'maj_par', r.maj_par) end);
end $$;
revoke all on function public.solde_boutique(text) from public, anon;
grant execute on function public.solde_boutique(text) to authenticated;

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

create or replace function public.solde_vendeur(cible uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  qui uuid := coalesce(cible, auth.uid());
  ventes bigint; gagne bigint; a_venir bigint; reverse bigint; attente bigint;
  r public.vendeurs_reception%rowtype;
begin
  if qui is null or not ((qui = auth.uid() and public.est_vendeur()) or public.est_super()) then
    raise exception 'Ce solde n''est pas le vôtre.';
  end if;
  select coalesce(sum(l.prix::bigint * l.quantite) filter (where l.etat = 'remise'), 0),
         coalesce(sum(l.prix_bizzoo::bigint * l.quantite) filter (where l.etat = 'remise'), 0),
         coalesce(sum(l.prix_bizzoo::bigint * l.quantite)
                    filter (where l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')), 0)
    into ventes, gagne, a_venir
    from public.commande_lignes l
    join public.commandes c on c.id = l.commande_id and c.etat = 'payee'
   where l.vendeur_id = qui;
  select coalesce(sum(v.montant) filter (where v.etat = 'valide'), 0),
         coalesce(sum(v.montant) filter (where v.etat = 'en_attente'), 0)
    into reverse, attente
    from public.reversements_vendeurs v where v.vendeur_id = qui;
  select * into r from public.vendeurs_reception where vendeur_id = qui;
  return jsonb_build_object(
    'ventes', ventes, 'gagne', gagne, 'a_venir', a_venir, 'reverse', reverse, 'en_attente', attente,
    'disponible', greatest(0, gagne - reverse - attente), 'devise', 'FCFA',
    'reception', case when r.vendeur_id is null or r.tel = '' then null
                      else jsonb_build_object('tel', r.tel, 'reseau', r.reseau, 'titulaire', r.titulaire,
                                              'maj_le', r.maj_le) end);
end $$;
revoke all on function public.solde_vendeur(uuid) from public, anon;
grant execute on function public.solde_vendeur(uuid) to authenticated;

create or replace function public.stock_rendre(ligne text) returns int
language plpgsql security definer set search_path = public as $$
declare
  l record;
begin
  select cl.id, cl.produit_id, cl.stock_pris into l
    from public.commande_lignes cl
   where cl.id = ligne and cl.stock_pris > 0
   for update;
  if not found then return 0; end if;
  begin
    if l.produit_id is not null then
      update public.produits
         set stock = greatest(coalesce(stock, 0), 0) + l.stock_pris,
             disponible = true
       where id = l.produit_id;
    end if;
    update public.commande_lignes set stock_pris = 0 where id = l.id;
  exception when others then
    -- Une annulation ne se bloque pas pour autant : la trace reste, et
    -- l'on pourra rendre plus tard.
    raise warning 'stock_rendre(%) : %', ligne, sqlerrm;
    return 0;
  end;
  return l.stock_pris;
end $$;
revoke all on function public.stock_rendre(text) from public, anon, authenticated;

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

create or replace function public.commande_stock() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  l        record;
  avant    int;
  pris     int;
  appro    boolean;
  numero   text := coalesce(new.numero, '');
  -- Par boutique, ce qu'il faudra lui dire. Une notification par
  -- boutique et par commande, pas une par produit : trois articles
  -- épuisés d'un coup se lisent en une ligne.
  epuises  jsonb := '{}'::jsonb;
  manques  jsonb := '{}'::jsonb;
  ratees   jsonb := '{}'::jsonb;
  -- (3.73.0) Les produits eux-mêmes : un seul produit épuisé (ou à
  -- vérifier), la notification ouvre SA fiche ; plusieurs, la liste.
  epuises_ids jsonb := '{}'::jsonb;
  ratees_ids  jsonb := '{}'::jsonb;
  b        text;
  liste    text;
begin
  -- ---- Annulée après paiement : tout ce qui avait été pris revient ----
  if old.etat = 'payee' and new.etat is distinct from 'payee' then
    for l in select cl.id from public.commande_lignes cl
              where cl.commande_id = new.id and cl.stock_pris > 0
              order by cl.produit_id, cl.id loop
      perform public.stock_rendre(l.id);
    end loop;
    return null;
  end if;

  if new.etat is distinct from 'payee' or old.etat = 'payee' then
    return null;
  end if;

  -- ---- Payée : on prend ----
  -- Dans l'ordre des produits : deux paiements simultanés verrouillent
  -- leurs produits dans le même ordre, et ne s'attendent jamais en croix.
  for l in select cl.id, cl.produit_id, coalesce(cl.boutique_id, '') as boutique,
                  cl.nom, cl.quantite
             from public.commande_lignes cl
            where cl.commande_id = new.id and cl.etat <> 'annulee'
              and cl.stock_pris = 0 and cl.produit_id is not null
            order by cl.produit_id, cl.id loop
    begin
      select greatest(coalesce(p.stock, 0), 0),
             (p.appro_le is not null and p.appro_le >= current_date)
        into avant, appro
        from public.produits p
       where p.id = l.produit_id and not coalesce(p.sur_commande, false)
       for update;
      -- « Sur commande » : la boutique le fait venir, il n'y a rien à compter.
      if not found then continue; end if;

      pris := least(avant, l.quantite);
      if pris > 0 then
        update public.produits
           set stock = avant - pris,
               disponible = (avant - pris) > 0
         where id = l.produit_id;
        update public.commande_lignes set stock_pris = pris where id = l.id;
      end if;

      -- En approvisionnement, ce qui manque ARRIVE : c'est ce que la
      -- boutique a annoncé, pas une vente de trop.
      if pris < l.quantite and not appro then
        manques := jsonb_set(manques, array[l.boutique],
          coalesce(manques -> l.boutique, '[]'::jsonb) ||
          to_jsonb(l.nom || ' (' || l.quantite || ' vendu' ||
                   case when l.quantite > 1 then 's' else '' end ||
                   ', ' || avant || ' en stock)'));
      elsif pris > 0 and avant - pris = 0 then
        epuises := jsonb_set(epuises, array[l.boutique],
          coalesce(epuises -> l.boutique, '[]'::jsonb) || to_jsonb(l.nom));
        epuises_ids := jsonb_set(epuises_ids, array[l.boutique],
          coalesce(epuises_ids -> l.boutique, '[]'::jsonb) || to_jsonb(l.produit_id));
      end if;
    exception when others then
      -- Le produit refuse l'écriture — un rayon devenu incohérent, par
      -- exemple. Le paiement, lui, passe : on le dit à qui peut corriger.
      ratees := jsonb_set(ratees, array[l.boutique],
        coalesce(ratees -> l.boutique, '[]'::jsonb) || to_jsonb(l.nom));
      ratees_ids := jsonb_set(ratees_ids, array[l.boutique],
        coalesce(ratees_ids -> l.boutique, '[]'::jsonb) || to_jsonb(l.produit_id));
      raise warning 'commande_stock(%) : % — %', new.id, l.nom, sqlerrm;
    end;
  end loop;

  -- ---- Ce que la boutique doit savoir ----
  -- Une notification ratée n'annule pas un paiement non plus.
  begin
    for b in select jsonb_object_keys(manques) loop
      select string_agg(x, ', ') into liste from jsonb_array_elements_text(manques -> b) x;
      perform public.notifier(
        public.equipe_de(nullif(b, '')) || public.enseigne_des_commandes() || public.les_superadmins(),
        'stock_insuffisant', 'Stock insuffisant',
        'Commande ' || numero || ' payée, mais il manque des pièces : ' || liste ||
          '. Voyez avec le client.',
        '#/commandes/' || new.id, new.id, nullif(b, ''), true);
    end loop;
    for b in select jsonb_object_keys(epuises) loop
      select string_agg(x, ', ') into liste from jsonb_array_elements_text(epuises -> b) x;
      perform public.notifier(public.equipe_de(nullif(b, '')),
        'stock_epuise', 'Rupture de stock',
        liste || ' : plus aucune pièce après la commande ' || numero ||
          '. Vos clients voient « En rupture ».',
        case when jsonb_array_length(epuises_ids -> b) = 1
                then '#/produit/' || (epuises_ids -> b ->> 0) else '#/stock?filtre=rupture' end,
           new.id, nullif(b, ''), false);
    end loop;
    for b in select jsonb_object_keys(ratees) loop
      select string_agg(x, ', ') into liste from jsonb_array_elements_text(ratees -> b) x;
      perform public.notifier(
        public.equipe_de(nullif(b, '')) || public.les_superadmins(),
        'stock_a_verifier', 'Stock à vérifier',
        'Commande ' || numero || ' payée, mais le stock de ' || liste ||
          ' n''a pas pu être décompté. Corrigez-le à la main.',
        case when jsonb_array_length(ratees_ids -> b) = 1
                then '#/produit/' || (ratees_ids -> b ->> 0) else '#/stock' end,
           new.id, nullif(b, ''), true);
    end loop;
  exception when others then
    raise warning 'commande_stock(%) notifications : %', new.id, sqlerrm;
  end;
  return null;
end $$;

create or replace function public.demander_reversement(cible text, montant bigint)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  solde jsonb;
  r     public.boutiques_reception%rowtype;
  qui   text := public.nom_du_compte();
  nouv  bigint;
begin
  if not public.gere_les_fonds(cible) then
    raise exception 'Seul l''administrateur de la boutique demande un reversement.';
  end if;
  -- Une demande à la fois par boutique : on la tranche avant la suivante.
  perform 1 from public.boutiques b where b.id = cible for update;
  select * into r from public.boutiques_reception where boutique_id = cible;
  if r.boutique_id is null or r.tel = '' then
    raise exception 'Réglez d''abord le numéro qui recevra les fonds.' using errcode = 'P0001';
  end if;
  solde := public.solde_boutique(cible);
  if coalesce(montant, 0) <= 0 then
    raise exception 'Indiquez le montant à reverser.' using errcode = 'P0001';
  end if;
  if montant > (solde ->> 'disponible')::bigint then
    raise exception 'Le solde disponible est de % : vous ne pouvez pas demander plus.',
      public.montant_lisible((solde ->> 'disponible')::bigint, solde ->> 'devise') using errcode = 'P0001';
  end if;
  insert into public.reversements (boutique_id, montant, tel, reseau, titulaire, demande_par)
  values (cible, montant, r.tel, r.reseau, r.titulaire, qui)
  returning id into nouv;
  perform public.notifier(public.les_superadmins(), 'reversement_demande',
    'Reversement demandé : ' || public.montant_lisible(montant, solde ->> 'devise'),
    coalesce((select b.nom from public.boutiques b where b.id = cible), cible) || ' — à envoyer sur ' ||
      r.reseau || ' ' || r.tel || coalesce(' (' || nullif(r.titulaire, '') || ')', '') || '. Demandé par ' || qui || '.',
    -- (3.73.0) La touche ouvre CETTE demande.
    '#/reversements/boutique-' || nouv, null, cible, true);
  return nouv;
end $$;

create or replace function public.demander_reversement_livreur(montant bigint)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  moi   uuid := auth.uid();
  solde jsonb;
  r     public.livreurs_reception%rowtype;
  qui   text := public.nom_du_compte();
  nouv  bigint;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Seul un livreur demande le reversement de ses gains.';
  end if;
  -- Une demande à la fois : on la tranche avant la suivante.
  perform 1 from public.profils p where p.id = moi for update;
  select * into r from public.livreurs_reception where livreur_id = moi;
  if r.livreur_id is null or r.tel = '' then
    raise exception 'Réglez d''abord le numéro qui recevra vos gains.' using errcode = 'P0001';
  end if;
  if coalesce(montant, 0) <= 0 then
    raise exception 'Indiquez le montant à reverser.' using errcode = 'P0001';
  end if;
  solde := public.solde_livreur(moi);
  if montant > (solde ->> 'disponible')::bigint then
    raise exception 'Votre solde disponible est de % : vous ne pouvez pas demander plus.',
      public.montant_lisible((solde ->> 'disponible')::bigint, 'FCFA') using errcode = 'P0001';
  end if;
  insert into public.reversements_livreurs (livreur_id, nom_livreur, montant, tel, reseau, titulaire)
  values (moi, qui, montant, r.tel, r.reseau, r.titulaire)
  returning id into nouv;
  perform public.notifier(public.les_superadmins(), 'reversement_demande',
    'Reversement demandé par un livreur : ' || public.montant_lisible(montant, 'FCFA'),
    qui || ' — à envoyer sur ' || r.reseau || ' ' || r.tel ||
      coalesce(' (' || nullif(r.titulaire, '') || ')', '') || '.',
    -- (3.73.0) La touche ouvre CETTE demande.
    '#/reversements/livreur-' || nouv, null, null, true);
  return nouv;
end $$;

create or replace function public.demander_reversement_vendeur(montant bigint)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  moi   uuid := auth.uid();
  solde jsonb;
  r     public.vendeurs_reception%rowtype;
  qui   text := public.nom_du_compte();
  nouv  bigint;
begin
  if moi is null or not public.est_vendeur() then
    raise exception 'Seul un vendeur demande le versement de ses gains.';
  end if;
  -- Une demande à la fois : on la tranche avant la suivante.
  perform 1 from public.profils p where p.id = moi for update;
  select * into r from public.vendeurs_reception where vendeur_id = moi;
  if r.vendeur_id is null or r.tel = '' then
    raise exception 'Réglez d''abord le numéro qui recevra vos gains.' using errcode = 'P0001';
  end if;
  if coalesce(montant, 0) <= 0 then
    raise exception 'Indiquez le montant à verser.' using errcode = 'P0001';
  end if;
  solde := public.solde_vendeur(moi);
  if montant > (solde ->> 'disponible')::bigint then
    raise exception 'Votre solde disponible est de % : vous ne pouvez pas demander plus.',
      public.montant_lisible((solde ->> 'disponible')::bigint, 'FCFA') using errcode = 'P0001';
  end if;
  insert into public.reversements_vendeurs (vendeur_id, nom_vendeur, montant, tel, reseau, titulaire)
  values (moi, qui, montant, r.tel, r.reseau, r.titulaire)
  returning id into nouv;
  perform public.notifier(public.les_superadmins(), 'reversement_demande',
    'Versement demandé par un vendeur : ' || public.montant_lisible(montant, 'FCFA'),
    qui || ' — à envoyer sur ' || r.reseau || ' ' || r.tel ||
      coalesce(' (' || nullif(r.titulaire, '') || ')', '') || '.',
    -- (3.73.0) La touche ouvre CETTE demande.
    '#/reversements/vendeur-' || nouv, null, null, true);
  return nouv;
end $$;

create or replace function public.profil_validation() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  nouveau boolean;
begin
  if coalesce(current_setting('bizzoo.compte', true), '') = 'oui' then
    return new;
  end if;

  if public.est_admin_bizzoo() and new.role = 'moderateur' then
    new.actif := false;
    new.a_valider := true;
    -- L'écran pose le rang par « insert … on conflict » : PostgreSQL exige
    -- alors que la ligne PROPOSÉE soit lisible par son auteur, et elle ne
    -- l'est que par son créateur. Sur une fiche qui n'en a pas encore, il
    -- l'est ; « profil_trace » en fera autant sur la mise à jour.
    if tg_op = 'INSERT' and new.cree_par is null then
      new.cree_par := auth.uid();
    end if;
    -- Une insertion qui vise une fiche existante finira en mise à jour
    -- (« on conflict ») : on ne prévient qu'une fois, sur la mise à jour.
    nouveau := case when tg_op = 'INSERT'
                    then not exists (select 1 from public.profils p where p.id = new.id)
                    else not old.a_valider end;
    if nouveau then
      perform public.notifier(public.les_superadmins(), 'compte_a_valider',
        'Un compte modérateur à valider',
        coalesce(nullif(trim(new.nom), ''), nullif(new.email, ''), 'Un nouveau compte') ||
          ', créé par ' || coalesce(public.nom_du_createur(auth.uid()), 'un administrateur de BIZZOO') ||
          '. Activez-le dans Comptes pour le valider.',
        '#/comptes/' || new.id, null, null, false);
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.a_valider := false;
    return new;
  end if;

  if public.est_super() then
    -- Activer, c'est valider.
    new.a_valider := old.a_valider and not new.actif;
    if old.a_valider and not new.a_valider and old.cree_par is not null then
      perform public.notifier(array[old.cree_par], 'compte_valide',
        'Compte validé',
        coalesce(nullif(trim(new.nom), ''), nullif(new.email, ''), 'Le compte') ||
          ' a été validé : il peut travailler.',
        '#/comptes/' || new.id, null, null, false);
    end if;
  else
    new.a_valider := old.a_valider;
    if old.a_valider then new.actif := false; end if;
  end if;
  return new;
end $$;

