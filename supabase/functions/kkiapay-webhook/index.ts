/* =========================================================
   BIZZOO — la notification de paiement de KkiaPay

   C'est la seule porte par laquelle une commande devient
   « payée ». Le message de succès que reçoit le TÉLÉPHONE du
   client, lui, n'est qu'un indice : c'est du code qui tourne
   chez lui, donc modifiable. Seul KkiaPay détient le secret
   qui signe cet appel-ci.

   Déploiement (à faire une fois, sur votre poste) :

     supabase secrets set KKIAPAY_WEBHOOK_SECRET='votre-secret'
     supabase functions deploy kkiapay-webhook --no-verify-jwt

   « --no-verify-jwt » n'est pas une négligence : KkiaPay
   n'envoie aucun jeton Supabase. Sans cette option, l'appel
   serait rejeté avant même d'entrer ici — et le paiement
   n'arriverait jamais. La sécurité est assurée par le secret,
   vérifié ci-dessous.

   Puis, dans le tableau de bord KkiaPay, déclarer l'adresse :
     https://<projet>.supabase.co/functions/v1/kkiapay-webhook
   DU BON CÔTÉ — bac à sable et production ont chacun leurs
   webhooks, et un webhook déclaré en production n'est jamais
   appelé par un paiement de test.
   ========================================================= */

const SECRET = Deno.env.get("KKIAPAY_WEBHOOK_SECRET") ?? "";
const BASE = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

/**
 * Comparaison à durée constante. Une comparaison ordinaire s'arrête au
 * premier caractère qui diffère : en mesurant les temps de réponse, on
 * reconstitue le secret lettre après lettre. Ici, le temps ne dépend
 * plus de ce qui est comparé.
 */
function memeSecret(recu: string, attendu: string): boolean {
  if (!attendu) return false;
  const a = new TextEncoder().encode(recu);
  const b = new TextEncoder().encode(attendu);
  let difference = a.length ^ b.length;
  const longueur = Math.max(a.length, b.length);
  for (let i = 0; i < longueur; i++) {
    difference |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return difference === 0;
}

/** Le premier des noms possibles qui porte quelque chose. */
function champ(objet: Record<string, unknown>, noms: string[]): string {
  for (const nom of noms) {
    const valeur = objet[nom];
    if (typeof valeur === "string" && valeur.trim()) return valeur.trim();
    if (typeof valeur === "number") return String(valeur);
  }
  return "";
}

/**
 * La référence de la commande. KkiaPay la renvoie dans le champ libre
 * qu'on lui a confié à l'ouverture du paiement — sous forme de texte
 * ou de petit objet selon les versions.
 */
function referenceCommande(corps: Record<string, unknown>): string {
  const brut = corps["data"] ?? corps["reason"] ?? corps["partnerId"] ?? "";
  if (typeof brut === "string") {
    const texte = brut.trim();
    if (texte.startsWith("{")) {
      try {
        const objet = JSON.parse(texte);
        return champ(objet, ["commande", "commande_id", "id"]);
      } catch (_) { /* champ libre qui n'est pas du JSON */ }
    }
    return texte.startsWith("cmd_") ? texte : "";
  }
  if (brut && typeof brut === "object") {
    return champ(brut as Record<string, unknown>, ["commande", "commande_id", "id"]);
  }
  return "";
}

/** Le paiement a-t-il abouti ? */
function aAbouti(corps: Record<string, unknown>): boolean {
  if (corps["isPaymentSucces"] === true || corps["isPaymentSuccess"] === true) return true;
  const etat = champ(corps, ["state", "status", "event"]).toUpperCase();
  return etat.includes("SUCCESS") || etat.includes("COMPLET") || etat === "DONE";
}

Deno.serve(async (requete: Request): Promise<Response> => {
  /* Toute réponse autre que 200 déclenche cinq nouvelles tentatives de
     KkiaPay. On ne répond donc « non » que quand c'est vraiment « non ». */
  const ok = (details: Record<string, unknown> = {}) =>
    new Response(JSON.stringify({ recu: true, ...details }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });

  if (requete.method !== "POST") return ok({ ignore: "methode" });

  const entetes = requete.headers;
  const recu = entetes.get("x-kkiapay-secret")
    ?? entetes.get("X-KKIAPAY-SECRET")
    ?? entetes.get("kkiapay-secret")
    ?? "";
  if (!memeSecret(recu, SECRET)) {
    /* Là, en revanche, on refuse franchement : ce n'est pas KkiaPay. */
    return new Response(JSON.stringify({ erreur: "signature refusée" }), {
      status: 401, headers: { "Content-Type": "application/json" },
    });
  }

  let corps: Record<string, unknown>;
  try {
    corps = await requete.json();
  } catch (_) {
    return ok({ ignore: "corps illisible" });
  }

  /* Un événement qui ne nous concerne pas — un échec, un autre type —
     repart avec un 200 : sinon KkiaPay réessaierait cinq fois pour rien. */
  if (!aAbouti(corps)) return ok({ ignore: "paiement non abouti" });

  const transaction = champ(corps, ["transactionId", "transaction_id", "id"]);
  if (!transaction) return ok({ ignore: "transaction absente" });

  const montant = Math.round(Number(
    champ(corps, ["amount", "montant", "amountPaid"]) || 0));
  const reference = referenceCommande(corps);

  if (!BASE || !SERVICE) {
    /* Mal configurée : surtout ne pas répondre 200, sinon KkiaPay
       considère la notification délivrée et ne la rejouera jamais. */
    return new Response(JSON.stringify({ erreur: "fonction mal configurée" }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }

  let reponse: Response;
  try {
    reponse = await fetch(BASE + "/rest/v1/rpc/marquer_payee", {
      method: "POST",
      headers: {
        "apikey": SERVICE,
        "Authorization": "Bearer " + SERVICE,
        "Content-Type": "application/json",
      },
      /* « qui » ne sert qu'au journal des versements : il fige QUI a
         encaissé, au moment du fait. Changer d'agrégateur demain ne
         réécrira pas les versements d'hier. */
      body: JSON.stringify({ reference, transaction, montant, qui: "kkiapay" }),
    });
  } catch (_) {
    /* Un délai dépassé n'est PAS un échec de paiement : la base a
       peut-être écrit malgré tout. On laisse KkiaPay réessayer — la
       fonction ne fera rien de plus la deuxième fois. */
    return new Response(JSON.stringify({ erreur: "base injoignable" }), {
      status: 503, headers: { "Content-Type": "application/json" },
    });
  }

  if (!reponse.ok) {
    const texte = await reponse.text().catch(() => "");
    return new Response(JSON.stringify({ erreur: "base refusée", details: texte }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }

  const resultat = await reponse.json().catch(() => ({}));
  return ok({ commande: resultat });
});
