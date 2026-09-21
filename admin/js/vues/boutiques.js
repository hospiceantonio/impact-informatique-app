/* =========================================================
   Boutiques — les secteurs d'activité de l'enseigne.

   Chaque boutique a son catalogue, ses rayons, son slider et
   ses coordonnées. L'administrateur les crée et passe de
   l'une à l'autre ; le modérateur reste dans la sienne.
   ========================================================= */
const VueBoutiques = (() => {

  /* Le jeu d'icônes proposé à la création : un glyphe par grand
     secteur d'activité, sans rien avoir à dessiner. */
  const ICONES = [
    ["magasin", "Boutique"], ["boite", "Matériel"],
    ["portable", "Informatique"], ["telephone", "Téléphonie"],
    ["ecran", "TV & écrans"], ["casque", "Audio"],
    ["energie", "Énergie"], ["tshirt", "Mode & vêtements"],
    ["sacoche", "Sacs & cuir"], ["goutte", "Cosmétiques"],
    ["sante", "Santé & pharmacie"], ["couverts", "Restauration"],
    ["voiture", "Auto & moto"], ["outils", "Outillage"],
    ["livre", "Librairie"], ["ballon", "Sport"],
    ["diamant", "Bijoux"], ["cadeau", "Cadeaux"],
    ["categories", "Rayons"], ["image", "Galerie"],
    ["nuage", "Services"], ["etoile", "Sélection"],
    ["promo", "Bons plans"], ["carte", "Point de vente"],
  ];

  /* Le bleu et l'orange de BIZZOO ouvrent la liste ; les autres
     teintes servent à distinguer les secteurs d'un coup d'œil. */
  const COULEURS = [
    ["#0B5CF5", "Bleu BIZZOO"], ["#F96302", "Orange BIZZOO"], ["#0F9D58", "Vert"],
    ["#E62329", "Rouge"], ["#D81B60", "Rose"], ["#6C3FBF", "Violet"],
    ["#3F51B5", "Indigo"], ["#0B7C8C", "Turquoise"], ["#9A6B00", "Ocre"],
    ["#7A4A32", "Marron"], ["#546E7A", "Ardoise"], ["#001450", "Bleu nuit"],
  ];

  /* Une boutique enregistrée avec une icône ou une couleur qui ne figure
     plus dans les choix la garde : on l'ajoute à la volée, sinon rien ne
     serait sélectionné et l'enregistrement la remplacerait en silence. */
  function listeIcones(b) {
    const liste = ICONES.slice();
    if (b && b.icone && !liste.some(([cle]) => cle === b.icone)) {
      liste.push([b.icone, "Icône actuelle"]);
    }
    return liste;
  }

  function listeCouleurs(b) {
    const liste = COULEURS.slice();
    if (b && b.couleur && !liste.some(([code]) => code === b.couleur)) {
      liste.push([b.couleur, "Couleur actuelle"]);
    }
    return liste;
  }

  /** Logo en cours de choix : { chemin } (en ligne), { dataUrl } (neuf) ou null. */
  let logoTravail = null;

  function pastille(b, taille) {
    const style = 'style="background:' + Utils.echapper(b.couleur || "#0B5CF5") + '"';
    return b.logoUrl
      ? '<span class="bou-pastille bou-pastille-photo"><img src="' +
          Utils.echapper(b.logoUrl) + '" alt=""></span>'
      : '<span class="bou-pastille" ' + style + ">" +
          UI.icone(b.icone || "magasin", taille || "") + "</span>";
  }

  /* ---------- Liste ---------- */

  function htmlLigne(b, courante, premiere, derniere) {
    return (
      '<div class="bou-ligne' + (b.actif ? "" : " bou-fermee") + '">' +
        pastille(b) +
        '<span class="bou-corps">' +
          '<span class="bou-nom">' + Utils.echapper(b.nomBoutique) +
            (courante ? ' <span class="bou-courante">ouverte</span>' : "") + "</span>" +
          '<span class="bou-details">' +
            Utils.echapper(b.secteur || "Sans secteur") +
            (b.actif ? "" : " · fermée aux clients") +
          "</span>" +
        "</span>" +
        '<span class="bou-actions">' +
          '<button type="button" class="btn-ic btn-ic-clair" data-monter="' + Utils.echapper(b.id) +
            '" aria-label="Monter"' + (premiere ? " disabled" : "") + ">" + UI.icone("haut", "ic-sm") + "</button>" +
          '<button type="button" class="btn-ic btn-ic-clair" data-descendre="' + Utils.echapper(b.id) +
            '" aria-label="Descendre"' + (derniere ? " disabled" : "") + ">" + UI.icone("bas", "ic-sm") + "</button>" +
          '<button type="button" class="btn-ic btn-ic-clair" data-boutique="' + Utils.echapper(b.id) +
            '" aria-label="Modifier">' + UI.icone("crayon", "ic-sm") + "</button>" +
        "</span>" +
      "</div>"
    );
  }

  /* ---------- Fiche (création et modification) ---------- */

  function champsIdentite(b) {
    return (
      UI.champTexte({ id: "bq-nom", label: "Nom de la boutique", obligatoire: true,
        valeur: b ? b.nomBoutique : "", placeholder: "Ex. COSMÉTIQUES ET BEAUTÉ",
        aide: "C'est ce nom que les clients voient sous l'icône." }) +
      /* LE SECTEUR, ET IL EST OBLIGATOIRE. C'est la catégorie de BIZZOO
         où la boutique se range, et elle décide de ce qu'elle pourra
         classer : ses produits ne se rangent que dans les RAYONS de ce
         secteur. Sans lui, son catalogue reste en vente mais
         n'apparaît sous aucune catégorie chez le client.

         La liste se remplit après coup, quand les catégories sont
         lues : un « select » vide à l'ouverture ferait croire qu'il n'y
         a rien à choisir. */
      '<div class="champ">' +
        '<label for="bq-categorie">Secteur d\'activité <span class="obligatoire">*</span></label>' +
        '<select id="bq-categorie"><option value="">Lecture des catégories…</option></select>' +
        '<div class="aide">La catégorie de BIZZOO où se range cette boutique. ' +
          "Ses produits se classeront dans les rayons de ce secteur, et dans " +
          "ceux-là seulement.</div>" +
      "</div>" +
      UI.champTexte({ id: "bq-secteur", label: "Précision affichée sous le nom",
        valeur: b ? b.secteur : "", placeholder: "Ex. Cosmétiques et beauté",
        aide: "Texte libre, montré aux clients sous le nom de la boutique. " +
          "Il ne change rien au classement." }) +
      UI.champTexte({ id: "bq-slogan", label: "Slogan", valeur: b ? b.slogan : "",
        placeholder: "Une phrase courte, affichée en bandeau" }) +

      /* La marge de BIZZOO sur cette boutique. Elle se pose ici, à la
         création, et la boutique ne peut plus y toucher — la base le
         refuse. C'est ce que l'enseigne gagne sur chaque vente. */
      '<div class="champ">' +
        '<label for="bq-marge">Marge BIZZOO <span class="obligatoire">*</span></label>' +
        '<div class="champ-montant">' +
          '<input id="bq-marge" inputmode="decimal" autocomplete="off" placeholder="20"' +
            ' value="' + Utils.echapper(b ? Utils.fmtTaux(b.tauxMarge) : "20") + '">' +
          '<span class="devise">%</span>' +
        "</div>" +
        '<div class="aide">Ce que BIZZOO ajoute au prix annoncé par la boutique. ' +
          "La boutique saisit son prix, ce pourcentage s'y ajoute, et la somme " +
          "devient le prix de vente. Elle ne peut pas le modifier.</div>" +
      "</div>" +

      /* La marge sur les ventes aux REVENDEURS. Sans elle, un revendeur
         validé achèterait au prix BIZZOO exact : la boutique toucherait
         bien son dû, mais BIZZOO ne gagnerait rien, et le revendeur
         lirait article par article ce que la boutique touche. */
      '<div class="champ">' +
        "<label>Prix des revendeurs</label>" +
        '<div class="st-filtres" id="bq-revendeur-mode">' +
          '<button type="button" class="puce' +
            ((b && b.revendeurMode === "public") ? "" : " active") +
            '" data-mode="bizzoo">Prix BIZZOO + marge</button>' +
          '<button type="button" class="puce' +
            ((b && b.revendeurMode === "public") ? " active" : "") +
            '" data-mode="public">Prix public − remise</button>' +
        "</div>" +
        '<div class="champ-montant" style="margin-top:10px">' +
          '<input id="bq-marge-revendeur" inputmode="decimal" autocomplete="off" placeholder="10"' +
            ' value="' + Utils.echapper(b ? Utils.fmtTaux(b.tauxRevendeur) : "10") + '">' +
          '<span class="devise">%</span>' +
        "</div>" +
        '<div class="aide">Ce que paie un revendeur validé. Quel que soit le taux, ' +
          "il ne descend jamais sous le prix BIZZOO et ne dépasse jamais le prix " +
          "public. Un article peut avoir son propre taux, depuis sa fiche.</div>" +
      "</div>" +

      '<div class="champ">' +
        "<label>Icône</label>" +
        '<div class="choix-icones" id="bq-icones">' +
          listeIcones(b).map(([cle, nom]) =>
            '<button type="button" class="choix-icone' +
              ((b ? b.icone : "magasin") === cle ? " actif" : "") +
              '" data-icone="' + cle + '" aria-label="' + Utils.echapper(nom) + '">' +
              UI.icone(cle) + "</button>").join("") +
        "</div>" +
      "</div>" +

      '<div class="champ">' +
        "<label>Couleur</label>" +
        '<div class="choix-couleurs" id="bq-couleurs">' +
          listeCouleurs(b).map(([code, nom]) =>
            '<button type="button" class="choix-couleur' +
              ((b ? b.couleur : "#0B5CF5") === code ? " actif" : "") +
              '" data-couleur="' + code + '" style="background:' + code +
              '" aria-label="' + Utils.echapper(nom) + '"></button>').join("") +
        "</div>" +
        '<div class="aide">L\'icône et la couleur composent la vignette de la boutique ' +
          "sur l'accueil des clients.</div>" +
      "</div>" +

      '<div class="champ">' +
        "<label>Logo (facultatif)</label>" +
        '<div class="photos-zone" id="bq-logo"></div>' +
        '<div class="aide">Une image remplace l\'icône. Carrée de préférence.</div>' +
      "</div>"
    );
  }

  function brancherLogo(base) {
    const zone = UI.$("#bq-logo", base);

    const rendre = () => {
      const apercu = logoTravail
        ? (logoTravail.dataUrl || Supabase.urlImage(logoTravail.chemin))
        : "";
      zone.innerHTML = apercu
        ? '<div class="photo-boite">' +
            '<img src="' + Utils.echapper(apercu) + '" alt="Logo">' +
            '<button type="button" class="photo-retirer" id="bq-logo-retirer" aria-label="Retirer le logo">' +
              UI.icone("fermer", "ic-sm") + "</button>" +
          "</div>"
        : '<label class="photo-ajout">' + UI.icone("camera") + "<span>Ajouter</span>" +
            '<input type="file" accept="image/*" hidden id="bq-logo-fichier"></label>';
      brancher();
    };

    const brancher = () => {
      const champ = UI.$("#bq-logo-fichier", zone);
      if (champ) {
        champ.addEventListener("change", async () => {
          const fichier = champ.files && champ.files[0];
          if (!fichier) return;
          try {
            const { dataUrl } = await Utils.compresserImage(fichier, 600, 0.85);
            logoTravail = { dataUrl };
          } catch (err) {
            UI.toast(err.message || "Image illisible", "err");
          }
          rendre();
        });
      }
      const retirer = UI.$("#bq-logo-retirer", zone);
      if (retirer) retirer.onclick = () => { logoTravail = null; rendre(); };
    };

    rendre();
  }

  function brancherChoix(base) {
    for (const bouton of UI.$$("#bq-icones [data-icone]", base)) {
      bouton.onclick = () => {
        for (const x of UI.$$("#bq-icones [data-icone]", base)) x.classList.toggle("actif", x === bouton);
      };
    }
    for (const bouton of UI.$$("#bq-couleurs [data-couleur]", base)) {
      bouton.onclick = () => {
        for (const x of UI.$$("#bq-couleurs [data-couleur]", base)) x.classList.toggle("actif", x === bouton);
      };
    }
    /* ATTENTION, deux conventions cohabitent dans cette application :
       les icônes et les couleurs s'allument avec « actif », les PUCES
       avec « active » — c'est ce que la feuille de style connaît. Les
       mélanger donne un bouton qui a l'air choisi et qu'on ne lit pas. */
    for (const bouton of UI.$$("#bq-revendeur-mode [data-mode]", base)) {
      bouton.onclick = () => {
        for (const x of UI.$$("#bq-revendeur-mode [data-mode]", base)) {
          x.classList.toggle("active", x === bouton);
        }
      };
    }
  }

  /* Les puces s'allument avec « active », pas « actif » : « choisi »
     ci-dessous ne saurait pas les lire. */
  const modeRevendeur = (base) => {
    const actif = UI.$("#bq-revendeur-mode .active", base);
    return actif && actif.dataset.mode === "public" ? "public" : "bizzoo";
  };

  /* La liste des secteurs se lit en base : on la remplit une fois la
     feuille ouverte, plutôt que de faire attendre son affichage. */
  async function remplirSecteurs(base, boutique) {
    const select = UI.$("#bq-categorie", base);
    if (!select) return;
    let categories = [];
    try {
      categories = await Store.listerCategories();
    } catch (_) {
      select.innerHTML = '<option value="">Catégories indisponibles</option>';
      return;
    }
    if (!categories.length) {
      select.innerHTML = '<option value="">Aucune catégorie — créez-en d\'abord</option>';
      return;
    }
    const actuel = (boutique && boutique.categorieId) || "";
    select.innerHTML =
      '<option value="">— Choisissez un secteur —</option>' +
      categories.map((c) =>
        '<option value="' + Utils.echapper(c.id) + '"' +
          (c.id === actuel ? " selected" : "") + ">" +
          Utils.echapper(c.nom) + "</option>").join("");
  }

  const choisi = (base, selecteur, attribut, defaut) => {
    const actif = UI.$(selecteur + " .actif", base);
    return actif ? actif.dataset[attribut] : defaut;
  };

  function ouvrirFiche(boutique, apres) {
    logoTravail = boutique && boutique.logo ? { chemin: boutique.logo } : null;

    const corps = UI.ouvrirFeuille(boutique ? boutique.nomBoutique : "Nouvelle boutique",
      champsIdentite(boutique) +
      (boutique
        ? UI.interrupteur({ id: "bq-actif", label: "Boutique ouverte", actif: boutique.actif,
            aide: "Fermée, elle disparaît de l'application des clients. Son catalogue reste intact." })
        : "") +
      '<div class="btn-rangee" style="margin-top:18px">' +
        '<button type="button" class="btn" id="bq-enregistrer">' + UI.icone("check") +
          (boutique ? "Enregistrer" : "Créer la boutique") + "</button>" +
      "</div>" +
      (boutique
        ? '<div class="carte" style="box-shadow:none;padding:16px 0 0;margin-top:20px;border-top:1px solid var(--trait)">' +
            '<div class="carte-titre">' + UI.icone("poubelle", "ic-sm") + " Supprimer cette boutique</div>" +
            '<p class="aide" style="margin:-6px 0 12px">Définitif : ses produits, ses rayons et ' +
              "son slider partent avec elle. Pour la retirer des clients sans rien perdre, " +
              "fermez-la plutôt.</p>" +
            '<button type="button" class="btn btn-clair btn-danger-clair" id="bq-supprimer">' +
              UI.icone("poubelle") + "Supprimer définitivement</button>" +
          "</div>"
        : '<p class="aide" style="margin:14px 0 0">Vous réglerez ensuite ses coordonnées, ' +
          "ses photos et sa marge dans Réglages, une fois la boutique ouverte.</p>"));

    brancherChoix(corps);
    brancherLogo(corps);
    remplirSecteurs(corps, boutique);

    UI.$("#bq-enregistrer", corps).onclick = async () => {
      const bouton = UI.$("#bq-enregistrer", corps);
      bouton.disabled = true;
      try {
        const secteurVoulu = UI.$("#bq-categorie", corps).value;
        if (!secteurVoulu) throw new Error("Choisissez le secteur d'activité de la boutique.");

        /* CHANGER DE SECTEUR DÉCLASSE LE CATALOGUE : les produits sont
           rangés dans des rayons de l'ancien, que le nouveau n'a pas.
           La base refuse d'ailleurs l'écriture directe. On enregistre
           donc TOUT LE RESTE D'ABORD — avec l'ancien secteur, qui ne
           lève pas — puis on demande, en disant combien de produits
           perdront leur rayon. Faire l'inverse perdrait le nom, le
           slogan et l'icône si la question recevait « non ». */
        const changement = !!(boutique && boutique.categorieId
                              && secteurVoulu !== boutique.categorieId);

        const enregistree = await Store.sauverBoutique({
          id: boutique ? boutique.id : null,
          nomBoutique: UI.$("#bq-nom", corps).value,
          categorieId: changement ? boutique.categorieId : secteurVoulu,
          secteur: UI.$("#bq-secteur", corps).value.trim(),
          slogan: UI.$("#bq-slogan", corps).value.trim(),
          icone: choisi(corps, "#bq-icones", "icone", "magasin"),
          couleur: choisi(corps, "#bq-couleurs", "couleur", "#0B5CF5"),
          tauxMarge: UI.$("#bq-marge", corps).value,
          revendeurMode: modeRevendeur(corps),
          tauxRevendeur: UI.$("#bq-marge-revendeur", corps).value,
          logo: logoTravail && logoTravail.dataUrl ? logoTravail : (logoTravail ? undefined : null),
          actif: boutique ? UI.$("#bq-actif", corps).checked : true,
        });
        UI.feuilleSansRappel();
        UI.fermerFeuille();

        if (changement) {
          const combien = await Store.produitsClasses(boutique.id);
          const ok = await UI.confirmer({
            titre: "Changer le secteur ?",
            texte: combien
              ? combien + " produit" + (combien > 1 ? "s" : "") + " de cette boutique " +
                (combien > 1 ? "sont rangés" : "est rangé") + " dans les rayons du secteur " +
                "actuel. Le nouveau n'a pas les mêmes : " +
                (combien > 1 ? "ils repasseront" : "il repassera") + " « à classer » — " +
                "en vente, mais sous aucune catégorie — jusqu'à ce que la boutique " +
                (combien > 1 ? "les reclasse" : "le reclasse") + "."
              : "Aucun produit n'est encore classé : rien ne sera perdu.",
            bouton: "Changer le secteur",
            danger: combien > 0,
          });
          if (ok) {
            await Store.changerSecteur(boutique.id, secteurVoulu);
            UI.toast(combien
              ? "Secteur changé — " + combien + " produit" + (combien > 1 ? "s" : "") + " à reclasser"
              : "Secteur changé", "ok");
          } else {
            UI.toast("Le reste est enregistré ; le secteur n'a pas changé.");
          }
        } else {
          UI.toast(boutique ? "Boutique enregistrée"
                            : "Boutique créée : " + enregistree.nomBoutique, "ok");
        }
        apres();
      } catch (err) {
        UI.toast(err.message, "err");
        bouton.disabled = false;
      }
    };

    const btnSupprimer = UI.$("#bq-supprimer", corps);
    if (btnSupprimer) {
      btnSupprimer.onclick = async () => {
        UI.feuilleSansRappel();
        UI.fermerFeuille();
        const ok = await UI.confirmer({
          titre: "Supprimer " + boutique.nomBoutique + " ?",
          texte: "Tous ses produits, ses rayons et les images de son slider seront effacés " +
            "définitivement. Cette action ne se rattrape pas.",
          bouton: "Supprimer", danger: true,
        });
        if (!ok) return;
        try {
          await Store.supprimerBoutique(boutique.id);
          UI.toast("Boutique supprimée", "ok");
          apres();
        } catch (err) {
          UI.toast(err.message, "err");
        }
      };
    }
  }

  /* ---------- Écran ---------- */

  async function afficher(vue) {
    UI.entete({ titre: "Boutiques", retour: true, sous: "Les secteurs de l'enseigne" });

    const boutiques = Store.listerBoutiques();
    const courante = Store.boutiqueCourante();

    if (!boutiques.length) {
      vue.innerHTML =
        '<div class="carte"><div class="carte-titre">Boutiques indisponibles</div>' +
        '<p class="aide" style="margin:0">La base n\'a pas encore la table des boutiques : ' +
        "exécutez le dernier fichier SQL dans Supabase.</p></div>";
      return;
    }

    vue.innerHTML =
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("magasin", "ic-sm") + " Vos boutiques (" + boutiques.length + ")</div>" +
        '<p class="aide" style="margin:-4px 0 12px">Elles s\'affichent chez les clients dans cet ordre. ' +
          "Touchez le crayon pour changer le nom, l'icône ou fermer une boutique.</p>" +
        boutiques.map((b, i) =>
          htmlLigne(b, courante && b.id === courante.id, i === 0, i === boutiques.length - 1)).join("") +
        '<button type="button" class="btn" id="bq-nouvelle" style="margin-top:14px">' +
          UI.icone("plus") + "Créer une boutique</button>" +
      "</div>" +

      '<div class="carte">' +
        '<div class="carte-titre">Boutique ouverte</div>' +
        '<p class="aide" style="margin:0 0 12px">Produits, rayons, slider et réglages concernent ' +
          "la boutique ouverte. Touchez-en une pour y travailler.</p>" +
        '<div class="bou-choix">' +
          boutiques.map((b) =>
            '<button type="button" class="bou-vignette' +
              (courante && b.id === courante.id ? " actif" : "") +
              (b.actif ? "" : " bou-fermee") + '" data-ouvrir="' + Utils.echapper(b.id) + '">' +
              pastille(b) +
              "<span>" + Utils.echapper(b.nomBoutique) + "</span>" +
            "</button>").join("") +
        "</div>" +
      "</div>";

    const nouvelle = UI.$("#bq-nouvelle");
    if (nouvelle) nouvelle.onclick = () => ouvrirFiche(null, () => afficher(vue));

    for (const bouton of UI.$$("[data-boutique]", vue)) {
      bouton.onclick = () => {
        const b = boutiques.find((x) => x.id === bouton.dataset.boutique);
        if (b) ouvrirFiche(b, () => afficher(vue));
      };
    }
    for (const bouton of UI.$$("[data-monter]", vue)) {
      bouton.onclick = async () => {
        await Store.deplacerBoutique(bouton.dataset.monter, "haut");
        afficher(vue);
      };
    }
    for (const bouton of UI.$$("[data-descendre]", vue)) {
      bouton.onclick = async () => {
        await Store.deplacerBoutique(bouton.dataset.descendre, "bas");
        afficher(vue);
      };
    }
    for (const bouton of UI.$$("[data-ouvrir]", vue)) {
      bouton.onclick = () => {
        try {
          const ouverte = Store.choisirBoutique(bouton.dataset.ouvrir);
          UI.toast("Vous travaillez sur « " + ouverte.nomBoutique + " »", "ok");
          location.hash = "#/";
        } catch (err) {
          UI.toast(err.message, "err");
        }
      };
    }
  }

  return { afficher, pastille };
})();
