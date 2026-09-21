-- =========================================================
-- Les avis : qui a le droit d'en donner un, et sur quoi.
--
-- Un système d'avis ne vaut que par ce qu'il refuse. S'il
-- accepte n'importe qui, il ne dit plus rien : un concurrent en
-- poste dix mauvais le matin, une boutique s'en écrit vingt
-- bons l'après-midi, et les avis honnêtes se noient avec les
-- autres.
--
-- Quatre portes, et on les force toutes :
--
--   1. SANS ACHAT, PAS D'AVIS ;
--   2. ET L'ACHAT DOIT ÊTRE PAYÉ. C'est la ligne la plus facile
--      à oublier, et celle qui coûte le plus cher : ouvrir une
--      commande ne coûte rien et ne prouve rien ;
--   3. LA BOUTIQUE VIENT DU CATALOGUE. Sans cela, on achète un
--      article à trois francs chez l'un pour aller noter
--      l'autre ;
--   4. LA BOUTIQUE NE SUPPRIME PAS CE QUI LA GÊNE. Elle répond.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set AWA      '''44444444-4444-4444-4444-444444444444'''
\set KOFI     '''55555555-5555-5555-5555-555555555555'''

select essai.titre('Le décor : Awa a payé, Kofi non');

insert into public.produits
  (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_avis', 'bou_informatique', 'Article à noter', 7000,
        'sc_hightech_accessoires', 50, true)
on conflict (id) do update set prix = 7000, stock = 50;

-- Awa achète, et PAIE.
select essai.devenir(:AWA::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Awa","tel":"97111111"}'::jsonb,
  '[{"produit_id":"prod_avis","quantite":1}]'::jsonb) ->> 'id' as payee_awa \gset
reset role;
select essai.personne();
select public.marquer_payee(:'payee_awa', 'TRX-AVIS-1',
  (select total from public.commandes where id = :'payee_awa')) as encaisse \gset
select essai.egal((select etat from public.commandes where id = :'payee_awa'),
  'payee', 'la commande d''Awa est payée');

-- Kofi commande le même article, et ne paie jamais.
select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97222222"}'::jsonb,
  '[{"produit_id":"prod_avis","quantite":1}]'::jsonb) ->> 'id' as ouverte_kofi \gset
reset role;
select essai.personne();
select essai.egal((select etat from public.commandes where id = :'ouverte_kofi'),
  'a_payer', 'celle de Kofi reste à payer');

-- ---------------------------------------------------------
select essai.titre('Sans achat payé, pas d''avis');
-- ---------------------------------------------------------
-- LE CONSTAT LE PLUS IMPORTANT DE CE FICHIER. Kofi a une commande, un
-- vrai compte, et le produit sous les yeux. Il n'a simplement pas payé.
select essai.devenir(:KOFI::uuid);
set role authenticated;
select essai.egal(public.a_achete('prod_avis', 'bou_informatique'), false,
  'une commande OUVERTE ne vaut pas un achat');
select essai.refuse(
  $$select public.deposer_avis('prod_avis', null, 1, 'Nul')$$,
  'il note un produit qu''il n''a pas réglé');
select essai.refuse(
  $$select public.deposer_avis(null, 'bou_informatique', 1, 'Nuls')$$,
  'il note la boutique sans avoir rien réglé chez elle');
reset role;
select essai.personne();

-- Un visiteur non connecté, encore moins.
set role anon;
select essai.refuse(
  $$select public.deposer_avis('prod_avis', null, 5, 'Excellent')$$,
  'un visiteur dépose un avis');
reset role;

-- Et un compte de l'équipe n'est pas un acheteur : il noterait sa
-- propre boutique.
select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.refuse(
  $$select public.deposer_avis('prod_avis', null, 5, 'Très bon produit')$$,
  'le gérant note son propre produit');
reset role;
select essai.personne();

select essai.egal((select count(*)::int from public.avis), 0,
  'aucun avis n''a été déposé');

-- ---------------------------------------------------------
select essai.titre('Qui a payé donne son avis');
-- ---------------------------------------------------------
select essai.devenir(:AWA::uuid);
set role authenticated;

select essai.egal(public.a_achete('prod_avis', 'bou_informatique'), true,
  'Awa a bien acheté');
select public.deposer_avis('prod_avis', null, 4, 'Bon rapport qualité prix') ->> 'id'
  as avis_awa \gset
reset role;
select essai.personne();

select essai.egal((select note from public.avis where id = :'avis_awa'), 4,
  'son avis est déposé');
select essai.egal((select boutique_id from public.avis where id = :'avis_awa'),
  'bou_informatique',
  'et la boutique vient du catalogue, pas de la requête');
