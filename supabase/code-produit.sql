-- =========================================================
-- BIZZOO — le code d'un produit
--
-- Un numéro, rien que des chiffres, donné par la base au
-- moment où le produit est créé. Il ne se choisit pas, il ne
-- se corrige pas, il ne se réutilise pas — pas même par un
-- superadministrateur. C'est ce qui en fait un repère sûr :
-- un code dicté au téléphone, ou recopié dans un message,
-- désigne un seul produit, aujourd'hui et dans dix ans.
--
-- À ne pas confondre avec la RÉFÉRENCE, qui reste ce que la
-- boutique veut en faire : elle la choisit, la change, la
-- laisse vide. Deux choses différentes, deux colonnes.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable. Les produits déjà au catalogue
-- reçoivent leur code, du plus ancien au plus récent, et ne
-- le changent plus jamais.
-- =========================================================

-- ---------------------------------------------------------
-- 1. La colonne et le compteur
-- ---------------------------------------------------------
alter table public.produits add column if not exists code text not null default '';

-- Six chiffres, sans zéro en tête : un code se dicte au téléphone et se
-- recopie à la main. Le compteur ne revient jamais en arrière, même si
-- un produit est supprimé — un code retiré du catalogue reste retiré.
create sequence if not exists public.produits_code start with 100001;

-- ---------------------------------------------------------
-- 2. Les produits d'avant reçoivent le leur
-- ---------------------------------------------------------
-- Le déclencheur est posé APRÈS ce rattrapage : il refuserait cette
-- écriture, puisqu'un code ne se change pas.
drop trigger if exists produits_code on public.produits;

do $$
declare p record;
begin
  for p in select id from public.produits
            where coalesce(code, '') = '' order by cree_le, id loop
    update public.produits set code = nextval('public.produits_code')::text
     where id = p.id;
  end loop;
end $$;

-- Deux produits ne partagent pas un code : sans cela, il ne désignerait
-- plus rien.
create unique index if not exists produits_code_unique
  on public.produits(code) where code <> '';

-- ---------------------------------------------------------
-- 3. Le code ne se choisit pas, et ne se change plus
-- ---------------------------------------------------------
create or replace function public.produit_code() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    -- Ce que l'application envoie dans « code » n'est jamais écouté :
    -- la base le donne elle-même.
    new.code := nextval('public.produits_code')::text;
  else
    -- Et il ne bouge plus, quel que soit le rang de qui écrit. Un repère
    -- qu'on peut corriger n'est plus un repère.
    new.code := old.code;
  end if;
  return new;
end $$;

create trigger produits_code
  before insert or update on public.produits
  for each row execute function public.produit_code();

-- ---------------------------------------------------------
-- 4. Le code suit le produit dans les commandes
-- ---------------------------------------------------------
-- Figé sur la ligne, comme le nom et le prix : c'est ce qui a été vendu.
alter table public.commande_lignes add column if not exists code text not null default '';

create or replace function public.ligne_a_l_ecriture() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  p public.produits%rowtype;
begin
  select * into p from public.produits where id = new.produit_id;
  if not found then
    raise exception 'Produit introuvable : %', coalesce(new.produit_id, '(aucun)');
  end if;
  new.boutique_id := p.boutique_id;
  new.nom         := p.nom;
  new.code        := coalesce(p.code, '');
  new.reference   := coalesce(p.reference, '');
  new.prix        := coalesce(p.prix, 0)::int;
  new.etat        := 'nouvelle';
  return new;
end $$;

create or replace function public.ligne_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.commande_id is distinct from old.commande_id
  or new.boutique_id is distinct from old.boutique_id
  or new.produit_id  is distinct from old.produit_id
  or new.nom         is distinct from old.nom
  or new.code        is distinct from old.code
  or new.reference   is distinct from old.reference
  or new.prix        is distinct from old.prix
  or new.quantite    is distinct from old.quantite then
    raise exception 'Une ligne de commande ne change que d''état : ce qui a été vendu est vendu';
  end if;
  return new;
end $$;

-- Le récapitulatif renvoyé au client porte le code, pour que le message
-- WhatsApp et le reçu désignent le produit sans ambiguïté.
create or replace function public.creer_commande(client jsonb, articles jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  nouvelle text := 'cmd_' || replace(gen_random_uuid()::text, '-', '');
  article  jsonb;
  qte      int;
  p        public.produits%rowtype;
  devises  text[];
  sortie   jsonb;
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

  perform set_config('bizzoo.interne', 'oui', true);

  insert into public.commandes
    (id, client_nom, client_tel, client_indicatif, client_adresse, note)
  values (
    nouvelle,
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

  if (select count(distinct d) from unnest(devises) d) > 1 then
    raise exception 'Ces produits ne se paient pas dans la même monnaie : commandez boutique par boutique.';
  end if;
  update public.commandes set devise = coalesce(devises[1], 'FCFA') where id = nouvelle;

  select jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'total', c.total, 'devise', c.devise,
    'etat', c.etat,
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
                       'quantite', l.quantite) order by l.nom) as lignes
                from public.commande_lignes l
               where l.commande_id = c.id
               group by l.boutique_id) g), '[]'::jsonb))
    into sortie
    from public.commandes c where c.id = nouvelle;
  return sortie;
end $$;

revoke all on function public.creer_commande(jsonb, jsonb) from public;
grant execute on function public.creer_commande(jsonb, jsonb) to anon, authenticated;

-- ---------- Vérification ----------
-- 1. Tous les produits ont un code, et aucun ne le partage.
select count(*)                                   as "produits",
       count(*) filter (where code <> '')          as "avec un code",
       count(distinct code) filter (where code <> '') as "codes distincts"
  from public.produits;

-- 2. Le garde-fou est en place.
select t.tgname as "garde-fou"
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
 where not t.tgisinternal and c.relname = 'produits' and t.tgname = 'produits_code';

-- 3. Un aperçu.
select code, reference, nom from public.produits order by code limit 10;
