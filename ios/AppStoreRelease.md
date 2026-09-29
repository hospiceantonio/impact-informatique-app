# BIZZOO sur App Store Connect

Préparation du 29 septembre 2026 pour le compte Apple Developer WINNER MARKET LIFE
(équipe `M57V85Y92Z`). Les deux applications sont gratuites et proposent des
biens physiques.

| Champ | BIZZOO | BIZZOO Admin |
|---|---|---|
| Nom | BIZZOO | BIZZOO Admin |
| Plateforme | iOS | iOS |
| Langue principale | Français | Français |
| Bundle ID | `com.impactinformatique.client` | `com.impactinformatique.admin` |
| SKU proposé | `WML-BIZZOO-IOS` | `WML-BIZZOO-ADMIN-IOS` |
| Catégorie principale | Shopping | Business |
| Version / build | 3.54.1 / 96 | 3.54.1 / 96 |
| Sous-titre | Vos boutiques, au même endroit | Gérez boutiques et commandes |
| Mots-clés | boutiques,achats,produits,commandes,promotions,commerce,Bénin | boutique,gestion,catalogue,produits,commandes,livraisons,Bénin |

## Présentation BIZZOO

BIZZOO réunit les boutiques et leurs produits dans une seule application.
Parcourez les catalogues par catégorie, recherchez un article et retrouvez vos
favoris. Consultez les nouveautés et les informations de chaque boutique avant
de commander.

Préparez votre panier et passez commande selon les options proposées par la
boutique. Les paiements pour les produits physiques peuvent être effectués par
Mobile Money. Vous pouvez aussi contacter la boutique via WhatsApp lorsque ce
parcours est proposé. Certaines informations déjà consultées restent disponibles
hors connexion.

## Présentation BIZZOO Admin

BIZZOO Admin est l'espace de gestion réservé aux gérants et aux équipes
autorisées du réseau BIZZOO. Gérez les boutiques, les produits, les catégories,
les photos et vidéos du catalogue. Consultez les commandes et les livraisons
selon les droits accordés à votre compte.

L'accès nécessite un compte BIZZOO Admin attribué par l'exploitant.

## Liens et contacts

- Assistance : `https://www.bizzoomarket.com/`
- E-mail public : `contact@bizzoomarket.com`
- Politique de confidentialité :
  `https://hospiceantonio.github.io/impact-informatique-app/legal/confidentialite.html`
- Suppression de compte :
  `https://hospiceantonio.github.io/impact-informatique-app/legal/suppression-compte.html`
- Copyright proposé : `© 2026 MATERIEL NET SARL` ; confirmer la titularité
  des droits avant saisie définitive.
- Contact de revue communiqué par l'exploitant : `bizzoomarket@gmail.com`,
  `0142323238`. Vérifier le nom et le format international du numéro avant
  saisie dans les champs Apple.

## Fichiers prêts

Les fichiers signés et les captures sont générés sous `ios/build/2026-09-29/`
et volontairement exclus de Git.

| Application | IPA | Capture iPhone 6,9 pouces | Capture iPad 13 pouces |
|---|---|---|---|
| BIZZOO | `client/Bizzoo.ipa` | `client/iphone-17-pro-max-store.jpg` | `client/ipad-pro-13-store.jpg` |
| BIZZOO Admin | `admin-final/BizzooAdmin.ipa` | `admin-final/iphone-17-pro-max-store.jpg` | `admin-final/ipad-pro-13-store.jpg` |

Les captures JPEG n'ont pas de canal alpha et mesurent respectivement
1320 × 2868 et 2064 × 2752 pixels.

## Étapes App Store Connect restantes

1. Reconnecter le compte Apple dans Chrome, puis vérifier **Business >
   Agreements**. Ne signer aucun nouveau contrat sans autorisation spécifique.
2. Créer les deux fiches iOS avec les Bundle IDs déjà enregistrés, les SKU
   ci-dessus et le français comme langue principale.
3. Valider puis téléverser les IPA. Attendre que les builds 3.54.1 (96) soient
   traités et sélectionner chacun dans sa version App Store.
4. Saisir les présentations, liens, catégorie, captures et prix gratuit.
   Définir les pays de disponibilité demandés ; le Bénin est le marché initial
   cohérent avec l'application.
5. Compléter les questionnaires Apple sur la confidentialité, l'âge, les droits
   sur les contenus, le chiffrement et le statut de professionnel pour les pays
   de l'UE si ceux-ci sont sélectionnés. Les réponses doivent correspondre aux
   traitements documentés dans `docs/audit-confidentialite.md`.
6. Fournir à Apple un compte de revue BIZZOO Admin opérationnel hors dépôt et
   des instructions suffisantes pour atteindre la gestion après connexion.
7. Contrôler les alertes de chaque fiche, puis soumettre les deux versions à
   App Review. Vérifier le statut **Waiting for Review** ou son équivalent,
   sans présenter un simple téléversement comme une soumission.

Le compte vendeur Apple est WINNER MARKET LIFE, alors que l'exploitant indiqué
par le RCCM est MATERIEL NET SARL. Une autorisation de distribution entre les
deux entités doit être conservée.
