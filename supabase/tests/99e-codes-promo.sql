-- =========================================================
-- Les codes promo : qui paie, et ce qui ne se laisse pas
-- forcer.
--
-- UNE REMISE SORT DE LA MARGE DE L'ENSEIGNE. La boutique
-- touche son prix BIZZOO en entier : elle n'a pas décidé
-- cette promotion, elle n'a pas à la payer. Tout le reste
-- découle de là.
--
-- Six choses à prouver :
--
--   1. LA BOUTIQUE NE PAIE RIEN. Son prix BIZZOO figé sur la
--      ligne ne bouge pas d'un franc, code ou pas ;
--   2. LE PLAFOND TIENT. Une remise ne descend JAMAIS en
--      dessous de ce que les boutiques doivent toucher —
--      sinon l'enseigne paierait de sa poche à chaque vente,
--      sans que personne le voie avant les comptes ;
--   3. L'ÉCRAN ET LA CAISSE DISENT LE MÊME MONTANT. Une seule
--      règle, appelée par les deux. Deux calculs finiraient
--      par diverger, et le client paierait autre chose que ce
--      qu'on lui a montré ;
--   4. LES LIMITES SE TIENNENT : échéance, nombre, une fois
--      par client, montant minimum ;
--   5. UN CODE REFUSÉ NE TUE PAS LA COMMANDE. Le panier est
--      bon ; c'est le code qui ne vaut rien ;
--   6. PERSONNE NE SE POSE UN CODE. Ni un client, ni une
--      boutique.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set KOFI     '''55555555-5555-5555-5555-555555555555'''

select essai.titre('Le décor : un article dont on connaît toute la marge');

-- Prix public 10 000, prix BIZZOO 6 000 : l'enseigne garde 4 000 par
-- unité. Chaque chiffre de ce fichier se relit de tête.
insert into public.produits
  (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_promo', 'bou_informatique', 'Clavier mécanique', 10000,
        'sc_hightech_accessoires', 99, true)
on conflict (id) do update
   set prix = 10000, stock = 99, disponible = true;
insert into public.produits_prive (produit_id, prix_grossiste)
values ('prod_promo', 6000)
on conflict (produit_id) do update set prix_grossiste = 6000;

select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select public.enregistrer_code('BIENVENUE10', 'Dix pour cent', 'pourcent', 10,
  0, 0, false, null::date, true) as c1 \gset
select essai.egal(:'c1'::text, 'BIENVENUE10', 'le code est posé');
-- Un code se tape comme on veut : la base le normalise.
select essai.egal(public.code_normalise('  bien-venue 10 '), 'BIENVENUE10',
  'et « bien-venue 10 » désigne le même');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('L''écran annonce, la caisse applique — le même montant');
-- ---------------------------------------------------------
-- Deux claviers : 20 000 de panier, 8 000 de marge pour l'enseigne.
-- 10 % font 2 000, bien en dessous du plafond.
set role anon;
select public.verifier_code('BIENVENUE10',
  '[{"produit_id":"prod_promo","quantite":2}]'::jsonb) as apercu \gset
reset role;
select essai.verifie((:'apercu'::jsonb ->> 'ok')::boolean, 'le panier accepte le code');
select essai.egal((:'apercu'::jsonb ->> 'remise')::int, 2000,
  'et annonce 2 000 de remise');

select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97222222"}'::jsonb,
  '[{"produit_id":"prod_promo","quantite":2}]'::jsonb,
  'BIENVENUE10') as vente \gset
reset role;
select essai.personne();

select essai.egal((:'vente'::jsonb ->> 'remise')::int, 2000,
  'la caisse retire exactement le même montant');
select essai.egal((:'vente'::jsonb ->> 'total')::int, 18000,
  'et le total tombe à 18 000');
select essai.egal((:'vente'::jsonb ->> 'code_promo'), 'BIENVENUE10',
  'le récapitulatif dit quel code a servi');

-- ---------------------------------------------------------
select essai.titre('LA BOUTIQUE NE PAIE RIEN');
-- ---------------------------------------------------------
-- LE CONSTAT DE CE FICHIER. Le prix et le prix BIZZOO figés sur la
-- ligne ne bougent pas : la remise est sur la COMMANDE. Toucher aux
-- lignes ferait payer à la boutique une promotion qu'elle n'a pas
-- décidée — et elle ne s'en apercevrait qu'en comptant.
\set v '''' :vente ''''
select id as cmd from public.commandes
 where id = (:'vente'::jsonb ->> 'id') \gset
