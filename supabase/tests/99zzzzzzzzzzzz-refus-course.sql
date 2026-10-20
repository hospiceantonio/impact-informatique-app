-- =========================================================
-- Le livreur refuse une course ; la boutique voit qui livre (3.59.0)
--
-- Ce qu'on prouve :
--   1. la boutique voit le livreur de sa course : nom, numéro, accepté
--      ou non ; la boutique voisine ne voit rien ;
--   2. le livreur refuse tant que le colis n'est pas parti : la course
--      redevient libre, la boutique voit « refusée par » avec le motif et
--      en est prévenue ; le client aussi, s'il connaissait son livreur ;
--   3. la demande se rouvre aux autres, pas à celui qui a refusé ; un
--      autre la prend, et le client reçoit bien le NOUVEAU nom ;
--   4. la boutique peut confier à nouveau ; un colis parti ne se refuse
--      plus ; un autre livreur ne refuse pas à la place du sien.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set RF1      '''dededede-0000-0000-0000-000000000001'''
\set RF2      '''dededede-0000-0000-0000-000000000002'''
\set VOISIN   '''dededede-0000-0000-0000-000000000003'''

select essai.titre('Le décor');
insert into auth.users (id, email) values
  (:RF1::uuid, 'rf1.refus@essai.bj'), (:RF2::uuid, 'rf2.refus@essai.bj'), (:VOISIN::uuid, 'voisin.refus@essai.bj')
on conflict do nothing;
update public.profils p set role = v.r, actif = true, boutique_id = v.b, nom = v.n, tel = v.t
  from (values (:RF1::uuid, 'livreur', 'bou_informatique', 'Moussa', '0196300001'),
               (:RF2::uuid, 'livreur', 'bou_informatique', 'Nadia', '0196300002'),
               (:VOISIN::uuid, 'administrateur', 'bou_essai_voisine', 'Voisin', '0196300003')) as v(i, r, b, n, t)
 where p.id = v.i;
insert into public.positions_livreurs (profil_id, latitude, longitude, adresse)
select i, 6.37, 2.42, 'Cotonou' from unnest(array[:RF1::uuid, :RF2::uuid]) i
on conflict (profil_id) do nothing;
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set ouvertures = null where id = 'bou_informatique';
reset role; select essai.personne();
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_refus', 'bou_informatique', 'Souris', 5000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true;
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666008","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_refus","quantite":1}]'::jsonb, '', true, true) ->> 'id' as cmd \gset
reset role; select essai.personne();
select public.marquer_payee(:'cmd', 'TRX-REFUS-1', 600, 'feexpay') as p \gset

select essai.titre('1. La boutique voit qui livre');
select essai.devenir(:RF1::uuid); set role authenticated;
select public.prendre_course(:'cmd') as pris \gset
reset role; select essai.personne();
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.egal((select livreur_nom || '/' || livreur_tel || '/' || (recu_le is not null)
                     from public.livraison_des_commandes(array[:'cmd'])),
  'Moussa/0196300001/true', 'Prise par Moussa, son numéro, acceptée');
reset role; select essai.personne();
select essai.devenir(:VOISIN::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.livraison_des_commandes(array[:'cmd'])), 0,
  'la boutique voisine ne voit rien');
reset role; select essai.personne();
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.livraison_des_commandes(array[:'cmd'])), 0,
  'un client non plus');
reset role; select essai.personne();

select essai.titre('2. Le livreur refuse');
select essai.devenir(:RF2::uuid); set role authenticated;
select essai.refuse(format($$select public.refuser_course(%L)$$, :'cmd'), 'un autre livreur ne refuse pas à sa place');
reset role; select essai.personne();
select essai.devenir(:RF1::uuid); set role authenticated;
select public.refuser_course(:'cmd', 'Ma moto est en panne') as rf \gset
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.commande_lignes where commande_id = :'cmd' and livreur_id is null and recu_le is null),
  (select count(*)::int from public.commande_lignes where commande_id = :'cmd'), 'la course redevient libre');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.egal((select coalesce(livreur_nom, '') || '|' || refus_nom || '|' || refus_motif
                     from public.livraison_des_commandes(array[:'cmd'])),
  '|Moussa|Ma moto est en panne', 'la boutique voit : refusée par Moussa, et pourquoi');
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :CHEF::uuid and commande_id = :'cmd' and type = 'course_refusee'
                      and titre like 'Commande refusée par le livreur%' and corps like '%Ma moto est en panne%'), 1,
  'la boutique est prévenue : « Commande refusée par le livreur »');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ACHETEUR::uuid and commande_id = :'cmd' and type = 'course_refusee'), 1,
  'le client, qui connaissait son livreur, apprend qu''il change');

select essai.titre('3. La demande se rouvre aux autres, pas à lui');
select essai.devenir(:RF1::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.courses_proposees() where commande_id = :'cmd'), 0,
  'Moussa ne la revoit pas');
select essai.refuse(format($$select public.prendre_course(%L)$$, :'cmd'), 'ni ne la reprend');
reset role; select essai.personne();
select essai.devenir(:RF2::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.courses_proposees() where commande_id = :'cmd'), 1,
  'Nadia la voit');
select public.prendre_course(:'cmd') as pris2 \gset
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ACHETEUR::uuid and commande_id = :'cmd' and type = 'course_acceptee'
                      and titre = 'Votre livreur : Nadia'), 1, 'le client reçoit le NOUVEAU nom : Nadia');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ACHETEUR::uuid and commande_id = :'cmd' and type like 'course_acceptee_avant_%'), 1,
  'l''ancienne nouvelle (Moussa) reste lisible, mise de côté');

select essai.titre('4. Confier à nouveau ; un colis parti ne se refuse plus');
select essai.devenir(:RF2::uuid); set role authenticated;
select public.refuser_course(:'cmd', '') as rf2 \gset
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :CHEF::uuid and commande_id = :'cmd' and type = 'course_refusee'), 1,
  'un second refus prévient encore la boutique');
select essai.devenir(:CHEF::uuid); set role authenticated;
select public.assigner_livreur(:'cmd', 'bou_informatique', :RF1::uuid) as re \gset
select essai.egal((select livreur_nom || '/' || (recu_le is null) from public.livraison_des_commandes(array[:'cmd'])),
  'Moussa/true', 'la boutique la confie à nouveau : confiée à Moussa, en attente de sa réponse');
update public.commande_lignes set etat = 'preparee' where commande_id = :'cmd';
reset role; select essai.personne();
select essai.devenir(:RF1::uuid); set role authenticated;
select public.avancer_livraison(:'cmd', 'bou_informatique', 'en_livraison') as av \gset
select essai.refuse(format($$select public.refuser_course(%L)$$, :'cmd'), 'le colis est parti : plus de refus');
reset role; select essai.personne();
