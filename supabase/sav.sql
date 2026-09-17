-- =========================================================
-- BIZZOO — le service après-vente
--
-- Un client a payé, et quelque chose ne va pas : rien reçu,
-- article abîmé, commande incomplète, pas conforme. Il ouvre une
-- réclamation.
--
-- LA BOUTIQUE D'ABORD, BIZZOO EN RECOURS. C'est la règle de ce
-- fichier, et tout le reste en découle.
--
--   1. LA RÉCLAMATION VA À LA BOUTIQUE. C'est elle qui a vendu,
--      elle qui a la marchandise, elle qui peut remplacer ou
--      rembourser le jour même. Faire passer chaque problème par
--      l'enseigne rallongerait tout, et l'enseigne ne saurait
--      rien de plus ;
--
--   2. BIZZOO N'ENTRE QU'EN RECOURS, et jamais avant. Deux
--      portes seulement s'ouvrent vers elle : la boutique a
--      répondu et le client n'est pas d'accord, ou la boutique
--      N'A PAS RÉPONDU passé le délai. Sans cette condition,
--      « la boutique d'abord » ne serait qu'une politesse : tout
--      le monde escaladerait à la seconde même, et l'enseigne
--      ferait le travail de ses boutiques ;
--
--   3. LA BOUTIQUE NE CLÔT PAS CE QUI LA MET EN CAUSE. Elle
--      répond. C'est le CLIENT qui dit « c'est réglé », ou
--      l'enseigne qui tranche. Une boutique capable de fermer
--      une réclamation fermerait toutes celles qui la gênent,
--      et le SAV ne serait plus qu'un formulaire ;
--
--   4. ON NE RÉCLAME QUE SUR SA PROPRE COMMANDE, ET PAYÉE. Une
--      commande ouverte et jamais réglée ne donne droit à rien —
--      même raison que pour les avis : elle ne coûte rien à
--      ouvrir, donc elle ne prouve rien.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, et rien n'est supprimé.
-- =========================================================

-- ---------------------------------------------------------
-- 1. Le délai au bout duquel le silence vaut réponse
-- ---------------------------------------------------------
-- Quarante-huit heures. Assez pour qu'une boutique fermée le
-- dimanche ne se fasse pas déborder ; assez court pour qu'un client
-- resté sans nouvelle ne soit pas prisonnier de ce silence.
--
-- Une fonction plutôt qu'un nombre écrit à dix endroits : le jour où
-- ce délai change, il change ici.
create or replace function public.delai_sav() returns interval
language sql immutable as $$ select interval '48 hours'; $$;

-- ---------- La réclamation ----------
create table if not exists public.reclamations (
  id          text primary key,
  client_id   uuid not null references public.clients(id) on delete cascade,
  -- Une réclamation SANS commande n'est pas une réclamation, c'est une
  -- question : elle a son chemin, le numéro WhatsApp de la boutique.
  commande_id text not null references public.commandes(id) on delete cascade,
  -- La boutique concernée, relue dans la COMMANDE. Jamais dans la
  -- requête : sinon on réclamerait chez l'une pour un achat fait chez
  -- l'autre.
  boutique_id text not null references public.boutiques(id) on delete cascade,
  -- L'article visé, quand il y en a un. À null, c'est toute la
  -- commande — « rien reçu » ne désigne aucun article en particulier.
  produit_id  text references public.produits(id) on delete set null,
  sujet       text not null default 'autre',
  --   'ouverte'   — la boutique doit répondre
  --   'repondue'  — elle a répondu, le client lit
  --   'resolue'   — le client dit que c'est réglé
  --   'escaladee' — BIZZOO est appelée en recours
  --   'tranchee'  — BIZZOO a décidé ; c'est fini
  etat        text not null default 'ouverte',
  escalade_le     timestamptz,
  escalade_motif  text not null default '',
  decision        text not null default '',
  decide_par      text not null default '',
  decide_le       timestamptz,
  -- Quand la boutique a répondu la première fois. C'est ce qui ouvre
  -- la porte du recours, avec le délai.
  repondu_le  timestamptz,
  cree_le     timestamptz not null default now(),
  maj_le      timestamptz not null default now()
);

alter table public.reclamations add column if not exists produit_id text
  references public.produits(id) on delete set null;
alter table public.reclamations add column if not exists escalade_le timestamptz;
alter table public.reclamations add column if not exists escalade_motif text not null default '';
alter table public.reclamations add column if not exists decision text not null default '';
alter table public.reclamations add column if not exists decide_par text not null default '';
alter table public.reclamations add column if not exists decide_le timestamptz;
alter table public.reclamations add column if not exists repondu_le timestamptz;

