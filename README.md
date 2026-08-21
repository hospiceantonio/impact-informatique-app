# BIZZOO — Applications mobiles

Deux applications Android pour l'enseigne **BIZZOO**, reliées à une base
**Supabase** partagée en temps réel :

- **BIZZOO Admin** (l'icône BIZZOO marquée d'une roue dentée) :
  l'application du gérant. Boutiques, produits avec photos, vidéo, prix
  grossiste et prix public, catégories et sous-catégories, et les
  **sliders** — celui de l'enseigne (photos et vidéos, dans les réglages
  de BIZZOO) et celui de chaque boutique. Tout est enregistré
  directement en ligne.
- **BIZZOO** (l'icône bleue de la marque) : l'application des clients.
  Slider de l'enseigne, **boutiques en icônes**, rayons par catégorie et
  sous-catégorie, promotions, recherche, fiches produit et **commande par
  WhatsApp**. Mise à jour en temps réel, consultable hors connexion.

**Plusieurs boutiques.** L'enseigne couvre plusieurs secteurs
d'activité — informatique, cosmétiques, etc. Chaque boutique a son
catalogue, ses rayons, son slider et ses coordonnées. Le client voit
d'abord le slider de l'enseigne, puis les boutiques en icônes ; il entre
dans l'une d'elles et tout l'écran ne parle plus que d'elle.

```
BIZZOO Admin (téléphone du gérant, connexion email + mot de passe)
    │  écrit directement dans la base
    ▼
Supabase  →  tables boutiques / categories / sous_categories / produits
             / produits_prive / slides / profils / journal
             + stockage des photos (lecture publique, écriture protégée)
    │  lu en direct
    ▼
BIZZOO (téléphones des clients)
```

La connexion à la base (URL + clé publiable) est intégrée dans
`client/config.js` et `admin/config.js` : rien à configurer dans les
applications.

## Les APK

Construits automatiquement par GitHub Actions à chaque modification
(`.github/workflows/apk.yml`) et déposés dans [`apk/`](apk/) :

- `bizzoo-client.apk` — l'application des clients ;
- `bizzoo-admin.apk` — l'application du gérant.

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
   d'Impact Admin. Il devient **administrateur** ; les comptes suivants
   se créent depuis l'application (Réglages → Comptes).
3. **Authentication → Providers → Email** : décocher « Confirm email »,
   sans quoi chaque compte créé depuis l'application devra d'abord
   cliquer un lien reçu par mail avant de pouvoir se connecter.

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
├── client/                   # Application des clients
│   ├── config.js             # URL + clé publiable du projet Supabase
│   ├── demo-catalogue.json   # Catalogue de démonstration (si config vide)
│   ├── index.html / styles.css / manifest.webmanifest / sw.js
│   └── js/
│       ├── catalogue.js      # Lecture de la base + copie hors connexion
│       ├── ui.js             # Logo, cartes produit, prix, badges
│       └── vues/             # Accueil (slider + boutiques), catégories, produit, recherche, infos
├── admin/                    # Application du gérant
│   ├── config.js
│   ├── index.html / styles.css / manifest.webmanifest / sw.js
│   └── js/
│       ├── supabase.js       # Connexion, base, stockage des photos
│       ├── store.js          # Logique métier (slider, rôles, validations…)
│       └── vues/             # Connexion, accueil, boutiques, produits, catégories, réglages
├── android/                  # Projet Android unique, deux variantes
│   ├── app/src/main/java/... # MainActivity : WebView, photos, WhatsApp, retours
│   ├── app/src/{client,admin}/  # Nom, couleurs, icônes de chaque application
│   ├── preparer-assets.js    # Copie les fichiers web dans les APK
│   └── signature/            # Clé de TEST (pas celle du Play Store)
├── apk/                      # APK construits par GitHub Actions
└── tools/
    ├── bizzoo-icone.jpg      # L'œuvre officielle — source de toutes les icônes
    └── make-icons.js         # Icônes PWA + Android (node tools/make-icons.js)
```

## Détails techniques

- Photos : compressées sur le téléphone (~100 Ko) puis envoyées dans le
  bucket public `produits`. Le droit d'y écrire suit le rôle : toute
  l'équipe pour les photos de produits (à la racine du bucket),
  l'administrateur seul pour `boutique/` et `slider/`. La règle teste le
  chemin au `like` plutôt que par `storage.foldername()` — une fonction
  de moins entre le refus et sa cause. Un refus du stockage est traduit
  en français dans l'application : « new row violates row-level security
  policy » ne dit rien à qui tient une boutique. Les fonctions de rôle
  sont explicitement exécutables par `authenticated`, les règles du
  stockage les appelant au nom du compte connecté. l'app client les met en cache après le
  premier affichage. Les photos HEIC/HEIF (iPhone et Android récents)
  sont converties en JPEG par l'application Android elle-même.
- Vidéo de présentation : une par produit (40 Mo maximum), envoyée telle
  quelle dans le même bucket et lue directement dans la fiche produit
  côté client. Les vidéos ne sont pas mises en cache hors connexion.
- Téléchargement des photos (app client) : bouton sur la fiche produit et
  dans la visionneuse. Sur Android, les fichiers vont dans le dossier
  Téléchargements via le pont natif ; sur le web, par le téléchargement
  du navigateur. Nom de fichier : `<référence>-<produit>-<n>.jpg`.
- Mise à jour automatique du catalogue client (`client/js/live.js`), sans
  fermer l'application : temps réel par WebSocket Supabase (~1 s),
  rafraîchissement au retour au premier plan, vérification de fond toutes
  les 45 s en secours, et bouton d'actualisation sur l'accueil. Le temps
  réel exige que les tables soient dans la publication `supabase_realtime`
  — la section « Temps réel » de `schema.sql` s'en charge.
- Gestion de stock, **quatre états** dérivés de trois colonnes
  (`produits.stock`, `produits.sur_commande` et `produits.appro_le`) :
  **Disponible** (vert) quand il reste des pièces, **En rupture** (rouge
  clignotant) quand le stock est à zéro, **Sur commande** (bleu) pour un
  produit que la boutique ne tient pas — celui-là n'a pas de stock du
  tout — et **En approvisionnement** (ambre) pour un produit qui n'est
  pas là mais qui arrive. `Store.statut()` et `Catalogue.statut()`
  calculent l'état ; rien n'est stocké en double.
  Dans l'admin : le stock se saisit dans le formulaire (le champ
  disparaît si le produit est sur commande ou en approvisionnement) et
  se corrige d'un geste depuis la fiche — − / + / « En rupture » /
  « Sur commande » / « Arrive dans N jours ». La liste des produits
  affiche « Stock 12 », « Stock 0 » en rouge, « Sans stock » ou
  « Arrive dans 3 jours ».
- **Produit en cours d'approvisionnement**, avec un délai de **1 à
  8 jours décompté chaque jour**. Ce qu'on enregistre n'est pas un
  nombre de jours mais la **date d'arrivée** (`produits.appro_le`) :
  sinon il faudrait décrémenter chaque produit chaque nuit, et le compte
  serait faux dès qu'une journée passe sans que l'application s'ouvre.
  Le décompte se lit donc en jours de calendrier — « arrive dans
  3 jours », « arrive demain », « arrive aujourd'hui » — et non en
  heures, sans quoi « dans 3 jours » deviendrait « dans 2 jours » à
  midi. Passée la date, le produit repasse **En rupture** de lui-même,
  comme une vente flash s'éteint : aucune tâche à faire tourner.
  Les trois options s'excluent : annoncer une arrivée efface « sur
  commande », et saisir un stock efface l'arrivée annoncée. Côté client,
  la carte porte le décompte dans son badge (elle n'a pas la place
  d'autre chose) et la fiche l'écrit en toutes lettres sur une bande
  ambre, sous le badge d'état.
  Côté client, le nombre exact n'est jamais montré, et le message
  WhatsApp suit l'état : disponibilité, date de retour, ou délai de
  commande. Le clignotement du rouge s'arrête sous
  `prefers-reduced-motion`.
  La colonne `disponible` existe toujours et suit les deux autres
  (`sur_commande or stock > 0`) : une application client d'une version
  antérieure continue de voir juste. Un catalogue en cache sans `stock`
  est relu comme 1 ou 0 selon l'ancien `disponible`, pour qu'une mise à
  jour n'affiche jamais tout le catalogue en rupture.
- Plein écran (les deux applications Android) : ni barre d'état ni barre
  de navigation, l'écran entier est à l'application
  (`WindowInsetsControllerCompat.hide`, comportement
  `BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE` — un glissement depuis un bord
  ramène les barres le temps de s'en servir, puis elles repartent). Le
  plein écran est réappliqué dans `onWindowFocusChanged`, sinon le
  système le rend après un appel, une notification déroulée ou le choix
  d'une photo. Deux zones restent contournées par les marges de la
  WebView : l'encoche de l'appareil photo (`displayCutout`) et le
  clavier (`ime`), pour qu'un champ de formulaire ne se retrouve pas
  caché dessous. Le thème passe en `windowLayoutInDisplayCutoutMode
  shortEdges`. Côté web installé (PWA), les manifestes demandent
  `display: fullscreen`.
- Les écrans se dessinent l'un après l'autre (`file` dans les deux
  `app.js`) : deux navigations rapprochées — un renvoi automatique suivi
  d'un appui — se chevauchaient, et la plus lente écrasait l'écran de la
  plus récente.
- Cadres d'images de dimensions fixes (carrés) quelle que soit la forme
  de la photo : le cadre commande la taille, la photo est posée dessus en
  `position:absolute` (sans quoi une photo verticale étire sa carte).
  Grille et rangées : photo cadrée (`cover`) ; fiche produit : photo
  entière visible (`contain`).
- Tri du catalogue client : rayons, sous-catégories, promotions et
  résultats de recherche sont classés **du prix le plus bas au plus
  élevé** (à prix égal, par ordre alphabétique). Les nouveautés restent
  classées par date et le slider garde l'ordre choisi par le gérant.
- **La charte graphique vient de l'icône.** Les couleurs des deux
  applications sont relevées sur l'œuvre BIZZOO (`tools/bizzoo-icone.jpg`) :
  le **bleu vif** du fond (`--bleu`, #0B5CF5), le **bleu nuit** du sac
  (`--bleu-900`, #001450), l'**orange** de la vague (`--orange`, #F96302)
  et l'**ambre** de l'anse (`--ambre`, #FFA808). Une règle de lisibilité
  gouverne l'orange : il sert de **fond** et porte alors du bleu nuit
  (5,6:1) ; **en texte** sur fond clair, c'est l'orange foncé
  (`--orange-fonce`, #C24B00 — 4,9:1), car l'orange vif ne fait que 3:1 et
  se lit mal en petit. Le **rouge ne dit plus la marque** : il est réservé
  au danger (suppression, erreur, rupture de stock). Les deux feuilles de
  style partagent les mêmes noms de variables, et les tests lisent la
  teinte dans l'application au lieu de la figer, pour qu'un changement de
  charte ne casse rien.
- **Les icônes sortent de l'œuvre, motif détouré sur blanc.**
  `node tools/make-icons.js` décode `tools/bizzoo-icone.jpg` dans Chromium
  et en tire les 48 fichiers (PWA et Android, toutes densités). Le **fond
  bleu de l'œuvre est retiré** : sur le téléphone, la tuile bleue pleine
  écrasait tout. Il ne reste que le motif, posé sur blanc.
  Le détourage part des bords du carré et avance **tant que la couleur ne
  change presque pas** (écart de 4 au plus d'un pixel au suivant) : le
  fond est un dégradé lisse, la propagation le suit ; le motif a des bords
  francs, elle s'y arrête. Un simple seuil de couleur ne marcherait pas —
  le sac est bleu, comme le fond. Le **chariot blanc est conservé** sans
  rien faire de particulier : enfermé au milieu du motif, la propagation
  ne peut pas l'atteindre. Le liseré du cadre s'efface par **géométrie**
  (un carré arrondi rentré de 3,5 %) et non par érosion, qui creuserait
  aussi autour du chariot — un trou dans le masque. Un pixel de bord est
  grignoté pour ôter la frange bleue laissée par le lissage.
  Le motif est ensuite **rogné au plus juste, centré**, et posé à une
  emprise qui dépend de ce que le téléphone laisse voir : large sur une
  tuile carrée, plus serrée sous un masque rond. Repère utile : le calque
  adaptatif fait 108 dp mais le téléphone n'en montre que **72** — le
  motif à 0,60 occupe donc 90 % de ce qu'on voit, et au-delà les traits
  de vitesse se font couper. L'icône adaptative porte tout dans son
  calque de fond, le premier plan restant transparent.
  Le fond de la tuile est **blanc franc** : l'œuvre garde sa structure,
  on ne lui retire que son fond bleu.
  **Un seul dessin sert partout** : `UI.marque()` affiche le fichier
  d'icône lui-même (`icons/icon-192.png`) au lieu d'un SVG approché —
  barre du haut, écran de connexion admin, vignette d'un produit sans
  photo. Plus de version parallèle qui finirait par diverger, et le
  fichier est déjà gardé hors connexion par le service worker.
  L'**écran de démarrage** (`drawable/ecran_demarrage.xml`) pose la même
  icône au centre du fond blanc : l'ouverture montre la marque au lieu
  d'un écran vide.
  L'**écran de démarrage** (`fond_demarrage`, la couleur affichée le temps
  que l'application s'ouvre) est passé du bleu au **blanc** : l'ouverture
  ne commence plus par un éclair bleu, et enchaîne sans rupture sur les
  écrans clairs de l'application.
  L'application admin reçoit la **même** œuvre, marquée d'une pastille
  « réglages » : les deux applications vivent sur le même téléphone, on
  doit les distinguer d'un coup d'œil. Sous masque rond, la pastille se
  pose tangente à l'intérieur de la zone sûre — sinon le téléphone lui
  couperait la moitié.
- **Annuler une action, depuis l'historique.** Réservé au
  **SuperAdministrateur** : chaque ligne de `Réglages → Historique`
  porte un bouton qui remet les choses comme elles étaient avant cette
  action. Le mécanisme tient en une idée : au moment d'écrire,
  l'application range dans le journal la **ligne telle qu'elle était**
  (`journal.retour`). Annuler, c'est la réécrire ; et si elle n'existait
  pas avant, c'est la supprimer — un ajout, une modification et une
  suppression s'annulent donc par le même code, sans cas particulier.
  `retour` porte une **liste** de lignes et une liste d'identifiants, ce
  qui couvre aussi ce qui touche plusieurs lignes à la fois : un échange
  de position (deux lignes) ou un rayon avec ses sous-catégories (deux
  tables).
  Deux conséquences assumées : supprimer un produit ou un écran du
  slider **ne supprime plus la photo ni la vidéo** du stockage — sans
  elles, l'annulation rendrait une fiche aux images mortes ; et
  l'annulation reste inscrite au journal (la ligne annulée est barrée,
  l'action d'annulation apparaît à son tour) plutôt que d'effacer
  l'histoire.
  Ne s'annulent pas : la suppression d'un **compte** (l'identifiant de
  connexion lui-même est effacé), la suppression d'une **boutique**
  (elle emporte tout son catalogue), et les actions d'avant cette
  version — le journal n'en avait rien gardé. La règle
  `journal annulation` (RLS) est ce qui ferme vraiment la porte aux
  autres rangs ; cacher le bouton n'est qu'une politesse.
- **Le slider appartient à l'enseigne.** Ce qui défile en haut de
  l'accueil de l'application client est composé dans **BIZZOO Admin →
  Réglages → onglet BIZZOO → Slider** : des **photos et des vidéos**,
  ajoutées une par une, dans l'ordre voulu, chacune pouvant renvoyer
  vers un produit de n'importe quelle boutique. Les boutiques n'envoient
  plus rien à l'accueil, et les produits mis en avant n'y défilent plus.
  Chaque boutique garde pourtant **son** slider — ses écrans puis ses
  produits mis en avant — qui défile sur son écran à elle.
  Une seule colonne sépare les deux : `slides.portee` vaut `enseigne` ou
  `boutique`. Elle porte aussi les droits (le slider de BIZZOO au
  superadministrateur, celui d'une boutique à son administrateur) et
  protège la reprise d'avant les boutiques multiples, qui rangeait dans
  la première boutique tout écran sans `boutique_id` — ce que sont
  justement les écrans de l'enseigne.
  Une vidéo (`slides.video`, 40 Mo maximum) part **sans le son** et sans
  passer en plein écran : c'est la seule façon qu'un téléphone la lance
  tout seul. Une seule joue à la fois, celle qu'on regarde ; les autres
  se taisent et repartent du début. Le slider n'avance pas tant qu'elle
  n'est pas finie — au-delà d'une minute, il passe outre, une vidéo qui
  bloque ne doit pas figer la vitrine.
- **Ventes flash.** Chaque boutique peut mettre des produits en vente
  flash avec une date de fin (fiche produit → Actions rapides →
  « Mettre en vente flash » : 24 h, 48 h, 3 jours, 7 jours ou une date
  précise). Une seule colonne, `produits.flash_fin` — nulle : pas de
  flash ; passée : le flash s'éteint tout seul, sans tâche planifiée,
  car les deux applications ne montrent le badge « Vente flash » que si
  `flash_fin` est à venir. Côté client, la rangée **Ventes flash**
  défile juste après les icônes des boutiques sur l'accueil de
  l'enseigne (toutes boutiques actives confondues, les échéances les
  plus proches d'abord), chaque accueil de boutique montre les siennes,
  et la fiche affiche « se termine dans 2 j 4 h ». Peut poser ou retirer
  un flash quiconque a le droit de modifier les produits de la boutique
  (mêmes règles RLS que la modification de produit, rien à ajouter).
- **Deux prix par produit.** Le gérant saisit un **prix grossiste** —
  ce que la boutique paie — et un **taux de marge** ; le **prix
  public** en découle et reste modifiable pour arrondir (le corriger à
  la main recalcule le taux, les trois champs se répondent). Le taux
  par défaut est celui de la boutique (`boutique.taux_marge`, 20 % au
  départ, réglé dans **Réglages → Marge par défaut**) ; un produit peut
  garder le sien (`produits_prive.taux_marge`). Le changer ne retouche
  aucun prix déjà enregistré.
  Le prix public reste `produits.prix` : **le catalogue client ne change
  pas d'un octet**, et une application cliente d'avant continue de
  fonctionner. Le prix grossiste, lui, ne vit **pas** dans `produits`,
  qui est en lecture publique : il vit dans `produits_prive`, dont le
  rôle `anon` n'a **aucun droit** (`revoke all … from anon`, plus des
  policies `to authenticated` calquées sur celles des produits). Sans
  cela, la clé publiable embarquée dans l'APK client suffirait à lire
  toutes les marges de la boutique. L'admin lit les deux en une requête
  (`produits?select=*,produits_prive(*)`, jeton du compte obligatoire) et
  se rabat sur `select=*` seul tant que la table n'existe pas, pour ne
  jamais bloquer le catalogue sur une base pas encore mise à jour.
  La fiche produit affiche une carte **Marge** (achat, public, taux,
  bénéfice à la pièce et sur le stock) qui ne quitte jamais l'admin, et
  la sauvegarde JSON emporte les prix d'achat — l'écran de sauvegarde
  le dit.
- Sous-catégories figées (client, écran d'un rayon) : la rangée de puces
  est `position:sticky` et se cale juste sous la barre du haut pendant
  qu'on fait défiler les produits — on change de sous-catégorie sans
  remonter. La barre du haut n'a pas toujours la même hauteur (logo et
  slogan sur l'accueil, titre seul ou titre + sous-titre ailleurs) :
  `UI.entete()` la mesure après chaque rendu et publie le résultat dans
  la variable CSS `--haut-topbar`, que `.puces-collees` lit dans son
  `top`. Un `ResizeObserver` et l'événement `resize` la remesurent à la
  rotation de l'écran ou quand la barre système revient. Le bandeau
  déborde des marges de la vue (`margin:-16px -16px 0`) pour qu'aucune
  carte ne passe derrière, et cette marge négative en haut le met dès le
  départ à la place qu'il gardera une fois figé : il ne saute pas au
  premier défilement.
- Boutique : coordonnées GPS (`latitude`/`longitude`) et photos
  (`photos[]`, dossier `boutique/` du bucket) réglées dans l'admin —
  relevé de la position sur place en un bouton, ou extraction depuis un
  lien Google Maps collé. Côté client : bande de photos et lien
  d'itinéraire dans l'onglet Infos. Le relevé de position demande la
  permission Android de localisation (application admin uniquement).
- Plusieurs numéros et plusieurs adresses (colonnes `jsonb`
  `boutique.telephones` et `boutique.adresses`, 8 de chaque au
  maximum) : en plus du numéro de commande WhatsApp et de l'adresse
  principale, l'admin ajoute autant de lignes qu'il veut dans
  **Réglages → Autres numéros / Autres adresses**. Un numéro porte un
  libellé (« Atelier », « Service après-vente ») et une case
  « aussi sur WhatsApp » qui décide du bouton chez le client : appel
  direct ou conversation WhatsApp. Une adresse porte un libellé, son
  texte et — facultatif — sa position, relevée d'un lien Google Maps
  collé comme pour la boutique ; renseignée, la ligne ouvre le plan sur
  ce point précis, sinon sur une recherche du texte. Les lignes laissées
  vides (numéro sans chiffre, adresse sans texte) sont écartées à
  l'enregistrement plutôt que publiées à moitié. Côté client, tout
  arrive dans la carte « Nous contacter » de l'onglet Infos, à la suite
  du numéro et de l'adresse principaux.
- Position de lecture conservée (les deux applications) : la hauteur de
  défilement de chaque écran est mémorisée et restaurée au retour en
  arrière — on retrouve sa place exacte dans une longue liste après
  avoir consulté un produit. Le retour est reconnu grâce à un rang
  déposé sur chaque entrée d'historique ; une nouvelle visite du même
  écran repart bien du haut. `history.scrollRestoration` est passé en
  « manual » pour que le navigateur ne s'en mêle pas.
- Visionneuse en galerie (les deux applications) : ouvrir une photo
  charge **toute la série** (produit ou boutique) et on passe de l'une à
  l'autre du doigt, par les flèches, les points ou les touches ←/→ ;
  compteur « 2 / 3 » et bouton d'enregistrement qui suit la photo
  affichée.
- Réseaux sociaux : Facebook, Instagram, TikTok, YouTube et Snapchat
  (colonnes de `boutique`). Le gérant saisit un nom de compte ou un lien
  complet ; l'adresse finale est reconstruite (`Utils.lienReseau`) et
  affichée en aperçu dans l'admin. Côté client, carte « Suivez-nous »
  dans l'onglet Infos, avec les couleurs de chaque marque — seuls les
  réseaux remplis apparaissent.
- Notifications du catalogue (app client Android) : une vérification de
  fond (`VerificateurCatalogue.java`, WorkManager, toutes les 15 min et
  même application fermée) lit le produit modifié en dernier et dépose
  une notification quand il a changé. Le repère comparé est
  `identifiant|modifie_le` ; l'application le remet à jour à chaque
  affichage du catalogue (pont `AndroidPont.majDerniereVue`), donc rien
  n'est annoncé deux fois. La permission est demandée au premier
  lancement (Android 13+) ; l'app admin, elle, n'en reçoit aucune
  (`notifications_actives` à `false` dans sa variante).
- **Deux niveaux de coordonnées.** *BIZZOO l'enseigne* (table `boutique`,
  ligne unique) a les siennes — nom, slogan, présentation, WhatsApp,
  téléphone, adresse, horaires, réseaux, position, autres numéros, autres
  adresses, photos et **vidéo** ; *chaque boutique* a exactement les
  mêmes, plus sa devise et sa marge (l'enseigne ne vend rien, elle n'en
  a pas). Côté admin, **Réglages** porte une bascule *BIZZOO / boutique
  ouverte* et tout l'écran suit. Côté client, l'onglet **Infos** montre
  BIZZOO tant qu'aucune boutique n'est choisie — et redescend vers elles
  par une liste — puis les coordonnées de la boutique dès qu'on est
  dedans. Les autres onglets (Catégories, Recherche) entrent d'office
  dans la première boutique : eux ne savent parler que d'un catalogue.
- **Plusieurs boutiques** (table `boutiques`) : un secteur d'activité par
  boutique, chacune avec son nom, son icône, sa couleur, son logo
  facultatif, ses coordonnées, ses photos, sa marge — et son propre
  catalogue (`produits.boutique_id`, `categories.boutique_id`,
  `slides.boutique_id`). **Seul l'administrateur** en crée, en modifie ou
  en ferme (`boutiques` : lecture publique, écriture `est_admin()`). Une
  boutique **fermée** garde tout son contenu mais disparaît de
  l'application client.
  Côté admin, une **boutique ouverte** à la fois : produits, rayons,
  slider et réglages ne parlent que d'elle, et l'accueil l'affiche en
  bandeau. L'administrateur en change dans **Réglages → Gérer les
  boutiques** (le choix se retient dans `localStorage`) ; le modérateur
  est verrouillé sur la sienne (`profils.boutique_id`, choisie à la
  création du compte).
  La serrure est en base, pas seulement à l'écran : `peut_agir_sur(id)`
  — administrateur partout, modérateur dans sa boutique — garde les
  produits, les rayons, les sous-catégories et les prix d'achat. Un
  modérateur qui s'adresse directement à la base pour un produit d'un
  autre secteur se fait refuser, et ne voit pas non plus les marges du
  voisin.
  Le formulaire produit **annonce la boutique** dans laquelle le produit
  va naître, et l'administrateur peut en changer avant de créer — le
  formulaire se rouvre alors sur cette boutique, avec ses rayons, sa
  devise et sa marge. Sur un produit existant c'est un rappel, pas un
  choix : un produit ne change pas de boutique (son rayon n'y existerait
  pas).
  Les références produit (`IMP-0001`…) se numérotent sur **toutes** les
  boutiques : deux produits de secteurs différents ne portent jamais le
  même numéro, sinon une commande WhatsApp deviendrait ambiguë.
  Côté client, l'accueil montre **le slider d'abord** — les images et
  les produits mis en avant de toutes les boutiques ouvertes, boutique
  par boutique — puis la grille des **icônes**. On entre dans une
  boutique (`#/boutique/:id`) et rayons, recherche et infos ne parlent
  plus que d'elle ; un bandeau rappelle laquelle et ramène aux autres.
  Un lien direct — produit partagé sur WhatsApp, rayon mis en favori —
  ouvre la bonne boutique tout seul : elle se déduit de ce qui est
  affiché.
  Migration : la ligne `boutique` d'origine devient
  « INFORMATIQUE ET ELECTRONIQUE » avec tous ses réglages, et tout le
  catalogue existant y est rangé. Tant que la table n'existe pas, les
  deux applications retombent sur le fonctionnement à boutique unique.
- **Trois rangs de comptes** (table `profils`) : le
  **super administrateur** tient toute l'enseigne — boutiques, réglages
  BIZZOO, tous les comptes (les administrateurs d'avant la migration
  deviennent super administrateurs) ; l'**administrateur** a tous les
  droits de gestion de SA boutique — produits, rayons, slider, réglages
  et ses modérateurs, rien en dehors ; le **modérateur** garde son
  périmètre. La hiérarchie est en base, pas seulement à l'écran :
  `est_super()`, `administre(boutique)` et `gere_le_compte(compte)`
  gardent l'enseigne, les boutiques, les sliders, les comptes et les
  deux RPC (`supprimer_compte`, `changer_mot_de_passe`). Un
  administrateur ne voit que l'équipe de sa boutique, ne nomme que des
  modérateurs, et ne peut ni créer une boutique, ni toucher l'enseigne,
  ni écrire chez le voisin — les tests attaquent la base directement
  pour le prouver.
- Deux rôles historiques dans l'app admin : **administrateur** —
  toute l'application, et lui seul crée les comptes ; **modérateur** —
  produits et catégories, sans réglages, ni comptes, ni historique, ni
  composition du slider. Le rôle est lu au démarrage
  (`Supabase.chargerProfil()`) et masque les écrans concernés, mais la
  vraie serrure est en base : les règles RLS s'appuient sur
  `est_admin()` / `est_equipe()`, et un déclencheur interdit au
  modérateur de toucher `en_avant` / `ordre_avant`. Les comptes sont
  créés par l'inscription publique de Supabase avec la clé publiable (la
  clé `service_role` ne doit jamais quitter le serveur) ; un déclencheur
  sur `auth.users` pose une fiche « en attente » pour tout compte créé,
  que l'administrateur active dans **Comptes**. Un compte désactivé ne
  peut plus rien écrire. Depuis ce même écran, l'administrateur peut
  aussi **supprimer** un compte ou lui **redonner un mot de passe** —
  jamais le sien. Ces deux gestes demandent des droits que la clé
  publiable n'a pas : ils passent par deux fonctions `security definer`
  de la base (`supprimer_compte`, `changer_mot_de_passe`) qui vérifient
  elles-mêmes `est_admin()`, plutôt que d'embarquer la clé
  `service_role` dans une application posée sur un téléphone. Changer un
  mot de passe ferme les sessions ouvertes du compte visé. Sur une base
  d'avant les rôles, le compte garde tous les droits : rien ne se bloque
  tant que le SQL n'est pas passé.
