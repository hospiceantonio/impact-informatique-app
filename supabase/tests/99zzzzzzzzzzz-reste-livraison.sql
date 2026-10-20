-- =========================================================
-- Le reste payé à la livraison (3.59.0)
--
-- Ce qu'on prouve :
--   1. le livreur déclare ce qu'il encaisse en remettant le colis :
--      montant et façon de payer ; un autre montant que le dû demande un
--      motif ; remettre sans déclarer « Je l'ai prise » d'abord : refusé ;
--      un autre livreur ne déclare pas à sa place ; personne n'écrit dans
--      la table à la main ;
--   2. le client le voit (suivre_commande), en reçoit la nouvelle, et peut
--      le contester — une fois ; la boutique et BIZZOO sont prévenus ;
--   3. la caisse : la boutique voit ce qu'on lui doit, pas celle d'à
--      côté ; un modérateur non ; « Argent reçu du livreur » se marque une
--      fois, et le livreur en est prévenu ; sa caisse se vide.
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

select essai.titre('1. Le livreur déclare ce qu''il encaisse');
select essai.devenir(:LR1::uuid); set role authenticated;
select essai.refuse(format($$select public.remettre_course(%L, 'bou_informatique', 7000, 'especes')$$, :'cmd'),
  'remettre avant « Je l''ai prise » : refusé');
select public.avancer_livraison(:'cmd', 'bou_informatique', 'en_livraison') as av \gset
select essai.refuse(format($$select public.remettre_course(%L, 'bou_informatique', 7000, 'cheque')$$, :'cmd'),
  'une façon de payer inconnue : refusée');
select essai.refuse(format($$select public.remettre_course(%L, 'bou_informatique', 5000, 'especes')$$, :'cmd'),
  '5 000 au lieu de 7 000, sans motif : refusé');
select essai.refuse($$insert into public.encaissements (commande_id, boutique_id, montant) values ('x', 'bou_informatique', 1)$$,
  'écrire dans la table à la main : refusé');
reset role; select essai.personne();
select essai.devenir(:LR2::uuid); set role authenticated;
select essai.refuse(format($$select public.remettre_course(%L, 'bou_informatique', 7000, 'especes')$$, :'cmd'),
  'un autre livreur ne déclare pas à sa place');
reset role; select essai.personne();
select essai.devenir(:LR1::uuid); set role authenticated;
select public.remettre_course(:'cmd', 'bou_informatique', 7000, 'especes') as rem \gset
select essai.egal((select fiche -> 'encaisse' ->> 'montant' from public.mes_livraisons() where commande_id = :'cmd'),
  '7000', 'sa fiche le garde : 7 000 encaissés');
select essai.egal((public.ma_caisse() ->> 'a_remettre')::int, 7000, 'sa caisse : 7 000 à remettre');
reset role; select essai.personne();
select essai.egal((select etat from public.commande_lignes where commande_id = :'cmd' limit 1), 'remise',
  'le colis est remis');
select essai.egal((select du || '/' || montant || '/' || mode from public.encaissements where commande_id = :'cmd'),
  '7000/7000/especes', 'enregistré : dû 7 000, encaissé 7 000, en espèces');

select essai.titre('2. Le client le voit, en est prévenu, peut le contester');
select essai.egal((select (s -> 'encaissements' -> 'bou_informatique' ->> 'montant') || '/' || (s ->> 'paye_livraison')
                     from (select public.suivre_commande(:'cmd', '97666007') as s) x),
  '7000/7000', 'son reçu : 7 000 payés à la livraison');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ACHETEUR::uuid and commande_id = :'cmd' and type = 'reste_encaisse'
                      and titre = 'Reste payé : 7 000 FCFA' and corps like '%Kodjo en espèces%'), 1,
  'la notification « Reste payé : 7 000 FCFA », à Kodjo en espèces');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :CHEF::uuid and commande_id = :'cmd' and type = 'reste_encaisse'), 1,
  'la boutique apprend ce que Kodjo a encaissé');
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
select essai.egal((select (public.suivre_commande(:'cmd', '97666007') -> 'encaissements' -> 'bou_informatique' ->> 'conteste')),
  'true', 'et le reçu dit « contesté »');

select essai.titre('3. La caisse');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.egal((select montant || '/' || livreur_nom || '/' || declare from public.caisse_livreurs() where commande_id = :'cmd'),
  '7000/Kodjo/true', 'l''administrateur de la boutique voit : 7 000, Kodjo');
select id as eid from public.caisse_livreurs() where commande_id = :'cmd' \gset
reset role; select essai.personne();
select essai.devenir(:MODO::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.caisse_livreurs()), 0, 'un modérateur ne voit pas la caisse');
select essai.refuse(format($$select public.marquer_remis(array[%s]::bigint[])$$, :eid), 'ni ne la marque');
reset role; select essai.personne();
select essai.devenir(:VOISIN::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.caisse_livreurs() where commande_id = :'cmd'), 0,
  'la boutique voisine ne voit pas cet argent');
reset role; select essai.personne();
select essai.devenir(:CHEF::uuid); set role authenticated;
select public.marquer_remis(array[:eid]::bigint[]) as mr \gset
select essai.refuse(format($$select public.marquer_remis(array[%s]::bigint[])$$, :eid), 'marquer deux fois : refusé');
reset role; select essai.personne();
select essai.egal(:'mr'::int, 1, '« Argent reçu du livreur » : marqué');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :LR1::uuid and type = 'caisse_remise' and titre = 'Argent bien reçu : 7 000 FCFA'), 1,
  'Kodjo est prévenu');
select essai.devenir(:LR1::uuid); set role authenticated;
select essai.egal((public.ma_caisse() ->> 'a_remettre')::int, 0, 'sa caisse est vide');
reset role; select essai.personne();

select essai.titre('Un écart, avec son motif ; une remise sans déclaration');
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666007","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_reste","quantite":1}]'::jsonb, '', true, true) ->> 'id' as cmd2 \gset
select public.creer_commande('{"nom":"Afi","tel":"97666007","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_reste","quantite":1}]'::jsonb, '', true, true) ->> 'id' as cmd3 \gset
reset role; select essai.personne();
select public.marquer_payee(:'cmd2', 'TRX-RESTE-2', 3000, 'feexpay') as p2 \gset
select public.marquer_payee(:'cmd3', 'TRX-RESTE-3', 3000, 'feexpay') as p3 \gset
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
select public.remettre_course(:'cmd2', 'bou_informatique', 6500, 'mobile_money', 'Remise de 500 accordée par la boutique') as r2 \gset
-- Une application d'avant : « Je l'ai remise » sans rien déclarer.
select public.avancer_livraison(:'cmd3', 'bou_informatique', 'remise') as a4 \gset
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :CHEF::uuid and commande_id = :'cmd2' and type = 'reste_encaisse'
                      and corps like '%Écart : il était dû 7 000 FCFA%'), 1, 'l''écart est signalé à la boutique, avec son motif');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.egal((select montant || '/' || mode from public.caisse_livreurs() where commande_id = :'cmd2'),
  '6500/mobile_money', 'la caisse : 6 500 par Mobile Money');
select essai.egal((select (declare)::text || '/' || du from public.caisse_livreurs() where commande_id = :'cmd3'),
  'false/7000', 'la remise sans déclaration apparaît, avec ses 7 000 dus');
reset role; select essai.personne();

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set taux_acompte = 10 where id = 'bou_informatique';
reset role; select essai.personne();
