-- =========================================================
-- BIZZOO — les comptes clients
--
-- Jusqu'ici, BIZZOO ne connaissait que l'équipe : la table
-- « profils » et les rôles qui vont avec. Un client commandait
-- sans compte, et son historique vivait dans son téléphone —
-- changez d'appareil, et tout disparaît.
--
-- Ce fichier pose l'identité du client. Rien d'autre ne bouge :
-- commander sans compte reste possible, et le restera tant que
-- la chaîne entière n'aura pas été éprouvée.
--
-- CE QUI TIENT TOUT :
--
--   1. UN COMPTE EST SOIT DE L'ÉQUIPE, SOIT D'UN CLIENT, jamais
--      les deux. Sans cette ligne, un modérateur pourrait noter
--      sa propre boutique, et un client hériterait un jour d'un
--      droit écrit pour l'équipe ;
--   2. LE CLIENT NE DÉCLARE PAS SON PROPRE TÉLÉPHONE VÉRIFIÉ.
--      C'est ce drapeau qui donnera accès aux commandes passées
--      avec ce numéro : le laisser écrire, c'est laisser
--      n'importe qui réclamer les commandes d'un autre ;
--   3. UN NUMÉRO VÉRIFIÉ N'APPARTIENT QU'À UN COMPTE.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, et rien n'est supprimé.
-- =========================================================

-- ---------------------------------------------------------
-- 1. Qui est le client
-- ---------------------------------------------------------
create table if not exists public.clients (
  id          uuid primary key references auth.users(id) on delete cascade,
  nom         text not null default '',
  -- Le numéro national, chiffres seulement — la même forme que
  -- « commandes.client_tel », sans quoi on ne pourrait pas les rapprocher.
  tel         text not null default '',
  indicatif   text not null default '229',
  -- Posé UNIQUEMENT par la vérification par SMS. Voir le verrou plus bas.
  tel_verifie boolean not null default false,
  adresse     text not null default '',
  cree_le     timestamptz not null default now(),
  maj_le      timestamptz not null default now()
);

-- Sur une base déjà en service, le corps du « create table » n'est pas relu.
alter table public.clients add column if not exists tel_verifie boolean not null default false;
alter table public.clients add column if not exists adresse text not null default '';
alter table public.clients add column if not exists indicatif text not null default '229';

-- Un numéro vérifié ne désigne qu'un compte. Deux comptes qui
-- revendiquent le même numéro se disputeraient les mêmes commandes.
create unique index if not exists clients_tel_verifie
  on public.clients(tel) where tel_verifie and tel <> '';

alter table public.clients enable row level security;

-- ---------------------------------------------------------
-- 2. Un compte est de l'équipe OU d'un client, jamais les deux
-- ---------------------------------------------------------
-- Le gérant d'une boutique qui veut acheter ailleurs crée un second
-- compte, avec une autre adresse. C'est un petit inconfort contre une
-- grande clarté : sans cette règle, chaque droit écrit pour l'équipe
-- devrait être relu en se demandant « et si c'était aussi un client ? ».
create or replace function public.compte_unique() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'clients' then
    /* Un profil EN ATTENTE ne vaut aucun droit : personne n'a encore
       décidé quoi que ce soit de ce compte. Les comptes créés hors de
       l'application cliente — dans le tableau de bord Supabase, par
       exemple — en reçoivent un ; devenir client l'efface, et rien n'est
       perdu. Un profil ACTIF, lui, porte de vrais droits sur une
       boutique : on ne le mélange pas avec un compte d'acheteur. */
    delete from public.profils p
     where p.id = new.id and not p.actif and p.role = 'moderateur';
    if exists (select 1 from public.profils p where p.id = new.id) then
      raise exception 'Ce compte est déjà un compte de l''équipe : un compte client demande une autre adresse';
    end if;
  else
    if exists (select 1 from public.clients c where c.id = new.id) then
      raise exception 'Ce compte est déjà un compte client : un compte d''équipe demande une autre adresse';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists clients_pas_equipe on public.clients;
create trigger clients_pas_equipe
  before insert or update on public.clients
  for each row execute function public.compte_unique();

drop trigger if exists profils_pas_client on public.profils;
create trigger profils_pas_client
  before insert or update on public.profils
  for each row execute function public.compte_unique();

-- Le compte connecté est-il un client ? « security definer » : la fonction
-- lit la table sans repasser par RLS, sinon les règles s'appelleraient
-- elles-mêmes.
create or replace function public.est_client() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.clients c where c.id = auth.uid());
$$;
grant execute on function public.est_client() to authenticated;

