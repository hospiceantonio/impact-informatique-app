-- =========================================================
-- Revendeurs et livreurs valident leur compte par leur position
--
-- Ce qu'on prouve :
--   1. un livreur sans position ne reçoit aucune course ;
--   2. il enregistre SA position lui-même — pas « 0, 0 », pas sans
--      adresse ; personne d'autre ne la pose, personne ne l'écrit à
--      la main ;
--   3. ensuite, on lui confie la course ;
--   4. sa boutique et l'enseigne lisent sa position ; une autre
--      boutique et un client, non ;
--   5. un revendeur sans position ne peut pas être validé (refusé, si) ;
--      avec sa position et son adresse, il l'est.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE  '''11111111-1111-1111-1111-111111111111'''
\set CHEF      '''22222222-2222-2222-2222-222222222222'''
\set EQUIPE    '''33333333-3333-3333-3333-333333333333'''
\set ACHETEUR  '''ffffffff-2222-2222-2222-222222222222'''
\set NOUVEAU   '''abababab-1111-1111-1111-111111111111'''
\set GROSSISTE '''abababab-2222-2222-2222-222222222222'''

select essai.titre('Le décor : un livreur tout neuf, une commande prête');

insert into auth.users (id, email) values
  (:NOUVEAU::uuid, 'nouveau.livreur@impact.bj'),
  (:GROSSISTE::uuid, 'grossiste.position@essai.bj')
on conflict do nothing;
insert into public.profils (id, email, nom, tel, role, boutique_id, actif) values
  (:NOUVEAU::uuid, 'nouveau.livreur@impact.bj', 'Codjo', '0196112233',
   'livreur', 'bou_informatique', true)
on conflict (id) do update set role = 'livreur', boutique_id = 'bou_informatique', actif = true;
delete from public.positions_livreurs where profil_id = :NOUVEAU::uuid;

insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_position', 'bou_informatique', 'Câble', 3000, 'sc_hightech_accessoires', 100, true)
on conflict (id) do update set stock = 100, disponible = true;
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select public.creer_commande('{"nom":"Afi","tel":"97666002","adresse":"Fidjrossè"}'::jsonb,
  '[{"produit_id":"prod_position","quantite":1}]'::jsonb) ->> 'id' as cmd \gset
reset role; select essai.personne();
select public.marquer_payee(:'cmd', 'TRX-POSITION',
  (select coalesce(acompte, total) from public.commandes where id = :'cmd'), 'feexpay') as p \gset
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'preparee' where commande_id = :'cmd';
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('1. Sans position, aucune course');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse(format($$select public.assigner_livreur(%L, 'bou_informatique', %L::uuid)$$,
  :'cmd', :NOUVEAU), 'confier une course à un livreur sans position : refusé');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('2. Le livreur enregistre SA position');
select essai.devenir(:NOUVEAU::uuid); set role authenticated;
select essai.refuse($$select public.enregistrer_ma_position(0, 0, 'Akpakpa')$$,
  '« 0, 0 » (un téléphone qui n''a rien trouvé) : refusé');
select essai.refuse($$select public.enregistrer_ma_position(6.37, 2.39, '')$$,
  'sans adresse : refusé');
select essai.refuse($$select public.enregistrer_ma_position(95, 2.39, 'Akpakpa')$$,
  'une latitude impossible : refusée');
select essai.refuse($$insert into public.positions_livreurs (profil_id, latitude, longitude, adresse)
  values (auth.uid(), 6.37, 2.39, 'à la main')$$, 'personne ne l''écrit à la main');
select public.enregistrer_ma_position(6.3654, 2.4183, 'Akpakpa, face au marché', 12) as pos \gset
reset role; select essai.personne();
select essai.egal((select adresse from public.positions_livreurs where profil_id = :NOUVEAU::uuid),
  'Akpakpa, face au marché', 'sa position et son adresse sont enregistrées');

select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse($$select public.enregistrer_ma_position(6.37, 2.39, 'Ganhi')$$,
  'un administrateur n''enregistre pas « sa position de livreur »');
reset role; select essai.personne();
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.refuse($$select public.enregistrer_ma_position(6.37, 2.39, 'Ganhi')$$,
  'un client non plus');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('3. Position enregistrée : la course lui est confiée');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.egal(public.assigner_livreur(:'cmd', 'bou_informatique', :NOUVEAU::uuid), 1,
  'la boutique lui confie la course');

-- ---------------------------------------------------------
select essai.titre('4. Qui lit sa position');
select essai.egal((select count(*)::int from public.positions_livreurs where profil_id = :NOUVEAU::uuid),
  1, 'sa boutique la lit');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.positions_livreurs where profil_id = :NOUVEAU::uuid),
  1, 'l''enseigne aussi');
reset role; select essai.personne();
select essai.devenir(:EQUIPE::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.positions_livreurs where profil_id = :NOUVEAU::uuid),
  0, 'une autre boutique, non');
reset role; select essai.personne();
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.egal((select count(*)::int from public.positions_livreurs), 0, 'un client, non');
reset role; select essai.personne();
set role anon;
select essai.refuse($$select * from public.positions_livreurs$$, 'un visiteur, non');
reset role;

-- ---------------------------------------------------------
select essai.titre('5. Un revendeur sans position n''est pas validé');
insert into public.clients (id, nom, tel, type_compte) values
  (:GROSSISTE::uuid, 'Grossiste sans position', '97555777', 'revendeur')
on conflict (id) do nothing;
update public.clients set revendeur_latitude = null, revendeur_longitude = null,
       revendeur_adresse = '' where id = :GROSSISTE::uuid;

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse(format($$select public.valider_revendeur(%L::uuid, true, '')$$, :GROSSISTE),
  'sans position : la validation est refusée');
reset role; select essai.personne();
select essai.egal((select revendeur_etat from public.clients where id = :GROSSISTE::uuid),
  'en_attente', 'la demande reste en attente');

-- Le revendeur active sa position depuis son compte.
select essai.devenir(:GROSSISTE::uuid); set role authenticated;
update public.clients set revendeur_latitude = 6.3561, revendeur_longitude = 2.4334
 where id = :GROSSISTE::uuid;
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse(format($$select public.valider_revendeur(%L::uuid, true, '')$$, :GROSSISTE),
  'une position sans adresse ne suffit pas');
reset role; select essai.personne();
select essai.devenir(:GROSSISTE::uuid); set role authenticated;
update public.clients set revendeur_adresse = 'Dantokpa, allée des tissus'
 where id = :GROSSISTE::uuid;
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal(public.valider_revendeur(:GROSSISTE::uuid, true, ''), 'validee',
  'position et adresse : le revendeur est validé');
reset role; select essai.personne();
