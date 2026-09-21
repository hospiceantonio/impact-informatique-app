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

     Une vidéo se joue à la demande (`controls`) : plusieurs vidéos qui
     démarreraient ensemble feraient chauffer le téléphone et
     mangeraient le forfait. */

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

  /* ---------- Catégories ---------- */

  /* L'ICÔNE ET LA COULEUR VIENNENT DE LA BASE, pas d'une devinette sur
     le nom : c'est l'enseigne qui les choisit, et la même pastille doit
     se reconnaître d'un écran à l'autre. */
  function carteCategorie(c, compte) {
    return (
      '<a class="cat-carte" href="#/categorie/' + Utils.echapper(c.id) + '">' +
        '<span class="cat-rond cat-rond-couleur" style="background:' +
          Utils.echapper(c.couleur || "#0B5CF5") + '">' +
          UI.icone(c.icone || "categories") + "</span>" +
        '<span class="cat-nom">' + Utils.echapper(c.nom) + "</span>" +
        (compte
          ? '<span class="cat-compte">' + compte + " article" + (compte > 1 ? "s" : "") + "</span>"
          : '<span class="cat-compte">à découvrir</span>') +
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

    /* La boutique a déjà été quittée par le routeur, qui devait
       trancher avant que la barre d'onglets ne se règle. */
    UI.entete({ accueil: true, actions:
      '<button type="button" class="btn-ic" id="accueil-actualiser" aria-label="Actualiser le catalogue">' +
        UI.icone("actualiser") + "</button>" +
      '<a class="btn-ic" href="#/recherche" aria-label="Rechercher">' + UI.icone("recherche") + "</a>" });

    const boutiques = Catalogue.boutiques();
    const comptes = Catalogue.nombreParBoutique();

    /* Le slider de l'accueil ne montre que ce que BIZZOO y met. */
    let html = htmlSlider(Catalogue.slidesGeneral(), []);
    html += htmlEtatCatalogue();

    html += UI.titreSection("Nos boutiques");
    html += boutiques.length
      ? '<div class="bou-grille">' +
          boutiques.map((b) => carteBoutique(b, comptes[b.id] || 0)).join("") +
        "</div>"
      : UI.vide("magasin", "Les boutiques arrivent bientôt",
          "Elles s'afficheront ici dès leur ouverture.");

    /* Pas de ventes flash ici : une vente flash appartient à la
       boutique qui la fait, et s'annonce sur son écran à elle. Ce que
       BIZZOO met en avant à ce niveau, c'est sa publicité — composée
       dans ses réglages, par le superadministrateur seul. */
    const publicites = Catalogue.publicites();
    if (publicites.length) {
      html += UI.titreSection("Publicité");
      html += htmlPublicite(publicites);
    }

    /* LES CATÉGORIES DE BIZZOO, et pas toutes : quinze lignes sur un
       accueil, c'est n'en montrer aucune. L'enseigne en désigne
       quelques-unes ; le reste attend derrière le bouton, sur l'écran
       qui n'est fait que pour cela. */
    const misesEnAvant = Catalogue.categoriesEnAvant();
    const toutes = Catalogue.categoriesBizzoo();
    const vedettes = misesEnAvant.length ? misesEnAvant : toutes.slice(0, 8);
    if (vedettes.length) {
      html += UI.titreSection("Catégories", "#/categories");
      html += '<div class="cat-grille">' +
        vedettes.map((r) => carteCategorie(r.categorie, r.compte)).join("") +
      "</div>";
      if (toutes.length > vedettes.length) {
        html += '<a class="btn btn-clair" href="#/categories">' + UI.icone("categories") +
          "Voir toutes les catégories (" + toutes.length + ")</a>";
      }
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
      /* Le logo de la boutique à gauche de son nom : on sait chez qui
         l'on est sans avoir à lire. */
      : { titre: b.nom, sous: b.slogan || b.description || "", retour: true,
          vignette: UI.vignetteBoutique(Catalogue.boutiqueChoisie()), actions:
          '<button type="button" class="btn-ic" id="accueil-actualiser" aria-label="Actualiser le catalogue">' +
            UI.icone("actualiser") + "</button>" +
          '<a class="btn-ic" href="#/recherche" aria-label="Rechercher">' + UI.icone("recherche") + "</a>" });

    const slides = Catalogue.slides();
    const enAvant = Catalogue.misEnAvant();
    /* LES RAYONS DE CETTE BOUTIQUE. « Catalogue.categories() » rendrait
       les quinze secteurs de BIZZOO, dont quatorze qu'elle ne tient
       pas : ce qui la concerne, ce sont les rayons de son secteur où
       elle a quelque chose. */
    const mesRayons = Catalogue.rayonsDeLaBoutique();
    const promos = Catalogue.promotions().slice(0, 8);
    const nouveautes = Catalogue.nouveautes(8);
    const boutique = Catalogue.boutique();

    let html = "";

    html += htmlSlider(slides, enAvant);
    html += htmlEtatCatalogue();

    if (mesRayons.length) {
      html += UI.titreSection("Rayons", "#/categories");
      html += mesRayons.slice(0, 6).map((r) => UI.ligneSousRayon(r, r.categorieId)).join("");
    }

    /* Les ventes flash de cette boutique : elles n'appartiennent
       qu'à elle, et ne remontent plus sur l'accueil de BIZZOO. */
    const flash = Catalogue.ventesFlash();
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
