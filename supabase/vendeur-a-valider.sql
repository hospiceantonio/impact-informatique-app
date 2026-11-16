-- =========================================================
-- BIZZOO 4.5.0 — L'administrateur de BIZZOO crée un vendeur sur place ;
-- le superadministrateur le valide
--
--   L'administrateur de BIZZOO crée le vendeur chez lui : son compte, son
--   lieu (nom du commerce, numéro, adresse, sa position — « je suis chez
--   lui » —, ses horaires). Le vendeur naît INACTIF, « à valider » ; le
--   superadministrateur, prévenu, vérifie et l'active. Tant qu'il attend,
--   l'administrateur qui l'a créé peut encore corriger son lieu.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- Les colonnes que ces fonctions lisent et écrivent : un fichier qui pose
-- une fonction pose aussi les colonnes qu'elle touche.
-- (4.1.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;
revoke all on function public.est_equipe() from public, anon, authenticated;
grant execute on function public.est_equipe() to authenticated;

create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false)
     and public.role_courant() is not null;
$$;
revoke all on function public.est_compte_enseigne()  from public, anon;
grant execute on function public.est_compte_enseigne() to authenticated;

create or replace function public.ouvertures_valides(o jsonb) returns boolean
language sql immutable set search_path = public as $$
  select jsonb_typeof(o) = 'object'
     and not exists (select 1 from jsonb_object_keys(o) k
                      where k not in ('lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'))
     and not exists (
       select 1 from jsonb_each(o) j
        where jsonb_typeof(j.value) not in ('null', 'object')
           or (jsonb_typeof(j.value) = 'object' and not (
                length(coalesce(j.value ->> 'de', '')) = 5
            and (j.value ->> 'de') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]'
            and length(coalesce(j.value ->> 'a', '')) = 5
            and ((j.value ->> 'a') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]' or (j.value ->> 'a') = '24:00')
            and (j.value ->> 'de') < (j.value ->> 'a'))))
     and exists (select 1 from jsonb_each(o) j where jsonb_typeof(j.value) = 'object');
$$;
grant execute on function public.ouvertures_valides(jsonb) to anon, authenticated;

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

create or replace function public.nom_du_createur(qui uuid)
returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(trim(p.nom), ''), nullif(p.email, ''), 'compte inconnu')
         || ' (' || p.role || ')'
    from public.profils p
   where p.id = qui;
$$;
revoke all on function public.nom_du_createur(uuid) from public, anon, authenticated;

create or replace function public.lieu_vendeur(cible uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l public.vendeurs_lieux%rowtype;
begin
  if auth.uid() is null or not (public.est_super() or public.est_equipe() or auth.uid() = cible) then
    raise exception 'Réservé à l''équipe.' using errcode = 'P0001';
  end if;
  select * into l from public.vendeurs_lieux where vendeur_id = cible;
  return jsonb_build_object('nom', coalesce(l.nom, ''), 'tel', coalesce(l.tel, ''),
    'indicatif', coalesce(l.indicatif, '229'), 'adresse', coalesce(l.adresse, ''),
    'latitude', l.latitude, 'longitude', l.longitude, 'ouvertures', l.ouvertures,
    'connu', found);
end $$;
revoke all on function public.lieu_vendeur(uuid) from public, anon;
grant execute on function public.lieu_vendeur(uuid) to authenticated;

create or replace function public.les_superadmins() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.role = 'superadministrateur';
$$;
revoke all on function public.les_superadmins()          from public, anon, authenticated;

create or replace function public.est_admin_bizzoo() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'administrateur', false)
     and public.est_compte_enseigne();
$$;
revoke all on function public.est_admin_bizzoo() from public, anon;
grant execute on function public.est_admin_bizzoo() to authenticated;

alter table public.profils add column if not exists boutique_id text references public.boutiques(id) on delete set null;
alter table public.profils add column if not exists nom text not null default '';
alter table public.profils add column if not exists tel text not null default '';
alter table public.profils add column if not exists a_valider boolean not null default false;
alter table public.profils add column if not exists cree_par uuid;

