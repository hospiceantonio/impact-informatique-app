/* =========================================================
   BIZZOO — le banc de l'annonce d'un live TikTok

   CE QU'ON DÉFEND ICI.
     1. Sans jeton, rien ne part — ni base, ni Google, ni Firebase.
     2. La base décide, AU NOM DE L'APPELANT : son jeton est celui
        qui part vers « demarrer_live » ; un refus de la base est
        rendu tel quel, et aucune notification ne part.
     3. Un live déjà en cours n'est PAS annoncé une seconde fois.
     4. Le jeton signé pour Google est un vrai RS256, vérifiable avec
        la clé publique du compte de service.
     5. Le message part au sujet « tous », en DONNÉES seulement, avec
        le lien TikTok — c'est l'application qui ouvre ce lien.
     6. Sans compte de service : le live s'ouvre, la réponse dit ce
        qui manque. Firebase qui refuse : dit, et noté en base.
     7. La note en base part avec la clé de service, jamais avec le
        jeton de l'appelant.

   Google, Firebase et la base sont des DOUBLURES : aucun appel ne
   sort. Usage :  tools/eprouver-live.sh
   ========================================================= */
import { generateKeyPairSync, createVerify } from "node:crypto";

const dire = console.log.bind(console);
const rouge = (s) => "\x1b[31m" + s + "\x1b[0m";
const vert = (s) => "\x1b[32m" + s + "\x1b[0m";
const gris = (s) => "\x1b[90m" + s + "\x1b[0m";

const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const COMPTE = {
  type: "service_account",
  project_id: "bizzoo-essai",
  client_email: "notifications@bizzoo-essai.iam.gserviceaccount.com",
  /* Comme collé dans un champ d'une ligne : « \n » en toutes lettres. */
  private_key: privateKey.export({ type: "pkcs8", format: "pem" }).replace(/\n/g, "\\n"),
  token_uri: "https://oauth2.googleapis.com/token",
};
const SECRETS = {
  SUPABASE_URL: "https://base.essai",
  SUPABASE_ANON_KEY: "cle-publiable",
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
  if (a === SECRETS.SUPABASE_URL + "/rest/v1/rpc/demarrer_live") {
    monde.base.push({ jeton: o.headers.Authorization, corps: JSON.parse(o.body) });
    return monde.demarrer();
  }
  if (a === SECRETS.SUPABASE_URL + "/rest/v1/rpc/noter_annonce_live") {
    monde.notes.push({ jeton: o.headers.Authorization, corps: JSON.parse(o.body) });
    return reponse("", 204);
  }
  if (a === COMPTE.token_uri) {
    const p = new URLSearchParams(o.body);
    monde.google.push(p.get("assertion"));
    return monde.google_reponse();
  }
  if (a === "https://fcm.googleapis.com/v1/projects/bizzoo-essai/messages:send") {
    monde.fcm.push({ jeton: o.headers.Authorization, corps: JSON.parse(o.body) });
    return monde.fcm_reponse();
  }
  throw new Error("adresse inattendue : " + a);
};

const LIVE = { id: 12, boutique: "bou_mode", nom: "MODE COTONOU",
  lien: "https://www.tiktok.com/@modecotonou", deja: false };
function decor(r = {}) {
  monde.base = []; monde.notes = []; monde.google = []; monde.fcm = [];
  monde.demarrer = r.demarrer ?? (() => reponse(LIVE));
  monde.google_reponse = r.google ?? (() => reponse({ access_token: "acces-google", expires_in: 3599 }));
  monde.fcm_reponse = r.fcm ?? (() => reponse({ name: "projects/bizzoo-essai/messages/42" }));
  journal.length = 0;
}

let echecs = 0;
const verifie = (v, q) => { if (v) dire("  " + gris("ok") + "    " + q); else { echecs++; dire("  " + rouge("ÉCHEC") + " " + q); } };
const titre = (q) => { dire(""); dire("== " + q); };

await import("../annoncer-live/index.ts");
const porte = portes.pop();
const JETON = "Bearer aaa.bbb.ccc";
async function appeler(corps, jeton = JETON) {
  const r = await porte(new Request("https://fonction.essai/annoncer-live", {
    method: "POST", headers: jeton ? { Authorization: jeton } : {}, body: JSON.stringify(corps) }));
  return { statut: r.status, d: await r.json().catch(() => null) };
}
const rien = () => !monde.base.length && !monde.google.length && !monde.fcm.length;

titre("1. Sans jeton, rien ne part");
decor();
let r = await appeler({ boutique: "bou_mode" }, "");
verifie(r.statut === 401 && rien(), "pas connecté : 401, et aucun appel");
r = await appeler({ boutique: "bou_mode" }, "Bearer cle-publiable");
verifie(r.statut === 401 && rien(), "la clé publique n'est pas un jeton de session");

