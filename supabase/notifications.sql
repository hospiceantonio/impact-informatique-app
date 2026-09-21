-- =========================================================
-- BIZZOO — les notifications
--
-- CE QUE CE FICHIER AJOUTE : une table « notifications », ses
-- règles, et les déclencheurs qui la remplissent au fil du
-- cycle d'une commande — payée, préparée, confiée, en route,
-- remise, confirmée, annulée.
--
-- CE QU'IL NE DÉFAIT PAS : rien. Aucune commande, aucun
-- produit, aucun réglage n'est touché. Les déclencheurs se
-- posent APRÈS l'écriture (« after update ») : si l'un d'eux
-- échouait, il ne pourrait pas empêcher une commande
-- d'avancer. On peut le coller deux fois de suite sans
-- conséquence.
--
-- QUI PEUT ÉCRIRE ICI : PERSONNE. Aucune règle d'insertion
-- n'existe, pour aucun rang. Les notifications naissent des
-- déclencheurs et d'eux seuls — un client ne peut pas
-- s'inventer une commande livrée, ni une boutique se fabriquer
-- un accusé de réception. La seule écriture permise est
-- « lue_le », sur ses propres lignes.
--
-- APRÈS L'AVOIR COLLÉ : allez dans Database → Replication et
-- vérifiez que « notifications » est bien publiée en temps
-- réel. Le fichier s'en charge, mais seulement si la
-- publication « supabase_realtime » existe déjà.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
-- =========================================================

-- ---------- Recopié de schema.sql ----------
-- Ce fichier doit pouvoir se coller seul sur une base d'avant : les
-- déclencheurs ci-dessous lisent ces colonnes-là.
alter table public.profils
  add column if not exists peut_commandes boolean not null default true;
alter table public.commandes
  add column if not exists client_id uuid;
alter table public.commande_lignes
  add column if not exists livreur_id uuid;
alter table public.commande_lignes
  add column if not exists confirme_le timestamptz;

-- =========================================================
-- Les notifications
--
-- UNE LIGNE PAR PERSONNE PRÉVENUE, et non une ligne par
-- événement. C'est plus de lignes, mais c'est la seule forme
-- où « lue » veut dire quelque chose : une commande payée
-- prévient le client, l'équipe de chaque boutique concernée,
-- les comptes de BIZZOO et le superadministrateur — chacun la
-- lit à son heure, et l'un ne décoche rien pour les autres.
--
-- PERSONNE N'ÉCRIT ICI, PAS MÊME L'APPLICATION. Aucune règle
-- d'insertion n'existe : les notifications naissent de
-- déclencheurs, qui posent ce que le cycle de la commande dit,
-- et rien d'autre. Un client ne peut donc pas s'inventer une
-- commande livrée, ni une boutique se fabriquer un accusé de
-- réception. La seule chose qu'on puisse écrire, c'est
-- « lue_le », et sur ses propres lignes.
--
-- AUCUN MONTANT N'Y ENTRE, et c'est voulu. Un livreur reçoit
-- « une course vous est confiée », pas « 385 000 FCFA ». La
-- règle des prix fermés ne servirait à rien si le texte d'une
-- notification les recopiait.
-- =========================================================

create table if not exists public.notifications (
  id           bigserial primary key,
  destinataire uuid not null references auth.users(id) on delete cascade,
  type         text not null,
  titre        text not null default '',
  corps        text not null default '',
  -- Où mène le doigt : « #/commande/… » chez le client,
  -- « #/commandes/… » chez la boutique, « #/livraisons » chez le livreur.
  lien         text not null default '',
  commande_id  text,
  boutique_id  text,
  -- Les trois bips. Tout ce qui touche une commande sonne ; le reste, non.
  sonne        boolean not null default false,
  lue_le       timestamptz,
  cree_le      timestamptz not null default now()
);

create index if not exists notifications_a_moi
  on public.notifications (destinataire, cree_le desc);
create index if not exists notifications_non_lues
  on public.notifications (destinataire) where lue_le is null;

-- UNE FOIS, ET UNE SEULE. Une commande de trois articles chez la même
-- boutique fait trois lignes qui passent à « préparée » : sans cet
-- index, la boutique recevrait trois fois la même nouvelle. Le
-- « coalesce » n'est pas décoratif — deux NULL sont DISTINCTS pour un
-- index unique, et la contrainte n'aurait rien retenu sur les
-- notifications sans boutique.
create unique index if not exists notifications_une_fois
  on public.notifications
     (destinataire, type, commande_id, coalesce(boutique_id, ''))
  where commande_id is not null;

