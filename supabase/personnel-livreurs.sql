-- =========================================================
-- BIZZOO Personnel : le menu Livreurs — la liste, la fiche et les
-- statistiques de chaque livreur ; l'administration peut le bloquer :
-- il ne reçoit plus de course.
--
-- À coller tel quel dans l'éditeur SQL ; il se rejoue sans dommage.
-- =========================================================

alter table public.profils add column if not exists courses_bloquees boolean not null default false;

-- ---------- Ce qui change (copies de schema.sql) ----------
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

create or replace function public.equipe_de(cible text) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p.id), '{}'::uuid[])
    from public.profils p
   where p.actif and cible is not null and p.boutique_id = cible
     and p.role in ('administrateur', 'moderateur');
$$;

create or replace function public.rh_moi() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_mon_profil() returns uuid
language sql stable security definer set search_path = public as $$
  select profil_id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_est_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and (administration or ceo));
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

create or replace function public.livreur_en_course(qui uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
     where l.livreur_id = qui and c.etat = 'payee'
       and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison'));
$$;

create or replace function public.candidats_course(commande text)
returns uuid[]
language plpgsql stable security definer set search_path = public as $$
declare
  boutiques text[];
  qui       uuid[];
  besoin    text;
  vs        text[];
  v         text;
begin
  select array_agg(distinct l.boutique_id) into boutiques
    from public.commande_lignes l
   where l.commande_id = commande and l.etat <> 'annulee' and l.boutique_id is not null;
  if boutiques is null then return '{}'; end if;
  select c.livraison ->> 'vehicule' into besoin from public.commandes c where c.id = commande;
  vs := case besoin when 'tricycle' then array['tricycle']
                    when 'moto' then array['moto', 'tricycle']
                    else array[null::text] end;
  if array_length(boutiques, 1) = 1 then
    foreach v in array vs loop
      select array_agg(p.id order by p.id) into qui
        from public.profils p
       where p.role = 'livreur' and p.actif and not p.courses_bloquees and p.boutique_id = boutiques[1]
         and (v is null or p.vehicule = v)
         and exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id);
      if qui is not null then return qui; end if;
    end loop;
  end if;
  foreach v in array vs loop
    select array_agg(p.id order by p.id) into qui
      from public.profils p
     where p.role = 'livreur' and p.actif and not p.courses_bloquees and p.boutique_id is null
       and (v is null or p.vehicule = v)
       and exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id);
    if qui is not null then return qui; end if;
  end loop;
  return '{}';
end $$;

