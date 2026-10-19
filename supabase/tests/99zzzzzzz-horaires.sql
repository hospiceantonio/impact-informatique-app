-- =========================================================
-- Les jours et heures d'ouverture des boutiques (3.59.0)
--
-- Ce qu'on prouve :
--   1. le format est vérifié (jours connus, HH:MM, ouverture avant
--      fermeture, au moins un jour ouvert) ;
--   2. « ouverte » se lit à l'heure du BÉNIN (UTC+1), pas du serveur ;
--   3. une boutique créée depuis l'application doit avoir ses horaires ;
--   4. une boutique fermée — hors de ses heures, ou par son
--      interrupteur — ne reçoit pas de commande ; ouverte, si.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''

select essai.titre('1. Le format');
select essai.egal(public.ouvertures_valides('{"lun":{"de":"08:00","a":"19:00"},"dim":null}'), true,
  'lundi 8 h – 19 h, fermé le dimanche : valable');
select essai.egal(public.ouvertures_valides('{"lun":{"de":"19:00","a":"08:00"}}'), false,
  'la fermeture avant l''ouverture : refusée');
select essai.egal(public.ouvertures_valides('{"lundi":{"de":"08:00","a":"19:00"}}'), false,
  'un jour inconnu : refusé');
select essai.egal(public.ouvertures_valides('{"lun":{"de":"8h","a":"19:00"}}'), false,
  '« 8h » n''est pas une heure : refusée');
select essai.egal(public.ouvertures_valides('{"lun":null,"mar":null}'), false,
  'aucun jour ouvert : refusé');
select essai.egal(public.ouvertures_valides('{"sam":{"de":"09:00","a":"24:00"}}'), true,
  'jusqu''à minuit : valable');
select essai.refuse($$update public.boutiques set ouvertures = '{"lun":{"de":"20:00","a":"09:00"}}'
  where id = 'bou_informatique'$$, 'la base refuse d''enregistrer des horaires faux');

select essai.titre('2. À l''heure du Bénin');
-- Le lundi 19 octobre 2026. 07:30 UTC = 08:30 à Cotonou.
select essai.egal(public.boutique_ouverte('{"lun":{"de":"08:00","a":"19:00"}}',
  '2026-10-19 07:30:00+00'), true, 'lundi 08:30 à Cotonou (07:30 UTC) : ouverte');
select essai.egal(public.boutique_ouverte('{"lun":{"de":"08:00","a":"19:00"}}',
  '2026-10-19 06:30:00+00'), false, 'lundi 07:30 à Cotonou : pas encore ouverte');
select essai.egal(public.boutique_ouverte('{"lun":{"de":"08:00","a":"19:00"}}',
  '2026-10-19 18:00:00+00'), false, 'lundi 19:00 à Cotonou : fermée (19 h exclu)');
select essai.egal(public.boutique_ouverte('{"lun":{"de":"00:00","a":"02:00"}}',
  '2026-10-18 23:30:00+00'), true, 'dimanche 23:30 UTC, c''est déjà lundi 00:30 à Cotonou : ouverte');
select essai.egal(public.boutique_ouverte('{"lun":{"de":"08:00","a":"19:00"},"dim":null}',
  '2026-10-18 12:00:00+00'), false, 'le dimanche, fermé ce jour-là');
select essai.egal(public.boutique_ouverte(null, now()), true,
  'sans horaires encore : ouverte, comme avant');

select essai.titre('3. Une boutique créée depuis l''application a ses horaires');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse($$insert into public.boutiques (id, nom, ordre) values ('bou_sans_horaires', 'Sans horaires', 90)$$,
  'sans horaires : refusée');
insert into public.boutiques (id, nom, ordre, ouvertures)
values ('bou_horaires', 'Avec horaires', 91, '{"lun":{"de":"08:00","a":"18:00"}}');
select essai.egal((select count(*)::int from public.boutiques where id = 'bou_horaires'), 1,
  'avec ses horaires : créée');
reset role; select essai.personne();
delete from public.boutiques where id = 'bou_horaires';

select essai.titre('4. Fermée, elle ne reçoit pas de commande');
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_horaires', 'bou_informatique', 'Clé USB', 4000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true;
-- Ouverte demain seulement : fermée maintenant, quel que soit l'instant
-- où l'essai tourne.
update public.boutiques
   set ouvertures = jsonb_build_object(
     (array['lun','mar','mer','jeu','ven','sam','dim'])
       [extract(isodow from (now() at time zone 'Africa/Porto-Novo') + interval '1 day')::int],
     jsonb_build_object('de', '00:00', 'a', '24:00'))
 where id = 'bou_informatique';
select essai.egal((select public.boutique_ouverte(ouvertures) from public.boutiques where id = 'bou_informatique'),
  false, 'la boutique est fermée en ce moment');
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.refuse($$select public.creer_commande('{"nom":"Afi","tel":"97666003","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_horaires","quantite":1}]'::jsonb)$$, 'commander chez elle : refusé');
reset role; select essai.personne();

-- Ouverte toute la journée d'aujourd'hui : la commande passe.
update public.boutiques
   set ouvertures = jsonb_build_object(
     (array['lun','mar','mer','jeu','ven','sam','dim'])
       [extract(isodow from (now() at time zone 'Africa/Porto-Novo'))::int],
     jsonb_build_object('de', '00:00', 'a', '24:00'))
 where id = 'bou_informatique';
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666003","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_horaires","quantite":1}]'::jsonb) ->> 'id' as cmd \gset
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.commandes where id = :'cmd'), 1,
  'ouverte : la commande passe');

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set actif = false where id = 'bou_informatique';
reset role; select essai.personne();
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.refuse($$select public.creer_commande('{"nom":"Afi","tel":"97666003","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_horaires","quantite":1}]'::jsonb)$$, 'fermée par son interrupteur : refusé aussi');
reset role; select essai.personne();

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set actif = true, ouvertures = null where id = 'bou_informatique';
reset role; select essai.personne();
