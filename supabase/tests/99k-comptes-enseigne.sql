-- =========================================================
-- Les comptes d'enseigne, et leurs interrupteurs
--
-- CE QU'ON DÉFEND ICI. Un compte d'enseigne — administrateur ou
-- modérateur de BIZZOO, rattaché à aucune boutique — voit les
-- commandes de TOUTES les boutiques. C'est beaucoup, et c'est
-- pour cela que ses droits viennent d'interrupteurs et non de
-- son rang.
--
-- UN INTERRUPTEUR QUI NE FERME QU'À L'ÉCRAN N'EST PAS UN DROIT.
-- « peut_agir_sur() » répond OUI partout à un compte d'enseigne ;
-- si les règles s'en contentaient, éteindre « commandes » ne
-- fermerait rien du tout. Chaque constat ci-dessous éprouve donc
-- la BASE, pas le bouton.
--
-- ET LE PIÈGE QU'ON A FAILLI LAISSER. schema.sql promouvait en
-- superadministrateur « tout administrateur sans boutique » —
-- une ligne écrite pour rattraper les bases d'avant. Avec les
-- comptes d'enseigne, cette phrase décrit exactement le nouveau
-- rang : un simple rejeu du fichier aurait donné l'enseigne
-- entière à un compte qu'on avait volontairement bridé. Le
-- dernier constat surveille cette ligne.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ADJOINT  '''dddddddd-1111-1111-1111-111111111111'''
\set VEILLEUR '''dddddddd-2222-2222-2222-222222222222'''
\set BRIDE    '''dddddddd-3333-3333-3333-333333333333'''

-- ---------------------------------------------------------
select essai.titre('Le décor : trois comptes de BIZZOO, aucune boutique');

insert into auth.users (id, email) values
  (:ADJOINT::uuid,  'adjoint@bizzoo.bj'),
  (:VEILLEUR::uuid, 'veilleur@bizzoo.bj'),
  (:BRIDE::uuid,    'bride@bizzoo.bj')
on conflict do nothing;

-- ADJOINT : administrateur de BIZZOO, tous les interrupteurs.
-- VEILLEUR : modérateur de BIZZOO, les commandes seulement.
-- BRIDE : modérateur de BIZZOO à qui on a TOUT éteint.
insert into public.profils
  (id, email, role, boutique_id, actif,
   peut_commandes, peut_boutiques, peut_finances, peut_modifier_produits)
values
  (:ADJOINT::uuid,  'adjoint@bizzoo.bj',  'administrateur', null, true,
   true,  true,  true,  true),
  (:VEILLEUR::uuid, 'veilleur@bizzoo.bj', 'moderateur',     null, true,
   true,  false, false, false),
  (:BRIDE::uuid,    'bride@bizzoo.bj',    'moderateur',     null, true,
   false, false, false, false)
on conflict (id) do update
   set role = excluded.role, boutique_id = null, actif = true,
       peut_commandes = excluded.peut_commandes,
       peut_boutiques = excluded.peut_boutiques,
       peut_finances  = excluded.peut_finances,
       peut_modifier_produits = excluded.peut_modifier_produits;

select essai.egal(
  (select count(*)::int from public.profils
    where boutique_id is null and role in ('administrateur', 'moderateur')), 3,
  'trois comptes d''enseigne existent');

-- ---------------------------------------------------------
select essai.titre('Qui est un compte d''enseigne, et qui ne l''est pas');

select essai.devenir(:ADJOINT::uuid); set role authenticated;
select essai.verifie(public.est_compte_enseigne(),
  'l''adjoint de BIZZOO en est un');
reset role;

select essai.devenir(:ENSEIGNE::uuid); set role authenticated;
select essai.verifie(not public.est_compte_enseigne(),
  'le superadministrateur, NON — il passe au-dessus des interrupteurs');
reset role;

select essai.devenir(:CHEF::uuid); set role authenticated;
select essai.verifie(not public.est_compte_enseigne(),
  'un administrateur de boutique, NON plus');
reset role;

-- ---------------------------------------------------------
select essai.titre('L''interrupteur « commandes » ouvre… et ferme');

select essai.devenir(:VEILLEUR::uuid); set role authenticated;
select essai.verifie(public.peut_voir_commandes(),
  'le veilleur, interrupteur allumé, voit les commandes');
select essai.verifie(
  (select count(*) from public.commandes) > 0,
  'et il en lit vraiment, de toutes les boutiques');
reset role;

select essai.devenir(:BRIDE::uuid); set role authenticated;
select essai.verifie(not public.peut_voir_commandes(),
  'le bridé, interrupteur éteint, ne les voit pas');
-- LE CONSTAT QUI COMPTE : ce n'est pas un bouton grisé, c'est la base
-- qui ne rend RIEN. RLS filtre les lignes sans rien annoncer : zéro
-- ligne est la seule preuve possible.
select essai.egal(
  (select count(*)::int from public.commandes), 0,
  'et la base ne lui en rend aucune');
select essai.egal(
  (select count(*)::int from public.commande_lignes), 0,
  'ni aucune ligne de commande');
reset role;

-- ---------------------------------------------------------
select essai.titre('Éteint, il ne peut pas non plus FAIRE AVANCER');

