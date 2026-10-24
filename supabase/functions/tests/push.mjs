/* =========================================================
   BIZZOO — le banc des notifications push (3.65.0)

   CE QU'ON DÉFEND ICI.
     1. Un appel sans numéro de notification valable ne touche à rien.
     2. Seul ce numéro vient de l'appel : la base est interrogée avec la
        clé de SERVICE (« push_a_envoyer ») ; ce qu'elle ne rend pas — déjà
        envoyée, inconnue — ne part pas.
     3. Chaque téléphone reçoit le message, en DONNÉES seulement, priorité
        haute ; une course part sur le canal « courses » (elle sonne jusqu'à
        ce qu'on la touche), une commande sur « commandes ».
     4. Un téléphone que Firebase ne connaît plus est oublié en base ; les
        autres reçoivent quand même.
     5. Sans compte de service, rien ne part, et c'est dit.

   Google, Firebase et la base sont des DOUBLURES : aucun appel ne
   sort. Usage :  tools/eprouver-push.sh
   ========================================================= */
import { generateKeyPairSync } from "node:crypto";

const dire = console.log.bind(console);
const rouge = (s) => "\x1b[31m" + s + "\x1b[0m";
const vert = (s) => "\x1b[32m" + s + "\x1b[0m";
const gris = (s) => "\x1b[90m" + s + "\x1b[0m";

const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const COMPTE = {
  type: "service_account",
  project_id: "bizzoo-essai",
  client_email: "notifications@bizzoo-essai.iam.gserviceaccount.com",
  private_key: privateKey.export({ type: "pkcs8", format: "pem" }),
  token_uri: "https://oauth2.googleapis.com/token",
};
const SECRETS = {
  SUPABASE_URL: "https://base.essai",
  SUPABASE_SERVICE_ROLE_KEY: "cle-de-service-qui-ne-sort-jamais",
  FIREBASE_COMPTE_SERVICE: JSON.stringify(COMPTE),
};
const portes = [];
globalThis.Deno = { env: { get: (n) => SECRETS[n] }, serve: (h) => portes.push(h) };
const journal = [];
for (const voie of ["log", "error", "warn"]) console[voie] = (...a) => journal.push(a.map(String).join(" "));

const monde = {};
const reponse = (corps, statut = 200) => new Response(
  typeof corps === "string" ? corps : JSON.stringify(corps),
  { status: statut, headers: { "Content-Type": "application/json" } });

globalThis.fetch = async (url, o = {}) => {
  const a = String(url);
  if (a === SECRETS.SUPABASE_URL + "/rest/v1/rpc/push_a_envoyer") {
    monde.base.push({ cle: o.headers.Authorization, corps: JSON.parse(o.body) });
    return monde.notification();
  }
  if (a === SECRETS.SUPABASE_URL + "/rest/v1/rpc/jeton_push_mort") {
    monde.morts.push({ cle: o.headers.Authorization, corps: JSON.parse(o.body) });
    return reponse("", 204);
  }
  if (a === COMPTE.token_uri) {
    monde.google.push(1);
    return reponse({ access_token: "acces-google", expires_in: 3599 });
  }
  if (a === "https://fcm.googleapis.com/v1/projects/bizzoo-essai/messages:send") {
    const corps = JSON.parse(o.body);
    monde.fcm.push({ jeton: o.headers.Authorization, corps });
    return monde.fcm_reponse(corps.message.token);
  }
  throw new Error("adresse inattendue : " + a);
};

const COURSE = { id: 501, type: "course_confiee", titre: "Nouvelle course — BZ-000101",
  corps: "Récupérer : Alpha", lien: "#/livraisons", commande_id: "cmd_km",
  jetons: ["jeton-telephone-aaaaaaaaaaaa", "jeton-telephone-bbbbbbbbbbbb"] };
function decor(r = {}) {
  monde.base = []; monde.morts = []; monde.google = []; monde.fcm = [];
  monde.notification = r.notification ?? (() => reponse(COURSE));
  monde.fcm_reponse = r.fcm ?? (() => reponse({ name: "projects/bizzoo-essai/messages/7" }));
  journal.length = 0;
}

let echecs = 0;
const verifie = (v, q) => { if (v) dire("  " + gris("ok") + "    " + q); else { echecs++; dire("  " + rouge("ÉCHEC") + " " + q); } };
const titre = (q) => { dire(""); dire("== " + q); };

await import("../envoyer-push/index.ts");
const porte = portes.pop();
async function appeler(corps, methode = "POST") {
  const r = await porte(new Request("https://fonction.essai/envoyer-push", {
    method: methode, body: methode === "POST" ? JSON.stringify(corps) : undefined }));
  return { statut: r.status, d: await r.json().catch(() => null) };
}

