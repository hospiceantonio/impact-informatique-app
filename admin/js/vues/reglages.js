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

  /* Plusieurs rendus peuvent se chevaucher : l'arrivée sur l'écran, la
     bascule enseigne/boutique, un enregistrement. Seul le plus récent a
     le droit de peindre. Sans cela, un rendu en retard remplace tout le
     formulaire — et efface ce que le gérant était en train d'y saisir. */
  let generation = 0;

  /* ---------- La livraison au kilomètre (3.64.0) ---------- */
  let carteKm = null;
  const unEnvoi = async (bouton, action) => {
    bouton.disabled = true;
    try { await action(); } finally { bouton.disabled = false; }
  };

  function htmlLivraisonKm(l) {
    const actif = l.latitude !== null && l.longitude !== null;
    const champ = (id, label, valeur, unite, aide) =>
      '<div class="champ"><label for="' + id + '">' + Utils.echapper(label) + "</label>" +
        '<div class="champ-montant"><input id="' + id + '" inputmode="decimal" autocomplete="off" value="' +
          Utils.echapper(String(valeur)) + '"><span class="devise">' + Utils.echapper(unite) + "</span></div>" +
        (aide ? '<div class="aide">' + Utils.echapper(aide) + "</div>" : "") + "</div>";
    return (
      (actif
        ? '<div class="note-ok" style="margin:0 0 12px">' + UI.icone("check", "ic-sm") +
            " En service : chaque commande paie UN frais, du point BIZZOO jusqu'au client.</div>"
        : '<div class="note-attente" style="margin:0 0 12px">' + UI.icone("alerte", "ic-sm") +
            " Pas encore en service : réglez le point BIZZOO pour l'ouvrir. D'ici là, chaque " +
            "boutique garde ses frais de livraison.</div>") +
      '<p class="aide" style="margin:0 0 12px">La distance se mesure à vol d\'oiseau du point BIZZOO ' +
        "jusqu'au client, multipliée par le coefficient de la route (réglé plus bas) ; chaque kilomètre entamé au-delà " +
        "du rayon compte. Le tricycle s'applique dès qu'un produit de la commande l'exige. Les frais se " +
        "paient en ligne avec l'acompte ; le livreur en touche sa part une fois la commande remise.</p>" +
      '<div class="carte-titre" style="font-size:14px">Le point BIZZOO</div>' +
      '<div class="btn-rangee">' +
        '<button type="button" class="btn btn-clair" id="km-position">' + UI.icone("carte") +
          "Ma position actuelle</button>" +
      "</div>" +
      '<div class="km-carte" id="km-carte"></div>' +
      '<p class="aide" style="margin:6px 0 10px">Déplacez l\'épingle ou touchez la carte pour poser le point.</p>' +
      '<div class="champ-duo">' +
        UI.champTexte({ id: "km-lat", label: "Latitude", valeur: actif ? l.latitude : "", placeholder: "6.3654" }) +
        UI.champTexte({ id: "km-lng", label: "Longitude", valeur: actif ? l.longitude : "", placeholder: "2.4183" }) +
      "</div>" +
      UI.champTexte({ id: "km-adresse", label: "Adresse du point (facultatif)", valeur: l.adresse,
        placeholder: "Siège BIZZOO, Cotonou" }) +
      '<div class="carte-titre" style="font-size:14px;margin-top:6px">Les tarifs</div>' +
      '<div class="champ-duo">' +
        champ("km-moto-forfait", "Moto : forfait", l.motoForfait, "FCFA") +
        champ("km-moto-km", "Moto : par km au-delà", l.motoPrixKm, "FCFA") +
      "</div>" +
      '<div class="champ-duo">' +
        champ("km-tri-forfait", "Tricycle : forfait", l.tricycleForfait, "FCFA") +
        champ("km-tri-km", "Tricycle : par km au-delà", l.tricyclePrixKm, "FCFA") +
      "</div>" +
      '<div class="champ-duo">' +
        champ("km-rayon", "Le forfait couvre", l.rayon, "km") +
        /* (3.66.0) Le détour de la route, réglable : 1,3 = 30 % de plus
           que la ligne droite. La base le borne entre 1 et 3. */
        champ("km-coef", "Coefficient de la route", String(isFinite(l.coef) && l.coef ? l.coef : 1.3).replace(".", ","), "×",
          "La distance en ligne droite est multipliée par ce nombre pour suivre les routes. " +
          "1,3 = 30 % de détour. Entre 1 et 3.") +
      "</div>" +
      '<div class="champ-duo">' +
        champ("km-taux", "Part du livreur", l.tauxLivreur, "%",
          "Sur les frais de chaque commande ; le reste revient à BIZZOO.") +
      "</div>" +
      '<div class="btn-rangee" style="margin-top:6px">' +
        '<button type="button" class="btn" id="km-enregistrer">' + UI.icone("check") + "Enregistrer</button>" +
        (actif ? '<button type="button" class="btn btn-clair" id="km-arreter">Arrêter la livraison au km</button>' : "") +
      "</div>"
    );
  }

  /* ---------- (3.70.0) Les préfixes des opérateurs ---------- */
  const OPERATEURS_PREFIXES = [["MTN", "MTN"], ["MOOV", "Moov"], ["CELTIIS", "Celtiis"]];

  function htmlPrefixes(lignes) {
    const e = Utils.echapper;
    return OPERATEURS_PREFIXES.map(([op, nom]) => {
      const siens = lignes.filter((l) => l.operateur === op).map((l) => l.prefixe).sort();
      return '<div class="champ"><label>' + e(nom) + " <small>(" + siens.length + ")</small></label>" +
        '<div class="st-filtres">' +
          (siens.length
            ? siens.map((p) => '<button type="button" class="puce" data-prefixe="' + e(p) +
                '" data-operateur="' + e(op) + '" title="Retirer ou réattribuer">01 ' + e(p) + "</button>").join("")
            : '<span class="aide">Aucun préfixe</span>') +
        "</div></div>";
    }).join("") +
    '<div class="champ-duo">' +
      UI.champTexte({ id: "prefixe-nouveau", label: "Préfixe", type: "tel", placeholder: "Exemple : 01 30",
        aide: "Les deux chiffres après 01." }) +
      '<div class="champ"><label for="prefixe-operateur">Opérateur</label>' +
        '<select id="prefixe-operateur">' +
          OPERATEURS_PREFIXES.map(([op, nom]) => '<option value="' + op + '">' + nom + "</option>").join("") +
        "</select></div>" +
    "</div>" +
    '<button type="button" class="btn" id="prefixe-enregistrer">' + UI.icone("plus") +
      "Ajouter ou réattribuer</button>";
  }

  function brancherPrefixes(toujoursLa) {
    Store.listerPrefixes().then((lignes) => {
      const corps = UI.$("#prefixes-corps");
      if (!toujoursLa() || !corps) return;
      if (!lignes.length) {
        corps.innerHTML = '<p class="aide" style="margin:0">Exécutez d\'abord le fichier ' +
          "supabase/prefixes-operateurs.sql. En attendant, les applications gardent leur liste intégrée.</p>";
        return;
      }
      corps.innerHTML = htmlPrefixes(lignes);
      const regler = async (bouton, prefixe, operateur, message) => unEnvoi(bouton, async () => {
        try {
          await Store.reglerPrefixe(prefixe, operateur);
          UI.toast(message, "ok");
          brancherPrefixes(toujoursLa);
        } catch (err) { UI.toast(err.message, "err"); }
      });
      const bouton = UI.$("#prefixe-enregistrer");
      bouton.onclick = () => {
        const saisi = UI.$("#prefixe-nouveau").value;
        const chiffres = saisi.replace(/\D/g, "").replace(/^01(?=\d{2}$)/, "");
        const op = UI.$("#prefixe-operateur").value;
        const nom = Utils.NOM_OPERATEUR[op] || op;
        const avant = lignes.find((l) => l.prefixe === chiffres);
        if (avant && avant.operateur === op) { UI.toast("01 " + chiffres + " est déjà " + nom + ".", "alerte"); return; }
        if (avant && !window.confirm("01 " + chiffres + " est aujourd'hui " +
            (Utils.NOM_OPERATEUR[avant.operateur] || avant.operateur) + ". Le passer à " + nom + " ?")) return;
        regler(bouton, saisi, op, "01 " + chiffres + " → " + nom);
      };
      for (const puce of UI.$$("[data-prefixe]", corps)) {
        puce.onclick = () => {
          const p = puce.dataset.prefixe;
          const nom = Utils.NOM_OPERATEUR[puce.dataset.operateur] || puce.dataset.operateur;
          if (!window.confirm("Retirer 01 " + p + " (" + nom + ") ? Les numéros qui commencent ainsi " +
              "ne feront plus corriger le réseau. Pour le passer à un autre opérateur, saisissez-le " +
              "plutôt dans « Préfixe » avec le bon opérateur.")) return;
          regler(puce, p, "", "01 " + p + " retiré");
        };
      }
    }).catch(() => {
      const corps = UI.$("#prefixes-corps");
      if (corps) corps.innerHTML = '<p class="aide" style="margin:0">Liste illisible pour l\'instant ' +
        "(exécutez supabase/prefixes-operateurs.sql si ce n'est pas fait).</p>";
    });
  }

  function brancherLivraisonKm(toujoursLa) {
    if (carteKm) { carteKm.detruire(); carteKm = null; }
    Store.lirePaiement().then(async (p) => {
      const corps = UI.$("#km-corps");
      if (!toujoursLa() || !corps) return;
      if (!p.livraison) {
        corps.innerHTML = '<p class="aide" style="margin:0">Exécutez d\'abord le fichier ' +
          "supabase/livraison-au-km.sql.</p>";
        return;
      }
      const l = p.livraison;
      corps.innerHTML = htmlLivraisonKm(l);
      const lat = UI.$("#km-lat"), lng = UI.$("#km-lng");
      const lire = () => {
        const a = Number(String(lat.value).replace(",", ".")), b = Number(String(lng.value).replace(",", "."));
        return lat.value.trim() && lng.value.trim() && isFinite(a) && isFinite(b) ? { latitude: a, longitude: b } : null;
      };
      const poser = (d) => { lat.value = d.latitude.toFixed(6); lng.value = d.longitude.toFixed(6); };
      try {
        carteKm = await Carte.monter(UI.$("#km-carte"), { position: lire(), deplace: poser });
      } catch (_) {
        const zone = UI.$("#km-carte");
        if (zone) zone.innerHTML = '<p class="aide" style="padding:12px">La carte ne s\'affiche pas sans ' +
          "connexion : saisissez les coordonnées, ou « Ma position actuelle ».</p>";
      }
      for (const champ of [lat, lng]) {
        champ.addEventListener("change", () => { const d = lire(); if (d && carteKm) carteKm.placer(d); });
      }
      UI.$("#km-position").onclick = () => {
        if (!navigator.geolocation) { UI.toast("Ce téléphone ne permet pas de relever la position.", "err"); return; }
        UI.toast("Relevé de la position…");
        navigator.geolocation.getCurrentPosition(
          (pos) => {
            const d = { latitude: pos.coords.latitude, longitude: pos.coords.longitude };
            poser(d);
            if (carteKm) carteKm.placer(d);
            UI.toast("Position relevée : enregistrez pour la retenir.", "ok");
          },
          (err) => UI.toast(err.code === 1
            ? "Autorisation refusée : activez la localisation pour cette application."
            : "Position introuvable : sortez à l'air libre puis réessayez.", "err"),
          { enableHighAccuracy: true, timeout: 20000, maximumAge: 0 });
      };
      const valeurs = (point) => ({
        point,
        adresse: UI.$("#km-adresse").value,
        rayon: UI.$("#km-rayon").value,
        coef: UI.$("#km-coef").value,
        motoForfait: UI.$("#km-moto-forfait").value, motoPrixKm: UI.$("#km-moto-km").value,
        tricycleForfait: UI.$("#km-tri-forfait").value, tricyclePrixKm: UI.$("#km-tri-km").value,
        tauxLivreur: UI.$("#km-taux").value,
      });
      const bouton = UI.$("#km-enregistrer");
      bouton.onclick = () => unEnvoi(bouton, async () => {
        const point = lire();
        if (!point) { UI.toast("Posez d'abord le point BIZZOO sur la carte", "err"); return; }
        try {
          await Store.majLivraisonKm(valeurs(point));
          UI.toast("Livraison au kilomètre enregistrée — en service", "ok");
          brancherLivraisonKm(toujoursLa);
        } catch (err) { UI.toast(err.message, "err"); }
      });
      const arreter = UI.$("#km-arreter");
      if (arreter) {
        arreter.onclick = () => unEnvoi(arreter, async () => {
          if (!window.confirm("Arrêter la livraison au kilomètre ? Les frais de chaque boutique " +
              "s'appliqueront de nouveau aux nouvelles commandes.")) return;
          try {
            await Store.majLivraisonKm(valeurs(null));
            UI.toast("Livraison au kilomètre arrêtée", "ok");
            brancherLivraisonKm(toujoursLa);
          } catch (err) { UI.toast(err.message, "err"); }
        });
      }
    }).catch(() => {
      const corps = UI.$("#km-corps");
      if (corps) corps.innerHTML = '<p class="aide" style="margin:0">Réglages illisibles pour l\'instant.</p>';
    });
  }

  async function afficher(vue, params) {
    const moi = ++generation;
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

    /* Ce que cette boutique a demandé et qui attend encore. Le
       superadministrateur n'attend rien : il tranche. La table peut ne
       pas exister — le SQL n'a peut-être pas été exécuté. */
    const enAttente = (surEnseigne || Supabase.estSuper())
      ? []
      : (await Store.listerDemandes("en_attente").catch(() => []));

    const configEnDur = typeof CONFIG !== "undefined" && !!CONFIG.SUPABASE_URL;
    const configActuelle = Supabase.configuration() || { url: "", cle: "" };


    /* Enregistrer va dans la ligne de l'enseigne ou dans celle de la
       boutique ouverte, selon l'onglet choisi. */
    const enregistrer = (maj, libelle) =>
      (surEnseigne ? Store.majEnseigne(maj, libelle) : Store.majReglages(maj, libelle));

    /* Un rendu plus récent a pris la main pendant nos lectures : celui-ci
       n'a plus rien à dire. */
    if (moi !== generation) return;

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
              /* Le nom dans son « strong » : il se plie sur deux lignes
                 (« IMPACT INFORMATIQUE ») au lieu de pousser la tuile
                 hors de l'écran. */
              '<button type="button" class="cible-onglet' + (surEnseigne ? " actif" : "") +
                '" data-cible="enseigne">' + UI.icone("magasin", "ic-sm") +
                "<span><strong>BIZZOO</strong><small>L'enseigne</small></span></button>" +
              '<button type="button" class="cible-onglet' + (surEnseigne ? "" : " actif") +
                '" data-cible="boutique">' + UI.icone("boite", "ic-sm") +
                "<span><strong>" + Utils.echapper((courante || {}).nomBoutique || "Boutique") +
                "</strong><small>La boutique ouverte</small></span></button>" +
            "</div>" +
            /* Les portes permanentes, en liste (3.62.0) : cinq boutons
               empilés se lisaient comme cinq alarmes. L'accueil ne parle
               des demandes que lorsqu'une attend : sans ces portes,
               retirer un statut accordé par erreur serait impossible, et
               les décisions passées irrelisables. */
            '<div class="liste-portes" style="margin-top:14px">' +
              UI.porte({ href: "#/boutiques", icone: "magasin", titre: "Gérer les boutiques",
                sous: "Secteurs, ordre, logos, ouverture" }) +
              UI.porte({ href: "#/revendeurs", icone: "personne", titre: "Comptes revendeurs",
                sous: "Demandes à trancher, comptes validés" }) +
              UI.porte({ href: "#/validations", icone: "check", titre: "Demandes des boutiques",
                sous: "Changements à approuver, décisions passées" }) +
              UI.porte({ href: "#/avis", icone: "etoile", titre: "Avis des clients",
                sous: "Répondre, signaler, masquer" }) +
              UI.porte({ href: "#/sav", icone: "alerte", titre: "Réclamations",
                sous: "Le service après-vente, boutique par boutique" }) +
            "</div>" +
          "</div>" +

          /* ---------- La passerelle SMS ----------
             Tant qu'aucun SMS n'est parti pour de bon, on ne sait rien :
             ni si la clé est bonne, ni si le nom d'expéditeur a été
             validé chez CREATISINTER. Ce bouton envoie un VRAI SMS par
             le chemin exact de la production. */
          '<div class="carte">' +
            '<div class="carte-titre">' + UI.icone("tel", "ic-sm") +
              " Passerelle SMS</div>" +
            '<p class="aide" style="margin:-4px 0 12px">C\'est par elle que partent les ' +
              "codes de connexion des clients. Envoyez-vous un SMS d'essai : c'est le " +
              "seul moyen de savoir que la clé et le nom d'expéditeur sont bons avant " +
              "de les confier aux clients.</p>" +
            '<div class="champ"><label for="sms-numero">Numéro d\'essai</label>' +
              '<input id="sms-numero" type="tel" inputmode="tel" placeholder="01 97 12 15 96"' +
                ' value="' + Utils.echapper((courante || {}).tel || "") + '"></div>' +
            '<button type="button" class="btn btn-clair" id="sms-essayer">' +
              UI.icone("tel") + "Envoyer un essai</button>" +
            '<div id="sms-resultat"></div>' +
            '<p class="aide" style="margin:12px 0 0">La clé vit dans les secrets ' +
              "Supabase, jamais en base : elle n'est donc pas modifiable d'ici, et " +
              "n'apparaît dans aucune sauvegarde.</p>" +
          "</div>" +

          /* ---------- (3.70.0) Les SMS aux clients ----------
             Ceux que la notification de l'application ne touche pas —
             sans compte, venus de WhatsApp, iPhone ou navigateur —
             reçoivent un SMS aux étapes cochées. Un SMS coûte : coupé
             tant qu'on ne l'allume pas, et plafonné. */
          '<div class="carte" id="section-sms-clients">' +
            '<div class="carte-titre">' + UI.icone("tel", "ic-sm") + " SMS aux clients</div>" +
            '<p class="aide" style="margin:-4px 0 12px">Un client qui n\'a pas l\'application Android ' +
              "n'apprend où en est sa commande qu'en ouvrant son reçu : il est absent quand le livreur " +
              "arrive. Allumé, il reçoit un SMS court aux étapes cochées ci-dessous — avec le nom et le " +
              "numéro de son livreur. Les clients qui ont l'application reçoivent une notification, gratuite.</p>" +
            '<div id="sms-clients-zone"><span class="chargement-rond"></span> Lecture du réglage…</div>' +
          "</div>" +

          /* ---------- La connexion de l'équipe par SMS ----------
             Allumé, chaque compte de l'équipe rend un code reçu par SMS à
             chaque connexion. Il ne s'allume qu'après avoir soi-même reçu
             et rendu le sien : la base le refuse sinon, et l'écran le dit
             avant. Une passerelle qui ne livre pas fermerait la porte à
             toute l'équipe — à commencer par celui qui l'allume. */
          '<div class="carte" id="section-sms-equipe">' +
            '<div class="carte-titre">' + UI.icone("bouclier", "ic-sm") +
              " Code SMS du superadministrateur</div>" +
            '<p class="aide" style="margin:-4px 0 12px">Allumé, chaque <strong>superadministrateur</strong> ' +
              "reçoit un code par SMS en se connectant, en plus de son mot de passe — sauf sur un " +
              "appareil auquel il a fait confiance (un mois). Tant qu'il ne l'a pas saisi, la base " +
              "ne lui reconnaît <strong>aucun droit</strong>. Les autres comptes — administrateurs, " +
              "modérateurs, livreurs, clients — entrent avec leur mot de passe seul.</p>" +
            '<div id="sms-equipe-etat" class="aide" style="margin:0 0 12px">' +
              '<span class="chargement-rond"></span> Lecture de l\'équipe…</div>' +
            '<div id="sms-equipe-essai"></div>' +
            UI.interrupteur({ id: "sms-equipe-exige",
              label: "Exiger un code SMS des superadministrateurs", actif: false,
              aide: "Ne s\'allume qu\'après avoir reçu et saisi votre propre code." }) +
            '<button type="button" class="btn" id="sms-equipe-enregistrer">' + UI.icone("check") +
              "Enregistrer</button>" +
            '<p class="aide" style="margin:12px 0 0">En cas d\'urgence — plus de crédit SMS, ' +
              "et plus personne n'entre —, dans l'éditeur SQL de Supabase : " +
              "<code>update public.securite_equipe set sms_exige = false;</code></p>" +
            '<div id="sms-appareils" style="margin-top:12px"></div>' +
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
        /* Ce qui représente la boutique auprès des clients passe par
           BIZZOO : le dire AVANT la saisie, pas après l'enregistrement. */
        (surEnseigne || Supabase.estSuper()
          ? ""
          : '<div class="note-attente" style="margin-bottom:12px">' +
              UI.icone("bouclier", "ic-sm") +
              " Le nom, le logo, la présentation, l'adresse et les contacts sont envoyés " +
              "à BIZZOO pour validation. Le reste s'applique tout de suite.</div>") +
        (enAttente.length
          ? '<div class="note-attente" style="margin-bottom:12px">' +
              UI.icone("horloge", "ic-sm") + " En attente de BIZZOO : " +
              Utils.echapper(enAttente.map((d) => d.objet).join(" · ")) +
              ". Les valeurs ci-dessous restent celles d'aujourd'hui.</div>"
          : "") +
        UI.champTexte({ id: "r-nom", label: "Nom", valeur: r.nomBoutique, obligatoire: true }) +
        /* Le logo se règle ici, pas seulement depuis l'écran des
           boutiques : c'est la boutique qui sait à quoi elle ressemble.
           Elle le propose, l'enseigne l'approuve. */
        (surEnseigne
          ? ""
          : '<div class="champ"><label>Logo</label>' +
              '<div class="photos-zone" id="r-logo"></div>' +
              '<div class="aide">Une image remplace l\'icône chez le client. ' +
                "Carrée de préférence.</div></div>") +
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
        /* LES JOURS ET HEURES D'OUVERTURE (3.59.0) : ceux que l'application
           suit pour montrer, ou cacher, les produits. Une boutique qui ne
           les a pas encore posés reste ouverte en permanence. */
        (surEnseigne ? ""
          : (r.ouvertures ? ""
              : '<div class="note-attente" id="r-sans-horaires">' + UI.icone("horloge", "ic-sm") +
                  " Vos jours et heures d'ouverture ne sont pas encore posés : votre boutique " +
                  "paraît ouverte en permanence. Enregistrez-les ci-dessous.</div>") +
            UI.champsHoraires("r", r.ouvertures,
              "En dehors de ces heures, vos produits ne sont pas visibles des clients, et ils " +
              "ne peuvent pas vous commander.")) +
        /* SES CONDITIONS DE PAIEMENT ET SES FRAIS (3.59.0) : c'est la
           boutique qui les fixe. Une base d'avant ne les connaît pas. */
        (!surEnseigne && r.modePaiement !== undefined
          ? '<div class="titre-section" style="margin-top:14px">Paiement et livraison</div>' +
            UI.champsConditions("r", r)
          : "") +
        UI.champTexte({ id: "r-horaires", label: "Précisions sur les horaires (facultatif)", valeur: r.horaires,
          placeholder: "Ex. : fermé les jours fériés" }) +
        /* Le site web se saisit comme on le dit : « bizzoo.bj ». C'est
           l'application qui en fait une adresse ouvrable, comme pour
           Facebook ou Instagram — et l'aperçu montre laquelle, avant
           d'enregistrer. */
        UI.champTexte({ id: "r-site", label: "Site web", valeur: r.siteWeb,
          placeholder: "bizzoo.bj",
          aide: "Sans « https:// » si vous voulez : il est ajouté tout seul. " +
            "Laissez vide si vous n'avez pas de site." }) +
        '<div id="r-site-apercu"></div>' +
        '<button type="button" class="btn" id="r-enregistrer">' + UI.icone("check") + (surEnseigne ? "Enregistrer BIZZOO" : "Enregistrer la boutique") + "</button>" +
      "</div>" +

      /* ---------- Marge de BIZZOO ----------
         Elle appartient à l'enseigne, qui la pose en créant la boutique.
         La boutique la LIT — elle a le droit de savoir ce qu'on prend
         sur elle — mais ne la modifie pas : la base le refuse, et cet
         écran n'a donc rien à lui proposer. */
      (surEnseigne ? "" :
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("promo", "ic-sm") + " Marge de BIZZOO</div>" +
        '<div class="code-fige" style="margin-bottom:12px">' + UI.icone("bouclier", "ic-sm") +
          '<div><span class="code-produit">' + Utils.echapper(Utils.fmtTaux(r.tauxMarge)) +
            " %</span><br><small>Fixée par BIZZOO à la création de la boutique. " +
            "Elle ne se modifie pas ici.</small></div>" +
        "</div>" +
        '<p class="aide" style="margin:0">Vous indiquez sur chaque produit le ' +
          "<strong>prix BIZZOO</strong> — ce que vous touchez. L'application y ajoute ce " +
          "pourcentage et obtient le <strong>prix de vente</strong>, celui que voient les " +
          "clients." +
          (Supabase.estSuper()
            ? "<br>Pour le changer, passez par Boutiques → cette boutique."
            : "") +
        "</p>" +
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
            UI.icone("check") + "Enregistrer</button>" +
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
            UI.icone("check") + "Enregistrer</button>" +
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
          UI.icone("carte") + "Ma position actuelle</button>" +
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

      /* ---------- Publicité ----------
         Réservée à BIZZOO, et au superadministrateur seul : c'est
         l'enseigne qui met en avant, à travers toutes ses boutiques.
         L'écran cache la carte aux autres, mais c'est la règle de la
         base qui ferme vraiment la porte. */
      (surEnseigne && Supabase.estSuper()
        ? '<div class="carte">' +
            '<div class="carte-titre">' + UI.icone("promo", "ic-sm") + " Publicité " +
              '<span class="aide-inline">(BIZZOO)</span></div>' +
            '<p class="aide" style="margin:0 0 12px">Ce que BIZZOO met en avant sur l\'accueil de ' +
              "l'application, sous les boutiques — là où les ventes flash apparaissaient avant. " +
              "Chaque annonce est une photo ou une vidéo, et peut renvoyer vers un produit de " +
              "n'importe quelle boutique.</p>" +
            '<div id="reg-publicite"></div>' +
          "</div>"
        : "") +

      /* ---------- Paiement en ligne ----------
         La clé publique de KkiaPay vit EN BASE, pas dans le code des
         applications : c'est ce qui permet de passer des essais à la
         production sans reconstruire ni republier les APK.

         Il n'y a AUCUNE clé privée à saisir, ni ici ni ailleurs dans
         l'application. Ce qui protège l'argent est le secret du
         webhook, posé une fois pour toutes dans Supabase, sur le
         serveur — jamais dans un téléphone. */
      (surEnseigne && Supabase.estSuper()
        ? '<div class="carte" id="section-paiement">' +
            '<div class="carte-titre">' + UI.icone("energie", "ic-sm") + " Paiement en ligne</div>" +
            '<p class="aide" style="margin:0 0 12px">Ce réglage vaut pour <strong>toutes les ' +
              "boutiques de BIZZOO</strong>, et vous seul y touchez. Quand c'est ouvert, les " +
              "clients paient en ligne l'acompte de leur panier, et la commande arrive dans le " +
              "compte de chaque boutique concernée ; le reste se paie à la livraison. Tant que " +
              "c'est fermé, le panier existe toujours mais la commande part sur WhatsApp, " +
              "comme avant.</p>" +

            '<div class="champ"><label>Qui encaisse</label>' +
              '<div class="st-filtres" id="pay-fournisseurs">' +
                '<button type="button" class="puce active" data-fournisseur="feexpay">FeexPay</button>' +
                '<button type="button" class="puce" data-fournisseur="kkiapay">KkiaPay</button>' +
              "</div></div>" +

            /* ---- FeexPay ----
               Son jeton est un SECRET porteur : il n'a rien à faire dans
               une table que les clients lisent, ni dans un APK où il se
               lirait en clair. Il vit dans les secrets Supabase, posés
               une fois depuis un ordinateur. Il n'y a donc rien à saisir
               ici — et c'est voulu. */
            '<div id="pay-bloc-feexpay">' +
              '<div class="note-attente" style="margin:0 0 12px">' + UI.icone("alerte", "ic-sm") +
                " Rien à saisir ici : le jeton FeexPay est un secret, posé une fois sur un " +
                "ordinateur (<code>supabase secrets set FEEXPAY_TOKEN</code>) avec l'identifiant " +
                "de boutique. Voir README.md, section « Paiement en ligne ».</div>" +
              '<p class="aide" style="margin:0 0 12px"><strong>FeexPay n\'a pas de mode essai.</strong> ' +
                "Son bac à sable annonce un succès sans rien encaisser — s'y fier laisserait " +
                "n'importe qui se déclarer payé. Éprouvez avec un petit montant réel. " +
                "Frais au Bénin : 1,7 % en Mobile Money. La carte bancaire, que FeexPay annonce " +
                "à 4,5 %, n'est pas ouverte dans son API actuelle : vos clients paient par " +
                "Mobile Money (MTN, Moov, Celtiis).</p>" +
            "</div>" +

            /* ---- KkiaPay ---- */
            '<div id="pay-bloc-kkiapay" hidden>' +
              UI.champTexte({ id: "pay-cle", label: "Clé publique KkiaPay",
                valeur: "", placeholder: "d1a2b3c4-…",
                aide: "Tableau de bord KkiaPay → API KEYS. Cette clé est faite pour être publique ; " +
                      "ne saisissez JAMAIS la clé privée ici." }) +
              UI.interrupteur({ id: "pay-essai", label: "Mode essai (bac à sable)",
                actif: true,
                aide: "En essai, aucun argent n\'est prélevé et seuls les numéros de test " +
                      "passent (MTN 97000000, Moov 95000000). Attention : essai et production " +
                      "ont chacun leur clé ET leur webhook — les deux se changent ensemble." }) +
              '<div class="note-attente" style="margin:12px 0">' + UI.icone("alerte", "ic-sm") +
                " Le webhook doit être déclaré côté KkiaPay. Sans lui, l\'argent arrive mais " +
                "les commandes restent « en attente ».</div>" +
            "</div>" +

            /* ---- L'acompte à la commande ----
               Ce que le client paie en ligne pour que sa commande parte ;
               le reste se paie à la livraison. C'est ce qui écarte les
               commandes fictives : commander engage déjà de l'argent. La
               base le borne de 1 à 100 et ne laisse que vous l'écrire. */
            '<div class="champ" id="pay-bloc-acompte" hidden>' +
              '<label for="pay-acompte">Acompte proposé aux nouvelles boutiques</label>' +
              '<div class="champ-montant">' +
                '<input id="pay-acompte" inputmode="numeric" autocomplete="off" placeholder="10">' +
                '<span class="devise">%</span>' +
              "</div>" +
              '<div class="aide">Depuis la 3.59.0, <strong>chaque boutique règle sa propre ' +
                "condition de paiement</strong> (fiche de la boutique, ou ses Réglages). Ce taux " +
                "n'est plus que la valeur proposée à la création d'une boutique.</div>" +
            "</div>" +

            /* ---- Les frais de livraison ----
               Un montant par commande, ajouté au total. Aucun code promo
               ne les touche. Fixes pour l'instant ; ils dépendront plus
               tard de la distance. */
            '<div class="champ" id="pay-bloc-frais" hidden>' +
              '<label for="pay-frais">Frais de livraison proposés aux nouvelles boutiques</label>' +
              '<div class="champ-montant">' +
                '<input id="pay-frais" inputmode="numeric" autocomplete="off" placeholder="1000">' +
                '<span class="devise">FCFA</span>' +
              "</div>" +
              '<div class="aide">Depuis la 3.59.0, <strong>chaque boutique fixe ses frais de ' +
                "livraison</strong>. Ce montant n'est plus que la valeur proposée à la création " +
                "d'une boutique.</div>" +
            "</div>" +

            UI.interrupteur({ id: "pay-actif", label: "Ouvrir le paiement aux clients",
              actif: false,
              aide: "À n\'ouvrir qu\'une fois un paiement réussi de bout en bout." }) +
            '<button type="button" class="btn" id="pay-enregistrer">' + UI.icone("check") +
              "Enregistrer le paiement</button>" +
          "</div>"
        : "") +

      /* ---------- Le code MoMoPay de BIZZOO (3.59.0) ----------
         PLUS D'ESPÈCES À LA LIVRAISON : le reste se paie par MoMoPay, sur
         ce compte. Le livreur montre ce code et le montant au client, qui
         paie depuis son téléphone ; le livreur saisit le numéro de la
         transaction. Vous retrouvez ensuite chaque paiement dans la
         Caisse, « MoMoPay à vérifier ». */
      (surEnseigne && Supabase.estSuper()
        ? '<div class="carte" id="section-momopay">' +
            '<div class="carte-titre">' + UI.icone("promo", "ic-sm") + " MoMoPay — le reste à la livraison</div>" +
            '<p class="aide" style="margin:0 0 12px"><strong>Plus d\'espèces à la livraison.</strong> ' +
              "Le livreur montre ce code MoMoPay et le montant au client, qui paie depuis son " +
              "téléphone ; le livreur saisit ensuite le numéro de la transaction reçu par SMS. " +
              "Retrouvez chaque paiement dans <strong>Caisse → MoMoPay à vérifier</strong>.</p>" +
            UI.champTexte({ id: "momo-code", label: "Code marchand MoMoPay de BIZZOO", valeur: "",
              placeholder: "Exemple : 123456",
              aide: "Le code que vos clients saisissent pour vous payer. Il est fait pour être montré." }) +
            UI.champTexte({ id: "momo-nom", label: "Nom affiché du compte (facultatif)", valeur: "",
              placeholder: "BIZZOO",
              aide: "Le nom que le client voit à l'écran de paiement, pour être sûr de payer le bon compte." }) +
            '<button type="button" class="btn" id="momo-enregistrer">' + UI.icone("check") +
              "Enregistrer le code MoMoPay</button>" +
          "</div>"
        : "") +

      /* ---------- La livraison au kilomètre (3.64.0) ----------
         UN point de départ, celui de BIZZOO ; un forfait jusqu'au rayon,
         puis le kilomètre entamé, au tarif du véhicule. Tant que le point
         n'est pas réglé, rien ne change : chaque boutique garde ses frais.
         Le réglage vaut pour toute l'enseigne, et vous seul y touchez. */
      (surEnseigne && Supabase.estSuper()
        ? '<div class="carte" id="section-km">' +
            '<div class="carte-titre">' + UI.icone("voiture", "ic-sm") + " Livraison au kilomètre</div>" +
            '<div id="km-corps"><p class="aide" style="margin:0">Lecture…</p></div>' +
          "</div>"
        : "") +

      /* ---------- (3.70.0) Les préfixes des opérateurs ----------
         Ce qui fait corriger le réseau au paiement (Moov choisi, numéro
         MTN tapé → MTN) et repérer un numéro saisi à la place d'un ID de
         transaction. La liste vit dans la base : un nouveau préfixe
         attribué par l'ARCEP s'ajoute ici, sans nouvelle version. */
      (surEnseigne && Supabase.estSuper()
        ? '<div class="carte" id="section-prefixes">' +
            '<div class="carte-titre">' + UI.icone("tel", "ic-sm") + " Préfixes des opérateurs</div>" +
            '<p class="aide" style="margin:0 0 12px">Les deux chiffres après « 01 » disent le réseau ' +
              "d'un numéro. Les applications s'en servent pour corriger le réseau choisi au paiement, " +
              "et pour signaler un numéro tapé à la place d'un ID de transaction. Quand MTN, Moov ou " +
              "Celtiis annoncent de nouveaux numéros, ajoutez leur préfixe ici : les applications le " +
              "prennent à leur prochaine ouverture, sans mise à jour.</p>" +
            '<div id="prefixes-corps"><p class="aide" style="margin:0">Lecture…</p></div>' +
          "</div>"
        : "") +

      /* ---------- Un compte pour commander ----------
         Le seul réglage de l'application qui puisse FERMER la caisse.
         Il mérite donc son avertissement : tant qu'aucune porte
         d'inscription n'est réellement ouverte — la confirmation par
         e-mail qui part, ou le SMS qui arrive — l'allumer reviendrait
         à renvoyer un client qui n'a aucun moyen d'ouvrir un compte.

         Comme ailleurs : l'écran cache l'interrupteur aux autres, mais
         c'est la règle de la base qui ferme vraiment la porte. */
      (surEnseigne && Supabase.estSuper()
        ? '<div class="carte" id="section-regles">' +
            '<div class="carte-titre">' + UI.icone("personne", "ic-sm") +
              " Un compte pour commander</div>" +
            '<p class="aide" style="margin:0 0 12px">Ce réglage vaut pour <strong>toutes les ' +
              "boutiques de BIZZOO</strong>, et vous seul y touchez. Fermé, on commande avec " +
              "un simple numéro, comme depuis le premier jour. Ouvert, plus une commande sans " +
              "compte — le client ouvre le sien avant de valider son panier.</p>" +
            '<p class="aide" style="margin:0 0 12px">Ce qu\'un compte apporte : la commande se ' +
              "retrouve d'un téléphone à l'autre, l'avis n'est donné que par qui a payé, et la " +
              "réclamation a un interlocuteur. Le catalogue, lui, reste ouvert à tous : " +
              "<strong>on ferme la caisse, pas le magasin</strong>.</p>" +
            '<div class="note-attente" style="margin:0 0 12px">' + UI.icone("alerte", "ic-sm") +
              " À n'ouvrir qu'une fois une porte d'inscription éprouvée de bout en bout : " +
              "un e-mail de confirmation qui arrive vraiment, ou le SMS branché " +
              "(README.md, section « Vérification du numéro »). Sans cela, vous renverriez " +
              "un client qui n'a aucun moyen d'ouvrir un compte.</div>" +
            UI.interrupteur({ id: "reg-compte-obligatoire",
              label: "Exiger un compte pour commander", actif: false,
              aide: "Le refus est posé dans la base, pas seulement à l\'écran." }) +
            '<button type="button" class="btn" id="reg-regles-enregistrer">' + UI.icone("check") +
              "Enregistrer la règle</button>" +
          "</div>"
        : "") +

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
          '<a class="btn btn-clair" href="#/livreurs">' + UI.icone("voiture") + "Gérer les livreurs</a>" +
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
        /* Côte à côte, un mot chacun : la carte s'appelle déjà
           « Sauvegarde », et « Exporter une sauvegarde » se pliait sur
           deux lignes en grands caractères. */
        '<div class="btn-duo">' +
          '<button type="button" class="btn btn-clair" id="s-exporter">' + UI.icone("telecharger") + "Exporter</button>" +
          '<label class="btn btn-clair" for="s-importer-fichier">' + UI.icone("televerser") + "Restaurer" +
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

    if (UI.$("#km-corps")) brancherLivraisonKm(() => moi === generation);
    if (UI.$("#prefixes-corps")) brancherPrefixes(() => moi === generation);

    const boutonMomo = UI.$("#momo-enregistrer");
    if (boutonMomo) {
      Store.lirePaiement().then((p) => {
        if (moi !== generation || !UI.$("#momo-code")) return;
        if (p.momopayCode === null) {
          UI.$("#section-momopay").innerHTML = '<div class="carte-titre">MoMoPay</div>' +
            '<p class="aide" style="margin:0">Exécutez d\'abord le fichier supabase/reste-momopay.sql.</p>';
          return;
        }
        UI.$("#momo-code").value = p.momopayCode;
        UI.$("#momo-nom").value = p.momopayNom;
      }).catch(() => {});
      boutonMomo.onclick = async () => {
        boutonMomo.disabled = true;
        try {
          const code = await Store.majMomopay(UI.$("#momo-code").value, UI.$("#momo-nom").value);
          UI.toast(code ? "Code MoMoPay enregistré : " + code : "Code MoMoPay retiré.", "ok");
        } catch (err) {
          UI.toast(err.message, "err");
        }
        boutonMomo.disabled = false;
      };
    }

    const boutonPaiement = UI.$("#pay-enregistrer");
    if (boutonPaiement) {
      /* La carte est déjà à l'écran ; ses valeurs arrivent ensuite. Faire
         attendre TOUT l'écran pour une lecture secondaire le remplacerait
         sous les doigts de qui a commencé à saisir ailleurs. */
      /* Un seul agrégateur à la fois : montrer les réglages des deux
         laisserait croire qu'on saisit pour celui qui n'encaisse pas. */
      const puces = UI.$$("#pay-fournisseurs .puce");
      const montrer = (quel) => {
        for (const puce of puces) {
          puce.classList.toggle("active", puce.dataset.fournisseur === quel);
        }
        const bf = UI.$("#pay-bloc-feexpay");
        const bk = UI.$("#pay-bloc-kkiapay");
        if (bf) bf.hidden = quel !== "feexpay";
        if (bk) bk.hidden = quel !== "kkiapay";
      };
      const choisi = () => {
        const actif = UI.$("#pay-fournisseurs .puce.active");
        return actif ? actif.dataset.fournisseur : "feexpay";
      };
      for (const puce of puces) puce.onclick = () => montrer(puce.dataset.fournisseur);

      /* La carte est déjà à l'écran ; ses valeurs arrivent ensuite. Faire
         attendre TOUT l'écran pour une lecture secondaire le remplacerait
         sous les doigts de qui a commencé à saisir ailleurs. */
      Store.lirePaiement().then((p) => {
        if (moi !== generation) return;   // un autre écran a pris la main
        const cle = UI.$("#pay-cle");
        if (!cle) return;
        cle.value = p.clePublique;
        UI.$("#pay-essai").checked = p.bacASable;
        UI.$("#pay-actif").checked = p.actif;
        montrer(p.fournisseur || "feexpay");
        /* Le champ de l'acompte n'apparaît que si la base le connaît. */
        if (p.tauxAcompte != null) {
          UI.$("#pay-acompte").value = String(p.tauxAcompte);
          UI.$("#pay-bloc-acompte").hidden = false;
        }
        if (p.fraisLivraison != null) {
          UI.$("#pay-frais").value = String(p.fraisLivraison);
          UI.$("#pay-bloc-frais").hidden = false;
        }
      }).catch(() => { /* base d'avant les achats intégrés : carte vide */ });

      boutonPaiement.onclick = async () => {
        const fournisseur = choisi();
        const cle = UI.$("#pay-cle").value.trim();
        const actif = UI.$("#pay-actif").checked;
        /* Ouvrir KkiaPay sans clé afficherait un bouton « Payer » qui ne
           ferait rien : le client croirait à une panne de son téléphone.
           FeexPay, lui, n'a rien à saisir ici — c'est l'Edge Function qui
           dira si son jeton est en place. */
        if (actif && fournisseur === "kkiapay" && !cle) {
          UI.toast("Saisissez d'abord la clé publique KkiaPay", "err");
          UI.$("#pay-cle").focus();
          return;
        }
        /* L'acompte : un nombre entier de 1 à 100. Le refuser ici dit
           pourquoi ; la base, elle, le refuserait sans phrase. */
        const blocAcompte = UI.$("#pay-bloc-acompte");
        let tauxAcompte = null;
        if (blocAcompte && !blocAcompte.hidden) {
          const brut = UI.$("#pay-acompte").value.trim().replace(/\s|%/g, "");
          tauxAcompte = /^\d{1,3}$/.test(brut) ? Number(brut) : NaN;
          if (!(tauxAcompte >= 1 && tauxAcompte <= 100)) {
            UI.toast("L'acompte se règle entre 1 et 100 %", "err");
            UI.$("#pay-acompte").focus();
            return;
          }
        }
        const blocFrais = UI.$("#pay-bloc-frais");
        let fraisLivraison = null;
        if (blocFrais && !blocFrais.hidden) {
          const brut = UI.$("#pay-frais").value.trim().replace(/\s|fcfa/gi, "");
          fraisLivraison = /^\d{1,6}$/.test(brut) ? Number(brut) : NaN;
          if (!(fraisLivraison >= 0 && fraisLivraison <= 100000)) {
            UI.toast("Les frais de livraison vont de 0 à 100 000 FCFA", "err");
            UI.$("#pay-frais").focus();
            return;
          }
        }
        boutonPaiement.disabled = true;
        try {
          await Store.majPaiement({
            actif, fournisseur, clePublique: cle,
            bacASable: UI.$("#pay-essai").checked,
            tauxAcompte, fraisLivraison,
          });
          const nom = fournisseur === "feexpay" ? "FeexPay" : "KkiaPay";
          UI.toast((actif
            ? "Paiement ouvert par " + nom
              + (fournisseur === "kkiapay" && UI.$("#pay-essai").checked ? " (mode essai)" : "")
            : "Paiement en ligne fermé")
            + (tauxAcompte != null && tauxAcompte < 100
              ? " — acompte de " + tauxAcompte + " %" : ""), "ok");
        } catch (err) {
          UI.toast(err.message, "err");
        }
        boutonPaiement.disabled = false;
      };
    }

    /* ---------- Un compte pour commander ---------- */
    const boutonRegles = UI.$("#reg-regles-enregistrer");
    if (boutonRegles) {
      /* Même façon de faire que le paiement : la carte est déjà à
         l'écran, sa valeur arrive ensuite. */
      Store.lireRegles().then((r) => {
        if (moi !== generation) return;   // un autre écran a pris la main
        const interrupteur = UI.$("#reg-compte-obligatoire");
        if (!interrupteur) return;
        interrupteur.checked = r.compteObligatoire;
      }).catch(() => { /* base d'avant cette règle : interrupteur éteint */ });

      boutonRegles.onclick = async () => {
        const exige = UI.$("#reg-compte-obligatoire").checked;
        /* Fermer la caisse mérite qu'on redemande : c'est le seul
           réglage de cette application qui puisse arrêter une vente. */
        if (exige && !await UI.confirmer({
          titre: "Exiger un compte pour commander ?",
          texte: "À partir de maintenant, un client sans compte ne pourra plus " +
                 "valider son panier : il devra d'abord en ouvrir un. " +
                 "Assurez-vous qu'une inscription aboutit vraiment — e-mail de " +
                 "confirmation reçu, ou SMS branché.",
          bouton: "Exiger un compte", danger: true,
        })) {
          /* On renonce : l'interrupteur revient où il était, sinon
             l'écran montrerait une règle qui n'a pas été enregistrée. */
          UI.$("#reg-compte-obligatoire").checked = false;
          return;
        }
        boutonRegles.disabled = true;
        try {
          await Store.majRegles({ compteObligatoire: exige });
          UI.toast(exige
            ? "Un compte est désormais exigé pour commander"
            : "La commande sans compte est de nouveau permise", "ok");
        } catch (err) {
          UI.toast(err.message, "err");
        }
        boutonRegles.disabled = false;
      };
    }

    if (params && params.section === "regles") {
      const section = UI.$("#section-regles");
      if (section) setTimeout(() => section.scrollIntoView({ behavior: "smooth", block: "start" }), 60);
    }

    if (params && params.section === "compte") {
      const section = UI.$("#section-compte");
      if (section) setTimeout(() => section.scrollIntoView({ behavior: "smooth", block: "start" }), 60);
    }

    /* ---------- Logo de la boutique ---------- */
    let logoTravail = surEnseigne ? null : (r.logo ? { chemin: r.logo } : null);
    let logoTouche = false;
    const zoneLogo = UI.$("#r-logo", vue);
    if (zoneLogo) {
      const rendreLogo = () => {
        const apercu = logoTravail
          ? (logoTravail.dataUrl || Supabase.urlImage(logoTravail.chemin))
          : "";
        zoneLogo.innerHTML = apercu
          ? '<div class="photo-boite">' +
              '<img src="' + Utils.echapper(apercu) + '" alt="Logo">' +
              '<button type="button" class="photo-retirer" id="r-logo-retirer" ' +
                'aria-label="Retirer le logo">' + UI.icone("fermer", "ic-sm") + "</button>" +
            "</div>"
          : '<label class="photo-ajout">' + UI.icone("camera") + "<span>Ajouter</span>" +
              '<input type="file" accept="image/*" hidden id="r-logo-fichier"></label>';
        const champ = UI.$("#r-logo-fichier", zoneLogo);
        if (champ) {
          champ.addEventListener("change", async () => {
            const fichier = champ.files && champ.files[0];
            if (!fichier) return;
            try {
              const { dataUrl } = await Utils.compresserImage(fichier, 600, 0.85);
              logoTravail = { dataUrl };
              logoTouche = true;
            } catch (err) {
              UI.toast(err.message || "Image illisible", "err");
            }
            rendreLogo();
          });
        }
        const retirer = UI.$("#r-logo-retirer", zoneLogo);
        if (retirer) retirer.onclick = () => { logoTravail = null; logoTouche = true; rendreLogo(); };
      };
      rendreLogo();
    }

    /* ---------- Le site web, et où il mène ----------
       Le gérant voit l'adresse exacte avant d'enregistrer — et, si ce
       qu'il a tapé n'en est pas une, il le lit ici plutôt que de le
       découvrir chez un client. */
    const montrerApercuSite = () => {
      const zone = UI.$("#r-site-apercu");
      if (!zone) return;
      const saisi = UI.$("#r-site").value.trim();
      const lien = Utils.lienSite(saisi);
      zone.innerHTML = !saisi ? ""
        : lien
          ? '<a class="lien-copiable" style="margin:8px 0 12px" target="_blank" ' +
            'rel="noopener" href="' + Utils.echapper(lien) + '">' +
              UI.icone("lien", "ic-sm") + "<span>" + Utils.echapper(lien) + "</span></a>"
          : '<p class="aide" style="margin:8px 0 12px;color:var(--rouge)">' +
            "Cela ne ressemble pas à une adresse de site — il y manque un point " +
            "(« bizzoo.bj »). Tel quel, aucun lien ne sera montré aux clients.</p>";
    };
    if (UI.$("#r-site")) {
      UI.$("#r-site").addEventListener("input", Utils.tempo(montrerApercuSite, 300));
      montrerApercuSite();
    }

    /* UN SEUL ENVOI À LA FOIS, sur chaque bouton de cet écran. Ce qui
       demande un accord part en DEMANDE : un double appui en déposait
       deux, que le superadmin avait ensuite à valider l'une après
       l'autre — et un logo changé partait deux fois au stockage. */
    const unSeulEnvoi = async (bouton, action) => {
      bouton.disabled = true;
      try {
        await action();
      } finally {
        bouton.disabled = false;
      }
    };

    /* ---------- Boutique ---------- */
    UI.brancherConditions(vue, "r");
    UI.$("#r-enregistrer").onclick = () => unSeulEnvoi(UI.$("#r-enregistrer"), async () => {
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
          ...(surEnseigne ? {} : { ouvertures: UI.lireHoraires(vue, "r") }),
          ...(surEnseigne || r.modePaiement === undefined ? {} : UI.lireConditions(vue, "r")),
          siteWeb: UI.$("#r-site").value.trim(),
          /* Le logo ne part que s'il a bougé : sinon chaque
             enregistrement demanderait une validation pour rien. */
          ...(logoTouche ? { logo: logoTravail } : {}),
        }, (surEnseigne ? "Coordonnées de BIZZOO modifiées" : "Informations de la boutique modifiées"));
        /* Nom, description, adresse et contacts peuvent être partis en
           demande : le dire, plutôt que d'annoncer une mise en ligne
           qui n'a pas eu lieu. */
        const envoi = Store.dernierEnvoiValidation();
        if (envoi) {
          UI.toast("Envoyé à BIZZOO pour validation : " + envoi.objet, "ok");
          afficher(vue, params);
        } else {
          UI.toast((surEnseigne ? "BIZZOO enregistrée" : "Boutique enregistrée") +
            " — visible immédiatement chez les clients.", "ok");
        }
      } catch (err) {
        UI.toast(err.message, "err");
      }
    });

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

    UI.$("#r-tels-enregistrer").onclick = () => unSeulEnvoi(UI.$("#r-tels-enregistrer"), async () => {
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
    });

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

    UI.$("#r-adresses-enregistrer").onclick = () => unSeulEnvoi(UI.$("#r-adresses-enregistrer"), async () => {
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
    });

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

    UI.$("#rs-enregistrer").onclick = () => unSeulEnvoi(UI.$("#rs-enregistrer"), async () => {
      try {
        const maj = {};
        for (const [cle] of RESEAUX) maj[cle] = UI.$("#rs-" + cle).value.trim();
        await enregistrer(maj, "Réseaux sociaux mis à jour");
        UI.toast("Réseaux enregistrés — visibles chez les clients", "ok");
      } catch (err) {
        UI.toast(err.message, "err");
      }
    });

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

    UI.$("#loc-enregistrer").onclick = () => unSeulEnvoi(UI.$("#loc-enregistrer"), async () => {
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
    });

    /* ---------- Enseigne ou boutique : la bascule ---------- */
    for (const bouton of UI.$$("[data-cible]", vue)) {
      bouton.onclick = () => {
        cible = bouton.dataset.cible;
        afficher(vue, params);
      };
    }

    /* ---------- L'essai de la passerelle SMS ----------
       On montre la réponse ENTIÈRE de CREATISINTER, pas seulement notre
       verdict : un code « INVALID_SENDERID » ou « MISSING_PARAMETERS_TO »
       nomme lui-même ce qui manque, là où « l'envoi a échoué » ferait
       chercher partout. */
    const essaiSms = UI.$("#sms-essayer", vue);
    if (essaiSms) {
      essaiSms.onclick = async () => {
        const numero = UI.$("#sms-numero", vue).value;
        const zone = UI.$("#sms-resultat", vue);
        if (numero.replace(/\D/g, "").length < 8) {
          return UI.toast("Tapez le numéro qui doit recevoir l'essai.", "err");
        }
        essaiSms.disabled = true;
        zone.innerHTML = '<div class="aide" style="margin-top:12px">' +
          '<span class="chargement-rond"></span> Envoi en cours…</div>';
        try {
          const r = await Supabase.fonctionEdge("tester-sms", { numero });
          zone.innerHTML =
            '<div class="sms-verdict ' + (r.ok ? "sms-ok" : "sms-ko") + '">' +
              UI.icone(r.ok ? "check" : "alerte", "ic-sm") +
              "<div><strong>" + Utils.echapper(r.ok ? "SMS accepté" : "Envoi refusé") +
                "</strong><br>" + Utils.echapper(r.message || "") +
                (r.code ? "<br><small>Code : " + Utils.echapper(r.code) + "</small>" : "") +
                (r.expediteur
                  ? "<br><small>Expéditeur : " + Utils.echapper(r.expediteur) + "</small>"
                  : "") +
              "</div></div>" +
            /* La réponse brute, repliée : inutile au quotidien,
               indispensable le jour où rien ne marche. */
            '<details class="sms-brut"><summary>Réponse de la passerelle</summary>' +
              "<pre>" + Utils.echapper(JSON.stringify(r.reponse_passerelle, null, 2)) +
            "</pre></details>";
          UI.toast(r.ok ? "SMS envoyé — regardez le téléphone" : "Envoi refusé", r.ok ? "ok" : "err");
        } catch (err) {
          zone.innerHTML = '<div class="sms-verdict sms-ko">' + UI.icone("alerte", "ic-sm") +
            "<div>" + Utils.echapper(err.message) + "</div></div>";
          UI.toast(err.message, "err");
        }
        essaiSms.disabled = false;
      };
    }

    /* ---------- La connexion de l'équipe par SMS ----------
       L'état vient de la base, la liste de l'équipe aussi : on dit qui
       n'a pas de numéro AVANT qu'on exige le code, pas après qu'il est
       resté dehors. */
    const carteSmsEquipe = UI.$("#section-sms-equipe", vue);
    if (carteSmsEquipe) {
      const nomDuCompte = (c) => c.nom || c.email || "un compte";
      const chiffres = (c) => String(c.tel || "").replace(/\D/g, "");

      const dessinerSmsEquipe = async () => {
        const zoneEtat = UI.$("#sms-equipe-etat", vue);
        const zoneEssai = UI.$("#sms-equipe-essai", vue);
        const interrupteur = UI.$("#sms-equipe-exige", vue);
        const bouton = UI.$("#sms-equipe-enregistrer", vue);
        if (!zoneEtat || !interrupteur || !bouton) return;

        let etat = null;
        let comptes = [];
        try {
          [etat, comptes] = await Promise.all([Supabase.etatConnexion(), Store.listerComptes()]);
        } catch (err) {
          if (moi !== generation) return;
          zoneEtat.textContent = err.message || "Lecture impossible.";
          return;
        }
        if (moi !== generation || !zoneEtat.isConnected) return;

        if (!etat) {
          zoneEtat.innerHTML = "Cette nouveauté demande la mise à jour de la base : " +
            "exécutez <strong>supabase/connexion-sms.sql</strong> dans Supabase (SQL Editor).";
          interrupteur.disabled = true;
          bouton.disabled = true;
          return;
        }

        /* (3.59.0) Le code ne vaut plus que pour les superadministrateurs. */
        const actifs = comptes.filter((c) => c.actif && c.role === "superadministrateur");
        const avecNumero = actifs.filter((c) => chiffres(c).length >= 8);
        const confirmes = avecNumero.filter((c) => c.telVerifie);
        const sansNumero = actifs.filter((c) => chiffres(c).length < 8);
        zoneEtat.innerHTML =
          "<strong>" + (etat.sms_exige ? "Exigé des superadministrateurs." : "Pas exigé pour l'instant.") +
          "</strong><br>" +
          avecNumero.length + " superadministrateur" + (avecNumero.length > 1 ? "s" : "") +
          " sur " + actifs.length + " " +
          (avecNumero.length > 1 ? "ont" : "a") + " un numéro ; " + confirmes.length + " " +
          (confirmes.length > 1 ? "l'ont" : "l'a") + " déjà confirmé par un code." +
          (sansNumero.length
            ? '<span class="sms-equipe-manque">Sans numéro, ' +
              (sansNumero.length > 1 ? "ces superadministrateurs ne pourraient" : "ce superadministrateur ne pourrait") +
              " plus entrer : " + sansNumero.map((c) => Utils.echapper(nomDuCompte(c))).join(", ") +
              '. <a href="#/comptes">Ajoutez-le dans Comptes</a>.</span>'
            : "");

        interrupteur.checked = !!etat.sms_exige;
        bouton.disabled = false;
        if (etat.session_confirmee) {
          zoneEssai.innerHTML = '<div class="sms-verdict sms-ok">' + UI.icone("check", "ic-sm") +
            "<div>Votre connexion est confirmée par SMS : la passerelle livre bien les codes.</div></div>";
          interrupteur.disabled = false;
        } else if (!etat.numero) {
          zoneEssai.innerHTML = '<div class="sms-verdict sms-ko">' + UI.icone("alerte", "ic-sm") +
            "<div>Votre propre compte n'a pas de numéro : ajoutez-le dans Comptes avant " +
            "d'exiger le code de qui que ce soit.</div></div>";
          interrupteur.disabled = !etat.sms_exige;
        } else {
          zoneEssai.innerHTML =
            '<p class="aide" style="margin:0 0 8px">D\'abord, recevez un code sur votre numéro ' +
              "(qui finit par " + Utils.echapper(etat.fin_numero || "") + ") et saisissez-le : " +
              "c'est la preuve que les codes arrivent.</p>" +
            '<div id="sms-equipe-bloc"></div>';
          VueConnexion.blocCode(UI.$("#sms-equipe-bloc", vue), {
            libelle: "Recevoir un code",
            apres: () => {
              UI.toast("Code reçu et saisi : la passerelle livre", "ok");
              dessinerSmsEquipe();
            },
          });
          /* L'allumer sans preuve : la base le refuserait. L'éteindre
             reste toujours possible. */
          interrupteur.disabled = !etat.sms_exige;
        }
      };
      dessinerSmsEquipe();

      /* SES APPAREILS DE CONFIANCE : combien, et « tous les oublier ». */
      const dessinerAppareils = async () => {
        const zone = UI.$("#sms-appareils", vue);
        if (!zone) return;
        const n = await Supabase.mesAppareilsConfiance();
        if (!zone.isConnected) return;
        zone.innerHTML = n
          ? '<p class="aide" style="margin:0 0 8px">' + n + " appareil" + (n > 1 ? "s" : "") +
              " de confiance : le code n'y est pas demandé jusqu'à un mois après la confiance donnée.</p>" +
            '<button type="button" class="btn btn-clair" id="sms-appareils-oublier">' +
              UI.icone("fermer") + "Oublier mes appareils de confiance</button>"
          : "";
        const oublier = UI.$("#sms-appareils-oublier", zone);
        if (oublier) {
          oublier.onclick = async () => {
            oublier.disabled = true;
            try {
              await Supabase.oublierAppareils();
              UI.toast("Appareils oubliés : le code sera redemandé à la prochaine connexion.", "ok");
            } catch (err) {
              UI.toast(err.message, "err");
            }
            dessinerAppareils();
          };
        }
      };
      dessinerAppareils();

      UI.$("#sms-equipe-enregistrer", vue).onclick = async () => {
        const bouton = UI.$("#sms-equipe-enregistrer", vue);
        const exige = UI.$("#sms-equipe-exige", vue).checked;
        if (exige && !await UI.confirmer({
          titre: "Exiger un code SMS des superadministrateurs ?",
          texte: "Dès maintenant, chaque superadministrateur devra saisir un code reçu par " +
                 "SMS en se connectant — sauf sur un appareil de confiance. Un " +
                 "superadministrateur sans numéro ne pourra plus entrer.",
          bouton: "Exiger le code", danger: true,
        })) {
          UI.$("#sms-equipe-exige", vue).checked = false;
          return;
        }
        bouton.disabled = true;
        try {
          await Supabase.reglerSmsEquipe(exige);
          UI.toast(exige ? "Le code SMS est exigé des superadministrateurs"
                         : "Le code SMS n'est plus exigé", "ok");
        } catch (err) {
          UI.toast(err.message, "err");
        }
        await dessinerSmsEquipe();
      };
    }

    /* ---------- (3.70.0) Les SMS aux clients ---------- */
    const zoneSmsClients = UI.$("#sms-clients-zone", vue);
    if (zoneSmsClients) {
      const ETAPES_SMS = [
        ["commande_payee", "Commande payée", "« Votre commande BZ-… est confirmée. Nous la préparons. »"],
        ["course_acceptee", "Livreur trouvé", "Son nom et son numéro : le plus utile."],
        ["commande_en_livraison", "Colis en route", "« Gardez votre téléphone à portée. »"],
        ["commande_remise", "Colis livré", "« Merci de votre confiance ! »"],
        ["commande_annulee", "Article annulé", "Un ou plusieurs articles annulés."],
      ];
      const dessinerSmsClients = async () => {
        let r;
        try {
          r = await Supabase.rpc("sms_commandes_reglages", {});
        } catch (err) {
          if (moi !== generation || !zoneSmsClients.isConnected) return;
          zoneSmsClients.innerHTML = /sms_commandes_reglages|schema cache|does not exist/i.test(err.message || "")
            ? "Cette nouveauté demande la mise à jour de la base : exécutez <strong>supabase/sms-clients.sql</strong> " +
              "dans Supabase (SQL Editor)."
            : Utils.echapper(err.message || "Lecture impossible.");
          return;
        }
        if (moi !== generation || !zoneSmsClients.isConnected) return;
        if (!r || typeof r !== "object") {
          zoneSmsClients.innerHTML = "Cette nouveauté demande la mise à jour de la base : exécutez " +
            "<strong>supabase/sms-clients.sql</strong> dans Supabase (SQL Editor).";
          return;
        }
        const etapes = r.etapes || [];
        const a = r.aujourdhui || {};
        zoneSmsClients.innerHTML =
          '<div class="aide" style="margin:0 0 10px"><strong>' +
            (r.actif ? "Allumés" + (r.actif_depuis ? " depuis le " + Utils.echapper(UI.dateHeure ? UI.dateHeure(r.actif_depuis) : new Date(r.actif_depuis).toLocaleString("fr-FR")) : "") + "."
                     : "Coupés : aucun SMS ne part.") + "</strong>" +
            " Aujourd'hui : " + (a.envoyes || 0) + " envoyé(s), " + (a.en_attente || 0) + " en attente, " +
            (a.refuses || 0) + " refusé(s)." +
            (r.dernier_refus ? '<span class="sms-equipe-manque">Dernier refus : ' +
              Utils.echapper(r.dernier_refus.code || "") + " — " + Utils.echapper(r.dernier_refus.message || "") + "</span>" : "") +
            (r.branche ? "" : '<span class="sms-equipe-manque">La fonction d\'envoi n\'est pas encore branchée ' +
              "(adresse de « envoyer-sms-commande » à poser dans la base) : rien ne partira.</span>") +
          "</div>" +
          UI.interrupteur({ id: "smsc-actif", label: "Envoyer des SMS aux clients", actif: !!r.actif,
            aide: "Seules les commandes payées APRÈS l'allumage sont concernées." }) +
          '<div class="carte-titre" style="margin-top:12px;font-size:14px">Aux étapes</div>' +
          ETAPES_SMS.map(([cle, libelle, aide]) =>
            UI.interrupteur({ id: "smsc-" + cle, label: libelle, actif: etapes.includes(cle), aide })).join("") +
          '<div class="carte-titre" style="margin-top:12px;font-size:14px">À qui</div>' +
          UI.interrupteur({ id: "smsc-sans-compte", label: "Clients sans compte", actif: r.sans_compte !== false,
            aide: "Commande passée sans se connecter : personne d'autre ne peut les prévenir." }) +
          UI.interrupteur({ id: "smsc-whatsapp", label: "Commandes prises sur WhatsApp", actif: r.whatsapp !== false,
            aide: "Saisies par l'équipe avec « Faire livrer »." }) +
          UI.interrupteur({ id: "smsc-sans-appareil", label: "Clients avec compte, sans l'application Android",
            actif: r.sans_appareil !== false, aide: "iPhone ou navigateur : la notification ne les réveille pas." }) +
          '<div class="champ-ligne" style="display:flex;gap:12px;flex-wrap:wrap;margin-top:8px">' +
            '<div class="champ"><label for="smsc-plafond">Au plus, par commande</label>' +
              '<input id="smsc-plafond" type="number" min="0" max="10" value="' + Number(r.plafond ?? 3) + '"></div>' +
            '<div class="champ"><label for="smsc-plafond-jour">Au plus, par jour</label>' +
              '<input id="smsc-plafond-jour" type="number" min="0" max="5000" value="' + Number(r.plafond_jour ?? 300) + '"></div>' +
          "</div>" +
          '<button type="button" class="btn" id="smsc-enregistrer">' + UI.icone("check") + "Enregistrer</button>" +
          '<p class="aide" style="margin:12px 0 0">Le compte des SMS, jour par jour, est dans BIZZOO Personnel ' +
            "(Suivi des commandes → SMS). Un crédit SMS épuisé y apparaît aussitôt.</p>";
        UI.$("#smsc-enregistrer", vue).onclick = async (ev) => {
          const coche = (id) => !!(UI.$("#" + id, vue) || {}).checked;
          const bouton = ev.currentTarget;
          bouton.disabled = true;
          try {
            await Supabase.rpc("regler_sms_commandes", {
              actif: coche("smsc-actif"),
              plafond: Number(UI.$("#smsc-plafond", vue).value),
              plafond_jour: Number(UI.$("#smsc-plafond-jour", vue).value),
              etapes: ETAPES_SMS.map(([cle]) => cle).filter((cle) => coche("smsc-" + cle)),
              sans_compte: coche("smsc-sans-compte"), whatsapp: coche("smsc-whatsapp"),
              sans_appareil: coche("smsc-sans-appareil"),
            });
            UI.toast(coche("smsc-actif") ? "SMS aux clients enregistrés" : "SMS aux clients coupés", "ok");
          } catch (err) {
            UI.toast(err.message, "err");
          }
          await dessinerSmsClients();
        };
      };
      dessinerSmsClients();
    }

    /* ---------- Slider ----------
       Le même gestionnaire que l'écran Slider, posé dans la carte. */
    const zoneSlider = UI.$("#reg-slider", vue);
    if (zoneSlider) VueSlider.rendre(zoneSlider, surEnseigne ? "enseigne" : "boutique");

    /* ---------- Publicité ----------
       Le même gestionnaire encore, sur la troisième vitrine. */
    const zonePublicite = UI.$("#reg-publicite", vue);
    if (zonePublicite) VueSlider.rendre(zonePublicite, "publicite");

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
