-- =========================================================
-- BIZZOO Personnel : la gestion interne des employés
--
-- Ce qu'on prouve :
--   1. le premier CEO s'amorce une seule fois, par un superadministrateur ;
--   2. l'administration crée un employé, le CEO seul le valide ; les
--      droits (administration, décaissement, salaire en poste) sont au CEO ;
--   3. un employé ne touche qu'à ses coordonnées ;
--   4. un profil a un responsable qui en est membre ;
--   5. les messages : à tout le monde, à un profil (le sien ou un autre),
--      à une personne ; un message privé reste entre ses deux personnes ;
--   6. le circuit d'une mission : créée par l'administration, acceptée
--      et rapportée par le responsable, clôturée par l'administration ;
--   7. les rapports d'activité : publiés par le responsable, validés par
--      le CEO seul ;
--   8. les dépenses : demandées par le responsable, approuvées par le CEO,
--      décaissées par l'habilité seul ;
--   9. la paie : barèmes ignorés tant que le CEO ne les a pas validés,
--      calcul au franc près, avances étalées, prorata d'embauche, fiche
--      invisible à l'employé avant validation, figée après ;
--  10. la boîte mail chiffrée n'est lisible par aucun compte ;
--  11. un compte « personnel » ne devient pas un compte de boutique ;
--  12. les statistiques : chacun ne reçoit que ses sous-menus ;
--  13. le suivi des commandes ;
--  14. le menu Paramètres : les accès aux menus, que la base applique
--      elle-même, et l'en-tête de l'entreprise ;
--  15. bloquer, débloquer, supprimer : le CEO et le superadministrateur ;
--  16. les statistiques internes : salaires, dépenses, effectifs, revenus ;
--  17. photos, vidéos et audio dans les discussions ; tout s'efface à 7 jours ;
--  18. localiser un livreur : son téléphone envoie sa position pendant ses
--      courses, par un jeton qui ne sert qu'à cela ; Personnel la lit ;
--  19. la caisse : quatre compartiments, un gestionnaire, des mouvements
--      qu'on n'efface pas, un solde qui ne passe jamais sous zéro ;
--  20. la fiche complète : le superadministrateur la modifie comme le CEO,
--      l'employé complète ce qui le regarde, les données sensibles restent
--      au CEO ; on se connecte par son numéro ;
--  21. le solde de chaque employé : la paie validée s'y verse le 10, les
--      primes et retenues du CEO vont sur la prochaine paie, le prêt passe
--      par le CEO puis la caisse et revient sur la paie, un retrait ne
--      dépasse pas le solde et personne ne s'écrit « payé ».
--  22. l'accueil : les chiffres de la place de marché, montants et marge
--      seulement pour qui y a droit ;
--  23. un employé ne voit pas les informations des autres : seulement le
--      nom, le poste, le profil et le contact professionnel de chacun ;
--  24. un compte ouvert avec le mot de passe de départ ne vaut rien tant
--      que l'employé n'a pas choisi le sien ;
--  25. l'administration redonne un mot de passe provisoire, à changer
--      aussitôt de la même façon ;
--  26. le menu Livreurs : la liste et la fiche de chacun ; bloqué par
--      l'administration, un livreur ne reçoit plus aucune course.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ADMRH    '''a0a0a0a0-0001-4000-8000-000000000001'''
\set RESP     '''a0a0a0a0-0002-4000-8000-000000000002'''
\set MEMBRE   '''a0a0a0a0-0003-4000-8000-000000000003'''
\set AUTRE    '''a0a0a0a0-0004-4000-8000-000000000004'''
\set CAISSE   '''a0a0a0a0-0005-4000-8000-000000000005'''
\set NOUVEAU  '''a0a0a0a0-0006-4000-8000-000000000006'''

select essai.titre('Le décor : des comptes de connexion, personne encore employé');
insert into auth.users (id, email, raw_user_meta_data) values
  (:ADMRH::uuid,  'admin.rh@bizzoomarket.com',    '{"compte":"personnel"}'),
  (:RESP::uuid,   'resp.marketing@bizzoomarket.com', '{"compte":"personnel"}'),
  (:MEMBRE::uuid, 'membre.marketing@bizzoomarket.com', '{"compte":"personnel"}'),
  (:AUTRE::uuid,  'logisticien@bizzoomarket.com', '{"compte":"personnel"}'),
  (:CAISSE::uuid, 'caisse@bizzoomarket.com',      '{"compte":"personnel"}')
on conflict do nothing;

-- ---------------------------------------------------------
select essai.titre('11. Un compte « personnel » ne devient pas un compte de boutique');
select essai.verifie(not exists (select 1 from public.profils where id = :ADMRH::uuid),
  'aucune fiche d''équipe en attente pour un compte du personnel');
insert into auth.users (id, email) values (:NOUVEAU::uuid, 'quelquun@bizzoo.bj') on conflict do nothing;
select essai.verifie(exists (select 1 from public.profils where id = :NOUVEAU::uuid and not actif),
  'un compte ordinaire reçoit toujours sa fiche en attente');

-- ---------------------------------------------------------
select essai.titre('1 bis. Désigner le CEO sans l''être (essai annulé ensuite)');
begin;
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse($$select public.rh_designer_ceo('X', 'Y', 'M', 'admin.rh@bizzoomarket.com')$$,
  'un compte qui n''est pas superadministrateur ne désigne pas le CEO');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse($$select public.rh_designer_ceo('X', 'Y', 'M', 'personne@bizzoomarket.com')$$,
  'une adresse sans compte de connexion : refusée');
select essai.refuse($$select public.rh_designer_ceo('X', 'Y', 'M', 'enseigne@bizzoo.bj')$$,
  'sa propre adresse : refusée (il y a « Je suis le CEO » pour cela)');
select public.rh_designer_ceo('DIRECTEUR', 'Vrai', 'M', 'Resp.Marketing@bizzoomarket.com',
  'INSTALLATEUR', 'Technique', 'F');
select essai.egal((select count(*)::int from public.rh_employes
                    where ceo and compte_id = :RESP::uuid and etat = 'actif'), 1,
  'le CEO désigné est en poste, relié au compte de SON adresse');
select essai.egal((public.rh_tableau_de_bord() -> 'moi' ->> 'ceo')::boolean, false,
  'le superadministrateur n''est pas devenu CEO');
select essai.egal((public.rh_tableau_de_bord() -> 'moi' ->> 'administration')::boolean, true,
  'il est inscrit dans l''administration');
select essai.refuse($$select public.rh_designer_ceo('A', 'B', 'M', 'caisse@bizzoomarket.com')$$,
  'un second CEO : refusé');
select essai.refuse($$select public.rh_devenir_ceo('A', 'B', 'M')$$, 'ni par l''autre porte');
reset role; select essai.personne();
rollback;

-- ---------------------------------------------------------
select essai.titre('1. Le premier CEO');
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.egal((public.rh_tableau_de_bord() -> 'moi'), 'null'::jsonb,
  'un compte sans fiche employé n''est personne');
select essai.egal((public.rh_tableau_de_bord() ->> 'amorce_possible')::boolean, false,
  'il ne peut pas amorcer le CEO');
select essai.refuse($$select public.rh_devenir_ceo('Moi', 'Même', 'M')$$,
  'se déclarer CEO sans être superadministrateur : refusé');
select essai.egal((select count(*)::int from public.rh_annuaire()), 0,
  'l''annuaire est vide pour qui n''est pas employé');
reset role; select essai.personne();

set role anon;
select essai.refuse($$select * from public.rh_employes$$, 'un visiteur ne lit pas les employés');
select essai.refuse($$select public.rh_tableau_de_bord()$$, 'un visiteur n''appelle pas le tableau de bord');
reset role;

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal((public.rh_tableau_de_bord() ->> 'amorce_possible')::boolean, true,
  'le superadministrateur peut amorcer le CEO');
select public.rh_devenir_ceo('AKPLOGAN', 'Directeur', 'M') as ceo \gset
select essai.egal((public.rh_tableau_de_bord() -> 'moi' ->> 'ceo')::boolean, true,
  'il est désormais le CEO');
select essai.refuse($$select public.rh_devenir_ceo('Encore', 'Un', 'M')$$,
  'un second CEO : refusé');
reset role; select essai.personne();
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse($$select public.rh_devenir_ceo('Autre', 'Chef', 'M')$$,
  'même un autre compte : la porte est fermée');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('2. Créer et valider les employés');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
insert into public.rh_profils (nom) values ('Administration'), ('Marketing'), ('Logistique');
select id as p_admin from public.rh_profils where nom = 'Administration' \gset
select id as p_mkt from public.rh_profils where nom = 'Marketing' \gset
select id as p_log from public.rh_profils where nom = 'Logistique' \gset

insert into public.rh_employes (nom, prenoms, sexe, email_pro, date_embauche, statut,
                                salaire_base, profil_id, administration)
values ('HOUNKPE', 'Rita', 'F', 'admin.rh@bizzoomarket.com', '2025-03-01', 'employe',
        250000, :'p_admin', true)
returning id as e_admrh \gset
select essai.egal((select etat from public.rh_employes where id = :'e_admrh'), 'actif',
  'créé par le CEO : actif d''emblée');
select essai.egal((select administration from public.rh_employes where id = :'e_admrh'), true,
  'le CEO donne lui-même le droit d''administration');
select public.rh_rattacher_compte(:'e_admrh') \gset
reset role; select essai.personne();

select essai.devenir(:ADMRH::uuid); set role authenticated;
insert into public.rh_employes (nom, prenoms, sexe, email_pro, date_embauche, statut,
                                salaire_base, profil_id, administration, peut_decaisser, etat, ceo)
values ('DOSSOU', 'Koffi', 'M', 'resp.marketing@bizzoomarket.com', '2026-01-01', 'employe',
        200000, :'p_mkt', true, true, 'actif', false)
returning id as e_resp \gset
select essai.egal((select etat || '/' || administration || '/' || peut_decaisser
                     from public.rh_employes where id = :'e_resp'),
  'en_attente/false/false', 'créé par l''administration : en attente, sans droits proposés');
select essai.refuse(format($$select public.rh_decider_employe(%L, true)$$, :'e_resp'),
  'l''administration ne valide pas un employé');
select essai.refuse(format($$select public.rh_rattacher_compte(%L)$$, :'e_resp'),
  'pas d''accès avant la validation');
select essai.refuse(format($$update public.rh_employes set etat = 'actif' where id = %L$$, :'e_resp'),
  'ni en forçant l''état à la main');
select essai.refuse(format($$update public.rh_employes set nom = 'X' where id = %L$$, :'ceo'),
  'l''administration ne touche pas à la fiche du CEO');
insert into public.rh_employes (nom, prenoms, sexe, email_pro, date_embauche, statut, salaire_base, profil_id)
values ('ADJOVI', 'Inès', 'F', 'membre.marketing@bizzoomarket.com', '2026-09-16', 'stagiaire', 150000, :'p_mkt'),
       ('TOSSOU', 'Marc', 'M', 'logisticien@bizzoomarket.com', '2026-02-01', 'employe', 180000, :'p_log'),
       ('GBAGUIDI', 'Awa', 'F', 'caisse@bizzoomarket.com', '2026-02-01', 'employe', 170000, :'p_admin'),
       ('REFUSE', 'Test', 'M', null, '2026-02-01', 'employe', 1, :'p_log');
select id as e_membre from public.rh_employes where email_pro = 'membre.marketing@bizzoomarket.com' \gset
select id as e_autre  from public.rh_employes where email_pro = 'logisticien@bizzoomarket.com' \gset
select id as e_caisse from public.rh_employes where email_pro = 'caisse@bizzoomarket.com' \gset
select id as e_refuse from public.rh_employes where nom = 'REFUSE' \gset
select essai.egal((public.rh_tableau_de_bord() -> 'compteurs' ->> 'employes_a_valider')::int, 0,
  'les validations en attente ne s''affichent qu''au CEO');
reset role; select essai.personne();

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal((public.rh_tableau_de_bord() -> 'compteurs' ->> 'employes_a_valider')::int, 5,
  'le CEO voit les cinq employés à valider');
select essai.refuse(format($$select public.rh_decider_employe(%L, false, '')$$, :'e_refuse'),
  'un refus sans motif : refusé');
select public.rh_decider_employe(:'e_refuse', false, 'Dossier incomplet');
select public.rh_decider_employe(:'e_resp', true);
select public.rh_decider_employe(:'e_membre', true);
select public.rh_decider_employe(:'e_autre', true);
select public.rh_decider_employe(:'e_caisse', true);
update public.rh_employes set peut_decaisser = true where id = :'e_caisse';
-- La caisse : son gestionnaire, et de quoi décaisser.
select public.rh_designer_gestionnaire_caisse(:'e_caisse');
select public.rh_caisse_apport('especes', 2000000, 'ceo');
select public.rh_caisse_apport('mtn', 1000000, 'ceo');
select essai.egal((select count(*)::int from public.rh_employes where etat = 'actif'), 6,
  'cinq validés (le CEO compris, six en poste)');
reset role; select essai.personne();

select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_rattacher_compte(id) from public.rh_employes
 where id in (:'e_resp', :'e_membre', :'e_autre', :'e_caisse');
select essai.egal((select count(*)::int from public.rh_employes where compte_id is not null), 6,
  'chacun relié au compte de SA propre adresse');
update public.rh_employes set nom = 'REFUSE', poste = 'corrigé' where id = :'e_refuse';
select essai.egal((select etat from public.rh_employes where id = :'e_refuse'), 'en_attente',
  'une fiche refusée qu''on corrige repart chez le CEO');
select essai.refuse(format($$update public.rh_employes set salaire_base = 999999 where id = %L$$, :'e_resp'),
  'l''administration ne change pas le salaire d''un employé en poste');
select essai.refuse(format($$update public.rh_employes set peut_decaisser = true where id = %L$$, :'e_resp'),
  'ni ne donne le droit de décaisser');
select essai.refuse(format($$select public.rh_sortie_employe(%L, current_date)$$, :'e_autre'),
  'ni n''enregistre une sortie');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('3. Un employé ne touche qu''à ses coordonnées');
select essai.devenir(:MEMBRE::uuid); set role authenticated;
update public.rh_employes set adresse = 'Cadjèhoun' where compte_id = auth.uid();
select essai.egal((select adresse from public.rh_employes where compte_id = auth.uid()), 'Cadjèhoun',
  'il change son adresse');
select essai.refuse($$update public.rh_employes set telephone = '0197000001' where compte_id = auth.uid()$$,
  'pas son téléphone : c''est par lui qu''il se connecte');
select essai.refuse($$update public.rh_employes set salaire_base = 900000 where compte_id = auth.uid()$$,
  'pas son salaire');
select essai.refuse($$update public.rh_employes set administration = true where compte_id = auth.uid()$$,
  'pas ses droits');
select essai.egal((select count(*)::int from public.rh_employes), 1,
  'il ne lit que sa propre fiche');
select essai.verifie((select count(*) from public.rh_annuaire()) = 6,
  'l''annuaire lui montre ses six collègues en poste');
select essai.verifie(not (to_jsonb((select a from public.rh_annuaire() a limit 1)) ? 'salaire_base'),
  'l''annuaire ne dit pas les salaires');
select essai.refuse($$select public.rh_generer_paie('2026-09-01')$$, 'il ne prépare pas la paie');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('4. Le responsable d''un profil en est membre');
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.refuse(format($$update public.rh_profils set responsable_id = %L where id = %L$$,
  :'e_autre', :'p_mkt'), 'un logisticien ne dirige pas le Marketing');
update public.rh_profils set responsable_id = :'e_resp' where id = :'p_mkt';
reset role; select essai.personne();
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.sans_effet(format($$update public.rh_profils set responsable_id = %L where id = %L$$,
  :'e_membre', :'p_mkt'), 'un membre ne se nomme pas responsable');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('5. Les messages');
select essai.devenir(:MEMBRE::uuid); set role authenticated;
insert into public.rh_messages (profil_id, texte, auteur_id) values (:'p_mkt', 'Bonjour l''équipe', :'e_autre');
select essai.egal((select auteur_id from public.rh_messages order by id desc limit 1), :'e_membre'::uuid,
  'l''auteur est celui qui écrit, pas celui qu''il prétend être');
-- Trois façons d'écrire : à un profil (le sien ou un autre), à une
-- personne (n'importe quel employé), à tout le monde.
insert into public.rh_messages (profil_id, texte) values (:'p_log', 'Une question du Marketing à la Logistique');
select essai.egal((select count(*)::int from public.rh_messages where profil_id = :'p_log'), 1,
  'il écrit dans le fil d''un autre profil, et le lit ensuite pour en voir les réponses');
insert into public.rh_messages (destinataire_id, texte) values (:'e_autre', 'Un message privé au logisticien');
select essai.refuse(format($$insert into public.rh_messages (destinataire_id, texte) values (%L, 'moi')$$, :'e_membre'),
  'pas de message privé à soi-même');
insert into public.rh_messages (general, texte) values (true, 'Bonne semaine à tous');
select essai.refuse(format($$insert into public.rh_messages (general, profil_id, texte) values (true, %L, 'double')$$, :'p_mkt'),
  'un message n''a qu''une cible : tout le monde, un profil ou une personne');
select essai.refuse($$insert into public.rh_messages (texte) values ('nulle part')$$, 'ni aucune');
insert into public.rh_messages (destinataire_id, texte) values (:'e_resp', 'Chef, une question privée');
insert into public.rh_messages (destinataire_id, texte) values (:'e_admrh', 'Question à l''administration');
reset role; select essai.personne();

select essai.devenir(:AUTRE::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.rh_messages where profil_id = :'p_mkt'), 0,
  'la Logistique ne lit pas la discussion du Marketing');
select essai.egal((select count(*)::int from public.rh_messages where profil_id = :'p_log'), 1,
  'mais elle lit le message que le Marketing a posté dans son fil');
select essai.egal((select count(*)::int from public.rh_messages where general), 1, 'tout le monde lit le fil général');
select essai.egal((select count(*)::int from public.rh_messages where destinataire_id = :'e_autre'), 1,
  'et le logisticien reçoit le message privé');
select essai.egal((select non_lus from public.rh_conversations() where cle = 'g:tous'), 1,
  'le fil général est dans ses discussions, non lu');
select public.rh_marquer_lu('g:tous');
select essai.egal((select non_lus from public.rh_conversations() where cle = 'g:tous'), 0, 'lu, il ne compte plus');
reset role; select essai.personne();

select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.rh_messages where profil_id = :'p_mkt'), 1,
  'l''administration lit la discussion de chaque profil');
select essai.egal((select count(*)::int from public.rh_messages where destinataire_id = :'e_resp'), 0,
  'mais pas un message privé entre deux autres personnes');
insert into public.rh_messages (destinataire_id, texte) values (:'e_autre', 'L''administration écrit à tous');
reset role; select essai.personne();

select essai.devenir(:RESP::uuid); set role authenticated;
select essai.egal((select non_lus from public.rh_conversations() where cle = 'p:' || :'p_mkt'), 1,
  'le responsable a un message non lu dans son profil');
select public.rh_marquer_lu('p:' || :'p_mkt');
select essai.egal((select non_lus from public.rh_conversations() where cle = 'p:' || :'p_mkt'), 0,
  'lu, il ne compte plus');
select essai.egal((select non_lus from public.rh_conversations() where cle = 'd:' || :'e_membre'), 1,
  'le message privé du membre est là, non lu');
select essai.egal((select count(*)::int from public.rh_messages where profil_id = :'p_log'), 0,
  'un responsable ne lit pas le fil d''un autre profil où il n''a pas écrit');
select essai.verifie(exists (select 1 from public.rh_conversations() where cle = 'g:tous'), 'il a lui aussi le fil général');
reset role; select essai.personne();
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.verifie(exists (select 1 from public.rh_conversations() where cle = 'p:' || :'p_log'),
  'le profil où il a écrit apparaît dans ses discussions');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('6. Une mission, de bout en bout');
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.refuse(format($$insert into public.rh_missions (titre, profil_id, echeance) values ('X', %L, '2026-12-01')$$, :'p_mkt'),
  'un employé ne crée pas de mission');
reset role; select essai.personne();

select essai.devenir(:ADMRH::uuid); set role authenticated;
insert into public.rh_missions (titre, description, profil_id, date_debut, echeance, statut, rapport)
values ('Campagne de rentrée', 'Affiches et réseaux sociaux', :'p_mkt', '2026-09-01', '2026-09-30',
        'cloturee', 'faux rapport')
returning id as mission \gset
select essai.egal((select statut || '/' || rapport from public.rh_missions where id = :'mission'),
  'proposee/', 'une mission naît « proposée », sans rapport, quoi qu''on envoie');
select essai.refuse(format($$update public.rh_missions set statut = 'acceptee' where id = %L$$, :'mission'),
  'l''administration ne l''accepte pas à la place du responsable');
reset role; select essai.personne();

select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_repondre_mission(%L, true)$$, :'mission'),
  'un simple membre ne répond pas à la mission');
select essai.egal((select count(*)::int from public.rh_missions), 1, 'mais il la voit');
reset role; select essai.personne();
select essai.devenir(:AUTRE::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.rh_missions), 0, 'un autre profil ne la voit pas');
reset role; select essai.personne();

select essai.devenir(:RESP::uuid); set role authenticated;
select essai.egal((public.rh_tableau_de_bord() -> 'compteurs' ->> 'missions_a_repondre')::int, 1,
  'le responsable a une mission qui attend sa réponse');
select essai.refuse(format($$select public.rh_rendre_rapport_mission(%L, 'Rapport trop tôt pour être vrai')$$, :'mission'),
  'pas de rapport avant d''avoir accepté');
select public.rh_repondre_mission(:'mission', true);
select essai.refuse(format($$select public.rh_repondre_mission(%L, false, 'non')$$, :'mission'),
  'on ne répond pas deux fois');
select public.rh_rendre_rapport_mission(:'mission', 'Affiches posées dans 12 quartiers, 3 publications.');
reset role; select essai.personne();

select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_cloturer_mission(:'mission', false, 'Ajoutez les chiffres de vente');
reset role; select essai.personne();
select essai.devenir(:RESP::uuid); set role authenticated;
select public.rh_rendre_rapport_mission(:'mission', 'Affiches posées, 3 publications, ventes en hausse de 12 %.');
reset role; select essai.personne();
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_cloturer_mission(:'mission', true, 'Merci');
select essai.egal((select statut from public.rh_missions where id = :'mission'), 'cloturee',
  'à reprendre, puis rapportée de nouveau, puis clôturée');
select essai.refuse(format($$update public.rh_missions set titre = 'Autre' where id = %L$$, :'mission'),
  'une mission clôturée ne se modifie plus');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('7. Les rapports d''activité');
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.refuse(format($$insert into public.rh_rapports (profil_id, titre, periode_debut, periode_fin) values (%L, 'R', '2026-09-01', '2026-09-30')$$, :'p_mkt'),
  'un simple membre ne publie pas le rapport de son profil');
reset role; select essai.personne();

select essai.devenir(:RESP::uuid); set role authenticated;
insert into public.rh_rapports (profil_id, titre, periode_debut, periode_fin, contenu, statut)
values (:'p_mkt', 'Septembre 2026', '2026-09-01', '2026-09-30', 'Trois campagnes, deux partenariats.', 'valide')
returning id as rapport \gset
select essai.egal((select statut from public.rh_rapports where id = :'rapport'), 'brouillon',
  'un rapport naît brouillon');
reset role; select essai.personne();
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.rh_rapports), 0, 'un brouillon ne se lit que par son auteur');
reset role; select essai.personne();
select essai.devenir(:RESP::uuid); set role authenticated;
select public.rh_publier_rapport(:'rapport');
select essai.refuse(format($$update public.rh_rapports set contenu = 'réécrit' where id = %L$$, :'rapport'),
  'publié, il ne se modifie plus');
reset role; select essai.personne();
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_decider_rapport(%L, true)$$, :'rapport'),
  'l''administration ne valide pas un rapport d''activité');
reset role; select essai.personne();
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.rh_rapports), 0, 'les membres ne le lisent pas avant validation');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select public.rh_decider_rapport(:'rapport', true, 'Bon travail');
reset role; select essai.personne();
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.rh_rapports), 1, 'validé, les membres du profil le lisent');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('8. Les dépenses : l''employé demande, son responsable valide, le CEO approuve, l''habilité décaisse');
select essai.devenir(:MEMBRE::uuid); set role authenticated;
insert into public.rh_depenses (profil_id, objet, montant, statut)
values (:'p_log', 'Impression de 500 affiches', 50000, 'decaissee')
returning id as depense \gset
select essai.egal((select statut from public.rh_depenses where id = :'depense'), 'demandee',
  'tout employé demande ; sa demande attend d''abord son responsable, quoi que dise l''écran');
select essai.egal((select profil_id from public.rh_depenses where id = :'depense'), :'p_mkt'::uuid,
  'dans le profil du demandeur, pas celui que l''écran propose');
update public.rh_depenses set montant = 55000 where id = :'depense';
select essai.egal((select montant from public.rh_depenses where id = :'depense'), 55000::bigint,
  'il la corrige tant que personne ne l''a validée');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_decider_depense(%L, true)$$, :'depense'),
  'le CEO attend la validation du responsable');
reset role; select essai.personne();
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_valider_depense(%L, true)$$, :'depense'),
  'l''administration ne valide pas à la place du responsable');
reset role; select essai.personne();
select essai.devenir(:RESP::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_valider_depense(%L, false, '')$$, :'depense'),
  'un refus sans motif est refusé');
select public.rh_valider_depense(:'depense', true);
reset role; select essai.personne();
select essai.egal((select statut || '/' || (responsable_par = :'e_resp'::uuid) from public.rh_depenses where id = :'depense'),
  'validee_responsable/true', 'validée par le responsable, qui est noté ; elle part chez le CEO');
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.refuse(format($$update public.rh_depenses set montant = 90000 where id = %L$$, :'depense'),
  'validée, son montant ne change plus');
reset role; select essai.personne();
select essai.devenir(:CAISSE::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.rh_depenses), 0, 'l''habilité ne voit pas une demande non approuvée');
select essai.refuse(format($$select public.rh_decaisser_depense(%L, 'especes')$$, :'depense'),
  'ni ne la décaisse');
reset role; select essai.personne();
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_decider_depense(%L, true)$$, :'depense'),
  'l''administration n''approuve pas une dépense');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_decaisser_depense(%L, 'especes')$$, :'depense'),
  'le CEO lui-même ne décaisse pas sans habilitation');
select public.rh_decider_depense(:'depense', true);
reset role; select essai.personne();
select essai.devenir(:CAISSE::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_decaisser(%L, '{"especes": 20000, "mtn": 30000}', 'MM-123')$$, :'depense'),
  'une répartition qui ne tombe pas juste est refusée');
select public.rh_decaisser(:'depense', '{"especes": 20000, "mtn": 35000}', 'MM-123');
select essai.egal((select string_agg((x ->> 'compte') || ':' || (x ->> 'montant'), ',' order by x ->> 'compte')
                     from jsonb_array_elements(public.rh_caisse() -> 'mouvements') x
                    where x ->> 'depense_id' = :'depense'), 'especes:20000,mtn:35000',
  'décaissée en espèces + MTN : deux sorties de caisse');
select essai.egal((select statut || '/' || (decaisse_par = :'e_caisse'::uuid) from public.rh_depenses where id = :'depense'),
  'decaissee/true', 'approuvée par le CEO, décaissée par l''habilité, qui est noté');
select essai.refuse(format($$select public.rh_decaisser_depense(%L, 'especes')$$, :'depense'),
  'on ne décaisse pas deux fois');
insert into public.rh_depenses (objet, montant) values ('Carburant du groupe', 10000) returning id as depense_caisse \gset
reset role; select essai.personne();
select set_config('rh.decision', 'oui', false);
update public.rh_depenses set statut = 'approuvee' where id = :'depense_caisse';
select set_config('rh.decision', '', false);
select essai.devenir(:CAISSE::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_decaisser_depense(%L, 'especes')$$, :'depense_caisse'),
  'l''habilité ne décaisse jamais sa propre demande');
reset role; select essai.personne();

select essai.devenir(:RESP::uuid); set role authenticated;
insert into public.rh_depenses (objet, montant) values ('Stylos', 5000) returning id as depense_resp \gset
reset role; select essai.personne();
select essai.egal((select statut from public.rh_depenses where id = :'depense_resp'), 'validee_responsable',
  'le responsable qui demande va droit au CEO');
select essai.devenir(:MEMBRE::uuid); set role authenticated;
insert into public.rh_depenses (objet, montant) values ('Taxi', 3000) returning id as depense_taxi \gset
insert into public.rh_depenses (objet, montant) values ('Eau', 2000) returning id as depense_eau \gset
select public.rh_annuler_depense(:'depense_eau');
reset role; select essai.personne();
select essai.devenir(:RESP::uuid); set role authenticated;
select public.rh_valider_depense(:'depense_taxi', false, 'Pas prévu ce mois');
select essai.egal((public.rh_tableau_de_bord() #>> '{compteurs,depenses_a_valider}')::int, 0,
  'le tableau de bord du responsable ne compte plus rien à valider');
reset role; select essai.personne();
select essai.egal((select statut || '/' || motif_responsable from public.rh_depenses where id = :'depense_taxi'),
  'refusee/Pas prévu ce mois', 'le responsable refuse, avec son motif');
select essai.egal((select statut from public.rh_depenses where id = :'depense_eau'), 'annulee',
  'le demandeur annule tant que rien n''est tranché');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal((public.rh_tableau_de_bord() #>> '{compteurs,depenses_a_approuver}')::int, 1,
  'le CEO voit une demande à approuver : celle du responsable');
select public.rh_decider_depense(:'depense_resp', false, 'Budget fournitures épuisé');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('9. La paie');
select essai.devenir(:ADMRH::uuid); set role authenticated;
-- Des taux d'essai, pas ceux de la loi : l'application n'en fournit aucun.
insert into public.rh_cotisations (code, libelle, taux_salarie, taux_employeur, valide)
values ('CNSS_ESSAI', 'Cotisation d''essai', 3.6, 6.4, true)
returning id as cotisation \gset
select essai.egal((select valide from public.rh_cotisations where id = :'cotisation'), false,
  'une cotisation saisie attend le CEO, même envoyée « validée »');
insert into public.rh_tranches_impot (borne_inf, borne_sup, taux) values
  (0, 60000, 0), (60000, 150000, 10), (150000, null, 15);
insert into public.rh_elements_paie (employe_id, mois, nature, libelle, montant, imposable) values
  (:'e_resp', '2026-09-01', 'prime', 'Prime de rendement', 20000, true),
  (:'e_resp', '2026-09-01', 'indemnite', 'Transport', 10000, false),
  (:'e_resp', '2026-09-01', 'retenue', 'Retard', 5000, true);
insert into public.rh_avances (employe_id, date_avance, montant, mensualites, premier_mois)
values (:'e_resp', '2026-09-05', 30000, 3, '2026-09-01');
select essai.refuse($$select public.rh_generer_paie((now() + interval '2 months')::date)$$,
  'pas de paie pour un mois à venir');
select essai.verifie(public.rh_generer_paie('2026-09-01') >= 5, 'la paie de septembre est calculée');
select essai.egal((select cotisations_salariales + impot from public.rh_fiches_paie
                    where employe_id = :'e_resp' and mois = '2026-09-01'), 0::bigint,
  'barèmes pas encore validés par le CEO : ni cotisation ni impôt');
select essai.egal((select net from public.rh_fiches_paie where employe_id = :'e_resp' and mois = '2026-09-01'),
  215000::bigint, '230 000 de brut − 5 000 de retenue − 10 000 d''avance');
reset role; select essai.personne();

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal((public.rh_tableau_de_bord() -> 'compteurs' ->> 'baremes_a_valider')::int, 2,
  'le CEO a la cotisation et le barème d''impôt à valider');
select public.rh_valider_cotisation(:'cotisation');
select public.rh_valider_bareme_impot();
select public.rh_generer_paie('2026-09-01');
reset role; select essai.personne();

select essai.egal((select brut || '/' || brut_imposable || '/' || cotisations_salariales || '/' ||
                          impot || '/' || avances || '/' || retenues || '/' || net || '/' || charges_patronales
                     from public.rh_fiches_paie where employe_id = :'e_resp' and mois = '2026-09-01'),
  '230000/220000/7920/19500/10000/5000/187580/14080',
  'brut, imposable, CNSS 3,6 %, impôt par tranches, avance, retenue, net et part patronale au franc près');
select essai.egal((select salaire_du || '/' || jours_payes || '/' || cotisations_salariales || '/' || impot || '/' || net
                     from public.rh_fiches_paie where employe_id = :'e_membre' and mois = '2026-09-01'),
  '75000/15/0/0/75000', 'stagiaire embauchée le 16 : 15 jours sur 30, ni cotisation ni impôt');

select essai.devenir(:RESP::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.rh_fiches_paie), 0,
  'l''employé ne voit pas une fiche encore calculée');
reset role; select essai.personne();

select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.refuse($$select public.rh_valider_paie('2026-09-01')$$, 'l''administration ne valide pas la paie');
reset role; select essai.personne();
select essai.devenir(:CAISSE::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.rh_fiches_paie), 0,
  'l''habilité ne voit pas les fiches des autres');
reset role; select essai.personne();

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.verifie(public.rh_valider_paie('2026-09-01') >= 5, 'le CEO valide la paie de septembre');
reset role; select essai.personne();

select essai.devenir(:RESP::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.rh_fiches_paie), 1, 'validée, l''employé voit SA fiche, et elle seule');
reset role; select essai.personne();
select essai.devenir(:CAISSE::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.rh_fiches_paie where employe_id <> :'e_caisse'), 0,
  'validées, le gestionnaire de la caisse ne lit pas pour autant les fiches des autres');
reset role; select essai.personne();

select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.refuse(format($$insert into public.rh_elements_paie (employe_id, mois, nature, libelle, montant) values (%L, '2026-09-01', 'prime', 'Après coup', 1000)$$, :'e_resp'),
  'une prime sur un mois validé : refusée');
select essai.refuse(format($$update public.rh_avances set montant = 1 where employe_id = %L$$, :'e_resp'),
  'une avance déjà retenue sur une paie validée ne se modifie plus');
select public.rh_generer_paie('2026-10-01');
select essai.egal((select avances from public.rh_fiches_paie where employe_id = :'e_resp' and mois = '2026-10-01'),
  10000::bigint, 'octobre retient la deuxième mensualité de l''avance');
select essai.egal((select net from public.rh_fiches_paie where employe_id = :'e_resp' and mois = '2026-09-01'),
  187580::bigint, 'septembre, validé, n''a pas bougé');
reset role; select essai.personne();

select (select id from public.rh_fiches_paie where employe_id = :'e_resp' and mois = '2026-09-01') as fiche_sept \gset
select (select id from public.rh_fiches_paie where employe_id = :'e_resp' and mois = '2026-10-01') as fiche_oct \gset
-- Septembre se versait le 10 octobre : validée après, la fiche est
-- versée aussitôt sur le solde de l'employé.
select essai.egal((select statut || '/' || mode_paiement from public.rh_fiches_paie where id = :'fiche_sept'),
  'payee/solde', 'validée après son 10, la fiche est versée aussitôt sur le solde');
select essai.egal(public.rh_solde_de(:'e_resp'), 187580::bigint, 'le net de septembre est sur le solde de l''employé');
select essai.egal((select count(*)::int from public.rh_caisse_mouvements where fiche_id = :'fiche_sept'), 0,
  'versée sur le solde, elle ne sort pas encore de la caisse');
select essai.devenir(:CAISSE::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_payer_fiche(%L, 'mtn', 'MTN-09')$$, :'fiche_sept'),
  'un salaire ne se paie plus de la main à la main');
select essai.refuse(format($$select public.rh_payer(%L, '{"mtn": 187580}', 'MTN-09')$$, :'fiche_oct'),
  'ni réparti entre les compartiments');
reset role; select essai.personne();
-- L'employé retire son salaire à la caisse ; le gestionnaire le sert sur MTN.
select essai.devenir(:RESP::uuid); set role authenticated;
select public.rh_demander_retrait(187580, 'caisse') as retrait_sept \gset
reset role; select essai.personne();
select essai.devenir(:CAISSE::uuid); set role authenticated;
select public.rh_servir_retrait(:'retrait_sept', '{"mtn": 187580}', 'MTN-09');
select essai.egal((select (x ->> 'montant')::bigint from jsonb_array_elements(public.rh_caisse() -> 'mouvements') x
                    where x ->> 'nature' = 'salaire' and x ->> 'compte' = 'mtn' limit 1),
  187580::bigint, 'le retrait sort du compartiment MTN');
reset role; select essai.personne();
select essai.egal(public.rh_solde_de(:'e_resp'), 0::bigint, 'retiré, le solde est vide');
select (select 'Retrait de salaire R-' || lpad(numero::text, 4, '0') from public.rh_retraits
         where id = :'retrait_sept') as libelle_sept \gset
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_rouvrir_fiche(%L)$$, :'fiche_sept'),
  'une fiche payée ne se rouvre pas');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('10. La boîte mail chiffrée');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse($$select * from public.rh_boites_mail$$, 'même le CEO ne lit pas les mots de passe des boîtes');
select essai.egal((public.rh_ma_messagerie() ->> 'configuree')::boolean, false,
  'il sait seulement si SA boîte est configurée');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('12. Les statistiques : qui voit quoi, et des chiffres justes');
\set ACHETEUSE_RH '''a0a0a0a0-0008-4000-8000-000000000008'''
insert into auth.users (id, email) values (:ACHETEUSE_RH::uuid, 'acheteuse.rh@essai.bj') on conflict do nothing;
insert into public.clients (id, nom, tel) values (:ACHETEUSE_RH::uuid, 'Sika', '97666088') on conflict (id) do nothing;
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_rh_stats', 'bou_informatique', 'Écran', 50000, 'sc_hightech_accessoires', 100, true)
on conflict (id) do update set stock = 100, disponible = true;
insert into public.produits_prive (produit_id, prix_grossiste) values ('prod_rh_stats', 40000)
on conflict (produit_id) do update set prix_grossiste = 40000;

select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.refuse($$select public.rh_statistiques()$$, 'un simple employé ne voit aucune statistique');
reset role; select essai.personne();
select essai.devenir(:RESP::uuid); set role authenticated;
select essai.refuse($$select public.rh_statistiques()$$,
  'un responsable dont le profil n''a aucune rubrique ouverte : rien');
select essai.refuse(format($$select public.rh_regler_acces(%L, '{"stats_livraisons":"responsable"}')$$, :'p_mkt'),
  'il ne s''ouvre pas les statistiques lui-même');
reset role; select essai.personne();

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select public.rh_statistiques(current_date - 1, current_date + 1) as avant \gset
reset role; select essai.personne();

select essai.devenir(:ACHETEUSE_RH::uuid); set role authenticated;
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_rh_stats","quantite":2}]'::jsonb) ->> 'id' as cmd_rh \gset
reset role; select essai.personne();
select public.marquer_payee(:'cmd_rh', 'TRX-RH-STATS',
  (select coalesce(acompte, total) from public.commandes where id = :'cmd_rh'), 'feexpay') as p \gset
select (select total from public.commandes where id = :'cmd_rh') as total_rh \gset
select (select sum(greatest(0, prix - prix_bizzoo) * quantite) from public.commande_lignes
         where commande_id = :'cmd_rh') as benef_rh \gset
select essai.verifie(:'benef_rh'::bigint > 0, 'la commande d''essai rapporte une marge (' || :'benef_rh' || ')');

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select public.rh_statistiques(current_date - 1, current_date + 1) as apres \gset
reset role; select essai.personne();
select essai.egal((:'apres'::jsonb #>> '{commandes,payees}')::bigint - (:'avant'::jsonb #>> '{commandes,payees}')::bigint,
  1::bigint, 'une commande payée de plus');
select essai.egal((:'apres'::jsonb #>> '{commandes,articles}')::bigint - (:'avant'::jsonb #>> '{commandes,articles}')::bigint,
  2::bigint, 'deux articles de plus');
select essai.egal((:'apres'::jsonb #>> '{commandes,montant}')::bigint - (:'avant'::jsonb #>> '{commandes,montant}')::bigint,
  :'total_rh'::bigint, 'le montant monte exactement du total de la commande');
select essai.egal((:'apres'::jsonb #>> '{commandes,benefice}')::bigint - (:'avant'::jsonb #>> '{commandes,benefice}')::bigint,
  :'benef_rh'::bigint, 'le bénéfice monte exactement de la marge de ses lignes');
select essai.egal((:'apres'::jsonb #>> '{livraisons,en_cours}')::bigint - (:'avant'::jsonb #>> '{livraisons,en_cours}')::bigint,
  1::bigint, 'sa ligne est à livrer');

select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_statistiques(current_date - 1, current_date + 1) as admin_stats \gset
reset role; select essai.personne();
select essai.verifie((:'admin_stats'::jsonb #>> '{commandes,montant}') is not null,
  'l''administration voit les montants');
select essai.verifie((:'admin_stats'::jsonb #>> '{commandes,benefice}') is null
  and (:'admin_stats'::jsonb #>> '{commandes,reverse_boutiques}') is null
  and not (:'admin_stats'::jsonb::text ~ '"benefice": [0-9]'),
  'mais pas la marge de BIZZOO, nulle part');

select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_regler_acces(:'p_mkt', '{"stats_livraisons":"responsable","stats_livreurs":"responsable"}');
select essai.refuse(format($$select public.rh_regler_acces(%L, '{"marge":"responsable"}')$$, :'p_mkt'),
  'un menu inconnu est refusé');
reset role; select essai.personne();
select essai.devenir(:RESP::uuid); set role authenticated;
select public.rh_statistiques(current_date - 1, current_date + 1) as resp_stats \gset
reset role; select essai.personne();
select essai.verifie(:'resp_stats'::jsonb -> 'livraisons' <> 'null'::jsonb, 'le responsable du Marketing voit les livraisons');
select essai.verifie(:'resp_stats'::jsonb -> 'commandes' = 'null'::jsonb and :'resp_stats'::jsonb -> 'sav' = 'null'::jsonb,
  'et seulement elles');
select essai.verifie(not (:'resp_stats'::jsonb::text ~ '"(gains|montant|ventes|benefice)": [0-9]'),
  'sans aucun montant');
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.refuse($$select public.rh_statistiques()$$, 'les membres du profil, eux, ne voient toujours rien');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse($$select public.rh_statistiques(current_date, current_date - 3)$$, 'une période à l''envers est refusée');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('13. Le suivi des commandes');
select essai.egal(public.rh_cle('Fidjrossè, von-Morija'), 'fidjrosse von morija', 'une adresse se lit sans accents ni ponctuation');
select essai.egal(public.rh_zone_de('Fidjrosse von morija, Cotonou'), 'Fidjrossè (Cotonou)',
  'le quartier est reconnu dans l''adresse libre, avant la commune');

select essai.devenir(:ACHETEUSE_RH::uuid); set role authenticated;
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Fidjrosse von morija"}'::jsonb,
  '[{"produit_id":"prod_rh_stats","quantite":1}]'::jsonb) ->> 'id' as cmd_suivi \gset
reset role; select essai.personne();
select public.marquer_payee(:'cmd_suivi', 'TRX-RH-SUIVI',
  (select coalesce(acompte, total) from public.commandes where id = :'cmd_suivi'), 'feexpay') as p \gset
select (select id from public.commande_lignes where commande_id = :'cmd_suivi' limit 1) as ligne_suivi \gset

select essai.verifie(exists (select 1 from public.rh_journal_lignes
                              where ligne_id = :'ligne_suivi' and quoi = 'etat' and valeur = 'nouvelle' and not reconstitue),
  'le journal note la naissance de l''article');
select essai.verifie(exists (select 1 from public.rh_journal_lignes
                              where commande_id = :'cmd_suivi' and quoi = 'commande' and valeur = 'payee'),
  'et le paiement de la commande');

select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.refuse($$select public.rh_suivi()$$, 'un simple employé ne voit pas le suivi');
reset role; select essai.personne();

-- Le paiement recule de 5 heures : la boutique n'a toujours rien vu.
do $$ begin
  perform set_config('bizzoo.paiement', 'oui', true);
  update public.commandes set paye_le = now() - interval '5 hours'
   where id = (select id from public.commandes where transaction_id = 'TRX-RH-SUIVI' limit 1);
end $$;

select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_suivi_regler(1, 1, 3, 1);
select x as ligne_cmd from jsonb_array_elements(public.rh_suivi(current_date - 1, current_date + 1) -> 'commandes') x
 where x ->> 'id' = :'cmd_suivi' \gset
reset role; select essai.personne();
select essai.egal(:'ligne_cmd'::jsonb ->> 'statut', 'Nouvelle commande', 'payée, pas encore vue : « Nouvelle commande »');
select essai.egal(:'ligne_cmd'::jsonb #>> '{client,zone}', 'Fidjrossè (Cotonou)', 'sa zone est lue dans l''adresse');
select essai.verifie((:'ligne_cmd'::jsonb -> 'alertes') ? 'non_vue', 'alerte : la boutique ne l''a pas vue');
select essai.verifie((:'ligne_cmd'::jsonb -> 'alertes') ? 'retard_livraison', 'alerte : en retard de livraison');
select essai.verifie((:'ligne_cmd'::jsonb ->> 'total') is not null, 'l''administration voit les montants');
select essai.egal(:'ligne_cmd'::jsonb ->> 'confirmation', 'Non', 'le client n''a rien confirmé');

-- La boutique qui prépare : son administrateur, en poste (le fichier se suffit).
insert into public.profils (id, email, role, boutique_id, actif)
values (:CHEF::uuid, 'chef-boutique@bizzoo.bj', 'administrateur', 'bou_informatique', true)
on conflict (id) do update set role = 'administrateur', boutique_id = 'bou_informatique', actif = true;
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'preparee' where commande_id = :'cmd_suivi';
reset role; select essai.personne();
select essai.verifie(exists (select 1 from public.rh_journal_lignes
                              where ligne_id = :'ligne_suivi' and quoi = 'etat' and valeur = 'preparee'),
  'le journal date le passage à « préparée »');

select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_regler_acces(:'p_mkt', '{"suivi":"responsable"}');
select public.rh_incident_ouvrir(:'cmd_suivi', 'client_absent', 'Client injoignable à 14 h') as incident \gset
select essai.refuse(format($$select public.rh_suivi_cloturer(%L)$$, :'cmd_suivi'),
  'un incident ouvert empêche la clôture');
select essai.refuse(format($$select public.rh_suivi_terrain(%L, 'echouee', '')$$, :'ligne_suivi'),
  'un échec de livraison sans motif est refusé');
select public.rh_suivi_terrain(:'ligne_suivi', 'echouee', 'Client absent deux fois');
select public.rh_incident_resoudre(:'incident', 'Nouveau rendez-vous fixé');
select public.rh_suivi_noter(:'cmd_suivi', 'Akpakpa (Cotonou)', 'Rappeler le client avant 10 h');
select (public.rh_suivi_commande(:'cmd_suivi')) as fiche \gset
reset role; select essai.personne();
select essai.egal(:'fiche'::jsonb ->> 'statut', 'Livraison échouée', 'l''échec noté par l''administration devient le statut');
select essai.egal(:'fiche'::jsonb #>> '{client,zone}', 'Akpakpa (Cotonou)', 'la zone corrigée remplace la zone devinée');
select essai.verifie(jsonb_array_length(:'fiche'::jsonb -> 'journal') >= 3, 'la fiche porte sa chronologie');

select essai.devenir(:RESP::uuid); set role authenticated;
select x as vue_resp from jsonb_array_elements(public.rh_suivi(current_date - 1, current_date + 1) -> 'commandes') x
 where x ->> 'id' = :'cmd_suivi' \gset
select essai.refuse($$select public.rh_suivi_regler(5, 5, 5, 5)$$, 'ni ne règle les délais');
select public.rh_suivi_bilan(current_date - 1, current_date + 1) as bilan_resp \gset
reset role; select essai.personne();
select essai.verifie(:'vue_resp'::jsonb is not null, 'le responsable d''un profil coché « suivi » voit les commandes');
select essai.verifie(not (:'vue_resp'::jsonb ? 'total') and not (:'vue_resp'::jsonb ? 'reste')
  and not (:'vue_resp'::jsonb::text ~ '"prix"'), 'mais aucun montant');
select essai.verifie((:'bilan_resp'::jsonb #>> '{total,reste}') is null, 'ni dans le bilan');

select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_suivi_cloturer(:'cmd_suivi');
select essai.egal(public.rh_suivi_commande(:'cmd_suivi') ->> 'statut', 'Clôturée', 'incident résolu, parcours fini : clôturée');
select essai.refuse(format($$select public.rh_suivi_terrain(%L, 'retournee')$$, :'ligne_suivi'),
  'une commande clôturée ne se retouche plus');
select public.rh_suivi_bilan(current_date - 1, current_date + 1, 'jour') as bilan_admin \gset
reset role; select essai.personne();
select essai.verifie((:'bilan_admin'::jsonb #>> '{total,recues}')::int >= 2, 'le bilan compte les commandes reçues');
select essai.verifie((:'bilan_admin'::jsonb #>> '{total,reste}') is not null, 'l''administration y voit le reste à encaisser');
select essai.verifie(jsonb_array_length(:'bilan_admin'::jsonb -> 'par_zone') >= 1, 'et les commandes par zone');

select essai.devenir(:RESP::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_suivi_rouvrir(%L)$$, :'cmd_suivi'), 'le responsable ne rouvre pas une commande clôturée');
reset role; select essai.personne();
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_suivi_rouvrir(:'cmd_suivi');
reset role; select essai.personne();
select essai.verifie((select cloturee_le from public.rh_suivi_commandes where commande_id = :'cmd_suivi') is null,
  'l''administration la rouvre');

set role anon;
select essai.refuse($$select * from public.rh_journal_lignes$$, 'un visiteur ne lit pas le journal');
reset role;

-- ---------------------------------------------------------
select essai.titre('14. Les paramètres : les accès aux menus, profil par profil');
select essai.egal((select string_agg(menu || '=' || qui, ',' order by menu) from public.rh_acces_menus
                    where profil_id = :'p_log'),
  'depenses=membres,discussions=membres,mails=membres,missions=membres,rapports=membres',
  'un profil reçoit à sa naissance les accès d''avant');
select (select count(*) from public.rh_missions where profil_id = :'p_mkt') as nb_missions_mkt \gset
select essai.verifie(:'nb_missions_mkt'::int > 0, 'le Marketing a des missions');

select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.egal(public.rh_mes_menus(), array['mails', 'discussions', 'missions', 'rapports', 'depenses'],
  'un membre : mails, discussions, missions, rapports, dépenses');
select essai.egal(public.rh_suivi_acces(), null::text, 'le suivi, ouvert au seul responsable, lui reste fermé');
select essai.refuse(format($$select public.rh_regler_acces(%L, '{"suivi":"membres"}')$$, :'p_mkt'),
  'un membre ne s''ouvre pas un menu');
select essai.refuse(format($$insert into public.rh_acces_menus (profil_id, menu, qui) values (%L, 'suivi', 'membres')$$, :'p_mkt'),
  'ni en écrivant la table');
select essai.egal((select count(*)::int from public.rh_missions where profil_id = :'p_mkt'), :'nb_missions_mkt'::int,
  'il voit les missions de son profil');
reset role; select essai.personne();

select essai.devenir(:RESP::uuid); set role authenticated;
select essai.egal(public.rh_mes_menus(),
  array['mails', 'discussions', 'missions', 'rapports', 'depenses', 'suivi', 'stats_livraisons', 'stats_livreurs'],
  'son responsable a en plus les dépenses, le suivi et deux sous-menus de statistiques');
reset role; select essai.personne();

select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_regler_acces(:'p_mkt',
  '{"missions":"responsable","discussions":"ferme","stats_livraisons":"ferme","employes":"membres"}');
select essai.refuse(format($$select public.rh_regler_acces(%L, '{"paie":"membres"}')$$, :'p_mkt'),
  'la paie ne s''ouvre à aucun profil');
select essai.refuse(format($$select public.rh_regler_acces(%L, '{"mails":"tous"}')$$, :'p_mkt'),
  'un réglage inconnu est refusé');
select essai.egal((select modifie_par from public.rh_acces_menus where profil_id = :'p_mkt' and menu = 'missions'),
  :'e_admrh'::uuid, 'qui a réglé l''accès reste noté');
select essai.verifie((select count(*) from public.rh_messages where profil_id = :'p_mkt') > 0,
  'l''administration lit toujours la discussion du profil');
reset role; select essai.personne();

select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.egal(public.rh_mes_menus(), array['mails', 'rapports', 'depenses', 'employes'],
  'le membre n''a plus que mails, rapports, dépenses et l''annuaire');
select essai.egal((select count(*)::int from public.rh_missions where profil_id = :'p_mkt'), 0,
  'missions fermées aux membres : il ne les voit plus');
select essai.egal((select count(*)::int from public.rh_messages where profil_id = :'p_mkt'), 0,
  'discussions fermées : il ne lit plus celle du profil');
select essai.refuse(format($$insert into public.rh_messages (profil_id, texte) values (%L, 'encore là ?')$$, :'p_mkt'),
  'ni n''y écrit');
select essai.refuse(format($$insert into public.rh_messages (destinataire_id, texte) values (%L, 'en privé')$$, :'e_resp'),
  'ni n''envoie de message direct');
select essai.egal((select count(*)::int from public.rh_conversations()), 0, 'sa liste de discussions est vide');
select essai.verifie((select count(*) from public.rh_annuaire()) > 0, 'l''annuaire, lui, s''ouvre');
reset role; select essai.personne();

select essai.devenir(:RESP::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.rh_missions where profil_id = :'p_mkt'), :'nb_missions_mkt'::int,
  'le responsable voit toujours les missions');
select essai.egal((select count(*)::int from public.rh_messages where profil_id = :'p_mkt'), 0,
  'mais plus la discussion, fermée à tout le profil');
select public.rh_statistiques(current_date - 1, current_date + 1) as st14 \gset
select essai.egal((select array_agg(k order by k) from jsonb_object_keys(:'st14'::jsonb -> 'livraisons') k),
  array['livreurs'], 'Livraisons fermée, Livreurs ouverte : il ne reçoit que le classement des livreurs');
select essai.egal(:'st14'::jsonb #> '{droits,rubriques}', '["livreurs"]'::jsonb, 'et la base le lui dit');
reset role; select essai.personne();

select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_regler_acces(:'p_mkt', '{"missions":"membres","discussions":"membres","employes":"ferme"}');
reset role; select essai.personne();
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.rh_messages where profil_id = :'p_mkt') > 0, true,
  'rouverte, la discussion revient avec ses messages');
reset role; select essai.personne();

select essai.titre('14 bis. L''en-tête de l''entreprise');
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.egal((select raison_sociale from public.rh_entreprise), 'BIZZOO', 'tout employé lit l''en-tête');
select essai.sans_effet($$update public.rh_entreprise set ifu = '0000000000000'$$, 'un employé ne le change pas');
reset role; select essai.personne();
select essai.devenir(:ADMRH::uuid); set role authenticated;
update public.rh_entreprise set adresse = 'Cotonou';
select essai.refuse($$update public.rh_entreprise set modifie_par = null$$, 'la trace de la modification ne s''écrit pas à la main');
reset role; select essai.personne();
select essai.egal((select adresse || '/' || modifie_par from public.rh_entreprise), 'Cotonou/' || :'e_admrh',
  'l''administration le change, et la base note qui');
select essai.verifie(not exists (select 1 from information_schema.role_table_grants
                                  where table_name in ('rh_acces_menus', 'rh_entreprise') and grantee = 'anon'),
  'rien pour un visiteur');

-- ---------------------------------------------------------
select essai.titre('15. Bloquer, débloquer, supprimer un employé');
\set SUPER2 '''a0a0a0a0-0009-4000-8000-000000000009'''
insert into auth.users (id, email) values (:SUPER2::uuid, 'second.super@essai.bj') on conflict do nothing;
update public.profils set role = 'superadministrateur', actif = true where id = :SUPER2::uuid;

select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_bloquer_employe(%L, true, 'Retards')$$, :'e_membre'),
  'l''administration ne bloque pas');
select essai.refuse(format($$select public.rh_supprimer_employe(%L, 'Doublon')$$, :'e_refuse'),
  'ni ne supprime');
reset role; select essai.personne();

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_bloquer_employe(%L, true, '')$$, :'e_membre'), 'un blocage sans motif est refusé');
select essai.refuse(format($$select public.rh_bloquer_employe(%L, true, 'Essai')$$, :'ceo'), 'le CEO ne se bloque pas');
select public.rh_bloquer_employe(:'e_membre', true, 'Absence prolongée');
select essai.refuse(format($$select public.rh_bloquer_employe(%L, true, 'Encore')$$, :'e_membre'), 'on ne bloque pas deux fois');
reset role; select essai.personne();

select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.egal(public.rh_tableau_de_bord() -> 'moi', 'null'::jsonb, 'bloqué, il n''entre plus');
select essai.egal((public.rh_tableau_de_bord() ->> 'bloque')::boolean, true, 'et l''écran sait pourquoi');
select essai.egal((select count(*)::int from public.rh_messages), 0, 'il ne lit plus rien');
reset role; select essai.personne();
select essai.verifie(public.rh_calculer_fiche(:'e_membre', '2026-11-01') is not null, 'bloqué, sa paie se calcule toujours');
delete from public.rh_fiches_paie where employe_id = :'e_membre' and mois = '2026-11-01';

select essai.devenir(:SUPER2::uuid); set role authenticated;
select essai.verifie(public.rh_peut_bloquer() and not public.rh_est_ceo(), 'un superadministrateur qui n''est pas le CEO');
select public.rh_bloquer_employe(:'e_membre', false, '');
reset role; select essai.personne();
select essai.egal((select etat from public.rh_employes where id = :'e_membre'), 'actif', 'débloqué par lui, il est de nouveau en poste');
select essai.egal((select string_agg(action || ':' || par_nom, ',' order by id) from public.rh_journal_employes
                    where employe_id = :'e_membre'), 'bloque:Directeur AKPLOGAN,debloque:Superadministrateur',
  'le journal dit qui a bloqué et qui a débloqué');
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.verifie(public.rh_tableau_de_bord() -> 'moi' <> 'null'::jsonb, 'et il rentre');
reset role; select essai.personne();

select essai.verifie(not exists (select 1 from public.rh_fiches_paie where employe_id = :'e_refuse'),
  'la fiche refusée n''a aucune paie');
select essai.verifie(exists (select 1 from public.rh_fiches_paie where employe_id = :'e_autre' and statut <> 'calculee'),
  'le logisticien a une paie validée');
select (select count(*) from public.rh_fiches_paie where employe_id = :'e_autre' and statut <> 'calculee') as fiches_autre \gset
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_supprimer_employe(%L, '')$$, :'e_refuse'), 'une suppression sans motif est refusée');
select essai.refuse(format($$select public.rh_supprimer_employe(%L, 'Essai')$$, :'ceo'), 'le CEO ne se supprime pas');
select essai.egal(public.rh_supprimer_employe(:'e_refuse', 'Doublon'), 'efface', 'sans paie : tout s''efface');
select essai.egal(public.rh_supprimer_employe(:'e_autre', 'Départ sans préavis'), 'archive',
  'avec une paie validée : la fiche est archivée');
reset role; select essai.personne();
select essai.verifie(not exists (select 1 from public.rh_employes where id = :'e_refuse'), 'la fiche effacée n''existe plus');
select essai.egal((select etat || '/' || coalesce(compte_id::text, '-') || '/' || coalesce(email_pro, '-') || '/' || telephone || '/' || matricule
                     from public.rh_employes where id = :'e_autre'),
  'supprime/-/-//' || (select matricule from public.rh_employes where id = :'e_autre'),
  'archivée : plus d''accès, plus d''adresse ni de téléphone ; le matricule reste');
select essai.egal((select count(*) from public.rh_fiches_paie where employe_id = :'e_autre'), :'fiches_autre'::bigint,
  'ses fiches de paie validées restent, pour la comptabilité');
select essai.egal((select count(*)::int from public.rh_messages where auteur_id = :'e_autre' or destinataire_id = :'e_autre'), 0,
  'ses messages sont partis');
select essai.egal((select string_agg(action, ',' order by id) from public.rh_journal_employes
                    where employe_id in (:'e_refuse', :'e_autre')), 'efface,supprime', 'les deux gestes sont au journal');
select essai.devenir(:AUTRE::uuid); set role authenticated;
select essai.egal(public.rh_tableau_de_bord() -> 'moi', 'null'::jsonb, 'supprimé, son compte n''ouvre plus rien');
select essai.refuse(format($$select public.rh_rattacher_compte(%L)$$, :'e_autre'), 'ni ne se rattache de nouveau');
reset role; select essai.personne();
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.verifie(not exists (select 1 from public.rh_annuaire() where id = :'e_autre'), 'il sort de l''annuaire');
select essai.egal((select count(*)::int from public.rh_journal_employes), 0, 'un employé ne lit pas le journal');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('16. Les statistiques internes : salaires, dépenses, effectifs, revenus');
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.refuse($$select public.rh_finances()$$, 'un employé ne voit pas les finances');
reset role; select essai.personne();

select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_finances('2026-09-01', current_date) as fin_admin \gset
reset role; select essai.personne();
select essai.egal(:'fin_admin'::jsonb -> 'revenus', 'null'::jsonb, 'l''administration ne voit pas les revenus de BIZZOO');
select essai.egal((:'fin_admin'::jsonb #>> '{droits,revenus}')::boolean, false, 'et la base le lui dit');
select essai.egal((select (x ->> 'brut')::bigint from jsonb_array_elements(:'fin_admin'::jsonb #> '{salaires,par_mois}') x
                    where x ->> 'mois' = '2026-09-01'),
  (select sum(brut)::bigint from public.rh_fiches_paie where mois = '2026-09-01' and statut <> 'calculee'),
  'le brut de septembre est celui des fiches validées');
select essai.egal((select sum((x ->> 'montant_decaisse')::bigint)::bigint from jsonb_array_elements(:'fin_admin'::jsonb #> '{depenses,par_mois}') x),
  (select coalesce(sum(montant), 0)::bigint from public.rh_depenses where statut = 'decaissee' and decaisse_le >= '2026-09-01'),
  'les dépenses décaissées sont toutes comptées');
select essai.egal((:'fin_admin'::jsonb #>> '{effectifs,en_poste}')::bigint,
  (select count(*) from public.rh_employes where etat in ('actif', 'bloque')), 'l''effectif en poste');

select essai.devenir(:SUPER2::uuid); set role authenticated;
select public.rh_finances(current_date, current_date) as fin_super \gset
reset role; select essai.personne();
select (:'fin_super'::jsonb #> '{revenus,0}') as ce_mois \gset
select essai.egal((:'ce_mois'::jsonb ->> 'marge')::bigint,
  (select coalesce(sum(greatest(0, l.prix - l.prix_bizzoo) * l.quantite), 0)::bigint
     from public.commande_lignes l join public.commandes c on c.id = l.commande_id
    where c.etat = 'payee' and l.etat <> 'annulee'
      and date_trunc('month', c.paye_le at time zone 'Africa/Porto-Novo') = date_trunc('month', now() at time zone 'Africa/Porto-Novo')),
  'le superadministrateur voit la marge du mois, exacte');
select essai.verifie((:'ce_mois'::jsonb ->> 'marge')::bigint > 0, 'la commande d''essai y compte');
select essai.egal((:'ce_mois'::jsonb ->> 'resultat')::bigint,
  (:'ce_mois'::jsonb ->> 'revenus')::bigint - (:'ce_mois'::jsonb ->> 'salaires')::bigint - (:'ce_mois'::jsonb ->> 'depenses')::bigint,
  'résultat = revenus − salaires − dépenses');
select essai.egal((:'ce_mois'::jsonb ->> 'revenus')::bigint,
  (:'ce_mois'::jsonb ->> 'marge')::bigint + (:'ce_mois'::jsonb ->> 'frais_livraison')::bigint
  - (:'ce_mois'::jsonb ->> 'remises')::bigint - (:'ce_mois'::jsonb ->> 'gains_livreurs')::bigint,
  'revenus = marge + frais de livraison − remises − gains des livreurs');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.verifie(public.rh_finances() -> 'revenus' <> 'null'::jsonb, 'le CEO les voit aussi');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('17. Les pièces jointes des discussions, et l''effacement à 7 jours');
-- Comme dans Supabase, les comptes connectés atteignent la table du
-- stockage ; ce sont ses règles qui trient.
grant select, insert, delete on storage.objects to authenticated;
alter table storage.objects enable row level security;
select essai.verifie((select not public from storage.buckets where id = 'rh-pieces'), 'le seau des pièces est privé');
insert into storage.objects (bucket_id, name, metadata) values
  ('rh-pieces', :'e_membre' || '/photo-1.jpg', '{"mimetype": "image/jpeg", "size": 120000}'),
  ('rh-pieces', :'e_membre' || '/note.webm', '{"mimetype": "audio/webm", "size": 30000}'),
  ('rh-pieces', :'e_membre' || '/contrat.pdf', '{"mimetype": "application/pdf", "size": 9000}'),
  ('rh-pieces', :'e_resp' || '/video.mp4', '{"mimetype": "video/mp4", "size": 4000000}');

select essai.devenir(:MEMBRE::uuid); set role authenticated;
insert into public.rh_messages (profil_id, texte, piece, piece_nom)
values (:'p_mkt', '', :'e_membre' || '/photo-1.jpg', 'Affiche.jpg');
select essai.egal((select piece_type || '/' || piece_taille || '/' || piece_nom from public.rh_messages
                    where piece = :'e_membre' || '/photo-1.jpg'), 'image/120000/Affiche.jpg',
  'une photo s''envoie sans texte ; type et poids viennent du stockage');
insert into public.rh_messages (destinataire_id, texte, piece, piece_type, piece_taille)
values (:'e_resp', 'Écoute ça', :'e_membre' || '/note.webm', 'image', 1);
select essai.egal((select piece_type || '/' || piece_taille from public.rh_messages where piece = :'e_membre' || '/note.webm'),
  'audio/30000', 'un message vocal ; le type et le poids annoncés par l''écran ne comptent pas');
select essai.refuse(format($$insert into public.rh_messages (profil_id, texte, piece) values (%L, '', %L)$$, :'p_mkt', :'e_resp' || '/video.mp4'),
  'on n''envoie pas le fichier d''un autre');
select essai.refuse(format($$insert into public.rh_messages (profil_id, texte, piece) values (%L, '', %L)$$, :'p_mkt', :'e_membre' || '/photo-1.jpg'),
  'ni deux fois le même');
select essai.refuse(format($$insert into public.rh_messages (profil_id, texte, piece) values (%L, '', %L)$$, :'p_mkt', :'e_membre' || '/absent.jpg'),
  'ni un fichier qui n''existe pas');
select essai.refuse(format($$insert into public.rh_messages (profil_id, texte, piece) values (%L, '', %L)$$, :'p_mkt', :'e_membre' || '/contrat.pdf'),
  'ni autre chose qu''une photo, une vidéo ou un audio');
select essai.refuse(format($$insert into public.rh_messages (profil_id, texte) values (%L, '  ')$$, :'p_mkt'),
  'un message vide, sans pièce, reste refusé');
select essai.refuse(format($$insert into storage.objects (bucket_id, name) values ('rh-pieces', %L)$$, :'e_resp' || '/intrus.jpg'),
  'personne ne dépose dans le dossier d''un autre');
insert into storage.objects (bucket_id, name, metadata) values ('rh-pieces', :'e_membre' || '/la-mienne.jpg', '{"mimetype": "image/jpeg"}');
select essai.verifie(true, 'chacun dépose dans son dossier');
reset role; select essai.personne();

select essai.devenir(:RESP::uuid); set role authenticated;
select essai.egal((select count(*)::int from storage.objects where bucket_id = 'rh-pieces' and name like :'e_membre' || '/%'), 2,
  'le responsable voit la photo du profil et la note qui lui est adressée — pas le reste');
reset role; select essai.personne();
select essai.devenir(:CAISSE::uuid); set role authenticated;
select essai.egal((select count(*)::int from storage.objects where bucket_id = 'rh-pieces' and name like :'e_membre' || '/%'), 0,
  'hors du profil, on ne voit aucun fichier');
reset role; select essai.personne();
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.egal((select count(*)::int from storage.objects where bucket_id = 'rh-pieces' and name like :'e_membre' || '/%'), 1,
  'l''administration voit la photo du profil, pas la note privée');
reset role; select essai.personne();

update public.rh_messages set cree_le = now() - interval '8 days' where piece = :'e_membre' || '/photo-1.jpg';
update storage.objects set created_at = now() - interval '8 days' where name = :'e_membre' || '/photo-1.jpg';
update storage.objects set created_at = now() - interval '2 hours' where name = :'e_membre' || '/contrat.pdf';
select (select count(*) from public.rh_messages) as nb_messages \gset
select essai.verifie(public.rh_purger_messages() >= 1, 'au bout de 7 jours, le message s''efface');
select essai.verifie(not exists (select 1 from public.rh_messages where piece = :'e_membre' || '/photo-1.jpg'),
  'avec sa pièce');
select essai.verifie(exists (select 1 from public.rh_messages where piece = :'e_membre' || '/note.webm'),
  'le message récent, lui, reste');
select essai.egal(public.rh_pieces_perimees(), array[:'e_membre' || '/photo-1.jpg', :'e_membre' || '/contrat.pdf'],
  'à effacer du stockage : la photo du message parti, et le fichier abandonné ; rien de récent ni de cité');
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.refuse($$select public.rh_purger_messages()$$, 'personne ne déclenche l''effacement à la main');
select essai.refuse($$select public.rh_pieces_perimees()$$, 'ni ne liste les fichiers à effacer');
reset role; select essai.personne();
delete from storage.objects where bucket_id = 'rh-pieces';
alter table storage.objects disable row level security;
revoke select, insert, delete on storage.objects from authenticated;
delete from public.rh_messages where piece is not null;

-- ---------------------------------------------------------
select essai.titre('18. Localiser un livreur');
\set LIVREUR_RH '''a0a0a0a0-0010-4000-8000-000000000010'''
insert into auth.users (id, email) values (:LIVREUR_RH::uuid, 'livreur.rh@essai.bj') on conflict do nothing;
insert into public.profils (id, email, role, actif, nom, boutique_id)
values (:LIVREUR_RH::uuid, 'livreur.rh@essai.bj', 'livreur', true, 'Codjo', 'bou_informatique')
on conflict (id) do update set role = 'livreur', actif = true, nom = 'Codjo', boutique_id = 'bou_informatique';
insert into public.positions_livreurs (profil_id, latitude, longitude, adresse)
values (:LIVREUR_RH::uuid, 6.36, 2.41, 'Cadjèhoun')
on conflict (profil_id) do update set latitude = 6.36, longitude = 2.41;

select essai.devenir(:LIVREUR_RH::uuid); set role authenticated;
select public.ouvrir_suivi_livreur() as suivi \gset
select essai.refuse($$select * from public.suivis_livreurs$$, 'un livreur ne lit pas les jetons de suivi');
reset role; select essai.personne();
select essai.egal((:'suivi'::jsonb ->> 'en_course')::boolean, false, 'sans course, rien à suivre');
select essai.egal(length(:'suivi'::jsonb ->> 'jeton'), 64, 'le jeton : 64 caractères tirés au hasard');
select essai.verifie(not exists (select 1 from public.suivis_livreurs where jeton_hash = :'suivi'::jsonb ->> 'jeton'),
  'la base n''en garde que l''empreinte');
select essai.egal(public.position_en_course(:'suivi'::jsonb ->> 'jeton', 6.37, 2.42) ->> 'continuer', 'false',
  'sans course, son téléphone s''arrête de lui-même');
select essai.egal((select latitude from public.positions_livreurs where profil_id = :LIVREUR_RH::uuid), 6.36::double precision,
  'et sa position ne bouge pas');

-- Une course : la commande payée de la section 12, livrée chez un point précis.
select essai.devenir(:CHEF::uuid); set role authenticated;
select public.assigner_livreur(:'cmd_rh', 'bou_informatique', :LIVREUR_RH::uuid) as confiee \gset
reset role; select essai.personne();
-- Le point du client, posé comme le ferait la commande au kilomètre :
-- déclencheurs coupés le temps de cette seule écriture du décor.
set session_replication_role = replica;
update public.commandes set livraison = '{"destination": {"latitude": 6.37, "longitude": 2.43}}'::jsonb where id = :'cmd_rh';
set session_replication_role = origin;
select essai.devenir(:LIVREUR_RH::uuid); set role authenticated;
select public.ouvrir_suivi_livreur() as suivi2 \gset
reset role; select essai.personne();
select essai.egal((:'suivi2'::jsonb ->> 'en_course')::boolean, true, 'en course, le suivi s''ouvre');
select essai.refuse(format($$select public.position_en_course(%L, 6.37, 2.42)$$, :'suivi'::jsonb ->> 'jeton'),
  'l''ancien jeton ne vaut plus rien');
select essai.refuse($$select public.position_en_course('faux', 6.37, 2.42)$$, 'un faux jeton est refusé');
update public.positions_livreurs set enregistre_le = now() - interval '1 minute' where profil_id = :LIVREUR_RH::uuid;
set role anon;
select essai.egal(public.position_en_course(:'suivi2'::jsonb ->> 'jeton', 6.365, 2.415, 12) ->> 'continuer', 'true',
  'sans session, le jeton suffit');
reset role;
select essai.egal((select latitude || '/' || longitude || '/' || precision_m from public.positions_livreurs
                    where profil_id = :LIVREUR_RH::uuid), '6.365/2.415/12', 'sa position suit');
select essai.egal(public.position_en_course(:'suivi2'::jsonb ->> 'jeton', 6.5, 2.5) ->> 'continuer', 'true',
  'une seconde position dans les 5 secondes');
select essai.egal((select latitude from public.positions_livreurs where profil_id = :LIVREUR_RH::uuid),
  6.365::double precision, 'n''écrit rien : une écriture toutes les 5 secondes au plus');
update public.positions_livreurs set enregistre_le = now() - interval '1 minute' where profil_id = :LIVREUR_RH::uuid;
select essai.egal(public.position_en_course(:'suivi2'::jsonb ->> 'jeton', 1000, 2.415) ->> 'continuer', 'true',
  'une position impossible est ignorée, sans arrêter le suivi');
select essai.egal((select latitude from public.positions_livreurs where profil_id = :LIVREUR_RH::uuid),
  6.365::double precision, 'et n''écrit rien');

select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.refuse($$select public.rh_localiser_livreurs()$$, 'menu fermé : un employé ne localise personne');
reset role; select essai.personne();
select essai.devenir(:ADMRH::uuid); set role authenticated;
select x as livreur_carte from jsonb_array_elements(public.rh_localiser_livreurs() -> 'livreurs') x
 where x ->> 'id' = :LIVREUR_RH \gset
select (x -> 'lignes' -> 0 ->> 'livreur_id') as livreur_suivi from public.rh_suivi_commande(:'cmd_rh') x \gset
reset role; select essai.personne();
select essai.egal((:'livreur_carte'::jsonb ->> 'en_course')::boolean, true, 'l''administration le voit en course');
select essai.egal(:'livreur_carte'::jsonb #>> '{courses,0,numero}', (select numero from public.commandes where id = :'cmd_rh'),
  'avec sa commande');
select essai.egal((:'livreur_carte'::jsonb #>> '{courses,0,distance_km}')::numeric,
  round((sqrt((0.005 * 111.195) ^ 2 + (0.015 * 111.195 * cos(radians(6.3675))) ^ 2)
         * (select livraison_coef from public.paiement where id = 1))::numeric, 1),
  'et la distance jusqu''au client, coefficient de route compris');
select essai.verifie(not (:'livreur_carte'::jsonb::text ~ '"(total|prix|montant|frais)"'), 'sans aucun montant');
select essai.egal(:'livreur_suivi'::text, :LIVREUR_RH::text, 'le suivi des commandes donne son identifiant, pour « Voir sa position »');

select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_regler_acces(:'p_mkt', '{"livreurs":"membres"}');
reset role; select essai.personne();
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.verifie(jsonb_array_length(public.rh_localiser_livreurs() -> 'livreurs') >= 1, 'ouvert au profil, le membre localise');
reset role; select essai.personne();
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_regler_acces(:'p_mkt', '{"livreurs":"ferme"}');
reset role; select essai.personne();

update public.commande_lignes set etat = 'remise' where commande_id = :'cmd_rh';
select essai.egal(public.position_en_course(:'suivi2'::jsonb ->> 'jeton', 6.37, 2.43) ->> 'continuer', 'false',
  'course remise : le suivi s''arrête');
select essai.verifie(not exists (select 1 from public.suivis_livreurs where profil_id = :LIVREUR_RH::uuid),
  'et son jeton disparaît');
delete from auth.users where id = :LIVREUR_RH::uuid;

-- ---------------------------------------------------------
select essai.titre('19. La caisse');
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.egal(public.rh_caisse_acces(), null::text, 'un employé ne voit pas la caisse');
select essai.refuse($$select public.rh_caisse()$$, 'ni ne la lit');
select essai.refuse($$select * from public.rh_caisse_mouvements$$, 'ni ne lit ses mouvements directement');
select essai.refuse($$select public.rh_caisse_apport('especes', 1000, 'ceo')$$, 'ni n''y fait entrer d''argent');
reset role; select essai.personne();
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.egal(public.rh_caisse_acces(), null::text, 'l''administration non plus, d''office');
select essai.refuse(format($$select public.rh_designer_gestionnaire_caisse(%L)$$, :'e_admrh'),
  'ni ne désigne le gestionnaire');
reset role; select essai.personne();
select essai.devenir(:SUPER2::uuid); set role authenticated;
select essai.egal(public.rh_caisse_acces(), 'super', 'le superadministrateur la voit');
reset role; select essai.personne();

select essai.devenir(:CAISSE::uuid); set role authenticated;
select essai.egal(public.rh_caisse_acces(), 'gestion', 'son gestionnaire la tient');
select (select sum((x ->> 'solde')::bigint) from jsonb_array_elements(public.rh_caisse() -> 'comptes') x) as solde_avant \gset
select public.rh_caisse_apport('celtiis', 50000, 'autre', 'Vente de cartons', 'CEL-1');
select essai.refuse($$select public.rh_caisse_apport('moov', 5000, 'autre', '')$$, 'un apport d''une autre source se nomme');
select essai.refuse($$select public.rh_caisse_transfert('celtiis', 'especes', 60000)$$,
  'on ne déplace pas plus que le compartiment n''a');
select public.rh_caisse_transfert('celtiis', 'especes', 40000, 500, 'Retrait au kiosque');
select essai.refuse($$select public.rh_caisse_ajustement('especes', -1000, 'Pièce perdue')$$,
  'le gestionnaire n''ajuste pas : le CEO seul');
select public.rh_caisse() as caisse \gset
reset role; select essai.personne();
select essai.egal((select (x ->> 'solde')::bigint from jsonb_array_elements(:'caisse'::jsonb -> 'comptes') x where x ->> 'compte' = 'celtiis'),
  9500::bigint, 'Celtiis : 50 000 entrés, 40 000 déplacés, 500 de frais');
select essai.egal((select sum((x ->> 'solde')::bigint)::bigint from jsonb_array_elements(:'caisse'::jsonb -> 'comptes') x),
  :'solde_avant'::bigint + 50000 - 500, 'le solde total : la somme des quatre compartiments');
select essai.egal((select solde_total from public.rh_caisse_mouvements order by id desc limit 1),
  :'solde_avant'::bigint + 50000 - 500, 'chaque mouvement garde le solde qu''il laisse');
select essai.refuse($$update public.rh_caisse_mouvements set montant = 1$$, 'un mouvement ne se modifie pas');
select essai.refuse($$delete from public.rh_caisse_mouvements$$, 'ni ne s''efface');

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse($$select public.rh_caisse_ajustement('moov', -1, 'Écart')$$, 'aucun compartiment ne passe sous zéro');
select public.rh_caisse_ajustement('especes', -1000, 'Écart constaté au comptage');
select essai.egal((select (x ->> 'nature') || '/' || (x ->> 'sens') || '/' || (x ->> 'montant') from (select public.rh_caisse() -> 'mouvements' -> 0 as x) y),
  'ajustement/sortie/1000', 'le CEO corrige par un ajustement motivé');
select public.rh_regler_acces(:'p_mkt', '{"caisse":"responsable"}');
reset role; select essai.personne();

select essai.devenir(:RESP::uuid); set role authenticated;
select essai.egal(public.rh_caisse_acces(), 'consultation', 'le responsable du Marketing consulte, droit reçu');
select public.rh_caisse('2026-01-01', current_date) as vue_resp \gset
select essai.refuse($$select public.rh_caisse_apport('especes', 1000, 'ceo')$$, 'il consulte seulement');
reset role; select essai.personne();
select essai.egal((select string_agg(x ->> 'libelle', '|') from jsonb_array_elements(:'vue_resp'::jsonb -> 'mouvements') x
                    where x ->> 'nature' = 'salaire'), :'libelle_sept',
  'en consultation, un salaire ne dit pas de qui il est');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal((select string_agg(x ->> 'libelle', '|') from jsonb_array_elements(public.rh_caisse('2026-01-01', current_date) -> 'mouvements') x
                    where x ->> 'nature' = 'salaire'),
  :'libelle_sept' || ' · ' || (select btrim(prenoms || ' ' || nom) from public.rh_employes where id = :'e_resp'),
  'le CEO, lui, voit de qui');
reset role; select essai.personne();
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.egal(public.rh_caisse_acces(), null::text, 'ses membres, eux, ne la voient pas');
reset role; select essai.personne();

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select public.rh_regler_acces(:'p_mkt', '{"caisse":"ferme"}');
select public.rh_designer_gestionnaire_caisse(:'e_admrh');
reset role; select essai.personne();
select essai.devenir(:CAISSE::uuid); set role authenticated;
select essai.egal(public.rh_peut_decaisser(), false, 'remplacé, l''ancien gestionnaire ne décaisse plus');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select public.rh_designer_gestionnaire_caisse(:'e_caisse');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('20. La fiche complète et la connexion par numéro');
select essai.devenir(:SUPER2::uuid); set role authenticated;
update public.rh_employes set salaire_base = 123000, poste = 'Chargée de communication' where id = :'e_membre';
reset role; select essai.personne();
select essai.egal((select salaire_base || '/' || poste from public.rh_employes where id = :'e_membre'),
  '123000/Chargée de communication', 'le superadministrateur modifie la fiche, salaire compris, comme le CEO');

select essai.devenir(:ADMRH::uuid); set role authenticated;
update public.rh_employes set telephone = '0140000001' where id = :'e_membre';
select essai.refuse(format($$update public.rh_employes set telephone = '0140000001' where id = %L$$, :'e_resp'),
  'un numéro ne sert qu''à un employé en poste');
select essai.refuse(format($$insert into public.rh_employes_sensibles (employe_id, ethnie) values (%L, 'X')$$, :'e_membre'),
  'l''administration n''écrit pas les données sensibles');
reset role; select essai.personne();

select essai.devenir(:MEMBRE::uuid); set role authenticated;
update public.rh_employes set sexe = 'F', langue = 'Fon', marie = 'Non', moto = false, adresse = 'Cadjèhoun',
       email_perso = 'membre@exemple.bj' where id = :'e_membre';
select essai.refuse(format($$update public.rh_employes set telephone = '0149999999' where id = %L$$, :'e_membre'),
  'l''employé ne change pas son numéro : c''est par lui qu''il se connecte');
select essai.refuse(format($$update public.rh_employes set poste = 'Directrice' where id = %L$$, :'e_membre'),
  'ni son poste');
select essai.egal((select count(*)::int from public.rh_employes_sensibles), 0, 'il ne lit pas les données sensibles');
reset role; select essai.personne();
select essai.egal((select sexe || '/' || langue || '/' || marie || '/' || moto || '/' || adresse from public.rh_employes where id = :'e_membre'),
  'F/Fon/Non/false/Cadjèhoun', 'l''employé complète ce qui le regarde');

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
insert into public.rh_employes_sensibles (employe_id, ethnie, religion) values (:'e_membre', 'Fon', 'Catholique');
reset role; select essai.personne();
select essai.devenir(:SUPER2::uuid); set role authenticated;
select essai.egal((select ethnie || '/' || religion from public.rh_employes_sensibles where employe_id = :'e_membre'),
  'Fon/Catholique', 'le CEO les écrit, le superadministrateur les lit');
reset role; select essai.personne();
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.rh_employes_sensibles), 0, 'l''administration ne les voit pas');
reset role; select essai.personne();

set role anon;
select essai.egal(public.rh_telephone_employe('+229 01 40 00 00 01'), true, 'un numéro d''employé, écrit n''importe comment, est reconnu');
select essai.egal(public.rh_telephone_employe('0199999999'), false, 'un numéro inconnu ne reçoit pas de code');
reset role;

-- Une fiche sans compte ni sexe, avec un numéro : elle se relie à la connexion.
\set TEL_RH '''a0a0a0a0-0011-4000-8000-000000000011'''
\set TEL_AUTRE '''a0a0a0a0-0012-4000-8000-000000000012'''
select set_config('rh.decision', 'oui', false);
insert into public.rh_employes (nom, prenoms, telephone, date_embauche, etat, statut, salaire_base, profil_id)
values ('ESSAI', 'Téléphone', '0140000002', '2026-10-01', 'actif', 'employe', 65000, :'p_mkt')
returning id as e_tel \gset
select set_config('rh.decision', '', false);
select essai.verifie((select sexe is null from public.rh_employes where id = :'e_tel'), 'le sexe peut rester vide');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.verifie((public.rh_finances() #>> '{effectifs,par_sexe,NR}')::int >= 1,
  'un sexe vide ne casse pas les statistiques internes : il compte « non renseigné »');
reset role; select essai.personne();
insert into auth.users (id, phone, raw_user_meta_data) values
  (:TEL_RH::uuid, '2290140000002', '{"compte":"personnel"}'),
  (:TEL_AUTRE::uuid, '2290140000001', '{"compte":"personnel"}') on conflict do nothing;
select essai.devenir(:TEL_RH::uuid); set role authenticated;
select essai.egal(public.rh_rattacher_par_telephone(), :'e_tel'::uuid, 'connecté par son numéro, il rejoint sa fiche');
select essai.verifie(public.rh_tableau_de_bord() -> 'moi' <> 'null'::jsonb, 'et il entre');
select essai.egal(public.rh_rattacher_par_telephone(), :'e_tel'::uuid, 'se reconnecter ne change rien');
reset role; select essai.personne();
select essai.devenir(:TEL_AUTRE::uuid); set role authenticated;
select essai.refuse($$select public.rh_rattacher_par_telephone()$$,
  'une fiche déjà reliée à un autre compte ne change pas de main');
reset role; select essai.personne();
select set_config('rh.decision', 'oui', false);
delete from auth.users where id in (:TEL_RH::uuid, :TEL_AUTRE::uuid);
update public.rh_employes set etat = 'supprime', telephone = '' where id = :'e_tel';
update public.rh_employes set telephone = '' where id = :'e_membre';
select set_config('rh.decision', '', false);

-- ---------------------------------------------------------
select essai.titre('21. Le solde, les primes du CEO, les prêts et les retraits');
-- Les dates réelles du banc changent d'un jour à l'autre : on compare
-- des écarts de solde, et ce qui dépend du 10 se lit sur le calendrier.
select essai.egal(public.rh_date_versement('2026-09-01'), '2026-10-10'::date, 'la paie de septembre se verse le 10 octobre');
select essai.egal(public.rh_date_versement('2026-12-01'), '2027-01-10'::date, 'celle de décembre, le 10 janvier');
select essai.egal(public.rh_numero_national('97 00 00 01'), '0197000001', 'un numéro à huit chiffres reçoit son 01');
select essai.egal(public.rh_numero_national('+229 01 97 00 00 01'), '0197000001', 'un numéro international perd son 229');
select essai.refuse($$select public.rh_numero_national('12345')$$, 'un numéro trop court est refusé');

-- Les primes et retenues du CEO
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_octroyer(%L, 'prime', 1000, 'Bravo')$$, :'e_membre'),
  'l''administration n''accorde pas de prime ainsi : le CEO seul');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select public.rh_octroyer(:'e_admrh', 'prime', 15000, 'Prime d''assiduité') as mois_prime \gset
select public.rh_octroyer(:'e_admrh', 'retenue', 4000, 'Casse d''un casque') as mois_retenue \gset
select essai.refuse(format($$select public.rh_octroyer(%L, 'prime', 0, 'Rien')$$, :'e_admrh'), 'un montant positif');
select essai.refuse(format($$select public.rh_octroyer(%L, 'bonus', 100, 'Autre chose')$$, :'e_admrh'), 'une prime ou une retenue, rien d''autre');
select essai.refuse(format($$select public.rh_octroyer(%L, 'prime', 100, '')$$, :'e_admrh'), 'avec son libellé');
select public.rh_compte_employe(:'e_admrh') as compte_autre \gset
reset role; select essai.personne();
select essai.egal(:'mois_prime'::date, public.rh_prochain_mois_paie(:'e_admrh'), 'la prime va sur la prochaine paie');
select essai.egal(:'mois_retenue'::date, :'mois_prime'::date, 'la retenue aussi');
select essai.verifie(not exists (select 1 from public.rh_fiches_paie where employe_id = :'e_admrh'
                                    and mois = :'mois_prime'::date and statut <> 'calculee'),
  'jamais sur une paie déjà validée');
select essai.egal((select imposable from public.rh_elements_paie where employe_id = :'e_admrh' and libelle = 'Prime d''assiduité'),
  true, 'une prime du CEO est imposable');
select essai.egal(jsonb_array_length(:'compte_autre'::jsonb -> 'elements'), 2, 'le CEO les voit sur le compte de l''employé');

-- Le prêt : l'employé le demande, le CEO le valide, la caisse le décaisse
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.refuse($$select public.rh_demander_pret(0, 'Rien')$$, 'un prêt a un montant');
select essai.refuse($$select public.rh_demander_pret(20000, '')$$, 'et un motif');
select public.rh_demander_pret(20000, 'Frais de scolarité') as pret \gset
select essai.refuse($$select public.rh_demander_pret(5000, 'Encore un')$$, 'un seul prêt en attente à la fois');
select essai.refuse(format($$select public.rh_decider_pret(%L, true)$$, :'pret'), 'il ne valide pas son prêt');
select essai.refuse($$select public.rh_prets_retraits()$$, 'ni ne lit la liste des prêts et retraits');
reset role; select essai.personne();
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_generer_paie(:'mois_prime'::date);
reset role; select essai.personne();
select essai.egal((select primes || '/' || retenues || '/' || avances from public.rh_fiches_paie
                    where employe_id = :'e_admrh' and mois = :'mois_prime'::date), '15000/4000/0',
  'la fiche porte la prime et la retenue ; un prêt demandé ne retient rien');
select essai.devenir(:CAISSE::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_decaisser_pret(%L, '{"especes": 20000}')$$, :'pret'),
  'la caisse ne décaisse pas un prêt que le CEO n''a pas validé');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal((public.rh_compteurs_solde() ->> 'prets_a_valider')::int, 1, 'le CEO a un prêt à valider');
select essai.refuse(format($$select public.rh_decider_pret(%L, false, '')$$, :'pret'), 'un refus se motive');
select public.rh_decider_pret(:'pret', true);
reset role; select essai.personne();
select essai.devenir(:CAISSE::uuid); set role authenticated;
select essai.egal((public.rh_compteurs_solde() ->> 'prets_a_decaisser')::int, 1, 'le gestionnaire a un prêt à décaisser');
select essai.refuse(format($$select public.rh_decaisser_pret(%L, '{"especes": 15000}')$$, :'pret'),
  'la répartition doit tomber juste');
select public.rh_decaisser_pret(:'pret', '{"especes": 20000}', 'REC-PRET-1');
select essai.egal((select x ->> 'nature' || '/' || (x ->> 'montant') from (select public.rh_caisse() -> 'mouvements' -> 0 as x) y),
  'pret/20000', 'le prêt sort de la caisse');
reset role; select essai.personne();
select essai.egal((select statut || '/' || premier_mois from public.rh_avances where id = :'pret'),
  'active/' || public.rh_prochain_mois_paie(:'e_admrh'), 'décaissé, le prêt s''inscrit sur la prochaine paie');
select essai.egal((select avances from public.rh_fiches_paie where employe_id = :'e_admrh' and mois = :'mois_prime'::date),
  20000::bigint, 'et la paie le reprend en une fois');
select essai.egal((select net from public.rh_fiches_paie where employe_id = :'e_admrh' and mois = :'mois_prime'::date),
  (select brut - cotisations_salariales - impot - 4000 - 20000 from public.rh_fiches_paie
    where employe_id = :'e_admrh' and mois = :'mois_prime'::date),
  'à verser : salaire + prime − retenue − prêt (cotisations et impôt déduits)');

-- Un refus ; le gestionnaire ne décaisse pas son propre prêt
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select public.rh_demander_pret(500000, 'Achat d''une moto') as pret_membre \gset
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select public.rh_decider_pret(:'pret_membre', false, 'Montant trop élevé');
reset role; select essai.personne();
select essai.egal((select statut from public.rh_avances where id = :'pret_membre'), 'refusee', 'le CEO refuse, motif à l''appui');
select essai.devenir(:CAISSE::uuid); set role authenticated;
select public.rh_demander_pret(10000, 'Dépannage') as pret_caisse \gset
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select public.rh_decider_pret(:'pret_caisse', true);
reset role; select essai.personne();
select essai.devenir(:CAISSE::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_decaisser_pret(%L, '{"especes": 10000}')$$, :'pret_caisse'),
  'le gestionnaire ne décaisse pas son propre prêt');
select essai.egal((public.rh_compteurs_solde() ->> 'prets_a_decaisser')::int, 0, 'et ne le compte pas parmi ses tâches');
reset role; select essai.personne();

-- Les retraits
select public.rh_solde_de(:'e_membre') as solde_membre \gset
select essai.verifie(:'solde_membre'::bigint >= 75000, 'la stagiaire a son salaire de septembre sur son solde');
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.egal((public.rh_compte_employe() ->> 'solde')::bigint, :'solde_membre'::bigint, 'elle lit son solde');
select essai.refuse(format($$select public.rh_compte_employe(%L)$$, :'e_admrh'), 'pas celui d''un autre');
select essai.refuse($$select * from public.rh_solde_mouvements$$, 'ni la table des mouvements');
select essai.refuse($$select * from public.rh_retraits$$, 'ni celle des retraits');
select essai.refuse(format($$select public.rh_demander_retrait(%s, 'caisse')$$, :'solde_membre'::bigint + 1),
  'pas plus que son solde');
select essai.refuse($$select public.rh_demander_retrait(1000, 'feexpay', 'orange', '0197000001')$$, 'MTN, Moov ou Celtiis');
select essai.refuse($$select public.rh_demander_retrait(30, 'feexpay', 'mtn', '0197000001')$$, 'au moins 50 francs par Mobile Money');
select essai.refuse($$select public.rh_demander_retrait(1000, 'feexpay', 'mtn', '12345')$$, 'un vrai numéro');
select public.rh_demander_retrait(30000, 'feexpay', 'mtn', '97 00 00 01') as r1 \gset
select public.rh_demander_retrait(10000, 'caisse') as r2 \gset
select essai.egal((public.rh_compte_employe() ->> 'solde')::bigint, :'solde_membre'::bigint - 40000,
  'demandés, les retraits quittent aussitôt le solde');
select public.rh_annuler_retrait(:'r2');
select essai.egal((public.rh_compte_employe() ->> 'solde')::bigint, :'solde_membre'::bigint - 30000,
  'annulé, le retrait revient sur le solde');
select essai.refuse(format($$select public.rh_annuler_retrait(%L)$$, :'r2'), 'une seule fois');
select essai.refuse(format($$select public.rh_retrait_preparer(%L)$$, :'r1'), 'elle ne lance pas elle-même le reversement');
select essai.refuse(format($$select public.rh_retrait_resultat(%L, 'paye')$$, :'r1'), 'ni ne s''écrit « payé »');
reset role; select essai.personne();
select essai.egal((select telephone || '/' || reseau from public.rh_retraits where id = :'r1'), '0197000001/mtn',
  'le numéro est rangé sous sa forme nationale');

select essai.devenir(:CAISSE::uuid); set role authenticated;
select essai.verifie((public.rh_compteurs_solde() ->> 'retraits_a_servir')::int >= 1, 'le gestionnaire a un retrait à servir');
select public.rh_retrait_preparer(:'r1') as prep \gset
select essai.egal((:'prep'::jsonb ->> 'montant')::bigint, 30000::bigint, 'le montant envoyé vient de la base');
select essai.refuse(format($$select public.rh_retrait_preparer(%L)$$, :'r1'), 'deux clics ne font pas deux virements');
select essai.refuse(format($$select public.rh_servir_retrait(%L, '{"mtn": 30000}')$$, :'r1'),
  'ni un virement et un paiement à la caisse');
reset role; select essai.personne();
-- Ce que la fonction Edge constate chez FeexPay (droits du service)
select essai.egal(public.rh_retrait_resultat(:'r1', 'paye', 'X'), 'envoi', 'pas « payé » avant d''avoir été accepté par FeexPay');
select public.rh_retrait_resultat(:'r1', 'envoye', 'FEEX-REF-1', '{"statut": 200}');
select essai.verifie(public.rh_retraits_a_verifier() @> jsonb_build_array(jsonb_build_object('id', :'r1'::uuid)),
  'un reversement accepté reste à revérifier');
select public.rh_retrait_resultat(:'r1', 'echoue', '', '{"status": "FAILED"}');
select essai.egal(public.rh_retrait_resultat(:'r1', 'paye', '', '{}'), 'echoue', 'un reversement échoué ne devient pas payé');
select essai.egal(public.rh_solde_de(:'e_membre'), :'solde_membre'::bigint, 'échoué, le montant est revenu sur le solde');
select essai.egal((select reference from public.rh_retraits where id = :'r1'), 'FEEX-REF-1', 'la référence FeexPay reste notée');

select essai.devenir(:MEMBRE::uuid); set role authenticated;
select public.rh_demander_retrait(20000, 'feexpay', 'moov', '0195000002') as r3 \gset
select public.rh_demander_retrait(5000, 'caisse') as r4 \gset
reset role; select essai.personne();
select essai.devenir(:CAISSE::uuid); set role authenticated;
select public.rh_retrait_preparer(:'r3');
select essai.refuse(format($$select public.rh_refuser_retrait(%L, '')$$, :'r4'), 'un refus se motive');
select public.rh_refuser_retrait(:'r4', 'Caisse vide ce jour');
reset role; select essai.personne();
select public.rh_retrait_resultat(:'r3', 'incertain', '', '{"erreur": "délai dépassé"}');
select essai.devenir(:CAISSE::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_retrait_trancher(%L, true, 'Vu chez FeexPay')$$, :'r3'),
  'le gestionnaire ne tranche pas un reversement incertain');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal((public.rh_compteurs_solde() ->> 'retraits_incertains')::int, 1, 'le CEO voit le reversement incertain');
select public.rh_retrait_trancher(:'r3', true, 'Vu SUCCESSFUL dans le tableau de bord FeexPay');
select public.rh_prets_retraits() as liste_ceo \gset
reset role; select essai.personne();
select essai.egal((select statut from public.rh_retraits where id = :'r3'), 'paye', 'le CEO le déclare payé, constat à l''appui');
select essai.egal(public.rh_solde_de(:'e_membre'), :'solde_membre'::bigint - 20000, 'payé 20 000, refusé 5 000 : rendu');
select essai.verifie(jsonb_array_length(:'liste_ceo'::jsonb -> 'soldes') >= 5, 'le CEO voit le solde de chacun');

-- Le gestionnaire ne se sert pas lui-même
select essai.devenir(:CAISSE::uuid); set role authenticated;
select public.rh_demander_retrait(1000, 'caisse') as r_caisse \gset
select essai.refuse(format($$select public.rh_servir_retrait(%L, '{"especes": 1000}')$$, :'r_caisse'),
  'le gestionnaire ne sert pas son propre retrait');
select public.rh_annuler_retrait(:'r_caisse');
reset role; select essai.personne();

-- La fiche du mois de la prime : validée, versée le 10 suivant
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select public.rh_valider_paie(:'mois_prime'::date);
reset role; select essai.personne();
select essai.egal((select statut from public.rh_fiches_paie where employe_id = :'e_admrh' and mois = :'mois_prime'::date),
  case when public.rh_aujourdhui() >= public.rh_date_versement(:'mois_prime'::date) then 'payee' else 'validee' end,
  'validée, la fiche attend le 10 du mois suivant pour se verser');
select essai.egal(public.rh_crediter_salaires(), 0, 'le passage du matin ne verse rien avant le 10');

-- Rien ne s'efface, et chaque solde tombe juste
select essai.refuse($$update public.rh_solde_mouvements set montant = 1$$, 'un mouvement du solde ne se modifie pas');
select essai.refuse($$delete from public.rh_solde_mouvements$$, 'ni ne s''efface');
select essai.egal((select count(*)::int from public.rh_solde_mouvements m
                    where m.solde <> (select sum(case when x.sens = 'credit' then x.montant else -x.montant end)
                                        from public.rh_solde_mouvements x
                                       where x.employe_id = m.employe_id and x.id <= m.id)), 0,
  'chaque mouvement garde le solde qu''il laisse');
select essai.egal((select count(*)::int from public.rh_solde_mouvements where nature = 'retrait' and solde < 0), 0,
  'aucun retrait n''a fait passer un solde sous zéro');
select essai.egal((select count(*)::int from public.rh_retraits r
                    where r.statut in ('echoue', 'refuse', 'annule')
                      and not exists (select 1 from public.rh_solde_mouvements m
                                       where m.retrait_id = r.id and m.nature = 'retour' and m.montant = r.montant)), 0,
  'tout retrait qui n''a pas abouti est revenu sur le solde');

-- ---------------------------------------------------------
select essai.titre('22. L''accueil : la place de marché d''un coup d''œil');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select coalesce(public.rh_accueil_chiffres(), 'null'::jsonb) as acc_ceo \gset
reset role; select essai.personne();
select essai.devenir(:ADMRH::uuid); set role authenticated;
select coalesce(public.rh_accueil_chiffres(), 'null'::jsonb) as acc_adm \gset
reset role; select essai.personne();
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select coalesce(public.rh_accueil_chiffres(), 'null'::jsonb) as acc_membre \gset
reset role; select essai.personne();
select essai.verifie((:'acc_ceo'::jsonb #> '{commandes,marge_mois}') <> 'null'::jsonb, 'le CEO voit la marge du mois');
select essai.verifie((:'acc_adm'::jsonb #> '{commandes,ventes_mois}') <> 'null'::jsonb, 'l''administration voit les ventes');
select essai.verifie((:'acc_adm'::jsonb #> '{commandes,marge_mois}') = 'null'::jsonb, 'mais pas la marge');
select essai.verifie(:'acc_membre'::jsonb = 'null'::jsonb or (:'acc_membre'::jsonb #> '{commandes,ventes_mois}') = 'null'::jsonb,
  'un employé ne voit aucun montant de la place de marché');
select essai.egal((:'acc_ceo'::jsonb #>> '{boutiques,total}')::bigint, (select count(*) from public.boutiques), 'le nombre de boutiques enregistrées');
select essai.egal((:'acc_ceo'::jsonb #>> '{clients,total}')::bigint, (select count(*) from public.clients), 'le nombre de clients');
select essai.egal((:'acc_ceo'::jsonb #>> '{produits,total}')::bigint, (select count(*) from public.produits where not masque), 'le nombre de produits en ligne');
select essai.egal((:'acc_ceo'::jsonb #>> '{commandes,payees_mois}')::bigint,
  (select count(*) from public.commandes where etat = 'payee'
     and paye_le >= date_trunc('month', (now() at time zone 'Africa/Porto-Novo'))::timestamp at time zone 'Africa/Porto-Novo'),
  'les commandes payées ce mois, heure du Bénin');
set role anon;
select essai.refuse($$select public.rh_accueil_chiffres()$$, 'un visiteur n''y a pas accès');
reset role;

-- ---------------------------------------------------------
select essai.titre('23. Un employé ne voit pas les informations des autres');
select set_config('rh.decision', 'oui', false);
update public.rh_employes set telephone_pro = '0190000099' where id = :'e_resp';
select set_config('rh.decision', '', false);
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.rh_employes), 1, 'un employé ne lit que sa propre fiche');
select essai.egal((select count(*)::int from public.rh_annuaire() where matricule is not null or sexe is not null), 0,
  'l''annuaire ne lui donne ni matricule ni sexe');
select array_agg(telephone order by id) as numeros_vus from public.rh_annuaire() where telephone is not null \gset
select essai.egal((select telephone from public.rh_annuaire() where id = :'e_resp'), '0190000099',
  'mais le téléphone PROFESSIONNEL d''un collègue, pour le joindre');
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.rh_employes where etat = 'actif' and telephone <> ''
                    and telephone = any(:'numeros_vus'::text[])), 0,
  'jamais son numéro personnel, celui qui sert à se connecter');
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.verifie((select count(*) from public.rh_annuaire() where matricule is not null) >= 3,
  'l''administration, elle, voit les matricules');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('24. La première connexion avec le mot de passe de départ');
\set TEL_NEUF '''a0a0a0a0-0024-4000-8000-000000000024'''
select set_config('rh.decision', 'oui', false);
insert into public.rh_employes (nom, prenoms, telephone, date_embauche, etat, statut, salaire_base, profil_id)
values ('PREMIERE', 'Connexion', '0140002424', '2026-10-01', 'actif', 'employe', 70000, :'p_mkt')
returning id as e_neuf \gset
select set_config('rh.decision', '', false);
-- Le compte que BIZZOO ouvre : numéro + mot de passe de départ, en attente d'activation.
insert into auth.users (id, phone, phone_confirmed_at, encrypted_password, raw_user_meta_data)
values (:TEL_NEUF::uuid, '2290140002424', now(), crypt('depart-essai', gen_salt('bf')), '{"compte":"personnel"}');
insert into public.rh_comptes_a_activer (compte_id, employe_id, empreinte)
select :TEL_NEUF::uuid, :'e_neuf', encrypted_password from auth.users where id = :TEL_NEUF::uuid;

select essai.devenir(:TEL_NEUF::uuid); set role authenticated;
select essai.egal(public.rh_moi(), null::uuid, 'avec le mot de passe de départ, il n''est encore personne pour la base');
select essai.egal((public.rh_tableau_de_bord() -> 'moi'), 'null'::jsonb, 'et n''ouvre rien');
select essai.egal((public.rh_activation() ->> 'a_activer')::boolean, true, 'on lui demande de choisir son mot de passe');
select essai.refuse($$select public.rh_rattacher_par_telephone()$$, 'il ne passe pas par le code SMS pour l''éviter');
select essai.refuse($$select public.rh_activer_compte()$$, 'ni ne s''active en gardant le mot de passe de départ');
select essai.refuse($$select * from public.rh_comptes_a_activer$$, 'ni ne lit la table des comptes à activer');
reset role; select essai.personne();
-- Il choisit son mot de passe (Supabase réécrit l'empreinte).
update auth.users set encrypted_password = crypt('le-sien-essai', gen_salt('bf')) where id = :TEL_NEUF::uuid;
select essai.devenir(:TEL_NEUF::uuid); set role authenticated;
select essai.egal(public.rh_activer_compte(), :'e_neuf'::uuid, 'son mot de passe à lui choisi, le compte rejoint sa fiche');
select essai.egal(public.rh_moi(), :'e_neuf'::uuid, 'et il entre');
select essai.egal((public.rh_activation() ->> 'a_activer')::boolean, false, 'plus rien à activer');
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.rh_comptes_a_activer), 0, 'l''empreinte du mot de passe de départ est oubliée');
select set_config('rh.decision', 'oui', false);
delete from auth.users where id = :TEL_NEUF::uuid;
update public.rh_employes set etat = 'supprime', telephone = '' where id = :'e_neuf';
select set_config('rh.decision', '', false);

-- ---------------------------------------------------------
select essai.titre('25. L''administration redonne un mot de passe');
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_mdp_preparer(%L)$$, :'e_resp'), 'un employé ne touche pas au mot de passe d''un autre');
reset role; select essai.personne();
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.egal(public.rh_mdp_preparer(:'e_membre'), :MEMBRE::uuid, 'l''administration obtient le compte à traiter');
select essai.refuse(format($$select public.rh_mdp_preparer(%L)$$, :'ceo'), 'pas celui du CEO');
select essai.refuse(format($$select public.rh_mdp_preparer(%L)$$, :'e_admrh'), 'ni le sien : c''est « Mon compte »');
select essai.refuse(format($$select public.rh_mdp_conclure(%L, %L, %L)$$, :'e_membre', :MEMBRE::uuid, :ADMRH::uuid),
  'la suite est réservée à la fonction Edge');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_mdp_preparer(%L)$$, :'ceo'), 'le CEO change le sien dans « Mon compte »');
reset role; select essai.personne();
-- La fonction Edge a posé le mot de passe provisoire, puis conclut.
update auth.users set encrypted_password = crypt('provisoire-essai', gen_salt('bf')) where id = :MEMBRE::uuid;
select public.rh_mdp_conclure(:'e_membre', :MEMBRE::uuid, :ADMRH::uuid, 'Mot de passe oublié');
select essai.egal((select compte_id from public.rh_employes where id = :'e_membre'), null::uuid,
  'avec le mot de passe provisoire, le compte est détaché de sa fiche');
select essai.egal((select action || '/' || par_nom from public.rh_journal_employes where employe_id = :'e_membre' order by id desc limit 1),
  'mot_de_passe/Rita HOUNKPE', 'le geste va au journal de la fiche, avec son auteur');
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.egal(public.rh_moi(), null::uuid, 'l''employé n''ouvre rien avant d''avoir choisi le sien');
select essai.refuse($$select public.rh_activer_compte()$$, 'ni ne garde le mot de passe provisoire');
reset role; select essai.personne();
update auth.users set encrypted_password = crypt('le-sien-encore', gen_salt('bf')) where id = :MEMBRE::uuid;
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select public.rh_activer_compte();
select essai.egal(public.rh_moi(), :'e_membre'::uuid, 'son mot de passe choisi, il retrouve sa fiche');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('26. Les livreurs, et le blocage');
\set LIV_BLOC '''a0a0a0a0-0011-4000-8000-000000000011'''
insert into auth.users (id, email) values (:LIV_BLOC::uuid, 'livreur.bloc@essai.bj') on conflict do nothing;
insert into public.profils (id, email, role, actif, nom, tel, boutique_id)
values (:LIV_BLOC::uuid, 'livreur.bloc@essai.bj', 'livreur', true, 'Dossou', '0197000011', 'bou_informatique')
on conflict (id) do update set role = 'livreur', actif = true, nom = 'Dossou', boutique_id = 'bou_informatique';
insert into public.positions_livreurs (profil_id, latitude, longitude, adresse)
values (:LIV_BLOC::uuid, 6.36, 2.41, 'Akpakpa')
on conflict (profil_id) do update set latitude = 6.36, longitude = 2.41;

select essai.devenir(:ACHETEUSE_RH::uuid); set role authenticated;
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_rh_stats","quantite":1}]'::jsonb) ->> 'id' as cmd_bloc \gset
reset role; select essai.personne();
select public.marquer_payee(:'cmd_bloc', 'TRX-RH-BLOC',
  (select coalesce(acompte, total) from public.commandes where id = :'cmd_bloc'), 'feexpay') as p \gset
select essai.verifie(:LIV_BLOC::uuid = any(public.candidats_course(:'cmd_bloc')), 'la course lui est proposée');
select essai.devenir(:CHEF::uuid); set role authenticated;
select public.assigner_livreur(:'cmd_bloc', 'bou_informatique', :LIV_BLOC::uuid) as confiee \gset
-- La boutique ne bloque ni ne débloque son livreur elle-même.
select essai.refuse(format($$update public.profils set courses_bloquees = true where id = %L$$, :LIV_BLOC),
  'une boutique ne pose pas le blocage à la main');
reset role; select essai.personne();

select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.refuse($$select public.rh_livreurs()$$, 'menus fermés : un employé ne voit pas les livreurs');
select essai.refuse(format($$select public.rh_bloquer_livreur(%L, true, 'essai')$$, :LIV_BLOC), 'ni ne bloque personne');
reset role; select essai.personne();

select essai.devenir(:ADMRH::uuid); set role authenticated;
select x as liv_liste from jsonb_array_elements(public.rh_livreurs(current_date - 1, current_date + 1) -> 'livreurs') x
 where x ->> 'id' = :LIV_BLOC \gset
select essai.refuse(format($$select public.rh_bloquer_livreur(%L, true, '')$$, :LIV_BLOC), 'bloquer demande un motif');
select public.rh_bloquer_livreur(:LIV_BLOC::uuid, true, 'Retards répétés') as bloc \gset
select essai.refuse(format($$select public.rh_bloquer_livreur(%L, true, 'encore')$$, :LIV_BLOC), 'on ne bloque pas deux fois');
select public.rh_livreur_fiche(:LIV_BLOC::uuid, current_date - 1, current_date + 1) as liv_fiche \gset
reset role; select essai.personne();
select essai.egal((:'liv_liste'::jsonb ->> 'courses')::int, 1, 'la liste compte sa course de la période');
select essai.egal((:'liv_liste'::jsonb ->> 'gains') is not null, true, 'l''administration voit ses gains');
select essai.egal((:'bloc'::jsonb ->> 'liberees')::int, 1, 'bloqué, sa course pas encore partie est retirée');
select essai.egal((select count(*)::int from public.commande_lignes where commande_id = :'cmd_bloc' and livreur_id is not null), 0,
  'et repart vers la boutique, sans livreur');
select essai.egal((:'liv_fiche'::jsonb #>> '{livreur,bloque}')::boolean, true, 'sa fiche le dit bloqué');
select essai.egal(:'liv_fiche'::jsonb #>> '{blocages,0,motif}', 'Retards répétés', 'avec le motif');
select essai.egal(:'liv_fiche'::jsonb #>> '{blocages,0,par}', 'Rita HOUNKPE', 'et son auteur');
select essai.verifie(not (:LIV_BLOC::uuid = any(public.candidats_course(:'cmd_bloc'))), 'aucune demande ne lui est plus proposée');
select essai.verifie(exists (select 1 from public.notifications where destinataire = :LIV_BLOC::uuid and type = 'livreur_bloque'),
  'il est prévenu');

select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse(format($$select public.assigner_livreur(%L, 'bou_informatique', %L)$$, :'cmd_bloc', :LIV_BLOC),
  'la boutique ne peut plus lui confier de course');
reset role; select essai.personne();
select essai.devenir(:LIV_BLOC::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.courses_proposees()), 0, 'il ne voit plus aucune demande');
select essai.refuse(format($$select public.prendre_course(%L)$$, :'cmd_bloc'), 'et n''en prend aucune');
reset role; select essai.personne();

select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_livreur_fiche(%L)$$, :LIV_BLOC), 'un employé sans accès ne lit pas sa fiche');
reset role; select essai.personne();
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_regler_acces(:'p_mkt', '{"livreurs":"membres"}');
reset role; select essai.personne();
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select public.rh_livreur_fiche(:LIV_BLOC::uuid) as fiche_membre \gset
select essai.refuse(format($$select public.rh_bloquer_livreur(%L, false, '')$$, :LIV_BLOC), 'qui localise les livreurs ne les débloque pas');
reset role; select essai.personne();
select essai.egal(:'fiche_membre'::jsonb #> '{chiffres,gains}', 'null'::jsonb, 'ouvert à son profil, il lit la fiche sans les montants');

select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_regler_acces(:'p_mkt', '{"livreurs":"ferme"}');
select public.rh_bloquer_livreur(:LIV_BLOC::uuid, false, '');
reset role; select essai.personne();
select essai.verifie(:LIV_BLOC::uuid = any(public.candidats_course(:'cmd_bloc')), 'débloqué, les demandes lui reviennent');
select essai.egal((select count(*)::int from public.livreurs_blocages where profil_id = :LIV_BLOC::uuid), 2,
  'le blocage et le déblocage restent dans l''historique');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.verifie(public.assigner_livreur(:'cmd_bloc', 'bou_informatique', :LIV_BLOC::uuid) > 0,
  'et la boutique peut de nouveau lui confier la course');
reset role; select essai.personne();
delete from auth.users where id = :LIV_BLOC::uuid;

-- ---------------------------------------------------------
select essai.titre('La sortie d''un employé');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_sortie_employe(%L, current_date)$$, :'ceo'),
  'le CEO ne se fait pas sortir lui-même');
select public.rh_sortie_employe(:'e_resp', '2026-10-20', 'Démission');
select essai.egal((select responsable_id from public.rh_profils where id = :'p_mkt'), null::uuid,
  'sorti, il ne dirige plus son profil');
reset role; select essai.personne();
select essai.devenir(:RESP::uuid); set role authenticated;
select essai.egal((public.rh_tableau_de_bord() -> 'moi'), 'null'::jsonb, 'sorti, il n''a plus accès');
reset role; select essai.personne();
