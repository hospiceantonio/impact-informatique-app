-- =========================================================
-- Le lieu de chaque vendeur (3.78.0)
--
-- Ce qu'on prouve :
--   1. le lieu d'un vendeur (numéro, adresse, position, horaires) : le
--      superadministrateur l'écrit ; l'équipe et le vendeur le lisent ;
--      personne d'autre ; une position ou des horaires faux sont refusés ;
--   2. l'application des clients lit la position et les horaires de chaque
--      vendeur et ses produits — ni son numéro, ni son adresse ;
--   3. un vendeur fermé ne reçoit pas de commande ; les autres, si ;
--   4. la tournée part de CHAQUE VENDEUR, à sa position — jamais de celle
--      de la boutique multivendeur ; deux vendeurs = deux arrêts, deux
--      suppléments ; un vendeur sans position part du point BIZZOO ;
--   5. la commande garde ces arrêts ; le bon du livreur nomme chaque
--      vendeur, son adresse écrite, son numéro, sa position, ses articles ;
--   6. « Faire livrer » compte de même.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''
\set CHEF     '''22222222-2222-2222-2222-222222222222'''
\set ACHETEUR '''ffffffff-2222-2222-2222-222222222222'''
\set V1       '''c7c7c7c7-0000-0000-0000-000000000001'''
\set V2       '''c7c7c7c7-0000-0000-0000-000000000002'''

select essai.titre('Le décor : la boutique multivendeur, deux vendeurs, leurs produits');
update public.profils set role = 'vendeur', actif = true, boutique_id = null where id in (:V1::uuid, :V2::uuid);
update public.produits set stock = 20, disponible = true, masque = false
 where id in ('prod_v_a', 'prod_v_b', 'prod_v_c');
-- Au nom de l'enseigne : la position d'une boutique, le vendeur d'un
-- produit changent par elle.
create function pg_temp.comme_enseigne(q text) returns void language plpgsql as $$
begin
  perform essai.devenir('11111111-1111-1111-1111-111111111111'::uuid);
  set local role authenticated;
  execute q;
  reset role;
  perform essai.personne();
end $$;
-- La position de la boutique multivendeur : à NE JAMAIS utiliser pour un vendeur.
select pg_temp.comme_enseigne($$update public.boutiques set actif = true, ouvertures = null,
  latitude = 6.3000, longitude = 2.5000 where id = 'bou_vendeurs'$$);
select pg_temp.comme_enseigne(format($$update public.produits_prive set vendeur_id = %L, taux_vendeur = 80
  where produit_id = 'prod_v_a'$$, :V1));
select pg_temp.comme_enseigne(format($$update public.produits_prive set vendeur_id = %L, taux_vendeur = 75
  where produit_id = 'prod_v_b'$$, :V2));
update public.paiement
   set livraison_latitude = 6.3600, livraison_longitude = 2.3800, livraison_coef = 1.0,
       livraison_rayon_km = 2, moto_forfait = 600, moto_prix_km = 100, livraison_supplement_boutique = 200
 where id = 1;
delete from public.vendeurs_lieux where vendeur_id in (:V1::uuid, :V2::uuid);
-- Ouvert tous les jours ; fermé aujourd'hui (heure du Bénin).
create function pg_temp.horaires(ouvert_aujourdhui boolean) returns jsonb language sql as $$
  select jsonb_object_agg(j, jsonb_build_object('de', '00:00', 'a', '24:00'))
    from unnest(array['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim']) j
   where ouvert_aujourdhui
      or j <> (array['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'])
              [extract(isodow from now() at time zone 'Africa/Porto-Novo')::int];
$$;
create function pg_temp.lieu(qui uuid, cible uuid, l jsonb) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform essai.devenir(qui);
  set local role authenticated;
  r := public.enregistrer_lieu_vendeur(cible, l);
  reset role;
  perform essai.personne();
  return r;
end $$;

select essai.titre('1. Le lieu d''un vendeur : le superadministrateur l''écrit');
select pg_temp.lieu(:ENSEIGNE::uuid, :V1::uuid, jsonb_build_object('nom', '  Pagnes Afi  ', 'tel', '01 97 70 00 11',
  'adresse', 'Dantokpa, allée 4, porte bleue', 'latitude', 6.3700, 'longitude', 2.4300,
  'ouvertures', pg_temp.horaires(true))) as l \gset
select essai.egal(:'l'::jsonb ->> 'nom', 'Pagnes Afi', 'son nom de commerce, sans espaces autour');
select essai.egal(:'l'::jsonb ->> 'tel', '0197700011', 'son numéro, chiffres seuls');
select essai.egal((:'l'::jsonb ->> 'latitude') || ',' || (:'l'::jsonb ->> 'longitude'), '6.37,2.43', 'sa position');
select essai.refuse(format($$select pg_temp.lieu(%L::uuid, %L::uuid, '{"tel":"0100"}'::jsonb)$$, :CHEF, :V1),
  'l''administrateur d''une boutique ne l''écrit pas');
