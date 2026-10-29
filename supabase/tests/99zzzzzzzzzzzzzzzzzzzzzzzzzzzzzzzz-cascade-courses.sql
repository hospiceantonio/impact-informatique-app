-- =========================================================
-- La course au livreur le plus proche, puis à tous (3.70.0)
--
-- Ce qu'on prouve :
--   1. au paiement, seul le livreur le plus proche est alerté (et sonne) ;
--      les positions récentes passent avant les vieilles ; un livreur en
--      course n'est pas dans le classement ;
--   2. lui seul voit la course et peut la prendre ;
--   3. 30 secondes plus tard (avancer_cascades), le deuxième, puis le
--      troisième ; ceux d'avant la gardent ;
--   4. aucun des trois : elle part à TOUS les livreurs de BIZZOO ;
--   5. prise : la cascade s'arrête, les alertés apprennent « Déjà pris » ;
--   6. prise à temps par le premier : le deuxième n'est jamais dérangé ;
--   7. annulée par son livreur : la cascade repart du plus proche, sans lui ;
--   8. cascade éteinte, ou sans son horloge (pg_cron) : à tous d'un coup ;
--   9. la boutique reprend la course à son livreur : elle repart en cascade ;
--  10. la position du livreur libre se met à jour (signaler_ma_position) ;
--  11. « disponible » : application fermée, le service Android l'envoie
--      (position_livreur, par le jeton de suivi) ; pas disponible : il
--      s'arrête, et le livreur n'est plus parmi les plus proches.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set L1 '''cacacaca-0000-0000-0000-000000000001'''
\set L2 '''cacacaca-0000-0000-0000-000000000002'''
\set L3 '''cacacaca-0000-0000-0000-000000000003'''
\set L4 '''cacacaca-0000-0000-0000-000000000004'''
\set L5 '''cacacaca-0000-0000-0000-000000000005'''

select essai.titre('Le décor : une boutique à Parakou, cinq livreurs de BIZZOO autour');
-- Loin de Cotonou, où sont les livreurs des autres essais : les nôtres
-- sont les plus proches.
insert into public.boutiques (id, nom, secteur, actif, ordre, latitude, longitude, categorie_id)
select 'bou_cascade', 'Cascade', b.secteur, true, 50, 9.3370, 2.6300, b.categorie_id
  from public.boutiques b where b.id = 'bou_informatique'
on conflict (id) do update set latitude = 9.3370, longitude = 2.6300, actif = true, ouvertures = null;
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_cascade', 'bou_cascade', 'Ventilateur', 8000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true, masque = false;
insert into auth.users (id, email) values
  (:L1::uuid, 'l1.cascade@essai.bj'), (:L2::uuid, 'l2.cascade@essai.bj'), (:L3::uuid, 'l3.cascade@essai.bj'),
  (:L4::uuid, 'l4.cascade@essai.bj'), (:L5::uuid, 'l5.cascade@essai.bj')
on conflict do nothing;
update public.profils p set role = 'livreur', actif = true, boutique_id = null, nom = v.n, vehicule = 'moto'
  from (values (:L1::uuid, 'Un'), (:L2::uuid, 'Deux'), (:L3::uuid, 'Trois'),
               (:L4::uuid, 'Quatre'), (:L5::uuid, 'Vieux')) as v(i, n)
 where p.id = v.i;
-- Un à 0,5 km, Deux à 1 km, Trois à 2 km, Quatre à 5 km ; Vieux est à
-- 100 m, mais sa position date d'hier.
insert into public.positions_livreurs (profil_id, latitude, longitude, adresse, enregistre_le) values
  (:L1::uuid, 9.3415, 2.6300, 'Parakou', now()),
  (:L2::uuid, 9.3460, 2.6300, 'Parakou', now()),
  (:L3::uuid, 9.3550, 2.6300, 'Parakou', now()),
  (:L4::uuid, 9.3820, 2.6300, 'Parakou', now()),
  (:L5::uuid, 9.3379, 2.6300, 'Parakou', now() - interval '1 day')