alter table public.notifications enable row level security;
drop policy if exists "notifications a soi"      on public.notifications;
drop policy if exists "notifications marquer lues" on public.notifications;
-- Chacun les siennes. Il n'y a pas d'autre règle : ni insertion, ni
-- suppression, pour personne.
create policy "notifications a soi" on public.notifications
  for select to authenticated using (destinataire = auth.uid());
create policy "notifications marquer lues" on public.notifications
  for update to authenticated
  using (destinataire = auth.uid()) with check (destinataire = auth.uid());

-- UNE BASE SUPABASE DONNE TOUT PAR DÉFAUT : un « grant » posé
-- par-dessus n'enlève rien, il faut « revoke » d'abord. Et la mise à
-- jour se limite à « lue_le » — le titre et le lien d'une notification
-- ne se réécrivent pas après coup.
revoke all on public.notifications from anon, authenticated;
revoke all on sequence public.notifications_id_seq from anon, authenticated;
grant select on public.notifications to authenticated;
grant update (lue_le) on public.notifications to authenticated;

-- ---------- À qui l'on écrit ----------
-- Trois listes, et elles disent à elles seules qui est prévenu de quoi.

-- L'équipe d'une boutique : ceux qui la tiennent. PAS le livreur — il
-- reçoit ses courses, pas les nouvelles de la boutique.
create or replace function public.equipe_de(cible text) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and cible is not null and p.boutique_id = cible
     and p.role in ('administrateur', 'moderateur');
$$;

-- Les comptes de BIZZOO qui suivent les commandes. Leur interrupteur
-- décide : éteint, on ne les dérange pas pour ce qu'ils ne voient pas.
create or replace function public.enseigne_des_commandes() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.boutique_id is null and p.peut_commandes
     and p.role in ('administrateur', 'moderateur');
$$;

-- LE SUPERADMINISTRATEUR N'EST PAS PRÉVENU DE TOUT, et c'est un choix.
-- À dix boutiques et vingt commandes par jour, être prévenu de chaque
-- cran ferait plusieurs centaines de pastilles quotidiennes : une
-- pastille qui ne redescend jamais à zéro ne veut plus rien dire. Il
-- reçoit l'ARGENT qui entre et les INCIDENTS ; les étapes
-- intermédiaires restent lisibles sur l'écran des commandes.
create or replace function public.les_superadmins() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.role = 'superadministrateur';
$$;

revoke all on function public.equipe_de(text)            from public, anon, authenticated;
revoke all on function public.enseigne_des_commandes()   from public, anon, authenticated;
revoke all on function public.les_superadmins()          from public, anon, authenticated;

-- ---------- Écrire la notification ----------
-- « on conflict do nothing » s'appuie sur l'index unique plus haut :
-- c'est lui qui fait qu'une commande de trois articles ne prévient
-- qu'une fois.
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

-- ---------- Le paiement ----------
-- Le premier cran, et le seul qui réveille le superadministrateur :
-- c'est de l'argent qui entre.
create or replace function public.notifier_paiement() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  b        record;
  numero   text := coalesce(new.numero, '');
  client   uuid := new.client_id;
begin
  if new.etat is not distinct from old.etat or new.etat <> 'payee' then
    return new;
  end if;

  -- Le client, s'il a un compte. Une commande passée sans compte n'a
  -- personne à prévenir — le reçu lui est déjà revenu par WhatsApp.
  if client is not null then
    perform public.notifier(array[client], 'commande_payee',
      'Paiement reçu',
      'Votre commande ' || numero || ' est confirmée. Nous la préparons.',
      '#/commande/' || new.id, new.id, null, true);
  end if;

  -- Chaque boutique concernée, une fois.
  for b in select distinct l.boutique_id from public.commande_lignes l
            where l.commande_id = new.id and l.boutique_id is not null loop
    perform public.notifier(public.equipe_de(b.boutique_id), 'commande_payee',
      'Nouvelle commande payée',
      'La commande ' || numero || ' est payée. À préparer.',
      '#/commandes/' || new.id, new.id, b.boutique_id, true);
  end loop;

  perform public.notifier(public.enseigne_des_commandes(), 'commande_payee',
    'Nouvelle commande payée',
    'La commande ' || numero || ' vient d''être payée.',
    '#/commandes/' || new.id, new.id, null, true);

  perform public.notifier(public.les_superadmins(), 'commande_payee',
    'Paiement encaissé',
    'La commande ' || numero || ' est payée.',
    '#/commandes/' || new.id, new.id, null, true);

  return new;
