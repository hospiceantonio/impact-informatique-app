/* =========================================================
   Dépenses — demandées par le responsable d'un profil,
   approuvées (ou refusées) par le CEO, puis décaissées par
   l'employé habilité, qui note le mode et la référence.
   Personne ne décaisse ce que le CEO n'a pas approuvé.
   ========================================================= */
const VueDepenses = (() => {
  const { h } = UI;

  const STATUTS = {
    demandee: ["À approuver", "orange"],
    approuvee: ["À décaisser", "bleu"],
    decaissee: ["Décaissée", "vert"],
    refusee: ["Refusée", "rouge"],
    annulee: ["Annulée", ""],
  };
  const MODES = { especes: "Espèces", virement: "Virement", mobile_money: "Mobile Money", cheque: "Chèque" };
  const etiquette = (s) => UI.etiquette(...(STATUTS[s] || [s, ""]));
  const numero = (d) => "D-" + String(d.numero).padStart(4, "0");

  let annuaire = [];
  const nom = (id) => UI.nomComplet(annuaire.find((e) => e.id === id));

  async function afficher(zone, morceaux, params) {
    UI.vider(zone, UI.chargement());
    annuaire = await Supabase.rpc("rh_annuaire").catch(() => []);
    if (morceaux[0] === "nouvelle") return formulaire(zone);
    if (morceaux[0]) return fiche(zone, morceaux[0]);
    return liste(zone, params.filtre || "");
  }

  async function liste(zone, filtre) {
    let chemin = "rh_depenses?select=*,profil:rh_profils(nom)&order=cree_le.desc&limit=300";
    if (filtre) chemin += "&statut=eq." + filtre;
    const depenses = await Supabase.lire(chemin);
    if (!zone.isConnected) return;
    const total = (s) => depenses.filter((d) => d.statut === s).reduce((t, d) => t + Number(d.montant), 0);
    UI.vider(zone,
      h("div", { class: "titre-section" }, h("h2", {}, "Dépenses"),
        App.estResponsable() ? h("a", { class: "btn btn-petit", href: "#/depenses/nouvelle" }, UI.icone("plus", "ic-sm"), "Demander une dépense") : null),
      h("div", { class: "filtres" }, [["", "Toutes"], ["demandee", "À approuver"], ["approuvee", "À décaisser"], ["decaissee", "Décaissées"], ["refusee", "Refusées"]]
        .map(([v, l]) => h("button", { class: v === filtre ? "actif" : "", onclick: () => { location.hash = "#/depenses" + (v ? "?filtre=" + v : ""); } }, l))),
      !filtre && depenses.length ? h("div", { class: "tuiles" },
        h("div", { class: "tuile" }, h("b", { style: { fontSize: "17px" } }, UI.fcfa(total("demandee"))), h("span", {}, "en attente du CEO")),
        h("div", { class: "tuile" }, h("b", { style: { fontSize: "17px" } }, UI.fcfa(total("approuvee"))), h("span", {}, "approuvées, à décaisser")),
        h("div", { class: "tuile" }, h("b", { style: { fontSize: "17px" } }, UI.fcfa(total("decaissee"))), h("span", {}, "décaissées"))) : null,
      depenses.length ? h("div", { class: "liste" }, depenses.map((d) =>
        h("a", { class: "element", href: "#/depenses/" + d.id },
          h("div", { class: "etire" },
            h("div", { class: "ligne" }, h("span", { class: "gras etire coupe" }, d.objet), h("b", {}, UI.fcfa(d.montant))),
            h("div", { class: "ligne petit doux" }, h("span", { class: "etire coupe" }, numero(d) + " · " +
              ((d.profil && d.profil.nom) || "") + " · " + UI.date(d.cree_le)), etiquette(d.statut))),
          UI.icone("chevron", "ic-sm"))))
        : UI.vide("Aucune dépense ici."));
  }

  async function formulaire(zone, depense) {
    App.titre(depense ? "Modifier la demande" : "Demande de dépense");
    const mesProfils = App.moi().responsable_de || [];
    const profils = mesProfils.length ? await Supabase.lire("rh_profils?select=id,nom&id=in.(" + mesProfils.join(",") + ")") : [];
    if (!zone.isConnected) return;
    if (!profils.length) return UI.vider(zone, h("div", { class: "avertissement" }, "Seul le responsable d'un profil demande une dépense."));
    const profil = h("select", { disabled: !!depense }, profils.map((p) => h("option", { value: p.id, selected: depense && depense.profil_id === p.id }, p.nom)));
    const objet = h("input", { required: true, value: depense ? depense.objet : "", placeholder: "Ex. : impression de 500 affiches" });
    const montant = h("input", { type: "number", min: 1, step: 1, required: true, value: depense ? depense.montant : "" });
    const details = h("textarea", { placeholder: "Pourquoi, pour quand, fournisseur, devis…" });
    details.value = depense ? depense.details : "";
    const bouton = h("button", { class: "btn", type: "submit" }, depense ? "Enregistrer" : "Envoyer au CEO");
    const form = h("form", { class: "carte pile" },
      h("div", { class: "formulaire" },
        h("label", { class: "champ" }, h("span", {}, "Profil"), profil),
        h("label", { class: "champ" }, h("span", {}, "Montant (FCFA) *"), montant)),
      h("label", { class: "champ" }, h("span", {}, "Objet *"), objet),
      h("label", { class: "champ" }, h("span", {}, "Détails"), details),
      h("div", { class: "actions" }, bouton, h("a", { class: "btn btn-second", href: "#/depenses" }, "Annuler")));
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const n = Math.round(Number(montant.value));
      if (!(n > 0)) return UI.echec("Le montant doit être un nombre positif de francs.");
      const valeurs = { objet: objet.value.trim(), montant: n, details: details.value.trim() };
      const d = await UI.agir(bouton, () => depense
        ? Supabase.modifier("rh_depenses", "id=eq." + depense.id, valeurs)
        : Supabase.ajouter("rh_depenses", { ...valeurs, profil_id: profil.value }),
        depense ? "Demande modifiée." : "Demande envoyée au CEO.");
      location.hash = "#/depenses/" + (d ? d.id : depense.id);
    });
    UI.vider(zone, form);
  }

  async function fiche(zone, id) {
    const [d] = await Supabase.lire("rh_depenses?select=*,profil:rh_profils(nom)&id=eq." + encodeURIComponent(id));
    if (!zone.isConnected) return;
    if (!d) return UI.vider(zone, UI.vide("Dépense introuvable."));
    App.titre(numero(d));
    const recharger = () => App.rafraichir().then(() => fiche(zone, id));
    const actions = [];
    const demandeur = d.demandeur_id === App.moi().id;
    if (demandeur && d.statut === "demandee") {
      actions.push(h("button", { class: "btn btn-second", onclick: () => formulaire(zone, d) }, UI.icone("crayon", "ic-sm"), "Modifier"));
      actions.push(h("button", { class: "btn btn-danger", onclick: async (ev) => {
        if (!await UI.confirmer("Annuler cette demande ?", { danger: true, valider: "Annuler la demande" })) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_annuler_depense", { depense: d.id }), "Demande annulée.");
        recharger();
      } }, "Annuler la demande"));
    }
    if (App.estCeo() && d.statut === "demandee") {
      actions.push(h("button", { class: "btn btn-vert", onclick: async (ev) => {
        if (!await UI.confirmer("Approuver « " + d.objet + " » pour " + UI.fcfa(d.montant) + " ?", { valider: "Approuver" })) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_decider_depense", { depense: d.id, approuver: true, motif: "" }), "Dépense approuvée.");
        recharger();
      } }, UI.icone("check", "ic-sm"), "Approuver"));
      actions.push(h("button", { class: "btn btn-danger", onclick: async (ev) => {
        const motif = await UI.motif("Refuser la dépense", "Pourquoi ?");
        if (motif === null) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_decider_depense", { depense: d.id, approuver: false, motif }), "Dépense refusée.");
        recharger();
      } }, "Refuser"));
    }
    if (App.peutDecaisser() && d.statut === "approuvee") {
      actions.push(h("button", { class: "btn btn-orange", onclick: async (ev) => {
        const v = await UI.formulaire({ titre: "Décaisser " + UI.fcfa(d.montant), valider: "Confirmer le décaissement", champs: [
          { nom: "mode", libelle: "Mode", type: "select", valeur: "especes", options: Object.entries(MODES).map(([valeur, libelle]) => ({ valeur, libelle })) },
          { nom: "reference", libelle: "Référence (n° de transaction, de chèque…)" }] });
        if (!v) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_decaisser_depense", { depense: d.id, mode: v.mode, reference: v.reference }), "Décaissement enregistré.");
        recharger();
      } }, UI.icone("argent", "ic-sm"), "Décaisser"));
    }
    const ligne = (libelle, valeur) => h("div", {}, h("div", { class: "doux" }, libelle), h("b", {}, valeur));
    UI.vider(zone, h("div", { class: "carte pile" },
      h("div", { class: "ligne" }, h("h2", { class: "etire", style: { marginBottom: 0 } }, d.objet), etiquette(d.statut)),
      h("div", { style: { fontSize: "24px", fontWeight: 700, color: "var(--bleu-900)" } }, UI.fcfa(d.montant)),
      h("div", { class: "formulaire petit" },
        ligne("Profil", (d.profil && d.profil.nom) || "—"),
        ligne("Demandée par", nom(d.demandeur_id) + " le " + UI.dateHeure(d.cree_le)),
        d.decision_le ? ligne(d.statut === "refusee" ? "Refusée par" : "Approuvée par", nom(d.decision_par) + " le " + UI.dateHeure(d.decision_le)) : null,
        d.decaisse_le ? ligne("Décaissée par", nom(d.decaisse_par) + " le " + UI.dateHeure(d.decaisse_le)) : null,
        d.mode_decaissement ? ligne("Mode", MODES[d.mode_decaissement] + (d.reference ? " · " + d.reference : "")) : null),
      d.details ? h("div", { class: "pre" }, d.details) : null,
      d.motif_decision ? h("div", { class: d.statut === "refusee" ? "erreur" : "info" }, "CEO : " + d.motif_decision) : null,
      actions.length ? h("div", { class: "actions" }, actions) : null));
  }

  return { titre: "Dépenses", afficher };
})();
