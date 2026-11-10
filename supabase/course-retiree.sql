-- =========================================================
-- BIZZOO 3.80.0 — Une course remise par l'administration se retire
--
--   Quand l'administration mettait une commande « Remise au client » (ou
--   l'annulait, la confiait ou la mettait en livraison) sans passer par
--   un livreur, la demande de course restait chez les livreurs — non
--   lue, qui sonne — et l'écran des commandes affichait encore « En
--   attente d'un livreur ». Désormais la course se retire d'elle-même :
--   demandes lues, cascade arrêtée, « Course retirée » aux livreurs
--   alertés, et plus d'attente affichée. Les demandes restées ouvertes
--   sont fermées.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- (3.80.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;
grant execute on function public.boutique_du_compte() to authenticated;

create or replace function public.peut_agir_sur(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.est_compte_enseigne()
      or (public.est_equipe() and cible is not null
          and cible = public.boutique_du_compte());
$$;
grant execute on function public.peut_agir_sur(text) to authenticated;

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

create or replace function public.course_a_prendre(commande text)
returns int
language plpgsql stable security definer set search_path = public as $$
declare c record;
begin
  select c0.etat, c0.paye_le into c from public.commandes c0 where c0.id = commande;
  if not found or c.etat <> 'payee' then return 0; end if;
  if not exists (select 1 from public.commande_lignes l
                  where l.commande_id = commande and l.etat <> 'annulee') then
    return 0;
  end if;
  if exists (select 1 from public.commande_lignes l
              where l.commande_id = commande and l.etat <> 'annulee'
                and (l.livreur_id is not null or l.etat in ('en_livraison', 'remise'))) then
    return -1;
  end if;
  if c.paye_le is null or c.paye_le <= now() - interval '7 days' then return 0; end if;
  return 1;
end $$;
revoke all on function public.course_a_prendre(text) from public, anon, authenticated;

create or replace function public.livraison_des_commandes(cibles text[])
returns table (commande_id text, boutique_id text,
               livreur_nom text, livreur_tel text, livreur_bizzoo boolean, recu_le timestamptz,
               refus_nom text, refus_motif text, refuse_le timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or not (public.est_equipe() or public.est_compte_enseigne()) then return; end if;
  return query
    select x.commande_id, x.boutique_id,
           coalesce(nullif(p.nom, ''), p.email, '')::text, coalesce(p.tel, '')::text,
           (p.id is not null and p.boutique_id is null), x.recu,
           coalesce(nullif(q.nom, ''), q.email, '')::text, coalesce(r.motif, '')::text, r.refuse_le
      from (select l.commande_id, l.boutique_id,
                   (array_agg(l.livreur_id) filter (where l.livreur_id is not null and l.etat <> 'annulee'))[1] as livreur,
                   min(l.recu_le) as recu
              from public.commande_lignes l
             where l.commande_id = any(cibles)
               and public.peut_agir_sur(l.boutique_id)
             group by l.commande_id, l.boutique_id
             -- (3.80.0) Remise (ou annulée) sans livreur — l'administration
             -- l'a remise elle-même : il n'y a plus de livreur à attendre.
             having bool_or(l.etat not in ('remise', 'annulee'))
                 or bool_or(l.livreur_id is not null)) x
      left join public.profils p on p.id = x.livreur
      left join lateral (select rc.livreur_id, rc.motif, rc.refuse_le from public.refus_courses rc
                          where rc.commande_id = x.commande_id and rc.boutique_id = x.boutique_id
                          order by rc.refuse_le desc limit 1) r on true
      left join public.profils q on q.id = r.livreur_id;
end $$;
revoke all on function public.livraison_des_commandes(text[]) from public, anon;
grant execute on function public.livraison_des_commandes(text[]) to authenticated;

-- ---------- (3.80.0) Une course qui n'est plus à prendre se retire ----------
-- L'administration peut faire avancer une commande elle-même : « En
-- livraison », « Remise au client », l'annuler, ou la confier à un
-- livreur précis. Avant, les livreurs alertés gardaient la demande (non
-- lue, qui sonne sur le téléphone), et la cascade continuait. Désormais,
-- dès qu'une commande n'est plus à prendre (course_a_prendre ≠ 1) : les
-- demandes non lues passent « lues », la cascade s'arrête, et chaque
-- livreur alerté reçoit « Course retirée » — sa sonnerie s'arrête, son
-- téléphone retire l'alerte. Celui qui porte la course n'en reçoit pas.
create or replace function public.retirer_course_close() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  qui    uuid[];
  numero text;
  pourquoi text;
begin
  -- « Commande reçue » sur une demande : prendre_course prévient lui-même
  -- les autres (« Déjà pris par … »).
  if coalesce(current_setting('bizzoo.prise', true), '') = 'oui' then
    return null;
  end if;
  if public.course_a_prendre(new.commande_id) = 1 then
    return null;
  end if;
  qui := array(select distinct n.destinataire from public.notifications n
                where n.commande_id = new.commande_id and n.type = 'course_proposee'
                  and n.lue_le is null
                  and n.destinataire not in (select l.livreur_id from public.commande_lignes l
                                              where l.commande_id = new.commande_id
                                                and l.livreur_id is not null));
  update public.notifications n set lue_le = now()
   where n.commande_id = new.commande_id and n.type = 'course_proposee' and n.lue_le is null;
  update public.courses_cascade k set prochaine = null
   where k.commande_id = new.commande_id and k.prochaine is not null;
  if array_length(qui, 1) is null then
    return null;
  end if;
  select c.numero into numero from public.commandes c where c.id = new.commande_id;
  pourquoi := case when old.etat is not distinct from new.etat then 'confiée à un autre livreur'
                   when new.etat = 'remise' then 'remise au client par BIZZOO'
                   when new.etat = 'annulee' then 'annulée'
                   else 'déjà en route' end;
  perform public.notifier(qui, 'course_retiree', 'Course retirée',
    'Commande ' || coalesce(numero, '') || ' : ' || pourquoi || '. Elle n''est plus disponible.',
    '#/livraisons', new.commande_id, null, false);
  return null;
end $$;
revoke all on function public.retirer_course_close() from public, anon, authenticated;

drop trigger if exists lignes_course_retiree on public.commande_lignes;
create trigger lignes_course_retiree
  after update of etat, livreur_id on public.commande_lignes
  for each row
  when ((new.etat in ('en_livraison', 'remise', 'annulee') and old.etat is distinct from new.etat)
        or (old.livreur_id is null and new.livreur_id is not null))
  execute function public.retirer_course_close();

-- Les demandes restées ouvertes sur des commandes qui ne sont plus à prendre.
update public.notifications n set lue_le = now()
 where n.type = 'course_proposee' and n.lue_le is null
   and public.course_a_prendre(n.commande_id) <> 1;
