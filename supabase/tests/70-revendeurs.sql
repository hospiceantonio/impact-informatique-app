-- =========================================================
-- Les comptes revendeurs : qui décide, et qui paie quoi.
--
-- Un revendeur validé achète au PRIX BIZZOO — celui que la
-- boutique a annoncé à la création du produit — AUGMENTÉ DE LA
-- MARGE DE L'ENSEIGNE. C'est donc une remise permanente, accordée
-- compte par compte, mais qui rapporte toujours à BIZZOO. Le calcul
-- lui-même est éprouvé ailleurs (98-marge-revendeur.sql) ; ici on
-- force les deux portes dont tout le reste découle :
--
--   1. LE STATUT NE S'ACCORDE PAS SOI-MÊME. Demander est libre ;
--      valider ne l'est pas. Si un client pouvait écrire
--      « revendeur_etat », il s'achèterait le catalogue au prix
--      d'achat de la boutique ;
--   2. LE PRIX NE VIENT PAS DU TÉLÉPHONE. Il est relu dans le
--      catalogue à l'écriture de la ligne, comme le nom et la
--      référence. Ce qui est affiché et ce qui est facturé
--      sortent de la même règle — sinon le client voit un
--      montant et en paie un autre.
--
-- Et une troisième, moins spectaculaire mais tout aussi chère :
-- UN PRIX BIZZOO À ZÉRO N'EST PAS UN PRIX. Un produit dont la
-- boutique n'a rien renseigné doit rester au prix public, sans
-- quoi il partirait gratuitement.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set AWA      '''44444444-4444-4444-4444-444444444444'''
\set KOFI     '''55555555-5555-5555-5555-555555555555'''

select essai.titre('Le décor : un produit à prix BIZZOO, un autre sans');

-- « prod_marge » vient du banc de la marge : vendu 10 000, la boutique
-- en touche 8 000. Au taux de départ — 10 % sur le prix BIZZOO — un
-- revendeur le paie donc 8 800, et l'enseigne garde 800.
insert into public.produits
  (id, boutique_id, nom, prix, categorie_id, stock, disponible)
values ('prod_marge', 'bou_informatique', 'Article à marge', 10000,
        'cat_accessoires', 10, true)
on conflict (id) do update set prix = 10000, stock = 10;
insert into public.produits_prive (produit_id, prix_grossiste)
values ('prod_marge', 8000)
on conflict (produit_id) do update set prix_grossiste = 8000;

-- Et un produit dont personne n'a renseigné le prix BIZZOO. C'est le
-- cas d'un catalogue importé, ou d'une boutique pressée.
insert into public.produits
  (id, boutique_id, nom, prix, categorie_id, stock, disponible)
values ('prod_sans_bizzoo', 'bou_informatique', 'Article sans prix BIZZOO',
        5000, 'cat_accessoires', 10, true)
on conflict (id) do update set prix = 5000, stock = 10;
delete from public.produits_prive where produit_id = 'prod_sans_bizzoo';

select essai.egal((select count(*)::int from public.clients where id = :AWA::uuid), 1,
  'Awa a bien son compte client');

-- ---------------------------------------------------------
select essai.titre('Un client ne s''accorde pas le statut');
-- ---------------------------------------------------------
select essai.devenir(:AWA::uuid);
set role authenticated;

select essai.egal(public.est_revendeur(), false, 'elle n''est pas revendeuse');

select essai.refuse(
  $$update public.clients set revendeur_etat = 'validee'
     where id = '44444444-4444-4444-4444-444444444444'$$,
  'elle se déclare revendeuse validée');
select essai.refuse(
  $$update public.clients set revendeur_decide_par = 'moi-meme'
     where id = '44444444-4444-4444-4444-444444444444'$$,
  'elle signe elle-même la décision');
select essai.refuse(
  $$update public.clients set revendeur_motif = 'accordé'
     where id = '44444444-4444-4444-4444-444444444444'$$,
  'elle s''écrit un motif');

-- Demander, en revanche, est libre : c'est tout le sens du formulaire.
update public.clients
   set type_compte = 'revendeur',
       revendeur_message = 'Boutique Ayaba, marché Dantokpa'
 where id = :AWA::uuid;

