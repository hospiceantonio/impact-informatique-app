-- =========================================================
-- BIZZOO — les codes promo
--
-- UNE REMISE SORT DE VOTRE MARGE, jamais de la poche d'une
-- boutique. La boutique touche son prix BIZZOO en entier,
-- comme si le code n'existait pas : elle n'a pas décidé cette
-- promotion, elle n'a pas à la payer.
--
-- C'est pour cela que la remise se pose sur la COMMANDE et
-- jamais sur les lignes : le prix et le prix BIZZOO figés sur
-- chaque ligne ne bougent pas d'un franc.
--
-- ET C'EST POUR CELA QU'IL Y A UN PLAFOND. Une remise ne
-- descend JAMAIS en dessous de ce que les boutiques doivent
-- toucher. Un code de 80 % sur un article qui ne vous laisse
-- que 40 % de marge est ramené à 40 % — sinon vous paieriez la
-- différence de votre poche, à chaque vente, sans vous en
-- apercevoir avant de faire les comptes.
--
-- CE QU'UN CODE PEUT PORTER :
--
--   une remise en POURCENTAGE ou en MONTANT ;
--   un montant minimum de commande ;
--   un nombre total d'utilisations ;
--   une seule fois par client ;
--   une date de fin.
--
-- LES UTILISATIONS SE COMPTENT SUR LES COMMANDES PAYÉES. Un
-- panier abandonné n'a rien coûté à personne, et ne doit pas
-- manger le quota d'un vrai client.
--
-- UNE SEULE RÈGLE, LUE PAR LES DEUX CÔTÉS. L'écran du panier
-- annonce la remise, la caisse l'applique — et tous deux
-- appellent la même fonction. Deux calculs séparés finiraient
-- par diverger, et le client paierait autre chose que ce qu'on
-- lui a montré.
--
-- UN CODE REFUSÉ NE TUE PAS LA COMMANDE : le panier est bon,
-- c'est le code qui ne vaut rien. La commande passe à plein
-- tarif plutôt que de perdre un client pour une ristourne.
--
-- CE QUE CE FICHIER CHANGE LE JOUR OÙ VOUS L'EXÉCUTEZ : rien
-- de visible. Aucun code n'existe encore, et une commande sans
-- code vaut exactement ce qu'elle valait hier. Vous créez vos
-- codes ensuite, depuis l'application.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, et rien n'est supprimé.
-- =========================================================

-- Les colonnes que les fonctions ci-dessous écrivent ou lisent. Elles
-- viennent d'ailleurs, et sont répétées ici : un fichier qui pose une
-- fonction pose aussi les colonnes dont elle se sert.
alter table public.commandes add column if not exists client_id uuid;
alter table public.commandes add column if not exists revendeur boolean not null default false;
alter table public.commandes add column if not exists paye_le timestamptz;
alter table public.commandes add column if not exists code_promo text not null default '';
alter table public.commandes add column if not exists remise bigint not null default 0;
alter table public.commande_lignes add column if not exists code text not null default '';
alter table public.commande_lignes
  add column if not exists prix_bizzoo int not null default 0;
alter table public.commande_lignes add column if not exists taux_marge numeric;
alter table public.boutiques
  add column if not exists taux_revendeur numeric(6,2) not null default 10;
alter table public.boutiques
  add column if not exists revendeur_mode text not null default 'bizzoo';
alter table public.produits_prive add column if not exists taux_revendeur numeric(6,2);

-- ---------- Ce que vaut une commande ----------
-- Le total, c'est la somme de ses lignes MOINS la remise d'un code
-- promo. La règle vit ici, en un seul endroit : le déclencheur des
-- lignes l'appelle, et l'application d'un code aussi. Deux endroits
-- finiraient par diverger, et un client paierait un montant que la
-- base n'aurait pas calculé.
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

create or replace function public.commande_recalcule() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.commande_total(coalesce(new.commande_id, old.commande_id));
  return null;
end $$;

drop trigger if exists lignes_recalculent on public.commande_lignes;
create trigger lignes_recalculent
  after insert or update or delete on public.commande_lignes
  for each row execute function public.commande_recalcule();
-- ---------------------------------------------------------
-- Les trois fonctions que la caisse appelle, recopiées ici
-- ---------------------------------------------------------
-- « creer_commande » consulte la règle du compte obligatoire, et
-- « verifier_code » doit connaître le prix d'un revendeur pour
-- calculer la bonne marge. Un fichier qui pose une fonction pose
-- aussi les fonctions qu'elle appelle : collé seul sur une base qui
-- ne les a pas, celui-ci passerait et s'arrêterait à l'usage.
-- Sur une base qui les a déjà, ce bloc ne fait rien.

