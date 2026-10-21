-- =========================================================
-- BIZZOO 3.59.0 — « Déjà pris par … »
--
-- Une course proposée à plusieurs livreurs — une livraison groupée, à
-- tous les livreurs de BIZZOO : dès que l'un la prend, les autres
-- reçoivent « Déjà pris par <son nom> » en temps réel, leur sonnerie
-- s'arrête, et leur demande passe lue. Celui qui arrive trop tard lit le
-- nom de celui qui l'a prise.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- À coller APRÈS admin-boutique-comptes.sql.
-- =========================================================

-- « Commande reçue » : le premier qui touche prend TOUTE la commande —
-- toutes ses boutiques en livraison groupée. Le verrou sur la commande
-- range les livreurs en file : le second trouve la course déjà prise.
-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
create or replace function public.candidats_course(commande text)
returns uuid[]
language plpgsql stable security definer set search_path = public as $$
declare
  boutiques text[];
  qui       uuid[];
begin
  select array_agg(distinct l.boutique_id) into boutiques
    from public.commande_lignes l
   where l.commande_id = commande and l.etat <> 'annulee' and l.boutique_id is not null;
  if boutiques is null then return '{}'; end if;
  if array_length(boutiques, 1) = 1 then
    select array_agg(p.id order by p.id) into qui
      from public.profils p
     where p.role = 'livreur' and p.actif and p.boutique_id = boutiques[1]
       and exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id);
    if qui is not null then return qui; end if;
  end if;
  select array_agg(p.id order by p.id) into qui
    from public.profils p
   where p.role = 'livreur' and p.actif and p.boutique_id is null
     and exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id);
  return coalesce(qui, '{}');
end $$;
revoke all on function public.candidats_course(text) from public, anon, authenticated;

create or replace function public.est_livreur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'livreur', false);
$$;


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


create or replace function public.prendre_course(commande text)
returns int
language plpgsql security definer set search_path = public as $$
declare
  moi     uuid := auth.uid();
  combien int;
  preneur text;
  numero  text;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Seul un livreur prend une course';
  end if;
  perform 1 from public.commandes c where c.id = commande and c.etat = 'payee' for update;
  if not found then
    raise exception 'Cette commande n''attend pas de livreur';
  end if;
  if not (moi = any(public.candidats_course(commande))) then
    raise exception 'Cette course n''est pas proposée à votre compte';
  end if;
  if exists (select 1 from public.refus_courses rc
              where rc.commande_id = commande and rc.livreur_id = moi) then
    raise exception 'Vous avez refusé cette course.' using errcode = 'P0001';
  end if;
  -- (3.59.0) On dit QUI l'a prise.
  select coalesce(nullif(p.nom, ''), 'un autre livreur') into preneur
    from public.commande_lignes l join public.profils p on p.id = l.livreur_id
   where l.commande_id = commande and l.etat <> 'annulee' and l.livreur_id is not null
   limit 1;
  if preneur is not null then
    raise exception 'Déjà pris par %.', preneur using errcode = 'P0001';
  end if;

  perform set_config('bizzoo.livraison', 'oui', true);
  perform set_config('bizzoo.prise', 'oui', true);
  update public.commande_lignes l
     set livreur_id = moi, recu_le = now()
   where l.commande_id = commande
     and l.livreur_id is null
     and l.etat in ('nouvelle', 'vue', 'preparee');
  get diagnostics combien = row_count;
  perform set_config('bizzoo.prise', '', true);
  perform set_config('bizzoo.livraison', '', true);
  if combien = 0 then
    raise exception 'Trop tard : un autre livreur a déjà pris cette course.'
      using errcode = 'P0001';
  end if;

  -- (3.59.0) LES AUTRES SONT PRÉVENUS TOUT DE SUITE : « Déjà pris par … ».
  -- La nouvelle arrive en temps réel sur leur téléphone, et leur
  -- sonnerie s'arrête. Leur demande d'avant passe « lue ».
  select coalesce(nullif(p.nom, ''), 'un autre livreur') into preneur
    from public.profils p where p.id = moi;
  select c.numero into numero from public.commandes c where c.id = commande;
  update public.notifications n
     set lue_le = now()
   where n.commande_id = commande and n.type = 'course_proposee'
     and n.destinataire <> moi and n.lue_le is null;
  perform public.notifier(
    array(select x from unnest(public.candidats_course(commande)) as x where x <> moi),
    'course_prise',
    'Déjà pris par ' || preneur,
    'Commande ' || coalesce(numero, '') || ' — ' || preneur || ' a pris la course. Elle n''est plus disponible.',
    '#/livraisons', commande, null, false);
  return combien;
end $$;
revoke all on function public.prendre_course(text) from public, anon;
grant execute on function public.prendre_course(text) to authenticated;
