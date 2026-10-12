/* =========================================================
   BIZZOO — le code de connexion de l'équipe

   Quand l'enseigne l'exige, un compte de l'équipe qui vient de
   donner son mot de passe n'a encore AUCUN droit : la base attend
   le code qu'on lui envoie ici, par SMS, au numéro de sa fiche.

   POURQUOI UN CODE À NOUS, et pas celui de Supabase Auth ? Parce
   que GoTrue marque de la même étiquette une session ouverte par
   un code SMS et une session ouverte par un lien reçu par e-mail.
   La base ne saurait pas les distinguer. Le seul témoin d'un SMS
   reçu est un code que nous avons tiré et que la personne nous
   rend.

   CE QUE CETTE FONCTION SAIT, ET CE QU'ELLE NE DIT JAMAIS.

   1. ELLE SEULE CONNAÎT LE CODE EN CLAIR. Elle le tire, n'en
      confie à la base que l'empreinte — sha256(« code:session ») —
      et l'envoie par SMS. Il ne revient jamais à l'application :
      lire la réponse réseau suffirait sinon à ouvrir n'importe
      quelle session.

   2. LE NUMÉRO EST CELUI DE LA FICHE, que l'administrateur a
      enregistré. Jamais un numéro reçu dans la requête : un mot de
      passe volé suffirait alors, le voleur donnerait le sien.

   3. LE JETON EST REDEMANDÉ À GOTRUE. La passerelle de Supabase
      le vérifie déjà quand la fonction est déployée avec la
      vérification ; on ne s'y fie pas seul, parce qu'un déploiement
      oublié « --no-verify-jwt » ferait de cette fonction une
      machine à envoyer des SMS aux frais de l'enseigne.

   4. UN SMS QUI NE PART PAS NE COMPTE PAS : le code est annulé, et
      ne mange pas l'un des cinq envois de l'heure.

   ---------------------------------------------------------
   Déploiement (une fois)
   ---------------------------------------------------------
     supabase functions deploy code-connexion

   AVEC la vérification du jeton : c'est voulu, voir le point 3.
   Les secrets SMS_CLE et SMS_EXPEDITEUR sont ceux du hook ;
   SUPABASE_URL, SUPABASE_ANON_KEY et SUPABASE_SERVICE_ROLE_KEY
   sont fournis par Supabase à chaque fonction.
   ========================================================= */

import { envoyerSms } from "../_partage/sms.ts";

