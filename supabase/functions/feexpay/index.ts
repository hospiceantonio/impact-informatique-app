/* =========================================================
   BIZZOO — encaissement FeexPay

   FeexPay ne marche pas comme KkiaPay, et tout ce fichier
   découle de deux constats tirés de LEUR PROPRE SDK officiel
   (@feexpay/react-sdk 1.5.8) :

   1. IL N'Y A AUCUNE NOTIFICATION SIGNÉE. Rien qu'un
      « callback_url », c'est-à-dire une redirection de
      navigateur — donc fabriquée chez le client, donc
      falsifiable. On ne peut pas s'y fier pour encaisser.

   2. LEUR JETON EST UN SECRET PORTEUR. Leur SDK le met dans
      le navigateur ; leur propre README dit pourtant de ne
      jamais exposer un jeton sensible. Dans un APK, il se lit
      en clair.

   Alors on inverse le sens : c'est NOTRE serveur qui ouvre le
   paiement (le jeton ne quitte jamais les secrets Supabase),
   reçoit une RÉFÉRENCE, puis va DEMANDER À FEEXPAY si le
   versement a abouti. La réponse de FeexPay décide. Celle du
   téléphone n'est qu'une invitation à aller regarder.

   La règle de BIZZOO ne bouge donc pas d'un pouce :
   L'APPLICATION NE DÉCLARE JAMAIS UN PAIEMENT. Elle attend.

   ---------------------------------------------------------
   PAS DE BAC À SABLE ICI, ET C'EST VOULU
   ---------------------------------------------------------
   Le SDK de FeexPay, en mode « SANDBOX », n'appelle pas leur
   API du tout : il renvoie un succès écrit en dur.

       if (mode === "SANDBOX")
         return { status: "SUCCESSFUL", ... };

   Reproduire cela ici rouvrirait exactement la porte qu'on
   passe le projet entier à fermer : il suffirait de demander
   le mode test pour être déclaré payé. Cette fonction n'a
   donc pas de mode test. Éprouvez avec un petit montant réel.

   ---------------------------------------------------------
   Déploiement (une fois, sur votre poste)
   ---------------------------------------------------------
     supabase secrets set FEEXPAY_TOKEN='fp_votre_jeton'
     supabase secrets set FEEXPAY_SHOP='identifiant-de-boutique'
     supabase functions deploy feexpay --no-verify-jwt

   « --no-verify-jwt » : le client d'une boutique n'est pas
   connecté à Supabase. Ce qui protège cet appel, c'est le
   NUMÉRO DE TÉLÉPHONE de la commande, vérifié en base — la
   même clé que pour « suivre_commande ».
   ========================================================= */

const JETON = Deno.env.get("FEEXPAY_TOKEN") ?? "";
const BOUTIQUE = Deno.env.get("FEEXPAY_SHOP") ?? "";
const BASE = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const FEEX = "https://api.feexpay.me/api/transactions";

/* Le nom que FeexPay donne à chaque opérateur. « CELTIIS BJ » avec son
   espace n'est pas une coquette : c'est la valeur qu'attend leur API. */
