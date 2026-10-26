-- =========================================================
-- BIZZOO Personnel : le solde de chaque employé, les prêts, les retraits
--
-- Le calendrier de la paie :
--   - le 5, la base calcule seule les fiches du mois écoulé, qui
--     attendent la validation du CEO ;
--   - le 10, chaque fiche validée est versée sur le SOLDE de son
--     employé (une fiche validée après le 10 l'est aussitôt) ;
--   - l'employé retire ensuite son argent quand il veut, tout ou partie :
--     par Mobile Money (FeexPay, reversement validé par le gestionnaire
--     de la caisse) ou à la caisse.
--
-- Ce que verse la fiche : salaire + primes − retenues − prêt.
-- Le CEO accorde une prime ou impose une retenue sur la prochaine paie
-- d'un employé. L'employé demande un prêt : le CEO le valide, la caisse
-- le décaisse, et la paie suivante le reprend en une fois.
--
-- Rien ne s'efface : le solde est la somme de mouvements figés, et un
-- retrait refusé ou échoué revient sur le solde par un mouvement de
-- retour. Le jeton FeexPay ne vit que dans les secrets de Supabase : la
-- base ne fait que noter ce que la fonction Edge « rh-reversement » a
-- constaté chez FeexPay.
-- =========================================================

-- ---------- Le solde : des mouvements, jamais corrigés ----------
create table if not exists public.rh_solde_mouvements (
  id          bigint generated always as identity primary key,
  le          timestamptz not null default now(),
  employe_id  uuid not null references public.rh_employes(id) on delete cascade,
  sens        text not null check (sens in ('credit', 'debit')),
  nature      text not null check (nature in ('salaire', 'retrait', 'retour')),
  montant     bigint not null check (montant > 0),
  libelle     text not null default '',
  fiche_id    uuid references public.rh_fiches_paie(id) on delete set null,
  retrait_id  uuid,
  par         uuid,
  solde       bigint not null   -- le solde de l'employé, après ce mouvement
);
create index if not exists rh_solde_mouvements_employe on public.rh_solde_mouvements (employe_id, id);
-- Une fiche ne se verse qu'une fois.
create unique index if not exists rh_solde_mouvements_fiche on public.rh_solde_mouvements (fiche_id)
  where nature = 'salaire' and fiche_id is not null;

create or replace function public.rh_solde_fige() returns trigger
language plpgsql as $$
begin
  raise exception 'Un mouvement du solde ne se modifie ni ne s''efface';
end $$;
drop trigger if exists rh_solde_fige on public.rh_solde_mouvements;
create trigger rh_solde_fige before update or delete on public.rh_solde_mouvements
  for each row execute function public.rh_solde_fige();

-- ---------- Les retraits ----------
--   demande   : l'employé l'a demandé ; le montant a quitté son solde ;
--   envoi     : le gestionnaire a lancé le reversement, FeexPay n'a pas encore répondu ;
--   envoye    : FeexPay l'a accepté (référence notée), le versement est en cours ;
--   incertain : on ne sait pas si l'argent est parti (coupure, panne) :
--               le CEO tranche après avoir regardé le tableau de bord FeexPay ;
--   paye      : versé (FeexPay l'a confirmé, ou la caisse l'a remis) ;
--   echoue / refuse / annule : rien n'est parti, le montant est revenu sur le solde.
create table if not exists public.rh_retraits (
  id           uuid primary key default gen_random_uuid(),
  numero       bigint generated always as identity,
  employe_id   uuid not null references public.rh_employes(id) on delete cascade,
  montant      bigint not null check (montant > 0),
  moyen        text not null check (moyen in ('feexpay', 'caisse')),
  reseau       text check (reseau in ('mtn', 'moov', 'celtiis')),
  telephone    text not null default '',
  statut       text not null default 'demande'
               check (statut in ('demande', 'envoi', 'envoye', 'incertain', 'paye', 'echoue', 'refuse', 'annule')),
  motif        text not null default '',
  reference    text not null default '',
  demande_le   timestamptz not null default now(),
  traite_par   uuid,
  traite_le    timestamptz,
  conclu_le    timestamptz,
  -- Ce qu'on a envoyé à FeexPay et ce qu'il a répondu, jeton retiré.
  journal      jsonb not null default '[]'::jsonb
);
create index if not exists rh_retraits_employe on public.rh_retraits (employe_id, demande_le desc);
create index if not exists rh_retraits_statut on public.rh_retraits (statut);

-- ---------- Les prêts : les avances, demandées par l'employé ----------
alter table public.rh_avances add column if not exists valide_par uuid;
alter table public.rh_avances add column if not exists valide_le timestamptz;
alter table public.rh_avances add column if not exists motif_refus text not null default '';
alter table public.rh_avances add column if not exists decaisse_par uuid;
alter table public.rh_avances add column if not exists decaisse_le timestamptz;
alter table public.rh_avances add column if not exists reference_caisse text not null default '';
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'rh_avances_statut_check'
               and pg_get_constraintdef(oid) not like '%demandee%') then
    alter table public.rh_avances drop constraint rh_avances_statut_check;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_avances_statut_check') then
    alter table public.rh_avances add constraint rh_avances_statut_check
      check (statut in ('demandee', 'validee', 'active', 'soldee', 'annulee', 'refusee'));
  end if;
end $$;

-- La caisse décaisse aussi les prêts.
do $$
begin
  if exists (select 1 from pg_constraint where conname = 'rh_caisse_mouvements_nature_check'
               and pg_get_constraintdef(oid) not like '%pret%') then
    alter table public.rh_caisse_mouvements drop constraint rh_caisse_mouvements_nature_check;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rh_caisse_mouvements_nature_check') then
    alter table public.rh_caisse_mouvements add constraint rh_caisse_mouvements_nature_check
      check (nature in ('apport_ceo', 'apport_autre', 'depense', 'salaire', 'pret',
                        'transfert', 'frais', 'ajustement'));
  end if;
end $$;

-- ---------- Le calendrier ----------
/** Aujourd'hui, à l'heure du Bénin. */
create or replace function public.rh_aujourdhui() returns date
language sql stable as $$
  select (now() at time zone 'Africa/Porto-Novo')::date;
$$;

/** Le jour où la paie d'un mois se verse : le 10 du mois suivant. */
create or replace function public.rh_date_versement(mois date) returns date
language sql immutable as $$
  select (date_trunc('month', mois) + interval '1 month 9 days')::date;
$$;

/** Le mois de la prochaine paie d'un employé : celui qu'une prime, une
    retenue ou un prêt accordé aujourd'hui touchera. C'est le mois écoulé
    tant que sa fiche n'est pas validée, sinon le mois en cours — jamais
    un mois d'avant son embauche. */
create or replace function public.rh_prochain_mois_paie(qui uuid) returns date
language plpgsql stable security definer set search_path = public as $$
declare
  depart date := (date_trunc('month', public.rh_aujourdhui()) - interval '1 month')::date;
  embauche date;
  m date;
