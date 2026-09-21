-- =========================================================
-- La fiche d'un client : ce que l'enseigne y lit, et qui n'y
-- entre pas.
--
-- Un client appelle pour un litige. Sans cet écran, il fallait
-- parcourir les commandes une à une. Mais ouvrir le fichier
-- clients, c'est ouvrir des noms, des numéros et des achats —
-- alors quatre choses à prouver :
--
--   1. L'ENSEIGNE SEULE. Ni une boutique, ni un client, ni un
--      visiteur. Une boutique voit déjà le nom et le numéro
--      sur SES commandes ; lui ouvrir la liste entière, ce
--      serait lui remettre le fichier des autres ;
--   2. LA RECHERCHE NE REND PAS TOUT. Chercher un nom qui ne
--      contient aucun chiffre ne doit pas déverser la liste
--      complète par la branche « numéro » ;
--   3. UN NUMÉRO NON VÉRIFIÉ NE DÉSIGNE PERSONNE. Les
--      commandes d'avant le compte ne remontent QUE sur un
--      numéro vérifié — sinon deux clients qui tapent le même
--      numéro liraient les achats l'un de l'autre ;
--   4. ET PAS AU-DELÀ DE DIX-HUIT MOIS. La même règle que
--      rattacher_mes_commandes, pas une règle voisine.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set KOFI     '''55555555-5555-5555-5555-555555555555'''
\set BRICE    '''eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'''

select essai.titre('Le décor : un client, ses deux commandes, et une d''avant');

insert into auth.users (id, email) values (:BRICE::uuid, 'brice@client.bj')
on conflict do nothing;
insert into public.clients (id, nom, tel) values (:BRICE::uuid, 'Brice', '96121212')
on conflict (id) do update set nom = 'Brice', tel = '96121212';

-- Un article à prix rond : chaque total doit se lire sans calcul.
insert into public.produits
  (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_fiche', 'bou_informatique', 'Chargeur secteur', 4000,
        'sc_hightech_accessoires', 50, true)
on conflict (id) do update
   set prix = excluded.prix, stock = 50, disponible = true;

-- Deux commandes à son compte : une payée, une non.
select essai.devenir(:BRICE::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Brice","tel":"96121212"}'::jsonb,
  '[{"produit_id":"prod_fiche","quantite":2}]'::jsonb) ->> 'id' as payee \gset
select public.creer_commande('{"nom":"Brice","tel":"96121212"}'::jsonb,
  '[{"produit_id":"prod_fiche","quantite":1}]'::jsonb) ->> 'id' as impayee \gset
reset role;
select essai.personne();

select public.marquer_payee(:'payee', 'TRX-FICHE-1',
  (select total from public.commandes where id = :'payee')) as encaisse \gset
select essai.egal((select total::int from public.commandes where id = :'payee'),
  8000, 'la commande payée vaut 2 × 4 000');

-- Et une commande passée AU MÊME NUMÉRO, sans compte. C'est le cas qui
-- sépare vraiment les deux règles.
set role anon;
select public.creer_commande('{"nom":"Brice","tel":"96121212"}'::jsonb,
  '[{"produit_id":"prod_fiche","quantite":3}]'::jsonb) ->> 'id' as orpheline \gset
reset role;

select essai.verifie(
  (select client_id is null from public.commandes where id = :'orpheline'),
  'la commande du visiteur n''appartient à aucun compte');
select essai.verifie(
  not (select tel_verifie from public.clients where id = :BRICE::uuid),
  'et le numéro de Brice n''est pas encore vérifié');

-- ---------------------------------------------------------
select essai.titre('L''enseigne lit la fiche, et ses chiffres');
-- ---------------------------------------------------------
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;

select essai.egal((select count(*)::int from public.clients_liste('', :BRICE::uuid)), 1,
  'la fiche de Brice se trouve par son identifiant');
select essai.egal((select nom from public.clients_liste('', :BRICE::uuid)),
  'Brice', 'avec son nom');
select essai.egal((select commandes from public.clients_liste('', :BRICE::uuid)),
  2::bigint, 'ses deux commandes');
select essai.egal((select payees from public.clients_liste('', :BRICE::uuid)),
  1::bigint, 'dont une payée');
select essai.egal((select total_paye from public.clients_liste('', :BRICE::uuid)),
  8000::bigint, 'et ce qu''il a réellement dépensé — pas ce qu''il a mis au panier');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('La recherche ne déverse pas la liste');
-- ---------------------------------------------------------
-- LE CONSTAT. Le filtre du numéro est un « ou » : sans garde, chercher
-- un nom sans chiffre le réduirait à « like '%%' », vrai pour tout le
-- monde — et une recherche par nom rendrait le fichier entier.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;

select essai.verifie(
  (select count(*) > 1 from public.clients_liste('')),
  'il y a bien plus d''un compte dans la base');
select essai.egal((select count(*)::int from public.clients_liste('brice')), 1,
  'chercher « brice » n''en rend QU''UN');
select essai.egal((select nom from public.clients_liste('BRICE')),
  'Brice', 'la casse n''y change rien');
