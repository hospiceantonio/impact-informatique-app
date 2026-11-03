-- =========================================================
-- La tournée : de boutique en boutique, puis au client (3.74.0)
--
-- Ce qu'on prouve :
--   1. la distance suit le trajet boutique A → boutique B → client, dans
--      l'ordre le plus court, que la base choisit ; l'exemple du gérant :
--      deux boutiques, 13 km, à moto = 1 000 + 3 × 100 + 2 × 200 = 1 700 ;
--   2. 200 FCFA par boutique, dès la première ; réglable (0 : aucun) ;
--   3. une boutique sans position compte depuis le point BIZZOO ;
--   4. sans boutique : du point BIZZOO, sans supplément, comme avant ;
--   5. trois boutiques : le meilleur des six ordres ; huit boutiques : de
--      la plus proche en plus proche ;
--   6. la commande fige la tournée ; le livreur lit l'itinéraire, les
--      frais, la part de BIZZOO et son gain.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''

select essai.titre('Le décor : le point BIZZOO, deux boutiques sur la carte');
update public.paiement
   set livraison_latitude = 6.3600, livraison_longitude = 2.3800, livraison_coef = 1.0,
       livraison_rayon_km = 10, moto_forfait = 1000, moto_prix_km = 100,
       tricycle_forfait = 4000, tricycle_prix_km = 500, livraison_supplement_boutique = 200
 where id = 1;
-- Au nom de l'enseigne : la position d'une boutique demande son accord.
create function pg_temp.placer(b text, la double precision, lo double precision) returns void language plpgsql as $$
begin
  perform essai.devenir('11111111-1111-1111-1111-111111111111'::uuid);
  set local role authenticated;
  update public.boutiques set latitude = la, longitude = lo, actif = true, ouvertures = null where id = b;
  reset role;
  perform essai.personne();
end $$;
select pg_temp.placer('bou_informatique', 6.4000, 2.4000);
select pg_temp.placer('bou_essai_voisine', 6.4100, 2.4300);
-- Les tronçons, comme si Google les avait rendus : A = informatique,
-- B = voisine, C = le client (6.4500, 2.4600).
delete from public.distances_route
 where (o_lat, o_lng) in ((6.4000, 2.4000), (6.4100, 2.4300));
insert into public.distances_route (o_lat, o_lng, d_lat, d_lng, distance_m) values
  (6.4000, 2.4000, 6.4100, 2.4300, 4000),    -- A → B
  (6.4100, 2.4300, 6.4000, 2.4000, 4000),    -- B → A
  (6.4100, 2.4300, 6.4500, 2.4600, 9000),    -- B → client
  (6.4000, 2.4000, 6.4500, 2.4600, 11000);   -- A → client
select essai.egal((select livraison_supplement_boutique from public.paiement where id = 1), 200,
  'le supplément par boutique naît à 200 FCFA');

select essai.titre('1. L''exemple du gérant : deux boutiques, 13 km, 1 700 FCFA');
select public.devis_tournee(array['bou_essai_voisine', 'bou_informatique'], 6.45, 2.46, 'moto') as d \gset
select essai.egal((:'d'::jsonb ->> 'distance_km')::numeric, 13.0, 'A → B → client : 4 + 9 = 13 km (et non B → A → client, 15 km)');
select essai.egal((:'d'::jsonb ->> 'km_factures')::int, 3, '3 km au-delà des 10 km');
select essai.egal((:'d'::jsonb ->> 'supplements')::int, 400, '2 boutiques × 200 = 400');
select essai.egal((:'d'::jsonb ->> 'frais')::int, 1700, '1 000 + 300 + 400 = 1 700 FCFA');
select essai.egal(:'d'::jsonb ->> 'calcul', 'route', 'chaque tronçon vient de la route');
select essai.egal((select string_agg(e ->> 'boutique_id', ' → ' order by o)
                     from jsonb_array_elements(:'d'::jsonb -> 'tournee') with ordinality x(e, o)),
  'bou_informatique → bou_essai_voisine', 'l''ordre : informatique d''abord, puis la voisine');
select essai.egal((:'d'::jsonb -> 'tournee' -> 0 ->> 'vers_suivante_km')::numeric, 4.0, 'le tronçon vers la suivante est dit');

-- Que le chemin le plus court change, et l'ordre suit.
update public.distances_route set distance_m = 1000 where (o_lat, o_lng, d_lat, d_lng) = (6.4100, 2.4300, 6.4000, 2.4000);
update public.distances_route set distance_m = 8000 where (o_lat, o_lng, d_lat, d_lng) = (6.4000, 2.4000, 6.4500, 2.4600);
select public.devis_tournee(array['bou_informatique', 'bou_essai_voisine'], 6.45, 2.46, 'moto') as d \gset
select essai.egal((select string_agg(e ->> 'boutique_id', ' → ' order by o)
                     from jsonb_array_elements(:'d'::jsonb -> 'tournee') with ordinality x(e, o)),
  'bou_essai_voisine → bou_informatique', 'B → A → client devient le plus court : l''ordre s''inverse');
