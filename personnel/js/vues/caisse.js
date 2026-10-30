/* =========================================================
   Caisse — la caisse de la maison.

   Quatre compartiments : espèces, MTN Mobile Money, Moov Money,
   Celtiis Cash. Leur somme fait le solde. Le gestionnaire, désigné
   par le CEO, la tient : il enregistre les apports, déplace l'argent
   d'un compartiment à l'autre, et c'est d'ici que sortent les
   dépenses décaissées, les salaires retirés et les prêts — au besoin répartis
   entre compartiments. Le CEO ajuste (un écart, une erreur), avec un
   motif : aucun mouvement ne se modifie ni ne s'efface.

   La base décide de tout (rh_caisse…) : qui voit, qui écrit, et
   qu'aucun compartiment ne passe sous zéro.
   ========================================================= */
const VueCaisse = (() => {
  const { h } = UI;
  const COMPTES = [["especes", "Espèces"], ["mtn", "MTN Mobile Money"], ["moov", "Moov Money"], ["celtiis", "Celtiis Cash"]];
  const NOM_COMPTE = Object.fromEntries(COMPTES);
  const NATURES = { apport_ceo: "Apport du CEO", apport_autre: "Apport", depense: "Dépense", salaire: "Salaire", pret: "Prêt",
    transfert: "Transfert", frais: "Frais d'opérateur", ajustement: "Ajustement" };

  const iso = (d) => d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  function periodes() {
    const j = new Date();
    const moins = (n) => { const d = new Date(j); d.setDate(d.getDate() - n); return iso(d); };
    return [
      ["jour", "Aujourd'hui", iso(j), iso(j)],
      ["7j", "7 jours", moins(6), iso(j)],
      ["mois", "Ce mois", iso(new Date(j.getFullYear(), j.getMonth(), 1)), iso(j)],
      ["moisprec", "Mois dernier", iso(new Date(j.getFullYear(), j.getMonth() - 1, 1)), iso(new Date(j.getFullYear(), j.getMonth(), 0))],
      ["annee", "Cette année", j.getFullYear() + "-01-01", iso(j)],
    ];
  }

  /* (3.70.0) Un numéro de téléphone saisi comme référence de transaction :
     la fenêtre le dit et reste ouverte. Revalidée telle quelle, la
     référence passe (un n° de reçu peut ressembler à un numéro). */
  function referenceDouteuse(reference, dejaAvertie, retenir) {
    const r = String(reference || "").trim();
    if (!r || r === dejaAvertie || !UI.ressembleTelephone(r)) return null;
    retenir(r);
    return UI.alerteTransaction(r);
  }

  /**
   * D'où sort l'argent d'un décaissement ou d'un salaire : la répartition
   * entre compartiments, avec le solde de chacun sous les yeux. Rend
   * { repartition, reference }, ou null si l'on renonce. Partagé avec
   * Dépenses et Paie.
   */
  async function repartir({ titre, montant, valider }) {
    let comptes = [];
    try { comptes = (await Supabase.rpc("rh_caisse")).comptes || []; } catch (_) { /* soldes inconnus : on saisit quand même */ }
    const solde = (c) => { const x = comptes.find((k) => k.compte === c); return x ? Number(x.solde) : null; };
    const premier = COMPTES.find(([c]) => (solde(c) ?? 0) >= montant);
    let refAvertie = null;
    const v = await UI.formulaire({
      titre, valider: valider || "Confirmer",
      texte: "Montant : " + UI.fcfa(montant) + ". Répartissez-le entre les compartiments de la caisse (espèces seules, ou espèces + Mobile Money…) : le total doit tomber juste.",
      champs: COMPTES.map(([c, libelle]) => ({ nom: c, type: "number", min: 0, pas: 1,
        libelle: libelle + (solde(c) === null ? "" : " — disponible : " + UI.fcfa(solde(c))),
        valeur: premier && premier[0] === c ? montant : "" }))
        .concat([{ nom: "reference", libelle: "Référence (n° de transaction Mobile Money, de reçu…)" }]),
      verifier: (x) => {
        let total = 0;
        for (const [c, libelle] of COMPTES) {
          const n = x[c] === "" ? 0 : Number(x[c]);
          if (!Number.isInteger(n) || n < 0) return "Des francs entiers, positifs, pour " + libelle + ".";
          if (solde(c) !== null && n > solde(c)) return libelle + " n'a que " + UI.fcfa(solde(c)) + ".";
          total += n;
        }
        if (total !== montant) return "La répartition fait " + UI.fcfa(total) + " pour " + UI.fcfa(montant) + " : elle doit tomber juste.";
        return referenceDouteuse(x.reference, refAvertie, (r) => { refAvertie = r; });
      },
    });
    if (!v) return null;
    const repartition = {};
    for (const [c] of COMPTES) if (Number(v[c]) > 0) repartition[c] = Number(v[c]);
    return { repartition, reference: v.reference };
  }

  async function afficher(zone, morceaux, params) {
    UI.vider(zone, UI.chargement());
    const liste = periodes();
    const choix = liste.find((p) => p[0] === params.p) || (params.du ? null : liste[2]);
    const depuis = choix ? choix[2] : params.du;
    const jusqu = choix ? choix[3] : (params.au || iso(new Date()));
    const c = await Supabase.rpc("rh_caisse", { depuis, jusqu });
    if (!zone.isConnected) return;
    const recharger = () => afficher(zone, morceaux, params);
    const gerer = c.acces === "gestion";
    const ceo = c.acces === "ceo";
    const solde = c.comptes.reduce((t, k) => t + Number(k.solde), 0);
    const somme = (cle) => c.comptes.reduce((t, k) => t + Number(k[cle]), 0);

    /* ---------- Ce que chacun peut faire ---------- */
    const actions = [];
    if (gerer || ceo) {
      actions.push(h("button", { class: "btn btn-vert", onclick: async (ev) => {
        let refApport = null;
        const v = await UI.formulaire({ titre: "Enregistrer un apport", valider: "Enregistrer", champs: [
          { nom: "provenance", libelle: "Provenance", type: "select", valeur: "ceo", options: [{ valeur: "ceo", libelle: "Du CEO" }, { valeur: "autre", libelle: "D'une autre source" }] },
          { nom: "compte", libelle: "Dans quel compartiment", type: "select", valeur: "especes", options: COMPTES.map(([valeur, libelle]) => ({ valeur, libelle })) },
          { nom: "montant", libelle: "Montant (FCFA)", type: "number", min: 1, pas: 1, requis: true },
          { nom: "libelle", libelle: "Source ou motif (obligatoire pour une autre source)" },
          { nom: "reference", libelle: "Référence (n° de transaction, de reçu…)" }],
          verifier: (x) => !(Number(x.montant) > 0) || !Number.isInteger(Number(x.montant)) ? "Un montant en francs entiers, positif."
            : x.provenance === "autre" && x.libelle.length < 3 ? "Nommez la source de cet apport."
            : referenceDouteuse(x.reference, refApport, (r) => { refApport = r; }) });
        if (!v) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_caisse_apport", { compte: v.compte, montant: Number(v.montant),
          provenance: v.provenance, libelle: v.libelle, reference: v.reference }), "Apport enregistré.");
        recharger();
      } }, UI.icone("plus", "ic-sm"), "Apport"));
    }
    if (gerer) {
      actions.push(h("button", { class: "btn btn-second", onclick: async (ev) => {
        const options = COMPTES.map(([valeur, libelle]) => ({ valeur, libelle }));
        const v = await UI.formulaire({ titre: "Déplacer de l'argent", valider: "Déplacer",
          texte: "Un retrait Mobile Money en espèces, un dépôt… Les frais de l'opérateur sortent du compartiment de départ.",
          champs: [{ nom: "de", libelle: "De", type: "select", valeur: "mtn", options },
            { nom: "vers", libelle: "Vers", type: "select", valeur: "especes", options },
            { nom: "montant", libelle: "Montant (FCFA)", type: "number", min: 1, pas: 1, requis: true },
            { nom: "frais", libelle: "Frais de l'opérateur (FCFA)", type: "number", min: 0, pas: 1, valeur: 0 },
            { nom: "libelle", libelle: "Note" }],
          verifier: (x) => x.de === x.vers ? "Choisissez deux compartiments différents."
            : !(Number(x.montant) > 0) ? "Un montant positif." : null });
        if (!v) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_caisse_transfert", { de: v.de, vers: v.vers,
          montant: Number(v.montant), frais: Number(v.frais || 0), libelle: v.libelle }), "Argent déplacé.");
        recharger();
      } }, "Déplacer"));
    }
    if (ceo) {
      actions.push(h("button", { class: "btn btn-second", onclick: async (ev) => {
        const v = await UI.formulaire({ titre: "Ajuster la caisse", valider: "Ajuster", danger: true,
          texte: "Pour un écart constaté au comptage ou une erreur de saisie : rien ne s'efface, l'ajustement s'ajoute, avec son motif.",
          champs: [{ nom: "compte", libelle: "Compartiment", type: "select", valeur: "especes", options: COMPTES.map(([valeur, libelle]) => ({ valeur, libelle })) },
            { nom: "sens", libelle: "Sens", type: "select", valeur: "moins", options: [{ valeur: "moins", libelle: "Il manque de l'argent" }, { valeur: "plus", libelle: "Il y a de l'argent en plus" }] },
            { nom: "montant", libelle: "Montant (FCFA)", type: "number", min: 1, pas: 1, requis: true },
            { nom: "motif", libelle: "Motif", type: "textarea", requis: true }],
          verifier: (x) => !(Number(x.montant) > 0) ? "Un montant positif." : x.motif.length < 3 ? "Le motif est obligatoire." : null });
        if (!v) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_caisse_ajustement", { compte: v.compte,
          montant: (v.sens === "moins" ? -1 : 1) * Number(v.montant), motif: v.motif }), "Ajustement enregistré.");
        recharger();
      } }, "Ajuster"));
      actions.push(h("button", { class: "btn btn-second", onclick: async (ev) => {
        const employes = (await Supabase.rpc("rh_annuaire")).filter((e) => e.a_un_compte);
        const v = await UI.formulaire({ titre: "Gestionnaire de la caisse", valider: "Désigner",
          texte: "Lui seul décaisse les dépenses approuvées et paie les salaires.",
          champs: [{ nom: "qui", libelle: "Employé", type: "select", valeur: c.gestionnaire ? c.gestionnaire.id : "",
            options: employes.map((e) => ({ valeur: e.id, libelle: UI.nomComplet(e) + (e.poste ? " · " + e.poste : "") })) }] });
        if (!v) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_designer_gestionnaire_caisse", { qui: v.qui }), "Gestionnaire désigné.");
        App.rafraichir();
        recharger();
      } }, c.gestionnaire ? "Changer de gestionnaire" : "Désigner le gestionnaire"));
    }

    /* ---------- La période ---------- */

    const exporter = () => Xlsx.telecharger("BIZZOO_caisse_" + depuis + "_au_" + jusqu + ".xlsx", [{
      nom: "Mouvements de caisse",
      colonnes: [{ titre: "Date", largeur: 18 }, { titre: "Compartiment", largeur: 18 }, { titre: "Nature", largeur: 16 },
        { titre: "Libellé", largeur: 40 }, { titre: "Entrée (FCFA)", largeur: 14, type: "fcfa" }, { titre: "Sortie (FCFA)", largeur: 14, type: "fcfa" },
        { titre: "Solde de la caisse (FCFA)", largeur: 16, type: "fcfa" }, { titre: "Référence", largeur: 16 }, { titre: "Par", largeur: 20 }],
      lignes: c.mouvements.slice().reverse().map((m) => [UI.dateHeure(m.le), NOM_COMPTE[m.compte], NATURES[m.nature] || m.nature, m.libelle,
        m.sens === "entree" ? Number(m.montant) : "", m.sens === "sortie" ? Number(m.montant) : "", Number(m.solde_total), m.reference, m.par || ""]),
    }]);

    UI.vider(zone,
      h("div", { class: "carte pile" },
        h("div", { class: "ligne" },
          h("div", { class: "etire" },
            h("div", { class: "doux petit" }, "Solde de la caisse à l'instant"),
            h("div", { style: { fontSize: "30px", fontWeight: 800, color: "var(--bleu-900)" } }, UI.fcfa(solde))),
          UI.etiquette(c.acces === "gestion" ? "Vous tenez la caisse" : c.acces === "consultation" ? "Consultation" : c.acces === "ceo" ? "CEO" : "Superadministrateur", "bleu")),
        h("div", { class: "tuiles" }, c.comptes.map((k) => h("div", { class: "tuile" },
          h("b", { style: { fontSize: "17px" } }, UI.fcfa(k.solde)), h("span", {}, NOM_COMPTE[k.compte])))),
        h("div", { class: "petit doux" }, "Gestionnaire : " + (c.gestionnaire ? c.gestionnaire.nom : "aucun pour l'instant") +
          (c.gestionnaire ? "" : (ceo ? " — désignez-le pour pouvoir décaisser." : " — le CEO doit le désigner."))),
        actions.length ? h("div", { class: "actions" }, actions) : null),
      UI.barrePeriode({ liste, choix, depuis, jusqu }, "#/caisse"),
      h("div", { class: "tuiles" },
        h("div", { class: "tuile" }, h("b", { style: { fontSize: "17px" } }, UI.fcfa(somme("debut"))), h("span", {}, "solde au " + UI.date(depuis))),
        h("div", { class: "tuile" }, h("b", { style: { fontSize: "17px", color: "var(--vert-fonce)" } }, "+ " + UI.fcfa(somme("entrees"))), h("span", {}, "entrées de la période")),
        h("div", { class: "tuile" }, h("b", { style: { fontSize: "17px", color: "var(--rouge-fonce)" } }, "− " + UI.fcfa(somme("sorties"))), h("span", {}, "sorties de la période")),
        h("div", { class: "tuile" }, h("b", { style: { fontSize: "17px" } }, UI.fcfa(somme("debut") + somme("entrees") - somme("sorties"))), h("span", {}, "solde au " + UI.date(jusqu)))),
      h("div", { class: "carte defile", style: { padding: 0 } },
        h("div", { class: "ligne", style: { padding: "12px 12px 0" } }, h("h3", { class: "etire" }, "Mouvements (" + c.mouvements.length + ")"),
          c.mouvements.length ? h("button", { class: "btn btn-petit btn-second", onclick: exporter }, UI.icone("telecharger", "ic-sm"), "Excel") : null),
        c.mouvements.length ? h("table", { class: "tableau" },
          h("thead", {}, h("tr", {}, ["Date", "Compartiment", "Opération", "Entrée", "Sortie", "Solde"].map((t, i) => h("th", { class: i > 2 ? "nombre" : "" }, t)))),
          h("tbody", {}, c.mouvements.map((m) => h("tr", {},
            h("td", { class: "petit", style: { whiteSpace: "nowrap" } }, UI.dateHeure(m.le)),
            h("td", { class: "petit" }, NOM_COMPTE[m.compte]),
            h("td", {}, h("div", { class: "gras petit" }, NATURES[m.nature] || m.nature),
              h("div", { class: "tres-petit doux" }, [m.depense_id ? h("a", { href: "#/depenses/" + m.depense_id }, m.libelle) : m.libelle]),
              h("div", { class: "tres-petit doux" }, [m.reference ? "Réf. " + m.reference : "", m.par ? "par " + m.par : ""].filter(Boolean).join(" · "))),
            h("td", { class: "nombre", style: { color: "var(--vert-fonce)" } }, m.sens === "entree" ? UI.entier(m.montant) : ""),
            h("td", { class: "nombre", style: { color: "var(--rouge-fonce)" } }, m.sens === "sortie" ? UI.entier(m.montant) : ""),
            h("td", { class: "nombre gras" }, UI.entier(m.solde_total)))))) : UI.vide("Aucun mouvement sur cette période.")));
  }

  return { titre: "Caisse", afficher, repartir, COMPTES };
})();
