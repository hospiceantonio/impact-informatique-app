/* =========================================================
   Recherche — plein texte sur les produits de TOUTES les
   boutiques ouvertes, insensible aux accents et aux mots
   incomplets. Les produits seulement : les rayons ont leur
   propre onglet.
   ========================================================= */
const VueRecherche = (() => {

  let dernierTerme = "";

  /** « 12 résultats dans 3 boutiques » — savoir où chercher compte
      autant que savoir combien on a trouvé. */
  function resume(resultats) {
    const boutiques = new Set();
    for (const p of resultats) {
      const b = Catalogue.boutiqueDuProduit(p);
      if (b) boutiques.add(b.id);
    }
    const n = resultats.length;
    let texte = n + " résultat" + (n > 1 ? "s" : "");
    if (boutiques.size > 1) texte += " dans " + boutiques.size + " boutiques";
    else if (boutiques.size === 1 && Catalogue.multiBoutiques()) {
      const seule = Catalogue.boutiqueDuProduit(resultats[0]);
      if (seule) texte += " chez " + seule.nom;
    }
    return texte;
  }

  async function afficher(vue) {
    /* On y entre par la barre de l'accueil, plus par un onglet : un
       retour ramène d'où l'on vient. */
    UI.entete({
      titre: "Recherche",
      retour: true,
      sous: Catalogue.multiBoutiques()
        ? "Dans toutes les boutiques, en quelques lettres"
        : "Trouvez votre matériel en quelques lettres",
    });

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
        /* La recherche ne concerne que les produits : tant que rien
           n'est tapé, on ne montre rien d'autre qu'un mot d'aide. Les
           rayons se parcourent depuis l'onglet Catégories. */
        zone.innerHTML =
          '<p class="aide" style="margin:6px 2px 0">Tapez un nom de produit, ' +
          "une référence ou un mot de la description. Quelques lettres " +
          "suffisent" +
          (Catalogue.multiBoutiques()
            ? ", et toutes les boutiques sont fouillées à la fois.</p>"
            : ".</p>");
        return;
      }

      const resultats = Catalogue.rechercher(terme);
      zone.innerHTML = resultats.length
        ? '<div class="aide" style="margin:2px 2px 10px">' + Utils.echapper(resume(resultats)) + "</div>" +
          UI.grilleProduits(resultats, { boutique: Catalogue.multiBoutiques() })
        : UI.vide("recherche", "Aucun résultat pour « " + terme + " »",
            "Essayez un autre mot, ou contactez la boutique : nous trouvons souvent ce qui manque.");
    };

    champ.addEventListener("input", Utils.tempo(rendre, 200));
    rendre();
    if (!dernierTerme) champ.focus();
  }

  return { afficher };
})();
