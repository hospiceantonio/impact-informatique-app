# IMPACT INFORMATIQUE — Applications mobiles

Deux applications Android pour la boutique **IMPACT INFORMATIQUE**
(« Nous sommes imbattables en prix »), reliées à une base **Supabase**
partagée en temps réel :

- **Impact Admin** (icône rouge) : l'application du gérant. Produits avec
  photos, prix et promotions, catégories et sous-catégories, choix des
  **5 produits mis en avant** et de leur ordre dans le slider. Tout est
  enregistré directement en ligne.
- **Impact Informatique** (icône bleue) : l'application des clients.
  Slider des 5 produits mis en avant, rayons par catégorie et
  sous-catégorie, promotions, recherche, fiches produit et **commande par
  WhatsApp**. Mise à jour en temps réel, consultable hors connexion.

```
Impact Admin (téléphone du gérant, connexion email + mot de passe)
    │  écrit directement dans la base
    ▼
Supabase  →  tables boutique / categories / sous_categories / produits
             + stockage des photos (lecture publique, écriture protégée)
    │  lu en direct
    ▼
Impact Informatique (téléphones des clients)
```

La connexion à la base (URL + clé publiable) est intégrée dans
`client/config.js` et `admin/config.js` : rien à configurer dans les
applications.

## Les APK

Construits automatiquement par GitHub Actions à chaque modification
(`.github/workflows/apk.yml`) et déposés dans [`apk/`](apk/) :

- `impact-informatique-client.apk` — l'application des clients ;
- `impact-admin.apk` — l'application du gérant.

Sur le téléphone : ouvrir le fichier APK → autoriser « installer des
applications inconnues » → installer. (Signés avec la **clé de test**
versionnée dans `android/signature/` — parfaite pour essayer, pas pour
le Play Store.)

## Versions web (GitHub Pages)

Les mêmes applications, installables comme PWA :

- Client : `https://hospiceantonio.github.io/impact-informatique-app/client/`
- Admin : `https://hospiceantonio.github.io/impact-informatique-app/admin/`

> Si le premier déploiement échoue, vérifier une fois dans
> `Settings → Pages` que la source est « GitHub Actions ».

## La base Supabase (mise en route, une seule fois)

1. [`supabase/schema.sql`](supabase/schema.sql) : à coller dans
   **SQL Editor → New query → Run** du projet Supabase. Crée les tables,
   les règles de sécurité (lecture publique, écriture réservée au compte
   connecté), le stockage des photos, les rayons types et 6 produits
   d'exemple.
2. **Authentication → Users → Add user** : l'email et le mot de passe du
   gérant (cocher « Auto Confirm ») — les identifiants de connexion
   d'Impact Admin.

La clé embarquée est la clé **publiable** : elle ne permet que la
lecture ; toute écriture exige le compte du gérant (règles RLS).

## Publication sur le Play Store (le moment venu)

1. Compte **Google Play Console** (25 $ une fois).
2. Générer une **clé de signature privée** (à garder précieusement,
   jamais dans le dépôt) et construire des **AAB** :
   `./gradlew bundleClientRelease bundleAdminRelease` avec cette clé à la
   place de la clé de test dans `android/app/build.gradle`.
3. Créer deux fiches Play (client et admin — l'admin peut rester en
   « diffusion interne » pour ne pas être publique), avec captures
   d'écran, description et politique de confidentialité.

Le projet est déjà conforme aux exigences actuelles : `targetSdk 35`,
icônes adaptatives, portrait, aucune permission sensible (l'appareil
photo passe par l'application Photos du téléphone).

## Test local (versions web)

```powershell
./serve.ps1        # client : http://localhost:5180/client/
                   # admin  : http://localhost:5180/admin/
```

ou `python -m http.server 5180` à la racine du dépôt.

## Structure

```
impact-informatique-app/
├── supabase/schema.sql       # La base : tables, sécurité, stockage, données de départ
├── client/                   # Application des clients (bleue)
│   ├── config.js             # URL + clé publiable du projet Supabase
│   ├── demo-catalogue.json   # Catalogue de démonstration (si config vide)
│   ├── index.html / styles.css / manifest.webmanifest / sw.js
│   └── js/
│       ├── catalogue.js      # Lecture de la base + copie hors connexion
│       ├── ui.js             # Logo, cartes produit, prix, badges
│       └── vues/             # Accueil (slider), catégories, produit, recherche, infos
├── admin/                    # Application du gérant (rouge)
│   ├── config.js
│   ├── index.html / styles.css / manifest.webmanifest / sw.js
│   └── js/
│       ├── supabase.js       # Connexion, base, stockage des photos
│       ├── store.js          # Logique métier (5 en avant max, validations…)
│       └── vues/             # Connexion, accueil, produits, catégories, réglages
├── android/                  # Projet Android unique, deux variantes
│   ├── app/src/main/java/... # MainActivity : WebView, photos, WhatsApp, retours
│   ├── app/src/{client,admin}/  # Nom, couleurs, icônes de chaque application
│   ├── preparer-assets.js    # Copie les fichiers web dans les APK
│   └── signature/            # Clé de TEST (pas celle du Play Store)
├── apk/                      # APK construits par GitHub Actions
└── tools/make-icons.js       # Icônes PWA + Android (node tools/make-icons.js)
```

## Détails techniques

- Photos : compressées sur le téléphone (~100 Ko) puis envoyées dans le
  bucket public `produits` ; l'app client les met en cache après le
  premier affichage. Les photos HEIC/HEIF (iPhone et Android récents)
  sont converties en JPEG par l'application Android elle-même.
- Vidéo de présentation : une par produit (40 Mo maximum), envoyée telle
  quelle dans le même bucket et lue directement dans la fiche produit
  côté client. Les vidéos ne sont pas mises en cache hors connexion.
- Téléchargement des photos (app client) : bouton sur la fiche produit et
  dans la visionneuse. Sur Android, les fichiers vont dans le dossier
  Téléchargements via le pont natif ; sur le web, par le téléchargement
  du navigateur. Nom de fichier : `<référence>-<produit>-<n>.jpg`.
- La limite des **5 produits mis en avant** (le slider client) est
  imposée par l'application admin.
- Sauvegarde : Réglages → export/restauration d'un fichier JSON complet
  (produits, photos, boutique).
- Après modification des fichiers web, incrémenter `VERSION` dans
  `client/sw.js` / `admin/sw.js` (versions web) — les APK, eux, se
  reconstruisent automatiquement.
- Historique : ce projet a d'abord vécu dans le dépôt `le-matelot-site`
  (dossier `impact-informatique/`) avant d'être déplacé ici.