end $$;

drop trigger if exists commandes_notifient on public.commandes;
create trigger commandes_notifient
  after update on public.commandes
  for each row execute function public.notifier_paiement();

-- ---------- Le cycle de la ligne ----------
-- Préparée, confiée, en route, remise, confirmée, annulée. Un
-- déclencheur par LIGNE, mais l'index unique n'en laisse passer qu'une
-- par boutique et par cran.
create or replace function public.notifier_ligne() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  cmd      record;
  numero   text;
  client   uuid;
  equipe   uuid[];
  enseigne uuid[];
begin
  select c.numero, c.client_id into cmd
    from public.commandes c where c.id = new.commande_id;
  numero   := coalesce(cmd.numero, '');
  client   := cmd.client_id;
  equipe   := public.equipe_de(new.boutique_id);
  enseigne := public.enseigne_des_commandes();

  -- ---- Une course confiée, ou reprise ----
  if new.livreur_id is distinct from old.livreur_id then
    if new.livreur_id is not null then
      -- LE LIVREUR NE VOIT AUCUN MONTANT, ici comme ailleurs.
      perform public.notifier(array[new.livreur_id], 'course_confiee',
        'Une course vous est confiée',
        'Commande ' || numero || ' — ouvrez vos livraisons pour l''adresse.',
        '#/livraisons', new.commande_id, new.boutique_id, true);
    end if;
    perform public.notifier(enseigne, 'course_confiee',
      'Course confiée à un livreur',
      'Commande ' || numero || '.',
      '#/commandes/' || new.commande_id, new.commande_id, new.boutique_id, true);
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

drop trigger if exists lignes_notifient on public.commande_lignes;
create trigger lignes_notifient
  after update on public.commande_lignes
  for each row execute function public.notifier_ligne();

-- ---------- Ce que l'application demande ----------
-- Combien n'ai-je pas lu ? Une seule question, une seule réponse : la
-- pastille ne compte pas les lignes elle-même.
create or replace function public.mes_notifications_non_lues() returns int
language sql stable security definer set search_path = public as $$
  select coalesce(count(*), 0)::int from public.notifications
   where destinataire = auth.uid() and lue_le is null;
$$;
revoke all on function public.mes_notifications_non_lues() from public, anon;
grant execute on function public.mes_notifications_non_lues() to authenticated;

-- Tout marquer lu d'un geste. Rend le nombre de lignes touchées, pour
-- que l'écran sache quoi dire.
create or replace function public.tout_marquer_lu() returns int
language plpgsql security definer set search_path = public as $$
declare combien int;
begin
  if auth.uid() is null then return 0; end if;
  update public.notifications set lue_le = now()
   where destinataire = auth.uid() and lue_le is null;
  get diagnostics combien = row_count;
  return combien;
end $$;
revoke all on function public.tout_marquer_lu() from public, anon;
grant execute on function public.tout_marquer_lu() to authenticated;

-- ---------- Temps réel ----------
-- Sans cela, la pastille n'apparaîtrait qu'à la prochaine ouverture de
-- l'application — « instantané » n'aurait plus grand sens.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
 and not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime'
                    and schemaname = 'public' and tablename = 'notifications') then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;

-- ---------- Un contrôle à la fin ----------
do $$
declare manque text := '';
begin
  if to_regclass('public.notifications') is null then
    manque := manque || ' table notifications';
  end if;
  if to_regprocedure('public.notifier(uuid[],text,text,text,text,text,text,boolean)') is null then
    manque := manque || ' notifier()';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'lignes_notifient') then
    manque := manque || ' declencheur lignes_notifient';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'commandes_notifient') then
    manque := manque || ' declencheur commandes_notifient';
  end if;
  if manque <> '' then
    raise exception 'Manque :%', manque;
  end if;
  raise notice 'Les notifications sont posées.';
end $$;