titre("1. Un appel sans numéro valable ne touche à rien");
decor();
let r = await appeler({});
verifie(r.statut === 400 && !monde.base.length && !monde.fcm.length, "sans numéro : 400, aucun appel");
r = await appeler({ id: "1; drop table" });
verifie(r.statut === 400 && !monde.base.length, "un numéro qui n'en est pas un : 400");
r = await appeler({ titre: "Faux titre", id: -3 });
verifie(r.statut === 400 && !monde.fcm.length, "un numéro négatif : 400");
r = await appeler(null, "GET");
verifie(r.statut === 405, "autre chose que POST : 405");

titre("2. La base dit quoi envoyer, avec la clé de service");
decor({ notification: () => reponse(null) });
r = await appeler({ id: 501, titre: "Titre forgé", jetons: ["jeton-forge-cccccccccccccc"] });
verifie(monde.base[0] && monde.base[0].cle === "Bearer " + SECRETS.SUPABASE_SERVICE_ROLE_KEY &&
  monde.base[0].corps.cible === 501, "push_a_envoyer(501), avec la clé de service");
verifie(r.statut === 200 && r.d.envoyees === 0 && !monde.fcm.length && !monde.google.length,
  "déjà envoyée (la base ne rend rien) : rien ne part, quoi que dise l'appel");

titre("3. Chaque téléphone reçoit la course, en données, priorité haute");
decor();
r = await appeler({ id: 501, titre: "Titre forgé" });
verifie(r.statut === 200 && r.d.envoyees === 2 && monde.fcm.length === 2, "deux téléphones, deux envois");
const m = (monde.fcm[0] || {}).corps?.message || {};
verifie(m.token === COURSE.jetons[0] && !m.topic && !m.notification, "à UN téléphone, en données seulement");
verifie(m.data && m.data.titre === COURSE.titre && m.data.lien === "#/livraisons" && m.data.canal === "courses",
  "le titre et le lien de la base (pas ceux de l'appel), sur le canal « courses »");
verifie(Object.values(m.data || {}).every((v) => typeof v === "string"), "toutes les données sont du texte (exigé par FCM)");
verifie(m.android && m.android.priority === "HIGH" && m.android.ttl === "900s",
  "priorité haute, et un quart d'heure de vie au plus");
verifie(monde.google.length === 1, "un seul jeton d'accès Google pour tous les téléphones");
decor({ notification: () => reponse({ ...COURSE, id: 502, type: "commande_payee", titre: "Nouvelle commande",
  lien: "#/commandes/cmd_x", jetons: ["jeton-boutique-dddddddddddd"] }) });
r = await appeler({ id: 502 });
const m2 = (monde.fcm[0] || {}).corps?.message || {};
verifie(m2.data && m2.data.canal === "commandes" && m2.data.lien === "#/commandes/cmd_x" && m2.android.ttl === "3600s",
  "une commande payée : canal « commandes », une heure de vie");

titre("4. Un téléphone désinstallé est oublié, les autres reçoivent");
decor({ fcm: (jeton) => jeton === COURSE.jetons[0]
  ? reponse({ error: { code: 404, message: "Requested entity was not found.", status: "NOT_FOUND",
      details: [{ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode: "UNREGISTERED" }] } }, 404)
  : reponse({ name: "projects/bizzoo-essai/messages/8" }) });
r = await appeler({ id: 501 });
verifie(r.d.envoyees === 1 && r.d.echecs === 1, "un envoyé, un en échec");
verifie(monde.morts.length === 1 && monde.morts[0].corps.jeton === COURSE.jetons[0] &&
  monde.morts[0].cle === "Bearer " + SECRETS.SUPABASE_SERVICE_ROLE_KEY, "le jeton mort est oublié en base");
decor({ fcm: () => reponse({ error: { code: 500, message: "Internal error" } }, 500) });
r = await appeler({ id: 501 });
verifie(!monde.morts.length, "une panne de Firebase n'efface aucun téléphone");

titre("5. Sans compte de service");
const garde = SECRETS.FIREBASE_COMPTE_SERVICE;
SECRETS.FIREBASE_COMPTE_SERVICE = "";
decor();
r = await appeler({ id: 501 });
verifie(r.statut === 500 && /Firebase/.test(r.d.message) && !monde.fcm.length, "rien ne part, et c'est dit");
SECRETS.FIREBASE_COMPTE_SERVICE = garde;
verifie(!journal.some((l) => l.includes(SECRETS.SUPABASE_SERVICE_ROLE_KEY)), "la clé de service n'apparaît dans aucun journal");

dire("");
if (echecs) { dire(rouge(echecs + " constat(s) en échec ✘")); process.exit(1); }
dire(vert("Le push ne part que pour une notification de la base, une fois, vers les téléphones de son destinataire ✔"));
