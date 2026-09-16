/* =========================================================
   BIZZOO — livrer le code de connexion par SMS

   Supabase Auth sait déjà générer un code à usage unique, le
   faire expirer et le vérifier. Il ne sait pas le LIVRER : au
   Bénin, il n'a aucun opérateur. Cette fonction est le
   transporteur, et rien d'autre.

   C'est ce qui permet la connexion par numéro sans écrire une
   seule ligne de gestion de codes — ni table, ni hachage, ni
   expiration, ni compteur de tentatives. Tout cela existe déjà
   chez GoTrue, dans un schéma que l'application ne peut pas
   toucher. En réécrire une version maison ne rapporterait que
   des bugs, et une surface de plus à défendre.

   ---------------------------------------------------------
   ATTENTION — LA SIGNATURE EST LE SEUL CONTRÔLE
   ---------------------------------------------------------
   Cette fonction se déploie SANS vérification de jeton : son
   appelant est Supabase Auth, qui SIGNE sa requête au lieu de
   porter un jeton. Il n'y a donc rien d'autre entre l'Internet
   et l'envoi d'un SMS.

   Sans la signature, n'importe qui connaissant cette adresse
   fait envoyer des SMS aux frais de l'enseigne — jusqu'à
   épuisement du crédit. Et quand le crédit est épuisé, plus
   aucune vérification n'aboutit : plus personne ne peut
   s'inscrire, sans qu'aucune erreur ne se déclenche nulle part.

   D'où le refus net si « SMS_HOOK_SECRET » manque. Une fonction
   ouverte par oubli de configuration doit se voir tout de
   suite, pas se découvrir sur la facture.

   ---------------------------------------------------------
   Déploiement (une fois, sur votre poste)
   ---------------------------------------------------------
     supabase secrets set SMS_CLE=...            (clé CREATISINTER)
     supabase secrets set SMS_EXPEDITEUR=BIZZOO  (nom validé chez eux)
     supabase functions deploy hook-sms-auth --no-verify-jwt

   Puis, dans le tableau de bord :
     Authentication → Sign In / Providers → Phone : activer
     Authentication → Hooks → Send SMS hook :
       https://<projet>.supabase.co/functions/v1/hook-sms-auth
     Le tableau de bord affiche alors un secret « v1,whsec_… » :
       supabase secrets set SMS_HOOK_SECRET='v1,whsec_…'

   « --no-verify-jwt » n'est pas une négligence : sans lui,
   l'appel de Supabase Auth serait rejeté avant d'entrer ici,
   parce qu'il ne porte pas de jeton d'utilisateur. La sécurité
   est dans la signature, vérifiée trois lignes plus bas.
   ========================================================= */

import { envoyerSms, signatureValable } from "../_partage/sms.ts";

const SECRET = Deno.env.get("SMS_HOOK_SECRET") ?? "";

/* Le message. Court volontairement : un SMS long coûte deux SMS, et le
   client ne lit que les six chiffres. Le nom de l'enseigne y figure pour
   qu'on sache d'où vient le code — c'est ce qui permet de se méfier d'un
   code qu'on n'a pas demandé. */
function messageDuCode(code: string): string {
  return "BIZZOO : votre code est " + code +
    ". Il expire dans quelques minutes. Ne le communiquez a personne.";
}

Deno.serve(async (requete) => {
  if (requete.method !== "POST") {
    return new Response("Méthode non permise", { status: 405 });
  }

  /* Le corps est lu UNE fois, en texte : la signature porte sur les
     octets exacts. Le relire en JSON d'abord puis le re-sérialiser
     changerait l'espacement, et aucune signature ne correspondrait plus. */
  const corps = await requete.text();

  const verdict = await signatureValable(SECRET, requete.headers, corps);
  if (!verdict.ok) {
    console.error("hook-sms-auth : requête refusée —", verdict.raison);
    /* 401 sans détail : on ne renseigne pas qui tâtonne. Le journal, lui,
       dit tout. */
    return new Response(
      JSON.stringify({ error: { http_code: 401, message: "Non autorisé" } }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  let charge: { user?: { phone?: string }; sms?: { otp?: string } };
  try {
    charge = JSON.parse(corps);
  } catch (_) {
    return new Response(
      JSON.stringify({ error: { http_code: 400, message: "Corps illisible" } }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  const numero = String(charge?.user?.phone ?? "");
  const code = String(charge?.sms?.otp ?? "");
  if (!numero || !code) {
    return new Response(
      JSON.stringify({
        error: { http_code: 400, message: "Numéro ou code absent de la requête" },
      }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }

  const envoi = await envoyerSms(numero, messageDuCode(code));

  if (!envoi.ok) {
    /* On dit à GoTrue que l'envoi a échoué, pour qu'il le dise au client
       plutôt que de le laisser attendre un SMS qui ne viendra pas.

       Et on le JOURNALISE avec son code : « INSUFFICIENT_BALANCE » veut
       dire que plus personne ne peut s'inscrire, et cela ne se voit
       nulle part ailleurs. */
    console.error("hook-sms-auth : envoi refusé —", envoi.code, envoi.message);
    return new Response(
      JSON.stringify({ error: { http_code: 500, message: envoi.message } }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  /* Le code ne figure JAMAIS dans un journal : celui qui les lit pourrait
     valider n'importe quel numéro. On ne trace que le fait, et les quatre
     derniers chiffres du destinataire — de quoi suivre un envoi sans
     livrer un annuaire. */
  console.log("hook-sms-auth : code envoyé au …" + numero.slice(-4));
  return new Response("{}", {
    status: 200, headers: { "Content-Type": "application/json" },
  });
});
