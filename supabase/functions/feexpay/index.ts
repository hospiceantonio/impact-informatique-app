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
     supabase secrets set FEEXPAY_STATUT='https://api-v2.feexpay.me/…/'
     supabase functions deploy feexpay --no-verify-jwt

   FEEXPAY_RESEAUX, facultatif, referme un reseau sans redeploiement :
     supabase secrets set FEEXPAY_RESEAUX='mtn,moov'   (Celtiis ferme)
   Absent ou vide, les trois sont ouverts.

   FEEXPAY_STATUT est l'adresse V2 qui dit ou en est un versement,
   jusqu'a la barre finale. TANT QU'ELLE MANQUE, LE PAIEMENT RESTE
   FERME — et c'est voulu : voir plus bas.

   « --no-verify-jwt » : le client d'une boutique n'est pas
   connecté à Supabase. Ce qui protège cet appel, c'est le
   NUMÉRO DE TÉLÉPHONE de la commande, vérifié en base — la
   même clé que pour « suivre_commande ».
   ========================================================= */

const JETON = Deno.env.get("FEEXPAY_TOKEN") ?? "";
const BOUTIQUE = Deno.env.get("FEEXPAY_SHOP") ?? "";
const BASE = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

/* ---------------------------------------------------------
   API V2 — la V1 a été retirée
   ---------------------------------------------------------
   Le 502 que renvoyait « api.feexpay.me » sur TOUTES ses adresses,
   y compris celle du logo, n'était pas une panne : c'est la V1 qu'ils
   ferment. Leur réponse à l'enseigne : « migrez vers api-v2 ».

   Ce que la V2 change, et rien de tout cela ne se devinait :

     1. LE NUMÉRO PORTE L'INDICATIF. « 2290197444893 » : 229 suivi du
        numéro national à dix chiffres. La V1 voulait exactement
        l'inverse — on lui RETIRAIT le 229 ;
     2. LE RÉSEAU N'EST PLUS UN CHAMP mais le dernier segment de
        l'adresse : …/requesttopay/mtn ;
     3. LE JETON NE VOYAGE PLUS DANS LE CORPS, seulement dans l'en-tête
        « Authorization ». C'est un progrès : un secret n'a rien à faire
        dans des données ;
     4. « callback_info » est une CHAÎNE, plus un objet ;
     5. « currency », « customId » et « token » ont disparu du corps ;
     6. le montant est borné : 100 minimum, 2 000 000 maximum.
   --------------------------------------------------------- */
const FEEX = "https://api-v2.feexpay.me/api/transactions/public";

/* Le dernier segment de l'adresse, un par opérateur. */
const RESEAUX: Record<string, string> = {
  MTN: "mtn",
  MOOV: "moov",
  /* « celtiis_bj », et non « celtiis » : leur documentation le donne
     ainsi. Le devinir d'après les deux autres aurait envoyé les clients
     Celtiis sur une adresse qui n'existe pas. */
  CELTIIS: "celtiis_bj",
};

/* LES RÉSEAUX OUVERTS, en une liste séparée par des virgules. Vide ou
   absent : les trois sont ouverts, et c'est le bon état par défaut.

     supabase secrets set FEEXPAY_RESEAUX='mtn,moov'

   Cela sert le jour — arrivé — où l'agrégateur casse UN opérateur et pas
   les autres. On le referme en une ligne dans le tableau de bord, sans
   redéploiement ni nouvelle version de l'application, et on le rouvre en
   effaçant le réglage. Un état temporaire appartient à la configuration,
   pas au code, où on l'oublierait. */
const OUVERTS = (Deno.env.get("FEEXPAY_RESEAUX") ?? "")
  .split(",").map((r) => r.trim().toUpperCase()).filter(Boolean);

const ouvert = (reseau: string) => OUVERTS.length === 0 || OUVERTS.includes(reseau);

/* Les préfixes béninois, tels que le SDK officiel de FeexPay les
   énumère. Ils ne servent PAS à interdire : un numéro porté d'un réseau
   à l'autre garde son préfixe d'origine, et c'est au client de savoir
   chez qui est son compte. Ils servent à EXPLIQUER un refus — « Celtiis
   BJ API Error » ne dit rien à personne, « ce numéro est un numéro
   MTN » se corrige en deux secondes. */
