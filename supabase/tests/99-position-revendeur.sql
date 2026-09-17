-- =========================================================
-- Où se trouve le commerce d'un revendeur.
--
-- Valider une demande, c'est accorder une remise permanente sur
-- tout le catalogue. L'enseigne veut donc savoir à qui elle a
-- affaire, et où. La position est une DÉCLARATION du demandeur —
-- comme son message : c'est l'enseigne qui juge, et c'est bien
-- pour cela qu'elle la demande.
--
-- Quatre choses à prouver :
--
--   1. CE QUI N'EST PAS UNE POSITION N'EN DEVIENT PAS UNE. Hors
--      bornes, « NaN », une latitude sans longitude, ou « 0, 0 »
--      — le point au large du Ghana que rend un téléphone qui
--      n'a rien trouvé. Un point FAUX sur une carte est pire que
--      pas de point du tout : on se déplace pour rien ;
--   2. UNE VRAIE POSITION PASSE, elle, sans être retouchée. Une
--      règle qui écarte tout ne protège rien ;
--   3. ELLE SURVIT À LA DÉCISION. Valider ne doit pas effacer ce
--      sur quoi on vient de se décider ;
--   4. ELLE NE REGARDE QUE L'ENSEIGNE. L'adresse d'un commerce
--      est celle d'une personne : un autre client n'a rien à y
--      lire.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set AWA      '''44444444-4444-4444-4444-444444444444'''
\set KOFI     '''55555555-5555-5555-5555-555555555555'''

select essai.titre('Ce qui n''est pas une coordonnée');

-- La règle seule, d'abord : c'est une fonction pure.
select essai.egal(public.coord_valable(6.37, 90), 6.37::double precision,
  'Cotonou passe');
select essai.egal(public.coord_valable(2.42, 180), 2.42::double precision,
  'sa longitude aussi');
select essai.egal(public.coord_valable(91, 90), null::double precision,
  'une latitude de 91 n''existe pas');
select essai.egal(public.coord_valable(-91, 90), null::double precision,
  'ni de −91');
select essai.egal(public.coord_valable(181, 180), null::double precision,
  'ni une longitude de 181');
select essai.egal(public.coord_valable('NaN'::double precision, 90),
  null::double precision, '« NaN » non plus — et il ne s''égale pas lui-même');
select essai.egal(public.coord_valable(null, 90), null::double precision,
  'rien reste rien');
-- Les bornes elles-mêmes sont dedans : le pôle Sud et l'antiméridien
-- existent, même si aucune boutique béninoise ne s'y trouve.
select essai.egal(public.coord_valable(-90, 90), -90::double precision,
  'le pôle Sud est une latitude valable');
select essai.egal(public.coord_valable(180, 180), 180::double precision,
  'et 180 une longitude valable');

-- ---------------------------------------------------------
select essai.titre('Le décor : une demande avec sa position');
-- ---------------------------------------------------------
-- Awa est revendeuse validée depuis le banc de la marge. On la remet
-- cliente pour repartir d'une demande neuve, position comprise.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.egal(public.valider_revendeur(:AWA::uuid, false, 'On recommence'),
  'refusee', 'BIZZOO remet le compteur à zéro');
reset role;
select essai.personne();

select essai.devenir(:AWA::uuid);
set role authenticated;
update public.clients
   set type_compte         = 'client'
 where id = :AWA::uuid;
update public.clients
   set type_compte         = 'revendeur',
       revendeur_message   = 'Boutique Ayaba, marché Dantokpa',
       revendeur_adresse   = 'Dantokpa, allée des tissus, face à la mosquée',
       revendeur_latitude  = 6.3702,
       revendeur_longitude = 2.4289
 where id = :AWA::uuid;
reset role;
select essai.personne();

select essai.egal((select revendeur_etat from public.clients where id = :AWA::uuid),
  'en_attente', 'sa demande attend BIZZOO');
select essai.egal((select revendeur_latitude from public.clients where id = :AWA::uuid),
  6.3702::double precision, 'sa latitude est gardée telle quelle');
select essai.egal((select revendeur_longitude from public.clients where id = :AWA::uuid),
  2.4289::double precision, 'sa longitude aussi');
select essai.egal((select revendeur_adresse from public.clients where id = :AWA::uuid),
  'Dantokpa, allée des tissus, face à la mosquée',
  'et son adresse écrite, qui est ce qui permet de trouver');

