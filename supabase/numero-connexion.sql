-- =========================================================
-- BIZZOO 3.79.2 — Le numéro d'un compte est son numéro de connexion
--
--   Changer le numéro d'un vendeur (ou d'un livreur) dans l'administration
--   ne changeait que sa fiche : il ne pouvait entrer qu'avec l'ancien.
--   Désormais le nouveau numéro devient aussi son numéro de connexion,
--   l'ancien n'ouvre plus rien, le mot de passe et toutes les données du
--   compte restent. Les comptes déjà désaccordés sont réparés.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- La colonne existe depuis longtemps ; posée ici pour que le fichier se suffise.
alter table public.profils add column if not exists tel text not null default '';

-- ---------- (3.79.2) Le numéro d'un compte EST son numéro de connexion ----------
-- Un vendeur, un livreur entrent par leur numéro et leur mot de passe :
-- c'est le numéro rangé par GoTrue (« auth.users.phone ») qui ouvre la
-- porte. L'administration, elle, change le numéro de la FICHE
-- (« profils.tel »). Avant, les deux se séparaient : la fiche montrait le
-- nouveau numéro, et seul l'ancien permettait d'entrer.
--
-- Désormais, changer le numéro de la fiche d'un compte qui entre par son
-- numéro change aussi son numéro de connexion, dans la même transaction :
-- l'ancien ne permet plus d'entrer, le mot de passe reste le même, et
-- rien d'autre du compte ne bouge (rôle, boutique, soldes, commandes,
-- historique). Un numéro déjà pris par un autre compte est refusé, et
-- alors rien ne change — ni la fiche, ni la connexion.
--
-- Qui peut changer ce numéro ? Ceux que les règles de « profils »
-- laissent modifier la fiche : le superadministrateur, l'administrateur
-- sur SES livreurs et modérateurs. Personne ne change le sien par là.
-- Un compte qui entre par e-mail (sans numéro de connexion) garde son
-- numéro de fiche comme simple contact.
--
-- Le numéro s'écrit comme l'application le tape à la connexion :
-- chiffres seuls, « 00 » ôté, l'indicatif 229 ajouté s'il manque.
create or replace function public.numero_connexion(brut text) returns text
language sql immutable set search_path = public as $$
  select case when d = '' then ''
              when left(d, 3) = '229' then d
              else '229' || d end
    from (select case when left(x, 2) = '00' then substr(x, 3) else x end as d
            from (select regexp_replace(coalesce(brut, ''), '\D', '', 'g') as x) a) b;
$$;
revoke all on function public.numero_connexion(text) from public, anon, authenticated;

-- Pose le numéro de la fiche comme numéro de connexion. « strict » : une
-- erreur claire si c'est impossible (l'enregistrement est alors annulé) ;
-- sinon, rend false et ne touche à rien (réparation des anciens comptes).
create or replace function public.synchroniser_numero_connexion(cible uuid, strict boolean default true)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  actuel text;
  voulu  text;
begin
  select coalesce(u.phone, '') into actuel from auth.users u where u.id = cible;
  if not found or actuel = '' then
    return false;                       -- entre par e-mail : rien à faire
  end if;
  select public.numero_connexion(p.tel) into voulu from public.profils p where p.id = cible;
  if coalesce(voulu, '') = '' then
    if strict then
      raise exception 'Ce compte entre avec son numéro : il ne peut pas rester sans numéro.'
        using errcode = 'P0001';
    end if;
    return false;
  end if;
  if length(voulu) < 11 or length(voulu) > 15 then
    if strict then
      raise exception 'Numéro invalide : écrivez ses 10 chiffres, comme 01 97 00 00 00.'
        using errcode = 'P0001';
    end if;
    return false;
  end if;
  if voulu = actuel then
    return false;
  end if;
  -- Un téléphone, un compte : « 97 12 15 96 » et « 01 97 12 15 96 » sont
  -- le même (le Bénin est passé de 8 à 10 chiffres), d'où les 8 derniers.
  if exists (select 1 from auth.users x
              where x.id <> cible and coalesce(x.phone, '') <> ''
                and right(x.phone, 8) = right(voulu, 8)) then
    if strict then
      raise exception 'Ce numéro est déjà celui d''un autre compte BIZZOO : un numéro ne sert qu''à un seul compte.'
        using errcode = 'P0001';
    end if;
    return false;
  end if;
  -- Le nouveau numéro prend la place de l'ancien, qui n'ouvre plus rien.
  -- Sa confirmation suit : l'administration le donne, comme elle avait
  -- donné le premier. Le mot de passe ne bouge pas.
  update auth.users set phone = voulu, updated_at = now() where id = cible;
  return true;
end $$;
revoke all on function public.synchroniser_numero_connexion(uuid, boolean) from public, anon, authenticated;

create or replace function public.profil_numero_connexion() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if regexp_replace(coalesce(new.tel, ''), '\D', '', 'g')
     is distinct from regexp_replace(coalesce(old.tel, ''), '\D', '', 'g') then
    perform public.synchroniser_numero_connexion(new.id, true);
  end if;
  return null;
end $$;
revoke all on function public.profil_numero_connexion() from public, anon, authenticated;

drop trigger if exists profils_numero_connexion on public.profils;
create trigger profils_numero_connexion
  after update of tel on public.profils
  for each row execute function public.profil_numero_connexion();

-- Les comptes dont la fiche avait déjà changé de numéro sans la connexion
-- (avant la 3.79.2) : la fiche dit le numéro voulu, il devient celui de
-- la connexion. Un numéro pris par un autre compte reste tel quel.
do $$
declare
  p record;
  n int := 0;
begin
  for p in select x.id from public.profils x join auth.users u on u.id = x.id
            where coalesce(u.phone, '') <> ''
              and public.numero_connexion(x.tel) <> ''
              and public.numero_connexion(x.tel) <> u.phone loop
    if public.synchroniser_numero_connexion(p.id, false) then
      n := n + 1;
    end if;
  end loop;
  if n > 0 then
    raise notice '% compte(s) : le numéro de la fiche est devenu le numéro de connexion.', n;
  end if;
end $$;
