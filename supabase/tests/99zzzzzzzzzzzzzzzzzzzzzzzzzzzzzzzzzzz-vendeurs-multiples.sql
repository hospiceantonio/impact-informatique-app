-- =========================================================
-- (3.70.0) Les boutiques à vendeurs multiples
--
-- Ce qu'on prouve :
--   1. le type de boutique et la part maximale : au superadministrateur ;
--   2. un produit de boutique à vendeurs multiples a son vendeur (un
--      compte vendeur actif) et sa part (dans la borne) ; la part en
--      francs est calculée par la base, au franc inférieur, et suit le
--      prix ; une boutique à vendeur unique n'en a pas ;
--   3. chaque changement de vendeur ou de part laisse une trace ;
--   4. une commande à plusieurs vendeurs : chaque ligne au vendeur de son
--      produit, figée — changer la part ensuite ne touche pas la vente ;
--   5. payée : « en attente » ; remise : « disponible » ; une notification
--      de paiement rejouée ne crédite rien de plus ; la boutique ne compte
--      plus la part des vendeurs ;
--   6. chacun ne voit que son solde ; aucun client dans son espace ;
--   7. ses versements : numéro, demande bornée, le superadministrateur
--      seul tranche ;
--   8. le tableau du superadministrateur : ventes, part, commission.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set V1       '''c7c7c7c7-0000-0000-0000-000000000001'''
\set V2       '''c7c7c7c7-0000-0000-0000-000000000002'''

select essai.titre('Le décor : une boutique, deux vendeurs, quatre produits');
insert into auth.users (id, email) values
  (:V1::uuid, 'v1.vendeur@essai.bj'), (:V2::uuid, 'v2.vendeur@essai.bj')
on conflict do nothing;
update public.profils p set role = 'vendeur', actif = true, boutique_id = null, nom = v.n, tel = v.t
  from (values (:V1::uuid, 'Afi', '0197700001'), (:V2::uuid, 'Bio', '0197700002')) as v(i, n, t)
 where p.id = v.i;
insert into public.boutiques (id, nom, secteur, devise, actif, ordre, categorie_id, mode_paiement, frais_livraison)
values ('bou_vendeurs', 'Marché BIZZOO', 'Essai', 'FCFA', true, 95, 'cat_hightech', 'total', 0)
on conflict (id) do nothing;
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible) values
  ('prod_v_a', 'bou_vendeurs', 'Pagne A', 10000, 'sc_hightech_accessoires', 20, true),
  ('prod_v_b', 'bou_vendeurs', 'Sac B', 12000, 'sc_hightech_accessoires', 20, true),
  ('prod_v_c', 'bou_vendeurs', 'Bijou C', 8000, 'sc_hightech_accessoires', 20, true),
  ('prod_v_sans', 'bou_vendeurs', 'Ancien article', 5000, 'sc_hightech_accessoires', 20, true)
on conflict (id) do update set stock = 20, disponible = true;
update public.paiement set livraison_latitude = null, livraison_longitude = null where id = 1;
-- Un article d'avant le changement de type : prix BIZZOO, pas de vendeur.
insert into public.produits_prive (produit_id, prix_grossiste) values ('prod_v_sans', 4000)
on conflict (produit_id) do update set prix_grossiste = 4000;
select essai.egal((select vendeurs from public.boutiques where id = 'bou_vendeurs'), 'unique',
  'une boutique naît « à vendeur unique »');

select essai.titre('1. Le type de boutique : au superadministrateur');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse($$update public.boutiques set vendeurs = 'multiples' where id = 'bou_informatique'$$,
  'l''administrateur d''une boutique ne la passe pas à vendeurs multiples');
select essai.refuse($$update public.boutiques set part_vendeur_max = 100 where id = 'bou_informatique'$$,
  'ni ne relève la part des vendeurs');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set vendeurs = 'multiples', part_vendeur_max = 80 where id = 'bou_vendeurs';
