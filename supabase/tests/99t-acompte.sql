-- =========================================================
-- L'acompte à la commande
--
-- CE QU'ON DÉFEND ICI. Le client paie en ligne une part du total
-- — l'acompte — pour que sa commande parte ; le reste se paie à la
-- livraison. Ce qui doit tenir :
--
--   1. LE TAUX EST AU SUPERADMINISTRATEUR : 10 % au départ, de 1 à
--      100, et personne d'autre ne l'écrit — ni un visiteur, ni un
--      client, ni une boutique, ni le compte de BIZZOO ;
--   2. LA BASE CALCULE L'ACOMPTE : le taux du jour sur le total remise
--      déduite, au franc supérieur, 100 FCFA au moins, jamais plus que
--      le total. Une application d'avant, qui ne le demande pas, fait
--      payer le total ;
--   3. IL EST FIGÉ : changer le taux ne réécrit pas une commande
--      passée, et personne ne réécrit l'acompte ni le versé ;
--   4. L'AGRÉGATEUR DEMANDE L'ACOMPTE ; un versement plus petit reste
--      incomplet, le versé se garde, le journal attend l'acompte ;
--   5. LE RESTE SE PARTAGE ENTRE LES BOUTIQUES au franc près, et un
--      article annulé ne se paie pas ;
--   6. CHACUN NE VOIT QUE CE QUI LE REGARDE : le client et l'enseigne
--      tout, une boutique sa part, les autres rien ;
--   7. LE LIVREUR VOIT CE QU'IL ENCAISSE, et rien d'autre ;
--   8. LES NOTIFICATIONS DISENT L'ACOMPTE ET LE RESTE ;
--   9. L'ENSEIGNE QUI SE PORTE GARANTE le fait pour l'acompte ;
--  10. UNE COMMANDE D'AVANT L'ACOMPTE se paie en entier, et il ne lui
--      reste rien.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set EQUIPE   '''33333333-3333-3333-3333-333333333333'''
\set KOFI     '''55555555-5555-5555-5555-555555555555'''
\set PORTEUR  '''cccccccc-1111-1111-1111-111111111111'''
\set VOISIN   '''cccccccc-3333-3333-3333-333333333333'''
\set ADJOINT  '''dddddddd-1111-1111-1111-111111111111'''

-- Une commande d'avant l'acompte : la base la reçoit sans acompte. On
-- l'imite en effaçant celui qu'elle vient de poser — dans la même
-- transaction que le drapeau, d'où la fonction.
create or replace function essai.oublier_acompte(cible text) returns void
language plpgsql as $$
begin
  perform set_config('bizzoo.interne', 'oui', true);
  update public.commandes set acompte = null, taux_acompte = null where id = cible;
end $$;

-- Une commande dont on ne connaît que l'identifiant, avec les montants
-- qu'on voudrait : ce qu'un curieux enverrait à « restes » en direct.
create or replace function essai.fabriquee(cible text, total int, verse int)
returns public.commandes language sql as $$
  select jsonb_populate_record(null::public.commandes,
    jsonb_build_object('id', cible, 'total', total, 'verse', verse));
$$;
grant execute on function essai.fabriquee(text, int, int) to anon, authenticated;

-- ---------------------------------------------------------
select essai.titre('Le décor : deux boutiques, un client, deux livreurs');

update public.reglages set compte_obligatoire = false where id = 1;

insert into public.boutiques (id, nom, secteur, devise, actif, ordre, categorie_id)
values ('bou_essai_voisine', 'BOUTIQUE VOISINE', 'Essai', 'FCFA', true, 91, 'cat_hightech')
on conflict (id) do nothing;

insert into auth.users (id, email) values
  (:PORTEUR::uuid, 'porteur@impact.bj'),
  (:VOISIN::uuid,  'voisin@impact.bj'),
  (:ADJOINT::uuid, 'adjoint@bizzoo.bj')
