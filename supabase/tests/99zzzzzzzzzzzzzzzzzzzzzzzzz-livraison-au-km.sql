-- =========================================================
-- La livraison au kilomètre, et le solde des livreurs (3.64.0)
--
-- Ce qu'on prouve :
--   0. tant que le point BIZZOO n'est pas réglé, rien ne change : frais
--      par boutique, pas de devis ;
--   1. le devis : forfait jusqu'à 10 km, puis le kilomètre ENTAMÉ, au
--      tarif du véhicule ; une position absurde est refusée ;
--   2. la commande : position obligatoire ; UN frais pour la commande,
--      tricycle dès qu'un produit l'exige ; payé en ligne avec l'acompte ;
--      le reste à la livraison ne le compte pas ;
--   3. un livreur par commande : plusieurs boutiques → un livreur de
--      BIZZOO ; tricycle → un livreur en tricycle ;
--   4. remise en entier, la commande crédite le livreur de 80 % des
--      frais, une seule fois ; annulée, rien ;
--   5. son solde, son numéro, ses demandes de reversement ; le
--      superadministrateur seul les tranche.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set LA       '''b8b8b8b8-0000-0000-0000-000000000001'''
\set BZM      '''b8b8b8b8-0000-0000-0000-000000000002'''
\set BZT      '''b8b8b8b8-0000-0000-0000-000000000003'''
\set ADMB     '''b8b8b8b8-0000-0000-0000-000000000004'''

select essai.titre('Le décor : deux boutiques, un livreur de boutique, deux livreurs de BIZZOO');
insert into auth.users (id, email) values
  (:LA::uuid, 'la.km@essai.bj'), (:BZM::uuid, 'bzm.km@essai.bj'),
  (:BZT::uuid, 'bzt.km@essai.bj'), (:ADMB::uuid, 'admb.km@essai.bj')
on conflict do nothing;
update public.profils p set role = v.r, actif = true, boutique_id = v.b, nom = v.n, tel = v.t, vehicule = v.v
  from (values (:LA::uuid, 'livreur', 'bou_informatique', 'Kossi', '0196500001', 'moto'),
               (:BZM::uuid, 'livreur', null, 'Lamine', '0196500002', 'moto'),
               (:BZT::uuid, 'livreur', null, 'Mawu', '0196500003', 'tricycle'),
               (:ADMB::uuid, 'administrateur', 'bou_essai_voisine', 'Nadia', '0196500004', 'moto'))
       as v(i, r, b, n, t, v)
 where p.id = v.i;
insert into public.positions_livreurs (profil_id, latitude, longitude, adresse)
select i, 6.37, 2.42, 'Cotonou' from unnest(array[:LA::uuid, :BZM::uuid, :BZT::uuid]) i
on conflict (profil_id) do nothing;
-- Les autres livreurs de BIZZOO des essais d'avant se retirent : la
-- liste des candidats doit être celle de ce décor.
update public.profils set actif = false
 where role = 'livreur' and boutique_id is null and id not in (:BZM::uuid, :BZT::uuid);
update public.profils set actif = false
 where role = 'livreur' and boutique_id = 'bou_informatique' and id <> :LA::uuid;
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set actif = true, ouvertures = null, mode_paiement = 'acompte', taux_acompte = 50,
       frais_livraison = 1000
 where id in ('bou_informatique', 'bou_essai_voisine');
