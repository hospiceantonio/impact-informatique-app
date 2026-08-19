/* =========================================================
   UI — briques d'interface : entête, feuille modale, toasts,
   visionneuse, lignes produit, champs de formulaire.
   ========================================================= */
const UI = (() => {

  const $ = (sel, base) => (base || document).querySelector(sel);
  const $$ = (sel, base) => Array.from((base || document).querySelectorAll(sel));
  const e = Utils.echapper;

  /* ---------- Marque (reprend la charte du logo officiel) ---------- */

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

  function logoAdmin() {
    return (
      '<span class="logo">' +
        marque(44) +
        '<span class="logo-textes">' +
          '<span class="logo-nom">BIZZOO</span>' +
          '<span class="logo-sous">Espace admin</span>' +
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
          ? '<div class="topbar-logo">' + logoAdmin() + "</div>"
          : "<div style='flex:1;min-width:0'>" +
              "<h1>" + e(titre || "") + "</h1>" +
              (sous ? '<div class="sous">' + e(sous) + "</div>" : "") +
            "</div>") +
        '<div class="topbar-actions">' + (actions || "") + "</div>" +
      "</div>";
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

  /* ---------- Feuille modale ---------- */

  let feuilleAuFermer = null;

  function ouvrirFeuille(titre, html, auFermer) {
    const feuille = $("#feuille");
    $("#feuille-titre").textContent = titre;
    $("#feuille-corps").innerHTML = html;
    feuille.hidden = false;
    document.body.style.overflow = "hidden";
    feuilleAuFermer = auFermer || null;
    return $("#feuille-corps");
  }

  function fermerFeuille() {
    const feuille = $("#feuille");
    if (feuille.hidden) return;
    feuille.hidden = true;
    $("#feuille-corps").innerHTML = "";
    document.body.style.overflow = "";
    if (feuilleAuFermer) { const fn = feuilleAuFermer; feuilleAuFermer = null; fn(); }
  }

  function feuilleSansRappel() { feuilleAuFermer = null; }

  /* ---------- Confirmation ---------- */

  function confirmer({ titre, texte, bouton, danger }) {
    return new Promise((resolve) => {
      const corps = ouvrirFeuille(titre,
        '<div class="carte" style="box-shadow:none;padding:0"><p style="margin:0 0 16px;font-size:14.5px;line-height:1.55;color:var(--encre-douce)">' + e(texte) + "</p>" +
        '<div class="btn-rangee">' +
          '<button type="button" class="btn btn-clair" data-role="annuler">Annuler</button>' +
          '<button type="button" class="btn ' + (danger ? "btn-danger" : "") + '" data-role="ok">' + e(bouton || "Confirmer") + "</button>" +
        "</div></div>",
        () => resolve(false));
      $("[data-role=annuler]", corps).onclick = () => fermerFeuille();
      $("[data-role=ok]", corps).onclick = () => {
        feuilleSansRappel();
        fermerFeuille();
        resolve(true);
      };
    });
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
  }

  function fermerVisionneuse() {
    const visionneuse = $("#visionneuse");
    if (!visionneuse || visionneuse.hidden) return;
    visionneuse.hidden = true;
    $("#visionneuse-piste").innerHTML = "";
    photosVisionneuse = [];
    indexVisionneuse = 0;
    if ($("#feuille").hidden) document.body.style.overflow = "";
  }

  /* ---------- Composants produit ---------- */

  function vignetteProduit(p) {
    if (p.vignette) return '<span class="pastille"><img src="' + p.vignette + '" alt=""></span>';
    return '<span class="pastille pastille-vide">' + icone("image", "ic-sm") + "</span>";
  }

  function badgesProduit(p) {
    const remise = Utils.remisePourcent(p.ancienPrix, p.prix);
    let html = "";
    if (p.enAvant) html += '<span class="badge badge-avant">' + icone("etoile", "ic-sm") + "En avant</span>";
    if (Store.enVenteFlash(p)) html += '<span class="badge badge-flash">' + icone("energie", "ic-sm") + "Vente flash</span>";
    if (remise !== null) html += '<span class="badge badge-promo">-' + remise + " %</span>";
    const etat = Store.statut(p);
    if (etat !== "disponible") {
      html += '<span class="badge badge-' + etat + '">' + Store.STATUTS[etat].nom + "</span>";
    }
    return html;
  }

  function ligneProduit(p, sousTitre) {
    const devise = Store.lireReglages().devise;
    return (
      '<button type="button" class="ligne" data-nav="#/produit/' + e(p.id) + '">' +
        vignetteProduit(p) +
        '<span class="ligne-corps">' +
          '<span class="ligne-titre">' + e(p.nom) + "</span>" +
          '<span class="ligne-sous">' + e(sousTitre || "") + "</span>" +
        "</span>" +
        '<span class="ligne-fin">' +
          '<span class="ligne-montant">' + e(Utils.fmtMontant(p.prix, devise)) + "</span>" +
          '<span class="ligne-stock' + (Store.statut(p) === "rupture" ? " ligne-stock-vide" : "") + '">' +
            (p.surCommande ? "Sans stock" : "Stock " + p.stock) + "</span>" +
          '<span class="ligne-badges">' + badgesProduit(p) + "</span>" +
        "</span>" +
      "</button>"
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

  /* ---------- Champs de formulaire ---------- */

  function champTexte({ id, label, valeur, obligatoire, aide, placeholder, type }) {
    return (
      '<div class="champ">' +
        '<label for="' + id + '">' + e(label) + (obligatoire ? ' <span class="obligatoire">*</span>' : "") + "</label>" +
        '<input id="' + id + '" type="' + (type || "text") + '" autocomplete="off"' +
          (placeholder ? ' placeholder="' + e(placeholder) + '"' : "") +
          (valeur !== undefined && valeur !== null ? ' value="' + e(valeur) + '"' : "") + ">" +
        (aide ? '<div class="aide">' + e(aide) + "</div>" : "") +
      "</div>"
    );
  }

  function champMontant({ id, label, valeur, obligatoire, aide, placeholder }) {
    const devise = Store.lireReglages().devise;
    return (
      '<div class="champ">' +
        '<label for="' + id + '">' + e(label) + (obligatoire ? ' <span class="obligatoire">*</span>' : "") + "</label>" +
        '<div class="champ-montant">' +
          '<input id="' + id + '" inputmode="numeric" autocomplete="off" placeholder="' + e(placeholder || "0") + '"' +
            (valeur !== undefined && valeur !== null && valeur !== "" ? ' value="' + e(Utils.fmtNombre(valeur)) + '"' : "") + ">" +
          '<span class="devise">' + e(devise) + "</span>" +
        "</div>" +
        (aide ? '<div class="aide">' + e(aide) + "</div>" : "") +
      "</div>"
    );
  }

  function champZone({ id, label, valeur, aide, lignes, placeholder }) {
    return (
      '<div class="champ">' +
        '<label for="' + id + '">' + e(label) + "</label>" +
        '<textarea id="' + id + '" rows="' + (lignes || 4) + '"' +
          (placeholder ? ' placeholder="' + e(placeholder) + '"' : "") + ">" +
          e(valeur || "") + "</textarea>" +
        (aide ? '<div class="aide">' + e(aide) + "</div>" : "") +
      "</div>"
    );
  }

  function interrupteur({ id, label, actif, aide }) {
    return (
      '<label class="inter" for="' + id + '">' +
        '<span class="inter-textes"><span class="inter-label">' + e(label) + "</span>" +
          (aide ? '<span class="aide">' + e(aide) + "</span>" : "") +
        "</span>" +
        '<input type="checkbox" id="' + id + '"' + (actif ? " checked" : "") + ">" +
        '<span class="inter-piste"><span class="inter-pouce"></span></span>' +
      "</label>"
    );
  }

  return {
    $, $$, entete, icone, marque, logoAdmin, toast,
    ouvrirFeuille, fermerFeuille, feuilleSansRappel, confirmer,
    ouvrirVisionneuse, fermerVisionneuse,
    vignetteProduit, badgesProduit, ligneProduit, vide,
    champTexte, champMontant, champZone, interrupteur,
  };
})();
