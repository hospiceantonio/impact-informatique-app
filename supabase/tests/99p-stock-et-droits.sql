-- =========================================================
-- Le bilan de santé : le stock gardé, quatre portes refermées
--
-- CE QU'ON DÉFEND ICI. La base en ligne comparée à schema.sql a
-- montré deux garde-fous absents :
--
--   - la règle « produits_stock_check » : une base neuve la porte
--     dans son « create table », une base en service a reçu la
--     colonne après coup, sans elle ;
--   - quatre actions d'administration restaient ouvertes à
--     « anon » : Supabase lui accorde chaque fonction nommément,
--     et « retirer à public » ne lui retirait rien.
--
-- Cinq choses à prouver :
--
--   1. LE STOCK NE DESCEND PAS SOUS ZÉRO, même pour l'enseigne,
--      même en passant par-dessus les règles d'accès ;
--   2. UNE BASE EN SERVICE SANS LA RÈGLE LA REÇOIT du fichier à
--      coller — un stock négatif ramené à zéro d'abord, sinon le
--      fichier entier échouerait —, sous le MÊME nom et la MÊME
--      définition qu'une base neuve ;
--   3. LES QUATRE PORTES SONT FERMÉES AUX VISITEURS, et ouvertes
--      à l'équipe connectée ;
--   4. RIEN D'AUTRE N'A ÉTÉ FERMÉ : ce que le client appelle sans
--      compte reste ouvert, et les fonctions que les règles d'accès
--      appellent aussi — les fermer ferait refuser à un visiteur
--      jusqu'à la lecture du catalogue ;
--   5. REJOUER LE FICHIER NE CHANGE RIEN.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''

-- DEUX REFUS PRÉCIS. « essai.refuse » se contente d'une erreur, quelle
-- qu'elle soit — et ici, cela ne prouverait rien : une fonction ouverte
-- à « anon » refuse AUSSI un visiteur, de l'intérieur ; un stock négatif
-- pourrait tomber sur un autre verrou que la règle. On exige donc la
-- bonne raison.

-- Refusé par CETTE règle-là, et pas par une autre.
create or replace function essai.refuse_par_regle(requete text, regle text, quoi text)
returns void language plpgsql as $$
declare nom text;
begin
  begin
    execute requete;
  exception when check_violation then
    get stacked diagnostics nom = constraint_name;
    if nom = regle then
      raise notice '  ok    % — refusé par %', quoi, nom;
      return;
    end if;
    perform essai.echec('ÉCHEC : ' || quoi || ' — refusé par ' || coalesce(nom, '?') ||
                        ', et non par ' || regle);
  end;
  perform essai.echec('ÉCHEC : ' || quoi || ' — la base a LAISSÉ PASSER');
end $$;

-- Refusé À LA PORTE : le droit d'exécuter manque. Une fonction qui
-- s'exécute puis refuse de l'intérieur ne compte pas.
create or replace function essai.porte_fermee(requete text, quoi text)
returns void language plpgsql as $$
begin
  begin
    execute requete;
  exception
    when insufficient_privilege then
      raise notice '  ok    % — refusé à la porte', quoi;
      return;
    when sqlstate 'BZ001' then raise;
    when others then
      perform essai.echec('ÉCHEC : ' || quoi || ' — la porte était ouverte : la fonction ' ||
                          's''est exécutée, et a refusé d''elle-même (' || left(sqlerrm, 50) || ')');
  end;
  perform essai.echec('ÉCHEC : ' || quoi || ' — la base a LAISSÉ PASSER');
end $$;
-- Le message d'un refus, pour le LIRE (le même que dans 97, pour que ce
-- fichier se suffise).
create or replace function essai.message_de(requete text) returns text
language plpgsql as $$
begin
  execute requete;
  return '';
exception
  when sqlstate 'BZ001' then raise;
  when others then return sqlerrm;
end $$;
grant execute on function essai.refuse_par_regle(text, text, text) to anon, authenticated, service_role;
grant execute on function essai.porte_fermee(text, text) to anon, authenticated, service_role;
grant execute on function essai.message_de(text) to anon, authenticated;

-- ---------------------------------------------------------
select essai.titre('Le décor : un produit en stock');

insert into public.produits
  (id, boutique_id, nom, prix, sous_categorie_id, stock, sur_commande, disponible)
values
  ('prod_essai_stock', 'bou_informatique', 'Article du bilan', 5000,
   'sc_hightech_accessoires', 4, false, true)
on conflict (id) do update set stock = 4, sur_commande = false, disponible = true;

select essai.egal(
  (select stock from public.produits where id = 'prod_essai_stock'), 4,
  'il a quatre pièces');

-- ---------------------------------------------------------
select essai.titre('1. Le stock ne descend pas sous zéro');

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.refuse_par_regle(
  $$update public.produits set stock = -1 where id = 'prod_essai_stock'$$,
  'produits_stock_check', 'l''enseigne elle-même ne pose pas « moins une » pièce');
reset role; select essai.personne();

-- PAR-DESSUS LES RÈGLES D'ACCÈS : c'est ainsi qu'écrivent les fonctions
-- du serveur. Une règle de table les arrête quand même.
set role service_role;
select essai.refuse_par_regle(
  $$update public.produits set stock = -3 where id = 'prod_essai_stock'$$,
  'produits_stock_check', 'le rôle du serveur non plus');