select essai.egal((select count(*)::int from public.clients_liste('zzz-personne')), 0,
  'et un nom qui n''existe pas n''en rend aucun');

-- Un numéro se tape comme on le lit.
select essai.egal((select nom from public.clients_liste('96 12 12 12')),
  'Brice', 'le numéro se cherche avec ses espaces');
select essai.egal((select nom from public.clients_liste('+229 96121212')),
  'Brice', 'et avec son indicatif, que la colonne ne garde pas');
-- Mais l'indicatif SEUL ne doit pas vider le fichier : sans la garde de
-- longueur, il ne resterait qu'un « like '%%' » vrai pour tout le monde.
select essai.verifie(
  (select count(*) < (select count(*) from public.clients_liste(''))
     from public.clients_liste('+229')),
  'taper l''indicatif seul ne rend pas toute la liste');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Un numéro non vérifié ne ramasse rien');
-- ---------------------------------------------------------
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.client_commandes(:BRICE::uuid)), 2,
  'la fiche ne montre que les deux commandes de son compte');
select essai.egal((select count(*)::int from public.client_commandes(:BRICE::uuid)
                    where id = :'orpheline'), 0,
  'PAS celle du visiteur, pourtant au même numéro');
reset role;
select essai.personne();

-- Le numéro est vérifié par SMS. La règle bascule, et elle seule.
begin;
select set_config('bizzoo.verification', 'oui', true);
update public.clients set tel_verifie = true where id = :BRICE::uuid;
commit;

select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.client_commandes(:BRICE::uuid)), 3,
  'une fois le numéro vérifié, la commande d''avant remonte');
select essai.verifie(
  not (select rattachee from public.client_commandes(:BRICE::uuid)
        where id = :'orpheline'),
  'et l''écran sait qu''elle n''est pas encore rattachée');
select essai.egal((select total from public.client_commandes(:BRICE::uuid)
                    where id = :'orpheline'), 12000::bigint,
  'avec son montant : 3 × 4 000');
-- Le nom de la boutique est lu dans la table, pas recopié ici : des
-- essais plus haut l'ont déjà renommée. Une jointure cassée rendrait
-- une chaîne vide, et l'écart se verrait quand même.
select essai.egal((select boutiques from public.client_commandes(:BRICE::uuid)
                    where id = :'payee'),
  (select nom from public.boutiques where id = 'bou_informatique'),
  'et chaque commande dit chez qui elle a été passée');
select essai.egal((select articles from public.client_commandes(:BRICE::uuid)
                    where id = :'payee'), 1::bigint,
  'avec le nombre de lignes qu''elle porte');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Et pas au-delà de dix-huit mois');
-- ---------------------------------------------------------
-- La même borne que rattacher_mes_commandes. Si les deux divergeaient,
-- l'écran promettrait une commande que le client ne retrouverait jamais.
begin;
select set_config('bizzoo.interne', 'oui', true);
update public.commandes set cree_le = now() - interval '19 months'
 where id = :'orpheline';
commit;

select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.client_commandes(:BRICE::uuid)), 2,
  'une commande trop vieille ne remonte plus');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Le fichier clients ne sort pas de l''enseigne');
-- ---------------------------------------------------------
-- Une boutique voit déjà le nom et le numéro sur SES commandes. Lui
-- ouvrir la liste, ce serait lui remettre celui de toutes les autres.
select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.clients_liste('')), 0,
  'un chef de boutique ne lit aucune fiche');
select essai.egal((select count(*)::int from public.clients_liste('brice')), 0,
  'ni en cherchant un nom qu''il connaît');
select essai.egal((select count(*)::int from public.client_commandes(:BRICE::uuid)), 0,
  'ni les commandes de ce client');
reset role;
select essai.personne();

select essai.devenir(:KOFI::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.clients_liste('')), 0,
  'un client ne lit pas le fichier des autres');
select essai.egal((select count(*)::int from public.client_commandes(:BRICE::uuid)), 0,
  'ni les commandes de son voisin');
-- Et pas davantage la sienne par cette porte : l'écran est celui de
-- l'enseigne. Le client a « mes_commandes », qui ne rend que les siennes.
select essai.egal((select count(*)::int from public.client_commandes(:KOFI::uuid)), 0,
  'ni même les siennes : ce n''est pas sa porte');
reset role;
select essai.personne();

set role anon;
select essai.refuse($$select count(*) from public.clients_liste('')$$,
  'un visiteur appelle la liste');
select essai.refuse(
  $$select count(*) from public.client_commandes(
      'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'::uuid)$$,
  'ou les commandes d''un client');
reset role;

-- ---------------------------------------------------------
select essai.titre('Ce qui n''existe pas ne rend rien');
-- ---------------------------------------------------------
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.client_commandes(null)), 0,
  'aucun client demandé, aucune commande rendue');
select essai.egal((select count(*)::int from public.client_commandes(
    '00000000-0000-0000-0000-000000000000'::uuid)), 0,
  'un compte inconnu n''ouvre rien');
reset role;
select essai.personne();
