/* =========================================================
   Historique — tout ce qui a été fait dans l'application :
   date, heure, opération, produit concerné, utilisateur.
   ========================================================= */
const VueHistorique = (() => {

  const PAR_PAGE = 60;

  const FAMILLES = [
    { cle: "", nom: "Tout" },
    { cle: "produit", nom: "Produits" },
    { cle: "categorie", nom: "Catégories" },
    { cle: "slider", nom: "Slider" },
    { cle: "boutique", nom: "Boutique" },
    { cle: "compte", nom: "Compte" },
  ];

  /* Chaque type d'action a son icône et sa couleur. */
  const ASPECTS = {
    ajout: { icone: "plus", teinte: "vert" },
    modification: { icone: "crayon", teinte: "bleu" },
    suppression: { icone: "poubelle", teinte: "rouge" },
    mise_en_avant: { icone: "etoile", teinte: "or" },
    retrait_avant: { icone: "etoile", teinte: "gris" },
    stock: { icone: "boite", teinte: "bleu" },
    rupture: { icone: "alerte", teinte: "rouge" },
    appro: { icone: "horloge", teinte: "or" },
    retour_stock: { icone: "check", teinte: "vert" },
    ordre_slider: { icone: "haut", teinte: "bleu" },
    ordre: { icone: "haut", teinte: "bleu" },
    connexion: { icone: "cle", teinte: "gris" },
    deconnexion: { icone: "cle", teinte: "gris" },
    activation: { icone: "personne", teinte: "vert" },
    desactivation: { icone: "personne", teinte: "rouge" },
  };

  let famille = "";
  let entrees = [];
  let toutCharge = false;

  function aspect(entree) {
    return ASPECTS[entree.action] || { icone: "horloge", teinte: "gris" };
  }

  /** « aujourd'hui », « hier », sinon la date complète. */
  function titreDuJour(date) {
    const jour = new Date(date);
    const aujourdhui = new Date();
    const hier = new Date(Date.now() - 86400000);
    const memeJour = (a, b) => a.toDateString() === b.toDateString();
    if (memeJour(jour, aujourdhui)) return "Aujourd'hui";
    if (memeJour(jour, hier)) return "Hier";
    return Utils.fmtDate(date);
  }

  function htmlEntree(entree) {
    const a = aspect(entree);
    /* Annuler, c'est écrire dans les tables : le superadministrateur
       seul le peut, et la base le vérifie de son côté. */
    const annulable = entree.annulable && Supabase.estSuper();
    return (
      '<div class="histo-ligne' + (entree.annuleLe ? " histo-annulee" : "") + '">' +
        '<span class="histo-rond histo-' + a.teinte + '">' + UI.icone(a.icone, "ic-sm") + "</span>" +
        '<span class="histo-corps">' +
          '<span class="histo-libelle">' + Utils.echapper(entree.libelle) + "</span>" +
          '<span class="histo-details">' +
            Utils.echapper(Utils.fmtHeure(entree.date)) +
            (entree.utilisateur ? " · " + Utils.echapper(entree.utilisateur) : "") +
            (entree.cible ? " · " + Utils.echapper(entree.cible) : "") +
          "</span>" +
          (entree.annuleLe
            ? '<span class="histo-marque-annulee">' + UI.icone("actualiser", "ic-sm") +
              " Annulée" + (entree.annulePar ? " par " + Utils.echapper(entree.annulePar) : "") +
              "</span>"
            : "") +
        "</span>" +
        (annulable
          ? '<button type="button" class="btn-ic btn-ic-clair" data-annuler="' + entree.id +
            '" aria-label="Annuler cette action" title="Annuler cette action">' +
            UI.icone("actualiser", "ic-sm") + "</button>"
          : "") +
      "</div>"
    );
  }

  function htmlListe(liste) {
    if (!liste.length) {
      return UI.vide("horloge", "Aucune action enregistrée",
        famille ? "Essayez un autre filtre." : "Les modifications apparaîtront ici au fur et à mesure.");
    }
    let html = "";
    let jourCourant = null;
    for (const entree of liste) {
      const jour = titreDuJour(entree.date);
      if (jour !== jourCourant) {
        if (jourCourant !== null) html += "</div>";
        html += '<div class="histo-jour">' + Utils.echapper(jour) + "</div>" + '<div class="carte carte-liste">';
        jourCourant = jour;
      }
      html += htmlEntree(entree);
    }
    return html + "</div>";
  }

  function filtrees() {
    return famille ? entrees.filter((e) => e.famille === famille) : entrees;
  }

  function rendre(vue) {
    UI.$("#histo-liste", vue).innerHTML = htmlListe(filtrees());
    const bouton = UI.$("#histo-plus", vue);
    if (bouton) bouton.hidden = toutCharge || !entrees.length;
    brancherAnnulation(vue);
  }

  /** « Annuler » remet les lignes touchées telles qu'elles étaient. */
  function brancherAnnulation(vue) {
    for (const bouton of UI.$$("[data-annuler]", vue)) {
      bouton.onclick = async () => {
        const entree = entrees.find((e) => String(e.id) === bouton.dataset.annuler);
        if (!entree) return;
        const ok = await UI.confirmer({
          titre: "Annuler cette action ?",
          texte: "« " + entree.libelle + " »\n\nTout revient comme avant cette action. " +
            "Ce qui a été fait depuis, sur les mêmes fiches, sera écrasé.",
          bouton: "Annuler l'action",
          danger: true,
        });
        if (!ok) return;
        bouton.disabled = true;
        try {
          await Store.annulerAction(entree.id);
          UI.toast("Action annulée — tout est revenu comme avant", "ok");
          await afficher(vue);
        } catch (err) {
          UI.toast(err.message, "err");
          bouton.disabled = false;
        }
      };
    }
  }

  async function afficher(vue) {
    UI.entete({ titre: "Historique", retour: true, sous: "Toutes les actions de l'application" });

    vue.innerHTML =
      '<div class="puces" id="histo-filtres">' +
        FAMILLES.map((f) =>
          '<button type="button" class="puce' + (famille === f.cle ? " active" : "") +
          '" data-famille="' + f.cle + '">' + f.nom + "</button>").join("") +
      "</div>" +
      '<div id="histo-liste"><div class="chargement"><span class="chargement-rond"></span>Lecture du journal…</div></div>' +
      '<button type="button" class="btn btn-clair" id="histo-plus" hidden>' +
        UI.icone("bas") + "Voir les actions plus anciennes</button>";

    entrees = [];
    toutCharge = false;
    try {
      entrees = await Store.lireJournal(PAR_PAGE, 0);
      toutCharge = entrees.length < PAR_PAGE;
    } catch (err) {
      UI.$("#histo-liste", vue).innerHTML =
        '<div class="carte"><div class="carte-titre">Journal indisponible</div>' +
        '<p class="aide" style="margin:0">' + Utils.echapper(err.message) +
        "<br>Si la table vient d'être ajoutée, exécutez le fichier supabase/schema.sql.</p></div>";
      return;
    }
    rendre(vue);

    for (const bouton of UI.$$("#histo-filtres [data-famille]", vue)) {
      bouton.onclick = () => {
        famille = bouton.dataset.famille;
        for (const autre of UI.$$("#histo-filtres [data-famille]", vue)) {
          autre.classList.toggle("active", autre === bouton);
        }
        rendre(vue);
      };
    }

    UI.$("#histo-plus", vue).onclick = async () => {
      const bouton = UI.$("#histo-plus", vue);
      bouton.disabled = true;
      try {
        const suite = await Store.lireJournal(PAR_PAGE, entrees.length);
        entrees = entrees.concat(suite);
        toutCharge = suite.length < PAR_PAGE;
        rendre(vue);
      } catch (err) {
        UI.toast(err.message, "err");
      }
      bouton.disabled = false;
    };
  }

  return { afficher };
})();
