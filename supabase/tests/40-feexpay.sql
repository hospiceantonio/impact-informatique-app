-- =========================================================
-- FeexPay : le second agrégateur, et ce qui le tient.
--
-- FeexPay n'envoie AUCUNE notification signée. C'est donc
-- notre serveur qui ouvre le paiement, garde la RÉFÉRENCE que
-- FeexPay lui rend, puis va lui demander si le versement a
-- abouti. Deux choses doivent tenir, sans quoi tout s'écroule :
--
--   1. la référence ne se pose que depuis le serveur, jamais
--      depuis un téléphone — sinon le client désignerait
--      lui-même le versement censé régler sa commande, et un
--      paiement de 100 francs solderait une commande de
--      100 000 ;
--
--   2. le montant à encaisser sort de la BASE, jamais de la
--      requête.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''

select essai.titre('Le décor : deux commandes à payer');

select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
update public.paiement set fournisseur = 'feexpay', actif = true where id = 1;
reset role;
select essai.personne();

select essai.egal((select fournisseur from public.paiement where id = 1),
  'feexpay', 'l''enseigne choisit son agrégateur');

-- Un agrégateur qu'on ne connaît pas n'entre pas : une faute de frappe
-- laisserait le paiement ouvert sans que personne ne sache par où.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.refuse(
  $$update public.paiement set fournisseur = 'orange-money' where id = 1$$,
  'un agrégateur inconnu');
reset role;
select essai.personne();

-- Un produit à nous : les essais précédents ont pu fermer une boutique
-- ou vider un stock, et un décor qui dépend de ce qu'ils ont laissé
-- casse pour des raisons qui n'ont rien à voir avec ce qu'on éprouve.
insert into public.produits
  (id, boutique_id, nom, prix, categorie_id, stock, disponible)
values ('prod_feex', 'bou_informatique', 'Article FeexPay', 12000,
        'cat_accessoires', 10, true)
on conflict (id) do update set prix = 12000, stock = 10, disponible = true;

-- Deux commandes, créées par la porte prévue.
set role anon;
select public.creer_commande(
  '{"nom":"Awa K.","tel":"97000000","adresse":"Cotonou"}'::jsonb,
  '[{"produit_id":"prod_feex","quantite":1}]'::jsonb) \gset cmdA_
select public.creer_commande(
  '{"nom":"Koffi D.","tel":"96000000","adresse":"Calavi"}'::jsonb,
  '[{"produit_id":"prod_feex","quantite":1}]'::jsonb) \gset cmdB_
reset role;

\set A :cmdA_creer_commande
\set B :cmdB_creer_commande
select (:'A'::jsonb ->> 'id') as a \gset
select (:'B'::jsonb ->> 'id') as b \gset

select essai.verifie(:'a' like 'cmd_%', 'la première commande est née');
select essai.verifie(:'b' like 'cmd_%', 'la seconde aussi');

-- ---------------------------------------------------------
select essai.titre('Ce que le serveur seul a le droit de faire');
-- ---------------------------------------------------------
-- « noter_reference » pose la référence avec laquelle on ira vérifier
-- le versement. Un téléphone qui pourrait la poser choisirait quel
-- versement répond pour sa commande.
set role anon;
select essai.refuse(
  format($$select public.noter_reference(%L, 'ref_vol')$$, :'a'),
  'un client pose lui-même la référence de son paiement');
select essai.refuse(
  format($$select public.commande_pour_paiement(%L, '97000000')$$, :'a'),
  'un client lit le montant à encaisser');
reset role;

select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.refuse(
  format($$select public.noter_reference(%L, 'ref_boutique')$$, :'a'),
  'une boutique pose la référence d''un paiement');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Le montant vient de la base, et le numéro fait foi');
-- ---------------------------------------------------------
select essai.egal(
  (public.commande_pour_paiement(:'a', '97000000') ->> 'total')::int,
  (select total from public.commandes where id = :'a'),
  'le serveur lit le montant dans la base');

