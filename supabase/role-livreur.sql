-- =========================================================
-- BIZZOO — le rôle livreur
--
-- Un quatrième rang dans l'équipe, et le plus délicat de
-- tous : il a un profil, donc la base lui répond — mais il ne
-- TIENT rien. Il porte la marchandise, et c'est tout.
--
-- CE QUE CE FICHIER CORRIGE AVANT MÊME D'AJOUTER LE RANG.
--
--   « est_equipe() » disait « n'importe quel profil actif ».
--   Le jour où le rang livreur arrive, cette seule phrase lui
--   ouvre d'un coup : les commandes de toute la boutique, le
--   journal des actions, les chiffres de vente et le dépôt de
--   photos. Elle nomme désormais les trois rangs qui tiennent
--   la boutique, et le livreur n'en est pas.
--
--   « peut_modifier_produits » vaut VRAI PAR DÉFAUT sur tout
--   profil. Un livreur fraîchement créé aurait pu modifier le
--   catalogue, parce que la colonne lui disait oui. La
--   fonction demande maintenant d'abord s'il est de l'équipe.
--
-- CE QU'IL VOIT. Le numéro de la commande, ce qu'il porte, le
-- nom du client, son numéro, son adresse. RIEN D'AUTRE — et
-- surtout AUCUN MONTANT : ni le prix payé, ni le prix BIZZOO.
--
-- C'EST POURQUOI IL PASSE PAR UNE FONCTION, et pas par une
-- règle RLS. Une règle décide quelles LIGNES on voit ; elle
-- les rend alors ENTIÈRES, prix BIZZOO compris. Seule une
-- fonction « security definer » peut choisir les colonnes. La
-- liste que rend « mes_livraisons() » est la réponse entière
-- à « que voit un livreur ? ».
--
-- QUI CONFIE, ET À QUI. La boutique confie, et seulement à SON
-- livreur : confier au livreur d'à côté reviendrait à lui
-- remettre le nom, le numéro et l'adresse d'un client qui
-- n'est pas le sien. Et on ne confie que ce qui est PRÊT.
--
-- CE QU'IL PEUT FAIRE. Deux gestes : « je l'ai prise » et
-- « je l'ai remise », sur SES courses seulement. Préparer
-- reste à la boutique, annuler aussi, et c'est toujours le
-- CLIENT qui confirme avoir reçu.
--
-- CE QUE CE FICHIER CHANGE LE JOUR OÙ VOUS L'EXÉCUTEZ : rien
-- de visible. Aucun livreur n'existe encore ; vous en créez
-- depuis Comptes, comme n'importe quel membre de l'équipe.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, et rien n'est supprimé.
-- =========================================================

-- Les colonnes dont les fonctions ci-dessous se servent.
-- ---------- Socle des comptes d'enseigne ----------
-- Recopié de schema.sql : les fonctions de droits ci-dessous s'appuient
-- dessus, et ce fichier doit pouvoir se coller seul sur une base d'avant.
alter table public.profils add column if not exists nom text not null default '';
alter table public.profils add column if not exists tel text not null default '';
alter table public.profils
  add column if not exists peut_commandes boolean not null default true;
alter table public.profils
  add column if not exists peut_boutiques boolean not null default false;
alter table public.profils
  add column if not exists peut_finances  boolean not null default false;

create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false);
$$;
revoke all on function public.est_compte_enseigne() from public, anon;
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
revoke all on function public.droit_enseigne(text) from public, anon;
grant execute on function public.droit_enseigne(text) to authenticated;


alter table public.profils
  add column if not exists boutique_id text references public.boutiques(id) on delete set null;
alter table public.profils
  add column if not exists peut_modifier_produits boolean not null default true;
alter table public.commandes add column if not exists paye_le timestamptz;
alter table public.commande_lignes add column if not exists code text not null default '';
alter table public.commande_lignes add column if not exists confirme_le timestamptz;
-- Le verrou plus bas les nomme toutes les deux : s'il s'installait sur
-- une base qui ne les a pas, il lèverait « record "new" has no field »
-- à la première ligne avancée, et la boutique serait à l'arrêt.
alter table public.commande_lignes add column if not exists prix_bizzoo int not null default 0;
alter table public.commande_lignes add column if not exists taux_marge numeric;

