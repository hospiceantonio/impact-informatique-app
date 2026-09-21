-- =========================================================
-- Le compte pour commander : un interrupteur, pas un écran.
--
-- La septième étape ferme la caisse à qui n'a pas de compte.
-- Elle ne vaut que si elle tient DANS LA BASE : cacher le
-- bouton ne ferme rien, il suffit d'appeler la fonction
-- directement — ce que fait ce fichier, ligne après ligne.
--
-- Cinq choses à prouver :
--
--   1. ÉTEINT, RIEN NE CHANGE. C'est la moitié la plus
--      importante : l'interrupteur arrive éteint chez le
--      gérant, et poser ce fichier ne doit fermer aucune
--      caisse le jour où on l'exécute ;
--   2. PERSONNE D'AUTRE QUE L'ENSEIGNE ne le bascule — ni un
--      visiteur, ni un client, ni le chef d'une boutique ;
--   3. ALLUMÉ, LA COMMANDE SANS COMPTE EST REFUSÉE, et le
--      client connecté passe comme avant ;
--   4. UN COMPTE DE L'ÉQUIPE N'EST PAS UN COMPTE CLIENT, et
--      on le lui dit avec ses mots à lui : il EST connecté,
--      lui répondre « connectez-vous » le ferait chercher ;
--   5. LA RÈGLE NE SE PERD PAS. La ligne est unique et ne
--      peut pas disparaître ; et si malgré tout elle
--      disparaissait, la caisse se ROUVRE — une règle qui
--      force une inscription ne doit pas pouvoir verrouiller
--      la boutique un samedi soir.
--
-- Et une chose qui ne doit PAS changer : on regarde le
-- catalogue sans compte, interrupteur allumé ou non. On ne
-- ferme pas le magasin, seulement la caisse.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set AWA      '''44444444-4444-4444-4444-444444444444'''

-- Le message d'un refus, pour pouvoir le LIRE et non seulement
-- constater qu'il y en a eu un. Deux refus différents doivent dire
-- deux choses différentes, sinon l'un des deux envoie le client
-- chercher au mauvais endroit.
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

select essai.titre('Le décor : un article, et l''interrupteur tel qu''il arrive');

insert into public.produits
  (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_porte', 'bou_informatique', 'Article de la porte', 9000,
        'sc_hightech_accessoires', 100, true)
on conflict (id) do update set prix = 9000, stock = 100, disponible = true;

select essai.verifie(exists (
  select 1 from public.reglages where id = 1),
  'la règle existe, en une seule ligne');
select essai.egal((select count(*)::int from public.reglages), 1,
  'et il n''y en a qu''une');
select essai.egal(public.compte_exige(), false,
  'elle arrive ÉTEINTE : poser le fichier ne ferme rien');

-- ---------------------------------------------------------
select essai.titre('Éteint : on commande comme avant');
-- ---------------------------------------------------------
select essai.personne();
set role anon;

select essai.egal(public.compte_exige(), false,
  'un visiteur peut lire la règle');

select public.creer_commande('{"nom":"Passant","tel":"97444444"}'::jsonb,
  '[{"produit_id":"prod_porte","quantite":1}]'::jsonb) ->> 'id' as sans_compte \gset
select essai.verifie(:'sans_compte' <> '',
  'un visiteur sans compte commande');
reset role;
select essai.egal((select client_id from public.commandes where id = :'sans_compte'),
  null::uuid, 'et sa commande n''appartient à personne');

select essai.devenir(:AWA::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Awa","tel":"97111111"}'::jsonb,
  '[{"produit_id":"prod_porte","quantite":1}]'::jsonb) ->> 'id' as awa_avant \gset
reset role;
select essai.personne();
select essai.egal((select client_id from public.commandes where id = :'awa_avant'),
  :AWA::uuid, 'une cliente connectée commande, et sa commande la porte');

-- ---------------------------------------------------------
select essai.titre('L''interrupteur n''est pas à tout le monde');
-- ---------------------------------------------------------
-- Un visiteur n'a aucun droit d'écriture sur la table : PostgreSQL
-- refuse avant même d'ouvrir la règle de sécurité.
select essai.personne();
set role anon;
select essai.refuse(
  $$update public.reglages set compte_obligatoire = true where id = 1$$,
  'un visiteur allume l''interrupteur');
