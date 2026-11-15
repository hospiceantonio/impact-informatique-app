-- =========================================================
-- BIZZOO 4.4.0 — Plus d'orange dans les couleurs des boutiques
--
--   La charte lumineuse de BIZZOO Market n'a plus d'orange (« pas
--   d'orange », dit la direction artistique), et l'admin ne le propose
--   plus pour une boutique ni pour une catégorie. Celles qui le portent
--   encore — l'orange de l'ancienne charte (#F96302) et l'ocre (#9A6B00) —
--   passent au turquoise de la palette (#0B7C8C). Les autres couleurs
--   choisies (rouge, vert, violet…) ne bougent pas.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable : la
-- seconde fois, il n'y a plus rien à changer.
-- =========================================================
update public.boutiques  set couleur = '#0B7C8C' where upper(couleur) in ('#F96302', '#9A6B00');
update public.categories set couleur = '#0B7C8C' where upper(couleur) in ('#F96302', '#9A6B00');
