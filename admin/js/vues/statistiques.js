/* =========================================================
   Statistiques — ce que chaque boutique rapporte.

   Uniquement les ventes RÉELLEMENT encaissées : une commande
   à payer n'est pas une vente, et n'entre dans aucun chiffre
   de cet écran.

   Pour chaque produit vendu :

     prix BIZZOO   ce que la boutique touche
     marge         ce que l'enseigne ajoute, en %
     prix de vente ce que le client a payé
     bénéfice      prix de vente − prix BIZZOO

   Ces montants sont ceux du JOUR DE LA VENTE, figés sur la
   ligne de commande. Changer une marge aujourd'hui ne réécrit
   pas les comptes d'hier — c'est la base qui s'en assure.

   DEUX ÉCRANS, PAS UN. Ce qui précède est celui de l'enseigne.
   Une boutique, elle, a besoin de savoir ce qu'elle vend — mais
   la commission prise sur ses voisines ne la regarde pas. Elle
   a donc son propre écran, et sa propre fonction en base :

     statistiques_ventes()    l'enseigne, toutes boutiques,
                              avec marge et bénéfice
     statistiques_boutique()  la sienne seulement, et
                              uniquement ce qui lui revient

   La seconde ne porte NI prix de vente, NI marge, NI bénéfice :
   ces colonnes ne sont pas masquées ici, elles ne sortent pas
   de la base. Et elle ne prend pas de paramètre « boutique » :
   c'est toujours celle du compte connecté. Choisir l'écran
   selon le rang n'est donc qu'une politesse — la serrure est
   plus bas, dans la base, et elle a été éprouvée.
   ========================================================= */