reset role; select essai.personne();
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible) values
  ('prod_km_a', 'bou_informatique', 'Souris', 9000, 'sc_hightech_accessoires', 50, true),
  ('prod_km_b', 'bou_essai_voisine', 'Lampe', 6000, 'sc_hightech_accessoires', 50, true),
  ('prod_km_frigo', 'bou_informatique', 'Réfrigérateur', 150000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true;
update public.paiement set livraison_latitude = null, livraison_longitude = null where id = 1;
select essai.egal((select vehicule from public.produits where id = 'prod_km_a'), 'moto',
  'un produit naît « moto »');

-- Une commande au nom de l'acheteur.
create function pg_temp.commander(articles jsonb, dest jsonb) returns jsonb language plpgsql as $$
declare g jsonb;
begin
  perform essai.devenir('ffffffff-2222-2222-2222-222222222222'::uuid);
  set local role authenticated;
  g := public.creer_commande('{"nom":"Rosine","tel":"97666077","adresse":"Godomey"}'::jsonb,
    articles, '', true, true, dest);
  reset role;
  perform essai.personne();
  return g;
end $$;

select essai.titre('0. Sans point BIZZOO : les frais de chaque boutique, comme avant');
select essai.verifie(not public.livraison_active(), 'la livraison au kilomètre n''est pas en service');
select essai.egal(public.devis_livraison(6.45, 2.42, 'moto'), null::jsonb, 'pas de devis');
select pg_temp.commander('[{"produit_id":"prod_km_a","quantite":1},{"produit_id":"prod_km_b","quantite":1}]'::jsonb,
  null) as g0 \gset
select essai.egal((:'g0'::jsonb ->> 'frais_livraison')::int, 2000, 'les frais des deux boutiques : 2 000');
select essai.egal(:'g0'::jsonb -> 'livraison', 'null'::jsonb, 'pas de livraison au kilomètre sur la commande');

select essai.titre('1. Le superadministrateur règle le point ; le devis');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.sans_effet($$update public.paiement set livraison_latitude = 6.3654, livraison_longitude = 2.4183 where id = 1$$,
  'l''administrateur d''une boutique ne règle pas le point BIZZOO');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.paiement set livraison_latitude = 6.3654, livraison_longitude = 2.4183,
       livraison_adresse = 'Siège BIZZOO, Cotonou' where id = 1;
select essai.refuse($$update public.paiement set livraison_latitude = 6.3654, livraison_longitude = null where id = 1$$,
  'un point à moitié : refusé');
select essai.refuse($$update public.paiement set taux_livreur = 120 where id = 1$$,
  'un taux au-delà de 100 % : refusé');
reset role; select essai.personne();
select essai.verifie(public.livraison_active(), 'la livraison au kilomètre est en service');
select essai.egal((select (d ->> 'distance_km') || '/' || (d ->> 'km_factures') || '/' || (d ->> 'frais')
                     from (select public.devis_livraison(6.413825, 2.4183, 'moto') d) x),
  '7.0/0/1000', '7 km à moto : le forfait, 1 000');
select essai.egal((select (d ->> 'distance_km') || '/' || (d ->> 'km_factures') || '/' || (d ->> 'frais')
                     from (select public.devis_livraison(6.458099, 2.4183, 'moto') d) x),
  '13.4/4/1400', '13,4 km à moto : 4 km entamés, 1 400');
select essai.egal((public.devis_livraison(6.458099, 2.4183, 'tricycle') ->> 'frais')::int, 6000,
  '13,4 km en tricycle : 4 000 + 4 × 500');
select essai.egal((public.devis_livraison(6.434924, 2.4183, 'moto') ->> 'km_factures')::int, 1,
  '10,05 km : le kilomètre entamé compte');
select essai.egal((public.devis_livraison(6.3654, 2.4183, 'avion') ->> 'vehicule'), 'moto',
  'un véhicule inconnu : moto');
select essai.refuse($$select public.devis_livraison(0, 0, 'moto')$$, 'la position 0,0 : refusée');
select essai.refuse($$select public.devis_livraison(95, 2, 'moto')$$, 'une latitude impossible : refusée');
set role anon;
select essai.egal((public.devis_livraison(6.458099, 2.4183, 'moto') ->> 'frais')::int, 1400,
  'un visiteur voit le devis');
reset role;

select essai.titre('2. La commande : position obligatoire, un seul frais, en ligne');
select essai.refuse($$select pg_temp.commander('[{"produit_id":"prod_km_a","quantite":1}]'::jsonb, null)$$,
  'sans position : refusé');
select essai.refuse($$select pg_temp.commander('[{"produit_id":"prod_km_a","quantite":1}]'::jsonb, '{"adresse":"x"}'::jsonb)$$,
  'une position sans coordonnées : refusée');
select pg_temp.commander('[{"produit_id":"prod_km_a","quantite":1},{"produit_id":"prod_km_b","quantite":1}]'::jsonb,
  '{"latitude":6.458099,"longitude":2.4183}'::jsonb) as g1 \gset
select essai.egal((:'g1'::jsonb ->> 'frais_livraison')::int, 1400,
  'deux boutiques, UN frais : 1 400 (plus de frais par boutique)');
select essai.egal((:'g1'::jsonb -> 'livraison' ->> 'vehicule') || '/' || (:'g1'::jsonb -> 'livraison' ->> 'distance_km'),
  'moto/13.4', 'à moto, 13,4 km, figés sur la commande');
select essai.egal((:'g1'::jsonb ->> 'total')::int, 16400, 'total : 15 000 d''articles + 1 400');
select essai.egal((:'g1'::jsonb ->> 'acompte')::int, 8900, 'en ligne : la moitié des articles (7 500) + les frais (1 400)');
select essai.egal((:'g1'::jsonb ->> 'reste')::int, 7500, 'à la livraison : 7 500, sans frais');
select essai.egal((select sum((v ->> 'frais')::int)::int from jsonb_each(:'g1'::jsonb -> 'parts') e(k, v)), 0,
  'les parts des boutiques ne portent plus de frais');
select essai.egal((select sum(r.a_encaisser)::int from public.restes_par_boutique(:'g1'::jsonb ->> 'id') r), 7500,
  'les boutiques n''encaissent pas les frais à la porte');

select essai.devenir(:CHEF::uuid); set role authenticated;
update public.produits set vehicule = 'tricycle' where id = 'prod_km_frigo';
select essai.refuse($$update public.produits set vehicule = 'camion' where id = 'prod_km_frigo'$$,
  'un véhicule inconnu : refusé');
reset role; select essai.personne();
select essai.egal((select vehicule from public.produits where id = 'prod_km_frigo'), 'tricycle',
  'la boutique règle son réfrigérateur « tricycle »');
select pg_temp.commander('[{"produit_id":"prod_km_a","quantite":1},{"produit_id":"prod_km_frigo","quantite":1}]'::jsonb,
  '{"latitude":6.458099,"longitude":2.4183}'::jsonb) as g2 \gset
select essai.egal((:'g2'::jsonb -> 'livraison' ->> 'vehicule') || '/' || (:'g2'::jsonb ->> 'frais_livraison'),
  'tricycle/6000', 'un seul produit en tricycle : toute la commande en tricycle, 6 000');

select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.sans_effet(format($$update public.commandes set frais_livraison = 0, livraison = null where id = %L$$,
  :'g1'::jsonb ->> 'id'), 'le client ne retouche pas ses frais');
reset role; select essai.personne();
select essai.egal((select frais_livraison::int from public.commandes where id = :'g1'::jsonb ->> 'id'), 1400,
  'les frais restent 1 400');

select essai.titre('3. Un livreur par commande ; le tricycle aux tricycles');
select public.marquer_payee(:'g1'::jsonb ->> 'id', 'TRX-KM-1', (:'g1'::jsonb ->> 'acompte')::int, 'feexpay') as p1 \gset
select essai.egal((select string_agg(p.nom, ',' order by p.nom) from unnest(public.candidats_course(:'g1'::jsonb ->> 'id')) c
                     join public.profils p on p.id = c), 'Lamine',
  'deux boutiques, à moto : proposée aux livreurs de BIZZOO à moto');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse(format($$select public.assigner_livreur(%L, 'bou_informatique', %L::uuid)$$, :'g1'::jsonb ->> 'id', :LA),
  'confiée au livreur d''une boutique : refusé, elle traverse deux boutiques');
reset role; select essai.personne();
select essai.devenir(:ADMB::uuid); set role authenticated;
select essai.egal(public.assigner_livreur(:'g1'::jsonb ->> 'id', 'bou_essai_voisine', :BZM::uuid), 2,
  'la voisine la confie à Lamine : les deux boutiques');
select essai.egal(public.assigner_livreur(:'g1'::jsonb ->> 'id', 'bou_essai_voisine', null), 2,
  'et la reprend : retirée de toute la commande');
select essai.egal(public.assigner_livreur(:'g1'::jsonb ->> 'id', 'bou_essai_voisine', :BZM::uuid), 2,
  'puis la lui confie de nouveau');
reset role; select essai.personne();
select essai.egal((select count(distinct livreur_id)::int from public.commande_lignes where commande_id = :'g1'::jsonb ->> 'id'), 1,
  'un seul livreur sur la commande');
select essai.egal(public.gain_livreur(:'g1'::jsonb ->> 'id'), 1120::bigint, 'son gain annoncé : 80 % de 1 400');
select essai.devenir(:BZM::uuid); set role authenticated;
select essai.egal((public.solde_livreur() ->> 'a_venir')::int, 1120, 'son solde : 1 120 à venir');
reset role; select essai.personne();

select public.marquer_payee(:'g2'::jsonb ->> 'id', 'TRX-KM-2', (:'g2'::jsonb ->> 'acompte')::int, 'feexpay') as p2 \gset
select essai.egal((select string_agg(p.nom, ',' order by p.nom) from unnest(public.candidats_course(:'g2'::jsonb ->> 'id')) c
                     join public.profils p on p.id = c), 'Mawu',
  'en tricycle : proposée au seul livreur en tricycle');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse(format($$select public.assigner_livreur(%L, 'bou_informatique', %L::uuid)$$, :'g2'::jsonb ->> 'id', :LA),
  'confiée à un livreur à moto : refusé');
reset role; select essai.personne();
select essai.devenir(:BZM::uuid); set role authenticated;
select essai.refuse(format($$select public.prendre_course(%L)$$, :'g2'::jsonb ->> 'id'), 'Lamine, à moto, ne la prend pas');
reset role; select essai.personne();
select essai.devenir(:BZT::uuid); set role authenticated;
select essai.egal(public.prendre_course(:'g2'::jsonb ->> 'id'), 2, 'Mawu, en tricycle, la prend');
reset role; select essai.personne();

select essai.titre('4. Remise en entier : 80 % des frais au livreur, une fois');
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'preparee' where commande_id = :'g1'::jsonb ->> 'id' and boutique_id = 'bou_informatique';
reset role; select essai.personne();
select essai.devenir(:ADMB::uuid); set role authenticated;
update public.commande_lignes set etat = 'preparee' where commande_id = :'g1'::jsonb ->> 'id' and boutique_id = 'bou_essai_voisine';
reset role; select essai.personne();
select essai.devenir(:BZM::uuid); set role authenticated;
select public.accepter_course(:'g1'::jsonb ->> 'id', 'bou_informatique') as acc \gset
select public.avancer_livraison(:'g1'::jsonb ->> 'id', 'bou_informatique', 'en_livraison') as av1 \gset
select public.avancer_livraison(:'g1'::jsonb ->> 'id', 'bou_essai_voisine', 'en_livraison') as av2 \gset
select public.remettre_course(:'g1'::jsonb ->> 'id', 'bou_informatique', 4500, 'mobile_money', 'MPKM0001') as r1 \gset
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.gains_livreurs where commande_id = :'g1'::jsonb ->> 'id'), 0,
  'une boutique remise sur deux : pas encore crédité');
