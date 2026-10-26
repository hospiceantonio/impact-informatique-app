# BIZZOO — Applications mobiles

Deux applications Android et iOS pour l'enseigne **BIZZOO**, reliées à une base
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

Les variantes Google Play utilisent une signature privée distincte et
produisent des AAB avec `python3 tools/construire-play.py`. Le projet iOS
est défini dans `ios/project.yml` ; `python3 tools/preparer-ios.py` copie
les deux applications web dans les ressources natives avant la génération
du projet Xcode. Les certificats et profils de distribution restent hors
du dépôt.

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
| Bleu | `#2550B7` — celui de l'icône, depuis la 3.53.0 (voir « Le bleu de l'icône ») |
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

**Le logo : le B au chariot, puis le nom (depuis la 3.56.1).** La tuile
du B est une image, `icons/logo-bizzoo.png`, tirée de l'œuvre comme les
icônes. Le nom, lui, reste écrit par la feuille de style (`motSymbole()`
dans `ui.js`) : « Bizz » en bleu, « oo » en orange. Il reste net à toutes
les tailles, suit la couleur du thème et ne coûte aucun fichier. Les deux
points qu'il portait dessous sont partis : les deux roues orange du B
les portent. Voir « Le logo partout, et des captures à jour ».

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

Cinquante-six constats sur les deux applications et le site, à quatre
largeurs d'écran (360, 390, 768, 1440 px). Ils regardent ce qu'une capture
d'écran ne montre pas :

- la police **affichée** est Poppins (`document.fonts.check`) — une
  `@font-face` qui échoue ne laisse aucune trace, le navigateur retombe
  sur la police du système et la page reste belle ;
- rien n'est demandé hors de l'application ;
- les couleurs sont relevées **sur les éléments**, pas dans la feuille de
  style — une règle peut être écrite et surchargée dix lignes plus bas ;
- la gamme de bleus est **la même partout** — les deux applications, la
  page d'entrée du site, sa page 404, la couleur de barre du navigateur
  et le manifeste — et **aucune règle n'a gardé l'ancien bleu** en dur
  (une ombre en `rgba(…)` ne suit pas les jetons) ;
- les cartes-liens de l'accueil admin **enveloppent leur titre** ;
- rien ne déborde en largeur, à aucune des quatre largeurs.

Quatre sabotages les font tomber, onze constats en tout : renvoyer la
police chez Google, remettre l'ancien bleu, repasser les boutons de la
barre en blanc, retirer la bascule de l'écran d'ordinateur. Huit autres
depuis la 3.53.0 : une ombre du client, une nuance de l'admin, la
couleur de barre et le manifeste du client, une nuance et une ombre de
la page d'entrée, la page 404 revenus à l'ancien bleu — et la règle qui
fait des cartes-liens des blocs, retirée.

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

> **Elle a changé depuis** : la barre a deux visages, celui de BIZZOO et
> celui d'une boutique, la recherche est redevenue un onglet et le compte
> est monté dans la barre du haut — voir « La barre du bas à deux
> visages » plus bas. Ce qui suit est la barre de la DA d'origine.

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

Panier, paiement et confirmation n'ont pas de barre d'onglets, comme
sur la DA : on y avance, on n'y navigue pas. (La fiche boutique et la
fiche produit en ont eu aucune, elles aussi, avant de prendre la barre
de la boutique.) L'action qui fait avancer est **fixée en bas** de
l'écran :

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

### Il ne voit qu'un montant : ce qu'il encaisse

Ni le prix payé, ni le prix BIZZOO, ni la marge, ni l'acompte. Depuis
l'acompte à la commande (3.57.0), un seul chiffre lui parvient : **ce
qu'il doit encaisser à la livraison**, la part du reste qui revient à
sa boutique (`a_encaisser`). Ce n'est pas une politesse d'affichage :
`mes_livraisons()` **ne rend aucune autre colonne d'argent**.

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

La liste est désormais celle de **BIZZOO** : trente secteurs rangés par
thème, et leurs rayons, écrits par le **superadministrateur seul** (voir
« La liste rangée », plus bas).

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
attendent derrière « Voir toutes les catégories ». Trente lignes sur un
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

## Les icônes des catégories (3.56)

L'enseigne a choisi trois planches d'icônes — trait bleu nuit, une
touche orange — et demandé **exactement celles-là**, attribuées aux
catégories :

- la première, douze icônes sur des carrés bleu-gris
  ([`docs/icones-categories-source.webp`](docs/icones-categories-source.webp)) :
  Alimentation, Restauration, Mode, Beauté, Téléphones, Informatique,
  Électroménager, Maison & Déco, Auto & Moto, Santé, Immobilier,
  Services ;
- les deux suivantes, vingt-deux icônes sur des carrés blancs
  ([`-2.jpg`](docs/icones-categories-source-2.jpg),
  [`-3.jpg`](docs/icones-categories-source-3.jpg)) : Bébé & Enfants,
  Sport & Loisirs, Bijoux & Accessoires, Livres & Fournitures scolaires,
  Bricolage & Matériaux, Animaux, Agriculture & Élevage, Cadeaux & Fêtes,
  Équipements de bureau, Grossistes & Fournisseurs, Énergie solaire &
  Électricité, Sécurité & Surveillance, Musique & Instruments,
  Artisanat & Produits locaux, Jardinage & Espaces verts, Imprimerie &
  Communication, Événementiel & Décoration, Matériel professionnel,
  Transport & Location, Formation & Cours — plus un tracteur et des
  cartons, variantes d'Agriculture et de Grossistes.

Ce sont elles, **telles quelles** : chacune est découpée dans sa
planche, sans le nom écrit dessous, et le fond de sa tuile est rendu
transparent. Rien n'y est redessiné ni recoloré — le bleu nuit des
planches blanches est un peu plus sombre, leur orange un peu plus
jaune, et ce sont les leurs. Les quatre icônes construites un temps
dans le style de la première planche (Bébé, Sport, Livres, Animaux)
cèdent la place à celles des planches.

Les planches n'ont pas la même échelle : les icônes des planches
blanches sont ramenées à la taille médiane des douze premières, et
toutes se posent sur le même carré. Les douze premières restent
identiques au pixel près ; le trait des vingt-deux autres est plus fin,
comme sur leurs planches.

### Sur l'écran

- **L'accueil** : les huit catégories en tuiles, comme sur les
  planches — le carré bleu-gris, l'icône, le nom dessous, dans la
  tuile. Le nom tient sur deux lignes au plus (« Électro- / ménagers ») ;
  un seul mot trop long pour la tuile finit par « … » au lieu d'être
  coupé net.
- **L'écran « Catégories »** : la même tuile, en petit, devant chaque
  nom.
- **L'admin** : la même pastille dans la liste ; dans la fiche
  (Catégories → Modifier), le choix de l'**icône** montre les
  trente-quatre sur leur tuile, dans l'ordre des catégories et sous les
  noms des planches. Une même icône peut servir à plusieurs catégories.

La couleur de chaque catégorie ne se choisit plus : toutes les tuiles
ont le même fond. La base garde la couleur de chacune, parce que les
applications d'avant s'en servent encore.

### La liste rangée

Les nouvelles planches apportaient leurs catégories. Rapprochées de
celles qui existaient, elles donnent une liste de **trente**, rangée par
thème ([`categories-rangement.sql`](supabase/categories-rangement.sql),
à appliquer sur la base en ligne — voir plus bas) :

| # | Catégorie | Icône | Accueil |
|---|-----------|-------|---------|
| 1 | Informatique & Électronique | Informatique | ✔ |
| 2 | Logiciels & Solutions pro | Informatique | ✔ |
| 3 | Électro-ménagers & Cuisinière | Électroménager | ✔ |
| 4 | Énergie solaire & Électricité *(nouvelle)* | Énergie solaire & Électricité | |
| 5 | Sécurité & Surveillance *(nouvelle)* | Sécurité & Surveillance | |
| 6 | Bébé & Enfants | Bébé & Enfants | ✔ |
| 7 | Livres & Fournitures scolaires | Livres & Fournitures scolaires | ✔ |
| 8 | Formation & Cours *(nouvelle)* | Formation & Cours | |
| 9 | Maison & Déco | Maison & Déco | ✔ |
| 10 | Jardinage & Espaces verts *(nouvelle)* | Jardinage & Espaces verts | |
| 11 | Bricolage & Matériaux | Bricolage & Matériaux | ✔ |
| 12 | Auto & Moto | Auto & Moto | ✔ |
| 13 | Transport & Location *(nouvelle)* | Transport & Location | |
| 14 | Mode & Vêtements | Mode | |
| 15 | Bijoux & Accessoires | Bijoux & Accessoires | |
| 16 | Beauté & Bien-être | Beauté | |
| 17 | Supermarché & Épicerie | Alimentation | |
| 18 | Restauration | Restauration | |
| 19 | Agriculture & Élevage *(nouvelle)* | Agriculture & Élevage (feuille et épi) | |
| 20 | Animaux | Animaux | |
| 21 | Sport & Loisirs | Sport & Loisirs | |
| 22 | Musique & Instruments *(nouvelle)* | Musique & Instruments | |
| 23 | Artisanat & Produits locaux *(nouvelle)* | Artisanat & Produits locaux | |
| 24 | Cadeaux & Fêtes *(nouvelle)* | Cadeaux & Fêtes | |
| 25 | Événementiel & Décoration *(nouvelle)* | Événementiel & Décoration | |
| 26 | Équipements de bureau *(nouvelle)* | Équipements de bureau | |
| 27 | Matériel professionnel *(nouvelle)* | Matériel professionnel | |
| 28 | Imprimerie & Communication *(nouvelle)* | Imprimerie & Communication | |
| 29 | Grossistes & Fournisseurs *(nouvelle)* | Grossistes & Fournisseurs | |
| 30 | Services & Prestataires | Services | |

Ce que le rangement a changé :

- **quatorze catégories nouvelles**, avec quelques rayons de départ
  chacune, que l'enseigne retouche dans l'admin ;
