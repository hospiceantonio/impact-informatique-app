-- BIZZOO : préfiltrage et signalement des avis publics.
-- À appliquer après avis.sql. Les avis ordinaires restent immédiatement
-- visibles, y compris depuis l'ancien site web ; un texte manifestement
-- problématique est refusé avec une erreur lisible avant publication.

-- Le fichier peut aussi être appliqué seul à une base disposant déjà
-- de la table d'avis mais créée avant ces deux colonnes.
alter table public.avis add column if not exists auteur text not null default '';
alter table public.avis add column if not exists reponse text not null default '';

create or replace function public.avis_filtre_code(contenu text) returns text
language plpgsql immutable set search_path = public as $$
declare valeur text := coalesce(contenu, '');
begin
  if valeur ~* '(https?://|www[.]|[[:alnum:]._%+-]+@[[:alnum:].-]+[.][[:alpha:]]{2,})' or
     valeur ~* '(\m(tel|telephone|téléphone|whatsapp|contact|appeler|appelez)\M[^[:digit:]]{0,12}([0-9][ .-]?){8,10})' or
     valeur ~* '((\+|00)229[ .-]?([0-9][ .-]?){8,10})' then
    return 'coordonnees';
  end if;
  if valeur ~* '(\m(porno|pornographie|pornographique|onlyfans|nudes?)\M|kill[[:space:]]+yourself|va[[:space:]]+te[[:space:]]+tuer)' then
    return 'abus';
  end if;
  return '';
end $$;

create or replace function public.avis_filtrer_publication() returns trigger
language plpgsql set search_path = public as $$
declare code text;
begin
  if tg_op = 'INSERT' then
    code := public.avis_filtre_code(concat_ws(' ', new.texte, new.auteur, new.reponse));
  else
    -- Un ancien texte licite lors de sa publication ne doit pas empêcher
    -- une réponse ou une correction sans rapport avec ce texte.
    code := public.avis_filtre_code(concat_ws(' ',
      case when new.texte is distinct from old.texte then new.texte end,
      case when new.auteur is distinct from old.auteur then new.auteur end,
      case when new.reponse is distinct from old.reponse then new.reponse end));
  end if;
  if code = 'coordonnees' then
    raise exception 'Ne publiez ni lien, ni numéro, ni adresse e-mail dans un avis ou une réponse';
  end if;
  if code = 'abus' then
    raise exception 'Ce contenu ne peut pas être publié. Modifiez-le ou contactez BIZZOO';
  end if;
  return new;
end $$;

drop trigger if exists avis_prepublication on public.avis;
create trigger avis_prepublication
  before insert or update of texte, auteur, reponse on public.avis
  for each row execute function public.avis_filtrer_publication();

-- Un signalement est une demande de contrôle, jamais un masquage automatique.
-- La cible "auteur" permet de signaler le comportement d'une personne,
-- indépendamment du texte de l'avis choisi comme preuve.
create table if not exists public.avis_signalements (
  id           bigint generated always as identity primary key,
  avis_id      text not null references public.avis(id) on delete cascade,
  auteur_id    uuid not null references auth.users(id) on delete cascade,
  signale_par  uuid not null references auth.users(id) on delete cascade,
  cible        text not null check (cible in ('avis', 'auteur')),
  motif        text not null check (motif in
                 ('harcelement', 'haine', 'sexuel', 'donnees_personnelles', 'spam', 'autre')),
  details      text not null default '',
  etat         text not null default 'ouvert'
               check (etat in ('ouvert', 'traite', 'rejete')),
  cree_le      timestamptz not null default now(),
  traite_le    timestamptz,
  traite_par   uuid references auth.users(id) on delete set null,
  decision     text not null default ''
);
create unique index if not exists avis_signalements_une_demande_ouverte
  on public.avis_signalements(avis_id, signale_par, cible) where etat = 'ouvert';
create index if not exists avis_signalements_a_traiter
  on public.avis_signalements(cree_le) where etat = 'ouvert';

alter table public.avis_signalements enable row level security;
drop policy if exists "signalements lecture auteur et enseigne" on public.avis_signalements;
create policy "signalements lecture auteur et enseigne" on public.avis_signalements
  for select to authenticated
  using (signale_par = auth.uid() or public.est_super());
revoke all on public.avis_signalements from anon, authenticated;
grant select on public.avis_signalements to authenticated;

create or replace function public.signaler_avis(
  avis_cible text, cible_signalee text, motif_signalement text, precisions text default '')
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  auteur uuid;
  identifiant bigint;
