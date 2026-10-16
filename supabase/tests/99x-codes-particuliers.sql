-- =========================================================
-- Les codes des particuliers : commission, solde, retraits
--
-- Ce qu'on prouve :
--   1. seul le superadministrateur donne un code à un particulier ;
--   2. le propriétaire ne se sert pas de son propre code ;
--   3. le client a sa remise ; la commission ne naît qu'à la
--      LIVRAISON complète, une seule fois, au bon montant ;
--   4. elle est plafonnée par ce que l'enseigne gagne encore ;
--   5. une commande annulée ne rapporte rien ;
--   6. le solde, les retraits : pas plus que le solde, refus et
--      versement par le superadministrateur seul ;
--   7. personne n'écrit dans ces tables à la main.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set PORTEUR2 '''cccccccc-7777-7777-7777-777777777777'''
\set PARRAIN  '''ffffffff-1111-1111-1111-111111111111'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''

select essai.titre('Le décor : un particulier, une acheteuse, deux produits');

insert into auth.users (id, email) values
  (:PARRAIN::uuid, 'parrain@essai.bj'),
  (:ACHETEUR::uuid, 'acheteuse@essai.bj')
on conflict do nothing;
insert into public.clients (id, nom, tel) values
  (:PARRAIN::uuid, 'Rodrigue', '97666001'),
  (:ACHETEUR::uuid, 'Afi', '97666002')
on conflict (id) do nothing;

insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_parrain', 'bou_informatique', 'Casque', 10000, 'sc_hightech_accessoires', 100, true),
       ('prod_serre', 'bou_informatique', 'Câble', 10000, 'sc_hightech_accessoires', 100, true)
on conflict (id) do update set prix = excluded.prix, stock = 100, disponible = true;
insert into public.produits_prive (produit_id, prix_grossiste)
values ('prod_parrain', 6000), ('prod_serre', 9500)
on conflict (produit_id) do update set prix_grossiste = excluded.prix_grossiste;

-- ---------------------------------------------------------
select essai.titre('1. Seul le superadministrateur donne un code');

select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse(
  format($$select public.creer_code_parrain(%L::uuid, 'RODRIGUE', 5, 2, 'Rodrigue')$$, :PARRAIN),
  'une boutique ne crée pas de code de particulier');
reset role; select essai.personne();

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal(public.creer_code_parrain(:PARRAIN::uuid, 'rodrigue', 5, 2, 'Rodrigue'),
  'RODRIGUE', 'le superadministrateur le crée');
select essai.egal(public.creer_code_parrain(:PARRAIN::uuid, 'SERRE50', 0, 50, 'Rodrigue'),
  'SERRE50', 'un second, sans remise, à forte commission');
select essai.refuse(
  format($$select public.creer_code_parrain(%L::uuid, 'RODRIGUE', 5, 2, '')$$, :PARRAIN),
  'un code qui existe déjà est refusé');
select essai.refuse(
  format($$select public.creer_code_parrain(%L::uuid, 'TROPCHER', 5, 80, '')$$, :PARRAIN),
  'une commission au-delà de 50 % est refusée');
select essai.refuse(
  format($$select public.creer_code_parrain(%L::uuid, 'EQUIPE1', 5, 2, '')$$, :CHEF),
  'un compte de l''équipe ne reçoit pas de code de particulier');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('2. Le propriétaire ne se sert pas de son code');

select essai.devenir(:PARRAIN::uuid); set role authenticated;
select essai.verifie(
  not (public.verifier_code('RODRIGUE', '[{"produit_id":"prod_parrain","quantite":1}]'::jsonb)
         ->> 'ok')::boolean,
  'il est refusé à son propriétaire');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('3. La remise du client, puis la commission à la livraison');

select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.egal(
  (public.verifier_code('RODRIGUE', '[{"produit_id":"prod_parrain","quantite":2}]'::jsonb)
     ->> 'remise')::bigint, 1000::bigint,
  'le client voit sa remise : 5 % de 20 000');
select public.creer_commande('{"nom":"Afi","tel":"97666002","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_parrain","quantite":2}]'::jsonb, 'RODRIGUE') ->> 'id' as cmd \gset
reset role; select essai.personne();

select essai.egal((select total::bigint from public.commandes where id = :'cmd'), 19000::bigint,
  'la commande vaut 19 000 après la remise');
select public.marquer_payee(:'cmd', 'TRX-PARRAIN',
  (select coalesce(acompte, total) from public.commandes where id = :'cmd'), 'feexpay') as e \gset
select essai.egal((select count(*)::int from public.gains_parrain where commande_id = :'cmd'), 0,
  'payée : pas encore de commission');

select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'preparee' where commande_id = :'cmd';
select public.assigner_livreur(:'cmd', 'bou_informatique', :PORTEUR2::uuid) as n \gset
reset role; select essai.personne();

select essai.devenir(:PORTEUR2::uuid); set role authenticated;
select public.avancer_livraison(:'cmd', 'bou_informatique', 'en_livraison') as a \gset
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.gains_parrain where commande_id = :'cmd'), 0,
  'en route : toujours rien');

select essai.devenir(:PORTEUR2::uuid); set role authenticated;
select public.avancer_livraison(:'cmd', 'bou_informatique', 'remise') as b \gset
reset role; select essai.personne();
select essai.egal((select montant::bigint from public.gains_parrain where commande_id = :'cmd'), 380::bigint,
  'livrée : 2 % de 19 000, soit 380, crédités au propriétaire');
