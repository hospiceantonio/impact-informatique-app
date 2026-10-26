-- =========================================================
-- BIZZOO Personnel : à qui l'on écrit
--
-- Trois façons d'écrire, ouvertes à tout employé qui a les discussions :
--   - un message PRIVÉ à n'importe quel autre employé en poste (avant :
--     seulement son profil, son responsable et l'administration) ;
--   - un message dans le fil d'un PROFIL, le sien ou un autre ; qui écrit
--     à un autre profil en lit ensuite le fil, pour voir les réponses ;
--   - un message à TOUT LE MONDE, dans le fil général que tous lisent.
-- Un message privé reste privé : l'administration ne le lit pas.
-- =========================================================

-- Le fil général, « Tout le monde » : un message n'a alors ni profil ni
-- destinataire. Une et une seule cible : un profil, une personne, ou tous.
alter table public.rh_messages add column if not exists general boolean not null default false;
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'rh_messages_une_cible'
               and pg_get_constraintdef(oid) not like '%general%') then
    alter table public.rh_messages drop constraint rh_messages_une_cible;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_messages_une_cible') then
    alter table public.rh_messages add constraint rh_messages_une_cible
      check (num_nonnulls(profil_id, destinataire_id) + case when general then 1 else 0 end = 1);
  end if;
end $$;
create index if not exists rh_messages_general on public.rh_messages (id) where general;

-- ---------- Ce qui change (copies de schema.sql) ----------

create or replace function public.rh_mon_profil() returns uuid
language sql stable security definer set search_path = public as $$
  select profil_id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_responsable_de(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select cible is not null and exists (
    select 1 from public.rh_profils p
     where p.id = cible and p.responsable_id is not null
       and p.responsable_id = public.rh_moi());
$$;

create or replace function public.rh_membre_de(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select cible is not null
     and (public.rh_mon_profil() = cible or public.rh_responsable_de(cible));
$$;

create or replace function public.rh_moi() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_est_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and (administration or ceo));
$$;

create or replace function public.rh_acces(cible uuid, cle text) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rh_est_admin() then
    return true;
  end if;
  if cible is null or public.rh_moi() is null then
    return false;
  end if;
  if to_regclass('public.rh_acces_menus') is null then
    return public.rh_membre_de(cible);
  end if;
  return exists (
    select 1 from public.rh_acces_menus a
     where a.profil_id = cible and a.menu = cle
       and (public.rh_responsable_de(cible)
            or (a.qui = 'membres' and public.rh_mon_profil() = cible)));
end $$;

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

create or replace function public.rh_peut_ecrire_a(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.rh_moi() is not null and cible <> public.rh_moi() and exists (
    select 1 from public.rh_employes c where c.id = cible and c.etat = 'actif');
$$;

create or replace function public.rh_a_ecrit_dans(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.rh_moi() is not null and exists (
    select 1 from public.rh_messages m where m.profil_id = cible and m.auteur_id = public.rh_moi());
$$;

create or replace function public.rh_marquer_lu(conversation text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.rh_moi() is null then
    raise exception 'Seul un employé en poste lit ses messages';
  end if;
  if conversation !~ '^([pd]:[0-9a-f-]{36}|g:tous)\Z' then
    raise exception 'Discussion inconnue';
  end if;
  insert into public.rh_lectures (employe_id, conversation, lu_le)
  values (public.rh_moi(), conversation, now())
  on conflict on constraint rh_lectures_pkey do update set lu_le = excluded.lu_le;
end $$;

create or replace function public.rh_conversations()
returns table (cle text, genre text, cible uuid, titre text, dernier_texte text,
               dernier_le timestamptz, non_lus int)
language sql stable security definer set search_path = public as $$
  with moi as (select public.rh_moi() as id, public.rh_est_admin() as admin),
  groupes as (
    select 'p:' || p.id as cle, 'profil'::text as genre, p.id as cible, p.nom as titre
      from public.rh_profils p, moi
     where moi.id is not null
       and (moi.admin or public.rh_acces(p.id, 'discussions')
            or (public.rh_menu_ouvert('discussions') and public.rh_a_ecrit_dans(p.id)))
  ),
  -- « Tout le monde » : tous les employés qui ont les discussions.
  general as (
    select 'g:tous' as cle, 'general'::text as genre, null::uuid as cible, 'Tout le monde' as titre
      from moi where moi.id is not null and public.rh_menu_ouvert('discussions')
  ),
  personnes as (
    select distinct case when m.auteur_id = moi.id then m.destinataire_id else m.auteur_id end as autre
      from public.rh_messages m, moi
     where m.destinataire_id is not null and (m.auteur_id = moi.id or m.destinataire_id = moi.id)
       and public.rh_menu_ouvert('discussions')
  ),
  prives as (
    select 'd:' || e.id as cle, 'personne'::text as genre, e.id as cible,
           btrim(e.prenoms || ' ' || e.nom) as titre
      from personnes x join public.rh_employes e on e.id = x.autre
  ),
  toutes as (select * from general union all select * from groupes union all select * from prives)
  select t.cle, t.genre, t.cible, t.titre, d.texte, d.cree_le,
         (select count(*)::int from public.rh_messages m, moi
           where m.auteur_id <> moi.id
             and m.cree_le > coalesce((select l.lu_le from public.rh_lectures l
                                        where l.employe_id = moi.id and l.conversation = t.cle),
                                      '-infinity')
             and ((t.genre = 'profil' and m.profil_id = t.cible)
               or (t.genre = 'general' and m.general)
               or (t.genre = 'personne' and m.auteur_id = t.cible and m.destinataire_id = moi.id)))
    from toutes t
    left join lateral (
      select m.texte, m.cree_le from public.rh_messages m, moi
       where (t.genre = 'profil' and m.profil_id = t.cible)
          or (t.genre = 'general' and m.general)
          or (t.genre = 'personne' and ((m.auteur_id = t.cible and m.destinataire_id = moi.id)
                                     or (m.auteur_id = moi.id and m.destinataire_id = t.cible)))
       order by m.id desc limit 1) d on true
   order by t.genre = 'general' desc, d.cree_le desc nulls last, t.titre;
$$;

revoke all on function public.rh_a_ecrit_dans(uuid) from public, anon;
grant execute on function public.rh_a_ecrit_dans(uuid) to authenticated, service_role;

-- ---------- Les règles ----------
drop policy if exists "rh messages lecture" on public.rh_messages;
drop policy if exists "rh messages envoi" on public.rh_messages;
-- Un message privé reste privé : l'administration lit les discussions
-- de tous les profils, pas les messages entre deux personnes.
create policy "rh messages lecture" on public.rh_messages
  for select to authenticated using (
    (profil_id is not null and (public.rh_acces(profil_id, 'discussions')
      or (public.rh_menu_ouvert('discussions') and public.rh_a_ecrit_dans(profil_id))))
    or (general and public.rh_menu_ouvert('discussions'))
    or (destinataire_id is not null
        and (auteur_id = public.rh_moi() or destinataire_id = public.rh_moi())
        and public.rh_menu_ouvert('discussions')));
create policy "rh messages envoi" on public.rh_messages
  for insert to authenticated with check (
    (profil_id is not null and (public.rh_acces(profil_id, 'discussions') or public.rh_menu_ouvert('discussions')))
    or (general and public.rh_menu_ouvert('discussions'))
    or (destinataire_id is not null and public.rh_peut_ecrire_a(destinataire_id)
        and public.rh_menu_ouvert('discussions')));

