/* =========================================================
   Les notifications de l'équipe — la pastille, le panneau,
   le son, et le doigt qui mène à la bonne commande.

   L'APPLICATION DE LA BOUTIQUE N'AVAIT AUCUN TEMPS RÉEL. Celle
   du client en a un depuis longtemps (« live.js », pour le
   catalogue) ; ici, tout se lisait à l'ouverture d'un écran.
   Pour une commande payée à l'instant, c'est trop tard : la
   boutique ne l'apprend qu'en rouvrant l'écran des commandes,
   et le client attend pendant ce temps.

   TROIS FILETS, du plus rapide au plus sûr :
   1. temps réel : la base prévient dès qu'une ligne paraît ;
   2. retour au premier plan : à chaque fois qu'on revient
      dans l'application, on vérifie ;
   3. vérification régulière tant que l'écran est allumé.

   LE SOCKET PORTE LE JETON DU COMPTE, et non la clé publiable.
   Les notifications sont fermées à leur destinataire : le temps
   réel ne laisse passer une ligne que si le jeton le permet.
   C'est la base qui trie, pas cet écran.

   ET LE LIVREUR EN PROFITE AUTANT QUE LA BOUTIQUE : c'est lui
   qui attend le plus une nouvelle course, et lui qui a le moins
   envie de rouvrir un écran toutes les cinq minutes.
   ========================================================= */
