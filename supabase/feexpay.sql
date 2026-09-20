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

-- Sous quel régime de prix cette commande est partie : prix public, ou
-- prix BIZZOO pour un revendeur validé. Le verrou plus bas l'empêche de
-- basculer après coup. Posée par « comptes-revendeurs.sql », répétée
-- ici : la règle d'écriture ci-dessous la lit.
alter table public.commandes add column if not exists revendeur boolean not null default false;

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
-- ---------------------------------------------------------
-- Qui est qui, recopié ici
-- ---------------------------------------------------------
-- « est_equipe() » a CHANGÉ DE SENS avec l'arrivée du rang livreur :
-- elle nomme désormais les trois rangs qui tiennent la boutique, et
-- le livreur n'en est pas. Les règles de ce fichier s'appuient sur
-- elle ; collé seul sur une base qui garde l'ancienne définition,
-- il laisserait un livreur passer pour un membre de l'équipe.
-- Sur une base déjà à jour, ce bloc ne fait rien.

-- Membre de l'équipe qui TIENT la boutique : catalogue, commandes,
-- avis, réclamations.
--
-- LE LIVREUR N'EN EST PAS, et c'est tout l'objet de cette liste. Il a un
-- profil, donc « role_courant() » lui répond — mais il ne tient rien. La
-- version d'avant disait « n'importe quel profil actif », et le jour où
-- le rang « livreur » est arrivé, cela lui aurait ouvert d'un coup :
-- les commandes de toute la boutique, le journal, les chiffres de
-- vente, le dépôt de photos. Rien de tout cela n'est son travail.
--
-- Une seule fonction à corriger plutôt que neuf endroits : c'est
-- justement pour cela qu'elle existe.
create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;

-- Celui qui porte la marchandise, et rien d'autre.
create or replace function public.est_livreur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'livreur', false);
$$;

-- Peut-il retoucher un produit déjà au catalogue ? Les deux rangs
-- d'administrateur toujours ; le modérateur seulement si on le lui accorde.
--
-- « est_equipe() » EN PREMIER, et ce n'est pas une précaution de style :
-- « peut_modifier_produits » vaut VRAI par défaut sur tout profil. Sans
-- cette condition, un livreur qu'on vient de créer pourrait modifier le
-- catalogue — la colonne lui aurait dit oui.
create or replace function public.peut_modifier_produits() returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_equipe()
     and coalesce((select role in ('superadministrateur', 'administrateur')
                       or peut_modifier_produits
                     from public.profils where id = auth.uid() and actif), false);
$$;

-- La boutique à laquelle le compte est rattaché. Null pour un
-- administrateur : il n'est enfermé nulle part.
create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils where id = auth.uid() and actif;
$$;

