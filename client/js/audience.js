/* =========================================================
   Audience (4.6.0) — combien de visiteurs, combien de temps,
   ce qu'ils regardent.

   La boutique dit à la base de BIZZOO, et à elle seule : « une
   visite a commencé », « elle dure encore », « ce produit, cette
   boutique ont été ouverts », « un article est allé au panier »,
   « une commande a été payée ». L'administration y lit des
   totaux (Statistiques → Visiteurs).

   TROIS RÈGLES.

   1. AUCUNE DONNÉE PERSONNELLE. Le visiteur est un identifiant
      tiré au hasard par cet appareil. Il n'est relié ni au compte,
      ni au numéro, ni à l'adresse : l'envoi part sans le jeton du
      client, même connecté. Rien ne part ailleurs que chez BIZZOO.

   2. JAMAIS GÊNANT. Les envois sont groupés, partent en arrière-
      plan, et un échec (hors connexion, base d'avant) se tait : la
      boutique n'attend jamais cette réponse.

   3. LE TEMPS PASSÉ EST DU TEMPS PASSÉ. La visite ne « dure » que
      tant que l'écran est visible et que le visiteur y touche : un
      onglet oublié ouvert ne compte pas. Après une demi-heure sans
      rien, c'est une nouvelle visite.
   ========================================================= */
const Audience = (() => {
  const CLE_VISITEUR = "bizzoo-visiteur";
  const CLE_VISITE = "bizzoo-visite";
  const PAUSE = 30 * 60 * 1000;      // au-delà, une nouvelle visite
  const GROUPE = 4000;               // les envois se groupent
  const BATTEMENT = 30000;           // « elle dure encore »
  const memoire = {};

  function alea() {
    const lettres = "abcdefghijklmnopqrstuvwxyz0123456789";
    const t = new Uint8Array(20);
    try { crypto.getRandomValues(t); } catch (_) { for (let i = 0; i < t.length; i++) t[i] = Math.floor(Math.random() * 256); }
    let s = "";
    for (const o of t) s += lettres[o % lettres.length];
    return s;
  }
  const lire = (magasin, cle) => { try { return magasin.getItem(cle); } catch (_) { return memoire[cle] || null; } };
  const ecrire = (magasin, cle, v) => { try { magasin.setItem(cle, v); } catch (_) { memoire[cle] = v; } };

  function visiteur() {
    let v = lire(localStorage, CLE_VISITEUR);
    if (!/^[a-z0-9]{12,40}$/.test(v || "")) { v = alea(); ecrire(localStorage, CLE_VISITEUR, v); }
    return v;
  }
  /** La visite en cours ; une autre après une demi-heure sans rien. */
  function visite() {
    let s = null;
    try { s = JSON.parse(lire(sessionStorage, CLE_VISITE) || "null"); } catch (_) { s = null; }
    const maintenant = Date.now();
    if (!s || !/^[a-z0-9]{12,40}$/.test(s.id || "") || maintenant - Number(s.vu || 0) > PAUSE) {
      s = { id: alea(), vues: [] };
    }
    s.vu = maintenant;
    if (!Array.isArray(s.vues)) s.vues = [];
    ecrire(sessionStorage, CLE_VISITE, JSON.stringify(s));
    return s;
  }
  const plateforme = () => window.BizzooIOS ? "ios"
    : location.hostname === "appassets.androidx.dev" ? "android" : "web";

  let ecrans = 0;
  let vues = [];
  let panier = false;
  let commande = false;
  let attente = null;
  let touche = false;

  function envoyer() {
    clearTimeout(attente);
    attente = null;
    const c = typeof Catalogue !== "undefined" && Catalogue.configuration ? Catalogue.configuration() : null;
    const corps = { le_visiteur: visiteur(), la_session: visite().id, la_plateforme: plateforme(),
      des_ecrans: ecrans, des_vues: vues, au_panier: panier, a_commande: commande };
    ecrans = 0; vues = []; panier = false; commande = false;
    if (!c || !c.url || !c.cle) return;
    try {
      fetch(c.url + "/rest/v1/rpc/noter_visite", {
        method: "POST", keepalive: true,
        headers: { "apikey": c.cle, "Content-Type": "application/json" },
        body: JSON.stringify(corps),
      }).catch(() => { /* règle 2 */ });
    } catch (_) { /* règle 2 */ }
  }
  const bientot = () => { if (!attente) attente = setTimeout(envoyer, GROUPE); };

  /** Une fiche ouverte : une fois par visite. */
  function vu(genre, id) {
    if (!id) return;
    const s = visite();
    const cle = genre + ":" + id;
    if (s.vues.includes(cle)) return;
    s.vues.push(cle);
    if (s.vues.length > 300) s.vues.shift();
    ecrire(sessionStorage, CLE_VISITE, JSON.stringify(s));
    vues.push({ g: genre, c: String(id) });
    bientot();
  }
  /** Un écran affiché (une vraie navigation, pas un écran redessiné). */
  function ecran(chemin) {
    ecrans++;
    const m = /^\/boutique\/([^/]+)$/.exec(chemin || "");
    if (m) { try { vu("boutique", decodeURIComponent(m[1])); } catch (_) { /* adresse illisible */ } }
    bientot();
  }

  for (const geste of ["pointerdown", "keydown", "scroll", "touchstart"]) {
    window.addEventListener(geste, () => { touche = true; }, { passive: true, capture: true });
  }
  setInterval(() => {
    if (document.visibilityState !== "visible" || !touche) return;
    touche = false;
    envoyer();
  }, BATTEMENT);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden" && (attente || touche)) { touche = false; envoyer(); }
  });

  return {
    ecran, vu,
    produitVu: (id) => vu("produit", id),
    panier: () => { panier = true; bientot(); },
    achat: () => { commande = true; bientot(); },
  };
})();
