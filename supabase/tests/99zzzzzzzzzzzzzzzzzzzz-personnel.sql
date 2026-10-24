-- =========================================================
-- BIZZOO Personnel : la gestion interne des employés
--
-- Ce qu'on prouve :
--   1. le premier CEO s'amorce une seule fois, par un superadministrateur ;
--   2. l'administration crée un employé, le CEO seul le valide ; les
--      droits (administration, décaissement, salaire en poste) sont au CEO ;
--   3. un employé ne touche qu'à ses coordonnées ;
--   4. un profil a un responsable qui en est membre ;
--   5. les messages restent dans leur profil, les messages privés entre
--      leurs deux personnes ;
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
--  11. un compte « personnel » ne devient pas un compte de boutique.
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
update public.rh_employes set telephone = '0197000001', adresse = 'Cadjèhoun' where compte_id = auth.uid();
select essai.egal((select telephone from public.rh_employes where compte_id = auth.uid()), '0197000001',
  'il change son téléphone');
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
select essai.refuse(format($$insert into public.rh_messages (profil_id, texte) values (%L, 'intrus')$$, :'p_log'),
  'il n''écrit pas dans la discussion de la Logistique');
select essai.refuse(format($$insert into public.rh_messages (destinataire_id, texte) values (%L, 'salut')$$, :'e_autre'),
  'ni en privé à un logisticien qu''il ne connaît pas par son profil');
insert into public.rh_messages (destinataire_id, texte) values (:'e_resp', 'Chef, une question privée');
insert into public.rh_messages (destinataire_id, texte) values (:'e_admrh', 'Question à l''administration');
reset role; select essai.personne();

select essai.devenir(:AUTRE::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.rh_messages where profil_id = :'p_mkt'), 0,
  'la Logistique ne lit pas la discussion du Marketing');
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
select essai.titre('8. Les dépenses');
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.refuse(format($$insert into public.rh_depenses (profil_id, objet, montant) values (%L, 'Stylos', 5000)$$, :'p_mkt'),
  'un simple membre ne demande pas de dépense');
reset role; select essai.personne();
select essai.devenir(:RESP::uuid); set role authenticated;
insert into public.rh_depenses (profil_id, objet, montant, statut)
values (:'p_mkt', 'Impression de 500 affiches', 50000, 'decaissee')
returning id as depense \gset
select essai.egal((select statut from public.rh_depenses where id = :'depense'), 'demandee',
  'une dépense naît « demandée »');
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
select essai.devenir(:RESP::uuid); set role authenticated;
select essai.refuse(format($$update public.rh_depenses set montant = 90000 where id = %L$$, :'depense'),
  'approuvée, son montant ne change plus');
reset role; select essai.personne();
select essai.devenir(:CAISSE::uuid); set role authenticated;
select public.rh_decaisser_depense(:'depense', 'mobile_money', 'MM-123');
select essai.egal((select statut from public.rh_depenses where id = :'depense'), 'decaissee',
  'approuvée par le CEO, décaissée par l''habilité');
select essai.refuse(format($$select public.rh_decaisser_depense(%L, 'especes')$$, :'depense'),
  'on ne décaisse pas deux fois');
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
select essai.verifie((select count(*) from public.rh_fiches_paie where mois = '2026-09-01') >= 5,
  'validées, l''habilité voit toutes les fiches à payer');
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
select essai.devenir(:CAISSE::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_payer_fiche(%L, 'especes')$$, :'fiche_oct'),
  'une fiche pas encore validée ne se paie pas');
reset role; select essai.personne();
select essai.devenir(:CAISSE::uuid); set role authenticated;
select public.rh_payer_fiche(:'fiche_sept', 'virement', 'VIR-09');
reset role; select essai.personne();
select essai.egal((select statut from public.rh_fiches_paie where id = :'fiche_sept'), 'payee',
  'validée par le CEO, payée par l''habilité');
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
select essai.sans_effet(format($$update public.rh_profils set statistiques = '{livraisons}' where id = %L$$, :'p_mkt'),
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
update public.rh_profils set statistiques = '{livraisons}' where id = :'p_mkt';
select essai.refuse(format($$update public.rh_profils set statistiques = '{marge}' where id = %L$$, :'p_mkt'),
  'une rubrique inconnue est refusée');
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
