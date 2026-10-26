/* =========================================================
   BIZZOO Personnel — le banc du reversement FeexPay

   « rh-reversement » envoie de l'argent : un défaut ici paie deux
   fois, ou paie sans que personne l'ait voulu. Le banc ne touche
   JAMAIS FeexPay : il lui substitue une doublure qui répond ce
   qu'on lui dit, et note ce qu'on lui envoie ; la base aussi est
   une doublure, qui refuse comme la vraie.

   Ce qu'on prouve :
     — rien ne part sans le jeton d'un gestionnaire, que la BASE
       accepte (rh_retrait_preparer) ; deux clics, un seul virement ;
     — le montant et le numéro viennent de la base, pas de la requête ;
     — ce qui part chez FeexPay est ce que leur documentation V2
       demande : l'adresse par réseau, 229 + numéro, motif propre ;
     — « payé » ne s'écrit que sur la parole de l'API de statut, au
       montant exact ;
     — un refus (4xx) rend l'argent ; une panne, un délai dépassé ou
       une réponse sans référence laissent « incertain », JAMAIS
       « échoué » : l'argent est peut-être parti ;
     — le jeton ne sort ni vers l'application, ni dans le journal.

   Usage :  tools/eprouver-reversement.sh
   ========================================================= */

const dire = console.log.bind(console);
const rouge = (s) => "\x1b[31m" + s + "\x1b[0m";
const vert = (s) => "\x1b[32m" + s + "\x1b[0m";
const gris = (s) => "\x1b[90m" + s + "\x1b[0m";

const SECRETS = {
  FEEXPAY_TOKEN: "fp_jeton_qui_ne_doit_jamais_sortir",
  FEEXPAY_SHOP: "boutique-d-essai",
  SUPABASE_URL: "https://base.essai",
  SUPABASE_SERVICE_ROLE_KEY: "cle-de-service",
  SUPABASE_ANON_KEY: "cle-anonyme",
};
const portes = [];
globalThis.Deno = { env: { get: (n) => SECRETS[n] }, serve: (h) => portes.push(h) };

const journal = [];
for (const voie of ["log", "error", "warn"]) {
  console[voie] = (...a) => journal.push(a.map(String).join(" "));
}

/* ---------- Le faux FeexPay, et la fausse base ---------- */
const monde = {};
const GESTIONNAIRE = "jeton-du-gestionnaire";
const EMPLOYE = "jeton-d-un-employe";

function faireReponse({ statut = 200, corps = {} }) {
  const texte = typeof corps === "string" ? corps : JSON.stringify(corps);
  return new Response(texte, { status: statut, headers: { "Content-Type": "application/json" } });
}

/* La fausse base refuse comme la vraie : seul le gestionnaire prépare,
   et seulement un retrait Mobile Money encore en attente. */
function rpcFaux(nom, p, entetes) {
  const jeton = String(entetes.Authorization || "").replace("Bearer ", "");
  const r = monde.retraits.get(p.retrait);
  if (nom === "rh_retrait_preparer") {
    if (jeton !== GESTIONNAIRE) return { statut: 400, corps: { message: "Seul le gestionnaire de la caisse lance un reversement" } };
    if (!r || r.statut !== "demande" || r.moyen !== "feexpay") return { statut: 400, corps: { message: "Seul un retrait Mobile Money en attente se reverse" } };
    r.statut = "envoi";
    return { corps: { id: r.id, numero: r.numero, montant: r.montant, reseau: r.reseau, telephone: r.telephone } };
  }
  if (jeton !== SECRETS.SUPABASE_SERVICE_ROLE_KEY) return { statut: 401, corps: { message: "service seulement" } };
  if (nom === "rh_retrait_resultat") {
    monde.resultats.push(p);
    const permis = (r.statut === "envoi" && ["demande", "envoye", "incertain", "echoue"].includes(p.issue))
      || (["envoye", "incertain"].includes(r.statut) && ["paye", "echoue"].includes(p.issue));
    if (permis) {
      r.statut = p.issue;
      if (p.reference) r.reference = p.reference;
    }
    return { corps: r.statut };
  }
  if (nom === "rh_retraits_a_verifier") {
    return { corps: [...monde.retraits.values()].filter((x) => ["envoye", "incertain"].includes(x.statut) && x.reference)
      .map((x) => ({ id: x.id, reference: x.reference, montant: x.montant })) };
  }
  throw new Error("fonction de base inattendue : " + nom);
}

