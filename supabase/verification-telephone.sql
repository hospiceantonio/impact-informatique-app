-- =========================================================
-- BIZZOO — vérifier son numéro par SMS
--
-- Un client peut désormais entrer chez BIZZOO par son NUMÉRO
-- plutôt que par une adresse e-mail, et un client déjà inscrit
-- par e-mail peut confirmer le sien. Dans les deux cas, c'est
-- Supabase Auth qui envoie le code, le fait expirer et le
-- vérifie ; notre seul travail est de LIVRER le SMS (fonction
-- « hook-sms-auth ») et de tirer les conséquences ici.
--
-- CE QUI TIENT TOUT :
--
--   1. NOUS N'ÉCRIVONS AUCUN CODE. Ni table de codes, ni
--      hachage, ni expiration, ni compteur de tentatives.
--      Supabase Auth sait déjà tout cela. En réécrire une
--      version maison ne rapporterait que des bugs — et une
--      surface de plus à défendre ;
--
--   2. LA VÉRITÉ EST « auth.users.phone_confirmed_at ». Cette
--      colonne est écrite par GoTrue lui-même, dans un schéma
--      que l'application ne peut pas toucher. Le drapeau
--      « clients.tel_verifie » n'en est que le reflet, posé par
--      le déclencheur ci-dessous. Il n'existe AUCUN chemin par
--      lequel l'application pourrait se déclarer vérifiée ;
--
--   3. CE DÉCLENCHEUR NE LÈVE JAMAIS D'EXCEPTION. Il tourne
--      dans la transaction de « verify » : une erreur ici
--      ferait échouer la vérification alors que le numéro est
--      bel et bien confirmé. Il avale donc tout, et une
--      réconciliation rattrape ce qui aurait été manqué ;
--
--   4. UN NUMÉRO VÉRIFIÉ N'APPARTIENT QU'À UN COMPTE. Il donne
--      accès aux commandes passées avec lui : deux comptes qui
--      le revendiquent liraient les achats l'un de l'autre. Le
--      second est refusé — sans bruit côté base, avec un
--      message clair côté application.
--
-- AVANT D'EXÉCUTER CE FICHIER, dans le tableau de bord :
--   Authentication → Sign In / Providers → Phone : activer.
--   Authentication → Hooks → Send SMS hook : y déclarer
--     https://<projet>.supabase.co/functions/v1/hook-sms-auth
--   puis déployer la fonction (voir son en-tête).
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, et rien n'est supprimé.
-- =========================================================

-- ---------------------------------------------------------
-- 1. Les colonnes que ce fichier remplit
-- ---------------------------------------------------------
create table if not exists public.clients (
  id          uuid primary key references auth.users(id) on delete cascade,
  nom         text not null default '',
  tel         text not null default '',
  indicatif   text not null default '229',
  tel_verifie boolean not null default false,
  adresse     text not null default '',
  cree_le     timestamptz not null default now(),
  maj_le      timestamptz not null default now()
);
alter table public.clients add column if not exists tel_verifie boolean not null default false;
alter table public.clients add column if not exists adresse text not null default '';
alter table public.clients add column if not exists indicatif text not null default '229';
alter table public.clients add column if not exists type_compte text not null default 'client';
alter table public.clients add column if not exists revendeur_etat text not null default 'aucune';
alter table public.clients add column if not exists revendeur_message text not null default '';
alter table public.clients add column if not exists revendeur_demande_le timestamptz;
alter table public.clients add column if not exists revendeur_decide_par text not null default '';
alter table public.clients add column if not exists revendeur_decide_le timestamptz;
alter table public.clients add column if not exists revendeur_motif text not null default '';

-- Un numéro vérifié ne désigne qu'un compte.
create unique index if not exists clients_tel_verifie
  on public.clients(tel) where tel_verifie and tel <> '';

