-- =========================================================
-- Le live TikTok
--
-- Ce qu'on prouve :
--   1. seul l'administrateur de la boutique (ou l'enseigne) lance son
--      live — pas un modérateur, pas un client, pas un visiteur ;
--   2. sans compte TikTok, ou boutique fermée : refusé, en le disant ;
--   3. le lien est celui de la page TikTok de la boutique ;
--   4. un live en cours ne se relance pas (« deja ») : pas de seconde
--      notification ; trois lives par jour au plus ;
--   5. tout le monde voit les lives en cours, et rien de qui les lance ;
--   6. seule la clé de service note l'annonce.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set EQUIPE   '''33333333-3333-3333-3333-333333333333'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''

select essai.titre('Le décor : la boutique sans compte TikTok');
update public.boutiques set tiktok = '', actif = true where id = 'bou_informatique';
delete from public.lives_tiktok;

-- ---------------------------------------------------------
select essai.titre('1 et 2. Qui lance, et à quelle condition');

select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse($$select public.demarrer_live('bou_informatique')$$,
  'sans compte TikTok : refusé');
reset role; select essai.personne();

update public.boutiques set tiktok = '@impact.bj' where id = 'bou_informatique';
select essai.egal(public.lien_tiktok('@impact.bj'), 'https://www.tiktok.com/@impact.bj',
  'un « @nom » devient la page TikTok');
select essai.egal(public.lien_tiktok('https://vm.tiktok.com/ZM123/'), 'https://vm.tiktok.com/ZM123/',
  'une adresse complète reste telle quelle');

select essai.devenir(:EQUIPE::uuid); set role authenticated;
select essai.refuse($$select public.demarrer_live('bou_informatique')$$,
  'un modérateur d''une autre boutique : refusé');
reset role; select essai.personne();

select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.refuse($$select public.demarrer_live('bou_informatique')$$, 'un client : refusé');
reset role; select essai.personne();

set role anon;
select essai.refuse($$select public.demarrer_live('bou_informatique')$$, 'un visiteur : refusé');
reset role;

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set actif = false where id = 'bou_informatique';
reset role; select essai.personne();
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse($$select public.demarrer_live('bou_informatique')$$,
  'boutique fermée aux clients : refusé');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set actif = true where id = 'bou_informatique';
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('3 et 4. Le live, une seule notification');

select essai.devenir(:CHEF::uuid); set role authenticated;
select public.demarrer_live('bou_informatique') as l1 \gset
reset role; select essai.personne();
select essai.egal((:'l1'::jsonb ->> 'lien'), 'https://www.tiktok.com/@impact.bj',
  'le live porte le lien TikTok de la boutique');
select essai.verifie(not (:'l1'::jsonb ->> 'deja')::boolean, 'un nouveau live : à annoncer');
select essai.egal((select lance_par from public.lives_tiktok where id = (:'l1'::jsonb ->> 'id')::bigint),
  :CHEF::uuid, 'on sait qui l''a lancé');

select essai.devenir(:CHEF::uuid); set role authenticated;
select public.demarrer_live('bou_informatique') as l2 \gset
reset role; select essai.personne();
select essai.verifie((:'l2'::jsonb ->> 'deja')::boolean and
  (:'l2'::jsonb ->> 'id') = (:'l1'::jsonb ->> 'id'),
  'relancé pendant qu''il dure : le même live, sans nouvelle annonce');

-- ---------------------------------------------------------
select essai.titre('5. Tout le monde voit les lives en cours');

set role anon;
select essai.egal((select count(*)::int from public.lives_en_cours()
  where boutique_id = 'bou_informatique'), 1, 'un visiteur voit le live');
select essai.refuse($$select lance_par from public.lives_tiktok$$,
  'mais pas la table, ni qui l''a lancé');
reset role;

select essai.devenir(:EQUIPE::uuid); set role authenticated;
select essai.refuse($$select public.arreter_live('bou_informatique')$$,
  'une autre boutique ne l''arrête pas');
reset role; select essai.personne();

select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.egal(public.arreter_live('bou_informatique'), 1, 'l''administrateur l''arrête');
reset role; select essai.personne();
set role anon;
select essai.egal((select count(*)::int from public.lives_en_cours()
  where boutique_id = 'bou_informatique'), 0, 'arrêté : il disparaît');
reset role;

-- Un live oublié s'éteint de lui-même.
insert into public.lives_tiktok (boutique_id, lien, debut)
values ('bou_essai_voisine', 'https://www.tiktok.com/@voisine', now() - interval '5 hours');
select essai.egal((select count(*)::int from public.lives_en_cours()
  where boutique_id = 'bou_essai_voisine'), 0, 'un live de plus de quatre heures n''est plus montré');

-- Trois par jour au plus.
select essai.devenir(:CHEF::uuid); set role authenticated;
select public.demarrer_live('bou_informatique') as l3 \gset
select public.arreter_live('bou_informatique') as a3 \gset
select public.demarrer_live('bou_informatique') as l4 \gset
select public.arreter_live('bou_informatique') as a4 \gset
select essai.refuse($$select public.demarrer_live('bou_informatique')$$,
  'un quatrième live dans la journée : refusé');
reset role; select essai.personne();

-- L'enseigne, elle, lance le live de n'importe quelle boutique.
update public.boutiques set tiktok = 'voisine' where id = 'bou_essai_voisine';
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.verifie(
  (public.demarrer_live('bou_essai_voisine') ->> 'lien') = 'https://www.tiktok.com/@voisine',
  'le superadministrateur lance le live d''une boutique');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('6. Noter l''annonce : la clé de service seule');

select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse(format($$select public.noter_annonce_live(%s, 'faux')$$, :'l1'::jsonb ->> 'id'),
  'un administrateur ne note pas une annonce');
reset role; select essai.personne();
set role service_role;
select public.noter_annonce_live((:'l1'::jsonb ->> 'id')::bigint, 'envoyée') as n \gset
reset role;
select essai.egal((select annonce from public.lives_tiktok where id = (:'l1'::jsonb ->> 'id')::bigint),
  'envoyée', 'la fonction Edge note la réponse de Firebase');