begin
  select date_trunc('month', date_embauche)::date into embauche from public.rh_employes where id = qui;
  m := greatest(depart, coalesce(embauche, depart));
  while exists (select 1 from public.rh_fiches_paie f
                 where f.employe_id = qui and f.mois = m and f.statut <> 'calculee') loop
    m := (m + interval '1 month')::date;
  end loop;
  return m;
end $$;

-- ---------- Le solde ----------
/** Le solde d'un employé : la somme de ses mouvements. */
create or replace function public.rh_solde_de(qui uuid) returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce(sum(case when sens = 'credit' then montant else -montant end), 0)::bigint
    from public.rh_solde_mouvements where employe_id = qui;
$$;

/** Un mouvement sur le solde, l'employé verrouillé : deux retraits
    simultanés ne passent pas sur le même argent. Un retrait ne fait
    jamais passer le solde sous zéro. Interne. */
create or replace function public.rh_solde_mouvoir(qui uuid, p_sens text, p_nature text, p_montant bigint,
  p_libelle text, p_fiche uuid default null, p_retrait uuid default null)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  dispo bigint;
  ligne bigint;
begin
  if p_montant is null or p_montant <= 0 then
    raise exception 'Le montant doit être positif';
  end if;
  perform 1 from public.rh_employes where id = qui for update;
  dispo := public.rh_solde_de(qui);
  if p_sens = 'debit' and p_nature = 'retrait' and dispo < p_montant then
    raise exception 'Solde insuffisant : % FCFA disponibles, % FCFA demandés',
      replace(to_char(dispo, 'FM999G999G999G990'), ',', ' '), replace(to_char(p_montant, 'FM999G999G999G990'), ',', ' ');
  end if;
  insert into public.rh_solde_mouvements (employe_id, sens, nature, montant, libelle, fiche_id, retrait_id, par, solde)
  values (qui, p_sens, p_nature, p_montant, left(btrim(coalesce(p_libelle, '')), 300), p_fiche, p_retrait,
          public.rh_moi(), dispo + case when p_sens = 'credit' then p_montant else -p_montant end)
  returning id into ligne;
  return ligne;
end $$;

-- ---------- Le versement du 10 ----------
/** Verse une fiche validée sur le solde de son employé, si son jour est
    venu. Rend vrai si elle a été versée. Interne. */
