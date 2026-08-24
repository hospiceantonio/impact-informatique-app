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
         and tablename = 'commandes'))
)
select rang                                            as "#",
       element                                         as "Ce qui est vérifié",
       case when ok then 'en place' else 'MANQUANT' end as "État",
       case when ok then '' else 'Exécuter supabase/schema.sql' end as "À faire"
  from controles
 order by rang;

-- ---------- Facultatif : où en est le paiement KkiaPay ----------
-- À lancer séparément (la requête ci-dessus n'en dépend pas, pour
-- pouvoir répondre même sur une base où les commandes manquent encore).
--
--   select case when actif then 'ouvert aux clients' else 'fermé' end as "Paiement",
--          case when bac_a_sable then 'bac à sable' else 'PRODUCTION' end as "Mode",
--          case when coalesce(cle_publique, '') = '' then 'aucune'
--               else left(cle_publique, 8) || '…' end as "Clé publique"
--     from public.paiement;
