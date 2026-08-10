/* =========================================================
   Accueil — slider des produits mis en avant (5 max),
   catégories, promotions et nouveautés.
   ========================================================= */
const VueAccueil = (() => {

  const DELAI_SLIDER = 4500; // défilement automatique
  let minuterie = null;
  let derniereInteraction = 0;

  /* ---------- Slider ---------- */

  function slide(p, index) {
    const src = Catalogue.imagePrincipale(p);
    const remise = Utils.remisePourcent(p.ancienPrix, p.prix);
    const devise = Catalogue.boutique().devise;
    return (
      '<a class="slide' + (src ? "" : " slide-sans-photo") + '" href="#/produit/' + Utils.echapper(p.id) + '" aria-label="' + Utils.echapper(p.nom) + '">' +
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

  function htmlSlider(enAvant) {
    if (!enAvant.length) return "";
    return (
      '<section class="slider" aria-label="Produits mis en avant">' +
        '<div class="slider-piste" id="slider-piste">' + enAvant.map(slide).join("") + "</div>" +
        (enAvant.length > 1
          ? '<div class="slider-points" id="slider-points">' +
              enAvant.map((p, i) =>
                '<button type="button" data-slide="' + i + '" aria-label="Produit ' + (i + 1) + '"' +
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

  /* ---------- Vue ---------- */

  async function afficher(vue) {
    UI.entete({ accueil: true, actions:
      '<button type="button" class="btn-ic" id="accueil-actualiser" aria-label="Actualiser le catalogue">' +
        UI.icone("actualiser") + "</button>" +
      '<a class="btn-ic" href="#/recherche" aria-label="Rechercher">' + UI.icone("recherche") + "</a>" });

    const enAvant = Catalogue.misEnAvant();
    const categories = Catalogue.categories();
    const comptes = Catalogue.nombreParCategorie();
    const promos = Catalogue.promotions().slice(0, 8);
    const nouveautes = Catalogue.nouveautes(8);
    const boutique = Catalogue.boutique();

    let html = "";

    html += htmlSlider(enAvant);

    if (Catalogue.depuisCache()) {
      html +=
        '<div class="note-hors-ligne">' + UI.icone("alerte", "ic-sm") +
        " Hors connexion — catalogue du " + Utils.echapper(Utils.fmtDateHeure(new Date(Catalogue.versionPubliee() || 0).getTime())) + "</div>";
    } else if (Catalogue.modeDemo()) {
      html +=
        '<div class="note-hors-ligne">' + UI.icone("alerte", "ic-sm") +
        " Catalogue de démonstration — la connexion à la boutique se règle dans l'onglet Infos.</div>";
    }

    if (categories.length) {
      html += UI.titreSection("Catégories", "#/categories");
      html += '<div class="cat-grille">' +
        categories.slice(0, 6).map((c) => carteCategorie(c, comptes[c.id] || 0)).join("") +
      "</div>";
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

    const btnActualiser = UI.$("#accueil-actualiser");
    if (btnActualiser) {
      btnActualiser.onclick = async () => {
        btnActualiser.disabled = true;
        btnActualiser.classList.add("tourne");
        const change = await Live.verifier();
        btnActualiser.disabled = false;
        btnActualiser.classList.remove("tourne");
        if (!change) UI.toast("Catalogue déjà à jour", "ok");
      };
    }
  }

  return { afficher, arreterSlider };
})();
