/* =========================================================
   BIZZOO — le SAV à l'écran

   On y arrive depuis le reçu d'une commande PAYÉE : c'est là
   que le client est quand il constate le problème, et c'est la
   commande qui prouve l'achat.

   L'écran suit la règle sans jamais la garder : le bouton
   « Demander BIZZOO » ne s'affiche que lorsque la base dit que
   le recours est ouvert. Si l'écran se trompait, la base
   refuserait — mais un bouton qui refuse est pire qu'un bouton
   absent : il promet quelque chose.
   ========================================================= */

const VueSAV = (() => {

  /* ---------- Le bloc posé sur un reçu ---------- */

  /** Ce qu'on ajoute au reçu d'une commande payée. */
  function blocReçu(commande) {
    if (!commande || commande.etat !== "payee") return "";
    if (typeof Compte === "undefined" || !Compte.connecte()) return "";
    return '<div class="carte" id="sav-bloc">' +
      '<div id="sav-corps"><span class="chargement-rond"></span></div></div>';
  }

  /** Remplir ce bloc : les réclamations en cours, ou l'invitation. */
  async function remplirReçu(commande) {
    const zone = UI.$("#sav-corps");
    if (!zone) return;
    let liste = [];
    try { liste = await SAV.pourCommande(commande.id); } catch (_) { /* hors ligne */ }
    if (!UI.$("#sav-corps")) return;

    if (!liste.length) {
      zone.innerHTML =
        '<div class="carte-titre">' + UI.icone("alerte", "ic-sm") +
          " Un problème avec cette commande ?</div>" +
        '<p class="aide" style="margin:0 0 10px">Rien reçu, article abîmé, commande ' +
          "incomplète ? Signalez-le à la boutique : c'est elle qui a la marchandise " +
          "et qui peut remplacer le jour même.</p>" +
        '<button type="button" class="btn btn-clair" id="sav-ouvrir">' +
          UI.icone("alerte") + "Signaler un problème</button>";
      UI.$("#sav-ouvrir").addEventListener("click", () => formulaire(commande));
      return;
    }

    zone.innerHTML =
      '<div class="carte-titre">' + UI.icone("alerte", "ic-sm") +
        " Réclamation" + (liste.length > 1 ? "s" : "") + "</div>" +
      liste.map((r) =>
        '<a class="sav-resume" href="#/reclamation/' + Utils.echapper(r.id) + '">' +
          "<div><strong>" + Utils.echapper(SAV.SUJETS[r.sujet] || SAV.SUJETS.autre) + "</strong>" +
          '<div class="sav-quand">' + Utils.echapper(Utils.fmtDateHeure(r.creeLe)) + "</div></div>" +
          badge(r) +
        "</a>").join("") +
      '<button type="button" class="btn btn-clair" id="sav-ouvrir" style="margin-top:10px">' +
        UI.icone("alerte") + "Signaler autre chose</button>";
    UI.$("#sav-ouvrir").addEventListener("click", () => formulaire(commande));
  }

  const badge = (r) => {
    const e = SAV.ETATS[r.etat] || SAV.ETATS.ouverte;
    return '<span class="badge ' + e.classe + '">' + Utils.echapper(e.nom) + "</span>";
  };

  /* ---------- Ouvrir une réclamation ---------- */

  function formulaire(commande) {
    /* Les articles de la commande : désigner celui qui pose problème
       aide la boutique bien plus qu'une description. « Toute la
       commande » reste possible — « rien reçu » ne vise aucun article. */
    const articles = [];
    for (const g of (commande.boutiques || [])) {
      for (const l of (g.lignes || [])) {
        if (l.produitId || l.produit_id) {
          articles.push({ id: l.produitId || l.produit_id, nom: l.nom });
        }
      }
    }

    UI.entete({ titre: "Signaler un problème", retour: true, sous: commande.numero });
    UI.$("#vue").innerHTML =
      '<div class="carte">' +
        '<p class="aide" style="margin:0 0 12px">Votre message part à la boutique. ' +
          "Si elle ne répond pas sous 48 heures, ou si sa réponse ne vous convient " +
          "pas, vous pourrez demander à BIZZOO de trancher.</p>" +
        '<div class="champ"><label for="sav-sujet">Que se passe-t-il ?</label>' +
          '<select id="sav-sujet">' +
            Object.entries(SAV.SUJETS).map(([cle, texte]) =>
              '<option value="' + cle + '">' + Utils.echapper(texte) + "</option>").join("") +
          "</select></div>" +
        (articles.length
          ? '<div class="champ"><label for="sav-article">Quel article ?</label>' +
            '<select id="sav-article"><option value="">Toute la commande</option>' +
              articles.map((a) =>
                '<option value="' + Utils.echapper(a.id) + '">' +
                Utils.echapper(a.nom) + "</option>").join("") +
            "</select></div>"
          : "") +
        '<div class="champ"><label for="sav-message">Dites-nous tout</label>' +
          '<textarea id="sav-message" rows="4" maxlength="2000" ' +
            'placeholder="Ce qui s\'est passé, et ce que vous attendez"></textarea></div>' +
        '<button type="button" class="btn" id="sav-envoyer">' + UI.icone("check") +
          "Envoyer à la boutique</button>" +
      "</div>";

    UI.$("#sav-envoyer").addEventListener("click", async () => {
      const message = UI.$("#sav-message").value.trim();
      if (!message) return UI.toast("Décrivez le problème.", "alerte");
      const bouton = UI.$("#sav-envoyer");
      bouton.disabled = true;
      try {
        const r = await SAV.ouvrir(
          commande.id,
          articles.length ? UI.$("#sav-article").value : "",
          UI.$("#sav-sujet").value, message);
        UI.toast("Envoyé à la boutique.");
        location.hash = "#/reclamation/" + r.id;
      } catch (err) {
        UI.toast(err.message, "alerte");
        bouton.disabled = false;
      }
    });
  }

  /* ---------- Le fil d'une réclamation ---------- */

  async function fil(vue, id) {
    UI.entete({ titre: "Réclamation", retour: true });
    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>' +
      "Lecture…</div>";

    if (typeof Compte === "undefined" || !Compte.connecte()) {
      VueCompte.revenirVers("#/reclamation/" + id);
      location.hash = "#/connexion";
      return;
    }

    let liste = [], messages = [], recours = false;
    try {
      liste = await SAV.mesReclamations();
      messages = await SAV.messages(id);
      recours = await SAV.recoursPossible(id);
    } catch (_) { /* on affichera ce qu'on a */ }

    const r = liste.find((x) => x.id === id);
    if (!r) {
      vue.innerHTML = UI.vide("alerte", "Réclamation introuvable",
        "Elle n'appartient pas à ce compte, ou la connexion manque.",
        '<a class="btn btn-clair" href="#/mes-commandes">Mes commandes</a>');
      return;
    }

    UI.entete({ titre: SAV.SUJETS[r.sujet] || "Réclamation", retour: true,
      sous: SAV.ETATS[r.etat] ? SAV.ETATS[r.etat].nom : "" });

    const close = r.etat === "resolue" || r.etat === "tranchee";

    vue.innerHTML =
      '<div class="carte">' +
        '<div class="sav-entete">' + badge(r) +
          '<span class="sav-quand">Ouverte le ' +
            Utils.echapper(Utils.fmtDateHeure(r.creeLe)) + "</span></div>" +
        (r.etat === "ouverte"
          ? '<p class="aide" style="margin:10px 0 0">La boutique a 48 heures pour vous ' +
            "répondre. Passé ce délai, vous pourrez demander à BIZZOO de trancher.</p>"
          : "") +
        (r.etat === "escaladee"
          ? '<p class="aide" style="margin:10px 0 0">' + UI.icone("horloge", "ic-sm") +
            " BIZZOO a été saisie et examine votre dossier.</p>"
          : "") +
      "</div>" +
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("infos", "ic-sm") + " Le fil</div>" +
        (messages.length
          ? messages.map(messageHtml).join("")
          : '<p class="aide" style="margin:0">Rien encore.</p>') +
      "</div>" +
      (close
        ? '<div class="carte sav-close">' + UI.icone("check", "ic-sm") +
          "<div>" + (r.etat === "tranchee"
            ? "<strong>BIZZOO a tranché.</strong> Sa décision est dans le fil ci-dessus."
            : "<strong>Vous avez marqué ce problème comme réglé.</strong>") +
          "</div></div>"
        : '<div class="carte">' +
            '<div class="champ"><label for="sav-reponse">Répondre</label>' +
              '<textarea id="sav-reponse" rows="3" maxlength="2000" ' +
                'placeholder="Votre message"></textarea></div>' +
            '<button type="button" class="btn" id="sav-repondre">' + UI.icone("check") +
              "Envoyer</button>" +
          "</div>" +
          '<div class="carte">' +
            '<button type="button" class="btn btn-clair" id="sav-regle">' +
              UI.icone("check") + "C'est réglé, je ferme</button>" +
            /* LE BOUTON DU RECOURS. Il n'apparaît que lorsque la BASE dit
               qu'il est ouvert : la boutique a répondu, ou elle n'a pas
               répondu passé le délai. Avant, il n'y aurait rien à
               contester — et un bouton qui refuse promet pour rien. */
            (recours && r.etat !== "escaladee"
              ? '<button type="button" class="btn btn-clair sav-recours-btn" ' +
                'id="sav-escalader" style="margin-top:10px">' + UI.icone("alerte") +
                "Demander à BIZZOO de trancher</button>" +
                '<p class="aide" style="margin:8px 0 0">BIZZOO lira tout le fil et ' +
                "décidera. Sa décision s'impose à la boutique.</p>"
              : r.etat === "escaladee" ? ""
              : '<p class="aide" style="margin:8px 0 0">' + UI.icone("horloge", "ic-sm") +
                " Si la boutique ne répond pas sous 48 heures, vous pourrez demander " +
                "à BIZZOO de trancher.</p>") +
          "</div>");

    const repondre = UI.$("#sav-repondre", vue);
    if (repondre) {
      repondre.addEventListener("click", async () => {
        const texte = UI.$("#sav-reponse", vue).value.trim();
        if (!texte) return UI.toast("Écrivez votre message.", "alerte");
        repondre.disabled = true;
        try {
          await SAV.repondre(id, texte);
          await fil(vue, id);
        } catch (err) {
          UI.toast(err.message, "alerte");
          repondre.disabled = false;
        }
      });
    }

    const regle = UI.$("#sav-regle", vue);
    if (regle) {
      regle.addEventListener("click", async () => {
        regle.disabled = true;
        try {
          await SAV.clore(id);
          UI.toast("Merci, c'est noté.");
          await fil(vue, id);
        } catch (err) {
          UI.toast(err.message, "alerte");
          regle.disabled = false;
        }
      });
    }

    const escalader = UI.$("#sav-escalader", vue);
    if (escalader) {
      escalader.addEventListener("click", async () => {
        const motif = (UI.$("#sav-reponse", vue) || {}).value || "";
        escalader.disabled = true;
        try {
          await SAV.escalader(id, motif.trim());
          UI.toast("BIZZOO a été saisie.");
          await fil(vue, id);
        } catch (err) {
          UI.toast(err.message, "alerte");
          escalader.disabled = false;
        }
      });
    }
  }

  function messageHtml(m) {
    const qui = m.auteur_role === "boutique" ? "La boutique"
      : m.auteur_role === "enseigne" ? "BIZZOO" : (m.auteur_nom || "Vous");
    return (
      '<div class="sav-message sav-de-' + Utils.echapper(m.auteur_role) + '">' +
        '<div class="sav-message-qui">' +
          UI.icone(m.auteur_role === "boutique" ? "magasin"
            : m.auteur_role === "enseigne" ? "check" : "compte", "ic-sm") +
          "<strong>" + Utils.echapper(qui) + "</strong>" +
          '<span class="sav-quand">' + Utils.echapper(Utils.fmtDateHeure(m.cree_le)) + "</span>" +
        "</div>" +
        '<p class="sav-message-texte">' + Utils.echapper(m.texte) + "</p>" +
      "</div>"
    );
  }

  /* ---------- Toutes mes réclamations ---------- */

  async function mesReclamations(vue) {
    UI.entete({ titre: "Mes réclamations", retour: true });
    if (typeof Compte === "undefined" || !Compte.connecte()) {
      VueCompte.revenirVers("#/reclamations");
      location.hash = "#/connexion";
      return;
    }
    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>' +
      "Lecture…</div>";

    let liste = [];
    try { liste = await SAV.mesReclamations(); } catch (_) { /* hors ligne */ }

    if (!liste.length) {
      vue.innerHTML = UI.vide("check", "Aucune réclamation",
        "Un problème avec une commande ? Ouvrez-la et signalez-le : la boutique " +
        "vous répond, et BIZZOO tranche si besoin.",
        '<a class="btn btn-clair" href="#/mes-commandes">Mes commandes</a>');
      return;
    }

    vue.innerHTML = liste.map((r) =>
      '<a class="carte sav-resume" href="#/reclamation/' + Utils.echapper(r.id) + '">' +
        "<div><strong>" + Utils.echapper(SAV.SUJETS[r.sujet] || SAV.SUJETS.autre) + "</strong>" +
        '<div class="sav-quand">' + Utils.echapper(Utils.fmtDateHeure(r.creeLe)) + "</div></div>" +
        badge(r) +
      "</a>").join("");
  }

  return { blocReçu, remplirReçu, fil, mesReclamations };
})();
