/* =========================================================
   BIZZOO — prévenir par SMS un client que l'application ne touche pas

   Une étape de sa commande vient de passer (payée, livreur en route,
   livrée…) et la base a écrit un SMS dans « sms_commandes » : le
   déclencheur « sms_commandes_partent » appelle cette fonction par
   pg_net, avec le seul numéro de la ligne. La fonction :

     1. demande à la base, avec la clé de service, le numéro et le texte
        (« sms_a_envoyer »). La base le marque « en cours » AU PASSAGE :
        un second appel — rejoué, ou forgé par quelqu'un qui connaîtrait
        l'adresse — ne rend rien, et rien ne part deux fois ;
     2. l'envoie par la passerelle CREATISINTER (_partage/sms.ts, le même
        chemin que le code de connexion) ;
     3. rend le verdict à la base (« sms_resultat ») : envoyé, refusé, ou
        à réessayer si la passerelle était injoignable.

   RIEN DE CE QUE L'APPEL APPORTE N'EST CRU, hormis ce numéro de ligne :
   le destinataire et le texte viennent de la base. C'est ce qui permet
   de la déployer sans vérification de jeton.

   ---------------------------------------------------------
   Déploiement (une fois)
   ---------------------------------------------------------
     supabase functions deploy envoyer-sms-commande --no-verify-jwt
   puis, dans la base :
     update public.sms_reglages
        set url = 'https://<projet>.supabase.co/functions/v1/envoyer-sms-commande';
   Les secrets SMS_CLE et SMS_EXPEDITEUR sont ceux du code de connexion.
   ========================================================= */

import { envoyerSms } from "../_partage/sms.ts";

const BASE = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const json = (corps: unknown, statut = 200) =>
  new Response(JSON.stringify(corps), { status: statut, headers: { "Content-Type": "application/json" } });

type AEnvoyer = { id: number; numero: string; texte: string };

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
  if (!Number.isSafeInteger(id) || id <= 0) return json({ ok: false, message: "Quel SMS ?" }, 400);
  if (!BASE || !SERVICE) return json({ ok: false, message: "Fonction mal réglée." }, 500);

  /* 1. LA BASE DIT QUOI ENVOYER, ET À QUI — une seule fois. */
  let s: AEnvoyer | null;
  try {
    s = await base("sms_a_envoyer", { cible: id }) as AEnvoyer | null;
  } catch (e) {
    console.error("envoyer-sms-commande : " + String(e));
    return json({ ok: false, message: "Base injoignable." }, 502);
  }
  if (!s || !s.numero || !s.texte) return json({ ok: true, envoye: false, message: "Rien à envoyer." });

  /* 2. LA PASSERELLE. Le numéro arrive complet, indicatif compris : on
     n'ajoute rien devant (indicatif vide). */
  const envoi = await envoyerSms(s.numero, s.texte, "");

  /* 3. LE VERDICT, rendu à la base — trois essais : un verdict perdu
     laisse la ligne « en cours », et elle ne repartira JAMAIS (elle est
     peut-être partie). Le journal ne garde jamais le numéro entier : ses
     quatre derniers chiffres suffisent à le reconnaître. */
  const verdict = {
    cible: s.id, ok: envoi.ok, code: envoi.code, statut_http: envoi.statutHttp,
    message: envoi.ok ? "" : envoi.message,
  };
  for (let essai = 1; essai <= 3; essai++) {
    try {
      await base("sms_resultat", verdict);
      break;
    } catch (e) {
      if (essai === 3) {
        console.error("envoyer-sms-commande(" + s.id + ") : verdict non rendu — " + String(e));
      } else {
        await new Promise((r) => setTimeout(r, 500 * essai));
      }
    }
  }
  if (!envoi.ok) {
    console.error("envoyer-sms-commande(" + s.id + ", …" + s.numero.slice(-4) + ") : " + envoi.code + " — " + envoi.message);
  }
  return json({ ok: true, envoye: envoi.ok, code: envoi.code });
});
