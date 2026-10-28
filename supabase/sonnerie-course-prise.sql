-- =========================================================
-- BIZZOO 3.66.0 — Une course prise sonne aussi chez BIZZOO
--
--   Quand un livreur prend une course (« Commande reçue »), la boutique
--   l'entendait déjà. Désormais les administrateurs de BIZZOO qui suivent
--   les commandes ET les superadministrateurs l'entendent aussi : trois
--   bips application ouverte, une sonnerie application fermée (BIZZOO
--   Admin 3.65.0 ou plus récente). Une seule sonnerie par prise.
--
--   (Une commande payée par le client sonnait déjà chez la boutique, chez
--   les administrateurs de BIZZOO qui suivent les commandes, et chez les
--   superadministrateurs : rien ne change pour elle.)
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- Les colonnes que la fonction lit.
alter table public.commande_lignes add column if not exists recu_le timestamptz;
alter table public.commande_lignes add column if not exists livreur_id uuid;
alter table public.commande_lignes add column if not exists confirme_le timestamptz;

-- Emprunté par la fonction plus bas, recopié tel quel.
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

-- Emprunté par la fonction plus bas, recopié tel quel.
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

-- Emprunté par la fonction plus bas, recopié tel quel.
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

-- Emprunté par la fonction plus bas, recopié tel quel.
create or replace function public.enseigne_des_commandes() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.boutique_id is null and p.peut_commandes
     and p.role in ('administrateur', 'moderateur');
$$;

-- Emprunté par la fonction plus bas, recopié tel quel.
create or replace function public.equipe_de(cible text) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and cible is not null and p.boutique_id = cible
     and p.role in ('administrateur', 'moderateur');
$$;

-- Emprunté par la fonction plus bas, recopié tel quel.
create or replace function public.les_superadmins() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.role = 'superadministrateur';
$$;

-- Emprunté par la fonction plus bas, recopié tel quel.
create or replace function public.montant_lisible(n numeric, devise text default 'FCFA')
returns text
language sql immutable set search_path = public as $$
  select replace(to_char(coalesce(n, 0), 'FM999,999,999,990'), ',', ' ') || ' ' || coalesce(nullif(devise, ''), 'FCFA');
$$;
revoke all on function public.montant_lisible(numeric, text) from public, anon, authenticated;

-- Emprunté par la fonction plus bas, recopié tel quel.
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

-- (3.70.0) Lue par « fiche_course » / « faire_livrer » plus bas.
alter table public.commandes add column if not exists lieu_retrait text not null default '';

-- Emprunté par la fonction plus bas, recopié tel quel.
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

-- ---------- Le cycle de la ligne ----------
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
        -- (3.70.0) Ce que l'équipe a précisé en saisissant la commande.
        coalesce('Où récupérer : ' || nullif(fiche ->> 'lieu_retrait', '') || E'\n', '') ||
        'Livrer à : ' || coalesce(nullif(fiche -> 'livraison' ->> 'nom', ''), 'le client') ||
          coalesce(nullif(' — ' || (fiche -> 'livraison' ->> 'adresse'), ' — '), ' (adresse à demander)') || E'\n' ||
        'Destinataire : +' || (fiche -> 'livraison' ->> 'indicatif') || ' ' || (fiche -> 'livraison' ->> 'tel') || E'\n' ||
        'Frais de livraison : ' || public.montant_lisible((fiche ->> 'frais')::numeric, fiche ->> 'devise') || E'\n' ||
        'Déjà payé : ' || public.montant_lisible((fiche ->> 'deja_paye')::numeric, fiche ->> 'devise') || E'\n' ||
        case when (fiche ->> 'a_encaisser')::numeric > 0
             then 'Reste à payer par MoMoPay : ' || public.montant_lisible((fiche ->> 'a_encaisser')::numeric, fiche ->> 'devise') ||
                  ' (pas d''espèces)'
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
    -- (3.66.0) BIZZOO AUSSI L'ENTEND : ses administrateurs qui suivent les
    -- commandes et les superadministrateurs — une sonnerie par prise, pas
    -- une par boutique quand le livreur prend toute la commande d'un coup.
    perform public.notifier(enseigne || public.les_superadmins(), 'course_acceptee',
      'Course prise par ' || porteur.nom,
      'Commande ' || numero || ' — ' || porteur.nom || ' a pris la course.',
      '#/commandes/' || new.commande_id, new.commande_id,
      case when coalesce(current_setting('bizzoo.prise', true), '') = 'oui' then null
           else new.boutique_id end, true);
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