-- ---------------------------------------------------------
-- 3. Le client ne se déclare pas vérifié lui-même
-- ---------------------------------------------------------
-- C'est LE point de sécurité de ce fichier. Le drapeau « tel_verifie »
-- ouvrira l'accès aux commandes passées avec ce numéro : s'il s'écrivait
-- depuis l'application, il suffirait de taper le numéro d'un autre pour
-- lire ses commandes, ses adresses et ses achats.
--
-- Seule une fonction du serveur peut le poser, et elle pose du même coup
-- le numéro : on ne peut pas faire vérifier un numéro puis en changer.
create or replace function public.client_verrous() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('bizzoo.verification', true), '') = 'oui' then
    return new;   -- la vérification par SMS, et elle seule
  end if;
  if new.tel_verifie is distinct from old.tel_verifie then
    raise exception 'Un numéro se vérifie par SMS, il ne se déclare pas';
  end if;
  if old.tel_verifie and new.tel is distinct from old.tel then
    raise exception 'Un numéro vérifié ne se change pas : refaites une vérification';
  end if;
  return new;
end $$;

drop trigger if exists clients_verrous on public.clients;
create trigger clients_verrous
  before update on public.clients
  for each row execute function public.client_verrous();

-- Un compte client naît toujours non vérifié, quoi qu'en dise l'insertion.
create or replace function public.client_a_l_ecriture() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('bizzoo.verification', true), '') <> 'oui' then
    new.tel_verifie := false;
  end if;
  new.tel := left(regexp_replace(coalesce(new.tel, ''), '\D', '', 'g'), 20);
  return new;
end $$;

drop trigger if exists clients_ecriture on public.clients;
create trigger clients_ecriture
  before insert on public.clients
  for each row execute function public.client_a_l_ecriture();

-- ---------------------------------------------------------
-- 4. Ce qu'un client voit de lui-même
-- ---------------------------------------------------------
drop policy if exists "clients lecture" on public.clients;
create policy "clients lecture" on public.clients
  for select to authenticated
  using (id = auth.uid() or public.est_super());

drop policy if exists "clients creation" on public.clients;
create policy "clients creation" on public.clients
  for insert to authenticated with check (id = auth.uid());

drop policy if exists "clients modification" on public.clients;
create policy "clients modification" on public.clients
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- L'enseigne ne modifie pas un compte client : elle le voit, c'est tout.
-- Un compte se supprime depuis le compte lui-même, ou avec auth.users.

-- ---------------------------------------------------------
-- 5. La commande porte son client
-- ---------------------------------------------------------
alter table public.commandes add column if not exists client_id uuid;

-- La clé étrangère à part : les fichiers de paiement posent la colonne
-- sans connaître la table des clients, et une contrainte ne s'ajoute pas
-- deux fois.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'commandes_client_fk') then
    alter table public.commandes
      add constraint commandes_client_fk foreign key (client_id)
      references public.clients(id) on delete set null;
  end if;
end $$;

-- « on delete set null » et non « cascade » : un client qui ferme son
-- compte n'efface pas les ventes de la boutique. Les comptes d'hier ne se
-- réécrivent pas.
create index if not exists commandes_client on public.commandes(client_id, cree_le desc);

-- Le verrou des commandes garde aussi ce lien : réattribuer une commande
-- à un autre compte, c'est lui donner l'historique et les avis d'un tiers.
-- Ce fichier pose donc toutes les colonnes tardives que ce verrou touche —
-- une fonction ne s'installe jamais sans les colonnes qu'elle lit.
alter table public.commandes
  add column if not exists transaction_annoncee text not null default '';
alter table public.commandes
  add column if not exists fournisseur_ref text not null default '';
alter table public.commandes
  add column if not exists tentative_le timestamptz;

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
-- 6. Un client lit ses commandes, et rien d'autre
-- ---------------------------------------------------------
drop policy if exists "commandes lecture client" on public.commandes;
create policy "commandes lecture client" on public.commandes
  for select to authenticated
  using (client_id is not null and client_id = auth.uid());

-- « security definer » : la fonction lit la table SANS repasser par RLS.
-- Sans cela, la règle des lignes interrogerait les commandes, dont la règle
-- interroge les lignes — PostgreSQL s'arrête sur « infinite recursion
-- detected in policy ». Une règle ne doit jamais dépendre d'une règle qui
-- dépend d'elle.
create or replace function public.ma_commande(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.commandes c
     where c.id = cible
       and c.client_id is not null
       and c.client_id = auth.uid());
$$;
grant execute on function public.ma_commande(text) to authenticated;

drop policy if exists "lignes lecture client" on public.commande_lignes;
create policy "lignes lecture client" on public.commande_lignes
  for select to authenticated
  using (public.ma_commande(commande_id));

