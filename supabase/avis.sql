-- =========================================================
-- BIZZOO — les avis des clients
--
-- Une note de 1 à 5 et quelques mots, sur un PRODUIT ou sur une
-- BOUTIQUE. Publics : c'est tout leur intérêt — un avis que
-- personne ne lit ne sert à personne.
--
-- CE QUI TIENT TOUT :
--
--   1. SEUL QUI A ACHETÉ DONNE SON AVIS, et seulement sur ce
--      qu'il a acheté. Sans cette règle, un avis ne vaut rien :
--      un concurrent en poste dix mauvais le matin, une boutique
--      s'en écrit vingt bons l'après-midi, et plus personne n'y
--      croit — y compris pour les avis honnêtes ;
--
--   2. ET L'ACHAT DOIT ÊTRE PAYÉ. Ouvrir une commande ne coûte
--      rien et ne prouve rien : sans le « payee », il suffirait
--      d'en ouvrir une, de ne jamais la régler, et d'écrire ce
--      qu'on veut. C'est LA ligne à ne pas retirer ;
--
--   3. LA BOUTIQUE VIENT DU CATALOGUE, JAMAIS DE LA REQUÊTE.
--      Comme le prix d'une ligne de commande. Autrement, on
--      achèterait un article à trois francs chez l'un pour aller
--      noter l'autre ;
--
--   4. UN SEUL AVIS PAR CLIENT ET PAR CIBLE. Il se modifie —
--      on change d'avis, c'est le mot — mais il ne se multiplie
--      pas ;
--
--   5. LA BOUTIQUE NE SUPPRIME PAS CE QUI LA GÊNE. Elle RÉPOND,
--      ce qui est plus utile et se voit. Masquer est réservé à
--      l'enseigne, et pour ce qui n'a pas sa place : insultes,
--      numéro de téléphone, règlement de comptes.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, et rien n'est supprimé.
-- =========================================================

-- ---------------------------------------------------------
-- 1. La table
-- ---------------------------------------------------------
create table if not exists public.avis (
  id          text primary key,
  client_id   uuid not null references public.clients(id) on delete cascade,
  -- Un avis porte sur un PRODUIT (« produit_id » rempli) ou sur la
  -- BOUTIQUE elle-même (« produit_id » à null). Dans les deux cas la
  -- boutique est connue : celle du produit, ou celle qu'on note.
  produit_id  text references public.produits(id) on delete cascade,
  boutique_id text not null references public.boutiques(id) on delete cascade,
  note        int not null check (note between 1 and 5),
  texte       text not null default '',
  -- Le nom affiché, figé le jour de l'avis. Changer de nom ne réécrit
  -- pas ce qu'on a signé — et « clients » reste fermée aux visiteurs,
  -- qui doivent pourtant lire les avis.
  auteur      text not null default '',
  -- La commande qui a servi de preuve. Gardée pour pouvoir répondre
  -- « cet avis vient bien d'un achat » le jour où on le conteste.
  commande_id text references public.commandes(id) on delete set null,
  -- La réponse de la boutique. Publique, comme l'avis.
  reponse     text not null default '',
  reponse_le  timestamptz,
  -- Le masquage, réservé à l'enseigne.
  masque      boolean not null default false,
  motif_masque text not null default '',
  cree_le     timestamptz not null default now(),
  maj_le      timestamptz not null default now()
);

alter table public.avis add column if not exists auteur text not null default '';
alter table public.avis add column if not exists commande_id text;
alter table public.avis add column if not exists reponse text not null default '';
alter table public.avis add column if not exists reponse_le timestamptz;
alter table public.avis add column if not exists masque boolean not null default false;
alter table public.avis add column if not exists motif_masque text not null default '';

-- UN SEUL AVIS PAR CIBLE. Deux index partiels plutôt qu'un seul : sur
-- un avis de boutique, « produit_id » est null — et null n'est égal à
-- rien, pas même à null. Un index unique ordinaire laisserait donc
-- passer autant d'avis de boutique qu'on veut.
create unique index if not exists avis_un_par_produit
  on public.avis(client_id, produit_id) where produit_id is not null;
