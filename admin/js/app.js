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
    { motif: /^\/boutiques$/, vue: (v) => VueBoutiques.afficher(v), super: true },
    { motif: /^\/slider$/, vue: (v) => VueSlider.afficher(v), admin: true },
    { motif: /^\/validations$/, vue: (v) => VueValidations.afficher(v), super: true },
    { motif: /^\/historique$/, vue: (v) => VueHistorique.afficher(v), admin: true },
    { motif: /^\/comptes$/, vue: (v) => VueComptes.afficher(v), admin: true },
    { motif: /^\/compte$/, vue: (v) => VueComptes.monCompte(v), onglet: "/compte" },
    { motif: /^\/reglages$/, vue: (v, m, p) => VueReglages.afficher(v, p), onglet: "/reglages", admin: true },
  ];

  /* ---------- Ce que le compte a le droit de voir ----------
     Le modérateur s'occupe des produits et des catégories ; les
     réglages, les comptes et l'historique restent à l'administrateur.
     Le tri se fait aussi dans la base (règles RLS) : masquer un écran
     n'est ici qu'une politesse, pas la serrure. */

  function adapterAuRole() {
    const admin = Supabase.estAdmin();
    for (const el of document.querySelectorAll("[data-acces]")) {
      el.style.display = (el.dataset.acces === "administrateur") === admin ? "" : "none";
    }
  }


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

  /* Les écrans se dessinent l'un après l'autre. Sans cette file, deux
     navigations rapprochées — un renvoi automatique suivi d'un appui, par
     exemple — se chevauchent, et la plus lente écrase la plus récente. */
  let file = Promise.resolve();

  function naviguer() {
    file = file.then(dessinerEcran).catch((err) => { console.error(err); });
    return file;
  }

  async function dessinerEcran() {
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
    if (route.super && !Supabase.estSuper()) {
      UI.toast("Cet écran est réservé au super administrateur.", "err");
      location.hash = "#/";
      return;
    }
    if (route.admin && !Supabase.estAdmin()) {
      UI.toast("Cet écran est réservé à l'administrateur.", "err");
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
      if (err && err.deconnecte) {   // session périmée : on redemande le mot de passe
        VueConnexion.connexion(vue, ouvrirApplication);
        return;
      }
      vue.innerHTML =
        '<div class="carte"><div class="carte-titre">Base injoignable</div>' +
        '<p style="margin:0 0 12px;font-size:13.5px;color:var(--encre-douce)">' +
        Utils.echapper(err.message || "Impossible d'ouvrir la base en ligne.") + "</p>" +
        '<button type="button" class="btn" onclick="location.reload()">Réessayer</button></div>';
      return;
    }
    adapterAuRole();
    if (!Supabase.compteActif()) {
      compteEnAttente(vue);
      return;
    }
    /* Un administrateur ou un modérateur sans boutique n'a de prise sur
       rien : mieux vaut un écran qui l'explique qu'une application à
       moitié morte — ou pire, des produits créés hors de toute boutique. */
    if (!Supabase.estSuper() && Store.listerBoutiques().length && !Store.boutiqueCourante()) {
      compteSansBoutique(vue);
      return;
    }
    window.addEventListener("hashchange", naviguer);
    naviguer();
  }

  /** Compte actif, mais rattaché à aucune boutique existante. */
  function compteSansBoutique(vue) {
    document.getElementById("tabbar").style.display = "none";
    UI.entete({ titre: "Boutique à confier" });
    vue.innerHTML =
      '<div class="carte"><div class="carte-titre">Ce compte n\'a pas encore de boutique</div>' +
      '<p class="aide" style="margin:0 0 14px">Votre compte <strong>' +
        Utils.echapper(Supabase.utilisateur() || "") + "</strong> est bien actif, mais aucune " +
        "boutique ne lui est confiée : il n'a donc rien à gérer pour l'instant.</p>" +
      '<p class="aide" style="margin:0 0 14px">Deux cas possibles :<br>' +
        "• un <strong>super administrateur</strong> doit lui confier une boutique " +
        "(Comptes → crayon → Boutique confiée) ;<br>" +
        "• si ce compte était <strong>administrateur avant les boutiques multiples</strong>, " +
        "il doit exécuter le dernier fichier SQL dans Supabase pour le faire monter " +
        "en super administrateur.</p>" +
      '<div class="btn-rangee">' +
        '<button type="button" class="btn" onclick="location.reload()">Réessayer</button>' +
        '<button type="button" class="btn btn-clair" id="attente-deconnexion">Se déconnecter</button>' +
      "</div></div>";
    UI.$("#attente-deconnexion").onclick = async () => {
      await Supabase.deconnexion();
      location.reload();
    };
  }

  /** Compte créé mais pas encore activé par l'administrateur. */
  function compteEnAttente(vue) {
    document.getElementById("tabbar").style.display = "none";
    UI.entete({ titre: "Compte en attente" });
    vue.innerHTML =
      '<div class="carte"><div class="carte-titre">Ce compte n\'est pas encore activé</div>' +
      '<p class="aide" style="margin:0 0 14px">Votre compte <strong>' +
        Utils.echapper(Supabase.utilisateur() || "") + "</strong> existe, mais l'administrateur " +
        "de la boutique doit encore lui donner ses droits. Demandez-lui de l'activer " +
        "dans Comptes.</p>" +
      '<button type="button" class="btn btn-clair" id="attente-deconnexion">Se déconnecter</button></div>';
    UI.$("#attente-deconnexion").onclick = async () => {
      await Supabase.deconnexion();
      location.reload();
    };
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
