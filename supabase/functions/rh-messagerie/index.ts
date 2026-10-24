/* =========================================================
   BIZZOO Personnel — la boîte mail professionnelle

   Chaque employé lit et écrit ses mails @bizzoomarket.com depuis
   l'application. Les boîtes sont chez LWS : IMAP pour lire
   (mail.bizzoomarket.com:993), SMTP pour envoyer (:465), tous deux
   chiffrés (TLS). Un navigateur ne sait parler ni l'un ni l'autre :
   c'est cette fonction qui le fait pour lui.

   CE QUE CETTE FONCTION GARANTIT.

   1. ON N'OUVRE QUE SA PROPRE BOÎTE. L'adresse n'est jamais lue dans
      la requête : c'est l'e-mail professionnel de la fiche de
      l'employé connecté, retrouvée par son jeton — que l'on fait
      reconnaître par GoTrue avant tout.

   2. LE MOT DE PASSE DE LA BOÎTE EST CHIFFRÉ (AES-GCM) avant d'entrer
      dans la base, avec une clé qui ne quitte pas les secrets de
      Supabase. La table « rh_boites_mail » n'a aucune règle de
      lecture : ni l'application, ni le CEO ne la lisent. Il n'est
      enregistré qu'après qu'IMAP l'a accepté.

   3. LE MOT DE PASSE NE REVIENT JAMAIS à l'application.

   ---------------------------------------------------------
   Déploiement (une fois)
   ---------------------------------------------------------
     supabase functions deploy rh-messagerie

   AVEC la vérification du jeton. Secret facultatif mais conseillé :
     RH_MESSAGERIE_CLE  — une longue phrase aléatoire. Sans elle, la
                          clé dérive de SUPABASE_SERVICE_ROLE_KEY ; la
                          changer oblige chacun à ressaisir le mot de
                          passe de sa boîte (rien d'autre n'est perdu).
   Facultatifs, si les boîtes changent d'hébergeur :
     RH_IMAP_HOTE, RH_IMAP_PORT, RH_SMTP_HOTE, RH_SMTP_PORT.
   ========================================================= */

import { ImapFlow } from "npm:imapflow@2.0.5";
import nodemailer from "npm:nodemailer@10.0.10";
import PostalMime from "npm:postal-mime@2.7.6";

const BASE = Deno.env.get("SUPABASE_URL") ?? "";
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const IMAP_HOTE = Deno.env.get("RH_IMAP_HOTE") ?? "mail.bizzoomarket.com";
const IMAP_PORT = Number(Deno.env.get("RH_IMAP_PORT") ?? "993");
const SMTP_HOTE = Deno.env.get("RH_SMTP_HOTE") ?? "mail.bizzoomarket.com";
const SMTP_PORT = Number(Deno.env.get("RH_SMTP_PORT") ?? "465");

/* Au-delà, une pièce jointe passe mal dans une réponse de fonction et
   dans la mémoire d'un téléphone : on le dit plutôt que de planter. */
const PIECE_MAX = 10 * 1024 * 1024;
const ENVOI_MAX = 15 * 1024 * 1024;

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

/** Une erreur dont le message est fait pour l'employé. */
class Refus extends Error {
  constructor(message: string, readonly code = "refus") {
    super(message);
  }
}

/* ---------- Qui appelle ---------- */

type Employe = { id: string; email_pro: string | null; nom: string; prenoms: string };

async function employeConnecte(req: Request): Promise<Employe> {
  const jeton = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jeton) throw new Refus("Connectez-vous d'abord.", "session");
  /* Le jeton est redemandé à GoTrue : on ne croit pas son contenu sur parole. */
  const r = await fetch(BASE + "/auth/v1/user", {
    headers: { apikey: ANON, Authorization: "Bearer " + jeton },
  });
  if (!r.ok) throw new Refus("Votre session a expiré : reconnectez-vous.", "session");
  const u = await r.json();
  const lignes = await service("GET",
    "rh_employes?select=id,email_pro,nom,prenoms&etat=eq.actif&compte_id=eq." + encodeURIComponent(u.id));
  const e = (lignes as Employe[])[0];
  if (!e) throw new Refus("Votre compte n'est pas celui d'un employé en poste.", "employe");
  /* Le menu Mails se ferme à un profil depuis le menu Paramètres. La base
     juge avec le jeton de l'employé : c'est son droit à lui qu'elle lit.
     Une base pas encore à jour (fonction absente) laisse passer, comme avant. */
  const acces = await fetch(BASE + "/rest/v1/rpc/rh_menu_ouvert", {
    method: "POST",
    headers: { apikey: ANON, Authorization: "Bearer " + jeton, "Content-Type": "application/json" },
    body: JSON.stringify({ cle: "mails" }),
  });
  if (acces.ok && (await acces.json()) === false) {
    throw new Refus("Le menu Mails n'est pas ouvert à votre profil.", "acces");
  }
  if (!e.email_pro) {
    throw new Refus("Votre fiche n'a pas d'adresse professionnelle : voyez l'administration.", "adresse");
  }
  return e;
}

