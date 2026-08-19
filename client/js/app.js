/* =========================================================
   App — routeur par ancre (#/...), démarrage, mise à jour
   du catalogue, service worker, installation.
   ========================================================= */
const App = { evenementInstallation: null };

(() => {

  const ROUTES = [
    { motif: /^\/$/, vue: (v) => VueAccueil.afficher(v), onglet: "/" },
    { motif: /^\/boutique\/([^/]+)$/, vue: (v, m) => VueAccueil.boutique(v, m[1]), onglet: "/" },
    { motif: /^\/categories$/, vue: (v) => VueCategories.liste(v), onglet: "/categories" },
    { motif: /^\/categorie\/([^/]+)$/, vue: (v, m, p) => VueCategories.rayon(v, m[1], p), onglet: "/categories" },
    { motif: /^\/promos$/, vue: (v) => VueCategories.promos(v) },
    { motif: /^\/produit\/([^/]+)$/, vue: (v, m) => VueProduit.afficher(v, m[1]) },
    { motif: /^\/recherche$/, vue: (v) => VueRecherche.afficher(v), onglet: "/recherche" },
    { motif: /^\/infos$/, vue: (v) => VueInfos.afficher(v), onglet: "/infos" },
  ];


  /* ---------- Mémoire de la position de lecture ----------
     Le client parcourt une longue liste, ouvre un produit, revient :
     il doit retrouver sa place exacte, pas le haut de la page. */

  const positions = new Map();   // adresse d'écran -> hauteur de défilement
  let indexCourant = -1;         // rang de l'écran affiché dans l'historique
  let compteurHistorique = 0;
  let ecranQuitte = null;

  const hauteurActuelle = () =>
    window.scrollY || document.documentElement.scrollTop || 0;

  /**
   * Replace l'écran à la hauteur voulue. Les photos peuvent arriver
   * après coup : on réapplique quelques fois, puis on lâche.
   */
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

  /* Les écrans se dessinent l'un après l'autre : deux navigations
     rapprochées ne se chevauchent pas, et la dernière demandée gagne. */
  let file = Promise.resolve();

  function naviguer(options) {
    file = file.then(() => dessinerEcran(options)).catch((err) => { console.error(err); });
    return file;
  }

  async function dessinerEcran(options) {
    const { chemin, params } = lireHash();
    const conserverPosition = !!(options && options.conserverPosition);
    const vue = document.getElementById("vue");
    const ecran = location.hash || "#/";

    /* Retenir où en était l'écran que l'on quitte. */
    if (!conserverPosition && ecranQuitte && ecranQuitte !== ecran) {
      positions.set(ecranQuitte, hauteurActuelle());
    }

    /* Chaque entrée d'historique reçoit un rang : un rang plus petit
       que le précédent, c'est que le client est revenu en arrière. */
    let retourEnArriere = false;
    if (!conserverPosition) {
      const etat = history.state;
      if (etat && typeof etat.rang === "number") {
        retourEnArriere = etat.rang < indexCourant;
        indexCourant = etat.rang;
      } else {
        indexCourant = ++compteurHistorique;
        try { history.replaceState({ rang: indexCourant }, ""); } catch (_) { /* sans importance */ }
      }
      ecranQuitte = ecran;
    }
    UI.fermerVisionneuse();
    VueAccueil.arreterSlider();

    const route = ROUTES.find((r) => r.motif.test(chemin));
    if (!route) {
      location.hash = "#/";
      return;
    }
    reglerBoutique(chemin);

    for (const lien of document.querySelectorAll("#tabbar [data-tab]")) {
      lien.classList.toggle("actif", lien.dataset.tab === (route.onglet || ""));
    }

    try {
      await route.vue(vue, chemin.match(route.motif), params);
    } catch (err) {
      console.error(err);
      vue.innerHTML =
        '<div class="carte"><div class="carte-titre">Un problème est survenu</div>' +
        '<p style="margin:0 0 12px;font-size:13.5px;color:var(--encre-douce)">' +
        Utils.echapper(err && err.message ? err.message : "Erreur inattendue.") + "</p>" +
        '<button type="button" class="btn btn-clair" onclick="location.reload()">Recharger l\'application</button></div>';
    }
    if (!conserverPosition) {
      vue.scrollTop = 0;
      const memorisee = retourEnArriere ? positions.get(ecran) : 0;
      if (memorisee) restaurerHauteur(memorisee);
      else window.scrollTo(0, 0);
    }
  }

  /* ---------- La boutique du moment ----------
     Un lien direct — un produit partagé sur WhatsApp, un rayon mis en
     favori — doit ouvrir le bon écran même si le client visitait une
     autre boutique. On déduit donc la boutique de ce qui est affiché ;
     et si rien ne l'indique, on entre dans la première ouverte plutôt
     que de laisser un écran vide. */

  function reglerBoutique(chemin) {
    if (!Catalogue.multiBoutiques()) return;

    const produit = /^\/produit\/([^/]+)$/.exec(chemin);
    if (produit) {
      const p = Catalogue.produit(produit[1]);
      if (p && p.boutiqueId) Catalogue.choisirBoutique(p.boutiqueId);
    }
    const rayon = /^\/categorie\/([^/]+)$/.exec(chemin);
    if (rayon) {
      const c = Catalogue.categorie(rayon[1]);
      if (c && c.boutiqueId) Catalogue.choisirBoutique(c.boutiqueId);
    }

    /* Les onglets Catégories, Recherche et Infos parlent forcément
       d'une boutique : à défaut de choix, ce sera la première. */
    if (/^\/(categories|recherche|infos|promos)$/.test(chemin) && !Catalogue.boutiqueChoisie()) {
      const premiere = Catalogue.boutiques()[0];
      if (premiere) Catalogue.choisirBoutique(premiere.id);
    }
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
    if (action.dataset.action === "fermer-visionneuse") UI.fermerVisionneuse();
  });

  document.addEventListener("keydown", (ev) => {
    if (ev.key === "Escape") UI.fermerVisionneuse();
  });

  document.addEventListener("click", async (ev) => {
    if (!ev.target.closest("#visionneuse-telecharger")) return;
    const photo = UI.photoVisionneuse();
    if (!photo) return;
    try {
      await Utils.telechargerImage(photo.src, photo.nom);
      UI.toast("Photo enregistrée dans Téléchargements", "ok");
    } catch (err) {
      UI.toast(err.message || "Téléchargement impossible", "err");
    }
  });

  window.addEventListener("beforeinstallprompt", (ev) => {
    ev.preventDefault();
    App.evenementInstallation = ev;
  });

  /* Quand une version plus récente du catalogue arrive du réseau :
     on redessine l'écran sans faire perdre sa place au client. */
  document.addEventListener("catalogue:maj", async () => {
    const hauteur = window.scrollY || document.documentElement.scrollTop || 0;
    await naviguer({ conserverPosition: true });
    if (hauteur) window.scrollTo(0, hauteur);
    UI.toast("Catalogue mis à jour", "ok");
  });

  /* ---------- Démarrage ---------- */

  function ecranErreur() {
    document.getElementById("vue").innerHTML =
      '<div class="vide">' + UI.icone("wifi") +
        "<p>Impossible de charger le catalogue</p>" +
        "<small>Vérifiez votre connexion internet puis réessayez. " +
        "Une fois chargé, le catalogue reste consultable hors connexion.</small>" +
        '<button type="button" class="btn" onclick="location.reload()">' +
          UI.icone("actualiser") + "Réessayer</button>" +
      "</div>";
  }

  async function demarrer() {
    /* Le navigateur ne se mêle pas du défilement : l'application gère. */
    if ("scrollRestoration" in history) history.scrollRestoration = "manual";
    UI.entete({ accueil: true });
    document.getElementById("vue").innerHTML =
      '<div class="chargement"><span class="chargement-rond"></span>Chargement du catalogue…</div>';

    const ok = await Catalogue.charger();
    if (!ok) {
      ecranErreur();
      window.addEventListener("hashchange", () => location.reload(), { once: true });
      return;
    }

    window.addEventListener("hashchange", () => naviguer());
    naviguer();

    /* Le catalogue se met à jour tout seul (temps réel + vérifications). */
    Live.demarrer();

    if ("serviceWorker" in navigator && !location.hostname.endsWith("appassets.androidx.dev")) {
      navigator.serviceWorker.register("sw.js").catch(() => { /* hors ligne au premier chargement */ });
    }
  }

  demarrer();
})();
