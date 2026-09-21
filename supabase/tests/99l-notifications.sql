-- =========================================================
-- Les notifications : qui est prévenu, et qui ne l'est pas
--
-- CE QU'ON DÉFEND ICI. Une notification porte le numéro d'une
-- commande, le nom d'un client, parfois son adresse. Elle
-- traverse donc exactement les mêmes frontières que le reste :
--
--   le CLIENT n'est prévenu que de SES commandes ;
--   une BOUTIQUE n'est prévenue que de ce qui la concerne, et
--     ne voit jamais celles de la boutique d'à côté ;
--   le LIVREUR reçoit ses courses, AUCUN MONTANT, et rien des
--     étapes qui ne le regardent pas ;
--   le SUPERADMINISTRATEUR reçoit l'argent et les incidents,
--     pas les crans intermédiaires de chaque boutique.
--
-- ET PERSONNE N'ÉCRIT ICI. C'est la partie la plus importante :
-- un client qui pourrait s'insérer une notification pourrait
-- s'annoncer une commande livrée. Aucune règle d'insertion
-- n'existe, pour aucun rang — on le vérifie pour le client, la
-- boutique ET le superadministrateur.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set KOFI     '''55555555-5555-5555-5555-555555555555'''
\set PORTEUR  '''cccccccc-1111-1111-1111-111111111111'''
\set ADJOINT  '''dddddddd-1111-1111-1111-111111111111'''

-- ---------------------------------------------------------
select essai.titre('Le décor : une commande de Kofi, chez deux boutiques');

-- Le livreur d'IMPACT et l'adjoint de BIZZOO peuvent ne pas exister si
-- les essais d'à côté n'ont pas tourné : on les pose ici aussi.
insert into auth.users (id, email) values
  (:PORTEUR::uuid, 'porteur@impact.bj'),
  (:ADJOINT::uuid, 'adjoint@bizzoo.bj')
on conflict do nothing;
insert into public.profils (id, email, role, boutique_id, actif, peut_commandes) values
  (:PORTEUR::uuid, 'porteur@impact.bj', 'livreur',        'bou_informatique', true, true),
  (:ADJOINT::uuid, 'adjoint@bizzoo.bj', 'administrateur',  null,              true, true)
on conflict (id) do update
   set role = excluded.role, boutique_id = excluded.boutique_id,
       actif = true, peut_commandes = true;

insert into public.produits
  (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_notif_a', 'bou_informatique',  'Clé USB 64 Go',  5000,
        'sc_hightech_accessoires', 50, true),
       ('prod_notif_b', 'bou_essai_voisine', 'Housse',         3000,
        'sc_hightech_accessoires', 50, true)
on conflict (id) do update
   set prix = excluded.prix, stock = 50, disponible = true;

select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97222222"}'::jsonb,
  '[{"produit_id":"prod_notif_a","quantite":1},
    {"produit_id":"prod_notif_b","quantite":1}]'::jsonb) ->> 'id' as vente \gset
reset role;
select essai.personne();

-- Avant le paiement : rien. Une commande en attente ne prévient
-- personne — elle n'est pas encore une commande.
select essai.egal(
  (select count(*)::int from public.notifications where commande_id = :'vente'), 0,
  'avant paiement, aucune notification');

-- ---------------------------------------------------------
select essai.titre('Le paiement prévient tout le monde — chacun une fois');

select public.marquer_payee(:'vente', 'TRX-NOTIF-1',
  (select total from public.commandes where id = :'vente'), 'feexpay') as encaisse \gset

select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'vente' and type = 'commande_payee'
      and destinataire = :KOFI::uuid), 1,
  'le client est prévenu — une seule fois');

select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'vente' and type = 'commande_payee'
      and destinataire = :CHEF::uuid), 1,
  'la boutique aussi');

select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'vente' and type = 'commande_payee'
      and destinataire = :ADJOINT::uuid), 1,
  'le compte de BIZZOO aussi');

select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'vente' and type = 'commande_payee'
      and destinataire = :ENSEIGNE::uuid), 1,
  'et le superadministrateur : c''est de l''argent qui entre');

-- LE LIVREUR, NON. Rien ne lui a encore été confié.
select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'vente' and destinataire = :PORTEUR::uuid), 0,
  'le livreur, NON : on ne lui a rien confié');

-- ---------------------------------------------------------
select essai.titre('Aucun montant n''entre dans le texte');

-- ON CHERCHE LE MONTANT, PAS LES CHIFFRES. Une première version de ce
-- constat refusait tout nombre à quatre chiffres : elle tombait sur le
-- NUMÉRO de la commande — « BZ-000123 » —, qui a parfaitement sa place
-- dans le texte. Un constat qui se déclenche sur ce qu'on veut garder
-- ne défend rien, il gêne.
--
-- Ce qu'on refuse, c'est le TOTAL de la commande, écrit comme
-- l'application l'écrit : avec ou sans espace des milliers.
select total as montant from public.commandes where id = :'vente' \gset

