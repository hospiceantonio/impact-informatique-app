-- =========================================================
-- Ce que le client garde pour lui
--
-- Favoris, boutiques suivies, adresses de livraison. Trois
-- tables qui ne disent pas ce qu'on a acheté, mais ce qu'on
-- a REGARDÉ et où l'on habite. Une fuite y coûte plus cher
-- qu'ailleurs : un panier abandonné se rattrape, une adresse
-- de domicile lue par un inconnu, non.
--
-- Cinq choses à prouver :
--
--   1. CHACUN NE LIT QUE LES SIENS. Ni les favoris d'un
--      autre, ni ses boutiques suivies, ni ses adresses ;
--   2. CHACUN N'ÉCRIT QU'À SON NOM. Poser un favori au nom
--      d'un tiers doit être refusé — une liste qu'un autre
--      peut garnir ne vaut plus rien ;
--   3. L'ENSEIGNE NON PLUS. C'est le point qui distingue ces
--      tables de presque toutes les autres : « est_super() »
--      n'ouvre aucune de ces portes. Si ce constat tombe un
--      jour, c'est qu'on a ouvert cette porte sans le dire ;
--   4. UNE SEULE ADRESSE PAR DÉFAUT, garantie par la base et
--      non par l'application. Deux adresses par défaut, c'est
--      un colis chez la mauvaise ;
--   5. LE CLASSEMENT NE REND QUE L'ORDRE. Jamais un chiffre
--      de vente : ce serait livrer à chaque commerçant le
--      carnet de commandes de son voisin.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

-- Deux clients, et un compte d'enseigne. « AUTRE » est là pour une
-- seule raison : sans un second client, « chacun ne lit que les
-- siens » ne veut rien dire — on ne prouve rien en ne lisant que ce
-- qu'on a soi-même écrit.
\set MOI    '''cc111111-1111-1111-1111-111111111111'''
\set AUTRE  '''cc222222-2222-2222-2222-222222222222'''
\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''

select essai.titre('Le décor : deux clients, chacun ses affaires');

-- Les comptes d'authentification d'abord : « clients » référence
-- auth.users, et une clé étrangère ne se contourne pas.
insert into auth.users (id, email)
values (:MOI::uuid,   'moi@essai.bj'),
       (:AUTRE::uuid, 'autre@essai.bj')
on conflict (id) do nothing;

insert into public.clients (id, nom, tel, indicatif)
values (:MOI::uuid,   'MOI',   '97000001', '229'),
       (:AUTRE::uuid, 'AUTRE', '97000002', '229')
on conflict (id) do nothing;

select essai.verifie(
  (select count(*) from public.clients where id in (:MOI::uuid, :AUTRE::uuid)) = 2,
  'les deux clients existent');

-- ---------------------------------------------------------
select essai.titre('Chacun met de côté ce qu''il veut');

select essai.devenir(:MOI::uuid);
set role authenticated;
insert into public.favoris (client_id, produit_id)
values (:MOI::uuid, 'prod_hp15') on conflict do nothing;
insert into public.boutiques_suivies (client_id, boutique_id)
values (:MOI::uuid, 'bou_informatique') on conflict do nothing;

select essai.egal(
  (select count(*)::int from public.favoris), 1,
  'le client voit le produit qu''il vient de mettre de côté');
select essai.egal(
  (select count(*)::int from public.boutiques_suivies), 1,
  'et la boutique qu''il suit');

select essai.devenir(:AUTRE::uuid);
set role authenticated;
insert into public.favoris (client_id, produit_id)
values (:AUTRE::uuid, 'prod_epson_l3250') on conflict do nothing;

-- ---------------------------------------------------------
select essai.titre('MAIS PERSONNE NE LIT CEUX D''UN AUTRE');

-- Le cœur de l'affaire. « AUTRE » est connecté et a UN favori à lui ;
-- s'il en voit deux, il voit celui de MOI.
select essai.egal(
  (select count(*)::int from public.favoris), 1,
  'un client ne voit que ses propres favoris');
select essai.egal(
  (select count(*)::int from public.favoris where client_id = :MOI::uuid), 0,
  'et rien de ceux du voisin, même en le nommant');
select essai.egal(
  (select count(*)::int from public.boutiques_suivies), 0,
  'il ne voit pas non plus les boutiques que l''autre suit');

-- ---------------------------------------------------------
select essai.titre('Et personne n''écrit au nom d''un autre');

-- Sans « with check », cette ligne passerait : RLS filtre ce qu'on
-- LIT, elle n'empêche pas d'écrire une ligne qu'on ne pourra pas
-- relire. Le favori serait bien posé chez MOI, par AUTRE.
select essai.refuse(
  'insert into public.favoris (client_id, produit_id)
   values (' || quote_literal(:MOI) || '::uuid, ''prod_apc650'')',
  'poser un favori au nom d''un autre');
select essai.refuse(
  'insert into public.boutiques_suivies (client_id, boutique_id)
   values (' || quote_literal(:MOI) || '::uuid, ''bou_informatique'')',
  'suivre une boutique au nom d''un autre');

-- Effacer ne lève pas : RLS écarte la ligne, et zéro ligne touchée.
select essai.sans_effet(
  'delete from public.favoris where client_id = ' || quote_literal(:MOI) || '::uuid',
  'effacer le favori d''un autre');

select essai.devenir(:MOI::uuid);
set role authenticated;
select essai.egal(
  (select count(*)::int from public.favoris), 1,
  'le favori du premier client est toujours là, intact');

-- ---------------------------------------------------------
select essai.titre('L''ENSEIGNE NON PLUS — et c''est voulu');

