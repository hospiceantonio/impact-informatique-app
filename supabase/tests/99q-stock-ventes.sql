-- =========================================================
-- Le stock suit les ventes
--
-- CE QU'ON DÉFEND ICI. Rien ne décomptait le stock : une vente
-- payée laissait le produit « Disponible » avec ses cinq pièces, et
-- la base acceptait dix pièces quand il en restait trois. Désormais :
--
--   1. UNE COMMANDE NE DÉPASSE PAS LE STOCK — compté par produit,
--      deux lignes du même article ne font pas deux stocks ; « sur
--      commande » et approvisionnement gardent leur liberté ; un
--      refus ne laisse aucune commande derrière lui ;
--   2. LE PAIEMENT DÉCOMPTE — par l'agrégateur comme à la main —,
--      une seule fois même s'il est rejoué, et le produit tombé à
--      zéro passe « En rupture » ; la boutique en est prévenue ;
--   3. UNE SURVENTE NE BLOQUE PAS LE PAIEMENT : le second client
--      qui paie la dernière pièce est encaissé, le stock s'arrête à
--      zéro, et la boutique, l'enseigne et le superadmin savent
--      qu'il manque des pièces ;
--   4. « SUR COMMANDE » ET APPROVISIONNEMENT ne bougent pas ;
--   5. UNE ANNULATION REND CE QUI AVAIT ÉTÉ PRIS, ni plus ni moins —
--      commande entière ou ligne d'une boutique ;
--   6. UN PRODUIT QUI REFUSE L'ÉCRITURE ne fait pas tomber le
--      paiement : la commande est payée, et on le signale ;
--   7. PERSONNE NE TOUCHE AU STOCK PRIS À LA MAIN, ni ne rend du
--      stock sans annulation ;
--   8. REJOUER LE FICHIER NE DÉCOMPTE RIEN DE PLUS.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''

-- Le message d'un refus, pour le LIRE (le même que dans 97).
create or replace function essai.message_de(requete text) returns text
language plpgsql as $$
begin
  execute requete;
  return '';
exception
  when sqlstate 'BZ001' then raise;
  when others then return sqlerrm;
end $$;
grant execute on function essai.message_de(text) to anon, authenticated;

-- Une commande sans compte : la base n'en exige pas pendant cet essai.
create or replace function essai.commander(articles text) returns text
language plpgsql security definer as $$
begin
  return public.creer_commande('{"nom":"Awa","tel":"97000123"}'::jsonb,
                               articles::jsonb) ->> 'id';
end $$;

-- Payée par l'agrégateur, au montant exact.
create or replace function essai.payer(cible text, trx text) returns jsonb
language plpgsql security definer as $$
begin
  return public.marquer_payee(cible, trx,
    (select total from public.commandes where id = cible), 'feexpay');
end $$;

create or replace function essai.stock(cible text) returns int
language sql as $$ select stock from public.produits where id = cible $$;

-- ---------------------------------------------------------
select essai.titre('Le décor : cinq produits, une équipe à prévenir');

update public.reglages set compte_obligatoire = false where id = 1;
insert into public.profils (id, email, role, boutique_id, actif) values
  (:CHEF::uuid, 'chef-boutique@bizzoo.bj', 'administrateur', 'bou_informatique', true)
on conflict (id) do update
   set role = 'administrateur', boutique_id = 'bou_informatique', actif = true;

insert into public.produits
  (id, boutique_id, nom, prix, sous_categorie_id, stock, sur_commande, disponible, appro_le)
values
  ('prod_sv_a',     'bou_informatique', 'Souris sans fil',   7500, 'sc_hightech_accessoires', 5, false, true,  null),
  ('prod_sv_b',     'bou_informatique', 'Tapis de souris',   2000, 'sc_hightech_accessoires', 1, false, true,  null),
  ('prod_sv_c',     'bou_informatique', 'Clavier Bluetooth', 15000,'sc_hightech_accessoires', 2, false, true,  null),
  ('prod_sv_cmd',   'bou_informatique', 'Écran 27 pouces',   120000,'sc_hightech_accessoires', 0, true,  true,  null),
  ('prod_sv_appro', 'bou_informatique', 'Webcam HD',         18000,'sc_hightech_accessoires', 0, false, false, current_date + 3)
