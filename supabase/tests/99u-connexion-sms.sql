-- =========================================================
-- La connexion de l'équipe confirmée par SMS, et qui a créé
-- quel compte
--
-- CE QU'ON DÉFEND ICI. Quand l'enseigne l'exige, un compte de
-- l'équipe qui a donné son mot de passe n'a ENCORE AUCUN DROIT :
-- il lui faut rendre le code reçu par SMS, et ce code ne vaut que
-- pour la session où il a été demandé. Un mot de passe volé ne
-- suffit plus.
--
-- UN CODE QUI NE FERME QU'À L'ÉCRAN NE FERME RIEN. Chaque constat
-- éprouve la BASE : « role_courant() », dont découlent tous les
-- droits de l'équipe, et les deux fonctions qui lisent la fiche
-- elles-mêmes.
--
-- Et la trace : qui a créé un compte, et quand. La base l'écrit,
-- l'application ne peut que la lire.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set EQUIPE   '''33333333-3333-3333-3333-333333333333'''
\set PORTEUR  '''cccccccc-1111-1111-1111-111111111111'''
\set ADJOINT  '''dddddddd-1111-1111-1111-111111111111'''
\set NOUVEAU  '''f0f0f0f0-0000-0000-0000-000000000001'''
\set RECRUE   '''f0f0f0f0-0000-0000-0000-000000000002'''
\set INSCRIT  '''f0f0f0f0-0000-0000-0000-000000000003'''
\set FORGE    '''f0f0f0f0-0000-0000-0000-000000000004'''
\set PARTI    '''f0f0f0f0-0000-0000-0000-000000000007'''
\set SANSNUM  '''f0f0f0f0-0000-0000-0000-000000000005'''
\set ACHETEUR '''f0f0f0f0-0000-0000-0000-000000000006'''
\set S1       '''e1000000-0000-0000-0000-000000000001'''
\set S2       '''e1000000-0000-0000-0000-000000000002'''
\set S3       '''e1000000-0000-0000-0000-000000000003'''
\set S4       '''e1000000-0000-0000-0000-000000000004'''
\set S5       '''e1000000-0000-0000-0000-000000000005'''
\set S6       '''e1000000-0000-0000-0000-000000000006'''
\set S7       '''e1000000-0000-0000-0000-000000000007'''

-- L'empreinte d'un code pour une session, telle que la fonction Edge la
-- calcule : sha256(« code:session »), en hexadécimal.
create or replace function essai.empreinte(code text, session uuid) returns text
language sql immutable as $$
  select encode(digest(code || ':' || session::text, 'sha256'), 'hex');
$$;

-- Ce que fait la fonction Edge : inscrire l'empreinte, avec la clé de
-- service. Rend l'identifiant du code, ou la raison du refus.
create or replace function essai.envoyer(qui uuid, session uuid, code text)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  set local role service_role;
  r := public.enregistrer_code_connexion(qui, session, essai.empreinte(code, session));
  reset role;
  return r;
end $$;

-- Laisser passer le temps : reculer les codes d'un compte.
create or replace function essai.reculer_codes(qui uuid, secondes int)
returns void language plpgsql as $$
begin
  update public.codes_connexion
     set envoye_le = envoye_le - make_interval(secs => secondes),
         expire_le = expire_le - make_interval(secs => secondes)
   where utilisateur = qui;
end $$;

grant execute on all functions in schema essai to anon, authenticated, service_role;

-- LE MÊME CALCUL DES DEUX CÔTÉS. La fonction Edge hache avec Web Crypto,
-- la base avec pgcrypto ; ce vecteur est aussi celui du banc des
-- fonctions (functions/tests/sms.mjs). S'ils divergeaient, aucun code ne
-- serait jamais juste.
select essai.egal(essai.empreinte('123456', 'e1000000-0000-0000-0000-000000000001'::uuid),
  '6c04d1634fb52316e8e6b0d11a7dcf50ef38dc054cdf5f350a7a0ec9f58f537f',
  'l''empreinte de référence, partagée avec le banc des fonctions');

-- ---------------------------------------------------------
select essai.titre('Le décor : des numéros pour l''équipe');

update public.profils set tel = '0197000001', nom = 'Enseigne' where id = :ENSEIGNE::uuid;
update public.profils set tel = '0197000002' where id = :CHEF::uuid;
update public.profils set tel = '0197000003' where id = :EQUIPE::uuid;
update public.profils set tel = '0197000004' where id = :PORTEUR::uuid;
update public.profils set tel = '0197000005' where id = :ADJOINT::uuid;

insert into auth.users (id, email) values
  (:SANSNUM::uuid, 'sans-numero@bizzoo.bj')
on conflict do nothing;
update public.profils set role = 'moderateur', actif = true, tel = '',
       boutique_id = 'bou_informatique'
 where id = :SANSNUM::uuid;

-- Un acheteur, qui n'est pas de l'équipe.
insert into auth.users (id, email, raw_user_meta_data) values
  (:ACHETEUR::uuid, 'acheteur@exemple.bj', '{"compte": "client"}')
on conflict do nothing;
insert into public.clients (id, nom, tel) values (:ACHETEUR::uuid, 'Acheteur', '0196000006')
on conflict (id) do nothing;

select essai.egal(
  (select count(*)::int from public.profils
    where id in (:ENSEIGNE::uuid, :CHEF::uuid, :EQUIPE::uuid, :PORTEUR::uuid, :ADJOINT::uuid)
      and actif and length(tel) >= 8), 5,
  'cinq comptes de l''équipe ont un numéro');

-- ---------------------------------------------------------
select essai.titre('Tant que l''enseigne ne l''exige pas, rien ne change');

select essai.verifie(not public.sms_equipe_exige(), 'l''interrupteur part éteint');

select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.verifie(public.est_admin(), 'l''administrateur garde ses droits sans code');
select essai.egal(public.boutique_du_compte(), 'bou_informatique',
  'et sa boutique');
select essai.egal((public.etat_connexion() ->> 'sms_exige')::boolean, false,
  'l''état de la connexion dit « rien d''exigé »');
reset role;

select essai.devenir(:ADJOINT::uuid); set role authenticated;
select essai.verifie(public.est_compte_enseigne(), 'le compte de BIZZOO aussi');
reset role;

-- ---------------------------------------------------------
select essai.titre('Inscrire un code est réservé à la fonction Edge');

select essai.devenir(:ENSEIGNE::uuid, :S1::uuid); set role authenticated;
select essai.refuse(
  format('select public.enregistrer_code_connexion(%L::uuid, %L::uuid, %L)',
         :ENSEIGNE, :S1, essai.empreinte('111111', :S1::uuid)),
  'un compte connecté n''inscrit pas l''empreinte d''un code qu''il aurait choisi');
select essai.refuse(
  'select public.annuler_code_connexion(1)',
  'ni n''annule un code');
select essai.refuse('select * from public.codes_connexion',
  'les codes envoyés ne se lisent pas');
select essai.refuse('select * from public.sessions_sms',
  'les sessions confirmées non plus');
select essai.refuse('select * from public.securite_equipe',
  'ni l''interrupteur');
select essai.refuse(
  'update public.securite_equipe set sms_exige = false',
  'qui ne s''écrit pas non plus directement');
reset role;

select essai.personne(); set role anon;
select essai.refuse(
  format('select public.enregistrer_code_connexion(%L::uuid, %L::uuid, %L)',
         :ENSEIGNE, :S1, essai.empreinte('111111', :S1::uuid)),
  'un visiteur encore moins');
select essai.refuse('select public.confirmer_code_connexion(''111111'')',
  'un visiteur ne rend pas de code');
select essai.refuse('select public.etat_connexion()',
  'ni ne lit l''état d''une connexion');
reset role;

-- ---------------------------------------------------------
select essai.titre('L''envoi : le numéro de la fiche, et le frein');

select essai.egal(essai.envoyer(:SANSNUM::uuid, :S2::uuid, '222222') ->> 'raison', 'sans_numero',
  'un compte sans numéro ne reçoit rien : il n''y a nulle part où l''envoyer');
select essai.egal(essai.envoyer(:ACHETEUR::uuid, :S2::uuid, '222222') ->> 'raison', 'hors_equipe',
  'un acheteur n''est pas de l''équipe');
update public.profils set actif = false where id = :EQUIPE::uuid;
select essai.egal(essai.envoyer(:EQUIPE::uuid, :S2::uuid, '222222') ->> 'raison', 'hors_equipe',
  'un compte désactivé non plus');
update public.profils set actif = true where id = :EQUIPE::uuid;

set role service_role;
select essai.egal(
  public.enregistrer_code_connexion(:ENSEIGNE::uuid, :S1::uuid, 'pas-une-empreinte') ->> 'raison',
  'requete', 'une empreinte qui n''en est pas une est refusée');
reset role;

select essai.egal((essai.envoyer(:ENSEIGNE::uuid, :S1::uuid, '123456') ->> 'ok')::boolean, true,
  'le superadministrateur reçoit un code');
select essai.egal(
  (select tel from public.codes_connexion where session_id = :S1::uuid and etat = 'envoye'),
  '0197000001', 'envoyé au numéro de SA fiche, jamais à un numéro tapé à la connexion');
select essai.verifie(
  (select code_hache from public.codes_connexion where session_id = :S1::uuid and etat = 'envoye')
    = essai.empreinte('123456', :S1::uuid)
  and not exists (select 1 from public.codes_connexion where code_hache like '%123456%'),
  'seule l''empreinte est gardée, jamais le code');

select essai.egal(essai.envoyer(:ENSEIGNE::uuid, :S1::uuid, '654321') ->> 'raison', 'trop_tot',
  'un second code dans les trente secondes : refusé');
select essai.verifie(
  (essai.envoyer(:ENSEIGNE::uuid, :S1::uuid, '654321') ->> 'attente')::int between 1 and 30,
  'et la réponse dit combien attendre');

select essai.reculer_codes(:ENSEIGNE::uuid, 40);
select essai.egal((essai.envoyer(:ENSEIGNE::uuid, :S1::uuid, '654321') ->> 'ok')::boolean, true,
  'passé le délai, un nouveau code part');
select essai.egal(
  (select count(*)::int from public.codes_connexion where session_id = :S1::uuid and etat = 'envoye'), 1,
  'un seul code vaut pour une session : le précédent a cédé');

-- Cinq par heure, pas un de plus.
select essai.reculer_codes(:ENSEIGNE::uuid, 40);
select essai.envoyer(:ENSEIGNE::uuid, :S1::uuid, '000003');
select essai.reculer_codes(:ENSEIGNE::uuid, 40);
select essai.envoyer(:ENSEIGNE::uuid, :S1::uuid, '000004');
select essai.reculer_codes(:ENSEIGNE::uuid, 40);
select essai.envoyer(:ENSEIGNE::uuid, :S1::uuid, '000005');
select essai.reculer_codes(:ENSEIGNE::uuid, 40);
select essai.egal(essai.envoyer(:ENSEIGNE::uuid, :S1::uuid, '000006') ->> 'raison', 'trop_de_codes',
  'un sixième code dans l''heure : refusé — chaque code est un SMS payé');

-- Un SMS qui n'est pas parti ne compte pas.
set role service_role;
select public.annuler_code_connexion(
  (select max(id) from public.codes_connexion where utilisateur = :ENSEIGNE::uuid));
reset role;
select essai.egal(
  (select etat from public.codes_connexion
    where id = (select max(id) from public.codes_connexion where utilisateur = :ENSEIGNE::uuid)),
  'annule', 'un envoi raté s''annule');
select essai.reculer_codes(:ENSEIGNE::uuid, 40);
select essai.egal((essai.envoyer(:ENSEIGNE::uuid, :S1::uuid, '424242') ->> 'ok')::boolean, true,
  'et rend sa place dans l''heure');

-- L'heure passée, le compteur repart.
select essai.reculer_codes(:ENSEIGNE::uuid, 3700);
select essai.egal((essai.envoyer(:ENSEIGNE::uuid, :S1::uuid, '135790') ->> 'ok')::boolean, true,
  'une heure plus tard, on peut de nouveau en demander');

-- ---------------------------------------------------------
select essai.titre('Rendre le code');

select essai.devenir(:ENSEIGNE::uuid, :S1::uuid); set role authenticated;
select essai.egal(public.confirmer_code_connexion('000000') ->> 'raison', 'code_faux',
  'un code faux est refusé');
select essai.egal((public.confirmer_code_connexion('000001') ->> 'restants')::int, 3,
  'et le compte des essais restants descend');
reset role;
select essai.egal(
  (select essais from public.codes_connexion where session_id = :S1::uuid and etat = 'envoye'), 2,
  'les essais manqués RESTENT comptés : une erreur levée les aurait effacés');

-- Le bon code, mais dans une AUTRE session : il n'ouvre rien.
select essai.devenir(:ENSEIGNE::uuid, :S3::uuid); set role authenticated;
select essai.egal(public.confirmer_code_connexion('135790') ->> 'raison', 'sans_code',
  'le code d''une session n''ouvre pas une autre session');
reset role;

-- Un jeton sans session — une clé, un vieux jeton — ne confirme rien.
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal(public.confirmer_code_connexion('135790') ->> 'raison', 'sans_session',
  'un jeton sans session ne confirme rien');
reset role;

select essai.devenir(:ENSEIGNE::uuid, :S1::uuid); set role authenticated;
select essai.egal((public.confirmer_code_connexion(' 135 790 ') ->> 'ok')::boolean, true,
  'le bon code, tapé avec des espaces, confirme la session');
select essai.egal((public.confirmer_code_connexion('135790') ->> 'deja')::boolean, true,
  'le rendre deux fois ne fait pas une panne');
select essai.verifie(public.session_confirmee(), 'la session est confirmée');
reset role;
select essai.verifie(
  (select tel_verifie and tel_verifie_le is not null from public.profils where id = :ENSEIGNE::uuid),
  'et le numéro de la fiche est vérifié : on y a reçu le code');

-- Cinq codes faux et le code ne vaut plus rien.
select essai.envoyer(:CHEF::uuid, :S4::uuid, '246810');
select essai.devenir(:CHEF::uuid, :S4::uuid); set role authenticated;
select public.confirmer_code_connexion('000001');
select public.confirmer_code_connexion('000002');
select public.confirmer_code_connexion('000003');
select public.confirmer_code_connexion('000004');
select essai.egal((public.confirmer_code_connexion('000005') ->> 'restants')::int, 0,
  'au cinquième code faux, il ne reste plus d''essai');
select essai.egal(public.confirmer_code_connexion('246810') ->> 'raison', 'sans_code',
  'et même le bon code n''ouvre plus rien : il faut en redemander un');
reset role;

-- Un code expiré.
select essai.reculer_codes(:CHEF::uuid, 40);
select essai.envoyer(:CHEF::uuid, :S4::uuid, '112233');
select essai.reculer_codes(:CHEF::uuid, 660);
select essai.devenir(:CHEF::uuid, :S4::uuid); set role authenticated;
select essai.egal(public.confirmer_code_connexion('112233') ->> 'raison', 'expire',
  'un code de plus de dix minutes est expiré');
reset role;

-- Le numéro change entre l'envoi et la saisie : la session s'ouvre, mais
-- le NOUVEAU numéro n'est pas vérifié — c'est l'ancien qui a reçu le code.
select essai.envoyer(:PORTEUR::uuid, :S5::uuid, '998877');
update public.profils set tel = '0197999999' where id = :PORTEUR::uuid;
select essai.devenir(:PORTEUR::uuid, :S5::uuid); set role authenticated;
select essai.egal((public.confirmer_code_connexion('998877') ->> 'ok')::boolean, true,
  'le code ouvre la session');
reset role;
select essai.verifie(not (select tel_verifie from public.profils where id = :PORTEUR::uuid),
  'mais le numéro changé entre-temps n''est pas vérifié pour autant');

-- ---------------------------------------------------------
select essai.titre('L''interrupteur');

select essai.devenir(:CHEF::uuid, :S6::uuid); set role authenticated;
select essai.refuse('select public.regler_sms_equipe(true)',
  'un administrateur de boutique ne l''allume pas');
reset role;

select essai.devenir(:ENSEIGNE::uuid, :S2::uuid); set role authenticated;
select essai.refuse('select public.regler_sms_equipe(true)',
  'le superadministrateur non plus, tant qu''il n''a pas lui-même rendu son code');
reset role;

select essai.devenir(:ENSEIGNE::uuid, :S1::uuid); set role authenticated;
select essai.verifie(public.regler_sms_equipe(true),
  'avec sa session confirmée, il l''allume');
reset role;
select essai.verifie(public.sms_equipe_exige(), 'l''enseigne exige le code');
select essai.verifie(
  exists (select 1 from public.journal
           where libelle like 'Connexion de l''équipe : code SMS exigé%'),
  'et le journal le dit');

-- ---------------------------------------------------------
select essai.titre('Quand l''enseigne l''exige, la base ferme');

select essai.devenir(:ENSEIGNE::uuid, :S1::uuid); set role authenticated;
select essai.verifie(public.est_super(), 'session confirmée : le superadministrateur garde tout');
reset role;

select essai.devenir(:ENSEIGNE::uuid, :S2::uuid); set role authenticated;
select essai.verifie(not public.est_super(),
  'le même compte, dans une AUTRE session sans code : plus superadministrateur');
select essai.verifie(public.role_courant() is null, 'aucun rang du tout');
select essai.egal((public.etat_connexion() ->> 'session_confirmee')::boolean, false,
  'l''état de la connexion le dit, pour que l''écran demande le code');
select essai.egal(public.etat_connexion() ->> 'fin_numero', '01',
  'avec les deux derniers chiffres du numéro, rien de plus');
select essai.egal(
  (select count(*)::int from public.profils), 1,
  'il ne lit plus que sa propre fiche');
reset role;

select essai.devenir(:CHEF::uuid, :S6::uuid); set role authenticated;
select essai.verifie(not public.est_admin(), 'l''administrateur sans code : plus administrateur');
select essai.verifie(public.boutique_du_compte() is null, 'plus de boutique');
select essai.verifie(not public.peut_agir_sur('bou_informatique'),
  'plus aucune prise sur sa boutique');
select essai.sans_effet(
  'update public.produits set nom = nom || '' (piraté)'' where boutique_id = ''bou_informatique''',
  'son catalogue ne se modifie plus');