reset role; select essai.personne();
select essai.egal((select vendeurs || '/' || part_vendeur_max from public.boutiques where id = 'bou_vendeurs'),
  'multiples/80.00', 'le superadministrateur la passe à vendeurs multiples, part au plus 80 %');

select essai.titre('2. Chaque produit : son vendeur, sa part');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
insert into public.produits_prive (produit_id, prix_grossiste, vendeur_id, taux_vendeur)
values ('prod_v_a', 9999, :V1::uuid, 80), ('prod_v_b', 1, :V2::uuid, 75), ('prod_v_c', 0, :V1::uuid, 70.5);
select essai.egal((select string_agg(produit_id || '=' || prix_grossiste, ',' order by produit_id)
                     from public.produits_prive where produit_id in ('prod_v_a', 'prod_v_b', 'prod_v_c')),
  'prod_v_a=8000,prod_v_b=9000,prod_v_c=5640',
  'la part se calcule en base (10 000 × 80 %, 12 000 × 75 %, 8 000 × 70,5 %) — ce que l''écran envoie n''est pas écouté');
select essai.refuse($$update public.produits_prive set taux_vendeur = 90 where produit_id = 'prod_v_a'$$,
  'une part au-delà de la borne de la boutique (80 %) : refusée');
select essai.refuse(format($$update public.produits_prive set vendeur_id = %L where produit_id = 'prod_v_a'$$, :CHEF),
  'un compte qui n''est pas vendeur : refusé');
select essai.refuse($$update public.produits_prive set vendeur_id = null, taux_vendeur = null where produit_id = 'prod_v_a'$$,
  'retirer le vendeur d''un produit de la boutique : refusé');
select essai.refuse($$update public.produits_prive set prix_grossiste = 4000 where produit_id = 'prod_v_sans'$$,
  'un article d''avant ne s''enregistre plus sans son vendeur');
select essai.refuse(format($$insert into public.produits_prive (produit_id, prix_grossiste, vendeur_id, taux_vendeur)
  values ('prod_essai_voisin', 4000, %L, 50)
  on conflict (produit_id) do update set vendeur_id = excluded.vendeur_id, taux_vendeur = excluded.taux_vendeur$$, :V1),
  'dans une boutique à vendeur unique, pas de vendeur');
update public.produits set prix = 11000 where id = 'prod_v_a';
select essai.egal((select prix_grossiste::int from public.produits_prive where produit_id = 'prod_v_a'), 8800,
  'le prix de vente change (11 000) : la part suit (8 800)');
update public.produits set prix = 10000 where id = 'prod_v_a';
reset role; select essai.personne();
select essai.egal(public.part_vendeur(9999, 80), 7999::bigint, '9 999 × 80 % = 7 999,2 → 7 999 : au franc inférieur');

select essai.titre('3. L''historique des parts');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.produits_prive set taux_vendeur = 78 where produit_id = 'prod_v_a';
update public.produits_prive set taux_vendeur = 80 where produit_id = 'prod_v_a';
select essai.refuse($$select * from public.parts_vendeurs_historique$$, 'personne ne lit la table à la main');
select essai.egal((select count(*)::int from jsonb_array_elements(public.parts_vendeurs_historique_liste()) h
                    where h ->> 'produit' = 'Pagne A' and (h ->> 'taux_avant')::numeric = 80
                      and (h ->> 'taux_apres')::numeric = 78), 1,
  '80 % → 78 % : la trace est là, avec qui l''a fait');
reset role; select essai.personne();
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse($$select public.parts_vendeurs_historique_liste()$$,
  'l''historique est au superadministrateur');
reset role; select essai.personne();

-- Une commande au nom de l'acheteur.
create function pg_temp.commander(articles jsonb) returns jsonb language plpgsql as $$
declare g jsonb;
begin
  perform essai.devenir('ffffffff-2222-2222-2222-222222222222'::uuid);
  set local role authenticated;
  g := public.creer_commande('{"nom":"Rosine","tel":"97666077","adresse":"Godomey"}'::jsonb,
    articles, '', true, true, null);
  reset role;
  perform essai.personne();
  return g;