on conflict do nothing;
insert into public.profils (id, email, role, boutique_id, actif, peut_commandes) values
  (:CHEF::uuid,    'chef-boutique@bizzoo.bj', 'administrateur', 'bou_informatique',  true, true),
  (:EQUIPE::uuid,  'equipe@bizzoo.bj',        'moderateur',     'bou_essai_voisine', true, true),
  (:PORTEUR::uuid, 'porteur@impact.bj',       'livreur',        'bou_informatique',  true, true),
  (:VOISIN::uuid,  'voisin@impact.bj',        'livreur',        'bou_essai_voisine', true, true),
  (:ADJOINT::uuid, 'adjoint@bizzoo.bj',       'administrateur', null,                true, true)
on conflict (id) do update
   set role = excluded.role, boutique_id = excluded.boutique_id,
       actif = true, peut_commandes = true;

-- Des prix qui se relisent de tête.
insert into public.produits
  (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values
  ('prod_ac_a', 'bou_informatique',  'Imprimante',   15000, 'sc_hightech_accessoires', 99, true),
  ('prod_ac_b', 'bou_essai_voisine', 'Sacoche',       5000, 'sc_hightech_accessoires', 99, true),
  ('prod_ac_c', 'bou_informatique',  'Câble USB',      750, 'sc_hightech_accessoires', 99, true),
  ('prod_ac_d', 'bou_informatique',  'Adaptateur',    1234, 'sc_hightech_accessoires', 99, true),
  ('prod_ac_e', 'bou_informatique',  'Autocollant',     80, 'sc_hightech_accessoires', 99, true)
on conflict (id) do update
   set prix = excluded.prix, stock = 99, disponible = true;
insert into public.produits_prive (produit_id, prix_grossiste) values
  ('prod_ac_a', 10000), ('prod_ac_b', 3000)
on conflict (produit_id) do update set prix_grossiste = excluded.prix_grossiste;

-- ---------------------------------------------------------
select essai.titre('1. Le taux est au superadministrateur');

select essai.egal((select taux_acompte from public.paiement where id = 1), 10,
  'il part à 10 %');

set role anon;
select essai.sans_effet($$update public.paiement set taux_acompte = 1 where id = 1$$,
  'un visiteur le baisse à 1 %');
reset role;

select essai.devenir(:KOFI::uuid);
set role authenticated;
select essai.sans_effet($$update public.paiement set taux_acompte = 1 where id = 1$$,
  'un client le baisse à 1 %');
reset role;

select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.sans_effet($$update public.paiement set taux_acompte = 1 where id = 1$$,
  'l''administrateur d''une boutique le baisse');
reset role;

-- Le compte de BIZZOO suit les commandes ; l'argent de l'enseigne n'est
-- pas à lui.
select essai.devenir(:ADJOINT::uuid);
set role authenticated;
select essai.sans_effet($$update public.paiement set taux_acompte = 1 where id = 1$$,
  'le compte de BIZZOO le baisse, commandes ouvertes ou non');
reset role;
select essai.personne();

select essai.egal((select taux_acompte from public.paiement where id = 1), 10,
  'il est toujours à 10 %');

select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.refuse($$update public.paiement set taux_acompte = 0 where id = 1$$,
  'le superadmin le met à 0 % : plus rien n''écarterait les commandes fictives');
select essai.refuse($$update public.paiement set taux_acompte = 101 where id = 1$$,
  'ni à 101 %');
update public.paiement set taux_acompte = 25 where id = 1;
reset role;
select essai.personne();
select essai.egal((select taux_acompte from public.paiement where id = 1), 25,
  'le superadmin le passe à 25 %');
update public.paiement set taux_acompte = 10 where id = 1;

-- ---------------------------------------------------------
select essai.titre('2. La base calcule l''acompte');

set role anon;
select public.creer_commande('{"nom":"Awa","tel":"97000321"}'::jsonb,
  '[{"produit_id":"prod_ac_a","quantite":1}]'::jsonb, '', true) as sortie \gset
reset role;
select :'sortie'::jsonb ->> 'id' as awa \gset

select essai.egal((:'sortie'::jsonb ->> 'total')::int, 15000, 'le total : 15 000');
select essai.egal((:'sortie'::jsonb ->> 'taux_acompte')::int, 10, 'le taux du jour : 10 %');
select essai.egal((:'sortie'::jsonb ->> 'acompte')::int, 1500, 'l''acompte : 1 500');
select essai.egal((:'sortie'::jsonb ->> 'reste')::int, 13500, 'le reste à la livraison : 13 500');
select essai.egal((:'sortie'::jsonb -> 'boutiques' -> 0 ->> 'a_encaisser')::int, 13500,
  'la boutique sait ce qu''elle encaissera');
select essai.egal((select acompte from public.commandes where id = :'awa'), 1500,
  'et c''est ce qui est figé sur la commande');

-- UNE APPLICATION D'AVANT ne demande rien : elle fait payer le total,
-- et sa commande se paie en entier — avec le code promo comme sans.
set role anon;
select public.creer_commande('{"nom":"Awa","tel":"97000321"}'::jsonb,
  '[{"produit_id":"prod_ac_a","quantite":1}]'::jsonb, '') as ancienne \gset
select public.creer_commande('{"nom":"Awa","tel":"97000321"}'::jsonb,
  '[{"produit_id":"prod_ac_a","quantite":1}]'::jsonb) as plus_ancienne \gset
reset role;
select essai.egal((:'ancienne'::jsonb ->> 'acompte')::int, 15000,
  'l''application 3.54 (trois paramètres) paie le total');
select essai.egal((:'ancienne'::jsonb ->> 'taux_acompte')::int, 100, 'son taux : 100 %');
select essai.egal((:'ancienne'::jsonb ->> 'reste')::int, 0, 'rien à la livraison');
select essai.egal((:'plus_ancienne'::jsonb ->> 'acompte')::int, 15000,
  'celle d''avant les codes (deux paramètres) aussi');
select :'ancienne'::jsonb ->> 'id' as ancienne_id \gset

-- Les bornes.
set role anon;
select public.creer_commande('{"nom":"Awa","tel":"97000321"}'::jsonb,
  '[{"produit_id":"prod_ac_c","quantite":1}]'::jsonb, '', true) as petite \gset
select public.creer_commande('{"nom":"Awa","tel":"97000321"}'::jsonb,
  '[{"produit_id":"prod_ac_e","quantite":1}]'::jsonb, '', true) as minuscule \gset
select public.creer_commande('{"nom":"Awa","tel":"97000321"}'::jsonb,
  '[{"produit_id":"prod_ac_d","quantite":1}]'::jsonb, '', true) as impaire \gset
reset role;
select essai.egal((:'petite'::jsonb ->> 'acompte')::int, 100,
  '750 FCFA : 10 % feraient 75, l''acompte monte à 100 — le minimum de FeexPay');
select essai.egal((:'petite'::jsonb ->> 'reste')::int, 650, 'reste 650');
select essai.egal((:'minuscule'::jsonb ->> 'acompte')::int, 80,
  '80 FCFA : jamais plus que le total');
select essai.egal((:'impaire'::jsonb ->> 'acompte')::int, 124,
  '1 234 FCFA : 123,40 arrondi au franc supérieur, 124');

-- APRÈS LE CODE PROMO : l'acompte se prend sur ce que le client doit.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select public.enregistrer_code('ACOMPTE10', 'Essai de l''acompte', 'pourcent', 10,
  0, 0, false, null::date, true) as code_pose \gset
