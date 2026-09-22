/* =========================================================
   Fiche produit — photos, prix, description, commande
   WhatsApp et produits similaires.
   ========================================================= */
const VueProduit = (() => {

  /** « dans 2 j 4 h », « dans 3 h 12 min », « dans 40 min ». */
  function dansCombien(ms) {
    const reste = Math.max(0, ms - Date.now());
    const minutes = Math.round(reste / 60000);
    if (minutes < 60) return "dans " + Math.max(1, minutes) + " min";
    const heures = Math.floor(minutes / 60);
    if (heures < 24) return "dans " + heures + " h" + (minutes % 60 ? " " + (minutes % 60) + " min" : "");
    const jours = Math.floor(heures / 24);
    return "dans " + jours + " j" + (heures % 24 ? " " + (heures % 24) + " h" : "");
  }


  /** "IMP-0002-imprimante-epson-l3250-1.jpg" */
  function nomPhoto(p, rang) {
    const debut = p.reference ? Utils.versNomFichier(p.reference) + "-" : "";
    return debut + Utils.versNomFichier(p.nom) + "-" + rang + ".jpg";
  }

  function carrousel(p) {
    const images = p.images.map(Catalogue.urlImage);
    if (!images.length) {
      return '<div class="fiche-img img-absente">' + UI.marque(120) + "</div>";
    }
    if (images.length === 1) {
      return '<div class="fiche-img"><img src="' + Utils.echapper(images[0]) +
        '" alt="' + Utils.echapper(p.nom) + '" data-rang="1" data-visionneuse="' +
        Utils.echapper(images[0]) + '"></div>';
    }
    return (
      '<div class="fiche-carrousel" id="fiche-carrousel">' +
        images.map((src, i) =>
          '<div class="fiche-img"><img src="' + Utils.echapper(src) + '" alt="' +
            Utils.echapper(p.nom) + " — photo " + (i + 1) + '" data-rang="' + (i + 1) +
            '" data-visionneuse="' + Utils.echapper(src) + '"' +
            (i > 0 ? ' loading="lazy"' : "") + "></div>"
        ).join("") +
      "</div>" +
      '<div class="slider-points fiche-points">' +
        images.map((_, i) => '<button type="button" data-slide="' + i + '"' +
          (i === 0 ? ' class="actif"' : "") + ' aria-label="Photo ' + (i + 1) + '"></button>').join("") +
      "</div>"
    );
  }

  function activerCarrousel() {
    const piste = UI.$("#fiche-carrousel");
    if (!piste) return;
    const points = UI.$$(".fiche-points [data-slide]");
    const maj = () => {
      const index = Math.round(piste.scrollLeft / piste.clientWidth);
      points.forEach((pt, i) => pt.classList.toggle("actif", i === index));
    };
    piste.addEventListener("scroll", Utils.tempo(maj, 80), { passive: true });
    for (const pt of points) {
      pt.onclick = () => piste.scrollTo({ left: Number(pt.dataset.slide) * piste.clientWidth, behavior: "smooth" });
    }
  }

  /**
   * Le compteur et le bouton « Ajouter au panier », dans la barre du
   * bas. La fiche n'est pas redessinée après l'ajout : le client vient
   * de la lire, la lui remettre sous les yeux lui ferait perdre sa place.
   */
  function brancherPanier(barre, p) {
    const affichage = UI.$("#p-quantite", barre);
    if (!affichage) return;
    let quantite = 1;
    const poser = () => { affichage.textContent = String(quantite); };

    UI.$("#p-moins", barre).onclick = () => { quantite = Math.max(1, quantite - 1); poser(); };
    UI.$("#p-plus", barre).onclick = () => {
      quantite = Math.min(Panier.MAX_QUANTITE, quantite + 1);
      poser();
    };

    UI.$("#p-ajouter", barre).onclick = () => {
      if (!Panier.ajouter(p.id, quantite)) {
        UI.toast("Votre panier est plein (" + Panier.MAX_ARTICLES + " produits différents)", "err");
        return;
      }
      UI.toast(quantite > 1
        ? quantite + " articles ajoutés au panier"
        : "Ajouté au panier", "ok");
      quantite = 1;
      poser();
      const dedans = UI.$("#p-deja");
      if (dedans) dedans.hidden = false;
      const combien = UI.$("#p-deja-combien");
      if (combien) {
        const n = Panier.quantiteDe(p.id);
        combien.textContent = n + (n > 1 ? " articles" : " article");
      }
    };
  }

  /**
   * LES SPÉCIFICATIONS DE LA DA, tirées de la description. Une boutique
   * écrit « Processeur : Intel Core i5 » ligne après ligne — c'est déjà
   * un tableau, il suffit de le poser comme tel. Il en faut au moins
   * deux : une seule ligne « Couleur : noir » au milieu d'un paragraphe
   * n'est pas une fiche technique.
   *
   * Ce qui n'a pas la forme « clé : valeur » reste du texte, sous
   * « Description » : rien de ce que la boutique a écrit ne se perd.
   */
  function lireSpecifications(description) {
    const lignes = String(description || "").split(/\n+/).map((l) => l.trim()).filter(Boolean);
    const specs = [];
    const reste = [];
    for (const l of lignes) {
      const m = /^[-•*\s]*([^:]{2,32}?)\s*:\s*(.+)$/.exec(l);
      if (m && !/https?$/i.test(m[1])) specs.push({ cle: m[1].trim(), valeur: m[2].trim() });
      else reste.push(l);
    }
    if (specs.length < 2) return { specs: [], texte: String(description || "") };
    return { specs, texte: reste.join("\n") };
  }

  async function afficher(vue, id) {
    const p = Catalogue.produit(id);
    if (!p) {
      UI.entete({ titre: "Produit", retour: true });
      vue.innerHTML = UI.vide("alerte", "Produit introuvable",
        "Il a peut-être été retiré du catalogue.",
        '<a class="btn btn-clair" href="#/">Retour à l\'accueil</a>');
      return;
    }

    const boutique = Catalogue.boutique();
    const remise = Utils.remisePourcent(p.ancienPrix, p.prix);
    const similaires = Catalogue.similaires(p, 4);

    /* L'EN-TÊTE DE LA DA : le retour à gauche, le cœur et le panier à
       droite, et pas de titre — le nom du produit est en grand juste
       sous la photo. Le cœur est en haut, loin de la photo : posé
       dessus, il se touchait par accident en la faisant défiler. */
    UI.entete({ titre: "", retour: true, actions: UI.coeur(p.id, "coeur-entete") });

    /* Message WhatsApp : référence, prix et description complète du produit. */
    const description = (p.description || "").split(/\n+/)
      .map((l) => l.trim()).filter(Boolean).map((l) => "  - " + l).join("\n");
    const fiche =
      "• Produit : " + p.nom +
      /* Le code d'abord : c'est le seul repère que la boutique et le
         client désignent de la même façon, quoi qu'il arrive au reste. */
      (p.code ? "\n• Code : " + p.code : "") +
      (p.reference ? "\n• Référence : " + p.reference : "") +
      "\n• Prix affiché : " + Utils.fmtMontant(p.prix, boutique.devise) +
      (description ? "\n• Description :\n" + description : "");
    const etat = Catalogue.statut(p);
    const messageWa = etat === "disponible"
      ? "Bonjour " + boutique.nom + " 👋\nJe suis intéressé(e) par ce produit :\n" + fiche +
        "\n\nEst-il toujours disponible ?"
      : etat === "rupture"
        ? "Bonjour " + boutique.nom + " 👋\nCe produit est affiché « En rupture » :\n" + fiche +
          "\n\nQuand sera-t-il de nouveau disponible ?"
        : "Bonjour " + boutique.nom + " 👋\nCe produit est affiché « Sur commande » :\n" + fiche +
          "\n\nSous combien de temps pouvez-vous me l'avoir ?";

    let html = "";

    html += carrousel(p);

    const lu = lireSpecifications(p.description);
    const dejaDedans = Panier.quantiteDe(p.id);

    /* DANS L'ORDRE DE LA DA : le nom, le prix en bleu et sa remise en
       pastille orange, l'étoile et les avis. Ce qui suit — l'état du
       stock, la vente flash, le code — ne figure pas sur la maquette,
       mais le client en a besoin : il vient après, plus discret. */
    html +=
      '<div class="fiche-infos">' +
        '<h2 class="fiche-nom">' + Utils.echapper(p.nom) + "</h2>" +
        '<div class="fiche-prix-ligne">' +
          UI.prixHtml(p, { grand: true }) +
          (remise !== null ? '<span class="badge badge-promo">-' + remise + "&nbsp;%</span>" : "") +
        "</div>" +
        /* Un prix barré ressemble à une promotion, et une promotion
           s'arrête. Ici il faut dire ce que c'est : le prix de ce
           compte-ci, qui ne s'arrêtera pas dimanche soir. */
        (p.prixRevendeur
          ? '<div class="fiche-revendeur">' + UI.icone("magasin", "ic-sm") +
            "Votre prix revendeur</div>"
          : "") +
        /* La note mène au bloc des avis, plus bas. */
        (p.nbAvis ? '<a class="fiche-note" href="#av-bloc">' + UI.noteCourte(p) + "</a>" : "") +
        '<div class="fiche-badges">' +
          '<span class="badge ' + Catalogue.STATUTS[etat].classe + '">' +
            (etat === "disponible" ? UI.icone("check", "ic-sm") : "") +
            Catalogue.STATUTS[etat].nom + "</span>" +
          (Catalogue.enVenteFlash(p)
            ? '<span class="badge badge-flash">' + UI.icone("energie", "ic-sm") + "Vente flash</span>"
            : "") +
          (p.enAvant ? '<span class="badge badge-avant">' + UI.icone("etoile", "ic-sm") + "Sélection</span>" : "") +
          (p.code ? '<span class="fiche-code">Code ' + Utils.echapper(p.code) + "</span>" : "") +
          (p.reference ? '<span class="fiche-ref">Réf. ' + Utils.echapper(p.reference) + "</span>" : "") +
        "</div>" +
        (Catalogue.enVenteFlash(p)
          ? '<div class="flash-echeance">' + UI.icone("horloge", "ic-sm") +
            " Vente flash — se termine " + Utils.echapper(dansCombien(p.flashFin)) + "</div>"
          : "") +
        /* Le réassort annoncé : le client sait quand revenir. */
        (etat === "approvisionnement"
          ? '<div class="appro-echeance">' + UI.icone("horloge", "ic-sm") +
            " En cours d'approvisionnement — arrive " +
            Utils.echapper(Utils.delaiEnMots(Catalogue.joursAppro(p))) + "</div>"
          : "") +
        /* Déjà dans le panier : on le dit, pour qu'il ne l'ajoute pas
           deux fois par mégarde. Le bloc est posé caché et se montre
           après un ajout, sans redessiner la fiche. */
        '<a class="p-panier-dedans" id="p-deja" href="#/panier"' + (dejaDedans ? "" : " hidden") + ">" +
          UI.icone("check", "ic-sm") + "<span>Déjà dans votre panier — <b id=\"p-deja-combien\">" +
          dejaDedans + (dejaDedans > 1 ? " articles" : " article") + "</b></span>" +
          UI.icone("chevron", "ic-sm") + "</a>" +
      "</div>";

    if (lu.specs.length) {
      html +=
        '<div class="carte">' +
          '<div class="carte-titre">Spécifications</div>' +
          '<dl class="fiche-specs">' + lu.specs.map((s) =>
            "<dt>" + Utils.echapper(s.cle) + "</dt><dd>" + Utils.echapper(s.valeur) + "</dd>").join("") +
          "</dl>" +
        "</div>";
    }

    if (p.video) {
      html +=
        '<div class="carte">' +
          '<div class="carte-titre">' + UI.icone("video", "ic-sm") + " Vidéo de présentation</div>" +
          '<video class="fiche-video" src="' + Utils.echapper(p.video) + '" controls preload="metadata" ' +
            'playsinline' + (Catalogue.imagePrincipale(p)
              ? ' poster="' + Utils.echapper(Catalogue.imagePrincipale(p)) + '"' : "") + "></video>" +
        "</div>";
    }

    if (lu.texte.trim()) {
      html +=
        '<div class="carte">' +
          '<div class="carte-titre">Description</div>' +
          '<div class="fiche-description">' + Utils.paragraphes(lu.texte) + "</div>" +
        "</div>";
    }

    if (boutique.whatsapp || boutique.tel) {
      html +=
        '<div class="carte">' +
          '<div class="carte-titre">' + (etat === "disponible" ? "Commander" : "Passer commande") + "</div>" +
          '<div class="btn-rangee">' +
            (boutique.whatsapp
              ? '<a class="btn btn-wa" target="_blank" rel="noopener" href="' +
                  Utils.echapper(Utils.lienWhatsApp(boutique.whatsapp, messageWa, boutique.indicatif)) + '">' +
                  UI.icone("whatsapp") +
                  (etat === "disponible" ? "Commander sur WhatsApp" : "Demander le délai") + "</a>"
              : "") +
            (boutique.tel
              ? '<a class="btn btn-clair" href="' + Utils.echapper(Utils.lienTel(boutique.tel, boutique.indicatif)) + '">' +
                  UI.icone("tel") + "Appeler la boutique</a>"
              : "") +
          "</div>" +
          '<div class="aide" style="margin-top:10px">Retrait en boutique ou livraison à discuter au moment de la commande.</div>' +
        "</div>";
    }

    if (p.images.length) {
      html +=
        '<div class="carte">' +
          '<div class="carte-titre">Photos du produit</div>' +
          '<p class="aide" style="margin:0 0 12px">Gardez-les sur votre téléphone ou partagez-les : ' +
            "elles s'enregistrent dans vos Téléchargements.</p>" +
          '<button type="button" class="btn btn-clair" id="p-telecharger-photos">' +
            UI.icone("telecharger") +
            (p.images.length > 1 ? "Enregistrer les " + p.images.length + " photos" : "Enregistrer la photo") +
          "</button>" +
        "</div>";
    }

    /* Les avis avant les produits voisins : on décide d'acheter CET
       article-là, pas un autre. Le bloc se pose vide et se remplit
       après — la fiche ne doit pas attendre le réseau pour s'afficher. */
    html += VueAvis.bloc("Avis sur ce produit");

    if (similaires.length) {
      html += UI.titreSection("Dans le même rayon");
      html += UI.rangeeProduits(similaires);
    }

    vue.innerHTML = html;
    activerCarrousel();

    /* « AJOUTER AU PANIER », ORANGE, EN BAS — comme la DA. Le compteur
       l'accompagne : on choisit la quantité là où l'on ajoute.
       Un produit en rupture n'a pas de barre : la boutique ne pourrait
       pas le remettre, et la base refuserait la commande au moment de
       payer. Le bouton WhatsApp, plus haut, reste là pour demander le
       délai. */
    if (etat !== "rupture") {
      const barre = UI.barreAction(
        '<div class="pa-compteur pa-compteur-da">' +
          '<button type="button" id="p-moins" aria-label="Un de moins">−</button>' +
          '<span id="p-quantite">1</span>' +
          '<button type="button" id="p-plus" aria-label="Un de plus">+</button>' +
        "</div>" +
        '<button type="button" class="btn btn-orange" id="p-ajouter">Ajouter au panier</button>');
      brancherPanier(barre, p);
    }

    /* Un avis déposé change la note du produit : on redemande le
       catalogue, et la fiche se redessine avec ses nouvelles étoiles. */
    VueAvis.remplir({ produit: p.id }, async () => {
      await Catalogue.rafraichir();
    });

    /* Toute la série est ouverte d'un coup : le client fait défiler. */
    const serie = p.images.map(Catalogue.urlImage)
      .map((src, i) => ({ src, nom: nomPhoto(p, i + 1) }));
    for (const img of UI.$$("[data-visionneuse]", vue)) {
      img.addEventListener("click", () =>
        UI.ouvrirVisionneuse(serie, (Number(img.dataset.rang) || 1) - 1));
    }

    const btnPhotos = UI.$("#p-telecharger-photos");
    if (btnPhotos) {
      btnPhotos.onclick = async () => {
        const images = p.images.map(Catalogue.urlImage);
        btnPhotos.disabled = true;
        const libelle = btnPhotos.innerHTML;
        let reussies = 0;
        for (let i = 0; i < images.length; i++) {
          btnPhotos.innerHTML = UI.icone("telecharger") +
            (images.length > 1 ? "Enregistrement… (" + (i + 1) + "/" + images.length + ")" : "Enregistrement…");
          try {
            await Utils.telechargerImage(images[i], nomPhoto(p, i + 1));
            reussies++;
          } catch (err) {
            UI.toast(err.message || "Téléchargement impossible", "err");
            break;
          }
        }
        btnPhotos.innerHTML = libelle;
        btnPhotos.disabled = false;
        if (reussies) {
          UI.toast(reussies > 1
            ? reussies + " photos enregistrées dans Téléchargements"
            : "Photo enregistrée dans Téléchargements", "ok");
        }
      };
    }
  }

  return { afficher };
})();
