-- =========================================================
-- BIZZOO Personnel : le suivi des commandes
--
-- Le tableau de bord demandé par BIZZOO (« Tableau de bord de suivi
-- des commandes ») : une commande par ligne, un statut actualisé, des
-- alertes à part du statut, des incidents, une clôture, un bilan par
-- jour, semaine ou mois, et l'export pour Excel.
--
-- CE FICHIER NE TOUCHE À AUCUNE RÈGLE DE LA PLACE DE MARCHÉ. Il ajoute :
--   - un JOURNAL des étapes de chaque article (« rh_journal_lignes »),
--     tenu par un déclencheur qui ne bloque JAMAIS une commande : une
--     erreur du journal est avalée, la commande passe. C'est lui qui
--     donne les délais (vu → préparé → reçu par le client) ;
--   - ce que l'administration note elle-même : les étapes que le
--     terrain ne saisit pas encore (colis récupéré, livraison échouée,
--     retour en cours, retourné au marchand), la zone corrigée, les
--     observations, les incidents, la clôture ;
--   - les seuils des retards, réglables ;
--   - un référentiel des zones du Bénin, pour lire la zone dans
--     l'adresse libre du client.
--
-- QUI : le CEO et l'administration voient et agissent, montants
-- compris ; le responsable d'un profil coché « suivi » voit et agit,
-- SANS aucun montant. Les autres : rien.
--
-- Le journal ne connaît que ce qui arrive APRÈS son installation. Pour
-- les commandes d'avant, il reconstitue ce que la base avait daté
-- (commande, paiement, course acceptée, réception confirmée) et le
-- marque « reconstitué ».
--
-- Se colle tel quel dans l'éditeur SQL de Supabase, et se rejoue.
-- =========================================================

-- La rubrique « suivi » s'ajoute à celles qu'un profil peut ouvrir.
alter table public.rh_profils
  add column if not exists statistiques text[] not null default '{}';
alter table public.rh_profils drop constraint if exists rh_profils_statistiques_check;
alter table public.rh_profils add constraint rh_profils_statistiques_check
  check (statistiques <@ array['commandes', 'livraisons', 'sav', 'suivi']::text[]);

-- (3.70.0) Lues par les fonctions plus bas (déjà là sur une base en service).
create table if not exists public.refus_courses (
  id          bigserial primary key,
  commande_id text not null references public.commandes(id) on delete cascade,
  boutique_id text not null references public.boutiques(id) on delete cascade,
  livreur_id  uuid references public.profils(id) on delete set null,
  motif       text not null default '',
  refuse_le   timestamptz not null default now()
);
create index if not exists refus_courses_commande on public.refus_courses(commande_id, refuse_le desc);
alter table public.refus_courses enable row level security;
revoke all on public.refus_courses from anon, authenticated;
revoke all on sequence public.refus_courses_id_seq from anon, authenticated;

-- Qui est connecté : recopié de personnel.sql, pour que ce fichier se suffise.
create or replace function public.rh_moi() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_est_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and (administration or ceo));
$$;

