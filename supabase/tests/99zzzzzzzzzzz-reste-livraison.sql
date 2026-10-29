-- =========================================================
-- Le reste payé à la livraison, par MoMoPay (3.59.0)
--
-- Ce qu'on prouve :
--   1. PLUS D'ESPÈCES : le livreur ne remet le colis qu'avec le numéro de
--      la transaction MoMoPay, pour le montant dû au franc près ; espèces,
--      autre montant, sans transaction, transaction déjà servie : refusé ;
--      l'ancien « Je l'ai remise » sans paiement : refusé aussi ; un autre
--      livreur ne remet pas à sa place ; personne n'écrit dans la table ;
--   2. le client le voit (suivre_commande), en reçoit la nouvelle, et peut
--      le contester — une fois ; la boutique et BIZZOO sont prévenus ;
--   3. la caisse : le paiement est « à vérifier » ; la boutique le voit,
--      pas celle d'à côté ni un modérateur ; seul BIZZOO le marque
--      vérifié — l'argent est sur son compte ; le livreur n'a rien à
--      rendre, sa caisse reste vide ;
--   4. le livreur lit le code MoMoPay de BIZZOO sur sa fiche.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set LR1      '''cacacaca-0000-0000-0000-000000000001'''
\set LR2      '''cacacaca-0000-0000-0000-000000000002'''
\set MODO     '''cacacaca-0000-0000-0000-000000000003'''
\set VOISIN   '''cacacaca-0000-0000-0000-000000000004'''

-- (3.70.0) Ces essais éprouvent qui PEUT prendre la course : on la fait
-- partir à tous d'un coup (cascade éteinte, la règle d'avant). La cascade
-- au plus proche a ses propres essais (…-cascade-courses.sql).
update public.cascade_reglage set actif = false where id = 1;

select essai.titre('Le décor : une boutique à 30 %, deux livreurs, un modérateur, une boutique voisine');
insert into auth.users (id, email) values
  (:LR1::uuid, 'lr1.reste@essai.bj'), (:LR2::uuid, 'lr2.reste@essai.bj'),
  (:MODO::uuid, 'modo.reste@essai.bj'), (:VOISIN::uuid, 'voisin.reste@essai.bj')
on conflict do nothing;
update public.profils p set role = v.r, actif = true, boutique_id = v.b, nom = v.n, tel = v.t
  from (values (:LR1::uuid, 'livreur', 'bou_informatique', 'Kodjo', '0196200001'),
               (:LR2::uuid, 'livreur', 'bou_informatique', 'Lamine', '0196200002'),
               (:MODO::uuid, 'moderateur', 'bou_informatique', 'Modo', '0196200003'),
               (:VOISIN::uuid, 'administrateur', 'bou_essai_voisine', 'Voisin', '0196200004')) as v(i, r, b, n, t)
 where p.id = v.i;
insert into public.positions_livreurs (profil_id, latitude, longitude, adresse)
select i, 6.37, 2.42, 'Cotonou' from unnest(array[:LR1::uuid, :LR2::uuid]) i
on conflict (profil_id) do nothing;
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set ouvertures = null, mode_paiement = 'acompte', taux_acompte = 30, frais_livraison = 1000
 where id = 'bou_informatique';
reset role; select essai.personne();
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_reste', 'bou_informatique', 'Casque', 9000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true, prix = 9000;

-- 9 000 + 1 000 = 10 000 ; 3 000 en ligne, 7 000 à la livraison.
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666007","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_reste","quantite":1}]'::jsonb, '', true, true) ->> 'id' as cmd \gset
reset role; select essai.personne();
select public.marquer_payee(:'cmd', 'TRX-RESTE-1', 3000, 'feexpay') as p \gset
select essai.devenir(:LR1::uuid); set role authenticated;
select public.prendre_course(:'cmd') as pris \gset
reset role; select essai.personne();
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'preparee' where commande_id = :'cmd';
reset role; select essai.personne();

