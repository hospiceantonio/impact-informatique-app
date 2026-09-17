-- =========================================================
-- BIZZOO — où se trouve le commerce d'un revendeur
--
-- Valider une demande de compte revendeur, c'est accorder une
-- remise permanente sur tout le catalogue. Jusqu'ici, pour
-- décider, l'enseigne n'avait qu'un nom, une adresse e-mail et
-- une phrase. On ne signe pas cela à l'aveugle.
--
-- La demande porte désormais OÙ SE TROUVE LE COMMERCE, sous
-- deux formes qui se complètent — et aucune n'est obligatoire :
--
--   L'ADRESSE ÉCRITE. Au Bénin, c'est elle qui permet de
--     trouver : un quartier, un repère, « derrière la
--     pharmacie ». Un point GPS seul ne se demande pas à un
--     taximan.
--   LES COORDONNÉES. Relevées par le téléphone d'un geste, ou
--     tirées d'un lien de carte que le demandeur colle. Elles
--     ouvrent l'itinéraire depuis l'application admin.
--
-- Ce N'EST PAS l'adresse de livraison du client : on se fait
-- livrer chez soi et on tient boutique ailleurs.
--
-- LA POSITION EST UNE DÉCLARATION, pas une preuve. Elle
-- s'écrit librement, comme le message de la demande — c'est
-- l'enseigne qui juge, et c'est bien pour cela qu'elle la
-- demande. La base se contente de refuser ce qui n'est pas une
-- position : hors bornes, « NaN », une latitude sans longitude,
-- ou le fameux « 0, 0 » que rend un téléphone qui n'a rien
-- trouvé et qui tombe au large du Ghana.
--
-- Rien ne change pour les comptes déjà validés : leur position
-- est simplement vide, et ils peuvent la renseigner depuis leur
-- compte.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, et rien n'est supprimé.
-- =========================================================

-- ---------------------------------------------------------
-- 1. Les trois colonnes
-- ---------------------------------------------------------
alter table public.clients add column if not exists revendeur_adresse text not null default '';
alter table public.clients add column if not exists revendeur_latitude double precision;
alter table public.clients add column if not exists revendeur_longitude double precision;

-- Les colonnes que les règles d'écriture ci-dessous remplissent aussi.
-- Elles viennent de « comptes-clients.sql » et « comptes-revendeurs.sql »,
-- et sont répétées ici : un fichier qui pose une fonction pose aussi les
-- colonnes qu'elle touche.
alter table public.clients add column if not exists tel_verifie boolean not null default false;
alter table public.clients add column if not exists type_compte text not null default 'client';
alter table public.clients add column if not exists revendeur_etat text not null default 'aucune';
alter table public.clients add column if not exists revendeur_message text not null default '';
alter table public.clients add column if not exists revendeur_demande_le timestamptz;
alter table public.clients add column if not exists revendeur_decide_par text not null default '';
alter table public.clients add column if not exists revendeur_decide_le timestamptz;
alter table public.clients add column if not exists revendeur_motif text not null default '';

-- ---------------------------------------------------------
-- 2. Ce qui n'est pas une coordonnée
-- ---------------------------------------------------------
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

-- ---------------------------------------------------------
-- 3. Les deux règles d'écriture la remettent d'aplomb
-- ---------------------------------------------------------
-- La même normalisation aux deux entrées : à la création du compte, et
-- à chaque modification. Le reste de ces deux règles est inchangé — on
-- les repose entières parce qu'une fonction ne se modifie pas par
-- morceaux.
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

drop trigger if exists clients_verrous on public.clients;
create trigger clients_verrous
  before update on public.clients
  for each row execute function public.client_verrous();

drop trigger if exists clients_ecriture on public.clients;
create trigger clients_ecriture
  before insert on public.clients
  for each row execute function public.client_a_l_ecriture();

-- ---------------------------------------------------------
-- 4. La liste du superadministrateur la rend
-- ---------------------------------------------------------
-- « drop » avant « create » : ajouter des colonnes au résultat d'une
-- fonction change son type de retour, et PostgreSQL refuse de le changer
-- sur place — « cannot change return type of existing function ». Sans
-- ce retrait, le fichier entier échouerait.
drop function if exists public.revendeurs(text);
create or replace function public.revendeurs(filtre text default 'en_attente')
returns table (
  id uuid, nom text, email text, tel text, indicatif text,
  message text, etat text, demande_le timestamptz,
  decide_par text, decide_le timestamptz, motif text,
  adresse text, latitude double precision, longitude double precision)
language sql stable security definer set search_path = public as $$
  select c.id, c.nom, coalesce(u.email, '')::text, c.tel, c.indicatif,
         c.revendeur_message, c.revendeur_etat, c.revendeur_demande_le,
         c.revendeur_decide_par, c.revendeur_decide_le, c.revendeur_motif,
         c.revendeur_adresse, c.revendeur_latitude, c.revendeur_longitude
    from public.clients c
    left join auth.users u on u.id = c.id
   where public.est_super()
     and c.revendeur_etat <> 'aucune'
     and (coalesce(filtre, '') = '' or c.revendeur_etat = filtre)
   order by c.revendeur_demande_le desc nulls last;
$$;
revoke all on function public.revendeurs(text) from public, anon, authenticated;
grant execute on function public.revendeurs(text) to authenticated;

-- ---------- Vérification ----------
-- La règle refuse-t-elle ce qui n'est pas une position ? Les quatre
-- premières lignes doivent dire « écartée », la dernière « gardée ».
select cas, case when garde is null then 'écartée' else 'gardée : ' || garde end as "Verdict"
  from (values
    ('une latitude impossible (91)',      public.coord_valable(91,    90)),
    ('une longitude impossible (-181)',   public.coord_valable(-181, 180)),
    ('« NaN », qu''un téléphone peut rendre',
                                          public.coord_valable('NaN'::double precision, 90)),
    ('rien du tout',                      public.coord_valable(null,  90)),
    ('Cotonou (6.37)',                    public.coord_valable(6.37,  90))
  ) as t(cas, garde);
