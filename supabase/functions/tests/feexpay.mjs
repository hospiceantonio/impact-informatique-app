/* =========================================================
   BIZZOO — le banc des deux fonctions de paiement

   Ces fonctions n'avaient AUCUN test, et c'est précisément là
   qu'ont vécu les deux défauts de la première mise en service :

     1. le libellé partait avec un tiret (« Commande BZ-000005 »)
        alors que MTN n'accepte que lettres, chiffres et espaces.
        Leur propre SDK le nettoie ; nous, non ;

     2. tout statut non-2xx de FeexPay s'affichait « FeexPay a
        refusé la demande » — y compris un 502 de leur serveur.
        On envoyait le client vérifier un numéro qui n'avait
        rien, et la boutique douter d'identifiants qui sont bons.

   Le banc ne touche JAMAIS l'API de FeexPay : il lui substitue
   une doublure qui répond ce qu'on lui dit de répondre, et note
   ce qu'on lui a envoyé. On éprouve donc ce que NOTRE code
   décide, pas ce que leur serveur fait ce matin-là — un banc qui
   dépend d'un service extérieur rougit les jours de panne et ne
   prouve rien les autres jours.

   Ce qui est vraiment en jeu ici, et qu'aucun autre banc ne voit :

     — l'application ne déclare jamais un paiement. Ni le
       téléphone du client, ni la notification de FeexPay, qui
       n'est PAS SIGNÉE : n'importe qui peut poster
       « SUCCESSFUL, 999999 » sur l'adresse du webhook ;
     — le montant encaissé vient toujours de la réponse que
       FeexPay donne à NOTRE question, jamais d'un payload ;
     — le frein de trente secondes se vérifie AVANT d'appeler
       FeexPay, sinon le téléphone sonne quand même ;
     — le jeton ne sort ni vers le client, ni dans le journal.

   Usage :  tools/eprouver-paiement.sh
   ========================================================= */

const dire = console.log.bind(console);
const rouge = (s) => "\x1b[31m" + s + "\x1b[0m";
const vert = (s) => "\x1b[32m" + s + "\x1b[0m";
const gris = (s) => "\x1b[90m" + s + "\x1b[0m";

/* ---------- La doublure de Deno ----------
   Les deux fonctions lisent leurs secrets et posent leur porte au
   chargement : la doublure doit donc exister AVANT l'import. */
const SECRETS = {
  FEEXPAY_TOKEN: "fp_jeton_qui_ne_doit_jamais_sortir",
  FEEXPAY_SHOP: "boutique-d-essai",
  SUPABASE_URL: "https://base.essai",
  SUPABASE_SERVICE_ROLE_KEY: "cle-de-service",
};
const portes = [];
globalThis.Deno = { env: { get: (n) => SECRETS[n] }, serve: (h) => portes.push(h) };

/* Ce que les fonctions écrivent dans le journal. On le garde pour
   vérifier qu'on y trouve de quoi diagnostiquer une panne — et jamais
   le jeton. */
const journal = [];
for (const voie of ["log", "error", "warn"]) {
  console[voie] = (...a) => journal.push(a.map(String).join(" "));
}

/* ---------- Le faux FeexPay, et la fausse base ---------- */
const monde = {};

function faireReponse({ statut = 200, corps = {} }) {
  const texte = typeof corps === "string" ? corps : JSON.stringify(corps);
  return new Response(texte, {
    status: statut, headers: { "Content-Type": "application/json" },
  });
}

/* La fausse base répond comme les fonctions SQL réelles : mêmes noms,
   mêmes clés, mêmes refus. Une doublure qui répondrait plus gentiment
   que la vraie ne prouverait rien. */
function rpcFaux(nom, p) {
  if (nom === "commande_pour_paiement") {
    const c = monde.commandes.get(p.cible);
    if (!c) return null;
    if (c.tel !== String(p.tel || "").replace(/\D/g, "")) return null;
    return {
      id: c.id, numero: c.numero, etat: c.etat, total: c.total, devise: c.devise,
      nom: c.nom, tel: c.tel, reference: c.reference, tentative_le: c.tentative_le,
    };
  }
  if (nom === "commande_par_reference") {
    for (const c of monde.commandes.values()) {
      if (c.reference && c.reference === p.reference) {
        return { id: c.id, numero: c.numero, etat: c.etat, total: c.total };
      }
    }
    return null;
  }
  if (nom === "noter_reference") {
    if (!monde.noterReference()) return false;
    const c = monde.commandes.get(p.cible);
    if (!c || c.etat !== "a_payer") return false;
    c.reference = p.reference;
    c.tentative_le = new Date().toISOString();
    return true;
  }
  if (nom === "marquer_payee") {
    const c = monde.commandes.get(p.reference);
    if (!c) return { erreur: "inconnue" };
    if (p.montant < c.total) return { insuffisant: true };
    c.etat = "payee";
    return { numero: c.numero };
  }
  throw new Error("fonction de base inattendue : " + nom);
}

