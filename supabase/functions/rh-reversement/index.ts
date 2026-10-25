/* =========================================================
   BIZZOO Personnel — le reversement d'un salaire par FeexPay

   Un employé retire tout ou partie de son solde par Mobile Money.
   Le gestionnaire de la caisse clique « Envoyer » : cette fonction
   demande alors à FeexPay de verser le montant sur le numéro de
   l'employé (« payout » de leur API V2), puis va constater chez
   FeexPay que le versement a abouti.

   CE QUI NE SE DISCUTE PAS :

   - LE DROIT D'ENVOYER se vérifie dans la base, avec le jeton du
     gestionnaire (rh_retrait_preparer) : la fonction n'en décide
     rien. Le retrait passe d'un coup de « demande » à « envoi » :
     deux clics ne font pas deux virements.
   - LE MONTANT ET LE NUMÉRO viennent de la base, jamais de la requête.
   - « PAYÉ » NE S'ÉCRIT QUE SUR LA PAROLE DE FEEXPAY, lue sur leur API
     de statut, montant compris. Leur notification n'est pas signée :
     on ne l'écoute même pas ici ; pg_cron fait revérifier toutes les
     10 minutes ce qui est en cours (action « verifier_tout »).
   - UN DÉLAI DÉPASSÉ N'EST PAS UN ÉCHEC. Si l'on ne sait pas si
     l'argent est parti (coupure, panne chez eux), le retrait devient
     « incertain » : il ne repart pas tout seul — on paierait deux
     fois — et le CEO tranche après avoir regardé leur tableau de bord.
   - UN REFUS (4xx) EST SÛR : rien n'est parti, le montant revient sur
     le solde de l'employé.
   - LE JETON fp_ ne vit que dans les secrets de Supabase. Il ne sort ni
     vers l'application, ni dans le journal.

   Secrets (déjà posés pour le paiement des commandes) :
     FEEXPAY_TOKEN, FEEXPAY_SHOP
   Facultatif, pour fermer un réseau sans redéploiement :
     RH_REVERSEMENT_RESEAUX='mtn,moov'   (vide = tous ouverts)

   Déploiement :
     supabase functions deploy rh-reversement --no-verify-jwt
   « --no-verify-jwt » : pg_cron n'a pas de jeton. L'envoi, lui, exige
   celui du gestionnaire, que la base vérifie.

   ATTENTION : FeexPay peut n'accepter les reversements que depuis des
   adresses IP déclarées (tableau de bord FeexPay, onglet « IP List »).
   Les fonctions de Supabase n'ont pas d'adresse fixe : un refus pour
   cette raison est un 4xx, donc sans dommage — le montant revient sur
   le solde — mais aucun reversement ne passera tant que FeexPay ne
   l'autorise pas.
   ========================================================= */

const JETON = Deno.env.get("FEEXPAY_TOKEN") ?? "";
const BOUTIQUE = Deno.env.get("FEEXPAY_SHOP") ?? "";
const BASE = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

/* Les adresses de leur documentation V2, section « Payout (Retrait) ».
   MTN et Moov passent par la même adresse, le réseau en champ ; Celtiis
   a la sienne. Le statut se lit sur une troisième. */
const FEEX = "https://api-v2.feexpay.me/api/payouts";
const ENVOI: Record<string, { url: string; network: string }> = {
  mtn: { url: FEEX + "/public/transfer/global", network: "MTN" },
  moov: { url: FEEX + "/public/transfer/global", network: "MOOV" },
  celtiis: { url: FEEX + "/public/celtiis_bj", network: "CELTIIS BJ" },
};
const STATUT = FEEX + "/status/public/";
const DELAI_MS = 30000;

const OUVERTS = (Deno.env.get("RH_REVERSEMENT_RESEAUX") ?? "")
  .split(",").map((r) => r.trim().toLowerCase()).filter(Boolean);
const ouvert = (reseau: string) => OUVERTS.length === 0 || OUVERTS.includes(reseau);

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const repondre = (corps: Record<string, unknown>, statut = 200) =>
  new Response(JSON.stringify(corps), { status: statut, headers: { ...CORS, "Content-Type": "application/json" } });