- **les noms des planches** pour celles qui existaient : « Bébé &
  Enfants », « Livres & Fournitures scolaires », « Bricolage &
  Matériaux » (c'était « Btp et matériaux. ») ; et ceux qu'imposait le
  rangement : « Maison & Déco » (le jardinage a sa catégorie),
  « Restauration » (l'alimentation, c'est le supermarché),
  « Informatique & Électronique » (le « & » de toutes). « Électro-ménagers
  & Cuisinière », nommée par l'enseigne, garde son nom ;
- **des rayons vides déménagent**, pour qu'un même rayon ne soit pas à
  deux endroits : Électricité (de Bricolage vers Énergie solaire),
  Formations (de Livres vers Formation & Cours), Jardinage (de Maison
  vers Jardinage & Espaces verts), Épicerie et Produits frais (de
  Restauration vers le supermarché) ;
- **« Prestataires de services » rejoint « Services »**, qui devient
  « Services & Prestataires » : ses rayons (Électricien, Informaticien,
  Vitrier, Plombier) y passent, et son « Informaticien » remplace
  « Informatique » ;
- **Bijoux & Accessoires et Bricolage & Matériaux** ont leur icône à
  elles : elles portaient celles de Mode et d'Immobilier ;
- **l'ordre par thème** : high-tech, enfants et école, maison,
  mobilité, mode, alimentation, loisirs, professionnels, services. Les
  huit de l'accueil restent les mêmes ; les flèches de la liste, dans
  l'admin, changent l'ordre si l'enseigne en préfère un autre.

Rien ne s'y perd : un rayon qui a des produits ne déménage pas, une
catégorie qui a des produits ou des boutiques ne s'efface pas, aucun
produit ne change de rayon. Un nom ou une icône que l'enseigne avait
déjà changés ne sont pas touchés. Le fichier ne joue **qu'une fois** :
dès que l'une des quatorze existe, il ne fait plus rien — le rejouer ne
défait jamais un nom, un ordre ou une suppression décidés depuis dans
l'admin. Une base neuve naît déjà rangée : `schema.sql` sème les
vingt-neuf (toutes sauf « Électro-ménagers & Cuisinière », créée depuis
l'admin) et leurs cent vingt-trois rayons.

Téléphones, Santé et Immobilier ne servent encore à aucune catégorie ;
elles restent dans le choix de la fiche, avec le tracteur et les
cartons, pour celles qui viendront.

[`tests/99s-categories-rangement.sql`](supabase/tests/99s-categories-rangement.sql)
éprouve le rangement en 38 constats. Il refait la base en ligne
d'avant — ses dix-sept catégories, dont les deux créées depuis l'admin,
ses noms, ses illustrations, son ordre, ses huit de l'accueil — et lui
colle `categories-rangement.sql` : elle arrive exactement à la liste de
`schema.sql` (les quatorze, leurs rayons, les noms, les icônes,
l'ordre), sans qu'aucun produit change de rayon ni aucune boutique de
secteur. Rejoué après des retouches dans l'admin, le fichier ne fait
rien. Une seconde fois, avec un nom déjà changé par l'enseigne, un
produit dans un rayon qui devait déménager et une boutique rangée dans
« Prestataires » : le nom reste, le rayon reste, « Prestataires » ne
s'efface pas. Deux sabotages font tomber chacun un constat : laisser
déménager un rayon qui a des produits, laisser le fichier rejouer.

### Sans gêner les applications déjà installées

Les icônes sont des images de l'application (`img/pictos/`, dans le
client et dans l'admin, dans la coquille hors connexion) ; la colonne
`icone` de la base dit laquelle. Changer cette colonne ne se voit pas
dans les applications 3.54 et 3.55 : elles posent leur illustration en
3D **par-dessus** l'icône. La base garde donc ces illustrations
(`image = 'img/categories/…'`) — et les applications 3.56 **ne lisent
plus ces chemins** : elles montrent l'icône. Personne ne voit sa tuile
se vider le jour de la mise à jour.

Les catégories nouvelles, elles, n'existaient pas pour ces
applications. Sept reçoivent l'illustration d'avant qui dit la même
chose : le panier tressé (Artisanat), la plante en pot (Jardinage,
Agriculture), la mallette (Bureau), les outils (Matériel
professionnel), la moto (Transport), les livres (Formation). Trois ont
une clé que l'application cliente d'avant sait dessiner d'un trait
(`energie`, `cadeau`, `imprimante`). Sécurité, Musique, Événementiel et
Grossistes n'ont ni l'un ni l'autre : dans une application 3.54 ou
3.55, leur pastille reste une pastille de couleur, sans dessin, jusqu'à
la mise à jour.

La fiche de l'admin ne réécrit la photo **que si on l'a touchée** :
renommer une catégorie ou changer son icône laisse l'illustration
d'avant en place pour les applications installées. Une vraie photo,
elle, recouvre l'icône partout.

Une icône qui ne fait pas partie des trente-quatre — choisie avec une
admin d'avant — garde son dessin d'un trait, en bleu nuit ; une icône
inconnue retombe sur celle des rayons. Jamais une tuile vide.

À coller dans Supabase, dans l'ordre :
[`categories-icones.sql`](supabase/categories-icones.sql) (déjà
appliqué sur la base en ligne), puis
[`categories-rangement.sql`](supabase/categories-rangement.sql) (pas
encore : il attend l'accord de l'enseigne, parce qu'il efface
« Prestataires de services » une fois ses rayons déplacés). Le premier
ne touche qu'une catégorie qui a **encore son ancienne icône** ; le
second ne joue qu'une fois. Rejoués, ni l'un ni l'autre ne défait un
choix fait depuis dans l'admin, et aucun ne touche à l'image d'une
catégorie qui existait.

### Refaire les icônes

```bash
python3 tools/icones-categories.py
```

Il découpe les trente-quatre dans les trois planches de `docs/` et les
pose dans les deux applications. Refaites ainsi, elles sont identiques,
octet pour octet, à celles du dépôt.

## La photo d'une catégorie

Sur la DA, les catégories de l'accueil portaient une **photo**. Chaque
catégorie peut en recevoir une, **facultative**, que le
superadministrateur pose dans l'application admin :
**Catégories → Modifier → Photo de la tuile (facultative)**. Depuis la
3.56, elle prend la place de l'icône — sur l'accueil, sur l'écran
« Catégories » et dans la liste de l'admin.

### Les illustrations en 3D d'avant (jusqu'à la 3.55)

De la 3.47 à la 3.55, chaque catégorie portait d'office une
**illustration** : un objet en 3D (Fluent Emoji de Microsoft, licence
MIT) sur le fond pastel de sa couleur, embarqué dans les deux
applications (`img/categories/`). Depuis la 3.56, ce sont les icônes de
l'enseigne (voir plus haut) : les illustrations ne voyagent plus avec
les applications, et `categories-photos.sql` n'en pose plus. Seules
sept catégories nouvelles en reçoivent une, de `categories-rangement.sql`,
pour les applications installées.

La base en ligne **garde leurs chemins** (`img/categories/robe.jpg`…) :
les applications 3.54 et 3.55 déjà installées les montrent encore. Les
applications 3.56 ne lisent plus ces chemins, et la fiche de l'admin ne
les efface pas en passant.

### Poser, remplacer, retirer

- **Mettre une photo** : le carré « Ajouter » de la fiche. L'aperçu a
  les **coins arrondis** de la tuile : on voit tout de suite ce que les
  coins perdront. Une photo carrée, le sujet au centre, convient le mieux.
- **Remplacer** : la croix, puis « Ajouter ».
- **Retirer** : la croix, puis « Enregistrer ». La tuile retrouve son
  icône.

L'application **réduit la photo à 480 px** et l'enregistre en JPEG avant
de l'envoyer — une photo de téléphone de plusieurs Mo n'en garde que
quelques dizaines de Ko : la plus grande tuile n'a pas besoin de plus,
même sur l'écran le plus fin.

### L'icône en secours

La photo se pose **par-dessus l'icône**, qui reste dessous. Tant qu'elle
charge, on voit l'icône ; si elle ne vient pas — hors connexion, sur un
téléphone qui ne l'a jamais vue, ou fichier retiré du stockage —, elle
**s'efface** et l'icône reste. Jamais un carré d'image cassée à l'accueil.
Une seule écoute par application, posée une fois pour tous les écrans
(`data-secours`), sans attribut `onerror` dans le HTML. L'icône est une
image elle aussi : seule la photo porte `data-secours`.

### Ce que la base garde

- **Un chemin, jamais une adresse**, dans l'un de deux dossiers :
  `enseigne/categories/` (une photo, dans le seau) ou `img/categories/`
  (une illustration d'avant la 3.56, gardée pour les applications
  installées). La règle `categories_image_chemin` refuse tout le reste —
  une adresse internet, un autre dossier, un `..`, un fichier caché —
  même au superadministrateur : ce n'est pas une question de droit,
  c'est la forme de la donnée. Une adresse libre ferait charger à
  l'accueil de tous les clients une image posée n'importe où.
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
(déjà appliqué sur la base en ligne).

### Le banc

[`tests/99o-categories-photos.sql`](supabase/tests/99o-categories-photos.sql)
force les portes en 39 constats — dont l'état des lieux du stockage
**tel qu'il part chez le gérant**, lu dans le dépôt : c'est sa liste
d'orphelins qu'on éprouve, pas une copie. Il lit aussi les deux dossiers
d'icônes sur le disque : chacune de celles que la base désigne doit y
être, dans le client **et** dans l'admin, et les deux dossiers doivent
coïncider. Il refait la base en ligne d'avant la 3.56 — icônes d'un
trait, illustrations par-dessus — et lui recolle
`categories-icones.sql` : chacune reçoit la sienne, l'illustration reste,
et rejoué, le fichier ne défait pas un choix fait dans l'admin.

[`tools/banc-categories-photos.mjs`](tools/banc-categories-photos.mjs) en
ajoute 128 au navigateur, dans les deux applications : les trente-quatre
icônes identiques, octet pour octet, et connues des trois codes qui les
nomment ; « cadeau », qui est aussi le nom d'un dessin d'un trait
d'avant, montre celle de la planche ; chaque tuile montre l'icône que la base lui donne, lue à côté
de la page ; la photo la recouvre (mesuré) et l'icône revient quand la
photo manque ; une illustration d'avant n'est même pas demandée ; une
icône d'avant garde son trait, une inconnue retombe sur celle des
rayons ; rien ne déborde à 320 px, le chemin est échappé ; dans l'admin,
le choix des trente-quatre, dans l'ordre des catégories, et ce qui part
au stockage et vers la base, corps compris — ni couleur ni photo
réécrites sans raison.

Trois sabotages, un par un, et chacun fait tomber au moins un constat :
relire les illustrations d'avant chez le client (elles sont demandées
au réseau), faire réécrire la photo à chaque enregistrement de la fiche
(l'illustration des applications installées serait effacée), retirer le
secours d'une icône inconnue (la tuile resterait vide).

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
| Les chiffres | rien encore — voir « Il entrait en base, pas dans l'application » | éteint |

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

### Il entrait en base, pas dans l'application (3.55.0)

Le gérant passait un compte en « administrateur de BIZZOO »… et ce
compte s'arrêtait sur **« Boutique à confier »**, sans rien à toucher.
La base était prête — `peut_agir_sur()` lui répond oui partout — mais
l'application admin, plus ancienne que les comptes d'enseigne, ne le
laissait pas entrer : au démarrage, seul le superadministrateur
recevait une boutique à ouvrir, et la porte arrêtait tout compte sans
boutique ouverte. Le banc de la base était vert : il éprouvait la base,
pas la porte.

Désormais :

- **il entre sur une boutique** — la dernière qu'il a ouverte, sinon la
  première — et en change depuis la carte « Boutique ouverte » de
  l'accueil, comme le superadministrateur. Il crée un produit dans la
  boutique de son choix. Créer, renommer, ranger ou supprimer une
  boutique reste au superadministrateur ;
- **ses interrupteurs décident de l'écran**, comme ils décident en base :

| interrupteur | à l'écran |
| --- | --- |
| Les commandes | l'icône et l'écran des commandes |
| Le catalogue | retoucher les produits (déjà en place) |
| Les boutiques | Réglages et slider de la boutique ouverte — ce que `administre()` lui ouvre ; sans lui, « Mon compte » remplace « Réglages » |
| Les chiffres | rien encore : voir plus bas |

- **ni historique, ni comptes, ni chiffres** : la base ne lui en rend
  rien. Le journal et les comptes ne lui montrent que des lignes de
  boutique, ou sa propre fiche ; `statistiques_ventes()` est au
  superadministrateur, et `statistiques_boutique()` part de la boutique
  du compte. Ces écrans le renvoient à l'accueil en disant pourquoi,
  plutôt que de lui montrer des pages vides qu'il prendrait pour une
  panne ;
- **« Mon compte » dit ce qu'il est** : « Administrateur de BIZZOO —
  toutes les boutiques · commandes, catalogue ».

**Le livreur de BIZZOO était arrêté par la même porte** : aucune
boutique, et il n'en ouvre pas. Il va maintenant droit à ses courses.

**La porte ne regarde plus que les comptes de boutique** dont la
boutique n'existe plus. Son second conseil — « exécuter le dernier
fichier SQL pour monter en super administrateur » — est retiré : depuis
la garde `rattraper_anciens_admins()`, ce fichier ne promeut plus
personne dès qu'un superadministrateur existe. Le conseil menait à une
impasse.

**L'interrupteur « Les chiffres » n'ouvre encore rien.**
`peut_voir_finances()` existe en base, mais aucune règle ne l'appelle :
le journal des versements et les statistiques de l'enseigne restent au
superadministrateur. L'allumer ne change donc rien. Le brancher est une
décision à prendre d'abord : il montrerait les marges et les bénéfices
de toutes les boutiques.

[`tools/banc-compte-enseigne.mjs`](tools/banc-compte-enseigne.mjs) ouvre
l'application avec chacun des comptes — administrateur et modérateur de
BIZZOO, livreur de BIZZOO, compte dont la boutique a disparu, modérateur
de boutique, superadministrateur : 49 constats. Quatre sabotages
tombent, dont la panne d'origine : réserver de nouveau le départ au
superadministrateur remet « Boutique à confier ».

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

**Un montant n'y entre que s'il regarde son destinataire.** Depuis
l'acompte (3.57.0), le client lit ce qui lui reste à payer à la
livraison, chaque boutique ce qu'elle encaissera, le superadministrateur
l'acompte reçu et le reste. Le livreur, lui, n'en reçoit aucun : la
règle des prix fermés au livreur ne servirait à rien si le texte d'une
notification les recopiait.

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
  référence et le prix, et calcule le total — puis l'acompte (3.57.0).
  C'est cet acompte-là qui part chez l'agrégateur.
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

## Le paiement qui n'aboutit pas (3.56.1)

Après un paiement Mobile Money refusé, le reçu répétait en boucle
« Validez la demande sur votre téléphone, avec votre code Mobile Money.
Nous allons ensuite demander à FeexPay si le versement a abouti. Ne
payez pas une seconde fois. » — et l'on ne pouvait plus quitter l'écran.
Quatre causes, que le navigateur a d'abord reproduites :

- **Le refus n'était pas lu.** FeexPay répondait FAILED, notre fonction
  `feexpay` le disait (`echoue`), mais l'application ne regardait pas sa
  réponse : le sablier tournait une minute et demie, puis annonçait
  « vous n'avez rien à refaire » à un client qui n'avait rien payé — et
  tout recommençait à chaque réouverture du reçu.
- **Le reçu retenait le client.** L'application dessine ses écrans un
  par un, et le reçu ne rendait la main qu'au bout de son attente :
  pendant une minute et demie, le retour, « Mes commandes » ou l'accueil
  restaient sans effet.
- **Le sablier tournait aussi là où plus rien n'arrivera** : sur une
  commande « Paiement non abouti » ou annulée, sans aucun moyen de
  l'arrêter.
- **Le retour arrière tournait en rond.** Après l'achat, revenir en
  arrière depuis le panier ramenait au formulaire de commande, qui, le
  panier vidé, renvoyait au panier : le bouton retour du téléphone
  passait de l'un à l'autre sans jamais sortir.

### Une carte qui laisse la main

Le message devient une carte, sous l'en-tête du reçu, qui a toujours un
bouton pour en sortir :

| Ce qui se passe | Ce que dit la carte | Ses boutons |
|---|---|---|
| On attend la confirmation | le sablier, « Validez la demande… Ne payez pas une seconde fois. » | **Arrêter l'attente** |
| L'attente est arrêtée, ou a duré une minute et demie | plus de sablier : si le client a validé et a été débité, la boutique recevra sa commande dès que FeexPay aura confirmé — rien à refaire, garder le numéro BZ-… | **Vérifier à nouveau**, **Fermer** |
| FeexPay a refusé le versement | sa raison (« rien n'a été débité »), puis l'opérateur et le numéro qui paie | **Réessayer le paiement**, **Fermer** |
| Aucune demande n'est partie pour cette commande | « rien n'est parti sur votre téléphone », l'opérateur et le numéro | **Payer maintenant**, **Fermer** |

- **Arrêter l'attente** cesse d'interroger FeexPay ; **Fermer** retire
  la carte ; **Vérifier à nouveau** relance l'attente.
- **L'attente ne retient plus l'écran.** Elle part à côté, et quitter le
  reçu l'arrête : « Mes commandes », l'accueil et le retour répondent
  aussitôt.
- **Rouvrir le reçu d'un versement refusé le dit tout de suite** : avec
  FeexPay, la première vérification part sans attendre.
- **Une commande « Paiement non abouti » ou annulée n'a plus de carte.**
- **Le retour arrière sort.** Les renvois vers le panier et vers le reçu
  remplacent l'écran précédent dans l'historique (`location.replace`) :
  depuis le reçu, retour mène au panier, puis à l'accueil.

**Réessayer ne vient qu'après un verdict** de FeexPay : un refus, ou
aucune demande ouverte. Pendant l'attente, une seconde demande ferait
sonner le téléphone deux fois, et le client pourrait payer deux fois —
c'est pour cela que le sablier dit « Ne payez pas une seconde fois », et
qu'il n'a pas ce bouton. La nouvelle demande porte sur **la même
commande**, avec l'opérateur et le numéro choisis ; notre fonction
refuse toujours une commande qui n'est plus à payer, et une seconde
demande moins de trente secondes après la précédente.

**L'argent, lui, ne dépend toujours pas du téléphone.** « Arrêter » ou
« Fermer » ne touchent pas à la commande : elle reste « à payer », et si
le versement aboutit malgré tout, la notification de FeexPay la fait
passer à « payée » (voir « La notification de FeexPay n'est pas
signée »). L'application ne conclut rien ; elle cesse seulement
d'attendre devant le client.

[`tools/banc-paiement-echoue.mjs`](tools/banc-paiement-echoue.mjs)
rejoue tout cela au navigateur, FeexPay et la base simulés, en 40
constats : le refus arrête l'attente en moins de quatre secondes, après
une seule question à FeexPay ; « Fermer » ; « Réessayer », qui repart
sur la même commande avec l'opérateur et le numéro choisis, jusqu'à
« Commande confirmée » quand la base le dit ; « Arrêter l'attente » et
« Vérifier à nouveau » ; « Mes commandes » affiché en moins d'une
seconde quand on quitte le reçu, et l'attente arrêtée avec lui ;
« Payer maintenant » sans demande en cours ; aucune carte sur
une commande non aboutie ou annulée ; le retour arrière après un achat,
et depuis le formulaire ouvert panier vide. Quatre sabotages le font
tomber : ignorer le refus, laisser le reçu attendre la fin de l'attente,
renvoyer au panier ou au reçu sans remplacer l'entrée d'historique.

## L'acompte à la commande (3.57.0)

Pour écarter les commandes fictives, le client paie en ligne **une part
du total — l'acompte —** pour que sa commande parte ; **le reste se paie
à la livraison**. Le taux est au superadministrateur : **Réglages →
BIZZOO → Paiement en ligne → « Acompte à la commande »**, de 1 à 100 %.
Il part à 10 % ; 100 % revient à tout faire payer en ligne, comme avant.

### Ce que fait la base

- **Le taux** vit dans `paiement.taux_acompte`, borné de 1 à 100, et
  seul le superadministrateur l'écrit — la même règle que le choix de
  l'agrégateur.
- **La base calcule l'acompte, jamais le téléphone.**
  `creer_commande(client, articles, code, avec_acompte)` le fixe
  *après* le code promo : le taux du jour sur le total remise déduite,
  au franc supérieur, **100 FCFA au moins** (le minimum de FeexPay),
  jamais plus que le total. Il est figé sur la commande
  (`taux_acompte`, `acompte`) : changer le taux ne réécrit pas les
  commandes passées. Personne ne le réécrit ensuite — pas même le
  superadministrateur, que `commande_verrous` arrête comme pour le total.
- **L'agrégateur ne demande que l'acompte.** `commande_pour_paiement`
  le rend sous `total` : la fonction Edge `feexpay` déployée demande ce
  champ-là, et **n'a pas eu à changer**. KkiaPay reçoit l'acompte de
  l'application ; dans les deux cas, `marquer_payee` le vérifie, et un
  versement plus petit reste « incomplet ». Ce qui est réellement entré
  se garde dans `verse`. Le journal des versements attend l'acompte, et
  écrit « Acompte encaissé ».
- **La commande part dès l'acompte reçu** : elle passe à « payée », les
  boutiques sont prévenues et le stock décompté, comme avant.
- **Le reste se partage entre les boutiques** (`restes_par_boutique`).
  Une commande qui traverse deux boutiques est livrée en deux fois, et
  chacune encaisse sa part ; la somme des parts tombe juste au franc près
  (l'arrondi va à la plus grosse). **Un article annulé ne se paie pas** :
  le client ne doit plus que ce qu'il recevra, remise comprise au
  prorata, moins ce qu'il a versé ; une boutique dont tout est annulé n'a
  rien à encaisser.
- **À chacun ce qui le regarde.** `commandes?select=*,restes` — une
  fonction que PostgREST lit comme une colonne — rend toutes les parts au
  client et à l'enseigne, sa part à une boutique, rien aux autres ; elle
  relit la commande par son identifiant, si bien qu'une ligne fabriquée
  n'y change rien. Le livreur lit `a_encaisser` dans `mes_livraisons()`,
  et rien d'autre.
- **Les notifications le disent** : « Acompte reçu » et le reste au
  client ; à chaque boutique, ce qu'elle encaissera ; au
  superadministrateur, l'acompte encaissé et le reste. Une commande
  réglée en entier garde les mots d'avant.
- **L'enseigne qui confirme à la main** (`confirmer_paiement`) se porte
  garante de l'acompte, pas du total.

### Ce que voient les écrans

| Où | Ce qui s'affiche |
|---|---|
| Le panier | sous le total : « À payer à la commande — acompte de 10 % » et « À payer à la livraison » |
| Le formulaire de commande | « Total de la commande », « À payer maintenant », « Reste à payer à la livraison » — code promo compris — et le bouton **Payer l'acompte · 30 000 FCFA** |
| Le reçu | « Acompte à payer », puis, payée : le badge « Acompte payé », « Acompte reçu. », le reste sous la coche, et pour chaque boutique ce qu'on lui donnera |
| Le message WhatsApp à une boutique | « Acompte payé en ligne. Reste à payer à la livraison : … » — sa part seulement |
| « Mes commandes » | « Acompte payé », et « reste … à la livraison » tant que la livraison n'a pas eu lieu |
| Admin — Réglages (superadministrateur) | le champ « Acompte à la commande (%) », refusé hors de 1 à 100 |
| Admin — Commandes | « Acompte payé en ligne (10 %) » et « À encaisser à la livraison » : sa part pour une boutique, tout le reste pour l'enseigne ; la feuille « Confier » dit au livreur ce qu'il encaissera |
| Admin — Mes courses (livreur) | « À encaisser : … », « Rien à encaisser : tout est payé », ou « Encaissé à la livraison » une fois remise |

### Les applications déjà installées

**Elles ne changent pas.** Les applications 3.54 des stores ne savent
rien de l'acompte : elles n'envoient pas `avec_acompte`, leurs commandes
se règlent donc en entier (taux 100), comme elles l'annoncent au client.
L'acompte vaut pour les commandes passées depuis la 3.57.0. Dans l'autre
sens, une application 3.57.0 face à une base d'avant retire le paramètre
inconnu et fait payer le total : la réponse de la base décide de ce que
l'écran affiche.

### Ce qui change pour l'argent

- **BIZZOO encaisse l'acompte en ligne ; la boutique — son livreur —
  encaisse le reste à la porte.** Pour ces commandes, le règlement entre
  BIZZOO et ses boutiques change de sens : c'est désormais la boutique
  qui a l'essentiel en main, et BIZZOO qui garde l'acompte. Les chiffres
  de vente ne bougent pas — une commande compte toujours au moment où
  elle passe à « payée » —, mais ce règlement se fait hors de
  l'application.
- **Une commande annulée après l'acompte** se rembourse hors de
  l'application, comme un paiement entier aujourd'hui.
- **Paiement en ligne fermé, pas d'acompte** : la commande part sur
  WhatsApp et rien n'est créé en base.

### Le fichier à coller

[`supabase/acompte.sql`](supabase/acompte.sql). Il se suffit — il pose
les colonnes et les fonctions dont il a besoin — et se rejoue sans
dommage. Les applications installées n'en voient rien, puisqu'elles ne
demandent pas l'acompte.

**Il est appliqué sur la base en ligne depuis le 11 octobre 2026**,
collé par le propriétaire dans le SQL Editor : le fichier retire puis
repose deux fonctions, et l'outil Supabase de Claude attendait pour cela
une confirmation qui n'arrivait jamais. Vérifié aussitôt, sans rien
écrire : les 27 fonctions du fichier sont en ligne identiques au dépôt,
aux fins de ligne près ; `paiement.taux_acompte` est en place, borné de
1 à 100, à 10 % ; `creer_commande` prend ses quatre paramètres ; les
droits sont ceux du dépôt ; PostgREST a rechargé son schéma dans la
seconde. Les commandes d'avant n'ont pas d'acompte : elles se sont
payées en entier.

Pour le recoller sur une autre base, copier le fichier **en entier** —
le bouton « Copy raw file » de GitHub le fait. Un premier collage,
coupé à la ligne 100 par un aperçu du fichier, a été refusé par la base
avant d'exécuter quoi que ce soit.

### Les bancs

- [`supabase/tests/99t-acompte.sql`](supabase/tests/99t-acompte.sql) :
  92 constats sur un vrai PostgreSQL — le taux et qui l'écrit, le calcul
  (plancher, plafond, arrondi, code promo), une application d'avant, le
  verrou, l'encaissement incomplet puis entier, le partage au franc près,
  l'article annulé, qui voit quelle part, le livreur, les notifications,
  la confirmation à la main, la commande d'avant l'acompte. **Neuf
  sabotages le font tomber**, chacun sur la règle qu'il casse.
- [`tools/banc-acompte.mjs`](tools/banc-acompte.mjs) : 66 constats au
  navigateur, la base et les agrégateurs simulés — de l'annonce dans le
  panier jusqu'à l'écran du livreur, en passant par la base d'avant et le
  petit téléphone. **Huit sabotages le font tomber.** Les 20 autres bancs
  navigateur passent toujours : 1021 constats en tout, aucun échec.

## Le numéro d'abord, et qui a créé quel compte (3.58.0)

Le compte SMS de BIZZOO est prêt : **on crée son compte et on s'y connecte
désormais avec son numéro et un code reçu par SMS.** Et chaque compte de
l'équipe dit **qui l'a créé, le jour et l'heure.**

### Le client : son numéro, et un code

| Pour | Il faut |
|---|---|
| Créer son compte | son nom, son numéro, le code reçu |
| Se connecter | son numéro, le code reçu |
| Un compte ouvert avant, avec un e-mail | l'e-mail et le mot de passe **une dernière fois**, puis le code envoyé à son numéro — ensuite, le numéro suffit |

- **« Se connecter » ouvre sur le numéro.** L'e-mail recule derrière un
  lien, « Entrer avec mon e-mail », pour les seuls comptes d'avant
  (`#/connexion-email`). « Créer mon compte » ne demande plus ni e-mail
  ni mot de passe.
- **Le même code crée et ouvre.** GoTrue crée le compte au premier code
  validé et ouvre celui qui existe déjà : l'écran ne dit donc à personne
  quels numéros ont un compte chez BIZZOO. Un compte né à la porte « Se
  connecter » donne son nom juste après — et ce nom s'écrit seul, sans
  effacer une adresse déjà donnée. « Créer mon compte » avec un numéro
  qui en avait déjà un ouvre ce compte-là, et le dit.
- **La demande de revendeur** se fait toujours à l'inscription : elle part
  une fois le compte ouvert, avec sa session. Un statut déjà acquis ne se
  redemande pas.
- **L'ancien compte e-mail n'entre pas sur son seul mot de passe.** La
  session que GoTrue rend attend **en mémoire seulement** : rien n'est
  gardé sur le téléphone avant le code, et « Annuler » le laisse dehors.
  Le code validé, il entre, et les commandes passées avec ce numéro le
  rejoignent.
- **Resté connecté depuis avant**, un compte e-mail est prié de confirmer
  son numéro dans « Mon compte » — une carte devant tout le reste — et
  **avant de commander** : la commande reprend d'elle-même ensuite, panier
  intact.
- **Trois exceptions, voulues.** Le SMS fermé ou incertain : on n'enferme
  personne dehors sur une réponse qu'on n'a pas — fermé, l'e-mail et le
  mot de passe reviennent devant, comme avant. Un numéro déjà confirmé
  chez GoTrue. Un compte de l'équipe, qui a sa propre porte.

**Ce n'est pas un verrou de la base**, et c'est voulu : la porte e-mail
reste ouverte chez Supabase, parce que l'application admin s'en sert pour
créer les comptes de l'équipe (`/auth/v1/signup`). C'est l'application
client qui ne propose plus que le numéro.

### L'équipe : un code à chaque connexion

Quand le superadministrateur l'exige, chaque compte de l'équipe —
administrateurs, modérateurs, livreurs — rend **un code reçu par SMS à
chaque connexion**, en plus de son mot de passe. **Tant qu'il ne l'a pas
rendu, la base ne lui reconnaît aucun droit** : `role_courant()` ne répond
rien à une session non confirmée, et toutes les règles de l'équipe en
découlent — `est_admin()`, `est_super()`, `boutique_du_compte()`,
`est_compte_enseigne()`… Un mot de passe volé n'ouvre plus rien.

Pourquoi pas le code de GoTrue, comme pour les clients ? Parce que GoTrue
marque **toute** session ouverte par un code de la même façon — un lien
reçu par e-mail compris : rien n'y distinguerait « a reçu un SMS sur le
numéro de sa fiche ». Les codes de l'équipe sont donc les nôtres :

- tirés par la fonction Edge **`code-connexion`** (déployée **avec**
  vérification du jeton), envoyés au numéro **de la fiche** — jamais à un
  numéro tapé à l'écran ;
- gardés **hachés avec la session** (`sha256(code:session)`) : un code ne
  vaut que pour la connexion qui l'a demandé, et ne revient jamais à
  l'application ;
- **10 minutes**, **5 essais**, un renvoi toutes les **30 secondes**, **5
  codes par heure** — en base, où rien ne les contourne ;
- inscrits par la seule clé de service : un compte connecté ne choisit
  pas son propre code.

Rendre son code vérifie aussi **le numéro de la fiche** ; le changer
annule cette vérification. **Un nouveau compte de l'équipe ne se crée plus
sans numéro** : c'est là que partira son code.

**L'interrupteur** est dans **Réglages → BIZZOO → « Connexion de l'équipe
par SMS »**, au superadministrateur seul. La carte compte l'équipe et
**nomme qui n'a pas de numéro** — il ne pourrait plus entrer. Elle ne
s'allume qu'**après que le superadministrateur a reçu et rendu son propre
code** : c'est la preuve que la passerelle livre, avant d'en dépendre. La
base le refuse sinon.

En cas d'urgence — plus de crédit SMS, et plus personne n'entre —, dans le
SQL Editor de Supabase :

```sql
update public.securite_equipe set sms_exige = false;
```

### Qui a créé quel compte

Chaque compte de l'équipe porte **son créateur, son nom et son rang au
moment de la création, la date et l'heure** (`profils.cree_par`,
`cree_par_nom`, `cree_le`). La base les écrit — un déclencheur, au moment
où un administrateur donne son rang à la fiche toute neuve — et **personne
ne les réécrit ensuite**, pas même le superadministrateur.

- **Admin → Comptes** : sous chaque compte, « Créé le 10 octobre 2026 à
  14:05 par Sena (superadministrateur) · numéro vérifié », et la même
  ligne en tête de sa fiche. Un compte né hors de l'application —
  tableau de bord de Supabase, inscription seule — le dit : « — hors de
  l'application ».
- **Les comptes d'avant** retrouvent leur créateur dans le journal
  (« Modérateur ajouté : … », écrit au nom de celui qui l'a créé), une
  fois, sans jamais écraser une trace déjà posée.
- **Admin → Fiches clients** : un compte client s'ouvre toujours par le
  client lui-même ; la fiche dit par quelle porte — « avec son adresse
  e-mail », ou « avec son numéro, confirmé par un code SMS ».

Au passage, un défaut d'avant est tombé : un administrateur de boutique
ne pouvait pas finir de créer un modérateur — la fiche toute neuve, sans
boutique encore, lui était invisible. Les deux règles de `profils` le
laissent désormais voir et compléter **cette** fiche, un quart d'heure
durant, et rien d'autre.

Et un piège a été évité de justesse : **l'Historique annule une
modification de compte en remettant la fiche d'avant entière**, par un
upsert. L'insertion passe d'abord par la règle de création, qui y aurait
nommé le créateur du moment — et toute annulation aurait échoué sur « la
création ne se réécrit pas ». Une insertion qui vise une fiche existante y
reporte donc la trace en place ; un upsert qui *écrit* un autre créateur
reste refusé.

### Le fichier à coller, et les fonctions

[`supabase/connexion-sms.sql`](supabase/connexion-sms.sql) se suffit, se
rejoue sans dommage et ne supprime rien. **Il ne change rien tant que
l'interrupteur est éteint** : le code de l'équipe n'est exigé qu'une fois
allumé, depuis les Réglages. La mise en route — secrets, fonctions, hook
de Supabase — est dans la section suivante.

**Il est appliqué sur la base en ligne depuis le 12 octobre 2026.**
Vérifié aussitôt, sans rien écrire : les 15 fonctions du fichier sont en
ligne identiques au dépôt, à l'octet près ; leurs droits sont ceux du
dépôt — inscrire ou annuler un code, la clé de service seule ; les codes
et l'interrupteur ne se lisent pas depuis l'API ; l'interrupteur est
éteint ; les deux règles de `profils` ouvrent la fiche toute fraîche.
**Neuf comptes de l'équipe sur treize ont retrouvé leur créateur** dans
le journal ; les quatre autres sont nés hors de l'application. Les trois
fonctions sont déployées le même jour : `hook-sms-auth` sans vérification
du jeton, `tester-sms` et `code-connexion` avec. Le premier essai depuis
les Réglages a montré que la passerelle attend le texte sous `content` :
le transport corrigé est redéployé dans les trois le soir même.

### Les bancs

- [`supabase/tests/99u-connexion-sms.sql`](supabase/tests/99u-connexion-sms.sql) :
  104 constats sur un vrai PostgreSQL — qui inscrit un code, le frein et
  le plafond, les essais, l'expiration, le code d'une autre session,
  l'interrupteur, la base qui ferme sans code, la trace, l'annulation et
  le rattrapage. **Treize sabotages le font tomber**, chacun sur la règle
  qu'il casse ; trois d'entre eux sont arrêtés plus tôt encore par
  l'état des lieux (contrôles 124 à 128), qui fait le même constat sur la
  base en ligne. 1298 constats en tout.
- [`tools/eprouver-sms.sh`](tools/eprouver-sms.sh) : le transport, le hook
  (dont le destinataire d'un changement de numéro) et `code-connexion` —
  105 constats, l'empreinte de référence partagée avec la base.
- [`tools/banc-connexion-sms.mjs`](tools/banc-connexion-sms.mjs) : 70
  constats au navigateur, côté client ; **huit sabotages** le font
  tomber.
- [`tools/banc-connexion-equipe.mjs`](tools/banc-connexion-equipe.mjs) : 46
  constats, côté admin ; **douze sabotages** le font tomber.
- [`tools/banc-sms-ferme.mjs`](tools/banc-sms-ferme.mjs) suit la nouvelle
  porte : le SMS fermé, tout revient comme avant.

Les 21 autres bancs navigateur passent toujours : 1119 constats en tout,
sur 23 bancs, aucun échec.

## Vérification du numéro (entrer par SMS)

Au Bénin, beaucoup d'acheteurs n'ont pas d'adresse e-mail mais tous ont
un numéro. **Depuis la 3.58.0, le numéro est LA porte** (section
précédente) ; l'e-mail ne sert plus qu'aux comptes ouverts avant.

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

2. **Les trois fonctions** :

   ```bash
   supabase functions deploy hook-sms-auth --no-verify-jwt
   supabase functions deploy tester-sms
   supabase functions deploy code-connexion
   ```

   `tester-sms` et `code-connexion` gardent la vérification du jeton : un
   SMS coûte de l'argent, et seul un compte connecté peut en demander.

   `--no-verify-jwt` est indispensable : c'est Supabase lui-même qui
   appelle ce point d'entrée, sans jeton d'utilisateur. Ce qui le protège
   n'est pas un jeton mais **la signature** — l'en-tête Standard Webhooks,
   vérifiée octet pour octet sur le corps brut, avec une fenêtre de cinq
   minutes contre le rejeu. Sans `SMS_HOOK_SECRET`, la fonction refuse de
   démarrer plutôt que de laisser passer.

3. **Dashboard → Authentication → Hooks → Send SMS hook**, de type
   **HTTPS** → `https://<projet>.supabase.co/functions/v1/hook-sms-auth`,
   puis « Generate secret » : le secret `v1,whsec_…` va tel quel dans
   `SMS_HOOK_SECRET`. Ensuite **Authentication → Sign In / Providers →
   Phone** : activer, avec la confirmation du numéro — sans elle, aucun
   code ne part, et le hook n'est jamais appelé. Le formulaire réclame
   quand même un fournisseur (Twilio) et ses champs : y mettre
   `inutilise`. Le hook prend sa place, ces valeurs ne servent jamais.

4. **Éprouver pour de vrai**, depuis l'app admin : Réglages → *Essayer la
   passerelle SMS*. L'écran rend **la réponse brute de la passerelle** —
   c'est voulu : si un champ ne porte pas le nom attendu, la réponse le
   dit elle-même.

Trois pièges qui coûtent des heures :

- **Un `HTTP 200` de CREATISINTER ne veut pas dire « envoyé ».** La
  réponse porte un `status` et un code d'état ; seuls
  `SUBMITTED`, `SENT`, `DELIVERED` et `PROGRAMMED` valent succès. Le
  transport (`functions/_partage/sms.ts`) le vérifie, et 105 assertions
  (`tools/eprouver-sms.sh`) l'éprouvent — avec le hook et
  `code-connexion`.
- **Le texte part sous `content`, pas sous `message`.** Sous `message`,
  la clé est acceptée mais l'envoi refusé : « MISSING_PARAMETERS_CONTENT —
  Required parameter [content] or [text] is missing ». Côté client, cela
  se voyait seulement comme « Unexpected status code returned from hook:
  500 ».
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
trente-trois constats, trois sabotages qui le font rougir.

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

`node tools/make-icons.js` en tire les 48 images des deux applications
(50 depuis que le logo a la sienne, `icons/logo-bizzoo.png`, en 3.56.1),
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

## Le bleu de l'icône (3.53.0)

Les écrans prennent le bleu de la nouvelle icône. Le bleu principal
passe de `#0047D9`, le bleu vif de la DA, à **`#2550B7`** : le bleu du
milieu de la tuile, un bleu roi un peu moins saturé.

**Chaque nuance garde sa clarté, et prend la couleur de l'icône.** Le
dégradé de la tuile est mesuré comme pour les icônes (un plan par
couleur) ; il court exactement le long de sa diagonale, de `#3B77F6` en
haut à gauche à `#0D2574` en bas à droite. Pour chacune des huit
nuances, on garde la **luminance** de celle qu'elle remplace — donc
tous les contrastes, à 0,04 près — et on prend la couleur que la tuile
a à cette luminance. Plus claire que la tuile : son bleu le plus clair,
éclairci vers le blanc ; plus sombre : son bleu le plus sombre, assombri
vers le noir.

| Jeton | Avant | Après | D'où vient la nouvelle nuance |
|---|---|---|---|
| `--bleu-900` | `#001B52` | `#091A51` | le bas de la tuile, assombri |
| `--bleu-800` | `#002A80` | `#102A7C` | la diagonale, à 94 % |
| `--bleu-700` | `#0038A8` | `#1A3B98` | la diagonale, à 73 % |
| `--bleu` | `#0047D9` | `#2550B7` | la diagonale, à 48 % : le milieu |
| `--bleu-400` | `#3D78EC` | `#3B76F4` | le haut de la tuile |
| `--bleu-300` | `#6FA0F5` | `#749EF8` | le haut, éclairci |
| `--bleu-100` | `#D6E2FB` | `#D5E2FD` | le haut, éclairci |
| `--bleu-50` | `#EDF2FE` | `#ECF2FE` | le haut, éclairci |

Les nuances claires et la plus sombre bougent à peine : elles étaient
déjà dans la teinte de l'icône. Ce qui change à l'œil, c'est le bleu
principal et ses deux nuances foncées — le « Bizz » du logo, les
boutons pleins (« Payer », « Suivre »), les liens, l'onglet actif,
l'offre du jour. Le blanc sur le bleu reste à **7,2:1**.

**Ce qui suit le bleu :**
- les deux applications, la page d'entrée du site et sa page 404 ;
- les ombres, écrites en `rgba(…)` : elles ne suivent pas les jetons ;
- la couleur de barre du navigateur (`theme-color`) et le manifeste du
  client ; la fenêtre de paiement KkiaPay (`theme`) ;
- le bleu de secours d'une couleur de boutique illisible ;
- le **« Bleu BIZZOO »** des nuanciers de l'admin (boutiques et
  catégories), qui valait encore `#0B5CF5`, le bleu d'une charte
  antérieure. Une boutique ou une catégorie enregistrée avec l'ancien le
  **garde** : le nuancier l'ajoute sous « Couleur actuelle » plutôt que
  de la remplacer en silence. En base, une boutique et deux catégories
  l'utilisent ; il suffit de leur choisir le nouveau. La colonne garde
  `#0B5CF5` comme valeur par défaut : l'admin écrit toujours la couleur
  choisie, ce défaut ne sert qu'à une ligne insérée à la main ;
- les captures de la vitrine (`vitrine/ecran-*.jpg`) et l'image de
  partage (`vitrine/partage.jpg`), refaites — elles montrent aussi
  l'accueil d'aujourd'hui, le slider en tête.

**Ce qui ne bouge pas :** la barre du navigateur de l'admin garde le bleu
nuit de sa pastille « réglages » (`#001A6E`) ; les couleurs propres à
chaque boutique et catégorie, qui sont des données ; l'orange.

**Un défaut trouvé en chemin, par la capture.** Sur l'accueil de
l'admin, la carte « Stock de la boutique » (3.49.0) n'avait pas de
fond : son titre et son texte flottaient sur la page, un rectangle blanc
au bord. C'est un lien, et un « a » reste en ligne si rien ne dit le
contraire : son fond ne couvre alors que des bouts de ligne. Les cartes
orange « à traiter » (validations, revendeurs, réclamations, avis) et
les cartes Clients, Versements et Codes promo de l'enseigne avaient le
même défaut. Toute carte-lien est désormais un bloc (`:where(a).carte`,
qui laisse aux variantes en flex le dernier mot), et `banc-da` mesure
que chaque carte-lien enveloppe son titre.

## Le logo partout, et des captures à jour (3.56.1)

La version web portait encore l'ancien logo, et ses captures montraient
l'accueil d'avant. Deux oublis, et un piège :

- **Le logo.** À la 3.52.0, le B au chariot n'a remplacé que les
  icônes : l'écran du téléphone, l'onglet du navigateur, la connexion de
  l'admin. Partout ailleurs restait « Bizzoo » écrit avec ses deux
  points : l'en-tête et le pied du site, sa page 404, le haut des deux
  applications, leur menu sur ordinateur.
- **Les captures.** Les quatre écrans de la vitrine et l'image de
  partage dataient de la 3.54.0. L'accueil y montrait encore les ronds
  de couleur d'avant les icônes des planches (3.56.0).
- **Le piège.** L'hébergement laisse les navigateurs garder une image
  une semaine, et WhatsApp garde l'aperçu d'une adresse. Une image
  refaite sous le même nom ne se voit donc pas tout de suite.

### Le logo : le B au chariot, puis le nom

C'est le choix de l'enseigne, parmi trois propositions (la tuile et le
nom, la tuile seule, le nom seul). La tuile est
`icons/logo-bizzoo.png`, que `tools/make-icons.js` tire de l'œuvre dans
les deux applications. Dans l'admin aussi, c'est la tuile **sans** la
pastille « réglages » : la marque de BIZZOO, pas l'icône d'une
application. Les deux service workers la gardent hors connexion. Le nom
reste écrit, en bleu et orange, sans les deux points : les roues du B
les portent.

Où il est :
- **le site** : l'en-tête, le pied (« Bizz » en blanc sur le bleu nuit),
  la page 404 ;
- **l'application des clients** : la barre du haut de l'accueil (le
  slogan sous le nom, à droite de la tuile), le menu sur ordinateur,
  « À propos de BIZZOO », la couverture d'une boutique sans photo ;
- **l'admin** : la barre du haut (« Espace admin » sous le nom), le menu
  sur ordinateur (« Admin » sous le nom).

Le logo est plus large qu'avant, et deux endroits manquaient de place.
- **La barre du haut de l'admin.** Le superadministrateur y a cinq
  boutons : à 360 px, ils recouvraient « Bizzoo », sans que rien ne
  déborde de l'écran. Le logo se règle sur la place qui lui reste : en
  entier à partir de 390 px, plus petit à 360, la tuile seule à 320.
- **L'en-tête du site.** « Ouvrir la boutique » y passait sur deux
  lignes à 390 px. Au téléphone, l'en-tête se resserre, et sous 360 px
  le bouton ne dit plus que « Boutique ». Le grand bouton orange du
  bandeau, juste dessous, le dit en toutes lettres.

En passant, les liens légaux du pied du site (mentions, confidentialité,
conditions, suppression de compte) sont rentrés dans sa marge. Posés en
dehors, ils touchaient le bord de l'écran, en grand.

### Les captures

Elles sont refaites depuis l'application 3.56.1, dans la même mise en
scène que les précédentes : 390 px, en double densité, réduites à
540 × 1169, JPEG qualité 82. Les huit catégories de l'accueil sont
celles que range `categories-rangement.sql`, avec leurs icônes.

**Seul l'accueil change.** Les trois autres écrans (la boutique, le
produit, le paiement) sortent identiques à l'octet près : ni le logo ni
les catégories n'y figurent. L'image de partage (1200 × 630, 89 Ko)
porte le nouveau logo et le nouvel accueil.

**Les adresses portent la version des images** :
`vitrine/ecran-accueil.jpg?v=3.56.1`, et de même pour les trois autres
écrans et pour `og:image`. Une adresse nouvelle oblige navigateurs et
WhatsApp à reprendre l'image.

**À refaire quand l'accueil ou le logo changent** : les quatre captures,
l'image de partage, puis le `?v=` dans `index.html` (captures et
`og:image`) et dans `client/index.html` (`og:image`).

`banc-da` regarde le logo lui-même, et pas seulement son texte :
- la tuile est bien celle du logo, chargée, devant le nom ;
- les deux points sont partis ;
- le site, sa page 404, la barre du haut et le menu des deux
  applications ;
- la barre de l'admin à 320, 360 et 390 px, avec ses cinq boutons ;
- l'en-tête du site sur une ligne, de 320 à 1440 px.

`banc-mise-en-ligne` ouvre la page 404 sous une adresse profonde, et
vérifie que son logo s'affiche. Il lit aussi `og:image` versionnée.
Six sabotages les font tomber :
- la tuile retirée de l'accueil ;
- les points remis ;
- l'admin sans réglage de place ;
- l'icône à pastille au lieu du logo ;
- l'en-tête du site qui ne se resserre plus ;
- le logo de la 404 en adresse relative.

## La barre du bas à deux visages (3.54.0)

La barre du bas n'est plus la même partout : elle dit où l'on se tient.

| Sur BIZZOO | Dans une boutique |
|---|---|
| **Accueil** — l'accueil de BIZZOO | **Accueil** — la vitrine de la boutique |
| **Catégories** — la liste de BIZZOO | **Catégories** — ses rayons à elle |
| **Favoris** | **Favoris** — tous les vôtres, de toutes les boutiques |
| **Recherche** — dans toutes les boutiques | **Recherche** — d'abord chez elle, une puce pour toutes les boutiques |
| | **Retour à Bizzoo** — le logo en guise d'icône : on revient à l'accueil de BIZZOO, et on sort de la boutique |

**Le compte est monté dans la barre du haut**, juste avant le panier. Il
s'allume sur les écrans du compte — la connexion, pour un visiteur.

**Une fois entré chez quelqu'un, on y reste.** « Accueil » ramène à la
vitrine de la boutique, et non plus à BIZZOO : on la quittait sans
l'avoir voulu, en croyant remonter en haut de la sienne. Sortir se
demande, par « Retour à Bizzoo ». C'était le comportement d'avant la
DA, qui l'avait retiré en faisant de la fiche boutique un écran sans
barre.

**La vitrine et la fiche d'un produit portent la barre de la boutique.**
Sur la fiche produit, « Ajouter au panier » se pose au-dessus des
onglets, jamais dessus ; sur ordinateur, à droite du menu. Le panier, le
paiement et la confirmation traversent les boutiques : ils restent sans
barre. En boutique unique, il n'y a pas d'enseigne où revenir : la barre
garde le visage de BIZZOO, sans « Retour ».

**Ce qui a changé sous le capot :**
- « Catégories » ne fait plus sortir de la boutique. Dans une boutique,
  l'onglet montre ses rayons (`rayonsDeLaBoutique`, qui existait mais ne
  servait plus) ; un rayon ouvert de là n'affiche que ses produits, et
  ses puces que ses rayons ;
- les **favoris** se retrouvent dans toutes les boutiques ouvertes : la
  vue passait par `Catalogue.produits()`, limité à la boutique en cours,
  et aurait compté les favoris des autres pour « plus en vente » ;
- la **recherche** garde ce qui est tapé quand on passe de « Chez … » à
  « Toutes les boutiques » ;
- « Retour à Bizzoo » tient sur deux lignes au cinquième d'un téléphone ;
  sur 320 px, les libellés perdent un point pour que « Catégories »
  tienne en entier.

`tools/banc-navigation-boutique.mjs` suit le vrai chemin — la tuile
d'une boutique, ses onglets, un rayon, la recherche, les favoris d'un
client connecté, une fiche produit, la sortie — en 52 constats, du
téléphone de 320 px à l'ordinateur. Dix sabotages le font tomber, un par
règle : « Catégories » qui fait sortir, « Accueil » toujours vers
BIZZOO, « Retour à Bizzoo » jamais affiché, les favoris filtrés par la
boutique, l'action posée sur les onglets, le compte retiré du haut, la
recherche jamais limitée, la petite taille retirée à 320 px, les rayons
d'une catégorie non filtrés, la fiche produit sans barre.
`banc-da-ecrans` et `banc-notifications` suivent la nouvelle barre (la
cloche se pose avant le compte, le panier reste le dernier bouton). Les
captures de la vitrine et l'image de partage sont refaites : elles
montrent la nouvelle barre.

## Préparation Google Play (3.54.1)

Les deux applications seront publiées sur le compte **WINNER MARKET LIFE**.
La configuration cible Android 16 (`targetSdk 36`) et garde les packages
existants. Les variantes `clientPlay` et `adminPlay` utilisent une clé privée
hors dépôt ; les APK de test gardent leur signature historique.

Lancer `python3 tools/construire-play.py` avec Java 17 et Android SDK 36.
Le script construit les deux AAB et lance les contrôles Android Lint.
Les variables `BIZZOO_PLAY_*` sont obligatoires pour une construction Play.

Le [dossier de publication](docs/google-play.md) contient les fiches proposées,
les instructions de signature et les points encore nécessaires avant soumission.
Les AAB préparés ne valent pas validation Google Play : la confidentialité,
la suppression de compte et les parcours authentifiés doivent être vérifiés.

### Étapes de publication

1. Compte **Google Play Console** (25 $ une fois).
2. Générer une **clé de signature privée** (à garder précieusement,
   jamais dans le dépôt) et construire des **AAB** :
   `./gradlew bundleClientPlay bundleAdminPlay` avec les variables de
   signature privées, sans remplacer la clé de test.
3. Créer deux fiches Play (client et admin — l'admin peut rester en
   « diffusion interne » pour ne pas être publique), avec captures
   d'écran, description et politique de confidentialité.

La conformité doit être évaluée sur les fonctionnalités réellement proposées :
localisation facultative, notifications, photos, comptes et commandes.
La présence d'icônes adaptatives et d'une cible Android récente ne suffit pas.

## Le pixel Meta (3.54.2, site web seulement)

Le pixel **1786119222612781** mesure la publicité de BIZZOO sur Facebook
et Instagram. Tout passe par
[`client/js/pixel.js`](client/js/pixel.js) : les écrans disent « ceci
vient d'arriver », le module décide de ce qui part, et quand.

**Il ne vit que sur l'adresse officielle**, `www.bizzoomarket.com` (et
`bizzoomarket.com`). Les applications Android et iPhone servent les mêmes
fichiers, mais depuis le téléphone : pas de pixel, donc rien à déclarer de
plus sur Google Play, et pas d'autorisation de suivi à demander sur
l'iPhone. La copie de GitHub Pages ne parle pas à Meta non plus.
L'application admin n'a pas de pixel.

| Événement | Quand il part |
|---|---|
| `PageView` | à chaque écran de la boutique, et à l'ouverture de la vitrine |
| `ViewContent` | une fiche produit ouverte : identifiant, nom, prix, XOF |
| `AddToCart` | « Ajouter au panier » — ce qui est vraiment entré, pas ce qui était demandé |
| `InitiateCheckout` | « Passer la commande » : le panier entier, son total |
| `AddPaymentInfo` | le choix de l'opérateur, ou « Payer » si on a gardé celui proposé — une fois par écran |
| `Purchase` | **quand la base confirme le versement**, jamais au clic sur « Payer » : total payé, produits, quantités, numéro de commande |
| `CompleteRegistration` | un compte créé par e-mail, ou par numéro — la naissance du compte, pas chaque retour |
| `Lead` | une demande de compte revendeur, à l'inscription ou depuis « Mon compte » |
| `Search` | ce qu'on a fini de taper : une pause d'une seconde et demie, ou Entrée |
| `Contact` | un lien WhatsApp vers un numéro, `tel:` ou `mailto:` — un partage WhatsApp n'en est pas un |

**Un envoi par action.** Un écran redessiné — catalogue mis à jour, prix
d'un revendeur arrivés — n'est pas une visite. Un écran qui renvoie aussitôt
ailleurs (le panier vide qui ramène à l'accueil) non plus : seul le second
compte. Un écran qui travaille longtemps compte au bout de deux secondes
s'il est toujours affiché : le reçu, qui patiente jusqu'à la confirmation du
paiement, aurait sinon compté une minute et demie trop tard — ou jamais. Meta suit d'ordinaire tout seul les changements d'adresse des
applications d'une page ; `disablePushState` le lui interdit, sinon chaque
écran compterait deux fois. Un achat est gardé en mémoire sur le téléphone,
avec un `eventID` (`achat-BZ-…`) : un reçu rouvert, une confirmation relue
ne le recomptent pas. Seules comptent les commandes passées depuis ce
téléphone, et depuis moins d'une semaine : une vieille commande restée « à
payer », dont la confirmation n'est relue qu'aujourd'hui, ne devient pas un
achat du jour.

**Rien de personnel.** Ni nom, ni numéro, ni e-mail : des identifiants de
produits, des montants en nombre entier (18500, pas « 18 500 FCFA »), la
monnaie (XOF), un numéro de commande. Une recherche qui ressemble à un
numéro ou à une adresse e-mail ne part pas. La configuration automatique
de Meta (`autoConfig`) est coupée : elle relève d'elle-même les clics et le
contenu des pages. *Dans le Gestionnaire d'événements, la « correspondance
avancée automatique » doit rester éteinte* : elle irait chercher, de son
côté, les e-mails et numéros tapés dans les formulaires.

**Jamais de jeton vers Meta.** Le lien « mot de passe oublié » ramène le
client avec sa session dans l'adresse, et Meta reçoit l'adresse avec chaque
événement. Le pixel ne se charge donc qu'au premier écran dessiné, quand
l'application a lu le jeton et nettoyé l'adresse ; et rien ne part tant
qu'elle en porte un. Sur la vitrine, la redirection vers la boutique passe
avant le pixel. Le code de Meta ne se colle donc **pas** tel quel en tête de
page, comme Meta le conseille : il doit rester après la redirection.

**Sans bandeau de consentement**, par décision de l'enseigne. La
[politique de confidentialité](legal/confidentialite.html) (section
« Mesure publicitaire sur le site », version du 15 octobre 2026) dit ce qui
part, à qui, et comment s'y opposer. Elle est générée par
`tools/generer-mentions.py`, comme les autres pages légales.

### Ce que la 3.58.0 y change

- **L'inscription par numéro.** Le compte naît au code validé ; c'est
  l'écran (`apresEntree`) qui la déclare, parce que lui seul sait si une
  demande de revendeur l'accompagne : `CompleteRegistration` porte alors
  « revendeur », et `Lead` part une fois la demande enregistrée. Un numéro
  qui avait déjà son compte n'est pas un inscrit. L'inscription par e-mail
  ne vit plus que quand le SMS est fermé ; elle déclare comme avant.
- **L'acompte.** La valeur de `Purchase` reste **celle de la commande** :
  c'est ce que le client achète, et ce que la publicité doit mesurer. Ce
  qui a été versé en ligne part à côté, dans `acompte` ; le reste se paie à
  la livraison. L'achat part toujours à la confirmation du versement, et
  pas avant.

### Le banc

[`tools/banc-pixel-meta.mjs`](tools/banc-pixel-meta.mjs) sert le site sous
sa vraie adresse, remplace le script de Meta par un enregistreur, et note
chaque appel au moment où il part, avec l'adresse que Meta recevrait :
**78 constats** sur la 3.58.0 (71 sur la 3.54.2 en ligne : l'inscription
par numéro, l'acompte et un écran lent s'y ajoutent), de l'APK sans pixel
au jeton qui ne part jamais.
**Seize sabotages le font tomber**, chacun là où il casse : le pixel dans
l'APK, `disablePushState` ou `autoConfig` oubliés, le code de Meta collé en
tête de vitrine, l'écran redirigé ou redessiné compté, le reçu jamais compté
pendant qu'il attend le paiement, l'achat oublié, compté au clic sur
« Payer » ou compté pour une vieille commande, un numéro parti dans la
recherche, le partage pris pour un contact, chaque retour par numéro compté
comme une inscription, les montants en texte, la demande de revendeur
perdue, le moyen de paiement redit. Sur la 3.58.0, **vingt** : les mêmes —
le reçu, qui y rend la main tout de suite depuis la 3.56.1, cède la place
à un écran lent, la commande d'un autre téléphone que la base met quatre
secondes à rendre —, et quatre sur ce qu'elle ajoute : l'inscription par
numéro non déclarée, la demande de revendeur qui l'accompagne perdue,
l'acompte non transmis, l'achat qui vaudrait l'acompte au lieu de la
commande.

```bash
PLAYWRIGHT=<chemin>/playwright-core/index.js \
CHROMIUM=<chemin>/chrome node tools/banc-pixel-meta.mjs
```

## Qui me livre : le livreur sur le reçu (3.58.0)

Sur le reçu d'une commande payée, sous chaque boutique, le client voit
**le livreur à qui la course est confiée** : son nom, son numéro, et deux
boutons — **Appeler** et **WhatsApp**. Le message WhatsApp part tout
prêt : « Bonjour Sèna, je suis le client de la commande BZ-… ». Une
commande qui traverse deux boutiques montre deux livreurs, chacun sous la
sienne ; une boutique qui n'a pas encore confié sa part ne montre rien.

**C'est la base qui décide qui le voit**, par une seule fonction,
`livreurs_de_ma_commande(cible, tel)` — le client ne lit toujours pas la
table des comptes. Elle ne rend que le nom, le numéro et l'indicatif ; ni
e-mail, ni adresse, ni montant. Et seulement :

- au compte qui a passé la commande, ou à qui donne le numéro de
  téléphone de la commande (le client sans compte, comme pour le suivi) ;
- une fois la commande payée et la course confiée ;
- tant que le client n'a pas confirmé « J'ai bien reçu » — après, le
  numéro du livreur n'a plus à rester sous ses yeux ;
- jamais pour une part annulée, ni pour un livreur désactivé.

Un livreur sans numéro paraît sous son nom, avec une phrase : la boutique
peut mettre le client en relation. **Pour que les boutons apparaissent,
le numéro doit être rempli** dans la fiche du livreur (Comptes, dans
l'application admin). La politique de confidentialité le dit (version du
16 octobre 2026).

**À coller une fois dans Supabase** : [`supabase/livreur-client.sql`](supabase/livreur-client.sql)
— une fonction en lecture, aucune table ne change, relançable. Tant
qu'elle n'est pas posée, le reçu ne montre simplement pas de livreur.

**Elle est posée sur la base en ligne depuis le 16 octobre 2026.**
Vérifié aussitôt, sans rien écrire : la fonction existe avec ses deux
paramètres, en `security definer`, ouverte à `anon` et `authenticated` ;
elle ne rend que le nom, le numéro et l'indicatif, porte les quatre
conditions (payée, réception non confirmée, livreur actif, numéro de la
commande), et ne rend rien pour une commande inconnue.

### Les bancs

- [`supabase/tests/99v-livreur-client.sql`](supabase/tests/99v-livreur-client.sql) :
  14 constats sur un vrai PostgreSQL — rien avant la course confiée, le
  bon client seulement, le numéro de la commande pour qui n'a pas de
  compte, rien pour une commande impayée ou un livreur désactivé, et le
  numéro qui disparaît à la réception confirmée.
- [`tools/banc-livreur-client.mjs`](tools/banc-livreur-client.mjs) : 12
  constats au navigateur — la question posée avec la commande et son
  numéro, le livreur sous SA boutique, `tel:+229…` et `wa.me/229…` justes,
  rien quand la base ne rend rien ou ne connaît pas encore la fonction,
  aucune question pour une commande impayée.

## Les liens de partage : boutique, catalogue, produit (3.58.0)

Chaque boutique, son catalogue et chaque produit ont un lien qui ouvre
**directement** le bon écran :

| | Lien |
|---|---|
| Une boutique | `https://www.bizzoomarket.com/client/#/boutique/<id>` |
| Son catalogue | `https://www.bizzoomarket.com/client/#/boutique/<id>/produits` |
| Un produit | `https://www.bizzoomarket.com/client/#/produit/<id>` |

C'est **toujours l'adresse officielle**, même depuis l'application
Android, qui sert ses fichiers depuis le téléphone.

- **Dans l'application client** : « Partager la boutique » sous
  « Suivre », une icône de partage dans l'en-tête de la fiche produit et
  du catalogue d'une boutique. L'application Android ouvre le partage du
  téléphone (WhatsApp, Messenger, SMS…) par un nouveau pont,
  `AndroidPont.partager` — il faut donc un nouvel APK. Ailleurs : le
  partage du navigateur, ou une feuille « WhatsApp / Copier le lien ».
- **Dans l'admin** : une carte « Liens à partager » sur la fiche d'une
  boutique (la boutique, son catalogue) et sur celle d'un produit, avec
  « Copier » et « WhatsApp ».

Banc : [`tools/banc-partage.mjs`](tools/banc-partage.mjs), 12 constats.

## Les codes promo : pas pour les revendeurs, et ceux des particuliers (3.58.0)

**Un revendeur n'a pas de code promo.** Il achète déjà au prix BIZZOO :
un code s'ajouterait à cette remise et sortirait une seconde fois de la
même marge. La base le refuse, à l'aperçu comme à la caisse, en le
disant ; le champ du code n'apparaît plus dans son panier.
À coller : [`supabase/revendeur-sans-code.sql`](supabase/revendeur-sans-code.sql).

**Le code d'un particulier.** Dans l'admin, *Codes promo → Nouveau code de
particulier* (superadministrateur) : prénom, nom, e-mail, mot de passe, le
code, la remise du client (0 à 50 %) et la commission de la personne
(0,5 à 50 %). Un compte **client** est créé à son nom, puis le code.

- Le client qui tape le code a sa remise. La personne ne peut pas
  utiliser son propre code.
- La commission naît à la **livraison** : quand toutes les parts non
  annulées de la commande sont remises. Une commande annulée ou jamais
  livrée ne rapporte rien. Exemple : 2 % d'une commande de 100 000 FCFA
  = 2 000 FCFA. Une commission par commande, garantie par la base.
- Elle sort de la marge de l'enseigne et la base la **plafonne** à ce
  que l'enseigne gagne encore sur la commande après la remise.
- La personne se connecte à l'application client (*Entrer avec une
  adresse e-mail*), voit **Mes gains** dans *Mon compte* (code, solde,
  historique) et demande un retrait (500 FCFA au moins) vers son numéro
  Mobile Money. Le montant demandé n'est plus disponible.
- L'admin voit les **retraits à verser** sous la liste des codes : on
  envoie l'argent, puis *Versé* avec la référence du transfert, ou
  *Refuser* avec un motif (le montant revient sur le solde).

À coller : [`supabase/codes-particuliers.sql`](supabase/codes-particuliers.sql).

Bancs : [`supabase/tests/99w-revendeur-sans-code.sql`](supabase/tests/99w-revendeur-sans-code.sql),
[`supabase/tests/99x-codes-particuliers.sql`](supabase/tests/99x-codes-particuliers.sql)
(commission, plafond, annulation, solde, retraits, droits) et
[`tools/banc-codes-particuliers.mjs`](tools/banc-codes-particuliers.mjs), 14 constats.

## Le live TikTok (3.58.0)

Une boutique passe en direct sur TikTok : son administrateur (ou le
superadministrateur) ouvre l'**accueil de BIZZOO Admin** sur la boutique
et touche **Démarrer le live TikTok**. Après confirmation :

- **tous les téléphones où l'application BIZZOO (Android) est installée**
  reçoivent « *IMPACT est en live sur TikTok* » ; toucher la notification
  ouvre **directement la page TikTok de la boutique** (l'application
  TikTok si elle est installée) ;
- l'**accueil** de l'application et du site, et la **fiche de la
  boutique**, montrent un bandeau noir « *… est en live sur TikTok —
  Regarder* » tant que le live dure ;
- **Arrêter le live** retire le bandeau. Un live oublié s'éteint seul au
  bout de 4 heures.

Garde-fous : seul l'administrateur de la boutique lance son live (pas un
modérateur, pas un client) ; la boutique doit avoir son compte TikTok
(Réglages → réseaux sociaux) et être ouverte ; un live en cours ne se
réannonce pas ; **trois lives par jour au plus** par boutique.

