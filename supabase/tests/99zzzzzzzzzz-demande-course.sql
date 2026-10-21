-- =========================================================
-- La demande de course envoyée à tous les livreurs (3.59.0)
--
-- Ce qu'on prouve :
--   1. UNE boutique : dès le paiement, la demande part à TOUS ses
--      livreurs validés — pas à un livreur pas encore validé, pas à ceux
--      d'une autre boutique, pas à ceux de BIZZOO ;
--   2. le premier qui touche « Commande reçue » prend la course ; le
--      second arrive trop tard ; la demande disparaît pour les autres ;
--      le client reçoit le nom et le numéro du livreur ; le colis se
--      prend quand la boutique l'a préparé ;
--   3. PLUSIEURS boutiques : livraison groupée, aux seuls livreurs de
--      BIZZOO ; le premier prend TOUTES les boutiques ; le client reçoit
--      UNE nouvelle ;
--   4. une boutique sans livreur validé passe la main à BIZZOO ;
--   5. avant le paiement : rien ne part, rien ne se prend, rien ne se
--      confie.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set LA1      '''dadadada-0000-0000-0000-000000000001'''
\set LA2      '''dadadada-0000-0000-0000-000000000002'''
\set LA3      '''dadadada-0000-0000-0000-000000000003'''
\set LB1      '''dadadada-0000-0000-0000-000000000004'''
\set BZ1      '''dadadada-0000-0000-0000-000000000005'''
\set BZ2      '''dadadada-0000-0000-0000-000000000006'''

select essai.titre('Le décor : deux boutiques, leurs livreurs, ceux de BIZZOO');
insert into auth.users (id, email) values
  (:LA1::uuid, 'la1.demande@essai.bj'), (:LA2::uuid, 'la2.demande@essai.bj'),
  (:LA3::uuid, 'la3.demande@essai.bj'), (:LB1::uuid, 'lb1.demande@essai.bj'),
  (:BZ1::uuid, 'bz1.demande@essai.bj'), (:BZ2::uuid, 'bz2.demande@essai.bj')
on conflict do nothing;
update public.profils p set role = 'livreur', actif = true, boutique_id = v.b, nom = v.n, tel = v.t
  from (values (:LA1::uuid, 'bou_informatique', 'Akim', '0196100001'),
               (:LA2::uuid, 'bou_informatique', 'Bola', '0196100002'),
               (:LA3::uuid, 'bou_informatique', 'Cica', '0196100003'),
               (:LB1::uuid, 'bou_essai_voisine', 'Dodo', '0196100004'),
               (:BZ1::uuid, null, 'Edem', '0196100005'),
               (:BZ2::uuid, null, 'Fifa', '0196100006')) as v(i, b, n, t)
 where p.id = v.i;
-- Tous valident leur position, sauf Cica.
insert into public.positions_livreurs (profil_id, latitude, longitude, adresse)
select i, 6.37, 2.42, 'Cotonou' from unnest(array[:LA1::uuid, :LA2::uuid, :LB1::uuid, :BZ1::uuid, :BZ2::uuid]) i
on conflict (profil_id) do nothing;

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set ouvertures = null, mode_paiement = 'acompte', taux_acompte = 50, frais_livraison = 1000
 where id in ('bou_informatique', 'bou_essai_voisine');
reset role; select essai.personne();
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible) values
  ('prod_dem_a', 'bou_informatique', 'Clavier', 8000, 'sc_hightech_accessoires', 50, true),
  ('prod_dem_b', 'bou_essai_voisine', 'Lampe', 4000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true;

select essai.titre('5. Avant le paiement : rien');
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666006","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_dem_a","quantite":1}]'::jsonb, '', true, true) ->> 'id' as impayee \gset
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.notifications
                    where commande_id = :'impayee' and type = 'course_proposee'), 0,
  'pas payée : aucune demande ne part');
select essai.devenir(:LA1::uuid); set role authenticated;
select essai.refuse(format($$select public.prendre_course(%L)$$, :'impayee'), 'pas payée : aucun livreur ne la prend');
reset role; select essai.personne();
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse(format($$select public.assigner_livreur(%L, 'bou_informatique', %L::uuid)$$, :'impayee', :LA1),
  'pas payée : la boutique ne la confie pas non plus');
reset role; select essai.personne();

select essai.titre('1. Une boutique : la demande part à tous ses livreurs validés');
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666006","adresse":"Fidjrossè, rue 12"}'::jsonb,
  '[{"produit_id":"prod_dem_a","quantite":1}]'::jsonb, '', true, true) ->> 'id' as seule \gset