/** Un appel à la base, avec le jeton de l'appelant ou les droits du service. */
async function rpc(nom: string, parametres: Record<string, unknown>, jeton?: string): Promise<unknown> {
  const r = await fetch(BASE + "/rest/v1/rpc/" + nom, {
    method: "POST",
    headers: {
      apikey: jeton ? ANON : SERVICE,
      Authorization: "Bearer " + (jeton ?? SERVICE),
      "Content-Type": "application/json",
    },
    body: JSON.stringify(parametres),
  });
  const texte = await r.text();
  if (!r.ok) {
    let message = texte.slice(0, 300);
    try { message = JSON.parse(texte).message || message; } catch (_) { /* texte brut */ }
    throw new Error(message);
  }
  try { return JSON.parse(texte); } catch (_) { return null; }
}

const noter = (retrait: string, issue: string, reference: string, trace: Record<string, unknown>) =>
  rpc("rh_retrait_resultat", { retrait, issue, reference, trace });

function champ(objet: Record<string, unknown>, noms: string[]): string {
  for (const nom of noms) {
    const v = objet[nom];
    if (typeof v === "string" && v.trim()) return v.trim();
    if (typeof v === "number") return String(v);
  }
  return "";
}

/** Lettres, chiffres, espaces : ce que leurs passerelles acceptent. */
function sansFioriture(texte: string): string {
  return texte.normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-zA-Z0-9 ]/g, "").replace(/\s+/g, " ").trim();
}

/* =========================================================
   Constater chez FeexPay
   ========================================================= */
async function verifier(item: { id: string; reference: string; montant: number }): Promise<string> {
  let r: Response;
  try {
    r = await fetch(STATUT + encodeURIComponent(item.reference), { headers: { Authorization: "Bearer " + JETON } });
  } catch (_) {
    return "injoignable";
  }
  const texte = await r.text().catch(() => "");
  console.log("rh-reversement ← statut", r.status, item.reference, texte.slice(0, 300));
  if (!r.ok) return "illisible";
  let d: Record<string, unknown> = {};
  try { d = JSON.parse(texte); } catch (_) { return "illisible"; }
  const etat = champ(d, ["status", "state"]).toUpperCase();
  const trace = { verification: r.status, status: etat, amount: d["amount"] ?? null, reason: d["reason"] ?? null };
  if (etat === "SUCCESSFUL" || etat === "SUCCESS") {
    /* Le montant de LEUR réponse doit être celui du retrait : un succès
       sans montant, ou d'un autre montant, ne s'écrit pas « payé ». */
    const montant = Math.round(Number(champ(d, ["amount", "montant"])));
    if (!montant || montant !== Number(item.montant)) return "montant à confirmer";
    await noter(item.id, "paye", "", trace);
    return "paye";
  }
  if (etat === "FAILED") {
    await noter(item.id, "echoue", "", trace);
    return "echoue";
  }
  return "en cours";
}

async function enCours(): Promise<{ id: string; reference: string; montant: number }[]> {
  return (await rpc("rh_retraits_a_verifier", {}) as { id: string; reference: string; montant: number }[]) || [];
}

/* =========================================================
   Envoyer
   ========================================================= */
