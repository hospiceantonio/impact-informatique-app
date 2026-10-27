-- =========================================================
-- « Faire livrer » : une commande prise sur WhatsApp (3.68.0)
--
-- Ce qu'on prouve :
--   1. seuls l'enseigne qui suit les commandes et le superadministrateur
--      font livrer — ni une boutique, ni un client, ni un visiteur ;
--   2. le devis dit, sans rien écrire, ce que la commande coûtera ;
--   3. un montant payé trop court est refusé AVANT d'écrire : aucun
--      numéro « BZ- » perdu ;
--   4. la commande naît payée en entier, « whatsapp », au nom de qui l'a
--      saisie, au journal des versements ; rien à encaisser à la porte ;
--      elle va au compte du client quand il en a un à ce numéro ;
--   5. une transaction ne paie qu'une commande ;
--   6. au kilomètre : la position est obligatoire, les frais suivent la
--      distance, et la course est proposée aux livreurs de BIZZOO ;
--   7. le compte obligatoire n'empêche pas l'équipe de la saisir.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set SUPER    '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set ADMBZ    '''d7d7d7d7-0000-0000-0000-000000000001'''
\set MODBZ    '''d7d7d7d7-0000-0000-0000-000000000002'''
\set FIDELE   '''d7d7d7d7-0000-0000-0000-000000000003'''
\set LIVBZ    '''d7d7d7d7-0000-0000-0000-000000000004'''

select essai.titre('Le décor : un administrateur et un modérateur de BIZZOO, un client fidèle, un livreur');
insert into auth.users (id, email) values
  (:ADMBZ::uuid, 'adm.wa@essai.bj'), (:MODBZ::uuid, 'mod.wa@essai.bj'),
  (:FIDELE::uuid, 'fidele.wa@essai.bj'), (:LIVBZ::uuid, 'liv.wa@essai.bj')
on conflict do nothing;
update public.profils p set role = v.r, actif = true, boutique_id = null, nom = v.n, peut_commandes = v.c
  from (values (:ADMBZ::uuid, 'administrateur', 'Awa', true),
               (:MODBZ::uuid, 'moderateur', 'Rémi', false),
               (:LIVBZ::uuid, 'livreur', 'Yao', true)) as v(i, r, n, c)
 where p.id = v.i;
update public.profils set vehicule = 'moto', tel = '0196700004' where id = :LIVBZ::uuid;
insert into public.positions_livreurs (profil_id, latitude, longitude, adresse)
values (:LIVBZ::uuid, 6.37, 2.42, 'Cotonou') on conflict (profil_id) do nothing;
insert into public.clients (id, nom, tel, indicatif, adresse)
values (:FIDELE::uuid, 'Fidèle', '0196700003', '229', 'Akpakpa')
on conflict (id) do update set tel = excluded.tel, indicatif = excluded.indicatif;
update public.paiement set livraison_latitude = null, livraison_longitude = null, taux_livreur = 80 where id = 1;
update public.boutiques set actif = true, ouvertures = null, mode_paiement = 'acompte', taux_acompte = 50,
       frais_livraison = 1000
 where id in ('bou_informatique', 'bou_essai_voisine');
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible) values
  ('prod_wa_a', 'bou_informatique', 'Casque', 12000, 'sc_hightech_accessoires', 10, true),
  ('prod_wa_b', 'bou_essai_voisine', 'Chargeur', 4000, 'sc_hightech_accessoires', 10, true)
on conflict (id) do update set stock = 10, disponible = true, masque = false, prix = excluded.prix;

-- Au nom d'un compte, avec le rôle des applications.
create function pg_temp.faire(qui uuid, art jsonb, cli jsonb, dest jsonb, trans text, montant bigint)
returns jsonb language plpgsql as $$
declare g jsonb;
begin
  perform essai.devenir(qui);
  set local role authenticated;
  g := public.faire_livrer(art, cli, dest, trans, montant, 'MTN');
  reset role;
  perform essai.personne();
  return g;
end $$;
create function pg_temp.devis(qui uuid, art jsonb, dest jsonb) returns jsonb language plpgsql as $$
declare g jsonb;
begin
  perform essai.devenir(qui);
  set local role authenticated;
  g := public.devis_faire_livrer(art, dest);
  reset role;
  perform essai.personne();
  return g;
end $$;

\set ART '''[{"produit_id":"prod_wa_a","quantite":1},{"produit_id":"prod_wa_b","quantite":2}]'''
\set CLI '''{"nom":"Koffi","tel":"0196700099","indicatif":"229","adresse":"Fidjrossè, près du marché"}'''

select essai.titre('1. Qui peut faire livrer');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse(format($$select public.faire_livrer(%L::jsonb, %L::jsonb, null, 'MP0001', 50000)$$, :ART, :CLI),
  'l''administrateur d''une boutique : refusé');
select essai.refuse(format($$select public.devis_faire_livrer(%L::jsonb, null)$$, :ART), 'ni son devis');
reset role; select essai.personne();
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.refuse(format($$select public.faire_livrer(%L::jsonb, %L::jsonb, null, 'MP0001', 50000)$$, :ART, :CLI),
  'un client : refusé');
reset role; select essai.personne();
select essai.devenir(:MODBZ::uuid); set role authenticated;
select essai.refuse(format($$select public.faire_livrer(%L::jsonb, %L::jsonb, null, 'MP0001', 50000)$$, :ART, :CLI),
  'un modérateur de BIZZOO sans le droit « commandes » : refusé');
reset role; select essai.personne();
set role anon;
select essai.refuse(format($$select public.faire_livrer(%L::jsonb, %L::jsonb, null, 'MP0001', 50000)$$, :ART, :CLI),
  'un visiteur : refusé');
reset role;

select essai.titre('2. Le devis, sans rien écrire');
select (select last_value from public.commandes_numero) as numero_avant \gset
select essai.egal((select (d ->> 'sous_total') || '/' || (d ->> 'frais_livraison') || '/' || (d ->> 'total')
                     from (select pg_temp.devis(:ADMBZ::uuid, :ART::jsonb, null) d) x),
  '20000/2000/22000', '12 000 + 2 × 4 000, et 1 000 de frais par boutique : 22 000');
select essai.egal((select last_value from public.commandes_numero), :numero_avant::bigint,
  'aucun numéro de commande consommé');

select essai.titre('3. Un montant trop court : refusé avant d''écrire');
select essai.refuse(format($$select pg_temp.faire(%L::uuid, %L::jsonb, %L::jsonb, null, 'MP-COURT-1', 21000)$$,
  :ADMBZ, :ART, :CLI), 'payé 21 000 pour 22 000 : refusé');
select essai.egal((select last_value from public.commandes_numero), :numero_avant::bigint,
  'et aucun numéro « BZ- » perdu');
select essai.refuse(format($$select pg_temp.faire(%L::uuid, %L::jsonb, %L::jsonb, null, 'MP', 22000)$$,
  :ADMBZ, :ART, :CLI), 'une référence de transaction trop courte : refusée');
select essai.refuse(format($$select pg_temp.faire(%L::uuid, %L::jsonb, '{"nom":"Koffi","tel":"0196700099"}'::jsonb, null, 'MP-SANS-ADR', 22000)$$,
  :ADMBZ, :ART), 'sans adresse de livraison : refusé');

select essai.titre('4. La commande WhatsApp : payée en entier, tracée');
select pg_temp.faire(:ADMBZ::uuid, :ART::jsonb, :CLI::jsonb, null, 'mp241027.1530.a12345', 22000) as w1 \gset
select essai.egal((select etat || '/' || origine || '/' || (saisie_par = :ADMBZ::uuid) || '/' || total || '/' || verse
                     from public.commandes where id = :'w1'::jsonb ->> 'id'),
  'payee/whatsapp/true/22000/22000', 'payée, « whatsapp », saisie par Awa, 22 000 versés');
select essai.egal((select transaction_id from public.commandes where id = :'w1'::jsonb ->> 'id'), 'MP241027.1530.A12345',
  'la référence de la transaction, en majuscules');
select essai.egal((select coalesce(sum(r.a_encaisser), 0)::int from public.restes_par_boutique(:'w1'::jsonb ->> 'id') r), 0,
  'rien à encaisser à la porte : le livreur ne prend rien chez le client');
select essai.egal((select confirme_par from public.commandes where id = :'w1'::jsonb ->> 'id'), 'Awa',
  'la commande porte le nom de qui l''a saisie');
select essai.egal((select fournisseur || '/' || reseau || '/' || verdict || '/' || recu
                     from public.versements where commande_id = :'w1'::jsonb ->> 'id'),
  'whatsapp/MTN/payee/22000', 'au journal des versements : « whatsapp », MTN, 22 000');
select essai.egal((select client_id is null from public.commandes where id = :'w1'::jsonb ->> 'id'), true,
  'pas de compte à ce numéro : une commande sans compte, comme une commande d''invité');
select essai.egal((select stock from public.produits where id = 'prod_wa_b'), 8, 'le stock est décompté (10 − 2)');
select essai.verifie((select count(*) > 0 from public.notifications
                       where commande_id = :'w1'::jsonb ->> 'id' and type = 'commande_payee'
                         and destinataire = :CHEF::uuid),
  'la boutique est prévenue, comme pour toute commande payée');
select essai.verifie((select count(*) > 0 from public.notifications
                       where commande_id = :'w1'::jsonb ->> 'id' and type = 'commande_payee'
                         and destinataire = :SUPER::uuid),
  'le superadministrateur aussi');

select essai.titre('5. Une transaction ne paie qu''une commande');
select essai.refuse(format($$select pg_temp.faire(%L::uuid, %L::jsonb, %L::jsonb, null, 'MP241027-1530-A12345', 22000)$$,
  :ADMBZ, :ART, :CLI), 'la même référence, autrement ponctuée : refusée');

select essai.titre('Le client qui a un compte la retrouve dans son application');
select pg_temp.faire(:SUPER::uuid, '[{"produit_id":"prod_wa_a","quantite":1}]'::jsonb,
  '{"nom":"Fidèle","tel":"01 96 70 00 03","indicatif":"229","adresse":"Akpakpa"}'::jsonb, null, 'MP-FIDELE-1', 15000) as w2 \gset
select essai.egal((select client_id = :FIDELE::uuid from public.commandes where id = :'w2'::jsonb ->> 'id'), true,
  'son numéro a un compte : la commande est la sienne');
select essai.egal((select verse::int from public.commandes where id = :'w2'::jsonb ->> 'id'), 15000,
  'payé plus que le total (13 000) : le versement réel est gardé');
select essai.verifie((select count(*) > 0 from public.notifications
                       where commande_id = :'w2'::jsonb ->> 'id' and destinataire = :FIDELE::uuid
                         and type = 'commande_payee'),
  'et il en est prévenu dans son application');

select essai.titre('6. Au kilomètre : la position, les frais, la course aux livreurs');
update public.paiement set livraison_latitude = 6.3654, livraison_longitude = 2.4183,
       moto_forfait = 1000, moto_prix_km = 100, livraison_rayon_km = 10, livraison_coef = 1.3 where id = 1;
select essai.egal((select (d ->> 'position_requise') from (select pg_temp.devis(:ADMBZ::uuid, :ART::jsonb, null) d) x),
  'true', 'sans position, le devis la réclame');
select essai.refuse(format($$select pg_temp.faire(%L::uuid, %L::jsonb, %L::jsonb, null, 'MP-KM-0', 50000)$$,
  :ADMBZ, :ART, :CLI), 'sans position : refusé');
create function pg_temp.message(requete text) returns text language plpgsql as $$
begin
  execute requete;
  return '(aucune erreur)';
exception when others then
  return sqlerrm;
end $$;
select essai.verifie(pg_temp.message(format($$select pg_temp.faire(%L::uuid, %L::jsonb, %L::jsonb, null, 'MP-KM-0', 50000)$$,
  :ADMBZ, :ART, :CLI)) like 'Indiquez la position du client%', 'et l''équipe lit quoi faire, pas « mettez à jour »');
select essai.egal((select (d ->> 'frais_livraison') || '/' || (d ->> 'total')
                     from (select pg_temp.devis(:ADMBZ::uuid, :ART::jsonb,
                             '{"latitude":6.458099,"longitude":2.4183}'::jsonb) d) x),
  '1400/21400', '13,4 km à moto : 1 400 de frais, 21 400 en tout');
select pg_temp.faire(:ADMBZ::uuid, :ART::jsonb, :CLI::jsonb, '{"latitude":6.458099,"longitude":2.4183}'::jsonb,
  'MP-KM-1', 21400) as w3 \gset
select essai.egal((select frais_livraison || '/' || (livraison ->> 'vehicule') || '/' || total
                     from public.commandes where id = :'w3'::jsonb ->> 'id'),
  '1400/moto/21400', 'les frais au kilomètre, figés sur la commande');
select essai.egal((select coalesce(sum(r.a_encaisser), 0)::int from public.restes_par_boutique(:'w3'::jsonb ->> 'id') r), 0,
  'toujours rien à encaisser à la porte');
select essai.verifie((select count(*) > 0 from public.notifications
                       where commande_id = :'w3'::jsonb ->> 'id' and type = 'course_proposee'
                         and destinataire = :LIVBZ::uuid and sonne),
  'la course sonne chez les livreurs de BIZZOO, comme d''habitude');

select essai.titre('7. Le compte obligatoire n''arrête pas l''équipe');
update public.reglages set compte_obligatoire = true where id = 1;
select pg_temp.faire(:ADMBZ::uuid, '[{"produit_id":"prod_wa_b","quantite":1}]'::jsonb, :CLI::jsonb,
  '{"latitude":6.413825,"longitude":2.4183}'::jsonb, 'MP-OBLIG-1', 5000) as w4 \gset
select essai.egal((select etat from public.commandes where id = :'w4'::jsonb ->> 'id'), 'payee',
  'compte exigé des clients : la commande WhatsApp passe quand même');
update public.reglages set compte_obligatoire = false where id = 1;

-- Le décor rendu.
update public.paiement set livraison_latitude = null, livraison_longitude = null where id = 1;
