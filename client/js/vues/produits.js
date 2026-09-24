/* =========================================================
   Produits — tout un catalogue, en galerie.

   Deux entrées, un seul écran :
   - « Nos produits » (#/nos-produits), ouvert par « Voir tout »
     sur l'accueil de BIZZOO : TOUTES les boutiques ouvertes, les
     derniers arrivés d'abord — les huit cartes de l'accueil sont
     les huit premières d'ici ;
   - « Produits » (#/produits) : le catalogue de la boutique
     visitée, du moins cher au plus cher. Ouvert par un lien direct
     avant tout choix de boutique, il montre toute l'enseigne.

   Quand l'écran mélange les boutiques, chaque carte porte le nom
   de la sienne : sans lui, le mélange ne voudrait rien dire.

   LA GALERIE SE REMPLIT EN DÉFILANT. Deux cent cinquante cartes
   d'un coup, c'est deux cent cinquante photos demandées ensemble
   sur un forfait mobile, et un écran qui fige le temps de les
   poser. On en pose un lot ; le suivant vient quand le pouce
   approche du bas, bien avant qu'il ne l'atteigne. Chaque photo,
   elle, ne se charge qu'en approchant de l'écran (« lazy »).
   ========================================================= */
const VueProduits = (() => {

  const LOT = 20;              // cartes posées à chaque fois
  const AVANCE = "900px 0px";  // on remplit avant que le pouce n'arrive

  /* CE QUI ÉTAIT DÉJÀ POSÉ, par adresse d'écran. Le client ouvre la
     150ᵉ carte, puis revient : le routeur le replace à sa hauteur, mais
     cette hauteur n'existe que si les 150 cartes sont là. On repose donc
     d'emblée ce qu'il avait déjà fait défiler. */
  const dejaPoses = new Map();
  let observateur = null;

  /** L'écran change : la galerie quittée cesse de guetter le bas. */
  function arreter() {
    if (observateur) { observateur.disconnect(); observateur = null; }
  }

  /**
   * `options.galerie` : la galerie de l'accueil — toutes les boutiques,
   * les derniers arrivés d'abord, quelle que soit la boutique visitée
   * juste avant (ouvrir un produit fait entrer dans SA boutique ; le
   * retour ne doit pas trouver la galerie réduite à celle-là).
   */
  async function afficher(vue, options) {
    arreter();
    const galerie = !!(options && options.galerie);
    const choisie = galerie ? null : Catalogue.boutiqueChoisie();
    const toutesBoutiques = Catalogue.multiBoutiques() && !choisie;
    const produits = Catalogue.produitsDeLEnseigne(choisie ? choisie.id : "",
      galerie ? "recents" : "");
    const cle = location.hash || (galerie ? "#/nos-produits" : "#/produits");

    UI.entete({
      titre: galerie ? "Nos produits" : "Produits",
      retour: galerie,
      sous: produits.length
        ? produits.length + " produit" + (produits.length > 1 ? "s" : "") +
          (toutesBoutiques ? " dans toutes les boutiques" : "")
        : "",
      actions: UI.boutonRecherche(),
    });

    const bandeau = toutesBoutiques ? "" : UI.bandeauBoutique();
    if (!produits.length) {
      vue.innerHTML = bandeau + UI.vide("boite", "Le catalogue arrive bientôt",
        "Les produits publiés par les boutiques s'afficheront ici.");
      return;
    }

    vue.innerHTML = bandeau +
      '<div class="p-grille galerie" id="galerie"></div>' +
      '<div class="galerie-suite" id="galerie-suite">' +
        /* LE BOUTON DE SECOURS : un téléphone dont le navigateur ne sait
           pas prévenir qu'on approche du bas remplit la galerie au doigt.
           Ailleurs, il ne sert presque jamais — la suite arrive avant. */
        '<button type="button" class="btn btn-clair" id="galerie-plus">Afficher plus</button>' +
      "</div>";

    const grille = UI.$("#galerie", vue);
    const suite = UI.$("#galerie-suite", vue);
    let poses = 0;

    const poser = (combien) => {
      const lot = produits.slice(poses, poses + combien);
      if (!lot.length) return;
      grille.insertAdjacentHTML("beforeend",
        lot.map((p) => UI.carteProduit(p, { boutique: toutesBoutiques })).join(""));
      poses += lot.length;
      dejaPoses.set(cle, poses);
      if (poses >= produits.length) {
        arreter();
        suite.innerHTML = produits.length > LOT
          ? '<p class="galerie-fin">Vous avez tout vu : ' + produits.length + " produits.</p>"
          : "";
      }
    };

    poser(Math.max(LOT, dejaPoses.get(cle) || 0));
    if (poses >= produits.length) return;

    UI.$("#galerie-plus", vue).onclick = () => poser(LOT);

    if (typeof IntersectionObserver !== "function") return;
    observateur = new IntersectionObserver((entrees) => {
      /* L'écran a changé entre-temps : la galerie quittée ne se remplit plus. */
      if (!document.body.contains(suite)) { arreter(); return; }
      if (!entrees.some((x) => x.isIntersecting)) return;
      poser(LOT);
      /* Toujours en vue après ce lot — un grand écran, un lot court — :
         on se fait prévenir de nouveau, sans quoi la galerie attendrait
         un défilement qui ne viendra peut-être pas. */
      if (observateur) {
        observateur.unobserve(suite);
        observateur.observe(suite);
      }
    }, { rootMargin: AVANCE });
    observateur.observe(suite);
  }

  return { afficher, arreter };
})();