end $$;

select essai.titre('4. Une commande, trois vendeurs : chaque ligne au sien, figée');
select pg_temp.commander('[{"produit_id":"prod_v_a","quantite":1},{"produit_id":"prod_v_b","quantite":2},
                            {"produit_id":"prod_v_c","quantite":1},{"produit_id":"prod_v_sans","quantite":1}]'::jsonb) as g1 \gset
select essai.egal((select string_agg(l.produit_id || ':' || coalesce(p.nom, '—') || ':' || l.prix_bizzoo, ',' order by l.produit_id)
                     from public.commande_lignes l left join public.profils p on p.id = l.vendeur_id
                    where l.commande_id = :'g1'::jsonb ->> 'id'),
  'prod_v_a:Afi:8000,prod_v_b:Bio:9000,prod_v_c:Afi:5640,prod_v_sans:—:4000',
  'Pagne et Bijou à Afi, Sac à Bio, l''article d''avant à la boutique — chacun sa part');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.produits_prive set taux_vendeur = 60 where produit_id = 'prod_v_a';
reset role; select essai.personne();
select essai.egal((select prix_bizzoo from public.commande_lignes
                    where commande_id = :'g1'::jsonb ->> 'id' and produit_id = 'prod_v_a'), 8000,
  'la part changée ensuite (60 %) ne touche pas la vente : 8 000');
select essai.refuse(format($$update public.commande_lignes set vendeur_id = %L
                             where commande_id = %L and produit_id = 'prod_v_a'$$, :V2, :'g1'::jsonb ->> 'id'),
  'personne ne change le vendeur d''une ligne vendue — même pas la base à la main');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.produits_prive set taux_vendeur = 80 where produit_id = 'prod_v_a';
reset role; select essai.personne();

select essai.titre('5. Payée : en attente ; remise : disponible ; jamais deux fois');
select essai.devenir(:V1::uuid); set role authenticated;
select essai.egal((public.solde_vendeur() ->> 'a_venir')::int, 0, 'pas encore payée : rien');
reset role; select essai.personne();
select public.marquer_payee(:'g1'::jsonb ->> 'id', 'TRX-V-1', (:'g1'::jsonb ->> 'acompte')::int, 'feexpay') as p1 \gset
select essai.devenir(:V1::uuid); set role authenticated;
select essai.egal((select (s ->> 'a_venir') || '/' || (s ->> 'gagne') || '/' || (s ->> 'disponible')
                     from (select public.solde_vendeur() s) x), '13640/0/0',
  'payée : 13 640 en attente pour Afi (8 000 + 5 640), rien de disponible');
reset role; select essai.personne();
select public.marquer_payee(:'g1'::jsonb ->> 'id', 'TRX-V-1', (:'g1'::jsonb ->> 'acompte')::int, 'feexpay') as p1bis \gset
update public.commande_lignes set etat = 'remise' where commande_id = :'g1'::jsonb ->> 'id';
select essai.devenir(:V1::uuid); set role authenticated;
select essai.egal((select (s ->> 'ventes') || '/' || (s ->> 'gagne') || '/' || (s ->> 'a_venir') || '/' || (s ->> 'disponible')
                     from (select public.solde_vendeur() s) x), '18000/13640/0/13640',
  'remise : 18 000 de ventes, 13 640 gagnés et disponibles — une seule fois, malgré le paiement notifié deux fois');
reset role; select essai.personne();
select essai.devenir(:V2::uuid); set role authenticated;
select essai.egal((public.solde_vendeur() ->> 'gagne')::int, 18000, 'Bio : 2 × 9 000');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal((public.solde_boutique('bou_vendeurs') ->> 'gagne')::int, 4000,
  'la boutique ne compte que l''article sans vendeur (4 000), pas la part des vendeurs');