reset role; select essai.personne();
-- 8 000 + 1 000 = 9 000 ; 50 % : 4 500 maintenant, 4 500 à la livraison.
select public.marquer_payee(:'seule', 'TRX-DEM-1', 4500, 'feexpay') as p \gset

select essai.egal((select string_agg(p.nom, ',' order by p.nom) from public.notifications n
                     join public.profils p on p.id = n.destinataire
                    where n.commande_id = :'seule' and n.type = 'course_proposee'
                      and p.id in (:LA1::uuid, :LA2::uuid, :LA3::uuid, :LB1::uuid, :BZ1::uuid, :BZ2::uuid)),
  'Akim,Bola', 'Akim et Bola, ses livreurs validés — ni Cica (pas validé), ni Dodo, ni BIZZOO');
select n.titre as t1, n.corps as c1 from public.notifications n
 where n.destinataire = :LA1::uuid and n.commande_id = :'seule' and n.type = 'course_proposee' \gset
select essai.verifie(:'t1' like 'Nouvelle course — %', 'le titre : « Nouvelle course »');
select essai.verifie(:'c1' like '%Récupérer : %' and :'c1' like '%Livrer à : Afi — Fidjrossè, rue 12%'
  and :'c1' like '%Destinataire : +229 97666006%' and :'c1' like '%Frais de livraison : 1 000 FCFA%'
  and :'c1' like '%Déjà payé : 4 500 FCFA%' and :'c1' like '%À récupérer : 4 500 FCFA%'
  and :'c1' like '%Commande reçue%', 'l''alerte dit tout, et « Commande reçue »');
select essai.verifie(:'c1' not like '%8 000%', 'pas le prix des articles');

select essai.devenir(:LA2::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.courses_proposees() where commande_id = :'seule'), 1,
  'Bola la voit dans ses demandes');
reset role; select essai.personne();
select essai.devenir(:BZ1::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.courses_proposees() where commande_id = :'seule'), 0,
  'BIZZOO ne la voit pas : la boutique a ses livreurs');
select essai.refuse(format($$select public.prendre_course(%L)$$, :'seule'), 'ni ne la prend');
reset role; select essai.personne();
select essai.devenir(:LA3::uuid); set role authenticated;
select essai.refuse(format($$select public.prendre_course(%L)$$, :'seule'), 'Cica, pas validé, ne la prend pas');
reset role; select essai.personne();

select essai.titre('2. Le premier qui touche « Commande reçue » la prend');
select essai.devenir(:LA1::uuid); set role authenticated;
select public.prendre_course(:'seule') as pris \gset
reset role; select essai.personne();
select essai.egal(:'pris'::int, 1, 'Akim la prend');
select essai.devenir(:LA2::uuid); set role authenticated;
select essai.refuse(format($$select public.prendre_course(%L)$$, :'seule'), 'Bola arrive trop tard');
select essai.egal((select count(*)::int from public.courses_proposees() where commande_id = :'seule'), 0,
  'et la demande a disparu de sa liste');
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ACHETEUR::uuid and commande_id = :'seule' and type = 'course_acceptee'
                      and titre = 'Votre livreur : Akim' and corps like '%+229 0196100001%'), 1,
  'le client reçoit le nom et le numéro d''Akim');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :LA1::uuid and commande_id = :'seule' and type = 'course_confiee'), 0,
  'Akim ne reçoit pas d''alerte « confiée » : il l''a prise lui-même');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :CHEF::uuid and commande_id = :'seule' and type = 'course_acceptee'), 1,
  'la boutique apprend qui l''a prise');

select essai.devenir(:LA1::uuid); set role authenticated;
select essai.egal((select etat || '/' || (recu_le is not null) from public.mes_livraisons() where commande_id = :'seule'),
  'nouvelle/true', 'dans « Mes courses » : acceptée, en préparation à la boutique');
select essai.refuse(format($$select public.avancer_livraison(%L, 'bou_informatique', 'en_livraison')$$, :'seule'),
  'pas de « Je l''ai prise » avant que la boutique ait préparé le colis');
reset role; select essai.personne();
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'preparee' where commande_id = :'seule';
reset role; select essai.personne();
select essai.devenir(:LA1::uuid); set role authenticated;
select public.avancer_livraison(:'seule', 'bou_informatique', 'en_livraison') as av \gset
reset role; select essai.personne();
select essai.egal(:'av'::int, 1, 'colis prêt : Akim le prend');

select essai.titre('3. Plusieurs boutiques : livraison groupée, aux livreurs de BIZZOO');
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666006","adresse":"Fidjrossè, rue 12"}'::jsonb,
  '[{"produit_id":"prod_dem_a","quantite":1},{"produit_id":"prod_dem_b","quantite":1}]'::jsonb,
  '', true, true) as g \gset
