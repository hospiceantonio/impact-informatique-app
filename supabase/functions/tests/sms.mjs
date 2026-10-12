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
  SUPABASE_SERVICE_ROLE_KEY: "cle-de-service-qui-ne-sort-jamais",
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
  /* GoTrue, qui reconnaît — ou non — le jeton de l'appelant. */
  if (adresse === SECRETS.SUPABASE_URL + "/auth/v1/user") {
    monde.appelsGoTrue.push(options.headers?.Authorization || "");
    return faireReponse(monde.goTrue(options.headers?.Authorization || ""));
  }
  /* La base, pour les deux fonctions de la clé de service. */
  if (adresse.endsWith("/rpc/enregistrer_code_connexion")) {
    const corps = JSON.parse(options.body || "{}");
    monde.inscriptions.push({ corps, entetes: options.headers || {} });
    return faireReponse({ corps: monde.inscrire(corps) });
  }
  if (adresse.endsWith("/rpc/annuler_code_connexion")) {
    monde.annulations.push(JSON.parse(options.body || "{}"));
    return faireReponse({ statut: 204, corps: "" });
  }
  throw new Error("adresse inattendue : " + adresse);
};

function decor(reglages = {}) {
  monde.envois = [];
  monde.appelsSuper = [];
  monde.reponsePasserelle = reglages.reponsePasserelle ??
    (() => ({ corps: { status: true, code: "SUBMITTED" } }));
  monde.estSuper = reglages.estSuper ?? (() => true);
  monde.appelsGoTrue = [];
  monde.inscriptions = [];
  monde.annulations = [];
  /* Par défaut, GoTrue reconnaît le jeton de « u-equipe », et la base
     accepte d'inscrire le code. */
  monde.goTrue = reglages.goTrue ??
    ((auth) => auth.includes(".") ? { corps: { id: "u-equipe" } } : { statut: 401, corps: {} });
  monde.inscrire = reglages.inscrire ??
    (() => ({ ok: true, id: 41, tel: "0197121596" }));
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
await import("../code-connexion/index.ts");
const codeConnexion = portes.pop();

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

/* LE CHANGEMENT DE NUMÉRO. Un compte ouvert par e-mail qui confirme son
   numéro n'a pas encore de « user.phone » : le code part vers le
   NOUVEAU, que GoTrue nomme dans « sms.phone » — et, à défaut, porte
   dans « user.new_phone ». Lire « user.phone » ne trouvait rien, et le
   SMS ne partait pas. */
titre("Le code part vers le numéro qu'on confirme");

decor();
const changement = JSON.stringify({
  user: { id: "u2", phone: "", new_phone: "2290196000000" },
  sms: { otp: "112233", phone: "2290196000000", sms_type: "phone_change" },
});
h = await appelerHook(changement, await signer(changement));
egal(h.statut, 200, "un compte e-mail qui confirme son numéro : accepté");
egal(monde.envois[0]?.corps.to, "2290196000000", "le code part vers le nouveau numéro");
verifie(monde.envois[0]?.corps.message.includes("112233"), "avec son code");

decor();
const ancienFormat = JSON.stringify({
  user: { id: "u3", phone: "2290197121596", new_phone: "2290196111111" },
  sms: { otp: "445566" },
});
h = await appelerHook(ancienFormat, await signer(ancienFormat));
egal(monde.envois[0]?.corps.to, "2290196111111",
  "sans « sms.phone », c'est « user.new_phone » — jamais l'ancien numéro");

decor();
const connexionSimple = JSON.stringify({
  user: { id: "u4", phone: "2290197121596" },
  sms: { otp: "778899", phone: "2290197121596" },
});
h = await appelerHook(connexionSimple, await signer(connexionSimple));
egal(monde.envois[0]?.corps.to, "2290197121596", "une connexion ordinaire ne change rien");

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


/* =========================================================
   6. Le code de connexion de l'équipe
   ========================================================= */
/** Un jeton comme en fabrique GoTrue : seul son contenu compte ici, la
    signature étant l'affaire de GoTrue — que la doublure imite. */
function jeton(contenu) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  return b64({ alg: "HS256", typ: "JWT" }) + "." + b64(contenu) + ".signature";
}
const JETON = jeton({ sub: "u-equipe", session_id: "5e55a0a0-0000-4000-8000-000000000001" });