-- ---------------------------------------------------------
-- 2. Un compte créé par SMS n'est pas un compte d'équipe
-- ---------------------------------------------------------
-- L'application cliente pose « compte: client » dans les métadonnées, et
-- le fait aussi bien pour l'inscription par e-mail que pour l'entrée par
-- numéro. Mais un compte né d'un SMS n'a PAS d'adresse e-mail : s'il
-- échappait au test, il atterrirait dans la liste des comptes de
-- l'enseigne, où un clic distrait lui donnerait les droits d'un
-- modérateur. On ajoute donc la seconde barrière : un compte sans
-- e-mail et avec un numéro est un client, quoi qu'il ait déclaré.
create or replace function public.profil_nouveau_compte() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  /* UN CLIENT N'EST PAS UN COMPTE D'ÉQUIPE EN ATTENTE. L'application
     cliente s'inscrit en posant « compte: client » ; sans ce test, chaque
     acheteur apparaîtrait dans la liste des comptes de l'enseigne, et il
     suffirait d'un clic distrait pour donner à un client les droits d'un
     modérateur sur une boutique. */
  if coalesce(new.raw_user_meta_data ->> 'compte', '') = 'client' then
    return new;
  end if;
  /* Et l'équipe n'entre pas par SMS : elle a des adresses e-mail. Un
     compte qui n'a qu'un numéro est un acheteur, même si les
     métadonnées manquent — elles viennent du téléphone, après tout. */
  if coalesce(new.email, '') = '' and coalesce(new.phone, '') <> '' then
    return new;
  end if;
  insert into public.profils (id, email, role, actif)
  values (new.id, coalesce(new.email, ''), 'moderateur', false)
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists profil_a_la_creation on auth.users;
create trigger profil_a_la_creation
  after insert on auth.users
  for each row execute function public.profil_nouveau_compte();

-- ---------------------------------------------------------
-- 3. Le numéro national, tel que BIZZOO le range
-- ---------------------------------------------------------
-- Supabase range le numéro complet et SANS « + » : « 2290197121596 ».
-- « commandes.client_tel » et « clients.tel », eux, ne portent que la
-- partie nationale — « 0197121596 » — parce que c'est ainsi qu'un client
-- le tape dans le panier. Sans cette conversion, rapprocher un compte de
-- ses commandes d'avant ne donnerait jamais rien.
create or replace function public.tel_national(complet text, indicatif text default '229')
returns text
language sql immutable as $$
  select case
           when chiffres like indicatif || '%'
                and length(chiffres) > length(indicatif)
             then substr(chiffres, length(indicatif) + 1)
           else chiffres
         end
    from (select regexp_replace(coalesce(complet, ''), '\D', '', 'g') as chiffres) x;
$$;
revoke all on function public.tel_national(text, text) from public, anon, authenticated;

-- ---------------------------------------------------------
-- 4. Quand GoTrue confirme un numéro
-- ---------------------------------------------------------
-- LE POINT DÉLICAT : ce déclencheur tourne DANS la transaction de
-- « verify ». S'il lève quoi que ce soit, la vérification échoue alors
-- que le numéro vient d'être confirmé — et le client, qui a bien reçu
-- son SMS et bien tapé son code, voit une panne. Il avale donc tout.
--
-- Le prix de ce silence : une vérification peut aboutir chez GoTrue sans
-- que « clients » l'apprenne. D'où reconcilier_numeros_verifies(), plus
-- bas, qui rattrape.
create or replace function public.au_numero_confirme() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  national text;
begin
  -- Rien de neuf : ni une confirmation, ni un changement de numéro
  -- confirmé. On sort sans rien faire.
  if new.phone_confirmed_at is null then return new; end if;
  if tg_op = 'UPDATE'
     and old.phone_confirmed_at is not null
     and coalesce(old.phone, '') = coalesce(new.phone, '') then
    return new;
  end if;

  national := public.tel_national(new.phone, '229');
  if coalesce(national, '') = '' then return new; end if;

  -- Un compte de l'équipe qui confirme son numéro reste un compte
  -- d'équipe : lui poser une fiche client ferait de lui les deux à la
  -- fois, ce que « compte_unique » refuse — et à raison.
  if exists (select 1 from public.profils p where p.id = new.id and p.actif) then
    return new;
  end if;

  -- Ce numéro est déjà vérifié ailleurs : on ne le vole pas. Le compte
  -- reste non vérifié, et l'application le dira en clair — mieux vaut un
  -- message qu'une contrainte violée au visage du client.
  if exists (select 1 from public.clients c
              where c.tel = national and c.tel_verifie and c.id <> new.id) then
    raise notice 'BIZZOO : le numéro % est déjà vérifié sur un autre compte', national;
    return new;
  end if;

  -- « bizzoo.verification » est ce qui distingue cette écriture d'une
  -- requête ordinaire : sans lui, le verrou de « clients » la refuserait.
  perform set_config('bizzoo.verification', 'oui', true);
  insert into public.clients (id, tel, indicatif, tel_verifie, nom)
  values (new.id, national, '229', true,
          left(coalesce(new.raw_user_meta_data ->> 'nom', ''), 120))
  on conflict (id) do update
    set tel = excluded.tel,
        indicatif = excluded.indicatif,
        tel_verifie = true,
        maj_le = now();
  perform set_config('bizzoo.verification', '', true);
  return new;