Comment ça marche : la base ouvre le live (`demarrer_live`, qui décide des
droits) ; la fonction Edge [`annoncer-live`](supabase/functions/annoncer-live/index.ts)
envoie la notification par **Firebase Cloud Messaging** au sujet `tous`,
auquel l'application client s'abonne à son ouverture
([`ServiceNotifications.java`](android/app/src/main/java/com/impactinformatique/apps/ServiceNotifications.java)).
Le message ne porte que des données : c'est l'application qui construit
la notification et ouvre le lien TikTok.

### Ce qu'il faut régler (une fois)

1. **Créer le projet Firebase** : console.firebase.google.com → *Ajouter
   un projet* (« BIZZOO »), Google Analytics facultatif.
2. **Ajouter l'application Android** `com.impactinformatique.client`
   (Paramètres du projet → Général → *Ajouter une application* → Android).
   Remplir [`android/firebase.properties`](android/firebase.properties)
   avec l'ID de l'application, la clé API, l'ID et le numéro du projet.
   Ce sont des identifiants **publics** (ils sont dans tout APK
   Firebase) : on peut les transmettre.
3. **Le compte de service** : Paramètres du projet → *Comptes de service*
   → *Générer une nouvelle clé privée*. Le fichier JSON téléchargé est un
   **secret** : ne jamais l'envoyer dans une conversation ni le mettre
   dans le dépôt. Le coller **en entier** dans Supabase → *Edge Functions*
   → *Secrets* → nouveau secret `FIREBASE_COMPTE_SERVICE`.
