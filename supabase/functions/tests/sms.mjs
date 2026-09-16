/* =========================================================
   BIZZOO — le banc du transport SMS

   Deux portes à forcer ici, et elles ne se ressemblent pas.

   LA PREMIÈRE EST UN MENSONGE POLI. La passerelle répond
   volontiers « HTTP 200 » en portant l'échec dans le corps :

       { "status": false, "code": "INVALID_PHONE" }

   Du code appelant, cela ressemble trait pour trait à un
   succès. Le client attend un SMS qui n'arrivera jamais, et
   rien nulle part ne le signale. Pire : « INSUFFICIENT_BALANCE »
   veut dire que PLUS PERSONNE ne peut s'inscrire — la
   plateforme s'arrête sans qu'aucune erreur ne se déclenche.

   LA SECONDE EST UNE PORTE OUVERTE. Le hook de Supabase Auth
   se déploie sans vérification de jeton : la signature est le
   seul contrôle. Sans elle, n'importe qui connaissant l'adresse
   fait envoyer des SMS aux frais de l'enseigne jusqu'à
   épuisement du crédit — et l'on retombe sur le cas précédent.

   Le banc ne touche JAMAIS la passerelle : il lui substitue une
   doublure qui répond ce qu'on lui dit et note ce qu'on lui a
   envoyé. On éprouve donc ce que NOTRE code décide, pas ce que
   CREATISINTER fait ce matin-là.

   Usage :  tools/eprouver-sms.sh
   ========================================================= */

const dire = console.log.bind(console);
const rouge = (s) => "\x1b[31m" + s + "\x1b[0m";
const vert = (s) => "\x1b[32m" + s + "\x1b[0m";
const gris = (s) => "\x1b[90m" + s + "\x1b[0m";

/* ---------- La doublure de Deno ----------
   Les fonctions lisent leurs secrets et posent leur porte au
   chargement : la doublure doit exister AVANT l'import. */
const SECRET_HOOK = "v1,whsec_" + Buffer.from("secret-du-hook-bizzoo").toString("base64");
const SECRETS = {
  SMS_CLE: "cle_sms_qui_ne_doit_jamais_sortir",
  SMS_EXPEDITEUR: "BIZZOO",
  SMS_URL: "https://sms.creatisinter.essai/api/v1/sms/send",
  SMS_HOOK_SECRET: SECRET_HOOK,
  SUPABASE_URL: "https://base.essai",
  SUPABASE_ANON_KEY: "cle-publiable",
};
const portes = [];
globalThis.Deno = { env: { get: (n) => SECRETS[n] }, serve: (h) => portes.push(h) };

const journal = [];
for (const voie of ["log", "error", "warn"]) {
  console[voie] = (...a) => journal.push(a.map(String).join(" "));
}

/* ---------- La fausse passerelle, et la fausse base ---------- */
const monde = {};

function faireReponse({ statut = 200, corps = {} }) {
  const texte = typeof corps === "string" ? corps : JSON.stringify(corps);
  return new Response(texte, {
    status: statut, headers: { "Content-Type": "application/json" },
  });
}

globalThis.fetch = async (url, options = {}) => {
  const adresse = String(url);

  if (adresse === SECRETS.SMS_URL) {
    monde.envois.push({
      corps: options.body ? JSON.parse(options.body) : null,
      entetes: options.headers || {},
    });
    const r = monde.reponsePasserelle();
    if (r.injoignable) throw new Error("réseau");
    return faireReponse(r);
  }
  if (adresse.endsWith("/rpc/est_super")) {
    monde.appelsSuper.push(options.headers?.Authorization || "");
    return faireReponse({ corps: monde.estSuper() });
  }
  throw new Error("adresse inattendue : " + adresse);
};

function decor(reglages = {}) {
  monde.envois = [];
  monde.appelsSuper = [];
  monde.reponsePasserelle = reglages.reponsePasserelle ??
    (() => ({ corps: { status: true, code: "SUBMITTED" } }));
  monde.estSuper = reglages.estSuper ?? (() => true);
  journal.length = 0;
}
decor();

/* ---------- Les constats ---------- */
let echecs = 0;
function verifie(vrai, quoi) {
  if (vrai) dire("  " + gris("ok") + "    " + quoi);
  else { echecs++; dire("  " + rouge("ÉCHEC") + " " + quoi); }
}
function egal(obtenu, attendu, quoi) {
  verifie(Object.is(obtenu, attendu),
    quoi + (Object.is(obtenu, attendu) ? " (" + attendu + ")"
      : " — obtenu " + JSON.stringify(obtenu) + ", attendu " + JSON.stringify(attendu)));
}
function titre(quoi) { dire(""); dire("== " + quoi); }