select essai.titre('1. Plus d''espèces : MoMoPay, avec le numéro de la transaction');
update public.paiement set momopay_code = '123456', momopay_nom = 'BIZZOO SARL' where id = 1;
select essai.devenir(:LR1::uuid); set role authenticated;
select essai.egal((select fiche -> 'momopay' ->> 'code' || '/' || (fiche -> 'momopay' ->> 'nom')
                     from public.mes_livraisons() where commande_id = :'cmd'),
  '123456/BIZZOO SARL', 'sa fiche porte le code MoMoPay de BIZZOO');
select essai.refuse(format($$select public.remettre_course(%L, 'bou_informatique', 7000, 'mobile_money', 'MP1234567')$$, :'cmd'),
  'remettre avant « Je l''ai prise » : refusé');
select public.avancer_livraison(:'cmd', 'bou_informatique', 'en_livraison') as av \gset
select essai.refuse(format($$select public.remettre_course(%L, 'bou_informatique', 7000, 'especes', '')$$, :'cmd'),
  'en espèces : refusé');
select essai.refuse(format($$select public.remettre_course(%L, 'bou_informatique', 7000, 'mobile_money', '')$$, :'cmd'),
  'sans numéro de transaction : refusé');
select essai.refuse(format($$select public.remettre_course(%L, 'bou_informatique', 5000, 'mobile_money', 'MP1234567')$$, :'cmd'),
  '5 000 au lieu de 7 000 : refusé');
select essai.refuse(format($$select public.avancer_livraison(%L, 'bou_informatique', 'remise')$$, :'cmd'),
  'l''ancien « Je l''ai remise », sans paiement : refusé');
select essai.refuse($$insert into public.encaissements (commande_id, boutique_id, montant) values ('x', 'bou_informatique', 1)$$,
  'écrire dans la table à la main : refusé');
reset role; select essai.personne();
select essai.devenir(:LR2::uuid); set role authenticated;
select essai.refuse(format($$select public.remettre_course(%L, 'bou_informatique', 7000, 'mobile_money', 'MP1234567')$$, :'cmd'),
  'un autre livreur ne remet pas à sa place');
reset role; select essai.personne();
select essai.devenir(:LR1::uuid); set role authenticated;
select public.remettre_course(:'cmd', 'bou_informatique', 7000, 'mobile_money', ' mp-1234567 ') as rem \gset
select essai.egal((select fiche -> 'encaisse' ->> 'transaction' from public.mes_livraisons() where commande_id = :'cmd'),
  'MP-1234567', 'sa fiche garde la transaction');
select essai.egal((public.ma_caisse() ->> 'a_remettre')::int, 0, 'sa caisse : rien à rendre, l''argent est chez BIZZOO');
reset role; select essai.personne();
select essai.egal((select etat from public.commande_lignes where commande_id = :'cmd' limit 1), 'remise',
  'le colis est remis');
select essai.egal((select du || '/' || montant || '/' || mode || '/' || transaction_id || '/' || (remis_le is null)
                     from public.encaissements where commande_id = :'cmd'),
  '7000/7000/mobile_money/MP-1234567/true', 'enregistré : 7 000 par MoMoPay, transaction MP-1234567, à vérifier');

select essai.titre('2. Le client le voit, en est prévenu, peut le contester');
select essai.egal((select (s -> 'encaissements' -> 'bou_informatique' ->> 'montant') || '/' || (s ->> 'paye_livraison')
                     from (select public.suivre_commande(:'cmd', '97666007') as s) x),
  '7000/7000', 'son reçu : 7 000 payés à la livraison');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ACHETEUR::uuid and commande_id = :'cmd' and type = 'reste_encaisse'
                      and titre = 'Reste payé : 7 000 FCFA' and corps like '%MoMoPay (transaction MP-1234567)%'), 1,
  'la notification « Reste payé : 7 000 FCFA », par MoMoPay, avec la transaction');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :CHEF::uuid and commande_id = :'cmd' and type = 'reste_encaisse'
                      and titre = 'MoMoPay à vérifier : 7 000 FCFA'), 1,
  'la boutique apprend le paiement, à vérifier');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ENSEIGNE::uuid and commande_id = :'cmd' and type = 'reste_encaisse'), 1,
  'BIZZOO aussi');
