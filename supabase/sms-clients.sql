-- =========================================================
-- BIZZOO 3.70.0 — Le client prévenu à chaque étape
--
--   1. La notification de l'application client SONNE sur son téléphone,
--      application fermée (Android) : le push, jusqu'ici réservé à
--      BIZZOO Admin, part aussi vers l'application client pour les
--      notifications de l'acheteur (lien « #/commande/… »).
--   2. Les clients que la notification ne touche pas — sans compte,
--      venus de WhatsApp, iPhone ou navigateur — reçoivent un SMS aux
--      étapes choisies par le superadministrateur (3 au plus par
--      commande, 300 par jour). COUPÉ tant qu'il ne l'allume pas, dans
--      BIZZOO Admin → Réglages.
--   3. BIZZOO Personnel compte les SMS (Suivi → SMS).
--
-- DANS CET ORDRE :
--   0. Redéployer la fonction Edge « envoyer-push » (elle lit le nouveau
--      champ « application » : sans elle, la notification du client
--      partirait sur le canal des boutiques), et déployer
--      « envoyer-sms-commande » (--no-verify-jwt toutes les deux).
--   1. Coller ce fichier dans Supabase → SQL Editor → Run. Relançable.
--   2. update public.sms_reglages
--         set url = 'https://<projet>.supabase.co/functions/v1/envoyer-sms-commande';
-- =========================================================

-- Les colonnes que les déclencheurs lisent (déjà là sur une base en service).
alter table public.commande_lignes add column if not exists livreur_id uuid;
alter table public.commande_lignes add column if not exists recu_le timestamptz;

-- Empruntées par les fonctions plus bas, recopiées telles quelles.
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
create or replace function public.rh_suivi_acces() returns text
language sql stable security definer set search_path = public as $$
  select case
    when public.rh_est_admin() then 'admin'
    when public.rh_menu_ouvert('suivi') then 'responsable'
  end;
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
create or replace function public.rh_moi() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;
create or replace function public.rh_mon_profil() returns uuid
language sql stable security definer set search_path = public as $$
  select profil_id from public.rh_employes where compte_id = auth.uid() and etat = 'actif';
$$;