alter table public.reclamations drop constraint if exists reclamations_sujet;
alter table public.reclamations add constraint reclamations_sujet
  check (sujet in ('non_recu', 'abime', 'pas_conforme', 'incomplet', 'autre'));
alter table public.reclamations drop constraint if exists reclamations_etat;
alter table public.reclamations add constraint reclamations_etat
  check (etat in ('ouverte', 'repondue', 'resolue', 'escaladee', 'tranchee'));

create index if not exists reclamations_boutique
  on public.reclamations(boutique_id, cree_le desc);
create index if not exists reclamations_client
  on public.reclamations(client_id, cree_le desc);
create index if not exists reclamations_recours
  on public.reclamations(escalade_le desc) where etat = 'escaladee';

-- Une réclamation est une CONVERSATION, pas un formulaire. Un seul
-- champ « réponse » forcerait à écraser ce qui a été dit : le client
-- n'aurait plus de quoi montrer ce qu'on lui avait promis.
create table if not exists public.reclamation_messages (
  id             text primary key,
  reclamation_id text not null references public.reclamations(id) on delete cascade,
  -- 'client' | 'boutique' | 'enseigne' — écrit par la base, jamais
  -- envoyé par l'application.
  auteur_role    text not null default 'client',
  auteur_nom     text not null default '',
  texte          text not null default '',
  cree_le        timestamptz not null default now()
);
alter table public.reclamation_messages drop constraint if exists reclamation_messages_role;
alter table public.reclamation_messages add constraint reclamation_messages_role
  check (auteur_role in ('client', 'boutique', 'enseigne'));
create index if not exists reclamation_messages_fil
  on public.reclamation_messages(reclamation_id, cree_le);

-- ---------- Qui lit quoi ----------
-- « security definer » : sans elle, la règle des messages
-- interrogerait les réclamations, dont la règle interrogerait les
-- messages — PostgreSQL s'arrête sur « infinite recursion detected in
-- policy ». Même remède que pour les commandes.
create or replace function public.ma_reclamation(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.reclamations r
     where r.id = cible
       and (r.client_id = auth.uid()
            or public.est_super()
            or public.peut_agir_sur(r.boutique_id)));
$$;
revoke all on function public.ma_reclamation(text) from public, anon, authenticated;
grant execute on function public.ma_reclamation(text) to authenticated;

alter table public.reclamations         enable row level security;
alter table public.reclamation_messages enable row level security;

drop policy if exists "reclamations lecture"  on public.reclamations;
drop policy if exists "messages sav lecture"  on public.reclamation_messages;

-- Le client voit les siennes ; la boutique celles qui la concernent ;
-- l'enseigne toutes — c'est elle le recours, elle doit pouvoir juger
-- sur pièces, et voir venir ce qui va lui remonter.
create policy "reclamations lecture" on public.reclamations
  for select to authenticated
  using (client_id = auth.uid()
         or public.est_super()
         or public.peut_agir_sur(boutique_id));

create policy "messages sav lecture" on public.reclamation_messages
  for select to authenticated
  using (public.ma_reclamation(reclamation_id));

-- AUCUNE règle d'écriture, d'aucun côté : tout passe par les fonctions
-- ci-dessous, qui relisent la commande et vérifient l'état.
revoke all on public.reclamations         from anon, authenticated;
revoke all on public.reclamation_messages from anon, authenticated;
grant select on public.reclamations         to authenticated;
grant select on public.reclamation_messages to authenticated;

