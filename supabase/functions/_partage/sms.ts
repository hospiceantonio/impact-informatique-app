/* =========================================================
   BIZZOO — le transport SMS (passerelle CREATISINTER)

   Un seul module, deux appelants : le hook de Supabase Auth qui
   livre les codes de connexion, et le bouton d'essai du
   back-office. C'est VOULU, et c'est la règle la plus utile de
   ce fichier :

     LE BOUTON D'ESSAI DOIT EMPRUNTER EXACTEMENT LE CHEMIN DE LA
     PRODUCTION.

   Une petite fonction d'essai à part serait plus simple à
   écrire — et ne prouverait rien. Elle validerait un chemin que
   personne n'emprunte jamais, et le vrai envoi continuerait
   d'échouer.

   ---------------------------------------------------------
   LE PIÈGE CENTRAL : un HTTP 200 ne veut pas dire que le SMS
   est parti.
   ---------------------------------------------------------
   La passerelle répond volontiers 200 en portant l'échec DANS
   LE CORPS :

       { "status": false, "code": "INVALID_PHONE", ... }

   Se fier au code HTTP fait passer un envoi manqué pour un
   envoi réussi : le client attend un SMS qui n'arrivera jamais,
   et rien dans les journaux ne le signale. On vérifie donc les
   DEUX : « status » vrai ET un code de la liste des succès.

   ---------------------------------------------------------
   Où vit la clé
   ---------------------------------------------------------
   Dans les secrets Supabase, jamais en base et jamais dans un
   APK — même règle que le jeton FeexPay :

     supabase secrets set SMS_CLE=...
     supabase secrets set SMS_EXPEDITEUR=BIZZOO

   La table serait plus commode à modifier depuis le
   back-office ; elle serait aussi lisible dans chaque
   sauvegarde de la base, et dépendrait de règles RLS. Un secret
   est hors d'atteinte de l'API. Pour BIZZOO, où la clé ne
   changera qu'exceptionnellement, le secret gagne.
   ========================================================= */

/* L'adresse de la passerelle. Modifiable par secret : le jour où
   CREATISINTER change d'adresse, on n'a pas à redéployer. */
export const PASSERELLE =
  Deno.env.get("SMS_URL") ?? "https://sms.creatisinter.com/api/v1/sms/send";

/* Le pays par défaut. Le Bénin, ici — un numéro tapé « 0197121596 »
   part « 2290197121596 ». */
export const INDICATIF = Deno.env.get("SMS_INDICATIF") ?? "229";

/** Ce que la passerelle appelle un succès. Tout le reste est un échec. */
const CODES_SUCCES = new Set(["SUBMITTED", "SENT", "DELIVERED", "PROGRAMMED"]);

/* Les échecs qui méritent qu'on les nomme en français. Les autres
   passent tels quels : mieux vaut un code brut qu'une traduction
   approximative qui ferait chercher au mauvais endroit. */
const EXPLICATIONS: Record<string, string> = {
  INVALID_PHONE: "Numéro refusé par la passerelle.",
  INVALID_SENDERID:
    "Nom d'expéditeur non validé chez CREATISINTER. Ce n'est pas une panne : " +
    "il faut le faire valider chez eux.",
  INSUFFICIENT_BALANCE:
    "Crédit SMS épuisé. Plus aucune vérification n'aboutira tant qu'il n'est " +
    "pas rechargé.",
  AUTHENTICATION_FAILED: "Clé API refusée par la passerelle.",
  UNAUTHORIZED: "Compte CREATISINTER fermé ou restreint.",
  FORBIDDEN: "Compte CREATISINTER fermé ou restreint.",
  SUSPENDED: "Compte CREATISINTER suspendu.",
  MISSING_PARAMETERS_FROM: "La passerelle n'a pas reçu le nom d'expéditeur.",
  MISSING_PARAMETERS_TO: "La passerelle n'a pas reçu le destinataire.",
};

export type Envoi = {
  ok: boolean;
  code: string;          // le code rendu par la passerelle, ou le nôtre
  message: string;       // ce qu'on montre à un humain
  statutHttp: number;    // ce que la passerelle a répondu, pour le journal
  brut: unknown;         // sa réponse entière — l'essai la montre telle quelle
};

/**
 * Le numéro tel que la passerelle l'attend : indicatif compris, sans
 * « + » ni espaces. « 01 97 12 15 96 » → « 2290197121596 ».
 */