on conflict (profil_id) do update
  set latitude = excluded.latitude, longitude = excluded.longitude, enregistre_le = excluded.enregistre_le;
update public.cascade_reglage set actif = true, delai_s = 30, rangs = 3, fraicheur_min = 60 where id = 1;
-- L'horloge : la tâche pg_cron « courses-cascade ». Le PostgreSQL d'essai
-- n'a pas pg_cron : on en pose le seul registre que la base consulte.
create schema if not exists cron;
create table if not exists cron.job (jobid bigserial primary key, jobname text, active boolean not null default true);
insert into cron.job (jobname) select 'courses-cascade'
 where not exists (select 1 from cron.job where jobname = 'courses-cascade');

-- Une commande payée, au nom du client d'essai.
create function pg_temp.commande_payee(trx text) returns text language plpgsql as $$
declare v_id text;
begin
  perform essai.devenir('ffffffff-2222-2222-2222-222222222222'::uuid);
  set local role authenticated;
  v_id := public.creer_commande('{"nom":"Afi","tel":"97666011","adresse":"Parakou, Banikanni"}'::jsonb,
    '[{"produit_id":"prod_cascade","quantite":1}]'::jsonb, '', true, true) ->> 'id';
  reset role;
  perform essai.personne();
  perform public.marquer_payee(v_id, trx,
    (select coalesce(c.acompte, c.total)::int from public.commandes c where c.id = v_id), 'feexpay');
  return v_id;
end $$;
-- Ce qu'un livreur voit, et ce qu'il peut prendre.
create function pg_temp.voit(qui uuid, cmd text) returns boolean language plpgsql as $$
declare n int;
begin
  perform essai.devenir(qui);
  set local role authenticated;
  select count(*) into n from public.courses_proposees() x where x.commande_id = cmd;
  reset role;
  perform essai.personne();
  return n > 0;
end $$;
create function pg_temp.prend(qui uuid, cmd text) returns int language plpgsql as $$
declare n int;
begin
  perform essai.devenir(qui);
  set local role authenticated;
  n := public.prendre_course(cmd);
  reset role;
  perform essai.personne();
  return n;
end $$;
create function pg_temp.alerte(qui uuid, cmd text) returns int language sql as $$
  select count(*)::int from public.notifications n
   where n.destinataire = qui and n.commande_id = cmd and n.type = 'course_proposee' and n.sonne;
$$;
-- « 30 secondes plus tard ».
create function pg_temp.trente_secondes(cmd text) returns int language plpgsql as $$
begin
  update public.courses_cascade set prochaine = now() - interval '1 second'
   where commande_id = cmd and prochaine is not null;
  return public.avancer_cascades();
end $$;

select pg_temp.commande_payee('TRX-CASCADE-1') as c1 \gset

select essai.titre('1. Au paiement : le plus proche, seul');
select essai.egal((select ordre from public.courses_cascade where commande_id = :'c1'),
  array[:L1::uuid, :L2::uuid, :L3::uuid], 'l''ordre : Un (0,5 km), Deux (1 km), Trois (2 km) — Vieux, trop ancien, après');
select essai.egal(pg_temp.alerte(:L1::uuid, :'c1'), 1, 'Un est alerté, et ça sonne');
select essai.verifie((select corps like 'Vous êtes parmi les plus proches%30 secondes%'
                        from public.notifications where destinataire = :L1::uuid and commande_id = :'c1'
                         and type = 'course_proposee'),
  'son alerte lui dit qu''il a 30 secondes');
select essai.egal(pg_temp.alerte(:L2::uuid, :'c1') + pg_temp.alerte(:L3::uuid, :'c1')
                  + pg_temp.alerte(:L4::uuid, :'c1') + pg_temp.alerte(:L5::uuid, :'c1'), 0,
  'personne d''autre');

