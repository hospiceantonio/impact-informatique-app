/* =========================================================
   Statistiques — commandes, livraisons, SAV et avis de BIZZOO,
   sur une période.

   C'est la base (rh_statistiques) qui décide de ce que chacun
   voit : le CEO tout, marge comprise ; l'administration tout
   sauf la marge ; un responsable les seules rubriques ouvertes
   à son profil, sans aucun montant. Un chiffre absent de la
   réponse n'est donc jamais affiché : l'écran ne cache rien,
   il n'a simplement rien reçu.
   ========================================================= */
const VueStatistiques = (() => {
  const { h } = UI;

  const ETATS_LIGNE = { nouvelle: "Nouvelle", vue: "Vue par la boutique", preparee: "Préparée",
    en_livraison: "En livraison", remise: "Livrée", annulee: "Annulée" };
  const ETATS_SAV = { ouverte: "Ouverte", repondue: "Répondue", resolue: "Résolue",
    escaladee: "Escaladée vers BIZZOO", tranchee: "Tranchée par BIZZOO" };
  const SUJETS_SAV = { non_recu: "Non reçu", abime: "Abîmé", pas_conforme: "Pas conforme",
    incomplet: "Incomplet", autre: "Autre" };

  const iso = (d) => d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  function periodes() {
    const j = new Date();
    const moinsJours = (n) => { const d = new Date(j); d.setDate(d.getDate() - n); return iso(d); };
    const debutMois = new Date(j.getFullYear(), j.getMonth(), 1);
    const debutMoisPrec = new Date(j.getFullYear(), j.getMonth() - 1, 1);
    const finMoisPrec = new Date(j.getFullYear(), j.getMonth(), 0);
    return [
      ["7j", "7 jours", moinsJours(6), iso(j)],
      ["30j", "30 jours", moinsJours(29), iso(j)],
      ["mois", "Ce mois", iso(debutMois), iso(j)],
      ["moisprec", "Mois dernier", iso(debutMoisPrec), iso(finMoisPrec)],
      ["annee", "Cette année", j.getFullYear() + "-01-01", iso(j)],
    ];
  }

  const nombre = (n) => (n === null || n === undefined ? "—" : UI.entier(n));
  const tuile = (valeur, libelle, petit) => h("div", { class: "tuile" },
    h("b", { style: petit ? { fontSize: "17px" } : null }, valeur), h("span", {}, libelle));
  const montant = (v) => (v === null || v === undefined ? null : UI.fcfa(v));

  async function afficher(zone, morceaux, params) {
    const liste = periodes();
    const choix = liste.find((p) => p[0] === params.p) || (params.du ? null : liste[1]);
    const depuis = choix ? choix[2] : params.du;
    const jusqu = choix ? choix[3] : (params.au || iso(new Date()));

    const du = h("input", { type: "date", value: depuis });
    const au = h("input", { type: "date", value: jusqu });
    const formPeriode = h("form", { class: "ligne" },
      h("label", { class: "champ" }, h("span", {}, "Du"), du),
      h("label", { class: "champ" }, h("span", {}, "Au"), au),
      h("button", { class: "btn btn-second", type: "submit", style: { alignSelf: "flex-end" } }, "Afficher"));
    formPeriode.addEventListener("submit", (ev) => {
      ev.preventDefault();
      location.hash = "#/statistiques?du=" + du.value + "&au=" + au.value;
    });

    const corps = h("div", { class: "pile" }, UI.chargement());
    UI.vider(zone,
      h("div", { class: "filtres" }, liste.map(([cle, libelle]) =>
        h("button", { class: choix && choix[0] === cle ? "actif" : "", onclick: () => { location.hash = "#/statistiques?p=" + cle; } }, libelle))),
      formPeriode, corps);

    const s = await Supabase.rpc("rh_statistiques", { depuis, jusqu });
    if (!corps.isConnected) return;
    const blocs = [h("p", { class: "doux petit" }, "Du " + UI.dateLongue(s.periode.depuis) + " au " + UI.dateLongue(s.periode.jusqu) +
      (s.droits.argent ? "" : " · sans les montants, réservés à l'administration"))];
    if (s.commandes) blocs.push(...commandes(s.commandes, s.droits));
    if (s.livraisons) blocs.push(...livraisons(s.livraisons, s.droits));
    if (s.sav) blocs.push(...sav(s.sav));
    UI.vider(corps, blocs);
  }

  /* ---------- Les commandes ---------- */

  function commandes(c, droits) {
    const tuiles = [
      tuile(nombre(c.payees), "commandes payées"),
      tuile(nombre(c.articles), "articles vendus"),
      tuile(nombre(c.creees), "commandes passées"),
      tuile(nombre(c.a_payer), "en attente de paiement"),
      tuile(nombre(c.echouees), "échouées ou annulées"),
      tuile(nombre(c.revendeurs), "par des revendeurs"),
    ];
    if (droits.argent) {
      tuiles.unshift(tuile(montant(c.montant), "encaissé sur les commandes payées", true));
      tuiles.splice(1, 0, tuile(montant(c.panier_moyen), "panier moyen", true));
      tuiles.push(tuile(montant(c.frais_livraison), "frais de livraison", true), tuile(montant(c.remises), "remises (codes promo)", true));
    }
    if (droits.marge) {
      tuiles.splice(1, 0, h("div", { class: "tuile alerte" }, h("b", { style: { fontSize: "17px" } }, montant(c.benefice)),
        h("span", {}, "marge de BIZZOO (CEO seul)")));
      tuiles.push(tuile(montant(c.reverse_boutiques), "reversé aux boutiques", true));
    }
    const sortie = [h("h2", { style: { fontSize: "18px" } }, "Commandes"), h("div", { class: "tuiles" }, tuiles)];
    if (c.par_jour.length) sortie.push(courbe(c.par_jour, droits.argent));
    if (c.boutiques.length) {
      sortie.push(tableau("Boutiques qui vendent le plus",
        ["Boutique", "Commandes", "Articles", droits.argent ? "Ventes" : null, droits.marge ? "Marge" : null],
        c.boutiques.map((b) => [b.boutique || "—", nombre(b.commandes), nombre(b.articles),
          droits.argent ? UI.entier(b.ventes) : null, droits.marge ? UI.entier(b.benefice) : null])));
    }
    if (c.produits.length) {
      sortie.push(tableau("Produits les plus vendus",
        ["Produit", "Articles", droits.argent ? "Ventes" : null],
        c.produits.map((p) => [(p.code ? p.code + " · " : "") + p.produit, nombre(p.articles), droits.argent ? UI.entier(p.ventes) : null])));
    }
    return sortie;
  }

  /** Des barres, une par jour : le nombre de commandes payées. */
  function courbe(jours, argent) {
    const max = Math.max(1, ...jours.map((j) => j.payees));
    return h("div", { class: "carte" },
      h("h3", { style: { marginBottom: "10px" } }, "Commandes payées par jour"),
      h("div", { style: { display: "flex", alignItems: "flex-end", gap: "3px", height: "140px", overflowX: "auto" } },
        jours.map((j) => h("div", {
          title: UI.date(j.jour) + " : " + j.payees + " commande(s)" + (argent && j.montant !== null ? " · " + UI.fcfa(j.montant) : ""),
          style: { flex: "1 0 10px", minWidth: "10px", maxWidth: "36px", height: Math.max(4, Math.round(j.payees / max * 130)) + "px",
                   background: "var(--bleu)", borderRadius: "4px 4px 0 0" } }))),
      h("div", { class: "ligne tres-petit doux", style: { justifyContent: "space-between", marginTop: "4px" } },
        h("span", {}, UI.date(jours[0].jour)), h("span", {}, UI.date(jours[jours.length - 1].jour))));
  }

  function tableau(titre, entetes, lignes) {
    const garder = entetes.map((e) => e !== null);
    return h("div", { class: "carte defile" },
      h("h3", { style: { marginBottom: "8px" } }, titre),
      h("table", { class: "tableau" },
        h("thead", {}, h("tr", {}, entetes.filter((e, i) => garder[i]).map((e, i) =>
          h("th", { class: i === 0 ? "" : "nombre" }, e)))),
        h("tbody", {}, lignes.map((l) => h("tr", {}, l.filter((_, i) => garder[i]).map((v, i) =>
          h("td", { class: i === 0 ? "" : "nombre" }, v)))))));
  }

  /* ---------- Les livraisons ---------- */

  function livraisons(l, droits) {
    const delai = l.delai_moyen_heures === null ? "—"
      : l.delai_moyen_heures < 48 ? String(l.delai_moyen_heures).replace(".", ",") + " h"
      : (Math.round(l.delai_moyen_heures / 24 * 10) / 10).toString().replace(".", ",") + " j";
    const sortie = [
      h("h2", { style: { fontSize: "18px" } }, "Livraisons"),
      h("div", { class: "tuiles" },
        tuile(nombre(l.livrees), "articles livrés"),
        tuile(nombre(l.en_cours), "à livrer"),
        tuile(nombre(l.annulees), "annulés"),
        tuile(delai, "délai moyen paiement → réception")),
    ];
    const etats = Object.entries(l.par_etat || {});
    if (etats.length) {
      sortie.push(tableau("Où en sont les articles payés", ["État", "Articles"],
        etats.sort((a, b) => b[1] - a[1]).map(([e, n]) => [ETATS_LIGNE[e] || e, nombre(n)])));
    }
    if (l.livreurs.length) {
      sortie.push(tableau("Livreurs", ["Livreur", "Commandes", "Articles livrés", droits.argent ? "Gains" : null],
        l.livreurs.map((x) => [x.livreur, nombre(x.commandes), nombre(x.livrees), droits.argent ? UI.entier(x.gains) : null])));
    }
    return sortie;
  }

  /* ---------- SAV et avis ---------- */

  function sav(s) {
    const sortie = [
      h("h2", { style: { fontSize: "18px" } }, "Service après-vente et avis"),
      h("div", { class: "tuiles" },
        tuile(nombre(s.reclamations), "réclamations"),
        tuile(nombre(s.avis), "avis déposés"),
        tuile(s.note_moyenne === null ? "—" : String(s.note_moyenne).replace(".", ",") + " / 5", "note moyenne"),
        tuile(nombre(s.avis_masques), "avis masqués")),
    ];
    const etats = Object.entries(s.par_etat || {});
    if (etats.length) sortie.push(tableau("Réclamations par état", ["État", "Nombre"], etats.map(([e, n]) => [ETATS_SAV[e] || e, nombre(n)])));
    const sujets = Object.entries(s.par_sujet || {});
    if (sujets.length) sortie.push(tableau("Réclamations par motif", ["Motif", "Nombre"],
      sujets.sort((a, b) => b[1] - a[1]).map(([e, n]) => [SUJETS_SAV[e] || e, nombre(n)])));
    const notes = s.notes || {};
    if (Object.keys(notes).length) {
      sortie.push(tableau("Répartition des notes", ["Note", "Avis"],
        [5, 4, 3, 2, 1].map((n) => ["★".repeat(n), nombre(notes[n] || 0)])));
    }
    return sortie;
  }

  return { titre: "Statistiques", afficher };
})();
