---
name: feexpay
description: >-
  Intégration de l'API V2 de FeexPay (agrégateur de paiement Mobile Money au
  Bénin — MTN, Moov, Celtiis, carte, en FCFA) côté SERVEUR, avec des fonctions
  Edge Supabase : encaissement, vérification du versement, notification non
  signée, et tous les pièges de la migration V1 → V2. À utiliser dès que
  l'utilisateur parle de FeexPay, d'api-v2.feexpay.me, de requesttopay, de
  Mobile Money au Bénin, d'encaisser un paiement en FCFA, de jeton fp_, de
  webhook de paiement — et tout particulièrement quand l'API répond
  « 502 Bad Gateway » sur toutes ses adresses, quand une demande est refusée
  sans explication, quand un opérateur passe et pas un autre, ou quand une
  commande reste « à payer » alors que le client a été débité. Use when
  integrating FeexPay or Mobile Money payments in Benin, or when debugging a
  FeexPay request that is refused, a payment that never confirms, or an
  operator that works for MTN but not for Celtiis.
---

# Paiement Mobile Money avec FeexPay (API V2)

FeexPay est un agrégateur béninois : MTN, Moov, Celtiis, Coris, carte bancaire.

Cette compétence rassemble une intégration qui a été menée jusqu'au premier
encaissement réel, et surtout **ce qui coûte des heures et ne figure nulle
part**. Leur documentation décrit le cas nominal ; presque rien de ce qui suit
n'y est écrit, et plusieurs points la contredisent.

> **Avertissement qui sert de fondation.** Au moment où ces lignes sont
> écrites, **les trois SDK publics de FeexPay (React sur npm, Flutter sur
> pub.dev, PHP sur GitHub) pointent encore vers l'API V1**, qui est retirée.
> Ne les prenez pas pour le contrat. Ils restent utiles pour comprendre des
> comportements — leur code révèle des règles que la documentation tait — mais
> les adresses et les champs qu'ils utilisent sont périmés.

## Le principe, à ne jamais contourner

**L'application ne déclare jamais un paiement.** C'est le serveur qui ouvre la
demande, garde la référence, puis va *demander* à FeexPay si le versement a
abouti.

```
App ──« ouvre le paiement »──▶ Edge Function ──Bearer fp_──▶ FeexPay
                                    │                            │
                                    │◀── référence ──────────────┘
                                    │
App ──« où en est-ce ? »─────▶ Edge Function ──Bearer fp_──▶ /single/status/<ref>
                                    │                            │
                                    │◀── SUCCESSFUL + montant ────┘
                                    ▼
                              marquer_payee()   (service_role)
```

Deux raisons, et la seconde est décisive :

1. **Le jeton `fp_…` est un secret porteur.** Leur SDK React le met dans le
   navigateur ; leur propre README dit pourtant de ne jamais exposer un jeton
   sensible. Dans un APK, il se lit en clair. Il ne doit vivre que dans les
   secrets du serveur.
2. **La notification de FeexPay n'est signée par rien** (voir piège 5). Elle ne
   peut donc pas décider d'un encaissement. Seule la réponse que FeexPay donne
   à *votre* question fait foi.

Conséquence dans l'interface : après le paiement, on **attend** que la commande
bouge, on ne l'annonce pas.

## Où vit chaque secret

| Élément | Où il vit | Jamais |
|---|---|---|
| `shop` (identifiant de boutique) | Secret serveur | — peu sensible, mais inutile ailleurs |
| **jeton `fp_…`** | Secret serveur (`FEEXPAY_TOKEN`) | dans l'app, dans un dépôt, dans une conversation |
| Secret de webhook | **il n'en existe pas** | — voir piège 5 |

Le jeton doit être posé par l'utilisateur lui-même (`supabase secrets set`, ou
le tableau de bord Supabase) : il n'a aucune raison de transiter par une
conversation, où il resterait écrit. Sous PowerShell, **guillemets simples** —
les doubles interpolent `$`.

## Le contrat V2, l'essentiel

Base : `https://api-v2.feexpay.me`

| | |
|---|---|
| Encaisser | `POST /api/transactions/public/requesttopay/{mtn\|moov\|celtiis_bj}` |
| Vérifier | `GET /api/transactions/public/single/status/{reference}` |
| En-tête, **sur les deux** | `Authorization: Bearer fp_…` |
| Corps, obligatoire | `phoneNumber`, `amount`, `shop` |
| Corps, facultatif | `first_name`, `last_name`, `description`, `callback_info` |
| Montant | **100 à 2 000 000 XOF** |
| États | `PENDING`, `IN PENDING STATE`, `SUCCESSFUL`, `FAILED` |