-- A-t-il le droit de toucher à ce qui appartient à cette boutique-là ?
-- Le superadministrateur partout ; les autres dans la leur seulement.
create or replace function public.peut_agir_sur(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or (public.est_equipe() and cible is not null
          and cible = public.boutique_du_compte());
$$;

-- Droits d'administration SUR cette boutique-là : le superadministrateur
-- partout, l'administrateur uniquement chez lui.
create or replace function public.administre(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or (public.est_admin() and cible is not null
          and cible = public.boutique_du_compte());
$$;

-- Les règles de sécurité, y compris celles du stockage des photos,
-- appellent ces fonctions au nom du compte connecté.
grant execute on function public.peut_modifier_produits() to authenticated;
grant execute on function public.role_courant() to authenticated;
grant execute on function public.est_admin() to authenticated;
grant execute on function public.est_equipe() to authenticated;
revoke all on function public.est_livreur() from public, anon, authenticated;
grant execute on function public.est_livreur() to authenticated;
grant execute on function public.boutique_du_compte() to authenticated;
grant execute on function public.peut_agir_sur(text) to authenticated;

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
  -- Et sous quel régime de prix elle est partie : la basculer après
  -- coup, c'est réécrire ce que la boutique a touché.
  or new.revendeur is distinct from old.revendeur
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
-- Le journal des versements, recopié ici
-- ---------------------------------------------------------
-- Les fonctions de paiement ci-dessous y écrivent. Un fichier qui
-- pose une fonction pose aussi les fonctions qu'elle appelle :
-- collé seul sur une base d'avant le journal, ce fichier passerait
-- sans broncher et s'arrêterait au premier encaissement.
-- Sur une base qui l'a déjà, ce bloc ne fait rien.

-- ---------- Le journal des versements ----------
-- La commande ne garde que son ÉTAT ACTUEL : payée ou non. Ce qui s'est
-- passé en route — une demande partie sur un mauvais numéro, un versement
-- incomplet, un client qui s'y reprend à trois fois — n'était noté nulle
-- part. Pire : « marquer_payee » efface la remarque en réussissant, si
-- bien qu'un encaissement effaçait la trace de ses propres échecs.
--
-- D'où ce journal. UNE LIGNE PAR TENTATIVE, jamais modifiée ensuite :
-- c'est ce qui permet de répondre à « combien d'échecs cette semaine »
-- et « chez quel opérateur ». Un journal qu'on met à jour ne garde que
-- la fin de l'histoire, et la fin de l'histoire est déjà sur la commande.
--
-- PAS DE CLÉ ÉTRANGÈRE vers « commandes », et c'est voulu : effacer une
-- commande ne doit pas effacer la trace de l'argent. Le numéro est donc
-- recopié ici, figé, pour que la ligne se lise encore toute seule.
create table if not exists public.versements (
  id          bigint generated always as identity primary key,
  commande_id text,
  numero      text not null default '',
  -- Qui a encaissé : « feexpay », « kkiapay », ou « main » quand
  -- l'enseigne s'est portée garante elle-même. Figé au moment du fait :
  -- changer d'agrégateur demain ne réécrit pas les versements d'hier.
  fournisseur text not null default '',
  -- L'opérateur du client : MTN, MOOV, CELTIIS, CARTE. Connu seulement
  -- à l'ouverture de la demande — c'est le client qui l'a choisi.
  reseau      text not null default '',
  reference   text not null default '',
  transaction_id text not null default '',
  attendu     bigint not null default 0,
  recu        bigint not null default 0,
  verdict     text not null default 'ouverte'
              check (verdict in ('ouverte', 'payee', 'incomplete',
                                 'conflit', 'refusee', 'inconnue')),
  detail      text not null default '',
  cree_le     timestamptz not null default now()
);
create index if not exists versements_quand on public.versements(cree_le desc);
create index if not exists versements_commande on public.versements(commande_id);

alter table public.versements enable row level security;
drop policy if exists "versements lecture" on public.versements;
-- L'enseigne lit, personne n'écrit. AUCUNE règle d'écriture n'est posée
-- ici : les seules écritures viennent des fonctions « security definer »
-- ci-dessous, qui s'exécutent avec les droits du propriétaire et passent
-- donc au-dessus de RLS. Une règle d'écriture, même étroite, ouvrirait
-- au journal une porte par PostgREST.
create policy "versements lecture" on public.versements
  for select to authenticated using (public.est_super());
revoke all on public.versements from anon, authenticated;
grant select on public.versements to authenticated;

-- Poser une ligne. Appelée UNIQUEMENT par les fonctions du serveur —
-- jamais depuis une application, d'où la révocation qui suit.
create or replace function public.noter_versement(
  cible text, quoi text, qui text default '', ou text default '',
  ref text default '', trans text default '',
  du bigint default 0, recu bigint default 0, pourquoi text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare
  num     text := '';
  agregat text := left(regexp_replace(lower(coalesce(qui, '')), '[^a-z]', '', 'g'), 16);
  reseau  text := left(regexp_replace(upper(coalesce(ou,  '')), '[^A-Z]', '', 'g'), 16);
begin
  select c.numero into num from public.commandes c where c.id = cible;

  -- L'AGRÉGATEUR ET L'OPÉRATEUR NE SONT CONNUS QU'À L'OUVERTURE. Ni la
  -- notification ni la vérification ne les rappellent : elles n'ont
  -- qu'une référence. On les reprend donc sur la dernière ligne de la
  -- même commande qui les portait.
  --
  -- La règle vit ICI plutôt que chez chaque appelant : posée à trois
  -- endroits, elle finirait par diverger, et le journal dirait « MTN »
  -- d'un côté et rien de l'autre pour un même versement.
  if coalesce(cible, '') <> '' then
    if agregat = '' then
      select v.fournisseur into agregat from public.versements v
       where v.commande_id = cible and v.fournisseur <> ''
       order by v.cree_le desc, v.id desc limit 1;
    end if;
    if reseau = '' then
      select v.reseau into reseau from public.versements v
       where v.commande_id = cible and v.reseau <> ''
       order by v.cree_le desc, v.id desc limit 1;
    end if;
  end if;

  insert into public.versements
    (commande_id, numero, fournisseur, reseau, reference, transaction_id,
     attendu, recu, verdict, detail)
  values (
    nullif(coalesce(cible, ''), ''),
    coalesce(num, ''),
    coalesce(agregat, ''),
    coalesce(reseau, ''),
    left(regexp_replace(coalesce(ref, ''), '[^A-Za-z0-9_-]', '', 'g'), 96),
    left(regexp_replace(coalesce(trans, ''), '[^A-Za-z0-9_-]', '', 'g'), 64),
    greatest(0, coalesce(du, 0)),
    greatest(0, coalesce(recu, 0)),
    -- Un verdict inconnu ne fait pas échouer l'encaissement : il se range
    -- en « inconnue ». Le journal ne doit jamais empêcher l'argent
    -- d'entrer.
    case when quoi in ('ouverte', 'payee', 'incomplete', 'conflit',
                       'refusee', 'inconnue') then quoi else 'inconnue' end,
    left(coalesce(pourquoi, ''), 300));
end $$;
revoke all on function public.noter_versement(text, text, text, text, text, text, bigint, bigint, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------
-- 4. Enregistrer la référence donnée par l'agrégateur
-- ---------------------------------------------------------
-- « drop » avant « create » : cette fonction a gagné deux paramètres —
-- l'agrégateur et l'opérateur — pour le journal des versements. Ajouter
-- des paramètres par défaut ne remplace pas l'ancienne signature, il en
-- crée une seconde, et l'appel devient ambigu : « function is not
-- unique ». Sans ce retrait, chaque paiement échouerait.
drop function if exists public.noter_reference(text, text);
create or replace function public.noter_reference(
  cible text, reference text,
  qui text default '', ou text default '')
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

  -- Au journal. C'est ICI, et nulle part ailleurs, qu'on sait chez quel
  -- opérateur la demande est partie : ni la notification ni la
  -- vérification ne le rappellent.
  perform public.noter_versement(c.id, 'ouverte', qui, ou, net, '', c.total, 0,
    'Demande de paiement envoyée.');
  return true;
end $$;

revoke all on function public.noter_reference(text, text, text, text)
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