globalThis.fetch = async (url, options = {}) => {
  const adresse = String(url);
  const corps = options.body ? JSON.parse(options.body) : {};
  if (adresse.startsWith("https://api-v2.feexpay.me/api/payouts/status/public/")) {
    monde.statutAppels.push({ ref: decodeURIComponent(adresse.split("/").pop()), entetes: options.headers || {} });
    const r = monde.reponseStatut();
    if (r.injoignable) throw new Error("réseau");
    return faireReponse(r);
  }
  if (adresse.startsWith("https://api-v2.feexpay.me/api/payouts/public/")) {
    monde.envois.push({ adresse, corps, entetes: options.headers || {} });
    const r = monde.reponseEnvoi();
    if (r.injoignable) throw new Error("délai dépassé");
    return faireReponse(r);
  }
  if (adresse.startsWith(SECRETS.SUPABASE_URL + "/rest/v1/rpc/")) {
    const nom = adresse.split("/rpc/")[1];
    monde.rpc.push({ nom, entetes: options.headers || {} });
    return faireReponse(rpcFaux(nom, corps, options.headers || {}));
  }
  throw new Error("adresse inattendue : " + adresse);
};

function decor(modif = {}) {
  monde.retraits = new Map();
  monde.envois = [];
  monde.statutAppels = [];
  monde.resultats = [];
  monde.rpc = [];
  monde.reponseEnvoi = () => ({ corps: { reference: "a19d2d2d-ref", status: "PENDING", message: "Payout request accepted" } });
  monde.reponseStatut = () => ({ corps: { status: "SUCCESSFUL", amount: 30000, reference: "a19d2d2d-ref" } });
  journal.length = 0;
  monde.retraits.set("r1", { id: "r1", numero: 7, montant: 30000, moyen: "feexpay", reseau: "mtn",
    telephone: "0197000001", statut: "demande", reference: "", ...modif });
  return monde.retraits.get("r1");
}

let echecs = 0;
const titre = (t) => { dire(""); dire("== " + t); };
function verifie(vrai, quoi) {
  if (vrai) dire("  ok    " + quoi);
  else { dire(rouge("  ÉCHEC " + quoi)); echecs++; }
}
function egal(obtenu, attendu, quoi) {
  if (JSON.stringify(obtenu) === JSON.stringify(attendu)) dire("  ok    " + quoi + " " + gris("(" + JSON.stringify(obtenu) + ")"));
  else {
    dire(rouge("  ÉCHEC " + quoi));
    dire("        obtenu  : " + JSON.stringify(obtenu));
    dire("        attendu : " + JSON.stringify(attendu));
    echecs++;
  }
}

async function appeler(porte, corps, jeton) {
  const entetes = { "Content-Type": "application/json" };
  if (jeton) entetes.Authorization = "Bearer " + jeton;
  const r = await porte(new Request("https://fonction.essai/", { method: "POST", headers: entetes, body: JSON.stringify(corps) }));
  const texte = await r.text();
  let donnees = {};
  try { donnees = JSON.parse(texte); } catch (_) { /* clair */ }
  return { statut: r.status, donnees, texte };
}

const { mkdtempSync, copyFileSync } = await import("node:fs");
const { tmpdir } = await import("node:os");
const { join } = await import("node:path");
const { pathToFileURL } = await import("node:url");

await import("../rh-reversement/index.ts");
const [reversement] = portes;
const ENVOYER = { action: "envoyer", retrait: "r1", montant: 999999, telephone: "0166000000" };

dire(gris("Banc du reversement — FeexPay et la base sont des doublures, aucun appel ne sort d'ici."));

