/* =========================================================
   BIZZOO Personnel — le banc des alertes sur le téléphone (rh-push)

   CE QU'ON DÉFEND ICI.
     1. Un appel sans numéro d'envoi valable ne touche à rien.
     2. Sans clés VAPID, rien n'est demandé à la base : l'envoi n'est
        pas consommé pour rien, et c'est dit.
     3. Seul ce numéro vient de l'appel : la base est interrogée avec la
        clé de SERVICE (« rh_push_a_envoyer ») ; ce qu'elle ne rend pas
        ne part pas.
     4. Chaque navigateur reçoit un message CHIFFRÉ pour lui (RFC 8291,
        aes128gcm) : on le déchiffre ici avec node:crypto, sa clé privée
        à lui, et l'on retrouve exactement le titre, le texte et le lien
        de la base ; la signature VAPID (ES256) se vérifie avec la clé
        publique, pour l'origine du service de push.
     5. Un abonnement que le service ne connaît plus (410) est oublié en
        base ; les autres reçoivent quand même.

   Le service de push et la base sont des DOUBLURES : aucun appel ne
   sort. Usage :  tools/eprouver-rh-push.sh
   ========================================================= */
import { createECDH, createDecipheriv, hkdfSync, createPublicKey, verify } from "node:crypto";

const dire = console.log.bind(console);
const rouge = (s) => "\x1b[31m" + s + "\x1b[0m";
const vert = (s) => "\x1b[32m" + s + "\x1b[0m";
const gris = (s) => "\x1b[90m" + s + "\x1b[0m";
const b64 = (o) => Buffer.from(o).toString("base64url");

/* Les clés VAPID de l'essai, fabriquées comme tools/vapid-cles.mjs. */
const vapid = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const vapidPub = new Uint8Array(await crypto.subtle.exportKey("raw", vapid.publicKey));
const vapidJwk = await crypto.subtle.exportKey("jwk", vapid.privateKey);

const SECRETS = {
  SUPABASE_URL: "https://base.essai",
  SUPABASE_SERVICE_ROLE_KEY: "cle-de-service-qui-ne-sort-jamais",
  VAPID_PUBLIQUE: b64(vapidPub),
  VAPID_PRIVEE: vapidJwk.d,
  VAPID_SUJET: "mailto:equipe@bizzoomarket.com",
};
const portes = [];
globalThis.Deno = { env: { get: (n) => SECRETS[n] }, serve: (h) => portes.push(h) };
const journal = [];
for (const voie of ["log", "error", "warn"]) console[voie] = (...a) => journal.push(a.map(String).join(" "));

/* Deux navigateurs abonnés : leurs clés, que seul le banc connaît. */
function navigateur(nom) {
  const ecdh = createECDH("prime256v1");
  ecdh.generateKeys();
  const auth = crypto.getRandomValues(new Uint8Array(16));
  return { nom, ecdh, abonnement: { endpoint: "https://push." + nom + ".essai/abc/" + nom,
                                    p256dh: b64(ecdh.getPublicKey()), auth: b64(auth) }, auth };
}
const A = navigateur("vivant"), B = navigateur("mort");

const monde = {};
const reponse = (corps, statut = 200) => new Response(
  typeof corps === "string" ? corps : JSON.stringify(corps),
  { status: statut, headers: { "Content-Type": "application/json" } });

globalThis.fetch = async (url, o = {}) => {
  const a = String(url);
  if (a === SECRETS.SUPABASE_URL + "/rest/v1/rpc/rh_push_a_envoyer") {
    monde.base.push({ cle: o.headers.Authorization, corps: JSON.parse(o.body) });
    return monde.envoi();
  }
  if (a === SECRETS.SUPABASE_URL + "/rest/v1/rpc/rh_push_abonnement_mort") {
    monde.morts.push(JSON.parse(o.body));
    return reponse("", 204);
  }
  if (a.startsWith("https://push.")) {
    monde.push.push({ url: a, entetes: o.headers, corps: new Uint8Array(o.body) });
    return a.includes("mort") ? reponse("gone", 410) : reponse("", 201);
  }
  throw new Error("appel inattendu : " + a);
};

await import("../rh-push/index.ts");
const porte = portes[0];
const appeler = (corps) => porte(new Request("https://fonction.essai/rh-push", {
  method: "POST", body: JSON.stringify(corps), headers: { "Content-Type": "application/json" } }));
const neuf = (envoi) => {
  monde.base = []; monde.morts = []; monde.push = [];
  monde.envoi = envoi;
};

let echecs = 0;
const ok = (vrai, quoi) => {
  if (vrai) dire(vert("  ok  ") + quoi);
  else { echecs++; dire(rouge("  ÉCHEC  ") + quoi); }
};