select essai.devenir(:BZM::uuid); set role authenticated;
select public.remettre_course(:'g1'::jsonb ->> 'id', 'bou_essai_voisine', 3000, 'mobile_money', 'MPKM0002') as r2 \gset
reset role; select essai.personne();
select essai.egal((select frais || '/' || taux || '/' || montant || '/' || (livreur_id = :BZM::uuid)
                     from public.gains_livreurs where commande_id = :'g1'::jsonb ->> 'id'),
  '1400/80/1120/true', 'toute la commande remise : 1 120 crédités à Lamine, sans attendre le client');
select essai.egal(public.crediter_livreur(:'g1'::jsonb ->> 'id'), 1120::bigint, 'rejouer le crédit…');
select essai.egal((select count(*)::int from public.gains_livreurs where commande_id = :'g1'::jsonb ->> 'id'), 1,
  '… ne crédite pas deux fois');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :BZM::uuid and type = 'gain_livraison'
                      and commande_id = :'g1'::jsonb ->> 'id'), 1, 'il en est prévenu');
update public.paiement set taux_livreur = 70 where id = 1;
select essai.egal(public.gain_livreur(:'g1'::jsonb ->> 'id'), 1120::bigint,
  'le taux change ensuite : le gain crédité reste figé');
update public.paiement set taux_livreur = 80 where id = 1;