reset role;
select essai.personne();
set role anon;
select public.creer_commande('{"nom":"Awa","tel":"97000321"}'::jsonb,
  '[{"produit_id":"prod_ac_a","quantite":1}]'::jsonb, 'ACOMPTE10', true) as promo \gset
reset role;
select essai.egal((:'promo'::jsonb ->> 'total')::int, 13500, 'le code retire 1 500 : total 13 500');
select essai.egal((:'promo'::jsonb ->> 'acompte')::int, 1350,
  'l''acompte se prend sur 13 500, pas sur 15 000');
select essai.egal((:'promo'::jsonb ->> 'reste')::int, 12150, 'reste 12 150');

-- ---------------------------------------------------------
select essai.titre('3. L''acompte est figé, et personne ne le réécrit');

update public.paiement set taux_acompte = 30 where id = 1;
set role anon;
select public.creer_commande('{"nom":"Awa","tel":"97000321"}'::jsonb,
  '[{"produit_id":"prod_ac_a","quantite":1}]'::jsonb, '', true) as trente \gset
reset role;
select essai.egal((:'trente'::jsonb ->> 'acompte')::int, 4500, 'à 30 %, une commande neuve : 4 500');
select essai.egal((select acompte from public.commandes where id = :'awa'), 1500,
  'celle d''avant garde ses 1 500');