const Notifs = (() => {

  const INTERVALLE = 60000;   // vérification de fond
  const BATTEMENT = 25000;    // le serveur ferme au-delà de 60 s

  let liste = [];
  let nonLues = 0;
  let socket = null;
  let minuterieFond = null;
  let minuterieBattement = null;
  let minuterieReconnexion = null;
  let tentatives = 0;
  let refMessage = 0;
  let actif = false;
  let enCours = null;
  const abonnes = [];

  const surChangement = (rappel) => { abonnes.push(rappel); };
  const prevenir = () => { for (const r of abonnes) { try { r(); } catch (_) { /* vide */ } } };
  const compte = () => nonLues;
  const toutes = () => liste.slice();

  /* ---------- Lire ---------- */

  /* Une lecture en cours se partage : l'écran ouvert d'emblée sur
     « #/notifications » attend celle du démarrage au lieu de repartir
     les mains vides. */
  function recharger() {
    if (enCours) return enCours;
    if (!Supabase.sessionPresente()) return Promise.resolve(false);
    enCours = lire();
    return enCours;
  }

  async function lire() {
    try {
      const avant = nonLues;
      const lignes = await Supabase.requete("GET",
        "notifications?select=*&order=cree_le.desc&limit=60", undefined,
        { avecSession: true });
      liste = (lignes || []).map((n) => ({
        id: n.id,
        type: n.type || "",
        titre: n.titre || "",
        corps: n.corps || "",
        lien: n.lien || "",
        commandeId: n.commande_id || "",
        boutiqueId: n.boutique_id || "",
        sonne: n.sonne === true,
        lue: !!n.lue_le,
        creeLe: n.cree_le ? Date.parse(n.cree_le) : 0,
      }));
      nonLues = liste.filter((n) => !n.lue).length;
      /* LE SON SUIT LES NOUVELLES, PAS LE COMPTEUR. Sonner « quand le
         nombre monte » ferait sonner au premier chargement, quand on
         retrouve trente commandes jamais ouvertes — un carillon à
         l'ouverture de l'application. */
      /* LE LIVREUR A SA SONNERIE (3.59.0) : elle insiste tant qu'une
         course attend « Commande reçue ». Les autres gardent les bips. */
      if (estLivreur()) {
        verifierCourses();
      } else if (avant >= 0 && nonLues > avant && liste.some((n) => !n.lue && n.sonne)) {
        Son.troisBips();
      }
      prevenir();
      return true;
    } catch (_) {
      /* Base injoignable, colonne absente d'une base pas encore mise à
         jour : on garde ce qu'on a, et l'application marche sans. */
      return false;
    } finally {
      enCours = null;
    }
  }

  /* ---------- La sonnerie du livreur (3.59.0) ----------
     Une course l'attend : confiée et pas encore acceptée, ou proposée à
     tous et pas encore prise. Tant qu'il y en a une, la sonnerie et la
     vibration reprennent toutes les quatre secondes ; « Commande reçue »,
     ou un refus, les arrêtent. */
  const estLivreur = () => Supabase.role() === "livreur";

  /* « DÉJÀ PRIS PAR … » (3.59.0). Une demande proposée à plusieurs
     livreurs — une livraison groupée, à tous ceux de BIZZOO — disparaît
     dès que l'un la prend : la base envoie aux autres « Déjà pris par
     <nom> », en temps réel. On le dit à l'écran, et la sonnerie s'arrête. */
  let demandesVues = new Set();
  const priseDe = (commandeId) =>
    liste.find((n) => n.type === "course_prise" && n.commandeId === commandeId);

  function majAlerte(courses, demandes) {
    const ici = new Set((demandes || []).map((d) => d.commandeId));
    const parties = [...demandesVues].filter((id) => !ici.has(id));
    demandesVues = ici;
    for (const id of parties) {
      const n = priseDe(id);
      if (n) {
        UI.toast(n.titre + " : la course n'est plus disponible.");
        marquerLue(n.id);
      }
    }
    const attend = (demandes || []).length > 0 ||
      (courses || []).some((c) => c.fiche && !c.recuLe && c.etat !== "remise");
    if (attend && estLivreur()) Son.demarrerAlerte();
    else Son.arreterAlerte();
    return parties;
  }

  async function verifierCourses() {
    if (!estLivreur()) { Son.arreterAlerte(); return; }
    try {
      const [courses, demandes] = await Promise.all([Store.mesLivraisons(), Store.coursesProposees()]);
      /* Une demande vient de partir chez un autre : l'écran des courses,
         s'il est ouvert, se relit — la carte disparaît sous ses yeux. */
      if (majAlerte(courses, demandes).length) {
        window.dispatchEvent(new CustomEvent("bizzoo:courses"));
      }
    } catch (_) {
      /* Base injoignable : on ne coupe pas une sonnerie en cours sur une
         panne, et on n'en lance pas une sur rien. */
    }
  }

  async function toutMarquerLu() {
    if (!Supabase.sessionPresente()) return 0;
    let combien = 0;
    try {
      const r = await Supabase.rpcLecture("tout_marquer_lu", {});
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
   * Marquer UNE notification lue. On décoche à l'écran sans attendre la
   * base : le doigt part déjà vers la commande, et une pastille qui
   * traîne d'une seconde se lit comme une panne.
   *
   * « sansRetour » N'EST PAS UN DÉTAIL : sans lui, PostgREST ajoute
   * « returning * », qui réclame la lecture de toute la ligne. C'est la
   * leçon de « Marquer vue » — on ne demande pas ce dont on n'a que
   * faire.
   */
  async function marquerLue(id) {
    const n = liste.find((x) => String(x.id) === String(id));
    if (!n || n.lue) return;
    n.lue = true;
    nonLues = Math.max(0, nonLues - 1);
    prevenir();
    try {
      await Supabase.requete("PATCH",
        "notifications?id=eq." + encodeURIComponent(id),
        { lue_le: new Date().toISOString() }, { sansRetour: true });
    } catch (_) {
      /* Elle repassera non lue à la prochaine lecture : la base fait foi. */
    }
  }

  /* ---------- Le temps réel ---------- */

  function connecter() {
    const c = Supabase.configuration();
    if (!actif || !c || typeof WebSocket !== "function") return;
    if (!Supabase.sessionPresente()) return;
    if (socket && (socket.readyState === WebSocket.OPEN ||
                   socket.readyState === WebSocket.CONNECTING)) return;

    Supabase.assurerSession().then((s) => {
      if (!s || !s.access_token || !actif) return;
      const moi = Supabase.identifiant();
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
          topic: "realtime:impact-notifs",
          event: "phx_join",
          payload: {
            config: {
              broadcast: { self: false },
              /* Le filtre n'est pas une optimisation : sans lui, le
                 serveur enverrait les lignes des autres et compterait
                 sur nous pour les jeter. */
              postgres_changes: [{ event: "INSERT", schema: "public",
                table: "notifications", filter: "destinataire=eq." + moi },
                /* (3.59.0) Le signal des commandes qu'on voit : la base ne
                   l'envoie qu'à ceux qui y ont droit. */
                { event: "*", schema: "public", table: "commandes_signaux" }],
            },
            access_token: s.access_token,
          },
          ref: String(++refMessage),
        });
        clearInterval(minuterieBattement);
        minuterieBattement = setInterval(() => {
          envoyer({ topic: "phoenix", event: "heartbeat", payload: {},
            ref: String(++refMessage) });
        }, BATTEMENT);
        recharger();
      };

      socket.onmessage = (message) => {
        let donnees;
        try { donnees = JSON.parse(message.data); } catch (_) { return; }
        if (!donnees || donnees.event !== "postgres_changes") return;
        const table = donnees.payload && donnees.payload.data && donnees.payload.data.table;
        if (table === "commandes_signaux") {
          /* UNE COMMANDE A BOUGÉ (3.59.0) : l'écran qui la montre se relit. */
          const r = donnees.payload.data.record || {};
          window.dispatchEvent(new CustomEvent("bizzoo:commande", { detail: { id: r.commande_id || "" } }));
          return;
        }
        recharger();
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
    Son.arreterAlerte();
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
    marquerLue, toutMarquerLu, surChangement, majAlerte, verifierCourses,
  };
})();