create or replace function public.rh_crediter_fiche(fiche uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  f public.rh_fiches_paie;
begin
  select * into f from public.rh_fiches_paie where id = fiche for update;
  if not found or f.statut <> 'validee' or public.rh_aujourdhui() < public.rh_date_versement(f.mois) then
    return false;
  end if;
  update public.rh_fiches_paie
     set statut = 'payee', paye_le = now(), paye_par = null, mode_paiement = 'solde', reference = ''
   where id = fiche;
  /* Une fiche négative (des retenues plus fortes que le salaire) laisse
     une dette sur le solde : elle se reprend sur les versements suivants. */
  if f.net <> 0 then
    perform public.rh_solde_mouvoir(f.employe_id, case when f.net > 0 then 'credit' else 'debit' end,
      'salaire', abs(f.net), 'Salaire de ' || to_char(f.mois, 'MM/YYYY'), f.id, null);
  end if;
  return true;
end $$;

/** Toutes les fiches validées dont le 10 est passé. pg_cron l'appelle
    chaque matin ; c'est sans effet sur ce qui est déjà versé. */
create or replace function public.rh_crediter_salaires() returns int
language plpgsql security definer set search_path = public as $$
declare
  f record;
  combien int := 0;
begin
  for f in select id from public.rh_fiches_paie
            where statut = 'validee' and public.rh_date_versement(mois) <= public.rh_aujourdhui()
            order by mois, id loop
    if public.rh_crediter_fiche(f.id) then
      combien := combien + 1;
    end if;
  end loop;
  return combien;
end $$;

/* Une fiche validée après le 10 n'attend pas le mois suivant. */
create or replace function public.rh_fiche_validee_versee() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.statut = 'validee' and old.statut is distinct from 'validee' then
    perform public.rh_crediter_fiche(new.id);
  end if;
  return null;
end $$;
drop trigger if exists rh_fiche_validee_versee on public.rh_fiches_paie;
create trigger rh_fiche_validee_versee after update of statut on public.rh_fiches_paie
  for each row execute function public.rh_fiche_validee_versee();

-- ---------- Primes et retenues du CEO ----------
/** Le CEO (ou le superadministrateur) accorde une prime ou impose une
    retenue : elle s'inscrit sur la prochaine paie de l'employé. Rend le
    mois touché. */
create or replace function public.rh_octroyer(qui uuid, nature text, montant bigint, libelle text)
returns date
language plpgsql security definer set search_path = public as $$
declare
  m date;
begin
  if not (public.rh_est_ceo() or public.est_super()) then
    raise exception 'Seul le CEO accorde une prime ou impose une retenue';
  end if;
  if nature not in ('prime', 'retenue') then
    raise exception 'Une prime ou une retenue';
  end if;
  if coalesce(montant, 0) <= 0 then
    raise exception 'Le montant doit être positif';
  end if;
  if length(btrim(coalesce(libelle, ''))) < 3 then
    raise exception 'Dites pourquoi (le libellé figure sur la fiche de paie)';
  end if;
  if not exists (select 1 from public.rh_employes where id = qui and etat in ('actif', 'bloque')) then
    raise exception 'Cet employé n''est pas en poste';
  end if;
  m := public.rh_prochain_mois_paie(qui);
  insert into public.rh_elements_paie (employe_id, mois, nature, libelle, montant, imposable)
  values (qui, m, nature, btrim(libelle), montant, nature = 'prime');
  return m;
end $$;

/** Retirer une prime ou une retenue que la paie n'a pas encore validée. */
create or replace function public.rh_retirer_element(element uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.rh_est_ceo() or public.est_super()) then
    raise exception 'Seul le CEO retire une prime ou une retenue';
  end if;
  delete from public.rh_elements_paie where id = element;
  if not found then
    raise exception 'Élément introuvable';
  end if;
end $$;

-- ---------- Les prêts ----------
/** L'employé demande un prêt : le CEO le validera, la caisse le
    décaissera, la paie suivante le reprendra en une fois. */
create or replace function public.rh_demander_pret(montant bigint, motif text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_moi uuid := public.rh_moi();
  nouveau uuid;
begin
  if v_moi is null then
    raise exception 'Seul un employé en poste demande un prêt';
  end if;
  if coalesce(montant, 0) <= 0 then
    raise exception 'Le montant doit être positif';
  end if;
  if length(btrim(coalesce(motif, ''))) < 3 then
    raise exception 'Dites pourquoi vous demandez ce prêt';
  end if;
  if exists (select 1 from public.rh_avances where employe_id = v_moi and statut in ('demandee', 'validee')) then
    raise exception 'Vous avez déjà un prêt en attente : attendez qu''il soit décaissé ou refusé';
  end if;
  insert into public.rh_avances (employe_id, montant, mensualites, premier_mois, motif, statut)
  values (v_moi, montant, 1, public.rh_prochain_mois_paie(v_moi), btrim(motif), 'demandee')
  returning id into nouveau;
  return nouveau;
end $$;

/** L'employé retire sa demande, tant que le CEO ne l'a pas tranchée. */
create or replace function public.rh_annuler_pret(pret uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('rh.decision', 'oui', true);
  update public.rh_avances set statut = 'annulee'
   where id = pret and employe_id = public.rh_moi() and statut = 'demandee';
  if not found then
    raise exception 'Seule votre demande encore en attente du CEO s''annule';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

/** Le CEO valide ou refuse une demande de prêt. */
create or replace function public.rh_decider_pret(pret uuid, accepter boolean, raison text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.rh_est_ceo() or public.est_super()) then
    raise exception 'Seul le CEO valide un prêt';
  end if;
  if not accepter and length(btrim(coalesce(raison, ''))) < 3 then
    raise exception 'Dites pourquoi vous refusez ce prêt';
  end if;
  perform set_config('rh.decision', 'oui', true);
  update public.rh_avances
     set statut = case when accepter then 'validee' else 'refusee' end,
         valide_par = public.rh_moi(), valide_le = now(),
         motif_refus = case when accepter then '' else btrim(raison) end
   where id = pret and statut = 'demandee';
  if not found then
    raise exception 'Seule une demande de prêt en attente se tranche';
  end if;
  perform set_config('rh.decision', '', true);
end $$;

/** Le gestionnaire de la caisse décaisse un prêt validé, réparti entre
    les compartiments ; il ne décaisse pas son propre prêt. Le prêt
    s'inscrit alors sur la prochaine paie de l'employé. */
create or replace function public.rh_decaisser_pret(pret uuid, repartition jsonb, reference text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare
  a public.rh_avances;
  rep jsonb;
  k text;
  v jsonb;
  qui_nom text;
begin
  if public.rh_caisse_acces() is distinct from 'gestion' then
    raise exception 'Seul le gestionnaire de la caisse décaisse un prêt';
  end if;
  select * into a from public.rh_avances where id = pret for update;
  if not found or a.statut <> 'validee' then
    raise exception 'Seul un prêt validé par le CEO se décaisse';
  end if;
  if a.employe_id = public.rh_moi() then
    raise exception 'Vous ne décaissez pas votre propre prêt : le CEO désigne quelqu''un d''autre';
  end if;
  rep := public.rh_caisse_repartition(repartition, a.montant);
  select btrim(e.prenoms || ' ' || e.nom) into qui_nom from public.rh_employes e where e.id = a.employe_id;
  for k, v in select e.key, e.value from jsonb_each(rep) as e order by e.key loop
    perform public.rh_caisse_mouvoir(k, 'sortie', 'pret', (v #>> '{}')::bigint,
      'Prêt du ' || to_char(public.rh_aujourdhui(), 'DD/MM/YYYY') || ' · ' || qui_nom, reference);
  end loop;
  /* Le prêt devient une avance active : la prochaine fiche le reprend
     (le déclencheur des avances la recalcule). */
  update public.rh_avances
     set statut = 'active', date_avance = public.rh_aujourdhui(),
         premier_mois = public.rh_prochain_mois_paie(a.employe_id),
         decaisse_par = public.rh_moi(), decaisse_le = now(),
         reference_caisse = left(btrim(coalesce(rh_decaisser_pret.reference, '')), 120)
   where id = pret;
end $$;

-- ---------- Les retraits ----------
/** Le numéro national à dix chiffres (01 + 8), ou une erreur. */
create or replace function public.rh_numero_national(tel text) returns text
language plpgsql immutable as $$
declare
  n text := regexp_replace(coalesce(tel, ''), '[^0-9]', '', 'g');
begin
  if length(n) = 13 and n like '229%' then
    n := right(n, 10);
  end if;
  if length(n) = 8 then
    n := '01' || n;
  end if;
  if length(n) <> 10 or n !~ '^01[0-9]{8}' then
    raise exception 'Numéro de téléphone : 01 suivi de 8 chiffres';
  end if;
  return n;
end $$;

/** L'employé demande un retrait de son solde : par Mobile Money
    (FeexPay) ou à la caisse. Le montant quitte aussitôt son solde ; il
    y revient si le retrait est refusé, annulé ou échoue. */
create or replace function public.rh_demander_retrait(montant bigint, moyen text, reseau text default null,
  telephone text default '')
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_moi uuid := public.rh_moi();
  nouveau uuid;
  num bigint;
  tel text := '';
begin
  if v_moi is null then
    raise exception 'Seul un employé en poste retire de son solde';
  end if;
  if coalesce(montant, 0) <= 0 then
    raise exception 'Le montant doit être positif';
  end if;
  if moyen not in ('feexpay', 'caisse') then
    raise exception 'Choisissez : Mobile Money ou la caisse';
  end if;
  if moyen = 'feexpay' then
    if reseau not in ('mtn', 'moov', 'celtiis') then
      raise exception 'Choisissez le réseau : MTN, Moov ou Celtiis';
    end if;
    -- FeexPay ne reverse pas moins de 50 francs.
    if montant < 50 then
      raise exception 'Un retrait Mobile Money fait au moins 50 FCFA';
    end if;
    tel := public.rh_numero_national(telephone);
  end if;
  insert into public.rh_retraits (employe_id, montant, moyen, reseau, telephone)
  values (v_moi, montant, moyen, case when moyen = 'feexpay' then reseau end, tel)
  returning id, numero into nouveau, num;
  perform public.rh_solde_mouvoir(v_moi, 'debit', 'retrait', montant,
    'Retrait R-' || lpad(num::text, 4, '0') || case when moyen = 'feexpay' then ' (Mobile Money)' else ' (caisse)' end,
    null, nouveau);
  return nouveau;
end $$;

/** Le montant d'un retrait qui n'a pas abouti revient sur le solde. Interne. */
create or replace function public.rh_retrait_rendre(r public.rh_retraits, pourquoi text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.rh_solde_mouvoir(r.employe_id, 'credit', 'retour', r.montant,
    'Retour du retrait R-' || lpad(r.numero::text, 4, '0') || ' · ' || pourquoi, null, r.id);
end $$;

/** L'employé annule son retrait tant que personne ne l'a traité. */
create or replace function public.rh_annuler_retrait(retrait uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  r public.rh_retraits;
begin
  update public.rh_retraits set statut = 'annule', conclu_le = now()
   where id = retrait and employe_id = public.rh_moi() and statut = 'demande'
  returning * into r;
  if r.id is null then
    raise exception 'Seul votre retrait encore en attente s''annule';
  end if;
  perform public.rh_retrait_rendre(r, 'annulé');
end $$;

/** Le gestionnaire de la caisse (ou le CEO) refuse un retrait, avec un motif. */
create or replace function public.rh_refuser_retrait(retrait uuid, raison text) returns void
language plpgsql security definer set search_path = public as $$
declare
  r public.rh_retraits;
begin
  if public.rh_caisse_acces() not in ('gestion', 'ceo', 'super') or public.rh_caisse_acces() is null then
    raise exception 'Seuls le gestionnaire de la caisse et le CEO refusent un retrait';
  end if;
  if length(btrim(coalesce(raison, ''))) < 3 then
    raise exception 'Dites pourquoi vous refusez ce retrait';
  end if;
  update public.rh_retraits
     set statut = 'refuse', motif = btrim(raison), traite_par = public.rh_moi(), traite_le = now(), conclu_le = now()
   where id = retrait and statut = 'demande'
  returning * into r;
  if r.id is null then
    raise exception 'Seul un retrait en attente se refuse';
  end if;
  perform public.rh_retrait_rendre(r, 'refusé');
end $$;

/** Le gestionnaire remet l'argent à la caisse, réparti entre les
    compartiments. Il peut servir ainsi un retrait demandé en Mobile
    Money (en l'envoyant lui-même depuis le compartiment MTN, par
    exemple). Il ne sert pas son propre retrait. */
create or replace function public.rh_servir_retrait(retrait uuid, repartition jsonb, reference text default '')
returns void
language plpgsql security definer set search_path = public as $$
declare
  r public.rh_retraits;
  rep jsonb;
  k text;
  v jsonb;
  qui_nom text;
begin
  if public.rh_caisse_acces() is distinct from 'gestion' then
    raise exception 'Seul le gestionnaire de la caisse sert un retrait';
  end if;
  select * into r from public.rh_retraits where id = retrait for update;
  if not found or r.statut <> 'demande' then
    raise exception 'Seul un retrait en attente se sert';
  end if;
  if r.employe_id = public.rh_moi() then
    raise exception 'Vous ne servez pas votre propre retrait : le CEO désigne quelqu''un d''autre';
  end if;
  rep := public.rh_caisse_repartition(repartition, r.montant);
  select btrim(e.prenoms || ' ' || e.nom) into qui_nom from public.rh_employes e where e.id = r.employe_id;
  for k, v in select e.key, e.value from jsonb_each(rep) as e order by e.key loop
    perform public.rh_caisse_mouvoir(k, 'sortie', 'salaire', (v #>> '{}')::bigint,
      'Retrait de salaire R-' || lpad(r.numero::text, 4, '0') || ' · ' || qui_nom, reference);
  end loop;
  update public.rh_retraits
     set statut = 'paye', moyen = 'caisse', reference = left(btrim(coalesce(rh_servir_retrait.reference, '')), 120),
         traite_par = public.rh_moi(), traite_le = now(), conclu_le = now()
   where id = retrait;
end $$;

/** Le gestionnaire lance le reversement FeexPay d'un retrait. Appelée
    par la fonction Edge « rh-reversement » AVEC LE JETON DU
    GESTIONNAIRE : c'est la base qui vérifie son droit. Le retrait passe
    à « envoi » d'un coup : deux clics ne font pas deux virements. Rend
    ce que la fonction envoie à FeexPay — le montant vient d'ici. */
create or replace function public.rh_retrait_preparer(retrait uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r public.rh_retraits;
begin
  if public.rh_caisse_acces() is distinct from 'gestion' then
    raise exception 'Seul le gestionnaire de la caisse lance un reversement';
  end if;
  select * into r from public.rh_retraits where id = retrait;
  if found and r.employe_id = public.rh_moi() then
    raise exception 'Vous ne servez pas votre propre retrait : le CEO désigne quelqu''un d''autre';
  end if;
  update public.rh_retraits
     set statut = 'envoi', traite_par = public.rh_moi(), traite_le = now()
   where id = retrait and statut = 'demande' and moyen = 'feexpay'
  returning * into r;
  if r.id is null then
    raise exception 'Seul un retrait Mobile Money en attente se reverse';
  end if;
  return jsonb_build_object('id', r.id, 'numero', r.numero, 'montant', r.montant,
    'reseau', r.reseau, 'telephone', r.telephone);
end $$;

/** Ce que la fonction Edge a constaté chez FeexPay. Service seulement :
    aucun compte ne s'écrit « payé ». Les passages permis :
      envoi → demande (rien n'est parti), envoye (référence), incertain, echoue ;
      envoye / incertain → paye, echoue. */
create or replace function public.rh_retrait_resultat(retrait uuid, issue text, reference text default '',
  trace jsonb default '{}'::jsonb)
returns text
language plpgsql security definer set search_path = public as $$
declare
  r public.rh_retraits;
begin
  select * into r from public.rh_retraits where id = retrait for update;
  if not found then
    raise exception 'Retrait introuvable';
  end if;
  if not ((r.statut = 'envoi' and issue in ('demande', 'envoye', 'incertain', 'echoue'))
          or (r.statut in ('envoye', 'incertain') and issue in ('paye', 'echoue'))) then
    -- Déjà conclu, ou passage interdit : on ne change rien.
    update public.rh_retraits set journal = journal || jsonb_build_array(jsonb_build_object(
        'le', now(), 'ignore', issue, 'trace', coalesce(trace, '{}'::jsonb)))
     where id = retrait;
    return r.statut;
  end if;
  update public.rh_retraits
     set statut = issue,
         reference = case when coalesce(btrim(rh_retrait_resultat.reference), '') <> ''
                          then left(btrim(rh_retrait_resultat.reference), 120) else r.reference end,
         traite_par = case when issue = 'demande' then null else r.traite_par end,
         traite_le = case when issue = 'demande' then null else r.traite_le end,
         conclu_le = case when issue in ('paye', 'echoue') then now() else null end,
         journal = journal || jsonb_build_array(jsonb_build_object(
           'le', now(), 'issue', issue, 'trace', coalesce(trace, '{}'::jsonb)))
   where id = retrait;
  if issue = 'echoue' then
    perform public.rh_retrait_rendre(r, 'reversement échoué');
  end if;
  return issue;
end $$;

/** Les reversements à revérifier chez FeexPay. Service seulement. */
create or replace function public.rh_retraits_a_verifier() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'reference', reference, 'montant', montant)), '[]')
    from public.rh_retraits
   where statut in ('envoye', 'incertain') and reference <> '';
$$;

/** Le CEO tranche un reversement incertain (ou bloqué en envoi depuis
    plus de 10 minutes), après avoir regardé le tableau de bord FeexPay :
    payé, ou rien n'est parti (le montant revient alors sur le solde). */
create or replace function public.rh_retrait_trancher(retrait uuid, paye boolean, constat text) returns void
language plpgsql security definer set search_path = public as $$
declare
  r public.rh_retraits;
begin
  if not (public.rh_est_ceo() or public.est_super()) then
    raise exception 'Seul le CEO tranche un reversement incertain';
  end if;
  if length(btrim(coalesce(constat, ''))) < 3 then
    raise exception 'Dites ce que vous avez constaté chez FeexPay';
  end if;
  select * into r from public.rh_retraits where id = retrait for update;
  if not found or not (r.statut = 'incertain' or (r.statut = 'envoi' and r.traite_le < now() - interval '10 minutes')) then
    raise exception 'Seul un reversement incertain se tranche';
  end if;
  update public.rh_retraits
     set statut = case when paye then 'paye' else 'echoue' end, motif = btrim(constat), conclu_le = now(),
         journal = journal || jsonb_build_array(jsonb_build_object('le', now(), 'tranche_par', public.rh_moi(),
           'paye', paye, 'motif', btrim(constat)))
   where id = retrait;
  if not paye then
    perform public.rh_retrait_rendre(r, 'reversement non parti');
  end if;
end $$;

-- ---------- Ce que chacun lit ----------
/** Le compte d'un employé : son solde, ses mouvements, ses retraits, ses
    prêts, et ce qui attend sa prochaine paie. L'employé lit le sien ;
    le CEO et le superadministrateur, celui de chacun. */
create or replace function public.rh_compte_employe(qui uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  cible uuid := coalesce(qui, public.rh_moi());
  prochain date;
begin
  if cible is null then
    raise exception 'Seul un employé en poste a un solde';
  end if;
  if cible is distinct from public.rh_moi() and not (public.rh_est_ceo() or public.est_super()) then
    raise exception 'Vous ne lisez que votre propre solde';
  end if;
  prochain := public.rh_prochain_mois_paie(cible);
  return jsonb_build_object(
    'employe_id', cible,
    'solde', public.rh_solde_de(cible),
    'telephone', (select telephone from public.rh_employes where id = cible),
    'prochain_mois', prochain,
    'prochain_versement', public.rh_date_versement(prochain),
    'mouvements', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'le', m.le, 'sens', m.sens,
        'nature', m.nature, 'montant', m.montant, 'libelle', m.libelle, 'solde', m.solde) order by m.id desc), '[]')
      from (select * from public.rh_solde_mouvements where employe_id = cible order by id desc limit 100) m),
    'retraits', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'numero', r.numero, 'montant', r.montant,
        'moyen', r.moyen, 'reseau', r.reseau, 'telephone', r.telephone, 'statut', r.statut, 'motif', r.motif,
        'demande_le', r.demande_le, 'conclu_le', r.conclu_le) order by r.demande_le desc), '[]')
      from (select * from public.rh_retraits where employe_id = cible order by demande_le desc limit 50) r),
    'prets', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'montant', a.montant, 'motif', a.motif,
        'statut', a.statut, 'motif_refus', a.motif_refus, 'cree_le', a.cree_le, 'premier_mois', a.premier_mois,
        'decaisse_le', a.decaisse_le,
        'reste', a.montant - coalesce((select sum(fa.montant) from public.rh_fiche_avances fa
                                         join public.rh_fiches_paie f on f.id = fa.fiche_id
                                        where fa.avance_id = a.id and f.statut <> 'calculee'), 0))
        order by a.cree_le desc), '[]')
      from (select * from public.rh_avances where employe_id = cible and statut <> 'annulee'
             order by cree_le desc limit 50) a),
    'elements', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'mois', x.mois, 'nature', x.nature,
        'libelle', x.libelle, 'montant', x.montant) order by x.mois, x.cree_le), '[]')
      from public.rh_elements_paie x where x.employe_id = cible and x.mois >= prochain));
