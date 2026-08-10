/* =========================================================
   Live — le catalogue se met à jour tout seul, sans que le
   client ait à fermer et rouvrir l'application.

   Trois filets, du plus rapide au plus sûr :
   1. temps réel : la base prévient dès qu'un produit change
      (WebSocket) — l'écran suit en une seconde ;
   2. retour au premier plan : à chaque fois que le client
      revient dans l'application, on vérifie ;
   3. vérification régulière tant que l'écran est allumé,
      au cas où le temps réel serait indisponible.
   ========================================================= */
const Live = (() => {

  const INTERVALLE_DEFAUT = 45000;   // vérification de fond
  const BATTEMENT = 25000;           // le serveur ferme au-delà de 60 s
  const TABLES = ["produits", "categories", "sous_categories", "boutique"];

  let intervalle = INTERVALLE_DEFAUT;
  let socket = null;
  let minuterieFond = null;
  let minuterieBattement = null;
  let minuterieReconnexion = null;
  let minuterieRegroupement = null;
  let tentatives = 0;
  let refMessage = 0;
  let actif = false;
  let enCoursDeVerification = false;

  /* ---------- Vérification (partagée par les trois filets) ---------- */

  async function verifier() {
    if (enCoursDeVerification || !Catalogue.estConfigure()) return false;
    enCoursDeVerification = true;
    try {
      return await Catalogue.rafraichir();
    } finally {
      enCoursDeVerification = false;
    }
  }

  /** Plusieurs modifications d'affilée ne déclenchent qu'une lecture. */
  function verifierBientot(delai = 700) {
    clearTimeout(minuterieRegroupement);
    minuterieRegroupement = setTimeout(verifier, delai);
  }

  /* ---------- 1. Temps réel ---------- */

  function connecter() {
    const c = Catalogue.configuration ? Catalogue.configuration() : null;
    if (!actif || !c || typeof WebSocket !== "function") return;
    if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) return;

    const adresse = c.url.replace(/^http/, "ws") +
      "/realtime/v1/websocket?apikey=" + encodeURIComponent(c.cle) + "&vsn=1.0.0";

    try {
      socket = new WebSocket(adresse);
    } catch (_) {
      programmerReconnexion();
      return;
    }

    socket.onopen = () => {
      tentatives = 0;
      envoyer({
        topic: "realtime:impact",
        event: "phx_join",
        payload: {
          config: {
            broadcast: { self: false },
            postgres_changes: TABLES.map((table) => ({ event: "*", schema: "public", table })),
          },
          access_token: c.cle,
        },
        ref: String(++refMessage),
      });
      clearInterval(minuterieBattement);
      minuterieBattement = setInterval(() => {
        envoyer({ topic: "phoenix", event: "heartbeat", payload: {}, ref: String(++refMessage) });
      }, BATTEMENT);
      /* Une modification a pu survenir pendant la coupure. */
      verifierBientot(200);
    };

    socket.onmessage = (message) => {
      let donnees;
      try { donnees = JSON.parse(message.data); } catch (_) { return; }
      if (donnees && donnees.event === "postgres_changes") verifierBientot();
    };

    socket.onclose = () => {
      clearInterval(minuterieBattement);
      socket = null;
      programmerReconnexion();
    };

    socket.onerror = () => {
      /* onclose suit toujours : c'est lui qui reprogramme. */
    };
  }

  function envoyer(objet) {
    try {
      if (socket && socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(objet));
    } catch (_) { /* la fermeture sera traitée par onclose */ }
  }

  function programmerReconnexion() {
    if (!actif) return;
    clearTimeout(minuterieReconnexion);
    /* 2 s, 4 s, 8 s… plafonné à 1 minute : jamais de rafale. */
    const attente = Math.min(60000, 2000 * Math.pow(2, Math.min(tentatives++, 5)));
    minuterieReconnexion = setTimeout(connecter, attente);
  }

  function deconnecter() {
    clearInterval(minuterieBattement);
    clearTimeout(minuterieReconnexion);
    if (socket) {
      socket.onclose = null;
      try { socket.close(); } catch (_) { /* déjà fermé */ }
      socket = null;
    }
  }

  const tempsReelConnecte = () => !!socket && socket.readyState === WebSocket.OPEN;

  /* ---------- 2. Retour au premier plan ---------- */

  function surVisibilite() {
    if (document.visibilityState === "visible") {
      verifier();
      connecter();
      demarrerFond();
    } else {
      /* En arrière-plan : on relâche tout, batterie et données préservées. */
      clearInterval(minuterieFond);
      minuterieFond = null;
      deconnecter();
    }
  }

  /* ---------- 3. Vérification régulière ---------- */

  function demarrerFond() {
    clearInterval(minuterieFond);
    minuterieFond = setInterval(() => {
      if (document.visibilityState !== "visible") return;
      /* Avec le temps réel, cette vérification n'est qu'un filet de sécurité. */
      verifier();
    }, intervalle);
  }

  /* ---------- Démarrage / arrêt ---------- */

  function demarrer(options) {
    if (options && options.intervalle) intervalle = options.intervalle;
    if (actif) return;
    actif = true;
    document.addEventListener("visibilitychange", surVisibilite);
    window.addEventListener("online", () => { verifier(); connecter(); });
    window.addEventListener("focus", () => verifierBientot(300));
    connecter();
    demarrerFond();
  }

  function arreter() {
    actif = false;
    document.removeEventListener("visibilitychange", surVisibilite);
    clearInterval(minuterieFond);
    clearTimeout(minuterieRegroupement);
    minuterieFond = null;
    deconnecter();
  }

  return { demarrer, arreter, verifier, tempsReelConnecte };
})();
