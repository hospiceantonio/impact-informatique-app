/* =========================================================
   Réglages — boutique, compte du gérant, connexion à la
   base, sauvegarde et restauration.
   ========================================================= */
const VueReglages = (() => {

  /** Photos de la boutique en cours d'édition. */
  let photosTravail = [];

  /* =====================================================
     Autres numéros et autres adresses

     La boutique garde un numéro principal (celui des commandes
     WhatsApp) et une adresse principale ; ces listes-ci sont ce
     qui vient en plus, et se retrouvent dans l'onglet Infos de
     l'application client.
     ===================================================== */

  let telsTravail = [];
  let adressesTravail = [];

  function htmlTelephones() {
    if (!telsTravail.length) {
      return '<p class="aide" style="margin:0">Aucun autre numéro. Le numéro principal suffit à la boutique.</p>';
    }
    return telsTravail.map((t, i) =>
      '<div class="ligne-multi">' +
        '<div class="ligne-multi-champs">' +
          '<input type="text" data-tel-libelle="' + i + '" value="' + Utils.echapper(t.libelle || "") +
            '" placeholder="À quoi sert ce numéro ? (Atelier, SAV…)">' +
          '<input type="tel" data-tel-numero="' + i + '" value="' + Utils.echapper(t.numero || "") +
            '" placeholder="01 97 00 00 00">' +
          '<label class="ligne-multi-coche">' +
            '<input type="checkbox" data-tel-wa="' + i + '"' + (t.whatsapp ? " checked" : "") + ">" +
            "<span>Ce numéro est aussi sur WhatsApp</span>" +
          "</label>" +
        "</div>" +
        '<button type="button" class="btn-ic btn-ic-clair btn-ic-danger" data-tel-retirer="' + i +
          '" aria-label="Retirer ce numéro">' + UI.icone("fermer", "ic-sm") + "</button>" +
      "</div>"
    ).join("");
  }

  function htmlAdresses() {
    if (!adressesTravail.length) {
      return '<p class="aide" style="margin:0">Aucune autre adresse. Seule l\'adresse principale s\'affiche.</p>';
    }
    return adressesTravail.map((a, i) =>
      '<div class="ligne-multi">' +
        '<div class="ligne-multi-champs">' +
          '<input type="text" data-adr-libelle="' + i + '" value="' + Utils.echapper(a.libelle || "") +
            '" placeholder="Nom du lieu (Annexe Godomey, Dépôt…)">' +
          '<input type="text" data-adr-texte="' + i + '" value="' + Utils.echapper(a.texte || "") +
            '" placeholder="Quartier, rue, ville">' +
          '<div class="ligne-multi-duo">' +
            '<input type="text" data-adr-lat="' + i + '" value="' +
              Utils.echapper(a.latitude === null || a.latitude === undefined ? "" : a.latitude) +
              '" placeholder="Latitude (facultatif)">' +
            '<input type="text" data-adr-lng="' + i + '" value="' +
              Utils.echapper(a.longitude === null || a.longitude === undefined ? "" : a.longitude) +
              '" placeholder="Longitude">' +
          "</div>" +
          '<input type="text" data-adr-lien="' + i + '" value="" ' +
            'placeholder="…ou collez ici un lien Google Maps">' +
        "</div>" +
        '<button type="button" class="btn-ic btn-ic-clair btn-ic-danger" data-adr-retirer="' + i +
          '" aria-label="Retirer cette adresse">' + UI.icone("fermer", "ic-sm") + "</button>" +
      "</div>"
    ).join("");
  }

  /** Recopie ce qui est tapé à l'écran dans les listes de travail. */
  function lireTelephones(base) {
    for (const champ of UI.$$("[data-tel-libelle]", base)) {
      telsTravail[Number(champ.dataset.telLibelle)].libelle = champ.value;
    }
    for (const champ of UI.$$("[data-tel-numero]", base)) {
      telsTravail[Number(champ.dataset.telNumero)].numero = champ.value;
    }
    for (const champ of UI.$$("[data-tel-wa]", base)) {
      telsTravail[Number(champ.dataset.telWa)].whatsapp = champ.checked;
    }
  }

  function lireAdresses(base) {
    for (const champ of UI.$$("[data-adr-libelle]", base)) {
      adressesTravail[Number(champ.dataset.adrLibelle)].libelle = champ.value;
    }
    for (const champ of UI.$$("[data-adr-texte]", base)) {
      adressesTravail[Number(champ.dataset.adrTexte)].texte = champ.value;
    }
    for (const champ of UI.$$("[data-adr-lat]", base)) {
      adressesTravail[Number(champ.dataset.adrLat)].latitude = champ.value.trim();
    }
    for (const champ of UI.$$("[data-adr-lng]", base)) {
      adressesTravail[Number(champ.dataset.adrLng)].longitude = champ.value.trim();
    }
  }

  /** Vidéo en cours d'édition : { chemin, url } | { fichier, url, taille } | null */
  let videoTravail = null;

  function htmlVideoBoutique() {
    if (videoTravail) {
      return (
        '<div class="video-boite">' +
          '<video src="' + Utils.echapper(videoTravail.url) + '" controls preload="metadata" playsinline></video>' +
          '<div class="video-pied">' +
            "<span>" + (videoTravail.taille
              ? "Nouvelle vidéo · " + Utils.echapper(Utils.tailleLisible(videoTravail.taille))
              : "Vidéo en ligne") + "</span>" +
            '<button type="button" class="btn-ic btn-ic-clair btn-ic-danger" id="boutique-video-retirer" ' +
              'aria-label="Retirer la vidéo">' + UI.icone("poubelle", "ic-sm") + "</button>" +
          "</div>" +
        "</div>"
      );
    }
    return (
      '<label class="video-ajout">' + UI.icone("video") +
        "<span>Ajouter une vidéo</span>" +
        '<small>Facultatif · ' + Store.MAX_VIDEO_MO + ' Mo maximum</small>' +
        '<input type="file" accept="video/*" hidden id="boutique-video-fichier">' +
      "</label>"
    );
  }

  function brancherVideoBoutique(base) {
    const zone = UI.$("#boutique-video", base);
    if (!zone) return;

    const rafraichir = () => {
      zone.innerHTML = htmlVideoBoutique();
      brancher();
    };

    const brancher = () => {
      const champ = UI.$("#boutique-video-fichier", zone);
      if (champ) {
        champ.addEventListener("change", () => {
          const fichier = champ.files && champ.files[0];
          if (!fichier) return;
          if (fichier.size > Store.MAX_VIDEO_MO * 1024 * 1024) {
            UI.toast("Vidéo trop lourde (" + Utils.tailleLisible(fichier.size) + ") : " +
              Store.MAX_VIDEO_MO + " Mo au maximum.", "err");
            return;
          }
          if (videoTravail && videoTravail.taille && videoTravail.url) URL.revokeObjectURL(videoTravail.url);
          videoTravail = { fichier, url: URL.createObjectURL(fichier), taille: fichier.size };
          rafraichir();
        });
      }
      const retirer = UI.$("#boutique-video-retirer", zone);
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

  function htmlPhotosBoutique() {
    let html = photosTravail.map((photo, i) =>
      '<div class="photo-boite">' +
        '<img src="' + photo.apercu + '" alt="Photo ' + (i + 1) + '" data-agrandir="' + i + '">' +
        '<button type="button" class="photo-retirer" data-retirer="' + i + '" aria-label="Retirer la photo">' +
          UI.icone("fermer", "ic-sm") + "</button>" +
      "</div>"
    ).join("");
    if (photosTravail.length < Store.MAX_PHOTOS_BOUTIQUE) {
      html +=
        '<label class="photo-ajout">' +
          UI.icone("camera") + "<span>Ajouter</span>" +
          '<input type="file" accept="image/*" multiple hidden id="boutique-photo-fichier">' +
        "</label>";
    }
    return html;
  }

  function brancherPhotosBoutique(base) {
    const zone = UI.$("#boutique-photos", base);
    if (!zone) return;

    const rafraichir = () => {
      zone.innerHTML = htmlPhotosBoutique();
      brancher();
    };

    const brancher = () => {
      const champ = UI.$("#boutique-photo-fichier", zone);
      if (champ) {
        champ.addEventListener("change", async () => {
          const fichiers = Array.from(champ.files || [])
            .slice(0, Store.MAX_PHOTOS_BOUTIQUE - photosTravail.length);
          for (const fichier of fichiers) {
            try {
              const { dataUrl } = await Utils.compresserImage(fichier, 1400, 0.78);
              photosTravail.push({ id: Utils.uid("bou"), dataUrl, apercu: dataUrl });
            } catch (err) {
              UI.toast(err.message || "Photo illisible", "err");
            }
          }
          rafraichir();
        });
      }
      for (const b of UI.$$("[data-retirer]", zone)) {
        b.onclick = () => { photosTravail.splice(Number(b.dataset.retirer), 1); rafraichir(); };
      }
      for (const img of UI.$$("[data-agrandir]", zone)) {
        img.onclick = () => UI.ouvrirVisionneuse(
          photosTravail.map((photo) => ({ src: photo.apercu })), Number(img.dataset.agrandir));
      }
    };

    rafraichir();
  }

  /** Sur quoi portent les réglages affichés : l'enseigne ou une boutique. */
  let cible = "boutique";

  async function afficher(vue, params) {
    const boutiques = Store.listerBoutiques();
    const courante = Store.boutiqueCourante();
    /* Sans table des boutiques, il n'y a qu'un jeu de réglages. Et les
       coordonnées de l'enseigne ne regardent que le super administrateur. */
    if (!boutiques.length || !Supabase.estSuper()) cible = "boutique";
    const surEnseigne = cible === "enseigne";

    UI.entete({ titre: "Réglages",
      sous: boutiques.length
        ? (surEnseigne ? "L'enseigne BIZZOO" : (courante || {}).nomBoutique || "")
        : "Boutique, compte et sauvegarde" });

    const r = surEnseigne ? Store.lireEnseigne() : Store.lireReglages();
    const configEnDur = typeof CONFIG !== "undefined" && !!CONFIG.SUPABASE_URL;
    const configActuelle = Supabase.configuration() || { url: "", cle: "" };

    /* Enregistrer va dans la ligne de l'enseigne ou dans celle de la
       boutique ouverte, selon l'onglet choisi. */
    const enregistrer = (maj, libelle) =>
      (surEnseigne ? Store.majEnseigne(maj, libelle) : Store.majReglages(maj, libelle));

    vue.innerHTML =
      /* ---------- Enseigne ou boutique : de quoi parle-t-on ? ---------- */
      (boutiques.length && Supabase.estSuper()
        ? '<div class="carte">' +
            '<div class="carte-titre">' + UI.icone("magasin", "ic-sm") + " Régler quoi ?</div>" +
            '<p class="aide" style="margin:-4px 0 12px">BIZZOO réunit ' + boutiques.length +
              " boutique" + (boutiques.length > 1 ? "s" : "") + ". L'enseigne a ses propres " +
              "coordonnées — celles que voient les clients à l'accueil — et chaque boutique " +
              "a les siennes.</p>" +
            '<div class="cible-choix">' +
              '<button type="button" class="cible-onglet' + (surEnseigne ? " actif" : "") +
                '" data-cible="enseigne">' + UI.icone("magasin", "ic-sm") +
                "<span>BIZZOO<small>L'enseigne</small></span></button>" +
              '<button type="button" class="cible-onglet' + (surEnseigne ? "" : " actif") +
                '" data-cible="boutique">' + UI.icone("boite", "ic-sm") +
                "<span>" + Utils.echapper((courante || {}).nomBoutique || "Boutique") +
                "<small>La boutique ouverte</small></span></button>" +
            "</div>" +
            '<a class="btn btn-clair" href="#/boutiques" style="margin-top:12px">' + UI.icone("magasin") +
              "Gérer les boutiques</a>" +
          "</div>"
        : "") +

      /* ---------- Identité et contacts ---------- */
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("magasin", "ic-sm") + " " +
          Utils.echapper(surEnseigne ? "BIZZOO" : ((courante || {}).nomBoutique || "La boutique")) + "</div>" +
        '<p class="aide" style="margin:0 0 12px">' +
          (surEnseigne
            ? "Les coordonnées de l'enseigne : elles s'affichent dans l'onglet Infos des " +
              "clients tant qu'ils n'ont pas choisi de boutique."
            : "Ces informations s'affichent dans l'application client quand on entre dans " +
              "cette boutique (contact, WhatsApp de commande…).") + "</p>" +
        UI.champTexte({ id: "r-nom", label: "Nom", valeur: r.nomBoutique, obligatoire: true }) +
        UI.champTexte({ id: "r-slogan", label: "Slogan", valeur: r.slogan,
          aide: "Affiché en bandeau rouge dans l'application client." }) +
        UI.champZone({ id: "r-description", label: "Présentation", valeur: r.description, lignes: 3 }) +
        UI.champTexte({ id: "r-whatsapp", label: "Numéro WhatsApp (commandes)", valeur: r.whatsapp,
          type: "tel", placeholder: "01 97 00 00 00",
          aide: "Les clients commandent par ce numéro depuis l'application." }) +
        UI.champTexte({ id: "r-tel", label: "Téléphone (appels)", valeur: r.tel, type: "tel",
          placeholder: "01 97 00 00 00" }) +
        (surEnseigne
          ? UI.champTexte({ id: "r-indicatif", label: "Indicatif pays", valeur: r.indicatif,
              placeholder: "229" })
          : '<div class="champ-duo">' +
              UI.champTexte({ id: "r-indicatif", label: "Indicatif pays", valeur: r.indicatif, placeholder: "229" }) +
              UI.champTexte({ id: "r-devise", label: "Devise", valeur: r.devise, placeholder: "FCFA" }) +
            "</div>") +
        UI.champTexte({ id: "r-adresse", label: "Adresse", valeur: r.adresse,
          placeholder: "Quartier, rue, ville" }) +
        UI.champTexte({ id: "r-horaires", label: "Horaires", valeur: r.horaires,
          placeholder: "Lun–Sam : 8h–19h" }) +
        '<button type="button" class="btn" id="r-enregistrer">' + UI.icone("check") + (surEnseigne ? "Enregistrer BIZZOO" : "Enregistrer la boutique") + "</button>" +
      "</div>" +

      /* ---------- Marge (une boutique seulement : l'enseigne ne vend rien) ---------- */
      (surEnseigne ? "" :
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("promo", "ic-sm") + " Marge par défaut</div>" +
        '<p class="aide" style="margin:0 0 12px">Vous tapez le prix grossiste d\'un produit, ' +
          "l'application y ajoute ce taux et obtient le prix public — celui que voient vos clients. " +
          "Chaque produit peut garder son propre taux ; celui-ci sert pour tous les autres.</p>" +
        '<div class="champ">' +
          '<label for="r-taux">Taux appliqué au prix grossiste</label>' +
          '<div class="champ-montant">' +
            '<input id="r-taux" inputmode="decimal" autocomplete="off" placeholder="20" value="' +
              Utils.echapper(Utils.fmtTaux(r.tauxMarge)) + '">' +
            '<span class="devise">%</span>' +
          "</div>" +
          '<div class="aide" id="r-taux-exemple"></div>' +
        "</div>" +
        '<button type="button" class="btn" id="r-taux-enregistrer">' +
          UI.icone("check") + "Enregistrer le taux</button>" +
        '<p class="aide" style="margin:12px 0 0">Changer ce taux ne retouche aucun prix ' +
          "déjà enregistré : il s'appliquera aux prochains produits, et à ceux que vous " +
          "rouvrirez sans taux propre.</p>" +
      "</div>") +

      /* ---------- Autres numéros ---------- */
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("tel", "ic-sm") + " Autres numéros " +
          '<span class="aide-inline">(' + Store.MAX_TELEPHONES + " max)</span></div>" +
        '<p class="aide" style="margin:0 0 12px">En plus du numéro principal ci-dessus : atelier, ' +
          "service après-vente, second poste… Ils s'affichent tous dans l'onglet Infos des clients, " +
          "avec leur libellé.</p>" +
        '<div id="r-tels"></div>' +
        '<div class="btn-rangee" style="margin-top:12px">' +
          '<button type="button" class="btn btn-clair" id="r-tel-ajouter">' +
            UI.icone("plus") + "Ajouter un numéro</button>" +
          '<button type="button" class="btn" id="r-tels-enregistrer">' +
            UI.icone("check") + "Enregistrer les numéros</button>" +
        "</div>" +
      "</div>" +

      /* ---------- Autres adresses ---------- */
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("carte", "ic-sm") + " Autres adresses " +
          '<span class="aide-inline">(' + Store.MAX_ADRESSES + " max)</span></div>" +
        '<p class="aide" style="margin:0 0 12px">Une annexe, un dépôt, un second point de vente. ' +
          "La position est facultative : renseignée, le client peut lancer l'itinéraire vers ce lieu " +
          "d'un seul appui.</p>" +
        '<div id="r-adresses"></div>' +
        '<div class="btn-rangee" style="margin-top:12px">' +
          '<button type="button" class="btn btn-clair" id="r-adresse-ajouter">' +
            UI.icone("plus") + "Ajouter une adresse</button>" +
          '<button type="button" class="btn" id="r-adresses-enregistrer">' +
            UI.icone("check") + "Enregistrer les adresses</button>" +
        "</div>" +
      "</div>" +

      /* ---------- Localisation ---------- */
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("instagram", "ic-sm") + " Réseaux sociaux</div>" +
        '<p class="aide" style="margin:0 0 12px">Indiquez le nom du compte (ex. <strong>impactinformatique</strong>) ' +
          "ou collez le lien complet. Seuls les réseaux remplis apparaissent chez les clients.</p>" +
        UI.champTexte({ id: "rs-facebook", label: "Facebook", valeur: r.facebook,
          placeholder: "impactinformatique" }) +
        UI.champTexte({ id: "rs-instagram", label: "Instagram", valeur: r.instagram,
          placeholder: "@impactinformatique" }) +
        UI.champTexte({ id: "rs-tiktok", label: "TikTok", valeur: r.tiktok,
          placeholder: "@impactinformatique" }) +
        UI.champTexte({ id: "rs-youtube", label: "YouTube", valeur: r.youtube,
          placeholder: "@impactinformatique" }) +
        UI.champTexte({ id: "rs-snapchat", label: "Snapchat", valeur: r.snapchat,
          placeholder: "impactinformatique" }) +
        '<div class="btn-rangee">' +
          '<button type="button" class="btn" id="rs-enregistrer">' + UI.icone("check") + "Enregistrer les réseaux</button>" +
        "</div>" +
        '<div id="rs-apercu"></div>' +
      "</div>" +

      '<div class="carte" id="section-localisation">' +
        '<div class="carte-titre">' + UI.icone("carte", "ic-sm") + " Localisation de la boutique</div>" +
        '<p class="aide" style="margin:0 0 12px">Les clients pourront lancer l\'itinéraire vers la boutique ' +
          "depuis leur téléphone. Le plus simple : appuyez sur le bouton ci-dessous <strong>en étant sur place</strong>.</p>" +
        '<button type="button" class="btn btn-clair" id="loc-position">' +
          UI.icone("carte") + "Utiliser ma position actuelle</button>" +
        '<div class="champ-duo" style="margin-top:14px">' +
          UI.champTexte({ id: "loc-lat", label: "Latitude",
            valeur: r.latitude === null ? "" : r.latitude, placeholder: "6.3654" }) +
          UI.champTexte({ id: "loc-lng", label: "Longitude",
            valeur: r.longitude === null ? "" : r.longitude, placeholder: "2.4183" }) +
        "</div>" +
        UI.champTexte({ id: "loc-lien", label: "…ou collez un lien Google Maps", placeholder: "https://maps.app.goo.gl/…",
          aide: "Les coordonnées sont extraites automatiquement du lien." }) +
        '<div id="loc-resultat"></div>' +
        '<div class="btn-rangee" style="margin-top:12px">' +
          '<button type="button" class="btn" id="loc-enregistrer">' + UI.icone("check") + "Enregistrer la position</button>" +
          (r.latitude !== null && r.longitude !== null
            ? '<a class="btn btn-clair" target="_blank" rel="noopener" href="https://www.google.com/maps/search/?api=1&query=' +
                r.latitude + "," + r.longitude + '">' + UI.icone("oeil") + "Vérifier sur la carte</a>"
            : "") +
        "</div>" +
      "</div>" +

      /* ---------- Photos ---------- */
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("image", "ic-sm") + " Photos " +
          '<span class="aide-inline">(' + Store.MAX_PHOTOS_BOUTIQUE + " max)</span></div>" +
        '<p class="aide" style="margin:0 0 12px">Devanture, rayons, atelier… Elles rassurent les clients ' +
          "et s'affichent dans l'onglet Infos de leur application.</p>" +
        '<div class="photos-zone" id="boutique-photos"></div>' +
        '<button type="button" class="btn" id="boutique-photos-enregistrer" style="margin-top:14px">' +
          UI.icone("check") + "Enregistrer les photos</button>" +
      "</div>" +

      /* ---------- Slider ----------
         Celui de l'enseigne défile sur l'accueil de l'application ;
         celui d'une boutique, sur son écran à elle. */
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("image", "ic-sm") + " Slider" +
          (surEnseigne ? " de BIZZOO" : "") + "</div>" +
        '<div id="reg-slider"></div>' +
      "</div>" +

      /* ---------- Vidéo de présentation ---------- */
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("video", "ic-sm") + " Vidéo de présentation " +
          '<span class="aide-inline">(facultative · ' + Store.MAX_VIDEO_MO + " Mo max)</span></div>" +
        '<p class="aide" style="margin:0 0 12px">Une visite filmée vaut mille photos. Elle se lit ' +
          "dans l'onglet Infos des clients.</p>" +
        '<div id="boutique-video"></div>' +
        '<button type="button" class="btn" id="boutique-video-enregistrer" style="margin-top:14px">' +
          UI.icone("check") + "Enregistrer la vidéo</button>" +
      "</div>" +

      /* ---------- Comptes ---------- */
      '<div class="carte" id="section-compte">' +
        '<div class="carte-titre">' + UI.icone("equipe", "ic-sm") + " Comptes</div>" +
        '<p class="aide" style="margin:0 0 12px">Connecté en tant que <strong>' +
          Utils.echapper(Supabase.utilisateur() || "—") + "</strong> (administrateur).<br>" +
          "Vous pouvez créer des comptes pour votre équipe : un modérateur s'occupe " +
          "des produits et des catégories, sans accès aux réglages.</p>" +
        '<div class="btn-rangee">' +
          '<a class="btn" href="#/comptes">' + UI.icone("equipe") + "Gérer l'équipe</a>" +
          '<a class="btn btn-clair" href="#/compte">' + UI.icone("cle") + "Mon mot de passe</a>" +
        "</div>" +
        '<button type="button" class="btn btn-clair" id="c-deconnexion" style="margin-top:10px">Se déconnecter</button>' +
      "</div>" +

      /* ---------- Connexion à la base ---------- */
      (!configEnDur
        ? '<div class="carte" id="section-base">' +
            '<div class="carte-titre">' + UI.icone("nuage", "ic-sm") + " Connexion à la base</div>" +
            UI.champTexte({ id: "b-url", label: "Adresse du projet Supabase", valeur: configActuelle.url,
              placeholder: "https://abcdefgh.supabase.co", type: "url" }) +
            UI.champTexte({ id: "b-cle", label: "Clé « anon public »", valeur: configActuelle.cle,
              placeholder: "eyJhbGciOi…" }) +
            '<div class="btn-rangee" style="margin-top:4px">' +
              '<button type="button" class="btn" id="b-enregistrer">' + UI.icone("check") + "Enregistrer</button>" +
              '<button type="button" class="btn btn-clair" id="b-tester">' + UI.icone("actualiser") + "Tester la connexion</button>" +
            "</div>" +
            '<div id="b-resultat"></div>' +
          "</div>"
        : "") +

      /* ---------- Sauvegarde ---------- */
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("telecharger", "ic-sm") + " Sauvegarde</div>" +
        '<p class="aide" style="margin:0 0 12px">Les données vivent déjà en ligne, mais une copie de secours ' +
          "(produits, photos, réglages) ne coûte rien : à garder sur WhatsApp, e-mail ou carte mémoire.<br>" +
          "<strong>Le fichier contient vos prix grossistes</strong> : ne le transmettez qu'à quelqu'un " +
          "de la boutique.</p>" +
        '<div class="btn-rangee">' +
          '<button type="button" class="btn btn-clair" id="s-exporter">' + UI.icone("telecharger") + "Exporter une sauvegarde</button>" +
          '<label class="btn btn-clair" for="s-importer-fichier">' + UI.icone("televerser") + "Restaurer une sauvegarde" +
            '<input type="file" id="s-importer-fichier" accept="application/json,.json" hidden></label>' +
        "</div>" +
        '<div id="s-progression" class="aide" style="margin-top:10px"></div>' +
      "</div>" +

      /* ---------- À propos ---------- */
      '<div class="carte">' +
        '<div class="carte-titre">À propos</div>' +
        '<p class="aide" style="margin:0">' +
          "BIZZOO Admin — gestion des boutiques et de leurs catalogues.<br>" +
          "Base en ligne : les modifications sont visibles immédiatement par les clients." +
        "</p>" +
      "</div>";

    if (params && params.section === "compte") {
      const section = UI.$("#section-compte");
      if (section) setTimeout(() => section.scrollIntoView({ behavior: "smooth", block: "start" }), 60);
    }

    /* ---------- Boutique ---------- */
    UI.$("#r-enregistrer").onclick = async () => {
      const nom = UI.$("#r-nom").value.trim();
      if (!nom) {
        UI.toast((surEnseigne ? "Le nom de l'enseigne" : "Le nom de la boutique") +
          " est obligatoire.", "err");
        return;
      }
      try {
        await enregistrer({
          nomBoutique: nom,
          slogan: UI.$("#r-slogan").value.trim(),
          description: UI.$("#r-description").value.trim(),
          whatsapp: UI.$("#r-whatsapp").value.trim(),
          tel: UI.$("#r-tel").value.trim(),
          indicatif: UI.$("#r-indicatif").value.trim() || "229",
          ...(surEnseigne ? {} : { devise: UI.$("#r-devise").value.trim() || "FCFA" }),
          adresse: UI.$("#r-adresse").value.trim(),
          horaires: UI.$("#r-horaires").value.trim(),
        }, (surEnseigne ? "Coordonnées de BIZZOO modifiées" : "Informations de la boutique modifiées"));
        UI.toast((surEnseigne ? "BIZZOO enregistrée" : "Boutique enregistrée") +
          " — visible immédiatement chez les clients.", "ok");
      } catch (err) {
        UI.toast(err.message, "err");
      }
    };

    /* ---------- Marge ----------
       Un exemple chiffré vaut mieux qu'une explication : on montre en
       direct ce que devient un achat à 100 000. */
    const champTaux = UI.$("#r-taux");
    /* Absent quand on règle l'enseigne : elle n'a pas de marge. */
    if (champTaux) {
      const exemple = UI.$("#r-taux-exemple");
      const direExemple = () => {
        const taux = Store.lireTaux(champTaux.value);
        if (taux === null) {
          exemple.textContent = "Indiquez un nombre entre 0 et " + Store.TAUX_MAX + ".";
          return;
        }
        const achat = 100000;
        exemple.textContent = "Exemple : acheté à " + Utils.fmtMontant(achat, r.devise) +
          ", vendu " + Utils.fmtMontant(Store.prixPublic(achat, taux), r.devise) + ".";
      };
      champTaux.addEventListener("input", Utils.tempo(direExemple, 300));
      direExemple();

      UI.$("#r-taux-enregistrer").onclick = async () => {
        try {
          await enregistrer({ tauxMarge: champTaux.value },
            "Taux de marge de la boutique : " + Utils.fmtTaux(Store.lireTaux(champTaux.value)) + " %");
          UI.toast("Taux enregistré", "ok");
          afficher(vue, params);
        } catch (err) {
          UI.toast(err.message, "err");
        }
      };
    }

    /* ---------- Autres numéros ---------- */
    telsTravail = (r.telephones || []).map((t) => ({ ...t }));
    const zoneTels = UI.$("#r-tels");

    const rendreTels = () => {
      zoneTels.innerHTML = htmlTelephones();
      for (const b of UI.$$("[data-tel-retirer]", zoneTels)) {
        b.onclick = () => {
          lireTelephones(zoneTels);
          telsTravail.splice(Number(b.dataset.telRetirer), 1);
          rendreTels();
        };
      }
    };
    rendreTels();

    UI.$("#r-tel-ajouter").onclick = () => {
      lireTelephones(zoneTels);
      if (telsTravail.length >= Store.MAX_TELEPHONES) {
        UI.toast("Déjà " + Store.MAX_TELEPHONES + " numéros : c'est le maximum.", "err");
        return;
      }
      telsTravail.push({ libelle: "", numero: "", whatsapp: false });
      rendreTels();
      const champs = UI.$$("[data-tel-libelle]", zoneTels);
      if (champs.length) champs[champs.length - 1].focus();
    };

    UI.$("#r-tels-enregistrer").onclick = async () => {
      lireTelephones(zoneTels);
      const vides = telsTravail.filter((t) => !/\d/.test(t.numero)).length;
      try {
        const maj = await enregistrer({ telephones: telsTravail },
          "Autres numéros de la boutique mis à jour");
        telsTravail = (maj.telephones || []).map((t) => ({ ...t }));
        rendreTels();
        UI.toast(vides
          ? "Numéros enregistrés (" + vides + " ligne" + (vides > 1 ? "s vides ont" : " vide a") + " été écartée" +
            (vides > 1 ? "s" : "") + ")"
          : "Numéros enregistrés — visibles chez les clients", vides ? "err" : "ok");
      } catch (err) {
        UI.toast(err.message, "err");
      }
    };

    /* ---------- Autres adresses ---------- */
    adressesTravail = (r.adresses || []).map((a) => ({ ...a }));
    const zoneAdresses = UI.$("#r-adresses");

    const rendreAdresses = () => {
      zoneAdresses.innerHTML = htmlAdresses();
      for (const b of UI.$$("[data-adr-retirer]", zoneAdresses)) {
        b.onclick = () => {
          lireAdresses(zoneAdresses);
          adressesTravail.splice(Number(b.dataset.adrRetirer), 1);
          rendreAdresses();
        };
      }
      /* Un lien Google Maps collé remplit les deux coordonnées. */
      for (const champ of UI.$$("[data-adr-lien]", zoneAdresses)) {
        champ.addEventListener("input", (ev) => {
          const trouve = String(ev.target.value)
            .match(/(-?\d{1,3}\.\d{3,})[,\s/@]+(-?\d{1,3}\.\d{3,})/);
          if (!trouve) return;
          const i = champ.dataset.adrLien;
          UI.$('[data-adr-lat="' + i + '"]', zoneAdresses).value = trouve[1];
          UI.$('[data-adr-lng="' + i + '"]', zoneAdresses).value = trouve[2];
          UI.toast("Coordonnées extraites du lien", "ok");
        });
      }
    };
    rendreAdresses();

    UI.$("#r-adresse-ajouter").onclick = () => {
      lireAdresses(zoneAdresses);
      if (adressesTravail.length >= Store.MAX_ADRESSES) {
        UI.toast("Déjà " + Store.MAX_ADRESSES + " adresses : c'est le maximum.", "err");
        return;
      }
      adressesTravail.push({ libelle: "", texte: "", latitude: "", longitude: "" });
      rendreAdresses();
      const champs = UI.$$("[data-adr-libelle]", zoneAdresses);
      if (champs.length) champs[champs.length - 1].focus();
    };

    UI.$("#r-adresses-enregistrer").onclick = async () => {
      lireAdresses(zoneAdresses);
      const vides = adressesTravail.filter((a) => !String(a.texte || "").trim()).length;
      try {
        const maj = await enregistrer({ adresses: adressesTravail },
          "Autres adresses de la boutique mises à jour");
        adressesTravail = (maj.adresses || []).map((a) => ({ ...a }));
        rendreAdresses();
        UI.toast(vides
          ? "Adresses enregistrées (" + vides + " sans texte " + (vides > 1 ? "ont" : "a") + " été écartée" +
            (vides > 1 ? "s" : "") + ")"
          : "Adresses enregistrées — visibles chez les clients", vides ? "err" : "ok");
      } catch (err) {
        UI.toast(err.message, "err");
      }
    };

    /* ---------- Localisation ---------- */
    const RESEAUX = [
      ["facebook", "Facebook"], ["instagram", "Instagram"], ["tiktok", "TikTok"],
      ["youtube", "YouTube"], ["snapchat", "Snapchat"],
    ];

    /** Nom de compte ou lien complet -> adresse ouverte par les clients. */
    const lienReseau = (reseau, valeur) => {
      const v = String(valeur || "").trim();
      if (!v) return "";
      if (/^https?:\/\//i.test(v)) return v;
      if (/^(www\.|[a-z0-9-]+\.[a-z]{2,}\/)/i.test(v)) return "https://" + v.replace(/^\/+/, "");
      const bases = {
        facebook: "https://facebook.com/", instagram: "https://instagram.com/",
        tiktok: "https://tiktok.com/@", youtube: "https://youtube.com/@",
        snapchat: "https://snapchat.com/add/",
      };
      return bases[reseau] + v.replace(/^@+/, "").replace(/^\/+/, "");
    };

    /* Aperçu en direct : le gérant voit où mènent ses saisies. */
    const montrerApercuReseaux = () => {
      const liens = RESEAUX
        .map(([cle, nom]) => ({ nom, lien: lienReseau(cle, UI.$("#rs-" + cle).value) }))
        .filter((x) => x.lien);
      UI.$("#rs-apercu").innerHTML = liens.length
        ? '<div class="aide" style="margin-top:12px">Adresses ouvertes par les clients :</div>' +
          liens.map((x) =>
            '<a class="lien-copiable" style="margin-top:8px" target="_blank" rel="noopener" href="' +
              Utils.echapper(x.lien) + '">' + UI.icone("lien", "ic-sm") +
              "<span>" + Utils.echapper(x.lien) + "</span></a>").join("")
        : "";
    };

    for (const [cle] of RESEAUX) {
      UI.$("#rs-" + cle).addEventListener("input", Utils.tempo(montrerApercuReseaux, 300));
    }
    montrerApercuReseaux();

    UI.$("#rs-enregistrer").onclick = async () => {
      try {
        const maj = {};
        for (const [cle] of RESEAUX) maj[cle] = UI.$("#rs-" + cle).value.trim();
        await enregistrer(maj, "Réseaux sociaux mis à jour");
        UI.toast("Réseaux enregistrés — visibles chez les clients", "ok");
      } catch (err) {
        UI.toast(err.message, "err");
      }
    };

    const zoneLoc = UI.$("#loc-resultat");
    const direLoc = (texte, type) => {
      zoneLoc.innerHTML = texte
        ? '<div class="' + (type === "err" ? "note-attente" : "note-ok") + '" style="margin-top:12px">' +
            UI.icone(type === "err" ? "alerte" : "check", "ic-sm") + " " + Utils.echapper(texte) + "</div>"
        : "";
    };

    UI.$("#loc-position").onclick = () => {
      if (!navigator.geolocation) {
        direLoc("Ce téléphone ne permet pas de relever la position.", "err");
        return;
      }
      direLoc("Relevé de la position en cours…");
      navigator.geolocation.getCurrentPosition(
        (position) => {
          UI.$("#loc-lat").value = position.coords.latitude.toFixed(6);
          UI.$("#loc-lng").value = position.coords.longitude.toFixed(6);
          direLoc("Position relevée (précision : environ " +
            Math.round(position.coords.accuracy) + " m). Enregistrez pour la publier.");
        },
        (err) => {
          direLoc(err.code === 1
            ? "Autorisation refusée : activez la localisation pour cette application."
            : "Position introuvable : sortez à l'air libre puis réessayez.", "err");
        },
        { enableHighAccuracy: true, timeout: 20000, maximumAge: 0 }
      );
    };

    /* Un lien Google Maps collé : on en extrait les coordonnées. */
    UI.$("#loc-lien").addEventListener("input", (ev) => {
      const trouve = String(ev.target.value).match(/(-?\d{1,3}\.\d{3,})[,\s/@]+(-?\d{1,3}\.\d{3,})/);
      if (trouve) {
        UI.$("#loc-lat").value = trouve[1];
        UI.$("#loc-lng").value = trouve[2];
        direLoc("Coordonnées extraites du lien. Enregistrez pour les publier.");
      }
    });

    UI.$("#loc-enregistrer").onclick = async () => {
      const lat = UI.$("#loc-lat").value.trim();
      const lng = UI.$("#loc-lng").value.trim();
      if (!lat && !lng) {
        try {
          await enregistrer({ latitude: null, longitude: null }, "Position de la boutique retirée");
          UI.toast("Position retirée", "ok");
          afficher(vue, params);
        } catch (err) { UI.toast(err.message, "err"); }
        return;
      }
      const latitude = Number(String(lat).replace(",", "."));
      const longitude = Number(String(lng).replace(",", "."));
      if (!isFinite(latitude) || latitude < -90 || latitude > 90 ||
          !isFinite(longitude) || longitude < -180 || longitude > 180) {
        direLoc("Coordonnées invalides : la latitude va de -90 à 90, la longitude de -180 à 180.", "err");
        return;
      }
      try {
        await enregistrer({ latitude, longitude },
          "Position de la boutique enregistrée (" + latitude.toFixed(5) + ", " + longitude.toFixed(5) + ")");
        UI.toast("Position enregistrée — visible chez les clients", "ok");
        afficher(vue, params);
      } catch (err) {
        UI.toast(err.message, "err");
      }
    };

    /* ---------- Enseigne ou boutique : la bascule ---------- */
    for (const bouton of UI.$$("[data-cible]", vue)) {
      bouton.onclick = () => {
        cible = bouton.dataset.cible;
        afficher(vue, params);
      };
    }

    /* ---------- Slider ----------
       Le même gestionnaire que l'écran Slider, posé dans la carte. */
    const zoneSlider = UI.$("#reg-slider", vue);
    if (zoneSlider) VueSlider.rendre(zoneSlider, surEnseigne ? "enseigne" : "boutique");

    /* ---------- Photos ---------- */
    photosTravail = Store.photosBoutique(cible);
    brancherPhotosBoutique(vue);

    UI.$("#boutique-photos-enregistrer").onclick = async () => {
      const bouton = UI.$("#boutique-photos-enregistrer");
      bouton.disabled = true;
      try {
        await Store.sauverPhotosBoutique(photosTravail, cible);
        UI.toast("Photos enregistrées", "ok");
        afficher(vue, params);
      } catch (err) {
        UI.toast(err.message, "err");
        bouton.disabled = false;
      }
    };

    /* ---------- Vidéo de présentation ---------- */
    videoTravail = Store.videoBoutique(cible);
    brancherVideoBoutique(vue);

    UI.$("#boutique-video-enregistrer").onclick = async () => {
      const bouton = UI.$("#boutique-video-enregistrer");
      bouton.disabled = true;
      try {
        await Store.sauverVideoBoutique(videoTravail, cible);
        UI.toast(videoTravail ? "Vidéo enregistrée" : "Vidéo retirée", "ok");
        afficher(vue, params);
      } catch (err) {
        UI.toast(err.message, "err");
        bouton.disabled = false;
      }
    };

    /* ---------- Compte ---------- */
    UI.$("#c-deconnexion").onclick = async () => {
      await Store.journaliser("compte", "deconnexion", "Déconnexion de l'application admin",
        Supabase.utilisateur());
      await Supabase.deconnexion();
      location.reload();
    };

    /* ---------- Connexion à la base ---------- */
    const btnBase = UI.$("#b-enregistrer");
    if (btnBase) {
      btnBase.onclick = () => {
        const url = UI.$("#b-url").value.trim();
        const cle = UI.$("#b-cle").value.trim();
        if (!/^https:\/\//.test(url) || !cle) {
          UI.toast("Indiquez l'adresse https://… et la clé du projet.", "err");
          return;
        }
        Supabase.majConfiguration(url, cle);
        UI.toast("Connexion enregistrée", "ok");
        setTimeout(() => location.reload(), 500);
      };
      UI.$("#b-tester").onclick = async () => {
        const zone = UI.$("#b-resultat");
        zone.innerHTML = '<div class="aide" style="margin-top:10px">Test en cours…</div>';
        try {
          Supabase.majConfiguration(UI.$("#b-url").value, UI.$("#b-cle").value);
          await Supabase.testerConnexion();
          zone.innerHTML = '<div class="note-ok" style="margin-top:10px">' + UI.icone("check", "ic-sm") +
            " Base joignable — tout est en ordre.</div>";
        } catch (err) {
          zone.innerHTML = '<div class="note-attente" style="margin-top:10px">' + UI.icone("alerte", "ic-sm") + " " +
            Utils.echapper(err.message) + "</div>";
        }
      };
    }

    /* ---------- Sauvegarde ---------- */
    UI.$("#s-exporter").onclick = async () => {
      const zone = UI.$("#s-progression");
      try {
        const donnees = await Store.exporter((texte) => { zone.textContent = texte; });
        zone.textContent = "";
        const jour = new Date().toISOString().slice(0, 10);
        Utils.telecharger("impact-catalogue-" + jour + ".json", JSON.stringify(donnees));
        UI.toast("Sauvegarde téléchargée", "ok");
      } catch (err) {
        zone.textContent = "";
        UI.toast(err.message, "err");
      }
    };

    UI.$("#s-importer-fichier").addEventListener("change", async (ev) => {
      const fichier = ev.target.files && ev.target.files[0];
      ev.target.value = "";
      if (!fichier) return;
      const ok = await UI.confirmer({
        titre: "Restaurer cette sauvegarde ?",
        texte: "Le contenu du fichier « " + fichier.name + " » sera réécrit dans le catalogue en ligne " +
          "(les produits du fichier remplacent ceux qui portent le même identifiant).",
        bouton: "Restaurer",
        danger: true,
      });
      if (!ok) return;
      const zone = UI.$("#s-progression");
      try {
        const donnees = JSON.parse(await fichier.text());
        const resultat = await Store.importer(donnees, (texte) => { zone.textContent = texte; });
        zone.textContent = "";
        UI.toast(resultat.produits + " produits restaurés", "ok");
        afficher(vue, params);
      } catch (err) {
        zone.textContent = "";
        UI.toast(err.message || "Fichier illisible", "err");
      }
    });
  }

  return { afficher };
})();
