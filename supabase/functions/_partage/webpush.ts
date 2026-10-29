/* =========================================================
   BIZZOO — envoyer une notification Web Push (navigateur, PWA)

   BIZZOO Personnel est une application web : son téléphone ne
   connaît pas Firebase, mais son navigateur sait recevoir une
   notification « Web Push ». Chaque navigateur abonné donne trois
   choses : une adresse chez son service de push (Google, Mozilla,
   Apple…), et deux clés pour chiffrer ce qu'on lui envoie (p256dh,
   auth). On lui parle avec une paire de clés VAPID, qui prouve que
   c'est bien BIZZOO qui écrit.

   LA CLÉ PRIVÉE VAPID NE QUITTE JAMAIS LES SECRETS SUPABASE.
   Le propriétaire la fabrique sur son PC (tools/vapid-cles.mjs) et
   la colle lui-même dans
     Supabase → Edge Functions → Secrets → VAPID_PRIVEE
   avec VAPID_PUBLIQUE (la même que dans rh_push_reglage) et
   VAPID_SUJET (« mailto:… », l'adresse que le service de push
   peut prévenir en cas d'abus).

   Tout se fait avec WebCrypto, sans bibliothèque :
     - le chiffrement « aes128gcm » de la RFC 8291 (une clé
       éphémère par message, ECDH avec la clé du navigateur, HKDF,
       AES-128-GCM) ;
     - la signature VAPID de la RFC 8292 (un jeton ES256 de 12 h,
       pour l'origine du service de push).
   ========================================================= */

export type Abonnement = { endpoint: string; p256dh: string; auth: string };
export type ClesVapid = { publique: string; privee: string; sujet: string };

const encodeur = new TextEncoder();

export function base64url(octets: Uint8Array): string {
  let s = "";
  for (const o of octets) s += String.fromCharCode(o);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function depuisBase64url(texte: string): Uint8Array {
  const b = texte.replace(/-/g, "+").replace(/_/g, "/");
  const brut = atob(b + "===".slice((b.length + 3) % 4));
  return Uint8Array.from(brut, (c) => c.charCodeAt(0));
}

function concat(...morceaux: Uint8Array[]): Uint8Array {
  const total = new Uint8Array(morceaux.reduce((n, m) => n + m.length, 0));
  let i = 0;
  for (const m of morceaux) { total.set(m, i); i += m.length; }
  return total;
}

async function hkdf(sel: Uint8Array, ikm: Uint8Array, info: Uint8Array, octets: number): Promise<Uint8Array> {
  const cle = await crypto.subtle.importKey("raw", ikm, "HKDF", false, ["deriveBits"]);
  return new Uint8Array(await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt: sel, info }, cle, octets * 8));
}

/** Les clés VAPID, lues dans les secrets. null s'il en manque une. */
export function lireClesVapid(): ClesVapid | null {
  const publique = (Deno.env.get("VAPID_PUBLIQUE") ?? "").trim();
  const privee = (Deno.env.get("VAPID_PRIVEE") ?? "").trim();
  const sujet = (Deno.env.get("VAPID_SUJET") ?? "").trim();
  if (!publique || !privee || !/^(mailto:|https:\/\/)/.test(sujet)) return null;
  return { publique, privee, sujet };
}

/** La clé privée VAPID (32 octets « d ») et sa publique (65 octets), en clé de signature. */
async function cleDeSignature(v: ClesVapid): Promise<CryptoKey> {
  const pub = depuisBase64url(v.publique);
  if (pub.length !== 65 || pub[0] !== 4) throw new Error("VAPID_PUBLIQUE illisible");
  return await crypto.subtle.importKey("jwk", {
    kty: "EC", crv: "P-256", d: v.privee, ext: true,
    x: base64url(pub.slice(1, 33)), y: base64url(pub.slice(33, 65)),
  }, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

/** L'en-tête « Authorization » VAPID pour l'origine du service de push. */
export async function enteteVapid(v: ClesVapid, endpoint: string, maintenant = Date.now()): Promise<string> {
  const entete = base64url(encodeur.encode(JSON.stringify({ typ: "JWT", alg: "ES256" })));
  const charge = base64url(encodeur.encode(JSON.stringify({
    aud: new URL(endpoint).origin, exp: Math.floor(maintenant / 1000) + 12 * 3600, sub: v.sujet,
  })));
  const signature = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, await cleDeSignature(v), encodeur.encode(entete + "." + charge)));
  return "vapid t=" + entete + "." + charge + "." + base64url(signature) + ", k=" + v.publique;
}

/** Chiffre un message pour un navigateur abonné (RFC 8291, un seul bloc). */
export async function chiffrer(a: Abonnement, message: Uint8Array): Promise<Uint8Array> {
  const cleNavigateur = depuisBase64url(a.p256dh);
  const secret = depuisBase64url(a.auth);
  if (cleNavigateur.length !== 65 || secret.length < 16) throw new Error("abonnement illisible");
  const ephemere = await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
  const nousPublique = new Uint8Array(await crypto.subtle.exportKey("raw", ephemere.publicKey));
  const euxPublique = await crypto.subtle.importKey("raw", cleNavigateur, { name: "ECDH", namedCurve: "P-256" }, false, []);
  const partage = new Uint8Array(await crypto.subtle.deriveBits({ name: "ECDH", public: euxPublique }, ephemere.privateKey, 256));
  const ikm = await hkdf(secret, partage,
    concat(encodeur.encode("WebPush: info\0"), cleNavigateur, nousPublique), 32);
  const sel = crypto.getRandomValues(new Uint8Array(16));
  const cek = await hkdf(sel, ikm, encodeur.encode("Content-Encoding: aes128gcm\0"), 16);
  const nonce = await hkdf(sel, ikm, encodeur.encode("Content-Encoding: nonce\0"), 12);
  const cle = await crypto.subtle.importKey("raw", cek, "AES-GCM", false, ["encrypt"]);
  // Un seul bloc : le message, puis le délimiteur 0x02 du dernier bloc.
  const chiffre = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, cle,
    concat(message, new Uint8Array([2]))));
  const taille = new Uint8Array(4);
  new DataView(taille.buffer).setUint32(0, 4096);
  return concat(sel, taille, new Uint8Array([nousPublique.length]), nousPublique, chiffre);
}

export type Envoi = { ok: true } | { ok: false; mort: boolean; message: string };

/** Envoie un message à un navigateur. « mort » : l'abonnement n'existe plus (404, 410). */
export async function envoyerWebPush(v: ClesVapid, a: Abonnement, donnees: unknown, ttl = 3600): Promise<Envoi> {
  try {
    const corps = await chiffrer(a, encodeur.encode(JSON.stringify(donnees)));
    const r = await fetch(a.endpoint, {
      method: "POST",
      headers: {
        "Authorization": await enteteVapid(v, a.endpoint),
        "Content-Encoding": "aes128gcm",
        "Content-Type": "application/octet-stream",
        "TTL": String(ttl),
        "Urgency": "high",
      },
      body: corps,
      signal: AbortSignal.timeout(10000),
    });
    if (r.ok) return { ok: true };
    const texte = (await r.text().catch(() => "")).slice(0, 200);
    return { ok: false, mort: r.status === 404 || r.status === 410, message: "HTTP " + r.status + " " + texte };
  } catch (e) {
    return { ok: false, mort: false, message: String(e) };
  }
}