create unique index if not exists avis_un_par_boutique
  on public.avis(client_id, boutique_id) where produit_id is null;

create index if not exists avis_produit on public.avis(produit_id, cree_le desc)
  where not masque;
create index if not exists avis_boutique on public.avis(boutique_id, cree_le desc)
  where not masque;

-- Les moyennes, là où le catalogue les lit déjà. L'application cliente
-- lit « produits » et « boutiques » avec la clé publiable, en un seul
-- appel : une étoile sur une carte ne doit pas coûter une requête de
-- plus par produit.
alter table public.produits  add column if not exists note_moyenne numeric(3,2);
alter table public.produits  add column if not exists nb_avis int not null default 0;
alter table public.boutiques add column if not exists note_moyenne numeric(3,2);
alter table public.boutiques add column if not exists nb_avis int not null default 0;

-- ---------------------------------------------------------
-- 2. A-t-il acheté ?
-- ---------------------------------------------------------
-- LE « payee » EST LA LIGNE À NE PAS RETIRER. Ouvrir une commande ne
-- coûte rien : sans lui, on en ouvre une, on ne la paie jamais, et l'on
-- écrit ce qu'on veut sur qui l'on veut.
create or replace function public.a_achete(cible_produit text, cible_boutique text)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
      from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
     where c.client_id = auth.uid()
       and c.etat = 'payee'
       and (cible_produit is null or l.produit_id = cible_produit)
       and (cible_boutique is null or l.boutique_id = cible_boutique)
  );
$$;
revoke all on function public.a_achete(text, text) from public, anon, authenticated;
grant execute on function public.a_achete(text, text) to authenticated;

-- La commande qui sert de preuve : la plus récente qui porte cet achat.
create or replace function public.commande_temoin(cible_produit text, cible_boutique text)
returns text
language sql stable security definer set search_path = public as $$
  select c.id
    from public.commande_lignes l
    join public.commandes c on c.id = l.commande_id
   where c.client_id = auth.uid()
     and c.etat = 'payee'
     and (cible_produit is null or l.produit_id = cible_produit)
     and (cible_boutique is null or l.boutique_id = cible_boutique)
   order by c.cree_le desc
   limit 1;
$$;
revoke all on function public.commande_temoin(text, text) from public, anon, authenticated;

-- ---------------------------------------------------------
-- 3. Les moyennes suivent leurs avis
-- ---------------------------------------------------------
-- Tenues par la base, jamais par un écran. Un avis masqué ne compte
-- plus : le masquer doit faire remonter la note, sinon masquer ne sert
-- à rien.
create or replace function public.avis_recalcule() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  p text := coalesce(new.produit_id, old.produit_id);
  b text := coalesce(new.boutique_id, old.boutique_id);
begin
  /* Ce drapeau est ce qui distingue ce calcul d'une écriture ordinaire :
     les verrous de « produits » et de « boutiques » refusent la note à
     tout le reste, y compris à l'enseigne. Il ne vaut que le temps de
     cette transaction, et ne s'attrape pas depuis PostgREST. */
  perform set_config('bizzoo.avis', 'oui', true);
  if p is not null then
    update public.produits x
       set note_moyenne = (select round(avg(a.note), 2) from public.avis a
                            where a.produit_id = x.id and not a.masque),
           nb_avis      = (select count(*) from public.avis a
                            where a.produit_id = x.id and not a.masque)
     where x.id = p;
  end if;
  if b is not null then
    /* La note d'une boutique est celle qu'on lui donne À ELLE — la
       livraison, l'accueil, le sérieux — pas la moyenne des notes de
       ses produits. Les deux questions sont différentes, et les
       mélanger rendrait les deux illisibles. */
    update public.boutiques x
       set note_moyenne = (select round(avg(a.note), 2) from public.avis a
                            where a.boutique_id = x.id and a.produit_id is null
                              and not a.masque),
           nb_avis      = (select count(*) from public.avis a
                            where a.boutique_id = x.id and a.produit_id is null
                              and not a.masque)
     where x.id = b;
  end if;
  -- Rendu tel qu'il était : il ne vaut que pour ce qu'on vient d'écrire.
  perform set_config('bizzoo.avis', '', true);
  return null;
