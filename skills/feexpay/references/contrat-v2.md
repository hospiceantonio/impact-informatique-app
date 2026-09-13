# Le contrat de l'API V2 — ce qui est vérifié

Tout ce qui suit vient de leur documentation V2 ou d'appels réels. Ce qui est
tiré de leurs SDK — donc de la V1 — est signalé comme tel.

## Sommaire

1. [Encaisser (payin)](#1-encaisser-payin)
2. [Vérifier un versement](#2-vérifier-un-versement)
3. [La notification (webhook)](#3-la-notification-webhook)
4. [Les opérateurs du Bénin](#4-les-opérateurs-du-bénin)
5. [Les préfixes béninois](#5-les-préfixes-béninois)
6. [Commissions et limites](#6-commissions-et-limites)
7. [Ce que la V1 faisait différemment](#7-ce-que-la-v1-faisait-différemment)

---

## 1. Encaisser (payin)

```
POST https://api-v2.feexpay.me/api/transactions/public/requesttopay/<réseau>
Authorization: Bearer fp_…
Content-Type: application/json
```

Sans l'en-tête, **la requête est refusée** — leur documentation le met en
encadré.

### Le corps

| Champ | Statut | Description | Exemple |
|---|---|---|---|
| `phoneNumber` | **obligatoire** | indicatif + dix chiffres commençant par `01` | `2290166000000` |
| `amount` | **obligatoire** | montant de la transaction | `100` |
| `shop` | **obligatoire** | identifiant de la boutique | `Ayg9lkjkhurIvNp` |
| `first_name` | facultatif | prénom du client | `FeexPay` |
| `last_name` | facultatif | nom du client | `FeexPay` |
| `description` | facultatif | **sans caractères spéciaux** | `Achat de produit` |
| `callback_info` | facultatif | **une chaîne**, rendue telle quelle | `order_12345` |

Ne mettez **rien d'autre**. `token`, `currency`, `reseau`, `customId`,
`merchant_domain`, `merchant_ip`, `payment_interface` et `otp` appartiennent à
la V1 ou au navigateur ; le jeton vit dans l'en-tête, le réseau dans l'adresse.

### La réponse

```json
{
  "reference": "6a00a986-fcb9-4491-93d5-28693034ef95",
  "message": "Accepted",
  "status": "PENDING",
  "amount": 10,
  "description": "",
  "callback_info": null,
  "phoneNumber": "2290167919150"
}
```

`reference` est la clé de tout l'encaissement : c'est avec elle qu'on ira
demander où en est le versement. Rangez-la **avant** de répondre au client — si
l'écriture échoue, il ne doit pas croire que le paiement est en cours, il le
serait sans qu'on puisse le constater.

---

## 2. Vérifier un versement

```
GET https://api-v2.feexpay.me/api/transactions/public/single/status/<référence>
Authorization: Bearer fp_…
```

**Le jeton est exigé.** En V1 cette lecture était publique.

### Réponse — abouti

```json
{
  "reference": "63ecaff1-7572-413d-93bb-8cba92bb8c2c",
  "amount": 10,
  "phoneNumber": "2290167919150",
  "status": "SUCCESSFUL",
  "callback_info": null,
  "responsecode": "SUCCESSFUL",
  "responsemsg": "SUCCESSFUL",
  "transref": "63ecaff1-7572-413d-93bb-8cba92bb8c2c",
  "serviceref": "63ecaff1-7572-413d-93bb-8cba92bb8c2c",
  "comment": "",
  "reason": "",
  "description": "",
  "date": "2026-06-10T08:36:35.020Z",
  "operator_id": "12243963624"
}
```

### Réponse — échoué

Même forme, avec `"status": "FAILED"` et une `reason` parlante :
`LOW_BALANCE_OR_PAYEE_LIMIT_REACHED_OR_NOT_ALLOWED`, `PAYER_NOT_FOUND`…

C'est le vocabulaire de l'opérateur, pas celui d'un client : gardez-la pour le
marchand et le journal, et dites au client quelque chose qu'il peut corriger.

### Les états

| État | Ce que ça veut dire |
|---|---|
| `PENDING` | en cours, le client n'a pas encore confirmé |
| `IN PENDING STATE` | idem — leur note le mentionne à part |
| `SUCCESSFUL` | abouti |
| `FAILED` | **un verdict**, pas une attente |

Traiter `FAILED` comme une attente fait tourner le sablier quatre-vingt-dix
secondes sur un refus déjà prononcé, et laisse croire au client que ça peut
encore aboutir.

**Un succès sans montant ne s'encaisse pas.** Si `amount` manque, on ne peut pas
vérifier qu'il couvre la commande : laissez le marchand trancher à la main, avec
la référence sous les yeux.

---

## 3. La notification (webhook)

Configurée dans leur tableau de bord → menu **Webhook**. Requête `POST`, corps
JSON. **Aucune signature, aucun secret, aucun en-tête d'authentification.**

```json
{
  "reference": "1e636dff-6b81-499e-bf8b-64b4a07a02a8",
  "order_id": "1e636dff-6b81-499e-bf8b-64b4a07a02a8",
  "status": "SUCCESSFUL",
  "amount": 250,
  "callback_info": "",
  "last_name": "",
  "first_name": "",
  "email": "…",
  "type": "Paiement",
  "phoneNumber": "2290190877433",
  "date": "2026-05-25T10:06:26.662Z",
  "reseau": "MTN CI",
  "ref_link": "",
  "description": "test de 10",
  "reason": "PAYER_NOT_FOUND",
  "ref_operator": ""
}
```

Un échec porte la même forme, avec `status: "FAILED"` et une `reason`.

**De tout cela, ne gardez que `reference`** (ou `order_id`, qui la répète).
Le `status` et le `amount` sont invérifiables : les croire, c'est laisser
n'importe qui écrire `SUCCESSFUL, 999999`.

Répondez **200** à presque tout — une notification qui ne vous concerne pas
n'est pas une erreur, et un refus la ferait rejouer pour rien. Mais répondez
**autre chose qu'un 200** quand vous êtes mal configuré ou que FeexPay est
injoignable : sinon la notification est considérée comme délivrée et ne
reviendra jamais.

---

## 4. Les opérateurs du Bénin

| Réseau | Dernier segment de l'adresse |
|---|---|
| MTN Bénin | `mtn` |
| Moov Bénin | `moov` |
| Celtiis Bénin | `celtiis_bj` |
| Coris Bénin | `coris` *(non vérifié)* |

Le segment ne se déduit pas : `celtiis_bj` le prouve. Vérifiez chaque opérateur
dans leur documentation.

### Moov — le statut final arrive parfois tout de suite

> « Pour Moov Bénin, la réponse peut déjà contenir le statut final (par exemple
> FAILED en cas de solde insuffisant), sans nécessité d'appeler l'API de
> vérification. Si le client confirme le code, la réponse sera directement
> SUCCESSFUL. »

```json
{
  "reference": "32D6CC4C-8AA1-4DFF-80A2-84D34C1BD19F",
  "status": "FAILED",
  "response_operator": { "description": ["Balance is insufficient"], "status": ["10"] },
  "statusCode": "10"
}
```

Notez `response_operator.description` : un **tableau**, pas une chaîne.

### Celtiis — du SOAP dans la réponse

> « La réponse peut inclure une charge utile SOAP. Le champ status peut
> initialement être PENDING ; consultez l'API statut pour confirmation finale. »

La référence a sa forme à elle : `AG_20251202_701033309a4e1387a99b`. Un
nettoyage `[A-Za-z0-9_-]` la laisse intacte. Les champs `normal_response` et
`response_operator` contiennent du XML Huawei CPS — on n'en a pas besoin.

---

## 5. Les préfixes béninois

Table du SDK officiel. Utile pour **proposer** l'opérateur et pour **expliquer**
un refus — pas pour interdire : un numéro porté d'un réseau à l'autre garde son
préfixe d'origine, et c'est au client de savoir chez qui est son compte.

| Réseau | Préfixes (numéro national à dix chiffres) |
|---|---|
| MTN | 0142 0146 0150 0151 0152 0153 0154 0156 0157 0159 0161 0162 0166 0167 0169 0190 0191 0192 0193 0196 0197 |
| MOOV | 0145 0155 0158 0160 0163 0164 0165 0168 0194 0195 0198 0199 |
| CELTIIS | 0140 0141 0143 0144 0147 |

---

## 6. Commissions et limites

- **Mobile Money : 1,7 %** au Bénin (MTN, Moov, Celtiis, Coris).
- **Carte : 4,5 %** (VISA, Mastercard).
- **Montant : 100 minimum, 2 000 000 XOF maximum.**

Vérifiez les bornes **avant** d'appeler : « FeexPay a refusé » n'apprend rien à
un client dont le panier fait quatre-vingts francs.

Autres pays desservis (commissions différentes) : Togo, Côte d'Ivoire, Congo
Brazzaville, Sénégal, Burkina Faso, Mali.

---

## 7. Ce que la V1 faisait différemment

`api.feexpay.me` est **retirée**. Elle répond `502 Bad Gateway` sur *toutes* ses
adresses, y compris celle de son logo — ce n'est pas une panne, et attendre un
rétablissement fait perdre des jours.

| | V1 (retirée) | V2 |
|---|---|---|
| Numéro | `229` **retiré** | `229` **ajouté** |
| Réseau | champ `reseau` du corps (`MTN`, `MOOV`, `CELTIIS BJ`) | dernier segment de l'adresse |
| Jeton | dans le corps **et** l'en-tête | en-tête seulement |
| `callback_info` | un objet | une chaîne |
| Champs en plus | `currency`, `customId`, `otp`, `merchant_*` | supprimés |
| Vérification | `/getrequesttopay/integration/<ref>`, **sans authentification** | `/single/status/<ref>`, **jeton exigé** |

Les SDK publics (React, Flutter, PHP) pointaient encore vers la V1 bien après sa
fermeture. Ne les prenez pas pour le contrat ; leur code reste utile pour
comprendre des comportements que la documentation tait, comme le nettoyage du
libellé.