alter table public.clients add column if not exists revendeur_etat text not null default 'aucune';
create table if not exists public.reglages (
  id smallint primary key default 1 check (id = 1),
  compte_obligatoire boolean not null default false,
  maj_le timestamptz not null default now()
);
insert into public.reglages (id) values (1) on conflict (id) do nothing;

drop function if exists public.prix_revendeur(int, int);
create or replace function public.prix_revendeur(
  prix_public int,
  prix_bizzoo int,
  taux        numeric default 0,
  mode        text    default 'bizzoo')
returns int
language sql immutable as $$
  with borne as (
    select greatest(0, coalesce(prix_public, 0))::numeric as public,
           greatest(0, coalesce(prix_bizzoo, 0))::numeric as achat,
           -- Un taux hors de [0, 100] est une faute de saisie, pas une
           -- intention : on le ramène, on ne refuse pas la vente.
           greatest(0, least(100, coalesce(taux, 0)))      as t,
           case when mode = 'public' then 'public' else 'bizzoo' end as m
  ),
  brut as (
    select public, achat, m,
           case when m = 'public' then public * (1 - t / 100)
                                  else achat  * (1 + t / 100) end as p
      from borne
  ),
  arrondi as (
    select public, achat,
           case when m = 'public' then floor(p / 5) * 5
                                  else ceil (p / 5) * 5 end as p
      from brut
  )
  select case when achat <= 0 then public::int
              -- plancher au prix BIZZOO, PUIS plafond au prix public :
              -- dans cet ordre, le plafond l'emporte quand les deux se
              -- contredisent.
              else least(public, greatest(p, achat))::int end
    from arrondi;
$$;
revoke all on function public.prix_revendeur(int, int, numeric, text)
  from public, anon, authenticated;

create or replace function public.est_revendeur() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.clients c
                  where c.id = auth.uid() and c.revendeur_etat = 'validee');
$$;
revoke all on function public.est_revendeur() from public, anon, authenticated;
grant execute on function public.est_revendeur() to authenticated;

create or replace function public.compte_exige() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select r.compte_obligatoire from public.reglages r where r.id = 1), false);
$$;
revoke all on function public.compte_exige() from public, anon, authenticated;
grant execute on function public.compte_exige() to anon, authenticated;

-- ---------- Les codes promo ----------
-- UNE REMISE SORT DE LA MARGE DE L'ENSEIGNE, jamais de la poche d'une
-- boutique. La boutique touche son prix BIZZOO en entier, comme si le
-- code n'existait pas : elle n'a pas décidé cette promotion, elle n'a
-- pas à la payer. C'est pour cela que la remise vit sur la COMMANDE et
-- jamais sur les lignes.
--
-- Et c'est pour cela qu'il y a UN PLAFOND, plus bas : une remise ne
-- descend jamais en dessous de ce que les boutiques doivent toucher.
-- Sans lui, un code de 50 % sur un article vendu avec 20 % de marge
-- ferait payer la différence à l'enseigne — sur chaque vente, sans que
-- personne s'en aperçoive avant de faire les comptes.
create table if not exists public.codes_promo (
  code     text primary key,
  libelle  text not null default '',
  mode     text not null default 'pourcent'
           check (mode in ('pourcent', 'montant')),
  valeur   numeric(10,2) not null default 0,
  -- Montant minimum de commande. Sans lui, « 20 % » s'applique aussi à
  -- un panier de 500 francs.
  minimum  bigint not null default 0,
  -- 0 = sans limite. Voir « utilisations » plus bas : ce sont les
  -- commandes PAYÉES qui comptent, pas les paniers abandonnés.
  maximum  int not null default 0,
  une_par_client boolean not null default true,
  fin      date,
  actif    boolean not null default true,
  cree_le  timestamptz not null default now(),
  cree_par text not null default ''
);

alter table public.codes_promo enable row level security;
drop policy if exists "codes lecture" on public.codes_promo;
-- L'enseigne seule voit la liste. Un client ne doit PAS pouvoir lire la
-- table : il y trouverait tous les codes en cours, y compris ceux qui
-- ne lui étaient pas destinés. Il passe par « verifier_code », qui
-- répond sur un code qu'il connaît déjà et ne révèle rien d'autre.
create policy "codes lecture" on public.codes_promo
  for select to authenticated using (public.est_super());
revoke all on public.codes_promo from anon, authenticated;
grant select on public.codes_promo to authenticated;

-- Un code se tape à la main, sur un téléphone : « rentree2026 »,
-- « Rentrée 2026 », « RENTREE-2026 » doivent désigner le même code.
create or replace function public.code_normalise(brut text) returns text
language sql immutable as $$
  select left(regexp_replace(upper(coalesce(brut, '')), '[^A-Z0-9]', '', 'g'), 24);
$$;