titre("2. La base décide, au nom de l'appelant");
decor({ demarrer: () => reponse({ message: "Seul l'administrateur de la boutique lance son live." }, 403) });
r = await appeler({ boutique: "bou_mode" });
verifie(monde.base[0] && monde.base[0].jeton === JETON && monde.base[0].corps.cible === "bou_mode",
  "la base est interrogée avec le jeton de l'appelant, pour sa boutique");
verifie(r.statut === 403 && /administrateur/.test(r.d.message), "son refus est rendu tel quel");
verifie(!monde.google.length && !monde.fcm.length, "et aucune notification ne part");

titre("3. Un live déjà en cours n'est pas réannoncé");
decor({ demarrer: () => reponse({ ...LIVE, deja: true }) });
r = await appeler({ boutique: "bou_mode" });
verifie(r.statut === 200 && r.d.deja === true && r.d.push === false && !monde.fcm.length,
  "« deja » : réponse polie, aucune notification");

titre("4 et 5. Le jeton signé, puis le message");
decor();
r = await appeler({ boutique: "bou_mode" });
const jwt = monde.google[0] || "";
const [e, c, s] = jwt.split(".");
const charge = c ? JSON.parse(Buffer.from(c, "base64url").toString()) : {};
const verif = createVerify("RSA-SHA256"); verif.update(e + "." + c);
verifie(s && verif.verify(publicKey, Buffer.from(s, "base64url")),
  "la signature RS256 se vérifie avec la clé publique du compte de service");
verifie(charge.iss === COMPTE.client_email && /firebase\.messaging/.test(charge.scope) &&
  charge.aud === COMPTE.token_uri && charge.exp - charge.iat === 3600,
  "le jeton dit qui, pour quoi, pour qui, et pour une heure");
const m = (monde.fcm[0] || {}).corps?.message || {};
verifie(monde.fcm[0] && monde.fcm[0].jeton === "Bearer acces-google", "Firebase reçoit le jeton d'accès de Google");
verifie(m.topic === "tous" && !m.notification && m.data && m.data.type === "live",
  "au sujet « tous », en données seulement");
verifie(m.data && m.data.lien === LIVE.lien && /MODE COTONOU est en live sur TikTok/.test(m.data.titre),
  "avec le lien TikTok et le nom de la boutique (" + (m.data && m.data.titre) + ")");
verifie(Object.values(m.data || {}).every((v) => typeof v === "string"), "toutes les données sont du texte (exigé par FCM)");
verifie(m.android && m.android.priority === "HIGH", "priorité haute : le téléphone se réveille");
verifie(r.d.ok && r.d.push === true, "la réponse dit que la notification est partie");
const note = monde.notes[0];
verifie(note && note.corps.cible === 12 && /^envoyée/.test(note.corps.resultat) &&
  note.jeton === "Bearer " + SECRETS.SUPABASE_SERVICE_ROLE_KEY,
  "c'est noté en base, avec la clé de service");
verifie(!JSON.stringify(r.d).includes(SECRETS.SUPABASE_SERVICE_ROLE_KEY) &&
  !JSON.stringify(r.d).includes("PRIVATE KEY"), "ni la clé de service ni la clé privée ne ressortent");

titre("6. Firebase absent, ou qui refuse");
const garde = SECRETS.FIREBASE_COMPTE_SERVICE;
SECRETS.FIREBASE_COMPTE_SERVICE = "";
decor();
r = await appeler({ boutique: "bou_mode" });
verifie(r.statut === 200 && r.d.push === false && /FIREBASE_COMPTE_SERVICE/.test(r.d.message) &&
  !monde.google.length, "pas de compte de service : le live s'ouvre, la réponse dit ce qui manque");
SECRETS.FIREBASE_COMPTE_SERVICE = garde;
decor({ google: () => reponse({ error: "invalid_grant", error_description: "Invalid JWT Signature." }, 400) });
r = await appeler({ boutique: "bou_mode" });
verifie(r.d.push === false && /Invalid JWT Signature/.test(r.d.message) && !monde.fcm.length,
  "Google refuse le compte : c'est dit, rien ne part chez Firebase");
decor({ fcm: () => reponse({ error: { message: "Requested entity was not found." } }, 404) });
r = await appeler({ boutique: "bou_mode" });
verifie(r.d.push === false && /not found/.test(r.d.message) && /^échec/.test(monde.notes[0].corps.resultat),
  "Firebase refuse : c'est dit, et noté en base");

dire("");
dire(echecs ? rouge(echecs + " constat(s) en échec ✘") : vert("L'annonce d'un live ne part que pour un live nouveau, lancé par qui en a le droit ✔"));
process.exit(echecs ? 1 : 0);
