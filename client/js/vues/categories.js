/* =========================================================
   Catégories — liste complète, rayon d'une catégorie
   (avec puces de sous-catégories) et page promotions.
   ========================================================= */
const VueCategories = (() => {

  /* ---------- Toutes les catégories ---------- */

  async function liste(vue) {
    UI.entete({ titre: "Catégories", sous: "Tout le matériel, classé par rayon" });

    const categories = Catalogue.categories();
    const comptes = Catalogue.nombreParCategorie();

    if (!categories.length) {
      vue.innerHTML = UI.vide("categories", "Aucune catégorie pour l'instant",
        "Les rayons de la boutique s'afficheront ici.");
      return;
    }

    vue.innerHTML = categories.map((c) => {
      const sousCategories = Catalogue.sousCategories(c.id);
      return (
        '<a class="carte cat-ligne" href="#/categorie/' + Utils.echapper(c.id) + '">' +
          '<span class="cat-rond">' + UI.icone(UI.iconeCategorie(c.nom)) + "</span>" +
          '<span class="cat-ligne-corps">' +
            '<span class="cat-ligne-nom">' + Utils.echapper(c.nom) + "</span>" +
            '<span class="cat-ligne-sous">' +
              (sousCategories.length
                ? Utils.echapper(sousCategories.map((s) => s.nom).join(" · "))
                : (comptes[c.id] || 0) + " produit" + ((comptes[c.id] || 0) > 1 ? "s" : "")) +
            "</span>" +
          "</span>" +
          '<span class="cat-ligne-compte">' + (comptes[c.id] || 0) + "</span>" +
          UI.icone("chevron", "ic-sm") +
        "</a>"
      );
    }).join("");
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
