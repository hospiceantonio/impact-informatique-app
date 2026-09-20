-- =========================================================
-- BIZZOO — le cycle de vie d'une commande
--
-- Jusqu'ici, une boutique faisait avancer sa ligne en trois
-- pas : vue, préparée, remise. Deux choses manquaient.
--
-- UNE ÉTAPE « EN LIVRAISON », entre préparée et remise. Sans
-- elle, la marchandise passait du comptoir au client sans que
-- rien ne dise qu'elle était partie — et personne ne pouvait
-- répondre à « où en est ma commande ? » entre les deux.
--
-- UN ACCUSÉ DE RÉCEPTION DU CLIENT. « Remise » est ce que la
-- BOUTIQUE déclare. Le client, lui, ne disait rien du tout :
-- la boutique fermait la commande toute seule, et sa
-- déclaration n'avait aucun contrepoids.
--
-- C'EST POUR CELA QUE LA CONFIRMATION EST UNE COLONNE À PART,
-- et pas un sixième état dans la chaîne. Ce ne sont pas les
-- mêmes faits, ni les mêmes témoins. Les mêler reviendrait à
-- laisser la boutique signer l'accusé de réception du client
-- — et le jour d'un litige, il n'y aurait plus rien à
-- interroger.
--
-- Ni la boutique ni l'enseigne ne peuvent la poser : le verrou
-- la refuse à tout le monde sauf à « confirmer_reception »,
-- qui vérifie d'abord que la commande appartient bien à celui
-- qui appelle.
--
-- ET ON NE CONFIRME QUE CE QUI A ÉTÉ REMIS. Confirmer avant
-- que la boutique n'ait rien déclaré ne voudrait rien dire.
--
-- CE QUE CE FICHIER CHANGE LE JOUR OÙ VOUS L'EXÉCUTEZ : rien
-- de vos commandes en cours. Elles gardent leur état ; la
-- nouvelle étape s'offre simplement à la suivante.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, et rien n'est supprimé.
-- =========================================================

-- Les colonnes dont les règles ci-dessous se servent. Un fichier qui
-- pose une fonction pose aussi les colonnes qu'elle touche.
alter table public.commande_lignes add column if not exists code text not null default '';
alter table public.commande_lignes
  add column if not exists prix_bizzoo int not null default 0;
alter table public.commande_lignes add column if not exists taux_marge numeric;
alter table public.commandes add column if not exists client_id uuid;

-- « en_livraison » est arrivé après coup : sur une base déjà en service,
-- le corps du « create table » n'est jamais relu, et la contrainte y
-- refuserait encore ce nouvel état. On la repose donc explicitement.
alter table public.commande_lignes drop constraint if exists commande_lignes_etat_check;
alter table public.commande_lignes add constraint commande_lignes_etat_check
  check (etat in ('nouvelle', 'vue', 'preparee', 'en_livraison', 'remise', 'annulee'));

-- QUAND LE CLIENT A DIT « JE L'AI BIEN REÇU ».
--
-- Une colonne à part, et pas un état de plus dans la chaîne ci-dessus :
-- ce ne sont pas les mêmes faits, ni les mêmes témoins. « remise » est
-- ce que la BOUTIQUE déclare ; « confirme_le » est ce que le CLIENT
-- constate. Les mêler dans une seule colonne reviendrait à laisser l'un
-- écrire la parole de l'autre — et la déclaration de la boutique n'a
-- plus de valeur si elle peut aussi signer l'accusé de réception.
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

drop trigger if exists lignes_verrous on public.commande_lignes;
create trigger lignes_verrous
  before update on public.commande_lignes
  for each row execute function public.ligne_verrous();
-- ---------------------------------------------------------
-- « Cette commande est-elle la mienne ? », recopiée ici
-- ---------------------------------------------------------
-- « confirmer_reception » s'en sert pour vérifier que celui qui
-- confirme est bien le client de la commande. Un fichier qui pose
-- une fonction pose aussi les fonctions qu'elle appelle.
-- Sur une base qui l'a déjà, ce bloc ne fait rien.

