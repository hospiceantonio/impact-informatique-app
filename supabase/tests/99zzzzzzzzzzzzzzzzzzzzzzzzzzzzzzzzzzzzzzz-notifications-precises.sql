-- =========================================================
-- Chaque notification mène à l'écran exact (3.73.0)
--
-- Les essais d'avant ont fait vivre la place de marché : courses
-- proposées, demandes de reversement, comptes à valider, ruptures de
-- stock. On relit ce qu'ils ont laissé dans les notifications :
--   1. une course proposée mène à CETTE course ;
--   2. une demande de reversement à CETTE demande, qui existe ;
--   3. un compte à valider (ou validé) à la fiche de CE compte ;
--   4. une rupture d'UN produit à la fiche de CE produit ; de plusieurs,
--      à la liste du stock ;
--   5. aucun lien n'est vide, et tous sont des adresses internes.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

select essai.titre('1. Une course proposée mène à CETTE course');
select essai.verifie((select count(*) from public.notifications where type = 'course_proposee') > 0,
  'le décor : des courses ont été proposées (' ||
  (select count(*) from public.notifications where type = 'course_proposee') || ')');
select essai.egal((select count(*)::int from public.notifications
                    where type = 'course_proposee' and lien is distinct from '#/livraisons/' || commande_id), 0,
  'chacune porte « #/livraisons/<sa commande> »');

select essai.titre('2. Une demande de reversement mène à CETTE demande');
-- Une demande de chaque sorte, si les essais d'avant n'en ont pas laissé.
select essai.verifie((select count(*) from public.notifications where type = 'reversement_demande') > 0,
  'le décor : des demandes de reversement (' ||
  (select count(*) from public.notifications where type = 'reversement_demande') || ')');
select essai.egal((select count(*)::int from public.notifications
                    where type = 'reversement_demande' and lien !~ '^#/reversements/(boutique|livreur|vendeur)-[0-9]+$'), 0,
  'chacune porte « #/reversements/<sorte>-<numéro> »');
select essai.egal((select count(*)::int from public.notifications n
                    where n.type = 'reversement_demande'
                      and not case split_part(substr(n.lien, 16), '-', 1)
                        when 'boutique' then exists (select 1 from public.reversements r
                                                      where r.id = split_part(n.lien, '-', 2)::bigint)
                        when 'livreur' then exists (select 1 from public.reversements_livreurs r
                                                      where r.id = split_part(n.lien, '-', 2)::bigint)
                        when 'vendeur' then exists (select 1 from public.reversements_vendeurs r
                                                      where r.id = split_part(n.lien, '-', 2)::bigint)
                        else false end), 0,
  'et la demande nommée existe bien, dans la bonne liste');
select essai.verifie(exists (select 1 from public.notifications where type = 'reversement_demande'
                               and lien like '#/reversements/livreur-%'),
  'celle d''un livreur mène à la liste des livreurs');

select essai.titre('3. Un compte à valider mène à la fiche de CE compte');
select essai.verifie((select count(*) from public.notifications where type in ('compte_a_valider', 'compte_valide')) > 0,
  'le décor : des comptes à valider (' ||
  (select count(*) from public.notifications where type in ('compte_a_valider', 'compte_valide')) || ')');
select essai.egal((select count(*)::int from public.notifications n
                    where n.type in ('compte_a_valider', 'compte_valide')
                      and not (n.lien ~ '^#/comptes/[0-9a-f-]{36}$'
                               and exists (select 1 from public.profils p where p.id::text = substr(n.lien, 11)))), 0,
  'chacun porte « #/comptes/<son identifiant> », d''un compte qui existe');

select essai.titre('4. Une rupture : la fiche du produit ; plusieurs : le stock');
-- Deux commandes payées : l'une épuise UN produit, l'autre DEUX d'un coup.
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible)
values ('prod_np1', 'bou_informatique', 'Souris NP', 3000, 'sc_hightech_accessoires', 1, true),
       ('prod_np2', 'bou_informatique', 'Clé NP', 2000, 'sc_hightech_accessoires', 1, true),
       ('prod_np3', 'bou_informatique', 'Câble NP', 1000, 'sc_hightech_accessoires', 1, true)
on conflict (id) do update set stock = 1, disponible = true, masque = false;
update public.boutiques set actif = true, ouvertures = null where id = 'bou_informatique';
create function pg_temp.payer(articles jsonb, trx text) returns text language plpgsql as $$
declare v_id text;
begin
  perform essai.devenir('ffffffff-2222-2222-2222-222222222222'::uuid);
  set local role authenticated;
  v_id := public.creer_commande('{"nom":"Rosine","tel":"97666099","adresse":"Godomey"}'::jsonb,
    articles, '', true, false) ->> 'id';
  reset role;
  perform essai.personne();
  perform public.marquer_payee(v_id, trx,
    (select coalesce(c.acompte, c.total)::int from public.commandes c where c.id = v_id), 'feexpay');
  return v_id;
end $$;
select pg_temp.payer('[{"produit_id":"prod_np1","quantite":1}]'::jsonb, 'TRX-NP-1') as c1 \gset
select pg_temp.payer('[{"produit_id":"prod_np2","quantite":1},{"produit_id":"prod_np3","quantite":1}]'::jsonb,
  'TRX-NP-2') as c2 \gset
select essai.egal((select string_agg(distinct lien, ',') from public.notifications
                    where type = 'stock_epuise' and commande_id = :'c1'), '#/produit/prod_np1',
  'un seul produit épuisé : sa fiche');
select essai.egal((select string_agg(distinct lien, ',') from public.notifications
                    where type = 'stock_epuise' and commande_id = :'c2'), '#/stock?filtre=rupture',
  'deux d''un coup : la liste des ruptures');

select essai.titre('5. Aucun lien vide, que des adresses internes');
select essai.egal((select count(*)::int from public.notifications
                    where cree_le > now() - interval '1 hour' and coalesce(lien, '') !~ '^#/'), 0,
  'toutes les notifications de ces essais portent une adresse « #/… »');
