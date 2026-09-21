/* =========================================================
   Catégories — la liste de BIZZOO, et non celle d'une
   boutique.

   L'ENSEIGNE SEULE L'ÉCRIT, et c'est tout l'objet de cet
   écran. Sur une place de marché, laisser chaque commerce
   inventer ses rayons donne à l'acheteur autant de
   classements qu'il y a de boutiques : « Ordinateurs » chez
   l'un ne rejoint jamais « Ordinateurs » chez l'autre, et
   aucune liste ne peut plus les réunir.

   Une boutique choisit SON SECTEUR dans cette liste, et ses
   produits se rangent dans les SOUS-CATÉGORIES de ce secteur.
   Ce que voit l'acheteur en ouvrant « Catégories », c'est
   exactement ce qui se règle ici.
   ========================================================= */
const VueCategories = (() => {

  /* Les mêmes jeux que pour les boutiques : la pastille d'une
     catégorie et celle d'un commerce se ressemblent à l'écran, elles
     se choisissent de la même façon. Toutes ces icônes existent dans
     LES DEUX applications — une icône que l'admin propose et que le
     client ne sait pas dessiner laisserait un trou rond et vide. */
  const ICONES = [
    ["categories", "Rayons"], ["tshirt", "Mode & vêtements"],
    ["portable", "High-Tech"], ["ecran", "Écrans & logiciels"],
    ["voiture", "Auto & moto"], ["maison", "Maison & jardin"],
    ["goutte", "Beauté"], ["couverts", "Restauration"],
    ["chariot", "Supermarché"], ["cadeau", "Bébé & enfant"],
    ["ballon", "Sport & loisirs"], ["outils", "Bricolage"],
    ["livre", "Livres & fournitures"], ["diamant", "Bijoux"],
    ["patte", "Animaux"], ["sacoche", "Services"],
    ["magasin", "Boutique"], ["boite", "Matériel"],
    ["telephone", "Téléphonie"], ["casque", "Audio"],
    ["energie", "Énergie"], ["sante", "Santé"],
    ["nuage", "Numérique"], ["etoile", "Sélection"],
    ["promo", "Bons plans"], ["carte", "Point de vente"],
  ];

  const COULEURS = [
    ["#0B5CF5", "Bleu BIZZOO"], ["#F96302", "Orange BIZZOO"], ["#0F9D58", "Vert"],
    ["#E62329", "Rouge"], ["#D81B60", "Rose"], ["#6C3FBF", "Violet"],
    ["#3F51B5", "Indigo"], ["#0B7C8C", "Turquoise"], ["#9A6B00", "Ocre"],
    ["#7A4A32", "Marron"], ["#546E7A", "Ardoise"], ["#001450", "Bleu nuit"],
  ];

  /* Une catégorie enregistrée avec une icône ou une couleur qui ne
     figure plus dans les choix la garde : sans cela rien ne serait
     sélectionné, et l'enregistrement la remplacerait en silence. */
  const avecLaSienne = (liste, valeur, etiquette) =>
    valeur && !liste.some(([cle]) => cle === valeur)
      ? liste.concat([[valeur, etiquette]]) : liste;

  function pastille(c, classe) {
    return '<span class="cat-pastille ' + (classe || "") + '" style="background:' +
      Utils.echapper(c.couleur || "#0B5CF5") + '">' +
      UI.icone(c.icone || "categories") + "</span>";
  }

  async function afficher(vue) {
    /* ÉCRIRE LA LISTE EST À L'ENSEIGNE ; LA LIRE EST À TOUT LE MONDE.
       Un onglet qui ne mènerait qu'à « vous n'avez pas le droit » est
       un onglet mort. Une boutique y trouve ce qui la concerne
       vraiment : SES rayons — ceux de son secteur — et ce qu'elle a
       rangé dedans. */
    if (!Supabase.estSuper()) { await mesRayons(vue); return; }

    const [categories, produits] = await Promise.all([
      Store.listerCategories(), Store.listerProduits({ toutesBoutiques: true }),
    ]);
    const comptes = {};
    for (const p of produits) {
      if (p.categorieId) comptes[p.categorieId] = (comptes[p.categorieId] || 0) + 1;
    }
    const enAvant = categories.filter((c) => c.enAvant).length;

    UI.entete({ titre: "Catégories", sous: "La liste de BIZZOO, la même pour toutes" });

    let html =
      '<button type="button" class="btn" id="cat-ajouter">' +
        UI.icone("plus") + "Nouvelle catégorie</button>" +
      '<div class="carte carte-publier" style="margin-top:12px">' +
        '<div class="carte-titre">' + UI.icone("accueil", "ic-sm") + " " +
          enAvant + " sur l'accueil</div>" +
        '<p class="aide" style="margin:0">Les catégories « en avant » s\'affichent ' +
          "directement sur l'accueil de l'application cliente ; les autres attendent " +
          "derrière « Voir toutes les catégories ». Huit tiennent bien sur un écran.</p>" +
      "</div>";

    if (categories.length) {
      html += categories.map((c, i) =>
        '<div class="carte cat-bloc">' +
          '<div class="cat-bloc-entete">' +
            pastille(c) +
            '<span class="cat-bloc-nom">' + Utils.echapper(c.nom) +
              (c.enAvant ? ' <span class="badge badge-ok">Accueil</span>' : "") + "</span>" +
            '<span class="cat-bloc-compte">' + (comptes[c.id] || 0) + " produit" +
              ((comptes[c.id] || 0) > 1 ? "s" : "") + "</span>" +
            '<span class="avant-actions">' +
              '<button type="button" class="btn-ic btn-ic-clair" data-monter="' + Utils.echapper(c.id) + '"' +
                (i === 0 ? " disabled" : "") + ' aria-label="Monter">' + UI.icone("haut", "ic-sm") + "</button>" +
              '<button type="button" class="btn-ic btn-ic-clair" data-descendre="' + Utils.echapper(c.id) + '"' +
                (i === categories.length - 1 ? " disabled" : "") + ' aria-label="Descendre">' + UI.icone("bas", "ic-sm") + "</button>" +
              '<button type="button" class="btn-ic btn-ic-clair" data-modifier="' + Utils.echapper(c.id) + '" aria-label="Modifier">' +
                UI.icone("crayon", "ic-sm") + "</button>" +
            "</span>" +
          "</div>" +
          '<div class="cat-bloc-sous">' +
            ((c.sousCategories || []).length
              ? c.sousCategories.map((s) => '<span class="puce puce-fixe">' + Utils.echapper(s.nom) + "</span>").join("")
              : '<span class="aide">Aucun rayon — une boutique de ce secteur ne pourrait rien classer.</span>') +
          "</div>" +
        "</div>"
      ).join("");
    } else {
      html += UI.vide("categories", "Aucune catégorie",
        "Posez les secteurs de BIZZOO : Mode & Vêtements, High-Tech, Auto & Moto…");
    }

    vue.innerHTML = html;

    UI.$("#cat-ajouter").onclick = () => formulaire(null, () => afficher(vue));
    for (const b of UI.$$("[data-monter]", vue)) {
      b.onclick = async () => { await Store.deplacerCategorie(b.dataset.monter, -1); afficher(vue); };
    }
    for (const b of UI.$$("[data-descendre]", vue)) {
      b.onclick = async () => { await Store.deplacerCategorie(b.dataset.descendre, +1); afficher(vue); };
    }
    for (const b of UI.$$("[data-modifier]", vue)) {
      b.onclick = async () => {
        const c = await Store.lireCategorie(b.dataset.modifier);
        if (c) formulaire(c, () => afficher(vue));
      };
    }
  }

  /* ---------- Ce que voit une boutique : SES rayons ---------- */

  async function mesRayons(vue) {
    UI.entete({ titre: "Mes rayons", sous: "Ceux de votre secteur, tenus par BIZZOO" });
    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>' +
      "Lecture de vos rayons…</div>";

    const boutique = Store.boutiqueCourante();
    const [categories, produits] = await Promise.all([
      Store.listerCategories(), Store.listerProduits(),
    ]);
    const secteur = categories.find((c) => c.id === (boutique && boutique.categorieId));

    /* SANS SECTEUR, ELLE NE PEUT RIEN CLASSER. Le dire franchement, et
       dire à qui le demander : l'attribution est une décision de
       l'enseigne, pas un réglage de la boutique. */
    if (!secteur) {
      vue.innerHTML = UI.vide("categories", "Votre boutique n'a pas encore de secteur",
        "BIZZOO range les boutiques par secteur d'activité, et vos produits se " +
        "classent dans les rayons du vôtre. Demandez à l'enseigne de vous en " +
        "attribuer un : sans lui, vos produits restent en vente mais n'apparaissent " +
        "sous aucune catégorie de l'application cliente.");
      return;
    }

    const comptes = {};
    let aClasser = 0;
    for (const p of produits) {
      if (p.sousCategorieId) comptes[p.sousCategorieId] = (comptes[p.sousCategorieId] || 0) + 1;
      else aClasser += 1;
    }

    vue.innerHTML =
      '<div class="carte cat-bloc">' +
        '<div class="cat-bloc-entete">' +
          pastille(secteur) +
          '<span class="cat-bloc-nom">' + Utils.echapper(secteur.nom) + "</span>" +
          '<span class="cat-bloc-compte">votre secteur</span>' +
        "</div>" +
        '<p class="aide" style="margin:6px 0 0">Le secteur est attribué par BIZZOO. ' +
          "Vos produits se rangent dans les rayons ci-dessous, et dans ceux-là seulement.</p>" +
      "</div>" +

      (aClasser
        ? '<div class="carte carte-publier">' +
            '<div class="carte-titre">' + UI.icone("alerte", "ic-sm") + " " +
              aClasser + " produit" + (aClasser > 1 ? "s" : "") + " à classer</div>" +
            '<p class="aide" style="margin:0 0 10px">' +
              (aClasser > 1 ? "Ils restent" : "Il reste") + " en vente, mais " +
              (aClasser > 1 ? "n'apparaissent" : "n'apparaît") + " sous aucun rayon de " +
              "BIZZOO. Ouvrez chaque fiche et choisissez son rayon.</p>" +
            '<a class="btn btn-clair" href="#/produits">' + UI.icone("boite") +
              "Ouvrir les produits</a>" +
          "</div>"
        : "") +

      '<div class="titre-section">' + secteur.sousCategories.length + " rayon" +
        (secteur.sousCategories.length > 1 ? "s" : "") + "</div>" +
      (secteur.sousCategories.length
        ? secteur.sousCategories.map((s) =>
            '<div class="carte cat-bloc">' +
              '<div class="cat-bloc-entete">' +
                '<span class="cat-bloc-nom">' + Utils.echapper(s.nom) + "</span>" +
                '<span class="cat-bloc-compte">' + (comptes[s.id] || 0) + " produit" +
                  ((comptes[s.id] || 0) > 1 ? "s" : "") + "</span>" +
              "</div>" +
            "</div>").join("")
        : UI.vide("categories", "Aucun rayon dans votre secteur",
            "Demandez à l'enseigne d'en ajouter : sans rayon, vous ne pouvez rien classer."));
  }

  /* ---------- Feuille de création / modification ---------- */

  /** Sous-catégories en cours d'édition : [{ id?, nom }] */
  let sousTravail = [];

  function htmlSous() {
    return sousTravail.map((s, i) =>
      '<div class="sous-ligne">' +
        '<input type="text" value="' + Utils.echapper(s.nom) + '" data-sous="' + i + '" placeholder="Nom du rayon">' +
        '<button type="button" class="btn-ic btn-ic-clair btn-ic-danger" data-sous-retirer="' + i + '" aria-label="Retirer">' +
          UI.icone("fermer", "ic-sm") + "</button>" +
      "</div>"
    ).join("") || '<p class="aide" style="margin:0">Aucun rayon pour l\'instant.</p>';
  }

  function formulaire(categorie, auTermine) {
    sousTravail = ((categorie && categorie.sousCategories) || []).map((s) => ({ id: s.id, nom: s.nom }));

    const corps = UI.ouvrirFeuille(
      categorie ? "Modifier la catégorie" : "Nouvelle catégorie",
      UI.champTexte({ id: "cat-nom", label: "Nom de la catégorie", obligatoire: true,
        valeur: categorie ? categorie.nom : "", placeholder: "Ex. Mode & Vêtements" }) +

      '<div class="champ">' +
        "<label>Icône</label>" +
        '<div class="choix-icones" id="cat-icones">' +
          avecLaSienne(ICONES, categorie && categorie.icone, "Icône actuelle")
            .map(([cle, nom]) =>
              '<button type="button" class="choix-icone' +
                ((categorie ? categorie.icone : "categories") === cle ? " actif" : "") +
                '" data-icone="' + cle + '" aria-label="' + Utils.echapper(nom) + '">' +
                UI.icone(cle) + "</button>").join("") +
        "</div>" +
      "</div>" +

      '<div class="champ">' +
        "<label>Couleur de la pastille</label>" +
        '<div class="choix-couleurs" id="cat-couleurs">' +
          avecLaSienne(COULEURS, categorie && categorie.couleur, "Couleur actuelle")
            .map(([code, nom]) =>
              '<button type="button" class="choix-couleur' +
                ((categorie ? categorie.couleur : "#0B5CF5") === code ? " actif" : "") +
                '" data-couleur="' + code + '" style="background:' + code +
                '" aria-label="' + Utils.echapper(nom) + '"></button>').join("") +
        "</div>" +
        '<div class="aide">L\'icône et la couleur composent la pastille ronde de ' +
          "l'écran « Catégories », chez le client.</div>" +
      "</div>" +

      UI.interrupteur({ id: "cat-avant", label: "Montrer sur l'accueil",
        actif: categorie ? categorie.enAvant : false,
        aide: "Les catégories ne tiennent pas toutes sur un premier écran. " +
          "Celles-ci s'y affichent ; les autres restent derrière " +
          "« Voir toutes les catégories »." }) +
      '<div class="champ"><label>Rayons de cette catégorie</label>' +
        '<div id="cat-sous"></div>' +
        '<button type="button" class="btn btn-clair" id="cat-sous-ajouter" style="margin-top:10px">' +
          UI.icone("plus", "ic-sm") + "Ajouter un rayon</button>" +
        '<div class="aide" style="margin-top:8px">C\'est là-dedans que les boutiques ' +
          "de ce secteur rangent leurs produits. Ex. Homme, Femme, Enfant, Chaussures…</div>" +
      "</div>" +
      '<div class="btn-rangee">' +
        '<button type="button" class="btn" id="cat-enregistrer">' + UI.icone("check") + "Enregistrer</button>" +
        (categorie
          ? '<button type="button" class="btn btn-clair btn-danger-clair" id="cat-supprimer">' +
              UI.icone("poubelle") + "Supprimer la catégorie</button>"
          : "") +
      "</div>"
    );

    /* ATTENTION, deux conventions cohabitent dans cette application :
       les icônes et les couleurs s'allument avec « actif », les PUCES
       avec « active ». Les mélanger donne un bouton qui a l'air choisi
       et qu'on ne relit jamais. */
    for (const zone of ["#cat-icones", "#cat-couleurs"]) {
      for (const bouton of UI.$$(zone + " button", corps)) {
        bouton.onclick = () => {
          for (const x of UI.$$(zone + " button", corps)) x.classList.toggle("actif", x === bouton);
        };
      }
    }
    const choisi = (selecteur, attribut, defaut) => {
      const actif = UI.$(selecteur + " .actif", corps);
      return actif ? actif.dataset[attribut] : defaut;
    };

    const zoneSous = UI.$("#cat-sous", corps);

    const lireSaisies = () => {
      for (const champ of UI.$$("[data-sous]", zoneSous)) {
        sousTravail[Number(champ.dataset.sous)].nom = champ.value;
      }
    };

    const rendreSous = () => {
      zoneSous.innerHTML = htmlSous();
      for (const b of UI.$$("[data-sous-retirer]", zoneSous)) {
        b.onclick = () => {
          lireSaisies();
          sousTravail.splice(Number(b.dataset.sousRetirer), 1);
          rendreSous();
        };
      }
    };
    rendreSous();

    UI.$("#cat-sous-ajouter", corps).onclick = () => {
      lireSaisies();
      sousTravail.push({ nom: "" });
      rendreSous();
      const champs = UI.$$("[data-sous]", zoneSous);
      if (champs.length) champs[champs.length - 1].focus();
    };

    UI.$("#cat-enregistrer", corps).onclick = async () => {
      lireSaisies();
      try {
        /* RETIRER UN RAYON DÉCLASSE LES PRODUITS QUI S'Y TROUVENT, et
           dans toutes les boutiques du secteur : on compte d'abord. */
        if (categorie) {
          const restants = new Set(sousTravail.filter((s) => s.id && s.nom.trim()).map((s) => s.id));
          const produits = await Store.produitsDeCategorie(categorie.id);
          for (const ancien of categorie.sousCategories || []) {
            if (!restants.has(ancien.id)) {
              const utilises = produits.filter((p) => p.sousCategorieId === ancien.id).length;
              if (utilises) {
                throw new Error("« " + ancien.nom + " » contient " + utilises + " produit" +
                  (utilises > 1 ? "s" : "") + ". Déplacez-les avant de le retirer.");
              }
            }
          }
        }
        await Store.sauverCategorie({
          id: categorie ? categorie.id : null,
          nom: UI.$("#cat-nom", corps).value,
          icone: choisi("#cat-icones", "icone", "categories"),
          couleur: choisi("#cat-couleurs", "couleur", "#0B5CF5"),
          enAvant: UI.$("#cat-avant", corps).checked,
          sousCategories: sousTravail,
        });
        UI.feuilleSansRappel();
        UI.fermerFeuille();
        UI.toast(categorie ? "Catégorie modifiée" : "Catégorie créée", "ok");
        auTermine();
      } catch (err) {
        UI.toast(err.message || "Enregistrement impossible", "err");
      }
    };

    const btnSupprimer = UI.$("#cat-supprimer", corps);
    if (btnSupprimer) {
      btnSupprimer.onclick = async () => {
        UI.feuilleSansRappel();
        UI.fermerFeuille();
        const ok = await UI.confirmer({
          titre: "Supprimer cette catégorie ?",
          texte: "« " + categorie.nom + " » disparaîtra de l'écran des clients. " +
            "Possible seulement si aucune boutique ne l'a pour secteur et si aucun " +
            "produit n'y est rangé.",
          bouton: "Supprimer",
          danger: true,
        });
        if (!ok) { auTermine(); return; }
        try {
          await Store.supprimerCategorie(categorie.id);
          UI.toast("Catégorie supprimée");
        } catch (err) {
          UI.toast(err.message, "err");
        }
        auTermine();
      };
    }
  }

  return { afficher };
})();