select essai.egal((select auteur from public.avis where id = :'avis_awa'), 'Awa',
  'signé de son prénom, et de lui seul');
select essai.verifie(
  (select commande_id is not null from public.avis where id = :'avis_awa'),
  'avec la commande qui le prouve');

-- ---------------------------------------------------------
select essai.titre('La boutique ne vient jamais de la requête');
-- ---------------------------------------------------------
-- Awa a acheté chez « bou_informatique ». Elle tente de noter une autre
-- boutique en la nommant dans sa requête.
insert into public.boutiques (id, nom, secteur, actif, ordre)
values ('bou_voisine', 'Boutique voisine', 'Cosmétiques', true, 9)
on conflict (id) do nothing;

select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.refuse(
  $$select public.deposer_avis(null, 'bou_voisine', 1, 'A eviter')$$,
  'elle note une boutique où elle n''a jamais rien acheté');
-- Et en donnant un produit d'une boutique ET le nom d'une autre : c'est
-- le produit qui décide, la seconde est ignorée.
select public.deposer_avis('prod_avis', 'bou_voisine', 5, 'Parfait') ->> 'id'
  as avis_bis \gset
reset role;
select essai.personne();
select essai.egal((select boutique_id from public.avis where id = :'avis_bis'),
  'bou_informatique',
  'le nom de boutique envoyé est ignoré : c''est le produit qui décide');

-- ---------------------------------------------------------
select essai.titre('Un seul avis par cible, mais on peut changer d''avis');
-- ---------------------------------------------------------
select essai.egal((select count(*)::int from public.avis
                    where client_id = :AWA::uuid and produit_id = 'prod_avis'), 1,
  'toujours un seul avis sur ce produit');
select essai.egal((select note from public.avis
                    where client_id = :AWA::uuid and produit_id = 'prod_avis'), 5,
  'et c''est le dernier qui compte');
select essai.egal(:'avis_awa'::text, :'avis_bis'::text,
  'le même avis, modifié — pas un second');

-- L'avis de boutique est une autre cible : il s'ajoute, il ne remplace pas.
select essai.devenir(:AWA::uuid);
set role authenticated;
select public.deposer_avis(null, 'bou_informatique', 3, 'Livraison lente') ->> 'id'
  as avis_bout \gset
select public.deposer_avis(null, 'bou_informatique', 2, 'Toujours lente') ->> 'id'
  as avis_bout2 \gset
reset role;
select essai.personne();
select essai.egal(:'avis_bout'::text, :'avis_bout2'::text,
  'deux avis de boutique de suite : c''est le même, modifié');
select essai.egal((select count(*)::int from public.avis
                    where client_id = :AWA::uuid), 2,
  'elle a un avis produit et un avis boutique, pas quatre');

-- ---------------------------------------------------------
select essai.titre('Les moyennes suivent, et ne se déclarent pas');
-- ---------------------------------------------------------
select essai.egal((select note_moyenne from public.produits where id = 'prod_avis'),
  5.00::numeric, 'la note du produit suit son avis');
select essai.egal((select nb_avis from public.produits where id = 'prod_avis'), 1,
  'et le compte aussi');
select essai.egal((select note_moyenne from public.boutiques where id = 'bou_informatique'),
  2.00::numeric, 'la note de la boutique suit la sienne');
-- La note d'une boutique n'est PAS la moyenne de ses produits : ce sont
-- deux questions différentes.
select essai.egal((select nb_avis from public.boutiques where id = 'bou_informatique'), 1,
  'et ne compte que les avis qui lui sont adressés');

-- Personne ne les écrit à la main.
select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.refuse(
  $$update public.produits set note_moyenne = 5, nb_avis = 999 where id = 'prod_avis'$$,
  'le gérant s''écrit cinq étoiles');
reset role;
select essai.personne();
select essai.egal((select nb_avis from public.produits where id = 'prod_avis'), 1,
  'la note n''a pas bougé');

-- ---------------------------------------------------------
select essai.titre('On n''écrit pas dans la table, et pas celui d''un autre');
-- ---------------------------------------------------------
select essai.devenir(:KOFI::uuid);
set role authenticated;
select essai.refuse(
  $$insert into public.avis (id, client_id, produit_id, boutique_id, note)
    values ('avi_triche', '55555555-5555-5555-5555-555555555555',
            'prod_avis', 'bou_informatique', 5)$$,
  'il écrit directement dans la table');
select essai.refuse(
  format($$update public.avis set note = 1 where id = %L$$, :'avis_awa'),
  'il abaisse la note d''Awa');