-- ---------------------------------------------------------
select essai.titre('Une position aberrante est écartée, pas gardée');
-- ---------------------------------------------------------
select essai.devenir(:AWA::uuid);
set role authenticated;

update public.clients set revendeur_latitude = 999, revendeur_longitude = 2.42
 where id = :AWA::uuid;
reset role;
select essai.personne();
select essai.egal((select revendeur_latitude from public.clients where id = :AWA::uuid),
  null::double precision, 'une latitude de 999 est effacée');
select essai.egal((select revendeur_longitude from public.clients where id = :AWA::uuid),
  null::double precision, 'et la longitude qui restait seule avec elle');

-- Une latitude sans longitude ne désigne rien : les deux, ou aucune.
select essai.devenir(:AWA::uuid);
set role authenticated;
update public.clients set revendeur_latitude = 6.37, revendeur_longitude = null
 where id = :AWA::uuid;
reset role;
select essai.personne();
select essai.egal((select revendeur_latitude from public.clients where id = :AWA::uuid),
  null::double precision, 'une latitude seule ne vaut rien');

-- « 0, 0 » : le point au large du Ghana. C'est ce que rend un téléphone
-- qui n'a rien trouvé, jamais une boutique de Cotonou.
select essai.devenir(:AWA::uuid);
set role authenticated;
update public.clients set revendeur_latitude = 0, revendeur_longitude = 0
 where id = :AWA::uuid;
reset role;
select essai.personne();
select essai.egal((select revendeur_latitude from public.clients where id = :AWA::uuid),
  null::double precision, '« 0, 0 » est écarté : c''est une panne de GPS');

-- Et une vraie position repasse. Une règle qui écarterait tout ne
-- protégerait rien.
select essai.devenir(:AWA::uuid);
set role authenticated;
update public.clients
   set revendeur_latitude = 6.3702, revendeur_longitude = 2.4289
 where id = :AWA::uuid;
reset role;
select essai.personne();
select essai.egal((select revendeur_latitude from public.clients where id = :AWA::uuid),
  6.3702::double precision, 'une vraie position revient sans être retouchée');

-- L'adresse écrite est coupée, pas refusée : on ne perd pas une demande
-- parce que quelqu'un a collé trois paragraphes.
select essai.devenir(:AWA::uuid);
set role authenticated;
update public.clients set revendeur_adresse = repeat('x', 500) where id = :AWA::uuid;
reset role;
select essai.personne();
select essai.egal((select length(revendeur_adresse) from public.clients
                    where id = :AWA::uuid), 200,
  'une adresse trop longue est coupée à 200, non refusée');

-- On rend son adresse lisible pour la suite.
select essai.devenir(:AWA::uuid);
set role authenticated;
update public.clients
   set revendeur_adresse = 'Dantokpa, allée des tissus, face à la mosquée'
 where id = :AWA::uuid;
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('La position ne se déclare pas validée pour autant');
-- ---------------------------------------------------------
-- Donner sa position n'accorde rien : c'est toujours BIZZOO qui décide.
select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.refuse(
  $$update public.clients set revendeur_etat = 'validee'
     where id = '44444444-4444-4444-4444-444444444444'$$,
  'la demandeuse se valide en même temps que sa position');
reset role;
select essai.personne();
select essai.egal(public.est_revendeur(), false, 'et elle n''est pas revendeuse');

-- ---------------------------------------------------------
select essai.titre('BIZZOO voit où c''est, et décide');
-- ---------------------------------------------------------
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;

select essai.egal((select count(*)::int from public.revendeurs('en_attente')), 1,
  'la demande est dans sa liste');
select essai.verifie(
  (select adresse = 'Dantokpa, allée des tissus, face à la mosquée'
     from public.revendeurs('en_attente') limit 1),
  'avec l''adresse écrite');
select essai.verifie(
  (select latitude is not null and longitude is not null
     from public.revendeurs('en_attente') limit 1),
  'et les coordonnées, pour ouvrir l''itinéraire');

select essai.egal(public.valider_revendeur(:AWA::uuid, true, ''), 'validee',
  'il valide en connaissance de cause');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('La décision n''efface pas ce sur quoi elle porte');
-- ---------------------------------------------------------
select essai.egal((select revendeur_latitude from public.clients where id = :AWA::uuid),
  6.3702::double precision, 'la position survit à la validation');
