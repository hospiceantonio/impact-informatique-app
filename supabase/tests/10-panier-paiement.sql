-- =========================================================
-- Le panier, la commande et l'encaissement, éprouvés sur un
-- vrai moteur.
--
-- Ce qu'on cherche à mettre en défaut n'est pas l'affichage :
-- c'est l'argent. Trois règles doivent tenir quoi qu'on
-- envoie à la base.
--
--   1. le client n'écrit pas les prix ;
--   2. le client ne déclare pas qu'il a payé ;
--   3. le montant qui compte est celui annoncé par KkiaPay.
--
-- Chaque « refusé » ci-dessous est une porte qu'on a essayé
-- d'ouvrir et qui a tenu. Un « LAISSÉ PASSER » arrête tout.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

select essai.titre('Le décor : deux boutiques, quelques produits');

insert into public.boutiques (id, nom, secteur, devise, actif, ordre)
values ('bou_essai_eur', 'BOUTIQUE EN EUROS', 'Essai', 'EUR', true, 90)
on conflict (id) do update set devise = 'EUR';

insert into public.categories (id, boutique_id, nom, ordre)
values ('cat_essai_eur', 'bou_essai_eur', 'Divers', 1)
on conflict (id) do nothing;

insert into public.produits
  (id, boutique_id, nom, prix, categorie_id, stock, sur_commande, disponible)
values
  ('prod_essai_eur', 'bou_essai_eur', 'Article en euros', 10, 'cat_essai_eur', 5, false, true)
on conflict (id) do nothing;

-- Un produit dont il ne reste rien, et qu'on ne commande pas.
insert into public.produits
  (id, boutique_id, nom, prix, categorie_id, stock, sur_commande, disponible, appro_le)
values
  ('prod_essai_rupture', 'bou_informatique', 'Article épuisé', 1000,
   'cat_accessoires', 0, false, false, null)
on conflict (id) do update set stock = 0, sur_commande = false, appro_le = null;

-- ---------------------------------------------------------
select essai.titre('Une commande n''entre que par la porte prévue');
-- ---------------------------------------------------------
set role anon;

select essai.refuse(
  $$insert into public.commandes (id, client_tel) values ('cmd_force', '97000000')$$,
  'un client écrit directement une commande');

select essai.refuse(
  $$insert into public.commande_lignes (id, commande_id, produit_id, quantite)
    values ('lig_force', 'cmd_force', 'prod_hp15', 1)$$,
  'un client écrit directement une ligne');

select essai.refuse(
  $$select public.creer_commande('{"tel":"97000000"}'::jsonb, '[]'::jsonb)$$,
  'un panier vide');

select essai.refuse(
  $$select public.creer_commande('{"nom":"X"}'::jsonb,
      '[{"produit_id":"prod_hp15","quantite":1}]'::jsonb)$$,
  'une commande sans numéro de téléphone');

select essai.refuse(
  $$select public.creer_commande('{"tel":"97000000"}'::jsonb,
      '[{"produit_id":"prod_essai_rupture","quantite":1}]'::jsonb)$$,
  'un produit dont il ne reste rien');

select essai.refuse(
  $$select public.creer_commande('{"tel":"97000000"}'::jsonb,
      '[{"produit_id":"prod_hp15","quantite":1},
        {"produit_id":"prod_essai_eur","quantite":1}]'::jsonb)$$,
  'deux monnaies dans un seul versement');

select essai.refuse(
  $$select public.creer_commande('{"tel":"97000000"}'::jsonb,
      '[{"produit_id":"prod_invente","quantite":1}]'::jsonb)$$,
  'un produit qui n''existe pas');

-- ---------------------------------------------------------
select essai.titre('Le prix vient du catalogue, jamais du téléphone');
-- ---------------------------------------------------------
select public.creer_commande(
  '{"nom":"Awa K.","tel":"97 44 55 66","indicatif":"229","adresse":"Calavi"}'::jsonb,
  '[{"produit_id":"prod_hp15","quantite":2},
    {"produit_id":"prod_logitech_m185","quantite":1}]'::jsonb) as commande \gset
reset role;

select (:'commande'::jsonb ->> 'id') as cmd,
       (:'commande'::jsonb ->> 'total')::int as total_annonce \gset

select essai.egal(
  (select sum(p.prix * l.quantite)::int from public.commande_lignes l
     join public.produits p on p.id = l.produit_id where l.commande_id = :'cmd'),
  :total_annonce,
  'le total annoncé est celui du catalogue');