select essai.refuse(
  format($$delete from public.avis where id = %L$$, :'avis_awa'),
  'il efface l''avis d''Awa');
select essai.egal(public.retirer_mon_avis(:'avis_awa'), false,
  'et la fonction de retrait ne retire que le sien');
reset role;
select essai.personne();
select essai.egal((select count(*)::int from public.avis where id = :'avis_awa'), 1,
  'l''avis d''Awa est toujours là');

-- ---------------------------------------------------------
select essai.titre('La boutique répond, elle n''efface pas');
-- ---------------------------------------------------------
select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.refuse(
  format($$delete from public.avis where id = %L$$, :'avis_bout'),
  'la boutique efface l''avis qui la gêne');
select essai.refuse(
  format($$select public.masquer_avis(%L, true, 'ça me dérange')$$, :'avis_bout'),
  'elle le masque elle-même');
select essai.egal(public.repondre_avis(:'avis_bout', 'Désolés, nous corrigeons.'), true,
  'mais elle répond');
reset role;
select essai.personne();

select essai.egal((select reponse from public.avis where id = :'avis_bout'),
  'Désolés, nous corrigeons.', 'et sa réponse est publique');
select essai.verifie((select reponse_le is not null from public.avis where id = :'avis_bout'),
  'datée');

-- Une boutique ne répond pas pour une autre.
insert into auth.users (id, email) values
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'chef-voisine@bizzoo.bj')
on conflict do nothing;
insert into public.profils (id, email, role, actif, boutique_id)
values ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'chef-voisine@bizzoo.bj',
        'administrateur', true, 'bou_voisine')
on conflict (id) do update set boutique_id = 'bou_voisine', actif = true;

select essai.devenir('cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid);
set role authenticated;
select essai.refuse(
  format($$select public.repondre_avis(%L, 'Ce n''est pas nous')$$, :'avis_bout'),
  'la boutique voisine répond à un avis qui ne la concerne pas');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Masquer est réservé à l''enseigne, et fait remonter la note');
-- ---------------------------------------------------------
select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.refuse(
  format($$select public.masquer_avis(%L, true, '')$$, :'avis_bout'),
  'une cliente masque un avis');
reset role;

select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.egal(public.masquer_avis(:'avis_bout', true, 'Insultes'), true,
  'l''enseigne masque un avis qui n''a pas sa place');
reset role;
select essai.personne();

select essai.egal((select nb_avis from public.boutiques where id = 'bou_informatique'), 0,
  'un avis masqué ne compte plus dans la moyenne');
select essai.egal((select note_moyenne from public.boutiques where id = 'bou_informatique'),
  null::numeric, 'et la note redevient vide quand il n''en reste aucun');

-- Et il disparaît pour le public, pas pour l'équipe qui doit pouvoir
-- vérifier ce qu'elle a masqué.
set role anon;
select essai.egal((select count(*)::int from public.avis where id = :'avis_bout'), 0,
  'un visiteur ne voit plus l''avis masqué');
reset role;
select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.avis where id = :'avis_bout'), 1,
  'la boutique concernée le voit encore');
reset role;
select essai.personne();

-- Le démasquer le rend au public, et à la moyenne.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.egal(public.masquer_avis(:'avis_bout', false, ''), true, 'l''enseigne le rend');
reset role;
select essai.personne();
select essai.egal((select nb_avis from public.boutiques where id = 'bou_informatique'), 1,
  'et il recompte');

-- ---------------------------------------------------------
select essai.titre('Les avis sont publics : c''est tout leur intérêt');
-- ---------------------------------------------------------
set role anon;
select essai.verifie((select count(*) from public.avis) >= 2,
  'un visiteur lit les avis sans compte');
select essai.egal((select auteur from public.avis where id = :'avis_awa'), 'Awa',
  'avec le prénom de qui les a écrits');
-- Mais rien de plus : pas de quoi retrouver la personne. Zéro ligne,
-- et non une erreur : c'est ainsi qu'une règle RLS refuse, en silence.
select essai.egal((select count(*)::int from public.clients), 0,
  'et rien de la fiche du client — ni son nom, ni son numéro');
reset role;

-- Une note que le client retire disparaît de la moyenne.
select essai.devenir(:AWA::uuid);
set role authenticated;
select essai.egal(public.retirer_mon_avis(:'avis_awa'), true, 'Awa retire son avis produit');
reset role;
select essai.personne();
select essai.egal((select nb_avis from public.produits where id = 'prod_avis'), 0,
  'et le produit n''a plus d''avis');
select essai.egal((select note_moyenne from public.produits where id = 'prod_avis'),
  null::numeric, 'ni de note');
