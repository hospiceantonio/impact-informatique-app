-- =========================================================
-- BIZZOO — la colonne qui manquait sur les lignes vendues
--
-- Le symptôme : « record "new" has no field "code" » dès qu'un
-- panier est validé. Aucune commande ne se crée, et le paiement
-- n'est même pas tenté. Rien n'a jamais été débité.
--
-- La cause : le fichier « marge-bizzoo.sql » a installé la règle
-- d'écriture des lignes de commande, celle qui fige sur la ligne
-- le code du produit vendu — sans installer la colonne qui le
-- reçoit. PostgreSQL ne relit le corps d'une fonction qu'au
-- moment de l'exécuter : le fichier est passé sans broncher, et
-- la base s'est arrêtée à la première commande.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, et rien n'est supprimé.
-- =========================================================

-- ---------------------------------------------------------
-- 1. La colonne
-- ---------------------------------------------------------
-- Figée sur la ligne, comme le nom et le prix : c'est ce qui a
-- été vendu, et cela ne se réécrit pas.
alter table public.commande_lignes
  add column if not exists code text not null default '';

-- Le verrou reposé plus bas lit aussi ces deux-là. Elles viennent de
-- « marge-bizzoo.sql », qui est le fichier fautif que celui-ci répare :
-- autant ne rien supposer de ce qu'il a réussi à poser.
alter table public.commande_lignes
  add column if not exists prix_bizzoo int not null default 0;
alter table public.commande_lignes
  add column if not exists taux_marge numeric;

-- ---------------------------------------------------------
-- 2. Les commandes déjà passées reçoivent le leur
-- ---------------------------------------------------------
-- Un code ne bouge jamais : celui que porte le produit aujourd'hui
-- est celui qu'il portait le jour de la vente. On ne réécrit donc
-- pas l'histoire, on la complète. Les lignes dont le produit a
-- disparu du catalogue restent sans code — il n'y a plus rien à
-- aller chercher.
--
-- Le verrou est retiré le temps de l'écriture, puisqu'il interdit
-- précisément de toucher à ces colonnes-là.
drop trigger if exists lignes_verrous on public.commande_lignes;

update public.commande_lignes l
   set code = p.code
  from public.produits p
 where p.id = l.produit_id
   and coalesce(l.code, '') = ''
   and coalesce(p.code, '') <> '';

-- Le verrou lui-même, reposé à l'identique avant d'être rebranché : un
-- « create trigger » qui désigne une fonction absente échoue, et tout le
-- fichier serait annulé — l'éditeur SQL de Supabase exécute d'un bloc.
-- La colonne que « ligne_verrous » protège : l'accusé de réception du
-- client. Un fichier qui pose une fonction pose aussi les colonnes
-- qu'elle touche — sans elle, la règle s'installerait sans un mot et
-- la base s'arrêterait sur « record "new" has no field » à la
-- première ligne de commande avancée.
alter table public.commande_lignes add column if not exists confirme_le timestamptz;

create or replace function public.ligne_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- LA CONFIRMATION DU CLIENT passe par « confirmer_reception », qui
  -- pose ce drapeau. Sans lui, la colonne est aussi verrouillée que le
  -- reste : ni la boutique ni le client ne peuvent l'écrire à la main.
  if coalesce(current_setting('bizzoo.reception', true), '') <> 'oui'
     and new.confirme_le is distinct from old.confirme_le then
    raise exception 'Un accusé de réception se pose depuis le compte du client';
  end if;

  if new.commande_id is distinct from old.commande_id
  or new.boutique_id is distinct from old.boutique_id
  or new.produit_id  is distinct from old.produit_id
  or new.nom         is distinct from old.nom
  or new.code        is distinct from old.code
  or new.reference   is distinct from old.reference
  or new.prix        is distinct from old.prix
  or new.prix_bizzoo is distinct from old.prix_bizzoo
  or new.taux_marge  is distinct from old.taux_marge
  or new.quantite    is distinct from old.quantite then
    raise exception 'Une ligne de commande ne change que d''état : ce qui a été vendu est vendu';
  end if;
  return new;
end $$;

create trigger lignes_verrous
  before update on public.commande_lignes
  for each row execute function public.ligne_verrous();

-- ---------- Vérification ----------
-- « colonne code » doit dire « en place », et « produits sans
-- code » doit être à 0. Si ce dernier n'est pas à 0, c'est que le
-- distributeur de codes manque aussi : dites-le-moi, il y a un
-- second fichier à passer.
select
  case when exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name   = 'commande_lignes'
       and column_name  = 'code')
    then 'en place' else 'MANQUANT' end                       as "colonne code",
  (select count(*) from public.commande_lignes)               as "lignes vendues",
  (select count(*) from public.commande_lignes
    where code <> '')                                         as "avec leur code",
  (select count(*) from public.commande_lignes
    where code = '' and produit_id is null)                   as "produit disparu depuis",
  (select count(*) from public.produits
    where coalesce(code, '') = '')                            as "produits sans code";
