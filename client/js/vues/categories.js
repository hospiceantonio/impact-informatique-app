/* =========================================================
   Catégories — le menu de BIZZOO.

   DEUX ÉTAGES, et c'est tout l'objet de cet écran.

     1. LES CATÉGORIES DE BIZZOO. La même liste pour tout le
        monde, posée par l'enseigne : pastille ronde, nom,
        chevron. Un champ de recherche en tête, parce qu'une
        liste de quinze lignes se parcourt mal au doigt.

     2. LES RAYONS. Ouvrir une catégorie montre ce que les
        boutiques de ce secteur tiennent VRAIMENT — et rien
        d'autre. Un rayon vide n'y figure pas : sur une place
        de marché, c'est une porte qui ne mène nulle part.

   Dans une boutique, l'écran parle d'elle seule : ses rayons,
   c'est-à-dire ceux de son secteur où elle a quelque chose.
   ========================================================= */
const VueCategories = (() => {

  /* ---------- Premier étage : la liste de BIZZOO ---------- */

  async function liste(vue) {
    /* L'onglet existe dans les deux cas. Entré dans une boutique, il
       parle d'elle ; sur l'accueil de l'enseigne, il parle de BIZZOO. */
    const choisie = Catalogue.boutiqueChoisie();
    if (Catalogue.multiBoutiques() && choisie) { rayonsDeLaBoutique(vue); return; }

    const rayons = Catalogue.categoriesBizzoo();

    /* Le titre seul, et la loupe qui mène à la recherche des PRODUITS :
       le champ juste dessous, lui, ne cherche que parmi les catégories. */
    UI.entete({ titre: "Catégories", actions: UI.boutonRecherche() });

    if (!rayons.length) {
      vue.innerHTML = UI.vide("categories", "Aucune catégorie pour l'instant",
        "Les rayons de BIZZOO s'afficheront ici.");
      return;
    }

    vue.innerHTML =
      '<div class="recherche-boite">' + UI.icone("recherche", "ic-sm") +
        '<input id="cat-chercher" type="search" autocomplete="off" ' +
          'placeholder="Rechercher une catégorie…">' +
      "</div>" +
      '<div id="cat-liste">' + rayons.map((r) => UI.ligneRayon(r)).join("") + "</div>";

    /* LA RECHERCHE REGARDE AUSSI LES RAYONS. On cherche « pneus » sans
       savoir que cela vit sous « Auto & Moto » : ne comparer que le nom
       des catégories ne rendrait rien, et l'écran paraîtrait vide. */
    const zone = UI.$("#cat-liste", vue);
    const champ = UI.$("#cat-chercher", vue);
    champ.oninput = () => {
      const t = Utils.sansAccent(champ.value).trim();
      const gardes = !t ? rayons : rayons.filter((r) => {
        const noms = [r.categorie.nom]
          .concat(Catalogue.sousCategories(r.categorie.id).map((s) => s.nom));
        return Utils.sansAccent(noms.join(" ")).includes(t);
      });
      zone.innerHTML = gardes.length
        ? gardes.map((r) => UI.ligneRayon(r)).join("")
        : UI.vide("recherche", "Aucune catégorie trouvée",
            "Essayez un autre mot — « chaussures », « pneus », « riz »…");
    };
  }

  /* Dans une boutique : ses rayons à elle. « Les catégories d'une
     boutique » n'existent plus ; ce sont les rayons du secteur de
     BIZZOO où elle se range, et seulement ceux qu'elle tient. C'est
     l'onglet « Catégories » de la barre de la boutique qui y mène. */
  function rayonsDeLaBoutique(vue) {
    const rayons = Catalogue.rayonsDeLaBoutique();
    const b = Catalogue.boutiqueChoisie();
    /* « d'Impact Informatique », « de Bêta » : on élide devant une
       voyelle. */
    const de = (nom) => (/^[aeiouyàâäéèêëîïôöùûü]/i.test(nom) ? "d'" : "de ") + nom;
    UI.entete({ titre: "Catégories",
      sous: b ? "Les rayons " + de(b.nom) : "Tout le catalogue, classé par rayon",
      actions: UI.boutonRecherche() });

    if (!rayons.length) {
      vue.innerHTML = UI.bandeauBoutique() +
        UI.vide("categories", "Aucun rayon pour l'instant",
          "Les articles de cette boutique s'afficheront ici, classés par rayon.");
      return;
    }
    vue.innerHTML = UI.bandeauBoutique() +
      rayons.map((r) => UI.ligneSousRayon(r, r.categorieId)).join("");
  }

  /* ---------- Second étage : une catégorie ---------- */

  async function rayon(vue, id, params) {
    const c = Catalogue.categorie(id);
    /* LA LOUPE À CHAQUE ÉTAGE : la liste des rayons comme la grille des
       produits. On y arrive le plus souvent par un rond de l'accueil, où
       la recherche était la pilule du haut — elle ne doit pas disparaître
       en entrant. */
    const loupe = UI.boutonRecherche();
    if (!c) {
      vue.innerHTML = UI.vide("alerte", "Catégorie introuvable",
        "Elle a peut-être été retirée du catalogue.",
        '<a class="btn btn-clair" href="#/categories">Voir les catégories</a>');
      UI.entete({ titre: "Catégorie", retour: true, actions: loupe });
      return;
    }

    const rayons = Catalogue.rayonsDeLaCategorie(c.id);
    const scActive = params && params.sc && rayons.some((r) => r.sousCategorie.id === params.sc)
      ? params.sc : null;

    /* SANS RAYON CHOISI, ON MONTRE LES RAYONS — c'est ce qu'on attend
       en ouvrant une catégorie sur une place de marché : savoir ce
       qu'elle contient avant de dérouler cent articles. Le lien
       « Tout voir » reste, pour qui préfère la grille. */
    /* « ?sc=tout » n'est pas un rayon : c'est la demande explicite de
       voir la grille entière. Sans ce cas à part, le lien « Tout voir »
       ramènerait à la liste des rayons — en rond. */
    const toutVoir = !!(params && params.sc === "tout");
    if (!scActive && !toutVoir && rayons.length > 1) {
      const total = Catalogue.produitsDeCategorie(c.id).length;
      UI.entete({ titre: c.nom, retour: true, actions: loupe,
        sous: rayons.length + " rayon" + (rayons.length > 1 ? "s" : "") });
      vue.innerHTML =
        rayons.map((r) => UI.ligneSousRayon(r, c.id)).join("") +
        '<a class="btn btn-clair" style="margin-top:12px" href="#/categorie/' +
          Utils.echapper(c.id) + '?sc=tout">' + UI.icone("boite") +
          "Tout voir (" + total + " article" + (total > 1 ? "s" : "") + ")</a>";
      return;
    }

    const produits = Catalogue.produitsDeCategorie(c.id, scActive);
    const nomRayon = scActive
      ? (rayons.find((r) => r.sousCategorie.id === scActive) || {}).sousCategorie
      : null;

    UI.entete({ titre: nomRayon ? nomRayon.nom : c.nom, retour: true, actions: loupe,
      sous: produits.length + " article" + (produits.length > 1 ? "s" : "") +
        (nomRayon ? " · " + c.nom : "") });

    let html = "";

    if (rayons.length) {
      /* « collees » : la rangée se fige sous la barre du haut quand on
         fait défiler, pour changer de rayon sans avoir à remonter. */
      html += '<div class="puces puces-collees">' +
        '<a class="puce' + (scActive ? "" : " active") + '" href="#/categorie/' +
          Utils.echapper(c.id) + '?sc=tout">Tout</a>' +
        rayons.map((r) =>
          '<a class="puce' + (scActive === r.sousCategorie.id ? " active" : "") +
            '" href="#/categorie/' + Utils.echapper(c.id) + "?sc=" +
            Utils.echapper(r.sousCategorie.id) + '">' +
            Utils.echapper(r.sousCategorie.nom) + "</a>").join("") +
      "</div>";
    }

    html += produits.length
      ? UI.grilleProduits(produits)
      : UI.vide("boite", "Rien dans ce rayon pour l'instant",
          "Repassez bientôt : le catalogue est mis à jour régulièrement.");

    vue.innerHTML = html;
  }

  /* ---------- Promotions ---------- */

  async function promos(vue) {
    const produits = Catalogue.promotions();
    UI.entete({ titre: "Promotions", retour: true, actions: UI.boutonRecherche(),
      sous: produits.length ? "Profitez-en, stocks limités" : "" });

    vue.innerHTML = produits.length
      ? UI.grilleProduits(produits)
      : UI.vide("promo", "Pas de promotion en cours",
          "Les offres du moment s'afficheront ici.");
  }

  return { liste, rayon, promos };
})();