const PREFIXES: Record<string, string[]> = {
  MTN: ["0142", "0146", "0150", "0151", "0152", "0153", "0154", "0156", "0157",
        "0159", "0161", "0162", "0166", "0167", "0169", "0190", "0191", "0192",
        "0193", "0196", "0197"],
  MOOV: ["0145", "0155", "0158", "0160", "0163", "0164", "0165", "0168",
         "0194", "0195", "0198", "0199"],
  CELTIIS: ["0140", "0141", "0143", "0144", "0147"],
};

/** L'opérateur que suggère un numéro national, ou "" si on ne sait pas. */
function operateurDuNumero(national: string): string {
  const p = national.slice(0, 4);
  for (const nom of Object.keys(PREFIXES)) {
    if (PREFIXES[nom].includes(p)) return nom;
  }
  return "";
}

/* Leur limite, annoncée en tête de la documentation V2. La vérifier ici
   évite un refus obscur : « FeexPay a refusé » n'apprend rien à un
   client dont le panier fait 80 francs. */
const MONTANT_MIN = 100;
const MONTANT_MAX = 2000000;

/* L'adresse qui dit où en est un versement, jusqu'à la barre finale :
   la référence s'y ajoute. Elle vit dans un secret plutôt que dans ce
   fichier — le jour où FeexPay la déplace, l'enseigne la change en une
   ligne dans son tableau de bord, sans redéploiement.

   TANT QU'ELLE EST VIDE, ON N'OUVRE AUCUN PAIEMENT : encaisser sans
   pouvoir constater, c'est prendre l'argent d'un client sans jamais lui
   livrer sa commande. (V1 : /getrequesttopay/integration/ — retirée.)

     supabase secrets set FEEXPAY_STATUT='https://api-v2.feexpay.me/…/'

   Le réglage sert aussi d'INTERRUPTEUR : posé à la chaîne vide, il
   ferme le paiement en ligne sans redéploiement ni modification de
   code — utile le jour où FeexPay retirera la V2 comme il a retiré
   la V1. */