reset role;

-- Une cliente, elle, a le droit d'écrire la colonne — c'est la règle
-- de sécurité qui lui retire la ligne. Zéro ligne touchée, sans erreur :
-- le refus est silencieux, et c'est bien ce qu'on veut vérifier ici.
select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.sans_effet(
  $$update public.reglages set compte_obligatoire = true where id = 1$$,
  'une cliente allume l''interrupteur');
select essai.refuse(
  $$delete from public.reglages where id = 1$$,
  'une cliente efface la règle');
select essai.refuse(
  $$insert into public.reglages (id, compte_obligatoire) values (2, true)$$,
  'une cliente pose une deuxième règle');
reset role;

-- Le chef d'une boutique administre SA boutique. Fermer la caisse de
-- toute l'enseigne n'est pas dans son périmètre.
select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.sans_effet(
  $$update public.reglages set compte_obligatoire = true where id = 1$$,
  'le chef d''une boutique allume l''interrupteur');
reset role;
select essai.personne();

select essai.egal(public.compte_exige(), false,
  'après tout cela, l''interrupteur n''a pas bougé');

-- Même l'enseigne ne peut pas faire disparaître la ligne : une table
-- vide répondrait « pas de règle », et rouvrirait la porte toute seule.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.refuse(
  $$delete from public.reglages where id = 1$$,
  'l''enseigne elle-même efface la règle');
reset role;
select essai.personne();

-- Et la ligne est unique par construction, même pour le propriétaire
-- de la base — celui qui exécute les fichiers dans l'éditeur SQL.
select essai.refuse(
  $$insert into public.reglages (id, compte_obligatoire) values (2, true)$$,
  'une deuxième règle, depuis l''éditeur SQL');

-- ---------------------------------------------------------
select essai.titre('L''enseigne allume, et la porte se ferme');
-- ---------------------------------------------------------
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
update public.reglages set compte_obligatoire = true, maj_le = now() where id = 1;
reset role;
select essai.personne();

select essai.egal(public.compte_exige(), true, 'l''interrupteur est allumé');

set role anon;
select essai.egal(public.compte_exige(), true,
  'et un visiteur le lit : l''application saura quoi dessiner');
select essai.refuse(
  $$select public.creer_commande('{"nom":"Passant","tel":"97444444"}'::jsonb,
      '[{"produit_id":"prod_porte","quantite":1}]'::jsonb)$$,
  'un visiteur sans compte commande');
reset role;

-- Le refus doit NOMMER le compte : c'est le seul indice que le client
-- aura sur ce qu'on attend de lui.
select essai.personne();
set role anon;
select essai.message_de(
  $$select public.creer_commande('{"nom":"Passant","tel":"97444444"}'::jsonb,
      '[{"produit_id":"prod_porte","quantite":1}]'::jsonb)$$) as refus_visiteur \gset
reset role;
select essai.verifie(:'refus_visiteur' like '%compte%',
  'le refus parle de compte');
select essai.verifie(:'refus_visiteur' not like '%équipe%',
  'et ne parle pas de l''équipe à un visiteur');

-- ---------------------------------------------------------
select essai.titre('Mais la cliente connectée, elle, passe');
-- ---------------------------------------------------------
select essai.devenir(:AWA::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Awa","tel":"97111111"}'::jsonb,
  '[{"produit_id":"prod_porte","quantite":1}]'::jsonb) ->> 'id' as awa_apres \gset
reset role;
select essai.personne();
select essai.verifie(:'awa_apres' <> '',
  'porte fermée, une cliente connectée commande toujours');
select essai.egal((select client_id from public.commandes where id = :'awa_apres'),
  :AWA::uuid, 'et sa commande la porte');

-- ---------------------------------------------------------
select essai.titre('Un compte de l''équipe n''est pas un compte client');
-- ---------------------------------------------------------
-- L'enseigne est connectée — mais avec un compte de l'équipe, qui
-- agirait sur sa propre commande avec les droits d'une boutique. La
-- base la ramène donc à « personne », et la porte se ferme aussi pour
-- elle. Lui répondre « connectez-vous » alors qu'elle EST connectée la
-- ferait chercher longtemps : le message doit être le sien.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.refuse(
  $$select public.creer_commande('{"nom":"Le chef","tel":"97555555"}'::jsonb,
      '[{"produit_id":"prod_porte","quantite":1}]'::jsonb)$$,
  'un compte de l''équipe commande pour lui-même');
