-- =========================================================
-- BIZZOO — les fiches clients
--
-- Un client appelle : « j'ai commandé mardi, rien n'est
-- arrivé ». Jusqu'ici il fallait parcourir les commandes une à
-- une en espérant tomber sur son numéro : les comptes clients
-- n'étaient listés nulle part.
--
-- Ce fichier pose deux lectures, et RIEN D'AUTRE :
--
--   clients_liste()     retrouver quelqu'un par son nom ou son
--                       numéro, avec ce qu'il a commandé et
--                       dépensé ;
--   client_commandes()  ses commandes, une par une.
--
-- AUCUNE ÉCRITURE. Un nom, un numéro, une adresse se corrigent
-- depuis le compte du client lui-même — la base refuse déjà à
-- l'enseigne de les écrire, et ce fichier n'y touche pas.
--
-- RÉSERVÉES À L'ENSEIGNE, et c'est délibéré. Une boutique voit
-- déjà le nom et le numéro sur SES commandes ; lui ouvrir la
-- liste entière, ce serait lui remettre le fichier clients de
-- toutes les autres. À qui n'y a pas droit, les deux fonctions
-- rendent zéro ligne.
--
-- DEUX PRÉCAUTIONS QUI COMPTENT :
--
--   LA RECHERCHE NE DÉVERSE PAS LA LISTE. Le filtre du numéro
--     est un « ou ». Sans garde, chercher un nom sans chiffre
--     le réduirait à « like '%%' » — vrai pour tout le monde —
--     et une recherche par nom rendrait le fichier entier.
--   UN NUMÉRO NON VÉRIFIÉ NE DÉSIGNE PERSONNE. Les commandes
--     passées AVANT le compte ne remontent que sur un numéro
--     vérifié par SMS, et moins de dix-huit mois : exactement
--     la règle de rattacher_mes_commandes, pas une règle
--     voisine. Deux clients peuvent taper le même numéro ;
--     l'un lirait sinon les achats de l'autre.
--
-- CE QUE CE FICHIER CHANGE LE JOUR OÙ VOUS L'EXÉCUTEZ : il
-- ouvre l'écran « Fiches clients » à votre compte. Aucune
-- donnée n'est touchée.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
--
-- Sans danger : relançable, et rien n'est supprimé.
-- =========================================================

-- Les colonnes que les deux lectures rapprochent. Elles viennent
-- d'ailleurs, et sont répétées ici : un fichier qui pose une fonction
-- pose aussi les colonnes dont elle se sert. Sur une base qui les a
-- déjà, ces lignes ne font rien.
alter table public.clients add column if not exists tel_verifie boolean not null default false;
alter table public.clients add column if not exists adresse text not null default '';
alter table public.clients add column if not exists indicatif text not null default '229';
alter table public.clients add column if not exists type_compte text not null default 'client';
alter table public.clients add column if not exists revendeur_etat text not null default 'aucune';
alter table public.clients add column if not exists revendeur_adresse text not null default '';
alter table public.clients add column if not exists revendeur_latitude double precision;
alter table public.clients add column if not exists revendeur_longitude double precision;
alter table public.commandes add column if not exists client_id uuid;
alter table public.commandes add column if not exists revendeur boolean not null default false;

-- ---------- La fiche d'un client ----------
-- Un client appelle : « j'ai commandé mardi, rien n'est arrivé ». Sans
-- cet écran, il fallait parcourir les commandes une à une. La liste se
-- cherche par nom ou par numéro, et chaque fiche porte ce que le compte
-- a fait : combien de commandes, combien payées, combien dépensé.
--
-- RÉSERVÉE À L'ENSEIGNE, et c'est délibéré. Une boutique voit déjà le
-- nom et le numéro sur SES commandes ; lui ouvrir la liste entière, ce
-- serait lui remettre le fichier clients de toutes les autres.
--
-- Zéro ligne plutôt qu'une erreur pour qui n'y a pas droit : l'écran
-- est déjà fermé côté application, et une erreur ne renseignerait que
-- celui qui la provoque.
create or replace function public.clients_liste(
  filtre text default '',
  cible  uuid default null)
