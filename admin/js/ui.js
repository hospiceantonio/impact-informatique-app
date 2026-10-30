/* =========================================================
   UI — briques d'interface : entête, feuille modale, toasts,
   visionneuse, lignes produit, champs de formulaire.
   ========================================================= */
const UI = (() => {

  const $ = (sel, base) => (base || document).querySelector(sel);
  const $$ = (sel, base) => Array.from((base || document).querySelectorAll(sel));
  const e = Utils.echapper;

  /* ---------- Le logo : le B au chariot, puis le nom ---------- */

  /**
   * LE NOM BIZZOO, écrit et non dessiné : « Bizz » en bleu, « oo » en
   * orange. En texte plutôt qu'en image, il reste net à toutes les
   * tailles, ne pèse rien, et s'affiche sans réseau comme sans fichier.
   * Plus de points dessous depuis la 3.56.1 : le B au chariot qui le
   * précède porte ses deux roues orange.
   */
  function motSymbole(classe) {
    return (
      '<span class="logo-mot' + (classe ? " " + classe : "") + '" aria-label="BIZZOO">' +
        '<span class="logo-bizz">Bizz</span><span class="logo-oo">oo</span>' +
      "</span>"
    );
  }

  /**
   * La marque : l'icône même de l'application, celle qu'on voit sur
   * l'écran d'accueil du téléphone — ici avec sa pastille « réglages ».
   * Le fichier est déjà gardé hors connexion par le service worker.
   */
  function marque(taille = 40) {
    return (
      '<img class="marque" src="icons/icon-192.png" alt="" aria-hidden="true"' +
      ' width="' + taille + '" height="' + taille + '">'
    );
  }

  /**
   * LE LOGO DE BIZZOO, puis « Espace admin » sous le nom. La tuile est
   * « icons/logo-bizzoo.png » : le B au chariot SANS la pastille
   * « réglages » de l'icône de l'admin — c'est la marque de l'enseigne,
   * la même que dans l'application des clients et sur le site.
   */
  function logoAdmin() {
    return (
      '<span class="logo">' +
        '<img class="logo-tuile" src="icons/logo-bizzoo.png" alt="" aria-hidden="true"' +
        ' width="40" height="40">' +
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
        '<div class="topbar-actions">' + (actions || "") + boutonCloche() + "</div>" +
      "</div>";
  }

  /* ---------- La cloche des notifications ----------

     ELLE PARAÎT DÈS QU'ON EST CONNECTÉ, quel que soit le rang — le
     livreur en a autant besoin que la boutique, et plus encore : c'est
     lui qui attend une course, et lui qui n'a aucune raison de rouvrir
     un écran toutes les cinq minutes.

     LE NOMBRE EST DANS L'ÉTIQUETTE, pas seulement dans la pastille :
     un lecteur d'écran annonce « Notifications, 3 non lues », là où
     une pastille seule ne dit rien. */
  function boutonCloche() {
    if (typeof Notifs === "undefined" || !Supabase.sessionPresente()) return "";
    if (/^#\/notifications/.test(location.hash)) return "";
    const combien = Notifs.compte();
    return (
      '<a class="btn-ic btn-cloche" href="#/notifications" aria-label="' +
        (combien ? "Notifications, " + combien + " non lue" + (combien > 1 ? "s" : "")
                 : "Notifications") + '">' + icone("cloche") +
        (combien ? '<span class="cloche-pastille">' +
          (combien > 99 ? "99+" : combien) + "</span>" : "") +
      "</a>"
    );
  }

  /** Rafraîchit la pastille sans redessiner tout l'écran. */
  function majCloche() {
    const zone = $("#topbar .topbar-actions");
    if (!zone) return;
    const ancien = $(".btn-cloche", zone);
    const neuf = boutonCloche();
    if (ancien) ancien.outerHTML = neuf;
    else if (neuf) zone.insertAdjacentHTML("beforeend", neuf);
  }

  document.addEventListener("notifs:maj", majCloche);

  /* UNE IMAGE « DE SECOURS » QUI NE VIENT PAS S'EFFACE : ce qu'elle
     recouvrait — l'icône d'une catégorie — reparaît, au lieu du
     carré d'image cassée. L'erreur d'une image ne remonte pas jusqu'au
     document ; on l'attrape donc à la descente (« true »), une fois
     pour toutes les pages, sans attribut « onerror » dans le HTML. */
  document.addEventListener("error", (ev) => {
    const cible = ev.target;
    if (cible && cible.tagName === "IMG" && cible.hasAttribute("data-secours")) cible.remove();
  }, true);

  function icone(nom, classe) {
    return '<svg class="ic' + (classe ? " " + classe : "") + '" viewBox="0 0 24 24" aria-hidden="true"><use href="#i-' + nom + '"/></svg>';
  }

  /* L'ICÔNE D'UNE CATÉGORIE (3.56), la même que chez le client : l'une
     de celles des trois planches choisies par l'enseigne, reprises telles
     quelles (« img/pictos/<nom>.png »). Une icône qui n'en fait pas
     partie — choisie avant la 3.56 — garde son dessin d'un trait : jamais
     une pastille vide. */
  const PICTOS = [
    "informatique", "electromenager", "energie", "securite", "telephones",
    "bebe-enfant", "livres-education", "formation", "maison-deco", "jardinage",
    "bricolage", "immobilier", "auto-moto", "transport", "mode", "bijoux",
    "beaute", "sante", "alimentation", "restauration", "agriculture",
    "tracteur", "animaux", "sport-loisirs", "musique", "artisanat", "cadeau",
    "evenementiel", "bureau", "materiel-pro", "imprimante", "grossistes",
    "cartons", "services"];

  function picto(nom) {
    const cle = String(nom || "categories");
    if (PICTOS.includes(cle)) {
      return '<img class="picto" src="img/pictos/' + cle + '.png" alt="" draggable="false">';
    }
    /* Ni icône de l'image ni dessin d'un trait connu : les rayons. */
    return icone(document.getElementById("i-" + cle) ? e(cle) : "categories");
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
    /* MASQUÉ (3.59.0) : en tête, c'est ce qui compte le plus — le client
       ne le voit pas. */
    if (p.masque) html += '<span class="badge badge-masque">' + icone("fermer", "ic-sm") + "Masqué</span>";
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

  function champZone({ id, label, valeur, obligatoire, aide, lignes, placeholder, max }) {
    return (
      '<div class="champ">' +
        '<label for="' + id + '">' + e(label) + (obligatoire ? ' <span class="obligatoire">*</span>' : "") + "</label>" +
        '<textarea id="' + id + '" rows="' + (lignes || 4) + '"' + (max ? ' maxlength="' + max + '"' : "") +
          (placeholder ? ' placeholder="' + e(placeholder) + '"' : "") + ">" +
          e(valeur || "") + "</textarea>" +
        (aide ? '<div class="aide">' + e(aide) + "</div>" : "") +
      "</div>"
    );
  }

  /* ---------- Les jours et heures d'ouverture (3.59.0) ----------
     Sept lignes : le jour (ouvert ou non), l'heure d'ouverture, l'heure
     de fermeture. Fermée, une boutique ne montre pas ses produits aux
     clients, et la base refuse leurs commandes. */
  const JOURS_HORAIRES = [["lun", "Lundi"], ["mar", "Mardi"], ["mer", "Mercredi"],
    ["jeu", "Jeudi"], ["ven", "Vendredi"], ["sam", "Samedi"], ["dim", "Dimanche"]];
  const HORAIRES_DEFAUT = { lun: { de: "08:00", a: "19:00" }, mar: { de: "08:00", a: "19:00" },
    mer: { de: "08:00", a: "19:00" }, jeu: { de: "08:00", a: "19:00" },
    ven: { de: "08:00", a: "19:00" }, sam: { de: "08:00", a: "19:00" }, dim: null };

  function champsHoraires(prefixe, ouvertures, aide) {
    const o = ouvertures || HORAIRES_DEFAUT;
    return (
      '<div class="champ champ-horaires" id="' + prefixe + '-ouvertures">' +
        '<label>Jours et heures d\'ouverture <span class="obligatoire">*</span></label>' +
        (aide ? '<div class="aide" style="margin:0 0 8px">' + aide + "</div>" : "") +
        JOURS_HORAIRES.map(([cle, nom]) => {
          const p = o[cle];
          return (
            '<div class="horaire-ligne" data-jour="' + cle + '">' +
              '<label class="horaire-jour"><input type="checkbox" data-ouvert' + (p ? " checked" : "") + "> " +
                nom + "</label>" +
              '<input type="time" data-de value="' + escapeAttr((p && p.de) || "08:00") + '" aria-label="' + nom + ', ouverture">' +
              '<span class="horaire-tiret">–</span>' +
              '<input type="time" data-a value="' + escapeAttr((p && p.a) || "19:00") + '" aria-label="' + nom + ', fermeture">' +
            "</div>"
          );
        }).join("") +
      "</div>"
    );
  }
  function escapeAttr(t) { return String(t).replace(/[&"<>]/g, (c) => ({ "&": "&amp;", '"': "&quot;", "<": "&lt;", ">": "&gt;" }[c])); }

  /** Lit l'éditeur ; refuse en le disant ce que la base refuserait. */
  function lireHoraires(racine, prefixe) {
    const zone = $("#" + prefixe + "-ouvertures", racine);
    if (!zone) return undefined;
    const sortie = {};
    let ouverts = 0;
    for (const [cle, nom] of JOURS_HORAIRES) {
      const ligne = zone.querySelector('[data-jour="' + cle + '"]');
      if (!ligne.querySelector("[data-ouvert]").checked) { sortie[cle] = null; continue; }
      const de = ligne.querySelector("[data-de]").value;
      const a = ligne.querySelector("[data-a]").value;
      if (!/^\d\d:\d\d/.test(de) || !/^\d\d:\d\d/.test(a)) {
        throw new Error(nom + " : indiquez l'heure d'ouverture et de fermeture.");
      }
      if (de.slice(0, 5) >= a.slice(0, 5)) {
        throw new Error(nom + " : la fermeture doit venir après l'ouverture.");
      }
      sortie[cle] = { de: de.slice(0, 5), a: a.slice(0, 5) };
      ouverts++;
    }
    if (!ouverts) throw new Error("Indiquez au moins un jour d'ouverture.");
    return sortie;
  }

  /* ---------- Conditions de paiement et frais d'une boutique (3.59.0) ----------
     Tout à la commande, ou un acompte (1 à 99 %) à la commande et le
     reste à la livraison ; et ses frais de livraison. */
  function champsConditions(prefixe, b, defauts) {
    const d = defauts || {};
    const mode = (b && b.modePaiement) || d.modePaiement || "acompte";
    const taux = (b && b.tauxAcompte != null ? b.tauxAcompte : d.tauxAcompte) || 10;
    const frais = b && b.fraisLivraison != null ? b.fraisLivraison : (d.fraisLivraison != null ? d.fraisLivraison : 1000);
    return (
      '<div class="champ champ-conditions" id="' + prefixe + '-conditions">' +
        '<label for="' + prefixe + '-mode">Paiement à la commande <span class="obligatoire">*</span></label>' +
        '<select id="' + prefixe + '-mode">' +
          '<option value="total"' + (mode === "total" ? " selected" : "") + ">Tout à la commande</option>" +
          '<option value="acompte"' + (mode === "acompte" ? " selected" : "") +
            ">Un acompte à la commande, le reste à la livraison</option>" +
        "</select>" +
        '<div class="champ-montant" id="' + prefixe + '-bloc-taux" style="margin-top:8px"' +
          (mode === "acompte" ? "" : " hidden") + ">" +
          '<input id="' + prefixe + '-taux" inputmode="numeric" autocomplete="off" value="' + escapeAttr(taux) + '">' +
          '<span class="devise">%</span>' +
        "</div>" +
        '<div class="aide">Le client paie ce pourcentage de la part de la boutique (articles et ' +
          "livraison) en commandant ; son livreur encaisse le reste à la livraison.</div>" +
      "</div>" +
      '<div class="note-ok" id="' + prefixe + '-frais-km" hidden style="margin:0 0 12px">' + icone("check", "ic-sm") +
        " Livraison au kilomètre en service : BIZZOO calcule les frais selon la distance. " +
        "Ceux de la boutique ne s'appliquent plus.</div>" +
      '<div class="champ" id="' + prefixe + '-bloc-frais">' +
        '<label for="' + prefixe + '-frais">Frais de livraison <span class="obligatoire">*</span></label>' +
        '<div class="champ-montant">' +
          '<input id="' + prefixe + '-frais" inputmode="numeric" autocomplete="off" value="' + escapeAttr(frais) + '">' +
          '<span class="devise">FCFA</span>' +
        "</div>" +
        '<div class="aide">Ajoutés à chaque commande qui contient ses produits. Les codes promo ne ' +
          "les touchent pas. 0 : livraison offerte.</div>" +
      "</div>"
    );
  }
  /** Branche le menu : le taux ne paraît que pour l'acompte. */
  function brancherConditions(racine, prefixe) {
    const menu = $("#" + prefixe + "-mode", racine);
    const bloc = $("#" + prefixe + "-bloc-taux", racine);
    if (menu && bloc) menu.onchange = () => { bloc.hidden = menu.value !== "acompte"; };
    /* (3.64.0) Au kilomètre, les frais de la boutique ne comptent plus :
       on ne les fait pas saisir pour rien. */
    if (typeof Store !== "undefined" && Store.lirePaiement) {
      Store.lirePaiement().then((p) => {
        const l = p && p.livraison;
        if (!l || l.latitude === null || l.longitude === null) return;
        const frais = $("#" + prefixe + "-bloc-frais", racine);
        const note = $("#" + prefixe + "-frais-km", racine);
        if (frais) frais.hidden = true;
        if (note) note.hidden = false;
      }).catch(() => { /* on laisse le champ */ });
    }
  }
  function lireConditions(racine, prefixe) {
    const menu = $("#" + prefixe + "-mode", racine);
    if (!menu) return {};
    const modePaiement = menu.value === "total" ? "total" : "acompte";
    const taux = Math.round(Number(String($("#" + prefixe + "-taux", racine).value).replace(/\s|%/g, "")));
    if (modePaiement === "acompte" && !(taux >= 1 && taux <= 99)) {
      throw new Error("L'acompte se donne en pour cent, de 1 à 99 %.");
    }
    const brut = String($("#" + prefixe + "-frais", racine).value).replace(/\s|fcfa/gi, "");
    const frais = Math.round(Number(brut));
    if (brut === "" || !(frais >= 0 && frais <= 100000)) {
      throw new Error("Les frais de livraison : un montant de 0 à 100 000 FCFA.");
    }
    return { modePaiement, tauxAcompte: modePaiement === "acompte" ? taux : undefined, fraisLivraison: frais };
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

  /* ---------- Les liens à partager ----------
     L'ADRESSE OFFICIELLE de la boutique en ligne, quel que soit
     l'endroit d'où l'on copie : un lien partagé sur WhatsApp ou sur une
     page Facebook ouvre directement la boutique, son catalogue ou la
     fiche du produit. */
  const SITE_BOUTIQUE = "https://www.bizzoomarket.com/client/#/";
  function lienPartage(type, id) {
    const cle = encodeURIComponent(String(id || ""));
    if (type === "produit") return SITE_BOUTIQUE + "produit/" + cle;
    if (type === "catalogue") return SITE_BOUTIQUE + "boutique/" + cle + "/produits";
    return SITE_BOUTIQUE + "boutique/" + cle;
  }

  /** Une carte de liens : chacun avec « Copier » et « WhatsApp ». */
  function liensPartage(liens) {
    return '<div class="carte liens-partage">' +
      '<div class="carte-titre">' + icone("lien", "ic-sm") + " Liens à partager</div>" +
      liens.map((l) =>
        '<div class="lien-partage">' +
          "<small>" + Utils.echapper(l.nom) + "</small>" +
          '<input type="text" readonly value="' + Utils.echapper(l.lien) + '">' +
          '<div class="btn-rangee">' +
            '<button type="button" class="btn btn-clair" data-copier="' + Utils.echapper(l.lien) + '">' +
              "Copier</button>" +
            '<a class="btn btn-clair" target="_blank" rel="noopener" href="' +
              Utils.echapper("https://wa.me/?text=" + encodeURIComponent(l.lien)) + '">' +
              icone("whatsapp") + "WhatsApp</a>" +
          "</div>" +
        "</div>").join("") +
    "</div>";
  }

  /* Un seul écouteur pour tous les boutons « Copier » de l'application. */
  document.addEventListener("click", async (ev) => {
    const b = ev.target.closest && ev.target.closest("[data-copier]");
    if (!b) return;
    const lien = b.dataset.copier;
    try {
      await navigator.clipboard.writeText(lien);
    } catch (_) {
      const champ = b.closest(".lien-partage") && b.closest(".lien-partage").querySelector("input");
      if (champ) { champ.select(); try { document.execCommand("copy"); } catch (__) { /* sélectionné */ } }
    }
    toast("Lien copié", "ok");
  });

  /* ---------- Une porte dans une liste (3.62.0) ----------
     La rangée « tuile, nom, un mot dessous, chevron » : celle de « À
     propos de BIZZOO » chez le client, reprise ici pour les Réglages et
     « Vos données et vos droits ». Un lien si « href » est donné, un
     bouton sinon ; « attrs » porte un id ou un data-*. */
  function porte({ href, icone: nom, titre, sous, attrs, rond }) {
    const dedans =
      '<span class="' + (rond || "rond-bleu") + '">' + icone(nom) + "</span>" +
      "<span><strong>" + e(titre) + "</strong>" + (sous ? "<small>" + e(sous) + "</small>" : "") + "</span>" +
      icone("chevron", "ic-sm");
    return href
      ? '<a class="ligne-info" href="' + e(href) + '"' + (attrs || "") + ">" + dedans + "</a>"
      : '<button type="button" class="ligne-info"' + (attrs || "") + ">" + dedans + "</button>";
  }

  /* (3.72.0) UNE LISTE QUI SE CHERCHE. Un menu de boutiques, de produits,
     de vendeurs : rangé par ordre alphabétique, et un champ au-dessus
     pour taper quelques lettres plutôt que de faire défiler. Les choix
     fixes (« Choisir… », « BIZZOO — toutes les boutiques », « Aucun »)
     restent en tête. Une liste courte n'a pas besoin du champ. */
  function cherchable(select, o = {}) {
    if (!select || select.dataset.cherchable === "pret") return select;
    select.dataset.cherchable = "pret";
    const fixe = (opt) => opt.value === "" || opt.value.startsWith("__") || opt.dataset.fixe === "1";
    const plier = (t) => Utils.sansAccent(t).replace(/\s+/g, " ").trim();
    const valeur = select.value;
    const tete = [...select.options].filter(fixe);
    const reste = [...select.options].filter((x) => !fixe(x))
      .sort((a, b) => a.textContent.localeCompare(b.textContent, "fr", { sensitivity: "base", numeric: true }));
    const toutes = tete.concat(reste);
    select.replaceChildren(...toutes);
    select.value = valeur;
    if (reste.length < (o.seuil == null ? 6 : o.seuil)) return select;
    const champ = document.createElement("input");
    champ.type = "search";
    champ.className = "recherche-liste";
    champ.autocomplete = "off";
    champ.placeholder = o.placeholder || "Rechercher…";
    champ.setAttribute("aria-label", o.placeholder || "Rechercher dans la liste");
    if (select.id) champ.id = select.id + "-chercher";
    const note = document.createElement("div");
    note.className = "aide recherche-liste-vide";
    note.hidden = true;
    note.textContent = "Aucun résultat : essayez un autre mot.";
    select.insertAdjacentElement("beforebegin", champ);
    select.insertAdjacentElement("afterend", note);
    champ.addEventListener("input", () => {
      const q = plier(champ.value);
      const avant = select.value;
      const trouvees = q ? reste.filter((x) => plier(x.textContent).includes(q)) : reste;
      note.hidden = !(q && !trouvees.length);
      if (q && !trouvees.length) return;
      select.replaceChildren(...(q ? trouvees : toutes));
      /* Le choix d'avant reste s'il est encore là ; sinon le premier trouvé,
         et la page en est prévenue comme d'un choix à la main. Une page qui
         se redessine à chaque choix (« auto: false ») attend qu'on choisisse. */
      if ([...select.options].some((x) => x.value === avant)) select.value = avant;
      else if (o.auto === false) {
        const invite = document.createElement("option");
        invite.value = avant;
        invite.disabled = true;
        invite.textContent = trouvees.length + " résultat" + (trouvees.length > 1 ? "s" : "") + " — choisissez";
        select.prepend(invite);
        select.selectedIndex = 0;
      } else if (trouvees.length) {
        select.value = trouvees[0].value;
        select.dispatchEvent(new Event("change", { bubbles: true }));
      }
    });
    return select;
  }

  return {
    cherchable,
    lienPartage, liensPartage, porte,
    $, $$, entete, icone, picto, marque, motSymbole, logoAdmin, toast, majCloche,
    ouvrirFeuille, fermerFeuille, feuilleSansRappel, confirmer, demanderTexte,
    champsHoraires, lireHoraires, champsConditions, brancherConditions, lireConditions,
    ouvrirVisionneuse, fermerVisionneuse,
    vignetteProduit, badgesProduit, ligneProduit, vide,
    champTexte, champMontant, champZone, interrupteur,
  };
})();