select essai.egal((select count(*)::int from public.commandes), 0,
  'ses commandes ne se lisent plus');
select essai.egal((select count(*)::int from public.journal), 0,
  'ni le journal');
reset role;

select essai.devenir(:ADJOINT::uuid, :S6::uuid); set role authenticated;
select essai.verifie(not public.est_compte_enseigne(),
  'le compte de BIZZOO sans code n''est plus compte de BIZZOO');
select essai.verifie(not public.droit_enseigne('commandes'),
  'ses interrupteurs ne valent plus rien');
select essai.verifie(not public.peut_voir_commandes(),
  'les commandes de toutes les boutiques lui sont fermées');
reset role;

select essai.devenir(:PORTEUR::uuid, :S6::uuid); set role authenticated;
select essai.verifie(not public.est_livreur(), 'le livreur sans code : plus livreur');
select essai.egal((select count(*)::int from public.mes_livraisons()), 0,
  'ses courses ne se lisent plus');
reset role;

select essai.devenir(:PORTEUR::uuid, :S5::uuid); set role authenticated;
select essai.verifie(public.est_livreur(),
  'dans la session où il a rendu son code, il porte toujours');
reset role;

-- Le code rendu, tout revient.
select essai.envoyer(:CHEF::uuid, :S7::uuid, '777777');
select essai.devenir(:CHEF::uuid, :S7::uuid); set role authenticated;
select essai.verifie(not public.est_admin(), 'code demandé mais pas rendu : toujours rien');
select essai.egal((public.confirmer_code_connexion('777777') ->> 'ok')::boolean, true,
  'le code rendu');
