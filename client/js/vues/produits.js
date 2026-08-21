/* =========================================================
   Produits — tout le catalogue de la boutique visitée, du
   moins cher au plus cher. L'onglet Catégories range par
   rayon ; celui-ci ne range rien et montre tout d'un coup.

   Comme Catégories, il n'apparaît qu'une fois le client
   entré quelque part. Ouvert par un lien direct avant tout
   choix de boutique, il montre alors toute l'enseigne —
   chaque carte portant le nom de sa boutique, sans quoi le
   mélange ne voudrait rien dire.
   ========================================================= */
const VueProduits = (() => {

  async function afficher(vue) {
    const choisie = Catalogue.boutiqueChoisie();
    const toutesBoutiques = Catalogue.multiBoutiques() && !choisie;
    const produits = Catalogue.produitsDeLEnseigne(choisie ? choisie.id : "");

    UI.entete({
      titre: "Produits",
      sous: produits.length
        ? produits.length + " produit" + (produits.length > 1 ? "s" : "") +
          (toutesBoutiques ? " dans toutes les boutiques" : "")
        : "",
      actions: '<a class="btn-ic" href="#/recherche" aria-label="Rechercher">' +
        UI.icone("recherche") + "</a>",
    });

    vue.innerHTML =
      (toutesBoutiques ? "" : UI.bandeauBoutique()) +
      (produits.length
        ? UI.grilleProduits(produits, { boutique: toutesBoutiques })
        : UI.vide("boite", "Le catalogue arrive bientôt",
            "Les produits publiés par la boutique s'afficheront ici."));
  }

  return { afficher };
})();
