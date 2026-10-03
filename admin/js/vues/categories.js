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

  /* LES ICÔNES DES CATÉGORIES (3.56) : les douze de l'image choisie par
     l'enseigne, reprises telles quelles et nommées comme sur l'image,
     puis les quatre construites dans son style pour les catégories
     qu'elle n'avait pas. Elles sont dans LES DEUX applications
     (« img/pictos/ ») — une icône que l'admin propose et que le client
     n'aurait pas laisserait une tuile vide. Une même icône peut servir
     à plusieurs catégories. */
  const PICTOS = [
    ["alimentation", "Alimentation"], ["restauration", "Restauration"], ["mode", "Mode"],
    ["beaute", "Beauté"], ["telephones", "Téléphones"], ["informatique", "Informatique"],
    ["electromenager", "Électroménager"], ["maison-deco", "Maison & Déco"],
    ["auto-moto", "Auto & Moto"], ["sante", "Santé"], ["immobilier", "Immobilier"],
    ["services", "Services"], ["bebe-enfant", "Bébé & Enfant"],
    ["sport-loisirs", "Sport & Loisirs"], ["livres-education", "Livres & Éducation"],
    ["animaux", "Animaux"],
  ];

  /* Une catégorie enregistrée avec une icône qui ne figure pas dans les
     choix — choisie avant la 3.56 — la garde : sans cela rien ne serait
     sélectionné, et l'enregistrement la remplacerait en silence. */
  const avecLaSienne = (liste, valeur, etiquette) =>
    valeur && !liste.some(([cle]) => cle === valeur)
      ? liste.concat([[valeur, etiquette]]) : liste;

  /* « img/categories/… », c'est une illustration en 3D d'avant la 3.56.
     La base en ligne les garde — les applications déjà installées les
     montrent encore —, mais ici on ne les voit plus : la tuile montre
     son icône. Seule une photo déposée par l'enseigne, dans le seau, la
     recouvre. */
  const illustrationDAvant = (chemin) => /^img\/categories\//.test(chemin || "");
  const urlPhoto = (chemin) =>
    !chemin || illustrationDAvant(chemin) ? "" : Supabase.urlImage(chemin);

  /* LA PASTILLE : la tuile du client, en petit. La photo par-dessus
     l'icône : tant qu'elle charge, et si elle ne vient pas, c'est
     l'icône qu'on voit. */
  function pastille(c, classe) {
    const photo = urlPhoto(c.image);
    return '<span class="cat-pastille ' + (classe || "") + '">' + UI.picto(c.icone) +
      (photo ? '<img src="' + Utils.echapper(photo) + '" alt="" data-secours>' : "") +
      "</span>";
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
          enAvant + " en tête de l'accueil</div>" +
        '<p class="aide" style="margin:0">L\'accueil de l\'application cliente montre ' +
          "toujours huit catégories. Celles « en avant » passent en premier, dans cet " +
          "ordre ; s'il en manque, les suivantes de la liste complètent — celles qui ont " +
          "des produits d'abord. Toutes restent dans l'onglet « Catégories ».</p>" +
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

  /** La photo en cours d'édition : { chemin } (en ligne), { dataUrl }
   *  (nouvelle), ou null (aucune). */
  let photoTravail = null;
  /** La photo a-t-elle été ajoutée ou retirée dans cette fiche ? Sinon,
   *  l'enregistrement n'écrit pas la colonne — et l'illustration d'avant
   *  la 3.56, invisible ici, reste pour les applications installées. */
  let photoTouchee = false;

  /* LA PHOTO DE LA TUILE, facultative. Même geste que le logo d'une
     boutique : un carré pour la choisir, la croix pour la retirer. */
  function brancherPhoto(corps) {
    const zone = UI.$("#cat-photo", corps);

    const rendre = () => {
      const apercu = photoTravail
        ? (photoTravail.dataUrl || urlPhoto(photoTravail.chemin))
        : "";
      zone.innerHTML = apercu
        ? '<div class="photo-boite cat-photo-boite">' +
            '<img src="' + Utils.echapper(apercu) + '" alt="Photo de la catégorie">' +
            '<button type="button" class="photo-retirer" id="cat-photo-retirer" ' +
              'aria-label="Retirer la photo">' + UI.icone("fermer", "ic-sm") + "</button>" +
          "</div>"
        : '<label class="photo-ajout">' + UI.icone("camera") + "<span>Ajouter</span>" +
            '<input type="file" accept="image/*" hidden id="cat-photo-fichier"></label>';

      const champ = UI.$("#cat-photo-fichier", zone);
      if (champ) {
        champ.addEventListener("change", async () => {
          const fichier = champ.files && champ.files[0];
          if (!fichier) return;
          try {
            /* 480 px suffisent : la plus grande tuile fait moins de 50 px
               à l'écran, soit moins de 150 points sur l'écran le plus fin. */
            const { dataUrl } = await Utils.compresserImage(fichier, 480, 0.82);
            photoTravail = { dataUrl };
            photoTouchee = true;
          } catch (err) {
            UI.toast(err.message || "Image illisible", "err");
          }
          rendre();
        });
      }
      const retirer = UI.$("#cat-photo-retirer", zone);
      if (retirer) retirer.onclick = () => { photoTravail = null; photoTouchee = true; rendre(); };
    };

    rendre();
  }

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
    /* Une illustration d'avant la 3.56 ne s'affiche plus : la fiche part
       sans photo, et ne l'efface pas pour autant (voir photoTouchee). */
    photoTravail = categorie && urlPhoto(categorie.image) ? { chemin: categorie.image } : null;
    photoTouchee = false;

    const corps = UI.ouvrirFeuille(
      categorie ? "Modifier la catégorie" : "Nouvelle catégorie",
      UI.champTexte({ id: "cat-nom", label: "Nom de la catégorie", obligatoire: true,
        valeur: categorie ? categorie.nom : "", placeholder: "Ex. Mode & Vêtements" }) +

      '<div class="champ">' +
        "<label>Icône</label>" +
        '<div class="choix-pictos" id="cat-icones">' +
          avecLaSienne(PICTOS, categorie && categorie.icone, "Icône actuelle")
            .map(([cle, nom]) =>
              '<button type="button" class="choix-picto' +
                ((categorie ? categorie.icone : "categories") === cle ? " actif" : "") +
                '" data-icone="' + Utils.echapper(cle) + '" aria-label="' + Utils.echapper(nom) +
                '" title="' + Utils.echapper(nom) + '">' +
                UI.picto(cle) + "</button>").join("") +
        "</div>" +
        '<div class="aide">Elle compose la tuile de la catégorie, sur l\'accueil et ' +
          "l'écran « Catégories », chez le client.</div>" +
      "</div>" +

      '<div class="champ">' +
        "<label>Photo de la tuile (facultative)</label>" +
        '<div class="photos-zone" id="cat-photo"></div>' +
        '<div class="aide">Elle prend la place de l\'icône, sur l\'accueil et ' +
          "l'écran « Catégories ». Choisissez une photo carrée, le sujet au centre : " +
          "les coins seront arrondis. Sans photo — ou si elle ne se charge pas —, " +
          "c'est l'icône qu'on voit.</div>" +
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
       les icônes s'allument avec « actif », les PUCES avec
       « active ». Les mélanger donne un bouton qui a l'air choisi et
       qu'on ne relit jamais. */
    for (const bouton of UI.$$("#cat-icones button", corps)) {
      bouton.onclick = () => {
        for (const x of UI.$$("#cat-icones button", corps)) x.classList.toggle("actif", x === bouton);
      };
    }
    const choisi = (selecteur, attribut, defaut) => {
      const actif = UI.$(selecteur + " .actif", corps);
      return actif ? actif.dataset[attribut] : defaut;
    };

    brancherPhoto(corps);

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
      /* UN SEUL ENVOI À LA FOIS : la photo part au stockage avant la
         ligne, et un second appui pendant ce temps en déposerait une
         seconde. */
      const bouton = UI.$("#cat-enregistrer", corps);
      bouton.disabled = true;
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
        /* NI COULEUR NI PHOTO INCHANGÉE : la couleur ne se choisit plus
           (toutes les tuiles ont le même fond), et la base garde celle
           qu'elle a ; une photo que la fiche n'a pas touchée n'est pas
           réécrite — l'illustration d'avant la 3.56 reste ainsi aux
           applications déjà installées. */
        await Store.sauverCategorie({
          id: categorie ? categorie.id : null,
          nom: UI.$("#cat-nom", corps).value,
          icone: choisi("#cat-icones", "icone", "categories"),
          enAvant: UI.$("#cat-avant", corps).checked,
          photo: photoTouchee ? photoTravail : undefined,
          sousCategories: sousTravail,
        });
        UI.feuilleSansRappel();
        UI.fermerFeuille();
        UI.toast(categorie ? "Catégorie modifiée" : "Catégorie créée", "ok");
        auTermine();
      } catch (err) {
        bouton.disabled = false;
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
