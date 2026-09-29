# Publication BIZZOO sur Google Play

État vérifié le 29 septembre 2026. Compte choisi par le propriétaire :
**WINNER MARKET LIFE**, organisation `7195819094188094036`.

| Application | Package existant conservé | Version préparée |
|---|---|---|
| BIZZOO | `com.impactinformatique.client` | 3.54.1 (96) |
| BIZZOO Admin | `com.impactinformatique.admin` | 3.54.1 (96) |

Les deux applications sont toujours absentes du compte Play lors du dernier
contrôle. Leurs formulaires de création sont préremplis dans Chrome, sans que
les attestations requises aient été cochées. La préparation locale ne constitue
ni une création d'application Play, ni une soumission.

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
- Les deux applications ont été installées sur un émulateur Android 14 à partir
  des AAB précédant la correction UGC. L'accueil et les catégories de BIZZOO,
  puis l'écran de connexion et les CGU de BIZZOO Admin, ont été capturés sans
  compte connecté.
  Les AAB UGC finaux n'ont pas été réinstallés sur cet émulateur ; les parcours
  authentifiés et les tests de revue Play restent à faire.
- Aucun AAB envoyé, aucune application créée, aucune release soumise.
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
- Les deux URL légales ci-dessus sont prêtes à être saisies dans la console
  Play. La page de suppression détaille le parcours dans l'application et la
  demande sans réinstallation.
- BIZZOO affiche une section « Publicité » pour des mises en avant de
  boutiques. Sa déclaration de publicité doit refléter cet affichage.
- Les deux applications collectent des données de compte et métier via
  Supabase ; la déclaration Data Safety doit être renseignée pour chaque
  package, y compris les données traitées dans la WebView.

## Conditions encore nécessaires avant soumission publique

- Obtenir la confirmation du propriétaire pour les deux attestations du
  formulaire de création de chaque application : conformité aux règles Play
  et respect des lois américaines sur l'exportation. Les deux cases restent
  décochées. Créer ensuite les applications Play et relever leurs identifiants.
- Renseigner les fiches, les contacts, les URL légales, les captures et les
  bannières. Compléter les déclarations de contenu, de publicité, de public
  cible, de classification IARC et de sécurité des données selon le code.
- Fournir à Google des identifiants de revue professionnels réutilisables,
  sans code à usage unique, pour BIZZOO Admin ; fournir aussi l'accès aux
  fonctionnalités privées de BIZZOO. Tester ces parcours sur Android sans
  déclencher de paiement réel.
- Confirmer sur Android les écrans authentifiés de signalement, masquage et
  traitement des signalements avant de déclarer le dispositif UGC entièrement
  opérationnel.
- Configurer Play App Signing, uploader les deux AAB finaux, vérifier les
  résultats Play et soumettre les releases à l'examen sur la piste production.
  La disponibilité publique dépend ensuite de la revue Google.

## Sources officielles vérifiées

- [Cible Android 16 / API 36](https://developer.android.com/google/play/requirements/target-sdk)
- [Compatibilité Android Gradle Plugin 8.10](https://developer.android.com/build/releases/agp-8-10-0-release-notes)
- [Suppression des comptes](https://support.google.com/googleplay/android-developer/answer/13327111?hl=fr)
- [Données utilisateur et confidentialité](https://support.google.com/googleplay/android-developer/answer/10144311?hl=fr)