- Droit de modification, compte par compte (colonne
  `profils.peut_modifier_produits`) : dans **Comptes**, l'administrateur
  coche ou décoche « Peut modifier les produits » sur la fiche d'un
  modérateur. Décoché, celui-ci continue d'**ajouter** des produits mais
  ne peut plus en **modifier** ni en **supprimer** ; la liste des comptes
  l'annonce par « ajout seulement ». L'administrateur, lui, garde
  toujours le droit — son interrupteur disparaît. Côté écran, la fiche
  produit passe en « Lecture seule » (ni crayon, ni disponibilité, ni
  bouton de modification) et l'adresse `#/produit/…/modifier` répond
  « Modification non autorisée ». Côté base, la serrure est faite de
  trois règles RLS distinctes sur `produits` — `produits ajout`
  (`est_equipe()`), `produits modification` et `produits suppression`
  (`peut_modifier_produits()`) — de sorte qu'un refus ne dépende jamais
  de ce que l'application veut bien afficher.
- Historique de l'admin (menu horloge, `#/historique`) : chaque geste du
  gérant écrit une ligne dans la table `journal` (date et heure,
  utilisateur, famille, opération, élément concerné) — produits,
  catégories, slider, stock, boutique, connexion et déconnexion. Écran
  groupé par jour, filtres par famille, chargement par pages de 60, et
  rappel des 4 dernières actions sur l'accueil. Le journal n'est **pas**
  public : sa règle RLS le réserve au compte connecté.
