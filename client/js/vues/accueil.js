/* =========================================================
   Accueil — slider, catégories, promotions et nouveautés.

   Deux sliders, selon l'écran :
   - l'accueil de l'enseigne fait défiler les photos et les
     vidéos de BIZZOO, et rien d'autre ;
   - l'écran d'une boutique fait défiler les siennes, puis
     ses produits mis en avant.
   ========================================================= */
const VueAccueil = (() => {

  const DELAI_SLIDER = 4500; // défilement automatique
  let minuterie = null;
  let derniereInteraction = 0;

  /* ---------- Slider ---------- */

  /**
   * Un écran composé à la main : une photo ou une vidéo. Il mène au
   * produit qu'il annonce, s'il en annonce un.
   *
   * Les vidéos partent sans le son (les téléphones refusent d'ouvrir
   * une vidéo sonore toute seule) et ne tournent pas en boucle : le
   * slider attend la fin pour passer à l'écran suivant.
   */
  function slideEcran(s, index) {
    const produit = s.produitId ? Catalogue.produit(s.produitId) : null;
    const cible = produit ? "#/produit/" + Utils.echapper(produit.id) : "";
    const balise = cible ? "a" : "div";
    const lien = cible ? ' href="' + cible + '"' : "";
    const etiquette = s.titre || (produit ? produit.nom : "");
    const media = s.video
      ? '<video class="slide-img" src="' + Utils.echapper(s.video) + '" muted playsinline ' +
          'preload="' + (index === 0 ? "auto" : "metadata") + '"></video>'
      : '<img class="slide-img" src="' + Utils.echapper(s.image) + '" alt="' +
          Utils.echapper(etiquette) + '"' + (index > 0 ? ' loading="lazy"' : "") + ">";
    return (
      "<" + balise + ' class="slide"' + lien +
        (etiquette ? ' aria-label="' + Utils.echapper(etiquette) + '"' : "") + ">" +
        media +
        (s.titre || produit
          ? '<span class="slide-voile"></span>' +
            '<span class="slide-infos">' +
              (s.titre ? '<span class="slide-nom">' + Utils.echapper(s.titre) + "</span>" : "") +
              (produit
                ? '<span class="slide-cta">Voir le produit ' + UI.icone("chevron", "ic-sm") + "</span>"
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

  function htmlSlider(ecransComposes, enAvant) {
    const total = ecransComposes.length + enAvant.length;
    if (!total) return "";
    const ecrans =
      ecransComposes.map((s, i) => slideEcran(s, i)).concat(
      enAvant.map((p, i) => slideProduit(p, ecransComposes.length + i)));
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

  /* ---------- Publicité de BIZZOO ----------
     Ce que l'enseigne met en avant sur son accueil : des affiches —
     photos ou vidéos — et des produits pris dans n'importe quelle
     boutique. Une rangée qui se pousse du doigt, et non un second
     slider : celui du haut a déjà cette place, et deux choses qui
     défilent toutes seules sur le même écran se disputent l'œil.

     RIEN NE DÉMARRE TOUT SEUL : la première vidéo attend un geste
     (`controls`). Mais une fois lancée, la rangée s'enchaîne — la
     vidéo finie, on avance jusqu'à la suivante et on la joue, comme un
     slider. La chaîne s'arrête au bout de la rangée, sans boucler, et
     jamais deux vidéos ne jouent ensemble : ce serait le double du
     débit et un téléphone qui chauffe. Voir « brancherPublicite ». */

  function cartePublicite(s, index) {
    const produit = s.produitId ? Catalogue.produit(s.produitId) : null;
    const boutique = produit ? Catalogue.boutiqueDuProduit(produit) : null;
    const image = s.image || (produit ? Catalogue.imagePrincipale(produit) : "");
    const etiquette = s.titre || (produit ? produit.nom : "");
    /* Une vidéo se manipule : elle ne peut pas être le corps d'un lien,
       sans quoi le premier geste ouvrirait la fiche produit. */
    const lien = produit && !s.video ? "#/produit/" + Utils.echapper(produit.id) : "";
    const balise = lien ? "a" : "div";
    const media = s.video
      ? '<video class="pub-media" src="' + Utils.echapper(s.video) + '" controls muted ' +
          'playsinline preload="metadata"></video>'
      : (image
        ? '<img class="pub-media" src="' + Utils.echapper(image) + '" alt="' +
            Utils.echapper(etiquette) + '"' + (index > 0 ? ' loading="lazy"' : "") + ">"
        : '<span class="pub-motif">' + UI.marque(64) + "</span>");
    return (
      "<" + balise + ' class="pub-carte"' + (lien ? ' href="' + lien + '"' : "") +
        (etiquette ? ' aria-label="' + Utils.echapper(etiquette) + '"' : "") + ">" +
        '<span class="pub-cadre">' + media + "</span>" +
        (etiquette || produit
          ? '<span class="pub-pied">' +
              (etiquette ? '<span class="pub-titre">' + Utils.echapper(etiquette) + "</span>" : "") +
              (produit
                ? '<span class="pub-prix">' +
                    Utils.echapper(Utils.fmtMontant(produit.prix, Catalogue.deviseDe(produit))) +
                  "</span>" +
                  (boutique
                    ? '<span class="pub-boutique">' + UI.icone("magasin", "ic-sm") +
                        "<span>" + Utils.echapper(boutique.nom) + "</span></span>"
                    : "") +
                  /* La vidéo ayant pris le geste, le lien vers le
                     produit s'écrit ici en toutes lettres. */
                  (s.video
                    ? '<a class="pub-lien" href="#/produit/' + Utils.echapper(produit.id) + '">' +
                        "Voir le produit " + UI.icone("chevron", "ic-sm") + "</a>"
                    : "")
                : "") +
            "</span>"
          : "") +
      "</" + balise + ">"
    );
  }

  const htmlPublicite = (liste) =>
    '<div class="pub-rangee">' + liste.map((s, i) => cartePublicite(s, i)).join("") + "</div>";

  /* Au-delà, on passe à l'écran suivant même si la vidéo n'est pas
     finie : une vidéo qui bloque ne doit pas figer le slider. */
  const ATTENTE_MAX_VIDEO = 60000;

  function demarrerSlider() {
    arreterSlider();
    const piste = UI.$("#slider-piste");
    if (!piste || !piste.children.length) return;
    const points = UI.$$("#slider-points [data-slide]");
    const videos = Array.prototype.slice.call(piste.querySelectorAll("video.slide-img"));
    let index = 0;
    let depuis = Date.now();

    const indexVu = () => Math.round(piste.scrollLeft / piste.clientWidth) || 0;
    const ecranDe = (video) => Array.prototype.indexOf.call(piste.children, video.parentElement);

    /* Une seule vidéo joue : celle qu'on regarde. Les autres se taisent
       et repartent du début — sans quoi le téléphone chauffe et la
       connexion s'épuise pour des écrans que personne ne voit. */
    const reglerVideos = () => {
      for (const video of videos) {
        if (ecranDe(video) === index) {
          const promesse = video.play();
          if (promesse && promesse.catch) promesse.catch(() => {});
        } else {
          video.pause();
          try { video.currentTime = 0; } catch (e) { /* pas encore chargée */ }
        }
      }
    };

    const suivre = () => {
      const vu = indexVu();
      if (vu === index) return;
      index = vu;
      depuis = Date.now();
      points.forEach((pt, i) => pt.classList.toggle("actif", i === index));
      reglerVideos();
    };

    const avancer = () => {
      const n = piste.children.length;
      if (n < 2) return;
      piste.scrollTo({ left: ((index + 1) % n) * piste.clientWidth, behavior: "smooth" });
    };

    piste.addEventListener("scroll", Utils.tempo(suivre, 80), { passive: true });
    piste.addEventListener("pointerdown", () => { derniereInteraction = Date.now(); }, { passive: true });
    piste.addEventListener("touchstart", () => { derniereInteraction = Date.now(); }, { passive: true });

    for (const pt of points) {
      pt.onclick = () => {
        derniereInteraction = Date.now();
        piste.scrollTo({ left: Number(pt.dataset.slide) * piste.clientWidth, behavior: "smooth" });
      };
    }

    /* La vidéo terminée, l'écran suivant prend la main tout de suite. */
    for (const video of videos) {
      video.addEventListener("ended", () => {
        if (ecranDe(video) === index) avancer();
      });
    }

    reglerVideos();
    if (piste.children.length < 2) return;   // rien à faire défiler

    minuterie = setInterval(() => {
      if (!document.body.contains(piste)) { arreterSlider(); return; }
      if (Date.now() - derniereInteraction < 6000) return; // l'utilisateur explore
      /* Une vidéo en cours garde l'écran : on la laisse aller au bout. */
      const ecran = piste.children[index];
      const video = ecran ? ecran.querySelector("video.slide-img") : null;
      if (video && !video.paused && !video.ended && Date.now() - depuis < ATTENTE_MAX_VIDEO) return;
      avancer();
    }, DELAI_SLIDER);
  }

  function arreterSlider() {
    if (minuterie) { clearInterval(minuterie); minuterie = null; }
    /* En quittant l'écran, plus rien ne joue en fond. */
    const piste = UI.$("#slider-piste");
    if (piste) {
      for (const video of piste.querySelectorAll("video.slide-img")) video.pause();
    }
  }

  /* ---------- Couleurs venues de la base ----------
     Une couleur saisie dans les réglages part dans un attribut « style ».
     On n'y laisse passer qu'une couleur hexadécimale : le reste — une
     faute de frappe comme une règle glissée exprès — retombe sur le bleu
     de la DA. */
  const couleurSure = (c) => (/^#[0-9a-f]{6}$/i.test(String(c || "").trim())
    ? String(c).trim() : "#0047D9");

  /* La teinte claire d'une couleur : le fond des ronds pastel de la DA.
     Calculée ici plutôt qu'avec « color-mix » : un téléphone dont le
     navigateur intégré n'a pas été mis à jour ne le connaît pas, et la
     pastille resterait blanche. */
  function teinteClaire(hex, part) {
    const n = parseInt(couleurSure(hex).slice(1), 16);
    const mele = (c) => Math.round(c * part + 255 * (1 - part));
    return "rgb(" + mele(n >> 16) + "," + mele((n >> 8) & 255) + "," + mele(n & 255) + ")";
  }

  /* ---------- Catégories ---------- */

  /* LE NOM COURT, comme sur la DA : « Mode » pour « Mode & Accessoires »,
     « Électronique » pour « Électronique & Informatique ». Sous un rond,
     le nom entier se coupait en « Électronique &… ». Le nom complet reste
     sur l'écran Catégories, et dans ce que lit un lecteur d'écran. */
  function libelleCourt(nom) {
    return String(nom || "").split(/\s+(?:&|et)\s+/i)[0].trim() || String(nom || "");
  }

  /* L'ICÔNE ET LA COULEUR VIENNENT DE LA BASE, pas d'une devinette sur
     le nom : c'est l'enseigne qui les choisit, et la même pastille doit
     se reconnaître d'un écran à l'autre. Sur l'accueil, elle se pose sur
     un rond pastel — la DA y met des ronds clairs, pas des aplats. */
  function rondCategorie(c) {
    const couleur = couleurSure(c.couleur);
    return (
      '<a class="cat-rond-lien" href="#/categorie/' + Utils.echapper(c.id) + '" aria-label="' +
        Utils.echapper(c.nom) + '">' +
        '<span class="cat-rond-da" style="background:' + teinteClaire(couleur, .16) +
          ";color:" + couleur + '">' + UI.icone(c.icone || "categories") + "</span>" +
        '<span class="cat-rond-nom" aria-hidden="true">' +
          Utils.echapper(libelleCourt(c.nom)) + "</span>" +
      "</a>"
    );
  }

  /* ---------- Les boutiques de l'enseigne ---------- */

  /* LE LOGO DANS UN CARRÉ AUX COINS RONDS, celui de la DA — sur la tuile
     de l'accueil, dans la liste et en tête de la fiche. Un rond coupait
     les logos carrés, qui sont la plupart. */
  function logoBoutique(b, classe) {
    return b.logo
      ? '<span class="bou-logo' + (classe ? " " + classe : "") + '"><img src="' +
          Utils.echapper(b.logo) + '" alt="" loading="lazy"></span>'
      : '<span class="bou-logo bou-logo-icone' + (classe ? " " + classe : "") +
          '" style="background:' + couleurSure(b.couleur) + '">' + UI.icone(b.icone) + "</span>";
  }

  /** La tuile de l'accueil : le logo, et le nom dessous. */
  function tuileBoutique(b) {
    return (
      '<a class="bou-tuile" href="#/boutique/' + Utils.echapper(b.id) + '" data-boutique="' +
        Utils.echapper(b.id) + '">' +
        logoBoutique(b) +
        '<span class="bou-tuile-nom">' + Utils.echapper(b.nom) + "</span>" +
      "</a>"
    );
  }

  const fmtDistance = (km) => (km < 1
    ? Math.max(50, Math.round(km * 1000 / 50) * 50) + " m"
    : (km < 10 ? km.toFixed(1).replace(".", ",") : String(Math.round(km))) + " km");

  /** Une ligne de « Nos boutiques » : logo, nom, secteur, note, chevron. */
  function ligneBoutique(b, distance) {
    return (
      '<a class="bou-ligne" href="#/boutique/' + Utils.echapper(b.id) + '" data-boutique="' +
        Utils.echapper(b.id) + '">' +
        logoBoutique(b, "bou-logo-liste") +
        '<span class="bou-ligne-mots">' +
          '<span class="bou-ligne-nom">' + Utils.echapper(b.nom) + "</span>" +
          (b.secteur ? '<span class="bou-ligne-sous">' + Utils.echapper(b.secteur) + "</span>" : "") +
          '<span class="bou-ligne-pied">' +
            /* PAS D'AVIS, PAS DE NOTE. On le dit, plutôt que d'afficher
               un zéro qui passerait pour une mauvaise note. */
            (UI.noteCourte(b) || '<span class="bou-sans-avis">Pas encore d\'avis</span>') +
            (typeof distance === "number"
              ? '<span class="bou-distance">' + UI.icone("lieu", "ic-sm") +
                  "à " + fmtDistance(distance) + "</span>"
              : "") +
          "</span>" +
        "</span>" +
        UI.icone("chevron", "ic-sm") +
      "</a>"
    );
  }

  /* ---------- Vue ---------- */

  /**
   * L'accueil de BIZZOO, dans l'ordre de la DA : la recherche, les
   * catégories en ronds, la bannière, puis les boutiques partenaires.
   * L'offre du jour, la publicité et les populaires viennent après.
   */
  async function afficher(vue) {
    if (!Catalogue.multiBoutiques()) return accueilBoutique(vue, true);

    /* La boutique a déjà été quittée par le routeur, qui devait
       trancher avant que la barre d'onglets ne se règle. */
    UI.entete({ accueil: true });

    const boutiques = Catalogue.boutiques();

    /* LA RECHERCHE EN TÊTE, comme sur la DA. Elle n'est plus un onglet :
       c'est ici qu'on la cherche, avant même de savoir chez qui aller. */
    let html = UI.recherchePilule("Rechercher un produit, une boutique…");
    html += htmlEtatCatalogue();

    /* LES CATÉGORIES, et pas toutes : quinze ronds sur un accueil, c'est
       n'en montrer aucun. L'enseigne en désigne huit, qui tiennent sur
       deux rangées de quatre. C'est par là qu'on cherche quand on ne sait
       pas encore chez qui acheter — donc en tête. */
    const misesEnAvant = Catalogue.categoriesEnAvant();
    const toutes = Catalogue.categoriesBizzoo();
    const vedettes = misesEnAvant.length ? misesEnAvant : toutes.slice(0, 8);
    if (vedettes.length) {
      html += '<nav class="cat-ronds" aria-label="Catégories">' +
        vedettes.map((r) => rondCategorie(r.categorie)).join("") + "</nav>";
    }

    /* La bannière : le slider de BIZZOO, et lui seul. */
    html += htmlSlider(Catalogue.slidesGeneral(), []);

    /* « NOS BOUTIQUES PARTENAIRES », le titre de la DA, JUSTE APRÈS LA
       BANNIÈRE : la DA n'intercale rien entre les deux. « Tout voir »
       ouvre la liste entière, avec ses notes et ses filtres. */
    html += UI.titreSection("Nos boutiques partenaires", boutiques.length ? "#/boutiques" : "");
    html += boutiques.length
      ? '<div class="bou-tuiles">' + boutiques.map(tuileBoutique).join("") + "</div>"
      : UI.vide("magasin", "Les boutiques arrivent bientôt",
          "Elles s'afficheront ici dès leur ouverture.");

    /* L'offre du jour vient ensuite, sous les boutiques. */
    html += htmlOffreDuJour();

    /* Pas de ventes flash ici : une vente flash appartient à la
       boutique qui la fait, et s'annonce sur son écran à elle. Ce que
       BIZZOO met en avant à ce niveau, c'est sa publicité — composée
       dans ses réglages, par le superadministrateur seul. */
    const publicites = Catalogue.publicites();
    if (publicites.length) {
      html += UI.titreSection("Publicité");
      html += htmlPublicite(publicites);
    }

    vue.innerHTML = html;
    demarrerSlider();
    brancherPublicite();

    /* LA RANGÉE DES POPULAIRES ARRIVE APRÈS, et c'est voulu : elle
       demande un aller-retour à la base, et l'accueil ne doit pas
       attendre après elle. Si la base est plus ancienne que ce
       chantier, hors d'atteinte, ou qu'aucune vente n'a encore eu
       lieu, la rangée ne s'affiche pas — l'accueil reste entier. */
    Catalogue.produitsPopulaires(8).then((liste) => {
      if (!liste.length) return;
      /* L'écran a pu changer pendant l'aller-retour : on ne pose pas
         une rangée sur une vue que le client a déjà quittée. */
      if (!document.body.contains(vue)) return;
      if (location.hash && !/^#\/?$/.test(location.hash)) return;
      vue.insertAdjacentHTML("beforeend",
        UI.titreSection("Produits populaires") + UI.rangeeProduits(liste));
    }).catch(() => { /* la rangée s'abstient, le reste tient debout */ });
  }

  /* ---------- « Nos boutiques » ----------
     La liste entière, et trois façons de la ranger — celles de la DA.

       Toutes          l'ordre choisi par l'enseigne ;
       Top             les mieux notées d'abord, et seulement celles qui
                       ONT une note : ranger « sans avis » au milieu des
                       notes ferait croire à une mauvaise note ;
       Proches de moi  par distance, pour les boutiques qui ont posé leur
                       adresse sur la carte. Les autres viennent après,
                       sans distance — on ne l'invente pas. */

  let rangement = "toutes";

  const FILTRES_BOUTIQUES = [
    { cle: "toutes", nom: "Toutes" },
    { cle: "top", nom: "Top" },
    { cle: "proches", nom: "Proches de moi" },
  ];

  /* La distance à vol d'oiseau. Elle n'est pas le trajet, et l'écran ne
     prétend pas le contraire : « à 2,3 km » se lit comme une idée de
     l'éloignement, pas comme un itinéraire. */
  function distanceKm(a, b) {
    const rad = (x) => x * Math.PI / 180;
    const dLat = rad(b.latitude - a.latitude);
    const dLng = rad(b.longitude - a.longitude);
    const h = Math.sin(dLat / 2) ** 2 +
      Math.cos(rad(a.latitude)) * Math.cos(rad(b.latitude)) * Math.sin(dLng / 2) ** 2;
    return 6371 * 2 * Math.asin(Math.min(1, Math.sqrt(h)));
  }

  async function boutiques(vue) {
    UI.entete({ titre: "Nos boutiques", retour: true });
    vue.innerHTML =
      '<div class="puces puces-da" id="bou-filtres">' +
        FILTRES_BOUTIQUES.map((f) =>
          '<button type="button" class="puce' + (f.cle === rangement ? " active" : "") +
            '" data-filtre="' + f.cle + '" aria-pressed="' + (f.cle === rangement) + '">' +
            Utils.echapper(f.nom) + "</button>").join("") +
      "</div>" +
      '<div class="carte bou-liste" id="bou-liste"></div>';

    const zone = UI.$("#bou-liste", vue);
    const puces = UI.$$("#bou-filtres [data-filtre]", vue);

    const choisir = (cle) => {
      rangement = cle;
      for (const p of puces) {
        p.classList.toggle("active", p.dataset.filtre === cle);
        p.setAttribute("aria-pressed", String(p.dataset.filtre === cle));
      }
    };

    async function dessiner(cle) {
      const liste = Catalogue.boutiques().slice();
      if (!liste.length) {
        zone.innerHTML = UI.vide("magasin", "Les boutiques arrivent bientôt",
          "Elles s'afficheront ici dès leur ouverture.");
        return;
      }

      if (cle === "top") {
        const notees = liste.filter((b) => b.nbAvis && b.note !== null)
          .sort((x, y) => (y.note - x.note) || (y.nbAvis - x.nbAvis));
        zone.innerHTML = notees.length
          ? notees.map((b) => ligneBoutique(b)).join("")
          : '<p class="aide" style="margin:0">Aucune boutique n\'a encore reçu d\'avis. ' +
            "Les mieux notées apparaîtront ici.</p>";
        return;
      }

      if (cle === "proches") {
        zone.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>' +
          "Recherche de votre position…</div>";
        let ici;
        try {
          ici = await Compte.positionActuelle();
        } catch (err) {
          /* REFUSÉE OU INTROUVABLE : on le dit, et on revient à la liste
             entière plutôt que de laisser un écran vide. */
          UI.toast(err.message, "err");
          choisir("toutes");
          return dessiner("toutes");
        }
        if (rangement !== "proches") return;   // le client a changé d'avis entre-temps
        const situees = liste.filter((b) => b.latitude !== null && b.longitude !== null)
          .map((b) => ({ b, d: distanceKm(ici, b) }))
          .sort((x, y) => x.d - y.d);
        const ailleurs = liste.filter((b) => b.latitude === null || b.longitude === null);
        zone.innerHTML =
          situees.map((x) => ligneBoutique(x.b, x.d)).join("") +
          (ailleurs.length
            ? (situees.length
                ? '<p class="aide bou-liste-note">Ces boutiques n\'ont pas encore placé ' +
                  "leur adresse sur la carte :</p>"
                : '<p class="aide bou-liste-note">Aucune boutique n\'a encore placé son ' +
                  "adresse sur la carte.</p>") +
              ailleurs.map((b) => ligneBoutique(b)).join("")
            : "");
        return;
      }

      zone.innerHTML = liste.map((b) => ligneBoutique(b)).join("");
    }

    for (const p of puces) {
      p.onclick = () => {
        if (p.dataset.filtre === rangement && p.dataset.filtre !== "proches") return;
        choisir(p.dataset.filtre);
        dessiner(p.dataset.filtre);
      };
    }
    await dessiner(rangement);
  }

  /**
   * L'offre du jour : la plus forte remise RÉELLEMENT en cours.
   *
   * Aucun chiffre n'est écrit en dur. Si plus rien n'est remisé, le
   * bandeau disparaît — plutôt que de promettre une ristourne que le
   * client ne trouvera nulle part une fois sur place.
   */
  function htmlOffreDuJour() {
    const remise = Catalogue.meilleureRemise();
    if (remise === null) return "";
    return (
      '<a class="offre-jour" href="#/promos">' +
        '<span class="offre-jour-quoi">Offre du jour</span>' +
        '<strong class="offre-jour-chiffre">Jusqu\'à −' + remise + "&nbsp;%</strong>" +
        '<span class="offre-jour-voir">Voir les bonnes affaires ' +
          UI.icone("chevron", "ic-sm") + "</span>" +
      "</a>"
    );
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
        " Catalogue de démonstration — la connexion se règle dans Compte → À propos de BIZZOO.</div>";
    }
    return "";
  }

  /* ---------- La publicité s'enchaîne ----------

     Quand une vidéo finit, la rangée avance jusqu'à la suivante et la
     lance. C'est le comportement d'un slider, avec une différence qui
     compte : RIEN NE DÉMARRE TOUT SEUL. La chaîne ne part que d'un
     geste — le client a appuyé sur lecture — et s'arrête d'elle-même
     au bout de la rangée, sans boucler.

     Trois garde-fous, et chacun répond à une façon précise de gâcher
     le forfait d'un client :

       — UNE SEULE VIDÉO À LA FOIS. On met les autres en pause avant de
         lancer la suivante : deux vidéos qui jouent ensemble, c'est le
         double du débit et un téléphone qui chauffe.
       — ON NE JOUE PAS CE QU'ON NE REGARDE PAS. Si la rangée est
         sortie de l'écran — le client a fait défiler l'accueil, ou
         changé d'onglet —, la chaîne s'arrête là.
       — LA CARTE SUIVANTE N'EST PAS TOUJOURS UNE VIDÉO. Si c'est une
         affiche, on s'y arrête : une image n'a pas de fin, et
         continuer sans elle reviendrait à la sauter. */
  function brancherPublicite() {
    const rangee = UI.$(".pub-rangee");
    if (!rangee) return;
    const cartes = Array.from(rangee.querySelectorAll(".pub-carte"));
    const videos = Array.from(rangee.querySelectorAll("video.pub-media"));
    if (videos.length < 1) return;

    const douceur = window.matchMedia &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches
        ? "auto" : "smooth";

    const visible = () => {
      const r = rangee.getBoundingClientRect();
      return r.bottom > 0 && r.top < (window.innerHeight || 0);
    };

    videos.forEach((v) => {
      /* Une seule à la fois : dès qu'une part, les autres s'arrêtent.
         Cela vaut aussi quand c'est le CLIENT qui appuie sur lecture,
         pas seulement quand la chaîne enchaîne. */
      v.addEventListener("play", () => {
        videos.forEach((autre) => { if (autre !== v) autre.pause(); });
      });

      v.addEventListener("ended", () => {
        if (!visible()) return;
        const carte = v.closest(".pub-carte");
        const suivante = cartes[cartes.indexOf(carte) + 1];
        if (!suivante) return;          // fin de rangée : on ne boucle pas

        /* Le défilement porte sur la RANGÉE, jamais sur la page :
           « scrollIntoView » ferait sauter tout l'accueil sous les
           yeux du client pour montrer une publicité. */
        const dx = suivante.getBoundingClientRect().left -
                   rangee.getBoundingClientRect().left;
        rangee.scrollTo({ left: rangee.scrollLeft + dx, behavior: douceur });

        const prochaine = suivante.querySelector("video.pub-media");
        if (!prochaine) return;         // une affiche : on s'arrête dessus
        /* Le temps que le défilement se pose, sinon la vidéo démarre
           hors champ et le client entend avant de voir. */
        setTimeout(() => {
          if (!visible()) return;
          const promesse = prochaine.play();
          /* Le navigateur peut refuser — c'est son droit, et ce n'est
             pas une panne : la rangée reste simplement là où elle est. */
          if (promesse && promesse.catch) promesse.catch(() => {});
        }, douceur === "smooth" ? 420 : 0);
      });
    });
  }

  /** La fiche d'une boutique : on y entre depuis l'accueil ou la liste. */
  async function boutique(vue, id, params) {
    const cible = Catalogue.choisirBoutique(id);
    if (!cible) {
      UI.entete({ titre: "Boutique", retour: true });
      vue.innerHTML = UI.vide("magasin", "Boutique introuvable",
        "Elle a peut-être fermé.",
        '<a class="btn btn-clair" href="#/boutiques">Voir les boutiques</a>');
      return;
    }
    return ficheBoutique(vue, cible, (params && params.onglet) || "produits");
  }

  /* ---------- Les atouts, sous le nom ----------
     LES PROMESSES DE BIZZOO, PAS CELLES DE LA BOUTIQUE. La maquette
     montre « Produits certifiés » et « Service pro » : écrits sur toutes
     les fiches, ils diraient d'un vendeur de voitures comme d'un vendeur
     de cosmétiques une chose que personne n'a vérifiée. On prend donc
     les trois promesses que la DA elle-même porte sur ses supports de
     communication — elles sont celles de l'enseigne, et chacune répond à
     quelque chose qui existe : les livreurs, le SAV avec recours, le
     paiement en ligne. Le paiement ne s'annonce que s'il est ouvert. */
  function atouts() {
    const liste = [
      { icone: "voiture", texte: "Livraison rapide" },
      Paiement.disponible() ? { icone: "check", texte: "Paiement sécurisé" } : null,
      { icone: "outils", texte: "SAV irréprochable" },
    ].filter(Boolean);
    return '<div class="bou-atouts">' + liste.map((a) =>
      '<span class="bou-atout"><span class="bou-atout-rond">' + UI.icone(a.icone, "ic-sm") +
        "</span>" + Utils.echapper(a.texte) + "</span>").join("") + "</div>";
  }

  const ONGLETS_FICHE = [
    { cle: "produits", nom: "Produits" },
    { cle: "avis", nom: "Avis" },
    { cle: "apropos", nom: "À propos" },
  ];

  /**
   * LA FICHE DE LA DA : la couverture, la fiche qui la chevauche — logo,
   * nom, note, slogan, atouts —, « Suivre », puis trois onglets.
   */
  async function ficheBoutique(vue, b, onglet) {
    /* Pas de titre dans l'en-tête : le nom est juste dessous, en grand.
       Le retour, la cloche et le panier suffisent — c'est l'en-tête de
       la DA. */
    UI.entete({ titre: "", retour: true });

    const couverture = (b.photos && b.photos[0]) || "";
    const suivie = typeof Favoris !== "undefined" && Favoris.aBoutique(b.id);

    vue.innerHTML =
      '<div class="bou-couverture' + (couverture ? "" : " bou-couverture-vide") + '">' +
        (couverture
          ? '<img src="' + Utils.echapper(couverture) + '" alt="">'
          : '<span class="bou-couverture-motif">' + UI.motSymbole("clair") + "</span>") +
      "</div>" +
      '<section class="bou-fiche">' +
        '<div class="bou-fiche-tete">' +
          logoBoutique(b, "bou-logo-fiche") +
          '<div class="bou-fiche-mots">' +
            "<h1 class=\"bou-fiche-nom\">" + Utils.echapper(b.nom) + "</h1>" +
            (UI.noteCourte(b) || '<span class="bou-sans-avis">Pas encore d\'avis</span>') +
          "</div>" +
        "</div>" +
        (b.slogan || b.description
          ? '<p class="bou-fiche-slogan">' + Utils.echapper(b.slogan || b.description) + "</p>"
          : "") +
        atouts() +
        '<button type="button" class="btn' + (suivie ? " btn-clair" : "") + '" id="bou-suivre" ' +
          'aria-pressed="' + suivie + '">' +
          (suivie ? UI.icone("check") + "Boutique suivie" : "Suivre") + "</button>" +
        '<div class="bou-onglets" role="tablist">' +
          ONGLETS_FICHE.map((o) =>
            '<button type="button" role="tab" class="bou-onglet' + (o.cle === onglet ? " actif" : "") +
              '" data-onglet="' + o.cle + '" aria-selected="' + (o.cle === onglet) + '">' +
              Utils.echapper(o.nom) + "</button>").join("") +
        "</div>" +
      "</section>" +
      '<div id="bou-contenu"></div>';

    brancherSuivre(b);

    const contenu = UI.$("#bou-contenu", vue);
    const montrer = (cle) => {
      for (const bouton of UI.$$(".bou-onglet", vue)) {
        const oui = bouton.dataset.onglet === cle;
        bouton.classList.toggle("actif", oui);
        bouton.setAttribute("aria-selected", String(oui));
      }
      arreterSlider();
      if (cle === "avis") {
        contenu.innerHTML = VueAvis.bloc("Avis sur cette boutique");
        VueAvis.remplir({ boutique: b.id }, async () => { await Catalogue.rafraichir(); });
      } else if (cle === "apropos") {
        VueInfos.aPropos(contenu);
      } else {
        contenu.innerHTML = htmlProduitsDeLaBoutique(true);
        demarrerSlider();
      }
    };
    for (const bouton of UI.$$(".bou-onglet", vue)) {
      bouton.onclick = () => montrer(bouton.dataset.onglet);
    }
    montrer(ONGLETS_FICHE.some((o) => o.cle === onglet) ? onglet : "produits");
  }

  /* « Suivre » : la boutique entre dans la liste de celles qu'on suit
     (Favoris). Sans compte, on invite à s'en ouvrir un, et l'on revient
     ici ensuite — pas sur l'accueil. */
  function brancherSuivre(b) {
    const bouton = UI.$("#bou-suivre");
    if (!bouton) return;
    bouton.onclick = async () => {
      if (typeof Compte === "undefined" || !Compte.connecte()) {
        UI.toast("Connectez-vous pour suivre une boutique.", "err");
        if (typeof VueCompte !== "undefined") VueCompte.revenirVers("#/boutique/" + b.id);
        location.hash = "#/connexion";
        return;
      }
      bouton.disabled = true;
      try {
        const suit = await Favoris.basculerBoutique(b.id);
        bouton.classList.toggle("btn-clair", suit);
        bouton.setAttribute("aria-pressed", String(suit));
        bouton.innerHTML = suit ? UI.icone("check") + "Boutique suivie" : "Suivre";
        UI.toast(suit ? "Vous suivez " + b.nom + "." : "Vous ne suivez plus " + b.nom + ".", "ok");
      } catch (err) {
        UI.toast(err.message, "err");
      }
      bouton.disabled = false;
    };
  }

  /* L'onglet « Produits » : ce que la boutique met en avant, ses rayons,
     ses promotions — et tout son catalogue, en vignettes, comme la DA.

     SUR LA FICHE (« surLaFiche »), LES VIGNETTES D'ABORD : la DA les
     pose juste sous les onglets, et l'onglet « Produits » leur sert de
     titre. La vitrine de la boutique — ses bannières, ses ventes flash,
     ses promotions, ses rayons — vient dessous. Quand BIZZOO ne compte
     qu'une boutique, cette même page est l'accueil : la bannière reste
     alors en tête, comme sur l'accueil de la DA. */
  function htmlProduitsDeLaBoutique(surLaFiche) {
    const slides = Catalogue.slides();
    const enAvant = Catalogue.misEnAvant();
    /* LES RAYONS DE CETTE BOUTIQUE. « Catalogue.categories() » rendrait
       les quinze secteurs de BIZZOO, dont quatorze qu'elle ne tient
       pas : ce qui la concerne, ce sont les rayons de son secteur où
       elle a quelque chose. */
    const mesRayons = Catalogue.rayonsDeLaBoutique();
    const promos = Catalogue.promotions().slice(0, 8);
    const tous = Catalogue.produits();

    const etat = htmlEtatCatalogue();
    const banniere = htmlSlider(slides, enAvant);

    if (!tous.length) {
      return banniere + etat + UI.vide("boite", "Le catalogue arrive bientôt",
        "Les produits publiés par la boutique s'afficheront ici.");
    }

    let vitrine = "";
    /* Les ventes flash de cette boutique : elles n'appartiennent
       qu'à elle, et ne remontent pas sur l'accueil de BIZZOO. */
    const flash = Catalogue.ventesFlash();
    if (flash.length) {
      vitrine += UI.titreSection("Ventes flash");
      vitrine += UI.rangeeProduits(flash);
    }
    if (promos.length) {
      vitrine += UI.titreSection("Promotions", "#/promos");
      vitrine += UI.rangeeProduits(promos);
    }
    if (mesRayons.length) {
      vitrine += UI.titreSection("Rayons");
      vitrine += mesRayons.slice(0, 6).map((r) => UI.ligneSousRayon(r, r.categorieId)).join("");
    }

    /* TOUT LE CATALOGUE EN VIGNETTES, trois par rangée, comme la DA.
       Au-delà de neuf, la liste complète s'ouvre à part, avec ses tris
       — une fiche de boutique n'a pas à dérouler deux cents photos. */
    const vignettes = '<div class="bou-vignettes">' + tous.slice(0, 9).map((p) =>
      '<a class="bou-vignette" href="#/produit/' + Utils.echapper(p.id) + '" aria-label="' +
        Utils.echapper(p.nom) + '">' + UI.imageProduit(p, "bou-vignette-photo") + "</a>").join("") +
      "</div>";

    if (surLaFiche) {
      return etat + vignettes +
        (tous.length > 9
          ? '<a class="btn btn-clair bou-tout-voir" href="#/produits">Voir les ' +
              tous.length + " produits</a>"
          : "") +
        banniere + vitrine;
    }
    return banniere + etat + vitrine +
      UI.titreSection("Tous les produits", tous.length > 9 ? "#/produits" : "",
        "Tout voir (" + tous.length + ")") + vignettes;
  }

  /**
   * L'accueil quand BIZZOO ne compte qu'UNE boutique : elle EST
   * l'enseigne, et son catalogue est l'accueil.
   */
  async function accueilBoutique(vue) {
    UI.entete({ accueil: true });
    const boutique = Catalogue.boutique();
    let html = UI.recherchePilule("Rechercher un produit…");
    html += htmlProduitsDeLaBoutique();

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
    brancherPublicite();
  }

  return { afficher, boutiques, boutique, arreterSlider };
})();