end $$;

/** Les prêts et les retraits à traiter : le CEO valide les prêts et
    tranche les reversements incertains ; le gestionnaire décaisse les
    prêts et sert les retraits. Le CEO et le superadministrateur voient
    aussi le solde de chacun. */
create or replace function public.rh_prets_retraits() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  acces text := public.rh_caisse_acces();
  chef boolean := public.rh_est_ceo() or public.est_super();
begin
  if not chef and acces is distinct from 'gestion' then
    raise exception 'Réservé au CEO et au gestionnaire de la caisse';
  end if;
  return jsonb_build_object(
    'gestion', acces = 'gestion',
    'chef', chef,
    'moi', public.rh_moi(),
    'prets', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'employe_id', a.employe_id,
        'nom', btrim(e.prenoms || ' ' || e.nom), 'montant', a.montant, 'motif', a.motif, 'statut', a.statut,
        'cree_le', a.cree_le, 'valide_le', a.valide_le) order by a.cree_le), '[]')
      from public.rh_avances a join public.rh_employes e on e.id = a.employe_id
     where a.statut in ('demandee', 'validee')),
    'retraits', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'numero', r.numero,
        'employe_id', r.employe_id, 'nom', btrim(e.prenoms || ' ' || e.nom), 'montant', r.montant,
        'moyen', r.moyen, 'reseau', r.reseau, 'telephone', r.telephone,
        'telephone_fiche', e.telephone, 'statut', r.statut, 'motif', r.motif, 'reference', r.reference,
        'demande_le', r.demande_le, 'traite_le', r.traite_le, 'conclu_le', r.conclu_le) order by r.demande_le desc), '[]')
      from (select * from public.rh_retraits
             where statut in ('demande', 'envoi', 'envoye', 'incertain')
                or conclu_le > now() - interval '30 days') r
      join public.rh_employes e on e.id = r.employe_id),
    'soldes', case when chef then (select coalesce(jsonb_agg(jsonb_build_object('employe_id', e.id,
        'nom', btrim(e.prenoms || ' ' || e.nom), 'solde', public.rh_solde_de(e.id)) order by e.nom, e.prenoms), '[]')
      from public.rh_employes e where e.etat in ('actif', 'bloque')
         or exists (select 1 from public.rh_solde_mouvements m where m.employe_id = e.id)) end);
