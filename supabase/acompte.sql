-- =========================================================
-- BIZZOO — l'acompte à la commande
--
-- Un client qui commande règle EN LIGNE une part du total
-- — 10 % par défaut — pour que sa commande parte. Le reste se
-- paie à la livraison. Commander engage donc déjà de l'argent :
-- c'est ce qui écarte les commandes fictives.
--
-- CE QUE ÇA CHANGE.
--
--   1. LE TAUX EST À VOUS, superadministrateur, dans les réglages
--      du paiement : de 1 à 100 %. 100 revient à tout faire payer
--      en ligne, comme avant. Personne d'autre ne peut le changer :
--      c'est la même règle d'écriture que pour l'agrégateur.
--
--   2. LA BASE CALCULE L'ACOMPTE, jamais le téléphone : le taux du
--      jour appliqué au total, remise déduite, arrondi au franc
--      supérieur, 100 FCFA au moins (le minimum de FeexPay), jamais
--      plus que le total. Il est figé sur la commande : changer le
--      taux demain ne réécrit pas les commandes d'hier.
--
--   3. L'AGRÉGATEUR DEMANDE L'ACOMPTE, et la commande part dès qu'il
--      est reçu : les boutiques sont prévenues et le stock décompté,
--      comme avant. Un versement plus petit que l'acompte reste
--      « incomplet ». Les fonctions Edge ne changent pas : celle de
--      FeexPay lit dans la base le montant à demander, et c'est
--      désormais l'acompte.
--
--   4. LE RESTE SE PAIE À LA LIVRAISON, à chaque boutique sa part :
--      une commande qui traverse deux boutiques est livrée en deux
--      fois, et chacune encaisse ce qui lui revient. Le livreur voit
--      ce montant-là, et aucun autre. Un article annulé ne se paie
--      pas : la part de sa boutique baisse d'autant.
--
--   5. LES APPLICATIONS DÉJÀ INSTALLÉES NE CHANGENT PAS. Elles ne
--      savent rien de l'acompte : leurs commandes se paient en
--      entier, comme elles l'annoncent au client. L'acompte vaut
--      pour les commandes passées depuis la 3.57.0.
--
-- Les commandes passées avant ce fichier se sont payées en entier :
-- il ne leur reste rien à encaisser.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, et aucune donnée n'est supprimée.
-- =========================================================

-- ---------- Le taux, dans les réglages du paiement ----------
-- La table est lisible par tous — l'application des clients en a besoin
-- pour annoncer l'acompte avant de commander — et seul le
-- superadministrateur y écrit.
alter table public.paiement
  add column if not exists taux_acompte int not null default 10;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'paiement_taux_acompte_borne') then
    alter table public.paiement
      add constraint paiement_taux_acompte_borne
      check (taux_acompte between 1 and 100);
  end if;
end $$;

-- ---------- L'acompte, figé sur la commande ----------
--   taux_acompte : le taux du jour, en pour cent ;
--   acompte      : ce qui se paie en ligne pour que la commande parte ;
--   verse        : ce que l'agrégateur a réellement encaissé.
alter table public.commandes add column if not exists taux_acompte int;
alter table public.commandes add column if not exists acompte int;
alter table public.commandes add column if not exists verse int;

-- Les colonnes que les fonctions ci-dessous écrivent ou lisent. Elles
-- viennent d'ailleurs, et sont répétées ici : un fichier qui pose une
-- fonction pose aussi les colonnes dont elle se sert.
alter table public.commandes add column if not exists transaction_annoncee text not null default '';
alter table public.commandes add column if not exists fournisseur_ref text not null default '';
alter table public.commandes add column if not exists tentative_le timestamptz;
alter table public.commandes add column if not exists client_id uuid;
alter table public.commandes add column if not exists compte_supprime boolean not null default false;
alter table public.commandes add column if not exists revendeur boolean not null default false;