on conflict (id) do update
   set stock = excluded.stock, sur_commande = excluded.sur_commande,
       disponible = excluded.disponible, appro_le = excluded.appro_le;

select essai.egal(essai.stock('prod_sv_a'), 5, 'la souris : cinq pièces');

-- ---------------------------------------------------------
select essai.titre('1. Une commande ne dépasse pas le stock');

set role anon;
select essai.egal(
  essai.message_de($$select essai.commander('[{"produit_id":"prod_sv_a","quantite":6}]')$$),
  'Plus que 5 en stock pour « Souris sans fil » : réduisez la quantité dans votre panier.',
  'six souris quand il en reste cinq : refusé, et on dit combien il en reste');
-- DEUX LIGNES DU MÊME ARTICLE NE FONT PAS DEUX STOCKS. L'application
-- n'en envoie jamais deux, mais la fonction s'appelle aussi à la main.
select essai.verifie(
  essai.message_de($$select essai.commander('[{"produit_id":"prod_sv_a","quantite":3},
                                              {"produit_id":"prod_sv_a","quantite":3}]')$$)
    like 'Plus que 5 en stock pour%',
  'trois et trois font six : refusé aussi');
select essai.verifie(
  essai.message_de($$select essai.commander('[{"produit_id":"prod_sv_a","quantite":5}]')$$) = '',
  'cinq souris quand il en reste cinq : accepté');
select essai.verifie(
  essai.message_de($$select essai.commander('[{"produit_id":"prod_sv_cmd","quantite":10}]')$$) = '',
  '« sur commande » : dix écrans passent, la boutique les fait venir');
select essai.verifie(
  essai.message_de($$select essai.commander('[{"produit_id":"prod_sv_appro","quantite":4}]')$$) = '',
  'en approvisionnement : quatre webcams passent, elles arrivent');
reset role;

-- UN REFUS NE LAISSE RIEN DERRIÈRE LUI : ni commande orpheline, ni
-- ligne à moitié écrite.
select count(*) as avant from public.commandes \gset
set role anon;
select essai.message_de($$select essai.commander('[{"produit_id":"prod_sv_b","quantite":2}]')$$) \gset refus_
reset role;
select essai.egal((select count(*) from public.commandes), :avant::bigint,
  'le refus n''a laissé aucune commande');
select essai.egal(essai.stock('prod_sv_a'), 5, 'et commander ne décompte rien : cinq souris');

-- ---------------------------------------------------------
select essai.titre('2. Le paiement décompte, une seule fois');

select essai.commander('[{"produit_id":"prod_sv_a","quantite":2},
                         {"produit_id":"prod_sv_b","quantite":1}]') as v1 \gset
select essai.egal(essai.stock('prod_sv_a'), 5, 'à payer : rien n''a bougé');

select essai.payer(:'v1', 'TRX-SV-1') ->> 'numero' is not null as paye \gset
select essai.egal((select etat from public.commandes where id = :'v1'), 'payee', 'la commande est payée');
select essai.egal(essai.stock('prod_sv_a'), 3, 'deux souris vendues : il en reste trois');
select essai.egal(essai.stock('prod_sv_b'), 0, 'le dernier tapis est parti');
select essai.egal((select disponible from public.produits where id = 'prod_sv_b'), false,
  'et le tapis passe « En rupture » chez les clients');
select essai.egal((select disponible from public.produits where id = 'prod_sv_a'), true,
  'la souris reste disponible');
select essai.egal(
  (select string_agg(stock_pris::text, ',' order by nom) from public.commande_lignes
    where commande_id = :'v1'), '2,1',
  'chaque ligne note ce qu''elle a pris');

-- Un paiement rejoué — l'agrégateur réessaie, la vérification repasse.
select essai.payer(:'v1', 'TRX-SV-1') ->> 'deja' as deja \gset
select essai.egal(:'deja'::text, 'true', 'le paiement rejoué est reconnu');
select essai.egal(essai.stock('prod_sv_a'), 3, 'et ne décompte rien de plus');

-- LA BOUTIQUE EST PRÉVENUE DE LA RUPTURE, d'une seule notification.
select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'v1' and type = 'stock_epuise'
      and destinataire = :CHEF::uuid and corps like 'Tapis de souris : plus aucune pièce%'),
  1, 'l''administrateur de la boutique apprend que le tapis est épuisé');
