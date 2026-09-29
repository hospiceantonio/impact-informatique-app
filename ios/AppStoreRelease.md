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
| Version / build téléversé | 3.54.1 / 96 | 3.54.1 / 96 |
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
- Copyright : titulaire des droits à confirmer avant saisie dans Apple.
- Contact App Review saisi : Hospice SOETONVE,
  `contact@bizzoomarket.com`, `+2290142323238`.

## Fichiers prêts

Les fichiers signés et les captures sont générés sous `ios/build/2026-09-29/`
et volontairement exclus de Git.

| Application | IPA | Capture iPhone 6,9 pouces | Capture iPad 13 pouces |
|---|---|---|---|
| BIZZOO | `client/Bizzoo.ipa` | `client/iphone-17-pro-max-store.jpg` | `client/ipad-pro-13-store.jpg` |
| BIZZOO Admin | `admin-final/BizzooAdmin.ipa` | `admin-final/iphone-17-pro-max-store.jpg` | `admin-final/ipad-pro-13-store.jpg` |

Les captures JPEG n'ont pas de canal alpha et mesurent respectivement
1320 × 2868 et 2064 × 2752 pixels.

Le 29 septembre, les deux IPA ont passé `xcrun altool --validate-app` sans erreur,
puis l'upload Apple a réussi. Les builds sont traités en état `VALID`, admissibles
à l'App Store, et sélectionnés dans leur version 3.54.1 :
`3b6662fe-4bf4-4d75-bfc2-071e436293e0` pour BIZZOO et
`d7827229-45be-4599-bcd3-03fd22464813` pour BIZZOO Admin. La déclaration
d'usage d'IDFA est `false` pour les deux. Les quatre captures Apple, iPhone
6,9 pouces et iPad 13 pouces pour chaque app, sont téléversées et en état
`COMPLETE`.

Ces builds 96 précèdent la correction de la politique de confidentialité dans
les ressources embarquées. Ils ne doivent pas être soumis à App Review. Un build
97 doit être produit après l'intégration du correctif de signalement des avis
publics, puis validé, téléversé et sélectionné pour chaque application.

Les fiches contiennent leurs catégories, sous-titres, descriptions en français,
mots-clés, liens de support et de politique de confidentialité. Les deux apps
sont gratuites (`customerPrice` 0,0) avec le Bénin comme seul territoire
disponible ; les nouveaux territoires ne s'ajoutent pas automatiquement.
Les contacts App Review sont enregistrés pour les deux versions. Apple requiert
les identifiants de démonstration pour les fonctions protégées. Ceux du compte
client ont été saisis depuis un fichier local protégé, hors dépôt ; le compte
Admin doit encore être activé et testé dans l'application avant sa saisie.
Les 24 réponses de classification par âge sont enregistrées pour chaque app ;
Apple retourne `FOUR_PLUS` pour les deux. Les contrats gratuits et payants du
compte WINNER MARKET LIFE ont été vérifiés actifs jusqu'au 17 juin 2027,
sans nouvelle acceptation.

## Étapes App Store Connect restantes

1. Publier les questionnaires de confidentialité Apple après confirmation au
   moment de l'attestation juridique d'exactitude. Les deux questionnaires sont
   complets, avec 11 types chacun, liés à l'identité et sans suivi déclaré.
   Les finalités sont le fonctionnement de l'app, ainsi que la personnalisation
   pour les interactions client. Les réponses doivent rester cohérentes avec
   les traitements documentés dans `docs/audit-confidentialite.md`.
   - BIZZOO : nom, e-mail, téléphone, adresse physique, informations de
     paiement, emplacement précis, assistance client, autre contenu utilisateur,
     identifiant utilisateur, historique d'achats et interaction avec le produit.
   - BIZZOO Admin : nom, e-mail, téléphone, adresse physique, emplacement précis,
     photos ou vidéos, assistance client, autre contenu utilisateur, identifiant
     utilisateur, historique d'achats et autres données d'utilisation.
2. Compléter la déclaration de droits sur les contenus. La classification
   par âge et la déclaration de chiffrement des builds sont déjà renseignées.
3. Tester le parcours du compte de revue client dans l'app, puis activer et
   tester le compte Admin. Saisir ce dernier hors dépôt dans les champs Apple,
   avec des instructions permettant d'atteindre les fonctions protégées.
4. Confirmer le titulaire des droits avant de renseigner le copyright.
5. Deux brouillons `reviewSubmissions` sont créés :
   `c49041b4-e9d0-4203-bfd8-e737361e011c` pour BIZZOO et
   `9a3a16c3-a223-454d-80c8-ea039811ada9` pour BIZZOO Admin. Le préflight
   Apple refuse encore l'ajout des versions (`409`) pour les quatre champs
   signalés ci-dessus : confidentialité publiée, comptes démo, copyright et
   droits sur les contenus. Une fois renseignés, ajouter chaque version au
   brouillon et soumettre réellement à App Review. Vérifier le statut
   **Waiting for Review** ou son équivalent, sans présenter un simple
   téléversement comme une soumission.

Le compte vendeur Apple est WINNER MARKET LIFE, alors que l'exploitant indiqué
par le RCCM est MATERIEL NET SARL. Une autorisation de distribution entre les
deux entités doit être conservée.