-- ---------- Personne ne les écrit à la main ----------
-- Une commande naît sans acompte ni versement : « creer_commande » pose
-- l'acompte une fois le total connu, et seul l'agrégateur dit ce qu'il a
-- reçu. Et l'équipe ne les réécrit pas : ce serait changer ce que le
-- livreur va réclamer à la porte du client.
create or replace function public.est_revendeur() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.clients c
                  where c.id = auth.uid() and c.revendeur_etat = 'validee');
$$;
create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;
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
  new.verse := null;
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
  or new.verse is distinct from old.verse
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

-- ---------- Ce qui reste à payer à la livraison ----------
create or replace function public.restes_par_boutique(cible text)
returns table (boutique_id text, a_encaisser bigint)
language sql stable security definer set search_path = public as $$
  with commande as (
    select c.total::numeric as total,
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
    select greatest(0, coalesce(round(c.total * sum(p.servi) / nullif(sum(p.brut), 0)), 0)
                       - c.deja) as du,
           sum(p.servi) as servi
      from commande c, parts p
     group by c.total, c.deja
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
$$;
revoke all on function public.restes_par_boutique(text) from public, anon, authenticated;

-- Lu avec la commande : « commandes?select=*,restes ». À chacun ce qui
-- le regarde : l'enseigne et le client voient toutes les parts, une
-- boutique la sienne.
create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false);
$$;
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
create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils where id = auth.uid() and actif;
$$;
create or replace function public.restes(cmd public.commandes)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  o     public.commandes%rowtype;
  tout  boolean;
  chez  text;
  parts jsonb;
begin
  select * into o from public.commandes c where c.id = cmd.id;
  if not found then return null; end if;

  tout := public.est_super()
       or public.droit_enseigne('commandes')
       or (o.client_id is not null and o.client_id = auth.uid());
  if not tout then
    chez := public.boutique_du_compte();
    if chez is null or not public.est_equipe() or public.est_compte_enseigne()
       or not exists (select 1 from public.commande_lignes l
                       where l.commande_id = o.id and l.boutique_id = chez) then
      return null;
    end if;
  end if;

  select coalesce(jsonb_object_agg(r.boutique_id, r.a_encaisser), '{}'::jsonb)
    into parts
    from public.restes_par_boutique(o.id) r
   where r.boutique_id is not null and (tout or r.boutique_id = chez);

  return jsonb_build_object(
    'reste', (select coalesce(sum(r.a_encaisser), 0)
                from public.restes_par_boutique(o.id) r
               where tout or r.boutique_id = chez),
    'boutiques', parts);
end $$;
revoke all on function public.restes(public.commandes) from public, anon;
grant execute on function public.restes(public.commandes) to authenticated;

-- ---------- La commande pose son acompte ----------
-- Un paramètre de plus, « avec_acompte », que seules les applications
-- 3.57.0 envoient. Les anciennes l'omettent : leurs commandes se paient
-- en entier, comme elles le disent au client.
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
drop function if exists public.creer_commande(jsonb, jsonb, text);
create or replace function public.creer_commande(
  client jsonb, articles jsonb, code text default '',
  avec_acompte boolean default false)
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
  taux     int;
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
  taux := case when coalesce(avec_acompte, false)
               then coalesce((select pa.taux_acompte from public.paiement pa where pa.id = 1), 100)
               else 100 end;
  perform set_config('bizzoo.interne', 'oui', true);
  update public.commandes c
     set taux_acompte = taux,
         acompte = case when c.total <= 0 then 0
                        else least(c.total, greatest(ceil(c.total * taux / 100.0)::int, 100)) end
   where c.id = nouvelle;
  perform set_config('bizzoo.interne', '', true);

  select jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'total', c.total, 'devise', c.devise,
    'etat', c.etat,
    /* Ce que le code a retiré, et lequel. Le récapitulatif doit pouvoir
       le dire : un client qui a tapé un code et ne le voit nulle part
       croit qu'il n'a pas été pris. */
    'code_promo', c.code_promo, 'remise', c.remise,
    /* Ce qui se paie maintenant, et ce qui restera pour la livraison. */
    'taux_acompte', c.taux_acompte, 'acompte', c.acompte,
    'reste', greatest(0, c.total - c.acompte),
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
revoke all on function public.creer_commande(jsonb, jsonb, text, boolean) from public;
grant execute on function public.creer_commande(jsonb, jsonb, text, boolean) to anon, authenticated;

