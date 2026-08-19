/* =========================================================
   Accueil — slider (les images choisies par la boutique,
   puis ses produits mis en avant), catégories, promotions
   et nouveautés.
   ========================================================= */
const VueAccueil = (() => {

  const DELAI_SLIDER = 4500; // défilement automatique
  let minuterie = null;
  let derniereInteraction = 0;

  /* ---------- Slider ----------
     Deux sources à la suite : les images composées par la boutique
     dans l'application admin, puis ses produits mis en avant. */

  /**
   * Une image libre. Elle mène au produit qu'elle annonce ; à défaut, sur
   * l'accueil général, elle mène à la boutique qui l'a composée.
   */
  function slideImage(s, index, avecBoutique) {
    const produit = s.produitId ? Catalogue.produit(s.produitId) : null;
    const laBoutique = avecBoutique && s.boutiqueId ? Catalogue.laBoutique(s.boutiqueId) : null;
    const cible = produit
      ? "#/produit/" + Utils.echapper(produit.id)
      : (laBoutique ? "#/boutique/" + Utils.echapper(laBoutique.id) : "");
    const balise = cible ? "a" : "div";
    const lien = cible ? ' href="' + cible + '"' : "";
    const etiquette = s.titre || (produit ? produit.nom : (laBoutique ? laBoutique.nom : ""));
    return (
      "<" + balise + ' class="slide"' + lien +
        (etiquette ? ' aria-label="' + Utils.echapper(etiquette) + '"' : "") + ">" +
        '<img class="slide-img" src="' + Utils.echapper(s.image) + '" alt="' +
          Utils.echapper(etiquette) + '"' + (index > 0 ? ' loading="lazy"' : "") + ">" +
        (s.titre || produit || laBoutique
          ? '<span class="slide-voile"></span>' +
            '<span class="slide-infos">' +
              (s.titre ? '<span class="slide-nom">' + Utils.echapper(s.titre) + "</span>" : "") +
              (produit
                ? '<span class="slide-cta">Voir le produit ' + UI.icone("chevron", "ic-sm") + "</span>"
                : laBoutique
                  ? '<span class="slide-cta">' + Utils.echapper(laBoutique.nom) + " " +
                    UI.icone("chevron", "ic-sm") + "</span>"
                  : "") +
            "</span>"
          : "") +
      "</" + balise + ">"
    );
  }

  /** Un produit mis en avant : sa photo, son nom, son prix. */
  function slideProduit(p, index) {
    const src = Catalogue.imagePrincipale(p);
    const remise = Utils.remisePourcent(p.ancienPrix, p.prix);
    const devise = Catalogue.boutique().devise;
    return (
      '<a class="slide" href="#/produit/' + Utils.echapper(p.id) + '" aria-label="' + Utils.echapper(p.nom) + '">' +
        (src
          ? '<img class="slide-img" src="' + Utils.echapper(src) + '" alt="" ' + (index > 0 ? 'loading="lazy"' : "") + ">"
          : '<span class="slide-motif">' + UI.marque(120) + "</span>") +
        '<span class="slide-voile"></span>' +
        (remise !== null ? '<span class="badge badge-promo slide-badge">-' + remise + " %</span>" : "") +
        '<span class="slide-infos">' +
          '<span class="slide-nom">' + Utils.echapper(p.nom) + "</span>" +
          '<span class="slide-prix">' + Utils.echapper(Utils.fmtMontant(p.prix, devise)) +
            (remise !== null ? ' <s>' + Utils.echapper(Utils.fmtMontant(p.ancienPrix, devise)) + "</s>" : "") +
          "</span>" +
          '<span class="slide-cta">Voir le produit ' + UI.icone("chevron", "ic-sm") + "</span>" +
        "</span>" +
      "</a>"
    );
  }

  function htmlSlider(images, enAvant, avecBoutique) {
    const total = images.length + enAvant.length;
    if (!total) return "";
    const ecrans =
      images.map((s, i) => slideImage(s, i, avecBoutique)).concat(
      enAvant.map((p, i) => slideProduit(p, images.length + i)));
    return (
      '<section class="slider" aria-label="À la une">' +
        '<div class="slider-piste" id="slider-piste">' + ecrans.join("") + "</div>" +
        (total > 1
          ? '<div class="slider-points" id="slider-points">' +
              ecrans.map((_, i) =>
                '<button type="button" data-slide="' + i + '" aria-label="Écran ' + (i + 1) + '"' +
                (i === 0 ? ' class="actif"' : "") + "></button>").join("") +
            "</div>"
          : "") +
      "</section>"
    );
  }

  function demarrerSlider() {
    arreterSlider();
    const piste = UI.$("#slider-piste");
    if (!piste || piste.children.length < 2) return;
    const points = UI.$$("#slider-points [data-slide]");

    const majPoints = () => {
      const index = Math.round(piste.scrollLeft / piste.clientWidth);
      points.forEach((pt, i) => pt.classList.toggle("actif", i === index));
    };
    piste.addEventListener("scroll", Utils.tempo(majPoints, 80), { passive: true });
    piste.addEventListener("pointerdown", () => { derniereInteraction = Date.now(); }, { passive: true });
    piste.addEventListener("touchstart", () => { derniereInteraction = Date.now(); }, { passive: true });

    for (const pt of points) {
      pt.onclick = () => {
        derniereInteraction = Date.now();
        piste.scrollTo({ left: Number(pt.dataset.slide) * piste.clientWidth, behavior: "smooth" });
      };
    }

    minuterie = setInterval(() => {
      if (!document.body.contains(piste)) { arreterSlider(); return; }
      if (Date.now() - derniereInteraction < 6000) return; // l'utilisateur explore
      const n = piste.children.length;
      const index = Math.round(piste.scrollLeft / piste.clientWidth);
      piste.scrollTo({ left: ((index + 1) % n) * piste.clientWidth, behavior: "smooth" });
    }, DELAI_SLIDER);
  }

  function arreterSlider() {
    if (minuterie) { clearInterval(minuterie); minuterie = null; }
  }

  /* ---------- Catégories ---------- */

  function carteCategorie(c, compte) {
    return (
      '<a class="cat-carte" href="#/categorie/' + Utils.echapper(c.id) + '">' +
        '<span class="cat-rond">' + UI.icone(UI.iconeCategorie(c.nom)) + "</span>" +
        '<span class="cat-nom">' + Utils.echapper(c.nom) + "</span>" +
        '<span class="cat-compte">' + (compte || 0) + " produit" + (compte > 1 ? "s" : "") + "</span>" +
      "</a>"
    );
  }

  /* ---------- Les boutiques de l'enseigne ---------- */

  /** La vignette d'une boutique : son logo, ou son icône sur sa couleur. */
  function carteBoutique(b, compte) {
    return (
      '<a class="bou-carte" href="#/boutique/' + Utils.echapper(b.id) + '" data-boutique="' +
        Utils.echapper(b.id) + '">' +
        (b.logo
          ? '<span class="bou-rond bou-rond-photo"><img src="' + Utils.echapper(b.logo) +
            '" alt="" loading="lazy"></span>'
          : '<span class="bou-rond" style="background:' + Utils.echapper(b.couleur) + '">' +
            UI.icone(b.icone) + "</span>") +
        '<span class="bou-carte-nom">' + Utils.echapper(b.nom) + "</span>" +
        '<span class="bou-carte-sous">' +
          Utils.echapper(b.secteur || (compte + " produit" + (compte > 1 ? "s" : ""))) + "</span>" +
      "</a>"
    );
  }

  /* ---------- Vue ---------- */

  /**
   * L'accueil de l'application : d'abord ce que les boutiques mettent en
   * avant — images et produits confondus —, puis les boutiques elles-mêmes.
   * On choisit la sienne, et tout l'écran suivant ne parle plus que d'elle.
   */
  async function afficher(vue) {
    if (!Catalogue.multiBoutiques()) return accueilBoutique(vue, true);

    Catalogue.quitterBoutique();
    UI.entete({ accueil: true, actions:
      '<button type="button" class="btn-ic" id="accueil-actualiser" aria-label="Actualiser le catalogue">' +
        UI.icone("actualiser") + "</button>" +
      '<a class="btn-ic" href="#/recherche" aria-label="Rechercher">' + UI.icone("recherche") + "</a>" });

    const boutiques = Catalogue.boutiques();
    const comptes = Catalogue.nombreParBoutique();

    let html = htmlSlider(Catalogue.slidesGeneral(), Catalogue.misEnAvantGeneral(), true);
    html += htmlEtatCatalogue();

    html += UI.titreSection("Nos boutiques");
    html += boutiques.length
      ? '<div class="bou-grille">' +
          boutiques.map((b) => carteBoutique(b, comptes[b.id] || 0)).join("") +
        "</div>"
      : UI.vide("magasin", "Les boutiques arrivent bientôt",
          "Elles s'afficheront ici dès leur ouverture.");

    /* Les ventes flash de toutes les boutiques, juste sous leurs icônes.
       La rangée disparaît d'elle-même quand la dernière expire. */
    const flash = Catalogue.ventesFlash();
    if (flash.length) {
      html += UI.titreSection("Ventes flash");
      html += UI.rangeeProduits(flash);
    }

    vue.innerHTML = html;
    demarrerSlider();
    brancherActualiser();
  }

  /** L'état du catalogue : hors ligne, démonstration… */
  function htmlEtatCatalogue() {
    if (Catalogue.depuisCache()) {
      return '<div class="note-hors-ligne">' + UI.icone("alerte", "ic-sm") +
        " Hors connexion — catalogue du " +
        Utils.echapper(Utils.fmtDateHeure(new Date(Catalogue.versionPubliee() || 0).getTime())) + "</div>";
    }
    if (Catalogue.modeDemo()) {
      return '<div class="note-hors-ligne">' + UI.icone("alerte", "ic-sm") +
        " Catalogue de démonstration — la connexion à la boutique se règle dans l'onglet Infos.</div>";
    }
    return "";
  }

  function brancherActualiser() {
    const btnActualiser = UI.$("#accueil-actualiser");
    if (!btnActualiser) return;
    btnActualiser.onclick = async () => {
      btnActualiser.disabled = true;
      btnActualiser.classList.add("tourne");
      const change = await Live.verifier();
      btnActualiser.disabled = false;
      btnActualiser.classList.remove("tourne");
      if (!change) UI.toast("Catalogue déjà à jour", "ok");
    };
  }

  /** L'accueil d'une boutique : on y entre depuis la grille des icônes. */
  async function boutique(vue, id) {
    const cible = Catalogue.choisirBoutique(id);
    if (!cible) {
      UI.entete({ titre: "Boutique", retour: true });
      vue.innerHTML = UI.vide("magasin", "Boutique introuvable",
        "Elle a peut-être fermé.",
        '<a class="btn btn-clair" href="#/">Voir les boutiques</a>');
      return;
    }
    return accueilBoutique(vue, false);
  }

  async function accueilBoutique(vue, enseigne) {
    const b = Catalogue.boutique();
    UI.entete(enseigne
      ? { accueil: true, actions:
          '<button type="button" class="btn-ic" id="accueil-actualiser" aria-label="Actualiser le catalogue">' +
            UI.icone("actualiser") + "</button>" +
          '<a class="btn-ic" href="#/recherche" aria-label="Rechercher">' + UI.icone("recherche") + "</a>" }
      : { titre: b.nom, sous: b.slogan || b.description || "", retour: true, actions:
          '<button type="button" class="btn-ic" id="accueil-actualiser" aria-label="Actualiser le catalogue">' +
            UI.icone("actualiser") + "</button>" +
          '<a class="btn-ic" href="#/recherche" aria-label="Rechercher">' + UI.icone("recherche") + "</a>" });

    const slides = Catalogue.slides();
    const enAvant = Catalogue.misEnAvant();
    const categories = Catalogue.categories();
    const comptes = Catalogue.nombreParCategorie();
    const promos = Catalogue.promotions().slice(0, 8);
    const nouveautes = Catalogue.nouveautes(8);
    const boutique = Catalogue.boutique();

    let html = "";

    html += htmlSlider(slides, enAvant, false);
    html += htmlEtatCatalogue();

    if (categories.length) {
      html += UI.titreSection("Catégories", "#/categories");
      html += '<div class="cat-grille">' +
        categories.slice(0, 6).map((c) => carteCategorie(c, comptes[c.id] || 0)).join("") +
      "</div>";
    }

    const flash = Catalogue.produits()
      .filter((p) => Catalogue.enVenteFlash(p))
      .sort((a, b) => (a.flashFin || 0) - (b.flashFin || 0));
    if (flash.length) {
      html += UI.titreSection("Ventes flash");
      html += UI.rangeeProduits(flash);
    }

    if (promos.length) {
      html += UI.titreSection("Promotions", "#/promos");
      html += UI.rangeeProduits(promos);
    }

    if (nouveautes.length) {
      html += UI.titreSection("Nouveautés");
      html += UI.rangeeProduits(nouveautes);
    }

    if (!Catalogue.produits().length) {
      html += UI.vide("boite", "Le catalogue arrive bientôt",
        "Les produits publiés par la boutique s'afficheront ici.");
    }

    if (boutique.whatsapp) {
      const message = "Bonjour " + boutique.nom + ", je souhaite un renseignement.";
      html +=
        '<a class="carte carte-contact" target="_blank" rel="noopener" href="' +
          Utils.echapper(Utils.lienWhatsApp(boutique.whatsapp, message, boutique.indicatif)) + '">' +
          '<span class="rond-wa">' + UI.icone("whatsapp") + "</span>" +
          "<span><strong>Besoin d'un conseil ?</strong><br>" +
          "<small>Écrivez-nous sur WhatsApp, réponse rapide.</small></span>" +
          UI.icone("chevron", "ic-sm") +
        "</a>";
    }

    vue.innerHTML = html;
    demarrerSlider();
    brancherActualiser();
  }

  return { afficher, boutique, arreterSlider };
})();