create or replace function public.rh_mon_profil() returns uuid
language sql stable security definer set search_path = public as $$
  select profil_id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_menu_ouvert(cle text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_moi uuid := public.rh_moi();
  v_profil uuid := public.rh_mon_profil();
begin
  if public.rh_est_admin() then
    return true;
  end if;
  if v_moi is null then
    return false;
  end if;
  if to_regclass('public.rh_acces_menus') is null then
    return cle in ('mails', 'discussions', 'missions', 'rapports');
  end if;
  if v_profil is null and not exists (select 1 from public.rh_profils p where p.responsable_id = v_moi) then
    return cle in ('mails', 'discussions', 'depenses');
  end if;
  return exists (
    select 1 from public.rh_acces_menus a
      join public.rh_profils p on p.id = a.profil_id
     where a.menu = cle
       and (p.responsable_id = v_moi or (a.qui = 'membres' and p.id = v_profil)));
end $$;

/** Le droit au suivi : « admin » (montants compris), « responsable »
    (sans montant : un profil à qui le menu Paramètres l'ouvre), ou rien. */
create or replace function public.rh_suivi_acces() returns text
language sql stable security definer set search_path = public as $$
  select case
    when public.rh_est_admin() then 'admin'
    when public.rh_menu_ouvert('suivi') then 'responsable'
  end;
$$;

-- ---------- Le journal des étapes ----------
create table if not exists public.rh_journal_lignes (
  id           bigint generated always as identity primary key,
  commande_id  text not null,
  ligne_id     text,
  boutique_id  text,
  -- « etat » (valeur : le nouvel état), « livreur » (valeur : son id),
  -- « course_acceptee », « confirmee » (le client), « payee »,
  -- « commande » (valeur : le nouvel état de la commande).
  quoi         text not null,
  valeur       text not null default '',
  le           timestamptz not null default now(),
  -- Reconstitué depuis les dates que la base avait déjà : sans l'heure
  -- des étapes intermédiaires.
  reconstitue  boolean not null default false
);
create index if not exists rh_journal_lignes_commande on public.rh_journal_lignes (commande_id, le);

-- Les colonnes que le journal lit, posées comme le fait schema.sql.
alter table public.commande_lignes add column if not exists confirme_le timestamptz;
alter table public.commande_lignes add column if not exists livreur_id uuid;
alter table public.commande_lignes add column if not exists recu_le timestamptz;

/* JAMAIS D'ERREUR VERS LA COMMANDE : tout est dans un bloc qui avale
   ses propres échecs. Un journal manqué se regrette ; une commande
   bloquée par un journal, jamais. */
create or replace function public.rh_journaliser_ligne() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    if tg_op = 'INSERT' then
      insert into public.rh_journal_lignes (commande_id, ligne_id, boutique_id, quoi, valeur)
      values (new.commande_id, new.id, new.boutique_id, 'etat', coalesce(new.etat, ''));
      return null;
    end if;
    if new.etat is distinct from old.etat then
      insert into public.rh_journal_lignes (commande_id, ligne_id, boutique_id, quoi, valeur)
      values (new.commande_id, new.id, new.boutique_id, 'etat', coalesce(new.etat, ''));
    end if;
    if new.livreur_id is distinct from old.livreur_id then
      insert into public.rh_journal_lignes (commande_id, ligne_id, boutique_id, quoi, valeur)
      values (new.commande_id, new.id, new.boutique_id, 'livreur', coalesce(new.livreur_id::text, ''));
    end if;
    if new.recu_le is not null and old.recu_le is null then
      insert into public.rh_journal_lignes (commande_id, ligne_id, boutique_id, quoi, le)
      values (new.commande_id, new.id, new.boutique_id, 'course_acceptee', new.recu_le);
    end if;
    if new.confirme_le is not null and old.confirme_le is null then
      insert into public.rh_journal_lignes (commande_id, ligne_id, boutique_id, quoi, le)
      values (new.commande_id, new.id, new.boutique_id, 'confirmee', new.confirme_le);
    end if;
  exception when others then
    null;
  end;
  return null;
end $$;

drop trigger if exists rh_journal_lignes on public.commande_lignes;
create trigger rh_journal_lignes
  after insert or update on public.commande_lignes
  for each row execute function public.rh_journaliser_ligne();

create or replace function public.rh_journaliser_commande() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    if new.etat is distinct from old.etat then
      insert into public.rh_journal_lignes (commande_id, quoi, valeur, le)
      values (new.id, 'commande', coalesce(new.etat, ''),
              case when new.etat = 'payee' then coalesce(new.paye_le, now()) else now() end);
    end if;
  exception when others then
    null;
  end;
  return null;
end $$;

drop trigger if exists rh_journal_commandes on public.commandes;
create trigger rh_journal_commandes
  after update on public.commandes
  for each row execute function public.rh_journaliser_commande();

-- Les commandes d'avant le journal : ce que la base avait daté.
insert into public.rh_journal_lignes (commande_id, ligne_id, boutique_id, quoi, valeur, le, reconstitue)
select l.commande_id, l.id, l.boutique_id, 'etat', 'nouvelle', l.cree_le, true
  from public.commande_lignes l
 where not exists (select 1 from public.rh_journal_lignes j where j.ligne_id = l.id);
insert into public.rh_journal_lignes (commande_id, ligne_id, boutique_id, quoi, le, reconstitue)
select l.commande_id, l.id, l.boutique_id, 'course_acceptee', l.recu_le, true
  from public.commande_lignes l
 where l.recu_le is not null
   and not exists (select 1 from public.rh_journal_lignes j where j.ligne_id = l.id and j.quoi = 'course_acceptee');
insert into public.rh_journal_lignes (commande_id, ligne_id, boutique_id, quoi, le, reconstitue)
select l.commande_id, l.id, l.boutique_id, 'confirmee', l.confirme_le, true
  from public.commande_lignes l
 where l.confirme_le is not null
   and not exists (select 1 from public.rh_journal_lignes j where j.ligne_id = l.id and j.quoi = 'confirmee');
insert into public.rh_journal_lignes (commande_id, quoi, valeur, le, reconstitue)
select c.id, 'commande', 'payee', c.paye_le, true
  from public.commandes c
 where c.paye_le is not null
   and not exists (select 1 from public.rh_journal_lignes j
                    where j.commande_id = c.id and j.quoi = 'commande' and j.valeur = 'payee');

-- ---------- Ce que l'administration note ----------
-- Les étapes que le terrain ne saisit pas encore, article par article.
create table if not exists public.rh_suivi_lignes (
  ligne_id     text primary key,
  commande_id  text not null,
  statut       text not null check (statut in ('recupere', 'echouee', 'retour_en_cours', 'retournee')),
  motif        text not null default '',
  maj_par      uuid,
  maj_le       timestamptz not null default now()
);
create index if not exists rh_suivi_lignes_commande on public.rh_suivi_lignes (commande_id);

create table if not exists public.rh_suivi_commandes (
  commande_id   text primary key,
  zone          text not null default '',
  observations  text not null default '',
  cloturee_le   timestamptz,
  cloturee_par  uuid,
  maj_par       uuid,
  maj_le        timestamptz not null default now()
);

create table if not exists public.rh_incidents (
  id           bigint generated always as identity primary key,
  commande_id  text not null,
  boutique_id  text,
  livreur_id   uuid,
  type         text not null check (type in ('retard', 'colis_abime', 'colis_perdu', 'client_absent',
                                             'adresse', 'paiement', 'erreur_article', 'autre')),
  description  text not null default '',
  cree_par     uuid,
  cree_le      timestamptz not null default now(),
  resolu_le    timestamptz,
  resolu_par   uuid,
  resolution   text not null default ''
);
create index if not exists rh_incidents_commande on public.rh_incidents (commande_id);

-- Les seuils des retards, en heures. Des valeurs de départ, à régler.
create table if not exists public.rh_reglages_suivi (
  id              boolean primary key default true check (id),
  vue_h           int not null default 2 check (vue_h between 1 and 720),
  preparation_h   int not null default 24 check (preparation_h between 1 and 720),
  livraison_h     int not null default 48 check (livraison_h between 1 and 720),
  confirmation_h  int not null default 24 check (confirmation_h between 1 and 720)
);
insert into public.rh_reglages_suivi (id) values (true) on conflict (id) do nothing;

-- ---------- Les zones ----------
-- Communes (toutes) et quartiers ou arrondissements connus du
-- référentiel du découpage du Bénin. La liste des quartiers est
-- partielle : l'administration corrige la zone d'une commande, et peut
-- ajouter un nom (« ajout »).
create table if not exists public.rh_zones (
  id           bigint generated always as identity primary key,
  nom          text not null,
  type         text not null check (type in ('commune', 'arrondissement', 'quartier', 'village', 'ajout')),
  commune      text not null default '',
  departement  text not null default ''
);
create unique index if not exists rh_zones_unique on public.rh_zones (nom, type, commune);

/** Un nom sans accents ni ponctuation, en minuscules : « Fidjrossè » = « fidjrosse ». */
create or replace function public.rh_cle(t text) returns text
language sql immutable set search_path = public as $$
  select btrim(regexp_replace(
           translate(lower(coalesce(t, '')),
                     'àâäáãéèêëíìîïóòôöõúùûüçñ''’-_/.,;:()',
                     'aaaaaeeeeiiiiooooouuuucn            '),
           '\s+', ' ', 'g'));
$$;

insert into public.rh_zones (nom, type, commune, departement) values
  ('Banikoara', 'commune', 'Banikoara', 'Alibori'),
  ('Gogounou', 'commune', 'Gogounou', 'Alibori'),
  ('Kandi', 'commune', 'Kandi', 'Alibori'),
  ('Karimama', 'commune', 'Karimama', 'Alibori'),
  ('Malanville', 'commune', 'Malanville', 'Alibori'),
  ('Ségbana', 'commune', 'Ségbana', 'Alibori'),
  ('Boukoumbé', 'commune', 'Boukoumbé', 'Atacora'),
  ('Cobly', 'commune', 'Cobly', 'Atacora'),
  ('Kérou', 'commune', 'Kérou', 'Atacora'),
  ('Kouandé', 'commune', 'Kouandé', 'Atacora'),
  ('Matéri', 'commune', 'Matéri', 'Atacora'),
  ('Natitingou', 'commune', 'Natitingou', 'Atacora'),
  ('Péhunco', 'commune', 'Péhunco', 'Atacora'),
  ('Tanguiéta', 'commune', 'Tanguiéta', 'Atacora'),
  ('Toucountouna', 'commune', 'Toucountouna', 'Atacora'),
  ('Abomey-Calavi', 'commune', 'Abomey-Calavi', 'Atlantique'),
  ('Allada', 'commune', 'Allada', 'Atlantique'),
  ('Kpomassè', 'commune', 'Kpomassè', 'Atlantique'),
  ('Ouidah', 'commune', 'Ouidah', 'Atlantique'),
  ('Sô-Ava', 'commune', 'Sô-Ava', 'Atlantique'),
  ('Toffo', 'commune', 'Toffo', 'Atlantique'),
  ('Tori-Bossito', 'commune', 'Tori-Bossito', 'Atlantique'),
  ('Zè', 'commune', 'Zè', 'Atlantique'),
  ('Bembèrèkè', 'commune', 'Bembèrèkè', 'Borgou'),
  ('Kalalé', 'commune', 'Kalalé', 'Borgou'),
  ('N''Dali', 'commune', 'N''Dali', 'Borgou'),
  ('Nikki', 'commune', 'Nikki', 'Borgou'),
  ('Parakou', 'commune', 'Parakou', 'Borgou'),
  ('Pèrèrè', 'commune', 'Pèrèrè', 'Borgou'),
  ('Sinendé', 'commune', 'Sinendé', 'Borgou'),
  ('Tchaourou', 'commune', 'Tchaourou', 'Borgou'),
  ('Bantè', 'commune', 'Bantè', 'Collines'),
  ('Dassa-Zoumè', 'commune', 'Dassa-Zoumè', 'Collines'),
  ('Glazoué', 'commune', 'Glazoué', 'Collines'),
  ('Ouèssè', 'commune', 'Ouèssè', 'Collines'),
  ('Savalou', 'commune', 'Savalou', 'Collines'),
  ('Savè', 'commune', 'Savè', 'Collines'),
  ('Aplahoué', 'commune', 'Aplahoué', 'Couffo'),
  ('Djakotomey', 'commune', 'Djakotomey', 'Couffo'),
  ('Dogbo', 'commune', 'Dogbo', 'Couffo'),
  ('Klouékanmè', 'commune', 'Klouékanmè', 'Couffo'),
  ('Lalo', 'commune', 'Lalo', 'Couffo'),
  ('Toviklin', 'commune', 'Toviklin', 'Couffo'),
  ('Bassila', 'commune', 'Bassila', 'Donga'),
  ('Copargo', 'commune', 'Copargo', 'Donga'),
  ('Djougou', 'commune', 'Djougou', 'Donga'),
  ('Ouaké', 'commune', 'Ouaké', 'Donga'),
  ('Cotonou', 'commune', 'Cotonou', 'Littoral'),
  ('Athiémé', 'commune', 'Athiémé', 'Mono'),
  ('Bopa', 'commune', 'Bopa', 'Mono'),
  ('Comè', 'commune', 'Comè', 'Mono'),
  ('Grand-Popo', 'commune', 'Grand-Popo', 'Mono'),
  ('Houéyogbé', 'commune', 'Houéyogbé', 'Mono'),
  ('Lokossa', 'commune', 'Lokossa', 'Mono'),
  ('Adjarra', 'commune', 'Adjarra', 'Ouémé'),
  ('Adjohoun', 'commune', 'Adjohoun', 'Ouémé'),
  ('Aguégués', 'commune', 'Aguégués', 'Ouémé'),
  ('Akpro-Missérété', 'commune', 'Akpro-Missérété', 'Ouémé'),
  ('Avrankou', 'commune', 'Avrankou', 'Ouémé'),
  ('Bonou', 'commune', 'Bonou', 'Ouémé'),
  ('Dangbo', 'commune', 'Dangbo', 'Ouémé'),
  ('Porto-Novo', 'commune', 'Porto-Novo', 'Ouémé'),
  ('Sèmè-Kpodji', 'commune', 'Sèmè-Kpodji', 'Ouémé'),
  ('Adja-Ouèrè', 'commune', 'Adja-Ouèrè', 'Plateau'),
  ('Ifangni', 'commune', 'Ifangni', 'Plateau'),
  ('Kétou', 'commune', 'Kétou', 'Plateau'),
  ('Pobè', 'commune', 'Pobè', 'Plateau'),
  ('Sakété', 'commune', 'Sakété', 'Plateau'),
  ('Abomey', 'commune', 'Abomey', 'Zou'),
  ('Agbangnizoun', 'commune', 'Agbangnizoun', 'Zou'),
  ('Bohicon', 'commune', 'Bohicon', 'Zou'),
  ('Covè', 'commune', 'Covè', 'Zou'),
  ('Djidja', 'commune', 'Djidja', 'Zou'),
  ('Ouinhi', 'commune', 'Ouinhi', 'Zou'),
  ('Za-Kpota', 'commune', 'Za-Kpota', 'Zou'),
  ('Zagnanado', 'commune', 'Zagnanado', 'Zou'),
  ('Zogbodomey', 'commune', 'Zogbodomey', 'Zou'),
  ('Kotopounga', 'arrondissement', 'Natitingou', 'Atacora'),
  ('Kouandata', 'arrondissement', 'Natitingou', 'Atacora'),
  ('Natitingou Centre', 'arrondissement', 'Natitingou', 'Atacora'),
  ('Perma', 'arrondissement', 'Natitingou', 'Atacora'),
  ('Péporiyakou', 'arrondissement', 'Natitingou', 'Atacora'),
  ('Tchoumi-Tchoumi', 'arrondissement', 'Natitingou', 'Atacora'),
  ('Angaradébou', 'arrondissement', 'Kandi', 'Alibori'),
  ('Bensékou', 'arrondissement', 'Kandi', 'Alibori'),
  ('Donwari', 'arrondissement', 'Kandi', 'Alibori'),
  ('Kandi Centre', 'arrondissement', 'Kandi', 'Alibori'),
  ('Kassakou', 'arrondissement', 'Kandi', 'Alibori'),
  ('Saah', 'arrondissement', 'Kandi', 'Alibori'),
  ('Sam', 'arrondissement', 'Kandi', 'Alibori'),
  ('Abomey-Calavi Centre', 'arrondissement', 'Abomey-Calavi', 'Atlantique'),
  ('Adjagbo', 'quartier', 'Abomey-Calavi', 'Atlantique'),
  ('Akassato', 'arrondissement', 'Abomey-Calavi', 'Atlantique'),
  ('Arconville', 'quartier', 'Abomey-Calavi', 'Atlantique'),
  ('Aïtchédji', 'quartier', 'Abomey-Calavi', 'Atlantique'),
  ('Cococodji', 'quartier', 'Abomey-Calavi', 'Atlantique'),
  ('Cocotomey', 'quartier', 'Abomey-Calavi', 'Atlantique'),
  ('Glo-Djigbé', 'arrondissement', 'Abomey-Calavi', 'Atlantique'),
  ('Godomey', 'arrondissement', 'Abomey-Calavi', 'Atlantique'),
  ('Hêvié', 'arrondissement', 'Abomey-Calavi', 'Atlantique'),
  ('Kpanroun', 'arrondissement', 'Abomey-Calavi', 'Atlantique'),
  ('Missessinto', 'quartier', 'Abomey-Calavi', 'Atlantique'),
  ('Ouèdo', 'arrondissement', 'Abomey-Calavi', 'Atlantique'),
  ('Tankpè', 'quartier', 'Abomey-Calavi', 'Atlantique'),
  ('Togba', 'arrondissement', 'Abomey-Calavi', 'Atlantique'),
  ('Womey', 'quartier', 'Abomey-Calavi', 'Atlantique'),
  ('Zinvié', 'arrondissement', 'Abomey-Calavi', 'Atlantique'),
  ('Zogbadjè', 'quartier', 'Abomey-Calavi', 'Atlantique'),
  ('Avlékété', 'arrondissement', 'Ouidah', 'Atlantique'),
  ('Djègbadji', 'arrondissement', 'Ouidah', 'Atlantique'),
  ('Gakpé', 'arrondissement', 'Ouidah', 'Atlantique'),
  ('Houakpè-Daho', 'arrondissement', 'Ouidah', 'Atlantique'),
  ('Ouidah Centre', 'arrondissement', 'Ouidah', 'Atlantique'),
  ('Pahou', 'arrondissement', 'Ouidah', 'Atlantique'),
  ('Savi', 'arrondissement', 'Ouidah', 'Atlantique'),
  ('Albarika', 'quartier', 'Parakou', 'Borgou'),
  ('Amawignon', 'quartier', 'Parakou', 'Borgou'),
  ('Baka', 'quartier', 'Parakou', 'Borgou'),
  ('Banikanni', 'quartier', 'Parakou', 'Borgou'),
  ('Camp Adagbè', 'quartier', 'Parakou', 'Borgou'),
  ('Dépôt', 'quartier', 'Parakou', 'Borgou'),
  ('Guéma', 'quartier', 'Parakou', 'Borgou'),
  ('Kpébié', 'quartier', 'Parakou', 'Borgou'),
  ('Ladji Farani', 'quartier', 'Parakou', 'Borgou'),
  ('Madina', 'quartier', 'Parakou', 'Borgou'),
  ('Okédama', 'quartier', 'Parakou', 'Borgou'),
  ('Titirou', 'quartier', 'Parakou', 'Borgou'),
  ('Tourou', 'quartier', 'Parakou', 'Borgou'),
  ('Wansirou', 'quartier', 'Parakou', 'Borgou'),
  ('Zongo', 'quartier', 'Parakou', 'Borgou'),
  ('Bariénou', 'arrondissement', 'Djougou', 'Donga'),
  ('Bougou', 'arrondissement', 'Djougou', 'Donga'),
  ('Bèlèfoungou', 'arrondissement', 'Djougou', 'Donga'),
  ('Djougou Centre', 'arrondissement', 'Djougou', 'Donga'),
  ('Kolokondé', 'arrondissement', 'Djougou', 'Donga'),
  ('Onklou', 'arrondissement', 'Djougou', 'Donga'),
  ('Partago', 'arrondissement', 'Djougou', 'Donga'),
  ('Pélébina', 'arrondissement', 'Djougou', 'Donga'),
  ('Sérou', 'arrondissement', 'Djougou', 'Donga'),
  ('Agla', 'quartier', 'Cotonou', 'Littoral'),
  ('Akogbato', 'quartier', 'Cotonou', 'Littoral'),
  ('Akpakpa', 'quartier', 'Cotonou', 'Littoral'),
  ('Avotrou', 'quartier', 'Cotonou', 'Littoral'),
  ('Ayélawadjè', 'quartier', 'Cotonou', 'Littoral'),
  ('Aïbatin', 'quartier', 'Cotonou', 'Littoral'),
  ('Aïdjèdo', 'quartier', 'Cotonou', 'Littoral'),
  ('Cadjèhoun', 'quartier', 'Cotonou', 'Littoral'),
  ('Cocotiers', 'quartier', 'Cotonou', 'Littoral'),
  ('Dandji', 'quartier', 'Cotonou', 'Littoral'),
  ('Dantokpa', 'quartier', 'Cotonou', 'Littoral'),
  ('Djidjè', 'quartier', 'Cotonou', 'Littoral'),
  ('Enagnon', 'quartier', 'Cotonou', 'Littoral'),
  ('Fidjrossè', 'quartier', 'Cotonou', 'Littoral'),
  ('Fifadji', 'quartier', 'Cotonou', 'Littoral'),
  ('Ganhi', 'quartier', 'Cotonou', 'Littoral'),
  ('Gbédjromèdé', 'quartier', 'Cotonou', 'Littoral'),
  ('Gbégamey', 'quartier', 'Cotonou', 'Littoral'),
  ('Guinkomey', 'quartier', 'Cotonou', 'Littoral'),
  ('Haie Vive', 'quartier', 'Cotonou', 'Littoral'),
  ('Houéyiho', 'quartier', 'Cotonou', 'Littoral'),
  ('Jonquet', 'quartier', 'Cotonou', 'Littoral'),
  ('Jéricho', 'quartier', 'Cotonou', 'Littoral'),
  ('Kouhounou', 'quartier', 'Cotonou', 'Littoral'),
  ('Ladji', 'quartier', 'Cotonou', 'Littoral'),
  ('Midombo', 'quartier', 'Cotonou', 'Littoral'),
  ('Missèbo', 'quartier', 'Cotonou', 'Littoral'),
  ('Mènontin', 'quartier', 'Cotonou', 'Littoral'),
  ('Placodji', 'quartier', 'Cotonou', 'Littoral'),
  ('Saint-Jean', 'quartier', 'Cotonou', 'Littoral'),
  ('Saint-Michel', 'quartier', 'Cotonou', 'Littoral'),
  ('Sainte-Rita', 'quartier', 'Cotonou', 'Littoral'),
  ('Scoa Gbéto', 'quartier', 'Cotonou', 'Littoral'),
  ('Sikècodji', 'quartier', 'Cotonou', 'Littoral'),
  ('Sodjèatimè', 'quartier', 'Cotonou', 'Littoral'),
  ('Sègbèya', 'quartier', 'Cotonou', 'Littoral'),
  ('Tokpa', 'quartier', 'Cotonou', 'Littoral'),
  ('Vodjè', 'quartier', 'Cotonou', 'Littoral'),
  ('Vossa', 'quartier', 'Cotonou', 'Littoral'),
  ('Vèdoko', 'quartier', 'Cotonou', 'Littoral'),
  ('Xwlacodji', 'quartier', 'Cotonou', 'Littoral'),
  ('Zogbo', 'quartier', 'Cotonou', 'Littoral'),
  ('Zongo', 'quartier', 'Cotonou', 'Littoral'),
  ('Agatogbo', 'arrondissement', 'Comè', 'Mono'),
  ('Akodéha', 'arrondissement', 'Comè', 'Mono'),
  ('Comè Centre', 'arrondissement', 'Comè', 'Mono'),
  ('Oumako', 'arrondissement', 'Comè', 'Mono'),
  ('Ouèdèmè-Pédah', 'arrondissement', 'Comè', 'Mono'),
  ('Agamè', 'arrondissement', 'Lokossa', 'Mono'),
  ('Houin', 'arrondissement', 'Lokossa', 'Mono'),
  ('Koudo', 'arrondissement', 'Lokossa', 'Mono'),
  ('Lokossa Centre', 'arrondissement', 'Lokossa', 'Mono'),
  ('Adjina', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Agbokou', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Attaké', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Djassin', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Djègan-Daho', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Dowa', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Foun-Foun', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Gbokou', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Houinmè', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Kandévié', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Lokpodji', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Louho', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Ouando', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Tokpota', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Zèbou', 'quartier', 'Porto-Novo', 'Ouémé'),
  ('Agblangandan', 'arrondissement', 'Sèmè-Kpodji', 'Ouémé'),
  ('Aholouyèmè', 'arrondissement', 'Sèmè-Kpodji', 'Ouémé'),
  ('Djèffa', 'quartier', 'Sèmè-Kpodji', 'Ouémé'),
  ('Djèrègbé', 'arrondissement', 'Sèmè-Kpodji', 'Ouémé'),
  ('Ekpè', 'arrondissement', 'Sèmè-Kpodji', 'Ouémé'),
  ('Sèmè-Podji Centre', 'arrondissement', 'Sèmè-Kpodji', 'Ouémé'),
  ('Tohouè', 'arrondissement', 'Sèmè-Kpodji', 'Ouémé'),
  ('Agbokpa', 'arrondissement', 'Abomey', 'Zou'),
  ('Djègbé', 'arrondissement', 'Abomey', 'Zou'),
  ('Détohou', 'arrondissement', 'Abomey', 'Zou'),
  ('Hounli', 'arrondissement', 'Abomey', 'Zou'),
  ('Sèhoun', 'arrondissement', 'Abomey', 'Zou'),
  ('Vidolé', 'arrondissement', 'Abomey', 'Zou'),
  ('Zounzonmè', 'arrondissement', 'Abomey', 'Zou'),
  ('Agongointo', 'arrondissement', 'Bohicon', 'Zou'),
  ('Avogbanna', 'arrondissement', 'Bohicon', 'Zou'),
  ('Bohicon Centre', 'arrondissement', 'Bohicon', 'Zou'),
  ('Gnidjazoun', 'arrondissement', 'Bohicon', 'Zou'),
  ('Lissèzoun', 'arrondissement', 'Bohicon', 'Zou'),
  ('Ouassaho', 'arrondissement', 'Bohicon', 'Zou'),
  ('Passagon', 'arrondissement', 'Bohicon', 'Zou'),
  ('Saclo', 'arrondissement', 'Bohicon', 'Zou'),
  ('Sodohomè', 'arrondissement', 'Bohicon', 'Zou')
on conflict (nom, type, commune) do nothing;

/** La zone lue dans une adresse : le quartier si on le reconnaît, sinon la commune. */
create or replace function public.rh_zone_de(adresse text) returns text
language sql stable security definer set search_path = public as $$
  select z.nom || case when z.type <> 'commune' and z.commune <> '' and z.commune <> z.nom
                       then ' (' || z.commune || ')' else '' end
    from public.rh_zones z
   where length(public.rh_cle(z.nom)) >= 3
     and position(' ' || public.rh_cle(z.nom) || ' ' in ' ' || public.rh_cle(adresse) || ' ') > 0
   order by case z.type when 'ajout' then 0 when 'quartier' then 1 when 'village' then 1
                        when 'arrondissement' then 2 else 3 end,
            length(z.nom) desc
   limit 1;
$$;

-- ---------- Le statut ----------
/* L'ordre et les noms du document de BIZZOO. Les incidents ne
   remplacent jamais le statut : ils sont des alertes, à côté. */
create or replace function public.rh_statut_libelle(rang int) returns text
language sql immutable set search_path = public as $$
  select case rang
    when 0 then 'En attente de paiement'
    when 1 then 'Nouvelle commande'
    when 2 then 'Confirmée'
    when 3 then 'Commande préparée'
    when 4 then 'Colis récupéré'
    when 5 then 'En cours de livraison'
    when 6 then 'Livraison effectuée — confirmation en attente'
    when 8 then 'Livré et confirmé'
    when 9 then 'Livraison échouée'
    when 10 then 'Livraison contestée'
    when 11 then 'Annulée'
    when 12 then 'Retour en cours'
    when 13 then 'Retournée au marchand'
    when 14 then 'Clôturée'
    when 15 then 'Paiement échoué'
    else '' end;
$$;

/** Le rang d'un article, de ce que la base et l'administration en savent. */
create or replace function public.rh_statut_ligne(etat text, confirme timestamptz, terrain text, contestee boolean)
returns int
language sql immutable set search_path = public as $$
  select case
    when etat = 'annulee' then 11
    when terrain = 'retournee' then 13
    when terrain = 'retour_en_cours' then 12
    when terrain = 'echouee' then 9
    when contestee then 10
    when confirme is not null then 8
    when etat = 'remise' then 6
    when etat = 'en_livraison' then 5
    when terrain = 'recupere' then 4
    when etat = 'preparee' then 3
    when etat = 'vue' then 2
    else 1 end;
$$;

-- (3.72.0) Le délai de préparation en minutes, que la fonction lit.
alter table public.rh_reglages_suivi add column if not exists preparation_min int
  check (preparation_min is null or preparation_min between 5 and 10080);

/**
 * Le suivi d'une liste de commandes : une ligne JSON par commande,
 * articles et marchands compris, alertes calculées. Interne : les
 * fonctions publiques vérifient d'abord qui appelle et ôtent les
 * montants à qui n'y a pas droit.
 */
create or replace function public.rh_suivi_donnees(t1 timestamptz, t2 timestamptz, une text default null)
returns setof jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r public.rh_reglages_suivi;
  maintenant timestamptz := now();
  -- Les seuils de la veille et des encaissements (personnel-controles.sql)
  -- se lisent par to_jsonb : sur une base où leurs colonnes manquent
  -- encore, la valeur de départ vaut, au lieu d'une erreur.
  v_prise_min int;
  v_position_min int;
  v_momopay_h int;
begin
  select * into r from public.rh_reglages_suivi where id;
  v_prise_min := coalesce((to_jsonb(r) ->> 'prise_course_min')::int, 30);
  v_position_min := coalesce((to_jsonb(r) ->> 'position_min')::int, 15);
  v_momopay_h := coalesce((to_jsonb(r) ->> 'momopay_h')::int, 48);
  return query
  with cmd as (
    select c.* from public.commandes c
     where (une is not null and c.id = une)
        or (une is null and c.cree_le >= t1 and c.cree_le < t2)
     order by c.cree_le desc
     limit 2000
  ),
  lig as (
    select l.*, b.nom as boutique_nom, coalesce(nullif(b.tel, ''), '') as boutique_tel,
           coalesce(nullif(pl.nom, ''), pl.email) as livreur_nom, coalesce(pl.tel, '') as livreur_tel,
           s.statut as terrain, s.motif as terrain_motif,
           exists (select 1 from public.reclamations rc
                    where rc.commande_id = l.commande_id and rc.sujet = 'non_recu'
                      and (rc.boutique_id is null or rc.boutique_id = l.boutique_id)
                      and rc.etat not in ('resolue', 'tranchee')) as contestee,
           (select min(j.le) from public.rh_journal_lignes j
             where j.ligne_id = l.id and j.quoi = 'etat' and j.valeur = 'vue') as vue_le,
           (select min(j.le) from public.rh_journal_lignes j
             where j.ligne_id = l.id and j.quoi = 'etat' and j.valeur = 'preparee') as preparee_le,
           (select min(j.le) from public.rh_journal_lignes j
             where j.ligne_id = l.id and j.quoi = 'etat' and j.valeur = 'remise') as remise_le
      from public.commande_lignes l
      join cmd c on c.id = l.commande_id
      left join public.boutiques b on b.id = l.boutique_id
      left join public.profils pl on pl.id = l.livreur_id
      left join public.rh_suivi_lignes s on s.ligne_id = l.id
  ),
  lig2 as (
    select x.*, public.rh_statut_ligne(x.etat, x.confirme_le, x.terrain, x.contestee) as rang
      from lig x
  )
  select jsonb_build_object(
    'id', c.id, 'numero', c.numero, 'cree_le', c.cree_le, 'paye_le', c.paye_le, 'etat', c.etat,
    -- (3.68.0) D'où vient la commande : passée dans l'application, ou prise
    -- sur WhatsApp et saisie par l'équipe (« Faire livrer »). Lue par
    -- « to_jsonb » : une base sans la colonne répond « Depuis APP ».
    'source', case when to_jsonb(c) ->> 'origine' = 'whatsapp' then 'Par whatsapp' else 'Depuis APP' end,
    'client', jsonb_build_object('nom', c.client_nom,
                                 'tel', btrim(case when coalesce(c.client_indicatif, '') <> '' and c.client_indicatif <> '229'
                                                   then '+' || c.client_indicatif || ' ' else '' end || coalesce(c.client_tel, '')),
                                 'adresse', c.client_adresse,
                                 'zone', coalesce(nullif(sc.zone, ''), public.rh_zone_de(c.client_adresse), ''),
                                 'zone_corrigee', coalesce(sc.zone, '') <> ''),
    'lignes', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', x.id, 'boutique_id', x.boutique_id, 'boutique', coalesce(x.boutique_nom, x.boutique_id),
                 'boutique_tel', x.boutique_tel, 'nom', x.nom, 'code', x.code, 'quantite', x.quantite,
                 'prix', x.prix, 'etat', x.etat, 'rang', x.rang, 'statut', public.rh_statut_libelle(x.rang),
                 'terrain', x.terrain, 'terrain_motif', coalesce(x.terrain_motif, ''),
                 'livreur', x.livreur_nom, 'livreur_tel', x.livreur_tel, 'livreur_id', x.livreur_id,
                 'confirme_le', x.confirme_le, 'vue_le', x.vue_le, 'remise_le', x.remise_le)
               order by x.boutique_nom, x.nom) from lig2 x where x.commande_id = c.id), '[]'),
    'articles', coalesce((select string_agg(x.quantite || ' × ' || x.nom
                                            || case when x.etat = 'annulee' then ' (annulé)' else '' end, ' ; '
                                            order by x.boutique_nom, x.nom)
                            from lig2 x where x.commande_id = c.id), ''),
    'marchands', coalesce((select string_agg(distinct coalesce(x.boutique_nom, x.boutique_id)
                                             || case when x.boutique_tel <> '' then ' / ' || x.boutique_tel else '' end, ' ; ')
                             from lig2 x where x.commande_id = c.id), ''),
    'livreurs', coalesce((select string_agg(distinct x.livreur_nom
                                            || case when x.livreur_tel <> '' then ' / ' || x.livreur_tel else '' end, ' ; ')
                            from lig2 x where x.commande_id = c.id and x.livreur_nom is not null), ''),
    'frais', coalesce(c.frais_livraison, 0), 'total', c.total,
    'reste', case when c.etat = 'payee' then
               coalesce((select sum(greatest(0, rr.a_encaisser - coalesce(e.montant, 0)))
                           from public.restes_par_boutique(c.id) rr
                           left join public.encaissements e on e.commande_id = c.id and e.boutique_id = rr.boutique_id), 0)
             else 0 end,
    'rang', st.rang, 'statut', public.rh_statut_libelle(st.rang),
    'confirmation', case
       when not exists (select 1 from lig2 x where x.commande_id = c.id and x.etat <> 'annulee') then '—'
       when not exists (select 1 from lig2 x where x.commande_id = c.id and x.etat <> 'annulee' and x.confirme_le is null) then 'Oui'
       when exists (select 1 from lig2 x where x.commande_id = c.id and x.confirme_le is not null) then 'Partielle'
       else 'Non' end,
    -- La durée du document : du « vu » du marchand au « je l'ai reçu » du client.
    'delai_h', (select round(max(extract(epoch from (x.confirme_le - x.vue_le)) / 3600)::numeric, 1)
                  from lig2 x where x.commande_id = c.id and x.confirme_le is not null and x.vue_le is not null),
    'observations', coalesce(sc.observations, ''),
    'incidents_ouverts', (select count(*) from public.rh_incidents i where i.commande_id = c.id and i.resolu_le is null),
    'cloturee_le', sc.cloturee_le,
    'alertes', case when c.etat <> 'payee' or sc.cloturee_le is not null then '[]'::jsonb else (
      select coalesce(jsonb_agg(a), '[]') from (
        select 'non_vue' as a where exists (select 1 from lig2 x where x.commande_id = c.id and x.etat = 'nouvelle')
                                 and maintenant - c.paye_le > make_interval(hours => r.vue_h)
        union all
        select 'retard_preparation' where exists (select 1 from lig2 x where x.commande_id = c.id and x.etat = 'vue'
                                 -- (3.72.0) En minutes quand il est réglé ainsi.
                                 and maintenant - coalesce(x.vue_le, c.paye_le)
                                     > make_interval(mins => coalesce(r.preparation_min, r.preparation_h * 60)))
        union all
        select 'retard_livraison' where exists (select 1 from lig2 x where x.commande_id = c.id and x.rang < 6)
                                 and maintenant - c.paye_le > make_interval(hours => r.livraison_h)
        union all
        select 'sans_confirmation' where exists (select 1 from lig2 x where x.commande_id = c.id and x.rang = 6
                                 and maintenant - coalesce(x.remise_le, c.paye_le) > make_interval(hours => r.confirmation_h))
        union all
        select 'contestee' where exists (select 1 from lig2 x where x.commande_id = c.id and x.contestee)
        union all
        select 'echec' where exists (select 1 from lig2 x where x.commande_id = c.id and x.rang in (9, 12))
        union all
        select 'incident' where exists (select 1 from public.rh_incidents i where i.commande_id = c.id and i.resolu_le is null)
        union all
        select 'refus_course' where exists (select 1 from public.refus_courses f where f.commande_id = c.id)
        union all
        select 'encaissement_conteste' where exists (select 1 from public.encaissements e
                                                     where e.commande_id = c.id and e.conteste_le is not null)
        union all
        -- Payée (ou préparée) et personne n'a pris la course : la demande
        -- part à tous les livreurs au paiement, elle devrait trouver preneur.
        select 'course_sans_livreur' where exists (select 1 from lig2 x where x.commande_id = c.id
                                 and x.etat in ('nouvelle', 'vue', 'preparee') and x.livreur_id is null
                                 and maintenant - coalesce(x.preparee_le, c.paye_le) > make_interval(mins => v_prise_min))
        union all
        -- En route, et son téléphone n'envoie plus rien : compté depuis sa
        -- dernière position, ou depuis qu'il a accepté la course.
        select 'livreur_muet' where exists (select 1 from lig2 x
                                 left join public.positions_livreurs pp on pp.profil_id = x.livreur_id
                                 where x.commande_id = c.id and x.etat = 'en_livraison' and x.livreur_id is not null
                                   and maintenant - greatest(pp.enregistre_le, x.recu_le, c.paye_le)
                                       > make_interval(mins => v_position_min))
        union all
        select 'momopay_non_verifie' where exists (select 1 from public.encaissements e
                                 where e.commande_id = c.id and e.mode = 'mobile_money' and e.remis_le is null
                                   and maintenant - e.encaisse_le > make_interval(hours => v_momopay_h))
        union all
        select 'encaissement_ecart' where exists (select 1 from public.encaissements e
                                 where e.commande_id = c.id and e.montant <> e.du)
      ) al)
    end)
  from cmd c
  left join public.rh_suivi_commandes sc on sc.commande_id = c.id
  cross join lateral (
    select case
      when sc.cloturee_le is not null then 14
      when c.etat = 'a_payer' then 0
      when c.etat = 'echouee' then 15
      when c.etat = 'annulee' then 11
      when not exists (select 1 from lig2 x where x.commande_id = c.id and x.rang <> 11) then 11
      when exists (select 1 from lig2 x where x.commande_id = c.id and x.rang = 10) then 10
      when exists (select 1 from lig2 x where x.commande_id = c.id and x.rang = 9) then 9
      when exists (select 1 from lig2 x where x.commande_id = c.id and x.rang = 12) then 12
      else (select min(x.rang) from lig2 x where x.commande_id = c.id and x.rang <> 11)
    end as rang) st
  order by c.cree_le desc;