const BASE = Deno.env.get("SUPABASE_URL") ?? "";
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (corps: unknown, statut = 200) =>
  new Response(JSON.stringify(corps), {
    status: statut,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

/* Le message. Sans accents : un seul caractère hors de l'alphabet du
   SMS fait passer tout le message en Unicode, qui coûte deux SMS au lieu
   d'un. Le nom de l'application y figure, pour qu'on sache d'où vient un
   code qu'on n'aurait pas demandé. */
function messageDuCode(code: string): string {
  return "BIZZOO Admin : votre code de connexion est " + code +
    ". Il expire dans 10 minutes. Ne le communiquez a personne.";
}

/** Le contenu du jeton. Il n'est cru qu'après que GoTrue l'a reconnu. */
function contenuDuJeton(jeton: string): Record<string, unknown> | null {
  const morceaux = jeton.split(".");
  if (morceaux.length !== 3) return null;
  try {
    let charge = morceaux[1].replace(/-/g, "+").replace(/_/g, "/");
    charge += "===".slice((charge.length + 3) % 4);
    const octets = Uint8Array.from(atob(charge), (c) => c.charCodeAt(0));
    return JSON.parse(new TextDecoder().decode(octets));
  } catch (_) {
    return null;
  }
}

/** Le compte du jeton, selon GoTrue : un jeton forgé ou périmé n'y passe pas. */
async function compteReconnu(jeton: string): Promise<string | null> {
  if (!jeton || !BASE || !ANON) return null;
  try {
    const reponse = await fetch(BASE + "/auth/v1/user", {
      headers: { "apikey": ANON, "Authorization": "Bearer " + jeton },
      signal: AbortSignal.timeout(10000),
    });
    if (!reponse.ok) return null;
    const u = await reponse.json().catch(() => null) as { id?: string } | null;
    return u && typeof u.id === "string" ? u.id : null;
  } catch (_) {
    return null;
  }
}

/** Six chiffres, tirés sans biais : on écarte ce qui dépasse le dernier
    multiple d'un million, qui ferait sortir les petits codes plus
    souvent que les grands. */
function codeAuHasard(): string {
  const lot = new Uint32Array(1);
  const plafond = Math.floor(0x100000000 / 1000000) * 1000000;
  do { crypto.getRandomValues(lot); } while (lot[0] >= plafond);
  return String(lot[0] % 1000000).padStart(6, "0");
}

/** L'empreinte que la base comparera : sha256(« code:session »). */
async function empreinte(code: string, session: string): Promise<string> {
  const octets = await crypto.subtle.digest(
    "SHA-256", new TextEncoder().encode(code + ":" + session));
  return Array.from(new Uint8Array(octets))
    .map((o) => o.toString(16).padStart(2, "0")).join("");
}

/** Une fonction de la base, avec la clé de service : celles-ci sont
    fermées à tout compte connecté. */
async function rpcService(nom: string, corps: unknown): Promise<unknown> {
  const reponse = await fetch(BASE + "/rest/v1/rpc/" + nom, {
    method: "POST",
    headers: {
      "apikey": SERVICE,
      "Authorization": "Bearer " + SERVICE,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(corps),
    signal: AbortSignal.timeout(10000),
  });
  if (!reponse.ok) throw new Error("base : " + reponse.status);
  return await reponse.json().catch(() => null);
}

const REFUS: Record<string, [number, string]> = {
  sans_numero: [409,
    "Votre compte n'a pas de numéro enregistré. Demandez à un superadministrateur " +
    "de l'ajouter dans Comptes."],
  hors_equipe: [403, "Ce compte n'est pas un compte actif de l'équipe."],
  trop_de_codes: [429,
    "Trop de codes demandés en une heure. Réessayez plus tard, ou demandez à un " +
    "superadministrateur."],
  requete: [400, "Demande de code invalide."],
};

Deno.serve(async (requete) => {
  /* Le back-office tourne dans un navigateur : sans réponse au contrôle
     préalable, il ne verrait qu'une erreur réseau muette. */
  if (requete.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (requete.method !== "POST") {
    return json({ ok: false, message: "Méthode non permise" }, 405);
  }

  const jeton = (requete.headers.get("Authorization") ?? "")
    .replace(/^Bearer\s+/i, "").trim();
  const contenu = contenuDuJeton(jeton);
  /* En minuscules : la base recalcule l'empreinte sur « session::text »,
     qui l'écrit ainsi. Une majuscule, et aucun code ne serait juste. */
  const session = String(contenu?.session_id ?? "").toLowerCase();
  const qui = await compteReconnu(jeton);
  if (!qui || !session || contenu?.sub !== qui) {
    return json({ ok: false, message: "Votre session a expiré : reconnectez-vous." }, 401);
  }

  const code = codeAuHasard();
  let inscrit: { ok?: boolean; raison?: string; attente?: number; id?: number; tel?: string } | null;
  try {
    inscrit = await rpcService("enregistrer_code_connexion",
      { qui, session, hache: await empreinte(code, session) }) as typeof inscrit;
  } catch (err) {
    console.error("code-connexion : la base ne répond pas —", (err as Error).message);
    return json({ ok: false, message: "La base ne répond pas. Réessayez dans un instant." }, 502);
  }
  if (!inscrit) {
    return json({ ok: false, message: "La base ne répond pas. Réessayez dans un instant." }, 502);
  }

  if (!inscrit.ok) {
    if (inscrit.raison === "deja_confirmee") return json({ ok: true, deja: true });
    if (inscrit.raison === "trop_tot") {
      const attente = Math.max(1, Number(inscrit.attente) || 30);
      return json({
        ok: false, raison: "trop_tot", attente,
        message: "Un code vient de partir. Attendez " + attente +
          " seconde" + (attente > 1 ? "s" : "") + " avant d'en demander un autre.",
      }, 429);
    }
    const [statut, message] = REFUS[inscrit.raison ?? ""] ??
      [400, "Le code n'a pas pu être préparé."];
    return json({ ok: false, raison: inscrit.raison ?? "", message }, statut);
  }

  const numero = String(inscrit.tel ?? "");
  const envoi = await envoyerSms(numero, messageDuCode(code));
  if (!envoi.ok) {
    /* Le SMS n'est pas parti : le code ne compte pas. Et on le JOURNALISE
       avec son code d'échec — « INSUFFICIENT_BALANCE » veut dire que plus
       personne de l'équipe ne peut entrer. */
    try {
      await rpcService("annuler_code_connexion", { code_id: inscrit.id });
    } catch (_) { /* au pire, il comptera : il expire dans dix minutes */ }
    console.error("code-connexion : envoi refusé —", envoi.code, envoi.message);
    return json({ ok: false, raison: "envoi", code: envoi.code, message: envoi.message }, 502);
  }

  /* Ni le code, ni le numéro entier dans un journal : ses lecteurs
     pourraient ouvrir une session, ou se constituer un annuaire. */
  console.log("code-connexion : code envoyé au …" + numero.slice(-4));
  return json({ ok: true, fin_numero: numero.slice(-2) });
});
