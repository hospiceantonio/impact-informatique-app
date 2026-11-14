-- =========================================================
-- BIZZOO 4.4.0 — Le client annule une commande qu'il n'a pas payée
--
--   Un client lance une commande, le paiement échoue (solde insuffisant,
--   demande refusée) : la commande restait « En attente » pour toujours,
--   et rien ne permettait de l'annuler. Le client l'annule désormais
--   lui-même, depuis son reçu.
--
--   C'est l'Edge Function « feexpay » qui appelle cette fonction, APRÈS
--   avoir demandé à FeexPay qu'aucun versement ne soit en cours ni arrivé
--   pour cette commande. L'application ne l'appelle jamais : elle est
--   fermée à « anon » comme à « authenticated ».
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- « reference_vue » : la référence de paiement que l'Edge Function a
-- vérifiée chez FeexPay. Si une nouvelle demande est partie entre-temps
-- (le client a touché « Réessayer » dans un autre onglet), la référence a
-- changé : on n'annule pas, la nouvelle demande peut aboutir.
--
-- Seule une commande « à payer » s'annule ici. Ni le stock ni les
-- notifications ne bougent : ils ne suivent que le paiement. Les lignes
-- restent telles quelles : si un versement arrivait malgré tout plus tard
-- (une demande restée en attente chez l'opérateur), « marquer_payee »
-- remettrait la commande à « payée », entière — l'argent d'un client ne
-- se perd jamais dans une commande annulée.
create or replace function public.annuler_commande_impayee(cible text, reference_vue text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.commandes%rowtype;
begin
  select * into c from public.commandes where id = coalesce(cible, '') for update;
  if not found then
    return jsonb_build_object('ok', false, 'raison', 'introuvable');
  end if;
  if c.etat = 'annulee' then
    return jsonb_build_object('ok', true, 'deja', true, 'numero', c.numero);
  end if;
  if c.etat <> 'a_payer' then
    return jsonb_build_object('ok', false, 'raison', 'etat', 'etat', c.etat, 'numero', c.numero);
  end if;
  if coalesce(c.fournisseur_ref, '') <> coalesce(reference_vue, '') then
    return jsonb_build_object('ok', false, 'raison', 'nouvelle demande', 'numero', c.numero);
  end if;

  -- La base écrit pour elle-même : « commande_verrous » réserve sinon le
  -- changement d'état à l'équipe.
  perform set_config('bizzoo.interne', 'oui', true);
  update public.commandes
     set etat = 'annulee',
         remarque = 'Annulée par le client avant paiement, le '
                    || to_char(now() at time zone 'Africa/Porto-Novo', 'DD/MM/YYYY à HH24:MI') || '.'
   where id = c.id;
  return jsonb_build_object('ok', true, 'numero', c.numero);
end $$;
revoke all on function public.annuler_commande_impayee(text, text) from public, anon, authenticated;
grant execute on function public.annuler_commande_impayee(text, text) to service_role;
