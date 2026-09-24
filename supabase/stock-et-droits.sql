-- =========================================================
-- BIZZOO — le stock jamais négatif, et quatre portes refermées
--
-- À exécuter UNE FOIS dans Supabase :
--   Dashboard → SQL Editor → New query → coller tout → Run.
-- Se rejoue sans dommage.
--
-- CE QUE ÇA CORRIGE. Le bilan de santé de la base en ligne a
-- trouvé deux écarts avec schema.sql. Rien de cassé : deux
-- garde-fous absents.
--
--   1. LE STOCK N'AVAIT PAS SA RÈGLE. Une base créée d'un coup
--      refuse un stock négatif (« produits_stock_check ») ; une
--      base en service a reçu la colonne après coup, sans la
--      règle. L'application n'écrit jamais de stock négatif — la
--      base le garantit désormais aussi.
--
--   2. QUATRE ACTIONS D'ADMINISTRATION RESTAIENT APPELABLES SANS
--      COMPTE : supprimer un compte, changer un mot de passe,
--      approuver ou refuser une demande. Chacune vérifie, au
--      dedans, que l'appelant en a le droit — un visiteur était
--      donc refusé. Mais Supabase accorde chaque fonction à
--      « anon » nommément, et « retirer à public » ne lui
--      retirait rien. La porte se ferme maintenant avant même
--      le contrôle, comme pour les autres actions de l'admin.
--
--      Les fonctions que le client appelle SANS compte — passer
--      commande, suivre une commande, signaler un paiement,
--      essayer un code promo — restent ouvertes : c'est voulu.
-- =========================================================

-- 1. Le stock. D'abord ce qui violerait la règle — une boutique n'a pas
--    « moins deux » pièces —, puis la règle, sous le nom qu'elle porte
--    sur une base neuve.
update public.produits set stock = 0 where stock < 0;
do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.produits'::regclass
                    and conname = 'produits_stock_check') then
    alter table public.produits add constraint produits_stock_check check (stock >= 0);
  end if;
end $$;

-- 2. Les quatre portes : fermées aux visiteurs, ouvertes à l'équipe
--    connectée — c'est la fonction qui décide ensuite qui peut quoi.
revoke all on function public.supprimer_compte(uuid) from public, anon;
revoke all on function public.changer_mot_de_passe(uuid, text) from public, anon;
revoke all on function public.approuver_demande(text) from public, anon;
revoke all on function public.refuser_demande(text, text) from public, anon;
grant execute on function public.supprimer_compte(uuid) to authenticated;
grant execute on function public.changer_mot_de_passe(uuid, text) to authenticated;
grant execute on function public.approuver_demande(text) to authenticated;
grant execute on function public.refuser_demande(text, text) to authenticated;

-- Vérification : la règle posée, aucun stock négatif, les quatre
-- fermées aux visiteurs et ouvertes à l'équipe.
select
  exists (select 1 from pg_constraint
           where conrelid = 'public.produits'::regclass
             and conname = 'produits_stock_check')                  as "Stock gardé",
  (select count(*) from public.produits where stock < 0)            as "Stocks négatifs",
  (select count(*)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('supprimer_compte', 'changer_mot_de_passe',
                        'approuver_demande', 'refuser_demande')
      and has_function_privilege('anon', p.oid, 'EXECUTE'))         as "Ouvertes aux visiteurs (0)",
  (select count(*)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('supprimer_compte', 'changer_mot_de_passe',
                        'approuver_demande', 'refuser_demande')
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')) as "Ouvertes à l'équipe (4)";
