/* =========================================================
   Catégories — rayons et sous-catégories du catalogue :
   création, renommage, ordre d'affichage, suppression.
   ========================================================= */
const VueCategories = (() => {

  async function afficher(vue) {
    const [categories, produits] = await Promise.all([
      Store.listerCategories(), Store.listerProduits(),
    ]);
    const comptes = {};
    for (const p of produits) comptes[p.categorieId] = (comptes[p.categorieId] || 0) + 1;

    UI.entete({ titre: "Catégories", sous: "Les rayons visibles par vos clients" });

    let html =
      '<button type="button" class="btn" id="cat-ajouter">' + UI.icone("plus") + "Nouvelle catégorie</button>";

    if (categories.length) {
      html += categories.map((c, i) =>
        '<div class="carte cat-bloc">' +
          '<div class="cat-bloc-entete">' +
            '<span class="cat-bloc-nom">' + Utils.echapper(c.nom) + "</span>" +
            '<span class="cat-bloc-compte">' + (comptes[c.id] || 0) + " produit" + ((comptes[c.id] || 0) > 1 ? "s" : "") + "</span>" +
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
              : '<span class="aide">Aucune sous-catégorie — ajoutez-en avec le crayon.</span>') +
          "</div>" +
        "</div>"
      ).join("");
    } else {
      html += UI.vide("categories", "Aucune catégorie",
        "Créez vos rayons : Ordinateurs, Imprimantes, Consommables…");
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

  /* ---------- Feuille de création / modification ---------- */

  /** Sous-catégories en cours d'édition : [{ id?, nom }] */
  let sousTravail = [];

  function htmlSous() {
    return sousTravail.map((s, i) =>
      '<div class="sous-ligne">' +
        '<input type="text" value="' + Utils.echapper(s.nom) + '" data-sous="' + i + '" placeholder="Nom de la sous-catégorie">' +
        '<button type="button" class="btn-ic btn-ic-clair btn-ic-danger" data-sous-retirer="' + i + '" aria-label="Retirer">' +
          UI.icone("fermer", "ic-sm") + "</button>" +
      "</div>"
    ).join("") || '<p class="aide" style="margin:0">Aucune sous-catégorie pour l\'instant.</p>';
  }

  function formulaire(categorie, auTermine) {
    sousTravail = ((categorie && categorie.sousCategories) || []).map((s) => ({ id: s.id, nom: s.nom }));

    const corps = UI.ouvrirFeuille(
      categorie ? "Modifier la catégorie" : "Nouvelle catégorie",
      UI.champTexte({ id: "cat-nom", label: "Nom de la catégorie", obligatoire: true,
        valeur: categorie ? categorie.nom : "", placeholder: "Ex. Ordinateurs" }) +
      '<div class="champ"><label>Sous-catégories</label>' +
        '<div id="cat-sous"></div>' +
        '<button type="button" class="btn btn-clair" id="cat-sous-ajouter" style="margin-top:10px">' +
          UI.icone("plus", "ic-sm") + "Ajouter une sous-catégorie</button>" +
        '<div class="aide" style="margin-top:8px">Ex. Ordinateurs portables, Ordinateurs de bureau…</div>' +
      "</div>" +
      '<div class="btn-rangee">' +
        '<button type="button" class="btn" id="cat-enregistrer">' + UI.icone("check") + "Enregistrer</button>" +
        (categorie
          ? '<button type="button" class="btn btn-clair btn-danger-clair" id="cat-supprimer">' +
              UI.icone("poubelle") + "Supprimer la catégorie</button>"
          : "") +
      "</div>"
    );

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
        /* Refuser la suppression silencieuse d'une sous-catégorie encore utilisée. */
        if (categorie) {
          const restantes = new Set(sousTravail.filter((s) => s.id && s.nom.trim()).map((s) => s.id));
          const produits = await Store.produitsDeCategorie(categorie.id);
          for (const ancienne of categorie.sousCategories || []) {
            if (!restantes.has(ancienne.id)) {
              const utilises = produits.filter((p) => p.sousCategorieId === ancienne.id).length;
              if (utilises) {
                throw new Error("« " + ancienne.nom + " » contient " + utilises + " produit" +
                  (utilises > 1 ? "s" : "") + ". Déplacez-les avant de la retirer.");
              }
            }
          }
        }
        await Store.sauverCategorie({
          id: categorie ? categorie.id : null,
          nom: UI.$("#cat-nom", corps).value,
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
          texte: "« " + categorie.nom + " » sera retirée du catalogue (possible uniquement si elle ne contient aucun produit).",
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
