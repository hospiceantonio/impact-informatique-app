-- =========================================================
-- La clôture automatique des commandes, et le menu Incidents (3.69.0)
--
-- Ce qu'on prouve :
--   1. le délai est de 24 heures par défaut ; seule l'administration le
--      règle (vide : clôture à la main) ;
--   2. une commande livrée et confirmée se clôture d'elle-même 24 heures
--      après le « Je l'ai reçu », au journal « clôturée automatiquement » ;
--      pas avant ;
--   3. ce qui demande un regard reste ouvert : un reste à encaisser (qui
--      bloque aussi la clôture à la main), un incident ouvert, une
--      commande que l'administration a rouverte ;
--   4. en mode manuel, rien ne se clôture seul ; à 0 heure, tout de suite ;
--   5. personne ne déclenche la clôture automatique depuis l'application ;
--   6. le menu Incidents : signaler par le numéro de la commande, les
--      incidents ouverts toujours listés, les résolus sur la période,
--      la pastille ; fermé à qui ne suit pas les commandes.
--
-- Le décor vient des fichiers d'avant : le CEO (le compte de
-- l'enseigne), l'acheteuse et l'écran du fichier « personnel ».
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE     '''11111111-1111-1111-1111-111111111111'''
\set MEMBRE       '''a0a0a0a0-0003-4000-8000-000000000003'''
\set ACHETEUSE_RH '''a0a0a0a0-0008-4000-8000-000000000008'''

-- Une commande payée, ses articles livrés et confirmés il y a « heures »
-- heures ; « manque » : ce que le client doit encore à la livraison.
create function pg_temp.confirmee(heures int, manque bigint default 0) returns text
language plpgsql as $$
declare
  nouvelle text;
begin
  perform essai.devenir('a0a0a0a0-0008-4000-8000-000000000008'::uuid);
  set local role authenticated;
  nouvelle := public.creer_commande('{"nom":"Sika","tel":"97666088","adresse":"Fidjrosse von morija"}'::jsonb,
          '[{"produit_id":"prod_rh_stats","quantite":1}]'::jsonb) ->> 'id';
  reset role;
  perform essai.personne();
  perform public.marquer_payee(nouvelle, 'TRX-CLOT-' || nouvelle,
    (select coalesce(c.acompte, c.total) from public.commandes c where c.id = nouvelle), 'feexpay');
  update public.commandes c set verse = c.total - manque where c.id = nouvelle;
  -- Le « Je l'ai reçu » antidaté : le drapeau de « confirmer_reception ».
  perform set_config('bizzoo.reception', 'oui', true);
  perform set_config('bizzoo.livraison', 'oui', true);
  perform set_config('bizzoo.interne', 'oui', true);
  update public.commande_lignes l set etat = 'remise', confirme_le = now() - make_interval(hours => heures)
   where l.commande_id = nouvelle;
  perform set_config('bizzoo.reception', '', true);
  perform set_config('bizzoo.livraison', '', true);
  perform set_config('bizzoo.interne', '', true);
  return nouvelle;
end $$;

