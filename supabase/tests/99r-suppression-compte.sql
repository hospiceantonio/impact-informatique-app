begin;
select essai.verifie(not has_function_privilege('anon', 'public.supprimer_mon_compte(text)', 'execute'), 'Un visiteur ne peut pas supprimer un compte');
insert into auth.users(id,email,raw_user_meta_data) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1','effacement@bizzoo.invalid','{"compte":"client"}'),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2','autre@bizzoo.invalid','{"compte":"client"}'),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3','signalant@bizzoo.invalid','{"compte":"client"}');
insert into public.clients(id,nom,tel) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1','Compte à supprimer','0199990001'),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2','Autre compte','0199990002'),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3','Signalant à supprimer','0199990003') on conflict(id) do nothing;
insert into public.commandes(id,client_id,client_nom,client_tel)
values ('suppression-test','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1','Compte à supprimer','0199990001');
insert into public.avis(id,client_id,boutique_id,note,texte,auteur) values
 ('suppression-avis-auteur','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
  'bou_informatique',4,'Commande reçue','Compte à supprimer'),
 ('suppression-avis-signalant','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',
  'bou_informatique',3,'Livraison correcte','Autre compte');
insert into public.produits(id,boutique_id,nom,prix)
values ('suppression-produit-signalement','bou_informatique','Produit à examiner',1000)
on conflict (id) do nothing;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',true);
set local role authenticated;
select public.signaler_avis('suppression-avis-auteur','avis','autre','À examiner');
reset role;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3',true);
set local role authenticated;
select public.signaler_avis('suppression-avis-signalant','auteur','spam','À examiner');
select public.signaler_produit('suppression-produit-signalement','trompeur','À examiner');
select public.supprimer_mon_compte('SUPPRIMER');
reset role;
select essai.verifie(not exists(select 1 from public.avis_signalements
    where signale_par='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3'),
    'Supprimer le signalant efface son signalement');
select essai.verifie(not exists(select 1 from public.produits_signalements
    where signale_par='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3'),
    'Supprimer le signalant efface son signalement de fiche');
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
set local role authenticated;
select public.bloquer_auteur_avis('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
                                  true, 'Abus répétés');
reset role;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',true);
set local role authenticated;
select essai.refuse($q$select public.supprimer_mon_compte('NON')$q$, 'La confirmation est obligatoire');
select public.supprimer_mon_compte('SUPPRIMER');
reset role;
select essai.verifie(not exists(select 1 from auth.users where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'), 'Le titulaire est supprimé');
select essai.verifie(not exists(select 1 from public.clients where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'), 'Le profil est supprimé en cascade');
select essai.verifie(not exists(select 1 from public.avis_signalements
    where auteur_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
       or avis_id='suppression-avis-auteur'),
    'Supprimer l’auteur efface les signalements de son avis');
select essai.verifie(not exists(select 1 from public.avis_auteurs_bloques
    where client_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'),
    'Supprimer l’auteur efface la sanction de publication');
select essai.verifie(exists(select 1 from auth.users where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'), 'Un autre compte reste intact');
select essai.verifie(exists(select 1 from public.commandes where id='suppression-test' and client_id is null and compte_supprime), 'La pièce commerciale reste détachée et verrouillée');
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2',true);
-- Une vérification par SMS passe par auth.users, puis son déclencheur
-- synchronise le profil. Le test ne force pas le drapeau tel_verifie.
update auth.users set phone='+2290199990001', phone_confirmed_at=now()
where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2';
set local role authenticated;
select essai.verifie(public.rattacher_mes_commandes()=0, 'Un numéro réutilisé ne récupère pas la commande supprimée');
reset role;
rollback;
