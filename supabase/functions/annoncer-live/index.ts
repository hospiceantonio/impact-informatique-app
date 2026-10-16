/* =========================================================
   BIZZOO — annoncer un live TikTok

   L'administrateur d'une boutique touche « Démarrer le live TikTok »
   dans BIZZOO Admin. Cette fonction :

     1. demande à la base d'ouvrir le live, AVEC LE JETON DE
        L'APPELANT : c'est « demarrer_live » qui décide s'il en a le
        droit, si la boutique a un compte TikTok, et si ce live est
        nouveau. Rien ici ne lit un rôle venu de l'application ;
     2. si le live est NOUVEAU, envoie la notification à tous les
        téléphones (Firebase, sujet « tous »). Un live déjà en cours
        n'est pas annoncé une seconde fois ;
     3. note dans la base ce qu'a répondu Firebase.

   Sans compte de service Firebase dans les secrets, le live s'ouvre
   quand même — le bandeau « En live » de l'application le montre —,
   et la réponse dit ce qui manque.

   ---------------------------------------------------------
   Déploiement (une fois)
   ---------------------------------------------------------
     supabase functions deploy annoncer-live

   AVEC la vérification du jeton : une notification à tous les
   clients ne s'envoie pas sans être connecté.
   ========================================================= */

import { envoyerAuSujet, lireCompte, SUJET_TOUS } from "../_partage/fcm.ts";

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

type Live = { id: number; boutique: string; nom: string; lien: string; deja: boolean };

async function noter(id: number, resultat: string) {
  if (!SERVICE) return;
  try {
    await fetch(BASE + "/rest/v1/rpc/noter_annonce_live", {
      method: "POST",
      headers: { "apikey": SERVICE, "Authorization": "Bearer " + SERVICE,
        "Content-Type": "application/json" },
      body: JSON.stringify({ cible: id, resultat }),
      signal: AbortSignal.timeout(10000),
    });
  } catch (_) { /* la notification est partie ou non : la noter n'est qu'un plus */ }
}

Deno.serve(async (requete) => {
  if (requete.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (requete.method !== "POST") return json({ ok: false, message: "Méthode non permise" }, 405);

  const jeton = requete.headers.get("Authorization") ?? "";
  if (!/^Bearer\s+\S+\.\S+\.\S+/.test(jeton)) {
    return json({ ok: false, message: "Connectez-vous à BIZZOO Admin." }, 401);
  }
  const corps = await requete.json().catch(() => ({})) as { boutique?: string };
  const boutique = String(corps.boutique ?? "").trim();
  if (!boutique) return json({ ok: false, message: "Quelle boutique ?" }, 400);

  /* 1. LA BASE DÉCIDE, au nom de l'appelant. */
  let live: Live;
  try {
    const r = await fetch(BASE + "/rest/v1/rpc/demarrer_live", {
      method: "POST",
      headers: { "apikey": ANON, "Authorization": jeton, "Content-Type": "application/json" },
      body: JSON.stringify({ cible: boutique }),
      signal: AbortSignal.timeout(10000),
    });
    const d = await r.json().catch(() => null);
    if (!r.ok) {
      const message = (d && (d.message || d.hint)) || "La base refuse ce live.";
      return json({ ok: false, message }, r.status === 401 || r.status === 403 ? 403 : 400);
    }
    live = d as Live;
  } catch (_) {
    return json({ ok: false, message: "La base est injoignable. Réessayez." }, 502);
  }

  if (live.deja) {
    return json({ ok: true, deja: true, push: false, live,
      message: "Ce live est déjà annoncé : pas de seconde notification." });
  }

  /* 2. LA NOTIFICATION, si Firebase est réglé. */
  const compte = lireCompte();
  if (!compte) {
    await noter(live.id, "non envoyée : Firebase n'est pas encore réglé");
    return json({ ok: true, deja: false, push: false, live,
      message: "Live ouvert. La notification n'est pas partie : Firebase n'est pas encore " +
        "réglé (secret FIREBASE_COMPTE_SERVICE)." });
  }
  const envoi = await envoyerAuSujet(compte, SUJET_TOUS, {
    type: "live",
    id: String(live.id),
    boutique: live.boutique,
    titre: live.nom + " est en live sur TikTok",
    corps: "Touchez pour regarder le live maintenant.",
    lien: live.lien,
  });
  await noter(live.id, (envoi.ok ? "envoyée : " : "échec : ") + envoi.message);
  if (!envoi.ok) console.error("annoncer-live : " + envoi.message);

  return json({ ok: true, deja: false, push: envoi.ok, live,
    message: envoi.ok
      ? "Live annoncé : la notification part vers tous les téléphones."
      : "Live ouvert, mais la notification a échoué : " + envoi.message });
});
