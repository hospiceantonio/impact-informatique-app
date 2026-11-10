-- =========================================================
-- BIZZOO 3.80.0 — Les notifications dans le navigateur (Web Push)
--
--   Client et Admin, sans l'application Android, reçoivent désormais
--   leurs notifications dans le navigateur, même le site fermé, une fois
--   autorisées dans « Mon compte ». Mêmes clés VAPID que BIZZOO Personnel.
--   À déployer avec la fonction Edge « envoyer-push » à jour.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- =========================================================
-- (3.80.0) LES NOTIFICATIONS DANS LE NAVIGATEUR (Web Push)
--
-- Sans l'application Android, Client et Admin ne recevaient rien : un
-- client sur le site, une boutique, un vendeur ou un livreur dans le
-- navigateur. Désormais chacun peut, depuis « Mon compte », autoriser son
-- navigateur : il reçoit alors les mêmes notifications que l'application,
-- même le site fermé (Android, ordinateur ; iPhone : BIZZOO ajouté à
-- l'écran d'accueil). Les clés VAPID sont celles de BIZZOO Personnel
-- (« rh_push_reglage », secrets de la fonction Edge) : la clé publique se
-- lit ici, la privée ne quitte jamais les secrets.
--
-- Les SMS des clients ne changent pas : un navigateur abonné ne les
-- remplace pas (une notification web se coupe trop facilement).
-- =========================================================
-- (3.80.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.langue_du_compte(qui uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select l.langue from public.langues_comptes l where l.compte = qui), 'fr');
$$;
revoke all on function public.langue_du_compte(uuid) from public, anon, authenticated;
grant execute on function public.langue_du_compte(uuid) to service_role;

create table if not exists public.appareils_web (
  endpoint    text primary key check (endpoint ~ '^https://' and length(endpoint) <= 2000),
  compte      uuid not null references auth.users(id) on delete cascade,
  application text not null check (application in ('admin', 'client')),
  p256dh      text not null check (length(p256dh) between 40 and 200),
  auth        text not null check (length(auth) between 10 and 100),
  maj_le      timestamptz not null default now()
);
create index if not exists appareils_web_compte on public.appareils_web(compte, application);
alter table public.appareils_web enable row level security;
revoke all on public.appareils_web from public, anon, authenticated;

-- Les navigateurs d'un compte pour une application : de quoi chiffrer.
create or replace function public.navigateurs_de(qui uuid, app text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if to_regclass('public.appareils_web') is null then
    return '[]'::jsonb;
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('endpoint', w.endpoint, 'p256dh', w.p256dh, 'auth', w.auth)
                                    order by w.maj_le desc)
                     from public.appareils_web w
                    where w.compte = qui and w.application = app), '[]'::jsonb);
end $$;
revoke all on function public.navigateurs_de(uuid, text) from public, anon, authenticated;

-- La clé publique : publique par nature, le navigateur en a besoin pour s'abonner.
create or replace function public.cle_push_web() returns text
language plpgsql stable security definer set search_path = public as $$
begin
  if to_regclass('public.rh_push_reglage') is null then
    return null;
  end if;
  return nullif((select g.cle_publique from public.rh_push_reglage g where g.id = 1), '');
end $$;
revoke all on function public.cle_push_web() from public;
grant execute on function public.cle_push_web() to anon, authenticated;

-- Ce navigateur s'abonne pour le compte connecté. Cinq au plus par compte
-- et par application : les plus anciens s'effacent.
create or replace function public.enregistrer_navigateur(point text, cle text, secret text, application text default 'admin')
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  app text := case when application = 'client' then 'client' else 'admin' end;
begin
  if moi is null then
    raise exception 'Connectez-vous d''abord.' using errcode = 'P0001';
  end if;
  if coalesce(point, '') !~ '^https://' or length(point) > 2000
     or length(coalesce(cle, '')) not between 40 and 200 or length(coalesce(secret, '')) not between 10 and 100 then
    raise exception 'Abonnement du navigateur illisible.' using errcode = 'P0001';
  end if;
  insert into public.appareils_web (endpoint, compte, application, p256dh, auth, maj_le)
  values (point, moi, app, cle, secret, clock_timestamp())
  on conflict (endpoint) do update
     set compte = excluded.compte, application = excluded.application,
         p256dh = excluded.p256dh, auth = excluded.auth, maj_le = clock_timestamp();
  delete from public.appareils_web w
   where w.compte = moi and w.application = app
     and w.endpoint not in (select x.endpoint from public.appareils_web x
                             where x.compte = moi and x.application = app
                             order by x.maj_le desc limit 5);
  return true;
end $$;
revoke all on function public.enregistrer_navigateur(text, text, text, text) from public, anon;
grant execute on function public.enregistrer_navigateur(text, text, text, text) to authenticated;

-- Ce navigateur ne reçoit plus rien. L'adresse d'abonnement, que seul ce
-- navigateur connaît, suffit : une déconnexion hors ligne se rejoue sans session.
create or replace function public.oublier_navigateur(point text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  delete from public.appareils_web w where w.endpoint = coalesce(point, '');
  return found;
end $$;
revoke all on function public.oublier_navigateur(text) from public;
grant execute on function public.oublier_navigateur(text) to anon, authenticated;

-- Un abonnement que le service de push ne connaît plus : oublié. Réservé au serveur.
create or replace function public.navigateur_mort(point text) returns void
language sql security definer set search_path = public as $$
  delete from public.appareils_web w where w.endpoint = point;
$$;
revoke all on function public.navigateur_mort(text) from public, anon, authenticated;

-- La notification part aussi vers les navigateurs.
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
    -- (3.73.0) La langue du destinataire : la fonction Edge traduit.
    'langue', public.langue_du_compte(n.destinataire),
    'application', case when coalesce(n.lien, '') like '#/commande/%' then 'client' else 'admin' end,
    'jetons', coalesce((select jsonb_agg(a.jeton order by a.maj_le desc)
                          from public.appareils_push a
                         where a.compte = n.destinataire
                           and a.application = case when coalesce(n.lien, '') like '#/commande/%'
                                                    then 'client' else 'admin' end), '[]'::jsonb),
    -- (3.80.0) Ses navigateurs abonnés (Web Push), de la même application.
    -- Lu par « to_regclass » : une base sans la table rend une liste vide.
    'web', public.navigateurs_de(n.destinataire,
             case when coalesce(n.lien, '') like '#/commande/%' then 'client' else 'admin' end));
end $$;
revoke all on function public.push_a_envoyer(bigint) from public, anon, authenticated;

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
                                             then 'client' else 'admin' end)
     -- (3.80.0) ni navigateur abonné : personne à réveiller.
     and jsonb_array_length(public.navigateurs_de(new.destinataire,
           case when coalesce(new.lien, '') like '#/commande/%' then 'client' else 'admin' end)) = 0 then
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