4. **Déployer la fonction** : `supabase functions deploy annoncer-live`
   (avec la vérification du jeton, sans `--no-verify-jwt`).
5. **Un nouvel APK client** (Firebase y entre) : les téléphones doivent
   le réinstaller pour recevoir les notifications. Le bandeau, lui,
   marche tout de suite, site compris.

Sans Firebase réglé, le bouton ouvre quand même le live (le bandeau
s'affiche) et l'admin est prévenu que la notification n'est pas partie.
L'application iPhone ne reçoit pas ces notifications (il faudrait un
compte Apple Developer et APNs) ; elle voit le bandeau.

À coller : [`supabase/live-tiktok.sql`](supabase/live-tiktok.sql).

Bancs : [`supabase/tests/99y-live-tiktok.sql`](supabase/tests/99y-live-tiktok.sql)
(droits, refus, une seule annonce, trois par jour, lecture publique),
[`supabase/functions/tests/live.mjs`](supabase/functions/tests/live.mjs)
via `tools/eprouver-live.sh` (19 constats : jeton, signature RS256,
message, Firebase absent ou qui refuse) et
[`tools/banc-live-tiktok.mjs`](tools/banc-live-tiktok.mjs) (16 constats).

## Les frais de livraison (3.58.0)

**1 000 FCFA par commande** pour l'instant, une seule fois même si
plusieurs boutiques livrent. Ils dépendront plus tard de critères comme la
distance.

- Le client paie **le montant des articles + les frais de livraison**. Le
  panier, le formulaire de commande et le reçu montrent la ligne
  « Frais de livraison ».
- **Aucun code promo ne les touche** : la remise se calcule sur les
  articles seuls, et la commission d'un particulier aussi.
- L'acompte se prend sur le total, frais compris. À la livraison, les
  frais ne diminuent pas si un article est annulé ; si **tout** est
  annulé, il n'y a pas de course, donc pas de frais.
- Le superadministrateur règle le montant dans *Réglages → BIZZOO →
  Paiement → Frais de livraison* (0 à 100 000 FCFA ; 0 = pas de frais).
  Le montant est **figé** sur chaque commande à sa création : le changer
  ne réécrit pas les commandes passées, et personne ne peut le modifier
  après coup.
- **Les applications d'avant la 3.58.0 ne font pas payer les frais** :
  elles ne sauraient pas les afficher. C'est le paramètre `avec_frais`
  de `creer_commande` qui les active ; seule la 3.58.0 l'envoie.

À coller : [`supabase/frais-livraison.sql`](supabase/frais-livraison.sql)
— **au moment de mettre la 3.58.0 en ligne**, pas avant.

Bancs : [`supabase/tests/99z-frais-livraison.sql`](supabase/tests/99z-frais-livraison.sql)
(24 constats : total, remise, acompte, annulations, verrou, commission) et
[`tools/banc-frais-livraison.mjs`](tools/banc-frais-livraison.mjs) (21 constats).

## Les livreurs à part, et la position qui valide les comptes (3.58.0)

**Les livreurs ont leur propre écran.** Dans BIZZOO Admin, *Comptes*
montre l'équipe (modérateurs, administrateurs, superadministrateurs) et
une carte **« Les livreurs »** qui mène à leur écran (*#/livreurs*, aussi
depuis *Réglages → Gérer les livreurs*). On y voit chaque livreur, pour
quelle boutique il porte (ou BIZZOO), et s'il a validé sa position ; le
bouton **« Créer un livreur »** est à part de « Créer un compte », qui ne
propose plus ce rang. La fiche d'un livreur le garde livreur.

**Un livreur valide son compte par sa position.** À sa première
connexion, BIZZOO Admin l'arrête sur *« Validez votre compte »* : il écrit
son adresse, puis touche *Activer ma position et valider* (localisation du
téléphone). Tant qu'il ne l'a pas fait, **aucune course ne peut lui être
confiée** : la base le refuse (`assigner_livreur`). Sa position est
visible de sa boutique et de l'enseigne (table `positions_livreurs`,
écrite seulement par `enregistrer_ma_position`, par le livreur lui-même).

**Un revendeur valide son compte par sa position.** Dans l'application
client, la demande de compte revendeur ne part plus sans **la position du
téléphone** (bouton *Activer ma position*) **et** l'adresse ; le « lien de
carte » à coller a disparu. Une demande déjà en attente sans position
affiche *« Validez votre compte : votre position »* dans *Mon compte*.
Dans l'admin, *Valider* est désactivé tant que la position manque, et la
base refuse de toute façon (`valider_revendeur`) ; refuser reste possible.
Les revendeurs déjà validés ne perdent rien.

Correction au passage : l'écran admin des revendeurs n'affichait jamais
l'adresse ni la carte (les champs n'étaient pas repris de la base).

À coller : [`supabase/positions-comptes.sql`](supabase/positions-comptes.sql)
— au moment de mettre la 3.58.0 en ligne : avant, les livreurs de la
version en ligne n'ont pas d'écran pour enregistrer leur position, et
plus aucune course ne pourrait leur être confiée.

Bancs : [`supabase/tests/99zz-positions-comptes.sql`](supabase/tests/99zz-positions-comptes.sql)
(20 constats) et [`tools/banc-positions-comptes.mjs`](tools/banc-positions-comptes.mjs)
(26 constats).

## Entrer avec son numéro, son mot de passe, et un code (3.59.0)

**Clients et livreurs** entrent désormais avec leur **numéro de téléphone
et leur mot de passe, puis un code reçu par SMS**. L'adresse e-mail n'est
plus exigée nulle part.

**Client — créer son compte.** *Créer mon compte* demande le nom, le
numéro et un mot de passe (deux fois). Supabase envoie un code par SMS ;
le code validé ouvre le compte. « Pour revendre » garde sa demande, son
commerce et sa position.

**Client — se connecter.** *Se connecter* demande le numéro et le mot de
passe. Mauvais mot de passe : refus, et **aucun SMS ne part**. Mot de
passe juste : le code part, et c'est lui qui ouvre la session. La session
ouverte par le seul mot de passe n'est jamais gardée : elle est fermée
dès le code validé (`logout?scope=local`).

**Mot de passe oublié — ou jamais choisi.** Les comptes ouverts par SMS
avant la 3.59.0 n'ont pas de mot de passe. *Mot de passe oublié* propose
d'abord le numéro : un code, puis le choix du mot de passe. Le lien par
e-mail reste, pour qui a un e-mail.

**L'e-mail, facultatif, porte de secours.** Dans *Mon compte*, la carte
*Mes accès* permet d'ajouter son e-mail et de changer son mot de passe.
Sans son téléphone, on entre alors par *Entrer avec mon e-mail* : e-mail et
mot de passe, **sans code** (choix de BIZZOO). Un compte d'avant, ouvert
avec un e-mail et sans numéro, y confirme son numéro une fois, comme en
3.58.0.

**Livreurs.** *Créer un livreur* (BIZZOO Admin) demande d'abord son
**numéro**, un mot de passe, son nom, et son e-mail **facultatif**. Le
compte naît par le numéro (`compte: equipe` dans les métadonnées, sans
quoi la base le prendrait pour un acheteur). Supabase lui envoie alors un
SMS de confirmation : il peut l'ignorer. À l'écran de connexion de
BIZZOO Admin, le champ accepte **un e-mail ou un numéro** : avec un numéro,
le livreur donne son mot de passe, puis le code reçu par SMS (ce code
confirme aussi son numéro la première fois). L'e-mail noté sur sa fiche
devient, à cette première connexion, sa porte de secours : e-mail et mot
de passe, sans code. **Les autres comptes de l'équipe ne changent pas** :
e-mail et mot de passe, et le code d'équipe quand l'enseigne l'exige.

**Ce que la base change** ([`supabase/connexion-telephone.sql`](supabase/connexion-telephone.sql)) :

- `profil_nouveau_compte` pose la fiche d'équipe en attente d'un compte né
  par numéro avec `compte: equipe` ;
- `au_numero_confirme` ne pose jamais de fiche client à un tel compte ;
- `session_confirmee` reconnaît, **pour un livreur seulement**, la session
  ouverte par le code Supabase (jeton signé : méthode `otp`, numéro
  confirmé) : quand l'enseigne exige le code d'équipe, il n'a pas à rendre
  un second code.

**À savoir, honnêtement.** C'est l'application qui enchaîne mot de passe
puis code : la base ne distingue pas une session « mot de passe + code »
d'une session « code seul ». Le code seul reste, volontairement, le
chemin de *Mot de passe oublié*. Côté Supabase, laisser **Authentication →
Sign In / Providers → Phone → « Enable phone confirmations »** coché (s'il
ne l'est pas, l'application redemande quand même le code).

Bancs : [`supabase/tests/99zzz-connexion-telephone.sql`](supabase/tests/99zzz-connexion-telephone.sql)
(9 constats), [`tools/banc-connexion-telephone.mjs`](tools/banc-connexion-telephone.mjs)
(28 constats, BIZZOO Admin) et [`tools/banc-connexion-sms.mjs`](tools/banc-connexion-sms.mjs)
réécrit (101 constats, application client) ; contrôle 131 de
l'état des lieux.

## Une mise à jour du site se voit tout de suite (3.59.0)

**Le symptôme.** Après une mise à jour du site, un lien de partage ouvert
sur un téléphone qui connaissait déjà BIZZOO montrait l'ancienne version ;
la nouvelle n'apparaissait qu'à l'ouverture suivante.

**La cause.** Le service worker (`client/sw.js`, `admin/sw.js`) servait
sa coquille gardée *avant* le réseau, et ne rangeait la nouvelle qu'en
arrière-plan.

**Désormais : le réseau d'abord.** En ligne, chaque ouverture reçoit la
version du serveur. Hors connexion — ou réseau de plus de 4 secondes —,
la version gardée prend le relais : BIZZOO s'ouvre toujours sans réseau.
À l'installation, les fichiers sont pris au serveur, jamais au cache du
navigateur.

**Pour les téléphones qui ont encore l'ancien service worker** : la
correction leur arrive à leur prochaine ouverture (le navigateur
vérifie `sw.js` à chaque visite). Cette fois encore, ils peuvent voir
l'ancienne version une dernière fois ; ensuite, plus jamais.

Banc : [`tools/banc-mise-a-jour.mjs`](tools/banc-mise-a-jour.mjs)
(8 constats) — il rejoue la scène sur une copie : visite, mise à jour du
site, lien rouvert, puis serveur coupé. L'ancien service worker y montre
la version A ; le nouveau, la B.

## Un livreur n'est ni acheteur ni revendeur (3.59.0)

**Le constat** (message du CEO) : un livreur qui ouvrait l'application
client se voyait proposer « Devenir revendeur », « Mes commandes » et
« Retrouver mes commandes d'avant », comme un acheteur. La cause : un
livreur créé par e-mail qui entrait par **son numéro** dans l'application
client y recevait un **second compte**, client. En ligne, un livreur et
deux administrateurs avaient ainsi un compte client à leur numéro.

**Désormais :**

- **le numéro d'un livreur n'ouvre plus de compte client** (inscription ou
  code SMS) : l'application dit d'entrer avec le compte livreur ;
- **un livreur ne devient pas revendeur**, même par un compte client
  ouvert avant ; BIZZOO ne peut pas valider une telle demande (la refuser
  reste possible) ;
- **dans « Mon compte », un livreur** ne voit plus les rubriques
  d'acheteur (revendeur, « Mes commandes », « Retrouver mes commandes
  d'avant », « Vérifier par SMS ») : **« Mes courses »** les remplace —
  à livrer, livrées ces deux derniers jours, ce qu'il y a à encaisser —,
  avec le bouton de l'espace vendeur pour les faire avancer ;
- **un compte client « double »** (ouvert avant avec le numéro d'un
  livreur) est prévenu : « Ce numéro est celui d'un livreur », avec
  « Me déconnecter » pour entrer avec son compte livreur.

Le numéro se compare sur ses **huit derniers chiffres** (« 97 12 15 96 »
et « 01 97 12 15 96 » sont le même téléphone).

Au passage : un « non » à la question « ce compte est-il de l'équipe ? »
posée sans session ne survit plus à la connexion qui suit.

À coller : [`supabase/livreurs-sans-compte-client.sql`](supabase/livreurs-sans-compte-client.sql)
(après `connexion-telephone.sql`).

Bancs : [`supabase/tests/99zzzz-livreur-pas-client.sql`](supabase/tests/99zzzz-livreur-pas-client.sql)
(14 constats), [`tools/banc-livreur-compte-client.mjs`](tools/banc-livreur-compte-client.mjs)
(25 constats) ; contrôle 132 de l'état des lieux.

## L'administrateur de BIZZOO gère livreurs et revendeurs ; la boutique voit ses livreurs (3.59.0)

**L'administrateur de BIZZOO** — un compte *administrateur* rattaché à
aucune boutique — fait désormais, comme le superadministrateur :

- **les livreurs** : il les voit tous, avec leur position ; il crée un
  livreur (par son numéro, pour BIZZOO ou pour une boutique), modifie sa
  fiche, le retire. **Il ne nomme personne d'autre** : ni modérateur, ni
  administrateur, ni superadministrateur — la base le refuse ;
- **les revendeurs** : *Créer un revendeur* (écran *Comptes revendeurs*)
  demande son nom, son numéro, un mot de passe, son commerce et
  l'adresse de son commerce. Le compte naît par le numéro, avec une
  **demande en attente**. Le revendeur entre dans l'application BIZZOO
  (numéro, mot de passe, code SMS), **active la position de son
  téléphone** dans *Mon compte*, puis l'administrateur **valide** — la
  base refuse toujours de valider sans position.

Son accueil porte une carte *Livreurs et revendeurs*, et les demandes en
attente s'y affichent. Un **modérateur** de BIZZOO n'a pas ces droits.

**L'administrateur d'une boutique voit ses livreurs** (*Comptes → Les
livreurs*) : ceux de sa boutique, avec leur position et leur numéro, et
ceux de **BIZZOO** qui portent pour toutes les boutiques. Il ne les crée
ni ne les modifie : un nouveau livreur se demande à BIZZOO.

À coller : [`supabase/admin-bizzoo-livreurs-revendeurs.sql`](supabase/admin-bizzoo-livreurs-revendeurs.sql).
Les règles de `profils` sont aussi reportées dans `connexion-sms.sql`,
qui les redéfinissait : l'ordre des fichiers n'y change plus rien.

Bancs : [`supabase/tests/99zzzzz-admin-bizzoo.sql`](supabase/tests/99zzzzz-admin-bizzoo.sql)
(25 constats) et [`tools/banc-admin-bizzoo.mjs`](tools/banc-admin-bizzoo.mjs)
(27 constats) ; contrôle 133 de l'état des lieux.

## Créer un produit demande l'habilitation (3.59.0)

**Avant**, retirer à un compte le droit « produits » l'empêchait de
*retoucher* un produit, pas d'en *créer* ; un administrateur de boutique
l'avait d'office ; un administrateur de BIZZOO réduit aux commandes
intégrait quand même des produits dans les boutiques.

**Désormais une seule habilitation — créer, modifier, supprimer un
produit —, et elle vaut pour tous** : modérateur, administrateur de
boutique, compte de BIZZOO (interrupteur *Le catalogue*). **Seul le
superadministrateur passe outre.** Dans la fiche d'un compte, l'interrupteur
s'appelle *Peut créer et modifier les produits* et paraît aussi pour un
administrateur de boutique. Sans l'habilitation, l'application vendeur
masque le « + » de la barre et *Ajouter un produit*, et le formulaire dit
qu'il faut la demander au superadministrateur. La base refuse de toute
façon (`produits ajout`, `prix achat ajout`, `peut_modifier_produits`).

