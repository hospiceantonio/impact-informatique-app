/* =========================================================
   Recherche — plein texte sur les produits, insensible aux
   accents et aux mots incomplets. Les produits seulement : les
   rayons ont leur propre onglet.

   OÙ L'ON CHERCHE. Sur BIZZOO, dans toutes les boutiques
   ouvertes. Dans une boutique, D'ABORD CHEZ ELLE — c'est là
   qu'on se tient, et un résultat venu d'ailleurs ferait croire
   qu'elle le vend —, avec une puce pour élargir à toutes les
   boutiques sans en sortir.
   ========================================================= */
const VueRecherche = (() => {

  let dernierTerme = "";
  /* « boutique » ou « partout ». Le choix vaut pour la boutique où il a
     été fait : entré dans une autre, on recommence chez elle. */
  let portee = "boutique";
  let porteePour = "";

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
    const chez = Catalogue.multiBoutiques() ? Catalogue.boutiqueChoisie() : null;
    if (!chez || porteePour !== chez.id) portee = "boutique";
    porteePour = chez ? chez.id : "";
    const dansLaBoutique = () => !!chez && portee === "boutique";

    /* L'onglet Recherche, la barre-pilule de l'accueil et la loupe des
       en-têtes mènent tous ici : un retour ramène d'où l'on vient. */
    const entete = () => UI.entete({
      titre: "Recherche",
      retour: true,
      sous: dansLaBoutique() ? "Chez " + chez.nom
        : Catalogue.multiBoutiques() ? "Dans toutes les boutiques, en quelques lettres"
        : "Trouvez votre matériel en quelques lettres",
    });
    entete();

    const puces = () => !chez ? "" :
      '<div class="puces" id="recherche-portee" role="group" aria-label="Où chercher">' +
        '<button type="button" class="puce' + (dansLaBoutique() ? " active" : "") +
          '" data-portee="boutique" aria-pressed="' + dansLaBoutique() + '">Chez ' +
          Utils.echapper(chez.nom) + "</button>" +
        '<button type="button" class="puce' + (dansLaBoutique() ? "" : " active") +
          '" data-portee="partout" aria-pressed="' + !dansLaBoutique() + '">Toutes les boutiques</button>' +
      "</div>";

    vue.innerHTML =
      '<div class="recherche-boite">' +
        UI.icone("recherche", "ic-sm") +
        '<input id="recherche-champ" type="search" placeholder="Ordinateur, encre, clé USB…" ' +
          'autocomplete="off" autocapitalize="off" value="' + Utils.echapper(dernierTerme) + '">' +
      "</div>" +
      '<div id="recherche-puces">' + puces() + "</div>" +
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
          (dansLaBoutique()
            ? " : on cherche chez " + Utils.echapper(chez.nom) + ".</p>"
            : Catalogue.multiBoutiques()
              ? ", et toutes les boutiques sont fouillées à la fois.</p>"
              : ".</p>");
        return;
      }

      let resultats = Catalogue.rechercher(terme);
      if (dansLaBoutique()) resultats = resultats.filter((p) => p.boutiqueId === chez.id);
      zone.innerHTML = resultats.length
        ? '<div class="aide" style="margin:2px 2px 10px">' + Utils.echapper(resume(resultats)) + "</div>" +
          UI.grilleProduits(resultats, { boutique: Catalogue.multiBoutiques() && !dansLaBoutique() })
        : UI.vide("recherche", "Aucun résultat pour « " + terme + " »" +
              (dansLaBoutique() ? " chez " + chez.nom : ""),
            dansLaBoutique()
              ? "Essayez un autre mot, ou cherchez dans toutes les boutiques."
              : "Essayez un autre mot, ou contactez la boutique : nous trouvons souvent ce qui manque.",
            dansLaBoutique()
              ? '<button type="button" class="btn btn-clair" data-portee="partout">' +
                  "Chercher dans toutes les boutiques</button>"
              : "");
    };

    /* Changer d'endroit garde ce qui est tapé : on élargit la même
       question, on ne la repose pas. L'écoute se pose sur les deux zones
       de CET écran, refaites à chaque affichage — posée sur « #vue »,
       commun à tous les écrans, elle s'accumulerait à chaque visite. */
    const zonePuces = UI.$("#recherche-puces");
    const changerPortee = (ev) => {
      const choix = ev.target.closest("[data-portee]");
      if (!choix || !chez) return;
      portee = choix.dataset.portee === "partout" ? "partout" : "boutique";
      zonePuces.innerHTML = puces();
      entete();
      rendre();
    };
    zonePuces.addEventListener("click", changerPortee);
    zone.addEventListener("click", changerPortee);

    champ.addEventListener("input", Utils.tempo(rendre, 200));
    rendre();
    if (!dernierTerme) champ.focus();
  }

  return { afficher };
})();
