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
        (a.masque
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
              UI.icone("oeil") + (a.masque ? "Rendre public" : "Masquer") + "</button>"
            : "") +
        "</div>" +
      "</div>"
    );
  }

  async function afficher(vue) {
    const peutMasquer = Supabase.estSuper();
    UI.entete({ titre: "Avis des clients",
      sous: peutMasquer ? "Toutes les boutiques" : "Votre boutique", retour: true });
    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>' +
      "Lecture des avis…</div>";

    let liste;
    try {
      liste = await Store.listerAvis();
    } catch (err) {
      vue.innerHTML =
        '<div class="carte"><div class="carte-titre">Avis indisponibles</div>' +
        '<p class="aide" style="margin:0">' + Utils.echapper(err.message) +
        "<br>Si les avis viennent d'être mis en place, exécutez le fichier " +
        "supabase/avis.sql.</p></div>";
      return;
    }

    /* Ce qui attend une réponse d'abord : c'est la seule chose à faire
       sur cet écran, et un avis sans réponse est un client qui attend. */
    const aRepondre = liste.filter((a) => !a.reponse && !a.masque);
    const traites = liste.filter((a) => a.reponse || a.masque);
    const moyenne = liste.length
      ? (liste.reduce((s, a) => s + a.note, 0) / liste.length).toFixed(1).replace(".", ",")
      : "—";

    vue.innerHTML =
      '<div class="carte carte-publier">' +
        '<div class="carte-titre">' + UI.icone("etoile", "ic-sm") + " " +
          (aRepondre.length
            ? aRepondre.length + " avis sans réponse"
            : "Tous les avis ont une réponse") + "</div>" +
        '<p class="aide" style="margin:0">' + liste.length + " avis, " + moyenne +
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
  }

  return { afficher };
})();
