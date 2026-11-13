-- =========================================================
-- BIZZOO 3.81.0 — Un reversement, c'est des commandes entières
--
--   On demande tout son solde, ou des commandes entières — jamais une
--   partie au hasard. Chaque demande (boutique, livreur, vendeur) garde
--   la liste des commandes qui composent son montant, avec la preuve de
--   chaque paiement : BIZZOO vérifie avant d'envoyer que l'argent vient
--   de vraies commandes, et non d'essais.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- =========================================================
-- (3.81.0) UN REVERSEMENT, C'EST DES COMMANDES ENTIÈRES — OU TOUT LE SOLDE
--
-- Une demande de reversement ne disait que son montant, et ce montant
-- était libre : rien ne permettait à BIZZOO de vérifier que l'argent
-- venait de vraies commandes, et non d'essais. Désormais :
--   - on demande TOUT son solde disponible, ou des COMMANDES ENTIÈRES
--     (« demander_reversement_commandes ») — jamais une partie au hasard ;
--   - chaque demande (boutique, livreur, vendeur) garde, au moment où
--     elle est faite, la liste des commandes qui composent son montant
--     (« operations ») : numéro, client, date du paiement, la part qui
--     revient au demandeur, ce que la demande en couvre, la preuve du
--     paiement (FeexPay et sa référence, ou confirmé à la main) et ce qui
--     doit faire vérifier (paiement confirmé à la main, commande saisie
--     par l'équipe, client « test »…) ;
--   - une commande déjà demandée (envoyée ou en attente) ne se redemande
--     pas ; une demande refusée rend ses commandes.
-- Seuls le superadministrateur, le CEO et la comptabilité lisent la
-- liste complète ; le demandeur voit ses commandes à reverser (numéro,
-- date, montant), sans le client.
-- =========================================================
-- (3.81.0) Empruntées plus bas, recopiées telles quelles.
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

create or replace function public.droit_enseigne(lequel text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_compte_enseigne() and coalesce((
    select case lequel
             when 'commandes' then p.peut_commandes
             when 'boutiques' then p.peut_boutiques
             when 'finances'  then p.peut_finances
             when 'produits'  then p.peut_modifier_produits
             else false
           end
      from public.profils p
     where p.id = auth.uid() and p.actif), false);
$$;
revoke all on function public.droit_enseigne(text)   from public, anon;
grant execute on function public.droit_enseigne(text)  to authenticated;

create or replace function public.tient_la_caisse(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.droit_enseigne('commandes')
      or public.droit_enseigne('finances')
      or (public.est_admin() and cible is not null
          and cible = public.boutique_du_compte());
$$;
revoke all on function public.tient_la_caisse(text) from public, anon, authenticated;
grant execute on function public.tient_la_caisse(text) to authenticated;

create or replace function public.rh_est_ceo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and ceo);
$$;


create or replace function public.part_frais_livreur(cible text, qui uuid) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare
  c          public.commandes%rowtype;
  f          numeric;
  siennes    int;
  confiees   int;
  part       numeric;
  brut_moi   numeric;
  brut_tout  numeric;
begin
  select * into c from public.commandes where id = cible;
  if not found then return 0; end if;
  f := greatest(0, coalesce(c.frais_livraison, 0));
  if f <= 0 then return 0; end if;
  select count(*) filter (where l.livreur_id = qui), count(*) filter (where l.livreur_id is not null)
    into siennes, confiees
    from public.commande_lignes l where l.commande_id = cible and l.etat <> 'annulee';
  if coalesce(siennes, 0) = 0 then
    return case when coalesce(confiees, 0) = 0 then f else 0 end;
  end if;
  if c.livraison is not null then return f; end if;
  if c.parts is not null and exists (select 1 from jsonb_each(c.parts) e(k, v)
                                      where coalesce((v ->> 'frais')::numeric, 0) > 0) then
    select coalesce(sum(coalesce((c.parts -> b.bou ->> 'frais')::numeric, 0)), 0) into part
      from (select distinct l.boutique_id as bou from public.commande_lignes l
             where l.commande_id = cible and l.livreur_id = qui and l.etat <> 'annulee') b;
    return least(f, part);
  end if;
  select coalesce(sum(l.prix * l.quantite) filter (where l.livreur_id = qui), 0),
         coalesce(sum(l.prix * l.quantite), 0)
    into brut_moi, brut_tout
    from public.commande_lignes l where l.commande_id = cible and l.etat <> 'annulee';
  if brut_tout <= 0 then return 0; end if;
  return round(f * brut_moi / brut_tout);
end $$;
revoke all on function public.part_frais_livreur(text, uuid) from public, anon, authenticated;

create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;
grant execute on function public.boutique_du_compte() to authenticated;

create or replace function public.solde_vendeur(cible uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  qui uuid := coalesce(cible, auth.uid());
  ventes bigint; gagne bigint; a_venir bigint; reverse bigint; attente bigint;
  r public.vendeurs_reception%rowtype;
begin
  if qui is null or not ((qui = auth.uid() and public.est_vendeur()) or public.est_super()) then
    raise exception 'Ce solde n''est pas le vôtre.';
  end if;
  select coalesce(sum(l.prix::bigint * l.quantite) filter (where l.etat = 'remise'), 0),
         coalesce(sum(l.prix_bizzoo::bigint * l.quantite) filter (where l.etat = 'remise'), 0),
         coalesce(sum(l.prix_bizzoo::bigint * l.quantite)
                    filter (where l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')), 0)
    into ventes, gagne, a_venir
    from public.commande_lignes l
    join public.commandes c on c.id = l.commande_id and c.etat = 'payee'
   where l.vendeur_id = qui;
  select coalesce(sum(v.montant) filter (where v.etat = 'valide'), 0),
         coalesce(sum(v.montant) filter (where v.etat = 'en_attente'), 0)
    into reverse, attente
    from public.reversements_vendeurs v where v.vendeur_id = qui;
  select * into r from public.vendeurs_reception where vendeur_id = qui;
  return jsonb_build_object(
    'ventes', ventes, 'gagne', gagne, 'a_venir', a_venir, 'reverse', reverse, 'en_attente', attente,
    'disponible', greatest(0, gagne - reverse - attente), 'devise', 'FCFA',
    'reception', case when r.vendeur_id is null or r.tel = '' then null
                      else jsonb_build_object('tel', r.tel, 'reseau', r.reseau, 'titulaire', r.titulaire,
                                              'maj_le', r.maj_le) end);
end $$;
revoke all on function public.solde_vendeur(uuid) from public, anon;
grant execute on function public.solde_vendeur(uuid) to authenticated;

create or replace function public.solde_livreur(cible uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  qui uuid := coalesce(cible, auth.uid());
  gagne bigint; a_venir bigint; reverse bigint; attente bigint; t int;
  r public.livreurs_reception%rowtype;
begin
  if qui is null or not ((qui = auth.uid() and public.est_livreur()) or public.est_super()) then
    raise exception 'Ce solde n''est pas le vôtre.';
  end if;
  select coalesce(sum(g.montant), 0) into gagne from public.gains_livreurs g where g.livreur_id = qui;
  select coalesce(p.taux_livreur, 80) into t from public.paiement p where p.id = 1;
  select coalesce(sum(floor(public.part_frais_livreur(c.id, qui) * coalesce(t, 80) / 100.0)), 0)::bigint
    into a_venir
    from public.commandes c
   where c.etat = 'payee' and coalesce(c.frais_livraison, 0) > 0
     and not exists (select 1 from public.gains_livreurs g where g.commande_id = c.id and g.livreur_id = qui)
     and exists (select 1 from public.commande_lignes l
                  where l.commande_id = c.id and l.livreur_id = qui
                    and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison'));
  select coalesce(sum(v.montant) filter (where v.etat = 'valide'), 0),
         coalesce(sum(v.montant) filter (where v.etat = 'en_attente'), 0)
    into reverse, attente
    from public.reversements_livreurs v where v.livreur_id = qui;
  select * into r from public.livreurs_reception where livreur_id = qui;
  return jsonb_build_object(
    'gagne', gagne, 'a_venir', a_venir, 'reverse', reverse, 'en_attente', attente,
    'disponible', greatest(0, gagne - reverse - attente),
    'taux', coalesce(t, 80), 'devise', 'FCFA',
    'reception', case when r.livreur_id is null or r.tel = '' then null
                      else jsonb_build_object('tel', r.tel, 'reseau', r.reseau, 'titulaire', r.titulaire,
                                              'maj_le', r.maj_le) end,
    'courses', coalesce((select jsonb_agg(jsonb_build_object(
                  'commande_id', g.commande_id, 'numero', c.numero, 'frais', g.frais,
                  'taux', g.taux, 'montant', g.montant, 'credite_le', g.credite_le,
                  'vehicule', c.livraison ->> 'vehicule',
                  'distance_km', c.livraison -> 'distance_km') order by g.credite_le desc)
                 from (select * from public.gains_livreurs x where x.livreur_id = qui
                        order by x.credite_le desc limit 50) g
                 join public.commandes c on c.id = g.commande_id), '[]'::jsonb));
end $$;
revoke all on function public.solde_livreur(uuid) from public, anon;
grant execute on function public.solde_livreur(uuid) to authenticated;

create or replace function public.solde_boutique(cible text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  gagne bigint; a_venir bigint; encaisse bigint; reverse bigint; attente bigint;
  r public.boutiques_reception%rowtype;
begin
  if not public.tient_la_caisse(cible) then
    raise exception 'Ce solde n''est pas celui de votre boutique.';
  end if;
  select coalesce(sum(l.prix_bizzoo::bigint * l.quantite) filter (where l.etat = 'remise'), 0),
         coalesce(sum(l.prix_bizzoo::bigint * l.quantite)
                    filter (where l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')), 0)
    into gagne, a_venir
    from public.commande_lignes l
    join public.commandes c on c.id = l.commande_id and c.etat = 'payee'
   where l.boutique_id = cible
     -- (3.70.0) La part d'un vendeur va au vendeur, pas à la boutique.
     and l.vendeur_id is null;
  select coalesce(sum(x.montant), 0) into encaisse from public.encaissements x
   where x.boutique_id = cible and x.mode = 'especes' and x.remis_le is not null;
  select coalesce(sum(v.montant) filter (where v.etat = 'valide'), 0),
         coalesce(sum(v.montant) filter (where v.etat = 'en_attente'), 0)
    into reverse, attente
    from public.reversements v where v.boutique_id = cible;
  select * into r from public.boutiques_reception where boutique_id = cible;
  return jsonb_build_object(
    'gagne', gagne, 'a_venir', a_venir, 'deja_encaisse', encaisse,
    'reverse', reverse, 'en_attente', attente,
    'disponible', greatest(0, gagne - encaisse - reverse - attente),
    'devise', coalesce((select nullif(b.devise, '') from public.boutiques b where b.id = cible), 'FCFA'),
    'reception', case when r.boutique_id is null or r.tel = '' then null
                      else jsonb_build_object('tel', r.tel, 'reseau', r.reseau, 'titulaire', r.titulaire,
                                              'maj_le', r.maj_le, 'maj_par', r.maj_par) end);
end $$;
revoke all on function public.solde_boutique(text) from public, anon;
grant execute on function public.solde_boutique(text) to authenticated;

create or replace function public.rh_reversements_acces() returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return public.rh_est_ceo() or exists (
    select 1 from public.rh_employes e join public.rh_profils p on p.id = e.profil_id
     where e.compte_id = auth.uid() and e.etat = 'actif' and p.comptabilite);
exception when undefined_table or undefined_column then
  -- Une base d'avant BIZZOO Personnel ou d'avant la comptabilité :
  -- personne n'y a l'accès, et les listes restent au superadministrateur.
  return false;
end $$;
revoke all on function public.rh_reversements_acces() from public, anon;
grant execute on function public.rh_reversements_acces() to authenticated;

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

create or replace function public.nom_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select coalesce(nullif(p.nom, ''), nullif(p.email, ''), 'l''équipe')
                     from public.profils p where p.id = auth.uid()), '');
$$;
revoke all on function public.nom_du_compte() from public, anon, authenticated;

create or replace function public.montant_lisible(n numeric, devise text default 'FCFA')
returns text
language sql immutable set search_path = public as $$
  select replace(to_char(coalesce(n, 0), 'FM999,999,999,990'), ',', ' ') || ' ' || coalesce(nullif(devise, ''), 'FCFA');
$$;
revoke all on function public.montant_lisible(numeric, text) from public, anon, authenticated;

create or replace function public.les_superadmins() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.role = 'superadministrateur';
$$;
revoke all on function public.les_superadmins()          from public, anon, authenticated;

create or replace function public.gere_les_fonds(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or (public.est_admin() and cible is not null and cible = public.boutique_du_compte());
$$;
revoke all on function public.gere_les_fonds(text) from public, anon, authenticated;
grant execute on function public.gere_les_fonds(text) to authenticated;

create or replace function public.est_vendeur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'vendeur', false);
$$;
revoke all on function public.est_vendeur() from public, anon;
grant execute on function public.est_vendeur() to authenticated;

create or replace function public.est_livreur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'livreur', false);
$$;
revoke all on function public.est_livreur() from public, anon, authenticated;
grant execute on function public.est_livreur() to authenticated;

alter table public.reversements add column if not exists operations jsonb;
alter table public.reversements_livreurs add column if not exists operations jsonb;
alter table public.reversements_vendeurs add column if not exists operations jsonb;

-- Les gains d'un demandeur, une ligne par commande, jusqu'à une date :
-- commandes payées et remises au client ; pour un livreur, ses courses
-- créditées.
create or replace function public.gains_par_commande(genre text, qui text, jusqu_a timestamptz)
returns table (commande_id text, part bigint, quand timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if genre = 'livreur' then
    return query
      select g.commande_id, sum(g.montant)::bigint, min(g.credite_le)
        from public.gains_livreurs g
       where g.livreur_id::text = qui and g.credite_le <= jusqu_a and g.montant > 0
       group by g.commande_id;
  else
    return query
      select l.commande_id, sum(l.prix_bizzoo::bigint * l.quantite)::bigint, min(coalesce(c.paye_le, c.cree_le))
        from public.commande_lignes l
        join public.commandes c on c.id = l.commande_id and c.etat = 'payee'
       where l.etat = 'remise' and coalesce(c.paye_le, c.cree_le) <= jusqu_a
         and case when genre = 'vendeur' then l.vendeur_id::text = qui
                  else l.boutique_id = qui and l.vendeur_id is null end
       group by l.commande_id
      having sum(l.prix_bizzoo::bigint * l.quantite) > 0;
  end if;
end $$;
revoke all on function public.gains_par_commande(text, text, timestamptz) from public, anon, authenticated;

-- Ce qui reste à reverser de chaque commande : sa part, moins ce que les
-- autres demandes (envoyées ou en attente) en couvrent déjà.
create or replace function public.commandes_reste(genre text, qui text, jusqu_a timestamptz, sauf bigint)
returns table (commande_id text, part bigint, reste bigint, quand timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  return query
    with demandes as (
      select r.operations as o from public.reversements r
       where genre = 'boutique' and r.boutique_id = qui and r.etat <> 'refuse'
         and r.id is distinct from sauf and r.operations is not null
      union all
      select r.operations from public.reversements_livreurs r
       where genre = 'livreur' and r.livreur_id::text = qui and r.etat <> 'refuse'
         and r.id is distinct from sauf and r.operations is not null
      union all
      select r.operations from public.reversements_vendeurs r
       where genre = 'vendeur' and r.vendeur_id::text = qui and r.etat <> 'refuse'
         and r.id is distinct from sauf and r.operations is not null
    ), couverts as (
      select e ->> 'commande_id' as cid, sum((e ->> 'couvert')::bigint) as fait
        from demandes d, jsonb_array_elements(coalesce(d.o -> 'commandes', '[]'::jsonb)) e
       group by 1
    )
    select g.commande_id, g.part, greatest(0, g.part - coalesce(k.fait, 0))::bigint, g.quand
      from public.gains_par_commande(genre, qui, jusqu_a) g
      left join couverts k on k.cid = g.commande_id;
end $$;
revoke all on function public.commandes_reste(text, text, timestamptz, bigint) from public, anon, authenticated;

-- Les commandes qui composent « montant » : celles choisies, ou les plus
-- anciennes qui restent à reverser.
create or replace function public.operations_couvertes(genre text, qui text, montant bigint,
  jusqu_a timestamptz, sauf bigint, choisies text[])
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  liste jsonb;
  couvert bigint;
begin
  with g as (
    select x.* from public.commandes_reste(genre, qui, jusqu_a, sauf) x
     where x.reste > 0 and (choisies is null or x.commande_id = any(choisies))
  ), c1 as (
    select g.*, coalesce(sum(g.reste) over (order by g.quand, g.commande_id
                                            rows between unbounded preceding and 1 preceding), 0) as debut
      from g
  ), pris as (
    select c1.*, least(c1.reste, montant - c1.debut) as couvre from c1
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'commande_id', c.id, 'numero', c.numero, 'paye_le', c.paye_le, 'client', c.client_nom,
           'total', c.total, 'part', p.part, 'couvert', p.couvre,
           'paiement', coalesce(v.fournisseur, ''), 'transaction', c.transaction_id,
           'confirme_par', c.confirme_par, 'origine', c.origine,
           'alertes', to_jsonb(array_remove(array[
             case when c.confirme_par <> '' then 'Paiement confirmé à la main par ' || c.confirme_par end,
             case when c.origine = 'whatsapp' then 'Commande saisie par l''équipe (WhatsApp)' end,
             case when c.transaction_id = '' and c.confirme_par = '' then 'Aucune référence de paiement' end,
             case when (c.client_nom || ' ' || c.note) ~* '\m(test|tests|essai|essais|tester)\M'
                  then 'Le nom ou la note du client parle de test' end], null)))
           order by p.quand, p.commande_id), '[]'::jsonb),
         coalesce(sum(p.couvre), 0)
    into liste, couvert
    from pris p
    join public.commandes c on c.id = p.commande_id
    left join lateral (select x.fournisseur from public.versements x
                        where x.commande_id = c.id and x.verdict = 'payee'
                        order by x.cree_le desc limit 1) v on true
   where p.couvre > 0;
  return jsonb_build_object('commandes', liste, 'non_rattache', greatest(0, montant - couvert),
                            'calcule_le', jusqu_a);
end $$;
revoke all on function public.operations_couvertes(text, text, bigint, timestamptz, bigint, text[])
  from public, anon, authenticated;

-- « BZ-000123, BZ-000130 » : les commandes d'une demande, pour la notification.
create or replace function public.numeros_operations(ops jsonb) returns text
language sql immutable set search_path = public as $$
  select case when n = 0 then '' when n <= 6 then l6
              else l6 || ' et ' || (n - 6) || ' autre' || case when n - 6 > 1 then 's' else '' end end
    from (select count(*)::int as n,
                 string_agg(e ->> 'numero', ', ' order by o) filter (where o <= 6) as l6
            from jsonb_array_elements(coalesce(ops -> 'commandes', '[]'::jsonb)) with ordinality as t(e, o)) x;
$$;
revoke all on function public.numeros_operations(jsonb) from public, anon, authenticated;

-- À chaque demande, la liste se fige : celle des commandes choisies
-- (posée par « demander_reversement_commandes »), sinon les plus anciennes
-- qui restent à reverser. Jamais bloquante : une erreur ici laisse la
-- demande passer, sans liste.
create or replace function public.reversement_note_operations() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  genre text := tg_argv[0];
  qui   text;
  choix text := nullif(current_setting('bizzoo.reversement_commandes', true), '');
begin
  begin
    if new.operations is null and choix is not null then
      new.operations := choix::jsonb;
    elsif new.operations is null then
      qui := to_jsonb(new) ->> case genre when 'livreur' then 'livreur_id'
                                          when 'vendeur' then 'vendeur_id' else 'boutique_id' end;
      if qui is not null then
        new.operations := public.operations_couvertes(genre, qui, new.montant, new.demande_le, null, null);
      end if;
    end if;
  exception when others then
    raise warning 'reversement_note_operations : %', sqlerrm;
  end;
  return new;
end $$;
revoke all on function public.reversement_note_operations() from public, anon, authenticated;

drop trigger if exists reversements_operations on public.reversements;
create trigger reversements_operations before insert on public.reversements
  for each row execute function public.reversement_note_operations('boutique');
drop trigger if exists reversements_livreurs_operations on public.reversements_livreurs;
create trigger reversements_livreurs_operations before insert on public.reversements_livreurs
  for each row execute function public.reversement_note_operations('livreur');
drop trigger if exists reversements_vendeurs_operations on public.reversements_vendeurs;
create trigger reversements_vendeurs_operations before insert on public.reversements_vendeurs
  for each row execute function public.reversement_note_operations('vendeur');

-- Les commandes d'une demande, pour qui la tranche.
create or replace function public.reversement_operations(genre text, cible bigint)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  o       jsonb;
  qui     text;
  quand   timestamptz;
  combien bigint;
begin
  if not (public.est_super() or public.rh_reversements_acces()) then
    raise exception 'Réservé au superadministrateur, au CEO et à la comptabilité.';
  end if;
  if genre = 'livreur' then
    select r.operations, r.livreur_id::text, r.demande_le, r.montant into o, qui, quand, combien
      from public.reversements_livreurs r where r.id = cible;
  elsif genre = 'vendeur' then
    select r.operations, r.vendeur_id::text, r.demande_le, r.montant into o, qui, quand, combien
      from public.reversements_vendeurs r where r.id = cible;
  else
    select r.operations, r.boutique_id, r.demande_le, r.montant into o, qui, quand, combien
      from public.reversements r where r.id = cible;
  end if;
  if not found then
    raise exception 'Demande introuvable.' using errcode = 'P0001';
  end if;
  if o is null and qui is not null then
    o := public.operations_couvertes(genre, qui, combien, quand, cible, null);
  end if;
  return coalesce(o, jsonb_build_object('commandes', '[]'::jsonb, 'non_rattache', combien));
end $$;
revoke all on function public.reversement_operations(text, bigint) from public, anon;
grant execute on function public.reversement_operations(text, bigint) to authenticated;

-- Le demandeur : ses commandes qui restent à reverser (numéro, date,
-- montant), pour choisir. Pas le client : ce n'est pas l'affaire d'un
-- vendeur.
create or replace function public.commandes_a_reverser(genre text, cible text default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  qui text := case when genre = 'boutique' then cible else coalesce(cible, auth.uid()::text) end;
begin
  if qui is null or not (
       public.est_super()
       or (genre = 'boutique' and public.gere_les_fonds(cible))
       or (genre = 'livreur' and qui = auth.uid()::text and public.est_livreur())
       or (genre = 'vendeur' and qui = auth.uid()::text and public.est_vendeur())) then
    raise exception 'Ces commandes ne sont pas les vôtres.';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
                     'commande_id', x.commande_id, 'numero', c.numero, 'paye_le', x.quand,
                     'part', x.part, 'reste', x.reste) order by x.quand, x.commande_id)
                     from public.commandes_reste(genre, qui, now(), null) x
                     join public.commandes c on c.id = x.commande_id
                    where x.reste > 0), '[]'::jsonb);
end $$;
revoke all on function public.commandes_a_reverser(text, text) from public, anon;
grant execute on function public.commandes_a_reverser(text, text) to authenticated;

-- Demander le reversement de COMMANDES ENTIÈRES. Le montant est la somme
-- de ce qui reste à reverser de chacune ; la demande passe ensuite par la
-- fonction habituelle (numéro de réception, solde, notification).
create or replace function public.demander_reversement_commandes(genre text, commandes text[], cible text default null)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  choix text[] := array(select distinct x from unnest(coalesce(commandes, '{}'::text[])) x where coalesce(x, '') <> '');
  qui   text := case when genre = 'boutique' then cible else auth.uid()::text end;
  total bigint;
  n     int;
  ops   jsonb;
  nouv  bigint;
begin
  if genre not in ('boutique', 'livreur', 'vendeur') then
    raise exception 'Demande illisible.' using errcode = 'P0001';
  end if;
  if qui is null
     or (genre = 'boutique' and not public.gere_les_fonds(cible))
     or (genre = 'livreur' and not public.est_livreur())
     or (genre = 'vendeur' and not public.est_vendeur()) then
    raise exception 'Seul le titulaire de ce solde en demande le reversement.';
  end if;
  if cardinality(choix) = 0 then
    raise exception 'Choisissez au moins une commande.' using errcode = 'P0001';
  end if;
  -- Une demande à la fois : le même verrou que la fonction habituelle.
  if genre = 'boutique' then
    perform 1 from public.boutiques b where b.id = cible for update;
  else
    perform 1 from public.profils p where p.id = auth.uid() for update;
  end if;
  select coalesce(sum(x.reste), 0), count(*) into total, n
    from public.commandes_reste(genre, qui, now(), null) x
   where x.reste > 0 and x.commande_id = any(choix);
  if n <> cardinality(choix) then
    raise exception 'Une des commandes choisies n''est pas à reverser : déjà demandée, ou pas encore remise au client.'
      using errcode = 'P0001';
  end if;
  ops := public.operations_couvertes(genre, qui, total, now(), null, choix);
  perform set_config('bizzoo.reversement_commandes', ops::text, true);
  if genre = 'boutique' then
    nouv := public.demander_reversement(cible, total);
  elsif genre = 'livreur' then
    nouv := public.demander_reversement_livreur(total);
  else
    nouv := public.demander_reversement_vendeur(total);
  end if;
  perform set_config('bizzoo.reversement_commandes', '', true);
  return nouv;
end $$;
revoke all on function public.demander_reversement_commandes(text, text[], text) from public, anon;
grant execute on function public.demander_reversement_commandes(text, text[], text) to authenticated;

-- Les demandes : tout le solde, ou des commandes entières ; la notification les nomme.
create or replace function public.demander_reversement(cible text, montant bigint)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  solde jsonb;
  r     public.boutiques_reception%rowtype;
  qui   text := public.nom_du_compte();
  nouv  bigint;
  ops   jsonb;
begin
  if not public.gere_les_fonds(cible) then
    raise exception 'Seul l''administrateur de la boutique demande un reversement.';
  end if;
  -- Une demande à la fois par boutique : on la tranche avant la suivante.
  perform 1 from public.boutiques b where b.id = cible for update;
  select * into r from public.boutiques_reception where boutique_id = cible;
  if r.boutique_id is null or r.tel = '' then
    raise exception 'Réglez d''abord le numéro qui recevra les fonds.' using errcode = 'P0001';
  end if;
  solde := public.solde_boutique(cible);
  if coalesce(montant, 0) <= 0 then
    raise exception 'Indiquez le montant à reverser.' using errcode = 'P0001';
  end if;
  if montant > (solde ->> 'disponible')::bigint then
    raise exception 'Le solde disponible est de % : vous ne pouvez pas demander plus.',
      public.montant_lisible((solde ->> 'disponible')::bigint, solde ->> 'devise') using errcode = 'P0001';
  end if;
  -- (3.81.0) Tout le solde, ou des commandes entières (« demander_reversement_commandes »).
  if nullif(current_setting('bizzoo.reversement_commandes', true), '') is null
     and montant <> (solde ->> 'disponible')::bigint then
    raise exception 'Demandez tout votre solde (%), ou choisissez des commandes entières.',
      public.montant_lisible((solde ->> 'disponible')::bigint, solde ->> 'devise') using errcode = 'P0001';
  end if;
  insert into public.reversements (boutique_id, montant, tel, reseau, titulaire, demande_par)
  values (cible, montant, r.tel, r.reseau, r.titulaire, qui)
  returning id, operations into nouv, ops;
  perform public.notifier(public.les_superadmins(), 'reversement_demande',
    'Reversement demandé : ' || public.montant_lisible(montant, solde ->> 'devise'),
    coalesce((select b.nom from public.boutiques b where b.id = cible), cible) || ' — à envoyer sur ' ||
      r.reseau || ' ' || r.tel || coalesce(' (' || nullif(r.titulaire, '') || ')', '') || '. Demandé par ' || qui || '.'
      -- (3.81.0) Les commandes de la demande.
      || case when public.numeros_operations(ops) <> '' then E'\nCommandes : ' || public.numeros_operations(ops) else '' end,
    -- (3.73.0) La touche ouvre CETTE demande.
    '#/reversements/boutique-' || nouv, null, cible, true);
  return nouv;
end $$;
revoke all on function public.demander_reversement(text, bigint) from public, anon;
grant execute on function public.demander_reversement(text, bigint) to authenticated;

create or replace function public.demander_reversement_livreur(montant bigint)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  moi   uuid := auth.uid();
  solde jsonb;
  r     public.livreurs_reception%rowtype;
  qui   text := public.nom_du_compte();
  nouv  bigint;
  ops   jsonb;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Seul un livreur demande le reversement de ses gains.';
  end if;
  -- Une demande à la fois : on la tranche avant la suivante.
  perform 1 from public.profils p where p.id = moi for update;
  select * into r from public.livreurs_reception where livreur_id = moi;
  if r.livreur_id is null or r.tel = '' then
    raise exception 'Réglez d''abord le numéro qui recevra vos gains.' using errcode = 'P0001';
  end if;
  if coalesce(montant, 0) <= 0 then
    raise exception 'Indiquez le montant à reverser.' using errcode = 'P0001';
  end if;
  solde := public.solde_livreur(moi);
  if montant > (solde ->> 'disponible')::bigint then
    raise exception 'Votre solde disponible est de % : vous ne pouvez pas demander plus.',
      public.montant_lisible((solde ->> 'disponible')::bigint, 'FCFA') using errcode = 'P0001';
  end if;
  -- (3.81.0) Tout le solde, ou des commandes entières (« demander_reversement_commandes »).
  if nullif(current_setting('bizzoo.reversement_commandes', true), '') is null
     and montant <> (solde ->> 'disponible')::bigint then
    raise exception 'Demandez tout votre solde (%), ou choisissez des commandes entières.',
      public.montant_lisible((solde ->> 'disponible')::bigint, 'FCFA') using errcode = 'P0001';
  end if;
  insert into public.reversements_livreurs (livreur_id, nom_livreur, montant, tel, reseau, titulaire)
  values (moi, qui, montant, r.tel, r.reseau, r.titulaire)
  returning id, operations into nouv, ops;
  perform public.notifier(public.les_superadmins(), 'reversement_demande',
    'Reversement demandé par un livreur : ' || public.montant_lisible(montant, 'FCFA'),
    qui || ' — à envoyer sur ' || r.reseau || ' ' || r.tel ||
      coalesce(' (' || nullif(r.titulaire, '') || ')', '') || '.'
      -- (3.81.0) Les commandes de la demande.
      || case when public.numeros_operations(ops) <> '' then E'\nCommandes : ' || public.numeros_operations(ops) else '' end,
    -- (3.73.0) La touche ouvre CETTE demande.
    '#/reversements/livreur-' || nouv, null, null, true);
  return nouv;
end $$;
revoke all on function public.demander_reversement_livreur(bigint) from public, anon;
grant execute on function public.demander_reversement_livreur(bigint) to authenticated;

create or replace function public.demander_reversement_vendeur(montant bigint)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  moi   uuid := auth.uid();
  solde jsonb;
  r     public.vendeurs_reception%rowtype;
  qui   text := public.nom_du_compte();
  nouv  bigint;
  ops   jsonb;
begin
  if moi is null or not public.est_vendeur() then
    raise exception 'Seul un vendeur demande le versement de ses gains.';
  end if;
  -- Une demande à la fois : on la tranche avant la suivante.
  perform 1 from public.profils p where p.id = moi for update;
  select * into r from public.vendeurs_reception where vendeur_id = moi;
  if r.vendeur_id is null or r.tel = '' then
    raise exception 'Réglez d''abord le numéro qui recevra vos gains.' using errcode = 'P0001';
  end if;
  if coalesce(montant, 0) <= 0 then
    raise exception 'Indiquez le montant à verser.' using errcode = 'P0001';
  end if;
  solde := public.solde_vendeur(moi);
  if montant > (solde ->> 'disponible')::bigint then
    raise exception 'Votre solde disponible est de % : vous ne pouvez pas demander plus.',
      public.montant_lisible((solde ->> 'disponible')::bigint, 'FCFA') using errcode = 'P0001';
  end if;
  -- (3.81.0) Tout le solde, ou des commandes entières (« demander_reversement_commandes »).
  if nullif(current_setting('bizzoo.reversement_commandes', true), '') is null
     and montant <> (solde ->> 'disponible')::bigint then
    raise exception 'Demandez tout votre solde (%), ou choisissez des commandes entières.',
      public.montant_lisible((solde ->> 'disponible')::bigint, 'FCFA') using errcode = 'P0001';
  end if;
  insert into public.reversements_vendeurs (vendeur_id, nom_vendeur, montant, tel, reseau, titulaire)
  values (moi, qui, montant, r.tel, r.reseau, r.titulaire)
  returning id, operations into nouv, ops;
  perform public.notifier(public.les_superadmins(), 'reversement_demande',
    'Versement demandé par un vendeur : ' || public.montant_lisible(montant, 'FCFA'),
    qui || ' — à envoyer sur ' || r.reseau || ' ' || r.tel ||
      coalesce(' (' || nullif(r.titulaire, '') || ')', '') || '.'
      -- (3.81.0) Les commandes de la demande.
      || case when public.numeros_operations(ops) <> '' then E'\nCommandes : ' || public.numeros_operations(ops) else '' end,
    -- (3.73.0) La touche ouvre CETTE demande.
    '#/reversements/vendeur-' || nouv, null, null, true);
  return nouv;
end $$;
revoke all on function public.demander_reversement_vendeur(bigint) from public, anon;
grant execute on function public.demander_reversement_vendeur(bigint) to authenticated;

-- Les demandes d'avant la 3.81.0 : leur liste, calculée à leur date, de
-- la plus ancienne à la plus récente.
do $$
declare
  d   record;
  ops jsonb;
begin
  for d in
    select 'boutique' as genre, r.id, r.boutique_id as qui, r.montant, r.demande_le
      from public.reversements r where r.operations is null
    union all
    select 'livreur', r.id, r.livreur_id::text, r.montant, r.demande_le
      from public.reversements_livreurs r where r.operations is null and r.livreur_id is not null
    union all
    select 'vendeur', r.id, r.vendeur_id::text, r.montant, r.demande_le
      from public.reversements_vendeurs r where r.operations is null and r.vendeur_id is not null
    order by 5, 2
  loop
    ops := public.operations_couvertes(d.genre, d.qui, d.montant, d.demande_le, d.id, null);
    if d.genre = 'livreur' then
      update public.reversements_livreurs set operations = ops where id = d.id;
    elsif d.genre = 'vendeur' then
      update public.reversements_vendeurs set operations = ops where id = d.id;
    else
      update public.reversements set operations = ops where id = d.id;
    end if;
  end loop;
end $$;
