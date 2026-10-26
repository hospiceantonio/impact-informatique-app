-- =========================================================
-- Le livreur touche sa part de TOUTES ses courses (3.66.0)
--
-- Ce qu'on prouve :
--   1. à l'ancien tarif (frais par boutique), deux livreurs sur une
--      commande : chacun touche 80 % des frais de SA boutique, dès qu'il
--      a remis sa part — sans attendre l'autre ;
--   2. un livreur de BIZZOO qui porte les deux boutiques touche les deux
--      frais, en une ligne ;
--   3. une commande plus ancienne encore (sans frais par boutique) : au
--      prorata de ce que chacun porte ;
--   4. le gain annoncé et le « à venir » disent la même chose ;
--   5. le rattrapage crédite sans prévenir course par course ; rejoué, il
--      ne crédite pas deux fois.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set LA       '''c9c9c9c9-0000-0000-0000-000000000001'''
\set LB       '''c9c9c9c9-0000-0000-0000-000000000002'''
\set BZ       '''c9c9c9c9-0000-0000-0000-000000000003'''

select essai.titre('Le décor : deux boutiques à 1 000 F de frais chacune, trois livreurs');
insert into auth.users (id, email) values
  (:LA::uuid, 'la.gains@essai.bj'), (:LB::uuid, 'lb.gains@essai.bj'), (:BZ::uuid, 'bz.gains@essai.bj')
on conflict do nothing;
update public.profils p set role = 'livreur', actif = true, boutique_id = v.b, nom = v.n, tel = v.t
  from (values (:LA::uuid, 'bou_informatique', 'Koffi', '0196600001'),
               (:LB::uuid, 'bou_essai_voisine', 'Bella', '0196600002'),
               (:BZ::uuid, null, 'Sèna', '0196600003')) as v(i, b, n, t)
 where p.id = v.i;
