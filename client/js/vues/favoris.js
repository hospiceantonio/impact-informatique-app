/* =========================================================
   Favoris et adresses — ce que le client garde pour lui.

   DEUX SECTIONS aux favoris, comme la maquette : les produits
   mis de côté, et les boutiques suivies. L'écran vit sous
   « Mon compte » et non dans la barre du bas : la barre est
   pleine, et on ne consulte pas ses favoris à chaque ouverture.

   CE QUE CET ÉCRAN DOIT RÉSOUDRE, et qui n'est pas évident :
   la base ne garde que des IDENTIFIANTS. Un produit retiré de
   la vente, ou une boutique fermée depuis, laisse un favori qui
   ne désigne plus rien d'affichable. On les écarte de l'écran
   — une carte vide n'explique rien à personne — mais on ne les
   efface pas de la base : ce n'est pas à un écran de décider
   qu'un produit est parti pour de bon, une boutique peut
   rouvrir. On dit simplement combien manquent à l'appel, faute
   de quoi le client compterait huit favoris, en verrait six, et
   croirait à une panne.
   ========================================================= */
const VueFavoris = (() => {
  const e = Utils.echapper;

  /* ---------- Les favoris ---------- */

  async function afficher(vue) {
    UI.entete({ titre: "Favoris", sous: "Ce que vous gardez sous la main",
      retour: true });

    if (!Compte.connecte()) {
      vue.innerHTML = UI.vide("coeur", "Vos favoris vous attendent",
        "Connectez-vous pour retrouver sur tous vos appareils ce que vous mettez de côté.",
        '<a class="btn" href="#/connexion">Se connecter</a>');
      return;
    }

    vue.innerHTML = '<div class="carte"><p class="muet">Chargement…</p></div>';

    let idsProduits = [], idsBoutiques = [];
    try {
      [idsProduits, idsBoutiques] = await Promise.all([
        Favoris.listeProduits(), Favoris.listeBoutiques(),
      ]);
    } catch (_) {
      vue.innerHTML = UI.vide("alerte", "Liste indisponible",
        "Impossible de joindre BIZZOO. Réessayez quand le réseau revient.");
      return;
    }

    /* Un identifiant n'est pas un produit : la marchandise se retrouve
       dans le catalogue, et ce qui ne s'y retrouve pas ne s'affiche pas. */
    const parId = new Map(Catalogue.produits().map((p) => [p.id, p]));
    const produits = idsProduits.map((id) => parId.get(id)).filter(Boolean);

    const parIdB = new Map(Catalogue.boutiques().map((b) => [b.id, b]));
    const boutiques = idsBoutiques.map((id) => parIdB.get(id)).filter(Boolean);

    if (!produits.length && !boutiques.length) {
      vue.innerHTML = UI.vide("coeur", "Rien de mis de côté pour l'instant",
        "Touchez le cœur sur un produit ou une boutique, et vous le retrouverez ici.",
        '<a class="btn" href="#/">Parcourir les boutiques</a>');
      return;
    }

    let html = "";
    if (produits.length) {
      html += UI.titreSection("Produits") + UI.grilleProduits(produits);
    }
    if (boutiques.length) {
      html += UI.titreSection("Boutiques suivies") +
        '<div class="bou-grille">' +
          boutiques.map((b) =>
            '<a class="bou-carte" href="#/boutique/' + e(b.id) + '">' +
              (b.logo
                ? '<span class="bou-rond bou-rond-photo"><img src="' + e(b.logo) +
                  '" alt="" loading="lazy"></span>'
                : '<span class="bou-rond" style="background:' + e(b.couleur || "#2550B7") +
                  '">' + UI.icone(b.icone || "magasin") + "</span>") +
              '<span class="bou-carte-nom">' + e(b.nom) + "</span>" +
              '<span class="bou-carte-sous">' + e(b.secteur || "") + "</span>" +
            "</a>").join("") +
        "</div>";
    }

    const perdus = (idsProduits.length - produits.length) +
                   (idsBoutiques.length - boutiques.length);
    if (perdus > 0) {
      html += '<p class="fav-absents">' +
        (perdus === 1
          ? "Un favori n'est plus en vente et n'apparaît pas ici."
          : perdus + " favoris ne sont plus en vente et n'apparaissent pas ici.") +
        "</p>";
    }
    vue.innerHTML = html;
  }

  /* ---------- Les adresses de livraison ---------- */

  async function adresses(vue) {
    UI.entete({ titre: "Mes adresses", sous: "Où vous faire livrer", retour: true });

    if (!Compte.connecte()) {
      vue.innerHTML = UI.vide("lieu", "Vos adresses vous attendent",
        "Connectez-vous pour les enregistrer une fois et les réutiliser à chaque commande.",
        '<a class="btn" href="#/connexion">Se connecter</a>');
      return;
    }
    await redessiner(vue);
  }

  async function redessiner(vue) {
    vue.innerHTML = '<div class="carte"><p class="muet">Chargement…</p></div>';
    let liste = [];
    try { liste = await Favoris.adresses(); }
    catch (_) {
      vue.innerHTML = UI.vide("alerte", "Adresses indisponibles",
        "Impossible de joindre BIZZOO. Réessayez quand le réseau revient.");
      return;
    }

    vue.innerHTML =
      (liste.length
        ? liste.map(carteAdresse).join("")
        : UI.vide("lieu", "Aucune adresse enregistrée",
            "Enregistrez-en une, et elle vous sera proposée à chaque commande.")) +
      '<button type="button" class="btn btn-clair" data-adr-ajouter ' +
        'style="margin-top:14px;width:100%">' +
        UI.icone("plus", "ic-sm") + " Ajouter une adresse</button>";

    brancher(vue, liste);
  }

  function carteAdresse(a) {
    return (
      '<div class="carte adr-carte">' +
        '<div class="adr-tete">' +
          '<span class="adr-rond">' + UI.icone("lieu", "ic-sm") + "</span>" +
          "<div style='flex:1;min-width:0'>" +
            "<strong>" + e(a.libelle || "Adresse") + "</strong>" +
            (a.parDefaut ? '<span class="adr-defaut">Par défaut</span>' : "") +
            "<p>" + e(a.texte) + (a.ville ? " · " + e(a.ville) : "") + "</p>" +
          "</div>" +
        "</div>" +
        '<div class="adr-actions">' +
          (a.parDefaut ? ""
            : '<button type="button" class="btn-lien" data-adr-defaut="' + e(a.id) +
              '">Choisir par défaut</button>') +
          '<button type="button" class="btn-lien" data-adr-modifier="' + e(a.id) +
            '">Modifier</button>' +
          '<button type="button" class="btn-lien btn-lien-danger" data-adr-supprimer="' +
            e(a.id) + '">' + UI.icone("corbeille", "ic-sm") + " Supprimer</button>" +
        "</div>" +
      "</div>"
    );
  }

  function formulaire(a) {
    a = a || { id: "", libelle: "", texte: "", ville: "", parDefaut: false };
    return (
      '<form class="carte" id="adr-form">' +
        "<h2 class='carte-titre'>" +
          (a.id ? "Modifier l'adresse" : "Nouvelle adresse") + "</h2>" +
        '<div class="champ"><label for="adr-libelle">Nom <small>(Maison, Bureau…)</small></label>' +
          '<input id="adr-libelle" maxlength="40" value="' + e(a.libelle) + '"></div>' +
        '<div class="champ"><label for="adr-texte">Adresse</label>' +
          '<textarea id="adr-texte" maxlength="300" ' +
            'placeholder="Carré, rue, repère connu du livreur…">' + e(a.texte) +
          "</textarea></div>" +
        '<div class="champ"><label for="adr-ville">Ville</label>' +
          '<input id="adr-ville" maxlength="80" value="' + e(a.ville) + '"></div>' +
        '<label class="adr-case"><input type="checkbox" id="adr-defaut"' +
          (a.parDefaut ? " checked" : "") + "> Utiliser par défaut</label>" +
        '<div class="adr-boutons">' +
          '<button type="submit" class="btn">Enregistrer</button>' +
          '<button type="button" class="btn btn-clair" data-adr-annuler>Annuler</button>' +
        "</div>" +
      "</form>"
    );
  }

  function brancher(vue, liste) {
    const ouvrir = (a) => {
      vue.innerHTML = formulaire(a);
      const form = vue.querySelector("#adr-form");
      form.addEventListener("submit", async (ev) => {
        ev.preventDefault();
        const bouton = form.querySelector('button[type="submit"]');
        bouton.disabled = true;
        try {
          await Favoris.enregistrerAdresse({
            id: a ? a.id : "",
            libelle: vue.querySelector("#adr-libelle").value,
            texte: vue.querySelector("#adr-texte").value,
            ville: vue.querySelector("#adr-ville").value,
            parDefaut: vue.querySelector("#adr-defaut").checked,
          });
          UI.toast("Adresse enregistrée");
          await redessiner(vue);
        } catch (err) {
          bouton.disabled = false;
          UI.toast(err.message || "L'enregistrement a échoué.", "erreur");
        }
      });
      vue.querySelector("[data-adr-annuler]")
         .addEventListener("click", () => redessiner(vue));
    };

    const bAjout = vue.querySelector("[data-adr-ajouter]");
    if (bAjout) bAjout.addEventListener("click", () => ouvrir(null));

    vue.querySelectorAll("[data-adr-modifier]").forEach((b) => {
      b.addEventListener("click", () =>
        ouvrir((liste || []).find((x) => x.id === b.dataset.adrModifier)));
    });

    vue.querySelectorAll("[data-adr-defaut]").forEach((b) => {
      b.addEventListener("click", async () => {
        b.disabled = true;
        try {
          await Favoris.choisirParDefaut(b.dataset.adrDefaut);
          await redessiner(vue);
        } catch (err) {
          b.disabled = false;
          UI.toast(err.message || "Impossible de changer l'adresse par défaut.", "erreur");
        }
      });
    });

    vue.querySelectorAll("[data-adr-supprimer]").forEach((b) => {
      b.addEventListener("click", async () => {
        /* On demande. Une adresse effacée par mégarde se retape en
           entier, et personne ne retient le libellé de son bureau. */
        if (!confirm("Supprimer cette adresse ?")) return;
        b.disabled = true;
        try {
          await Favoris.supprimerAdresse(b.dataset.adrSupprimer);
          UI.toast("Adresse supprimée");
          await redessiner(vue);
        } catch (err) {
          b.disabled = false;
          UI.toast(err.message || "La suppression a échoué.", "erreur");
        }
      });
    });
  }

  return { afficher, adresses };
})();