select essai.verifie(
  public.commande_pour_paiement(:'a', '96000000') is null,
  'un mauvais numéro ne donne rien — même commande, autre client');

select essai.verifie(
  public.commande_pour_paiement('cmd_inexistante', '97000000') is null,
  'une commande qui n''existe pas ne donne rien');

-- ---------------------------------------------------------
select essai.titre('Une référence ne sert qu''une commande');
-- ---------------------------------------------------------
select essai.verifie(public.noter_reference(:'a', 'ref_feex_001'),
  'le serveur pose la référence de la première commande');

select essai.egal(
  public.commande_pour_paiement(:'a', '97000000') ->> 'reference',
  'ref_feex_001', 'et la commande la porte');

select essai.verifie(not public.noter_reference(:'b', 'ref_feex_001'),
  'la même référence sur une AUTRE commande — refusée');

select essai.egal(
  public.commande_pour_paiement(:'b', '96000000') ->> 'reference',
  '', 'la seconde commande n''a rien attrapé');

-- Chaque tentative fait sonner un téléphone. Deux coup sur coup, non :
-- sans ce frein, on harcèlerait n'importe quel numéro de demandes de
-- paiement venues de l'enseigne.
select essai.verifie(not public.noter_reference(:'a', 'ref_feex_002'),
  'une seconde tentative dans la foulée — refusée');

select essai.egal(
  public.commande_pour_paiement(:'a', '97000000') ->> 'reference',
  'ref_feex_001', 'la première tient toujours');

-- Passé le délai, on peut se reprendre : on s'est trompé de numéro.
select essai.reculer_tentative(:'a', 60);
select essai.verifie(public.noter_reference(:'a', 'ref_feex_002'),
  'passé le délai, une nouvelle tentative remplace la première');

-- ---------------------------------------------------------
select essai.titre('L''équipe ne réécrit pas la référence');
-- ---------------------------------------------------------
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.refuse(
  format($$update public.commandes set fournisseur_ref = 'ref_choisie' where id = %L$$, :'a'),
  'L''ENSEIGNE ELLE-MÊME choisit quel versement règle la commande');
reset role;
select essai.personne();

select essai.egal(
  (select fournisseur_ref from public.commandes where id = :'a'),
  'ref_feex_002', 'la référence n''a pas bougé');

-- ---------------------------------------------------------
select essai.titre('Encaisser : seul le montant constaté vaut');
-- ---------------------------------------------------------
-- C'est ce que fait l'Edge Function après avoir INTERROGÉ FeexPay :
-- elle transmet le montant que FeexPay annonce, jamais celui du panier.
select essai.egal(
  public.marquer_payee(:'a', 'ref_feex_002',
    (select total - 1 from public.commandes where id = :'a')) ->> 'incomplet',
  'true', 'un versement d''un franc de moins ne paie pas la commande');

select essai.egal((select etat from public.commandes where id = :'a'),
  'a_payer', 'et la commande attend toujours');

select essai.egal(
  public.marquer_payee(:'a', 'ref_feex_002',
    (select total from public.commandes where id = :'a')) ->> 'numero',
  (select numero from public.commandes where id = :'a'),
  'le compte y étant, la commande est payée');

select essai.egal((select etat from public.commandes where id = :'a'),
  'payee', 'elle est encaissée');

-- Rejouable : notre serveur peut redemander le statut autant de fois
-- qu'il veut, cela n'encaisse qu'une fois.
select essai.egal(
  public.marquer_payee(:'a', 'ref_feex_002',
    (select total from public.commandes where id = :'a')) ->> 'deja',
  'true', 'vérifier deux fois n''encaisse pas deux fois');

-- Une commande payée n'accueille plus de nouvelle tentative.
select essai.verifie(not public.noter_reference(:'a', 'ref_feex_003'),
  'et plus aucune tentative ne s''ouvre dessus');