-- ---------- Suivre sa commande : l'acompte et le reste ----------
create or replace function public.suivre_commande(cible text, tel text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.commandes%rowtype;
begin
  select * into c from public.commandes
   where id = cible
     and not compte_supprime
     and client_tel = regexp_replace(coalesce(tel, ''), '\D', '', 'g');
  if not found then return null; end if;
  return jsonb_build_object(
    'numero', c.numero, 'etat', c.etat, 'total', c.total, 'devise', c.devise,
    'paye_le', c.paye_le, 'remarque', c.remarque,
    -- L'acompte, ce qui a été versé, et ce qui reste à payer à la
    -- livraison, boutique par boutique. Une commande d'avant l'acompte
    -- se payait en entier : son acompte est son total.
    'taux_acompte', coalesce(c.taux_acompte, 100),
    'acompte', coalesce(c.acompte, c.total),
    'verse', c.verse,
    'reste', (select coalesce(sum(r.a_encaisser), 0)
                from public.restes_par_boutique(c.id) r),
    'restes', (select coalesce(jsonb_object_agg(r.boutique_id, r.a_encaisser), '{}'::jsonb)
                 from public.restes_par_boutique(c.id) r
                where r.boutique_id is not null));
end $$;
revoke all on function public.suivre_commande(text, text) from public;
grant execute on function public.suivre_commande(text, text) to anon, authenticated;

-- ---------- Encaisser l'acompte ----------
-- Ce qui est attendu en ligne, c'est l'acompte. Ce qui est reçu se garde
-- dans « verse » : c'est de lui que se déduit ce que le livreur réclame.
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
drop function if exists public.marquer_payee(text, text, int);
create or replace function public.marquer_payee(
  reference text, transaction text, montant int, qui text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c   public.commandes%rowtype;
  net text := left(regexp_replace(coalesce(transaction, ''), '[^A-Za-z0-9_-]', '', 'g'), 64);
  du  int;
begin
  if net = '' then return jsonb_build_object('ok', false, 'raison', 'transaction absente'); end if;

  -- On ne retrouve la commande QUE par la référence que nous avons
  -- nous-mêmes confiée à KkiaPay en ouvrant le paiement. Se rabattre sur
  -- la transaction annoncée par un téléphone laisserait le client
  -- choisir quel versement valide quelle commande — un versement de
  -- 100 000 réglant une commande de 100 francs. Sans référence, c'est la
  -- boutique qui tranche, à la main (confirmer_paiement), avec sous les
  -- yeux la transaction annoncée.
  select * into c from public.commandes where id = coalesce(reference, '');
  if not found then
    -- Un paiement qui ne nous concerne pas n'est pas une erreur. Mais il
    -- se note : un versement qui ne trouve pas sa commande est
    -- exactement ce qu'on veut voir au journal.
    perform public.noter_versement(null, 'inconnue', qui, '', coalesce(reference, ''),
      net, 0, coalesce(montant, 0),
      'Versement reçu pour une commande introuvable.');
    return jsonb_build_object('ok', true, 'raison', 'commande inconnue');
  end if;

  if c.etat = 'payee' then
    return jsonb_build_object('ok', true, 'deja', true, 'numero', c.numero);
  end if;

  -- CE QUI EST ATTENDU EN LIGNE, c'est l'acompte : le reste se paie à la
  -- livraison. Une commande d'avant l'acompte se payait en entier.
  du := coalesce(c.acompte, c.total);

  perform set_config('bizzoo.paiement', 'oui', true);

  -- Cette transaction est déjà rattachée à une autre commande. On le
  -- NOTE au lieu de lever une erreur : une erreur ferait réessayer
  -- KkiaPay cinq fois pour rien, et l'encaissement resterait bloqué.
  if exists (select 1 from public.commandes a
              where a.transaction_id = net and a.id <> c.id) then
    update public.commandes
       set remarque = 'Transaction ' || net || ' déjà rattachée à une autre commande.'
     where id = c.id;
    -- L'agrégateur et l'opérateur se reprennent tout seuls sur la ligne
    -- d'ouverture : c'est « noter_versement » qui s'en charge.
    perform public.noter_versement(c.id, 'conflit', qui, '',
      c.fournisseur_ref, net, du, coalesce(montant, 0),
      'Transaction déjà rattachée à une autre commande.');
    return jsonb_build_object('ok', true, 'conflit', true, 'numero', c.numero);
  end if;

  -- Le montant qui compte est celui que l'agrégateur annonce. S'il manque
  -- quelque chose, on ne valide pas : on écrit ce qu'on a reçu, et la
  -- boutique tranche. La preuve, elle, n'est pas posée : la commande
  -- n'est pas payée.
  if coalesce(montant, 0) < du then
    update public.commandes
       set remarque = 'Paiement incomplet : ' || coalesce(montant, 0)::text
                      || ' reçus sur ' || du::text || ' attendus'
                      || ' (transaction ' || net || ').'
     where id = c.id;
    perform public.noter_versement(c.id, 'incomplete', qui, '',
      c.fournisseur_ref, net, du, coalesce(montant, 0),
      'Reçu ' || coalesce(montant, 0)::text || ' sur ' || du::text || ' attendus.');
    return jsonb_build_object('ok', true, 'incomplet', true, 'numero', c.numero);
  end if;

  -- « verse » garde ce qui est RÉELLEMENT entré : c'est de lui que se
  -- déduit ce que le livreur réclamera. Un client qui a tout payé en
  -- ligne ne doit plus rien à la porte.
  update public.commandes
     set etat = 'payee', paye_le = now(), transaction_id = net,
         confirme_par = '', remarque = '', verse = coalesce(montant, 0)
   where id = c.id;
  -- La remarque vient d'être effacée sur la commande : c'est le journal,
  -- désormais, qui garde ce qui s'est passé avant cette réussite.
  perform public.noter_versement(c.id, 'payee', qui, '',
    c.fournisseur_ref, net, du, coalesce(montant, 0),
    case when du < c.total then 'Acompte encaissé.' else 'Versement encaissé.' end);
  return jsonb_build_object('ok', true, 'numero', c.numero, 'total', c.total,
                            'verse', coalesce(montant, 0));
end $$;
revoke all on function public.marquer_payee(text, text, int, text)
  from public, anon, authenticated;
drop function if exists public.noter_reference(text, text);
create or replace function public.noter_reference(
  cible text, reference text,
  qui text default '', ou text default '')
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  net text := left(regexp_replace(coalesce(reference, ''), '[^A-Za-z0-9_-]', '', 'g'), 96);
  c   public.commandes%rowtype;
begin
  if net = '' then return false; end if;
  select * into c from public.commandes where id = coalesce(cible, '');
  if not found or c.etat <> 'a_payer' then return false; end if;

  -- Déjà prise par une autre commande : on ne la vole pas.
  if exists (select 1 from public.commandes a
              where a.fournisseur_ref = net and a.id <> c.id) then
    return false;
  end if;

  -- UN FREIN. Chaque appel fait sonner un téléphone : sans lui, on
  -- pourrait harceler n'importe quel numéro de demandes de paiement
  -- venues de l'enseigne — et c'est le compte marchand de BIZZOO qui
  -- en répondrait. Trente secondes laissent le temps de voir la
  -- demande arriver, et de se tromper de numéro sans être bloqué.
  if c.tentative_le is not null and c.tentative_le > now() - interval '30 seconds' then
    return false;
  end if;

  perform set_config('bizzoo.paiement', 'oui', true);
  -- Une commande non payée peut être retentée avec un autre numéro :
  -- la nouvelle tentative remplace alors l'ancienne référence.
  update public.commandes
     set fournisseur_ref = net, tentative_le = now()
   where id = c.id;

  -- Au journal. C'est ICI, et nulle part ailleurs, qu'on sait chez quel
  -- opérateur la demande est partie : ni la notification ni la
  -- vérification ne le rappellent. Ce qui est demandé, c'est l'acompte.
  perform public.noter_versement(c.id, 'ouverte', qui, ou, net, '',
    coalesce(c.acompte, c.total), 0, 'Demande de paiement envoyée.');
  return true;
end $$;
revoke all on function public.noter_reference(text, text, text, text)
  from public, anon, authenticated;

-- « total » est ce que l'agrégateur doit demander : l'acompte. La fonction
-- Edge « feexpay » déployée lit ce champ-là, et n'a pas à changer.
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
    'tentative_le', c.tentative_le);
end $$;
revoke all on function public.commande_pour_paiement(text, text)
  from public, anon, authenticated;

-- L'enseigne qui se porte garante le fait pour l'acompte.
create or replace function public.confirmer_paiement(cible text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  qui    text;
  montant bigint;
begin
  if not public.est_super() then
    raise exception 'Seule l''enseigne peut confirmer un paiement à la main';
  end if;
  select coalesce(p.email, '') into qui from public.profils p where p.id = auth.uid();
  perform set_config('bizzoo.paiement', 'oui', true);
  -- Ce dont l'enseigne se porte garante, c'est de l'ACOMPTE : le reste
  -- se paie à la livraison, et reste dû.
  update public.commandes
     set etat = 'payee', paye_le = now(), confirme_par = coalesce(qui, 'enseigne'),
         verse = coalesce(acompte, total)
   where id = cible and etat <> 'payee'
  returning verse into montant;

  -- Au journal, et NOMMÉMENT « main ». Un encaissement à la main n'est
  -- pas un versement comme un autre : personne ne l'a vérifié chez
  -- l'agrégateur, quelqu'un s'en est porté garant. Des mois plus tard,
  -- c'est la première chose qu'on veut pouvoir distinguer.
  --
  -- « montant » ne vaut quelque chose que si la mise à jour a porté :
  -- une commande déjà payée ne se re-note pas.
  if montant is not null then
    perform public.noter_versement(cible, 'payee', 'main', '', '', '',
      montant, montant,
      'Confirmé à la main par ' || coalesce(nullif(qui, ''), 'l''enseigne') || '.');
  end if;
end $$;
revoke all on function public.confirmer_paiement(text) from public, anon;
grant execute on function public.confirmer_paiement(text) to authenticated;

-- ---------- Le livreur voit ce qu'il doit encaisser ----------
create or replace function public.est_livreur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'livreur', false);
$$;
drop function if exists public.mes_livraisons();
create or replace function public.mes_livraisons()
returns table (
  commande_id text, numero text,
  boutique_id text, nom_boutique text,
  client_nom text, client_tel text, client_indicatif text,
  client_adresse text, note text,
  etat text, articles jsonb, paye_le timestamptz,
  a_encaisser bigint)
language plpgsql stable security definer set search_path = public as $$
declare moi uuid := auth.uid();
begin
  if moi is null or not public.est_livreur() then return; end if;
  return query
    select c.id, c.numero,
           l.boutique_id,
           coalesce((select b.nom from public.boutiques b where b.id = l.boutique_id), '')::text,
           c.client_nom, c.client_tel, c.client_indicatif,
           c.client_adresse, c.note,
           -- L'étape la MOINS avancée de ses lignes : c'est elle qui dit
           -- ce qu'il lui reste à faire.
           min(l.etat)::text,
           jsonb_agg(jsonb_build_object(
             'nom', l.nom, 'code', l.code, 'quantite', l.quantite)
             order by l.nom),
           c.paye_le,
           -- Ce qu'il réclame au client : la part du reste qui revient à
           -- SA boutique. Zéro quand tout a été payé en ligne.
           coalesce((select r.a_encaisser
                       from public.restes_par_boutique(c.id) r
                      where r.boutique_id is not distinct from l.boutique_id), 0)::bigint
      from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
     where l.livreur_id = moi
       and c.etat = 'payee'
       and l.etat in ('preparee', 'en_livraison', 'remise')
       -- Une course remise depuis plus de deux jours n'a plus à
       -- encombrer sa liste.
       and (l.etat <> 'remise' or c.paye_le > now() - interval '2 days')
     group by c.id, c.numero, l.boutique_id, c.client_nom, c.client_tel,
              c.client_indicatif, c.client_adresse, c.note, c.paye_le
     order by c.paye_le;
end $$;
revoke all on function public.mes_livraisons() from public, anon;
grant execute on function public.mes_livraisons() to authenticated;

-- ---------- Les notifications le disent ----------
-- « Acompte reçu », et ce qui reste à payer à la livraison ; à chaque
-- boutique, ce qu'elle encaissera.
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
create or replace function public.notifier_paiement() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  b        record;
  numero   text := coalesce(new.numero, '');
  client   uuid := new.client_id;
  devise   text := ' ' || coalesce(nullif(new.devise, ''), 'FCFA');
  reste    bigint;
begin
  if new.etat is not distinct from old.etat or new.etat <> 'payee' then
    return new;
  end if;

  -- CE QUI RESTE À PAYER À LA LIVRAISON. À zéro — tout réglé en ligne —
  -- les messages restent ceux d'avant l'acompte. Les montants s'écrivent
  -- comme dans les applications : « 13 500 FCFA ».
  select coalesce(sum(r.a_encaisser), 0) into reste
    from public.restes_par_boutique(new.id) r;

  -- Le client, s'il a un compte. Une commande passée sans compte n'a
  -- personne à prévenir — le reçu lui est déjà revenu par WhatsApp.
  if client is not null then
    perform public.notifier(array[client], 'commande_payee',
      case when reste > 0 then 'Acompte reçu' else 'Paiement reçu' end,
      'Votre commande ' || numero || ' est confirmée. Nous la préparons.' ||
        case when reste > 0
             then ' Reste à payer à la livraison : ' ||
                  replace(to_char(reste, 'FM999,999,999,990'), ',', ' ') || devise || '.'
             else '' end,
      '#/commande/' || new.id, new.id, null, true);
  end if;

  -- Chaque boutique concernée, une fois, avec CE QU'ELLE encaissera : sa
  -- part du reste, que son livreur réclamera à la porte.
  for b in select r.boutique_id, r.a_encaisser
             from public.restes_par_boutique(new.id) r
            where r.boutique_id is not null loop
    perform public.notifier(public.equipe_de(b.boutique_id), 'commande_payee',
      case when b.a_encaisser > 0 then 'Nouvelle commande confirmée' else 'Nouvelle commande payée' end,
      case when b.a_encaisser > 0
           then 'La commande ' || numero || ' est confirmée par son acompte. À préparer — ' ||
                replace(to_char(b.a_encaisser, 'FM999,999,999,990'), ',', ' ') || devise ||
                ' à encaisser à la livraison.'
           else 'La commande ' || numero || ' est payée. À préparer.' end,
      '#/commandes/' || new.id, new.id, b.boutique_id, true);
  end loop;

  perform public.notifier(public.enseigne_des_commandes(), 'commande_payee',
    case when reste > 0 then 'Nouvelle commande confirmée' else 'Nouvelle commande payée' end,
    'La commande ' || numero ||
      case when reste > 0 then ' vient d''être confirmée par son acompte.'
           else ' vient d''être payée.' end,
    '#/commandes/' || new.id, new.id, null, true);

  perform public.notifier(public.les_superadmins(), 'commande_payee',
    case when reste > 0 then 'Acompte encaissé' else 'Paiement encaissé' end,
    'La commande ' || numero ||
      case when reste > 0
           then ' : acompte de ' ||
                replace(to_char(coalesce(new.verse, new.acompte, 0), 'FM999,999,999,990'), ',', ' ') ||
                devise || ' encaissé, ' ||
                replace(to_char(reste, 'FM999,999,999,990'), ',', ' ') || devise ||
                ' à encaisser à la livraison.'
           else ' est payée.' end,
    '#/commandes/' || new.id, new.id, null, true);

  return new;
end $$;