select essai.egal((:'d'::jsonb ->> 'frais')::int, 1400, '1 + 8 = 9 km : 1 000 + 0 + 400 = 1 400 FCFA');

select essai.titre('2. Le supplément : dès la première boutique, et réglable');
select essai.egal((public.devis_tournee(array['bou_informatique'], 6.45, 2.46, 'moto') ->> 'frais')::int, 1200,
  'une boutique à 8 km : 1 000 + 200 = 1 200 FCFA');
select essai.egal((public.devis_tournee(array['bou_informatique', 'bou_essai_voisine'], 6.45, 2.46, 'tricycle') ->> 'frais')::int,
  4400, 'en tricycle : 4 000 + 0 + 400 = 4 400 FCFA');
update public.paiement set livraison_supplement_boutique = 0 where id = 1;
select essai.egal((public.devis_tournee(array['bou_informatique'], 6.45, 2.46, 'moto') ->> 'frais')::int, 1000,
  'supplément réglé à 0 : le forfait seul');
update public.paiement set livraison_supplement_boutique = 200 where id = 1;
select essai.refuse($$update public.paiement set livraison_supplement_boutique = -5 where id = 1$$,
  'un supplément négatif est refusé');
create function pg_temp.visiteur_change_supplement() returns int language plpgsql as $$
declare n int;
begin
  set local role anon;
  begin
    update public.paiement set livraison_supplement_boutique = 0 where id = 1;
    get diagnostics n = row_count;
  exception when others then n := -1;
  end;
  reset role;
  return n;
end $$;
select essai.verifie(pg_temp.visiteur_change_supplement() <= 0
                     and (select livraison_supplement_boutique from public.paiement where id = 1) = 200,
  'un visiteur ne touche pas au supplément');

select essai.titre('3. Une boutique sans position : depuis le point BIZZOO');
select pg_temp.placer('bou_essai_voisine', null, null);
select public.devis_tournee(array['bou_essai_voisine'], 6.45, 2.46, 'moto') as d \gset
select essai.verifie((:'d'::jsonb -> 'tournee' -> 0 ->> 'sans_position')::boolean, 'elle est marquée « sans position »');
select essai.egal(((:'d'::jsonb -> 'tournee' -> 0 ->> 'latitude')::numeric, (:'d'::jsonb -> 'tournee' -> 0 ->> 'longitude')::numeric)::text,
  '(6.360000,2.380000)', 'elle part du point BIZZOO');
select essai.egal((:'d'::jsonb ->> 'distance_km')::numeric,
  (public.devis_livraison(6.45, 2.46, 'moto') ->> 'distance_km')::numeric,
  'la même distance que depuis le point BIZZOO');
select essai.egal((:'d'::jsonb ->> 'frais')::int,
  (public.devis_livraison(6.45, 2.46, 'moto') ->> 'frais')::int + 200,
  'les frais d''avant, plus le supplément de la boutique');
select pg_temp.placer('bou_essai_voisine', 6.4100, 2.4300);

select essai.titre('4. Sans boutique : du point BIZZOO, sans supplément');
select essai.egal((public.devis_tournee('{}'::text[], 6.45, 2.46, 'moto') ->> 'frais')::int,
  (public.devis_livraison(6.45, 2.46, 'moto') ->> 'frais')::int, 'les frais d''avant, exactement');
select essai.egal(jsonb_array_length(public.devis_tournee(null, 6.45, 2.46, 'moto') -> 'tournee'), 0,
  'aucune étape à montrer');
select essai.refuse($$select public.devis_tournee(array['bou_informatique'], 0, 0, 'moto')$$,
  'une position absurde est refusée');
update public.paiement set livraison_latitude = null, livraison_longitude = null where id = 1;
select essai.verifie(public.devis_tournee(array['bou_informatique'], 6.45, 2.46, 'moto') is null,
  'sans point BIZZOO, pas de devis : la livraison au km n''est pas en service');
update public.paiement set livraison_latitude = 6.3600, livraison_longitude = 2.3800 where id = 1;