exception when others then
  /* On ne fait PAS échouer « verify » pour autant : le numéro est
     confirmé chez GoTrue, c'est ce qui compte. La réconciliation
     rattrapera. */
  raise notice 'BIZZOO : numéro confirmé mais fiche non mise à jour (%)', sqlerrm;
  return new;
end $$;

drop trigger if exists numero_confirme on auth.users;
create trigger numero_confirme
  after insert or update of phone, phone_confirmed_at on auth.users
  for each row execute function public.au_numero_confirme();

-- ---------------------------------------------------------
-- 5. Rattraper ce que le silence aurait manqué
-- ---------------------------------------------------------
-- Le déclencheur ci-dessus avale ses erreurs — il le faut. Cette
-- fonction rejoue le rapprochement pour tous les comptes dont GoTrue dit
-- le numéro confirmé et dont la fiche l'ignore. Réservée à l'enseigne,
-- relançable sans dommage.
create or replace function public.reconcilier_numeros_verifies() returns int
language plpgsql security definer set search_path = public as $$
declare
  u        record;
  national text;
  combien  int := 0;
begin
  if not public.est_super() then
    raise exception 'Réservé à BIZZOO';
  end if;
  perform set_config('bizzoo.verification', 'oui', true);
  for u in
    select au.id, au.phone, au.raw_user_meta_data
      from auth.users au
      join public.clients c on c.id = au.id
     where au.phone_confirmed_at is not null
       and (not c.tel_verifie
            or c.tel is distinct from public.tel_national(au.phone, '229'))
  loop
    national := public.tel_national(u.phone, '229');
    continue when coalesce(national, '') = '';
    continue when exists (select 1 from public.clients c
                           where c.tel = national and c.tel_verifie and c.id <> u.id);
    update public.clients
       set tel = national, indicatif = '229', tel_verifie = true, maj_le = now()
     where id = u.id;
    combien := combien + 1;
  end loop;
  perform set_config('bizzoo.verification', '', true);
  return combien;
end $$;

revoke all on function public.reconcilier_numeros_verifies()
  from public, anon, authenticated;
grant execute on function public.reconcilier_numeros_verifies() to authenticated;

-- ---------------------------------------------------------
-- 6. Ce qu'un numéro vérifié ouvre
-- ---------------------------------------------------------
-- Retrouver les commandes passées AVANT d'avoir un compte, avec ce
-- numéro-là. C'est tout, et c'est déjà beaucoup : ces commandes portent
-- une adresse de livraison et un historique d'achats.
--
-- Deux garde-fous que la fonction pose et qu'il faut connaître :
--
--   — elle exige le numéro VÉRIFIÉ, jamais celui qu'on a tapé ;
--   — elle ne remonte pas au-delà de dix-huit mois. Les opérateurs
--     béninois recyclent les numéros : sans cette borne, qui hérite
--     d'une ancienne ligne hériterait des commandes de son ancien
--     titulaire. Dix-huit mois laissent largement de quoi retrouver ses
--     achats, et referment la porte sur le passé lointain.
create or replace function public.rattacher_mes_commandes() returns int
language plpgsql security definer set search_path = public as $$
declare moi uuid := auth.uid(); mien public.clients%rowtype; combien int;
begin
  if moi is null then return 0; end if;
  select * into mien from public.clients where id = moi;
  if not found or not mien.tel_verifie or coalesce(mien.tel, '') = '' then
    raise exception 'Vérifiez votre numéro pour retrouver vos commandes';
  end if;

  perform set_config('bizzoo.interne', 'oui', true);
  update public.commandes
     set client_id = moi
   where client_id is null
     and client_tel = mien.tel
     and cree_le > now() - interval '18 months';
  get diagnostics combien = row_count;
  return combien;
end $$;

revoke all on function public.rattacher_mes_commandes() from public, anon;
grant execute on function public.rattacher_mes_commandes() to authenticated;

-- ---------- Vérification ----------
select
  case when exists (select 1 from pg_trigger tr join pg_class c on c.oid = tr.tgrelid
                     join pg_namespace n on n.oid = c.relnamespace
                    where n.nspname = 'auth' and c.relname = 'users'
                      and tr.tgname = 'numero_confirme')
       then 'en place' else 'MANQUANT' end                      as "déclencheur numero_confirme",
  case when exists (select 1 from pg_proc where proname = 'tel_national')
       then 'en place' else 'MANQUANT' end                      as "tel_national()",
  case when exists (select 1 from pg_proc where proname = 'reconcilier_numeros_verifies')
       then 'en place' else 'MANQUANT' end                      as "réconciliation",
  (select count(*)::int from public.clients where tel_verifie)   as "numéros vérifiés",
  (select count(*)::int from auth.users where phone_confirmed_at is not null)
                                                                 as "confirmés chez GoTrue";
