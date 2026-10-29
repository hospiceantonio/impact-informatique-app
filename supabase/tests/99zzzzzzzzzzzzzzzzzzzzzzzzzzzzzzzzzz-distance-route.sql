-- =========================================================
-- (3.70.0) La distance PAR LA ROUTE
--
--   1. personne d'autre que le serveur n'écrit ni ne lit le cache des
--      distances (ni visiteur, ni client, ni l'enseigne elle-même) ;
--   2. sans distance de route, le devis reste à vol d'oiseau × 1,3 ;
--   3. avec, il prend le trajet réel — à 50 m près, pas plus loin ;
--   4. déplacer le point BIZZOO rend les anciennes distances caduques ;
--   5. le plafond du jour protège la facture Google.
-- La commande fige ses frais par ce même « devis_livraison »
-- (creer_commande l'appelle) : éprouver le devis, c'est éprouver ses frais.
-- =========================================================
\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set ENSEIGNE '''11111111-1111-1111-1111-111111111111'''

-- Le décor : le point BIZZOO, les tarifs de départ.
update public.paiement set livraison_latitude = 6.3654, livraison_longitude = 2.4183,
       livraison_rayon_km = 10, livraison_coef = 1.3, moto_forfait = 1000, moto_prix_km = 100,
       tricycle_forfait = 4000, tricycle_prix_km = 500 where id = 1;
delete from public.distances_route;

select essai.titre('1. Le cache des distances : au serveur seulement');
set role anon;
select essai.refuse($$select * from public.distances_route$$, 'un visiteur lit le cache');
select essai.refuse($$select public.enregistrer_route(6.45, 2.42, 100)$$,
  'un visiteur écrit une distance (pour payer moins)');
select essai.refuse($$select public.route_connue(6.45, 2.42)$$, 'ou interroge le cache');
reset role;
select essai.devenir(:ENSEIGNE::uuid);
set role authenticated;
select essai.refuse($$insert into public.distances_route (o_lat, o_lng, d_lat, d_lng, distance_m)
                      values (6.3655, 2.4185, 6.45, 2.42, 100)$$,
  'l''enseigne elle-même n''écrit pas une distance à la main');
select essai.refuse($$select public.enregistrer_route(6.45, 2.42, 100)$$,
  'ni par la fonction du serveur');
reset role;
select essai.personne();

select essai.titre('2. Sans distance de route : vol d''oiseau × 1,3, comme avant');
select essai.egal((select (d ->> 'distance_km') || '/' || (d ->> 'calcul') || '/' || (d ->> 'frais')
                     from (select public.devis_livraison(6.458099, 2.4183, 'moto') d) x),
  '13.4/vol_oiseau/1400', '13,4 km estimés : 1 400');

select essai.titre('3. Avec la distance de route : le trajet réel');
set role service_role;
select essai.egal(public.route_connue(6.458099, 2.4183) ->> 'distance_m', null,
  'le serveur demande : rien de connu pour ce client');
select essai.egal((public.enregistrer_route(6.458099, 2.4183, 18450) ->> 'ok')::boolean, true,
  'le serveur écrit ce que Google a rendu : 18,45 km');
select essai.egal((public.route_connue(6.4581, 2.41832) ->> 'distance_m')::int, 18450,
  'à quelques mètres près, c''est la même adresse');
reset role;
select essai.egal((select (d ->> 'distance_km') || '/' || (d ->> 'calcul') || '/' || (d ->> 'km_factures') || '/' || (d ->> 'frais')
                     from (select public.devis_livraison(6.458099, 2.4183, 'moto') d) x),
  '18.5/route/9/1900', 'par la route, 18,45 km : 9 km entamés au-delà de 10, 1 900');
select essai.egal(public.devis_livraison(6.4600, 2.4183, 'moto') ->> 'calcul', 'vol_oiseau',
  'à 200 m de là, ce n''est plus la même adresse : vol d''oiseau');
set role service_role;
select essai.refuse($$select public.enregistrer_route(6.45, 2.42, 0)$$, 'une distance nulle : refusée');
select essai.refuse($$select public.enregistrer_route(6.45, 2.42, 2000000)$$, 'deux mille kilomètres : refusés');
reset role;

select essai.titre('4. Le point BIZZOO déplacé : les anciennes distances ne valent plus');
update public.paiement set livraison_latitude = 6.3700 where id = 1;
select essai.egal(public.devis_livraison(6.458099, 2.4183, 'moto') ->> 'calcul', 'vol_oiseau',
  'nouveau point : la distance d''avant ne sert plus');
update public.paiement set livraison_latitude = 6.3654 where id = 1;
select essai.egal(public.devis_livraison(6.458099, 2.4183, 'moto') ->> 'calcul', 'route',
  'le point revenu : elle resservirait');

select essai.titre('5. Le plafond du jour protège la facture Google');
insert into public.distances_route (o_lat, o_lng, d_lat, d_lng, distance_m)
select 6.3655, 2.4185, 7 + g / 2000.0, 2.5, 1000 from generate_series(1, 1000) g;
set role service_role;
select essai.egal((public.route_connue(6.30, 2.30) ->> 'plafond_atteint')::boolean, true,
  'mille appels nouveaux aujourd''hui : le suivant n''ira pas chez Google');
select essai.egal((public.route_connue(6.458099, 2.4183) ->> 'plafond_atteint')::boolean, false,
  'une adresse déjà connue, elle, reste servie');
reset role;
delete from public.distances_route where d_lng = 2.5;

-- Le décor rendu : le point retiré, les autres essais retrouvent les frais
-- par boutique.
delete from public.distances_route;
update public.paiement set livraison_latitude = null, livraison_longitude = null where id = 1;