async function demanderCode(entetes) {
  const reponse = await codeConnexion(new Request("https://fonction.essai/code-connexion", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(entetes || {}) },
    body: "{}",
  }));
  return { statut: reponse.status, donnees: await reponse.json().catch(() => null) };
}
const sha256 = async (texte) => Buffer.from(
  await crypto.subtle.digest("SHA-256", new TextEncoder().encode(texte))).toString("hex");

titre("Le code de l'équipe : il faut un jeton que GoTrue reconnaît");

decor();
let c = await demanderCode({});
egal(c.statut, 401, "sans jeton — refusé");
egal(monde.envois.length + monde.inscriptions.length, 0, "rien d'inscrit, rien d'envoyé");

decor({ goTrue: () => ({ statut: 401, corps: {} }) });
c = await demanderCode({ Authorization: "Bearer " + JETON });
egal(c.statut, 401, "un jeton que GoTrue ne reconnaît pas — refusé");
egal(monde.envois.length + monde.inscriptions.length, 0, "et rien ne part");

decor({ goTrue: () => ({ corps: { id: "un-autre-compte" } }) });
c = await demanderCode({ Authorization: "Bearer " + JETON });
egal(c.statut, 401, "un jeton dont le contenu ne dit pas le même compte que GoTrue — refusé");

decor();
c = await demanderCode({ Authorization: "Bearer " + jeton({ sub: "u-equipe" }) });
egal(c.statut, 401, "un jeton sans session — refusé : le code se rattache à une session");

titre("Le code part, et ne revient jamais");

decor();
c = await demanderCode({ Authorization: "Bearer " + JETON });
egal(c.statut, 200, "le compte reconnu reçoit son code");
egal(monde.envois.length, 1, "un SMS part");
egal(monde.envois[0].corps.to, "2290197121596", "au numéro que la BASE a donné, celui de la fiche");
const codeEnvoye = (monde.envois[0].corps.message.match(/\b(\d{6})\b/) || [])[1] || "";
verifie(/^\d{6}$/.test(codeEnvoye), "le SMS porte un code de six chiffres");
const inscription = monde.inscriptions[0] || { corps: {}, entetes: {} };
egal(inscription.corps.qui, "u-equipe", "la base reçoit le compte reconnu par GoTrue");
egal(inscription.corps.session, "5e55a0a0-0000-4000-8000-000000000001", "et la session du jeton");
egal(inscription.corps.hache, await sha256(codeEnvoye + ":5e55a0a0-0000-4000-8000-000000000001"),
  "l'empreinte est sha256(« code:session ») — celle que la base recalculera");
verifie(!JSON.stringify(inscription.corps).includes(codeEnvoye),
  "la base ne reçoit jamais le code lui-même");
egal(inscription.entetes.Authorization, "Bearer " + SECRETS.SUPABASE_SERVICE_ROLE_KEY,
  "elle est appelée avec la clé de service : la seule qui ouvre cette fonction");
verifie(!JSON.stringify(c.donnees).includes(codeEnvoye),
  "la réponse à l'application ne contient PAS le code");
egal(c.donnees.fin_numero, "96", "seulement les deux derniers chiffres du numéro");
verifie(!journal.some((l) => l.includes(codeEnvoye)), "le code n'est dans aucun journal");
verifie(!journal.some((l) => l.includes("0197121596") || l.includes("2290197121596")),
  "ni le numéro entier");
verifie(!journal.some((l) => l.includes(SECRETS.SUPABASE_SERVICE_ROLE_KEY)),
  "ni la clé de service");

