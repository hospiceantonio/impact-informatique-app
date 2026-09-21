/* =========================================================
   Les trois bips.

   RIEN À CHARGER, et c'est le point. Un fichier son, c'est un
   aller-retour de plus sur une connexion qui se paie au
   mégaoctet, un fichier de plus dans la coquille hors
   connexion, et un silence le jour où il manque. Trois bips se
   fabriquent en quelques lignes avec le son du navigateur.

   LES NAVIGATEURS REFUSENT LE SON AVANT LE PREMIER GESTE, et
   ce n'est pas un réglage qu'on puisse changer : une page qui
   se met à sonner toute seule à l'ouverture serait
   insupportable, alors ils l'interdisent. Le premier toucher,
   quel qu'il soit, débloque le son pour toute la session. Avant
   lui, la pastille paraît en silence — ce n'est pas une panne.

   ET ON PEUT LES COUPER. Quelqu'un qui tient vingt commandes
   par jour ne veut pas nécessairement vingt carillons. Le
   choix se garde sur l'appareil, pas en base : c'est un
   réglage de cet appareil-ci, pas du compte.

   LE MÊME FICHIER QUE CÔTÉ CLIENT, à la clé de rangement près.
   Les deux applications sont autonomes — aucune ne lit dans le
   dossier de l'autre —, et un son qui différerait d'un côté se
   remarquerait : c'est le même établissement qui sonne.
   ========================================================= */
const Son = (() => {

  const CLE = "impact-son";
  const BIPS = 3;
  const DUREE = 0.09;      // secondes, par bip
  const ECART = 0.16;      // secondes, entre deux départs
  const HAUTEUR = 880;     // hertz — un la, court et clair

  let contexte = null;
  let debloque = false;

  /** Coupé seulement si on l'a demandé : par défaut, ça sonne. */
  function actif() {
    try { return localStorage.getItem(CLE) !== "non"; } catch (_) { return true; }
  }

  function activer(oui) {
    try { localStorage.setItem(CLE, oui ? "oui" : "non"); } catch (_) { /* vide */ }
  }

  function contexteAudio() {
    if (contexte) return contexte;
    const Fabrique = window.AudioContext || window.webkitAudioContext;
    if (!Fabrique) return null;
    try { contexte = new Fabrique(); } catch (_) { contexte = null; }
    return contexte;
  }

  /**
   * Le premier geste débloque le son. On s'accroche à tout ce qui
   * ressemble à un geste, une seule fois — et on garde l'écouteur
   * « pointerdown » ET « keydown » : une tablette au clavier n'envoie
   * pas de « touchstart ».
   */
  function armer() {
    if (debloque) return;
    debloque = true;
    const ctx = contexteAudio();
    if (ctx && ctx.state === "suspended") ctx.resume().catch(() => { /* vide */ });
  }
  for (const geste of ["pointerdown", "touchstart", "keydown"]) {
    document.addEventListener(geste, armer, { once: true, passive: true });
  }

  /**
   * Trois bips courts. Silencieux si on les a coupés, si le navigateur
   * n'a pas encore été touché, ou s'il n'a pas de son du tout — et
   * dans les trois cas sans rien casser : la notification, elle, est
   * déjà arrivée.
   */
  function troisBips() {
    if (!actif()) return false;
    const ctx = contexteAudio();
    if (!ctx) return false;
    if (ctx.state === "suspended") {
      /* Pas encore débloqué : on tente, et on abandonne sans bruit. */
      ctx.resume().catch(() => { /* vide */ });
      if (ctx.state === "suspended") return false;
    }
    try {
      const depart = ctx.currentTime;
      for (let i = 0; i < BIPS; i++) {
        const t = depart + i * ECART;
        const oscillateur = ctx.createOscillator();
        const volume = ctx.createGain();
        oscillateur.type = "sine";
        oscillateur.frequency.setValueAtTime(HAUTEUR, t);
        /* UNE ENVELOPPE, ET NON UN INTERRUPTEUR. Un son qui démarre et
           s'arrête net claque — le haut-parleur d'un téléphone le rend
           en « clac ». On monte et on redescend en quelques
           millisecondes. */
        volume.gain.setValueAtTime(0.0001, t);
        volume.gain.exponentialRampToValueAtTime(0.25, t + 0.012);
        volume.gain.exponentialRampToValueAtTime(0.0001, t + DUREE);
        oscillateur.connect(volume);
        volume.connect(ctx.destination);
        oscillateur.start(t);
        oscillateur.stop(t + DUREE + 0.02);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  return { troisBips, actif, activer, CLE };
})();