select essai.refuse(format($$select public.contester_encaissement(%L, 'bou_informatique', 'faux', '97000000')$$, :'cmd'),
  'un inconnu ne conteste pas');
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.contester_encaissement(:'cmd', 'bou_informatique', 'J''ai payé 5 000 seulement') as ct \gset
select essai.refuse(format($$select public.contester_encaissement(%L, 'bou_informatique', 'encore')$$, :'cmd'),
  'contester deux fois : déjà signalé');
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :CHEF::uuid and commande_id = :'cmd' and type = 'encaissement_conteste'
                      and corps like '%5 000 seulement%'), 1, 'la boutique est prévenue de la contestation');

select essai.titre('3. La caisse : BIZZOO vérifie sur son compte MoMoPay');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.egal((select montant || '/' || mode || '/' || livreur_nom from public.caisse_livreurs() where commande_id = :'cmd'),
  '7000/mobile_money/Kodjo', 'l''administrateur de la boutique voit le paiement MoMoPay');
select id as eid from public.caisse_livreurs() where commande_id = :'cmd' \gset
select essai.refuse(format($$select public.marquer_remis(array[%s]::bigint[])$$, :eid),
  'mais ne le marque pas vérifié : l''argent est sur le compte de BIZZOO');
reset role; select essai.personne();
select essai.devenir(:MODO::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.caisse_livreurs()), 0, 'un modérateur ne voit pas la caisse');
reset role; select essai.personne();
select essai.devenir(:VOISIN::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.caisse_livreurs() where commande_id = :'cmd'), 0,
  'la boutique voisine ne voit pas cet argent');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select public.marquer_remis(array[:eid]::bigint[]) as mr \gset
select essai.refuse(format($$select public.marquer_remis(array[%s]::bigint[])$$, :eid), 'marquer deux fois : refusé');
reset role; select essai.personne();
select essai.egal(:'mr'::int, 1, 'BIZZOO le marque vérifié');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :LR1::uuid and type = 'caisse_remise'), 0,
  'le livreur n''a rien rendu : pas de « Argent bien reçu »');

select essai.titre('4. Une transaction ne sert qu''une fois ; rien de dû, rien à saisir');
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666007","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_reste","quantite":1}]'::jsonb, '', true, true) ->> 'id' as cmd2 \gset
select public.creer_commande('{"nom":"Afi","tel":"97666007","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_reste","quantite":1}]'::jsonb, '', true, true) ->> 'id' as cmd3 \gset
reset role; select essai.personne();
select public.marquer_payee(:'cmd2', 'TRX-RESTE-2', 3000, 'feexpay') as p2 \gset
-- Tout payé en ligne : rien à encaisser à la porte.
select public.marquer_payee(:'cmd3', 'TRX-RESTE-3', 10000, 'feexpay') as p3 \gset
select essai.devenir(:LR1::uuid); set role authenticated;
select public.prendre_course(:'cmd2') as x2 \gset
select public.prendre_course(:'cmd3') as x3 \gset
reset role; select essai.personne();
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'preparee' where commande_id in (:'cmd2', :'cmd3');
reset role; select essai.personne();
select essai.devenir(:LR1::uuid); set role authenticated;
select public.avancer_livraison(:'cmd2', 'bou_informatique', 'en_livraison') as a2 \gset
select public.avancer_livraison(:'cmd3', 'bou_informatique', 'en_livraison') as a3 \gset
select essai.refuse(format($$select public.remettre_course(%L, 'bou_informatique', 7000, 'mobile_money', 'MP-1234567')$$, :'cmd2'),
  'la même transaction pour une autre commande : refusé');
select public.remettre_course(:'cmd2', 'bou_informatique', 7000, 'mobile_money', 'MP7654321') as r2 \gset
select essai.egal((public.remettre_course(:'cmd3', 'bou_informatique', 0, 'aucun', '') ->> 'mode'), 'aucun',
  'tout était payé en ligne : remis sans rien saisir');
reset role; select essai.personne();

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set taux_acompte = 10 where id = 'bou_informatique';
reset role; select essai.personne();