select essai.refuse(format($$select pg_temp.lieu(%L::uuid, %L::uuid, '{"latitude":6.4}'::jsonb)$$, :ENSEIGNE, :V1),
  'une latitude sans longitude : refusée');
select essai.refuse(format($$select pg_temp.lieu(%L::uuid, %L::uuid, '{"latitude":0,"longitude":0}'::jsonb)$$, :ENSEIGNE, :V1),
  'le point « 0, 0 » : refusé');
select essai.refuse(format($$select pg_temp.lieu(%L::uuid, %L::uuid, '{"ouvertures":{"lun":{"de":"19:00","a":"08:00"}}}'::jsonb)$$,
  :ENSEIGNE, :V1), 'des horaires à l''envers : refusés');
select essai.refuse(format($$select pg_temp.lieu(%L::uuid, %L::uuid, '{}'::jsonb)$$, :ENSEIGNE, :CHEF),
  'un compte qui n''est pas vendeur : refusé');
set role anon;
select essai.refuse(format($$select public.lieu_vendeur(%L::uuid)$$, :V1), 'un visiteur ne lit pas le lieu d''un vendeur');
select essai.refuse($$select count(*) from public.vendeurs_lieux$$, 'ni la table');
reset role;
select essai.devenir(:V1::uuid); set role authenticated;
select essai.egal(public.lieu_vendeur(:V1::uuid) ->> 'adresse', 'Dantokpa, allée 4, porte bleue',
  'le vendeur lit son propre lieu');
select essai.refuse(format($$select public.lieu_vendeur(%L::uuid)$$, :V2), 'pas celui d''un autre vendeur');
reset role; select essai.personne();

select essai.titre('2. L''application des clients : position et horaires, pas le numéro');
set role anon;
select public.points_retrait() as pts \gset
reset role;
select essai.verifie(exists (select 1 from jsonb_array_elements(:'pts'::jsonb) e
                              where e ->> 'id' = :V1 and e ->> 'nom' = 'Pagnes Afi'
                                and (e ->> 'latitude')::numeric = 6.37 and e -> 'produits' ? 'prod_v_a'),
  'Pagnes Afi, sa position, et « Pagne A » qui se récupère chez elle');
select essai.verifie(not exists (select 1 from jsonb_array_elements(:'pts'::jsonb) e
                                  where e ? 'tel' or e ? 'adresse'),
  'ni numéro ni adresse écrite pour le public');
select essai.verifie(exists (select 1 from jsonb_array_elements(:'pts'::jsonb) e
                              where e ->> 'id' = :V2 and e -> 'latitude' = 'null'::jsonb),
  'un vendeur sans lieu figure aussi, sans position');

select essai.titre('3. Un vendeur fermé ne reçoit pas de commande');
select pg_temp.lieu(:ENSEIGNE::uuid, :V2::uuid, jsonb_build_object('nom', 'Sacs Bio', 'tel', '0197700022',
  'ouvertures', pg_temp.horaires(false)));
select essai.verifie(not public.vendeur_ouvert(:V2::uuid), 'Sacs Bio est fermé aujourd''hui');
select essai.verifie(public.vendeur_ouvert(:V1::uuid), 'Pagnes Afi est ouverte');
create function pg_temp.commander(articles jsonb, dest jsonb) returns jsonb language plpgsql as $$
declare g jsonb;
begin
  perform essai.devenir('ffffffff-2222-2222-2222-222222222222'::uuid);
  set local role authenticated;
  g := public.creer_commande('{"nom":"Rosine","tel":"97666123","adresse":"Godomey"}'::jsonb,
    articles, '', true, true, dest);
  reset role;
  perform essai.personne();
  return g;
end $$;
select essai.refuse($$select pg_temp.commander('[{"produit_id":"prod_v_b","quantite":1}]'::jsonb,
  '{"latitude":6.45,"longitude":2.46}'::jsonb)$$, '« Sac B », vendu par Sacs Bio fermé : refusé');
select pg_temp.lieu(:ENSEIGNE::uuid, :V2::uuid, jsonb_build_object('nom', 'Sacs Bio', 'tel', '0197700022',
  'adresse', 'Missèbo, face à la pharmacie', 'ouvertures', pg_temp.horaires(true)));

select essai.titre('4. La tournée part de chaque vendeur, à SA position');
-- Les tronçons, comme si la route les avait donnés.
delete from public.distances_route where (o_lat, o_lng) in ((6.3700, 2.4300), (6.3600, 2.3800), (6.3000, 2.5000));
select public.devis_tournee(array['v:' || :V1, 'v:' || :V2], 6.45, 2.46, 'moto') as d \gset
select essai.egal((:'d'::jsonb ->> 'nb_boutiques')::int, 2, 'deux vendeurs : deux arrêts');
select essai.egal((:'d'::jsonb ->> 'supplements')::int, 400, 'deux suppléments : 2 × 200');
select essai.verifie(exists (select 1 from jsonb_array_elements(:'d'::jsonb -> 'tournee') e
                              where e ->> 'vendeur_id' = :V1 and e ->> 'nom' = 'Pagnes Afi'
                                and (e ->> 'latitude')::numeric = 6.37 and (e ->> 'longitude')::numeric = 2.43),
  'Pagnes Afi : depuis sa position (6,37 ; 2,43)');