-- Annulée : rien au livreur, les frais reviennent au client.
select pg_temp.commander('[{"produit_id":"prod_km_a","quantite":1}]'::jsonb,
  '{"latitude":6.413825,"longitude":2.4183}'::jsonb) as g3 \gset
select public.marquer_payee(:'g3'::jsonb ->> 'id', 'TRX-KM-3', (:'g3'::jsonb ->> 'acompte')::int, 'feexpay') as p3 \gset
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'annulee' where commande_id = :'g3'::jsonb ->> 'id';
reset role; select essai.personne();
select essai.egal(public.crediter_livreur(:'g3'::jsonb ->> 'id'), 0::bigint, 'commande annulée : aucun gain');

select essai.titre('5. Son solde ; ses reversements, tranchés par le superadministrateur');
select essai.devenir(:BZM::uuid); set role authenticated;
select essai.egal((select (s ->> 'gagne') || '/' || (s ->> 'disponible') || '/' || (s ->> 'a_venir')
                     from (select public.solde_livreur() s) x), '1120/1120/0', 'gagné 1 120, disponible 1 120');
select essai.refuse($$select public.demander_reversement_livreur(500)$$, 'sans numéro de réception : refusé');
select essai.refuse($$select public.regler_reception_livreur('12345', 'MTN')$$, 'un numéro mal formé : refusé');
select public.regler_reception_livreur('97 50 00 02', 'mtn', 'Lamine B.') as rr \gset
select essai.refuse($$select public.demander_reversement_livreur(2000)$$, 'plus que son solde : refusé');
select public.demander_reversement_livreur(1000) as dem \gset
select essai.egal((public.solde_livreur() ->> 'disponible')::int, 120, 'demande en cours : 120 disponibles');
select essai.refuse($$select public.demander_reversement_livreur(500)$$, 'une deuxième demande au-delà : refusée');
select essai.refuse(format($$select public.decider_reversement_livreur(%s, true, 'REF-0001')$$, :dem),
  'il ne valide pas lui-même');
