-- =========================================================
-- (3.70.0) Les préfixes des opérateurs, réglables sans mise à jour
--
--   1. la liste de départ est là (38 préfixes), lisible sans compte ;
--   2. personne d'autre que le superadmin n'y écrit — ni par la
--      fonction, ni dans la table ;
--   3. le superadmin ajoute (« 0130 » ou « 30 »), réattribue, retire ;
--   4. une saisie fausse est refusée, avec un message clair.
-- =========================================================
\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''

select essai.titre('1. La liste de départ, lisible sans compte');
set role anon;
select essai.egal((select count(*)::int from public.prefixes_operateurs), 38,
  'un visiteur lit les 38 préfixes (le client paie sans compte)');
select essai.egal((select operateur from public.prefixes_operateurs where prefixe = '97'),
  'MTN', '97 : MTN');
select essai.egal((select operateur from public.prefixes_operateurs where prefixe = '94'),
  'MOOV', '94 : Moov (l''ancienne table du client le donnait à MTN)');
select essai.egal((select operateur from public.prefixes_operateurs where prefixe = '40'),
  'CELTIIS', '40 : Celtiis');

select essai.titre('2. Personne d''autre que le superadmin n''y écrit');
select essai.refuse($$select public.regler_prefixe_operateur('30', 'MTN')$$,
  'un visiteur ajoute un préfixe');
select essai.refuse($$insert into public.prefixes_operateurs (prefixe, operateur) values ('30', 'MTN')$$,
  'ou l''écrit dans la table');
reset role;
select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.refuse($$select public.regler_prefixe_operateur('30', 'MTN')$$,
  'un administrateur de boutique ajoute un préfixe');
select essai.refuse($$update public.prefixes_operateurs set operateur = 'MOOV' where prefixe = '97'$$,
  'ou réattribue celui d''un autre dans la table');
select essai.refuse($$delete from public.prefixes_operateurs where prefixe = '97'$$,
  'ou en efface un');
reset role;
select essai.personne();
select essai.egal((select operateur from public.prefixes_operateurs where prefixe = '97'),
  'MTN', 'et 97 est toujours MTN');

select essai.titre('3. Le superadmin ajoute, réattribue, retire');
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.egal(public.regler_prefixe_operateur('01 30', 'mtn'),
  '{"prefixe": "30", "operateur": "MTN"}'::jsonb, '« 01 30 » + « mtn » : 30 → MTN');
select essai.egal(public.regler_prefixe_operateur('30', 'Celtiis'),
  '{"prefixe": "30", "operateur": "CELTIIS"}'::jsonb, 'réattribué à Celtiis');
select essai.egal((select operateur from public.prefixes_operateurs where prefixe = '30'),
  'CELTIIS', 'la table le dit');
select essai.egal(public.regler_prefixe_operateur('30', ''),
  '{"prefixe": "30", "operateur": null}'::jsonb, 'retiré (opérateur vide)');
select essai.egal((select count(*)::int from public.prefixes_operateurs where prefixe = '30'), 0,
  'il n''est plus dans la liste');

select essai.titre('4. Une saisie fausse est refusée');
select essai.refuse($$select public.regler_prefixe_operateur('3', 'MTN')$$, 'un seul chiffre');
select essai.refuse($$select public.regler_prefixe_operateur('0230', 'MTN')$$, 'quatre chiffres sans « 01 »');
select essai.refuse($$select public.regler_prefixe_operateur('30', 'Orange')$$, 'un opérateur inconnu');
reset role;
select essai.personne();
select essai.egal((select count(*)::int from public.prefixes_operateurs), 38,
  'à la fin, la liste de départ, intacte');
