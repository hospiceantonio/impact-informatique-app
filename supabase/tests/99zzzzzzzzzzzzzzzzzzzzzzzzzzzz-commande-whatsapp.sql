-- =========================================================
-- « Faire livrer » : une commande prise sur WhatsApp (3.68.0)
--
-- Ce qu'on prouve :
--   1. seuls l'enseigne qui suit les commandes et le superadministrateur
--      font livrer — ni une boutique, ni un client, ni un visiteur ;
--   2. le devis dit, sans rien écrire, ce que valent les articles ;
--   3. les FRAIS sont saisis par l'équipe (obligatoires, 0 permis) ; un
--      montant payé trop court est refusé AVANT d'écrire : aucun numéro
--      « BZ- » perdu ;
--   4. la commande naît payée en entier, « whatsapp », au nom de qui l'a
--      saisie, au journal des versements ; rien à encaisser à la porte ;
--      elle va au compte du client quand il en a un à ce numéro ;
--   5. une transaction ne paie qu'une commande ;
--   6. la position est facultative, même au kilomètre ; donnée, elle
--      guide le livreur ; le livreur touche 80 % des frais saisis ;
--   7. le compte obligatoire n'empêche pas l'équipe de la saisir ;
--   9. (3.70.0) où le livreur récupère la commande, saisi par l'équipe :
--      gardé sur la commande, lu dans sa fiche et dans ses alertes ;
--      facultatif pour la base (l'écran d'avant ne l'envoie pas).
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
\set ADM2     '''d7d7d7d7-0000-0000-0000-000000000005'''
\set MOD3     '''d7d7d7d7-0000-0000-0000-000000000006'''

select essai.titre('Le décor : un administrateur et un modérateur de BIZZOO, un client fidèle, un livreur');
insert into auth.users (id, email) values
  (:ADMBZ::uuid, 'adm.wa@essai.bj'), (:MODBZ::uuid, 'mod.wa@essai.bj'),
  (:FIDELE::uuid, 'fidele.wa@essai.bj'), (:LIVBZ::uuid, 'liv.wa@essai.bj'), (:ADM2::uuid, 'adm2.wa@essai.bj'),
  (:MOD3::uuid, 'mod3.wa@essai.bj')
on conflict do nothing;
-- Awa a reçu le droit « Faire livrer » ; Rémi et Bio ne l'ont pas — Bio
-- suit pourtant les commandes : ce droit-là ne donne pas l'autre.
update public.profils p set role = v.r, actif = true, boutique_id = null, nom = v.n, peut_commandes = v.c,
       peut_faire_livrer = v.f
  from (values (:ADMBZ::uuid, 'administrateur', 'Awa', true, true),
               (:MODBZ::uuid, 'moderateur', 'Rémi', true, false),
               (:ADM2::uuid, 'administrateur', 'Bio', true, false),
               (:LIVBZ::uuid, 'livreur', 'Yao', true, false)) as v(i, r, n, c, f)
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
create function pg_temp.faire(qui uuid, art jsonb, cli jsonb, dest jsonb, frais bigint, trans text, montant bigint)
returns jsonb language plpgsql as $$
declare g jsonb;
begin
  perform essai.devenir(qui);
  set local role authenticated;
  g := public.faire_livrer(art, cli, dest, frais, trans, montant, 'MTN');
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
\set CLI_R '''{"nom":"Koffi","tel":"0196700099","indicatif":"229","adresse":"Fidjrossè, près du marché","retrait":"  Alpha, Ganhi — demander Rémi\\nBêta : marché Dantokpa  "}'''

select essai.titre('1. Qui peut faire livrer');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse(format($$select public.faire_livrer(%L::jsonb, %L::jsonb, null, 1500, 'MP0001', 50000)$$, :ART, :CLI),
  'l''administrateur d''une boutique : refusé');
select essai.refuse(format($$select public.devis_faire_livrer(%L::jsonb, null)$$, :ART), 'ni son devis');
reset role; select essai.personne();
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.refuse(format($$select public.faire_livrer(%L::jsonb, %L::jsonb, null, 1500, 'MP0001', 50000)$$, :ART, :CLI),
  'un client : refusé');
reset role; select essai.personne();
select essai.devenir(:MODBZ::uuid); set role authenticated;
select essai.refuse(format($$select public.faire_livrer(%L::jsonb, %L::jsonb, null, 1500, 'MP0001', 50000)$$, :ART, :CLI),
  'un modérateur de BIZZOO sans le droit « Faire livrer » : refusé');
reset role; select essai.personne();
select essai.devenir(:ADM2::uuid); set role authenticated;
select essai.refuse(format($$select public.faire_livrer(%L::jsonb, %L::jsonb, null, 1500, 'MP0001', 50000)$$, :ART, :CLI),
  'un administrateur de BIZZOO qui suit les commandes, mais sans le droit : refusé');
select essai.verifie(not public.peut_faire_livrer(), 'et l''écran le sait : « peut_faire_livrer() » est faux');
-- Un modérateur qu'il crée : la règle de « profils » le laisse faire — et
-- le retoucher tant qu'il attend sa validation. C'est par là qu'on
-- glisserait le droit.
select essai.refuse(format($$insert into public.profils (id, email, role, actif, boutique_id, nom, peut_faire_livrer)
  values (%L::uuid, 'mod3.wa@essai.bj', 'moderateur', true, null, 'Ola', true)
  on conflict (id) do update set role = excluded.role, actif = excluded.actif, boutique_id = excluded.boutique_id,
    nom = excluded.nom, peut_faire_livrer = excluded.peut_faire_livrer$$, :MOD3),
  'il ne peut pas créer un modérateur avec ce droit');
insert into public.profils (id, email, role, actif, boutique_id, nom)
values (:MOD3::uuid, 'mod3.wa@essai.bj', 'moderateur', true, null, 'Ola')
on conflict (id) do update set role = excluded.role, actif = excluded.actif,
  boutique_id = excluded.boutique_id, nom = excluded.nom;
select essai.refuse(format($$update public.profils set peut_faire_livrer = true where id = %L::uuid$$, :MOD3),
  'ni le lui glisser ensuite');
update public.profils set peut_faire_livrer = true where id = :ADM2::uuid;
reset role; select essai.personne();
select essai.egal((select peut_faire_livrer from public.profils where id = :ADM2::uuid), false,
  'ni se le donner lui-même');
select essai.devenir(:ADMBZ::uuid); set role authenticated;
select essai.sans_effet(format($$update public.profils set peut_faire_livrer = true where id = %L::uuid$$, :MODBZ),
  'Awa, qui l''a, ne peut pas le transmettre non plus');
reset role; select essai.personne();
select essai.devenir(:SUPER::uuid); set role authenticated;
update public.profils set peut_faire_livrer = true where id = :MODBZ::uuid;
select essai.egal((select peut_faire_livrer from public.profils where id = :MODBZ::uuid), true,
  'le superadministrateur, lui, l''accorde');
update public.profils set peut_faire_livrer = false where id = :MODBZ::uuid;
reset role; select essai.personne();
set role anon;
select essai.refuse(format($$select public.faire_livrer(%L::jsonb, %L::jsonb, null, 1500, 'MP0001', 50000)$$, :ART, :CLI),
  'un visiteur : refusé');
reset role;

select essai.titre('2. Le devis, sans rien écrire');
select (select last_value from public.commandes_numero) as numero_avant \gset
select essai.egal((select (d ->> 'sous_total') || '/' || (d ->> 'vehicule')
                     from (select pg_temp.devis(:ADMBZ::uuid, :ART::jsonb, null) d) x),
  '20000/moto', 'les articles : 12 000 + 2 × 4 000 = 20 000, à moto');
select essai.egal((select last_value from public.commandes_numero), :numero_avant::bigint,
  'aucun numéro de commande consommé');

select essai.titre('3. Les frais saisis ; un montant trop court : refusé avant d''écrire');
select essai.refuse(format($$select pg_temp.faire(%L::uuid, %L::jsonb, %L::jsonb, null, null, 'MP-SANS-FRAIS', 21500)$$,
  :ADMBZ, :ART, :CLI), 'sans frais de livraison : refusé (0 s''il n''y en a pas)');
select essai.refuse(format($$select pg_temp.faire(%L::uuid, %L::jsonb, %L::jsonb, null, -100, 'MP-FRAIS-NEG', 21500)$$,
  :ADMBZ, :ART, :CLI), 'des frais négatifs : refusés');
select essai.refuse(format($$select pg_temp.faire(%L::uuid, %L::jsonb, %L::jsonb, null, 1500, 'MP-COURT-1', 21000)$$,
  :ADMBZ, :ART, :CLI), 'payé 21 000 pour 20 000 + 1 500 de frais : refusé');
select essai.egal((select last_value from public.commandes_numero), :numero_avant::bigint,
  'et aucun numéro « BZ- » perdu');
select essai.refuse(format($$select pg_temp.faire(%L::uuid, %L::jsonb, %L::jsonb, null, 1500, 'MP', 21500)$$,
  :ADMBZ, :ART, :CLI), 'une référence de transaction trop courte : refusée');
select essai.refuse(format($$select pg_temp.faire(%L::uuid, %L::jsonb, '{"nom":"Koffi","tel":"0196700099"}'::jsonb, null, 1500, 'MP-SANS-ADR', 21500)$$,
  :ADMBZ, :ART), 'sans adresse de livraison : refusé');

select essai.titre('4. La commande WhatsApp, sans position : payée en entier, tracée');
select pg_temp.faire(:ADMBZ::uuid, :ART::jsonb, :CLI_R::jsonb, null, 1500, 'mp241027.1530.a12345', 21500) as w1 \gset
select essai.egal((select etat || '/' || origine || '/' || (saisie_par = :ADMBZ::uuid) || '/' || total || '/' || verse
                     from public.commandes where id = :'w1'::jsonb ->> 'id'),
  'payee/whatsapp/true/21500/21500', 'payée, « whatsapp », saisie par Awa, 21 500 versés');
select essai.egal((select frais_livraison || '/' || (livraison ->> 'saisie') || '/' || (livraison ->> 'vehicule') || '/' ||
                          coalesce(livraison ->> 'destination', 'sans position')
                     from public.commandes where id = :'w1'::jsonb ->> 'id'),
  '1500/true/moto/sans position', 'les frais saisis (1 500), à moto, sans position');
select essai.egal((select transaction_id from public.commandes where id = :'w1'::jsonb ->> 'id'), 'MP241027.1530.A12345',
  'la référence de la transaction, en majuscules');
select essai.egal((select coalesce(sum(r.a_encaisser), 0)::int from public.restes_par_boutique(:'w1'::jsonb ->> 'id') r), 0,
  'rien à encaisser à la porte : le livreur ne prend rien chez le client');
select essai.egal((select confirme_par from public.commandes where id = :'w1'::jsonb ->> 'id'), 'Awa',
  'la commande porte le nom de qui l''a saisie');
select essai.egal((select fournisseur || '/' || reseau || '/' || verdict || '/' || recu
                     from public.versements where commande_id = :'w1'::jsonb ->> 'id'),
  'whatsapp/MTN/payee/21500', 'au journal des versements : « whatsapp », MTN, 21 500');
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
select essai.verifie((select count(*) > 0 from public.notifications
                       where commande_id = :'w1'::jsonb ->> 'id' and type = 'course_proposee'
                         and destinataire = :LIVBZ::uuid and sonne),
  'la course sonne chez les livreurs de BIZZOO, comme d''habitude');
-- Yao la prend et la remet : 80 % des frais saisis.
select set_config('bizzoo.livraison', 'oui', false) as r \gset
update public.commande_lignes set livreur_id = :LIVBZ::uuid, etat = 'en_livraison' where commande_id = :'w1'::jsonb ->> 'id';
select essai.verifie((select count(*) > 0 from public.notifications
                       where commande_id = :'w1'::jsonb ->> 'id' and type = 'course_confiee'
                         and destinataire = :LIVBZ::uuid
                         and corps like '%Où récupérer : Alpha, Ganhi — demander Rémi' || E'\n' || 'Bêta : marché Dantokpa' || E'\n' || '%'),
  '(3.70.0) confiée à Yao : son alerte dit où récupérer la commande');
update public.commande_lignes set etat = 'remise' where commande_id = :'w1'::jsonb ->> 'id';
select set_config('bizzoo.livraison', '', false) as r \gset
select essai.egal((select frais || '/' || montant from public.gains_livreurs
                    where commande_id = :'w1'::jsonb ->> 'id' and livreur_id = :LIVBZ::uuid),
  '1500/1200', 'remise : Yao touche 80 % des 1 500 saisis, 1 200');

select essai.titre('5. Une transaction ne paie qu''une commande');
select essai.refuse(format($$select pg_temp.faire(%L::uuid, %L::jsonb, %L::jsonb, null, 1500, 'MP241027-1530-A12345', 21500)$$,
  :ADMBZ, :ART, :CLI), 'la même référence, autrement ponctuée : refusée');

select essai.titre('Le client qui a un compte la retrouve dans son application');
select pg_temp.faire(:SUPER::uuid, '[{"produit_id":"prod_wa_a","quantite":1}]'::jsonb,
  '{"nom":"Fidèle","tel":"01 96 70 00 03","indicatif":"229","adresse":"Akpakpa"}'::jsonb, null, 0, 'MP-FIDELE-1', 15000) as w2 \gset
select essai.egal((select client_id = :FIDELE::uuid from public.commandes where id = :'w2'::jsonb ->> 'id'), true,
  'son numéro a un compte : la commande est la sienne');
select essai.egal((select verse || '/' || total || '/' || frais_livraison from public.commandes where id = :'w2'::jsonb ->> 'id'),
  '15000/12000/0', 'livraison offerte (0) ; payé plus que le total : le versement réel est gardé');
select essai.verifie((select count(*) > 0 from public.notifications
                       where commande_id = :'w2'::jsonb ->> 'id' and destinataire = :FIDELE::uuid
                         and type = 'commande_payee'),
  'et il en est prévenu dans son application');

select essai.titre('6. La position, facultative même au kilomètre : elle guide le livreur');
update public.paiement set livraison_latitude = 6.3654, livraison_longitude = 2.4183,
       moto_forfait = 1000, moto_prix_km = 100, livraison_rayon_km = 10, livraison_coef = 1.3 where id = 1;
select pg_temp.faire(:ADMBZ::uuid, '[{"produit_id":"prod_wa_b","quantite":1}]'::jsonb, :CLI::jsonb, null, 2000,
  'MP-KM-0', 6000) as w3 \gset
select essai.egal((select frais_livraison || '/' || total from public.commandes where id = :'w3'::jsonb ->> 'id'),
  '2000/6000', 'livraison au kilomètre en service : sans position, ce sont les frais saisis (2 000), pas la distance');
select pg_temp.faire(:ADMBZ::uuid, '[{"produit_id":"prod_wa_b","quantite":1}]'::jsonb, :CLI::jsonb,
  '{"latitude":6.458099,"longitude":2.4183}'::jsonb, 2500, 'MP-KM-1', 6500) as w4 \gset
select essai.egal((select frais_livraison || '/' || (livraison -> 'destination' ->> 'latitude')
                     from public.commandes where id = :'w4'::jsonb ->> 'id'),
  '2500/6.458099', 'avec position : toujours les frais saisis (2 500), et le point du client gardé');
select essai.egal((public.fiche_course(:'w4'::jsonb ->> 'id', 'bou_essai_voisine') -> 'livraison' ->> 'latitude'), '6.458099',
  'la fiche du livreur montre où livrer');
select essai.egal((public.fiche_course(:'w4'::jsonb ->> 'id', 'bou_essai_voisine') ->> 'a_encaisser')::int, 0,
  'et rien à récupérer');

select essai.titre('7. Le compte obligatoire n''arrête pas l''équipe');
update public.reglages set compte_obligatoire = true where id = 1;
select pg_temp.faire(:ADMBZ::uuid, '[{"produit_id":"prod_wa_b","quantite":1}]'::jsonb, :CLI::jsonb,
  null, 1000, 'MP-OBLIG-1', 5000) as w5 \gset
select essai.egal((select etat from public.commandes where id = :'w5'::jsonb ->> 'id'), 'payee',
  'compte exigé des clients : la commande WhatsApp passe quand même');
update public.reglages set compte_obligatoire = false where id = 1;

select essai.titre('8. La colonne « Source » du suivi des commandes');
select essai.egal((select x ->> 'source' from public.rh_suivi_donnees(null, null, :'w1'::jsonb ->> 'id') x),
  'Par whatsapp', 'une commande prise sur WhatsApp : « Par whatsapp »');
select essai.egal((select x ->> 'source' from public.rh_suivi_donnees(null, null,
                     (select id from public.commandes where origine = 'application' order by cree_le desc limit 1)) x),
  'Depuis APP', 'une commande passée dans l''application : « Depuis APP »');

select essai.titre('9. Où le livreur récupère la commande (3.70.0)');
select essai.egal((select lieu_retrait from public.commandes where id = :'w1'::jsonb ->> 'id'),
  'Alpha, Ganhi — demander Rémi' || E'\n' || 'Bêta : marché Dantokpa',
  'gardé sur la commande, sans les espaces autour, lignes comprises');
select essai.egal((public.fiche_course(:'w1'::jsonb ->> 'id', 'bou_informatique') ->> 'lieu_retrait'),
  'Alpha, Ganhi — demander Rémi' || E'\n' || 'Bêta : marché Dantokpa', 'sur la fiche de la course');
select essai.egal((public.fiche_demande(:'w1'::jsonb ->> 'id') ->> 'lieu_retrait'),
  'Alpha, Ganhi — demander Rémi' || E'\n' || 'Bêta : marché Dantokpa', 'et sur la fiche de la demande, une seule fois');
-- Sans distance (frais saisis), l'alerte proposée sortait VIDE avant la
-- 3.70.0 : la ligne « Véhicule » valait NULL, et tout le texte avec.
select essai.verifie((select count(*) > 0 from public.notifications
                       where commande_id = :'w1'::jsonb ->> 'id' and type = 'course_proposee'
                         and destinataire = :LIVBZ::uuid
                         and corps like '%Récupérer : %' || E'\n' || 'Où récupérer : Alpha, Ganhi — demander Rémi%'
                         and corps like '%Véhicule : moto' || E'\n' || 'Frais de livraison : %'),
  'la course proposée aux livreurs le dit, après la boutique — et l''alerte n''est plus vide');
select essai.egal((select lieu_retrait from public.commandes where id = :'w3'::jsonb ->> 'id'), '',
  'non saisi (l''écran d''avant la 3.70.0) : la commande passe, sans lieu');
select essai.verifie(public.texte_demande(public.fiche_demande(:'w3'::jsonb ->> 'id')) not like '%Où récupérer%',
  'et l''alerte n''a pas de ligne vide « Où récupérer »');
select essai.refuse($$select pg_temp.faire('d7d7d7d7-0000-0000-0000-000000000001'::uuid,
  '[{"produit_id":"prod_wa_b","quantite":1}]'::jsonb,
  jsonb_build_object('nom', 'Koffi', 'tel', '0196700099', 'adresse', 'Fidjrossè', 'retrait', repeat('x', 501)),
  null, 1000, 'MP-LONG-1', 5000)$$,
  'plus de 500 caractères : refusé, plutôt que coupé en silence');
select essai.egal((:'w1'::jsonb ->> 'lieu_retrait'), 'Alpha, Ganhi — demander Rémi' || E'\n' || 'Bêta : marché Dantokpa',
  'la réponse rend le lieu gardé : l''écran sait que la base est à jour');

-- Le décor rendu.
update public.paiement set livraison_latitude = null, livraison_longitude = null where id = 1;
