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
  sous-catégorie, promotions, recherche, fiches produit, **panier et
  paiement Mobile Money** (KkiaPay), et commande par WhatsApp. Mise à
  jour en temps réel, consultable hors connexion.

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
             / produits_prive / slides / profils / journal / demandes
             / commandes / commande_lignes / paiement
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

## Les versions web

Ce sont **les mêmes applications**, pas des copies : un seul code, que
l'APK Android embarque et que le navigateur lit tel quel. Une correction
faite ici arrive des deux côtés.

### Les ouvrir sur son ordinateur

**Windows — double-cliquer sur `DEMARRER-BIZZOO.bat`.** Une fenêtre noire
s'ouvre, le navigateur suit. Pour arrêter : fermer la fenêtre noire.

> Pourquoi un `.bat` plutôt que le `.ps1` directement ? Windows **refuse
> par défaut d'exécuter un script PowerShell** — `.\serve.ps1` répond
> « l'exécution de scripts est désactivée sur ce système ». Le `.bat`
> lance PowerShell avec une exception valable pour ce seul lancement,
> sans rien changer aux réglages de la machine.

Linux et macOS :

```bash
bash tools/servir.sh
```

Puis, dans le navigateur :

| | |
|---|---|
| Accueil | `http://localhost:5180/` |
| La boutique | `http://localhost:5180/client/` |
| Espace admin | `http://localhost:5180/admin/` |

La base reste celle de Supabase, en ligne : **ce qu'on enregistre là est
enregistré pour de bon**. Ce n'est pas un bac à sable.

Pour voir ce que voit un téléphone, réduire la fenêtre sous 1024 px.

> Le service worker ne s'installe pas sur une adresse locale, et celui
> qu'une visite précédente aurait laissé est retiré. Il sert ses fichiers
> depuis son cache AVANT le réseau : en développement on modifierait un
> fichier, on rechargerait, et l'ancien réapparaîtrait.

### Deux tailles d'écran, une seule application

Au-delà de **1024 px**, la barre du bas — faite pour le pouce — devient un
menu à gauche, là où la lecture commence ; le catalogue passe à quatre
colonnes et les écrans s'élargissent. En dessous, rien ne change : le
téléphone garde exactement l'application qu'il a.

La bascule est vérifiée à 1023 et à 1024 px, des deux côtés.

### En ligne (GitHub Pages)

- Accueil : `https://hospiceantonio.github.io/impact-informatique-app/`
- Client : `https://hospiceantonio.github.io/impact-informatique-app/client/`
- Admin : `https://hospiceantonio.github.io/impact-informatique-app/admin/`

> Si le premier déploiement échoue, vérifier une fois dans
> `Settings → Pages` que la source est « GitHub Actions ».

L'adresse **officielle** est `https://www.bizzoomarket.com` (section
suivante) ; GitHub Pages en reste une copie, qui le dit aux moteurs de
recherche par la balise `canonical`.

## Mettre le site en ligne — www.bizzoomarket.com

Le domaine pointe déjà sur un hébergement classique (www et ftp sur le
même serveur, la messagerie ailleurs). Le site s'y dépose tel quel : ce
sont des fichiers, sans base de données ni PHP — la base reste celle de
Supabase.

### Ce qui part en ligne, et rien d'autre

`tools/assembler-site.sh` assemble le site à partir d'une **liste
blanche** : la vitrine (`index.html`, `vitrine/`), les deux applications
(`client/`, `admin/`), les APK (`apk/`), et les fichiers d'un site en
ligne (`404.html`, `robots.txt`, `sitemap.xml`).

**Avant, c'était une copie « tout sauf ».** Le README — l'architecture,
la place de chaque secret —, le dossier `skills/` et son code
d'intégration du paiement, le lanceur Windows : tout partait sur GitHub
Pages avec le reste, et un fichier ajouté demain au dépôt serait parti
de même. Le script refuse maintenant de finir si le site contient un
fichier de ce genre (`.md`, `.sql`, `.sh`, `.bat`…), ou quelque chose qui
ressemble à une clé secrète : `sb_secret_…`, un jeton FeexPay `fp_…`,
une clé privée — et l'ancienne clé `service_role`, que le script décode
pour la reconnaître, puisqu'un jeton JWT ne se trahit pas à l'œil. La
clé publiable de `config.js` est faite pour être lue : elle passe.

```bash
bash tools/assembler-site.sh                          # _site/, pour GitHub Pages
bash tools/assembler-site.sh --hebergement            # bizzoo-site.zip, pour l'hébergement
```

Le zip est aussi fabriqué à chaque publication : **Actions → « Déployer
sur GitHub Pages » → la dernière exécution → Artifacts →
`bizzoo-site-hebergement`** (GitHub l'emballe dans un second zip).

**La publication repart quand les APK sont prêts.** Ils sont construits
après le code, et poussés dans un commit `[skip ci]` qui ne relançait
rien : le bouton « Télécharger l'application » servait l'APK de la
version précédente jusqu'à la poussée suivante. Le site se republie
maintenant à la fin de « Construire les APK Android » — le zip de cette
exécution-là est donc celui qui porte les bons APK.

### Déposer le site sur l'hébergement

1. **Activer le certificat SSL** (Let's Encrypt, gratuit chez tous les
   hébergeurs) pour `bizzoomarket.com` **et** `www.bizzoomarket.com`.
   Sans HTTPS, l'application ne s'installe pas et la position ne se lit
   pas : le `.htaccess` y envoie donc tout le monde.
2. **Sauvegarder** ce qu'il y a aujourd'hui dans `public_html` : ce sera
   remplacé.
3. **Téléverser `bizzoo-site.zip` dans `public_html`** avec le
   gestionnaire de fichiers de l'hébergeur, puis **« Extraire »** sur
   place. Extraire sur le serveur garde le `.htaccess`, que certains
   logiciels FTP cachent et oublient.
4. **Vérifier** : `https://www.bizzoomarket.com/` s'ouvre ;
   `http://bizzoomarket.com` y mène ; « Ouvrir la boutique » ;
   `/admin/` ; une adresse inventée montre la page 404 de BIZZOO ;
   « Télécharger l'application » propose d'installer l'APK.
5. **À chaque nouvelle version**, recommencer l'étape 3 avec le zip du
   jour.

> **Autre voie, GitHub Pages sur le domaine.** `Settings → Pages →
> Custom domain : www.bizzoomarket.com`, puis chez le registraire un
> enregistrement `CNAME www → hospiceantonio.github.io` (et, pour
> `bizzoomarket.com`, les quatre `A` de GitHub : 185.199.108.153,
> 185.199.109.153, 185.199.110.153, 185.199.111.153). Le site se publie
> alors tout seul à chaque poussée — mais il quitte l'hébergement
> actuel. Ne pas toucher aux enregistrements `MX` de la messagerie.

### Le réglage Supabase sans lequel « mot de passe oublié » ne mène à rien

Le lien envoyé par e-mail ramène le client à la **Site URL** du projet.
Dans le tableau de bord Supabase : **Authentication → URL
Configuration** :

| | |
|---|---|
| Site URL | `https://www.bizzoomarket.com/client/` |
| Redirect URLs | `https://www.bizzoomarket.com/**` (et `https://hospiceantonio.github.io/impact-informatique-app/**` si la copie sert encore) |

### Le lien « mot de passe oublié » aboutit enfin

Supabase vérifie le lien, puis ramène le client au site avec une session
toute prête après le `#` (`#access_token=…&type=recovery`), ou une
erreur quand le lien a expiré (`#error_code=otp_expired`). **Personne ne
lisait ces morceaux** : le routeur les prenait pour un écran inconnu et
renvoyait à l'accueil. Le jeton était perdu, et le client ne pouvait
jamais choisir un nouveau mot de passe — un lien était pourtant parti le
22 septembre.

`Compte.lireRetourEmail()` les lit maintenant avant le premier écran :

- **le lien valable** ouvre « Nouveau mot de passe » (deux saisies, six
  caractères au moins), sans flèche de retour — l'écran d'avant
  rejouerait un lien déjà consommé. Le mot de passe part par
  `PUT /auth/v1/user`, au nom du compte du lien, puis « Mon compte »
  s'ouvre ;
- **le lien périmé** revient sur « Mot de passe oublié », qui le dit en
  clair et en renvoie un neuf ;
- **l'adresse est nettoyée sur-le-champ** : un jeton laissé dans la
  barre d'adresse finit dans une capture d'écran, ou dans un lien
  partagé ;
- **la vitrine passe la main** : si la Site URL mène à la racine du site
  plutôt qu'à `/client/`, elle transmet le lien à l'application.

Au passage : au rafraîchissement de la session (toutes les heures), le
numéro d'un compte créé par SMS était perdu, et « Mon compte » affichait
un identifiant vide. Il est gardé.

### Le .htaccess

`hebergement/htaccess`, copié en `.htaccess` dans le zip :

- **une seule adresse** : `http://` et `bizzoomarket.com` mènent à
  `https://www.bizzoomarket.com`, en un seul saut ;
- **sécurité** : `nosniff`, `SAMEORIGIN` (le site ne se laisse pas
  encadrer par un autre), la position permise, la caméra et le micro
  non, HTTPS obligatoire six mois (sans les sous-domaines : la
  messagerie a les siens) ;
- **cache** : les pages et le code se revalident à chaque visite — leurs
  noms ne changent pas d'une version à l'autre —, les images une
  semaine, les polices un an, l'APK jamais ;
- **types** : l'APK part en `application/vnd.android.package-archive` —
  sans quoi Android l'enregistre comme un fichier inconnu et ne propose
  pas de l'installer —, les polices et le manifeste avec les leurs.

**Un `.htaccess` fautif, c'est tout le site en erreur 500.** Chaque
module est donc entouré de `<IfModule>`, et aucune directive ne demande
plus que `AllowOverride FileInfo` : pas d'`Options -Indexes`, pas de
`mod_expires`, que certains hébergeurs refusent — le cache passe par des
en-têtes. En cas de « trop de redirections », l'hébergeur passe le HTTPS
par un chemin que les conditions ne voient pas : retirer les trois
lignes du bloc HTTPS.

### Ce que voient les moteurs et les messageries

- **l'aperçu d'un lien partagé** (WhatsApp, Facebook) : une image
  1200 × 630 aux couleurs de la DA (`vitrine/partage.jpg`, 89 Ko —
  WhatsApp renonce au-delà de 300), en **adresse entière** : l'ancienne,
  en chemin relatif, était ignorée, et le lien partait sans image ;
- `canonical`, `robots.txt`, `sitemap.xml` ;
- **l'admin hors des moteurs** : `noindex` sur la page, `Disallow` dans
  `robots.txt` ;
- une **page 404** aux couleurs de BIZZOO. Elle s'affiche à n'importe
  quelle profondeur (`/une/adresse/inconnue`) : ses liens partent donc de
  la racine — celle de `www.bizzoomarket.com`, ou celle du dépôt sur
  GitHub Pages ;
- les descriptions disent « commandez et payez par Mobile Money », et
  plus « par WhatsApp ».

### Le banc de la mise en ligne

```bash
PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-mise-en-ligne.mjs
```

Quatre-vingt-huit constats. Le banc assemble le site, puis l'ouvre aux
deux adresses — `https://www.bizzoomarket.com` et le sous-dossier de
GitHub Pages — servies par lui-même : aucune requête ne sort. Il suit le
lien « mot de passe oublié » de bout en bout, et démarre un **vrai
Apache** réglé comme l'hébergeur le plus avare (`AllowOverride FileInfo`,
une table de types sans APK ni woff2) pour y éprouver le `.htaccess`.
Cette dernière partie est sautée si Apache est absent
(`apt install apache2`).

Seize sabotages le font tomber, chacun sur le constat attendu : le
README publié (garde-fou du script retiré), un `.bat` publié, une clé
`sb_secret_`, une clé `service_role`, l'image de partage en chemin
relatif, l'admin indexable, le lien jamais lu, le jeton laissé dans
l'adresse, la vitrine qui ne passe plus la main, le numéro perdu au
rafraîchissement, un lien relatif dans la page 404, `Options -Indexes`
dans le `.htaccess` (dix-huit constats d'un coup : erreur 500), la
redirection vers `www` retirée, et les types de l'APK, des polices et du
manifeste oubliés.

## La charte graphique

La charte de BIZZOO s'applique aux deux applications et à la vitrine.

| | |
|---|---|
| Police | **Poppins**, 400/500/600/700 |
| Bleu | `#0047D9` |
| Orange | `#FF8A00` |
| Encre | `#1F2937` |
| Fond | `#F5F7FA` |

**La police est embarquée, pas appelée.** Les quatre graisses sont dans
`client/polices/` et `admin/polices/` — 31 ko en tout — et les deux
service workers les gardent hors connexion. Une application qui irait
chercher Poppins chez Google perdrait sa typographie au premier creux de
réseau, ce qui, ici, arrive tous les jours. Aucune requête ne sort de
l'application : le banc le vérifie en écoutant *tout* ce que la page
demande.

**Le logo n'est pas une image.** « Bizz » en bleu, « oo » en orange et
les deux points sous le B sont écrits par la feuille de style
(`motSymbole()` dans `ui.js`). Il reste net à toutes les tailles, suit la
couleur du thème, et ne coûte aucun fichier. L'icône de l'application —
le B au panier — reste une image : c'est un dessin fait pour un écran
d'accueil, et elle n'a pas sa place à côté du mot. Posée en tête du menu
latéral, elle donnait deux marques l'une contre l'autre.

**Sur l'orange, du blanc — c'est le choix de la DA corrigée, pas le plus
lisible.** Du blanc sur `#FF8A00` donne **2,36:1**, sous le seuil de
4,5:1 des règles d'accessibilité ; l'encre sombre `#1F2937` y donnait
**6,21:1**, et la version 3.42 l'employait pour cette raison. La DA
corrigée remet du blanc sur « Ajouter au panier » et « Passer la
commande » : la marque a tranché. On compense ce qui peut l'être sans
toucher à la couleur — un texte **gras** (700) et un peu plus grand.

Pour revenir au sombre, une ligne par feuille de style : le jeton
`--orange-texte` vaut `#FFFFFF` ; le passer à `#1F2937` dans
`client/styles.css`, `admin/styles.css` et `index.html`, et tous les
composants orange suivent. Le banc vérifie que le blanc et le gras sont
bien posés, et **affiche** le contraste à chaque passage plutôt que de
le taire.

**Un défaut que seule la capture d'écran a montré.** La barre du haut est
passée du bleu au blanc ; ses boutons, eux, sont restés blancs — donc
invisibles. Aucun constat ne tombait : les boutons étaient là, à la
bonne place, avec les bonnes icônes. Le banc mesure maintenant la
**luminance** du fond de la barre et celle de ses boutons, et exige que
les seconds s'y détachent.

### Le banc de la charte

```bash
bash tools/servir.sh &                 # le serveur local, sur 5180
PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-da.mjs
```

Playwright n'est **pas** une dépendance du projet : les deux
applications n'en ont aucune, et un banc ne justifie pas d'en ajouter
une. Le chemin se donne par `PLAYWRIGHT`, l'adresse par `BANC_URL` si le
serveur n'est pas sur 5180, le navigateur par `CHROMIUM` pour en
désigner un déjà installé, et `CAPTURES=<dossier>` range les images.

Quarante-trois constats sur les deux applications, à quatre largeurs
d'écran (360, 390, 768, 1440 px). Ils regardent ce qu'une capture
d'écran ne montre pas :

- la police **affichée** est Poppins (`document.fonts.check`) — une
  `@font-face` qui échoue ne laisse aucune trace, le navigateur retombe
  sur la police du système et la page reste belle ;
- rien n'est demandé hors de l'application ;
- les couleurs sont relevées **sur les éléments**, pas dans la feuille de
  style — une règle peut être écrite et surchargée dix lignes plus bas ;
- rien ne déborde en largeur, à aucune des quatre largeurs.

Quatre sabotages les font tomber, onze constats en tout : renvoyer la
police chez Google, remettre l'ancien bleu, repasser les boutons de la
barre en blanc, retirer la bascule de l'écran d'ordinateur.

> **Un seuil qu'on ne peut pas franchir ne prouve rien.** « Le catalogue
> s'étale » vérifiait une largeur de plus de 700 px — mais la colonne du
> téléphone en fait déjà 720. Le constat restait vert avec l'écran
> d'ordinateur entièrement désactivé. Le seuil est à 900.

## La DA corrigée : les huit écrans

La DA corrigée ne change pas seulement des couleurs : elle refait la
**structure** de l'application cliente. Huit écrans — Accueil,
Catégories, Nos boutiques, Fiche boutique, Fiche produit, Panier,
Paiement, Confirmation — et, pour les tenir, une barre du bas plus
courte et des écrans de parcours qui n'en ont plus.

### La barre du bas : quatre onglets

| Onglet | Ce qu'il ouvre |
|---|---|
| Accueil | l'accueil de BIZZOO — toujours, même depuis une boutique |
| Catégories | la liste des catégories |
| Favoris | les produits aimés et les boutiques suivies |
| Compte | le compte, et en bas : **À propos de BIZZOO**, **Nous contacter**, **Actualiser le catalogue** |

Ce qui n'est plus un onglet a gardé une place : la **recherche** est la
barre-pilule en tête de l'accueil (et la loupe de l'écran Catégories) ;
le **panier** est le bouton de la barre du haut ; les **infos** de
l'enseigne sont sous Compte → À propos de BIZZOO.

### Les écrans de parcours : pas d'onglets, une action en bas

Fiche boutique, fiche produit, panier, paiement et confirmation n'ont
pas de barre d'onglets, comme sur la DA : on y avance, on n'y navigue
pas. L'action qui fait avancer est **fixée en bas** de l'écran :

| Écran | Action du bas |
|---|---|
| Fiche produit | le compteur, et **Ajouter au panier** — orange |
| Panier | **Passer la commande** — orange |
| Paiement | **Payer 352 000 FCFA** — bleu, le montant dans le bouton |

La DA ne met l'orange que sur ce qui ajoute au panier et sur le passage
de commande ; payer est bleu. **L'action ne survit pas à son écran** :
revenu à l'accueil, elle disparaît et la barre d'onglets revient. C'est
le défaut qui se voit le moins en développant — on va toujours de
l'avant — et le plus en vrai.

### Écran par écran

- **Accueil**, dans l'ordre de la DA : la recherche, les catégories en
  ronds, la bannière, puis **Nos boutiques partenaires** — rien entre la
  bannière et les boutiques. L'offre du jour, la publicité et les
  produits populaires viennent dessous. Les ronds restent **huit, sur
  deux rangées**, comme demandé pour l'accueil ; la DA n'en dessine
  qu'une rangée de quatre, et avec des photos là où l'application a ses
  icônes (une catégorie n'a pas d'image en base).
- **Nos boutiques** (« Tout voir ») : la liste entière et trois filtres.
  *Toutes* suit l'ordre de l'enseigne ; *Top* range les mieux notées et
  **écarte celles qui n'ont aucun avis** — les mettre en queue les ferait
  passer pour les plus mal notées ; *Proches de moi* trie par distance
  celles qui ont posé leur adresse sur la carte, les autres suivent sans
  distance. Une boutique sans avis écrit « Pas encore d'avis », jamais
  un zéro.
- **Fiche boutique** : la couverture, le logo, la note, le slogan, les
  atouts, **Suivre**, puis trois onglets — Produits, Avis, À propos.
  Sous « Produits », **les vignettes d'abord**, trois par rangée ; la
  vitrine de la boutique (bannières, ventes flash, promotions, rayons)
  vient dessous. Au-delà de neuf produits, un bouton ouvre la liste
  complète.
- **Fiche produit** : le cœur dans la barre du haut, le prix en bleu, la
  remise en pastille orange, et les **Spécifications** lues dans la
  description — ses lignes « Clé : valeur », dès qu'il y en a deux.
- **Panier** : « Mon panier (3) », « Supprimer tout » (qui demande
  confirmation), une corbeille par ligne, et le récapitulatif.
- **Paiement** : la méthode, l'adresse **résumée** quand elle est déjà
  connue (« Modifier » rouvre le formulaire, déjà rempli), et « Payer ».
- **Confirmation** : la coche, les confettis, « Voir mes commandes » et
  « Retour à l'accueil ».

### Ce que la maquette montre et qui n'est pas vrai ici

Une maquette montre un exemple ; l'application affiche des faits. Ce qui
suit est dessiné sur la DA et n'a **pas** été recopié :

| Sur la DA | Dans l'application | Pourquoi |
|---|---|---|
| Livraison « 5 000 FCFA » | « À convenir avec la boutique » | aucun frais de livraison n'est fixé nulle part |
| « Orange Money », « Carte bancaire » | MTN, Moov, Celtiis | les opérateurs du Bénin ; FeexPay n'ouvre pas la carte ici |
| « Vous allez recevoir un e-mail » | le numéro de commande à garder — ou, avec un compte, « vous serez prévenu à chaque étape » | BIZZOO n'envoie pas d'e-mail |
| « Commande confirmée ! » | seulement quand la base a constaté le paiement | l'annoncer avant, c'est promettre une commande que la boutique n'a peut-être jamais reçue |
| « Produits certifiés », « Service pro » | Livraison rapide, **Paiement sécurisé** (seulement quand le paiement en ligne est ouvert), SAV irréprochable | les atouts reprennent les promesses de BIZZOO ; « certifiés », personne ne l'a vérifié |

Avec KkiaPay, l'opérateur se choisit dans la fenêtre de KkiaPay : l'écran
montre une seule ligne, « Mobile Money ou carte », plutôt que trois
choix qui ne serviraient à rien.

### La vitrine

La page d'accueil du site (`index.html`) suit la DA : boutons en pilule,
blanc sur l'orange, et le titre « Vos boutiques préférées **dans une
seule app !** ». Le téléphone dessiné en HTML — il montrait une liste
que l'application n'avait plus — est remplacé par une **vraie capture**
de l'application, et une galerie « L'application en images » en montre
quatre (accueil, boutique, produit, paiement), rangées dans `vitrine/`.
Les noms de boutiques sont ceux de BIZZOO, aucune note n'y est inventée,
et une ligne le dit : les produits et les prix sont des exemples. La
« carte bancaire » a quitté les textes : l'application n'encaisse que
le Mobile Money.

### Le banc des huit écrans

```bash
PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-da-ecrans.mjs
```