select essai.egal((select taux_acompte from public.commandes where id = :'awa'), 10,
  'et son taux de 10 %');
update public.paiement set taux_acompte = 10 where id = 1;

select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.refuse(format($$update public.commandes set acompte = 1 where id = %L$$, :'awa'),
  'le superadmin baisse l''acompte d''une commande');
select essai.refuse(format($$update public.commandes set verse = 15000 where id = %L$$, :'awa'),
  'ni ne déclare un versement');
select essai.refuse(format($$update public.commandes set taux_acompte = 1 where id = %L$$, :'awa'),
  'ni ne change son taux');
reset role;
select essai.personne();

select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.sans_effet(format($$update public.commandes set acompte = 1 where id = %L$$, :'awa'),
  'la boutique non plus');
reset role;
select essai.personne();

set role anon;
select essai.sans_effet(format($$update public.commandes set acompte = 1 where id = %L$$, :'awa'),
  'ni un visiteur');
reset role;

-- Même une écriture directe — si une règle d'insertion s'ouvrait un jour
-- par erreur — n'apporterait ni acompte ni versement.
insert into public.commandes (id, client_tel, acompte, verse, taux_acompte)
values ('cmd_ac_force', '97000000', 1, 99999, 1);
select essai.verifie((select acompte is null and verse is null and taux_acompte is null
                        from public.commandes where id = 'cmd_ac_force'),
  'une commande écrite à la main naît sans acompte ni versement');
delete from public.commandes where id = 'cmd_ac_force';

-- ---------------------------------------------------------
select essai.titre('4. L''agrégateur demande l''acompte');

select public.commande_pour_paiement(:'awa', '97000321') as pour \gset
select essai.egal((:'pour'::jsonb ->> 'total')::int, 1500,
  'la fonction Edge de FeexPay demande 1 500 : l''acompte');
select essai.egal((:'pour'::jsonb ->> 'total_commande')::int, 15000,
  'le total de la commande voyage à part');

select public.noter_reference(:'awa', 'REF-ACOMPTE-1', 'feexpay', 'MTN') as ref_ok \gset
select essai.egal(
  (select attendu from public.versements
    where commande_id = :'awa' and verdict = 'ouverte' order by id desc limit 1),
  1500::bigint, 'le journal attend 1 500');

select public.marquer_payee(:'awa', 'TRX-ACOMPTE-1', 1000, 'feexpay') as r1 \gset
select essai.verifie((:'r1'::jsonb ->> 'incomplet')::boolean, '1 000 sur 1 500 : incomplet');
select essai.egal((select etat from public.commandes where id = :'awa'), 'a_payer',
  'la commande attend toujours');
select essai.verifie(
  (select remarque like '%1000 reçus sur 1500 attendus%' from public.commandes where id = :'awa'),
  'la remarque dit ce qui manque, sur l''acompte');
