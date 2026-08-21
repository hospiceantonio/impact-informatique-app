/* =========================================================
   Catégories — liste complète, rayon d'une catégorie
   (avec puces de sous-catégories) et page promotions.
   ========================================================= */
const VueCategories = (() => {

  /* ---------- Toutes les catégories ---------- */

  async function liste(vue) {
    /* Cet onglet n'apparaît qu'une fois le client entré dans une
       boutique : il parle donc d'elle seule, et garde l'ordre que son
       gérant a choisi. La vue d'ensemble — tous les rayons de
       l'enseigne, par ordre alphabétique — vit sur l'accueil BIZZOO.

       Reste le cas d'un lien direct ouvert avant tout choix de
       boutique : on montre alors cette vue d'ensemble plutôt qu'un
       mélange de rayons sans étiquette. */
    const choisie = Catalogue.boutiqueChoisie();
    const toutesBoutiques = Catalogue.multiBoutiques() && !choisie;
    const comptes = toutesBoutiques ? {} : Catalogue.nombreParCategorie();
    const rayons = toutesBoutiques
      ? Catalogue.rayonsDeLEnseigne()
      : Catalogue.categories().map((c) => ({
          categorie: c, boutique: null, compte: comptes[c.id] || 0,
        }));

    UI.entete({ titre: "Catégories",
      sous: toutesBoutiques ? "Les rayons de toutes les boutiques" : "Tout le matériel, classé par rayon" });

    /* Le bandeau « vous êtes chez X » n'aurait rien à dire quand la
       liste les traverse toutes. */
    const bandeau = toutesBoutiques ? "" : UI.bandeauBoutique();

    if (!rayons.length) {
      vue.innerHTML = bandeau +
        UI.vide("categories", "Aucune catégorie pour l'instant",
          "Les rayons des boutiques s'afficheront ici.");
      return;
    }

    vue.innerHTML = bandeau + rayons.map((r) => UI.ligneRayon(r)).join("");
  }

  /* ---------- Une catégorie ---------- */

  async function rayon(vue, id, params) {
    const c = Catalogue.categorie(id);
    if (!c) {
      vue.innerHTML = UI.vide("alerte", "Catégorie introuvable",
        "Elle a peut-être été retirée du catalogue.",
        '<a class="btn btn-clair" href="#/categories">Voir les catégories</a>');
      UI.entete({ titre: "Catégorie", retour: true });
      return;
    }

    const sousCategories = Catalogue.sousCategories(c.id);
    const scActive = params && params.sc && sousCategories.some((s) => s.id === params.sc)
      ? params.sc : null;
    const produits = Catalogue.produitsDeCategorie(c.id, scActive);

    UI.entete({ titre: c.nom, retour: true,
      sous: produits.length + " produit" + (produits.length > 1 ? "s" : "") });

    let html = "";

    if (sousCategories.length) {
      /* « collees » : la rangée se fige sous la barre du haut quand on
         fait défiler le rayon, pour changer de sous-catégorie sans
         avoir à remonter. */
      html += '<div class="puces puces-collees">' +
        '<a class="puce' + (scActive ? "" : " active") + '" href="#/categorie/' + Utils.echapper(c.id) + '">Tout</a>' +
        sousCategories.map((s) =>
          '<a class="puce' + (scActive === s.id ? " active" : "") + '" href="#/categorie/' +
            Utils.echapper(c.id) + "?sc=" + Utils.echapper(s.id) + '">' + Utils.echapper(s.nom) + "</a>"
        ).join("") +
      "</div>";
    }

    html += produits.length
      ? UI.grilleProduits(produits)
      : UI.vide("boite", "Rien dans ce rayon pour l'instant",
          "Repassez bientôt : le catalogue est mis à jour régulièrement.");

    vue.innerHTML = html;
  }

  /* ---------- Promotions ---------- */

  async function promos(vue) {
    const produits = Catalogue.promotions();
    UI.entete({ titre: "Promotions", retour: true,
      sous: produits.length ? "Profitez-en, stocks limités" : "" });

    vue.innerHTML = produits.length
      ? UI.grilleProduits(produits)
      : UI.vide("promo", "Pas de promotion en cours",
          "Les offres du moment s'afficheront ici.");
  }

  return { liste, rayon, promos };
})();
