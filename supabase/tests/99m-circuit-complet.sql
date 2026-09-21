-- =========================================================
-- Le circuit d'une commande, de l'achat à la confirmation
--
-- CE QUE CET ESSAI FAIT, ET QUE LES AUTRES NE FONT PAS. Chaque
-- chantier a son banc : le paiement, le cycle, le livreur, les
-- notifications. Chacun est vert. Mais un circuit peut être
-- rompu ENTRE deux chantiers verts — c'est même là qu'il se
-- rompt, parce que personne ne regarde la jointure.
--
-- On parcourt donc UNE SEULE commande d'un bout à l'autre, et à
-- chaque cran on vérifie DEUX choses ensemble :
--
--   1. l'état a bien avancé, et le client le lit ;
--   2. la notification qui va avec est bien partie, chez les
--      bonnes personnes.
--
-- SI UN SEUL CRAN N'A PAS SA NOTIFICATION, quelqu'un attend
-- devant un écran qui ne bouge pas. C'est exactement le genre
-- de trou qu'aucun banc de chantier ne voit.
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

-- ---------------------------------------------------------
select essai.titre('Cran 0 — le client achète');

insert into auth.users (id, email) values (:PORTEUR::uuid, 'porteur@impact.bj')
on conflict do nothing;
insert into public.profils (id, email, nom, tel, role, boutique_id, actif) values
  (:PORTEUR::uuid, 'porteur@impact.bj', 'Rohim', '0197000011',
   'livreur', 'bou_informatique', true)
on conflict (id) do update
   set role = 'livreur', boutique_id = 'bou_informatique', actif = true,
       nom = excluded.nom, tel = excluded.tel;

insert into public.produits
  (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_circuit', 'bou_informatique', 'Chargeur rapide', 6000,
        'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true;

select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97222222"}'::jsonb,
  '[{"produit_id":"prod_circuit","quantite":1}]'::jsonb) ->> 'id' as cmd \gset
reset role;
select essai.personne();

select essai.egal((select etat from public.commandes where id = :'cmd'),
  'a_payer', 'la commande attend son paiement');
select essai.egal(
  (select count(*)::int from public.notifications where commande_id = :'cmd'), 0,
  'et personne n''est encore dérangé');

-- ---------------------------------------------------------
select essai.titre('Cran 1 — le paiement');

select public.marquer_payee(:'cmd', 'TRX-CIRCUIT',
  (select total from public.commandes where id = :'cmd'), 'feexpay') as e \gset

select essai.egal((select etat from public.commandes where id = :'cmd'),
  'payee', 'la commande est payée');
select essai.egal(
  (select etat from public.commande_lignes where commande_id = :'cmd'),
  'nouvelle', 'sa ligne part de « nouvelle »');
select essai.verifie(
  (select count(*) from public.notifications
    where commande_id = :'cmd' and type = 'commande_payee'
      and destinataire in (:KOFI::uuid, :CHEF::uuid, :ENSEIGNE::uuid)) = 3,
  'client, boutique et enseigne sont prévenus');

select id as lig from public.commande_lignes where commande_id = :'cmd' \gset

-- ---------------------------------------------------------
select essai.titre('Cran 2 — la boutique la voit');

select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'vue' where id = :'lig';
reset role; select essai.personne();

select essai.egal((select etat from public.commande_lignes where id = :'lig'),
  'vue', 'la ligne est vue');
-- « VUE » NE PRÉVIENT PERSONNE, et c'est voulu : le client n'a que
-- faire de savoir qu'on a ouvert son écran. Ce constat le fige — si
-- une notification y apparaissait un jour, elle serait délibérée.
select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'cmd' and destinataire = :KOFI::uuid), 1,
  'le client n''est pas dérangé pour cela');

-- ---------------------------------------------------------
select essai.titre('Cran 3 — le colis est prêt');

select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'preparee' where id = :'lig';
reset role; select essai.personne();

select essai.egal((select etat from public.commande_lignes where id = :'lig'),
  'preparee', 'la ligne est préparée');
select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'cmd' and type = 'commande_preparee'
      and destinataire = :KOFI::uuid), 1,
  'et le client est prévenu que son colis est prêt');

-- ---------------------------------------------------------
select essai.titre('Cran 4 — la course est confiée');

-- ON CONFIE PAR LA FONCTION, comme l'application. Un « update » direct
-- serait refusé par le verrou de la ligne, et l'essai serait passé à
-- côté de tout le chemin.
select essai.devenir(:CHEF::uuid); set role authenticated;
select public.assigner_livreur(:'cmd', 'bou_informatique', :PORTEUR::uuid) as n \gset
reset role; select essai.personne();

select essai.egal(
  (select livreur_id from public.commande_lignes where id = :'lig'),
  :PORTEUR::uuid, 'la ligne porte le livreur');
select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'cmd' and type = 'course_confiee'
      and destinataire = :PORTEUR::uuid), 1,
  'et le livreur est prévenu');

-- IL LA VOIT DANS SES COURSES — le lien de la notification l'y envoie,
-- et un écran vide au bout du lien serait pire que pas de lien.
select essai.devenir(:PORTEUR::uuid); set role authenticated;
select essai.verifie(
  (select count(*) from public.mes_livraisons()
    where commande_id = :'cmd') = 1,
  'elle paraît bien dans ses livraisons');