/** La base, avec la clé de service : seule cette fonction lit les boîtes. */
async function service(methode: string, chemin: string, corps?: unknown): Promise<unknown> {
  const r = await fetch(BASE + "/rest/v1/" + chemin, {
    method: methode,
    headers: {
      apikey: SERVICE,
      Authorization: "Bearer " + SERVICE,
      "Content-Type": "application/json",
      Prefer: "resolution=merge-duplicates,return=minimal",
    },
    body: corps === undefined ? undefined : JSON.stringify(corps),
  });
  if (!r.ok) throw new Error("Base : " + r.status + " " + (await r.text()).slice(0, 200));
  return r.status === 204 || r.status === 201 ? null : await r.json();
}

/* ---------- Le chiffrement du mot de passe ---------- */

const b64 = (o: Uint8Array) => {
  let s = "";
  for (const x of o) s += String.fromCharCode(x);
  return btoa(s);
};
const deB64 = (t: string) => Uint8Array.from(atob(t), (c) => c.charCodeAt(0));

async function cle(): Promise<CryptoKey> {
  const secret = Deno.env.get("RH_MESSAGERIE_CLE") || SERVICE;
  if (!secret) throw new Error("Aucune clé de chiffrement disponible");
  const empreinte = await crypto.subtle.digest("SHA-256",
    new TextEncoder().encode("bizzoo-personnel-messagerie:" + secret));
  return crypto.subtle.importKey("raw", empreinte, "AES-GCM", false, ["encrypt", "decrypt"]);
}

async function chiffrer(texte: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const c = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await cle(),
    new TextEncoder().encode(texte));
  return { secret: b64(new Uint8Array(c)), iv: b64(iv) };
}

async function motDePasse(e: Employe): Promise<string> {
  const lignes = await service("GET",
    "rh_boites_mail?select=secret,iv&employe_id=eq." + e.id) as { secret: string; iv: string }[];
  if (!lignes.length) {
    throw new Refus("Votre boîte mail n'est pas encore reliée : saisissez son mot de passe.", "a_configurer");
  }
  try {
    const clair = await crypto.subtle.decrypt({ name: "AES-GCM", iv: deB64(lignes[0].iv) }, await cle(),
      deB64(lignes[0].secret));
    return new TextDecoder().decode(clair);
  } catch (_) {
    /* La clé a changé : le mot de passe enregistré ne se relit plus. */
    throw new Refus("Ressaisissez le mot de passe de votre boîte mail.", "a_configurer");
  }
}

/* ---------- IMAP ---------- */

function client(adresse: string, mdp: string) {
  return new ImapFlow({
    host: IMAP_HOTE,
    port: IMAP_PORT,
    secure: true,
    auth: { user: adresse, pass: mdp },
    logger: false,
    socketTimeout: 25000,
  });
}

/** Ouvre la boîte, fait le travail, referme TOUJOURS. */
async function avecBoite<T>(adresse: string, mdp: string, travail: (c: ImapFlow) => Promise<T>): Promise<T> {
  const c = client(adresse, mdp);
  try {
    await c.connect();
  } catch (err) {
    const m = String((err as Error)?.message ?? err);
    if (/auth|login|credentials|invalid/i.test(m) || (err as { authenticationFailed?: boolean })?.authenticationFailed) {
      throw new Refus("Le serveur de mail refuse ce mot de passe.", "mot_de_passe");
    }
    throw new Refus("Le serveur de mail ne répond pas. Réessayez dans un instant.", "serveur");
  }
  try {
    return await travail(c);
  } finally {
    try { await c.logout(); } catch (_) { /* déjà fermée */ }
  }
}

type Dossier = { chemin: string; nom: string; role: string; non_lus: number; total: number };

