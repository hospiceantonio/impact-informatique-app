-- =========================================================
-- BIZZOO — état des lieux de la base
--
-- Une seule requête, qui ne modifie RIEN. Elle regarde ce qui
-- est en place et ce qui manque, fonctionnalité par
-- fonctionnalité — plutôt que de se demander quel fichier a
-- été exécuté et quand.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Tout doit répondre « en place ». Ce qui répond « MANQUANT »
-- se corrige en exécutant supabase/schema.sql, qui contient
-- tout et se relance sans danger.
-- =========================================================

with controles(rang, element, ok) as (values

  -- ---------- Le catalogue ----------
  (1, 'Gestion du stock (produits.stock)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'produits' and column_name = 'stock')),

  (2, 'Vente flash (produits.flash_fin)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'produits' and column_name = 'flash_fin')),

  (3, 'Approvisionnement annoncé (produits.appro_le)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'produits' and column_name = 'appro_le')),

  (4, 'Prix grossiste tenu à l''écart des clients', exists (
      select 1 from pg_class where relname = 'produits_prive')
    and not exists (
      select 1 from pg_class c
       where c.relname = 'produits_prive'
         and has_table_privilege('anon', c.oid, 'SELECT'))),

  -- ---------- Les boutiques et l'enseigne ----------
  (5, 'Publicité de BIZZOO (slides.portee, slides.produit_id)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'slides' and column_name = 'portee')
    and exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'slides' and column_name = 'produit_id')),

  (6, 'Ouvrir/fermer une boutique réservé à l''enseigne', exists (
      select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
       where not t.tgisinternal and c.relname = 'boutiques'
         and t.tgname = 'boutiques_verrous')),

  -- ---------- L'historique ----------
  (7, 'Historique par boutique (journal.boutique_id)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'journal' and column_name = 'boutique_id')),

  (8, 'Annuler une action (journal.retour)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'journal' and column_name = 'retour')
    and exists (
      select 1 from pg_policy p join pg_class c on c.oid = p.polrelid
       where c.relname = 'journal' and p.polname = 'journal annulation')),

  (9, 'Le journal ne se laisse pas forger', exists (
      select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
       where not t.tgisinternal and c.relname = 'journal'
         and t.tgname = 'journal_a_l_ecriture')),

  -- ---------- Les validations ----------
  (10, 'Demandes de validation (table demandes)', exists (
      select 1 from pg_class where relname = 'demandes')),

  (11, 'Approuver / refuser une demande', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'approuver_demande')),

  (12, 'Le slider d''une boutique passe par une demande', exists (
      select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
       where not t.tgisinternal and c.relname = 'slides'
         and t.tgname = 'slides_verrous')),

  -- ---------- Le panier et le paiement ----------
  (13, 'Commandes (tables commandes, commande_lignes, paiement)', exists (
      select 1 from pg_class where relname = 'commandes')
    and exists (select 1 from pg_class where relname = 'commande_lignes')
    and exists (select 1 from pg_class where relname = 'paiement')),

  (14, 'Passer commande sans écrire les prix (creer_commande)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'creer_commande')),

  (15, 'Le prix d''une ligne vendue ne se réécrit pas', exists (
      select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
       where not t.tgisinternal and c.relname = 'commande_lignes'
         and t.tgname = 'lignes_verrous')),

  (16, 'Personne ne se déclare payé (commandes_verrous)', exists (
      select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
       where not t.tgisinternal and c.relname = 'commandes'
         and t.tgname = 'commandes_verrous')),

  -- LE contrôle à ne jamais laisser passer : si « anon » ou
  -- « authenticated » peuvent appeler marquer_payee, quiconque extrait
  -- la clé publiable de l'APK valide ses commandes sans payer.
  (17, 'Encaisser réservé au serveur (marquer_payee)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'marquer_payee')
    and not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       cross join lateral (select rolname from pg_roles
                            where rolname in ('anon', 'authenticated')) r
       where n.nspname = 'public' and p.proname = 'marquer_payee'
         and has_function_privilege(r.rolname, p.oid, 'EXECUTE'))),

  (18, 'Les boutiques voient arriver leurs commandes en direct', exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public'
         and tablename = 'commandes')),

  -- ---------- Le code d'un produit ----------
  -- Ces deux-là vont ENSEMBLE. Le déclencheur « ligne_a_l_ecriture »
  -- écrit « new.code » sur chaque ligne de commande : si la colonne
  -- manque, PostgreSQL refuse la commande entière avec « record "new"
  -- has no field "code" », et plus personne ne peut commander.
  (19, 'Code du produit (produits.code)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'produits' and column_name = 'code')),

  (20, 'Code figé sur la ligne vendue (commande_lignes.code)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'commande_lignes' and column_name = 'code')),

  -- ---------- La marge de l'enseigne ----------
  (21, 'Prix BIZZOO figé sur la ligne (commande_lignes.prix_bizzoo)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'commande_lignes' and column_name = 'prix_bizzoo')),

  -- ---------- FeexPay ----------
  (22, 'Choix de l''agrégateur (paiement.fournisseur)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'paiement' and column_name = 'fournisseur')),

  (23, 'Référence de l''agrégateur (commandes.fournisseur_ref)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'commandes' and column_name = 'fournisseur_ref')),

  (24, 'Frein sur les demandes de paiement (commandes.tentative_le)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'commandes' and column_name = 'tentative_le')),

  (25, 'Le serveur seul pose une référence (noter_reference)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'noter_reference')),

  (26, 'Retrouver une commande par sa référence (commande_par_reference)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'commande_par_reference')),

  -- ---------- Les comptes clients ----------
  (27, 'Les comptes clients (table clients)', exists (
      select 1 from information_schema.tables
       where table_schema = 'public' and table_name = 'clients')),
  (28, 'La commande porte son compte (commandes.client_id)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'commandes'
         and column_name = 'client_id')),
  -- Sans ce verrou, un client pourrait se déclarer vérifié lui-même et
  -- réclamer les commandes passées avec le numéro d'un autre.
  (29, 'Le numéro vérifié ne se déclare pas (client_verrous)', exists (
      select 1 from pg_trigger tr join pg_class c on c.oid = tr.tgrelid
       where not tr.tgisinternal and c.relname = 'clients'
         and tr.tgname = 'clients_verrous')),
  (30, 'Retrouver ses commandes d''avant (rattacher_mes_commandes)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'rattacher_mes_commandes')),

  -- ---------- Les comptes revendeurs ----------
  (31, 'Client ou revendeur (clients.revendeur_etat)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'clients'
         and column_name = 'revendeur_etat')),
  (32, 'La commande porte son régime de prix (commandes.revendeur)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'commandes'
         and column_name = 'revendeur')),
  (33, 'Les prix d''un revendeur validé (mes_prix)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'mes_prix')),
  -- Sans elle, le statut s'écrirait depuis l'application : chacun
  -- s'offrirait le catalogue au prix d'achat de la boutique.
  (34, 'Seul BIZZOO valide un revendeur (valider_revendeur)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'valider_revendeur')),

  -- ---------- Vérifier son numéro par SMS ----------
  -- Le drapeau « tel_verifie » n'est plus posé à la main : il suit
  -- « auth.users.phone_confirmed_at », que GoTrue écrit. Sans ce
  -- déclencheur, un numéro confirmé chez GoTrue resterait ignoré de
  -- BIZZOO, et le client ne retrouverait jamais ses commandes.
  (35, 'Le numéro confirmé arrive jusqu''à la fiche (numero_confirme)', exists (
      select 1 from pg_trigger tr join pg_class c on c.oid = tr.tgrelid
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'auth' and c.relname = 'users'
         and tr.tgname = 'numero_confirme')),
  (36, 'Le numéro national se calcule (tel_national)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'tel_national')),
  (37, 'Rattraper une confirmation manquée (reconcilier_numeros_verifies)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'reconcilier_numeros_verifies')),

  -- ---------- Mes commandes ----------
  -- Depuis que le client se connecte, il lit ses propres lignes de
  -- commande. Une règle RLS décide des LIGNES qu'il voit, jamais des
  -- COLONNES : sans droits par colonne, il lit aussi ce que la boutique
  -- a payé sa marchandise. Ce contrôle-ci doit être VRAI.
  (38, 'Le prix d''achat de la boutique reste fermé à l''acheteur', not exists (
      select 1 from information_schema.column_privileges
       where table_schema = 'public' and table_name = 'commande_lignes'
         and grantee = 'authenticated' and privilege_type = 'SELECT'
         and column_name in ('prix_bizzoo', 'taux_marge'))),

  -- ---------- Les avis ----------
  (39, 'Les avis des clients (table avis)', exists (
      select 1 from information_schema.tables
       where table_schema = 'public' and table_name = 'avis')),
  -- Sans elle, n'importe qui noterait n'importe quoi, et les avis
  -- honnêtes se noieraient avec les autres.
  (40, 'Seul qui a PAYÉ donne son avis (a_achete)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'a_achete')),
  (41, 'La note suit ses avis (avis_moyennes)', exists (
      select 1 from pg_trigger tr join pg_class c on c.oid = tr.tgrelid
       where not tr.tgisinternal and c.relname = 'avis'
         and tr.tgname = 'avis_moyennes')),
  -- Une boutique qui efface ce qui la gêne rend ses bons avis suspects.
  (42, 'La boutique répond, elle n''efface pas (repondre_avis)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'repondre_avis')),

  -- ---------- Le service après-vente ----------
  (43, 'Les réclamations (table reclamations)', exists (
      select 1 from information_schema.tables
       where table_schema = 'public' and table_name = 'reclamations')),
  -- Sans elle, « la boutique d'abord » n'est qu'une phrase : chacun
  -- appellerait l'enseigne à la seconde même.
  (44, 'BIZZOO n''entre qu''en recours (recours_possible)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'recours_possible')),
  (45, 'Et elle tranche ce qui lui est remonté (trancher_reclamation)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'trancher_reclamation')),

  -- ---------- Le compte pour commander ----------
  -- « En place » veut dire que l'INTERRUPTEUR existe, pas qu'il est
  -- allumé : il arrive éteint, et c'est l'application admin qui le
  -- bascule. La requête facultative en bas de ce fichier dit, elle, où
  -- il en est aujourd'hui.
  (46, 'L''interrupteur du compte obligatoire (table reglages)', exists (
      select 1 from information_schema.tables
       where table_schema = 'public' and table_name = 'reglages')),
  -- Le refus tient dans la base, pas à l'écran : un écran qui cache un
  -- bouton ne ferme rien, il suffit d'appeler la fonction directement.
  (47, 'La commande consulte la règle (creer_commande)', coalesce((
      select pg_get_functiondef(p.oid) like '%compte_exige%'
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'creer_commande'
       limit 1), false))
)
select rang                                            as "#",
       element                                         as "Ce qui est vérifié",
       case when ok then 'en place' else 'MANQUANT' end as "État",
       case when ok then '' else 'Exécuter supabase/schema.sql' end as "À faire"
  from controles
 order by rang;

-- ---------- Facultatif : où en est le paiement ----------
-- À lancer séparément (la requête ci-dessus n'en dépend pas, pour
-- pouvoir répondre même sur une base où les commandes manquent encore).
--
--   select case when actif then 'ouvert aux clients' else 'fermé' end as "Paiement",
--          case when bac_a_sable then 'bac à sable' else 'PRODUCTION' end as "Mode",
--          case when coalesce(cle_publique, '') = '' then 'aucune'
--               else left(cle_publique, 8) || '…' end as "Clé publique"
--     from public.paiement;

-- ---------- Facultatif : l'interrupteur est-il allumé ? ----------
-- Le contrôle 46 dit que l'interrupteur EXISTE. Celui-ci dit dans quelle
-- position il se trouve. Il arrive éteint, et se bascule depuis
-- l'application admin — Réglages → « Un compte pour commander ».
--
--   select case when compte_obligatoire
--               then 'ALLUMÉ — plus de commande sans compte'
--               else 'éteint — on commande sans compte' end as "Un compte pour commander",
--          maj_le                                           as "Dernier changement"
--     from public.reglages where id = 1;
