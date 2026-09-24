/* =========================================================
   Codes promo — ce que vous offrez, et ce que cela vous coûte.

   UNE REMISE SORT DE VOTRE MARGE, jamais de la poche d'une
   boutique. La boutique touche son prix BIZZOO en entier :
   elle n'a pas décidé cette promotion, elle n'a pas à la
   payer. C'est pour cela que cet écran vous est réservé — on
   ne laisse pas quelqu'un d'autre engager votre marge.

   ET C'EST POUR CELA QU'IL Y A UN PLAFOND, posé en base : une
   remise ne descend jamais en dessous de ce que les boutiques
   doivent toucher. Un code de 80 % sur un article qui ne vous
   laisse que 40 % de marge est ramené à 40 %. Vous ne pouvez
   donc pas, même par erreur, vendre à perte avec un code.

   « Déjà utilisé » et « vous a coûté » se comptent sur les
   commandes PAYÉES. Un panier abandonné n'a rien coûté à
   personne, et ne mange pas le quota d'un vrai client.
   ========================================================= */
const VueCodes = (() => {

  const jourISO = (d) => d.toISOString().slice(0, 10);

  /** Ce que le code retire, en une ligne lisible. */
  function remiseLisible(c, devise) {
    return c.mode === "pourcent"
      ? Utils.fmtTaux(c.valeur) + " %"
      : Utils.fmtMontant(c.valeur, devise);
  }

  function htmlCode(c, devise) {
    const limites = [];
    if (c.minimum > 0) limites.push("dès " + Utils.fmtMontant(c.minimum, devise));
    if (c.maximum > 0) limites.push(c.maximum + " au total");
    if (c.uneParClient) limites.push("une fois par client");
    if (c.fin) limites.push("jusqu'au " + Utils.fmtDate(c.fin));

    return (
      '<div class="carte cd-carte' + (c.actif ? "" : " cd-ferme") + '" ' +
        'data-code="' + Utils.echapper(c.code) + '">' +
        '<div class="cd-haut">' +
          "<div>" +
            '<strong class="cd-code">' + Utils.echapper(c.code) + "</strong>" +
            (c.libelle
              ? '<div class="aide">' + Utils.echapper(c.libelle) + "</div>"
              : "") +
          "</div>" +
          '<span class="badge ' + (c.actif ? "badge-ok" : "badge-annulee") + '">' +
            (c.actif ? "Ouvert" : "Fermé") + "</span>" +
        "</div>" +
        '<div class="cd-remise">− ' + Utils.echapper(remiseLisible(c, devise)) + "</div>" +
        (limites.length
          ? '<div class="aide" style="margin:6px 0 0">' +
            Utils.echapper(limites.join(" · ")) + "</div>"
          : '<div class="aide" style="margin:6px 0 0">Aucune limite.</div>') +
        '<div class="cd-chiffres">' +
          "<span>" + c.utilisations + " utilisation" +
            (c.utilisations > 1 ? "s" : "") + "</span>" +
          "<strong>" + Utils.echapper(Utils.fmtMontant(c.coute, devise)) + "</strong>" +
        "</div>" +
        '<div class="btn-rangee" style="margin-top:12px">' +
          '<button type="button" class="btn btn-clair" data-modifier="' +
            Utils.echapper(c.code) + '">' + UI.icone("crayon") + "Modifier</button>" +
          '<button type="button" class="btn btn-clair' +
            (c.actif ? " btn-danger-clair" : "") + '" data-bascule="' +
            Utils.echapper(c.code) + '">' +
            UI.icone(c.actif ? "fermer" : "check") +
            (c.actif ? "Fermer" : "Rouvrir") + "</button>" +
        "</div>" +
      "</div>"
    );
  }

  async function afficher(vue) {
    const devise = Store.lireReglages().devise;

    UI.entete({ titre: "Codes promo", sous: "Ce que vous offrez, et ce qu'il vous coûte",
      retour: true,
      actions: '<button type="button" class="btn-ic" id="cd-nouveau" ' +
        'aria-label="Nouveau code">' + UI.icone("plus") + "</button>" });

    vue.innerHTML =
      '<div class="chargement"><span class="chargement-rond"></span>' +
      "Lecture des codes…</div>";

    const nouveau = UI.$("#cd-nouveau");
    if (nouveau) nouveau.onclick = () => formulaire(vue, null);

    let codes;
    try {
      codes = await Store.listerCodes();
    } catch (err) {
      vue.innerHTML =
        '<div class="carte"><div class="carte-titre">Codes indisponibles</div>' +
        '<p class="aide" style="margin:0">' + Utils.echapper(err.message) +
        "<br>Si les codes promo viennent d'être mis en place, exécutez le fichier " +
        "supabase/codes-promo.sql.</p></div>";
      return;
    }

    /* Ce que l'ensemble des codes a coûté : le chiffre qu'on vient
       vérifier en ouvrant cet écran. */
    const total = codes.reduce((s, c) => s + c.coute, 0);

    vue.innerHTML =
      '<div class="carte carte-publier st-resume">' +
        '<div class="st-resume-grand">' +
          "<small>Ce que vos codes vous ont coûté</small>" +
          "<strong>" + Utils.echapper(Utils.fmtMontant(total, devise)) + "</strong>" +
        "</div>" +
        '<div class="st-resume-detail deux">' +
          "<div><small>Codes ouverts</small><span>" +
            codes.filter((c) => c.actif).length + "</span></div>" +
          "<div><small>Utilisations</small><span>" +
            codes.reduce((s, c) => s + c.utilisations, 0) + "</span></div>" +
        "</div>" +
      "</div>" +
      '<p class="aide" style="margin:12px 4px">Une remise sort de VOTRE marge : la ' +
        "boutique touche son prix BIZZOO en entier. La base plafonne d'ailleurs chaque " +
        "remise à ce que vous gagnez sur la commande — vous ne pouvez pas vendre à " +
        "perte avec un code.</p>" +
      (codes.length
        ? '<div class="titre-section">Vos codes</div>' +
          codes.map((c) => htmlCode(c, devise)).join("")
        : UI.vide("cadeau", "Aucun code pour l'instant",
            "Touchez le + en haut pour en créer un. Vos clients le taperont au " +
            "moment de régler leur panier."));

    for (const b of UI.$$("[data-modifier]", vue)) {
      b.onclick = () => formulaire(vue, codes.find((c) => c.code === b.dataset.modifier));
    }
    for (const b of UI.$$("[data-bascule]", vue)) {
      b.onclick = () => basculer(vue, codes.find((c) => c.code === b.dataset.bascule));
    }
  }

  /** Fermer un code, ou le rouvrir. */
  async function basculer(vue, c) {
    if (!c) return;
    const ouvrir = !c.actif;
    if (!ouvrir) {
      const sur = await UI.confirmer({
        titre: "Fermer « " + c.code + " » ?",
        texte: "Il cessera de marcher immédiatement. Les commandes déjà passées " +
               "avec ce code gardent leur remise — on ne réécrit pas le passé.",
        bouton: "Fermer le code",
      });
      if (!sur) return;
    }
    try {
      await Store.enregistrerCode({ ...c, actif: ouvrir });
      UI.toast(ouvrir ? "Code rouvert." : "Code fermé.");
      afficher(vue);
    } catch (err) {
      UI.toast(err.message, "err");
    }
  }

  /* ---------- Créer, ou corriger ---------- */

  function formulaire(vue, existant) {
    const devise = Store.lireReglages().devise;
    const c = existant || {
      code: "", libelle: "", mode: "pourcent", valeur: "",
      minimum: 0, maximum: 0, uneParClient: true, fin: "", actif: true,
    };

    const corps = UI.ouvrirFeuille(
      existant ? "Modifier « " + c.code + " »" : "Nouveau code promo",
      /* Le code lui-même ne se change JAMAIS : c'est la clé, et des
         commandes le portent déjà. Pour en changer, on ferme celui-ci
         et on en pose un autre. */
      (existant
        ? '<div class="aide" style="margin:0 0 14px">Le code lui-même ne se change ' +
          "pas : des commandes le portent déjà. Pour en changer, fermez celui-ci et " +
          "créez-en un autre.</div>"
        : "") +
      (existant
        ? ""
        : UI.champTexte({ id: "cd-code", label: "Le code", obligatoire: true,
            placeholder: "RENTREE2026",
            aide: "Lettres et chiffres. Vos clients le taperont : court et simple." })) +
      UI.champTexte({ id: "cd-libelle", label: "À quoi il sert", valeur: c.libelle,
        placeholder: "Rentrée 2026",
        aide: "Pour vous y retrouver. Le client ne le voit pas." }) +

      '<div class="champ">' +
        "<label>Comment il se calcule</label>" +
        '<div class="st-filtres" id="cd-modes">' +
          '<button type="button" class="puce' +
            (c.mode === "pourcent" ? " active" : "") + '" data-mode="pourcent">' +
            "Pourcentage</button>" +
          '<button type="button" class="puce' +
            (c.mode === "montant" ? " active" : "") + '" data-mode="montant">' +
            "Montant fixe</button>" +
        "</div>" +
      "</div>" +
      UI.champTexte({ id: "cd-valeur", label: "Combien", obligatoire: true,
        valeur: c.valeur === "" ? "" : String(c.valeur),
        placeholder: "10",
        aide: "En pourcentage, ou en " + devise + " selon le choix ci-dessus." }) +

      UI.champTexte({ id: "cd-minimum", label: "Montant minimum de commande",
        valeur: c.minimum ? String(c.minimum) : "",
        placeholder: "0",
        aide: "0 = aucun minimum. Sans lui, « 20 % » s'applique aussi à un panier " +
              "de 500 " + devise + "." }) +
      UI.champTexte({ id: "cd-maximum", label: "Nombre total d'utilisations",
        valeur: c.maximum ? String(c.maximum) : "",
        placeholder: "0",
        aide: "0 = sans limite. Comptées sur les commandes PAYÉES : un panier " +
              "abandonné ne mange pas le quota." }) +
      '<div class="champ">' +
        '<label for="cd-fin">Dernier jour <small>(facultatif)</small></label>' +
        '<input id="cd-fin" type="date" value="' + Utils.echapper(c.fin || "") + '">' +
        '<div class="aide">Le code s\'arrête de lui-même après cette date. Laissez ' +
          "vide pour qu'il n'expire jamais.</div>" +
      "</div>" +
      UI.interrupteur({ id: "cd-une", label: "Une seule fois par client",
        actif: c.uneParClient,
        aide: "Un compte se reconnaît à son identifiant ; un client sans compte, à " +
              "son seul numéro de téléphone." }) +

      '<button type="button" class="btn" id="cd-enregistrer" style="margin-top:16px">' +
        UI.icone("check") + "Enregistrer</button>");

    let mode = c.mode;
    for (const b of UI.$$("[data-mode]", corps)) {
      b.onclick = () => {
        mode = b.dataset.mode;
        /* « active », pas « actif » : c'est la classe des puces dans
           cette application, et les deux conventions cohabitent. */
        for (const a of UI.$$("[data-mode]", corps)) {
          a.classList.toggle("active", a === b);
        }
      };
    }

    UI.$("#cd-enregistrer", corps).onclick = async () => {
      const valeur = Number((UI.$("#cd-valeur", corps).value || "").replace(",", "."));
      const maj = {
        code: existant ? existant.code : (UI.$("#cd-code", corps).value || "").trim(),
        libelle: (UI.$("#cd-libelle", corps).value || "").trim(),
        mode,
        valeur,
        minimum: Number(UI.$("#cd-minimum", corps).value || 0),
        maximum: Number(UI.$("#cd-maximum", corps).value || 0),
        uneParClient: UI.$("#cd-une", corps).checked,
        fin: (UI.$("#cd-fin", corps).value || "") || null,
        actif: existant ? existant.actif : true,
      };
      /* On arrête ici ce qui se voit ici. La base refuse les mêmes
         choses — ce n'est qu'une politesse pour éviter un aller-retour. */
      if (!maj.code) return UI.toast("Un code ne peut pas être vide.", "err");
      if (!(valeur > 0)) return UI.toast("Un code sans valeur ne retire rien.", "err");
      if (mode === "pourcent" && valeur > 100) {
        return UI.toast("Une remise ne dépasse pas 100 %.", "err");
      }
      /* Un seul envoi à la fois : un double appui écrivait deux fois,
         et deux lignes au journal. */
      const bouton = UI.$("#cd-enregistrer", corps);
      bouton.disabled = true;
      try {
        await Store.enregistrerCode(maj);
        UI.fermerFeuille();
        UI.toast("Code enregistré.");
        afficher(vue);
      } catch (err) {
        bouton.disabled = false;
        UI.toast(err.message, "err");
      }
    };
  }

  return { afficher };
})();
