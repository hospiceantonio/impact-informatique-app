-- =========================================================
-- BIZZOO 4.2.0 — Plus rien de l'ancienne charte dans les couleurs
--
--   Les boutiques et les catégories restées à un ancien bleu de BIZZOO
--   passent au turquoise de BIZZOO Market (#007F7C), et c'est désormais
--   la couleur d'une boutique ou d'une catégorie créée sans en choisir.
--
-- À coller dans Supabase → SQL Editor → New query → Run. Relançable.
-- =========================================================

-- Une boutique ou une catégorie créée sans couleur prend le turquoise de
-- BIZZOO Market, et plus un ancien bleu.
alter table public.boutiques  alter column couleur set default '#007F7C';
alter table public.categories alter column couleur set default '#007F7C';

-- Celles qui portent encore un ancien bleu de BIZZOO passent au
-- turquoise : #2550B7 (3.53 à 3.81), #0B5CF5 et #1176D8 (les couleurs
-- par défaut d'avant), #0047D9 (la première charte). Les couleurs que les
-- boutiques ont choisies elles-mêmes (orange, vert, violet…) ne bougent
-- pas. Relançable : la seconde fois, il n'y a plus rien à changer.
update public.boutiques  set couleur = '#007F7C'
 where upper(couleur) in ('#2550B7', '#0B5CF5', '#1176D8', '#0047D9');
update public.categories set couleur = '#007F7C'
 where upper(couleur) in ('#2550B7', '#0B5CF5', '#1176D8', '#0047D9');
