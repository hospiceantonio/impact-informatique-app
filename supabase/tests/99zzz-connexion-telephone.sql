-- =========================================================
-- Entrer avec son numéro, son mot de passe, et un code (3.59.0)
--
-- Ce qu'on prouve :
--   1. un livreur créé par son numéro (« compte: equipe ») reçoit sa
--      fiche d'équipe en attente — un acheteur créé par numéro, non ;
--   2. il ne reçoit pas de fiche client, même si son numéro est
--      confirmé d'office à la création ;
--   3. l'enseigne exige le code de l'équipe : un livreur entré par
--      numéro + code (jeton « otp ») a ses droits sans second code ;
--      entré par mot de passe seul, non ; un modérateur entré par code
--      Supabase garde, lui, son code d'équipe à rendre.
-- =========================================================

\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\pset format unaligned
set client_min_messages = notice;

\set LIVREUR  '''acacacac-1111-1111-1111-111111111111'''
\set D_OFFICE '''acacacac-2222-2222-2222-222222222222'''
\set ACHAT    '''acacacac-3333-3333-3333-333333333333'''
\set MODO     '''acacacac-4444-4444-4444-444444444444'''

-- Se présenter avec un jeton précis : la méthode d'entrée, le numéro.
create or replace function essai.jeton(compte uuid, methode text, telephone text)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', compte::text, false);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', compte, 'phone', telephone,
    'amr', jsonb_build_array(jsonb_build_object('method', methode, 'timestamp', 1)))::text, false);
end $$;
grant execute on all functions in schema essai to anon, authenticated, service_role;

select essai.titre('1. Un livreur créé par son numéro a sa fiche en attente');
insert into auth.users (id, email, phone, raw_user_meta_data) values
  (:LIVREUR::uuid, '', '2290196000111', '{"compte":"equipe","nom":"Kossi"}'),
  (:ACHAT::uuid, '', '2290196000333', '{}')
on conflict do nothing;
select essai.egal((select count(*)::int from public.profils where id = :LIVREUR::uuid and not actif),
  1, 'le livreur : fiche d''équipe en attente');
select essai.egal((select count(*)::int from public.profils where id = :ACHAT::uuid),
  0, 'un acheteur né d''un numéro : pas de fiche d''équipe');

select essai.titre('2. Numéro confirmé d''office : toujours pas de fiche client');
insert into auth.users (id, email, phone, phone_confirmed_at, raw_user_meta_data) values
  (:D_OFFICE::uuid, '', '2290196000222', now(), '{"compte":"equipe"}')
on conflict do nothing;
select essai.egal((select count(*)::int from public.clients where id = :D_OFFICE::uuid),
  0, 'aucune fiche client pour un livreur');
select essai.egal((select count(*)::int from public.profils where id = :D_OFFICE::uuid),
  1, 'sa fiche d''équipe est bien là');

-- L'administrateur active le livreur ; sa première connexion confirme
-- son numéro — et ne lui pose pas de fiche client non plus.
update public.profils set role = 'livreur', actif = true, tel = '0196000111'
 where id = :LIVREUR::uuid;
update auth.users set phone_confirmed_at = now() where id = :LIVREUR::uuid;
select essai.egal((select count(*)::int from public.clients where id = :LIVREUR::uuid),
  0, 'la confirmation de son numéro ne fait pas de lui un client');

select essai.titre('3. Le code de l''équipe exigé : un seul code pour le livreur');
insert into auth.users (id, email, phone) values
  (:MODO::uuid, 'modo.code@essai.bj', '2290196000444') on conflict do nothing;
update public.profils set role = 'moderateur', actif = true, boutique_id = 'bou_informatique',
       tel = '0196000444' where id = :MODO::uuid;
update public.securite_equipe set sms_exige = true;

select essai.jeton(:LIVREUR::uuid, 'otp', '2290196000111'); set role authenticated;
select essai.egal(public.role_courant(), 'livreur',
  'entré par numéro + code : le livreur a ses droits');
reset role; select essai.personne();

select essai.jeton(:LIVREUR::uuid, 'password', '2290196000111'); set role authenticated;
select essai.egal(coalesce(public.role_courant(), 'aucun'), 'aucun',
  'mot de passe seul : aucun droit tant que le code n''est pas rendu');
reset role; select essai.personne();

select essai.jeton(:LIVREUR::uuid, 'otp', ''); set role authenticated;
select essai.egal(coalesce(public.role_courant(), 'aucun'), 'aucun',
  'un jeton « otp » sans numéro confirmé ne compte pas');
reset role; select essai.personne();

select essai.jeton(:MODO::uuid, 'otp', '2290196000444'); set role authenticated;
select essai.egal(coalesce(public.role_courant(), 'aucun'), 'aucun',
  'un modérateur garde son code d''équipe à rendre');
reset role; select essai.personne();

update public.securite_equipe set sms_exige = false;
