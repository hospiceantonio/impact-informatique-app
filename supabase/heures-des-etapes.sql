-- =========================================================
-- BIZZOO 4.1.0 — L'heure de chaque étape d'une commande
--
--   Le suivi d'une commande montre au client l'heure de chaque étape
--   (reçue, vue, préparée, en livraison, remise), lue dans le journal que
--   la base tient déjà. Trois fonctions en lecture seule ; aucune table ne
--   change.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

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

create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;
grant execute on function public.boutique_du_compte() to authenticated;

-- La fonction interne : les heures, boutique par boutique.
--
-- POUR UNE BOUTIQUE, l'heure d'une étape est celle où SA DERNIÈRE ligne
-- l'a atteinte ou dépassée — la même règle que l'étape affichée, qui est
-- la moins avancée de ses lignes. Une ligne annulée ne compte pas. Une
-- ligne passée de « vue » à « en_livraison » d'un coup a franchi
-- « préparée » au même moment. « Commande reçue » : l'heure du paiement.
-- Une étape dont aucune heure n'est connue (une commande d'avant le
-- journal, reconstitué sans ses étapes intermédiaires) n'en a pas.
create or replace function public.heures_etapes_commande(cible text)
returns jsonb
language sql stable security definer set search_path = public as $$
  with rangs(etat, r) as (
    values ('vue', 1), ('preparee', 2), ('en_livraison', 3), ('remise', 4)
  ), lig as (
    select l.id, l.boutique_id
      from public.commande_lignes l
     where l.commande_id = cible and coalesce(l.etat, '') <> 'annulee'
       and l.boutique_id is not null
  ), atteint as (
    select lg.boutique_id, e.etat,
           (select min(j.le)
              from public.rh_journal_lignes j
              join rangs rj on rj.etat = j.valeur
             where j.ligne_id = lg.id and j.quoi = 'etat' and rj.r >= e.r) as le
      from lig lg cross join rangs e
  ), par_etape as (
    select a.boutique_id, a.etat,
           case when bool_and(a.le is not null) then max(a.le) end as le
      from atteint a
     group by a.boutique_id, a.etat
  )
  select coalesce(jsonb_object_agg(b.boutique_id, b.heures), '{}'::jsonb)
    from (select x.boutique_id,
                 jsonb_strip_nulls(jsonb_build_object('nouvelle',
                   (select c.paye_le from public.commandes c where c.id = cible)))
                 || coalesce((select jsonb_object_agg(p.etat, p.le)
                                from par_etape p
                               where p.boutique_id = x.boutique_id and p.le is not null),
                             '{}'::jsonb) as heures
            from (select distinct lg.boutique_id from lig lg) x) b;
$$;
revoke all on function public.heures_etapes_commande(text) from public, anon, authenticated;

-- Pour un compte : une colonne que PostgREST lit avec la commande
-- (« commandes?select=…,heures_etapes »), comme « restes ». Le client de
-- la commande et l'enseigne lisent tout ; l'équipe d'une boutique, sa
-- seule part ; personne d'autre.
create or replace function public.heures_etapes(cmd public.commandes)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  o    public.commandes%rowtype;
  tout boolean;
  chez text;
  h    jsonb;
begin
  select * into o from public.commandes c where c.id = cmd.id;
  if not found then return null; end if;

  tout := public.est_super()
       or public.droit_enseigne('commandes')
       or (o.client_id is not null and o.client_id = auth.uid());
  if not tout then
    chez := public.boutique_du_compte();
    if chez is null or not public.est_equipe() or public.est_compte_enseigne()
       or not exists (select 1 from public.commande_lignes l
                       where l.commande_id = o.id and l.boutique_id = chez) then
      return null;
    end if;
  end if;

  h := public.heures_etapes_commande(o.id);
  if tout then return h; end if;
  return jsonb_strip_nulls(jsonb_build_object(chez, h -> chez));
end $$;
revoke all on function public.heures_etapes(public.commandes) from public, anon;
grant execute on function public.heures_etapes(public.commandes) to authenticated;

-- Sans compte : par le numéro de la commande et le téléphone qui l'a
-- passée, exactement comme « suivre_commande ».
create or replace function public.heures_etapes_suivies(cible text, tel text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.commandes%rowtype;
begin
  select * into c from public.commandes
   where id = cible
     and not compte_supprime
     and client_tel = regexp_replace(coalesce(tel, ''), '\D', '', 'g');
  if not found then return null; end if;
  return public.heures_etapes_commande(c.id);
end $$;
revoke all on function public.heures_etapes_suivies(text, text) from public;
grant execute on function public.heures_etapes_suivies(text, text) to anon, authenticated;
