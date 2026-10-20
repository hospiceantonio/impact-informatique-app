-- =========================================================
-- Le parcours de livraison (3.59.0)
--
-- Ce qu'on prouve :
--   1. QUAND la boutique confie la course, le livreur reçoit une alerte
--      qui dit : où récupérer le colis, où le livrer, le numéro du
--      destinataire, les frais, le déjà-payé, ce qu'il reste à récupérer ;
--      son écran « Mes courses » rend la même fiche ;
--   2. le client ne voit pas encore son livreur ;
--   3. « REÇU » : seul le livreur de la course l'accepte ; le client
--      reçoit alors le nom et le numéro du livreur, la boutique est
--      prévenue ; et le client voit son livreur sur le reçu ;
--   4. personne n'écrit « Reçu » à la main ; une course confiée à un
--      autre livreur repart de zéro.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set LIV1     '''bebebebe-0000-0000-0000-000000000001'''
\set LIV2     '''bebebebe-0000-0000-0000-000000000002'''

select essai.titre('Le décor : une boutique à 30 % d''acompte, deux livreurs');
insert into auth.users (id, email) values
  (:LIV1::uuid, 'liv1.parcours@essai.bj'), (:LIV2::uuid, 'liv2.parcours@essai.bj')
on conflict do nothing;
update public.profils set role = 'livreur', actif = true, boutique_id = 'bou_informatique', nom = 'Rachidi',
       tel = '0196777888' where id = :LIV1::uuid;
update public.profils set role = 'livreur', actif = true, boutique_id = 'bou_informatique', nom = 'Bio',
       tel = '0196777999' where id = :LIV2::uuid;
insert into public.positions_livreurs (profil_id, latitude, longitude, adresse) values
  (:LIV1::uuid, 6.37, 2.42, 'Cadjèhoun'), (:LIV2::uuid, 6.36, 2.41, 'Gbégamey')
on conflict (profil_id) do nothing;
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set mode_paiement = 'acompte', taux_acompte = 30, frais_livraison = 1000,
       adresse = 'Ganhi, rue du marché', ouvertures = null where id = 'bou_informatique';
reset role; select essai.personne();
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_parcours', 'bou_informatique', 'Imprimante', 9000, 'sc_hightech_accessoires', 20, true)
on conflict (id) do update set stock = 20, disponible = true, prix = 9000;

select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666005","adresse":"Fidjrossè, près de l''église"}'::jsonb,
  '[{"produit_id":"prod_parcours","quantite":1}]'::jsonb, '', true, true) ->> 'id' as cmd \gset
reset role; select essai.personne();
-- 9 000 + 1 000 = 10 000 ; 30 % = 3 000 maintenant, 7 000 à la livraison.
select public.marquer_payee(:'cmd', 'TRX-PARCOURS', 3000, 'feexpay') as p \gset
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'preparee' where commande_id = :'cmd';
select public.assigner_livreur(:'cmd', 'bou_informatique', :LIV1::uuid) as n \gset
reset role; select essai.personne();

select essai.titre('1. L''alerte du livreur dit tout');
select n.corps as alerte from public.notifications n
 where n.destinataire = :LIV1::uuid and n.commande_id = :'cmd' and n.type = 'course_confiee' \gset
select essai.verifie(:'alerte' like '%Récupérer : %Ganhi, rue du marché%', 'où récupérer : la boutique et son adresse');
select essai.verifie(:'alerte' like '%Livrer à : Afi — Fidjrossè, près de l''église%', 'où livrer : le nom et l''adresse');
select essai.verifie(:'alerte' like '%Destinataire : +229 97666005%', 'le numéro du destinataire');
select essai.verifie(:'alerte' like '%Frais de livraison : 1 000 FCFA%', 'les frais de livraison');
select essai.verifie(:'alerte' like '%Déjà payé : 3 000 FCFA%', 'ce que le client a déjà payé');
select essai.verifie(:'alerte' like '%Reste à payer par MoMoPay : 7 000 FCFA (pas d''espèces)%', 'ce qu''il reste à payer, par MoMoPay');
select essai.verifie(:'alerte' not like '%9 000%', 'pas le prix des articles');

select essai.devenir(:LIV1::uuid); set role authenticated;
select essai.egal((select (fiche ->> 'a_encaisser')::int || '/' || (fiche ->> 'deja_paye')::int || '/' ||
                          (fiche -> 'retrait' ->> 'adresse')
                     from public.mes_livraisons() where commande_id = :'cmd'),
  '7000/3000/Ganhi, rue du marché', '« Mes courses » rend la même fiche');
select essai.egal((select recu_le is null from public.mes_livraisons() where commande_id = :'cmd'), true,
  'pas encore acceptée');
reset role; select essai.personne();

select essai.titre('2. Le client ne voit pas encore son livreur');
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.livreurs_de_ma_commande(:'cmd')), 0,
  'confiée, pas encore acceptée : rien à montrer');
reset role; select essai.personne();

select essai.titre('3. « Reçu »');
select essai.devenir(:LIV2::uuid); set role authenticated;
select essai.refuse(format($$select public.accepter_course(%L, 'bou_informatique')$$, :'cmd'),
  'un autre livreur ne l''accepte pas à sa place');
reset role; select essai.personne();
select essai.devenir(:LIV1::uuid); set role authenticated;
select public.accepter_course(:'cmd', 'bou_informatique') as r \gset
select public.accepter_course(:'cmd', 'bou_informatique') as r2 \gset
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ACHETEUR::uuid and commande_id = :'cmd' and type = 'course_acceptee'
                      and titre = 'Votre livreur : Rachidi' and corps like '%+229 0196777888%'), 1,
  'le client reçoit le nom et le numéro de son livreur — une fois, même touché deux fois');
select essai.egal((select count(*)::int from public.notifications
                    where commande_id = :'cmd' and type = 'course_acceptee'
                      and destinataire = :CHEF::uuid), 1, 'la boutique est prévenue');
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.egal((select nom || ' / ' || telephone from public.livreurs_de_ma_commande(:'cmd')),
  'Rachidi / 0196777888', 'le reçu du client montre son livreur');
reset role; select essai.personne();

select essai.titre('4. Personne n''écrit « Reçu » à la main ; un autre livreur repart de zéro');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse(format($$update public.commande_lignes set recu_le = null where commande_id = %L$$, :'cmd'),
  'la boutique n''efface pas « Reçu »');
select public.assigner_livreur(:'cmd', 'bou_informatique', :LIV2::uuid) as n2 \gset
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.commande_lignes where commande_id = :'cmd' and recu_le is null), 1,
  'confiée à Bio : à lui d''accepter');
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.livreurs_de_ma_commande(:'cmd')), 0,
  'et le client ne voit plus l''ancien livreur');
reset role; select essai.personne();

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set taux_acompte = 10, adresse = '' where id = 'bou_informatique';
reset role; select essai.personne();
