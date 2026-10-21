-- =========================================================
-- Le livreur de BIZZOO porte toute la commande (3.59.0)
--
-- Ce qu'on prouve :
--   1. une boutique confie au livreur de BIZZOO : il reçoit TOUS les
--      produits de la commande, ceux des autres boutiques aussi ; les
--      autres boutiques sont prévenues qu'il passe chez elles ;
--   2. il accepte d'un seul « Commande reçue » : toute la commande, et
--      une seule nouvelle au client ;
--   3. une part déjà confiée au livreur d'une autre boutique ne lui est
--      pas prise ;
--   4. confiée au livreur d'une boutique : les produits de CETTE
--      boutique seulement.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set LA       '''dfdfdfdf-0000-0000-0000-000000000001'''
\set LB       '''dfdfdfdf-0000-0000-0000-000000000002'''
\set BZ       '''dfdfdfdf-0000-0000-0000-000000000003'''
\set ADMB     '''dfdfdfdf-0000-0000-0000-000000000004'''

select essai.titre('Le décor : deux boutiques, leurs livreurs, un livreur de BIZZOO');
insert into auth.users (id, email) values
  (:LA::uuid, 'la.toute@essai.bj'), (:LB::uuid, 'lb.toute@essai.bj'),
  (:BZ::uuid, 'bz.toute@essai.bj'), (:ADMB::uuid, 'admb.toute@essai.bj')
on conflict do nothing;
update public.profils p set role = v.r, actif = true, boutique_id = v.b, nom = v.n, tel = v.t
  from (values (:LA::uuid, 'livreur', 'bou_informatique', 'Gildas', '0196400001'),
               (:LB::uuid, 'livreur', 'bou_essai_voisine', 'Hawa', '0196400002'),
               (:BZ::uuid, 'livreur', null, 'Ifè', '0196400003'),
               (:ADMB::uuid, 'administrateur', 'bou_essai_voisine', 'Jules', '0196400004')) as v(i, r, b, n, t)
 where p.id = v.i;
insert into public.positions_livreurs (profil_id, latitude, longitude, adresse)
select i, 6.37, 2.42, 'Cotonou' from unnest(array[:LA::uuid, :LB::uuid, :BZ::uuid]) i
on conflict (profil_id) do nothing;
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set actif = true, ouvertures = null, mode_paiement = 'acompte', taux_acompte = 50,
       frais_livraison = 1000
 where id in ('bou_informatique', 'bou_essai_voisine');
reset role; select essai.personne();
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible) values
  ('prod_tout_a', 'bou_informatique', 'Écran', 9000, 'sc_hightech_accessoires', 50, true),
  ('prod_tout_b', 'bou_essai_voisine', 'Ventilateur', 6000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true;

-- Une commande chez les deux boutiques, payée.
create function pg_temp.commande_payee(trx text) returns text language plpgsql as $$
declare g jsonb;
begin
  perform essai.devenir('ffffffff-2222-2222-2222-222222222222'::uuid);
  set local role authenticated;
  g := public.creer_commande('{"nom":"Kiki","tel":"97666009","adresse":"Akpakpa"}'::jsonb,
    '[{"produit_id":"prod_tout_a","quantite":1},{"produit_id":"prod_tout_b","quantite":2}]'::jsonb,
    '', true, true);
  reset role;
  perform essai.personne();
  perform public.marquer_payee(g ->> 'id', trx, (g ->> 'acompte')::int, 'feexpay');
  return g ->> 'id';
end $$;

select essai.titre('1. Confiée au livreur de BIZZOO : toute la commande');
select pg_temp.commande_payee('TRX-TOUT-1') as cmd \gset
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.egal(public.assigner_livreur(:'cmd', 'bou_informatique', :BZ::uuid), 2,
  'la boutique confie : les deux lignes, les siennes et celles de la voisine');
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.commande_lignes
                    where commande_id = :'cmd' and livreur_id = :BZ::uuid), 2,
  'Ifè porte tous les produits de la commande');
select essai.devenir(:BZ::uuid); set role authenticated;
select essai.egal((select string_agg(boutique_id, ',' order by boutique_id) from public.mes_livraisons()
                    where commande_id = :'cmd'), 'bou_essai_voisine,bou_informatique',
  'il voit ses deux retraits : chez chaque boutique');
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ADMB::uuid and commande_id = :'cmd' and type = 'course_confiee'
                      and titre = 'Un livreur BIZZOO passe récupérer vos produits'), 1,
  'la boutique voisine est prévenue qu''il passe chez elle');

select essai.titre('2. Un seul « Commande reçue » pour toute la commande');
select essai.devenir(:BZ::uuid); set role authenticated;
select essai.egal(public.accepter_course(:'cmd', 'bou_informatique'), 2, 'accepte d''un coup les deux parts');
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.commande_lignes
                    where commande_id = :'cmd' and recu_le is null), 0, 'plus rien en attente');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ACHETEUR::uuid and commande_id = :'cmd' and type = 'course_acceptee'), 1,
  'le client reçoit UNE nouvelle : son livreur');
select essai.verifie((select corps like '%Ifè livre votre commande%' from public.notifications
                       where destinataire = :ACHETEUR::uuid and commande_id = :'cmd' and type = 'course_acceptee'),
  'avec le nom du livreur');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :ADMB::uuid and commande_id = :'cmd' and type = 'course_acceptee'), 1,
  'la boutique voisine apprend que la course est acceptée');

select essai.titre('3. La part déjà confiée au livreur d''une autre boutique reste à lui');
select pg_temp.commande_payee('TRX-TOUT-2') as cmd2 \gset
select essai.devenir(:ADMB::uuid); set role authenticated;
select essai.egal(public.assigner_livreur(:'cmd2', 'bou_essai_voisine', :LB::uuid), 1, 'la voisine confie à Hawa');
reset role; select essai.personne();
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.egal(public.assigner_livreur(:'cmd2', 'bou_informatique', :BZ::uuid), 1,
  'la boutique confie à Ifè : sa part seulement');
reset role; select essai.personne();
select essai.egal((select livreur_id from public.commande_lignes
                    where commande_id = :'cmd2' and boutique_id = 'bou_essai_voisine'), :LB::uuid,
  'la part de la voisine reste à Hawa');

select essai.titre('4. Confiée au livreur d''une boutique : les produits de sa boutique');
select pg_temp.commande_payee('TRX-TOUT-3') as cmd3 \gset
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.egal(public.assigner_livreur(:'cmd3', 'bou_informatique', :LA::uuid), 1, 'Gildas : une ligne');
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.commande_lignes
                    where commande_id = :'cmd3' and boutique_id = 'bou_essai_voisine' and livreur_id is not null), 0,
  'la part de la voisine n''est confiée à personne');
select essai.devenir(:LA::uuid); set role authenticated;
select essai.egal(public.accepter_course(:'cmd3', 'bou_informatique'), 1, 'il accepte sa part seulement');
reset role; select essai.personne();