returns table (
  id uuid, nom text, email text, tel text, indicatif text,
  tel_verifie boolean, adresse text, cree_le timestamptz,
  type_compte text, revendeur_etat text,
  revendeur_adresse text,
  revendeur_latitude double precision, revendeur_longitude double precision,
  commandes bigint, payees bigint, total_paye bigint, derniere timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare
  cherche  text := lower(trim(coalesce(filtre, '')));
  -- Un numéro se tape « 97 22 22 22 », « +229 97222222 » ou « 97222222 ».
  -- On ne garde que les chiffres des deux côtés pour les rapprocher.
  chiffres text := regexp_replace(cherche, '\D', '', 'g');
begin
  if not public.est_super() then return; end if;
  return query
    select c.id, c.nom, coalesce(u.email, '')::text, c.tel, c.indicatif,
           c.tel_verifie, c.adresse, c.cree_le,
           c.type_compte, c.revendeur_etat,
           c.revendeur_adresse, c.revendeur_latitude, c.revendeur_longitude,
           count(v.id)::bigint,
           count(v.id) filter (where v.etat = 'payee')::bigint,
           coalesce(sum(v.total) filter (where v.etat = 'payee'), 0)::bigint,
           max(v.cree_le)
      from public.clients c
      left join auth.users u on u.id = c.id
      left join public.commandes v on v.client_id = c.id
     where (cible is null or c.id = cible)
       -- Le « ou » du numéro n'ouvre RIEN quand la recherche ne contient
       -- aucun chiffre : sans cette garde, « like '%%' » serait vrai pour
       -- tout le monde et une recherche par nom rendrait toute la liste.
       and (cherche = ''
            or lower(c.nom) like '%' || cherche || '%'
            or (chiffres <> '' and c.tel like '%' || chiffres || '%')
            -- Un numéro se donne souvent avec son indicatif — « +229 97 22
            -- 22 22 » — alors que la colonne ne garde que le national. On
            -- retire l'indicatif DE CE COMPTE, pas une longueur devinée :
            -- tous les pays n'ont pas des numéros de huit chiffres.
            -- La condition de longueur est la même garde que plus haut :
            -- taper « 229 » seul ne doit pas vider le fichier.
            or (chiffres <> '' and coalesce(c.indicatif, '') <> ''
                and chiffres like c.indicatif || '%'
                and length(chiffres) > length(c.indicatif)
                and c.tel like '%' || substr(chiffres, length(c.indicatif) + 1) || '%'))
     group by c.id, u.email, c.nom, c.tel, c.indicatif, c.tel_verifie,
              c.adresse, c.cree_le, c.type_compte, c.revendeur_etat,
              c.revendeur_adresse, c.revendeur_latitude, c.revendeur_longitude
     -- Les plus récemment actifs d'abord : c'est de ceux-là qu'on parle
     -- au téléphone. Les comptes sans commande suivent, par ancienneté.
     order by max(v.cree_le) desc nulls last, c.cree_le desc
     limit 200;
end $$;
revoke all on function public.clients_liste(text, uuid) from public, anon;
grant execute on function public.clients_liste(text, uuid) to authenticated;

-- Les commandes d'un client — celles que la base lui a rattachées, ET
-- celles d'avant son compte.
--
-- CES DERNIÈRES SUIVENT EXACTEMENT LA RÈGLE DE rattacher_mes_commandes :
-- numéro VÉRIFIÉ, commande sans compte, moins de dix-huit mois. Pas une
-- règle voisine — la même. Un numéro non vérifié ne désigne personne :
-- deux clients peuvent taper le même, et l'un lirait les achats de
-- l'autre depuis cet écran.
create or replace function public.client_commandes(client uuid)
returns table (
  id text, numero text, cree_le timestamptz, paye_le timestamptz,
  etat text, total bigint, revendeur boolean,
  articles bigint, boutiques text, rattachee boolean)
language plpgsql stable security definer set search_path = public as $$
declare mien public.clients%rowtype;
begin
  if not public.est_super() or client is null then return; end if;
  select * into mien from public.clients where clients.id = client;
  if not found then return; end if;
  return query
    select v.id, v.numero, v.cree_le, v.paye_le, v.etat,
           v.total::bigint, v.revendeur,
           count(l.id)::bigint,
           coalesce(string_agg(distinct b.nom, ', '), '')::text,
           v.client_id is not null
      from public.commandes v
      left join public.commande_lignes l on l.commande_id = v.id
      left join public.boutiques b on b.id = l.boutique_id
     where v.client_id = client
        or (v.client_id is null
            and mien.tel_verifie and coalesce(mien.tel, '') <> ''
            and v.client_tel = mien.tel
            and v.cree_le > now() - interval '18 months')
     group by v.id, v.numero, v.cree_le, v.paye_le, v.etat,
              v.total, v.revendeur, v.client_id
     order by v.cree_le desc
     limit 100;
end $$;
revoke all on function public.client_commandes(uuid) from public, anon;
grant execute on function public.client_commandes(uuid) to authenticated;

-- ---------- Vérification ----------
-- Les dix comptes les plus récemment actifs, tels que l'écran les
-- montrera. Vous lisez ceci en tant qu'enseigne : c'est exactement ce
-- que les fonctions ci-dessus vous rendront.
--
-- Aucun compte client encore créé ? Zéro ligne, et c'est normal.
select c.nom                                        as "Client",
       case when c.tel = '' then '—'
            else '+' || c.indicatif || ' ' || c.tel end as "Numéro",
       case when c.tel_verifie then 'oui' else 'non' end as "Vérifié",
       case c.revendeur_etat when 'validee' then 'revendeur'
                             when 'en_attente' then 'revendeur en attente'
                             when 'refusee' then 'revendeur refusé'
                             else 'client' end       as "Type",
       count(v.id)                                  as "Commandes",
       count(v.id) filter (where v.etat = 'payee')  as "Payées",
       coalesce(sum(v.total) filter (where v.etat = 'payee'), 0) as "Dépensé"
  from public.clients c
  left join public.commandes v on v.client_id = c.id
 group by c.id, c.nom, c.tel, c.indicatif, c.tel_verifie, c.revendeur_etat
 order by max(v.cree_le) desc nulls last, c.cree_le desc
 limit 10;
