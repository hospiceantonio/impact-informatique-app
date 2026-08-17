/* =========================================================
   Produits — liste avec recherche et filtres, formulaire
   (photos, vidéo, prix, catégorie) et fiche.
   ========================================================= */
const VueProduits = (() => {

  /* =====================================================
     Liste
     ===================================================== */

  let filtreCategorie = "";
  let termeRecherche = "";

  async function liste(vue) {
    const [produits, categories] = await Promise.all([
      Store.listerProduits(), Store.listerCategories(),
    ]);

    UI.entete({ titre: "Produits", sous: produits.length + " produit" + (produits.length > 1 ? "s" : "") + " au catalogue" });

    if (!produits.length) {
      vue.innerHTML = UI.vide("boite", "Aucun produit pour l'instant",
        "Ajoutez votre premier produit : photo, prix, catégorie, et il sera prêt à publier.",
        '<a class="btn" href="#/produit/nouveau">' + UI.icone("plus") + "Ajouter un produit</a>");
      return;
    }

    if (filtreCategorie && !categories.some((c) => c.id === filtreCategorie)) filtreCategorie = "";

    vue.innerHTML =
      '<div class="recherche-boite">' + UI.icone("recherche", "ic-sm") +
        '<input id="produits-recherche" type="search" placeholder="Rechercher un produit…" autocomplete="off" value="' +
        Utils.echapper(termeRecherche) + '">' +
      "</div>" +
      '<div class="puces" id="produits-filtres">' +
        '<button type="button" class="puce' + (filtreCategorie ? "" : " active") + '" data-filtre="">Tout</button>' +
        categories.map((c) =>
          '<button type="button" class="puce' + (filtreCategorie === c.id ? " active" : "") +
          '" data-filtre="' + Utils.echapper(c.id) + '">' + Utils.echapper(c.nom) + "</button>").join("") +
      "</div>" +
      '<div id="produits-liste"></div>';

    const zone = UI.$("#produits-liste");
    const nomSousCategorie = (p) => {
      const c = categories.find((x) => x.id === p.categorieId);
      const cat = !c ? "Sans catégorie"
        : ((c.sousCategories || []).find((x) => x.id === p.sousCategorieId) || {}).nom
          ? c.nom + " · " + (c.sousCategories || []).find((x) => x.id === p.sousCategorieId).nom
          : c.nom;
      return (p.reference ? p.reference + " · " : "") + cat;
    };

    const rendre = () => {
      let visibles = produits;
      if (filtreCategorie) visibles = visibles.filter((p) => p.categorieId === filtreCategorie);
      visibles = Store.chercherProduits(visibles, termeRecherche);
      zone.innerHTML = visibles.length
        ? '<div class="carte carte-liste">' + visibles.map((p) => UI.ligneProduit(p, nomSousCategorie(p))).join("") + "</div>"
        : UI.vide("recherche", "Aucun produit trouvé", "Essayez un autre mot ou un autre filtre.");
    };

    UI.$("#produits-recherche").addEventListener("input", Utils.tempo((ev) => {
      termeRecherche = ev.target.value;
      rendre();
    }, 200));

    for (const b of UI.$$("#produits-filtres [data-filtre]")) {
      b.onclick = () => {
        filtreCategorie = b.dataset.filtre;
        for (const x of UI.$$("#produits-filtres [data-filtre]")) x.classList.toggle("active", x === b);
        rendre();
      };
    }

    rendre();
  }

  /* =====================================================
     Stock : la saisie rapide, sans passer par le formulaire
     ===================================================== */

  function feuilleStock(p, auTermine) {
    const corps = UI.ouvrirFeuille("Disponibilité — " + p.nom,
      '<p class="aide" style="margin:0 0 14px">Combien de pièces reste-t-il en boutique ? ' +
        "À zéro, vos clients voient « En rupture ». Un produit que vous ne tenez pas " +
        "en boutique se met « Sur commande ».</p>" +
      '<div class="stock-saisie">' +
        '<button type="button" class="btn-ic btn-ic-clair" id="stock-moins" aria-label="Un de moins">' +
          UI.icone("bas") + "</button>" +
        '<input id="stock-valeur" type="tel" inputmode="numeric" value="' +
          (p.surCommande ? 0 : p.stock) + '" aria-label="Stock">' +
        '<button type="button" class="btn-ic btn-ic-clair" id="stock-plus" aria-label="Un de plus">' +
          UI.icone("haut") + "</button>" +
      "</div>" +
      '<div class="btn-rangee" style="margin-top:18px">' +
        '<button type="button" class="btn" id="stock-enregistrer">' + UI.icone("check") +
          "Enregistrer ce stock</button>" +
        '<button type="button" class="btn btn-clair btn-danger-clair" id="stock-zero">' +
          UI.icone("alerte") + "En rupture</button>" +
        (p.surCommande
          ? ""
          : '<button type="button" class="btn btn-clair" id="stock-commande">' +
              UI.icone("nuage") + "Passer en « Sur commande »</button>") +
      "</div>");

    const champ = UI.$("#stock-valeur", corps);
    const lire = () => Math.max(0, Math.round(Number(String(champ.value).replace(/\D/g, "")) || 0));
    UI.$("#stock-moins", corps).onclick = () => { champ.value = Math.max(0, lire() - 1); };
    UI.$("#stock-plus", corps).onclick = () => { champ.value = lire() + 1; };

    const enregistrer = async (maj, message) => {
      try {
        await Store.majDisponibilite(p.id, maj);
        UI.fermerFeuille();
        UI.toast(message, "ok");
        auTermine();
      } catch (err) {
        UI.toast(err.message, "err");
      }
    };
    UI.$("#stock-enregistrer", corps).onclick = () => {
      const stock = lire();
      enregistrer({ stock, surCommande: false },
        stock > 0 ? "Stock : " + stock + " en boutique" : "Produit passé « En rupture »");
    };
    UI.$("#stock-zero", corps).onclick = () =>
      enregistrer({ stock: 0, surCommande: false }, "Produit passé « En rupture »");
    const versCommande = UI.$("#stock-commande", corps);
    if (versCommande) {
      versCommande.onclick = () =>
        enregistrer({ surCommande: true }, "Produit passé « Sur commande »");
    }
  }

  /* =====================================================
     Formulaire (création / modification)
     ===================================================== */

  /** Photos en cours d'édition : [{ id, apercu, chemin? (en ligne), dataUrl? (nouvelle) }] */
  let photosTravail = [];
  /** Vidéo en cours d'édition : { chemin, url } | { fichier, url, taille } | null */
  let videoTravail = null;

  function htmlPhotos() {
    let html = photosTravail.map((photo, i) =>
      '<div class="photo-boite">' +
        '<img src="' + photo.apercu + '" alt="Photo ' + (i + 1) + '" data-agrandir="' + i + '">' +
        (i === 0 ? '<span class="photo-principale">Principale</span>' : "") +
        '<button type="button" class="photo-retirer" data-retirer="' + i + '" aria-label="Retirer la photo">' +
          UI.icone("fermer", "ic-sm") + "</button>" +
      "</div>"
    ).join("");
    if (photosTravail.length < Store.MAX_PHOTOS) {
      html +=
        '<label class="photo-ajout">' +
          UI.icone("camera") + "<span>Ajouter</span>" +
          '<input type="file" accept="image/*" multiple hidden id="photo-fichier">' +
        "</label>";
    }
    return html;
  }

  function brancherPhotos(base) {
    const zone = UI.$("#photos-zone", base);

    const rafraichir = () => {
      zone.innerHTML = htmlPhotos();
      brancher();
    };

    const brancher = () => {
      const champ = UI.$("#photo-fichier", zone);
      if (champ) {
        champ.addEventListener("change", async () => {
          const fichiers = Array.from(champ.files || []).slice(0, Store.MAX_PHOTOS - photosTravail.length);
          for (const fichier of fichiers) {
            try {
              const { dataUrl } = await Utils.compresserImage(fichier);
              photosTravail.push({ id: Utils.uid("pho"), dataUrl, apercu: dataUrl });
            } catch (err) {
              UI.toast(err.message || "Photo illisible", "err");
            }
          }
          rafraichir();
        });
      }
      for (const b of UI.$$("[data-retirer]", zone)) {
        b.onclick = () => {
          photosTravail.splice(Number(b.dataset.retirer), 1);
          rafraichir();
        };
      }
      for (const img of UI.$$("[data-agrandir]", zone)) {
        img.onclick = () => UI.ouvrirVisionneuse(
          photosTravail.map((photo) => ({ src: photo.apercu })), Number(img.dataset.agrandir));
      }
    };

    rafraichir();
  }

  function htmlVideo() {
    if (videoTravail) {
      return (
        '<div class="video-boite">' +
          '<video src="' + Utils.echapper(videoTravail.url) + '" controls preload="metadata" playsinline></video>' +
          '<div class="video-pied">' +
            "<span>" + (videoTravail.taille
              ? "Nouvelle vidéo · " + Utils.echapper(Utils.tailleLisible(videoTravail.taille))
              : "Vidéo en ligne") + "</span>" +
            '<button type="button" class="btn-ic btn-ic-clair btn-ic-danger" data-video-retirer aria-label="Retirer la vidéo">' +
              UI.icone("poubelle", "ic-sm") + "</button>" +
          "</div>" +
        "</div>"
      );
    }
    return (
      '<label class="video-ajout">' +
        UI.icone("video") +
        "<span>Ajouter une vidéo</span>" +
        '<small>Facultatif · ' + Store.MAX_VIDEO_MO + ' Mo maximum</small>' +
        '<input type="file" accept="video/*" hidden id="video-fichier">' +
      "</label>"
    );
  }

  function brancherVideo(base) {
    const zone = UI.$("#video-zone", base);

    const rafraichir = () => {
      zone.innerHTML = htmlVideo();
      brancher();
    };

    const brancher = () => {
      const champ = UI.$("#video-fichier", zone);
      if (champ) {
        champ.addEventListener("change", () => {
          const fichier = champ.files && champ.files[0];
          if (!fichier) return;
          if (fichier.size > Store.MAX_VIDEO_MO * 1024 * 1024) {
            UI.toast("Vidéo trop lourde (" + Utils.tailleLisible(fichier.size) + ") : " +
              Store.MAX_VIDEO_MO + " Mo au maximum.", "err");
            return;
          }
          if (videoTravail && videoTravail.url && videoTravail.taille) URL.revokeObjectURL(videoTravail.url);
          videoTravail = { fichier, url: URL.createObjectURL(fichier), taille: fichier.size };
          rafraichir();
        });
      }
      const retirer = UI.$("[data-video-retirer]", zone);
      if (retirer) {
        retirer.onclick = () => {
          if (videoTravail && videoTravail.taille && videoTravail.url) URL.revokeObjectURL(videoTravail.url);
          videoTravail = null;
          rafraichir();
        };
      }
    };

    rafraichir();
  }

  function optionsSousCategories(categories, categorieId, valeur) {
    const c = categories.find((x) => x.id === categorieId);
    const sousCategories = (c && c.sousCategories) || [];
    if (!sousCategories.length) {
      return '<option value="">— (aucune sous-catégorie dans ce rayon)</option>';
    }
    return '<option value="">Choisir…</option>' +
      sousCategories.map((s) =>
        '<option value="' + Utils.echapper(s.id) + '"' + (valeur === s.id ? " selected" : "") + ">" +
        Utils.echapper(s.nom) + "</option>").join("");
  }

  async function formulaire(vue, id) {
    /* Retoucher un produit existant demande le droit de modification ;
       en créer un neuf reste ouvert à toute l'équipe. */
    if (id && !Supabase.peutModifierProduits()) {
      UI.entete({ titre: "Modifier le produit", retour: true });
      vue.innerHTML = UI.vide("cle", "Modification non autorisée",
        "Votre compte peut ajouter des produits, mais pas retoucher ceux du catalogue. " +
        "Demandez ce droit à l'administrateur.",
        '<a class="btn btn-clair" href="#/produit/' + Utils.echapper(id) + '">Revenir à la fiche</a>');
      return;
    }

    const existant = id ? await Store.lireProduit(id) : null;
    const referenceProposee = existant ? existant.reference : await Store.prochaineReference();
    if (id && !existant) {
      UI.entete({ titre: "Produit", retour: true });
      vue.innerHTML = UI.vide("alerte", "Produit introuvable", "");
      return;
    }
    const categories = await Store.listerCategories();

    UI.entete({ titre: existant ? "Modifier le produit" : "Nouveau produit", retour: true });

    if (!categories.length) {
      vue.innerHTML = UI.vide("categories", "Créez d'abord une catégorie",
        "Chaque produit doit être rangé dans une catégorie et une sous-catégorie.",
        '<a class="btn" href="#/categories">Ouvrir les catégories</a>');
      return;
    }

    photosTravail = [];
    videoTravail = null;
    if (existant) {
      photosTravail = await Store.photosDeProduit(existant.id);
      if (existant.video) videoTravail = { chemin: existant.video, url: existant.videoUrl };
    }

    const categorieInitiale = existant ? existant.categorieId : (categories[0] && categories[0].id);
    const tauxBoutique = Store.lireReglages().tauxMarge;
    const tauxProduit = existant ? existant.tauxMarge : null;

    vue.innerHTML =
      '<div class="carte">' +
        '<div class="carte-titre">Photos <span class="aide-inline">(' + Store.MAX_PHOTOS + ' max, la première s\'affiche en vitrine)</span></div>' +
        '<div class="photos-zone" id="photos-zone"></div>' +
      "</div>" +

      '<div class="carte">' +
        '<div class="carte-titre">Vidéo de présentation <span class="aide-inline">(facultative)</span></div>' +
        '<div id="video-zone"></div>' +
      "</div>" +

      '<div class="carte">' +
        UI.champTexte({ id: "p-nom", label: "Nom du produit", valeur: existant ? existant.nom : "",
          obligatoire: true, placeholder: "Ex. Ordinateur portable HP 15" }) +
        UI.champTexte({ id: "p-reference", label: "Référence", valeur: referenceProposee,
          aide: "Attribuée automatiquement, modifiable (elle apparaît sur la fiche et dans les commandes WhatsApp)." }) +
        UI.champZone({ id: "p-description", label: "Description", valeur: existant ? existant.description : "",
          lignes: 5, placeholder: "Caractéristiques, état, garantie…\nUne idée par ligne." }) +
      "</div>" +

      /* ---------- Prix ----------
         On tape ce qu'on a payé, on choisit sa marge, et le prix public
         se calcule tout seul. Il reste modifiable pour arrondir. */
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("promo", "ic-sm") + " Prix</div>" +
        UI.champMontant({ id: "p-grossiste", label: "Prix grossiste",
          valeur: existant && existant.prixGrossiste ? existant.prixGrossiste : "",
          aide: "Ce que la boutique paie. Il ne quitte jamais l'application admin : " +
            "vos clients ne le voient pas." }) +
        '<div class="champ">' +
          '<label for="p-taux">Taux de marge</label>' +
          '<div class="champ-montant">' +
            '<input id="p-taux" inputmode="decimal" autocomplete="off" placeholder="' +
              Utils.echapper(Utils.fmtTaux(tauxBoutique)) + '"' +
              (tauxProduit === null ? "" : ' value="' + Utils.echapper(Utils.fmtTaux(tauxProduit)) + '"') +
              ">" +
            '<span class="devise">%</span>' +
          "</div>" +
          '<div class="aide">Laissé vide, c\'est le taux de la boutique (' +
            Utils.echapper(Utils.fmtTaux(tauxBoutique)) + " %) qui s'applique.</div>" +
        "</div>" +
        UI.champMontant({ id: "p-prix", label: "Prix public", obligatoire: true,
          valeur: existant ? existant.prix : "",
          aide: "Calculé à partir des deux champs ci-dessus. C'est le prix que voient " +
            "vos clients — vous pouvez l'arrondir à la main." }) +
        '<div id="p-marge"></div>' +
        UI.champMontant({ id: "p-ancien", label: "Prix barré (optionnel)",
          valeur: existant && existant.ancienPrix ? existant.ancienPrix : "",
          aide: "L'ancien prix, pour afficher une promotion (« -15 % »)." }) +
      "</div>" +

      '<div class="carte">' +
        '<div class="champ">' +
          '<label for="p-categorie">Catégorie <span class="obligatoire">*</span></label>' +
          '<select id="p-categorie">' +
            categories.map((c) =>
              '<option value="' + Utils.echapper(c.id) + '"' + (categorieInitiale === c.id ? " selected" : "") + ">" +
              Utils.echapper(c.nom) + "</option>").join("") +
          "</select>" +
        "</div>" +
        '<div class="champ">' +
          '<label for="p-souscategorie">Sous-catégorie <span class="obligatoire">*</span></label>' +
          '<select id="p-souscategorie">' +
            optionsSousCategories(categories, categorieInitiale, existant ? existant.sousCategorieId : "") +
          "</select>" +
        "</div>" +
      "</div>" +

      '<div class="carte">' +
        UI.interrupteur({ id: "p-sur-commande", label: "Produit sur commande",
          actif: existant ? !!existant.surCommande : false,
          aide: "Vous ne le tenez pas en boutique : il est commandé à la demande. Pas de stock à saisir." }) +
        '<div id="p-zone-stock">' +
          UI.champTexte({ id: "p-stock", label: "Stock", type: "tel",
            valeur: existant ? existant.stock : "",
            placeholder: "0",
            aide: "Nombre de pièces en boutique. À zéro, vos clients voient « En rupture »." }) +
        "</div>" +
        (Supabase.estAdmin()
          ? UI.interrupteur({ id: "p-avant", label: "Mettre en avant",
              actif: existant ? !!existant.enAvant : false,
              aide: "Le produit défile dans le slider client, après les images (" +
                Store.MAX_EN_AVANT + " produits au maximum)." })
          : "") +
      "</div>" +

      '<div class="btn-rangee">' +
        '<button type="button" class="btn" id="p-enregistrer">' + UI.icone("check") +
          (existant ? "Enregistrer les modifications" : "Ajouter le produit") + "</button>" +
        (existant
          ? '<button type="button" class="btn btn-clair btn-danger-clair" id="p-supprimer">' +
              UI.icone("poubelle") + "Supprimer le produit</button>"
          : "") +
      "</div>";

    brancherPhotos(vue);
    brancherVideo(vue);

    /* Un produit sur commande n'a pas de stock : le champ disparaît. */
    const surCommande = UI.$("#p-sur-commande");
    const zoneStock = UI.$("#p-zone-stock");
    const majZoneStock = () => { zoneStock.hidden = surCommande.checked; };
    surCommande.addEventListener("change", majZoneStock);
    majZoneStock();

    UI.$("#p-categorie").addEventListener("change", (ev) => {
      UI.$("#p-souscategorie").innerHTML = optionsSousCategories(categories, ev.target.value, "");
    });

    /* ---------- Prix grossiste → prix public ----------
       Les trois champs se répondent : toucher au prix d'achat ou au taux
       recalcule le prix public ; corriger le prix public à la main
       recalcule le taux. Le bandeau du dessous dit le bénéfice. */

    const champGrossiste = UI.$("#p-grossiste");
    const champTaux = UI.$("#p-taux");
    const champPrix = UI.$("#p-prix");
    const zoneMarge = UI.$("#p-marge");
    const devise = Store.lireReglages().devise;

    const lireGrossiste = () => Math.max(0, Math.round(Utils.lireNombre(champGrossiste.value) || 0));
    const lirePrix = () => Math.max(0, Math.round(Utils.lireNombre(champPrix.value) || 0));

    function direMarge() {
      const achat = lireGrossiste();
      const vente = lirePrix();
      if (!achat) {
        zoneMarge.innerHTML = '<div class="aide" style="margin:-6px 0 14px">Sans prix grossiste, ' +
          "le prix public est celui que vous tapez.</div>";
        return;
      }
      const benefice = vente - achat;
      const taux = Store.tauxDepuisPrix(achat, vente);
      zoneMarge.innerHTML =
        '<div class="note-marge' + (benefice < 0 ? " note-marge-perte" : "") + '">' +
          UI.icone(benefice < 0 ? "alerte" : "promo", "ic-sm") +
          "<span>" + (benefice < 0
            ? "Vente à perte : " + Utils.echapper(Utils.fmtMontant(benefice, devise)) + " par pièce."
            : "Bénéfice : <strong>" + Utils.echapper(Utils.fmtMontant(benefice, devise)) +
              "</strong> par pièce (" + Utils.echapper(Utils.fmtTaux(taux)) + " %).") +
          "</span>" +
        "</div>";
    }

    /** Le prix public découle du prix d'achat et du taux. */
    function recalculerPrix() {
      const achat = lireGrossiste();
      if (!achat) return direMarge();
      const taux = Store.lireTaux(champTaux.value);
      champPrix.value = Utils.fmtNombre(Store.prixPublic(achat, taux));
      direMarge();
    }

    /** …et le taux découle du prix public quand on l'arrondit à la main. */
    function recalculerTaux() {
      const achat = lireGrossiste();
      if (!achat) return direMarge();
      const taux = Store.tauxDepuisPrix(achat, lirePrix());
      if (taux !== null) champTaux.value = Utils.fmtTaux(taux);
      direMarge();
    }

    champGrossiste.addEventListener("input", Utils.tempo(recalculerPrix, 350));
    champTaux.addEventListener("input", Utils.tempo(recalculerPrix, 350));
    champPrix.addEventListener("input", Utils.tempo(recalculerTaux, 500));
    direMarge();

    UI.$("#p-enregistrer").onclick = async () => {
      try {
        const produit = await Store.sauverProduit({
          id: existant ? existant.id : null,
          nom: UI.$("#p-nom").value,
          reference: UI.$("#p-reference").value,
          description: UI.$("#p-description").value,
          prixGrossiste: champGrossiste.value,
          tauxMarge: champTaux.value,
          prix: champPrix.value,
          ancienPrix: UI.$("#p-ancien").value.trim(),
          categorieId: UI.$("#p-categorie").value,
          sousCategorieId: UI.$("#p-souscategorie").value,
          stock: UI.$("#p-stock").value,
          surCommande: UI.$("#p-sur-commande").checked,
          /* Sans l'interrupteur à l'écran (modérateur), la mise en avant ne bouge pas. */
          enAvant: UI.$("#p-avant") ? UI.$("#p-avant").checked : (existant ? !!existant.enAvant : false),
          video: videoTravail,
        }, photosTravail);
        UI.toast(existant ? "Produit modifié" : "Produit ajouté", "ok");
        location.hash = "#/produit/" + produit.id;
      } catch (err) {
        UI.toast(err.message || "Enregistrement impossible", "err");
      }
    };

    const btnSupprimer = UI.$("#p-supprimer");
    if (btnSupprimer) {
      btnSupprimer.onclick = async () => {
        const ok = await UI.confirmer({
          titre: "Supprimer ce produit ?",
          texte: "« " + existant.nom + " » et ses photos seront retirés du catalogue. " +
            "La suppression sera visible en ligne à la prochaine publication.",
          bouton: "Supprimer",
          danger: true,
        });
        if (!ok) return;
        await Store.supprimerProduit(existant.id);
        UI.toast("Produit supprimé");
        location.hash = "#/produits";
      };
    }
  }

  /* =====================================================
     Fiche produit
     ===================================================== */

  async function detail(vue, id) {
    const p = await Store.lireProduit(id);
    if (!p) {
      UI.entete({ titre: "Produit", retour: true });
      vue.innerHTML = UI.vide("alerte", "Produit introuvable",
        "Il a peut-être été supprimé.",
        '<a class="btn btn-clair" href="#/produits">Voir les produits</a>');
      return;
    }

    const [photos, categories] = await Promise.all([
      Store.photosDeProduit(p.id), Store.listerCategories(),
    ]);
    const categorie = categories.find((c) => c.id === p.categorieId);
    const sousCategorie = categorie && (categorie.sousCategories || []).find((s) => s.id === p.sousCategorieId);
    const devise = Store.lireReglages().devise;
    const remise = Utils.remisePourcent(p.ancienPrix, p.prix);
    /* Sans le droit de modification, la fiche reste consultable mais
       tous les chemins qui mènent au formulaire disparaissent. */
    const peutModifier = Supabase.peutModifierProduits();

    UI.entete({ titre: p.nom, retour: true, actions: peutModifier
      ? '<a class="btn-ic" href="#/produit/' + Utils.echapper(p.id) + '/modifier" aria-label="Modifier">' +
        UI.icone("crayon") + "</a>"
      : "" });

    let html = "";

    if (photos.length) {
      html += '<div class="photos-bande">' +
        photos.map((photo, i) =>
          '<img src="' + photo.apercu + '" alt="Photo ' + (i + 1) +
          '" data-photo="' + i + '" class="photos-bande-img">').join("") +
      "</div>";
    } else {
      html += '<div class="carte photo-absente">' + UI.icone("image") +
        "<span>Aucune photo — les produits avec photo attirent bien plus de clients.</span></div>";
    }

    html +=
      '<div class="carte">' +
        '<div class="fiche-badges">' + UI.badgesProduit(p) + "</div>" +
        '<h2 class="fiche-nom">' + Utils.echapper(p.nom) + "</h2>" +
        '<div class="prix prix-grand">' +
          '<span class="prix-actuel">' + Utils.echapper(Utils.fmtMontant(p.prix, devise)) + "</span>" +
          (remise !== null ? '<s class="prix-ancien">' + Utils.echapper(Utils.fmtMontant(p.ancienPrix, devise)) + "</s>" : "") +
        "</div>" +
        '<div class="aide" style="margin-top:6px">' +
          (p.reference ? "Réf : " + Utils.echapper(p.reference) + " · " : "") +
          Utils.echapper(categorie ? categorie.nom + (sousCategorie ? " · " + sousCategorie.nom : "") : "Sans catégorie") +
          " — modifié le " + Utils.echapper(Utils.fmtDate(p.modifieLe)) +
        "</div>" +
      "</div>";

    /* Le détail des prix ne sort jamais de l'application admin. */
    if (p.prixGrossiste) {
      const benefice = p.prix - p.prixGrossiste;
      const tauxReel = Store.tauxDepuisPrix(p.prixGrossiste, p.prix);
      html +=
        '<div class="carte">' +
          '<div class="carte-titre">' + UI.icone("promo", "ic-sm") + " Marge " +
            '<span class="aide-inline">(visible ici seulement)</span></div>' +
          '<div class="marge-grille">' +
            "<div><span>Prix grossiste</span><strong>" +
              Utils.echapper(Utils.fmtMontant(p.prixGrossiste, devise)) + "</strong></div>" +
            "<div><span>Prix public</span><strong>" +
              Utils.echapper(Utils.fmtMontant(p.prix, devise)) + "</strong></div>" +
            "<div><span>Taux appliqué</span><strong>" +
              Utils.echapper(Utils.fmtTaux(tauxReel)) + " %</strong></div>" +
            '<div><span>Bénéfice à la pièce</span><strong' +
              (benefice < 0 ? ' class="marge-perte"' : "") + ">" +
              Utils.echapper(Utils.fmtMontant(benefice, devise)) + "</strong></div>" +
          "</div>" +
          (p.stock > 0
            ? '<div class="aide" style="margin:12px 0 0">Sur les ' + p.stock +
              " pièce" + (p.stock > 1 ? "s" : "") + " en boutique : <strong>" +
              Utils.echapper(Utils.fmtMontant(benefice * p.stock, devise)) +
              "</strong> de bénéfice à venir.</div>"
            : "") +
        "</div>";
    }

    if (p.videoUrl) {
      html += '<div class="carte"><div class="carte-titre">' + UI.icone("video", "ic-sm") +
        " Vidéo de présentation</div>" +
        '<video class="video-lecture" src="' + Utils.echapper(p.videoUrl) +
        '" controls preload="metadata" playsinline></video></div>';
    }

    if (p.description) {
      html += '<div class="carte"><div class="carte-titre">Description</div>' +
        '<div class="fiche-description">' +
          p.description.split(/\n+/).filter((l) => l.trim()).map((l) => "<p>" + Utils.echapper(l.trim()) + "</p>").join("") +
        "</div></div>";
    }

    /* Le slider de l'application client se compose côté administrateur. */
    const admin = Supabase.estAdmin();
    html += peutModifier
      ? '<div class="carte">' +
          '<div class="carte-titre">Actions rapides</div>' +
          '<div class="btn-rangee">' +
            (admin
              ? '<button type="button" class="btn' + (p.enAvant ? " btn-clair" : "") + '" id="p-basculer-avant">' +
                UI.icone(p.enAvant ? "fermer" : "etoile") +
                (p.enAvant ? "Retirer du slider" : "Mettre en avant (slider)") + "</button>"
              : "") +
            '<button type="button" class="btn btn-clair" id="p-modifier-stock">' +
              UI.icone("boite") + "Modifier la disponibilité</button>" +
            '<a class="btn btn-clair" href="#/produit/' + Utils.echapper(p.id) + '/modifier">' +
              UI.icone("crayon") + "Modifier le produit</a>" +
          "</div>" +
        "</div>"
      : '<div class="carte">' +
          '<div class="carte-titre">' + UI.icone("cle", "ic-sm") + " Lecture seule</div>" +
          '<p class="aide" style="margin:0">Votre compte ajoute des produits mais ne modifie pas ' +
            "ceux du catalogue. Demandez ce droit à l'administrateur.</p>" +
        "</div>";

    vue.innerHTML = html;

    const serie = photos.map((photo) => ({ src: photo.apercu }));
    for (const img of UI.$$("[data-photo]", vue)) {
      img.addEventListener("click", () => UI.ouvrirVisionneuse(serie, Number(img.dataset.photo)));
    }

    if (!peutModifier) return;

    if (admin) {
      UI.$("#p-basculer-avant").onclick = async () => {
        try {
          const maj = await Store.basculerEnAvant(p.id);
          UI.toast(maj.enAvant ? "Ajouté au slider client" : "Retiré du slider", "ok");
          detail(vue, p.id);
        } catch (err) {
          UI.toast(err.message, "err");
        }
      };
    }

    UI.$("#p-modifier-stock").onclick = () => feuilleStock(p, () => detail(vue, p.id));
  }

  return { liste, formulaire, detail };
})();
