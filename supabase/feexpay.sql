-- =========================================================
-- BIZZOO — DEUX AGRÉGATEURS DE PAIEMENT, AU CHOIX
--
-- Jusqu'ici un seul encaissait : KkiaPay. L'enseigne choisit
-- désormais, dans ses réglages, qui encaisse — KkiaPay ou
-- FeexPay — sans qu'on reconstruise ni republie quoi que ce
-- soit.
--
-- LES DEUX NE MARCHENT PAS PAREIL, et c'est ce qui explique
-- tout ce fichier :
--
--   KkiaPay  l'application ouvre un widget avec une clé
--            PUBLIQUE, puis KkiaPay nous envoie une
--            notification SIGNÉE. C'est elle, et elle seule,
--            qui fait passer une commande à « payée ».
--
--   FeexPay  il n'y a AUCUNE notification signée : rien qu'une
--            redirection de navigateur, que le client pourrait
--            fabriquer. Et son jeton est un secret porteur, à
--            ne surtout pas mettre dans une application.
--
--            Alors on inverse : notre Edge Function ouvre le
--            paiement elle-même (le jeton reste dans les
--            secrets Supabase), reçoit une RÉFÉRENCE, et c'est
--            elle qui ira demander à FeexPay « ce versement
--            a-t-il abouti ? ». La réponse de FeexPay décide,
--            jamais celle du téléphone.
--
-- La règle ne change donc pas d'un pouce : L'APPLICATION NE
-- DÉCLARE JAMAIS UN PAIEMENT. Elle attend.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable.
-- =========================================================

-- ---------------------------------------------------------
-- 1. Qui encaisse
-- ---------------------------------------------------------
alter table public.paiement
  add column if not exists fournisseur text not null default 'feexpay';
alter table public.paiement alter column fournisseur set default 'feexpay';

-- FeexPay devient l'agrégateur de BIZZOO. Mais on ne bascule PAS un
-- paiement déjà ouvert : le faire couperait les encaissements en cours
-- le temps que le jeton FeexPay soit posé, et personne ne comprendrait
-- pourquoi les commandes cessent d'aboutir. Tant que le paiement est
-- fermé, en revanche, il n'y a rien à casser.
update public.paiement set fournisseur = 'feexpay'
 where id = 1 and not actif;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'paiement_fournisseur_connu') then
    alter table public.paiement
      add constraint paiement_fournisseur_connu
      check (fournisseur in ('kkiapay', 'feexpay'));
  end if;
end $$;

-- ---------------------------------------------------------
-- 2. La référence de la tentative de paiement
-- ---------------------------------------------------------
-- C'est la clé de tout l'encaissement FeexPay : sans elle, notre
-- serveur ne saurait pas quel versement interroger.
alter table public.commandes
  add column if not exists fournisseur_ref text not null default '';
-- Quand la dernière demande de paiement est partie. Chaque appel fait
-- sonner un téléphone : sans ce repère, on pourrait harceler n'importe
-- quel numéro de demandes venues de l'enseigne, et c'est le compte
-- marchand de BIZZOO qui en répondrait.
alter table public.commandes
  add column if not exists tentative_le timestamptz;
-- Ce que le téléphone affirme : le verrou réinstallé plus bas le garde
-- lui aussi. Un fichier qui pose une fonction pose toutes les colonnes
-- qu'elle lit ou écrit, même celles d'un autre fichier — PostgreSQL ne
-- relit le corps d'une fonction qu'à l'exécution, et l'oubli ne se voit
-- qu'au premier passage.
alter table public.commandes
  add column if not exists transaction_annoncee text not null default '';

-- À qui appartient cette commande. Le verrou posé plus bas la garde :
-- réattribuer une commande, c'est offrir à quelqu'un l'historique, les
-- avis et le SAV d'un autre. La clé étrangère, elle, est posée par
-- « comptes-clients.sql », seul fichier où la table des clients existe.
alter table public.commandes add column if not exists client_id uuid;