select essai.egal((select verse from public.commandes where id = :'awa'), null::int,
  'rien n''est compté comme versé');

select public.marquer_payee(:'awa', 'TRX-ACOMPTE-2', 1500, 'feexpay') as r2 \gset
select essai.egal((select etat from public.commandes where id = :'awa'), 'payee',
  'l''acompte reçu, la commande part');
select essai.egal((select verse from public.commandes where id = :'awa'), 1500,
  'le versé : 1 500');
select essai.egal(
  (select detail from public.versements where commande_id = :'awa' and verdict = 'payee'),
  'Acompte encaissé.', 'le journal dit « Acompte encaissé »');
select essai.egal(
  (select attendu::int from public.versements where commande_id = :'awa' and verdict = 'payee'),
  1500, 'pour 1 500 attendus');
select public.marquer_payee(:'awa', 'TRX-ACOMPTE-2', 1500, 'feexpay') as r3 \gset
select essai.verifie((:'r3'::jsonb ->> 'deja')::boolean, 'rejoué : rien de plus');

-- Ce que le client sans compte retrouve, avec son numéro.
set role anon;
select public.suivre_commande(:'awa', '97000321') as suivi \gset
reset role;
select essai.egal((:'suivi'::jsonb ->> 'acompte')::int, 1500, 'le suivi dit l''acompte');
select essai.egal((:'suivi'::jsonb ->> 'verse')::int, 1500, 'ce qui a été versé');
select essai.egal((:'suivi'::jsonb ->> 'reste')::int, 13500, 'et ce qui reste à payer');
select essai.egal((:'suivi'::jsonb -> 'restes' ->> 'bou_informatique')::int, 13500,
  'boutique par boutique');

-- L'application d'avant paie le total : rien ne reste.
select public.marquer_payee(:'ancienne_id', 'TRX-ACOMPTE-ANC', 15000, 'feexpay') as r4 \gset
select essai.egal((select verse from public.commandes where id = :'ancienne_id'), 15000,
  'l''application d''avant : 15 000 versés');
select essai.egal(
  (select coalesce(sum(a_encaisser), 0)::int from public.restes_par_boutique(:'ancienne_id')), 0,
  'il ne reste rien à encaisser');
select essai.egal(
  (select detail from public.versements where commande_id = :'ancienne_id' and verdict = 'payee'),
  'Versement encaissé.', 'et le journal parle d''un versement, pas d''un acompte');

-- Un client qui paie plus que l'acompte ne doit plus rien à la porte.
select :'trente'::jsonb ->> 'id' as trente_id \gset
select public.marquer_payee(:'trente_id', 'TRX-ACOMPTE-TOUT', 15000, 'feexpay') as r5 \gset
select essai.egal(
  (select coalesce(sum(a_encaisser), 0)::int from public.restes_par_boutique(:'trente_id')), 0,
  'tout payé en ligne : rien à la livraison');

-- ---------------------------------------------------------
select essai.titre('5. Le reste se partage entre les boutiques');

select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97222222"}'::jsonb,
  '[{"produit_id":"prod_ac_a","quantite":1},
    {"produit_id":"prod_ac_b","quantite":1}]'::jsonb, '', true) as duo \gset
select public.creer_commande('{"nom":"Kofi","tel":"97222222"}'::jsonb,
  '[{"produit_id":"prod_ac_d","quantite":1},
    {"produit_id":"prod_ac_b","quantite":1}]'::jsonb, '', true) as arrondi \gset
reset role;
select essai.personne();
select :'duo'::jsonb ->> 'id' as duo_id \gset
select :'arrondi'::jsonb ->> 'id' as arrondi_id \gset

select essai.egal((:'duo'::jsonb ->> 'acompte')::int, 2000, '20 000 de panier : 2 000 d''acompte');
select essai.egal(
  (select (b ->> 'a_encaisser')::int from jsonb_array_elements(:'duo'::jsonb -> 'boutiques') b
    where b ->> 'id' = 'bou_informatique'), 13500,
  'l''informatique encaissera 13 500');
