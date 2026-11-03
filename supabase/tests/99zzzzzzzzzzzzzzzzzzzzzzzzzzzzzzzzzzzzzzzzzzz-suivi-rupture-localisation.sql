-- =========================================================
-- Trois demandes de l'équipe (3.75.0)
--
-- Ce qu'on prouve :
--   1. une commande en attente dont un produit est parti en rupture : la
--      base dit lesquels (au client, par son numéro ou son compte ; à
--      personne d'autre) ; la fonction de paiement le voit ;
--   2. le suivi de Personnel donne le temps de préparation de chaque
--      marchand (« vue » → « préparée ») et le délai réglé ;
--   3. le livreur en course coupe sa localisation : la base le retient,
--      alerte BIZZOO une fois (ça sonne) et le livreur ; « rétablie » quand
--      elle revient ; une position qui ne bouge plus depuis le seuil, aussi ;
--      une course annulée après « Commande reçue » le dit.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set LR       '''d7d7d7d7-0000-0000-0000-000000000001'''

select essai.titre('Le décor : une boutique, deux produits, un livreur de BIZZOO');
update public.paiement set livraison_latitude = null, livraison_longitude = null where id = 1;
update public.boutiques set actif = true, ouvertures = null where id = 'bou_informatique';
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible) values
  ('prod_rup_a', 'bou_informatique', 'Casque rupture', 7000, 'sc_hightech_accessoires', 5, true),
  ('prod_rup_b', 'bou_informatique', 'Câble rupture', 1000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = excluded.stock, disponible = true, masque = false;
insert into auth.users (id, email) values (:LR::uuid, 'lr.localisation@essai.bj') on conflict do nothing;
update public.profils set role = 'livreur', actif = true, boutique_id = null, nom = 'Sika', tel = '0196500077',
       vehicule = 'moto'
 where id = :LR::uuid;
insert into public.positions_livreurs (profil_id, latitude, longitude, adresse, enregistre_le)
values (:LR::uuid, 6.37, 2.42, 'Cotonou', now())
on conflict (profil_id) do update set latitude = 6.37, longitude = 2.42, enregistre_le = now(),
  localisation_coupee_le = null, fix_le = null;
create function pg_temp.commander(articles jsonb) returns jsonb language plpgsql as $$
declare g jsonb;
begin
  perform essai.devenir('ffffffff-2222-2222-2222-222222222222'::uuid);
  set local role authenticated;
  g := public.creer_commande('{"nom":"Rosine","tel":"97666123","adresse":"Godomey"}'::jsonb,
    articles, '', true, true);
  reset role;
  perform essai.personne();
  return g;
end $$;

select essai.titre('1. Commande en attente, produit parti en rupture');
select pg_temp.commander('[{"produit_id":"prod_rup_a","quantite":2},{"produit_id":"prod_rup_b","quantite":3}]'::jsonb)
  ->> 'id' as c1 \gset
set role anon;
select essai.egal(jsonb_array_length(public.manquants_commande(:'c1', '97666123') -> 'manquants'), 0,
  'tout est en stock : rien ne manque');
reset role;
update public.produits set stock = 1 where id = 'prod_rup_a';
set role anon;
select public.manquants_commande(:'c1', '97 66 61 23') as m \gset
reset role;
select essai.egal((:'m'::jsonb -> 'manquants' -> 0 ->> 'nom') || ' / ' || (:'m'::jsonb -> 'manquants' -> 0 ->> 'reste') ||
                  ' sur ' || (:'m'::jsonb -> 'manquants' -> 0 ->> 'demande'),
  'Casque rupture / 1 sur 2', 'plus qu''un casque pour deux commandés : il manque');
select essai.egal((:'m'::jsonb -> 'autres' -> 0 ->> 'produit_id') || ' × ' || (:'m'::jsonb -> 'autres' -> 0 ->> 'quantite'),
  'prod_rup_b × 3', 'le reste, pour refaire le panier : 3 câbles');
set role anon;
select essai.egal(jsonb_array_length(public.manquants_commande(:'c1', '0100000000') -> 'manquants'), 0,
  'un autre numéro ne lit rien');
reset role;
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.egal(jsonb_array_length(public.manquants_commande(:'c1') -> 'manquants'), 1,
  'le compte du client, connecté, le lit sans numéro');
reset role; select essai.personne();
select essai.egal(jsonb_array_length(public.commande_pour_paiement(:'c1', '97666123') -> 'manquants'), 1,
  'la fonction de paiement le voit : elle refusera d''encaisser');
update public.produits set masque = true, stock = 5 where id = 'prod_rup_a';
select essai.egal((public.manquants_commande(:'c1', '97666123') -> 'manquants' -> 0 ->> 'reste'), '0',
  'un produit retiré de la vente : il manque en entier');
update public.produits set masque = false, stock = 0, sur_commande = true where id = 'prod_rup_a';
select essai.egal(jsonb_array_length(public.manquants_commande(:'c1', '97666123') -> 'manquants'), 0,
  'un produit « sur commande » ne manque jamais');
update public.produits set sur_commande = false, stock = 5 where id = 'prod_rup_a';
select essai.egal(jsonb_array_length(public.manquants_commande(:'c1', '97666123') -> 'manquants'), 0,
  'le stock revenu : plus rien ne manque');

select essai.titre('2. Le temps de préparation de chaque marchand');
select public.marquer_payee(:'c1', 'TRX-RUP-1',
  (select coalesce(c.acompte, c.total)::int from public.commandes c where c.id = :'c1'), 'feexpay');
insert into public.rh_journal_lignes (commande_id, ligne_id, boutique_id, quoi, valeur, le)
select l.commande_id, l.id, l.boutique_id, 'etat', v.valeur, now() - v.il_y_a
  from public.commande_lignes l
 cross join (values ('vue', interval '40 minutes'), ('preparee', interval '26 minutes')) v(valeur, il_y_a)
 where l.commande_id = :'c1';
update public.rh_reglages_suivi set preparation_min = 20;
select (select d from public.rh_suivi_donnees(now() - interval '1 day', now() + interval '1 day', :'c1') d) as s \gset
select essai.egal((:'s'::jsonb -> 'preparation' -> 0 ->> 'minutes'), '14',
  'vue il y a 40 min, préparée il y a 26 : 14 minutes de préparation');
select essai.egal((:'s'::jsonb ->> 'preparation_seuil_min'), '20', 'le délai convenu : 20 minutes');
select essai.verifie((:'s'::jsonb -> 'lignes' -> 0 ->> 'preparee_le') is not null,
  'chaque article dit quand il a été préparé');

select essai.titre('3. Le livreur coupe sa localisation pendant la course');
-- L'enseigne lui confie la course (la cascade, elle, a ses propres essais).
select essai.devenir('11111111-1111-1111-1111-111111111111'::uuid); set role authenticated;
select public.assigner_livreur(:'c1', 'bou_informatique', :LR::uuid);
reset role; select essai.personne();
select essai.devenir(:LR::uuid); set role authenticated;
select public.accepter_course(:'c1', 'bou_informatique');
select public.ouvrir_suivi_livreur() ->> 'jeton' as jeton \gset
reset role; select essai.personne();
select essai.verifie(public.livreur_en_course(:LR::uuid), 'le décor : Sika est en course, « Commande reçue »');
delete from public.notifications where type in ('livreur_sans_localisation', 'localisation_a_reactiver',
                                                 'livreur_localisation_retablie');
delete from public.alertes_localisation;
-- Une écriture toutes les 5 secondes au plus : la précédente date.
update public.positions_livreurs set enregistre_le = now() - interval '1 minute' where profil_id = :LR::uuid;
set role anon;
select public.position_livreur(:'jeton', 6.38, 2.42, 10, true, 3) as r \gset
reset role;
select essai.verifie((select localisation_coupee_le is null and fix_le > now() - interval '1 minute'
                        from public.positions_livreurs where profil_id = :LR::uuid),
  'localisation allumée : la position mesurée il y a 3 s est retenue');
select essai.egal(public.alerter_localisations(), 0, 'tout va bien : aucune alerte');
set role anon;
select public.position_livreur(:'jeton', 6.38, 2.42, 10, false, 300) as r \gset
reset role;
select essai.verifie((select localisation_coupee_le is not null from public.positions_livreurs where profil_id = :LR::uuid),
  'localisation coupée : la base le retient aussitôt');
select essai.egal(public.alerter_localisations(), 0, 'pas avant une minute (un clignement ne sonne pas)');
update public.positions_livreurs set localisation_coupee_le = now() - interval '2 minutes' where profil_id = :LR::uuid;
select essai.egal(public.alerter_localisations(), 1, 'au-delà d''une minute : une alerte');
select essai.verifie((select count(*) > 0 and bool_and(sonne) from public.notifications
                       where type = 'livreur_sans_localisation' and titre = 'Localisation coupée — Sika'),
  'BIZZOO reçoit « Localisation coupée — Sika », et ça sonne');
select essai.verifie(exists (select 1 from public.notifications where type = 'livreur_sans_localisation'
                               and corps like '%Appelez-le : 0196500077%'),
  'avec son numéro, pour l''appeler');
select essai.verifie(exists (select 1 from public.notifications where destinataire = :LR::uuid
                               and type = 'localisation_a_reactiver' and sonne),
  'Sika reçoit « Réactivez votre localisation »');
select essai.egal(public.alerter_localisations(), 0, 'une seule alerte par épisode');
-- Une écriture toutes les 5 secondes au plus : la précédente date.
update public.positions_livreurs set enregistre_le = now() - interval '1 minute' where profil_id = :LR::uuid;
set role anon;
select public.position_livreur(:'jeton', 6.39, 2.42, 10, true, 2) as r \gset
reset role;
select essai.egal(public.alerter_localisations(), 0, 'la localisation revient');
select essai.verifie(exists (select 1 from public.notifications where type = 'livreur_localisation_retablie'
                               and titre = 'Localisation rétablie — Sika' and not sonne),
  'BIZZOO lit « Localisation rétablie — Sika » (sans sonnerie)');
-- Le téléphone parle encore, mais sa position ne bouge plus (plus de mesure).
update public.positions_livreurs set fix_le = now() - interval '30 minutes', enregistre_le = now()
 where profil_id = :LR::uuid;
select essai.egal(public.alerter_localisations(), 1, 'plus aucune position mesurée depuis 30 min : alerte');
select essai.verifie(exists (select 1 from public.notifications where titre = 'Livreur sans position — Sika'),
  '« Livreur sans position — Sika »');
select (select d from public.rh_suivi_donnees(now() - interval '1 day', now() + interval '1 day', :'c1') d) as s \gset
update public.positions_livreurs set fix_le = now() where profil_id = :LR::uuid;
select public.alerter_localisations();

select essai.titre('4. La course annulée après « Commande reçue » le dit');
delete from public.notifications where type = 'course_annulee_livreur';
select essai.devenir(:LR::uuid); set role authenticated;
select public.refuser_course(:'c1', 'Panne');
reset role; select essai.personne();
select essai.verifie(exists (select 1 from public.notifications where type = 'course_annulee_livreur'
                               and titre like 'Course annulée après acceptation par Sika — %'),
  '« Course annulée après acceptation par Sika — … »');
select essai.egal(public.alerter_localisations(), 0, 'plus en course : plus d''alerte de localisation');
select essai.egal((select count(*)::int from public.alertes_localisation where livreur = :LR::uuid), 0,
  'l''épisode est clos');
update public.rh_reglages_suivi set preparation_min = null;