export function normaliserNumero(brut: string, indicatif = INDICATIF): string {
  let chiffres = String(brut ?? "").replace(/\D/g, "");
  if (!chiffres) return "";
  if (chiffres.startsWith("00")) chiffres = chiffres.slice(2);
  if (!chiffres.startsWith(indicatif)) chiffres = indicatif + chiffres;
  return chiffres;
}

/**
 * Le nom d'expéditeur, validé mais JAMAIS corrigé en silence.
 *
 * Une version précédente de ce code retirait les caractères « suspects » :
 * un nom saisi « CREATIS-SMS » partait « CREATISSMS », sans un mot — alors
 * que le tiret est parfaitement accepté, et figure dans l'exemple de la
 * documentation. Entre corriger une saisie en douce et la refuser en
 * l'expliquant, refuser gagne toujours : une valeur silencieusement
 * amputée se découvre bien plus tard, sur un symptôme sans rapport.
 *
 * On ne valide donc que ce qui est CERTAIN — la longueur, et les
 * caractères qu'aucune passerelle n'accepte. Le reste, c'est elle qui en
 * juge, et c'est à cela que sert le bouton d'essai.
 */
export function validerExpediteur(nom: string): string {
  const propre = String(nom ?? "").trim();
  if (!propre) throw new Error("Nom d'expéditeur manquant.");
  if (propre.length > 11) {
    throw new Error(
      "Nom d'expéditeur trop long (" + propre.length +
      " caractères) : onze au maximum.",
    );
  }
  if (/[\r\n\t"'\\<>]/.test(propre)) {
    throw new Error("Nom d'expéditeur : caractères interdits.");
  }
  return propre;
}

/** La configuration, lue au moment de l'envoi — jamais mise en cache. */
export function configuration() {
  const cle = (Deno.env.get("SMS_CLE") ?? "").trim();
  const expediteur = (Deno.env.get("SMS_EXPEDITEUR") ?? "BIZZOO").trim();
  return { cle, expediteur };
}

/**
 * Envoyer un SMS. C'est le seul chemin : le hook de connexion et le
 * bouton d'essai passent tous les deux par ici.
 *
 * Ne lève pas pour un refus de la passerelle — un refus est un résultat,
 * pas un accident. L'appelant lit « ok ».
 */
export async function envoyerSms(numero: string, texte: string): Promise<Envoi> {
  const { cle, expediteur } = configuration();
  if (!cle) {
    return {
      ok: false, code: "SANS_CLE", statutHttp: 0, brut: null,
      message: "La clé SMS n'est pas configurée (secret SMS_CLE).",
    };
  }

  let de: string;
  try {
    de = validerExpediteur(expediteur);
  } catch (err) {
    return {
      ok: false, code: "EXPEDITEUR_INVALIDE", statutHttp: 0, brut: null,
      message: (err as Error).message,
    };
  }

  const vers = normaliserNumero(numero);
  if (vers.length < 8) {
    return {
      ok: false, code: "NUMERO_INVALIDE", statutHttp: 0, brut: null,
      message: "Numéro incomplet.",
    };
  }
  const corps = String(texte ?? "").trim();
  if (!corps) {
    return {
      ok: false, code: "MESSAGE_VIDE", statutHttp: 0, brut: null,
      message: "Message vide : rien à envoyer.",
    };
  }

  let reponse: Response;
  try {
    reponse = await fetch(PASSERELLE, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        /* La clé part des DEUX façons dont les passerelles ont
           l'habitude. Un en-tête inconnu est ignoré partout ; deviner
           laquelle des deux c'est aurait coûté un aller-retour de plus
           avec CREATISINTER, et un « AUTHENTICATION_FAILED » qui ne
           veut rien dire. */
        "Authorization": "Bearer " + cle,
        "X-API-KEY": cle,
      },
      body: JSON.stringify({ from: de, to: vers, message: corps }),
      signal: AbortSignal.timeout(20000),
    });
  } catch (err) {
    /* Passerelle injoignable. À distinguer d'un refus : ici, réessayer
       a du sens. */
    return {
      ok: false, code: "INJOIGNABLE", statutHttp: 0, brut: null,
      message: "Passerelle SMS injoignable : " + (err as Error).message,
    };
  }

  const brut = await reponse.json().catch(() => null) as
    | { status?: boolean; code?: string; description?: string }
    | null;

  const code = String(brut?.code ?? "").toUpperCase();
  /* LES DEUX conditions. « status » seul ne suffit pas, et le code HTTP
     encore moins — voir l'en-tête de ce fichier. */
  const ok = brut?.status === true && CODES_SUCCES.has(code);

  if (ok) {
    return { ok: true, code: code || "SUBMITTED", statutHttp: reponse.status,
             brut, message: "SMS accepté par la passerelle." };
  }

  const explication = EXPLICATIONS[code];
  return {
    ok: false,
    code: code || "REFUS_SANS_CODE",
    statutHttp: reponse.status,
    brut,
    message: explication ??
      ("La passerelle a refusé l'envoi" + (code ? " (" + code + ")" : "") +
       (brut?.description ? " : " + brut.description : "") + "."),
  };
}