select essai.verifie(
  not exists (select 1 from public.commande_lignes l
                join public.produits p on p.id = l.produit_id
               where l.commande_id = :'cmd' and l.prix <> p.prix),
  'chaque ligne porte le prix du catalogue');

select essai.verifie(
  (select numero from public.commandes where id = :'cmd') like 'BZ-%',
  'la commande porte un numéro lisible');

select essai.egal((select etat from public.commandes where id = :'cmd'),
  'a_payer', 'une commande naît « à payer »');

-- Même en écrivant la ligne soi-même, le prix est relu.
insert into public.commande_lignes (id, commande_id, produit_id, quantite, prix, nom)
values ('lig_triche', :'cmd', 'prod_epson_l3250', 1, 1, 'Imprimante à un franc');

select essai.egal((select prix from public.commande_lignes where id = 'lig_triche'),
  (select prix::int from public.produits where id = 'prod_epson_l3250'),
  'un prix soufflé par le client est écrasé par le catalogue');

select essai.egal((select total from public.commandes where id = :'cmd'),
  (select sum(prix * quantite)::int from public.commande_lignes where commande_id = :'cmd'),
  'le total suit ses lignes');

-- ---------------------------------------------------------
select essai.titre('Personne ne se déclare payé');
-- ---------------------------------------------------------
select essai.refuse(
  format($$update public.commandes set etat = 'payee' where id = %L$$, :'cmd'),
  'un inconnu fait passer une commande à « payée »');