end $$;

drop trigger if exists avis_moyennes on public.avis;
create trigger avis_moyennes
  after insert or update or delete on public.avis
  for each row execute function public.avis_recalcule();

-- ---------------------------------------------------------
-- 4. Déposer un avis
-- ---------------------------------------------------------
-- AUCUNE RÈGLE D'ÉCRITURE DIRECTE sur « avis » : tout passe par ici.
-- C'est ce qui permet de relire la boutique DANS LE CATALOGUE plutôt
-- que de la croire sur parole — sans quoi on achèterait un article à
-- trois francs chez l'un pour aller noter l'autre.
create or replace function public.deposer_avis(
  cible_produit text, cible_boutique text, note int, texte text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  moi       uuid := auth.uid();
  boutique  text;
  temoin    text;
  nom       text;
  identifie text;
  existant  text;
begin
  if moi is null then
    raise exception 'Connectez-vous pour donner votre avis';
  end if;
  if not exists (select 1 from public.clients c where c.id = moi) then
    raise exception 'Seuls les acheteurs donnent leur avis';
  end if;
  if note is null or note < 1 or note > 5 then
    raise exception 'Une note va de 1 à 5 étoiles';
  end if;

  -- La boutique vient du CATALOGUE. Ce que la requête en dit n'est lu
  -- que pour un avis de boutique, et vérifié juste après.
  if coalesce(cible_produit, '') <> '' then
    select p.boutique_id into boutique
      from public.produits p where p.id = cible_produit;
    if boutique is null then
      raise exception 'Ce produit n''existe plus';
    end if;
  else
    cible_produit := null;
    boutique := nullif(trim(coalesce(cible_boutique, '')), '');
    if boutique is null
       or not exists (select 1 from public.boutiques b where b.id = boutique) then
      raise exception 'Boutique inconnue';
    end if;
  end if;

  if not public.a_achete(cible_produit, boutique) then
    raise exception 'Seuls les acheteurs donnent leur avis : cet achat n''a pas été réglé';
  end if;
  temoin := public.commande_temoin(cible_produit, boutique);

  -- Le prénom seul : un avis se signe, il ne livre pas un annuaire.
  select coalesce(c.nom, '') into nom from public.clients c where c.id = moi;
  identifie := left(coalesce(nullif(split_part(trim(nom), ' ', 1), ''), 'Client'), 40);

  /* Un avis existe déjà ? On le remplace — on change d'avis, c'est le
     mot. « is not distinct from » et non « = » : sur un avis de
     boutique, « produit_id » est null, et null n'est égal à rien, pas
     même à null. Avec « = », on en déposerait un second à chaque fois. */
  select a.id into existant
    from public.avis a
   where a.client_id = moi
     and a.boutique_id = boutique
     and a.produit_id is not distinct from cible_produit;

  if existant is not null then
    update public.avis
       set note = deposer_avis.note,
           texte = left(coalesce(trim(deposer_avis.texte), ''), 1000),
           auteur = identifie,
           maj_le = now()
     where id = existant;
  else
    existant := 'avi_' || replace(gen_random_uuid()::text, '-', '');
    insert into public.avis
      (id, client_id, produit_id, boutique_id, note, texte, auteur, commande_id)
    values (existant, moi, cible_produit, boutique,
            deposer_avis.note, left(coalesce(trim(deposer_avis.texte), ''), 1000),
            identifie, temoin);
  end if;

  return jsonb_build_object('id', existant, 'note', deposer_avis.note);
end $$;

revoke all on function public.deposer_avis(text, text, int, text)
  from public, anon, authenticated;
grant execute on function public.deposer_avis(text, text, int, text) to authenticated;

-- Retirer son propre avis. On a le droit de se taire.
create or replace function public.retirer_mon_avis(cible text) returns boolean
language plpgsql security definer set search_path = public as $$
declare combien int;
begin
  if auth.uid() is null then return false; end if;
  delete from public.avis a where a.id = cible and a.client_id = auth.uid();
  get diagnostics combien = row_count;
  return combien > 0;
end $$;
revoke all on function public.retirer_mon_avis(text) from public, anon, authenticated;
grant execute on function public.retirer_mon_avis(text) to authenticated;

-- ---------------------------------------------------------
-- 5. Ce que la boutique peut, et ce qu'elle ne peut pas
-- ---------------------------------------------------------
-- ELLE RÉPOND. Elle ne supprime pas, elle ne modifie pas, elle ne
-- masque pas : une boutique qui efface ce qui la gêne rend tous les
-- avis sans valeur, y compris les bons.
create or replace function public.repondre_avis(cible text, texte text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare vise public.avis%rowtype;
begin
  select * into vise from public.avis where id = cible;
  if not found then raise exception 'Avis introuvable'; end if;
  if not public.peut_agir_sur(vise.boutique_id) then
    raise exception 'Cet avis ne concerne pas votre boutique';
  end if;
  /* « repondre_avis.texte » et non « texte » : la table porte une
     colonne du même nom, et PostgreSQL ne devine pas laquelle on veut.
     Il s'arrête sur « column reference is ambiguous » — à l'exécution,
     jamais à la création. */
  update public.avis
     set reponse = left(coalesce(trim(repondre_avis.texte), ''), 1000),
         reponse_le = case when coalesce(trim(repondre_avis.texte), '') = ''
                           then null else now() end,
         maj_le = now()
   where id = cible;
  return true;
end $$;
revoke all on function public.repondre_avis(text, text) from public, anon, authenticated;
grant execute on function public.repondre_avis(text, text) to authenticated;

-- MASQUER EST RÉSERVÉ À L'ENSEIGNE, et pour ce qui n'a pas sa place :
-- insultes, numéro de téléphone, règlement de comptes. Pas pour une
-- mauvaise note — une mauvaise note est une information.
create or replace function public.masquer_avis(cible text, cacher boolean, raison text default '')
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not public.est_super() then
    raise exception 'Seul BIZZOO masque un avis';
  end if;
  update public.avis
     set masque = coalesce(cacher, true),
         motif_masque = left(coalesce(trim(raison), ''), 300),
         maj_le = now()
   where id = cible;
  if not found then raise exception 'Avis introuvable'; end if;
  return true;
end $$;
revoke all on function public.masquer_avis(text, boolean, text)
  from public, anon, authenticated;
grant execute on function public.masquer_avis(text, boolean, text) to authenticated;

-- ---------------------------------------------------------
-- 6. Qui lit quoi
-- ---------------------------------------------------------
alter table public.avis enable row level security;

drop policy if exists "avis lecture publique" on public.avis;
drop policy if exists "avis lecture equipe"   on public.avis;

-- Les avis sont PUBLICS : un avis que personne ne lit ne sert à rien.
-- Les masqués disparaissent pour tout le monde sauf l'équipe, qui doit
-- pouvoir vérifier ce qu'elle a masqué.
create policy "avis lecture publique" on public.avis
  for select using (not masque);
create policy "avis lecture equipe" on public.avis
  for select to authenticated
  using (public.est_super() or public.peut_agir_sur(boutique_id));

-- AUCUNE règle d'écriture : ni pour le client, ni pour la boutique.
-- Tout passe par les fonctions ci-dessus, qui vérifient l'achat et
-- relisent la boutique dans le catalogue.
revoke all on public.avis from anon, authenticated;
grant select on public.avis to anon, authenticated;

-- ---------- Vérification ----------
select
  case when exists (select 1 from information_schema.tables
                     where table_schema = 'public' and table_name = 'avis')
       then 'en place' else 'MANQUANT' end                      as "table avis",
  case when exists (select 1 from pg_proc where proname = 'a_achete')
       then 'en place' else 'MANQUANT' end                      as "a_achete()",
  case when exists (select 1 from pg_proc where proname = 'deposer_avis')
       then 'en place' else 'MANQUANT' end                      as "deposer_avis()",
  case when exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'produits'
                       and column_name = 'note_moyenne')
       then 'en place' else 'MANQUANT' end                      as "produits.note_moyenne",
  (select count(*)::int from public.avis)                       as "avis déposés",
  (select count(*)::int from public.avis where masque)          as "avis masqués";
