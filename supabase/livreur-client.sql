-- =========================================================
-- BIZZOO — le client voit qui lui livre sa commande
--
-- Sur le reçu, sous chaque boutique : le nom du livreur à qui elle a
-- confié la course, et deux boutons — l'appeler, lui écrire sur
-- WhatsApp. Visible une fois la commande payée et la course confiée,
-- jusqu'à ce que le client confirme l'avoir reçue.
--
-- Une seule fonction, en lecture. Aucune table ne change, aucune donnée
-- n'est touchée. Le client ne lit toujours pas « profils » : la fonction
-- lui rend le nom et le numéro, rien d'autre.
--
-- À exécuter dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
-- Sans danger : relançable.
-- =========================================================

-- ---------- Qui me livre ----------
-- LE CLIENT VOIT LE NOM ET LE NUMÉRO DU LIVREUR à qui chaque boutique a
-- confié sa part, pour l'appeler ou lui écrire sur WhatsApp. Rien de
-- plus : ni son e-mail, ni ses autres courses.
--
-- À QUI : au compte qui a passé la commande, ou à qui connaît son numéro
-- ET le numéro de téléphone donné à la commande — la même règle que
-- « suivre_commande », pour le client qui a commandé sans compte.
--
-- QUAND : une fois la commande payée, la course confiée, et tant que le
-- client n'a pas confirmé l'avoir reçue. Après, le numéro du livreur n'a
-- plus de raison de rester sous ses yeux. Une part annulée, un livreur
-- désactivé : rien.
--
-- D'OÙ UNE FONCTION : le client ne lit pas « profils », et ne doit pas.
drop function if exists public.livreurs_de_ma_commande(text, text);
create or replace function public.livreurs_de_ma_commande(cible text, tel text default '')
returns table (boutique_id text, nom text, telephone text, indicatif text)
language plpgsql stable security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  tel_donne text := regexp_replace(coalesce(tel, ''), '\D', '', 'g');
begin
  if not exists (
    select 1 from public.commandes c
     where c.id = cible
       and not c.compte_supprime
       and c.etat = 'payee'
       and ((moi is not null and c.client_id = moi)
            or (tel_donne <> '' and c.client_tel = tel_donne))) then
    return;
  end if;
  return query
    select distinct on (l.boutique_id)
           l.boutique_id::text, coalesce(p.nom, '')::text, coalesce(p.tel, '')::text,
           coalesce(nullif(b.indicatif, ''), '229')::text
      from public.commande_lignes l
      join public.profils p
        on p.id = l.livreur_id and p.role = 'livreur' and p.actif
      left join public.boutiques b on b.id = l.boutique_id
     where l.commande_id = cible
       and l.etat <> 'annulee'
       and l.confirme_le is null
     order by l.boutique_id;
end $$;
revoke all on function public.livreurs_de_ma_commande(text, text) from public;
grant execute on function public.livreurs_de_ma_commande(text, text) to anon, authenticated;

