# BIZZOO : confrontation du code et des mentions

Audit du 26 septembre 2026. Exploitant identifié par l'extrait RCCM transmis :
MATERIEL NET SARL. Le document original, les données de naissance et l'adresse
personnelle du gérant ne sont pas destinés au site ni aux stores.

| Traitement constaté | Source | Mention nécessaire |
|---|---|---|
| E-mail ou téléphone, authentification, profil client ou équipe | `client/js/compte.js`, `admin/js/supabase.js`, tables `clients`, `profils` | Connexion et gestion des accès ; sessions conservées sur l'appareil |
| Coordonnées, note de commande, montants et références de paiement | `commandes`, `commande_lignes`, `client/js/paiement.js` | Commande, paiement, livraison ; transmission aux boutiques, livreurs et opérateurs concernés |
| FeexPay ou KkiaPay selon configuration | `supabase/functions/feexpay/`, `client/js/paiement.js` | Prestataires de paiement externes ; aucune saisie du code secret Mobile Money dans BIZZOO |
| Codes de connexion par SMS | `supabase/functions/_partage/sms.ts` | Numéro transmis au service SMS CREATIS INTER ; activation réelle à vérifier |
| Position facultative du commerce | `client/js/compte.js`, `admin/js/vues/reglages.js` | Localisation ponctuelle demandée par l'utilisateur, sans suivi continu établi par l'audit |
| Photos et vidéos de catalogue | Stockage public `produits` | Contenus destinés à être publics ; ne pas déposer de document personnel dans les photos du catalogue |
| Favoris, adresses, avis, réclamations et messages | Tables correspondantes de `supabase/schema.sql` | Personnalisation, avis et SAV ; accès selon le rôle |
| Historique des opérations, anciennes valeurs pour annulation | Table `journal`, champ `retour` | Traçabilité métier ; certaines anciennes données peuvent subsister dans l'historique |
| Cache de catalogue, panier, coordonnées, sessions | `localStorage` et service workers | Stockage technique sur l'appareil ; nettoyage après suppression de compte |
| Supabase en `eu-west-1` | Tableau de bord observé | Hébergement de données en Irlande, transfert hors du Bénin |

## Durées proposées pour validation opérationnelle

Ces durées sont des propositions de gestion. Le code audité ne comporte pas
de purge générale fondée sur l'ancienneté. Ne pas présenter cette purge comme
déjà active ni déclarer une certification APDP inexistante.

- Compte et préférences : jusqu'à suppression du compte, avec revue des
  comptes inactifs après 24 mois.
- Commandes abandonnées ou échouées : 90 jours, sauf contestation en cours.
- Pièces commerciales et comptables : 10 ans à compter de la clôture de
  l'exercice concerné, sous réserve de confirmation du régime applicable.
- Historique technique et demandes de support : 12 mois après résolution,
  hors litige ou obligation de conservation documentée.
- Sauvegardes : suivre la durée configurée chez le prestataire ; vérifier
  cette durée avant de promettre une disparition de toutes les copies.

La politique publiée doit distinguer les données supprimées du compte des
commandes et traces métier conservées, et indiquer les critères appliqués.
Le support doit tenir un registre des demandes et justifier toute rétention.

## Écarts de publication à lever

- IFU absent de l'extrait fourni ; ne pas en inventer.
- Hébergeur du site `bizzoomarket.com` non identifié dans le dépôt, distinct
  de Supabase. Ses coordonnées restent à compléter dans les mentions.
- Vérifier la réception des messages sur `contact@bizzoomarket.com`.
- Documenter les formalités APDP et les garanties des transferts ; aucune
  preuve de déclaration, autorisation ou certification n'a été fournie.
- Les stores afficheront WINNER MARKET LIFE comme vendeur/développeur du
  compte. Conserver une autorisation de MATERIEL NET pour cette distribution.
- Ne pas annoncer une fonctionnalité médicale, financière ou de voyage sur
  les fiches tant que ses parcours et obligations ne sont pas évalués.

## Références

- [Code du numérique publié par l'APDP](https://apiprod.apdp.bj/storage/c46ab3f55e93d40c8545b70add0ea8c7/CODE-DU-NUMERIQUE-DU-BENIN_2018-version-APDP.pdf)
- [Information et confidentialité APDP](https://service.apdp.bj/mise_en_conformite/politique_de_confidentialite)
- [Suppression des comptes Apple](https://developer.apple.com/fr/support/offering-account-deletion-in-your-app/)
- [Suppression des comptes Google Play](https://support.google.com/googleplay/android-developer/answer/13327111?hl=fr)