select essai.titre('5. Trois boutiques : le meilleur des six ordres ; huit : de proche en proche');
-- Sur une même ligne, vers l'est, le client au bout : l'ordre géographique
-- (qui n'est pas celui des identifiants) est le seul bon.
insert into public.boutiques (id, nom, secteur, devise, actif, ordre, latitude, longitude) values
  ('bou_th_c', 'Tournée C', 'hightech', 'FCFA', true, 90, 6.37, 2.40),
  ('bou_th_a', 'Tournée A', 'hightech', 'FCFA', true, 91, 6.37, 2.42),
  ('bou_th_b', 'Tournée B', 'hightech', 'FCFA', true, 92, 6.37, 2.41)
on conflict (id) do update set latitude = excluded.latitude, longitude = excluded.longitude;
select public.devis_tournee(array['bou_th_a', 'bou_th_b', 'bou_th_c'], 6.37, 2.45, 'moto') as d \gset
select essai.egal((select string_agg(e ->> 'nom', ' → ' order by o)
                     from jsonb_array_elements(:'d'::jsonb -> 'tournee') with ordinality x(e, o)),
  'Tournée C → Tournée B → Tournée A', 'C → B → A → client, d''ouest en est');
select essai.egal(:'d'::jsonb ->> 'calcul', 'vol_oiseau', 'sans route connue : à vol d''oiseau × coefficient');
select essai.verifie(abs((:'d'::jsonb ->> 'distance_km')::numeric - 5.5) <= 0.1,
  'la distance : de C au client, 0,05° ≈ 5,5 km (' || (:'d'::jsonb ->> 'distance_km') || ')');
insert into public.boutiques (id, nom, secteur, devise, actif, ordre, latitude, longitude)
select 'bou_tg' || k, 'Huit ' || k, 'hightech', 'FCFA', true, 100 + k, 6.37, 2.40 + (9 - k) * 0.005
  from generate_series(1, 8) k
on conflict (id) do update set latitude = excluded.latitude, longitude = excluded.longitude;
select public.devis_tournee(array(select 'bou_tg' || k from generate_series(1, 8) k), 6.37, 2.50, 'moto') as d \gset
select essai.egal((select string_agg(e ->> 'nom', ',' order by o)
                     from jsonb_array_elements(:'d'::jsonb -> 'tournee') with ordinality x(e, o)),
  'Huit 8,Huit 7,Huit 6,Huit 5,Huit 4,Huit 3,Huit 2,Huit 1', 'huit boutiques : d''ouest en est, de proche en proche');
select essai.egal((:'d'::jsonb ->> 'supplements')::int, 1600, '8 × 200 = 1 600');
delete from public.boutiques where id like 'bou_tg%' or id like 'bou_th_%';

select essai.titre('6. La commande fige la tournée ; le livreur la lit');
insert into public.produits (id, boutique_id, nom, prix, sous_categorie_id, stock, disponible) values
  ('prod_tr_a', 'bou_informatique', 'Clavier tournée', 5000, 'sc_hightech_accessoires', 50, true),
  ('prod_tr_b', 'bou_essai_voisine', 'Lampe tournée', 4000, 'sc_hightech_accessoires', 50, true)
on conflict (id) do update set stock = 50, disponible = true, masque = false;
create function pg_temp.commander(articles jsonb, dest jsonb) returns jsonb language plpgsql as $$
declare g jsonb;
begin
  perform essai.devenir('ffffffff-2222-2222-2222-222222222222'::uuid);
  set local role authenticated;
  g := public.creer_commande('{"nom":"Rosine","tel":"97666088","adresse":"Godomey"}'::jsonb,
    articles, '', true, true, dest);
  reset role;
  perform essai.personne();
  return g;
end $$;
select pg_temp.commander('[{"produit_id":"prod_tr_a","quantite":1},{"produit_id":"prod_tr_b","quantite":1}]'::jsonb,
  '{"latitude":6.45,"longitude":2.46}'::jsonb) ->> 'id' as cmd \gset
select essai.egal((select frais_livraison from public.commandes where id = :'cmd')::int, 1400,
  'la commande fige les frais de la tournée (1 400 FCFA)');
select essai.egal((select jsonb_array_length(livraison -> 'tournee') from public.commandes where id = :'cmd'), 2,
  'et ses deux étapes');
select public.fiche_demande(:'cmd') as f \gset
select essai.egal((select string_agg(r ->> 'boutique_id', ' → ' order by o)
                     from jsonb_array_elements(:'f'::jsonb -> 'retraits') with ordinality x(r, o)),
  'bou_essai_voisine → bou_informatique', 'le livreur lit les boutiques dans l''ordre de passage');
select essai.verifie(public.texte_demande(:'f'::jsonb) like '%Itinéraire : Boutique voisine → Informatique → client%'
                     or public.texte_demande(:'f'::jsonb) ~ 'Itinéraire : .+ → .+ → client',
  'l''alerte dit l''itinéraire : « Itinéraire : … → … → client »');
select essai.verifie(public.texte_demande(:'f'::jsonb) ~ 'Frais de livraison : 1 400',
  'l''alerte dit les frais de la course');
select essai.verifie(public.texte_demande(:'f'::jsonb) ~ 'Votre gain : 1 120'
                     and public.texte_demande(:'f'::jsonb) ~ 'Part BIZZOO : 280',
  'et ce qui revient à chacun : 1 120 au livreur (80 %), 280 à BIZZOO');

update public.paiement set livraison_latitude = null, livraison_longitude = null, livraison_coef = 1.3,
       livraison_supplement_boutique = 200 where id = 1;