reset role;
select essai.personne();

select essai.egal((select revendeur_etat from public.clients where id = :AWA::uuid),
  'en_attente', 'sa demande attend BIZZOO');
select essai.verifie(
  (select revendeur_demande_le is not null from public.clients where id = :AWA::uuid),
  'et elle est datée');

-- ---------------------------------------------------------
select essai.titre('En attendant, elle paie le prix de tout le monde');
-- ---------------------------------------------------------
select essai.devenir(:AWA::uuid);
set role authenticated;

select essai.egal(public.est_revendeur(), false, 'demander n''est pas être');
select essai.egal((select count(*)::int from public.mes_prix()), 0,
  'aucun prix revendeur ne lui est servi');

select public.creer_commande('{"nom":"Awa","tel":"97111111"}'::jsonb,
  '[{"produit_id":"prod_marge","quantite":1}]'::jsonb) ->> 'id' as attente \gset

reset role;
select essai.personne();

select essai.egal((select prix from public.commande_lignes where commande_id = :'attente'),
  10000, 'sa commande part au prix public');
select essai.egal((select revendeur from public.commandes where id = :'attente'),
  false, 'et ne porte pas le régime revendeur');

-- ---------------------------------------------------------
select essai.titre('Seul BIZZOO tranche');
-- ---------------------------------------------------------
-- L'administrateur d'une boutique gère ses produits, pas les comptes
-- de l'enseigne : la remise engage TOUTES les boutiques.
select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.refuse(
  $$select public.valider_revendeur(
      '44444444-4444-4444-4444-444444444444'::uuid, true, '')$$,
  'un administrateur de boutique valide une revendeuse');
select essai.egal((select count(*)::int from public.revendeurs('')), 0,
  'et il ne voit même pas la liste');
reset role;

-- La demandeuse elle-même, encore moins.
select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.refuse(
  $$select public.valider_revendeur(
      '44444444-4444-4444-4444-444444444444'::uuid, true, '')$$,
  'elle se valide elle-même par la fonction');
select essai.egal((select count(*)::int from public.revendeurs('')), 0,
  'et la liste des demandes lui reste fermée');
reset role;

-- Ni un visiteur : la fonction n'est pas ouverte à « anon ».
select essai.personne();
set role anon;
select essai.refuse($$select count(*) from public.mes_prix()$$,
  'un visiteur demande des prix revendeur');
select essai.refuse(
  $$select public.valider_revendeur(
      '44444444-4444-4444-4444-444444444444'::uuid, true, '')$$,
  'un visiteur valide une revendeuse');
reset role;

-- ---------------------------------------------------------
select essai.titre('BIZZOO valide');
-- ---------------------------------------------------------
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;

select essai.egal((select count(*)::int from public.revendeurs('en_attente')), 1,
  'le superadministrateur voit la demande');
select essai.verifie(
  (select message = 'Boutique Ayaba, marché Dantokpa'
     from public.revendeurs('en_attente') limit 1),
  'avec ce que la demandeuse dit de son commerce');
select essai.verifie(
  (select email <> '' from public.revendeurs('en_attente') limit 1),
  'et son adresse e-mail, pour la joindre');

select essai.egal(public.valider_revendeur(:AWA::uuid, true, ''), 'validee',
  'il valide');
reset role;
select essai.personne();

select essai.egal((select revendeur_etat from public.clients where id = :AWA::uuid),
  'validee', 'le compte est validé');
select essai.verifie(
  (select revendeur_decide_par <> '' from public.clients where id = :AWA::uuid),
  'et la décision est signée');

-- ---------------------------------------------------------
select essai.titre('Ce qu''une revendeuse validée voit');
-- ---------------------------------------------------------
select essai.devenir(:AWA::uuid);
set role authenticated;

select essai.egal(public.est_revendeur(), true, 'elle est revendeuse');
select essai.egal(
  (select prix::int from public.mes_prix() where produit_id = 'prod_marge'),
  8800, 'le prix BIZZOO majoré de la marge lui est servi');
