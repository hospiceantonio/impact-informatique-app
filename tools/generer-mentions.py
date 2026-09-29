#!/usr/bin/env python3
"""Génère les pages légales depuis l'identité professionnelle documentée."""
import html
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
profil = json.loads((ROOT / 'docs/profil-bizzoo.json').read_text())
e = lambda key: html.escape(profil[key])
identite = f"<p>BIZZOO est exploité par <strong>{e('raison_sociale')} {e('forme')}</strong>, au capital de {e('capital')}, immatriculée au RCCM {e('rccm')}. Siège : {e('siege')}. Gérant : {e('gerant')}.</p>"
contact = '<p>Contact : <a href="mailto:contact@bizzoomarket.com">contact@bizzoomarket.com</a>. Contact complémentaire : <a href="mailto:bizzoomarket@gmail.com">bizzoomarket@gmail.com</a>. Téléphone : <a href="tel:+2290142323238">+229 01 42 32 32 38</a>.</p>'
pages = {
 'mentions-legales': ('Mentions légales', identite + contact +
   '<h2>Les intervenants</h2><p>Le développement des applications est assuré par CREATIS INTER. Le compte utilisé pour leur distribution sur les stores est celui de WINNER MARKET LIFE. L’exploitation de la marketplace relève de MATERIEL NET.</p>' +
   '<h2>Données et contenus</h2><p>Les données applicatives sont hébergées avec Supabase, dans la région Irlande (eu-west-1). Les catalogues des boutiques et leurs médias sont destinés à être publics. Les marques et contenus restent soumis aux droits de leurs titulaires. Pour signaler un contenu ou exercer vos droits, utilisez le contact ci-dessus.</p>'),
 'confidentialite': ('Politique de confidentialité', identite + contact +
   '<h2>Champ d’application</h2><p>Cette politique concerne BIZZOO, BIZZOO Admin et le site bizzoomarket.com : consultation de catalogues, achats, exploitation des boutiques, livraisons et service après-vente.</p>' +
   '<h2>Données et finalités</h2><ul><li>Compte : e-mail ou téléphone, identifiant, nom, mot de passe traité par le service d’authentification, rôle et habilitations.</li><li>Commandes : articles, quantités, montants, coordonnées de livraison, notes et références de paiement, pour préparer, payer et livrer vos achats.</li><li>Préférences : favoris, boutiques suivies et adresses enregistrées.</li><li>Avis et SAV : notes, avis, réclamations et messages associés aux commandes.</li><li>Professionnels : coordonnées de boutique, catalogue, photos, vidéos, stocks et historique des opérations.</li><li>Localisation : position du commerce relevée seulement lorsque vous choisissez cette fonction. Vous pouvez refuser et saisir une adresse.</li></ul>' +
   '<h2>Destinataires et prestataires</h2><p>Les boutiques, livreurs et personnes habilitées accèdent aux informations nécessaires à leurs missions. Supabase assure les services de base de données, authentification et stockage, avec la base située en Irlande. Selon la configuration de BIZZOO, le paiement est traité par FeexPay ou KkiaPay et les codes SMS par le service CREATIS INTER. Les références de transaction sont conservées pour le suivi des paiements. Ne communiquez jamais votre code secret Mobile Money à BIZZOO.</p>' +
   '<p>Les liens vers WhatsApp, les réseaux sociaux et les cartes ouvrent des services tiers soumis à leurs propres politiques. Les photos et vidéos de catalogue sont publiques : n’y déposez pas de pièce d’identité ou de document confidentiel.</p>' +
   '<h2>Stockage sur votre appareil</h2><p>Les applications conservent localement des éléments techniques : session de connexion, catalogue, panier, préférences et certaines coordonnées. Cela permet de retrouver votre session et de consulter le catalogue déjà chargé hors connexion. Une connexion reste nécessaire pour commander, payer et synchroniser les données. Les notifications peuvent être désactivées dans les réglages de votre appareil.</p>' +
   '<h2>Conservation et suppression</h2><p>Votre profil et vos préférences sont conservés tant que votre compte existe. La suppression du compte efface le profil, les favoris, les adresses enregistrées, les avis et les réclamations associés. Les commandes et traces métier nécessaires à l’exécution des opérations, à la comptabilité ou à la résolution d’un litige restent conservées dans leur périmètre professionnel. Elles ne sont pas réattribuées à un nouveau compte utilisant le même numéro.</p>' +
   '<p>La durée des documents conservés dépend de leur nature et des obligations applicables ; une conservation pour litige prend fin lorsque sa justification cesse. Le support peut vous préciser les documents conservés et le motif applicable à votre demande. Les sauvegardes peuvent contenir des copies résiduelles jusqu’à leur renouvellement par le prestataire ; elles ne doivent pas être utilisées pour réactiver un compte supprimé.</p>' +
   '<h2>Vos droits</h2><p>Vous pouvez demander l’accès, la rectification et la suppression de vos données, ainsi que vous opposer à un usage non nécessaire ou retirer une autorisation facultative. Écrivez au contact ci-dessus sans envoyer de mot de passe ni de code de connexion. Une vérification proportionnée de votre identité peut être nécessaire.</p><p><a href="suppression-compte.html">Supprimer votre compte BIZZOO</a>. Vous pouvez également contacter l’<a href="https://service.apdp.bj/">Autorité de Protection des Données Personnelles du Bénin</a>.</p>'),
 'conditions': ('Conditions d’utilisation', identite + contact +
   '<h2>La marketplace</h2><p>BIZZOO présente les catalogues de boutiques et permet la commande, le paiement et le suivi de livraison. BIZZOO Admin est réservé aux professionnels autorisés. Les droits accessibles dépendent du rôle attribué au compte.</p>' +
   '<h2>Commandes et paiements</h2><p>Vérifiez les articles, le prix, la devise, les coordonnées et les modalités affichées avant de confirmer. Le paiement est confirmé par le prestataire ou par une vérification administrative habilitée. Un simple retour de votre téléphone ne constitue pas une preuve de paiement. La disponibilité et le suivi des articles sont fournis par les boutiques concernées.</p>' +
   '<h2>Usage du compte et contenus</h2><p>Gardez vos identifiants confidentiels. N’utilisez pas le service pour publier des contenus illicites, trompeurs ou portant atteinte aux droits d’autrui. Les professionnels doivent disposer des droits sur leurs contenus et fournir des informations exactes.</p>' +
   '<h2>Assistance et litiges</h2><p>Pour un problème de commande, utilisez le suivi et le service après-vente dans l’application ou contactez BIZZOO. Les présentes conditions ne suppriment aucun droit impératif du consommateur. Les modalités particulières d’une vente doivent être précisées par la boutique et restent soumises au droit applicable.</p>' +
   '<h2>Disponibilité</h2><p>La consultation de certains contenus déjà chargés reste possible hors connexion. Les paiements, connexions et synchronisations dépendent du réseau et des prestataires. Contactez-nous pour toute anomalie.</p>'),
 'suppression-compte': ('Supprimer votre compte BIZZOO',
   '<p>Cette page concerne les comptes BIZZOO et BIZZOO Admin.</p><ol><li>Ouvrez votre application et connectez-vous à votre compte.</li><li>Ouvrez <strong>Mon compte → Vos données et vos droits → Supprimer mon compte</strong>.</li><li>Lisez les conséquences puis confirmez la suppression définitive.</li></ol>' +
   '<p>Sans réinstaller l’application : <a href="__CLIENT_ACCOUNT__">ouvrir mon compte BIZZOO sur le web</a> ou <a href="__ADMIN_ACCOUNT__">mon compte BIZZOO Admin</a>.</p>' +
   '<p>La suppression efface le profil, les favoris, les adresses enregistrées, les avis et les réclamations associés. Les commandes et traces métier nécessaires sont conservées selon les critères décrits dans la <a href="confidentialite.html">politique de confidentialité</a>. Pour le dernier superadministrateur de la plateforme, la responsabilité doit d’abord être transmise à un autre superadministrateur actif.</p>' +
   '<p>Si vous avez perdu l’accès au compte, contactez-nous avec l’adresse ou le numéro utilisé pour vous inscrire. Ne joignez ni mot de passe, ni code SMS. Cette assistance complète le parcours de suppression autonome.</p>' + contact),
}
style = 'body{font:17px/1.65 system-ui,sans-serif;max-width:820px;margin:0 auto;padding:32px 22px 80px;color:#162a43;background:#f8fafc}h1,h2{line-height:1.2}h1{font-size:32px}h2{margin-top:32px;font-size:23px}a{color:#174db0}nav{display:flex;gap:16px;flex-wrap:wrap}li{margin:9px 0}main{background:white;padding:26px;border-radius:18px}footer{margin-top:28px;font-size:14px}'
for dest in (ROOT / 'legal', ROOT / 'client/legal', ROOT / 'admin/legal'):
    dest.mkdir(parents=True, exist_ok=True)
    chemin_compte = {
        ROOT / 'legal': ('../client/#/compte', '../admin/#/compte'),
        ROOT / 'client/legal': ('../#/compte', '../../admin/#/compte'),
        ROOT / 'admin/legal': ('../../client/#/compte', '../#/compte'),
    }[dest]
    for slug, (title, content) in pages.items():
        content = content.replace('__CLIENT_ACCOUNT__', chemin_compte[0]).replace('__ADMIN_ACCOUNT__', chemin_compte[1])
        (dest / f'{slug}.html').write_text(f'<!doctype html><html lang="fr"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{title} | BIZZOO</title><style>{style}</style><nav><a href="../">Retour à BIZZOO</a><a href="confidentialite.html">Confidentialité</a><a href="mentions-legales.html">Mentions légales</a></nav><main><h1>{title}</h1>{content}</main><footer>Version du 29 septembre 2026 · BIZZOO</footer></html>\n')
for app in ('client', 'admin'):
    shutil.copyfile(ROOT / 'tools/droits-compte.js', ROOT / app / 'js/droits-compte.js')
