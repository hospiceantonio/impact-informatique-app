/* =========================================================
   Avis — ce que les clients disent, et ce qu'on y répond.

   UNE BOUTIQUE NE SUPPRIME PAS CE QUI LA GÊNE. Elle répond, et
   sa réponse se lit sous l'avis, publiquement. C'est la règle
   qui donne sa valeur à tout le reste : une boutique capable de
   faire disparaître ses mauvais avis rend ses bons avis suspects
   par la même occasion.

   Masquer existe, mais pour ce qui n'a pas sa place — insultes,
   numéro de téléphone, règlement de comptes — et l'enseigne
   seule en décide. Pas pour une mauvaise note : une mauvaise
   note est une information, et souvent la plus utile.

   C'est la base qui applique tout cela. Cet écran ne fait que
   ne pas montrer les boutons qui seraient refusés.
   ========================================================= */
const VueAvis = (() => {

  function etoiles(note) {
    let html = "";
    for (let i = 1; i <= 5; i++) {
      html += '<span class="av-et' + (i <= note ? " av-et-pleine" : "") + '">' +
        UI.icone("etoile", "ic-sm") + "</span>";
    }
    return '<span class="av-etoiles-lues">' + html + "</span>";
  }

  function htmlAvis(a, peutMasquer) {
    const enAttente = a.masque && a.motifMasque === "En attente de modération";
    const cible = a.produitId
      ? "Sur un produit"
      : "Sur la boutique " + (a.nomBoutique || a.boutiqueId);
    return (
      '<div class="carte av-carte' + (a.masque ? " av-masque" : "") + '" ' +
        'data-avis="' + Utils.echapper(a.id) + '">' +
        '<div class="dem-entete">' +
          '<span class="dem-boutique">' + UI.icone("personne", "ic-sm") +
            Utils.echapper(a.auteur || "Client") + "</span>" +
          '<span class="dem-quand">' + Utils.echapper(Utils.fmtDateHeure(a.creeLe)) + "</span>" +
        "</div>" +
        '<div class="av-ligne">' + etoiles(a.note) +
          '<span class="av-cible">' + Utils.echapper(cible) + "</span></div>" +
        (a.texte ? '<p class="av-dit">' + Utils.echapper(a.texte) + "</p>"
                 : '<p class="aide" style="margin:0 0 10px">Une note, sans commentaire.</p>') +
        (enAttente
          ? '<div class="av-etiquette-masque">En attente de validation, invisible pour les clients</div>'
          : a.masque
          ? '<div class="av-etiquette-masque">' + UI.icone("oeil", "ic-sm") +
            " Masqué — invisible pour les clients" +
            (a.motifMasque ? " · " + Utils.echapper(a.motifMasque) : "") + "</div>"
          : "") +
        (a.reponse
          ? '<div class="av-deja-repondu">' + UI.icone("magasin", "ic-sm") +
            "<div><strong>Votre réponse</strong><br>" + Utils.echapper(a.reponse) + "</div></div>"
          : "") +
        '<div class="btn-rangee" style="margin-top:12px">' +
          '<button type="button" class="btn btn-clair" data-repondre="' +
            Utils.echapper(a.id) + '">' + UI.icone("crayon") +
            (a.reponse ? "Modifier ma réponse" : "Répondre") + "</button>" +
          (peutMasquer
            ? '<button type="button" class="btn ' +
              (a.masque ? "btn-clair" : "btn-danger-clair") + '" data-masquer="' +
              Utils.echapper(a.id) + '" data-cacher="' + (a.masque ? "non" : "oui") + '">' +
              UI.icone("oeil") + (enAttente ? "Valider et publier" : a.masque ? "Rendre public" : "Masquer") + "</button>"
            : "") +
        "</div>" +
      "</div>"
    );
  }

  const MOTIFS = {
    harcelement: "Harcèlement ou menace", haine: "Haine ou discrimination",
    sexuel: "Contenu sexuel", donnees_personnelles: "Données personnelles exposées",
    spam: "Spam ou publicité", autre: "Autre contenu répréhensible",
  };
  const MOTIFS_PRODUITS = {
    trompeur: "Information trompeuse ou dangereuse",
    contrefacon: "Contrefaçon ou droit d’auteur",
    haine: "Haine ou discrimination", sexuel: "Contenu sexuel",
    donnees_personnelles: "Données personnelles exposées",
    spam: "Spam ou publicité", autre: "Autre contenu répréhensible",
  };

  function htmlSignalementProduit(s) {
    return '<div class="carte av-carte" data-signalement-produit="' + s.id + '">' +
      '<div class="carte-titre">' + UI.icone("alerte", "ic-sm") +
        ' Fiche produit signalée</div>' +
      '<p><strong>' + Utils.echapper(s.nomProduit || s.produitId) + '</strong>' +
        (s.boutiqueId ? ' · ' + Utils.echapper(s.boutiqueId) : '') + '</p>' +
      '<p class="aide">' + Utils.echapper(MOTIFS_PRODUITS[s.motif] || s.motif) +
        ' · ' + Utils.echapper(Utils.fmtDateHeure(s.creeLe)) + '</p>' +
      (s.details ? '<p class="aide">Précisions : ' + Utils.echapper(s.details) + '</p>' : '') +
      '<div class="btn-rangee">' +
        '<a class="btn btn-clair" href="#/produit/' + Utils.echapper(s.produitId) +
          '">Examiner la fiche</a>' +
        '<button type="button" class="btn btn-clair" data-traiter-signalement-produit="' +
          s.id + '">Classer après examen</button>' +
      '</div></div>';
  }

  function htmlSignalement(s, a, auteurBloque) {
    return '<div class="carte av-carte" data-signalement="' + s.id + '">' +
      '<div class="carte-titre">' + UI.icone("alerte", "ic-sm") +
        ' Signalement d’un ' + (s.cible === "auteur" ? "auteur" : "avis") + '</div>' +
      '<p class="aide">' + Utils.echapper(MOTIFS[s.motif] || s.motif) +
        ' · ' + Utils.echapper(Utils.fmtDateHeure(s.creeLe)) + '</p>' +
      (a ? '<p class="av-dit"><strong>' + Utils.echapper(a.auteur || "Client") +
        '</strong> · ' + Utils.echapper(a.texte || "Avis sans commentaire") + '</p>' :
        '<p class="aide">Avis ' + Utils.echapper(s.avisId) + '</p>') +
      (s.details ? '<p class="aide">Précisions : ' + Utils.echapper(s.details) + '</p>' : "") +
      (auteurBloque ? '<p class="aide">Cet auteur ne peut plus publier d’avis.</p>' : "") +
      '<div class="btn-rangee">' +
        '<button type="button" class="btn btn-danger-clair" data-traiter-signalement="' + s.id +
          '" data-masquer-signalement="oui">Masquer l’avis</button>' +
        '<button type="button" class="btn btn-clair" data-traiter-signalement="' + s.id +
          '" data-masquer-signalement="non">Classer sans suite</button>' +
        (!auteurBloque && s.auteurId
          ? '<button type="button" class="btn btn-clair" data-bloquer-auteur="' +
            Utils.echapper(s.auteurId) + '">Interdire ses futurs avis</button>'
          : "") +
      '</div></div>';
  }

  function htmlAuteurBloque(b) {
    return '<div class="carte av-carte"><div class="carte-titre">' +
      Utils.echapper(b.auteur || "Auteur") + '</div>' +
      '<p class="aide">Avis interdits depuis ' +
        Utils.echapper(Utils.fmtDateHeure(b.bloqueLe)) +
        ' · ' + Utils.echapper(b.motif) + '</p>' +
      '<button type="button" class="btn btn-clair" data-retablir-auteur="' +
        Utils.echapper(b.id) + '">Rétablir ses avis</button></div>';
  }

  async function afficher(vue) {
    const peutMasquer = Supabase.estSuper();
    UI.entete({ titre: peutMasquer ? "Avis et signalements" : "Avis des clients",
      sous: peutMasquer ? "Toutes les boutiques" : "Votre boutique", retour: true });
    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>' +
      "Lecture des avis…</div>";

    let liste, signalements, auteursBloques, signalementsProduits;
    try {
      [liste, signalements, auteursBloques, signalementsProduits] = await Promise.all([
        Store.listerAvis(300),
        peutMasquer ? Store.listerSignalementsAvis() : Promise.resolve([]),
        peutMasquer ? Store.listerAuteursAvisBloques() : Promise.resolve([]),
        peutMasquer ? Store.listerSignalementsProduits() : Promise.resolve([]),
      ]);
      const connus = new Set(liste.map((a) => a.id));
      const manquants = [...new Set(signalements.map((s) => s.avisId))]
        .filter((id) => !connus.has(id));
      if (manquants.length) {
        const anciens = await Promise.all(manquants.map((id) => Store.lireAvis(id)));
        liste.push(...anciens.filter(Boolean));
      }
    } catch (err) {
      vue.innerHTML =
        '<div class="carte"><div class="carte-titre">Modération indisponible</div>' +
        '<p class="aide" style="margin:0">' + Utils.echapper(err.message) +
        "<br>Si les avis viennent d'être mis en place, exécutez le fichier " +
          "supabase/avis.sql puis supabase/moderation-ugc.sql.</p></div>";
      return;
    }

    /* Ce qui attend une réponse d'abord : c'est la seule chose à faire
       sur cet écran, et un avis sans réponse est un client qui attend. */
    const enAttente = liste.filter((a) => a.masque &&
      a.motifMasque === "En attente de modération");
    const aRepondre = liste.filter((a) => !a.reponse && !a.masque);
    const traites = liste.filter((a) => (a.reponse || a.masque) && !enAttente.includes(a));
    const publies = liste.filter((a) => !a.masque);
    const idsBloques = new Set(auteursBloques.map((b) => b.id));
    const moyenne = publies.length
      ? (publies.reduce((s, a) => s + a.note, 0) / publies.length).toFixed(1).replace(".", ",")
      : "—";

    vue.innerHTML =
      (peutMasquer && signalementsProduits.length
        ? '<div class="titre-section">Fiches produit signalées (' +
          signalementsProduits.length + ')</div>' +
          signalementsProduits.map(htmlSignalementProduit).join("")
        : "") +
      (peutMasquer && signalements.length
        ? '<div class="titre-section">Signalements à traiter (' + signalements.length +
          ')</div>' + signalements.map((s) => htmlSignalement(s,
            liste.find((a) => a.id === s.avisId), idsBloques.has(s.auteurId))).join("")
        : "") +
      (peutMasquer && auteursBloques.length
        ? '<div class="titre-section">Auteurs privés de publication (' +
          auteursBloques.length + ')</div>' +
          auteursBloques.map(htmlAuteurBloque).join("")
        : "") +
      (peutMasquer && enAttente.length
        ? '<div class="titre-section">Avis à valider (' + enAttente.length +
          ')</div>' + enAttente.map((a) => htmlAvis(a, peutMasquer)).join("")
        : "") +
      '<div class="carte carte-publier">' +
        '<div class="carte-titre">' + UI.icone("etoile", "ic-sm") + " " +
          (aRepondre.length
            ? aRepondre.length + " avis sans réponse"
            : "Tous les avis ont une réponse") + "</div>" +
        '<p class="aide" style="margin:0">' + publies.length + " avis publiés, " + moyenne +
          " de moyenne. Répondre à un avis, même mauvais, se voit : c'est ce que " +
          "lisent les clients suivants. Un avis ne s'efface pas" +
          (peutMasquer
            ? " — il se masque, et seulement s'il n'a pas sa place : insultes, " +
              "numéro de téléphone, règlement de comptes. Pas pour une mauvaise note."
            : ".") + "</p>" +
      "</div>" +
      (aRepondre.length ? aRepondre.map((a) => htmlAvis(a, peutMasquer)).join("") : "") +
      (traites.length
        ? '<div class="titre-section">Déjà traités</div>' +
          traites.map((a) => htmlAvis(a, peutMasquer)).join("")
        : "") +
      (!liste.length
        ? UI.vide("etoile", "Aucun avis",
            "Les avis de vos clients s'afficheront ici, dès qu'ils auront acheté.")
        : "");

    const recharger = () => afficher(vue);
    const avisDe = (id) => liste.find((a) => a.id === id) || {};

    for (const bouton of UI.$$("[data-repondre]", vue)) {
      bouton.onclick = async () => {
        const a = avisDe(bouton.dataset.repondre);
        const texte = await UI.demanderTexte({
          titre: "Répondre à " + (a.auteur || "ce client"),
          texte: "Votre réponse s'affichera sous son avis, pour tout le monde. " +
            "C'est ce que liront les clients suivants.",
          libelle: "Votre réponse",
          valeur: a.reponse || "",
          bouton: "Publier ma réponse",
        });
        if (texte === null) return;
        bouton.disabled = true;
        try {
          await Store.repondreAvis(a.id, texte);
          UI.toast(texte ? "Réponse publiée" : "Réponse retirée", "ok");
          recharger();
        } catch (err) {
          UI.toast(err.message, "err");
          bouton.disabled = false;
        }
      };
    }

    for (const bouton of UI.$$("[data-masquer]", vue)) {
      bouton.onclick = async () => {
        const id = bouton.dataset.masquer;
        const cacher = bouton.dataset.cacher === "oui";
        let motif = "";
        if (cacher) {
          /* On demande POURQUOI, et le motif reste en base : masquer sans
             raison écrite, c'est se donner le droit d'effacer une
             mauvaise note en se disant qu'on avait sûrement une bonne
             raison. */
          motif = await UI.demanderTexte({
            titre: "Masquer cet avis ?",
            texte: "À réserver à ce qui n'a pas sa place : insultes, numéro de " +
              "téléphone, règlement de comptes. Une mauvaise note n'est pas un motif.",
            libelle: "Motif",
            bouton: "Masquer", danger: true,
          });
          if (motif === null) return;
          if (!motif.trim()) return UI.toast("Dites pourquoi vous le masquez.", "err");
        } else if (!(await UI.confirmer({
          titre: "Rendre cet avis public ?",
          texte: "Il redeviendra visible par tous, et recomptera dans la note.",
          bouton: "Rendre public",
        }))) return;

        bouton.disabled = true;
        try {
          await Store.masquerAvis(id, cacher, motif);
          UI.toast(cacher ? "Avis masqué" : "Avis rendu public", "ok");
          recharger();
        } catch (err) {
          UI.toast(err.message, "err");
          bouton.disabled = false;
        }
      };
    }

    for (const bouton of UI.$$("[data-traiter-signalement]", vue)) {
      bouton.onclick = async () => {
        const cacher = bouton.dataset.masquerSignalement === "oui";
        const motif = await UI.demanderTexte({
          titre: cacher ? "Masquer cet avis ?" : "Classer ce signalement ?",
          texte: cacher
            ? "Indiquez le contenu contraire aux règles. Une mauvaise note seule n'est pas un motif."
            : "Vous pouvez noter pourquoi ce signalement ne nécessite pas de retrait.",
          libelle: cacher ? "Motif du masquage" : "Décision (facultative)",
          bouton: cacher ? "Masquer l’avis" : "Classer", danger: cacher,
        });
        if (motif === null) return;
        if (cacher && !motif.trim()) {
          return UI.toast("Indiquez pourquoi vous masquez cet avis.", "err");
        }
        bouton.disabled = true;
        try {
          await Store.traiterSignalementAvis(bouton.dataset.traiterSignalement,
            cacher, motif);
          UI.toast(cacher ? "Avis masqué, signalement traité" : "Signalement classé", "ok");
          recharger();
        } catch (err) {
          UI.toast(err.message, "err");
          bouton.disabled = false;
        }
      };
    }

    for (const bouton of UI.$$("[data-bloquer-auteur]", vue)) {
      bouton.onclick = async () => {
        const motif = await UI.demanderTexte({
          titre: "Interdire les futurs avis de cet auteur ?",
          texte: "Son accès aux achats et aux commandes reste ouvert. Ses avis déjà publiés doivent être examinés séparément.",
          libelle: "Motif de la sanction", bouton: "Interdire les avis", danger: true,
        });
        if (motif === null) return;
        if (!motif.trim()) return UI.toast("Indiquez le motif de la sanction.", "err");
        bouton.disabled = true;
        try {
          await Store.bloquerAuteurAvis(bouton.dataset.bloquerAuteur, true, motif);
          UI.toast("Cet auteur ne peut plus publier d’avis.", "ok");
          recharger();
        } catch (err) {
          UI.toast(err.message, "err");
          bouton.disabled = false;
        }
      };
    }

    for (const bouton of UI.$$("[data-retablir-auteur]", vue)) {
      bouton.onclick = async () => {
        if (!(await UI.confirmer({
          titre: "Rétablir la publication d’avis ?",
          texte: "Cet auteur pourra de nouveau donner ou modifier ses avis après un achat payé.",
          bouton: "Rétablir",
        }))) return;
        bouton.disabled = true;
        try {
          await Store.bloquerAuteurAvis(bouton.dataset.retablirAuteur, false, "");
          UI.toast("Publication d’avis rétablie.", "ok");
          recharger();
        } catch (err) {
          UI.toast(err.message, "err");
          bouton.disabled = false;
        }
      };
    }

    for (const bouton of UI.$$("[data-traiter-signalement-produit]", vue)) {
      bouton.onclick = async () => {
        const suite = await UI.demanderTexte({
          titre: "Suite donnée au signalement",
          texte: "Examinez d’abord la fiche. Corrigez ou retirez le contenu si nécessaire, puis consignez votre décision.",
          libelle: "Correction, retrait ou motif de classement",
          bouton: "Classer le signalement",
        });
        if (suite === null) return;
        if (!suite.trim()) return UI.toast("Indiquez la suite donnée.", "err");
        bouton.disabled = true;
        try {
          await Store.traiterSignalementProduit(
            bouton.dataset.traiterSignalementProduit, suite);
          UI.toast("Signalement de fiche traité.", "ok");
          recharger();
        } catch (err) {
          UI.toast(err.message, "err");
          bouton.disabled = false;
        }
      };
    }
  }

  return { afficher };
})();