globalThis.fetch = async (url, options = {}) => {
  const adresse = String(url);
  const corps = options.body ? JSON.parse(options.body) : {};

  if (adresse.includes("/requesttopay/integration")) {
    monde.feexAppels.push(corps);
    monde.feexEntetes.push(options.headers || {});
    const r = monde.reponsePayer();
    if (r.injoignable) throw new Error("réseau");
    return faireReponse(r);
  }
  if (adresse.includes("/getrequesttopay/integration/")) {
    monde.feexStatutAppels.push(decodeURIComponent(adresse.split("/").pop()));
    const r = monde.reponseStatut();
    if (r.injoignable) throw new Error("réseau");
    return faireReponse(r);
  }
  if (adresse.startsWith(SECRETS.SUPABASE_URL + "/rest/v1/rpc/")) {
    const nom = adresse.split("/rpc/")[1];
    monde.rpcAppels.push({ nom, parametres: corps });
    return faireReponse({ corps: rpcFaux(nom, corps) });
  }
  throw new Error("adresse inattendue : " + adresse);
};

/* ---------- Le décor, remis à neuf avant chaque essai ---------- */
function decor(modifications = {}) {
  monde.commandes = new Map();
  monde.feexAppels = [];
  monde.feexEntetes = [];
  monde.feexStatutAppels = [];
  monde.rpcAppels = [];
  monde.reponsePayer = () => ({ corps: { status: "PENDING", reference: "ref_feex_essai" } });
  monde.reponseStatut = () => ({ corps: { status: "PENDING" } });
  monde.noterReference = () => true;
  journal.length = 0;
  monde.commandes.set("cmd_essai", {
    id: "cmd_essai", numero: "BZ-000005", etat: "a_payer", total: 12000,
    devise: "FCFA", nom: "Awa Gnonlonfoun", tel: "97444893",
    reference: "", tentative_le: null, ...modifications,
  });
  return monde.commandes.get("cmd_essai");
}

/* ---------- Les constats ---------- */
let echecs = 0;
const titre = (t) => { dire(""); dire("== " + t); };

function verifie(vrai, quoi) {
  if (vrai) dire("  ok    " + quoi);
  else { dire(rouge("  ÉCHEC " + quoi)); echecs++; }
}
function egal(obtenu, attendu, quoi) {
  if (JSON.stringify(obtenu) === JSON.stringify(attendu)) {
    dire("  ok    " + quoi + " " + gris("(" + JSON.stringify(obtenu) + ")"));
  } else {
    dire(rouge("  ÉCHEC " + quoi));
    dire("        obtenu  : " + JSON.stringify(obtenu));
    dire("        attendu : " + JSON.stringify(attendu));
    echecs++;
  }
}

async function appeler(porte, corps) {
  const r = await porte(new Request("https://fonction.essai/", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(corps),
  }));
  const texte = await r.text();
  let donnees = {};
  try { donnees = JSON.parse(texte); } catch (_) { /* réponse en clair */ }
  return { statut: r.status, donnees, texte };
}

const PAYER = { action: "payer", commande: "cmd_essai", tel: "97444893",
                numero: "0197444893", reseau: "MTN" };
const VERIFIER = { action: "verifier", commande: "cmd_essai", tel: "97444893" };

/* ---------- Les portes ---------- */
await import("../feexpay/index.ts");
await import("../feexpay-webhook/index.ts");
const [paiement, notification] = portes;

dire(gris("Banc des fonctions de paiement — FeexPay est une doublure,"));
dire(gris("aucun appel ne sort d'ici."));

/* =========================================================
   Ce qui part chez FeexPay
   ========================================================= */
titre("Ce qui part chez FeexPay");

decor();
await appeler(paiement, PAYER);
const envoye = monde.feexAppels[0] || {};

