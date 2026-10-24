/* =========================================================
   App — le chef d'orchestre de BIZZOO Personnel.

   Au démarrage : la session, puis le tableau de bord (« qui suis-je,
   et qu'est-ce qui m'attend ? ») en un seul appel. Le menu ne montre
   que ce que le rang de chacun lui ouvre ; la base, elle, refuse le
   reste quoi que montre l'écran.

   Routes : #/<vue>/<paramètre>, par exemple #/missions/<id>.
   ========================================================= */
const App = (() => {

  let tableau = null;          // la réponse de rh_tableau_de_bord()
  /* Les menus que le menu Paramètres ouvre à mes profils (rh_mes_menus). */
  let menus = [];
  let routeCourante = "";
  let minuterie = null;

  const moi = () => (tableau && tableau.moi) || null;
  const compteurs = () => (tableau && tableau.compteurs) || {};
  const estCeo = () => !!(moi() && moi().ceo);
  const estAdmin = () => !!(moi() && moi().administration);
  const peutDecaisser = () => !!(moi() && moi().peut_decaisser);
  const responsableDe = (profil) => !!(moi() && (moi().responsable_de || []).includes(profil));
  const estResponsable = () => !!(moi() && (moi().responsable_de || []).length);
  /** Ce menu m'est-il ouvert ? L'administration a tout ; la base refuse le reste. */
  const ouvert = (cle) => estAdmin() || menus.includes(cle);
  const voitSuivi = () => ouvert("suivi");
  /* Les commandes en alerte : la pastille du suivi. */
  let alertesSuivi = 0;
  /** Les sous-menus des statistiques ouverts à ce compte (leurs clés). */
  const sousMenusStatistiques = () =>
    VueStatistiques.SOUS_MENUS.map((s) => s.cle).filter((c) => ouvert("stats_" + c));
  const voitStatistiques = () => sousMenusStatistiques().length > 0;

  /* ---------- Les écrans ---------- */
  const VUES = {
    "": VueAccueil, accueil: VueAccueil,
    mails: VueMails,
    discussions: VueDiscussions,
    missions: VueMissions,
    rapports: VueRapports,
    depenses: VueDepenses,
    employes: VueEmployes,
    profils: VueProfils,
    paie: VuePaie,
    statistiques: VueStatistiques,
    suivi: VueSuivi,
    parametres: VueParametres,
    compte: VueCompte,
  };

  /** Le menu : route, libellé, icône, pour qui, et la pastille. */
  function menu() {
    const c = compteurs();
    return [
      { route: "accueil", libelle: "Accueil", icone: "accueil" },
      { route: "mails", libelle: "Mails", icone: "mail", pour: () => ouvert("mails") },
      { route: "discussions", libelle: "Discussions", icone: "bulle", pour: () => ouvert("discussions"),
        pastille: c.messages_non_lus },
      { route: "missions", libelle: "Missions", icone: "mission", pour: () => ouvert("missions"),
        pastille: (c.missions_a_repondre || 0) + (c.missions_a_cloturer || 0) },
      { route: "rapports", libelle: "Rapports", icone: "rapport", pour: () => ouvert("rapports"),
        pastille: c.rapports_a_valider },
      { route: "depenses", libelle: "Dépenses", icone: "argent",
        pour: () => ouvert("depenses") || peutDecaisser(),
        pastille: (c.depenses_a_approuver || 0) + (c.depenses_a_decaisser || 0) },
      { route: "suivi", libelle: "Suivi commandes", icone: "suivi", pour: voitSuivi, pastille: alertesSuivi },
      { route: "statistiques", libelle: "Statistiques", icone: "stats", pour: voitStatistiques },
      /* Ouvert à un profil, « Employés » n'est que l'annuaire, en lecture. */
      { route: "employes", libelle: estAdmin() ? "Employés" : "Annuaire", icone: "equipe", pour: () => ouvert("employes"),
        pastille: c.employes_a_valider, groupe: estAdmin() ? "Administration" : undefined },
      { route: "profils", libelle: "Profils", icone: "profils", pour: estAdmin },
      { route: "paie", libelle: "Paie", icone: "paie", pour: () => estAdmin() || peutDecaisser(),
        pastille: (c.fiches_a_valider || 0) + (c.baremes_a_valider || 0) + (c.fiches_a_payer || 0) },
      { route: "parametres", libelle: "Paramètres", icone: "reglages", pour: estAdmin },
      { route: "compte", libelle: "Mon compte", icone: "personne", groupe: "Moi" },
    ].filter((m) => !m.pour || m.pour());
  }

  const { h } = UI;
  const pastille = (n) => (n > 0 ? h("span", { class: "pastille" }, n > 99 ? "99+" : n) : null);

  function dessinerMenus() {
    const items = menu();
    const lateral = document.getElementById("menu-lateral");
    let groupe = "";
    UI.vider(lateral,
      h("a", { class: "logo", href: "#/" }, h("img", { src: "icons/icon-192.png", alt: "" }),
        h("span", {}, h("b", {}, "BIZZOO"), h("small", {}, "Personnel"))),
      items.map((m) => {
        const titre = m.groupe && m.groupe !== groupe ? h("div", { class: "titre-groupe" }, m.groupe) : null;
        if (m.groupe) groupe = m.groupe;
        const lien = h("a", { href: "#/" + m.route, "data-route": m.route },
          UI.icone(m.icone), m.libelle, pastille(m.pastille));
        /* Les sous-menus des statistiques, visibles quand on y est. */
        const sous = m.route === "statistiques"
          ? VueStatistiques.SOUS_MENUS.filter((x) => sousMenusStatistiques().includes(x.cle)).map((x) =>
            h("a", { class: "sous", href: "#/statistiques/" + x.cle, "data-sous": "statistiques/" + x.cle }, x.libelle))
          : [];
        return [titre, lien, sous];
      }),
      h("div", { class: "pied" }, UI.nomComplet(moi()), h("br"), h("span", { class: "tres-petit" },
        estCeo() ? "CEO" : estAdmin() ? "Administration" : (moi() && moi().profil) || "")));

    /* Sur téléphone, cinq onglets : les quatre premiers, puis « Plus ». */
    const onglets = document.getElementById("onglets");
    const principaux = items.filter((m) => ["accueil", "mails", "discussions", "missions"].includes(m.route));
    const autres = items.filter((m) => !principaux.includes(m));
    const pastilleAutres = autres.reduce((s, m) => s + (m.pastille || 0), 0);
    UI.vider(onglets,
      principaux.map((m) => h("a", { href: "#/" + m.route, "data-route": m.route },
        UI.icone(m.icone), m.libelle, pastille(m.pastille))),
      h("a", { href: "#/plus", "data-route": "plus" }, UI.icone("menu"), "Plus", pastille(pastilleAutres)));
    marquerActif();
  }

  function marquerActif() {
    const r = routeCourante || "accueil";
    document.querySelectorAll("[data-route]").forEach((a) => {
      a.classList.toggle("actif", a.dataset.route === r);
    });
    const { morceaux } = lireRoute();
    const ici = r + "/" + (morceaux[0] || "");
    document.querySelectorAll("[data-sous]").forEach((a) => {
      a.hidden = r !== "statistiques";
      a.classList.toggle("actif", a.dataset.sous === ici);
    });
  }

  /** Le menu « Plus » du téléphone : tout ce qui n'a pas d'onglet. */
  const VuePlus = {
    titre: "Plus",
    afficher(zone) {
      const items = menu().filter((m) => !["accueil", "mails", "discussions", "missions"].includes(m.route));
      UI.vider(zone, h("div", { class: "liste" }, items.map((m) =>
        h("a", { class: "element", href: "#/" + m.route }, UI.icone(m.icone),
          h("span", { class: "etire gras" }, m.libelle), pastille(m.pastille), UI.icone("chevron", "ic-sm")))));
    },
  };

  /* ---------- Navigation ---------- */

  function lireRoute() {
    const brut = (location.hash || "#/").replace(/^#\/?/, "");
    const [chemin, requete] = brut.split("?");
    const morceaux = chemin.split("/").filter(Boolean).map(decodeURIComponent);
    const params = Object.fromEntries(new URLSearchParams(requete || ""));
    return { route: morceaux[0] || "", morceaux: morceaux.slice(1), params };
  }

  async function naviguer() {
    if (!tableau || !moi()) return;
    const { route, morceaux, params } = lireRoute();
    routeCourante = route || "accueil";
    const vue = route === "plus" ? VuePlus : VUES[route];
    const zone = document.getElementById("contenu");
    /* Une zone neuve à chaque navigation : une vue quittée pendant son
       chargement écrit dans SA zone, détachée, jamais dans la suivante. */
    const neuve = h("main", { class: "vue", id: "contenu", tabindex: "-1" });
    zone.replaceWith(neuve);
    marquerActif();
    const titre = document.getElementById("titre");
    const retour = document.getElementById("bouton-retour");
    retour.hidden = morceaux.length === 0;
    if (!vue || (route && !menu().some((m) => m.route === route) && route !== "plus")) {
      titre.textContent = "Introuvable";
      UI.vider(neuve, UI.vide("Cette page n'existe pas, ou votre compte n'y a pas accès."));
      return;
    }
    titre.textContent = vue.titre || "BIZZOO Personnel";
    window.scrollTo(0, 0);
    try {
      await vue.afficher(neuve, morceaux, params);
    } catch (err) {
      if (err && err.deconnecte) return deconnecte();
      if (neuve.isConnected) UI.vider(neuve, UI.erreur(err));
    }
  }

  /** Une vue change le titre de l'en-tête (le nom d'un employé, d'une mission). */
  function titre(texte) {
    document.getElementById("titre").textContent = texte;
  }

  /* ---------- Le tableau de bord ---------- */

  async function rafraichir() {
    try {
      tableau = await Supabase.rpc("rh_tableau_de_bord");
      if (tableau && tableau.moi) await chargerMenus();
      if (tableau && tableau.moi && voitSuivi()) {
        alertesSuivi = await Supabase.rpc("rh_suivi_alertes_nb").catch(() => alertesSuivi);
      }
      if (tableau && tableau.moi) dessinerMenus();
    } catch (err) {
      if (err && err.deconnecte) deconnecte();
    }
    return tableau;
  }

  /** Les menus ouverts par le menu Paramètres. Base pas encore à jour :
      les menus d'avant, sans suivi ni statistiques. */
  async function chargerMenus() {
    if (estAdmin()) return;
    try {
      menus = (await Supabase.rpc("rh_mes_menus")) || [];
    } catch (err) {
      if (err && err.deconnecte) throw err;
      menus = ["mails", "discussions", "missions", "rapports"].concat(estResponsable() ? ["depenses"] : []);
    }
  }

  function deconnecte() {
    clearInterval(minuterie);
    tableau = null;
    Supabase.deconnexion();
    demarrer();
  }

  async function demarrer() {
    const zone = document.getElementById("contenu");
    const connecte = Supabase.sessionPresente() && await Supabase.assurerSession();
    document.body.classList.toggle("connecte", !!connecte);
    for (const id of ["entete", "onglets", "menu-lateral"]) document.getElementById(id).hidden = !connecte;
    if (!connecte) {
      VueConnexion.afficher(zone, demarrer);
      return;
    }
    UI.vider(zone, UI.chargement());
    try {
      tableau = await Supabase.rpc("rh_tableau_de_bord");
    } catch (err) {
      if (err && err.deconnecte) return deconnecte();
      UI.vider(zone, UI.erreur(err), h("button", { class: "btn btn-second", onclick: demarrer }, "Réessayer"));
      return;
    }
    if (!tableau || !tableau.moi) {
      for (const id of ["entete", "onglets", "menu-lateral"]) document.getElementById(id).hidden = true;
      document.body.classList.remove("connecte");
      VueConnexion.sansFiche(zone, tableau || {}, demarrer, deconnecte);
      return;
    }
    menus = [];
    alertesSuivi = 0;
    await chargerMenus();
    if (voitSuivi()) alertesSuivi = await Supabase.rpc("rh_suivi_alertes_nb").catch(() => 0);
    dessinerMenus();
    /* La paie de fin de mois se rattrape à l'ouverture si personne ne
       l'a faite (et si pg_cron n'est pas là pour la faire). */
    if (estAdmin()) Supabase.rpc("rh_paie_a_jour").then((n) => { if (n > 0) rafraichir(); }).catch(() => {});
    clearInterval(minuterie);
    minuterie = setInterval(rafraichir, 60000);
    naviguer();
  }

  document.getElementById("bouton-retour").addEventListener("click", () => {
    const { route } = lireRoute();
    location.hash = "#/" + (route || "");
  });
  document.getElementById("bouton-actualiser").addEventListener("click", async () => {
    await rafraichir();
    naviguer();
  });
  window.addEventListener("hashchange", naviguer);

  if ("serviceWorker" in navigator && location.protocol === "https:") {
    navigator.serviceWorker.register("sw.js").catch(() => {});
  }

  demarrer();

  return {
    moi, compteurs, estCeo, estAdmin, peutDecaisser, responsableDe, estResponsable, ouvert, sousMenusStatistiques,
    rafraichir, naviguer, titre, deconnecte, demarrer,
  };
})();
