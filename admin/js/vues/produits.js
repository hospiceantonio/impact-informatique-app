/* =========================================================
   Produits — liste avec recherche et filtres, formulaire
   (photos, vidéo, prix, catégorie) et fiche.
   ========================================================= */
const VueProduits = (() => {

  /* =====================================================
     Liste
     ===================================================== */

  let filtreCategorie = "";
  let termeRecherche = "";

  async function liste(vue) {
    const [produits, categories] = await Promise.all([
      Store.listerProduits(), Store.listerCategories(),
    ]);

    UI.entete({ titre: "Produits",
      sous: produits.length + " produit" + (produits.length > 1 ? "s" : "") + " au catalogue",
      /* Le stock de toute la boutique, sur un seul écran. */
      actions: '<a class="btn-ic" href="#/stock" aria-label="Stock" title="Stock">' +
        UI.icone("boite") + "</a>" });

    if (!produits.length) {
      vue.innerHTML = UI.vide("boite", "Aucun produit pour l'instant",
        "Ajoutez votre premier produit : photo, prix, catégorie, et il sera prêt à publier.",
        '<a class="btn" href="#/produit/nouveau">' + UI.icone("plus") + "Ajouter un produit</a>");
      return;
    }

    /* LES FILTRES SONT LES RAYONS DU SECTEUR, plus celui qui compte le
       plus après la reprise : « à classer ». Filtrer par CATÉGORIE
       n'aurait plus de sens — une boutique n'en a qu'une, son
       secteur, et la puce ne retirerait jamais rien. */
    const maBoutique = Store.boutiqueCourante();
    const secteur = categories.find((c) => c.id === (maBoutique && maBoutique.categorieId));
    const rayons = (secteur && secteur.sousCategories) || [];
    const aClasser = produits.filter((p) => !p.sousCategorieId).length;
    if (filtreCategorie && filtreCategorie !== "aclasser"
        && !rayons.some((sc) => sc.id === filtreCategorie)) filtreCategorie = "";

    vue.innerHTML =
      (aClasser
        ? '<div class="carte carte-publier">' +
            '<div class="carte-titre">' + UI.icone("alerte", "ic-sm") + " " +
              aClasser + " produit" + (aClasser > 1 ? "s" : "") + " à classer</div>" +
            '<p class="aide" style="margin:0">' +
              (aClasser > 1 ? "Ils restent" : "Il reste") + " en vente, mais " +
              (aClasser > 1 ? "n'apparaissent" : "n'apparaît") + " sous aucun rayon de " +
              "BIZZOO. Ouvrez la fiche et choisissez le rayon.</p>" +
          "</div>"
        : "") +
      '<div class="recherche-boite">' + UI.icone("recherche", "ic-sm") +
        '<input id="produits-recherche" type="search" placeholder="Rechercher un produit…" autocomplete="off" value="' +
        Utils.echapper(termeRecherche) + '">' +
      "</div>" +
      '<div class="puces" id="produits-filtres">' +
        '<button type="button" class="puce' + (filtreCategorie ? "" : " active") + '" data-filtre="">Tout</button>' +
        (aClasser
          ? '<button type="button" class="puce' +
            (filtreCategorie === "aclasser" ? " active" : "") +
            '" data-filtre="aclasser">À classer (' + aClasser + ")</button>"
          : "") +
        rayons.map((sc) =>
          '<button type="button" class="puce' + (filtreCategorie === sc.id ? " active" : "") +
          '" data-filtre="' + Utils.echapper(sc.id) + '">' + Utils.echapper(sc.nom) + "</button>").join("") +
      "</div>" +
      '<div id="produits-liste"></div>';

    const zone = UI.$("#produits-liste");
    const nomSousCategorie = (p) => {
      const rayon = rayons.find((x) => x.id === p.sousCategorieId);
      return (p.code ? p.code + " · " : "") +
        (p.reference ? p.reference + " · " : "") +
        (rayon ? rayon.nom : "À CLASSER");
    };

    const rendre = () => {
      let visibles = produits;
      if (filtreCategorie === "aclasser") visibles = visibles.filter((p) => !p.sousCategorieId);
      else if (filtreCategorie) visibles = visibles.filter((p) => p.sousCategorieId === filtreCategorie);
      visibles = Store.chercherProduits(visibles, termeRecherche);
      zone.innerHTML = visibles.length
        ? '<div class="carte carte-liste">' + visibles.map((p) => UI.ligneProduit(p, nomSousCategorie(p))).join("") + "</div>"
        : UI.vide("recherche", "Aucun produit trouvé", "Essayez un autre mot ou un autre filtre.");
    };

    UI.$("#produits-recherche").addEventListener("input", Utils.tempo((ev) => {
      termeRecherche = ev.target.value;
      rendre();
    }, 200));

    for (const b of UI.$$("#produits-filtres [data-filtre]")) {
      b.onclick = () => {
        filtreCategorie = b.dataset.filtre;
        for (const x of UI.$$("#produits-filtres [data-filtre]")) x.classList.toggle("active", x === b);
        rendre();
      };
    }

    rendre();
  }

  /* =====================================================
     Stock : la saisie rapide, sans passer par le formulaire
     ===================================================== */

  function feuilleStock(p, auTermine) {
    const joursAppro = [];
    for (let n = Store.APPRO_MIN; n <= Store.APPRO_MAX; n++) joursAppro.push(n);
    const restant = Store.joursAppro(p);
    const joursChoisis = restant !== null && restant >= Store.APPRO_MIN
      ? Math.min(Store.APPRO_MAX, restant)
      : 3;

    /* LE CHIFFRE MONTRÉ, sur lequel on écrit. Si une vente est payée
       pendant que la feuille est ouverte, la base refuse d'écrire
       par-dessus et rend le nouveau chiffre : on l'affiche, et le
       prochain appui part de lui. */
    let vu = p.stock;
    const etatActuel = () => (p.surCommande
      ? "Sur commande — sans stock"
      : Store.enAppro(p)
        ? "En approvisionnement — arrive " + Utils.delaiEnMots(Store.joursAppro(p))
        : vu > 0 ? vu + " en stock" : "En rupture — 0 en stock");

    const corps = UI.ouvrirFeuille("Disponibilité — " + p.nom,
      '<p class="stock-actuel" id="stock-actuel">Actuellement : <strong>' +
        Utils.echapper(etatActuel()) + "</strong></p>" +
      '<p class="aide" style="margin:0 0 14px">Chaque vente payée se décompte toute seule. ' +
        "Saisissez ici ce qui arrive, ou corrigez le chiffre après un comptage. " +
        "À zéro, vos clients voient « En rupture ». Un produit que vous ne tenez pas " +
        "en boutique se met « Sur commande » ; un produit qui arrive bientôt se met " +
        "« En approvisionnement ».</p>" +
      '<div class="stock-saisie">' +
        '<button type="button" class="btn-ic btn-ic-clair" id="stock-moins" aria-label="Un de moins">' +
          UI.icone("bas") + "</button>" +
        '<input id="stock-valeur" type="tel" inputmode="numeric" value="' +
          (p.surCommande ? 0 : p.stock) + '" aria-label="Stock">' +
        '<button type="button" class="btn-ic btn-ic-clair" id="stock-plus" aria-label="Un de plus">' +
          UI.icone("haut") + "</button>" +
      "</div>" +
      '<div class="btn-rangee" style="margin-top:18px">' +
        '<button type="button" class="btn" id="stock-enregistrer">' + UI.icone("check") +
          "Enregistrer ce stock</button>" +
        '<button type="button" class="btn btn-clair btn-danger-clair" id="stock-zero">' +
          UI.icone("alerte") + "En rupture</button>" +
        (p.surCommande
          ? ""
          : '<button type="button" class="btn btn-clair" id="stock-commande">' +
              UI.icone("nuage") + "Passer en « Sur commande »</button>") +
      "</div>" +

      /* ---- Réassort annoncé ---- */
      '<div class="champ" style="margin-top:20px">' +
        '<label for="stock-appro-jours">' + UI.icone("horloge", "ic-sm") +
          " En approvisionnement — arrive dans</label>" +
        '<select id="stock-appro-jours">' +
          joursAppro.map((n) =>
            '<option value="' + n + '"' + (n === joursChoisis ? " selected" : "") + ">" +
            n + (n > 1 ? " jours" : " jour") + "</option>").join("") +
        "</select>" +
      "</div>" +
      '<div class="btn-rangee">' +
        '<button type="button" class="btn btn-clair" id="stock-appro">' +
          UI.icone("horloge") + "Annoncer l'arrivée</button>" +
        (Store.enAppro(p)
          ? '<button type="button" class="btn btn-clair btn-danger-clair" id="stock-appro-retirer">' +
              UI.icone("fermer") + "Annuler l'approvisionnement</button>"
          : "") +
      "</div>");

    const champ = UI.$("#stock-valeur", corps);
    const lire = () => Math.max(0, Math.round(Number(String(champ.value).replace(/\D/g, "")) || 0));
    UI.$("#stock-moins", corps).onclick = () => { champ.value = Math.max(0, lire() - 1); };
    UI.$("#stock-plus", corps).onclick = () => { champ.value = lire() + 1; };

    /* UN APPUI, UN ENVOI. Un double appui envoyait deux fois le même
       chiffre ; avec la garde du stock, le second se serait heurté au
       premier et aurait crié à un changement qui n'en était pas un. */
    let enCours = false;
    const enregistrer = async (maj, message) => {
      if (enCours) return;
      enCours = true;
      const boutons = UI.$$("button", corps);
      for (const b of boutons) b.disabled = true;
      try {
        await Store.majDisponibilite(p.id, maj);
        UI.fermerFeuille();
        UI.toast(message, "ok");
        auTermine();
      } catch (err) {
        if (err.stockActuel !== undefined) {
          vu = err.stockActuel;
          UI.$("#stock-actuel", corps).innerHTML = "Actuellement : <strong>" +
            Utils.echapper(etatActuel()) + "</strong> — le chiffre vient de changer";
        }
        UI.toast(err.message, "err");
      } finally {
        enCours = false;
        for (const b of boutons) b.disabled = false;
      }
    };
    UI.$("#stock-enregistrer", corps).onclick = () => {
      const stock = lire();
      enregistrer({ stock, surCommande: false, stockVu: vu },
        stock > 0 ? "Stock : " + stock + " en boutique" : "Produit passé « En rupture »");
    };
    UI.$("#stock-zero", corps).onclick = () =>
      enregistrer({ stock: 0, surCommande: false }, "Produit passé « En rupture »");
    const versCommande = UI.$("#stock-commande", corps);
    if (versCommande) {
      versCommande.onclick = () =>
        enregistrer({ surCommande: true }, "Produit passé « Sur commande »");
    }

    UI.$("#stock-appro", corps).onclick = () => {
      const jours = Number(UI.$("#stock-appro-jours", corps).value);
      enregistrer({ approJours: jours, surCommande: false },
        "En approvisionnement — arrive " + Utils.delaiEnMots(jours));
    };
    const retirerAppro = UI.$("#stock-appro-retirer", corps);
    if (retirerAppro) {
      retirerAppro.onclick = () =>
        enregistrer({ approJours: 0, stock: 0 }, "Approvisionnement annulé");
    }
  }

  /* =====================================================
     L'écran Stock : toute la réserve de la boutique
     ===================================================== */

  /* Chaque vente payée se décompte toute seule. Ce qui reste à la
     boutique, c'est de dire ce qui ARRIVE et de corriger ce qui s'est
     perdu — et de voir ce qui manque avant que le client ne le voie.
     Cet écran ne montre que cela : combien il en reste, produit par
     produit, les plus urgents en tête. */

  let filtreStock = "";
  let termeStock = "";

  const ETATS_STOCK = {
    rupture:  { nom: "En rupture",           puce: "En rupture" },
    bas:      { nom: "Bientôt épuisé",       puce: "Bientôt épuisés" },
    ok:       { nom: "En stock",             puce: "En stock" },
    appro:    { nom: "En approvisionnement", puce: "En approvisionnement" },
    commande: { nom: "Sur commande",         puce: "Sur commande" },
  };
  /* L'ordre de la liste : ce qui manque, puis ce qui va manquer. */
  const ORDRE_STOCK = ["rupture", "bas", "ok", "appro", "commande"];

  function etatStock(p) {
    const s = Store.statut(p);
    if (s === "commande") return "commande";
    if (s === "approvisionnement") return "appro";
    if (s === "rupture") return "rupture";
    return p.stock <= Store.STOCK_BAS ? "bas" : "ok";
  }

  function ligneStock(p, peutModifier) {
    const e = Utils.echapper;
    const etat = etatStock(p);
    const compte = etat === "rupture" || etat === "bas" || etat === "ok";
    const note = etat === "appro"
      ? "Arrive " + Utils.delaiEnMots(Store.joursAppro(p))
      : etat === "commande" ? "Sans stock" : ETATS_STOCK[etat].nom;
    /* Sans le droit de modifier, la ligne ouvre la fiche, en lecture. */
    return (
      '<button type="button" class="ligne"' +
        (peutModifier
          ? ' data-stock="' + e(p.id) + '"'
          : ' data-nav="#/produit/' + e(p.id) + '"') + ">" +
        UI.vignetteProduit(p) +
        '<span class="ligne-corps">' +
          '<span class="ligne-titre">' + e(p.nom) + "</span>" +
          '<span class="ligne-sous">' +
            e([p.code, p.reference].filter(Boolean).join(" · ")) + "</span>" +
        "</span>" +
        '<span class="ligne-fin">' +
          (compte
            ? '<span class="stock-chiffre stock-' + etat + '">' + p.stock + "</span>"
            : "") +
          '<span class="ligne-stock' + (etat === "rupture" ? " ligne-stock-vide" : "") + '">' +
            e(note) + "</span>" +
        "</span>" +
      "</button>"
    );
  }

  async function stock(vue, params) {
    const produits = await Store.listerProduits();
    const peutModifier = Supabase.peutModifierProduits();

    const combien = { rupture: 0, bas: 0, ok: 0, appro: 0, commande: 0 };
    for (const p of produits) combien[etatStock(p)]++;

    /* Venu d'une notification ou de l'accueil, le filtre vient avec :
       « rupture » pose le doigt sur ce qui manque. */
    if (params && params.filtre !== undefined) filtreStock = params.filtre;
    if (!ETATS_STOCK[filtreStock]) filtreStock = "";

    const alertes = [
      combien.rupture ? combien.rupture + " en rupture" : "",
      combien.bas ? combien.bas + " bientôt épuisé" + (combien.bas > 1 ? "s" : "") : "",
    ].filter(Boolean);
    UI.entete({ titre: "Stock", retour: true,
      sous: !produits.length ? "Aucun produit"
        : alertes.length ? alertes.join(" · ")
        : "Tout est en stock",
      actions: '<button type="button" class="btn-ic" id="stock-actualiser" ' +
        'aria-label="Actualiser">' + UI.icone("actualiser") + "</button>" });
    UI.$("#stock-actualiser").onclick = () => stock(vue);

    if (!produits.length) {
      vue.innerHTML = UI.vide("boite", "Aucun produit pour l'instant",
        "Ajoutez un produit : son stock se suivra ici.",
        '<a class="btn" href="#/produit/nouveau">' + UI.icone("plus") + "Ajouter un produit</a>");
      return;
    }

    /* Rupture et stock bas restent toujours à l'écran, même à zéro : un
       « 0 » dit que tout va bien, une puce absente ne dit rien. */
    const puces = ORDRE_STOCK.filter((k) =>
      k === "rupture" || k === "bas" || combien[k] || filtreStock === k);

    vue.innerHTML =
      '<div class="carte stock-aide">' +
        '<p class="aide" style="margin:0">' +
          (peutModifier
            ? "Chaque vente payée se décompte toute seule, et une commande annulée " +
              "rend ses pièces. Touchez un produit pour saisir un arrivage ou " +
              "corriger le chiffre après un comptage."
            : "Chaque vente payée se décompte toute seule. Votre compte consulte " +
              "le stock sans le modifier : demandez ce droit à l'administrateur.") +
        "</p>" +
      "</div>" +
      '<div class="recherche-boite">' + UI.icone("recherche", "ic-sm") +
        '<input id="stock-recherche" type="search" placeholder="Rechercher un produit…" ' +
          'autocomplete="off" value="' + Utils.echapper(termeStock) + '">' +
      "</div>" +
      '<div class="puces" id="stock-filtres">' +
        '<button type="button" class="puce' + (filtreStock ? "" : " active") +
          '" data-filtre="">Tout (' + produits.length + ")</button>" +
        puces.map((k) =>
          '<button type="button" class="puce' + (filtreStock === k ? " active" : "") +
          '" data-filtre="' + k + '">' + ETATS_STOCK[k].puce + " (" + combien[k] + ")</button>"
        ).join("") +
      "</div>" +
      '<div id="stock-liste"></div>';

    const zone = UI.$("#stock-liste");
    const rendre = () => {
      let visibles = filtreStock
        ? produits.filter((p) => etatStock(p) === filtreStock)
        : produits;
      visibles = Store.chercherProduits(visibles, termeStock).slice().sort((a, b) =>
        ORDRE_STOCK.indexOf(etatStock(a)) - ORDRE_STOCK.indexOf(etatStock(b)) ||
        a.stock - b.stock ||
        String(a.nom).localeCompare(String(b.nom), "fr"));
      if (visibles.length) {
        zone.innerHTML = '<div class="carte carte-liste">' +
          visibles.map((p) => ligneStock(p, peutModifier)).join("") + "</div>";
      } else if (!termeStock && (filtreStock === "rupture" || filtreStock === "bas")) {
        zone.innerHTML = UI.vide("check",
          filtreStock === "rupture" ? "Aucun produit en rupture" : "Aucun produit bientôt épuisé",
          "Vos clients trouvent tout ce qu'ils cherchent.");
      } else {
        zone.innerHTML = UI.vide("recherche", "Aucun produit trouvé",
          "Essayez un autre mot ou un autre filtre.");
      }
    };

    UI.$("#stock-recherche").addEventListener("input", Utils.tempo((ev) => {
      termeStock = ev.target.value;
      rendre();
    }, 200));

    for (const b of UI.$$("#stock-filtres [data-filtre]")) {
      b.onclick = () => {
        filtreStock = b.dataset.filtre;
        for (const x of UI.$$("#stock-filtres [data-filtre]")) x.classList.toggle("active", x === b);
        rendre();
      };
    }

    /* La liste a pu vieillir pendant qu'on la lisait : la feuille s'ouvre
       sur le chiffre du moment, relu en base, pas sur celui de l'écran. */
    zone.addEventListener("click", async (ev) => {
      const ligne = ev.target.closest("[data-stock]");
      if (!ligne || ligne.disabled) return;
      const affiche = produits.find((x) => x.id === ligne.dataset.stock);
      if (!affiche) return;
      ligne.disabled = true;
      let frais;
      try {
        frais = await Store.lireProduit(affiche.id);
      } catch (_) {
        frais = affiche;   // hors ligne : la garde du stock veillera à l'écriture
      }
      ligne.disabled = false;
      if (!frais) {
        UI.toast("Ce produit n'existe plus.", "err");
        stock(vue);
        return;
      }
      feuilleStock(frais, () => stock(vue));
    });

    rendre();
  }

  /* =====================================================
     Vente flash : choisir la durée, ou l'arrêter
     ===================================================== */

  function feuilleFlash(p, auTermine) {
    const active = Store.enVenteFlash(p);
    const DUREES = [
      [24, "24 heures"], [48, "48 heures"], [72, "3 jours"], [168, "7 jours"],
    ];

    const corps = UI.ouvrirFeuille("Vente flash — " + p.nom,
      '<p class="aide" style="margin:0 0 14px">' +
        (active
          ? "Ce produit est en vente flash jusqu'au <strong>" +
            Utils.echapper(Utils.fmtDateHeure(p.flashFin)) + "</strong>. " +
            "Il défile sur l'accueil de l'application client, après les boutiques."
          : "Le produit défilera sur l'accueil de l'application client, après les " +
            "boutiques, jusqu'à la fin choisie — puis il en sortira tout seul.") + "</p>" +
      '<div class="champ">' +
        "<label>" + (active ? "Prolonger jusqu'à" : "Pendant") + "</label>" +
        '<div class="puces">' +
          DUREES.map(([h, nom]) =>
            '<button type="button" class="puce" data-flash-heures="' + h + '">' + nom + "</button>"
          ).join("") +
        "</div>" +
      "</div>" +
      '<div class="champ">' +
        '<label for="flash-fin">…ou choisissez la date et l\'heure de fin</label>' +
        '<input id="flash-fin" type="datetime-local">' +
        '<div class="aide">La vente flash s\'arrête d\'elle-même à cette échéance.</div>' +
      "</div>" +
      '<div class="btn-rangee" style="margin-top:16px">' +
        '<button type="button" class="btn" id="flash-enregistrer">' + UI.icone("check") +
          (active ? "Enregistrer la nouvelle fin" : "Lancer la vente flash") + "</button>" +
        (active
          ? '<button type="button" class="btn btn-clair btn-danger-clair" id="flash-retirer">' +
              UI.icone("fermer") + "Arrêter la vente flash</button>"
          : "") +
      "</div>");

    const champFin = UI.$("#flash-fin", corps);

    /** Une date locale -> la valeur d'un champ datetime-local. */
    const versChampDate = (ms) => {
      const d = new Date(ms - new Date(ms).getTimezoneOffset() * 60000);
      return d.toISOString().slice(0, 16);
    };
    champFin.min = versChampDate(Date.now() + 30 * 60000);
    if (active) champFin.value = versChampDate(p.flashFin);

    for (const bouton of UI.$$("[data-flash-heures]", corps)) {
      bouton.onclick = () => {
        champFin.value = versChampDate(Date.now() + Number(bouton.dataset.flashHeures) * 3600000);
        for (const x of UI.$$("[data-flash-heures]", corps)) x.classList.toggle("active", x === bouton);
      };
    }

    const appliquer = async (fin, message) => {
      try {
        await Store.majVenteFlash(p.id, fin);
        UI.fermerFeuille();
        UI.toast(message, "ok");
        auTermine();
      } catch (err) {
        UI.toast(err.message, "err");
      }
    };

    UI.$("#flash-enregistrer", corps).onclick = () => {
      if (!champFin.value) {
        UI.toast("Choisissez une durée ou une date de fin.", "err");
        return;
      }
      const fin = new Date(champFin.value).getTime();
      appliquer(fin, "Vente flash jusqu'au " + Utils.fmtDateHeure(fin));
    };
    const retirer = UI.$("#flash-retirer", corps);
    if (retirer) retirer.onclick = () => appliquer(null, "Vente flash arrêtée");
  }

  /* =====================================================
     Formulaire (création / modification)
     ===================================================== */

  /** Photos en cours d'édition : [{ id, apercu, chemin? (en ligne), dataUrl? (nouvelle) }] */
  let photosTravail = [];
  /** Vidéo en cours d'édition : { chemin, url } | { fichier, url, taille } | null */
  let videoTravail = null;

  function htmlPhotos() {
    let html = photosTravail.map((photo, i) =>
      '<div class="photo-boite">' +
        '<img src="' + photo.apercu + '" alt="Photo ' + (i + 1) + '" data-agrandir="' + i + '">' +
        (i === 0 ? '<span class="photo-principale">Principale</span>' : "") +
        '<button type="button" class="photo-retirer" data-retirer="' + i + '" aria-label="Retirer la photo">' +
          UI.icone("fermer", "ic-sm") + "</button>" +
      "</div>"
    ).join("");
    if (photosTravail.length < Store.MAX_PHOTOS) {
      html +=
        '<label class="photo-ajout">' +
          UI.icone("camera") + "<span>Ajouter</span>" +
          '<input type="file" accept="image/*" multiple hidden id="photo-fichier">' +
        "</label>";
    }
    return html;
  }

  function brancherPhotos(base) {
    const zone = UI.$("#photos-zone", base);

    const rafraichir = () => {
      zone.innerHTML = htmlPhotos();
      brancher();
    };

    const brancher = () => {
      const champ = UI.$("#photo-fichier", zone);
      if (champ) {
        champ.addEventListener("change", async () => {
          const fichiers = Array.from(champ.files || []).slice(0, Store.MAX_PHOTOS - photosTravail.length);
          for (const fichier of fichiers) {
            try {
              const { dataUrl } = await Utils.compresserImage(fichier);
              photosTravail.push({ id: Utils.uid("pho"), dataUrl, apercu: dataUrl });
            } catch (err) {
              UI.toast(err.message || "Photo illisible", "err");
            }
          }
          rafraichir();
        });
      }
      for (const b of UI.$$("[data-retirer]", zone)) {
        b.onclick = () => {
          photosTravail.splice(Number(b.dataset.retirer), 1);
          rafraichir();
        };
      }
      for (const img of UI.$$("[data-agrandir]", zone)) {
        img.onclick = () => UI.ouvrirVisionneuse(
          photosTravail.map((photo) => ({ src: photo.apercu })), Number(img.dataset.agrandir));
      }
    };

    rafraichir();
  }

  function htmlVideo() {
    if (videoTravail) {
      return (
        '<div class="video-boite">' +
          '<video src="' + Utils.echapper(videoTravail.url) + '" controls preload="metadata" playsinline></video>' +
          '<div class="video-pied">' +
            "<span>" + (videoTravail.taille
              ? "Nouvelle vidéo · " + Utils.echapper(Utils.tailleLisible(videoTravail.taille))
              : "Vidéo en ligne") + "</span>" +
            '<button type="button" class="btn-ic btn-ic-clair btn-ic-danger" data-video-retirer aria-label="Retirer la vidéo">' +
              UI.icone("poubelle", "ic-sm") + "</button>" +
          "</div>" +
        "</div>"
      );
    }
    return (
      '<label class="video-ajout">' +
        UI.icone("video") +
        "<span>Ajouter une vidéo</span>" +
        '<small>Facultatif · ' + Store.MAX_VIDEO_MO + ' Mo maximum</small>' +
        '<input type="file" accept="video/*" hidden id="video-fichier">' +
      "</label>"
    );
  }

  function brancherVideo(base) {
    const zone = UI.$("#video-zone", base);

    const rafraichir = () => {
      zone.innerHTML = htmlVideo();
      brancher();
    };

    const brancher = () => {
      const champ = UI.$("#video-fichier", zone);
      if (champ) {
        champ.addEventListener("change", () => {
          const fichier = champ.files && champ.files[0];
          if (!fichier) return;
          if (fichier.size > Store.MAX_VIDEO_MO * 1024 * 1024) {
            UI.toast("Vidéo trop lourde (" + Utils.tailleLisible(fichier.size) + ") : " +
              Store.MAX_VIDEO_MO + " Mo au maximum.", "err");
            return;
          }
          if (videoTravail && videoTravail.url && videoTravail.taille) URL.revokeObjectURL(videoTravail.url);
          videoTravail = { fichier, url: URL.createObjectURL(fichier), taille: fichier.size };
          rafraichir();
        });
      }
      const retirer = UI.$("[data-video-retirer]", zone);
      if (retirer) {
        retirer.onclick = () => {
          if (videoTravail && videoTravail.taille && videoTravail.url) URL.revokeObjectURL(videoTravail.url);
          videoTravail = null;
          rafraichir();
        };
      }
    };

    rafraichir();
  }


  async function formulaire(vue, id) {
    /* Retoucher un produit existant demande le droit de modification ;
       en créer un neuf reste ouvert à toute l'équipe. */
    if (id && !Supabase.peutModifierProduits()) {
      UI.entete({ titre: "Modifier le produit", retour: true });
      vue.innerHTML = UI.vide("cle", "Modification non autorisée",
        "Votre compte peut ajouter des produits, mais pas retoucher ceux du catalogue. " +
        "Demandez ce droit à l'administrateur.",
        '<a class="btn btn-clair" href="#/produit/' + Utils.echapper(id) + '">Revenir à la fiche</a>');
      return;
    }

    const existant = id ? await Store.lireProduit(id) : null;
    const referenceProposee = existant ? existant.reference : await Store.prochaineReference();
    if (id && !existant) {
      UI.entete({ titre: "Produit", retour: true });
      vue.innerHTML = UI.vide("alerte", "Produit introuvable", "");
      return;
    }
    const categories = await Store.listerCategories();
    /* LA CATÉGORIE NE SE CHOISIT PLUS : c'est le SECTEUR de la boutique,
       posé par l'enseigne. Ce qui se choisit, c'est le RAYON — une
       sous-catégorie de ce secteur, et d'aucun autre. */
    const maBoutique = Store.boutiqueCourante();
    const secteur = categories.find((c) => c.id === (maBoutique && maBoutique.categorieId));

    UI.entete({ titre: existant ? "Modifier le produit" : "Nouveau produit", retour: true });

    if (!secteur) {
      vue.innerHTML = UI.vide("categories", "Votre boutique n'a pas encore de secteur",
        "BIZZOO range les boutiques par secteur d'activité, et vos produits se classent " +
        "dans les rayons du vôtre. Demandez à l'enseigne de vous en attribuer un : " +
        "sans lui, un produit ne peut être rangé nulle part.");
      return;
    }
    if (!secteur.sousCategories.length) {
      vue.innerHTML = UI.vide("categories", "Aucun rayon dans votre secteur",
        "« " + secteur.nom + " » n'a encore aucun rayon. Demandez à l'enseigne d'en " +
        "ajouter : sans rayon, un produit ne peut pas être classé.");
      return;
    }

    photosTravail = [];
    videoTravail = null;
    if (existant) {
      photosTravail = await Store.photosDeProduit(existant.id);
      if (existant.video) videoTravail = { chemin: existant.video, url: existant.videoUrl };
    }


    /* Délai d'approvisionnement : de 1 à 8 jours. On rouvre le
       formulaire sur ce qu'il reste à courir, pas sur ce qui a été
       saisi le premier jour. */
    const joursAppro = [];
    for (let n = Store.APPRO_MIN; n <= Store.APPRO_MAX; n++) joursAppro.push(n);
    const restantAppro = existant ? Store.joursAppro(existant) : null;
    const joursChoisis = restantAppro !== null && restantAppro >= Store.APPRO_MIN
      ? Math.min(Store.APPRO_MAX, restantAppro)
      : 3;

    const tauxBoutique = Store.lireReglages().tauxMarge;
    const tauxRevBoutique = Store.lireReglages().tauxRevendeur;
    const modeRevBoutique = Store.lireReglages().revendeurMode;

    const boutiques = Store.listerBoutiques();
    const laBoutique = Store.boutiqueCourante();
    /* Un produit appartient à une boutique et n'en change plus : on le
       dit clairement, et l'administrateur choisit laquelle avant de
       créer. Sur un produit existant, c'est un rappel, pas un choix. */
    /* Seul le super administrateur crée dans une autre boutique que la
       sienne — les autres n'en ont qu'une. */
    const peutChoisirBoutique = boutiques.length > 1 && !existant && Supabase.estSuper();

    vue.innerHTML =
      (laBoutique
        ? '<div class="carte">' +
            '<div class="carte-titre">' + UI.icone("magasin", "ic-sm") + " Boutique</div>" +
            (peutChoisirBoutique
              ? '<div class="champ">' +
                  '<label for="p-boutique">Ce produit ira dans</label>' +
                  '<select id="p-boutique">' +
                    boutiques.map((b) =>
                      '<option value="' + Utils.echapper(b.id) + '"' +
                      (b.id === laBoutique.id ? " selected" : "") + ">" +
                      Utils.echapper(b.nomBoutique) + "</option>").join("") +
                  "</select>" +
                  '<div class="aide">Ses rayons, sa devise et sa marge suivent la boutique choisie.</div>' +
                "</div>"
              : '<p class="aide" style="margin:0">' +
                  (existant ? "Ce produit appartient à " : "Ce produit ira dans ") +
                  "<strong>" + Utils.echapper(laBoutique.nomBoutique) + "</strong>" +
                  (existant ? " et n'en change pas." : ".") + "</p>") +
          "</div>"
        : "") +
      '<div class="carte">' +
        '<div class="carte-titre">Photos <span class="aide-inline">(' + Store.MAX_PHOTOS + ' max, la première s\'affiche en vitrine)</span></div>' +
        '<div class="photos-zone" id="photos-zone"></div>' +
      "</div>" +

      '<div class="carte">' +
        '<div class="carte-titre">Vidéo de présentation <span class="aide-inline">(facultative)</span></div>' +
        '<div id="video-zone"></div>' +
      "</div>" +

      '<div class="carte">' +
        UI.champTexte({ id: "p-nom", label: "Nom du produit", valeur: existant ? existant.nom : "",
          obligatoire: true, placeholder: "Ex. Ordinateur portable HP 15" }) +
        (existant && existant.code
          ? '<div class="champ"><label>Code</label>' +
              '<div class="code-fige">' + UI.icone("bouclier", "ic-sm") +
                '<span class="code-produit">' + Utils.echapper(existant.code) + "</span>" +
                "<small>Donné par la base à la création. Il ne se corrige pas, " +
                "même par un super administrateur : c'est ce qui en fait un repère sûr.</small>" +
              "</div></div>"
          : '<div class="champ"><label>Code</label>' +
              '<div class="code-fige">' + UI.icone("bouclier", "ic-sm") +
                "<small>Le code sera donné par la base à l'enregistrement.</small>" +
              "</div></div>") +
        UI.champTexte({ id: "p-reference", label: "Référence", valeur: referenceProposee,
          aide: "Attribuée automatiquement, modifiable (elle apparaît sur la fiche et dans les commandes WhatsApp)." }) +
        UI.champZone({ id: "p-description", label: "Description", valeur: existant ? existant.description : "",
          lignes: 5, placeholder: "Caractéristiques, état, garantie…\nUne idée par ligne." }) +
      "</div>" +

      /* ---------- Prix ----------
         La boutique annonce ce qu'elle veut toucher — le prix BIZZOO.
         L'enseigne y ajoute SA marge, fixée en créant la boutique. La
         somme est le prix de vente : il se calcule, il ne se saisit
         pas. C'est ce qui rend les comptes de l'enseigne lisibles. */
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("promo", "ic-sm") + " Prix</div>" +
        UI.champMontant({ id: "p-grossiste", label: "Prix BIZZOO", obligatoire: true,
          valeur: existant && existant.prixGrossiste ? existant.prixGrossiste : "",
          aide: "Ce que la boutique touche sur cette vente. Il ne quitte jamais " +
            "l'application admin : ni vos clients ni les autres boutiques ne le voient." }) +
        '<div class="champ">' +
          "<label>Prix de vente</label>" +
          '<div class="champ-montant champ-fige">' +
            '<input id="p-prix" inputmode="numeric" readonly tabindex="-1" value="' +
              Utils.echapper(existant && existant.prix ? Utils.fmtNombre(existant.prix) : "") + '">' +
            '<span class="devise">' + Utils.echapper(Store.lireReglages().devise) + "</span>" +
          "</div>" +
          '<div class="aide">Prix BIZZOO + la marge de l\'enseigne (' +
            Utils.echapper(Utils.fmtTaux(tauxBoutique)) + " %). C'est le prix que voient " +
            "vos clients ; il se calcule tout seul et ne se modifie pas.</div>" +
        "</div>" +
        '<div id="p-marge"></div>' +
        /* Le taux revendeur de CET article. Vide — et c'est le cas de
           presque tous — le taux de la boutique s'applique. On ne le
           saisit que pour un article négocié à part. */
        '<div class="champ">' +
          '<label for="p-taux-revendeur">Taux revendeur de cet article ' +
            "<small>(optionnel)</small></label>" +
          '<div class="champ-montant">' +
            '<input id="p-taux-revendeur" inputmode="decimal" autocomplete="off"' +
              ' placeholder="' + Utils.echapper(Utils.fmtTaux(tauxRevBoutique)) + '"' +
              ' value="' + Utils.echapper(
                existant && existant.tauxRevendeur !== null && existant.tauxRevendeur !== undefined
                  ? Utils.fmtTaux(existant.tauxRevendeur) : "") + '">' +
            '<span class="devise">%</span>' +
          "</div>" +
          '<div class="aide">Laissez vide pour suivre la boutique (' +
            Utils.echapper(Utils.fmtTaux(tauxRevBoutique)) + " %).</div>" +
        "</div>" +
        UI.champMontant({ id: "p-ancien", label: "Prix barré (optionnel)",
          valeur: existant && existant.ancienPrix ? existant.ancienPrix : "",
          aide: "L'ancien prix, pour afficher une promotion (« -15 % »)." }) +
      "</div>" +

      '<div class="carte">' +
        '<div class="champ">' +
          "<label>Secteur de la boutique</label>" +
          '<div class="lecture-seule">' + Utils.echapper(secteur.nom) + "</div>" +
          '<div class="aide">Posé par BIZZOO. Vos produits se rangent dans ses rayons, ' +
            "et dans ceux-là seulement.</div>" +
        "</div>" +
        '<div class="champ">' +
          '<label for="p-souscategorie">Rayon <span class="obligatoire">*</span></label>' +
          '<select id="p-souscategorie">' +
            '<option value="">— Choisissez un rayon —</option>' +
            secteur.sousCategories.map((sc) =>
              '<option value="' + Utils.echapper(sc.id) + '"' +
                ((existant && existant.sousCategorieId === sc.id) ? " selected" : "") + ">" +
                Utils.echapper(sc.nom) + "</option>").join("") +
          "</select>" +
          '<div class="aide">C\'est sous ce rayon que vos clients trouveront le produit ' +
            "dans l'écran « Catégories » de BIZZOO.</div>" +
        "</div>" +
      "</div>" +

      '<div class="carte">' +
        UI.interrupteur({ id: "p-sur-commande", label: "Produit sur commande",
          actif: existant ? !!existant.surCommande : false,
          aide: "Vous ne le tenez pas en boutique : il est commandé à la demande. Pas de stock à saisir." }) +
        UI.interrupteur({ id: "p-appro", label: "Produit en cours d'approvisionnement",
          actif: existant ? Store.enAppro(existant) : false,
          aide: "Il n'est pas en boutique mais il arrive. Vos clients voient le nombre " +
            "de jours qui restent, décompté chaque jour." }) +
        '<div class="champ" id="p-zone-appro">' +
          '<label for="p-appro-jours">Arrive dans</label>' +
          '<select id="p-appro-jours">' +
            joursAppro.map((n) =>
              '<option value="' + n + '"' + (n === joursChoisis ? " selected" : "") + ">" +
              n + (n > 1 ? " jours" : " jour") + "</option>").join("") +
          "</select>" +
          '<div class="aide">Le décompte se fait tout seul. Passée la date, le produit ' +
            "repasse « En rupture » : vous n'avez qu'à saisir le stock reçu.</div>" +
        "</div>" +
        '<div id="p-zone-stock">' +
          UI.champTexte({ id: "p-stock", label: "Stock", type: "tel",
            valeur: existant ? existant.stock : "",
            placeholder: "0",
            aide: "Nombre de pièces en boutique. À zéro, vos clients voient « En rupture »." }) +
        "</div>" +
        (Supabase.estAdmin()
          ? UI.interrupteur({ id: "p-avant", label: "Mettre en avant",
              actif: existant ? !!existant.enAvant : false,
              aide: "Le produit défile dans le slider client, après les images (" +
                Store.MAX_EN_AVANT + " produits au maximum)." })
          : "") +
      "</div>" +

      '<div class="btn-rangee">' +
        '<button type="button" class="btn" id="p-enregistrer">' + UI.icone("check") +
          (existant ? "Enregistrer les modifications" : "Ajouter le produit") + "</button>" +
        (existant
          ? '<button type="button" class="btn btn-clair btn-danger-clair" id="p-supprimer">' +
              UI.icone("poubelle") + "Supprimer le produit</button>"
          : "") +
      "</div>";

    brancherPhotos(vue);
    brancherVideo(vue);

    /* Trois façons d'être indisponible, qui s'excluent : sur commande,
       en cours d'approvisionnement, ou simplement un stock à saisir. */
    const surCommande = UI.$("#p-sur-commande");
    const appro = UI.$("#p-appro");
    const zoneStock = UI.$("#p-zone-stock");
    const zoneAppro = UI.$("#p-zone-appro");
    const majZones = () => {
      zoneStock.hidden = surCommande.checked || appro.checked;
      zoneAppro.hidden = !appro.checked;
    };
    surCommande.addEventListener("change", () => {
      if (surCommande.checked) appro.checked = false;
      majZones();
    });
    appro.addEventListener("change", () => {
      if (appro.checked) surCommande.checked = false;
      majZones();
    });
    majZones();

    /* Changer de boutique change tout le reste — rayons, devise, marge :
       on rouvre le formulaire sur la boutique choisie. */
    const champBoutique = UI.$("#p-boutique");
    if (champBoutique) {
      champBoutique.addEventListener("change", () => {
        try {
          const ouverte = Store.choisirBoutique(champBoutique.value);
          UI.toast("Produit pour « " + ouverte.nomBoutique + " »", "ok");
          formulaire(vue, id);
        } catch (err) {
          UI.toast(err.message, "err");
        }
      });
    }


    /* ---------- Prix grossiste → prix public ----------
       Les trois champs se répondent : toucher au prix d'achat ou au taux
       recalcule le prix public ; corriger le prix public à la main
       recalcule le taux. Le bandeau du dessous dit le bénéfice. */

    const champGrossiste = UI.$("#p-grossiste");
    const champPrix = UI.$("#p-prix");
    const zoneMarge = UI.$("#p-marge");
    const devise = Store.lireReglages().devise;

    const lireGrossiste = () => Math.max(0, Math.round(Utils.lireNombre(champGrossiste.value) || 0));

    /* Le prix de vente découle du prix BIZZOO et de la marge de
       l'enseigne. Un seul sens : on ne remonte plus du prix de vente
       vers le taux, puisque le taux n'appartient plus à la boutique. */
    function recalculerPrix() {
      const bizzoo = lireGrossiste();
      const vente = bizzoo ? Store.prixPublic(bizzoo, tauxBoutique) : 0;
      champPrix.value = vente ? Utils.fmtNombre(vente) : "";
      /* Ce que paierait un revendeur validé, au taux de l'article s'il
         en a un, à celui de la boutique sinon. Un aperçu : c'est la base
         qui facture, et elle applique exactement la même règle. */
      const champTauxRev = UI.$("#p-taux-revendeur");
      const saisi = champTauxRev ? Utils.lireNombre(champTauxRev.value) : null;
      const tauxRev = saisi === null || saisi === undefined || champTauxRev.value.trim() === ""
        ? tauxRevBoutique : saisi;
      const revendeur = bizzoo ? Store.prixRevendeur(vente, bizzoo, tauxRev, modeRevBoutique) : 0;

      zoneMarge.innerHTML = bizzoo
        ? '<div class="note-marge">' + UI.icone("promo", "ic-sm") +
            "<span>La boutique touche <strong>" +
              Utils.echapper(Utils.fmtMontant(bizzoo, devise)) + "</strong>, " +
              "BIZZOO garde <strong>" +
              Utils.echapper(Utils.fmtMontant(vente - bizzoo, devise)) + "</strong> " +
              "(" + Utils.echapper(Utils.fmtTaux(tauxBoutique)) + " %) par pièce.</span>" +
          "</div>" +
          '<div class="note-marge">' + UI.icone("personne", "ic-sm") +
            "<span>Un revendeur validé paie <strong>" +
              Utils.echapper(Utils.fmtMontant(revendeur, devise)) + "</strong> — " +
              "BIZZOO y garde <strong>" +
              Utils.echapper(Utils.fmtMontant(Math.max(0, revendeur - bizzoo), devise)) +
              "</strong>.</span>" +
          "</div>"
        : '<div class="aide" style="margin:-6px 0 14px">Indiquez le prix BIZZOO : ' +
            "le prix de vente s'en déduit.</div>";
    }

    champGrossiste.addEventListener("input", Utils.tempo(recalculerPrix, 350));
    /* Le taux revendeur change l'aperçu, pas le prix de vente — mais on
       repasse par le même calcul : il n'y a qu'un endroit où il se fait. */
    const champTauxRevendeur = UI.$("#p-taux-revendeur");
    if (champTauxRevendeur) {
      champTauxRevendeur.addEventListener("input", Utils.tempo(recalculerPrix, 350));
    }
    recalculerPrix();

    /* LE STOCK TEL QU'ON L'A MONTRÉ. Les ventes le font baisser pendant
       qu'on retouche la fiche : la base ne remplace que ce chiffre-là, et
       seulement si on l'a changé (voir Store.sauverProduit). */
    let stockVu = existant ? existant.stock : undefined;

    const btnEnregistrer = UI.$("#p-enregistrer");
    btnEnregistrer.onclick = async () => {
      /* UN SEUL ENVOI À LA FOIS. Deux appuis rapprochés — ou un réseau
         lent qui pousse à réappuyer — créaient DEUX produits, avec la même
         référence et les mêmes photos : c'est arrivé en ligne, à deux et
         six secondes d'écart. Le contrôle de la référence ne les arrêtait
         pas, puisque chaque envoi le passait avant que l'autre n'écrive.
         Le bouton ne revient qu'en cas d'échec : après un succès, on
         quitte l'écran. */
      btnEnregistrer.disabled = true;
      try {
        const produit = await Store.sauverProduit({
          id: existant ? existant.id : null,
          nom: UI.$("#p-nom").value,
          reference: UI.$("#p-reference").value,
          description: UI.$("#p-description").value,
          prixGrossiste: champGrossiste.value,
          /* Ni taux de marge ni prix de vente : ils découlent de la marge
             de l'enseigne, que la boutique ne choisit pas. Le taux
             REVENDEUR, lui, se règle article par article — vide, c'est
             celui de la boutique qui s'applique. */
          tauxRevendeur: champTauxRevendeur ? champTauxRevendeur.value : "",
          ancienPrix: UI.$("#p-ancien").value.trim(),
          /* On n'envoie PAS de catégorie : le déclencheur la déduit du
             rayon. En envoyer une n'aurait aucun effet, et laisserait
             croire que l'application décide du classement. */
          sousCategorieId: UI.$("#p-souscategorie").value,
          stock: UI.$("#p-stock").value,
          stockVu,
          surCommande: UI.$("#p-sur-commande").checked,
          approJours: UI.$("#p-appro").checked ? Number(UI.$("#p-appro-jours").value) : 0,
          /* Sans l'interrupteur à l'écran (modérateur), la mise en avant ne bouge pas. */
          enAvant: UI.$("#p-avant") ? UI.$("#p-avant").checked : (existant ? !!existant.enAvant : false),
          video: videoTravail,
        }, photosTravail);
        UI.toast(existant ? "Produit modifié" : "Produit ajouté", "ok");
        location.hash = "#/produit/" + produit.id;
      } catch (err) {
        btnEnregistrer.disabled = false;
        /* Une vente est passée pendant la retouche : on garde ce qui a
           été tapé, on montre le chiffre du moment, et le prochain appui
           part de lui. */
        if (err.stockActuel !== undefined) {
          stockVu = err.stockActuel;
          let note = UI.$("#p-stock-change");
          if (!note) {
            note = document.createElement("div");
            note.id = "p-stock-change";
            note.className = "note-attente";
            UI.$("#p-zone-stock").appendChild(note);
          }
          note.textContent = "Stock actuel en base : " + err.stockActuel +
            ". Corrigez le champ si besoin, puis enregistrez.";
        }
        UI.toast(err.message || "Enregistrement impossible", "err");
      }
    };

    const btnSupprimer = UI.$("#p-supprimer");
    if (btnSupprimer) {
      btnSupprimer.onclick = async () => {
        const ok = await UI.confirmer({
          titre: "Supprimer ce produit ?",
          texte: "« " + existant.nom + " » et ses photos seront retirés du catalogue. " +
            "La suppression sera visible en ligne à la prochaine publication.",
          bouton: "Supprimer",
          danger: true,
        });
        if (!ok) return;
        /* Un refus — un droit qui manque, un réseau coupé — ne se
           disait nulle part : l'écran restait là, sans un mot. */
        btnSupprimer.disabled = true;
        try {
          await Store.supprimerProduit(existant.id);
          UI.toast("Produit supprimé");
          location.hash = "#/produits";
        } catch (err) {
          btnSupprimer.disabled = false;
          UI.toast(err.message || "Suppression impossible", "err");
        }
      };
    }
  }

  /* =====================================================
     Fiche produit
     ===================================================== */

  async function detail(vue, id) {
    const p = await Store.lireProduit(id);
    if (!p) {
      UI.entete({ titre: "Produit", retour: true });
      vue.innerHTML = UI.vide("alerte", "Produit introuvable",
        "Il a peut-être été supprimé.",
        '<a class="btn btn-clair" href="#/produits">Voir les produits</a>');
      return;
    }

    const [photos, categories] = await Promise.all([
      Store.photosDeProduit(p.id), Store.listerCategories(),
    ]);
    const categorie = categories.find((c) => c.id === p.categorieId);
    const sousCategorie = categorie && (categorie.sousCategories || []).find((s) => s.id === p.sousCategorieId);
    const devise = Store.lireReglages().devise;
    const remise = Utils.remisePourcent(p.ancienPrix, p.prix);
    /* Sans le droit de modification, la fiche reste consultable mais
       tous les chemins qui mènent au formulaire disparaissent. */
    const peutModifier = Supabase.peutModifierProduits();

    UI.entete({ titre: p.nom, retour: true, actions: peutModifier
      ? '<a class="btn-ic" href="#/produit/' + Utils.echapper(p.id) + '/modifier" aria-label="Modifier">' +
        UI.icone("crayon") + "</a>"
      : "" });

    let html = "";

    if (photos.length) {
      html += '<div class="photos-bande">' +
        photos.map((photo, i) =>
          '<img src="' + photo.apercu + '" alt="Photo ' + (i + 1) +
          '" data-photo="' + i + '" class="photos-bande-img">').join("") +
      "</div>";
    } else {
      html += '<div class="carte photo-absente">' + UI.icone("image") +
        "<span>Aucune photo — les produits avec photo attirent bien plus de clients.</span></div>";
    }

    html +=
      '<div class="carte">' +
        '<div class="fiche-badges">' + UI.badgesProduit(p) + "</div>" +
        '<h2 class="fiche-nom">' + Utils.echapper(p.nom) + "</h2>" +
        '<div class="prix prix-grand">' +
          '<span class="prix-actuel">' + Utils.echapper(Utils.fmtMontant(p.prix, devise)) + "</span>" +
          (remise !== null ? '<s class="prix-ancien">' + Utils.echapper(Utils.fmtMontant(p.ancienPrix, devise)) + "</s>" : "") +
        "</div>" +
        '<div class="aide" style="margin-top:6px">' +
          (p.code ? '<span class="code-produit">Code ' + Utils.echapper(p.code) + "</span> " : "") +
          (p.reference ? "Réf : " + Utils.echapper(p.reference) + " · " : "") +
          Utils.echapper(categorie ? categorie.nom + (sousCategorie ? " · " + sousCategorie.nom : "") : "Sans catégorie") +
          " — modifié le " + Utils.echapper(Utils.fmtDate(p.modifieLe)) +
          (Store.boutiqueCourante()
            ? "<br>Boutique : " + Utils.echapper(Store.boutiqueCourante().nomBoutique)
            : "") +
        "</div>" +
      "</div>";

    /* Le détail des prix ne sort jamais de l'application admin. */
    if (p.prixGrossiste) {
      const benefice = p.prix - p.prixGrossiste;
      const tauxReel = Store.tauxDepuisPrix(p.prixGrossiste, p.prix);
      html +=
        '<div class="carte">' +
          '<div class="carte-titre">' + UI.icone("promo", "ic-sm") + " Marge " +
            '<span class="aide-inline">(visible ici seulement)</span></div>' +
          '<div class="marge-grille">' +
            "<div><span>Prix BIZZOO</span><strong>" +
              Utils.echapper(Utils.fmtMontant(p.prixGrossiste, devise)) + "</strong></div>" +
            "<div><span>Prix de vente</span><strong>" +
              Utils.echapper(Utils.fmtMontant(p.prix, devise)) + "</strong></div>" +
            "<div><span>Marge BIZZOO</span><strong>" +
              Utils.echapper(Utils.fmtTaux(tauxReel)) + " %</strong></div>" +
            '<div><span>Bénéfice de BIZZOO</span><strong' +
              (benefice < 0 ? ' class="marge-perte"' : "") + ">" +
              Utils.echapper(Utils.fmtMontant(benefice, devise)) + "</strong></div>" +
          "</div>" +
          (p.stock > 0
            ? '<div class="aide" style="margin:12px 0 0">Sur les ' + p.stock +
              " pièce" + (p.stock > 1 ? "s" : "") + " en boutique : <strong>" +
              Utils.echapper(Utils.fmtMontant(benefice * p.stock, devise)) +
              "</strong> pour BIZZOO si tout part.</div>"
            : "") +
        "</div>";
    }

    if (p.videoUrl) {
      html += '<div class="carte"><div class="carte-titre">' + UI.icone("video", "ic-sm") +
        " Vidéo de présentation</div>" +
        '<video class="video-lecture" src="' + Utils.echapper(p.videoUrl) +
        '" controls preload="metadata" playsinline></video></div>';
    }

    if (p.description) {
      html += '<div class="carte"><div class="carte-titre">Description</div>' +
        '<div class="fiche-description">' +
          p.description.split(/\n+/).filter((l) => l.trim()).map((l) => "<p>" + Utils.echapper(l.trim()) + "</p>").join("") +
        "</div></div>";
    }

    /* Le slider de l'application client se compose côté administrateur. */
    const admin = Supabase.estAdmin();
    html += peutModifier
      ? '<div class="carte">' +
          '<div class="carte-titre">Actions rapides</div>' +
          '<div class="btn-rangee">' +
            (admin
              ? '<button type="button" class="btn' + (p.enAvant ? " btn-clair" : "") + '" id="p-basculer-avant">' +
                UI.icone(p.enAvant ? "fermer" : "etoile") +
                (p.enAvant ? "Retirer du slider" : "Mettre en avant (slider)") + "</button>"
              : "") +
            '<button type="button" class="btn btn-clair" id="p-modifier-stock">' +
              UI.icone("boite") + "Modifier la disponibilité</button>" +
            '<button type="button" class="btn btn-clair" id="p-vente-flash">' +
              UI.icone("energie") +
              (Store.enVenteFlash(p)
                ? "Vente flash — jusqu'au " + Utils.echapper(Utils.fmtDateHeure(p.flashFin))
                : "Mettre en vente flash") + "</button>" +
            '<a class="btn btn-clair" href="#/produit/' + Utils.echapper(p.id) + '/modifier">' +
              UI.icone("crayon") + "Modifier le produit</a>" +
          "</div>" +
        "</div>"
      : '<div class="carte">' +
          '<div class="carte-titre">' + UI.icone("cle", "ic-sm") + " Lecture seule</div>" +
          '<p class="aide" style="margin:0">Votre compte ajoute des produits mais ne modifie pas ' +
            "ceux du catalogue. Demandez ce droit à l'administrateur.</p>" +
        "</div>";

    vue.innerHTML = html;

    const serie = photos.map((photo) => ({ src: photo.apercu }));
    for (const img of UI.$$("[data-photo]", vue)) {
      img.addEventListener("click", () => UI.ouvrirVisionneuse(serie, Number(img.dataset.photo)));
    }

    if (!peutModifier) return;

    if (admin) {
      const basculer = UI.$("#p-basculer-avant");
      basculer.onclick = async () => {
        /* Un double appui basculait deux fois : le produit revenait à
           son état de départ, et le message disait le contraire. */
        basculer.disabled = true;
        try {
          const maj = await Store.basculerEnAvant(p.id);
          UI.toast(maj.enAvant ? "Ajouté au slider client" : "Retiré du slider", "ok");
          detail(vue, p.id);
        } catch (err) {
          basculer.disabled = false;
          UI.toast(err.message, "err");
        }
      };
    }

    UI.$("#p-modifier-stock").onclick = () => feuilleStock(p, () => detail(vue, p.id));
    UI.$("#p-vente-flash").onclick = () => feuilleFlash(p, () => detail(vue, p.id));
  }

  return { liste, stock, formulaire, detail };
})();