-- ---------------------------------------------------------
-- 4. Ouvrir une réclamation
-- ---------------------------------------------------------
create or replace function public.ouvrir_reclamation(
  commande text, produit text, sujet text, message text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  moi      uuid := auth.uid();
  c        public.commandes%rowtype;
  boutique text;
  nom      text;
  nouvelle text;
begin
  if moi is null then
    raise exception 'Connectez-vous pour ouvrir une réclamation';
  end if;

  select * into c from public.commandes where id = commande;
  if not found or c.client_id is distinct from moi then
    raise exception 'Cette commande n''est pas la vôtre';
  end if;
  -- MÊME RAISON QUE POUR LES AVIS : une commande ouverte et jamais
  -- réglée ne coûte rien, donc ne prouve rien.
  if c.etat <> 'payee' then
    raise exception 'Une réclamation se fait sur une commande payée';
  end if;

  -- La boutique vient de la COMMANDE. Un produit précisé doit en faire
  -- partie ; sinon on désignerait un article qu'on n'a pas acheté.
  if coalesce(produit, '') <> '' then
    select l.boutique_id into boutique
      from public.commande_lignes l
     where l.commande_id = c.id and l.produit_id = produit
     limit 1;
    if boutique is null then
      raise exception 'Cet article ne figure pas dans cette commande';
    end if;
  else
    produit := null;
    -- Une commande peut traverser plusieurs boutiques. Sans article
    -- précisé, la réclamation va à celle qui en a livré le plus —
    -- c'est la plus concernée, et le client peut en ouvrir une autre.
    select l.boutique_id into boutique
      from public.commande_lignes l
     where l.commande_id = c.id
     group by l.boutique_id
     order by sum(l.prix * l.quantite) desc
     limit 1;
    if boutique is null then
      raise exception 'Cette commande ne contient aucun article';
    end if;
  end if;

  if coalesce(sujet, '') not in ('non_recu', 'abime', 'pas_conforme', 'incomplet') then
    sujet := 'autre';
  end if;

  select coalesce(cl.nom, '') into nom from public.clients cl where cl.id = moi;
  nouvelle := 'sav_' || replace(gen_random_uuid()::text, '-', '');

  insert into public.reclamations
    (id, client_id, commande_id, boutique_id, produit_id, sujet, etat)
  values (nouvelle, moi, c.id, boutique, produit, sujet, 'ouverte');

  insert into public.reclamation_messages
    (id, reclamation_id, auteur_role, auteur_nom, texte)
  values ('msg_' || replace(gen_random_uuid()::text, '-', ''),
          nouvelle, 'client',
          left(coalesce(nullif(split_part(trim(nom), ' ', 1), ''), 'Client'), 40),
          left(coalesce(trim(message), ''), 2000));

  return jsonb_build_object('id', nouvelle, 'boutique', boutique);
end $$;

revoke all on function public.ouvrir_reclamation(text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.ouvrir_reclamation(text, text, text, text) to authenticated;

-- ---------------------------------------------------------
-- 5. Répondre — des deux côtés
-- ---------------------------------------------------------
-- Le client et la boutique écrivent dans le même fil. C'est la base
-- qui décide QUI parle, à partir du jeton : un rôle envoyé dans la
-- requête ne vaudrait rien.
create or replace function public.repondre_reclamation(cible text, message text)
returns text
language plpgsql security definer set search_path = public as $$
declare
  r     public.reclamations%rowtype;
  role  text;
  nom   text;
begin
  select * into r from public.reclamations where id = cible;
  if not found then raise exception 'Réclamation introuvable'; end if;
  if coalesce(trim(message), '') = '' then
    raise exception 'Écrivez votre message';
  end if;

  if r.client_id = auth.uid() then
    role := 'client';
    select coalesce(nullif(split_part(trim(coalesce(cl.nom, '')), ' ', 1), ''), 'Client')
      into nom from public.clients cl where cl.id = auth.uid();
  elsif public.est_super() then
    role := 'enseigne';
    select coalesce(p.email, 'BIZZOO') into nom
      from public.profils p where p.id = auth.uid();
  elsif public.peut_agir_sur(r.boutique_id) then
    role := 'boutique';
    select coalesce(b.nom, 'La boutique') into nom
      from public.boutiques b where b.id = r.boutique_id;
  else
    raise exception 'Cette réclamation ne vous concerne pas';
  end if;

  if r.etat in ('resolue', 'tranchee') then
    raise exception 'Cette réclamation est close';
  end if;

  insert into public.reclamation_messages
    (id, reclamation_id, auteur_role, auteur_nom, texte)
  values ('msg_' || replace(gen_random_uuid()::text, '-', ''),
          r.id, role, left(nom, 80), left(trim(message), 2000));

  /* La première réponse de la boutique ouvre la porte du recours : à
     partir de là, le client peut ne pas être d'accord. Avant, il n'a
     rien à contester — d'où « repondu_le », et non un simple état. */
  update public.reclamations
     set etat = case when role = 'boutique' and etat = 'ouverte' then 'repondue'
                     else etat end,
         repondu_le = case when role = 'boutique' and repondu_le is null
                           then now() else repondu_le end,
         maj_le = now()
   where id = r.id;

  return role;
end $$;

revoke all on function public.repondre_reclamation(text, text)
  from public, anon, authenticated;
grant execute on function public.repondre_reclamation(text, text) to authenticated;

-- ---------------------------------------------------------
-- 6. Le recours — et ce qui l'ouvre
-- ---------------------------------------------------------
-- LE CŒUR DE CE FICHIER. Deux portes seulement mènent à l'enseigne :
--
--   — la boutique a répondu, et le client n'est pas d'accord ;
--   — la boutique N'A PAS répondu passé le délai.
--
-- Sans cette condition, « la boutique d'abord » ne serait qu'une
-- phrase : chacun escaladerait à la seconde même, et l'enseigne ferait
-- le travail de ses boutiques.
create or replace function public.recours_possible(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.reclamations r
     where r.id = cible
       and r.client_id = auth.uid()
       and (r.etat = 'repondue'
            or (r.etat = 'ouverte' and r.cree_le < now() - public.delai_sav())));
$$;
revoke all on function public.recours_possible(text) from public, anon, authenticated;
grant execute on function public.recours_possible(text) to authenticated;

create or replace function public.escalader_reclamation(cible text, motif text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare r public.reclamations%rowtype;
begin
  select * into r from public.reclamations where id = cible;
  if not found then raise exception 'Réclamation introuvable'; end if;
  if r.client_id is distinct from auth.uid() then
    raise exception 'Seul le client appelle BIZZOO en recours';
  end if;
  if r.etat in ('resolue', 'tranchee') then
    raise exception 'Cette réclamation est close';
  end if;
  if r.etat = 'escaladee' then
    raise exception 'BIZZOO a déjà été saisie';
  end if;
  if not public.recours_possible(cible) then
    raise exception 'Laissez d''abord à la boutique le temps de répondre : BIZZOO n''intervient qu''ensuite';
  end if;

  update public.reclamations
     set etat = 'escaladee', escalade_le = now(),
         escalade_motif = left(coalesce(trim(motif), ''), 500), maj_le = now()
   where id = cible;
  return true;
end $$;
revoke all on function public.escalader_reclamation(text, text)
  from public, anon, authenticated;
grant execute on function public.escalader_reclamation(text, text) to authenticated;

-- ---------------------------------------------------------
-- 7. Clore — et qui en a le droit
-- ---------------------------------------------------------
-- LE CLIENT dit « c'est réglé ». Pas la boutique : celle-ci fermerait
-- ce qui la gêne, et le SAV ne serait plus qu'un formulaire.
create or replace function public.clore_reclamation(cible text) returns boolean
language plpgsql security definer set search_path = public as $$
declare r public.reclamations%rowtype;
begin
  select * into r from public.reclamations where id = cible;
  if not found then raise exception 'Réclamation introuvable'; end if;
  if r.client_id is distinct from auth.uid() then
    raise exception 'Seul le client dit que son problème est réglé';
  end if;
  if r.etat = 'tranchee' then
    raise exception 'BIZZOO a déjà tranché';
  end if;
  update public.reclamations set etat = 'resolue', maj_le = now() where id = cible;
  return true;
end $$;
revoke all on function public.clore_reclamation(text) from public, anon, authenticated;
grant execute on function public.clore_reclamation(text) to authenticated;

-- L'ENSEIGNE TRANCHE, et seulement ce qui lui a été remonté. Trancher
-- une réclamation que la boutique traite encore, ce serait lui retirer
-- le dossier des mains sans qu'on le lui ait demandé.
create or replace function public.trancher_reclamation(cible text, verdict text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  r   public.reclamations%rowtype;
  qui text;
begin
  if not public.est_super() then
    raise exception 'Seule BIZZOO tranche un recours';
  end if;
  select * into r from public.reclamations where id = cible;
  if not found then raise exception 'Réclamation introuvable'; end if;
  if r.etat <> 'escaladee' then
    raise exception 'BIZZOO ne tranche que ce qui lui est remonté';
  end if;
  if coalesce(trim(verdict), '') = '' then
    raise exception 'Dites votre décision : les deux parties la liront';
  end if;

  select coalesce(p.email, '') into qui from public.profils p where p.id = auth.uid();
  insert into public.reclamation_messages
    (id, reclamation_id, auteur_role, auteur_nom, texte)
  values ('msg_' || replace(gen_random_uuid()::text, '-', ''),
          r.id, 'enseigne', left(coalesce(qui, 'BIZZOO'), 80),
          left(trim(verdict), 2000));

  update public.reclamations
     set etat = 'tranchee', decision = left(trim(verdict), 2000),
         decide_par = coalesce(qui, ''), decide_le = now(), maj_le = now()
   where id = cible;
  return true;
end $$;
revoke all on function public.trancher_reclamation(text, text)
  from public, anon, authenticated;
grant execute on function public.trancher_reclamation(text, text) to authenticated;

-- ---------- Vérification ----------
select
  case when exists (select 1 from information_schema.tables
                     where table_schema = 'public' and table_name = 'reclamations')
       then 'en place' else 'MANQUANT' end                      as "table reclamations",
  case when exists (select 1 from pg_proc where proname = 'recours_possible')
       then 'en place' else 'MANQUANT' end                      as "recours_possible()",
  case when exists (select 1 from pg_proc where proname = 'trancher_reclamation')
       then 'en place' else 'MANQUANT' end                      as "trancher_reclamation()",
  (select public.delai_sav()::text)                             as "délai avant recours",
  (select count(*)::int from public.reclamations
    where etat in ('ouverte', 'repondue'))                      as "en cours",
  (select count(*)::int from public.reclamations
    where etat = 'escaladee')                                   as "remontées à BIZZOO";