/** Déchiffre comme le ferait le navigateur (RFC 8291), avec node:crypto. */
function dechiffrer(nav, corps) {
  const sel = corps.subarray(0, 16);
  const idlen = corps[20];
  const leur = corps.subarray(21, 21 + idlen);
  const chiffre = corps.subarray(21 + idlen);
  const partage = nav.ecdh.computeSecret(leur);
  const info = Buffer.concat([Buffer.from("WebPush: info\0"), nav.ecdh.getPublicKey(), leur]);
  const ikm = Buffer.from(hkdfSync("sha256", partage, nav.auth, info, 32));
  const cek = Buffer.from(hkdfSync("sha256", ikm, sel, Buffer.from("Content-Encoding: aes128gcm\0"), 16));
  const nonce = Buffer.from(hkdfSync("sha256", ikm, sel, Buffer.from("Content-Encoding: nonce\0"), 12));
  const d = createDecipheriv("aes-128-gcm", cek, nonce);
  d.setAuthTag(chiffre.subarray(chiffre.length - 16));
  const clair = Buffer.concat([d.update(chiffre.subarray(0, chiffre.length - 16)), d.final()]);
  if (clair[clair.length - 1] !== 2) throw new Error("délimiteur absent");
  return JSON.parse(clair.subarray(0, clair.length - 1).toString("utf8"));
}

/** Vérifie le jeton VAPID : signature, origine, sujet, clé annoncée. */
function jetonValable(entete, endpoint) {
  const m = /^vapid t=([^.]+)\.([^.]+)\.([^,]+), k=(.+)$/.exec(entete || "");
  if (!m) return false;
  const charge = JSON.parse(Buffer.from(m[2], "base64url").toString());
  const cle = createPublicKey({ key: { kty: "EC", crv: "P-256", x: b64(vapidPub.slice(1, 33)), y: b64(vapidPub.slice(33)) }, format: "jwk" });
  const signe = verify("sha256", Buffer.from(m[1] + "." + m[2]), { key: cle, dsaEncoding: "ieee-p1363" }, Buffer.from(m[3], "base64url"));
  return signe && m[4] === SECRETS.VAPID_PUBLIQUE && charge.aud === new URL(endpoint).origin
    && charge.sub === SECRETS.VAPID_SUJET && charge.exp > Date.now() / 1000;
}

dire(gris("1. Un appel sans numéro valable"));
neuf(() => reponse(null));
let r = await appeler({ id: "x" });
ok(r.status === 400 && monde.base.length === 0, "refusé (400), la base n'est pas interrogée");

dire(gris("2. Sans clés VAPID"));
const garde = SECRETS.VAPID_PRIVEE;
delete SECRETS.VAPID_PRIVEE;
neuf(() => reponse(null));
r = await appeler({ id: 7 });
ok(r.status === 500 && monde.base.length === 0, "rien n'est demandé à la base, l'envoi n'est pas consommé");
ok(journal.some((l) => l.includes("VAPID")), "et le journal dit pourquoi");
SECRETS.VAPID_PRIVEE = garde;

dire(gris("3. La base ne rend rien (déjà parti, inconnu)"));
neuf(() => reponse(null));
r = await appeler({ id: 7 });
ok(r.status === 200 && monde.push.length === 0, "rien ne part");
ok(monde.base.length === 1 && monde.base[0].cle === "Bearer " + SECRETS.SUPABASE_SERVICE_ROLE_KEY
   && monde.base[0].corps.cible === 7, "la base est interrogée avec la clé de service et le seul numéro");

dire(gris("4 et 5. Deux navigateurs, dont un disparu"));
const MESSAGE = { id: 12, titre: "Préparation en retard", corps: "Préparation en retard — BZ-123", lien: "#/suivi/commande/cmd_1",
  tache: "suivi:retard_preparation:cmd_1",
  abonnements: [A.abonnement, B.abonnement] };
neuf(() => reponse(MESSAGE));
r = await appeler({ id: 12, titre: "FORGÉ", corps: "forgé" });
const rendu = await r.json();
ok(r.status === 200 && rendu.envoyees === 1 && rendu.echecs === 1, "un envoyé, un en échec");
ok(monde.push.length === 2, "chaque navigateur est appelé");
const versA = monde.push.find((p) => p.url === A.abonnement.endpoint);
const lu = dechiffrer(A, versA.corps);
ok(lu.titre === MESSAGE.titre && lu.corps === MESSAGE.corps && lu.lien === MESSAGE.lien && lu.id === 12,
  "le navigateur déchiffre exactement le message de la base (rien de l'appel)");
ok(lu.tache === MESSAGE.tache, "avec la clé de la tâche, qui sert d'étiquette à la notification");
ok(versA.entetes["Content-Encoding"] === "aes128gcm" && Number(versA.entetes.TTL) > 0, "aes128gcm, avec une durée de vie");
ok(jetonValable(versA.entetes.Authorization, A.abonnement.endpoint), "la signature VAPID se vérifie, pour l'origine du service");
let autre = true;
try { dechiffrer(B, versA.corps); autre = false; } catch (_) { /* attendu */ }
ok(autre, "un autre navigateur ne sait pas le lire");
ok(monde.morts.length === 1 && monde.morts[0].v_endpoint === B.abonnement.endpoint, "l'abonnement disparu est oublié en base");

if (echecs) {
  dire(rouge(echecs + " porte(s) ont cédé."));
  process.exit(1);
}
dire(vert("Les alertes sur le téléphone tiennent ✔"));
