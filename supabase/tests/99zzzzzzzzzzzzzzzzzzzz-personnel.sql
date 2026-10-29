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
--  27. les contrôles : chaque changement d'un réglage sensible (paiement,
--      code MoMoPay, numéros de réception) est gardé et attend l'approbation
--      du CEO, sans jamais bloquer le réglage ; les encaissements qui
--      attendent, par livreur, montants à l'administration seulement ; la
--      veille des livreurs (course sans livreur, livreur muet) ; l'historique
--      s'écrit sur le vrai chemin (rôle authenticated), la pastille compte
--      les livrés sans déclaration, les écarts sont ceux de la période.
--  28. l'argent : les paiements à rapprocher (client débité, conflit, « j'ai
--      payé » sans suite, confirmé à la main) et la note de qui les traite ;
--      ce que BIZZOO doit payer, réel et ancienneté ; les remboursements dus
--      après annulation, qui a annulé, le retard, jamais plus que le dû ; le
--      journal des gestes d'Admin (CEO, « audit », pas l'administration
--      d'office) ; les codes promo et leurs abus, numéros masqués ; aucun
--      montant hors de l'administration. Corrections : une commande payée
--      puis annulée n'est pas un « client débité », « inconnu » suit la
--      dernière réponse ; la clé « audit » se règle par le CEO et n'ouvre
--      jamais le journal à l'administration ; un profil « audit » lit les
--      libellés sans chiffres ; les vrais libellés d'Admin (prix en FCFA,
--      connexion) ; l'« à venir » des livreurs est celui de leur solde.
--  29. la qualité : les réclamations rangées (la boutique doit répondre, le
--      client lit, BIZZOO tranche), les alertes « sans réponse » et
--      « escalade en attente », le délai de réponse et la chute de la note ;
--      la fiche qualité des boutiques, feu compris, ventes à l'administration
--      seule ; la santé du catalogue et « boutique appelée » ; les files
--      d'attente d'Admin, sans aucun nom ; le service par zone, sans montant ;
--      la fidélité (cohortes, perdus, comptes supprimés), la liste à relancer
--      à l'administration seule, numéros masqués ; les seuils dans leurs bornes ;
--      les zones comptent TOUTES les commandes (plus de 3 000 aussi), le
--      journal se lit par commande (son index), et une cohorte n'a de taux de
--      rachat que pour un mois terminé, jamais pour le mois en cours.
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
select essai.titre('27. Les contrôles : réglages sensibles, encaissements, veille des livreurs');
-- Tout le décor de cette section s'annule à la fin : le paiement, les
-- réglages et les commandes d'essai redeviennent ce qu'ils étaient.
begin;
\set LIV_CTRL '''a0a0a0a0-0013-4000-8000-000000000013'''
insert into auth.users (id, email) values (:LIV_CTRL::uuid, 'livreur.ctrl@essai.bj') on conflict do nothing;
insert into public.profils (id, email, role, actif, nom, tel, boutique_id)
values (:LIV_CTRL::uuid, 'livreur.ctrl@essai.bj', 'livreur', true, 'Kpodo', '0197000013', 'bou_informatique')
on conflict (id) do update set role = 'livreur', actif = true, nom = 'Kpodo', boutique_id = 'bou_informatique';
-- Son numéro, posé comme le ferait sa fiche (déclencheurs coupés le temps de cette écriture du décor).
set session_replication_role = replica;
update public.profils set tel = '0197000013' where id = :LIV_CTRL::uuid;
set session_replication_role = origin;

-- Les droits : un employé sans accès, un compte de boutique.
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.egal(public.rh_controles_compteurs() -> 'acces', 'null'::jsonb, 'menu fermé : un employé n''a pas les contrôles');
select essai.refuse($$select public.rh_audit_reglages_liste()$$, 'ni l''historique des réglages');
select essai.refuse($$select public.rh_encaissements()$$, 'ni les encaissements');
select essai.refuse($$select public.rh_audit_approuver(array[1::bigint])$$, 'ni n''approuve');
select essai.refuse($$select public.rh_controles_regler(1, 1, 1)$$, 'ni ne règle les seuils');
select essai.refuse($$select public.rh_suivi_regler_veille(30, 15)$$, 'ni la veille des livreurs');
select essai.refuse($$select * from public.rh_audit_reglages$$, 'la table de l''historique ne se lit pas');
reset role; select essai.personne();
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse($$select public.rh_encaissements()$$, 'un compte de boutique non plus');
select essai.refuse($$insert into public.rh_audit_reglages (table_nom, champ) values ('paiement', 'faux')$$,
  'personne n''écrit dans l''historique à la main');
reset role; select essai.personne();

-- 1. Un réglage sensible change : le superadministrateur passe le paiement
--    en mode essai et change le code MoMoPay.
--    COMME EN PRODUCTION : BIZZOO Admin écrit « paiement » en rôle
--    authenticated (PATCH paiement?id=eq.1), et une boutique règle son
--    numéro par regler_reception. L'historique est fermé à authenticated :
--    seul le mode SECURITY DEFINER du déclencheur permet d'y écrire. En
--    superutilisateur, l'essai passerait même si ce mode se perdait, et le
--    déclencheur avalerait l'erreur sans bruit.
update public.boutiques_reception set tel = '0100000000' where boutique_id = 'bou_informatique';
update public.rh_audit_reglages set approuve_le = now() where approuve_le is null;
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.paiement set bac_a_sable = not bac_a_sable, momopay_code = '0161234567', maj_le = now() where id = 1;
reset role; select essai.personne();
update public.reglages set compte_obligatoire = not compte_obligatoire, maj_le = now() where id = 1;
select essai.devenir(:CHEF::uuid); set role authenticated;
select public.regler_reception('bou_informatique', '0197123456', 'MTN', 'Essai Chef') as reception \gset
reset role; select essai.personne();
select essai.egal((select momopay_code from public.paiement where id = 1), '0161234567',
  'le superadministrateur a bien changé le paiement, en rôle authenticated');
select essai.egal((select count(*)::int from public.rh_audit_reglages
                    where approuve_le is null and table_nom = 'paiement' and champ in ('bac_a_sable', 'momopay_code')
                      and par_compte = :ENSEIGNE::uuid and par_nom <> '' and par_nom not like 'Système%'), 2,
  'chaque champ changé est gardé, avec son auteur (écrit en rôle authenticated)');
select essai.verifie(exists (select 1 from public.rh_audit_reglages where table_nom = 'boutiques_reception'
                              and cible = 'bou_informatique' and champ = 'tel' and apres = '0197123456'
                              and par_compte = :CHEF::uuid and approuve_le is null),
  'le numéro réglé par l''administrateur de la boutique est gardé, à son nom');
select essai.verifie((select p.prosecdef from pg_proc p where p.oid = 'public.rh_audit_reglages_noter()'::regprocedure),
  'le déclencheur reste SECURITY DEFINER');
select essai.verifie(not exists (select 1 from public.rh_audit_reglages where champ = 'maj_le'),
  'la date de mise à jour seule ne compte pas');
select essai.verifie(exists (select 1 from public.rh_audit_reglages where table_nom = 'paiement' and champ = 'momopay_code'
                              and apres = '0161234567' and critique), 'le code MoMoPay : valeur d''avant et d''après, critique');
select essai.verifie(exists (select 1 from public.rh_audit_reglages where table_nom = 'reglages' and champ = 'compte_obligatoire'
                              and par_compte is null and par_nom like 'Système%'), 'un changement sans compte : « Système »');
select essai.verifie(exists (select 1 from public.rh_audit_reglages where table_nom = 'boutiques_reception'
                              and cible = 'bou_informatique' and champ = 'tel'), 'le numéro de réception d''une boutique aussi');

-- Le déclencheur avale ses erreurs : un historique impossible n'empêche
-- pas le réglage.
select taux_livreur as tl_avant from public.paiement where id = 1 \gset
alter table public.rh_audit_reglages add constraint essai_historique_impossible check (false) not valid;
update public.paiement set taux_livreur = taux_livreur + 1 where id = 1;
alter table public.rh_audit_reglages drop constraint essai_historique_impossible;
select essai.verifie(not exists (select 1 from public.rh_audit_reglages where champ = 'taux_livreur'),
  'l''historique a échoué en silence…');
select essai.egal((select taux_livreur from public.paiement where id = 1), :'tl_avant'::int + 1,
  '… et le réglage est passé quand même');

-- La table est figée.
select essai.refuse($$delete from public.rh_audit_reglages$$, 'l''historique ne s''efface pas');
select essai.refuse($$update public.rh_audit_reglages set apres = 'autre' where champ = 'momopay_code'$$,
  'ni ne se réécrit');

-- L'administration lit ; le CEO et le superadministrateur approuvent.
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_audit_reglages_liste(true) as audit_adm \gset
select public.rh_controles_compteurs() as compteurs_adm \gset
select (select array_agg((x ->> 'id')::bigint) from jsonb_array_elements(:'audit_adm'::jsonb -> 'changements') x) as ids_audit \gset
select essai.refuse(format($$select public.rh_audit_approuver(%L::bigint[])$$, :'ids_audit'),
  'l''administration n''approuve pas : elle lit');
reset role; select essai.personne();
select essai.egal((:'audit_adm'::jsonb ->> 'approuver')::boolean, false, 'l''écran le lui dit');
select essai.verifie((:'audit_adm'::jsonb ->> 'a_approuver')::int >= 6, 'les changements attendent leur approbation');
select essai.egal((select x ->> 'apres' from jsonb_array_elements(:'audit_adm'::jsonb -> 'changements') x
                    where x ->> 'champ' = 'momopay_code'), '016…67', 'le code MoMoPay sort tronqué');
select essai.egal((select x ->> 'apres' from jsonb_array_elements(:'audit_adm'::jsonb -> 'changements') x
                    where x ->> 'champ' = 'tel'), '019…56', 'le numéro de réception aussi');
select essai.verifie(not (:'audit_adm'::jsonb::text like '%0161234567%') and not (:'audit_adm'::jsonb::text like '%0197123456%'),
  'aucune valeur entière ne sort');
select essai.verifie((select x ->> 'libelle' from jsonb_array_elements(:'audit_adm'::jsonb -> 'changements') x
                       where x ->> 'champ' = 'bac_a_sable') like 'Paiement passé en %', 'chaque changement dit ce qu''il veut dire');
