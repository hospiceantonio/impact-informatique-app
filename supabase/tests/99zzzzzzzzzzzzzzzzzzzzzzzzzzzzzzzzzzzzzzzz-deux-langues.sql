-- =========================================================
-- Deux langues : la langue de chaque compte (3.73.0)
--
-- Ce qu'on prouve :
--   1. chacun règle SA langue (fr ou en), et ne lit que la sienne ;
--      un visiteur ne règle rien ;
--   2. sans choix connu : le français ;
--   3. la notification poussée sur le téléphone porte la langue du
--      destinataire (la fonction Edge traduit) ;
--   4. le SMS d'un client anglophone part en anglais, celui d'un client
--      francophone en français, comme avant.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set CLIENT   '''ffffffff-2222-2222-2222-222222222222'''
\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''

select essai.titre('1. Chacun règle sa langue, et ne lit que la sienne');
set role anon;
select essai.refuse($$select public.regler_langue('en')$$, 'un visiteur ne règle aucune langue');
reset role;
select essai.devenir(:CLIENT::uuid); set role authenticated;
select essai.refuse($$select public.regler_langue('de')$$, 'une langue inconnue : refusée');
select essai.egal(public.regler_langue('EN'), 'en', 'le client choisit l''anglais');
select essai.egal(public.regler_langue('en'), 'en', 'le redire ne change rien');
select essai.egal((select count(*)::int from public.langues_comptes), 1, 'il ne lit que sa propre ligne');
select essai.refuse($$select public.langue_du_compte('11111111-1111-1111-1111-111111111111')$$,
  'il ne lit pas la langue d''un autre compte');
reset role; select essai.personne();
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select public.regler_langue('fr');
select essai.egal((select count(*)::int from public.langues_comptes), 1, 'l''enseigne non plus ne lit que la sienne');
reset role; select essai.personne();

select essai.titre('2. Sans choix connu : le français');
select essai.egal(public.langue_du_compte('00000000-0000-4000-8000-0000000000aa'::uuid), 'fr', 'un compte qui n''a rien choisi : fr');
select essai.egal(public.langue_du_compte(null), 'fr', 'aucun compte : fr');
select essai.egal(public.langue_du_compte(:CLIENT::uuid), 'en', 'le client : en');

select essai.titre('3. La notification poussée porte la langue du destinataire');
insert into public.notifications (destinataire, type, titre, corps, lien, sonne)
values (:CLIENT::uuid, 'commande_preparee', 'Votre colis est prêt', 'Commande BZ-000999 — il part bientôt.', '#/commande/cmd_dl', true)
returning id as n_en \gset
select essai.egal((public.push_a_envoyer(:n_en) ->> 'langue'), 'en', 'push_a_envoyer rend « en » pour le client anglophone');
insert into public.notifications (destinataire, type, titre, corps, lien, sonne)
values (:ENSEIGNE::uuid, 'commande_payee', 'Nouvelle commande payée', 'La commande BZ-000999 est payée.', '#/commandes/cmd_dl', true)
returning id as n_fr \gset
select essai.egal((public.push_a_envoyer(:n_fr) ->> 'langue'), 'fr', 'et « fr » pour l''enseigne');

select essai.titre('4. Le SMS du client anglophone part en anglais');
update public.sms_reglages set url = 'https://exemple.essai/functions/v1/envoyer-sms-commande' where id = 1;
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select public.regler_sms_commandes(true, 3, 300, array['commande_payee', 'commande_en_livraison'], true, true, true);
reset role; select essai.personne();
update public.sms_reglages set actif_depuis = now() - interval '1 hour' where id = 1;
update public.boutiques set actif = true, ouvertures = null where id = 'bou_informatique';
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_dl', 'bou_informatique', 'Souris DL', 3000, 'sc_hightech_accessoires', 20, true)
on conflict (id) do update set stock = 20, disponible = true, masque = false;
delete from public.appareils_push where compte = :CLIENT::uuid and application = 'client';
create function pg_temp.payer(qui uuid, trx text) returns text language plpgsql as $$
declare v_id text;
begin
  perform essai.devenir(qui);
  set local role authenticated;
  v_id := public.creer_commande('{"nom":"Rosine","tel":"97666099","adresse":"Godomey"}'::jsonb,
    '[{"produit_id":"prod_dl","quantite":1}]'::jsonb, '', true, false) ->> 'id';
  reset role;
  perform essai.personne();
  perform public.marquer_payee(v_id, trx,
    (select coalesce(c.acompte, c.total)::int from public.commandes c where c.id = v_id), 'feexpay');
  return v_id;
end $$;
select pg_temp.payer(:CLIENT::uuid, 'TRX-DL-1') as c_en \gset
select essai.verifie((select texte from public.sms_commandes where commande_id = :'c_en' and etape = 'commande_payee')
                       ~ '^BIZZOO: your order BZ-[0-9]+ is confirmed\. We are preparing it\.',
  'payée : « BIZZOO: your order … is confirmed. We are preparing it. »');
select essai.verifie((select max(length(texte)) from public.sms_commandes where commande_id = :'c_en') <= 160,
  'il tient en un SMS');
select essai.devenir(:CLIENT::uuid); set role authenticated;
select public.regler_langue('fr');
reset role; select essai.personne();
select pg_temp.payer(:CLIENT::uuid, 'TRX-DL-2') as c_fr \gset
select essai.verifie((select texte from public.sms_commandes where commande_id = :'c_fr' and etape = 'commande_payee')
                       ~ '^BIZZOO : votre commande BZ-[0-9]+ est confirmee',
  'revenu au français : le SMS repart en français');
update public.sms_reglages set actif = false, url = '' where id = 1;