-- Le rang accepte désormais « livreur ». Sur une base déjà en service,
-- le corps du « create table » n'est jamais relu : la contrainte s'y
-- repose explicitement, sans quoi aucun livreur ne pourrait être créé.
alter table public.profils drop constraint if exists profils_role_check;
alter table public.profils add constraint profils_role_check
  check (role in ('superadministrateur', 'administrateur', 'moderateur', 'livreur'));

-- L'étape « en livraison » doit exister : c'est là que le livreur
-- emmène la course.
alter table public.commande_lignes drop constraint if exists commande_lignes_etat_check;
alter table public.commande_lignes add constraint commande_lignes_etat_check
  check (etat in ('nouvelle', 'vue', 'preparee', 'en_livraison', 'remise', 'annulee'));

-- Membre de l'équipe qui TIENT la boutique : catalogue, commandes,
-- avis, réclamations.
--
-- LE LIVREUR N'EN EST PAS, et c'est tout l'objet de cette liste. Il a un
-- profil, donc « role_courant() » lui répond — mais il ne tient rien. La
-- version d'avant disait « n'importe quel profil actif », et le jour où
-- le rang « livreur » est arrivé, cela lui aurait ouvert d'un coup :
-- les commandes de toute la boutique, le journal, les chiffres de
-- vente, le dépôt de photos. Rien de tout cela n'est son travail.
--
-- Une seule fonction à corriger plutôt que neuf endroits : c'est
-- justement pour cela qu'elle existe.
create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;

-- Celui qui porte la marchandise, et rien d'autre.
create or replace function public.est_livreur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'livreur', false);
$$;

-- Peut-il retoucher un produit déjà au catalogue ? Les deux rangs
-- d'administrateur toujours ; le modérateur seulement si on le lui accorde.
--
-- « est_equipe() » EN PREMIER, et ce n'est pas une précaution de style :
-- « peut_modifier_produits » vaut VRAI par défaut sur tout profil. Sans
-- cette condition, un livreur qu'on vient de créer pourrait modifier le
-- catalogue — la colonne lui aurait dit oui.
create or replace function public.peut_modifier_produits() returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when public.est_super() then true
    when public.est_compte_enseigne() then public.droit_enseigne('produits')
    else public.est_equipe()
     and coalesce((select role = 'administrateur' or peut_modifier_produits
                     from public.profils where id = auth.uid() and actif), false)
  end;
$$;

-- La boutique à laquelle le compte est rattaché. Null pour un
-- administrateur : il n'est enfermé nulle part.
create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils where id = auth.uid() and actif;
$$;

