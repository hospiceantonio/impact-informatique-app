# BIZZOO

BIZZOO, ce sont deux applications sur une même base Supabase :

- **BIZZOO** (`client/`) : la place de marché des clients, en site web (PWA) et en APK Android ;
- **BIZZOO Admin** (`admin/`) : l'application des boutiques, des livreurs et de l'enseigne, en PWA et en APK.

Le propriétaire de BIZZOO est au Bénin et parle français. Il n'est pas développeur. Lui répondre en français simple, lui dire précisément quoi faire (quel bouton, quel fichier), et expliquer chaque terme technique.

`README.md` est la documentation complète. Il fait près de 4 000 lignes : le lire par section. On y trouve une section par chantier, puis « Structure » et « Détails techniques ». Lire la section concernée avant de toucher à un domaine, et la tenir à jour.

## Où vit le projet

- **Sur le PC du propriétaire** : le dossier `BIZZOO`, dans « MES CONCEPTIONS CLAUDE ». C'est la copie de travail. Jusqu'à la version 3.54.0, le travail se faisait dans une session Claude dans le cloud, directement sur GitHub.
- **Sur GitHub** : `hospiceantonio/impact-informatique-app`, branche `main`. Le dépôt garde ce nom : le renommer casserait la copie github.io du site (`404.html`, `tools/banc-mise-en-ligne.mjs`, Redirect URLs de Supabase).
- **En ligne** : www.bizzoomarket.com, chez un hébergeur à qui l'on envoie le zip d'hébergement, et une copie sur GitHub Pages.
- **La base** : Supabase, projet `rrwzegmrmvvkmzfoiitb`.

C'est GitHub qui fabrique ce qui se livre :

- un push qui touche `client/`, `admin/` ou `android/` construit les deux APK et les committe dans `apk/` (« APK Android construits automatiquement [skip ci] ») ;
- un push sur `main`, puis l'arrivée des APK, redéploient le site sur GitHub Pages et fabriquent le zip d'hébergement (artefact `bizzoo-site-hebergement`) ;
- « Éprouver la base » (PostgreSQL) et « Éprouver les fonctions » (paiement, SMS) rejouent les essais qui ne tournent pas sur le PC.

Un travail qui n'est pas poussé ne produit ni APK ni site.

## Première session sur le PC : relier le dossier à GitHub

Le dossier `BIZZOO` a été copié depuis le zip de GitHub : il n'a pas de `.git`. Contrôle du 26/09/2026 : 333 fichiers et 12 843 010 octets, soit exactement le commit `1ce1421` (version 3.54.0). S'y ajoute ce `CLAUDE.md`.

Si `git status` répond « not a git repository », relier le dossier sans rien retélécharger :

```bash
git init -b main
git config core.autocrlf false
git remote add origin https://github.com/hospiceantonio/impact-informatique-app.git
git fetch origin main
git reset origin/main
git branch --set-upstream-to=origin/main main
git status
```

- `git status` doit être propre, puisque les fichiers sont ceux de GitHub. S'il montre des écarts, les montrer au propriétaire avant d'écraser quoi que ce soit.
- `core.autocrlf false` garde les fins de ligne du dépôt. `.gitattributes` fixe déjà celles des `.bat`, `.ps1` et `.sh`.
- Au premier push, Git ouvre le navigateur pour se connecter à GitHub. C'est le propriétaire qui se connecte, avec son compte.

Il faut Git pour Windows (git-scm.com). Pour les bancs et les icônes, il faut aussi Node.js (version LTS). S'ils manquent, le dire au propriétaire, lien à l'appui.

## Règles de sécurité : non négociables

- Ne jamais demander ni accepter dans la conversation :
  - le jeton FeexPay (`fp_…`) ;
  - la clé SMS de CREATISINTER ;
  - la clé `service_role` de Supabase.

  Si le propriétaire en colle une, lui dire de la régénérer.
- La clé `service_role` ne va sur aucun poste. `tools/menage-stockage.ps1` s'authentifie avec l'e-mail et le mot de passe de l'admin.
- Le jeton et l'identifiant de boutique FeexPay vivent uniquement dans les secrets Supabase : jamais dans la table `paiement` (lisible par `anon`), jamais dans un APK. Même règle pour `SMS_CLE`, `SMS_EXPEDITEUR` et `SMS_HOOK_SECRET`.
- Le choix de l'agrégateur de paiement est réservé au superadmin. C'est la RLS qui l'impose (`est_super()`).
- FeexPay n'a pas de bac à sable utilisable : ne jamais simuler un paiement réussi.
- La notification (webhook) de FeexPay n'est pas signée : ne jamais croire son `status` ni son `amount`, toujours revérifier auprès de FeexPay.
- `favoris`, `boutiques_suivies` et `adresses` sont fermées à `est_super()`, exprès.
- Le SELECT de `commande_lignes` est restreint par colonne pour cacher `prix_bizzoo` et `taux_marge` : ne jamais l'élargir.
- Ne jamais retirer à `anon` le droit EXECUTE sur une fonction qu'appelle une politique RLS.
- La base en ligne se lit par défaut ; elle ne s'écrit que sur demande explicite. Le propriétaire a autorisé l'exécution directe de nos propres fichiers de migration.
- Aucun mot de passe choisi par Claude n'apparaît dans la conversation.
- Aucune donnée personnelle de client n'est exposée.
- Rien n'est inventé : ni avis, ni chiffres, ni clients.
- Aucun identifiant de modèle d'IA dans le code, les commentaires ou les commits (hors lignes d'attribution).

