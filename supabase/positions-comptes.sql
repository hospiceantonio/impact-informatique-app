-- =========================================================
-- BIZZOO — revendeurs et livreurs valident leur compte par leur position
--
-- Un LIVREUR enregistre sa position (géolocalisation du téléphone +
-- adresse) à sa première connexion à BIZZOO Admin ; tant qu'il ne l'a
-- pas fait, aucune course ne lui est confiée.
-- Un REVENDEUR enregistre la sienne dans son compte ; tant qu'il ne l'a
-- pas fait, BIZZOO ne peut pas valider sa demande.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
-- Sans danger : relançable.
-- =========================================================

-- =========================================================
-- Un livreur VALIDE SON COMPTE en enregistrant sa position : la
-- géolocalisation de son téléphone, et son adresse écrite. BIZZOO Admin
-- le lui demande à la connexion, avant tout le reste ; tant qu'il ne
-- l'a pas fait, aucune course ne lui est confiée (« assigner_livreur »).
--
-- La position s'écrit par « enregistrer_ma_position », et par le livreur
-- lui-même : personne ne la pose à sa place, personne ne la retouche à
-- la main. L'enseigne les lit toutes ; une boutique, celles de ses
-- livreurs.

-- Les fonctions qu'appellent celles qui suivent, telles quelles.
create or replace function public.administre(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.droit_enseigne('boutiques')
      or (public.est_admin() and cible is not null
          and cible = public.boutique_du_compte());
$$;


create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;


create or replace function public.coord_valable(valeur double precision, borne double precision)
returns double precision
language sql immutable as $$
  select case when valeur is null
                or valeur <> valeur              -- « NaN » ne s'égale pas lui-même
                or valeur < -borne or valeur > borne
              then null else valeur end;
$$;
revoke all on function public.coord_valable(double precision, double precision)
  from public, anon, authenticated;
grant execute on function public.coord_valable(double precision, double precision)
  to anon, authenticated;

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


create or replace function public.peut_agir_sur(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.est_compte_enseigne()
      or (public.est_equipe() and cible is not null
          and cible = public.boutique_du_compte());
$$;


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



-- Les fonctions qu'appellent celles qui suivent, telles quelles.
create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;



create table if not exists public.positions_livreurs (
  profil_id      uuid primary key references public.profils(id) on delete cascade,
  latitude       double precision not null,
  longitude      double precision not null,
  precision_m    int,
  adresse        text not null default '',
  enregistre_le  timestamptz not null default now()
);
alter table public.positions_livreurs enable row level security;
drop policy if exists "positions livreurs lecture" on public.positions_livreurs;
create policy "positions livreurs lecture" on public.positions_livreurs
  for select to authenticated
  using (profil_id = auth.uid()
         or public.est_super()
         or exists (select 1 from public.profils p
                     where p.id = positions_livreurs.profil_id
                       and public.administre(p.boutique_id)));
revoke all on public.positions_livreurs from anon;
revoke insert, update, delete on public.positions_livreurs from authenticated;
grant select on public.positions_livreurs to authenticated;

create or replace function public.enregistrer_ma_position(
  lat double precision, lng double precision, adresse text, precision_m int default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  la  double precision := public.coord_valable(lat, 90);
  lo  double precision := public.coord_valable(lng, 180);
  ad  text := left(trim(coalesce(adresse, '')), 200);
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Seul un livreur enregistre sa position ici.' using errcode = '42501';
  end if;
  -- « 0, 0 » : un téléphone qui n'a rien trouvé, jamais Cotonou.
  if la is null or lo is null or (la = 0 and lo = 0) then
    raise exception 'Position introuvable : activez la localisation du téléphone, puis réessayez.'
      using errcode = 'P0001';
  end if;
  if length(ad) < 3 then
    raise exception 'Indiquez aussi votre adresse : quartier, repère.' using errcode = 'P0001';
  end if;
  insert into public.positions_livreurs (profil_id, latitude, longitude, precision_m, adresse, enregistre_le)
  values (moi, la, lo, greatest(0, precision_m), ad, now())
  on conflict (profil_id) do update
     set latitude = excluded.latitude, longitude = excluded.longitude,
         precision_m = excluded.precision_m, adresse = excluded.adresse,
         enregistre_le = now();
  return jsonb_build_object('latitude', la, 'longitude', lo, 'adresse', ad, 'le', now());
end $$;
revoke all on function public.enregistrer_ma_position(double precision, double precision, text, int)
  from public, anon;
grant execute on function public.enregistrer_ma_position(double precision, double precision, text, int)
  to authenticated;


create or replace function public.valider_revendeur(
  cible uuid, accord boolean, raison text default '')
returns text
language plpgsql security definer set search_path = public as $$
declare
  qui  text;
  etat text;
begin
  if not public.est_super() then
    raise exception 'Seul BIZZOO valide un compte revendeur';
  end if;
  select coalesce(p.email, '') into qui from public.profils p where p.id = auth.uid();
  etat := case when accord then 'validee' else 'refusee' end;

  -- UN REVENDEUR VALIDE SON COMPTE EN ACTIVANT SA POSITION : la
  -- géolocalisation de son téléphone, ET son adresse écrite. Sans elles,
  -- BIZZOO ne l'accepte pas (il peut toujours refuser).
  if accord and not exists (
       select 1 from public.clients c
        where c.id = cible
          and c.revendeur_latitude is not null and c.revendeur_longitude is not null
          and length(trim(coalesce(c.revendeur_adresse, ''))) >= 3) then
    raise exception 'Ce revendeur n''a pas encore enregistré sa position : il doit activer la localisation de son téléphone dans son compte, et indiquer son adresse.'
      using errcode = 'P0001';
  end if;

  perform set_config('bizzoo.revendeur', 'oui', true);
  update public.clients
     set revendeur_etat       = etat,
         type_compte          = case when accord then 'revendeur' else type_compte end,
         revendeur_decide_par = coalesce(qui, ''),
         revendeur_decide_le  = now(),
         revendeur_motif      = left(coalesce(raison, ''), 300),
         maj_le               = now()
   where id = cible;
  if not found then
    perform set_config('bizzoo.revendeur', '', true);
    raise exception 'Compte introuvable';
  end if;
  -- Le drapeau est rendu tel qu'il était : il ne vaut que pour la
  -- ligne qu'on vient d'écrire, pas pour la suite de l'appel.
  perform set_config('bizzoo.revendeur', '', true);
  return etat;
end $$;

revoke all on function public.valider_revendeur(uuid, boolean, text)
  from public, anon, authenticated;
grant execute on function public.valider_revendeur(uuid, boolean, text) to authenticated;

create or replace function public.assigner_livreur(
  commande text, boutique text, livreur uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  combien int;
  rang    text;
begin
  if not public.peut_agir_sur(boutique) then
    raise exception 'Cette commande ne concerne pas votre boutique';
  end if;

  -- « livreur » nul : on retire l'attribution. Une boutique doit pouvoir
  -- reprendre une course confiée par erreur.
  if livreur is not null then
    select p.role into rang from public.profils p
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
     set livreur_id = livreur
   where l.commande_id = commande
     and l.boutique_id = boutique
     and l.etat in ('preparee', 'en_livraison');
  get diagnostics combien = row_count;
  perform set_config('bizzoo.livraison', '', true);

  if combien = 0 then
    raise exception 'Rien à confier ici : préparez d''abord la commande.';
  end if;
  return combien;
end $$;
revoke all on function public.assigner_livreur(text, text, uuid) from public, anon;
grant execute on function public.assigner_livreur(text, text, uuid) to authenticated;


