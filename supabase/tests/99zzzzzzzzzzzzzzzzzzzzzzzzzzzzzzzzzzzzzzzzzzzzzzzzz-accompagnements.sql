-- =========================================================
-- Les accompagnements (3.80.0)
--
-- Ce qu'on prouve :
--   1. l'équipe pose les accompagnements d'un produit ; une liste mal
--      faite (maximum nul, nom vide, identifiant en double) est refusée ;
--   2. « 1 Poulet + 2 Riz » : la ligne vaut 5 000 + 2 × 1 000 = 7 000,
--      son nom le dit, la boutique touche le supplément ;
--   3. la quantité multiplie le tout ; un accompagnement à zéro ne compte
--      pas ; un même accompagnement cité deux fois s'additionne ;
--   4. au-delà du maximum, ou un accompagnement qui n'existe pas : refusé ;
--   5. sans accompagnement, rien ne change.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''

select essai.titre('Le décor : un poulet braisé, ses accompagnements');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set actif = true, ouvertures = null where id = 'bou_informatique';
reset role; select essai.personne();
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible) values
  ('prod_acc', 'bou_informatique', 'Poulet braisé', 5000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true, prix = 5000, nom = 'Poulet braisé';
create function pg_temp.commander(articles jsonb) returns jsonb language plpgsql as $$
declare g jsonb;
begin
  perform essai.devenir('ffffffff-2222-2222-2222-222222222222'::uuid);
  set local role authenticated;
  g := public.creer_commande('{"nom":"Koffi","tel":"97666555","adresse":"Cadjèhoun"}'::jsonb,
    articles, '', true, true);
  reset role;
  perform essai.personne();
  return g;
end $$;

select essai.titre('1. L''équipe pose les accompagnements');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.produits
   set accompagnements = '[{"id":"riz","nom":"Riz","prix":1000,"max":3},{"id":"alloco","nom":"Alloco","prix":500,"max":2}]'
 where id = 'prod_acc';
reset role; select essai.personne();
select essai.egal((select jsonb_array_length(accompagnements) from public.produits where id = 'prod_acc'), 2,
  'Riz et Alloco, posés par l''enseigne');
select essai.refuse($$update public.produits set accompagnements = '[{"id":"riz","nom":"Riz","prix":1000,"max":0}]'
  where id = 'prod_acc'$$, 'un maximum nul : refusé');
select essai.refuse($$update public.produits set accompagnements = '[{"id":"riz","nom":"","prix":1000,"max":2}]'
  where id = 'prod_acc'$$, 'un nom vide : refusé');
select essai.refuse($$update public.produits set accompagnements =
  '[{"id":"riz","nom":"Riz","prix":1000,"max":2},{"id":"riz","nom":"Riz blanc","prix":800,"max":2}]'
  where id = 'prod_acc'$$, 'deux fois le même identifiant : refusé');
select essai.refuse($$update public.produits set accompagnements = '[{"id":"riz","nom":"Riz","prix":-5,"max":2}]'
  where id = 'prod_acc'$$, 'un prix négatif : refusé');

select essai.titre('2. « 1 Poulet + 2 Riz » = 7 000');
select pg_temp.commander('[{"produit_id":"prod_acc","quantite":1,"accompagnements":[{"id":"riz","quantite":2}]}]'::jsonb) as g \gset
select l.prix as prix, l.nom as nom, l.supplement as sup, l.prix_bizzoo as pb, l.accompagnements as acc
  from public.commande_lignes l where l.commande_id = :'g'::jsonb ->> 'id' \gset
select essai.egal(:'prix'::int, 7000, 'la ligne vaut 5 000 + 2 × 1 000');
select essai.egal(:'nom'::text, 'Poulet braisé + 2 Riz'::text, 'son nom dit ce qu''il y a dans le plat');
select essai.egal(:'sup'::int, 2000, 'le supplément est noté à part');
select essai.verifie(:'acc'::jsonb = '[{"id":"riz","nom":"Riz","prix":1000,"quantite":2}]'::jsonb,
  'le détail, relu sur le produit (nom et prix de la base)');
select essai.egal((select (total - coalesce(frais_livraison, 0))::int from public.commandes
                    where id = :'g'::jsonb ->> 'id'), 7000, 'la commande compte 7 000 d''articles');
select essai.verifie(:'pb'::int >= 2000, 'la boutique touche le supplément (part ' || :'pb' || ')');

select essai.titre('3. Quantité, zéro, doublon');
select pg_temp.commander('[{"produit_id":"prod_acc","quantite":2,"accompagnements":[{"id":"riz","quantite":1},{"id":"alloco","quantite":0},{"id":"alloco","quantite":1},{"id":"alloco","quantite":1}]}]'::jsonb) as g2 \gset
select essai.egal((select prix from public.commande_lignes where commande_id = :'g2'::jsonb ->> 'id')::int, 7000,
  'une portion : 5 000 + 1 000 + 2 × 500');
select essai.egal((select (total - coalesce(frais_livraison, 0))::int from public.commandes
                    where id = :'g2'::jsonb ->> 'id'), 14000, 'deux plats : 14 000');
select essai.egal((select nom from public.commande_lignes where commande_id = :'g2'::jsonb ->> 'id'),
  'Poulet braisé + 2 Alloco + 1 Riz', 'Alloco cité deux fois : 2 ; à zéro : rien');

select essai.titre('4. Au-delà du maximum, ou inconnu : refusé');
select essai.refuse($$select pg_temp.commander('[{"produit_id":"prod_acc","quantite":1,"accompagnements":[{"id":"riz","quantite":4}]}]'::jsonb)$$,
  '4 Riz quand 3 au plus : refusé');
select essai.refuse($$select pg_temp.commander('[{"produit_id":"prod_acc","quantite":1,"accompagnements":[{"id":"frites","quantite":1}]}]'::jsonb)$$,
  'un accompagnement qui n''existe pas : refusé');

select essai.titre('5. Sans accompagnement, rien ne change');
select pg_temp.commander('[{"produit_id":"prod_acc","quantite":1}]'::jsonb) as g3 \gset
select essai.verifie((select prix = 5000 and nom = 'Poulet braisé' and supplement = 0 and accompagnements = '[]'::jsonb
                        from public.commande_lignes where commande_id = :'g3'::jsonb ->> 'id'),
  '5 000, « Poulet braisé », sans supplément');
