-- =========================================================
-- BIZZOO — le journal des versements
--
-- Une commande ne garde que son ÉTAT ACTUEL : payée, ou non.
-- Ce qui s'est passé en route ne l'était nulle part :
--
--   une demande partie sur un mauvais numéro,
--   un versement incomplet,
--   un client qui s'y reprend à trois fois,
--   un versement arrivé pour une commande introuvable.
--
-- Pire : en réussissant, « marquer_payee » EFFACE la remarque
-- de la commande. Un encaissement effaçait donc la trace de
-- ses propres échecs.
--
-- D'où ce journal. UNE LIGNE PAR TENTATIVE, jamais modifiée
-- ensuite : c'est ce qui permet de répondre à « combien
-- d'échecs cette semaine » et « chez quel opérateur ». Un
-- journal qu'on met à jour ne garde que la fin de l'histoire
-- — et la fin de l'histoire est déjà sur la commande.
--
-- PERSONNE NE L'ÉCRIT À LA MAIN, pas même vous. Aucune règle
-- d'écriture n'est posée sur la table : les seules écritures
-- viennent des fonctions du serveur, qui s'exécutent avec les
-- droits du propriétaire. Un journal qu'on peut retoucher ne
-- prouve rien le jour où il faudrait qu'il prouve quelque
-- chose.
--
-- L'OPÉRATEUR N'EST CONNU QU'À L'OUVERTURE de la demande :
-- c'est le client qui choisit MTN, Moov ou Celtiis, et ni la
-- notification ni la vérification ne le rappellent ensuite. La
-- fonction Edge le transmet donc au moment d'ouvrir, et les
-- lignes suivantes de la même commande le reprennent d'elles-
-- mêmes.
--
-- CE QUE CE FICHIER NE FAIT PAS : remplir le passé. Ce qui n'a
-- jamais été noté ne peut pas l'être après coup — le journal
-- commence le jour où vous l'exécutez. Vos commandes déjà
-- payées gardent leur état, elles n'apparaîtront simplement
-- pas dans le journal.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, et rien n'est supprimé.
-- =========================================================

-- Les colonnes que les fonctions ci-dessous écrivent ou lisent. Elles
-- viennent d'ailleurs, et sont répétées ici : un fichier qui pose une
-- fonction pose aussi les colonnes dont elle se sert.
alter table public.commandes add column if not exists fournisseur_ref text not null default '';
alter table public.commandes add column if not exists tentative_le timestamptz;
alter table public.commandes add column if not exists confirme_par text not null default '';
alter table public.commandes add column if not exists remarque text not null default '';
alter table public.commandes add column if not exists annonce_le timestamptz;
alter table public.commandes add column if not exists paye_le timestamptz;

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

-- Une ancienne base peut porter « reseau_de_la_commande » : la règle
-- qu'elle tenait vit désormais DANS « noter_versement », une seule fois.
-- On la retire pour qu'il ne reste pas deux endroits où la lire.
drop function if exists public.reseau_de_la_commande(text);

-- ---------- Lire le journal ----------
-- Réservé à l'enseigne : c'est l'argent de BIZZOO qui transite, pas
-- celui d'une boutique. Une boutique voit ses ventes encaissées dans
-- « statistiques_boutique » ; par quel opérateur le client a payé ne la
-- regarde pas.
create or replace function public.versements_liste(
  depuis date default null,
  jusqu  date default null,
  filtre text default '')