end $$;

/** Les pastilles du menu « Prêts et retraits ». */
create or replace function public.rh_compteurs_solde() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  acces text := public.rh_caisse_acces();
  chef boolean := public.rh_est_ceo() or public.est_super();
  v_moi uuid := public.rh_moi();
begin
  return jsonb_build_object(
    'menu', chef or acces = 'gestion',
    'prets_a_valider', case when chef then (select count(*) from public.rh_avances where statut = 'demandee') else 0 end,
    'prets_a_decaisser', case when acces = 'gestion' then
      (select count(*) from public.rh_avances where statut = 'validee' and employe_id is distinct from v_moi) else 0 end,
    'retraits_a_servir', case when acces = 'gestion' then
      (select count(*) from public.rh_retraits where statut = 'demande' and employe_id is distinct from v_moi) else 0 end,
    'retraits_incertains', case when chef then
      (select count(*) from public.rh_retraits where statut = 'incertain'
          or (statut = 'envoi' and traite_le < now() - interval '10 minutes')) else 0 end);
end $$;

create or replace function public.rh_moi() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_est_ceo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.rh_employes
                  where compte_id = auth.uid() and etat = 'actif' and ceo);
$$;

create or replace function public.rh_caisse_acces() returns text
language plpgsql stable security definer set search_path = public as $$
declare
  v_moi uuid := public.rh_moi();
