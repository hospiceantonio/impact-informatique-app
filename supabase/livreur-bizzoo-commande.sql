-- =========================================================
-- BIZZOO 3.59.0 — Le livreur de BIZZOO porte toute la commande
--
--   1. confiée à un livreur de BIZZOO, la course lui donne TOUS les
--      produits de la commande — ceux des autres boutiques aussi, sauf
--      une part déjà confiée au livreur d'une autre boutique ; les autres
--      boutiques sont prévenues qu'il passe chez elles ;
--   2. il accepte d'un seul « Commande reçue » toute la commande ; le
--      client reçoit une seule nouvelle ;
--   3. confiée au livreur d'une boutique : les produits de CETTE
--      boutique seulement, comme avant.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- À coller APRÈS refus-course.sql.
-- =========================================================

-- ---------- Confier une livraison ----------
-- LA BOUTIQUE CONFIE, à SON livreur ou à CELUI DE BIZZOO. Confier à
-- celui de la boutique d'à côté reste refusé : ce serait lui remettre
-- le nom, le numéro et l'adresse d'un client qui n'est pas le sien.
-- Un livreur de BIZZOO, lui, porte pour toute l'enseigne — c'est
-- exactement ce qu'on a voulu en ne le rattachant à aucune boutique.
--
-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;



create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;


create or replace function public.equipe_de(cible text) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and cible is not null and p.boutique_id = cible
     and p.role in ('administrateur', 'moderateur');
$$;


create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false)
     and public.role_courant() is not null;
$$;


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

create or replace function public.peut_agir_sur(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.est_compte_enseigne()
      or (public.est_equipe() and cible is not null
          and cible = public.boutique_du_compte());
$$;


-- (3.59.0) LE LIVREUR DE BIZZOO PORTE TOUTE LA COMMANDE : confié par une
-- boutique, il reçoit aussi les produits des autres boutiques de la
-- commande — ceux qu'aucun autre livreur ne porte déjà. Le livreur d'une
-- boutique, lui, ne reçoit que les produits de SA boutique.
create or replace function public.assigner_livreur(
  commande text, boutique text, livreur uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  combien  int;
  autres   int := 0;
  rang     text;
  bizzoo   boolean := false;
  numero   text;
  b        record;
begin
  if not public.peut_agir_sur(boutique) then
    raise exception 'Cette commande ne concerne pas votre boutique';
  end if;

  -- « livreur » nul : on retire l'attribution. Une boutique doit pouvoir
  -- reprendre une course confiée par erreur.
  if livreur is not null then
    select p.role, (p.boutique_id is null) into rang, bizzoo from public.profils p
     where p.id = livreur and p.actif
       and (public.est_super()
            or public.est_compte_enseigne()
            -- Le livreur de BIZZOO : aucune boutique, donc toutes.
            or p.boutique_id is null
            or p.boutique_id = public.boutique_du_compte());
    if rang is distinct from 'livreur' then
      raise exception 'Ce compte n''est pas un livreur de votre boutique ni de BIZZOO';
    end if;
    -- UN LIVREUR VALIDE SON COMPTE EN ENREGISTRANT SA POSITION. Tant
    -- qu'il ne l'a pas fait, on ne lui confie rien.
    if not exists (select 1 from public.positions_livreurs pl where pl.profil_id = livreur) then
      raise exception 'Ce livreur n''a pas encore validé son compte : il doit ouvrir BIZZOO Admin et enregistrer sa position.'
        using errcode = 'P0001';
    end if;
  end if;

  perform set_config('bizzoo.livraison', 'oui', true);
  update public.commande_lignes l
     set livreur_id = livreur,
         -- Un autre livreur doit accepter à son tour (3.59.0).
         recu_le = case when l.livreur_id is distinct from livreur then null else l.recu_le end
   where l.commande_id = commande
     and l.boutique_id = boutique
     -- (3.59.0) En secours de la demande envoyée à tous les livreurs : la
     -- boutique peut confier dès le paiement, sans attendre le colis.
     and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')
     and exists (select 1 from public.commandes c where c.id = l.commande_id and c.etat = 'payee');
  get diagnostics combien = row_count;

  -- LE LIVREUR DE BIZZOO : les produits des autres boutiques aussi. Sans
  -- prendre une part déjà confiée au livreur d'une autre boutique.
  if bizzoo and combien > 0 then
    update public.commande_lignes l
       set livreur_id = livreur, recu_le = null
     where l.commande_id = commande
       and l.boutique_id <> boutique
       and l.livreur_id is null
       and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison');
    get diagnostics autres = row_count;
  end if;
  perform set_config('bizzoo.livraison', '', true);

  if combien = 0 then
    raise exception 'Rien à confier ici : la commande n''est pas encore payée, ou elle est déjà livrée.';
  end if;

  -- Les autres boutiques le savent : un livreur BIZZOO passera chez elles.
  if autres > 0 then
    select c.numero into numero from public.commandes c where c.id = commande;
    for b in select distinct l.boutique_id as id from public.commande_lignes l
              where l.commande_id = commande and l.boutique_id <> boutique and l.livreur_id = livreur
    loop
      perform public.notifier(public.equipe_de(b.id), 'course_confiee',
        'Un livreur BIZZOO passe récupérer vos produits',
        'Commande ' || coalesce(numero, '') || ' — il livre toute la commande. Préparez le colis.',
        '#/commandes/' || commande, commande, b.id, true);
    end loop;
  end if;
  return combien + autres;
end $$;
revoke all on function public.assigner_livreur(text, text, uuid) from public, anon;
grant execute on function public.assigner_livreur(text, text, uuid) to authenticated;

-- ---------- « Reçu » : le livreur accepte la course (3.59.0) ----------
-- Le client est alors prévenu, avec le nom et le numéro de son livreur ;
-- la boutique aussi. Seulement SES courses, et une seule fois.
-- Le livreur de BIZZOO accepte d'un coup TOUTE la commande qu'il porte :
-- une seule nouvelle au client.
create or replace function public.accepter_course(commande text, boutique text)
returns int
language plpgsql security definer set search_path = public as $$
declare
  moi     uuid := auth.uid();
  combien int;
  bizzoo  boolean;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Cette course ne vous est pas confiée';
  end if;
  select (p.boutique_id is null) into bizzoo from public.profils p where p.id = moi;
  perform set_config('bizzoo.livraison', 'oui', true);
  if coalesce(bizzoo, false) then
    perform set_config('bizzoo.prise', 'oui', true);
  end if;
  update public.commande_lignes l
     set recu_le = now()
   where l.commande_id = commande
     and (l.boutique_id = boutique or coalesce(bizzoo, false))
     and l.livreur_id = moi
     and l.recu_le is null
     -- (3.59.0) Dès le paiement : la course s'accepte avant que le colis
     -- soit prêt.
     and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison');
  get diagnostics combien = row_count;
  perform set_config('bizzoo.livraison', '', true);
  perform set_config('bizzoo.prise', '', true);
  if combien = 0 and not exists (
       select 1 from public.commande_lignes l
        where l.commande_id = commande and l.boutique_id = boutique
          and l.livreur_id = moi and l.recu_le is not null) then
    raise exception 'Cette course ne vous est pas confiée';
  end if;
  return combien;
end $$;
revoke all on function public.accepter_course(text, text) from public, anon;
grant execute on function public.accepter_course(text, text) to authenticated;
