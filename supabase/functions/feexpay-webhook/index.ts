/* =========================================================
   BIZZOO — la notification de paiement de FeexPay

   ATTENTION, ET C'EST TOUT LE SUJET DE CE FICHIER :

   LA NOTIFICATION DE FEEXPAY N'EST PAS SIGNÉE — et la V2 n'y
   a rien changé. Le payload est un simple JSON posté sur une
   adresse, sans secret, sans signature, sans en-tête
   d'authentification. Rien n'y prouve qu'il vient d'eux.

   Leur documentation V2 l'assume, et renvoie la charge au
   marchand : « C'est à vous d'écouter ces requêtes, de les
   récupérer et de les traiter pour faire VOS CONTRÔLES CÔTÉ
   SERVEUR. » C'est exactement ce que fait ce fichier.

   Autrement dit : n'importe qui connaissant cette adresse
   peut poster

       { "reference": "...", "status": "SUCCESSFUL", "amount": 999999 }

   et se faire livrer sans payer un franc. Chez KkiaPay, un
   secret partagé réglait la question ; ici, il n'y en a pas.

   ALORS ON NE LA CROIT PAS. Cette notification ne sert qu'à
   une chose : nous DIRE d'aller regarder. C'est notre serveur
   qui redemande ensuite à FeexPay, sur son API à lui, si le
   versement a vraiment abouti — et c'est cette réponse-là qui
   décide. Le montant aussi vient de là, jamais du payload.

   ---------------------------------------------------------
   Pourquoi ce fichier existe quand même
   ---------------------------------------------------------
   L'application interroge déjà pendant 90 secondes après le
   paiement. Mais un client qui ferme l'application, ou qui met
   plus longtemps à taper son code Mobile Money, laissait sa
   commande « à payer » POUR TOUJOURS : plus personne ne
   redemandait. La notification bouche ce trou — et rend la
   confirmation quasi immédiate quand le client, lui, attend.

   ---------------------------------------------------------
   Déploiement (une fois, sur votre poste)
   ---------------------------------------------------------
     supabase functions deploy feexpay-webhook --no-verify-jwt

   Puis, dans le tableau de bord FeexPay → menu Webhook,
   déclarer l'adresse :
     https://<projet>.supabase.co/functions/v1/feexpay-webhook

   « --no-verify-jwt » : FeexPay n'envoie aucun jeton Supabase.
   Sans cette option l'appel serait rejeté avant d'entrer ici.
   Ce n'est pas une négligence — puisqu'on ne croit de toute
   façon rien de ce qui arrive, il n'y a rien à protéger à
   l'entrée. La sécurité est plus loin : dans la vérification.
   ========================================================= */

const BASE = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
/* L'adresse V2 qui dit où en est un versement. La V1 a été retirée — son
   502 sur toutes ses adresses n'était pas une panne. TANT QU'ELLE EST
   VIDE, on ne conclut rien : une notification qu'on ne peut pas vérifier
   ne prouve toujours rien, et mieux vaut la laisser rejouer que
   d'encaisser sur parole. */
const VERIFICATION = Deno.env.get("FEEXPAY_STATUT")
  ?? "https://api-v2.feexpay.me/api/transactions/public/single/status/";

/* EN V2, LA LECTURE DU STATUT EXIGE LE JETON. La V1 ne demandait rien, et
   cette fonction n'avait donc aucun secret à détenir. Ce n'est plus vrai :
   sans lui, elle ne pourrait plus rien vérifier — et comme elle ne croit
   jamais le payload, elle n'encaisserait tout simplement plus rien. */
const JETON = Deno.env.get("FEEXPAY_TOKEN") ?? "";