create or replace function public.profil_validation() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  nouveau boolean;
begin
  if coalesce(current_setting('bizzoo.compte', true), '') = 'oui' then
    return new;
  end if;

  -- (4.5.0) Le vendeur aussi : l'administrateur de BIZZOO le crée sur
  -- place, avec son lieu ; le superadministrateur le valide.
  if public.est_admin_bizzoo() and new.role in ('moderateur', 'vendeur') then
    new.actif := false;
    new.a_valider := true;
    -- L'écran pose le rang par « insert … on conflict » : PostgreSQL exige
    -- alors que la ligne PROPOSÉE soit lisible par son auteur, et elle ne
    -- l'est que par son créateur. Sur une fiche qui n'en a pas encore, il
    -- l'est ; « profil_trace » en fera autant sur la mise à jour.
    if tg_op = 'INSERT' and new.cree_par is null then
      new.cree_par := auth.uid();
    end if;
    -- Une insertion qui vise une fiche existante finira en mise à jour
    -- (« on conflict ») : on ne prévient qu'une fois, sur la mise à jour.
    nouveau := case when tg_op = 'INSERT'
                    then not exists (select 1 from public.profils p where p.id = new.id)
                    else not old.a_valider end;
    -- Le vendeur a sa propre notification (« profil_vendeur_cree »).
    if nouveau and new.role = 'moderateur' then
      perform public.notifier(public.les_superadmins(), 'compte_a_valider',
        'Un compte modérateur à valider',
        coalesce(nullif(trim(new.nom), ''), nullif(new.email, ''), 'Un nouveau compte') ||
          ', créé par ' || coalesce(public.nom_du_createur(auth.uid()), 'un administrateur de BIZZOO') ||
          '. Activez-le dans Comptes pour le valider.',
        '#/comptes/' || new.id, null, null, false);
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.a_valider := false;
    return new;
  end if;

  if public.est_super() then
    -- Activer, c'est valider.
    new.a_valider := old.a_valider and not new.actif;
    if old.a_valider and not new.a_valider and old.cree_par is not null then
      perform public.notifier(array[old.cree_par], 'compte_valide',
        'Compte validé',
        coalesce(nullif(trim(new.nom), ''), nullif(new.email, ''), 'Le compte') ||
          ' a été validé : il peut travailler.',
        '#/comptes/' || new.id, null, null, false);
    end if;
  else
    new.a_valider := old.a_valider;
    if old.a_valider then new.actif := false; end if;
  end if;
  return new;
end $$;
drop trigger if exists profils_validation on public.profils;
create trigger profils_validation
  before insert or update on public.profils
  for each row execute function public.profil_validation();

create or replace function public.profil_vendeur_cree() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.role is distinct from 'vendeur' or public.est_super() or not public.est_admin_bizzoo() then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.role = 'vendeur' then
    return new;
  end if;
  if tg_op = 'UPDATE' and not (old.role = 'moderateur' and not old.actif and old.boutique_id is null
                              and not coalesce(old.a_valider, false)
                              and old.cree_le > now() - interval '15 minutes') then
    raise exception 'L''administrateur de BIZZOO crée un vendeur ; il ne change pas un compte existant en vendeur.'
      using errcode = 'P0001';
  end if;
  new.boutique_id := null;
  -- Une insertion qui vise une fiche existante finit en mise à jour
  -- (« on conflict ») : on ne prévient qu'une fois.
  if tg_op = 'UPDATE' or not exists (select 1 from public.profils p where p.id = new.id) then
    -- (4.5.0) Il naît INACTIF (« profil_validation ») : son lieu est posé
    -- sur place par l'administrateur ; le superadministrateur le valide.
    perform public.notifier(public.les_superadmins(), 'vendeur_cree', 'Un vendeur à valider',
      coalesce(nullif(trim(new.nom), ''), nullif(trim(new.tel), ''), 'Un vendeur') || ', créé par ' ||
        coalesce(public.nom_du_createur(auth.uid()), 'un administrateur de BIZZOO') ||
        '. Vérifiez son lieu, puis activez-le pour le valider.',
      '#/vendeurs/' || new.id, null, null, false);
  end if;
  return new;