-- RLS ne lève pas : un « update » qui ne touche aucune ligne permise
-- réussit en silence. C'est le NOMBRE DE LIGNES TOUCHÉES qui parle.
select essai.devenir(:BRIDE::uuid); set role authenticated;
do $$
declare combien int;
begin
  update public.commande_lignes set etat = 'vue' where etat = 'nouvelle';
  get diagnostics combien = row_count;
  if combien > 0 then
    perform essai.echec('ÉCHEC : le compte bridé a fait avancer ' ||
      combien || ' ligne(s)');
  end if;
  raise notice '  ok    aucune ligne ne bouge sous sa main (0)';
end $$;
reset role;

-- Et le veilleur, lui, en fait avancer : sans ce constat, le précédent
-- serait vert même si PERSONNE ne pouvait rien faire.
select essai.devenir(:VEILLEUR::uuid); set role authenticated;
do $$
declare combien int;
begin
  update public.commande_lignes set etat = 'vue' where etat = 'nouvelle';
  get diagnostics combien = row_count;
  if combien = 0 then
    perform essai.echec(
      'ÉCHEC : personne ne peut faire avancer — le constat d''à côté ne prouvait rien');
  end if;
  raise notice '  ok    le veilleur, lui, en fait avancer (%)', combien;
end $$;
reset role;

-- ---------------------------------------------------------
select essai.titre('Le catalogue et les boutiques suivent leurs propres interrupteurs');

select essai.devenir(:ADJOINT::uuid); set role authenticated;
select essai.verifie(public.peut_modifier_produits(),
  'l''adjoint, interrupteur allumé, retouche le catalogue');
select essai.verifie(public.administre('bou_informatique'),
  'et règle une boutique qui n''est pas la sienne — il n''en a aucune');
reset role;

select essai.devenir(:VEILLEUR::uuid); set role authenticated;
select essai.verifie(not public.peut_modifier_produits(),
  'le veilleur, NON : son interrupteur catalogue est éteint');
select essai.verifie(not public.administre('bou_informatique'),
  'et il ne règle aucune boutique');
-- Là encore, la base doit refuser et pas seulement l'écran.
do $$
declare combien int;
begin
  update public.produits set nom = nom || ' (touché)'
   where id = 'prod_hp15';
  get diagnostics combien = row_count;
  if combien > 0 then
    perform essai.echec('ÉCHEC : le veilleur a modifié ' || combien || ' produit(s)');
  end if;
  raise notice '  ok    et aucun produit ne change sous sa main (0)';
end $$;
reset role;

-- ---------------------------------------------------------
select essai.titre('Un compte d''enseigne ne nomme personne');

-- CE QUI LE TIENT : les règles de « profils » exigent une boutique NON
-- NULLE pour qu'un administrateur agisse. Un compte d'enseigne n'en a
-- pas — il en est donc exclu sans qu'on ait eu à l'écrire. Si cette
-- porte s'ouvrait un jour, un adjoint pourrait se nommer
-- superadministrateur, et l'enseigne changerait de mains.
select essai.devenir(:ADJOINT::uuid); set role authenticated;
select essai.refuse($$
  insert into public.profils (id, email, role, boutique_id, actif)
  values ('dddddddd-9999-9999-9999-999999999999'::uuid,
          'intrus@bizzoo.bj', 'superadministrateur', null, true)
$$, 'il ne se nomme pas un superadministrateur');

select essai.sans_effet($$
  update public.profils set role = 'superadministrateur'
   where id = 'dddddddd-1111-1111-1111-111111111111'::uuid
$$, 'et ne se promeut pas lui-même');
reset role;

select essai.egal(
  (select role from public.profils where id = :ADJOINT::uuid), 'administrateur',
  'il est resté administrateur');

-- ---------------------------------------------------------
select essai.titre('Le rejeu de schema.sql ne promeut plus personne');

-- LA LIGNE SURVEILLÉE. schema.sql disait, sans condition :
--     update profils set role = 'superadministrateur'
--      where role = 'administrateur' and boutique_id is null;
-- Elle décrit mot pour mot un administrateur de BIZZOO.
--
-- ON APPELLE LA VRAIE FONCTION, pas une copie. Une première version de
-- cet essai recopiait la garde ici : elle éprouvait donc sa propre
-- copie, et restait verte même après qu'on eut retiré la garde de
-- schema.sql. C'est pour cela que « rattraper_anciens_admins() » porte
-- un nom — pour qu'il y ait quelque chose à appeler.
select essai.egal(public.rattraper_anciens_admins(), 0,
  'le rattrapage ne touche personne : l''enseigne a déjà son maître');

select essai.egal(
  (select role from public.profils where id = :ADJOINT::uuid), 'administrateur',
  'l''adjoint n''est pas devenu maître de l''enseigne');
select essai.egal(
  (select count(*)::int from public.profils
    where role = 'superadministrateur'), 1,
  'et il n''y a toujours qu''un superadministrateur');

-- ---------------------------------------------------------
-- On remet le décor comme on l'a trouvé : les essais suivants
-- comptent les lignes, et « vue » en aurait déplacé.
update public.commande_lignes set etat = 'nouvelle' where etat = 'vue';
select essai.personne();
