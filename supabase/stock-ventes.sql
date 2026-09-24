-- =========================================================
-- BIZZOO — le stock suit les ventes
--
-- À exécuter UNE FOIS dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
-- Se rejoue sans dommage.
--
-- CE QUE ÇA CHANGE.
--
--   1. UNE COMMANDE NE DÉPASSE PLUS LE STOCK. La base refusait un
--      produit à zéro, mais dix pièces passaient quand il en restait
--      trois. Elle compte désormais par produit, et répond au client
--      « Plus que 3 en stock pour … ». Un produit « sur commande » ou
--      en approvisionnement garde sa liberté : la boutique le fait
--      venir.
--
--   2. UNE VENTE PAYÉE SORT DU STOCK, toute seule, au moment où la
--      commande passe à « payée » — par l'agrégateur ou par l'enseigne
--      à la main. Ce qui a été pris se note sur la ligne de commande.
--      À zéro, le produit passe « En rupture » chez les clients, et la
--      boutique en est prévenue.
--
--   3. UN PAIEMENT NE S'ANNULE JAMAIS À CAUSE DU STOCK. Si deux
--      clients paient la dernière pièce à une seconde d'écart, le
--      second passe quand même — l'argent est déjà chez l'agrégateur —,
--      le stock s'arrête à zéro, et la boutique, l'enseigne et le
--      superadministrateur sont prévenus qu'il manque des pièces.
--
--   4. UNE VENTE ANNULÉE REND SON STOCK — ce qu'elle avait pris, ni
--      plus ni moins.
--
-- Les commandes déjà payées avant ce fichier ne sont pas reprises :
-- leur stock a pu être corrigé à la main depuis, et le décompter une
-- seconde fois fausserait ce qui est juste.
-- =========================================================

-- Ce qu'une ligne a réellement pris au stock : c'est ce qui se rend.
alter table public.commande_lignes
  add column if not exists stock_pris int not null default 0 check (stock_pris >= 0);

-- ---------- La commande, bornée au stock ----------
-- Avec ce qu'elle appelle, pour qu'une base qui n'aurait pas reçu les
-- fichiers précédents dans l'ordre ne s'arrête pas à la première vente.

create or replace function public.compte_exige() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select r.compte_obligatoire from public.reglages r where r.id = 1), false);
$$;

revoke all on function public.compte_exige() from public, anon, authenticated;
grant execute on function public.compte_exige() to anon, authenticated;

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
   where c.id = cible;
  perform set_config('bizzoo.interne', avant, true);
end $$;

revoke all on function public.commande_total(text) from public, anon, authenticated;

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

  if brute <= 0 then
    return jsonb_build_object('ok', false, 'remise', 0,
      'raison', 'Ce code ne s''applique pas à ce panier.');
  end if;
  return jsonb_build_object('ok', true, 'remise', brute, 'raison', '');
end $$;

revoke all on function public.remise_du_code(text, bigint, bigint, uuid, text)
  from public, anon, authenticated;

drop function if exists public.creer_commande(jsonb, jsonb);

