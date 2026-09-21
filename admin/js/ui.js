/* =========================================================
   UI — briques d'interface : entête, feuille modale, toasts,
   visionneuse, lignes produit, champs de formulaire.
   ========================================================= */
const UI = (() => {

  const $ = (sel, base) => (base || document).querySelector(sel);
  const $$ = (sel, base) => Array.from((base || document).querySelectorAll(sel));
  const e = Utils.echapper;

  /* ---------- Marque (reprend la charte du logo officiel) ---------- */

  /**
   * La marque : l'icône même de l'application, celle qu'on voit sur
   * l'écran d'accueil du téléphone. Un seul dessin pour les deux —
   * plus de version approchée qui finirait par diverger.
   * Le fichier est déjà gardé hors connexion par le service worker.
   */
  /**
   * LE MOT-SYMBOLE BIZZOO, écrit et non dessiné.
   *
   * « Bizz » en bleu, « oo » en orange, et les deux points sous le
   * mot. Le tracer en texte plutôt qu'en image lui donne trois choses
   * qu'une image n'a pas : il reste net à toutes les tailles, il ne
   * pèse rien, et il s'affiche sans réseau comme sans fichier.
   *
   * L'icône carrée, elle, reste une image : c'est le raccourci sur
   * l'écran d'accueil du téléphone, et Android la veut en PNG.
   */
  function motSymbole(classe) {
    return (
      '<span class="logo-mot' + (classe ? " " + classe : "") + '" aria-label="BIZZOO">' +
        '<span class="logo-bizz">Bizz</span><span class="logo-oo">oo</span>' +
        '<span class="logo-points" aria-hidden="true"><i></i><i></i></span>' +
      "</span>"
    );
  }

  function marque(taille = 40) {
    return (
      '<img class="marque" src="icons/icon-192.png" alt="" aria-hidden="true"' +
      ' width="' + taille + '" height="' + taille + '">'
    );
  }

  function logoAdmin() {
    return (
      '<span class="logo">' +
        '<span class="logo-textes">' +
          motSymbole() +
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
    /* LE TEMPS DE LIRE. 2,6 s suffisent pour « Enregistré » ; un
       avertissement de trois lignes disparaissait avant d'être lu — et
       un avertissement qu'on ne lit pas ne sert à rien. On compte donc
       sur la longueur du message, sans descendre sous 2,6 s ni monter
       au-delà de 8 : passé ce délai, ce serait une fenêtre qu'il
       faudrait, pas un toast. */
    const duree = Math.min(8000, Math.max(2600, 1200 + message.length * 45));
    setTimeout(() => {
      el.style.transition = "opacity .25s";
      el.style.opacity = "0";
      setTimeout(() => el.remove(), 260);
    }, duree);
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

  /**
   * Comme `confirmer`, mais on repart avec une phrase : le motif d'un
   * refus, par exemple. Rend le texte saisi, ou `null` si on renonce —
   * une chaîne vide reste une réponse, elle veut dire « sans motif ».
   */
  function demanderTexte({ titre, texte, libelle, bouton, danger, valeur }) {
    return new Promise((resolve) => {
      const corps = ouvrirFeuille(titre,
        '<div class="carte" style="box-shadow:none;padding:0">' +
          (texte
            ? '<p style="margin:0 0 14px;font-size:14.5px;line-height:1.55;color:var(--encre-douce)">' +
              e(texte) + "</p>"
            : "") +
          champZone({ id: "saisie-motif", label: libelle || "Votre réponse",
            valeur: valeur || "", lignes: 3 }) +
          '<div class="btn-rangee" style="margin-top:14px">' +
            '<button type="button" class="btn btn-clair" data-role="annuler">Annuler</button>' +
            '<button type="button" class="btn ' + (danger ? "btn-danger" : "") +
              '" data-role="ok">' + e(bouton || "Envoyer") + "</button>" +
          "</div></div>",
        () => resolve(null));
      const champ = $("#saisie-motif", corps);
      if (champ) setTimeout(() => champ.focus(), 80);
      $("[data-role=annuler]", corps).onclick = () => fermerFeuille();
      $("[data-role=ok]", corps).onclick = () => {
        const reponse = champ ? champ.value.trim() : "";
        feuilleSansRappel();
        fermerFeuille();
        resolve(reponse);
      };
    });
  }

  /* ---------- Visionneuse ---------- */

  /* ---------- Visionneuse : galerie plein écran ----------
     On ouvre une photo, on fait défiler toutes celles de
     l'article du bout du doigt, et on grossit celle qu'on
     regarde pour en juger le détail. */

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
    reinitialiserZoom();

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
      if (ev.key === "+" || ev.key === "=") basculerZoom();
      if (ev.key === "-") reinitialiserZoom();
    });
    brancherZoom($("#visionneuse-piste"));
  }

  function allerAPhoto(rang) {
    const piste = $("#visionneuse-piste");
    const cible = Math.min(Math.max(rang, 0), photosVisionneuse.length - 1);
    reinitialiserZoom();
    piste.scrollTo({ left: cible * piste.clientWidth, behavior: "smooth" });
  }

  /* ---------- Visionneuse : zoom ----------
     Pincer à deux doigts pour grossir, promener la photo du bout
     du doigt, taper deux fois pour aller et venir entre la vue
     d'ensemble et le détail. À la souris : molette et double-clic,
     et le bouton loupe pour ceux qui ne devinent pas le geste.

     On revient toujours à 1× en changeant de photo : sinon la
     suivante s'ouvrirait déjà agrandie, sur un coin qu'on n'a pas
     choisi. */

  const ZOOM_MAX = 4;
  const ZOOM_TAPE = 2.5;   // ce que donne une double-tape
  let zoom = 1;
  let zoomX = 0;           // décalage de la photo, en pixels d'écran
  let zoomY = 0;
  let pince = null;        // geste à deux doigts en cours
  let glisse = null;       // photo agrandie promenée à un doigt
  let derniereTape = 0;
  let dernierToucher = 0;  // pour ignorer le dblclick fabriqué par le tactile

  const borner = (v, min, max) => Math.min(Math.max(v, min), max);
  const estAgrandie = () => zoom > 1.001;

  function imageActive() {
    return $$("#visionneuse-piste .visionneuse-vue img")[indexVisionneuse] || null;
  }

  /** La photo ne quitte jamais le cadre : on retient ses bords. */
  function retenirZoom() {
    const img = imageActive();
    const piste = $("#visionneuse-piste");
    if (!img || !piste) return;
    const debord = (taille, cadre) => Math.max(0, (taille * zoom - cadre) / 2);
    const x = debord(img.clientWidth, piste.clientWidth);
    const y = debord(img.clientHeight, piste.clientHeight);
    zoomX = borner(zoomX, -x, x);
    zoomY = borner(zoomY, -y, y);
  }

  function appliquerZoom() {
    if (!estAgrandie()) { zoomX = 0; zoomY = 0; }
    retenirZoom();
    const img = imageActive();
    const piste = $("#visionneuse-piste");
    if (img) {
      img.style.transform = estAgrandie()
        ? "translate(" + zoomX + "px," + zoomY + "px) scale(" + zoom + ")"
        : "";
    }
    /* Agrandie, la photo garde le doigt pour elle : on ne passe à
       la suivante qu'une fois revenu à 1×. */
    if (piste) piste.classList.toggle("figee", estAgrandie());
    marquerBoutonZoom();
  }

  function marquerBoutonZoom() {
    const bouton = $("#visionneuse-zoom");
    if (!bouton) return;
    bouton.classList.toggle("actif", estAgrandie());
    bouton.setAttribute("aria-label", estAgrandie() ? "Revenir à la taille normale" : "Agrandir la photo");
  }

  function reinitialiserZoom() {
    zoom = 1;
    zoomX = 0;
    zoomY = 0;
    pince = null;
    glisse = null;
    for (const img of $$("#visionneuse-piste .visionneuse-vue img")) img.style.transform = "";
    const piste = $("#visionneuse-piste");
    if (piste) piste.classList.remove("figee", "pincee");
    marquerBoutonZoom();
  }

  /** Grossit autour d'un point de l'écran : ce qu'on vise ne bouge pas. */
  function zoomerVers(niveau, versX, versY) {
    const piste = $("#visionneuse-piste");
    if (!piste) return;
    const cadre = piste.getBoundingClientRect();
    const centreX = cadre.left + cadre.width / 2 + zoomX;
    const centreY = cadre.top + cadre.height / 2 + zoomY;
    const cible = borner(niveau, 1, ZOOM_MAX);
    const rapport = cible / (zoom || 1);
    zoomX += (versX - centreX) * (1 - rapport);
    zoomY += (versY - centreY) * (1 - rapport);
    zoom = cible;
    appliquerZoom();
  }

  /** Le bouton loupe et la double-tape : agrandir, ou tout remettre. */
  function basculerZoom(versX, versY) {
    const piste = $("#visionneuse-piste");
    if (!piste) return;
    if (estAgrandie()) { reinitialiserZoom(); return; }
    const cadre = piste.getBoundingClientRect();
    zoomerVers(ZOOM_TAPE,
      versX == null ? cadre.left + cadre.width / 2 : versX,
      versY == null ? cadre.top + cadre.height / 2 : versY);
  }

  const ecartDoigts = (a, b) => Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY) || 1;

  function brancherZoom(piste) {
    piste.addEventListener("touchstart", (ev) => {
      piste.classList.add("pincee"); // pas d'animation pendant le geste
      if (ev.touches.length === 2) {
        pince = {
          ecart: ecartDoigts(ev.touches[0], ev.touches[1]),
          depart: zoom,
          x: (ev.touches[0].clientX + ev.touches[1].clientX) / 2,
          y: (ev.touches[0].clientY + ev.touches[1].clientY) / 2,
        };
        glisse = null;
        ev.preventDefault();
      } else if (ev.touches.length === 1) {
        const t = ev.touches[0];
        glisse = { x: t.clientX, y: t.clientY, xDepart: t.clientX, yDepart: t.clientY, bouge: false };
      }
    }, { passive: false });

    piste.addEventListener("touchmove", (ev) => {
      if (pince && ev.touches.length === 2) {
        const ecart = ecartDoigts(ev.touches[0], ev.touches[1]);
        const x = (ev.touches[0].clientX + ev.touches[1].clientX) / 2;
        const y = (ev.touches[0].clientY + ev.touches[1].clientY) / 2;
        zoomerVers(pince.depart * (ecart / pince.ecart), x, y);
        zoomX += x - pince.x;   // et la photo suit les deux doigts
        zoomY += y - pince.y;
        pince.x = x;
        pince.y = y;
        appliquerZoom();
        ev.preventDefault();
        return;
      }
      if (!glisse || ev.touches.length !== 1) return;
      const doigt = ev.touches[0];
      const dx = doigt.clientX - glisse.x;
      const dy = doigt.clientY - glisse.y;
      /* Depuis le point de départ, sinon un déplacement lent — quelques
         pixels par image — passerait pour une tape. */
      if (Math.abs(doigt.clientX - glisse.xDepart) > 6 ||
          Math.abs(doigt.clientY - glisse.yDepart) > 6) glisse.bouge = true;
      if (!estAgrandie()) return;  // à 1×, le doigt fait défiler la galerie
      zoomX += dx;
      zoomY += dy;
      glisse.x = doigt.clientX;
      glisse.y = doigt.clientY;
      appliquerZoom();
      ev.preventDefault();
    }, { passive: false });

    piste.addEventListener("touchend", (ev) => {
      dernierToucher = Date.now();
      const tape = !pince && glisse && !glisse.bouge && ev.touches.length === 0;
      const doigt = ev.changedTouches && ev.changedTouches[0];
      if (ev.touches.length === 0) {
        pince = null;
        glisse = null;
        piste.classList.remove("pincee");
      }
      if (!tape || !doigt) return;
      const maintenant = Date.now();
      if (maintenant - derniereTape < 320) {
        derniereTape = 0;
        basculerZoom(doigt.clientX, doigt.clientY);
      } else {
        derniereTape = maintenant;
      }
    }, { passive: false });

    /* Un appel, un volet de notifications : le système reprend les
       doigts sans jamais envoyer de touchend. Sans ceci, le geste
       resterait ouvert et le prochain déplacement partirait de
       travers. */
    piste.addEventListener("touchcancel", () => {
      pince = null;
      glisse = null;
      derniereTape = 0;
      piste.classList.remove("pincee");
    }, { passive: true });

    /* À la souris. */
    piste.addEventListener("wheel", (ev) => {
      if ($("#visionneuse").hidden) return;
      ev.preventDefault();
      zoomerVers(zoom * (ev.deltaY < 0 ? 1.18 : 1 / 1.18), ev.clientX, ev.clientY);
    }, { passive: false });
    /* Une double-tape sur l'écran fabrique aussi un dblclick : sans ce
       garde-fou, le doigt agrandirait puis réduirait aussitôt, et la
       double-tape ne ferait rien du tout. */
    piste.addEventListener("dblclick", (ev) => {
      if (Date.now() - dernierToucher < 700) return;
      basculerZoom(ev.clientX, ev.clientY);
    });

    const bouton = $("#visionneuse-zoom");
    if (bouton) bouton.onclick = () => basculerZoom();
  }

  /** Met à jour points, compteur et flèches selon la photo affichée. */
  function majVisionneuse() {
    const piste = $("#visionneuse-piste");
    if (!piste || !piste.clientWidth) return;
    const total = photosVisionneuse.length;
    const avant = indexVisionneuse;
    indexVisionneuse = Math.min(Math.round(piste.scrollLeft / piste.clientWidth), Math.max(0, total - 1));
    /* Photo suivante : on repart de la vue d'ensemble. */
    if (indexVisionneuse !== avant) reinitialiserZoom();

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
    reinitialiserZoom();
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
      /* En approvisionnement, le badge porte le décompte : c'est
         l'information utile, pas l'état seul. */
      const nom = etat === "approvisionnement"
        ? "Arrive " + Utils.delaiEnMots(Store.joursAppro(p))
        : Store.STATUTS[etat].nom;
      html += '<span class="badge badge-' + etat + '">' + e(nom) + "</span>";
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
            (p.surCommande
              ? "Sans stock"
              : Store.enAppro(p)
                ? "Arrive " + e(Utils.delaiEnMots(Store.joursAppro(p)))
                : "Stock " + p.stock) + "</span>" +
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
    $, $$, entete, icone, marque, motSymbole, logoAdmin, toast,
    ouvrirFeuille, fermerFeuille, feuilleSansRappel, confirmer, demanderTexte,
    ouvrirVisionneuse, fermerVisionneuse,
    vignetteProduit, badgesProduit, ligneProduit, vide,
    champTexte, champMontant, champZone, interrupteur,
  };
})();
