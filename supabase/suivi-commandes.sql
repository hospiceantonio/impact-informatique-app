-- =========================================================
-- BIZZOO 3.59.0 — Le suivi des commandes en direct
--
--   Chaque modification d'une commande (étape, livreur, paiement à la
--   livraison) prévient en temps réel le client, l'équipe des boutiques
--   concernées, BIZZOO et le livreur : leurs écrans se mettent à jour
--   tout seuls.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- À coller APRÈS produit-masque.sql.
-- =========================================================

-- Les colonnes que les fonctions plus bas lisent.
alter table public.commande_lignes add column if not exists livreur_id uuid;

-- ---------- Le suivi des commandes en direct (3.59.0) ----------
-- CHAQUE MODIFICATION D'UNE COMMANDE PRÉVIENT TOUS CEUX QUI LA VOIENT :
-- le client qui l'a passée, l'administrateur et le modérateur de chaque
-- boutique concernée, BIZZOO, et le livreur qui la porte. Leur écran se
-- met à jour tout seul — étape, livreur, paiement à la livraison.
--
-- Pourquoi un « signal » plutôt que la commande elle-même : les lignes
-- de commande ont des colonnes que personne ne lit (le prix BIZZOO). Le
-- temps réel relit la ligne modifiée avec les droits de chacun ; on lui
-- donne donc une table qui ne porte RIEN d'autre que l'identifiant de la
-- commande et l'heure, et chaque écran relit ensuite ce qui le regarde
-- par ses chemins habituels.
create table if not exists public.commandes_signaux (
  commande_id text primary key references public.commandes(id) on delete cascade,
  maj_le      timestamptz not null default now()
);
alter table public.commandes_signaux enable row level security;
revoke all on public.commandes_signaux from anon, authenticated;
grant select on public.commandes_signaux to authenticated;

-- Qui voit cette commande : son client, l'équipe d'une boutique dont
-- elle porte un article (et BIZZOO), le livreur d'une de ses parts.
-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
-- Emprunté par les fonctions plus bas (3.59.0), recopié tel quel.
create or replace function public.boutique_du_compte() returns text
language sql stable security definer set search_path = public as $$
  select boutique_id from public.profils
   where id = auth.uid() and actif and public.role_courant() is not null;
$$;


create or replace function public.est_compte_enseigne() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select p.role in ('administrateur', 'moderateur') and p.boutique_id is null
      from public.profils p
     where p.id = auth.uid() and p.actif), false)
     and public.role_courant() is not null;
$$;


create or replace function public.est_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_courant() in
    ('superadministrateur', 'administrateur', 'moderateur'), false);
$$;



create or replace function public.peut_agir_sur(cible text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super()
      or public.est_compte_enseigne()
      or (public.est_equipe() and cible is not null
          and cible = public.boutique_du_compte());
$$;



create or replace function public.voit_la_commande(cible text) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then return false; end if;
  return exists (select 1 from public.commandes c where c.id = cible and c.client_id = auth.uid())
      or exists (select 1 from public.commande_lignes l
                  where l.commande_id = cible
                    and (l.livreur_id = auth.uid() or public.peut_agir_sur(l.boutique_id)));
end $$;
revoke all on function public.voit_la_commande(text) from public, anon;
grant execute on function public.voit_la_commande(text) to authenticated;

drop policy if exists "signaux de mes commandes" on public.commandes_signaux;
create policy "signaux de mes commandes" on public.commandes_signaux
  for select to authenticated using (public.voit_la_commande(commande_id));

create or replace function public.signaler_commande() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.commandes_signaux (commande_id, maj_le) values (new.id, now())
  on conflict (commande_id) do update set maj_le = now();
  return null;
end $$;
revoke all on function public.signaler_commande() from public, anon, authenticated;

create or replace function public.signaler_ligne() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.commandes_signaux (commande_id, maj_le) values (new.commande_id, now())
  on conflict (commande_id) do update set maj_le = now();
  return null;
end $$;
revoke all on function public.signaler_ligne() from public, anon, authenticated;

create or replace trigger commandes_signalent
  after update on public.commandes
  for each row execute function public.signaler_commande();
create or replace trigger lignes_signalent
  after insert or update on public.commande_lignes
  for each row execute function public.signaler_ligne();
create or replace trigger encaissements_signalent
  after insert or update on public.encaissements
  for each row execute function public.signaler_ligne();

-- Le temps réel porte ce signal.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                      where pubname = 'supabase_realtime' and schemaname = 'public'
                        and tablename = 'commandes_signaux') then
    alter publication supabase_realtime add table public.commandes_signaux;
  end if;
end $$;
