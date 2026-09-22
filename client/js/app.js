/* =========================================================
   App — routeur par ancre (#/...), démarrage, mise à jour
   du catalogue, service worker, installation.
   ========================================================= */
const App = { evenementInstallation: null };

(() => {

  /* « onglet » : celui qui s'allume dans la barre du bas. Quatre
     onglets pour tous les écrans — chacun dit sous lequel il se range.

     « sansOnglets » : les écrans de PARCOURS de la DA — une boutique, un
     produit, le panier, le paiement, la confirmation. Ils n'ont pas de
     barre du bas : un retour en haut, et une action en bas. */
  const ROUTES = [
    { motif: /^\/$/, vue: (v) => VueAccueil.afficher(v), onglet: "/" },
    /* « Nos boutiques » : la liste entière, qu'on ouvre depuis
       « Nos boutiques partenaires » sur l'accueil. */
    { motif: /^\/boutiques$/, vue: (v) => VueAccueil.boutiques(v), onglet: "/" },
    { motif: /^\/boutique\/([^/]+)$/, vue: (v, m, p) => VueAccueil.boutique(v, m[1], p),
      sansOnglets: true },
    { motif: /^\/categories$/, vue: (v) => VueCategories.liste(v), onglet: "/categories" },
    { motif: /^\/categorie\/([^/]+)$/, vue: (v, m, p) => VueCategories.rayon(v, m[1], p), onglet: "/categories" },
    { motif: /^\/promos$/, vue: (v) => VueCategories.promos(v), onglet: "/" },
    /* Les produits d'une boutique : l'onglet « Produits » de sa fiche y
       mène aussi, pour qui veut la liste entière avec ses tris. */
    { motif: /^\/produits$/, vue: (v) => VueProduits.afficher(v), onglet: "/" },
    { motif: /^\/produit\/([^/]+)$/, vue: (v, m) => VueProduit.afficher(v, m[1]),
      sansOnglets: true },
    /* La recherche n'est plus un onglet : c'est la barre-pilule de
       l'accueil, comme sur la DA. Elle se range donc sous « Accueil ». */
    { motif: /^\/recherche$/, vue: (v) => VueRecherche.afficher(v), onglet: "/" },
    /* Le panier traverse les boutiques : on y entre par le bouton de la
       barre du haut, et il ne porte que son action — « Passer la
       commande ». */
    { motif: /^\/panier$/, vue: (v) => VuePanier.afficher(v), sansOnglets: true },
    { motif: /^\/commande$/, vue: (v) => VuePanier.commander(v), sansOnglets: true },
    { motif: /^\/commande\/([^/]+)$/, vue: (v, m) => VuePanier.recu(v, m[1]), sansOnglets: true },
    { motif: /^\/mes-commandes$/, vue: (v) => VuePanier.mesCommandes(v), onglet: "/compte" },
    /* Le SAV : on y arrive depuis le reçu d'une commande payée, c'est
       là que le client est quand il constate le problème. */
    { motif: /^\/reclamations$/, vue: (v) => VueSAV.mesReclamations(v), onglet: "/compte" },
    { motif: /^\/reclamation\/([^/]+)$/, vue: (v, m) => VueSAV.fil(v, m[1]), onglet: "/compte" },
    /* Se connecter, c'est ouvrir son compte : l'onglet « Compte » reste
       allumé, sans quoi on croirait avoir quitté l'écran qu'on a pressé. */
    { motif: /^\/connexion$/, vue: (v) => VueCompte.connexion(v), onglet: "/compte" },
    /* Entrer par son numéro : au Bénin, beaucoup de clients ont un
       téléphone et pas d'adresse e-mail. */
    { motif: /^\/connexion-tel$/, vue: (v) => VueCompte.connexionTel(v), onglet: "/compte" },
    { motif: /^\/inscription$/, vue: (v) => VueCompte.inscription(v), onglet: "/compte" },
    { motif: /^\/mot-de-passe$/, vue: (v, m, p) => VueCompte.motDePasse(v, p), onglet: "/compte" },
    /* Là où ramène le lien de « Mot de passe oublié » (Compte.lireRetourEmail). */
    { motif: /^\/nouveau-mot-de-passe$/, vue: (v) => VueCompte.nouveauMotDePasse(v), onglet: "/compte" },
    { motif: /^\/compte$/, vue: (v) => VueCompte.monCompte(v), onglet: "/compte" },
    /* LES FAVORIS SONT UN ONGLET, comme sur la DA. */
    { motif: /^\/favoris$/, vue: (v) => VueFavoris.afficher(v), onglet: "/favoris" },
    /* Les notifications : ce qui vient d'arriver, et le doigt qui mène
       à l'opération concernée. */
    { motif: /^\/notifications$/, vue: (v) => VueNotifications.afficher(v), onglet: "/compte" },
    { motif: /^\/adresses$/, vue: (v) => VueFavoris.adresses(v), onglet: "/compte" },
    /* « À propos de BIZZOO » : ses contacts, ses réseaux, et le réglage
       de la base. On y entre par l'écran du compte. */
    { motif: /^\/infos$/, vue: (v) => VueInfos.afficher(v), onglet: "/compte" },
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
    /* La barre du bas se range AVANT que l'écran ne se dessine, et
       l'action du bas de l'écran quitté s'en va : « Ajouter au panier »
       ne doit pas survivre sur le panier. Chaque écran de parcours pose
       la sienne. */
    document.body.classList.toggle("sans-onglets", !!route.sansOnglets);
    UI.retirerAction();
    reglerContact(chemin);
    reglerOnglets();

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

    /* L'accueil BIZZOO ne parle d'aucune boutique en particulier ;
       l'écran d'une boutique parle de celle-là. C'est ici que la
       question se règle, avant que l'écran ne se dessine — la barre
       d'onglets, juste après, a besoin de la réponse. */
    /* « À propos de BIZZOO » parle de l'enseigne, même si l'on sort
       d'une boutique pour l'ouvrir : on y arrive par le compte, pas par
       la boutique, dont la fiche a son propre « À propos ». */
    /* « Catégories » aussi : c'est le menu de BIZZOO, le même partout.
       Entré dans une boutique puis passé à cet onglet, on ne doit pas
       tomber sur les seuls rayons de la boutique quittée. */
    if (chemin === "/" || chemin === "/infos" || chemin === "/categories") {
      Catalogue.quitterBoutique();
    }
    const laBoutique = /^\/boutique\/([^/]+)$/.exec(chemin);
    if (laBoutique) Catalogue.choisirBoutique(laBoutique[1]);

    const produit = /^\/produit\/([^/]+)$/.exec(chemin);
    if (produit) {
      const p = Catalogue.produit(produit[1]);
      if (p && p.boutiqueId) Catalogue.choisirBoutique(p.boutiqueId);
    }
    /* UNE CATÉGORIE N'APPARTIENT PLUS À UNE BOUTIQUE : c'est la liste
       de l'enseigne, et « Mode & Vêtements » traverse tous les
       commerces qui s'y rangent. Entrer dans l'une d'elles en ouvrant
       un rayon cacherait les autres — c'est l'inverse de ce que cet
       écran sert à montrer.

       Les PROMOTIONS non plus n'entrent plus d'autorité dans la
       première boutique : la rubrique des bonnes affaires est celle de
       BIZZOO, elle doit les réunir toutes. Dans une boutique, elle
       reste la sienne. */
  }

  /* ---------- Les quatre onglets de la DA ----------
     Accueil, Catégories, Favoris, Compte : les mêmes partout.

     « ACCUEIL » RAMÈNE À BIZZOO, TOUJOURS. L'ancienne barre gardait le
     client dans la boutique où il était entré — « Accueil » y menait à
     la vitrine de la boutique, et un onglet BIZZOO servait à en sortir.
     La DA n'a plus ce double sens : la fiche d'une boutique est un écran
     de parcours, avec son retour en haut, et « Accueil » est celui de
     l'enseigne. Une boutique partagée par lien s'ouvre toujours sur sa
     fiche ; c'est seulement la sortie qui mène désormais à toutes les
     autres.

     « Catégories » est le menu de BIZZOO, et il l'est partout : la
     liste est celle de l'enseigne, la même pour tout le monde. */

  /* Est-on CHEZ quelqu'un ? En boutique unique, toujours : il n'y a pas
     d'accueil d'enseigne où se tenir. */
  const enBoutique = () =>
    !Catalogue.multiBoutiques() || !!Catalogue.boutiqueChoisie();

  function reglerOnglets() {
    const accueil = document.querySelector('#tabbar a[data-tab="/"]');
    if (accueil) accueil.href = "#/";
  }

  /* ---------- « Nous contacter » ----------
     Le bouton WhatsApp flottant, sur les écrans d'UNE boutique : sa
     fiche, ses produits. Le numéro venant du catalogue, on repose le
     lien à chaque écran plutôt que de le figer dans la page : il suit
     une mise à jour des réglages sans qu'on ait à rouvrir l'application.

     Le contact de BIZZOO, lui, n'est plus un onglet : la barre de la DA
     en compte quatre, et il vit sous « Compte ». */

  function reglerContact(chemin) {
    const flottant = document.getElementById("contact-flottant");
    const maison = Catalogue.enseigne();

    /* SUR LES ÉCRANS DE LA BOUTIQUE SEULEMENT. Ailleurs — le panier qui
       mêle plusieurs boutiques, les catégories de l'enseigne — le bouton
       écrirait à la dernière boutique visitée, qui n'a peut-être rien à
       voir avec ce que le client regarde. */
    const flotte = enBoutique() &&
      /^\/(boutique\/[^/]+|produit\/[^/]+|produits)$/.test(chemin || "");

    /* ---------- À QUI l'on écrit ----------
       Le bouton vu DANS une boutique écrit à CETTE boutique : le client
       qui le presse sur une fiche produit veut parler au commerçant qui
       l'a en rayon, pas à l'enseigne. Celui de l'accueil BIZZOO, lui,
       écrit à l'enseigne — c'est chez elle qu'on se trouve.

       En boutique unique, la boutique EST l'enseigne : rien à
       distinguer. */
    const chez = Catalogue.boutiqueChoisie();

    /* Le bouton flottant écrit à la boutique, ET À PERSONNE D'AUTRE.
       Une boutique qui n'a pas renseigné de numéro n'a pas de bouton :
       le rabattre sur l'enseigne ferait croire au client qu'il écrit au
       commerçant, et le message partirait ailleurs.

       En boutique unique, la boutique EST l'enseigne : c'est son numéro
       qu'on emploie, et il n'y a rien à distinguer. */
    const qui = chez
      ? { numero: chez.whatsapp || chez.tel || "", indicatif: chez.indicatif || maison.indicatif,
          nom: chez.nom }
      : { numero: maison.whatsapp, indicatif: maison.indicatif, nom: maison.nom };

    const adresser = (a) => Utils.lienWhatsApp(
      a.numero, "Bonjour " + a.nom + ", je souhaite un renseignement.", a.indicatif);

    if (flottant) {
      flottant.hidden = !flotte || !qui.numero;
      if (qui.numero) {
        flottant.href = adresser(qui);
        flottant.setAttribute("aria-label", "Écrire à " + qui.nom + " sur WhatsApp");
      }
    }
  }

  /* ---------- Interactions globales ---------- */

  /* Accueil ramène toujours en début de page. Deux raisons de s'en
     occuper à la main : si l'on y est déjà, l'adresse ne change pas et
     rien ne se redessine ; et si l'on en revient, la position de
     lecture mémorisée reprendrait la main. */
  document.addEventListener("click", (ev) => {
    const accueil = ev.target.closest('#tabbar a[data-tab="/"]');
    if (!accueil) return;
    /* L'écran visé n'est plus toujours « #/ » : dans une boutique,
       Accueil ramène à sa vitrine. On oublie la position mémorisée de
       CELUI-LÀ, sans quoi on retomberait au milieu de la page. */
    const vise = accueil.getAttribute("href") || "#/";
    positions.delete(vise);
    requestAnimationFrame(() => window.scrollTo(0, 0));
  });

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
    /* LE RETOUR D'UN LIEN REÇU PAR E-MAIL, lu avant tout le reste : le
       jeton quitte la barre d'adresse sur-le-champ, et le premier écran
       dessiné est le bon — « Nouveau mot de passe », pas l'accueil. */
    if (typeof Compte !== "undefined") Compte.lireRetourEmail();

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

    /* Les prix de ce compte-ci. Un revendeur validé achète au prix
       BIZZOO : la base les lui sert, et l'écran se redessine tout seul
       quand ils arrivent. Personne d'autre n'en reçoit — la base répond
       zéro ligne à tous les autres comptes. */
    if (typeof Compte !== "undefined" && Compte.connecte()) {
      Compte.charger(true)
        .then(() => Compte.chargerPrix())
        .catch(() => { /* hors connexion : le catalogue local suffit */ });
    }

    /* Les réglages du paiement : la clé publique de KkiaPay vit en base,
       pour qu'on puisse passer des essais à la production sans
       reconstruire l'application. Sans réponse, le panier reste ouvert
       et la commande part sur WhatsApp comme avant. */
    Paiement.charger();

    /* Et la règle de la maison : faut-il un compte pour commander ?
       Elle vit en base pour la même raison — l'enseigne la bascule
       depuis son application, sans qu'on republie celle-ci. On la lit
       dès l'ouverture, pour que l'écran de commande soit le bon du
       premier coup et non après un aller-retour sous les doigts. */
    if (typeof Compte !== "undefined") {
      Compte.chargerRegles().catch(() => { /* hors connexion : la dernière connue */ });
    }

    /* ---------- Les notifications ----------
       Elles ne tournent que pour un compte connecté : sans compte, la
       base n'a personne à prévenir. On les démarre à l'ouverture et à
       chaque connexion, on les ARRÊTE à la déconnexion — sans quoi un
       socket resterait ouvert au nom de quelqu'un qui est parti, et la
       cloche garderait le compte du précédent. */
    if (typeof Notifs !== "undefined" && typeof Compte !== "undefined") {
      const suivreLeCompte = () => {
        if (Compte.connecte()) Notifs.demarrer();
        else Notifs.arreter();
        UI.majCloche();
      };
      /* La cloche vit dans la barre du haut, redessinée à chaque écran :
         on passe par un événement plutôt que d'aller la chercher. */
      Notifs.surChangement(() =>
        document.dispatchEvent(new CustomEvent("notifs:maj")));
      Compte.surChangement(suivreLeCompte);
      suivreLeCompte();
    }

    /* Les favoris, lus une fois à l'ouverture. Sans cela, le premier
       écran afficherait des cœurs vides sur des produits déjà mis de
       côté — et le client en toucherait un pour le RETIRER en croyant
       l'ajouter. On ne bloque pas le démarrage pour autant : un réseau
       lent ne doit pas retarder le catalogue. */
    if (typeof Favoris !== "undefined") {
      Favoris.charger().catch(() => { /* on réessaiera à la connexion */ });
      /* Quand la liste change, les cœurs déjà à l'écran se repeignent :
         la même fiche peut être ouverte à deux endroits — la grille et
         la rangée « Nouveautés » —, et deux cœurs contradictoires sur
         un même produit passent pour un défaut. */
      Favoris.surChangement(() => {
        document.querySelectorAll("[data-coeur]").forEach((b) => {
          const garde = Favoris.aProduit(b.dataset.coeur);
          b.classList.toggle("coeur-plein", garde);
          b.setAttribute("aria-pressed", garde ? "true" : "false");
        });
      });
    }

    /* Le catalogue se met à jour tout seul (temps réel + vérifications). */
    Live.demarrer();

    /* Le service worker sert les fichiers depuis son cache AVANT le
       réseau : c'est ce qui rend le catalogue consultable hors connexion.
       Sur une adresse locale c'est un piège — on modifie un fichier, on
       recharge, et l'ancien réapparaît. On ne l'installe donc pas, et on
       retire celui qu'une visite précédente aurait laissé : sinon il
       continuerait de servir ses vieux fichiers sans qu'on comprenne. */
    const enLocal = ["localhost", "127.0.0.1", "::1"]
      .includes(location.hostname.replace(/^\[|\]$/g, ""));
    if ("serviceWorker" in navigator && !location.hostname.endsWith("appassets.androidx.dev")) {
      if (enLocal) {
        navigator.serviceWorker.getRegistrations()
          .then((liste) => liste.forEach((sw) => sw.unregister()))
          .catch(() => { /* rien à retirer */ });
      } else {
        navigator.serviceWorker.register("sw.js").catch(() => { /* hors ligne au premier chargement */ });
      }
    }
  }

  demarrer();
})();