reset role;

select essai.egal(
  (select stock from public.produits where id = 'prod_essai_stock'), 4,
  'le stock n''a pas bougé');

-- ---------------------------------------------------------
select essai.titre('2. Une base en service sans la règle la reçoit');

-- LA BASE EN LIGNE, TELLE QU'ELLE ÉTAIT : la règle absente, et — pire
-- cas — un stock déjà négatif. Sans la remise à zéro, poser la règle
-- échouerait, et avec elle tout le fichier collé.
create temp table essai_regle_neuve as
  select pg_get_constraintdef(oid) as definition
    from pg_constraint
   where conrelid = 'public.produits'::regclass and conname = 'produits_stock_check';
alter table public.produits drop constraint produits_stock_check;
update public.produits set stock = -2 where id = 'prod_essai_stock';
select essai.egal(
  (select stock from public.produits where id = 'prod_essai_stock'), -2,
  'sans la règle, un stock négatif passait');

\set fichier `echo "$RACINE/supabase/stock-et-droits.sql"`
\o /dev/null
set client_min_messages = warning;
\i :fichier
set client_min_messages = notice;
\o

select essai.egal(
  (select stock from public.produits where id = 'prod_essai_stock'), 0,
  'le stock négatif est ramené à zéro');
select essai.egal(
  (select pg_get_constraintdef(oid) from pg_constraint
    where conrelid = 'public.produits'::regclass and conname = 'produits_stock_check'),
  (select definition from essai_regle_neuve),
  'la règle revient, sous le nom et la définition d''une base neuve');
select essai.refuse_par_regle(
  $$update public.produits set stock = -1 where id = 'prod_essai_stock'$$,
  'produits_stock_check', 'et elle refuse de nouveau');

-- ---------------------------------------------------------
select essai.titre('3. Les quatre portes, fermées aux visiteurs');

select essai.egal(
  (select string_agg(p.proname, ', ' order by p.proname)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('supprimer_compte', 'changer_mot_de_passe',
                        'approuver_demande', 'refuser_demande')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  'approuver_demande, changer_mot_de_passe, refuser_demande, supprimer_compte',
  'fermées aux visiteurs, ouvertes à l''équipe');

-- UN VISITEUR NE PEUT PLUS MÊME TENTER L'APPEL : c'est la base qui
-- refuse à la porte, avant que la fonction ne s'exécute.
set role anon;
select essai.porte_fermee(
  $$select public.supprimer_compte('11111111-1111-1111-1111-111111111111')$$,
  'un visiteur ne tente pas de supprimer un compte');
select essai.porte_fermee(
  $$select public.changer_mot_de_passe('11111111-1111-1111-1111-111111111111', 'x')$$,
  'ni de changer un mot de passe');
select essai.porte_fermee(
  $$select public.approuver_demande('dem_inexistante')$$,
  'ni d''approuver une demande');
select essai.porte_fermee(
  $$select public.refuser_demande('dem_inexistante', '')$$,
  'ni d''en refuser une');
reset role;

-- L'ÉQUIPE CONNECTÉE, ELLE, ENTRE — et c'est la fonction qui décide.
-- L'enseigne approuve ; la demande n'existe pas : c'est ce refus-là,
-- venu du dedans, qui prouve qu'on a passé la porte.
select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.egal(
  essai.message_de($$select public.approuver_demande('dem_inexistante')$$),
  'Demande introuvable',
  'l''enseigne passe la porte ; la fonction répond « introuvable »');
reset role; select essai.personne();

-- ---------------------------------------------------------
select essai.titre('4. Rien d''autre n''a été fermé');

select essai.egal(
  (select count(*)::int
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('creer_commande', 'suivre_commande',
                        'signaler_transaction', 'verifier_code')
      and has_function_privilege('anon', p.oid, 'EXECUTE')),
  4, 'commander, suivre, signaler un paiement, essayer un code : sans compte');
-- Les fonctions que les règles d'accès appellent. Fermées à « anon »,
-- elles feraient refuser à un visiteur la moindre lecture.
select essai.egal(
  (select count(*)::int
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('est_super', 'est_admin', 'peut_agir_sur', 'peut_deposer',
                        'role_courant', 'boutique_du_compte')
      and has_function_privilege('anon', p.oid, 'EXECUTE')),
  6, 'les fonctions des règles d''accès restent ouvertes');
set role anon;
select essai.verifie(
  (select count(*) from public.produits where id = 'prod_essai_stock') = 1,
  'un visiteur lit toujours le catalogue');
reset role;

-- ---------------------------------------------------------
select essai.titre('5. Rejouer le fichier ne change rien');

\o /dev/null
set client_min_messages = warning;
\i :fichier
set client_min_messages = notice;
\o
select essai.egal(
  (select count(*)::int from pg_constraint
    where conrelid = 'public.produits'::regclass and conname = 'produits_stock_check'),
  1, 'une seule règle, pas deux');
select essai.egal(
  (select count(*)::int
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('supprimer_compte', 'changer_mot_de_passe',
                        'approuver_demande', 'refuser_demande')
      and has_function_privilege('anon', p.oid, 'EXECUTE')),
  0, 'les quatre portes restent fermées');

-- On rend la base comme on l'a trouvée.
delete from public.produits where id = 'prod_essai_stock';
