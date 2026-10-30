-- =========================================================
-- BIZZOO — les boutiques à vendeurs multiples (3.70.0)
-- Fichier de mise à jour : à exécuter une fois sur la base en service.
-- Sans danger : relançable, et rien n'est supprimé. Les boutiques
-- existantes restent « à vendeur unique » : rien ne change pour elles.
-- =========================================================

-- =========================================================
-- (3.70.0) LES BOUTIQUES À VENDEURS MULTIPLES
--
-- Une boutique est « à vendeur unique » (comme avant) ou « à vendeurs
-- multiples » : plusieurs vendeurs y proposent leurs produits. Chaque
-- produit d'une boutique à vendeurs multiples a SON vendeur (un compte
-- « vendeur » de BIZZOO) et SA part, en pour cent du prix de vente.
--
--   prix de vente 10 000, part du vendeur 80 % →
--     le vendeur reçoit 8 000 (au franc INFÉRIEUR), BIZZOO garde 2 000.
--
-- La part du vendeur EST le « prix BIZZOO » du produit : tout ce qui
-- existait déjà s'en sert sans changer — la ligne de commande la fige à
-- la vente, une remise (code promo, prix revendeur) se prend sur la
-- commission de BIZZOO, jamais sur le vendeur. La base la calcule
-- elle-même ; l'application ne l'écrit pas.
--
-- Le vendeur est crédité COMME UNE BOUTIQUE : payé mais pas livré, « en
-- attente » ; remis au client, « disponible » ; puis il demande un
-- versement, que le superadministrateur envoie (« versé »). Une ligne
-- annulée n'est jamais créditée, et une ligne ne se crédite qu'une fois
-- — le solde se CALCULE sur les lignes, il ne s'additionne pas à chaque
-- notification de paiement.
-- =========================================================

-- Les colonnes dont ces fonctions se servent. Elles viennent d'ailleurs,
-- et sont répétées ici : un fichier qui pose une fonction pose aussi les
-- colonnes qu'elle touche.
alter table public.boutiques add column if not exists taux_marge numeric(6,2) not null default 20;
alter table public.produits_prive add column if not exists taux_marge numeric(6,2);

-- ---------- Le rang « vendeur » ----------
alter table public.profils drop constraint if exists profils_role_check;
alter table public.profils add constraint profils_role_check
  check (role in ('superadministrateur', 'administrateur', 'moderateur', 'livreur', 'vendeur'));

-- (3.70.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false)
     and public.role_courant() is not null;
$$;
revoke all on function public.est_compte_enseigne()  from public, anon;
grant execute on function public.est_compte_enseigne() to authenticated;

