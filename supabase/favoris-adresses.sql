-- =========================================================
-- BIZZOO — ce que le client garde pour lui
--
-- Trois choses arrivent avec ce fichier : les FAVORIS, les
-- BOUTIQUES SUIVIES et les ADRESSES de livraison. Plus le
-- classement des produits qui se vendent le mieux, pour
-- l'accueil.
--
-- CE QUE CE FICHIER NE DÉFAIT PAS : rien. Il n'ajoute que
-- des tables neuves et une fonction. Aucun produit, aucune
-- commande, aucun réglage n'est touché. On peut le coller
-- deux fois de suite sans conséquence.
--
-- CE QU'IL FAUT SAVOIR AVANT DE LE COLLER.
--
--   Ces trois tables ne sont PAS de la donnée de vente,
--   c'est de la donnée de vie. Une liste de favoris dit ce
--   qu'on hésite à s'offrir ; une liste d'adresses dit où
--   l'on dort et où l'on travaille.
--
--   VOUS N'Y AUREZ PAS ACCÈS, et c'est voulu. Presque toutes
--   les autres tables s'ouvrent au superadministrateur ;
--   celles-ci, non. Personne ne lit les favoris d'un client,
--   pas même vous. Si un jour vous avez besoin du contraire,
--   ce sera un choix à prendre en connaissance de cause, pas
--   une porte laissée ouverte par distraction.
--
--   Le CLASSEMENT rend un ordre, jamais des chiffres. « Voici
--   ce qui part le plus » est un service au client ; « voici
--   combien chaque boutique vend » livrerait à chaque
--   commerçant le carnet de commandes de son voisin, et il
--   suffirait d'un compte gratuit pour l'ouvrir.
--
-- À COLLER DANS : Supabase → SQL Editor → New query → Run.
-- Aucun compte n'a besoin d'être connecté.
-- =========================================================

-- =========================================================
-- Ce que le client garde pour lui
--
-- Trois choses appartiennent au client et à personne d'autre : ce
-- qu'il met de côté, les boutiques qu'il suit, et les adresses où il
-- se fait livrer.
--
-- CE N'EST PAS DE LA DONNÉE DE VENTE, C'EST DE LA DONNÉE DE VIE.
-- Une liste de favoris dit ce qu'on hésite à s'offrir ; une liste
-- d'adresses dit où l'on dort et où l'on travaille. L'enseigne n'en a
-- aucun besoin pour faire son métier, et « est_super() » n'ouvre donc
-- AUCUNE de ces trois portes — contrairement à presque toutes les
-- autres tables de ce fichier. Un superadministrateur curieux ne lit
-- pas les favoris de ses clients.
--
-- Ce qui sort de là ressort au moment de commander, et seulement
-- parce que le client l'a choisi lui-même à l'écran.
-- =========================================================

-- ---------- Les produits mis de côté ----------
create table if not exists public.favoris (
  client_id  uuid not null references public.clients(id) on delete cascade,
  produit_id text not null references public.produits(id) on delete cascade,
  cree_le    timestamptz not null default now(),
  primary key (client_id, produit_id)
);

-- ---------- Les boutiques qu'on suit ----------
create table if not exists public.boutiques_suivies (
  client_id   uuid not null references public.clients(id) on delete cascade,
  boutique_id text not null references public.boutiques(id) on delete cascade,
  cree_le     timestamptz not null default now(),
  primary key (client_id, boutique_id)
);

-- La liste se lit dans l'ordre où on l'a remplie, le dernier d'abord.
create index if not exists favoris_du_client
  on public.favoris(client_id, cree_le desc);
create index if not exists suivies_du_client
  on public.boutiques_suivies(client_id, cree_le desc);

-- ---------- Les adresses de livraison ----------
create table if not exists public.adresses (
  id         text primary key,
  client_id  uuid not null references public.clients(id) on delete cascade,
  libelle    text not null default '',        -- « Maison », « Bureau »
  texte      text not null default '',        -- ce qu'on dit au livreur
  ville      text not null default '',
  par_defaut boolean not null default false,
  cree_le    timestamptz not null default now(),
  maj_le     timestamptz not null default now()
);
create index if not exists adresses_du_client
  on public.adresses(client_id, cree_le desc);

-- UNE SEULE ADRESSE PAR DÉFAUT, et l'index le garantit plutôt que
-- l'application. Deux adresses par défaut, c'est un formulaire de
-- commande qui en choisit une au hasard — et un colis chez l'autre.
create unique index if not exists adresses_une_par_defaut
  on public.adresses(client_id) where par_defaut;

-- L'index REFUSE la deuxième ; le déclencheur fait en sorte qu'on n'ait
-- jamais à la refuser. Sans lui, cocher « par défaut » sur une nouvelle
-- adresse renverrait une erreur de contrainte au client, qui devrait
-- décocher l'ancienne lui-même. Les deux se complètent : le
-- déclencheur pour que ce soit utilisable, l'index pour que ce soit vrai.
create or replace function public.adresse_une_seule_defaut() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.par_defaut then
    update public.adresses
       set par_defaut = false, maj_le = now()
     where client_id = new.client_id
       and par_defaut
       and id <> new.id;
  end if;
  new.maj_le := now();
  return new;
end $$;
drop trigger if exists adresses_defaut on public.adresses;
create trigger adresses_defaut before insert or update on public.adresses
  for each row execute function public.adresse_une_seule_defaut();