-- Une référence ne désigne qu'une commande : sans cela, deux commandes
-- pourraient se disputer le même versement.
create unique index if not exists commandes_fournisseur_ref
  on public.commandes(fournisseur_ref) where fournisseur_ref <> '';

-- ---------------------------------------------------------
-- 3. Le verrou des commandes
-- ---------------------------------------------------------
-- La nouvelle colonne rejoint celles que l'équipe ne réécrit pas :
-- laisser modifier la référence, c'est laisser désigner quel versement
-- répond pour quelle commande.
create or replace function public.commande_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- La base écrit pour elle-même : le total qui suit ses lignes, la
  -- monnaie posée à la création. Ces drapeaux n'existent que le temps de
  -- l'appel — ils ne s'attrapent pas depuis PostgREST.
  if coalesce(current_setting('bizzoo.interne', true), '') = 'oui' then
    return new;
  end if;
  if coalesce(current_setting('bizzoo.paiement', true), '') = 'oui' then
    return new;   -- l'agrégateur, ou l'enseigne qui se porte garante
  end if;

  if not public.est_equipe() then
    raise exception 'Seule l''équipe suit une commande';
  end if;

  -- L'équipe suit la commande, elle ne la réécrit pas.
  if new.total is distinct from old.total
  or new.client_nom is distinct from old.client_nom
  or new.client_tel is distinct from old.client_tel
  or new.client_adresse is distinct from old.client_adresse
  -- À qui appartient cette commande. La réattribuer, c'est offrir à
  -- quelqu'un l'historique, les avis et le SAV d'un autre.
  or new.client_id is distinct from old.client_id
  or new.transaction_id is distinct from old.transaction_id
  or new.transaction_annoncee is distinct from old.transaction_annoncee
  -- La référence de l'agrégateur est ce avec quoi notre serveur ira lui
  -- demander si le versement a abouti. La laisser réécrire, c'est
  -- laisser désigner quel versement répond pour quelle commande.
  or new.fournisseur_ref is distinct from old.fournisseur_ref
  or new.tentative_le is distinct from old.tentative_le
  or new.confirme_par is distinct from old.confirme_par
  or new.paye_le is distinct from old.paye_le then
    raise exception 'Le montant et le paiement d''une commande ne se réécrivent pas';
  end if;

  -- Et surtout : elle n'invente pas un encaissement.
  if new.etat = 'payee' and old.etat <> 'payee' then
    raise exception 'Seul l''agrégateur de paiement déclare un paiement';
  end if;
  if old.etat = 'payee' and new.etat not in ('payee', 'annulee') then
    raise exception 'Une commande payée ne peut être qu''annulée';
  end if;
  return new;
end $$;

drop trigger if exists commandes_verrous on public.commandes;
create trigger commandes_verrous
  before update on public.commandes
  for each row execute function public.commande_verrous();

