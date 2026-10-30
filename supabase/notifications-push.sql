-- =========================================================
-- BIZZOO 3.65.0 — Les notifications push, application fermée
--
--   Une course confiée à un livreur, une commande payée chez une
--   boutique : le téléphone sonne même quand BIZZOO Admin est fermée.
--
--   Après ce fichier :
--     1. activer pg_net (Database → Extensions → pg_net) ;
--     2. déployer la fonction Edge « envoyer-push » (sans vérification du
--        jeton : elle ne fait que relire la base) ;
--     3. poser son adresse :
--          update public.push_reglage
--             set url = 'https://<projet>.supabase.co/functions/v1/envoyer-push';
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- =========================================================
-- Les notifications push, application fermée (3.65.0)
-- =========================================================
-- UNE COURSE CONFIÉE, UNE COMMANDE PAYÉE : le téléphone doit sonner même
-- quand BIZZOO Admin est fermée ou en veille. L'application ouverte
-- sonne déjà toute seule (temps réel) ; fermée, il faut que la nouvelle
-- vienne de dehors — Firebase Cloud Messaging.
--
--   1. CHAQUE TÉLÉPHONE se déclare à la connexion : son jeton Firebase,
--      rattaché au compte connecté (« enregistrer_appareil ») ; il s'en
--      retire à la déconnexion (« oublier_appareil »).
--   2. UNE NOTIFICATION QUI SONNE (« sonne », posé par « notifier ») et
--      dont le destinataire a un téléphone déclaré déclenche un appel à
--      la fonction Edge « envoyer-push », par pg_net, APRÈS la
--      transaction : une notification annulée ne part pas.
--   3. LA FONCTION EDGE ne reçoit que le numéro de la notification. Elle
--      relit tout dans la base (« push_a_envoyer », serveur seul), qui
--      la marque envoyée au passage : un appel rejoué, ou forgé, ne fait
--      rien partir une seconde fois.
--
-- Sans pg_net, ou sans l'adresse de la fonction (« push_reglage »), rien
-- ne part et rien ne casse : les notifications s'écrivent comme avant.
create table if not exists public.appareils_push (
  jeton       text primary key check (length(jeton) between 20 and 4096),
  compte      uuid not null references auth.users(id) on delete cascade,
  application text not null default 'admin' check (application in ('admin', 'client')),
  maj_le      timestamptz not null default now()
);
create index if not exists appareils_push_compte on public.appareils_push(compte);
alter table public.appareils_push enable row level security;
revoke all on public.appareils_push from anon, authenticated;

-- L'adresse de la fonction Edge : propre à chaque projet Supabase.
create table if not exists public.push_reglage (
  id  int primary key default 1 check (id = 1),
  url text not null default '' check (url = '' or url ~ '^https://')
);
insert into public.push_reglage (id) values (1) on conflict (id) do nothing;
alter table public.push_reglage enable row level security;
revoke all on public.push_reglage from anon, authenticated;

alter table public.notifications add column if not exists push_le timestamptz;

-- Le téléphone se déclare. Un jeton passe d'un compte à l'autre quand on
-- change de compte sur le même téléphone : il suit le dernier connecté.
create or replace function public.enregistrer_appareil(jeton text, application text default 'admin')
returns boolean
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  moi uuid := auth.uid();
  j   text := trim(coalesce(jeton, ''));
  app text := case when application = 'client' then 'client' else 'admin' end;
begin
  if moi is null then return false; end if;
  if length(j) < 20 or length(j) > 4096 then
    raise exception 'Jeton de notification invalide.' using errcode = 'P0001';
  end if;
  insert into public.appareils_push (jeton, compte, application, maj_le)
  values (j, moi, app, clock_timestamp())
  on conflict (jeton) do update
     set compte = excluded.compte, application = excluded.application, maj_le = clock_timestamp();
  -- Dix téléphones au plus par compte : les plus anciens s'effacent.
  delete from public.appareils_push a
   where a.compte = moi
     and a.jeton not in (select x.jeton from public.appareils_push x
                          where x.compte = moi order by x.maj_le desc limit 10);
  return true;
end $$;
revoke all on function public.enregistrer_appareil(text, text) from public, anon;
grant execute on function public.enregistrer_appareil(text, text) to authenticated;

create or replace function public.oublier_appareil(jeton text)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return false; end if;
  delete from public.appareils_push a where a.jeton = trim(coalesce(oublier_appareil.jeton, ''))
     and a.compte = auth.uid();
  return found;
end $$;
revoke all on function public.oublier_appareil(text) from public, anon;
grant execute on function public.oublier_appareil(text) to authenticated;

-- Ce que la fonction Edge envoie : la notification et les téléphones de
-- son destinataire — une seule fois. Réservé au serveur.
create or replace function public.push_a_envoyer(cible bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare n public.notifications%rowtype;
begin
  update public.notifications x set push_le = now()
   where x.id = cible and x.push_le is null and x.sonne
     and x.cree_le > now() - interval '1 hour'
  returning * into n;
  if not found then return null; end if;
  return jsonb_build_object(
    'id', n.id, 'type', n.type, 'titre', n.titre, 'corps', n.corps, 'lien', n.lien,
    'commande_id', n.commande_id,
    'application', case when coalesce(n.lien, '') like '#/commande/%' then 'client' else 'admin' end,
    'jetons', coalesce((select jsonb_agg(a.jeton order by a.maj_le desc)
                          from public.appareils_push a
                         where a.compte = n.destinataire
                           and a.application = case when coalesce(n.lien, '') like '#/commande/%'
                                                    then 'client' else 'admin' end), '[]'::jsonb));
end $$;
revoke all on function public.push_a_envoyer(bigint) from public, anon, authenticated;

-- Un jeton que Firebase ne connaît plus (application désinstallée) :
-- on l'oublie. Réservé au serveur.
create or replace function public.jeton_push_mort(jeton text)
returns void
language sql security definer set search_path = public as $$
  delete from public.appareils_push a where a.jeton = jeton_push_mort.jeton;
$$;
revoke all on function public.jeton_push_mort(text) from public, anon, authenticated;

-- LE DÉCLENCHEUR. Il ne fait qu'une demande, après la transaction ; il ne
-- bloque jamais l'écriture de la notification, quoi qu'il arrive.
create or replace function public.notification_pousse() returns trigger
language plpgsql security definer set search_path = public as $$
declare adresse text;
begin
  if not new.sonne then return null; end if;
  if to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then return null; end if;
  select r.url into adresse from public.push_reglage r where r.id = 1;
  if coalesce(adresse, '') = '' then return null; end if;
  if not exists (select 1 from public.appareils_push a
                  where a.compte = new.destinataire
                    and a.application = case when coalesce(new.lien, '') like '#/commande/%'
                                             then 'client' else 'admin' end) then
    return null;
  end if;
  begin
    perform net.http_post(adresse, jsonb_build_object('id', new.id),
      '{}'::jsonb, '{"Content-Type": "application/json"}'::jsonb, 10000);
  exception when others then
    raise warning 'notification_pousse(%) : %', new.id, sqlerrm;
  end;
  return null;
end $$;
drop trigger if exists notifications_poussent on public.notifications;
create trigger notifications_poussent
  after insert on public.notifications
  for each row execute function public.notification_pousse();
