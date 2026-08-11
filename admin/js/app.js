/* =========================================================
   App — routeur par ancre (#/...), démarrage, connexion,
   service worker.
   ========================================================= */
(() => {

  const ROUTES = [
    { motif: /^\/$/, vue: (v) => VueAccueil.afficher(v), onglet: "/" },
    { motif: /^\/produits$/, vue: (v) => VueProduits.liste(v), onglet: "/produits" },
    { motif: /^\/produit\/nouveau$/, vue: (v) => VueProduits.formulaire(v) },
    { motif: /^\/produit\/([^/]+)\/modifier$/, vue: (v, m) => VueProduits.formulaire(v, m[1]) },
    { motif: /^\/produit\/([^/]+)$/, vue: (v, m) => VueProduits.detail(v, m[1]) },
    { motif: /^\/categories$/, vue: (v) => VueCategories.afficher(v), onglet: "/categories" },
    { motif: /^\/reglages$/, vue: (v, m, p) => VueReglages.afficher(v, p), onglet: "/reglages" },
  ];


  /* ---------- Mémoire de la position de lecture ----------
     Après avoir ouvert un produit, le gérant revient à sa place
     exacte dans la liste, pas en haut de l'écran. */

  const positions = new Map();
  let indexCourant = -1;
  let compteurHistorique = 0;
  let ecranQuitte = null;

  const hauteurActuelle = () =>
    window.scrollY || document.documentElement.scrollTop || 0;

  function restaurerHauteur(hauteur) {
    if (!hauteur) return;
    let essais = 0;
    const appliquer = () => {
      window.scrollTo(0, hauteur);
      essais++;
      if (essais < 10 && Math.abs(hauteurActuelle() - hauteur) > 2) {
        requestAnimationFrame(appliquer);
      }
    };
    requestAnimationFrame(appliquer);
    setTimeout(appliquer, 150);
    setTimeout(appliquer, 500);
  }

  function lireHash() {
    const brut = location.hash.replace(/^#/, "") || "/";
    const [chemin, requete] = brut.split("?");
    const params = {};
    if (requete) {
      for (const morceau of requete.split("&")) {
        const [cle, valeur] = morceau.split("=");
        if (cle) params[decodeURIComponent(cle)] = decodeURIComponent(valeur || "");
      }
    }
    return { chemin: chemin || "/", params };
  }

  async function naviguer() {
    const { chemin, params } = lireHash();
    const vue = document.getElementById("vue");
    const ecran = location.hash || "#/";

    if (ecranQuitte && ecranQuitte !== ecran) {
      positions.set(ecranQuitte, hauteurActuelle());
    }

    let retourEnArriere = false;
    const etat = history.state;
    if (etat && typeof etat.rang === "number") {
      retourEnArriere = etat.rang < indexCourant;
      indexCourant = etat.rang;
    } else {
      indexCourant = ++compteurHistorique;
      try { history.replaceState({ rang: indexCourant }, ""); } catch (_) { /* sans importance */ }
    }
    ecranQuitte = ecran;
    UI.fermerFeuille();
    UI.fermerVisionneuse();

    const route = ROUTES.find((r) => r.motif.test(chemin));
    if (!route) {
      location.hash = "#/";
      return;
    }

    for (const lien of document.querySelectorAll("#tabbar [data-tab]")) {
      lien.classList.toggle("actif", lien.dataset.tab === (route.onglet || ""));
    }

    try {
      await route.vue(vue, chemin.match(route.motif), params);
    } catch (err) {
      console.error(err);
      if (err && err.deconnecte) {
        VueConnexion.connexion(vue, () => naviguer());
        return;
      }
      vue.innerHTML =
        '<div class="carte"><div class="carte-titre">Un problème est survenu</div>' +
        '<p style="margin:0 0 12px;font-size:13.5px;color:var(--encre-douce)">' +
        Utils.echapper(err && err.message ? err.message : "Erreur inattendue.") + "</p>" +
        '<button type="button" class="btn btn-clair" onclick="location.reload()">Recharger l\'application</button></div>';
    }
    vue.scrollTop = 0;
    const memorisee = retourEnArriere ? positions.get(ecran) : 0;
    if (memorisee) restaurerHauteur(memorisee);
    else window.scrollTo(0, 0);
  }

  /* ---------- Interactions globales ---------- */

  document.addEventListener("click", (ev) => {
    const nav = ev.target.closest("[data-nav]");
    if (nav) {
      location.hash = nav.dataset.nav;
      return;
    }
    const action = ev.target.closest("[data-action]");
    if (!action) return;
    if (action.dataset.action === "retour") {
      if (history.length > 1) history.back();
      else location.hash = "#/";
    }
    if (action.dataset.action === "fermer-feuille") UI.fermerFeuille();
    if (action.dataset.action === "fermer-visionneuse") UI.fermerVisionneuse();
  });

  document.addEventListener("keydown", (ev) => {
    if (ev.key === "Escape") {
      UI.fermerVisionneuse();
      UI.fermerFeuille();
    }
  });

  /* ---------- Démarrage ---------- */

  async function ouvrirApplication() {
    const vue = document.getElementById("vue");
    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>Ouverture du catalogue…</div>';
    try {
      await Store.init();
    } catch (err) {
      if (err && err.nonConfigure) {
        VueConnexion.configuration(vue);
        return;
      }
      vue.innerHTML =
        '<div class="carte"><div class="carte-titre">Base injoignable</div>' +
        '<p style="margin:0 0 12px;font-size:13.5px;color:var(--encre-douce)">' +
        Utils.echapper(err.message || "Impossible d'ouvrir la base en ligne.") + "</p>" +
        '<button type="button" class="btn" onclick="location.reload()">Réessayer</button></div>';
      return;
    }
    window.addEventListener("hashchange", naviguer);
    naviguer();
  }

  function demarrer() {
    if ("scrollRestoration" in history) history.scrollRestoration = "manual";
    const vue = document.getElementById("vue");

    if (!Supabase.estConfigure()) {
      VueConnexion.configuration(vue);
    } else if (!Supabase.sessionPresente()) {
      VueConnexion.connexion(vue, ouvrirApplication);
    } else {
      ouvrirApplication();
    }

    if ("serviceWorker" in navigator && !location.hostname.endsWith("appassets.androidx.dev")) {
      navigator.serviceWorker.register("sw.js").catch(() => { /* hors ligne au premier chargement */ });
    }
  }

  demarrer();
})();