begin
  if v_moi is not null and exists (select 1 from public.rh_caisse where gestionnaire_id = v_moi) then
    return 'gestion';
  end if;
  if public.rh_est_ceo() then
    return 'ceo';
  end if;
  if public.est_super() then
    return 'super';
  end if;
  if v_moi is not null and exists (
       select 1 from public.rh_acces_menus a join public.rh_profils p on p.id = a.profil_id
        where a.menu = 'caisse'
          and (p.responsable_id = v_moi or (a.qui = 'membres' and p.id = public.rh_mon_profil()))) then
    return 'consultation';
  end if;
  return null;
end $$;

create or replace function public.rh_caisse_mouvoir(p_compte text, p_sens text, p_nature text,
  p_montant bigint, p_libelle text, p_reference text default '', p_depense uuid default null,
  p_fiche uuid default null)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  dispo bigint;
  total bigint;
  nouveau bigint;
  ligne bigint;
begin
  if p_montant is null or p_montant <= 0 then
    raise exception 'Le montant doit être positif';
  end if;
  perform 1 from public.rh_caisse where id for update;
  select coalesce(sum(case when sens = 'entree' then montant else -montant end), 0) into dispo
    from public.rh_caisse_mouvements where compte = p_compte;
  select coalesce(sum(case when sens = 'entree' then montant else -montant end), 0) into total
    from public.rh_caisse_mouvements;
  if p_sens = 'sortie' and dispo < p_montant then
    raise exception 'Solde insuffisant en % : % FCFA disponibles, % FCFA demandés',
      case p_compte when 'especes' then 'espèces' when 'mtn' then 'MTN Mobile Money'
                    when 'moov' then 'Moov Money' else 'Celtiis Cash' end,
      replace(to_char(dispo, 'FM999G999G999G990'), ',', ' '), replace(to_char(p_montant, 'FM999G999G999G990'), ',', ' ');
  end if;
  nouveau := dispo + case when p_sens = 'entree' then p_montant else -p_montant end;
  insert into public.rh_caisse_mouvements (compte, sens, nature, montant, libelle, reference,
                                           depense_id, fiche_id, par, solde_compte, solde_total)
  values (p_compte, p_sens, p_nature, p_montant, left(btrim(coalesce(p_libelle, '')), 300),
          left(btrim(coalesce(p_reference, '')), 120), p_depense, p_fiche, public.rh_moi(), nouveau,
          total + case when p_sens = 'entree' then p_montant else -p_montant end)
  returning id into ligne;
  return ligne;
end $$;

create or replace function public.rh_caisse_repartition(brut jsonb, montant bigint) returns jsonb
language plpgsql immutable as $$
declare
  k text;
  v jsonb;
  somme bigint := 0;
  propre jsonb := '{}'::jsonb;
