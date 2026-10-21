-- =========================================================
-- La commande d'un compte reste la sienne (3.63.0)
--
-- Le 21 octobre 2026, des commandes de test sont nées sans compte
-- rattaché alors que leurs auteurs se croyaient connectés. L'essentiel
-- du correctif est dans l'application (la session ne tombe plus en
-- silence) ; ici, les deux parts de la base.
--
-- Ce qu'on prouve :
--   1. un compte connecté SANS fiche client commande : la commande est à
--      son compte, et sa fiche se pose avec ce qu'il a donné ;
--   2. un compte dont la fiche d'équipe est EN ATTENTE est un acheteur
--      comme un autre : même chose, et la fiche en attente s'efface ;
--   3. un vrai compte d'équipe reste écarté : sa commande n'a pas de
--      compte, et aucune fiche client ne lui est posée ;
--   4. le suivi par numéro dit l'étape de chaque boutique — « nouvelle »
--      à la commande, « remise » quand la boutique l'a déclaré —, et si
--      le client a confirmé ; un autre numéro ne lit rien.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE  '''11111111-1111-1111-1111-111111111111'''
\set CHEF      '''22222222-2222-2222-2222-222222222222'''
\set SANSFICHE '''e3e3e3e3-0000-0000-0000-000000000001'''
\set ENATTENTE '''e3e3e3e3-0000-0000-0000-000000000002'''

select essai.titre('Le décor : un produit, une boutique ouverte, deux comptes sans fiche client');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set actif = true, ouvertures = null where id = 'bou_informatique';
reset role; select essai.personne();
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_sans_fiche', 'bou_informatique', 'Câble HDMI', 3000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true, prix = 3000, masque = false;
-- Un compte créé par SMS dont le numéro n'a jamais été confirmé : pas de
-- fiche client ; « compte: client » : pas de fiche d'équipe non plus.
insert into auth.users (id, email, phone, raw_user_meta_data)
values (:SANSFICHE::uuid, '', '2290197600001', '{"compte":"client"}'::jsonb)
on conflict do nothing;
-- Un compte créé par e-mail hors de l'application : il reçoit, comme tous
-- ceux-là, une fiche d'équipe EN ATTENTE.
insert into auth.users (id, email) values (:ENATTENTE::uuid, 'attente.fiche@essai.bj')
on conflict do nothing;
select essai.verifie(not exists (select 1 from public.clients where id = :SANSFICHE::uuid)
                 and not exists (select 1 from public.profils where id = :SANSFICHE::uuid),
  'le premier n''a ni fiche client ni fiche d''équipe');
select essai.verifie(exists (select 1 from public.profils
                              where id = :ENATTENTE::uuid and not actif and role = 'moderateur'),
  'le second a une fiche d''équipe en attente');

select essai.titre('1. Sans fiche : la commande est à son compte, et la fiche se pose');
select essai.devenir(:SANSFICHE::uuid); set role authenticated;
select public.creer_commande('{"nom":"Nadège","tel":"97600001","adresse":"Calavi, Tokpa"}'::jsonb,
  '[{"produit_id":"prod_sans_fiche","quantite":1}]'::jsonb, '', true, true) as g1 \gset
reset role; select essai.personne();
select (:'g1'::jsonb ->> 'id') as cmd1 \gset
select essai.verifie((select client_id = :SANSFICHE::uuid from public.commandes where id = :'cmd1'),
  'la commande porte son compte');
select essai.egal((select nom || '/' || tel || '/' || adresse from public.clients where id = :SANSFICHE::uuid),
  'Nadège/97600001/Calavi, Tokpa', 'sa fiche est posée avec ce qu''il a donné');
select essai.verifie((select not tel_verifie from public.clients where id = :SANSFICHE::uuid),
  'et elle naît non vérifiée');
-- Depuis son compte, il lit sa commande et ses lignes : c'est tout l'enjeu.
select essai.devenir(:SANSFICHE::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.commande_lignes where commande_id = :'cmd1'), 1,
  'il lit les lignes de sa commande');
reset role; select essai.personne();

select essai.titre('2. Fiche d''équipe en attente : un acheteur comme un autre');
select essai.devenir(:ENATTENTE::uuid); set role authenticated;
select public.creer_commande('{"nom":"Firmin","tel":"97600002","adresse":"Akpakpa"}'::jsonb,
  '[{"produit_id":"prod_sans_fiche","quantite":1}]'::jsonb, '', true, true) as g2 \gset
reset role; select essai.personne();
select (:'g2'::jsonb ->> 'id') as cmd2 \gset
select essai.verifie((select client_id = :ENATTENTE::uuid from public.commandes where id = :'cmd2'),
  'la commande porte son compte');
select essai.verifie(not exists (select 1 from public.profils where id = :ENATTENTE::uuid),
  'la fiche d''équipe en attente s''est effacée');
select essai.egal((select nom from public.clients where id = :ENATTENTE::uuid), 'Firmin',
  'une fiche client la remplace');

select essai.titre('3. Un vrai compte d''équipe reste écarté');
select essai.devenir(:CHEF::uuid); set role authenticated;
select public.creer_commande('{"nom":"Chef","tel":"97600003","adresse":"Ganhi"}'::jsonb,
  '[{"produit_id":"prod_sans_fiche","quantite":1}]'::jsonb, '', true, true) as g3 \gset
reset role; select essai.personne();
select (:'g3'::jsonb ->> 'id') as cmd3 \gset
select essai.verifie((select client_id is null from public.commandes where id = :'cmd3'),
  'sa commande n''a pas de compte');
select essai.verifie(not exists (select 1 from public.clients where id = :CHEF::uuid),
  'et aucune fiche client ne lui a été posée');

select essai.titre('4. Le suivi par numéro dit l''étape de chaque boutique');
-- En visiteur : personne n'est connecté, le numéro seul fait foi.
select (public.suivre_commande(:'cmd1', '97600001') -> 'etats' -> 'bou_informatique') as e1 \gset
select essai.egal(:'e1'::jsonb ->> 'etat', 'nouvelle', 'à la commande : « nouvelle »');
select essai.egal((:'e1'::jsonb ->> 'confirme')::boolean, false, 'et rien n''est confirmé');
select public.marquer_payee(:'cmd1', 'TRX-SANS-FICHE', (:'g1'::jsonb ->> 'acompte')::int, 'feexpay') as p \gset
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'vue' where commande_id = :'cmd1';
update public.commande_lignes set etat = 'preparee' where commande_id = :'cmd1';
update public.commande_lignes set etat = 'en_livraison' where commande_id = :'cmd1';
update public.commande_lignes set etat = 'remise' where commande_id = :'cmd1';
reset role; select essai.personne();
select (public.suivre_commande(:'cmd1', '97600001') -> 'etats' -> 'bou_informatique') as e2 \gset
select essai.egal(:'e2'::jsonb ->> 'etat', 'remise', 'remise par la boutique : « remise »');
select essai.egal((:'e2'::jsonb ->> 'confirme')::boolean, false, 'pas encore confirmée par le client');
select essai.devenir(:SANSFICHE::uuid); set role authenticated;
select public.confirmer_reception(:'cmd1', 'bou_informatique') as recu \gset
reset role; select essai.personne();
select (public.suivre_commande(:'cmd1', '97600001') -> 'etats' -> 'bou_informatique') as e3 \gset
select essai.egal((:'e3'::jsonb ->> 'confirme')::boolean, true, 'confirmée depuis son compte : le numéro le dit aussi');
select essai.verifie(public.suivre_commande(:'cmd1', '00000000') is null, 'un autre numéro ne lit rien');