-- Le produit sans prix BIZZOO reste au prix public : rien n'est gratuit.
select essai.egal(
  (select prix::int from public.mes_prix() where produit_id = 'prod_sans_bizzoo'),
  5000, 'un produit sans prix BIZZOO garde son prix public');

-- Mais la table des prix d'achat, elle, reste fermée : elle porte aussi
-- les taux de marge de chaque boutique.
select essai.egal((select count(*)::int from public.produits_prive), 0,
  'elle ne lit toujours pas les prix d''achat');
select essai.egal((select count(*)::int from public.produits_prive
                    where produit_id = 'prod_marge'), 0,
  'ni celui du produit qu''elle achète');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Et ce qu''elle paie');
-- ---------------------------------------------------------
select essai.devenir(:AWA::uuid);
set role authenticated;

-- Le panier annonce un prix de 1 franc. La base n'en tient aucun compte.
select public.creer_commande('{"nom":"Awa","tel":"97111111"}'::jsonb,
  '[{"produit_id":"prod_marge","quantite":2,"prix":1}]'::jsonb) ->> 'id' as vente \gset

reset role;
select essai.personne();

select essai.egal((select revendeur from public.commandes where id = :'vente'),
  true, 'la commande porte le régime revendeur');
select essai.egal((select prix from public.commande_lignes where commande_id = :'vente'),
  8800, 'la ligne est facturée au prix revendeur, pas au prix envoyé');
select essai.egal((select prix_bizzoo from public.commande_lignes where commande_id = :'vente'),
  8000, 'et ce que la boutique touche n''a pas bougé');
select essai.egal((select total from public.commandes where id = :'vente'),
  17600, 'le total suit : deux articles à 8 800');
-- Et l'enseigne y gagne : c'est tout l'objet de la marge revendeur.
select essai.verifie((select prix > prix_bizzoo from public.commande_lignes
                       where commande_id = :'vente'),
  'l''enseigne gagne sur cette vente, elle ne vend pas à prix coûtant');

-- Un produit sans prix BIZZOO ne part pas pour rien.
select essai.devenir(:AWA::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Awa","tel":"97111111"}'::jsonb,
  '[{"produit_id":"prod_sans_bizzoo","quantite":1}]'::jsonb) ->> 'id' as gratuite \gset
reset role;
select essai.personne();
select essai.egal((select prix from public.commande_lignes where commande_id = :'gratuite'),
  5000, 'un produit sans prix BIZZOO se facture au prix public');
select essai.verifie((select total > 0 from public.commandes where id = :'gratuite'),
  'et rien ne part gratuitement');

-- ---------------------------------------------------------
select essai.titre('Le client ordinaire, lui, ne change pas de prix');
-- ---------------------------------------------------------
select essai.devenir(:KOFI::uuid);
set role authenticated;
select essai.egal(public.est_revendeur(), false, 'Kofi n''est pas revendeur');
select essai.egal((select count(*)::int from public.mes_prix()), 0,
  'et ne reçoit aucun prix revendeur');
select public.creer_commande('{"nom":"Kofi","tel":"97222222"}'::jsonb,
  '[{"produit_id":"prod_marge","quantite":1}]'::jsonb) ->> 'id' as ordinaire \gset
reset role;
select essai.personne();
select essai.egal((select prix from public.commande_lignes where commande_id = :'ordinaire'),
  10000, 'il paie le prix de la vitrine');

-- Et l'équipe non plus : un compte d'équipe n'est pas un compte client.
select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.egal(public.est_revendeur(), false, 'un compte d''équipe n''est pas revendeur');
reset role;
select essai.personne();

-- Un visiteur qui commande sans compte reste au prix public.
set role anon;
select public.creer_commande('{"nom":"Passante","tel":"97998877"}'::jsonb,
  '[{"produit_id":"prod_marge","quantite":1}]'::jsonb) ->> 'id' as visiteur \gset
reset role;
select essai.egal((select prix from public.commande_lignes where commande_id = :'visiteur'),
  10000, 'un visiteur paie le prix de la vitrine');
select essai.egal((select revendeur from public.commandes where id = :'visiteur'),
  false, 'et sa commande ne porte aucun régime revendeur');

