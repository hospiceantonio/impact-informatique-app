-- =========================================================
-- Une course remise par l'administration se retire (3.80.0)
--
-- Ce qu'on prouve :
--   1. payée, la commande est proposée aux livreurs ;
--   2. l'administration la met « Remise au client » sans livreur : les
--      demandes passent lues, chaque livreur alerté reçoit « Course
--      retirée » (qui ne sonne pas), elle sort de leurs courses proposées,
--      et l'écran des commandes n'attend plus de livreur ;
--   3. une course qu'un livreur a prise puis met en route : il ne reçoit
--      pas « Course retirée » pour SA course ;
--   4. les demandes restées ouvertes d'avant se ferment.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set R1 '''aeae0000-0000-0000-0000-0000000000a1'''
\set R2 '''aeae0000-0000-0000-0000-0000000000a2'''

update public.cascade_reglage set actif = false where id = 1;

select essai.titre('Le décor : deux livreurs de BIZZOO');
insert into auth.users (id, email) values (:R1::uuid, 'r1.retiree@essai.bj'), (:R2::uuid, 'r2.retiree@essai.bj')
on conflict do nothing;
update public.profils p set role = 'livreur', actif = true, boutique_id = null, nom = v.n, tel = v.t
  from (values (:R1::uuid, 'Rachid', '0196810001'), (:R2::uuid, 'Rosine', '0196810002')) as v(i, n, t)
 where p.id = v.i;
insert into public.positions_livreurs (profil_id, latitude, longitude, adresse)
select i, 6.37, 2.42, 'Cotonou' from unnest(array[:R1::uuid, :R2::uuid]) i
on conflict (profil_id) do nothing;
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set actif = true, ouvertures = null where id in ('bou_informatique', 'bou_essai_voisine');
reset role; select essai.personne();
-- Deux boutiques : une livraison groupée, proposée à tous les livreurs de BIZZOO.
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible) values
  ('prod_retiree', 'bou_informatique', 'Souris retirée', 4000, 'sc_hightech_accessoires', 50, true),
  ('prod_retiree_b', 'bou_essai_voisine', 'Tapis retiré', 2000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true;

create function pg_temp.commande_payee(trx text) returns text language plpgsql as $$
declare g jsonb;
begin
  perform essai.devenir('ffffffff-2222-2222-2222-222222222222'::uuid);
  set local role authenticated;
  g := public.creer_commande('{"nom":"Rita","tel":"97666020","adresse":"Akpakpa"}'::jsonb,
    '[{"produit_id":"prod_retiree","quantite":1},{"produit_id":"prod_retiree_b","quantite":1}]'::jsonb,
    '', true, true);
  reset role;
  perform essai.personne();
  perform public.marquer_payee(g ->> 'id', trx, (g ->> 'acompte')::int, 'feexpay');
  return g ->> 'id';
end $$;
create function pg_temp.proposees(qui uuid) returns text[] language plpgsql as $$
declare r text[];
begin
  perform essai.devenir(qui);
  set local role authenticated;
  select array_agg(x.commande_id) into r from public.courses_proposees() x;
  reset role;
  perform essai.personne();
  return coalesce(r, '{}');
end $$;

select essai.titre('1. Payée : proposée aux livreurs');
select pg_temp.commande_payee('TRX-RETIREE-1') as cmd \gset
select essai.verifie((select count(*) from public.notifications
                       where commande_id = :'cmd' and type = 'course_proposee' and lue_le is null
                         and destinataire in (:R1::uuid, :R2::uuid)) = 2, 'les deux la reçoivent, non lue');
select essai.verifie(:'cmd' = any(pg_temp.proposees(:R1::uuid)), 'elle est dans les courses de Rachid');

select essai.titre('2. L''administration la met « Remise au client » : la course se retire');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.commande_lignes set etat = 'remise' where commande_id = :'cmd';
select essai.verifie(not exists (select 1 from public.livraison_des_commandes(array[:'cmd'])),
  'l''écran des commandes n''attend plus de livreur');
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.commande_lignes where commande_id = :'cmd' and etat = 'remise'), 2,
  'la commande est remise');
select essai.verifie(not exists (select 1 from public.notifications
                                  where commande_id = :'cmd' and type = 'course_proposee' and lue_le is null),
  'les demandes passent lues : plus rien ne sonne');
select essai.egal((select count(*)::int from public.notifications
                    where commande_id = :'cmd' and type = 'course_retiree' and not sonne
                      and corps like '%remise au client par BIZZOO%'
                      and destinataire in (:R1::uuid, :R2::uuid)), 2,
  'chaque livreur alerté reçoit « Course retirée », sans sonnerie');
select essai.verifie(not (:'cmd' = any(pg_temp.proposees(:R1::uuid))), 'elle sort des courses de Rachid');
select essai.verifie(not (:'cmd' = any(pg_temp.proposees(:R2::uuid))), 'et de celles de Rosine');

select essai.titre('3. Un livreur prend la course et la met en route : rien pour lui');
select pg_temp.commande_payee('TRX-RETIREE-2') as cmd2 \gset
select essai.devenir(:R1::uuid); set role authenticated;
select public.prendre_course(:'cmd2') as pris \gset
reset role; select essai.personne();
update public.commande_lignes set etat = 'en_livraison' where commande_id = :'cmd2';
select essai.egal((select count(*)::int from public.notifications
                    where commande_id = :'cmd2' and type = 'course_retiree'), 0,
  'personne ne reçoit « Course retirée » : Rosine a déjà « Déjà pris », Rachid la porte');
select essai.verifie((select bool_and(lue_le is not null) from public.notifications
                       where commande_id = :'cmd2' and type = 'course_proposee' and destinataire <> :R1::uuid),
  'les demandes des autres sont lues');

select essai.titre('4. Les demandes restées ouvertes d''avant se ferment');
-- Comme avant la 3.80.0 : une demande restée non lue sur une commande remise.
update public.notifications set lue_le = null where commande_id = :'cmd' and type = 'course_proposee';
update public.notifications n set lue_le = now()
 where n.type = 'course_proposee' and n.lue_le is null
   and public.course_a_prendre(n.commande_id) <> 1;
select essai.verifie(not exists (select 1 from public.notifications
                                  where commande_id = :'cmd' and type = 'course_proposee' and lue_le is null),
  'la réparation de la mise en ligne les passe lues');

update public.cascade_reglage set actif = true where id = 1;