select essai.egal((select prix from public.commande_lignes
                    where commande_id = :'cmd'), 10000,
  'le prix de vente figé sur la ligne ne bouge pas');
select essai.egal((select prix_bizzoo from public.commande_lignes
                    where commande_id = :'cmd'), 6000,
  'et le prix BIZZOO de la boutique non plus');
select essai.egal((select sum(prix_bizzoo * quantite)::int
                     from public.commande_lignes where commande_id = :'cmd'), 12000,
  'la boutique touche ses 12 000 en entier');

-- ET CE N'EST PAS QU'UNE QUESTION DE BONNE VOLONTÉ. Même avec le drapeau
-- interne de la base — celui dont « creer_commande » se sert pour écrire
-- le total — une ligne vendue refuse de se laisser réécrire. Une future
-- version qui voudrait faire payer la boutique se heurterait au verrou,
-- pas à un oubli. C'est le banc qui l'a montré : le sabotage qui rognait
-- les lignes n'a pas produit de faux chiffres, il a été refusé.
select essai.refuse(
  $q$do $x$ begin
      perform set_config('bizzoo.interne', 'oui', true);
      update public.commande_lignes set prix_bizzoo = prix_bizzoo - 1000
       where prix_bizzoo > 0;
    end $x$;$q$,
  'la base réécrit le prix BIZZOO d''une ligne vendue');

-- Et ses statistiques à elle ne voient rien de la remise.
select public.marquer_payee(:'cmd', 'TRX-PROMO-1',
  (select total from public.commandes where id = :'cmd'), 'feexpay') as e1 \gset
select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.egal((select total_bizzoo from public.statistiques_boutique()
                    where produit_id = 'prod_promo'), 12000::bigint,
  'ses chiffres portent 12 000, remise ou pas');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Mais VOS comptes, eux, la voient');
-- ---------------------------------------------------------
-- LE PIÈGE. Le bénéfice se calcule ligne par ligne ; la remise est sur
-- la commande. Sans « remises_periode », le bénéfice affiché serait
-- surévalué de toutes les remises accordées.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.egal((select remise from public.remises_periode()
                    where boutique_id = 'bou_informatique'), 2000::bigint,
  'la remise est imputée à la boutique concernée');
-- Le bénéfice brut des lignes, lui, ignore la remise — c'est justement
-- pour cela qu'il faut la retrancher à l'écran.
select essai.verifie(
  (select coalesce(sum(benefice), 0) >= 8000 from public.statistiques_ventes()
    where produit_id = 'prod_promo'),
  'le bénéfice des lignes vaut bien 8 000 avant remise');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('LE PLAFOND : la remise ne mange pas la boutique');
-- ---------------------------------------------------------
-- Un code de 80 % sur un article qui ne laisse que 40 % de marge.
-- Sans plafond, l'enseigne paierait la différence de sa poche.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select public.enregistrer_code('GROSSE80', 'Quatre-vingts pour cent', 'pourcent', 80,
  0, 0, false, null::date, true);
reset role;
select essai.personne();

set role anon;
select public.verifier_code('GROSSE80',
  '[{"produit_id":"prod_promo","quantite":1}]'::jsonb) as gros \gset
reset role;
-- 80 % de 10 000 font 8 000. La marge n'est que de 4 000 : on rabote.
select essai.egal((:'gros'::jsonb ->> 'remise')::int, 4000,
  'la remise est ramenée à la marge de l''enseigne : 4 000, pas 8 000');

select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97222299"}'::jsonb,
  '[{"produit_id":"prod_promo","quantite":1}]'::jsonb,
  'GROSSE80') as grosse \gset
reset role;
select essai.personne();
select id as cmd2 from public.commandes where id = (:'grosse'::jsonb ->> 'id') \gset

select essai.egal((:'grosse'::jsonb ->> 'remise')::int, 4000,
  'la caisse rabote pareil');
select essai.egal((:'grosse'::jsonb ->> 'total')::int, 6000,
  'le client paie 6 000');
