# BIZZOO sur App Store Connect

Préparation du 29 septembre 2026 pour le compte Apple Developer WINNER MARKET LIFE
(équipe `M57V85Y92Z`). Les deux applications sont gratuites et présentent une
place de marché au Bénin.

| Champ | BIZZOO | BIZZOO Admin |
|---|---|---|
| Nom | BIZZOO | BIZZOO Admin |
| Plateforme | iOS | iOS |
| Langue principale | Français | Français |
| Bundle ID | `com.impactinformatique.client` | `com.impactinformatique.admin` |
| Apple app ID | `6817267737` | `6817268373` |
| SKU enregistré | `WML-BIZZOO-IOS` | `WML-BIZZOO-ADMIN-IOS` |
| Catégorie principale | Shopping | Business |
| Version / build sélectionné | 3.54.1 / 97 | 3.54.1 / 97 |
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

- Assistance :
  `https://hospiceantonio.github.io/impact-informatique-app/legal/mentions-legales.html`
  (coordonnées publiques vérifiées sur cette page)
- Site commercial : `https://www.bizzoomarket.com/`
- E-mail public : `contact@bizzoomarket.com`
- Politique de confidentialité :
  `https://hospiceantonio.github.io/impact-informatique-app/legal/confidentialite.html`
- Suppression de compte :
  `https://hospiceantonio.github.io/impact-informatique-app/legal/suppression-compte.html`
- Copyright saisi : `2026 MATERIEL NET SARL`, en tant qu'exploitant identifié
  au RCCM. La cession éventuelle des droits logiciels n'est pas établie par
  cette seule pièce et doit être conservée dans le dossier contractuel privé.
- Contact App Review saisi : Hospice SOETONVE,
  `contact@bizzoomarket.com`, `+2290142323238`.

## Fichiers prêts

Les fichiers signés et les captures sont générés sous `ios/build/2026-09-29/`
et volontairement exclus de Git.

| Application | IPA | Capture iPhone 6,9 pouces | Capture iPad 13 pouces |
|---|---|---|---|
| BIZZOO | `client-b97/Bizzoo.ipa` | `client/iphone-17-pro-max-store.jpg` | `client/ipad-pro-13-store.jpg` |
| BIZZOO Admin | `admin-b97/BizzooAdmin.ipa` | `admin-final/iphone-17-pro-max-store.jpg` | `admin-final/ipad-pro-13-store.jpg` |

Les captures JPEG n'ont pas de canal alpha et mesurent respectivement
1320 × 2868 et 2064 × 2752 pixels.

Le 29 septembre, les deux IPA 97 ont passé `xcrun altool --validate-app` sans
erreur, puis l'upload Apple a réussi. Les builds sont traités en état `VALID`,
admissibles à l'App Store, et sélectionnés dans leur version 3.54.1 :
`6538e3cb-0db6-4924-a2c7-45654dda798f` pour BIZZOO et
`5720ee4c-49fd-428d-a4bb-a6d4b3786119` pour BIZZOO Admin. Les deux
archives et les IPA exportés ont une signature valide, `CFBundleVersion=97` et
embarquent les ressources finales de modération des avis et fiches ainsi que
la politique de confidentialité corrigée. La déclaration d'usage d'IDFA est
`false` pour les deux. Les quatre captures Apple, iPhone 6,9 pouces et iPad
13 pouces pour chaque app, sont téléversées et en état `COMPLETE`.

Les builds 96, antérieurs à ces corrections, restent dans l'historique Apple
mais ne sont plus sélectionnés pour la soumission.

Les fiches contiennent leurs catégories, sous-titres, descriptions en français,
mots-clés, liens de support et de politique de confidentialité. Les deux apps
sont gratuites (`customerPrice` 0,0) avec le Bénin comme seul territoire
disponible ; les nouveaux territoires ne s'ajoutent pas automatiquement.
Les contacts App Review sont enregistrés pour les deux versions. Apple requiert
les identifiants de démonstration pour les fonctions protégées. Ceux du compte
client ont été saisis depuis un fichier local protégé, hors dépôt ; le compte
Admin a été activé dans un profil isolé rattaché à une boutique de démonstration
fermée. QA a validé l'authentification et les restrictions RLS, puis ses
identifiants ont été transmis à Apple depuis un fichier local protégé. Le
parcours graphique connecté dans l'app reste à vérifier ; les captures Admin
actuelles montrent l'écran de connexion.
Les 24 réponses de classification par âge sont enregistrées pour chaque app ;
Apple retourne `FOUR_PLUS` pour les deux. Les contrats gratuits et payants du
compte WINNER MARKET LIFE ont été vérifiés actifs jusqu'au 17 juin 2027,
sans nouvelle acceptation.

## Soumission App Store Connect

Le 29 septembre, les questionnaires de confidentialité ont été publiés dans
App Store Connect pour les deux applications. Ils comportent chacun 11 types de
données liés à l'identité, sans suivi déclaré. Les finalités sont le
fonctionnement de l'app et, pour les interactions client, la personnalisation.
Les réponses doivent rester cohérentes avec les traitements documentés dans
`docs/audit-confidentialite.md` :

- BIZZOO : nom, e-mail, téléphone, adresse physique, informations de paiement,
  emplacement précis, assistance client, autre contenu utilisateur, identifiant
  utilisateur, historique d'achats et interaction avec le produit.
