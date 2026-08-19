/* =========================================================
   UI — briques d'interface : entête avec logo, cartes
   produit, prix, badges, toasts, visionneuse.
   ========================================================= */
const UI = (() => {

  const $ = (sel, base) => (base || document).querySelector(sel);
  const $$ = (sel, base) => Array.from((base || document).querySelectorAll(sel));
  const e = Utils.echapper;

  /* ---------- Logo (reprend la charte du logo officiel) ---------- */

  /** Le sac de BIZZOO : un carré arrondi bleu, l'anse et le sac en blanc. */
  function marque(taille = 40) {
    return (
      '<svg class="marque" width="' + taille + '" height="' + taille + '" viewBox="0 0 64 64" aria-hidden="true">' +
        '<defs><linearGradient id="grad-marque" x1="0" y1="0" x2="1" y2="1">' +
          '<stop offset="0" stop-color="#3D9BEE"/><stop offset="1" stop-color="#0B4FA0"/>' +
        "</linearGradient></defs>" +
        '<rect x="2" y="2" width="60" height="60" rx="17" fill="url(#grad-marque)"/>' +
        /* L'anse d'abord : le sac vient ensuite en cacher les deux bouts. */
        '<path d="M24.3 32.7a7.7 7.7 0 0 1 15.4 0" fill="none" stroke="#fff" stroke-width="2.6"/>' +
        '<rect x="15.7" y="31.4" width="32.6" height="19.2" rx="2.6" fill="#fff"/>' +
      "</svg>"
    );
  }

  /** Logo complet : le sac + « BIZZOO », pour l'accueil. */
  function logo() {
    return (
      '<span class="logo">' +
        marque(46) +
        '<span class="logo-textes">' +
          '<span class="logo-nom">BIZZOO</span>' +
          '<span class="logo-sous">Toutes vos boutiques</span>' +
        "</span>" +
      "</span>"
    );
  }

  /* ---------- Barre supérieure ---------- */

  function entete({ titre, sous, retour, accueil, actions }) {
    const zone = $("#topbar");
    zone.innerHTML =
      '<div class="topbar-ligne">' +
        (retour
          ? '<button type="button" class="btn-ic" data-action="retour" aria-label="Retour">' + icone("retour") + "</button>"
          : "") +
        (accueil
          ? '<div class="topbar-logo">' + logo() + "</div>"
          : "<div style='flex:1;min-width:0'>" +
              "<h1>" + e(titre || "") + "</h1>" +
              (sous ? '<div class="sous">' + e(sous) + "</div>" : "") +
            "</div>") +
        '<div class="topbar-actions">' + (actions || "") + "</div>" +
      "</div>" +
      (accueil && Catalogue.boutique().slogan
        ? '<div class="topbar-slogan">' + e(Catalogue.boutique().slogan) + "</div>"
        : "");
    mesurerEntete();
  }

  /* La barre du haut ne fait pas toujours la même hauteur : logo et
     slogan sur l'accueil, titre seul ailleurs, deux lignes quand il y a
     un sous-titre. Ce qui doit se figer juste en dessous — les
     sous-catégories d'un rayon — lit sa hauteur dans « --haut-topbar ». */

  let mesureEnAttente = false;

  function mesurerEntete() {
    if (mesureEnAttente) return;
    mesureEnAttente = true;
    requestAnimationFrame(() => {
      mesureEnAttente = false;
      const zone = $("#topbar");
      if (!zone) return;
      const hauteur = Math.round(zone.getBoundingClientRect().height);
      if (hauteur) document.documentElement.style.setProperty("--haut-topbar", hauteur + "px");
    });
  }

  /* Rotation de l'écran, retour de la barre système, police agrandie… */
  window.addEventListener("resize", mesurerEntete);
  if (window.ResizeObserver) {
    const observateur = new ResizeObserver(mesurerEntete);
    const surveiller = () => {
      const zone = $("#topbar");
      if (zone) observateur.observe(zone);
    };
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", surveiller);
    } else {
      surveiller();
    }
  }

  function icone(nom, classe) {
    return '<svg class="ic' + (classe ? " " + classe : "") + '" viewBox="0 0 24 24" aria-hidden="true"><use href="#i-' + nom + '"/></svg>';
  }

  /* ---------- Toasts ---------- */

  function toast(message, type) {
    const zone = $("#toasts");
    zone.innerHTML = ""; // un seul toast à la fois
    const el = document.createElement("div");
    el.className = "toast" + (type ? " toast-" + type : "");
    el.textContent = message;
    zone.appendChild(el);
    setTimeout(() => {
      el.style.transition = "opacity .25s";
      el.style.opacity = "0";
      setTimeout(() => el.remove(), 260);
    }, 2600);
  }

  /* ---------- Visionneuse ---------- */

  /* ---------- Visionneuse : galerie plein écran ----------
     On ouvre une photo, on fait défiler toutes celles de
     l'article du bout du doigt. */

  let photosVisionneuse = [];
  let indexVisionneuse = 0;
  let visionneuseBranchee = false;

  function normaliserPhotos(photos) {
    return (Array.isArray(photos) ? photos : [photos])
      .map((p) => (typeof p === "string" ? { src: p, nom: "" } : { src: p.src, nom: p.nom || "" }))
      .filter((p) => p.src);
  }

  function ouvrirVisionneuse(photos, index) {
    const liste = normaliserPhotos(photos);
    if (!liste.length) return;
    photosVisionneuse = liste;
    indexVisionneuse = Math.min(Math.max(Number(index) || 0, 0), liste.length - 1);

    const piste = $("#visionneuse-piste");
    piste.innerHTML = liste.map((p, i) =>
      '<div class="visionneuse-vue"><img src="' + e(p.src) + '" alt="Photo ' + (i + 1) + '"></div>'
    ).join("");

    const points = $("#visionneuse-points");
    points.innerHTML = liste.length > 1
      ? liste.map((_, i) => '<button type="button" data-vue="' + i + '" aria-label="Photo ' + (i + 1) + '"></button>').join("")
      : "";

    $("#visionneuse").hidden = false;
    document.body.style.overflow = "hidden";
    brancherVisionneuse();

    /* Se placer sur la photo choisie une fois la largeur connue. */
    requestAnimationFrame(() => {
      piste.scrollLeft = indexVisionneuse * piste.clientWidth;
      majVisionneuse();
    });
  }

  function brancherVisionneuse() {
    if (visionneuseBranchee) return;
    visionneuseBranchee = true;

    $("#visionneuse-piste").addEventListener("scroll", Utils.tempo(majVisionneuse, 60), { passive: true });
    $("#visionneuse-points").addEventListener("click", (ev) => {
      const bouton = ev.target.closest("[data-vue]");
      if (bouton) allerAPhoto(Number(bouton.dataset.vue));
    });
    $("#visionneuse-precedent").onclick = () => allerAPhoto(indexVisionneuse - 1);
    $("#visionneuse-suivant").onclick = () => allerAPhoto(indexVisionneuse + 1);
    document.addEventListener("keydown", (ev) => {
      if ($("#visionneuse").hidden) return;
      if (ev.key === "ArrowLeft") allerAPhoto(indexVisionneuse - 1);
      if (ev.key === "ArrowRight") allerAPhoto(indexVisionneuse + 1);
    });
  }

  function allerAPhoto(rang) {
    const piste = $("#visionneuse-piste");
    const cible = Math.min(Math.max(rang, 0), photosVisionneuse.length - 1);
    piste.scrollTo({ left: cible * piste.clientWidth, behavior: "smooth" });
  }

  /** Met à jour points, compteur et flèches selon la photo affichée. */
  function majVisionneuse() {
    const piste = $("#visionneuse-piste");
    if (!piste || !piste.clientWidth) return;
    const total = photosVisionneuse.length;
    indexVisionneuse = Math.min(Math.round(piste.scrollLeft / piste.clientWidth), Math.max(0, total - 1));

    for (const point of $$("#visionneuse-points [data-vue]")) {
      point.classList.toggle("actif", Number(point.dataset.vue) === indexVisionneuse);
    }
    const compteur = $("#visionneuse-compteur");
    if (compteur) compteur.textContent = total > 1 ? (indexVisionneuse + 1) + " / " + total : "";

    const precedent = $("#visionneuse-precedent");
    const suivant = $("#visionneuse-suivant");
    if (precedent) precedent.hidden = total < 2 || indexVisionneuse === 0;
    if (suivant) suivant.hidden = total < 2 || indexVisionneuse === total - 1;

    const telecharger = $("#visionneuse-telecharger");
    if (telecharger) telecharger.hidden = !(photosVisionneuse[indexVisionneuse] || {}).nom;
  }

  function fermerVisionneuse() {
    const visionneuse = $("#visionneuse");
    if (!visionneuse || visionneuse.hidden) return;
    visionneuse.hidden = true;
    $("#visionneuse-piste").innerHTML = "";
    photosVisionneuse = [];
    indexVisionneuse = 0;
    document.body.style.overflow = "";
  }

  const photoVisionneuse = () => photosVisionneuse[indexVisionneuse] || null;

  /* ---------- Icônes de catégories ---------- */

  const ICONES_CATEGORIES = [
    [/portable|laptop|ordinateur/, "portable"],
    [/bureau|tour|unite|serveur/, "bureau"],
    [/imprimante|scanner|photocop|multifonction/, "imprimante"],
    [/encre|cartouche|consommable/, "goutte"],
    [/toner|laser/, "goutte"],
    [/papier|rame/, "boite"],
    [/souris|clavier|accessoire/, "souris"],
    [/casque|audio|son|enceinte/, "casque"],
    [/sacoche|sac/, "sacoche"],
    [/cle|usb|stockage/, "usb"],
    [/disque|ssd|memoire|carte/, "disque"],
    [/reseau|wifi|routeur|internet/, "wifi"],
    [/cable|adaptateur|connectique|chargeur/, "cable"],
    [/onduleur|energie|batterie|solaire/, "energie"],
    [/telephone|tablette|mobile|smartphone/, "telephone"],
    [/ecran|moniteur|tele|tv|projecteur/, "ecran"],
  ];

  function iconeCategorie(nom) {
    const t = Utils.sansAccent(nom);
    for (const [motif, ic] of ICONES_CATEGORIES) {
      if (motif.test(t)) return ic;
    }
    return "boite";
  }

  /* ---------- Prix & badges ---------- */

  function prixHtml(p, options) {
    const o = options || {};
    const devise = Catalogue.boutique().devise;
    const remise = Utils.remisePourcent(p.ancienPrix, p.prix);
    return (
      '<span class="prix' + (o.grand ? " prix-grand" : "") + '">' +
        '<span class="prix-actuel">' + e(Utils.fmtMontant(p.prix, devise)) + "</span>" +
        (remise !== null
          ? ' <s class="prix-ancien">' + e(Utils.fmtMontant(p.ancienPrix, devise)) + "</s>"
          : "") +
      "</span>"
    );
  }

  function badgesProduit(p) {
    const remise = Utils.remisePourcent(p.ancienPrix, p.prix);
    let html = "";
    if (remise !== null) html += '<span class="badge badge-promo">-' + remise + " %</span>";
    const etat = Catalogue.statut(p);
    html += '<span class="badge ' + Catalogue.STATUTS[etat].classe + '">' +
      Catalogue.STATUTS[etat].nom + "</span>";
    return html;
  }

  /** Pastille « vidéo » posée sur la photo d'une carte. */
  function pastilleVideo(p) {
    return p && p.video ? '<span class="pastille-video">' + icone("video", "ic-sm") + "</span>" : "";
  }

  /** Image principale d'un produit, ou pastille logo si aucune photo. */
  function imageProduit(p, classe) {
    const src = Catalogue.imagePrincipale(p);
    if (src) {
      return '<img class="' + classe + '" src="' + e(src) + '" alt="' + e(p.nom) + '" loading="lazy">';
    }
    return '<span class="' + classe + ' img-absente">' + marque(46) + "</span>";
  }

  /* ---------- Cartes produit ---------- */

  /** Carte pour les grilles à 2 colonnes. */
  function carteProduit(p) {
    const sc = Catalogue.sousCategorie(p.categorieId, p.sousCategorieId);
    const cat = Catalogue.categorie(p.categorieId);
    return (
      '<a class="p-carte" href="#/produit/' + e(p.id) + '">' +
        '<span class="p-carte-img">' +
          imageProduit(p, "p-carte-photo") +
          '<span class="p-carte-badges">' + badgesProduit(p) + "</span>" +
          pastilleVideo(p) +
        "</span>" +
        '<span class="p-carte-corps">' +
          '<span class="p-carte-nom">' + e(p.nom) + "</span>" +
          prixHtml(p) +
          '<span class="p-carte-cat">' + e(sc ? sc.nom : (cat ? cat.nom : "")) + "</span>" +
        "</span>" +
      "</a>"
    );
  }

  function grilleProduits(liste) {
    if (!liste.length) return "";
    return '<div class="p-grille">' + liste.map(carteProduit).join("") + "</div>";
  }

  /** Petite carte pour les rangées horizontales (nouveautés, similaires). */
  function carteProduitMini(p) {
    return (
      '<a class="p-mini" href="#/produit/' + e(p.id) + '">' +
        '<span class="p-mini-img">' +
          imageProduit(p, "p-mini-photo") +
          '<span class="p-carte-badges">' + badgesProduit(p) + "</span>" +
          pastilleVideo(p) +
        "</span>" +
        '<span class="p-mini-nom">' + e(p.nom) + "</span>" +
        prixHtml(p) +
      "</a>"
    );
  }

  function rangeeProduits(liste) {
    if (!liste.length) return "";
    return '<div class="p-rangee">' + liste.map(carteProduitMini).join("") + "</div>";
  }

  /* ---------- Divers ---------- */

  function titreSection(titre, lien, texteLien) {
    return (
      '<div class="section-titre">' +
        "<h2>" + e(titre) + "</h2>" +
        (lien ? '<a class="section-lien" href="' + e(lien) + '">' + e(texteLien || "Tout voir") + " " + icone("chevron", "ic-sm") + "</a>" : "") +
      "</div>"
    );
  }

  function vide(icon, titre, note, bouton) {
    return (
      '<div class="vide">' + icone(icon) +
        "<p>" + e(titre) + "</p>" +
        (note ? "<small>" + e(note) + "</small>" : "") +
        (bouton || "") +
      "</div>"
    );
  }

  /**
   * Le bandeau « vous êtes dans telle boutique », posé en haut des
   * écrans qui ne parlent que d'elle. Il ramène aux autres boutiques.
   */
  function bandeauBoutique() {
    const b = Catalogue.boutiqueChoisie();
    if (!b) return "";
    return (
      '<a class="bou-bandeau" href="#/">' +
        (b.logo
          ? '<span class="bou-rond bou-rond-photo"><img src="' + e(b.logo) + '" alt=""></span>'
          : '<span class="bou-rond" style="background:' + e(b.couleur) + '">' + icone(b.icone) + "</span>") +
        "<span><strong>" + e(b.nom) + "</strong>" +
          "Changer de boutique</span>" +
        icone("chevron", "ic-sm") +
      "</a>"
    );
  }

  return {
    $, $$, entete, icone, marque, logo, toast, bandeauBoutique,
    ouvrirVisionneuse, fermerVisionneuse, photoVisionneuse,
    iconeCategorie, prixHtml, badgesProduit, pastilleVideo, imageProduit,
    carteProduit, grilleProduits, carteProduitMini, rangeeProduits,
    titreSection, vide,
  };
})();
