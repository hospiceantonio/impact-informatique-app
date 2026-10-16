-- =========================================================
-- Le client voit qui lui livre sa commande
--
-- « livreurs_de_ma_commande » rend, boutique par boutique, le
-- nom et le numéro du livreur à qui la course est confiée. Le
-- client l'appelle ou lui écrit sur WhatsApp depuis son reçu.
--
-- Ce qu'on prouve :
--   1. rien avant que la course soit confiée ;
--   2. le client qui a commandé voit le nom et le numéro, et rien
--      d'autre ;
--   3. sans compte, il faut le numéro donné à la commande ; un
--      autre client, ou un mauvais numéro, ne voit rien ;
--   4. une commande impayée ne dit rien ;
--   5. une fois la réception confirmée, le numéro disparaît ;
--   6. un livreur désactivé ne paraît plus.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set KOFI     '''55555555-5555-5555-5555-555555555555'''
\set AUTRE    '''dddddddd-7777-7777-7777-777777777777'''
\set PORTEUR2 '''cccccccc-7777-7777-7777-777777777777'''

-- ---------------------------------------------------------
select essai.titre('Le décor : un livreur, une commande payée');

insert into auth.users (id, email) values
  (:PORTEUR2::uuid, 'porteur2@impact.bj'),
  (:AUTRE::uuid, 'autre@client.bj')
on conflict do nothing;
insert into public.profils (id, email, nom, tel, role, boutique_id, actif) values
  (:PORTEUR2::uuid, 'porteur2@impact.bj', 'Sèna', '0196554433',
   'livreur', 'bou_informatique', true)
on conflict (id) do update
   set role = 'livreur', boutique_id = 'bou_informatique', actif = true,
       nom = excluded.nom, tel = excluded.tel;

insert into public.produits
  (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_qui_livre', 'bou_informatique', 'Souris', 4000,
        'sc_hightech_accessoires', 20, true)
on conflict (id) do update set stock = 20, disponible = true;

select essai.devenir(:KOFI::uuid); set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97 22 22 22","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_qui_livre","quantite":1}]'::jsonb) ->> 'id' as cmd \gset
select public.creer_commande('{"nom":"Kofi","tel":"97222222","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_qui_livre","quantite":1}]'::jsonb) ->> 'id' as impayee \gset
reset role; select essai.personne();

select public.marquer_payee(:'cmd', 'TRX-QUI-LIVRE',
  (select total from public.commandes where id = :'cmd'), 'feexpay') as e \gset

-- ---------------------------------------------------------
select essai.titre('1. Rien avant que la course soit confiée');

select essai.devenir(:KOFI::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.livreurs_de_ma_commande(:'cmd')), 0,
  'payée mais pas encore confiée : aucun livreur à montrer');
reset role; select essai.personne();

insert into public.positions_livreurs (profil_id, latitude, longitude, adresse)
  select p.id, 6.3703, 2.3912, 'Cotonou (essai)' from public.profils p where p.role = 'livreur'
  on conflict (profil_id) do nothing;  -- les livreurs ont validé leur position
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'preparee' where commande_id = :'cmd';
select public.assigner_livreur(:'cmd', 'bou_informatique', :PORTEUR2::uuid) as n \gset
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('2. Le client voit son livreur, et rien d''autre');

select essai.devenir(:KOFI::uuid); set role authenticated;
select essai.egal(
  (select boutique_id || ' / ' || nom || ' / ' || telephone || ' / ' || indicatif
     from public.livreurs_de_ma_commande(:'cmd')),
  'bou_informatique / Sèna / 0196554433 / 229',
  'la boutique, le nom du livreur, son numéro et l''indicatif');
select essai.egal((select count(*)::int from public.livreurs_de_ma_commande(:'cmd')), 1,
  'une ligne par boutique, même si la boutique a plusieurs articles');
-- Le client ne lit toujours pas la fiche du livreur directement.
select essai.egal(
  (select count(*)::int from public.profils where id = :PORTEUR2::uuid), 0,
  'et la table des comptes lui reste fermée');
reset role; select essai.personne();

select essai.verifie(
  pg_get_function_result('public.livreurs_de_ma_commande(text, text)'::regprocedure)
    !~* '(email|prix|total|montant|marge|adresse)',
  'la fonction ne rend ni e-mail, ni adresse, ni montant');

-- ---------------------------------------------------------
select essai.titre('3. Sans compte, il faut le numéro de la commande');

set role anon;
select essai.egal(
  (select nom from public.livreurs_de_ma_commande(:'cmd', '97 22 22 22')),
  'Sèna', 'avec le numéro donné à la commande : le livreur paraît');
select essai.egal(
  (select count(*)::int from public.livreurs_de_ma_commande(:'cmd', '97000000')), 0,
  'avec un autre numéro : rien');
select essai.egal(
  (select count(*)::int from public.livreurs_de_ma_commande(:'cmd')), 0,
  'sans numéro : rien');
reset role;

select essai.devenir(:AUTRE::uuid); set role authenticated;
select essai.egal(
  (select count(*)::int from public.livreurs_de_ma_commande(:'cmd')), 0,
  'un autre client connecté ne voit rien');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('4. Une commande impayée ne dit rien');

select essai.devenir(:KOFI::uuid); set role authenticated;
select essai.egal(
  (select count(*)::int from public.livreurs_de_ma_commande(:'impayee')), 0,
  'pas payée : pas de livreur');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('6. Un livreur désactivé ne paraît plus');

update public.profils set actif = false where id = :PORTEUR2::uuid;
select essai.devenir(:KOFI::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.livreurs_de_ma_commande(:'cmd')), 0,
  'désactivé : son numéro ne s''affiche plus');
reset role; select essai.personne();
update public.profils set actif = true where id = :PORTEUR2::uuid;

-- ---------------------------------------------------------
select essai.titre('5. La réception confirmée, le numéro disparaît');

select essai.devenir(:PORTEUR2::uuid); set role authenticated;
select public.avancer_livraison(:'cmd', 'bou_informatique', 'en_livraison') as a \gset
reset role; select essai.personne();

select essai.devenir(:KOFI::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.livreurs_de_ma_commande(:'cmd')), 1,
  'pendant la course : toujours là');
reset role; select essai.personne();

select essai.devenir(:PORTEUR2::uuid); set role authenticated;
select public.avancer_livraison(:'cmd', 'bou_informatique', 'remise') as b \gset
reset role; select essai.personne();

select essai.devenir(:KOFI::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.livreurs_de_ma_commande(:'cmd')), 1,
  'remise par le livreur : encore là, le client peut l''appeler s''il manque quelque chose');
select public.confirmer_reception(:'cmd', 'bou_informatique') as c \gset
select essai.egal((select count(*)::int from public.livreurs_de_ma_commande(:'cmd')), 0,
  'réception confirmée par le client : le numéro disparaît');
reset role; select essai.personne();
