-- =========================================================
-- Le journal des versements : ce qu'il garde, et qui peut y
-- toucher.
--
-- La commande ne garde que son état ACTUEL. Le journal, lui,
-- garde le chemin — et c'est tout son intérêt : « combien
-- d'échecs cette semaine », « chez quel opérateur ».
--
-- Cinq choses à prouver :
--
--   1. UNE LIGNE PAR TENTATIVE. Trois essais laissent trois
--      lignes. Un journal qui se met à jour ne garderait que
--      la fin de l'histoire — et la fin est déjà sur la
--      commande ;
--   2. LA RÉUSSITE N'EFFACE PAS LES ÉCHECS. « marquer_payee »
--      efface la remarque de la commande en réussissant :
--      sans le journal, un encaissement effaçait la trace de
--      ses propres ratés ;
--   3. PERSONNE NE L'ÉCRIT À LA MAIN, pas même l'enseigne. Un
--      journal qu'on peut retoucher ne prouve rien le jour où
--      il faudrait qu'il prouve quelque chose ;
--   4. IL NE SORT PAS DE L'ENSEIGNE. C'est l'argent de BIZZOO
--      qui transite, pas celui d'une boutique ;
--   5. IL SURVIT À LA COMMANDE. Effacer une commande ne doit
--      pas effacer la trace de l'argent.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set KOFI     '''55555555-5555-5555-5555-555555555555'''

select essai.titre('Le décor : une commande, et trois tentatives');

insert into public.produits
  (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_versement', 'bou_informatique', 'Onduleur 650 VA', 30000,
        'sc_hightech_accessoires', 50, true)
on conflict (id) do update
   set prix = excluded.prix, stock = 50, disponible = true;

select essai.devenir(:KOFI::uuid);
set role authenticated;
select public.creer_commande('{"nom":"Kofi","tel":"97222222"}'::jsonb,
  '[{"produit_id":"prod_versement","quantite":1}]'::jsonb) ->> 'id' as vente \gset
reset role;
select essai.personne();

select essai.egal((select total::int from public.commandes where id = :'vente'),
  30000, 'la commande vaut 30 000');

-- Première tentative : la demande part chez MTN.
select public.noter_reference(:'vente', 'REF-MTN-1', 'feexpay', 'MTN') as ouverte1 \gset
select essai.verifie(:'ouverte1'::boolean, 'la demande part chez MTN');

select essai.egal((select count(*)::int from public.versements
                    where commande_id = :'vente'), 1,
  'et le journal en garde une ligne');
select essai.egal((select reseau from public.versements
                    where commande_id = :'vente'), 'MTN',
  'avec l''opérateur — qu''on ne saura plus ensuite');
select essai.egal((select fournisseur from public.versements
                    where commande_id = :'vente'), 'feexpay',
  'et l''agrégateur qui a ouvert');
select essai.egal((select attendu from public.versements
                    where commande_id = :'vente'), 30000::bigint,
  'et ce qu''on attendait');

-- ---------------------------------------------------------
select essai.titre('Un versement incomplet se note, et ne paie pas');
-- ---------------------------------------------------------
-- Le frein de trente secondes n'existe que pour les DEMANDES : constater
-- un versement ne fait sonner aucun téléphone.
select public.marquer_payee(:'vente', 'TRX-PARTIEL', 12000, 'feexpay') as r1 \gset

select essai.egal((select etat from public.commandes where id = :'vente'),
  'a_payer', 'la commande n''est PAS payée');
select essai.egal((select count(*)::int from public.versements
                    where commande_id = :'vente'), 2,
  'et le journal a sa deuxième ligne');
select essai.egal((select verdict from public.versements
                    where commande_id = :'vente' order by id desc limit 1),
  'incomplete', 'marquée « incomplete »');
select essai.egal((select recu from public.versements
                    where commande_id = :'vente' order by id desc limit 1),
  12000::bigint, 'avec ce qui est réellement entré');
-- L'OPÉRATEUR EST REPRIS TOUT SEUL. Ni la notification ni la
-- vérification ne le rappellent : sans cette reprise, la moitié du
-- journal serait muette sur la question qu'on lui pose.
select essai.egal((select reseau from public.versements
                    where commande_id = :'vente' order by id desc limit 1),
  'MTN', 'et l''opérateur repris de la ligne d''ouverture');

-- ---------------------------------------------------------
select essai.titre('La réussite n''efface pas les échecs');
-- ---------------------------------------------------------
-- LE CONSTAT. « marquer_payee » efface la remarque de la commande en
-- réussissant. Avant le journal, l'encaissement effaçait donc la trace
-- de ses propres ratés.
select public.marquer_payee(:'vente', 'TRX-COMPLET', 30000, 'feexpay') as r2 \gset

select essai.egal((select etat from public.commandes where id = :'vente'),
  'payee', 'la commande est payée');
select essai.egal((select remarque from public.commandes where id = :'vente'),
  '', 'et sa remarque a bien été effacée');
select essai.egal((select count(*)::int from public.versements
                    where commande_id = :'vente'), 3,
  'mais les TROIS lignes du journal sont là');
select essai.egal((select count(*)::int from public.versements
                    where commande_id = :'vente' and verdict = 'incomplete'), 1,
  'y compris le versement incomplet, que la commande ne dit plus');
select essai.egal((select recu from public.versements
                    where commande_id = :'vente' and verdict = 'payee'),
  30000::bigint, 'et l''encaissement porte son montant');

-- ---------------------------------------------------------
select essai.titre('Un versement sans commande se note aussi');
-- ---------------------------------------------------------
-- De l'argent arrivé pour une commande introuvable est exactement ce
-- qu'un journal doit montrer : sinon il disparaît sans laisser de trace.
select public.marquer_payee('commande-qui-n-existe-pas', 'TRX-ORPHELIN',
  5000, 'kkiapay') as r3 \gset
select essai.egal((select count(*)::int from public.versements
                    where transaction_id = 'TRX-ORPHELIN' and verdict = 'inconnue'), 1,
  'le versement orphelin laisse sa ligne');
select essai.egal((select fournisseur from public.versements
                    where transaction_id = 'TRX-ORPHELIN'), 'kkiapay',
  'avec l''agrégateur qui l''a annoncé');

-- ---------------------------------------------------------
select essai.titre('Personne n''écrit le journal à la main');
-- ---------------------------------------------------------
-- Pas même l'enseigne. Un journal qu'on peut retoucher ne prouve rien
-- le jour où il faudrait qu'il prouve quelque chose.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.refuse(
  $$insert into public.versements (numero, verdict, recu)
    values ('BZ-FAUX', 'payee', 999999)$$,
  'l''enseigne ajoute une ligne au journal');
select essai.refuse(
  $$update public.versements set recu = 1 where verdict = 'payee'$$,
  'ou retouche un montant déjà écrit');
select essai.refuse(
  $$delete from public.versements where verdict = 'incomplete'$$,
  'ou efface un échec qui la gêne');
-- Elle LIT, en revanche : c'est tout ce qu'on lui accorde.
select essai.verifie(
  (select count(*) > 0 from public.versements_liste()),
  'mais elle lit le journal');
reset role;
select essai.personne();

-- Et l'écriture ne s'ouvre pas non plus par la fonction du serveur.
set role authenticated;
select essai.refuse(
  $$select public.noter_versement('x', 'payee', 'feexpay', 'MTN', '', '', 1, 1, '')$$,
  'un compte connecté écrit par la fonction du serveur');
reset role;
set role anon;
select essai.refuse($$select count(*) from public.versements$$,
  'un visiteur lit le journal');
select essai.refuse($$select count(*) from public.versements_liste()$$,
  'ou passe par la fonction de lecture');
reset role;

-- ---------------------------------------------------------
select essai.titre('Le journal ne sort pas de l''enseigne');
-- ---------------------------------------------------------
-- C'est l'argent de BIZZOO qui transite. Une boutique voit ses ventes
-- encaissées dans « statistiques_boutique » ; par quel opérateur le
-- client a payé ne la regarde pas.
select essai.devenir(:CHEF::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.versements), 0,
  'un chef de boutique ne lit aucune ligne');
select essai.egal((select count(*)::int from public.versements_liste()), 0,
  'ni par la fonction de lecture');
select essai.egal((select count(*)::int from public.versements_resume()), 0,
  'ni le résumé');
reset role;
select essai.personne();

select essai.devenir(:KOFI::uuid);
set role authenticated;
select essai.egal((select count(*)::int from public.versements_liste()), 0,
  'un client non plus, même pour ses propres versements');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Le résumé ne compte que ce qui est entré');
-- ---------------------------------------------------------
-- LE PIÈGE. Additionner les tentatives ferait un chiffre d'affaires
-- imaginaire : ici 30 000 encaissés, mais 72 000 en tout si l'on
-- additionnait l'ouverture, l'incomplet et l'encaissement.
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.egal(
  (select sum(total)::bigint from public.versements_resume()
    where fournisseur = 'feexpay' and reseau = 'MTN'),
  30000::bigint,
  'seul l''encaissement compte dans le total');
select essai.egal(
  (select combien from public.versements_resume()
    where verdict = 'incomplete' and reseau = 'MTN'), 1::bigint,
  'et les échecs se comptent à part');
-- La liste se borne par dates, comme les statistiques.
select essai.verifie(
  (select count(*) > 0 from public.versements_liste(current_date, current_date)),
  'la période du jour contient les versements du jour');
select essai.egal(
  (select count(*)::int from public.versements_liste(current_date + 1, current_date + 30)), 0,
  'et pas ceux de demain');
-- Un verdict inconnu ne rend RIEN plutôt que tout : se tromper de mot
-- ne doit pas laisser croire que la période est vide.
select essai.egal(
  (select count(*)::int from public.versements_liste(null, null, 'nimportequoi')), 0,
  'un verdict qui n''existe pas ne rend rien');
select essai.verifie(
  (select count(*) > 0 from public.versements_liste(null, null, 'tout')),
  'et « tout » rend tout');
reset role;
select essai.personne();

-- ---------------------------------------------------------
select essai.titre('Le journal survit à la commande effacée');
-- ---------------------------------------------------------
-- Pas de clé étrangère vers « commandes », et c'est voulu : effacer une
-- commande ne doit pas effacer la trace de l'argent. Le numéro est
-- recopié dans le journal pour que la ligne se lise encore toute seule.
select numero as num_efface from public.commandes where id = :'vente' \gset
delete from public.commandes where id = :'vente';

select essai.egal((select count(*)::int from public.versements
                    where numero = :'num_efface'), 3,
  'les trois lignes sont toujours là');
select essai.egal((select numero from public.versements
                    where numero = :'num_efface' limit 1), :'num_efface',
  'et chacune porte encore le numéro de la commande');
