-- =========================================================
-- Un reversement, c'est des commandes entières — ou tout le solde (3.81.0)
--
-- Ce qu'on prouve :
--   1. la boutique voit ses commandes à reverser (numéro, date, montant) ;
--   2. une partie du solde est refusée ; des commandes entières passent,
--      au montant de ces commandes ; la demande garde leur liste : client,
--      paiement (FeexPay et sa référence), et ce qui doit faire vérifier
--      (client « test », paiement confirmé à la main) ; la notification
--      de BIZZOO nomme les commandes ;
--   3. une commande déjà demandée, d'une autre boutique, ou inconnue :
--      refusée ;
--   4. tout le solde : la demande prend les commandes qui restent ;
--   5. une demande refusée rend ses commandes ;
--   6. seuls le superadministrateur, le CEO et la comptabilité lisent la
--      liste d'une demande ; une demande sans liste se calcule à la volée.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set CHEFR    '''cbcbcbcb-0000-0000-0000-000000000001'''

select essai.titre('Le décor : une boutique, trois commandes livrées de 8 000 pour elle');
insert into public.boutiques (id, nom, secteur, devise, actif, ordre, categorie_id)
values ('bou_rvc', 'BOUTIQUE REVERSEMENTS', 'Essai', 'FCFA', true, 96, 'cat_hightech') on conflict (id) do nothing;
insert into auth.users (id, email) values (:CHEFR::uuid, 'chef.rvc@essai.bj') on conflict do nothing;
update public.profils set role = 'administrateur', actif = true, boutique_id = 'bou_rvc', nom = 'Chef RVC'
 where id = :CHEFR::uuid;
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_rvc', 'bou_rvc', 'Casque', 10000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true, masque = false, prix = 10000;
insert into public.produits_prive (produit_id, prix_grossiste) values ('prod_rvc', 8000)
on conflict (produit_id) do update set prix_grossiste = 8000;
create function pg_temp.commande(nom text, trx text) returns text language plpgsql as $$
declare g jsonb;
begin
  perform essai.devenir('ffffffff-2222-2222-2222-222222222222'::uuid);
  set local role authenticated;
  g := public.creer_commande(jsonb_build_object('nom', nom, 'tel', '97666088', 'adresse', 'Gbégamey'),
    '[{"produit_id":"prod_rvc","quantite":1}]'::jsonb, '', true, true);
  reset role;
  perform essai.personne();
  perform public.marquer_payee(g ->> 'id', trx, (g ->> 'acompte')::int, 'feexpay');
  update public.commande_lignes set etat = 'remise' where commande_id = g ->> 'id';
  return g ->> 'id';
end $$;
create function pg_temp.comme(qui uuid, q text) returns text language plpgsql as $$
declare r text;
begin
  perform essai.devenir(qui);
  set local role authenticated;
  execute q into r;
  reset role;
  perform essai.personne();
  return r;
end $$;
select pg_temp.commande('Ablawa', 'TRX-RVC-1') as c1 \gset
select pg_temp.commande('Client Test', 'TRX-RVC-2') as c2 \gset
select pg_temp.commande('Codjo', 'TRX-RVC-3') as c3 \gset
-- Confirmée à la main par l'enseigne (comme le ferait « confirmer_paiement »).
select set_config('bizzoo.interne', 'oui', false) as x \gset
update public.commandes set confirme_par = 'chef@bizzoo.bj' where id = :'c3';
select set_config('bizzoo.interne', '', false) as x \gset
select essai.devenir(:CHEFR::uuid); set role authenticated;
select public.regler_reception('bou_rvc', '0196554433', 'MTN', 'Chef RVC') as rr \gset
select essai.egal((public.solde_boutique('bou_rvc') ->> 'disponible')::int, 24000, '24 000 disponibles');

select essai.titre('1. Ses commandes à reverser');
select public.commandes_a_reverser('boutique', 'bou_rvc') as acr \gset
select essai.egal(jsonb_array_length(:'acr'::jsonb), 3, 'les trois commandes');
select essai.verifie((select bool_and((x ->> 'reste')::int = 8000 and x ->> 'numero' like 'BZ-%')
                        from jsonb_array_elements(:'acr'::jsonb) x), 'chacune : son numéro, 8 000 à reverser');
select essai.verifie(position('Ablawa' in :'acr') = 0, 'sans le nom du client');

select essai.titre('2. Des commandes entières, jamais une partie');
select essai.refuse($$select public.demander_reversement('bou_rvc', 10000)$$, 'une partie du solde : refusé');
select public.demander_reversement_commandes('boutique', array[:'c1', :'c2'], 'bou_rvc') as rv1 \gset
reset role; select essai.personne();
select essai.egal((select montant::int from public.reversements where id = :rv1), 16000,
  'deux commandes entières : 16 000');
select (select operations from public.reversements where id = :rv1) as ops \gset
select essai.egal(jsonb_array_length(:'ops'::jsonb -> 'commandes'), 2, 'la demande garde ses deux commandes');
select essai.verifie((select bool_and(x ->> 'paiement' = 'feexpay' and x ->> 'transaction' like 'TRX-RVC-%'
                                      and (x ->> 'couvert')::int = 8000 and (x ->> 'part')::int = 8000)
                        from jsonb_array_elements(:'ops'::jsonb -> 'commandes') x),
  'chacune : payée par FeexPay, sa référence, 8 000 couverts');
select essai.verifie((select x -> 'alertes' ? 'Le nom ou la note du client parle de test'
                        from jsonb_array_elements(:'ops'::jsonb -> 'commandes') x where x ->> 'client' = 'Client Test'),
  'le client « Test » fait vérifier');
select essai.verifie((select jsonb_array_length(x -> 'alertes') = 0
                        from jsonb_array_elements(:'ops'::jsonb -> 'commandes') x where x ->> 'client' = 'Ablawa'),
  'une vraie commande : rien à signaler');
select essai.egal((:'ops'::jsonb ->> 'non_rattache')::int, 0, 'tout le montant vient de commandes');
select essai.verifie((select bool_and(corps like '%Commandes : BZ-%') from public.notifications
                       where type = 'reversement_demande' and lien = '#/reversements/boutique-' || :rv1),
  'la notification de BIZZOO nomme les commandes');

select essai.titre('3. Déjà demandée, d''ailleurs, inconnue : refusée');
select essai.refuse(format('select pg_temp.comme(%L, %L)', :CHEFR,
  format('select public.demander_reversement_commandes(''boutique'', array[%L], ''bou_rvc'')::text', :'c1')),
  'une commande déjà demandée');
select essai.refuse(format('select pg_temp.comme(%L, %L)', :CHEFR,
  'select public.demander_reversement_commandes(''boutique'', array[''CMD-INCONNUE''], ''bou_rvc'')::text'),
  'une commande inconnue');
select essai.refuse(format('select pg_temp.comme(%L, %L)', :CHEFR,
  'select public.demander_reversement_commandes(''boutique'', array[]::text[], ''bou_rvc'')::text'),
  'aucune commande');
set role anon;
select essai.refuse(format($$select public.demander_reversement_commandes('boutique', array[%L], 'bou_rvc')$$, :'c3'),
  'un visiteur');
reset role;

select essai.titre('4. Tout le solde : les commandes qui restent');
select pg_temp.comme(:CHEFR::uuid, $$select public.demander_reversement('bou_rvc', 8000)::text$$) as rv2 \gset
select (select operations from public.reversements where id = :rv2) as ops2 \gset
select essai.egal((:'ops2'::jsonb -> 'commandes' -> 0 ->> 'commande_id'), :'c3', 'la troisième commande');
select essai.verifie((:'ops2'::jsonb -> 'commandes' -> 0 -> 'alertes') ? 'Paiement confirmé à la main par chef@bizzoo.bj',
  'confirmée à la main : à vérifier');

select essai.titre('5. Une demande refusée rend ses commandes');
select pg_temp.comme(:ENSEIGNE::uuid, format($$select public.decider_reversement(%s, false, '', 'Commande d''essai')$$, :rv1));
select essai.egal(jsonb_array_length(pg_temp.comme(:CHEFR::uuid,
  $$select public.commandes_a_reverser('boutique', 'bou_rvc')::text$$)::jsonb), 2,
  'les deux commandes de la demande refusée sont de nouveau à reverser');

select essai.titre('6. Qui lit la liste d''une demande');
select essai.egal(jsonb_array_length(pg_temp.comme(:ENSEIGNE::uuid,
  format('select public.reversement_operations(''boutique'', %s)::text', :rv2))::jsonb -> 'commandes'), 1,
  'le superadministrateur');
select essai.refuse(format('select pg_temp.comme(%L, %L)', :CHEFR,
  format('select public.reversement_operations(''boutique'', %s)::text', :rv2)),
  'pas l''administrateur de la boutique : la liste nomme les clients');
set role anon;
select essai.refuse(format($$select public.reversement_operations('boutique', %s)$$, :rv2), 'pas un visiteur');
reset role;
select essai.devenir(:CHEFR::uuid); set role authenticated;
select essai.refuse('select * from public.reversements', 'la table ne se lit toujours pas');
reset role; select essai.personne();
update public.reversements set operations = null where id = :rv2;
select essai.egal((pg_temp.comme(:ENSEIGNE::uuid,
  format('select public.reversement_operations(''boutique'', %s)::text', :rv2))::jsonb -> 'commandes' -> 0 ->> 'commande_id'),
  :'c1', 'une demande sans liste : calculée à la volée, sur les plus anciennes commandes libres (la demande refusée a rendu les siennes)');
set role authenticated;
select essai.refuse($$select public.operations_couvertes('boutique', 'bou_rvc', 1, now(), null, null)$$,
  'le calcul lui-même n''est pas ouvert');
reset role;