async function envoyer(retrait: string, jeton: string): Promise<Response> {
  if (!JETON || !BOUTIQUE) {
    return repondre({ erreur: "Le reversement FeexPay n'est pas configuré. Servez ce retrait à la caisse." }, 503);
  }
  let prep: Record<string, unknown>;
  try {
    prep = await rpc("rh_retrait_preparer", { retrait }, jeton) as Record<string, unknown>;
  } catch (err) {
    return repondre({ erreur: (err as Error).message }, 403);
  }
  const reseau = String(prep.reseau || "");
  const cible = ENVOI[reseau];
  if (!cible || !ouvert(reseau)) {
    await noter(retrait, "demande", "", { ferme: reseau });
    return repondre({ erreur: "Ce réseau est fermé pour l'instant chez FeexPay : servez ce retrait à la caisse, ou réessayez plus tard." }, 503);
  }
  const corps = {
    shop: BOUTIQUE,
    amount: Number(prep.montant),
    phoneNumber: "229" + String(prep.telephone),
    network: cible.network,
    // 30 caractères au plus, sans caractère spécial.
    motif: sansFioriture("Salaire BIZZOO R" + String(prep.numero).padStart(4, "0")).slice(0, 30),
    callback_info: "rh-retrait-" + retrait,
  };
  console.log("rh-reversement → envoi", cible.url, JSON.stringify(corps));

  const minuterie = new AbortController();
  const arret = setTimeout(() => minuterie.abort(), DELAI_MS);
  let r: Response;
  try {
    r = await fetch(cible.url, {
      method: "POST",
      headers: { Authorization: "Bearer " + JETON, "Content-Type": "application/json" },
      body: JSON.stringify(corps),
      signal: minuterie.signal,
    });
  } catch (err) {
    /* On ne sait pas si FeexPay l'a reçu : surtout pas « échoué ». */
    clearTimeout(arret);
    await noter(retrait, "incertain", "", { envoi: corps, erreur: String((err as Error).message || err) });
    return repondre({ statut: "incertain", message: "FeexPay n'a pas répondu à temps. Le retrait est mis de côté : le CEO vérifiera dans le tableau de bord FeexPay avant de le déclarer payé ou de le rendre." });
  }
  clearTimeout(arret);
  const texte = await r.text().catch(() => "");
  console.log("rh-reversement ← envoi", r.status, texte.slice(0, 500));
  let d: Record<string, unknown> = {};
  try { d = JSON.parse(texte); } catch (_) { /* réponse non JSON */ }
  const trace = { envoi: corps, statut: r.status, reponse: texte.slice(0, 500) };

  if (r.status === 429) {
    await noter(retrait, "demande", "", trace);
    return repondre({ erreur: "FeexPay reçoit trop de demandes : réessayez dans une minute. Rien n'est parti." }, 429);
  }
  if (r.status >= 400 && r.status < 500) {
    await noter(retrait, "echoue", "", trace);
    const phrase = champ(d, ["message", "error", "detail"]) || "sans explication";
    return repondre({ statut: "echoue", message: "FeexPay a refusé le reversement (" + phrase + "). Rien n'est parti : le montant est revenu sur le solde de l'employé." });
  }
  const reference = champ(d, ["reference", "transref"]).replace(/[^A-Za-z0-9_-]/g, "");
  if (!r.ok || !reference) {
    /* Une panne chez eux, ou une réponse sans référence : on ne sait pas. */
    await noter(retrait, "incertain", reference, trace);
    return repondre({ statut: "incertain", message: "La réponse de FeexPay ne permet pas de savoir si l'argent est parti. Le CEO vérifiera dans leur tableau de bord." });
  }
  await noter(retrait, "envoye", reference, trace);
  const issue = await verifier({ id: retrait, reference, montant: Number(prep.montant) }).catch(() => "en cours");
  return repondre({ statut: issue === "paye" ? "paye" : issue === "echoue" ? "echoue" : "envoye", reference });
}

Deno.serve(async (requete: Request): Promise<Response> => {
  if (requete.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (requete.method !== "POST") return repondre({ erreur: "POST seulement" }, 405);
  if (!BASE || !SERVICE) return repondre({ erreur: "fonction mal configurée" }, 500);
  let corps: Record<string, unknown> = {};
  try { corps = await requete.json(); } catch (_) { /* corps vide */ }
  const action = String(corps.action || "");
  try {
    if (action === "envoyer") {
      const jeton = (requete.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
      if (!jeton || jeton === ANON) return repondre({ erreur: "Connectez-vous." }, 401);
      return await envoyer(String(corps.retrait || ""), jeton);
    }
    if (action === "verifier" || action === "verifier_tout") {
      if (!JETON) return repondre({ erreur: "FeexPay n'est pas configuré" }, 503);
      const liste = (await enCours()).filter((x) => action === "verifier_tout" || x.id === corps.retrait);
      const issues: Record<string, string> = {};
      for (const x of liste) issues[x.id] = await verifier(x);
      return repondre({ ok: true, issues });
    }
    return repondre({ erreur: "action inconnue" }, 400);
  } catch (err) {
    console.error("rh-reversement", err);
    return repondre({ erreur: String((err as Error).message || err) }, 500);
  }
});
