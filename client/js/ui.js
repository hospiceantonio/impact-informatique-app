/* =========================================================
   UI — briques d'interface : entête avec logo, cartes
   produit, prix, badges, toasts, visionneuse.
   ========================================================= */
const UI = (() => {

  const $ = (sel, base) => (base || document).querySelector(sel);
  const $$ = (sel, base) => Array.from((base || document).querySelectorAll(sel));
  const e = Utils.echapper;

  /* ---------- Logo (reprend la charte du logo officiel) ---------- */

  /** Rond bleu avec le "i" blanc et les ondes — la marque de la boutique. */
  function marque(taille = 40) {
    return (
      '<svg class="marque" width="' + taille + '" height="' + taille + '" viewBox="0 0 64 64" aria-hidden="true">' +
        '<defs><linearGradient id="grad-marque" x1="0" y1="0" x2="1" y2="1">' +
          '<stop offset="0" stop-color="#3D9BEE"/><stop offset="1" stop-color="#0B4FA0"/>' +
        "</linearGradient></defs>" +
        '<circle cx="32" cy="36" r="24" fill="url(#grad-marque)"/>' +
        '<g transform="translate(32 36) skewX(-8)">' +
          '<rect x="-4.5" y="-8" width="9" height="26" rx="4.5" fill="#fff"/>' +
          '<circle cx="2" cy="-17" r="5" fill="#fff"/>' +
        "</g>" +
        '<g fill="none" stroke="#fff" stroke-width="3.4" stroke-linecap="round" opacity=".95">' +
          '<path d="M42 13a12 12 0 0 0-9-4"/>' +
          '<path d="M47 7.5A19 19 0 0 0 33 2.5"/>' +
        "</g>" +
      "</svg>"
    );
  }

  /** Logo complet : rond + "mpact" rouge + sous-titre, pour l'accueil. */
  function logo() {
    return (
      '<span class="logo">' +
        marque(46) +
        '<span class="logo-textes">' +
          '<span class="logo-nom"><i>mpact</i></span>' +
          '<span class="logo-sous">Informatique &amp; Électronique</span>' +
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
      (accueil ? '<div class="topbar-slogan">' + e(Catalogue.boutique().slogan) + "</div>" : "");
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

  let photoAffichee = null;  // { src, nom } pour le bouton d'enregistrement

  function ouvrirVisionneuse(src, nomFichier) {
    $("#visionneuse-img").src = src;
    $("#visionneuse").hidden = false;
    document.body.style.overflow = "hidden";
    photoAffichee = { src, nom: nomFichier || "photo.jpg" };
    const bouton = $("#visionneuse-telecharger");
    if (bouton) bouton.hidden = !nomFichier;
  }

  const photoVisionneuse = () => photoAffichee;

  function fermerVisionneuse() {
    $("#visionneuse").hidden = true;
    $("#visionneuse-img").src = "";
    document.body.style.overflow = "";
  }

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
    if (!p.disponible) html += '<span class="badge badge-rupture">Rupture</span>';
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

  return {
    $, $$, entete, icone, marque, logo, toast,
    ouvrirVisionneuse, fermerVisionneuse, photoVisionneuse,
    iconeCategorie, prixHtml, badgesProduit, pastilleVideo, imageProduit,
    carteProduit, grilleProduits, carteProduitMini, rangeeProduits,
    titreSection, vide,
  };
})();