select essai.verifie(exists (select 1 from jsonb_array_elements(:'d'::jsonb -> 'tournee') e
                              where e ->> 'vendeur_id' = :V2 and (e ->> 'sans_position')::boolean
                                and (e ->> 'latitude')::numeric = 6.36),
  'Sacs Bio, sans position : depuis le point BIZZOO en attendant');
select essai.verifie(not exists (select 1 from jsonb_array_elements(:'d'::jsonb -> 'tournee') e
                                  where (e ->> 'latitude')::numeric = 6.3 and (e ->> 'longitude')::numeric = 2.5),
  'jamais depuis la position de la boutique multivendeur');
select essai.egal((public.devis_tournee(array['v:' || :V1], 6.45, 2.46, 'moto') ->> 'supplements')::int, 0,
  'un seul vendeur : un seul arrêt, sans supplément');

select essai.titre('5. La commande garde ces arrêts ; le livreur sait chez qui aller');
select pg_temp.commander('[{"produit_id":"prod_v_a","quantite":2},{"produit_id":"prod_v_b","quantite":1}]'::jsonb,
  '{"latitude":6.45,"longitude":2.46}'::jsonb) ->> 'id' as c1 \gset
select livraison as liv from public.commandes where id = :'c1' \gset
select essai.egal((:'liv'::jsonb ->> 'frais')::int, (:'d'::jsonb ->> 'frais')::int,
  'les frais de la commande : ceux de la tournée des deux vendeurs');
select essai.egal(jsonb_array_length(:'liv'::jsonb -> 'tournee'), 2, 'deux arrêts gardés sur la commande');
select public.fiche_course(:'c1', 'bou_vendeurs') -> 'retrait' as r \gset
select essai.egal(jsonb_array_length(:'r'::jsonb -> 'vendeurs'), 2, 'le bon du livreur : deux vendeurs');
select essai.verifie(exists (select 1 from jsonb_array_elements(:'r'::jsonb -> 'vendeurs') v
                              where v ->> 'nom' = 'Pagnes Afi' and v ->> 'adresse' = 'Dantokpa, allée 4, porte bleue'
                                and v ->> 'tel' = '0197700011' and (v ->> 'latitude')::numeric = 6.37
                                and v -> 'articles' -> 0 ->> 'nom' = 'Pagne A'
                                and (v -> 'articles' -> 0 ->> 'quantite')::int = 2),
  'Pagnes Afi : son adresse écrite, son numéro, sa position, « Pagne A × 2 »');
select essai.verifie(exists (select 1 from jsonb_array_elements(:'r'::jsonb -> 'vendeurs') v
                              where v ->> 'nom' = 'Sacs Bio' and v ->> 'adresse' = 'Missèbo, face à la pharmacie'
                                and v -> 'latitude' = 'null'::jsonb),
  'Sacs Bio : son adresse écrite, sans position encore');
select essai.egal(jsonb_array_length(public.fiche_course(:'c1', 'bou_vendeurs') -> 'retrait' -> 'vendeurs'), 2,
  'et la fiche d''une course proposée les porte aussi (même fiche)');
select essai.egal(jsonb_array_length(coalesce(public.fiche_course(
    (select l.commande_id from public.commande_lignes l where l.boutique_id = 'bou_informatique' limit 1),
    'bou_informatique') -> 'retrait' -> 'vendeurs', '[]'::jsonb)), 0,
  'une boutique à vendeur unique : aucun vendeur sur le bon');

select essai.titre('6. « Faire livrer » compte de même');
create function pg_temp.devis(art jsonb, dest jsonb) returns jsonb language plpgsql as $$
declare g jsonb;
begin
  perform essai.devenir('11111111-1111-1111-1111-111111111111'::uuid);
  set local role authenticated;
  g := public.devis_faire_livrer(art, dest);
  reset role;
  perform essai.personne();
  return g;
end $$;
select essai.egal((pg_temp.devis('[{"produit_id":"prod_v_a","quantite":1},{"produit_id":"prod_v_b","quantite":1}]'::jsonb,
                                 '{"latitude":6.45,"longitude":2.46}'::jsonb) -> 'livraison' ->> 'frais')::int,
  (:'d'::jsonb ->> 'frais')::int, 'deux vendeurs : les mêmes frais que l''application');

update public.paiement set livraison_latitude = null, livraison_longitude = null,
       livraison_supplement_boutique = 0 where id = 1;
select pg_temp.comme_enseigne($$update public.boutiques set latitude = null, longitude = null
  where id = 'bou_vendeurs'$$);
