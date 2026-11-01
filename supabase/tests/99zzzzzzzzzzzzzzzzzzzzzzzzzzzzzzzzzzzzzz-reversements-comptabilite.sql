-- =========================================================
-- Les reversements dans BIZZOO Personnel : le CEO et la comptabilité (3.73.0)
--
-- Ce qu'on prouve :
--   1. le profil « Comptabilité » existe, marqué, vide au départ ;
--   2. l'administration ne voit ni ne tranche les demandes, et ne peut
--      ni marquer un profil « comptabilité » ni y placer quelqu'un ;
--   3. le CEO y place un employé : celui-ci voit les trois listes, lit
--      le nom MoMo des livreurs et tranche — sous son nom d'employé ;
--   4. sorti du profil (par le CEO seul), il n'y a plus accès.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set ADMRH    '''a0a0a0a0-0001-4000-8000-000000000001'''
\set COMPTA   '''a0a0a0a0-0021-4000-8000-000000000021'''

select essai.titre('1. Le profil « Comptabilité », posé et vide');
select id as p_compta from public.rh_profils where lower(nom) = lower('Comptabilité') \gset
select essai.verifie((select comptabilite from public.rh_profils where id = :'p_compta'),
  'le profil Comptabilité existe et traite les reversements');
select essai.egal((select count(*)::int from public.rh_employes where profil_id = :'p_compta'), 0,
  'personne dedans au départ : le CEO y placera le comptable');
select essai.egal((select count(*)::int from public.rh_profils where comptabilite), 1,
  'aucun autre profil n''est marqué');

select essai.titre('Le décor : une demande d''un livreur, son nom MoMo');
select id as livreur from public.profils where role = 'livreur' order by id limit 1 \gset
update public.profils set momo_nom = 'KOFFI Titulaire' where id = :'livreur';
insert into public.reversements_livreurs (livreur_id, nom_livreur, montant, tel, reseau, titulaire, etat)
values (:'livreur', 'Livreur compta', 1500, '0197000021', 'MTN', 'KOFFI Titulaire', 'en_attente')
returning id as dem \gset
insert into public.reversements (boutique_id, montant, tel, reseau, etat, demande_par)
select 'bou_informatique', 1000, '0197000022', 'MTN', 'en_attente', 'Chef'
 where not exists (select 1 from public.reversements where etat = 'en_attente');
insert into auth.users (id, email, raw_user_meta_data)
values (:COMPTA::uuid, 'comptable@bizzoomarket.com', '{"compte":"personnel"}') on conflict do nothing;

select essai.titre('2. L''administration : ni voir, ni trancher, ni s''y placer');
select essai.devenir(:ADMRH::uuid); set role authenticated;
select essai.verifie(public.rh_est_admin() and not public.est_super(),
  'le décor : un compte de l''administration, pas superadministrateur');
select essai.verifie(not public.rh_reversements_acces(), 'l''administration n''a pas l''accès');
select essai.egal((select count(*)::int from public.reversements_liste(null)), 0,
  'elle ne lit pas les demandes des boutiques');
select essai.egal((select count(*)::int from public.reversements_livreurs_liste()), 0,
  'ni celles des livreurs');
select essai.egal((select count(*)::int from public.noms_momo(array[:'livreur']::uuid[])), 0,
  'ni le nom MoMo des livreurs');
select essai.refuse(format($$select public.decider_reversement_livreur(%s, true, 'MP-0021')$$, :dem),
  'elle ne tranche pas');
select essai.refuse(format($$update public.rh_profils set comptabilite = true where nom = 'Marketing'$$),
  'elle ne marque pas un autre profil « comptabilité »');
select essai.refuse(format($$insert into public.rh_employes (nom, prenoms, sexe, email_pro, date_embauche, statut, salaire_base, profil_id)
  values ('INTRUS', 'X', 'M', 'intrus@bizzoomarket.com', '2026-10-01', 'employe', 1, %L)$$, :'p_compta'),
  'elle n''y place pas un employé');
select essai.refuse(format($$update public.rh_employes set profil_id = %L where compte_id = auth.uid()$$, :'p_compta'),
  'ni elle-même');
reset role; select essai.personne();

select essai.titre('3. Le CEO y place le comptable : il voit et tranche');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.verifie(public.rh_est_ceo() and public.rh_reversements_acces(), 'le CEO a l''accès');
insert into public.rh_employes (nom, prenoms, sexe, email_pro, date_embauche, statut, salaire_base, profil_id)
values ('ZINSOU', 'Comptable', 'F', 'comptable@bizzoomarket.com', '2026-10-01', 'employe', 200000, :'p_compta')
returning id as e_compta \gset
select public.rh_rattacher_compte(:'e_compta') \gset
reset role; select essai.personne();

select essai.devenir(:COMPTA::uuid); set role authenticated;
select essai.verifie(not public.est_super() and not public.rh_est_ceo() and public.rh_reversements_acces(),
  'le comptable, ni CEO ni superadministrateur, a l''accès');
select essai.verifie((select count(*) from public.reversements_liste(null)) > 0, 'il lit les demandes des boutiques');
select essai.verifie(exists (select 1 from public.reversements_livreurs_liste() where id = :dem),
  'il lit celles des livreurs');
select essai.egal((select momo_nom from public.noms_momo(array[:'livreur']::uuid[])), 'KOFFI Titulaire',
  'et le nom du compte MoMo du livreur');
select essai.refuse(format($$update public.rh_employes set profil_id = null where id = %L$$, :'e_compta'),
  'il ne sort pas lui-même du profil');
select essai.egal(public.decider_reversement_livreur(:dem, true, 'MP-0021'), 'valide', 'il valide l''envoi');
reset role; select essai.personne();
select essai.egal((select decide_par from public.reversements_livreurs where id = :dem), 'Comptable ZINSOU',
  'la décision porte son nom d''employé');

select essai.titre('4. Sorti du profil par le CEO : plus d''accès');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select id as p_autre from public.rh_profils where not comptabilite order by nom limit 1 \gset
update public.rh_employes set profil_id = :'p_autre' where id = :'e_compta';
reset role; select essai.personne();
select essai.devenir(:COMPTA::uuid); set role authenticated;
select essai.verifie(not public.rh_reversements_acces(), 'hors du profil : plus d''accès');
select essai.egal((select count(*)::int from public.reversements_livreurs_liste()), 0, 'plus de liste');
reset role; select essai.personne();
