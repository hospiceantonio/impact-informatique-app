/* =========================================================
   BIZZOO — le banc des deux fonctions de paiement

   Ces fonctions n'avaient AUCUN test, et c'est précisément là
   qu'ont vécu les défauts de la première mise en service :

     1. le libellé partait avec un tiret (« Commande BZ-000005 »)
        alors que MTN n'accepte que lettres, chiffres et espaces.
        Leur propre SDK le nettoie ; nous, non ;

     2. tout statut non-2xx de FeexPay s'affichait « FeexPay a
        refusé la demande » — y compris un 502 de leur serveur.
        On envoyait le client vérifier un numéro qui n'avait
        rien, et la boutique douter d'identifiants qui sont bons.

   Puis FeexPay a RETIRÉ LA V1 — ce 502 sur toutes leurs adresses
   n'était pas une panne. La V2 renverse des choses qu'aucune
   relecture ne rattrape : le numéro porte désormais l'indicatif
   (2290197444893) là où la V1 le RETIRAIT, l'opérateur passe du
   corps à l'adresse, et le jeton sort du corps. Chacune de ces
   inversions a son constat ici.

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

   Usage :  node --experimental-strip-types eprouver-paiement.mjs
            (les trois fichiers côte à côte ; Node 22.6 ou plus)
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
  FEEXPAY_STATUT: "https://api-v2.feexpay.me/api/transactions/public/status/",
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

  if (adresse.includes("/requesttopay/")) {
    monde.feexAppels.push(corps);
    monde.feexAdresses.push(adresse);
    monde.feexEntetes.push(options.headers || {});
    const r = monde.reponsePayer();
    if (r.injoignable) throw new Error("réseau");
    return faireReponse(r);
  }
  /* Un préfixe VIDE est le préfixe de toute adresse : sans ce garde, la
     doublure détournerait jusqu'aux appels à la base le jour où l'on
     éprouve une vérification non configurée. */
  if (SECRETS.FEEXPAY_STATUT && adresse.startsWith(SECRETS.FEEXPAY_STATUT)) {
    monde.feexStatutAppels.push(decodeURIComponent(adresse.split("/").pop()));
    monde.feexStatutEntetes.push(options.headers || {});
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
  monde.feexAdresses = [];
  monde.feexEntetes = [];
  monde.feexStatutAppels = [];
  monde.feexStatutEntetes = [];
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

/* Un second exemplaire d'un module, sous un autre chemin : Node ne
   réévalue pas un module déjà chargé, et un simple « ?variante » ne suffit
   pas. On copie le fichier tel quel — pas une ligne n'est modifiée pour
   l'essai. */
const { mkdtempSync, copyFileSync } = await import("node:fs");
const { tmpdir } = await import("node:os");
const { join } = await import("node:path");
const { pathToFileURL } = await import("node:url");

const PAYER = { action: "payer", commande: "cmd_essai", tel: "97444893",
                numero: "0197444893", reseau: "MTN" };
const VERIFIER = { action: "verifier", commande: "cmd_essai", tel: "97444893" };

/* ---------- Les portes ---------- */
await import("./feexpay.ts");
await import("./feexpay-webhook.ts");
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

/* V2 : L'OPÉRATEUR EST DANS L'ADRESSE, plus dans le corps. */
egal(monde.feexAdresses[0],
  "https://api-v2.feexpay.me/api/transactions/public/requesttopay/mtn",
  "l'opérateur est le dernier segment de l'adresse");

/* V2 : LE NUMÉRO PORTE L'INDICATIF. La V1 voulait exactement l'inverse —
   on lui retirait le 229. C'est le genre de renversement qu'aucune
   relecture ne rattrape : seul un constat le tient. */
egal(envoye.phoneNumber, "2290197444893",
  "le numéro part avec l'indicatif, suivi des dix chiffres nationaux");

egal(envoye.shop, SECRETS.FEEXPAY_SHOP, "l'identifiant de boutique est celui des secrets");
egal(envoye.callback_info, "cmd_essai",
  "callback_info est une CHAÎNE en V2, et désigne la commande");
verifie(!("currency" in envoye) && !("reseau" in envoye) && !("customId" in envoye),
  "les champs que la V2 a retirés ne partent plus");

/* L'ancien format à huit chiffres, que beaucoup dictent encore. */
decor();
await appeler(paiement, { ...PAYER, numero: "97444893" });
egal(monde.feexAppels[0].phoneNumber, "2290197444893",
  "un numéro à huit chiffres est ramené à la même forme");

decor();
await appeler(paiement, { ...PAYER, numero: "+229 01 97 44 48 93" });
egal(monde.feexAppels[0].phoneNumber, "2290197444893",
  "un numéro déjà international aussi, sans doubler l'indicatif");

decor();
const malFormé = await appeler(paiement, { ...PAYER, numero: "12345" });
egal(malFormé.statut, 400, "un numéro qui n'est pas béninois est refusé ici");
egal(monde.feexAppels.length, 0, "avant tout appel");

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

/* La passerelle Celtiis parle SOAP : une apostrophe n'a rien à faire
   dans du XML assemblé à la main. Un prénom écorné ne coûte rien. */
decor({ nom: "N'Dah Soètonvê" });
await appeler(paiement, PAYER);
verifie(/^[A-Za-z0-9 ]+$/.test(monde.feexAppels[0].first_name),
  "le nom part sans apostrophe ni accent, comme le libellé");
/* Ramené, pas amputé : un prénom écorné passe, un prénom tronqué inquiète
   le client qui le lit sur son téléphone. */
egal(monde.feexAppels[0].first_name, "NDah Soetonve",
  "l'accent est ramené à sa lettre, la lettre n'est pas supprimée");

/* Les trois opérateurs du Bénin, chacun à SON adresse. « celtiis_bj »
   n'est pas « celtiis » : le déduire des deux autres aurait envoyé les
   clients Celtiis sur une adresse qui n'existe pas. */
for (const [demande, segment] of [["MOOV", "moov"], ["CELTIIS", "celtiis_bj"]]) {
  decor();
  await appeler(paiement, { ...PAYER, reseau: demande });
  egal(monde.feexAdresses[0],
    "https://api-v2.feexpay.me/api/transactions/public/requesttopay/" + segment,
    demande + " part à son adresse, telle que la documentation l'écrit");
}

decor();
const inconnu = await appeler(paiement, { ...PAYER, reseau: "ORANGE" });
egal(inconnu.statut, 400, "un opérateur qui n'existe pas au Bénin est refusé");
egal(monde.feexAppels.length, 0, "et rien ne part au hasard");

/* ---------- Ce que Moov et Celtiis font de particulier ---------- */
titre("Moov répond parfois tout de suite, Celtiis jamais");

/* « Pour Moov Bénin, la réponse peut déjà contenir le statut final (par
   exemple FAILED en cas de solde insuffisant) ». Envoyer ce client
   corriger son numéro, c'est le faire chercher ce qui n'a rien. */
decor();
monde.reponsePayer = () => ({ corps: {
  reference: "32D6CC4C-8AA1-4DFF-80A2-84D34C1BD19F", status: "FAILED",
  response_operator: { description: ["Balance is insufficient"] }, statusCode: "10" } });
const soldeMoov = await appeler(paiement, { ...PAYER, reseau: "MOOV" });
egal(soldeMoov.statut, 400, "un FAILED immédiat est un refus, pas une attente");
verifie(soldeMoov.donnees.erreur.includes("solde"),
  "et on parle d'abord du solde, comme le dit leur documentation");
verifie(!monde.rpcAppels.some((a) => a.nom === "noter_reference"),
  "aucune référence n'est notée sur un versement déjà refusé");

/* « Si le client confirme le code, la réponse sera directement
   SUCCESSFUL » — mais on n'encaisse toujours pas sur cette réponse-là. */
decor();
monde.reponsePayer = () => ({ corps: { status: "SUCCESSFUL", reference: "ref_moov_direct" } });
const vite = await appeler(paiement, { ...PAYER, reseau: "MOOV" });
verifie(vite.donnees.ouvert === true, "un SUCCESSFUL immédiat ouvre bien le paiement");
verifie(!vite.donnees.message.includes("Validez"),
  "on n'envoie pas valider un versement déjà validé");
verifie(!monde.rpcAppels.some((a) => a.nom === "marquer_payee"),
  "et SURTOUT on n'encaisse pas sur cette réponse : la vérification tranche");

/* LE REFUS LE PLUS FRÉQUENT, ET LE PLUS OPAQUE : l'opérateur choisi
   n'est pas celui du numéro. FeexPay répond « Celtiis BJ API Error » —
   une phrase qui ne dit rien à personne. On ne l'empêche pas de choisir,
   la portabilité existe ; on lui dit ce qu'on voit. */
decor();
monde.reponsePayer = () => ({ statut: 400, corps: { message: "Celtiis BJ API Error" } });
const desaccord = await appeler(paiement, { ...PAYER, numero: "0197444893", reseau: "CELTIIS" });
verifie(desaccord.donnees.erreur.includes("MTN"),
  "un numéro MTN envoyé chez Celtiis : on le dit au client");
verifie(desaccord.donnees.erreur.includes("CELTIIS"),
  "et on lui rappelle ce qu'il a choisi");
egal(desaccord.donnees.details, "Celtiis BJ API Error",
  "la phrase de FeexPay reste, elle, telle quelle");

/* Mais on ne l'invente pas quand il n'y a pas de désaccord : accuser un
   numéro juste enverrait le client corriger ce qui n'a rien. */
decor();
monde.reponsePayer = () => ({ statut: 400, corps: { message: "Something failed" } });
const accord = await appeler(paiement, { ...PAYER, numero: "0140000000", reseau: "CELTIIS" });
verifie(!accord.donnees.erreur.includes("vérifiez l'opérateur"),
  "un numéro Celtiis chez Celtiis : aucun reproche inventé");

/* Un préfixe qu'on ne connaît pas ne permet aucune conclusion. */
decor();
monde.reponsePayer = () => ({ statut: 400, corps: { message: "Erreur" } });
const muetPrefixe = await appeler(paiement, { ...PAYER, numero: "0100000000", reseau: "MTN" });
verifie(!muetPrefixe.donnees.erreur.includes("vérifiez l'opérateur"),
  "un préfixe inconnu ne fait accuser personne");

/* Celtiis renvoie une enveloppe SOAP et un statut PENDING : on ne garde
   que la référence, et elle a sa forme à elle. */
decor();
monde.reponsePayer = () => ({ corps: {
  reference: "AG_20251202_701033309a4e1387a99b", status: "PENDING",
  message: "Accept the service request successfully.",
  normal_response: "<?xml version=\"1.0\"?><soapenv:Envelope/>" } });
await appeler(paiement, { ...PAYER, reseau: "CELTIIS" });
egal(monde.rpcAppels.filter((a) => a.nom === "noter_reference")[0].parametres.reference,
  "AG_20251202_701033309a4e1387a99b",
  "la référence Celtiis est gardée telle quelle, SOAP ou pas");

/* ---------- Les limites annoncées par la V2 ---------- */
titre("Les bornes de montant, vérifiées avant d'appeler");

for (const [total, quoi] of [[80, "moins de 100 FCFA"], [3000000, "plus de 2 000 000"]]) {
  decor({ total });
  const r = await appeler(paiement, PAYER);
  egal(r.statut, 400, quoi + " : refusé avec une phrase qui s'explique");
  egal(monde.feexAppels.length, 0, "et FeexPay n'est pas dérangé pour rien");
}

decor({ total: 100 });
await appeler(paiement, PAYER);
egal(monde.feexAppels.length, 1, "le minimum exact passe");

/* =========================================================
   Le jeton
   ========================================================= */
titre("Le jeton ne sort pas");

decor();
monde.reponsePayer = () => ({ statut: 400, corps: { message: "quelque chose ne va pas" } });
const refus = await appeler(paiement, PAYER);

verifie(!("token" in monde.feexAppels[0]),
  "la V2 l'a sorti du corps de la requête — un secret n'est pas une donnée");
verifie(String(monde.feexEntetes[0].Authorization || "").includes(SECRETS.FEEXPAY_TOKEN),
  "il ne voyage plus que dans l'en-tête d'autorisation");
verifie(!refus.texte.includes(SECRETS.FEEXPAY_TOKEN),
  "mais JAMAIS dans ce qui redescend au téléphone");
verifie(!journal.join(" ").includes(SECRETS.FEEXPAY_TOKEN),
  "ni dans le journal, que la boutique peut lire");
verifie(journal.join(" ").includes("feexpay/payer"),
  "le journal dit quand même ce qu'on a envoyé, pour diagnostiquer");

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
const etranger = await appeler(paiement, { ...PAYER, tel: "99999999" });
egal(etranger.statut, 404, "un mauvais numéro ne donne rien");
egal(monde.feexAppels.length, 0,
  "et ne fait sonner aucun téléphone — on ne harcèle personne");

decor();
await appeler(paiement, { ...PAYER, commande: "cmd_qui_n_existe_pas" });
egal(monde.feexAppels.length, 0, "une commande inventée non plus");

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

/* V2 : LA LECTURE DU STATUT EXIGE LE JETON. La V1 ne demandait rien —
   l'oublier ne casserait rien de visible : les commandes resteraient
   simplement « à payer », et personne ne saurait pourquoi. */
verifie(String(monde.feexStatutEntetes[0].Authorization || "").includes(SECRETS.FEEXPAY_TOKEN),
  "la vérification porte le jeton, que la V2 exige");

/* FAILED est un verdict, pas une attente : le sablier ne doit pas tourner
   quatre-vingt-dix secondes sur un refus déjà prononcé. */
decor({ reference: "ref_feex_essai" });
monde.reponseStatut = () => ({ corps: {
  status: "FAILED", amount: 12000,
  reason: "LOW_BALANCE_OR_PAYEE_LIMIT_REACHED_OR_NOT_ALLOWED" } });
const rate = await appeler(paiement, VERIFIER);
verifie(rate.donnees.echoue === true, "un FAILED est annoncé au client, pas subi");
egal(rate.donnees.etat, "a_payer", "et la commande reste à payer : il peut réessayer");
verifie(!monde.rpcAppels.some((a) => a.nom === "marquer_payee"),
  "rien n'est encaissé, malgré le montant qui accompagne le refus");
verifie(journal.join(" ").includes("LOW_BALANCE"),
  "la raison de FeexPay est notée pour la boutique");

/* « IN PENDING STATE » : leur documentation le nomme à côté de PENDING. */
decor({ reference: "ref_feex_essai" });
monde.reponseStatut = () => ({ corps: { status: "IN PENDING STATE" } });
const encours = await appeler(paiement, VERIFIER);
verifie(encours.donnees.attente === true, "« IN PENDING STATE » est une attente, pas un échec");
verifie(!encours.donnees.echoue, "et surtout pas un verdict");

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

/* La notification est le chemin qui confirme quand le client a fermé
   l'application. Si elle perdait le jeton, plus rien ne se confirmerait
   par là — et personne ne le verrait, puisqu'elle répond 200. */
verifie(String(monde.feexStatutEntetes[0].Authorization || "").includes(SECRETS.FEEXPAY_TOKEN),
  "et elle a vérifié EN PORTANT LE JETON, que la V2 exige");

decor({ reference: "ref_feex_essai" });
monde.reponseStatut = () => ({ corps: { status: "SUCCESSFUL" } });
await appeler(notification, { reference: "ref_feex_essai", status: "SUCCESSFUL" });
verifie(!monde.rpcAppels.some((a) => a.nom === "marquer_payee"),
  "un succès sans montant n'encaisse rien ici non plus");

/* Un 401 sur la lecture du statut dit que NOTRE jeton ne va pas, pas que
   le versement a échoué. L'acquitter, c'est perdre un encaissement réel
   sur une faute de configuration — en silence, et sans retour possible. */
decor({ reference: "ref_feex_essai" });
monde.reponseStatut = () => ({ statut: 401, corps: { message: "Unauthorized" } });
const jetonFaux = await appeler(notification, { reference: "ref_feex_essai" });
egal(jetonFaux.statut, 503,
  "un 401 à la vérification n'est PAS acquitté : FeexPay rejouera");
verifie(!monde.rpcAppels.some((a) => a.nom === "marquer_payee"),
  "et rien n'est encaissé entre-temps");

/* Un 404, en revanche, est sans retour : FeexPay ne connaît pas cette
   référence, la rejouer ne changerait rien. */
decor({ reference: "ref_feex_essai" });
monde.reponseStatut = () => ({ statut: 404, corps: { message: "Not found" } });
egal((await appeler(notification, { reference: "ref_feex_essai" })).statut, 200,
  "un 404 est acquitté : il n'y a rien à réessayer");

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

/* =========================================================
   Refermer un réseau sans redéployer
   =========================================================
   C'est arrivé : MTN et Moov passaient, Celtiis répondait « Celtiis BJ
   API Error » — chez l'agrégateur, pas chez nous. Laisser le réseau
   ouvert, c'est envoyer chaque client Celtiis dans le mur ; le retirer du
   code, c'est un déploiement pour une panne qui durera peut-être deux
   heures. Un état temporaire appartient à la configuration. */
titre("Un réseau se referme par réglage, pas par déploiement");

SECRETS.FEEXPAY_RESEAUX = "mtn,moov";
portes.length = 0;
{
  const dossier = mkdtempSync(join(tmpdir(), "bizzoo-reseaux-"));
  const vers = join(dossier, "feexpay.ts");
  copyFileSync(new URL("./feexpay.ts", import.meta.url), vers);
  await import(pathToFileURL(vers).href);
}
const paiementPartiel = portes[0];

decor();
const refermé = await appeler(paiementPartiel, { ...PAYER, reseau: "CELTIIS" });
egal(refermé.statut, 503, "le réseau refermé se referme");
egal(monde.feexAppels.length, 0, "et rien ne part chez FeexPay");
verifie(!refermé.donnees.erreur.includes("refus"),
  "le client n'est accusé de rien : ce n'est ni son numéro ni son solde");
verifie(refermé.donnees.erreur.includes("MTN") && refermé.donnees.erreur.includes("MOOV"),
  "on lui dit lesquels marchent");
egal(refermé.donnees.reseaux, ["MTN", "MOOV"], "et l'application peut s'y fier");

decor();
await appeler(paiementPartiel, { ...PAYER, reseau: "MOOV" });
egal(monde.feexAppels.length, 1, "les réseaux restés ouverts passent toujours");

/* =========================================================
   Ce qu'on ne saura pas constater, on ne l'encaisse pas
   =========================================================
   La V1 est fermée et l'adresse de vérification V2 n'est pas encore
   connue. Une fonction qui ouvrirait quand même un paiement prendrait
   l'argent du client sans que personne, jamais, ne puisse aller demander
   à FeexPay si le versement a abouti : la commande resterait « à payer »
   pour toujours. Mieux vaut un paiement fermé qu'un paiement borgne.

   On recharge donc les deux fonctions avec un secret vide — l'adresse
   est lue au chargement, il faut un second exemplaire du module. */
titre("Sans adresse de vérification, on n'ouvre rien");

const copie = mkdtempSync(join(tmpdir(), "bizzoo-sans-verification-"));
SECRETS.FEEXPAY_STATUT = "";
portes.length = 0;
for (const nom of ["feexpay", "feexpay-webhook"]) {
  const vers = join(copie, nom + ".ts");
  copyFileSync(new URL("./" + nom + ".ts", import.meta.url), vers);
  await import(pathToFileURL(vers).href);
}
const [paiementAveugle, notificationAveugle] = portes;

decor();
const ferme = await appeler(paiementAveugle, PAYER);
egal(ferme.statut, 503, "le paiement se referme au lieu de s'ouvrir");
egal(monde.feexAppels.length, 0, "aucune demande ne part chez FeexPay");
verifie(!monde.rpcAppels.some((a) => a.nom === "noter_reference"),
  "et aucune référence n'est notée");
verifie(!ferme.donnees.erreur.includes("refus"),
  "le client n'est pas accusé d'avoir mal fait");

decor({ reference: "ref_feex_essai" });
const attente = await appeler(paiementAveugle, VERIFIER);
egal(attente.donnees.etat, "a_payer", "une commande ouverte avant la migration ATTEND");
verifie(attente.donnees.attente === true,
  "on ne la déclare pas échouée : son versement a peut-être abouti");

decor({ reference: "ref_feex_essai" });
const rejeuAveugle = await appeler(notificationAveugle, {
  reference: "ref_feex_essai", status: "SUCCESSFUL", amount: 12000,
});
egal(rejeuAveugle.statut, 503,
  "la notification n'est pas acquittée : FeexPay la rejouera");
verifie(!monde.rpcAppels.some((a) => a.nom === "marquer_payee"),
  "et rien n'est encaissé sur sa seule parole");

/* ========================================================= */
dire("");
if (echecs > 0) {
  dire(rouge(echecs + " constat(s) en échec : une porte du paiement a cédé."));
  process.exit(1);
}
dire(vert("Les deux fonctions tiennent : rien ne déclare un paiement sans FeexPay ✔"));