reset role; select essai.personne();
select essai.egal((select tel || '/' || reseau from public.reversements_livreurs where id = :dem), '0197500002/MTN',
  'le numéro, ramené à dix chiffres, voyage avec la demande');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ENSEIGNE::uuid and type = 'reversement_demande'
                      and titre like 'Reversement demandé par un livreur%'), 1,
  'le superadministrateur est prévenu');
select essai.devenir(:BZT::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.reversements_livreurs_liste()), 0,
  'un autre livreur ne voit pas ses demandes');
select essai.refuse(format($$select public.solde_livreur(%L::uuid)$$, :BZM), 'ni son solde');
reset role; select essai.personne();
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse(format($$select public.decider_reversement_livreur(%s, true, 'REF-0001')$$, :dem),
  'l''administrateur d''une boutique ne valide pas');
select essai.refuse($$select * from public.gains_livreurs$$, 'ni ne lit les gains');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.reversements_livreurs_liste() where id = :dem), 1,
  'le superadministrateur voit la demande');
select essai.refuse(format($$select public.decider_reversement_livreur(%s, true, '')$$, :dem),
  'valider sans référence : refusé');
select essai.egal(public.decider_reversement_livreur(:dem, true, 'MTN-778899'), 'valide', 'il valide, avec la référence');
select essai.refuse(format($$select public.decider_reversement_livreur(%s, false, '', 'non')$$, :dem),
  'une demande tranchée ne se retranche pas');
select essai.egal((select (s ->> 'reverse') || '/' || (s ->> 'disponible') from (select public.solde_livreur(:BZM::uuid) s) x),
  '1000/120', 'il lit le solde de Lamine : 1 000 reversés, 120 disponibles');
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :BZM::uuid and type = 'reversement_decide'
                      and corps like '%MTN-778899%'), 1, 'Lamine reçoit la référence');

select essai.devenir(:BZM::uuid); set role authenticated;
select public.demander_reversement_livreur(100) as dem2 \gset
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal(public.decider_reversement_livreur(:dem2, false, '', 'Numéro injoignable'), 'refuse', 'il refuse, avec un motif');
reset role; select essai.personne();
select essai.devenir(:BZM::uuid); set role authenticated;
select essai.egal((public.solde_livreur() ->> 'disponible')::int, 120, 'refusée : les 100 reviennent au solde');
reset role; select essai.personne();

-- Le décor rendu : le point BIZZOO retiré, les autres essais retrouvent
-- les frais par boutique.
update public.paiement set livraison_latitude = null, livraison_longitude = null where id = 1;