-- ET VOICI POURQUOI : ce que le client paie couvre exactement ce que la
-- boutique doit toucher. Pas un franc de moins.
select essai.egal((select sum(prix_bizzoo * quantite)::int
                     from public.commande_lignes where commande_id = :'cmd2'), 6000,
  'et la boutique touche ses 6 000 : le client couvre son dû à l''unité près');

-- ---------------------------------------------------------
select essai.titre('Les limites tiennent');
-- ---------------------------------------------------------
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select public.enregistrer_code('EXPIRE', 'Périmé', 'montant', 1000,
  0, 0, false, current_date - 1, true);
select public.enregistrer_code('GROSPANIER', 'Dès 50 000', 'montant', 5000,
  50000, 0, false, null::date, true);
select public.enregistrer_code('FERME', 'Fermé à la main', 'montant', 1000,
  0, 0, false, null::date, false);
reset role;
select essai.personne();

set role anon;
select public.verifier_code('EXPIRE',
  '[{"produit_id":"prod_promo","quantite":1}]'::jsonb) as x1 \gset
select public.verifier_code('GROSPANIER',
  '[{"produit_id":"prod_promo","quantite":1}]'::jsonb) as x2 \gset
select public.verifier_code('FERME',
  '[{"produit_id":"prod_promo","quantite":1}]'::jsonb) as x3 \gset
select public.verifier_code('JAMAISVU',
  '[{"produit_id":"prod_promo","quantite":1}]'::jsonb) as x4 \gset
reset role;

select essai.verifie(not (:'x1'::jsonb ->> 'ok')::boolean, 'un code expiré est refusé');
select essai.verifie((:'x1'::jsonb ->> 'raison') like '%expiré%',
  'et on dit depuis quand');
select essai.verifie(not (:'x2'::jsonb ->> 'ok')::boolean,
  'un panier sous le minimum est refusé');
select essai.verifie((:'x2'::jsonb ->> 'raison') like '%50000%',
  'et on dit à partir de combien');
select essai.verifie(not (:'x3'::jsonb ->> 'ok')::boolean, 'un code fermé est refusé');
-- LE MÊME REFUS pour « fermé » et « inconnu » : distinguer les deux
-- dirait à qui essaie des codes au hasard lesquels ont existé.
select essai.egal((:'x3'::jsonb ->> 'raison'), (:'x4'::jsonb ->> 'raison'),
  'et un code fermé se refuse comme un code inconnu — mot pour mot');

-- ---------------------------------------------------------
select essai.titre('Une seule fois par client');
-- ---------------------------------------------------------
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select public.enregistrer_code('UNEFOIS', 'Une seule fois', 'montant', 1000,
  0, 0, true, null::date, true);
reset role;
select essai.personne();

select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97222222"}'::jsonb,
  '[{"produit_id":"prod_promo","quantite":1}]'::jsonb, 'UNEFOIS') as u1 \gset
reset role;
select essai.personne();
select essai.egal((:'u1'::jsonb ->> 'remise')::int, 1000,
  'la première fois, le code passe');

-- Tant que ce n'est pas PAYÉ, cela ne compte pas : un panier abandonné
-- ne doit pas brûler le droit d'un vrai client.
select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97222222"}'::jsonb,
  '[{"produit_id":"prod_promo","quantite":1}]'::jsonb, 'UNEFOIS') as u2 \gset
reset role;
select essai.personne();
select essai.egal((:'u2'::jsonb ->> 'remise')::int, 1000,
  'un panier non payé ne brûle pas son droit');

-- On paie la première. Maintenant, c'est fini.
select public.marquer_payee((:'u1'::jsonb ->> 'id'), 'TRX-UNEFOIS',
  (:'u1'::jsonb ->> 'total')::int, 'feexpay') as e2 \gset
select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97222222"}'::jsonb,
  '[{"produit_id":"prod_promo","quantite":1}]'::jsonb, 'UNEFOIS') as u3 \gset
reset role;
select essai.personne();
select essai.egal((:'u3'::jsonb ->> 'remise')::int, 0,
  'une fois payée, le même client ne l''a plus');
-- MAIS LA COMMANDE PASSE QUAND MÊME. Le panier est bon ; c'est le code
-- qui ne vaut rien. Refuser la vente pour une ristourne perdrait un
-- client.
select essai.egal((:'u3'::jsonb ->> 'total')::int, 10000,
  'et la commande passe quand même, à plein tarif');

