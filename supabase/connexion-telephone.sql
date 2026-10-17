-- =========================================================
-- BIZZOO 3.59.0 — Entrer avec son numéro, son mot de passe, et un code
--
-- Clients et livreurs entrent désormais avec leur NUMÉRO et un MOT DE
-- PASSE, puis un code reçu par SMS. L'e-mail devient facultatif : la
-- seconde porte, sans code, pour le jour où le téléphone n'est pas là.
--
-- Ce que la base change pour cela :
--   1. un livreur créé par son numéro (« compte: equipe ») reçoit sa
--      fiche d'équipe en attente, comme un compte créé par e-mail ;
--   2. il ne reçoit jamais de fiche client, même si Supabase confirme
--      son numéro d'office ;
--   3. un livreur entré par numéro + code n'a pas à rendre, en plus, le
--      code de l'équipe quand l'enseigne l'exige.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- Ce que les fonctions plus bas empruntent, recopié tel quel : ce
-- fichier doit passer seul, même sur une base d'avant.
create or replace function public.session_courante() returns uuid
language sql stable as $$
  select case when s ~* '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z'
              then s::uuid end
    from (select coalesce(auth.jwt() ->> 'session_id', '') as s) x;
$$;


create or replace function public.tel_national(complet text, indicatif text default '229')
returns text
language sql immutable as $$
  select case
           when chiffres like indicatif || '%'
                and length(chiffres) > length(indicatif)
             then substr(chiffres, length(indicatif) + 1)
           else chiffres
         end
    from (select regexp_replace(coalesce(complet, ''), '\D', '', 'g') as chiffres) x;
$$;
revoke all on function public.tel_national(text, text) from public, anon, authenticated;


create or replace function public.profil_nouveau_compte() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  /* UN CLIENT N'EST PAS UN COMPTE D'ÉQUIPE EN ATTENTE. L'application
     cliente s'inscrit en posant « compte: client » ; sans ce test, chaque
     acheteur apparaîtrait dans la liste des comptes de l'enseigne, et il
     suffirait d'un clic distrait pour donner à un client les droits d'un
     modérateur sur une boutique. */
  if coalesce(new.raw_user_meta_data ->> 'compte', '') = 'client' then
    return new;
  end if;
  /* Un compte qui n'a qu'un numéro est un acheteur, même si les
     métadonnées manquent — elles viennent du téléphone, après tout.
     SAUF « compte: equipe » : c'est un livreur que l'administrateur crée
     par son numéro (3.59.0). Il reçoit, comme les autres, sa fiche en
     attente — que l'administrateur active dans la foulée. */
  if coalesce(new.email, '') = '' and coalesce(new.phone, '') <> ''
     and coalesce(new.raw_user_meta_data ->> 'compte', '') <> 'equipe' then
    return new;
  end if;
  insert into public.profils (id, email, role, actif)
  values (new.id, coalesce(new.email, ''), 'moderateur', false)
  on conflict (id) do nothing;
  return new;
end $$;


create or replace function public.au_numero_confirme() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  national text;
begin
  -- Rien de neuf : ni une confirmation, ni un changement de numéro
  -- confirmé. On sort sans rien faire.
  if new.phone_confirmed_at is null then return new; end if;
  if tg_op = 'UPDATE'
     and old.phone_confirmed_at is not null
     and coalesce(old.phone, '') = coalesce(new.phone, '') then
    return new;
  end if;

  national := public.tel_national(new.phone, '229');
  if coalesce(national, '') = '' then return new; end if;

  -- Un compte de l'équipe qui confirme son numéro reste un compte
  -- d'équipe : lui poser une fiche client ferait de lui les deux à la
  -- fois, ce que « compte_unique » refuse — et à raison.
  if exists (select 1 from public.profils p where p.id = new.id and p.actif) then
    return new;
  end if;
  -- Un livreur créé par son numéro (« compte: equipe ») n'est pas un
  -- acheteur, même avant que sa fiche soit activée. Sans ce test, un
  -- Supabase réglé pour confirmer les numéros d'office lui poserait une
  -- fiche client à la création — et sa fiche d'équipe serait refusée.
  if coalesce(new.raw_user_meta_data ->> 'compte', '') = 'equipe' then
    return new;
  end if;

  -- Ce numéro est déjà vérifié ailleurs : on ne le vole pas. Le compte
  -- reste non vérifié, et l'application le dira en clair — mieux vaut un
  -- message qu'une contrainte violée au visage du client.
  if exists (select 1 from public.clients c
              where c.tel = national and c.tel_verifie and c.id <> new.id) then
    raise notice 'BIZZOO : le numéro % est déjà vérifié sur un autre compte', national;
    return new;
  end if;

  -- « bizzoo.verification » est ce qui distingue cette écriture d'une
  -- requête ordinaire : sans lui, le verrou de « clients » la refuserait.
  perform set_config('bizzoo.verification', 'oui', true);
  insert into public.clients (id, tel, indicatif, tel_verifie, nom)
  values (new.id, national, '229', true,
          left(coalesce(new.raw_user_meta_data ->> 'nom', ''), 120))
  on conflict (id) do update
    set tel = excluded.tel,
        indicatif = excluded.indicatif,
        tel_verifie = true,
        maj_le = now();
  perform set_config('bizzoo.verification', '', true);
  return new;
exception when others then
  /* On ne fait PAS échouer « verify » pour autant : le numéro est
     confirmé chez GoTrue, c'est ce qui compte. La réconciliation
     rattrapera. */
  raise notice 'BIZZOO : numéro confirmé mais fiche non mise à jour (%)', sqlerrm;
  return new;
end $$;


create or replace function public.session_confirmee() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.sessions_sms s
     where s.session_id = public.session_courante()
       and s.utilisateur = auth.uid())
  /* UN LIVREUR ENTRÉ PAR SON NUMÉRO a déjà rendu un code : celui de
     Supabase (numéro, mot de passe, puis code — 3.59.0). Le jeton le
     dit, signé par GoTrue : méthode « otp », numéro confirmé. Lui
     redemander le code de l'équipe, ce serait deux SMS pour une seule
     porte. Les autres rangs gardent leur code d'équipe, inchangé. */
  or (coalesce(auth.jwt() ->> 'phone', '') <> ''
      and exists (select 1 from jsonb_array_elements(
                    case when jsonb_typeof(auth.jwt() -> 'amr') = 'array'
                         then auth.jwt() -> 'amr' else '[]'::jsonb end) a
                   where a ->> 'method' = 'otp')
      and exists (select 1 from public.profils p
                   where p.id = auth.uid() and p.role = 'livreur'));
$$;



