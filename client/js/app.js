/* =========================================================
   App — routeur par ancre (#/...), démarrage, mise à jour
   du catalogue, service worker, installation.
   ========================================================= */
const App = { evenementInstallation: null };

(() => {

  const ROUTES = [
    { motif: /^\/$/, vue: (v) => VueAccueil.afficher(v), onglet: "/" },
    { motif: /^\/categories$/, vue: (v) => VueCategories.liste(v), onglet: "/categories" },
    { motif: /^\/categorie\/([^/]+)$/, vue: (v, m, p) => VueCategories.rayon(v, m[1], p), onglet: "/categories" },
    { motif: /^\/promos$/, vue: (v) => VueCategories.promos(v) },
    { motif: /^\/produit\/([^/]+)$/, vue: (v, m) => VueProduit.afficher(v, m[1]) },
    { motif: /^\/recherche$/, vue: (v) => VueRecherche.afficher(v), onglet: "/recherche" },
    { motif: /^\/infos$/, vue: (v) => VueInfos.afficher(v), onglet: "/infos" },
  ];

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

  async function naviguer(options) {
    const { chemin, params } = lireHash();
    const conserverPosition = !!(options && options.conserverPosition);
    const vue = document.getElementById("vue");
    UI.fermerVisionneuse();
    VueAccueil.arreterSlider();

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
      vue.innerHTML =
        '<div class="carte"><div class="carte-titre">Un problème est survenu</div>' +
        '<p style="margin:0 0 12px;font-size:13.5px;color:var(--encre-douce)">' +
        Utils.echapper(err && err.message ? err.message : "Erreur inattendue.") + "</p>" +
        '<button type="button" class="btn btn-clair" onclick="location.reload()">Recharger l\'application</button></div>';
    }
    if (!conserverPosition) {
      vue.scrollTop = 0;
      window.scrollTo(0, 0);
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