begin
  if moi is null or not exists (select 1 from public.clients where id = moi) then
    raise exception 'Connectez-vous comme client pour signaler cet avis';
  end if;
  if cible_signalee not in ('avis', 'auteur') or
     motif_signalement not in
       ('harcelement', 'haine', 'sexuel', 'donnees_personnelles', 'spam', 'autre') then
    raise exception 'Choisissez un motif de signalement valide';
  end if;
  select client_id into auteur from public.avis
   where id = avis_cible and not masque;
  if auteur is null then raise exception 'Cet avis n''est plus public'; end if;
  if auteur = moi then raise exception 'Vous ne pouvez pas signaler votre propre avis'; end if;

  insert into public.avis_signalements
    (avis_id, auteur_id, signale_par, cible, motif, details)
  values (avis_cible, auteur, moi, cible_signalee, motif_signalement,
          left(trim(coalesce(precisions, '')), 500))
  on conflict (avis_id, signale_par, cible) where etat = 'ouvert'
  do update set motif = excluded.motif, details = excluded.details, cree_le = now()
  returning id into identifiant;
  return identifiant;
end $$;
revoke all on function public.signaler_avis(text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.signaler_avis(text, text, text, text)
  to authenticated;

-- Une sanction ciblée empêche un auteur abusif de déposer ou modifier
-- des avis, sans l'empêcher de consulter ses commandes ni d'acheter.
create table if not exists public.avis_auteurs_bloques (
  client_id  uuid primary key references auth.users(id) on delete cascade,
  auteur    text not null default '',
  motif     text not null,
  bloque_le timestamptz not null default now(),
  bloque_par uuid references auth.users(id) on delete set null
);
alter table public.avis_auteurs_bloques enable row level security;
drop policy if exists "auteurs bloqués lecture enseigne" on public.avis_auteurs_bloques;
create policy "auteurs bloqués lecture enseigne" on public.avis_auteurs_bloques
  for select to authenticated using (public.est_super());
revoke all on public.avis_auteurs_bloques from anon, authenticated;
grant select on public.avis_auteurs_bloques to authenticated;

create or replace function public.avis_interdire_auteur() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.avis_auteurs_bloques b
              where b.client_id = new.client_id) then
    raise exception 'Votre compte ne peut plus publier d''avis. Contactez BIZZOO';
  end if;
  return new;
end $$;
drop trigger if exists avis_auteur_interdit on public.avis;
create trigger avis_auteur_interdit
  before insert or update of note, texte, produit_id, boutique_id on public.avis
  for each row execute function public.avis_interdire_auteur();

create or replace function public.bloquer_auteur_avis(
  auteur_cible uuid, bloquer boolean, justification text default '')
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  raison text := left(trim(coalesce(justification, '')), 300);
  nom_public text;
begin
  if not public.est_super() then
    raise exception 'Seule l''enseigne peut bloquer les avis d''un auteur';
  end if;
  if coalesce(bloquer, false) then
    if not exists (select 1 from public.clients where id = auteur_cible) then
      raise exception 'Auteur introuvable';
    end if;
    if raison = '' then raise exception 'Indiquez pourquoi cet auteur est bloqué'; end if;
    select coalesce(a.auteur, '') into nom_public from public.avis a
     where a.client_id = auteur_cible order by a.cree_le desc limit 1;
    insert into public.avis_auteurs_bloques
      (client_id, auteur, motif, bloque_par)
    values (auteur_cible, coalesce(nom_public, ''), raison, auth.uid())
    on conflict (client_id) do update
      set auteur = excluded.auteur, motif = excluded.motif,
          bloque_le = now(), bloque_par = excluded.bloque_par;
  else
    delete from public.avis_auteurs_bloques where client_id = auteur_cible;
  end if;
  return true;
end $$;
revoke all on function public.bloquer_auteur_avis(uuid, boolean, text)
  from public, anon, authenticated;
grant execute on function public.bloquer_auteur_avis(uuid, boolean, text)
  to authenticated;

-- Le superadministrateur clôt une demande et, si elle est fondée,
-- masque l'avis. Le déclencheur existant le retire des moyennes.
create or replace function public.traiter_signalement_avis(
  signalement bigint, masquer boolean, justification text default '')
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  demande public.avis_signalements%rowtype;
  raison text := left(trim(coalesce(justification, '')), 300);