-- (3.70.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;
grant execute on function public.boutique_du_compte() to authenticated;

create or replace function public.droit_enseigne(lequel text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_compte_enseigne() and coalesce((
    select case lequel
             when 'commandes' then p.peut_commandes
             when 'boutiques' then p.peut_boutiques
             when 'finances'  then p.peut_finances
             when 'produits'  then p.peut_modifier_produits
             else false
           end
      from public.profils p
     where p.id = auth.uid() and p.actif), false);
$$;
revoke all on function public.droit_enseigne(text)   from public, anon;
grant execute on function public.droit_enseigne(text)  to authenticated;

-- (3.70.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;
revoke all on function public.est_equipe() from public, anon, authenticated;
grant execute on function public.est_equipe() to authenticated;

create or replace function public.les_superadmins() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and p.role = 'superadministrateur';
$$;
revoke all on function public.les_superadmins()          from public, anon, authenticated;

create or replace function public.montant_lisible(n numeric, devise text default 'FCFA')
returns text
language sql immutable set search_path = public as $$
  select replace(to_char(coalesce(n, 0), 'FM999,999,999,990'), ',', ' ') || ' ' || coalesce(nullif(devise, ''), 'FCFA');
$$;
revoke all on function public.montant_lisible(numeric, text) from public, anon, authenticated;

create or replace function public.nom_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select coalesce(nullif(p.nom, ''), nullif(p.email, ''), 'l''équipe')
                     from public.profils p where p.id = auth.uid()), '');
$$;
revoke all on function public.nom_du_compte() from public, anon, authenticated;

create or replace function public.notifier(
  qui uuid[], quoi text, le_titre text, le_corps text,
  le_lien text, la_commande text, la_boutique text, qui_sonne boolean)
returns int
language plpgsql security definer set search_path = public as $$
declare combien int := 0;
begin
  if qui is null or array_length(qui, 1) is null then return 0; end if;
  insert into public.notifications
    (destinataire, type, titre, corps, lien, commande_id, boutique_id, sonne)
  select u, quoi, coalesce(le_titre, ''), coalesce(le_corps, ''),
         coalesce(le_lien, ''), la_commande, la_boutique, coalesce(qui_sonne, false)
    from unnest(qui) as u
   where u is not null
  on conflict do nothing;
  get diagnostics combien = row_count;
  return combien;
end $$;
revoke all on function public.notifier(uuid[], text, text, text, text, text, text, boolean)
  from public, anon, authenticated;

create or replace function public.prix_public(prix_bizzoo bigint, taux numeric)
returns int
language sql immutable as $$
  -- Le même calcul, au franc près, que celui de l'application admin.
  -- Les deux doivent donner le même chiffre : sinon réenregistrer un
  -- produit déplacerait son prix sans que personne ne l'ait demandé.
  -- (3.70.0) Arrondi au franc SUPÉRIEUR : la marge réglée est toujours
  -- tenue. 2 273 + 10 % = 2 500,3 → 2 501 ; l'arrondi au plus proche
  -- donnait 2 500, soit 9,99 % pour BIZZOO au lieu des 10 % réglés.
  select case when coalesce(prix_bizzoo, 0) <= 0 then 0
              else ceil(prix_bizzoo * (1 + greatest(0, coalesce(taux, 0)) / 100))::int
         end;
$$;
revoke all on function public.prix_public(bigint, numeric) from public, anon, authenticated;
grant execute on function public.prix_public(bigint, numeric) to authenticated;

create or replace function public.tient_la_caisse(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.droit_enseigne('commandes')
      or public.droit_enseigne('finances')
      or (public.est_admin() and cible is not null
          and cible = public.boutique_du_compte());
$$;
revoke all on function public.tient_la_caisse(text) from public, anon, authenticated;
grant execute on function public.tient_la_caisse(text) to authenticated;

-- Celui qui vend ses produits dans une boutique de BIZZOO, et rien
-- d'autre : il n'est pas de l'équipe (« est_equipe » ne le nomme pas), il
-- ne voit ni les commandes, ni les clients, ni le catalogue à modifier.
create or replace function public.est_vendeur() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() = 'vendeur', false);
$$;
revoke all on function public.est_vendeur() from public, anon;
grant execute on function public.est_vendeur() to authenticated;

-- ---------- Le type de boutique ----------
-- Combien de produits d'une boutique ont leur vendeur (pour le verrou
-- ci-dessous, qui tourne aux droits de l'appelant).
-- En plpgsql : son corps n'est lu qu'à l'usage, quand la colonne
-- « vendeur_id », posée plus bas, existe.
create or replace function public.produits_avec_vendeur(boutique text) returns int
language plpgsql stable security definer set search_path = public as $$
begin
  return (select count(*)::int from public.produits_prive pp
            join public.produits p on p.id = pp.produit_id
           where p.boutique_id = boutique and pp.vendeur_id is not null);
end $$;
revoke all on function public.produits_avec_vendeur(text) from public, anon;
grant execute on function public.produits_avec_vendeur(text) to authenticated;

-- Un compte vendeur actif ? (le verrou des produits tourne aux droits de
-- l'appelant, qui ne lit pas la fiche des autres comptes).
create or replace function public.vendeur_actif(cible uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profils v where v.id = cible and v.role = 'vendeur' and v.actif);
$$;
revoke all on function public.vendeur_actif(uuid) from public, anon;
grant execute on function public.vendeur_actif(uuid) to authenticated;

alter table public.boutiques add column if not exists vendeurs text not null default 'unique';
alter table public.boutiques drop constraint if exists boutiques_vendeurs_type;
alter table public.boutiques add constraint boutiques_vendeurs_type
  check (vendeurs in ('unique', 'multiples'));
-- La part la plus haute qu'un vendeur puisse recevoir dans cette boutique :
-- la règle de BIZZOO, qui borne ce que l'on saisit sur chaque produit.
alter table public.boutiques add column if not exists part_vendeur_max numeric(5,2) not null default 80;
alter table public.boutiques drop constraint if exists boutiques_part_vendeur_max;
alter table public.boutiques add constraint boutiques_part_vendeur_max
  check (part_vendeur_max between 1 and 100);

-- Le type et la part maximale sont des décisions de BIZZOO : le
-- superadministrateur seul. Et l'on ne repasse pas en « vendeur unique »
-- tant qu'un produit a encore son vendeur : ses ventes futures
-- changeraient de bénéficiaire sans que personne ne l'ait décidé.
-- AUX DROITS DE L'APPELANT (pas « security definer ») : c'est ce qui
-- permet de reconnaître l'application (« anon », « authenticated ») d'une
-- fonction de la base ou d'une mise à jour, qui passent.
create or replace function public.boutique_vendeurs_verrou() returns trigger
language plpgsql set search_path = public as $$
declare combien int;
begin
  if tg_op = 'INSERT' then
    if (new.vendeurs <> 'unique' or new.part_vendeur_max <> 80)
       and current_user in ('anon', 'authenticated') and not public.est_super() then
      raise exception 'Le type de boutique est choisi par le superadministrateur.';
    end if;
    return new;
  end if;
  if new.vendeurs is distinct from old.vendeurs
     or new.part_vendeur_max is distinct from old.part_vendeur_max then
    if current_user in ('anon', 'authenticated') and not public.est_super() then
      raise exception 'Le type de boutique et la part des vendeurs sont réglés par le superadministrateur.';
    end if;
  end if;
  if old.vendeurs = 'multiples' and new.vendeurs = 'unique' then
    combien := public.produits_avec_vendeur(new.id);
    if combien > 0 then
      raise exception '% produit(s) de cette boutique ont encore leur vendeur : elle reste à vendeurs multiples.',
        combien using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists boutiques_vendeurs_verrou on public.boutiques;
create trigger boutiques_vendeurs_verrou
  before insert or update on public.boutiques
  for each row execute function public.boutique_vendeurs_verrou();

-- ---------- Le vendeur d'un produit, et sa part ----------
alter table public.produits_prive add column if not exists vendeur_id uuid references public.profils(id) on delete set null;
alter table public.produits_prive add column if not exists taux_vendeur numeric(5,2);
alter table public.produits_prive drop constraint if exists produits_prive_taux_vendeur;
alter table public.produits_prive add constraint produits_prive_taux_vendeur
  check (taux_vendeur is null or taux_vendeur between 1 and 100);
create index if not exists produits_prive_vendeur on public.produits_prive(vendeur_id) where vendeur_id is not null;

-- La part du vendeur : le prix de vente par son pourcentage, au franc
-- INFÉRIEUR — la commission de BIZZOO n'est jamais rabotée par l'arrondi.
create or replace function public.part_vendeur(prix bigint, taux numeric) returns bigint
language sql immutable as $$
  select case when coalesce(prix, 0) <= 0 or coalesce(taux, 0) <= 0 then 0
              else floor(prix * least(100, taux) / 100)::bigint end;
$$;

-- À chaque écriture du prix privé d'un produit : dans une boutique à
-- vendeurs multiples, un vendeur (compte vendeur actif) et une part (dans
-- la borne de la boutique) — et la part calculée ici ; dans une boutique à
-- vendeur unique, ni l'un ni l'autre.
-- AUX DROITS DE L'APPELANT, pour la même raison que le verrou des
-- boutiques : l'application est tenue, la base et ses fonctions passent.
create or replace function public.produit_vendeur_controle() returns trigger
language plpgsql set search_path = public as $$
declare
  b     public.boutiques%rowtype;
  prix  bigint;
  appli boolean := current_user in ('anon', 'authenticated');
begin
  select bo.* into b from public.produits p join public.boutiques bo on bo.id = p.boutique_id
   where p.id = new.produit_id;
  if coalesce(b.vendeurs, 'unique') <> 'multiples' then
    if new.vendeur_id is not null or new.taux_vendeur is not null then
      if appli then
        raise exception 'Cette boutique est à vendeur unique : ses produits n''ont pas de vendeur.'
          using errcode = 'P0001';
      end if;
      new.vendeur_id := null;
      new.taux_vendeur := null;
    end if;
    return new;
  end if;
  if new.vendeur_id is null or new.taux_vendeur is null then
    -- Un produit d'avant le changement de type peut attendre son vendeur,
    -- mais on ne l'enregistre plus sans lui.
    if appli then
      raise exception 'Dans une boutique à vendeurs multiples, chaque produit a son vendeur et sa part.'
        using errcode = 'P0001';
    end if;
    return new;
  end if;
  if not public.vendeur_actif(new.vendeur_id) then
    raise exception 'Ce vendeur n''a pas de compte vendeur actif sur BIZZOO.' using errcode = 'P0001';
  end if;
  if new.taux_vendeur > b.part_vendeur_max then
    raise exception 'Dans cette boutique, la part d''un vendeur ne dépasse pas % %%.',
      trim(trailing ',' from replace(to_char(b.part_vendeur_max, 'FM990.99'), '.', ',')) using errcode = 'P0001';
  end if;
  select coalesce(p.prix, 0) into prix from public.produits p where p.id = new.produit_id;
  new.prix_grossiste := public.part_vendeur(prix, new.taux_vendeur);
  -- La marge de la boutique ne s'applique pas : le prix de vente est saisi.
  new.taux_marge := null;
  return new;
end $$;
drop trigger if exists produits_prive_vendeur on public.produits_prive;
create trigger produits_prive_vendeur
  before insert or update on public.produits_prive
  for each row execute function public.produit_vendeur_controle();

-- Le prix de vente change : la part du vendeur suit.
create or replace function public.produit_prix_part_vendeur() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.prix is distinct from old.prix then
    update public.produits_prive pp
       set prix_grossiste = public.part_vendeur(new.prix, pp.taux_vendeur)
     where pp.produit_id = new.id and pp.taux_vendeur is not null;
  end if;
  return new;
end $$;
drop trigger if exists produits_part_vendeur on public.produits;
create trigger produits_part_vendeur
  after update of prix on public.produits
  for each row execute function public.produit_prix_part_vendeur();

-- L'HISTORIQUE DES PARTS. Toute pose ou modification du vendeur ou de sa
-- part laisse une trace, que personne n'écrit à la main. Les ventes déjà
-- faites gardent la part de leur jour (figée sur la ligne).
create table if not exists public.parts_vendeurs_historique (
  id            bigserial primary key,
  produit_id    text not null,
  produit_nom   text not null default '',
  boutique_id   text,
  vendeur_avant uuid,
  vendeur_apres uuid,
  taux_avant    numeric(5,2),
  taux_apres    numeric(5,2),
  prix          bigint not null default 0,
  par           text not null default '',
  le            timestamptz not null default now()
);
create index if not exists parts_vendeurs_historique_le on public.parts_vendeurs_historique(le desc);
alter table public.parts_vendeurs_historique enable row level security;
revoke all on public.parts_vendeurs_historique from anon, authenticated;
revoke all on sequence public.parts_vendeurs_historique_id_seq from anon, authenticated;

create or replace function public.produit_vendeur_trace() returns trigger
language plpgsql security definer set search_path = public as $$
declare p public.produits%rowtype;
begin
  if tg_op = 'UPDATE' and new.vendeur_id is not distinct from old.vendeur_id
     and new.taux_vendeur is not distinct from old.taux_vendeur then
    return null;
  end if;
  if tg_op = 'INSERT' and new.vendeur_id is null and new.taux_vendeur is null then
    return null;
  end if;
  select * into p from public.produits where id = new.produit_id;
  insert into public.parts_vendeurs_historique
    (produit_id, produit_nom, boutique_id, vendeur_avant, vendeur_apres, taux_avant, taux_apres, prix, par)
  values (new.produit_id, coalesce(p.nom, ''), p.boutique_id,
          case when tg_op = 'UPDATE' then old.vendeur_id end, new.vendeur_id,
          case when tg_op = 'UPDATE' then old.taux_vendeur end, new.taux_vendeur,
          coalesce(p.prix, 0), coalesce(nullif(public.nom_du_compte(), ''), 'BIZZOO'));
  return null;
end $$;
drop trigger if exists produits_prive_vendeur_trace on public.produits_prive;
create trigger produits_prive_vendeur_trace
  after insert or update on public.produits_prive
  for each row execute function public.produit_vendeur_trace();

-- ---------- La vente : le vendeur et sa part, figés sur la ligne ----------
alter table public.commande_lignes add column if not exists vendeur_id uuid;
alter table public.commande_lignes add column if not exists taux_vendeur numeric(5,2);
create index if not exists commande_lignes_vendeur on public.commande_lignes(vendeur_id) where vendeur_id is not null;

-- Après « ligne_a_l_ecriture » (l'ordre des déclencheurs est celui de
-- leur nom) : le prix BIZZOO de la ligne est déjà la part du vendeur.
create or replace function public.ligne_vendeur() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  select pp.vendeur_id, pp.taux_vendeur into new.vendeur_id, new.taux_vendeur
    from public.produits_prive pp
    join public.produits p on p.id = pp.produit_id
    join public.boutiques b on b.id = p.boutique_id
   where pp.produit_id = new.produit_id and b.vendeurs = 'multiples'
     and pp.vendeur_id is not null and pp.taux_vendeur is not null;
  if not found then
    new.vendeur_id := null;
    new.taux_vendeur := null;
  end if;
  return new;
end $$;
drop trigger if exists lignes_vendeur on public.commande_lignes;
create trigger lignes_vendeur
  before insert on public.commande_lignes
  for each row execute function public.ligne_vendeur();

-- Ce qui a été vendu est vendu : le vendeur d'une ligne ne change plus.
create or replace function public.ligne_vendeur_fige() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.vendeur_id is distinct from old.vendeur_id
     or new.taux_vendeur is distinct from old.taux_vendeur then
    raise exception 'Une ligne de commande ne change que d''état : ce qui a été vendu est vendu';
  end if;
  return new;
end $$;
drop trigger if exists lignes_vendeur_fige on public.commande_lignes;
create trigger lignes_vendeur_fige
  before update on public.commande_lignes
  for each row execute function public.ligne_vendeur_fige();

-- ---------- Les vendeurs, pour le formulaire des produits ----------
create or replace function public.vendeurs_liste() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not (public.est_equipe() or public.est_super()) then '[]'::jsonb else
    coalesce((select jsonb_agg(jsonb_build_object(
                'id', p.id, 'nom', coalesce(nullif(p.nom, ''), p.email, 'Vendeur'), 'tel', p.tel)
                order by coalesce(nullif(p.nom, ''), p.email))
                from public.profils p where p.role = 'vendeur' and p.actif), '[]'::jsonb) end;
$$;
revoke all on function public.vendeurs_liste() from public, anon;
grant execute on function public.vendeurs_liste() to authenticated;

-- ---------- Son numéro de réception, ses versements ----------
create table if not exists public.vendeurs_reception (
  vendeur_id uuid primary key references public.profils(id) on delete cascade,
  tel        text not null default '',
  reseau     text not null default '' check (reseau in ('', 'MTN', 'MOOV', 'CELTIIS')),
  titulaire  text not null default '',
  maj_le     timestamptz not null default now()
);
alter table public.vendeurs_reception enable row level security;
revoke all on public.vendeurs_reception from anon, authenticated;

create table if not exists public.reversements_vendeurs (
  id          bigserial primary key,
  vendeur_id  uuid references public.profils(id) on delete set null,
  nom_vendeur text not null default '',
  montant     bigint not null check (montant > 0),
  tel         text not null default '',
  reseau      text not null default '',
  titulaire   text not null default '',
  etat        text not null default 'en_attente' check (etat in ('en_attente', 'valide', 'refuse')),
  demande_le  timestamptz not null default now(),
  decide_par  text not null default '',
  decide_le   timestamptz,
  reference   text not null default '',
  motif       text not null default ''
);
create index if not exists reversements_vendeurs_vendeur on public.reversements_vendeurs(vendeur_id, demande_le desc);
create index if not exists reversements_vendeurs_attente on public.reversements_vendeurs(demande_le) where etat = 'en_attente';
alter table public.reversements_vendeurs enable row level security;
revoke all on public.reversements_vendeurs from anon, authenticated;
revoke all on sequence public.reversements_vendeurs_id_seq from anon, authenticated;

-- Le solde d'un vendeur : le sien, ou celui de n'importe lequel pour le
-- superadministrateur. Sur les lignes des commandes PAYÉES : remises au
-- client, elles sont gagnées ; pas encore, elles sont à venir.
create or replace function public.solde_vendeur(cible uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  qui uuid := coalesce(cible, auth.uid());
  ventes bigint; gagne bigint; a_venir bigint; reverse bigint; attente bigint;
  r public.vendeurs_reception%rowtype;
begin
  if qui is null or not ((qui = auth.uid() and public.est_vendeur()) or public.est_super()) then
    raise exception 'Ce solde n''est pas le vôtre.';
  end if;
  select coalesce(sum(l.prix::bigint * l.quantite) filter (where l.etat = 'remise'), 0),
         coalesce(sum(l.prix_bizzoo::bigint * l.quantite) filter (where l.etat = 'remise'), 0),
         coalesce(sum(l.prix_bizzoo::bigint * l.quantite)
                    filter (where l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')), 0)
    into ventes, gagne, a_venir
    from public.commande_lignes l
    join public.commandes c on c.id = l.commande_id and c.etat = 'payee'
   where l.vendeur_id = qui;
  select coalesce(sum(v.montant) filter (where v.etat = 'valide'), 0),
         coalesce(sum(v.montant) filter (where v.etat = 'en_attente'), 0)
    into reverse, attente
    from public.reversements_vendeurs v where v.vendeur_id = qui;
  select * into r from public.vendeurs_reception where vendeur_id = qui;
  return jsonb_build_object(
    'ventes', ventes, 'gagne', gagne, 'a_venir', a_venir, 'reverse', reverse, 'en_attente', attente,
    'disponible', greatest(0, gagne - reverse - attente), 'devise', 'FCFA',
    'reception', case when r.vendeur_id is null or r.tel = '' then null
                      else jsonb_build_object('tel', r.tel, 'reseau', r.reseau, 'titulaire', r.titulaire,
                                              'maj_le', r.maj_le) end);
end $$;
revoke all on function public.solde_vendeur(uuid) from public, anon;
grant execute on function public.solde_vendeur(uuid) to authenticated;

-- L'ESPACE DU VENDEUR : ses produits, ses ventes, son solde, ses
-- versements. Ni le nom ni le numéro d'aucun client : ce n'est pas son
-- affaire.
create or replace function public.espace_vendeur(cible uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  qui uuid := coalesce(cible, auth.uid());
  solde jsonb;
begin
  solde := public.solde_vendeur(qui);   -- refuse qui n'a pas à le voir
  return jsonb_build_object(
    'vendeur', (select jsonb_build_object('id', p.id, 'nom', coalesce(nullif(p.nom, ''), p.email), 'tel', p.tel)
                  from public.profils p where p.id = qui),
    'solde', solde,
    'produits', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'nom', p.nom, 'code', p.code, 'boutique', b.nom, 'prix', p.prix,
        'taux', pp.taux_vendeur, 'part', pp.prix_grossiste, 'stock', p.stock,
        'sur_commande', p.sur_commande,
        'vendus', coalesce(v.vendus, 0), 'en_cours', coalesce(v.en_cours, 0),
        'ventes', coalesce(v.ventes, 0), 'gagne', coalesce(v.gagne, 0))
        order by p.nom)
      from public.produits_prive pp
      join public.produits p on p.id = pp.produit_id
      left join public.boutiques b on b.id = p.boutique_id
      left join lateral (
        select sum(l.quantite) filter (where l.etat = 'remise') as vendus,
               sum(l.quantite) filter (where l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')) as en_cours,
               sum(l.prix::bigint * l.quantite) filter (where l.etat = 'remise') as ventes,
               sum(l.prix_bizzoo::bigint * l.quantite) filter (where l.etat = 'remise') as gagne
          from public.commande_lignes l
          join public.commandes c on c.id = l.commande_id and c.etat = 'payee'
         where l.produit_id = p.id and l.vendeur_id = qui) v on true
     where pp.vendeur_id = qui), '[]'::jsonb),
    'lignes', coalesce((select jsonb_agg(x.j order by x.le desc) from (
        select c.cree_le as le, jsonb_build_object(
          'le', c.cree_le, 'numero', c.numero, 'produit', l.nom, 'quantite', l.quantite,
          'prix', l.prix, 'taux', l.taux_vendeur, 'part', l.prix_bizzoo::bigint * l.quantite,
          'statut', case when l.etat = 'remise' then 'disponible'
                         when l.etat = 'annulee' then 'annulee' else 'en_attente' end) as j
          from public.commande_lignes l
          join public.commandes c on c.id = l.commande_id and c.etat = 'payee'
         where l.vendeur_id = qui
         order by c.cree_le desc limit 100) x), '[]'::jsonb),
    'versements', coalesce((select jsonb_agg(jsonb_build_object(
        'id', v.id, 'montant', v.montant, 'etat', v.etat, 'tel', v.tel, 'reseau', v.reseau,
        'demande_le', v.demande_le, 'decide_le', v.decide_le, 'reference', v.reference, 'motif', v.motif)
        order by v.demande_le desc)
      from public.reversements_vendeurs v where v.vendeur_id = qui), '[]'::jsonb));
end $$;
revoke all on function public.espace_vendeur(uuid) from public, anon;
grant execute on function public.espace_vendeur(uuid) to authenticated;

-- SON NUMÉRO DE RÉCEPTION : le vendeur le règle lui-même ; BIZZOO est
-- prévenu de chaque changement — c'est par là qu'on détournerait ses gains.
create or replace function public.regler_reception_vendeur(tel text, reseau text, titulaire text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  moi      uuid := auth.uid();
  national text := regexp_replace(coalesce(tel, ''), '\D', '', 'g');
  res      text := upper(coalesce(reseau, ''));
begin
  if moi is null or not public.est_vendeur() then
    raise exception 'Seul un vendeur règle son numéro de réception.';
  end if;
  national := regexp_replace(national, '^229', '');
  if length(national) = 8 then national := '01' || national; end if;
  if length(national) <> 10 or national !~ '^01[0-9]+' then
    raise exception 'Ce numéro n''a pas la forme d''un numéro béninois : dix chiffres commençant par 01.'
      using errcode = 'P0001';
  end if;
  if res not in ('MTN', 'MOOV', 'CELTIIS') then
    raise exception 'Choisissez le réseau du numéro : MTN, Moov ou Celtiis.' using errcode = 'P0001';
  end if;
  insert into public.vendeurs_reception (vendeur_id, tel, reseau, titulaire, maj_le)
  values (moi, national, res, left(trim(coalesce(titulaire, '')), 80), now())
  on conflict (vendeur_id) do update
     set tel = excluded.tel, reseau = excluded.reseau, titulaire = excluded.titulaire, maj_le = now();
  perform public.notifier(public.les_superadmins(), 'reception_reglee',
    'Numéro de réception d''un vendeur — ' || public.nom_du_compte(),
    public.nom_du_compte() || ' a réglé son numéro de réception : ' || res || ' ' || national ||
      coalesce(' (' || nullif(trim(coalesce(titulaire, '')), '') || ')', '') || '.',
    '#/reversements', null, null, false);
  return jsonb_build_object('tel', national, 'reseau', res);
end $$;
revoke all on function public.regler_reception_vendeur(text, text, text) from public, anon;
grant execute on function public.regler_reception_vendeur(text, text, text) to authenticated;

create or replace function public.demander_reversement_vendeur(montant bigint)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  moi   uuid := auth.uid();
  solde jsonb;
  r     public.vendeurs_reception%rowtype;
  qui   text := public.nom_du_compte();
  nouv  bigint;
begin
  if moi is null or not public.est_vendeur() then
    raise exception 'Seul un vendeur demande le versement de ses gains.';
  end if;
  -- Une demande à la fois : on la tranche avant la suivante.
  perform 1 from public.profils p where p.id = moi for update;
  select * into r from public.vendeurs_reception where vendeur_id = moi;
  if r.vendeur_id is null or r.tel = '' then
    raise exception 'Réglez d''abord le numéro qui recevra vos gains.' using errcode = 'P0001';
  end if;
  if coalesce(montant, 0) <= 0 then
    raise exception 'Indiquez le montant à verser.' using errcode = 'P0001';
  end if;
  solde := public.solde_vendeur(moi);
  if montant > (solde ->> 'disponible')::bigint then
    raise exception 'Votre solde disponible est de % : vous ne pouvez pas demander plus.',
      public.montant_lisible((solde ->> 'disponible')::bigint, 'FCFA') using errcode = 'P0001';
  end if;
  insert into public.reversements_vendeurs (vendeur_id, nom_vendeur, montant, tel, reseau, titulaire)
  values (moi, qui, montant, r.tel, r.reseau, r.titulaire)
  returning id into nouv;
  perform public.notifier(public.les_superadmins(), 'reversement_demande',
    'Versement demandé par un vendeur : ' || public.montant_lisible(montant, 'FCFA'),
    qui || ' — à envoyer sur ' || r.reseau || ' ' || r.tel ||
      coalesce(' (' || nullif(r.titulaire, '') || ')', '') || '.',
    '#/reversements', null, null, true);
  return nouv;
end $$;
revoke all on function public.demander_reversement_vendeur(bigint) from public, anon;
grant execute on function public.demander_reversement_vendeur(bigint) to authenticated;

-- La liste : le vendeur, les siennes ; le superadministrateur, toutes.
create or replace function public.reversements_vendeurs_liste()
returns table (id bigint, vendeur_id uuid, nom_vendeur text, montant bigint, tel text, reseau text,
               titulaire text, etat text, demande_le timestamptz, decide_par text,
               decide_le timestamptz, reference text, motif text)
language plpgsql stable security definer set search_path = public as $$
declare moi uuid := auth.uid();
begin
  if moi is null or not (public.est_super() or public.est_vendeur()) then return; end if;
  return query
    select v.id, v.vendeur_id, v.nom_vendeur, v.montant, v.tel, v.reseau, v.titulaire, v.etat,
           v.demande_le, v.decide_par, v.decide_le, v.reference, v.motif
      from public.reversements_vendeurs v
     where public.est_super() or v.vendeur_id = moi
     order by (v.etat = 'en_attente') desc, v.demande_le desc
     limit 200;
end $$;
revoke all on function public.reversements_vendeurs_liste() from public, anon;
grant execute on function public.reversements_vendeurs_liste() to authenticated;

create or replace function public.decider_reversement_vendeur(cible bigint, accord boolean,
  reference text default '', motif text default '')
returns text
language plpgsql security definer set search_path = public as $$
declare
  v   public.reversements_vendeurs%rowtype;
  ref text := left(trim(coalesce(reference, '')), 60);
  pourquoi text := left(trim(coalesce(motif, '')), 300);
begin
  if not public.est_super() then
    raise exception 'Seul le superadministrateur valide un versement.';
  end if;
  select * into v from public.reversements_vendeurs where id = cible for update;
  if not found then raise exception 'Demande introuvable.'; end if;
  if v.etat <> 'en_attente' then
    raise exception 'Cette demande est déjà tranchée.' using errcode = 'P0001';
  end if;
  if accord and length(ref) < 4 then
    raise exception 'Notez la référence de la transaction envoyée.' using errcode = 'P0001';
  end if;
  update public.reversements_vendeurs
     set etat = case when accord then 'valide' else 'refuse' end,
         decide_par = public.nom_du_compte(), decide_le = now(),
         reference = case when accord then ref else '' end, motif = pourquoi
   where id = cible;
  perform public.notifier(array[v.vendeur_id], 'reversement_decide',
    case when accord then 'Gains envoyés : ' || public.montant_lisible(v.montant, 'FCFA')
         else 'Versement refusé : ' || public.montant_lisible(v.montant, 'FCFA') end,
    case when accord then 'Envoyé sur ' || v.reseau || ' ' || v.tel || ' — référence ' || ref || '.'
         else 'BIZZOO a refusé la demande' || coalesce(' : « ' || nullif(pourquoi, '') || ' »', '') ||
              '. Le montant revient à votre solde.' end,
    '#/ventes', null, null, true);
  return case when accord then 'valide' else 'refuse' end;
end $$;
revoke all on function public.decider_reversement_vendeur(bigint, boolean, text, text) from public, anon;
grant execute on function public.decider_reversement_vendeur(bigint, boolean, text, text) to authenticated;

-- ---------- Le tableau du superadministrateur ----------
-- Chaque vendeur : ses ventes livrées, sa part, la commission de BIZZOO
-- (avant les codes promo, qui se prennent sur elle), ce qui est à venir,
-- versé, demandé, disponible.
create or replace function public.ventes_vendeurs() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.est_super() then
    raise exception 'Réservé au superadministrateur.';
  end if;
  return coalesce((select jsonb_agg(x.j order by x.nom) from (
    select coalesce(nullif(p.nom, ''), p.email) as nom, jsonb_build_object(
      'id', p.id, 'nom', coalesce(nullif(p.nom, ''), p.email), 'tel', p.tel, 'actif', p.actif,
      'produits', (select count(*) from public.produits_prive pp where pp.vendeur_id = p.id),
      'ventes', coalesce(s.ventes, 0), 'part', coalesce(s.gagne, 0),
      'commission', coalesce(s.ventes, 0) - coalesce(s.gagne, 0),
      'a_venir', coalesce(s.a_venir, 0),
      'reverse', coalesce(r.reverse, 0), 'en_attente', coalesce(r.attente, 0),
      'disponible', greatest(0, coalesce(s.gagne, 0) - coalesce(r.reverse, 0) - coalesce(r.attente, 0))) as j
      from public.profils p
      left join lateral (
        select sum(l.prix::bigint * l.quantite) filter (where l.etat = 'remise') as ventes,
               sum(l.prix_bizzoo::bigint * l.quantite) filter (where l.etat = 'remise') as gagne,
               sum(l.prix_bizzoo::bigint * l.quantite)
                 filter (where l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')) as a_venir
          from public.commande_lignes l
          join public.commandes c on c.id = l.commande_id and c.etat = 'payee'
         where l.vendeur_id = p.id) s on true
      left join lateral (
        select sum(v.montant) filter (where v.etat = 'valide') as reverse,
               sum(v.montant) filter (where v.etat = 'en_attente') as attente
          from public.reversements_vendeurs v where v.vendeur_id = p.id) r on true
     where p.role = 'vendeur') x), '[]'::jsonb);
end $$;
revoke all on function public.ventes_vendeurs() from public, anon;
grant execute on function public.ventes_vendeurs() to authenticated;

-- L'historique des parts, pour le superadministrateur.
create or replace function public.parts_vendeurs_historique_liste() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.est_super() then
    raise exception 'Réservé au superadministrateur.';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'le', h.le, 'produit', h.produit_nom, 'boutique', b.nom,
      'vendeur_avant', coalesce(nullif(va.nom, ''), va.email), 'vendeur_apres', coalesce(nullif(vp.nom, ''), vp.email),
      'taux_avant', h.taux_avant, 'taux_apres', h.taux_apres, 'prix', h.prix, 'par', h.par)
      order by h.le desc)
    from (select * from public.parts_vendeurs_historique order by le desc limit 200) h
    left join public.boutiques b on b.id = h.boutique_id
    left join public.profils va on va.id = h.vendeur_avant
    left join public.profils vp on vp.id = h.vendeur_apres), '[]'::jsonb);
end $$;
revoke all on function public.parts_vendeurs_historique_liste() from public, anon;
grant execute on function public.parts_vendeurs_historique_liste() to authenticated;


-- ---------- Ce qui existait, et qui en tient compte ----------
-- Le solde d'une boutique ne compte plus la part de ses vendeurs.
create or replace function public.solde_boutique(cible text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  gagne bigint; a_venir bigint; encaisse bigint; reverse bigint; attente bigint;
  r public.boutiques_reception%rowtype;
begin
  if not public.tient_la_caisse(cible) then
    raise exception 'Ce solde n''est pas celui de votre boutique.';
  end if;
  select coalesce(sum(l.prix_bizzoo::bigint * l.quantite) filter (where l.etat = 'remise'), 0),
         coalesce(sum(l.prix_bizzoo::bigint * l.quantite)
                    filter (where l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')), 0)
    into gagne, a_venir
    from public.commande_lignes l
    join public.commandes c on c.id = l.commande_id and c.etat = 'payee'
   where l.boutique_id = cible
     -- (3.70.0) La part d'un vendeur va au vendeur, pas à la boutique.
     and l.vendeur_id is null;
  select coalesce(sum(x.montant), 0) into encaisse from public.encaissements x
   where x.boutique_id = cible and x.mode = 'especes' and x.remis_le is not null;
  select coalesce(sum(v.montant) filter (where v.etat = 'valide'), 0),
         coalesce(sum(v.montant) filter (where v.etat = 'en_attente'), 0)
    into reverse, attente
    from public.reversements v where v.boutique_id = cible;
  select * into r from public.boutiques_reception where boutique_id = cible;
  return jsonb_build_object(
    'gagne', gagne, 'a_venir', a_venir, 'deja_encaisse', encaisse,
    'reverse', reverse, 'en_attente', attente,
    'disponible', greatest(0, gagne - encaisse - reverse - attente),
    'devise', coalesce((select nullif(b.devise, '') from public.boutiques b where b.id = cible), 'FCFA'),
    'reception', case when r.boutique_id is null or r.tel = '' then null
                      else jsonb_build_object('tel', r.tel, 'reseau', r.reseau, 'titulaire', r.titulaire,
                                              'maj_le', r.maj_le, 'maj_par', r.maj_par) end);
end $$;
revoke all on function public.solde_boutique(text) from public, anon;
grant execute on function public.solde_boutique(text) to authenticated;

-- Le changement de marge d'une boutique ne recalcule pas le prix saisi
-- d'un produit de vendeur.
create or replace function public.boutique_prix_a_jour() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.taux_marge is not distinct from old.taux_marge then return new; end if;

  update public.produits p
     set prix = public.prix_public(pp.prix_grossiste,
                                   coalesce(pp.taux_marge, new.taux_marge))
    from public.produits_prive pp
   where pp.produit_id = p.id
     and p.boutique_id = new.id
     and coalesce(pp.prix_grossiste, 0) > 0
     -- (3.70.0) Le prix d'un produit de vendeur est saisi : la marge de la
     -- boutique ne le recalcule pas.
     and pp.taux_vendeur is null
     -- N'écrire que ce qui change vraiment : un article dont le prix
     -- tombe juste n'a pas à passer par les déclencheurs pour rien.
     and p.prix is distinct from public.prix_public(pp.prix_grossiste,
                                   coalesce(pp.taux_marge, new.taux_marge));
  return new;
end $$;