-- A-t-il le droit de toucher à ce qui appartient à cette boutique-là ?
-- Le superadministrateur partout ; les autres dans la leur seulement.
create or replace function public.peut_agir_sur(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.est_compte_enseigne()
      or (public.est_equipe() and cible is not null
          and cible = public.boutique_du_compte());
$$;

-- Droits d'administration SUR cette boutique-là : le superadministrateur
-- partout, l'administrateur uniquement chez lui.
create or replace function public.administre(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.droit_enseigne('boutiques')
      or (public.est_admin() and cible is not null
          and cible = public.boutique_du_compte());
$$;

-- Les règles de sécurité, y compris celles du stockage des photos,
-- appellent ces fonctions au nom du compte connecté.
grant execute on function public.peut_modifier_produits() to authenticated;
grant execute on function public.role_courant() to authenticated;
grant execute on function public.est_admin() to authenticated;
grant execute on function public.est_equipe() to authenticated;
revoke all on function public.est_livreur() from public, anon, authenticated;
grant execute on function public.est_livreur() to authenticated;
grant execute on function public.boutique_du_compte() to authenticated;
grant execute on function public.peut_agir_sur(text) to authenticated;
-- ---------- À qui cette livraison est confiée ----------
-- Sur la LIGNE, pas sur la commande : une commande peut traverser deux
-- boutiques, qui livrent chacune la sienne, chacune par son livreur.
alter table public.commande_lignes add column if not exists livreur_id uuid;
create index if not exists lignes_livreur on public.commande_lignes(livreur_id)
  where livreur_id is not null;

-- ET LE VERROU QUI VA AVEC, dans le MÊME fichier. Une base Supabase
-- donne « grant all » d'office à « authenticated » sur toute table du
-- schéma public : poser la colonne sans poser le verrou, ce serait
-- laisser n'importe quelle écriture sur la ligne se désigner porteuse
-- de la marchandise — et lui livrer du même coup le nom, le téléphone
-- et l'adresse du client, fût-il d'une autre boutique.
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

  -- CONFIER UNE LIVRAISON passe par « assigner_livreur », qui pose ce
  -- drapeau après avoir vérifié que celui qui confie tient bien la
  -- boutique, et que celui à qui l'on confie est bien son livreur.
  -- Sans lui, n'importe quelle écriture sur la ligne pourrait se
  -- désigner porteuse de la marchandise.
  if coalesce(current_setting('bizzoo.livraison', true), '') <> 'oui'
     and new.livreur_id is distinct from old.livreur_id then
    raise exception 'Une livraison se confie depuis le compte de la boutique';
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

-- ET LA SECONDE SERRURE. Le retrait d'abord, sans quoi la ligne
-- suivante n'ajoute rien : chaque table du schéma public naît avec
-- « grant all » pour « authenticated », et un droit de colonne posé
-- par-dessus n'en retire aucun. L'équipe avance l'état de sa ligne,
-- et rien d'autre.
revoke update on public.commande_lignes from authenticated;
grant update (etat) on public.commande_lignes to authenticated;

-- Le livreur
-- =========================================================
-- Il porte la marchandise, et c'est tout. Ce qu'il doit savoir : QUOI
-- porter, À QUI, et OÙ. Ce qu'il ne doit pas savoir : ce que la
-- boutique touche, ce que l'enseigne garde, ce que le client a payé.
--
-- D'OÙ UNE FONCTION, ET PAS UNE RÈGLE RLS. Une règle décide quelles
-- LIGNES on voit ; elle les rend alors ENTIÈRES, prix BIZZOO compris.
-- Seule une fonction « security definer » peut choisir les colonnes —
-- c'est la même raison qui avait imposé des droits par colonne pour
-- l'historique du client.

-- Les livreurs de la boutique, pour que celle-ci puisse choisir.
-- ON CHOISIT UN LIVREUR PAR SON NOM, pas par son adresse e-mail.
-- « porteur@impact.bj » ne dit pas qui c'est ; « Rohim » si. Et son
-- NUMÉRO part avec : quand le client n'est pas chez lui, c'est le
-- livreur qu'on rappelle, et on ne va pas le chercher ailleurs.
--
-- « drop » AVANT « create or replace » : changer les colonnes rendues
-- par une fonction n'est pas un remplacement aux yeux de PostgreSQL,
-- qui refuse net. Sans cette ligne, le fichier s'arrêterait sur une
-- base déjà en service — et seulement sur celle-là.
drop function if exists public.livreurs_boutique();
create or replace function public.livreurs_boutique()
returns table (id uuid, email text, nom text, tel text, actif boolean)
language plpgsql stable security definer set search_path = public as $$
declare cible text := public.boutique_du_compte();
begin
  if not public.est_equipe() then return; end if;
  return query
    select p.id, coalesce(p.email, '')::text,
           coalesce(p.nom, '')::text, coalesce(p.tel, '')::text, p.actif
      from public.profils p
     where p.role = 'livreur'
       -- L'enseigne les voit tous, les comptes de BIZZOO aussi ;
       -- une boutique, les siens.
       and (public.est_super() or public.est_compte_enseigne()
            or (cible is not null and p.boutique_id = cible))
     -- Par nom quand il y en a un, par adresse sinon : une liste
     -- rangée par e-mail alors qu'on lit des noms paraît en désordre.
     order by nullif(p.nom, '') nulls last, p.email;
end $$;
revoke all on function public.livreurs_boutique() from public, anon;
grant execute on function public.livreurs_boutique() to authenticated;

-- ---------- Confier une livraison ----------
-- LA BOUTIQUE CONFIE, et seulement à SON livreur. Confier à celui de la
-- boutique d'à côté reviendrait à lui remettre le nom, le numéro et
-- l'adresse d'un client qui n'est pas le sien.
--
-- On ne confie que ce qui est PRÊT : une commande pas encore préparée
-- n'a rien à donner à porter.
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
            or p.boutique_id = public.boutique_du_compte());
    if rang is distinct from 'livreur' then
      raise exception 'Ce compte n''est pas un livreur de votre boutique';
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

-- ---------- Ce que le livreur a à porter ----------
-- SES courses, et rien que les siennes. Pas celles de son collègue, pas
-- celles des autres boutiques — et AUCUN montant : ni le prix BIZZOO,
-- ni le prix payé. Regardez la liste des colonnes rendues : elle est la
-- réponse entière à « que voit un livreur ? ».
create or replace function public.mes_livraisons()
returns table (
  commande_id text, numero text,
  boutique_id text, nom_boutique text,
  client_nom text, client_tel text, client_indicatif text,
  client_adresse text, note text,
  etat text, articles jsonb, paye_le timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare moi uuid := auth.uid();
begin
  if moi is null or not public.est_livreur() then return; end if;
  return query
    select c.id, c.numero,
           l.boutique_id,
           coalesce((select b.nom from public.boutiques b where b.id = l.boutique_id), '')::text,
           c.client_nom, c.client_tel, c.client_indicatif,
           c.client_adresse, c.note,
           -- L'étape la MOINS avancée de ses lignes : c'est elle qui dit
           -- ce qu'il lui reste à faire.
           min(l.etat)::text,
           jsonb_agg(jsonb_build_object(
             'nom', l.nom, 'code', l.code, 'quantite', l.quantite)
             order by l.nom),
           c.paye_le
      from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
     where l.livreur_id = moi
       and c.etat = 'payee'
       and l.etat in ('preparee', 'en_livraison', 'remise')
       -- Une course remise depuis plus de deux jours n'a plus à
       -- encombrer sa liste.
       and (l.etat <> 'remise' or c.paye_le > now() - interval '2 days')
     group by c.id, c.numero, l.boutique_id, c.client_nom, c.client_tel,
              c.client_indicatif, c.client_adresse, c.note, c.paye_le
     order by c.paye_le;
end $$;
revoke all on function public.mes_livraisons() from public, anon;
grant execute on function public.mes_livraisons() to authenticated;

-- ---------- Le livreur avance sa course ----------
-- DEUX ÉTAPES, ET PAS D'AUTRES : « je l'ai prise » et « je l'ai
-- remise ». Préparer reste à la boutique ; annuler aussi.
--
-- Et seulement SES lignes. Un livreur qui pourrait avancer celles d'un
-- collègue déclarerait remises des commandes qu'il n'a jamais portées.
create or replace function public.avancer_livraison(
  commande text, boutique text, vers text)
returns int
language plpgsql security definer set search_path = public as $$
declare
  moi     uuid := auth.uid();
  combien int;
  depuis  text;
begin
  if moi is null or not public.est_livreur() then
    raise exception 'Cette course ne vous est pas confiée';
  end if;
  if vers not in ('en_livraison', 'remise') then
    raise exception 'Un livreur prend une course, ou la remet.';
  end if;
  -- On n'avance que dans le bon sens : « remise » ne se pose qu'après
  -- « en livraison ». Sans cela, une course se déclarerait remise sans
  -- jamais avoir été prise.
  depuis := case when vers = 'en_livraison' then 'preparee' else 'en_livraison' end;

  update public.commande_lignes l
     set etat = vers
   where l.commande_id = commande
     and l.boutique_id = boutique
     and l.livreur_id = moi
     and l.etat = depuis;
  get diagnostics combien = row_count;

  if combien = 0 then
    raise exception 'Rien à avancer ici : cette course n''en est pas là.';
  end if;
  return combien;
end $$;
revoke all on function public.avancer_livraison(text, text, text) from public, anon;
grant execute on function public.avancer_livraison(text, text, text) to authenticated;

-- ---------- Vérification ----------
-- Vos livreurs, et ce qu'on leur a confié. Aucun livreur encore créé ?
-- Zéro ligne, et c'est normal : vous en créez depuis Comptes.
select p.email                                       as "Livreur",
       coalesce(b.nom, '—')                          as "Boutique",
       case when p.actif then 'actif' else 'désactivé' end as "État",
       count(l.id) filter (where l.etat = 'en_livraison') as "En cours",
       count(l.id) filter (where l.etat = 'remise')       as "Remises"
  from public.profils p
  left join public.boutiques b on b.id = p.boutique_id
  left join public.commande_lignes l on l.livreur_id = p.id
 where p.role = 'livreur'
 group by p.email, b.nom, p.actif
 order by p.email;