-- ---------------------------------------------------------
select essai.titre('Le nombre d''utilisations se compte sur les payées');
-- ---------------------------------------------------------
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select public.enregistrer_code('LESDEUX', 'Les deux premiers', 'montant', 500,
  0, 2, false, null::date, true);
reset role;
select essai.personne();

select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97000001"}'::jsonb,
  '[{"produit_id":"prod_promo","quantite":1}]'::jsonb, 'LESDEUX') as d1 \gset
select public.creer_commande('{"nom":"Kofi","tel":"97000002"}'::jsonb,
  '[{"produit_id":"prod_promo","quantite":1}]'::jsonb, 'LESDEUX') as d2 \gset
reset role;
select essai.personne();
select public.marquer_payee((:'d1'::jsonb ->> 'id'), 'TRX-D1',
  (:'d1'::jsonb ->> 'total')::int, 'feexpay') as e3 \gset
select public.marquer_payee((:'d2'::jsonb ->> 'id'), 'TRX-D2',
  (:'d2'::jsonb ->> 'total')::int, 'feexpay') as e4 \gset

set role anon;
select public.verifier_code('LESDEUX',
  '[{"produit_id":"prod_promo","quantite":1}]'::jsonb) as d3 \gset
reset role;
select essai.verifie(not (:'d3'::jsonb ->> 'ok')::boolean,
  'après deux commandes payées, le code se ferme');
select essai.verifie((:'d3'::jsonb ->> 'raison') like '%utilisations%',
  'et on dit pourquoi');

-- ---------------------------------------------------------
select essai.titre('Personne ne se pose un code');
-- ---------------------------------------------------------
select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.refuse(
  $$select public.enregistrer_code('CADEAU', 'x', 'montant', 9999, 0, 0, false, null::date, true)$$,
  'un chef de boutique pose un code');
select essai.refuse(
  $$insert into public.codes_promo (code, mode, valeur) values ('TRICHE', 'montant', 9999)$$,
  'ou l''écrit directement dans la table');
select essai.egal((select count(*)::int from public.codes_promo_liste()), 0,
  'et il ne lit même pas la liste');
reset role;
select essai.personne();

select essai.devenir(:KOFI::uuid);
set role authenticated;
select essai.refuse(
  $$insert into public.codes_promo (code, mode, valeur) values ('MOI', 'montant', 9999)$$,
  'un client s''écrit un code');
select essai.egal((select count(*)::int from public.codes_promo), 0,
  'et ne lit pas la table des codes : il y trouverait tout ce qui existe');
reset role;
select essai.personne();

set role anon;
select essai.refuse($$select count(*) from public.codes_promo$$,
  'un visiteur lit la table des codes');
select essai.refuse($$select count(*) from public.codes_promo_liste()$$,
  'ou passe par la liste de l''enseigne');
select essai.refuse(
  $$select public.remise_du_code('BIENVENUE10', 100000, 100000, null, '')$$,
  'ou appelle la règle directement, avec la marge qu''il veut');
reset role;

-- ---------------------------------------------------------
select essai.titre('L''enseigne suit ce que ses codes lui coûtent');
-- ---------------------------------------------------------
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.egal((select utilisations from public.codes_promo_liste()
                    where code = 'LESDEUX'), 2::bigint,
  'deux commandes payées au compteur');
select essai.egal((select coute from public.codes_promo_liste()
                    where code = 'LESDEUX'), 1000::bigint,
  'et ce qu''elles ont coûté : 2 × 500');
select essai.egal((select utilisations from public.codes_promo_liste()
                    where code = 'GROSSE80'), 0::bigint,
  'un code jamais payé n''a rien coûté');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Un code ne dérègle pas ce qui existait');
-- ---------------------------------------------------------
-- Une commande SANS code doit valoir exactement ce qu'elle valait avant
-- que les codes existent.
select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97222222"}'::jsonb,
  '[{"produit_id":"prod_promo","quantite":3}]'::jsonb) as sans \gset
reset role;
select essai.personne();
select essai.egal((:'sans'::jsonb ->> 'total')::int, 30000,
  'sans code, le total est la somme des lignes');
select essai.egal((:'sans'::jsonb ->> 'remise')::int, 0, 'et la remise est nulle');
select essai.egal((:'sans'::jsonb ->> 'code_promo'), '', 'sans code inscrit');