-- ---------- Les portes ----------
-- CHACUN CHEZ SOI, sans exception. « client_id = auth.uid() » des deux
-- côtés de chaque règle : « using » décide ce qu'on voit et ce qu'on
-- peut effacer, « with check » ce qu'on a le droit d'écrire. Sans le
-- second, n'importe qui poserait un favori au nom d'un autre — et une
-- liste de favoris qu'un tiers peut garnir ne vaut plus rien.
alter table public.favoris            enable row level security;
alter table public.boutiques_suivies  enable row level security;
alter table public.adresses           enable row level security;

drop policy if exists "favoris a soi" on public.favoris;
create policy "favoris a soi" on public.favoris
  for all to authenticated
  using (client_id = auth.uid()) with check (client_id = auth.uid());

drop policy if exists "suivies a soi" on public.boutiques_suivies;
create policy "suivies a soi" on public.boutiques_suivies
  for all to authenticated
  using (client_id = auth.uid()) with check (client_id = auth.uid());

drop policy if exists "adresses a soi" on public.adresses;
create policy "adresses a soi" on public.adresses
  for all to authenticated
  using (client_id = auth.uid()) with check (client_id = auth.uid());

-- UNE BASE SUPABASE DONNE TOUT D'OFFICE. « alter default privileges »
-- accorde `all` à anon et authenticated sur toute table nouvelle : poser
-- un `grant` par-dessus n'enlève rien. Il faut RETIRER d'abord — sans
-- quoi un visiteur non connecté lirait ces trois tables, RLS ou pas,
-- puisque aucune règle ne s'applique à lui faute de `to anon`.
revoke all on public.favoris           from anon, authenticated;
revoke all on public.boutiques_suivies from anon, authenticated;
revoke all on public.adresses          from anon, authenticated;
grant select, insert, delete on public.favoris           to authenticated;
grant select, insert, delete on public.boutiques_suivies to authenticated;
grant select, insert, update, delete on public.adresses  to authenticated;

-- ---------- Ce qui se vend le mieux ----------
-- Le classement de l'accueil. Il lit les lignes de commande, que
-- personne ne peut lire — d'où « security definer ».
--
-- IL REND L'ORDRE, JAMAIS LES CHIFFRES. C'est toute la différence
-- entre « voici ce qui part le plus » et « voici combien chaque
-- boutique vend ». Le premier est un service au client ; le second
-- livrerait à chaque commerçant le carnet de commandes de son voisin,
-- et il suffirait d'un compte gratuit pour l'ouvrir.
--
-- Trois mois de recul : assez pour que le classement veuille dire
-- quelque chose, assez court pour qu'un succès de l'an dernier ne
-- tienne pas la première place pour toujours.
create or replace function public.produits_populaires(limite int default 8)
returns table (produit_id text)
language sql stable security definer set search_path = public as $$
  select l.produit_id
    from public.commande_lignes l
    join public.commandes c on c.id = l.commande_id
    join public.produits  p on p.id = l.produit_id
    join public.boutiques b on b.id = p.boutique_id
   where c.etat = 'payee'
     and c.cree_le > now() - interval '90 days'
     and l.produit_id is not null
     -- Un produit retiré de la vente, ou d'une boutique fermée, n'a
     -- rien à faire sur l'accueil : le client cliquerait dans le vide.
     and p.disponible
     and b.actif
   group by l.produit_id
   -- Le nombre sert à trier, et ne sort pas de la fonction.
   order by sum(l.quantite) desc, l.produit_id
   limit greatest(1, least(coalesce(limite, 8), 24));
$$;
revoke all on function public.produits_populaires(int)
  from public, anon, authenticated;
-- Ouverte à tous, y compris sans compte : c'est l'accueil de BIZZOO,
-- et il doit s'afficher avant qu'on se connecte.
grant execute on function public.produits_populaires(int) to anon, authenticated;

-- =========================================================
-- CE QUI VIENT D'ÊTRE POSÉ
--
-- Cette dernière requête est là pour être LUE, pas seulement
-- exécutée. L'éditeur de Supabase n'affiche que le résultat
-- de la dernière requête : c'est celle-ci. Trois lignes
-- « en place » et tout est bon.
-- =========================================================
select 'Les produits mis de côté' as quoi,
       case when to_regclass('public.favoris') is not null
            then 'en place' else 'MANQUANT' end as etat
union all
select 'Les boutiques suivies',
       case when to_regclass('public.boutiques_suivies') is not null
            then 'en place' else 'MANQUANT' end
union all
select 'Les adresses de livraison',
       case when to_regclass('public.adresses') is not null
            then 'en place' else 'MANQUANT' end
union all
select 'Une seule adresse par défaut',
       case when exists (select 1 from pg_indexes
                          where schemaname = 'public'
                            and indexname = 'adresses_une_par_defaut')
            then 'en place' else 'MANQUANT' end
union all
select 'Le classement des ventes',
       case when exists (select 1 from pg_proc p
                          join pg_namespace n on n.oid = p.pronamespace
                         where n.nspname = 'public'
                           and p.proname = 'produits_populaires')
            then 'en place' else 'MANQUANT' end
union all
-- La porte qu'on vérifie vraiment : qu'un visiteur non connecté
-- n'ait AUCUN droit sur ces trois tables. Une base Supabase les
-- donne d'office ; si le « revoke » n'avait pas pris, ce contrôle
-- le dirait plutôt que de laisser croire que tout va bien.
select 'Rien n''est lisible sans compte',
       case when not exists (
              select 1 from information_schema.role_table_grants
               where table_schema = 'public'
                 and table_name in ('favoris', 'boutiques_suivies', 'adresses')
                 and grantee = 'anon')
            then 'en place' else 'MANQUANT' end;