select essai.verifie(public.est_admin(), 'l''administrateur retrouve ses droits');
select essai.egal(public.boutique_du_compte(), 'bou_informatique', 'et sa boutique');
reset role;

-- Un acheteur n'est pas concerné : il n'a pas de rang à perdre.
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.clients where id = :ACHETEUR::uuid), 1,
  'l''acheteur lit toujours sa fiche');
select essai.egal((public.etat_connexion() ->> 'equipe')::boolean, false,
  'et l''état de la connexion le dit hors de l''équipe');
reset role;

-- L'éteindre demande, lui aussi, une session confirmée.
select essai.devenir(:ENSEIGNE::uuid, :S2::uuid); set role authenticated;
select essai.refuse('select public.regler_sms_equipe(false)',
  'une session sans code ne l''éteint pas');
reset role;
select essai.devenir(:ENSEIGNE::uuid, :S1::uuid); set role authenticated;
select essai.egal(public.regler_sms_equipe(false), false,
  'la session confirmée l''éteint');
reset role;
select essai.devenir(:ENSEIGNE::uuid, :S2::uuid); set role authenticated;
select essai.verifie(public.est_super(), 'et toute session retrouve ses droits');
reset role;

-- ---------------------------------------------------------
select essai.titre('Qui a créé le compte : la base l''écrit');