/* ---------- Le chargement ---------- */
const sms = await import("../_partage/sms.ts");
await import("../hook-sms-auth/index.ts");
const hook = portes.pop();
await import("../tester-sms/index.ts");
const essai = portes.pop();

/** Signer un corps comme Supabase Auth le fait. */
async function signer(corps, { id = "msg_1", quand = Math.floor(Date.now() / 1000) } = {}) {
  const partie = SECRET_HOOK.slice(SECRET_HOOK.indexOf("whsec_") + 6);
  const cle = await crypto.subtle.importKey(
    "raw", Buffer.from(partie, "base64"),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = Buffer.from(await crypto.subtle.sign(
    "HMAC", cle, new TextEncoder().encode(id + "." + quand + "." + corps))).toString("base64");
  return {
    "webhook-id": id,
    "webhook-timestamp": String(quand),
    "webhook-signature": "v1," + signature,
  };
}

async function appelerHook(corps, entetes) {
  const reponse = await hook(new Request("https://fonction.essai/hook-sms-auth", {
    method: "POST", headers: entetes || {}, body: corps,
  }));
  return { statut: reponse.status, donnees: await reponse.json().catch(() => null) };
}

const charge = (numero, code) =>
  JSON.stringify({ user: { id: "u1", phone: numero }, sms: { otp: code } });

/* =========================================================
   1. Un HTTP 200 ne veut pas dire que le SMS est parti
   ========================================================= */
titre("Un 200 poli n'est pas un succès");

decor({ reponsePasserelle: () => ({ statut: 200, corps: { status: false, code: "INVALID_PHONE" } }) });
let r = await sms.envoyerSms("0197121596", "Bonjour");
verifie(r.ok === false, "« status: false » sur un HTTP 200 est un ÉCHEC");
egal(r.code, "INVALID_PHONE", "et le code de la passerelle est repris tel quel");
egal(r.statutHttp, 200, "le 200 est noté, mais il ne décide de rien");

decor({ reponsePasserelle: () => ({ statut: 200, corps: { status: true, code: "QUEUED_MAYBE" } }) });
r = await sms.envoyerSms("0197121596", "Bonjour");
verifie(r.ok === false, "« status: true » avec un code inconnu est un ÉCHEC aussi");

decor({ reponsePasserelle: () => ({ statut: 200, corps: { code: "SUBMITTED" } }) });
r = await sms.envoyerSms("0197121596", "Bonjour");
verifie(r.ok === false, "un bon code SANS « status: true » ne suffit pas");

for (const bon of ["SUBMITTED", "SENT", "DELIVERED", "PROGRAMMED"]) {
  decor({ reponsePasserelle: () => ({ corps: { status: true, code: bon } }) });
  r = await sms.envoyerSms("0197121596", "Bonjour");
  verifie(r.ok === true, "« " + bon + " » avec « status: true » est un succès");
}

/* Le crédit épuisé arrête toute la plateforme : il doit se lire, pas se
   deviner dans un code brut. */
decor({ reponsePasserelle: () => ({ corps: { status: false, code: "INSUFFICIENT_BALANCE" } }) });
r = await sms.envoyerSms("0197121596", "Bonjour");
verifie(/[Cc]rédit SMS épuisé/.test(r.message),
  "« crédit épuisé » se lit en clair : plus personne ne peut s'inscrire");
decor({ reponsePasserelle: () => ({ corps: { status: false, code: "INVALID_SENDERID" } }) });
r = await sms.envoyerSms("0197121596", "Bonjour");
verifie(/valider/.test(r.message),
  "un senderID non validé dit quoi faire, au lieu d'accuser le code");

decor({ reponsePasserelle: () => ({ injoignable: true }) });
r = await sms.envoyerSms("0197121596", "Bonjour");
egal(r.code, "INJOIGNABLE", "une passerelle injoignable se distingue d'un refus");

/* =========================================================
   2. Le numéro, l'expéditeur
   ========================================================= */
titre("Le numéro part tel que la passerelle l'attend");

egal(sms.normaliserNumero("01 97 12 15 96"), "2290197121596", "un numéro local reçoit son indicatif");
egal(sms.normaliserNumero("+229 01 97 12 15 96"), "2290197121596", "le « + » disparaît");
egal(sms.normaliserNumero("0022901971215 96"), "2290197121596", "le « 00 » de tête aussi");
egal(sms.normaliserNumero("2290197121596"), "2290197121596", "un numéro déjà complet ne double pas son indicatif");
egal(sms.normaliserNumero(""), "", "rien ne donne rien");

decor();
await sms.envoyerSms("01 97 12 15 96", "Bonjour");
egal(monde.envois[0].corps.to, "2290197121596", "c'est le numéro normalisé qui part");
egal(monde.envois[0].corps.from, "BIZZOO", "avec le nom d'expéditeur");
egal(monde.envois[0].corps.message, "Bonjour", "et le message");

decor();
r = await sms.envoyerSms("12", "Bonjour");
egal(r.code, "NUMERO_INVALIDE", "un numéro trop court est refusé AVANT l'appel");
egal(monde.envois.length, 0, "et rien n'est envoyé — un SMS coûte de l'argent");

titre("Le nom d'expéditeur n'est jamais corrigé en douce");

egal(sms.validerExpediteur("CREATIS-SMS"), "CREATIS-SMS",
  "un tiret traverse intact : la passerelle l'accepte, et son exemple en porte un");
egal(sms.validerExpediteur("  BIZZOO  "), "BIZZOO", "les espaces de bord sont retirés");
let refus = "";
try { sms.validerExpediteur("NOM-BEAUCOUP-TROP-LONG"); } catch (e) { refus = e.message; }
verifie(/onze/.test(refus), "trop long : REFUSÉ avec un message, pas amputé en silence");
refus = "";
try { sms.validerExpediteur(""); } catch (e) { refus = e.message; }
verifie(refus !== "", "vide : refusé aussi");

/* =========================================================
   3. Sans clé, on n'appelle personne
   ========================================================= */
titre("Sans clé, rien ne part");

decor();
const vraieCle = SECRETS.SMS_CLE;
SECRETS.SMS_CLE = "";
r = await sms.envoyerSms("0197121596", "Bonjour");
SECRETS.SMS_CLE = vraieCle;
egal(r.code, "SANS_CLE", "une clé absente se dit, elle ne se découvre pas sur un refus");
egal(monde.envois.length, 0, "et la passerelle n'est pas appelée pour rien");

/* =========================================================
   4. La signature est le SEUL contrôle du hook
   ========================================================= */
titre("Le hook refuse tout ce qui n'est pas signé");

decor();
let h = await appelerHook(charge("2290197121596", "123456"), {});
egal(h.statut, 401, "sans en-tête de signature — refusé");
egal(monde.envois.length, 0, "et aucun SMS n'est parti");

decor();
h = await appelerHook(charge("2290197121596", "123456"), {
  "webhook-id": "msg_1",
  "webhook-timestamp": String(Math.floor(Date.now() / 1000)),
  "webhook-signature": "v1,c2lnbmF0dXJlLWJpZG9u",
});
egal(h.statut, 401, "avec une signature inventée — refusé");
egal(monde.envois.length, 0, "et toujours aucun SMS");

decor();
const corpsVrai = charge("2290197121596", "123456");
const entetesVrais = await signer(corpsVrai);
h = await appelerHook(charge("2290199999999", "999999"), entetesVrais);
egal(h.statut, 401, "une signature valable pour UN AUTRE corps — refusée");

decor();
const vieux = await signer(corpsVrai, { quand: Math.floor(Date.now() / 1000) - 3600 });
h = await appelerHook(corpsVrai, vieux);
egal(h.statut, 401, "une requête d'il y a une heure — refusée : on ne rejoue pas");

decor();
const sansSecret = SECRETS.SMS_HOOK_SECRET;
SECRETS.SMS_HOOK_SECRET = "";
/* Le secret est lu au chargement : on éprouve donc la fonction de
   vérification elle-même, qui est ce que le hook appelle. */
const verdictSansSecret = await sms.signatureValable("", new Headers(entetesVrais), corpsVrai);
SECRETS.SMS_HOOK_SECRET = sansSecret;
verifie(verdictSansSecret.ok === false,
  "secret non configuré : on REFUSE, on n'ouvre pas la porte par défaut");

decor();
h = await appelerHook(corpsVrai, entetesVrais);
egal(h.statut, 200, "correctement signée — acceptée");
egal(monde.envois.length, 1, "et le SMS part");
egal(monde.envois[0].corps.to, "2290197121596", "au bon numéro");
verifie(monde.envois[0].corps.message.includes("123456"), "avec le code dedans");

/* Le corps est signé octet pour octet : le relire en JSON puis le
   re-sérialiser casserait la signature. On le prouve avec un espacement
   inhabituel, que JSON.stringify ne reproduirait pas. */
decor();
const espace = '{ "user" : { "phone" : "2290197121596" } , "sms" : { "otp" : "654321" } }';
h = await appelerHook(espace, await signer(espace));
egal(h.statut, 200, "un corps à l'espacement inhabituel passe : on signe les octets reçus");
verifie(monde.envois[0]?.corps.message.includes("654321"), "et le bon code est livré");

titre("Ce que le hook dit, et ce qu'il tait");

decor({ reponsePasserelle: () => ({ corps: { status: false, code: "INSUFFICIENT_BALANCE" } }) });
h = await appelerHook(corpsVrai, await signer(corpsVrai));
verifie(h.statut >= 400,
  "passerelle en échec : le hook le DIT à GoTrue, qui le dira au client");
verifie(/crédit/i.test(JSON.stringify(h.donnees)),
  "et la raison remonte, au lieu d'un échec muet");

decor();
await appelerHook(corpsVrai, await signer(corpsVrai));
verifie(!journal.some((l) => l.includes("123456")),
  "le code n'apparaît JAMAIS dans le journal");
verifie(!journal.some((l) => l.includes(SECRETS.SMS_CLE)),
  "ni la clé de la passerelle");
verifie(!journal.some((l) => l.includes("2290197121596")),
  "ni le numéro entier — un journal n'est pas un annuaire");
verifie(journal.some((l) => l.includes("1596")),
  "mais les derniers chiffres suffisent à suivre un envoi");

decor();
h = await appelerHook("pas du json", await signer("pas du json"));
egal(h.statut, 400, "un corps illisible est refusé proprement");
decor();
h = await appelerHook(JSON.stringify({ user: {} }), await signer(JSON.stringify({ user: {} })));
egal(h.statut, 400, "un corps sans numéro ni code aussi");
egal(monde.envois.length, 0, "et rien n'est envoyé");

/* =========================================================
   5. Le bouton d'essai coûte de l'argent : il est gardé
   ========================================================= */
titre("L'essai n'est ouvert qu'à l'enseigne");

async function appelerEssai(corps, entetes) {
  const reponse = await essai(new Request("https://fonction.essai/tester-sms", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(entetes || {}) },
    body: JSON.stringify(corps),
  }));
  return { statut: reponse.status, donnees: await reponse.json().catch(() => null) };
}

