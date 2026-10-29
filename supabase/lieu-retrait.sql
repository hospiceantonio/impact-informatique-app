-- =========================================================
-- BIZZOO 3.70.0 — « Faire livrer » : où le livreur récupère la commande
--
--   L'écran « Faire livrer » de BIZZOO Admin demande désormais où le
--   livreur ira chercher la commande : la boutique, son adresse, qui
--   appeler. La commande le garde (colonne « lieu_retrait »), et le
--   livreur le lit :
--     - dans l'alerte de la course proposée, et de la course confiée ;
--     - sur la fiche de la course, dans BIZZOO Admin → Livraisons.
--   La fiche de la boutique (nom, adresse, téléphone) reste affichée :
--   ce qui est saisi s'y ajoute.
--
--   Sans danger pour les applications déjà installées : la colonne a
--   une valeur par défaut, et « faire_livrer » garde sa signature (le
--   lieu voyage dans « client ») ; l'écran d'avant ne l'envoie pas, la
--   commande part alors sans, comme avant.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

alter table public.commandes add column if not exists lieu_retrait text not null default '';
-- Lues par « notifier_ligne » plus bas (déjà là sur une base en service).
alter table public.commande_lignes add column if not exists confirme_le timestamptz;
alter table public.commande_lignes add column if not exists livreur_id uuid;
alter table public.commande_lignes add column if not exists recu_le timestamptz;

-- (3.70.0) Le devis plus bas lit la distance par la route : la grille
-- et le cache qu'il emprunte, recopiés tels quels.
create or replace function public.grille_route(x double precision) returns numeric
language sql immutable as $$
  select (round((x * 2000)::numeric) / 2000)::numeric(9,4);
$$;

create table if not exists public.distances_route (
  o_lat      numeric(9,4) not null,
  o_lng      numeric(9,4) not null,
  d_lat      numeric(9,4) not null,
  d_lng      numeric(9,4) not null,
  distance_m int not null check (distance_m > 0 and distance_m <= 1000000),
  cree_le    timestamptz not null default now(),
  primary key (o_lat, o_lng, d_lat, d_lng)
);
create index if not exists distances_route_jour on public.distances_route(cree_le);
alter table public.distances_route enable row level security;
revoke all on public.distances_route from public, anon, authenticated;

-- Empruntées par les fonctions plus bas, recopiées telles quelles.
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
  -- (3.68.0) Les frais SAISIS par l'équipe pour une commande prise sur
  -- WhatsApp (« faire_livrer ») : ils remplacent le calcul à la distance.
  -- Les deux drapeaux ne s'attrapent pas depuis PostgREST.
  saisis   bigint := case when coalesce(current_setting('bizzoo.hors_appli', true), '') = 'oui'
                          then nullif(current_setting('bizzoo.frais_saisis', true), '')::bigint end;
  vehic    text;
begin
  -- Des frais saisis valent une livraison « au kilomètre » sans kilomètre :
  -- un seul frais pour la commande, un seul livreur, payé en ligne — et le
  -- livreur en touche sa part comme d'habitude.
  if saisis is not null then au_km := true; end if;
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
  if au_km and saisis is null then
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
    vehic := case when exists (select 1 from public.commande_lignes l
                                 join public.produits pr on pr.id = l.produit_id
                                where l.commande_id = nouvelle and pr.vehicule = 'tricycle')
                  then 'tricycle' else 'moto' end;
    if saisis is not null then
      -- (3.68.0) Les frais décidés par qui a pris la commande ; la position,
      -- si on l'a, pour que le livreur trouve le client.
      devis := jsonb_build_object('vehicule', vehic, 'distance_km', null, 'frais', greatest(0, saisis),
                 'saisie', true) ||
               case when destination is not null and jsonb_typeof(destination) = 'object'
                         and (destination ->> 'latitude') is not null and (destination ->> 'longitude') is not null
                    then jsonb_build_object('destination', jsonb_build_object(
                           'latitude', round((destination ->> 'latitude')::numeric, 6),
                           'longitude', round((destination ->> 'longitude')::numeric, 6)))
                    else '{}'::jsonb end;
    else
      devis := public.devis_livraison(
        (destination ->> 'latitude')::double precision,
        (destination ->> 'longitude')::double precision, vehic);
    end if;
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