select essai.message_de(
  $$select public.creer_commande('{"nom":"Le chef","tel":"97555555"}'::jsonb,
      '[{"produit_id":"prod_porte","quantite":1}]'::jsonb)$$) as refus_equipe \gset
reset role;
select essai.personne();

select essai.verifie(:'refus_equipe' like '%équipe%',
  'on lui dit que son compte est un compte de l''équipe');
select essai.verifie(:'refus_equipe' <> :'refus_visiteur',
  'et ce n''est pas le message du visiteur');

-- ---------------------------------------------------------
select essai.titre('On ferme la caisse, pas le magasin');
-- ---------------------------------------------------------
select essai.personne();
set role anon;
select essai.verifie((select count(*)::int from public.produits) > 0,
  'porte fermée, un visiteur voit toujours le catalogue');
select essai.verifie((select count(*)::int from public.categories) > 0,
  'et les rayons');
select essai.verifie((select count(*)::int from public.boutiques) > 0,
  'et les boutiques');
reset role;

-- ---------------------------------------------------------
select essai.titre('Si la règle disparaissait, la caisse se rouvre');
-- ---------------------------------------------------------
-- Personne ne peut effacer cette ligne — on vient de l'éprouver. Mais
-- une base se restaure, se migre, se répare à la main. Le jour où la
-- ligne manquerait, il vaut mieux vendre sans compte que ne plus
-- vendre du tout : la règle force une inscription, elle ne protège
-- rien. On force donc l'accident ici, depuis le propriétaire.
delete from public.reglages where id = 1;
select essai.egal((select count(*)::int from public.reglages), 0,
  'la ligne a disparu');
select essai.egal(public.compte_exige(), false,
  'sans règle, la réponse est « non » — la caisse rouvre');

set role anon;
select public.creer_commande('{"nom":"Passant","tel":"97444444"}'::jsonb,
  '[{"produit_id":"prod_porte","quantite":1}]'::jsonb) ->> 'id' as apres_accident \gset
reset role;
select essai.verifie(:'apres_accident' <> '',
  'et un visiteur commande de nouveau');

insert into public.reglages (id, compte_obligatoire) values (1, true);
select essai.egal(public.compte_exige(), true,
  'la ligne remise, la porte se referme');

-- ---------------------------------------------------------
select essai.titre('L''enseigne rouvre, et tout repart');
-- ---------------------------------------------------------
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
update public.reglages set compte_obligatoire = false, maj_le = now() where id = 1;
reset role;
select essai.personne();

select essai.egal(public.compte_exige(), false, 'l''interrupteur est éteint');

set role anon;
select public.creer_commande('{"nom":"Passant","tel":"97444444"}'::jsonb,
  '[{"produit_id":"prod_porte","quantite":1}]'::jsonb) ->> 'id' as rouverte \gset
reset role;
select essai.verifie(:'rouverte' <> '',
  'un visiteur commande de nouveau, sans compte');

-- ---------------------------------------------------------
select essai.titre('Ce que la règle ne touche pas');
-- ---------------------------------------------------------
-- Rien de ce qui précède ne doit avoir déplacé un prix, un stock ou
-- une commande déjà passée. Une porte qui s'ouvre et se ferme ne
-- change pas ce qu'il y a dans la boutique.
select essai.egal((select prix from public.produits where id = 'prod_porte')::int, 9000,
  'le prix de l''article n''a pas bougé');
select essai.verifie(exists (
  select 1 from public.commandes where id = :'sans_compte' and client_id is null),
  'la commande d''avant la règle est toujours là, et toujours orpheline');
select essai.verifie(exists (
  select 1 from public.commandes where id = :'awa_avant' and client_id = :AWA::uuid),
  'et celle d''Awa lui appartient toujours');

-- Le banc se quitte propre : l'interrupteur éteint, comme il arrive.
select essai.egal(public.compte_exige(), false,
  'le banc se termine l''interrupteur éteint');
