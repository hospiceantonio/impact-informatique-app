/* =========================================================
   Recherche — plein texte sur les produits, insensible
   aux accents, avec raccourcis vers les catégories.
   ========================================================= */
const VueRecherche = (() => {

  let dernierTerme = "";

  async function afficher(vue) {
    UI.entete({ titre: "Recherche", sous: "Trouvez votre matériel en quelques lettres" });

    vue.innerHTML =
      '<div class="recherche-boite">' +
        UI.icone("recherche", "ic-sm") +
        '<input id="recherche-champ" type="search" placeholder="Ordinateur, encre, clé USB…" ' +
          'autocomplete="off" autocapitalize="off" value="' + Utils.echapper(dernierTerme) + '">' +
      "</div>" +
      '<div id="recherche-resultats"></div>';

    const champ = UI.$("#recherche-champ");
    const zone = UI.$("#recherche-resultats");

    const rendre = () => {
      const terme = champ.value.trim();
      dernierTerme = terme;

      if (!terme) {
        const categories = Catalogue.categories();
        zone.innerHTML = categories.length
          ? UI.titreSection("Parcourir les rayons") +
            '<div class="puces puces-pliees">' +
              categories.map((c) =>
                '<a class="puce" href="#/categorie/' + Utils.echapper(c.id) + '">' + Utils.echapper(c.nom) + "</a>"
              ).join("") +
            "</div>"
          : "";
        return;
      }

      const resultats = Catalogue.rechercher(terme);
      zone.innerHTML = resultats.length
        ? '<div class="aide" style="margin:2px 2px 10px">' + resultats.length +
            " résultat" + (resultats.length > 1 ? "s" : "") + "</div>" +
          UI.grilleProduits(resultats)
        : UI.vide("recherche", "Aucun résultat pour « " + terme + " »",
            "Essayez un autre mot, ou contactez la boutique : nous trouvons souvent ce qui manque.");
    };

    champ.addEventListener("input", Utils.tempo(rendre, 200));
    rendre();
    if (!dernierTerme) champ.focus();
  }

  return { afficher };
})();