-- Au nom d'un compte, avec le rôle des applications.
create function pg_temp.en(qui uuid, requete text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform essai.devenir(qui);
  set local role authenticated;
  execute requete into r;
  reset role;
  perform essai.personne();
  return r;
end $$;

-- La même chose, pour une fonction qui ne rend rien.
create function pg_temp.fais(qui uuid, requete text) returns void language plpgsql as $$
begin
  perform essai.devenir(qui);
  set local role authenticated;
  execute requete;
  reset role;
  perform essai.personne();
end $$;

create function pg_temp.close(id text) returns boolean language sql as $$
  select exists (select 1 from public.rh_suivi_commandes s where s.commande_id = id and s.cloturee_le is not null);
$$;

-- ---------------------------------------------------------
select essai.titre('1. Le délai de clôture');
select essai.egal((select cloture_auto_h from public.rh_reglages_suivi where id), 24, 'par défaut : 24 heures');
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.refuse($$select public.rh_suivi_regler_cloture(1)$$, 'un employé ne règle pas la clôture');
select essai.refuse($$select public.rh_suivi_cloturer_auto()$$,
  'ni ne déclenche la clôture automatique');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse($$select public.rh_suivi_regler_cloture(721)$$, 'plus de 30 jours : refusé');
select essai.refuse($$select public.rh_suivi_cloturer_auto()$$,
  'même l''administration ne la déclenche pas depuis l''application : pg_cron s''en charge');
select public.rh_suivi_regler_cloture(24);
select essai.egal((public.rh_suivi(current_date, current_date) #>> '{reglages,cloture_auto_h}')::int, 24,
  'le réglage se lit avec les autres délais');
reset role; select essai.personne();
set role anon;
select essai.refuse($$select public.rh_suivi_regler_cloture(24)$$, 'un visiteur non plus');
reset role;

-- ---------------------------------------------------------
select essai.titre('2. Livrée et confirmée : clôturée 24 heures après');
select pg_temp.confirmee(30) as a_point \gset
select pg_temp.confirmee(2) as trop_tot \gset
select pg_temp.confirmee(30, 1000) as reste_du \gset
select pg_temp.confirmee(30) as avec_incident \gset
select pg_temp.confirmee(30) as a_rouvrir \gset
select pg_temp.en(:ENSEIGNE::uuid, format('select to_jsonb(public.rh_incident_ouvrir(%L, %L, %L))',
  :'avec_incident', 'colis_abime', 'Le carton est arrivé ouvert')) as incident \gset

select essai.verifie(public.rh_suivi_cloturer_auto() >= 2, 'le passage clôture ce qui est prêt');
select essai.verifie(pg_temp.close(:'a_point'), 'confirmée il y a 30 h : clôturée');
select essai.verifie((select cloturee_par is null from public.rh_suivi_commandes where commande_id = :'a_point'),
  'par personne : c''est la base');
select essai.verifie(exists (select 1 from public.rh_journal_lignes
                              where commande_id = :'a_point' and quoi = 'suivi' and valeur = 'cloturee_auto'),
  'la chronologie dit « clôturée automatiquement »');
select essai.egal(pg_temp.en(:ENSEIGNE::uuid, format('select public.rh_suivi_commande(%L)', :'a_point')) ->> 'statut',
  'Clôturée', 'et le suivi la montre clôturée');
select essai.verifie(not pg_temp.close(:'trop_tot'), 'confirmée il y a 2 h : pas encore');

-- ---------------------------------------------------------
select essai.titre('3. Ce qui demande un regard reste ouvert');
select essai.verifie(not pg_temp.close(:'reste_du'), 'un reste à encaisser : pas de clôture automatique');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse(format($$select public.rh_suivi_cloturer(%L)$$, :'reste_du'),
  'ni à la main : il faut d''abord encaisser');
reset role; select essai.personne();
select essai.verifie(not pg_temp.close(:'avec_incident'), 'un incident ouvert : pas de clôture');
select pg_temp.fais(:ENSEIGNE::uuid, format('select public.rh_incident_resoudre(%s, %L)', :'incident', 'Remplacé par la boutique'));
select public.rh_suivi_cloturer_auto() as n \gset
select essai.verifie(pg_temp.close(:'avec_incident'), 'l''incident résolu : clôturée au passage suivant');

select public.rh_suivi_cloturer_auto() as n \gset
select essai.verifie(pg_temp.close(:'a_rouvrir'), 'une autre, clôturée seule');
select pg_temp.fais(:ENSEIGNE::uuid, format('select public.rh_suivi_rouvrir(%L)', :'a_rouvrir'));
select public.rh_suivi_cloturer_auto() as n \gset
select essai.verifie(not pg_temp.close(:'a_rouvrir'),
  'rouverte par l''administration : la base ne la referme pas d''elle-même');
select pg_temp.fais(:ENSEIGNE::uuid, format('select public.rh_suivi_cloturer(%L)', :'a_rouvrir'));
select essai.verifie(pg_temp.close(:'a_rouvrir'), 'l''administration la referme à la main');

-- ---------------------------------------------------------
select essai.titre('4. Manuel, ou tout de suite');
select pg_temp.fais(:ENSEIGNE::uuid, 'select public.rh_suivi_regler_cloture(null)');
select pg_temp.confirmee(50) as manuelle \gset
select essai.egal(public.rh_suivi_cloturer_auto(), 0, 'réglée « à la main » : la base ne clôture rien');
select essai.verifie(not pg_temp.close(:'manuelle'), 'la commande reste ouverte');
select pg_temp.fais(:ENSEIGNE::uuid, 'select public.rh_suivi_regler_cloture(0)');
select public.rh_suivi_cloturer_auto() as n \gset
select essai.verifie(pg_temp.close(:'trop_tot'), 'à 0 heure : clôturée dès le « Je l''ai reçu »');
select essai.verifie(pg_temp.close(:'manuelle'), 'et celle d''avant aussi');
select pg_temp.fais(:ENSEIGNE::uuid, 'select public.rh_suivi_regler_cloture(24)');

-- ---------------------------------------------------------
select essai.titre('5. Le menu Incidents');
select numero as numero_reste from public.commandes where id = :'reste_du' \gset
select pg_temp.en(:ENSEIGNE::uuid, format('select to_jsonb(public.rh_incident_ouvrir(%L, %L, %L))',
  lower(:'numero_reste'), 'paiement', 'Le client dit avoir déjà tout payé')) as par_numero \gset
select essai.egal((select commande_id from public.rh_incidents where id = :'par_numero'::bigint), :'reste_du',
  'signalé par le numéro de la commande (même en minuscules)');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse($$select public.rh_incident_ouvrir('BZ-INEXISTANT', 'autre', 'x')$$,
  'un numéro inconnu : refusé');
reset role; select essai.personne();

-- Un vieil incident ouvert, un vieil incident résolu : 40 jours.
select pg_temp.en(:ENSEIGNE::uuid, format('select to_jsonb(public.rh_incident_ouvrir(%L, %L, %L))',
  :'trop_tot', 'retard', 'Ancien, toujours ouvert')) as vieux_ouvert \gset
select pg_temp.en(:ENSEIGNE::uuid, format('select to_jsonb(public.rh_incident_ouvrir(%L, %L, %L))',
  :'trop_tot', 'adresse', 'Ancien, résolu')) as vieux_resolu \gset
update public.rh_incidents set cree_le = now() - interval '40 days' where id in (:'vieux_ouvert'::bigint, :'vieux_resolu'::bigint);
update public.rh_incidents set resolu_le = now() - interval '39 days', resolution = 'Trouvée'
 where id = :'vieux_resolu'::bigint;

select pg_temp.en(:ENSEIGNE::uuid, 'select public.rh_incidents_liste()') as liste \gset
select essai.verifie(exists (select 1 from jsonb_array_elements(:'liste'::jsonb -> 'incidents') i
                              where (i ->> 'id')::bigint = :'par_numero'::bigint
                                and i ->> 'numero' = :'numero_reste' and i ->> 'client' = 'Sika'),
  'la liste donne le numéro de la commande et le client');
select essai.verifie(exists (select 1 from jsonb_array_elements(:'liste'::jsonb -> 'incidents') i
                              where (i ->> 'id')::bigint = :'vieux_ouvert'::bigint),
  'un incident ouvert y est, quelle que soit sa date');
select essai.verifie(not exists (select 1 from jsonb_array_elements(:'liste'::jsonb -> 'incidents') i
                                  where (i ->> 'id')::bigint = :'vieux_resolu'::bigint),
  'un incident résolu hors de la période n''y est pas');
select essai.verifie(exists (select 1 from jsonb_array_elements(:'liste'::jsonb -> 'incidents') i
                              where (i ->> 'id')::bigint = :'incident'::bigint and i ->> 'resolution' = 'Remplacé par la boutique'),
  'un incident résolu sur la période y est, avec sa résolution');
select essai.egal((pg_temp.en(:ENSEIGNE::uuid, 'select to_jsonb(public.rh_incidents_ouverts_nb())'))::int,
  (select count(*)::int from public.rh_incidents where resolu_le is null), 'la pastille compte les incidents ouverts');

select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.refuse($$select public.rh_incidents_liste()$$, 'un employé qui ne suit pas les commandes ne les voit pas');
select essai.egal(public.rh_incidents_ouverts_nb(), 0, 'et sa pastille reste à zéro');
reset role; select essai.personne();
set role anon;
select essai.refuse($$select public.rh_incidents_liste()$$, 'un visiteur non plus');
reset role;