En ligne, tous les administrateurs de boutique ont déjà l'habilitation :
personne ne perd un droit par surprise. Un modérateur de BIZZOO ne l'a
pas — il ne pourra plus créer de produit.

À coller : [`supabase/produits-habilitation.sql`](supabase/produits-habilitation.sql).

## Les jours et heures d'ouverture des boutiques (3.59.0)

**Chaque boutique a ses jours et heures d'ouverture** — sept lignes :
ouvert ou fermé, heure d'ouverture, heure de fermeture. On les pose **à la
création** de la boutique (obligatoires), puis dans sa fiche ou dans
*Réglages*. Le texte libre « Horaires » devient *Précisions* (fêtes,
exceptions).

**Fermée en ce moment** — hors de ses heures, à l'heure du **Bénin** :

- ses produits **disparaissent** des listes, de la recherche et de
  l'accueil de l'application client ;
- sa page dit *« Fermée en ce moment. Elle ouvre demain à 08 h 00 »*, sans
  vitrine ; la fiche d'un produit (lien partagé) n'a pas de panier ;
- un panier qui en contient ne laisse pas commander, et dit quand elle
  rouvre ;
- **la base refuse la commande** (`creer_commande`) — même depuis une
  application pas à jour ;
- *À propos* montre les horaires, jour par jour.

**Les boutiques déjà en service n'ont pas encore d'horaires** : elles
restent ouvertes en permanence, comme avant, et leurs *Réglages* les
invitent à les poser.

À coller : [`supabase/horaires-boutiques.sql`](supabase/horaires-boutiques.sql).

Bancs : [`supabase/tests/99zzzzzz-produits-habilitation.sql`](supabase/tests/99zzzzzz-produits-habilitation.sql),
[`supabase/tests/99zzzzzzz-horaires.sql`](supabase/tests/99zzzzzzz-horaires.sql),
[`tools/banc-horaires-droits.mjs`](tools/banc-horaires-droits.mjs) ;
contrôles 134 et 135 de l'état des lieux.

## Chaque boutique : sa condition de paiement, ses frais de livraison (3.59.0)

**Chaque boutique dit comment on la paie** :

- **Tout à la commande** : le client paie sa part entière en commandant ;
- **Un acompte à la commande** (1 à 99 %) : le client en paie ce
  pourcentage en commandant, et **le livreur de la boutique encaisse le
  reste à la livraison**.

**Et elle fixe ses frais de livraison** (0 : livraison offerte). Aucun code
promo ne les touche.

On les règle à la création de la boutique (*Paiement et livraison*, dans sa
fiche), puis l'administrateur de la boutique les change dans *Réglages*.

**À la commande, la base calcule tout** (`creer_commande`) : la part de
chaque boutique — ses articles, remise d'un code promo déduite au prorata,
plus ses frais —, ce qui se paie maintenant (100 % ou son acompte, au franc
supérieur) et ce qui restera à la livraison. Ces parts sont figées sur la
commande (`commandes.parts`). Une commande sur deux boutiques additionne
leurs deux conditions et leurs deux frais.

**À la livraison**, chaque livreur encaisse la part de **sa** boutique, moins
son acompte (`restes_par_boutique`). Rien de ce que le client a versé n'est
perdu pour lui : un surplus, ou l'acompte d'une part annulée par sa
boutique, diminue ce qui reste dû aux autres.

**Dans l'application client**, le panier et l'écran de commande annoncent
le total, *À payer à la commande* et *À payer à la livraison* — et, sur
plusieurs boutiques, le détail de chacune (« tout à la commande · livraison
1 500 », « acompte 30 % »). C'est un aperçu, calculé comme la base ; le
montant demandé à l'agrégateur est celui que la base renvoie.

**Les boutiques déjà en service** reçoivent ce que l'enseigne appliquait à
toutes : acompte de 10 %, livraison 1 000 FCFA. Dans *Réglages → Paiement*,
l'acompte et les frais de l'enseigne ne sont plus que les valeurs proposées
aux nouvelles boutiques. Les commandes passées avant gardent leur ancienne
règle.

À coller : [`supabase/conditions-paiement-boutiques.sql`](supabase/conditions-paiement-boutiques.sql)
(après `horaires-boutiques.sql`).

Bancs : [`supabase/tests/99zzzzzzzz-conditions-boutiques.sql`](supabase/tests/99zzzzzzzz-conditions-boutiques.sql),
[`tools/banc-conditions-boutiques.mjs`](tools/banc-conditions-boutiques.mjs) ;
`99t-acompte.sql` et `99z-frais-livraison.sql` adaptés à la règle par
boutique ; contrôle 136 de l'état des lieux.

## Le parcours de livraison : la demande à tous, « Commande reçue », le livreur annoncé (3.59.0)

**1. Dès que la commande est payée, la demande de livraison part à
plusieurs livreurs à la fois** (`proposer_course`) :

- **Commande d'une seule boutique** : à **tous les livreurs de cette
  boutique** (validés, c'est-à-dire qui ont enregistré leur position). Une
  boutique qui n'en a aucun passe la main aux livreurs de BIZZOO.
- **Commande de plusieurs boutiques — livraison groupée** : aux **seuls
  livreurs BIZZOO**, sans passer par ceux des boutiques.

L'alerte (dans les notifications, avec les trois bips) dit tout :

- **Récupérer** : la boutique et son adresse — une ligne par boutique en
  livraison groupée ;
- **Livrer à** : le nom et l'adresse du destinataire ;
- **Destinataire** : son numéro ;
- **Frais de livraison** ;
- **Déjà payé** : ce que le client a réglé à la commande ;
- **À récupérer** : ce qu'il reste à encaisser à la porte — ou « Rien à
  récupérer : tout est payé ».

La demande s'affiche aussi en tête de *Mes courses* (application admin, et
application client pour un livreur) : `courses_proposees`. **Aucun prix
d'article** n'y figure.

**2. « Commande reçue »** : le **premier** livreur qui touche le bouton
prend la course (`prendre_course`) — toute la commande, toutes ses boutiques
en livraison groupée. Le suivant reçoit « Trop tard : un autre livreur a
déjà pris cette course », et la demande disparaît de la liste des autres.
**À ce moment**, le client reçoit *Votre livreur : Nom* avec le numéro du
livreur (une seule nouvelle, même groupée), et chaque boutique apprend qui
vient chercher son colis. Le reçu du client montre alors son livreur, avec
*Appeler* et *WhatsApp* — **pas avant**.

**3. Puis** : la boutique prépare le colis (*En préparation* chez le
livreur) ; une fois prêt, *Je l'ai prise*, puis *Je l'ai remise*. En
livraison groupée, le livreur a une course par boutique, chacune avec son
lieu de retrait et ce qu'il y encaisse.

**Le secours** : si personne ne prend la demande, la boutique garde
*Confier à un livreur* dès le paiement (`assigner_livreur`) ; le livreur
désigné reçoit la fiche et accepte par *Commande reçue* (`accepter_course`).
Une course confiée à un autre livreur repart de zéro. Personne n'écrit
« reçu » à la main (`commande_lignes.recu_le`, verrouillé).

**Qui voit quoi**

| | Les livreurs | Le client |
|---|---|---|
| Au paiement | la demande complète (ci-dessus), tous ceux concernés | rien de nouveau |
| « Commande reçue » | celui qui l'a prise garde la course ; pour les autres, elle disparaît | le nom et le numéro du livreur |
| Toujours | jamais le prix des articles | jamais l'adresse personnelle du livreur |

Base : [`supabase/livraison-parcours.sql`](supabase/livraison-parcours.sql).
Bancs : [`supabase/tests/99zzzzzzzzz-parcours-livraison.sql`](supabase/tests/99zzzzzzzzz-parcours-livraison.sql),
[`supabase/tests/99zzzzzzzzzz-demande-course.sql`](supabase/tests/99zzzzzzzzzz-demande-course.sql),
[`tools/banc-parcours-livraison.mjs`](tools/banc-parcours-livraison.mjs) ;
contrôles 137 et 138 de l'état des lieux.

## Le reste payé à la livraison : déclaré, visible, rendu (3.59.0)

Le client paie l'acompte en ligne, et **le reste au livreur**. Avant, ce
reste passait de main en main sans laisser de trace. Désormais :

**1. Le livreur déclare ce qu'il encaisse.** *Je l'ai remise* ouvre une
feuille : le montant reçu — déjà rempli avec ce que le client devait — et
la façon de payer, **espèces** ou **Mobile Money**. Un autre montant
demande un mot d'explication (« remise de 500 accordée par la boutique »).
Remettre et déclarer se font d'un seul geste (`remettre_course`). En tête
de *Mes courses*, **Ma caisse** dit ce qu'il a encaissé et doit encore
rendre, boutique par boutique (`ma_caisse`).

**2. Le client le voit.** Il reçoit *Reste payé : 7 000 FCFA* (à qui,
comment, quand). Son reçu affiche **Payé à la livraison**, puis
**Commande soldée** (`suivre_commande`). S'il n'a pas payé ce qui est
déclaré, *Ce n'est pas exact* prévient la boutique et BIZZOO
(`contester_encaissement`).

**3. La caisse des livreurs** (*Accueil → Caisse des livreurs*,
`#/caisse`) : livreur par livreur, ce qu'il a encaissé et pas encore
rendu, les écarts avec leur motif, les contestations, et les colis remis
**sans déclaration** depuis une ancienne application. *Argent reçu du
livreur* le marque (`marquer_remis`) ; le livreur en est prévenu.

**Qui voit la caisse** (`tient_la_caisse`) : l'administrateur d'une
boutique, pour l'argent de **ses** colis — y compris encaissé par un
livreur BIZZOO en livraison groupée ; BIZZOO (superadministrateur, compte
de l'enseigne avec le droit *commandes* ou *finances*) : tout. Pas un
modérateur.

Base : [`supabase/reste-livraison.sql`](supabase/reste-livraison.sql)
(table `encaissements`, à coller après `livraison-parcours.sql`).
Bancs : [`supabase/tests/99zzzzzzzzzzz-reste-livraison.sql`](supabase/tests/99zzzzzzzzzzz-reste-livraison.sql),
[`tools/banc-reste-livraison.mjs`](tools/banc-reste-livraison.mjs) ;
contrôle 139 de l'état des lieux.

## Qui livre, vu de la boutique ; le livreur peut refuser (3.59.0)

**Sur chaque commande payée, la boutique voit qui livre** (`livraison_des_commandes`) :

- **Prise par Kodjo · 01 96 …** — le livreur a accepté ; son numéro s'appelle d'un appui ;
- **Confiée à Nadia — en attente de sa réponse** — confiée à la main, pas encore acceptée ;
- **Commande refusée par le livreur** — avec son nom, son motif et l'heure ; le bouton devient **Confier à nouveau** ;
- **En attente d'un livreur** — la demande est partie à tous les livreurs, personne ne l'a encore prise.

**Le livreur peut refuser** (*Refuser la course*, `refuser_course`) tant que le colis n'est pas
parti avec lui (*Je l'ai prise*). La course redevient libre : la boutique est prévenue
(*Commande refusée par le livreur*), la demande se rouvre aux autres livreurs — pas à celui
qui a refusé —, et le client, s'il connaissait déjà son livreur, apprend qu'il change. Quand un
autre livreur la prend, le client reçoit bien **le nouveau** nom et numéro. Chaque refus est
gardé (`refus_courses`).

Base : [`supabase/refus-course.sql`](supabase/refus-course.sql) (à coller après
`reste-livraison.sql`). Bancs : [`supabase/tests/99zzzzzzzzzzzz-refus-course.sql`](supabase/tests/99zzzzzzzzzzzz-refus-course.sql),
[`tools/banc-refus-course.mjs`](tools/banc-refus-course.mjs) ; contrôle 140 de l'état des lieux.

## Le livreur de BIZZOO livre toute la commande (3.59.0)

- **Livreur BIZZOO** (rattaché à aucune boutique) : quand une boutique lui
  confie une course, il reçoit **tous les produits de la commande**, ceux
  des autres boutiques aussi. Les autres boutiques sont prévenues
  (« Un livreur BIZZOO passe récupérer vos produits »). Une part déjà
  confiée au livreur d'une autre boutique lui reste.
- Il accepte d'un seul « Commande reçue » toute la commande ; le client
  reçoit une seule nouvelle avec son nom et son numéro.
- **Livreur d'une boutique** : il ne reçoit que les produits de sa boutique.
- La feuille « Confier » l'explique avant d'appuyer.
- À coller : `supabase/livreur-bizzoo-commande.sql` (après `refus-course.sql`).
  Essai : `supabase/tests/99zzzzzzzzzzzzzz-livreur-bizzoo-commande.sql`.

## Ajouter plusieurs produits d'affilée (3.59.0)

Après « Ajouter le produit », le formulaire se vide (nom, prix, rayon,
photos, vidéo, stock) et une nouvelle référence est proposée : on saisit
le produit suivant tout de suite. Un bandeau dit « … est ajouté » avec le
lien « Voir sa fiche ». Une modification, elle, ramène toujours à la fiche.

## Un revendeur achète comme un client (3.59.0)

Un revendeur validé commande dans l'application à ses prix revendeur,
paie l'acompte en ligne et se fait livrer comme n'importe quel client :
frais de livraison, demande de course aux livreurs, nom et numéro du
livreur, reste payé à la porte, confirmation de réception, suivi de la
commande. La commande porte la marque « Revendeur » chez la boutique.
Essai de bout en bout : `supabase/tests/99zzzzzzzzzzzzzzz-revendeur-client.sql`.

## Le reste se paie par MoMoPay, plus en espèces (3.59.0)

- **BIZZOO enregistre son code MoMoPay** : Réglages → onglet de l'enseigne →
  « MoMoPay — le reste à la livraison » (code marchand et nom affiché).
- **À la porte**, « Je l'ai remise » montre au client, en grand, le code
  MoMoPay de BIZZOO et le montant à payer. Le client paie depuis son
  téléphone et reçoit un SMS ; le livreur saisit le **numéro de la
  transaction**. Sans lui, le colis ne se remet pas.
- **Plus d'espèces** : la base refuse tout autre paiement, un autre montant,
  une transaction déjà utilisée, et l'ancien « Je l'ai remise » sans
  paiement.
- **Le livreur n'a rien en main**, rien à rendre (« Ma caisse » reste vide).
- **Caisse → « MoMoPay à vérifier »** : BIZZOO retrouve chaque transaction
  dans son compte MoMoPay et touche « Vérifié ». La boutique la voit mais ne
  peut pas la vérifier.
- Sans code enregistré, le livreur voit « Appelez BIZZOO » et ne peut pas
  remettre un colis dont le reste est dû.
- À coller : `supabase/reste-momopay.sql` (après `livreur-bizzoo-commande.sql`).

## Qui crée quels comptes (3.59.0)

- **Superadministrateur** : tous les comptes.
- **Administrateur de BIZZOO** : des livreurs (de BIZZOO ou d'une boutique) et
  des revendeurs, qu'il valide.
- **Administrateur d'une boutique** : des modérateurs et des **livreurs de sa
  boutique** (écran Livreurs), et des **revendeurs** (écran Revendeurs →
  « Créer un revendeur ») — la demande reste en attente, **BIZZOO seul la
  valide**. Il ne crée **jamais d'administrateur** ni de superadministrateur,
  ni de livreur de BIZZOO ou d'une autre boutique. La base le refuse.
- **On ne touche pas à son créateur** : un compte créé par un autre — par
  exemple un superadministrateur nommé par un autre — ne peut ni changer le
  rôle, ni désactiver, ni changer le mot de passe, ni supprimer celui qui
  l'a créé, ni ceux au-dessus dans la chaîne. L'écran Comptes l'affiche
  « vous a créé », sans crayon ; la base le refuse par tous les chemins.
- À coller : `supabase/admin-boutique-comptes.sql` (après `reste-momopay.sql`).

## La sonnerie du livreur (3.59.0)

Quand une course attend « Commande reçue » — confiée par la boutique, ou
proposée à tous —, l'application du livreur joue **trois notes qui
montent, trois fois**, plus fort qu'avant, et **fait vibrer le
téléphone**. Elle recommence **toutes les quatre secondes** jusqu'à ce
qu'il touche « Commande reçue » (ou refuse la course). Son coupé dans les
réglages : la vibration reste. Application fermée : c'est la notification
du téléphone qui sonne. Le son se fabrique dans l'application, aucun
fichier à charger (`admin/js/son.js`). Banc : `tools/banc-sonnerie-livreur.mjs`.

**Livraison groupée** : la commande payée sonne chez **tous les livreurs de
BIZZOO** à la fois. Dès que l'un touche « Commande reçue », les autres
reçoivent **« Déjà pris par <son nom> »** en temps réel : leur sonnerie
s'arrête, la carte disparaît, et la mention reste une heure dans « Mes
courses ». Celui qui arrive trop tard lit le même nom. À coller :
`supabase/course-deja-prise.sql`.

## Masquer un produit (3.59.0)

Sur la fiche d'un produit (application admin), **« Masquer le produit »** le
retire du catalogue des clients sans le supprimer : ni catalogue, ni
recherche, ni fiche, ni lien partagé, et il ne se commande plus. Sa fiche,
ses photos, son code et ses ventes restent ; **« Réafficher le produit »** le
remet en vente. Il porte « Masqué » dans la liste des produits, avec qui l'a
masqué et quand. L'administrateur ou le modérateur de la boutique le peut,
même sans le droit de modifier les produits ; BIZZOO sur toutes. À coller :
`supabase/produit-masque.sql`.

## Le suivi des commandes en direct, et le message du catalogue (3.59.0)

- **Chaque modification d'une commande** — paiement, étape (préparée, en
  livraison, remise), livreur confié ou accepté, paiement à la livraison —
  met à jour **tout seul** l'écran de ceux qui la suivent : le client (son
  reçu, « Mes commandes »), l'administrateur et le modérateur de la boutique
  (Commandes, Caisse, accueil), BIZZOO, et le livreur (« Mes courses »).
  La base pousse un **signal** (table `commandes_signaux`) que le temps réel
  ne remet qu'à ceux qui voient la commande ; l'écran se relit à la même
  hauteur, jamais sous les doigts (feuille ouverte, saisie en cours).
  À coller : `supabase/suivi-commandes.sql`.
- **« Catalogue mis à jour » ne s'affiche plus à chaque changement** (une
  vente qui baisse un stock, un horaire de boutique…) : l'écran suit en
  silence, et l'on annonce seulement un produit qui apparaît
  (« Nouveau : … »).

## Le solde de chaque boutique, et ses reversements (3.59.0)

Tout l'argent arrive chez BIZZOO (acompte en ligne, reste par MoMoPay).
Chaque boutique a donc un **solde** chez BIZZOO — écran **Solde de la
boutique** (accueil de l'administrateur, `#/solde`) :

- **Ventes livrées** : ses articles **remis au client**, au **prix BIZZOO**
  de chaque article (la commission de BIZZOO déduite). Les frais de livraison
  n'en font pas partie ; payé mais pas encore livré = **à venir**.
- Moins ce qui a déjà été **encaissé en espèces** par la boutique (l'ancien
  système), moins ce qui est **déjà reversé** et la demande **en attente** =
  **disponible**.
- L'administrateur règle le **numéro de réception** (réseau, numéro,
  titulaire) — BIZZOO est prévenu de chaque changement — et **demande un
  reversement** (pas plus que le disponible).
- Le superadministrateur voit les demandes (**Reversements**, `#/reversements`),
  envoie l'argent, puis touche **« Envoyé »** avec la référence de la
  transaction, ou **refuse** avec un motif (le montant revient au solde). La
  boutique est prévenue.
- Un modérateur ne voit pas le solde. À coller : `supabase/soldes-boutiques.sql`.

## Le code SMS : plus à chaque connexion — le superadministrateur seul, et l'appareil de confiance (3.59.0)

**Clients et livreurs** entrent avec leur **numéro et leur mot de passe**, sans code. Le code
reçu par SMS ne sert plus qu'à **confirmer le numéro une fois**, à l'inscription (ou à la
première connexion d'un livreur que l'administrateur vient de créer), et pour **« Mot de passe
oublié »**.

**L'équipe** (administrateurs, modérateurs, livreurs) entre avec son mot de passe seul. Le
code n'est plus demandé qu'aux **superadministrateurs**, quand l'interrupteur est allumé
(*Réglages → Code SMS du superadministrateur* ; `equipe_en_service`).

**L'appareil de confiance** : sur l'écran du code, la case *Faire confiance à cet appareil
pendant 1 mois*. Cochée, le code n'est plus demandé sur cet appareil pendant 30 jours — le mot
de passe, si. L'appareil garde un jeton tiré au hasard ; la base n'en garde que l'empreinte
(`confier_appareil`, `reconnaitre_appareil`). Dans les Réglages, *Oublier mes appareils de
confiance* fait redemander le code partout (`oublier_appareils`).

Base : [`supabase/connexion-superadmin.sql`](supabase/connexion-superadmin.sql).
Bancs : [`supabase/tests/99zzzzzzzzzzzzz-appareil-confiance.sql`](supabase/tests/99zzzzzzzzzzzzz-appareil-confiance.sql),
`99u-connexion-sms.sql` et `99zzz-connexion-telephone.sql` adaptés ;
[`tools/banc-connexion-equipe.mjs`](tools/banc-connexion-equipe.mjs),
`banc-connexion-sms.mjs` et `banc-connexion-telephone.mjs` adaptés ; contrôle 141.

## Un livreur n'a pas de lien vers l'application admin (3.59.0)

Dans l'application client, la carte **Espace vendeur** (et son bouton *Ouvrir l'espace
vendeur*) n'apparaît plus pour un livreur — ni sur *Mon compte*, ni sous *Mes courses*. Les
administrateurs et modérateurs qui ouvrent l'application client la gardent. Banc :
[`tools/banc-livreur-compte-client.mjs`](tools/banc-livreur-compte-client.mjs).

## Le revendeur choisit les prix qu'il affiche (3.59.0)

Dans *Mon compte → Compte revendeur*, deux boutons : **Prix revendeur** (par défaut) et **Prix
publics**. En « prix publics », le catalogue, la fiche produit et l'accueil montrent les prix
publics, sans rien de revendeur — pour les montrer à son propre client. Ce n'est qu'un
**affichage**, gardé sur le téléphone : la base facture toujours le prix revendeur, et le
**panier** montre toujours ce qu'il paiera (« Total à vos prix revendeur »). Le partage d'un
produit donne toujours le prix public. Banc : [`tools/banc-prix-revendeur.mjs`](tools/banc-prix-revendeur.mjs).

## BIZZOO Personnel : la gestion interne des employés (3.61.0)

Une troisième application, `personnel/`, pour les employés de BIZZOO eux-mêmes — pas pour les boutiques ni les clients. Même base Supabase, même charte, même façon d'écrire (pas de compilation, un module par fichier). En ligne, elle vit à `www.bizzoomarket.com/personnel/` ; sur téléphone, elle s'installe depuis le navigateur (« Ajouter à l'écran d'accueil »).

**Rien de la place de marché n'est touché.** Tout ce que pose `supabase/personnel.sql` commence par `rh_` : ses « profils » (Marketing, Logistique…) ne se confondent jamais avec la table `profils` des comptes de boutique.

### Les rangs

| Rang | Qui | Ce qu'il fait |
|---|---|---|
| CEO | un seul (`rh_employes.ceo`) | valide les employés, les rapports d'activité, les dépenses, les barèmes et la paie ; donne les droits |
| Administration | `administration` | droits sur tous les profils : crée les employés (validés par le CEO), les profils, les missions ; prépare la paie |
| Responsable | `rh_profils.responsable_id` | accepte les missions de son profil, rend leurs rapports, publie les rapports d'activité, demande les dépenses |
| Gestionnaire de la caisse | `rh_caisse.gestionnaire_id` | décaisse les dépenses approuvées et les prêts validés, sert les retraits (FeexPay ou caisse) |
| Employé | tout employé en poste | ses mails, la discussion de son profil, ses fiches de paie, son solde, ses coordonnées |

