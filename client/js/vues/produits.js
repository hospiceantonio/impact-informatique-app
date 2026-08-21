/* =========================================================
   Produits — tout le catalogue de l'enseigne, boutiques
   ouvertes confondues. L'onglet Catégories range par rayon
   et parle d'une boutique à la fois ; celui-ci ne range
   rien et les montre toutes.
   ========================================================= */
const VueProduits = (() => {

  /** Les puces du haut : « Toutes les boutiques », puis chacune. */
  function puces(idBoutique) {
    const boutiques = Catalogue.boutiques();
    if (boutiques.length < 2) return "";
    return (
      '<div class="puces puces-collees">' +
        '<a class="puce' + (idBoutique ? "" : " active") + '" href="#/produits">Toutes</a>' +
        boutiques.map((b) =>
          '<a class="puce' + (idBoutique === b.id ? " active" : "") +
            '" href="#/produits?b=' + Utils.echapper(b.id) + '">' + Utils.echapper(b.nom) + "</a>"
        ).join("") +
      "</div>"
    );
  }

  async function afficher(vue, params) {
    /* Une boutique fermée entre-temps ne doit pas laisser l'écran
       vide sans rien dire : on retombe alors sur « Toutes ». */
    const demandee = (params && params.b) || "";
    const idBoutique = Catalogue.boutiques().some((b) => b.id === demandee) ? demandee : "";

    const produits = Catalogue.produitsDeLEnseigne(idBoutique);
    const choisie = idBoutique
      ? Catalogue.boutiques().find((b) => b.id === idBoutique)
      : null;

    UI.entete({
      titre: "Produits",
      sous: produits.length
        ? produits.length + " produit" + (produits.length > 1 ? "s" : "") +
          (choisie ? " chez " + choisie.nom
                   : (Catalogue.multiBoutiques() ? " dans toutes les boutiques" : ""))
        : "",
      actions: '<a class="btn-ic" href="#/recherche" aria-label="Rechercher">' +
        UI.icone("recherche") + "</a>",
    });

    vue.innerHTML =
      puces(idBoutique) +
      (produits.length
        /* Le nom de la boutique sur chaque carte : sans lui, on ne
           saurait pas chez qui aller chercher le produit. */
        ? UI.grilleProduits(produits, { boutique: Catalogue.multiBoutiques() })
        : UI.vide("boite", "Le catalogue arrive bientôt",
            "Les produits publiés par les boutiques s'afficheront ici."));
  }

  return { afficher };
})();
