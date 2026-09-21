/* =========================================================
   Les notifications du client — la pastille, le panneau,
   le son, et le doigt qui mène à la bonne commande.

   TROIS FILETS, du plus rapide au plus sûr, exactement comme
   « live.js » pour le catalogue :
   1. temps réel : la base prévient dès qu'une ligne paraît ;
   2. retour au premier plan : à chaque fois qu'on revient
      dans l'application, on vérifie ;
   3. vérification régulière tant que l'écran est allumé.

   POURQUOI UN SOCKET À PART, et non celui de « live.js ». Ce
   dernier se connecte avec la clé PUBLIABLE : il écoute des
   tables ouvertes à tous. Les notifications, elles, sont
   fermées à leur destinataire — le temps réel ne laisse passer
   une ligne que si le JETON DU COMPTE le permet. Deux
   connexions, donc, parce que ce ne sont pas les mêmes droits.

   ET LE SON NE PART PAS TOUT SEUL. Les navigateurs refusent
   d'ouvrir le son avant que la personne n'ait touché l'écran —
   c'est une règle du navigateur, pas un réglage. Le premier
   geste, quel qu'il soit, le débloque ; avant lui, la pastille
   paraît en silence.
   ========================================================= */
const Notifs = (() => {

  const INTERVALLE = 60000;   // vérification de fond
  const BATTEMENT = 25000;    // le serveur ferme au-delà de 60 s
  const CLE_SON = "bizzoo-son";

  let liste = [];
  let nonLues = 0;
  let socket = null;
  let minuterieFond = null;
  let minuterieBattement = null;
  let minuterieReconnexion = null;
  let tentatives = 0;
  let refMessage = 0;
  let actif = false;
  let enCours = false;
  const abonnes = [];

  /* ---------- Ce que l'écran écoute ---------- */

  const surChangement = (rappel) => { abonnes.push(rappel); };
  const prevenir = () => { for (const r of abonnes) { try { r(); } catch (_) { /* vide */ } } };

  const compte = () => nonLues;
  const toutes = () => liste.slice();

  /* ---------- Lire ---------- */

  /**
   * On relit la LISTE, pas seulement le compteur : le panneau en a
   * besoin de toute façon, et deux appels là où un suffit coûtent deux
   * fois plus cher sur une connexion qui se paie au mégaoctet.
   */
  async function recharger() {
    if (enCours || typeof Compte === "undefined" || !Compte.connecte()) return false;
    enCours = true;
    try {
      const avant = nonLues;
      const lignes = await Compte.rest("GET",
        "notifications?select=*&order=cree_le.desc&limit=40");
      liste = (lignes || []).map((n) => ({
        id: n.id,
        type: n.type || "",
        titre: n.titre || "",
        corps: n.corps || "",
        lien: n.lien || "",
        commandeId: n.commande_id || "",
        sonne: n.sonne === true,
        lue: !!n.lue_le,
        creeLe: n.cree_le ? Date.parse(n.cree_le) : 0,
      }));
      nonLues = liste.filter((n) => !n.lue).length;
      /* LE SON NE SUIT PAS LE COMPTEUR, IL SUIT LES NOUVELLES. Sonner
         « quand le nombre monte » ferait sonner au premier chargement,
         quand on retrouve vingt notifications jamais lues — un
         carillon à l'ouverture de l'application. On ne sonne que pour
         ce qui vient d'arriver ET qui demande à sonner. */
      if (avant >= 0 && nonLues > avant && liste.some((n) => !n.lue && n.sonne)) {
        Son.troisBips();
      }
      prevenir();
      return true;
    } catch (_) {
      /* Base injoignable, jeton périmé : on garde ce qu'on a. */
      return false;
    } finally {
      enCours = false;
    }
  }

  /** Tout marquer lu. La base rend le nombre touché. */
  async function toutMarquerLu() {
    if (typeof Compte === "undefined" || !Compte.connecte()) return 0;
    let combien = 0;
    try {
      const r = await Compte.rpc("tout_marquer_lu", {});
      combien = Number(r) || 0;
    } catch (_) {
      return 0;
    }
    for (const n of liste) n.lue = true;
    nonLues = 0;
    prevenir();
    return combien;
  }

  /**
   * Marquer UNE notification lue. On n'attend pas la base pour
   * décocher à l'écran : le doigt part déjà vers la commande, et une
   * pastille qui traîne d'une seconde se lit comme une panne.
   */
  async function marquerLue(id) {
    const n = liste.find((x) => String(x.id) === String(id));
    if (!n || n.lue) return;
    n.lue = true;
    nonLues = Math.max(0, nonLues - 1);
    prevenir();
    try {
      await Compte.rest("PATCH", "notifications?id=eq." + encodeURIComponent(id),
        { lue_le: new Date().toISOString() }, { "Prefer": "return=minimal" });
    } catch (_) {
      /* Elle repassera non lue à la prochaine lecture : la base fait foi. */
    }
  }

  /* ---------- Le temps réel ---------- */

  function connecter() {
    const c = Catalogue.configuration ? Catalogue.configuration() : null;
    if (!actif || !c || typeof WebSocket !== "function") return;
    if (typeof Compte === "undefined" || !Compte.connecte()) return;
    if (socket && (socket.readyState === WebSocket.OPEN ||
                   socket.readyState === WebSocket.CONNECTING)) return;

    Compte.jeton().then((t) => {
      if (!t || !actif) return;
      const moi = Compte.identifiant();
      if (!moi) return;
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
          topic: "realtime:bizzoo-notifs",
          event: "phx_join",
          payload: {
            config: {
              broadcast: { self: false },
              /* LE FILTRE N'EST PAS UNE OPTIMISATION : sans lui, le
                 serveur enverrait les lignes des autres et compterait
                 sur nous pour les jeter. C'est la base qui trie, pas
                 l'écran — ici comme partout ailleurs. */
              postgres_changes: [{ event: "INSERT", schema: "public",
                table: "notifications", filter: "destinataire=eq." + moi }],
            },
            access_token: t,
          },
          ref: String(++refMessage),
        });
        clearInterval(minuterieBattement);
        minuterieBattement = setInterval(() => {
          envoyer({ topic: "phoenix", event: "heartbeat", payload: {},
            ref: String(++refMessage) });
        }, BATTEMENT);
        /* Une notification a pu naître pendant la coupure. */
        recharger();
      };

      socket.onmessage = (message) => {
        let donnees;
        try { donnees = JSON.parse(message.data); } catch (_) { return; }
        if (donnees && donnees.event === "postgres_changes") recharger();
      };

      socket.onclose = () => {
        clearInterval(minuterieBattement);
        socket = null;
        programmerReconnexion();
      };
      socket.onerror = () => { /* onclose suit toujours */ };
    }).catch(() => programmerReconnexion());
  }

  function envoyer(objet) {
    try {
      if (socket && socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(objet));
    } catch (_) { /* la fermeture sera traitée par onclose */ }
  }

  function programmerReconnexion() {
    if (!actif) return;
    clearTimeout(minuterieReconnexion);
    /* On s'éloigne à chaque échec, sans dépasser la minute : une base
       en panne ne doit pas être martelée par mille téléphones. */
    const attente = Math.min(60000, 1500 * Math.pow(2, Math.min(tentatives++, 5)));
    minuterieReconnexion = setTimeout(connecter, attente);
  }

  function fermer() {
    clearInterval(minuterieBattement);
    clearTimeout(minuterieReconnexion);
    if (socket) {
      try { socket.close(); } catch (_) { /* vide */ }
      socket = null;
    }
  }

  /* ---------- Démarrer, arrêter ---------- */

  function demarrer() {
    if (actif) return;
    actif = true;
    recharger();
    connecter();
    clearInterval(minuterieFond);
    minuterieFond = setInterval(() => {
      if (document.visibilityState === "visible") recharger();
    }, INTERVALLE);
  }

  function arreter() {
    actif = false;
    fermer();
    clearInterval(minuterieFond);
    liste = [];
    nonLues = 0;
    prevenir();
  }

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState !== "visible" || !actif) return;
    recharger();
    connecter();
  });

  return {
    demarrer, arreter, recharger, compte, toutes,
    marquerLue, toutMarquerLu, surChangement,
    activerSon: (oui) => Son.activer(oui), sonActif: () => Son.actif(),
    CLE_SON,
  };
})();