**Ce qu'un employé voit des autres** (`personnel-confidentialite.sql`) : rien de sa fiche. L'annuaire, qui sert à choisir à qui écrire, ne lui donne que le nom, le poste, le profil, l'e-mail et le téléphone **professionnels** de chacun ; le matricule, le sexe et le numéro personnel (celui de la connexion) sont réservés à l'administration, au CEO et au superadministrateur. Une fiche de paie ne se lit que par son employé (une fois validée) et par l'administration ; le gestionnaire de la caisse ne les lit pas.

Tout découle de `rh_moi()` : l'employé **en poste** du compte connecté. Une fiche en attente, refusée ou sortie n'a aucun droit.

**Le premier CEO** s'installe une seule fois, par un superadministrateur de BIZZOO qui ouvre l'application alors qu'aucun CEO n'existe encore. Deux choix : « Je suis le CEO » (`rh_devenir_ceo`), ou « Désigner le CEO » (`rh_designer_ceo`) : nom et adresse professionnelle du CEO, premier mot de passe si cette adresse n'a pas encore de compte, et, en option, l'inscription du superadministrateur lui-même dans l'administration pour tout préparer en attendant. Dès qu'un CEO existe, la porte est fermée.

### Les circuits

- **Employé** : créé par l'administration → « en attente » → validé ou refusé (avec motif) par le CEO. Ensuite, « Créer l'accès » : un compte de connexion à son adresse `@bizzoomarket.com` (inscription avec `compte: personnel`, puis `rh_rattacher_compte`, qui ne rattache que le compte de SA propre adresse). Un compte BIZZOO existant à cette adresse est simplement rattaché. Le salaire d'un employé en poste et les droits ne changent que par le CEO ; l'employé ne touche qu'à son téléphone, son adresse et son e-mail personnel.
- **Mission** : créée par l'administration pour un profil, avec une échéance → acceptée (ou refusée, motif) par le responsable → rapport rendu → clôturée, ou renvoyée « à reprendre ». En retard : le tableau de bord le dit.
- **Rapport d'activité** : brouillon du responsable → publié → validé ou rejeté (commentaire) par le CEO. Validé, tous les membres du profil le lisent.
- **Dépense** (`personnel-depenses.sql`) : demandée par **tout employé** (motif, montant, détails) → validée ou refusée (motif) par le **responsable de son profil** → approuvée ou refusée par le **CEO** → décaissée par l'**habilité** (mode, référence), jamais sa propre demande. Statuts : « En attente du responsable » (`demandee`), « En attente du CEO » (`validee_responsable`), « En attente de décaissement » (`approuvee`), « Décaissée », « Refusée », « Annulée ». Sans responsable au-dessus du demandeur (pas de profil, profil sans responsable, ou demandeur responsable lui-même), la base envoie la demande droit au CEO. Le profil de la dépense est celui du demandeur, posé par la base. Modifiable et annulable par le demandeur tant que personne ne l'a validée ; chaque étape garde qui et quand, et la fiche les montre en quatre étapes. Le menu Dépenses s'ouvre à tous les membres (Paramètres peut le restreindre).
- **Discussions** (`personnel-messages.sql`) : « Nouveau message » propose trois façons d'écrire, à tout employé qui a les discussions : **à tout le monde** (le fil général « Tout le monde », que tous lisent, en tête de la liste), **à un profil** (le sien ou n'importe quel autre : qui écrit à un autre service en lit ensuite le fil, pour voir les réponses, sans en devenir membre), **à un employé** en privé (n'importe lequel, avec recherche). Un message privé reste privé : l'administration ne le lit pas.

### La paie

- **Le 5 du mois**, à 7 h (heure du Bénin), `pg_cron` calcule les fiches **du mois écoulé** pour tous les employés en poste ; elles attendent la validation du CEO. Si le 5 est manqué, le passage suivant rattrape, et l'application aussi à l'ouverture (`rh_paie_a_jour`) ; l'administration peut « Calculer / Recalculer » à tout moment. (Jusqu'à la 3.66, c'était le dernier jour du mois.)
- Une fiche : salaire de base au prorata des jours (embauche ou sortie en cours de mois), primes et indemnités (imposables ou non), cotisations validées, impôt par tranches validé, retenues, puis les avances — une mensualité par paie, jamais au-delà de ce qui reste : la fiche ne descend pas sous zéro.
- **Aucun taux n'est fourni**, par décision du propriétaire : CNSS, impôt et autres cotisations se saisissent dans Paie → Barèmes, et ne comptent qu'une fois validés par le CEO. Toute modification les renvoie à sa validation.
- Le CEO valide le mois : les fiches sont figées (rien ne les recalcule plus) et l'employé voit la sienne. **Le 10 du mois suivant**, chaque fiche validée se **verse sur le solde** de son employé (voir plus bas) ; validée après le 10, elle s'y verse aussitôt. Une fiche validée mais pas encore versée peut être rouverte par le CEO. Une fiche ne se paie plus « de la main à la main » : `rh_payer` et `rh_payer_fiche` répondent qu'il faut passer par le solde.
- Chaque fiche garde une copie de ce qu'était l'employé (poste, profil, matricule) : un changement de poste ne réécrit pas le passé.

### Les mails

La fonction Edge `rh-messagerie` parle IMAP (`mail.bizzoomarket.com:993`) et SMTP (`:465`) au serveur de LWS. L'employé saisit une fois le mot de passe de sa boîte : il est vérifié auprès du serveur, puis **chiffré (AES-GCM)** dans `rh_boites_mail`, une table sans aucune règle de lecture — ni l'application ni le CEO ne la lisent ; seule la fonction, avec la clé de service, y accède. L'adresse ouverte est toujours celle de la fiche de l'employé connecté, jamais une adresse reçue dans la requête. Un message envoyé est rangé dans « Envoyés » (LWS ne le fait pas lui-même).

Le HTML d'un mail s'affiche dans un cadre isolé (sans script, sans accès à la page), images distantes bloquées tant qu'on ne clique pas « Afficher les images ».

### Les statistiques (3.61.1)

Menu « Statistiques » : un sommaire, puis six sous-menus, chacun sur sa page avec son choix de période (gardée quand on passe de l'un à l'autre ; sur ordinateur, ils s'affichent aussi sous « Statistiques » dans le menu de gauche) : Commandes (payées, passées, en attente, articles, revendeurs, jour par jour), Boutiques qui vendent le plus, Produits les plus vendus, Livraisons (états des articles payés, délai moyen paiement → réception), Livreurs, Service après-vente et avis (réclamations par état et par motif, avis et notes). Adresses : `#/statistiques/<sous-menu>?p=30j` ou `?du=…&au=…`. Une commande compte au jour de son paiement ; une ligne annulée ne compte jamais.

C'est `rh_statistiques` (`supabase/personnel-statistiques.sql`) qui décide de ce qui sort de la base : le CEO voit tout, **la marge de BIZZOO comprise** ; l'administration tout sauf la marge ; les autres, les seuls sous-menus que le menu Paramètres ouvre à leur profil, **sans aucun montant** (un sous-menu fermé ne sort même pas de la base : « Livreurs » seul ne donne que le classement des livreurs). Les statistiques de l'application admin restent en place.

### Le suivi des commandes

Menu « Suivi commandes » : le tableau de bord demandé par BIZZOO (document « Tableau de bord de suivi des commandes » et classeur « Suivi commandes »). `supabase/personnel-suivi.sql`, écran `personnel/js/vues/suivi.js`, export `personnel/js/xlsx.js`.

- **La pastille du menu** : hors du suivi, le nombre de commandes en alerte des 60 derniers jours (`rh_suivi_alertes_nb`) ; dans le tableau du suivi, exactement le nombre « en alerte » affiché, période et filtres compris. Une commande dont la seule alerte est une course refusée ne compte pas.
- **Les chiffres du tableau**, au-dessus de lui et recalculés à chaque filtre (période, statut, zone, recherche, alertes) : nombre de commandes, coût total des commandes, coût total de la livraison, reste à encaisser (ces trois montants seulement pour qui a droit aux montants), commandes en alerte, et le nombre de commandes par statut — un clic sur un statut filtre le tableau.
- **Un tableau, une commande par ligne** (toute la largeur de l'écran, lignes verticales, tri par clic sur l'en-tête, n° de commande figé à gauche ; chaque colonne s'élargit en tirant le bord droit de son en-tête, largeurs gardées dans le navigateur, double clic sur ce bord pour revenir aux largeurs d'origine) : n°, date et heure, client / téléphone / zone, articles, marchands, frais, total, reste à encaisser, livreur, statut, confirmation du client, délai de livraison, observations. Filtres par période, statut, zone, alertes, recherche libre. Fiche par commande : articles par marchand, chronologie, incidents, réclamations, courses refusées.
- **Les 14 statuts du document**, calculés : ceux que la place de marché connaît (nouvelle, vue, préparée, en livraison, déclarée livrée, « je l'ai reçu » du client, annulée, réclamation « non reçu ») et ceux que l'administration note elle-même dans le suivi (colis récupéré, livraison échouée, retour en cours, retourné au marchand, clôturée). Une commande à plusieurs marchands prend le statut de l'article le moins avancé, sauf contestation, échec ou retour, qui priment.
- **Les alertes, à part du statut** (seuils réglables, en heures) : pas vue par le marchand, préparation en retard, livraison en retard, livrée sans confirmation du client, livraison contestée, échec ou retour, incident ouvert, course refusée, encaissement contesté.
- **Incidents et clôture** : une commande ne se clôture pas tant qu'un incident reste ouvert, qu'un client conteste, ou qu'un article n'a pas fini son parcours. Seule l'administration rouvre.
- **Le journal des étapes** (`rh_journal_lignes`), tenu par deux déclencheurs sur `commande_lignes` et `commandes` qui ne bloquent jamais une commande (une erreur du journal est avalée). Il donne les délais vu → préparé → reçu ; les commandes d'avant son installation n'ont que les dates déjà connues, marquées « reconstitué ».
- **Les zones** : lues dans l'adresse libre du client avec le référentiel du découpage du Bénin (77 communes, 152 quartiers et arrondissements), quartier d'abord ; l'administration corrige la zone d'une commande et ajoute les quartiers non reconnus.
- **Le bilan** par jour, semaine ou mois : commandes reçues, payées, livrées et confirmées, en cours, en retard, contestées, annulées (et motifs), échecs et retours, reste à encaisser ; par livreur, par marchand, par zone ; heures et jours de pointe ; clients nouveaux et fidèles.
- **L'export Excel** (.xlsx fabriqué dans le navigateur, sans bibliothèque) : « Suivi commandes » au format exact du classeur de BIZZOO, « Détail par marchand » (une ligne par article), « Bilan ». Les montants restent des nombres.
- **Qui** : le CEO et l'administration, montants compris ; les profils à qui le menu Paramètres ouvre « Suivi des commandes » (responsable seul ou tous les membres), sans aucun montant.

### Le menu Paramètres

Réservé à l'administration (CEO compris). `supabase/personnel-parametres.sql`, écran `personnel/js/vues/parametres.js`.

- **Accès aux menus** : pour chaque profil, menu par menu, « Fermé », « Responsable » (le responsable du profil seul) ou « Tous les membres » (le responsable compris). Menus réglables : Mails, Discussions, Missions, Rapports, Dépenses (responsable seulement : c'est lui qui les demande), Suivi des commandes, chacun des six sous-menus des Statistiques, et l'Annuaire des employés (en lecture : nom, poste, profil, contact pro ; jamais le salaire). Profils, Paie et Paramètres ne s'ouvrent à aucun profil. Une vue d'ensemble montre tous les profils d'un coup.
- **La base applique ces accès elle-même** : `rh_acces_menus` (écrite seulement par `rh_regler_acces`, qui note qui a réglé), `rh_acces(profil, menu)` et `rh_menu_ouvert(menu)`, consultées par les règles RLS des missions, rapports, dépenses et messages, par les fonctions des missions et des rapports, par `rh_conversations`, `rh_suivi_acces`, `rh_statistiques` et par la fonction `rh-messagerie`. Fermer un menu le ferme vraiment, pas seulement à l'écran.
- **Le premier passage reprend les droits d'avant** : mails, discussions, missions et rapports à tous les membres, dépenses au responsable, et les anciennes rubriques cochées dans Profils (statistiques, suivi) au responsable. Un profil créé ensuite reçoit les mêmes accès de base. Un employé sans profil garde ses mails et ses messages directs.
- **Entreprise** : raison sociale, site, adresse, téléphone, e-mail, IFU, RCCM, n° employeur CNSS, imprimés en tête des bulletins de paie (`rh_entreprise`). Rien n'est inventé : seuls le nom et le site sont remplis d'avance.
- **Autres réglages** : les liens vers les réglages qui vivent ailleurs (délais et zones du suivi, barèmes de paie, profils, droits des employés, boîte mail).

### Se connecter par son numéro ; la fiche complète

`supabase/personnel-fiches.sql`.

- **Connexion** : chaque employé entre avec **son numéro** (01 + 8 chiffres) et le **code reçu par SMS** (Supabase Auth, hook `hook-sms-auth`). L'application demande d'abord à la base si ce numéro est celui d'un employé en poste (`rh_telephone_employe`) : pas de SMS ni de compte pour un autre numéro. Le compte rejoint alors la fiche qui porte ce numéro (`rh_rattacher_par_telephone`) ; une fiche déjà reliée à un autre compte ne change pas de main. **Appareil de confiance** : coché, la session se garde 7 jours (puis un nouveau code) ; sinon elle ne vit que le temps de l'onglet, et un code est redemandé à chaque connexion. L'e-mail et le mot de passe restent possibles (« Se connecter avec une adresse e-mail »).
- **Le mot de passe de départ** (`personnel-activation.sql`) : les employés importés reçoivent un compte « numéro + mot de passe de départ », le même pour tous, donné de vive voix et écrit nulle part dans ce dépôt (le fichier qui crée les comptes reste hors du dépôt). Ce compte n'est relié à sa fiche (donc n'ouvre rien) qu'une fois que l'employé a choisi son propre mot de passe : `rh_activer_compte` vérifie que l'empreinte enregistrée n'est plus celle de départ. L'écran de connexion propose numéro + mot de passe, avec le code SMS en secours ; le code SMS ne permet pas d'éviter l'étape. Chacun change ensuite son mot de passe dans « Mon compte ».
- **Un mot de passe provisoire donné par l'administration** (`personnel-mot-de-passe.sql`, fonction Edge `rh-mot-de-passe`) : sur la fiche d'un employé, bouton « Mot de passe ». La base décide du droit (`rh_mdp_preparer`, avec la session de l'administrateur : pas sa propre fiche, pas celle du CEO sauf par lui ou le superadministrateur), la fonction change le mot de passe avec la clé de service (qui ne quitte pas le serveur), puis `rh_mdp_conclure` détache le compte jusqu'à ce que l'employé choisisse le sien, ferme ses sessions et note le geste dans l'historique de la fiche. C'est le même compte que l'application BIZZOO s'il y en a un.
- **La fiche** gagne téléphone pro, équipement confié, langue, « marié(e) », moto ; le sexe peut rester vide. **Ethnie et religion** sont dans `rh_employes_sensibles`, lisibles et modifiables par le CEO et le superadministrateur seuls.
- **Qui modifie** : le superadministrateur comme le CEO (droits, salaire). L'employé complète lui-même, dans « Mon compte », son e-mail, son sexe, sa date de naissance, son lieu de résidence, sa langue, « marié(e) » et sa moto ; **pas son numéro** (c'est son identifiant), que l'administration change.
- **Le personnel de BIZZOO** a été importé le 25/10/2026 depuis son fichier (feuille « FICHIER DG »), hors du dépôt : 24 employés, 7 responsables, 6 profils ajoutés aux 5 existants.

### La caisse

`supabase/personnel-caisse.sql` ; écran `personnel/js/vues/caisse.js`.

- **Quatre compartiments** : espèces, MTN Mobile Money, Moov Money, Celtiis Cash ; leur somme fait le solde. Le menu Caisse montre le solde à l'instant (total et par compartiment) et, pour une période, le solde de début, les entrées, les sorties, le solde de fin et la liste des mouvements (exportable en Excel).
- **Le gestionnaire**, désigné par le CEO (`rh_designer_gestionnaire_caisse`), tient la caisse : **lui seul décaisse les dépenses approuvées, les prêts, et remet les salaires retirés à la caisse** (`rh_peut_decaisser()` = être ce gestionnaire ; la case « habilité à décaisser » de la fiche employé a disparu). Chaque décaissement ou paiement se **répartit** entre compartiments (« 20 000 en espèces + 30 000 sur MTN », `rh_decaisser` / `rh_payer`) : la somme doit tomber juste, et aucun compartiment ne passe sous zéro (la base refuse). Des déclencheurs font sortir de la caisse TOUT décaissement et TOUT salaire payé, quel que soit le chemin.
- **Les entrées** : apports du CEO ou d'une autre source nommée (`rh_caisse_apport`, par le gestionnaire ou le CEO). Le gestionnaire **déplace** l'argent entre compartiments (retrait Mobile Money en espèces…), frais de l'opérateur compris (`rh_caisse_transfert`).
- **Rien ne s'efface** : `rh_caisse_mouvements` est figée (ni modification, ni suppression) et fermée à la lecture directe ; chaque mouvement garde le solde qu'il laisse et qui l'a fait. Une erreur ou un écart de comptage se corrige par un **ajustement** du CEO, avec motif (`rh_caisse_ajustement`).
- **Qui la voit** (`rh_caisse_acces`) : le CEO, le gestionnaire, le superadministrateur, et les profils à qui Paramètres ouvre « Caisse (consultation) » ; l'administration n'y entre pas d'office. En consultation, on ne fait rien, et un salaire ne dit pas de qui il est.

### L'accueil : la place de marché d'un coup d'œil

`supabase/personnel-accueil.sql` (`rh_accueil_chiffres`) ; écran `personnel/js/vues/accueil.js`.

Sous les tâches de la personne connectée (validations, prêts et retraits, messages…), l'accueil montre « BIZZOO en <mois> », le mois en cours et aujourd'hui (heure du Bénin), en cinq rubriques ; chaque tuile mène à l'écran qui détaille :

- **Commandes** : payées ce mois et aujourd'hui, reçues, en attente de paiement, annulées ou échouées, articles vendus, commandes de revendeurs ; ventes du mois et du jour, panier moyen, frais de livraison encaissés, remises ; marge de BIZZOO.
- **Livraisons** : confirmées par le client ce mois ; articles à préparer, prêts, en cours de livraison, livrés sans confirmation ; livreurs inscrits et en course.
- **Clients** : inscrits, nouveaux ce mois et aujourd'hui, ayant acheté ce mois, numéros vérifiés, revendeurs et demandes en attente.
- **Boutiques et produits** : boutiques enregistrées, ouvertes, nouvelles, ayant vendu ce mois ; produits en ligne, disponibles, en rupture, nouveaux, masqués.
- **Avis et SAV** : avis du mois, note moyenne, réclamations à traiter et du mois.

Mêmes droits que les Statistiques, décidés par la base : les nombres pour l'administration, le superadministrateur et les profils à qui Paramètres ouvre les statistiques des commandes ; les montants pour l'administration et le superadministrateur ; la marge pour le CEO et le superadministrateur. Les autres ne voient que leurs tâches.

**Les écrans resserrés** : la barre de période (raccourcis, « du … au … », Afficher) tient sur une ligne et est commune au suivi, aux statistiques et à la caisse (`UI.lignePeriode` / `UI.barrePeriode`) ; tuiles et espaces entre les blocs réduits partout.

### Le solde, les prêts et les retraits

`supabase/personnel-solde.sql` ; écrans `personnel/js/vues/solde.js` (« Mon solde », tout employé, le CEO compris) et `personnel/js/vues/prets.js` (« Prêts et retraits », le CEO et le gestionnaire de la caisse) ; fonction Edge `supabase/functions/rh-reversement`.

- **Le solde** de chaque employé est la somme de mouvements figés (`rh_solde_mouvements` : ni modification, ni suppression, chacun garde le solde qu'il laisse). Il reçoit le 10 le net de la paie validée : **salaire + primes − retenues − prêt** (cotisations et impôt validés déduits). Une fiche négative laisse une dette, reprise sur les versements suivants. Le CEO voit le solde de chacun, et le total dû aux employés.
- **Primes et retenues du CEO** (ou du superadministrateur), depuis la fiche de l'employé : `rh_octroyer` les inscrit sur sa **prochaine paie** (`rh_prochain_mois_paie` : le mois écoulé tant que sa fiche n'est pas validée, sinon le mois en cours ; jamais avant l'embauche). Une prime est imposable. On la retire tant que la paie n'est pas validée.
- **Le prêt** : l'employé le demande (montant, motif ; un seul en attente à la fois) → le **CEO** le valide ou le refuse (motif) → le **gestionnaire de la caisse** le décaisse, réparti entre compartiments (nature « pret » dans la caisse), jamais le sien → la **prochaine paie le reprend en une fois** (une avance d'une mensualité ; si le salaire ne suffit pas, le reste attend la paie suivante, comme toute avance).
- **Le retrait** : l'employé retire **tout ou partie** de son solde, quand il veut, et le montant quitte aussitôt son solde (deux demandes ne passent pas sur le même argent). Deux moyens :
  - **Mobile Money** (MTN, Moov, Celtiis ; 50 FCFA au moins) : le gestionnaire clique « Envoyer par FeexPay ». La fonction `rh-reversement` fait vérifier son droit par la base, avec SA session (`rh_retrait_preparer`, qui fait passer le retrait d'un coup à « envoi » : deux clics, un seul virement), prend montant et numéro dans la base, appelle le **payout V2** de FeexPay (`/api/payouts/public/transfer/global` pour MTN et Moov, `/api/payouts/public/celtiis_bj` pour Celtiis ; numéro 229 + 10 chiffres ; motif de 30 caractères sans ponctuation), puis lit le statut (`/api/payouts/status/public/<référence>`). **« Payé » ne s'écrit que sur cette lecture, au montant exact** ; pg_cron fait revérifier toutes les 10 minutes ce qui est en cours (`rh-reversements-verifier`). Un refus (4xx) est sûr : l'argent revient sur le solde. Une panne, un délai dépassé ou une réponse sans référence rendent le retrait **« incertain »** : il ne repart jamais seul (on paierait deux fois) ; le CEO tranche après avoir regardé le tableau de bord FeexPay (`rh_retrait_trancher`, constat à l'appui). L'argent part du compte marchand FeexPay de BIZZOO, pas de la caisse.
  - **La caisse** : le gestionnaire remet l'argent et le répartit entre compartiments (`rh_servir_retrait`, nature « salaire »). Il peut ainsi servir un retrait demandé en Mobile Money (en l'envoyant lui-même depuis le compartiment MTN).
  - Le gestionnaire ou le CEO peut refuser un retrait (motif), l'employé l'annuler tant qu'il attend : le montant revient sur le solde. Le gestionnaire ne sert jamais son propre retrait.
- **Le calendrier**, une seule tâche `pg_cron` chaque matin à 7 h (`rh-paie-quotidienne`) : la paie du mois écoulé à partir du 5, puis le versement des fiches validées dont le 10 est passé (`rh_crediter_salaires`). Elle remplace `rh-paie-fin-de-mois`.
- **Secrets** : ceux du paiement des commandes (`FEEXPAY_TOKEN`, `FEEXPAY_SHOP`) ; facultatif `RH_REVERSEMENT_RESEAUX='mtn,moov'` pour fermer un réseau sans redéploiement. **FeexPay peut n'accepter les reversements que depuis des adresses IP déclarées** (tableau de bord FeexPay, onglet « IP List ») : les fonctions de Supabase n'ont pas d'adresse fixe. Un refus pour cette raison rend l'argent sans dommage, mais aucun reversement ne passera tant que FeexPay ne l'autorise pas. Le premier essai se fait avec un petit montant réel, sur chaque réseau : il n'y a pas de bac à sable.
- **Banc** : `tools/eprouver-reversement.sh` (FeexPay et la base en doublures, aucun appel ne sort) ; les essais de la base, section 21.

### Localiser un livreur

`supabase/localiser-livreurs.sql` ; écran `personnel/js/vues/localiser.js` ; côté livreur `admin/js/suivi-position.js` et le service Android `ServiceSuiviPosition`.

- **La carte** (menu « Localiser un livreur », clé `livreurs` réglable dans Paramètres) : OpenStreetMap par Leaflet, embarqué dans `personnel/vendor/leaflet`, sur tout l'écran (bouton « Plein écran »), relue toutes les 10 secondes. Chaque livreur avec sa dernière position (« il y a 15 s »), et pour chaque course en cours le point du client — quand il l'a donné en commandant (livraison au kilomètre) — relié par un trait, avec la distance : à vol d'oiseau multipliée par le coefficient de route de la livraison au km, d'où « environ ». Aucun montant. `rh_localiser_livreurs()`.
- **Depuis le suivi des commandes** : dans la fiche d'une commande, « Voir sa position » à côté du livreur ouvre la même carte centrée sur lui (`#/livreurs/<id>` ; `rh_suivi_donnees` donne `livreur_id`).
- **D'où vient la position** : tant qu'il a une course en cours (ligne confiée, commande payée, pas encore remise), BIZZOO Admin demande un **jeton de suivi** (`ouvrir_suivi_livreur`, 64 caractères, gardé en empreinte sha256, 16 h) et le passe au service Android au premier plan (notification « Course en cours »), qui envoie la position toutes les 20 s (et toutes les 2 min s'il ne bouge pas) à `position_en_course` — **même application fermée**. Le jeton ne permet que d'écrire la position de ce livreur ; il ne tient pas sa session (deux renouvellements concurrents de session le déconnecteraient). Quand la base répond « plus de course », le service s'arrête de lui-même et le jeton disparaît. Dans un navigateur, c'est la page qui envoie, tant qu'elle est ouverte. Une écriture toutes les 5 secondes au plus ; une position impossible est ignorée.
- **Limites** : il faut que le livreur ouvre l'écran de ses courses une fois après l'attribution (le service démarre là ; Android refuse de lancer un suivi de position depuis l'arrière-plan). Sans réseau ni GPS, la carte dit « pas de nouvelle position depuis plus de 5 min ». Le point du client n'est connu que s'il a touché « Utiliser ma position » en commandant ; sinon la carte affiche son adresse écrite.

### Le menu Livreurs ; bloquer un livreur (3.67.0)

`supabase/personnel-livreurs.sql` ; écran `personnel/js/vues/livreurs.js` (`#/liste-livreurs`).

- **La liste** : tous les livreurs, de BIZZOO et des boutiques, avec leurs étiquettes (bloqué, compte désactivé, pas encore validé, en course), et sur la période choisie leurs courses, livrées, refus et — pour l'administration — leurs gains. Recherche, filtres (BIZZOO, des boutiques, en course, bloqués) et tuiles de synthèse. `rh_livreurs(depuis, jusqu)`.
- **La fiche** (un clic sur un livreur) : qui il est, sa dernière position, ses chiffres (courses, livrées, en cours, annulées, réception confirmée par le client, refus, délai moyen pour accepter, délai du paiement à la réception, encaissements contestés ; gains et encaissements pour l'administration), ses 50 dernières courses, ses refus et l'historique de ses blocages. `rh_livreur_fiche(livreur, depuis, jusqu)`.
- **Qui le voit** : l'administration, le superadministrateur, et les profils à qui Paramètres ouvre « Localiser un livreur » ou les statistiques des livreurs (`rh_voit_livreurs`). Les montants : l'administration seulement.
- **Bloquer** (l'administration seule, motif obligatoire ; `rh_bloquer_livreur`) : la colonne `profils.courses_bloquees`, que seule cette fonction peut poser (déclencheur `profils_garde_blocage` : une boutique qui modifie son livreur ne peut pas y toucher). Bloqué, le livreur ne reçoit plus aucune demande (`candidats_course`, donc aussi `courses_proposees` et `prendre_course`), et aucune boutique ne peut lui confier de course (`assigner_livreur`). Ses courses **pas encore parties** (nouvelle, vue, préparée) lui sont retirées comme s'il les avait refusées — sans compter dans ses refus : la boutique est prévenue et la confie à un autre, le client aussi s'il connaissait déjà son livreur. Celles **déjà en route**, il les termine. Il garde son compte (ses courses passées, ses encaissements). Il est prévenu (« Courses suspendues »), et au déblocage (« Courses rétablies »). Chaque blocage et déblocage est gardé dans `livreurs_blocages` (auteur, motif, date), lisible seulement par ces fonctions.

### Photos, vidéos et audio dans les discussions ; tout s'efface à 7 jours

`supabase/personnel-pieces.sql`, fonction Edge `supabase/functions/rh-menage`.

- **Joindre** : le trombone choisit une photo, une vidéo ou un fichier audio ; le micro enregistre un message vocal (5 minutes au plus). Une pièce par message, texte facultatif ; 50 Mo au plus. Une photo plus grande que 1 600 px est réduite en JPEG avant l'envoi.
- **Le seau `rh-pieces` est privé.** Chacun dépose dans SON dossier (`<id de l'employé>/…`) et seulement s'il a les discussions ; le message ne peut citer qu'un fichier de son auteur, présent, jamais déjà cité, et dont le type (lu dans le stockage, pas dans la requête) est image, vidéo ou audio. On lit un fichier par un lien signé d'une heure, que la base n'accorde qu'à qui voit le message : la note vocale d'un message privé reste privée, même pour l'administration.
- **Tout message s'efface 7 jours après son envoi**, texte et pièce : pg_cron appelle `rh_purger_messages` chaque heure (`rh-messages-7-jours`), puis la fonction `rh-menage` (`rh-pieces-menage`, par pg_net), qui efface du stockage les fichiers qu'aucun message ne cite plus (ceux des messages partis, et les envois abandonnés depuis plus d'une heure). Le stockage ne s'efface que par son API : d'où la fonction. Elle ne lit rien dans la requête et n'efface que ce que la règle efface de toute façon : déployée **sans** vérification du jeton (`--no-verify-jwt`).

### Bloquer, supprimer un employé

`supabase/personnel-gestion.sql`. Sur la fiche d'un employé, le CEO et le superadministrateur de BIZZOO (`est_super()`, même s'il n'est pas le CEO) ont trois boutons ; l'administration ne les a pas. Le CEO ne se bloque ni ne se supprime, personne n'agit sur sa propre fiche, et chaque geste demande un motif.

- **Bloquer** (`rh_bloquer_employe`) : état `bloque`. `rh_moi()` ne le reconnaît plus : il n'ouvre plus rien, et l'écran de connexion lui dit que son accès est bloqué. **Sa paie continue** (il reste employé), et il reste responsable de son profil. **Débloquer** le remet en poste.
- **Supprimer** (`rh_supprimer_employe`) : sans paie validée ni avance, la fiche est effacée entièrement. Sinon, elle est **archivée** (état `supprime`, filtre « Archivés ») : nom, matricule, n° CNSS et paie validée restent pour la comptabilité et la CNSS ; accès, adresse pro, coordonnées, messages, boîte mail et brouillons de paie sont effacés. Sans retour.
- **Le journal** (`rh_journal_employes`, lu par l'administration) garde qui a bloqué, débloqué ou supprimé, quand et pourquoi ; il s'affiche sur la fiche (« Historique de l'accès »).

### Les statistiques internes

Cinq sous-menus de plus dans Statistiques, mois par mois (l'année en cours par défaut), chacun avec ses tableaux exportables en Excel. `rh_finances` (`supabase/personnel-gestion.sql`).

- **Salaires** (administration) : coût employeur, brut, net, charges patronales, cotisations et impôt, déjà payé, validé à payer, avances accordées et encore dues ; par mois, par profil, employés / stagiaires. Seules les fiches validées comptent ; les fiches à valider sont signalées à part.
- **Dépenses** (administration) : demandé, approuvé, décaissé par mois ; par profil ; les plus grosses ; ce qui attend le CEO ou le décaissement ; délai moyen de décision.
- **Effectifs** (administration) : en poste, masse et moyenne des salaires de base, âge et ancienneté moyens, répartition par profil, statut, sexe, niveau d'étude ; embauches et sorties par mois.
- **Missions et rapports** (administration) : missions rendues à temps ou en retard, en retard aujourd'hui, délai de réponse des responsables, par profil ; rapports d'activité et délai de validation.
- **Revenus et résultat** (CEO et superadministrateur seuls) : encaissé, reversé aux boutiques, marge, frais de livraison, remises, gains des livreurs. **Revenus = marge + frais de livraison − remises − gains des livreurs ; résultat = revenus − salaires (coût employeur des fiches validées) − dépenses décaissées.** Une estimation de gestion, pas une comptabilité : l'écran le dit.

### Mise en service

1. **La base** : exécuter `supabase/personnel.sql` dans l'éditeur SQL de Supabase (il se suffit, et se rejoue sans rien casser). Il active `pg_cron` et programme `rh-paie-fin-de-mois`.
2. **Le secret** (conseillé) : Supabase → Edge Functions → Secrets → `RH_MESSAGERIE_CLE`, une longue phrase aléatoire. Sans lui, la clé dérive de la clé de service ; le changer oblige chacun à ressaisir le mot de passe de sa boîte, rien d'autre.
3. **La fonction** : `supabase functions deploy rh-messagerie` (avec la vérification du jeton).
4. **Le CEO** ouvre `/personnel/` avec son compte superadministrateur et devient le CEO ; puis il crée les profils, l'administration, les employés.

Les chantiers suivants ont chacun leur fichier, à exécuter après : `personnel-statistiques.sql`, `personnel-suivi.sql`, `personnel-parametres.sql`, `personnel-gestion.sql`, `personnel-pieces.sql`, `localiser-livreurs.sql`, `personnel-depenses.sql`, `personnel-caisse.sql`, `personnel-fiches.sql`, `personnel-solde.sql`, `personnel-sexe-statistiques.sql`, `personnel-accueil.sql`, `personnel-messages.sql`, `personnel-confidentialite.sql`, `personnel-activation.sql`, `personnel-mot-de-passe.sql`, `personnel-livreurs.sql` (puis déployer `rh-menage` et `rh-reversement` avec `--no-verify-jwt` ; après `personnel-parametres.sql`, redéployer `rh-messagerie`, qui consulte l'accès au menu Mails).

Essais : `supabase/tests/99zzzzzzzzzzzzzzzzzzzz-personnel.sql` (constats : chaque porte, et une paie au franc près calculée à la main).

## L'ergonomie revue : ce qui débordait, et pourquoi (3.62.0)

Le propriétaire a envoyé une dizaine de captures de son téléphone : des
boutons dont le texte passait sur deux lignes avec l'icône seule collée
à gauche (« Demandes des boutiques », « Exporter une sauvegarde »,
« Changer mon mot de passe »), des titres coupés (« Mon co… »,
« Inform… », « Comptes rev… »), la tuile « IMPACT INFORMATIQUE » des
Réglages coupée au bord de l'écran, la barre du bas dont « Réglages »
sortait de l'écran, une adresse web qui traversait sa carte, la pastille
« Sur commande » passée sous le cœur d'une carte produit, le numéro
d'une commande plié en « BZ- » / « 000062 ».

### D'où venaient les défauts

**Son téléphone est réglé sur de grands caractères.** Android multiplie
alors toutes les tailles de police de l'application (ici ≈ 1,3 : le
« textZoom » du WebView suit le réglage du système) sans toucher aux
largeurs ni aux marges. Tout ce qui tenait *juste* sur un écran de
360 px débordait. Ce n'est pas une anomalie à corriger côté téléphone :
un client qui a choisi de grands caractères doit avoir une application
qui les accepte.

Deux mécanismes se répétaient derrière la plupart des captures :

1. **Un seul élément plus large que l'écran élargit la page entière.**
   Le navigateur la laisse défiler de côté, et les barres fixes du haut
   et du bas, calées sur cette page élargie, sortent de l'écran. C'est
   la tuile des Réglages (une colonne de grille `1fr` refuse d'être plus
   étroite que « IMPACT INFORMATIQUE » écrit sur une ligne) qui coupait
   « Réglages » tout en bas, et l'adresse web qui coupait « Recherche »
   chez le client.
2. **Un bouton en « flex » fait de son texte une boîte à part.** Dès
   qu'il se plie sur deux lignes, cette boîte prend toute la largeur,
   le texte se centre dedans, et l'icône reste seule au bord gauche.
   CSS n'a pas de boîte « à la taille de son texte une fois plié » :
   la seule mise en page qui donne « [icône] Demandes des » puis
   « boutiques » dessous, centrées, est celle d'un texte ordinaire —
   l'icône coulant dans la ligne comme une lettre.

### Ce qui change

- **Deux garde-fous**, dans les deux applications : `html{overflow-x:clip}`
  (ce qui dépasse est rogné à sa place, la page ne s'élargit plus) et
  `.vue{overflow-wrap:break-word}` (un mot qui ne tient nulle part se
  plie, sans toucher aux largeurs minimales des colonnes).
- **Les boutons sont en ligne, plus en flex.** L'icône fait partie du
  texte ; deux lignes se centrent ; la hauteur vient du texte (plus de
  hauteur minimale qui laissait un vide sous une ligne seule). Un bouton
  qui porte autre chose que des mots (le livreur et son numéro dans
  « Confier ») reste en flex, à part. Une icône placée *après* le texte
  porte `ic-apres`. Les libellés trop longs pour une ligne en grands
  caractères ont été raccourcis : « Recevoir un code », « Envoyer un
  essai », « Enregistrer », « Ma position actuelle », « Exporter » /
  « Restaurer » côte à côte, « Stock et disponibilité », « Code de
  particulier », « Activer ma position », « Voir la suite », « Espace
  vendeur », « Changer le mot de passe ».
- **Les titres d'écran se plient sur deux lignes** avant de finir en
  « … » ; le sous-titre aussi.
- **Une liste de portes partagée** — `UI.porte()` dans les deux
  applications, les classes `.liste-portes` / `.ligne-info` de « À propos
  de BIZZOO » — remplace les pilules empilées : dans les Réglages du
  superadministrateur (Gérer les boutiques, Comptes revendeurs,
  Demandes, Avis, Réclamations), dans « Mon compte » du client (Mes
  commandes, Mes réclamations, Mes favoris, Mes adresses) et dans « Vos
  données et vos droits », dont les trois liens en gros texte nu se
  lisaient comme des titres. « Supprimer mon compte » est en rouge pâle
  (`btn-danger-clair`), pour ne pas se confondre avec « Mes adresses ».
- **Les commandes (admin)** : seul le montant reste à droite du numéro ;
  l'heure et le paiement, puis « sur … » et « dont … de livraison »,
  passent sous l'en-tête sur toute la largeur. Le numéro et les
  pastilles d'état ne se plient plus (`white-space:nowrap` sur toute
  pastille, des deux côtés).
- **La liste des produits (admin)** : le nom sur deux lignes, le prix, le
  stock et les pastilles sur une rangée dessous ; à l'ordinateur, la
  rangée d'avant (nom à gauche, chiffres à droite) revient.
- **Catégories et Boutiques (admin)** : une grille où le nom a toute la
  ligne, le compte ou le secteur et les trois boutons dessous. « Mode &
  Vêtements » finissait en « Mo… ».
- **Les Réglages** : les deux tuiles « BIZZOO » / « la boutique ouverte »
  l'une sous l'autre au téléphone (`minmax(0,1fr)`, et le nom sur deux
  lignes).
- **Les cartes produit (client)** : les pastilles s'arrêtent avant le
  cœur et se plient au lieu d'être coupées.
- **« À propos »** : une adresse qui est déjà un lien (« maps.app.goo.gl… »)
  s'ouvre telle quelle et s'écrit « Voir sur le plan ».
- **Le reçu** : un prix ne se casse plus en « 105 » / « FCFA » ; la
  pastille d'une réclamation passe sous son titre au lieu d'écraser
  « Autre problème ».
- **Les champs** sont les mêmes dans les deux applications (trait d'un
  pixel et demi, coins de 12 px, 48 px, halo bleu au focus) ; le gris
  des textes d'aide passe de 2,8:1 à 4,8:1 (`--encre-moyenne`) ; l'icône
  d'un titre de carte reste sur sa première ligne quand il se plie.
- **La barre du bas (admin)** : la colonne du rond orange est à sa
  taille, les quatre mots autour gagnent de quoi s'écrire ; « Mon
  compte » devient « Compte ». Chez le client, les cinq onglets d'une
  boutique passent à 10 px sur un téléphone.

### L'outil : la galerie des écrans

```bash
GALERIE=galerie ZOOM=1.3 LARGEUR=360 \
PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/galerie-ecrans.mjs
```

[`tools/galerie-ecrans.mjs`](tools/galerie-ecrans.mjs) ouvre les deux
applications sur une base doublée (rien ne sort de la machine), passe sur
une soixantaine d'écrans — client connecté ou non, superadministrateur,
administrateur de boutique, livreur — et garde une capture de chacun.
`ZOOM=1.3` rejoue les grands caractères du téléphone : chaque élément
reçoit sa taille calculée × 1,3, une fois, avant la capture. Sur chaque
écran il mesure ce qu'une capture ne dit pas : la page déborde-t-elle en
largeur et à cause de quoi, quels boutons ont leur texte sur deux lignes,
quels titres d'en-tête sont coupés, quelles icônes sont après le texte
sans `ic-apres`. Les rangées qui défilent de côté (produits, puces) ne
comptent pas. Le rapport sort en JSON (`rapport.json`) et en résumé.

Ce n'est pas un banc — il ne compte pas d'échecs, les noms de produits
coupés d'un « … » dans une liste sont voulus — mais c'est ce qu'on
regarde avant de livrer, et ce qu'on envoie au propriétaire pour montrer
« avant » et « après ». Avant la refonte, à ZOOM=1.3 : dix-neuf écrans
avec un titre coupé, dix-sept boutons sur deux lignes, trois pages qui
débordaient. Après : aucun titre coupé, aucune page qui déborde, un seul
bouton sur deux lignes (« Prévenir IMPACT INFORMATIQUE », centré, lisible).

## La session qui tombait en silence, et la commande orpheline (3.63.0)

Le 21 octobre 2026, les commandes de test BZ-000055 à BZ-000064 sont
nées **sans compte rattaché**, alors que leurs auteurs se croyaient
connectés. Tout ce que le propriétaire a vu en découle : plus d'étapes
« Commande reçue … Remise » chez le client, plus de livreur annoncé,
plus de bouton « J'ai bien reçu » — et, côté boutique, « En attente de
sa confirmation » pour toujours. La base ne montre les lignes d'une
commande, et n'accepte la parole « j'ai reçu », que du compte qui l'a
passée : une commande sans compte n'a rien de tout cela.

### Ce qui s'est passé

Le journal d'authentification le raconte. À chaque fois, quelques
minutes avant la commande orpheline : une **déconnexion** du même
compte depuis un autre appareil — ou depuis le site plutôt que
l'application —, puis un rafraîchissement refusé, « Refresh Token Not
Found », jusqu'à **sept fois à la même seconde**.

Deux défauts se combinaient :

1. **« Se déconnecter » fermait toutes les sessions du compte.** Sans
   `scope=local`, GoTrue révoque tout : se déconnecter sur un téléphone
   déconnectait aussi l'autre, qui ne l'apprenait qu'au rafraîchissement
   suivant.
2. **La session perdue l'était en silence.** `assurerSession()` effaçait
   la session et rendait « personne ». L'écran de commande, prérempli
   des coordonnées gardées sur le téléphone, laissait alors partir la
   commande **en visiteur** — sans que rien ne change sous les yeux du
   client. Et les écrans qui s'ouvrent ensemble au démarrage demandaient
   chacun leur rafraîchissement, avec la même clé.

(BZ-000055 à 58 ont une autre cause, voulue : elles ont été passées avec
un compte de l'équipe — un modérateur —, que `creer_commande` écarte par
construction. Elles ne pourront pas être rattachées.)

### Ce qui change

**Côté client, la session** (`client/js/compte.js`) :

- un seul rafraîchissement à la fois : tous les écrans attendent le même
  appel ;
- avant de conclure que la session est perdue, relire celle que le
  téléphone garde — un autre onglet de la même application a pu la
  renouveler entre-temps ;
- perdue pour de bon, elle l'est **à voix haute** : « Votre session a
  expiré : reconnectez-vous… », un drapeau `bizzoo-session-perdue` gardé
  sur le téléphone, un événement `compte:perdue` ;
- « Se déconnecter » ne ferme que ce téléphone (`logout?scope=local`).

**L'écran de commande** (`client/js/vues/panier.js`) : le drapeau posé,
l'écran ne dessine plus son formulaire — il dit « Votre session a
expiré » et propose **Se reconnecter** ou **Commander sans compte**, en
disant ce que l'on perd (et pas de second choix quand l'enseigne exige
un compte). Au moment de payer, si la session est tombée entre-temps, la
commande ne part pas : l'écran se redessine sur ce même choix.

**Sans compte, le numéro suit aussi.** `suivre_commande` rend désormais
`etats` : par boutique, l'étape la moins avancée de ses lignes et si le
client a tout confirmé — la règle qu'appliquait déjà l'application aux
commandes d'un compte. Le reçu d'une commande passée sans compte montre
donc les étapes ; pas le bouton « J'ai bien reçu », que la base
n'accepte que d'un compte, mais la phrase qui dit comment : entrer avec
ce numéro, et la retrouver dans « Mes commandes ».

**« Mes commandes » rattache de lui-même.** Connecté, le numéro vérifié,
des copies locales que la base n'attribue à personne : l'écran appelle
`rattacher_mes_commandes` — ce que « Retrouver mes commandes d'avant »
fait à la main —, une fois par ouverture, et le dit : « 1 commande
rattachée à votre compte ».

**En base** (`supabase/commande-compte-client.sql`) : `creer_commande` ne
ramène plus à « personne » un compte connecté **sans fiche client** — sa
fiche se pose, avec ce qu'il vient de donner, et la commande reste la
sienne. Seul un vrai compte d'équipe est écarté ; une fiche d'équipe en
attente ne vaut aucun droit, et s'efface comme le fait l'application.

**Côté admin** : la commande porte `clientId`, et une ligne remise d'une
commande sans compte dit « Commande passée sans compte client : pas de
confirmation possible » au lieu d'attendre. Le rafraîchissement de la
session y suit les mêmes deux règles (un seul appel, relecture).

### Les commandes déjà passées

BZ-000059 à 64 ont été passées avec le numéro de deux comptes dont le
numéro est vérifié : avec l'application mise à jour, ouvrir « Mes
commandes » sur le téléphone qui les a passées suffit à les rattacher
(ou « Mon compte → Retrouver mes commandes d'avant »). Le bouton
« J'ai bien reçu » y paraît alors, et la boutique voit la confirmation.

### Les bancs

```bash
PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-session-perdue.mjs
bash tools/eprouver-base.sh     # supabase/tests/99zzz…-commande-sans-fiche.sql
```

Le banc au navigateur, 54 constats en sept chapitres : un seul
rafraîchissement ; refusée mais renouvelée ailleurs ; perdue, dite,
notée, et l'écran de commande qui la rappelle — même après fermeture —
sans qu'aucune commande ne parte d'elle-même ; connectée à l'ouverture
et plus au moment de payer ; `scope=local` ; le suivi par numéro sans
le bouton ; le rattachement automatique, une fois par ouverture. Le
quatrième chapitre a d'abord **échoué** : la session tombée en
arrière-plan pendant la saisie passait entre les mailles — d'où le
drapeau consulté au moment de payer, et pas seulement l'état de
connexion à l'ouverture de l'écran.

L'essai de base, 17 constats : la fiche posée, la fiche en attente
remplacée, le compte d'équipe écarté, et les étapes rendues par le
numéro — « nouvelle », « remise », puis confirmée.

### L'administrateur de BIZZOO et ses livreurs

Depuis la 3.59.0, l'administrateur de BIZZOO crée et modifie tous les
livreurs : les règles de `profils` le lui permettent. Mais « Redonner un
mot de passe » et « Supprimer » passent par `gere_le_compte`, qui ne
connaissait que le superadministrateur et l'administrateur d'une
boutique : ces deux gestes lui répondaient « Ce compte n'est pas sous
votre responsabilité ». La fonction l'accepte désormais — pour un
livreur, et rien d'autre (`supabase/admin-bizzoo-livreurs.sql`, appliqué
en ligne le 21 octobre 2026). L'essai
`99zzz…-admin-bizzoo-livreurs.sql` le garde, avec ce qui doit rester
fermé : ni modérateur, ni administrateur, ni lui-même ; et
l'administrateur d'une boutique toujours enfermé dans la sienne.

Il manquait aussi **le crayon** : à l'écran, `Store.gereLeCompte` exigeait
une boutique, et l'administrateur de BIZZOO n'en a pas — ses livreurs
s'affichaient sans aucun moyen de les ouvrir. Il l'a désormais sur tous.

### Le modérateur créé par l'administrateur, validé par le superadministrateur

Demande du CEO (message vocal du 21 octobre 2026) : *« un administrateur
peut créer un compte modérateur, et c'est le superadministrateur qui va
juste valider »* — pour pouvoir ensuite ramener les superadministrateurs
au rang d'administrateur.

- **L'administrateur de BIZZOO** entre dans « Comptes » et crée un
  modérateur, pour une boutique ou pour BIZZOO. Le compte naît
  **inactif** et « à valider par le superadministrateur ». Tant qu'il
  attend, son créateur le voit, le retouche, lui redonne un mot de
  passe ou le retire ; l'activer, jamais.
- **Le superadministrateur** est prévenu (notification « Un compte
  modérateur à valider ») et trouve en tête de « Comptes » une carte
  « À valider » avec un bouton **Valider**. Activer le compte le valide ;
  son créateur en est prévenu à son tour.
- **Personne d'autre ne l'active** : ni l'administrateur de la boutique
  concernée, ni une requête qui écrirait la colonne elle-même. C'est la
  base qui y veille (`profil_validation`, colonne `profils.a_valider`),
  pas l'écran.
- Validé, le compte n'appartient plus à son créateur : il se gère comme
  les autres. L'administrateur de BIZZOO ne crée toujours ni
  administrateur ni superadministrateur.

Le tout est dans `supabase/admin-bizzoo-livreurs.sql`. Un piège en
chemin : l'écran pose le rang par `insert … on conflict`, et PostgreSQL
exige alors que la ligne **proposée** soit lisible par son auteur —
avant même la mise à jour. Elle ne l'était que par son créateur, qui
n'était pas encore posé : `profil_validation` le pose dès l'insertion.

Gardés par l'essai `99zzz…-moderateur-a-valider.sql` (19 constats) et
les chapitres 7 et 8 de `tools/banc-admin-bizzoo.mjs`.


## La livraison au kilomètre, et le solde des livreurs (3.64.0)

Les frais de livraison ne dépendent plus de la boutique mais de la
**distance** entre le point de départ de BIZZOO et le client.

### Le tarif

| Véhicule | Jusqu'à 10 km | Au-delà, par km entamé |
|---|---|---|
| Moto | 1 000 FCFA | 100 FCFA |
| Tricycle | 4 000 FCFA | 500 FCFA |

- **La distance** : à vol d'oiseau du point BIZZOO au client, × 1,3 (le
  coefficient de la route). Le kilomètre **entamé** compte : 10,1 km
  facturent 11 km. Pas de distance maximale.
- **Le véhicule** : chaque produit a le sien (*moto* par défaut, pour
  tous les produits existants ; modifiable dans sa fiche, « Livré
  par »). **Un seul produit en tricycle** fait livrer toute la commande
  en tricycle.
- **Un seul frais par commande**, même si elle traverse plusieurs
  boutiques : les frais de chaque boutique ne comptent plus. Il se paie
  **en ligne, avec l'acompte** ; les codes promo n'y touchent pas ; les
  revendeurs paient le même. Le reste à la livraison ne le compte pas.
- Tout se règle dans **Réglages → BIZZOO → Livraison au kilomètre**
  (superadministrateur seul) : le point (position actuelle, ou épingle
  sur la carte), les forfaits, les prix au km, le rayon, la part du
  livreur.

**Rien ne change tant que le point BIZZOO n'est pas réglé** : chaque
boutique garde ses frais. Les commandes passées gardent les leurs.
« Arrêter la livraison au km » rend la main aux frais par boutique.

### Le client

- Le panier annonce « Livraison à moto — selon la distance — dès
  1 000 FCFA » et le tarif du véhicule ; la fiche d'un produit dit
  « Livraison en tricycle : 4 000 FCFA jusqu'à 10 km, 500 FCFA par km
  au-delà ».
- **Sa position est obligatoire** pour commander : « Utiliser ma
  position », puis l'épingle se déplace sur la carte (ou l'on colle un
  lien Google Maps) pour être livré ailleurs. Les frais s'affichent
  aussitôt ; la position est gardée pour la commande suivante. Sans
  position, la base refuse la commande.
- Le reçu dit « dont 1 400 FCFA de frais de livraison (moto, 13,4 km) ».

La carte est **Leaflet 1.9.4** (licence BSD), embarquée dans
`client/vendor/leaflet` et `admin/vendor/leaflet`, avec les tuiles
d'OpenStreetMap. Elle ne se charge qu'à l'ouverture d'une carte
(`js/carte.js`). Sans connexion, « Utiliser ma position » marche
toujours.

### Les livreurs

- **Un seul livreur par commande** au kilomètre. Une commande de
  plusieurs boutiques se confie à un livreur de BIZZOO, qui les livre
  toutes ; une commande en tricycle, à un livreur en tricycle — la base
  refuse le reste, et ne la propose qu'aux bons livreurs.
- Chaque livreur a un **véhicule** (moto par défaut), réglé dans sa
  fiche (« Livreurs »).
- Sa course montre le véhicule, la distance et **son gain**.
- **Ses gains** : 80 % des frais de chaque commande, crédités dès que
  **toute la commande est remise** (sans attendre le « J'ai bien reçu »
  du client), au taux du jour, figé. Une commande annulée ne rapporte
  rien. Le reste (20 %) revient à BIZZOO. Le taux se change dans les
  Réglages ; il vaut pour tous les livreurs, ceux de BIZZOO comme ceux
  des boutiques.
- **Mes gains** (icône en haut de « Mes courses ») : le solde, le numéro
  Mobile Money qui reçoit les gains, « Demander un reversement »,
  l'historique.
- **Le superadministrateur** trouve les demandes des livreurs dans
  « Reversements », à côté de celles des boutiques : il envoie
  l'argent, puis touche « Envoyé » avec la référence — ou refuse, avec un
  motif.

### Mise en service

1. Exécuter `supabase/livraison-au-km.sql` (ou `schema.sql`) — sans
   effet sur les commandes tant que le point n'est pas réglé.
2. Régler les véhicules : les gros produits en tricycle, les livreurs
   en tricycle.
3. Réglages → BIZZOO → Livraison au kilomètre : poser le point BIZZOO,
   vérifier les tarifs, **Enregistrer**. C'est en service.

Appliqué en ligne le 23 octobre 2026, en sept morceaux. L'ancienne
`creer_commande` à cinq paramètres n'a pas été effacée mais **renommée**
`creer_commande_avant_km` (sans droit d'appel) : avec les deux, PostgREST
n'aurait pas su laquelle choisir. Vérifié après coup : les 37 fonctions
du fichier sont identiques en ligne, et une commande d'essai (annulée)
se comporte comme avant tant que le point BIZZOO n'est pas réglé.

### Les essais

- `supabase/tests/99zzz…-livraison-au-km.sql` : le devis (forfait, km
  entamé, tricycle, positions absurdes refusées), la commande (position
  obligatoire, un seul frais, acompte + frais, restes sans frais), un
  livreur par commande, le tricycle aux tricycles, le crédit de 80 %
  une seule fois, rien sur une commande annulée, le solde, les
  reversements tranchés par le superadministrateur seul.
- `tools/banc-livraison-km.mjs` : panier, fiche produit, « Où livrer ? »
  avec la position du téléphone et un lien collé, la commande et son
  reçu, une base sans point BIZZOO, les Réglages, l'écran du livreur et
  « Mes gains », la décision du superadministrateur.


## Le téléphone sonne, application fermée (3.65.0)

Avant, une course confiée à un livreur ou une commande payée chez une
boutique ne sonnait que si BIZZOO Admin était **ouverte**. Désormais le
téléphone sonne même application fermée ou en veille, par Firebase Cloud
Messaging (le même projet Firebase que les lives TikTok).

- **Une course** (confiée par la boutique, ou proposée à tous) : la
  notification **sonne jusqu'à ce qu'on la touche** (trois notes qui
  montent, en boucle, et vibration), comme la sonnerie de l'application.
- **Une commande payée** (et toute notification « qui sonne » pour une
  boutique) : elle sonne une fois, fort.
- **Toucher la notification** ouvre BIZZOO Admin directement sur la course
  ou la commande. Ouvrir l'application arrête les sonneries : elle prend le
  relais.
- Application déjà à l'écran : pas de double sonnerie.
- Chaque téléphone se **déclare** à la connexion pour le compte connecté,
  et se **retire** à la déconnexion. Un téléphone désinstallé est oublié au
  premier refus de Firebase.

### Comment ça marche

1. `notifier()` écrit la notification, comme avant.
2. Si elle **sonne** et que son destinataire a un téléphone déclaré, le
   déclencheur `notifications_poussent` appelle la fonction Edge
   `envoyer-push` par **pg_net**, après la transaction.
3. La fonction ne reçoit que le **numéro** de la notification ; elle relit
   tout dans la base (`push_a_envoyer`), qui la marque envoyée au passage :
   rien ne part deux fois, et un appel forgé n'envoie rien qui ne vienne de
   la base.

Fichiers : `supabase/notifications-push.sql`,
`supabase/functions/envoyer-push/`, `admin/js/push.js`, et dans
`android/` : `ServiceNotifications.java`, `MainActivity.java`,
`res/raw/sonnerie_course.wav`.

### Mise en service

1. Firebase : ajouter l'application Android **`com.impactinformatique.admin`**
   au projet « bizzoo » (Paramètres du projet → Vos applications → Ajouter
   une application), et recopier son **ID de l'application** dans
   `android/firebase.properties`, ligne `admin_app_id=`. C'est un
   identifiant public, pas un secret. Vide : pas de push pour l'équipe.
2. Supabase : activer l'extension **pg_net**, exécuter
   `supabase/notifications-push.sql`, déployer `envoyer-push` **sans
   vérification du jeton**, et poser son adresse dans `push_reglage`.
3. Construire les APK : les livreurs et les boutiques installent la
   nouvelle BIZZOO Admin et s'y reconnectent une fois.

En ligne le 23 octobre 2026 : pg_net activé, tables, déclencheur et
fonctions posés, `envoyer-push` déployée (essayée : « Rien à envoyer » pour
un numéro inconnu, 400 pour un numéro absurde), adresse réglée, et l'ID
Firebase de l'application admin renseigné.

Android seulement : l'application iOS n'a pas encore de notifications push
(il faudrait un certificat Apple). Dans un navigateur, rien ne change.

### Les essais

- `supabase/tests/99zzz…-notifications-push.sql` (24 constats) : la
  déclaration du téléphone, les droits, l'appel par pg_net (simulé) pour
  les seules notifications qui sonnent, l'envoi unique, l'oubli.
- `tools/eprouver-push.sh` (19 constats) : la fonction Edge, Google et
  Firebase en doublures.
- `tools/banc-push-equipe.mjs` (14 constats) : la déclaration à la
  connexion, le retrait à la déconnexion, le navigateur sans pont, une
  base d'avant.

## Le coefficient de la route se règle à l'écran (3.66.0)

Dans **BIZZOO Admin → Réglages → BIZZOO (l'enseigne) → Livraison au
kilomètre**, le superadministrateur règle désormais le **coefficient de la
route** à côté du rayon du forfait. La distance en ligne droite entre le
point BIZZOO et le client est multipliée par ce nombre pour suivre les
routes : 1,3 = 30 % de détour (valeur en service). Entre 1 et 3, deux
décimales ; une valeur hors bornes est refusée, avec un message. Rien à
changer en base : la colonne `livraison_coef` et sa borne existaient déjà.
Banc : `tools/banc-livraison-km.mjs`, section 5.

## Qui entend quoi : commande payée, course prise (3.66.0)

| Événement | Boutique (admin, modérateur) | Admins BIZZOO qui suivent les commandes | Superadministrateurs |
|---|---|---|---|
| Le client paie (commande confirmée) | sonne | sonne | sonne |
| Un livreur prend / accepte la course | sonne | **sonne (nouveau)** | **sonne (nouveau)** |

« Sonne » : trois bips quand BIZZOO Admin est ouverte ; une notification
sonore quand elle est fermée ou en veille — à condition que le téléphone
ait BIZZOO Admin **3.65.0 ou plus récente**, et que le compte s'y soit
connecté une fois (le téléphone se déclare alors). Un livreur qui prend
toute une commande de plusieurs boutiques fait sonner BIZZOO **une seule
fois**. Les admins BIZZOO dont l'interrupteur « Commandes » est éteint ne
sont pas dérangés.

Fichier : `supabase/sonnerie-course-prise.sql` — **en ligne depuis le
24/10/2026**. Essai : section 6 de `99zzz…-gains-toutes-courses.sql` ;
`99m-circuit-complet.sql` attend désormais deux nouvelles pour le
superadministrateur (le paiement, la course prise).

## Le livreur touche sa part de toutes ses courses (3.66.0)

Avant, seules les commandes **au kilomètre** créditaient le livreur : ses
courses à l'ancien tarif (frais par boutique) ne lui rapportaient rien à
l'écran, et son solde restait à zéro. Désormais **chaque course remise et
payée** lui rapporte 80 % (« taux du livreur », Réglages) des frais :

- **au kilomètre** : les frais entiers — un seul livreur porte la commande ;
- **à l'ancien tarif** : les frais **des boutiques dont il a livré les
  produits**. Deux boutiques, deux livreurs : chacun 80 % des frais de la
  sienne, dès qu'il a remis sa part, sans attendre l'autre. Un livreur de
  BIZZOO qui porte les deux touche les deux ;
- **plus ancienne encore** (sans frais par boutique) : au prorata de ce
  qu'il porte.

Une part annulée ne compte pas. Le gain affiché sur la course, le « à
venir » et le crédit disent la même chose : une seule règle,
`part_frais_livreur()`, en base. `gains_livreurs` a désormais **une ligne
par commande et par livreur** (jamais deux pour le même).

**Le solde se voit** : un bandeau vert « Mon solde » en tête de « Mes
courses » (BIZZOO Admin) mène à « Mes gains ».

**Le livreur travaille dans BIZZOO Admin.** L'application client ne liste
plus ses courses : « Mon compte » et l'ancien lien « Mes courses » le
renvoient vers BIZZOO Admin (bouton « Ouvrir BIZZOO Admin », ou « pas
installée : demandez-la à BIZZOO »), où il entre avec le même numéro et le
même mot de passe — c'est là que les courses sonnent et que sont ses gains.

### Le rattrapage

`supabase/livreurs-gains-toutes-courses.sql` crédite une fois les courses
remises des **30 derniers jours**, et envoie **une seule** notification par
livreur avec le total (pas une par course). Relancé, il ne crédite rien deux
fois.

**En ligne depuis le 24/10/2026** : règles appliquées, rattrapage fait —
9 courses, 6 560 F crédités à 4 livreurs, une notification chacun.

### Les essais

- `supabase/tests/99zzz…-gains-toutes-courses.sql` (22 constats) : deux
  livreurs, deux parts ; un livreur pour deux boutiques ; le prorata ; une
  part annulée ; un compte livreur supprimé depuis (sauté, sans priver
  l'autre) ; le rattrapage silencieux et rejouable.
- `tools/banc-livraison-km.mjs` : le bandeau « Mon solde ».
- `tools/banc-livreur-compte-client.mjs`, `tools/banc-parcours-livraison.mjs` :
  le renvoi vers BIZZOO Admin.

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
│   ├── role-livreur.sql             # Le porteur : un écran, deux gestes, un seul montant (ce qu'il encaisse)
│   ├── categories-bizzoo.sql        # La liste des rayons : celle de l'enseigne, et d'elle seule
│   ├── categories-photos.sql        # La photo d'une catégorie : un chemin, un seul dossier
│   ├── categories-icones.sql        # L'icône de chaque catégorie (3.56), sans toucher à l'image
│   ├── categories-rangement.sql     # Trente catégories rangées par thème (3.56), une seule fois
│   ├── feexpay.sql                  # Le second agrégateur, au choix de l'enseigne
│   ├── stock-et-droits.sql          # Bilan de santé : la règle du stock, quatre portes fermées aux visiteurs
│   ├── stock-ventes.sql             # Le stock suit les ventes : excédent refusé, décompte payé, retour annulé
│   ├── acompte.sql                  # L'acompte à la commande (3.57.0) : en ligne l'acompte, le reste à la livraison
│   ├── connexion-sms.sql            # Le code SMS de l'équipe, et qui a créé quel compte (3.58.0)
│   ├── livreur-client.sql           # Le client voit qui lui livre sa commande (3.58.0)
│   ├── revendeur-sans-code.sql      # Pas de code promo pour un revendeur (3.58.0)
│   ├── codes-particuliers.sql       # Les codes des particuliers : commission, solde, retraits (3.58.0)
│   ├── live-tiktok.sql              # Le live TikTok : démarrer, arrêter, lives en cours (3.58.0)
│   ├── frais-livraison.sql          # Les frais de livraison : 1 000 FCFA par commande, hors code promo (3.58.0)
│   ├── positions-comptes.sql        # Livreurs et revendeurs valident leur compte par leur position (3.58.0)
│   ├── connexion-telephone.sql      # Numéro + mot de passe + code : livreurs créés par leur numéro (3.59.0)
│   ├── livreurs-sans-compte-client.sql # Un livreur n'est ni acheteur ni revendeur (3.59.0)
│   ├── admin-bizzoo-livreurs-revendeurs.sql # L'admin de BIZZOO : livreurs, revendeurs, validation (3.59.0)
│   ├── produits-habilitation.sql    # Créer un produit demande l'habilitation (3.59.0)
│   ├── horaires-boutiques.sql       # Jours et heures d'ouverture ; fermée, pas de commande (3.59.0)
│   ├── conditions-paiement-boutiques.sql # Condition de paiement et frais de chaque boutique (3.59.0)
│   ├── personnel.sql                # BIZZOO Personnel : employés, missions, rapports, dépenses, paie (3.61.0)
│   ├── personnel-statistiques.sql   # BIZZOO Personnel : les statistiques, selon le rang (3.61.1)
│   ├── personnel-suivi.sql          # BIZZOO Personnel : le suivi des commandes, journal, alertes, zones
│   ├── etat-des-lieux.sql           # Ce qui est en place et ce qui manque (ne modifie rien)
│   ├── etat-du-stockage.sql         # Les seaux, leur poids et les fichiers orphelins
│   ├── tests/                       # La base éprouvée sur un vrai PostgreSQL
│   ├── functions/kkiapay-webhook/   # KkiaPay : sa notification signée
│   ├── functions/feexpay/           # FeexPay : notre serveur ouvre, puis vérifie
│   ├── functions/feexpay-webhook/   # Sa notification — non signée, donc jamais crue
│   ├── functions/_partage/sms.ts    # Le transport SMS : un 200 n'est pas un succès
│   ├── functions/hook-sms-auth/     # Livrer le code de connexion — la signature est le seul contrôle
│   ├── functions/code-connexion/    # Le code de l'équipe : tiré ici, haché avec la session, jamais rendu
│   ├── functions/tester-sms/        # Le bouton d'essai, par le chemin de la production
│   └── functions/rh-messagerie/     # Les mails @bizzoomarket.com du personnel : IMAP, SMTP, mot de passe chiffré
├── personnel/                # BIZZOO Personnel : l'application interne des employés (3.61.0)
├── client/                   # Application des clients
│   ├── config.js             # URL + clé publiable du projet Supabase
│   ├── demo-catalogue.json   # Catalogue de démonstration (si config vide)
│   ├── index.html / styles.css / manifest.webmanifest / sw.js
│   ├── icons/                # Les icônes de l'application, et la tuile du logo (logo-bizzoo.png)
│   ├── img/pictos/           # Les icônes des catégories : celles de l'image de l'enseigne
│   └── js/
│       ├── catalogue.js      # Lecture de la base + copie hors connexion + prix du compte
│       ├── compte.js         # Le compte du client : son numéro et son code, sa fiche, sa demande de revendeur
│       ├── avis.js           # Lire les avis sans compte, en donner un si l'on a payé
│       ├── sav.js            # Réclamations : la boutique d'abord, BIZZOO en recours
│       ├── panier.js         # Le panier : des identifiants, jamais des prix
│       ├── paiement.js       # Commander, ouvrir KkiaPay, attendre la base
│       ├── ui.js             # Logo, cartes produit, prix, badges
│       └── vues/             # Accueil, catégories, produit, produits, panier, recherche, infos
├── admin/                    # Application du gérant
│   ├── config.js
│   ├── index.html / styles.css / manifest.webmanifest / sw.js
│   ├── icons/                # Ses icônes (à pastille « réglages »), et la tuile du logo, sans
│   ├── img/pictos/           # Les mêmes icônes, pour la liste et la fiche
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
├── vitrine/                  # Ses captures, et l'image de l'aperçu partagé (adresses en « ?v= »)
├── 404.html / robots.txt / sitemap.xml   # Ce qu'attend un site en ligne
├── hebergement/htaccess      # Le .htaccess de www.bizzoomarket.com (Apache, LiteSpeed)
├── DEMARRER-BIZZOO.bat       # Windows : double-cliquer pour tout ouvrir en local
├── serve.ps1                 # Le serveur local que le .bat appelle (Windows)
└── tools/
    ├── assembler-site.sh     # Le site public, sur liste blanche — et le zip de l'hébergement
    ├── aligner-migrations.js # Recopie les fonctions de schema.sql dans les migrations
    ├── banc-*.mjs            # Les bancs du navigateur (Playwright) — dont envoi-unique, sms-ferme, stock, accueil-galerie, navigation-boutique, compte-enseigne et paiement-echoue
    ├── bizzoo-icone.png      # L'œuvre officielle, le B au chariot — source de toutes les icônes
    ├── eprouver-base.sh      # Force les portes de la base (PostgreSQL jetable)
    ├── icones-categories.py  # Les icônes des catégories, découpées dans les trois planches
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
  applications ont d'abord été relevées sur la première œuvre BIZZOO, le
  sac de courses — remplacé en 3.52.0 par le B au chariot, sur lequel la
  gamme de bleus est tirée depuis la 3.53.0 (voir « Le bleu de
  l'icône ») :
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