reset role; select essai.personne();

-- ET TOUJOURS AUCUN MONTANT. C'est la règle du rôle livreur, et on la
-- revérifie ICI parce que c'est ici qu'elle se déferait sans qu'on
-- voie : au moment où l'on ajoute une colonne « bien pratique » à la
-- liste des courses.

select essai.verifie(
  pg_get_function_result('public.mes_livraisons()'::regprocedure) !~* '(prix|total|montant|marge)',
  'et sa liste de courses ne porte aucun montant');

-- ---------------------------------------------------------
select essai.titre('Cran 5 — le colis part');

select essai.devenir(:PORTEUR::uuid); set role authenticated;
select public.avancer_livraison(:'cmd', 'bou_informatique', 'en_livraison') as n \gset
reset role; select essai.personne();

select essai.egal((select etat from public.commande_lignes where id = :'lig'),
  'en_livraison', 'la ligne est en livraison');
select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'cmd' and type = 'commande_en_livraison'
      and destinataire = :KOFI::uuid), 1,
  'le client sait que son colis est en route');
select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'cmd' and type = 'commande_en_livraison'
      and destinataire = :CHEF::uuid), 1,
  'la boutique aussi');

-- ---------------------------------------------------------
select essai.titre('Cran 6 — le colis est remis');

select essai.devenir(:PORTEUR::uuid); set role authenticated;
select public.avancer_livraison(:'cmd', 'bou_informatique', 'remise') as n \gset
reset role; select essai.personne();

select essai.egal((select etat from public.commande_lignes where id = :'lig'),
  'remise', 'la ligne est remise');
select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'cmd' and type = 'commande_remise'
      and destinataire = :KOFI::uuid), 1,
  'le client est invité à confirmer');

-- ---------------------------------------------------------
select essai.titre('Cran 7 — le client confirme, la boutique l''apprend');

select essai.devenir(:KOFI::uuid); set role authenticated;
select public.confirmer_reception(:'cmd', 'bou_informatique') as n \gset
reset role; select essai.personne();

select essai.verifie(
  (select confirme_le from public.commande_lignes where id = :'lig') is not null,
  'la ligne porte l''accusé de réception');
select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'cmd' and type = 'reception_confirmee'
      and destinataire = :CHEF::uuid), 1,
  'LA BOUTIQUE reçoit la confirmation — c''était la demande d''origine');

-- ---------------------------------------------------------
select essai.titre('Le circuit entier : aucun cran muet');

-- LE CONSTAT QUI TIENT TOUT LE RESTE. On liste les crans qui DOIVENT
-- prévenir quelqu'un, et on vérifie qu'aucun n'est passé en silence.
-- Un cran muet, c'est quelqu'un devant un écran qui ne bouge pas.
select essai.egal(
  (select string_agg(distinct type, ',' order by type)
     from public.notifications where commande_id = :'cmd'),
  'commande_en_livraison,commande_payee,commande_preparee,commande_remise,' ||
  'course_confiee,reception_confirmee',
  'les six crans parlants ont tous parlé');

-- Et le client a suivi toute la course sans rien demander.
select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'cmd' and destinataire = :KOFI::uuid), 4,
  'le client a été prévenu quatre fois : payé, prêt, parti, livré');

-- LE SUPERADMINISTRATEUR N'A ÉTÉ DÉRANGÉ QU'UNE FOIS. Si ce nombre
-- monte un jour, c'est que quelqu'un a rebranché les crans
-- intermédiaires sur lui — et sa pastille ne redescendra plus.
select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'cmd' and destinataire = :ENSEIGNE::uuid), 1,
  'et le superadministrateur une seule : le paiement');

-- ---------------------------------------------------------
select essai.titre('Ce que le client lit de son côté');

select essai.devenir(:KOFI::uuid); set role authenticated;
-- IL LIT SA COMMANDE PAR LA TABLE, comme l'application : c'est la
-- règle « commandes lecture client » qui la lui rend, pas une fonction.
-- Si elle se refermait, l'historique serait vide alors que tout le
-- reste serait vert — et la barre de suivi n'aurait plus rien à
-- afficher.
select essai.egal(
  (select count(*)::int from public.commandes where id = :'cmd'), 1,
  'sa commande est bien dans son historique');
-- ET SES LIGNES AVEC, sans quoi la barre ne saurait pas où en est le
-- colis : c'est l'état de la LIGNE qui la remplit, pas celui de la
-- commande.
select essai.egal(
  (select etat from public.commande_lignes where commande_id = :'cmd'),
  'remise', 'et l''état de sa ligne, qui remplit la barre de suivi');
select essai.verifie(
  (select confirme_le from public.commande_lignes where commande_id = :'cmd')
    is not null,
  'avec l''accusé qu''il vient de poser');

-- CE QU'IL NE LIT PAS. La barre se remplit sans jamais lui montrer ce
-- que la boutique touche : le prix BIZZOO reste fermé, même sur sa
-- propre commande.
do $$
begin
  perform prix_bizzoo from public.commande_lignes limit 1;
  perform essai.echec('ÉCHEC : le client lit le prix BIZZOO de sa ligne');
exception
  when sqlstate 'BZ001' then raise;
  when insufficient_privilege then
    raise notice '  ok    et jamais le prix BIZZOO — refusé : %', left(sqlerrm, 44);
end $$;
reset role; select essai.personne();
