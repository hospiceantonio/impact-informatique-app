-- =========================================================
-- Une livraison groupée, proposée à tous les livreurs de BIZZOO :
-- « Déjà pris par … » (3.59.0)
--
-- Ce qu'on prouve :
--   1. payée, la commande groupée est proposée à TOUS les livreurs de
--      BIZZOO (qui ont validé leur position), et à eux seuls ;
--   2. l'un la prend : les autres reçoivent « Déjà pris par <son nom> »,
--      leur demande passe lue, elle n'est plus dans leurs courses
--      proposées — lui ne reçoit rien de tel ;
--   3. un autre qui touche « Commande reçue » trop tard lit « Déjà pris
--      par <son nom> ».
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set Z1 '''aeae0000-0000-0000-0000-000000000001'''
\set Z2 '''aeae0000-0000-0000-0000-000000000002'''
\set Z3 '''aeae0000-0000-0000-0000-000000000003'''
\set LB '''aeae0000-0000-0000-0000-000000000004'''

-- (3.70.0) Ces essais éprouvent qui PEUT prendre la course : on la fait
-- partir à tous d'un coup (cascade éteinte, la règle d'avant). La cascade
-- au plus proche a ses propres essais (…-cascade-courses.sql).
update public.cascade_reglage set actif = false where id = 1;

select essai.titre('Le décor : trois livreurs de BIZZOO, un livreur de boutique');
insert into auth.users (id, email) values (:Z1::uuid, 'z1.prise@essai.bj'), (:Z2::uuid, 'z2.prise@essai.bj'),
  (:Z3::uuid, 'z3.prise@essai.bj'), (:LB::uuid, 'lb.prise@essai.bj')
on conflict do nothing;
update public.profils p set role = 'livreur', actif = true, boutique_id = v.b, nom = v.n, tel = v.t
  from (values (:Z1::uuid, null, 'Zinsou', '0196800001'), (:Z2::uuid, null, 'Zoé', '0196800002'),
               (:Z3::uuid, null, 'Zakari', '0196800003'), (:LB::uuid, 'bou_informatique', 'Lucas', '0196800004'))
       as v(i, b, n, t)
 where p.id = v.i;
insert into public.positions_livreurs (profil_id, latitude, longitude, adresse)
select i, 6.37, 2.42, 'Cotonou' from unnest(array[:Z1::uuid, :Z2::uuid, :Z3::uuid, :LB::uuid]) i
on conflict (profil_id) do nothing;
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set actif = true, ouvertures = null where id in ('bou_informatique', 'bou_essai_voisine');
reset role; select essai.personne();
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible) values
  ('prod_prise_a', 'bou_informatique', 'Routeur', 7000, 'sc_hightech_accessoires', 50, true),
  ('prod_prise_b', 'bou_essai_voisine', 'Rallonge', 3000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true;

select essai.titre('1. Payée : proposée à tous les livreurs de BIZZOO');
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Kiki","tel":"97666010","adresse":"Cadjèhoun"}'::jsonb,
  '[{"produit_id":"prod_prise_a","quantite":1},{"produit_id":"prod_prise_b","quantite":1}]'::jsonb,
  '', true, true) as g \gset
reset role; select essai.personne();
select (:'g'::jsonb ->> 'id') as cmd \gset
select public.marquer_payee(:'cmd', 'TRX-PRISE-1', (:'g'::jsonb ->> 'acompte')::int, 'feexpay') as p \gset
select essai.egal((select count(*)::int from public.notifications
                    where commande_id = :'cmd' and type = 'course_proposee'
                      and destinataire in (:Z1::uuid, :Z2::uuid, :Z3::uuid)), 3,
  'les trois livreurs de BIZZOO la reçoivent');
select essai.egal((select count(*)::int from public.notifications
                    where commande_id = :'cmd' and type = 'course_proposee' and destinataire = :LB::uuid), 0,
  'pas le livreur d''une boutique');
select essai.verifie((select bool_and(sonne) from public.notifications
                       where commande_id = :'cmd' and type = 'course_proposee'), 'elle sonne');

select essai.titre('2. Zinsou la prend : les autres sont prévenus');
select essai.devenir(:Z1::uuid); set role authenticated;
select public.prendre_course(:'cmd') as pris \gset
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.notifications
                    where commande_id = :'cmd' and type = 'course_prise' and titre = 'Déjà pris par Zinsou'
                      and destinataire in (:Z2::uuid, :Z3::uuid)), 2,
  'Zoé et Zakari reçoivent « Déjà pris par Zinsou »');
select essai.egal((select count(*)::int from public.notifications
                    where commande_id = :'cmd' and type = 'course_prise' and destinataire = :Z1::uuid), 0,
  'Zinsou, lui, ne reçoit rien de tel');
select essai.egal((select count(*)::int from public.notifications
                    where commande_id = :'cmd' and type = 'course_proposee'
                      and destinataire in (:Z2::uuid, :Z3::uuid) and lue_le is null), 0,
  'leur demande passe lue');
select essai.devenir(:Z2::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.courses_proposees() where commande_id = :'cmd'), 0,
  'elle n''est plus dans les courses proposées de Zoé');

select essai.titre('3. Trop tard : « Déjà pris par Zinsou »');
select set_config('essai.cmd', :'cmd', false) as x \gset
do $$
begin
  perform public.prendre_course(current_setting('essai.cmd'));
  raise exception 'aurait dû être refusé';
exception when others then
  if sqlerrm <> 'Déjà pris par Zinsou.' then
    raise exception 'message inattendu : %', sqlerrm;
  end if;
end $$;
select essai.verifie(true, 'Zoé, trop tard, lit « Déjà pris par Zinsou. »');
reset role; select essai.personne();
