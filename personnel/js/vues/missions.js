/* =========================================================
   Missions — créées par l'administration pour un profil.

   Le circuit : proposée → acceptée (ou refusée, avec motif) par
   le responsable du profil → rapport remis avant l'échéance →
   clôturée par l'administration, ou renvoyée « à reprendre ».
   Chaque passage est une fonction de la base qui vérifie qui
   appelle : l'écran ne fait que proposer les bons boutons.
   ========================================================= */
const VueMissions = (() => {
  const { h } = UI;

  const STATUTS = {
    proposee: ["À accepter", "orange"],
    acceptee: ["En cours", "bleu"],
    a_reprendre: ["À reprendre", "orange"],
    rapport_remis: ["Rapport remis", "bleu"],
    cloturee: ["Clôturée", "vert"],
    refusee: ["Refusée", "rouge"],
  };
  const FILTRES = [
    ["", "Toutes"], ["proposee", "À accepter"], ["en_cours", "En cours"],
    ["rapport_remis", "Rapport remis"], ["cloturee", "Clôturées"], ["refusee", "Refusées"],
  ];

  const etiquette = (s) => UI.etiquette(...(STATUTS[s] || [s, ""]));
  const numero = (m) => "M-" + String(m.numero).padStart(4, "0");
  const enRetard = (m) => {
    const jour = UI.aujourdhui();
    if (["acceptee", "a_reprendre", "proposee"].includes(m.statut)) return m.echeance < jour;
    if (m.rapport_le) return m.rapport_le.slice(0, 10) > m.echeance;
    return false;
  };

  let annuaire = [];
  const nom = (id) => UI.nomComplet(annuaire.find((e) => e.id === id));

  async function afficher(zone, morceaux, params) {
    UI.vider(zone, UI.chargement());
    annuaire = await Supabase.rpc("rh_annuaire").catch(() => []);
    if (morceaux[0] === "nouvelle") return formulaire(zone, null, params);
    if (morceaux[0]) return fiche(zone, morceaux[0]);
    return liste(zone, params.filtre || "");
  }

  async function liste(zone, filtre) {
    let chemin = "rh_missions?select=*,profil:rh_profils(nom)&order=cree_le.desc&limit=200";
    if (filtre === "en_cours") chemin += "&statut=in.(acceptee,a_reprendre)";
    else if (filtre) chemin += "&statut=eq." + filtre;
    const missions = await Supabase.lire(chemin);
    if (!zone.isConnected) return;
    UI.vider(zone,
      h("div", { class: "titre-section" }, h("h2", {}, "Missions"),
        App.estAdmin() ? h("a", { class: "btn btn-petit", href: "#/missions/nouvelle" }, UI.icone("plus", "ic-sm"), "Nouvelle mission") : null),
      h("div", { class: "filtres" }, FILTRES.map(([v, l]) =>
        h("button", { class: v === filtre ? "actif" : "", onclick: () => { location.hash = "#/missions" + (v ? "?filtre=" + v : ""); } }, l))),
      missions.length ? h("div", { class: "liste" }, missions.map((m) =>
        h("a", { class: "element", href: "#/missions/" + m.id },
          h("div", { class: "etire" },
            h("div", { class: "ligne" }, h("span", { class: "gras etire coupe" }, m.titre), etiquette(m.statut)),
            h("div", { class: "petit doux" }, numero(m) + " · " + ((m.profil && m.profil.nom) || "") +
              " · rapport attendu le " + UI.date(m.echeance)),
            enRetard(m) ? h("div", { class: "tres-petit", style: { color: "var(--rouge-fonce)" } }, "En retard") : null),
          UI.icone("chevron", "ic-sm"))))
        : UI.vide("Aucune mission ici."));
  }

  /* « prerempli » : titre et description proposés par un autre écran (la
     fiche qualité d'une boutique) ; l'administration les relit avant de créer. */
  async function formulaire(zone, mission, prerempli) {
    const propose = (!mission && prerempli) || {};
    App.titre(mission ? "Modifier la mission" : "Nouvelle mission");
    const profils = await Supabase.lire("rh_profils?select=id,nom,responsable_id&order=nom");
    if (!zone.isConnected) return;
    if (!profils.length) {
      UI.vider(zone, h("div", { class: "avertissement" }, "Créez d'abord un profil (menu Profils)."));
      return;
    }
    const titre = h("input", { required: true, value: mission ? mission.titre : (propose.titre || "") });
    const description = h("textarea", {});
    description.value = mission ? mission.description : (propose.description || "");
    const profil = h("select", { disabled: !!mission }, profils.map((p) =>
      h("option", { value: p.id, selected: mission && mission.profil_id === p.id },
        p.nom + (p.responsable_id ? "" : " (sans responsable)"))));
    const debut = h("input", { type: "date", required: true, value: mission ? mission.date_debut : UI.aujourdhui() });
    const echeance = h("input", { type: "date", required: true, value: mission ? mission.echeance : "" });
    const bouton = h("button", { class: "btn", type: "submit" }, mission ? "Enregistrer" : "Créer la mission");
    const form = h("form", { class: "carte pile" },
      h("label", { class: "champ" }, h("span", {}, "Titre *"), titre),
      h("label", { class: "champ" }, h("span", {}, "Description et objectifs"), description),
      h("div", { class: "formulaire" },
        h("label", { class: "champ" }, h("span", {}, "Profil chargé de la mission *"), profil),
        h("label", { class: "champ" }, h("span", {}, "Début *"), debut),
        h("label", { class: "champ" }, h("span", {}, "Rapport attendu au plus tard le *"), echeance)),
      h("p", { class: "doux petit" }, "Le responsable du profil devra accepter la mission, puis rendre son rapport avant cette date."),
      h("div", { class: "actions" }, bouton, h("a", { class: "btn btn-second", href: mission ? "#/missions/" + mission.id : "#/missions" }, "Annuler")));
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      if (echeance.value < debut.value) return UI.echec("L'échéance ne peut pas précéder le début.");
      const valeurs = { titre: titre.value.trim(), description: description.value.trim(),
                        date_debut: debut.value, echeance: echeance.value };
      const m = await UI.agir(bouton, () => mission
        ? Supabase.modifier("rh_missions", "id=eq." + mission.id, valeurs)
        : Supabase.ajouter("rh_missions", { ...valeurs, profil_id: profil.value }),
        mission ? "Mission modifiée." : "Mission créée et envoyée au responsable du profil.");
      App.rafraichir();
      location.hash = "#/missions/" + (m ? m.id : mission.id);
    });
    UI.vider(zone, form);
  }

  async function fiche(zone, id) {
    const [m] = await Supabase.lire("rh_missions?select=*,profil:rh_profils(nom,responsable_id)&id=eq." + encodeURIComponent(id));
    if (!zone.isConnected) return;
    if (!m) return UI.vider(zone, UI.vide("Mission introuvable."));
    App.titre(numero(m));
    const responsable = App.responsableDe(m.profil_id);
    const admin = App.estAdmin();
    const recharger = () => App.rafraichir().then(() => fiche(zone, id));

    const actions = [];
    if (responsable && m.statut === "proposee") {
      actions.push(h("button", { class: "btn btn-vert", onclick: async (ev) => {
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_repondre_mission", { mission: m.id, accepter: true }), "Mission acceptée.");
        recharger();
      } }, UI.icone("check", "ic-sm"), "Accepter"));
      actions.push(h("button", { class: "btn btn-danger", onclick: async (ev) => {
        const motif = await UI.motif("Refuser la mission", "Pourquoi la refusez-vous ?");
        if (motif === null) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_repondre_mission", { mission: m.id, accepter: false, motif }), "Mission refusée.");
        recharger();
      } }, "Refuser"));
    }
    if (admin && m.statut === "rapport_remis") {
      actions.push(h("button", { class: "btn btn-vert", onclick: async (ev) => {
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_cloturer_mission", { mission: m.id, valider: true, commentaire: "" }), "Mission clôturée.");
        recharger();
      } }, UI.icone("check", "ic-sm"), "Clôturer"));
      actions.push(h("button", { class: "btn btn-second", onclick: async (ev) => {
        const commentaire = await UI.motif("Renvoyer le rapport", "Ce qu'il faut reprendre");
        if (commentaire === null) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_cloturer_mission", { mission: m.id, valider: false, commentaire }), "Rapport renvoyé au responsable.");
        recharger();
      } }, "À reprendre"));
    }
    if (admin && !["refusee", "cloturee"].includes(m.statut)) {
      actions.push(h("button", { class: "btn btn-second", onclick: () => formulaire(zone, m) }, UI.icone("crayon", "ic-sm"), "Modifier"));
    }
    if (admin && ["proposee", "refusee"].includes(m.statut)) {
      actions.push(h("button", { class: "btn btn-danger", onclick: async (ev) => {
        if (!await UI.confirmer("Supprimer définitivement cette mission ?", { danger: true, valider: "Supprimer" })) return;
        await UI.agir(ev.currentTarget, () => Supabase.supprimer("rh_missions", "id=eq." + m.id), "Mission supprimée.");
        App.rafraichir();
        location.hash = "#/missions";
      } }, UI.icone("poubelle", "ic-sm"), "Supprimer"));
    }

    let zoneRapport = null;
    if (responsable && ["acceptee", "a_reprendre"].includes(m.statut)) {
      const texte = h("textarea", { style: { minHeight: "180px" }, placeholder: "Ce qui a été fait, les résultats, les difficultés, les chiffres…" });
      texte.value = m.rapport || "";
      const bouton = h("button", { class: "btn", type: "submit" }, "Rendre le rapport");
      zoneRapport = h("form", { class: "carte pile" }, h("h2", {}, "Rapport de mission"),
        m.statut === "a_reprendre" ? h("div", { class: "avertissement" }, "À reprendre : " + m.commentaire) : null,
        h("label", { class: "champ" }, texte), h("div", { class: "actions" }, bouton));
      zoneRapport.addEventListener("submit", async (ev) => {
        ev.preventDefault();
        await UI.agir(bouton, () => Supabase.rpc("rh_rendre_rapport_mission", { mission: m.id, texte: texte.value }), "Rapport remis.");
        recharger();
      });
    }

    UI.vider(zone,
      h("div", { class: "carte pile" },
        h("div", { class: "ligne" }, h("h2", { class: "etire", style: { marginBottom: 0 } }, m.titre), etiquette(m.statut)),
        enRetard(m) ? h("div", { class: "erreur" }, "En retard : le rapport était attendu le " + UI.date(m.echeance) + ".") : null,
        h("div", { class: "formulaire petit" },
          h("div", {}, h("div", { class: "doux" }, "Profil"), h("b", {}, (m.profil && m.profil.nom) || "—")),
          h("div", {}, h("div", { class: "doux" }, "Responsable"), h("b", {}, m.profil && m.profil.responsable_id ? nom(m.profil.responsable_id) : "Aucun")),
          h("div", {}, h("div", { class: "doux" }, "Période"), h("b", {}, UI.date(m.date_debut) + " → " + UI.date(m.echeance))),
          h("div", {}, h("div", { class: "doux" }, "Créée par"), h("b", {}, nom(m.cree_par)), h("div", { class: "tres-petit doux" }, UI.dateHeure(m.cree_le)))),
        m.description ? h("div", { class: "pre" }, m.description) : null,
        m.motif_refus ? h("div", { class: "erreur" }, "Refusée : " + m.motif_refus) : null,
        actions.length ? h("div", { class: "actions" }, actions) : null),
      m.rapport && !zoneRapport ? h("div", { class: "carte pile" },
        h("h2", {}, "Rapport de mission"),
        h("div", { class: "petit doux" }, "Remis par " + nom(m.rapport_par) + " le " + UI.dateHeure(m.rapport_le)),
        h("div", { class: "pre" }, m.rapport),
        m.commentaire ? h("div", { class: m.statut === "cloturee" ? "info" : "avertissement" }, "Administration : " + m.commentaire) : null)
        : null,
      zoneRapport);
  }

  return { titre: "Missions", afficher };
})();