- BIZZOO Admin : nom, e-mail, téléphone, adresse physique, emplacement précis,
  photos ou vidéos, assistance client, autre contenu utilisateur, identifiant
  utilisateur, historique d'achats et autres données d'utilisation.

La déclaration de droits sur les contenus est `USES_THIRD_PARTY_CONTENT` pour
les deux applications. Elle reflète les fiches des marchands et les conditions
qui leur demandent de disposer des droits nécessaires ; elle ne constitue pas
un audit de chaque contenu publié. La classification par âge et la déclaration
de chiffrement des builds sont également renseignées.

**BIZZOO client est soumis à App Review.** La version 3.54.1, build 97, a été
ajoutée au brouillon `c49041b4-e9d0-4203-bfd8-e737361e011c`. L'API
officielle, relue après soumission, donne une date de soumission
`2026-09-29T11:15:48.446Z` et l'état `WAITING_FOR_REVIEW`.

**BIZZOO Admin est aussi soumis à App Review.** Le compte de démonstration a
été renseigné hors dépôt dans les détails de revue. Le préflight Apple a
accepté la version 3.54.1, build 97, dans le brouillon
`9a3a16c3-a223-454d-80c8-ea039811ada9`. L'API officielle, relue après
soumission, donne la date `2026-09-29T14:01:38.485Z` et l'état
`WAITING_FOR_REVIEW`. Cet état atteste l'envoi, pas une approbation par Apple.

Le compte vendeur Apple est WINNER MARKET LIFE, alors que l'exploitant indiqué
par le RCCM est MATERIEL NET SARL. Une autorisation de distribution entre les
deux entités doit être conservée.

## Retour App Review et correctif du 2 octobre 2026

Apple a rejeté les deux builds 97 pour la règle 2.1(a), *App Completeness* :
les applications se ferment dès le lancement sous iOS/iPadOS 27.0. Le dossier
BIZZOO cite un iPhone 17 Pro Max et un iPad Air 11 pouces (M3) ; le dossier
BIZZOO Admin cite un iPad Pro 11 pouces (M4). Avant le correctif, les deux
soumissions étaient en état `UNRESOLVED_ISSUES` et leurs versions en état `REJECTED`.

Les quatre rapports de crash joints par Apple concordent : `EXC_BREAKPOINT`
(`SIGTRAP`) sur le thread principal, dans
`___UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption_block_invoke`,
avant l'exécution du contrôleur WebKit. Le build 97 Admin a reproduit ce crash
sur un simulateur iPadOS 27.0. La note technique Apple
[TN3187](https://developer.apple.com/documentation/technotes/tn3187-migrating-to-the-uikit-scene-based-life-cycle)
confirme l'obligation d'adopter le cycle de vie `UIScene` pour les applications
compilées avec le SDK iOS 27. Le wrapper partagé déclare désormais une
configuration de scène unique et crée sa fenêtre depuis `UIWindowScene`.

Le projet est préparé en version 3.54.1, build 98, avec deux schémas Xcode
partagés. Les builds locaux corrigés ont démarré sur un iPhone 17 Pro Max
iOS 27.0 pour BIZZOO et un iPad Pro 11 pouces (M5) iPadOS 27.0 pour BIZZOO
Admin ; les écrans d'accueil ou de connexion sont visibles, sans nouveau crash
au lancement. Les archives signées sont dans `ios/build/2026-10-02/` :
`Bizzoo-3.54.1-b98.xcarchive` et `BizzooAdmin-3.54.1-b98.xcarchive`.
Leurs identifiants, versions, manifestes `UIScene` et signatures ont été vérifiés.
Les IPA exportés et vérifiés se trouvent dans `ios/build/2026-10-02/admin-b98/`
et `ios/build/2026-10-02/client-b98/`. Les configurations embarquées ne pointent
pas vers `localhost`.

Les deux IPA ont passé la validation distante Apple sans erreur, puis ont été
téléversés le 2 octobre 2026. Leur traitement est terminé : état `VALID`,
admissibilité `APP_STORE_ELIGIBLE`, chiffrement non exempté déclaré absent.

| Application | Identifiant du build 98 | Soumission après correctif |
|---|---|---|
| BIZZOO | `13e1728e-996e-42de-b96f-2145ece6f3a5` | `c49041b4-e9d0-4203-bfd8-e737361e011c`, le 2 octobre à 10 h 55 (GMT+1) |
| BIZZOO Admin | `ea466368-10b7-48be-adb3-dbc10519f5f1` | `9a3a16c3-a223-454d-80c8-ea039811ada9`, le 2 octobre à 10 h 53 (GMT+1) |

Les builds 98 remplacent les builds rejetés dans les deux soumissions. Les
remarques de revue expliquent le correctif `UIScene`, les essais sur simulateur
et l'utilisation des comptes de démonstration. Les deux consoles affichent
**En attente de vérification**. La publication automatique après approbation
reste activée. Cet état confirme la soumission, pas l'approbation ni une fiche
publique. Aucun message distinct n'a été envoyé à l'équipe Apple.

L'API App Store Connect confirme `WAITING_FOR_REVIEW` pour les deux versions
et la correspondance exacte des identifiants de revue avec le dossier privé.
Les mots de passe ne sont pas copiés dans ce document ni dans les preuves.

Preuves locales : `docs/publication-evidence/2026-10-02/apple-client-b98.jpg`
et `apple-admin-b98.jpg`.