create or replace function public.devis_faire_livrer(articles jsonb, destination jsonb default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  sous   bigint;
  devise text;
  tri    boolean;
begin
  if auth.uid() is null or not public.peut_faire_livrer() then
    raise exception 'Réservé aux comptes qui ont le droit « Faire livrer ».' using errcode = 'P0001';
  end if;
  if articles is null or jsonb_typeof(articles) <> 'array' or jsonb_array_length(articles) = 0 then
    return jsonb_build_object('sous_total', 0, 'devise', 'FCFA', 'vehicule', 'moto');
  end if;
  with a as (
    select x ->> 'produit_id' as id,
           greatest(1, least(99, coalesce((x ->> 'quantite')::int, 1))) as q
      from jsonb_array_elements(articles) x
  )
  select coalesce(sum(coalesce(p.prix, 0) * a.q), 0)::bigint,
         min(coalesce(nullif(b.devise, ''), 'FCFA')),
         bool_or(p.vehicule = 'tricycle')
    into sous, devise, tri
    from a join public.produits p on p.id = a.id
    left join public.boutiques b on b.id = p.boutique_id;
  return jsonb_build_object('sous_total', sous, 'devise', coalesce(devise, 'FCFA'),
    'vehicule', case when coalesce(tri, false) then 'tricycle' else 'moto' end);
end $$;
revoke all on function public.devis_faire_livrer(jsonb, jsonb) from public, anon;
grant execute on function public.devis_faire_livrer(jsonb, jsonb) to authenticated;

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

create or replace function public.noter_versement(
  cible text, quoi text, qui text default '', ou text default '',
  ref text default '', trans text default '',
  du bigint default 0, recu bigint default 0, pourquoi text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare
  num     text := '';
  agregat text := left(regexp_replace(lower(coalesce(qui, '')), '[^a-z]', '', 'g'), 16);
  reseau  text := left(regexp_replace(upper(coalesce(ou,  '')), '[^A-Z]', '', 'g'), 16);
begin
  select c.numero into num from public.commandes c where c.id = cible;

  -- L'AGRÉGATEUR ET L'OPÉRATEUR NE SONT CONNUS QU'À L'OUVERTURE. Ni la
  -- notification ni la vérification ne les rappellent : elles n'ont
  -- qu'une référence. On les reprend donc sur la dernière ligne de la
  -- même commande qui les portait.
  --
  -- La règle vit ICI plutôt que chez chaque appelant : posée à trois
  -- endroits, elle finirait par diverger, et le journal dirait « MTN »
  -- d'un côté et rien de l'autre pour un même versement.
  if coalesce(cible, '') <> '' then
    if agregat = '' then
      select v.fournisseur into agregat from public.versements v
       where v.commande_id = cible and v.fournisseur <> ''
       order by v.cree_le desc, v.id desc limit 1;
    end if;
    if reseau = '' then
      select v.reseau into reseau from public.versements v
       where v.commande_id = cible and v.reseau <> ''
       order by v.cree_le desc, v.id desc limit 1;
    end if;
  end if;

  insert into public.versements
    (commande_id, numero, fournisseur, reseau, reference, transaction_id,
     attendu, recu, verdict, detail)
  values (
    nullif(coalesce(cible, ''), ''),
    coalesce(num, ''),
    coalesce(agregat, ''),
    coalesce(reseau, ''),
    left(regexp_replace(coalesce(ref, ''), '[^A-Za-z0-9_-]', '', 'g'), 96),
    left(regexp_replace(coalesce(trans, ''), '[^A-Za-z0-9_-]', '', 'g'), 64),
    greatest(0, coalesce(du, 0)),
    greatest(0, coalesce(recu, 0)),
    -- Un verdict inconnu ne fait pas échouer l'encaissement : il se range
    -- en « inconnue ». Le journal ne doit jamais empêcher l'argent
    -- d'entrer.
    case when quoi in ('ouverte', 'payee', 'incomplete', 'conflit',
                       'refusee', 'inconnue') then quoi else 'inconnue' end,
    left(coalesce(pourquoi, ''), 300));
end $$;
revoke all on function public.noter_versement(text, text, text, text, text, text, bigint, bigint, text)
  from public, anon, authenticated;

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

create or replace function public.peut_faire_livrer() returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return public.est_super() or (public.est_compte_enseigne() and exists (
    select 1 from public.profils p where p.id = auth.uid() and p.actif and p.peut_faire_livrer));
end $$;
revoke all on function public.peut_faire_livrer() from public, anon;
grant execute on function public.peut_faire_livrer() to authenticated;

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
  route_m int;
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
  -- (3.70.0) PAR LA ROUTE, quand la fonction serveur « distance-route » l'a
  -- demandée à Google pour ce client (à 50 m près) : le vrai trajet.
  select x.distance_m into route_m from public.distances_route x
   where x.o_lat = public.grille_route(r.livraison_latitude)
     and x.o_lng = public.grille_route(r.livraison_longitude)
     and x.d_lat = public.grille_route(latitude)
     and x.d_lng = public.grille_route(longitude);
  if route_m is not null then
    dist := round(route_m / 1000.0, 3);
  else
    -- Sinon, à vol d'oiseau (formule de haversine, rayon terrestre de
    -- 6 371 km), multipliée par le coefficient de la route ; au mètre près.
    dlat := radians(latitude - r.livraison_latitude);
    dlng := radians(longitude - r.livraison_longitude);
    a := sin(dlat / 2) ^ 2
         + cos(radians(r.livraison_latitude)) * cos(radians(latitude)) * sin(dlng / 2) ^ 2;
    dist := round((2 * 6371 * asin(least(1, sqrt(a))) * r.livraison_coef)::numeric, 3);
  end if;
  -- Le kilomètre ENTAMÉ compte : 10,001 km facturent un kilomètre de plus.
  km := case when dist > r.livraison_rayon_km then ceil(dist - r.livraison_rayon_km)::int else 0 end;
  forf := case when v = 'tricycle' then r.tricycle_forfait else r.moto_forfait end;
  prix := case when v = 'tricycle' then r.tricycle_prix_km else r.moto_prix_km end;
  return jsonb_build_object(
    'vehicule', v,
    'distance_km', round(dist, 1),
    -- (3.70.0) « route » : le trajet réel (Google) ; « vol_oiseau » : estimé.
    'calcul', case when route_m is not null then 'route' else 'vol_oiseau' end,
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

create or replace function public.livraison_active() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.livraison_latitude is not null and p.livraison_longitude is not null
                     from public.paiement p where p.id = 1), false);
