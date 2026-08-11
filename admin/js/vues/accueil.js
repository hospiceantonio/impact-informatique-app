/* =========================================================
   Accueil — tableau de bord : publication, produits mis
   en avant (l'ordre du slider client), derniers produits.
   ========================================================= */
const VueAccueil = (() => {

  async function afficher(vue) {
    const admin = Supabase.estAdmin();

    UI.entete({ accueil: true, actions: admin
      ? '<a class="btn-ic" href="#/historique" aria-label="Historique">' + UI.icone("horloge") + "</a>" +
        '<a class="btn-ic" href="#/comptes" aria-label="Comptes">' + UI.icone("equipe") + "</a>" +
        '<a class="btn-ic" href="#/reglages" aria-label="Réglages">' + UI.icone("reglages") + "</a>"
      : '<a class="btn-ic" href="#/compte" aria-label="Mon compte">' + UI.icone("personne") + "</a>" });

    const [stats, slides, produits] = await Promise.all([
      Store.statistiques(),
      admin ? Store.listerSlides().catch(() => []) : Promise.resolve([]),
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
        (admin
          ? '<a class="stat" href="#/slider">' +
              '<span class="stat-valeur">' + stats.slides + "<small>/" + Store.MAX_SLIDES + "</small></span>" +
              '<span class="stat-label">Slider</span>' +
            "</a>"
          : '<span class="stat">' +
              '<span class="stat-valeur">' + stats.promotions + "</span>" +
              '<span class="stat-label">Promotion' + (stats.promotions > 1 ? "s" : "") + "</span>" +
            "</span>") +
      "</div>";

    /* ---- Catalogue en direct ---- */
    html +=
      '<div class="carte carte-publier">' +
        '<div class="carte-titre">' + UI.icone("nuage", "ic-sm") + " Catalogue en ligne</div>" +
        '<div class="note-ok" style="margin-bottom:0">' + UI.icone("check", "ic-sm") +
          " Vos modifications sont enregistrées directement en ligne : l'application client les affiche immédiatement." +
        "</div>" +
      "</div>";

    /* ---- Slider : les images à la une, composées par l'administrateur ---- */
    if (admin) {
      html += '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("image", "ic-sm") + " Slider — images à la une (" +
          slides.length + "/" + Store.MAX_SLIDES + ")</div>" +
        '<p class="aide" style="margin:-4px 0 12px">Ces images défilent en grand en haut de l\'application client, dans cet ordre.</p>';

      if (slides.length) {
        html += '<div class="slider-apercu">' +
          slides.map((s, i) =>
            '<a class="slider-apercu-img" href="#/slider" aria-label="Image ' + (i + 1) + ' du slider">' +
              '<img src="' + Utils.echapper(s.apercu) + '" alt="">' +
              (s.actif ? "" : '<span class="slide-etiquette">Masquée</span>') +
            "</a>").join("") +
        "</div>";
      } else {
        html += '<p class="aide" style="margin:0 0 12px">Le slider est vide : vos clients ne verront aucune image à la une.</p>';
      }
      html += '<a class="btn btn-clair" style="margin-top:10px" href="#/slider">' +
        UI.icone("image") + (slides.length ? "Gérer le slider" : "Composer le slider") + "</a>" +
      "</div>";
    }

    /* ---- Dernières actions (administrateur) ---- */
    let journal = [];
    if (admin) {
      try { journal = await Store.lireJournal(4, 0); } catch (_) { /* table pas encore créée */ }
    }
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
  }

  return { afficher };
})();