-- ---------------------------------------------------------
select essai.titre('Une commande partie ne change plus de régime');
-- ---------------------------------------------------------
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.refuse(
  format($$update public.commandes set revendeur = false where id = %L$$, :'vente'),
  'L''ENSEIGNE bascule une commande revendeur au prix public');
select essai.refuse(
  format($$update public.commande_lignes set prix = 10000 where commande_id = %L$$, :'vente'),
  'et elle en réécrit le prix');
reset role;
select essai.personne();
select essai.egal((select prix from public.commande_lignes where commande_id = :'vente'),
  8800, 'la ligne tient');

-- ---------------------------------------------------------
select essai.titre('Retirer le statut ne réécrit pas le passé');
-- ---------------------------------------------------------
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.egal(
  public.valider_revendeur(:AWA::uuid, false, 'Registre de commerce non fourni'),
  'refusee', 'BIZZOO retire le statut');
reset role;
select essai.personne();

select essai.egal((select prix from public.commande_lignes where commande_id = :'vente'),
  8800, 'la commande d''hier garde son prix');
select essai.egal((select revendeur from public.commandes where id = :'vente'),
  true, 'et son régime');

select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.egal(public.est_revendeur(), false, 'elle n''est plus revendeuse');
select essai.egal((select count(*)::int from public.mes_prix()), 0,
  'et ne reçoit plus de prix revendeur');
select essai.egal(
  (select revendeur_motif from public.clients where id = :AWA::uuid),
  'Registre de commerce non fourni', 'elle lit le motif du refus');

select public.creer_commande('{"nom":"Awa","tel":"97111111"}'::jsonb,
  '[{"produit_id":"prod_marge","quantite":1}]'::jsonb) ->> 'id' as apres \gset
reset role;
select essai.personne();
select essai.egal((select prix from public.commande_lignes where commande_id = :'apres'),
  10000, 'sa commande suivante repart au prix public');

-- ---------------------------------------------------------
select essai.titre('On ne se refait pas valider en changeant d''avis');
-- ---------------------------------------------------------
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select public.valider_revendeur(:AWA::uuid, true, '') as rendu \gset
reset role;
select essai.personne();

select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.egal(public.est_revendeur(), true, 'la revoilà revendeuse');

-- Elle redevient cliente ordinaire — puis retente aussitôt. Sans la
-- remise à zéro, elle retrouverait son statut sans décision.
update public.clients set type_compte = 'client' where id = :AWA::uuid;
select essai.egal(public.est_revendeur(), false, 'redevenue cliente, elle perd le prix');
update public.clients set type_compte = 'revendeur' where id = :AWA::uuid;
select essai.egal(public.est_revendeur(), false,
  'et la redemander ne la revalide pas');
reset role;
select essai.personne();

select essai.egal((select revendeur_etat from public.clients where id = :AWA::uuid),
  'en_attente', 'sa demande repart en attente');

-- ---------------------------------------------------------
select essai.titre('Un compte naît sans statut, quoi qu''il prétende');
-- ---------------------------------------------------------
insert into auth.users (id, email) values
  ('77777777-7777-7777-7777-777777777777', 'presse@client.bj')
on conflict do nothing;
-- L'insertion se déclare validée. La base n'en retient que la demande.
insert into public.clients (id, nom, tel, type_compte, revendeur_etat,
                            revendeur_decide_par, revendeur_motif)
values ('77777777-7777-7777-7777-777777777777', 'Pressé', '97444444',
        'revendeur', 'validee', 'lui-meme', 'accordé')
on conflict (id) do nothing;

select essai.egal(
  (select revendeur_etat from public.clients
    where id = '77777777-7777-7777-7777-777777777777'),
  'en_attente', 'un compte naît en attente, même s''il se prétend validé');
select essai.egal(
  (select revendeur_decide_par from public.clients
    where id = '77777777-7777-7777-7777-777777777777'),
  '', 'et sans signature');

select essai.devenir('77777777-7777-7777-7777-777777777777'::uuid);
set role authenticated;
select essai.egal(public.est_revendeur(), false, 'il n''achète pas au prix BIZZOO');
reset role;
select essai.personne();

delete from public.clients where id = '77777777-7777-7777-7777-777777777777';
