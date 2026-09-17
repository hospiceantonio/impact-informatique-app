-- =========================================================
-- BIZZOO — le compte, pour commander
--
-- Jusqu'ici on commandait sans compte : on laissait son nom,
-- son numéro, et la commande partait. C'était voulu — on
-- n'arrête pas un client au moment où il sort son argent.
--
-- Ce fichier pose de quoi CHANGER D'AVIS, sans rien casser :
--
--   1. une règle rangée en base, « compte_obligatoire », que
--      vous seul basculez depuis l'application admin ;
--   2. le refus lui-même, DANS « creer_commande » — pas à
--      l'écran. Un écran qui cache un bouton ne ferme rien :
--      il suffit d'appeler la fonction directement.
--
-- ELLE ARRIVE ÉTEINTE. Exécuter ce fichier ne change donc
-- rien aujourd'hui : on commande exactement comme hier. Vous
-- l'allumerez le jour où une porte d'inscription est ouverte
-- pour de bon — sans quoi vous fermeriez la caisse à un
-- client qui n'a aucun moyen d'ouvrir un compte.
--
-- Ce qui ne bouge pas : le catalogue, la recherche, le
-- panier. Un visiteur regarde et remplit son panier sans
-- compte, comme avant ; on ne lui demande rien tant qu'il
-- n'a pas décidé d'acheter.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, et rien n'est supprimé.
-- =========================================================

-- ---------------------------------------------------------
-- 1. La règle
-- ---------------------------------------------------------
create table if not exists public.reglages (
  id                 int primary key default 1 check (id = 1),
  compte_obligatoire boolean not null default false,
  maj_le             timestamptz not null default now()
);
-- Sur une base qui a déjà cette table, le corps ci-dessus n'est jamais
-- relu : chaque colonne se repose donc une par une.
alter table public.reglages
  add column if not exists compte_obligatoire boolean not null default false;
alter table public.reglages
  add column if not exists maj_le timestamptz not null default now();
insert into public.reglages (id) values (1) on conflict (id) do nothing;

alter table public.reglages enable row level security;
drop policy if exists "reglages lecture"  on public.reglages;
drop policy if exists "reglages ecriture" on public.reglages;

-- L'application doit CONNAÎTRE la règle avant de dessiner son bouton :
-- elle se lit donc sans compte. Il n'y a rien de secret là-dedans.
create policy "reglages lecture" on public.reglages
  for select to anon, authenticated using (true);
-- La changer ferme ou rouvre la caisse de toute l'enseigne : vous seul.
create policy "reglages ecriture" on public.reglages
  for update to authenticated
  using (public.est_super()) with check (public.est_super());

-- Ni « insert » ni « delete » pour personne : la ligne est unique et ne
-- doit pas pouvoir disparaître. Une table sans ligne répondrait « pas de
-- règle », et la porte se rouvrirait toute seule.
revoke all on public.reglages from anon, authenticated;
grant select on public.reglages to anon, authenticated;
-- « revoke all » puis « grant » par colonne, dans cet ordre : un droit
-- par colonne posé sur un droit de table déjà accordé ne retire rien.
grant update (compte_obligatoire, maj_le) on public.reglages to authenticated;

-- ---------------------------------------------------------
-- 2. La règle, lue par la base elle-même
-- ---------------------------------------------------------
-- « security definer » parce que « creer_commande » l'appelle pour un
-- visiteur sans compte, et qu'on préfère ne dépendre d'aucun droit de
-- lecture au moment de décider.
--
-- Si la ligne manquait malgré tout, la réponse est « non ». Ce choix est
-- délibéré : la règle force une inscription, elle ne protège rien. Un
-- accident doit laisser la boutique vendre, pas verrouiller la caisse un
-- samedi soir sans personne pour la rouvrir.
create or replace function public.compte_exige() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select r.compte_obligatoire from public.reglages r where r.id = 1), false);
$$;
revoke all on function public.compte_exige() from public, anon, authenticated;
grant execute on function public.compte_exige() to anon, authenticated;

-- ---------------------------------------------------------
-- 3. Le refus, là où il tient : dans « creer_commande »
-- ---------------------------------------------------------
-- La fonction ci-dessous est celle de « schema.sql », recopiée telle
-- quelle. Elle gagne deux choses : elle retient qu'un compte de l'équipe
-- N'EST PAS personne, et elle demande à « compte_exige() » si la porte
-- est fermée. Tout le reste — les prix pris en base, le stock, la
-- monnaie unique — est inchangé.
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
  moi      uuid := auth.uid();
  equipe   boolean := false;   -- connecté, mais pas avec un compte client
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

revoke all on function public.creer_commande(jsonb, jsonb) from public;
grant execute on function public.creer_commande(jsonb, jsonb) to anon, authenticated;

-- ---------- Vérification ----------
-- Trois lignes : la règle telle qu'elle est aujourd'hui, et le fait que
-- « creer_commande » sait désormais la lire.
select
  case when (select r.compte_obligatoire from public.reglages r where r.id = 1)
       then 'ALLUMÉE — plus de commande sans compte'
       else 'éteinte — on commande sans compte, comme avant' end   as "la règle",
  case when exists (select 1 from pg_proc pr join pg_namespace n on n.oid = pr.pronamespace
                     where n.nspname = 'public' and pr.proname = 'compte_exige')
       then 'en place' else 'MANQUANTE' end                        as "compte_exige()",
  case when (select pg_get_functiondef(pr.oid) from pg_proc pr
               join pg_namespace n on n.oid = pr.pronamespace
              where n.nspname = 'public' and pr.proname = 'creer_commande'
              limit 1) like '%compte_exige%'
       then 'la commande consulte la règle'
       else 'NON : la commande ignore la règle' end                as "creer_commande";
