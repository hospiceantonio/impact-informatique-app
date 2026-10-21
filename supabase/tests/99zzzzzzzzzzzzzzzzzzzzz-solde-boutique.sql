-- =========================================================
-- Le solde de chaque boutique, et ses reversements (3.59.0)
--
-- Ce qu'on prouve :
--   1. le solde, ce sont les ventes LIVRÉES au prix BIZZOO (commission
--      déduite) ; payées mais pas remises : « à venir » ;
--   2. l'administrateur règle le numéro de réception (refusé s'il est mal
--      formé) ; BIZZOO en est prévenu ;
--   3. il demande un reversement : pas plus que le disponible, pas sans
--      numéro ; la demande garde le numéro ; BIZZOO est prévenu ;
--   4. le superadministrateur valide (avec la référence) ou refuse (le
--      montant revient au disponible) ; la boutique est prévenue ;
--   5. un modérateur, la boutique voisine, l'administrateur lui-même pour
--      valider : non ; personne n'écrit les tables à la main.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set MODO     '''b1b10000-0000-0000-0000-000000000001'''
\set VOISIN   '''b1b10000-0000-0000-0000-000000000002'''

select essai.titre('Le décor : un article à 10 000, dont 8 000 pour la boutique');
insert into auth.users (id, email) values (:MODO::uuid, 'modo.solde@essai.bj'), (:VOISIN::uuid, 'voisin.solde@essai.bj')
on conflict do nothing;
update public.profils p set role = v.r, actif = true, boutique_id = v.b, nom = v.n
  from (values (:MODO::uuid, 'moderateur', 'bou_informatique', 'Modo'),
               (:VOISIN::uuid, 'administrateur', 'bou_essai_voisine', 'Voisin')) as v(i, r, b, n)
 where p.id = v.i;
update public.boutiques set actif = true, ouvertures = null where id = 'bou_informatique';
-- Une boutique d'essai à part, pour un solde qui ne doit rien aux autres essais.
insert into public.boutiques (id, nom, secteur, devise, actif, ordre, categorie_id)
values ('bou_solde', 'BOUTIQUE SOLDE', 'Essai', 'FCFA', true, 95, 'cat_hightech') on conflict (id) do nothing;
\set CHEFS '''b1b10000-0000-0000-0000-000000000003'''
insert into auth.users (id, email) values (:CHEFS::uuid, 'chef.solde@essai.bj') on conflict do nothing;
update public.profils set role = 'administrateur', actif = true, boutique_id = 'bou_solde', nom = 'Chef Solde'
 where id = :CHEFS::uuid;
update public.profils set boutique_id = 'bou_solde' where id = :MODO::uuid;
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_solde', 'bou_solde', 'Tablette', 10000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true, masque = false, prix = 10000;
insert into public.produits_prive (produit_id, prix_grossiste) values ('prod_solde', 8000)
on conflict (produit_id) do update set prix_grossiste = 8000;
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666013","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_solde","quantite":2}]'::jsonb, '', true, true) as g \gset
reset role; select essai.personne();
select (:'g'::jsonb ->> 'id') as cmd \gset
select public.marquer_payee(:'cmd', 'TRX-SOLDE-1', (:'g'::jsonb ->> 'acompte')::int, 'feexpay') as p \gset

select essai.titre('1. Le solde : les ventes livrées, au prix BIZZOO');
select essai.devenir(:CHEFS::uuid); set role authenticated;
select essai.egal((select (s ->> 'gagne') || '/' || (s ->> 'a_venir') || '/' || (s ->> 'disponible')
                     from (select public.solde_boutique('bou_solde') as s) x), '0/16000/0',
  'payée, pas remise : 0 gagné, 16 000 à venir');
reset role; select essai.personne();
update public.commande_lignes set etat = 'remise' where commande_id = :'cmd';
select essai.devenir(:CHEFS::uuid); set role authenticated;
select essai.egal((select (s ->> 'gagne') || '/' || (s ->> 'a_venir') || '/' || (s ->> 'disponible')
                     from (select public.solde_boutique('bou_solde') as s) x), '16000/0/16000',
  'remise : 16 000 gagnés (2 × 8 000, pas 2 × 10 000), disponibles');

select essai.titre('2. Le numéro de réception');
select essai.refuse($$select public.demander_reversement('bou_solde', 5000)$$, 'sans numéro : pas de demande');
select essai.refuse($$select public.regler_reception('bou_solde', '123', 'MTN')$$, 'un numéro mal formé : refusé');
select essai.refuse($$select public.regler_reception('bou_solde', '0196123456', 'ORANGE')$$, 'un réseau inconnu : refusé');
select essai.egal((public.regler_reception('bou_solde', '01 96 12 34 56', 'mtn', 'Chef Solde') ->> 'tel'),
  '0196123456', 'le numéro est réglé, au bon format');
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ENSEIGNE::uuid and type = 'reception_reglee' and boutique_id = 'bou_solde'), 1,
  'BIZZOO est prévenu du changement de numéro');

select essai.titre('3. La demande de reversement');
select essai.devenir(:CHEFS::uuid); set role authenticated;
select essai.refuse($$select public.demander_reversement('bou_solde', 20000)$$, 'plus que le disponible : refusé');
select public.demander_reversement('bou_solde', 10000) as rv1 \gset
select essai.egal((select (s ->> 'en_attente') || '/' || (s ->> 'disponible')
                     from (select public.solde_boutique('bou_solde') as s) x), '10000/6000',
  '10 000 en attente, 6 000 encore disponibles');
select essai.refuse($$select public.demander_reversement('bou_solde', 7000)$$, 'au-delà du reste disponible : refusé');
reset role; select essai.personne();
select essai.egal((select tel || '/' || reseau from public.reversements where id = :rv1), '0196123456/MTN',
  'la demande garde le numéro du moment');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ENSEIGNE::uuid and type = 'reversement_demande' and boutique_id = 'bou_solde'), 1,
  'BIZZOO est prévenu de la demande');

select essai.titre('4. Le superadministrateur tranche');
select essai.devenir(:CHEFS::uuid); set role authenticated;
select essai.refuse(format($$select public.decider_reversement(%s, true, 'REF-XYZ')$$, :rv1),
  'l''administrateur ne valide pas sa propre demande');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.reversements_liste() where etat = 'en_attente' and boutique_id = 'bou_solde'), 1,
  'il voit la demande en attente');
select essai.refuse(format($$select public.decider_reversement(%s, true, '')$$, :rv1), 'valider sans référence : refusé');
select essai.egal(public.decider_reversement(:rv1, true, 'MP-998877'), 'valide', 'il valide, référence MP-998877');
select essai.refuse(format($$select public.decider_reversement(%s, false, '', 'non')$$, :rv1), 'trancher deux fois : refusé');
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :CHEFS::uuid and type = 'reversement_decide' and titre like 'Reversement envoyé%'), 1,
  'la boutique est prévenue : envoyé');
select essai.devenir(:CHEFS::uuid); set role authenticated;
select essai.egal((select (s ->> 'reverse') || '/' || (s ->> 'disponible')
                     from (select public.solde_boutique('bou_solde') as s) x), '10000/6000',
  '10 000 reversés, 6 000 disponibles');
select public.demander_reversement('bou_solde', 6000) as rv2 \gset
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal(public.decider_reversement(:rv2, false, '', 'Numéro injoignable'), 'refuse', 'il refuse, avec un motif');
reset role; select essai.personne();
select essai.devenir(:CHEFS::uuid); set role authenticated;
select essai.egal((select (s ->> 'disponible') from (select public.solde_boutique('bou_solde') as s) x), '6000',
  'refusé : les 6 000 reviennent au disponible');
reset role; select essai.personne();

select essai.titre('5. Les autres : non');
select essai.devenir(:MODO::uuid); set role authenticated;
select essai.refuse($$select public.solde_boutique('bou_solde')$$, 'un modérateur ne voit pas le solde');
select essai.refuse($$select public.demander_reversement('bou_solde', 1000)$$, 'ni ne demande de reversement');
reset role; select essai.personne();
select essai.devenir(:VOISIN::uuid); set role authenticated;
select essai.refuse($$select public.solde_boutique('bou_solde')$$, 'la boutique voisine non plus');
select essai.egal((select count(*)::int from public.reversements_liste('bou_solde')), 0, 'ni ses reversements');
select essai.refuse($$select public.regler_reception('bou_solde', '0196000000', 'MTN')$$, 'ni son numéro');
select essai.refuse('select * from public.reversements', 'la table ne se lit pas');
select essai.refuse('select * from public.boutiques_reception', 'le numéro non plus');
reset role; select essai.personne();
update public.profils set boutique_id = 'bou_informatique' where id = :MODO::uuid;
