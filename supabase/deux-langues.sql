-- =========================================================
-- BIZZOO 3.73.0 — Deux langues : la langue de chaque compte
--
--   Les applications parlent français et anglais. La base retient la
--   langue de chaque compte (langues_comptes, réglée par l'application
--   avec regler_langue) pour que les notifications sur le téléphone et les
--   SMS au client partent dans cette langue :
--     - push_a_envoyer et rh_push_a_envoyer rendent la langue du
--       destinataire, et les fonctions Edge envoyer-push et rh-push
--       traduisent ;
--     - sms_prevoir écrit le SMS en anglais pour un client anglophone.
--   Sans choix connu : le français, comme avant.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- (3.80.0) Empruntées plus bas, recopiées telles quelles.
create or replace function public.navigateurs_de(qui uuid, app text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if to_regclass('public.appareils_web') is null then
    return '[]'::jsonb;
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('endpoint', w.endpoint, 'p256dh', w.p256dh, 'auth', w.auth)
                                    order by w.maj_le desc)
                     from public.appareils_web w
                    where w.compte = qui and w.application = app), '[]'::jsonb);
end $$;
revoke all on function public.navigateurs_de(uuid, text) from public, anon, authenticated;

create table if not exists public.langues_comptes (
  compte     uuid primary key references auth.users(id) on delete cascade,
  langue     text not null default 'fr' check (langue in ('fr', 'en')),
  modifie_le timestamptz not null default now()
);
alter table public.langues_comptes enable row level security;
drop policy if exists "langue lecture" on public.langues_comptes;
create policy "langue lecture" on public.langues_comptes
  for select to authenticated using (compte = auth.uid());
revoke all on table public.langues_comptes from public, anon, authenticated;
grant select on table public.langues_comptes to authenticated;
grant all on table public.langues_comptes to service_role;

-- (3.73.0) Empruntées plus bas, recopiées telles quelles.
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

create or replace function public.sms_texte(t text) returns text
language sql immutable set search_path = public as $$
  select left(btrim(regexp_replace(regexp_replace(normalize(translate(coalesce(t, ''),
    'àâäáãåçéèêëíìîïñóòôöõúùûüýÿÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝ«»’‘“”–—…œŒɔƆɛƐ',
    'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUY""''''""--.oOoOeE'), NFD),
    '[^ -~]', '', 'g'), '\s+', ' ', 'g')), 160);
$$;

/** La langue d'un compte : 'en' s'il l'a choisie, sinon 'fr'. */
create or replace function public.langue_du_compte(qui uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select l.langue from public.langues_comptes l where l.compte = qui), 'fr');
$$;
revoke all on function public.langue_du_compte(uuid) from public, anon, authenticated;
grant execute on function public.langue_du_compte(uuid) to service_role;

/** L'application dit la langue du compte connecté (au choix FR/EN, à la connexion). */
create or replace function public.regler_langue(langue text) returns text
language plpgsql security definer set search_path = public as $$
declare l text := lower(btrim(coalesce(langue, '')));
begin
  if auth.uid() is null then
    raise exception 'Connectez-vous d''abord.';
  end if;
  if l not in ('fr', 'en') then
    raise exception 'Langue inconnue : fr ou en.';
  end if;
  insert into public.langues_comptes as x (compte, langue, modifie_le)
  values (auth.uid(), l, now())
  on conflict (compte) do update set langue = excluded.langue, modifie_le = now()
   where x.langue is distinct from excluded.langue;
  return l;
end $$;
revoke all on function public.regler_langue(text) from public, anon;
grant execute on function public.regler_langue(text) to authenticated;


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
    -- (3.73.0) La langue du destinataire : la fonction Edge traduit.
    'langue', public.langue_du_compte(n.destinataire),
    'application', case when coalesce(n.lien, '') like '#/commande/%' then 'client' else 'admin' end,
    'jetons', coalesce((select jsonb_agg(a.jeton order by a.maj_le desc)
                          from public.appareils_push a
                         where a.compte = n.destinataire
                           and a.application = case when coalesce(n.lien, '') like '#/commande/%'
                                                    then 'client' else 'admin' end), '[]'::jsonb),
    -- (3.80.0) Ses navigateurs abonnés (Web Push), de la même application.
    -- Lu par « to_regclass » : une base sans la table rend une liste vide.
    'web', public.navigateurs_de(n.destinataire,
             case when coalesce(n.lien, '') like '#/commande/%' then 'client' else 'admin' end));
end $$;

create or replace function public.rh_push_a_envoyer(cible bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s public.rh_alertes_envoyees;
begin
  update public.rh_alertes_envoyees x set pousse_le = now()
   where x.id = cible and x.pousse_le is null and x.cree_le > now() - interval '1 hour'
  returning * into s;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'id', s.id, 'titre', s.titre, 'corps', s.corps, 'lien', s.lien,
    -- (3.73.0) La langue de l'employé : la fonction Edge traduit.
    'langue', public.langue_du_compte(s.compte),
    'tache', regexp_replace(regexp_replace(s.cle, '^escalade:', ''), '#[0-9]+\Z', ''),
    'abonnements', coalesce((select jsonb_agg(jsonb_build_object('endpoint', a.endpoint, 'p256dh', a.p256dh, 'auth', a.auth)
                                              order by a.cree_le desc)
                               from public.rh_push_abonnements a where a.compte = s.compte), '[]'::jsonb));
end $$;

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
  en     boolean;
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
  -- (3.73.0) Le client qui a choisi l'anglais reçoit ses SMS en anglais.
  en := public.langue_du_compte(c.client_id) = 'en';
  if en then
    if l_etape = 'commande_payee' then
      select coalesce(sum(greatest(0, x.a_encaisser)), 0) into reste from public.restes_par_boutique(c.id) x;
      msg := case when to_jsonb(c) ->> 'origine' = 'whatsapp'
                  then 'BIZZOO: your order ' || num || ' is registered and paid. We are preparing it.'
                  else 'BIZZOO: your order ' || num || ' is confirmed. We are preparing it.' end
          || case when reste > 0 then ' Balance to pay on delivery: ' || reste || ' FCFA.' else '' end
          || ' We will send you your delivery rider''s name.';
    elsif l_etape = 'course_acceptee' then
      select coalesce(nullif(btrim(p.nom), ''), 'Your delivery rider') as nom,
             regexp_replace(regexp_replace(coalesce(p.tel, ''), '\D', '', 'g'), '^229', '') as tel
        into liv
        from public.profils p where p.id::text = la_cle;
      if not found then
        return null;
      end if;
      msg := 'BIZZOO: ' || liv.nom || ' is delivering your order ' || num || '.'
          || case when liv.tel <> '' then ' Their number: ' || liv.tel || '.' else '' end
          || ' Keep your phone nearby.';
    elsif l_etape = 'commande_en_livraison' then
      msg := 'BIZZOO: your order ' || num || ' is on its way. Keep your phone nearby.';
    elsif l_etape = 'commande_remise' then
      msg := 'BIZZOO: your order ' || num || ' has been delivered. Thank you for your trust!';
    elsif l_etape = 'commande_annulee' then
      msg := 'BIZZOO: one or more items of your order ' || num
          || ' were cancelled. Open your receipt or contact us for details.';
    else
      return null;
    end if;
  elsif l_etape = 'commande_payee' then
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