/* LE MÊME CALCUL DES DEUX CÔTÉS. La base recalcule l'empreinte avec
   pgcrypto ; ce vecteur est celui que « 99u-connexion-sms.sql » éprouve
   aussi. S'ils divergeaient, aucun code ne serait jamais juste. */
egal(await sha256("123456:e1000000-0000-0000-0000-000000000001"),
  "6c04d1634fb52316e8e6b0d11a7dcf50ef38dc054cdf5f350a7a0ec9f58f537f",
  "l'empreinte de référence, partagée avec le banc de la base");

decor();
const JETON_MAJ = jeton({ sub: "u-equipe", session_id: "5E55A0A0-0000-4000-8000-000000000001" });
await demanderCode({ Authorization: "Bearer " + JETON_MAJ });
const codeMaj = (monde.envois[0]?.corps.message.match(/\b(\d{6})\b/) || [])[1] || "";
egal(monde.inscriptions[0]?.corps.hache,
  await sha256(codeMaj + ":5e55a0a0-0000-4000-8000-000000000001"),
  "une session écrite en majuscules est hachée en minuscules, comme la base l'écrit");

decor();
const tires = new Set();
for (let i = 0; i < 20; i++) {
  await demanderCode({ Authorization: "Bearer " + JETON });
  tires.add((monde.envois.at(-1).corps.message.match(/\b(\d{6})\b/) || [])[1]);
}
verifie(tires.size >= 18, "vingt demandes, vingt codes différents (ou presque) : le hasard tire");

titre("Ce que la base refuse, l'écran le dit");

decor({ inscrire: () => ({ ok: false, raison: "sans_numero" }) });
c = await demanderCode({ Authorization: "Bearer " + JETON });
egal(c.statut, 409, "un compte sans numéro");
verifie(/superadministrateur/.test(c.donnees.message), "le message dit à qui s'adresser");
egal(monde.envois.length, 0, "et aucun SMS ne part");

decor({ inscrire: () => ({ ok: false, raison: "trop_tot", attente: 12 }) });
c = await demanderCode({ Authorization: "Bearer " + JETON });
egal(c.statut, 429, "un code demandé trop tôt");
egal(c.donnees.attente, 12, "avec le délai à attendre");
egal(monde.envois.length, 0, "et pas de second SMS");

decor({ inscrire: () => ({ ok: false, raison: "trop_de_codes" }) });
c = await demanderCode({ Authorization: "Bearer " + JETON });
egal(c.statut, 429, "trop de codes dans l'heure");

decor({ inscrire: () => ({ ok: false, raison: "deja_confirmee" }) });
c = await demanderCode({ Authorization: "Bearer " + JETON });
egal(c.donnees.deja, true, "une session déjà confirmée : rien à envoyer, et ce n'est pas une panne");
egal(monde.envois.length, 0, "aucun SMS");

titre("Un SMS qui ne part pas ne compte pas");

decor({ reponsePasserelle: () => ({ corps: { status: false, code: "INSUFFICIENT_BALANCE" } }) });
c = await demanderCode({ Authorization: "Bearer " + JETON });
egal(c.statut, 502, "la passerelle refuse : l'écran le sait");
verifie(/[Cc]rédit SMS épuisé/.test(c.donnees.message), "et sait pourquoi");
egal(monde.annulations[0]?.code_id, 41, "le code inscrit est annulé : il ne mange pas un envoi de l'heure");
verifie(journal.some((l) => l.includes("INSUFFICIENT_BALANCE")),
  "et le crédit épuisé est au journal : plus personne de l'équipe n'entrerait");

decor();
const prevolCode = await codeConnexion(new Request("https://fonction.essai/code-connexion",
  { method: "OPTIONS" }));
egal(prevolCode.status, 200, "le contrôle préalable du navigateur reçoit sa réponse");

/* ========================================================= */
dire("");
if (echecs > 0) {
  dire(rouge(echecs + " constat(s) en échec : une porte du SMS a cédé."));
  process.exit(1);
}
dire(vert("Le transport SMS tient : rien ne part sans signature, et un 200 ne suffit pas ✔"));