-- LA RÈGLE, EN UN SEUL ENDROIT. L'écran du panier l'appelle pour
-- annoncer la remise ; la caisse l'appelle pour l'appliquer. Deux
-- calculs séparés finiraient par diverger, et le client verrait un
-- montant puis en paierait un autre — c'est déjà la règle que suivent
-- « mes_prix » et « ligne_a_l_ecriture » pour les prix revendeur.
--
-- Rend un objet : { ok, remise, raison }. « raison » est écrite pour
-- être montrée telle quelle au client.
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

-- Ce que le panier demande AVANT de commander : « ce code vaut-il
-- quelque chose sur ce panier-ci ? ». Les prix et la marge se
-- recalculent ICI, depuis la base : le panier ne les envoie pas, et le
-- prix BIZZOO ne sort toujours pas.
create or replace function public.verifier_code(brut text, articles jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  article    jsonb;
  qte        int;
  p          public.produits%rowtype;
  pv         public.produits_prive%rowtype;
  b          public.boutiques%rowtype;
  revendeur  boolean := public.est_revendeur();
  prix       bigint;
  achat      bigint;
  sous_total bigint := 0;
  marge      bigint := 0;
  moi        uuid := auth.uid();
begin
  if articles is null or jsonb_typeof(articles) <> 'array' then
    return jsonb_build_object('ok', false, 'remise', 0, 'raison', 'Panier vide.');
  end if;
  for article in select * from jsonb_array_elements(articles) loop
    qte := greatest(1, least(99, coalesce((article ->> 'quantite')::int, 1)));
    select * into p from public.produits where id = article ->> 'produit_id';
    continue when not found;
    select * into pv from public.produits_prive where produit_id = p.id;
    select * into b  from public.boutiques where id = p.boutique_id;
    achat := greatest(0, coalesce(pv.prix_grossiste, 0));
    prix  := case when revendeur and achat > 0
                  then public.prix_revendeur(coalesce(p.prix, 0)::int, achat::int,
                         coalesce(pv.taux_revendeur, b.taux_revendeur, 0),
                         coalesce(b.revendeur_mode, 'bizzoo'))
                  else coalesce(p.prix, 0) end;
    sous_total := sous_total + prix * qte;
    -- Ce que l'enseigne garde sur cette ligne. C'est lui, et lui seul,
    -- qui borne la remise.
    marge := marge + greatest(0, prix - achat) * qte;
  end loop;
  return public.remise_du_code(brut, sous_total, marge, moi,
    coalesce((select c.tel from public.clients c where c.id = moi), ''));
end $$;
revoke all on function public.verifier_code(text, jsonb) from public;
grant execute on function public.verifier_code(text, jsonb) to anon, authenticated;

-- ---------- Tenir les codes, côté enseigne ----------
-- Ce que chaque code a réellement coûté, et à combien de clients. Les
-- deux se comptent sur les commandes PAYÉES : un panier abandonné n'a
-- rien coûté à personne.
create or replace function public.codes_promo_liste()
returns table (
  code text, libelle text, mode text, valeur numeric,
  minimum bigint, maximum int, une_par_client boolean,
  fin date, actif boolean, cree_le timestamptz, cree_par text,
  utilisations bigint, coute bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.est_super() then return; end if;
  return query
    select c.code, c.libelle, c.mode, c.valeur, c.minimum, c.maximum,
           c.une_par_client, c.fin, c.actif, c.cree_le, c.cree_par,
           coalesce(u.combien, 0), coalesce(u.total, 0)
      from public.codes_promo c
      left join (select o.code_promo, count(*)::bigint as combien,
                        sum(o.remise)::bigint as total
                   from public.commandes o
                  where o.etat = 'payee' and o.code_promo <> ''
                  group by o.code_promo) u on u.code_promo = c.code
     order by c.actif desc, c.cree_le desc;
end $$;
revoke all on function public.codes_promo_liste() from public, anon;
grant execute on function public.codes_promo_liste() to authenticated;

-- Poser un code, ou le corriger. Le code lui-même ne se change jamais :
-- c'est la clé, et des commandes le portent déjà. Pour en changer, on
-- ferme celui-ci et on en pose un autre.
create or replace function public.enregistrer_code(
  brut text, libelle text, mode text, valeur numeric,
  minimum bigint default 0, maximum int default 0,
  une_par_client boolean default true,
  fin date default null, actif boolean default true)
returns text
language plpgsql security definer set search_path = public as $$
declare
  cle text := public.code_normalise(brut);
  qui text;
begin
  if not public.est_super() then
    raise exception 'Seule l''enseigne pose un code promo';
  end if;
  if cle = '' then
    raise exception 'Un code ne peut pas être vide : lettres et chiffres seulement.';
  end if;
  if mode not in ('pourcent', 'montant') then
    raise exception 'Un code se calcule en pourcentage ou en montant.';
  end if;
  if coalesce(valeur, 0) <= 0 then
    raise exception 'Un code sans valeur ne retire rien.';
  end if;
  if mode = 'pourcent' and valeur > 100 then
    raise exception 'Une remise ne dépasse pas 100 %%.';
  end if;

  select coalesce(p.email, '') into qui from public.profils p where p.id = auth.uid();
  insert into public.codes_promo
    (code, libelle, mode, valeur, minimum, maximum, une_par_client, fin, actif, cree_par)
  values (cle, left(coalesce(libelle, ''), 120), mode, valeur,
          greatest(0, coalesce(minimum, 0)), greatest(0, coalesce(maximum, 0)),
          coalesce(une_par_client, true), fin, coalesce(actif, true),
          coalesce(qui, 'enseigne'))
  on conflict (code) do update
     set libelle = excluded.libelle, mode = excluded.mode,
         valeur = excluded.valeur, minimum = excluded.minimum,
         maximum = excluded.maximum, une_par_client = excluded.une_par_client,
         fin = excluded.fin, actif = excluded.actif;
  return cle;
end $$;
revoke all on function public.enregistrer_code(text, text, text, numeric, bigint, int, boolean, date, boolean)
  from public, anon;
grant execute on function public.enregistrer_code(text, text, text, numeric, bigint, int, boolean, date, boolean)
  to authenticated;

-- ---------- Ce que les remises coûtent à l'enseigne ----------
-- LE PIÈGE QUE CETTE FONCTION FERME. « statistiques_ventes » calcule le
-- bénéfice LIGNE PAR LIGNE : prix de vente moins prix BIZZOO. Mais la
-- remise est sur la COMMANDE, pas sur les lignes — elle n'y apparaît
-- donc nulle part, et le bénéfice affiché serait surévalué de toutes
-- les remises accordées. Sur un mois de promotions, l'écart se compte
-- en dizaines de milliers.
--
-- La remise se répartit AU PRORATA de ce que chaque boutique pèse dans
-- la commande : c'est sur sa part de marge que l'enseigne a rogné.
create or replace function public.remises_periode(
  depuis date default null,
  jusqu  date default null,
  boutique text default null)
returns table (boutique_id text, remise bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.est_super() then return; end if;
  return query
    with payees as (
      select o.id, o.remise
        from public.commandes o
       where o.etat = 'payee' and coalesce(o.remise, 0) > 0
         and (depuis is null or o.paye_le >= depuis::timestamptz)
         and (jusqu  is null or o.paye_le <  (jusqu + 1)::timestamptz)
    ), parts as (
      select p.id as commande, p.remise as remise,
             l.boutique_id as bq,
             sum(l.prix * l.quantite)::numeric as part
        from payees p
        join public.commande_lignes l on l.commande_id = p.id
       group by p.id, p.remise, l.boutique_id
    ), entiers as (
      select parts.commande, sum(parts.part) as entier
        from parts group by parts.commande
    )
    select parts.bq,
           round(sum(parts.remise * parts.part / nullif(e.entier, 0)))::bigint
      from parts join entiers e on e.commande = parts.commande
     where boutique is null or parts.bq = boutique
     group by parts.bq;
end $$;
revoke all on function public.remises_periode(date, date, text) from public, anon;
grant execute on function public.remises_periode(date, date, text) to authenticated;
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

-- ---------- Vérification ----------
-- Aucun code n'existe encore : cette requête rend ZÉRO LIGNE, et c'est
-- exactement ce qu'on attend. Elle montre ce que l'écran affichera dès
-- que vous en aurez créé un, avec ce que chacun vous aura coûté.
select c.code                                          as "Code",
       c.libelle                                       as "Libellé",
       case c.mode when 'pourcent' then c.valeur::text || ' %'
                   else c.valeur::text end             as "Remise",
       case when c.minimum > 0 then 'dès ' || c.minimum::text
            else '—' end                               as "Minimum",
       case when c.maximum > 0 then c.maximum::text || ' max'
            else 'sans limite' end                     as "Utilisations",
       coalesce(to_char(c.fin, 'DD/MM/YYYY'), 'sans échéance') as "Fin",
       case when c.actif then 'ouvert' else 'fermé' end as "État",
       count(o.id)                                     as "Déjà utilisé",
       coalesce(sum(o.remise), 0)                      as "Vous a coûté"
  from public.codes_promo c
  left join public.commandes o
    on o.code_promo = c.code and o.etat = 'payee'
 group by c.code, c.libelle, c.mode, c.valeur, c.minimum, c.maximum,
          c.fin, c.actif, c.cree_le
 order by c.actif desc, c.cree_le desc
 limit 20;
