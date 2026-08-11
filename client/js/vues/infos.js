/* =========================================================
   Infos — coordonnées de la boutique, installation de
   l'application, à propos.
   ========================================================= */
const VueInfos = (() => {

  async function afficher(vue) {
    const b = Catalogue.boutique();
    UI.entete({ titre: "Infos boutique", sous: b.slogan });

    let html = "";

    html +=
      '<div class="carte carte-boutique">' +
        UI.logo() +
        (b.description ? '<p class="boutique-desc">' + Utils.echapper(b.description) + "</p>" : "") +
        '<span class="chip-slogan">' + Utils.echapper(b.slogan) + "</span>" +
      "</div>";

    if (b.photos && b.photos.length) {
      html +=
        '<div class="carte">' +
          '<div class="carte-titre">Notre boutique</div>' +
          '<div class="boutique-photos">' +
            b.photos.map((url, i) =>
              '<img src="' + Utils.echapper(url) + '" alt="Photo de la boutique ' + (i + 1) +
              '" data-photo-boutique="' + i + '"' + (i > 0 ? ' loading="lazy"' : "") + ">").join("") +
          "</div>" +
        "</div>";
    }

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
    if (b.adresse) {
      contacts.push(
        '<a class="ligne-info" target="_blank" rel="noopener" href="' +
          (b.latitude !== null && b.longitude !== null
            ? "https://www.google.com/maps/search/?api=1&query=" + b.latitude + "," + b.longitude
            : "https://maps.google.com/?q=" + encodeURIComponent(b.adresse)) + '">' +
          '<span class="rond-bleu">' + UI.icone("carte") + "</span>" +
          "<span><strong>Adresse</strong><br><small>" + Utils.echapper(b.adresse) + "</small></span>" +
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
    if (b.facebook) {
      const lien = /^https?:/.test(b.facebook) ? b.facebook : "https://facebook.com/" + b.facebook;
      contacts.push(
        '<a class="ligne-info" target="_blank" rel="noopener" href="' + Utils.echapper(lien) + '">' +
          '<span class="rond-bleu">' + UI.icone("facebook") + "</span>" +
          "<span><strong>Facebook</strong><br><small>Suivez nos arrivages</small></span>" +
          UI.icone("chevron", "ic-sm") +
        "</a>");
    }

    html += '<div class="carte">' +
      '<div class="carte-titre">Nous contacter</div>' +
      (contacts.length
        ? contacts.join("")
        : '<p class="aide" style="margin:0">Les coordonnées de la boutique seront bientôt disponibles.</p>') +
    "</div>";

    html +=
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
          'Tél : <a href="' + Utils.echapper(Utils.lienTel("0196202098", "229")) + '">01 96 20 20 98</a></div>' +
      "</div>";

    vue.innerHTML = html;

    const serieBoutique = (b.photos || []).map((src) => ({ src }));
    for (const img of UI.$$("[data-photo-boutique]", vue)) {
      img.addEventListener("click", () =>
        UI.ouvrirVisionneuse(serieBoutique, Number(img.dataset.photoBoutique) || 0));
    }

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
    if (App.evenementInstallation) {
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

  return { afficher };
})();