decor({ estSuper: () => false });
let e = await appelerEssai({ numero: "0197121596" }, { Authorization: "Bearer jeton-de-moderateur" });
egal(e.statut, 403, "un compte qui n'est pas superadministrateur — refusé");
egal(monde.envois.length, 0, "et aucun SMS à ses frais");

decor({ estSuper: () => false });
e = await appelerEssai({ numero: "0197121596" }, {});
egal(e.statut, 403, "sans jeton du tout — refusé");

decor();
e = await appelerEssai({ numero: "0197121596" }, { Authorization: "Bearer jeton-enseigne" });
egal(e.statut, 200, "le superadministrateur, lui, passe");
egal(monde.envois.length, 1, "et un vrai SMS part — c'est tout l'intérêt de l'essai");
verifie(monde.appelsSuper[0] === "Bearer jeton-enseigne",
  "le droit est demandé à la BASE, avec le jeton de l'appelant");

decor({ reponsePasserelle: () => ({ statut: 200, corps: { status: false, code: "MISSING_PARAMETERS_TO" } }) });
e = await appelerEssai({ numero: "0197121596" }, { Authorization: "Bearer jeton-enseigne" });
verifie(e.donnees.ok === false, "un refus reste un refus, même en 200");
egal(e.donnees.reponse_passerelle.code, "MISSING_PARAMETERS_TO",
  "la réponse ENTIÈRE de la passerelle revient : elle nomme ce qui manque");

decor();
const prevol = await essai(new Request("https://fonction.essai/tester-sms", { method: "OPTIONS" }));
egal(prevol.status, 200, "le contrôle préalable du navigateur reçoit sa réponse");
verifie(prevol.headers.get("Access-Control-Allow-Origin") === "*",
  "sans quoi le back-office ne verrait qu'une erreur réseau muette");

decor();
e = await appelerEssai({ numero: "12" }, { Authorization: "Bearer jeton-enseigne" });
egal(e.statut, 400, "un numéro incomplet est refusé avant l'appel");
verifie(!JSON.stringify(e.donnees).includes(SECRETS.SMS_CLE),
  "et la clé ne sort jamais vers le back-office");

/* ========================================================= */
dire("");
if (echecs > 0) {
  dire(rouge(echecs + " constat(s) en échec : une porte du SMS a cédé."));
  process.exit(1);
}
dire(vert("Le transport SMS tient : rien ne part sans signature, et un 200 ne suffit pas ✔"));