select essai.egal(
  (select count(*)::int from public.notifications n
    where n.commande_id = :'vente'
      and (position(:'montant' in replace(n.titre || ' ' || n.corps, ' ', '')) > 0
        or position(to_char(:montant, 'FM999G999G999')
                    in (n.titre || ' ' || n.corps)) > 0)), 0,
  'le montant de la commande n''apparaît dans aucune notification');

-- Et le numéro, lui, y est bien : sans ce constat, le précédent serait
-- vert sur des notifications vides de tout.
select essai.verifie(
  (select count(*) from public.notifications n
    join public.commandes c on c.id = n.commande_id
   where n.commande_id = :'vente' and position(c.numero in n.corps) > 0) > 0,
  'le numéro de la commande, lui, y figure bien');

-- ---------------------------------------------------------
select essai.titre('Une boutique n''est prévenue que de SES lignes');

select id as ligne_a from public.commande_lignes
 where commande_id = :'vente' and boutique_id = 'bou_informatique' \gset
select id as ligne_b from public.commande_lignes
 where commande_id = :'vente' and boutique_id = 'bou_essai_voisine' \gset

-- La voisine avance SA ligne. Le chef d'IMPACT ne doit rien en savoir.
update public.commande_lignes set etat = 'vue'      where id = :'ligne_b';
update public.commande_lignes set etat = 'preparee' where id = :'ligne_b';
update public.commande_lignes set etat = 'en_livraison' where id = :'ligne_b';

select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'vente' and destinataire = :CHEF::uuid
      and boutique_id = 'bou_essai_voisine'), 0,
  'le chef d''IMPACT ne reçoit rien de la boutique voisine');

select essai.verifie(
  (select count(*) from public.notifications
    where commande_id = :'vente' and type = 'commande_en_livraison'
      and destinataire = :KOFI::uuid) = 1,
  'le client, lui, sait que son colis est parti');

-- ---------------------------------------------------------
select essai.titre('Trois articles de la même boutique ne font qu''une nouvelle');

-- On remet la ligne d'IMPACT à « préparée » et on la rejoue : l'index
-- unique doit retenir la seconde. Sans lui, une commande de trois
-- articles sonnerait trois fois chez la boutique.
update public.commande_lignes set etat = 'vue'      where id = :'ligne_a';
update public.commande_lignes set etat = 'preparee' where id = :'ligne_a';
update public.commande_lignes set etat = 'vue'      where id = :'ligne_a';
update public.commande_lignes set etat = 'preparee' where id = :'ligne_a';

select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'vente' and type = 'commande_preparee'
      and destinataire = :KOFI::uuid and boutique_id = 'bou_informatique'), 1,
  'deux passages par « préparée » ne font qu''une notification');

-- ---------------------------------------------------------
select essai.titre('La course confiée : le livreur, et lui seul');

select essai.devenir(:CHEF::uuid); set role authenticated;
select public.assigner_livreur(:'vente', 'bou_informatique', :PORTEUR::uuid) as confie \gset
reset role; select essai.personne();

select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'vente' and type = 'course_confiee'
      and destinataire = :PORTEUR::uuid), 1,
  'le livreur est prévenu de sa course');

select essai.egal(
  (select lien from public.notifications
    where commande_id = :'vente' and type = 'course_confiee'
      and destinataire = :PORTEUR::uuid), '#/livraisons',
  'et le doigt le mène à ses livraisons');

select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'vente' and type = 'course_confiee'
      and destinataire = :KOFI::uuid), 0,
  'le client n''a pas à savoir à QUI la course est confiée');

-- ---------------------------------------------------------
select essai.titre('La remise, puis l''accusé de réception');

update public.commande_lignes set etat = 'en_livraison' where id = :'ligne_a';
update public.commande_lignes set etat = 'remise'       where id = :'ligne_a';

select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'vente' and type = 'commande_remise'
      and destinataire = :KOFI::uuid), 1,
  'le client est invité à confirmer');

select essai.devenir(:KOFI::uuid); set role authenticated;
select public.confirmer_reception(:'vente', 'bou_informatique') as signe \gset
reset role; select essai.personne();

-- C'EST LA DEMANDE D'ORIGINE : la boutique doit recevoir la confirmation.
select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'vente' and type = 'reception_confirmee'
      and destinataire = :CHEF::uuid), 1,
  'la boutique reçoit la confirmation de réception');

-- ---------------------------------------------------------
select essai.titre('Le superadministrateur n''est PAS réveillé pour chaque cran');

select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'vente' and destinataire = :ENSEIGNE::uuid
      and type in ('commande_preparee', 'commande_en_livraison',
                   'commande_remise', 'reception_confirmee', 'course_confiee')), 0,
  'aucune étape intermédiaire ne lui parvient');

select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'vente' and destinataire = :ENSEIGNE::uuid), 1,
  'il n''a reçu que le paiement');

-- Et l'adjoint de BIZZOO, lui, suit tout : sans ce constat, le
-- précédent serait vert même si PERSONNE ne suivait les étapes.
select essai.verifie(
  (select count(*) from public.notifications
    where commande_id = :'vente' and destinataire = :ADJOINT::uuid) > 1,
  'l''adjoint de BIZZOO, lui, suit les étapes');