/** Un appel à notre propre base, avec les droits du service. */
async function rpc(nom: string, parametres: Record<string, unknown>): Promise<unknown> {
  const reponse = await fetch(BASE + "/rest/v1/rpc/" + nom, {
    method: "POST",
    headers: {
      "apikey": SERVICE,
      "Authorization": "Bearer " + SERVICE,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(parametres),
  });
  if (!reponse.ok) throw new Error("base : " + (await reponse.text().catch(() => "")));
  return await reponse.json().catch(() => null);
}

function champ(objet: Record<string, unknown>, noms: string[]): string {
  for (const nom of noms) {
    const v = objet[nom];
    if (typeof v === "string" && v.trim()) return v.trim();
    if (typeof v === "number") return String(v);
  }
  return "";
}

Deno.serve(async (requete: Request): Promise<Response> => {
  /* On répond 200 à presque tout : une notification qui ne nous concerne
     pas n'est pas une erreur, et un refus ferait réessayer FeexPay pour
     rien. */
  const ok = (details: Record<string, unknown> = {}) =>
    new Response(JSON.stringify({ recu: true, ...details }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });

  if (requete.method !== "POST") return ok({ ignore: "methode" });

  let corps: Record<string, unknown>;
  try {
    corps = await requete.json();
  } catch (_) {
    return ok({ ignore: "corps illisible" });
  }

  /* LA SEULE CHOSE QU'ON RETIENT DU PAYLOAD : la référence. Elle ne
     prouve rien — c'est une clé de recherche, pas une preuve. Le statut
     et le montant qui l'accompagnent sont ignorés : les croire, ce
     serait laisser n'importe qui écrire « SUCCESSFUL ». */
  const reference = champ(corps, ["reference", "order_id", "transaction_id"]);
  if (!reference) return ok({ ignore: "reference absente" });

  if (!BASE || !SERVICE || !JETON) {
    /* Mal configurée : surtout pas 200, sinon FeexPay considère la
       notification délivrée et ne la rejouera jamais. Le jeton en fait
       partie depuis la V2 : sans lui, cette fonction ne peut plus rien
       vérifier, donc plus rien encaisser — en silence. */
    return new Response(JSON.stringify({ erreur: "fonction mal configurée" }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }

  let commande: Record<string, unknown> | null;
  try {
    commande = await rpc("commande_par_reference", { reference }) as Record<string, unknown> | null;
  } catch (_) {
    return new Response(JSON.stringify({ erreur: "base injoignable" }), {
      status: 503, headers: { "Content-Type": "application/json" },
    });
  }

  /* Une référence qu'on ne connaît pas : ce paiement n'est pas le nôtre,
     ou la notification arrive avant qu'on ait fini de la ranger. Dans
     les deux cas, ce n'est pas une erreur. */
  if (!commande) return ok({ ignore: "reference inconnue" });
  if (commande["etat"] === "payee") return ok({ deja: true });

  /* ---------- LA VÉRIFICATION, qui seule fait foi ----------
     On redemande à FeexPay, sur son API, sans croire un mot de ce qu'on
     vient de nous poster. En V2 cette lecture réclame le jeton : la V1
     ne demandait rien, et cette fonction n'avait alors aucun secret à
     détenir.

     Pas d'adresse de vérification : on refuse le 200. FeexPay rejouera
     la notification, et on l'encaissera quand on saura la vérifier. */
  if (!VERIFICATION) {
    console.error("feexpay-webhook : adresse de vérification V2 inconnue", reference);
    return new Response(JSON.stringify({ erreur: "vérification non configurée" }), {
      status: 503, headers: { "Content-Type": "application/json" },
    });
  }

  let reponse: Response;
  try {
    reponse = await fetch(VERIFICATION + encodeURIComponent(reference), {
      headers: { "Authorization": "Bearer " + JETON },
    });
  } catch (_) {
    /* Injoignable n'est pas « échoué ». On laisse FeexPay réessayer, et
       l'application redemandera de son côté. */
    return new Response(JSON.stringify({ erreur: "FeexPay injoignable" }), {
      status: 503, headers: { "Content-Type": "application/json" },
    });
  }
  /* RÉPONDRE 200 ICI BRÛLE LA NOTIFICATION. FeexPay la considère alors
     délivrée et ne la rejouera jamais — or un 401 ou un 403 ne dit rien
     du versement : il dit que NOTRE jeton ne va pas. On perdrait un
     encaissement réel sur une faute de configuration, en silence, et la
     commande resterait « à payer » pour toujours.

     On n'acquitte donc que ce qui est sans retour : un 404, c'est une
     référence que FeexPay ne connaît pas, il n'y a rien à réessayer.
     Tout le reste demande à revenir. */
  if (!reponse.ok) {
    console.error("feexpay-webhook ← statut", reponse.status, reference);
    if (reponse.status === 404) return ok({ ignore: "référence inconnue de FeexPay" });
    return new Response(JSON.stringify({ erreur: "statut illisible", statut: reponse.status }), {
      status: 503, headers: { "Content-Type": "application/json" },
    });
  }

  const statut = await reponse.json().catch(() => ({})) as Record<string, unknown>;
  const etat = champ(statut, ["status", "state"]).toUpperCase();
  if (etat !== "SUCCESSFUL" && etat !== "SUCCESS") {
    return ok({ ignore: "paiement non abouti", statut: etat || "PENDING" });
  }

  /* Le montant vient de CETTE réponse, jamais du payload. Sans lui, on
     ne peut pas vérifier qu'il couvre la commande : on ne valide pas, et
     la boutique tranchera à la main. */
  const brut = champ(statut, ["amount", "montant"]);
  if (!brut) return ok({ ignore: "succès sans montant : à confirmer à la main" });

  const resultat = await rpc("marquer_payee", {
    reference: commande["id"],
    transaction: reference,
    montant: Math.round(Number(brut)),
    /* Pour le journal des versements : QUI a encaissé, figé au moment
       du fait. Changer d'agrégateur demain ne réécrit pas hier. */
    qui: "feexpay",
  });

  return ok({ commande: resultat });
});
