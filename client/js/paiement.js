/* =========================================================
   Paiement — commander, puis payer l'acompte par Mobile Money.

   Ce qui se joue ici tient en une phrase : CE FICHIER NE DÉCIDE
   RIEN. Il demande à la base de créer la commande — c'est elle
   qui relit les prix et annonce le montant —, il ouvre la page
   de paiement de KkiaPay, puis il ATTEND que la base dise
   « payée ». Il ne l'annonce jamais de lui-même.

   La raison : tout ce fichier tourne sur le téléphone du
   client, donc n'importe qui peut le modifier. Si l'application
   disait « c'est payé », il suffirait de le lui faire dire.
   Seul KkiaPay, qui détient le secret du webhook, peut valider
   un encaissement (voir supabase/functions/kkiapay-webhook).

   Aucune clé privée ici : la clé publique est faite pour être
   publique, et elle est lue en base — on passe du bac à sable à
   la production sans reconstruire l'application.
   ========================================================= */
const Paiement = (() => {

  const SCRIPT = "https://cdn.kkiapay.me/k.js";
  const ATTENTE_MAX = 90000;    // 1 min 30 : le bac à sable prend son temps
  const INTERVALLE = 3000;

  let reglages = null;          // { actif, fournisseur, clePublique, bacASable, tauxAcompte, livraison }
  const CLE_DESTINATION = "bizzoo-destination";
  let widgetCharge = null;      // promesse de chargement du script
  let enCours = null;           // la promesse du paiement ouvert

  /* ---------- Les opérateurs du Bénin ----------
     Les préfixes viennent des tables du SDK officiel de FeexPay. On ne
     s'en sert que pour PROPOSER l'opérateur : le client garde la main,
     un numéro porté d'un réseau à l'autre ne se devine pas. */
  const PREFIXES_10 = {
    MTN: ["0142", "0146", "0150", "0151", "0152", "0153", "0154", "0156", "0157",
          "0159", "0161", "0162", "0166", "0167", "0169", "0190", "0191", "0192",
          "0193", "0196", "0197"],
    MOOV: ["0145", "0155", "0158", "0160", "0163", "0164", "0165", "0168",
           "0194", "0195", "0198", "0199"],
    CELTIIS: ["0140", "0141", "0143", "0144", "0147"],
  };
  /* L'ancien format à huit chiffres, encore dicté par beaucoup de monde. */
  const PREFIXES_8 = {
    MTN: ["04", "05", "06", "44", "45", "46", "54", "55", "56", "64", "65", "66",
          "74", "75", "76", "84", "85", "86", "94", "95", "96"],
    MOOV: ["01", "02", "03", "40", "41", "42", "43", "50", "51", "52", "53",
           "70", "71", "72", "73", "80", "81", "82", "83", "90", "91", "92", "93"],
  };

  /** L'opérateur que suggère un numéro, ou "" si on ne sait pas. */
  function operateurDuNumero(tel) {
    const n = String(tel || "").replace(/\D/g, "").replace(/^229/, "");
    if (n.length >= 10 && n.startsWith("01")) {
      const p = n.slice(0, 4);
      for (const [nom, liste] of Object.entries(PREFIXES_10)) {
        if (liste.includes(p)) return nom;
      }
      return "";
    }
    if (n.length >= 8) {
      const p = n.slice(0, 2);
      for (const [nom, liste] of Object.entries(PREFIXES_8)) {
        if (liste.includes(p)) return nom;
      }
    }
    return "";
  }

  /* ---------- Dialogue avec la base ---------- */

  async function rpc(nom, parametres) {
    const c = Catalogue.configuration();
    if (!c) throw new Error("L'application n'est pas reliée à la base.");
    let reponse;
    try {
      /* LA SESSION PART AVEC L'APPEL, quand il y en a une. C'est elle qui
         permet à « creer_commande » de rattacher la commande à son compte :
         sans ce jeton, la base ne voit personne et la commande naît
         orpheline — le client ne la retrouverait pas sur un autre
         téléphone. Un visiteur sans compte commande toujours : la base
         accepte les deux. */
      const t = typeof Compte !== "undefined" ? await Compte.jeton() : "";
      reponse = await fetch(c.url + "/rest/v1/rpc/" + nom, {
        method: "POST",
        headers: {
          "apikey": c.cle,
          "Content-Type": "application/json",
          ...(t ? { "Authorization": "Bearer " + t } : {}),
        },
        body: JSON.stringify(parametres || {}),
      });
    } catch (_) {
      throw new Error("Impossible de joindre la boutique. Vérifiez votre connexion internet.");
    }
    const donnees = await reponse.json().catch(() => null);
    if (!reponse.ok) {
      const message = (donnees && (donnees.message || donnees.hint)) || "";
      if (reponse.status === 404 || /does not exist|Could not find/i.test(message)) {
        const err = new Error("La commande en ligne n'est pas encore ouverte sur cette boutique.");
        /* La base ne connaît pas cette fonction, ou pas sous cette forme :
           celui qui appelle peut retenter autrement (« creerCommande »). */
        err.inconnue = true;
        throw err;
      }
      throw new Error(message || "La commande n'a pas pu être enregistrée.");
    }
    return donnees;
  }

  /* ---------- Les réglages, lus en base ---------- */

  /** Un taux d'acompte lisible, de 1 à 100 ; sinon 100 — tout en ligne. */
  function tauxValable(brut) {
    const n = Math.round(Number(brut));
    return n >= 1 && n <= 100 ? n : 100;
  }

  /**
   * `options.garder` : en cas d'échec, garder les réglages déjà connus.
   * L'écran de commande relit le taux en s'ouvrant — le superadministrateur
   * a pu le changer depuis le démarrage —, et un réseau capricieux à cet
   * instant-là ne doit pas fermer un paiement qui était ouvert.
   */
  async function charger(options) {
    const c = Catalogue.configuration();
    if (!c) return (reglages = { actif: false, clePublique: "", bacASable: true, tauxAcompte: 100,
                                 fraisLivraison: 0 });
    try {
      const reponse = await fetch(c.url + "/rest/v1/paiement?select=*&id=eq.1",
        { headers: { "apikey": c.cle } });
      if (!reponse.ok) throw new Error("indisponible");
      const ligne = (await reponse.json())[0] || {};
      reglages = {
        actif: ligne.actif === true,
        /* Base d'avant les deux agrégateurs : c'était KkiaPay. */
        fournisseur: String(ligne.fournisseur || "kkiapay").trim(),
        clePublique: String(ligne.cle_publique || "").trim(),
        bacASable: ligne.bac_a_sable !== false,
        /* L'ACOMPTE À LA COMMANDE, en pour cent, réglé par le
           superadministrateur. Une base d'avant ne le connaît pas : on y
           payait le total, et c'est donc ce qu'on annonce. */
        tauxAcompte: tauxValable(ligne.taux_acompte),
        /* LES FRAIS DE LIVRAISON, par commande, en FCFA. Une base d'avant
           ne les connaît pas : il n'y en a pas, et on n'en annonce pas. */
        fraisLivraison: Math.max(0, Math.round(Number(ligne.frais_livraison) || 0)),
        /* (3.64.0) LA LIVRAISON AU KILOMÈTRE : en service dès que le
           superadministrateur a réglé le point BIZZOO. Une base d'avant
           ne la connaît pas : null, et rien ne change. */
        livraison: lireLivraison(ligne),
      };
    } catch (_) {
      if (options && options.garder && reglages) return reglages;
      /* Base d'avant le paiement, ou hors connexion : la boutique
         fonctionne comme avant, commande par WhatsApp. */
      reglages = { actif: false, fournisseur: "kkiapay", clePublique: "", bacASable: true,
                   tauxAcompte: 100, fraisLivraison: 0 };
    }
    /* Les écrans déjà dessinés sans eux peuvent se compléter. */
    document.dispatchEvent(new CustomEvent("paiement:charge"));
    return reglages;
  }

  function lireLivraison(ligne) {
    const lat = ligne.livraison_latitude, lng = ligne.livraison_longitude;
    if (lat === null || lat === undefined || lng === null || lng === undefined) return null;
    const n = (v, d) => (v === null || v === undefined || isNaN(Number(v)) ? d : Number(v));
    return {
      point: { latitude: Number(lat), longitude: Number(lng) },
      adresse: String(ligne.livraison_adresse || ""),
      rayon: n(ligne.livraison_rayon_km, 10),
      coef: n(ligne.livraison_coef, 1.3),
      moto: { forfait: n(ligne.moto_forfait, 1000), prixKm: n(ligne.moto_prix_km, 100) },
      tricycle: { forfait: n(ligne.tricycle_forfait, 4000), prixKm: n(ligne.tricycle_prix_km, 500) },
    };
  }

  /* ---------- La livraison au kilomètre (3.64.0) ----------
     UN frais pour la commande, du point BIZZOO jusqu'au client : le
     forfait du véhicule jusqu'au rayon (10 km), puis chaque kilomètre
     ENTAMÉ. Le tricycle dès qu'un seul produit l'exige. Ce qui suit est
     un APERÇU, calculé comme « devis_livraison » le fait en base : c'est
     elle qui fige les frais sur la commande, et c'est son montant qui se
     paie. */
  const livraisonAuKm = () => !!(reglages && reglages.livraison);
  const tarifs = () => (reglages && reglages.livraison) || null;

  /** Le véhicule du panier : tricycle dès qu'un produit l'exige. */
  function vehiculePanier() {
    const lignes = typeof Panier !== "undefined" ? Panier.lignes() : [];
    return lignes.some((l) => l.produit && l.produit.vehicule === "tricycle") ? "tricycle" : "moto";
  }

  /** Le devis d'une livraison vers « dest », ou null. */
  function devis(dest, vehicule) {
    const t = tarifs();
    if (!t || !dest || !isFinite(dest.latitude) || !isFinite(dest.longitude)) return null;
    const v = vehicule === "tricycle" ? "tricycle" : "moto";
    const rad = (d) => d * Math.PI / 180;
    const dlat = rad(dest.latitude - t.point.latitude);
    const dlng = rad(dest.longitude - t.point.longitude);
    const a = Math.sin(dlat / 2) ** 2 +
      Math.cos(rad(t.point.latitude)) * Math.cos(rad(dest.latitude)) * Math.sin(dlng / 2) ** 2;
    const dist = Math.round(2 * 6371 * Math.asin(Math.min(1, Math.sqrt(a))) * t.coef * 1000) / 1000;
    const km = dist > t.rayon ? Math.ceil(dist - t.rayon) : 0;
    const tarif = t[v];
    return { vehicule: v, distanceKm: Math.round(dist * 10) / 10, rayon: t.rayon, kmFactures: km,
             forfait: tarif.forfait, prixKm: tarif.prixKm, frais: tarif.forfait + km * tarif.prixKm };
  }

  /** « Livraison tricycle : 4 000 F jusqu'à 10 km, 500 F par km au-delà. » */
  function phraseTarif(vehicule, devise) {
    const t = tarifs();
    if (!t) return "";
    const v = vehicule === "tricycle" ? "tricycle" : "moto";
    const f = (n) => Utils.fmtMontant(n, devise || "FCFA");
    return "Livraison " + (v === "tricycle" ? "en tricycle" : "à moto") + " : " + f(t[v].forfait) +
      " jusqu'à " + String(t.rayon).replace(".", ",") + " km, " + f(t[v].prixKm) + " par km au-delà.";
  }

  /* Où livrer : gardé sur le téléphone, pour ne pas le redemander à
     chaque commande. Le client le change d'un geste. */
  function destination() {
    try {
      const d = JSON.parse(localStorage.getItem(CLE_DESTINATION) || "null");
      if (d && isFinite(d.latitude) && isFinite(d.longitude) &&
          Math.abs(d.latitude) <= 90 && Math.abs(d.longitude) <= 180 &&
          !(d.latitude === 0 && d.longitude === 0)) {
        return { latitude: Number(d.latitude), longitude: Number(d.longitude) };
      }
    } catch (_) { /* navigation privée */ }
    return null;
  }
  function choisirDestination(d) {
    try {
      if (d) localStorage.setItem(CLE_DESTINATION, JSON.stringify({
        latitude: Number(Number(d.latitude).toFixed(6)), longitude: Number(Number(d.longitude).toFixed(6)) }));
      else localStorage.removeItem(CLE_DESTINATION);
    } catch (_) { /* stockage plein : elle vivra le temps de l'écran */ }
    document.dispatchEvent(new CustomEvent("destination:maj"));
  }

  const fournisseur = () => (reglages && reglages.fournisseur) || "kkiapay";
  const tauxAcompte = () => (reglages && reglages.tauxAcompte) || 100;
  /** Les frais de livraison d'une commande. Un APERÇU : la base fige les
      siens sur la commande, et c'est ce montant-là qui se paie. */
  const fraisLivraison = () => (reglages && reglages.fraisLivraison) || 0;

  /**
   * L'acompte que la base posera sur ce total. C'EST UN APERÇU, pour que
   * le client sache avant de commander ce qu'il paiera maintenant : la
   * règle est celle de « creer_commande » — le taux sur le total remise
   * déduite, au franc supérieur, 100 FCFA au moins, jamais plus que le
   * total. Le montant qui part chez l'agrégateur est celui que la base
   * RENVOIE en créant la commande, jamais celui-ci.
   */
  function acompteDe(total) {
    const t = Math.max(0, Math.round(Number(total) || 0));
    if (t <= 0) return 0;
    return Math.min(t, Math.max(Math.ceil(t * tauxAcompte() / 100), 100));
  }

  /**
   * CE QUE COÛTERA LE PANIER, boutique par boutique (3.59.0). Chaque
   * boutique a ses frais de livraison et sa condition de paiement : tout
   * à la commande, ou un acompte (en %) à la commande et le reste à la
   * livraison. C'EST UN APERÇU, calculé comme « creer_commande » le fait :
   * la part d'une boutique, c'est ses articles, remise déduite au prorata,
   * plus ses frais ; son acompte, cette part par son taux, au franc
   * supérieur. Le montant qui part chez l'agrégateur est celui que la
   * base renvoie, jamais celui-ci.
   *
   * Une base d'avant ne connaît pas ces réglages : on retombe sur ceux de
   * l'enseigne — un acompte unique, des frais une fois par commande.
   */
  function apercu(remise) {
    const groupes = typeof Panier !== "undefined" ? Panier.parBoutique() : [];
    const sousTotal = groupes.reduce((s, g) => s + g.montant, 0);
    const r = Math.min(Math.max(0, Math.round(Number(remise) || 0)), sousTotal);
    /* (3.64.0) Au kilomètre, plus de frais par boutique : UN frais pour
       la commande, payé en entier en ligne avec l'acompte. Tant que le
       client n'a pas dit où livrer, on n'en connaît que le forfait. */
    const auKm = livraisonAuKm();
    const leDevis = auKm ? devis(destination(), vehiculePanier()) : null;
    const parBoutique = !auKm && groupes.some((g) => g.boutique && g.boutique.fraisLivraison !== undefined);
    const parts = groupes.map((g) => {
      const b = g.boutique || {};
      const net = Math.max(0, Math.round(g.montant - (sousTotal ? r * g.montant / sousTotal : 0)));
      const frais = parBoutique ? (b.fraisLivraison || 0) : 0;
      const taux = b.modePaiement === "total" ? 100
        : b.modePaiement === "acompte" ? (b.tauxAcompte || 100)
        : tauxAcompte();
      const du = net + frais;
      return { boutique: b, frais, taux, du, acompte: Math.min(du, Math.ceil(du * taux / 100)) };
    });
    const fraisKm = leDevis && groupes.length ? leDevis.frais : 0;
    const fraisUniques = auKm ? fraisKm : parBoutique ? 0 : (groupes.length ? fraisLivraison() : 0);
    const frais = parts.reduce((s, p) => s + p.frais, 0) + fraisUniques;
    const total = Math.max(0, sousTotal - r) + frais;
    let acompte = auKm
      ? parts.reduce((s, p) => s + p.acompte, 0) + fraisKm
      : parBoutique
        ? parts.reduce((s, p) => s + p.acompte, 0)
        : (total > 0 ? Math.ceil(total * tauxAcompte() / 100) : 0);
    if (total > 0) acompte = Math.min(total, Math.max(acompte, 100));
    const taux = [...new Set(parts.map((p) => p.taux))];
    return { sousTotal, remise: r, frais, total, acompte, reste: total - acompte, parts,
      /* Au kilomètre : le devis, ou null tant qu'on ne sait pas où livrer. */
      auKm, devis: leDevis, vehicule: auKm ? vehiculePanier() : null,
      /* Un seul taux pour tout le panier : on peut l'écrire. */
      tauxUnique: parBoutique ? (taux.length === 1 ? taux[0] : null) : tauxAcompte() };
  }

  /**
   * Le paiement en ligne est-il ouvert ?
   *
   * KkiaPay a besoin de sa clé publique dans l'application. FeexPay,
   * non : c'est notre serveur qui ouvre le paiement, et son jeton ne
   * descend jamais jusqu'ici. Il n'y a donc rien à vérifier de ce
   * côté-là — l'Edge Function dira elle-même si elle est configurée.
   */
  const disponible = () => {
    if (!reglages || !reglages.actif) return false;
    if (reglages.fournisseur === "feexpay") return true;
    return !!reglages.clePublique;
  };
  const bacASable = () => !!(reglages && reglages.bacASable);
  const connu = () => reglages !== null;

  /* ---------- Le widget de KkiaPay ---------- */

  function chargerWidget() {
    if (widgetCharge) return widgetCharge;
    widgetCharge = new Promise((resoudre, rejeter) => {
      if (typeof window.openKkiapayWidget === "function") return resoudre();
      const balise = document.createElement("script");
      balise.src = SCRIPT;
      balise.async = true;
      balise.onload = () => {
        /* Le script se déclare chargé avant d'avoir posé ses fonctions :
           on laisse passer un tour de boucle. */
        setTimeout(() => {
          if (typeof window.openKkiapayWidget === "function") resoudre();
          else rejeter(new Error("La page de paiement n'a pas pu s'ouvrir."));
        }, 0);
      };
      balise.onerror = () => {
        widgetCharge = null;   // une prochaine tentative pourra réessayer
        rejeter(new Error("Page de paiement injoignable. Vérifiez votre connexion internet."));
      };
      document.head.appendChild(balise);
    });
    return widgetCharge;
  }

  /* Les écouteurs de KkiaPay se posent une fois pour toutes : les
     rebrancher à chaque essai les empilerait, et un paiement réussi
     serait annoncé autant de fois qu'on a ouvert la page. */
  let ecouteursPoses = false;

  function poserEcouteurs() {
    if (ecouteursPoses) return;
    ecouteursPoses = true;
    if (typeof window.addSuccessListener === "function") {
      window.addSuccessListener((reponse) => {
        if (enCours) enCours.reussi(reponse || {});
      });
    }
    if (typeof window.addFailedListener === "function") {
      window.addFailedListener((reponse) => {
        if (enCours) enCours.echoue(reponse || {});
      });
    }
  }

  /**
   * Ouvre la page de paiement et attend la réponse de KkiaPay.
   * Résout avec { transactionId } — un simple indice, pas une preuve.
   *
   * Les champs facultatifs ne sont transmis QUE s'ils portent une
   * vraie valeur : une chaîne vide pré-remplit le formulaire d'un
   * champ invisiblement invalide, et le paiement échoue sur « numéro
   * non valide » sans qu'on comprenne pourquoi.
   */
  async function payer({ montant, commande, nom, tel }) {
    if (!disponible()) throw new Error("Le paiement en ligne n'est pas ouvert sur cette boutique.");
    await chargerWidget();
    poserEcouteurs();

    if (enCours) throw new Error("Un paiement est déjà en cours.");

    return new Promise((resoudre, rejeter) => {
      let termine = false;
      const finir = (fn, valeur) => {
        if (termine) return;
        termine = true;
        enCours = null;
        fn(valeur);
      };
      enCours = {
        reussi: (r) => finir(resoudre, {
          transactionId: String(r.transactionId || r.transaction_id || r.id || ""),
        }),
        echoue: (r) => finir(rejeter, new Error(
          (r && (r.reason || r.message)) || "Le paiement n'a pas abouti.")),
      };

      const options = {
        amount: Math.round(montant),
        key: reglages.clePublique,
        sandbox: !!reglages.bacASable,
        position: "center",
        theme: "#2550B7",        // le bleu des écrans, celui de l'icône
        data: commande,          // la référence que KkiaPay nous renverra
      };
      if (nom && nom.trim()) options.name = nom.trim();
      /* En bac à sable, un vrai numéro est TOUJOURS refusé : seuls les
         numéros de test passent. Le pré-remplir ferait croire à une
         panne. */
      if (!reglages.bacASable && tel && /\d{6}/.test(tel)) options.phone = String(tel).trim();

      try {
        window.openKkiapayWidget(options);
      } catch (err) {
        finir(rejeter, new Error("La page de paiement n'a pas pu s'ouvrir."));
      }
    });
  }

  /* ---------- FeexPay : notre serveur ouvre, et notre serveur vérifie ----------

     Rien de ce qui suit ne décide d'un paiement. « ouvrir » demande à
     notre Edge Function de lancer la demande chez FeexPay ; « verifier »
     lui demande d'aller voir où elle en est. C'est elle qui interroge
     FeexPay, avec un jeton qui ne descend jamais jusqu'ici — et c'est la
     réponse de FeexPay qui fait passer la commande à « payée », jamais
     ce fichier.
  */

  async function edgeFeexpay(corps) {
    const c = Catalogue.configuration();
    if (!c) throw new Error("L'application n'est pas reliée à la base.");
    let reponse;
    try {
      reponse = await fetch(c.url + "/functions/v1/feexpay", {
        method: "POST",
        headers: { "apikey": c.cle, "Content-Type": "application/json" },
        body: JSON.stringify(corps),
      });
    } catch (_) {
      throw new Error("Impossible de joindre le paiement. Vérifiez votre connexion internet.");
    }
    const donnees = await reponse.json().catch(() => ({}));
    if (!reponse.ok) {
      /* Ce que l'agrégateur a répondu, quand il a répondu quelque chose.
         « FeexPay a refusé la demande » tout seul n'apprend rien à
         personne : ni au client devant son écran, ni à la boutique qu'il
         va appeler. Sa phrase à lui, même maladroite, dit au moins où
         chercher. */
      const details = typeof donnees.details === "string" ? donnees.details.trim() : "";
      throw new Error((donnees.erreur || "Le paiement n'a pas pu s'ouvrir.") +
                      (details ? " — " + details : ""));
    }
    return donnees;
  }

  /** Lance la demande de paiement. Le client valide ensuite sur son téléphone. */
  const ouvrirFeexpay = ({ commande, tel, numero, reseau }) =>
    edgeFeexpay({ action: "payer", commande, tel, numero, reseau });

  /** « Où en est ce versement ? » — la question est posée à FeexPay. */
  const verifierFeexpay = (commande, tel) =>
    edgeFeexpay({ action: "verifier", commande, tel });

  /* ---------- Commander ---------- */

  /**
   * Crée la commande. On envoie des coordonnées et une liste
   * d'identifiants ; la base répond avec le montant à payer —
   * l'acompte — et c'est CE montant-là qui part chez l'agrégateur.
   *
   * « avec_acompte » dit à la base que cette application sait annoncer
   * un acompte et un reste. Les applications d'avant ne l'envoient pas :
   * leurs commandes se paient en entier, comme elles le disent. Une base
   * d'avant l'acompte ne connaît pas ce paramètre : on recommande alors
   * sans lui, et la commande se paie en entier — la réponse le dit, et
   * l'écran suit la réponse.
   */
  async function creerCommande(client, articles, code, ou) {
    /* Du plus récent au plus ancien : une base d'avant les frais de
       livraison, ou d'avant l'acompte, ne connaît pas ces paramètres. */
    /* (3.64.0) Où livrer : la base en tire la distance et les frais. Une
       base d'avant ne connaît pas « destination » : on retombe plus bas. */
    if (ou) {
      try {
        return await rpc("creer_commande",
          { client, articles, code: code || "", avec_acompte: true, avec_frais: true,
            destination: { latitude: ou.latitude, longitude: ou.longitude } });
      } catch (err) {
        if (!err.inconnue) throw err;
      }
    }
    try {
      return await rpc("creer_commande",
        { client, articles, code: code || "", avec_acompte: true, avec_frais: true });
    } catch (err) {
      if (!err.inconnue) throw err;
    }
    try {
      return await rpc("creer_commande",
        { client, articles, code: code || "", avec_acompte: true });
    } catch (err) {
      if (!err.inconnue) throw err;
      return rpc("creer_commande", { client, articles, code: code || "" });
    }
  }

  /**
   * « Ce code vaut-il quelque chose sur ce panier-ci ? »
   *
   * C'est la BASE qui répond, avec la même fonction que la caisse
   * appellera au moment de commander. L'application ne calcule aucune
   * remise elle-même : deux calculs finiraient par diverger, et le
   * client verrait un montant puis en paierait un autre.
   *
   * Rend { ok, remise, raison } — « raison » est écrite pour être
   * montrée telle quelle.
   */
  const verifierCode = (code, articles) =>
    rpc("verifier_code", { brut: code || "", articles });

  /** « KkiaPay m'a répondu ceci » : un indice noté pour la boutique. */
  async function signalerTransaction(id, transaction) {
    if (!transaction) return;
    try {
      await rpc("signaler_transaction", { cible: id, transaction });
    } catch (_) { /* sans importance : la notification de KkiaPay fait foi */ }
  }

  /** Le livreur de chaque boutique de la commande — nom et numéro —,
      pour le client qui l'a passée. */
  const livreurs = (id, tel) => rpc("livreurs_de_ma_commande", { cible: id, tel: tel || "" });

  /* Le propriétaire d'un code de particulier : son solde, et ses retraits.
     null quand le compte n'a pas de code — la carte ne s'affiche pas. */
  /* Les boutiques en live sur TikTok en ce moment : le bandeau « En
     live » de l'accueil et de la fiche d'une boutique. */
  const lives = () => rpc("lives_en_cours", {});
  const soldeParrain = () => rpc("mon_solde_parrain", {});
  const demanderRetrait = (montant, numero, reseau) =>
    rpc("demander_retrait", { montant: Math.round(Number(montant) || 0),
      numero: String(numero || ""), reseau: String(reseau || "") });

  /** L'état d'une commande, tel que la base le connaît. */
  const suivre = (id, tel) => rpc("suivre_commande", { cible: id, tel });
  /** Le client conteste ce que le livreur a déclaré avoir encaissé (3.59.0). */
  const contester = (id, boutique, motif, tel) =>
    rpc("contester_encaissement", { commande: id, boutique, motif, tel: tel || "" });

  /**
   * Attend que la base confirme le paiement. On patiente au lieu
   * d'annoncer : quelques secondes passent entre le moment où le client
   * valide sur son téléphone et celui où l'encaissement est constaté.
   *
   * Les deux agrégateurs s'attendent différemment :
   *
   *   KkiaPay  sa notification signée arrive toute seule chez nous. Il
   *            n'y a qu'à relire l'état de la commande.
   *
   *   FeexPay  personne ne nous préviendra. À chaque tour, on demande à
   *            notre serveur d'aller INTERROGER FeexPay. Le tour de
   *            boucle ne décide de rien : il ne fait que poser la
   *            question, et c'est la réponse de FeexPay qui tranche.
   *
   * Renvoie l'état atteint. « a_payer » au bout du compte ne veut pas
   * dire « échoué » — seulement « pas encore confirmé ».
   *
   * DEUX RÉPONSES DE FEEXPAY ARRÊTENT L'ATTENTE SUR-LE-CHAMP, parce
   * qu'attendre encore ferait croire que le versement peut aboutir :
   *
   *   { echoue: true, erreur }  FeexPay a répondu FAILED. C'est un
   *                             verdict : le sablier tournait jusqu'au
   *                             bout, puis annonçait « vous n'avez rien à
   *                             refaire » à un client qui n'avait rien
   *                             payé ;
   *   { rien: true }            aucune demande de paiement n'est ouverte
   *                             pour cette commande : elle n'est jamais
   *                             partie sur le téléphone.
   *
   * « controle.arrete », posé par l'écran — le client a appuyé sur
   * « Arrêter l'attente », ou il a quitté le reçu —, rend la main au
   * tour suivant, sans rien conclure.
   */
  async function attendreConfirmation(id, tel, pendant, controle) {
    const limite = Date.now() + (pendant || ATTENTE_MAX);
    const parFeexpay = fournisseur() === "feexpay";
    const arrete = () => !!(controle && controle.arrete);
    let dernier = null;
    /* Avec FeexPay, le premier tour part tout de suite : rouvrir le reçu
       d'un versement déjà refusé doit le dire aussitôt, pas au bout de
       trois secondes de sablier. */
    let patienter = !parFeexpay;
    while (Date.now() < limite && !arrete()) {
      if (patienter) await new Promise((r) => setTimeout(r, INTERVALLE));
      patienter = true;
      if (arrete()) break;
      if (parFeexpay) {
        /* Une vérification qui échoue n'interrompt pas l'attente : le
           versement peut très bien aboutir au tour suivant. */
        let verdict = null;
        try { verdict = await verifierFeexpay(id, tel); } catch (_) { /* on redemandera */ }
        if (arrete()) break;
        if (verdict && verdict.echoue) {
          return { etat: "a_payer", echoue: true,
                   erreur: verdict.erreur || "Le versement n'a pas abouti." };
        }
        /* La phrase exacte de notre fonction « feexpay » quand la commande
           n'a aucune référence de paiement. */
        if (verdict && verdict.raison === "aucun paiement ouvert") {
          return { etat: "a_payer", rien: true };
        }
      }
      try {
        dernier = await suivre(id, tel);
      } catch (_) {
        continue;   // réseau capricieux : un délai dépassé n'est pas un échec
      }
      if (dernier && dernier.etat && dernier.etat !== "a_payer") return dernier;
      if (dernier && dernier.remarque) return dernier;   // paiement incomplet
    }
    return dernier;
  }

  return {
    charger, disponible, bacASable, connu, fournisseur, operateurDuNumero,
    tauxAcompte, acompteDe, fraisLivraison, apercu,
    livraisonAuKm, tarifs, devis, vehiculePanier, phraseTarif, destination, choisirDestination,
    creerCommande, verifierCode, payer, ouvrirFeexpay, verifierFeexpay,
    signalerTransaction, suivre, contester, attendreConfirmation, livreurs,
    soldeParrain, demanderRetrait, lives,
  };
})();
