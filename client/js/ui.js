/* =========================================================
   UI — briques d'interface : entête avec logo, cartes
   produit, prix, badges, toasts, visionneuse.
   ========================================================= */
const UI = (() => {

  const $ = (sel, base) => (base || document).querySelector(sel);
  const $$ = (sel, base) => Array.from((base || document).querySelectorAll(sel));
  const e = Utils.echapper;

  /* ---------- Logo (reprend la charte du logo officiel) ---------- */

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

  /** Logo complet : le sac + « BIZZOO », pour l'accueil. */
  /**
   * Le mot-symbole, et sous lui le slogan de l'enseigne quand on en
   * passe un. Deux lignes calées à gauche : le slogan appartient au
   * logo, il ne flotte pas à côté.
   */
  function logo(sous) {
    return (
      '<span class="logo' + (sous ? " logo-avec-sous" : "") + '">' +
        '<span class="logo-textes">' +
          motSymbole() +
          (sous ? '<span class="logo-sous">' + e(sous) + "</span>" : "") +
        "</span>" +
      "</span>"
    );
  }

  /* ---------- Barre supérieure ---------- */

  /* Le panier, toujours à portée. Un panier qu'on ne retrouve pas est
     un panier abandonné : le bouton est donc dans la barre du haut, sur
     tous les écrans, avec le nombre d'articles dessus. Il se retire des
     écrans du panier lui-même — y renvoyer depuis là ne mènerait nulle
     part. */

  /* Le compte vit à côté du panier, dans la barre du haut : une icône qui
     mène à « Mon compte » quand on est connecté, à la connexion sinon. Pas
     d'onglet en bas — la barre est déjà pleine, et le compte n'est pas un
     rayon du magasin. */
  function boutonCompte() {
    if (/^#\/(connexion|inscription|mot-de-passe|compte)/.test(location.hash)) return "";
    const dedans = typeof Compte !== "undefined" && Compte.connecte();
    return '<a class="btn-ic" href="#/' + (dedans ? "compte" : "connexion") +
      '" aria-label="' + (dedans ? "Mon compte" : "Se connecter") + '">' +
      icone("compte") + "</a>";
  }

  function boutonPanier() {
    if (/^#\/(panier|commande|mes-commandes)/.test(location.hash)) return "";
    const combien = Panier.nombre();
    return (
      '<a class="btn-ic btn-panier" href="#/panier" aria-label="' +
        (combien ? "Mon panier, " + combien + " article" + (combien > 1 ? "s" : "") : "Mon panier") +
        '">' + icone("sacoche") +
        (combien ? '<span class="panier-pastille">' + (combien > 99 ? "99+" : combien) + "</span>" : "") +
      "</a>"
    );
  }

  /** Rafraîchit la pastille sans redessiner tout l'écran. */
  function majPanier() {
    const zone = $("#topbar .topbar-actions");
    if (!zone) return;
    const ancien = $(".btn-panier", zone);
    const neuf = boutonPanier();
    if (ancien) ancien.outerHTML = neuf;
    else if (neuf) zone.insertAdjacentHTML("beforeend", neuf);
  }

  document.addEventListener("panier:maj", majPanier);

  /* ---------- La cloche des notifications ----------

     ELLE NE PARAÎT QUE POUR QUI A UN COMPTE. Sans compte, il n'y a
     personne à prévenir : la base n'a pas de destinataire, et une
     cloche muette sur tous les écrans ne ferait qu'encombrer une barre
     déjà pleine.

     LE NOMBRE EST DANS L'ÉTIQUETTE, pas seulement dans la pastille :
     un lecteur d'écran annonce « Notifications, 3 non lues », là où
     une pastille seule ne dit rien. */
  function boutonCloche() {
    if (typeof Compte === "undefined" || !Compte.connecte()) return "";
    if (/^#\/notifications/.test(location.hash)) return "";
    const combien = typeof Notifs !== "undefined" ? Notifs.compte() : 0;
    return (
      '<a class="btn-ic btn-cloche" href="#/notifications" aria-label="' +
        (combien ? "Notifications, " + combien + " non lue" + (combien > 1 ? "s" : "")
                 : "Notifications") + '">' + icone("cloche") +
        (combien ? '<span class="panier-pastille">' +
          (combien > 99 ? "99+" : combien) + "</span>" : "") +
      "</a>"
    );
  }

  function majCloche() {
    const zone = $("#topbar .topbar-actions");
    if (!zone) return;
    const ancien = $(".btn-cloche", zone);
    const neuf = boutonCloche();
    if (ancien) ancien.outerHTML = neuf;
    else if (neuf) {
      /* La cloche se pose AVANT le panier : le panier reste le dernier
         geste de la barre, celui qu'on cherche du pouce. */
      const panier = $(".btn-panier", zone);
      if (panier) panier.insertAdjacentHTML("beforebegin", neuf);
      else zone.insertAdjacentHTML("beforeend", neuf);
    }
  }

  document.addEventListener("notifs:maj", majCloche);

  /**
   * La barre du haut. `vignette` pose une pastille à gauche du titre :
   * c'est par elle qu'une boutique met son logo à côté de son nom, pour
   * qu'on sache d'un coup d'œil chez qui l'on est.
   */
  function entete({ titre, sous, retour, accueil, actions, vignette }) {
    const zone = $("#topbar");
    const retourHtml = retour
      ? '<button type="button" class="btn-ic" data-action="retour" aria-label="Retour">' +
        icone("retour") + "</button>"
      : "";
    actions = (actions || "") + boutonCompte() + boutonCloche() + boutonPanier();
    const actionsHtml = '<div class="topbar-actions">' + (actions || "") + "</div>";

    /* ---------- L'en-tête d'une boutique ----------

       SUR SA PROPRE LIGNE, et c'est le seul moyen que son nom tienne.
       Sur un téléphone de 390 px, une ligne unique porte le retour, le
       logo, quatre boutons et leurs écarts : il restait cent vingt
       pixels pour le nom, soit « IMP… », et le slogan se pliait sur
       quatre lignes en dessous. Une enseigne réduite à trois lettres
       ne dit plus chez qui l'on est.

       Les boutons montent donc sur la ligne du retour, et l'enseigne
       prend toute la largeur : logo à gauche, nom en entier, slogan
       dessous. Trois lignes courtes, et l'en-tête finit PLUS BAS que
       celui qu'il remplace. */
    if (vignette && !accueil) {
      zone.innerHTML =
        '<div class="topbar-ligne topbar-ligne-outils">' +
          retourHtml +
          '<span class="topbar-vide"></span>' +
          actionsHtml +
        "</div>" +
        '<div class="topbar-enseigne">' +
          vignette +
          '<div class="topbar-enseigne-mots">' +
            "<h1>" + e(titre || "") + "</h1>" +
            (sous ? '<div class="sous">' + e(sous) + "</div>" : "") +
          "</div>" +
        "</div>";
      mesurerEntete();
      return;
    }

    /* ---------- Le slogan de BIZZOO, sous le logo ----------

       DEUX ENDROITS POSSIBLES, JAMAIS LES DEUX. Le bandeau orange
       porte le slogan de la boutique en mode mono-boutique : là, la
       maison ET la boutique sont la même, et l'écrire deux fois serait
       du bégaiement. Sur l'accueil de l'enseigne le bandeau se tait —
       « boutique() » vide son slogan exprès, le slogan d'une boutique
       tromperait sur les autres —, et c'est alors sous le logo que
       BIZZOO parle en son nom. Le second n'apparaît donc que lorsque
       le premier se tait. */
    const sloganBandeau = accueil ? Catalogue.boutique().slogan : "";
    const sloganLogo = accueil && !sloganBandeau ? Catalogue.enseigne().slogan : "";

    zone.innerHTML =
      '<div class="topbar-ligne">' +
        retourHtml +
        (accueil
          ? '<div class="topbar-logo">' + logo(sloganLogo) + "</div>"
          : "<div style='flex:1;min-width:0'>" +
              "<h1>" + e(titre || "") + "</h1>" +
              (sous ? '<div class="sous">' + e(sous) + "</div>" : "") +
            "</div>") +
        actionsHtml +
      "</div>" +
      (sloganBandeau
        ? '<div class="topbar-slogan">' + e(sloganBandeau) + "</div>"
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

    const telecharger = $("#visionneuse-telecharger");
    if (telecharger) telecharger.hidden = !(photosVisionneuse[indexVisionneuse] || {}).nom;
  }

  function fermerVisionneuse() {
    const visionneuse = $("#visionneuse");
    if (!visionneuse || visionneuse.hidden) return;
    visionneuse.hidden = true;
    reinitialiserZoom();
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
    /* La devise du produit, pas celle de l'écran : un résultat de
       recherche peut venir d'une boutique qui compte autrement. */
    const devise = Catalogue.deviseDe(p);
    const remise = Utils.remisePourcent(p.ancienPrix, p.prix);
    /* Un revendeur voit ce qu'il gagne : son prix, et celui de la
       vitrine barré à côté. Ce n'est pas une promotion — c'est son
       tarif, et il ne s'arrêtera pas dimanche soir. */
    const vitrine = p.prixRevendeur && p.prixPublic > p.prix ? p.prixPublic : null;
    return (
      '<span class="prix' + (o.grand ? " prix-grand" : "") + '">' +
        '<span class="prix-actuel">' + e(Utils.fmtMontant(p.prix, devise)) + "</span>" +
        (remise !== null
          ? ' <s class="prix-ancien">' + e(Utils.fmtMontant(p.ancienPrix, devise)) + "</s>"
          : "") +
        (vitrine !== null
          ? ' <s class="prix-ancien">' + e(Utils.fmtMontant(vitrine, devise)) + "</s>"
          : "") +
      "</span>"
    );
  }

  /* ---------- Les étoiles ----------

     Cinq étoiles, pleines jusqu'à la note. On ARRONDIT au demi le plus
     proche pour le dessin, mais le chiffre écrit à côté reste le vrai :
     une note de 4,2 ne doit pas se lire « 4 » — c'est le chiffre qu'on
     compare d'un produit à l'autre, pas le dessin. */

  function etoiles(note, options) {
    const o = options || {};
    const n = Number(note);
    if (!isFinite(n) || n <= 0) return "";
    const pleines = Math.round(n);
    let dessin = "";
    for (let i = 1; i <= 5; i++) {
      dessin += '<span class="et' + (i <= pleines ? " et-pleine" : "") + '">' +
        icone("etoile", "ic-sm") + "</span>";
    }
    return (
      '<span class="etoiles' + (o.grand ? " etoiles-grand" : "") + '">' +
        dessin +
        (o.chiffre === false ? "" :
          '<span class="etoiles-note">' + e(n.toFixed(1).replace(".", ",")) + "</span>") +
        (o.combien
          ? '<span class="etoiles-combien">(' + o.combien + ")</span>"
          : "") +
      "</span>"
    );
  }

  /** La note d'un produit ou d'une boutique, ou rien du tout. */
  function noteHtml(cible, options) {
    if (!cible || !cible.nbAvis) return "";
    return etoiles(cible.note, Object.assign({ combien: cible.nbAvis }, options || {}));
  }

  function badgesProduit(p) {
    const remise = Utils.remisePourcent(p.ancienPrix, p.prix);
    let html = "";
    if (p.prixRevendeur) {
      html += '<span class="badge badge-revendeur">' + icone("magasin", "ic-sm") +
        "Prix revendeur</span>";
    }
    if (Catalogue.enVenteFlash(p)) {
      html += '<span class="badge badge-flash">' + icone("energie", "ic-sm") + "Flash</span>";
    }
    if (remise !== null) html += '<span class="badge badge-promo">-' + remise + " %</span>";
    const etat = Catalogue.statut(p);
    /* Un produit qui arrive dit quand : c'est ce que le client veut savoir. */
    const nom = etat === "approvisionnement"
      ? "Arrive " + Utils.delaiEnMots(Catalogue.joursAppro(p))
      : Catalogue.STATUTS[etat].nom;
    html += '<span class="badge ' + Catalogue.STATUTS[etat].classe + '">' +
      Utils.echapper(nom) + "</span>";
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
  /* ---------- Le cœur ----------

     UN BOUTON POSÉ SUR UN LIEN. La carte d'un produit est un lien vers
     sa fiche ; le cœur vit dedans. Sans « preventDefault », le toucher
     ouvrirait la fiche et le favori se perdrait en route — d'où
     l'écouteur unique posé plus bas, qui intercepte le clic avant que
     le lien ne l'emporte.

     ET IL S'AFFICHE POUR TOUT LE MONDE, connecté ou non. Le cacher aux
     visiteurs reviendrait à ne jamais leur dire que cela existe ; le
     toucher sans compte les mène à la connexion, avec la raison. */
  function coeur(id, classe) {
    const garde = typeof Favoris !== "undefined" && Favoris.aProduit(id);
    return (
      '<button type="button" class="coeur' + (garde ? " coeur-plein" : "") +
        (classe ? " " + classe : "") + '" data-coeur="' + e(id) + '" ' +
        'aria-pressed="' + (garde ? "true" : "false") + '" ' +
        'aria-label="' + (garde ? "Retirer des favoris" : "Mettre de côté") + '">' +
        icone("coeur") +
      "</button>"
    );
  }

  /* Un seul écouteur pour toute l'application : les cartes se
     redessinent sans arrêt, et en rebrancher une par une laisserait
     tôt ou tard un cœur mort sur un écran. */
  document.addEventListener("click", async (ev) => {
    const b = ev.target.closest("[data-coeur]");
    if (!b) return;
    ev.preventDefault();
    ev.stopPropagation();
    if (!Compte.connecte()) {
      toast("Connectez-vous pour garder vos favoris");
      location.hash = "#/connexion";
      return;
    }
    b.disabled = true;
    try {
      const garde = await Favoris.basculerProduit(b.dataset.coeur);
      /* On repeint CE cœur tout de suite. Les autres — la même fiche
         ouverte ailleurs à l'écran — suivent par « surChangement ». */
      b.classList.toggle("coeur-plein", garde);
      b.setAttribute("aria-pressed", garde ? "true" : "false");
      b.setAttribute("aria-label", garde ? "Retirer des favoris" : "Mettre de côté");
      toast(garde ? "Mis de côté" : "Retiré des favoris");
    } catch (e2) {
      toast(e2.message || "Impossible pour l'instant.", "erreur");
    }
    b.disabled = false;
  });

  /* `options.boutique` : dire d'où vient le produit. La recherche
     traverse toute l'enseigne — sans ce nom, on ne saurait pas chez
     qui aller le chercher. */
  function carteProduit(p, options) {
    const o = options || {};
    const sc = Catalogue.sousCategorie(p.categorieId, p.sousCategorieId);
    const cat = Catalogue.categorie(p.categorieId);
    const bou = o.boutique ? Catalogue.boutiqueDuProduit(p) : null;
    return (
      '<a class="p-carte" href="#/produit/' + e(p.id) + '">' +
        '<span class="p-carte-img">' +
          imageProduit(p, "p-carte-photo") +
          '<span class="p-carte-badges">' + badgesProduit(p) + "</span>" +
          pastilleVideo(p) +
          coeur(p.id) +
        "</span>" +
        '<span class="p-carte-corps">' +
          (bou
            ? '<span class="p-carte-boutique">' + icone("magasin", "ic-sm") +
                "<span>" + e(bou.nom) + "</span></span>"
            : "") +
          '<span class="p-carte-nom">' + e(p.nom) + "</span>" +
          /* Le code, sous le nom et avant le prix : c'est par lui qu'un
             client désigne un article sans se tromper. */
          (p.code ? '<span class="p-carte-code">Code ' + e(p.code) + "</span>" : "") +
          /* Les étoiles sans le chiffre : sur une carte, le dessin suffit
             à comparer d'un coup d'œil, et le chiffre exact attend sur la
             fiche. Un produit sans avis n'affiche rien — mieux vaut rien
             que cinq étoiles vides, qui se lisent « mal noté ». */
          noteHtml(p, { chiffre: false }) +
          prixHtml(p) +
          '<span class="p-carte-cat">' + e(sc ? sc.nom : (cat ? cat.nom : "")) + "</span>" +
        "</span>" +
      "</a>"
    );
  }

  function grilleProduits(liste, options) {
    if (!liste.length) return "";
    return '<div class="p-grille">' + liste.map((p) => carteProduit(p, options)).join("") + "</div>";
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
        (p.code ? '<span class="p-carte-code">Code ' + e(p.code) + "</span>" : "") +
        noteHtml(p, { chiffre: false }) +
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
  /**
   * Une ligne de rayon, partagée par l'accueil de l'enseigne et
   * l'onglet Catégories : le nom du rayon, ce qui le décrit dessous —
   * la boutique qui le tient, ou à défaut ses sous-catégories — et
   * combien de produits s'y trouvent.
   *
   * Le lien mène droit au rayon : la boutique se règle toute seule en
   * chemin, par le mécanisme qui sert déjà aux liens partagés.
   */
  /**
   * Une ligne de la liste « Catégories » : pastille ronde, nom,
   * chevron. La pastille porte l'icône ET LA COULEUR que l'enseigne a
   * choisies — c'est elle qu'on reconnaît d'un écran à l'autre, et
   * c'est pour cela qu'elle vient de la base et non d'une devinette
   * sur le nom.
   */
  function ligneRayon(r) {
    const rayons = Catalogue.rayonsDeLaCategorie(r.categorie.id);
    const dessous = rayons.length
      ? rayons.map((x) => x.sousCategorie.nom).join(" · ")
      : "Bientôt des articles ici";
    return (
      '<a class="carte cat-ligne" href="#/categorie/' + e(r.categorie.id) + '">' +
        '<span class="cat-rond cat-rond-couleur" style="background:' +
          e(r.categorie.couleur || "#0B5CF5") + '">' +
          icone(r.categorie.icone || "categories") + "</span>" +
        '<span class="cat-ligne-corps">' +
          '<span class="cat-ligne-nom">' + e(r.categorie.nom) + "</span>" +
          '<span class="cat-ligne-sous">' + e(dessous) + "</span>" +
        "</span>" +
        (r.compte ? '<span class="cat-ligne-compte">' + r.compte + "</span>" : "") +
        icone("chevron", "ic-sm") +
      "</a>"
    );
  }

  /**
   * Le second étage : un rayon d'une catégorie. Pas de pastille ici —
   * elle est déjà en haut de l'écran, et la répéter quinze fois ne
   * dirait rien de plus.
   */
  function ligneSousRayon(r, categorieId) {
    return (
      '<a class="carte cat-ligne" href="#/categorie/' + e(categorieId) +
        "?sc=" + e(r.sousCategorie.id) + '">' +
        '<span class="cat-ligne-corps">' +
          '<span class="cat-ligne-nom">' + e(r.sousCategorie.nom) + "</span>" +
        "</span>" +
        '<span class="cat-ligne-compte">' + r.compte + "</span>" +
        icone("chevron", "ic-sm") +
      "</a>"
    );
  }

  /**
   * Le logo d'une boutique, en pastille : son image si elle en a une,
   * sinon son icône sur sa couleur — exactement ce que montre sa carte
   * sur l'accueil, pour qu'on la reconnaisse d'un écran à l'autre.
   */
  function vignetteBoutique(b) {
    if (!b) return "";
    return b.logo
      ? '<span class="topbar-vignette topbar-vignette-photo"><img src="' + e(b.logo) + '" alt=""></span>'
      : '<span class="topbar-vignette" style="background:' + e(b.couleur || "#0B5CF5") + '">' +
          icone(b.icone || "magasin") + "</span>";
  }

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
    $, $$, entete, icone, marque, motSymbole, logo, toast, bandeauBoutique, vignetteBoutique, ligneRayon,
    majPanier, majCloche,
    ouvrirVisionneuse, fermerVisionneuse, photoVisionneuse,
    coeur, iconeCategorie, ligneSousRayon, prixHtml, badgesProduit, etoiles, noteHtml, pastilleVideo, imageProduit,
    carteProduit, grilleProduits, carteProduitMini, rangeeProduits,
    titreSection, vide,
  };
})();