-- « Créer un compte », comme le fait l'application : l'inscription pose
-- une fiche en attente, et l'administrateur lui donne aussitôt son rang.
-- L'inscription arrive sans jeton : GoTrue n'en porte aucun.
select essai.personne();
insert into auth.users (id, email) values (:NOUVEAU::uuid, 'nouveau@bizzoo.bj');
select essai.egal(
  (select cree_par from public.profils where id = :NOUVEAU::uuid), null::uuid,
  'la fiche en attente n''a pas encore de créateur');
select essai.devenir(:ENSEIGNE::uuid, :S1::uuid); set role authenticated;
insert into public.profils (id, email, role, actif, boutique_id, nom, tel)
values (:NOUVEAU::uuid, 'nouveau@bizzoo.bj', 'moderateur', true, 'bou_informatique',
        'Nouveau', '0197000010')
on conflict (id) do update
   set email = excluded.email, role = excluded.role, actif = excluded.actif,
       boutique_id = excluded.boutique_id, nom = excluded.nom, tel = excluded.tel;
reset role;
select essai.egal((select cree_par from public.profils where id = :NOUVEAU::uuid),
  :ENSEIGNE::uuid, 'le créateur est celui qui a donné son rang à la fiche');
select essai.egal((select cree_par_nom from public.profils where id = :NOUVEAU::uuid),
  'Enseigne (superadministrateur)', 'son nom, figé au moment de la création');
