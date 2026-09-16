/* =========================================================
   BIZZOO — essayer la passerelle SMS

   Un bouton dans les réglages de l'enseigne, qui envoie un vrai
   SMS à un vrai numéro. C'est le SEUL moyen de valider la clé et
   le nom d'expéditeur avant de les confier aux clients : tant
   qu'aucun SMS n'est parti pour de bon, on ne sait rien.

   DEUX CHOSES À NE PAS PERDRE DE VUE.

   1. L'ESSAI EMPRUNTE LE CHEMIN DE LA PRODUCTION. Le même
      module « _partage/sms.ts » que le hook de connexion, à la
      lettre. Une fonction d'essai plus simple, écrite à part,
      validerait un chemin que personne n'emprunte jamais.

   2. UN ENVOI COÛTE DE L'ARGENT. Contrairement à un webhook de
      paiement, cette fonction se déploie AVEC la vérification
      du jeton — et vérifie en plus, à l'intérieur, que
      l'appelant est bien le superadministrateur. Ouverte, elle
      serait une machine à vider le crédit SMS de l'enseigne.

   ---------------------------------------------------------
   Déploiement (une fois, sur votre poste)
   ---------------------------------------------------------
     supabase functions deploy tester-sms

   Sans « --no-verify-jwt » : c'est voulu, voir ci-dessus.
   ========================================================= */

import { configuration, envoyerSms, normaliserNumero } from "../_partage/sms.ts";

const BASE = Deno.env.get("SUPABASE_URL") ?? "";
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

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

/**
 * L'appelant est-il le superadministrateur ?
 *
 * On le demande À LA BASE, avec le jeton de l'appelant — jamais en
 * lisant un rôle que l'application aurait mis dans sa requête. C'est
 * « est_super() » qui décide, la même fonction que partout ailleurs.
 */
async function estSuper(jeton: string): Promise<boolean> {
  if (!jeton || !BASE || !ANON) return false;
  try {
    const reponse = await fetch(BASE + "/rest/v1/rpc/est_super", {
      method: "POST",
      headers: {
        "apikey": ANON,
        "Authorization": jeton,
        "Content-Type": "application/json",
      },
      body: "{}",
      signal: AbortSignal.timeout(10000),
    });
    if (!reponse.ok) return false;
    return (await reponse.json()) === true;
  } catch (_) {
    return false;
  }
}

Deno.serve(async (requete) => {
  /* Le back-office tourne dans un navigateur : sans réponse au contrôle
     préalable, il bloque tout SANS JAMAIS envoyer le POST, et l'appelant
     ne voit qu'une erreur réseau qui ne dit rien. Une fonction validée en
     ligne de commande peut être totalement inaccessible au navigateur. */
  if (requete.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (requete.method !== "POST") {
    return json({ ok: false, message: "Méthode non permise" }, 405);
  }

  const jeton = requete.headers.get("Authorization") ?? "";
  if (!(await estSuper(jeton))) {
    return json({ ok: false, message: "Réservé à BIZZOO." }, 403);
  }

  const corps = await requete.json().catch(() => ({})) as
    { numero?: string; message?: string };
  const numero = String(corps.numero ?? "");
  if (normaliserNumero(numero).length < 8) {
    return json({ ok: false, message: "Numéro incomplet." }, 400);
  }

  const { expediteur } = configuration();
  const texte = String(corps.message ?? "").trim() ||
    "BIZZOO : essai de la passerelle SMS. Si vous lisez ceci, tout fonctionne.";

  const envoi = await envoyerSms(numero, texte);

  /* On rend la réponse ENTIÈRE de la passerelle, pas seulement notre
     verdict. C'est ce qui permet de corriger du premier coup : un code
     « MISSING_PARAMETERS_TO » ou « INVALID_SENDERID » nomme lui-même ce
     qui manque, là où « l'envoi a échoué » ferait chercher partout. */
  return json({
    ok: envoi.ok,
    code: envoi.code,
    message: envoi.message,
    expediteur,
    destinataire: normaliserNumero(numero),
    statut_http: envoi.statutHttp,
    reponse_passerelle: envoi.brut,
  }, envoi.ok ? 200 : 502);
});
