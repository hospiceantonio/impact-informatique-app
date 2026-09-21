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
       limit 1), false)),

  -- ---------- La marge sur les ventes aux revendeurs ----------
  -- Sans elle, un revendeur validé achèterait au prix BIZZOO exact :
  -- l'enseigne ne gagnerait rien, et il lirait article par article ce
  -- que la boutique touche.
  (48, 'La marge revendeur de chaque boutique (boutiques.taux_revendeur)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'boutiques'
         and column_name = 'taux_revendeur')),
  (49, 'Et sa façon de compter (boutiques.revendeur_mode)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'boutiques'
         and column_name = 'revendeur_mode')),
  -- Un article négocié à part a son propre taux ; à null, celui de la
  -- boutique s'applique.
  (50, 'Le taux propre à un article (produits_prive.taux_revendeur)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'produits_prive'
         and column_name = 'taux_revendeur')),
  -- La règle à quatre arguments : l'ancienne n'en prenait que deux et
  -- rendait le prix BIZZOO nu.
  (51, 'La règle de prix porte la marge (prix_revendeur)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'prix_revendeur'
         and p.pronargs = 4)),

  -- ---------- Où se trouve le commerce d'un revendeur ----------
  -- Valider, c'est accorder une remise permanente sur tout le
  -- catalogue : l'enseigne décide mieux en sachant où c'est.
  (52, 'La position du commerce (clients.revendeur_latitude)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'clients'
         and column_name = 'revendeur_latitude')),
  (53, 'Et son adresse écrite (clients.revendeur_adresse)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'clients'
         and column_name = 'revendeur_adresse')),
  -- Un point FAUX sur une carte est pire que pas de point du tout :
  -- on se déplace pour rien.
  (54, 'Ce qui n''est pas une coordonnée est écarté (coord_valable)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'coord_valable')),
  (55, 'La liste du superadministrateur la rend (revendeurs)', coalesce((
      select pg_get_function_result(p.oid) like '%latitude%'
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'revendeurs'
       limit 1), false)),

  -- ---------- La marge change, les prix suivent ----------
  -- Sans ce déclencheur, changer la marge d'une boutique ne touche
  -- AUCUN prix : il faut rouvrir chaque article un par un. En pratique,
  -- la marge annoncée et la marge pratiquée divergent en silence.
  (56, 'Le prix de vente se calcule en base (prix_public)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'prix_public')),
  (57, 'Changer la marge recalcule les prix (boutiques_prix_a_jour)', exists (
      select 1 from pg_trigger tr join pg_class c on c.oid = tr.tgrelid
       where not tr.tgisinternal and c.relname = 'boutiques'
         and tr.tgname = 'boutiques_prix_a_jour')),

  -- ---------- Chaque boutique voit ce qu'elle vend ----------
  (58, 'Une boutique lit ses propres ventes (statistiques_boutique)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'statistiques_boutique')),
  -- Et elle ne lit QUE les siennes : deux paramètres, deux dates. Si un
  -- troisième apparaissait, ce serait un paramètre « boutique » — donc
  -- la possibilité de viser la voisine.
  (59, 'Et seulement les siennes : la boutique ne se choisit pas', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'statistiques_boutique'
         and p.pronargs = 2)),
  -- Les chiffres de l'enseigne ne sont pas dans le résultat. Pas
  -- « masqués à l'écran » : absents.
  (60, 'Ni la marge ni le bénéfice n''en sortent', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'statistiques_boutique'
         and pg_get_function_result(p.oid) not like '%taux_marge%'
         and pg_get_function_result(p.oid) not like '%benefice%'
         and pg_get_function_result(p.oid) not like '%prix_vente%')),

  -- ---------- Retrouver un client, et ses commandes ----------
  (61, 'Les fiches clients (clients_liste)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'clients_liste')),
  (62, 'Et ses commandes, celles d''avant comprises (client_commandes)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'client_commandes')),
  -- Les deux sont des LECTURES. Si l'une d'elles écrivait, elle ne
  -- pourrait pas être déclarée « stable » : PostgreSQL le refuse.
  (63, 'Elles regardent le fichier, elles ne l''écrivent pas', not exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname in ('clients_liste', 'client_commandes')
         and p.provolatile = 'v')),

  -- ---------- Le journal des versements ----------
  (64, 'Le journal des versements (table versements)', exists (
      select 1 from information_schema.tables
       where table_schema = 'public' and table_name = 'versements')),
  (65, 'Une ligne s''y écrit par le serveur seul (noter_versement)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'noter_versement')),
  -- LE contrôle qui compte. Une seule règle sur cette table, et elle ne
  -- porte que sur la lecture : personne n'écrit le journal à la main,
  -- pas même l'enseigne. Un journal retouchable ne prouve rien.
  (66, 'Et personne ne l''écrit à la main, pas même l''enseigne', not exists (
      select 1 from pg_policies
       where schemaname = 'public' and tablename = 'versements'
         and cmd <> 'SELECT')),
  -- Le paiement dit QUI a encaissé et chez quel opérateur : sans ce
  -- paramètre, le journal resterait muet sur la question qu'on lui pose.
  (67, 'Le paiement note l''agrégateur (marquer_payee à 4 paramètres)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'marquer_payee'
         and p.pronargs = 4)),
  (68, 'Et l''ouverture note l''opérateur (noter_reference à 4)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'noter_reference'
         and p.pronargs = 4)),
  (69, 'Le journal se lit par l''enseigne (versements_liste)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'versements_liste')),

  -- ---------- Les codes promo ----------
  (70, 'Les codes promo (table codes_promo)', exists (
      select 1 from information_schema.tables
       where table_schema = 'public' and table_name = 'codes_promo')),
  (71, 'La remise se pose sur la COMMANDE (commandes.remise)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'commandes'
         and column_name = 'remise')),
  -- LA règle, et elle est UNE : l'écran du panier et la caisse appellent
  -- la même. Deux calculs finiraient par diverger, et le client paierait
  -- autre chose que ce qu'on lui a montré.
  (72, 'Une seule règle de remise (remise_du_code)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'remise_du_code')),
  (73, 'Le panier peut l''interroger avant de commander (verifier_code)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'verifier_code')),
  -- La caisse doit savoir recevoir un code : sans ce troisième
  -- paramètre, le client taperait un code que la commande ignorerait.
  (74, 'La caisse reçoit le code (creer_commande à 3 paramètres)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'creer_commande'
         and p.pronargs = 3)),
  -- Sans celle-ci, le bénéfice affiché serait surévalué de toutes les
  -- remises accordées : il se calcule sur les lignes, où la remise
  -- n'apparaît pas.
  (75, 'Les remises se retranchent de vos comptes (remises_periode)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'remises_periode')),
  -- Un client ne doit pas pouvoir lire la table : il y trouverait tous
  -- les codes en cours, y compris ceux qui ne lui étaient pas destinés.
  (76, 'Un client ne lit pas la liste des codes', not exists (
      select 1 from pg_policies
       where schemaname = 'public' and tablename = 'codes_promo'
         and cmd <> 'SELECT')),

  -- ---------- Le cycle de vie d'une commande ----------
  (77, 'L''étape « en livraison » existe', exists (
      select 1 from pg_constraint
       where conrelid = 'public.commande_lignes'::regclass
         and conname = 'commande_lignes_etat_check'
         and pg_get_constraintdef(oid) like '%en_livraison%')),
  (78, 'L''accusé de réception du client (commande_lignes.confirme_le)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'commande_lignes'
         and column_name = 'confirme_le')),
  (79, 'Le client le pose lui-même (confirmer_reception)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'confirmer_reception')),
  -- LE contrôle qui compte, et il ne regarde PAS les droits d'écriture :
  -- sur une base Supabase, « authenticated » les reçoit d'office sur
  -- toute table du schéma public. Chercher là un droit restreint, c'est
  -- annoncer « MANQUANT » sur une base parfaitement saine. Ce qui tient
  -- la porte, c'est le déclencheur « lignes_verrous » : il REFUSE toute
  -- écriture de confirme_le qui ne vienne pas de confirmer_reception().
  -- Sans lui, la boutique signerait l'accusé de réception du client, et
  -- sa propre déclaration « remise » n'aurait plus de contrepoids.
  (80, 'Et la boutique ne peut pas le poser à sa place', exists (
      select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
       where t.tgrelid = 'public.commande_lignes'::regclass
         and not t.tgisinternal and p.proname = 'ligne_verrous'
         and pg_get_functiondef(p.oid) like '%confirme_le%')),
  -- Le client doit LIRE l'avancement : sans ce droit, son écran
  -- n'afficherait aucune étape.
  (81, 'Le client lit l''avancement de sa commande', exists (
      select 1 from information_schema.column_privileges
       where table_schema = 'public' and table_name = 'commande_lignes'
         and grantee = 'authenticated' and privilege_type = 'SELECT'
         and column_name = 'confirme_le')),

  -- ---------- Le rôle livreur ----------
  (82, 'Le rôle « livreur » est accepté', exists (
      select 1 from pg_constraint
       where conrelid = 'public.profils'::regclass
         and conname = 'profils_role_check'
         and pg_get_constraintdef(oid) like '%livreur%')),
  (83, 'On sait à qui une ligne est confiée (commande_lignes.livreur_id)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'commande_lignes'
         and column_name = 'livreur_id')),
  -- Et comme pour l'accusé de réception, c'est le déclencheur qui tient
  -- la porte : sans lui, n'importe quelle écriture sur la ligne pourrait
  -- se désigner porteuse de la marchandise.
  (84, 'Et on ne se désigne pas porteur soi-même', exists (
      select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
       where t.tgrelid = 'public.commande_lignes'::regclass
         and not t.tgisinternal and p.proname = 'ligne_verrous'
         and pg_get_functiondef(p.oid) like '%livreur_id%')),
  -- LE contrôle de sécurité de tout ce chantier. « est_equipe() » ouvre
  -- neuf écrans, du catalogue aux statistiques. Tant qu'elle disait
  -- « un rôle, n'importe lequel », le premier livreur créé entrait
  -- partout. On vérifie donc qu'elle NOMME les trois rôles de la
  -- boutique — un « livreur absent » ne prouverait rien, l'ancienne
  -- version ne le nommait pas non plus.
  (85, 'L''équipe de la boutique est nommée, et le livreur n''en est pas', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'est_equipe'
         and pg_get_functiondef(p.oid) like '%moderateur%'
         and pg_get_functiondef(p.oid) not like '%''livreur''%')),
  (86, 'On sait le reconnaître (est_livreur)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'est_livreur')),
  -- « peut_modifier_produits » vaut VRAI par défaut sur tout profil :
  -- sans le est_equipe() en tête, la colonne dirait oui à un livreur
  -- qu'on vient de créer, et le catalogue s'ouvrirait.
  (87, 'Et il ne touche pas au catalogue', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'peut_modifier_produits'
         and pg_get_functiondef(p.oid) like '%est_equipe%')),
  (88, 'La boutique lui confie une course (assigner_livreur)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'assigner_livreur')),
  (89, 'Il voit les siennes (mes_livraisons)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'mes_livraisons')),
  -- Le livreur porte la marchandise ; il n'a pas à savoir ce qu'elle
  -- vaut. Une règle RLS choisit les LIGNES et les rend entières : seule
  -- une fonction peut retenir des colonnes. On lit donc ce qu'elle
  -- annonce rendre, et on y cherche de l'argent.
  (90, 'Sans voir un seul montant', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'mes_livraisons'
         and pg_get_function_result(p.oid) not like '%prix%'
         and pg_get_function_result(p.oid) not like '%total%'
         and pg_get_function_result(p.oid) not like '%montant%'
         and pg_get_function_result(p.oid) not like '%remise%')),
  (91, 'Et il avance lui-même sa course (avancer_livraison)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'avancer_livraison')),

  -- ---------- La seconde serrure des lignes de commande ----------
  -- Le contrôle 80 regarde le déclencheur, qui est la serrure qui a
  -- toujours tenu. Celui-ci regarde la seconde, posée depuis : le droit
  -- d'écriture lui-même, RETIRÉ sur la table entière puis rendu sur la
  -- seule colonne « etat ». Sans le retrait il n'y a pas de seconde
  -- serrure — une base Supabase donne « grant all » d'office, et un
  -- droit de colonne par-dessus n'en retire aucun.
  (92, 'L''équipe n''écrit que « etat » sur une ligne vendue', not exists (
      select 1 from information_schema.column_privileges
       where table_schema = 'public' and table_name = 'commande_lignes'
         and grantee = 'authenticated' and privilege_type = 'UPDATE'
         and column_name <> 'etat')),

  -- ---------- La liste des catégories, celle de l'enseigne ----------
  (93, 'La pastille d''une catégorie (icone, couleur)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'categories' and column_name = 'icone')
    and exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'categories' and column_name = 'couleur')),
  (94, 'Celles que l''accueil montre (categories.en_avant)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'categories' and column_name = 'en_avant')),
  (95, 'Le secteur d''une boutique (boutiques.categorie_id)', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'boutiques' and column_name = 'categorie_id')),
  -- Sans ce retrait, un produit laissé à classer serait refusé et toute
  -- la reprise s'arrêterait à la première ligne.
  (96, 'Un produit peut attendre d''être classé', exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'produits'
         and column_name = 'categorie_id' and is_nullable = 'YES')),
  -- LE contrôle de ce chantier. Tant qu'une boutique peut écrire la
  -- liste, ce n'est plus une liste commune : c'est autant de
  -- classements qu'il y a de commerces, et l'écran « Catégories » de
  -- BIZZOO ne veut plus rien dire.
  (97, 'L''enseigne SEULE écrit la liste', not exists (
      select 1 from pg_policies
       where schemaname = 'public' and tablename in ('categories', 'sous_categories')
         and cmd <> 'SELECT'
         and coalesce(qual, '') not like '%est_super%')),
  -- Et elle reste LUE par tout le monde : c'est le menu de la vitrine.
  (98, 'Et tout le monde la lit, même sans compte', exists (
      select 1 from pg_policies
       where schemaname = 'public' and tablename = 'categories' and cmd = 'SELECT')),
  -- Le rayon commande, la catégorie suit. Si le déclencheur ne nommait
  -- plus la sous-catégorie, l'application pourrait ranger un produit
  -- où bon lui semble.
  (99, 'Le rayon d''un produit se déduit de sa sous-catégorie', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'produit_code'
         and pg_get_functiondef(p.oid) like '%sous_categorie_id%'
         and pg_get_functiondef(p.oid) like '%secteur de sa boutique%')),
  (100, 'Changer de secteur passe par la fonction prévue (changer_secteur)', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'changer_secteur')),
  -- Une catégorie de l'enseigne n'appartient à personne. S'il en restait
  -- une rattachée à une boutique, l'ancien classement cohabiterait avec
  -- le nouveau, et l'écran du client montrerait les deux.
  (101, 'Aucun ancien rayon de boutique ne traîne', not exists (
      select 1 from public.categories where boutique_id is not null)),

  -- ---------- Ce que le client garde pour lui ----------
  (102, 'Les produits mis de côté (favoris)',
      to_regclass('public.favoris') is not null),
  (103, 'Les boutiques suivies',
      to_regclass('public.boutiques_suivies') is not null),
  (104, 'Les adresses de livraison',
      to_regclass('public.adresses') is not null),
  -- Deux adresses par défaut, c'est un formulaire de commande qui en
  -- choisit une au hasard — et un colis chez la mauvaise.
  (105, 'Une seule adresse par défaut, garantie par la base', exists (
      select 1 from pg_indexes where schemaname = 'public'
         and indexname = 'adresses_une_par_defaut')),
  (106, 'Et cochée sans erreur au client', exists (
      select 1 from pg_trigger where tgname = 'adresses_defaut'
         and not tgisinternal)),
  -- CE CONTRÔLE-LÀ EST LE PLUS IMPORTANT DES HUIT. Une base Supabase
  -- accorde tout d'office aux visiteurs : si le « revoke » n'avait pas
  -- pris, n'importe qui lirait les adresses de domicile de tous les
  -- clients avec la seule clé publique de l'application.
  (107, 'Rien de tout cela n''est lisible sans compte', not exists (
      select 1 from information_schema.role_table_grants
       where table_schema = 'public'
         and table_name in ('favoris', 'boutiques_suivies', 'adresses')
         and grantee = 'anon')),
  (108, 'Le classement des ventes, pour l''accueil', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'produits_populaires')),
  -- Il rend un ORDRE, jamais des chiffres : « voici ce qui part le
  -- plus » est un service au client ; « voici combien chaque boutique
  -- vend » livrerait à chacun le carnet de commandes de son voisin.
  (109, 'Qui rend un ordre, et aucun chiffre de vente', exists (
      select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'produits_populaires'
         and pg_get_function_result(p.oid) = 'TABLE(produit_id text)'))
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

-- ---------- Facultatif : ce que paierait un revendeur ----------
-- Trois articles pris au hasard. « Prix revendeur » doit tomber ENTRE
-- le prix BIZZOO et le prix public — jamais en dessous, jamais au-dessus.
--
--   select b.nom as "Boutique",
--          case b.revendeur_mode when 'public' then 'prix public − ' || b.taux_revendeur || ' %'
--                                else 'prix BIZZOO + ' || b.taux_revendeur || ' %' end as "Règle",
--          p.nom as "Article", p.prix as "Prix public",
--          coalesce(pv.prix_grossiste, 0) as "Prix BIZZOO",
--          public.prix_revendeur(coalesce(p.prix, 0)::int,
--            greatest(0, coalesce(pv.prix_grossiste, 0))::int,
--            coalesce(pv.taux_revendeur, b.taux_revendeur, 0),
--            coalesce(b.revendeur_mode, 'bizzoo')) as "Prix revendeur"
--     from public.produits p
--     join public.boutiques b on b.id = p.boutique_id
--     left join public.produits_prive pv on pv.produit_id = p.id
--    order by b.nom, p.nom limit 3;
