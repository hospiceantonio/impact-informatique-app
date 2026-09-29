/* =========================================================
   BIZZOO — le bloc des avis

   Le même bloc sert la fiche d'un produit et l'écran d'une
   boutique : on y lit les avis, et l'on y donne le sien quand on
   a acheté. Deux écrans, un seul code — les règles sont les
   mêmes des deux côtés, et les écrire deux fois, c'est les voir
   diverger.

   CE QUE CE BLOC NE FAIT PAS : décider qui a le droit d'écrire.
   Il demande à la base (« a_achete »), et la base revérifie de
   toute façon au dépôt. Cacher le formulaire n'est qu'une
   politesse — on n'affiche pas un bouton qui sera refusé.
   ========================================================= */

const VueAvis = (() => {

  /** Le squelette, posé tout de suite ; les avis arrivent après. */
  function bloc(titre) {
    return (
      '<div class="carte" id="av-bloc">' +
        '<div class="carte-titre">' + UI.icone("etoile", "ic-sm") + " " +
          Utils.echapper(titre) + "</div>" +
        '<div id="av-corps"><span class="chargement-rond"></span></div>' +
      "</div>"
    );
  }

  /** Un avis, tel qu'il se lit. */
  function avisHtml(a, mien) {
    const quand = a.maj_le || a.cree_le;
    return (
      '<div class="av-un' + (mien ? " av-mien" : "") + '" data-av-id="' +
        Utils.echapper(a.id) + '">' +
        '<div class="av-entete">' +
          "<div>" +
            '<span class="av-auteur">' + Utils.echapper(a.auteur || "Client") + "</span>" +
            (mien ? '<span class="av-vous">vous</span>' : "") +
            '<div class="av-quand">' + Utils.echapper(Utils.fmtDateHeure(quand)) + "</div>" +
          "</div>" +
          UI.etoiles(a.note, { chiffre: false }) +
        "</div>" +
        (a.texte ? '<p class="av-texte">' + Utils.echapper(a.texte) + "</p>" : "") +
        /* La réponse de la boutique se lit sous l'avis, décalée : c'est
           une conversation, pas un second avis. */
        (a.reponse
          ? '<div class="av-reponse">' + UI.icone("magasin", "ic-sm") +
            "<div><strong>Réponse de la boutique</strong><br>" +
            Utils.echapper(a.reponse) + "</div></div>"
          : "") +
        (mien
          ? '<div class="btn-rangee av-actions">' +
              '<button type="button" class="btn-mini" id="av-modifier">Modifier</button>' +
              '<button type="button" class="btn-mini av-retirer" id="av-retirer">Retirer</button>' +
            "</div>"
          : '<div class="btn-rangee av-actions">' +
              '<button type="button" class="btn-mini" data-av-signaler="avis">Signaler l’avis</button>' +
              '<button type="button" class="btn-mini" data-av-signaler="auteur">Signaler l’auteur</button>' +
              '<button type="button" class="btn-mini" data-av-masquer="' +
                Utils.echapper(a.client_id) + '">Masquer cet auteur</button>' +
            "</div>") +
      "</div>"
    );
  }

  function formulaireSignalement(id, cible) {
    return '<form class="av-signalement" data-av-report-form="' + Utils.echapper(id) +
      '" data-av-cible="' + Utils.echapper(cible) + '">' +
      '<label>Pourquoi signaler ' + (cible === "auteur" ? "cet auteur" : "cet avis") + ' ?' +
        '<select name="motif" required>' +
          '<option value="">Choisir un motif</option>' +
          '<option value="harcelement">Harcèlement ou menace</option>' +
          '<option value="haine">Haine ou discrimination</option>' +
          '<option value="sexuel">Contenu sexuel</option>' +
          '<option value="donnees_personnelles">Données personnelles exposées</option>' +
          '<option value="spam">Spam ou publicité</option>' +
          '<option value="autre">Autre contenu répréhensible</option>' +
        '</select></label>' +
      '<label>Précisions (facultatives)<textarea name="details" rows="2" maxlength="500"></textarea></label>' +
      '<div class="btn-rangee av-actions">' +
        '<button type="submit" class="btn-mini">Envoyer à la modération</button>' +
        '<button type="button" class="btn-mini" data-av-annuler>Annuler</button>' +
      '</div></form>';
  }

  /** Le formulaire : cinq étoiles qu'on touche, et quelques mots. */
  function formulaire(existant) {
    const note = existant ? existant.note : 0;
    let etoiles = "";
    for (let i = 1; i <= 5; i++) {
      etoiles += '<button type="button" class="av-etoile' + (i <= note ? " av-choisie" : "") +
        '" data-note="' + i + '" aria-label="' + i + ' étoile' + (i > 1 ? "s" : "") + '">' +
        UI.icone("etoile") + "</button>";
    }
    return (
      '<div class="av-formulaire" id="av-formulaire">' +
        '<div class="av-question">' +
          (existant ? "Modifier votre avis" : "Votre avis") + "</div>" +
        '<div class="av-etoiles" id="av-etoiles">' + etoiles + "</div>" +
        '<div class="champ"><textarea id="av-texte" rows="3" maxlength="1000" ' +
          'placeholder="Ce que vous en pensez, en quelques mots (facultatif)">' +
          Utils.echapper(existant ? existant.texte || "" : "") + "</textarea></div>" +
        '<label class="av-conditions"><input type="checkbox" id="av-conditions"> ' +
          'J’accepte les <a href="legal/conditions.html">' +
          'conditions d’utilisation</a> et les règles de publication des avis.</label>' +
        '<button type="button" class="btn" id="av-envoyer">' + UI.icone("check") +
          (existant ? "Enregistrer" : "Publier mon avis") + "</button>" +
      "</div>"
    );
  }

  /**
   * Remplir le bloc. `cible` vaut { produit } ou { boutique }.
   *
   * Appelée après le rendu de l'écran : les avis arrivent du réseau, et
   * la fiche ne doit pas les attendre pour s'afficher.
   */
  async function remplir(cible, quandChange) {
    const zone = UI.$("#av-corps");
    if (!zone) return;

    const [liste, peut] = await Promise.all([
      cible.produit ? Avis.duProduit(cible.produit) : Avis.deLaBoutique(cible.boutique),
      Avis.peutDonner(cible.produit || null, cible.boutique || null),
    ]);
    if (!UI.$("#av-corps")) return;   // l'écran a changé pendant l'attente

    const mien = Avis.lemien(liste);
    const masques = Avis.auteursMasques();
    const auteursCaches = new Set(masques.map((a) => a.id));
    const autres = liste.filter((a) => (!mien || a.id !== mien.id) &&
      !auteursCaches.has(a.client_id));

    let html = "";
    if (!liste.length) {
      html += '<p class="aide" style="margin:0">Aucun avis pour l\'instant.</p>';
    }
    if (mien) html += avisHtml(mien, true);
    html += autres.map((a) => avisHtml(a, false)).join("");
    if (masques.length) {
      html += '<details class="av-auteurs-masques"><summary>Auteurs masqués (' +
        masques.length + ')</summary>' + masques.map((a) =>
          '<div>' + Utils.echapper(a.nom) +
            ' <button type="button" class="btn-mini" data-av-revoir="' +
              Utils.echapper(a.id) + '">Afficher à nouveau</button></div>').join("") +
        '</details>';
    }

    /* Trois situations, trois messages. Ne rien dire à celui qui ne peut
       pas écrire serait le plus mauvais des trois : il chercherait le
       bouton. */
    if (peut && !mien) {
      html += formulaire(null);
    } else if (!peut) {
      const connecte = typeof Compte !== "undefined" && Compte.connecte();
      html +=
        '<p class="aide av-fermee" style="margin:12px 0 0">' + UI.icone("check", "ic-sm") +
          (connecte
            ? " Les avis sont réservés à ceux qui ont acheté et réglé. " +
              "C'est ce qui leur donne leur valeur."
            : " Seuls les acheteurs donnent leur avis. ") +
          (connecte ? "" : '<a href="#/connexion">Se connecter</a>') +
        "</p>";
    }

    zone.innerHTML = html;
    brancher(zone, cible, mien, quandChange);
  }

  function brancher(zone, cible, mien, quandChange) {
    let note = mien ? mien.note : 0;

    const marquer = () => {
      for (const b of UI.$$(".av-etoile", zone)) {
        b.classList.toggle("av-choisie", Number(b.dataset.note) <= note);
      }
    };
    for (const b of UI.$$(".av-etoile", zone)) {
      b.addEventListener("click", () => { note = Number(b.dataset.note); marquer(); });
    }

    const envoyer = UI.$("#av-envoyer", zone);
    if (envoyer) {
      envoyer.addEventListener("click", async () => {
        if (!note) return UI.toast("Touchez les étoiles pour noter.", "alerte");
        if (!UI.$("#av-conditions", zone).checked) {
          return UI.toast("Acceptez les conditions avant de publier votre avis.", "alerte");
        }
        envoyer.disabled = true;
        try {
          await Avis.deposer({
            produit: cible.produit, boutique: cible.boutique,
            note, texte: UI.$("#av-texte", zone).value,
          });
          UI.toast("Votre avis a été publié.");
          if (quandChange) await quandChange();
          await remplir(cible, quandChange);
        } catch (err) {
          UI.toast(err.message, "alerte");
          envoyer.disabled = false;
        }
      });
    }

    const modifier = UI.$("#av-modifier", zone);
    if (modifier) {
      modifier.addEventListener("click", () => {
        /* Le formulaire prend la place du bouton, pré-rempli : on
           modifie ce qu'on a écrit, on ne le retape pas. */
        modifier.closest(".av-actions").outerHTML = formulaire(mien);
        brancher(zone, cible, mien, quandChange);
      });
    }

    const retirer = UI.$("#av-retirer", zone);
    if (retirer) {
      retirer.addEventListener("click", async () => {
        retirer.disabled = true;
        try {
          await Avis.retirer(mien.id);
          UI.toast("Votre avis a été retiré.");
          if (quandChange) await quandChange();
          await remplir(cible, quandChange);
        } catch (err) {
          UI.toast(err.message, "alerte");
          retirer.disabled = false;
        }
      });
    }

    if (!zone.dataset.signalementBranche) {
      zone.dataset.signalementBranche = "oui";
      zone.addEventListener("click", async (ev) => {
        const signaler = ev.target.closest("[data-av-signaler]");
        if (signaler) {
          if (typeof Compte === "undefined" || !Compte.connecte()) {
            VueCompte.revenirVers(location.hash);
            location.hash = "#/connexion";
            UI.toast("Connectez-vous pour signaler un avis.", "alerte");
            return;
          }
          const carte = signaler.closest("[data-av-id]");
          const ancien = carte.querySelector("[data-av-report-form]");
          if (ancien) ancien.remove();
          carte.insertAdjacentHTML("beforeend",
            formulaireSignalement(carte.dataset.avId, signaler.dataset.avSignaler));
          return;
        }
        const annuler = ev.target.closest("[data-av-annuler]");
        if (annuler) { annuler.closest("[data-av-report-form]").remove(); return; }
        const masquer = ev.target.closest("[data-av-masquer]");
        if (masquer) {
          const carte = masquer.closest("[data-av-id]");
          const nom = carte.querySelector(".av-auteur").textContent;
          Avis.masquerAuteur(masquer.dataset.avMasquer, nom);
          UI.toast("Auteur masqué sur cet appareil.");
          await remplir(cible, quandChange);
          return;
        }
        const revoir = ev.target.closest("[data-av-revoir]");
        if (revoir) {
          Avis.revoirAuteur(revoir.dataset.avRevoir);
          await remplir(cible, quandChange);
        }
      });
      zone.addEventListener("submit", async (ev) => {
        const formulaire = ev.target.closest("[data-av-report-form]");
        if (!formulaire) return;
        ev.preventDefault();
        const motif = formulaire.elements.motif.value;
        if (!motif) return UI.toast("Choisissez un motif.", "alerte");
        const bouton = formulaire.querySelector('button[type="submit"]');
        bouton.disabled = true;
        try {
          await Avis.signaler(formulaire.dataset.avReportForm,
            formulaire.dataset.avCible, motif, formulaire.elements.details.value);
          formulaire.outerHTML = '<p class="av-moderation">Signalement reçu par BIZZOO.</p>';
        } catch (err) {
          UI.toast(err.message || "Signalement impossible", "alerte");
          bouton.disabled = false;
        }
      });
    }
  }

  return { bloc, remplir };
})();