select essai.titre('2. Lui seul la voit et peut la prendre');
select essai.verifie(pg_temp.voit(:L1::uuid, :'c1'), 'Un la voit dans ses demandes');
select essai.verifie(not pg_temp.voit(:L2::uuid, :'c1'), 'Deux ne la voit pas encore');
select essai.refuse(format($$select pg_temp.prend(%L::uuid, %L)$$, :L2, :'c1'), 'ni ne la prend');

select essai.titre('3. Trente secondes : le deuxième, puis le troisième');
select essai.egal(pg_temp.trente_secondes(:'c1'), 1, 'la tâche des 5 secondes fait avancer la cascade');
select essai.egal(pg_temp.alerte(:L2::uuid, :'c1'), 1, 'Deux est alerté');
select essai.verifie(pg_temp.voit(:L1::uuid, :'c1') and pg_temp.voit(:L2::uuid, :'c1'),
  'Un la voit toujours : le premier qui touche « Commande reçue » la prend');
select essai.egal(pg_temp.alerte(:L3::uuid, :'c1'), 0, 'Trois pas encore');
select essai.egal(public.avancer_cascades(), 0, 'avant les 30 secondes, rien ne bouge');
select pg_temp.trente_secondes(:'c1') as t \gset
select essai.egal(pg_temp.alerte(:L3::uuid, :'c1'), 1, 'trente secondes encore : Trois');
select essai.egal(pg_temp.alerte(:L4::uuid, :'c1'), 0, 'Quatre pas encore');

select essai.titre('4. Aucun des trois : à tous les livreurs de BIZZOO');
select pg_temp.trente_secondes(:'c1') as t \gset
select essai.egal((select tous::text || '/' || coalesce(prochaine::text, 'fin') from public.courses_cascade
                    where commande_id = :'c1'), 'true/fin', 'la cascade est au bout');
select essai.egal(pg_temp.alerte(:L4::uuid, :'c1') + pg_temp.alerte(:L5::uuid, :'c1'), 2,
  'Quatre et Vieux sonnent');
select essai.egal(pg_temp.alerte(:L1::uuid, :'c1'), 1, 'Un n''est pas sonné une seconde fois');
select essai.verifie((select count(*) > 5 from public.notifications
                       where commande_id = :'c1' and type = 'course_proposee'),
  'et les livreurs de BIZZOO des autres essais aussi');

select essai.titre('5. Prise : la cascade s''arrête');
select essai.egal(pg_temp.prend(:L4::uuid, :'c1'), 1, 'Quatre la prend');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :L1::uuid and commande_id = :'c1' and type = 'course_prise'), 1,
  'Un apprend « Déjà pris par Quatre »');
select essai.verifie(not pg_temp.voit(:L2::uuid, :'c1'), 'elle disparaît des demandes des autres');

select essai.titre('6. Prise à temps par le premier : le deuxième n''est pas dérangé');
select pg_temp.commande_payee('TRX-CASCADE-2') as c2 \gset
select essai.verifie(not (:L4::uuid = any(coalesce((select ordre from public.courses_cascade where commande_id = :'c2'), '{}'::uuid[]))),
  'Quatre, déjà en course, n''est pas dans le classement');
select essai.egal(pg_temp.alerte(:L1::uuid, :'c2'), 1, 'Un est alerté');
select essai.egal(pg_temp.prend(:L1::uuid, :'c2'), 1, 'et la prend dans les 30 secondes');
select essai.egal(pg_temp.trente_secondes(:'c2'), 0, 'la tâche n''a plus rien à faire');
select essai.egal(pg_temp.alerte(:L2::uuid, :'c2'), 0, 'Deux n''a jamais sonné');

select essai.titre('7. Annulée par son livreur : la cascade repart, sans lui');
select essai.devenir(:L1::uuid); set role authenticated;
select public.refuser_course(:'c2', 'Crevaison') as rf \gset
reset role; select essai.personne();
select essai.egal((select ordre[1] from public.courses_cascade where commande_id = :'c2'), :L2::uuid,
  'le plus proche est maintenant Deux (Un l''a refusée, Quatre est en course)');