-- ---------------------------------------------------------
-- 7. Créer une commande en la rattachant à son compte
-- ---------------------------------------------------------
-- La commande est estampillée du compte connecté, s'il y en a un. Un
-- visiteur sans compte commande encore : c'est l'étape suivante qui
-- fermera cette porte, quand les écrans seront prêts.
create or replace function public.creer_commande(client jsonb, articles jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  nouvelle text := 'cmd_' || replace(gen_random_uuid()::text, '-', '');
  article  jsonb;
  qte      int;
  p        public.produits%rowtype;
  devises  text[];
  sortie   jsonb;
  moi      uuid := auth.uid();
begin
  if articles is null or jsonb_typeof(articles) <> 'array'
     or jsonb_array_length(articles) = 0 then
    raise exception 'Votre panier est vide.';
  end if;
  if jsonb_array_length(articles) > 40 then
    raise exception 'Un panier ne peut pas dépasser 40 articles différents.';
  end if;
  if coalesce(trim(client ->> 'tel'), '') = '' then
    raise exception 'Un numéro de téléphone est nécessaire pour vous joindre.';
  end if;

  -- Un compte de l'équipe ne passe pas commande pour lui-même : il agirait
  -- avec les droits d'une boutique sur une commande qui lui appartient.
  if moi is not null and not exists (select 1 from public.clients c where c.id = moi) then
    moi := null;
  end if;

  perform set_config('bizzoo.interne', 'oui', true);

  insert into public.commandes
    (id, client_id, client_nom, client_tel, client_indicatif, client_adresse, note)
  values (
    nouvelle,
    moi,
    left(coalesce(trim(client ->> 'nom'), ''), 120),
    left(regexp_replace(coalesce(client ->> 'tel', ''), '\D', '', 'g'), 20),
    left(coalesce(nullif(trim(client ->> 'indicatif'), ''), '229'), 6),
    left(coalesce(trim(client ->> 'adresse'), ''), 300),
    left(coalesce(trim(client ->> 'note'), ''), 500));

  for article in select * from jsonb_array_elements(articles) loop
    qte := greatest(1, least(99, coalesce((article ->> 'quantite')::int, 1)));
    select * into p from public.produits where id = article ->> 'produit_id';
    if not found then
      raise exception 'Un des produits de votre panier n''existe plus.';
    end if;
    if coalesce(p.stock, 0) <= 0 and not coalesce(p.sur_commande, false)
       and (p.appro_le is null or p.appro_le < current_date) then
      raise exception '« % » n''est plus disponible : retirez-le du panier.', p.nom;
    end if;
    devises := devises || coalesce(nullif((
      select b.devise from public.boutiques b where b.id = p.boutique_id), ''), 'FCFA');
    insert into public.commande_lignes (id, commande_id, produit_id, quantite)
    values ('lig_' || replace(gen_random_uuid()::text, '-', ''), nouvelle, p.id, qte);
  end loop;

  if (select count(distinct d) from unnest(devises) d) > 1 then
    raise exception 'Ces produits ne se paient pas dans la même monnaie : commandez boutique par boutique.';
  end if;
  update public.commandes set devise = coalesce(devises[1], 'FCFA') where id = nouvelle;

  select jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'total', c.total, 'devise', c.devise,
    'etat', c.etat,
    'boutiques', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', g.boutique_id,
               'nom', coalesce((select b.nom from public.boutiques b where b.id = g.boutique_id), ''),
               'whatsapp', coalesce((select b.whatsapp from public.boutiques b where b.id = g.boutique_id), ''),
               'indicatif', coalesce((select b.indicatif from public.boutiques b where b.id = g.boutique_id), '229'),
               'montant', g.montant,
               'lignes', g.lignes) order by g.montant desc)
        from (select l.boutique_id,
                     sum(l.prix * l.quantite) as montant,
                     jsonb_agg(jsonb_build_object('nom', l.nom, 'code', l.code,
                       'reference', l.reference, 'prix', l.prix,
                       'quantite', l.quantite) order by l.nom) as lignes
                from public.commande_lignes l
               where l.commande_id = c.id
               group by l.boutique_id) g), '[]'::jsonb))
    into sortie
    from public.commandes c where c.id = nouvelle;
  return sortie;
end $$;

revoke all on function public.creer_commande(jsonb, jsonb) from public;
grant execute on function public.creer_commande(jsonb, jsonb) to anon, authenticated;

-- ---------------------------------------------------------
-- 8. Retrouver ses commandes d'avant le compte
-- ---------------------------------------------------------
-- LE NUMÉRO DOIT ÊTRE VÉRIFIÉ. C'est toute la question : sans cela, il
-- suffirait de taper le numéro d'un voisin pour hériter de ses commandes,
-- de ses adresses et de ce qu'il achète.
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
     and client_tel = mien.tel;
  get diagnostics combien = row_count;
  return combien;
end $$;

revoke all on function public.rattacher_mes_commandes() from public, anon;
grant execute on function public.rattacher_mes_commandes() to authenticated;

-- ---------- Vérification ----------
select
  case when exists (select 1 from information_schema.tables
                     where table_schema = 'public' and table_name = 'clients')
       then 'en place' else 'MANQUANT' end                      as "table clients",
  case when exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'commandes'
                       and column_name = 'client_id')
       then 'en place' else 'MANQUANT' end                      as "commandes.client_id",
  (select count(*)::int from public.clients)                    as "comptes clients",
  (select count(*)::int from public.commandes
    where client_id is null)                                    as "commandes sans compte";