$$;
revoke all on function public.livraison_active() from public;
grant execute on function public.livraison_active() to anon, authenticated;

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

-- ---------- Ce que ce fichier change ----------
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
          coalesce(nullif(' — ' || (fiche -> 'retrait' ->> 'adresse'), ' — '), '') ||
          -- (3.70.0) Le numéro de la boutique, pour l'appeler s'il se perd.
          coalesce(' — Tél. boutique : +' || coalesce(nullif(fiche -> 'retrait' ->> 'indicatif', ''), '229') || ' ' ||
                   nullif(fiche -> 'retrait' ->> 'tel', ''), '') || E'\n' ||
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

create or replace function public.faire_livrer(
  articles jsonb, client jsonb, destination jsonb, frais bigint, transaction text,
  montant bigint, reseau text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  moi    uuid := auth.uid();
  qui    text;
  net    text := upper(left(regexp_replace(coalesce(transaction, ''), '[^A-Za-z0-9._-]', '', 'g'), 64));
  cle    text;
  res    text := upper(trim(coalesce(reseau, '')));
  g      jsonb;
  c      public.commandes%rowtype;
  compte uuid;
begin
  if moi is null or not public.peut_faire_livrer() then
    raise exception 'Faire livrer une commande prise sur WhatsApp demande le droit « Faire livrer », que le superadministrateur accorde.'
      using errcode = 'P0001';
  end if;
  if coalesce(trim(client ->> 'nom'), '') = '' then
    raise exception 'Indiquez le nom du client.' using errcode = 'P0001';
  end if;
  if coalesce(trim(client ->> 'adresse'), '') = '' then
    raise exception 'Indiquez l''adresse de livraison du client.' using errcode = 'P0001';
  end if;
  if length(net) < 4 then
    raise exception 'Saisissez la référence de la transaction du client, lue sur son reçu de paiement.'
      using errcode = 'P0001';
  end if;
  if res not in ('', 'MTN', 'MOOV', 'CELTIIS') then
    raise exception 'Le réseau du paiement : MTN, Moov ou Celtiis.' using errcode = 'P0001';
  end if;
  if coalesce(montant, 0) <= 0 then
    raise exception 'Indiquez le montant que le client a payé.' using errcode = 'P0001';
  end if;
  if frais is null or frais < 0 or frais > 1000000 then
    raise exception 'Indiquez les frais de livraison convenus avec le client (0 s''il n''y en a pas).'
      using errcode = 'P0001';
  end if;
  -- (3.70.0) Où récupérer : refusé plutôt que coupé en silence — la fin
  -- coupée, c'est souvent la dernière boutique ou le numéro à appeler.
  if length(btrim(coalesce(client ->> 'retrait', ''))) > 500 then
    raise exception 'Où récupérer la commande : 500 caractères au plus. Raccourcissez-le.'
      using errcode = 'P0001';
  end if;
  -- UNE TRANSACTION NE PAIE QU'UNE COMMANDE : ni une autre commande, ni un
  -- reste payé à la livraison. Comparées sans ponctuation ni casse : un
  -- reçu se recopie de plusieurs façons.
  cle := regexp_replace(net, '[^A-Z0-9]', '', 'g');
  if exists (select 1 from public.commandes x
              where regexp_replace(upper(x.transaction_id), '[^A-Z0-9]', '', 'g') = cle)
     or exists (select 1 from public.encaissements e
                 where regexp_replace(upper(e.transaction_id), '[^A-Z0-9]', '', 'g') = cle) then
    raise exception 'Cette transaction a déjà servi pour une autre commande : vérifiez la référence.'
      using errcode = 'P0001';
  end if;

  -- LE MONTANT D'ABORD, avant d'écrire quoi que ce soit : une commande
  -- refusée après coup aurait déjà pris un numéro « BZ- », et un trou
  -- dans les numéros fait croire au point qu'une commande manque.
  g := public.devis_faire_livrer(articles, null);
  if montant < (g ->> 'sous_total')::bigint + frais then
    raise exception 'Le client a payé %, mais la commande coûte % (dont % de livraison). Vérifiez le montant ou les articles.',
      public.montant_lisible(montant, g ->> 'devise'),
      public.montant_lisible((g ->> 'sous_total')::bigint + frais, g ->> 'devise'),
      public.montant_lisible(frais, g ->> 'devise')
      using errcode = 'P0001';
  end if;

  -- La commande, par le chemin de toutes les commandes : prix, stock,
  -- boutique ouverte, frais. Tout se paie d'un coup (pas d'acompte).
  perform set_config('bizzoo.hors_appli', 'oui', true);
  perform set_config('bizzoo.frais_saisis', frais::text, true);
  g := public.creer_commande(client, articles, '', false, false, destination);
  perform set_config('bizzoo.frais_saisis', '', true);
  perform set_config('bizzoo.hors_appli', '', true);
  select * into c from public.commandes where id = g ->> 'id';

  if montant < c.total then
    raise exception 'Le client a payé %, mais la commande coûte % (dont % de livraison). Vérifiez le montant ou les articles.',
      public.montant_lisible(montant, c.devise), public.montant_lisible(c.total, c.devise),
      public.montant_lisible(coalesce(c.frais_livraison, 0), c.devise)
      using errcode = 'P0001';
  end if;

  -- LE COMPTE DU CLIENT, s'il en a un à ce numéro (et un seul) : la
  -- commande apparaît dans son application, avec le suivi et « J'ai bien
  -- reçu », comme s'il l'avait passée lui-même.
  select min(k.id::text)::uuid into compte
    from public.clients k
   where regexp_replace(coalesce(k.tel, ''), '\D', '', 'g') = c.client_tel
     and coalesce(nullif(k.indicatif, ''), '229') = coalesce(nullif(c.client_indicatif, ''), '229')
  having count(*) = 1;

  select coalesce(nullif(trim(p.nom), ''), nullif(p.email, ''), 'l''équipe') into qui
    from public.profils p where p.id = moi;

  perform set_config('bizzoo.interne', 'oui', true);
  update public.commandes
     set origine = 'whatsapp', saisie_par = moi, client_id = coalesce(client_id, compte),
         -- (3.70.0) Où le livreur récupère la commande, saisi par l'équipe.
         -- Facultatif ici : l'écran d'avant la 3.70.0 ne l'envoie pas.
         lieu_retrait = btrim(coalesce(client ->> 'retrait', ''))
   where id = c.id;
  perform set_config('bizzoo.interne', '', true);

  -- Payée : le client a TOUT réglé, rien ne reste à encaisser à la porte.
  perform set_config('bizzoo.paiement', 'oui', true);
  update public.commandes
     set etat = 'payee', paye_le = now(), transaction_id = net,
         confirme_par = coalesce(qui, 'l''équipe'), remarque = '', verse = montant
   where id = c.id;
  perform set_config('bizzoo.paiement', '', true);
  perform public.noter_versement(c.id, 'payee', 'whatsapp', res, '', net, c.total, montant,
    'Commande WhatsApp saisie par ' || coalesce(qui, 'l''équipe') || '.');

  select * into c from public.commandes where id = c.id;
  return jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'total', c.total, 'devise', c.devise,
    'frais_livraison', c.frais_livraison, 'livraison', c.livraison,
    'verse', c.verse, 'client_relie', c.client_id is not null,
    -- (3.70.0) Ce qui a été gardé : l'écran sait ainsi que la base est à jour.
    'lieu_retrait', c.lieu_retrait);
end $$;
revoke all on function public.faire_livrer(jsonb, jsonb, jsonb, bigint, text, bigint, text) from public, anon;
grant execute on function public.faire_livrer(jsonb, jsonb, jsonb, bigint, text, bigint, text) to authenticated;
