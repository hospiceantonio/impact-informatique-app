-- =========================================================
-- L'heure de chaque étape d'une commande (4.1.0)
--
-- Ce qu'on prouve :
--   1. « Commande reçue » prend l'heure du paiement ; une étape prend
--      l'heure où la DERNIÈRE ligne de la boutique l'a atteinte ;
--   2. une ligne qui saute une étape la franchit au même moment ; une
--      étape qu'une ligne n'a pas atteinte n'a pas d'heure ;
--   3. une ligne annulée ne retient rien ;
--   4. le client lit les heures avec sa commande ; un autre client, non ;
--      un visiteur n'appelle ni la colonne ni la fonction interne ;
--   5. sans compte : le numéro et le bon téléphone, sinon rien.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set AUTRE    '''cdcdcdcd-4100-0000-0000-000000000001'''

select essai.titre('Le décor : une commande payée, deux lignes de la même boutique');
insert into public.boutiques (id, nom, secteur, devise, actif, ordre, categorie_id)
values ('bou_het', 'BOUTIQUE HEURES', 'Essai', 'FCFA', true, 97, 'cat_hightech') on conflict (id) do nothing;
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_het_a', 'bou_het', 'Riz', 3500, 'sc_hightech_accessoires', 50, true),
       ('prod_het_b', 'bou_het', 'Huile', 1200, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true, masque = false;
insert into public.produits_prive (produit_id, prix_grossiste) values ('prod_het_a', 3000), ('prod_het_b', 1000)
on conflict (produit_id) do nothing;
insert into auth.users (id, email) values (:AUTRE::uuid, 'autre.client@essai.bj') on conflict do nothing;

select essai.devenir(:ACHETEUR::uuid);
set role authenticated;
select public.creer_commande(jsonb_build_object('nom', 'Ablawa', 'tel', '97666088', 'adresse', 'Gbégamey'),
  '[{"produit_id":"prod_het_a","quantite":1},{"produit_id":"prod_het_b","quantite":2}]'::jsonb, '', true, true) as g \gset
reset role;
select essai.personne();
select :'g'::jsonb ->> 'id' as c1 \gset
select public.marquer_payee(:'c1', 'TRX-HET-1', (:'g'::jsonb ->> 'acompte')::int, 'feexpay') as x \gset
select (select id from public.commande_lignes where commande_id = :'c1' and produit_id = 'prod_het_a') as la \gset
select (select id from public.commande_lignes where commande_id = :'c1' and produit_id = 'prod_het_b') as lb \gset
select (select client_tel from public.commandes where id = :'c1') as tel \gset

-- Les étapes franchies, puis leurs heures posées à la main dans le
-- journal : le déclencheur écrit l'heure du moment, toutes à la même
-- seconde ou presque.
update public.commande_lignes set etat = 'vue' where id = :'la';
update public.commande_lignes set etat = 'vue' where id = :'lb';
update public.commande_lignes set etat = 'en_livraison' where id = :'la';
update public.rh_journal_lignes set le = '2026-11-12 09:40:00+00'
 where ligne_id = :'la' and quoi = 'etat' and valeur = 'vue';
update public.rh_journal_lignes set le = '2026-11-12 09:42:00+00'
 where ligne_id = :'lb' and quoi = 'etat' and valeur = 'vue';
update public.rh_journal_lignes set le = '2026-11-12 09:58:00+00'
 where ligne_id = :'la' and quoi = 'etat' and valeur = 'en_livraison';
select public.heures_etapes_commande(:'c1') -> 'bou_het' as h \gset

select essai.titre('1. Reçue à l''heure du paiement, vue quand la dernière ligne l''a été');
select essai.verifie((:'h'::jsonb ->> 'nouvelle')::timestamptz =
                     (select paye_le from public.commandes where id = :'c1'), 'reçue : l''heure du paiement');
select essai.egal((:'h'::jsonb ->> 'vue')::timestamptz, '2026-11-12 09:42:00+00'::timestamptz,
  'vue : 09:42, l''heure de la seconde ligne, pas 09:40');

select essai.titre('2. Une étape sautée, une étape pas atteinte');
select essai.verifie(not (:'h'::jsonb ? 'preparee'), 'préparée : pas d''heure, une ligne ne l''est pas encore');
select essai.verifie(not (:'h'::jsonb ? 'en_livraison') and not (:'h'::jsonb ? 'remise'),
  'en livraison, remise : pas d''heure');
update public.commande_lignes set etat = 'preparee' where id = :'lb';
update public.rh_journal_lignes set le = '2026-11-12 09:50:00+00'
 where ligne_id = :'lb' and quoi = 'etat' and valeur = 'preparee';
select public.heures_etapes_commande(:'c1') -> 'bou_het' as h \gset
select essai.egal((:'h'::jsonb ->> 'preparee')::timestamptz, '2026-11-12 09:58:00+00'::timestamptz,
  'préparée : 09:58 — la première ligne l''a franchie en passant directement en livraison');

select essai.titre('3. Une ligne annulée ne retient rien');
update public.commande_lignes set etat = 'annulee' where id = :'lb';
select public.heures_etapes_commande(:'c1') -> 'bou_het' as h \gset
select essai.egal((:'h'::jsonb ->> 'en_livraison')::timestamptz, '2026-11-12 09:58:00+00'::timestamptz,
  'la seconde ligne annulée : en livraison à 09:58, l''heure de la seule ligne qui reste');
select essai.egal((:'h'::jsonb ->> 'vue')::timestamptz, '2026-11-12 09:40:00+00'::timestamptz,
  'et vue à 09:40');

select essai.titre('4. Le client les lit avec sa commande ; personne d''autre');
select essai.devenir(:ACHETEUR::uuid);
set role authenticated;
select essai.verifie((select public.heures_etapes(c) -> 'bou_het' ? 'en_livraison'
                        from public.commandes c where c.id = :'c1'), 'le client de la commande : ses heures');
reset role;
select essai.personne();
select essai.devenir(:AUTRE::uuid);
set role authenticated;
select essai.verifie((select public.heures_etapes(c) from public.commandes c where c.id = :'c1') is null,
  'un autre client : rien');
select essai.refuse($$select public.heures_etapes_commande('x')$$, 'la fonction interne : fermée aux comptes');
reset role;
select essai.personne();
set role anon;
select essai.refuse($$select public.heures_etapes_commande('x')$$, 'et aux visiteurs');
select essai.refuse($$select public.heures_etapes(c) from public.commandes c limit 1$$,
  'un visiteur ne lit pas la colonne');

select essai.titre('5. Sans compte : le numéro et le bon téléphone');
select essai.verifie(public.heures_etapes_suivies(:'c1', :'tel') -> 'bou_het' ? 'vue',
  'le bon numéro de téléphone : les heures');
select essai.verifie(public.heures_etapes_suivies(:'c1', '0100000000') is null, 'un autre téléphone : rien');
select essai.verifie(public.heures_etapes_suivies('CMD-INCONNUE', :'tel') is null, 'une autre commande : rien');
reset role;
