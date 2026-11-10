-- =========================================================
-- L'espace du vendeur (3.80.0)
--
-- Ce qu'on prouve :
--   1. le vendeur met SON produit « Non disponible » : il ne se commande
--      plus (message clair) ; un autre vendeur, un visiteur ne le peuvent
--      pas ; « Disponible » le rend commandable ;
--   2. une commande payée qui contient ses produits le prévient, avec ce
--      qu'il a à préparer ;
--   3. son espace donne la photo et l'état de chaque produit ;
--   4. il change son nom affiché, et seulement le sien.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set V1       '''c7c7c7c7-0000-0000-0000-000000000001'''
\set V2       '''c7c7c7c7-0000-0000-0000-000000000002'''

select essai.titre('Le décor : la boutique multivendeur de l''essai « lieux-vendeurs »');
delete from public.vendeurs_lieux where vendeur_id in (:V1::uuid, :V2::uuid);
update public.produits set stock = 20, disponible = true, masque = false, en_pause = false,
       images = array['vendeurs/pagne-a.jpg']
 where id = 'prod_v_a';
update public.boutiques set actif = true, ouvertures = null where id = 'bou_vendeurs';
create function pg_temp.comme(qui uuid, q text) returns text language plpgsql as $$
declare r text;
begin
  perform essai.devenir(qui);
  set local role authenticated;
  execute q into r;
  reset role;
  perform essai.personne();
  return r;
end $$;
create function pg_temp.commander(articles jsonb) returns jsonb language plpgsql as $$
declare g jsonb;
begin
  perform essai.devenir('ffffffff-2222-2222-2222-222222222222'::uuid);
  set local role authenticated;
  g := public.creer_commande('{"nom":"Aïcha","tel":"97666321","adresse":"Dantokpa"}'::jsonb,
    articles, '', true, true);
  reset role;
  perform essai.personne();
  return g;
end $$;

select essai.titre('1. « Non disponible » : visible, mais ne se commande pas');
select pg_temp.comme(:V1::uuid, $$select public.vendeur_produit_disponible('prod_v_a', false)::text$$);
select essai.verifie((select en_pause and en_pause_le is not null from public.produits where id = 'prod_v_a'),
  'Pagnes Afi met « Pagne A » non disponible');
select essai.verifie((select not masque from public.produits where id = 'prod_v_a'),
  'il n''est pas masqué : les clients le voient toujours');
select essai.refuse($$select pg_temp.commander('[{"produit_id":"prod_v_a","quantite":1}]'::jsonb)$$,
  'une commande qui le contient : refusée');
select essai.refuse(format($$select pg_temp.comme(%L::uuid, 'select public.vendeur_produit_disponible(''prod_v_a'', true)::text')$$, :V2),
  'un autre vendeur ne touche pas à ses produits');
set role anon;
select essai.refuse($$select public.vendeur_produit_disponible('prod_v_a', true)$$, 'un visiteur non plus');
reset role;
select pg_temp.comme(:V1::uuid, $$select public.vendeur_produit_disponible('prod_v_a', true)::text$$);
select essai.verifie((select not en_pause and en_pause_le is null from public.produits where id = 'prod_v_a'),
  '« Disponible » : il se commande de nouveau');

select essai.titre('2. Une commande payée le prévient');
select pg_temp.commander('[{"produit_id":"prod_v_a","quantite":2}]'::jsonb) as g \gset
select public.marquer_payee(:'g'::jsonb ->> 'id', 'TRX-VENDEUR-1', (:'g'::jsonb ->> 'acompte')::int, 'feexpay') as p \gset
select essai.verifie(exists (select 1 from public.notifications
                              where destinataire = :V1::uuid and commande_id = :'g'::jsonb ->> 'id'
                                and type = 'commande_payee' and sonne and lien = '#/ventes'
                                and corps like '%2 × Pagne A%'),
  'Pagnes Afi reçoit « Nouvelle commande : 2 × Pagne A », qui sonne et ouvre son espace');
select essai.verifie(not exists (select 1 from public.notifications
                                  where destinataire = :V2::uuid and commande_id = :'g'::jsonb ->> 'id'),
  'pas Sacs Bio, qui n''y vend rien');

select essai.titre('3. Son espace : la photo et l''état de chaque produit');
select pg_temp.comme(:V1::uuid, $$select public.espace_vendeur()::text$$) as esp \gset
select essai.verifie(exists (select 1 from jsonb_array_elements(:'esp'::jsonb -> 'produits') p
                              where p ->> 'id' = 'prod_v_a' and p ->> 'image' = 'vendeurs/pagne-a.jpg'
                                and p -> 'en_pause' = 'false'::jsonb),
  'la photo de « Pagne A », et « disponible »');

select essai.titre('4. Son nom affiché');
select essai.egal(pg_temp.comme(:V1::uuid, $$select public.modifier_mon_nom('  Afi   Pagnes  ')$$), 'Afi Pagnes',
  'il change son nom, espaces superflus ôtés');
select essai.egal((select nom from public.profils where id = :V1::uuid), 'Afi Pagnes', 'sa fiche le garde');
select essai.refuse(format($$select pg_temp.comme(%L::uuid, 'select public.modifier_mon_nom(''A'')')$$, :V1),
  'un nom d''une lettre : refusé');
set role anon;
select essai.refuse($$select public.modifier_mon_nom('Quelqu''un')$$, 'un visiteur : refusé');
reset role;
update public.profils set nom = 'Pagnes Afi' where id = :V1::uuid;