reset role; select essai.personne();

select essai.titre('6. Chacun son solde, et aucun client');
select essai.devenir(:V1::uuid); set role authenticated;
select essai.refuse(format($$select public.solde_vendeur(%L)$$, :V2), 'Afi ne lit pas le solde de Bio');
select essai.egal((select count(*)::int from public.commandes), 0, 'un vendeur ne lit pas les commandes');
select public.espace_vendeur() as esp \gset
select essai.egal(jsonb_array_length(:'esp'::jsonb -> 'produits'), 2, 'son espace : ses deux produits');
select essai.egal(jsonb_array_length(:'esp'::jsonb -> 'lignes'), 2, 'ses deux ventes');
select essai.verifie(position('Rosine' in :'esp') = 0 and position('97666077' in :'esp') = 0,
  'ni le nom ni le numéro du client');
reset role; select essai.personne();
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse(format($$select public.solde_vendeur(%L)$$, :V1), 'un administrateur de boutique non plus');
reset role; select essai.personne();

select essai.titre('7. Ses versements');
select essai.devenir(:V1::uuid); set role authenticated;
select essai.refuse($$select public.demander_reversement_vendeur(1000)$$, 'sans numéro de réception : refusé');
select public.regler_reception_vendeur('97 70 00 01', 'mtn', 'Afi');
select essai.refuse($$select public.demander_reversement_vendeur(20000)$$, 'plus que son disponible : refusé');
select public.demander_reversement_vendeur(10000) as dem \gset
select essai.egal((public.solde_vendeur() ->> 'disponible')::int, 3640, 'demandé : 3 640 restent disponibles');
select essai.refuse(format($$select public.decider_reversement_vendeur(%s, true, 'MP0001')$$, :dem),
  'il ne valide pas lui-même');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse(format($$select public.decider_reversement_vendeur(%s, true, '')$$, :dem),
  'sans référence de transaction : refusé');
select essai.egal(public.decider_reversement_vendeur(:dem, true, 'MP0001'), 'valide', 'le superadministrateur l''envoie');
reset role; select essai.personne();
select essai.devenir(:V1::uuid); set role authenticated;
select essai.egal((select (s ->> 'reverse') || '/' || (s ->> 'disponible') from (select public.solde_vendeur() s) x),
  '10000/3640', 'versé : 10 000, et 3 640 encore disponibles');
reset role; select essai.personne();

select essai.titre('8. Le tableau du superadministrateur');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal((select (v ->> 'ventes') || '/' || (v ->> 'part') || '/' || (v ->> 'commission') || '/' || (v ->> 'reverse')
                     from jsonb_array_elements(public.ventes_vendeurs()) v where v ->> 'nom' = 'Afi'),
  '18000/13640/4360/10000', 'Afi : 18 000 de ventes, 13 640 pour lui, 4 360 pour BIZZOO, 10 000 versés');
reset role; select essai.personne();
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse($$select public.ventes_vendeurs()$$, 'ce tableau est au superadministrateur');
select essai.egal(jsonb_array_length(public.vendeurs_liste()), 2, 'l''équipe voit la liste des vendeurs, pour ses produits');
reset role; select essai.personne();
select essai.devenir(:V1::uuid); set role authenticated;
select essai.egal(public.vendeurs_liste(), '[]'::jsonb, 'un vendeur ne voit pas la liste des autres');
reset role; select essai.personne();

select essai.titre('9. On ne repasse pas en vendeur unique avec des produits de vendeurs');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse($$update public.boutiques set vendeurs = 'unique' where id = 'bou_vendeurs'$$,
  'trois produits ont leur vendeur : la boutique reste à vendeurs multiples');
reset role; select essai.personne();

-- Le décor rendu : les articles de la boutique d'essai hors vente.
update public.produits set disponible = false, stock = 0 where boutique_id = 'bou_vendeurs';
