-- =========================================================
-- Google partout : les noms de lieux et la clé des cartes (4.8.0)
--
-- Ce qu'on prouve :
--   1. un nom de lieu se note avec sa source ; celui de Google ne vaut
--      que 30 jours, celui d'OpenStreetMap reste ;
--   2. personne d'autre que le serveur ne note ni ne lit ces noms ;
--   3. la clé des cartes : tout le monde la lit (elle est publique),
--      seul le superadministrateur l'écrit, et ce qui ne ressemble pas à
--      une clé de cartes est refusé.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set SUP   '''dfdfdf00-0000-0000-0000-000000000001'''
\set MODO  '''dfdfdf00-0000-0000-0000-000000000002'''

select essai.titre('Le décor : un superadministrateur, un modérateur');
insert into auth.users (id, email) values (:SUP::uuid, 'sup.cartes@essai.bj'), (:MODO::uuid, 'modo.cartes@essai.bj') on conflict do nothing;
select set_config('bizzoo.compte', 'oui', false) \gset
update public.profils set role = 'superadministrateur', actif = true, boutique_id = null where id = :SUP::uuid;
update public.profils set role = 'moderateur', actif = true, boutique_id = null where id = :MODO::uuid;
select set_config('bizzoo.compte', '', false) \gset
delete from public.lieux_noms where lat_g in (public.grille_route(11.1111), public.grille_route(11.2222));

select essai.titre('1. Un nom de Google vaut 30 jours ; un nom d''OpenStreetMap reste');
select essai.verifie(public.noter_lieu(11.1111, 2.1111, 'Quartier Google', 'google'), 'un nom venu de Google se note');
select essai.verifie(public.noter_lieu(11.2222, 2.2222, 'Quartier OSM'), 'sans source dite : OpenStreetMap, comme avant');
select essai.egal((select source from public.lieux_noms where lat_g = public.grille_route(11.1111)) || '/' ||
                  (select source from public.lieux_noms where lat_g = public.grille_route(11.2222)), 'google/osm', 'chacun garde sa source');
select essai.egal(public.lieu_connu(11.1111, 2.1111) ->> 'nom', 'Quartier Google', 'frais : connu');
update public.lieux_noms set cree_le = now() - interval '31 days' where lat_g in (public.grille_route(11.1111), public.grille_route(11.2222));
select essai.verifie((public.lieu_connu(11.1111, 2.1111) ->> 'nom') is null, '31 jours plus tard, le nom de Google ne vaut plus : on le redemandera');
select essai.egal(public.lieu_connu(11.2222, 2.2222) ->> 'nom', 'Quartier OSM', 'celui d''OpenStreetMap vaut toujours');
select essai.verifie(public.noter_lieu(11.1111, 2.1111, 'Quartier Google bis', 'google'), 'redemandé, renoté');
select essai.egal(public.lieu_connu(11.1111, 2.1111) ->> 'nom', 'Quartier Google bis', 'et de nouveau connu');
select essai.verifie(public.noter_lieu(11.1111, 2.1111, 'Quartier X', 'ailleurs'), 'une source inconnue se note…');
select essai.egal((select source from public.lieux_noms where lat_g = public.grille_route(11.1111)), 'osm', '… comme OpenStreetMap');

select essai.titre('2. Le serveur seul note et lit ces noms');
set role anon;
select essai.refuse($$select public.noter_lieu(11.1111, 2.1111, 'Faux', 'google')$$, 'un visiteur note un nom');
select essai.refuse($$select public.lieu_connu(11.1111, 2.1111)$$, 'un visiteur lit la mémoire');
reset role;
select essai.devenir(:MODO::uuid); set role authenticated;
select essai.refuse($$select public.noter_lieu(11.1111, 2.1111, 'Faux', 'google')$$, 'un modérateur note un nom');
reset role; select essai.personne();

select essai.titre('3. La clé des cartes : publique à lire, au superadministrateur à écrire');
set role anon;
select essai.egal((select cle_tuiles from public.cartes_reglage where id = 1), '', 'un visiteur la lit : vide au départ (cartes d''OpenStreetMap)');
select essai.sans_effet($$update public.cartes_reglage set cle_tuiles = 'AIzaFAUSSE0000000000000000000000000000' where id = 1$$, 'un visiteur l''écrit dans la table');
select essai.refuse($$select public.regler_cle_cartes('AIzaFAUSSE0000000000000000000000000000')$$, 'ou par la fonction');
reset role;
select essai.devenir(:MODO::uuid); set role authenticated;
select essai.refuse($$select public.regler_cle_cartes('AIzaFAUSSE0000000000000000000000000000')$$, 'un modérateur la règle');
select essai.sans_effet($$update public.cartes_reglage set cle_tuiles = 'AIzaFAUSSE0000000000000000000000000000' where id = 1$$, 'ou l''écrit dans la table');
reset role; select essai.personne();
select essai.devenir(:SUP::uuid); set role authenticated;
-- La fausse clé est écrite en deux morceaux : entière, elle ressemblerait
-- à une vraie pour les contrôles de GitHub.
select essai.refuse($$select public.regler_cle_cartes('sb_' || 'secret_' || repeat('0', 31))$$, 'une clé secrète collée là par erreur');
select essai.refuse($$select public.regler_cle_cartes('AIzaCourte')$$, 'une clé trop courte');
select essai.refuse($$select public.regler_cle_cartes('AIza avec des espaces 000000000000000000000')$$, 'une clé avec autre chose que des lettres et des chiffres');
select essai.verifie(public.regler_cle_cartes('  AIzaESSAI_cle-de-cartes-0000000000000000  '), 'le superadministrateur la règle (les espaces autour s''en vont)');
reset role; select essai.personne();
set role anon;
select essai.egal((select cle_tuiles from public.cartes_reglage where id = 1), 'AIzaESSAI_cle-de-cartes-0000000000000000', 'et tout le monde la lit');
reset role;
select essai.devenir(:SUP::uuid); set role authenticated;
select essai.verifie(not public.regler_cle_cartes(''), 'vidée : les cartes d''OpenStreetMap reviennent');
reset role; select essai.personne();
select essai.egal((select cle_tuiles from public.cartes_reglage where id = 1), '', 'la table est vide de nouveau');

delete from public.lieux_noms where lat_g in (public.grille_route(11.1111), public.grille_route(11.2222));
delete from public.profils where id in (:SUP::uuid, :MODO::uuid);
delete from auth.users where id in (:SUP::uuid, :MODO::uuid);