`references/contrat-v2.md` donne le détail complet : réponses type, champs
rendus, table des préfixes béninois, commissions, et ce que la V1 faisait
différemment.

## Les six pièges

Quatre échouent en silence ou avec un message trompeur. Lisez-les avant
d'écrire la moindre ligne.

### 1. Le numéro porte l'indicatif — la V1 voulait l'inverse

V2 attend `229` **suivi** du numéro national à dix chiffres commençant par
`01` : `2290197444893`. La V1, elle, voulait qu'on **retire** le `229`.

C'est un renversement exact, et aucune relecture ne le rattrape : le code
« marchait » avant, il ne marche plus, et le message de refus ne dit pas
pourquoi. Acceptez ce que le client tape — huit chiffres à l'ancienne, format
international, espaces — et ramenez tout à cette seule forme.

### 2. La description ne supporte aucun caractère spécial

Un simple **tiret** fait refuser la demande. Leur documentation V2 l'écrit
enfin — « description : sans caractères spéciaux » — et leur SDK le fait depuis
toujours, pour MTN précisément :

```js
if (network === "MTN") description = description.replace(/[^a-zA-Z0-9 ]/g, "");
```

Si vos commandes s'appellent `BZ-000005`, **aucun paiement MTN ne passera** et
vous chercherez ailleurs pendant des heures. Nettoyez pour tous les opérateurs :
un libellé sans ponctuation ne coûte rien. **Retirez** le caractère au lieu de
le remplacer par une espace — `Commande BZ000005` se retrouve d'un bloc dans
leur tableau de bord, `Commande BZ 000005` non.

La même prudence vaut pour `first_name` : la passerelle Celtiis parle SOAP, et
une apostrophe dans « N'Dah » n'a rien à faire dans du XML assemblé à la main.

Un détail qui compte en Afrique de l'Ouest : **ramenez les accents à leur
lettre avant de nettoyer**, ne les supprimez pas. Un `[^a-zA-Z0-9 ]` appliqué
seul transforme « Soètonvê » en « Sotonv » — un prénom écorné passe, un prénom
amputé inquiète le client qui le lit sur son téléphone.

```js
texte.normalize("NFD").replace(/[\u0300-\u036f]/g, "")   // é → e
     .replace(/[^a-zA-Z0-9 ]/g, "").replace(/\s+/g, " ").trim();
```

### 3. `celtiis_bj`, et non `celtiis`

Le dernier segment de l'adresse ne se déduit pas des deux autres :

```
…/requesttopay/mtn
…/requesttopay/moov
…/requesttopay/celtiis_bj     ← pas « celtiis »
```

Deviner cette adresse envoie tous les clients Celtiis nulle part. Vérifiez
chaque opérateur dans leur documentation plutôt que d'extrapoler.

### 4. La vérification exige le jeton en V2

En V1, lire le statut d'un versement ne demandait **aucune** authentification —
on pouvait s'en féliciter : le serveur vérifiait sans détenir de secret. En V2,
`/single/status/` exige `Authorization: Bearer`.

L'oublier **ne casse rien de visible** : aucune erreur côté client, aucun
paiement refusé. Les commandes restent simplement « à payer » pour toujours, et
personne ne sait pourquoi. C'est le genre de panne qui met des semaines à se
comprendre. Si vous avez une fonction de notification séparée, elle a besoin du
jeton elle aussi — et doit refuser de répondre 200 s'il lui manque.

### 5. La notification n'est signée par rien

Ni secret, ni signature, ni en-tête d'authentification. Leur documentation V2
l'assume et renvoie la charge au marchand : « c'est à vous d'écouter ces
requêtes […] pour faire **vos contrôles côté serveur** ».

Autrement dit, quiconque connaît l'adresse peut poster :

```json
{ "reference": "…", "status": "SUCCESSFUL", "amount": 999999 }
```

et se faire livrer sans payer un franc.

**Alors on ne la croit pas.** De tout le payload, on ne garde **que la
référence** — une clé de recherche, pas une preuve — et on redemande à FeexPay.
Le montant vient de cette réponse-là, jamais du payload.