## Travailler avec le propriétaire

- Quand il annonce une série de modifications (« attends que je te dise c'est fini avant de générer les APK et le web »), ne rien pousser avant son « c'est fini » : committer en local seulement.
- Pas de pull request, sauf demande : on travaille sur `main`.
- Livrer, c'est :
  1. pousser ;
  2. attendre le commit des APK ;
  3. lui donner les deux APK (`apk/bizzoo-client.apk`, `apk/bizzoo-admin.apk`) et le zip d'hébergement, avec la marche à suivre.

## La routine de chaque version

1. `node --check` sur chaque fichier JS modifié.
2. `node tools/aligner-migrations.js`. `schema.sql` est la seule source de vérité des fonctions SQL : les migrations en recopient le corps.
3. `bash tools/fichiers-autonomes.sh`, puis `bash tools/coquille-complete.sh` (la liste du service worker).
4. Tous les bancs au navigateur, sans un seul « ÉCHEC » (voir plus bas).
5. Le README :
   - une section pour le chantier (modèle : « La barre du bas à deux visages (3.54.0) ») ;
   - la mise à jour des sections qu'il touche.
6. La version :
   - `android/app/build.gradle` : `versionCode` + 1, et `versionName` ;
   - `client/sw.js` : `VERSION = "impact-client-vNN"`, + 1 si le client change ;
   - `admin/sw.js` : `"impact-admin-vNN"`, + 1 si l'admin change.

   Sans ce + 1, les téléphones gardent l'ancienne version en cache.
7. Un commit en français, qui dit ce qui change pour le propriétaire. Puis `git pull --rebase`, et `git push`.
8. Attendre le commit des APK (quelques minutes), puis `git pull`. Vérifier sur GitHub, onglet Actions, que les workflows sont verts.
9. Le zip d'hébergement, au choix :
   - `bash tools/assembler-site.sh --hebergement ../bizzoo-site-X.Y.Z.zip`, hors du dépôt (il demande python3 et zip) ;
   - l'artefact `bizzoo-site-hebergement` du workflow « Déployer sur GitHub Pages ».

## Les bancs au navigateur

Les bancs ouvrent les applications dans Chromium et contrôlent les écrans. Ils simulent la base : ils ne touchent jamais aux vraies données.

1. Servir le projet sur http://localhost:5180, au choix :
   - dans PowerShell : `.\serve.ps1 -SansNavigateur` ;
   - dans bash : `bash tools/servir.sh`.
2. Une fois pour toutes, dans un dossier hors du dépôt : `npm install playwright-core`.
3. Lancer chaque banc :

   ```bash
   PLAYWRIGHT=<dossier>/node_modules/playwright-core/index.js \
   CHROMIUM="<chemin de msedge.exe ou de chrome.exe>" \
   node tools/banc-<nom>.mjs
   ```

Les 18 bancs :

- navigation-boutique, accueil-galerie, accueil-enseigne ;
- stock, envoi-unique, sms-ferme ;
- categories-photos, commandes-admin, livreur-bizzoo ;
- da-ecrans, da, entete, publicite ;
- marquer-vue, notifications-admin, notifications, suivi ;
- mise-en-ligne.

`tools/make-icons.js` refait toutes les icônes depuis `tools/bizzoo-icone.png`. Il utilise les mêmes `PLAYWRIGHT` et `CHROMIUM`.

## Le code

- Pas de compilation : ce qui est dans `client/` et `admin/` est exactement ce que lit le navigateur. C'est aussi ce qu'embarquent les APK (`android/preparer-assets.js`).
- Un module par fichier : `const X = (() => { … })()`.
- Noms et commentaires en français. Un commentaire dit pourquoi, pas quoi.
- Côté client :
  - le routeur à hash `ROUTES` est dans `client/js/app.js` (`onglet`, `sansOnglets`) ;
  - chaque écran a son fichier dans `client/js/vues/` ;
  - l'en-tête est dans `client/js/ui.js`.
- Les couleurs sont les jetons de `client/styles.css` et `admin/styles.css` (`--bleu-900` à `--bleu-50`, tirés de l'icône). Ne pas remettre de bleu en dur.
- La base :
  - `supabase/schema.sql` décrit toute la base ;
  - chaque chantier a son fichier de migration, qui doit se suffire à lui-même ;
  - on l'exécute dans l'éditeur SQL de Supabase, ou avec le connecteur Supabase s'il est branché.
- Les fonctions Edge (paiement FeexPay, hook SMS) sont dans `supabase/functions/`. Leurs essais : `tools/eprouver-paiement.sh` et `tools/eprouver-sms.sh`.
- `apk/` est écrit par GitHub : ne jamais y toucher à la main.