titre("Rien ne part sans un gestionnaire que la base accepte");
decor();
let rep = await appeler(reversement, ENVOYER);
egal(rep.statut, 401, "sans session : refusé");
rep = await appeler(reversement, ENVOYER, SECRETS.SUPABASE_ANON_KEY);
egal(rep.statut, 401, "avec la seule clé publique : refusé");
rep = await appeler(reversement, ENVOYER, EMPLOYE);
egal(rep.statut, 403, "un employé quelconque : la base refuse");
egal(monde.envois.length, 0, "et rien n'est parti chez FeexPay");
verifie(monde.rpc.find((a) => a.nom === "rh_retrait_preparer").entetes.Authorization === "Bearer " + EMPLOYE,
  "le droit se vérifie avec le jeton de l'appelant, pas celui du service");

titre("Ce qui part chez FeexPay");
decor();
rep = await appeler(reversement, ENVOYER, GESTIONNAIRE);
const envoi = monde.envois[0] || { corps: {}, entetes: {} };
egal(envoi.adresse, "https://api-v2.feexpay.me/api/payouts/public/transfer/global", "MTN : l'adresse globale de la V2");
egal(envoi.corps.network, "MTN", "le réseau en champ");
egal(envoi.corps.amount, 30000, "le montant vient de la base, pas de la requête");
egal(envoi.corps.phoneNumber, "2290197000001", "le numéro de la base, avec l'indicatif 229");
egal(envoi.corps.shop, "boutique-d-essai", "la boutique des secrets");
verifie(/^[A-Za-z0-9 ]{1,30}$/.test(envoi.corps.motif), "un motif de lettres et chiffres, 30 caractères au plus (" + envoi.corps.motif + ")");
egal(envoi.entetes.Authorization, "Bearer " + SECRETS.FEEXPAY_TOKEN, "le jeton dans l'en-tête");
egal(monde.statutAppels.map((x) => x.ref), ["a19d2d2d-ref"], "puis le statut est lu sur leur API");
egal(rep.donnees.statut, "paye", "SUCCESSFUL au bon montant : payé");
egal(monde.retraits.get("r1").statut, "paye", "et la base le note");

decor();
await appeler(reversement, ENVOYER, GESTIONNAIRE);
rep = await appeler(reversement, ENVOYER, GESTIONNAIRE);
egal(monde.envois.length, 1, "deux clics : un seul virement");
egal(rep.statut, 403, "le second est refusé par la base");

decor({ reseau: "celtiis", telephone: "0140000000" });
await appeler(reversement, ENVOYER, GESTIONNAIRE);
egal(monde.envois[0] && monde.envois[0].adresse, "https://api-v2.feexpay.me/api/payouts/public/celtiis_bj", "Celtiis : son adresse à lui");
egal(monde.envois[0] && monde.envois[0].corps.network, "CELTIIS BJ", "et son nom de réseau");

decor({ reseau: "moov" });
await appeler(reversement, ENVOYER, GESTIONNAIRE);
egal(monde.envois[0] && monde.envois[0].corps.network, "MOOV", "Moov : l'adresse globale, réseau MOOV");

titre("Payé seulement sur la parole de FeexPay, au montant exact");
decor();
monde.reponseStatut = () => ({ corps: { status: "SUCCESSFUL" } });
rep = await appeler(reversement, ENVOYER, GESTIONNAIRE);
egal(monde.retraits.get("r1").statut, "envoye", "un succès sans montant ne s'écrit pas « payé »");
decor();
monde.reponseStatut = () => ({ corps: { status: "SUCCESSFUL", amount: 3000 } });
await appeler(reversement, ENVOYER, GESTIONNAIRE);
egal(monde.retraits.get("r1").statut, "envoye", "ni un succès d'un autre montant");
decor();
monde.reponseStatut = () => ({ corps: { status: "PENDING" } });
rep = await appeler(reversement, ENVOYER, GESTIONNAIRE);
egal([rep.donnees.statut, monde.retraits.get("r1").statut], ["envoye", "envoye"], "en cours chez FeexPay : en cours chez nous");
monde.reponseStatut = () => ({ corps: { status: "SUCCESSFUL", amount: 30000 } });
rep = await appeler(reversement, { action: "verifier_tout" });
egal(monde.retraits.get("r1").statut, "paye", "le passage de pg_cron le conclut, sans jeton d'utilisateur");
decor();
monde.reponseStatut = () => ({ corps: { status: "FAILED", reason: "solde marchand" } });
await appeler(reversement, ENVOYER, GESTIONNAIRE);
egal(monde.retraits.get("r1").statut, "echoue", "FAILED chez FeexPay : échoué (la base rend l'argent)");