Elle sert quand même : un client qui ferme l'application, ou qui met trop
longtemps à taper son code, laisserait sa commande « à payer » pour toujours
puisque plus personne ne redemande. La notification bouche ce trou.

Corollaire moins évident : **n'acquittez pas ce que vous n'avez pas pu
vérifier.** Répondre 200 quand la lecture du statut échoue — un 401 sur un
jeton mal posé, par exemple — fait considérer la notification comme délivrée,
et elle ne reviendra jamais. Un encaissement réel se perd alors sur une faute
de configuration, sans le moindre message. N'acquittez que ce qui est sans
retour (un 404 : FeexPay ne connaît pas cette référence) ; pour tout le reste,
répondez 503 et laissez-la revenir.

### 6. Il n'y a pas de bac à sable utilisable

Le mode `SANDBOX` de leur SDK **n'appelle pas leur API** : il renvoie un succès
écrit en dur.

```js
if (mode === "SANDBOX") return { status: "SUCCESSFUL", … };
```

Reproduire cela côté serveur rouvrirait exactement la porte qu'on passe son
temps à fermer : il suffirait de demander le mode test pour être déclaré payé.
**N'écrivez pas de mode test.** Éprouvez avec un petit montant réel — et voyez
plus bas comment éprouver *tout le reste* sans dépenser un franc.

## Ce que chaque opérateur fait de particulier

- **Moov** répond souvent le statut **final dès l'ouverture** : `FAILED` en cas
  de solde insuffisant, ou `SUCCESSFUL` directement si le client a déjà
  confirmé. Deux conséquences : un `FAILED` immédiat parle d'abord du **solde**,
  pas d'un numéro mal saisi — envoyer le client corriger son numéro, c'est le
  faire chercher ce qui n'a rien ; et quand la réponse est déjà `SUCCESSFUL`, ne
  lui demandez plus de « valider sur son téléphone ». Dans les deux cas,
  **n'encaissez pas sur cette réponse** : la vérification tranche, elle seule.
- **Celtiis** renvoie une enveloppe **SOAP** (Huawei CPS) et un `PENDING`, avec
  une référence de sa forme à lui (`AG_20251202_…`). On ne garde que la
  référence ; elle passe un nettoyage `[A-Za-z0-9_-]` sans dommage.
- **MTN** est le plus strict sur le libellé (piège 2).

## Marche à suivre

1. **Compte marchand** — l'utilisateur récupère son `shop` et son jeton `fp_…`
   sur `app-v2.feexpay.me`. Vérifiez au passage **quels réseaux sont activés**
   sur le compte : ils se contractualisent séparément.
2. **Base** — `assets/paiement-feexpay.sql` pose les colonnes et les trois
   fonctions réservées au serveur : `noter_reference` (avec le frein de trente
   secondes), `commande_pour_paiement` (le montant vient de la base) et
   `commande_par_reference` (pour la notification). Adaptez les noms de tables
   au projet.
3. **Fonctions Edge** — copier `assets/feexpay.ts` et
   `assets/feexpay-webhook.ts`, adapter les noms des fonctions SQL appelées,
   puis faire lancer par l'utilisateur :
   ```bash
   supabase secrets set FEEXPAY_TOKEN='fp_…'
   supabase secrets set FEEXPAY_SHOP='…'
   supabase functions deploy feexpay --no-verify-jwt
   supabase functions deploy feexpay-webhook --no-verify-jwt
   ```
   `--no-verify-jwt` est **indispensable** : ni le client d'une boutique ni
   FeexPay n'envoient de jeton Supabase, l'appel serait rejeté avant d'entrer.
   Ce qui protège l'appel côté client, c'est le **numéro de téléphone de la
   commande**, vérifié en base.
4. **Déclarer l'URL de notification** dans leur tableau de bord → menu Webhook :
   `https://<projet>.supabase.co/functions/v1/feexpay-webhook`
5. **Éprouver sans dépenser** (voir plus bas), puis **un petit montant réel**
   sur chaque opérateur activé. Tant que ce dernier test n'est pas passé,
   l'intégration n'est pas finie.

Si le tableau de bord Supabase est le seul outil disponible — la CLI Supabase
n'est pas toujours installée chez un commerçant — les fonctions s'éditent et se
déploient directement depuis Edge Functions, et les secrets s'y ajoutent aussi.

## Éprouver sans dépenser un franc

