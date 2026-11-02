-- =========================================================
-- BIZZOO 3.73.0 — « Numéro de réception » mène à la bonne fiche
--
--   La notification « Numéro de réception d'un livreur » (ou d'un
--   vendeur, ou d'une boutique) menait à l'écran des reversements : on y
--   lisait la demande en attente d'un autre, sans rapport avec la
--   personne. Elle mène désormais :
--     - pour un livreur, à sa fiche (son numéro de réception y est) ;
--     - pour un vendeur, à son espace ;
--     - pour une boutique, à son solde.
--   Les notifications déjà reçues sont redirigées par l'application.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;
grant execute on function public.boutique_du_compte() to authenticated;

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.est_livreur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'livreur', false);
$$;
revoke all on function public.est_livreur() from public, anon, authenticated;
grant execute on function public.est_livreur() to authenticated;

create or replace function public.est_vendeur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'vendeur', false);
$$;
revoke all on function public.est_vendeur() from public, anon;
grant execute on function public.est_vendeur() to authenticated;

create or replace function public.gere_les_fonds(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or (public.est_admin() and cible is not null and cible = public.boutique_du_compte());
$$;
revoke all on function public.gere_les_fonds(text) from public, anon, authenticated;
grant execute on function public.gere_les_fonds(text) to authenticated;

create or replace function public.les_superadmins() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.role = 'superadministrateur';
$$;
revoke all on function public.les_superadmins()          from public, anon, authenticated;

create or replace function public.nom_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select coalesce(nullif(p.nom, ''), nullif(p.email, ''), 'l''équipe')
                     from public.profils p where p.id = auth.uid()), '');
$$;
revoke all on function public.nom_du_compte() from public, anon, authenticated;

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

