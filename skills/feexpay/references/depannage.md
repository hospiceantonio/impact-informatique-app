# Dépannage — symptôme, cause, correctif

Chacune de ces lignes a coûté du temps réel. Plusieurs symptômes désignent la
mauvaise cause si on les lit naïvement : c'est ce qui les rend chers.

## Avant de chercher : regardez le journal

Si vos fonctions ne journalisent pas ce qu'elles envoient et ce qu'on leur
répond, commencez par ça. Tout ce qui suit se diagnostique en dix secondes avec
deux lignes de journal, et en une soirée sans.

```ts
console.log("feexpay/payer →", reseau, JSON.stringify(charge));   // jeton retiré
console.error("feexpay/payer ←", reponse.status, texte.slice(0, 600));
```

Le **code HTTP à lui seul** réduit déjà le champ : `403` désigne une
autorisation, `400` le contenu de la demande, `5xx` une panne chez eux.

---

## Table

| Symptôme | Cause | Correctif |
|---|---|---|
| **`502 Bad Gateway` sur toutes les adresses**, y compris `/api/static/feexpay_logo` | La V1 est **retirée**. Ce n'est pas une panne. | Migrer vers `api-v2.feexpay.me`. Ne pas attendre un rétablissement. |
| **« FeexPay a refusé la demande »** sans autre information | Votre code appelle « refus » tout statut non-2xx. | Distinguer : 4xx = refus, 5xx = panne, 429 = trop de demandes. Et remonter **leur** phrase au client. |
| **Refus systématique sur MTN**, les autres passent | Un **caractère spécial dans `description`**. Un tiret suffit (`Commande BZ-000005`). | `description.replace(/[^a-zA-Z0-9 ]/g, "")`. Retirer, pas remplacer par une espace. |
| **Refus sur tous les opérateurs après une migration** | Le numéro est au format V1 (sans `229`). | `229` + national à dix chiffres : `2290197444893`. |
| **`Celtiis BJ API Error`** (ou l'équivalent) sur **un seul** opérateur | Adresse fausse (`celtiis` au lieu de `celtiis_bj`) — **ou** le réseau n'est pas activé sur le compte marchand — **ou** une panne de leur intégration. | Vérifier l'adresse ; vérifier les réseaux activés sur `app-v2.feexpay.me` ; si les autres opérateurs passent avec la **même** boutique et le **même** jeton, c'est chez eux : le corps envoyé est identique, seul le segment change. |
| **Le paiement part, mais la commande reste « à payer » pour toujours** | La vérification V2 **exige le jeton** ; sans lui, elle échoue en silence. | Ajouter `Authorization: Bearer` sur `/single/status/`. Vérifier que la fonction de notification l'a aussi. |
| **Idem, mais seulement quand le client rouvre l'application sur le reçu** | Les réglages de paiement sont chargés **sans être attendus** au démarrage ; l'écran lit l'agrégateur avant la réponse et retombe sur le défaut. | Attendre les réglages avant de dessiner l'écran, comme le fait déjà l'écran de paiement. |
| **Le client reste devant un sablier alors que le versement a échoué** | `FAILED` traité comme une attente. | `FAILED` est un verdict : le dire, laisser la commande « à payer », permettre une nouvelle tentative. |
| **Le téléphone sonne alors que la demande est refusée pour cause de délai** | Le frein des trente secondes est vérifié **après** l'appel à FeexPay. | Le vérifier **avant**. La référence n'est notée qu'après une réponse valable, donc un appel raté n'entame pas le frein. |
| **Le client s'entend dire « vérifiez votre numéro » alors que son solde est vide** | Chez **Moov**, un `FAILED` immédiat signifie le plus souvent un solde insuffisant. | Parler du **solde** d'abord, et joindre `reason`. |
| **On demande au client de valider un versement déjà validé** | Moov peut répondre `SUCCESSFUL` dès l'ouverture. | Adapter le message au statut rendu. Mais **ne pas encaisser** sur cette réponse : la vérification tranche. |
| **Une commande est encaissée sans que personne n'ait payé** | La notification a été crue. | Ne garder que `reference` du payload, et redemander à FeexPay. Le montant vient de **cette** réponse. |
| **La même notification encaisse deux fois** | Pas d'idempotence. | Index unique sur la référence, et une commande déjà payée renvoie 200 sans rien refaire. |
| **Une commande reste « à payer » et la notification n'est jamais rejouée** | La fonction de notification répond **200** quand la lecture du statut échoue. Sur un 401 — donc une faute de jeton, pas un problème de versement — FeexPay considère la notification délivrée et ne revient jamais. L'encaissement est perdu en silence. | N'acquitter que ce qui est sans retour : un 404 (référence inconnue de FeexPay). Sur 401, 403 ou 5xx, répondre 503 pour qu'elle revienne. |
| **FeexPay rejoue indéfiniment la même notification** | Vous répondez autre chose qu'un 200 sur un événement qui ne vous concerne pas. | 200 pour « pas pour nous » ; réservez les autres codes à « je n'ai pas pu traiter, réessayez ». |
| **Un succès est annoncé sans montant** | Cela arrive. | Ne pas encaisser : le marchand tranche à la main, avec la référence. |
| **« Numéro incomplet » ou refus immédiat sur un numéro valide** | Format à huit chiffres d'avant 2023, ou `+229` collé. | Normaliser : retirer le non-numérique, retirer `229` en tête, préfixer `01` si huit chiffres, puis remettre `229`. |
| **Tout marche en test, rien en production** | Vous avez reproduit le « bac à sable » de leur SDK, qui **fabrique un succès côté client** sans appeler l'API. | Supprimer ce mode. Éprouver avec une doublure de leur API, et un petit montant réel pour le bout de la chaîne. |
| **Le jeton se retrouve dans l'APK ou dans le navigateur** | Vous avez suivi leur SDK React, qui le met côté client. | Le jeton ne quitte jamais le serveur. C'est tout l'intérêt de passer par une fonction Edge. |
| **Un appel est rejeté avant d'entrer dans la fonction Edge** | `--no-verify-jwt` manquant. | Ni le client ni FeexPay n'envoient de jeton Supabase. Ce qui protège l'appel, c'est le numéro de téléphone de la commande, vérifié en base. |
| **`{"erreur":"corps illisible"}` en testant à la main** | Requête sans corps JSON, ou `Content-Type` absent. | C'est le signe que la fonction est **déployée et vivante**. Envoyer un vrai corps. |

---

## Deux réflexes qui évitent la moitié de cette table

**Un délai dépassé n'est pas un échec.** Le versement a peut-être abouti. Ne
marquez jamais « échoué » sur une erreur réseau : c'est la première cause des
« j'ai été débité mais rien n'est arrivé ».

**L'ordre n'est pas garanti.** La notification peut arriver avant que vous ayez
fini de ranger la référence, et le client peut vous interroger avant la
notification. Les deux chemins doivent rester commutatifs — chacun doit pouvoir
constater l'encaissement sans l'autre, et deux constats ne doivent pas encaisser
deux fois.

---

## Quand écrire à leur support

Quand vous avez éliminé ce qui vous appartient. Un rapport utile ressemble à
ceci — il coupe court à tout ce qu'ils vous renverraient vérifier :

> `POST /api/transactions/public/requesttopay/celtiis_bj` répond
> « Celtiis BJ API Error ».
>
> - numéro `2290144483333` (préfixe Celtiis valide), montant 1100
> - boutique `<identifiant>`, Celtiis **activé** sur notre compte marchand
> - les mêmes appels sur `/requesttopay/mtn` **et** `/requesttopay/moov`
>   **fonctionnent** — même boutique, même jeton, corps identique, seul le
>   segment de l'URL change
>
> Le problème semble donc propre à votre intégration Celtiis. Incident connu ?

En attendant leur réponse, refermez le réseau par **réglage** plutôt que par
déploiement (`FEEXPAY_RESEAUX='mtn,moov'`), et dites au client lesquels marchent
plutôt que de le laisser buter.