select essai.egal((select revendeur_adresse from public.clients where id = :AWA::uuid),
  'Dantokpa, allée des tissus, face à la mosquée',
  'et l''adresse écrite aussi');

select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.verifie(
  (select latitude is not null from public.revendeurs('validee') limit 1),
  'la liste des validés la porte encore');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Un revendeur validé corrige son adresse sans rien perdre');
-- ---------------------------------------------------------
-- Une demande déposée sans position n'est pas perdue : on la complète
-- après coup. C'est ce qui rend la chose utilisable — on ne relève pas
-- toujours sa position au moment où on ouvre un compte.
--
-- ET CELA NE DOIT RIEN COÛTER À QUI EST DÉJÀ VALIDÉ. Refaire une
-- demande pour corriger une adresse ferait repasser le compte en
-- attente, et ses prix avec, le temps que BIZZOO la regarde. Écrire la
-- seule position ne touche pas « type_compte », et la décision tient.
select essai.devenir(:AWA::uuid);
set role authenticated;
update public.clients
   set revendeur_adresse   = 'Déménagé : Sainte-Rita, rue 12',
       revendeur_latitude  = 6.3610,
       revendeur_longitude = 2.3900
 where id = :AWA::uuid;
reset role;
select essai.personne();

select essai.egal((select revendeur_etat from public.clients where id = :AWA::uuid),
  'validee', 'elle est TOUJOURS validée');
select essai.egal((select revendeur_adresse from public.clients where id = :AWA::uuid),
  'Déménagé : Sainte-Rita, rue 12', 'et sa nouvelle adresse est prise');
select essai.egal((select revendeur_latitude from public.clients where id = :AWA::uuid),
  6.3610::double precision, 'avec sa nouvelle position');

select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.egal(public.est_revendeur(), true, 'elle achète toujours au prix revendeur');
reset role;
select essai.personne();

-- Une position peut aussi se RETIRER : une adresse fausse est pire
-- qu'une adresse absente, on se déplace pour rien.
select essai.devenir(:AWA::uuid);
set role authenticated;
update public.clients
   set revendeur_adresse = '', revendeur_latitude = null, revendeur_longitude = null
 where id = :AWA::uuid;
reset role;
select essai.personne();
select essai.egal((select revendeur_latitude from public.clients where id = :AWA::uuid),
  null::double precision, 'la position se retire');
select essai.egal((select revendeur_etat from public.clients where id = :AWA::uuid),
  'validee', 'et le statut tient encore');

-- On la remet pour la suite du banc.
select essai.devenir(:AWA::uuid);
set role authenticated;
update public.clients
   set revendeur_adresse   = 'Dantokpa, allée des tissus, face à la mosquée',
       revendeur_latitude  = 6.3702,
       revendeur_longitude = 2.4289
 where id = :AWA::uuid;
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('L''adresse d''un commerce ne regarde pas les autres');
-- ---------------------------------------------------------
-- C'est l'adresse d'une personne. Kofi est un client ordinaire : il ne
-- doit pas pouvoir lire où travaille Awa.
select essai.devenir(:KOFI::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.clients
                    where id = '44444444-4444-4444-4444-444444444444'), 0,
  'un autre client ne lit pas la fiche d''Awa');
-- La fonction est ouverte à tout compte connecté, mais elle filtre sur
-- « est_super() » : elle rend ZÉRO LIGNE, elle ne lève pas d'erreur.
-- C'est le bon refus, et il se constate autrement.
select essai.egal((select count(*)::int from public.revendeurs('')), 0,
  'ni la liste des demandes');
reset role;

-- Ni un visiteur, évidemment.
select essai.personne();
set role anon;
select essai.refuse($$select count(*) from public.revendeurs('')$$,
  'un visiteur lit la liste des revendeurs');
reset role;

-- ---------------------------------------------------------
select essai.titre('Le banc se quitte propre');
-- ---------------------------------------------------------
-- Awa repart validée et localisée : c'est l'état dans lequel les
-- fichiers précédents l'ont laissée, et rien ne doit dépendre de
-- l'ordre où on les lance.
select essai.egal((select revendeur_etat from public.clients where id = :AWA::uuid),
  'validee', 'Awa est validée');
select essai.egal(
  (select count(*)::int from public.clients
    where id = :AWA::uuid and revendeur_latitude is not null), 1,
  'et sa position est en place');