-- Ce que la fonction Edge envoie : la notification et les téléphones de
-- son destinataire — une seule fois. Réservé au serveur.
--
-- (3.70.0) L'APPLICATION QUI SONNE se lit dans le lien : « #/commande/… »
-- (au singulier) n'est écrit QUE pour l'acheteur — son reçu dans
-- l'application client. Tout le reste va à BIZZOO Admin. Le type ne
-- suffit pas : « commande_payee », « course_acceptee »… partent aussi
-- vers l'équipe, sous le même nom.
create or replace function public.push_a_envoyer(cible bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare n public.notifications%rowtype;
begin
  update public.notifications x set push_le = now()
   where x.id = cible and x.push_le is null and x.sonne
     and x.cree_le > now() - interval '1 hour'
  returning * into n;
  if not found then return null; end if;
  return jsonb_build_object(
    'id', n.id, 'type', n.type, 'titre', n.titre, 'corps', n.corps, 'lien', n.lien,
    'commande_id', n.commande_id,
    'application', case when coalesce(n.lien, '') like '#/commande/%' then 'client' else 'admin' end,
    'jetons', coalesce((select jsonb_agg(a.jeton order by a.maj_le desc)
                          from public.appareils_push a
                         where a.compte = n.destinataire
                           and a.application = case when coalesce(n.lien, '') like '#/commande/%'
                                                    then 'client' else 'admin' end), '[]'::jsonb));
end $$;
revoke all on function public.push_a_envoyer(bigint) from public, anon, authenticated;

-- LE DÉCLENCHEUR. Il ne fait qu'une demande, après la transaction ; il ne
-- bloque jamais l'écriture de la notification, quoi qu'il arrive.
create or replace function public.notification_pousse() returns trigger
language plpgsql security definer set search_path = public as $$
declare adresse text;
begin
  if not new.sonne then return null; end if;
  if to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then return null; end if;
  select r.url into adresse from public.push_reglage r where r.id = 1;
  if coalesce(adresse, '') = '' then return null; end if;
  if not exists (select 1 from public.appareils_push a
                  where a.compte = new.destinataire
                    and a.application = case when coalesce(new.lien, '') like '#/commande/%'
                                             then 'client' else 'admin' end) then
    return null;
  end if;
  begin
    perform net.http_post(adresse, jsonb_build_object('id', new.id),
      '{}'::jsonb, '{"Content-Type": "application/json"}'::jsonb, 10000);
  exception when others then
    raise warning 'notification_pousse(%) : %', new.id, sqlerrm;
  end;
  return null;
end $$;

-- (3.70.0) Un client déconnecté HORS LIGNE n'a pas pu retirer son
-- téléphone : à la prochaine ouverture, sans session, il le retire avec
-- le seul jeton — que seul ce téléphone connaît. Application client
-- seulement : un jeton d'équipe ne se retire pas ainsi.
create or replace function public.oublier_jeton_push(jeton text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  delete from public.appareils_push a
   where a.jeton = trim(coalesce(oublier_jeton_push.jeton, '')) and a.application = 'client';
  return found;
end $$;
revoke all on function public.oublier_jeton_push(text) from public;
grant execute on function public.oublier_jeton_push(text) to anon, authenticated;

-- =========================================================
-- (3.70.0) LE CLIENT PRÉVENU PAR SMS, application fermée
--
-- La notification de l'application ne touche que l'acheteur qui a un
-- compte ET l'application Android. Les autres — commande passée sans
-- compte, commande prise sur WhatsApp, iPhone ou navigateur — ne savent
-- rien tant qu'ils n'ouvrent pas leur reçu : ils sont absents quand le
-- livreur arrive, et l'équipe passe sa journée au téléphone.
--
-- Aux étapes que le superadministrateur choisit, la base écrit un SMS
-- dans « sms_commandes » — qui est à la fois la file d'attente, le
-- journal et le compteur — puis demande, par pg_net, à la fonction Edge
-- « envoyer-sms-commande » de le faire partir. Comme pour le push, la
-- fonction ne croit que le numéro de la ligne : le texte et le
-- destinataire viennent de la base, qui marque l'envoi au passage.
--
-- UN SMS COÛTE DE L'ARGENT. D'où : coupé tant que le superadministrateur
-- ne l'allume pas ; un plafond par commande (3) et par jour (300) ; rien
-- pour une commande payée avant l'allumage (une migration rejouée, une
-- mise à jour en masse ne réveillent pas le passé) ; une étape ne part
-- qu'une fois par commande.
-- =========================================================
create table if not exists public.sms_reglages (
  id            int primary key default 1 check (id = 1),
  actif         boolean not null default false,
  plafond       int not null default 3 check (plafond between 0 and 10),
  plafond_jour  int not null default 300 check (plafond_jour between 0 and 5000),
  etapes        text[] not null default array['commande_payee', 'course_acceptee', 'commande_remise']
                check (etapes <@ array['commande_payee', 'course_acceptee', 'commande_en_livraison',
                                       'commande_remise', 'commande_annulee']),
  -- Qui reçoit : sans compte ; venu de WhatsApp ; avec un compte mais
  -- sans l'application Android (iPhone, navigateur).
  sans_compte   boolean not null default true,
  whatsapp      boolean not null default true,
  sans_appareil boolean not null default true,
  actif_depuis  timestamptz,
  -- L'adresse de la fonction Edge : posée depuis l'éditeur SQL, comme
  -- celle du push. Jamais par l'application.
  url           text not null default '' check (url = '' or url ~ '^https://'),
  maj_le        timestamptz not null default now(),
  maj_par       uuid
);
insert into public.sms_reglages (id) values (1) on conflict (id) do nothing;
alter table public.sms_reglages enable row level security;
revoke all on table public.sms_reglages from public, anon, authenticated;
grant all on table public.sms_reglages to service_role;

create table if not exists public.sms_commandes (
  id           bigint generated always as identity primary key,
  commande_id  text not null references public.commandes(id) on delete cascade,
  etape        text not null,
  -- Ce qui distingue deux SMS d'une même étape : le livreur, pour
  -- « course_acceptee » (un nouveau livreur après un refus se présente).
  cle          text not null default '',
  numero       text not null,
  texte        text not null,
  etat         text not null default 'a_envoyer'
               check (etat in ('a_envoyer', 'en_cours', 'envoye', 'refuse', 'abandonne')),
  tentatives   int not null default 0,
  essaye_le    timestamptz,
  code         text not null default '',
  statut_http  int,
  message      text not null default '',
  cree_le      timestamptz not null default now(),
  envoye_le    timestamptz
);
create unique index if not exists sms_commandes_une_fois on public.sms_commandes (commande_id, etape, cle);
create index if not exists sms_commandes_jour on public.sms_commandes (cree_le);
create index if not exists sms_commandes_en_attente on public.sms_commandes (etat)
  where etat in ('a_envoyer', 'en_cours');
-- Le numéro complet y vit : personne d'autre que le serveur.
alter table public.sms_commandes enable row level security;
revoke all on table public.sms_commandes from public, anon, authenticated;
grant all on table public.sms_commandes to service_role;

/**
 * Un texte qu'aucun téléphone ne déforme : sans accents, un seul SMS
 * (160). Les lettres connues se traduisent (« Dɔssou » → « Dossou ») ;
 * les autres accents se décomposent et perdent leur signe ; ce qui reste
 * hors de l'ASCII (un émoji dans un nom) disparaît — sans quoi le SMS
 * passerait en Unicode, à 70 caractères, et se paierait deux ou trois fois.
 */
create or replace function public.sms_texte(t text) returns text
language sql immutable set search_path = public as $$
  select left(btrim(regexp_replace(regexp_replace(normalize(translate(coalesce(t, ''),
    'àâäáãåçéèêëíìîïñóòôöõúùûüýÿÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝ«»’‘“”–—…œŒɔƆɛƐ',
    'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUY""''''""--.oOoOeE'), NFD),
    '[^ -~]', '', 'g'), '\s+', ' ', 'g')), 160);
$$;

/**
 * Le numéro tel que la passerelle l'attend : indicatif compris, sans
 * « + ». Au Bénin, un ancien numéro à 8 chiffres prend « 01 » devant
 * (la même règle que les numéros de réception). Null : pas un numéro.
 */
create or replace function public.sms_numero(tel text, indicatif text default '229') returns text
language plpgsql immutable set search_path = public as $$
declare
  chiffres text := regexp_replace(coalesce(tel, ''), '\D', '', 'g');
  ind      text := coalesce(nullif(regexp_replace(coalesce(indicatif, ''), '\D', '', 'g'), ''), '229');
begin
  if chiffres like '00%' then chiffres := substr(chiffres, 3); end if;
  if ind = '229' then
    chiffres := regexp_replace(chiffres, '^229', '');
    if length(chiffres) = 8 then chiffres := '01' || chiffres; end if;
    if length(chiffres) <> 10 then return null; end if;
    return '229' || chiffres;
  end if;
  if chiffres like ind || '%' and length(chiffres) > length(ind) + 6 then
    chiffres := substr(chiffres, length(ind) + 1);
  end if;
  if length(chiffres) < 6 or length(chiffres) > 13 then return null; end if;
  return ind || chiffres;
end $$;

/**
 * DÉCIDER ET RÉSERVER un SMS d'étape. Rend le numéro de la ligne écrite,
 * ou null si rien ne doit partir. Toutes les règles sont ici, au même
 * endroit : allumé, étape choisie, commande payée après l'allumage, client
 * visé, numéro valable, une fois par étape, plafonds.
 */
create or replace function public.sms_prevoir(la_commande text, l_etape text, la_cle text default '')
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  r      public.sms_reglages%rowtype;
  c      public.commandes%rowtype;
  vers   text;
  num    text;
  msg    text;
  reste  bigint;
  liv    record;
  etat_x text := 'a_envoyer';
  code_x text := '';
  nouveau bigint;
begin
  select * into r from public.sms_reglages where id = 1;
  if not found or not r.actif or r.url = '' or not (l_etape = any(r.etapes)) then
    return null;
  end if;
  select * into c from public.commandes x where x.id = la_commande;
  if not found or c.etat <> 'payee' or c.compte_supprime then
    return null;
  end if;
  if r.actif_depuis is null or c.paye_le is null or c.paye_le < r.actif_depuis then
    return null;
  end if;
  -- LE CLIENT VISÉ : celui que la notification de l'application ne touche pas.
  if not ((c.client_id is null and r.sans_compte)
          or (to_jsonb(c) ->> 'origine' = 'whatsapp' and r.whatsapp)
          -- Un téléphone qui n'a pas ouvert l'application depuis 30 jours
          -- (désinstallée, perdue) ne vaut plus notification.
          or (c.client_id is not null and r.sans_appareil
              and not exists (select 1 from public.appareils_push a
                               where a.compte = c.client_id and a.application = 'client'
                                 and a.maj_le > now() - interval '30 days'))) then
    return null;
  end if;
  vers := public.sms_numero(c.client_tel, c.client_indicatif);
  if vers is null then
    return null;
  end if;

  -- UN SEUL VERROU pour toutes les réservations : le doublon d'étape, le
  -- plafond par commande ET le plafond du jour se comptent l'un après
  -- l'autre. Un verrou par commande laissait deux commandes payées au même
  -- instant passer toutes deux sous le plafond du jour. Il n'est pris
  -- qu'ici, après les sorties rapides : quelques centaines par jour.
  perform pg_advisory_xact_lock(hashtext('sms:commandes'));
  if l_etape = 'course_acceptee' then
    -- Le livreur qui se présente : un SMS à chaque NOUVEAU livreur (A, puis
    -- B après un refus, puis A de nouveau) — pas deux fois le même d'affilée.
    if (select split_part(s.cle, '#', 1) from public.sms_commandes s
         where s.commande_id = la_commande and s.etape = 'course_acceptee'
         order by s.id desc limit 1) is not distinct from coalesce(la_cle, '') then
      return null;
    end if;
  elsif exists (select 1 from public.sms_commandes s
                 where s.commande_id = la_commande and s.etape = l_etape and s.cle = coalesce(la_cle, '')) then
    return null;
  end if;
  if (select count(*) from public.sms_commandes s
       where s.commande_id = la_commande and s.etat in ('a_envoyer', 'en_cours', 'envoye')) >= r.plafond then
    etat_x := 'abandonne'; code_x := 'PLAFOND';
  elsif (select count(*) from public.sms_commandes s
          where s.etat in ('a_envoyer', 'en_cours', 'envoye')
            and s.cree_le >= (date_trunc('day', now() at time zone 'Africa/Porto-Novo')
                              at time zone 'Africa/Porto-Novo')) >= r.plafond_jour then
    etat_x := 'abandonne'; code_x := 'PLAFOND_JOUR';
  end if;

  num := coalesce(nullif(c.numero, ''), c.id);
  if l_etape = 'commande_payee' then
    select coalesce(sum(greatest(0, x.a_encaisser)), 0) into reste from public.restes_par_boutique(c.id) x;
    msg := case when to_jsonb(c) ->> 'origine' = 'whatsapp'
                then 'BIZZOO : votre commande ' || num || ' est enregistree et payee. Nous la preparons.'
                else 'BIZZOO : votre commande ' || num || ' est confirmee. Nous la preparons.' end
        || case when reste > 0 then ' Reste a payer a la livraison : ' || reste || ' FCFA.' else '' end
        || ' Nous vous enverrons le nom de votre livreur.';
  elsif l_etape = 'course_acceptee' then
    select coalesce(nullif(btrim(p.nom), ''), 'Votre livreur') as nom,
           regexp_replace(regexp_replace(coalesce(p.tel, ''), '\D', '', 'g'), '^229', '') as tel
      into liv
      from public.profils p where p.id::text = la_cle;
    if not found then
      return null;
    end if;
    msg := 'BIZZOO : ' || liv.nom || ' livre votre commande ' || num || '.'
        || case when liv.tel <> '' then ' Son numero : ' || liv.tel || '.' else '' end
        || ' Gardez votre telephone a portee.';
  elsif l_etape = 'commande_en_livraison' then
    msg := 'BIZZOO : votre commande ' || num || ' est en route. Gardez votre telephone a portee.';
  elsif l_etape = 'commande_remise' then
    msg := 'BIZZOO : votre commande ' || num || ' est livree. Merci de votre confiance !';
  elsif l_etape = 'commande_annulee' then
    msg := 'BIZZOO : un ou plusieurs articles de votre commande ' || num
        || ' sont annules. Ouvrez votre recu ou contactez-nous pour le detail.';
  else
    return null;
  end if;

  insert into public.sms_commandes as s (commande_id, etape, cle, numero, texte, etat, code)
  values (la_commande, l_etape,
          case when l_etape = 'course_acceptee'
               then coalesce(la_cle, '') || '#' || (select count(*) from public.sms_commandes x
                                                     where x.commande_id = la_commande and x.etape = 'course_acceptee')
               else coalesce(la_cle, '') end,
          vers, public.sms_texte(msg), etat_x, code_x)
  on conflict (commande_id, etape, cle) do nothing
  returning s.id into nouveau;
  return case when etat_x = 'a_envoyer' then nouveau end;
end $$;

-- LE DÉCLENCHEUR D'ENVOI : une demande à la fonction Edge, après la
-- transaction. Il ne bloque jamais l'écriture, quoi qu'il arrive.
create or replace function public.sms_commande_part() returns trigger
language plpgsql security definer set search_path = public as $$
declare adresse text;
begin
  if new.etat <> 'a_envoyer' then return null; end if;
  if to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then return null; end if;
  select r.url into adresse from public.sms_reglages r where r.id = 1;
  if coalesce(adresse, '') = '' then return null; end if;
  begin
    perform net.http_post(adresse, jsonb_build_object('id', new.id),
      '{}'::jsonb, '{"Content-Type": "application/json"}'::jsonb, 10000);
  exception when others then
    raise warning 'sms_commande_part(%) : %', new.id, sqlerrm;
  end;
  return null;
end $$;
drop trigger if exists sms_commandes_partent on public.sms_commandes;
create trigger sms_commandes_partent
  after insert on public.sms_commandes
  for each row execute function public.sms_commande_part();

/** Ce que la fonction Edge envoie — une seule fois. Réservé au serveur. */
create or replace function public.sms_a_envoyer(cible bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s public.sms_commandes%rowtype;
begin
  -- Coupés entre-temps : rien ne part.
  if not coalesce((select r.actif from public.sms_reglages r where r.id = 1), false) then
    update public.sms_commandes x set etat = 'abandonne', code = 'COUPE', message = 'SMS coupés par le superadministrateur.'
     where x.id = cible and x.etat = 'a_envoyer';
    return null;
  end if;
  update public.sms_commandes x
     set etat = 'en_cours', tentatives = x.tentatives + 1, essaye_le = now()
   where x.id = cible and x.etat = 'a_envoyer' and x.cree_le > now() - interval '6 hours'
  returning * into s;
  if not found then return null; end if;
  return jsonb_build_object('id', s.id, 'numero', s.numero, 'texte', s.texte);
end $$;

/**
 * Le verdict de la passerelle. On ne réessaie QUE lorsque rien n'a pu
 * partir : passerelle injoignable (connexion impossible), ou « trop de
 * demandes » / « indisponible » sans code (429, 503) — 3 fois en tout.
 * Un délai dépassé (DELAI_DEPASSE) ou un 200 sans code, c'est peut-être
 * parti : renvoyer, ce serait payer deux fois le même SMS.
 */
create or replace function public.sms_resultat(cible bigint, ok boolean, code text default '',
                                               statut_http int default null, message text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.sms_commandes x
     set etat = case when ok then 'envoye'
                     when (upper(coalesce(sms_resultat.code, '')) = 'INJOIGNABLE'
                           or (upper(coalesce(sms_resultat.code, '')) = 'REFUS_SANS_CODE'
                               and coalesce(sms_resultat.statut_http, 0) in (429, 503)))
                          and x.tentatives < 3 then 'a_envoyer'
                     else 'refuse' end,
         envoye_le = case when ok then now() end,
         code = left(coalesce(sms_resultat.code, ''), 40),
         statut_http = sms_resultat.statut_http,
         message = left(coalesce(sms_resultat.message, ''), 300)
   where x.id = cible and x.etat = 'en_cours';
end $$;

/**
 * La reprise, chaque 10 minutes : ce qui attend depuis plus de deux
 * minutes repart (passerelle injoignable, appel perdu) ; au-delà de six
 * heures, un SMS d'étape n'a plus de sens — abandonné. UN ENVOI RESTÉ
 * « EN COURS » NE REPART JAMAIS : la fonction a peut-être envoyé le SMS
 * puis perdu le verdict ; le renvoyer, ce serait le payer deux fois.
 */
create or replace function public.sms_reprendre() returns int
language plpgsql security definer set search_path = public as $$
declare
  adresse text;
  cible   bigint;
  n       int := 0;
begin
  update public.sms_commandes x set etat = 'abandonne', code = 'TROP_TARD', message = 'Pas parti en six heures.'
   where x.etat in ('a_envoyer', 'en_cours') and x.cree_le <= now() - interval '6 hours';
  update public.sms_commandes x
     set etat = 'abandonne', code = 'SANS_REPONSE', message = 'Sans verdict : peut-être parti, pas renvoyé.'
   where x.etat = 'en_cours' and x.essaye_le <= now() - interval '10 minutes';
  if to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then return 0; end if;
  select r.url into adresse from public.sms_reglages r where r.id = 1 and r.actif;
  if coalesce(adresse, '') = '' then return 0; end if;
  for cible in
    select x.id from public.sms_commandes x
     where x.etat = 'a_envoyer' and x.cree_le <= now() - interval '2 minutes'
     order by x.cree_le limit 50
  loop
    begin
      perform net.http_post(adresse, jsonb_build_object('id', cible),
        '{}'::jsonb, '{"Content-Type": "application/json"}'::jsonb, 10000);
      n := n + 1;
    exception when others then
      raise warning 'sms_reprendre(%) : %', cible, sqlerrm;
    end;
  end loop;
  return n;
end $$;

-- ---------- Les étapes ----------
-- Des déclencheurs À PART : ceux des notifications (notifier_paiement,
-- notifier_ligne) ne bougent pas. Un SMS qui échoue n'empêche JAMAIS
-- l'étape elle-même.
create or replace function public.sms_paiement() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    perform public.sms_prevoir(new.id, 'commande_payee', '');
  exception when others then
    raise warning 'sms_paiement(%) : %', new.id, sqlerrm;
  end;
  return null;
end $$;
drop trigger if exists commandes_sms on public.commandes;
create trigger commandes_sms
  after update of etat on public.commandes
  for each row when (new.etat = 'payee' and old.etat is distinct from 'payee')
  execute function public.sms_paiement();

-- Les étapes se lisent au niveau de la COMMANDE : « livrée » quand plus
-- aucun article n'attend. Un déclencheur AFTER voit toutes les lignes
-- changées par la même instruction (une course prise d'un coup).
create or replace function public.sms_ligne() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    if new.recu_le is not null and old.recu_le is null and new.livreur_id is not null then
      perform public.sms_prevoir(new.commande_id, 'course_acceptee', new.livreur_id::text);
    end if;
    if new.etat = 'en_livraison' and old.etat is distinct from 'en_livraison' then
      perform public.sms_prevoir(new.commande_id, 'commande_en_livraison', '');
    end if;
    -- « Livrée » quand plus rien n'attend — que la dernière ligne soit
    -- remise, ou annulée après que les autres l'ont été.
    if new.etat in ('remise', 'annulee') and old.etat is distinct from new.etat
       and not exists (select 1 from public.commande_lignes l
                        where l.commande_id = new.commande_id and l.etat not in ('remise', 'annulee'))
       and exists (select 1 from public.commande_lignes l
                    where l.commande_id = new.commande_id and l.etat = 'remise') then
      perform public.sms_prevoir(new.commande_id, 'commande_remise', '');
    end if;
    if new.etat = 'annulee' and old.etat is distinct from 'annulee' then
      perform public.sms_prevoir(new.commande_id, 'commande_annulee', '');
    end if;
  exception when others then
    raise warning 'sms_ligne(%) : %', new.id, sqlerrm;
  end;
  return null;
end $$;
drop trigger if exists lignes_sms on public.commande_lignes;
create trigger lignes_sms
  after update on public.commande_lignes
  for each row execute function public.sms_ligne();

-- ---------- Le réglage, par le superadministrateur (BIZZOO Admin) ----------
create or replace function public.sms_commandes_reglages() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r public.sms_reglages%rowtype;
  debut timestamptz := date_trunc('day', now() at time zone 'Africa/Porto-Novo') at time zone 'Africa/Porto-Novo';
begin
  if not public.est_super() then
    raise exception 'Réservé au superadministrateur.' using errcode = 'P0001';
  end if;
  select * into r from public.sms_reglages where id = 1;
  return jsonb_build_object(
    'actif', r.actif, 'plafond', r.plafond, 'plafond_jour', r.plafond_jour, 'etapes', to_jsonb(r.etapes),
    'sans_compte', r.sans_compte, 'whatsapp', r.whatsapp, 'sans_appareil', r.sans_appareil,
    'actif_depuis', r.actif_depuis, 'branche', r.url <> '',
    'aujourdhui', jsonb_build_object(
      'envoyes', (select count(*) from public.sms_commandes s where s.cree_le >= debut and s.etat = 'envoye'),
      'en_attente', (select count(*) from public.sms_commandes s where s.cree_le >= debut and s.etat in ('a_envoyer', 'en_cours')),
      'refuses', (select count(*) from public.sms_commandes s where s.cree_le >= debut and s.etat = 'refuse')),
    'dernier_refus', (select jsonb_build_object('le', s.cree_le, 'code', s.code,
                                                'message', regexp_replace(s.message, '\d{6,}', '…', 'g'))
                        from public.sms_commandes s where s.etat = 'refuse' order by s.cree_le desc limit 1));
end $$;

create or replace function public.regler_sms_commandes(actif boolean, plafond int, plafond_jour int, etapes text[],
                                                       sans_compte boolean, whatsapp boolean, sans_appareil boolean)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  etait boolean;
begin
  if not public.est_super() then
    raise exception 'Seul le superadministrateur règle les SMS aux clients.' using errcode = 'P0001';
  end if;
  if plafond is null or plafond < 0 or plafond > 10 then
    raise exception 'Le plafond par commande : de 0 à 10 SMS.' using errcode = 'P0001';
  end if;
  if plafond_jour is null or plafond_jour < 0 or plafond_jour > 5000 then
    raise exception 'Le plafond par jour : de 0 à 5 000 SMS.' using errcode = 'P0001';
  end if;
  if not (coalesce(etapes, '{}') <@ array['commande_payee', 'course_acceptee', 'commande_en_livraison',
                                          'commande_remise', 'commande_annulee']) then
    raise exception 'Une étape inconnue.' using errcode = 'P0001';
  end if;
  select r.actif into etait from public.sms_reglages r where r.id = 1;
  update public.sms_reglages r
     set actif = coalesce(regler_sms_commandes.actif, false),
         -- Allumer, c'est « à partir de maintenant » : rien pour le passé.
         actif_depuis = case when coalesce(regler_sms_commandes.actif, false) and not coalesce(etait, false)
                             then now() else r.actif_depuis end,
         plafond = regler_sms_commandes.plafond, plafond_jour = regler_sms_commandes.plafond_jour,
         etapes = coalesce(regler_sms_commandes.etapes, '{}'),
         sans_compte = coalesce(regler_sms_commandes.sans_compte, true),
         whatsapp = coalesce(regler_sms_commandes.whatsapp, true),
         sans_appareil = coalesce(regler_sms_commandes.sans_appareil, true),
         maj_le = now(), maj_par = auth.uid()
   where r.id = 1;
  return public.sms_commandes_reglages();
end $$;

-- ---------- Le compteur, dans BIZZOO Personnel (Suivi → SMS) ----------
create or replace function public.rh_sms_compteur(depuis date default null, jusqu date default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  aujourdhui date := (now() at time zone 'Africa/Porto-Novo')::date;
  fin date := coalesce(jusqu, aujourdhui);
  debut date := coalesce(depuis, coalesce(jusqu, aujourdhui) - 29);
  t1 timestamptz;
  t2 timestamptz;
begin
  if public.rh_suivi_acces() is null then
    raise exception 'Votre compte n''a pas accès au suivi des commandes';
  end if;
  if fin < debut then
    raise exception 'La fin de la période précède son début';
  end if;
  if fin - debut > 400 then
    raise exception 'Choisissez une période d''un an au plus';
  end if;
  t1 := debut::timestamp at time zone 'Africa/Porto-Novo';
  t2 := (fin + 1)::timestamp at time zone 'Africa/Porto-Novo';
  return jsonb_build_object(
    'periode', jsonb_build_object('depuis', debut, 'jusqu', fin),
    'reglages', (select jsonb_build_object('actif', r.actif, 'plafond', r.plafond, 'plafond_jour', r.plafond_jour,
                                           'etapes', to_jsonb(r.etapes), 'actif_depuis', r.actif_depuis)
                   from public.sms_reglages r where r.id = 1),
    'total', (select jsonb_build_object(
                'envoyes', count(*) filter (where s.etat = 'envoye'),
                'refuses', count(*) filter (where s.etat = 'refuse'),
                'en_attente', count(*) filter (where s.etat in ('a_envoyer', 'en_cours')),
                'abandonnes', count(*) filter (where s.etat = 'abandonne'),
                'plafonnes', count(*) filter (where s.code in ('PLAFOND', 'PLAFOND_JOUR')),
                'commandes', count(distinct s.commande_id) filter (where s.etat = 'envoye'),
                'credit_epuise', count(*) filter (where s.code = 'INSUFFICIENT_BALANCE'))
                from public.sms_commandes s where s.cree_le >= t1 and s.cree_le < t2),
    'par_jour', coalesce((select jsonb_agg(jsonb_build_object('jour', j.jour, 'envoyes', j.envoyes, 'refuses', j.refuses,
                                                              'autres', j.autres) order by j.jour desc)
                from (select (s.cree_le at time zone 'Africa/Porto-Novo')::date as jour,
                             count(*) filter (where s.etat = 'envoye') as envoyes,
                             count(*) filter (where s.etat = 'refuse') as refuses,
                             count(*) filter (where s.etat not in ('envoye', 'refuse')) as autres
                        from public.sms_commandes s where s.cree_le >= t1 and s.cree_le < t2
                       group by 1) j), '[]'),
    'par_etape', coalesce((select jsonb_agg(jsonb_build_object('etape', e.etape, 'envoyes', e.envoyes, 'total', e.total)
                                            order by e.total desc)
                from (select s.etape, count(*) filter (where s.etat = 'envoye') as envoyes, count(*) as total
                        from public.sms_commandes s where s.cree_le >= t1 and s.cree_le < t2
                       group by 1) e), '[]'),
    -- Les derniers échecs, SANS le numéro du client.
    'echecs', coalesce((select jsonb_agg(x order by x ->> 'le' desc) from (
                select jsonb_build_object('le', s.cree_le, 'etape', s.etape, 'etat', s.etat, 'code', s.code,
                                          'message', regexp_replace(s.message, '\d{6,}', '…', 'g'),
                                          'commande_id', s.commande_id, 'numero', c.numero) as x
                  from public.sms_commandes s join public.commandes c on c.id = s.commande_id
                 where s.cree_le >= t1 and s.cree_le < t2 and s.etat in ('refuse', 'abandonne')
                 order by s.cree_le desc limit 30) d), '[]'));
end $$;

do $$
declare f text;
begin
  foreach f in array array['sms_texte(text)', 'sms_numero(text, text)', 'sms_prevoir(text, text, text)',
                           'sms_a_envoyer(bigint)', 'sms_resultat(bigint, boolean, text, int, text)',
                           'sms_reprendre()', 'sms_paiement()', 'sms_ligne()', 'sms_commande_part()'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['sms_a_envoyer(bigint)', 'sms_resultat(bigint, boolean, text, int, text)'] loop
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
  foreach f in array array['sms_commandes_reglages()',
                           'regler_sms_commandes(boolean, int, int, text[], boolean, boolean, boolean)',
                           'rh_sms_compteur(date, date)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- La reprise passe toutes les dix minutes. Sans pg_cron, rien ne casse :
-- ce qui n'est pas parti du premier coup ne repart pas.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('sms-commandes-reprise', '*/10 * * * *', 'select public.sms_reprendre()');
  end if;
exception when others then
  raise notice 'Reprise des SMS non programmée (%)', sqlerrm;
end $$;
revoke all on function public.restes_par_boutique(text) from public, anon, authenticated;