/* LE DÉFAUT QUI A BLOQUÉ LA PREMIÈRE MISE EN SERVICE. Leur SDK nettoie
   le libellé pour MTN ; nos commandes s'appellent « BZ-000005 ». */
verifie(/^[A-Za-z0-9 ]+$/.test(String(envoye.description || "")),
  "le libellé ne porte que lettres, chiffres et espaces");
verifie(String(envoye.description || "").includes("BZ000005"),
  "et il désigne bien la commande");

egal(envoye.reseau, "MTN", "l'opérateur part sous le nom qu'attend FeexPay");
egal(envoye.shop, SECRETS.FEEXPAY_SHOP, "l'identifiant de boutique est celui des secrets");
egal(envoye.currency, "XOF", "la monnaie est celle de la zone");
egal(envoye.callback_info, { commande: "cmd_essai" },
  "la notification saura de quelle commande elle parle");

/* LE MONTANT VIENT DE LA BASE. C'est toute la raison de passer par un
   serveur : s'il venait de la requête, on paierait 100 francs une
   commande de 100 000. */
decor();
await appeler(paiement, { ...PAYER, montant: 1, amount: 1, total: 1 });
egal(monde.feexAppels[0].amount, 12000,
  "le montant vient de la base, pas de la requête");

decor({ nom: "" });
await appeler(paiement, PAYER);
verifie(String(monde.feexAppels[0].first_name || "").trim() !== "",
  "le nom ne part jamais vide — leur SDK l'envoie toujours");

for (const [demande, attendu] of [["MOOV", "MOOV"], ["CELTIIS", "CELTIIS BJ"]]) {
  decor();
  await appeler(paiement, { ...PAYER, reseau: demande });
  egal(monde.feexAppels[0].reseau, attendu, demande + " part sous son nom FeexPay");
}

/* =========================================================
   Le jeton
   ========================================================= */
titre("Le jeton ne sort pas");

decor();
monde.reponsePayer = () => ({ statut: 400, corps: { message: "quelque chose ne va pas" } });
const refus = await appeler(paiement, PAYER);

egal(monde.feexAppels[0].token, SECRETS.FEEXPAY_TOKEN,
  "il part bien chez FeexPay, qui l'exige");
verifie(String(monde.feexEntetes[0].Authorization || "").includes(SECRETS.FEEXPAY_TOKEN),
  "et dans l'en-tête d'autorisation");
verifie(!refus.texte.includes(SECRETS.FEEXPAY_TOKEN),
  "mais JAMAIS dans ce qui redescend au téléphone");
verifie(!journal.join(" ").includes(SECRETS.FEEXPAY_TOKEN),
  "ni dans le journal, que la boutique peut lire");
verifie(journal.join(" ").includes("***"),
  "le journal dit ce qu'on a envoyé, jeton retiré");

/* =========================================================
   Une panne n'est pas un refus
   ========================================================= */
titre("Une panne chez eux n'est pas un refus");

decor();
monde.reponsePayer = () => ({ statut: 502, corps: "<html>Bad Gateway</html>" });
const panne = await appeler(paiement, PAYER);
egal(panne.statut, 503, "un 502 de FeexPay ne se présente pas comme un refus");
verifie(!panne.donnees.erreur.includes("refusé"),
  "et le client ne s'entend pas dire qu'on l'a refusé");
verifie(panne.donnees.erreur.includes("Rien n'a été débité"),
  "on lui dit ce qui compte : rien n'a été débité");
verifie(!monde.rpcAppels.some((a) => a.nom === "noter_reference"),
  "aucune référence n'est notée — le frein n'est pas entamé");

decor();
monde.reponsePayer = () => ({ statut: 400, corps: { message: "phone number is invalid" } });
const rejet = await appeler(paiement, PAYER);
egal(rejet.statut, 502, "un 400, lui, est bien un refus");
verifie(rejet.donnees.erreur.includes("refusé"), "et se présente comme tel");
egal(rejet.donnees.details, "phone number is invalid",
  "la phrase de FeexPay remonte jusqu'au client");

decor();
monde.reponsePayer = () => ({ statut: 400, corps: "shop not found" });
const brut = await appeler(paiement, PAYER);
verifie(String(brut.donnees.details || "").includes("shop not found"),
  "même quand FeexPay répond en clair au lieu de JSON");

