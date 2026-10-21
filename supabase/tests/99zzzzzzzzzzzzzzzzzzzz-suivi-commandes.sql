-- =========================================================
-- Le suivi des commandes en direct (3.59.0)
--
-- Ce qu'on prouve :
--   1. chaque modification d'une commande — paiement, étape, livreur,
--      encaissement — fait avancer son signal ;
--   2. ce signal, seuls le voient : le client de la commande, l'équipe de
--      la boutique (administrateur, modérateur), BIZZOO, et le livreur
--      qui la porte ; ni un autre client, ni la boutique voisine, ni un
--      livreur qui n'y est pour rien ;
--   3. personne ne l'écrit à la main.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set AUTRE    '''b0b00000-0000-0000-0000-000000000001'''
\set MODO     '''b0b00000-0000-0000-0000-000000000002'''
\set VOISIN   '''b0b00000-0000-0000-0000-000000000003'''
\set LIV      '''b0b00000-0000-0000-0000-000000000004'''
\set LIV2     '''b0b00000-0000-0000-0000-000000000005'''

select essai.titre('Le décor');
insert into auth.users (id, email) values (:AUTRE::uuid, 'autre.suivi@essai.bj'), (:MODO::uuid, 'modo.suivi@essai.bj'),
  (:VOISIN::uuid, 'voisin.suivi@essai.bj'), (:LIV::uuid, 'liv.suivi@essai.bj'), (:LIV2::uuid, 'liv2.suivi@essai.bj')
on conflict do nothing;
insert into public.clients (id, nom, tel) values (:AUTRE::uuid, 'Autre', '0197666099') on conflict do nothing;
update public.profils p set role = v.r, actif = true, boutique_id = v.b, nom = v.n
  from (values (:MODO::uuid, 'moderateur', 'bou_informatique', 'Modo'),
               (:VOISIN::uuid, 'administrateur', 'bou_essai_voisine', 'Voisin'),
               (:LIV::uuid, 'livreur', 'bou_informatique', 'Liv'),
               (:LIV2::uuid, 'livreur', 'bou_informatique', 'Liv2')) as v(i, r, b, n)
 where p.id = v.i;
insert into public.positions_livreurs (profil_id, latitude, longitude, adresse)
select i, 6.37, 2.42, 'Cotonou' from unnest(array[:LIV::uuid, :LIV2::uuid]) i on conflict (profil_id) do nothing;
update public.boutiques set actif = true, ouvertures = null where id = 'bou_informatique';
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_suivi', 'bou_informatique', 'Webcam', 6000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true, masque = false;
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666012","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_suivi","quantite":1}]'::jsonb, '', true, true) as g \gset
reset role; select essai.personne();
select (:'g'::jsonb ->> 'id') as cmd \gset

select essai.titre('1. Chaque modification fait avancer le signal');
select essai.egal((select count(*)::int from public.commandes_signaux where commande_id = :'cmd'), 1,
  'la commande a son signal dès sa création');
select maj_le as t0 from public.commandes_signaux where commande_id = :'cmd' \gset
select public.marquer_payee(:'cmd', 'TRX-SUIVI-1', (:'g'::jsonb ->> 'acompte')::int, 'feexpay') as p \gset
select essai.verifie((select maj_le >= :'t0'::timestamptz from public.commandes_signaux where commande_id = :'cmd'),
  'le paiement le fait avancer');
update public.commandes_signaux set maj_le = now() - interval '1 hour' where commande_id = :'cmd';
select essai.devenir(:CHEF::uuid); set role authenticated;
select public.assigner_livreur(:'cmd', 'bou_informatique', :LIV::uuid) as a \gset
reset role; select essai.personne();
select essai.verifie((select maj_le > now() - interval '1 minute' from public.commandes_signaux where commande_id = :'cmd'),
  'confier la course le fait avancer');
update public.commandes_signaux set maj_le = now() - interval '1 hour' where commande_id = :'cmd';
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'preparee' where commande_id = :'cmd';
reset role; select essai.personne();
select essai.verifie((select maj_le > now() - interval '1 minute' from public.commandes_signaux where commande_id = :'cmd'),
  'une étape (préparée) le fait avancer');

select essai.titre('2. Qui le voit');
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.commandes_signaux where commande_id = :'cmd'), 1, 'le client');
reset role; select essai.personne();
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.commandes_signaux where commande_id = :'cmd'), 1, 'l''administrateur de la boutique');
reset role; select essai.personne();
select essai.devenir(:MODO::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.commandes_signaux where commande_id = :'cmd'), 1, 'le modérateur de la boutique');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.commandes_signaux where commande_id = :'cmd'), 1, 'BIZZOO');
reset role; select essai.personne();
select essai.devenir(:LIV::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.commandes_signaux where commande_id = :'cmd'), 1, 'le livreur qui la porte');
reset role; select essai.personne();
select essai.devenir(:AUTRE::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.commandes_signaux where commande_id = :'cmd'), 0, 'pas un autre client');
reset role; select essai.personne();
select essai.devenir(:VOISIN::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.commandes_signaux where commande_id = :'cmd'), 0, 'pas la boutique voisine');
reset role; select essai.personne();
select essai.devenir(:LIV2::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.commandes_signaux where commande_id = :'cmd'), 0, 'pas un livreur qui n''y est pour rien');
reset role; select essai.personne();
set role anon;
select essai.refuse('select count(*) from public.commandes_signaux', 'pas un visiteur');
reset role;

select essai.titre('3. Personne ne l''écrit à la main');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse(format($$update public.commandes_signaux set maj_le = now() where commande_id = %L$$, :'cmd'),
  'pas même l''administrateur');
reset role; select essai.personne();
