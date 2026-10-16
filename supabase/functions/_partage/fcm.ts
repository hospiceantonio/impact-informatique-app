/* =========================================================
   BIZZOO — envoyer une notification par Firebase (FCM)

   Firebase Cloud Messaging porte une notification jusqu'aux
   téléphones où l'application BIZZOO est installée. On lui parle
   par son API « HTTP v1 », avec un COMPTE DE SERVICE : un petit
   fichier JSON que la console Firebase fabrique, et qui contient
   une clé privée.

   CETTE CLÉ NE QUITTE JAMAIS LES SECRETS SUPABASE. Elle n'est ni
   dans le dépôt, ni dans un APK, ni dans une conversation : le
   propriétaire la colle lui-même dans
     Supabase → Edge Functions → Secrets → FIREBASE_COMPTE_SERVICE
   (le contenu ENTIER du fichier JSON).

   Le chemin, en trois temps :
     1. on signe un jeton (JWT, RS256) avec la clé privée ;
     2. Google l'échange contre un jeton d'accès d'une heure ;
     3. on envoie le message au SUJET « tous », auquel chaque
        application BIZZOO s'abonne à son ouverture.

   LE MESSAGE NE PORTE QUE DES DONNÉES (« data »), pas de bloc
   « notification ». C'est voulu : l'application construit elle-même
   la notification, et la touche ouvre DIRECTEMENT le lien TikTok —
   ce qu'un bloc « notification » ne sait pas faire quand
   l'application est fermée (il rouvrirait seulement l'application).
   ========================================================= */

export type CompteService = {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
};

export const SUJET_TOUS = "tous";
const PORTEE = "https://www.googleapis.com/auth/firebase.messaging";
const JETON_GOOGLE = "https://oauth2.googleapis.com/token";

/** Le compte de service, lu dans les secrets. null s'il manque ou ne se lit pas. */
export function lireCompte(): CompteService | null {
  const brut = Deno.env.get("FIREBASE_COMPTE_SERVICE") ?? "";
  if (!brut.trim()) return null;
  try {
    const c = JSON.parse(brut) as CompteService;
    if (!c.project_id || !c.client_email || !c.private_key) return null;
    /* Collé dans un champ d'une ligne, « \n » arrive parfois écrit en
       toutes lettres : la clé ne se lirait plus. */
    return { ...c, private_key: c.private_key.replace(/\\n/g, "\n") };
  } catch (_) {
    return null;
  }
}

const base64url = (octets: Uint8Array) => {
  let s = "";
  for (const o of octets) s += String.fromCharCode(o);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};
const texteB64 = (t: string) => base64url(new TextEncoder().encode(t));

/** La clé privée PEM (PKCS#8) en clé de signature. */
async function cleDeSignature(pem: string): Promise<CryptoKey> {
  const corps = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(corps), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey("pkcs8", der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
}

/** Le jeton signé que Google échange contre un jeton d'accès. */
export async function jetonSigne(compte: CompteService, maintenant = Math.floor(Date.now() / 1000)) {
  const entete = texteB64(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const charge = texteB64(JSON.stringify({
    iss: compte.client_email,
    scope: PORTEE,
    aud: compte.token_uri || JETON_GOOGLE,
    iat: maintenant,
    exp: maintenant + 3600,
  }));
  const cle = await cleDeSignature(compte.private_key);
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", cle, new TextEncoder().encode(entete + "." + charge)));
  return entete + "." + charge + "." + base64url(signature);
}

export type Envoi = { ok: boolean; statut: number; message: string };

/** Envoie des données à tous les téléphones abonnés au sujet. */
export async function envoyerAuSujet(
  compte: CompteService, sujet: string, donnees: Record<string, string>,
): Promise<Envoi> {
  let acces = "";
  try {
    const r = await fetch(compte.token_uri || JETON_GOOGLE, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: "grant_type=" + encodeURIComponent("urn:ietf:params:oauth:grant-type:jwt-bearer") +
        "&assertion=" + encodeURIComponent(await jetonSigne(compte)),
      signal: AbortSignal.timeout(15000),
    });
    const d = await r.json().catch(() => ({})) as { access_token?: string; error_description?: string };
    if (!r.ok || !d.access_token) {
      return { ok: false, statut: r.status,
        message: "Google refuse le compte de service : " + (d.error_description || "HTTP " + r.status) };
    }
    acces = d.access_token;
  } catch (e) {
    return { ok: false, statut: 0, message: "Google injoignable : " + String(e) };
  }

  try {
    const r = await fetch(
      "https://fcm.googleapis.com/v1/projects/" + encodeURIComponent(compte.project_id) + "/messages:send", {
        method: "POST",
        headers: { "Authorization": "Bearer " + acces, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            topic: sujet,
            data: donnees,
            /* « HIGH » : la notification réveille le téléphone, même en
               veille. Quatre heures de vie : au-delà, le live est fini. */
            android: { priority: "HIGH", ttl: "14400s" },
          },
        }),
        signal: AbortSignal.timeout(15000),
      });
    const d = await r.json().catch(() => ({})) as { name?: string; error?: { message?: string } };
    if (!r.ok) {
      return { ok: false, statut: r.status,
        message: "Firebase refuse l'envoi : " + ((d.error && d.error.message) || "HTTP " + r.status) };
    }
    return { ok: true, statut: r.status, message: d.name || "envoyée" };
  } catch (e) {
    return { ok: false, statut: 0, message: "Firebase injoignable : " + String(e) };
  }
}