returns table (
  id bigint, commande_id text, numero text,
  fournisseur text, reseau text, reference text, transaction_id text,
  attendu bigint, recu bigint, verdict text, detail text,
  cree_le timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare tri text := lower(trim(coalesce(filtre, '')));
begin
  if not public.est_super() then return; end if;
  return query
    select v.id, v.commande_id, v.numero, v.fournisseur, v.reseau,
           v.reference, v.transaction_id, v.attendu, v.recu,
           v.verdict, v.detail, v.cree_le
      from public.versements v
     where (depuis is null or v.cree_le >= depuis::timestamptz)
       and (jusqu  is null or v.cree_le <  (jusqu + 1)::timestamptz)
       -- « tout » et le filtre vide disent la même chose. Un verdict
       -- inconnu ne rend rien plutôt que tout : se tromper de mot ne
       -- doit pas donner l'impression que la période est vide.
       and (tri = '' or tri = 'tout' or v.verdict = tri)
     order by v.cree_le desc, v.id desc
     limit 300;
end $$;
revoke all on function public.versements_liste(date, date, text) from public, anon;
grant execute on function public.versements_liste(date, date, text) to authenticated;

-- Le résumé de la période. Il compte sur TOUTES les lignes, pas sur les
-- trois cents que la liste rend : « ce qui est entré cette semaine » ne
-- peut pas dépendre de la longueur d'un écran.
create or replace function public.versements_resume(
  depuis date default null,
  jusqu  date default null)
returns table (
  fournisseur text, reseau text, verdict text,
  combien bigint, total bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.est_super() then return; end if;
  return query
    select v.fournisseur, v.reseau, v.verdict,
           count(*)::bigint,
           -- On ne somme QUE ce qui est réellement entré. Additionner
           -- les tentatives ouvertes ferait un chiffre d'affaires
           -- imaginaire, et c'est exactement l'erreur qu'un journal doit
           -- empêcher.
           coalesce(sum(v.recu) filter (where v.verdict = 'payee'), 0)::bigint
      from public.versements v
     where (depuis is null or v.cree_le >= depuis::timestamptz)
       and (jusqu  is null or v.cree_le <  (jusqu + 1)::timestamptz)
     group by v.fournisseur, v.reseau, v.verdict;
end $$;
revoke all on function public.versements_resume(date, date) from public, anon;
grant execute on function public.versements_resume(date, date) to authenticated;
-- « drop » avant « create » : cette fonction a gagné un paramètre —
-- l'agrégateur qui notifie — pour le journal des versements. Un
-- paramètre par défaut ne remplace pas l'ancienne signature, il en crée
-- une seconde, et l'appel devient ambigu : « function is not unique ».
-- Sans ce retrait, chaque encaissement échouerait.
drop function if exists public.marquer_payee(text, text, int);
create or replace function public.marquer_payee(
  reference text, transaction text, montant int, qui text default '')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c   public.commandes%rowtype;
  net text := left(regexp_replace(coalesce(transaction, ''), '[^A-Za-z0-9_-]', '', 'g'), 64);
begin
  if net = '' then return jsonb_build_object('ok', false, 'raison', 'transaction absente'); end if;

  -- On ne retrouve la commande QUE par la référence que nous avons
  -- nous-mêmes confiée à KkiaPay en ouvrant le paiement. Se rabattre sur
  -- la transaction annoncée par un téléphone laisserait le client
  -- choisir quel versement valide quelle commande — un versement de
  -- 100 000 réglant une commande de 100 francs. Sans référence, c'est la
  -- boutique qui tranche, à la main (confirmer_paiement), avec sous les
  -- yeux la transaction annoncée.
  select * into c from public.commandes where id = coalesce(reference, '');
  if not found then
    -- Un paiement qui ne nous concerne pas n'est pas une erreur. Mais il
    -- se note : un versement qui ne trouve pas sa commande est
    -- exactement ce qu'on veut voir au journal.
    perform public.noter_versement(null, 'inconnue', qui, '', coalesce(reference, ''),
      net, 0, coalesce(montant, 0),
      'Versement reçu pour une commande introuvable.');
    return jsonb_build_object('ok', true, 'raison', 'commande inconnue');
  end if;

  if c.etat = 'payee' then
    return jsonb_build_object('ok', true, 'deja', true, 'numero', c.numero);
  end if;

  perform set_config('bizzoo.paiement', 'oui', true);

  -- Cette transaction est déjà rattachée à une autre commande. On le
  -- NOTE au lieu de lever une erreur : une erreur ferait réessayer
  -- KkiaPay cinq fois pour rien, et l'encaissement resterait bloqué.
  if exists (select 1 from public.commandes a
              where a.transaction_id = net and a.id <> c.id) then
    update public.commandes
       set remarque = 'Transaction ' || net || ' déjà rattachée à une autre commande.'
     where id = c.id;
    -- L'agrégateur et l'opérateur se reprennent tout seuls sur la ligne
    -- d'ouverture : c'est « noter_versement » qui s'en charge.
    perform public.noter_versement(c.id, 'conflit', qui, '',
      c.fournisseur_ref, net, c.total, coalesce(montant, 0),
      'Transaction déjà rattachée à une autre commande.');
    return jsonb_build_object('ok', true, 'conflit', true, 'numero', c.numero);
  end if;

  -- Le montant qui compte est celui que KkiaPay annonce. S'il manque
  -- quelque chose, on ne valide pas : on écrit ce qu'on a reçu, et la
  -- boutique tranche. La preuve, elle, n'est pas posée : la commande
  -- n'est pas payée.
  if coalesce(montant, 0) < c.total then
    update public.commandes
       set remarque = 'Paiement incomplet : ' || coalesce(montant, 0)::text
                      || ' reçus sur ' || c.total::text || ' attendus'
                      || ' (transaction ' || net || ').'
     where id = c.id;
    perform public.noter_versement(c.id, 'incomplete', qui, '',
      c.fournisseur_ref, net, c.total, coalesce(montant, 0),
      'Reçu ' || coalesce(montant, 0)::text || ' sur ' || c.total::text || ' attendus.');
    return jsonb_build_object('ok', true, 'incomplet', true, 'numero', c.numero);
  end if;

  update public.commandes
     set etat = 'payee', paye_le = now(), transaction_id = net,
         confirme_par = '', remarque = ''
   where id = c.id;
  -- La remarque vient d'être effacée sur la commande : c'est le journal,
  -- désormais, qui garde ce qui s'est passé avant cette réussite.
  perform public.noter_versement(c.id, 'payee', qui, '',
    c.fournisseur_ref, net, c.total, coalesce(montant, 0), 'Versement encaissé.');
  return jsonb_build_object('ok', true, 'numero', c.numero, 'total', c.total);
end $$;

-- LE POINT À NE PAS MANQUER : révoquer du seul pseudo-rôle « public »
-- ne suffit pas. Supabase accorde d'office EXECUTE à « anon » et
-- « authenticated » sur toute fonction du schéma public. Sans ces deux
-- lignes, quiconque extrait la clé publiable de l'APK — et elle y est,
-- par construction — validerait ses commandes sans payer.
revoke all on function public.marquer_payee(text, text, int, text)
  from public, anon, authenticated;
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
create or replace function public.confirmer_paiement(cible text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  qui    text;
  montant bigint;
begin
  if not public.est_super() then
    raise exception 'Seule l''enseigne peut confirmer un paiement à la main';
  end if;
  select coalesce(p.email, '') into qui from public.profils p where p.id = auth.uid();
  perform set_config('bizzoo.paiement', 'oui', true);
  update public.commandes
     set etat = 'payee', paye_le = now(), confirme_par = coalesce(qui, 'enseigne')
   where id = cible and etat <> 'payee'
  returning total into montant;

  -- Au journal, et NOMMÉMENT « main ». Un encaissement à la main n'est
  -- pas un versement comme un autre : personne ne l'a vérifié chez
  -- l'agrégateur, quelqu'un s'en est porté garant. Des mois plus tard,
  -- c'est la première chose qu'on veut pouvoir distinguer.
  --
  -- « montant » ne vaut quelque chose que si la mise à jour a porté :
  -- une commande déjà payée ne se re-note pas.
  if montant is not null then
    perform public.noter_versement(cible, 'payee', 'main', '', '', '',
      montant, montant,
      'Confirmé à la main par ' || coalesce(nullif(qui, ''), 'l''enseigne') || '.');
  end if;
end $$;
revoke all on function public.confirmer_paiement(text) from public, anon;
grant execute on function public.confirmer_paiement(text) to authenticated;

-- ---------- Vérification ----------
-- Le journal vient d'être posé : il est VIDE, et c'est normal. Cette
-- requête montre ce qu'il affichera dès le premier paiement.
--
-- Zéro ligne aujourd'hui. Revenez-y après un encaissement.
select to_char(v.cree_le, 'DD/MM HH24:MI')             as "Quand",
       v.numero                                        as "Commande",
       coalesce(nullif(v.fournisseur, ''), '—')        as "Par",
       coalesce(nullif(v.reseau, ''), '—')             as "Opérateur",
       case v.verdict when 'payee'      then 'encaissé'
                      when 'ouverte'    then 'demande envoyée'
                      when 'incomplete' then 'INCOMPLET'
                      when 'conflit'    then 'CONFLIT'
                      when 'refusee'    then 'refusé'
                      else 'commande introuvable' end  as "Verdict",
       v.attendu                                       as "Attendu",
       v.recu                                          as "Reçu"
  from public.versements v
 order by v.cree_le desc
 limit 20;