end $$;

-- Le reste à encaisser par boutique : recopié de schema.sql, pour que ce fichier se suffise.
create or replace function public.restes_par_boutique(cible text)
returns table (boutique_id text, a_encaisser bigint)
language plpgsql stable security definer set search_path = public as $$
declare lp jsonb;
begin
  select c.parts into lp from public.commandes c where c.id = cible;
  -- UNE COMMANDE D'AVANT LES CONDITIONS PAR BOUTIQUE (« parts » vide) :
  -- l'ancienne règle, celle d'un acompte unique réparti au prorata.
  if lp is null then
    return query
  with commande as (
    select c.total::numeric as total,
           greatest(0, coalesce(c.frais_livraison, 0))::numeric as frais,
           coalesce(c.verse, c.acompte, c.total)::numeric as deja
      from public.commandes c
     where c.id = cible
  ), parts as (
    select l.boutique_id as boutique,
           sum(l.prix * l.quantite)::numeric as brut,
           coalesce(sum(l.prix * l.quantite) filter (where l.etat <> 'annulee'), 0)::numeric as servi
      from public.commande_lignes l
     where l.commande_id = cible
     group by l.boutique_id
  ), reste as (
    -- Ce que vaut ce qui sera livré, remise déduite au prorata, moins ce
    -- qui est déjà versé.
    -- LES FRAIS DE LIVRAISON ne se réduisent pas au prorata : tant qu'il
    -- reste quelque chose à livrer, la course a lieu et coûte son prix.
    -- Tout annulé, il n'y a pas de course, donc pas de frais.
    select greatest(0, coalesce(round((c.total - c.frais) * sum(p.servi) / nullif(sum(p.brut), 0)), 0)
                       + case when sum(p.servi) > 0 then c.frais else 0 end
                       - c.deja) as du,
           sum(p.servi) as servi
      from commande c, parts p
     group by c.total, c.frais, c.deja
  ), repartie as (
    select p.boutique,
           coalesce(floor(r.du * p.servi / nullif(r.servi, 0)), 0) as part,
           row_number() over (order by p.servi desc, p.boutique) as rang,
           r.du
      from parts p, reste r
  )
  select x.boutique,
         (x.part + case when x.rang = 1 then x.du - sum(x.part) over () else 0 end)::bigint
    from repartie x;
    return;
  end if;
  -- (3.59.0) CHAQUE BOUTIQUE ENCAISSE SA PART, moins SON acompte : ce
  -- que valent ses articles servis, remise déduite au prorata, plus ses
  -- frais tant qu'il y a quelque chose à livrer.
  --
  -- CE QUE LE CLIENT A VERSÉ N'EST JAMAIS PERDU POUR LUI. Chaque boutique
  -- déduit d'abord son propre acompte ; ce qui a été versé en plus — un
  -- surplus, ou l'acompte d'une part annulée — diminue les autres parts
  -- au prorata, l'arrondi à la plus grosse.
  return query
    with commande as (
      select greatest(0, coalesce(c.remise, 0))::numeric as remise,
             -- (3.64.0) Au kilomètre, les frais de livraison se paient en ligne
             -- avec l'acompte, hors des parts des boutiques : ce versement-là
             -- n'allège le reste d'aucune d'elles.
             greatest(0, coalesce(c.verse, c.acompte, c.total)
                         - case when c.livraison is not null
                                then coalesce(c.frais_livraison, 0) else 0 end)::numeric as paye
        from public.commandes c where c.id = cible
    ), lignes as (
      select l.boutique_id as bou,
             sum(l.prix * l.quantite)::numeric as brut,
             coalesce(sum(l.prix * l.quantite) filter (where l.etat <> 'annulee'), 0)::numeric as servi
        from public.commande_lignes l
       where l.commande_id = cible
       group by l.boutique_id
    ), tout as (
      select sum(x.brut) as s from lignes x
    ), brutes as (
      select x.bou,
             greatest(0, round(x.servi - k.remise * x.servi / nullif(t.s, 0))
                         + case when x.servi > 0 then coalesce((lp -> x.bou ->> 'frais')::numeric, 0) else 0 end) as du
        from lignes x, tout t, commande k
    ), propres as (
      select b.bou, b.du,
             least(b.du, coalesce((lp -> b.bou ->> 'acompte')::numeric, 0)) as sien
        from brutes b
    ), credit as (
      select greatest(0, k.paye - coalesce(sum(p.sien), 0)) as reste_credit,
             coalesce(sum(p.du - p.sien), 0) as a_couvrir
        from propres p, commande k
       group by k.paye
    ), allege as (
      select p.bou, p.du - p.sien as du,
             case when c.a_couvrir > 0
                  then floor(least(c.reste_credit, c.a_couvrir) * (p.du - p.sien) / c.a_couvrir)
                  else 0 end as moins,
             least(c.reste_credit, c.a_couvrir) as credit,
             row_number() over (order by p.du - p.sien desc, p.bou) as rang
        from propres p, credit c
    )
    select a.bou,
           greatest(0, a.du - a.moins
                       - case when a.rang = 1 then a.credit - sum(a.moins) over () else 0 end)::bigint
      from allege a;
