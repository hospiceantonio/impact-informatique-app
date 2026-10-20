-- =========================================================
-- Un revendeur achète, paie et se fait livrer comme un client (3.59.0)
--
-- Ce qu'on prouve, de bout en bout, avec un revendeur VALIDÉ :
--   1. il commande à ses prix revendeur, avec les frais de livraison ;
--   2. il paie l'acompte en ligne : la commande part aux boutiques et la
--      course est proposée aux livreurs ;
--   3. un livreur la prend ; le revendeur apprend son nom et son numéro ;
--   4. le colis est remis, le reste encaissé, et il confirme l'avoir reçu ;
--   5. sa commande se suit depuis son compte, comme celle d'un client.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set REV      '''e0e0e0e0-0000-0000-0000-000000000001'''
\set LIV      '''e0e0e0e0-0000-0000-0000-000000000002'''

select essai.titre('Le décor : un revendeur validé, un livreur');
insert into auth.users (id, email, phone) values
  (:REV::uuid, '', '2290197555001'), (:LIV::uuid, 'liv.rev@essai.bj', null)
on conflict do nothing;
insert into public.clients (id, nom, tel, indicatif, adresse, type_compte, revendeur_etat)
values (:REV::uuid, 'Mawuli', '0197555001', '229', 'Dantokpa', 'revendeur', 'validee')
on conflict (id) do update set type_compte = 'revendeur', revendeur_etat = 'validee',
  nom = excluded.nom, tel = excluded.tel, adresse = excluded.adresse;
-- Sa position, puis BIZZOO le valide — le vrai chemin.
update public.clients set revendeur_adresse = 'Dantokpa', revendeur_latitude = 6.36,
       revendeur_longitude = 2.43 where id = :REV::uuid;
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select public.valider_revendeur(:REV::uuid, true, '') as v \gset
reset role; select essai.personne();
update public.profils set role = 'livreur', actif = true, boutique_id = 'bou_informatique',
       nom = 'Sena', tel = '0196500002' where id = :LIV::uuid;
insert into public.positions_livreurs (profil_id, latitude, longitude, adresse)
values (:LIV::uuid, 6.37, 2.42, 'Cotonou') on conflict (profil_id) do nothing;
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set actif = true, ouvertures = null, mode_paiement = 'acompte', taux_acompte = 50,
       frais_livraison = 1000 where id = 'bou_informatique';
reset role; select essai.personne();
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_rev_cli', 'bou_informatique', 'Imprimante', 12000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true, prix = 12000;
insert into public.produits_prive (produit_id, prix_grossiste)
values ('prod_rev_cli', 10000) on conflict (produit_id) do update set prix_grossiste = 10000;

select essai.titre('1. Il commande, à ses prix, avec la livraison');
select essai.devenir(:REV::uuid); set role authenticated;
select essai.verifie(public.est_revendeur(), 'c''est bien un revendeur validé');
select public.creer_commande('{"nom":"Mawuli","tel":"97555001","adresse":"Dantokpa, porte 3"}'::jsonb,
  '[{"produit_id":"prod_rev_cli","quantite":1}]'::jsonb, '', true, true) as g \gset
reset role; select essai.personne();
select (:'g'::jsonb ->> 'id') as cmd \gset
select essai.verifie((select c.client_id = :REV::uuid and c.revendeur from public.commandes c where c.id = :'cmd'),
  'la commande est à son compte, marquée « revendeur »');
select essai.verifie((select l.prix < 12000 from public.commande_lignes l where l.commande_id = :'cmd'),
  'au prix revendeur, pas au prix public');
select essai.egal((select frais_livraison::int from public.commandes where id = :'cmd'), 1000,
  'les frais de livraison comptent, comme pour un client');

select essai.titre('2. Il paie : la commande part, la course est proposée');
select public.marquer_payee(:'cmd', 'TRX-REV-CLI', (:'g'::jsonb ->> 'acompte')::int, 'feexpay') as p \gset
select essai.egal((select etat from public.commandes where id = :'cmd'), 'payee', 'commande payée');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :LIV::uuid and commande_id = :'cmd' and type = 'course_proposee'), 1,
  'le livreur reçoit la demande de course');

select essai.titre('3. Un livreur la prend ; le revendeur le sait');
select essai.devenir(:LIV::uuid); set role authenticated;
select public.prendre_course(:'cmd') as pris \gset
reset role; select essai.personne();
select essai.devenir(:REV::uuid); set role authenticated;
select essai.egal((select nom || '/' || telephone from public.livreurs_de_ma_commande(:'cmd')),
  'Sena/0196500002', 'il voit son livreur : nom et numéro');
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :REV::uuid and commande_id = :'cmd' and type = 'course_acceptee'), 1,
  'et en est prévenu');

select essai.titre('4. Livré, payé, reçu');
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'preparee' where commande_id = :'cmd';
reset role; select essai.personne();
select essai.devenir(:LIV::uuid); set role authenticated;
select public.avancer_livraison(:'cmd', 'bou_informatique', 'en_livraison') as av \gset
select (fiche ->> 'a_encaisser')::int as reste from public.mes_livraisons() where commande_id = :'cmd' \gset
select essai.verifie(:'reste'::int > 0, 'il reste un montant à encaisser à la porte');
select public.remettre_course(:'cmd', 'bou_informatique', :'reste'::int, 'mobile_money') as rem \gset
reset role; select essai.personne();
select essai.devenir(:REV::uuid); set role authenticated;
select public.confirmer_reception(:'cmd', 'bou_informatique') as recu \gset
reset role; select essai.personne();
select essai.verifie((select bool_and(confirme_le is not null) from public.commande_lignes where commande_id = :'cmd'),
  'il confirme la réception');

select essai.titre('5. Il suit sa commande depuis son compte');
select essai.devenir(:REV::uuid); set role authenticated;
select essai.egal((select (s ->> 'paye_livraison')::int from (select public.suivre_commande(:'cmd', '97555001') as s) x),
  :'reste'::int, 'son reçu : le reste payé à la livraison');
select essai.egal((select count(*)::int from public.commandes where id = :'cmd'), 1,
  'il lit sa commande');
reset role; select essai.personne();