C'est la pratique qui rapporte le plus, et celle qu'on néglige : donnez à vos
fonctions un **faux FeexPay**, qui répond ce qu'on lui dit et note ce qu'on lui
a envoyé. `assets/eprouver-paiement.mjs` en est un, complet — il charge les
fonctions Deno sous Node avec une doublure de `Deno`, sans modifier une ligne du
code éprouvé.

Pourquoi cela vaut l'effort : un banc qui appelle vraiment leur API rougit les
jours de panne et ne prouve rien les autres jours. Un banc à doublure éprouve ce
que **votre** code décide.

Ce qu'il faut y constater, au minimum :

- le libellé ne porte que lettres, chiffres et espaces ;
- le numéro part avec son indicatif ;
- le montant vient de la base, pas de la requête ;
- le frein est vérifié **avant** d'appeler FeexPay — sinon le téléphone sonne
  quand même ;
- un succès **sans montant** n'encaisse rien ;
- la notification ne fait rien encaisser sur sa seule parole ;
- le jeton ne sort ni vers le client, ni dans le journal.

Et la règle qui donne sa valeur au banc : **sabotez chaque règle exprès et
vérifiez qu'il rougit**. Sur cette intégration, un constat manquait — une
fonction de notification qui vérifiait sans jeton passait inaperçue — et seul le
sabotage l'a révélé.

## Ce qu'il ne faut pas retirer

- **Le montant vient de la base**, jamais de la requête. Sinon on paie 100
  francs une commande de 100 000.
- **Le frein entre deux demandes** (trente secondes suffisent), vérifié **avant**
  l'appel. Chaque demande fait sonner un téléphone : sans frein, on peut harceler
  n'importe quel numéro depuis le compte marchand — et c'est le marchand qui en
  répond.
- **Un succès sans montant ne s'encaisse pas.** Valider sans montant, c'est
  croire sur parole qu'un versement quelconque règle cette commande-ci.
- **Une panne chez eux n'est pas un refus.** Un 5xx affiché « FeexPay a refusé
  la demande » envoie le client vérifier un numéro qui n'a rien, et le marchand
  douter d'identifiants qui sont bons. Distinguez : 4xx = refus (avec leur
  phrase), 5xx = panne (« rien n'a été débité, réessayez »), 429 = trop de
  demandes.
- **Un délai dépassé n'est pas un échec.** Le versement a peut-être abouti. Ne
  marquez jamais « échoué » sur une erreur réseau — c'est la première cause des
  « j'ai été débité mais rien n'est arrivé ».
- **Journalisez ce que vous envoyez et ce qu'on vous répond**, jeton retiré.
  Sans cette trace, un refus n'est qu'un écran rouge et il ne reste qu'à
  deviner. C'est la seule chose qui transforme une soirée perdue en dix
  secondes de diagnostic.

## Un interrupteur par réseau, pas dans le code

Un agrégateur casse **un** opérateur et pas les autres — c'est arrivé : MTN et
Moov passaient, Celtiis répondait « Celtiis BJ API Error ». Laisser le réseau
ouvert envoie chaque client Celtiis dans le mur ; le retirer du code, c'est un
déploiement pour une panne qui durera peut-être deux heures, et qu'on oubliera
de défaire.

Un réglage (`FEEXPAY_RESEAUX='mtn,moov'`, vide = tous ouverts) referme un réseau
en une ligne, sans redéploiement ni nouvelle version de l'application. **Un état
temporaire appartient à la configuration, pas au code.**

## Fichiers de cette compétence

- `references/contrat-v2.md` — le contrat complet : adresses, champs, réponses
  type par opérateur, table des préfixes béninois, commissions, limites, et ce
  que la V1 faisait différemment. À ouvrir avant d'écrire l'appel.
- `references/depannage.md` — **table symptôme → cause → correctif**. À ouvrir
  dès qu'un paiement se comporte bizarrement ; aucun de ces symptômes ne se
  devine, et plusieurs désignent la mauvaise cause si on les lit naïvement.
- `assets/feexpay.ts` — la fonction Edge d'encaissement et de vérification.
- `assets/feexpay-webhook.ts` — la notification, qu'on écoute sans la croire.
- `assets/paiement-feexpay.sql` — colonnes, frein, et les trois fonctions
  réservées au serveur.
- `assets/eprouver-paiement.mjs` — le banc à doublure, une centaine de constats.

Documentation officielle :
<https://docs.feexpay.me/?section=api-rest-integrations&version=v2>.
Elle décrit le cas nominal ; ce qui précède décrit ce qu'on rencontre
réellement.
