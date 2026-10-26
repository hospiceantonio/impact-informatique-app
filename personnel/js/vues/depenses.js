/* =========================================================
   Dépenses — le circuit d'une demande :

   1. tout employé la demande (motif, montant) ;
   2. le responsable de son profil la valide (ou la refuse, motif) ;
   3. le CEO l'approuve (ou la refuse, motif) ;
   4. l'employé habilité la décaisse : mode et référence. Jamais
      sa propre demande.

   Sans responsable — pas de profil, profil sans responsable, ou
   demandeur responsable lui-même — l'étape 2 saute : la base envoie
   la demande droit au CEO. C'est elle qui tient chaque étape ;
   l'écran ne fait que proposer le bon bouton à la bonne personne.
   ========================================================= */
const VueDepenses = (() => {
  const { h } = UI;

  const STATUTS = {
    demandee: ["En attente du responsable", "orange"],
    validee_responsable: ["En attente du CEO", "orange"],
    approuvee: ["En attente de décaissement", "bleu"],
    decaissee: ["Décaissée", "vert"],
    refusee: ["Refusée", "rouge"],
    annulee: ["Annulée", ""],
  };
  /* Les compartiments de la caisse ; les autres : décaissements d'avant la caisse. */
  const MODES = { especes: "Espèces", mtn: "MTN Mobile Money", moov: "Moov Money", celtiis: "Celtiis Cash", mixte: "Plusieurs compartiments", virement: "Virement", mobile_money: "Mobile Money", cheque: "Chèque" };
  const etiquette = (s) => UI.etiquette(...(STATUTS[s] || [s, ""]));
  const numero = (d) => "D-" + String(d.numero).padStart(4, "0");

  let annuaire = [];
  const nom = (id) => (id ? UI.nomComplet(annuaire.find((e) => e.id === id)) || "—" : "—");

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
    const moi = App.moi().id;
    UI.vider(zone,
      h("div", { class: "titre-section" }, h("h2", {}, "Dépenses"),
        App.ouvert("depenses") ? h("a", { class: "btn btn-petit", href: "#/depenses/nouvelle" }, UI.icone("plus", "ic-sm"), "Demander une dépense") : null),
      h("div", { class: "filtres" }, [["", "Toutes"], ["demandee", "Chez le responsable"], ["validee_responsable", "Chez le CEO"],
        ["approuvee", "À décaisser"], ["decaissee", "Décaissées"], ["refusee", "Refusées"]]
        .map(([v, l]) => h("button", { class: v === filtre ? "actif" : "", onclick: () => { location.hash = "#/depenses" + (v ? "?filtre=" + v : ""); } }, l))),
      !filtre && depenses.length ? h("div", { class: "tuiles" },
        h("div", { class: "tuile" }, h("b", { style: { fontSize: "17px" } }, UI.fcfa(total("demandee"))), h("span", {}, "chez les responsables")),
        h("div", { class: "tuile" }, h("b", { style: { fontSize: "17px" } }, UI.fcfa(total("validee_responsable"))), h("span", {}, "chez le CEO")),
        h("div", { class: "tuile" }, h("b", { style: { fontSize: "17px" } }, UI.fcfa(total("approuvee"))), h("span", {}, "approuvées, à décaisser")),
        h("div", { class: "tuile" }, h("b", { style: { fontSize: "17px" } }, UI.fcfa(total("decaissee"))), h("span", {}, "décaissées"))) : null,
      depenses.length ? h("div", { class: "liste" }, depenses.map((d) =>
        h("a", { class: "element", href: "#/depenses/" + d.id },
          h("div", { class: "etire" },
            h("div", { class: "ligne" }, h("span", { class: "gras etire coupe" }, d.objet), h("b", {}, UI.fcfa(d.montant))),
            h("div", { class: "ligne petit doux" }, h("span", { class: "etire coupe" }, [numero(d),
              d.demandeur_id === moi ? "ma demande" : nom(d.demandeur_id), d.profil && d.profil.nom, UI.date(d.cree_le)]
              .filter(Boolean).join(" · ")), etiquette(d.statut))),
          UI.icone("chevron", "ic-sm"))))
        : UI.vide("Aucune dépense ici."));
  }

  async function formulaire(zone, depense) {
    App.titre(depense ? "Modifier la demande" : "Demande de dépense");
    const objet = h("input", { required: true, maxlength: 200, value: depense ? depense.objet : "", placeholder: "Ex. : impression de 500 affiches" });
    const montant = h("input", { type: "number", min: 1, step: 1, required: true, inputmode: "numeric", value: depense ? depense.montant : "" });
    const details = h("textarea", { placeholder: "Pour quoi faire, pour quand, fournisseur, devis…" });
    details.value = depense ? depense.details : "";
    const bouton = h("button", { class: "btn", type: "submit" }, depense ? "Enregistrer" : "Envoyer la demande");
    const moi = App.moi();
    const form = h("form", { class: "carte pile" },
      h("label", { class: "champ" }, h("span", {}, "Motif *"), objet),
      h("label", { class: "champ" }, h("span", {}, "Montant (FCFA) *"), montant),
      h("label", { class: "champ" }, h("span", {}, "Détails"), details),
      depense ? null : h("p", { class: "doux petit" }, moi.profil && !App.responsableDe(moi.profil_id)
        ? "Votre demande part d'abord chez le responsable du profil « " + moi.profil + " », puis chez le CEO, avant d'être décaissée."
        : "Votre demande part directement chez le CEO" + (moi.profil ? " : vous êtes le responsable de votre profil." : " : vous n'êtes rangé dans aucun profil.")),
      h("div", { class: "actions" }, bouton, h("a", { class: "btn btn-second", href: depense ? "#/depenses/" + depense.id : "#/depenses" }, "Annuler")));
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const n = Math.round(Number(montant.value));
      if (!(n > 0)) return UI.echec("Le montant doit être un nombre positif de francs.");
      if (!objet.value.trim()) return UI.echec("Le motif est obligatoire.");
      const valeurs = { objet: objet.value.trim(), montant: n, details: details.value.trim() };
      const d = await UI.agir(bouton, () => depense
        ? Supabase.modifier("rh_depenses", "id=eq." + depense.id, valeurs)
        : Supabase.ajouter("rh_depenses", valeurs));
      const fiche = d || depense;
      UI.succes(depense ? "Demande modifiée." : fiche && fiche.statut === "validee_responsable"
        ? "Demande envoyée au CEO." : "Demande envoyée à votre responsable.");
      App.rafraichir();
      location.hash = "#/depenses/" + fiche.id;
    });
    UI.vider(zone, form);
  }

  /** Les quatre étapes, cochées au fur et à mesure. */
  function etapes(d) {
    const refusResp = d.statut === "refusee" && d.responsable_le && !d.decision_le;
    const refusCeo = d.statut === "refusee" && d.decision_le;
    const sauteResp = !d.responsable_le && d.statut !== "demandee" && !refusResp;
    const liste = [
      ["Demandée", true, "par " + nom(d.demandeur_id) + " le " + UI.dateHeure(d.cree_le)],
      ["Validée par le responsable", refusResp ? "refus" : !!d.responsable_le || sauteResp,
        d.responsable_le ? (refusResp ? "Refusée par " : "par ") + nom(d.responsable_par) + " le " + UI.dateHeure(d.responsable_le)
          : sauteResp ? "sans objet : pas de responsable au-dessus du demandeur" : "en attente"],
      ["Approuvée par le CEO", refusCeo ? "refus" : !!d.decision_le && !refusCeo,
        d.decision_le ? (refusCeo ? "Refusée par " : "par ") + nom(d.decision_par) + " le " + UI.dateHeure(d.decision_le)
          : refusResp ? "—" : "en attente"],
      ["Décaissée", !!d.decaisse_le, d.decaisse_le ? "par " + nom(d.decaisse_par) + " le " + UI.dateHeure(d.decaisse_le) +
        (d.mode_decaissement ? " · " + MODES[d.mode_decaissement] + (d.reference ? " · réf. " + d.reference : "") : "")
        : d.statut === "refusee" || d.statut === "annulee" ? "—" : "en attente"],
    ];
    return h("ol", { class: "etapes-depense" }, liste.map(([titre, fait, texte]) =>
      h("li", { class: fait === "refus" ? "refus" : fait ? "fait" : "" },
        h("div", { class: "gras" }, titre), h("div", { class: "petit doux" }, texte))));
  }

  async function fiche(zone, id) {
    const [d] = await Supabase.lire("rh_depenses?select=*,profil:rh_profils(nom)&id=eq." + encodeURIComponent(id));
    if (!zone.isConnected) return;
    if (!d) return UI.vider(zone, UI.vide("Dépense introuvable."));
    App.titre(numero(d));
    const recharger = () => App.rafraichir().then(() => fiche(zone, id));
    const actions = [];
    const moi = App.moi().id;
    const demandeur = d.demandeur_id === moi;
    const modifiable = d.statut === "demandee" || (d.statut === "validee_responsable" && !d.responsable_par);
    const refuser = (titre, rpc, cle) => async (ev) => {
      const motif = await UI.motif(titre, "Pourquoi ?");
      if (motif === null) return;
      await UI.agir(ev.currentTarget, () => Supabase.rpc(rpc, { depense: d.id, [cle]: false, motif }), "Dépense refusée.");
      recharger();
    };

    if (demandeur && modifiable) {
      actions.push(h("button", { class: "btn btn-second", onclick: () => formulaire(zone, d) }, UI.icone("crayon", "ic-sm"), "Modifier"));
    }
    if (demandeur && ["demandee", "validee_responsable"].includes(d.statut)) {
      actions.push(h("button", { class: "btn btn-danger", onclick: async (ev) => {
        if (!await UI.confirmer("Annuler cette demande ?", { danger: true, valider: "Annuler la demande" })) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_annuler_depense", { depense: d.id }), "Demande annulée.");
        recharger();
      } }, "Annuler la demande"));
    }
    if (d.statut === "demandee" && d.profil_id && App.responsableDe(d.profil_id)) {
      actions.push(h("button", { class: "btn btn-vert", onclick: async (ev) => {
        if (!await UI.confirmer("Valider « " + d.objet + " » pour " + UI.fcfa(d.montant) + " ? Elle part chez le CEO.", { valider: "Valider" })) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_valider_depense", { depense: d.id, valider: true, motif: "" }), "Demande validée : elle part chez le CEO.");
        recharger();
      } }, UI.icone("check", "ic-sm"), "Valider"));
      actions.push(h("button", { class: "btn btn-danger", onclick: refuser("Refuser la dépense", "rh_valider_depense", "valider") }, "Refuser"));
    }
    if (App.estCeo() && d.statut === "validee_responsable") {
      actions.push(h("button", { class: "btn btn-vert", onclick: async (ev) => {
        if (!await UI.confirmer("Approuver « " + d.objet + " » pour " + UI.fcfa(d.montant) + " ?", { valider: "Approuver" })) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_decider_depense", { depense: d.id, approuver: true, motif: "" }), "Dépense approuvée : elle attend le décaissement.");
        recharger();
      } }, UI.icone("check", "ic-sm"), "Approuver"));
      actions.push(h("button", { class: "btn btn-danger", onclick: refuser("Refuser la dépense", "rh_decider_depense", "approuver") }, "Refuser"));
    }
    if (App.peutDecaisser() && d.statut === "approuvee" && !demandeur) {
      actions.push(h("button", { class: "btn btn-orange", onclick: async (ev) => {
        /* L'argent sort de la caisse : espèces seules, ou réparti avec le Mobile Money. */
        const v = await VueCaisse.repartir({ titre: "Décaisser " + UI.fcfa(d.montant), montant: Number(d.montant), valider: "Confirmer le décaissement" });
        if (!v) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_decaisser", { depense: d.id, repartition: v.repartition, reference: v.reference }), "Décaissement enregistré : il sort de la caisse.");
        recharger();
      } }, UI.icone("argent", "ic-sm"), "Décaisser"));
    }

    UI.vider(zone, h("div", { class: "carte pile" },
      h("div", { class: "ligne" }, h("h2", { class: "etire", style: { marginBottom: 0 } }, d.objet), etiquette(d.statut)),
      h("div", { style: { fontSize: "24px", fontWeight: 700, color: "var(--bleu-900)" } }, UI.fcfa(d.montant)),
      h("div", { class: "petit doux" }, [numero(d), d.profil && "Profil " + d.profil.nom].filter(Boolean).join(" · ")),
      d.details ? h("div", { class: "pre" }, d.details) : null,
      etapes(d),
      d.motif_responsable ? h("div", { class: d.statut === "refusee" && !d.decision_le ? "erreur" : "info" }, "Responsable : " + d.motif_responsable) : null,
      d.motif_decision ? h("div", { class: d.statut === "refusee" ? "erreur" : "info" }, "CEO : " + d.motif_decision) : null,
      App.peutDecaisser() && d.statut === "approuvee" && demandeur
        ? h("p", { class: "avertissement" }, "C'est votre propre demande : un autre employé habilité doit la décaisser.") : null,
      actions.length ? h("div", { class: "actions" }, actions) : null));
  }

  return { titre: "Dépenses", afficher };
})();