titre("Un refus rend l'argent ; un doute, jamais");
decor();
monde.reponseEnvoi = () => ({ statut: 400, corps: { message: "Adresse IP non autorisée" } });
rep = await appeler(reversement, ENVOYER, GESTIONNAIRE);
egal(monde.retraits.get("r1").statut, "echoue", "un 4xx est un refus sûr : échoué, l'argent revient");
verifie(String(rep.donnees.message).includes("Adresse IP non autorisée"), "et leur phrase est rapportée");
decor();
monde.reponseEnvoi = () => ({ statut: 502, corps: "Bad Gateway" });
rep = await appeler(reversement, ENVOYER, GESTIONNAIRE);
egal(monde.retraits.get("r1").statut, "incertain", "une panne chez eux : incertain, pas échoué");
decor();
monde.reponseEnvoi = () => ({ injoignable: true });
rep = await appeler(reversement, ENVOYER, GESTIONNAIRE);
egal(monde.retraits.get("r1").statut, "incertain", "un délai dépassé : incertain");
egal(rep.donnees.statut, "incertain", "et l'écran le dit");
decor();
monde.reponseEnvoi = () => ({ corps: { status: "PENDING" } });
await appeler(reversement, ENVOYER, GESTIONNAIRE);
egal(monde.retraits.get("r1").statut, "incertain", "accepté sans référence : incertain, on ne pourrait pas vérifier");
decor();
monde.reponseEnvoi = () => ({ statut: 429, corps: { message: "Too many" } });
await appeler(reversement, ENVOYER, GESTIONNAIRE);
egal(monde.retraits.get("r1").statut, "demande", "trop de demandes : rien n'est parti, le retrait revient en attente");

titre("Le jeton ne sort pas");
decor();
await appeler(reversement, ENVOYER, GESTIONNAIRE);
monde.reponseEnvoi = () => ({ statut: 400, corps: { message: "non" } });
decor();
rep = await appeler(reversement, ENVOYER, GESTIONNAIRE);
verifie(!rep.texte.includes("fp_"), "ni dans la réponse à l'application");
verifie(!journal.some((l) => l.includes("fp_")), "ni dans le journal");
verifie(journal.some((l) => l.includes("rh-reversement → envoi")), "le journal garde ce qui est parti, pour diagnostiquer");
verifie(!monde.resultats.some((x) => JSON.stringify(x).includes("fp_")), "ni dans ce que la base garde");

titre("Un réseau fermé ne part pas");
const dossier = mkdtempSync(join(tmpdir(), "rh-reversement-"));
const copie = join(dossier, "index.ts");
copyFileSync(new URL("../rh-reversement/index.ts", import.meta.url), copie);
SECRETS.RH_REVERSEMENT_RESEAUX = "moov";
await import(pathToFileURL(copie).href);
const reversementFerme = portes[portes.length - 1];
decor();
rep = await appeler(reversementFerme, ENVOYER, GESTIONNAIRE);
egal(monde.envois.length, 0, "MTN fermé par le réglage : rien ne part");
egal(monde.retraits.get("r1").statut, "demande", "et le retrait revient en attente, à servir autrement");
delete SECRETS.RH_REVERSEMENT_RESEAUX;

dire("");
if (echecs > 0) {
  dire(rouge(echecs + " constat(s) en échec : une porte du reversement a cédé."));
  process.exit(1);
}
dire(vert("Le reversement tient : rien ne part sans la base, rien ne s'écrit payé sans FeexPay ✔"));
