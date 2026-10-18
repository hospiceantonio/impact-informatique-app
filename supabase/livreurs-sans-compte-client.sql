-- =========================================================
-- BIZZOO 3.59.0 — Un livreur n'est ni acheteur ni revendeur
--
-- Avant, un livreur qui entrait par son numéro dans l'application client
-- y recevait un SECOND compte, d'acheteur : on lui proposait « Devenir
-- revendeur », « Mes commandes », « Retrouver mes commandes d'avant ».
--
--   1. le numéro d'un livreur n'ouvre plus de compte client ;
--   2. il ne dépose pas de demande de revendeur — même par un compte
--      client ouvert avant —, et BIZZOO ne peut pas la valider ;
--   3. l'application client sait qu'un compte est celui d'un livreur
--      (ou le « double » client de son numéro) : mon_compte_livreur().
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- Les colonnes que les fonctions plus bas lisent et écrivent : posées
-- ici aussi, pour qu'une base d'avant ne casse pas à l'usage.
alter table public.clients add column if not exists tel_verifie boolean not null default false;
alter table public.clients add column if not exists adresse text not null default '';
alter table public.clients add column if not exists indicatif text not null default '229';
alter table public.clients add column if not exists type_compte text not null default 'client';
alter table public.clients add column if not exists revendeur_etat text not null default 'aucune';
alter table public.clients add column if not exists revendeur_message text not null default '';
alter table public.clients add column if not exists revendeur_adresse text not null default '';
alter table public.clients add column if not exists revendeur_latitude double precision;
alter table public.clients add column if not exists revendeur_longitude double precision;
alter table public.clients add column if not exists revendeur_demande_le timestamptz;
alter table public.clients add column if not exists revendeur_decide_par text not null default '';
alter table public.clients add column if not exists revendeur_decide_le timestamptz;
alter table public.clients add column if not exists revendeur_motif text not null default '';

-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
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


create or replace function public.numero_de_livreur(numero text) returns boolean
language sql stable security definer set search_path = public as $$
  select length(regexp_replace(coalesce(numero, ''), '\D', '', 'g')) >= 8
     and exists (
       select 1 from public.profils p
        where p.actif and p.role = 'livreur'
          and length(regexp_replace(coalesce(p.tel, ''), '\D', '', 'g')) >= 8
          and right(regexp_replace(p.tel, '\D', '', 'g'), 8)
            = right(regexp_replace(numero, '\D', '', 'g'), 8));
$$;
revoke all on function public.numero_de_livreur(text) from public, anon, authenticated;

create or replace function public.mon_compte_livreur() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  livreur boolean;
  numero text;
begin
  if moi is null then return jsonb_build_object('livreur', false, 'double', false); end if;
  select exists (select 1 from public.profils p where p.id = moi and p.actif and p.role = 'livreur')
    into livreur;
  numero := coalesce(nullif(auth.jwt() ->> 'phone', ''),
                     (select c.tel from public.clients c where c.id = moi), '');
  return jsonb_build_object(
    'livreur', livreur,
    'double', not livreur
              and not exists (select 1 from public.profils p where p.id = moi and p.actif)
              and public.numero_de_livreur(numero));
end $$;
revoke all on function public.mon_compte_livreur() from public, anon;
grant execute on function public.mon_compte_livreur() to authenticated;

create or replace function public.profil_nouveau_compte() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  /* LE NUMÉRO D'UN LIVREUR N'OUVRE PAS DE COMPTE CLIENT (3.59.0). Avant,
     un livreur qui entrait par son numéro dans l'application client y
     recevait un second compte, d'acheteur — d'où « Devenir revendeur »
     et « Mes commandes » sous ses yeux. Il entre avec SON compte. */
  if coalesce(new.raw_user_meta_data ->> 'compte', '') <> 'equipe'
     and coalesce(new.phone, '') <> ''
     and (coalesce(new.raw_user_meta_data ->> 'compte', '') = 'client' or coalesce(new.email, '') = '')
     and public.numero_de_livreur(new.phone) then
    raise exception 'NUMERO_LIVREUR : ce numéro est celui d''un livreur BIZZOO'
      using errcode = 'P0001';
  end if;
  /* UN CLIENT N'EST PAS UN COMPTE D'ÉQUIPE EN ATTENTE. L'application
     cliente s'inscrit en posant « compte: client » ; sans ce test, chaque
     acheteur apparaîtrait dans la liste des comptes de l'enseigne, et il
     suffirait d'un clic distrait pour donner à un client les droits d'un
     modérateur sur une boutique. */
  if coalesce(new.raw_user_meta_data ->> 'compte', '') = 'client' then
    return new;
  end if;
  /* Un compte qui n'a qu'un numéro est un acheteur, même si les
     métadonnées manquent — elles viennent du téléphone, après tout.
     SAUF « compte: equipe » : c'est un livreur que l'administrateur crée
     par son numéro (3.59.0). Il reçoit, comme les autres, sa fiche en
     attente — que l'administrateur active dans la foulée. */
  if coalesce(new.email, '') = '' and coalesce(new.phone, '') <> ''
     and coalesce(new.raw_user_meta_data ->> 'compte', '') <> 'equipe' then
    return new;
  end if;
  insert into public.profils (id, email, role, actif)
  values (new.id, coalesce(new.email, ''), 'moderateur', false)
  on conflict (id) do nothing;
  return new;
end $$;


