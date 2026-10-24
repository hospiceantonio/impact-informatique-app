/* =========================================================
   Suivi des commandes — le tableau de bord de BIZZOO.

   #/suivi                      : une commande par ligne, filtres,
                                  export Excel ;
   #/suivi/alertes              : ce qui demande une action ;
   #/suivi/bilan                : le bilan par jour, semaine, mois ;
   #/suivi/reglages             : les délais des alertes, les zones ;
   #/suivi/commande/<id>        : la fiche, la chronologie, les
                                  incidents, la clôture.

   Le statut dit OÙ EN EST la commande ; les alertes disent CE QUI
   NE VA PAS, à côté, sans jamais réécrire l'historique. C'est la
   base (rh_suivi…) qui calcule les deux, et qui ôte les montants
   à qui n'y a pas droit.
   ========================================================= */
const VueSuivi = (() => {
  const { h } = UI;

  const ALERTES = {
    non_vue: ["Pas vue par le marchand", "rouge"],
    retard_preparation: ["Préparation en retard", "orange"],
    retard_livraison: ["Livraison en retard", "orange"],
    sans_confirmation: ["Livrée, sans confirmation du client", "orange"],
    contestee: ["Livraison contestée", "rouge"],
    echec: ["Échec ou retour", "rouge"],
    incident: ["Incident ouvert", "rouge"],
    refus_course: ["Course refusée par un livreur", ""],
    encaissement_conteste: ["Encaissement contesté", "rouge"],
  };
  const COULEUR_STATUT = { 0: "", 1: "orange", 2: "bleu", 3: "bleu", 4: "bleu", 5: "bleu", 6: "orange",
    8: "vert", 9: "rouge", 10: "rouge", 11: "", 12: "orange", 13: "", 14: "vert", 15: "" };
  const TERRAIN = [["", "— (rien de noté)"], ["recupere", "Colis récupéré par le livreur"], ["echouee", "Livraison échouée"],
    ["retour_en_cours", "Retour en cours"], ["retournee", "Retourné au marchand"]];
  const TYPES_INCIDENT = [["retard", "Retard"], ["client_absent", "Client absent ou injoignable"], ["adresse", "Adresse introuvable"],
    ["colis_abime", "Colis abîmé"], ["colis_perdu", "Colis perdu"], ["erreur_article", "Erreur d'article"],
    ["paiement", "Problème de paiement"], ["autre", "Autre"]];
  const QUOI = { etat: "Étape", livreur: "Livreur assigné", course_acceptee: "Course acceptée par le livreur",
    confirmee: "« Je l'ai reçu » du client", commande: "Commande", suivi: "Suivi (administration)" };
  const ETAPES = { nouvelle: "Nouvelle", vue: "Vue par le marchand", preparee: "Préparée", en_livraison: "En livraison",
    remise: "Déclarée livrée", annulee: "Annulée", payee: "Payée", a_payer: "À payer", echouee: "Paiement échoué",
    recupere: "Colis récupéré", retour_en_cours: "Retour en cours", retournee: "Retourné au marchand",
    cloturee: "Clôturée", rouverte: "Rouverte" };

  const etiquetteStatut = (c) => UI.etiquette(c.statut || "—", COULEUR_STATUT[c.rang] || "");
  const etiquettesAlertes = (liste) => (liste || []).map((a) => UI.etiquette(...(ALERTES[a] || [a, ""])));
  const montant = (v) => (v === null || v === undefined ? "—" : UI.fcfa(v));
  const delai = (hres) => {
    if (hres === null || hres === undefined) return "—";
    const n = Number(hres);
    if (n < 48) return String(n).replace(".", ",") + " h";
    const j = Math.floor(n / 24);
    return j + " j " + Math.round(n - j * 24) + " h";
  };
  /** « 21/10/2026 - 13 h 20 », comme le classeur de BIZZOO. */
  const dateSuivi = (v) => {
    if (!v) return "—";
    const d = new Date(v);
    return d.toLocaleDateString("fr-FR", { day: "2-digit", month: "2-digit", year: "numeric" }) + " - " +
      String(d.getHours()).padStart(2, "0") + " h " + String(d.getMinutes()).padStart(2, "0");
  };

  /* ---------- La période ---------- */

  const iso = (d) => d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  function periodes() {
    const j = new Date();
    const moins = (n) => { const d = new Date(j); d.setDate(d.getDate() - n); return iso(d); };
    return [
      ["jour", "Aujourd'hui", iso(j), iso(j)],
      ["hier", "Hier", moins(1), moins(1)],
      ["7j", "7 jours", moins(6), iso(j)],
      ["30j", "30 jours", moins(29), iso(j)],
      ["mois", "Ce mois", iso(new Date(j.getFullYear(), j.getMonth(), 1)), iso(j)],
    ];
  }
  function periodeDe(params, defaut) {
    const liste = periodes();
    const choix = liste.find((p) => p[0] === params.p) || (params.du ? null : liste.find((p) => p[0] === defaut));
    return { liste, choix,
      depuis: choix ? choix[2] : params.du, jusqu: choix ? choix[3] : (params.au || iso(new Date())) };
  }
  function barrePeriode(route, periode, extra) {
    const du = h("input", { type: "date", value: periode.depuis });
    const au = h("input", { type: "date", value: periode.jusqu });
    const form = h("form", { class: "ligne" },
      h("label", { class: "champ" }, h("span", {}, "Du"), du),
      h("label", { class: "champ" }, h("span", {}, "Au"), au),
      h("button", { class: "btn btn-second", type: "submit", style: { alignSelf: "flex-end" } }, "Afficher"));
    form.addEventListener("submit", (ev) => {
      ev.preventDefault();
      if (au.value < du.value) return UI.echec("La fin de la période précède son début.");
      location.hash = route + "?du=" + du.value + "&au=" + au.value + (extra || "");
    });
    return h("div", { class: "carte pile" },
      h("div", { class: "filtres" }, periode.liste.map(([cle, libelle]) =>
        h("button", { class: periode.choix && periode.choix[0] === cle ? "actif" : "",
                      onclick: () => { location.hash = route + "?p=" + cle + (extra || ""); } }, libelle))),
      form);
  }

  function onglets(actif) {
    const items = [["", "Commandes"], ["alertes", "Alertes"], ["bilan", "Bilan"]];
    if (App.estAdmin()) items.push(["reglages", "Réglages"]);
    return h("div", { class: "filtres" }, items.map(([v, l]) =>
      h("button", { class: v === actif ? "actif" : "", onclick: () => { location.hash = "#/suivi" + (v ? "/" + v : ""); } }, l)));
  }

  async function afficher(zone, morceaux, params) {
    UI.vider(zone, UI.chargement());
    switch (morceaux[0]) {
      case "commande": return fiche(zone, morceaux[1]);
      case "alertes": return alertes(zone);
      case "bilan": return bilan(zone, params);
      case "reglages": return reglages(zone);
      default: return tableau(zone, params);
    }
  }

  /* ---------- Le tableau ---------- */

  async function tableau(zone, params) {
    const periode = periodeDe(params, "7j");
    const r = await Supabase.rpc("rh_suivi", { depuis: periode.depuis, jusqu: periode.jusqu });
    if (!zone.isConnected) return;
    const toutes = r.commandes;
    const statuts = [...new Set(toutes.map((c) => c.statut))].sort();
    const zones = [...new Set(toutes.map((c) => c.client.zone || "Non reconnue"))].sort((a, b) => a.localeCompare(b, "fr"));

    const recherche = h("input", { type: "search", placeholder: "N°, client, téléphone, marchand, livreur…" });
    const choixStatut = h("select", {}, h("option", { value: "" }, "Tous les statuts"), statuts.map((s) => h("option", { value: s }, s)));
    const choixZone = h("select", {}, h("option", { value: "" }, "Toutes les zones"), zones.map((s) => h("option", { value: s }, s)));
    const avecAlertes = h("input", { type: "checkbox" });
    const corps = h("div", {});
    const compte = h("p", { class: "doux petit" });

    const filtrees = () => {
      const q = recherche.value.trim().toLowerCase();
      return toutes.filter((c) =>
        (!choixStatut.value || c.statut === choixStatut.value) &&
        (!choixZone.value || (c.client.zone || "Non reconnue") === choixZone.value) &&
        (!avecAlertes.checked || c.alertes.length) &&
        (!q || [c.numero, c.client.nom, c.client.tel, c.client.adresse, c.marchands, c.livreurs, c.articles]
          .join(" ").toLowerCase().includes(q)));
    };
    /* Les colonnes du classeur de BIZZOO ; un clic sur l'en-tête trie. */
    const zoneDe = (c) => c.client.zone || c.client.adresse || "";
    const colonnes = [
      { titre: "N° commande", cle: (c) => c.numero || c.id, cellule: (c) => h("span", { class: "gras" }, c.numero || c.id) },
      { titre: "Date / heure", cle: (c) => c.cree_le || "", cellule: (c) => dateSuivi(c.cree_le), classe: "sans-retour" },
      { titre: "Client / téléphone / zone", cle: (c) => c.client.nom || "", classe: "moyen",
        cellule: (c) => [h("div", {}, c.client.nom || "—"), h("div", { class: "doux tres-petit" }, [c.client.tel, zoneDe(c)].filter(Boolean).join(" · "))] },
      { titre: "Articles commandés", cle: (c) => c.articles || "", cellule: (c) => c.articles || "—", classe: "large" },
      { titre: "Marchand", cle: (c) => c.marchands || "", cellule: (c) => c.marchands || "—", classe: "moyen" },
      ...(r.montants ? [
        { titre: "Frais de livraison", cle: (c) => Number(c.frais), cellule: (c) => montant(c.frais), classe: "nombre" },
        { titre: "Total commande", cle: (c) => Number(c.total), cellule: (c) => h("span", { class: "gras" }, montant(c.total)), classe: "nombre" },
        { titre: "Reste à encaisser", cle: (c) => Number(c.reste),
          cellule: (c) => Number(c.reste) > 0 ? h("span", { style: { color: "var(--orange-fonce)" } }, montant(c.reste)) : montant(c.reste), classe: "nombre" },
      ] : []),
      { titre: "Livreur", cle: (c) => c.livreurs || "", cellule: (c) => c.livreurs || "—", classe: "moyen" },
      { titre: "Statut", cle: (c) => c.rang, cellule: (c) => etiquetteStatut(c) },
      { titre: "Confirmation client", cle: (c) => c.confirmation || "", cellule: (c) => c.confirmation || "—" },
      { titre: "Délai de livraison", cle: (c) => (c.delai_h === null || c.delai_h === undefined ? -1 : Number(c.delai_h)),
        cellule: (c) => delai(c.delai_h), classe: "nombre" },
      { titre: "Observations / alertes", cle: (c) => c.alertes.length,
        cellule: (c) => [c.observations ? h("div", { class: "petit" }, c.observations) : null,
          c.alertes.length ? h("div", { class: "actions" }, etiquettesAlertes(c.alertes)) : null,
          c.incidents_ouverts ? h("div", { class: "tres-petit", style: { color: "var(--rouge-fonce)" } }, c.incidents_ouverts + " incident(s) ouvert(s)") : null,
          !c.observations && !c.alertes.length && !c.incidents_ouverts ? "—" : null], classe: "large" },
    ];
    let tri = { col: 1, sens: -1 };
    const comparer = (a, b) => {
      const ka = colonnes[tri.col].cle(a), kb = colonnes[tri.col].cle(b);
      const d = typeof ka === "number" && typeof kb === "number" ? ka - kb : String(ka).localeCompare(String(kb), "fr", { numeric: true });
      return d * tri.sens;
    };
    const dessiner = () => {
      const liste = filtrees().sort(comparer);
      compte.textContent = liste.length + " commande(s) sur " + toutes.length;
      if (!liste.length) return UI.vider(corps, UI.vide("Aucune commande ne correspond."));
      const ouvrir = (c) => { location.hash = "#/suivi/commande/" + encodeURIComponent(c.id); };
      UI.vider(corps, h("div", { class: "carte defile tableau-suivi" },
        h("table", { class: "tableau" },
          h("thead", {}, h("tr", {}, colonnes.map((col, i) =>
            h("th", { class: (col.classe || "") + " triable", title: "Trier",
                      onclick: () => { tri = { col: i, sens: tri.col === i ? -tri.sens : 1 }; dessiner(); } },
              col.titre, tri.col === i ? (tri.sens > 0 ? " ▲" : " ▼") : "")))),
          h("tbody", {}, liste.map((c) =>
            h("tr", { class: c.alertes.length ? "en-alerte" : "", tabindex: "0", title: "Ouvrir la fiche",
                      onclick: () => ouvrir(c), onkeydown: (ev) => { if (ev.key === "Enter") ouvrir(c); } },
              colonnes.map((col) => h("td", { class: col.classe || "" }, col.cellule(c)))))))));
    };
    for (const e of [recherche]) e.addEventListener("input", dessiner);
    for (const e of [choixStatut, choixZone, avecAlertes]) e.addEventListener("change", dessiner);

    /* Le tableau prend toute la largeur de l’écran (zone neuve à chaque page). */
    zone.classList.add("vue-large");
    UI.vider(zone,
      onglets(""),
      barrePeriode("#/suivi", periode),
      h("div", { class: "carte pile" },
        h("div", { class: "formulaire" },
          h("label", { class: "champ" }, h("span", {}, "Rechercher"), recherche),
          h("label", { class: "champ" }, h("span", {}, "Statut"), choixStatut),
          h("label", { class: "champ" }, h("span", {}, "Zone"), choixZone)),
        h("div", { class: "ligne" },
          h("label", { class: "case etire" }, avecAlertes, "Seulement les commandes en alerte"),
          h("button", { class: "btn btn-vert", type: "button", onclick: () => exporter(filtrees(), r, periode) },
            UI.icone("telecharger", "ic-sm"), "Exporter vers Excel"))),
      compte, corps);
    dessiner();
  }

  /* ---------- L'export Excel ---------- */

  async function exporter(commandes, r, periode) {
    if (!commandes.length) return UI.echec("Rien à exporter : aucune commande ne correspond.");
    const m = r.montants;
    const zone = (c) => c.client.zone || c.client.adresse || "";
    const observations = (c) => [c.observations, ...c.alertes.map((a) => (ALERTES[a] || [a])[0]),
      c.incidents_ouverts ? c.incidents_ouverts + " incident(s) ouvert(s)" : ""].filter(Boolean).join(" ; ") || "—";
    /* La feuille au format exact du classeur de BIZZOO. */
    const suivi = {
      nom: "Suivi commandes",
      colonnes: [
        { titre: "N° commande", largeur: 13 }, { titre: "Date / heure de passation", largeur: 20 },
        { titre: "Client / téléphone / zone", largeur: 34 }, { titre: "Articles commandés", largeur: 34 },
        { titre: "Marchand / numéro", largeur: 28 }, { titre: "Frais de livraison (FCFA)", largeur: 14, type: "fcfa" },
        { titre: "Total commande (FCFA)", largeur: 14, type: "fcfa" }, { titre: "Reste à encaisser (FCFA)", largeur: 14, type: "fcfa" },
        { titre: "Livreur / contact", largeur: 28 }, { titre: "Statut", largeur: 24 },
        { titre: "Confirmation client", largeur: 12 }, { titre: "Délai de livraison", largeur: 12 },
        { titre: "Observations / incidents", largeur: 40 }],
      lignes: commandes.map((c) => [
        c.numero || c.id, dateSuivi(c.cree_le),
        [c.client.nom, c.client.tel, zone(c)].filter(Boolean).join(" / "),
        c.articles, c.marchands,
        m ? Number(c.frais) : "", m ? Number(c.total) : "", m ? Number(c.reste) : "",
        c.livreurs || "—", c.statut, c.confirmation, delai(c.delai_h), observations(c)]),
    };
    /* Une ligne par marchand d'une même commande : la traçabilité du document. */
    const detail = {
      nom: "Détail par marchand",
      colonnes: [
        { titre: "N° commande", largeur: 13 }, { titre: "Date de passation", largeur: 18 }, { titre: "Payée le", largeur: 18 },
        { titre: "Client", largeur: 20 }, { titre: "Téléphone", largeur: 15 }, { titre: "Zone", largeur: 22 },
        { titre: "Adresse", largeur: 30 }, { titre: "Marchand", largeur: 22 }, { titre: "Numéro du marchand", largeur: 15 },
        { titre: "Article", largeur: 26 }, { titre: "Code", largeur: 10 }, { titre: "Quantité", largeur: 9, type: "nombre" },
        ...(m ? [{ titre: "Prix unitaire (FCFA)", largeur: 13, type: "fcfa" }, { titre: "Montant (FCFA)", largeur: 13, type: "fcfa" }] : []),
        { titre: "Statut de l'article", largeur: 24 }, { titre: "Livreur", largeur: 20 }, { titre: "Contact livreur", largeur: 15 },
        { titre: "Vu par le marchand", largeur: 18 }, { titre: "Déclaré livré", largeur: 18 }, { titre: "Confirmé par le client", largeur: 18 },
        { titre: "Délai vu → reçu (h)", largeur: 12, type: "heures" }, { titre: "Statut de la commande", largeur: 24 },
        { titre: "Alertes", largeur: 30 }],
      lignes: commandes.flatMap((c) => c.lignes.map((l) => {
        const dh = l.confirme_le && l.vue_le ? Math.round((new Date(l.confirme_le) - new Date(l.vue_le)) / 360000) / 10 : "";
        return [c.numero || c.id, dateSuivi(c.cree_le), c.paye_le ? dateSuivi(c.paye_le) : "", c.client.nom, c.client.tel,
          c.client.zone || "", c.client.adresse, l.boutique, l.boutique_tel, l.nom, l.code || "", Number(l.quantite),
          ...(m ? [Number(l.prix), Number(l.prix) * Number(l.quantite)] : []),
          l.statut, l.livreur || "", l.livreur_tel || "", l.vue_le ? dateSuivi(l.vue_le) : "",
          l.remise_le ? dateSuivi(l.remise_le) : "", l.confirme_le ? dateSuivi(l.confirme_le) : "", dh, c.statut,
          c.alertes.map((a) => (ALERTES[a] || [a])[0]).join(" ; ")];
      })),
    };
    const feuilles = [suivi, detail];
    try {
      const b = await Supabase.rpc("rh_suivi_bilan", { depuis: periode.depuis, jusqu: periode.jusqu, pas: "jour" });
      feuilles.push(feuilleBilan(b));
    } catch (_) { /* le bilan manque : les deux feuilles suffisent */ }
    Xlsx.telecharger("BIZZOO_suivi_" + periode.depuis + "_au_" + periode.jusqu + ".xlsx", feuilles);
    UI.succes("Fichier Excel prêt : " + commandes.length + " commande(s).");
  }

  const INDICATEURS = [
    ["recues", "Total des commandes reçues"], ["payees", "Commandes payées"],
    ["livrees_confirmees", "Commandes livrées et confirmées"], ["en_cours", "Commandes en cours"],
    ["en_retard", "Commandes en retard"], ["contestees", "Livraisons contestées"],
    ["annulees", "Commandes annulées"], ["echecs_retours", "Échecs et retours"]];

  function feuilleBilan(b) {
    const lignes = INDICATEURS.map(([k, l]) => [l, Number(b.total[k] || 0)]);
    if (b.montants) lignes.push(["Sommes restant à encaisser (FCFA)", Number(b.total.reste || 0)]);
    lignes.push(["", ""], ["Par jour", ""]);
    for (const s of b.series) lignes.push([UI.date(s.periode) + " : reçues / livrées et confirmées / en retard",
      s.recues + " / " + s.livrees_confirmees + " / " + s.en_retard]);
    lignes.push(["", ""], ["Par livreur (articles confirmés / livrés sans confirmation / échecs)", ""]);
    for (const x of b.par_livreur) lignes.push([x.livreur, x.confirmees + " / " + x.sans_confirmation + " / " + x.echecs]);
    lignes.push(["", ""], ["Par marchand (articles / annulés / incidents / réclamations)", ""]);
    for (const x of b.par_marchand) lignes.push([x.marchand, x.articles + " / " + x.annules + " / " + x.incidents + " / " + x.reclamations]);
    lignes.push(["", ""], ["Commandes par zone", ""]);
    for (const x of b.par_zone) lignes.push([x.zone, Number(x.commandes)]);
    return { nom: "Bilan", colonnes: [{ titre: "Indicateur", largeur: 60 }, { titre: "Valeur", largeur: 22, type: "nombre" }],
      lignes: lignes.map((l) => [l[0], typeof l[1] === "number" ? l[1] : String(l[1])]) };
  }

  /* ---------- Les alertes ---------- */

  async function alertes(zone) {
    const fin = new Date(), debut = new Date();
    debut.setDate(debut.getDate() - 59);
    const r = await Supabase.rpc("rh_suivi", { depuis: iso(debut), jusqu: iso(fin) });
    if (!zone.isConnected) return;
    const liste = r.commandes.filter((c) => c.alertes.some((a) => a !== "refus_course"));
    const parType = {};
    for (const c of liste) for (const a of c.alertes) parType[a] = (parType[a] || 0) + 1;
    UI.vider(zone,
      onglets("alertes"),
      h("p", { class: "doux petit" }, "Les commandes des 60 derniers jours qui demandent une action. Délais réglés : vue " +
        r.reglages.vue_h + " h, préparation " + r.reglages.preparation_h + " h, livraison " + r.reglages.livraison_h +
        " h, confirmation " + r.reglages.confirmation_h + " h."),
      Object.keys(parType).length ? h("div", { class: "tuiles" }, Object.entries(parType).map(([a, n]) =>
        h("div", { class: "tuile" + ((ALERTES[a] || [])[1] === "rouge" ? " alerte" : "") },
          h("b", {}, n), h("span", {}, (ALERTES[a] || [a])[0])))) : null,
      liste.length ? h("div", { class: "liste" }, liste.map((c) =>
        h("a", { class: "element", href: "#/suivi/commande/" + encodeURIComponent(c.id) },
          h("div", { class: "etire" },
            h("div", { class: "ligne" }, h("span", { class: "gras" }, c.numero || c.id),
              h("span", { class: "doux tres-petit" }, dateSuivi(c.cree_le)), h("span", { class: "etire" }), etiquetteStatut(c)),
            h("div", { class: "petit doux coupe" }, [c.client.nom, c.client.zone, c.marchands].filter(Boolean).join(" · ")),
            h("div", { class: "actions" }, etiquettesAlertes(c.alertes))),
          UI.icone("chevron", "ic-sm")))) : UI.vide("Aucune alerte : tout suit son cours."));
  }

  /* ---------- Le bilan ---------- */

  async function bilan(zone, params) {
    const periode = periodeDe(params, "30j");
    const pas = ["jour", "semaine", "mois"].includes(params.pas) ? params.pas : "jour";
    const b = await Supabase.rpc("rh_suivi_bilan", { depuis: periode.depuis, jusqu: periode.jusqu, pas });
    if (!zone.isConnected) return;
    const lienPas = (v) => "#/suivi/bilan" + (periode.choix ? "?p=" + periode.choix[0] : "?du=" + periode.depuis + "&au=" + periode.jusqu) + "&pas=" + v;
    const tuile = (v, l, alerte) => h("div", { class: "tuile" + (alerte && v > 0 ? " alerte" : "") }, h("b", {}, UI.entier(v || 0)), h("span", {}, l));
    const tableau = (titre, entetes, lignes) => h("div", { class: "carte defile" },
      h("h3", { style: { marginBottom: "8px" } }, titre),
      lignes.length ? h("table", { class: "tableau" },
        h("thead", {}, h("tr", {}, entetes.map((e, i) => h("th", { class: i ? "nombre" : "" }, e)))),
        h("tbody", {}, lignes.map((l) => h("tr", {}, l.map((v, i) => h("td", { class: i ? "nombre" : "" }, v))))))
        : h("p", { class: "doux petit" }, "Rien sur cette période."));
    const JOURS = ["", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"];
    const t = b.total;
    UI.vider(zone,
      onglets("bilan"),
      barrePeriode("#/suivi/bilan", periode, "&pas=" + pas),
      h("div", { class: "ligne" },
        h("div", { class: "filtres" }, [["jour", "Par jour"], ["semaine", "Par semaine"], ["mois", "Par mois"]].map(([v, l]) =>
          h("button", { class: v === pas ? "actif" : "", onclick: () => { location.hash = lienPas(v); } }, l))),
        h("span", { class: "etire" }),
        h("button", { class: "btn btn-vert btn-petit", onclick: () => {
          Xlsx.telecharger("BIZZOO_bilan_" + periode.depuis + "_au_" + periode.jusqu + ".xlsx", [feuilleBilan(b)]);
        } }, UI.icone("telecharger", "ic-sm"), "Exporter le bilan")),
      h("div", { class: "tuiles" },
        tuile(t.recues, "commandes reçues"), tuile(t.payees, "payées"),
        tuile(t.livrees_confirmees, "livrées et confirmées"), tuile(t.en_cours, "en cours"),
        tuile(t.en_retard, "en retard", true), tuile(t.contestees, "livraisons contestées", true),
        tuile(t.annulees, "annulées"), tuile(t.echecs_retours, "échecs et retours", true),
        b.montants ? h("div", { class: "tuile" }, h("b", { style: { fontSize: "17px" } }, UI.fcfa(t.reste)), h("span", {}, "restant à encaisser")) : null,
        b.clients ? tuile(b.clients.distincts, "clients différents") : null,
        b.clients ? tuile(b.clients.nouveaux, "nouveaux clients") : null),
      tableau("Par " + pas, ["Période", "Reçues", "Payées", "Livrées et confirmées", "En cours", "En retard", "Contestées", "Annulées",
        ...(b.montants ? ["Reste (FCFA)"] : [])],
        b.series.map((s) => [pas === "mois" ? UI.mois(s.periode) : pas === "semaine" ? "Semaine du " + UI.date(s.periode) : UI.date(s.periode),
          s.recues, s.payees, s.livrees_confirmees, s.en_cours, s.en_retard, s.contestees, s.annulees,
          ...(b.montants ? [UI.entier(s.reste)] : [])])),
      tableau("Livreurs", ["Livreur", "Articles", "Confirmés", "Sans confirmation", "Échecs", "Contestés", "Délai moyen", "Refus", "Incidents"],
        b.par_livreur.map((x) => [x.livreur, x.articles, x.confirmees, x.sans_confirmation, x.echecs, x.contestees,
          delai(x.delai_moyen_h), x.refus, x.incidents])),
      tableau("Marchands", ["Marchand", "Articles", "Annulés", "Pas vus", "Contestés", "Préparation", "Incidents", "Réclamations"],
        b.par_marchand.map((x) => [x.marchand, x.articles, x.annules, x.non_vus, x.contestes, delai(x.delai_preparation_h),
          x.incidents, x.reclamations])),
      tableau("Commandes payées par zone", ["Zone", "Commandes"], b.par_zone.map((x) => [x.zone, x.commandes])),
      tableau("Annulations", ["Motif", "Commandes"], b.annulations.map((x) => [x.motif, x.nombre])),
      tableau("Heures de pointe (commandes passées)", ["Heure", "Commandes"], b.heures.map((x) => [x.heure + " h", x.commandes])),
      tableau("Jours de la semaine", ["Jour", "Commandes"], b.jours_semaine.map((x) => [JOURS[x.jour], x.commandes])),
      h("p", { class: "doux tres-petit" }, "Les délais se mesurent avec le journal des étapes : les commandes d'avant son installation n'ont que les dates de commande, de paiement, d'acceptation de la course et de réception."));
  }

  /* ---------- Les réglages ---------- */

  async function reglages(zone) {
    const r = await Supabase.rpc("rh_suivi", { depuis: iso(new Date()), jusqu: iso(new Date()) });
    if (!zone.isConnected) return;
    const g = r.reglages;
    const champ = (nom, libelle, aide) => {
      const e = h("input", { type: "number", min: 1, max: 720, value: g[nom], required: true });
      e.name = nom;
      return h("label", { class: "champ" }, h("span", {}, libelle), e, h("small", {}, aide));
    };
    const form = h("form", { class: "carte pile" },
      h("h2", {}, "Délais des alertes (en heures)"),
      h("div", { class: "formulaire" },
        champ("vue_h", "Le marchand doit voir la commande", "après le paiement"),
        champ("preparation_h", "Le marchand doit l'avoir préparée", "après l'avoir vue"),
        champ("livraison_h", "Le colis doit être livré", "après le paiement"),
        champ("confirmation_h", "Le client doit confirmer", "après la livraison déclarée")),
      h("div", { class: "actions" }, h("button", { class: "btn", type: "submit" }, "Enregistrer")));
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const v = (n) => Number(form.querySelector("[name=" + n + "]").value);
      await UI.agir(ev.submitter, () => Supabase.rpc("rh_suivi_regler", {
        vue_h: v("vue_h"), preparation_h: v("preparation_h"), livraison_h: v("livraison_h"), confirmation_h: v("confirmation_h") }),
        "Délais enregistrés.");
      App.rafraichir();
    });
    const nom = h("input", { required: true, placeholder: "Ex. : Bidossessi" });
    const commune = h("input", { placeholder: "Ex. : Abomey-Calavi" });
    const formZone = h("form", { class: "carte pile" },
      h("h2", {}, "Ajouter une zone"),
      h("p", { class: "doux petit" }, "Les zones sont lues dans l'adresse des clients, grâce au découpage du Bénin. La liste des quartiers est partielle : ajoutez ceux que vos clients écrivent et qui ne sont pas reconnus."),
      h("div", { class: "formulaire" },
        h("label", { class: "champ" }, h("span", {}, "Quartier ou lieu"), nom),
        h("label", { class: "champ" }, h("span", {}, "Commune"), commune)),
      h("div", { class: "actions" }, h("button", { class: "btn btn-second", type: "submit" }, "Ajouter")));
    formZone.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      await UI.agir(ev.submitter, () => Supabase.rpc("rh_zone_ajouter", { nom_zone: nom.value.trim(), commune_zone: commune.value.trim() }),
        "Zone ajoutée : elle sera reconnue dans les adresses.");
      nom.value = commune.value = "";
    });
    UI.vider(zone, onglets("reglages"), form, formZone);
  }

  /* ---------- La fiche d'une commande ---------- */

  async function fiche(zone, id) {
    const c = await Supabase.rpc("rh_suivi_commande", { commande: id });
    if (!zone.isConnected) return;
    App.titre("Commande " + (c.numero || c.id));
    const recharger = () => App.rafraichir().then(() => fiche(zone, id));
    const close = !!c.cloturee_le;

    const zoneChamp = h("input", { value: c.client.zone || "", placeholder: "Quartier (Commune)" });
    const obs = h("textarea", { placeholder: "Observations sur cette commande" });
    obs.value = c.observations || "";
    const formNotes = h("form", { class: "carte pile" },
      h("h3", {}, "Zone et observations"),
      h("label", { class: "champ" }, h("span", {}, "Zone de livraison" + (c.client.zone_corrigee ? " (corrigée)" : " (lue dans l'adresse)")), zoneChamp,
        h("small", {}, "Adresse du client : " + (c.client.adresse || "—"))),
      h("label", { class: "champ" }, h("span", {}, "Observations"), obs),
      h("div", { class: "actions" }, h("button", { class: "btn btn-second", type: "submit" }, "Enregistrer")));
    formNotes.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      await UI.agir(ev.submitter, () => Supabase.rpc("rh_suivi_noter", { commande: c.id, zone: zoneChamp.value.trim(), observations: obs.value }),
        "Enregistré.");
      recharger();
    });

    const lignes = h("div", { class: "carte defile" },
      h("h3", { style: { marginBottom: "8px" } }, "Articles, par marchand"),
      h("table", { class: "tableau" },
        h("thead", {}, h("tr", {}, ["Article", "Marchand", "Livreur", "Statut", "Noter sur le terrain"].map((e) => h("th", {}, e)))),
        h("tbody", {}, c.lignes.map((l) => {
          const choix = h("select", { disabled: close }, TERRAIN.map(([v, t]) => h("option", { value: v, selected: (l.terrain || "") === v }, t)));
          choix.addEventListener("change", async () => {
            let motif = "";
            if (choix.value === "echouee" || choix.value === "retour_en_cours") {
              motif = await UI.motif(choix.value === "echouee" ? "Livraison échouée" : "Retour en cours", "Motif");
              if (motif === null) { choix.value = l.terrain || ""; return; }
            }
            try {
              await Supabase.rpc("rh_suivi_terrain", { ligne: l.id, statut: choix.value, motif });
              UI.succes("Statut noté.");
              recharger();
            } catch (err) { UI.echec(err); choix.value = l.terrain || ""; }
          });
          return h("tr", {},
            h("td", {}, l.quantite + " × " + l.nom, c.montants && l.prix !== undefined ? h("div", { class: "tres-petit doux" }, UI.fcfa(l.prix) + " l'unité") : null),
            h("td", {}, l.boutique, h("div", { class: "tres-petit doux" }, l.boutique_tel || "")),
            h("td", {}, l.livreur || "—", h("div", { class: "tres-petit doux" }, l.livreur_tel || "")),
            h("td", {}, UI.etiquette(l.statut, COULEUR_STATUT[l.rang] || ""), l.terrain_motif ? h("div", { class: "tres-petit doux" }, l.terrain_motif) : null),
            h("td", {}, choix));
        }))));

    const incidents = h("div", { class: "carte pile" },
      h("div", { class: "titre-section" }, h("h3", {}, "Incidents"),
        close ? null : h("button", { class: "btn btn-petit", onclick: async (ev) => {
          const marchands = [...new Map(c.lignes.map((l) => [l.boutique_id, l.boutique])).entries()];
          const v = await UI.formulaire({ titre: "Signaler un incident", champs: [
            { nom: "type", libelle: "Type", type: "select", valeur: "retard", options: TYPES_INCIDENT.map(([valeur, libelle]) => ({ valeur, libelle })) },
            { nom: "boutique", libelle: "Marchand concerné", type: "select", valeur: "",
              options: [{ valeur: "", libelle: "— Aucun en particulier —" }, ...marchands.map(([valeur, libelle]) => ({ valeur, libelle }))] },
            { nom: "description", libelle: "Ce qui s'est passé", type: "textarea", requis: true }],
            verifier: (x) => (x.description ? null : "Décrivez l'incident.") });
          if (!v) return;
          await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_incident_ouvrir", { commande: c.id, type: v.type,
            description: v.description, boutique: v.boutique || null, livreur: null }), "Incident enregistré.");
          recharger();
        } }, UI.icone("plus", "ic-sm"), "Signaler")),
      c.incidents.length ? h("div", { class: "liste" }, c.incidents.map((i) => h("div", { class: "element" },
        h("div", { class: "etire" },
          h("div", { class: "ligne" }, h("b", {}, (TYPES_INCIDENT.find((t) => t[0] === i.type) || [0, i.type])[1]),
            i.resolu_le ? UI.etiquette("Résolu", "vert") : UI.etiquette("Ouvert", "rouge")),
          h("div", { class: "petit" }, i.description),
          h("div", { class: "tres-petit doux" }, UI.dateHeure(i.cree_le) + (i.auteur ? " · " + i.auteur : "") + (i.boutique ? " · " + i.boutique : "")),
          i.resolu_le ? h("div", { class: "tres-petit", style: { color: "var(--vert-fonce)" } }, "Résolu le " + UI.dateHeure(i.resolu_le) + " : " + i.resolution) : null),
        !i.resolu_le ? h("button", { class: "btn btn-second btn-petit", onclick: async (ev) => {
          const resolution = await UI.motif("Résoudre l'incident", "Comment a-t-il été résolu ?");
          if (resolution === null) return;
          await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_incident_resoudre", { incident: i.id, resolution }), "Incident résolu.");
          recharger();
        } }, "Résoudre") : null))) : h("p", { class: "doux petit" }, "Aucun incident."));

    const journal = h("div", { class: "carte" },
      h("h3", { style: { marginBottom: "8px" } }, "Chronologie"),
      c.journal.length ? h("div", { class: "liste" }, c.journal.map((j) => h("div", { class: "element" },
        h("div", { class: "tres-petit doux", style: { minWidth: "130px" } }, dateSuivi(j.le)),
        h("div", { class: "etire petit" },
          h("b", {}, QUOI[j.quoi] || j.quoi), j.valeur && j.quoi !== "livreur" ? " : " + (ETAPES[j.valeur] || j.valeur) : "",
          j.livreur ? " : " + j.livreur : "",
          j.article ? h("span", { class: "doux" }, " — " + j.article + (j.boutique ? " (" + j.boutique + ")" : "")) : null,
          j.reconstitue ? h("span", { class: "doux" }, " · reconstitué") : null)))) : h("p", { class: "doux petit" }, "Rien de noté."));

    const autres = [];
    if (c.reclamations.length) autres.push(h("div", { class: "carte" }, h("h3", {}, "Réclamations du client"),
      h("ul", { class: "petit" }, c.reclamations.map((x) => h("li", {}, UI.date(x.cree_le) + " · " + x.sujet + " · " + x.etat + (x.boutique ? " · " + x.boutique : ""))))));
    if (c.refus.length) autres.push(h("div", { class: "carte" }, h("h3", {}, "Courses refusées"),
      h("ul", { class: "petit" }, c.refus.map((x) => h("li", {}, UI.dateHeure(x.le) + " · " + (x.livreur || "") + (x.motif ? " · " + x.motif : ""))))));

    const actions = [];
    if (!close) {
      actions.push(h("button", { class: "btn btn-vert", onclick: async (ev) => {
        if (!await UI.confirmer("Clôturer le suivi de cette commande ? Plus rien ne pourra y être noté sans la rouvrir.", { valider: "Clôturer" })) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_suivi_cloturer", { commande: c.id }), "Commande clôturée.");
        recharger();
      } }, UI.icone("check", "ic-sm"), "Clôturer"));
    } else if (App.estAdmin()) {
      actions.push(h("button", { class: "btn btn-second", onclick: async (ev) => {
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_suivi_rouvrir", { commande: c.id }), "Commande rouverte.");
        recharger();
      } }, "Rouvrir"));
    }

    UI.vider(zone,
      h("div", { class: "carte pile" },
        h("div", { class: "ligne" }, h("h2", { class: "etire", style: { marginBottom: 0 } }, "Commande " + (c.numero || c.id)), etiquetteStatut(c)),
        c.alertes.length ? h("div", { class: "actions" }, etiquettesAlertes(c.alertes)) : null,
        h("div", { class: "formulaire petit" },
          h("div", {}, h("div", { class: "doux" }, "Passée le"), h("b", {}, dateSuivi(c.cree_le))),
          h("div", {}, h("div", { class: "doux" }, "Payée le"), h("b", {}, c.paye_le ? dateSuivi(c.paye_le) : "—")),
          h("div", {}, h("div", { class: "doux" }, "Client"), h("b", {}, c.client.nom || "—"), h("div", {}, c.client.tel || "")),
          h("div", {}, h("div", { class: "doux" }, "Zone"), h("b", {}, c.client.zone || "Non reconnue")),
          h("div", {}, h("div", { class: "doux" }, "Confirmation client"), h("b", {}, c.confirmation)),
          h("div", {}, h("div", { class: "doux" }, "Délai vu → reçu"), h("b", {}, delai(c.delai_h))),
          c.montants ? h("div", {}, h("div", { class: "doux" }, "Total"), h("b", {}, montant(c.total)),
            h("div", { class: "tres-petit doux" }, "dont livraison " + montant(c.frais))) : null,
          c.montants ? h("div", {}, h("div", { class: "doux" }, "Reste à encaisser"), h("b", {}, montant(c.reste))) : null),
        close ? h("div", { class: "info" }, "Clôturée le " + dateSuivi(c.cloturee_le) + ".") : null,
        actions.length ? h("div", { class: "actions" }, actions) : null),
      lignes, incidents, formNotes, ...autres, journal);
  }

  return { titre: "Suivi des commandes", afficher };
})();
