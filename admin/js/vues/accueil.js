/* =========================================================
   Accueil — tableau de bord : publication, aperçu du slider
   (images puis produits mis en avant), derniers produits.
   ========================================================= */
const VueAccueil = (() => {

  async function afficher(vue) {
    const admin = Supabase.estAdmin();

    UI.entete({ accueil: true, actions: admin
      ? '<a class="btn-ic" href="#/commandes" aria-label="Commandes">' + UI.icone("boite") + "</a>" +
        '<a class="btn-ic" href="#/historique" aria-label="Historique">' + UI.icone("horloge") + "</a>" +
        '<a class="btn-ic" href="#/comptes" aria-label="Comptes">' + UI.icone("equipe") + "</a>" +
        '<a class="btn-ic" href="#/reglages" aria-label="Réglages">' + UI.icone("reglages") + "</a>"
      : '<a class="btn-ic" href="#/commandes" aria-label="Commandes">' + UI.icone("boite") + "</a>" +
        '<a class="btn-ic" href="#/compte" aria-label="Mon compte">' + UI.icone("personne") + "</a>" });

    const [stats, slides, produits, demandes, commandes] = await Promise.all([
      Store.statistiques(),
      admin ? Store.listerSlides().catch(() => []) : Promise.resolve([]),
      Store.listerProduits(),
      /* Les demandes de validation. La table peut ne pas exister encore
         — le SQL n'a peut-être pas été exécuté : l'accueil ne doit pas
         tomber pour autant. */
      admin ? Store.listerDemandes().catch(() => []) : Promise.resolve([]),
      /* Les commandes payées qui attendent d'être préparées. Même
         prudence : une base d'avant les achats intégrés n'a pas la table. */
      Store.commandesEnAttente().catch(() => 0),
    ]);
    const enAttente = demandes.filter((d) => d.etat === "en_attente");

    let html = "";

    /* ---- Les commandes qui attendent ----
       C'est le message que la boutique reçoit dans son compte : un
       client a payé, il attend sa marchandise. Rien ne doit passer
       avant à l'écran. */
    if (commandes) {
      html +=
        '<a class="carte carte-commandes" href="#/commandes">' +
          '<div class="carte-titre">' + UI.icone("boite", "ic-sm") + " " +
            commandes + " commande" + (commandes > 1 ? "s" : "") + " payée" +
            (commandes > 1 ? "s" : "") + " à préparer</div>" +
          '<p class="aide" style="margin:0">Un client a réglé sa commande et attend. ' +
            "Touchez pour voir ce qu'il faut préparer et ses coordonnées.</p>" +
        "</a>";
    }

    /* ---- Ce qui attend une décision ----
       Au superadministrateur, ce que les boutiques demandent ; à
       l'administrateur d'une boutique, où en sont ses propres demandes.
       Une demande oubliée, c'est une boutique qui attend. */
    if (enAttente.length) {
      const combien = enAttente.length + " demande" + (enAttente.length > 1 ? "s" : "");
      html += Supabase.estSuper()
        ? '<a class="carte carte-publier" href="#/validations">' +
            '<div class="carte-titre">' + UI.icone("alerte", "ic-sm") + " " +
              combien + " en attente</div>" +
            '<p class="aide" style="margin:0">Des boutiques veulent changer leur nom, ' +
              "leur logo, leurs contacts ou leur slider. Touchez pour voir et trancher.</p>" +
          "</a>"
        : '<div class="note-attente">' + UI.icone("horloge", "ic-sm") + " " +
            combien + " en attente de validation par BIZZOO : " +
            Utils.echapper(enAttente.map((d) => d.objet).join(" · ")) + "</div>";
    }

    /* ---- La boutique sur laquelle on travaille ----
       Avec plusieurs secteurs, il faut savoir en un coup d'œil où l'on
       est : tout ce qui suit ne concerne que cette boutique-là. */
    const courante = Store.boutiqueCourante();
    if (courante) {
      /* Seul le super administrateur passe d'une boutique à l'autre. */
      const peutChanger = Supabase.estSuper();
      html +=
        '<a class="carte carte-boutique-active"' +
          (peutChanger ? ' href="#/boutiques"' : "") + ">" +
          VueBoutiques.pastille(courante) +
          "<span><strong>" + Utils.echapper(courante.nomBoutique) + "</strong><br>" +
          "<small>" + (peutChanger
            ? "Boutique ouverte — touchez pour en changer"
            : Utils.echapper(courante.secteur || "Votre boutique")) +
          (courante.actif ? "" : " · fermée aux clients") + "</small></span>" +
          (peutChanger ? UI.icone("chevron", "ic-sm") : "") +
        "</a>";
    }

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
              '<span class="stat-valeur">' + (stats.slides + stats.enAvant) + "</span>" +
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

    /* ---- Slider : les images libres, puis les produits mis en avant ---- */
    const enAvant = produits
      .filter((p) => p.enAvant)
      .sort((a, b) => (a.ordreAvant || 0) - (b.ordreAvant || 0));
    const images = slides.filter((s) => s.actif);
    const ecrans = images.map((s) => ({ apercu: s.apercu, video: s.videoUrl, produit: false }))
      .concat(enAvant.map((p) => ({ apercu: p.vignette, video: "", produit: true })));

    if (admin) {
      html += '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("image", "ic-sm") + " Slider — à la une (" +
          ecrans.length + ")</div>" +
        '<p class="aide" style="margin:-4px 0 12px">' +
          images.length + " écran" + (images.length > 1 ? "s" : "") +
          " puis " + enAvant.length + " produit" + (enAvant.length > 1 ? "s" : "") +
          " mis en avant, dans cet ordre, en haut de l'écran de cette boutique. " +
          "L'accueil de l'application, lui, fait défiler le slider de BIZZOO " +
          "(Réglages → BIZZOO).</p>";

      if (ecrans.length) {
        html += '<div class="slider-apercu">' +
          ecrans.map((e, i) =>
            '<a class="slider-apercu-img" href="#/slider" aria-label="Écran ' + (i + 1) + ' du slider">' +
              (e.video
                ? '<video src="' + Utils.echapper(e.video) + '" muted playsinline preload="metadata"></video>'
                : e.apercu
                  ? '<img src="' + Utils.echapper(e.apercu) + '" alt="">'
                  : '<span class="slider-apercu-vide">' + UI.icone("image", "ic-sm") + "</span>") +
              (e.produit ? '<span class="slide-etiquette slide-etiquette-produit">Produit</span>' : "") +
            "</a>").join("") +
        "</div>";
      } else {
        html += '<p class="aide" style="margin:0 0 12px">Le slider est vide : vos clients ne verront rien à la une.</p>';
      }
      html += '<a class="btn btn-clair" style="margin-top:10px" href="#/slider">' +
        UI.icone("image") + (ecrans.length ? "Gérer le slider" : "Composer le slider") + "</a>" +
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