-- Et maintenant celui qui a vraiment la main sur la table : l'enseigne.
-- Sans ce passage, le garde-fou du paiement n'était jamais atteint —
-- le premier refus (« seule l'équipe suit une commande ») masquait tout.
select essai.devenir('11111111-1111-1111-1111-111111111111'::uuid);
set role authenticated;
select essai.refuse(
  format($$update public.commandes set etat = 'payee' where id = %L$$, :'cmd'),
  'L''ENSEIGNE ELLE-MÊME déclare un paiement à la main');
reset role;
select essai.personne();

select essai.refuse(
  $$update public.commande_lignes set prix = 1 where id = 'lig_triche'$$,
  'réécrire le prix d''une ligne vendue');

select essai.refuse(
  $$update public.commande_lignes set quantite = 99 where id = 'lig_triche'$$,
  'changer la quantité d''une ligne vendue');

set role anon;
select essai.refuse(
  format($$select public.marquer_payee(%L, 'faux', 1)$$, :'cmd'),
  'encaisser depuis l''application (anon)');
set role authenticated;
select essai.refuse(
  format($$select public.marquer_payee(%L, 'faux', 1)$$, :'cmd'),
  'encaisser depuis l''application (connecté)');
select essai.refuse(
  format($$select public.confirmer_paiement(%L)$$, :'cmd'),
  'se porter garant sans être l''enseigne');
reset role;

-- ---------------------------------------------------------
select essai.titre('Ce que le téléphone affirme n''est pas une preuve');
-- ---------------------------------------------------------
set role anon;
select public.signaler_transaction(:'cmd', 'TRX-ANNONCEE');
reset role;

select essai.egal((select transaction_annoncee from public.commandes where id = :'cmd'),
  'TRX-ANNONCEE', 'l''indice du téléphone est noté pour la boutique');
select essai.egal((select transaction_id from public.commandes where id = :'cmd'),
  '', 'mais il ne se range pas là où KkiaPay prouve');
select essai.egal((select etat from public.commandes where id = :'cmd'),
  'a_payer', 'et il ne fait pas bouger l''état');

-- Un autre client réclame la même transaction sur sa propre commande.
set role anon;
select public.creer_commande('{"nom":"Autre","tel":"96001122"}'::jsonb,
  '[{"produit_id":"prod_logitech_m185","quantite":1}]'::jsonb) ->> 'id' as autre \gset
select public.signaler_transaction(:'autre', 'TRX-ANNONCEE');
reset role;

select essai.egal((select transaction_annoncee from public.commandes where id = :'autre'),
  'TRX-ANNONCEE', 'réclamer la transaction d''un autre ne provoque aucune erreur');

-- ---------------------------------------------------------
select essai.titre('Seul le serveur encaisse, et il vérifie le montant');
-- ---------------------------------------------------------
select public.marquer_payee('', 'TRX-ANNONCEE', 999999) as sans_reference \gset
select essai.verifie((:'sans_reference'::jsonb ->> 'raison') = 'commande inconnue',
  'sans référence, la base ne devine pas quelle commande valider');
select essai.egal((select etat from public.commandes where id = :'autre'),
  'a_payer', 'la commande qui réclamait la transaction n''a pas été validée');

select public.marquer_payee(:'cmd', 'TRX-REELLE', 100) as incomplet \gset
select essai.verifie((:'incomplet'::jsonb ->> 'incomplet')::boolean,
  'un paiement incomplet est signalé');
select essai.egal((select etat from public.commandes where id = :'cmd'),
  'a_payer', 'un paiement incomplet ne valide rien');
select essai.verifie(
  (select remarque like 'Paiement incomplet%' from public.commandes where id = :'cmd'),
  'la boutique voit ce qui manque');

select public.marquer_payee(:'cmd', 'TRX-REELLE',
  (select total from public.commandes where id = :'cmd')) as complet \gset
select essai.egal((select etat from public.commandes where id = :'cmd'),
  'payee', 'le montant complet valide la commande');
select essai.egal((select transaction_id from public.commandes where id = :'cmd'),
  'TRX-REELLE', 'la preuve est enregistrée');
select essai.egal((select confirme_par from public.commandes where id = :'cmd'),
  '', 'et elle porte la signature de KkiaPay, pas celle d''un humain');
select essai.verifie((select remarque = '' from public.commandes where id = :'cmd'),
  'la remarque du paiement incomplet est effacée');

-- KkiaPay réessaie cinq fois tant qu'il n'a pas reçu un 200.
select public.marquer_payee(:'cmd', 'TRX-REELLE', 999999) as rejeu \gset
select essai.verifie((:'rejeu'::jsonb ->> 'deja')::boolean,
  'rejouée, la notification ne fait rien de plus');

-- Une transaction déjà prise ne doit pas faire tomber la fonction :
-- une erreur ferait réessayer KkiaPay cinq fois pour rien.
select public.marquer_payee(:'autre', 'TRX-REELLE', 999999) as conflit \gset
select essai.verifie((:'conflit'::jsonb ->> 'conflit')::boolean,
  'une transaction déjà rattachée est signalée, sans erreur');
select essai.egal((select etat from public.commandes where id = :'autre'),
  'a_payer', 'et la commande en conflit n''est pas validée');

-- ---------------------------------------------------------
select essai.titre('Suivre sa commande, et le filet de l''enseigne');
-- ---------------------------------------------------------
set role anon;
select essai.verifie(
  (public.suivre_commande(:'cmd', '97 44 55 66') ->> 'etat') = 'payee',
  'le client suit sa commande avec son numéro');
select essai.verifie(
  public.suivre_commande(:'cmd', '90000000') is null,
  'un autre numéro ne donne rien');
select essai.verifie(
  public.suivre_commande('cmd_invente', '97445566') is null,
  'un identifiant inventé ne donne rien');
reset role;

-- Le superadministrateur se porte garant quand la notification se perd.
select id as super from public.profils where role = 'superadministrateur' limit 1 \gset
select essai.devenir(:'super'::uuid);
set role authenticated;
select public.confirmer_paiement(:'autre');
reset role;
select essai.personne();

select essai.egal((select etat from public.commandes where id = :'autre'),
  'payee', 'l''enseigne peut confirmer un paiement à la main');
select essai.verifie(
  (select confirme_par <> '' from public.commandes where id = :'autre'),
  'et la commande garde le nom de qui s''est porté garant');

-- ---------------------------------------------------------
select essai.titre('Une commande payée ne se retouche plus');
-- ---------------------------------------------------------
-- Là encore, en tant qu'enseigne : c'est le seul compte qui a le droit
-- d'écrire dans « commandes », donc le seul dont le refus prouve quelque
-- chose.
select essai.devenir('11111111-1111-1111-1111-111111111111'::uuid);
set role authenticated;
select essai.refuse(
  format($$update public.commandes set total = 1 where id = %L$$, :'cmd'),
  'changer le montant d''une commande payée');
select essai.refuse(
  format($$update public.commandes set client_tel = '00000000' where id = %L$$, :'cmd'),
  'changer le client d''une commande payée');
select essai.refuse(
  format($$update public.commandes set transaction_id = 'INVENTEE' where id = %L$$, :'cmd'),
  'inventer une preuve de paiement');
-- Ce qu'elle a le droit de faire : annuler.
update public.commandes set etat = 'annulee' where id = :'cmd';
select essai.egal((select etat from public.commandes where id = :'cmd'),
  'annulee', 'mais l''enseigne peut annuler une commande payée');
reset role;
select essai.personne();