/* ---------- La signature de Supabase Auth ----------

   Le hook se déploie SANS vérification de jeton — son appelant est
   Supabase Auth, qui signe au lieu de porter un jeton. LA SIGNATURE EST
   DONC LE SEUL CONTRÔLE. Sans elle, n'importe qui connaissant l'adresse
   fait envoyer des SMS aux frais de l'enseigne, jusqu'à épuisement du
   crédit — et plus personne ne peut s'inscrire.

   Norme « Standard Webhooks » :
     signé = « <webhook-id>.<webhook-timestamp>.<corps> »
     signature = base64(HMAC-SHA256(secret, signé))
   Le secret du tableau de bord a la forme « v1,whsec_<base64> » ; c'est
   la partie après « whsec_ », décodée, qui sert de clé.
*/

const TOLERANCE_SECONDES = 300;

function octetsDeBase64(b64: string): Uint8Array {
  const binaire = atob(b64);
  const sortie = new Uint8Array(binaire.length);
  for (let i = 0; i < binaire.length; i++) sortie[i] = binaire.charCodeAt(i);
  return sortie;
}

function base64DOctets(octets: ArrayBuffer): string {
  return btoa(String.fromCharCode(...new Uint8Array(octets)));
}

/** Comparaison à durée constante : ne pas renseigner l'attaquant. */
function memeChaine(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let ecart = 0;
  for (let i = 0; i < a.length; i++) ecart |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return ecart === 0;
}

export type Verdict = { ok: true } | { ok: false; raison: string };

/**
 * La requête vient-elle vraiment de Supabase Auth ?
 *
 * « secret » est le secret du hook, tel que le tableau de bord le donne.
 * Absent, on REFUSE : une fonction ouverte fait envoyer des SMS à
 * n'importe qui, et un oubli de configuration doit se voir tout de
 * suite, pas se découvrir sur la facture.
 */
export async function signatureValable(
  secret: string,
  entetes: Headers,
  corps: string,
): Promise<Verdict> {
  const brut = (secret ?? "").trim();
  if (!brut) return { ok: false, raison: "secret du hook absent (SMS_HOOK_SECRET)" };

  const id = entetes.get("webhook-id") ?? "";
  const horodatage = entetes.get("webhook-timestamp") ?? "";
  const signatures = entetes.get("webhook-signature") ?? "";
  if (!id || !horodatage || !signatures) {
    return { ok: false, raison: "en-têtes de signature absents" };
  }

  /* Une signature valable reste valable pour toujours : sans cette
     fenêtre, une requête interceptée se rejoue indéfiniment. */
  const quand = Number(horodatage);
  if (!isFinite(quand)) return { ok: false, raison: "horodatage illisible" };
  const ecart = Math.abs(Math.floor(Date.now() / 1000) - quand);
  if (ecart > TOLERANCE_SECONDES) {
    return { ok: false, raison: "horodatage trop ancien (" + ecart + " s)" };
  }

  const partieSecrete = brut.includes("whsec_")
    ? brut.slice(brut.indexOf("whsec_") + "whsec_".length)
    : brut;
  let cle: CryptoKey;
  try {
    cle = await crypto.subtle.importKey(
      "raw", octetsDeBase64(partieSecrete),
      { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
    );
  } catch (_) {
    return { ok: false, raison: "secret du hook illisible" };
  }

  const attendue = base64DOctets(await crypto.subtle.sign(
    "HMAC", cle, new TextEncoder().encode(id + "." + horodatage + "." + corps),
  ));

  /* L'en-tête peut porter plusieurs signatures, séparées par des
     espaces, pour permettre une rotation du secret. Une seule qui
     corresponde suffit. */
  for (const morceau of signatures.split(" ")) {
    const virgule = morceau.indexOf(",");
    const donnee = virgule >= 0 ? morceau.slice(virgule + 1) : morceau;
    if (memeChaine(donnee, attendue)) return { ok: true };
  }
  return { ok: false, raison: "signature invalide" };
}
