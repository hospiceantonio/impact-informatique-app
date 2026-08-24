/* =========================================================
   Paiement — commander, puis payer par Mobile Money (KkiaPay).

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

  let reglages = null;          // { actif, clePublique, bacASable }
  let widgetCharge = null;      // promesse de chargement du script
  let enCours = null;           // la promesse du paiement ouvert

  /* ---------- Dialogue avec la base ---------- */

  async function rpc(nom, parametres) {
    const c = Catalogue.configuration();
    if (!c) throw new Error("L'application n'est pas reliée à la base.");
    let reponse;
    try {
      reponse = await fetch(c.url + "/rest/v1/rpc/" + nom, {
        method: "POST",
        headers: { "apikey": c.cle, "Content-Type": "application/json" },
        body: JSON.stringify(parametres || {}),
      });
    } catch (_) {
      throw new Error("Impossible de joindre la boutique. Vérifiez votre connexion internet.");
    }
    const donnees = await reponse.json().catch(() => null);
    if (!reponse.ok) {
      const message = (donnees && (donnees.message || donnees.hint)) || "";
      if (reponse.status === 404 || /does not exist|Could not find/i.test(message)) {
        throw new Error("La commande en ligne n'est pas encore ouverte sur cette boutique.");
      }
      throw new Error(message || "La commande n'a pas pu être enregistrée.");
    }
    return donnees;
  }

  /* ---------- Les réglages, lus en base ---------- */

  async function charger() {
    const c = Catalogue.configuration();
    if (!c) return (reglages = { actif: false, clePublique: "", bacASable: true });
    try {
      const reponse = await fetch(c.url + "/rest/v1/paiement?select=*&id=eq.1",
        { headers: { "apikey": c.cle } });
      if (!reponse.ok) throw new Error("indisponible");
      const ligne = (await reponse.json())[0] || {};
      reglages = {
        actif: ligne.actif === true,
        clePublique: String(ligne.cle_publique || "").trim(),
        bacASable: ligne.bac_a_sable !== false,
      };
    } catch (_) {
      /* Base d'avant le paiement, ou hors connexion : la boutique
         fonctionne comme avant, commande par WhatsApp. */
      reglages = { actif: false, clePublique: "", bacASable: true };
    }
    return reglages;
  }

  /** Le paiement en ligne est-il ouvert ? Faux tant qu'aucune clé n'est posée. */
  const disponible = () => !!(reglages && reglages.actif && reglages.clePublique);
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
        theme: "#0B5CF5",
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

  /* ---------- Commander ---------- */

  /**
   * Crée la commande. On envoie des coordonnées et une liste
   * d'identifiants ; la base répond avec le montant à payer —
   * et c'est CE montant-là qui part chez KkiaPay.
   */
  const creerCommande = (client, articles) => rpc("creer_commande", { client, articles });

  /** « KkiaPay m'a répondu ceci » : un indice noté pour la boutique. */
  async function signalerTransaction(id, transaction) {
    if (!transaction) return;
    try {
      await rpc("signaler_transaction", { cible: id, transaction });
    } catch (_) { /* sans importance : la notification de KkiaPay fait foi */ }
  }

  /** L'état d'une commande, tel que la base le connaît. */
  const suivre = (id, tel) => rpc("suivre_commande", { cible: id, tel });

  /**
   * Attend que la base confirme le paiement. Quelques secondes passent
   * entre la validation chez KkiaPay et l'arrivée de sa notification :
   * on patiente au lieu d'annoncer.
   *
   * Renvoie l'état atteint. « a_payer » au bout du compte ne veut pas
   * dire « échoué » — seulement « pas encore confirmé ».
   */
  async function attendreConfirmation(id, tel, pendant) {
    const limite = Date.now() + (pendant || ATTENTE_MAX);
    let dernier = null;
    while (Date.now() < limite) {
      await new Promise((r) => setTimeout(r, INTERVALLE));
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
    charger, disponible, bacASable, connu,
    creerCommande, payer, signalerTransaction, suivre, attendreConfirmation,
  };
})();