const NOMS: Record<string, string> = {
  "\\Inbox": "Boîte de réception", "\\Sent": "Envoyés", "\\Drafts": "Brouillons",
  "\\Trash": "Corbeille", "\\Junk": "Indésirables", "\\Archive": "Archives",
};
const ORDRE = ["\\Inbox", "\\Sent", "\\Drafts", "\\Archive", "\\Junk", "\\Trash", ""];

async function dossiers(c: ImapFlow): Promise<Dossier[]> {
  const liste = await c.list({ statusQuery: { messages: true, unseen: true } });
  const sortie: Dossier[] = liste
    .filter((d) => !(d.flags && d.flags.has("\\Noselect")))
    .map((d) => {
      const role = d.specialUse || (d.path.toUpperCase() === "INBOX" ? "\\Inbox" : "");
      return {
        chemin: d.path,
        nom: NOMS[role] || d.name,
        role,
        non_lus: d.status?.unseen ?? 0,
        total: d.status?.messages ?? 0,
      };
    });
  sortie.sort((a, b) => ORDRE.indexOf(a.role) - ORDRE.indexOf(b.role) || a.nom.localeCompare(b.nom, "fr"));
  return sortie;
}

async function dossierDeRole(c: ImapFlow, role: string, defaut: string): Promise<string> {
  const d = (await c.list()).find((x) => x.specialUse === role);
  return d ? d.path : defaut;
}

const adresses = (l?: { name?: string; address?: string }[]) =>
  (l ?? []).map((a) => ({ nom: a.name ?? "", adresse: a.address ?? "" }));

function aDesPieces(s: unknown): boolean {
  const n = s as { disposition?: string; childNodes?: unknown[] } | undefined;
  if (!n) return false;
  if (n.disposition === "attachment") return true;
  return (n.childNodes ?? []).some(aDesPieces);
}

async function lister(c: ImapFlow, chemin: string, page: number, parPage: number, recherche: string) {
  const verrou = await c.getMailboxLock(chemin);
  try {
    const total = (c.mailbox && typeof c.mailbox === "object") ? c.mailbox.exists : 0;
    let uids: number[];
    if (recherche) {
      uids = (await c.search({ or: [{ subject: recherche }, { from: recherche }, { body: recherche }] },
        { uid: true })) || [];
    } else {
      uids = (await c.search({ all: true }, { uid: true })) || [];
    }
    uids.sort((a, b) => b - a);
    const tranche = uids.slice(page * parPage, page * parPage + parPage);
    const messages = [];
    if (tranche.length) {
      for await (const m of c.fetch(tranche, { uid: true, envelope: true, flags: true, bodyStructure: true, size: true },
        { uid: true })) {
        messages.push({
          uid: m.uid,
          sujet: m.envelope?.subject ?? "",
          de: adresses(m.envelope?.from),
          a: adresses(m.envelope?.to),
          date: m.envelope?.date ?? null,
          lu: m.flags?.has("\\Seen") ?? false,
          suivi: m.flags?.has("\\Flagged") ?? false,
          pieces: aDesPieces(m.bodyStructure),
          taille: m.size ?? 0,
        });
      }
    }
    messages.sort((a, b) => b.uid - a.uid);
    return { total: recherche ? uids.length : total, page, par_page: parPage, messages };
  } finally {
    verrou.release();
  }
}

async function source(c: ImapFlow, uid: number): Promise<Uint8Array> {
  const m = await c.fetchOne(String(uid), { source: true }, { uid: true });
  if (!m || !m.source) throw new Refus("Ce message n'existe plus.", "introuvable");
  return new Uint8Array(m.source);
}

async function lire(c: ImapFlow, chemin: string, uid: number) {
  const verrou = await c.getMailboxLock(chemin);
  try {
    const brut = await source(c, uid);
    const m = await PostalMime.parse(brut);
    await c.messageFlagsAdd(String(uid), ["\\Seen"], { uid: true });
    return {
      uid,
      sujet: m.subject ?? "",
      de: m.from ? [{ nom: m.from.name ?? "", adresse: m.from.address ?? "" }] : [],
      a: adresses(m.to as { name?: string; address?: string }[]),
      cc: adresses(m.cc as { name?: string; address?: string }[]),
      repondre_a: adresses(m.replyTo as { name?: string; address?: string }[]),
      date: m.date ?? null,
      message_id: m.messageId ?? "",
      references: [m.inReplyTo, ...(String(m.references ?? "").split(/\s+/))].filter(Boolean),
      texte: m.text ?? "",
      // Le HTML part tel quel : l'application l'affiche dans un cadre
      // isolé, sans script ni images distantes tant qu'on ne les demande pas.
      html: m.html ?? "",
      pieces: (m.attachments ?? []).map((p, i) => ({
        index: i,
        nom: p.filename || "piece-" + (i + 1),
        type: p.mimeType || "application/octet-stream",
        taille: (p.content as ArrayBuffer)?.byteLength ?? 0,
        en_ligne: p.disposition === "inline" && !!p.contentId,
        cid: (p.contentId ?? "").replace(/^<|>$/g, ""),
      })),
    };
  } finally {
    verrou.release();
  }
}