begin
  if brut is null or jsonb_typeof(brut) <> 'object' then
    raise exception 'Indiquez d''où sort l''argent : espèces, MTN, Moov ou Celtiis';
  end if;
  for k, v in select e.key, e.value from jsonb_each(brut) as e loop
    if k not in ('especes', 'mtn', 'moov', 'celtiis') then
      raise exception 'Compartiment de caisse inconnu : %', k;
    end if;
    if jsonb_typeof(v) <> 'number' or (v #>> '{}')::numeric <> round((v #>> '{}')::numeric) or (v #>> '{}')::numeric < 0 then
      raise exception 'Un montant en francs entiers, positif, pour %', k;
    end if;
    if (v #>> '{}')::bigint > 0 then
      propre := propre || jsonb_build_object(k, (v #>> '{}')::bigint);
      somme := somme + (v #>> '{}')::bigint;
    end if;
  end loop;
  if somme <> montant then
    raise exception 'La répartition fait % FCFA, pour un montant de % FCFA : elle doit tomber juste',
      replace(to_char(somme, 'FM999G999G999G990'), ',', ' '), replace(to_char(montant, 'FM999G999G999G990'), ',', ' ');
  end if;
  return propre;
end $$;

create or replace function public.rh_generer_paie_interne(mois date) returns int
language plpgsql security definer set search_path = public as $$
declare
  debut date := date_trunc('month', mois)::date;
  fin date := (date_trunc('month', mois) + interval '1 month - 1 day')::date;
  e record;
  combien int := 0;
begin
  for e in select id from public.rh_employes
            where (etat in ('actif', 'bloque') or (etat = 'sorti' and date_sortie >= debut))
              and date_embauche <= fin loop
    if public.rh_calculer_fiche(e.id, debut) is not null then
      combien := combien + 1;
    end if;
  end loop;
  /* Un employé qui n'est plus à payer ce mois-là perd sa fiche non validée. */
  delete from public.rh_fiches_paie f
   where f.mois = debut and f.statut = 'calculee'
     and not exists (select 1 from public.rh_employes x
                      where x.id = f.employe_id
                        and (x.etat in ('actif', 'bloque') or (x.etat = 'sorti' and x.date_sortie >= debut))
                        and x.date_embauche <= fin);
  return combien;
end $$;

create or replace function public.rh_mon_profil() returns uuid
language sql stable security definer set search_path = public as $$
  select profil_id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

create or replace function public.rh_calculer_fiche(qui uuid, quand date) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  e public.rh_employes;
  debut date := date_trunc('month', quand)::date;
  fin date := (date_trunc('month', quand) + interval '1 month - 1 day')::date;
  jours int;
  d1 date;
  d2 date;
  payes int;
  du bigint;
  lignes jsonb := '[]'::jsonb;
  el record;
  c record;
  a record;
  primes bigint := 0;
  imposable bigint;
  brut bigint;
  cot_sal bigint := 0;
  cot_pat bigint := 0;
  assiette bigint;
  part bigint;
  reglage public.rh_reglages_paie;
  base_impot bigint;
  impot bigint := 0;
  retenues bigint := 0;
  avances bigint := 0;
  reste bigint;
  disponible bigint;
  prise bigint;
  existante public.rh_fiches_paie;
  fiche uuid;
  prises jsonb := '[]'::jsonb;
begin
  jours := fin - debut + 1;
  select * into e from public.rh_employes where id = qui;
  if not found then
    return null;
  end if;
  select * into existante from public.rh_fiches_paie f
   where f.employe_id = qui and f.mois = debut;
  if found and existante.statut <> 'calculee' then
    return existante.id;
  end if;

  /* Payé du jour d'embauche au jour de sortie, au prorata des jours
     calendaires du mois. */
  d1 := greatest(debut, e.date_embauche);
  d2 := least(fin, coalesce(e.date_sortie, fin));
  if e.etat not in ('actif', 'bloque', 'sorti') or d2 < d1 then
    delete from public.rh_fiches_paie f
     where f.employe_id = qui and f.mois = debut and f.statut = 'calculee';
    return null;
  end if;
  payes := d2 - d1 + 1;
  du := round(e.salaire_base::numeric * payes / jours);
  lignes := lignes || jsonb_build_object('genre', 'base', 'libelle',
    case when payes < jours then 'Salaire de base (' || payes || ' jours sur ' || jours || ')'
         else 'Salaire de base' end, 'montant', du);
  imposable := du;

  for el in select * from public.rh_elements_paie x
             where x.employe_id = qui and x.mois = debut and x.nature in ('prime', 'indemnite')
             order by x.cree_le loop
    primes := primes + el.montant;
    if el.imposable then
      imposable := imposable + el.montant;
    end if;
    lignes := lignes || jsonb_build_object('genre', el.nature, 'libelle', el.libelle,
                                           'montant', el.montant, 'imposable', el.imposable);
  end loop;
  brut := du + primes;

  for c in select * from public.rh_cotisations x
            where x.valide and x.actif and (e.statut = 'employe' or x.stagiaires)
            order by x.code loop
    assiette := least(imposable, coalesce(c.plafond, imposable));
    part := round(assiette * c.taux_salarie / 100);
    cot_sal := cot_sal + part;
    cot_pat := cot_pat + round(assiette * c.taux_employeur / 100);
    lignes := lignes || jsonb_build_object('genre', 'cotisation', 'code', c.code,
      'libelle', c.libelle, 'assiette', assiette, 'taux', c.taux_salarie,
      'montant', part, 'taux_employeur', c.taux_employeur,
      'employeur', round(assiette * c.taux_employeur / 100));
  end loop;

  select * into reglage from public.rh_reglages_paie where id;
  if reglage.impot_valide and (e.statut = 'employe' or reglage.impot_stagiaires) then
    base_impot := imposable - case when reglage.impot_sur = 'brut_moins_cotisations'
                                   then cot_sal else 0 end;
    select coalesce(sum(round((least(base_impot, coalesce(t.borne_sup, base_impot)) - t.borne_inf)
                              * t.taux / 100)), 0)
      into impot
      from public.rh_tranches_impot t
     where base_impot > t.borne_inf;
    lignes := lignes || jsonb_build_object('genre', 'impot', 'libelle', 'Impôt sur le salaire',
                                           'assiette', base_impot, 'montant', impot);
  end if;

  for el in select * from public.rh_elements_paie x
             where x.employe_id = qui and x.mois = debut and x.nature = 'retenue'
             order by x.cree_le loop
    retenues := retenues + el.montant;
    lignes := lignes || jsonb_build_object('genre', 'retenue', 'libelle', el.libelle,
                                           'montant', el.montant);
  end loop;

  /* Les avances passent en dernier, et jamais au-delà de ce qui reste :
     une fiche ne descend pas sous zéro à cause d'une avance — le reste
     attend la paie suivante. */
  disponible := greatest(0, brut - cot_sal - impot - retenues);
  for a in select * from public.rh_avances x
            where x.employe_id = qui and x.statut = 'active' and x.premier_mois <= debut
            order by x.date_avance, x.cree_le loop
    select a.montant - coalesce(sum(fa.montant), 0) into reste
      from public.rh_fiche_avances fa
      join public.rh_fiches_paie f on f.id = fa.fiche_id
     where fa.avance_id = a.id and f.mois <> debut;
    prise := least(reste, ceil(a.montant::numeric / a.mensualites)::bigint, disponible);
    if prise > 0 then
      avances := avances + prise;
      disponible := disponible - prise;
      prises := prises || jsonb_build_object('avance', a.id, 'montant', prise);
      lignes := lignes || jsonb_build_object('genre', 'avance', 'libelle',
        'Avance du ' || to_char(a.date_avance, 'DD/MM/YYYY') ||
        case when reste - prise > 0 then ' (reste ' || (reste - prise) || ' FCFA)' else ' (soldée)' end,
        'montant', prise);
    end if;
  end loop;

  insert into public.rh_fiches_paie as f (employe_id, mois, statut, jours_payes, jours_du_mois,
      salaire_base, salaire_du, primes, brut, brut_imposable, cotisations_salariales, impot,
      avances, retenues, net, charges_patronales, lignes, employe, calcule_le)
  values (qui, debut, 'calculee', payes, jours, e.salaire_base, du, primes, brut, imposable,
      cot_sal, impot, avances, retenues, brut - cot_sal - impot - retenues - avances, cot_pat,
      lignes,
      jsonb_build_object('matricule', e.matricule, 'nom', e.nom, 'prenoms', e.prenoms,
        'poste', e.poste, 'statut', e.statut, 'date_embauche', e.date_embauche,
        'numero_cnss', e.numero_cnss, 'mode_paiement', e.mode_paiement,
        'profil', (select p.nom from public.rh_profils p where p.id = e.profil_id)),
      now())
  on conflict on constraint rh_fiches_paie_employe_id_mois_key do update
     set jours_payes = excluded.jours_payes, jours_du_mois = excluded.jours_du_mois,
         salaire_base = excluded.salaire_base, salaire_du = excluded.salaire_du,
         primes = excluded.primes, brut = excluded.brut, brut_imposable = excluded.brut_imposable,
         cotisations_salariales = excluded.cotisations_salariales, impot = excluded.impot,
         avances = excluded.avances, retenues = excluded.retenues, net = excluded.net,
         charges_patronales = excluded.charges_patronales, lignes = excluded.lignes,
         employe = excluded.employe, calcule_le = now()
   where f.statut = 'calculee'
  returning f.id into fiche;

  delete from public.rh_fiche_avances where fiche_id = fiche;
  insert into public.rh_fiche_avances (fiche_id, avance_id, montant)
  select fiche, (x ->> 'avance')::uuid, (x ->> 'montant')::bigint
    from jsonb_array_elements(prises) x;
  return fiche;
end $$;

-- ---------- Ce qui change (copies de schema.sql) ----------

create or replace function public.rh_generer_paie_auto() returns int
language plpgsql security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  precedent date := (date_trunc('month', aujourdhui) - interval '1 month')::date;
begin
  if extract(day from aujourdhui) >= 5
     and not exists (select 1 from public.rh_fiches_paie where mois = precedent) then
    return public.rh_generer_paie_interne(precedent);
  end if;
  return 0;
end $$;

create or replace function public.rh_payer_fiche(fiche uuid, mode text, reference text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Un salaire ne se paie plus ici : la fiche validée est versée le 10 sur le solde de l''employé, qui le retire depuis son compte (Mobile Money ou caisse)';
end $$;

create or replace function public.rh_payer(fiche uuid, repartition jsonb, reference text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Un salaire ne se paie plus ici : la fiche validée est versée le 10 sur le solde de l''employé, qui le retire depuis son compte (Mobile Money ou caisse)';
end $$;

create or replace function public.rh_salaire_sort_de_caisse() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  rep jsonb;
  k text;
  v jsonb;
begin
  if new.statut <> 'payee' or old.statut = 'payee' then
    return null;
  end if;
  /* Versée sur le solde de l'employé : rien ne sort encore de la caisse.
     L'argent en sortira au retrait, s'il le retire à la caisse. */
  if new.mode_paiement = 'solde' then
    return null;
  end if;
  rep := nullif(current_setting('rh.repartition', true), '')::jsonb;
  if rep is null then
    if new.mode_paiement not in ('especes', 'mtn', 'moov', 'celtiis') then
      raise exception 'Un salaire sort de la caisse : espèces, MTN, Moov ou Celtiis';
    end if;
    rep := jsonb_build_object(new.mode_paiement, new.net);
  end if;
  rep := public.rh_caisse_repartition(rep, new.net);
  for k, v in select e.key, e.value from jsonb_each(rep) as e order by e.key loop
    perform public.rh_caisse_mouvoir(k, 'sortie', 'salaire', (v #>> '{}')::bigint,
      'Salaire de ' || to_char(new.mois, 'MM/YYYY'), new.reference, null, new.id);
  end loop;
  return null;
end $$;

create or replace function public.rh_caisse(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  acces text := public.rh_caisse_acces();
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  debut date := coalesce(depuis, date_trunc('month', aujourdhui)::date);
  fin date := coalesce(jusqu, aujourdhui);
  t1 timestamptz;
  t2 timestamptz;
begin
  if acces is null then
    raise exception 'Votre compte n''a pas accès à la caisse';
  end if;
  if fin < debut then
    raise exception 'La fin de la période précède son début';
  end if;
  t1 := debut::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (fin + 1)::timestamp at time zone 'Africa/Porto-Novo';
  return jsonb_build_object(
    'acces', acces,
    'periode', jsonb_build_object('depuis', debut, 'jusqu', fin),
    'gestionnaire', (select jsonb_build_object('id', e.id, 'nom', btrim(e.prenoms || ' ' || e.nom), 'le', c.designe_le)
                       from public.rh_caisse c join public.rh_employes e on e.id = c.gestionnaire_id),
    'comptes', (select jsonb_agg(jsonb_build_object(
        'compte', k.compte,
        'solde', coalesce((select sum(case when m.sens = 'entree' then m.montant else -m.montant end)
                             from public.rh_caisse_mouvements m where m.compte = k.compte), 0),
        'debut', coalesce((select sum(case when m.sens = 'entree' then m.montant else -m.montant end)
                             from public.rh_caisse_mouvements m where m.compte = k.compte and m.le < t1), 0),
        'entrees', coalesce((select sum(m.montant) from public.rh_caisse_mouvements m
                              where m.compte = k.compte and m.sens = 'entree' and m.le >= t1 and m.le < t2), 0),
        'sorties', coalesce((select sum(m.montant) from public.rh_caisse_mouvements m
                              where m.compte = k.compte and m.sens = 'sortie' and m.le >= t1 and m.le < t2), 0))
        order by k.n)
      from unnest(array['especes', 'mtn', 'moov', 'celtiis']) with ordinality as k(compte, n)),
    'mouvements', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', m.id, 'le', m.le, 'compte', m.compte, 'sens', m.sens, 'nature', m.nature, 'montant', m.montant,
        'libelle', case when acces = 'consultation' and m.nature in ('salaire', 'pret')
                          then split_part(m.libelle, ' · ', 1)
                        when m.nature = 'salaire' and m.fiche_id is not null
                          then m.libelle || coalesce(' · ' || (select f.employe ->> 'prenoms' || ' ' || (f.employe ->> 'nom')
                                                                 from public.rh_fiches_paie f where f.id = m.fiche_id), '')
                        else m.libelle end,
        'reference', m.reference, 'depense_id', m.depense_id,
        'par', (select btrim(e.prenoms || ' ' || e.nom) from public.rh_employes e where e.id = m.par),
        'solde_compte', m.solde_compte, 'solde_total', m.solde_total) order by m.id desc), '[]')
      from public.rh_caisse_mouvements m where m.le >= t1 and m.le < t2));
end $$;

-- ---------- Les droits ----------
alter table public.rh_solde_mouvements enable row level security;
alter table public.rh_retraits enable row level security;
-- Aucune règle : tout passe par les fonctions ci-dessus.
revoke all on table public.rh_solde_mouvements, public.rh_retraits from public, anon, authenticated;
grant all on table public.rh_solde_mouvements, public.rh_retraits to service_role;

do $$
declare f text;
begin
  foreach f in array array['rh_octroyer(uuid, text, bigint, text)', 'rh_retirer_element(uuid)',
                           'rh_demander_pret(bigint, text)', 'rh_annuler_pret(uuid)',
                           'rh_decider_pret(uuid, boolean, text)', 'rh_decaisser_pret(uuid, jsonb, text)',
                           'rh_demander_retrait(bigint, text, text, text)', 'rh_annuler_retrait(uuid)',
                           'rh_refuser_retrait(uuid, text)', 'rh_servir_retrait(uuid, jsonb, text)',
                           'rh_retrait_preparer(uuid)', 'rh_retrait_trancher(uuid, boolean, text)',
                           'rh_compte_employe(uuid)', 'rh_prets_retraits()', 'rh_compteurs_solde()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated, service_role', f);
  end loop;
  foreach f in array array['rh_retrait_resultat(uuid, text, text, jsonb)', 'rh_retraits_a_verifier()'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
  foreach f in array array['rh_solde_mouvoir(uuid, text, text, bigint, text, uuid, uuid)',
                           'rh_crediter_fiche(uuid)', 'rh_crediter_salaires()', 'rh_fiche_validee_versee()',
                           'rh_retrait_rendre(public.rh_retraits, text)', 'rh_solde_fige()',
                           'rh_solde_de(uuid)', 'rh_prochain_mois_paie(uuid)', 'rh_aujourdhui()',
                           'rh_date_versement(date)', 'rh_numero_national(text)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
end $$;

-- ---------- Le calendrier, tout seul ----------
-- Chaque matin à 7 h (heure du Bénin, 6 h UTC) : les fiches du mois
-- écoulé si l'on est le 5 ou après et qu'elles manquent, puis le
-- versement des fiches validées dont le 10 est passé. Toutes les
-- 10 minutes, s'il y a des reversements FeexPay en cours, la fonction
-- Edge va voir où ils en sont. Sans pg_cron, l'application rattrape la
-- paie à l'ouverture.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      perform cron.unschedule('rh-paie-fin-de-mois');
    exception when others then
      null;
    end;
    perform cron.schedule('rh-paie-quotidienne', '0 6 * * *',
      'select public.rh_generer_paie_auto(); select public.rh_crediter_salaires();');
    if exists (select 1 from pg_extension where extname = 'pg_net') then
      perform cron.schedule('rh-reversements-verifier', '*/10 * * * *',
        'select net.http_post(''https://rrwzegmrmvvkmzfoiitb.supabase.co/functions/v1/rh-reversement'', ''{"action":"verifier_tout"}''::jsonb, ''{}''::jsonb, ''{"Content-Type": "application/json"}''::jsonb, 60000) where exists (select 1 from public.rh_retraits where statut in (''envoye'', ''incertain'') and reference <> '''')');
    end if;
  end if;
exception when others then
  raise notice 'Calendrier de la paie non programmé (%), l''application la rattrapera', sqlerrm;
end $$;