create or replace function public.creer_commande(
  client jsonb, articles jsonb, code text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
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

  -- Un compte de l'équipe ne passe pas commande pour lui-même : il agirait
  -- avec les droits d'une boutique sur une commande qui lui appartient.
  if moi is not null and not exists (select 1 from public.clients c where c.id = moi) then
    moi    := null;
    equipe := true;
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
  if moi is null and public.compte_exige() then
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

  for article in select * from jsonb_array_elements(articles) loop
    qte := greatest(1, least(99, coalesce((article ->> 'quantite')::int, 1)));
    select * into p from public.produits where id = article ->> 'produit_id';
    if not found then
      raise exception 'Un des produits de votre panier n''existe plus.';
    end if;
    if coalesce(p.stock, 0) <= 0 and not coalesce(p.sur_commande, false)
       and (p.appro_le is null or p.appro_le < current_date) then
      raise exception '« % » n''est plus disponible : retirez-le du panier.', p.nom;
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

  select jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'total', c.total, 'devise', c.devise,
    'etat', c.etat,
    /* Ce que le code a retiré, et lequel. Le récapitulatif doit pouvoir
       le dire : un client qui a tapé un code et ne le voit nulle part
       croit qu'il n'a pas été pris. */
    'code_promo', c.code_promo, 'remise', c.remise,
    'boutiques', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', g.boutique_id,
               'nom', coalesce((select b.nom from public.boutiques b where b.id = g.boutique_id), ''),
               'whatsapp', coalesce((select b.whatsapp from public.boutiques b where b.id = g.boutique_id), ''),
               'indicatif', coalesce((select b.indicatif from public.boutiques b where b.id = g.boutique_id), '229'),
               'montant', g.montant,
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

revoke all on function public.creer_commande(jsonb, jsonb, text) from public;
grant execute on function public.creer_commande(jsonb, jsonb, text) to anon, authenticated;

-- ---------- Qui prévenir ----------

create or replace function public.equipe_de(cible text) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and cible is not null and p.boutique_id = cible
     and p.role in ('administrateur', 'moderateur');
$$;

create or replace function public.enseigne_des_commandes() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.boutique_id is null and p.peut_commandes
     and p.role in ('administrateur', 'moderateur');
$$;

create or replace function public.les_superadmins() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.role = 'superadministrateur';
$$;

revoke all on function public.equipe_de(text)            from public, anon, authenticated;
revoke all on function public.enseigne_des_commandes()   from public, anon, authenticated;
revoke all on function public.les_superadmins()          from public, anon, authenticated;

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

-- ---------- Le décompte, et le retour ----------

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
      end if;
    exception when others then
      -- Le produit refuse l'écriture — un rayon devenu incohérent, par
      -- exemple. Le paiement, lui, passe : on le dit à qui peut corriger.
      ratees := jsonb_set(ratees, array[l.boutique],
        coalesce(ratees -> l.boutique, '[]'::jsonb) || to_jsonb(l.nom));
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
        '#/stock?filtre=rupture', new.id, nullif(b, ''), false);
    end loop;
    for b in select jsonb_object_keys(ratees) loop
      select string_agg(x, ', ') into liste from jsonb_array_elements_text(ratees -> b) x;
      perform public.notifier(
        public.equipe_de(nullif(b, '')) || public.les_superadmins(),
        'stock_a_verifier', 'Stock à vérifier',
        'Commande ' || numero || ' payée, mais le stock de ' || liste ||
          ' n''a pas pu être décompté. Corrigez-le à la main.',
        '#/stock', new.id, nullif(b, ''), true);
    end loop;
  exception when others then
    raise warning 'commande_stock(%) notifications : %', new.id, sqlerrm;
  end;
  return null;
end $$;

drop trigger if exists commandes_stock on public.commandes;
create trigger commandes_stock
  after update of etat on public.commandes
  for each row execute function public.commande_stock();

create or replace function public.ligne_stock() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.etat = 'annulee' and old.etat is distinct from 'annulee' and new.stock_pris > 0 then
    perform public.stock_rendre(new.id);
  end if;
  return null;
end $$;

drop trigger if exists lignes_stock on public.commande_lignes;
create trigger lignes_stock
  after update of etat on public.commande_lignes
  for each row execute function public.ligne_stock();

-- Vérification : la trace, le décompte, le retour, la borne — et
-- personne qui rende du stock à la main.
select
  exists (select 1 from information_schema.columns
           where table_schema = 'public' and table_name = 'commande_lignes'
             and column_name = 'stock_pris')                         as "Trace du stock pris",
  exists (select 1 from pg_trigger
           where tgrelid = 'public.commandes'::regclass
             and tgname = 'commandes_stock')                         as "Décompte au paiement",
  exists (select 1 from pg_trigger
           where tgrelid = 'public.commande_lignes'::regclass
             and tgname = 'lignes_stock')                            as "Retour à l'annulation",
  exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'creer_commande'
             and p.prosrc like '%en stock pour%')                    as "Commande bornée au stock",
  not has_function_privilege('anon', 'public.stock_rendre(text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.stock_rendre(text)', 'EXECUTE')
                                                                     as "Personne ne rend à la main";