Quarante-sept constats en sept parties : les quatre onglets ; les écrans
de parcours sans onglets, leur action en bas et sa couleur ; l'ordre de
l'accueil et les filtres de « Nos boutiques » ; la fiche boutique ; le
panier ; le paiement ; la confirmation. Douze sabotages les font tomber,
chacun sur le constat attendu : un cinquième onglet, l'action du bas
jamais retirée, la fiche produit avec ses onglets, « Payer » en orange,
les boutiques sans avis dans « Top », « Paiement sécurisé » affiché
paiement fermé, « 5 000 FCFA » de livraison, « Orange Money » ajouté, la
coche « confirmée » sur une commande à payer, l'offre du jour remise
entre la bannière et les boutiques, le pluriel pour une seule boutique
(« Elles vous rappellent »), la bannière de la boutique devant ses
vignettes.

Trois bancs ont suivi la nouvelle structure : `banc-accueil-enseigne.mjs`
(les tuiles et la fiche de boutique), `banc-entete.mjs` (le nom long
d'une boutique tient sur deux lignes sans être coupé, son slogan sur
trois) et `banc-da.mjs` (le blanc sur l'orange).

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

### Éprouver la base avant de la livrer

```bash
tools/eprouver-base.sh
```

Monte un PostgreSQL jetable, y pose le décor de Supabase (rôles `anon`
et `authenticated`, schéma `auth`, stockage, temps réel), charge
`schema.sql` **tel qu'il part chez le client** — deux fois, pour vérifier
qu'il se rejoue —, **rejoue ensuite chaque fichier de `supabase/` comme
le fait l'éditeur SQL** (tout d'un bloc, sans compte connecté), puis
essaie de forcer chaque porte. Plus de 1 000 constats, plus les 118
contrôles de l'état des lieux ; la sortie nomme celui qui cède.

Pourquoi un vrai moteur : les tests des applications simulent la base.
Ils valident l'écran, jamais les **déclencheurs** — ceux-ci ne
s'exécutent que pour de vrai. Six défauts leur avaient échappé, dont un
qui ne se serait manifesté qu'au premier vrai paiement.

Sept règles pour que ce banc garde sa valeur :

- **On simule le décor, jamais la serrure.** RLS, déclencheurs et
  fonctions viennent tels quels de `schema.sql`. Le jour où l'on
  simulerait l'un d'eux, le banc ne prouverait plus rien.
- **Un essai doit passer par le compte qui a vraiment la main.** Essayer
  de forcer une porte avec un compte que le *premier* garde-fou arrête
  déjà, c'est croire éprouver le second. Retirer « Seul KkiaPay déclare
  un paiement » n'a d'abord rien cassé : l'essai se heurtait plus tôt à
  « seule l'équipe suit une commande ». Sabotez volontairement une règle
  et vérifiez que le banc rougit — sinon, l'essai regarde ailleurs.
  **Et sabotez-la dans `schema.sql` ET dans la migration qui la
  redéfinit** : les fichiers se rejouent après le schéma, si bien qu'une
  faille ouverte d'un seul côté est refermée par l'autre, et le banc
  reste vert pour une raison qui n'a rien à voir avec ce qu'on croit
  éprouver. L'aligneur n'y change rien : il recopie les **corps de
  fonctions**, pas les `grant`, les `policy` ni les `drop`. Un `grant`
  répété dans deux migrations reste donc à corriger — et à saboter — en
  autant d'endroits. Ouvrir l'écriture du journal des versements dans le
  seul `schema.sql` n'a rien cassé : les deux migrations la refermaient
  juste après, et l'essai n'était jamais éprouvé.
- **Un fichier envoyé au gérant doit passer sans compte connecté, et ne
  jamais porter une fonction périmée.** L'éditeur SQL de Supabase exécute
  tout d'un bloc et **annule tout à la première erreur** : une simple
  requête de vérification appelant une fonction réservée à l'enseigne
  fait échouer le fichier entier, et le gérant n'obtient rien. Et comme
  les fichiers se rejouent dans l'ordre alphabétique, celui qui garde une
  ancienne version d'une fonction défait en silence ce qu'un autre venait
  de poser. `node tools/aligner-migrations.js` recopie dans chaque
  fichier le corps que `schema.sql` donne à la fonction : `schema.sql`
  reste la seule source de vérité.
