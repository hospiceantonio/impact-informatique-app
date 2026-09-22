/* =========================================================
   Infos — coordonnées de la boutique, installation de
   l'application, à propos.
   ========================================================= */
const VueInfos = (() => {

  async function afficher(vue) {
    const b = Catalogue.boutique();
    /* Tant qu'aucune boutique n'est choisie, c'est l'enseigne qui parle :
       BIZZOO a ses propres coordonnées. */
    const enseigne = b.estEnseigne;
    /* On y entre depuis l'écran du compte : c'est « À propos de
       BIZZOO ». Les coordonnées d'UNE boutique sont dans l'onglet
       « À propos » de sa fiche. */
    UI.entete({ titre: enseigne ? "À propos de BIZZOO" : "Infos boutique",
      sous: enseigne ? "" : b.nom, retour: true });

    let html = UI.bandeauBoutique();

    html +=
      '<div class="carte carte-boutique">' +
        (enseigne
          ? UI.logo()
          : '<h2 class="boutique-nom">' + Utils.echapper(b.nom) + "</h2>") +
        /* La note que les acheteurs lui ont donnée À ELLE : la
           livraison, l'accueil, le sérieux. L'enseigne, elle, ne se
           note pas — on note des boutiques, pas une galerie. */
        (!enseigne && b.nbAvis
          ? '<div class="boutique-note">' + UI.noteHtml(b, { grand: true }) + "</div>"
          : "") +
        (b.description ? '<p class="boutique-desc">' + Utils.echapper(b.description) + "</p>" : "") +
        (b.slogan ? '<span class="chip-slogan">' + Utils.echapper(b.slogan) + "</span>" : "") +
      "</div>";

    html += htmlPhotos(b, enseigne) + htmlVideo(b) + htmlContacts(b);

    /* Depuis l'enseigne, on redescend vers les boutiques et leurs
       coordonnées à elles. */
    if (enseigne && Catalogue.boutiques().length) {
      html +=
        '<div class="carte">' +
          '<div class="carte-titre">' + UI.icone("magasin", "ic-sm") + " Nos boutiques</div>" +
          '<p class="aide" style="margin:0 0 12px">Chaque boutique a ses propres horaires, ' +
            "son adresse et son numéro. Ouvrez-en une pour les voir.</p>" +
          Catalogue.boutiques().map((x) =>
            '<a class="ligne-info" href="#/boutique/' + Utils.echapper(x.id) + '">' +
              (x.logo
                ? '<span class="bou-rond bou-rond-photo"><img src="' + Utils.echapper(x.logo) + '" alt=""></span>'
                : '<span class="bou-rond" style="background:' + Utils.echapper(x.couleur) + '">' +
                  UI.icone(x.icone) + "</span>") +
              "<span><strong>" + Utils.echapper(x.nom) + "</strong><br><small>" +
                Utils.echapper(x.secteur || "Voir la boutique") + "</small></span>" +
              UI.icone("chevron", "ic-sm") +
            "</a>").join("") +
        "</div>";
    }

    html += htmlReseaux(b);
    html += htmlFin();

    vue.innerHTML = html;

    /* Les avis de la boutique : ce que les acheteurs disent d'ELLE. Sur
       l'écran de l'enseigne il n'y a rien à noter — BIZZOO ne vend pas,
       ce sont ses boutiques qui vendent. */
    if (!enseigne && b.id) {
      UI.$("#vue").insertAdjacentHTML("beforeend", VueAvis.bloc("Avis sur cette boutique"));
      VueAvis.remplir({ boutique: b.id }, async () => { await Catalogue.rafraichir(); });
    }

    brancherPhotos(vue, b);
    brancherFin();
  }

  /* ---------- Les morceaux ----------
     L'écran « Infos » et l'onglet « À propos » de la fiche d'une
     boutique montrent les mêmes choses — photos, vidéo, coordonnées,
     réseaux. Ils sont écrits une fois, ici, et les deux s'en servent :
     deux copies finiraient par dire deux adresses différentes. */

  function htmlPhotos(b, enseigne) {
    if (!b.photos || !b.photos.length) return "";
    return (
      '<div class="carte">' +
        '<div class="carte-titre">' + (enseigne ? "En images" : "Notre boutique") + "</div>" +
        '<div class="boutique-photos">' +
          b.photos.map((url, i) =>
            '<img src="' + Utils.echapper(url) + '" alt="Photo de la boutique ' + (i + 1) +
            '" data-photo-boutique="' + i + '"' + (i > 0 ? ' loading="lazy"' : "") + ">").join("") +
        "</div>" +
      "</div>"
    );
  }

  /* La visite filmée, si le gérant en a déposé une. */
  function htmlVideo(b) {
    if (!b.video) return "";
    return (
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("video", "ic-sm") + " Vidéo de présentation</div>" +
        '<video class="video-lecture" src="' + Utils.echapper(b.video) +
        '" controls preload="metadata" playsinline></video>' +
      "</div>"
    );
  }

  function brancherPhotos(zone, b) {
    const serie = (b.photos || []).map((src) => ({ src }));
    for (const img of UI.$$("[data-photo-boutique]", zone)) {
      img.addEventListener("click", () =>
        UI.ouvrirVisionneuse(serie, Number(img.dataset.photoBoutique) || 0));
    }
  }

  function htmlContacts(b) {
    const contacts = [];
    if (b.whatsapp) {
      contacts.push(
        '<a class="ligne-info" target="_blank" rel="noopener" href="' +
          Utils.echapper(Utils.lienWhatsApp(b.whatsapp, "Bonjour " + b.nom + " 👋", b.indicatif)) + '">' +
          '<span class="rond-wa">' + UI.icone("whatsapp") + "</span>" +
          "<span><strong>WhatsApp</strong><br><small>" + Utils.echapper(b.whatsapp) + "</small></span>" +
          UI.icone("chevron", "ic-sm") +
        "</a>");
    }
    if (b.tel) {
      contacts.push(
        '<a class="ligne-info" href="' + Utils.echapper(Utils.lienTel(b.tel, b.indicatif)) + '">' +
          '<span class="rond-bleu">' + UI.icone("tel") + "</span>" +
          "<span><strong>Téléphone</strong><br><small>" + Utils.echapper(b.tel) + "</small></span>" +
          UI.icone("chevron", "ic-sm") +
        "</a>");
    }
    /* Les autres numéros de la boutique : atelier, service après-vente… */
    for (const t of b.telephones || []) {
      const nom = t.libelle || (t.whatsapp ? "Autre WhatsApp" : "Autre numéro");
      contacts.push(t.whatsapp
        ? '<a class="ligne-info" target="_blank" rel="noopener" href="' +
            Utils.echapper(Utils.lienWhatsApp(t.numero, "Bonjour " + b.nom + " 👋", b.indicatif)) + '">' +
            '<span class="rond-wa">' + UI.icone("whatsapp") + "</span>" +
            "<span><strong>" + Utils.echapper(nom) + "</strong><br><small>" +
              Utils.echapper(t.numero) + " · WhatsApp</small></span>" +
            UI.icone("chevron", "ic-sm") +
          "</a>"
        : '<a class="ligne-info" href="' + Utils.echapper(Utils.lienTel(t.numero, b.indicatif)) + '">' +
            '<span class="rond-bleu">' + UI.icone("tel") + "</span>" +
            "<span><strong>" + Utils.echapper(nom) + "</strong><br><small>" +
              Utils.echapper(t.numero) + "</small></span>" +
            UI.icone("chevron", "ic-sm") +
          "</a>");
    }

    if (b.latitude !== null && b.longitude !== null) {
      const point = b.latitude + "," + b.longitude;
      contacts.push(
        '<a class="ligne-info" target="_blank" rel="noopener" ' +
          'href="https://www.google.com/maps/dir/?api=1&destination=' + point + '">' +
          '<span class="rond-bleu">' + UI.icone("itineraire") + "</span>" +
          "<span><strong>Itinéraire vers la boutique</strong><br>" +
          "<small>Ouvre le guidage sur votre téléphone</small></span>" +
          UI.icone("chevron", "ic-sm") +
        "</a>");
    }
    /* Une adresse ouvre le plan : sur ses coordonnées si on les a,
       sur son texte sinon. */
    const lienCarte = (texte, latitude, longitude) =>
      (latitude !== null && longitude !== null
        ? "https://www.google.com/maps/search/?api=1&query=" + latitude + "," + longitude
        : "https://maps.google.com/?q=" + encodeURIComponent(texte));

    if (b.adresse) {
      contacts.push(
        '<a class="ligne-info" target="_blank" rel="noopener" href="' +
          Utils.echapper(lienCarte(b.adresse, b.latitude, b.longitude)) + '">' +
          '<span class="rond-bleu">' + UI.icone("carte") + "</span>" +
          "<span><strong>Adresse</strong><br><small>" + Utils.echapper(b.adresse) + "</small></span>" +
          UI.icone("chevron", "ic-sm") +
        "</a>");
    }

    /* Les autres adresses : annexe, dépôt, second point de vente… */
    for (const a of b.adresses || []) {
      const situee = a.latitude !== null && a.longitude !== null;
      contacts.push(
        '<a class="ligne-info" target="_blank" rel="noopener" href="' +
          Utils.echapper(lienCarte(a.texte, a.latitude, a.longitude)) + '">' +
          '<span class="rond-bleu">' + UI.icone("carte") + "</span>" +
          "<span><strong>" + Utils.echapper(a.libelle || "Autre adresse") + "</strong><br><small>" +
            Utils.echapper(a.texte) + (situee ? " · itinéraire disponible" : "") + "</small></span>" +
          UI.icone("chevron", "ic-sm") +
        "</a>");
    }
    if (b.horaires) {
      contacts.push(
        '<div class="ligne-info">' +
          '<span class="rond-bleu">' + UI.icone("horloge") + "</span>" +
          "<span><strong>Horaires</strong><br><small>" + Utils.echapper(b.horaires) + "</small></span>" +
        "</div>");
    }

    /* LE SITE WEB. On affiche l'adresse telle qu'elle a été saisie —
       « bizzoo.bj » se lit mieux que « https://bizzoo.bj » — mais le
       lien, lui, porte l'adresse complète. Une saisie qui n'est pas
       une adresse ne donne rien : « lienSite » rend « », et la ligne
       ne paraît pas, plutôt que d'offrir un lien mort. */
    const site = Utils.lienSite(b.siteWeb);
    if (site) {
      contacts.push(
        '<a class="ligne-info" target="_blank" rel="noopener" href="' +
          Utils.echapper(site) + '">' +
          '<span class="rond-bleu">' + UI.icone("globe") + "</span>" +
          "<span><strong>Site web</strong><br><small>" +
            Utils.echapper(b.siteWeb.replace(/^https?:\/\//i, "")) + "</small></span>" +
          UI.icone("chevron", "ic-sm") +
        "</a>");
    }

    return (
      '<div class="carte">' +
        '<div class="carte-titre">Nous contacter</div>' +
        (contacts.length
          ? contacts.join("")
          : '<p class="aide" style="margin:0">Les coordonnées seront bientôt disponibles.</p>') +
      "</div>"
    );
  }

  function htmlReseaux(b) {
    const reseaux = ["facebook", "instagram", "tiktok", "youtube", "snapchat"]
      .map((cle) => ({ cle, lien: Utils.lienReseau(cle, b[cle]) }))
      .filter((r) => r.lien);
    if (!reseaux.length) return "";
    return (
      '<div class="carte">' +
        '<div class="carte-titre">Suivez-nous</div>' +
        '<p class="aide" style="margin:0 0 14px">Arrivages, promotions et nouveautés en avant-première.</p>' +
        '<div class="reseaux">' +
          reseaux.map((r) =>
            '<a class="reseau reseau-' + r.cle + '" target="_blank" rel="noopener" href="' +
              Utils.echapper(r.lien) + '">' +
              '<span class="reseau-rond">' + UI.icone(r.cle) + "</span>" +
              "<span>" + Utils.echapper(Utils.RESEAUX[r.cle].nom) + "</span>" +
            "</a>").join("") +
        "</div>" +
      "</div>"
    );
  }

  /* L'installation, le réglage de la base en démonstration, et le mot
     de la fin : cela appartient à l'application, pas à une boutique. */
  function htmlFin() {
    let html =
      '<div class="carte" id="carte-installation">' +
        '<div class="carte-titre">Installer l\'application</div>' +
        '<p class="aide" style="margin:0 0 12px">Gardez le catalogue dans votre poche : il s\'ouvre en plein écran et reste consultable même sans connexion.</p>' +
        '<div id="zone-installer"></div>' +
        '<details class="bloc-aide"><summary>Comment faire ?</summary>' +
          "<p><strong>Android (Chrome)</strong> : menu ⋮ puis « Ajouter à l'écran d'accueil » ou « Installer l'application ».</p>" +
          "<p><strong>iPhone (Safari)</strong> : bouton Partager puis « Sur l'écran d'accueil ».</p>" +
        "</details>" +
      "</div>";

    if (Catalogue.modeDemo()) {
      html +=
        '<div class="carte">' +
          '<div class="carte-titre">Connexion à la boutique</div>' +
          '<p class="aide" style="margin:0 0 12px">L\'application affiche pour l\'instant un catalogue de démonstration. ' +
            "Collez ici l'adresse et la clé du projet Supabase de la boutique pour voir le vrai catalogue.</p>" +
          '<div class="champ-config"><input id="cfg-url" type="url" placeholder="https://….supabase.co" autocomplete="off"></div>' +
          '<div class="champ-config"><input id="cfg-cle" type="text" placeholder="Clé « anon public »" autocomplete="off"></div>' +
          '<button type="button" class="btn" id="cfg-enregistrer" style="margin-top:10px">' +
            UI.icone("check") + "Se connecter à la boutique</button>" +
        "</div>";
    }

    const maj = Catalogue.versionPubliee();
    html +=
      '<div class="carte">' +
        '<div class="carte-titre">À propos</div>' +
        '<p class="aide" style="margin:0">' +
          "Catalogue mis à jour le " + Utils.echapper(maj ? Utils.fmtDateHeure(new Date(maj).getTime()) : "—") + ".<br>" +
          "Les prix sont donnés à titre indicatif et confirmés à la commande." +
        "</p>" +
        '<div class="credit-dev">Application développée par <strong>CREATIS INTER</strong><br>' +
          'Tél : <a href="' + Utils.echapper(Utils.lienTel("0196202098", "229")) + '">01 96 20 20 98</a><br>' +
          '<a href="https://www.creatisinter.com" target="_blank" rel="noopener">www.creatisinter.com</a></div>' +
      "</div>";
    return html;
  }

  function brancherFin() {
    const btnConfig = UI.$("#cfg-enregistrer");
    if (btnConfig) {
      btnConfig.onclick = () => {
        const url = UI.$("#cfg-url").value.trim();
        const cle = UI.$("#cfg-cle").value.trim();
        if (!/^https:\/\//.test(url) || !cle) {
          UI.toast("Indiquez l'adresse https://… et la clé du projet.", "err");
          return;
        }
        Catalogue.majConfiguration(url, cle);
        UI.toast("Connexion enregistrée !", "ok");
        setTimeout(() => location.reload(), 600);
      };
    }

    /* Bouton d'installation direct quand le navigateur le permet. */
    const zone = UI.$("#zone-installer");
    if (zone && App.evenementInstallation) {
      zone.innerHTML = '<button type="button" class="btn" id="btn-installer">' +
        UI.icone("installer") + "Installer maintenant</button>";
      UI.$("#btn-installer").onclick = async () => {
        const ev = App.evenementInstallation;
        if (!ev) return;
        ev.prompt();
        const choix = await ev.userChoice.catch(() => null);
        if (choix && choix.outcome === "accepted") {
          UI.toast("Application installée !", "ok");
          App.evenementInstallation = null;
          zone.innerHTML = "";
        }
      };
    }
  }

  /**
   * L'onglet « À propos » de la fiche d'une boutique : sa présentation,
   * ses photos, sa vidéo, ses coordonnées et ses réseaux. Le nom, le
   * logo et la note sont déjà en tête de la fiche ; les avis ont leur
   * propre onglet.
   */
  function aPropos(zone) {
    const b = Catalogue.boutique();
    zone.innerHTML =
      (b.description
        ? '<div class="carte"><div class="carte-titre">Présentation</div>' +
            '<p class="boutique-desc" style="margin:0">' + Utils.echapper(b.description) + "</p></div>"
        : "") +
      htmlPhotos(b, false) + htmlVideo(b) + htmlContacts(b) + htmlReseaux(b);
    brancherPhotos(zone, b);
  }

  return { afficher, aPropos };
})();
