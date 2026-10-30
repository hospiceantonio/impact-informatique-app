-- =========================================================
-- La préparation en retard : un délai réglable, une alerte (3.72.0)
--
-- Ce qu'on prouve :
--   1. le délai se règle en minutes, par l'administration seule, dans
--      ses bornes ;
--   2. avant le délai : aucune alerte ;
--   3. après : la boutique ET BIZZOO sont alertés, et ça sonne ;
--      une seule fois par commande ; le suivi la marque en retard ;
--   4. préparée : plus d'alerte pour les suivantes.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''

select essai.titre('1. Le délai, en minutes, par l''administration seule');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse($$select public.rh_suivi_regler_preparation(30)$$,
  'l''administrateur d''une boutique ne règle pas le délai');
reset role; select essai.personne();
select essai.verifie((select preparation_min is null from public.rh_reglages_suivi where id),
  'au départ : pas de délai en minutes, celui en heures s''applique');
update public.rh_reglages_suivi set preparation_min = 30 where id;
select essai.refuse($$update public.rh_reglages_suivi set preparation_min = 2 where id$$,
  'moins de 5 minutes : refusé');

select essai.titre('Le décor : une commande payée, vue par la boutique');
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
update public.boutiques set actif = true, ouvertures = null where id = 'bou_informatique';
reset role; select essai.personne();
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_prep', 'bou_informatique', 'Chargeur', 5000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true, masque = false;
create function pg_temp.commande_vue(trx text) returns text language plpgsql as $$
declare v_id text;
begin
  perform essai.devenir('ffffffff-2222-2222-2222-222222222222'::uuid);
  set local role authenticated;
  v_id := public.creer_commande('{"nom":"Rosine","tel":"97666099","adresse":"Godomey"}'::jsonb,
    '[{"produit_id":"prod_prep","quantite":1}]'::jsonb, '', true, false) ->> 'id';
  reset role;
  perform essai.personne();
  perform public.marquer_payee(v_id, trx,
    (select coalesce(c.acompte, c.total)::int from public.commandes c where c.id = v_id), 'feexpay');
  perform essai.devenir('22222222-2222-2222-2222-222222222222'::uuid);
  set local role authenticated;
  update public.commande_lignes set etat = 'vue' where commande_id = v_id;
  reset role;
  perform essai.personne();
  return v_id;
end $$;
create function pg_temp.alertes(cmd text, qui uuid) returns int language sql as $$
  select count(*)::int from public.notifications
   where commande_id = cmd and type = 'preparation_en_retard' and destinataire = qui and sonne;
$$;
select pg_temp.commande_vue('TRX-PREP-1') as p1 \gset

select essai.titre('2. Avant le délai : rien');
select public.alerter_preparations() as n0 \gset
select essai.egal(pg_temp.alertes(:'p1', :CHEF::uuid), 0, 'vue il y a un instant : pas d''alerte');

select essai.titre('3. Après le délai : la boutique et BIZZOO, une fois');
-- Vue il y a 40 minutes (le journal date le « vu »).
update public.rh_journal_lignes set le = now() - interval '40 minutes'
 where commande_id = :'p1' and quoi = 'etat' and valeur = 'vue';
select essai.verifie(public.alerter_preparations() > 0, 'la tâche de chaque minute envoie l''alerte');
select essai.egal(pg_temp.alertes(:'p1', :CHEF::uuid), 1, 'la boutique est alertée, et ça sonne');
select essai.egal(pg_temp.alertes(:'p1', :ENSEIGNE::uuid), 1, 'BIZZOO aussi');
select essai.verifie((select corps like '%plus de 30 minutes%Relancez la boutique%' from public.notifications
                        where commande_id = :'p1' and type = 'preparation_en_retard' and destinataire = :ENSEIGNE::uuid),
  'BIZZOO lit le délai et la boutique à relancer');
select public.alerter_preparations() as n2 \gset
select essai.egal(pg_temp.alertes(:'p1', :CHEF::uuid) + pg_temp.alertes(:'p1', :ENSEIGNE::uuid), 2,
  'repassée : pas une seconde fois');
select essai.verifie((select (d -> 'alertes') ? 'retard_preparation'
                        from public.rh_suivi_donnees(now() - interval '1 day', now() + interval '1 day', :'p1') d),
  'le suivi la marque « Préparation en retard »');

select essai.titre('4. Préparée : plus d''alerte');
select pg_temp.commande_vue('TRX-PREP-2') as p2 \gset
update public.rh_journal_lignes set le = now() - interval '40 minutes'
 where commande_id = :'p2' and quoi = 'etat' and valeur = 'vue';
select essai.devenir(:CHEF::uuid); set role authenticated;
update public.commande_lignes set etat = 'preparee' where commande_id = :'p2';
reset role; select essai.personne();
select public.alerter_preparations() as n3 \gset
select essai.egal(pg_temp.alertes(:'p2', :CHEF::uuid), 0, 'préparée à temps… ou en retard : plus rien à signaler');

-- Le décor rendu.
update public.rh_reglages_suivi set preparation_min = null where id;