select essai.verifie(
  (select cree_le > now() - interval '1 minute' from public.profils where id = :NOUVEAU::uuid),
  'avec la date et l''heure');

-- L'administrateur d'une boutique crée un modérateur chez lui.
-- L'inscription arrive sans jeton : GoTrue n'en porte aucun.
select essai.personne();
insert into auth.users (id, email) values (:RECRUE::uuid, 'recrue@bizzoo.bj');
select essai.devenir(:CHEF::uuid, :S7::uuid); set role authenticated;
insert into public.profils (id, email, role, actif, boutique_id, nom, tel)
values (:RECRUE::uuid, 'recrue@bizzoo.bj', 'moderateur', true, 'bou_informatique',
        'Recrue', '0197000011')
on conflict (id) do update
   set role = excluded.role, actif = excluded.actif,
       boutique_id = excluded.boutique_id, nom = excluded.nom, tel = excluded.tel;
reset role;
select essai.egal((select cree_par from public.profils where id = :RECRUE::uuid),
  :CHEF::uuid, 'un administrateur de boutique est nommé quand il crée un modérateur');

-- Ce qui ne se déclare pas.
select essai.devenir(:ENSEIGNE::uuid, :S1::uuid); set role authenticated;
select essai.refuse(
  format('update public.profils set cree_par = %L::uuid where id = %L::uuid', :CHEF, :NOUVEAU),
  'le créateur ne se réécrit pas, même par le superadministrateur');
