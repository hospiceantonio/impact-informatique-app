/* =========================================================
   Fiche produit — photos, prix, description, commande
   WhatsApp et produits similaires.
   ========================================================= */
const VueProduit = (() => {

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
    const cat = Catalogue.categorie(p.categorieId);
    const sc = Catalogue.sousCategorie(p.categorieId, p.sousCategorieId);
    const remise = Utils.remisePourcent(p.ancienPrix, p.prix);
    const similaires = Catalogue.similaires(p, 4);

    UI.entete({ titre: p.nom, retour: true, sous: cat ? cat.nom : "" });

    /* Message WhatsApp : référence, prix et description complète du produit. */
    const description = (p.description || "").split(/\n+/)
      .map((l) => l.trim()).filter(Boolean).map((l) => "  - " + l).join("\n");
    const fiche =
      "• Produit : " + p.nom +
      (p.reference ? "\n• Référence : " + p.reference : "") +
      "\n• Prix affiché : " + Utils.fmtMontant(p.prix, boutique.devise) +
      (description ? "\n• Description :\n" + description : "");
    const messageWa = p.disponible
      ? "Bonjour " + boutique.nom + " 👋\nJe suis intéressé(e) par ce produit :\n" + fiche +
        "\n\nEst-il disponible ?"
      : "Bonjour " + boutique.nom + " 👋\nCe produit est affiché en rupture :\n" + fiche +
        "\n\nQuand sera-t-il de nouveau disponible ?";

    let html = "";

    html += carrousel(p);

    html +=
      '<div class="carte fiche-infos">' +
        '<div class="fiche-badges">' +
          (p.disponible
            ? '<span class="badge badge-ok">' + UI.icone("check", "ic-sm") + "En stock</span>"
            : '<span class="badge badge-rupture">Rupture de stock</span>') +
          (remise !== null ? '<span class="badge badge-promo">Promotion -' + remise + " %</span>" : "") +
          (p.enAvant ? '<span class="badge badge-avant">' + UI.icone("etoile", "ic-sm") + "Sélection</span>" : "") +
        "</div>" +
        '<h2 class="fiche-nom">' + Utils.echapper(p.nom) + "</h2>" +
        (p.reference ? '<div class="fiche-reference">Réf. ' + Utils.echapper(p.reference) + "</div>" : "") +
        UI.prixHtml(p, { grand: true }) +
        (cat
          ? '<div class="fiche-chemin">' +
              '<a class="puce" href="#/categorie/' + Utils.echapper(cat.id) + '">' + Utils.echapper(cat.nom) + "</a>" +
              (sc ? '<a class="puce" href="#/categorie/' + Utils.echapper(cat.id) + "?sc=" + Utils.echapper(sc.id) + '">' +
                Utils.echapper(sc.nom) + "</a>" : "") +
            "</div>"
          : "") +
      "</div>";

    if (p.video) {
      html +=
        '<div class="carte">' +
          '<div class="carte-titre">' + UI.icone("video", "ic-sm") + " Vidéo de présentation</div>" +
          '<video class="fiche-video" src="' + Utils.echapper(p.video) + '" controls preload="metadata" ' +
            'playsinline' + (Catalogue.imagePrincipale(p)
              ? ' poster="' + Utils.echapper(Catalogue.imagePrincipale(p)) + '"' : "") + "></video>" +
        "</div>";
    }

    if (p.description) {
      html +=
        '<div class="carte">' +
          '<div class="carte-titre">Description</div>' +
          '<div class="fiche-description">' + Utils.paragraphes(p.description) + "</div>" +
        "</div>";
    }

    if (boutique.whatsapp || boutique.tel) {
      html +=
        '<div class="carte">' +
          '<div class="carte-titre">' + (p.disponible ? "Commander" : "Être prévenu(e)") + "</div>" +
          '<div class="btn-rangee">' +
            (boutique.whatsapp
              ? '<a class="btn btn-wa" target="_blank" rel="noopener" href="' +
                  Utils.echapper(Utils.lienWhatsApp(boutique.whatsapp, messageWa, boutique.indicatif)) + '">' +
                  UI.icone("whatsapp") + (p.disponible ? "Commander sur WhatsApp" : "Demander sur WhatsApp") + "</a>"
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

    if (similaires.length) {
      html += UI.titreSection("Dans le même rayon");
      html += UI.rangeeProduits(similaires);
    }

    vue.innerHTML = html;
    activerCarrousel();

    for (const img of UI.$$("[data-visionneuse]", vue)) {
      img.addEventListener("click", () =>
        UI.ouvrirVisionneuse(img.dataset.visionneuse, nomPhoto(p, Number(img.dataset.rang) || 1)));
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