create or replace function public.regler_reception(cible text, tel text, reseau text, titulaire text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  national text := regexp_replace(coalesce(tel, ''), '\D', '', 'g');
  res      text := upper(coalesce(reseau, ''));
  qui      text := public.nom_du_compte();
begin
  if not public.gere_les_fonds(cible) then
    raise exception 'Seul l''administrateur de la boutique règle son numéro de réception.';
  end if;
  national := regexp_replace(national, '^229', '');
  if length(national) = 8 then national := '01' || national; end if;
  if length(national) <> 10 or national !~ '^01[0-9]+' then
    raise exception 'Ce numéro n''a pas la forme d''un numéro béninois : dix chiffres commençant par 01.'
      using errcode = 'P0001';
  end if;
  if res not in ('MTN', 'MOOV', 'CELTIIS') then
    raise exception 'Choisissez le réseau du numéro : MTN, Moov ou Celtiis.' using errcode = 'P0001';
  end if;
  insert into public.boutiques_reception (boutique_id, tel, reseau, titulaire, maj_le, maj_par)
  values (cible, national, res, left(trim(coalesce(titulaire, '')), 80), now(), qui)
  on conflict (boutique_id) do update
     set tel = excluded.tel, reseau = excluded.reseau, titulaire = excluded.titulaire,
         maj_le = now(), maj_par = excluded.maj_par;
  perform public.notifier(public.les_superadmins(), 'reception_reglee',
    'Numéro de réception changé — ' || coalesce((select b.nom from public.boutiques b where b.id = cible), cible),
    qui || ' a réglé le numéro de réception : ' || res || ' ' || national ||
      coalesce(' (' || nullif(trim(coalesce(titulaire, '')), '') || ')', '') || '.',
    -- (3.73.0) Le solde de la boutique, où ce numéro se lit (plus les reversements).
    '#/solde', null, cible, false);
  return jsonb_build_object('tel', national, 'reseau', res);
end $$;
revoke all on function public.regler_reception(text, text, text, text) from public, anon;
grant execute on function public.regler_reception(text, text, text, text) to authenticated;

create or replace function public.regler_reception_livreur(tel text, reseau text, titulaire text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  moi      uuid := auth.uid();
  national text := regexp_replace(coalesce(tel, ''), '\D', '', 'g');
  res      text := upper(coalesce(reseau, ''));
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Seul un livreur règle son numéro de réception.';
  end if;
  national := regexp_replace(national, '^229', '');
  if length(national) = 8 then national := '01' || national; end if;
  if length(national) <> 10 or national !~ '^01[0-9]+' then
    raise exception 'Ce numéro n''a pas la forme d''un numéro béninois : dix chiffres commençant par 01.'
      using errcode = 'P0001';
  end if;
  if res not in ('MTN', 'MOOV', 'CELTIIS') then
    raise exception 'Choisissez le réseau du numéro : MTN, Moov ou Celtiis.' using errcode = 'P0001';
  end if;
  insert into public.livreurs_reception (livreur_id, tel, reseau, titulaire, maj_le)
  values (moi, national, res, left(trim(coalesce(titulaire, '')), 80), now())
  on conflict (livreur_id) do update
     set tel = excluded.tel, reseau = excluded.reseau, titulaire = excluded.titulaire, maj_le = now();
  perform public.notifier(public.les_superadmins(), 'reception_reglee',
    'Numéro de réception d''un livreur — ' || public.nom_du_compte(),
    public.nom_du_compte() || ' a réglé son numéro de réception : ' || res || ' ' || national ||
      coalesce(' (' || nullif(trim(coalesce(titulaire, '')), '') || ')', '') || '.',
    -- (3.73.0) Sa fiche, où ce numéro se lit — pas les reversements, où
    -- l'on tombait sur la demande d'un autre.
    '#/livreurs/' || moi, null, null, false);
  return jsonb_build_object('tel', national, 'reseau', res);
end $$;
revoke all on function public.regler_reception_livreur(text, text, text) from public, anon;
grant execute on function public.regler_reception_livreur(text, text, text) to authenticated;

create or replace function public.regler_reception_vendeur(tel text, reseau text, titulaire text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  moi      uuid := auth.uid();
  national text := regexp_replace(coalesce(tel, ''), '\D', '', 'g');
  res      text := upper(coalesce(reseau, ''));
begin
  if moi is null or not public.est_vendeur() then
    raise exception 'Seul un vendeur règle son numéro de réception.';
  end if;
  national := regexp_replace(national, '^229', '');
  if length(national) = 8 then national := '01' || national; end if;
  if length(national) <> 10 or national !~ '^01[0-9]+' then
    raise exception 'Ce numéro n''a pas la forme d''un numéro béninois : dix chiffres commençant par 01.'
      using errcode = 'P0001';
  end if;
  if res not in ('MTN', 'MOOV', 'CELTIIS') then
    raise exception 'Choisissez le réseau du numéro : MTN, Moov ou Celtiis.' using errcode = 'P0001';
  end if;
  insert into public.vendeurs_reception (vendeur_id, tel, reseau, titulaire, maj_le)
  values (moi, national, res, left(trim(coalesce(titulaire, '')), 80), now())
  on conflict (vendeur_id) do update
     set tel = excluded.tel, reseau = excluded.reseau, titulaire = excluded.titulaire, maj_le = now();
  perform public.notifier(public.les_superadmins(), 'reception_reglee',
    'Numéro de réception d''un vendeur — ' || public.nom_du_compte(),
    public.nom_du_compte() || ' a réglé son numéro de réception : ' || res || ' ' || national ||
      coalesce(' (' || nullif(trim(coalesce(titulaire, '')), '') || ')', '') || '.',
    -- (3.73.0) Son espace, où ce numéro se lit.
    '#/vendeurs/' || moi, null, null, false);
  return jsonb_build_object('tel', national, 'reseau', res);
end $$;
revoke all on function public.regler_reception_vendeur(text, text, text) from public, anon;
grant execute on function public.regler_reception_vendeur(text, text, text) to authenticated;
