-- =========================================================
-- Le livreur de BIZZOO : il porte pour toutes les boutiques
--
-- CE QU'ON AJOUTE. Jusqu'ici un livreur appartenait à UNE
-- boutique. Un porteur qui fait la tournée de toute l'enseigne
-- n'avait pas de place. Désormais, un livreur rattaché à
-- AUCUNE boutique est un livreur de BIZZOO.
--
-- ET C'EST LÀ QUE C'EST DÉLICAT : « aucune boutique » veut
-- DÉJÀ dire quelque chose dans cette base. Pour un
-- administrateur ou un modérateur, c'est un compte d'enseigne —
-- quelqu'un qui regarde par-dessus TOUTES les boutiques.
-- Le même vide sur un livreur ne doit surtout pas vouloir dire
-- la même chose, sans quoi le porteur se retrouverait avec les
-- commandes, les chiffres et le catalogue de l'enseigne entière.
--
-- Cinq choses à prouver :
--
--   1. LA BOUTIQUE LE VOIT, à côté des siens, et sait lequel
--      est lequel ;
--   2. LA BOUTIQUE D'À CÔTÉ LE VOIT AUSSI — c'est tout
--      l'intérêt ; et aucune des deux ne voit le livreur de
--      l'autre ;
--   3. ON PEUT LUI CONFIER UNE COURSE, et il la reçoit ;
--   4. IL N'EST PAS DEVENU UN COMPTE DE BIZZOO : ni commandes,
--      ni catalogue, ni chiffres, et toujours aucun montant ;
--   5. IL AVANCE SA COURSE comme n'importe quel livreur.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set EQUIPE   '''33333333-3333-3333-3333-333333333333'''
\set KOFI     '''55555555-5555-5555-5555-555555555555'''
\set PORTEUR  '''cccccccc-1111-1111-1111-111111111111'''
\set VOISIN   '''cccccccc-3333-3333-3333-333333333333'''
\set TOURNEE  '''cccccccc-9999-9999-9999-999999999999'''

-- ---------------------------------------------------------
select essai.titre('Le décor : un porteur qui n''est d''aucune boutique');

insert into auth.users (id, email) values
  (:TOURNEE::uuid, 'tournee@bizzoo.bj')
on conflict do nothing;

-- AUCUNE BOUTIQUE, ET C'EST TOUT CE QUI LE DISTINGUE. Même rang que
-- les autres livreurs, même table, même colonnes.
insert into public.profils (id, email, nom, tel, role, boutique_id, actif) values
  (:TOURNEE::uuid, 'tournee@bizzoo.bj', 'Ablo', '0197000099',
   'livreur', null, true)
on conflict (id) do update
   set role = 'livreur', boutique_id = null, actif = true,
       nom = excluded.nom, tel = excluded.tel;

select essai.verifie(
  (select boutique_id is null from public.profils where id = :TOURNEE::uuid),
  'il n''est rattaché à aucune boutique');

-- ---------------------------------------------------------
select essai.titre('1. La boutique le voit, et sait qui il est');

select essai.devenir(:CHEF::uuid); set role authenticated;

-- LES DEUX SORTES SONT LÀ. Son porteur à elle, et celui de BIZZOO.
select essai.verifie(
  exists (select 1 from public.livreurs_boutique()
           where id = :TOURNEE::uuid and not actif is false),
  'le livreur de BIZZOO paraît dans sa liste');
select essai.verifie(
  exists (select 1 from public.livreurs_boutique() where id = :PORTEUR::uuid),
  'et son propre porteur toujours');

-- ET LA LISTE DIT LEQUEL EST LEQUEL. Sans cette colonne, l'écran
-- afficherait deux noms côte à côte sans pouvoir écrire que l'un
-- n'est pas de la maison — et on confierait une course à un inconnu
-- en croyant appeler son porteur.
select essai.verifie(
  (select bizzoo from public.livreurs_boutique() where id = :TOURNEE::uuid),
  'et elle le dit : celui-là est de BIZZOO');
select essai.verifie(
  not (select bizzoo from public.livreurs_boutique() where id = :PORTEUR::uuid),
  'celui-là non');

-- SON NOM ET SON NUMÉRO PARTENT AVEC. C'est sous ce nom qu'on le
-- choisit, et c'est ce numéro qu'on rappelle quand le client n'est
-- pas chez lui.
select essai.egal(
  (select nom || ' / ' || tel from public.livreurs_boutique()
    where id = :TOURNEE::uuid),
  'Ablo / 0197000099', 'avec son nom et son numéro');

-- LES SIENS D'ABORD. On appelle son propre porteur avant de déranger
-- celui de l'enseigne ; une liste qui mélangerait les deux ferait
-- choisir le premier venu.
select essai.verifie(
  (select bool_and(not bizzoo) from (
     select bizzoo, row_number() over () as rang
       from public.livreurs_boutique()) t
    where rang <= (select count(*) from public.livreurs_boutique()
                    where not bizzoo)),
  'et les siens paraissent en premier');

-- CE QU'ELLE NE VOIT TOUJOURS PAS : le porteur de la voisine.
select essai.verifie(
  not exists (select 1 from public.livreurs_boutique() where id = :VOISIN::uuid),
  'le livreur de la boutique voisine reste invisible');

reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('2. La boutique d''à côté le voit aussi');

-- C'EST TOUT L'INTÉRÊT, et c'est le constat qui tomberait si l'on
-- rattachait le livreur de BIZZOO à une boutique « par défaut » :
-- il redeviendrait le porteur d'une seule.
select essai.devenir(:EQUIPE::uuid); set role authenticated;
select essai.verifie(
  exists (select 1 from public.livreurs_boutique() where id = :TOURNEE::uuid),
  'la voisine voit le livreur de BIZZOO');
select essai.verifie(
  exists (select 1 from public.livreurs_boutique() where id = :VOISIN::uuid),
  'et le sien');
select essai.verifie(
  not exists (select 1 from public.livreurs_boutique() where id = :PORTEUR::uuid),
  'mais pas celui de la première boutique');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('3. On peut lui confier une course');

insert into public.produits
  (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_tournee', 'bou_informatique', 'Clavier', 9000,
        'sc_hightech_accessoires', 10, true)
on conflict (id) do update set stock = 10, disponible = true;

select essai.devenir(:KOFI::uuid); set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97222222","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_tournee","quantite":1}]'::jsonb) ->> 'id' as cmd \gset
reset role; select essai.personne();

select public.marquer_payee(:'cmd', 'TRX-TOURNEE',
  (select total from public.commandes where id = :'cmd'), 'feexpay') as e \gset
select id as lig from public.commande_lignes where commande_id = :'cmd' \gset

select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'preparee' where id = :'lig';

-- ON CONFIE PAR LA FONCTION, comme l'application.
select public.assigner_livreur(:'cmd', 'bou_informatique', :TOURNEE::uuid) as n \gset
select essai.egal(:'n'::int, 1, 'la course est confiée au livreur de BIZZOO');

-- ET LE REFUS TIENT TOUJOURS pour le porteur de la voisine : c'est
-- la moitié de la règle qu'on aurait pu emporter en ouvrant l'autre.
select essai.refuse(
  format($$select public.assigner_livreur(%L, 'bou_informatique', %L::uuid)$$,
    :'cmd', :VOISIN),
  'et le porteur de la boutique voisine reste refusé');
reset role; select essai.personne();

select essai.egal(
  (select livreur_id from public.commande_lignes where id = :'lig'),
  :TOURNEE::uuid, 'la ligne porte bien son nom');

-- IL EST PRÉVENU, comme n'importe quel livreur : une course confiée
-- sans notification, c'est un colis qui attend qu'on pense à lui.
select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'cmd' and type = 'course_confiee'
      and destinataire = :TOURNEE::uuid), 1,
  'et il est prévenu');

-- ---------------------------------------------------------
select essai.titre('4. Il n''est PAS devenu un compte de BIZZOO');

-- LE CONSTAT QUI TIENT TOUT LE RESTE. « Aucune boutique » ouvre les
-- portes de l'enseigne à un administrateur ou à un modérateur. Si le
-- livreur passait par la même porte, on lui aurait donné d'un coup
-- les commandes, le catalogue et les chiffres de QUATRE boutiques —
-- en croyant seulement lui permettre de porter partout.
select essai.devenir(:TOURNEE::uuid); set role authenticated;

select essai.verifie(not public.est_compte_enseigne(),
  'il n''est pas un compte d''enseigne, malgré sa boutique vide');
select essai.verifie(not public.est_equipe(), 'il n''est pas « l''équipe »');
select essai.verifie(public.est_livreur(), 'il est livreur, et rien d''autre');
select essai.verifie(not public.peut_voir_commandes(),
  'il ne suit pas les commandes');
select essai.verifie(not public.peut_voir_finances(), 'ni les chiffres');
select essai.verifie(not public.peut_modifier_produits(),
  'ni ne touche au catalogue');

-- Et les quatre interrupteurs de l'enseigne restent fermés pour lui,
-- quelle que soit la valeur des colonnes sur sa fiche.
select essai.verifie(not public.droit_enseigne('commandes'),
  'aucun interrupteur de BIZZOO ne s''allume pour lui');

-- Par la table, rien non plus.
select essai.egal((select count(*)::int from public.commandes), 0,
  'et la table des commandes lui reste fermée');
select essai.egal((select count(*)::int from public.statistiques_boutique()), 0,
  'comme les chiffres de vente');

-- IL NE VOIT QUE SA COURSE, et sans un franc.
select essai.egal((select count(*)::int from public.mes_livraisons()), 1,
  'sa liste ne contient que la course qu''on lui a confiée');
select essai.verifie(
  pg_get_function_result('public.mes_livraisons()'::regprocedure)
    !~* '(prix|total|montant|marge)',
  'et elle ne porte aucun montant');

-- ---------------------------------------------------------
select essai.titre('5. Il avance sa course comme un autre');

-- ON RELÈVE L'ÉTAT DEPUIS DEHORS, et pas sous son rôle à lui : le
-- livreur ne lit pas « commande_lignes », la règle le lui refuse. Un
-- constat posé sous son rôle ne lirait donc RIEN — et « rien » n'est
-- pas « pas avancé ». Le banc l'a trouvé en me le renvoyant.
select public.avancer_livraison(:'cmd', 'bou_informatique', 'en_livraison') as a \gset
reset role; select essai.personne();
select essai.egal((select etat from public.commande_lignes where id = :'lig'),
  'en_livraison', 'il prend la course');

select essai.devenir(:TOURNEE::uuid); set role authenticated;
select public.avancer_livraison(:'cmd', 'bou_informatique', 'remise') as b \gset
reset role; select essai.personne();
select essai.egal((select etat from public.commande_lignes where id = :'lig'),
  'remise', 'et la remet');

-- LA BOUTIQUE EST PRÉVENUE, alors même que le porteur n'est pas à
-- elle : c'est elle qui doit savoir que son colis est arrivé.
select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'cmd' and type = 'commande_remise'
      and destinataire = :CHEF::uuid), 1,
  'et la boutique l''apprend');

-- CE QU'IL NE PEUT PAS FAIRE : se donner du travail. « De BIZZOO »
-- veut dire qu'on PEUT lui confier une course partout, pas qu'il les
-- prend de lui-même — et « peut_agir_sur » l'en écarte, parce qu'un
-- livreur n'est pas « l'équipe ».
select essai.devenir(:TOURNEE::uuid); set role authenticated;
select essai.refuse(
  format($$select public.assigner_livreur(%L, 'bou_informatique', %L::uuid)$$,
    :'cmd', :TOURNEE),
  'il ne se confie pas une course tout seul');
reset role; select essai.personne();
