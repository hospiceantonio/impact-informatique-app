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

      '<div class="carte">' +
        UI.champMontant({ id: "p-prix", label: "Prix de vente", valeur: existant ? existant.prix : "", obligatoire: true }) +
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
        UI.interrupteur({ id: "p-disponible", label: "Disponible en stock",
          actif: existant ? existant.disponible !== false : true,
          aide: "Désactivé : le produit reste visible avec la mention « Rupture »." }) +
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

    UI.$("#p-categorie").addEventListener("change", (ev) => {
      UI.$("#p-souscategorie").innerHTML = optionsSousCategories(categories, ev.target.value, "");
    });

    UI.$("#p-enregistrer").onclick = async () => {
      try {
        const produit = await Store.sauverProduit({
          id: existant ? existant.id : null,
          nom: UI.$("#p-nom").value,
          reference: UI.$("#p-reference").value,
          description: UI.$("#p-description").value,
          prix: UI.$("#p-prix").value,
          ancienPrix: UI.$("#p-ancien").value.trim(),
          categorieId: UI.$("#p-categorie").value,
          sousCategorieId: UI.$("#p-souscategorie").value,
          disponible: UI.$("#p-disponible").checked,
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

    UI.entete({ titre: p.nom, retour: true, actions:
      '<a class="btn-ic" href="#/produit/' + Utils.echapper(p.id) + '/modifier" aria-label="Modifier">' +
      UI.icone("crayon") + "</a>" });

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
        '<div class="fiche-badges">' + UI.badgesProduit(p) +
          (p.disponible !== false ? '<span class="badge badge-ok">' + UI.icone("check", "ic-sm") + "En stock</span>" : "") +
        "</div>" +
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

    html +=
      '<div class="carte">' +
        '<div class="carte-titre">Actions rapides</div>' +
        '<div class="btn-rangee">' +
          '<button type="button" class="btn btn-clair" id="p-basculer-stock">' +
            UI.icone("boite") + (p.disponible !== false ? "Marquer en rupture" : "Remettre en stock") + "</button>" +
          '<a class="btn btn-clair" href="#/produit/' + Utils.echapper(p.id) + '/modifier">' +
            UI.icone("crayon") + "Modifier le produit</a>" +
        "</div>" +
      "</div>";

    vue.innerHTML = html;

    const serie = photos.map((photo) => ({ src: photo.apercu }));
    for (const img of UI.$$("[data-photo]", vue)) {
      img.addEventListener("click", () => UI.ouvrirVisionneuse(serie, Number(img.dataset.photo)));
    }

    UI.$("#p-basculer-stock").onclick = async () => {
      try {
        await Store.basculerDisponible(p.id);
        UI.toast(p.disponible !== false ? "Produit marqué en rupture" : "Produit remis en stock", "ok");
        detail(vue, p.id);
      } catch (err) {
        UI.toast(err.message, "err");
      }
    };
  }

  return { liste, formulaire, detail };
})();
