-- =========================================================
-- « Marquer vue » : la boutique fait avancer sa ligne
--
-- Le geste le plus courant de l'écran Commandes, et celui
-- qu'un refus rend le plus coûteux : la boutique ne peut plus
-- suivre ce qu'elle doit préparer.
--
-- CE QUE CET ESSAI REJOUE, ET POURQUOI. L'application n'envoie
-- pas « update … set etat = 'vue' ». Elle passe par PostgREST,
-- avec « Prefer: return=representation » — et PostgREST écrit
-- alors :
--
--     update public.commande_lignes set etat = 'vue'
--      where id = … RETURNING *
--
-- Ce « RETURNING * » est tout le sujet. Il réclame le droit de
-- LIRE chaque colonne de la table — y compris celles qu'on a
-- délibérément fermées à l'équipe : le prix BIZZOO et le taux
-- de marge. Un essai qui écrirait « update … set etat = 'vue' »
-- tout court passerait au vert sur une base où l'application
-- échoue.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set CHEF '''22222222-2222-2222-2222-222222222222'''

select essai.titre('Le décor : une commande payée, une ligne à suivre');

insert into public.commandes (id, numero, client_nom, client_tel, total, devise, etat)
values ('cmd_vue', 'BZ-000911', 'ROHIM', '97000099', 1650, 'FCFA', 'payee')
on conflict (id) do nothing;

insert into public.commande_lignes
  (id, commande_id, boutique_id, produit_id, nom, reference, prix, quantite, etat)
values ('lig_vue', 'cmd_vue', 'bou_informatique', 'prod_hp15',
        'M10 BT Wireless V5.3', 'Écouteurs bt', 1650, 1, 'nouvelle')
on conflict (id) do nothing;

select essai.egal(
  (select etat from public.commande_lignes where id = 'lig_vue'), 'nouvelle',
  'la ligne part de « nouvelle »');

-- ---------------------------------------------------------
select essai.titre('La boutique la marque vue — COMME L''APPLICATION LE FAIT');

select essai.devenir(:CHEF::uuid);
set role authenticated;

select essai.verifie(public.peut_agir_sur('bou_informatique'),
  'le compte agit bien sur cette boutique');

-- LA REQUÊTE DE POSTGREST, mot pour mot. Le « returning * » en fait
-- partie : c'est lui qui distingue un essai qui prouve quelque chose
-- d'un essai qui se rassure.
do $$
declare resultat text;
begin
  update public.commande_lignes set etat = 'vue'
   where id = 'lig_vue'
  returning etat into resultat;
  if resultat is null then
    raise exception 'aucune ligne touchée';
  end if;
end $$;

select essai.egal(
  (select etat from public.commande_lignes where id = 'lig_vue'), 'vue',
  'l''état a bien avancé');

-- ---------------------------------------------------------
select essai.titre('Mais « returning * » est REFUSÉ — et c''était le défaut');

-- CE CONSTAT DIT L'INVERSE DES AUTRES : il vérifie qu'un refus a bien
-- lieu. « returning * » réclame les colonnes fermées à l'équipe, et la
-- base a raison de refuser — ouvrir la lecture pour faire passer
-- l'écriture coûterait bien plus cher que le défaut qu'on répare.
--
-- C'est donc l'APPLICATION qui devait changer : elle demande désormais
-- « return=minimal », et ne réclame plus la ligne dont elle n'a que
-- faire. Si ce constat cesse un jour de refuser, c'est que quelqu'un a
-- ouvert le prix BIZZOO à toute l'équipe.
update public.commande_lignes set etat = 'nouvelle' where id = 'lig_vue';

do $$
declare ligne public.commande_lignes%rowtype;
begin
  update public.commande_lignes set etat = 'vue'
   where id = 'lig_vue'
  returning * into ligne;
  perform essai.echec(
    'ÉCHEC : « returning * » a été ACCEPTÉ — la marge est ouverte à l''équipe');
exception
  when sqlstate 'BZ001' then raise;
  when insufficient_privilege then
    raise notice '  ok    « returning * » est refusé, et doit l''être — %',
      left(sqlerrm, 50);
end $$;

-- ET CE QUE L'APPLICATION FAIT MAINTENANT : écrire sans rien réclamer
-- en retour. C'est exactement « Prefer: return=minimal ».
do $$
begin
  update public.commande_lignes set etat = 'vue' where id = 'lig_vue';
  raise notice '  ok    l''écriture seule, sans retour, passe';
exception
  when sqlstate 'BZ001' then raise;
  when others then
    perform essai.echec('ÉCHEC : même sans retour, l''écriture est refusée — '
      || sqlerrm);
end $$;

select essai.egal(
  (select etat from public.commande_lignes where id = 'lig_vue'), 'vue',
  'et la ligne est bien passée à « vue »');

-- ---------------------------------------------------------
select essai.titre('Ce qui reste fermé le reste');

-- La marge ne s'ouvre pas au passage : c'est tout l'objet des droits
-- de colonne, et un correctif qui les lèverait en bloc coûterait plus
-- cher que le défaut qu'il répare.
select essai.refuse(
  'select prix_bizzoo from public.commande_lignes where id = ''lig_vue''',
  'l''équipe lit le prix BIZZOO de la ligne');
select essai.refuse(
  'select taux_marge from public.commande_lignes where id = ''lig_vue''',
  'ou le taux de marge');
select essai.refuse(
  'update public.commande_lignes set prix = 1 where id = ''lig_vue''',
  'ou change le prix vendu');

reset role;
select essai.personne();
select essai.titre('Tout est passé');