const VERIFICATION = Deno.env.get("FEEXPAY_STATUT")
  ?? "https://api-v2.feexpay.me/api/transactions/public/single/status/";

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
  /* ON N'OUVRE PAS UN PAIEMENT QU'ON NE SAURA PAS CONSTATER. Tant que
     l'adresse de vérification n'est pas connue, le client serait débité
     sans que sa commande passe jamais à « payée » : personne ne pourrait
     aller demander à FeexPay si le versement a abouti. Mieux vaut un
     paiement fermé qu'un paiement borgne. */
  if (!VERIFICATION) {
    console.error("feexpay/payer : adresse de vérification V2 inconnue");
    return repondre({
      erreur: "Le paiement en ligne est momentanément fermé, le temps de " +
              "la migration chez notre opérateur. Commandez, la boutique " +
              "vous rappellera pour le règlement.",
    }, 503);
  }

  const demande = reseau.toUpperCase();
  const reseauFeex = RESEAUX[demande];
  if (!reseauFeex) return repondre({ erreur: "Opérateur inconnu." }, 400);

  /* Un réseau refermé à la main. On ne le cache pas au client et on ne
     lui laisse pas croire qu'il a mal fait : ce n'est ni son numéro ni
     son solde, c'est notre agrégateur qui ne traite pas ce réseau en ce
     moment. On lui dit lesquels marchent. */
  if (!ouvert(demande)) {
    console.error("feexpay/payer : réseau fermé à la main", demande);
    const restants = Object.keys(RESEAUX).filter(ouvert);
    return repondre({
      erreur: "Le paiement par " + demande + " est momentanément fermé : " +
              "notre opérateur de paiement ne traite pas ce réseau en ce moment." +
              (restants.length
                ? " Essayez " + restants.join(" ou ") + ", ou commandez et la " +
                  "boutique vous rappellera."
                : " Commandez, la boutique vous rappellera pour le règlement."),
      reseaux: restants,
    }, 503);
  }

  /* LE NUMÉRO, AU FORMAT DE LA V2 : l'indicatif PUIS le national à dix
     chiffres — « 2290197444893 ». La V1 voulait le contraire. On accepte
     ce que le client tape, y compris l'ancien format à huit chiffres que
     beaucoup dictent encore, et on le ramène à cette seule forme.

     Le numéro qui PAIE peut différer de celui de la commande : on paie
     souvent avec le téléphone d'un proche. */
  let national = tel.replace(/\D/g, "").replace(/^229/, "");
  if (national.length === 8) national = "01" + national;   // avant 2023
  if (!/^01\d{8}$/.test(national)) {
    return repondre({
      erreur: "Ce numéro n'a pas la forme d'un numéro béninois : dix " +
              "chiffres commençant par 01.",
    }, 400);
  }
  const numero = "229" + national;

  /* LE MONTANT VIENT DE LA BASE. C'est tout l'intérêt de passer par ici :
     s'il venait de la requête, on paierait 100 francs une commande de
     100 000. */
  const montant = Number(commande["total"] ?? 0);
  if (!(montant > 0)) return repondre({ erreur: "Commande sans montant." }, 400);
  if (montant < MONTANT_MIN) {
    return repondre({
      erreur: "FeexPay n'encaisse pas moins de " + MONTANT_MIN + " FCFA. " +
              "Réglez cette commande directement à la boutique.",
    }, 400);
  }
  if (montant > MONTANT_MAX) {
    return repondre({
      erreur: "FeexPay n'encaisse pas plus de " + MONTANT_MAX.toLocaleString("fr-FR") +
              " FCFA en une fois. Voyez avec la boutique.",
    }, 400);
  }

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
     faire refuser la demande, et FeexPay ne disait pas pourquoi. La
     documentation V2 le dit maintenant pour TOUS les opérateurs, en
     toutes lettres : « description — Sans caractères spéciaux ».

     Le tiret est RETIRÉ, pas remplacé par une espace, comme chez eux :
     « Commande BZ000005 » se retrouve d'un bloc dans leur tableau de
     bord, « Commande BZ 000005 » non. */
  const libelle = ("Commande " + String(commande["numero"] ?? ""))
    .replace(/[^a-zA-Z0-9 ]/g, "").replace(/\s+/g, " ").trim();

  /* Les six champs de la V2, et RIEN d'autre. « token », « currency »,
     « customId » et « reseau » ont disparu du corps : le jeton vit
     désormais dans le seul en-tête — un secret n'a rien à faire dans des
     données — et l'opérateur est dans l'adresse.

     « callback_info » est une CHAÎNE en V2, plus un objet. C'est ce que
     la notification nous rendra ; on y met l'identifiant de la commande,
     mais on ne s'en servira jamais comme d'une preuve. */
  const charge: Record<string, unknown> = {
    phoneNumber: numero,
    amount: montant,
    shop: BOUTIQUE,
    description: libelle,
    callback_info: String(commande["id"] ?? ""),
    /* Leur exemple le donne toujours, et une commande BIZZOO n'exige
       qu'un numéro de téléphone : une chaîne vide dans un champ attendu
       se comporte moins bien qu'une valeur quelconque.

       NETTOYÉ COMME LE LIBELLÉ, par précaution. Leur documentation ne
       l'exige que pour « description », mais la passerelle Celtiis parle
       SOAP — leur réponse d'exemple est une enveloppe XML Huawei — et une
       apostrophe dans « N'Dah » n'a rien à faire dans du XML assemblé à
       la main. Un prénom écorné ne coûte rien : il ne sert qu'à
       l'affichage chez eux. */
    first_name: String(commande["nom"] ?? "")
      .replace(/[^a-zA-Z0-9 ]/g, "").replace(/\s+/g, " ").trim() || "Client",
  };

  /* Ce qu'on envoie. Rien de secret n'y figure depuis la V2 — le jeton
     est dans l'en-tête, et l'en-tête ne se journalise pas. Sans cette
     trace, un refus de FeexPay n'est qu'un écran rouge : ni la boutique
     ni nous ne savons ce qui a déplu. */
  console.log("feexpay/payer →", reseauFeex, JSON.stringify(charge));

  let reponse: Response;
  try {
    reponse = await fetch(FEEX + "/requesttopay/" + reseauFeex, {
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

  /* Le refus le plus fréquent, et le plus opaque : l'opérateur choisi
     n'est pas celui du numéro. FeexPay répond alors « Celtiis BJ API
     Error », ou l'équivalent, et le client n'a aucun moyen de deviner.
     On ne l'a pas empêché de choisir — la portabilité existe — mais on
     lui dit ce qu'on voit. */
  const suggere = operateurDuNumero(national);
  const desaccord = suggere && suggere !== demande
    ? " Ce numéro est un numéro " + suggere + ", alors que vous avez choisi " +
      demande + " : vérifiez l'opérateur."
    : "";

  if (!reponse.ok) {
    console.error("feexpay/payer ←", reponse.status, reseauFeex,
      desaccord ? "(opérateur en désaccord avec le numéro)" : "", texte.slice(0, 600));
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
      erreur: "FeexPay a refusé la demande." + desaccord,
      details, statut: reponse.status,
    }, 502);
  }

  /* FeexPay répond 200 même quand il refuse : c'est « status: FAILED »
     qui le dit. Leur propre SDK traduit ce cas par « le numéro entré est
     incorrect » — c'est de loin la cause la plus fréquente, et le client
     doit l'entendre plutôt que de rester devant un écran qui attend. */
  /* UN 200 QUI DIT « FAILED » EST UN REFUS DÉGUISÉ, et chez Moov c'est
     la règle plutôt que l'exception : leur documentation prévient que la
     réponse « peut déjà contenir le statut final (par exemple FAILED en
     cas de solde insuffisant), sans nécessité d'appeler l'API de
     vérification ». On ne parle donc plus d'un numéro mal saisi, qui
     enverrait le client corriger ce qui n'a rien : le solde vient
     d'abord. */
  const etatOuvert = champ(resultat, ["status", "state"]).toUpperCase();
  if (etatOuvert === "FAILED") {
    console.error("feexpay/payer ← FAILED", reseauFeex, texte.slice(0, 600));
    return repondre({
      erreur: "Le versement n'a pas pu être lancé. Vérifiez votre solde, " +
              "et que le numéro correspond bien à l'opérateur choisi." + desaccord,
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
    /* Moov répond parfois SUCCESSFUL immédiatement — « si le client
       confirme le code, la réponse sera directement SUCCESSFUL ». Lui
       dire de valider sur son téléphone serait alors absurde. On
       n'ENCAISSE toujours pas sur cette réponse : c'est la vérification,
       et elle seule, qui fera passer la commande à « payée ». */
    message: aAbouti(etatOuvert)
      ? "Versement reçu. Nous confirmons votre commande."
      : "Validez la demande sur votre téléphone.",
  });
}

/* =========================================================
   Vérifier — et c'est FeexPay qui répond, pas le téléphone
   ========================================================= */
async function verifier(commande: Record<string, unknown>) {
  if (commande["etat"] === "payee") return repondre({ etat: "payee", deja: true });

  const reference = String(commande["reference"] ?? "");
  if (!reference) return repondre({ etat: "a_payer", attente: true, raison: "aucun paiement ouvert" });

  /* Sans adresse de vérification, on ATTEND — on ne conclut rien. Une
     commande ouverte avant la migration a un versement peut-être abouti :
     la déclarer échouée effacerait un paiement réel. */
  if (!VERIFICATION) {
    console.error("feexpay/verifier : adresse de vérification V2 inconnue", reference);
    return repondre({ etat: "a_payer", attente: true, raison: "vérification non configurée" });
  }

  let reponse: Response;
  try {
    /* EN V2, CETTE LECTURE EXIGE LE JETON. En V1 elle ne demandait rien —
       on s'en félicitait même : « notre serveur vérifie sans détenir de
       secret ». Ce n'est plus vrai, et l'oublier rendrait toute
       vérification impossible sans qu'aucun paiement n'en souffre
       visiblement : les commandes resteraient simplement « à payer ». */
    reponse = await fetch(VERIFICATION + encodeURIComponent(reference), {
      headers: { "Authorization": "Bearer " + JETON },
    });
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

  /* FAILED est un verdict, pas une attente. La documentation V2 nomme les
     trois états : PENDING, SUCCESSFUL, FAILED. Laisser tourner le sablier
     quatre-vingt-dix secondes sur un refus déjà prononcé, c'est faire
     croire au client que ça peut encore aboutir. La commande, elle, ne
     bouge pas : elle reste « à payer », et il peut réessayer.

     « reason » dit souvent pourquoi — LOW_BALANCE… — mais c'est leur
     vocabulaire, pas celui d'un client : on le garde pour la boutique. */
  if (etatFeex.toUpperCase() === "FAILED") {
    console.error("feexpay/verifier ← FAILED", reference,
      champ(statut, ["reason", "responsemsg"]));
    return repondre({
      etat: "a_payer", echoue: true,
      erreur: "Le versement n'a pas abouti. Vérifiez votre solde, puis " +
              "réessayez — rien n'a été débité.",
      raison: champ(statut, ["reason", "responsemsg"]),
    });
  }

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