select essai.egal((select parrain from public.gains_parrain where commande_id = :'cmd'), :PARRAIN::uuid,
  'sur SON compte');
select essai.egal(
  (select count(*)::int from public.notifications
    where destinataire = :PARRAIN::uuid and type = 'commission'), 1,
  'et il est prévenu');

-- Rejouer ne crédite pas deux fois.
select essai.egal(public.crediter_parrain(:'cmd'), 0::bigint, 'rejouer ne recrédite pas');
select essai.egal((select count(*)::int from public.gains_parrain where commande_id = :'cmd'), 1,
  'une seule commission par commande');

-- ---------------------------------------------------------
select essai.titre('4. Plafonnée par ce que l''enseigne gagne');

select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666002","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_serre","quantite":1}]'::jsonb, 'SERRE50') ->> 'id' as serre \gset
reset role; select essai.personne();
select essai.egal((select code_promo from public.commandes where id = :'serre'), 'SERRE50',
  'un code sans remise reste sur la commande : il porte la commission');
select public.marquer_payee(:'serre', 'TRX-SERRE',
  (select coalesce(acompte, total) from public.commandes where id = :'serre'), 'feexpay') as e2 \gset
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'preparee' where commande_id = :'serre';
select public.assigner_livreur(:'serre', 'bou_informatique', :PORTEUR2::uuid) as n2 \gset
reset role; select essai.personne();
select essai.devenir(:PORTEUR2::uuid); set role authenticated;
select public.avancer_livraison(:'serre', 'bou_informatique', 'en_livraison') as c1 \gset
select public.avancer_livraison(:'serre', 'bou_informatique', 'remise') as c2 \gset
reset role; select essai.personne();
select essai.egal((select montant::bigint from public.gains_parrain where commande_id = :'serre'), 500::bigint,
  '50 % de 10 000 ramenés à 500 : ce que l''enseigne gagne sur ce câble');

-- ---------------------------------------------------------
select essai.titre('5. Une commande annulée ne rapporte rien');

select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666002","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_parrain","quantite":1}]'::jsonb, 'RODRIGUE') ->> 'id' as annulee \gset
reset role; select essai.personne();
select public.marquer_payee(:'annulee', 'TRX-ANNULEE',
  (select coalesce(acompte, total) from public.commandes where id = :'annulee'), 'feexpay') as e3 \gset
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'annulee' where commande_id = :'annulee';
reset role; select essai.personne();
select essai.egal((select count(*)::int from public.gains_parrain where commande_id = :'annulee'), 0,
  'tout annulé : aucune commission');

-- ---------------------------------------------------------
select essai.titre('6. Le solde, les retraits');

select essai.devenir(:PARRAIN::uuid); set role authenticated;
select essai.egal((public.mon_solde_parrain() ->> 'solde')::bigint, 880::bigint,
  'il voit son solde : 380 + 500');
select essai.egal(jsonb_array_length(public.mon_solde_parrain() -> 'gains'), 2,
  'et ses deux commissions');
select essai.refuse($$select public.demander_retrait(100, '0196000000', 'MTN')$$,
  'moins de 500 FCFA : refusé');
select essai.refuse($$select public.demander_retrait(5000, '0196000000', 'MTN')$$,
  'plus que le solde : refusé');
select public.demander_retrait(500, '01 96 00 00 00', 'MTN') as r1 \gset
select essai.egal((public.mon_solde_parrain() ->> 'solde')::bigint, 380::bigint,
  'la demande bloque le montant : il reste 380');
select essai.refuse($$select public.demander_retrait(500, '0196000000', 'MTN')$$,
  'on ne redemande pas ce qui est déjà demandé');
reset role; select essai.personne();

select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.verifie(public.mon_solde_parrain() is null, 'l''acheteuse n''a pas de solde');
select essai.egal((select count(*)::int from public.retraits_parrain), 0,
  'et ne lit pas les retraits des autres');
select essai.refuse($$insert into public.gains_parrain (parrain, montant) values (auth.uid(), 99999)$$,
  'personne ne s''écrit une commission');
reset role; select essai.personne();

select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse(format($$select public.traiter_retrait(%s, true, 'X', '')$$, :'r1'),
  'une boutique ne verse pas les retraits');
reset role; select essai.personne();

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.retraits_a_traiter() where etat = 'demande'), 1,
  'le superadministrateur voit la demande');
select essai.egal(public.traiter_retrait(:'r1', false, '', 'numéro injoignable'), 'refusee',
  'une demande peut être refusée');
select essai.refuse(format($$select public.traiter_retrait(%s, true, 'X', '')$$, :'r1'),
  'une demande traitée ne se retraite pas');
reset role; select essai.personne();

select essai.devenir(:PARRAIN::uuid); set role authenticated;
select essai.egal((public.mon_solde_parrain() ->> 'solde')::bigint, 880::bigint,
  'refusée : le montant revient sur le solde');
select public.demander_retrait(500, '0196000000', 'MTN') as r2 \gset
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal(public.traiter_retrait(:'r2', true, 'MOMO-123', ''), 'payee', 'il la marque versée');
reset role; select essai.personne();
select essai.devenir(:PARRAIN::uuid); set role authenticated;
select essai.egal((public.mon_solde_parrain() ->> 'retire')::bigint, 500::bigint, 'versé : 500 retirés');
select essai.egal((public.mon_solde_parrain() ->> 'solde')::bigint, 380::bigint, 'il reste 380');
reset role; select essai.personne();