select essai.verifie(not (:L1::uuid = any(coalesce((select ordre from public.courses_cascade where commande_id = :'c2'), '{}'::uuid[]))),
  'Un n''est plus dans l''ordre');
select essai.egal((select count(*)::int from public.notifications
                    where destinataire = :L2::uuid and commande_id = :'c2' and type = 'course_proposee'
                      and titre like 'Course à reprendre%'), 1, 'Deux sonne : « Course à reprendre »');
select essai.verifie(not pg_temp.voit(:L1::uuid, :'c2'), 'Un ne la revoit pas');

select essai.titre('8. Cascade éteinte : à tous d''un coup, comme avant');
update public.cascade_reglage set actif = false where id = 1;
select pg_temp.commande_payee('TRX-CASCADE-3') as c3 \gset
select essai.egal((select tous from public.courses_cascade where commande_id = :'c3'), true,
  'partie à tous tout de suite');
select essai.egal(pg_temp.alerte(:L2::uuid, :'c3') + pg_temp.alerte(:L3::uuid, :'c3'), 2,
  'Deux et Trois sonnent ensemble');
update public.cascade_reglage set actif = true where id = 1;
update cron.job set active = false where jobname = 'courses-cascade';
select pg_temp.commande_payee('TRX-CASCADE-4') as c4 \gset
select essai.egal((select tous from public.courses_cascade where commande_id = :'c4'), true,
  'sans la tâche des 5 secondes, pas de cascade : à tous tout de suite (elle resterait au premier)');
update cron.job set active = true where jobname = 'courses-cascade';

select essai.titre('9. La boutique reprend la course à son livreur : elle repart');
select essai.devenir(:L2::uuid); set role authenticated;
select public.prendre_course(:'c2') as pris \gset
reset role; select essai.personne();
select essai.devenir('11111111-1111-1111-1111-111111111111'::uuid); set role authenticated;
select public.assigner_livreur(:'c2', 'bou_cascade', null) as repris \gset
reset role; select essai.personne();
select essai.verifie((select prochaine is not null and not tous and etape = 1 from public.courses_cascade
                       where commande_id = :'c2'),
  'reprise à Deux : la cascade repart du plus proche, avec son horloge');

select essai.titre('10. La position du livreur libre');
update public.positions_livreurs set enregistre_le = now() - interval '2 hours' where profil_id = :L3::uuid;
select essai.devenir(:L3::uuid); set role authenticated;
select essai.verifie(public.signaler_ma_position(9.3500, 2.6301, 12), 'BIZZOO Admin ouvert : sa position part');
select essai.verifie(not public.signaler_ma_position(9.3501, 2.6301, 12),
  'pas plus d''une écriture toutes les 30 secondes');
reset role; select essai.personne();
select essai.verifie((select enregistre_le > now() - interval '1 minute' and latitude = 9.35
                        from public.positions_livreurs where profil_id = :L3::uuid),
  'elle est à jour : il redevient « récent » pour la cascade');
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.verifie(not public.signaler_ma_position(6.37, 2.42, 10), 'un client n''écrit rien');
reset role; select essai.personne();

select essai.titre('11. Disponible : sa position, application fermée');
select essai.devenir(:L3::uuid); set role authenticated;
select public.ouvrir_suivi_livreur() ->> 'jeton' as jeton_vieux \gset
select public.ouvrir_suivi_livreur() as o3 \gset
select :'o3'::jsonb ->> 'jeton' as jeton3 \gset
select essai.egal((:'o3'::jsonb ->> 'disponible'), 'true', 'le jeton dit « disponible » (par défaut)');
reset role; select essai.personne();
set role anon;
select essai.egal((public.position_livreur(:'jeton_vieux', 9.3450, 2.6302, 20) ->> 'continuer'), 'true',
  'un jeton renouvelé : l''ancien vaut encore (10 minutes), le service en route n''est pas coupé');