reset role; select essai.personne();
select (:'g'::jsonb ->> 'id') as groupee \gset
select public.marquer_payee(:'groupee', 'TRX-DEM-2', (:'g'::jsonb ->> 'acompte')::int, 'feexpay') as p2 \gset

select essai.egal((select string_agg(p.nom, ',' order by p.nom) from public.notifications n
                     join public.profils p on p.id = n.destinataire
                    where n.commande_id = :'groupee' and n.type = 'course_proposee'
                      and p.id in (:LA1::uuid, :LA2::uuid, :LA3::uuid, :LB1::uuid, :BZ1::uuid, :BZ2::uuid)),
  'Edem,Fifa', 'Edem et Fifa, de BIZZOO — aucun livreur de boutique');
select essai.egal((select count(*)::int from public.notifications n join public.profils p on p.id = n.destinataire
                    where n.commande_id = :'groupee' and n.type = 'course_proposee'
                      and p.boutique_id is not null), 0, 'aucun livreur de boutique, quel qu''il soit');
select n.titre as t2, n.corps as c2 from public.notifications n
 where n.destinataire = :BZ1::uuid and n.commande_id = :'groupee' and n.type = 'course_proposee' \gset
select essai.verifie(:'t2' like 'Livraison groupée — %' and :'c2' like '%2 boutiques%',
  'le titre et le texte disent « livraison groupée »');
select essai.verifie((select count(*) from regexp_matches(:'c2', 'Récupérer : ', 'g')) = 2,
  'deux lieux où récupérer');
select essai.verifie(:'c2' like '%Frais de livraison : 2 000 FCFA%', 'les frais des deux boutiques');

select essai.devenir(:BZ2::uuid); set role authenticated;
select essai.egal((select jsonb_array_length(fiche -> 'retraits') || '/' || (fiche ->> 'groupee')
                     from public.courses_proposees() where commande_id = :'groupee'), '2/true',
  'sa liste : la fiche groupée, deux retraits');
select public.prendre_course(:'groupee') as pg \gset
select essai.egal((select count(*)::int from public.mes_livraisons() where commande_id = :'groupee'), 2,
  'Fifa a les deux boutiques dans « Mes courses »');
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.commande_lignes
                    where commande_id = :'groupee' and livreur_id = :BZ2::uuid and recu_le is not null), 2,
  'toutes les lignes, des deux boutiques, sont à elle');
select essai.devenir(:BZ1::uuid); set role authenticated;
select essai.refuse(format($$select public.prendre_course(%L)$$, :'groupee'), 'Edem arrive trop tard');
reset role; select essai.personne();
select essai.devenir(:LA2::uuid); set role authenticated;
select essai.refuse(format($$select public.prendre_course(%L)$$, :'groupee'), 'un livreur de boutique ne la prend pas');
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ACHETEUR::uuid and commande_id = :'groupee' and type = 'course_acceptee'), 1,
  'le client reçoit UNE nouvelle, pas une par boutique');
select essai.verifie((select corps from public.notifications
                        where destinataire = :ACHETEUR::uuid and commande_id = :'groupee' and type = 'course_acceptee')
                      like '%+229 0196100006%', 'avec le numéro de Fifa');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :CHEF::uuid and commande_id = :'groupee' and type = 'course_acceptee'), 1,
  'chaque boutique apprend qui vient chercher son colis');

select essai.titre('4. Une boutique sans livreur validé : BIZZOO prend le relais');
create temp table eteints as
  select id from public.profils where role = 'livreur' and actif and boutique_id = 'bou_essai_voisine';
update public.profils set actif = false where id in (select id from eteints);
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666006","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_dem_b","quantite":1}]'::jsonb, '', true, true) ->> 'id' as voisine \gset
reset role; select essai.personne();
select public.marquer_payee(:'voisine', 'TRX-DEM-3', 2500, 'feexpay') as p3 \gset
select essai.egal((select count(*)::int from public.notifications
                    where commande_id = :'voisine' and type = 'course_proposee'
                      and destinataire in (:BZ1::uuid, :BZ2::uuid)), 2,
  'la demande part aux livreurs de BIZZOO');
update public.profils set actif = true where id in (select id from eteints);

-- Le secours : une boutique confie encore à la main, dès le paiement.
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse(format($$select public.prendre_course(%L)$$, :'voisine'), 'la boutique ne « prend » pas une course');
reset role; select essai.personne();

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set taux_acompte = 10 where id in ('bou_informatique', 'bou_essai_voisine');
reset role; select essai.personne();
