-- =========================================================
-- BIZZOO 3.72.0 — Le nom du compte MoMo d'un livreur
--
--   À la création d'un livreur, l'équipe note le nom du titulaire du
--   compte Mobile Money qui recevra ses gains. Avant chaque reversement,
--   BIZZOO vérifie que MoMo affiche bien ce nom (Admin → Reversements).
--   Le livreur ne peut pas le changer lui-même : sa fiche ne lui est pas
--   ouverte en écriture.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

alter table public.profils add column if not exists momo_nom text not null default '';
alter table public.profils drop constraint if exists profils_momo_nom;
alter table public.profils add constraint profils_momo_nom check (length(momo_nom) <= 80);
