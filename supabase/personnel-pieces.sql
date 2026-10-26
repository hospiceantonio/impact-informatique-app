-- =========================================================
-- BIZZOO Personnel : photos, vidéos et audio dans les discussions,
-- et tout message effacé au bout de 7 jours
--
-- Un message porte au plus une pièce, rangée dans le seau PRIVÉ
-- « rh-pieces », dans le dossier de son auteur. Elle se lit avec un
-- lien signé, que seule obtient une personne qui voit le message.
--
-- Chaque heure, pg_cron efface les messages de plus de 7 jours
-- (rh_purger_messages), puis appelle la fonction rh-menage, qui efface
-- du stockage les fichiers que plus aucun message ne cite.
-- =========================================================

-- ---------- Les aides (copies de schema.sql) ----------
create or replace function public.rh_moi() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_est_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and (administration or ceo));
$$;

create or replace function public.rh_mon_profil() returns uuid
language sql stable security definer set search_path = public as $$
  select profil_id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_menu_ouvert(cle text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_moi uuid := public.rh_moi();
  v_profil uuid := public.rh_mon_profil();
begin
  if public.rh_est_admin() then
    return true;
  end if;
  if v_moi is null then
    return false;
  end if;
  if to_regclass('public.rh_acces_menus') is null then
    return cle in ('mails', 'discussions', 'missions', 'rapports');
  end if;
  if v_profil is null and not exists (select 1 from public.rh_profils p where p.responsable_id = v_moi) then
    return cle in ('mails', 'discussions', 'depenses');
  end if;
  return exists (
    select 1 from public.rh_acces_menus a
      join public.rh_profils p on p.id = a.profil_id
     where a.menu = cle
       and (p.responsable_id = v_moi or (a.qui = 'membres' and p.id = v_profil)));
end $$;

-- ---------- Le seau des pièces jointes ----------
-- PRIVÉ : un fichier ne se lit qu'avec un lien signé, que seule obtient
-- une personne qui voit le message qui le porte.
insert into storage.buckets (id, name, public)
values ('rh-pieces', 'rh-pieces', false)
on conflict (id) do nothing;
update storage.buckets
   set public = false,
       file_size_limit = 52428800,   -- 50 Mo : une vidéo de téléphone d'une minute ou deux
       allowed_mime_types = array[
         'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic', 'image/heif',
         'video/mp4', 'video/webm', 'video/quicktime', 'video/3gpp',
         'audio/mpeg', 'audio/mp4', 'audio/aac', 'audio/ogg', 'audio/webm', 'audio/wav',
         'audio/x-wav', 'audio/x-m4a', 'audio/3gpp', 'audio/amr']
 where id = 'rh-pieces';

-- ---------- Le message porte au plus une pièce ----------
alter table public.rh_messages add column if not exists piece text;
alter table public.rh_messages add column if not exists piece_type text;
alter table public.rh_messages add column if not exists piece_nom text not null default '';
alter table public.rh_messages add column if not exists piece_taille bigint;
create index if not exists rh_messages_piece on public.rh_messages (piece) where piece is not null;
create index if not exists rh_messages_age on public.rh_messages (cree_le);

do $$
begin
  -- Un message sans texte est permis s'il porte une pièce.
  if exists (select 1 from pg_constraint where conname = 'rh_messages_texte_check') then
    alter table public.rh_messages drop constraint rh_messages_texte_check;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_messages_contenu') then
    alter table public.rh_messages add constraint rh_messages_contenu
      check (length(texte) <= 4000 and (piece is not null or length(btrim(texte)) >= 1));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_messages_piece_type') then
    alter table public.rh_messages add constraint rh_messages_piece_type
      check ((piece is null) = (piece_type is null)
             and (piece_type is null or piece_type in ('image', 'video', 'audio')));
  end if;
end $$;

/** La pièce d'un message : un fichier que SON AUTEUR a déposé (son
    dossier), présent dans le seau, cité par un seul message. Le type
    et le poids se lisent dans le stockage, jamais dans la requête.
    Après rh_messages_verrous (ordre alphabétique) : l'auteur est posé. */
create or replace function public.rh_message_piece() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  o storage.objects;
  mime text;
begin
  if new.piece is null then
    new.piece_type := null;
    new.piece_nom := '';
    new.piece_taille := null;
    return new;
  end if;
  select * into o from storage.objects
   where bucket_id = 'rh-pieces' and name = new.piece;
  if not found or split_part(new.piece, '/', 1) is distinct from new.auteur_id::text then
    raise exception 'Pièce jointe introuvable : envoyez-la de nouveau';
  end if;
  if exists (select 1 from public.rh_messages m where m.piece = new.piece) then
    raise exception 'Cette pièce jointe est déjà envoyée';
  end if;
  mime := lower(coalesce(o.metadata ->> 'mimetype', ''));
  new.piece_type := case
    when mime like 'image/%' then 'image'
    when mime like 'video/%' then 'video'
    when mime like 'audio/%' then 'audio'
  end;
  if new.piece_type is null then
    raise exception 'Seules les photos, les vidéos et les enregistrements audio s''envoient';
  end if;
  new.piece_taille := nullif(o.metadata ->> 'size', '')::bigint;
  new.piece_nom := left(btrim(coalesce(new.piece_nom, '')), 120);
  return new;
end $$;
drop trigger if exists rh_messages_verrous_piece on public.rh_messages;
create trigger rh_messages_verrous_piece
  before insert on public.rh_messages
  for each row execute function public.rh_message_piece();

-- ---------- Qui dépose, qui lit ----------
-- Chacun dépose dans SON dossier (son identifiant d'employé), s'il a
-- les discussions. On lit un fichier si l'on voit le message qui le
-- porte — les règles de rh_messages s'appliquent dans la sous-requête —
-- ou si c'est le sien. On retire le sien tant qu'aucun message ne le cite.
drop policy if exists "rh pieces depot" on storage.objects;
drop policy if exists "rh pieces lecture" on storage.objects;
drop policy if exists "rh pieces retrait" on storage.objects;
create policy "rh pieces depot" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'rh-pieces'
              and split_part(name, '/', 1) = public.rh_moi()::text
              and public.rh_menu_ouvert('discussions'));
create policy "rh pieces lecture" on storage.objects
  for select to authenticated
  using (bucket_id = 'rh-pieces'
         and (split_part(name, '/', 1) = public.rh_moi()::text
              or exists (select 1 from public.rh_messages m where m.piece = objects.name)));
create policy "rh pieces retrait" on storage.objects
  for delete to authenticated
  using (bucket_id = 'rh-pieces'
         and split_part(name, '/', 1) = public.rh_moi()::text
         and not exists (select 1 from public.rh_messages m where m.piece = objects.name));

-- ---------- Tout s'efface au bout de 7 jours ----------
/** Les messages de plus de 7 jours : texte et pièce partent ensemble. */
create or replace function public.rh_purger_messages() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  delete from public.rh_messages where cree_le < now() - interval '7 days';
  get diagnostics n = row_count;
  return n;
end $$;

/** Les fichiers à effacer du stockage : plus cités par aucun message
    (message effacé, ou envoi abandonné depuis plus d'une heure). */
create or replace function public.rh_pieces_perimees() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(o.name order by o.created_at), '{}')
    from storage.objects o
   where o.bucket_id = 'rh-pieces'
     and o.created_at < now() - interval '1 hour'
     and not exists (select 1 from public.rh_messages m where m.piece = o.name);
$$;

revoke all on function public.rh_message_piece() from public, anon, authenticated;
revoke all on function public.rh_purger_messages() from public, anon, authenticated;
revoke all on function public.rh_pieces_perimees() from public, anon, authenticated;
grant execute on function public.rh_purger_messages() to service_role;
grant execute on function public.rh_pieces_perimees() to service_role;

-- pg_cron, chaque heure : la base efface les messages elle-même ; la
-- fonction rh-menage efface ensuite les fichiers (par pg_net). Sans
-- pg_net, les messages partent quand même ; les fichiers attendent.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('rh-messages-7-jours', '7 * * * *', 'select public.rh_purger_messages()');
    if exists (select 1 from pg_available_extensions where name = 'pg_net') then
      create extension if not exists pg_net;
      perform cron.schedule('rh-pieces-menage', '12 * * * *',
        'select net.http_post(''https://rrwzegmrmvvkmzfoiitb.supabase.co/functions/v1/rh-menage'', ''{}''::jsonb, ''{}''::jsonb, ''{"Content-Type": "application/json"}''::jsonb, 60000)');
    end if;
  end if;
exception when others then
  raise notice 'Ménage des discussions non programmé (%)', sqlerrm;
end $$;