end $$;
revoke all on function public.profil_vendeur_cree() from public, anon, authenticated;

drop trigger if exists profils_vendeur_cree on public.profils;
create trigger profils_vendeur_cree
  before insert or update on public.profils
  for each row execute function public.profil_vendeur_cree();

create or replace function public.enregistrer_lieu_vendeur(cible uuid, lieu jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  lat double precision;
  lng double precision;
  o   jsonb := case when jsonb_typeof(lieu -> 'ouvertures') = 'object' then lieu -> 'ouvertures' end;
  t   text := regexp_replace(coalesce(lieu ->> 'tel', ''), '\D', '', 'g');
  ind text := coalesce(nullif(regexp_replace(coalesce(lieu ->> 'indicatif', ''), '\D', '', 'g'), ''), '229');
begin
  -- (4.5.0) Le superadministrateur ; ou l'administrateur de BIZZOO qui a
  -- créé ce vendeur sur place, tant que le superadministrateur ne l'a pas
  -- validé.
  if auth.uid() is null or not (public.est_super() or (public.est_admin_bizzoo() and exists (
       select 1 from public.profils p
        where p.id = cible and p.role = 'vendeur' and p.a_valider and p.cree_par = auth.uid()))) then
    raise exception 'Le lieu d''un vendeur est réglé par le superadministrateur, ou par l''administrateur qui vient de le créer.'
      using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.profils p where p.id = cible and p.role = 'vendeur') then
    raise exception 'Ce compte n''est pas un vendeur.' using errcode = 'P0001';
  end if;
  if lieu is null or jsonb_typeof(lieu) <> 'object' then
    raise exception 'Lieu illisible.' using errcode = 'P0001';
  end if;
  begin
    lat := nullif(lieu ->> 'latitude', '')::double precision;
    lng := nullif(lieu ->> 'longitude', '')::double precision;
  exception when others then
    raise exception 'Position illisible : posez-la sur la carte.' using errcode = 'P0001';
  end;
  if (lat is null) <> (lng is null) or (lat is not null and (lat not between -90 and 90
       or lng not between -180 and 180 or (lat = 0 and lng = 0))) then
    raise exception 'Position illisible : posez-la sur la carte.' using errcode = 'P0001';
  end if;
  if length(t) > 20 then
    raise exception 'Numéro du vendeur : 20 chiffres au plus.' using errcode = 'P0001';
  end if;
  if length(btrim(coalesce(lieu ->> 'adresse', ''))) > 300 then
    raise exception 'Adresse du vendeur : 300 caractères au plus.' using errcode = 'P0001';
  end if;
  if length(btrim(coalesce(lieu ->> 'nom', ''))) > 120 then
    raise exception 'Nom du commerce : 120 caractères au plus.' using errcode = 'P0001';
  end if;
  if o is not null and not public.ouvertures_valides(o) then
    raise exception 'Horaires du vendeur illisibles : un jour ouvert au moins, l''ouverture avant la fermeture.'
      using errcode = 'P0001';
  end if;
  insert into public.vendeurs_lieux as v (vendeur_id, nom, tel, indicatif, adresse, latitude, longitude, ouvertures, maj_le)
  values (cible, btrim(coalesce(lieu ->> 'nom', '')), t, left(ind, 4), btrim(coalesce(lieu ->> 'adresse', '')),
          lat, lng, o, now())
  on conflict (vendeur_id) do update
    set nom = excluded.nom, tel = excluded.tel, indicatif = excluded.indicatif, adresse = excluded.adresse,
        latitude = excluded.latitude, longitude = excluded.longitude, ouvertures = excluded.ouvertures,
        maj_le = now();
  return public.lieu_vendeur(cible);
end $$;
revoke all on function public.enregistrer_lieu_vendeur(uuid, jsonb) from public, anon;
grant execute on function public.enregistrer_lieu_vendeur(uuid, jsonb) to authenticated;