- **La base du gérant existe déjà : chez lui, le corps d'un
  `create table if not exists` n'est jamais lu.** Une colonne ajoutée là
  après coup n'arrivera jamais dans sa base — il faut la répéter en
  `alter table … add column if not exists`. Le banc refait son chemin
  (l'ancien `schema.sql`, puis les fichiers envoyés) et compare colonne
  par colonne à une base neuve : il nomme celles qui manqueraient.
  **Les colonnes ne suffisent pas** : la base en ligne les avait toutes,
  et pourtant pas la règle du stock — posée dans le corps du
  `create table` — ni la fermeture de quatre fonctions à `anon`. Le banc
  compare donc aussi, à la lettre, **chaque règle** (`pg_constraint`) et
  **chaque droit d'exécution** des visiteurs et des comptes connectés.
- **Et dans l'autre sens : `schema.sql` seul doit arriver au même
  point.** C'est lui qui installe une base neuve ; ce qu'un fichier à
  coller pose doit donc s'y trouver aussi. Le banc monte une troisième
  base avec `schema.sql` et rien d'autre, et la compare — colonnes,
  règles, droits — à celle qui a tout reçu. Le premier jour, il a trouvé
  `est_equipe()` ouverte aux visiteurs dans `schema.sql` seul, alors
  qu'un fichier à coller la fermait : la base en ligne était juste, une
  base neuve ne l'aurait pas été.
- **Un fichier qui pose une fonction pose aussi les colonnes qu'elle
  remplit — même celles qu'il n'a pas inventées.** PostgreSQL ne relit le
  corps d'une fonction qu'au moment de l'*exécuter* : un fichier peut donc
  installer une règle d'écriture qui remplit une colonne absente, passer
  sans un mot, et arrêter la boutique à la commande suivante. C'est arrivé
  en production — `marge-bizzoo.sql` posait la règle qui fige le code du
  produit vendu sans poser la colonne qui le reçoit, et la base répondait
  `record "new" has no field "code"` à chaque panier validé.
  `tools/fichiers-autonomes.sh` relit chaque fichier et nomme la fonction,
  la colonne et la ligne à ajouter ; il tournait sur quatre fichiers et y
  a trouvé quinze trous du même genre. Et
  [`supabase/tests/50-reparation.sql`](supabase/tests/50-reparation.sql)
  refait la panne pour de vrai — colonne retirée, base à l'arrêt — puis
  colle le fichier de réparation et vérifie qu'elle repart.
- **Un fichier qui appelle une fonction la pose aussi.** Le même piège,
  un cran plus loin : une fonction n'appelle pas que des colonnes, elle
  appelle d'autres fonctions. Et une fonction née *après* la base du
  gérant manque chez lui alors qu'elle est là chez nous. C'est arrivé
  quand `creer_commande` s'est mise à demander `compte_exige()` : trois
  fichiers portaient l'appelante, aucun ne portait l'appelée — collé seul
  sur une base d'avant, chacun passait sans broncher pour refuser toute
  commande à la première vente. `tools/fichiers-autonomes.sh` le contrôle
  aussi : si un fichier nomme `public.f(` et que `f` naît dans une
  migration, ce fichier doit la poser lui-même. La règle a trouvé six
  emprunts du même genre le jour où on l'a écrite, dont deux qui
  dataient des comptes revendeurs.
- **Un fichier qu'on envoie au gérant doit être LU, pas seulement
  exécuté.** `etat-des-lieux.sql` passait depuis toujours dans le banc,
  avec les autres fichiers — et cela ne prouvait rien : une requête de
  *lecture* réussit même quand elle répond faux. Un de ses contrôles
  cherchait la garde de l'accusé de réception dans les droits de colonne,
  là où une base Supabase donne `grant all` d'office : il aurait répondu
  « MANQUANT » sur une base parfaitement saine, et envoyé le gérant
  réparer ce qui allait bien. Le banc rejoue donc l'état des lieux sur
  une base où tout vient d'être posé, **où la réponse est connue
  d'avance** : un seul « MANQUANT » y est un échec. Il l'a trouvé à sa
  première exécution.

Le même banc tourne à chaque poussée touchant `supabase/`
(`.github/workflows/base.yml`).

### Éprouver le paiement sans FeexPay

`tools/eprouver-paiement.sh` force les portes des deux fonctions Edge —
celle qui ouvre un paiement, et celle qui reçoit la notification. Le banc
de la base ne les voit pas : elles tournent chez Supabase, en Deno, et
parlent à un service extérieur. C'est pourtant là qu'ont vécu les deux
défauts de la première mise en service — un tiret dans le libellé que MTN
refusait, et une panne 502 chez FeexPay affichée au client comme un
refus.

**FeexPay y est une doublure** qui répond ce qu'on lui dit de répondre et
note ce qu'on lui a envoyé. Aucun appel ne sort. Un banc qui dépendrait
de leur API rougirait les jours de panne et ne prouverait rien les autres
jours. Deno n'étant pas installable partout, les fonctions sont chargées
par Node avec une doublure de `Deno` : le code éprouvé est celui qui
part en production, sans une ligne modifiée pour l'essai.

Cent cinq constats, dont ceux qui tiennent tout le reste : le montant
encaissé vient toujours de la réponse que FeexPay donne à **notre**
question — jamais du payload d'une notification que **personne ne
signe** ; un succès sans montant n'encaisse rien ; le frein de trente
secondes est vérifié AVANT d'appeler FeexPay, sinon le téléphone sonne
quand même ; et le jeton ne sort ni vers le client, ni dans le journal.
Chacune de ces règles a été sabotée exprès pour vérifier que le banc
rougit.

**L'API V2 de FeexPay**, depuis qu'ils ont retiré la V1 — leur 502 sur
toutes leurs adresses n'était pas une panne. Elle renverse des choses
qu'aucune relecture ne rattrape : le numéro porte désormais l'indicatif
(`2290197444893`) là où la V1 le *retirait*, l'opérateur passe du corps à
l'adresse (`…/requesttopay/mtn`), le jeton sort du corps pour ne vivre
que dans l'en-tête, `callback_info` devient une chaîne, et le montant est
borné à 100 – 2 000 000 FCFA. Chaque inversion a son constat.

La vérification V2 (`…/public/single/status/<ref>`) **exige le jeton**,
là où la V1 ne demandait rien — on s'en félicitait même. L'oublier ne
casserait rien de visible : les commandes resteraient simplement « à
payer », et personne ne saurait pourquoi. Deux constats le tiennent, un
par fonction. Et `FAILED` est désormais un verdict annoncé au client,
plus un sablier de quatre-vingt-dix secondes sur un refus déjà prononcé.

Les **trois opérateurs du Bénin** ont chacun leur adresse : `…/mtn`,
`…/moov` et `…/celtiis_bj` — qui n'est pas `celtiis`, et que déduire des
deux autres aurait envoyé les clients Celtiis nulle part. Moov peut
répondre `FAILED` dès l'ouverture (solde insuffisant) ou `SUCCESSFUL` tout
de suite ; Celtiis renvoie une enveloppe SOAP et un `PENDING`. Aucun de
ces cas n'encaisse quoi que ce soit : seule la vérification tranche.

**Le webhook V2 n'est toujours pas signé**, et leur documentation
l'assume en renvoyant la charge au marchand : « c'est à vous de faire vos
contrôles côté serveur ». C'est exactement ce que fait ce fichier.

`FEEXPAY_RESEAUX` referme **un seul réseau** sans redéployer —
`'mtn,moov'` ferme Celtiis, effacer le réglage le rouvre. C'est arrivé
deux jours après la migration : MTN et Moov passaient, Celtiis répondait
« Celtiis BJ API Error » chez l'agrégateur. Laisser le réseau ouvert
envoyait chaque client Celtiis dans le mur ; le retirer du code, c'était
un déploiement pour une panne peut-être longue de deux heures. Un état
temporaire appartient à la configuration.

`FEEXPAY_STATUT` sert du même coup d'**interrupteur général** : posé à la chaîne vide, il ferme
le paiement en ligne sans redéploiement — utile le jour où FeexPay
retirera la V2 comme il a retiré la V1. Ouvrir un encaissement qu'on ne
saura pas constater, c'est prendre l'argent d'un client dont la commande
restera « à payer » pour toujours ; le banc l'éprouve en rechargeant les
deux fonctions avec ce secret vide.

Il tourne à chaque poussée touchant `supabase/functions/`
(`.github/workflows/paiement.yml`).

### Savoir où en est la base

[`supabase/etat-des-lieux.sql`](supabase/etat-des-lieux.sql) répond en
une requête, sans rien modifier : chaque fonctionnalité y est vérifiée
dans le catalogue de PostgreSQL, et ce qui manque est nommé. Plus
fiable que de se demander quel fichier a été exécuté et quand.

`schema.sql` **se relance sans danger** : tout y est en `if not exists`
ou `create or replace`, et aucune donnée de départ ne déclenche un
garde-fou de l'application — un seul `raise` annulerait tout le fichier,
l'éditeur SQL de Supabase exécutant l'ensemble d'un bloc.

### Le stockage des médias

Un seul seau, `produits`, et ce n'est pas lui qui sépare : c'est le
**dossier**, et `peut_deposer()` dit qui a le droit d'écrire dans lequel.

| Dossier | Contenu | Qui dépose |
|---|---|---|
| *(racine)* | photos et vidéos des produits | toute l'équipe |
| `boutique/`, `boutiques/` | logos et devantures | administrateurs |
| `slider/` | slider d'une boutique | administrateurs |
| `enseigne/` | slider et publicité BIZZOO, photos des catégories (`enseigne/categories/`) | superadministrateur |

[`supabase/etat-du-stockage.sql`](supabase/etat-du-stockage.sql) ne
modifie rien et répond en **une seule requête** — l'éditeur SQL de
Supabase n'affiche que le résultat de la dernière d'un bloc, et tout ce
qui précède se perdrait en silence. Il montre les seaux, les règles, le
poids par dossier et par type, la part du gigaoctet gratuit, les plus
gros fichiers, et les **orphelins**.

Un orphelin est un fichier que plus aucune ligne de la base ne désigne :
une photo retirée d'un produit reste dans le seau, la base ne la suit
plus, le stockage la garde. La liste des fichiers « encore utilisés »
doit rester **complète** — `demandes.apres` en fait partie, car un logo
proposé et pas encore validé n'est dans aucune colonne. En cas de doute,
on garde un fichier de trop : une suppression ne se rattrape pas.

Pour faire le ménage, exporter le résultat en CSV puis :

```powershell
.\tools\menage-stockage.ps1 -Csv "resultat.csv" -Simulation   # pour voir
.\tools\menage-stockage.ps1 -Csv "resultat.csv"               # pour faire
```

Le script ne supprime que les lignes marquées `ORPHELINS`, et **ne
manipule aucun secret** : il se connecte avec le compte administrateur
de la personne qui le lance, et ce sont les règles de la base qui
autorisent chaque effacement — le même appel que celui de l'application.
La clé `service_role`, qui contourne toutes les règles, n'a rien à faire
sur un poste de travail.

> Supprimer une ligne de `storage.objects` en SQL ne supprime **pas** le
> fichier : les octets vivent ailleurs, et il ne resterait qu'un fichier
> devenu inatteignable. La suppression passe par l'API Storage.

## Le code d'un produit

Chaque produit reçoit à sa création un **code** : un numéro, rien que
des chiffres, donné par la base. Il ne se choisit pas, ne se corrige
pas, ne se réutilise pas — **pas même par un super administrateur**.
C'est ce qui en fait un repère : un code dicté au téléphone désigne un
seul produit, aujourd'hui et dans dix ans.

À ne pas confondre avec la **référence**, qui reste ce que la boutique
veut en faire : elle la choisit, la change, la laisse vide. Deux choses
différentes, deux colonnes.

Le code s'affiche **avant** la référence sur la fiche produit, et
accompagne l'article partout où il est nommé : message WhatsApp d'une
demande de prix, récapitulatif de commande envoyé à la boutique, lignes
de commande dans l'application admin, message de la boutique au client.
Les commandes le **figent** avec le nom et le prix : c'est ce qui a été
vendu.

Ce qui le protège, dans la base : le déclencheur `produits_code` donne
le code à l'insertion — ce que l'application envoie dans cette colonne
n'est jamais écouté — et le remet à sa valeur d'origine à chaque
modification. Un index unique garantit que deux produits ne le
partagent pas. Sur une base déjà en service,
[`supabase/code-produit.sql`](supabase/code-produit.sql) attribue leur
code aux produits existants, du plus ancien au plus récent.

## La marge de BIZZOO

Le modèle est celui d'une place de marché :

```
prix de vente = prix BIZZOO + marge
bénéfice      = prix de vente − prix BIZZOO
```

La boutique annonce le **prix BIZZOO** — ce qu'elle veut toucher.
L'enseigne y ajoute **sa marge**, fixée au moment où elle crée la
boutique. La somme est le **prix de vente**, le seul que le client voie.
La différence revient à BIZZOO.

Trois règles, et elles sont dans la base, pas à l'écran :

1. **La marge appartient à l'enseigne.** Une boutique ne la retouche
   pas — elle fixerait sinon elle-même la commission prise sur elle. Le
   déclencheur `boutique_verrous` refuse toute écriture qui ne vienne
   pas d'un super administrateur. Elle la **lit** dans ses réglages,
   sans pouvoir la changer.
2. **Le prix BIZZOO ne sort pas.** Il vit dans `produits_prive`, hors
   de portée des clients et des autres boutiques : il dirait à chacun ce
   que la boutique touche vraiment.
3. **Ce qui a été vendu est figé.** La ligne de commande garde le prix
   BIZZOO et le taux du jour de la vente. Changer une marge aujourd'hui
   ne réécrit pas les comptes d'hier.

Conséquence à l'écran : sur la fiche produit, la boutique saisit le prix
BIZZOO ; le **prix de vente se calcule et ne se saisit pas**. C'est ce
qui rend les comptes de l'enseigne vrais — un prix arrondi à la main
ferait mentir le bénéfice annoncé. Il n'y a plus non plus de taux par
produit : la marge est celle de la boutique, une fois pour toutes.

### Ce que rapportent les boutiques

Le tableau de bord du super administrateur mène à un écran qui ne compte
que les **ventes encaissées** — une commande à payer n'est pas une
vente. Pour chaque produit vendu : prix BIZZOO, marge, prix de vente et
bénéfice, avec un filtre par **boutique** et par **période** (7 jours,
30 jours, ce mois, tout).

Les chiffres viennent de `statistiques_ventes()`, réservée à l'enseigne
par la fonction elle-même : un administrateur de boutique y verrait la
commission prise sur ses voisins. Un produit vendu à deux tarifs
différents fait deux lignes, et non une moyenne qui ne correspondrait à
aucune vente réelle.

### Ce que vend votre boutique

Une boutique, elle, ouvre le **même écran** et voit le sien : ce qu'elle
a vendu, et ce qui lui revient au prix BIZZOO. Ni le prix payé par le
client, ni le taux de marge, ni le bénéfice de l'enseigne.

Ce sont deux fonctions distinctes, et la seconde est délibérément plus
pauvre :

| | `statistiques_ventes()` | `statistiques_boutique()` |
|---|---|---|
| Qui | l'enseigne | toute l'équipe |
| Portée | toutes les boutiques | celle du compte, toujours |
| Paramètres | dates **+ boutique** | dates seulement |
| Colonnes | prix de vente, marge, bénéfice | prix BIZZOO et total |

Les colonnes de l'enseigne ne sont pas *masquées à l'écran* : elles ne
sont pas dans le résultat. Une colonne qu'on se contente de cacher se
relit avec n'importe quel outil — c'est le défaut qui laissait autrefois
l'acheteur lire la marge sur sa propre commande.

Et il n'y a **pas de paramètre `boutique`** : c'est toujours celle du
compte connecté. Un paramètre serait une invitation à viser la voisine,
et il faudrait le défendre à chaque appel. Choisir l'écran selon le rang
n'est donc qu'une politesse ; la serrure est dans la base, et
`tests/99b-statistiques-boutique.sql` la force à chaque livraison —
deux boutiques dans **une même commande**, et chacune n'y lit que sa
part. Ni un panier abandonné ni une ligne que la boutique a annulée n'y
entrent.

### Retrouver un client

Un client appelle : « j'ai commandé mardi, rien n'est arrivé ». **Fiches
clients** le retrouve par son **nom** ou son **numéro** — avec ou sans
espaces, avec ou sans indicatif : c'est la base qui les rapproche, en
retirant l'indicatif *de ce compte-là* plutôt qu'une longueur devinée.

Sa fiche porte ce qu'il a commandé, ce qu'il a réellement payé, et
chaque commande une par une.

**Rien ne s'y modifie.** Un nom, un numéro, une adresse se corrigent
depuis le compte du client — la base refuse de toute façon à l'enseigne
de les écrire. L'écran sert à appeler et à trancher un litige avec les
commandes sous les yeux, pas à tenir un fichier.

**Réservé à l'enseigne.** Une boutique voit déjà le nom et le numéro sur
*ses* commandes ; lui ouvrir la liste entière, ce serait lui remettre le
fichier clients de toutes les autres.

Deux pièges évités, et tous deux éprouvés dans
[`tests/99c-fiche-client.sql`](supabase/tests/99c-fiche-client.sql) :

- **La recherche ne déverse pas la liste.** Le filtre du numéro est un
  « ou ». Sans garde, chercher un nom sans chiffre le réduirait à
  `like '%%'` — vrai pour tout le monde — et une recherche par nom
  rendrait le fichier entier. Le banc le prouve en retirant la garde :
  chercher « brice » rend alors tous les comptes.
- **Un numéro non vérifié ne désigne personne.** Les commandes passées
  *avant* le compte ne remontent que sur un numéro **vérifié par SMS**,
  et de moins de dix-huit mois : exactement la règle de
  `rattacher_mes_commandes`, pas une règle voisine. Deux clients peuvent
  taper le même numéro ; l'un lirait sinon les achats de l'autre. Sur la
  fiche, une commande pas encore rattachée le dit.

### Le journal des versements

Une commande ne garde que son **état actuel** : payée, ou non. Ce qui
s'est passé en route n'était nulle part — une demande partie sur un
mauvais numéro, un versement incomplet, un client qui s'y reprend à trois
fois, de l'argent arrivé pour une commande introuvable.

Pire : en réussissant, `marquer_payee` **efface la remarque** de la
commande. Un encaissement effaçait donc la trace de ses propres échecs.

D'où `public.versements` : **une ligne par tentative**, jamais modifiée
ensuite. C'est ce qui permet de répondre à « combien d'échecs cette
semaine » et « chez quel opérateur ». Un journal qu'on met à jour ne
garde que la fin de l'histoire — et la fin est déjà sur la commande.

**Personne ne l'écrit à la main, pas même l'enseigne.** Aucune règle
d'écriture n'est posée sur la table : les seules écritures viennent des
fonctions `security definer` du serveur, qui passent au-dessus de RLS. Un
journal qu'on peut retoucher ne prouve rien le jour où il faudrait qu'il
prouve quelque chose.

**Pas de clé étrangère vers `commandes`**, et c'est voulu : effacer une
commande ne doit pas effacer la trace de l'argent. Le numéro est recopié
dans le journal, figé, pour que la ligne se lise encore toute seule.

**L'opérateur n'est connu qu'à l'ouverture** — c'est le client qui
choisit MTN, Moov ou Celtiis, et ni la notification ni la vérification ne
le rappellent. La fonction Edge le transmet donc à `noter_reference`, et
les lignes suivantes de la même commande le reprennent d'elles-mêmes :
la règle vit dans `noter_versement`, une seule fois, plutôt qu'à trois
endroits où elle finirait par diverger.

À l'écran, deux chiffres qui **ne se mélangent pas** : *entré* ne compte
que les lignes encaissées, *échecs* se comptent sans s'additionner. Une
demande encore ouverte n'est pas un échec. Additionner les tentatives
ferait un chiffre d'affaires imaginaire — c'est exactement l'erreur qu'un
journal doit empêcher, et
[`tests/99d-journal-versements.sql`](supabase/tests/99d-journal-versements.sql)
la provoque exprès pour vérifier que le banc rougit.

**Le journal ne remonte pas le passé** : ce qui n'a jamais été noté ne
peut pas l'être après coup. Il commence le jour où le fichier est
exécuté.

### Les codes promo

**Une remise sort de la marge de l'enseigne, jamais de la poche d'une
boutique.** La boutique touche son prix BIZZOO en entier, comme si le
code n'existait pas : elle n'a pas décidé cette promotion, elle n'a pas
à la payer. C'est pour cela que la remise se pose sur la **commande** et
jamais sur les lignes — dont le prix et le prix BIZZOO restent figés.

**Et c'est pour cela qu'il y a un plafond.** Une remise ne descend jamais
en dessous de ce que les boutiques doivent toucher. Un code de 80 % sur
un article qui ne laisse que 40 % de marge est ramené à 40 %. Sans lui,
l'enseigne paierait la différence de sa poche, à chaque vente, sans s'en
apercevoir avant de faire les comptes.

Un code porte une remise en **pourcentage** ou en **montant**, et peut
exiger un montant minimum, un nombre total d'utilisations, une seule
fois par client, et une date de fin. **Les utilisations se comptent sur
les commandes payées** : un panier abandonné n'a rien coûté à personne,
et ne doit pas manger le quota d'un vrai client.

**Une seule règle, lue par les deux côtés.** `verifier_code()` annonce la
remise au panier, `creer_commande()` l'applique — et toutes deux
appellent `remise_du_code()`. C'est la même discipline que `mes_prix()`
et `ligne_a_l_ecriture()` pour les prix revendeur : deux calculs séparés
finiraient par diverger, et le client paierait autre chose que ce qu'on
lui a montré. Le banc le prouve en divisant le sous-total d'un seul côté.

**Un code refusé ne tue pas la commande** : le panier est bon, c'est le
code qui ne vaut rien. La commande passe à plein tarif plutôt que de
perdre un client pour une ristourne. Et **« fermé » se refuse comme
« inconnu », mot pour mot** — distinguer les deux dirait à qui essaie des
codes au hasard lesquels ont existé.

**Le champ n'apparaît pas quand le paiement en ligne est fermé.** La
commande part alors directement chez chaque boutique par WhatsApp :
aucune commande n'est créée, BIZZOO n'encaisse rien, il n'y a pas de
marge sur laquelle prendre une remise. Offrir le champ ferait voir
18 000 au client, qui enverrait ensuite un message disant 20 000.

**Un piège fermé au passage.** Le bénéfice se calcule *ligne par ligne*,
alors qu'un code s'applique à la *commande* : sans correction, le
bénéfice affiché serait surévalué de toutes les remises accordées.
`remises_periode()` les répartit au prorata de ce que chaque boutique
pèse dans la commande, et l'écran les retranche.

### Où en est ma commande

Une boutique fait avancer sa ligne en **cinq** pas :

```
nouvelle → vue → préparée → en livraison → remise
```

`en_livraison` manquait : la marchandise passait du comptoir au client
sans que rien ne dise qu'elle était partie, et personne ne pouvait
répondre à « où en est ma commande ? » entre les deux.

**Le client voit cet avancement**, boutique par boutique. Une commande
qui traverse deux boutiques en montre deux — l'une peut avoir remis
quand l'autre prépare encore. Pour une boutique donnée, l'étape affichée
est celle de sa ligne **la moins avancée** : annoncer « remis » parce
qu'un article sur trois l'est ferait attendre le client chez lui une
livraison déjà faite.

### Qui dit quoi

`remise` est ce que la **boutique** déclare. `confirme_le` est ce que le
**client** constate. Ce sont deux paroles différentes, et c'est pour cela
que la confirmation est une **colonne à part** et non un sixième état
dans la même chaîne.

Si l'un pouvait signer pour l'autre, la déclaration de la boutique
n'aurait plus de contrepoids — et c'est justement elle qu'un litige vient
interroger. La base l'empêche des deux côtés :

- `ligne_verrous` lève sur tout changement de `confirme_le` hors du
  drapeau que seule `confirmer_reception()` pose ;
- `confirmer_reception()` vérifie `ma_commande()` : l'enseigne elle-même
  est refusée, ce n'est pas elle qui a reçu la marchandise ;
- **on ne confirme que ce qui a été remis** — confirmer avant que la
  boutique n'ait rien déclaré ne voudrait rien dire.

[`tests/99f-cycle-commande.sql`](supabase/tests/99f-cycle-commande.sql)
force les quatre portes. Trois sabotages les font tomber : retirer la
garde du verrou, retirer la condition « remise », retirer le contrôle de
propriété.

**Une forme d'essai à ne pas confondre.** Une règle RLS ne *lève* pas :
elle *filtre*. Une écriture qui ne trouve aucune ligne autorisée réussit
en silence. Attendre un refus ferait échouer l'essai pour la mauvaise
raison — on constate donc que **rien n'a bougé**. Le verrou, lui, est un
déclencheur : il lève, et là `essai.refuse` est la bonne forme.

### Un `grant` de colonne ne retire rien : il faut retirer d'abord

`schema.sql` écrivait `grant update (etat) on commande_lignes`, et le
commentaire au-dessus affirmait que l'équipe n'écrivait *que* cette
colonne. **C'était faux**, et c'est une chose à savoir une fois pour
toutes : une base Supabase pose `alter default privileges in schema
public grant all … to anon, authenticated, service_role`. Chaque table
nouvelle naît donc avec `grant all` pour `authenticated` — un `grant` de
colonne par-dessus n'enlève rien, il ajoute à un droit déjà entier.

Le même fichier faisait pourtant les choses correctement quelques lignes
plus haut, pour la lecture : `revoke select … from authenticated`, puis
`grant select (…)`. On l'avait vu pour la lecture, manqué pour
l'écriture. Les deux vont désormais par paire :

```sql
revoke update on public.commande_lignes from authenticated;
grant  update (etat) on public.commande_lignes to authenticated;
```

Il y a donc **deux serrures** sur une ligne vendue. Le droit d'écriture,
qui ne porte plus que `etat` ; et le **déclencheur** `lignes_verrous`,
qui refuse en plus, ligne par ligne, toute écriture de `commande_id`,
`boutique_id`, `produit_id`, `nom`, `code`, `reference`, `prix`,
`prix_bizzoo`, `taux_marge`, `quantite`, `confirme_le` et `livreur_id`.
Le déclencheur a toujours tenu seul ; le retrait est ce qui rend vrai ce
que le commentaire disait déjà.

**Et un essai qui ne prouvait pas ce qu'il annonçait.** Les quatre
refus posés sur ces colonnes depuis le compte du chef de boutique
restaient verts *le retrait enlevé* : le déclencheur répondait à sa
place. Ils prouvent que la porte tient, pas **laquelle** des deux
serrures la tient. Un cinquième constat nomme la serrure — il lit le
droit lui-même, et tombe dès que le retrait disparaît des trois
fichiers.

**Un contrôle qui regardait le mauvais verrou.** L'état des lieux
demandait qu'aucune colonne autre que `etat` ne soit dans le droit
d'écriture de `authenticated` — vrai aujourd'hui, faux quand il a été
écrit : il aurait répondu « MANQUANT » sur une base parfaitement saine,
et envoyé le gérant réparer ce qui allait bien. Le banc ne le voyait
pas, parce qu'il *exécutait* `etat-des-lieux.sql` sans jamais **lire sa
réponse** : une requête de lecture réussit même quand elle répond faux.

`tools/eprouver-base.sh` rejoue donc maintenant l'état des lieux sur une
base où tout vient d'être posé, où la réponse est connue d'avance — **un
seul « MANQUANT » y est un échec du banc**. C'est ce contrôle qui a
trouvé celui-ci, à sa première exécution. Il y a aujourd'hui deux
contrôles là où il n'y en avait qu'un : le 80 regarde le déclencheur, le
92 regarde le droit.

## Le livreur

Un quatrième rôle, à côté de `superadministrateur`, `administrateur` et
`moderateur` : **`livreur`**. Il se crée comme les autres, depuis
Réglages → Comptes → **Créer un compte** : son adresse, son mot de
passe, **son nom**, **son numéro**, le rang « Livreur », puis pour qui
il porte.

### Son nom et son numéro se donnent à la création

Ils l'étaient déjà dans la fiche d'un compte existant — mais pas dans
l'écran de **création**, qui n'offrait même pas le rang « Livreur ». Il
fallait donc créer un modérateur, puis ouvrir sa fiche et changer son
rang : un détour que personne ne devine. Résultat sur la base en
service : un livreur sans nom ni numéro, que « Confier à un livreur »
affichait par son adresse e-mail. **Rien n'était rouge nulle part.**

Le nom est ce qu'on lit dans la liste ; le numéro est ce qu'on rappelle
quand le client n'est pas chez lui. Les laisser pour « plus tard », c'est
les laisser vides — plus tard n'arrive pas.

### Pour une boutique, ou pour BIZZOO

Un livreur se rattache à **une** boutique, ou à **aucune** — et aucune
veut dire **toutes** : c'est un livreur de l'enseigne. Toutes les
boutiques le voient dans « Confier à un livreur », toutes peuvent lui
confier une course, et ses courses arrivent dans une seule liste.
Comme pour les comptes d'enseigne, seul le superadministrateur peut le
décider.

**« Aucune boutique » veut donc dire deux choses dans cette base**, et
c'est ce qui rendait ce chantier délicat. Pour un `administrateur` ou un
`moderateur`, c'est un **compte d'enseigne** : quelqu'un qui regarde
par-dessus toutes les boutiques. Pour un `livreur`, c'est un **porteur**
qui les sert toutes. Ce qui empêche la confusion tient en un mot :
`est_compte_enseigne()` nomme les deux rangs qu'elle accepte, et le
livreur n'en est pas. Sans cette exclusion, lui permettre de porter
partout lui aurait donné d'un coup les commandes, le catalogue et les
chiffres de toutes les boutiques.

Le banc l'éprouve de front — *« il n'est pas un compte d'enseigne,
malgré sa boutique vide »* — et le sabotage de ce constat n'est tombé
qu'après avoir été posé dans les **douze** fichiers qui recopient
`est_compte_enseigne()`. Sabotés à onze, le dernier dans l'ordre
alphabétique remettait la bonne version et tout restait vert.

Dans « Confier à un livreur », celui de l'enseigne porte une pastille
**BIZZOO** : on lui remet le nom, le numéro et l'adresse d'un client, et
il n'est pas de la maison. Autant que ce soit lisible au moment
d'appuyer.

Un livreur créé **avant** ce chantier sans qu'on lui choisisse de
boutique se retrouvait avec une boutique vide par distraction, et plus
aucune liste ne le montrait. Ce compte-là devient maintenant un livreur
de BIZZOO, visible de toutes les boutiques. S'il y en a un dans ce cas,
sa fiche attend sa boutique.

### Il n'a qu'un écran

L'application admin, ouverte par un livreur, ne montre **que** « Mes
courses ». Les autres écrans le renvoient là, et la barre du bas
disparaît : la lui laisser reviendrait à lui offrir des boutons qui le
repoussent. Son compte reste accessible par l'en-tête — il doit pouvoir
changer son mot de passe.

Sur chaque course : le numéro de commande, ce qu'il porte, le nom du
client, son téléphone (appelable d'un doigt), l'adresse (qui ouvre la
carte) et le mot laissé à la commande. **Deux gestes seulement** : « Je
l'ai prise » et « Je l'ai remise ». Préparer reste à la boutique,
annuler aussi, et c'est toujours le client qui confirme avoir reçu.

### Il ne voit aucun montant

Ni le prix payé, ni le prix BIZZOO, ni la marge — pas même une devise à
l'écran. Ce n'est pas une politesse d'affichage : `mes_livraisons()`
**ne rend aucune colonne d'argent**.

C'est là qu'une distinction compte. Une règle RLS choisit les **lignes**
et les rend *entières* : elle ne sait pas retenir une colonne. Donner au
livreur une règle de lecture sur `commande_lignes` lui donnerait
`prix_bizzoo` avec le reste. Seule une **fonction** peut choisir les
colonnes — c'est pourquoi le livreur passe par `mes_livraisons()` et n'a
aucun droit sur la table.

### Ce que ce rôle a obligé à corriger

`est_equipe()` disait « un rôle, n'importe lequel ». Elle ouvre neuf
écrans, du catalogue aux statistiques : **le premier livreur créé serait
entré partout.** Elle nomme désormais les trois rôles de la boutique.

Et `peut_modifier_produits()` lisait la colonne du même nom, qui vaut
**vrai par défaut** sur tout profil : un livreur fraîchement créé aurait
pu modifier le catalogue, la colonne lui aurait dit oui. Elle commence
maintenant par `est_equipe()`.

Ce sont les deux corrections que le chantier a rendues nécessaires, et
elles valent bien au-delà du livreur : tout rôle ajouté plus tard entre
par ces deux portes.

### Confier une course

Sur une commande payée dont une ligne est `preparee`, la boutique voit
« Confier à un livreur » et choisit dans la liste de **ses** livreurs et
de **ceux de BIZZOO**. `assigner_livreur()` vérifie trois choses avant
d'écrire : que celui qui confie tient la boutique, que celui à qui l'on
confie est bien un livreur **de cette boutique ou de l'enseigne**, et
qu'il y a bien quelque chose à confier.

Le porteur de la boutique **d'à côté** reste refusé, et ce refus est
éprouvé à part : c'est la moitié de la règle qu'on aurait pu emporter en
ouvrant l'autre. Lui confier une course, ce serait lui remettre le nom,
le numéro et l'adresse d'un client qui n'est pas le sien.

`livreur_id` ne s'écrit pas à la main : `lignes_verrous` lève sur tout
changement de cette colonne hors du drapeau que seule
`assigner_livreur()` pose. Sans cela, n'importe quelle écriture sur la
ligne pourrait se désigner porteuse de la marchandise — et recevoir du
même coup le nom, le téléphone et l'adresse du client, fût-il d'une
autre boutique.

### Trois piles, et non deux

L'écran des commandes rangeait tout en deux tas : « à préparer » d'un
côté, « déjà remises » de l'autre. Une commande préparée — et *a
fortiori* partie avec le livreur — tombait donc sous un titre qui
annonçait le travail fini, sur l'écran même où la boutique doit la
retrouver pour la confier, et qu'elle regarde quand le client demande
où elle en est. Un troisième tas s'intercale : **« À livrer »**, ce qui
est prêt et ce qui est en route. Seul ce qui est remis reste sous
« Déjà remises ».

Ce défaut-là ne s'est pas vu dans un constat, mais sur une **capture
d'écran** : les treize constats de ce banc étaient verts, et le titre
au-dessus de la commande disait le contraire de son état.

[`tests/99g-livreur.sql`](supabase/tests/99g-livreur.sql) force les
portes en 46 constats. Quatre sabotages les font tomber : rendre à
`est_equipe()` son ancienne définition, ouvrir `mes_livraisons()` à
toutes les courses, retirer le contrôle « livreur de ma boutique » de
`assigner_livreur()`, et retirer le `revoke update` des trois fichiers
qui le posent.

[`tests/99n-livreur-bizzoo.sql`](supabase/tests/99n-livreur-bizzoo.sql)
ajoute 30 constats pour le porteur de l'enseigne, et trois sabotages les
font tomber : retirer `p.boutique_id is null` de la liste des livreurs,
le retirer de `assigner_livreur()`, et faire entrer le rang `livreur`
dans `est_compte_enseigne()`.

[`tools/banc-livreur-bizzoo.mjs`](tools/banc-livreur-bizzoo.mjs) éprouve
l'écran en 21 constats — mais sur **ce qui part vers la base**, pas sur
ce que le formulaire montre. Un champ peut être à l'écran et n'aller
nulle part : c'est exactement la panne qu'il répare, et un banc qui
regarde le formulaire ne l'aurait pas vue.

## Ce que le client garde pour lui

Les **favoris**, les **boutiques suivies** et les **adresses de
livraison**. Trois listes qui n'appartiennent qu'au client.

**Ce n'est pas de la donnée de vente, c'est de la donnée de vie.** Une
liste de favoris dit ce qu'on hésite à s'offrir ; une liste d'adresses
dit où l'on dort et où l'on travaille. L'enseigne n'en a aucun besoin
pour faire son métier, et **`est_super()` n'ouvre aucune de ces trois
portes** — contrairement à presque toutes les autres tables du projet.
Un superadministrateur curieux ne lit pas les favoris de ses clients.
C'est un choix, pas un oubli, et le banc le vérifie : si ce constat
tombe un jour, c'est qu'on a ouvert cette porte.

**Un favori se range en base, pas dans le téléphone.** C'est tout
l'intérêt : changer d'appareil ne doit rien faire perdre. Il faut donc
un compte, et le cœur d'un visiteur mène à la connexion plutôt que de
faire semblant d'enregistrer.

**Le cœur répond avant la base.** Un aller-retour réseau prend parfois
deux secondes ici ; un bouton qui attend deux secondes passe pour
cassé, et le client appuie une seconde fois. On peint donc tout de
suite, et on remet l'écran dans l'état vrai si la base refuse.

**Une seule adresse par défaut**, garantie par un index unique partiel
et non par l'application. Un déclencheur décoche l'ancienne, pour que
cocher une case ne renvoie pas une erreur de base de données au
client : le déclencheur pour que ce soit utilisable, l'index pour que
ce soit vrai.

### L'accueil : l'offre du jour, et ce qui se vend

**Le bandeau « Jusqu'à −X % » calcule son chiffre** sur les remises
réellement en cours. Écrire « −40 % » en dur serait plus simple et
plus faux : le jour où la dernière promotion se termine, l'accueil
continuerait de la promettre, et le client qui s'est déplacé ne la
trouverait nulle part. Quand plus rien n'est remisé, le bandeau
disparaît.

### L'en-tête d'une boutique

**Le nom sur une ligne, le slogan dessous, le logo à gauche.** Sur un
téléphone de 390 px, une ligne unique portait le retour, le logo,
quatre boutons et leurs écarts : il restait **cent vingt pixels** pour
le nom. « IMPACT INFORMATIQUE » s'affichait « IMP… », et le slogan se
pliait sur quatre lignes en dessous.

Les boutons montent donc sur la ligne du retour, et l'enseigne prend
toute la largeur suivante. Le nom dispose de **309 px** au lieu de 120,
le slogan tient sur une ligne quelle que soit sa longueur — une
description de boutique peut faire deux cents caractères —, et
l'en-tête finit **plus court** qu'avant : 117 px contre 153.

```bash
PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-entete.mjs
```

Vingt-trois constats, sur le nom et le slogan réels d'une boutique du
gérant. Rendre au slogan le droit de se replier fait tomber deux
constats et reproduit la capture d'origine à l'identique : trois
lignes, 153 px.

### La publicité s'enchaîne

Une vidéo finit, la rangée avance jusqu'à la suivante et la lance —
comme un slider. Avec une différence qui compte : **rien ne démarre
tout seul**. La chaîne ne part que d'un geste, et s'arrête au bout de
la rangée sans boucler.

Trois garde-fous, chacun contre une façon précise de vider le forfait
d'un client :

- **une seule vidéo à la fois** — deux qui jouent ensemble, c'est le
  double du débit et un téléphone qui chauffe. La règle vaut aussi
  quand c'est le client qui appuie sur lecture, pas seulement quand la
  chaîne enchaîne ;
- **on ne joue pas ce qu'on ne regarde pas** — si la rangée est sortie
  de l'écran, la chaîne s'arrête là ;
- **la carte suivante n'est pas toujours une vidéo** — sur une affiche
  on s'arrête : une image n'a pas de fin, et continuer sans elle
  reviendrait à la sauter.

Le défilement porte sur la **rangée**, jamais sur la page :
`scrollIntoView` ferait sauter tout l'accueil pour montrer une
publicité.

**Quelle taille pour une vidéo de publicité.** Le cadre fait 272 × 170
px, en **16:10**, et ce qui dépasse est coupé au centre. Visez
**1280 × 800**, 10 à 20 secondes, **3 à 6 Mo**, en MP4 *faststart*
(l'entête au début du fichier — sans lui, la lecture ne commence
qu'une fois tout téléchargé). Une vidéo filmée en 16:9 perd environ
10 % à gauche et à droite : gardez l'essentiel dans les 80 % centraux.
Au-delà de **8 Mo**, l'app admin prévient — sans refuser — que chaque
client paiera ce téléchargement sur son forfait. Le refus, lui, reste
à 40 Mo.

#### Le banc de la publicité

```bash
PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-publicite.mjs
```

Quinze constats, sur de **vraies vidéos** : c'est l'événement `ended`
d'un `<video>` qui déclenche tout, et une doublure de lecteur ne
prouverait rien. Trois sabotages les font tomber — retirer la mise en
pause des autres, faire boucler la chaîne, passer à `scrollIntoView`.

> **Deux pièges rencontrés en écrivant ce banc**, et qui resserviront.
>
> Un Chromium bâti à partir des sources **n'embarque pas H.264** : le
> MP4 s'y refuse avec « l'élément n'a aucune source ». Le banc éprouve
> donc en WebM — ce qu'il mesure ne dépend pas du format. Sur un
> téléphone Android, le MP4 du gérant se lit sans difficulté.
>
> Et le constat « la page n'a pas sauté » **restait vert avec le
> sabotage**, parce que la fenêtre d'essai faisait 1 800 px de haut :
> la page ne pouvait pas défiler. Il fallait une fenêtre de 640 px, et
> la rangée amenée **en bas** de l'écran — `scrollIntoView` veut poser
> la carte en haut, et vue en haut elle y est déjà.

**Le classement des ventes rend un ordre, jamais des chiffres.**
`produits_populaires()` lit les lignes de commande, que personne ne
peut lire — d'où le `security definer`. Ce qu'elle rend tient en une
colonne : l'identifiant du produit. Ajouter « quantité » au retour
paraîtrait anodin et livrerait à chaque commerçant le carnet de
commandes de son voisin, ouvrable avec un compte gratuit. Le banc
compare la signature de sortie mot pour mot.

La rangée arrive **après** le reste de l'accueil : elle demande un
aller-retour, et l'accueil ne doit pas attendre après elle. Sur une
base qui n'a pas encore reçu
[`favoris-adresses.sql`](supabase/favoris-adresses.sql), la fonction
n'existe pas, la rangée s'abstient, et tout le reste tient debout.

### Le banc

[`tests/99i-favoris-adresses.sql`](supabase/tests/99i-favoris-adresses.sql)
force les portes en 28 constats, et 50 de plus au navigateur. Cinq
sabotages les font tomber, chacun sur son propre constat : retirer le
`with check` d'une règle, ouvrir une table à `est_super()`, oublier
`anon` dans le `revoke`, ajouter les quantités au classement,
supprimer la garantie de l'adresse par défaut.

> **Deux fautes que ce chantier a values au banc lui-même.**
>
> Trois constats passaient au vert sur une **faute de frappe** : la
> requête de sabotage perdait les guillemets autour d'un identifiant,
> et la base répondait « la colonne cc111111 n'existe pas ». Un refus
> de syntaxe ressemble à un refus de sécurité dans un journal —
> `quote_literal()` a réglé cela, et il faut lire les motifs de refus,
> pas seulement compter les lignes vertes.
>
> Et un contrôle cherchait les colonnes d'une fonction dans
> `information_schema.columns`, où une fonction n'apparaît pas : il
> trouvait **zéro colonne** et concluait que tout allait bien. Il
> aurait trouvé zéro le jour où l'on aurait ajouté les quantités.

## La liste des catégories

Jusqu'ici, chaque boutique inventait ses rayons. Sur une vitrine unique
c'était sans conséquence ; sur une **place de marché**, cela donne à
l'acheteur autant de classements qu'il y a de commerces —
« Ordinateurs » chez l'un ne rejoint jamais « Ordinateurs » chez
l'autre, et aucune liste ne peut plus les réunir.

La liste est désormais celle de **BIZZOO** : quinze secteurs,
soixante-quatorze rayons, écrits par le **superadministrateur seul**.

```
Catégorie de BIZZOO            ← l'enseigne l'écrit
   └── Rayon (sous-catégorie)  ← l'enseigne l'écrit
          └── Produit          ← la boutique le range là
```

Une boutique **choisit son secteur** dans cette liste, et ses produits
ne se rangent que dans les rayons de celui-là : une boutique de
cosmétiques qui publierait sous « Pièces détachées » rendrait le
classement inutilisable pour l'acheteur, et c'est exactement ce que la
liste commune sert à empêcher.

### Le rayon commande, la catégorie suit

La boutique choisit une **sous-catégorie** ; `categorie_id` s'en déduit,
et le déclencheur `produit_code` l'écrit. Ce que l'application envoie
dans `categorie_id` **n'est jamais écouté** : deux colonnes qu'on
laisserait se contredire, c'est un classement qui ment — le produit
serait dans un rayon à l'écran et dans un autre dans les comptes.

Aucune des deux n'est obligatoire en base. Un produit peut rester **à
classer** : en vente, dans sa boutique et dans la recherche, mais sous
aucune catégorie. C'est l'état où la reprise laisse tout le catalogue,
et l'écran des produits le compte en haut de la liste. L'application,
elle, **refuse d'en créer de nouveaux** sans rayon — rien ne justifie de
publier un article que personne ne trouvera.

### Changer de secteur déclasse le catalogue

Les produits sont rangés dans des rayons de l'ancien secteur, que le
nouveau n'a pas. La base **refuse l'écriture directe**, même à
l'enseigne : ce n'est pas une question de rang mais de cohérence.
`changer_secteur()` fait les deux gestes dans l'ordre — déclasser, puis
changer — et rend le nombre de produits déclassés ; l'application le
demande **avant** d'ouvrir la confirmation, pour que l'enseigne sache ce
qu'elle s'apprête à défaire.

### Ce que voit l'acheteur

L'écran **Catégories** est le menu de BIZZOO : pastille ronde de la
couleur du secteur, nom, chevron, et un champ de recherche en tête qui
regarde **aussi les rayons** — on cherche « pneus » sans savoir que cela
vit sous « Auto & Moto ».

Ouvrir une catégorie montre ses **rayons tels que les boutiques les
tiennent**, et rien d'autre : un rayon que personne ne tient n'y figure
pas, parce que c'est une porte qui ne mène nulle part. Une **catégorie**
vide, elle, reste au menu — un menu annonce aussi ce qu'on peut venir y
chercher.

Sur l'accueil, l'enseigne en met quelques-unes en avant ; les autres
attendent derrière « Voir toutes les catégories ». Quinze lignes sur un
premier écran, c'est n'en montrer aucune.

**Un défaut que le banc a laissé passer, et pourquoi.** Enregistrer un
produit était devenu impossible : une règle restée à l'ancien modèle
réclamait toujours une catégorie, que le formulaire n'envoie plus. Le
banc du navigateur regardait les **champs** du formulaire — le secteur
affiché, les rayons proposés, le bon présélectionné — sans jamais
**appuyer sur Enregistrer**. Tous ses constats étaient verts, et
l'écran refusait la moindre modification.

Un banc d'écran doit aller jusqu'à l'envoi : il vérifie maintenant ce
qui **part vers la base** — le rayon choisi, et pas de catégorie,
puisque c'est la base qui la déduit. Remettre le défaut en place fait
tomber quatre constats.

**Un défaut que seule la capture d'écran a montré.** L'onglet
« Catégories » restait caché tant qu'on n'était pas entré dans une
boutique — à bon droit, du temps où il aurait mélangé les classements de
tous les commerces. Depuis que la liste est celle de l'enseigne, c'est
la porte d'entrée de la place de marché, et la cacher revenait à la
retirer. Les constats du banc étaient tous verts ; la barre du bas ne
proposait pas l'écran.

En le corrigeant, deux restes du modèle d'avant sont tombés : ouvrir un
rayon faisait **entrer dans une boutique** (une catégorie n'appartient
plus à personne), et « Promotions » entrait d'autorité dans la
**première** boutique — alors que la rubrique des bonnes affaires est
celle de BIZZOO et doit les réunir toutes. Ce second retrait a découvert
une fuite qu'il masquait : hors d'une boutique, les articles d'une
boutique **fermée** remontaient. `Catalogue.produits()` les écarte
maintenant, comme le faisait déjà `produitsDeLEnseigne()`.

[`tests/99h-categories.sql`](supabase/tests/99h-categories.sql) force
les portes en 38 constats, et 58 de plus au navigateur. Quatre sabotages
les font tomber : rendre la liste à l'équipe, retirer le contrôle du
secteur, laisser passer la catégorie soufflée par l'application,
permettre le changement de secteur à la main.

## La photo d'une catégorie

Sur la DA, les ronds des catégories de l'accueil portent une **photo**.
Chaque catégorie en reçoit maintenant une, **facultative**, que le
superadministrateur pose dans l'application admin :
**Catégories → Modifier → Photo du rond (facultative)**. La même photo
remplit la pastille de l'écran « Catégories », chez le client, et celle
de la liste dans l'admin.

### Les illustrations de BIZZOO

Chaque catégorie de la liste porte d'office une **illustration** : un
objet en 3D sur le fond pastel de sa couleur, comme les ronds de la DA —
une robe pour la Mode, un ordinateur pour le High-Tech, une voiture pour
l'Auto & Moto, une maison, un rouge à lèvres, une marmite, un chariot,
une boîte à outils pour les Services… Vingt-quatre en tout : une par
catégorie, et neuf autres au choix (une moto, un téléphone, une plante…).

Ce ne sont **pas des photos de vos produits**, et rien ne le prétend :
les images de la maquette elle-même font 29 px une fois découpées, trop
peu pour un rond de 62 px, et les banques de photos ne sont pas
joignables d'ici. Les objets sont les **Fluent Emoji 3D de Microsoft**,
sous licence MIT (libres, usage commercial compris) ; l'avis de licence
les accompagne (`img/categories/LICENCE.txt`), et
[`tools/illustrations-categories.py`](tools/illustrations-categories.py)
les recompose à l'identique.

Elles **voyagent avec l'application** — dans l'APK comme sur le site,
dans `client/img/categories/` et `admin/img/categories/` — et la base
les désigne par leur chemin (`img/categories/robe.jpg`). L'accueil les
montre donc **sans réseau**, dès la première ouverture : elles sont dans
la coquille hors connexion des deux applications, et le contrôle de la
coquille refuse une illustration oubliée.

La base en ligne les a reçues par
[`categories-photos.sql`](supabase/categories-photos.sql) — **une seule
fois** : tant qu'aucune catégorie n'a d'image. Recoller le fichier ne
remet jamais une illustration que l'enseigne a retirée ou remplacée.

### Poser, remplacer, retirer

- **Choisir une illustration** : dans la fiche, sous « Photo du rond »,
  la galerie les montre toutes, rondes ; un appui suffit. Celle en place
  est cerclée de bleu. Rien ne part au stockage : elle est déjà dans
  l'application.
- **Mettre une vraie photo** : le carré « Ajouter » de la fiche. L'aperçu
  est **rond**, comme chez le client : on voit tout de suite ce que les
  coins perdront. Une photo carrée, le sujet au centre, convient le mieux.
- **Remplacer** : la croix, puis « Ajouter » ou une illustration.
- **Retirer** : la croix, puis « Enregistrer ». Le rond retrouve son
  icône.

Quand une image est posée, la pastille de l'écran « Catégories » passe au
**pastel**, comme le rond de l'accueil : sous l'image, l'aplat foncé
d'avant débordait d'un fin liseré au bord du cercle.

L'application **réduit la photo à 480 px** et l'enregistre en JPEG avant
de l'envoyer — une photo de téléphone de plusieurs Mo n'en garde que
quelques dizaines de Ko : le plus grand rond n'a pas besoin de plus, même
sur l'écran le plus fin.

### L'icône en secours

La photo se pose **par-dessus l'icône**, qui reste dessous. Tant qu'elle
charge, on voit l'icône ; si elle ne vient pas — hors connexion, sur un
téléphone qui ne l'a jamais vue, ou fichier retiré du stockage —, elle
**s'efface** et l'icône reste. Jamais un carré d'image cassée à l'accueil.
Une seule écoute par application, posée une fois pour tous les écrans
(`data-secours`), sans attribut `onerror` dans le HTML.

### Ce que la base garde

- **Un chemin, jamais une adresse**, dans l'un de deux dossiers :
  `enseigne/categories/` (une photo, dans le seau) ou `img/categories/`
  (une illustration, dans l'application). La règle
  `categories_image_chemin` refuse tout le reste — une adresse internet,
  un autre dossier, un `..`, un fichier caché — même au
  superadministrateur : ce n'est pas une question de droit, c'est la
  forme de la donnée. Une adresse libre ferait charger à l'accueil de
  tous les clients une image posée n'importe où.
- **L'enseigne seule la pose**, comme elle seule écrit la liste ; le
  stockage réserve déjà `enseigne/` au superadministrateur. Aucune règle
  de stockage n'a changé.
- **Le fichier part avant la ligne** : la ligne ne désigne jamais une
  photo qui n'existe pas. Un envoi refusé n'écrit rien, et la fiche reste
  ouverte. Un double appui sur « Enregistrer » n'envoie qu'une photo.
- **Un nouveau nom à chaque photo.** Les téléphones gardent les photos en
  cache ; réutiliser un nom leur ferait montrer l'ancienne indéfiniment.
- **L'ancienne photo reste au stockage.** Annuler depuis le journal
  remet l'ancien chemin, et le fichier doit encore y être. Plus rien ne
  la désignant, [`etat-du-stockage.sql`](supabase/etat-du-stockage.sql)
  la liste parmi les **orphelins**, et `menage-stockage.ps1` l'enlèvera
  au prochain ménage — alors que la photo **en place**, elle, figure
  dans la liste des fichiers utilisés et n'est jamais proposée à la
  suppression.

À coller dans Supabase : [`categories-photos.sql`](supabase/categories-photos.sql)
(déjà appliqué sur la base en ligne, illustrations comprises).

### Le banc

[`tests/99o-categories-photos.sql`](supabase/tests/99o-categories-photos.sql)
force les portes en 34 constats — dont l'état des lieux du stockage
**tel qu'il part chez le gérant**, lu dans le dépôt : c'est sa liste
d'orphelins qu'on éprouve, pas une copie. Il lit aussi les deux dossiers
d'illustrations sur le disque : chacune de celles que la base désigne
doit y être, dans le client **et** dans l'admin. Et il recolle
`categories-photos.sql` pour prouver qu'un choix de l'enseigne survit.
[`tools/banc-categories-photos.mjs`](tools/banc-categories-photos.mjs) en
ajoute 101 au navigateur, dans les deux applications : la photo remplit
le rond et se trouve par-dessus l'icône (mesuré), l'icône revient quand
la photo manque, rien ne déborde à 320 px, le chemin est échappé ; la
liste que `schema.sql` sème montre ses quinze illustrations, lues à côté
de la page et jamais dans le seau ; dans l'admin, la galerie, et ce qui
part au stockage et vers la base, corps compris.

Dix-neuf sabotages, un par un, et chacun fait tomber au moins un
constat. En base : retirer la règle du premier caractère (« .. » passe),
oublier la photo dans l'état des lieux du stockage (elle devient
« supprimable »). Au navigateur : ne plus effacer une image cassée — chez
le client comme dans l'admin —, ne plus découper le rond, poser la photo
sous l'icône ou à côté, ne plus échapper le chemin, oublier l'écran
« Catégories », déposer hors de `enseigne/categories/`, écrire la ligne
avant la fin de l'envoi, effacer l'ancienne photo, retirer le verrou du
bouton, écrire la colonne inchangée, envoyer la photo sans la réduire,
continuer après un envoi refusé, ne plus montrer la photo dans la liste
de l'admin, taire la photo au journal. Le dix-neuvième — ne plus découper
la pastille de l'admin — fait plus qu'échouer : la photo, libérée, recouvre
toute la carte et **bloque le bouton « Modifier »**. La découpe évite
aussi cela.

Onze de plus pour les illustrations. En base : laisser passer un fichier
caché, reposer les illustrations à chaque relecture du fichier (celle que
l'enseigne a retirée revient), retirer une illustration de l'admin. Au
navigateur : chercher les illustrations dans le seau — chez le client
comme dans l'admin —, oublier le dossier dans la galerie, ne plus y
allumer le choix, remettre l'aplat foncé sous l'image — des deux côtés —,
retirer une illustration de l'admin. Et à la coquille hors connexion,
en oublier une dans la liste.

```bash
PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-categories-photos.mjs
```

## « Marquer vue » refusé : le retour, pas l'écriture

**Le défaut.** La boutique appuyait sur « Marquer vue » et l'écran
répondait *« Écriture refusée par la base : votre compte n'a pas ce
droit »*. Le droit d'écrire était pourtant bien là.

**La cause, et elle n'est pas où on la cherche.** L'application ne
dit pas `update … set etat = 'vue'`. Elle passe par PostgREST avec
`Prefer: return=representation`, et PostgREST écrit alors :

```sql
update public.commande_lignes set etat = 'vue' where id = … RETURNING *
```

Ce `RETURNING *` réclame le droit de **lire chaque colonne** — dont
`prix_bizzoo` et `taux_marge`, fermées à l'équipe exprès. La base
refuse donc toute la requête. **C'est le retour qui faisait tomber
l'écriture.**

**Ce qu'on n'a PAS fait :** ouvrir la lecture de ces colonnes. Cela
aurait réparé le geste en livrant la marge de BIZZOO à toute l'équipe
— bien plus cher que le défaut. C'est l'application qui change : elle
demande `return=minimal` et ne réclame plus une ligne dont elle n'a
que faire. Le nouvel état, elle vient de le donner.

On préfère `return=minimal` à la liste des colonnes permises : une
colonne fermée ajoutée demain casserait de nouveau.

### Les deux bancs

[`tests/99j-marquer-vue.sql`](supabase/tests/99j-marquer-vue.sql)
rejoue la requête de PostgREST, `RETURNING *` compris — un essai qui
écrirait `update … set etat = 'vue'` tout court serait passé au vert
sur une base où l'application échoue. **Un de ses constats vérifie
qu'un refus a bien lieu** : si `RETURNING *` cesse un jour d'être
refusé, c'est que quelqu'un a ouvert le prix BIZZOO à l'équipe.

```bash
PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-marquer-vue.mjs
```

Neuf constats côté écran, sur l'**en-tête** que l'application envoie —
regarder « l'état a changé à l'écran » n'aurait rien prouvé, puisque
l'écran se repeint avant la réponse de la base. La doublure répond 403
à `return=representation`, exactement comme la vraie base. Retirer le
correctif fait tomber trois constats et réaffiche le message d'origine.

## Où en est ma commande : la barre, et l'accusé de réception

Une commande payée restait « Payée » jusqu'au bout. Partie, livrée :
toujours « Payée ». Le suivi existait pourtant déjà en base — cinq
états par boutique, de `nouvelle` à `remise`, plus la confirmation du
client — mais **il ne se lisait qu'en ouvrant le reçu**. Dans la
liste, rien.

### Côté client : quatre paliers sous la commande

Chaque commande payée porte maintenant une barre à quatre segments,
avec son mot sous chacun :

```
Payé ──── Préparé ──── En route ──── Livré
```

Deux mots par palier, et c'est voulu : la pastille dit l'étape en
entier — « Livraison en cours » —, la barre la dit court — « En
route ». Quatre étiquettes entières sur la largeur d'un téléphone
déborderaient, et « Livraison en cours » serait le premier à sauter.

**Rien avant le paiement.** Une commande en attente n'affiche pas de
barre vide : elle se lirait comme une panne. C'est la pastille du
paiement qui parle, comme avant.

**Elle parle aussi à qui ne la voit pas.** Une barre est une image :
seule, elle ne dit rien à un lecteur d'écran. Elle s'annonce donc en
toutes lettres — *« Livraison en cours — étape 3 sur 4 »*.

### La règle qui compte : le palier le MOINS avancé

Une commande traverse parfois deux boutiques. Si l'une roule déjà et
l'autre prépare encore, le client lit **« Préparé »**. Annoncer
l'étape la plus avancée mentirait sur ce qu'il attend : son colis
n'est pas en route, la moitié l'est. La même règle vaut des deux
côtés — `Compte.statutLivraison` chez le client,
`Store.statutCommande` côté boutique — et c'est le genre de règle
qu'on écrit deux fois et qu'on désaccorde une fois sur deux, d'où le
constat qui l'éprouve sur chacune.

« Reçu confirmé » fait exception : il ne paraît que lorsque **toutes**
les boutiques ont été confirmées.

### « J'ai bien reçu », sans ouvrir la commande

Au palier « Livré », un bouton paraît sous la barre. Il confirme d'un
geste toutes les boutiques de la commande qui ont remis et attendent
encore — c'est bien ce que le client veut dire : *j'ai tout reçu*.
Quand il y en a deux, le bouton l'annonce : « J'ai bien reçu
(2 boutiques) ». Une confirmation part alors par boutique, car c'est
par boutique que la base signe, et la boutique la retrouve sur sa
ligne : « Reçu confirmé, le … ».

Le bouton **ne paraît qu'à « Livré »** et disparaît dès la
confirmation faite. Offert plus tôt, il ferait accuser réception d'un
colis qu'on n'a pas.

**La carte est un lien, et le bouton vit dedans.** Sans
`preventDefault`, le doigt ouvrirait la commande au lieu de
confirmer, et le geste se perdrait en route — la même leçon que le
cœur des favoris. Le banc ne s'en remet donc pas à ce qui est parti :
il regarde **l'adresse de la page après le clic**.

Ce qui s'affiche ensuite vient de la base : la liste est relue, pas
cochée à l'écran.

### Le banc

```bash
PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-suivi.mjs
```

Trente-six constats, sur ce qui **quitte** l'application — les appels
à la base, leur nombre et leurs arguments — et non sur ce que l'écran
affiche : l'écran se repeint avant la réponse, et se repeindrait de la
même façon si rien n'était parti.

Trois sabotages ont vérifié que ces constats mordent, chacun sur le
sien :

| ce qu'on casse | ce qui tombe |
| --- | --- |
| `preventDefault` retiré | *la commande ne s'est PAS ouverte sous le doigt* |
| le drapeau « confirmé » ignoré | *ni celle que le client a déjà confirmée* + *le bouton disparaît* |
| le bouton ne regarde plus l'état `remise` | *aucune de celles qui ne sont pas encore livrées* |

Un quatrième sabotage — annoncer le palier le **plus** avancé au lieu
du moins avancé — fait tomber les deux constats de la règle des deux
boutiques.

## L'écran Commandes de l'admin : serré, et rien de perdu

**Ce qui n'allait pas.** Une commande de trois articles prenait tout un
écran de téléphone (685 px). L'état d'un article et son bouton se
tenaient **à côté** du nom et lui prenaient la moitié de la largeur :
« Chargeur rapide USB-C 25 W Samsung d'origine » se cassait mot par mot
sur sept lignes. Les montants se coupaient en « 142 000 » / « FCFA ».
Chaque carte portait un bandeau vert « Payée — confirmée par KkiaPay »
et deux grands boutons de 50 px. Et « KkiaPay » était **faux** : le
paiement actif est FeexPay.

**Ce qui a changé** (`admin/js/vues/commandes.js`, `admin/styles.css`) :

- **un article, deux rangées** : la première au produit — quantité,
  nom, montant —, la seconde au travail — code, référence, état, geste
  suivant. Le nom tient sur **une ligne** ; tronqué, il se déplie d'un
  appui (c'est un bouton, et son nom entier est aussi en titre) ;
- **l'en-tête en deux colonnes** : le numéro, le statut et l'heure à
  gauche ; le montant en face, qui ne se coupe plus ;
- **le paiement sur la ligne de l'heure** : « il y a 12 min · payée par
  FeexPay ». Seul ce qui demande de l'attention garde un bandeau :
  l'attente, l'échec, une remarque ;
- **l'agrégateur est le bon** : une commande qui porte une référence
  FeexPay (`fournisseur_ref`) dit « FeexPay », les autres « KkiaPay »,
  et une confirmation à la main dit par qui ;
- **WhatsApp à côté du numéro** : les deux façons de joindre le client
  sur la même ligne, le message toujours rédigé. Le grand bouton « Écrire
  au client » a disparu du bas de la carte ;
- « **Confier à un livreur** » en bouton compact (40 px), seulement
  quand quelque chose est prêt à partir ; « Revendeur » sur la ligne de
  l'heure ; des dates courtes (« 20 sept. à 21:31 ») ;
- des **libellés à leur taille** : numéro 14 px, montant 15,5 px, nom
  d'article 13 px, badges 10,5 px ;
- **à l'ordinateur**, le client à gauche et les articles à droite.

| | Avant | Après |
|---|---|---|
| Trois articles, téléphone | 685 px | 408 px |
| Un article, téléphone | 470 à 560 px | 280 à 300 px |
| Trois articles, ordinateur | 582 px | 266 px |

> **Le piège de la grille.** Un nom qui ne passe plus à la ligne élargit
> sa colonne de grille jusqu'à sa longueur entière — et toute la page
> déborde à 671 px sur un téléphone de 390. D'où `minmax(0, 1fr)` et
> `min-width: 0` : il en faut au moins un des deux.

### Le banc

```bash
PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-commandes-admin.mjs
```

Quarante constats, de 320 à 1280 px : rien ne déborde, un nom par
ligne qui se déplie et se replie, aucun montant coupé (au plus serré :
320 px), des hauteurs bornées, les tailles des libellés, le bon
agrégateur, et **rien de perdu** — numéro, statut, montant, nom, appel,
WhatsApp et son récapitulatif, adresse, note, code, référence, état,
geste suivant, quantités, « Confier » au bon moment, « Revendeur », la
part d'une commande partagée, la réception confirmée par le client.

Onze sabotages le font tomber : le nom qui repasse à la ligne, la grille
sans ses deux protections, « KkiaPay » pour tout le monde, le bouton en
pleine largeur, le montant à 18 px, le montant sans ses deux protections,
WhatsApp retiré, le bandeau « Payée » revenu, le dépliage retiré, la
date longue revenue, « Confier » offert trop tôt.

## L'accueil de BIZZOO : le slogan, les boutiques, le site

### Le slogan sous le logo — celui de BIZZOO, pas celui d'une boutique

Sur l'accueil de l'enseigne, le slogan s'écrit maintenant **sous le
mot-symbole**, en petit et calé à gauche.

Il vient de `Catalogue.enseigne()`, et **jamais** de
`Catalogue.boutique()`. Cette dernière vide le slogan exprès quand
aucune boutique n'est choisie — *« le slogan de l'une d'elles
tromperait sur les autres »* —, ce qui est la bonne règle et qu'on
n'a pas défaite. L'enseigne, elle, a le droit de parler en son nom :
d'où l'accès séparé, qui ne laisse aucun doute sur qui parle.

**Il ne s'affiche jamais deux fois.** En mode mono-boutique — la
table `boutiques` vide, l'ancienne ligne unique fait les deux — le
bandeau orange porte déjà ce texte. Le slogan sous le logo n'apparaît
donc que lorsque ce bandeau se tait.

**Combien de place ?** Entre le bord de l'écran et les quatre boutons
de la barre, il reste **176 px sur un téléphone de 390 px** et
seulement **106 px sur un de 320 px**. Le slogan s'y écrit sur
**deux lignes au plus**, puis s'arrête — au-delà, la barre du haut
grandirait et tout ce qui se fige dessous descendrait avec elle.
Mesuré :

| slogan | 320 px | 390 px |
| --- | --- | --- |
| « Toutes vos boutiques » (20 car.) | tient | tient |
| « Nous sommes imbattables en prix » (31 car.) | coupé | tient |
| 56 caractères | coupé | tient |

En clair : **jusqu'à 55 caractères sur un téléphone courant, une
vingtaine sur les plus petits.**

### Les boutiques par trois

> **Depuis la 3.50.0, elles vont par quatre** (section « L'accueil
> réordonné et la galerie « Nos produits » »). Ce qui suit reste la
> leçon de ce passage, et vaut toujours : `min-width:0`, la largeur de
> la page mesurée, deux lignes réservées au nom.

`.bou-grille` passe de deux à trois colonnes, et l'icône de 64 à
48 px. C'est le plus petit téléphone qui commande : à 320 px la
colonne fait 288, et trois cartes avec deux écarts de 8 px n'en
laissent que **90,7 px** chacune — 74,7 une fois les marges
intérieures retirées. Le rond de 64 px y touchait les deux bords.

L'écart de 8 px est celui des catégories : deux grilles sur le même
écran ne peuvent pas respirer différemment.

**Le piège, et il coûte cher.** Une case de grille vaut
`min-width:auto` par défaut. Un nom d'un seul long mot —
INFORMATIQUE — **élargit sa colonne** au lieu d'être coupé : les
trois cartes passaient de 91 à 143 px et la page se mettait à défiler
de côté. D'où `min-width:0` sur `.bou-carte`, et
`overflow-wrap:anywhere` sur le nom. Le banc mesure donc la
**largeur de la page**, pas seulement le nombre de cartes par
rangée : compter trois cartes serait resté vert pendant que la page
débordait.

Les noms réservent deux lignes d'avance (`min-height:2.5em`), sans
quoi une boutique au nom court fait une carte plus basse que sa
voisine — c'est la leçon des catégories.

### Le site web

Une colonne `site_web` arrive sur l'enseigne **et** sur chaque
boutique : [`supabase/site-web.sql`](supabase/site-web.sql), à coller
dans **SQL Editor → New query → Run**. Elle n'ajoute que deux
colonnes vides et se recolle sans conséquence.

Le champ est dans **Réglages**, sous les horaires. On y tape
l'adresse comme on la dit — `bizzoo.bj` — et l'application en fait
`https://bizzoo.bj`. Un **aperçu sous le champ** montre l'adresse
exacte qui s'ouvrira, avant d'enregistrer.

**Ce qui n'est pas une adresse ne devient pas un lien.** Sans ce
contrôle, « mon site » donnerait `https://mon site` : un lien mort
posé chez tous les clients, et qui aurait l'air d'un vrai. La règle
(`Utils.lienSite`) exige un point dans le nom d'hôte et rien qui
ressemble à une phrase ; sinon elle rend `""`, l'écran des réglages
le dit en rouge au gérant, et la ligne ne paraît pas chez le client.
**La même fonction existe des deux côtés, à l'identique** — sinon
l'aperçu mentirait sur ce qui s'ouvre vraiment.

Chez le client, la ligne « Site web » rejoint « Nous contacter »,
avec une icône de globe. Elle affiche l'adresse **sans** le
`https://` — plus lisible — mais le lien, lui, porte l'adresse
complète.

### Le banc

```bash
PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-accueil-enseigne.mjs
```

Trente-sept constats : des **mesures réelles** à l'écran, et le
**corps des requêtes** qui partent vers la base — le nom de colonne
compris, car la base attend `site_web` et non `siteWeb`.

Six sabotages ont vérifié qu'ils mordent, chacun sur les siens :

| ce qu'on casse | ce qui tombe |
| --- | --- |
| retour à deux colonnes | les 4 constats « trois par rangée » |
| `min-width:0` retiré de la carte | la page déborde à 320 px (335 px) |
| le logo reprend le slogan vidé de `boutique()` | 5 constats du slogan |
| le slogan s'écrit aussi quand le bandeau le porte | *il ne s'écrit pas deux fois* |
| `lienSite` ne vérifie plus l'adresse | les 2 constats du lien mort |
| les réglages envoient `siteWeb` | les 2 constats du nom de colonne |

### Deux défauts que ce chantier a fait tomber

**Le logo débordait la page.** `.logo` est un `inline-flex` : il se
dimensionne sur son contenu et sort de son parent sans rien demander.
Le `min-width:0` posé plus bas ne servait donc à rien, ni la coupure
du slogan — un slogan un peu long faisait défiler la page de côté.
Il a fallu `max-width:100%` sur `.logo` lui-même.

**Le banc de la publicité avait cessé d'éprouver quoi que ce soit.**
Son constat « la page n'a pas sauté » suppose que la publicité soit
**sous le pli**. Son décor n'avait qu'une catégorie et une boutique ;
la grille passée à trois colonnes a raccourci l'accueil, la page a
tenu dans la fenêtre, `scrollTo` n'a plus rien fait — et le constat
serait resté vert même avec le défaut qu'il surveille. Le décor porte
maintenant huit catégories et six boutiques, comme en service, et le
sabotage retombe (248 → 299 px).

C'est la troisième fois dans ce projet qu'un constat vert ne prouvait
rien. La parade est toujours la même : **vérifier que la condition de
départ tient** — ici, que la page a bien de quoi défiler — avant de
croire ce qui suit.

## Les comptes de BIZZOO

Un compte de l'équipe était forcément rattaché à **une** boutique, sauf
le superadministrateur qui a tout. Entre les deux, rien : personne ne
pouvait suivre les commandes de toutes les boutiques sans devenir
maître de l'enseigne entière.

Un rang intermédiaire existe maintenant : **administrateur ou
modérateur rattaché à AUCUNE boutique**. Dans Réglages → Comptes, le
menu « Boutique confiée » propose « BIZZOO — toutes les boutiques »,
réservé au superadministrateur.

Ses droits ne viennent pas de son rang mais de **quatre
interrupteurs** :

| interrupteur | ce qu'il ouvre | défaut |
| --- | --- | --- |
| Les commandes | toutes les boutiques | allumé |
| Le catalogue | produits et rayons de toutes | allumé |
| Les boutiques | régler une boutique | éteint |
| Les chiffres | journal et statistiques | éteint |

Le rang nomme la personne ; les interrupteurs disent ce qu'elle
touche. « Admin de BIZZOO » ne veut pas dire la même chose chez vous
que la semaine prochaine.

**Il ne crée aucun compte**, quel que soit son rang. Ce n'est pas une
politesse d'écran : les règles de `profils` exigent une boutique non
nulle, et il n'en a pas. L'écran ne lui propose donc pas un geste que
la base refuserait.

### Un interrupteur qui ne ferme qu'à l'écran n'est pas un droit

`peut_agir_sur()` répond **oui partout** à un compte d'enseigne. Les
règles des commandes vérifient donc **aussi** `peut_voir_commandes()`.
Sans cette seconde condition, éteindre l'interrupteur n'aurait rien
fermé du tout — le bouton aurait disparu de l'écran pendant que la
base continuait de tout rendre.

### Le piège qu'on a failli laisser

`schema.sql` contenait cette ligne, écrite pour rattraper les bases
d'avant :

```sql
update profils set role = 'superadministrateur'
 where role = 'administrateur' and boutique_id is null;
```

Elle décrit désormais **mot pour mot un administrateur de BIZZOO**. Un
simple rejeu du fichier lui aurait donné l'argent, les comptes et
l'enseigne entière, en silence. Elle ne s'exécute plus que si personne
ne tient encore l'enseigne.

**Et elle porte un nom.** Écrite en `do $$` anonyme, cette garde ne
s'éprouvait pas : le banc ne pouvait que recopier la même logique à
côté, et il éprouvait alors **sa copie**. Vérifié : le sabotage ne
tombait pas — le banc restait vert pendant que le vrai fichier
promouvait tout le monde. Nommée `rattraper_anciens_admins()`, elle
s'appelle, et le sabotage tombe.

[`tests/99k-comptes-enseigne.sql`](supabase/tests/99k-comptes-enseigne.sql) :
vingt-deux constats sur la **base** et non sur les boutons — zéro
ligne rendue, zéro ligne touchée, refus à l'insertion.

À coller : [`comptes-enseigne.sql`](supabase/comptes-enseigne.sql).

## Les notifications

Le mot n'existait nulle part dans ce projet. Une commande payée à
l'instant n'arrivait chez la boutique qu'en rouvrant l'écran des
commandes — et le client attendait pendant ce temps.

### Une ligne par personne prévenue

Et non une ligne par événement. C'est plus de lignes, mais c'est la
seule forme où « lue » veut dire quelque chose : une commande payée
prévient le client, l'équipe de chaque boutique concernée, les comptes
de BIZZOO et le superadministrateur — chacun la lit à son heure, et
l'un ne décoche rien pour les autres.

**Une fois, et une seule.** Une commande de trois articles chez la
même boutique fait trois lignes qui passent à « préparée » : un index
unique retient les doublons, sans quoi la boutique recevrait trois
fois la même nouvelle. Le `coalesce` de cet index n'est pas décoratif
— deux `NULL` sont **distincts** pour un index unique, et la
contrainte n'aurait rien retenu sur les notifications sans boutique.

### Qui reçoit quoi

| cran du circuit | qui est prévenu |
| --- | --- |
| payée | client · boutique · BIZZOO · **superadministrateur** |
| vue | **personne** |
| préparée | le client |
| confiée à un livreur | **le livreur** · BIZZOO |
| en livraison | client · boutique |
| remise | client (invité à confirmer) · boutique |
| réception confirmée | **la boutique** · BIZZOO |
| annulée | client · boutique · BIZZOO · superadministrateur |

**Le superadministrateur reçoit l'argent et les incidents**, pas les
crans intermédiaires. À dix boutiques et vingt commandes par jour,
être prévenu de chaque cran ferait plusieurs centaines de pastilles
quotidiennes : une pastille qui ne redescend jamais à zéro ne veut
plus rien dire.

**« Vue » ne prévient personne**, et c'est un choix : le client n'a
que faire de savoir qu'on a ouvert son écran.

### Personne n'écrit ici, pas même l'application

Aucune règle d'insertion n'existe, pour aucun rang. Les notifications
naissent des déclencheurs et d'eux seuls — un client ne peut pas
s'annoncer une commande livrée, ni une boutique se fabriquer un accusé
de réception. La seule écriture permise est `lue_le`, sur ses propres
lignes.

**Aucun montant n'y entre.** La règle des prix fermés au livreur ne
servirait à rien si le texte d'une notification les recopiait.

### La cloche, le panneau, les trois bips

Dans les deux applications : pastille avec le compte, **et le nombre
dans l'étiquette** — une pastille seule ne dit rien à un lecteur
d'écran. Le panneau groupe par famille, dans l'ordre de la
notification la plus récente et non alphabétique. Un doigt sur une
ligne la marque lue **et** mène à l'opération : la commande chez le
client, la commande **visée dans la liste** chez la boutique, les
livraisons chez le livreur.

Les trois bips se fabriquent avec le son du navigateur — rien à
charger, rien de plus dans la coquille hors connexion, pas de silence
le jour où un fichier manque. **Les navigateurs refusent le son avant
le premier geste** : ce n'est pas un réglage, c'est une règle du
navigateur, et l'écran le dit. On peut les couper, sur l'appareil.

**Le son suit les nouvelles, pas le compteur.** Sonner « quand le
nombre monte » aurait sonné au premier chargement, quand on retrouve
vingt notifications jamais lues — un carillon à l'ouverture.

### Ce que cette option ne fait pas

Les notifications arrivent quand l'application est **ouverte ou
revenue de l'arrière-plan**. Une application fermée ne reçoit rien :
tout se rattrape à la réouverture, rien ne se perd, mais l'écran
verrouillé reste muet. Prévenir un téléphone fermé demande un service
de push extérieur — c'est un chantier à part, qui dépend d'un compte
qui n'est pas le nôtre.

### Le temps réel passe par son propre socket

Celui de `live.js` se connecte avec la clé **publiable** : il écoute
des tables ouvertes à tous. Les notifications sont fermées à leur
destinataire, et le temps réel ne laisse passer une ligne que si le
**jeton du compte** le permet. Deux connexions, parce que ce ne sont
pas les mêmes droits. Avec les trois mêmes filets que le catalogue :
temps réel, retour au premier plan, vérification de fond.

L'application de la boutique n'en avait aucun — elle a maintenant le
même.

### Le circuit, vérifié d'un bout à l'autre

Chaque chantier a son banc, et chacun est vert. Mais **un circuit se
rompt ENTRE deux chantiers verts**, là où personne ne regarde.
[`tests/99m-circuit-complet.sql`](supabase/tests/99m-circuit-complet.sql)
parcourt **une seule** commande de l'achat à la confirmation et
vérifie à chaque cran deux choses ensemble : l'état a avancé, **et**
la notification est partie chez les bonnes personnes. Un cran muet,
c'est quelqu'un devant un écran qui ne bouge pas.

Sabotage vérifié : rendre le cran « préparée » muet fait tomber le
constat.

### Trois constats qui passaient pour la mauvaise raison

Ce chantier en a surtout appris cela, et c'est ce qu'il faut retenir.

**Le numéro n'est pas un montant.** « Aucun nombre à quatre chiffres
dans le texte » tombait sur le **numéro de la commande**, qui a
parfaitement sa place. Un constat qui se déclenche sur ce qu'on veut
garder ne défend rien, il gêne. On cherche maintenant le montant
exact, écrit comme l'application l'écrit.

**Le refus venait d'ailleurs.** « L'insertion est refusée » restait
**vert** après qu'on eut ouvert `insert` **et** posé une règle
permissive : c'est la séquence de la clé primaire qui refusait, pas
l'absence de règle. Le banc lit désormais le catalogue — aucune règle
INSERT, aucune règle DELETE, et seulement SELECT et UPDATE.

**Saboter un fichier sur deux ne prouve rien.** `notifications.sql`
rejoue les mêmes règles après `schema.sql` : saboter le premier seul
laissait tout vert. Les sabotages se posent dans les deux. L'aligneur
propage les **fonctions**, pas les règles — c'est à la main pour
celles-ci.

**Et une doublure qui oublie les écritures ne représente pas une
base**, elle représente une base en panne : « tout marquer lu »
partait bien, la relecture ramenait les mêmes non lues, la pastille
remontait. Le défaut n'existait que dans le banc.

### Les bancs

```bash
PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-notifications.mjs
PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-notifications-admin.mjs
```

Vingt-sept constats côté client, vingt et un côté boutique, sur ce qui
**quitte** l'application — corps des requêtes et en-têtes compris. Le
quatrième sabotage admin ne tombait pas : le banc n'éprouvait jamais
l'application **déconnectée**. Comblé.

### Les fichiers à coller, dans l'ordre

1. [`comptes-enseigne.sql`](supabase/comptes-enseigne.sql)
2. [`notifications.sql`](supabase/notifications.sql) — il s'appuie sur
   des colonnes que le premier pose
3. [`livreur-nom.sql`](supabase/livreur-nom.sql)
4. [`livreur-bizzoo.sql`](supabase/livreur-bizzoo.sql) — le livreur de
   l'enseigne. Il repose les colonnes et la fonction du troisième :
   **si `livreur-nom.sql` n'a pas encore été collé, celui-ci suffit**.

**Le troisième est né d'une erreur, et elle mérite d'être écrite.**
`livreurs_boutique()` avait été enrichie — nom et téléphone — dans
`schema.sql` et `role-livreur.sql` seulement. Or une base déjà en
service ne rejoue ni l'un ni l'autre : les colonnes `nom` et `tel`
arrivaient bien sur les comptes, mais la liste de « Confier à un
livreur » continuait de rendre des adresses e-mail. **La
fonctionnalité était posée partout sauf là où elle se voit**, et rien
n'échouait — ni banc, ni écran, ni message d'erreur.

Ce qui l'a rattrapée : une lecture directe de la base après coup,
comparant ce qu'on croyait avoir livré à ce qui s'y trouvait vraiment.
`pg_get_function_result()` rendait encore
`TABLE(id uuid, email text, actif boolean)`.

**La règle qui en sort :** toucher une fonction dans `schema.sql` ne
suffit pas. Il faut se demander quel fichier une base EN SERVICE
rejouera pour la recevoir — et si aucun ne le fait, en écrire un.

## Ce que cherche la recherche

Le champ de recherche regarde six endroits, **dans cet ordre** :

1. le nom du produit,
2. sa catégorie,
3. sa sous-catégorie,
4. son code,
5. sa référence,
6. sa description.

L'ordre est **strict** : un produit trouvé par son nom passe devant un
produit trouvé par son rayon, même si ce dernier retrouve davantage des
mots tapés. Sans cette règle, trois mots retrouvés dans une description
finiraient par battre un titre exact — c'est le piège qu'un classement
par simple addition de points tend toujours.

À l'intérieur d'un même rang, le classement se fait plus fin : un mot en
tête de nom pèse plus qu'un mot au milieu, et retrouver tout ce qui a
été tapé vaut mieux que la moitié. Mais jamais assez pour changer de
rang.

## Paiement en ligne

Le client remplit un panier, valide, paie par **Mobile Money** (MTN,
Moov, Celtiis) — ou par carte, avec KkiaPay seulement —, et la commande arrive dans le compte
administrateur de **chaque boutique concernée** — chacune ne voit que ses
lignes à elle. Tant que le paiement n'est pas ouvert, le panier
fonctionne quand même : la commande part sur WhatsApp, comme avant.

### Deux agrégateurs, au choix de l'enseigne

`paiement.fournisseur` dit qui encaisse : `kkiapay` ou `feexpay`.
L'enseigne en change dans ses réglages, sans qu'on republie quoi que ce
soit. **Ils ne fonctionnent pas pareil, et c'est ce qui explique tout :**

| | KkiaPay | FeexPay |
|---|---|---|
| Ce que l'app porte | une clé **publique** | **rien** |
| Qui ouvre le paiement | l'app (widget) | **notre Edge Function** |
| Ce qui prouve l'encaissement | une notification **signée** | notre serveur **interroge** FeexPay |
| Frais (Bénin) | selon contrat | **1,7 %** Mobile Money |
| Carte bancaire | par le widget | annoncée (4,5 %), mais **absente de l'API V2** |

La carte, chez FeexPay, n'existe que sur leur plaquette : l'API V2 n'a
aucune adresse pour elle, et leur propre SDK V2 la désactive en
répondant « Les paiements par cartes sont momentanément indisponibles ».
Tant que FeexPay encaisse pour BIZZOO, les clients paient donc par
Mobile Money — l'écran des réglages le dit à l'enseigne.

FeexPay n'envoie **aucune notification signée** — rien qu'un
`callback_url`, c'est-à-dire une redirection de navigateur, fabriquée
chez le client donc falsifiable. Et son jeton est un **secret porteur**,
que leur propre SDK met pourtant dans le navigateur. On inverse donc le
sens : notre Edge Function ouvre le paiement (le jeton reste dans les
secrets Supabase), garde la **référence** que FeexPay lui rend, puis va
lui demander si le versement a abouti. La réponse de FeexPay décide.

> **Le mode « SANDBOX » de FeexPay est truqué côté navigateur.** Leur SDK
> n'appelle pas l'API en mode test : il renvoie un succès écrit en dur.
> Notre fonction n'a donc **pas** de mode test — le reproduire rouvrirait
> exactement la porte que tout le reste du projet ferme. Éprouvez avec un
> petit montant réel.

#### La notification de FeexPay n'est pas signée

FeexPay poste bien une notification sur une adresse qu'on lui donne. Mais
le payload est un simple JSON : **ni secret, ni signature, ni en-tête
d'authentification**. Rien n'y prouve qu'il vient d'eux — n'importe qui
connaissant l'adresse peut poster `{"reference":"…","status":"SUCCESSFUL"}`
et se faire livrer sans payer.

`feexpay-webhook` ne la croit donc pas. Il n'en retient **que la
référence**, comme clé de recherche, puis redemande à FeexPay sur son API
si le versement a abouti — et c'est cette réponse-là qui décide, montant
compris.

Pourquoi la brancher quand même : l'application interroge 90 secondes
après le paiement. Un client qui ferme l'application, ou qui met plus
longtemps à taper son code, laissait sa commande « à payer » **pour
toujours**. La notification bouche ce trou.

Mise en route de FeexPay, une fois :

```bash
supabase secrets set FEEXPAY_TOKEN='fp_votre_jeton'
supabase secrets set FEEXPAY_SHOP='identifiant-de-boutique'
supabase functions deploy feexpay --no-verify-jwt
supabase functions deploy feexpay-webhook --no-verify-jwt
```

Puis, dans le tableau de bord FeexPay → menu **Webhook**, déclarer :
`https://<projet>.supabase.co/functions/v1/feexpay-webhook`

Puis `supabase/feexpay.sql` dans l'éditeur SQL, et l'agrégateur se
choisit dans Admin → Réglages → BIZZOO.

### Le principe, à ne jamais contourner

### Le principe, à ne jamais contourner

**L'application ne valide jamais un paiement.** Avec KkiaPay elle ouvre
la page de paiement, et c'est KkiaPay qui, une fois l'argent encaissé,
appelle une fonction serveur. Avec FeexPay elle ne fait qu'inviter notre
serveur à aller vérifier. Dans les deux cas, ce qui fait passer une
commande à « payée » vient de l'agrégateur, jamais du téléphone.

```
Appli client ──ouvre le paiement (clé PUBLIQUE)──▶ KkiaPay
                                                     │
                             notification signée     │
                             (secret du webhook)     ▼
                                        Fonction Edge kkiapay-webhook
                                                     │ service_role
                                                     ▼
                                             marquer_payee()
```

La raison tient en une phrase : le message de succès de KkiaPay arrive
**sur le téléphone du client**. C'est du code qu'on peut modifier. Si
l'application disait « j'ai payé, valide ma commande », n'importe qui
pourrait le lui faire dire. Seul KkiaPay, qui détient le secret, peut
déclencher la validation.

Conséquence à l'écran : après le paiement, le reçu **attend** que l'état
bouge, il ne l'annonce pas. Il s'écoule quelques secondes entre la
confirmation chez KkiaPay et l'arrivée de sa notification.

### Où vit chaque secret

| Élément | Où il vit | Jamais |
|---|---|---|
| Clé **publique** | En base (table `paiement`), lue par l'app | — (elle est faite pour ça) |
| Clé **privée** | Tableau de bord KkiaPay | on n'en a **jamais** besoin ici |
| **Secret du webhook** | Secret Supabase (`KKIAPAY_WEBHOOK_SECRET`) | dans l'app, dans le dépôt, dans une conversation |

La clé publique est **en base** et non dans le code : on passe des
essais à la production sans reconstruire ni republier les APK.

### Mise en route

1. **Compte marchand KkiaPay**, puis relever la **clé publique** *bac à
   sable* et choisir un **secret de webhook**. Ne saisissez jamais la
   clé privée : elle ne sert à rien ici.
2. **Base** : exécuter `supabase/schema.sql` (il porte déjà les tables
   `commandes`, `commande_lignes` et `paiement`). Sur une base déjà en
   place, [`supabase/commandes-paiement.sql`](supabase/commandes-paiement.sql)
   suffit : il ne contient que les commandes et le paiement, et se
   relance sans danger.
3. **Fonction Edge**, une seule fois, depuis un ordinateur :
   ```bash
   supabase secrets set KKIAPAY_WEBHOOK_SECRET='votre-secret'
   supabase functions deploy kkiapay-webhook --no-verify-jwt
   ```
   `--no-verify-jwt` est **indispensable** : KkiaPay n'envoie aucun jeton
   Supabase, la fonction serait rejetée avant d'être exécutée. C'est le
   secret qui la protège, vérifié à durée constante dans le code.
4. **Déclarer l'adresse** dans le tableau de bord KkiaPay, **du bon
   côté** (bac à sable ou production, voir le piège ci-dessous) :
   `https://<projet>.supabase.co/functions/v1/kkiapay-webhook`
5. **Application admin** → Réglages → BIZZOO → *Paiement en ligne* :
   coller la clé publique, laisser « Mode essai », enregistrer.
6. **Éprouver** : passer une commande avec le numéro de test
   `97000000`, et vérifier que la commande apparaît « Payée » dans
   l'écran Commandes. Tant que ce test n'est pas passé, l'intégration
   n'est pas finie — c'est le seul qui prouve que la chaîne entière
   tient.

### Trois pièges qui coûtent des heures

- **Bac à sable et production sont deux mondes séparés.** Chacun a ses
  clés *et* ses webhooks. Un webhook déclaré en production n'est jamais
  appelé par un paiement d'essai : l'argent « part » et rien ne se
  valide, sans le moindre message. Les trois interrupteurs — le mode du
  tableau de bord KkiaPay, la clé publique, le webhook — se poussent
  **ensemble**.
- **Un vrai numéro est toujours refusé en bac à sable.** « Le numéro
  n'est pas valide » n'est pas une panne. Numéros de test : MTN
  `97000000` (et `97000002` pour un solde insuffisant), Moov
  `95000000`. Carte : `4242 4242 4242 4242`, exp. `01/31`, CVV `812`.
  Compter 1 à 2 minutes entre la validation et la confirmation.
- **Un délai dépassé n'est pas un échec.** Si un appel expire, la
  transaction peut très bien avoir abouti. Rien ne marque « échoué » sur
  une erreur réseau — c'est la première cause des « j'ai été débité mais
  ma commande n'est pas passée ».

### Ce que la base refuse, quoi qu'on lui envoie

- **Le client n'écrit pas les prix.** Il envoie des identifiants et des
  quantités ; `creer_commande()` relit le catalogue, fige le nom, la
  référence et le prix, et calcule le total. C'est ce total-là qui part
  chez KkiaPay.
- **Le client ne se déclare pas payé.** Une commande naît « à payer », et
  le déclencheur `commande_verrous` refuse tout passage à « payée » qui
  ne vienne pas de `marquer_payee()`.
- **Ce que le téléphone affirme et ce que KkiaPay prouve ne partagent pas
  une colonne.** L'application peut noter la transaction que KkiaPay lui
  a répondue — c'est un indice utile à la boutique — mais elle l'écrit
  dans `transaction_annoncee`. La preuve, elle, vit dans
  `transaction_id`, que seul le serveur remplit. Mélanger les deux
  laisserait n'importe qui réclamer la transaction d'un autre pour
  bloquer son encaissement.
- **Une commande n'est retrouvée que par la référence que nous avons
  nous-mêmes confiée à KkiaPay.** Se rabattre sur ce qu'un téléphone
  annonce laisserait le client choisir quel versement valide quelle
  commande — un versement de 100 000 réglant une commande de 100 francs.
- **`marquer_payee()` n'est appelable par personne d'autre que le
  serveur.** `EXECUTE` est révoqué de `public`, `anon` **et**
  `authenticated` — révoquer du seul `public` ne suffirait pas, Supabase
  accordant d'office ces droits aux deux autres. La requête de
  vérification est à la fin du fichier SQL : seul `service_role` doit
  apparaître.
- **Le montant qui compte est celui annoncé par KkiaPay.** Un paiement
  incomplet ne valide rien : la commande porte alors la remarque « reçu
  X sur Y attendus », que la boutique voit en rouge.
- **La notification est rejouable sans danger.** KkiaPay réessaie cinq
  fois tant qu'il n'a pas reçu un 200 ; un index unique sur la
  transaction et un état déjà « payée » font que rejouer ne fait rien de
  plus.

### Si une notification se perd

Le client a été débité, la commande reste « en attente ». L'écran
Commandes montre alors, au superadministrateur seulement, la transaction
que le téléphone a annoncée. Après l'avoir retrouvée dans le tableau de
bord KkiaPay, il peut se porter garant : **Confirmer le paiement à la
main**. La commande garde son nom — on voit d'un coup d'œil qu'elle n'a
pas été confirmée par la banque.

### Ce qui n'est pas fait, volontairement

- ~~Le stock ne se décrémente pas à la vente.~~ **Il se décompte depuis
  la 3.49.0** (section « Le stock suit les ventes »). La crainte d'alors
  — chaque vente marquant le produit comme modifié, et envoyant « catalogue
  mis à jour » à tous les clients — est écartée : le décompte ne touche
  pas à `modifie_le`, et la vérification de fond d'Android ne regarde que
  lui. Les applications ouvertes, elles, voient le nouveau chiffre par le
  temps réel.
- **Aucun message WhatsApp n'est envoyé automatiquement** à la boutique :
  cela demanderait l'API WhatsApp Business, qui est payante et suppose un
  numéro dédié. À la place, la commande arrive dans le compte
  administrateur, et le reçu du client propose un bouton « Prévenir la
  boutique » — le message part alors du WhatsApp du client, avec le
  détail déjà écrit.

## Vérification du numéro (entrer par SMS)

Au Bénin, beaucoup d'acheteurs n'ont pas d'adresse e-mail mais tous ont
un numéro. L'application propose donc **deux portes** pour ouvrir un
compte : e-mail + mot de passe, ou **numéro + code reçu par SMS**.

Rien n'est fabriqué à la main : le code est **celui de GoTrue**, et
`auth.users.phone_confirmed_at` est le seul ancrage. Un déclencheur
recopie le numéro confirmé dans la fiche client, et refuse de lui voler
un numéro déjà vérifié ailleurs.

**La porte SMS ne fonctionne qu'une fois branchée.** Quatre gestes,
depuis un ordinateur :

1. **Les secrets**, jamais dans le dépôt ni dans un APK :

   ```bash
   supabase secrets set SMS_CLE=…          # la clé CREATISINTER
   supabase secrets set SMS_EXPEDITEUR=…   # 11 caractères maximum
   supabase secrets set SMS_HOOK_SECRET=…  # celui que Supabase affiche à l'étape 3
   ```

2. **Les deux fonctions** :

   ```bash
   supabase functions deploy hook-sms-auth --no-verify-jwt
   supabase functions deploy tester-sms
   ```

   `--no-verify-jwt` est indispensable : c'est Supabase lui-même qui
   appelle ce point d'entrée, sans jeton d'utilisateur. Ce qui le protège
   n'est pas un jeton mais **la signature** — l'en-tête Standard Webhooks,
   vérifiée octet pour octet sur le corps brut, avec une fenêtre de cinq
   minutes contre le rejeu. Sans `SMS_HOOK_SECRET`, la fonction refuse de
   démarrer plutôt que de laisser passer.

3. **Dashboard → Authentication → Providers → Phone** : activer, puis
   **Send SMS hook** → `https://<projet>.supabase.co/functions/v1/hook-sms-auth`.
   Supabase affiche alors le secret `whsec_…` : c'est lui qui va dans
   `SMS_HOOK_SECRET`.

4. **Éprouver pour de vrai**, depuis l'app admin : Réglages → *Essayer la
   passerelle SMS*. L'écran rend **la réponse brute de la passerelle** —
   c'est voulu : si un champ ne porte pas le nom attendu, la réponse le
   dit elle-même.

Deux pièges qui coûtent des heures :

- **Un `HTTP 200` de CREATISINTER ne veut pas dire « envoyé ».** La
  réponse porte un `status` et un code d'état ; seuls
  `SUBMITTED`, `SENT`, `DELIVERED` et `PROGRAMMED` valent succès. Le
  transport (`functions/_partage/sms.ts`) le vérifie, et 64 assertions
  (`tools/eprouver-sms.sh`) l'éprouvent.
- **Le numéro a trois formes.** `0197121596` est ce que le client tape et
  ce que la base range ; `+2290197121596` est ce que GoTrue **exige** en
  entrée ; `2290197121596` — sans le `+` — est ce qu'il **range**. Relire
  `user.phone` et le renvoyer tel quel échoue, toujours.

**Tant que ces quatre gestes ne sont pas faits, les chemins par SMS se
retirent d'eux-mêmes.** En ligne, le fournisseur « Phone » était éteint,
et pourtant « Entrer avec mon numéro », « Vérifier par SMS » et
l'invitation de Mes commandes s'affichaient — pour mener tous au même
refus, en anglais : « Unsupported phone provider ». L'application
demande désormais à Supabase ce qui est ouvert (`GET /auth/v1/settings`,
une lecture publique) et retire tout élément marqué `data-sms` quand la
réponse est **non**. Dans le doute — réseau coupé, réponse illisible —,
elle **montre** : un refus bien dit coûte moins qu'un chemin caché à
tort. Un ancien lien vers « Entrer avec mon numéro » dit que ce n'est
pas encore ouvert et montre les autres portes, et le refus anglais se
traduit s'il arrive quand même. La question ne se pose qu'une fois par
ouverture de l'application : le jour où l'enseigne active le SMS, les
chemins reviennent au lancement suivant, sans nouvelle version.
[`tools/banc-sms-ferme.mjs`](tools/banc-sms-ferme.mjs) l'éprouve :
trente-deux constats, trois sabotages qui le font rougir.

## Deux applications, un seul point d'entrée

Les deux applications restent **séparées**, et c'est délibéré :
l'écran des marges ne doit pas se trouver à deux touches de celui que le
client regarde par-dessus l'épaule du vendeur. Une fausse manœuvre y
montrerait le prix BIZZOO de l'article qu'on est en train de lui vendre.

Mais un vendeur qui a ouvert BIZZOO n'a plus à ressortir chercher une
icône : **Mon compte → Espace vendeur** passe la main à BIZZOO Admin.

La carte n'apparaît **que pour un compte de l'équipe**. On le sait en
lisant `profils`, dont la règle RLS dit `id = auth.uid()` — un client
ordinaire qui pose la même question reçoit zéro ligne. Rien n'est caché
dans cette lecture, et rien n'est deviné.

**Elle n'ouvre aucune porte.** BIZZOO Admin redemande de s'identifier,
et c'est la base qui décide ensuite de ce que ce compte peut faire. Le
bouton épargne un geste, il n'accorde rien.

Sur Android, le passage se fait par le pont `AndroidPont` :
`espaceVendeurPresent()` dit si l'application est là — sinon la carte le
dit franchement plutôt que de promettre un bouton qui ne mènerait nulle
part — et `ouvrirEspaceVendeur()` la lance. **Android 11 et au-delà
cachent les applications installées** : sans la déclaration `<queries>`
dans `AndroidManifest.xml`, le système répond toujours « rien », même
quand l'application est bien là. Sur le web, où il n'y a pas de pont,
le bouton ouvre simplement le dossier voisin.

Au passage : un compte de l'équipe ne voit plus le formulaire « Vous
achetez pour revendre ? ». La base refuse qu'un compte soit des deux
côtés à la fois (`compte_unique()`), et le lui proposer l'envoyait le
remplir pour se faire refuser.

## La marge change, les prix suivent

Le modèle est `prix de vente = prix BIZZOO + marge`. Mais jusqu'à la
version 3.25, le prix de vente était calculé **par l'application** au
moment d'enregistrer le produit, puis figé dans la table. Changer la
marge d'une boutique ne touchait donc **rien** : il fallait rouvrir et
réenregistrer chaque article, un par un. Personne ne fait cela sur deux
cents articles — la marge affichée dans les réglages et celle réellement
pratiquée divergeaient en silence.

La base s'en charge désormais : changer `boutiques.taux_marge` recalcule
le prix de vente de tous les articles de cette boutique, à l'instant.
Deux choses restent intactes — **un article qui a son propre
`taux_marge`**, recalculé avec le sien ; et **ce qui a été vendu**, la
ligne de commande gardant le prix et le taux du jour de la vente.

Le déclencheur ne touche pas `modifie_le` : c'est lui qui déclenche la
notification « catalogue mis à jour » sur les téléphones. Un changement
de marge doit rafraîchir les écrans ouverts, pas réveiller toute la
ville.

**Côté client, un revendeur connecté suit sans se reconnecter.**
`Live` surveille désormais `boutiques` — changer un taux revendeur ne
déplace aucun prix public, donc rien d'autre ne le signalerait — et
**redemande `mes_prix()` à chaque vérification** pour un compte
connecté. On ne peut pas déduire du catalogue que les prix du compte ont
bougé : le taux d'un article vit dans une table que le client ne lit
pas. La seule réponse sûre est de la redemander à la base. Effet de
bord heureux : un revendeur qui vient d'être validé voit ses prix
arriver sans quitter l'application.

## La marge sur les ventes aux revendeurs

Un revendeur validé n'achète pas au prix public. Jusqu'à la version 3.23
il achetait au **prix BIZZOO exact** — ce que la boutique veut toucher —
et cela posait deux problèmes : **l'enseigne ne gagnait rien** sur ces
ventes, et le revendeur **lisait article par article le prix BIZZOO**,
que `produits_prive` existe précisément pour cacher.

Il paie désormais un prix calculé, de l'une des deux façons. **Chaque
boutique choisit la sienne**, dans sa fiche (Boutiques → Modifier) :

| Mode | Calcul | Arrondi |
|---|---|---|
| `bizzoo` | prix BIZZOO **+** N % | aux 5 F **supérieurs** — la marge n'est jamais rabotée |
| `public` | prix public **−** N % | aux 5 F **inférieurs** — la remise annoncée est tenue |

Le taux part à **10 %** et se règle boutique par boutique. Un article
négocié à part peut avoir **son propre taux**, depuis sa fiche : laissé
vide, c'est celui de la boutique qui s'applique — la règle que
`taux_marge` suit déjà.

**Deux bornes, quel que soit le mode et quel que soit le taux saisi :**

- **jamais sous le prix BIZZOO.** Une remise de 60 % sur un article dont
  la marge est de 20 % ferait vendre à perte, et personne ne s'en
  apercevrait avant les comptes ;
- **jamais au-dessus du prix public.** Un revendeur qui paierait plus
  cher qu'un client de passage n'aurait aucune raison de rester.

Quand le prix public est *déjà* sous le prix BIZZOO — une fin de série
soldée — les deux bornes se contredisent : **le plafond l'emporte**, la
perte étant déjà consentie en vitrine.

**Le taux appartient à l'enseigne.** `boutique_verrous` refuse à une
boutique de changer son mode ou son taux, exactement comme pour
`taux_marge` : une boutique qui pourrait le ramener à zéro revendrait au
prix BIZZOO, et tout ceci n'aurait servi à rien. Le taux d'*un article*,
lui, reste à la boutique — elle seule connaît ses négociations.

**L'écran et la caisse calculent le même prix**, et c'est le constat
principal de [`supabase/tests/98-marge-revendeur.sql`](supabase/tests/98-marge-revendeur.sql) :
`mes_prix()` affiche, `ligne_a_l_ecriture()` facture, et les deux
appellent `prix_revendeur()`. L'application admin en tient un aperçu en
JavaScript (`Store.prixRevendeur`) pour montrer le résultat pendant la
saisie — **c'est un aperçu, pas la règle** : les onze mêmes cas sont
éprouvés des deux côtés, et si vous touchez à l'un, touchez à l'autre.

### Où se trouve le commerce

Valider une demande de compte revendeur, c'est accorder une **remise
permanente sur tout le catalogue**. Pour décider, l'enseigne n'avait
qu'un nom, une adresse e-mail et une phrase. La demande porte désormais
**où se trouve le commerce**, sous deux formes complémentaires — et
aucune n'est obligatoire :

- **l'adresse écrite** : au Bénin, c'est elle qui permet de trouver. Un
  point GPS ne se dicte pas à un taximan ;
- **les coordonnées** : relevées par le téléphone d'un geste, ou tirées
  d'un **lien de carte collé**. Elles ouvrent l'itinéraire depuis l'app
  admin.

**C'est une déclaration, pas une preuve.** Personne n'a vérifié que le
point posé est bien une boutique : elle sert à décider en sachant de
quoi l'on parle. La base se contente d'écarter ce qui n'est *pas* une
position — hors bornes, `NaN`, une latitude sans longitude, et le
fameux **`0, 0`** qu'un téléphone rend quand il n'a rien trouvé, et qui
tombe au large du Ghana. Un point faux sur une carte est pire que pas
de point du tout : on se déplace pour rien.

La position **survit à la validation** — l'enseigne doit pouvoir
retrouver ce sur quoi elle s'est décidée — et ne se lit **que par
l'enseigne** : l'adresse d'un commerce est celle d'une personne.

**Elle se complète après coup.** Une demande déposée sans position n'est
pas perdue : la carte *Où se trouve votre commerce*, dans Mon compte,
permet de l'ajouter ou de la corriger. Pour un revendeur **déjà
validé**, c'est indispensable — refaire une demande pour rectifier une
adresse le ferait repasser en attente, et ses prix avec, le temps qu'on
la regarde. `Compte.enregistrerPosition()` n'écrit que ces trois champs
et ne touche pas `type_compte` ; c'est `type_compte` qui remet la
décision à zéro, et lui seul. Le banc l'éprouve.

## Un compte pour commander

Par défaut, **on commande sans compte** : un nom, un numéro, et la
commande part. C'est ainsi depuis le premier jour, et l'application est
livrée comme cela.

L'enseigne peut changer d'avis : **Réglages → Un compte pour commander**,
réservé au superadministrateur. Ce qu'un compte apporte au client — la
commande retrouvée d'un téléphone à l'autre, l'avis réservé à qui a payé,
la réclamation qui a un interlocuteur — n'existe que s'il en a un.

Trois choses à savoir avant de pousser l'interrupteur :

- **Le refus est dans la base, pas à l'écran.** `creer_commande()`
  consulte `compte_exige()` et refuse une commande sans compte. Cacher un
  bouton ne fermerait rien : il suffirait d'appeler la fonction
  directement. L'écran, lui, prévient **avant** le formulaire — découvrir
  qu'il faut un compte après avoir tapé son nom, son numéro et son
  adresse fait abandonner un panier plein.
- **On ferme la caisse, pas le magasin.** Le catalogue, la recherche et
  le panier restent ouverts à tous. On ne demande rien tant que le client
  n'a pas décidé d'acheter, et son panier l'attend intact pendant qu'il
  ouvre son compte.
- **N'allumez qu'une fois une inscription éprouvée de bout en bout.** Un
  e-mail de confirmation qui arrive vraiment, ou la porte SMS branchée
  (section ci-dessus). Sans cela, vous renverriez un client qui n'a aucun
  moyen d'ouvrir un compte. L'application redemande confirmation avant
  d'allumer, et le journal garde la date de la décision.

Si la ligne de réglage venait à disparaître — restauration, migration,
réparation à la main — la réponse est **« non »** et la caisse rouvre.
C'est délibéré : cette règle force une inscription, elle ne protège rien.
Un accident doit laisser la boutique vendre, pas verrouiller la caisse un
samedi soir sans personne pour la rouvrir.

## Le bilan de santé (3.48.0)

Un contrôle général de l'application, en deux temps : **tout rejouer**
ici (la base sur un vrai PostgreSQL, les deux fonctions de paiement,
la passerelle SMS, le ménage du stockage, chaque banc du navigateur),
puis **ausculter la base en ligne** — sans rien y écrire — et la
comparer au dépôt, objet par objet.

Ce qui était sain : chaque fonction de la base en ligne est **identique**
à celle du dépôt, de même que les règles d'accès, les déclencheurs et les
index ; les trois fonctions de paiement déployées sont celles du dépôt,
à la lettre ; les commandes sont cohérentes à tous les niveaux — lignes,
totaux, états, versements —, sans paiement resté en suspens.

Ce qui ne l'était pas, et ce qui a été fait :

| Trouvé | Corrigé |
|---|---|
| **Deux produits en double**, créés à 1,9 et 6,4 secondes d'écart, même référence, même photo : un double appui sur « Ajouter le produit » | Le bouton se grise pendant l'envoi. Même verrou sur « Supprimer » (dont le refus ne se disait nulle part), « Mettre en avant », les codes promo et chaque « Enregistrer » des réglages — où un double appui déposait deux demandes de validation |
| **Une photo partagée** par les deux jumeaux : la retirer de l'un l'aurait effacée sous les yeux de l'autre | Avant d'effacer un fichier, on demande à la base si un autre produit le montre encore. Au moindre doute, on garde : le ménage du stockage rattrape un fichier de trop, rien ne rattrape un fichier perdu |
| **La règle du stock absente** de la base en ligne (un stock négatif passait) | [`stock-et-droits.sql`](supabase/stock-et-droits.sql), **appliqué en ligne** |
| **Quatre actions d'administration appelables sans compte** — supprimer un compte, changer un mot de passe, approuver ou refuser une demande. Refusées de l'intérieur, mais la porte était ouverte | Même fichier : fermées aux visiteurs, ouvertes à l'équipe. Les appels du client sans compte — commander, suivre, signaler un paiement, essayer un code — restent ouverts |
| **`est_equipe()` ouverte aux visiteurs** dans `schema.sql` seul, fermée partout ailleurs | `schema.sql` aligné ; le banc compare désormais une base installée par lui seul |
| **Les chemins par SMS** menaient à un refus en anglais : le SMS n'est pas branché | Ils se retirent tant qu'il ne l'est pas (section « Vérification du numéro ») |
| **« 4,5 % par carte »** dans les réglages : l'API V2 de FeexPay n'a pas de carte | Le texte dit ce qui est vrai |

[`tests/99p-stock-et-droits.sql`](supabase/tests/99p-stock-et-droits.sql)
éprouve le fichier en base — refus **par la règle** et non par un autre
verrou, refus **à la porte** et non de l'intérieur, base en service
réparée sous le même nom qu'une base neuve ;
[`tools/banc-envoi-unique.mjs`](tools/banc-envoi-unique.mjs), au
navigateur, les doubles appuis et les photos partagées. Chaque
correction a été sabotée à son tour : le banc rougit à chaque fois.

**Ce qui reste à faire, et qui ne se fait pas depuis le code** — dans
le tableau de bord de Supabase ou dans l'admin :

1. **Authentication → URL Configuration** : l'adresse du site et les
   adresses de retour (section « Le réglage Supabase sans lequel « mot de
   passe oublié » ne mène à rien »). Les journaux montrent encore
   `localhost:3000` : un client qui demande un nouveau mot de passe
   reçoit un lien qui ne mène nulle part.
2. **Le SMS**, en quatre gestes (section « Vérification du numéro ») —
   les chemins reviendront d'eux-mêmes.
3. **Dans l'admin**, supprimer les deux jumeaux — codes **100221** et
   **100242**. La suppression garde les photos : l'original ne perd rien.
4. Reposer la photo manquante de **100154** (PlayStation Portal Remote
   Player), et donner un rayon à **100156** (Jetour traveller), qui
   n'apparaît sous aucune catégorie.
5. Facultatif : **Authentication → Passwords → protection contre les mots
   de passe compromis** (selon l'offre Supabase).

Les avis de performance de Supabase (index, relectures de règles) ne
pèsent qu'à grande échelle : rien n'y presse au volume actuel.

## Le stock suit les ventes (3.49.0)

Jusqu'ici, le stock ne bougeait que lorsque la boutique le changeait à
la main. Une commande payée ne retirait rien : le produit restait
« Disponible » après la dernière pièce vendue, et un client pouvait en
commander dix quand il en restait deux — la base acceptait.

### Ce que fait la base

| Moment | Ce qui se passe |
|---|---|
| **Le client commande** | `creer_commande` additionne ce que le panier demande de chaque produit — deux lignes du même article comptent ensemble — et refuse au-delà du stock : « Plus que 2 en stock pour « Clavier Bluetooth » : réduisez la quantité dans votre panier. » Rien n'est enregistré. Un produit **sur commande** ou **en approvisionnement** n'a pas de limite : la boutique le fait venir |
| **La commande est payée** | Un déclencheur ôte les pièces de chaque ligne au moment où la commande passe à « payée » — par l'agrégateur ou par la confirmation d'une boutique, c'est le même chemin. À zéro, le produit passe « En rupture ». Chaque ligne retient ce qu'elle a pris (`stock_pris`) : un paiement rejoué ne décompte pas deux fois |
| **Deux clients paient la dernière pièce** | Le second paiement passe quand même : l'argent est encaissé, on ne le refuse pas après coup. Le stock s'arrête à zéro, jamais en dessous, et la boutique, l'enseigne et le superadministrateur reçoivent **« Stock insuffisant »**, qui ouvre la commande à régler avec le client |
| **Une commande payée est annulée**, ou une seule de ses lignes | Les pièces reviennent au stock — exactement celles qui avaient été prises, et une seule fois |
| **Le décompte échoue** (un produit que la base refuse d'écrire) | Le paiement passe ; **« Stock à vérifier »** part à la boutique et à l'enseigne |

La dernière pièce vendue prévient la boutique (**« Rupture de stock »**,
sans son, qui ouvre l'écran Stock sur ce qui manque) ; les deux autres
alertes sonnent.

Le fichier [`stock-ventes.sql`](supabase/stock-ventes.sql) a été
**appliqué en ligne**. Les commandes payées **avant** lui ne sont pas
repassées : leur stock a pu être corrigé à la main entre-temps, et la
base ne peut pas le savoir. Une commande envoyée par **WhatsApp** n'est
pas une commande de la base : elle ne décompte rien, la boutique corrige
son stock dans l'écran Stock.

### Ce que voit le client

- **La fiche produit s'arrête au stock** : le « + » ne dépasse pas ce
  qui reste, en comptant ce qui est déjà au panier, et « Plus que 3 en
  stock » s'affiche à cinq pièces ou moins.
- **Le panier se ramène au stock du moment** : une quantité devenue trop
  grande — une autre vente est passée — est ramenée, et le panier le dit
  jusqu'à ce que le client y touche ; un article épuisé reste affiché mais
  grise « Passer la commande ». Le formulaire de commande ne s'ouvre pas
  sur un panier que le stock ne couvre plus.
- **Si la base refuse quand même** — une vente est passée pendant qu'il
  remplissait le formulaire —, le client revient au panier, catalogue
  relu, avec la phrase de la base. La relecture est silencieuse : avant,
  « Catalogue mis à jour » recouvrait l'explication.

### L'écran Stock de l'admin

Trois chemins y mènent : l'icône boîte en haut de **Produits**, la carte
**Stock** de l'accueil (pressante dès qu'il y a une rupture ou un stock
bas), et les notifications de rupture. Tous les produits de la boutique,
**le plus urgent en tête** — en rupture, bientôt épuisés (trois pièces
ou moins), en stock, en approvisionnement, sur commande —, des filtres
comptés, une recherche. Toucher un produit ouvre la saisie sur le
chiffre du moment, relu en base : − et +, « En rupture », « Sur
commande », le réassort annoncé.

Toute l'équipe lit cet écran ; seuls les comptes qui modifient les
produits y changent un chiffre — la base le refuse aux autres, l'écran
ne fait que ne pas le proposer.

### Une vente pendant qu'on saisit

Le stock bouge désormais tout seul, et deux mains peuvent le toucher à
la fois : la base qui décompte une vente, la boutique qui saisit un
arrivage. Sans précaution, la seconde écrasait la première — et les
pièces vendues revenaient en rayon.

- **La saisie s'écrit sur le chiffre vu** (`stock=eq.N` dans la
  requête) : si une vente est passée entre-temps, même à l'instant de
  l'envoi, rien n'est écrit ; l'écran dit le nouveau chiffre, garde ce
  qui a été tapé, et le prochain appui part de lui.
- **Le formulaire du produit ne renvoie le stock que s'il a été
  changé** : retoucher une description ne rend plus les pièces vendues
  pendant qu'on écrivait.
- **Défaire une retouche** dans l'historique garde le stock du moment ;
  seule une action **sur** le stock — un chiffre saisi, une rupture, un
  passage sur commande — remet l'ancien chiffre.
- **Une photo retirée ne quitte le stockage qu'après l'écriture de la
  fiche.** Elle partait avant : une écriture refusée — un stock qui a
  bougé, un réseau coupé — laissait une fiche qui désignait une photo
  effacée. Un fichier de trop, le ménage du stockage le rattrape ; un
  fichier perdu, rien.

### Les bancs

[`tests/99q-stock-ventes.sql`](supabase/tests/99q-stock-ventes.sql)
éprouve la base en 44 constats : l'excédent refusé (deux lignes du même
produit comprises) sans rien laisser derrière, le décompte au paiement
comme à la confirmation d'une boutique, le paiement rejoué, la survente,
les deux annulations, le produit qui refuse l'écriture, et les droits —
personne n'écrit `stock_pris`, personne ne rend du stock à la main.
[`tools/banc-stock.mjs`](tools/banc-stock.mjs) éprouve les deux
applications en 101 constats. Chaque garde a été sabotée à son tour —
la garde de la saisie, celle du formulaire, la relecture silencieuse,
l'annulation, le plafond du panier, le message gardé, la photo effacée
avant la fiche : le banc rougit à chaque fois.

## L'accueil réordonné et la galerie « Nos produits » (3.50.0)

L'accueil de BIZZOO, de haut en bas :

| | Bloc | Ce qui a changé |
|---|---|---|
| 1 | La recherche | Rien : c'est la porte d'entrée, pas un contenu — elle reste tout en haut |
| 2 | **Le slider** | Il passe **en tête des contenus** (il venait après les catégories) |
| 3 | **Huit catégories** | Toujours huit, deux rangées de quatre — il n'y en avait que quatre |
| 4 | L'offre du jour, puis la publicité | Elles passent **avant** les boutiques (elles venaient après) |
| 5 | Nos boutiques partenaires | **Quatre par rangée** (trois auparavant) |
| 6 | Produits populaires | Inchangés : seulement quand il y a eu des ventes, juste avant « Nos produits » |
| 7 | **Nos produits** | Nouveau : les huit derniers arrivés, et le bouton **« Voir tout — N produits »** |

**Pourquoi quatre catégories seulement ?** L'accueil ne montrait que
celles que l'enseigne a mises « en avant », et la base en ligne n'en a
que quatre sur quinze. Il en montre désormais toujours huit : celles
de l'enseigne d'abord, dans son ordre ; les places qui restent vont à
celles qui ont des produits — un rond qui mène à un écran vide est un
détour pour rien —, puis aux autres, dans l'ordre de la liste. Aucune
donnée n'a été touchée ; l'admin l'explique au-dessus de la liste des
catégories.

**Les boutiques par quatre.** Le logo suit la largeur de la tuile,
60 px au plus : 46 px sur un téléphone de 320 px, 56 px sur un de 360,
toujours carré et avec de l'air autour. Deux lignes restent réservées
au nom, pour que toutes les tuiles aient la même hauteur. Un nom d'un
seul mot tient sur **une** ligne et finit par « … » s'il déborde :
« JouJoutheque » se coupait en « JouJoutheq / ue ».

### La galerie « Nos produits »

« Voir tout » ouvre `#/nos-produits` : tout le catalogue des boutiques
ouvertes, **les derniers arrivés d'abord** — les huit cartes de
l'accueil sont les huit premières de la galerie, dans le même ordre.

- **Elle se remplit en défilant.** Vingt cartes d'abord ; les vingt
  suivantes arrivent quand le pouce approche du bas, 900 px avant qu'il
  ne l'atteigne. Deux cent cinquante cartes d'un coup, c'était deux
  cent cinquante photos demandées ensemble sur un forfait mobile.
- **Chaque photo ne se charge qu'à l'approche** (`loading="lazy"`) :
  à l'ouverture, une quinzaine sur soixante-cinq.
- **Un très grand écran se remplit tout seul.** Le guetteur de
  défilement ne prévient qu'au moment où le bas *entre* en vue ; resté
  en vue après un lot, il se taisait, et la galerie attendait un
  défilement qui ne viendrait pas. On le relance après chaque lot.
- **Un bouton « Afficher plus »** prend le relais sur un navigateur qui
  ne sait pas guetter le défilement.
- **Le retour d'une fiche produit retombe au même endroit.** Les cartes
  déjà vues sont reposées d'emblée — sans elles, la hauteur où revenir
  n'existerait plus. Et la galerie reste celle de **toutes** les
  boutiques : ouvrir un produit fait entrer dans sa boutique, la
  galerie en ressort au retour.

Le catalogue d'une boutique (`#/produits`, « Voir les N produits » sur
sa fiche) se remplit de la même façon, du moins cher au plus cher.

[`tools/banc-accueil-galerie.mjs`](tools/banc-accueil-galerie.mjs)
éprouve tout cela en 64 constats, de 320 à 1 280 px. Six sabotages le
font tomber : les catégories à la une seules, trois boutiques par
rangée, le nom coupé en deux, le guetteur non relancé, les cartes vues
non reposées, la boutique du produit gardée au retour.

### La loupe, sur chaque écran où l'on parcourt (3.51.0)

La recherche n'est plus un onglet : sur l'accueil, c'est la pilule du
haut ; ailleurs, une loupe dans l'en-tête. **Elle manquait dans une
catégorie** : entré par un rond de l'accueil, on ne pouvait plus
chercher qu'en y revenant. Elle manquait aussi sur les promotions, la
liste des boutiques et la fiche d'une boutique.

Elle vient maintenant d'une seule fonction, `UI.boutonRecherche()`,
posée sur tous ces écrans — la catégorie (liste de ses rayons comme
grille de ses produits), un rayon, les promotions, l'onglet
« Catégories », « Nos boutiques », la fiche d'une boutique, son
catalogue et la galerie « Nos produits ». Le banc suit le chemin
signalé — l'accueil, un rond, les produits de la catégorie, la loupe,
la recherche, le retour — puis passe chaque écran en revue (78 constats
en tout) ; retirer la loupe de la catégorie le fait tomber.

## La nouvelle icône : le B au chariot (3.52.0)

L'œuvre officielle est désormais une **tuile bleue en dégradé**, un
**B blanc** qui dessine un chariot, et ses **deux roues orange**
([`tools/bizzoo-icone.png`](tools/bizzoo-icone.png), 1 280 px). Elle
remplace le sac de courses partout : l'écran d'accueil du téléphone
(Android, iPhone, ordinateur), l'onglet du navigateur, l'écran de
connexion de l'admin, la vignette d'un produit sans photo —
`UI.marque()` affiche le fichier d'icône lui-même.

`node tools/make-icons.js` en tire les 48 images des deux applications,
et la silhouette des notifications :

| Forme | Où | Ce qu'on y voit |
|---|---|---|
| Tuile | PWA 192 et 512, Android d'avant la version 8 | L'œuvre, coins arrondis compris |
| Carré plein | iPhone (`apple-touch-icon`) | Le dégradé jusque dans les coins : l'iPhone arrondit lui-même |
| Maskable | L'application web installée sur Android | Le motif dans le disque de 40 % que tout masque respecte |
| Ronde | Android, lanceurs à icônes rondes | Le carré plein, découpé en disque |
| Adaptative | Android 8 et plus | Deux calques : le dégradé derrière, le B et ses roues devant |
| Notification | La barre d'état d'Android | La silhouette du B et de ses roues, en blanc |

**On ne redessine rien : on sépare.** Une icône ronde ou adaptative
demande un dégradé qui se prolonge au-delà de la tuile, et un B sur un
calque à lui. Le script **mesure** le dégradé sur l'œuvre — un plan par
couleur, ajusté aux moindres carrés sur les pixels bleus, de `#3F7DFF`
en haut à gauche à `#0A1F6B` en bas à droite — et l'orange de chaque
roue, qui a son propre dégradé. Chaque pixel du motif est lu comme un
mélange du fond et de sa couleur pure : on en déduit son opacité, et le
B garde ses bords adoucis.

**L'œuvre est arrivée compressée avec perte** (WebP). Ce format garde la
luminance à pleine résolution, mais la couleur à demi-résolution : d'où
un liseré délavé de 1 à 2 px autour du B, plus sombre autour des roues.
On l'a d'abord pris pour une ombre portée ; la mesure dit le contraire.
Au-delà de 3 px du motif, l'œuvre ne s'écarte pas du dégradé de plus de
3 niveaux, et dans le liseré la luminance est intacte : seule la couleur
a bavé. L'opacité se lit donc dans la **luminance**, et toutes les
formes — la tuile carrée comprise — sont recomposées depuis les deux
calques. Le liseré disparaît, et les icônes se ressemblent toutes.

**Le script vérifie ce qu'il livre**, et s'arrête plutôt que de livrer
faux :
- les deux calques recomposés redonnent l'œuvre : 0,34 niveau d'écart
  de luminance en moyenne, 9 au pire hors des bords du motif (au ras du
  bord de la tuile). Une copie de l'œuvre à laquelle on a ajouté une
  ombre portée est refusée (29 niveaux) ;
- le motif tient dans ce que chaque téléphone laisse voir : le calque
  adaptatif fait 108 dp, le téléphone en montre 72 et garantit un disque
  de 66 dp ; la tuile est posée sur les 72 dp, son motif tombe dans le
  disque ;
- la pastille de l'admin tient dans sa forme, sans toucher le B ni les
  roues.

**L'icône adaptative a maintenant un fond en dégradé.** Son calque de
fond était une couleur, le blanc (`@color/ic_launcher_fond`) : le B
blanc y aurait disparu. C'est désormais l'image
`@mipmap/ic_launcher_fond`, calculée pixel par pixel à chaque densité —
un dégradé n'a pas à être rééchantillonné. Toujours pas de calque
`monochrome` : les téléphones réglés en « icônes thématisées » en
feraient une silhouette d'une seule couleur, sans le bleu ni l'orange
de BIZZOO.

**BIZZOO Admin garde sa pastille « réglages »** — une roue dentée
blanche sur bleu nuit, cerclée de blanc — dans le coin bas-gauche, le
seul que le B laisse libre. Grande sur la tuile, elle se fait plus
petite sous un masque rond ou adaptatif, pour rester dans la zone sûre.

**La notification montre le B.** La petite icône de la barre d'état
était le sac ; c'est la silhouette du B et de ses deux roues, tracée
depuis l'œuvre (contour de l'opacité, simplifié), les deux trous du B
laissés vides. Android n'en garde que la forme, en blanc.

Pour régénérer après un changement d'œuvre :

```bash
PLAYWRIGHT=<chemin>/playwright-core/index.js CHROMIUM=<chemin de chrome> \
  node tools/make-icons.js
```

Le script affiche son bilan : le dégradé mesuré, les roues, les écarts,
la place de la pastille, la silhouette. Sur le téléphone, l'icône
change en installant le nouvel APK ; pour l'application web installée,
le navigateur la reprend à son rythme.

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

## Structure

```
impact-informatique-app/
├── supabase/
│   ├── schema.sql            # La base : tables, sécurité, stockage, données de départ
│   ├── commandes-paiement.sql       # Les commandes seules, pour une base déjà en place
│   ├── code-produit.sql             # Le code d'un produit, pour une base déjà en place
│   ├── marge-bizzoo.sql             # La marge de l'enseigne et les statistiques de ventes
│   ├── comptes-clients.sql          # L'identité du client : compte, numéro vérifié, ses commandes
│   ├── comptes-revendeurs.sql       # Client ou revendeur : qui achète au prix BIZZOO
│   ├── verification-telephone.sql   # Le numéro vérifié par SMS, ancré sur GoTrue
│   ├── mes-commandes.sql            # Droits par colonne : l'acheteur ne lit pas la marge
│   ├── avis.sql                     # Les avis, réservés à qui a payé ; la boutique répond
│   ├── sav.sql                      # Le SAV : la boutique d'abord, BIZZOO en recours
│   ├── compte-obligatoire.sql       # L'interrupteur « un compte pour commander » (éteint)
│   ├── marge-revendeur.sql          # Ce que rapporte une vente à un revendeur
│   ├── position-revendeur.sql       # Où se trouve le commerce d'un revendeur
│   ├── marge-appliquee.sql          # La marge change, les prix de la vitrine suivent
│   ├── statistiques-boutique.sql    # Chaque boutique voit ses ventes, et rien de l'enseigne
│   ├── fiche-client.sql             # Retrouver un client et ses commandes — l'enseigne seule
│   ├── journal-versements.sql       # Une ligne par tentative de paiement, jamais retouchée
│   ├── codes-promo.sql              # Une remise sort de la marge de l'enseigne, jamais de la boutique
│   ├── cycle-commande.sql           # Cinq étapes, et l'accusé de réception que le client seul pose
│   ├── role-livreur.sql             # Le porteur : un écran, deux gestes, aucun montant
│   ├── categories-bizzoo.sql        # La liste des rayons : celle de l'enseigne, et d'elle seule
│   ├── categories-photos.sql        # La photo du rond d'une catégorie : un chemin, un seul dossier
│   ├── feexpay.sql                  # Le second agrégateur, au choix de l'enseigne
│   ├── stock-et-droits.sql          # Bilan de santé : la règle du stock, quatre portes fermées aux visiteurs
│   ├── stock-ventes.sql             # Le stock suit les ventes : excédent refusé, décompte payé, retour annulé
│   ├── etat-des-lieux.sql           # Ce qui est en place et ce qui manque (ne modifie rien)
│   ├── etat-du-stockage.sql         # Les seaux, leur poids et les fichiers orphelins
│   ├── tests/                       # La base éprouvée sur un vrai PostgreSQL
│   ├── functions/kkiapay-webhook/   # KkiaPay : sa notification signée
│   ├── functions/feexpay/           # FeexPay : notre serveur ouvre, puis vérifie
│   ├── functions/feexpay-webhook/   # Sa notification — non signée, donc jamais crue
│   ├── functions/_partage/sms.ts    # Le transport SMS : un 200 n'est pas un succès
│   ├── functions/hook-sms-auth/     # Livrer le code de connexion — la signature est le seul contrôle
│   └── functions/tester-sms/        # Le bouton d'essai, par le chemin de la production
├── client/                   # Application des clients
│   ├── config.js             # URL + clé publiable du projet Supabase
│   ├── demo-catalogue.json   # Catalogue de démonstration (si config vide)
│   ├── index.html / styles.css / manifest.webmanifest / sw.js
│   ├── img/categories/       # Les illustrations des ronds (Fluent Emoji 3D, MIT)
│   └── js/
│       ├── catalogue.js      # Lecture de la base + copie hors connexion + prix du compte
│       ├── compte.js         # Le compte du client : session, fiche, demande de revendeur
│       ├── avis.js           # Lire les avis sans compte, en donner un si l'on a payé
│       ├── sav.js            # Réclamations : la boutique d'abord, BIZZOO en recours
│       ├── panier.js         # Le panier : des identifiants, jamais des prix
│       ├── paiement.js       # Commander, ouvrir KkiaPay, attendre la base
│       ├── ui.js             # Logo, cartes produit, prix, badges
│       └── vues/             # Accueil, catégories, produit, produits, panier, recherche, infos
├── admin/                    # Application du gérant
│   ├── config.js
│   ├── index.html / styles.css / manifest.webmanifest / sw.js
│   ├── img/categories/       # Les mêmes illustrations, pour la liste et la galerie
│   └── js/
│       ├── supabase.js       # Connexion, base, stockage des photos
│       ├── store.js          # Logique métier (slider, rôles, validations…)
│       └── vues/             # Connexion, accueil, boutiques, produits, catégories,
│                             #   commandes, statistiques, validations, revendeurs,
│                             #   clients, versements, codes, avis, SAV, réglages,
│                             #   livraisons (le seul écran du livreur)
├── android/                  # Projet Android unique, deux variantes
│   ├── app/src/main/java/... # MainActivity : WebView, photos, WhatsApp, retours
│   ├── app/src/{client,admin}/  # Nom, couleurs, icônes de chaque application
│   ├── preparer-assets.js    # Copie les fichiers web dans les APK
│   └── signature/            # Clé de TEST (pas celle du Play Store)
├── apk/                      # APK construits par GitHub Actions
├── index.html                # La vitrine : l'accueil du site
├── vitrine/                  # Ses captures, et l'image de l'aperçu partagé
├── 404.html / robots.txt / sitemap.xml   # Ce qu'attend un site en ligne
├── hebergement/htaccess      # Le .htaccess de www.bizzoomarket.com (Apache, LiteSpeed)
├── DEMARRER-BIZZOO.bat       # Windows : double-cliquer pour tout ouvrir en local
├── serve.ps1                 # Le serveur local que le .bat appelle (Windows)
└── tools/
    ├── assembler-site.sh     # Le site public, sur liste blanche — et le zip de l'hébergement
    ├── aligner-migrations.js # Recopie les fonctions de schema.sql dans les migrations
    ├── banc-*.mjs            # Les bancs du navigateur (Playwright) — dont envoi-unique, sms-ferme, stock et accueil-galerie
    ├── bizzoo-icone.png      # L'œuvre officielle, le B au chariot — source de toutes les icônes
    ├── eprouver-base.sh      # Force les portes de la base (PostgreSQL jetable)
    ├── illustrations-categories.py # Les illustrations des ronds de catégories
    ├── make-icons.js         # Icônes PWA + Android + notification (node tools/make-icons.js)
    ├── menage-stockage.ps1   # Supprime les fichiers orphelins du stockage
    └── servir.sh             # Ouvrir les deux applications en local (Linux, macOS)
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
  se corrige d'un geste depuis la fiche ou l'écran **Stock** — − / + /
  « En rupture » / « Sur commande » / « Arrive dans N jours ». La liste
  des produits affiche « Stock 12 », « Stock 0 » en rouge, « Sans
  stock » ou « Arrive dans 3 jours ». Chaque vente payée se décompte
  toute seule (section « Le stock suit les ventes »).
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
  Côté client, le nombre exact ne se montre qu'à cinq pièces ou moins
  (« Plus que 3 en stock » — il décide de l'achat), et le message
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
- Tri du catalogue client : rayons, sous-catégories et promotions sont
  classés **du prix le plus bas au plus élevé** (à prix égal, par ordre
  alphabétique). Les nouveautés restent classées par date et le slider
  garde l'ordre choisi par le gérant. La recherche, elle, classe par
  pertinence, et le prix ne départage qu'à pertinence égale.
- **Six onglets, dont deux qui n'existent que dans une boutique.**
  Accueil · Catégories · Produits · Recherche · Infos · Contact.
  - **Catégories** et **Produits** parlent d'**un** catalogue : ils
    n'ont rien à dire tant que le client n'est entré nulle part. Sur
    l'accueil BIZZOO ils sont **masqués** — il y choisit d'abord chez
    qui il va — et ils reparaissent dès qu'il est dans une boutique
    (`reglerOnglets`, `app.js`). En boutique unique il n'y a pas
    d'accueil d'enseigne : les deux sont alors toujours là. Un onglet
    reste visible quand c'est l'écran affiché — arrivé par un lien
    partagé, par exemple : une barre qui ne montre pas où l'on se
    trouve désoriente plus qu'elle n'allège.
  - **Catégories** montre les rayons de la boutique visitée, dans
    l'ordre choisi par son gérant. **La vue d'ensemble vit sur
    l'accueil BIZZOO** : « Tous les rayons » y liste **tous les rayons
    de toutes les boutiques ouvertes**, par ordre **alphabétique**,
    chacun avec **sa boutique** et **son nombre de produits**
    (`Catalogue.rayonsDeLEnseigne`). Les accents sont ignorés pour le
    classement : « Écrans » se range entre « Disques » et « Encre »,
    pas à la fin. Un rayon **vide** reste de la liste avec un 0 : le
    gérant l'a créé, il annonce ce qui vient. Toucher un rayon y entre
    directement — la boutique se règle en chemin, par le mécanisme des
    liens partagés. La ligne est écrite une seule fois
    (`UI.ligneRayon`) et sert aux deux écrans.
  - **Produits** montre tout le catalogue de la boutique visitée, du
    moins cher au plus cher. Ouvert par un lien direct avant tout choix
    de boutique, il montre toute l'enseigne — et chaque carte porte
    alors le nom de sa boutique, sans quoi le mélange ne voudrait rien
    dire.
  - **Contact** n'est pas un écran : il ouvre **WhatsApp** sur le
    numéro de **BIZZOO** — l'enseigne, jamais la boutique où l'on se
    trouvait par hasard (`Catalogue.enseigne`, distinct de
    `Catalogue.boutique`). Le lien est reposé à chaque écran, donc il
    suit une mise à jour des réglages sans rouvrir l'application ;
    **sans numéro renseigné, l'onglet se retire** et la barre se
    répartit d'elle-même sur ceux qui restent — d'où
    `grid-auto-columns` plutôt qu'un nombre de colonnes écrit en dur.
    Le libellé est « Contact » et non « Nous contacter » : à six
    onglets sur un téléphone, le mot long se ferait couper.
  - **Accueil ramène toujours en début de page.** Deux raisons de s'en
    occuper à la main : si l'on y est déjà, l'adresse ne change pas et
    rien ne se redessine ; et si l'on en revient, la position de
    lecture mémorisée reprendrait la main.
- **La publicité de BIZZOO**, sur l'accueil de l'enseigne, à l'endroit
  qu'occupaient les ventes flash. Des **affiches** — photos ou vidéos —
  et des **produits** pris dans n'importe quelle boutique. C'est une
  **troisième vitrine** dans la table `slides`
  (`portee = 'publicite'`), à côté du slider de l'enseigne et de celui
  d'une boutique : même gestionnaire, même stockage, même mécanique
  d'ordre et de masquage — rien de neuf à maintenir.
  **Réservée au superadministrateur** : la carte n'apparaît que dans
  Réglages → BIZZOO, et la règle RLS route `'enseigne'` **et**
  `'publicite'` vers `est_super()`. L'écran cache le bouton, la base
  ferme la porte.
  Côté client, une **rangée qui se pousse du doigt**, pas un second
  slider : celui du haut a déjà cette place, et deux choses qui
  défilent seules sur le même écran se disputent l'œil. Une vidéo se
  joue à la demande (`controls`) — plusieurs vidéos qui démarreraient
  ensemble feraient chauffer le téléphone — et, la vidéo ayant pris le
  geste, le lien vers le produit s'écrit alors en toutes lettres.
  Une annonce qui renvoie vers un **produit disparu** ou vers une
  **boutique fermée** s'efface d'elle-même : mieux vaut un écran plus
  court qu'une promesse qu'on ne peut pas tenir.
- **Les ventes flash appartiennent aux boutiques.** Elles ne remontent
  plus sur l'accueil BIZZOO : une vente flash est faite par une
  boutique, elle s'annonce sur son écran à elle
  (`Catalogue.ventesFlash`, sur la boutique visitée).
- **Le logo de la boutique accompagne son nom** en haut de son écran
  (`UI.vignetteBoutique`, posée par `entete({ vignette })`) : son image
  si elle en a une, sinon son icône sur sa couleur — exactement ce que
  montre sa carte sur l'accueil, pour qu'on la reconnaisse d'un écran à
  l'autre.
- **La recherche traverse toutes les boutiques ouvertes.** Le client
  cherche un produit ; il ne sait pas encore qui le vend. Trois règles
  (`Catalogue.rechercher`) :
  1. **quelques lettres suffisent** — « ordi » trouve « Ordinateur » ;
  2. **un seul des mots tapés suffit** — « ordinateur portable » sort
     aussi les ordinateurs de bureau, mais après les portables. Exiger
     tous les mots, comme avant, ne rendait plus rien dès qu'on en
     tapait un de trop ;
  3. on lit le **nom, la référence et la description** ; le rayon
     n'entre pas dans la recherche.
  Le classement rend la règle 2 supportable : le nom pèse plus que la
  référence, qui pèse plus que la description ; un mot en tête de nom
  pèse plus qu'un mot au milieu. Retrouver **tout** ce qui a été tapé
  agit comme un **multiplicateur**, jamais comme un bonus fixe — à plat,
  il faisait passer devant une sacoche dont la description contient
  « ordinateur » et « portable » un ordinateur qui porte le mot dans son
  nom. Une boutique **fermée** ne remonte rien.
  Chaque résultat porte le **nom de sa boutique** et son **prix dans la
  devise de celle-ci** (`Catalogue.deviseDe`) — deux boutiques peuvent
  compter autrement. L'ouvrir fait entrer dans sa boutique, par le même
  chemin qu'un lien partagé sur WhatsApp.
- **La charte graphique vient de l'icône.** Les couleurs des deux
  applications ont été relevées sur la première œuvre BIZZOO, le sac de
  courses — remplacé en 3.52.0 par le B au chariot, de la même famille
  de bleu et d'orange ; la charte, elle, n'a pas bougé :
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
- **Les icônes sortent de l'œuvre** (`tools/bizzoo-icone.png`, le B au
  chariot depuis 3.52.0). `node tools/make-icons.js` la sépare en deux
  calques — le dégradé mesuré, le motif démêlé — et en tire les 48
  fichiers (PWA et Android, toutes densités) et la silhouette des
  notifications : le détail est dans « La nouvelle icône » plus haut.
  L'icône adaptative est dans la **forme que les lanceurs attendent** :
  un **fond** (le dégradé) et le **motif au premier plan**. Elle a
  d'abord été faite à l'envers — tout le dessin dans le calque de fond,
  premier plan vide — et certains téléphones repeignaient alors la tuile
  à leur façon, le fond prenant la teinte du fond d'écran. Pas de calque
  `monochrome` : il ferait basculer les téléphones réglés en « icônes
  thématisées » vers une silhouette d'une seule couleur.
  **Un seul dessin sert partout** : `UI.marque()` affiche le fichier
  d'icône lui-même (`icons/icon-192.png`) au lieu d'un SVG approché —
  écran de connexion admin, vignette d'un produit sans photo, diapositive
  ou publicité sans image. Plus de version parallèle qui finirait par
  diverger, et le fichier est déjà gardé hors connexion par le service
  worker.
  L'**écran de démarrage** (`fond_demarrage`, la couleur affichée le temps
  que l'application s'ouvre) est passé du bleu au **blanc** : l'ouverture
  ne commence plus par un éclair bleu, et enchaîne sans rupture sur les
  écrans clairs de l'application. C'est une **couleur, et rien d'autre**.
  Y poser le logo par
  `<bitmap android:src="@mipmap/ic_launcher"/>` a fait **planter les deux
  applications au lancement** (3.9.2 et 3.9.3, corrigé en 3.9.4) :
  depuis Android 8 cette référence désigne le **XML d'une icône
  adaptative**, pas une image ; le fond de fenêtre ne sait pas la
  décoder, l'inflation du thème lève `Resources$NotFoundException` et
  l'application se referme dès le clic — sans rien afficher qui explique
  pourquoi. Le compilateur, lui, ne dit rien : la référence existe. Pour
  y remettre un logo un jour, il faudra un **vrai PNG** (`drawable/…png`
  dans un `<layer-list>`), jamais `@mipmap/ic_launcher`.
  L'application admin reçoit la **même** œuvre, marquée d'une pastille
  « réglages » : les deux applications vivent sur le même téléphone, on
  doit les distinguer d'un coup d'œil. Sous masque rond ou adaptatif, la
  pastille se fait plus petite et se pose à l'intérieur de la zone sûre —
  sinon le téléphone lui couperait la moitié.
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
  **Le journal est un député qu'il faut tenir.** `retour` dit *dans
  quelle table* écrire, et c'est le SuperAdministrateur qui clique :
  c'est donc **son** compte qui écrit. Or toute l'équipe alimente le
  journal — il le faut bien. Sans garde-fou, un modérateur y déposait
  une fausse ligne au libellé anodin dont l'annulation le nommait
  superadministrateur. Trois verrous ferment cela :
  1. `journal_verifie` (trigger) écrit `utilisateur` **d'après le
     jeton** : on ne signe plus du nom d'un autre, et il impose sa
     boutique à qui n'est pas superadministrateur ;
  2. `retour` ne peut viser que les tables du catalogue
     (`journal_tables_permises`). **`profils` n'y est acceptée que d'un
     superadministrateur** — d'un autre rang, elle serait un piège ;
  3. `journal_immuable` (trigger) : une ligne d'historique ne se
     réécrit pas, seule l'annulation s'y inscrit.
  `Store.TABLES_ANNULABLES` porte la même liste côté application : la
  base tranche, mais mieux vaut ne pas dépendre d'une seule barrière.
  **Chacun ne lit que sa boutique.** `journal.boutique_id` dit de qui
  parle une ligne ; l'administrateur des cosmétiques n'a pas à lire ce
  qui se passe en informatique — noms de produits, prix, mouvements de
  comptes. À `null`, la ligne parle de l'**enseigne** (réglages BIZZOO,
  publicité, comptes sans boutique) et ne se montre qu'au
  SuperAdministrateur. Les lignes écrites **avant** cette version n'ont
  pas de boutique : elles restent donc au SuperAdministrateur — on ne
  peut pas deviner après coup à laquelle elles appartenaient, et mieux
  vaut trop fermé que trop ouvert.
- **Ouvrir ou fermer une boutique appartient à l'enseigne.**
  L'administrateur règle la sienne — nom, coordonnées, marge, photos —
  mais ne touche ni à `actif` ni à `ordre`. RLS ne sait pas parler
  colonne par colonne : c'est le trigger `boutique_verrous` qui le dit,
  et l'écran des réglages ne renvoie plus ces deux colonnes du tout.
- **Le stockage suit les mêmes règles que les tables**, dossier par
  dossier (`peut_deposer`) : `enseigne/` — slider et publicité de
  BIZZOO — au SuperAdministrateur ; `slider/`, `boutique/` et
  `boutiques/` aux administrateurs ; le reste, les photos de produits, à
  toute l'équipe. Auparavant tout administrateur pouvait remplacer ou
  effacer les affiches de l'enseigne, alors que la table `slides` les
  lui refusait : la table disait une chose, les fichiers une autre. Le
  seau n'accepte par ailleurs **que des images et des vidéos**, 60 Mo au
  plus : il est public, et une page HTML déposée là serait servie depuis
  l'adresse du projet.
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
  d'itinéraire sous « À propos » de la fiche boutique. Le relevé de
  position demande la permission Android de localisation (application
  admin uniquement).
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
  arrive dans la carte « Nous contacter », sous « À propos » de la
  fiche boutique, à la suite du numéro et de l'adresse principaux.
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
- **Zoom sur la photo affichée** (les deux applications) : pincement à
  deux doigts jusqu'à 4×, double-tape pour aller et venir entre la vue
  d'ensemble et le détail, doigt pour promener la photo agrandie ;
  molette, double-clic, `+`/`−` et un bouton loupe pour la souris. Trois
  choix expliquent le code (`ui.js`, section « Visionneuse : zoom ») :
  1. le décalage est gardé **en pixels d'écran** (`translate(x,y)
     scale(z)` : la translation s'applique après l'agrandissement), pour
     ne pas avoir à raisonner dans deux repères à la fois ;
  2. agrandie, la photo prend la piste pour elle — classe `figee`,
     `overflow:hidden` et `touch-action:none` — sinon le même glissement
     voudrait dire deux choses : promener la photo, ou changer de photo.
     À 1× l'événement n'est pas intercepté et le défilement natif garde
     la main ;
  3. changer de photo **remet à 1×** : autrement la suivante s'ouvrirait
     déjà agrandie sur un coin que personne n'a choisi.
  Le pincement est intercepté (`touch-action:pan-x` sur la piste, puis
  `preventDefault`) : sans cela, `maximum-scale=5` laisserait le
  navigateur agrandir **toute la page** par-dessus. Les boutons de la
  visionneuse portent un `z-index` pour rester atteignables sous la photo
  agrandie, qui les recouvrirait sinon. La photo est retenue à ses bords
  (`retenirZoom`) : on ne peut pas la pousser hors du cadre.
- Réseaux sociaux : Facebook, Instagram, TikTok, YouTube et Snapchat
  (colonnes de `boutique`). Le gérant saisit un nom de compte ou un lien
  complet ; l'adresse finale est reconstruite (`Utils.lienReseau`) et
  affichée en aperçu dans l'admin. Côté client, carte « Suivez-nous »
  sous « À propos » de la fiche boutique, avec les couleurs de chaque
  marque — seuls les réseaux remplis apparaissent.
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
  dedans. **Catégories**, **Produits** et **Recherche** traversent
  toutes les boutiques ouvertes ; seules les **Promotions** entrent
  d'office dans la première boutique.
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
  boutique (`#/boutique/:id`) : son écran et ses infos ne parlent plus
  que d'elle, et un bandeau rappelle laquelle et ramène aux autres.
  Les onglets **Catégories**, **Produits** et **Recherche** font
  exception : ils traversent toutes les boutiques ouvertes, où qu'on se
  trouve.
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
- **Une boutique ne change pas seule ce qui la représente.** Six choses
  demandent l'accord de l'enseigne : le **nom**, le **logo**, la
  **description**, l'**adresse** (et le point sur la carte), les
  **contacts** (téléphone, WhatsApp, indicatif, autres numéros et autres
  adresses), et l'**ajout ou la modification d'un écran du slider**.
  L'administrateur remplit son écran comme avant et enregistre ; au lieu
  d'être écrit, le changement part en **demande** (`public.demandes`).
  Le SuperAdministrateur la voit dans **BIZZOO Admin → Validations**,
  avec l'ancien et le nouveau côte à côte — approuver sans voir ce qui
  change reviendrait à signer sans lire — et il approuve ou refuse avec
  un motif.
  Ce qui reste à la boutique, sans rien demander : slogan, secteur,
  icône, couleur, horaires, devise, marge, photos, vidéo, réseaux
  sociaux, l'ordre et l'extinction de ses écrans de slider — et tout son
  catalogue, produits, rayons, stocks et prix compris.
  **Le verrou est dans la base, pas à l'écran.** `boutique_verrous` et
  `slide_verrous` (triggers) refusent l'écriture de ces colonnes à qui
  n'est pas superadministrateur : même en appelant la base directement,
  la validation ne se contourne pas. C'est ce qui distingue une
  validation d'une politesse. L'application, elle, se contente de
  choisir le bon chemin pour éviter à l'administrateur une erreur qu'il
  ne comprendrait pas.
  L'**application** d'une demande approuvée passe par
  `approuver_demande()` — `security definer`, qui vérifie qui appelle et
  n'écrit **que les colonnes prévues, nommées une par une**. Rien de
  dynamique, rien qui se déduise du contenu de la demande : c'est la
  leçon du piège du journal, tirée une fois pour toutes.
  Un logo refusé laisse son fichier dans le stockage — orphelin, sans
  conséquence : mieux vaut un fichier de trop qu'une image manquante si
  la demande est finalement approuvée.