create or replace function public.ma_commande(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.commandes c
     where c.id = cible
       and c.client_id is not null
       and c.client_id = auth.uid());
$$;
grant execute on function public.ma_commande(text) to authenticated;

-- ---------- « Je l'ai bien reçu » ----------
-- LE CLIENT SEUL, et c'est tout l'intérêt. La boutique déclare avoir
-- remis la marchandise ; le client constate l'avoir reçue. Si l'un
-- pouvait signer pour l'autre, la déclaration de la boutique n'aurait
-- plus de valeur — et c'est justement ce qu'un litige vient interroger.
--
-- PAR BOUTIQUE, pas par commande entière : une commande peut traverser
-- deux boutiques qui livrent séparément, et le client ne peut pas
-- confirmer ce qu'il n'a pas encore vu arriver.
--
-- ON NE CONFIRME QUE CE QUI A ÉTÉ REMIS. Confirmer avant que la
-- boutique n'ait rien déclaré ne voudrait rien dire — et donnerait au
-- client un moyen de clore une commande qui n'est pas partie.
create or replace function public.confirmer_reception(commande text, boutique text)
returns int
language plpgsql security definer set search_path = public as $$
declare
  moi     uuid := auth.uid();
  combien int;
begin
  if moi is null then
    raise exception 'Connectez-vous pour confirmer une réception';
  end if;
  if not public.ma_commande(commande) then
    raise exception 'Cette commande n''est pas la vôtre';
  end if;

  perform set_config('bizzoo.reception', 'oui', true);
  update public.commande_lignes l
     set confirme_le = now()
   where l.commande_id = commande
     and l.boutique_id = boutique
     and l.etat = 'remise'
     and l.confirme_le is null;
  get diagnostics combien = row_count;
  perform set_config('bizzoo.reception', '', true);

  if combien = 0 then
    raise exception 'Rien à confirmer ici : la boutique n''a pas encore déclaré vous avoir remis cette commande.';
  end if;
  return combien;
end $$;
revoke all on function public.confirmer_reception(text, text) from public, anon;
grant execute on function public.confirmer_reception(text, text) to authenticated;

-- La colonne se LIT par l'équipe comme par le client. Une règle RLS
-- décide quelles lignes on voit, jamais quelles colonnes : sans ce
-- droit, personne ne verrait l'accusé de réception.
revoke select on public.commande_lignes from authenticated;
grant select (
  id, commande_id, boutique_id, produit_id,
  nom, code, reference, prix, quantite, etat, cree_le, confirme_le
) on public.commande_lignes to authenticated;
revoke all on public.commande_lignes from anon;
-- L'équipe avance l'état de sa ligne, et RIEN d'autre. « confirme_le »
-- n'est volontairement pas dans cette liste : il ne s'écrit que par la
-- fonction ci-dessus.
grant update (etat) on public.commande_lignes to authenticated;

-- ---------- Vérification ----------
-- Où en est chaque ligne des dernières commandes payées, et qui a dit
-- quoi. « Confirmé » ne se remplit que lorsque le CLIENT l'a dit.
select c.numero                                      as "Commande",
       b.nom                                         as "Boutique",
       l.nom                                         as "Article",
       case l.etat when 'nouvelle'     then '1. nouvelle'
                   when 'vue'          then '2. vue'
                   when 'preparee'     then '3. préparée'
                   when 'en_livraison' then '4. en livraison'
                   when 'remise'       then '5. remise au client'
                   else 'annulée' end                as "Où ça en est",
       case when l.confirme_le is null then '—'
            else to_char(l.confirme_le, 'DD/MM HH24:MI') end as "Client a confirmé"
  from public.commande_lignes l
  join public.commandes c on c.id = l.commande_id
  left join public.boutiques b on b.id = l.boutique_id
 where c.etat = 'payee'
 order by c.cree_le desc, b.nom
 limit 20;