select essai.egal(
  (select (b ->> 'a_encaisser')::int from jsonb_array_elements(:'duo'::jsonb -> 'boutiques') b
    where b ->> 'id' = 'bou_essai_voisine'), 4500,
  'la voisine 4 500');

-- 6 234 de panier : 624 d'acompte, 5 610 de reste, qui ne se coupe pas
-- juste. La somme des parts tombe quand même au franc près.
select essai.egal((:'arrondi'::jsonb ->> 'reste')::int, 5610, '6 234 de panier : 5 610 de reste');
select essai.egal(
  (select sum((b ->> 'a_encaisser')::int)::int
     from jsonb_array_elements(:'arrondi'::jsonb -> 'boutiques') b), 5610,
  'les deux parts font 5 610, au franc près');
select essai.egal(
  (select (b ->> 'a_encaisser')::int from jsonb_array_elements(:'arrondi'::jsonb -> 'boutiques') b
    where b ->> 'id' = 'bou_essai_voisine'), 4500,
  'le franc d''arrondi va à la plus grosse part');

select public.marquer_payee(:'duo_id', 'TRX-ACOMPTE-DUO', 2000, 'feexpay') as r6 \gset
select essai.egal((select etat from public.commandes where id = :'duo_id'), 'payee',
  'Kofi a versé ses 2 000');

-- ---------------------------------------------------------
select essai.titre('6. Chacun ne voit que ce qui le regarde');

select essai.devenir(:KOFI::uuid);
set role authenticated;
select essai.egal(
  (select public.restes(c) from public.commandes c where c.id = :'duo_id'),
  '{"reste": 18000, "boutiques": {"bou_informatique": 13500, "bou_essai_voisine": 4500}}'::jsonb,
  'le client voit tout ce qui lui reste à payer, boutique par boutique');
-- Des montants inventés n'y changent rien : la commande est relue.
select essai.egal(
  (select (public.restes(essai.fabriquee(:'duo_id', 1, 999999)) ->> 'reste')::int), 18000,
  'des montants fabriqués ne changent rien');
-- Une commande qui n'est pas la sienne : rien.
select essai.egal(public.restes(essai.fabriquee(:'awa', 15000, 0)), null::jsonb,
  'la commande d''un autre : rien');
reset role;

select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.egal(
  (select public.restes(c) from public.commandes c where c.id = :'duo_id'),
  '{"reste": 13500, "boutiques": {"bou_informatique": 13500}}'::jsonb,
  'l''informatique voit sa part, et seulement la sienne');
reset role;

select essai.devenir(:EQUIPE::uuid);
set role authenticated;
select essai.egal(
  (select public.restes(c) from public.commandes c where c.id = :'duo_id'),
  '{"reste": 4500, "boutiques": {"bou_essai_voisine": 4500}}'::jsonb,
  'la voisine, la sienne');
reset role;

select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.egal(
  (select (public.restes(c) ->> 'reste')::int from public.commandes c where c.id = :'duo_id'), 18000,
  'le superadmin voit tout');
reset role;

select essai.devenir(:ADJOINT::uuid);
set role authenticated;
select essai.egal(
  (select jsonb_object_keys(public.restes(c) -> 'boutiques') from public.commandes c
    where c.id = :'duo_id' order by 1 limit 1), 'bou_essai_voisine',
  'le compte de BIZZOO aussi, commandes ouvertes');
reset role;

-- Le livreur ne lit pas les commandes ; s'il appelle la fonction en
-- direct, elle ne lui répond rien.
select essai.devenir(:PORTEUR::uuid);
set role authenticated;
select essai.egal(public.restes(essai.fabriquee(:'duo_id', 20000, 0)), null::jsonb,
  'le livreur qui appelle « restes » en direct : rien');
