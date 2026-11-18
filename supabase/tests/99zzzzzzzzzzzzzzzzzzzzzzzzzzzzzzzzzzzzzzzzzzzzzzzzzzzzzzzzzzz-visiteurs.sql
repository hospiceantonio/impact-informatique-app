-- =========================================================
-- Les visiteurs de la boutique (4.6.0)
--
-- Ce qu'on prouve :
--   1. un visiteur, sans compte, note sa visite ; elle dure, ses écrans
--      s'ajoutent, le panier et la commande se retiennent ;
--   2. les fiches ouvertes se comptent, par jour — et une fiche qui
--      n'existe pas ne se compte pas ;
--   3. ce qui est mal formé ne s'écrit pas ; la visite d'un autre ne se
--      reprend pas ;
--   4. personne ne lit les tables ; les totaux sont au
--      superadministrateur, pas à un visiteur ni à un modérateur ;
--   5. les totaux : visiteurs, visites, panier, commande, classements.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set SUP   '''dedede00-0000-0000-0000-000000000001'''
\set MODO  '''dedede00-0000-0000-0000-000000000002'''

select essai.titre('Le décor : une boutique, deux produits, un superadministrateur, un modérateur');
insert into public.boutiques (id, nom, secteur, devise, actif, ordre) values ('bou_vis', 'BOUTIQUE VISITÉE', 'Essai', 'FCFA', true, 99)
on conflict (id) do nothing;
insert into public.produits (id, boutique_id, nom, prix) values ('p_vis1', 'bou_vis', 'Produit vu', 1000), ('p_vis2', 'bou_vis', 'Produit peu vu', 1000)
on conflict (id) do nothing;
insert into auth.users (id, email) values (:SUP::uuid, 'sup.visiteurs@essai.bj'), (:MODO::uuid, 'modo.visiteurs@essai.bj') on conflict do nothing;
select set_config('bizzoo.compte', 'oui', false) \gset
update public.profils set role = 'superadministrateur', actif = true, boutique_id = null where id = :SUP::uuid;
update public.profils set role = 'moderateur', actif = true, boutique_id = 'bou_vis' where id = :MODO::uuid;
select set_config('bizzoo.compte', '', false) \gset

select essai.titre('1. Un visiteur, sans compte, note sa visite');
set role anon;
select public.noter_visite('visiteuraaaaaaaa', 'sessionaaaaaaaaa', 'web', 1, '[{"g":"produit","c":"p_vis1"},{"g":"boutique","c":"bou_vis"}]'::jsonb, false, false);
select public.noter_visite('visiteuraaaaaaaa', 'sessionaaaaaaaaa', 'web', 2, '[{"g":"produit","c":"p_vis1"},{"g":"produit","c":"p_vis2"},{"g":"produit","c":"p_inconnu"}]'::jsonb, true, false);
select public.noter_visite('visiteuraaaaaaaa', 'sessionaaaaaaaaa', 'web', 0, null, false, true);
select public.noter_visite('visiteurbbbbbbbb', 'sessionbbbbbbbbb', 'android', 1, '[]'::jsonb, false, false);
reset role;
select essai.egal((select ecrans || '/' || panier || '/' || commande || '/' || plateforme from public.visites where session = 'sessionaaaaaaaaa'),
  '3/true/true/web', 'trois écrans, le panier et la commande retenus');
select essai.verifie((select dernier >= debut from public.visites where session = 'sessionaaaaaaaaa'), 'la visite dure : « dernier » suit');

select essai.titre('2. Les fiches ouvertes se comptent');
select essai.egal((select vues from public.visites_vues where genre = 'produit' and cible = 'p_vis1'), 2, 'le produit ouvert deux fois');
select essai.egal((select vues from public.visites_vues where genre = 'boutique' and cible = 'bou_vis'), 1, 'la boutique, une fois');
select essai.egal((select count(*)::int from public.visites_vues where cible = 'p_inconnu'), 0, 'une fiche qui n''existe pas ne se compte pas');