- Slider de l'application client : **deux sources à la suite**, réunies
  dans l'écran Slider de l'admin.
  1. Les **images libres** (table `slides`) : une affiche, une promotion,
     un arrivage — dans l'ordre voulu, 8 au maximum. Chaque image accepte
     une légende et peut renvoyer vers un produit ; sans produit, elle
     n'est pas cliquable. Une image masquée reste dans l'admin sans
     défiler chez les clients. Les fichiers vont dans le dossier
     `slider/` du bucket, réservé à l'administrateur comme la table.
  2. Les **produits mis en avant** (`en_avant` / `ordre_avant`), 5 au
     maximum : ils défilent après les images, avec photo, nom et prix.
     On les ajoute depuis la fiche d'un produit (« Mettre en avant »), on
     les ordonne dans l'écran Slider. Un déclencheur SQL réserve ce choix
     à l'administrateur.
- Sauvegarde : Réglages → export/restauration d'un fichier JSON complet
  (produits, photos, boutique).
- Après modification des fichiers web, incrémenter `VERSION` dans
  `client/sw.js` / `admin/sw.js` (versions web) — les APK, eux, se
  reconstruisent automatiquement.
- Historique : ce projet a d'abord vécu dans le dépôt `le-matelot-site`
  (dossier `impact-informatique/`) avant d'être déplacé ici.