select essai.refuse(format($$select * from public.restes_par_boutique(%L)$$, :'duo_id'),
  'ni le calcul de la base');
reset role;
select essai.personne();

set role anon;
select essai.refuse(format($$select public.restes(essai.fabriquee(%L, 1, 1))$$, :'duo_id'),
  'un visiteur appelle « restes »');
select essai.refuse(format($$select * from public.restes_par_boutique(%L)$$, :'duo_id'),
  'ou le calcul de la base');
reset role;

-- ---------------------------------------------------------
select essai.titre('7. Le livreur voit ce qu''il encaisse');

select essai.devenir(:CHEF::uuid);
set role authenticated;
update public.commande_lignes set etat = 'preparee'
 where commande_id = :'duo_id' and boutique_id = 'bou_informatique';
select public.assigner_livreur(:'duo_id', 'bou_informatique', :PORTEUR::uuid) as confie1 \gset
reset role;

select essai.devenir(:EQUIPE::uuid);
set role authenticated;
update public.commande_lignes set etat = 'preparee'
 where commande_id = :'duo_id' and boutique_id = 'bou_essai_voisine';
select public.assigner_livreur(:'duo_id', 'bou_essai_voisine', :VOISIN::uuid) as confie2 \gset
reset role;

select essai.devenir(:PORTEUR::uuid);
set role authenticated;
select essai.egal(
  (select a_encaisser::int from public.mes_livraisons() where commande_id = :'duo_id'), 13500,
  'le livreur de l''informatique encaisse 13 500');
reset role;

select essai.devenir(:VOISIN::uuid);
set role authenticated;
select essai.egal(
  (select a_encaisser::int from public.mes_livraisons() where commande_id = :'duo_id'), 4500,
  'celui de la voisine, 4 500');
reset role;
select essai.personne();

-- UN ARTICLE ANNULÉ NE SE PAIE PAS. La voisine ne peut pas servir : le
-- client ne doit plus que l'imprimante, moins son acompte.
select essai.devenir(:EQUIPE::uuid);
set role authenticated;
update public.commande_lignes set etat = 'annulee'
 where commande_id = :'duo_id' and boutique_id = 'bou_essai_voisine';
reset role;

select essai.devenir(:PORTEUR::uuid);
set role authenticated;
select essai.egal(
  (select a_encaisser::int from public.mes_livraisons() where commande_id = :'duo_id'), 13000,
  'la sacoche annulée : 15 000 d''articles moins 2 000 d''acompte, 13 000 à encaisser');
reset role;

select essai.devenir(:VOISIN::uuid);
set role authenticated;
select essai.egal(
  (select count(*)::int from public.mes_livraisons() where commande_id = :'duo_id'), 0,
  'la course annulée quitte la liste du livreur de la voisine');
reset role;
select essai.personne();

select essai.egal(
  (select a_encaisser::int from public.restes_par_boutique(:'duo_id')
    where boutique_id = 'bou_essai_voisine'), 0,
  'la voisine n''a plus rien à encaisser');

-- ---------------------------------------------------------
select essai.titre('8. Les notifications disent l''acompte et le reste');

select essai.egal(
  (select titre from public.notifications
    where commande_id = :'duo_id' and type = 'commande_payee' and destinataire = :KOFI::uuid),
  'Acompte reçu', 'le client : « Acompte reçu »');
select essai.verifie(
  (select corps like '%Reste à payer à la livraison : 18 000 FCFA.%' from public.notifications
    where commande_id = :'duo_id' and type = 'commande_payee' and destinataire = :KOFI::uuid),
  'avec ce qui lui reste à payer : 18 000 FCFA');
select essai.verifie(
  (select titre = 'Nouvelle commande confirmée'
      and corps like '%13 500 FCFA à encaisser à la livraison.%'
     from public.notifications
    where commande_id = :'duo_id' and type = 'commande_payee' and destinataire = :CHEF::uuid),
  'l''informatique : 13 500 FCFA à encaisser');