async function piece(c: ImapFlow, chemin: string, uid: number, index: number) {
  const verrou = await c.getMailboxLock(chemin);
  try {
    const m = await PostalMime.parse(await source(c, uid));
    const p = (m.attachments ?? [])[index];
    if (!p) throw new Refus("Pièce jointe introuvable.", "introuvable");
    const octets = new Uint8Array(p.content as ArrayBuffer);
    if (octets.byteLength > PIECE_MAX) {
      throw new Refus("Cette pièce jointe dépasse 10 Mo : ouvrez-la depuis un ordinateur (webmail LWS).", "trop_lourd");
    }
    return { nom: p.filename || "piece", type: p.mimeType || "application/octet-stream", contenu: b64(octets) };
  } finally {
    verrou.release();
  }
}

/* ---------- SMTP ---------- */

type Envoi = {
  a: string[]; cc?: string[]; cci?: string[]; sujet: string; texte: string;
  pieces?: { nom: string; type: string; contenu: string }[];
  en_reponse_a?: string; references?: string[];
};

const ADRESSE = /^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$/;

function nettoyer(l?: string[]): string[] {
  const sortie = (l ?? []).map((x) => String(x).trim()).filter(Boolean);
  for (const a of sortie) {
    if (!ADRESSE.test(a)) throw new Refus("Adresse invalide : « " + a + " ».", "adresse");
  }
  return sortie;
}

async function envoyer(e: Employe, mdp: string, corps: Envoi) {
  const a = nettoyer(corps.a), cc = nettoyer(corps.cc), cci = nettoyer(corps.cci);
  if (!a.length && !cc.length && !cci.length) throw new Refus("Indiquez au moins un destinataire.", "adresse");
  if (a.length + cc.length + cci.length > 50) throw new Refus("50 destinataires au plus par message.", "adresse");
  const pieces = (corps.pieces ?? []).map((p) => ({
    filename: String(p.nom || "piece"), contentType: String(p.type || "application/octet-stream"),
    content: deB64(String(p.contenu || "")),
  }));
  const poids = pieces.reduce((s, p) => s + p.content.byteLength, 0);
  if (poids > ENVOI_MAX) throw new Refus("Les pièces jointes dépassent 15 Mo en tout.", "trop_lourd");

  const nom = (e.prenoms + " " + e.nom).trim();
  const message = {
    from: { name: nom, address: e.email_pro! },
    to: a, cc, bcc: cci,
    subject: String(corps.sujet ?? "").slice(0, 300),
    text: String(corps.texte ?? ""),
    attachments: pieces,
    inReplyTo: corps.en_reponse_a || undefined,
    references: corps.references?.length ? corps.references : undefined,
  };

  /* Le message est composé UNE fois : ce qui part et ce qu'on range
     dans « Envoyés » sont les mêmes octets. Le serveur de LWS ne range
     pas lui-même ce qui passe par SMTP. */
  const composeur = nodemailer.createTransport({ streamTransport: true, buffer: true, newline: "\r\n" });
  const compose = await composeur.sendMail({ ...message, bcc: [] });
  const brut: Uint8Array = compose.message;

  const smtp = nodemailer.createTransport({
    host: SMTP_HOTE, port: SMTP_PORT, secure: SMTP_PORT === 465,
    auth: { user: e.email_pro!, pass: mdp },
    connectionTimeout: 20000, greetingTimeout: 20000, socketTimeout: 30000,
  });
  try {
    await smtp.sendMail({
      envelope: { from: e.email_pro!, to: [...a, ...cc, ...cci] },
      raw: brut,
    });
  } catch (err) {
    const m = String((err as Error)?.message ?? err);
    if (/auth|535|credentials/i.test(m)) throw new Refus("Le serveur d'envoi refuse ce mot de passe.", "mot_de_passe");
    if (/recipient|550|553|554/i.test(m)) throw new Refus("Le serveur refuse un destinataire : " + m.slice(0, 160), "adresse");
    throw new Refus("L'envoi a échoué : " + m.slice(0, 160), "serveur");
  }

  /* Ranger dans « Envoyés » : un échec ici ne rend pas l'envoi faux. */
  let range = true;
  try {
    await avecBoite(e.email_pro!, mdp, async (c) => {
      const envoyes = await dossierDeRole(c, "\\Sent", "INBOX.Sent");
      await c.append(envoyes, brut, ["\\Seen"]);
    });
  } catch (_) {
    range = false;
  }
  return { envoye: true, range_dans_envoyes: range };
}

