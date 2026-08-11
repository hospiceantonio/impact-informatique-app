/* =========================================================
   Accueil — tableau de bord : publication, produits mis
   en avant (l'ordre du slider client), derniers produits.
   ========================================================= */
const VueAccueil = (() => {

  async function afficher(vue) {
    UI.entete({ accueil: true, actions:
      '<a class="btn-ic" href="#/historique" aria-label="Historique">' + UI.icone("horloge") + "</a>" +
      '<a class="btn-ic" href="#/reglages" aria-label="Réglages">' + UI.icone("reglages") + "</a>" });

    const [stats, enAvant, produits] = await Promise.all([
      Store.statistiques(),
      Store.listerEnAvant(),
      Store.listerProduits(),
    ]);

    let html = "";

    /* ---- Chiffres clés ---- */
    html +=
      '<div class="stats">' +
        '<a class="stat" href="#/produits">' +
          '<span class="stat-valeur">' + stats.produits + "</span>" +
          '<span class="stat-label">Produit' + (stats.produits > 1 ? "s" : "") + "</span>" +
        "</a>" +
        '<a class="stat" href="#/categories">' +
          '<span class="stat-valeur">' + stats.categories + "</span>" +
          '<span class="stat-label">Catégorie' + (stats.categories > 1 ? "s" : "") + "</span>" +
        "</a>" +
        '<span class="stat">' +
          '<span class="stat-valeur">' + stats.enAvant + "<small>/" + Store.MAX_EN_AVANT + "</small></span>" +
          '<span class="stat-label">En avant</span>' +
        "</span>" +
      "</div>";

    /* ---- Catalogue en direct ---- */
    html +=
      '<div class="carte carte-publier">' +
        '<div class="carte-titre">' + UI.icone("nuage", "ic-sm") + " Catalogue en ligne</div>" +
        '<div class="note-ok" style="margin-bottom:0">' + UI.icone("check", "ic-sm") +
          " Vos modifications sont enregistrées directement en ligne : l'application client les affiche immédiatement." +
        "</div>" +
      "</div>";

    /* ---- Produits mis en avant ---- */
    html += '<div class="carte">' +
      '<div class="carte-titre">' + UI.icone("etoile", "ic-sm") + " Mis en avant — slider client (" +
        enAvant.length + "/" + Store.MAX_EN_AVANT + ")</div>" +
      '<p class="aide" style="margin:-4px 0 12px">Ces produits défilent en grand en haut de l\'application client, dans cet ordre.</p>';

    if (enAvant.length) {
      html += enAvant.map((p, i) =>
        '<div class="avant-ligne">' +
          '<span class="avant-num">' + (i + 1) + "</span>" +
          UI.vignetteProduit(p) +
          '<button type="button" class="avant-nom" data-nav="#/produit/' + Utils.echapper(p.id) + '">' +
            Utils.echapper(p.nom) + "</button>" +
          '<span class="avant-actions">' +
            '<button type="button" class="btn-ic btn-ic-clair" data-avant-monter="' + Utils.echapper(p.id) + '"' +
              (i === 0 ? " disabled" : "") + ' aria-label="Monter">' + UI.icone("haut", "ic-sm") + "</button>" +
            '<button type="button" class="btn-ic btn-ic-clair" data-avant-descendre="' + Utils.echapper(p.id) + '"' +
              (i === enAvant.length - 1 ? " disabled" : "") + ' aria-label="Descendre">' + UI.icone("bas", "ic-sm") + "</button>" +
            '<button type="button" class="btn-ic btn-ic-clair btn-ic-danger" data-avant-retirer="' + Utils.echapper(p.id) + '" aria-label="Retirer du slider">' +
              UI.icone("fermer", "ic-sm") + "</button>" +
          "</span>" +
        "</div>"
      ).join("");
    } else {
      html += '<p class="aide" style="margin:0">Aucun produit mis en avant. Ouvrez un produit puis activez « Mettre en avant ».</p>';
    }
    html += "</div>";

    /* ---- Dernières actions ---- */
    let journal = [];
    try { journal = await Store.lireJournal(4, 0); } catch (_) { /* table pas encore créée */ }
    if (journal.length) {
      html += '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("horloge", "ic-sm") + " Dernières actions</div>" +
        journal.map((e) =>
          '<div class="histo-ligne histo-compact">' +
            '<span class="histo-corps">' +
              '<span class="histo-libelle">' + Utils.echapper(e.libelle) + "</span>" +
              '<span class="histo-details">' + Utils.echapper(Utils.fmtDateHeure(e.date)) +
                (e.utilisateur ? " · " + Utils.echapper(e.utilisateur) : "") + "</span>" +
            "</span>" +
          "</div>").join("") +
        '<a class="btn btn-clair" style="margin-top:10px" href="#/historique">' +
          UI.icone("horloge") + "Voir tout l'historique</a>" +
      "</div>";
    }

    /* ---- Derniers produits ---- */
    html += '<div class="carte">' +
      '<div class="carte-titre">Derniers produits modifiés</div>';
    if (produits.length) {
      const categories = await Store.listerCategories();
      const nomCategorie = (p) => {
        const c = categories.find((x) => x.id === p.categorieId);
        if (!c) return "Sans catégorie";
        const sc = (c.sousCategories || []).find((x) => x.id === p.sousCategorieId);
        return sc ? c.nom + " · " + sc.nom : c.nom;
      };
      html += produits.slice(0, 5).map((p) => UI.ligneProduit(p, nomCategorie(p))).join("");
      if (produits.length > 5) {
        html += '<a class="btn btn-clair" style="margin-top:10px" href="#/produits">Voir les ' + produits.length + " produits</a>";
      }
    } else {
      html += UI.vide("boite", "Aucun produit pour l'instant",
        "Ajoutez votre premier produit avec le bouton + en bas de l'écran.");
    }
    html += "</div>";

    vue.innerHTML = html;

    /* ---- Actions sur la liste "en avant" ---- */
    const rafraichir = () => afficher(vue);
    for (const b of UI.$$("[data-avant-monter]", vue)) {
      b.onclick = async () => { await Store.deplacerEnAvant(b.dataset.avantMonter, -1); rafraichir(); };
    }
    for (const b of UI.$$("[data-avant-descendre]", vue)) {
      b.onclick = async () => { await Store.deplacerEnAvant(b.dataset.avantDescendre, +1); rafraichir(); };
    }
    for (const b of UI.$$("[data-avant-retirer]", vue)) {
      b.onclick = async () => {
        await Store.basculerEnAvant(b.dataset.avantRetirer);
        UI.toast("Produit retiré du slider");
        rafraichir();
      };
    }
  }

  return { afficher };
})();
