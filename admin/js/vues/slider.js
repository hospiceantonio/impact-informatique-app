/* =========================================================
   Slider — ce qui défile en haut de l'application client.

   Deux sources, l'une après l'autre :
     1. les images libres, choisies une par une (affiches,
        promotions, arrivages) ;
     2. les produits mis en avant, avec leur photo et leur prix.
   ========================================================= */
const VueSlider = (() => {

  /** Image en cours d'édition : { chemin? , dataUrl?, apercu } */
  let imageTravail = null;

  function htmlVignette(slide, i, total) {
    return (
      '<div class="carte slide-bloc' + (slide.actif ? "" : " slide-eteint") + '">' +
        '<div class="slide-apercu">' +
          '<img src="' + Utils.echapper(slide.apercu) + '" alt="Image ' + (i + 1) + '">' +
          (slide.actif ? "" : '<span class="slide-etiquette">Masquée</span>') +
        "</div>" +
        '<div class="slide-pied">' +
          '<span class="slide-texte">' +
            '<span class="slide-titre">' +
              Utils.echapper(slide.titre || "Sans légende") + "</span>" +
            '<span class="slide-lien">' + Utils.echapper(slide.nomProduit || "Aucun lien") + "</span>" +
          "</span>" +
          '<span class="avant-actions">' +
            '<button type="button" class="btn-ic btn-ic-clair" data-monter="' + Utils.echapper(slide.id) + '"' +
              (i === 0 ? " disabled" : "") + ' aria-label="Monter">' + UI.icone("haut", "ic-sm") + "</button>" +
            '<button type="button" class="btn-ic btn-ic-clair" data-descendre="' + Utils.echapper(slide.id) + '"' +
              (i === total - 1 ? " disabled" : "") + ' aria-label="Descendre">' + UI.icone("bas", "ic-sm") + "</button>" +
            '<button type="button" class="btn-ic btn-ic-clair" data-modifier="' + Utils.echapper(slide.id) + '" aria-label="Modifier">' +
              UI.icone("crayon", "ic-sm") + "</button>" +
          "</span>" +
        "</div>" +
      "</div>"
    );
  }

  /** Un produit mis en avant, dans la seconde partie du slider. */
  function htmlProduit(p, i, total, decalage) {
    return (
      '<div class="avant-ligne">' +
        '<span class="avant-num">' + (decalage + i + 1) + "</span>" +
        UI.vignetteProduit(p) +
        '<button type="button" class="avant-nom" data-nav="#/produit/' + Utils.echapper(p.id) + '">' +
          Utils.echapper(p.nom) + "</button>" +
        '<span class="avant-actions">' +
          '<button type="button" class="btn-ic btn-ic-clair" data-avant-monter="' + Utils.echapper(p.id) + '"' +
            (i === 0 ? " disabled" : "") + ' aria-label="Monter">' + UI.icone("haut", "ic-sm") + "</button>" +
          '<button type="button" class="btn-ic btn-ic-clair" data-avant-descendre="' + Utils.echapper(p.id) + '"' +
            (i === total - 1 ? " disabled" : "") + ' aria-label="Descendre">' + UI.icone("bas", "ic-sm") + "</button>" +
          '<button type="button" class="btn-ic btn-ic-clair btn-ic-danger" data-avant-retirer="' + Utils.echapper(p.id) + '" aria-label="Retirer du slider">' +
            UI.icone("fermer", "ic-sm") + "</button>" +
        "</span>" +
      "</div>"
    );
  }

  async function afficher(vue) {
    UI.entete({ titre: "Slider", retour: true, sous: "Ce qui défile chez vos clients" });

    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>Lecture du slider…</div>';

    let slides, produits;
    try {
      [slides, produits] = await Promise.all([Store.listerSlides(), Store.listerProduits()]);
    } catch (err) {
      vue.innerHTML =
        '<div class="carte"><div class="carte-titre">Slider indisponible</div>' +
        '<p class="aide" style="margin:0">' + Utils.echapper(err.message) +
        "<br>Si le slider vient d'être ajouté, exécutez le fichier supabase/schema.sql.</p></div>";
      return;
    }
    for (const s of slides) {
      const p = produits.find((x) => x.id === s.produitId);
      s.nomProduit = p ? "Renvoie vers " + p.nom : "";
    }
    const visibles = slides.filter((s) => s.actif);
    const enAvant = produits
      .filter((p) => p.enAvant)
      .sort((a, b) => (a.ordreAvant || 0) - (b.ordreAvant || 0));
    const total = visibles.length + enAvant.length;

    const compte = (n, mot) => n + " " + mot + (n > 1 ? "s" : "");

    vue.innerHTML =
      '<div class="carte carte-publier">' +
        '<div class="carte-titre">' + UI.icone("image", "ic-sm") + " " +
          (total ? compte(total, "écran") + " en haut de l'accueil" : "Rien ne défile pour l'instant") + "</div>" +
        '<p class="aide" style="margin:0">' +
          (total
            ? compte(visibles.length, "image") + " puis " + compte(enAvant.length, "produit") +
              " mis en avant, dans cet ordre."
            : "Ajoutez une image, ou mettez un produit en avant depuis sa fiche.") +
        "</p>" +
      "</div>" +

      /* ---------- 1. Les images libres ---------- */
      '<div class="titre-section">Images (' + visibles.length +
        (slides.length > visibles.length ? " visible" + (visibles.length > 1 ? "s" : "") +
          " sur " + slides.length : "") + "/" + Store.MAX_SLIDES + ")</div>" +
      (slides.length < Store.MAX_SLIDES
        ? '<button type="button" class="btn" id="slide-ajouter">' + UI.icone("plus") + "Ajouter une image</button>"
        : '<p class="aide" style="margin:0">Le maximum est atteint (' + Store.MAX_SLIDES +
          " images). Retirez-en une pour en ajouter une autre.</p>") +
      (slides.length
        ? slides.map((s, i) => htmlVignette(s, i, slides.length)).join("")
        : UI.vide("image", "Aucune image",
            "Vos affiches, promotions ou arrivages défileront ici, avant les produits.")) +

      /* ---------- 2. Les produits mis en avant ---------- */
      '<div class="titre-section">Produits mis en avant (' + enAvant.length + "/" + Store.MAX_EN_AVANT + ")</div>" +
      '<div class="carte">' +
        '<p class="aide" style="margin:0 0 12px">Ils défilent après vos images, avec leur photo et leur prix. ' +
          "Pour en ajouter un : ouvrez sa fiche puis « Mettre en avant ».</p>" +
        (enAvant.length
          ? enAvant.map((p, i) => htmlProduit(p, i, enAvant.length, visibles.length)).join("")
          : '<p class="aide" style="margin:0">Aucun produit mis en avant.</p>') +
      "</div>";

    const recharger = () => afficher(vue);
    const bouton = UI.$("#slide-ajouter", vue);
    if (bouton) bouton.onclick = () => formulaire(null, produits, recharger);
    for (const b of UI.$$("[data-monter]", vue)) {
      b.onclick = async () => { await Store.deplacerSlide(b.dataset.monter, -1); recharger(); };
    }
    for (const b of UI.$$("[data-descendre]", vue)) {
      b.onclick = async () => { await Store.deplacerSlide(b.dataset.descendre, +1); recharger(); };
    }
    for (const b of UI.$$("[data-modifier]", vue)) {
      b.onclick = () => {
        const slide = slides.find((s) => s.id === b.dataset.modifier);
        if (slide) formulaire(slide, produits, recharger);
      };
    }
    for (const b of UI.$$("[data-avant-monter]", vue)) {
      b.onclick = async () => { await Store.deplacerEnAvant(b.dataset.avantMonter, -1); recharger(); };
    }
    for (const b of UI.$$("[data-avant-descendre]", vue)) {
      b.onclick = async () => { await Store.deplacerEnAvant(b.dataset.avantDescendre, +1); recharger(); };
    }
    for (const b of UI.$$("[data-avant-retirer]", vue)) {
      b.onclick = async () => {
        await Store.basculerEnAvant(b.dataset.avantRetirer);
        UI.toast("Produit retiré du slider", "ok");
        recharger();
      };
    }
  }

  /* ---------- Feuille de création / modification ---------- */

  function htmlImage() {
    if (imageTravail) {
      return (
        '<div class="photo-boite">' +
          '<img src="' + imageTravail.apercu + '" alt="Image du slider" data-agrandir="0">' +
          '<button type="button" class="photo-retirer" data-retirer="1" aria-label="Retirer l\'image">' +
            UI.icone("fermer", "ic-sm") + "</button>" +
        "</div>"
      );
    }
    return (
      '<label class="photo-ajout">' +
        UI.icone("camera") + "<span>Choisir</span>" +
        '<input type="file" accept="image/*" hidden id="slide-fichier">' +
      "</label>"
    );
  }

  function brancherImage(corps) {
    const zone = UI.$("#slide-image", corps);
    const rafraichir = () => { zone.innerHTML = htmlImage(); brancher(); };

    const brancher = () => {
      const champ = UI.$("#slide-fichier", zone);
      if (champ) {
        champ.addEventListener("change", async () => {
          const fichier = (champ.files || [])[0];
          if (!fichier) return;
          try {
            /* Une affiche mérite plus de finesse qu'une vignette de produit. */
            const { dataUrl } = await Utils.compresserImage(fichier, 1600, 0.82);
            imageTravail = { dataUrl, apercu: dataUrl };
          } catch (err) {
            UI.toast(err.message || "Image illisible", "err");
          }
          rafraichir();
        });
      }
      const retirer = UI.$("[data-retirer]", zone);
      if (retirer) retirer.onclick = () => { imageTravail = null; rafraichir(); };
      const agrandir = UI.$("[data-agrandir]", zone);
      if (agrandir) {
        agrandir.onclick = () => UI.ouvrirVisionneuse([{ src: imageTravail.apercu }], 0);
      }
    };

    rafraichir();
  }

  function formulaire(slide, produits, auTermine) {
    imageTravail = slide && slide.apercu
      ? { chemin: slide.chemin, apercu: slide.apercu }
      : null;

    const corps = UI.ouvrirFeuille(slide ? "Image du slider" : "Nouvelle image",
      '<div class="champ">' +
        "<label>Image <span class=\"obligatoire\">*</span></label>" +
        '<div class="photos-zone" id="slide-image"></div>' +
        '<div class="aide">Format paysage de préférence (16/10) : une affiche, une promotion, un arrivage.</div>' +
      "</div>" +
      UI.champTexte({ id: "slide-titre", label: "Légende (facultatif)",
        valeur: slide ? slide.titre : "",
        placeholder: "Rentrée scolaire : -20 % sur les clés USB",
        aide: "Posée en bas de l'image. Laissez vide si votre image dit déjà tout." }) +
      '<div class="champ">' +
        '<label for="slide-produit">Renvoyer vers un produit (facultatif)</label>' +
        '<select id="slide-produit">' +
          '<option value="">Aucun — l\'image ne fait rien</option>' +
          produits.map((p) =>
            '<option value="' + Utils.echapper(p.id) + '"' +
            (slide && slide.produitId === p.id ? " selected" : "") + ">" +
            Utils.echapper(p.nom) + "</option>").join("") +
        "</select>" +
        '<div class="aide">Le client touche l\'image et arrive sur la fiche du produit.</div>' +
      "</div>" +
      UI.interrupteur({ id: "slide-actif", label: "Visible dans le slider",
        actif: !slide || slide.actif,
        aide: "Désactivée, l'image reste ici mais ne défile plus chez les clients." }) +
      '<div class="btn-rangee" style="margin-top:18px">' +
        '<button type="button" class="btn" id="slide-enregistrer">' + UI.icone("check") +
          (slide ? "Enregistrer" : "Ajouter au slider") + "</button>" +
        (slide
          ? '<button type="button" class="btn btn-clair btn-danger-clair" id="slide-supprimer">' +
              UI.icone("poubelle") + "Retirer</button>"
          : "") +
      "</div>");

    brancherImage(corps);

    UI.$("#slide-enregistrer", corps).onclick = async () => {
      const bouton = UI.$("#slide-enregistrer", corps);
      bouton.disabled = true;
      try {
        await Store.sauverSlide({
          id: slide ? slide.id : null,
          image: imageTravail || {},
          titre: UI.$("#slide-titre", corps).value,
          produitId: UI.$("#slide-produit", corps).value,
          actif: UI.$("#slide-actif", corps).checked,
        });
        UI.fermerFeuille();
        UI.toast(slide ? "Image enregistrée" : "Image ajoutée au slider", "ok");
        auTermine();
      } catch (err) {
        UI.toast(err.message, "err");
        bouton.disabled = false;
      }
    };

    const supprimer = UI.$("#slide-supprimer", corps);
    if (supprimer) {
      supprimer.onclick = async () => {
        UI.feuilleSansRappel();
        UI.fermerFeuille();
        const ok = await UI.confirmer({
          titre: "Retirer cette image ?",
          texte: "Elle disparaîtra du slider de l'application client.",
          bouton: "Retirer", danger: true,
        });
        if (!ok) return;
        try {
          await Store.supprimerSlide(slide.id);
          UI.toast("Image retirée du slider", "ok");
          auTermine();
        } catch (err) {
          UI.toast(err.message, "err");
        }
      };
    }
  }

  return { afficher };
})();
