-- =========================================================
-- Le client prévenu à chaque étape : push et SMS (3.70.0)
--
-- Ce qu'on prouve :
--   1. le push d'une notification d'acheteur (« #/commande/… ») va vers
--      les téléphones de l'application CLIENT, le reste vers BIZZOO Admin ;
--   2. coupés par défaut, les SMS ne partent que lorsque le
--      superadministrateur les allume — et seulement lui ;
--   3. une commande sans compte reçoit un SMS aux étapes choisies :
--      payée, livreur (nom et numéro), livrée — sans accents, un seul SMS ;
--      une étape ne part qu'une fois ; le plafond par commande tient ;
--   4. un client avec l'application Android n'en reçoit pas (il a le
--      push) ; sans application, il en reçoit ; une commande payée avant
--      l'allumage, jamais ;
--   5. la file : la fonction Edge prend un SMS une fois, le verdict de la
--      passerelle le range, un « injoignable » repart, trois fois au plus ;
--      personne ne la touche depuis l'application ;
--   6. le compteur de BIZZOO Personnel, sans aucun numéro de client.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set SUPER    '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set MEMBRE   '''a0a0a0a0-0003-4000-8000-000000000003'''
\set CLI_APP  '''e5e5e5e5-0000-0000-0000-000000000001'''
\set CLI_WEB  '''e5e5e5e5-0000-0000-0000-000000000002'''
\set LIV      '''e5e5e5e5-0000-0000-0000-000000000003'''

select essai.titre('Le décor : un livreur, deux clients avec compte (l''un a l''application Android)');
insert into auth.users (id, email) values
  (:CLI_APP::uuid, 'cli.app@essai.bj'), (:CLI_WEB::uuid, 'cli.web@essai.bj'), (:LIV::uuid, 'liv.sms@essai.bj')
on conflict do nothing;
insert into public.clients (id, nom, tel, indicatif) values
  (:CLI_APP::uuid, 'Afi', '0196800001', '229'), (:CLI_WEB::uuid, 'Basile', '96800002', '229')
on conflict (id) do update set tel = excluded.tel;
update public.profils set role = 'livreur', actif = true, boutique_id = null, nom = 'Yaô Séna', tel = '0196800009'
 where id = :LIV::uuid;
insert into public.appareils_push (jeton, compte, application) values
  ('jeton-client-android-essai-0001', :CLI_APP::uuid, 'client'),
  ('jeton-admin-chef-essai-00000001', :CHEF::uuid, 'admin')
on conflict (jeton) do update set compte = excluded.compte, application = excluded.application;
update public.boutiques set actif = true, ouvertures = null where id in ('bou_informatique', 'bou_essai_voisine');
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible) values
  ('prod_sms_b', 'bou_essai_voisine', 'Housse', 3000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true, masque = false;
\set LIV2 '''e5e5e5e5-0000-0000-0000-000000000004'''
insert into auth.users (id, email) values (:LIV2::uuid, 'liv2.sms@essai.bj') on conflict do nothing;
update public.profils set role = 'livreur', actif = true, boutique_id = null, nom = 'Bio', tel = '0196800008'
 where id = :LIV2::uuid;
update public.reglages set compte_obligatoire = false where id = 1;
update public.paiement set livraison_latitude = null, livraison_longitude = null where id = 1;

-- Une commande, par un visiteur (qui = null) ou au nom d'un client ; payée.
create function pg_temp.payee(qui uuid, tel text) returns text language plpgsql as $$
declare nouvelle text;
begin
  if qui is null then
    perform essai.personne();
    set local role anon;
  else
    perform essai.devenir(qui);
    set local role authenticated;
  end if;
  nouvelle := public.creer_commande(jsonb_build_object('nom', 'Client SMS', 'tel', tel, 'adresse', 'Cotonou'),
          '[{"produit_id":"prod_rh_stats","quantite":1}]'::jsonb) ->> 'id';
  reset role;
  perform essai.personne();
  perform public.marquer_payee(nouvelle, 'TRX-SMS-' || nouvelle,
    (select c.total from public.commandes c where c.id = nouvelle), 'feexpay');
  return nouvelle;
end $$;
-- Une étape de la livraison, comme l'écrivent les fonctions des boutiques et du livreur.
create function pg_temp.etape(cmd text, etat text, livreur uuid default null) returns void language plpgsql as $$
begin
  perform set_config('bizzoo.livraison', 'oui', true);
  perform set_config('bizzoo.interne', 'oui', true);
  if livreur is not null then
    -- Comme « assigner_livreur » puis « accepter_course » : la course est
    -- confiée (« reçu » remis à zéro), puis acceptée.
    update public.commande_lignes l set livreur_id = livreur, recu_le = null where l.commande_id = cmd;
    update public.commande_lignes l set recu_le = now() where l.commande_id = cmd;
  end if;
  if etat <> '' then
    update public.commande_lignes l set etat = etape.etat where l.commande_id = cmd;
  end if;
  perform set_config('bizzoo.livraison', '', true);
  perform set_config('bizzoo.interne', '', true);
end $$;
-- Une commande de DEUX articles (deux boutiques), payée.
create function pg_temp.payee2(tel text) returns text language plpgsql as $$
declare nouvelle text;
begin
  perform essai.personne();
  set local role anon;
  nouvelle := public.creer_commande(jsonb_build_object('nom', 'Client SMS', 'tel', tel, 'adresse', 'Cotonou'),
    '[{"produit_id":"prod_rh_stats","quantite":1},{"produit_id":"prod_sms_b","quantite":1}]'::jsonb) ->> 'id';
  reset role;
  perform public.marquer_payee(nouvelle, 'TRX-SMS-' || nouvelle,
    (select c.total from public.commandes c where c.id = nouvelle), 'feexpay');
  return nouvelle;
end $$;
create function pg_temp.etape_produit(cmd text, produit text, etat text) returns void language plpgsql as $$
begin
  perform set_config('bizzoo.livraison', 'oui', true);
  perform set_config('bizzoo.interne', 'oui', true);
  update public.commande_lignes l set etat = etape_produit.etat where l.commande_id = cmd and l.produit_id = produit;
  perform set_config('bizzoo.livraison', '', true);
  perform set_config('bizzoo.interne', '', true);
end $$;
create function pg_temp.sms(cmd text) returns text language sql as $$
  select coalesce(string_agg(etape || ':' || etat, ',' order by id), '') from public.sms_commandes where commande_id = cmd;
$$;

-- ---------------------------------------------------------
select essai.titre('1. Le push va à la bonne application');
select public.notifier(array[:CLI_APP::uuid], 'essai_client', 'Votre colis est en route', 'Essai',
  '#/commande/cmd_essai_push', null, null, true) as n \gset
select id as notif_client from public.notifications where destinataire = :CLI_APP::uuid and type = 'essai_client' \gset
select essai.egal((public.push_a_envoyer(:'notif_client'::bigint) ->> 'application'), 'client',
  'une notification d''acheteur (« #/commande/… ») part vers l''application client');
select essai.egal((select push_le is not null from public.notifications where id = :'notif_client'::bigint), true,
  'marquée envoyée');
select public.notifier(array[:CLI_APP::uuid], 'essai_client2', 'x', 'x', '#/commande/cmd_essai_push2', null, null, true) as n \gset
select id as notif_client2 from public.notifications where destinataire = :CLI_APP::uuid and type = 'essai_client2' \gset
select essai.verifie((public.push_a_envoyer(:'notif_client2'::bigint) -> 'jetons') ? 'jeton-client-android-essai-0001',
  'avec le téléphone de l''application client');
select public.notifier(array[:CHEF::uuid], 'essai_boutique', 'Nouvelle commande', 'x', '#/commandes/cmd_x', null, null, true) as n \gset
select id as notif_chef from public.notifications where destinataire = :CHEF::uuid and type = 'essai_boutique' \gset
select essai.egal((public.push_a_envoyer(:'notif_chef'::bigint) ->> 'application'), 'admin',
  'une notification d''équipe part toujours vers BIZZOO Admin');

-- ---------------------------------------------------------
select essai.titre('2. Coupés par défaut ; seul le superadministrateur les allume');
select essai.egal((select actif from public.sms_reglages where id = 1), false, 'les SMS sont coupés au départ');
select pg_temp.payee(null, '97800011') as avant \gset
select essai.egal(pg_temp.sms(:'avant'), '', 'coupés : aucun SMS pour une commande payée');
select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.refuse($$select public.regler_sms_commandes(true, 3, 300, array['commande_payee'], true, true, true)$$,
  'une boutique ne les allume pas');
select essai.refuse($$select public.sms_commandes_reglages()$$, 'ni ne lit leur réglage');
select essai.refuse($$select public.sms_a_envoyer(1)$$, 'personne ne vide la file depuis l''application');
select essai.refuse($$select public.sms_prevoir('x', 'commande_payee', '')$$, 'ni n''en fabrique');
select essai.refuse($$select * from public.sms_commandes$$, 'ni ne lit le journal (les numéros y sont)');
reset role; select essai.personne();
set role anon;
select essai.refuse($$select public.regler_sms_commandes(true, 3, 300, array['commande_payee'], true, true, true)$$,
  'un visiteur non plus');
reset role;
-- L'adresse de la fonction Edge, posée depuis l'éditeur SQL.
update public.sms_reglages set url = 'https://exemple.essai/functions/v1/envoyer-sms-commande' where id = 1;
select essai.devenir(:SUPER::uuid); set role authenticated;
select essai.refuse($$select public.regler_sms_commandes(true, 11, 300, array['commande_payee'], true, true, true)$$,
  'plus de 10 SMS par commande : refusé');
select essai.refuse($$select public.regler_sms_commandes(true, 3, 300, array['commande_inventee'], true, true, true)$$,
  'une étape inconnue : refusée');
select public.regler_sms_commandes(true, 3, 300,
  array['commande_payee', 'course_acceptee', 'commande_en_livraison', 'commande_remise'], true, true, true) as r \gset
reset role; select essai.personne();
select essai.verifie((:'r'::jsonb ->> 'actif')::boolean and (:'r'::jsonb ->> 'branche')::boolean,
  'le superadministrateur les allume ; la fonction est branchée');
select essai.verifie((select actif_depuis is not null from public.sms_reglages where id = 1), 'allumés « à partir de maintenant »');

-- ---------------------------------------------------------
select essai.titre('3. Une commande sans compte, étape par étape');
select pg_temp.payee(null, '97 80 00 12') as sans_compte \gset
select essai.egal(pg_temp.sms(:'sans_compte'), 'commande_payee:a_envoyer', 'payée : un SMS en attente d''envoi');
select essai.egal((select numero from public.sms_commandes where commande_id = :'sans_compte'), '2290197800012',
  'au bon numéro : un ancien numéro à 8 chiffres prend « 01 », indicatif compris');
select essai.verifie((select texte from public.sms_commandes where commande_id = :'sans_compte')
                       ~ '^BIZZOO : votre commande BZ-[0-9]+ est confirmee', 'le texte dit le numéro de la commande, sans accents');
select pg_temp.etape(:'sans_compte', 'preparee');
select pg_temp.etape(:'sans_compte', '', :LIV::uuid);
select essai.egal(pg_temp.sms(:'sans_compte'), 'commande_payee:a_envoyer,course_acceptee:a_envoyer',
  'le livreur accepte la course : un SMS');
select essai.verifie((select texte from public.sms_commandes where commande_id = :'sans_compte' and etape = 'course_acceptee')
                       like 'BIZZOO : Yao Sena livre votre commande %. Son numero : 0196800009.%',
  'avec son nom (sans accents) et son numéro');
select essai.verifie((select max(length(texte)) from public.sms_commandes where commande_id = :'sans_compte') <= 160,
  'chaque texte tient en un SMS');
select pg_temp.etape(:'sans_compte', 'en_livraison');
select essai.egal(pg_temp.sms(:'sans_compte'),
  'commande_payee:a_envoyer,course_acceptee:a_envoyer,commande_en_livraison:a_envoyer', 'en route : un troisième');
select pg_temp.etape(:'sans_compte', 'remise');
select essai.egal((select etat || '/' || code from public.sms_commandes where commande_id = :'sans_compte' and etape = 'commande_remise'),
  'abandonne/PLAFOND', 'livrée : le plafond de 3 par commande tient — noté, pas envoyé');
select pg_temp.etape(:'sans_compte', 'en_livraison');
select essai.egal((select count(*)::int from public.sms_commandes where commande_id = :'sans_compte' and etape = 'commande_en_livraison'), 1,
  'une étape ne part qu''une fois');

-- ---------------------------------------------------------
select essai.titre('4. Qui reçoit, qui ne reçoit pas');
select pg_temp.payee(:CLI_APP::uuid, '0196800001') as avec_appli \gset
select essai.egal(pg_temp.sms(:'avec_appli'), '', 'un client avec l''application Android : pas de SMS (il a le push)');
select essai.verifie(exists (select 1 from public.notifications where destinataire = :CLI_APP::uuid and commande_id = :'avec_appli'
                                and lien like '#/commande/%'), 'mais sa notification, oui');
select pg_temp.payee(:CLI_WEB::uuid, '96800002') as sans_appli \gset
select essai.egal(pg_temp.sms(:'sans_appli'), 'commande_payee:a_envoyer', 'un client sans l''application (iPhone, navigateur) : un SMS');
select essai.egal(public.sms_numero('00', '229'), null::text, 'un numéro qui n''en est pas un : aucun SMS possible');
select essai.egal(public.sms_numero('+229 01 96 80 00 02', '229'), '2290196800002', 'un numéro déjà international : tel quel');
select essai.egal(public.sms_numero('0612345678', '33'), '330612345678', 'un numéro étranger garde son indicatif');
-- Une commande payée AVANT l'allumage : elle n'existe pas pour les SMS.
update public.sms_reglages set actif_depuis = now() + interval '1 minute' where id = 1;
select pg_temp.etape(:'avant', '', :LIV::uuid);
select essai.egal(pg_temp.sms(:'avant'), '', 'une commande payée avant l''allumage : jamais de SMS');
update public.sms_reglages set actif_depuis = now() - interval '1 hour' where id = 1;
select pg_temp.etape(:'sans_appli', 'annulee');
select essai.egal(pg_temp.sms(:'sans_appli'), 'commande_payee:a_envoyer',
  'une étape que le superadministrateur n''a pas choisie (annulée) : rien');

-- ---------------------------------------------------------
select essai.titre('4 bis. Les cas de bord');
select essai.egal(public.sms_texte('Dɔssou 😀 Séna — « là »'), 'Dossou Sena - " la "',
  'un nom en fon et un émoji : un texte ASCII, qui reste un seul SMS');
-- Un téléphone qui n'a plus ouvert l'application depuis 40 jours : plus « prévenu ».
update public.appareils_push set maj_le = now() - interval '40 days' where jeton = 'jeton-client-android-essai-0001';
select pg_temp.payee(:CLI_APP::uuid, '0196800001') as appli_perdue \gset
select essai.egal(pg_temp.sms(:'appli_perdue'), 'commande_payee:a_envoyer',
  'application pas ouverte depuis 40 jours (désinstallée ?) : le SMS prend le relais');
update public.appareils_push set maj_le = now() where jeton = 'jeton-client-android-essai-0001';
-- Le livreur change, puis revient : un SMS à chaque NOUVEAU livreur.
update public.sms_reglages set plafond = 10 where id = 1;
select pg_temp.payee(null, '97800031') as va_et_vient \gset
select pg_temp.etape(:'va_et_vient', '', :LIV::uuid);
select pg_temp.etape(:'va_et_vient', '', :LIV2::uuid);
select pg_temp.etape(:'va_et_vient', '', :LIV::uuid);
select essai.egal((select string_agg(split_part(texte, ' livre', 1), ' / ' order by id) from public.sms_commandes
                    where commande_id = :'va_et_vient' and etape = 'course_acceptee'),
  'BIZZOO : Yao Sena / BIZZOO : Bio / BIZZOO : Yao Sena', 'Yao, puis Bio après un refus, puis Yao de nouveau : trois SMS justes');
update public.sms_reglages set plafond = 3 where id = 1;
-- Deux boutiques : l'une livre, l'autre annule ensuite. Plus rien n'attend : « livrée ».
select pg_temp.payee2('97800032') as deux \gset
select pg_temp.etape_produit(:'deux', 'prod_rh_stats', 'remise');
select essai.egal((select count(*)::int from public.sms_commandes where commande_id = :'deux' and etape = 'commande_remise'), 0,
  'une boutique a livré, l''autre pas encore : pas encore « livrée »');
select pg_temp.etape_produit(:'deux', 'prod_sms_b', 'annulee');
select essai.egal((select count(*)::int from public.sms_commandes where commande_id = :'deux' and etape = 'commande_remise'), 1,
  'l''autre annule : plus rien n''attend — « livrée »');

-- ---------------------------------------------------------
select essai.titre('5. La file : une fois, et le verdict de la passerelle');
select id as file1 from public.sms_commandes where commande_id = :'sans_appli' and etape = 'commande_payee' \gset
select essai.egal(public.sms_a_envoyer(:'file1'::bigint) ->> 'numero', '2290196800002', 'la fonction Edge le prend');
select essai.egal(public.sms_a_envoyer(:'file1'::bigint), null::jsonb, 'une seconde fois : rien — il ne part pas deux fois');
select public.sms_resultat(:'file1'::bigint, false, 'INJOIGNABLE', 0, 'Passerelle injoignable');
select essai.egal((select etat from public.sms_commandes where id = :'file1'::bigint), 'a_envoyer', 'injoignable : il repartira');
select public.sms_a_envoyer(:'file1'::bigint) as x \gset
select public.sms_resultat(:'file1'::bigint, true, 'SUBMITTED', 200, '');
select essai.egal((select etat || '/' || (envoye_le is not null) from public.sms_commandes where id = :'file1'::bigint), 'envoye/true',
  'accepté par la passerelle : envoyé, et daté');
select id as file2 from public.sms_commandes where commande_id = :'sans_compte' and etape = 'commande_payee' \gset
select public.sms_a_envoyer(:'file2'::bigint) as x \gset
select public.sms_resultat(:'file2'::bigint, false, 'INSUFFICIENT_BALANCE', 200, 'Crédit épuisé pour 2290197800012');
select essai.egal((select etat from public.sms_commandes where id = :'file2'::bigint), 'refuse', 'crédit épuisé : refusé, sans réessai');
update public.sms_commandes set essaye_le = now() - interval '20 minutes', tentatives = 1, etat = 'en_cours'
 where commande_id = :'sans_compte' and etape = 'course_acceptee';
select public.sms_reprendre() as x \gset
select essai.egal((select etat || '/' || code from public.sms_commandes where commande_id = :'sans_compte' and etape = 'course_acceptee'),
  'abandonne/SANS_REPONSE', 'resté « en cours » sans verdict, même au premier essai : JAMAIS renvoyé (il est peut-être parti)');
-- Les verdicts ambigus ne repartent pas ; seuls ceux où rien n'est parti.
select pg_temp.payee(null, '97800041') as v1 \gset
select pg_temp.payee(null, '97800042') as v2 \gset
select pg_temp.payee(null, '97800043') as v3 \gset
select id as l1 from public.sms_commandes where commande_id = :'v1' \gset
select id as l2 from public.sms_commandes where commande_id = :'v2' \gset
select id as l3 from public.sms_commandes where commande_id = :'v3' \gset
select public.sms_a_envoyer(:'l1'::bigint) as x \gset
select public.sms_a_envoyer(:'l2'::bigint) as x \gset
select public.sms_a_envoyer(:'l3'::bigint) as x \gset
select public.sms_resultat(:'l1'::bigint, false, 'DELAI_DEPASSE', 0, 'Pas de réponse en 20 s');
select public.sms_resultat(:'l2'::bigint, false, 'REFUS_SANS_CODE', 200, '<html>');
select public.sms_resultat(:'l3'::bigint, false, 'REFUS_SANS_CODE', 503, 'Indisponible');
select essai.egal((select string_agg(etat, ',' order by id) from public.sms_commandes where id in (:'l1'::bigint, :'l2'::bigint, :'l3'::bigint)),
  'refuse,refuse,a_envoyer', 'délai dépassé, ou 200 sans code : pas renvoyés (peut-être partis) ; 503 : renvoyé');
select essai.devenir(:SUPER::uuid); set role authenticated;
select public.regler_sms_commandes(false, 3, 300, array['commande_payee'], true, true, true) as r \gset
reset role; select essai.personne();
select id as file3 from public.sms_commandes where commande_id = :'sans_compte' and etape = 'commande_en_livraison' \gset
select essai.egal(public.sms_a_envoyer(:'file3'::bigint), null::jsonb, 'coupés entre-temps : rien ne part');
select essai.egal((select code from public.sms_commandes where id = :'file3'::bigint), 'COUPE', 'et c''est noté');

-- ---------------------------------------------------------
select essai.titre('6. Le compteur de BIZZOO Personnel');
select essai.devenir(:SUPER::uuid); set role authenticated;
select public.rh_sms_compteur() as compteur \gset
reset role; select essai.personne();
select essai.verifie((:'compteur'::jsonb #>> '{total,envoyes}')::int >= 1, 'il compte les SMS envoyés');
select essai.verifie((:'compteur'::jsonb #>> '{total,credit_epuise}')::int >= 1, 'et signale le crédit épuisé');
select essai.verifie((:'compteur'::jsonb #>> '{total,plafonnes}')::int >= 1, 'et les SMS retenus par le plafond');
select essai.verifie(:'compteur'::text !~ '2290197800012' and :'compteur'::text !~ '0197800012',
  'sans jamais montrer le numéro d''un client');
select essai.devenir(:MEMBRE::uuid); set role authenticated;
select essai.refuse($$select public.rh_sms_compteur()$$, 'un employé qui ne suit pas les commandes ne le voit pas');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('7. Un téléphone retiré hors ligne, rattrapé à la réouverture');
insert into public.appareils_push (jeton, compte, application) values
  ('jeton-client-a-oublier-00000001', :CLI_WEB::uuid, 'client') on conflict (jeton) do nothing;
set role anon;
select essai.egal(public.oublier_jeton_push('jeton-client-a-oublier-00000001'), true,
  'sans session, avec le seul jeton : le téléphone est retiré');
select essai.egal(public.oublier_jeton_push('jeton-admin-chef-essai-00000001'), false,
  'mais pas un téléphone de BIZZOO Admin');
reset role;
select essai.verifie(exists (select 1 from public.appareils_push where jeton = 'jeton-admin-chef-essai-00000001'),
  'qui est toujours là');

-- Le décor rendu : coupés, sans adresse.
update public.sms_reglages set actif = false, url = '' where id = 1;
delete from public.appareils_push where jeton in ('jeton-client-android-essai-0001', 'jeton-admin-chef-essai-00000001');