const RESEAUX: Record<string, string> = {
  MTN: "MTN",
  MOOV: "MOOV",
  CELTIIS: "CELTIIS BJ",
};

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const repondre = (corps: Record<string, unknown>, statut = 200) =>
  new Response(JSON.stringify(corps), {
    status: statut,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

/** Un appel à notre propre base, avec les droits du service. */
async function rpc(nom: string, parametres: Record<string, unknown>): Promise<unknown> {
  const reponse = await fetch(BASE + "/rest/v1/rpc/" + nom, {
    method: "POST",
    headers: {
      "apikey": SERVICE,
      "Authorization": "Bearer " + SERVICE,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(parametres),
  });
  if (!reponse.ok) throw new Error("base : " + (await reponse.text().catch(() => "")));
  return await reponse.json().catch(() => null);
}

/** Le premier des noms possibles qui porte quelque chose. */
function champ(objet: Record<string, unknown>, noms: string[]): string {
  for (const nom of noms) {
    const v = objet[nom];
    if (typeof v === "string" && v.trim()) return v.trim();
    if (typeof v === "number") return String(v);
  }
  return "";
}

/** Le versement a-t-il abouti ? FeexPay dit SUCCESSFUL, parfois SUCCESS. */
function aAbouti(etat: string): boolean {
  const e = etat.toUpperCase();
  return e === "SUCCESSFUL" || e === "SUCCESS";
}

/* =========================================================
   Ouvrir le paiement
   ========================================================= */
async function payer(commande: Record<string, unknown>, tel: string, reseau: string) {
  const reseauFeex = RESEAUX[reseau.toUpperCase()];
  if (!reseauFeex) return repondre({ erreur: "Opérateur inconnu." }, 400);

  /* Le numéro qui PAIE peut différer de celui de la commande : on paie
     souvent avec le téléphone d'un proche. On le nettoie, sans plus. */
  const numero = tel.replace(/\D/g, "").replace(/^229/, "");
  if (numero.length < 8) return repondre({ erreur: "Numéro de paiement incomplet." }, 400);

  /* LE MONTANT VIENT DE LA BASE. C'est tout l'intérêt de passer par ici :
     s'il venait de la requête, on paierait 100 francs une commande de
     100 000. */
  const montant = Number(commande["total"] ?? 0);
  if (!(montant > 0)) return repondre({ erreur: "Commande sans montant." }, 400);

  /* LE FREIN, AVANT d'appeler FeexPay. Chaque demande fait sonner un
     téléphone : le vérifier après coup laisserait la sonnerie partir, et
     on ne s'en apercevrait qu'en rangeant la référence. La base garde le
     même frein de son côté — celui-ci n'est qu'une politesse pour
     répondre clairement. */
  const derniere = commande["tentative_le"];
  if (derniere) {
    const depuis = Date.now() - new Date(String(derniere)).getTime();
    if (depuis >= 0 && depuis < 30000) {
      return repondre({
        erreur: "Une demande de paiement vient de partir sur ce numéro. " +
                "Regardez votre téléphone, ou patientez un instant avant de réessayer.",
        patienter: Math.ceil((30000 - depuis) / 1000),
      }, 429);
    }
  }

  /* LE LIBELLÉ NE PORTE QUE DES LETTRES, DES CHIFFRES ET DES ESPACES.
     Ce n'est pas une coquetterie : leur propre SDK le nettoie avant
     d'appeler l'API, et pour MTN précisément —

         if (network === "MTN")
           description = description.replace(/[^a-zA-Z0-9 ]/g, "");

     Or nos commandes s'appellent « BZ-000005 ». Le tiret suffisait à
     faire refuser la demande, et FeexPay ne disait pas pourquoi. On
     nettoie pour tous les opérateurs : un libellé sans ponctuation ne
     coûte rien, et ce qui vaut pour MTN vaut probablement ailleurs. */
  const libelle = ("Commande " + String(commande["numero"] ?? ""))
    .replace(/[^a-zA-Z0-9 ]/g, " ").replace(/\s+/g, " ").trim();

  /* Les champs sont ceux de LEUR SDK (@feexpay/react-sdk 1.5.8), moins
     ceux qui n'ont de sens que dans un navigateur : merchant_domain,
     merchant_ip, payment_interface. Un serveur n'a pas d'origine de page,
     et déclarer « REACT » serait faux.

     « email » n'est ajouté que s'il porte quelque chose : une chaîne vide
     dans un champ facultatif se comporte moins bien qu'un champ absent,
     c'est un piège connu chez leur concurrent. */
  const charge: Record<string, unknown> = {
    phoneNumber: numero,
    amount: montant,
    reseau: reseauFeex,
    shop: BOUTIQUE,
    token: JETON,
    currency: "XOF",
    /* Notre référence part des deux côtés : FeexPay nous la rendra,
       et elle nous permet de recoller le versement à la commande. */
    customId: String(commande["id"] ?? ""),
    callback_info: { commande: String(commande["id"] ?? "") },
    description: libelle,
    /* Toujours porteur : leur SDK envoie ce champ à chaque appel, et une
       commande BIZZOO n'exige qu'un numéro de téléphone. */
    first_name: String(commande["nom"] ?? "").trim() || "Client",
  };

  /* Ce qu'on envoie, JETON RETIRÉ. Sans cette trace, un refus de FeexPay
     n'est qu'un écran rouge : ni la boutique ni nous ne savons ce qui a
     déplu, et il ne reste qu'à deviner. */
  console.log("feexpay/payer →", JSON.stringify({ ...charge, token: "***" }));

  let reponse: Response;
  try {
    reponse = await fetch(FEEX + "/requesttopay/integration", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer " + JETON,
      },
      body: JSON.stringify(charge),
    });
  } catch (_) {
    /* Injoignable n'est pas « refusé ». Rien n'a été engagé. */
    console.error("feexpay/payer : injoignable");
    return repondre({ erreur: "FeexPay est injoignable. Réessayez dans un instant." }, 503);
  }

  /* On lit le texte, pas le JSON : quand FeexPay refuse, il lui arrive de
     répondre en clair, et un « .json() » raté effacerait justement la
     phrase qui explique le refus. */
  const texte = await reponse.text().catch(() => "");
  let resultat: Record<string, unknown> = {};
  try { resultat = JSON.parse(texte) as Record<string, unknown>; } catch (_) { /* tant pis */ }

  if (!reponse.ok) {
    console.error("feexpay/payer ←", reponse.status, texte.slice(0, 600));
    const details = champ(resultat, ["message", "reason", "error", "detail", "description"])
                    || texte.slice(0, 200);

    /* UNE PANNE CHEZ EUX N'EST PAS UN REFUS, et les confondre coûte cher.
       Un refus dit « ce numéro ne va pas » : il appelle une correction.
       Une panne n'appelle que de la patience. En affichant « FeexPay a
       refusé la demande » sur un 502, on envoie le client vérifier un
       numéro qui n'a rien, et la boutique douter d'identifiants qui sont
       bons. Rien n'a été engagé dans un cas comme dans l'autre : la
       référence n'est notée qu'après une réponse valable, donc le frein
       des trente secondes n'est pas entamé et on peut réessayer tout de
       suite. */
    if (reponse.status >= 500) {
      return repondre({
        erreur: "FeexPay ne répond pas correctement en ce moment. Rien n'a été " +
                "débité, et vous pouvez réessayer dans quelques minutes.",
        details, statut: reponse.status,
      }, 503);
    }
    if (reponse.status === 429) {
      return repondre({
        erreur: "FeexPay a reçu trop de demandes à la fois. Réessayez dans un instant.",
        details, statut: reponse.status,
      }, 429);
    }
    return repondre({
      erreur: "FeexPay a refusé la demande.", details, statut: reponse.status,
    }, 502);
  }

  /* FeexPay répond 200 même quand il refuse : c'est « status: FAILED »
     qui le dit. Leur propre SDK traduit ce cas par « le numéro entré est
     incorrect » — c'est de loin la cause la plus fréquente, et le client
     doit l'entendre plutôt que de rester devant un écran qui attend. */
  if (champ(resultat, ["status", "state"]).toUpperCase() === "FAILED") {
    console.error("feexpay/payer ← FAILED", texte.slice(0, 600));
    return repondre({
      erreur: "Ce numéro n'a pas été accepté. Vérifiez-le, et qu'il " +
              "correspond bien à l'opérateur choisi.",
      details: champ(resultat, ["message", "reason", "error", "detail"]),
    }, 400);
  }

  const reference = champ(resultat, ["reference", "transaction_id", "id"]);
  if (!reference) {
    console.error("feexpay/payer ← sans référence", texte.slice(0, 600));
    return repondre({ erreur: "FeexPay n'a pas renvoyé de référence." }, 502);
  }
  console.log("feexpay/payer ← ouvert", reference);

  /* On range la référence AVANT de répondre : c'est elle qui permettra
     de vérifier. Si l'écriture échoue, le client ne doit pas croire que
     le paiement est en cours — il le serait sans qu'on puisse le
     constater. */
  try {
    const note = await rpc("noter_reference", { cible: commande["id"], reference });
    if (note !== true) {
      return repondre({ erreur: "Référence de paiement non enregistrée. Ne payez pas, réessayez." }, 500);
    }
  } catch (_) {
    return repondre({ erreur: "Référence de paiement non enregistrée. Ne payez pas, réessayez." }, 500);
  }

  return repondre({
    ouvert: true,
    reference,
    /* La page hébergée, quand FeexPay en renvoie une (carte bancaire). */
    page: champ(resultat, ["payment_url"]) || null,
    message: "Validez la demande sur votre téléphone.",
  });
}

/* =========================================================
   Vérifier — et c'est FeexPay qui répond, pas le téléphone
   ========================================================= */
async function verifier(commande: Record<string, unknown>) {
  if (commande["etat"] === "payee") return repondre({ etat: "payee", deja: true });

  const reference = String(commande["reference"] ?? "");
  if (!reference) return repondre({ etat: "a_payer", attente: true, raison: "aucun paiement ouvert" });

  let reponse: Response;
  try {
    /* Cette lecture ne demande aucune authentification chez FeexPay.
       Tant mieux : notre serveur vérifie sans détenir de secret. */
    reponse = await fetch(FEEX + "/getrequesttopay/integration/" + encodeURIComponent(reference));
  } catch (_) {
    /* Un délai dépassé n'est PAS un échec : le versement a peut-être
       abouti. On ne marque JAMAIS « échoué » sur une panne de réseau. */
    return repondre({ etat: "a_payer", attente: true, raison: "FeexPay injoignable" });
  }

  if (!reponse.ok) {
    /* On attend, on ne conclut pas : une panne chez eux ne dit rien du
       versement, qui a peut-être abouti. Mais on la note — sans trace,
       une commande qui reste « à payer » pendant que FeexPay tousse
       ressemble à un client qui n'a pas payé. */
    console.error("feexpay/verifier ←", reponse.status, reference);
    return repondre({ etat: "a_payer", attente: true, raison: "statut illisible" });
  }
  const statut = await reponse.json().catch(() => ({})) as Record<string, unknown>;

  const etatFeex = champ(statut, ["status", "state"]);
  if (!aAbouti(etatFeex)) {
    return repondre({ etat: "a_payer", attente: true, statut: etatFeex || "PENDING" });
  }

  /* Abouti, oui — mais de combien ? FeexPay ne renvoie pas toujours le
     montant. Sans lui, on ne PEUT PAS vérifier qu'il couvre la commande,
     et on ne valide donc pas : la boutique tranchera à la main, avec la
     référence sous les yeux. Valider sans montant reviendrait à croire
     sur parole qu'un versement quelconque règle cette commande-ci. */
  const brut = champ(statut, ["amount", "montant"]);
  if (!brut) {
    return repondre({
      etat: "a_payer", attente: true,
      raison: "FeexPay annonce un succès sans montant : à confirmer par la boutique",
      reference,
    });
  }

  const resultat = await rpc("marquer_payee", {
    reference: commande["id"],
    transaction: reference,
    montant: Math.round(Number(brut)),
  }) as Record<string, unknown>;

  return repondre({ etat: resultat?.["deja"] || resultat?.["numero"] ? "payee" : "a_payer",
                    resultat });
}

/* ========================================================= */
Deno.serve(async (requete: Request): Promise<Response> => {
  if (requete.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (requete.method !== "POST") return repondre({ erreur: "méthode" }, 405);

  if (!JETON || !BOUTIQUE || !BASE || !SERVICE) {
    return repondre({ erreur: "Le paiement FeexPay n'est pas configuré." }, 500);
  }

  let corps: Record<string, unknown>;
  try {
    corps = await requete.json();
  } catch (_) {
    return repondre({ erreur: "corps illisible" }, 400);
  }

  const action = String(corps["action"] ?? "");
  const cible = String(corps["commande"] ?? "");
  const tel = String(corps["tel"] ?? "");

  /* Le numéro de la commande fait office de mot de passe. Sans lui,
     n'importe qui ferait sonner le téléphone d'un inconnu avec une
     demande de paiement, ou lirait où en sont ses commandes. */
  let commande: Record<string, unknown> | null;
  try {
    commande = await rpc("commande_pour_paiement", { cible, tel }) as Record<string, unknown> | null;
  } catch (_) {
    return repondre({ erreur: "Base injoignable." }, 503);
  }
  if (!commande) return repondre({ erreur: "Commande introuvable." }, 404);

  if (action === "verifier") return await verifier(commande);

  if (action === "payer") {
    if (commande["etat"] !== "a_payer") {
      return repondre({ etat: commande["etat"], deja: true });
    }
    return await payer(commande, String(corps["numero"] ?? tel), String(corps["reseau"] ?? ""));
  }

  return repondre({ erreur: "action inconnue" }, 400);
});
