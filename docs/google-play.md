# Publication BIZZOO sur Google Play

État vérifié le 2 octobre 2026. Compte choisi par le propriétaire :
**WINNER MARKET LIFE**, organisation `7195819094188094036`.

| Application | Package existant conservé | Version préparée |
|---|---|---|
| BIZZOO | `com.impactinformatique.client` | 3.54.1 (96) |
| BIZZOO Admin | `com.impactinformatique.admin` | 3.54.1 (96) |

Les deux applications ont été créées dans le compte Play WINNER MARKET LIFE.
Leurs versions 3.54.1 (96) visent la production, avec une disponibilité
initiale limitée au Bénin. **BIZZOO a été envoyé pour examen le 2 octobre**.
La console affiche « Modifications en cours d'examen » et exécute encore les
vérifications rapides avant la revue. La publication gérée est désactivée.
BIZZOO Admin reste en brouillon. Aucune disponibilité publique n'est confirmée.

| Application | ID Play Console | Version de production |
|---|---|---|
| [BIZZOO](https://play.google.com/console/u/0/developers/7195819094188094036/app/4972105003929543805/app-dashboard) | `4972105003929543805` | Piste `4698764254350008119`, release `1` |
| [BIZZOO Admin](https://play.google.com/console/u/0/developers/7195819094188094036/app/4975498465623729796/app-dashboard) | `4975498465623729796` | Piste `4698395075571677062`, release `1` |

## Résultats locaux

- Compilation des deux AAB 3.54.1 (96) réussie à partir du commit UGC
  `80a72da` et des fichiers Web et pages légales figés.
- Signature de chacun vérifiée avec `jarsigner` ; packages, versions et
  contenus embarqués contrôlés avec `bundletool` et l'archive AAB. Les 69
  fichiers client et 71 fichiers Admin embarqués correspondent octet par octet
  aux sources du commit ; `bundletool validate` accepte les deux bundles.
- Les deux AAB visent Android SDK 36, avec un minimum SDK 24.
- Android Lint : aucune erreur, 15 avertissements par variante
  (API anciennes, icônes, orientation et configuration WebView notamment).
- Contrôles des fichiers autonomes et des coquilles hors connexion réussis.
- Les APK universels générés depuis les deux AAB UGC finaux ont été installés
  sur un émulateur Android 14. BIZZOO ouvre le catalogue public, la catégorie
  Smartphones et une fiche produit réelle. Le bouton « Signaler cette fiche »
  y est visible et redirige vers la connexion pour un visiteur anonyme.
  BIZZOO Admin ouvre sa page de connexion avec le contact public attendu.
  Les captures de ce contrôle sont dans le dossier privé de remise. Les
  parcours authentifiés, notamment les avis et la modération Admin, ainsi que
  les accès de revue Play restent à tester avec un compte autorisé.
- Les deux AAB signés ont été acceptés dans les versions de production en
  brouillon, avec notes de version françaises et le Bénin comme pays choisi.
  Aucune version n'a été envoyée à Google pour examen.
- Accès Supabase confirmé dans le profil Chrome **Hospice (UTRAGBenin)**,
  compte `hospiceantonio`, organisation CREATIS INTER. Le projet attendu
  est affiché en production avec le statut Healthy. La migration de
  suppression de compte y a été appliquée : RPC présente, accessible à un
  utilisateur authentifié et refusée à `anon`, avec le drapeau de commande
  attendu. Cela ne valide pas encore les parcours métier authentifiés.
- La migration `supabase/moderation-ugc.sql` a été exécutée en production.
  Un contrôle SQL en lecture seule confirme les tables, la RPC et le filtre
  d'avis ; l'exécution de la RPC est autorisée au rôle `authenticated` et
  refusée à `anon`. Les écrans authentifiés restent à tester sur Android.
- Le RCCM fourni identifie **MATERIEL NET SARL** comme exploitant de BIZZOO.
  Le contact public choisi est `contact@bizzoomarket.com`, avec
  `bizzoomarket@gmail.com` et `+229 01 42 32 32 38` en complément.
- La politique de confidentialité et la page de suppression du compte sont
  publiques et ont répondu en HTTP 200 avec leur contenu final :
  <https://hospiceantonio.github.io/impact-informatique-app/legal/confidentialite.html>
  et <https://hospiceantonio.github.io/impact-informatique-app/legal/suppression-compte.html>.
  La CI GitHub Pages du code UGC a réussi.
  Les chemins `/legal/` sur `www.bizzoomarket.com` renvoient encore 404 ;
  utiliser les URL GitHub Pages pour la première soumission.

Empreintes SHA-256 des AAB finaux du 29 septembre, à recalculer après toute modification :

```text
client 8916cb2e4097743d1b241a8160d71a8bc34235d07ae7ec4d1ecdfb0df18ae7da
admin  f2595d8b6e9362f2d6105fa1621aa3cd40c8edf64ffba839dc05c8e12ea54185
```

## Construction

Java 17, Android SDK 36 et Node.js sont nécessaires. Définir `JAVA_HOME`
et `ANDROID_HOME` selon la machine, puis lancer :

```sh
python3 tools/construire-play.py
```

La signature provient des variables `BIZZOO_PLAY_STORE_FILE`,
`BIZZOO_PLAY_STORE_PASSWORD`, `BIZZOO_PLAY_KEY_ALIAS` et
`BIZZOO_PLAY_KEY_PASSWORD`, ou du fichier privé
`~/.config/bizzoo/android/play-signing.json`. Ne jamais committer ce fichier
ni afficher ses valeurs. La clé d'envoi doit être conservée et sauvegardée
dans un coffre sécurisé avant la première diffusion.

Les variantes `clientPlay` et `adminPlay` produisent les AAB Google Play.
Elles refusent une construction sans signature privée. Les variantes
`clientRelease` et `adminRelease` continuent à produire les APK de test
du workflow existant, avec leur clé historique.

Google Play App Signing doit gérer la signature de distribution. Les
installations des APK historiques signés avec la clé de test ne pourront
pas être mises à jour directement par une version signée différemment.
Ne pas demander une désinstallation avant d'avoir vérifié la synchronisation
des données et expliqué la perte éventuelle des données locales.

## Fiches françaises préparées

### BIZZOO

Description courte :

> Découvrez les boutiques, commandez et suivez vos achats au même endroit.

Description complète :

> BIZZOO réunit les boutiques dans une seule application. Parcourez les
> catalogues, consultez les fiches produits et préparez votre panier.
>
> Commandez auprès des boutiques, payez par Mobile Money et retrouvez
> le suivi de vos commandes. Enregistrez vos favoris et vos adresses pour
> préparer vos prochains achats. Contactez le service après-vente depuis
> vos commandes lorsque vous avez besoin d'aide.
>
> Le catalogue déjà chargé reste consultable hors connexion. Une connexion
> Internet est nécessaire pour actualiser les données, se connecter,
> commander et payer.

### BIZZOO Admin

Description courte :

> Gérez votre boutique BIZZOO, vos produits, commandes et livraisons.

Description complète :

> BIZZOO Admin accompagne les boutiques et les livreurs du réseau BIZZOO.
> Un compte professionnel autorisé est nécessaire pour accéder à l'application.
>
> Selon les droits de votre compte, gérez le catalogue et les stocks,
> consultez les commandes, organisez leur préparation et suivez les
> livraisons. Les outils de suivi et de service après-vente rassemblent
> les opérations de votre activité.
>
> Les fonctionnalités disponibles dépendent de votre rôle : boutique,
> livreur ou administration de l'enseigne.

## Éléments prêts pour les fiches Play

- Les icônes 512 × 512 sont dans `client/icons/icon-512.png` et
  `admin/icons/icon-512.png`. Les bannières 1024 × 500, les captures réelles
  et les AAB finaux sont dans `~/Downloads/BIZZOO-Play-2026-09-29/`.
- La fiche BIZZOO est complète et enregistrée : textes français, catégorie
  Shopping, contacts publics, site HTTPS, icône, bannière et quatre captures
  Android réelles du catalogue. La fiche Admin a les textes, la catégorie
  Professionnel, les contacts, l'icône et la bannière enregistrés. Le 2 octobre,
  ses deux captures Android existantes (connexion et conditions légales) ont
  été importées et sa fiche est **Prête à être envoyée pour examen**. Des vues
  métier authentifiées restent souhaitables pour mieux présenter l'application.
- Les deux politiques de confidentialité sont enregistrées avec l'URL
  GitHub Pages. La page de suppression du compte est renseignée dans la
  déclaration BIZZOO, qui permet la création de compte dans l'application.
- La publicité est déclarée **oui** pour BIZZOO (mises en avant internes),
  **non** pour Admin. L'ID publicitaire est déclaré absent pour les deux.
  Les déclarations « aucune fonctionnalité financière », « aucune
  fonctionnalité santé » et « application non gouvernementale » sont
  enregistrées pour les deux packages.
- Les déclarations Sécurité des données ont été importées par CSV, vérifiées
  puis enregistrées en brouillon pour les deux apps : collecte oui, chiffrement
  en transit oui, catégories de données métier et de localisation renseignées.
  La transmission à Supabase et aux prestataires de paiement comme sous-traitants
  n'est pas comptée comme partage ; les réponses doivent rester cohérentes
  avec les usages effectifs avant l'envoi final. Le formulaire Admin final
  déclare la création de comptes professionnels par email et mot de passe
  dans l'application, conformément à `Store.creerCompte`. Le lien public de
  suppression de compte est renseigné. L'option facultative de suppression
  de données *sans fermeture du compte* reste « non ».
- Les questionnaires IARC ont été envoyés et affichent l'état « Terminée » :
  BIZZOO est classée 12 ans et plus pour le reste du monde (avis, catalogue
  marchand et achats d'articles numériques externes à l'application) ;
  BIZZOO Admin est classée 3 ans et plus. Admin ne propose aucun achat
  numérique. Le descripteur IARC « Achats in-app » de BIZZOO reflète que
  STOCK PRO et L'ADDITION peuvent être commandés dans la place de marché ;
  ces logiciels sont installés et utilisés hors des applications BIZZOO.
  La [règle Google sur les paiements](https://support.google.com/googleplay/android-developer/answer/10281818?hl=en)
  distingue les biens numériques utilisables uniquement hors d'une app Play.

## Envoi BIZZOO du 2 octobre 2026

Les informations de connexion du compte client ont été enregistrées dans
Play Console, avec des instructions en anglais, sans publier le mot de passe
dans le dépôt. La valeur masquée du formulaire Apple a été remplacée dans
Google par l'identifiant original du dossier privé. La revue a ensuite été
relancée avec cette correction ; aucune modification ne reste à envoyer pour
BIZZOO. Le compte client de revue se connecte sur l'application web
GitHub Pages. L'accès de revue Admin a ensuite été élargi avec l'accord
spécifique du propriétaire, comme décrit ci-dessous.
La cible est 18 ans et plus. Le questionnaire Sécurité des
données importé a été parcouru, vérifié, puis enregistré définitivement.

La release 96 a été prévisualisée et confirmée. L'unique avertissement concerne
l'absence de fichier de désobscurcissement ; aucune erreur bloquante ne figure
sur cet écran. Les dix modifications ont été envoyées depuis la vue d'ensemble
de la publication. Preuve locale :
`docs/publication-evidence/2026-10-02/google-client-review.jpg`.

## Envoi BIZZOO Admin du 2 octobre 2026

Le propriétaire a confirmé l'élargissement de l'accès de revue. Le compte
Admin est désormais **superadministrateur**, actif et sans rattachement à une
boutique. Les trois restrictions Storage propres à ce compte ont été retirées,
sans modifier les autres politiques. Il accède donc aux données réelles de
l'enseigne. Les instructions de revue demandent de commencer les essais
d'édition dans la boutique de démonstration fermée et d'éviter les commandes
réelles. Un retour aux droits précédents est préparé dans le dossier privé.

Un compte de revue **livreur**, actif et rattaché à la boutique de démonstration,
permet d'ouvrir l'écran réservé aux livreurs. Sa liste de courses est vide.
Les deux identités sont authentifiées avec leurs identifiants originaux. Les
écrans web « Mon compte » confirment leurs rôles ; « Mes courses » s'ouvre pour
le livreur. Les identifiants des deux rôles sont enregistrés dans les
informations de connexion Play, en anglais et hors dépôt. La cible est 18 ans
et plus, et la déclaration Sécurité des données est enregistrée définitivement.

La release de production **96 (3.54.1)** est confirmée, avec le Bénin comme
seul territoire. L'unique avertissement technique concerne l'absence de fichier
de désobscurcissement. Google a aussi signalé automatiquement les captures
comme illustrations promotionnelles. Les fichiers ont été vérifiés : ils
montrent les écrans réels de connexion et de conditions d'utilisation.
L'option proposée par la console pour poursuivre vers la revue humaine a été
confirmée ; ce signalement peut encore conduire à un refus lors de la revue.
Les captures métier Android authentifiées restent à améliorer.

Les **dix modifications** ont été envoyées le 2 octobre 2026. La console
confirme **Modifications en cours d'examen**, sans modification restante à
envoyer ni contrôle rapide encore en cours. La publication gérée est
désactivée : la publication suivra l'approbation Google. Ce statut confirme
la soumission, pas encore l'approbation ni la disponibilité publique.
Preuve locale : `docs/publication-evidence/2026-10-02/google-admin-review.jpg`.

BIZZOO client affiche également **Modifications en cours d'examen**, sans
modification restante à envoyer. Les deux apps Android sont donc soumises.

## Sources officielles vérifiées

- [Cible Android 16 / API 36](https://developer.android.com/google/play/requirements/target-sdk)
- [Compatibilité Android Gradle Plugin 8.10](https://developer.android.com/build/releases/agp-8-10-0-release-notes)
- [Suppression des comptes](https://support.google.com/googleplay/android-developer/answer/13327111?hl=fr)
- [Données utilisateur et confidentialité](https://support.google.com/googleplay/android-developer/answer/10144311?hl=fr)
