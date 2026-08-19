/* =========================================================
   Boutiques — les secteurs d'activité de l'enseigne.

   Chaque boutique a son catalogue, ses rayons, son slider et
   ses coordonnées. L'administrateur les crée et passe de
   l'une à l'autre ; le modérateur reste dans la sienne.
   ========================================================= */
const VueBoutiques = (() => {

  /* Le jeu d'icônes proposé à la création : de quoi représenter
     les secteurs les plus courants sans dessiner quoi que ce soit. */
  const ICONES = [
    ["magasin", "Boutique"], ["boite", "Matériel"], ["categories", "Rayons"],
    ["image", "Beauté"], ["nuage", "Services"], ["etoile", "Sélection"],
    ["promo", "Bons plans"], ["carte", "Point de vente"],
  ];

  const COULEURS = [
    ["#1176D8", "Bleu"], ["#E62329", "Rouge"], ["#0F9D58", "Vert"],
    ["#9A6B00", "Ocre"], ["#6C3FBF", "Violet"], ["#0B7C8C", "Turquoise"],
  ];

  /** Logo en cours de choix : { chemin } (en ligne), { dataUrl } (neuf) ou null. */
  let logoTravail = null;

  function pastille(b, taille) {
    const style = 'style="background:' + Utils.echapper(b.couleur || "#1176D8") + '"';
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
      UI.champTexte({ id: "bq-secteur", label: "Secteur d'activité",
        valeur: b ? b.secteur : "", placeholder: "Ex. Cosmétiques et beauté" }) +
      UI.champTexte({ id: "bq-slogan", label: "Slogan", valeur: b ? b.slogan : "",
        placeholder: "Une phrase courte, affichée en bandeau" }) +

      '<div class="champ">' +
        "<label>Icône</label>" +
        '<div class="choix-icones" id="bq-icones">' +
          ICONES.map(([cle, nom]) =>
            '<button type="button" class="choix-icone' +
              ((b ? b.icone : "magasin") === cle ? " actif" : "") +
              '" data-icone="' + cle + '" aria-label="' + Utils.echapper(nom) + '">' +
              UI.icone(cle) + "</button>").join("") +
        "</div>" +
      "</div>" +

      '<div class="champ">' +
        "<label>Couleur</label>" +
        '<div class="choix-couleurs" id="bq-couleurs">' +
          COULEURS.map(([code, nom]) =>
            '<button type="button" class="choix-couleur' +
              ((b ? b.couleur : "#1176D8") === code ? " actif" : "") +
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

    UI.$("#bq-enregistrer", corps).onclick = async () => {
      const bouton = UI.$("#bq-enregistrer", corps);
      bouton.disabled = true;
      try {
        const enregistree = await Store.sauverBoutique({
          id: boutique ? boutique.id : null,
          nomBoutique: UI.$("#bq-nom", corps).value,
          secteur: UI.$("#bq-secteur", corps).value.trim(),
          slogan: UI.$("#bq-slogan", corps).value.trim(),
          icone: choisi(corps, "#bq-icones", "icone", "magasin"),
          couleur: choisi(corps, "#bq-couleurs", "couleur", "#1176D8"),
          logo: logoTravail && logoTravail.dataUrl ? logoTravail : (logoTravail ? undefined : null),
          actif: boutique ? UI.$("#bq-actif", corps).checked : true,
        });
        UI.fermerFeuille();
        UI.toast(boutique ? "Boutique enregistrée" : "Boutique créée : " + enregistree.nomBoutique, "ok");
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

    UI.$("#bq-nouvelle").onclick = () => ouvrirFiche(null, () => afficher(vue));

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
