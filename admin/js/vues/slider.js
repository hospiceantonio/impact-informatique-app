/* =========================================================
   Slider — ce qui défile en haut de l'application client.

   Deux sliders sans rapport l'un avec l'autre :
     - celui de l'enseigne BIZZOO, composé dans ses réglages,
       qui défile sur l'accueil de l'application client ;
     - celui d'une boutique, qui défile sur son écran à elle,
       suivi de ses produits mis en avant.
   Rien ne remonte plus d'une boutique vers l'accueil.

   Chaque écran est une photo OU une vidéo, et peut renvoyer
   vers un produit.

   Le même gestionnaire sert les deux : l'écran Slider de la
   boutique l'affiche en pleine page, les réglages de BIZZOO
   le posent dans une carte.
   ========================================================= */
const VueSlider = (() => {

  /**
   * Média en cours d'édition :
   *   { type:"photo", chemin?, dataUrl?, apercu }
   *   { type:"video", chemin?, fichier?, url, taille? }
   */
  let mediaTravail = null;

  const compte = (n, mot) => n + " " + mot + (n > 1 ? "s" : "");

  /* ---------- Vignettes ---------- */

  function htmlApercuMedia(slide) {
    return slide.estVideo
      ? '<video src="' + Utils.echapper(slide.videoUrl) + '" muted playsinline ' +
          'preload="metadata"></video>' +
        '<span class="slide-marque-video">' + UI.icone("video", "ic-sm") + "Vidéo</span>"
      : '<img src="' + Utils.echapper(slide.apercu) + '" alt="">';
  }

  function htmlVignette(slide, i, total) {
    return (
      '<div class="carte slide-bloc' + (slide.actif ? "" : " slide-eteint") + '">' +
        '<div class="slide-apercu">' +
          htmlApercuMedia(slide) +
          (slide.actif ? "" : '<span class="slide-etiquette">Masqué</span>') +
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

  /** Un produit mis en avant, dans la seconde partie du slider d'une boutique. */
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

  /* ---------- Le gestionnaire, posé où on veut ----------
     `cible` vaut :
       "enseigne"  — le slider en haut de l'accueil de l'application ;
       "publicite" — ce que BIZZOO met en avant plus bas sur l'accueil ;
       "boutique"  — le slider d'une boutique, sur son écran à elle.
     Les deux premiers sont au superadministrateur ; le troisième à
     l'administrateur de la boutique. */

  async function rendre(conteneur, cible, options) {
    const opts = options || {};
    const pub = cible === "publicite";
    /* Ce qui appartient à l'enseigne pioche dans TOUTES les boutiques. */
    const enseigne = cible === "enseigne" || pub;
    /* Les produits mis en avant ne défilent que dans le slider d'une
       boutique : l'accueil de l'application ne montre plus qu'eux. */
    const avecEnAvant = !enseigne;
    const mot = pub ? "annonce" : "écran";

    conteneur.innerHTML =
      '<div class="chargement"><span class="chargement-rond"></span>Lecture de la ' +
      (pub ? "publicité" : "vitrine") + "…</div>";

    let slides, produits;
    try {
      [slides, produits] = await Promise.all([
        Store.listerSlides(cible),
        Store.listerProduits(enseigne ? { toutesBoutiques: true } : undefined),
      ]);
    } catch (err) {
      conteneur.innerHTML =
        '<div class="carte"><div class="carte-titre">' +
          (pub ? "Publicité indisponible" : "Slider indisponible") + "</div>" +
        '<p class="aide" style="margin:0">' + Utils.echapper(err.message) +
        "<br>Si la base vient de changer, exécutez le fichier supabase/schema.sql.</p></div>";
      return;
    }
    for (const s of slides) {
      const p = produits.find((x) => x.id === s.produitId);
      s.nomProduit = p ? "Renvoie vers " + p.nom : "";
    }
    const visibles = slides.filter((s) => s.actif);
    const enAvant = avecEnAvant
      ? produits.filter((p) => p.enAvant).sort((a, b) => (a.ordreAvant || 0) - (b.ordreAvant || 0))
      : [];
    const total = visibles.length + enAvant.length;
    const plein = slides.length >= Store.MAX_SLIDES;

    const resume = pub
      ? (total
          ? compte(total, "annonce") + " sur l'accueil de BIZZOO"
          : "Aucune annonce pour l'instant")
      : enseigne
        ? (total
            ? compte(total, "écran") + " défile" + (total > 1 ? "nt" : "") + " sur l'accueil"
            : "Rien ne défile sur l'accueil")
        : (total
            ? compte(total, "écran") + " en haut de la boutique"
            : "Rien ne défile pour l'instant");
    const detail = pub
      ? (total
          ? "Vos annonces, dans cet ordre, sous les boutiques sur l'accueil. Chacune peut " +
            "renvoyer vers un produit de n'importe quelle boutique."
          : "Ajoutez une affiche — photo ou vidéo — et renvoyez-la, si vous voulez, vers un " +
            "produit de n'importe quelle boutique.")
      : enseigne
        ? (total
            ? "Vos photos et vidéos, dans cet ordre. Elles seules occupent le haut de " +
              "l'accueil : les boutiques n'y envoient plus rien."
            : "Ajoutez une photo ou une vidéo : c'est la première chose que voient vos clients.")
        : (total
            ? compte(visibles.length, "écran") + " puis " + compte(enAvant.length, "produit") +
              " mis en avant, dans cet ordre."
            : "Ajoutez une photo ou une vidéo, ou mettez un produit en avant depuis sa fiche.");

    conteneur.innerHTML =
      (opts.sansResume
        ? '<p class="aide" style="margin:0 0 12px">' + detail + "</p>"
        : '<div class="carte carte-publier">' +
            '<div class="carte-titre">' + UI.icone("image", "ic-sm") + " " + resume + "</div>" +
            '<p class="aide" style="margin:0">' + detail + "</p>" +
          "</div>") +

      /* ---------- 1. Les écrans composés à la main ---------- */
      (opts.sansResume
        ? ""
        : '<div class="titre-section">' + (pub ? "Annonces" : "Photos et vidéos") + " (" + visibles.length +
            (slides.length > visibles.length
              ? " visible" + (visibles.length > 1 ? "s" : "") + " sur " + slides.length
              : "") + "/" + Store.MAX_SLIDES + ")</div>") +
      (plein
        ? '<p class="aide" style="margin:0 0 10px">Le maximum est atteint (' + Store.MAX_SLIDES +
          " " + mot + "s). Retirez-en un" + (pub ? "e" : "") + " pour en ajouter un" +
          (pub ? "e" : "") + " autre.</p>"
        : '<div class="btn-rangee" style="margin-bottom:4px">' +
            '<button type="button" class="btn" id="slide-ajout-photo">' +
              UI.icone("camera") + "Ajouter une photo</button>" +
            '<button type="button" class="btn btn-clair" id="slide-ajout-video">' +
              UI.icone("video") + "Ajouter une vidéo</button>" +
          "</div>") +
      (slides.length
        ? slides.map((s, i) => htmlVignette(s, i, slides.length)).join("")
        : UI.vide("image", pub ? "Aucune annonce" : "Aucun écran",
            pub
              ? "Vos affiches et les produits que vous mettez en avant s'afficheront ici, sur " +
                "l'accueil de BIZZOO."
              : enseigne
                ? "Vos affiches, promotions et vidéos défileront ici, en haut de l'accueil."
                : "Vos affiches et vidéos défileront ici, avant les produits mis en avant.")) +

      /* ---------- 2. Les produits mis en avant (boutique seulement) ---------- */
      (avecEnAvant
        ? '<div class="titre-section">Produits mis en avant (' + enAvant.length + "/" +
            Store.MAX_EN_AVANT + ")</div>" +
          '<div class="carte">' +
            '<p class="aide" style="margin:0 0 12px">Ils défilent après vos écrans, avec leur photo ' +
              "et leur prix, sur l'écran de cette boutique. Pour en ajouter un : ouvrez sa fiche " +
              "puis « Mettre en avant ».</p>" +
            (enAvant.length
              ? enAvant.map((p, i) => htmlProduit(p, i, enAvant.length, visibles.length)).join("")
              : '<p class="aide" style="margin:0">Aucun produit mis en avant.</p>') +
          "</div>"
        : "");

    const recharger = () => rendre(conteneur, cible, options);
    const ajouter = (type) => formulaire(null, produits, cible, recharger, type);
    const photo = UI.$("#slide-ajout-photo", conteneur);
    if (photo) photo.onclick = () => ajouter("photo");
    const video = UI.$("#slide-ajout-video", conteneur);
    if (video) video.onclick = () => ajouter("video");

    for (const b of UI.$$("[data-monter]", conteneur)) {
      b.onclick = async () => { await Store.deplacerSlide(b.dataset.monter, -1, cible); recharger(); };
    }
    for (const b of UI.$$("[data-descendre]", conteneur)) {
      b.onclick = async () => { await Store.deplacerSlide(b.dataset.descendre, +1, cible); recharger(); };
    }
    for (const b of UI.$$("[data-modifier]", conteneur)) {
      b.onclick = () => {
        const slide = slides.find((s) => s.id === b.dataset.modifier);
        if (slide) formulaire(slide, produits, cible, recharger);
      };
    }
    for (const b of UI.$$("[data-avant-monter]", conteneur)) {
      b.onclick = async () => { await Store.deplacerEnAvant(b.dataset.avantMonter, -1); recharger(); };
    }
    for (const b of UI.$$("[data-avant-descendre]", conteneur)) {
      b.onclick = async () => { await Store.deplacerEnAvant(b.dataset.avantDescendre, +1); recharger(); };
    }
    for (const b of UI.$$("[data-avant-retirer]", conteneur)) {
      b.onclick = async () => {
        await Store.basculerEnAvant(b.dataset.avantRetirer);
        UI.toast("Produit retiré du slider", "ok");
        recharger();
      };
    }
  }

  /* ---------- L'écran Slider d'une boutique ---------- */

  async function afficher(vue) {
    UI.entete({ titre: "Slider", retour: true, sous: "Ce qui défile dans cette boutique" });
    await rendre(vue, "boutique");
  }

  /* ---------- Feuille de création / modification ---------- */

  function htmlMedia() {
    if (mediaTravail && mediaTravail.type === "video") {
      return (
        '<div class="video-boite">' +
          '<video src="' + Utils.echapper(mediaTravail.url) + '" controls preload="metadata" playsinline></video>' +
          '<div class="video-pied">' +
            "<span>" + (mediaTravail.taille
              ? "Nouvelle vidéo · " + Utils.echapper(Utils.tailleLisible(mediaTravail.taille))
              : "Vidéo en ligne") + "</span>" +
            '<button type="button" class="btn-ic btn-ic-clair btn-ic-danger" data-retirer="1" ' +
              'aria-label="Retirer la vidéo">' + UI.icone("poubelle", "ic-sm") + "</button>" +
          "</div>" +
        "</div>"
      );
    }
    if (mediaTravail) {
      return (
        '<div class="photo-boite">' +
          '<img src="' + mediaTravail.apercu + '" alt="Photo du slider" data-agrandir="0">' +
          '<button type="button" class="photo-retirer" data-retirer="1" aria-label="Retirer la photo">' +
            UI.icone("fermer", "ic-sm") + "</button>" +
        "</div>"
      );
    }
    return (
      '<div class="media-choix">' +
        '<label class="photo-ajout">' +
          UI.icone("camera") + "<span>Une photo</span>" +
          '<input type="file" accept="image/*" hidden id="slide-fichier">' +
        "</label>" +
        '<label class="photo-ajout">' +
          UI.icone("video") + "<span>Une vidéo</span>" +
          '<small>' + Store.MAX_VIDEO_MO + " Mo maximum</small>" +
          '<input type="file" accept="video/*" hidden id="slide-video">' +
        "</label>" +
      "</div>"
    );
  }

  function brancherMedia(corps) {
    const zone = UI.$("#slide-media", corps);
    const rafraichir = () => { zone.innerHTML = htmlMedia(); brancher(); };

    const brancher = () => {
      const champ = UI.$("#slide-fichier", zone);
      if (champ) {
        champ.addEventListener("change", async () => {
          const fichier = (champ.files || [])[0];
          if (!fichier) return;
          try {
            /* Une affiche mérite plus de finesse qu'une vignette de produit. */
            const { dataUrl } = await Utils.compresserImage(fichier, 1600, 0.82);
            mediaTravail = { type: "photo", dataUrl, apercu: dataUrl };
          } catch (err) {
            UI.toast(err.message || "Image illisible", "err");
          }
          rafraichir();
        });
      }
      const champVideo = UI.$("#slide-video", zone);
      if (champVideo) {
        champVideo.addEventListener("change", () => {
          const fichier = (champVideo.files || [])[0];
          if (!fichier) return;
          const octets = fichier.size || 0;
          if (octets > Store.MAX_VIDEO_MO * 1024 * 1024) {
            UI.toast("Vidéo trop lourde (" + Utils.tailleLisible(octets) + "). " +
              Store.MAX_VIDEO_MO + " Mo au maximum.", "err");
            champVideo.value = "";
            return;
          }
          /* CE QUE LE FICHIER COÛTERA À VOS CLIENTS. La vidéo n'est pas
             gardée hors connexion : chacun la retélécharge. On le dit
             ICI, au moment où l'on peut encore choisir une autre prise
             — et on laisse passer, parce qu'une vidéo lourde peut avoir
             une raison que l'application ne connaît pas. */
          if (octets > Store.ALERTE_VIDEO_MO * 1024 * 1024) {
            UI.toast("Vidéo de " + Utils.tailleLisible(octets) + " : chaque client " +
              "la téléchargera sur son forfait. Au-delà de " +
              Store.ALERTE_VIDEO_MO + " Mo, beaucoup ne la regarderont pas. " +
              "Elle passe quand même.", "alerte");
          }
          mediaTravail = {
            type: "video", fichier, taille: octets, url: URL.createObjectURL(fichier),
          };
          rafraichir();
        });
      }
      const retirer = UI.$("[data-retirer]", zone);
      if (retirer) retirer.onclick = () => { mediaTravail = null; rafraichir(); };
      const agrandir = UI.$("[data-agrandir]", zone);
      if (agrandir) {
        agrandir.onclick = () => UI.ouvrirVisionneuse([{ src: mediaTravail.apercu }], 0);
      }
    };

    rafraichir();
  }

  function formulaire(slide, produits, cible, auTermine, typeDemande) {
    const enseigne = cible === "enseigne";
    mediaTravail = null;
    if (slide && slide.estVideo) {
      mediaTravail = { type: "video", chemin: slide.video, url: slide.videoUrl };
    } else if (slide && slide.apercu) {
      mediaTravail = { type: "photo", chemin: slide.chemin, apercu: slide.apercu };
    }

    const titreFeuille = slide
      ? (slide.estVideo ? "Vidéo du slider" : "Photo du slider")
      : (typeDemande === "video" ? "Nouvelle vidéo" : "Nouvelle photo");

    const corps = UI.ouvrirFeuille(titreFeuille,
      '<div class="champ">' +
        '<label>Photo ou vidéo <span class="obligatoire">*</span></label>' +
        '<div class="photos-zone" id="slide-media"></div>' +
        '<div class="aide">Format paysage de préférence (16/10). Une vidéo défile sans le son, ' +
          "et l'écran suivant attend qu'elle se termine.</div>" +
      "</div>" +
      UI.champTexte({ id: "slide-titre", label: "Légende (facultatif)",
        valeur: slide ? slide.titre : "",
        placeholder: "Rentrée scolaire : -20 % sur les clés USB",
        aide: "Posée en bas de l'écran. Laissez vide si votre image dit déjà tout." }) +
      '<div class="champ">' +
        '<label for="slide-produit">Renvoyer vers un produit (facultatif)</label>' +
        '<select id="slide-produit">' +
          '<option value="">Aucun — l\'écran ne fait rien</option>' +
          produits.map((p) =>
            '<option value="' + Utils.echapper(p.id) + '"' +
            (slide && slide.produitId === p.id ? " selected" : "") + ">" +
            Utils.echapper(p.nom) + "</option>").join("") +
        "</select>" +
        '<div class="aide">Le client touche l\'écran et arrive sur la fiche du produit.</div>' +
      "</div>" +
      UI.interrupteur({ id: "slide-actif", label: "Visible dans le slider",
        actif: !slide || slide.actif,
        aide: "Désactivé, l'écran reste ici mais ne défile plus chez les clients." }) +
      '<div class="btn-rangee" style="margin-top:18px">' +
        '<button type="button" class="btn" id="slide-enregistrer">' + UI.icone("check") +
          (slide ? "Enregistrer" : "Ajouter au slider") + "</button>" +
        (slide
          ? '<button type="button" class="btn btn-clair btn-danger-clair" id="slide-supprimer">' +
              UI.icone("poubelle") + "Retirer</button>"
          : "") +
      "</div>");

    brancherMedia(corps);
    /* Créer depuis « Ajouter une vidéo » : le sélecteur s'ouvre tout seul. */
    if (!slide && typeDemande === "video") {
      const champ = UI.$("#slide-video", corps);
      if (champ) champ.click();
    }

    UI.$("#slide-enregistrer", corps).onclick = async () => {
      const bouton = UI.$("#slide-enregistrer", corps);
      bouton.disabled = true;
      try {
        await Store.sauverSlide({
          id: slide ? slide.id : null,
          media: mediaTravail || {},
          titre: UI.$("#slide-titre", corps).value,
          produitId: UI.$("#slide-produit", corps).value,
          actif: UI.$("#slide-actif", corps).checked,
        }, cible);
        UI.fermerFeuille();
        UI.toast(slide ? "Écran enregistré" : "Écran ajouté au slider" +
          (enseigne ? " de BIZZOO" : ""), "ok");
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
          titre: slide.estVideo ? "Retirer cette vidéo ?" : "Retirer cette photo ?",
          texte: "Elle disparaîtra du slider de l'application client.",
          bouton: "Retirer", danger: true,
        });
        if (!ok) return;
        try {
          await Store.supprimerSlide(slide.id, cible);
          UI.toast("Écran retiré du slider", "ok");
          auTermine();
        } catch (err) {
          UI.toast(err.message, "err");
        }
      };
    }
  }

  return { afficher, rendre };
})();