select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'v1' and type = 'stock_insuffisant'), 0,
  'et rien ne manquait : aucune alerte de stock insuffisant');

-- À LA MAIN, PAR L'ENSEIGNE : le même chemin.
select essai.commander('[{"produit_id":"prod_sv_a","quantite":1}]') as v2 \gset
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select public.confirmer_paiement(:'v2');
reset role; select essai.personne();
select essai.egal((select etat from public.commandes where id = :'v2'), 'payee',
  'confirmée à la main par l''enseigne');
select essai.egal(essai.stock('prod_sv_a'), 2, 'et la souris est décomptée pareil');

-- ---------------------------------------------------------
select essai.titre('3. Une survente ne bloque pas le paiement');

-- Deux clients commandent les deux derniers claviers : la commande ne
-- réserve rien, et les deux passent.
select essai.commander('[{"produit_id":"prod_sv_c","quantite":2}]') as v3 \gset
select essai.commander('[{"produit_id":"prod_sv_c","quantite":2}]') as v4 \gset
select essai.payer(:'v3', 'TRX-SV-3') is not null as p3 \gset
select essai.egal(essai.stock('prod_sv_c'), 0, 'le premier paie : plus un clavier');
select essai.payer(:'v4', 'TRX-SV-4') is not null as p4 \gset
select essai.egal((select etat from public.commandes where id = :'v4'), 'payee',
  'le second paie aussi : l''argent est chez l''agrégateur, la commande est PAYÉE');
select essai.egal(essai.stock('prod_sv_c'), 0, 'le stock s''arrête à zéro, jamais en dessous');
select essai.egal(
  (select stock_pris from public.commande_lignes where commande_id = :'v4'), 0,
  'la seconde vente n''a rien pris : il n''y avait plus rien');
select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'v4' and type = 'stock_insuffisant'
      and destinataire = :CHEF::uuid
      and corps like '%Clavier Bluetooth (2 vendus, 0 en stock)%'),
  1, 'la boutique apprend ce qui manque, et combien');
select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'v4' and type = 'stock_insuffisant'
      and destinataire = :ENSEIGNE::uuid),
  1, 'le superadministrateur aussi : c''est un incident');

-- ---------------------------------------------------------
select essai.titre('4. « Sur commande » et approvisionnement ne bougent pas');

select essai.commander('[{"produit_id":"prod_sv_cmd","quantite":3},
                         {"produit_id":"prod_sv_appro","quantite":2}]') as v5 \gset
select essai.payer(:'v5', 'TRX-SV-5') is not null as p5 \gset
select essai.egal(essai.stock('prod_sv_cmd'), 0, 'l''écran « sur commande » garde son stock de zéro');
select essai.egal(essai.stock('prod_sv_appro'), 0, 'la webcam en approvisionnement aussi');
select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'v5' and type in ('stock_insuffisant', 'stock_epuise')), 0,
  'et personne n''est alerté : c''est ce que la boutique avait annoncé');

-- ---------------------------------------------------------
select essai.titre('5. Une annulation rend ce qui avait été pris');

select essai.commander('[{"produit_id":"prod_sv_a","quantite":1}]') as v6 \gset
select essai.payer(:'v6', 'TRX-SV-6') is not null as p6 \gset
select essai.egal(essai.stock('prod_sv_a'), 1, 'une souris vendue : il en reste une');

-- La commande entière, annulée par l'enseigne.
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.commandes set etat = 'annulee' where id = :'v6';
reset role; select essai.personne();
select essai.egal(essai.stock('prod_sv_a'), 2, 'annulée : la souris revient en stock');
select essai.egal(
  (select stock_pris from public.commande_lignes where commande_id = :'v6'), 0,
  'et la ligne n''a plus rien à rendre');