decor();
monde.reponsePayer = () => ({ statut: 429, corps: { message: "too many requests" } });
egal((await appeler(paiement, PAYER)).statut, 429,
  "trop de demandes d'un coup se dit autrement qu'un refus");

decor();
monde.reponsePayer = () => ({ injoignable: true });
const muet = await appeler(paiement, PAYER);
egal(muet.statut, 503, "FeexPay injoignable n'est pas un refus non plus");

decor();
monde.reponsePayer = () => ({ corps: { status: "FAILED", message: "wrong number" } });
const echoue = await appeler(paiement, PAYER);
egal(echoue.statut, 400, "un 200 qui dit FAILED est un refus déguisé");
verifie(echoue.donnees.erreur.includes("numéro"),
  "et le client entend la seule chose qu'il peut corriger");

decor();
monde.reponsePayer = () => ({ corps: { status: "PENDING" } });
const sansRef = await appeler(paiement, PAYER);
egal(sansRef.statut, 502, "une ouverture sans référence ne vaut rien");
verifie(!monde.rpcAppels.some((a) => a.nom === "noter_reference"),
  "et rien n'est noté en base");

decor();
monde.noterReference = () => false;
const nonNotee = await appeler(paiement, PAYER);
verifie(nonNotee.donnees.erreur.includes("Ne payez pas"),
  "référence non rangée : on dit au client de NE PAS payer");

/* =========================================================
   Le frein des trente secondes
   ========================================================= */
titre("Le frein, vérifié AVANT de faire sonner un téléphone");

decor({ tentative_le: new Date().toISOString() });
const trop = await appeler(paiement, PAYER);
egal(trop.statut, 429, "une relance immédiate est refusée");
egal(monde.feexAppels.length, 0,
  "et FeexPay n'est PAS appelé — sinon le téléphone sonnerait quand même");

decor({ tentative_le: new Date(Date.now() - 60000).toISOString() });
await appeler(paiement, PAYER);
egal(monde.feexAppels.length, 1, "passé le délai, la demande repart");

/* =========================================================
   Le numéro de la commande fait office de mot de passe
   ========================================================= */
titre("Le numéro de la commande fait office de mot de passe");

decor();
const inconnu = await appeler(paiement, { ...PAYER, tel: "99999999" });
egal(inconnu.statut, 404, "un mauvais numéro ne donne rien");
egal(monde.feexAppels.length, 0,
  "et ne fait sonner aucun téléphone — on ne harcèle personne");

decor();
await appeler(paiement, { ...PAYER, commande: "cmd_qui_n_existe_pas" });
egal(monde.feexAppels.length, 0, "une commande inventée non plus");

decor();
const reseauFaux = await appeler(paiement, { ...PAYER, reseau: "ORANGE" });
egal(reseauFaux.statut, 400, "un opérateur qu'on ne connaît pas est refusé ici");
egal(monde.feexAppels.length, 0, "avant tout appel");

decor({ etat: "payee" });
const deja = await appeler(paiement, PAYER);
verifie(deja.donnees.deja === true, "une commande déjà payée ne se repaie pas");
egal(monde.feexAppels.length, 0, "et n'ouvre aucune demande");

/* =========================================================
   Vérifier : c'est FeexPay qui répond, pas le téléphone
   ========================================================= */
titre("Vérifier : c'est la réponse de FeexPay qui décide");

decor({ reference: "ref_feex_essai" });
monde.reponseStatut = () => ({ corps: { status: "SUCCESSFUL", amount: 12000 } });
const paye = await appeler(paiement, VERIFIER);
egal(paye.donnees.etat, "payee", "le compte y étant, la commande est encaissée");
egal(monde.rpcAppels.filter((a) => a.nom === "marquer_payee")[0].parametres.montant,
  12000, "avec le montant que FeexPay a constaté");

/* LA RÈGLE QUI TIENT TOUT : un succès sans montant ne s'encaisse pas.
   Valider sans montant, c'est croire sur parole qu'un versement
   quelconque règle cette commande-ci. */
decor({ reference: "ref_feex_essai" });
monde.reponseStatut = () => ({ corps: { status: "SUCCESSFUL" } });
const sansMontant = await appeler(paiement, VERIFIER);
egal(sansMontant.donnees.etat, "a_payer", "un succès SANS montant n'encaisse rien");
verifie(!monde.rpcAppels.some((a) => a.nom === "marquer_payee"),
  "la base n'est même pas sollicitée");