select essai.verifie((:'compteurs_adm'::jsonb ->> 'reglages_a_approuver')::int >= 6
  and (:'compteurs_adm'::jsonb #>> '{dernier,critique}')::boolean, 'l''alerte rouge de l''accueil et du menu');

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select public.rh_audit_approuver(:'ids_audit'::bigint[]) as approuves \gset
select essai.refuse(format($$select public.rh_audit_approuver(%L::bigint[])$$, :'ids_audit'), 'on n''approuve pas deux fois');
select public.rh_controles_compteurs() as compteurs_ceo \gset
reset role; select essai.personne();
select essai.verifie(:'approuves'::int >= 6, 'le CEO dit « vu et approuvé »');
select essai.egal((:'compteurs_ceo'::jsonb ->> 'reglages_a_approuver')::int, 0, 'l''alerte s''éteint');
select essai.verifie(not exists (select 1 from public.rh_audit_reglages where id = any(:'ids_audit'::bigint[]) and approuve_nom = ''),
  'chaque approbation garde son auteur');
select essai.refuse($$update public.rh_audit_reglages set approuve_le = null where champ = 'momopay_code'$$,
  'une approbation ne se retire pas');

-- 2. Les encaissements à la livraison : un MoMoPay pas vérifié depuis
--    60 h, des espèces pas rendues depuis 30 h avec un écart.
select essai.devenir(:ACHETEUSE_RH::uuid); set role authenticated;
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_rh_stats","quantite":1}]'::jsonb) ->> 'id' as cmd_enc1 \gset
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_rh_stats","quantite":1}]'::jsonb) ->> 'id' as cmd_enc2 \gset
reset role; select essai.personne();
select public.marquer_payee(:'cmd_enc1', 'TRX-RH-CTRL1', (select coalesce(acompte, total) from public.commandes where id = :'cmd_enc1'), 'feexpay') as p \gset
select public.marquer_payee(:'cmd_enc2', 'TRX-RH-CTRL2', (select coalesce(acompte, total) from public.commandes where id = :'cmd_enc2'), 'feexpay') as p \gset
insert into public.encaissements (commande_id, boutique_id, livreur_id, du, montant, mode, motif, transaction_id, encaisse_le)
values (:'cmd_enc1', 'bou_informatique', :LIV_CTRL::uuid, 5000, 5000, 'mobile_money', 'MoMoPay — transaction CTRL1', 'CTRL1', now() - interval '60 hours'),
       (:'cmd_enc2', 'bou_informatique', :LIV_CTRL::uuid, 3000, 2000, 'especes', 'Le client n''avait pas tout', '', now() - interval '30 hours');

select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_controles_regler(48, 24, 2);
select essai.refuse($$select public.rh_controles_regler(0, 24, 2)$$, 'un délai hors bornes est refusé');
-- Trois jours en arrière : les espèces datent de 30 h ; passé minuit, une
-- période qui commence hier ne les contiendrait plus (écart de la période).
select public.rh_encaissements(current_date - 3, current_date + 1) as enc_adm \gset
select x as enc_liv_adm from jsonb_array_elements(:'enc_adm'::jsonb -> 'livreurs') x where x ->> 'id' = :LIV_CTRL \gset
select public.rh_suivi_commande(:'cmd_enc1') as suivi_enc1 \gset
select public.rh_suivi_commande(:'cmd_enc2') as suivi_enc2 \gset
reset role; select essai.personne();
select essai.egal((:'enc_liv_adm'::jsonb ->> 'en_attente')::int, 2, 'par livreur : ses deux encaissements en attente');
select essai.egal((:'enc_liv_adm'::jsonb ->> 'anciens')::int, 2, 'tous deux au-delà des seuils (48 h MoMoPay, 24 h espèces)');
select essai.egal((:'enc_liv_adm'::jsonb ->> 'ecarts')::int, 1, 'et son écart entre le dû et le déclaré');
select essai.egal((:'enc_liv_adm'::jsonb ->> 'au_plafond')::boolean, true, 'le plafond (2) est atteint : il est signalé');
select essai.egal((:'enc_liv_adm'::jsonb ->> 'montant')::int, 7000, 'l''administration voit le montant en attente');
select essai.verifie((:'enc_adm'::jsonb #>> '{totaux,momopay_anciens}')::int >= 1
  and (:'enc_adm'::jsonb #>> '{totaux,especes_anciennes}')::int >= 1, 'les totaux comptent les anciens');
select essai.verifie(exists (select 1 from jsonb_array_elements(:'enc_adm'::jsonb -> 'lignes') x
                              where x ->> 'commande' = :'cmd_enc1' and x ->> 'statut' = 'momopay_a_verifier'
                                and (x ->> 'heures')::int >= 59 and x ->> 'transaction' = 'CTRL1'),
  'ligne par ligne : MoMoPay à vérifier, son ancienneté et sa transaction');
select essai.verifie((:'suivi_enc1'::jsonb -> 'alertes') ? 'momopay_non_verifie', 'le suivi lève « MoMoPay pas vérifié »');
select essai.verifie((:'suivi_enc2'::jsonb -> 'alertes') ? 'encaissement_ecart', 'et « écart d''encaissement »');

-- La logistique : Paramètres ouvre « controles » au profil, sans montants.
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_regler_acces(:'p_mkt', '{"controles":"membres"}');
reset role; select essai.personne();
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select public.rh_controles_compteurs() as compteurs_log \gset
select public.rh_encaissements(current_date - 1, current_date + 1) as enc_log \gset
select essai.verifie('controles' = any(public.rh_mes_menus()), 'le menu lui est ouvert');
select essai.refuse($$select public.rh_audit_reglages_liste()$$, 'mais pas l''historique des réglages');
select essai.refuse($$select public.rh_controles_regler(48, 24, 3)$$, 'ni les seuils');
reset role; select essai.personne();
select essai.egal(:'compteurs_log'::jsonb ->> 'acces', 'logistique', 'il entre dans la version sans montants');
select essai.verifie(:'compteurs_log'::jsonb -> 'reglages_a_approuver' = 'null'::jsonb
  and :'compteurs_log'::jsonb -> 'dernier' = 'null'::jsonb, 'sans rien des réglages sensibles');
select essai.verifie((:'compteurs_log'::jsonb ->> 'encaissements_anciens')::int >= 2, 'il voit combien attendent trop');
select essai.egal((:'enc_log'::jsonb ->> 'montants')::boolean, false, 'l''écran sait qu''il n''a pas les montants');
select essai.verifie(not (:'enc_log'::jsonb::text ~ '"(du|montant|transaction|montant_a_verifier|montant_especes|montant_non_declare|ecart_total)"'),
  'aucun montant ni numéro de transaction');
select essai.egal((select (x ->> 'anciens')::int from jsonb_array_elements(:'enc_log'::jsonb -> 'livreurs') x
                    where x ->> 'id' = :LIV_CTRL), 2, 'mais les nombres et l''ancienneté, oui');

-- Les écarts sont ceux de la période : des espèces pas rendues d'il y a
-- 10 jours, avec un écart, attendent toujours (elles comptent dans ce qui
-- attend) mais ne gonflent pas les écarts de ces trois jours-ci (trois, pas
-- deux : passé minuit, l'écart de 30 h sortirait d'une période « depuis hier »).
select essai.devenir(:ACHETEUSE_RH::uuid); set role authenticated;
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_rh_stats","quantite":1}]'::jsonb) ->> 'id' as cmd_enc3 \gset
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_rh_stats","quantite":1}]'::jsonb) ->> 'id' as cmd_nd \gset
reset role; select essai.personne();
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_encaissements(current_date - 2, current_date + 1) as enc_base \gset
reset role; select essai.personne();
select public.marquer_payee(:'cmd_enc3', 'TRX-RH-CTRL3', (select coalesce(acompte, total) from public.commandes where id = :'cmd_enc3'), 'feexpay') as p \gset
select public.marquer_payee(:'cmd_nd', 'TRX-RH-CTRLND', (select coalesce(acompte, total) from public.commandes where id = :'cmd_nd'), 'feexpay') as p \gset
insert into public.encaissements (commande_id, boutique_id, livreur_id, du, montant, mode, motif, transaction_id, encaisse_le)
values (:'cmd_enc3', 'bou_informatique', :LIV_CTRL::uuid, 4000, 1000, 'especes', 'Ancien écart', '', now() - interval '10 days');
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_controles_compteurs() as cpt_avant_nd \gset
select public.rh_encaissements(current_date - 2, current_date + 1) as enc_per \gset
select public.rh_encaissements(current_date - 15, current_date + 1) as enc_15j \gset
reset role; select essai.personne();
select essai.egal((:'enc_per'::jsonb #>> '{totaux,ecarts}')::int, (:'enc_base'::jsonb #>> '{totaux,ecarts}')::int, 'un écart d''il y a 10 jours n''entre pas dans les écarts des 3 derniers jours');
select essai.egal((select (x ->> 'ecarts')::int from jsonb_array_elements(:'enc_per'::jsonb -> 'livreurs') x
                    where x ->> 'id' = :LIV_CTRL), 1, 'ni dans ceux du livreur');
select essai.egal((select (x ->> 'en_attente')::int from jsonb_array_elements(:'enc_per'::jsonb -> 'livreurs') x
                    where x ->> 'id' = :LIV_CTRL), 3, 'mais il attend toujours : il reste dans ce qui attend');
select essai.egal((:'enc_per'::jsonb #>> '{totaux,ecart_total}')::int, (:'enc_base'::jsonb #>> '{totaux,ecart_total}')::int, 'le total des écarts reste celui de la période');
select essai.egal((select (x ->> 'ecarts')::int from jsonb_array_elements(:'enc_15j'::jsonb -> 'livreurs') x
                    where x ->> 'id' = :LIV_CTRL), 2, 'sur 15 jours, il y entre');

-- La pastille compte aussi les livrés sans déclaration, comme l'écran :
-- une livraison remise alors qu'un reste était dû, sans rien déclarer.
set session_replication_role = replica;
update public.commandes set verse = 0, parts = null where id = :'cmd_nd';
update public.commande_lignes set etat = 'remise', livreur_id = :LIV_CTRL::uuid where commande_id = :'cmd_nd';
set session_replication_role = origin;
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_controles_compteurs() as cpt_apres_nd \gset
select public.rh_encaissements(current_date - 1, current_date + 1) as enc_nd \gset
reset role; select essai.personne();
select essai.verifie(exists (select 1 from jsonb_array_elements(:'enc_nd'::jsonb -> 'lignes') x
                              where x ->> 'commande' = :'cmd_nd' and x ->> 'statut' = 'non_declare' and (x ->> 'ancien')::boolean),
  'l''écran la classe « livré sans déclaration », ancienne');
select essai.egal((:'cpt_apres_nd'::jsonb ->> 'encaissements_anciens')::int - (:'cpt_avant_nd'::jsonb ->> 'encaissements_anciens')::int, 1,
  'la pastille et l''accueil la comptent aussi');

-- 3. La veille des livreurs : une course payée que personne ne prend, un
--    livreur en route qui ne donne plus de position.
select essai.devenir(:ACHETEUSE_RH::uuid); set role authenticated;
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_rh_stats","quantite":1}]'::jsonb) ->> 'id' as cmd_veille1 \gset
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_rh_stats","quantite":1}]'::jsonb) ->> 'id' as cmd_veille2 \gset
reset role; select essai.personne();
select public.marquer_payee(:'cmd_veille1', 'TRX-RH-VEILLE1', (select coalesce(acompte, total) from public.commandes where id = :'cmd_veille1'), 'feexpay') as p \gset
select public.marquer_payee(:'cmd_veille2', 'TRX-RH-VEILLE2', (select coalesce(acompte, total) from public.commandes where id = :'cmd_veille2'), 'feexpay') as p \gset
insert into public.positions_livreurs (profil_id, latitude, longitude, adresse)
values (:LIV_CTRL::uuid, 6.36, 2.41, 'Akpakpa')
on conflict (profil_id) do update set latitude = 6.36, longitude = 2.41;
select essai.devenir(:CHEF::uuid); set role authenticated;
select public.assigner_livreur(:'cmd_veille2', 'bou_informatique', :LIV_CTRL::uuid) as confiee \gset
reset role; select essai.personne();
-- Le décor daté, déclencheurs coupés le temps de ces écritures : payées
-- il y a 2 h ; la seconde en route depuis 1 h, dernière position il y a 40 min.
set session_replication_role = replica;
update public.commandes set paye_le = now() - interval '2 hours' where id in (:'cmd_veille1', :'cmd_veille2');
update public.commande_lignes set etat = 'en_livraison', recu_le = now() - interval '1 hour' where commande_id = :'cmd_veille2';
set session_replication_role = origin;
update public.positions_livreurs set enregistre_le = now() - interval '40 minutes' where profil_id = :LIV_CTRL::uuid;

select essai.devenir(:RESP::uuid); set role authenticated;
select essai.refuse($$select public.rh_suivi_regler_veille(30, 15)$$, 'le responsable du suivi ne règle pas la veille');
reset role; select essai.personne();
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.refuse($$select public.rh_suivi_regler_veille(2, 15)$$, 'une veille hors bornes est refusée');
select public.rh_suivi_regler_veille(30, 15);
select public.rh_suivi(current_date, current_date) -> 'reglages' as reglages_veille \gset
select public.rh_suivi_commande(:'cmd_veille1') as veille1 \gset
select public.rh_suivi_commande(:'cmd_veille2') as veille2 \gset
select public.rh_suivi_alertes_nb() as nb_muet \gset
select x as carte_muet from jsonb_array_elements(public.rh_localiser_livreurs() -> 'livreurs') x where x ->> 'id' = :LIV_CTRL \gset
reset role; select essai.personne();
select essai.egal((:'reglages_veille'::jsonb ->> 'prise_course_min')::int, 30, 'les seuils de la veille vivent avec ceux du suivi');
select essai.verifie((:'veille1'::jsonb -> 'alertes') ? 'course_sans_livreur', 'payée depuis 2 h, sans livreur : « course sans livreur »');
select essai.egal(:'veille2'::jsonb -> 'alertes', '["livreur_muet"]'::jsonb, 'en route, sans position depuis 40 min : « livreur muet »');
select essai.egal((:'carte_muet'::jsonb ->> 'muet')::boolean, true, 'sur la carte, il est muet (en orange)');
select essai.egal(:'carte_muet'::jsonb ->> 'tel', '0197000013', 'avec son numéro, pour l''appeler');

-- Il redonne signe de vie : l'alerte tombe, la pastille du suivi aussi.
update public.positions_livreurs set enregistre_le = now() where profil_id = :LIV_CTRL::uuid;
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_suivi_commande(:'cmd_veille2') as veille2b \gset
select public.rh_suivi_alertes_nb() as nb_parle \gset
select x as carte_parle from jsonb_array_elements(public.rh_localiser_livreurs() -> 'livreurs') x where x ->> 'id' = :LIV_CTRL \gset
reset role; select essai.personne();
select essai.egal(:'veille2b'::jsonb -> 'alertes', '[]'::jsonb, 'une position fraîche : plus d''alerte');
select essai.egal(:'nb_muet'::int - :'nb_parle'::int, 1, 'la pastille du suivi la comptait');
select essai.egal((:'carte_parle'::jsonb ->> 'muet')::boolean, false, 'et la carte ne le dit plus muet');
select essai.verifie(not (:'carte_muet'::jsonb::text ~ '"(total|prix|montant|frais)"'), 'la carte reste sans montant');
rollback;

-- ---------------------------------------------------------
select essai.titre('28. L''argent : paiements à rapprocher, à payer, remboursements, gestes Admin, codes promo');
-- Tout le décor de cette section s'annule à la fin.
begin;
\set LIV_ARG  '''a0a0a0a0-0014-4000-8000-000000000014'''
\set PARRAIN  '''a0a0a0a0-0015-4000-8000-000000000015'''
insert into auth.users (id, email) values (:LIV_ARG::uuid, 'livreur.argent@essai.bj'), (:PARRAIN::uuid, 'parrain@essai.bj')
on conflict do nothing;
insert into public.profils (id, email, role, actif, nom, tel)
values (:LIV_ARG::uuid, 'livreur.argent@essai.bj', 'livreur', true, 'Dossou', '0197000014')
on conflict (id) do update set role = 'livreur', actif = true, nom = 'Dossou';
insert into public.clients (id, nom, tel) values (:PARRAIN::uuid, 'Parrain Essai', '0197112233')
on conflict (id) do update set nom = 'Parrain Essai', tel = '0197112233';
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_rh_argent', 'bou_informatique', 'Clavier', 10000, 'sc_hightech_accessoires', 100, true)
on conflict (id) do update set stock = 100, disponible = true;
insert into public.produits_prive (produit_id, prix_grossiste) values ('prod_rh_argent', 8000)
on conflict (produit_id) do update set prix_grossiste = 8000;

-- Les droits : un employé sans accès, un compte de boutique, un visiteur.
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select public.rh_argent_compteurs() as arg_ferme \gset
select essai.refuse($$select public.rh_paiements()$$, 'un employé sans accès ne lit pas les paiements à rapprocher');
select essai.refuse($$select public.rh_rapprocher('x', 'regle', 'essai')$$, 'ni n''y note rien');
select essai.refuse($$select public.rh_dettes()$$, 'ni ce que BIZZOO doit payer');
select essai.refuse($$select public.rh_remboursements_liste()$$, 'ni les remboursements');
select essai.refuse($$select public.rh_rembourser('x', 1, 'especes')$$, 'ni n''en note');
select essai.refuse($$select public.rh_gestes()$$, 'ni le journal des gestes');
select essai.refuse($$select public.rh_codes_surveillance()$$, 'ni les codes promo');
select essai.refuse($$select public.rh_argent_regler(30, 5, 7)$$, 'ni ne règle les seuils');
select essai.refuse($$select * from public.rh_rapprochements$$, 'la table des rapprochements ne se lit pas');
select essai.refuse($$select * from public.rh_remboursements$$, 'ni celle des remboursements');
select essai.refuse($$select * from public.rh_annulations$$, 'ni celle des annulations');
select essai.refuse($$select public.rh_rembourse_du('x')$$, 'le calcul du dû n''est pas appelable à la main');
reset role; select essai.personne();
select essai.verifie(:'arg_ferme'::jsonb #> '{onglets,paiements}' = 'null'::jsonb
  and :'arg_ferme'::jsonb #> '{onglets,dettes}' = 'null'::jsonb
  and :'arg_ferme'::jsonb #> '{onglets,codes}' = 'null'::jsonb
  and (:'arg_ferme'::jsonb #>> '{onglets,gestes}')::boolean = false
  and not (:'arg_ferme'::jsonb ? 'paiements_a_traiter'), 'ses compteurs n''ouvrent aucun onglet d''argent');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse($$select public.rh_paiements()$$, 'un compte de boutique non plus');
select essai.refuse($$select public.rh_gestes()$$, 'ni le journal des gestes');
reset role; select essai.personne();
set role anon;
select essai.refuse($$select public.rh_paiements()$$, 'un visiteur n''appelle rien');
reset role;

-- 1. Les paiements à rapprocher.
select essai.devenir(:ACHETEUSE_RH::uuid); set role authenticated;
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_rh_argent","quantite":1}]'::jsonb) ->> 'id' as cmd_deb \gset
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_rh_argent","quantite":1}]'::jsonb) ->> 'id' as cmd_conf \gset
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_rh_argent","quantite":1}]'::jsonb) ->> 'id' as cmd_annonce \gset
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_rh_argent","quantite":1}]'::jsonb) ->> 'id' as cmd_main \gset
reset role; select essai.personne();
-- L'agrégateur a dit « payé » mais la commande est restée « à payer » ; un
-- versement en conflit ; un « j'ai payé » sans suite depuis 2 h ; une
-- commande confirmée à la main par le superadministrateur.
insert into public.versements (commande_id, numero, fournisseur, reseau, transaction_id, attendu, recu, verdict, detail)
select c.id, c.numero, 'feexpay', 'MOOV', 'TRX-RH-DEB', c.total, c.total, 'payee', 'réponse tardive' from public.commandes c where c.id = :'cmd_deb'
union all
select c.id, c.numero, 'feexpay', 'MTN', 'TRX-RH-CONF', c.total, c.total - 1000, 'conflit', 'montant différent' from public.commandes c where c.id = :'cmd_conf';
select public.marquer_payee(:'cmd_main', 'TRX-RH-MAIN', (select coalesce(acompte, total) from public.commandes where id = :'cmd_main'), 'feexpay') as p \gset
set session_replication_role = replica;
update public.commandes set annonce_le = now() - interval '2 hours' where id = :'cmd_annonce';
update public.commandes set confirme_par = 'enseigne@bizzoo.bj' where id = :'cmd_main';
set session_replication_role = origin;

select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_argent_regler(30, 5, 7);
select essai.refuse($$select public.rh_argent_regler(2, 5, 7)$$, 'un seuil hors bornes est refusé');
select public.rh_paiements(current_date - 1, current_date + 1) as pai_adm \gset
select public.rh_argent_compteurs() as arg_adm \gset
reset role; select essai.personne();
select essai.egal((select x ->> 'motif' from jsonb_array_elements(:'pai_adm'::jsonb -> 'lignes') x where x ->> 'commande' = :'cmd_deb'),
  'debite_non_paye', 'l''agrégateur a dit « payé », la commande non : « client débité »');
select essai.egal((select x ->> 'motif' from jsonb_array_elements(:'pai_adm'::jsonb -> 'lignes') x where x ->> 'commande' = :'cmd_conf'),
  'conflit', 'le versement en conflit');
select essai.egal((select x ->> 'motif' from jsonb_array_elements(:'pai_adm'::jsonb -> 'lignes') x where x ->> 'commande' = :'cmd_annonce'),
  'annonce_sans_preuve', '« j''ai payé » sans suite depuis 2 h');
select essai.egal((select (x ->> 'a_traiter')::boolean from jsonb_array_elements(:'pai_adm'::jsonb -> 'lignes') x
                    where x ->> 'commande' = :'cmd_main' and x ->> 'motif' = 'manuel'), false,
  'la confirmation à la main est listée pour mémoire, sans rien à traiter');
select essai.egal((select x ->> 'confirme_par' from jsonb_array_elements(:'pai_adm'::jsonb -> 'lignes') x where x ->> 'commande' = :'cmd_main'),
  'enseigne@bizzoo.bj', 'avec qui s''en est porté garant');
select essai.verifie((select (x ->> 'recu')::int > 0 and x ->> 'tel' = '97666088' and x ->> 'transactions' = 'TRX-RH-DEB'
                        from jsonb_array_elements(:'pai_adm'::jsonb -> 'lignes') x where x ->> 'commande' = :'cmd_deb'),
  'l''administration voit le montant reçu, la transaction et le numéro entier');
select essai.verifie((:'arg_adm'::jsonb ->> 'paiements_a_traiter')::int >= 3, 'la pastille compte ce qui attend');
select essai.egal(:'arg_adm'::jsonb #>> '{onglets,paiements}', 'admin', 'l''administration a les montants');

-- La relation client : Paramètres ouvre « paiements » au profil, sans montants.
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_regler_acces(:'p_mkt', '{"paiements":"membres"}');
reset role; select essai.personne();
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select public.rh_paiements(current_date - 1, current_date + 1) as pai_sav \gset
select essai.verifie('paiements' = any(public.rh_mes_menus()), 'le menu lui est ouvert');
select essai.refuse(format($$select public.rh_rapprocher(%L, 'regle', 'ok')$$, :'cmd_deb'), 'une note de deux lettres ne dit rien : refusée');
select essai.refuse(format($$select public.rh_rapprocher(%L, 'confirme', 'Client rappelé')$$, :'cmd_deb'), 'un statut inconnu est refusé');
select essai.refuse($$select public.rh_rapprocher('cmd_inexistante', 'regle', 'Client rappelé')$$, 'une commande inconnue aussi');
select public.rh_rapprocher(:'cmd_deb', 'regle', 'Client rappelé : paiement retrouvé chez FeexPay') as note_id \gset
select essai.refuse(format($$select public.rh_rembourser(%L, 1000, 'especes')$$, :'cmd_deb'), 'sans être de l''administration, il ne note aucun remboursement');
select essai.refuse($$select public.rh_argent_regler(30, 5, 7)$$, 'ni les seuils');
reset role; select essai.personne();
select essai.egal((:'pai_sav'::jsonb ->> 'montants')::boolean, false, 'l''écran sait qu''il n''a pas les montants');
select essai.verifie(not (:'pai_sav'::jsonb::text ~ '"(total|attendu|recu|transactions|remarque|detail|montant_a_traiter|montant_manuel)"'),
  'aucun montant, aucune transaction');
select essai.verifie(not (:'pai_sav'::jsonb::text like '%97666088%'), 'pas le numéro entier du client');
select essai.egal((select x ->> 'tel' from jsonb_array_elements(:'pai_sav'::jsonb -> 'lignes') x where x ->> 'commande' = :'cmd_deb'),
  '•••• 6088', 'ses 4 derniers chiffres seulement');
select essai.verifie(exists (select 1 from public.rh_rapprochements where id = :'note_id'::bigint and commande_id = :'cmd_deb'
                              and statut = 'regle' and par = :'e_membre'::uuid and par_nom <> ''),
  'la note garde qui l''a écrite et quand');
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_paiements(current_date - 1, current_date + 1) as pai_apres \gset
select public.rh_argent_compteurs() as arg_apres \gset
reset role; select essai.personne();
select essai.verifie((select not (x ->> 'a_traiter')::boolean and x #>> '{traitement,statut}' = 'regle'
                             and x #>> '{traitement,par}' <> '' and x #>> '{traitement,commentaire}' like 'Client rappelé%'
                        from jsonb_array_elements(:'pai_apres'::jsonb -> 'lignes') x where x ->> 'commande' = :'cmd_deb'),
  'réglé : il ne reste plus à traiter, la note se lit avec son auteur');
select essai.egal((:'arg_adm'::jsonb ->> 'paiements_a_traiter')::int - (:'arg_apres'::jsonb ->> 'paiements_a_traiter')::int, 1,
  'la pastille descend d''un');
select essai.egal((select etat from public.commandes where id = :'cmd_deb'), 'a_payer',
  'la commande n''a pas bougé : la confirmation reste dans Admin');

-- Une commande payée puis annulée n'est pas un « client débité » : son
-- versement dit « payée », mais elle est déjà dans les remboursements. Une
-- réponse « inconnue » que l'agrégateur a ensuite refusée est tranchée ;
-- une réponse restée « inconnue », elle, attend.
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_argent_compteurs() as arg_av_annul \gset
reset role; select essai.personne();
select essai.devenir(:ACHETEUSE_RH::uuid); set role authenticated;
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_rh_argent","quantite":1}]'::jsonb) ->> 'id' as cmd_pa \gset
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_rh_argent","quantite":1}]'::jsonb) ->> 'id' as cmd_refus \gset
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_rh_argent","quantite":1}]'::jsonb) ->> 'id' as cmd_inc \gset
reset role; select essai.personne();
select public.marquer_payee(:'cmd_pa', 'TRX-RH-PA', (select coalesce(acompte, total) from public.commandes where id = :'cmd_pa'), 'feexpay') as p \gset
insert into public.versements (commande_id, numero, fournisseur, reseau, transaction_id, attendu, recu, verdict, detail, cree_le)
select c.id, c.numero, 'feexpay', 'MTN', 'TRX-RH-PA', c.total, c.total, 'payee', 'encaissé', now() - interval '5 minutes'
  from public.commandes c where c.id = :'cmd_pa'
union all
select c.id, c.numero, 'feexpay', 'MTN', 'TRX-RH-REF', c.total, 0, 'inconnue', 'délai dépassé', now() - interval '10 minutes'
  from public.commandes c where c.id = :'cmd_refus'
union all
select c.id, c.numero, 'feexpay', 'MTN', 'TRX-RH-REF', c.total, 0, 'refusee', 'solde insuffisant', now() - interval '2 minutes'
  from public.commandes c where c.id = :'cmd_refus'
union all
select c.id, c.numero, 'feexpay', 'MTN', 'TRX-RH-INC', c.total, 0, 'inconnue', 'délai dépassé', now() - interval '2 minutes'
  from public.commandes c where c.id = :'cmd_inc';
update public.commandes set etat = 'annulee' where id = :'cmd_pa';
select essai.verifie((select etat = 'annulee' and paye_le is not null from public.commandes where id = :'cmd_pa'),
  'le décor : payée, puis annulée (paye_le reste posé)');
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_paiements(current_date - 1, current_date + 1) as pai_annul \gset
select public.rh_argent_compteurs() as arg_ap_annul \gset
reset role; select essai.personne();
select essai.verifie(not exists (select 1 from jsonb_array_elements(:'pai_annul'::jsonb -> 'lignes') x where x ->> 'commande' = :'cmd_pa'),
  'payée puis annulée : pas dans les paiements à rapprocher');
select essai.verifie(not exists (select 1 from jsonb_array_elements(:'pai_annul'::jsonb -> 'lignes') x where x ->> 'commande' = :'cmd_refus'),
  '« inconnue » puis « refusée » : la dernière réponse tranche, rien à rapprocher');
select essai.egal((select x ->> 'motif' from jsonb_array_elements(:'pai_annul'::jsonb -> 'lignes') x where x ->> 'commande' = :'cmd_inc'),
  'inconnu', 'une réponse restée « inconnue » attend');
select essai.egal((:'arg_ap_annul'::jsonb ->> 'paiements_a_traiter')::int - (:'arg_av_annul'::jsonb ->> 'paiements_a_traiter')::int, 1,
  'la pastille ne monte que de celle-là');

-- 2. Les remboursements dus après annulation.
select essai.devenir(:ACHETEUSE_RH::uuid); set role authenticated;
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_rh_stats","quantite":1},{"produit_id":"prod_rh_argent","quantite":1}]'::jsonb) ->> 'id' as cmd_r1 \gset
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_rh_argent","quantite":1}]'::jsonb) ->> 'id' as cmd_r2 \gset
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_rh_argent","quantite":1}]'::jsonb) ->> 'id' as cmd_rien \gset
reset role; select essai.personne();
select public.marquer_payee(:'cmd_r1', 'TRX-RH-R1', (select coalesce(acompte, total) from public.commandes where id = :'cmd_r1'), 'feexpay') as p \gset
select public.marquer_payee(:'cmd_r2', 'TRX-RH-R2', (select coalesce(acompte, total) from public.commandes where id = :'cmd_r2'), 'feexpay') as p \gset
select public.marquer_payee(:'cmd_rien', 'TRX-RH-RIEN', (select coalesce(acompte, total) from public.commandes where id = :'cmd_rien'), 'feexpay') as p \gset
-- Le client a tout payé en ligne, sans frais ni remise : le calcul se lit à l'œil.
set session_replication_role = replica;
update public.commandes c set total = s.t, verse = s.t, acompte = s.t, remise = 0, frais_livraison = 0, parts = null, livraison = null
  from (select l.commande_id, sum(l.prix * l.quantite)::int as t from public.commande_lignes l
         where l.commande_id in (:'cmd_r1', :'cmd_r2', :'cmd_rien') group by l.commande_id) s
 where c.id = s.commande_id;
set session_replication_role = origin;
select prix * quantite as prix_clavier from public.commande_lignes where commande_id = :'cmd_r1' and produit_id = 'prod_rh_argent' \gset
select verse as verse_r2 from public.commandes where id = :'cmd_r2' \gset

-- La boutique annule le clavier, après paiement, depuis son compte.
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'annulee' where commande_id = :'cmd_r1' and produit_id = 'prod_rh_argent';
reset role; select essai.personne();
-- L'enseigne annule une commande entière, hors de tout compte connecté.
update public.commandes set etat = 'annulee' where id = :'cmd_r2';
select essai.verifie(exists (select 1 from public.rh_annulations where commande_id = :'cmd_r1' and ligne_id is not null
                              and apres_paiement and par_compte = :CHEF::uuid and par_nom <> '' and par_nom not like 'Système%'),
  'l''annulation d''un article est notée, avec son auteur, après paiement');
select essai.verifie(exists (select 1 from public.rh_annulations where commande_id = :'cmd_r2' and ligne_id is null
                              and apres_paiement and par_compte is null and par_nom like 'Système%'),
  'celle d''une commande entière aussi ; sans compte : « Système »');

-- Le déclencheur avale ses erreurs : une trace impossible n'empêche pas l'annulation.
alter table public.rh_annulations add constraint essai_trace_impossible check (false) not valid;
update public.commande_lignes set etat = 'annulee' where commande_id = :'cmd_rien';
alter table public.rh_annulations drop constraint essai_trace_impossible;
select essai.verifie(not exists (select 1 from public.rh_annulations where commande_id = :'cmd_rien'), 'la trace a échoué en silence…');
select essai.egal((select etat from public.commande_lignes where commande_id = :'cmd_rien'), 'annulee', '… et l''annulation est passée');
-- Remise en état : cette commande-là reste servie, rien n'est dû.
set session_replication_role = replica;
update public.commande_lignes set etat = 'nouvelle' where commande_id = :'cmd_rien';
set session_replication_role = origin;

select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_remboursements_liste(current_date - 1, current_date + 1) as remb1 \gset
select essai.refuse(format($$select public.rh_rembourser(%L, %s, 'especes')$$, :'cmd_r1', :'prix_clavier'::int + 1),
  'on ne rend pas plus que ce qui est dû');
select essai.refuse(format($$select public.rh_rembourser(%L, 1000, 'mobile_money')$$, :'cmd_r1'),
  'un remboursement Mobile Money sans référence est refusé');
select essai.refuse(format($$select public.rh_rembourser(%L, 0, 'especes')$$, :'cmd_r1'), 'un montant nul aussi');
select essai.refuse(format($$select public.rh_rembourser(%L, 1000, 'cheque')$$, :'cmd_r1'), 'un mode inconnu aussi');
select essai.refuse(format($$select public.rh_rembourser(%L, 1000, 'especes')$$, :'cmd_rien'), 'rien n''est dû sur une commande servie');
reset role; select essai.personne();
select x as r1 from jsonb_array_elements(:'remb1'::jsonb -> 'lignes') x where x ->> 'commande' = :'cmd_r1' \gset
select x as r2 from jsonb_array_elements(:'remb1'::jsonb -> 'lignes') x where x ->> 'commande' = :'cmd_r2' \gset
select essai.egal((:'r1'::jsonb ->> 'du')::int, :'prix_clavier'::int, 'un article annulé après paiement : son prix est dû au client');
select essai.egal(:'r1'::jsonb ->> 'statut', 'a_rembourser', 'il entre seul dans la file');
select essai.verifie(:'r1'::jsonb ->> 'annule_par' <> '' and :'r1'::jsonb ->> 'boutiques' <> '', 'avec qui a annulé, et quelle boutique');
select essai.egal((:'r1'::jsonb ->> 'en_retard')::boolean, false, 'pas encore en retard');
select essai.egal((:'r2'::jsonb ->> 'du')::int, :'verse_r2'::int, 'une commande entière annulée : tout ce qui a été versé');
select essai.verifie(not exists (select 1 from jsonb_array_elements(:'remb1'::jsonb -> 'lignes') x where x ->> 'commande' = :'cmd_rien'),
  'une commande servie n''y est pas');
select essai.verifie(exists (select 1 from jsonb_array_elements(:'remb1'::jsonb -> 'boutiques') x
                              where (x ->> 'lignes')::int >= 1 and (x ->> 'valeur')::int >= :'prix_clavier'::int),
  'la statistique compte la boutique qui annule après paiement');

-- Une semaine plus tard, rien n'est noté : alerte.
update public.rh_annulations set le = now() - interval '10 days' where commande_id = :'cmd_r1';
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_remboursements_liste(current_date - 1, current_date + 1) as remb2 \gset
select public.rh_argent_compteurs() as arg_retard \gset
reset role; select essai.personne();
select essai.egal((select (x ->> 'en_retard')::boolean from jsonb_array_elements(:'remb2'::jsonb -> 'lignes') x
                    where x ->> 'commande' = :'cmd_r1'), true, 'au-delà de 7 jours : en retard');
select essai.verifie((:'arg_retard'::jsonb ->> 'remboursements_en_retard')::int >= 1, 'la pastille le compte');

-- Le SAV voit la file, sans montants ; il ne note pas le remboursement.
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select public.rh_remboursements_liste(current_date - 1, current_date + 1) as remb_sav \gset
reset role; select essai.personne();
select essai.egal((:'remb_sav'::jsonb ->> 'montants')::boolean, false, 'le SAV lit la file sans les montants');
select essai.verifie(not (:'remb_sav'::jsonb::text ~ '"(du|rendu|reste|montant|reference|note|valeur|reste_total|rendu_periode)"'),
  'aucun montant ni référence');
select essai.verifie(exists (select 1 from jsonb_array_elements(:'remb_sav'::jsonb -> 'lignes') x
                              where x ->> 'commande' = :'cmd_r1' and (x ->> 'en_retard')::boolean and x ->> 'tel' = '•••• 6088'),
  'mais le retard, et le numéro masqué');

-- L'administration note le remboursement, en deux fois.
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_rembourser(:'cmd_r1', 4000, 'especes', '', 'Remis au client en boutique') as rb1 \gset
select public.rh_remboursements_liste(current_date - 1, current_date + 1) as remb3 \gset
select public.rh_rembourser(:'cmd_r1', :'prix_clavier'::int - 4000, 'mobile_money', 'MP-REMB-001') as rb2 \gset
select essai.refuse(format($$select public.rh_rembourser(%L, 1, 'especes')$$, :'cmd_r1'), 'tout rendu : plus rien n''est dû');
select public.rh_remboursements_liste(current_date - 1, current_date + 1) as remb4 \gset
reset role; select essai.personne();
select essai.verifie((select x ->> 'statut' = 'partiel' and (x ->> 'reste')::int = :'prix_clavier'::int - 4000
                        from jsonb_array_elements(:'remb3'::jsonb -> 'lignes') x where x ->> 'commande' = :'cmd_r1'),
  'une partie rendue : « partiel », le reste se lit');
select essai.verifie((select x ->> 'statut' = 'rembourse' and (x ->> 'reste')::int = 0 and not (x ->> 'en_retard')::boolean
                             and jsonb_array_length(x -> 'faits') = 2 and x #>> '{faits,1,reference}' = 'MP-REMB-001'
                        from jsonb_array_elements(:'remb4'::jsonb -> 'lignes') x where x ->> 'commande' = :'cmd_r1'),
  'tout rendu : remboursé, l''alerte tombe, les deux gestes gardent leur référence');
select essai.verifie(exists (select 1 from public.rh_remboursements where id = :'rb2'::bigint and par = :'e_admrh'::uuid and par_nom <> ''),
  'chaque remboursement garde son auteur');

-- 3. Ce que BIZZOO doit payer.
insert into public.reversements (boutique_id, montant, tel, reseau, etat, demande_par, demande_le)
values ('bou_informatique', 20000, '0197123456', 'MTN', 'en_attente', 'Chef', now() - interval '8 days');
insert into public.gains_livreurs (commande_id, livreur_id, frais, taux, montant)
values (:'cmd_main', :LIV_ARG::uuid, 3750, 80, 3000);
insert into public.reversements_livreurs (livreur_id, nom_livreur, montant, tel, reseau, etat, demande_le)
values (:LIV_ARG::uuid, 'Dossou', 2000, '0197000014', 'MOOV', 'en_attente', now() - interval '6 days');
insert into public.codes_promo (code, libelle, mode, valeur, actif, parrain, commission)
values ('RHPARRAIN28', 'Code d''un parrain', 'pourcent', 5, true, :PARRAIN::uuid, 10),
       ('RHPROMO28', 'Promotion d''essai', 'pourcent', 10, true, null, 0);
insert into public.gains_parrain (parrain, code, base, taux, montant) values (:PARRAIN::uuid, 'RHPARRAIN28', 15000, 10, 1500);
insert into public.retraits_parrain (parrain, montant, numero, reseau, etat, demande_le)
values (:PARRAIN::uuid, 1000, '0197112233', 'MTN', 'demande', now() - interval '1 day');
-- Une course payée que le livreur a en main, pas encore livrée : sa part
-- des frais est « à venir », comme dans son propre solde.
select essai.devenir(:ACHETEUSE_RH::uuid); set role authenticated;
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_rh_argent","quantite":1}]'::jsonb) ->> 'id' as cmd_course \gset
reset role; select essai.personne();
select public.marquer_payee(:'cmd_course', 'TRX-RH-COURSE', (select coalesce(acompte, total) from public.commandes where id = :'cmd_course'), 'feexpay') as p \gset
set session_replication_role = replica;
update public.commandes set frais_livraison = 1000, livraison = null, parts = null where id = :'cmd_course';
update public.commande_lignes set livreur_id = :LIV_ARG::uuid, etat = 'en_livraison' where commande_id = :'cmd_course';
set session_replication_role = origin;
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select (public.solde_livreur(:LIV_ARG::uuid) ->> 'a_venir')::int as liv_a_venir \gset
reset role; select essai.personne();
select essai.verifie(:'liv_a_venir'::int > 0, 'le décor : le solde du livreur a une course à venir');

select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_dettes(current_date - 1, current_date + 1) as det_adm \gset
select public.rh_argent_compteurs() as arg_det \gset
reset role; select essai.personne();
select essai.verifie(exists (select 1 from jsonb_array_elements(:'det_adm'::jsonb -> 'demandes') x
                              where x ->> 'type' = 'boutique' and (x ->> 'montant')::int = 20000 and (x ->> 'ancienne')::boolean
                                and (x ->> 'jours')::int >= 8), 'le reversement demandé il y a 8 jours : ancien (seuil 5 j)');
select essai.verifie(exists (select 1 from jsonb_array_elements(:'det_adm'::jsonb -> 'demandes') x
                              where x ->> 'type' = 'livreur' and x ->> 'nom' = 'Dossou' and (x ->> 'ancienne')::boolean),
  'les gains demandés par le livreur il y a 6 jours aussi');
select essai.verifie(exists (select 1 from jsonb_array_elements(:'det_adm'::jsonb -> 'demandes') x
                              where x ->> 'type' = 'parrain' and x ->> 'nom' like 'RHPARRAIN28%' and not (x ->> 'ancienne')::boolean),
  'le retrait du parrain, d''hier, pas encore');
select essai.egal((select (x ->> 'disponible')::int from jsonb_array_elements(:'det_adm'::jsonb -> 'comptes') x
                    where x ->> 'type' = 'livreur' and x ->> 'nom' = 'Dossou'), 1000,
  'le livreur : 3 000 gagnés, 2 000 demandés, 1 000 encore dus sans demande');
select essai.egal((select (x ->> 'a_venir')::int from jsonb_array_elements(:'det_adm'::jsonb -> 'comptes') x
                    where x ->> 'type' = 'livreur' and x ->> 'nom' = 'Dossou'), :'liv_a_venir'::int,
  'son « à venir » est celui de son solde, pas 0');
select essai.egal((:'det_adm'::jsonb #>> '{totaux,a_venir_livreurs}')::int >= :'liv_a_venir'::int, true,
  'et le total des livreurs le compte');
select essai.verifie((select (x ->> 'disponible')::int = 500 and x ->> 'nom' like '%Parrain Essai%'
                        from jsonb_array_elements(:'det_adm'::jsonb -> 'comptes') x where x ->> 'type' = 'parrain' and x ->> 'nom' like 'RHPARRAIN28%'),
  'le parrain : 500 encore dus ; l''administration voit son nom');
select essai.verifie((:'det_adm'::jsonb #>> '{totaux,reel}')::bigint >= 20000 + 1000 + 1000 + 2000 + 500
  and (:'det_adm'::jsonb #> '{totaux}') ? 'theorique_periode' and (:'det_adm'::jsonb #> '{totaux}') ? 'verse_periode',
  'la dette réelle, à côté du théorique et de ce qui a été versé');
select essai.verifie((:'arg_det'::jsonb ->> 'dettes_anciennes')::int >= 2, 'la pastille compte les demandes anciennes');

-- La clé « caisse » : les nombres et l'ancienneté, sans montants ni nom de parrain.
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_regler_acces(:'p_mkt', '{"caisse":"membres"}');
reset role; select essai.personne();
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select public.rh_dettes(current_date - 1, current_date + 1) as det_caisse \gset
reset role; select essai.personne();
select essai.egal((:'det_caisse'::jsonb ->> 'montants')::boolean, false, 'la consultation de caisse lit sans les montants');
select essai.verifie(not (:'det_caisse'::jsonb::text ~ '"(montant|attente|disponible|a_venir|reel|theorique_periode|verse_periode|attente_boutiques|disponible_boutiques)"'),
  'aucun montant');
select essai.verifie(not (:'det_caisse'::jsonb::text like '%Parrain Essai%'), 'ni le nom du parrain, un client');
select essai.verifie((:'det_caisse'::jsonb #>> '{totaux,anciennes}')::int >= 2, 'mais les demandes et leur ancienneté');

-- 4. Le journal des gestes de BIZZOO Admin. Le décor s'écrit déclencheurs
--    coupés : journal_verifie signe chaque ligne du compte connecté, et il
--    n'y en a pas ici.
set session_replication_role = replica;
insert into public.journal (fait_le, utilisateur, famille, action, libelle, cible, boutique_id, retour)
values (now() - interval '1 hour', 'moderateur@essai.bj', 'produit', 'modification', 'Produit modifié : Clavier — 10 000 FCFA', 'Clavier',
        'bou_informatique', '{"avant":[{"table":"produits","ligne":{"id":"prod_rh_argent"}}]}'),
       (((current_date - 1)::timestamp + time '23:10') at time zone 'Africa/Porto-Novo', 'moderateur@essai.bj', 'produit',
        'suppression', 'Produit supprimé : Souris', 'Souris', 'bou_informatique', null),
       -- Les libellés tels qu'Admin les écrit (store.js, connexion.js).
       (now() - interval '50 minutes', 'moderateur@essai.bj', 'boutique', 'ajout', 'Reversement demandé : 20000',
        'bou_informatique', 'bou_informatique', null),
       (now() - interval '45 minutes', 'moderateur@essai.bj', 'boutique', 'modification', 'Numéro de réception réglé : MTN 0197123456',
        'bou_informatique', 'bou_informatique', null),
       (now() - interval '40 minutes', 'moderateur@essai.bj', 'compte', 'connexion', 'Connexion à l''application admin',
        'moderateur@essai.bj', null, null);
insert into public.journal (fait_le, utilisateur, famille, action, libelle, cible, boutique_id)
select date_trunc('hour', now() - interval '3 hours') + make_interval(mins => g), 'rafale@essai.bj', 'categorie', 'modification',
       'Catégorie renommée', 'Câbles', 'bou_informatique'
  from generate_series(1, 11) g;
set session_replication_role = origin;

select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.refuse($$select public.rh_gestes()$$, 'l''administration n''y entre pas d''office : c''est elle que le journal regarde');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select public.rh_gestes(current_date - 2, current_date + 1) as ges_ceo \gset
select public.rh_gestes(current_date - 2, current_date + 1, 'produit', true) as ges_filtre \gset
reset role; select essai.personne();
select essai.egal((:'ges_ceo'::jsonb ->> 'tout_voir')::boolean, true, 'le CEO et superadministrateur lit tout');
select essai.verifie((select x -> 'raisons' ? 'argent' and x ? 'retour' from jsonb_array_elements(:'ges_ceo'::jsonb -> 'lignes') x
                       where x ->> 'libelle' like 'Produit modifié%'), 'un prix changé (« … — 10 000 FCFA ») : geste sensible « argent », avec l''état d''avant');
select essai.verifie((select x -> 'raisons' ? 'argent' from jsonb_array_elements(:'ges_ceo'::jsonb -> 'lignes') x
                       where x ->> 'libelle' like 'Numéro de réception%'), 'un numéro de réception réglé : « argent »');
select essai.verifie((select not (x -> 'raisons' ? 'compte') from jsonb_array_elements(:'ges_ceo'::jsonb -> 'lignes') x
                       where x ->> 'libelle' like 'Connexion à l''application%'), 'une simple connexion n''est pas un geste « compte »');
select essai.verifie(exists (select 1 from jsonb_array_elements(:'ges_ceo'::jsonb -> 'lignes') x
                              where x ->> 'libelle' = 'Reversement demandé : 20000')
  and not (:'ges_ceo'::jsonb ->> 'chiffres_masques')::boolean, 'le CEO lit les chiffres');
select essai.verifie((select x -> 'raisons' ? 'suppression' and x -> 'raisons' ? 'nuit' from jsonb_array_elements(:'ges_ceo'::jsonb -> 'lignes') x
                       where x ->> 'libelle' like 'Produit supprimé%'), 'une suppression à 23 h : « suppression » et « nuit »');
select essai.egal((select count(*)::int from jsonb_array_elements(:'ges_ceo'::jsonb -> 'lignes') x
                    where x ->> 'qui' = 'rafale@essai.bj' and x -> 'raisons' ? 'rafale'), 11, '11 gestes dans l''heure : « rafale »');
select essai.verifie((select bool_and(x ->> 'famille' = 'produit' and jsonb_array_length(x -> 'raisons') > 0)
                        from jsonb_array_elements(:'ges_filtre'::jsonb -> 'lignes') x)
  and jsonb_array_length(:'ges_filtre'::jsonb -> 'lignes') >= 2, 'les filtres : une famille, les sensibles seulement');

-- La clé « audit » : l'administration ne la règle pas, ni pour elle ni
-- pour un autre ; l'écran renvoie toutes les clés, une clé inchangée passe.
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_regler_acces(%L, '{"audit":"membres"}')$$, :'p_admin'),
  'l''administration ne s''ouvre pas le journal des gestes');
select essai.refuse(format($$select public.rh_regler_acces(%L, '{"audit":"responsable"}')$$, :'p_mkt'),
  'ni ne choisit qui la regarde : « audit » se règle par le CEO');
select public.rh_regler_acces(:'p_mkt', '{"audit":"ferme","promos":"membres"}');
reset role; select essai.personne();
select essai.verifie(not exists (select 1 from public.rh_acces_menus where menu = 'audit' and profil_id in (:'p_admin', :'p_mkt'))
  and exists (select 1 from public.rh_acces_menus where profil_id = :'p_mkt' and menu = 'promos'),
  'un enregistrement qui laisse « audit » tel quel passe');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select public.rh_regler_acces(:'p_mkt', '{"audit":"membres"}');
reset role; select essai.personne();
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.refuse($$select public.rh_gestes()$$, 'ouvrir « audit » à un autre profil ne l''ouvre pas à l''administration');
reset role; select essai.personne();
-- Même posée par une autre voie, la clé sur son propre profil ne lui ouvre rien.
insert into public.rh_acces_menus (profil_id, menu, qui, modifie_par, modifie_le)
select :'p_admin', 'audit', 'membres', a.modifie_par, now() from public.rh_acces_menus a
 where a.profil_id = :'p_mkt' and a.menu = 'audit';
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.refuse($$select public.rh_gestes()$$, 'son propre profil ouvert à « audit », l''administration n''y entre toujours pas');
select essai.egal((public.rh_argent_compteurs() #>> '{onglets,gestes}')::boolean, false, 'et ses compteurs ne lui ouvrent pas l''onglet');
reset role; select essai.personne();
delete from public.rh_acces_menus where profil_id = :'p_admin' and menu = 'audit';
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select public.rh_gestes(current_date - 2, current_date + 1) as ges_audit \gset
select public.rh_argent_compteurs() as arg_audit \gset
select essai.verifie('audit' = any(public.rh_mes_menus()) and 'promos' = any(public.rh_mes_menus()), 'les menus lui sont ouverts');
reset role; select essai.personne();
select essai.egal((:'ges_audit'::jsonb ->> 'tout_voir')::boolean, false, 'ouvert par « audit », il lit le journal…');
select essai.verifie(jsonb_array_length(:'ges_audit'::jsonb -> 'lignes') >= 13 and not (:'ges_audit'::jsonb::text like '%"retour"%'),
  '… sans l''état d''avant, réservé au CEO');
select essai.verifie(not exists (select 1 from jsonb_array_elements(:'ges_audit'::jsonb -> 'lignes') x
                                  where coalesce(x ->> 'libelle', '') ~ '[0-9]' or coalesce(x ->> 'cible', '') ~ '[0-9]')
  and not (:'ges_audit'::jsonb::text ~ '(20000|10 000|0197123456)') and (:'ges_audit'::jsonb ->> 'chiffres_masques')::boolean,
  '… sans aucun chiffre : ni montant, ni numéro de réception');
select essai.egal((select count(*)::int from jsonb_array_elements(:'ges_audit'::jsonb -> 'lignes') x
                    where x ->> 'libelle' = 'Reversement demandé : •••'), 1, 'le geste reste lisible, son montant masqué');
select essai.verifie((:'arg_audit'::jsonb #>> '{onglets,gestes}')::boolean and :'arg_audit'::jsonb #>> '{onglets,codes}' = 'equipe',
  'ses compteurs ouvrent les onglets');

-- 5. Les codes promo et le parrainage.
select essai.devenir(:ACHETEUSE_RH::uuid); set role authenticated;
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_rh_argent","quantite":1}]'::jsonb) ->> 'id' as cmd_p1 \gset
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_rh_argent","quantite":1}]'::jsonb) ->> 'id' as cmd_p2 \gset
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_rh_argent","quantite":1}]'::jsonb) ->> 'id' as cmd_p3 \gset
select public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_rh_argent","quantite":1}]'::jsonb) ->> 'id' as cmd_p4 \gset
reset role; select essai.personne();
select count(public.marquer_payee(x, 'TRX-RH-' || x, (select coalesce(acompte, total) from public.commandes where id = x), 'feexpay')) as payees
  from unnest(array[:'cmd_p1', :'cmd_p2', :'cmd_p3', :'cmd_p4']) x \gset
select essai.egal((select count(*)::int from public.commandes where etat = 'payee'
                    and id in (:'cmd_p1', :'cmd_p2', :'cmd_p3', :'cmd_p4')), 4, 'les quatre commandes du décor sont payées');
-- Trois comptes différents, une même adresse, le même code ; et le
-- parrain qui achète avec son propre code.
set session_replication_role = replica;
update public.commandes set code_promo = 'RHPROMO28', remise = 5000, client_adresse = 'Rue 12, Fidjrossè'
 where id in (:'cmd_p1', :'cmd_p2', :'cmd_p3');
update public.commandes set client_id = null, client_tel = '0196000001' where id = :'cmd_p2';
update public.commandes set client_id = null, client_tel = '0196000002' where id = :'cmd_p3';
update public.commandes set code_promo = 'RHPARRAIN28', remise = 500, client_id = :PARRAIN::uuid, client_tel = '0197112233'
 where id = :'cmd_p4';
set session_replication_role = origin;

select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_codes_surveillance(current_date - 1, current_date + 1) as codes_adm \gset
reset role; select essai.personne();
select essai.verifie((select (x ->> 'usages')::int = 3 and (x ->> 'clients')::int = 3 and (x ->> 'cout')::int = 15000
                             and (x ->> 'signalements')::int >= 1
                        from jsonb_array_elements(:'codes_adm'::jsonb -> 'codes') x where x ->> 'code' = 'RHPROMO28'),
  'un code : ses usages, ses clients, son coût, et il est signalé');
select essai.verifie(exists (select 1 from jsonb_array_elements(:'codes_adm'::jsonb -> 'abus') x
                              where x ->> 'type' = 'meme_lieu' and x ->> 'code' = 'RHPROMO28' and (x ->> 'comptes')::int = 3
                                and (x ->> 'commandes')::int = 3 and x -> 'numeros' ? '•••• 0001'),
  'abus probable : même adresse, trois comptes, numéros masqués');
select essai.verifie(exists (select 1 from jsonb_array_elements(:'codes_adm'::jsonb -> 'abus') x
                              where x ->> 'type' = 'propre_code' and x ->> 'code' = 'RHPARRAIN28'),
  'abus probable : le parrain use de son propre code');
select essai.verifie((select (x ->> 'propre_code')::boolean and x ->> 'tel' = '•••• 2233' and x ->> 'nom' = 'Parrain Essai'
                             and (x ->> 'disponible')::int = 500 and (x ->> 'demandes')::int = 1
                        from jsonb_array_elements(:'codes_adm'::jsonb -> 'parrains') x where x ->> 'codes' = 'RHPARRAIN28'),
  'le parrain : commissions, retraits, ce qui lui reste dû');
select essai.verifie(not (:'codes_adm'::jsonb::text ~ '(0196000001|0196000002|97666088|0197112233)'),
  'aucun numéro entier, même pour l''administration');

select essai.devenir(:MEMBRE::uuid); set role authenticated;
select public.rh_codes_surveillance(current_date - 1, current_date + 1) as codes_mkt \gset
reset role; select essai.personne();
select essai.egal((:'codes_mkt'::jsonb ->> 'montants')::boolean, false, 'le marketing lit les codes sans les montants');
select essai.verifie(not (:'codes_mkt'::jsonb::text ~ '"(cout|ventes|commissions|remise|valeur|mode|retire|demande|disponible|nom|commissions_periode|commissions_total)"'),
  'ni coût, ni valeur, ni commissions, ni nom de parrain');
select essai.verifie((select (x ->> 'usages')::int = 3 from jsonb_array_elements(:'codes_mkt'::jsonb -> 'codes') x where x ->> 'code' = 'RHPROMO28')
  and jsonb_array_length(:'codes_mkt'::jsonb -> 'abus') >= 2, 'mais les usages et les abus');
rollback;

-- ---------------------------------------------------------
select essai.titre('29. La qualité : SAV, fiche des boutiques, catalogue, files d''attente, zones, fidélité');
-- Tout le décor de cette section s'annule à la fin. Il s'écrit en grande
-- partie déclencheurs coupés (commandes, lignes, journal datés à la main) :
-- ce qu'on éprouve ici, ce sont les LECTURES de la qualité, pas le circuit
-- d'une commande, éprouvé ailleurs.
begin;
\set CLI_Q1   '''a0a0a0a0-0016-4000-8000-000000000016'''
\set CLI_Q2   '''a0a0a0a0-0017-4000-8000-000000000017'''
\set COMPTE_Q '''a0a0a0a0-0018-4000-8000-000000000018'''

-- Les droits : un employé sans accès, un compte de boutique, un visiteur.
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.egal(public.rh_qualite_compteurs() -> 'acces', 'null'::jsonb, 'menu fermé : un employé n''a pas la qualité');
select essai.refuse($$select public.rh_satisfaction()$$, 'ni le SAV');
select essai.refuse($$select public.rh_qualite_boutiques()$$, 'ni la fiche des boutiques');
select essai.refuse($$select public.rh_catalogue_anomalies()$$, 'ni la santé du catalogue');
select essai.refuse($$select public.rh_catalogue_appeler('x', 'rupture', true)$$, 'ni ne coche « boutique appelée »');
select essai.refuse($$select public.rh_files_attente()$$, 'ni les files d''attente');
select essai.refuse($$select public.rh_statistiques_zones()$$, 'ni les zones');
select essai.refuse($$select public.rh_statistiques_clients()$$, 'ni la fidélité');
select essai.refuse($$select public.rh_qualite_regler('{"reponse_h": 30}')$$, 'ni ne règle les seuils');
select essai.refuse($$select public.rh_notes_releve()$$, 'ni ne relève les notes');
select essai.refuse($$select * from public.rh_ruptures_suivi$$, 'la table des appels ne se lit pas');
select essai.refuse($$select * from public.rh_notes_boutiques$$, 'ni celle des notes');
select essai.refuse($$select * from public.rh_sav_ouvertes()$$, 'le rangement des réclamations n''est pas appelable à la main');
select essai.refuse($$select * from public.rh_ventes_30j()$$, 'ni les ventes des 30 jours');
reset role; select essai.personne();
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse($$select public.rh_satisfaction()$$, 'un compte de boutique non plus');
select essai.refuse($$select public.rh_statistiques_clients()$$, 'ni la fidélité');
reset role; select essai.personne();
set role anon;
select essai.refuse($$select public.rh_qualite_boutiques()$$, 'un visiteur n''appelle rien');
reset role;

-- Ce que la fidélité comptait AVANT le décor : les essais d'avant ont
-- laissé leurs clients, on ne mesure que ce que le décor ajoute.
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_statistiques_clients() as fid_avant \gset
select public.rh_qualite_compteurs() as cpt_avant \gset
reset role; select essai.personne();
select (date_trunc('month', current_date) - interval '8 months')::date as mois_q \gset

-- Le décor : deux boutiques (l'une sans horaires), leurs produits, deux
-- clientes qui notent, trois commandes payées il y a 6 h.
insert into auth.users (id, email) values (:CLI_Q1::uuid, 'cliente.q1@essai.bj'), (:CLI_Q2::uuid, 'cliente.q2@essai.bj'),
  (:COMPTE_Q::uuid, 'moderateur.q@essai.bj') on conflict do nothing;
insert into public.clients (id, nom, tel) values (:CLI_Q1::uuid, 'Cliente Un', '0196880001'), (:CLI_Q2::uuid, 'Cliente Deux', '0196880002')
on conflict (id) do update set nom = excluded.nom, tel = excluded.tel;
insert into public.boutiques (id, nom, actif) values ('bou_rh_q1', 'Boutique Lente', true);
insert into public.boutiques (id, nom, actif, ouvertures)
values ('bou_rh_q2', 'Boutique Modèle', true, '{"lun": {"de": "08:00", "a": "19:00"}}'::jsonb);
set session_replication_role = replica;
insert into public.produits (id, boutique_id, nom, prix, stock, sur_commande, appro_le, images, sous_categorie_id, masque, masque_le, code)
values ('prod_rq_1', 'bou_rh_q1', 'Fer à repasser', 2000, 0, false, null, '{a.jpg}', 'sc_hightech_accessoires', false, null, 'RQ1'),
       ('prod_rq_2', 'bou_rh_q1', 'Bouilloire', 3000, 0, false, current_date - 5, '{b.jpg}', 'sc_hightech_accessoires', false, null, 'RQ2'),
       ('prod_rq_3', 'bou_rh_q1', 'Ventilateur', 9000, 5, false, null, '{}', null, false, null, 'RQ3'),
       ('prod_rq_4', 'bou_rh_q1', 'Radio', 7000, 3, false, null, '{d.jpg}', 'sc_hightech_accessoires', true, now() - interval '40 days', 'RQ4'),
       ('prod_rq_ok', 'bou_rh_q2', 'Lampe', 4000, 10, false, null, '{e.jpg}', 'sc_hightech_accessoires', false, null, 'RQ5');
insert into public.commandes (id, numero, client_nom, client_tel, client_adresse, total, etat, cree_le, paye_le, client_id, livraison)
values ('cmd_rq_1', 'BZ-RQ1', 'Sika', '97666088', 'Rue 1', 9000, 'payee', now() - interval '6 hours', now() - interval '6 hours',
        :ACHETEUSE_RH::uuid, '{"distance_km": 4, "vehicule": "moto"}'::jsonb),
       ('cmd_rq_2', 'BZ-RQ2', 'Sika', '97666088', 'Rue 2', 4000, 'payee', now() - interval '6 hours', now() - interval '6 hours',
        :ACHETEUSE_RH::uuid, '{"distance_km": 10, "vehicule": "tricycle"}'::jsonb),
       ('cmd_rq_3', 'BZ-RQ3', 'Sika', '97666088', 'Rue 3', 4000, 'payee', now() - interval '6 hours', now() - interval '6 hours',
        :ACHETEUSE_RH::uuid, null);
insert into public.commande_lignes (id, commande_id, boutique_id, produit_id, nom, prix, quantite, etat, confirme_le)
values ('lig_rq_1', 'cmd_rq_1', 'bou_rh_q1', 'prod_rq_1', 'Fer à repasser', 2000, 3, 'vue', null),
       ('lig_rq_2', 'cmd_rq_1', 'bou_rh_q1', 'prod_rq_2', 'Bouilloire', 3000, 1, 'annulee', null),
       ('lig_rq_3', 'cmd_rq_2', 'bou_rh_q2', 'prod_rq_ok', 'Lampe', 4000, 1, 'remise', now() - interval '1 hour'),
       ('lig_rq_4', 'cmd_rq_3', 'bou_rh_q2', 'prod_rq_ok', 'Lampe', 4000, 1, 'en_livraison', null);
-- Le journal des étapes : la boutique lente voit sa commande 5 h après le
-- paiement ; la boutique modèle en 30 min, prépare en 30 min, remet à 3 h.
insert into public.rh_journal_lignes (commande_id, ligne_id, boutique_id, quoi, valeur, le) values
  ('cmd_rq_1', 'lig_rq_1', 'bou_rh_q1', 'etat', 'vue', now() - interval '1 hour'),
  ('cmd_rq_2', 'lig_rq_3', 'bou_rh_q2', 'etat', 'vue', now() - interval '5 hours 30 minutes'),
  ('cmd_rq_2', 'lig_rq_3', 'bou_rh_q2', 'etat', 'preparee', now() - interval '5 hours'),
  ('cmd_rq_2', 'lig_rq_3', 'bou_rh_q2', 'etat', 'remise', now() - interval '3 hours');
-- Les zones, corrigées comme le ferait l'administration ; un échec de livraison.
insert into public.rh_suivi_commandes (commande_id, zone) values
  ('cmd_rq_1', 'Quartier Alpha (Commune Essai)'), ('cmd_rq_2', 'Quartier Beta (Commune Essai)'), ('cmd_rq_3', 'Zone Essai Solo');
insert into public.rh_suivi_lignes (ligne_id, commande_id, statut, motif) values ('lig_rq_4', 'cmd_rq_3', 'echouee', 'Absent');
-- Le SAV de la boutique lente : une réclamation sans réponse depuis 30 h,
-- une répondue que le client lit, une escaladée depuis 3 jours, une où le
-- client a réécrit après la réponse, une tranchée hier.
insert into public.reclamations (id, client_id, commande_id, boutique_id, sujet, etat, cree_le, repondu_le, escalade_le,
                                 escalade_motif, decide_le, decision)
values ('rec_rq_1', :ACHETEUSE_RH::uuid, 'cmd_rq_1', 'bou_rh_q1', 'abime', 'ouverte', now() - interval '30 hours', null, null, '', null, ''),
       ('rec_rq_2', :ACHETEUSE_RH::uuid, 'cmd_rq_1', 'bou_rh_q1', 'pas_conforme', 'repondue', now() - interval '10 hours',
        now() - interval '9 hours', null, '', null, ''),
       ('rec_rq_3', :ACHETEUSE_RH::uuid, 'cmd_rq_1', 'bou_rh_q1', 'incomplet', 'escaladee', now() - interval '80 hours',
        now() - interval '78 hours', now() - interval '72 hours', 'Toujours rien reçu', null, ''),
       ('rec_rq_4', :ACHETEUSE_RH::uuid, 'cmd_rq_1', 'bou_rh_q1', 'autre', 'repondue', now() - interval '20 hours',
        now() - interval '19 hours', null, '', null, ''),
       ('rec_rq_5', :ACHETEUSE_RH::uuid, 'cmd_rq_1', 'bou_rh_q1', 'non_recu', 'tranchee', now() - interval '60 hours',
        now() - interval '58 hours', now() - interval '50 hours', 'Rien', now() - interval '26 hours', 'Remboursé');
insert into public.reclamation_messages (id, reclamation_id, auteur_role, texte, cree_le) values
  ('msg_rq_1', 'rec_rq_1', 'client', 'Abîmé', now() - interval '30 hours'),
  ('msg_rq_2', 'rec_rq_2', 'client', 'Pas conforme', now() - interval '10 hours'),
  ('msg_rq_3', 'rec_rq_2', 'boutique', 'Nous échangeons', now() - interval '9 hours'),
  ('msg_rq_4', 'rec_rq_4', 'client', 'Question', now() - interval '20 hours'),
  ('msg_rq_5', 'rec_rq_4', 'boutique', 'Réponse', now() - interval '19 hours'),
  ('msg_rq_6', 'rec_rq_4', 'client', 'Toujours pas', now() - interval '2 hours');
-- Les files d'Admin : une demande de boutique, un revendeur, un compte à
-- valider, un avis et un produit signalés, tous en attente depuis 3 à 4 jours.
insert into public.demandes (id, boutique_id, type, objet, apres, demande_le)
values ('dem_rq_1', 'bou_rh_q1', 'reglages', 'Nom', '{}'::jsonb, now() - interval '3 days');
update public.clients set revendeur_etat = 'en_attente', revendeur_demande_le = now() - interval '4 days' where id = :CLI_Q1::uuid;
update public.profils set a_valider = true, cree_le = now() - interval '3 days' where id = :COMPTE_Q::uuid;
-- La fidélité : trois clients venus il y a 8 mois ; le premier a racheté le
-- mois suivant ; le troisième a supprimé son compte.
insert into public.commandes (id, numero, client_nom, client_tel, client_adresse, total, etat, cree_le, paye_le, client_id, compte_supprime)
values ('cmd_rf_1', 'BZ-RF1', 'Fidèle Un', '0196990001', 'Rue F', 5000, 'payee', :'mois_q'::date + 9, :'mois_q'::date + 9, null, false),
       ('cmd_rf_2', 'BZ-RF2', 'Fidèle Un', '0196990001', 'Rue F', 7000, 'payee', (:'mois_q'::date + interval '1 month')::date + 9,
        (:'mois_q'::date + interval '1 month')::date + 9, null, false),
       ('cmd_rf_3', 'BZ-RF3', 'Passant Deux', '0196990002', 'Rue G', 3000, 'payee', :'mois_q'::date + 11, :'mois_q'::date + 11, null, false),
       ('cmd_rf_4', 'BZ-RF4', 'Parti Trois', '0196990003', 'Rue H', 2000, 'payee', :'mois_q'::date + 14, :'mois_q'::date + 14, null, true);
set session_replication_role = origin;
-- Les avis de la boutique lente, déclencheurs en marche (ils tiennent la
-- moyenne) : 5 il y a 40 jours, 1 hier — la note tombe de 5 à 3.
insert into public.avis (id, client_id, boutique_id, note, texte, auteur, cree_le)
values ('avis_rq_1', :CLI_Q1::uuid, 'bou_rh_q1', 5, 'Bien', 'Cliente Un', now() - interval '40 days'),
       ('avis_rq_2', :CLI_Q2::uuid, 'bou_rh_q1', 1, 'Lent', 'Cliente Deux', now() - interval '1 day');
set session_replication_role = replica;
insert into public.avis_signalements (avis_id, auteur_id, signale_par, cible, motif, cree_le)
values ('avis_rq_2', :CLI_Q2::uuid, :CHEF::uuid, 'avis', 'haine', now() - interval '3 days');
insert into public.produits_signalements (produit_id, nom_produit, boutique_id, signale_par, motif, cree_le)
values ('prod_rq_3', 'Ventilateur', 'bou_rh_q1', :CHEF::uuid, 'contrefacon', now() - interval '3 days');
set session_replication_role = origin;
select essai.egal((select note_moyenne from public.boutiques where id = 'bou_rh_q1'), 3.00::numeric(3,2),
  'le décor : la note de la boutique lente est de 3');

-- 1. Le SAV, vu par l'administration.
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_satisfaction(current_date - 5, current_date + 1) as sat_adm \gset
reset role; select essai.personne();
select essai.verifie((select x ->> 'colonne' = 'boutique' and x ->> 'alerte' = 'sans_reponse' and x ->> 'client' = 'Sika'
                        from jsonb_array_elements(:'sat_adm'::jsonb -> 'reclamations') x where x ->> 'id' = 'rec_rq_1'),
  'sans réponse depuis 30 h : « la boutique doit répondre », en alerte, le client nommé pour l''administration');
select essai.verifie((select x ->> 'colonne' = 'client' and x -> 'alerte' = 'null'::jsonb
                        from jsonb_array_elements(:'sat_adm'::jsonb -> 'reclamations') x where x ->> 'id' = 'rec_rq_2'),
  'répondue : « en attente du client », sans alerte');
select essai.verifie((select x ->> 'colonne' = 'bizzoo' and x ->> 'alerte' = 'escalade_en_attente' and x ->> 'motif' = 'Toujours rien reçu'
                        from jsonb_array_elements(:'sat_adm'::jsonb -> 'reclamations') x where x ->> 'id' = 'rec_rq_3'),
  'escaladée depuis 3 jours : « à trancher par BIZZOO », en alerte, avec son motif');
select essai.verifie((select x ->> 'colonne' = 'boutique' and x -> 'alerte' = 'null'::jsonb and (x ->> 'heures')::numeric = 2
                        from jsonb_array_elements(:'sat_adm'::jsonb -> 'reclamations') x where x ->> 'id' = 'rec_rq_4'),
  'le client a réécrit après la réponse : la boutique doit répondre, compté depuis son dernier message');
select essai.verifie(not exists (select 1 from jsonb_array_elements(:'sat_adm'::jsonb -> 'reclamations') x where x ->> 'id' = 'rec_rq_5'),
  'une réclamation tranchée n''attend plus personne');
select essai.verifie((select (x ->> 'reclamations')::int = 5 and (x ->> 'repondues')::int = 4
                             and (x ->> 'delai_reponse_h')::numeric = 1.5 and (x ->> 'sans_reponse')::int = 1
                             and (x ->> 'escaladees')::int = 2
                        from jsonb_array_elements(:'sat_adm'::jsonb -> 'boutiques') x where x ->> 'id' = 'bou_rh_q1'),
  'par boutique : 5 réclamations, 4 répondues en 1,5 h en moyenne, 1 sans réponse, 2 escaladées');
select essai.verifie((select (x ->> 'note')::numeric = 3 and (x ->> 'note_avant')::numeric = 5 and (x ->> 'variation')::numeric = -2
                             and (x ->> 'chute')::boolean and x ->> 'source_avant' = 'reconstituee'
                             and jsonb_array_length(x -> 'semaines') = 8
                        from jsonb_array_elements(:'sat_adm'::jsonb -> 'boutiques') x where x ->> 'id' = 'bou_rh_q1'),
  'la note est passée de 5 à 3 en 30 jours : chute signalée, courbe de 8 semaines');
select essai.verifie((:'sat_adm'::jsonb #>> '{totaux,sans_reponse}')::int >= 1
                     and (:'sat_adm'::jsonb #>> '{totaux,escalades_en_retard}')::int >= 1
                     and (:'sat_adm'::jsonb #>> '{totaux,tranchees}')::int >= 1,
  'les totaux comptent les alertes et les décisions de la période');

-- Le relevé des notes : pg_cron ou l'écran.
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.verifie(public.rh_notes_releve() >= 1, 'l''administration relève les notes');
reset role; select essai.personne();
select essai.egal((select note from public.rh_notes_boutiques where boutique_id = 'bou_rh_q1'
                    and semaine = date_trunc('week', now() at time zone 'Africa/Porto-Novo')::date), 3.00::numeric(3,2),
  'la note de la semaine est gardée');

-- 2. La fiche qualité des boutiques.
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_qualite_boutiques(current_date - 3, current_date + 1) as bq_adm \gset
reset role; select essai.personne();
select x as bq_lente from jsonb_array_elements(:'bq_adm'::jsonb -> 'boutiques') x where x ->> 'id' = 'bou_rh_q1' \gset
select x as bq_modele from jsonb_array_elements(:'bq_adm'::jsonb -> 'boutiques') x where x ->> 'id' = 'bou_rh_q2' \gset
select essai.egal((:'bq_lente'::jsonb ->> 'delai_vue_h')::numeric, 5.0, 'la boutique lente voit ses commandes en 5 h');
select essai.egal((:'bq_lente'::jsonb ->> 'annulation_pct')::numeric, 50.0, 'elle annule un article sur deux');
select essai.egal((:'bq_lente'::jsonb ->> 'rupture_pct')::numeric, 66.7, 'deux produits visibles sur trois sont épuisés');
select essai.verifie(:'bq_lente'::jsonb -> 'problemes' @> '["vue_lente", "annulations", "reclamations", "ruptures", "note", "horaires"]'::jsonb,
  'ses signaux : vue lente, annulations, réclamations, ruptures, note, pas d''horaires');
select essai.egal(:'bq_lente'::jsonb ->> 'feu', 'rouge', 'elle est en rouge');
select essai.egal((:'bq_lente'::jsonb ->> 'ventes')::int, 6000, 'l''administration voit ses ventes, articles annulés exclus');
select essai.egal(:'bq_modele'::jsonb ->> 'feu', 'vert', 'la boutique modèle est en vert');
select essai.egal((:'bq_modele'::jsonb ->> 'delai_preparation_h')::numeric, 0.5, 'elle prépare en 30 min');
select essai.verifie(not (:'bq_adm'::jsonb::text ~ '(prix_bizzoo|taux_marge|benefice)'), 'jamais le prix BIZZOO ni la marge');

-- 3. La santé du catalogue.
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_catalogue_anomalies() as cat_adm \gset
select public.rh_qualite_compteurs() as cpt_decor \gset
reset role; select essai.personne();
select essai.verifie((select (x ->> 'vendus_30j')::int = 3 and x -> 'appel' = 'null'::jsonb and x ->> 'boutique' = 'Boutique Lente'
                        from jsonb_array_elements(:'cat_adm'::jsonb -> 'ruptures') x where x ->> 'id' = 'prod_rq_1'),
  'épuisé après 3 ventes en 30 jours : une rupture qui coûte, pas encore appelée');
select essai.verifie(not exists (select 1 from jsonb_array_elements(:'cat_adm'::jsonb -> 'ruptures') x where x ->> 'id' = 'prod_rq_2'),
  'un article annulé n''est pas une vente');
select essai.verifie((select (x ->> 'retard_j')::int = 5 from jsonb_array_elements(:'cat_adm'::jsonb -> 'appro_depasse') x
                       where x ->> 'id' = 'prod_rq_2'), 'réapprovisionnement dépassé de 5 jours');
select essai.verifie(exists (select 1 from jsonb_array_elements(:'cat_adm'::jsonb -> 'sans_photo') x where x ->> 'id' = 'prod_rq_3')
                     and exists (select 1 from jsonb_array_elements(:'cat_adm'::jsonb -> 'sans_categorie') x where x ->> 'id' = 'prod_rq_3'),
  'une fiche sans photo ni catégorie');
select essai.verifie((select (x ->> 'jours')::int >= 40 from jsonb_array_elements(:'cat_adm'::jsonb -> 'masques') x
                       where x ->> 'id' = 'prod_rq_4'), 'masqué depuis 40 jours');
select essai.verifie(not (:'cat_adm'::jsonb::text ~ '"(prix|prix_grossiste|prix_bizzoo)"'), 'aucun prix');
select essai.egal((:'cpt_decor'::jsonb ->> 'ruptures_a_appeler')::int - (:'cpt_avant'::jsonb ->> 'ruptures_a_appeler')::int, 1,
  'la pastille compte la rupture à appeler');

-- La clé « qualite » ouvre le menu aux membres du Marketing, sans montants.
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_regler_acces(:'p_mkt', '{"qualite":"membres"}');
reset role; select essai.personne();
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.verifie('qualite' = any(public.rh_mes_menus()), 'le menu Qualité lui est ouvert');
select essai.egal(public.rh_qualite_compteurs() ->> 'acces', 'equipe', 'en équipe, sans montants');
select public.rh_satisfaction(current_date - 5, current_date + 1) as sat_mkt \gset
select public.rh_qualite_boutiques(current_date - 3, current_date + 1) as bq_mkt \gset
select essai.refuse($$select public.rh_catalogue_appeler('prod_rq_1', 'rupture_x', true)$$, 'une anomalie inconnue est refusée');
select essai.refuse($$select public.rh_catalogue_appeler('prod_inconnu', 'rupture', true)$$, 'un produit inconnu aussi');
select public.rh_catalogue_appeler('prod_rq_1', 'rupture', true, 'Réassort promis lundi');
select public.rh_catalogue_anomalies() as cat_appel \gset
select public.rh_qualite_compteurs() as cpt_appel \gset
select essai.refuse($$select public.rh_qualite_regler('{"reponse_h": 30}')$$, 'il ne règle pas les seuils');
reset role; select essai.personne();
select essai.verifie((select x -> 'client' = 'null'::jsonb and x -> 'motif' = 'null'::jsonb
                        from jsonb_array_elements(:'sat_mkt'::jsonb -> 'reclamations') x where x ->> 'id' = 'rec_rq_3'),
  'il voit les réclamations sans le nom du client ni le motif');
select essai.verifie(not (:'sat_mkt'::jsonb::text ~ '(Sika|Toujours rien)'), 'nulle part');
select essai.verifie((select (x ->> 'delai_vue_h')::numeric = 5.0 and x -> 'ventes' = 'null'::jsonb
                        from jsonb_array_elements(:'bq_mkt'::jsonb -> 'boutiques') x where x ->> 'id' = 'bou_rh_q1')
                     and not (:'bq_mkt'::jsonb::text ~ '"ventes": [0-9]'),
  'la fiche des boutiques : les délais, jamais les ventes');
select essai.verifie((select x #>> '{appel,par}' = 'Inès ADJOVI' and x #>> '{appel,note}' = 'Réassort promis lundi'
                        from jsonb_array_elements(:'cat_appel'::jsonb -> 'ruptures') x where x ->> 'id' = 'prod_rq_1'),
  '« boutique appelée » : qui, et ce qui a été dit');
select essai.egal((:'cpt_decor'::jsonb ->> 'ruptures_a_appeler')::int - (:'cpt_appel'::jsonb ->> 'ruptures_a_appeler')::int, 1,
  'appelée, la rupture quitte la pastille');
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select public.rh_catalogue_appeler('prod_rq_1', 'rupture', false);
select essai.verifie((select x -> 'appel' = 'null'::jsonb from jsonb_array_elements(public.rh_catalogue_anomalies() -> 'ruptures') x
                       where x ->> 'id' = 'prod_rq_1'), 'décochée, elle redevient à appeler');
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.rh_ruptures_suivi where produit_id = 'prod_rq_1'), 0, 'l''appel retiré n''est plus noté');

-- 4. Les files d'attente de décision.
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select public.rh_files_attente() as files_mkt \gset
reset role; select essai.personne();
select essai.verifie((select bool_and((x ->> 'nombre')::int >= 1 and (x ->> 'rouge')::boolean
                                      and (x ->> 'plus_ancienne')::timestamptz <= now() - interval '3 days')
                        from jsonb_array_elements(:'files_mkt'::jsonb -> 'files') x)
                     and jsonb_array_length(:'files_mkt'::jsonb -> 'files') = 5,
  'cinq files (demandes, revendeurs, comptes, avis, produits signalés), toutes en rouge au-delà de 48 h');
select essai.verifie(not (:'files_mkt'::jsonb::text ~ '(Cliente|Ventilateur|Boutique Lente|0196880001)'),
  'des nombres et des dates : aucun nom');

-- 5. Le service par zone.
-- Le volume : 3 000 commandes payées il y a 1 h, plus récentes que celles
-- du décor. Les zones ne gardaient que les 3 000 plus récentes : le décor
-- disparaissait des nombres, sans que l'écran le dise.
set session_replication_role = replica;
insert into public.commandes (id, numero, client_nom, client_tel, client_adresse, total, etat, cree_le, paye_le)
select 'cmd_rv_' || g, 'BZ-RV' || g, 'Volume', '', 'Rue V', 1000, 'payee', now() - interval '1 hour', now() - interval '1 hour'
  from generate_series(1, 3000) g;
insert into public.rh_suivi_commandes (commande_id, zone) select 'cmd_rv_' || g, 'Zone Volume' from generate_series(1, 3000) g;
set session_replication_role = origin;
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select public.rh_statistiques_zones(current_date - 1, current_date + 1) as zones_c \gset
select public.rh_statistiques_zones(current_date - 1, current_date + 1, 'quartier') as zones_q \gset
select essai.refuse($$select public.rh_statistiques_zones(null, null, 'pays')$$, 'un niveau inconnu est refusé');
reset role; select essai.personne();
select essai.verifie((select (x ->> 'commandes')::int = 2 and (x ->> 'livrees')::int = 1 and (x ->> 'delai_moyen_h')::numeric = 5
                             and (x ->> 'lentes')::int = 1 and (x ->> 'non_recus')::int = 1
                             and (x ->> 'distance_moyenne_km')::numeric = 7 and (x ->> 'tricycle_pct')::numeric = 50
                        from jsonb_array_elements(:'zones_c'::jsonb -> 'zones') x where x ->> 'zone' = 'Commune Essai'),
  'par commune : 2 commandes, 1 livrée en 5 h (lente), 1 non reçue, 7 km en moyenne, moitié en tricycle');
select essai.verifie((select (x ->> 'echecs')::int = 1 and x -> 'tricycle_pct' = 'null'::jsonb
                        from jsonb_array_elements(:'zones_c'::jsonb -> 'zones') x where x ->> 'zone' = 'Zone Essai Solo'),
  'une zone sans commune : son échec de livraison');
select essai.verifie((select (x ->> 'commandes')::int = 1 from jsonb_array_elements(:'zones_q'::jsonb -> 'zones') x
                       where x ->> 'zone' = 'Quartier Alpha (Commune Essai)'), 'par quartier : chaque quartier à part');
select essai.verifie(not (:'zones_c'::jsonb::text ~ '"(total|montant|frais|prix)"'), 'aucun montant');
select essai.verifie((select (x ->> 'commandes')::int = 3000 and (x ->> 'livrees')::int = 0
                        from jsonb_array_elements(:'zones_c'::jsonb -> 'zones') x where x ->> 'zone' = 'Zone Volume'),
  'les 3 000 commandes du volume comptent toutes, sans chasser celles du décor');
set session_replication_role = replica;
delete from public.rh_suivi_commandes where commande_id like 'cmd\_rv\_%';
delete from public.commandes where id like 'cmd\_rv\_%';
set session_replication_role = origin;
-- Le journal n'est indexé que par commande : chaque lecture d'un article
-- dans le journal doit passer par sa commande, sinon elle relit tout le
-- journal pour chaque article et une période d'un an dépasse le délai.
select essai.verifie((select bool_and(
                        (length(p.prosrc) - length(replace(p.prosrc, 'j.ligne_id = l.id', ''))) / length('j.ligne_id = l.id')
                        = (length(p.prosrc) - length(replace(p.prosrc, 'j.commande_id = l.commande_id and j.ligne_id = l.id', '')))
                          / length('j.commande_id = l.commande_id and j.ligne_id = l.id')
                        and p.prosrc like '%j.ligne_id = l.id%')
                        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'public' and p.proname in ('rh_qualite_boutiques', 'rh_statistiques_zones'))
                     and (select count(*) from pg_proc where proname in ('rh_qualite_boutiques', 'rh_statistiques_zones')) = 2,
  'la fiche des boutiques et les zones lisent le journal par commande (son index)');

-- 6. La fidélité.
-- Une cliente venue le mois dernier, revenue ce mois-ci : le mois en cours
-- n'est pas fini, sa cohorte n'a pas encore de taux « le mois suivant ».
select (date_trunc('month', now() at time zone 'Africa/Porto-Novo') - interval '1 month')::date as mois_prec \gset
set session_replication_role = replica;
insert into public.commandes (id, numero, client_nom, client_tel, client_adresse, total, etat, cree_le, paye_le, client_id)
values ('cmd_rf_5', 'BZ-RF5', 'Récente Quatre', '0196990004', 'Rue I', 1000, 'payee',
        (:'mois_prec'::date + interval '10 days 12 hours') at time zone 'Africa/Porto-Novo',
        (:'mois_prec'::date + interval '10 days 12 hours') at time zone 'Africa/Porto-Novo', null),
       ('cmd_rf_6', 'BZ-RF6', 'Récente Quatre', '0196990004', 'Rue I', 1000, 'payee', now() - interval '1 minute', now() - interval '1 minute', null);
set session_replication_role = origin;
select essai.devenir(:ADMRH::uuid); set role authenticated;
select public.rh_statistiques_clients() as fid_adm \gset
reset role; select essai.personne();
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select public.rh_statistiques_clients() as fid_mkt \gset
reset role; select essai.personne();
select coalesce((select x from jsonb_array_elements(:'fid_avant'::jsonb -> 'cohortes') x where (x ->> 'mois')::date = :'mois_q'::date),
                '{"nouveaux": 0, "m1": 0}'::jsonb) as coh_avant \gset
select x as coh_apres from jsonb_array_elements(:'fid_adm'::jsonb -> 'cohortes') x where (x ->> 'mois')::date = :'mois_q'::date \gset
select essai.egal((:'coh_apres'::jsonb ->> 'nouveaux')::int - (:'coh_avant'::jsonb ->> 'nouveaux')::int, 3,
  'trois nouveaux clients le mois de leur premier achat');
select essai.egal((:'coh_apres'::jsonb ->> 'm1')::int - (:'coh_avant'::jsonb ->> 'm1')::int, 1, 'un seul a racheté le mois suivant');
select essai.egal((:'fid_adm'::jsonb #>> '{totaux,perdus_90}')::int - (:'fid_avant'::jsonb #>> '{totaux,perdus_90}')::int, 2,
  'deux clients perdus depuis 90 jours (le compte supprimé à part)');
select essai.egal((:'fid_adm'::jsonb #>> '{totaux,comptes_supprimes}')::int - (:'fid_avant'::jsonb #>> '{totaux,comptes_supprimes}')::int, 1,
  'un compte supprimé');
select essai.verifie((select x ->> 'tel' = '•••• 0001' and (x ->> 'commandes')::int = 2 and x ->> 'derniere_commande' = 'BZ-RF2'
                        from jsonb_array_elements(:'fid_adm'::jsonb -> 'relance') x where x ->> 'nom' = 'Fidèle Un'),
  'la liste à relancer de l''administration : nom, numéro masqué, dernière commande');
select essai.verifie(not exists (select 1 from jsonb_array_elements(:'fid_adm'::jsonb -> 'relance') x where x ->> 'nom' = 'Parti Trois'),
  'jamais un compte supprimé');
select essai.verifie(not (:'fid_adm'::jsonb::text ~ '0196990001'), 'aucun numéro entier, même pour l''administration');
select essai.verifie(:'fid_mkt'::jsonb -> 'relance' = 'null'::jsonb and not (:'fid_mkt'::jsonb::text ~ '(Fidèle|"valeur": [0-9]|"depense")'),
  'les autres : les taux, ni la liste, ni la valeur des clients');
select essai.verifie((select (x ->> 'nouveaux')::int >= 1 and x -> 'm1' = 'null'::jsonb
                        from jsonb_array_elements(:'fid_adm'::jsonb -> 'cohortes') x where (x ->> 'mois')::date = :'mois_prec'::date),
  'la cohorte du mois dernier : « à venir » le mois suivant, puisque c''est le mois en cours');
-- Sur toutes les cohortes : un taux n'existe que pour un mois terminé.
select essai.verifie(coalesce((select bool_and(
                        (x -> 'm1' = 'null'::jsonb) = ((x ->> 'mois')::date + interval '1 month' >= :'mois_prec'::date + interval '1 month')
                        and (x -> 'm2' = 'null'::jsonb) = ((x ->> 'mois')::date + interval '2 months' >= :'mois_prec'::date + interval '1 month')
                        and (x -> 'm3' = 'null'::jsonb) = ((x ->> 'mois')::date + interval '3 months' >= :'mois_prec'::date + interval '1 month'))
                        from jsonb_array_elements(:'fid_adm'::jsonb -> 'cohortes') x), false),
  'aucune cohorte n''a de taux pour le mois en cours, toutes en ont pour un mois fini');

-- Les seuils : l'administration, dans leurs bornes.
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.refuse($$select public.rh_qualite_regler('{"reponse_h": 0}')$$, 'un seuil hors bornes est refusé');
select essai.refuse($$select public.rh_qualite_regler('{"inconnu": 3}')$$, 'un seuil inconnu aussi');
select essai.refuse($$select public.rh_qualite_regler('{"files_h": {"autre": 5}}')$$, 'une file inconnue aussi');
select essai.refuse($$select public.rh_qualite_regler('{"annulation_pct": 12.5}')$$, 'un pourcentage entier');
select public.rh_qualite_regler('{"reponse_h": 40, "files_h": {"demandes": 120}, "note_min": 2.5}');
select public.rh_satisfaction(current_date - 5, current_date + 1) as sat_regle \gset
select public.rh_files_attente() as files_regle \gset
reset role; select essai.personne();
select essai.verifie((select x -> 'alerte' = 'null'::jsonb from jsonb_array_elements(:'sat_regle'::jsonb -> 'reclamations') x
                       where x ->> 'id' = 'rec_rq_1'), 'à 40 h, la réclamation de 30 h n''est plus en alerte');
select essai.verifie((select (x ->> 'seuil_h')::int = 120 and not (x ->> 'rouge')::boolean
                        from jsonb_array_elements(:'files_regle'::jsonb -> 'files') x where x ->> 'cle' = 'demandes')
                     and (select (x ->> 'seuil_h')::int = 48 from jsonb_array_elements(:'files_regle'::jsonb -> 'files') x where x ->> 'cle' = 'avis'),
  'une file se règle seule, les autres gardent leur seuil');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal(public.rh_qualite_compteurs() ->> 'acces', 'admin', 'le CEO, superadministrateur, a tout');
reset role; select essai.personne();
rollback;

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