end $$;
revoke all on function public.restes_par_boutique(text) from public, anon, authenticated;

/** Ôte les montants pour qui n'y a pas droit. */
create or replace function public.rh_suivi_sans_montants(d jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select (d - 'frais' - 'total' - 'reste')
         || jsonb_build_object('lignes', coalesce((select jsonb_agg(l - 'prix') from jsonb_array_elements(d -> 'lignes') l), '[]'));
$$;

/** Le tableau du suivi : les commandes passées sur une période (heure du Bénin). */
create or replace function public.rh_suivi(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  acces text := public.rh_suivi_acces();
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  fin date := coalesce(jusqu, aujourdhui);
  debut date := coalesce(depuis, coalesce(jusqu, aujourdhui) - 6);
  lignes jsonb;
begin
  if acces is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  if fin < debut then
    raise exception 'La fin de la période précède son début';
  end if;
  if fin - debut > 400 then
    raise exception 'Choisissez une période d''un an au plus';
  end if;
  select coalesce(jsonb_agg(case when acces = 'admin' then d else public.rh_suivi_sans_montants(d) end), '[]')
    into lignes
    from public.rh_suivi_donnees(debut::timestamp at time zone 'Africa/Porto-Novo',
                                 (fin + 1)::timestamp at time zone 'Africa/Porto-Novo') d;
  return jsonb_build_object(
    'periode', jsonb_build_object('depuis', debut, 'jusqu', fin),
    'montants', acces = 'admin',
    'reglages', (select to_jsonb(r) - 'id' from public.rh_reglages_suivi r where r.id),
    'commandes', lignes);
end $$;

/** Les alertes en cours, toutes périodes : le chiffre de la pastille. */
create or replace function public.rh_suivi_alertes_nb() returns int
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rh_suivi_acces() is null then
    return 0;
  end if;
  return (select count(*)::int
            from public.rh_suivi_donnees(now() - interval '60 days', now() + interval '1 day') d
           where jsonb_array_length(d -> 'alertes') > 0
             and (d -> 'alertes') <> '["refus_course"]'::jsonb);
end $$;

/** Une commande : le suivi, la chronologie, les incidents, les réclamations. */
create or replace function public.rh_suivi_commande(commande text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  acces text := public.rh_suivi_acces();
  d jsonb;
begin
  if acces is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  select x into d from public.rh_suivi_donnees(null, null, commande) x;
  if d is null then
    raise exception 'Commande introuvable';
  end if;
  if acces <> 'admin' then
    d := public.rh_suivi_sans_montants(d);
  end if;
  return d || jsonb_build_object(
    'montants', acces = 'admin',
    'journal', coalesce((select jsonb_agg(jsonb_build_object(
                  'le', j.le, 'quoi', j.quoi, 'valeur', j.valeur, 'boutique', coalesce(b.nom, j.boutique_id),
                  'article', l.nom, 'reconstitue', j.reconstitue,
                  'livreur', case when j.quoi = 'livreur' then coalesce(nullif(p.nom, ''), p.email) end)
                order by j.le, j.id)
                from public.rh_journal_lignes j
                left join public.commande_lignes l on l.id = j.ligne_id
                left join public.boutiques b on b.id = j.boutique_id
                left join public.profils p on j.quoi = 'livreur' and p.id::text = j.valeur
               where j.commande_id = commande), '[]'),
    'incidents', coalesce((select jsonb_agg(jsonb_build_object(
                  'id', i.id, 'type', i.type, 'description', i.description, 'cree_le', i.cree_le,
                  'boutique', coalesce(b.nom, i.boutique_id), 'livreur', coalesce(nullif(p.nom, ''), p.email),
                  'auteur', btrim(coalesce(ea.prenoms, '') || ' ' || coalesce(ea.nom, '')),
                  'resolu_le', i.resolu_le, 'resolution', i.resolution) order by i.cree_le)
                from public.rh_incidents i
                left join public.boutiques b on b.id = i.boutique_id
                left join public.profils p on p.id = i.livreur_id
                left join public.rh_employes ea on ea.id = i.cree_par
               where i.commande_id = commande), '[]'),
    'reclamations', coalesce((select jsonb_agg(jsonb_build_object(
                  'sujet', rc.sujet, 'etat', rc.etat, 'cree_le', rc.cree_le,
                  'boutique', coalesce(b.nom, rc.boutique_id)) order by rc.cree_le)
                from public.reclamations rc left join public.boutiques b on b.id = rc.boutique_id
               where rc.commande_id = commande), '[]'),
    'refus', coalesce((select jsonb_agg(jsonb_build_object(
                  'le', f.refuse_le, 'motif', f.motif, 'livreur', coalesce(nullif(p.nom, ''), p.email)) order by f.refuse_le)
                from public.refus_courses f left join public.profils p on p.id = f.livreur_id
               where f.commande_id = commande), '[]'));
end $$;

/** Le bilan d'une période : les indicateurs du document, par jour, semaine ou mois. */
create or replace function public.rh_suivi_bilan(depuis date default null, jusqu date default null, pas text default 'jour')
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  acces text := public.rh_suivi_acces();
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  fin date := coalesce(jusqu, aujourdhui);
  debut date := coalesce(depuis, coalesce(jusqu, aujourdhui) - 29);
  unite text := case pas when 'semaine' then 'week' when 'mois' then 'month' else 'day' end;
begin
  if acces is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  if fin < debut or fin - debut > 400 then
    raise exception 'Choisissez une période valable, d''un an au plus';
  end if;
  return (
    with d as (
      select x as j,
             date_trunc(unite, ((x ->> 'cree_le')::timestamptz at time zone 'Africa/Porto-Novo'))::date as periode
        from public.rh_suivi_donnees(debut::timestamp at time zone 'Africa/Porto-Novo',
                                     (fin + 1)::timestamp at time zone 'Africa/Porto-Novo') x
    ),
    l as (
      select d.periode, d.j ->> 'id' as commande, d.j ->> 'etat' as etat_commande, e as ligne
        from d, jsonb_array_elements(d.j -> 'lignes') e
    ),
    resume as (
      select periode,
             count(*) as recues,
             count(*) filter (where j ->> 'etat' = 'payee') as payees,
             count(*) filter (where (j ->> 'rang')::int in (8, 14) and j ->> 'confirmation' = 'Oui') as livrees_confirmees,
             count(*) filter (where j ->> 'etat' = 'payee' and (j ->> 'rang')::int between 1 and 6) as en_cours,
             count(*) filter (where (j -> 'alertes') ?| array['non_vue', 'retard_preparation', 'retard_livraison', 'sans_confirmation']) as en_retard,
             count(*) filter (where (j ->> 'rang')::int = 10) as contestees,
             count(*) filter (where (j ->> 'rang')::int = 11 or j ->> 'etat' in ('annulee')) as annulees,
             count(*) filter (where j ->> 'etat' = 'echouee') as paiements_echoues,
             count(*) filter (where (j ->> 'rang')::int in (9, 12, 13)) as echecs_retours,
             coalesce(sum((j ->> 'reste')::bigint) filter (where j ->> 'etat' = 'payee'), 0) as reste
        from d group by periode
    )
    select jsonb_build_object(
      'periode', jsonb_build_object('depuis', debut, 'jusqu', fin, 'pas', coalesce(pas, 'jour')),
      'montants', acces = 'admin',
      'total', (select jsonb_build_object(
          'recues', coalesce(sum(recues), 0), 'payees', coalesce(sum(payees), 0),
          'livrees_confirmees', coalesce(sum(livrees_confirmees), 0), 'en_cours', coalesce(sum(en_cours), 0),
          'en_retard', coalesce(sum(en_retard), 0), 'contestees', coalesce(sum(contestees), 0),
          'annulees', coalesce(sum(annulees), 0), 'paiements_echoues', coalesce(sum(paiements_echoues), 0),
          'echecs_retours', coalesce(sum(echecs_retours), 0),
          'reste', case when acces = 'admin' then coalesce(sum(reste), 0) end) from resume),
      'series', coalesce((select jsonb_agg(jsonb_build_object(
          'periode', periode, 'recues', recues, 'payees', payees, 'livrees_confirmees', livrees_confirmees,
          'en_cours', en_cours, 'en_retard', en_retard, 'contestees', contestees, 'annulees', annulees,
          'echecs_retours', echecs_retours,
          'reste', case when acces = 'admin' then reste end) order by periode) from resume), '[]'),
      'par_livreur', coalesce((select jsonb_agg(x order by (x ->> 'confirmees')::int desc) from (
          select jsonb_build_object(
            'livreur', coalesce(k.livreur, '—'),
            'articles', count(*),
            'confirmees', count(*) filter (where k.confirme is not null),
            'sans_confirmation', count(*) filter (where k.rang = 6),
            'echecs', count(*) filter (where k.rang in (9, 12, 13)),
            'contestees', count(*) filter (where k.rang = 10),
            'delai_moyen_h', round(avg(extract(epoch from (k.confirme - k.vue)) / 3600)
                                   filter (where k.confirme is not null and k.vue is not null)::numeric, 1),
            'refus', (select count(*) from public.refus_courses f join public.profils p on p.id = f.livreur_id
                       where coalesce(nullif(p.nom, ''), p.email) = k.livreur
                         and f.refuse_le >= debut::timestamp at time zone 'Africa/Porto-Novo'
                         and f.refuse_le < (fin + 1)::timestamp at time zone 'Africa/Porto-Novo'),
            'incidents', (select count(*) from public.rh_incidents i join public.profils p on p.id = i.livreur_id
                           where coalesce(nullif(p.nom, ''), p.email) = k.livreur
                             and i.cree_le >= debut::timestamp at time zone 'Africa/Porto-Novo'
                             and i.cree_le < (fin + 1)::timestamp at time zone 'Africa/Porto-Novo')) as x
            from (select ligne ->> 'livreur' as livreur, (ligne ->> 'rang')::int as rang,
                         (ligne ->> 'confirme_le')::timestamptz as confirme, (ligne ->> 'vue_le')::timestamptz as vue
                    from l where ligne ->> 'livreur' is not null and etat_commande = 'payee') k
           group by k.livreur) t), '[]'),
      'par_marchand', coalesce((select jsonb_agg(x order by (x ->> 'articles')::int desc) from (
          select jsonb_build_object(
            'marchand', k.marchand,
            'articles', count(*),
            'annules', count(*) filter (where k.rang = 11),
            'non_vus', count(*) filter (where k.rang = 1),
            'contestes', count(*) filter (where k.rang = 10),
            'delai_preparation_h', round(avg(extract(epoch from (k.preparee - k.vue)) / 3600)
                                         filter (where k.preparee is not null and k.vue is not null)::numeric, 1),
            'incidents', (select count(*) from public.rh_incidents i
                           where i.boutique_id = k.boutique_id
                             and i.cree_le >= debut::timestamp at time zone 'Africa/Porto-Novo'
                             and i.cree_le < (fin + 1)::timestamp at time zone 'Africa/Porto-Novo'),
            'reclamations', (select count(*) from public.reclamations rc
                              where rc.boutique_id = k.boutique_id
                                and rc.cree_le >= debut::timestamp at time zone 'Africa/Porto-Novo'
                                and rc.cree_le < (fin + 1)::timestamp at time zone 'Africa/Porto-Novo')) as x
            from (select ligne ->> 'boutique' as marchand, ligne ->> 'boutique_id' as boutique_id,
                         (ligne ->> 'rang')::int as rang, (ligne ->> 'vue_le')::timestamptz as vue,
                         (select min(jj.le) from public.rh_journal_lignes jj
                           where jj.ligne_id = ligne ->> 'id' and jj.quoi = 'etat' and jj.valeur = 'preparee') as preparee
                    from l where etat_commande = 'payee') k
           group by k.marchand, k.boutique_id) t), '[]'),
      'par_zone', coalesce((select jsonb_agg(jsonb_build_object('zone', zone, 'commandes', nb) order by nb desc) from (
          select coalesce(nullif(j #>> '{client,zone}', ''), 'Non reconnue') as zone, count(*) as nb
            from d where j ->> 'etat' = 'payee' group by 1) z), '[]'),
      'heures', coalesce((select jsonb_agg(jsonb_build_object('heure', h, 'commandes', nb) order by h) from (
          select extract(hour from ((j ->> 'cree_le')::timestamptz at time zone 'Africa/Porto-Novo'))::int as h, count(*) as nb
            from d group by 1) hh), '[]'),
      'jours_semaine', coalesce((select jsonb_agg(jsonb_build_object('jour', js, 'commandes', nb) order by js) from (
          select extract(isodow from ((j ->> 'cree_le')::timestamptz at time zone 'Africa/Porto-Novo'))::int as js, count(*) as nb
            from d group by 1) w), '[]'),
      'clients', (select jsonb_build_object(
          'distincts', count(distinct coalesce(c.client_id::text, c.client_tel)),
          'nouveaux', count(distinct coalesce(c.client_id::text, c.client_tel)) filter (where not exists (
              select 1 from public.commandes o
               where coalesce(o.client_id::text, o.client_tel) = coalesce(c.client_id::text, c.client_tel)
                 and o.etat = 'payee' and o.paye_le < debut::timestamp at time zone 'Africa/Porto-Novo')))
          from public.commandes c
         where c.etat = 'payee'
           and c.paye_le >= debut::timestamp at time zone 'Africa/Porto-Novo'
           and c.paye_le < (fin + 1)::timestamp at time zone 'Africa/Porto-Novo'),
      'annulations', coalesce((select jsonb_agg(jsonb_build_object('motif', motif, 'nombre', nb) order by nb desc) from (
          select case when etat_commande = 'annulee' then 'Commande annulée'
                      when etat_commande = 'echouee' then 'Paiement échoué'
                      else 'Article annulé par ' || coalesce(ligne ->> 'boutique', 'la boutique') end as motif,
                 count(distinct commande) as nb
            from l where (ligne ->> 'rang')::int = 11 or etat_commande in ('annulee', 'echouee')
           group by 1) m), '[]')
    ));
end $$;

-- ---------- Agir sur le suivi ----------
create or replace function public.rh_suivi_terrain(ligne text, statut text, motif text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare
  cmd text;
begin
  if public.rh_suivi_acces() is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  select l.commande_id into cmd from public.commande_lignes l where l.id = ligne;
  if cmd is null then
    raise exception 'Article introuvable';
  end if;
  if exists (select 1 from public.rh_suivi_commandes s where s.commande_id = cmd and s.cloturee_le is not null) then
    raise exception 'Cette commande est clôturée : rouvrez-la d''abord';
  end if;
  if coalesce(statut, '') = '' then
    delete from public.rh_suivi_lignes s where s.ligne_id = ligne;
    return;
  end if;
  if statut not in ('recupere', 'echouee', 'retour_en_cours', 'retournee') then
    raise exception 'Statut inconnu';
  end if;
  if statut = 'echouee' and length(btrim(coalesce(motif, ''))) = 0 then
    raise exception 'Dites pourquoi la livraison a échoué';
  end if;
  insert into public.rh_suivi_lignes as s (ligne_id, commande_id, statut, motif, maj_par, maj_le)
  values (ligne, cmd, statut, btrim(coalesce(motif, '')), public.rh_moi(), now())
  on conflict on constraint rh_suivi_lignes_pkey do update
     set statut = excluded.statut, motif = excluded.motif, maj_par = excluded.maj_par, maj_le = now();
  insert into public.rh_journal_lignes (commande_id, ligne_id, quoi, valeur)
  values (cmd, ligne, 'suivi', statut);
end $$;

create or replace function public.rh_suivi_noter(commande text, zone text default null, observations text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.rh_suivi_acces() is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  if not exists (select 1 from public.commandes c where c.id = commande) then
    raise exception 'Commande introuvable';
  end if;
  insert into public.rh_suivi_commandes as s (commande_id, zone, observations, maj_par, maj_le)
  values (commande, btrim(coalesce(zone, '')), btrim(coalesce(observations, '')), public.rh_moi(), now())
  on conflict on constraint rh_suivi_commandes_pkey do update
     set zone = case when rh_suivi_noter.zone is null then s.zone else btrim(rh_suivi_noter.zone) end,
         observations = case when rh_suivi_noter.observations is null then s.observations
                             else btrim(rh_suivi_noter.observations) end,
         maj_par = public.rh_moi(), maj_le = now();
end $$;

create or replace function public.rh_incident_ouvrir(commande text, type text, description text,
                                                     boutique text default null, livreur uuid default null)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  nouveau bigint;
  cible   text;
begin
  if public.rh_suivi_acces() is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  -- (3.69.0) La commande, par son identifiant ou par son numéro (« BZ-… »),
  -- comme on le lit au client : le menu Incidents n'a que lui.
  select c.id into cible from public.commandes c where c.id = commande;
  if cible is null then
    select min(c.id) into cible from public.commandes c
     where upper(c.numero) = upper(btrim(coalesce(commande, '')));
  end if;
  if cible is null then
    raise exception 'Commande introuvable : vérifiez son numéro';
  end if;
  if length(btrim(coalesce(description, ''))) = 0 then
    raise exception 'Décrivez l''incident';
  end if;
  insert into public.rh_incidents (commande_id, boutique_id, livreur_id, type, description, cree_par)
  values (cible, nullif(boutique, ''), livreur, type, btrim(description), public.rh_moi())
  returning id into nouveau;
  return nouveau;
end $$;

create or replace function public.rh_incident_resoudre(incident bigint, resolution text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.rh_suivi_acces() is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  if length(btrim(coalesce(resolution, ''))) = 0 then
    raise exception 'Dites comment l''incident a été résolu';
  end if;
  update public.rh_incidents
     set resolu_le = now(), resolu_par = public.rh_moi(), resolution = btrim(rh_incident_resoudre.resolution)
   where id = incident and resolu_le is null;
  if not found then
    raise exception 'Cet incident est déjà résolu';
  end if;
end $$;

/**
 * Ce qui empêche de clôturer une commande, ou rien (null) : un incident
 * ouvert, un client qui conteste, un article qui n'a pas fini son
 * parcours (confirmé, annulé, échoué ou retourné), un reste à encaisser.
 * La même règle pour la clôture à la main et pour la clôture automatique.
 */
create or replace function public.rh_suivi_cloturable(d jsonb) returns text
language sql stable set search_path = public as $$
  select case
    when d ->> 'cloturee_le' is not null then 'Cette commande est déjà clôturée'
    when (d ->> 'incidents_ouverts')::int > 0 then 'Un incident reste ouvert : résolvez-le avant de clôturer'
    when exists (select 1 from jsonb_array_elements(d -> 'lignes') l where (l ->> 'rang')::int = 10)
      then 'Le client conteste encore la livraison : la réclamation doit être réglée avant de clôturer'
    when d ->> 'etat' = 'payee' and exists (select 1 from jsonb_array_elements(d -> 'lignes') l
                                             where (l ->> 'rang')::int not in (8, 9, 11, 13))
      then 'Un article n''a pas fini son parcours (livré et confirmé, annulé, échoué ou retourné)'
    -- (3.69.0) L'argent d'abord : un reste dû à la livraison doit être encaissé.
    when coalesce((d ->> 'reste')::bigint, 0) > 0
      then 'Un reste à encaisser n''est pas réglé : encaissez-le avant de clôturer'
  end;
$$;

/**
 * Clôturer : le suivi est terminé. REFUSÉ tant qu'un incident reste
 * ouvert, qu'un client conteste encore, ou qu'un article n'a pas fini
 * son parcours (confirmé, annulé, échoué ou retourné).
 */
create or replace function public.rh_suivi_cloturer(commande text) returns void
language plpgsql security definer set search_path = public as $$
declare
  d jsonb;
  refus text;
begin
  if public.rh_suivi_acces() is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  select x into d from public.rh_suivi_donnees(null, null, commande) x;
  if d is null then
    raise exception 'Commande introuvable';
  end if;
  refus := public.rh_suivi_cloturable(d);
  if refus is not null then
    raise exception '%', refus;
  end if;
  insert into public.rh_suivi_commandes as s (commande_id, cloturee_le, cloturee_par, maj_par, maj_le)
  values (commande, now(), public.rh_moi(), public.rh_moi(), now())
  on conflict on constraint rh_suivi_commandes_pkey do update
     set cloturee_le = now(), cloturee_par = public.rh_moi(), maj_par = public.rh_moi(), maj_le = now();
  insert into public.rh_journal_lignes (commande_id, quoi, valeur) values (commande, 'suivi', 'cloturee');
end $$;

create or replace function public.rh_suivi_rouvrir(commande text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_admin() then
    raise exception 'Seule l''administration rouvre une commande clôturée';
  end if;
  update public.rh_suivi_commandes set cloturee_le = null, cloturee_par = null, maj_par = public.rh_moi(), maj_le = now()
   where commande_id = commande and cloturee_le is not null;
  if not found then
    raise exception 'Cette commande n''est pas clôturée';
  end if;
  insert into public.rh_journal_lignes (commande_id, quoi, valeur) values (commande, 'suivi', 'rouverte');
end $$;

create or replace function public.rh_suivi_regler(vue_h int, preparation_h int, livraison_h int, confirmation_h int)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_admin() then
    raise exception 'Seule l''administration règle les délais';
  end if;
  update public.rh_reglages_suivi
     set vue_h = rh_suivi_regler.vue_h, preparation_h = rh_suivi_regler.preparation_h,
         livraison_h = rh_suivi_regler.livraison_h, confirmation_h = rh_suivi_regler.confirmation_h
   where id;
end $$;

create or replace function public.rh_zone_ajouter(nom_zone text, commune_zone text default '') returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.rh_est_admin() then
    raise exception 'Seule l''administration ajoute une zone';
  end if;
  if length(btrim(coalesce(nom_zone, ''))) < 3 then
    raise exception 'Le nom de la zone est trop court';
  end if;
  insert into public.rh_zones (nom, type, commune) values (btrim(nom_zone), 'ajout', btrim(coalesce(commune_zone, '')))
  on conflict do nothing;
end $$;

-- ---------- Les droits ----------
do $$
declare t text;
begin
  foreach t in array array['rh_journal_lignes', 'rh_suivi_lignes', 'rh_suivi_commandes', 'rh_incidents',
                           'rh_reglages_suivi', 'rh_zones'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
    execute format('grant all on table public.%I to service_role', t);
  end loop;
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'rh_suivi_acces()', 'rh_suivi(date, date)', 'rh_suivi_alertes_nb()', 'rh_suivi_commande(text)',
    'rh_suivi_bilan(date, date, text)', 'rh_suivi_terrain(text, text, text)', 'rh_suivi_noter(text, text, text)',
    'rh_incident_ouvrir(text, text, text, text, uuid)', 'rh_incident_resoudre(bigint, text)',
    'rh_suivi_cloturer(text)', 'rh_suivi_rouvrir(text)', 'rh_suivi_regler(int, int, int, int)',
    'rh_zone_ajouter(text, text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
  foreach f in array array[
    'rh_journaliser_ligne()', 'rh_journaliser_commande()', 'rh_suivi_donnees(timestamptz, timestamptz, text)',
    'rh_suivi_sans_montants(jsonb)', 'rh_zone_de(text)', 'rh_statut_ligne(text, timestamptz, text, boolean)',
    'rh_statut_libelle(int)', 'rh_cle(text)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;