select essai.titre('3. Ce qui est mal formé ne s''écrit pas');
set role anon;
select public.noter_visite('court', 'sessioncccccccccc', 'web', 1, null, false, false);
select public.noter_visite('Visiteur<script>x', 'sessiondddddddddd', 'web', 1, null, false, false);
select public.noter_visite('visiteurzzzzzzzz', 'sessionaaaaaaaaa', 'web', 5, null, false, false);
select public.noter_visite('visiteureeeeeeee', 'sessioneeeeeeeee', 'minitel', 9999, null, false, false);
reset role;
select essai.egal((select count(*)::int from public.visites where session in ('sessioncccccccccc', 'sessiondddddddddd')), 0,
  'un identifiant trop court, ou avec autre chose que des lettres et des chiffres : rien');
select essai.egal((select ecrans || '/' || visiteur from public.visites where session = 'sessionaaaaaaaaa'), '3/visiteuraaaaaaaa',
  'la visite d''un autre ne se reprend pas');
select essai.egal((select ecrans || '/' || plateforme from public.visites where session = 'sessioneeeeeeeee'), '20/web',
  'vingt écrans au plus par envoi ; une plateforme inconnue : « web »');

select essai.titre('4. Personne ne lit les tables ; les totaux sont au superadministrateur');
set role anon;
select essai.refuse('select count(*) from public.visites', 'un visiteur lit les visites');
select essai.refuse('select count(*) from public.visites_vues', 'un visiteur lit les fiches vues');
select essai.refuse('select public.statistiques_visiteurs()', 'un visiteur demande les totaux');
reset role;
select essai.devenir(:MODO::uuid); set role authenticated;
select essai.refuse('select count(*) from public.visites', 'un modérateur lit les visites');
select essai.refuse('select public.statistiques_visiteurs()', 'un modérateur demande les totaux');
reset role; select essai.personne();

select essai.titre('5. Les totaux');
select essai.devenir(:SUP::uuid); set role authenticated;
select public.statistiques_visiteurs() as s \gset
reset role; select essai.personne();
select essai.egal(:'s'::jsonb -> 'total' ->> 'visiteurs', '3', 'trois visiteurs');
select essai.egal(:'s'::jsonb -> 'total' ->> 'visites', '3', 'trois visites');
select essai.egal((:'s'::jsonb -> 'total' ->> 'panier') || '/' || (:'s'::jsonb -> 'total' ->> 'commande') || '/' || (:'s'::jsonb -> 'total' ->> 'nouveaux'),
  '1/1/3', 'une au panier, une commande, trois nouveaux visiteurs');
select essai.egal(:'s'::jsonb -> 'plateformes' ->> 'android', '1', 'une visite depuis l''application Android');
select essai.egal((:'s'::jsonb -> 'produits' -> 0 ->> 'nom') || '/' || (:'s'::jsonb -> 'produits' -> 0 ->> 'vues') || '/' || (:'s'::jsonb -> 'produits' -> 0 ->> 'boutique'),
  'Produit vu/2/BOUTIQUE VISITÉE', 'le produit le plus consulté en tête, avec sa boutique');
select essai.egal(:'s'::jsonb -> 'boutiques' -> 0 ->> 'nom', 'BOUTIQUE VISITÉE', 'la boutique la plus consultée');
select essai.egal(jsonb_array_length(:'s'::jsonb -> 'jours'), 1, 'un jour de visites');
select essai.verifie(:'s'::text not like '%visiteuraaaa%' and :'s'::text not like '%sessionaaaa%', 'aucun identifiant de visiteur ne sort');

delete from public.visites where session like 'session%';
delete from public.visites_vues where cible in ('p_vis1', 'p_vis2', 'bou_vis');
delete from public.produits where id in ('p_vis1', 'p_vis2');
delete from public.boutiques where id = 'bou_vis';
delete from public.profils where id in (:SUP::uuid, :MODO::uuid);
delete from auth.users where id in (:SUP::uuid, :MODO::uuid);
