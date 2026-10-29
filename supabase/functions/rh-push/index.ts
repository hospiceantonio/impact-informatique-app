/* =========================================================
   BIZZOO Personnel — faire sonner le téléphone d'un employé

   Une tâche nouvelle (ou une escalade) vient d'être notée pour un
   employé dans « rh_alertes_envoyees » : pg_cron, par
   « rh_pousser_alertes », appelle cette fonction avec le seul numéro
   de l'envoi. La fonction :

     1. demande à la base, avec la clé de service, le message et les
        téléphones abonnés de cet employé (« rh_push_a_envoyer »). La
        base le marque parti AU PASSAGE : un second appel — rejoué, ou
        forgé par quelqu'un qui connaîtrait l'adresse — ne rend rien ;
     2. l'envoie à chaque navigateur en Web Push, chiffré pour lui ;
        c'est le service worker de Personnel qui affiche la
        notification et ouvre « Ma file » au toucher ;
     3. oublie les abonnements que le service de push ne connaît plus.

   RIEN DE CE QUE L'APPEL APPORTE N'EST CRU, hormis ce numéro : le
   titre, le texte, le lien et les destinataires viennent de la base,
   et la base n'y met ni montant ni nom de client. C'est ce qui
   permet de la déployer sans vérification de jeton.

   Elle ne touche ni à « envoyer-push » ni à « appareils_push » :
   les notifications de BIZZOO Admin et du client restent ce qu'elles
   sont.

   ---------------------------------------------------------
   Déploiement (une fois)
   ---------------------------------------------------------
     node tools/vapid-cles.mjs        (sur le PC : fabrique les clés)
     secrets : VAPID_PUBLIQUE, VAPID_PRIVEE, VAPID_SUJET (mailto:…)
     supabase functions deploy rh-push --no-verify-jwt
   puis, dans la base :
     update public.rh_push_reglage
        set url = 'https://<projet>.supabase.co/functions/v1/rh-push',
            cle_publique = '<VAPID_PUBLIQUE>';
   ========================================================= */

import { type Abonnement, envoyerWebPush, lireClesVapid } from "../_partage/webpush.ts";

const BASE = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const json = (corps: unknown, statut = 200) =>
  new Response(JSON.stringify(corps), { status: statut, headers: { "Content-Type": "application/json" } });

type APousser = { id: number; titre: string; corps: string; lien: string; tache?: string; abonnements: Abonnement[] };

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
  if (!Number.isSafeInteger(id) || id <= 0) return json({ ok: false, message: "Quel envoi ?" }, 400);
  if (!BASE || !SERVICE) return json({ ok: false, message: "Fonction mal réglée." }, 500);

  /* Les clés d'abord : sans elles, on ne consomme pas l'envoi (il
     resterait marqué parti sans être parti) ; « rh_pousser_alertes » le
     rappelle toutes les cinq minutes pendant une heure. */
  const cles = lireClesVapid();
  if (!cles) {
    console.error("rh-push : secrets VAPID_PUBLIQUE, VAPID_PRIVEE ou VAPID_SUJET absents");
    return json({ ok: false, message: "Les clés VAPID ne sont pas réglées." }, 500);
  }

  /* 1. LA BASE DIT QUOI ENVOYER, ET À QUI — une seule fois. */
  let n: APousser | null;
  try {
    n = await base("rh_push_a_envoyer", { cible: id }) as APousser | null;
  } catch (e) {
    console.error("rh-push : " + String(e));
    return json({ ok: false, message: "Base injoignable." }, 502);
  }
  if (!n) return json({ ok: true, envoyees: 0, message: "Rien à envoyer." });
  const abonnements = Array.isArray(n.abonnements)
    ? n.abonnements.filter((a) => a && typeof a.endpoint === "string" && a.endpoint.startsWith("https://"))
    : [];
  if (!abonnements.length) return json({ ok: true, envoyees: 0, message: "Aucun téléphone abonné." });

  /* 2. LE WEB PUSH. */
  /* « tache » : l'étiquette de la notification — les alertes d'une même
     tâche se remplacent sur le téléphone au lieu de s'empiler. */
  const donnees = { titre: n.titre || "BIZZOO Personnel", corps: n.corps || "", lien: n.lien || "#/file", id: n.id,
                    tache: n.tache || "" };
  let envoyees = 0;
  const echecs: string[] = [];
  for (const a of abonnements) {
    const envoi = await envoyerWebPush(cles, a, donnees);
    if (envoi.ok) { envoyees++; continue; }
    echecs.push(envoi.message);
    /* 3. UN ABONNEMENT QUI N'EXISTE PLUS : on l'oublie. */
    if (envoi.mort) {
      try { await base("rh_push_abonnement_mort", { v_endpoint: a.endpoint }); } catch (_) { /* il repartira */ }
    }
  }
  if (echecs.length) console.error("rh-push(" + n.id + ") : " + echecs.join(" | "));
  return json({ ok: true, envoyees, echecs: echecs.length });
});
