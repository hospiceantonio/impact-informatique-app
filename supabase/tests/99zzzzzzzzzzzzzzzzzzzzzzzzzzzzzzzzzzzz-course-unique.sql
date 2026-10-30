-- =========================================================
-- Une commande groupée, une seule course (3.72.0)
--
-- Ce qu'on prouve :
--   1. deux boutiques : un seul livreur, qui accepte toute la commande
--      d'un geste ;
--   2. un colis déjà récupéré : il ne refuse plus le reste ;
--   3. « remettre_commande » attend tous les colis ;
--   4. puis remet TOUT d'un coup : le client paie le reste en UNE fois,
--      la même transaction notée sur chaque boutique pour sa part ;
--   5. la transaction ne resservira pas ; rien de dû : remise directe ;
--   6. il n'a pas cette course : refusé.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set CU1      '''c0c0c0c0-0000-0000-0000-000000000001'''
\set CU2      '''c0c0c0c0-0000-0000-0000-000000000002'''
\set ADMV     '''c0c0c0c0-0000-0000-0000-000000000003'''

select essai.titre('Le décor : deux boutiques, deux livreurs de BIZZOO, le point BIZZOO');
insert into auth.users (id, email) values
  (:CU1::uuid, 'cu1.unique@essai.bj'), (:CU2::uuid, 'cu2.unique@essai.bj'), (:ADMV::uuid, 'admv.unique@essai.bj')
on conflict do nothing;
update public.profils p set role = v.r, actif = true, boutique_id = v.b, nom = v.n, tel = v.t,
       vehicule = 'moto', courses_bloquees = false, disponible = true
  from (values (:CU1::uuid, 'livreur', null, 'Codjo', '0196600001'),
               (:CU2::uuid, 'livreur', null, 'Dossou', '0196600002'),
               (:ADMV::uuid, 'administrateur', 'bou_essai_voisine', 'Edwige', '0196600003'))
       as v(i, r, b, n, t)
 where p.id = v.i;
insert into public.positions_livreurs (profil_id, latitude, longitude, adresse)
select i, 6.37, 2.42, 'Cotonou' from unnest(array[:CU1::uuid, :CU2::uuid]) i
on conflict (profil_id) do nothing;
update public.cascade_reglage set actif = false where id = 1;
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set actif = true, ouvertures = null, mode_paiement = 'acompte', taux_acompte = 50,
       frais_livraison = 1000
 where id in ('bou_informatique', 'bou_essai_voisine');
update public.paiement set livraison_latitude = 6.3654, livraison_longitude = 2.4183 where id = 1;
reset role; select essai.personne();
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible) values
  ('prod_cu_a', 'bou_informatique', 'Clavier', 9000, 'sc_hightech_accessoires', 50, true),
  ('prod_cu_b', 'bou_essai_voisine', 'Ampoule', 6000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true, masque = false;

create function pg_temp.commande_groupee(trx text) returns text language plpgsql as $$
declare v_id text;
begin
  perform essai.devenir('ffffffff-2222-2222-2222-222222222222'::uuid);
  set local role authenticated;
  v_id := public.creer_commande('{"nom":"Rosine","tel":"97666088","adresse":"Godomey"}'::jsonb,
    '[{"produit_id":"prod_cu_a","quantite":1},{"produit_id":"prod_cu_b","quantite":1}]'::jsonb, '', true, true,
    '{"latitude":6.40,"longitude":2.42}'::jsonb) ->> 'id';
  reset role;
  perform essai.personne();
  perform public.marquer_payee(v_id, trx,
    (select coalesce(c.acompte, c.total)::int from public.commandes c where c.id = v_id), 'feexpay');
  return v_id;
end $$;
-- Une boutique prépare sa part.
create function pg_temp.preparer(qui uuid, cmd text, bq text) returns void language plpgsql as $$
begin
  perform essai.devenir(qui);
  set local role authenticated;
  update public.commande_lignes set etat = 'preparee' where commande_id = cmd and boutique_id = bq;
  reset role;
  perform essai.personne();
end $$;
create function pg_temp.reste(cmd text) returns bigint language sql as $$
  select coalesce(sum(a_encaisser), 0)::bigint from public.restes_par_boutique(cmd);
$$;

select pg_temp.commande_groupee('TRX-CU-1') as c1 \gset

select essai.titre('1. Deux boutiques, un livreur, une acceptation');
select essai.devenir(:CU1::uuid); set role authenticated;
select essai.egal(public.prendre_course(:'c1'), 2, 'Codjo prend la course : les deux boutiques');
reset role; select essai.personne();
select essai.egal((select count(distinct livreur_id)::int from public.commande_lignes where commande_id = :'c1'), 1,
  'un seul livreur sur toute la commande');
select essai.egal((select count(*)::int from public.commande_lignes where commande_id = :'c1' and recu_le is null), 0,
  'toute la commande est acceptée d''un geste');

select essai.titre('2. Un colis récupéré : plus de refus');
select pg_temp.preparer(:CHEF::uuid, :'c1', 'bou_informatique');
select essai.devenir(:CU1::uuid); set role authenticated;
select essai.egal(public.avancer_livraison(:'c1', 'bou_informatique', 'en_livraison'), 1,
  'il récupère le colis de la première boutique');
select essai.refuse(format($$select public.refuser_course(%L, 'trop loin')$$, :'c1'),
  'il ne refuse plus le reste : la commande ne se coupe pas en deux');
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.commande_lignes where commande_id = :'c1' and livreur_id = :CU1::uuid), 2,
  'il garde les deux boutiques');

select essai.titre('3. Remettre attend tous les colis');
select pg_temp.reste(:'c1') as du0 \gset
select essai.devenir(:CU1::uuid); set role authenticated;
select essai.refuse(format($$select public.remettre_commande(%L, %s, 'mobile_money', 'MPCU0001')$$,
  :'c1', :du0), 'l''autre colis est encore en préparation : refusé');
reset role; select essai.personne();

select essai.titre('4. Tout d''un coup, un seul paiement');
select pg_temp.preparer(:ADMV::uuid, :'c1', 'bou_essai_voisine');
select pg_temp.reste(:'c1') as du1 \gset
select essai.verifie(:du1 > 0, 'il reste à payer à la livraison (acompte de 50 %)');
select essai.egal((select count(*)::int from public.restes_par_boutique(:'c1') where a_encaisser > 0), 2,
  'le reste se partage entre les deux boutiques');
select essai.devenir(:CU1::uuid); set role authenticated;
select essai.egal(public.avancer_livraison(:'c1', 'bou_essai_voisine', 'en_livraison'), 1, 'il récupère le second colis');
select essai.refuse(format($$select public.remettre_commande(%L, %s, 'mobile_money', 'MPCU0001')$$, :'c1', :du1 - 1),
  'un montant qui n''est pas le reste : refusé');
select essai.refuse(format($$select public.remettre_commande(%L, %s, 'especes', '')$$, :'c1', :du1),
  'en espèces : refusé');
select essai.refuse(format($$select public.remettre_commande(%L, %s, 'mobile_money', '')$$, :'c1', :du1),
  'sans transaction : refusé');
select public.remettre_commande(:'c1', :du1, 'mobile_money', 'mpcu-0001') as r1 \gset
reset role; select essai.personne();
select essai.egal((:'r1'::jsonb ->> 'du')::bigint, :du1::bigint, 'tout le reste, en un paiement');
select essai.egal((select count(*)::int from public.commande_lignes where commande_id = :'c1' and etat = 'remise'), 2,
  'les deux boutiques sont remises');
select essai.egal((select count(*)::int || '/' || count(distinct transaction_id)::int || '/' || sum(montant)::bigint
                     from public.encaissements where commande_id = :'c1' and mode = 'mobile_money'),
  '2/1/' || :du1, 'une transaction, notée sur chaque boutique pour sa part');
select essai.egal((select min(transaction_id) from public.encaissements where commande_id = :'c1'), 'MPCU-0001',
  'la transaction, en majuscules');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ACHETEUR::uuid and commande_id = :'c1' and type = 'reste_encaisse'), 1,
  'le client reçoit UNE nouvelle « Reste payé »');
select essai.egal((select count(*)::int from public.gains_livreurs where commande_id = :'c1' and livreur_id = :CU1::uuid), 1,
  'le gain du livreur, une fois');
select essai.devenir(:CU1::uuid); set role authenticated;
select essai.refuse(format($$select public.remettre_commande(%L, 0, 'aucun', '')$$, :'c1'),
  'remettre deux fois : rien à remettre');
reset role; select essai.personne();

select essai.titre('5. La transaction ne resservira pas ; rien de dû : remise directe');
select pg_temp.commande_groupee('TRX-CU-2') as c2 \gset
select essai.devenir(:CU2::uuid); set role authenticated;
select essai.egal(public.prendre_course(:'c2'), 2, 'Dossou prend la seconde');
reset role; select essai.personne();
select pg_temp.preparer(:CHEF::uuid, :'c2', 'bou_informatique');
select pg_temp.preparer(:ADMV::uuid, :'c2', 'bou_essai_voisine');
select pg_temp.reste(:'c2') as du2 \gset
select essai.devenir(:CU2::uuid); set role authenticated;
select public.avancer_livraison(:'c2', 'bou_informatique', 'en_livraison') as a1 \gset
select public.avancer_livraison(:'c2', 'bou_essai_voisine', 'en_livraison') as a2 \gset
select essai.refuse(format($$select public.remettre_commande(%L, %s, 'mobile_money', 'MPCU-0001')$$,
  :'c2', :du2), 'la transaction de la première commande : refusée');
select essai.egal((public.remettre_commande(:'c2', :du2, 'mobile_money', 'MPCU-0002') ->> 'transaction'),
  'MPCU-0002', 'avec sa propre transaction : remise');
reset role; select essai.personne();

-- Des boutiques payées en entier à la commande : rien à encaisser.
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set mode_paiement = 'total' where id in ('bou_informatique', 'bou_essai_voisine');
reset role; select essai.personne();
select pg_temp.commande_groupee('TRX-CU-3') as c3 \gset
select essai.devenir(:CU2::uuid); set role authenticated;
select essai.egal(public.prendre_course(:'c3'), 2, 'Dossou prend la troisième');
reset role; select essai.personne();
select pg_temp.preparer(:CHEF::uuid, :'c3', 'bou_informatique');
select pg_temp.preparer(:ADMV::uuid, :'c3', 'bou_essai_voisine');
select essai.egal(pg_temp.reste(:'c3'), 0::bigint, 'tout est payé');
select essai.devenir(:CU2::uuid); set role authenticated;
select public.avancer_livraison(:'c3', 'bou_informatique', 'en_livraison') as a3 \gset
select public.avancer_livraison(:'c3', 'bou_essai_voisine', 'en_livraison') as a4 \gset
select essai.egal((public.remettre_commande(:'c3', 0, 'aucun', '') ->> 'lignes')::int, 2,
  'rien de dû : les deux boutiques remises, sans transaction');
reset role; select essai.personne();
select essai.egal((select string_agg(mode, ',' order by boutique_id) from public.encaissements where commande_id = :'c3'),
  'aucun,aucun', 'chaque part, soldée sans paiement');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set mode_paiement = 'acompte' where id in ('bou_informatique', 'bou_essai_voisine');
reset role; select essai.personne();

select essai.titre('6. Pas sa course : refusé');
select pg_temp.commande_groupee('TRX-CU-4') as c4 \gset
select essai.devenir(:CU1::uuid); set role authenticated;
select essai.refuse(format($$select public.remettre_commande(%L, 0, 'aucun', '')$$, :'c4'),
  'une course qu''il n''a pas : refusé');
reset role; select essai.personne();

-- Le décor rendu.
update public.paiement set livraison_latitude = null, livraison_longitude = null where id = 1;
update public.cascade_reglage set actif = true where id = 1;
update public.profils set actif = false where id in (:CU1::uuid, :CU2::uuid);