select essai.refuse(
  format('update public.profils set cree_par_nom = ''Personne'' where id = %L::uuid', :NOUVEAU),
  'son nom non plus');
select essai.refuse(
  format('update public.profils set cree_le = now() - interval ''1 year'' where id = %L::uuid', :NOUVEAU),
  'ni la date');
select essai.refuse(
  format('update public.profils set tel_verifie = true where id = %L::uuid', :NOUVEAU),
  'un numéro ne se déclare pas vérifié');
reset role;

-- L'ANNULATION D'UNE MODIFICATION, comme la fait l'Historique : la fiche
-- d'avant revient ENTIÈRE, par un upsert — trace et vérification
-- comprises. L'insertion passe d'abord par la règle de création ; si
-- celle-ci y nommait le créateur du moment, toute annulation échouerait
-- sur « la création ne se réécrit pas ».
create temp table fiche_avant as select * from public.profils where id = :NOUVEAU::uuid;
grant select on fiche_avant to authenticated;
select essai.devenir(:ENSEIGNE::uuid, :S1::uuid); set role authenticated;
update public.profils set nom = 'Renommé' where id = :NOUVEAU::uuid;
insert into public.profils select * from fiche_avant
on conflict (id) do update
   set nom = excluded.nom,
       cree_par = excluded.cree_par, cree_par_nom = excluded.cree_par_nom,
       cree_le = excluded.cree_le, tel_verifie = excluded.tel_verifie,
       tel_verifie_le = excluded.tel_verifie_le;