-- ---------------------------------------------------------
select essai.titre('Chacun ne LIT que les siennes');

select essai.devenir(:KOFI::uuid); set role authenticated;
select essai.egal(
  (select count(*)::int from public.notifications where destinataire <> :KOFI::uuid), 0,
  'le client ne voit aucune notification d''un autre');
select essai.verifie(
  (select count(*) from public.notifications) > 0,
  'et il voit bien les siennes');
reset role;

select essai.devenir(:PORTEUR::uuid); set role authenticated;
select essai.egal(
  (select count(*)::int from public.notifications where destinataire <> :PORTEUR::uuid), 0,
  'le livreur non plus');
-- MÊME PRÉCISION QUE PLUS HAUT : on cherche le montant, pas les
-- chiffres. Le numéro de la commande est justement ce qu'il doit lire
-- pour retrouver le colis.
select essai.egal(
  (select count(*)::int from public.notifications n
    where position(:'montant' in replace(n.titre || ' ' || n.corps, ' ', '')) > 0
       or position(to_char(:montant, 'FM999G999G999')
                   in (n.titre || ' ' || n.corps)) > 0), 0,
  'et rien de ce qu''il lit ne porte le montant de la commande');
reset role;

-- ---------------------------------------------------------
select essai.titre('PERSONNE n''écrit ici — ni client, ni boutique, ni enseigne');

-- ON REGARDE LA RÈGLE, PAS SEULEMENT LE REFUS. Un essai qui se
-- contente de constater « l'insertion est refusée » passe au vert pour
-- n'importe quelle raison — et il y en avait une autre ici : la
-- séquence de la clé primaire est fermée elle aussi. Vérifié : en
-- ouvrant « insert » ET en posant une règle permissive, les trois
-- constats de refus restaient VERTS, arrêtés par la séquence.
--
-- Ce qu'on veut dire, c'est qu'AUCUNE RÈGLE D'INSERTION N'EXISTE. Cela
-- se lit dans le catalogue, et nulle part ailleurs.
select essai.egal(
  (select count(*)::int from pg_policies
    where schemaname = 'public' and tablename = 'notifications'
      and cmd = 'INSERT'), 0,
  'aucune règle d''insertion n''existe sur la table');
select essai.egal(
  (select count(*)::int from pg_policies
    where schemaname = 'public' and tablename = 'notifications'
      and cmd = 'DELETE'), 0,
  'ni aucune règle de suppression');
-- Et les deux seules qui existent sont bien celles qu'on a voulues.
select essai.egal(
  (select string_agg(cmd, ',' order by cmd) from pg_policies
    where schemaname = 'public' and tablename = 'notifications'), 'SELECT,UPDATE',
  'il n''y a que « lire » et « marquer lu »');

-- Le refus a l'usage, maintenant : ce que vit vraiment un client.
select essai.devenir(:KOFI::uuid); set role authenticated;
select essai.refuse($$
  insert into public.notifications (destinataire, type, titre, lien)
  values ('55555555-5555-5555-5555-555555555555'::uuid,
          'commande_remise', 'Livré', '#/')
$$, 'et le client ne s''invente pas une commande livrée');
reset role;

select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse($$
  insert into public.notifications (destinataire, type, titre, lien)
  values ('22222222-2222-2222-2222-222222222222'::uuid,
          'reception_confirmee', 'Reçu', '#/')
$$, 'la boutique ne se fabrique pas un accusé de réception');
reset role;

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse($$
  insert into public.notifications (destinataire, type, titre, lien)
  values ('11111111-1111-1111-1111-111111111111'::uuid, 'essai', 'Essai', '#/')
$$, 'le superadministrateur non plus — aucune règle d''insertion n''existe');

-- Ni supprimer : une notification gênante ne s'efface pas.
select essai.sans_effet($$
  delete from public.notifications
$$, 'et il n''en supprime aucune');
reset role;

-- ---------------------------------------------------------
select essai.titre('On ne marque lu que chez soi, et rien d''autre');

select essai.devenir(:KOFI::uuid); set role authenticated;
select essai.egal(public.tout_marquer_lu() > 0, true,
  'le client marque les siennes lues');
select essai.egal(public.mes_notifications_non_lues(), 0,
  'et sa pastille retombe à zéro');
reset role;

-- Celles du chef n'ont pas bougé : c'est ce que « chacun les siennes »
-- veut dire, et un seul compteur partagé l'aurait trahi.
select essai.verifie(
  (select count(*) from public.notifications
    where destinataire = :CHEF::uuid and lue_le is null) > 0,
  'celles de la boutique sont restées non lues');

-- Le titre ne se réécrit pas : seule « lue_le » est ouverte.
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse($$
  update public.notifications set titre = 'Autre chose'
   where destinataire = '22222222-2222-2222-2222-222222222222'::uuid
$$, 'et le texte d''une notification ne se réécrit pas');
reset role;
select essai.personne();
