# Publication BIZZOO sur Google Play

Préparation du 26 septembre 2026. Compte choisi par le propriétaire :
**WINNER MARKET LIFE**, organisation `7195819094188094036`.

| Application | Package existant conservé | Version préparée |
|---|---|---|
| BIZZOO | `com.impactinformatique.client` | 3.54.1 (96) |
| BIZZOO Admin | `com.impactinformatique.admin` | 3.54.1 (96) |

Les deux applications étaient absentes du compte Play lors du contrôle.
La préparation locale et un formulaire prérempli ne constituent pas une publication.

## Résultats locaux

- Compilation des deux AAB 3.54.1 (96) réussie.
- Signature de chacun vérifiée avec `jarsigner`.
- Android Lint : aucune erreur, 15 avertissements par variante
  (API anciennes, icônes, orientation et configuration WebView notamment).
- Alignement des migrations : aucune modification, 236 fonctions déjà à jour.
- Contrôles des fichiers autonomes et des coquilles hors connexion réussis.
- Les parcours authentifiés sur appareil et les tests de revue Play restent à faire.
- Aucun AAB envoyé, aucune application créée, aucun changement de base déployé.
- Accès Supabase confirmé dans le profil Chrome **Hospice (UTRAGBenin)**,
  compte `hospiceantonio`, organisation CREATIS INTER. Le projet attendu
  est affiché en production avec le statut Healthy. Cela confirme l'accès
  au tableau de bord, pas encore les parcours métier des applications.
- La page publique `client/#/infos` fournit des contacts téléphoniques et
  WhatsApp, mais aucun e-mail de support. Elle attribue le développement
  à CREATIS INTER ; cela ne suffit pas à identifier l'exploitant juridique.

Empreintes des AAB de préparation, à recalculer après toute modification :

```text
client a3d3c80b2812efb50ad4b75ed6712a890bfd7c9aabb2bee2ebd14d0b42019e14
admin  3f4eca419e6e2956e50d19c74125370552e4bd939deacf481525a71243cac19a
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

## Conditions encore nécessaires avant soumission publique

- Confirmer l'exploitant juridique, le contact public et les durées de conservation.
- Publier une politique de confidentialité accessible et la relier dans les deux applications.
- Fournir un parcours de demande de suppression de compte dans l'application
  et une page web accessible sans réinstallation. Le contrôle existant de
  suppression est réservé aux administrateurs et interdit l'autosuppression.
- Terminer la vérification de configuration du projet Supabase `rrwzegmrmvvkmzfoiitb` et
  les parcours authentifiés, sans paiement réel.
- Créer les deux fiches Play, accepter les déclarations requises avec
  confirmation du propriétaire, puis configurer Play App Signing.
- Fournir les captures, la bannière, l'icône, les accès de revue et les
  déclarations de contenu, publicité et sécurité des données fondées sur les usages réels.
- Uploader les AAB, vérifier les résultats Play et les parcours sur Android,
  puis soumettre à l'examen. La disponibilité publique dépend de Google.

## Sources officielles vérifiées

- [Cible Android 16 / API 36](https://developer.android.com/google/play/requirements/target-sdk)
- [Compatibilité Android Gradle Plugin 8.10](https://developer.android.com/build/releases/agp-8-10-0-release-notes)
- [Suppression des comptes](https://support.google.com/googleplay/android-developer/answer/13327111?hl=fr)
- [Données utilisateur et confidentialité](https://support.google.com/googleplay/android-developer/answer/10144311?hl=fr)
