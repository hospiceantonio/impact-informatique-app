-- =========================================================
-- BIZZOO — (3.70.0) LES PRÉFIXES DES OPÉRATEURS, réglables sans mise à jour
-- Fichier de mise à jour : à exécuter une fois sur la base en service.
-- Sans danger : relançable, et rien n'est supprimé.
--
-- Un numéro béninois dit son réseau : « 01 » + deux chiffres (ou ces
-- deux chiffres en tête de l'ancien numéro à 8 chiffres). Les trois
-- applications s'en servent pour corriger le réseau choisi au paiement
-- et pour repérer un numéro tapé à la place d'un ID de transaction.
--
-- La liste vivait dans le code : un nouveau préfixe attribué par l'ARCEP
-- demandait une nouvelle version. Elle vit maintenant ICI ; les
-- applications la relisent à chaque ouverture, et gardent la leur si la
-- base ne répond pas. Le superadministrateur la règle depuis BIZZOO
-- Admin → Réglages → « Préfixes des opérateurs ».
--
-- Lecture : tout le monde (le client paie sans compte). Écriture : par
-- « regler_prefixe_operateur() » seulement, réservée au superadmin.
-- =========================================================
create table if not exists public.prefixes_operateurs (
  prefixe    text primary key check (prefixe ~ '^[0-9]{2}$'),
  operateur  text not null check (operateur in ('MTN', 'MOOV', 'CELTIIS')),
  modifie_le timestamptz not null default now()
);
alter table public.prefixes_operateurs enable row level security;
drop policy if exists "lecture publique" on public.prefixes_operateurs;
create policy "lecture publique" on public.prefixes_operateurs for select using (true);
revoke all on public.prefixes_operateurs from public, anon, authenticated;
grant select on public.prefixes_operateurs to anon, authenticated;

-- La liste de départ : celle du SDK de FeexPay, qui est aussi celle de
-- l'ancien plan. « do nothing » : relancé, ce fichier ne défait pas ce
-- que le superadmin a réglé depuis.
insert into public.prefixes_operateurs (prefixe, operateur)
select p, 'MTN' from unnest(array['42','46','50','51','52','53','54','56','57','59','61','62',
                                  '66','67','69','90','91','92','93','96','97']) p
union all
select p, 'MOOV' from unnest(array['45','55','58','60','63','64','65','68','94','95','98','99']) p
union all
select p, 'CELTIIS' from unnest(array['40','41','43','44','47']) p
on conflict (prefixe) do nothing;

-- Ajouter, réattribuer (« operateur » donné) ou retirer (« operateur »
-- vide) un préfixe. « prefixe » : « 30 », « 0130 » ou « 01 30 » — les
-- deux chiffres qui suivent « 01 ».
create or replace function public.regler_prefixe_operateur(prefixe text, operateur text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  p text := regexp_replace(coalesce(prefixe, ''), '\D', '', 'g');
  o text := upper(btrim(coalesce(operateur, '')));
begin
  if not public.est_super() then
    raise exception 'Les préfixes des opérateurs sont réglés par le superadministrateur';
  end if;
  if length(p) = 4 and left(p, 2) = '01' then p := right(p, 2); end if;
  if p !~ '^[0-9]{2}$' then
    raise exception 'Un préfixe : les deux chiffres qui suivent « 01 » (par exemple 97 pour 01 97…)';
  end if;
  if o = '' then
    delete from public.prefixes_operateurs x where x.prefixe = p;
    return jsonb_build_object('prefixe', p, 'operateur', null);
  end if;
  if o not in ('MTN', 'MOOV', 'CELTIIS') then
    raise exception 'Opérateur inconnu : MTN, Moov ou Celtiis';
  end if;
  insert into public.prefixes_operateurs as x (prefixe, operateur, modifie_le)
  values (p, o, now())
  -- La contrainte par son nom : « prefixe » est aussi le nom du paramètre,
  -- et « on conflict (prefixe) » serait ambigu pour plpgsql.
  on conflict on constraint prefixes_operateurs_pkey
  do update set operateur = excluded.operateur, modifie_le = now();
  return jsonb_build_object('prefixe', p, 'operateur', o);
end $$;
revoke all on function public.regler_prefixe_operateur(text, text) from public, anon, authenticated;
grant execute on function public.regler_prefixe_operateur(text, text) to authenticated;