-- Presque toutes les tables de ce projet s'ouvrent au
-- superadministrateur. Ces trois-là, non. Le jour où ce constat
-- tombe, c'est qu'on a ouvert la porte — et il vaut mieux que ce
-- soit ici qu'on l'apprenne.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.verifie(public.est_super(), 'le compte est bien celui de l''enseigne');
select essai.egal(
  (select count(*)::int from public.favoris), 0,
  'le superadministrateur ne lit AUCUN favori');
select essai.egal(
  (select count(*)::int from public.boutiques_suivies), 0,
  'ni aucune boutique suivie');

-- ---------------------------------------------------------
select essai.titre('Un visiteur sans compte ne voit rien du tout');

reset role;
select essai.personne();
set role anon;
-- Les règles portent « to authenticated » : un visiteur n'en a
-- aucune, et le « revoke » lui retire jusqu'au droit de lire.
select essai.refuse(
  'select count(*) from public.favoris',
  'un visiteur lit les favoris');
select essai.refuse(
  'select count(*) from public.adresses',
  'un visiteur lit les adresses');

-- ---------------------------------------------------------
select essai.titre('Les adresses : une seule par défaut');

select essai.devenir(:MOI::uuid);
set role authenticated;
insert into public.adresses (id, client_id, libelle, texte, ville, par_defaut)
values ('adr_maison', :MOI::uuid, 'Maison', 'Carré 1242, Akpakpa', 'Cotonou', true)
on conflict (id) do nothing;
select essai.egal(
  (select count(*)::int from public.adresses where par_defaut), 1,
  'la première adresse est celle par défaut');

-- LE DÉCLENCHEUR, ET CE QU'IL ÉVITE. Sans lui, cette ligne se
-- heurterait à l'index unique et le client verrait une erreur de
-- base de données pour avoir coché une case.
insert into public.adresses (id, client_id, libelle, texte, ville, par_defaut)
values ('adr_bureau', :MOI::uuid, 'Bureau', 'Rue 128, Ganhi', 'Cotonou', true)
on conflict (id) do nothing;
select essai.egal(
  (select count(*)::int from public.adresses where par_defaut), 1,
  'la seconde prend la place, elle ne s''ajoute pas');
select essai.egal(
  (select libelle from public.adresses where par_defaut), 'Bureau',
  'et c''est bien la dernière cochée qui l''emporte');
select essai.egal(
  (select count(*)::int from public.adresses), 2,
  'les deux adresses sont conservées');

-- La même chose par modification, et non par ajout : c'est le geste
-- courant à l'écran, et il emprunte un autre chemin dans la base.
update public.adresses set par_defaut = true where id = 'adr_maison';
select essai.egal(
  (select count(*)::int from public.adresses where par_defaut), 1,
  'cocher une ancienne adresse décoche l''autre');
select essai.egal(
  (select libelle from public.adresses where par_defaut), 'Maison',
  'et c''est celle qu''on vient de cocher');

-- ---------------------------------------------------------
select essai.titre('Une adresse ne se lit pas par-dessus l''épaule');

select essai.devenir(:AUTRE::uuid);
set role authenticated;
select essai.egal(
  (select count(*)::int from public.adresses), 0,
  'un client ne voit aucune adresse d''un autre');
select essai.refuse(
  'insert into public.adresses (id, client_id, libelle, texte)
   values (''adr_pirate'', ' || quote_literal(:MOI) || '::uuid, ''Chez lui'', ''…'')',
  'écrire une adresse au nom d''un autre');
select essai.sans_effet(
  'update public.adresses set texte = ''détourné'' where id = ''adr_maison''',
  'réécrire l''adresse d''un autre');

select essai.devenir(:MOI::uuid);
set role authenticated;
select essai.egal(
  (select texte from public.adresses where id = 'adr_maison'),
  'Carré 1242, Akpakpa',
  'l''adresse est restée telle qu''elle a été écrite');

-- ---------------------------------------------------------
select essai.titre('Le classement rend un ordre, pas des chiffres');

reset role;
select essai.personne();
set role anon;
-- Ouvert à tous : c'est l'accueil, il s'affiche avant qu'on se
-- connecte. Ce qui compte, c'est CE QU'IL REND.
select essai.verifie(
  (select count(*) from public.produits_populaires(8)) >= 0,
  'un visiteur obtient le classement de l''accueil');

-- UNE SEULE COLONNE, et c'est tout le sujet. Ajouter « quantité » à
-- ce retour paraîtrait anodin et livrerait les volumes de vente de
-- chaque boutique à qui sait ouvrir un navigateur.
-- LES COLONNES D'UNE FONCTION NE SONT PAS DANS
-- « information_schema.columns » : ce n'est pas une table. Elles sont
-- déclarées en paramètres de sortie dans pg_proc, et c'est là qu'il
-- faut aller les compter. Le contrôle écrit sur le mauvais catalogue
-- trouvait ZÉRO colonne — et aurait donc trouvé zéro le jour où l'on
-- aurait ajouté « quantité » au retour.
-- « proargnames » compte AUSSI le paramètre d'entrée : deux noms pour
-- une seule colonne rendue. On lit donc la signature de sortie telle
-- que PostgreSQL la déclare — une phrase qu'on peut comparer mot pour
-- mot, et qui change dès qu'on ajoute quoi que ce soit au retour.
select essai.egal(
  (select pg_get_function_result(p.oid)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'produits_populaires'),
  'TABLE(produit_id text)',
  'la fonction ne rend que l''identifiant du produit, et rien d''autre');

-- Les lignes de commande restent fermées : c'est ce qui rend la
-- fonction nécessaire, et c'est aussi ce qu'elle ne doit pas défaire.
select essai.refuse(
  'select count(*) from public.commande_lignes',
  'un visiteur lit les lignes de commande');

select essai.titre('Tout est passé');