reset role;
select essai.verifie(
  (select p.nom = 'Nouveau' and p.cree_par = f.cree_par and p.cree_par_nom = f.cree_par_nom
          and p.cree_le = f.cree_le
     from public.profils p, fiche_avant f where p.id = :NOUVEAU::uuid),
  'annuler une modification remet la fiche d''avant, sa trace telle quelle');
select essai.devenir(:ENSEIGNE::uuid, :S1::uuid); set role authenticated;
select essai.refuse(
  format('insert into public.profils (id, email, cree_par) values (%L::uuid, ''nouveau@bizzoo.bj'', %L::uuid)
          on conflict (id) do update set cree_par = %L::uuid', :NOUVEAU, :CHEF, :CHEF),
  'mais un upsert qui ÉCRIT un autre créateur reste refusé');
reset role;
drop table fiche_avant;

-- Une fiche insérée d'un coup, avec un créateur inventé : la base
-- l'ignore, et nomme celui qui l'a réellement posée.
select essai.personne();
insert into auth.users (id, email) values (:FORGE::uuid, 'forge@bizzoo.bj');
delete from public.profils where id = :FORGE::uuid;
select essai.devenir(:ENSEIGNE::uuid, :S1::uuid); set role authenticated;
insert into public.profils (id, email, role, actif, boutique_id, cree_par, cree_par_nom,
                            tel, tel_verifie)
values (:FORGE::uuid, 'forge@bizzoo.bj', 'moderateur', true, 'bou_informatique',
        :CHEF::uuid, 'Quelqu''un d''autre', '0197000012', true);
reset role;
select essai.egal((select cree_par from public.profils where id = :FORGE::uuid), :ENSEIGNE::uuid,
  'un créateur inventé dans la requête est remplacé par le vrai');
select essai.verifie(
  (select cree_par_nom = 'Enseigne (superadministrateur)' and not tel_verifie
     from public.profils where id = :FORGE::uuid),
  'son nom aussi, et le numéro n''arrive pas déjà vérifié');

-- Changer de numéro annule la vérification.
select essai.verifie((select tel_verifie from public.profils where id = :ENSEIGNE::uuid),
  'le numéro du superadministrateur est vérifié');
select essai.devenir(:ENSEIGNE::uuid, :S1::uuid); set role authenticated;
update public.profils set tel = '0197000099' where id = :ENSEIGNE::uuid;
reset role;
select essai.verifie(
  (select not tel_verifie and tel_verifie_le is null from public.profils where id = :ENSEIGNE::uuid),
  'un autre numéro n''est plus le numéro vérifié');

-- Une inscription réveillée des jours plus tard n'a pas de créateur.
-- L'inscription arrive sans jeton : GoTrue n'en porte aucun.
select essai.personne();
insert into auth.users (id, email) values (:INSCRIT::uuid, 'inscrit-seul@bizzoo.bj');
begin;
select set_config('bizzoo.compte', 'oui', true);
update public.profils set cree_le = now() - interval '3 days' where id = :INSCRIT::uuid;
commit;
select essai.devenir(:ENSEIGNE::uuid, :S1::uuid); set role authenticated;
update public.profils set actif = true, role = 'moderateur', boutique_id = 'bou_informatique'
 where id = :INSCRIT::uuid;
reset role;
select essai.egal((select cree_par from public.profils where id = :INSCRIT::uuid), null::uuid,
  'activer un compte inscrit seul, des jours après, n''en fait pas son créateur');

-- ---------------------------------------------------------
select essai.titre('Les comptes d''avant : le journal s''en souvient');

begin;
select set_config('bizzoo.compte', 'oui', true);
update public.profils set cree_par = null, cree_par_nom = ''
 where id in (:RECRUE::uuid, :SANSNUM::uuid);
commit;

-- Le journal signe lui-même chaque ligne du nom du compte connecté :
-- les lignes s'écrivent donc depuis le compte de leur auteur. Un
-- second superadministrateur écrit l'une, puis son compte disparaît.
select essai.personne();
insert into auth.users (id, email) values (:PARTI::uuid, 'parti@bizzoo.bj');
update public.profils set role = 'superadministrateur', actif = true where id = :PARTI::uuid;

select essai.devenir(:CHEF::uuid);
insert into public.journal (famille, action, libelle, cible)
values ('compte', 'ajout', 'Modérateur ajouté : recrue@bizzoo.bj', 'recrue@bizzoo.bj');
select essai.devenir(:PARTI::uuid);
insert into public.journal (famille, action, libelle, cible)
values ('compte', 'ajout', 'Modérateur ajouté : sans-numero@bizzoo.bj', 'sans-numero@bizzoo.bj');
select essai.personne();
delete from auth.users where id = :PARTI::uuid;
select essai.egal(
  (select utilisateur from public.journal where cible = 'sans-numero@bizzoo.bj'),
  'parti@bizzoo.bj', 'le journal garde l''adresse d''un compte disparu');

select essai.egal(public.rattraper_createurs(), 2, 'deux comptes retrouvent leur créateur');
select essai.egal((select cree_par from public.profils where id = :RECRUE::uuid), :CHEF::uuid,
  'le créateur est reconnu à son adresse');
select essai.verifie(
  (select cree_par_nom like '%(administrateur)' from public.profils where id = :RECRUE::uuid),
  'avec son nom et son rang');
select essai.egal((select cree_par_nom from public.profils where id = :SANSNUM::uuid),
  'parti@bizzoo.bj',
  'un créateur dont le compte a disparu garde au moins son adresse');
select essai.egal(public.rattraper_createurs(), 0,
  'relancé, le rattrapage ne touche plus rien');
select essai.egal((select cree_par from public.profils where id = :NOUVEAU::uuid), :ENSEIGNE::uuid,
  'et n''écrase jamais une trace déjà posée');

-- ---------------------------------------------------------
select essai.titre('Les droits des fonctions');

select essai.verifie(not has_function_privilege('authenticated',
  'public.enregistrer_code_connexion(uuid, uuid, text)', 'execute'),
  'inscrire un code : pas pour un compte connecté');
select essai.verifie(has_function_privilege('service_role',
  'public.enregistrer_code_connexion(uuid, uuid, text)', 'execute'),
  'mais pour la clé de service');
select essai.verifie(not has_function_privilege('anon',
  'public.regler_sms_equipe(boolean)', 'execute'),
  'l''interrupteur n''est pas ouvert aux visiteurs');
select essai.verifie(not has_function_privilege('authenticated',
  'public.rattraper_createurs()', 'execute'),
  'le rattrapage n''est pas ouvert aux comptes');

-- Le décor rendu tel qu'on l'a trouvé : l'interrupteur éteint.
update public.securite_equipe set sms_exige = false;
select essai.personne();