select essai.verifie(
  (select corps like '%4 500 FCFA à encaisser à la livraison.%' from public.notifications
    where commande_id = :'duo_id' and type = 'commande_payee' and destinataire = :EQUIPE::uuid),
  'la voisine : 4 500 FCFA');
select essai.verifie(
  (select titre = 'Acompte encaissé'
      and corps like '%acompte de 2 000 FCFA encaissé, 18 000 FCFA à encaisser à la livraison.%'
     from public.notifications
    where commande_id = :'duo_id' and type = 'commande_payee' and destinataire = :ENSEIGNE::uuid),
  'le superadmin : l''acompte encaissé et le reste');
select essai.egal(
  (select titre from public.notifications
    where commande_id = :'duo_id' and type = 'commande_payee' and destinataire = :ADJOINT::uuid),
  'Nouvelle commande confirmée', 'le compte de BIZZOO : « Nouvelle commande confirmée »');

-- Une commande réglée en entier garde les mots d'avant.
select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97222222"}'::jsonb,
  '[{"produit_id":"prod_ac_c","quantite":1}]'::jsonb, '') ->> 'id' as entiere \gset
reset role;
select essai.personne();
select public.marquer_payee(:'entiere', 'TRX-ACOMPTE-ENTIERE', 750, 'feexpay') as r7 \gset
select essai.verifie(
  (select titre = 'Paiement reçu' and corps not like '%Reste%' from public.notifications
    where commande_id = :'entiere' and type = 'commande_payee' and destinataire = :KOFI::uuid),
  'tout payé : « Paiement reçu », sans reste');

-- ---------------------------------------------------------
select essai.titre('9. L''enseigne se porte garante de l''acompte');

set role anon;
select public.creer_commande('{"nom":"Awa","tel":"97000321"}'::jsonb,
  '[{"produit_id":"prod_ac_a","quantite":1}]'::jsonb, '', true) ->> 'id' as garantie \gset
reset role;
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select public.confirmer_paiement(:'garantie') as conf \gset
reset role;
select essai.personne();
select essai.egal((select verse from public.commandes where id = :'garantie'), 1500,
  'confirmée à la main : 1 500 versés, pas 15 000');
select essai.verifie(
  (select fournisseur = 'main' and attendu = 1500 and recu = 1500 from public.versements
    where commande_id = :'garantie' and verdict = 'payee'),
  'le journal note 1 500, encaissés « à la main »');
select essai.egal(
  (select sum(a_encaisser)::int from public.restes_par_boutique(:'garantie')), 13500,
  'et 13 500 restent à encaisser à la livraison');

-- ---------------------------------------------------------
select essai.titre('10. Une commande d''avant l''acompte');

set role anon;
select public.creer_commande('{"nom":"Awa","tel":"97000321"}'::jsonb,
  '[{"produit_id":"prod_ac_a","quantite":1}]'::jsonb, '', true) ->> 'id' as davant \gset
reset role;
select essai.oublier_acompte(:'davant');
select essai.egal(
  (select (public.commande_pour_paiement(:'davant', '97000321') ->> 'total')::int), 15000,
  'sans acompte, l''agrégateur demande le total');
select essai.egal(
  (select coalesce(sum(a_encaisser), 0)::int from public.restes_par_boutique(:'davant')), 0,
  'et rien ne restera pour la livraison');
select public.marquer_payee(:'davant', 'TRX-ACOMPTE-DAVANT', 1500, 'feexpay') as r8 \gset
select essai.verifie((:'r8'::jsonb ->> 'incomplet')::boolean,
  '1 500 ne la règlent pas : elle se payait en entier');
select public.marquer_payee(:'davant', 'TRX-ACOMPTE-DAVANT2', 15000, 'feexpay') as r9 \gset
select essai.egal((select etat from public.commandes where id = :'davant'), 'payee',
  '15 000 la règlent');