reset role;
update public.suivis_livreurs set precedent_expire_le = now() - interval '1 second' where profil_id = :L3::uuid;
select essai.refuse(format($$select public.position_livreur(%L, 9.3, 2.6, 10)$$, :'jeton_vieux'),
  'passé ces 10 minutes : refusé');
update public.suivis_livreurs set expire_le = now() + interval '1 hour' where profil_id = :L3::uuid;
update public.positions_livreurs set enregistre_le = now() - interval '2 hours' where profil_id = :L3::uuid;
set role anon;
select essai.egal((public.position_livreur(:'jeton3', 9.3450, 2.6302, 20))::text,
  '{"continuer": true, "en_course": false}', 'libre et disponible, sans session (le jeton fait foi) : continuer');
reset role;
select essai.verifie((select enregistre_le > now() - interval '1 minute' and latitude = 9.345
                        from public.positions_livreurs where profil_id = :L3::uuid),
  'sa position est à jour : il compte parmi les plus proches');
select essai.verifie((select expire_le > now() + interval '15 hours' from public.suivis_livreurs where profil_id = :L3::uuid),
  'application fermée des jours durant : le jeton se prolonge tant que le téléphone se manifeste');
set role anon;
select public.position_livreur(:'jeton3', 9.9, 2.9, 20) as r \gset
reset role;
select essai.verifie((select latitude = 9.345 from public.positions_livreurs where profil_id = :L3::uuid),
  'libre : pas plus d''une écriture toutes les 30 secondes');
select essai.refuse($$select public.position_livreur('pas-un-jeton', 9.3, 2.6, 10)$$, 'un faux jeton : refusé');
select essai.devenir(:L3::uuid); set role authenticated;
select essai.egal(public.regler_disponibilite(false), false, 'il se dit « pas disponible »');
reset role; select essai.personne();
select essai.verifie(not exists (select 1 from public.suivis_livreurs where profil_id = :L3::uuid),
  'pas disponible et libre : son suivi est révoqué (« Localiser » ne le montre plus actif)');
select essai.refuse(format($$select public.position_livreur(%L, 9.3451, 2.6302, 20)$$, :'jeton3'),
  'et son téléphone, refusé, s''arrête');
select essai.devenir(:L3::uuid); set role authenticated;
select essai.verifie(not public.signaler_ma_position(9.3452, 2.6302, 20),
  'la page ouverte ne l''envoie pas non plus');
reset role; select essai.personne();
select pg_temp.commande_payee('TRX-CASCADE-5') as c5 \gset
select essai.verifie(not (:L3::uuid = any(coalesce((select ordre from public.courses_cascade where commande_id = :'c5'), '{}'::uuid[]))),
  'et il n''est plus parmi les plus proches');
select essai.devenir(:L3::uuid); set role authenticated;
select essai.verifie((public.ouvrir_suivi_livreur() ->> 'jeton') is null,
  'pas disponible et sans course : pas de jeton (rien à suivre)');
select essai.egal(public.regler_disponibilite(true), true, 'il se redit disponible');
select essai.verifie((public.ouvrir_suivi_livreur() ->> 'jeton') is not null, 'disponible : un jeton');
select essai.verifie(not public.fermer_suivi_livreur(false),
  'la page arrête le suivi alors qu''il est disponible : la base le garde');
select essai.verifie(public.fermer_suivi_livreur(true), 'déconnexion : la base l''oublie');
reset role; select essai.personne();
select essai.verifie(not exists (select 1 from public.suivis_livreurs where profil_id = :L3::uuid),
  'plus aucun suivi actif pour lui');
select essai.devenir(:ACHETEUR::uuid); set role authenticated;
select essai.refuse($$select public.regler_disponibilite(true)$$, 'un client ne règle rien');
reset role; select essai.personne();

-- Le décor rendu : nos livreurs ne gênent pas les essais suivants.
update public.cascade_reglage set actif = false where id = 1;
drop schema cron cascade;
update public.profils set actif = false
 where id in (:L1::uuid, :L2::uuid, :L3::uuid, :L4::uuid, :L5::uuid);