-- La part d'UNE boutique, annulée par elle.
select essai.commander('[{"produit_id":"prod_sv_a","quantite":2}]') as v7 \gset
select essai.payer(:'v7', 'TRX-SV-7') is not null as p7 \gset
select essai.egal(essai.stock('prod_sv_a'), 0, 'deux souris vendues : plus aucune');
select essai.egal((select disponible from public.produits where id = 'prod_sv_a'), false,
  'la souris est « En rupture »');
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'annulee' where commande_id = :'v7';
reset role; select essai.personne();
select essai.egal(essai.stock('prod_sv_a'), 2, 'la boutique annule sa ligne : les deux reviennent');
select essai.egal((select disponible from public.produits where id = 'prod_sv_a'), true,
  'et la souris redevient disponible');

-- Annuler ensuite toute la commande ne rend rien une seconde fois.
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.commandes set etat = 'annulee' where id = :'v7';
reset role; select essai.personne();
select essai.egal(essai.stock('prod_sv_a'), 2, 'la commande annulée après sa ligne : rien de plus');

-- NI PLUS NI MOINS : la vente qui n'avait rien pris ne rend rien.
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.commandes set etat = 'annulee' where id = :'v4';
reset role; select essai.personne();
select essai.egal(essai.stock('prod_sv_c'), 0,
  'la survente annulée ne fabrique pas de claviers');

-- ---------------------------------------------------------
select essai.titre('6. Un produit qui refuse l''écriture ne fait pas tomber le paiement');

insert into public.produits
  (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_sv_bloque', 'bou_informatique', 'Chargeur USB-C', 9000,
        'sc_hightech_accessoires', 7, true)
on conflict (id) do update set stock = 7, disponible = true;
select essai.commander('[{"produit_id":"prod_sv_bloque","quantite":1}]') as v8 \gset
-- Une règle qui refuse toute baisse de CE stock : n'importe quelle
-- raison qu'aurait un produit de refuser l'écriture.
alter table public.produits add constraint essai_stock_bloque
  check (id <> 'prod_sv_bloque' or stock >= 7);
select essai.payer(:'v8', 'TRX-SV-8') is not null as p8 \gset
alter table public.produits drop constraint essai_stock_bloque;
select essai.egal((select etat from public.commandes where id = :'v8'), 'payee',
  'la commande est payée quand même');
select essai.egal(essai.stock('prod_sv_bloque'), 7, 'le stock n''a pas pu bouger');
select essai.egal(
  (select stock_pris from public.commande_lignes where commande_id = :'v8'), 0,
  'et la ligne ne prétend pas l''avoir pris');
select essai.egal(
  (select count(*)::int from public.notifications
    where commande_id = :'v8' and type = 'stock_a_verifier'
      and destinataire in (:CHEF::uuid, :ENSEIGNE::uuid)),
  2, 'la boutique et le superadmin savent qu''il faut le corriger à la main');

-- ---------------------------------------------------------
select essai.titre('7. Personne ne touche au stock pris, ni ne rend à la main');

select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse(
  $$update public.commande_lignes set stock_pris = 50 where commande_id = '$$ || :'v1' || $$'$$,
  'la boutique n''écrit pas ce qu''une vente a pris');
select essai.refuse($$select public.stock_rendre('x')$$,
  'ni ne rend du stock sans annulation');
reset role; select essai.personne();
set role anon;
select essai.refuse($$select public.stock_rendre('x')$$, 'un visiteur non plus');
reset role;

-- ---------------------------------------------------------
select essai.titre('8. Rejouer le fichier ne décompte rien de plus');

select essai.stock('prod_sv_a') as a_avant, essai.stock('prod_sv_b') as b_avant \gset
\set fichier `echo "$RACINE/supabase/stock-ventes.sql"`
\o /dev/null
set client_min_messages = warning;
\i :fichier
set client_min_messages = notice;
\o
select essai.egal(essai.stock('prod_sv_a'), :a_avant::int, 'la souris n''a pas bougé');
select essai.egal(essai.stock('prod_sv_b'), :b_avant::int, 'le tapis non plus');
select essai.egal(
  (select count(*)::int from pg_trigger
    where tgrelid = 'public.commandes'::regclass and tgname = 'commandes_stock'), 1,
  'un seul déclencheur, pas deux');

-- Les produits de l'essai restent : ils ont été vendus, et une ligne de
-- commande ne lâche pas son produit — ce qui a été vendu est vendu.