const VueStatistiques = (() => {

  /* Les périodes qu'on regarde vraiment : « ce mois-ci » et « depuis le
     début » répondent à neuf questions sur dix. */
  const PERIODES = [
    { cle: "7j", nom: "7 jours" },
    { cle: "30j", nom: "30 jours" },
    { cle: "mois", nom: "Ce mois" },
    { cle: "tout", nom: "Tout" },
  ];

  let periode = "30j";
  let boutiqueChoisie = "";

  const jourISO = (d) => d.toISOString().slice(0, 10);

  /** Les deux bornes envoyées à la base, ou null pour « depuis toujours ». */
  function bornes() {
    const aujourdhui = new Date();
    if (periode === "tout") return { depuis: null, jusqu: null };
    if (periode === "mois") {
      return {
        depuis: jourISO(new Date(aujourdhui.getFullYear(), aujourdhui.getMonth(), 1)),
        jusqu: jourISO(aujourdhui),
      };
    }
    const jours = periode === "7j" ? 6 : 29;
    const debut = new Date(aujourdhui);
    debut.setDate(debut.getDate() - jours);
    return { depuis: jourISO(debut), jusqu: jourISO(aujourdhui) };
  }

  function total(lignes, champ) {
    return lignes.reduce((somme, l) => somme + (l[champ] || 0), 0);
  }

  function htmlLigne(l, devise, avecBoutique) {
    return (
      '<div class="st-ligne">' +
        '<div class="st-ligne-entete">' +
          "<div>" +
            (l.code ? '<span class="code-produit">' + Utils.echapper(l.code) + "</span> " : "") +
            '<span class="st-nom">' + Utils.echapper(l.nom) + "</span>" +
            (avecBoutique
              ? '<div class="st-boutique">' + UI.icone("magasin", "ic-sm") +
                Utils.echapper(l.nomBoutique || "—") + "</div>"
              : "") +
          "</div>" +
          '<div class="st-quantite">× ' + l.quantite + "</div>" +
        "</div>" +
        '<div class="st-chiffres">' +
          '<div><small>Prix BIZZOO</small><span>' +
            Utils.echapper(Utils.fmtMontant(l.prixBizzoo, devise)) + "</span></div>" +
          '<div><small>Marge</small><span>' +
            (l.tauxMarge === null ? "—" : Utils.echapper(Utils.fmtTaux(l.tauxMarge)) + " %") +
          "</span></div>" +
          '<div><small>Prix de vente</small><span>' +
            Utils.echapper(Utils.fmtMontant(l.prixVente, devise)) + "</span></div>" +
          '<div class="st-benefice"><small>Bénéfice</small><span>' +
            Utils.echapper(Utils.fmtMontant(l.benefice, devise)) + "</span></div>" +
        "</div>" +
        '<div class="st-totaux">' +
          l.quantite + " vendu" + (l.quantite > 1 ? "s" : "") + " — " +
          "encaissé " + Utils.echapper(Utils.fmtMontant(l.totalVente, devise)) +
          ", reversé " + Utils.echapper(Utils.fmtMontant(l.totalBizzoo, devise)) +
          ", gardé <strong>" + Utils.echapper(Utils.fmtMontant(l.benefice, devise)) + "</strong>" +
        "</div>" +
      "</div>"
    );
  }

  /** L'enseigne voit tout ; une boutique voit la sienne. */
  async function afficher(vue) {
    if (!Supabase.estSuper()) return afficherBoutique(vue);
    return afficherEnseigne(vue);
  }

  async function afficherEnseigne(vue) {
    const boutiques = Store.listerBoutiques();
    const devise = Store.lireReglages().devise;

    UI.entete({ titre: "Ce que rapportent les boutiques",
      sous: "Ventes encaissées", retour: true });

    vue.innerHTML =
      '<div class="carte">' +
        '<div class="st-filtres" id="st-periodes">' +
          PERIODES.map((p) =>
            '<button type="button" class="puce' + (p.cle === periode ? " active" : "") +
              '" data-periode="' + p.cle + '">' + Utils.echapper(p.nom) + "</button>").join("") +
        "</div>" +
        (boutiques.length > 1
          ? '<div class="champ" style="margin:12px 0 0">' +
              '<label for="st-boutique">Boutique</label>' +
              '<select id="st-boutique">' +
                '<option value="">Toutes les boutiques</option>' +
                boutiques.map((b) =>
                  '<option value="' + Utils.echapper(b.id) + '"' +
                    (b.id === boutiqueChoisie ? " selected" : "") + ">" +
                    Utils.echapper(b.nomBoutique) + "</option>").join("") +
              "</select>" +
            "</div>"
          : "") +
      "</div>" +
      '<div id="st-corps"><div class="chargement"><span class="chargement-rond"></span>' +
        "Lecture des ventes…</div></div>";

    for (const bouton of UI.$$("#st-periodes [data-periode]", vue)) {
      bouton.onclick = () => { periode = bouton.dataset.periode; afficher(vue); };
    }
    const choixBoutique = UI.$("#st-boutique", vue);
    if (choixBoutique) {
      choixBoutique.onchange = () => { boutiqueChoisie = choixBoutique.value; afficher(vue); };
    }

    const corps = UI.$("#st-corps", vue);
    let lignes;
    try {
      lignes = await Store.statistiquesVentes({ ...bornes(), boutique: boutiqueChoisie });
    } catch (err) {
      corps.innerHTML =
        '<div class="carte"><div class="carte-titre">Chiffres indisponibles</div>' +
        '<p class="aide" style="margin:0">' + Utils.echapper(err.message) +
        "<br>Si la marge de BIZZOO vient d'être mise en place, exécutez le dernier " +
        "fichier SQL dans Supabase.</p></div>";
      return;
    }

    if (!lignes.length) {
      corps.innerHTML = UI.vide("promo", "Aucune vente sur cette période",
        "Seules les commandes payées entrent ici. Dès qu'un client règle son panier, " +
        "le détail de ce qu'il rapporte s'affiche.");
      return;
    }

    /* Le total d'abord : c'est la question qu'on se pose en ouvrant
       l'écran. Le détail vient ensuite. */
    corps.innerHTML =
      '<div class="carte carte-publier st-resume">' +
        '<div class="st-resume-grand">' +
          "<small>Bénéfice de BIZZOO</small>" +
          "<strong>" + Utils.echapper(Utils.fmtMontant(total(lignes, "benefice"), devise)) +
          "</strong>" +
        "</div>" +
        '<div class="st-resume-detail">' +
          "<div><small>Encaissé</small><span>" +
            Utils.echapper(Utils.fmtMontant(total(lignes, "totalVente"), devise)) + "</span></div>" +
          "<div><small>Reversé aux boutiques</small><span>" +
            Utils.echapper(Utils.fmtMontant(total(lignes, "totalBizzoo"), devise)) + "</span></div>" +
          "<div><small>Articles vendus</small><span>" +
            total(lignes, "quantite") + "</span></div>" +
        "</div>" +
      "</div>" +
      (boutiqueChoisie ? "" : htmlParBoutique(lignes, devise)) +
      '<div class="titre-section">Produit par produit</div>' +
      lignes.map((l) => htmlLigne(l, devise, !boutiqueChoisie)).join("");
  }

  /* ---------- L'écran de la boutique ----------
     Ce qu'elle a vendu, et ce qui lui revient. Rien sur ce que
     l'enseigne a ajouté par-dessus : ce n'est pas son affaire, et la
     base ne le lui envoie pas. */

  function htmlLigneBoutique(l, devise) {
    return (
      '<div class="st-ligne">' +
        '<div class="st-ligne-entete">' +
          "<div>" +
            (l.code ? '<span class="code-produit">' + Utils.echapper(l.code) + "</span> " : "") +
            '<span class="st-nom">' + Utils.echapper(l.nom) + "</span>" +
          "</div>" +
          '<div class="st-quantite">× ' + l.quantite + "</div>" +
        "</div>" +
        '<div class="st-chiffres">' +
          '<div><small>Prix BIZZOO</small><span>' +
            Utils.echapper(Utils.fmtMontant(l.prixBizzoo, devise)) + "</span></div>" +
          '<div class="st-benefice"><small>Vous revient</small><span>' +
            Utils.echapper(Utils.fmtMontant(l.totalBizzoo, devise)) + "</span></div>" +
        "</div>" +
        '<div class="st-totaux">' +
          l.quantite + " vendu" + (l.quantite > 1 ? "s" : "") +
          " sur " + l.nbVentes + " commande" + (l.nbVentes > 1 ? "s" : "") +
        "</div>" +
      "</div>"
    );
  }

  async function afficherBoutique(vue) {
    const devise = Store.lireReglages().devise;
    const mienne = Store.boutiqueCourante();

    UI.entete({ titre: "Ce que vend votre boutique",
      sous: mienne ? mienne.nomBoutique : "Ventes encaissées", retour: true });

    vue.innerHTML =
      '<div class="carte">' +
        '<div class="st-filtres" id="st-periodes">' +
          PERIODES.map((p) =>
            '<button type="button" class="puce' + (p.cle === periode ? " active" : "") +
              '" data-periode="' + p.cle + '">' + Utils.echapper(p.nom) + "</button>").join("") +
        "</div>" +
      "</div>" +
      '<div id="st-corps"><div class="chargement"><span class="chargement-rond"></span>' +
        "Lecture des ventes…</div></div>";

    for (const bouton of UI.$$("#st-periodes [data-periode]", vue)) {
      bouton.onclick = () => { periode = bouton.dataset.periode; afficherBoutique(vue); };
    }

    const corps = UI.$("#st-corps", vue);
    let lignes;
    try {
      lignes = await Store.statistiquesBoutique(bornes());
    } catch (err) {
      corps.innerHTML =
        '<div class="carte"><div class="carte-titre">Chiffres indisponibles</div>' +
        '<p class="aide" style="margin:0">' + Utils.echapper(err.message) +
        "<br>Si les statistiques par boutique viennent d'être mises en place, " +
        "exécutez le dernier fichier SQL dans Supabase.</p></div>";
      return;
    }

    if (!lignes.length) {
      corps.innerHTML = UI.vide("promo", "Aucune vente sur cette période",
        "Seules les commandes payées entrent ici. Dès qu'un client règle un panier " +
        "contenant un de vos articles, il s'affiche.");
      return;
    }

    corps.innerHTML =
      '<div class="carte carte-publier st-resume">' +
        '<div class="st-resume-grand">' +
          "<small>Ce qui vous revient</small>" +
          "<strong>" + Utils.echapper(Utils.fmtMontant(total(lignes, "totalBizzoo"), devise)) +
          "</strong>" +
        "</div>" +
        '<div class="st-resume-detail deux">' +
          "<div><small>Articles vendus</small><span>" +
            total(lignes, "quantite") + "</span></div>" +
          "<div><small>Références</small><span>" + lignes.length + "</span></div>" +
        "</div>" +
      "</div>" +
      '<p class="aide" style="margin:12px 4px">Au prix BIZZOO que vous avez annoncé, ' +
        "figé le jour de la vente. Les commandes non payées et les lignes que vous avez " +
        "annulées n'y sont pas.</p>" +
      '<div class="titre-section">Produit par produit</div>' +
      lignes.map((l) => htmlLigneBoutique(l, devise)).join("");
  }

  /** Ce que chaque boutique rapporte, quand on les regarde toutes. */
  function htmlParBoutique(lignes, devise) {
    const table = new Map();
    for (const l of lignes) {
      const cle = l.boutiqueId || "";
      if (!table.has(cle)) {
        table.set(cle, { nom: l.nomBoutique || "—", benefice: 0, totalVente: 0, quantite: 0 });
      }
      const g = table.get(cle);
      g.benefice += l.benefice;
      g.totalVente += l.totalVente;
      g.quantite += l.quantite;
    }
    const groupes = [...table.values()].sort((a, b) => b.benefice - a.benefice);
    if (groupes.length < 2) return "";
    return (
      '<div class="titre-section">Par boutique</div>' +
      groupes.map((g) =>
        '<div class="carte st-boutique-ligne">' +
          "<div><strong>" + Utils.echapper(g.nom) + "</strong>" +
            '<div class="aide">' + g.quantite + " article" + (g.quantite > 1 ? "s" : "") +
              " — encaissé " + Utils.echapper(Utils.fmtMontant(g.totalVente, devise)) + "</div>" +
          "</div>" +
          '<div class="st-boutique-benefice">' +
            Utils.echapper(Utils.fmtMontant(g.benefice, devise)) + "</div>" +
        "</div>").join("")
    );
  }

  return { afficher };
})();