decor({ reference: "ref_feex_essai" });
monde.reponseStatut = () => ({ corps: { status: "SUCCESSFUL", amount: 5000 } });
await appeler(paiement, VERIFIER);
egal(monde.rpcAppels.filter((a) => a.nom === "marquer_payee")[0].parametres.montant,
  5000, "un versement partiel part tel quel : c'est la base qui tranche");

decor({ reference: "ref_feex_essai" });
monde.reponseStatut = () => ({ statut: 502, corps: "Bad Gateway" });
const veriPanne = await appeler(paiement, VERIFIER);
egal(veriPanne.donnees.etat, "a_payer", "une panne pendant la vérification ne conclut rien");
verifie(veriPanne.donnees.attente === true, "on attend, on ne déclare pas d'échec");

decor({ reference: "ref_feex_essai" });
monde.reponseStatut = () => ({ injoignable: true });
verifie((await appeler(paiement, VERIFIER)).donnees.attente === true,
  "FeexPay injoignable : on attend aussi");

decor();
const rienAVerifier = await appeler(paiement, VERIFIER);
egal(monde.feexStatutAppels.length, 0,
  "sans paiement ouvert, on ne va rien demander à FeexPay");

/* =========================================================
   La notification de FeexPay : une clé, pas une preuve
   ========================================================= */
titre("La notification n'est pas signée — on ne la croit pas");

/* Le scénario qui compte : quelqu'un qui connaît l'adresse du webhook
   poste un succès qu'il a écrit lui-même. */
decor({ reference: "ref_feex_essai" });
monde.reponseStatut = () => ({ corps: { status: "PENDING" } });
const faux = await appeler(notification, {
  reference: "ref_feex_essai", status: "SUCCESSFUL", amount: 999999,
});
egal(faux.statut, 200, "on répond 200 — inutile de faire rejouer FeexPay");
verifie(!monde.rpcAppels.some((a) => a.nom === "marquer_payee"),
  "mais RIEN n'est encaissé : le payload ne prouve rien");
egal(monde.feexStatutAppels, ["ref_feex_essai"],
  "on est allé demander à FeexPay, qui a dit PENDING");

decor({ reference: "ref_feex_essai" });
monde.reponseStatut = () => ({ corps: { status: "SUCCESSFUL", amount: 12000 } });
await appeler(notification, {
  reference: "ref_feex_essai", status: "SUCCESSFUL", amount: 999999,
});
egal(monde.rpcAppels.filter((a) => a.nom === "marquer_payee")[0].parametres.montant,
  12000, "le montant encaissé est celui de FeexPay, pas celui du payload");

decor({ reference: "ref_feex_essai" });
monde.reponseStatut = () => ({ corps: { status: "SUCCESSFUL" } });
await appeler(notification, { reference: "ref_feex_essai", status: "SUCCESSFUL" });
verifie(!monde.rpcAppels.some((a) => a.nom === "marquer_payee"),
  "un succès sans montant n'encaisse rien ici non plus");

decor();
const orpheline = await appeler(notification, { reference: "ref_inventee" });
egal(orpheline.statut, 200, "une référence qu'on ne connaît pas n'est pas une erreur");
egal(monde.feexStatutAppels.length, 0, "et n'envoie rien chez FeexPay");

decor();
verifie((await appeler(notification, { status: "SUCCESSFUL" })).statut === 200,
  "une notification sans référence est ignorée sans bruit");

decor({ reference: "ref_feex_essai" });
monde.reponseStatut = () => ({ injoignable: true });
const rejeu = await appeler(notification, { reference: "ref_feex_essai" });
egal(rejeu.statut, 503,
  "FeexPay injoignable : surtout pas 200, sinon la notification est perdue");

decor({ reference: "ref_feex_essai", etat: "payee" });
const encore = await appeler(notification, { reference: "ref_feex_essai" });
verifie(encore.donnees.deja === true, "une commande déjà payée ne s'encaisse pas deux fois");
egal(monde.feexStatutAppels.length, 0, "et n'interroge même pas FeexPay");

/* ========================================================= */
dire("");
if (echecs > 0) {
  dire(rouge(echecs + " constat(s) en échec : une porte du paiement a cédé."));
  process.exit(1);
}
dire(vert("Les deux fonctions tiennent : rien ne déclare un paiement sans FeexPay ✔"));
