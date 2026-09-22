-- =========================================================
-- BIZZOO — le livreur de l'enseigne
--
-- CE QUI MANQUAIT. Un livreur appartenait forcément à UNE
-- boutique. Un porteur qui fait la tournée de toutes les
-- boutiques de BIZZOO n'avait donc pas de place : il fallait
-- lui ouvrir un compte par boutique, avec un mot de passe par
-- boutique, et il recevait ses courses dans quatre listes.
--
-- CE QUE CE FICHIER AJOUTE. La même convention que pour les
-- comptes d'enseigne : AUCUNE BOUTIQUE VEUT DIRE TOUTES. Un
-- livreur rattaché à aucune boutique est un livreur de BIZZOO.
-- Toutes les boutiques le voient dans « Confier à un livreur »,
-- toutes peuvent lui confier une course, et ses courses
-- arrivent dans une seule liste, la sienne.
--
-- CE QUE CELA NE LUI DONNE PAS. Rien de plus. Un livreur de
-- BIZZOO reste un livreur : pas de catalogue, pas de commandes,
-- pas de chiffres, et AUCUN MONTANT — ni le prix payé, ni le
-- prix BIZZOO. Il ne voit d'ailleurs pas plus de courses qu'un
-- autre : seulement celles qu'on lui a confiées. « Aucune
-- boutique » ne le fait pas entrer dans l'équipe de BIZZOO —
-- « est_compte_enseigne() » écarte son rang exprès.
--
-- CE QUE CE FICHIER NE DÉFAIT PAS. Aucun livreur existant ne
-- change de main : celui qui a une boutique la garde, et sa
-- boutique reste la seule à le voir.
--
-- UNE SEULE CHOSE CHANGE POUR L'EXISTANT, et il faut la savoir.
-- Avant, un livreur créé SANS choisir de boutique se retrouvait
-- avec une boutique vide — par distraction, pas par décision —
-- et plus personne ne le voyait dans aucune liste. Ce compte-là
-- devient maintenant un livreur de BIZZOO, visible de toutes
-- les boutiques. Si vous en avez un dans ce cas, ouvrez sa
-- fiche et donnez-lui sa boutique.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
-- On peut le coller deux fois de suite sans conséquence.
-- =========================================================

-- ---------- Recopié de schema.sql ----------
-- Ce fichier doit pouvoir se coller seul : les deux fonctions
-- ci-dessous s'appuient sur celles-là, qui ne changent pas.
alter table public.profils add column if not exists nom text not null default '';
alter table public.profils add column if not exists tel text not null default '';

create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;
grant execute on function public.est_equipe() to authenticated;

create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils where id = auth.uid() and actif;
$$;
grant execute on function public.boutique_du_compte() to authenticated;

-- « administrateur » ou « modérateur », actif, rattaché à AUCUNE
-- boutique. LE LIVREUR EN EST EXCLU PAR SON RANG, et c'est ce qui
-- permet à « aucune boutique » de vouloir dire deux choses
-- différentes sans les confondre : un compte qui gouverne toutes les
-- boutiques d'un côté, un porteur qui les sert toutes de l'autre.
create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false);
$$;
revoke all on function public.est_compte_enseigne() from public, anon;
grant execute on function public.est_compte_enseigne() to authenticated;

-- « assigner_livreur » s'ouvre là-dessus : le superadministrateur
-- partout, un compte de BIZZOO partout, une boutique chez elle.
create or replace function public.peut_agir_sur(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.est_compte_enseigne()
      or (public.est_equipe() and cible is not null
          and cible = public.boutique_du_compte());
$$;

-- ---------- La liste des livreurs ----------
-- DEUX SORTES DE LIVREURS, et la liste les rend toutes les deux :
-- celui de la boutique, et CELUI DE BIZZOO. La colonne « bizzoo » dit
-- lequel est lequel, pour que l'écran puisse l'écrire : confier une
-- course à quelqu'un qui n'est pas de la maison se fait les yeux
-- ouverts.
--
-- « drop » AVANT « create or replace » : changer les colonnes rendues
-- par une fonction n'est pas un remplacement aux yeux de PostgreSQL,
-- qui refuse net. Sans cette ligne, le fichier s'arrêterait ici, et
-- seulement sur une base déjà en service.
drop function if exists public.livreurs_boutique();
create or replace function public.livreurs_boutique()
returns table (id uuid, email text, nom text, tel text,
               actif boolean, bizzoo boolean)
language plpgsql stable security definer set search_path = public as $$
declare cible text := public.boutique_du_compte();
begin
  if not public.est_equipe() then return; end if;
  return query
    select p.id, coalesce(p.email, '')::text,
           coalesce(p.nom, '')::text, coalesce(p.tel, '')::text, p.actif,
           (p.boutique_id is null)
      from public.profils p
     where p.role = 'livreur'
       -- L'enseigne les voit tous, les comptes de BIZZOO aussi ;
       -- une boutique, les siens ET ceux de BIZZOO.
       and (public.est_super() or public.est_compte_enseigne()
            or (cible is not null
                and (p.boutique_id = cible or p.boutique_id is null)))
     -- Les siens d'abord, ceux de BIZZOO ensuite : on appelle son
     -- porteur avant de déranger celui de l'enseigne.
     -- Puis par nom quand il y en a un, par adresse sinon : une liste
     -- rangée par e-mail alors qu'on lit des noms paraît en désordre.
     order by (p.boutique_id is null), nullif(p.nom, '') nulls last, p.email;
end $$;
revoke all on function public.livreurs_boutique() from public, anon;
grant execute on function public.livreurs_boutique() to authenticated;

-- ---------- Confier une livraison ----------
-- LA BOUTIQUE CONFIE, à SON livreur ou à CELUI DE BIZZOO. Confier à
-- celui de la boutique d'à côté reste refusé : ce serait lui remettre
-- le nom, le numéro et l'adresse d'un client qui n'est pas le sien.
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

-- ---------- Un contrôle à la fin ----------
do $$
declare rendu text; corps text;
begin
  select pg_get_function_result(p.oid) into rendu
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'livreurs_boutique';
  if rendu is null then
    raise exception 'livreurs_boutique() est introuvable';
  end if;
  if rendu !~ 'bizzoo boolean' then
    raise exception 'livreurs_boutique() ne dit pas qui est de BIZZOO : %', rendu;
  end if;

  select p.prosrc into corps
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'assigner_livreur';
  if corps !~ 'boutique_id is null' then
    raise exception 'assigner_livreur() refuse encore le livreur de BIZZOO';
  end if;

  raise notice 'Un livreur peut maintenant porter pour toute l''enseigne.';
end $$;
