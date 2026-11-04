-- =========================================================
-- Le nom des lieux, et les frais de « Faire livrer » (3.76.0)
--
-- Ce qu'on prouve :
--   1. le nom d'un point est rangé à 50 m près : un point voisin le
--      retrouve, un point plus loin non ;
--   2. personne d'autre que la fonction serveur n'y lit ni n'écrit
--      (ni visiteur, ni compte connecté) ;
--   3. un plafond par jour protège la source : atteint, la base le dit ;
--      un nom déjà connu reste servi ;
--   4. « Faire livrer » : avec le point de livraison, le devis donne les
--      frais au kilomètre, comme pour une commande de l'application ;
--      sans point (ou un point faux), rien — les frais restent à saisir.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set SUPER '''11111111-1111-1111-1111-111111111111'''

select essai.titre('1. Un nom, rangé à 50 m près');
delete from public.lieux_noms;
delete from public.lieux_recherches;
select essai.verifie(public.lieu_connu(6.3910, 2.3600) ->> 'nom' is null, 'rien de connu au départ');
select essai.egal(public.lieu_connu(6.3910, 2.3600) ->> 'plafond_atteint', 'false', 'et le plafond est loin');
select essai.verifie(public.noter_lieu(6.3910, 2.3600, '  Sèdomey, Togoudo, Godomey  '), 'la source a répondu : noté');
select essai.egal(public.lieu_connu(6.3910, 2.3600) ->> 'nom', 'Sèdomey, Togoudo, Godomey', 'retrouvé, sans les espaces');
select essai.egal(public.lieu_connu(6.39115, 2.36015) ->> 'nom', 'Sèdomey, Togoudo, Godomey',
  'à quinze mètres de là : le même nom, sans redemander');
select essai.verifie(public.lieu_connu(6.3990, 2.3600) ->> 'nom' is null, 'à 800 m : un autre lieu, inconnu');
select essai.verifie(not public.noter_lieu(6.40, 2.40, '   '), 'un nom vide n''est pas noté');
select essai.verifie(not public.noter_lieu(null, 2.40, 'Agla'), 'un point sans latitude non plus');
select public.noter_lieu(6.3910, 2.3600, 'Togoudo, Godomey');
select essai.egal(public.lieu_connu(6.3910, 2.3600) ->> 'nom', 'Togoudo, Godomey', 'un nom plus récent remplace l''ancien');
select essai.egal(public.compter_recherche_lieu(), 1, 'une recherche par nom : comptée');
select essai.egal(public.compter_recherche_lieu(), 2, 'deux');

select essai.titre('2. Personne d''autre que la fonction serveur');
set role anon;
select essai.refuse($$select public.lieu_connu(6.39, 2.36)$$, 'un visiteur ne lit pas les noms');
select essai.refuse($$select public.noter_lieu(6.39, 2.36, 'Chez moi')$$, 'ni n''en écrit');
select essai.refuse($$select public.compter_recherche_lieu()$$, 'ni ne touche au compteur');
select essai.refuse($$select count(*) from public.lieux_noms$$, 'ni ne lit la table');
reset role;
select essai.devenir(:SUPER::uuid); set role authenticated;
select essai.refuse($$select public.noter_lieu(6.39, 2.36, 'Chez moi')$$, 'un compte connecté non plus, même l''enseigne');
select essai.refuse($$insert into public.lieux_noms (lat_g, lng_g, nom) values (6.39, 2.36, 'X')$$,
  'ni par la table');
select essai.refuse($$update public.lieux_recherches set n = 0$$, 'ni ne remet le compteur à zéro');
reset role; select essai.personne();

select essai.titre('3. Le plafond du jour');
insert into public.lieux_recherches (jour, n) values (current_date, 1999)
on conflict (jour) do update set n = 1999;
-- 1 nom noté aujourd'hui + 1999 recherches = 2000 : atteint.
select essai.egal(public.lieu_connu(6.45, 2.45) ->> 'plafond_atteint', 'true', 'plafond atteint : la base le dit');
select essai.egal(public.lieu_connu(6.3910, 2.3600) ->> 'nom', 'Togoudo, Godomey',
  'un nom déjà connu reste servi');
select essai.egal(public.lieu_connu(6.3910, 2.3600) ->> 'plafond_atteint', 'false',
  'et sans plafond : il ne coûte rien à la source');
delete from public.lieux_recherches;

select essai.titre('4. « Faire livrer » : les frais au kilomètre, depuis le point');
update public.paiement
   set livraison_latitude = 6.3600, livraison_longitude = 2.3800, livraison_coef = 1.0,
       livraison_rayon_km = 2, moto_forfait = 600, moto_prix_km = 100, livraison_supplement_boutique = 200
 where id = 1;
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
-- Les boutiques gardent la position que l'essai « tournée » leur a donnée.
select pg_temp.devis('[{"produit_id":"prod_rup_b","quantite":2}]'::jsonb,
                     '{"latitude":6.4500,"longitude":2.4600}'::jsonb) as d \gset
select essai.verifie((:'d'::jsonb -> 'livraison') is not null, 'un point donné : des frais calculés');
select essai.egal((:'d'::jsonb -> 'livraison' ->> 'nb_boutiques')::int, 1, 'une boutique');
select essai.egal((:'d'::jsonb -> 'livraison' ->> 'supplements')::int, 0, 'une seule boutique : pas de supplément');
select essai.egal((:'d'::jsonb -> 'livraison' ->> 'frais')::int,
  (select (public.devis_tournee(array['bou_informatique'], 6.45, 2.46, 'moto') ->> 'frais')::int),
  'les mêmes frais qu''une commande de l''application');
select essai.egal((:'d'::jsonb ->> 'sous_total')::int, 2000, 'et le prix des articles, comme avant');
select pg_temp.devis('[{"produit_id":"prod_rup_b","quantite":1},{"produit_id":"prod_wa_b","quantite":1}]'::jsonb,
                     '{"latitude":6.4500,"longitude":2.4600}'::jsonb) as d \gset
select essai.egal((:'d'::jsonb -> 'livraison' ->> 'nb_boutiques')::int, 2, 'deux boutiques : une tournée');
select essai.egal((:'d'::jsonb -> 'livraison' ->> 'supplements')::int, 400, '200 par boutique');
select essai.verifie(pg_temp.devis('[{"produit_id":"prod_rup_b","quantite":1}]'::jsonb, null) -> 'livraison'
                       = 'null'::jsonb, 'sans point : pas de frais, ils restent à saisir');
select essai.verifie(pg_temp.devis('[{"produit_id":"prod_rup_b","quantite":1}]'::jsonb,
                                   '{"latitude":"abc","longitude":2}'::jsonb) -> 'livraison' = 'null'::jsonb,
  'un point illisible : rien, sans erreur');
select essai.verifie(pg_temp.devis('[{"produit_id":"prod_rup_b","quantite":1}]'::jsonb,
                                   '{"latitude":0,"longitude":0}'::jsonb) -> 'livraison' = 'null'::jsonb,
  'le point « 0, 0 » : rien non plus');
update public.paiement set livraison_latitude = null, livraison_longitude = null where id = 1;
select essai.verifie(pg_temp.devis('[{"produit_id":"prod_rup_b","quantite":1}]'::jsonb,
                                   '{"latitude":6.45,"longitude":2.46}'::jsonb) -> 'livraison' = 'null'::jsonb,
  'livraison au kilomètre hors service : rien, comme avant');
update public.paiement set livraison_supplement_boutique = 0 where id = 1;
delete from public.lieux_noms;