begin
  if not public.est_super() then
    raise exception 'Seule l''enseigne peut traiter un signalement';
  end if;
  select * into demande from public.avis_signalements
   where id = signalement and etat = 'ouvert' for update;
  if not found then raise exception 'Signalement déjà traité ou introuvable'; end if;
  if coalesce(masquer, false) and raison = '' then
    raise exception 'Indiquez pourquoi cet avis est masqué';
  end if;
  if coalesce(masquer, false) then
    update public.avis
       set masque = true, motif_masque = raison, maj_le = now()
     where id = demande.avis_id;
    if not found then raise exception 'Avis introuvable'; end if;
  end if;
  update public.avis_signalements
     set etat = case when coalesce(masquer, false) then 'traite' else 'rejete' end,
         traite_le = now(), traite_par = auth.uid(), decision = raison
   where id = signalement;
  return true;
end $$;
revoke all on function public.traiter_signalement_avis(bigint, boolean, text)
  from public, anon, authenticated;
grant execute on function public.traiter_signalement_avis(bigint, boolean, text)
  to authenticated;

-- Les fiches et médias des commerçants sont eux aussi visibles du public.
-- Un signalement n'interrompt jamais la vente automatiquement : la
-- plateforme examine la fiche, puis corrige ou retire si nécessaire.
create table if not exists public.produits_signalements (
  id           bigint generated always as identity primary key,
  produit_id   text not null references public.produits(id) on delete cascade,
  nom_produit  text not null default '',
  boutique_id  text not null default '',
  signale_par  uuid not null references auth.users(id) on delete cascade,
  motif        text not null check (motif in
                 ('trompeur', 'contrefacon', 'haine', 'sexuel',
                  'donnees_personnelles', 'spam', 'autre')),
  details      text not null default '',
  etat         text not null default 'ouvert'
               check (etat in ('ouvert', 'traite')),
  cree_le      timestamptz not null default now(),
  traite_le    timestamptz,
  traite_par   uuid references auth.users(id) on delete set null,
  decision     text not null default ''
);
create unique index if not exists produits_signalements_une_demande_ouverte
  on public.produits_signalements(produit_id, signale_par) where etat = 'ouvert';
create index if not exists produits_signalements_a_traiter
  on public.produits_signalements(cree_le) where etat = 'ouvert';
alter table public.produits_signalements enable row level security;
drop policy if exists "signalements produits lecture" on public.produits_signalements;
create policy "signalements produits lecture" on public.produits_signalements
  for select to authenticated
  using (signale_par = auth.uid() or public.est_super());
revoke all on public.produits_signalements from anon, authenticated;
grant select on public.produits_signalements to authenticated;

create or replace function public.signaler_produit(
  produit_cible text, motif_signalement text, precisions text default '')
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  fiche public.produits%rowtype;
  identifiant bigint;
begin
  if moi is null or not exists (select 1 from public.clients where id = moi) then
    raise exception 'Connectez-vous comme client pour signaler cette fiche';
  end if;
  if motif_signalement not in ('trompeur', 'contrefacon', 'haine', 'sexuel',
                               'donnees_personnelles', 'spam', 'autre') then
    raise exception 'Choisissez un motif de signalement valide';
  end if;
  select p.* into fiche from public.produits p
    left join public.boutiques b on b.id = p.boutique_id
   where p.id = produit_cible
     and (p.boutique_id is null or coalesce(b.actif, false));
  if not found then raise exception 'Cette fiche n''existe plus'; end if;
  insert into public.produits_signalements
    (produit_id, nom_produit, boutique_id, signale_par, motif, details)
  values (fiche.id, left(fiche.nom, 200), coalesce(fiche.boutique_id, ''),
          moi, motif_signalement, left(trim(coalesce(precisions, '')), 500))
  on conflict (produit_id, signale_par) where etat = 'ouvert'
  do update set motif = excluded.motif, details = excluded.details,
                nom_produit = excluded.nom_produit, cree_le = now()
  returning id into identifiant;
  return identifiant;
end $$;
revoke all on function public.signaler_produit(text, text, text)
  from public, anon, authenticated;
grant execute on function public.signaler_produit(text, text, text)
  to authenticated;

create or replace function public.traiter_signalement_produit(
  signalement bigint, justification text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare raison text := left(trim(coalesce(justification, '')), 300);
begin
  if not public.est_super() then
    raise exception 'Seule l''enseigne peut traiter un signalement de fiche';
  end if;
  if raison = '' then raise exception 'Indiquez la suite donnée au signalement'; end if;
  update public.produits_signalements
     set etat = 'traite', traite_le = now(), traite_par = auth.uid(),
         decision = raison
   where id = signalement and etat = 'ouvert';
  if not found then raise exception 'Signalement déjà traité ou introuvable'; end if;
  return true;
end $$;
revoke all on function public.traiter_signalement_produit(bigint, text)
  from public, anon, authenticated;
grant execute on function public.traiter_signalement_produit(bigint, text)
  to authenticated;
