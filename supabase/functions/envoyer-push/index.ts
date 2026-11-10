/* =========================================================
   BIZZOO — faire sonner le téléphone d'un livreur ou d'une boutique

   Une notification qui SONNE vient d'être écrite en base (course
   confiée, commande payée…) : le déclencheur « notifications_poussent »
   appelle cette fonction par pg_net, avec le seul numéro de la
   notification. La fonction :

     1. demande à la base, avec la clé de service, la notification et
        les téléphones de son destinataire (« push_a_envoyer »). La base
        la marque envoyée AU PASSAGE : un second appel — rejoué, ou
        forgé par quelqu'un qui connaîtrait l'adresse — ne rend rien,
        et rien ne part deux fois ;
     2. l'envoie à chaque téléphone par Firebase, en DONNÉES seulement :
        c'est l'application qui construit la notification, avec son son
        et le lien à ouvrir ;
     3. oublie les téléphones que Firebase ne connaît plus ;
     4. (3.80.0) l'envoie aussi, en Web Push, à chaque NAVIGATEUR abonné
        du destinataire (client sur le site, boutique ou vendeur dans le
        navigateur) — avec les clés VAPID de BIZZOO Personnel, déjà dans
        les secrets (VAPID_PUBLIQUE, VAPID_PRIVEE, VAPID_SUJET).

   RIEN DE CE QUE L'APPEL APPORTE N'EST CRU, hormis ce numéro : le
   titre, le texte, le lien et les destinataires viennent de la base.
   C'est ce qui permet de la déployer sans vérification de jeton — la
   base, qui l'appelle, n'en a pas à lui donner.

   ---------------------------------------------------------
   Déploiement (une fois)
   ---------------------------------------------------------
     supabase functions deploy envoyer-push --no-verify-jwt
   puis, dans la base :
     update public.push_reglage
        set url = 'https://<projet>.supabase.co/functions/v1/envoyer-push';
   ========================================================= */

import { envoyerAuJeton, jetonAcces, lireCompte } from "../_partage/fcm.ts";
import { type Abonnement, envoyerWebPush, lireClesVapid } from "../_partage/webpush.ts";
import { traduire } from "../_partage/langue.ts";

const BASE = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const json = (corps: unknown, statut = 200) =>
  new Response(JSON.stringify(corps), { status: statut, headers: { "Content-Type": "application/json" } });

type APousser = {
  id: number; type: string; titre: string; corps: string; lien: string;
  commande_id: string | null; jetons: string[]; application?: string; langue?: string;
  web?: Abonnement[];
};

/** Les courses sonnent jusqu'à ce qu'on les touche ; le reste, une fois. */
const COURSES = ["course_confiee", "course_proposee"];

async function base(fonction: string, corps: unknown): Promise<unknown> {
  const r = await fetch(BASE + "/rest/v1/rpc/" + fonction, {
    method: "POST",
    headers: { "apikey": SERVICE, "Authorization": "Bearer " + SERVICE, "Content-Type": "application/json" },
    body: JSON.stringify(corps),
    signal: AbortSignal.timeout(10000),
  });
  if (!r.ok) throw new Error(fonction + " : HTTP " + r.status);
  return await r.json().catch(() => null);
}

Deno.serve(async (requete) => {
  if (requete.method !== "POST") return json({ ok: false, message: "Méthode non permise" }, 405);
  const corps = await requete.json().catch(() => ({})) as { id?: unknown };
  const id = Number(corps.id);
  if (!Number.isSafeInteger(id) || id <= 0) return json({ ok: false, message: "Quelle notification ?" }, 400);
  if (!BASE || !SERVICE) return json({ ok: false, message: "Fonction mal réglée." }, 500);

  /* 1. LA BASE DIT QUOI ENVOYER, ET À QUI — une seule fois. */
  let n: APousser | null;
  try {
    n = await base("push_a_envoyer", { cible: id }) as APousser | null;
  } catch (e) {
    console.error("envoyer-push : " + String(e));
    return json({ ok: false, message: "Base injoignable." }, 502);
  }
  if (!n) return json({ ok: true, envoyees: 0, message: "Rien à envoyer." });
  const jetons = Array.isArray(n.jetons) ? n.jetons.filter((j) => typeof j === "string" && j) : [];
  const web = Array.isArray(n.web)
    ? n.web.filter((a) => a && typeof a.endpoint === "string" && a.endpoint.startsWith("https://") && a.p256dh && a.auth)
    : [];
  if (!jetons.length && !web.length) return json({ ok: true, envoyees: 0, message: "Aucun téléphone déclaré." });

  const course = COURSES.includes(n.type);
  /* (3.70.0) L'acheteur, dans l'application client : un canal à lui, qui
     sonne comme un message — pas la sonnerie insistante des courses. */
  const client = n.application === "client";
  /* (3.73.0) Dans la langue du destinataire (langues_comptes). */
  const titre = traduire(n.titre || "BIZZOO", n.langue);
  const texte = traduire(n.corps || "", n.langue);
  let envoyees = 0;
  const echecs: string[] = [];

  /* 2. FIREBASE — l'application Android. */
  if (jetons.length) {
    const compte = lireCompte();
    const acces = compte ? await jetonAcces(compte) : null;
    if (!compte) {
      console.error("envoyer-push : secret FIREBASE_COMPTE_SERVICE absent");
      echecs.push("Firebase n'est pas réglé.");
    } else if (!acces || !acces.ok) {
      console.error("envoyer-push : " + (acces ? acces.message : "accès Firebase"));
      echecs.push(acces ? acces.message : "accès Firebase");
    } else {
      const donnees: Record<string, string> = {
        type: "notification",
        genre: n.type,
        canal: client ? "client" : course ? "courses" : "commandes",
        id: String(n.id),
        titre,
        corps: texte,
        lien: n.lien || "",
        commande: n.commande_id || "",
      };
      for (const jeton of jetons) {
        const envoi = await envoyerAuJeton(compte, acces.jeton, jeton, donnees, course ? 900 : 3600);
        if (envoi.ok) { envoyees++; continue; }
        echecs.push(envoi.message);
        /* 3. UN TÉLÉPHONE QUI N'EXISTE PLUS : on l'oublie. */
        if (envoi.mort) {
          try { await base("jeton_push_mort", { jeton }); } catch (_) { /* il repartira à la prochaine */ }
        }
      }
    }
  }

  /* 4. (3.80.0) LES NAVIGATEURS — Web Push, chiffré pour chacun. C'est le
     service worker de l'application qui affiche la notification et ouvre
     le lien au toucher. */
  if (web.length) {
    const cles = lireClesVapid();
    if (!cles) {
      console.error("envoyer-push : secrets VAPID absents");
      echecs.push("Web Push n'est pas réglé.");
    } else {
      const message = { id: n.id, type: n.type, titre, corps: texte, lien: n.lien || "",
                        commande: n.commande_id || "", course };
      for (const a of web) {
        const envoi = await envoyerWebPush(cles, a, message, course ? 900 : 3600);
        if (envoi.ok) { envoyees++; continue; }
        echecs.push(envoi.message);
        if (envoi.mort) {
          try { await base("navigateur_mort", { point: a.endpoint }); } catch (_) { /* il repartira */ }
        }
      }
    }
  }
  if (echecs.length) console.error("envoyer-push(" + n.id + ") : " + echecs.join(" | "));
  return json({ ok: true, envoyees, echecs: echecs.length });
});