-- ---------------------------------------------------------
-- 4. Enregistrer la référence donnée par l'agrégateur
-- ---------------------------------------------------------
create or replace function public.noter_reference(cible text, reference text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  net text := left(regexp_replace(coalesce(reference, ''), '[^A-Za-z0-9_-]', '', 'g'), 96);
  c   public.commandes%rowtype;
begin
  if net = '' then return false; end if;
  select * into c from public.commandes where id = coalesce(cible, '');
  if not found or c.etat <> 'a_payer' then return false; end if;

  -- Déjà prise par une autre commande : on ne la vole pas.
  if exists (select 1 from public.commandes a
              where a.fournisseur_ref = net and a.id <> c.id) then
    return false;
  end if;

  -- UN FREIN. Chaque appel fait sonner un téléphone : sans lui, on
  -- pourrait harceler n'importe quel numéro de demandes de paiement
  -- venues de l'enseigne — et c'est le compte marchand de BIZZOO qui
  -- en répondrait. Trente secondes laissent le temps de voir la
  -- demande arriver, et de se tromper de numéro sans être bloqué.
  if c.tentative_le is not null and c.tentative_le > now() - interval '30 seconds' then
    return false;
  end if;

  perform set_config('bizzoo.paiement', 'oui', true);
  -- Une commande non payée peut être retentée avec un autre numéro :
  -- la nouvelle tentative remplace alors l'ancienne référence.
  update public.commandes
     set fournisseur_ref = net, tentative_le = now()
   where id = c.id;
  return true;
end $$;

revoke all on function public.noter_reference(text, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------
-- 5. Ce que l'Edge Function a besoin de savoir
-- ---------------------------------------------------------
create or replace function public.commande_pour_paiement(cible text, tel text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.commandes%rowtype;
begin
  select * into c from public.commandes
   where id = coalesce(cible, '')
     and client_tel = regexp_replace(coalesce(tel, ''), '\D', '', 'g');
  if not found then return null; end if;
  return jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'etat', c.etat,
    'total', c.total, 'devise', c.devise,
    'nom', c.client_nom, 'tel', c.client_tel,
    'reference', c.fournisseur_ref,
    -- Pour que l'Edge Function refuse une relance AVANT d'appeler
    -- l'agrégateur : sinon le téléphone sonnerait quand même, et c'est
    -- seulement en rangeant la référence qu'on s'apercevrait du frein.
    'tentative_le', c.tentative_le);
end $$;

revoke all on function public.commande_pour_paiement(text, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------
-- 6. Retrouver une commande par la référence de l'agrégateur
-- ---------------------------------------------------------
-- Le webhook de FeexPay ne connaît pas nos numéros de commande : il nous
-- rend SA référence. C'est par elle qu'on recolle le versement.
create or replace function public.commande_par_reference(reference text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  net text := left(regexp_replace(coalesce(reference, ''), '[^A-Za-z0-9_-]', '', 'g'), 96);
  c   public.commandes%rowtype;
begin
  if net = '' then return null; end if;
  select * into c from public.commandes where fournisseur_ref = net;
  if not found then return null; end if;
  return jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'etat', c.etat,
    'total', c.total, 'reference', c.fournisseur_ref);
end $$;

revoke all on function public.commande_par_reference(text)
  from public, anon, authenticated;

-- ---------- Vérification ----------
-- Aucune requête ne passe par une fonction réservée : l'éditeur SQL
-- n'est connecté à aucun compte, et un seul refus annulerait TOUT le
-- fichier — vous n'auriez rien.

-- 1. L'agrégateur en service, et ce qui est posé.
select p.fournisseur                                   as "agrégateur",
       case when p.actif then 'ouvert' else 'fermé' end as "paiement en ligne",
       case when p.bac_a_sable then 'bac à sable' else 'RÉEL' end as "mode",
       case when coalesce(p.cle_publique, '') = '' then 'absente' else 'posée' end
                                                       as "clé publique KkiaPay"
  from public.paiement p where p.id = 1;

-- 2. Les colonnes du paiement sur une commande.
select column_name as "colonne", data_type as "type"
  from information_schema.columns
 where table_schema = 'public' and table_name = 'commandes'
   and column_name in ('transaction_id', 'transaction_annoncee', 'fournisseur_ref')
 order by 1;

-- 3. Qui peut poser une référence de paiement. « service_role » doit
--    être SEUL : un téléphone qui le pourrait désignerait lui-même le
--    versement censé régler sa commande.
select r.rolname as "a le droit d'appeler noter_reference()"
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 cross join lateral (
   select rolname from pg_roles
    where rolname in ('anon', 'authenticated', 'service_role')
      and has_function_privilege(rolname, p.oid, 'EXECUTE')
 ) r
 where n.nspname = 'public' and p.proname = 'noter_reference';