update public.paiement set livraison_latitude = null, livraison_longitude = null, taux_livreur = 80 where id = 1;
update public.boutiques set actif = true, ouvertures = null, mode_paiement = 'acompte', taux_acompte = 50,
       frais_livraison = 1000
 where id in ('bou_informatique', 'bou_essai_voisine');
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible) values
  ('prod_gain_a', 'bou_informatique', 'Clavier', 9000, 'sc_hightech_accessoires', 50, true),
  ('prod_gain_b', 'bou_essai_voisine', 'Ampoule', 6000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true;

create function pg_temp.commander() returns text language plpgsql as $$
declare g jsonb;
begin
  perform essai.devenir('ffffffff-2222-2222-2222-222222222222'::uuid);
  set local role authenticated;
  g := public.creer_commande('{"nom":"Rosine","tel":"97666077","adresse":"Godomey"}'::jsonb,
    '[{"produit_id":"prod_gain_a","quantite":1},{"produit_id":"prod_gain_b","quantite":1}]'::jsonb,
    '', true, true, null);
  reset role;
  perform essai.personne();
  perform public.marquer_payee(g ->> 'id', 'TRX-GAIN-' || (g ->> 'id'), (g ->> 'acompte')::int, 'feexpay');
  return g ->> 'id';
end $$;
-- Confier une boutique de la commande à un livreur, puis la remettre.
-- (« bizzoo.livraison » : le passage que prennent les fonctions des courses.)
create function pg_temp.confier(cible text, bou text, qui uuid) returns void language sql as $$
  select set_config('bizzoo.livraison', 'oui', true);
  update public.commande_lignes set livreur_id = qui, etat = 'en_livraison'
   where commande_id = cible and boutique_id = bou;
  select set_config('bizzoo.livraison', '', true);
$$;
create function pg_temp.remettre(cible text, bou text) returns void language sql as $$
  select set_config('bizzoo.livraison', 'oui', true);
  update public.commande_lignes set etat = 'remise' where commande_id = cible and boutique_id = bou;
  select set_config('bizzoo.livraison', '', true);
$$;
-- Ce que dit l'application au livreur connecté.
create function pg_temp.vu_par(qui uuid, cible text) returns text language plpgsql as $$
declare r text;
begin
  perform essai.devenir(qui);
  -- « gain_livreur » ne s'appelle que par « fiche_course » : lue à son nom,
  -- sans le rôle des applications ; le solde, avec.
  r := coalesce(public.gain_livreur(cible)::text, '-');
  set local role authenticated;
  r := r || '/' || (public.solde_livreur() ->> 'a_venir');
  reset role;
  perform essai.personne();
  return r;
end $$;

select pg_temp.commander() as c1 \gset
select essai.egal((select frais_livraison::int from public.commandes where id = :'c1'), 2000,
  'l''ancien tarif : 1 000 F par boutique, 2 000 F');

select essai.titre('1. Deux livreurs, deux boutiques : chacun sa part');
select pg_temp.confier(:'c1', 'bou_informatique', :LA::uuid);
select pg_temp.confier(:'c1', 'bou_essai_voisine', :LB::uuid);
select essai.egal(pg_temp.vu_par(:LA::uuid, :'c1'), '800/800', 'Koffi voit 800 F annoncés, 800 F à venir');
select essai.egal(pg_temp.vu_par(:LB::uuid, :'c1'), '800/800', 'Bella aussi');
select pg_temp.remettre(:'c1', 'bou_informatique');
select essai.egal((select string_agg(livreur_id::text || '=' || montant, ',') from public.gains_livreurs
                    where commande_id = :'c1'), :LA || '=800',
  'Koffi a remis sa part : 800 F crédités, sans attendre Bella');
select essai.egal(pg_temp.vu_par(:LA::uuid, :'c1'), '800/0', 'pour lui : 800 F, plus rien à venir');
select pg_temp.remettre(:'c1', 'bou_essai_voisine');
select essai.egal((select montant::int from public.gains_livreurs where commande_id = :'c1' and livreur_id = :LB::uuid), 800,
  'Bella remet la sienne : 800 F');
select essai.egal(public.crediter_livreur(:'c1'), 1600::bigint, 'la commande a rapporté 1 600 F à ses livreurs');
select essai.egal((select count(*)::int from public.gains_livreurs where commande_id = :'c1'), 2,
  'rejoué : toujours deux lignes');
select essai.egal((select count(*)::int from public.notifications
                    where type = 'gain_livraison' and commande_id = :'c1'
                      and destinataire in (:LA::uuid, :LB::uuid)), 2, 'chacun en est prévenu, une fois');

select essai.titre('2. Un livreur de BIZZOO porte les deux boutiques');
select pg_temp.commander() as c2 \gset
select pg_temp.confier(:'c2', 'bou_informatique', :BZ::uuid);
select pg_temp.confier(:'c2', 'bou_essai_voisine', :BZ::uuid);
select essai.egal(pg_temp.vu_par(:BZ::uuid, :'c2'), '1600/1600', 'Sèna voit 1 600 F');
select pg_temp.remettre(:'c2', 'bou_informatique');
select essai.egal((select count(*)::int from public.gains_livreurs where commande_id = :'c2'), 0,
  'une boutique remise sur deux : pas encore crédité');
select pg_temp.remettre(:'c2', 'bou_essai_voisine');
select essai.egal((select frais || '/' || montant from public.gains_livreurs where commande_id = :'c2'), '2000/1600',
  'tout remis : 1 600 F, en une ligne');

select essai.titre('3. Plus ancienne : au prorata de ce que chacun porte');
select pg_temp.commander() as c3 \gset
select set_config('bizzoo.interne', 'oui', false) as r \gset
update public.commandes set parts = null where id = :'c3';
select set_config('bizzoo.interne', '', false) as r \gset
select pg_temp.confier(:'c3', 'bou_informatique', :LA::uuid);
select pg_temp.confier(:'c3', 'bou_essai_voisine', :LB::uuid);
select pg_temp.remettre(:'c3', 'bou_informatique');
select pg_temp.remettre(:'c3', 'bou_essai_voisine');
select essai.egal((select string_agg(frais || '>' || montant, ',' order by montant desc) from public.gains_livreurs
                    where commande_id = :'c3'), '1200>960,800>640',
  '9 000 F et 6 000 F d''articles : 1 200 F et 800 F de frais, 960 F et 640 F');

select essai.titre('4. Personne sur la course, ou une part annulée');
select pg_temp.commander() as c4 \gset
select essai.egal(pg_temp.vu_par(:BZ::uuid, :'c4'), '1600/0',
  'pas encore prise : celui qui la prendra la portera entière (1 600 F annoncés)');
select set_config('bizzoo.livraison', 'oui', false) as r \gset
update public.commande_lignes set etat = 'annulee' where commande_id = :'c4' and boutique_id = 'bou_essai_voisine';
select set_config('bizzoo.livraison', '', false) as r \gset
select pg_temp.confier(:'c4', 'bou_informatique', :LA::uuid);
select pg_temp.remettre(:'c4', 'bou_informatique');
select essai.egal((select montant::int from public.gains_livreurs where commande_id = :'c4'), 800,
  'la voisine annulée : Koffi touche sa seule boutique');

-- Un compte livreur supprimé depuis : on le saute, sans priver l'autre.
select pg_temp.commander() as c5 \gset
select pg_temp.confier(:'c5', 'bou_informatique', :LA::uuid);
insert into auth.users (id, email) values ('c9c9c9c9-0000-0000-0000-0000000000ff', 'parti.gains@essai.bj')
on conflict do nothing;
update public.profils set role = 'livreur', actif = true, boutique_id = 'bou_essai_voisine'
 where id = 'c9c9c9c9-0000-0000-0000-0000000000ff';
select pg_temp.confier(:'c5', 'bou_essai_voisine', 'c9c9c9c9-0000-0000-0000-0000000000ff'::uuid);
delete from auth.users where id = 'c9c9c9c9-0000-0000-0000-0000000000ff';
select pg_temp.remettre(:'c5', 'bou_essai_voisine');
select pg_temp.remettre(:'c5', 'bou_informatique');
select essai.egal((select string_agg(montant::text, ',') from public.gains_livreurs where commande_id = :'c5'), '800',
  'l''autre livreur n''existe plus : Koffi touche quand même ses 800 F');

select essai.titre('5. Le rattrapage : crédite sans prévenir course par course');
delete from public.gains_livreurs where commande_id = :'c2';
delete from public.notifications where commande_id = :'c2' and type = 'gain_livraison';
select set_config('bizzoo.rattrapage', 'oui', false) as r \gset
select essai.egal(public.crediter_livreur(:'c2'), 1600::bigint, 'la course de Sèna est créditée de nouveau');
select set_config('bizzoo.rattrapage', '', false) as r \gset
select essai.egal((select count(*)::int from public.notifications where commande_id = :'c2' and type = 'gain_livraison'), 0,
  'sans notification par course');
select essai.egal(public.crediter_livreur(:'c2'), 1600::bigint, 'rejoué…');
select essai.egal((select count(*)::int from public.gains_livreurs where commande_id = :'c2'), 1,
  '… jamais deux fois');
select essai.devenir(:BZ::uuid); set role authenticated;
select essai.egal((public.solde_livreur() ->> 'gagne')::int, 1600, 'son solde : 1 600 F gagnés');
select essai.refuse(format($$select public.part_frais_livreur(%L, %L::uuid)$$, :'c2', :LA),
  'un livreur ne calcule pas la part d''un autre');
reset role; select essai.personne();

select essai.titre('6. Une course prise sonne aussi chez BIZZOO (administrateurs et superadministrateurs)');
-- (« bizzoo.prise » : le passage de « Commande reçue », qui prend toute la commande d'un coup.)
create function pg_temp.recue(cible text, bou text, toute boolean) returns void language plpgsql as $$
begin
  perform set_config('bizzoo.livraison', 'oui', true);
  if toute then perform set_config('bizzoo.prise', 'oui', true); end if;
  update public.commande_lignes set recu_le = now()
   where commande_id = cible and (toute or boutique_id = bou);
  perform set_config('bizzoo.prise', '', true);
  perform set_config('bizzoo.livraison', '', true);
end $$;
select essai.verifie(cardinality(public.les_superadmins()) > 0, 'le décor a des superadministrateurs');
select pg_temp.commander() as c6 \gset
select pg_temp.confier(:'c6', 'bou_informatique', :BZ::uuid);
select pg_temp.confier(:'c6', 'bou_essai_voisine', :BZ::uuid);
select pg_temp.recue(:'c6', null, true);
select essai.egal((select count(*)::int from public.notifications n
                    where n.commande_id = :'c6' and n.type = 'course_acceptee' and n.sonne
                      and n.destinataire = any(public.les_superadmins() || public.enseigne_des_commandes())),
  cardinality(array(select distinct u from unnest(public.les_superadmins() || public.enseigne_des_commandes()) u)),
  'Sèna prend toute la commande : chaque superadministrateur et administrateur BIZZOO est sonné, UNE fois');
select essai.verifie((select bool_and(n.titre like 'Course prise par Sèna%') from public.notifications n
                       where n.commande_id = :'c6' and n.type = 'course_acceptee'
                         and n.destinataire = any(public.les_superadmins())),
  '« Course prise par Sèna »');
select pg_temp.commander() as c7 \gset
select pg_temp.confier(:'c7', 'bou_informatique', :LA::uuid);
select pg_temp.recue(:'c7', 'bou_informatique', false);
select essai.egal((select count(*)::int from public.notifications n
                    where n.commande_id = :'c7' and n.type = 'course_acceptee' and n.sonne
                      and n.destinataire = any(public.les_superadmins())),
  cardinality(public.les_superadmins()), 'Koffi accepte la course de sa boutique : les superadministrateurs l''entendent');
select essai.egal((select count(*)::int from public.notifications n
                    where n.commande_id = :'c7' and n.type = 'course_acceptee' and n.sonne
                      and n.destinataire = any(public.equipe_de('bou_informatique'))),
  cardinality(public.equipe_de('bou_informatique')), 'et la boutique, comme avant');