create or replace function public.client_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  decision boolean := coalesce(current_setting('bizzoo.revendeur', true), '') = 'oui';
begin
  if not decision then
    if new.revendeur_etat       is distinct from old.revendeur_etat
    or new.revendeur_decide_par is distinct from old.revendeur_decide_par
    or new.revendeur_decide_le  is distinct from old.revendeur_decide_le
    or new.revendeur_motif      is distinct from old.revendeur_motif then
      raise exception 'Un compte revendeur se valide chez BIZZOO, il ne se déclare pas';
    end if;
    if new.type_compte is distinct from old.type_compte then
      if new.type_compte = 'revendeur' then
        -- UN LIVREUR NE DEVIENT PAS REVENDEUR (3.59.0), même par un compte
        -- client ouvert avec son numéro.
        if public.numero_de_livreur(coalesce(nullif(new.tel, ''), auth.jwt() ->> 'phone', '')) then
          raise exception 'Un livreur BIZZOO ne devient pas revendeur.' using errcode = 'P0001';
        end if;
        -- Déjà validé : on ne redemande pas ce qu'on a.
        if old.revendeur_etat <> 'validee' then
          new.revendeur_etat       := 'en_attente';
          new.revendeur_demande_le := now();
          new.revendeur_decide_par := '';
          new.revendeur_decide_le  := null;
          new.revendeur_motif      := '';
        end if;
      else
        -- Redevenir client ordinaire rend le statut : le reprendre
        -- demandera une nouvelle décision.
        new.revendeur_etat       := 'aucune';
        new.revendeur_demande_le := null;
        new.revendeur_decide_par := '';
        new.revendeur_decide_le  := null;
        new.revendeur_motif      := '';
      end if;
    end if;
  end if;

  new.revendeur_message := left(coalesce(new.revendeur_message, ''), 300);
  -- La position du commerce, remise d'aplomb. Elle s'écrit librement —
  -- c'est la DÉCLARATION du demandeur, comme son message — mais elle ne
  -- part pas n'importe où : hors bornes, elle disparaît.
  new.revendeur_latitude  := public.coord_valable(new.revendeur_latitude, 90);
  new.revendeur_longitude := public.coord_valable(new.revendeur_longitude, 180);
  -- Une latitude sans longitude ne désigne rien. Et « 0, 0 » est un
  -- point au large du Ghana : c'est ce que rend un téléphone qui n'a
  -- rien trouvé, jamais une boutique de Cotonou.
  if new.revendeur_latitude is null or new.revendeur_longitude is null
     or (new.revendeur_latitude = 0 and new.revendeur_longitude = 0) then
    new.revendeur_latitude  := null;
    new.revendeur_longitude := null;
  end if;
  new.revendeur_adresse := left(coalesce(new.revendeur_adresse, ''), 200);

  if coalesce(current_setting('bizzoo.verification', true), '') = 'oui' then
    return new;   -- la vérification par SMS, et elle seule
  end if;
  if new.tel_verifie is distinct from old.tel_verifie then
    raise exception 'Un numéro se vérifie par SMS, il ne se déclare pas';
  end if;
  if old.tel_verifie and new.tel is distinct from old.tel then
    raise exception 'Un numéro vérifié ne se change pas : refaites une vérification';
  end if;
  return new;
end $$;


create or replace function public.client_a_l_ecriture() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('bizzoo.verification', true), '') <> 'oui' then
    new.tel_verifie := false;
  end if;
  new.tel := left(regexp_replace(coalesce(new.tel, ''), '\D', '', 'g'), 20);
  if coalesce(new.type_compte, '') <> 'revendeur' then
    new.type_compte          := 'client';
    new.revendeur_etat       := 'aucune';
    new.revendeur_demande_le := null;
  else
    if public.numero_de_livreur(coalesce(nullif(new.tel, ''), auth.jwt() ->> 'phone', '')) then
      raise exception 'Un livreur BIZZOO ne devient pas revendeur.' using errcode = 'P0001';
    end if;
    new.revendeur_etat       := 'en_attente';
    new.revendeur_demande_le := now();
  end if;
  new.revendeur_message    := left(coalesce(new.revendeur_message, ''), 300);
  -- La position du commerce, remise d'aplomb. Elle s'écrit librement —
  -- c'est la DÉCLARATION du demandeur, comme son message — mais elle ne
  -- part pas n'importe où : hors bornes, elle disparaît.
  new.revendeur_latitude  := public.coord_valable(new.revendeur_latitude, 90);
  new.revendeur_longitude := public.coord_valable(new.revendeur_longitude, 180);
  -- Une latitude sans longitude ne désigne rien. Et « 0, 0 » est un
  -- point au large du Ghana : c'est ce que rend un téléphone qui n'a
  -- rien trouvé, jamais une boutique de Cotonou.
  if new.revendeur_latitude is null or new.revendeur_longitude is null
     or (new.revendeur_latitude = 0 and new.revendeur_longitude = 0) then
    new.revendeur_latitude  := null;
    new.revendeur_longitude := null;
  end if;
  new.revendeur_adresse := left(coalesce(new.revendeur_adresse, ''), 200);
  new.revendeur_decide_par := '';
  new.revendeur_decide_le  := null;
  new.revendeur_motif      := '';
  return new;
end $$;


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

  -- Une demande déposée avant la 3.59.0 avec le numéro d'un livreur ne
  -- se valide pas : un livreur n'est pas revendeur.
  if accord and exists (select 1 from public.clients c
                         where c.id = cible and public.numero_de_livreur(c.tel)) then
    raise exception 'Ce numéro est celui d''un livreur BIZZOO : un livreur ne devient pas revendeur.'
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