/* ---------- La porte d'entrée ---------- */

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, message: "POST seulement" }, 405);
  let corps: Record<string, unknown>;
  try {
    corps = await req.json();
  } catch (_) {
    return json({ ok: false, message: "Requête illisible" }, 400);
  }
  const action = String(corps.action ?? "");
  try {
    const e = await employeConnecte(req);
    const adresse = e.email_pro!;

    if (action === "etat") {
      const l = await service("GET", "rh_boites_mail?select=enregistre_le&employe_id=eq." + e.id) as unknown[];
      return json({ ok: true, email: adresse, configuree: l.length > 0 });
    }

    if (action === "enregistrer") {
      const mdp = String(corps.mot_de_passe ?? "");
      if (!mdp) throw new Refus("Saisissez le mot de passe de votre boîte.", "mot_de_passe");
      // On n'enregistre qu'un mot de passe que le serveur a accepté.
      await avecBoite(adresse, mdp, async () => null);
      const { secret, iv } = await chiffrer(mdp);
      await service("POST", "rh_boites_mail?on_conflict=employe_id",
        { employe_id: e.id, secret, iv, enregistre_le: new Date().toISOString() });
      return json({ ok: true, email: adresse, configuree: true });
    }

    if (action === "oublier") {
      await service("DELETE", "rh_boites_mail?employe_id=eq." + e.id);
      return json({ ok: true, configuree: false });
    }

    const mdp = await motDePasse(e);
    const chemin = String(corps.dossier ?? "INBOX");
    const uid = Number(corps.uid ?? 0);

    switch (action) {
      case "dossiers":
        return json({ ok: true, email: adresse, dossiers: await avecBoite(adresse, mdp, dossiers) });
      case "lister": {
        const page = Math.max(0, Number(corps.page ?? 0) | 0);
        const parPage = Math.min(50, Math.max(5, Number(corps.par_page ?? 25) | 0));
        const recherche = String(corps.recherche ?? "").trim().slice(0, 100);
        return json({ ok: true, ...(await avecBoite(adresse, mdp, (c) => lister(c, chemin, page, parPage, recherche))) });
      }
      case "lire":
        return json({ ok: true, message: await avecBoite(adresse, mdp, (c) => lire(c, chemin, uid)) });
      case "piece":
        return json({ ok: true, piece: await avecBoite(adresse, mdp, (c) => piece(c, chemin, uid, Number(corps.index ?? -1))) });
      case "marquer":
        await avecBoite(adresse, mdp, async (c) => {
          const v = await c.getMailboxLock(chemin);
          try {
            if (corps.lu) await c.messageFlagsAdd(String(uid), ["\\Seen"], { uid: true });
            else await c.messageFlagsRemove(String(uid), ["\\Seen"], { uid: true });
          } finally { v.release(); }
        });
        return json({ ok: true });
      case "supprimer":
        await avecBoite(adresse, mdp, async (c) => {
          const corbeille = await dossierDeRole(c, "\\Trash", "INBOX.Trash");
          const v = await c.getMailboxLock(chemin);
          try {
            // Déjà dans la corbeille : effacé pour de bon ; sinon, mis à la corbeille.
            if (chemin === corbeille) await c.messageDelete(String(uid), { uid: true });
            else await c.messageMove(String(uid), corbeille, { uid: true });
          } finally { v.release(); }
        });
        return json({ ok: true });
      case "envoyer":
        return json({ ok: true, ...(await envoyer(e, mdp, corps as unknown as Envoi)) });
      default:
        return json({ ok: false, message: "Action inconnue" }, 400);
    }
  } catch (err) {
    if (err instanceof Refus) return json({ ok: false, code: err.code, message: err.message });
    console.error("rh-messagerie", action, err);
    return json({ ok: false, code: "erreur", message: "La messagerie a rencontré un problème. Réessayez." });
  }
});