create or replace function public.assigner_livreur(
  commande text, boutique text, livreur uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  combien  int;
  autres   int := 0;
  rang     text;
  bizzoo   boolean := false;
  numero   text;
  b        record;
  son_vehicule text;
  besoin   text;
  plusieurs boolean;
  au_km    boolean;
  bloque   boolean;
begin
  if not public.peut_agir_sur(boutique) then
    raise exception 'Cette commande ne concerne pas votre boutique';
  end if;
  -- (3.64.0) UN SEUL LIVREUR PAR COMMANDE AU KILOMÈTRE. Une telle
  -- commande de plusieurs boutiques se confie à un livreur de BIZZOO, qui
  -- les livre toutes ; et une commande en tricycle, à un livreur en
  -- tricycle. Les commandes d'avant (frais par boutique) gardent leur
  -- règle : un livreur par boutique.
  select c.livraison ->> 'vehicule', c.livraison is not null into besoin, au_km
    from public.commandes c where c.id = commande;
  au_km := coalesce(au_km, false);
  select au_km and count(distinct l.boutique_id) > 1 into plusieurs
    from public.commande_lignes l where l.commande_id = commande and l.etat <> 'annulee';

  -- « livreur » nul : on retire l'attribution. Une boutique doit pouvoir
  -- reprendre une course confiée par erreur.
  if livreur is not null then
    select p.role, (p.boutique_id is null), p.vehicule, p.courses_bloquees
      into rang, bizzoo, son_vehicule, bloque from public.profils p
     where p.id = livreur and p.actif
       and (public.est_super()
            or public.est_compte_enseigne()
            -- Le livreur de BIZZOO : aucune boutique, donc toutes.
            or p.boutique_id is null
            or p.boutique_id = public.boutique_du_compte());
    if rang is distinct from 'livreur' then
      raise exception 'Ce compte n''est pas un livreur de votre boutique ni de BIZZOO';
    end if;
    -- Bloqué par l'administration de BIZZOO : plus aucune course.
    if bloque then
      raise exception 'Ce livreur est bloqué par BIZZOO : il ne reçoit plus de course. Confiez-la à un autre.'
        using errcode = 'P0001';
    end if;
    if coalesce(plusieurs, false) and not coalesce(bizzoo, false) then
      raise exception 'Cette commande traverse plusieurs boutiques : confiez-la à un livreur de BIZZOO, qui les livre toutes.'
        using errcode = 'P0001';
    end if;
    if besoin = 'tricycle' and son_vehicule is distinct from 'tricycle' then
      raise exception 'Cette commande se livre en tricycle : confiez-la à un livreur en tricycle.'
        using errcode = 'P0001';
    end if;
    -- UN LIVREUR VALIDE SON COMPTE EN ENREGISTRANT SA POSITION. Tant
    -- qu'il ne l'a pas fait, on ne lui confie rien.
    if not exists (select 1 from public.positions_livreurs pl where pl.profil_id = livreur) then
      raise exception 'Ce livreur n''a pas encore validé son compte : il doit ouvrir BIZZOO Admin et enregistrer sa position.'
        using errcode = 'P0001';
    end if;
  end if;

  perform set_config('bizzoo.livraison', 'oui', true);
  update public.commande_lignes l
     set livreur_id = livreur,
         -- Un autre livreur doit accepter à son tour (3.59.0).
         recu_le = case when l.livreur_id is distinct from livreur then null else l.recu_le end
   where l.commande_id = commande
     -- (3.64.0) Au kilomètre, retirer le livreur le retire de toute la
     -- commande : une course, c'est la commande entière.
     and (l.boutique_id = boutique or (livreur is null and au_km))
     -- (3.59.0) En secours de la demande envoyée à tous les livreurs : la
     -- boutique peut confier dès le paiement, sans attendre le colis.
     and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')
     and exists (select 1 from public.commandes c where c.id = l.commande_id and c.etat = 'payee');
  get diagnostics combien = row_count;

  -- LE LIVREUR DE BIZZOO : les produits des autres boutiques aussi. Sans
  -- prendre une part déjà confiée au livreur d'une autre boutique —
  -- (3.64.0) sauf au kilomètre : un seul livreur par commande, il les
  -- prend toutes.
  if bizzoo and combien > 0 then
    update public.commande_lignes l
       set livreur_id = livreur, recu_le = null
     where l.commande_id = commande
       and l.boutique_id <> boutique
       and (l.livreur_id is null or (au_km and l.livreur_id is distinct from livreur))
       and l.etat in ('nouvelle', 'vue', 'preparee', 'en_livraison');
    get diagnostics autres = row_count;
  end if;
  perform set_config('bizzoo.livraison', '', true);

  if combien = 0 then
    raise exception 'Rien à confier ici : la commande n''est pas encore payée, ou elle est déjà livrée.';
  end if;

  -- Les autres boutiques le savent : un livreur BIZZOO passera chez elles.
  if autres > 0 then
    select c.numero into numero from public.commandes c where c.id = commande;
    for b in select distinct l.boutique_id as id from public.commande_lignes l
              where l.commande_id = commande and l.boutique_id <> boutique and l.livreur_id = livreur
    loop
      perform public.notifier(public.equipe_de(b.id), 'course_confiee',
        'Un livreur BIZZOO passe récupérer vos produits',
        'Commande ' || coalesce(numero, '') || ' — il livre toute la commande. Préparez le colis.',
        '#/commandes/' || commande, commande, b.id, true);
    end loop;
  end if;
  return combien + autres;
end $$;


-- =========================================================
-- BIZZOO Personnel : le menu Livreurs
--
-- La liste de tous les livreurs (de BIZZOO et des boutiques), avec ce
-- que chacun a fait sur la période ; un clic ouvre sa fiche et ses
-- statistiques (rh_livreurs, rh_livreur_fiche). Mêmes droits que la
-- carte et le classement des livreurs : l'administration, le
-- superadministrateur, et les profils à qui Paramètres ouvre
-- « Localiser un livreur » ou les statistiques des livreurs. Les
-- montants (gains, encaissements) : l'administration seulement.
--
-- BLOQUER UN LIVREUR (rh_bloquer_livreur) : l'administration seule, motif
-- obligatoire. Il ne reçoit plus aucune course : aucune demande ne lui
-- est proposée, il ne peut plus en prendre, et personne ne peut lui en
-- confier. Ses courses pas encore parties sont retirées et repartent
-- vers les boutiques, qui les confient à un autre ; celles qu'il a déjà
-- en route, il les termine. Il garde son compte : il voit ses courses
-- passées et rend ce qu'il a encaissé. Chaque blocage et chaque
-- déblocage est gardé, avec son auteur et son motif.
-- =========================================================

-- Personne ne pose ce drapeau à la main : seulement rh_bloquer_livreur.
-- Les comptes de boutique qui modifient leurs livreurs ne le peuvent pas.
create or replace function public.profils_garde_blocage() returns trigger
language plpgsql set search_path = public as $$
begin
  if coalesce(current_setting('bizzoo.blocage', true), '') = 'oui' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.courses_bloquees := false;
  elsif new.courses_bloquees is distinct from old.courses_bloquees then
    raise exception 'Le blocage d''un livreur se décide dans BIZZOO Personnel, par l''administration';
  end if;
  return new;
end $$;
drop trigger if exists profils_garde_blocage on public.profils;
create trigger profils_garde_blocage
  before insert or update on public.profils
  for each row execute function public.profils_garde_blocage();

-- L'historique des blocages : on ne l'efface pas, personne n'y écrit
-- directement.
create table if not exists public.livreurs_blocages (
  id          bigserial primary key,
  profil_id   uuid not null references public.profils(id) on delete cascade,
  bloque      boolean not null,
  motif       text not null default '',
  par_compte  uuid,
  par_nom     text not null default '',
  le          timestamptz not null default now()
);
create index if not exists livreurs_blocages_profil on public.livreurs_blocages(profil_id, le desc);
alter table public.livreurs_blocages enable row level security;
revoke all on public.livreurs_blocages from anon, authenticated;
revoke all on sequence public.livreurs_blocages_id_seq from anon, authenticated;
grant all on public.livreurs_blocages to service_role;
grant usage, select on sequence public.livreurs_blocages_id_seq to service_role;

/** Qui ouvre le menu Livreurs. */
create or replace function public.rh_voit_livreurs() returns boolean
language sql stable security definer set search_path = public as $$
  select public.est_super() or public.rh_menu_ouvert('livreurs') or public.rh_menu_ouvert('stats_livreurs');
$$;

/** Tous les livreurs, et ce que chacun a fait sur la période. */
create or replace function public.rh_livreurs(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  d1 date := coalesce(depuis, aujourdhui - 29);
  d2 date := coalesce(jusqu, aujourdhui);
  t1 timestamptz;
  t2 timestamptz;
  argent boolean := public.rh_est_admin() or public.est_super();
begin
  if not public.rh_voit_livreurs() then
    raise exception 'Votre compte n''a pas accès aux livreurs';
  end if;
  if d2 < d1 then
    raise exception 'La fin de la période précède son début';
  end if;
  if d2 - d1 > 1100 then
    raise exception 'Choisissez une période de trois ans au plus';
  end if;
  t1 := d1::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (d2 + 1)::timestamp at time zone 'Africa/Porto-Novo';
  return jsonb_build_object(
    'periode', jsonb_build_object('depuis', d1, 'jusqu', d2),
    'droits', jsonb_build_object('argent', argent, 'bloquer', argent),
    'livreurs', (select coalesce(jsonb_agg(x.j order by x.bloque, x.courses desc, x.nom), '[]') from (
      select p.courses_bloquees as bloque, k.courses,
             coalesce(nullif(btrim(p.nom), ''), p.email, 'Livreur') as nom,
             jsonb_build_object(
               'id', p.id,
               'nom', coalesce(nullif(btrim(p.nom), ''), p.email, 'Livreur'),
               'tel', coalesce(p.tel, ''),
               'vehicule', coalesce(p.vehicule, 'moto'),
               'boutique', (select b.nom from public.boutiques b where b.id = p.boutique_id),
               'actif', p.actif,
               'valide', exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id),
               'bloque', p.courses_bloquees,
               'en_course', public.livreur_en_course(p.id),
               'courses', k.courses,
               'livrees', k.livrees,
               'refus', (select count(*) from public.refus_courses r
                          where r.livreur_id = p.id and r.refuse_le >= t1 and r.refuse_le < t2),
               'derniere', (select max(c.paye_le) from public.commande_lignes l
                              join public.commandes c on c.id = l.commande_id
                             where l.livreur_id = p.id and c.etat = 'payee'),
               'gains', case when argent then
                 (select coalesce(sum(g.montant), 0) from public.gains_livreurs g
                   where g.livreur_id = p.id and g.credite_le >= t1 and g.credite_le < t2) end) as j
        from public.profils p
        cross join lateral (
          select count(distinct l.commande_id) as courses,
                 count(distinct l.commande_id) filter (where l.etat = 'remise') as livrees
            from public.commande_lignes l
            join public.commandes c on c.id = l.commande_id
           where l.livreur_id = p.id and c.etat = 'payee' and c.paye_le >= t1 and c.paye_le < t2) k
       where p.role = 'livreur') x));
end $$;

/** La fiche d'un livreur : qui il est, ses chiffres, ses courses, ses
    refus, et l'historique de ses blocages. */
create or replace function public.rh_livreur_fiche(livreur uuid, depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  d1 date := coalesce(depuis, aujourdhui - 29);
  d2 date := coalesce(jusqu, aujourdhui);
  t1 timestamptz;
  t2 timestamptz;
  argent boolean := public.rh_est_admin() or public.est_super();
  p public.profils;
  chiffres jsonb;
  courses jsonb;
begin
  if not public.rh_voit_livreurs() then
    raise exception 'Votre compte n''a pas accès aux livreurs';
  end if;
  if d2 < d1 then
    raise exception 'La fin de la période précède son début';
  end if;
  if d2 - d1 > 1100 then
    raise exception 'Choisissez une période de trois ans au plus';
  end if;
  select * into p from public.profils x where x.id = livreur and x.role = 'livreur';
  if not found then
    raise exception 'Livreur introuvable';
  end if;
  t1 := d1::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (d2 + 1)::timestamp at time zone 'Africa/Porto-Novo';

  -- Une course = une commande qu'il porte. Son étape : la moins avancée
  -- de ses articles encore valables.
  with k as (
    select c.id, c.numero, c.paye_le,
           min(l.recu_le) as recu_le, max(l.confirme_le) as confirme_le,
           coalesce((array['nouvelle', 'vue', 'preparee', 'en_livraison', 'remise'])[
             min(array_position(array['nouvelle', 'vue', 'preparee', 'en_livraison', 'remise'], l.etat))],
             'annulee') as etat,
           string_agg(distinct b.nom, ', ') as boutiques
      from public.commande_lignes l
      join public.commandes c on c.id = l.commande_id
      left join public.boutiques b on b.id = l.boutique_id
     where l.livreur_id = livreur and c.etat = 'payee' and c.paye_le >= t1 and c.paye_le < t2
     group by c.id, c.numero, c.paye_le
  )
  select jsonb_build_object(
           'courses', count(*),
           'livrees', count(*) filter (where etat = 'remise'),
           'en_cours', count(*) filter (where etat in ('nouvelle', 'vue', 'preparee', 'en_livraison')),
           'annulees', count(*) filter (where etat = 'annulee'),
           'confirmees', count(*) filter (where confirme_le is not null),
           'delai_prise_minutes', round(avg(extract(epoch from (recu_le - paye_le)) / 60)
                                         filter (where recu_le >= paye_le)),
           'delai_livraison_heures', round((avg(extract(epoch from (confirme_le - paye_le)) / 3600)
                                         filter (where confirme_le >= paye_le))::numeric, 1)),
         coalesce(jsonb_agg(jsonb_build_object(
           'commande', id, 'numero', numero, 'paye_le', paye_le, 'boutiques', boutiques,
           'etat', etat, 'recu_le', recu_le, 'confirme_le', confirme_le,
           'gain', case when argent then
             (select sum(g.montant) from public.gains_livreurs g
               where g.commande_id = k.id and g.livreur_id = livreur) end)
           order by paye_le desc), '[]')
    into chiffres, courses
    from k;

  chiffres := chiffres || jsonb_build_object(
    'refus', (select count(*) from public.refus_courses r
               where r.livreur_id = livreur and r.refuse_le >= t1 and r.refuse_le < t2),
    'gains', case when argent then
      (select coalesce(sum(g.montant), 0) from public.gains_livreurs g
        where g.livreur_id = livreur and g.credite_le >= t1 and g.credite_le < t2) end,
    'encaisse', case when argent then
      (select coalesce(sum(e.montant), 0) from public.encaissements e
        where e.livreur_id = livreur and e.encaisse_le >= t1 and e.encaisse_le < t2) end,
    'contestes', (select count(*) from public.encaissements e
                   where e.livreur_id = livreur and e.conteste_le is not null
                     and e.encaisse_le >= t1 and e.encaisse_le < t2));

  return jsonb_build_object(
    'periode', jsonb_build_object('depuis', d1, 'jusqu', d2),
    'droits', jsonb_build_object('argent', argent, 'bloquer', argent),
    'livreur', jsonb_build_object(
      'id', p.id,
      'nom', coalesce(nullif(btrim(p.nom), ''), p.email, 'Livreur'),
      'tel', coalesce(p.tel, ''),
      'vehicule', coalesce(p.vehicule, 'moto'),
      'boutique', (select b.nom from public.boutiques b where b.id = p.boutique_id),
      'actif', p.actif,
      'valide', exists (select 1 from public.positions_livreurs pl where pl.profil_id = p.id),
      'bloque', p.courses_bloquees,
      'cree_le', p.cree_le,
      'en_course', public.livreur_en_course(p.id),
      'position', (select jsonb_build_object('adresse', pl.adresse, 'le', pl.enregistre_le)
                     from public.positions_livreurs pl where pl.profil_id = p.id)),
    'chiffres', chiffres,
    'courses', (select coalesce(jsonb_agg(x order by x ->> 'paye_le' desc), '[]')
                  from (select x from jsonb_array_elements(courses) x limit 50) y),
    'refus', (select coalesce(jsonb_agg(jsonb_build_object(
                 'numero', c.numero, 'boutique', b.nom, 'motif', r.motif, 'le', r.refuse_le)
                 order by r.refuse_le desc), '[]')
                from (select * from public.refus_courses r0
                       where r0.livreur_id = livreur and r0.refuse_le >= t1 and r0.refuse_le < t2
                       order by r0.refuse_le desc limit 20) r
                left join public.commandes c on c.id = r.commande_id
                left join public.boutiques b on b.id = r.boutique_id),
    'blocages', (select coalesce(jsonb_agg(jsonb_build_object(
                   'bloque', x.bloque, 'motif', x.motif, 'par', x.par_nom, 'le', x.le)
                   order by x.le desc, x.id desc), '[]')
                  from public.livreurs_blocages x where x.profil_id = livreur));
end $$;

/** Bloquer ou débloquer un livreur : l'administration seule. Bloqué, il
    ne reçoit plus de course ; ses courses pas encore parties retournent
    aux boutiques. Rend le nombre de parts de commande retirées. */
create or replace function public.rh_bloquer_livreur(livreur uuid, bloquer boolean, motif text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  pourquoi text := left(btrim(coalesce(motif, '')), 300);
  p        public.profils;
  auteur   text;
  porteur  text;
  c        record;
  parts    record;
  annonce  boolean;
  liberees int := 0;
begin
  if not (public.rh_est_admin() or public.est_super()) then
    raise exception 'Seule l''administration bloque ou débloque un livreur';
  end if;
  if bloquer is null then
    raise exception 'Bloquer ou débloquer ?';
  end if;
  select * into p from public.profils x where x.id = livreur and x.role = 'livreur' for update;
  if not found then
    raise exception 'Livreur introuvable';
  end if;
  if p.courses_bloquees = bloquer then
    raise exception '%', case when bloquer then 'Ce livreur est déjà bloqué' else 'Ce livreur n''est pas bloqué' end;
  end if;
  if bloquer and length(pourquoi) < 3 then
    raise exception 'Dites pourquoi vous bloquez ce livreur';
  end if;
  select nullif(btrim(e.prenoms || ' ' || e.nom), '') into auteur
    from public.rh_employes e where e.id = public.rh_moi();
  auteur := coalesce(auteur, (select nullif(btrim(x.nom), '') from public.profils x where x.id = auth.uid()),
                     'Superadministrateur');
  porteur := coalesce(nullif(btrim(p.nom), ''), 'Le livreur');

  perform set_config('bizzoo.blocage', 'oui', true);
  update public.profils set courses_bloquees = bloquer where id = livreur;
  perform set_config('bizzoo.blocage', '', true);
  insert into public.livreurs_blocages (profil_id, bloque, motif, par_compte, par_nom)
  values (livreur, bloquer, pourquoi, auth.uid(), auteur);

  if not bloquer then
    perform public.notifier(array[livreur], 'livreur_debloque', 'Courses rétablies',
      'BIZZOO vous propose de nouveau des courses.', '#/livraisons', null, null, true);
    return jsonb_build_object('liberees', 0);
  end if;

  -- SES COURSES PAS ENCORE PARTIES retournent aux boutiques, comme s'il
  -- les avait refusées (refuser_course) — sans les compter comme ses refus.
  for c in
    select distinct l.commande_id, cm.numero, cm.client_id
      from public.commande_lignes l
      join public.commandes cm on cm.id = l.commande_id
     where l.livreur_id = livreur and l.etat in ('nouvelle', 'vue', 'preparee')
  loop
    select exists (select 1 from public.commande_lignes l
                    where l.commande_id = c.commande_id and l.livreur_id = livreur and l.recu_le is not null)
      into annonce;
    -- Une nouvelle course, de nouvelles nouvelles (voir refuser_course).
    update public.notifications n
       set type = n.type || '_avant_' || n.id
     where n.commande_id = c.commande_id
       and n.type in ('course_confiee', 'course_acceptee', 'course_refusee');
    perform set_config('bizzoo.livraison', 'oui', true);
    perform set_config('bizzoo.refus', 'oui', true);
    for parts in
      with retirees as (
        update public.commande_lignes l
           set livreur_id = null, recu_le = null
         where l.commande_id = c.commande_id and l.livreur_id = livreur
           and l.etat in ('nouvelle', 'vue', 'preparee')
        returning l.boutique_id
      )
      select distinct boutique_id from retirees
    loop
      liberees := liberees + 1;
      perform public.notifier(public.equipe_de(parts.boutique_id), 'course_refusee',
        'Course à confier de nouveau — ' || coalesce(c.numero, ''),
        porteur || ' ne prend plus de course pour BIZZOO. Confiez-la à un autre livreur.',
        '#/commandes/' || c.commande_id, c.commande_id, parts.boutique_id, true);
    end loop;
    perform set_config('bizzoo.refus', '', true);
    perform set_config('bizzoo.livraison', '', true);
    if annonce and c.client_id is not null then
      perform public.notifier(array[c.client_id], 'course_refusee',
        'Votre livreur a changé',
        'Commande ' || coalesce(c.numero, '') || ' : ' || porteur ||
          ' ne peut pas la livrer. Un autre livreur va la prendre ; vous recevrez son nom et son numéro.',
        '#/commande/' || c.commande_id, c.commande_id, null, true);
    end if;
  end loop;

  perform public.notifier(array[livreur], 'livreur_bloque', 'Courses suspendues',
    'BIZZOO ne vous propose plus de course pour le moment. Rapprochez-vous de BIZZOO.' ||
      case when liberees > 0 then ' Vos courses pas encore parties ont été retirées.' else '' end,
    '#/livraisons', null, null, true);
  return jsonb_build_object('liberees', liberees);
end $$;

revoke all on function public.profils_garde_blocage() from public, anon, authenticated;
revoke all on function public.rh_voit_livreurs() from public, anon;
grant execute on function public.rh_voit_livreurs() to authenticated, service_role;
revoke all on function public.rh_livreurs(date, date) from public, anon;
grant execute on function public.rh_livreurs(date, date) to authenticated, service_role;
revoke all on function public.rh_livreur_fiche(uuid, date, date) from public, anon;
grant execute on function public.rh_livreur_fiche(uuid, date, date) to authenticated, service_role;
revoke all on function public.rh_bloquer_livreur(uuid, boolean, text) from public, anon;
grant execute on function public.rh_bloquer_livreur(uuid, boolean, text) to authenticated, service_role;
