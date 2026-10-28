/* =========================================================
   Incidents (3.69.0) — tous les incidents des commandes, au même endroit.

   #/incidents : les incidents encore ouverts, quelle que soit leur date,
   et ceux signalés sur la période ; filtres, recherche, « Signaler » par
   le numéro de la commande, « Résoudre ». Ouvert à qui suit les
   commandes : c'est la base (rh_incidents_liste) qui en décide.
   ========================================================= */
const VueIncidents = (() => {
  const { h } = UI;

  const ETATS = [["ouverts", "Ouverts"], ["resolus", "Résolus"], ["", "Tous"]];
  const libelleType = (t) => (VueSuivi.TYPES_INCIDENT.find((x) => x[0] === t) || [t, t])[1];

  async function signaler(numero) {
    const v = await UI.formulaire({ titre: "Signaler un incident", valider: "Signaler", champs: [
      { nom: "commande", libelle: "N° de la commande", requis: true, valeur: numero || "", indice: "BZ-…" },
      { nom: "type", libelle: "Type", type: "select", valeur: "retard",
        options: VueSuivi.TYPES_INCIDENT.map(([valeur, libelle]) => ({ valeur, libelle })) },
      { nom: "description", libelle: "Ce qui s'est passé", type: "textarea", requis: true }],
      verifier: (x) => (!x.commande ? "Indiquez le numéro de la commande." : !x.description ? "Décrivez l'incident." : null) });
    if (!v) return false;
    await UI.agir(null, () => Supabase.rpc("rh_incident_ouvrir", { commande: v.commande, type: v.type,
      description: v.description, boutique: null, livreur: null }), "Incident enregistré.");
    return true;
  }

  async function afficher(zone, morceaux, params) {
    UI.vider(zone, UI.chargement());
    const periode = VueSuivi.periodeDe(params, "30j");
    const r = await Supabase.rpc("rh_incidents_liste", { depuis: periode.depuis, jusqu: periode.jusqu });
    if (!zone.isConnected) return;
    const tous = r.incidents || [];
    const recharger = () => { App.rafraichir(); afficher(zone, morceaux, params); };

    const recherche = h("input", { type: "search", class: "recherche", "aria-label": "Rechercher",
      placeholder: "Rechercher : n° de commande, client, marchand, livreur, description…" });
    const choixEtat = h("select", { "aria-label": "État" }, ETATS.map(([v, l]) => h("option", { value: v, selected: v === (params.etat ?? "ouverts") }, l)));
    const choixType = h("select", { "aria-label": "Type" }, h("option", { value: "" }, "Tous les types"),
      VueSuivi.TYPES_INCIDENT.map(([v, l]) => h("option", { value: v }, l)));
    const resume = h("div", {});
    const compte = h("p", { class: "doux petit" });
    const corps = h("div", {});

    const filtres = () => {
      const q = recherche.value.trim().toLowerCase();
      return tous.filter((i) =>
        (choixEtat.value !== "ouverts" || !i.resolu_le) &&
        (choixEtat.value !== "resolus" || i.resolu_le) &&
        (!choixType.value || i.type === choixType.value) &&
        (!q || [i.numero, i.client, i.boutique, i.livreur, i.description, i.resolution, i.auteur]
          .join(" ").toLowerCase().includes(q)));
    };

    const element = (i) => {
      const lienCommande = h("a", { href: "#/suivi/commande/" + encodeURIComponent(i.commande_id) }, "Commande " + (i.numero || i.commande_id));
      return h("div", { class: "element incident" + (i.resolu_le ? "" : " ouvert") },
        h("div", { class: "etire" },
          h("div", { class: "ligne" }, h("b", {}, libelleType(i.type)),
            i.resolu_le ? UI.etiquette("Résolu", "vert") : UI.etiquette("Ouvert", "rouge"),
            i.cloturee ? UI.etiquette("Commande clôturée", "") : null),
          h("div", { class: "petit" }, i.description),
          h("div", { class: "tres-petit doux" }, VueSuivi.dateSuivi(i.cree_le), i.auteur ? " · " + i.auteur : "", " · ", lienCommande,
            i.client ? " · " + i.client : "", i.boutique ? " · " + i.boutique : "", i.livreur ? " · livreur " + i.livreur : ""),
          i.resolu_le ? h("div", { class: "tres-petit", style: { color: "var(--vert-fonce)" } },
            "Résolu le " + VueSuivi.dateSuivi(i.resolu_le) + (i.resolu_par ? " par " + i.resolu_par : "") + " : " + i.resolution) : null),
        !i.resolu_le ? h("button", { class: "btn btn-second btn-petit", type: "button", onclick: async (ev) => {
          const resolution = await UI.motif("Résoudre l'incident", "Comment a-t-il été résolu ?");
          if (resolution === null) return;
          await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_incident_resoudre", { incident: i.id, resolution }), "Incident résolu.");
          recharger();
        } }, UI.icone("check", "ic-sm"), "Résoudre") : null);
    };

    const dessiner = () => {
      const liste = filtres();
      const ouverts = tous.filter((i) => !i.resolu_le).length;
      const tuile = (valeur, libelle, classe) => h("div", { class: "tuile" + (classe ? " " + classe : "") },
        h("b", { style: { fontSize: "19px" } }, valeur), h("span", {}, libelle));
      UI.vider(resume, h("div", { class: "tuiles compactes" },
        tuile(UI.entier(ouverts), "incident(s) ouvert(s)", ouverts ? "alerte" : ""),
        tuile(UI.entier(tous.filter((i) => i.resolu_le).length), "résolu(s) sur la période")));
      compte.textContent = liste.length + " incident(s) affiché(s)";
      UI.vider(corps, liste.length ? h("div", { class: "liste" }, liste.map(element))
        : UI.vide(choixEtat.value === "ouverts" && !recherche.value && !choixType.value
          ? "Aucun incident ouvert." : "Aucun incident ne correspond."));
    };
    recherche.addEventListener("input", dessiner);
    for (const e of [choixEtat, choixType]) e.addEventListener("change", dessiner);

    UI.vider(zone,
      h("div", { class: "titre-section" }, h("h2", {}, "Incidents"),
        h("button", { class: "btn", type: "button", onclick: async () => { if (await signaler()) recharger(); } },
          UI.icone("plus", "ic-sm"), "Signaler un incident")),
      h("div", { class: "carte compacte" },
        UI.lignePeriode(periode, "#/incidents"),
        h("div", { class: "barre-compacte" }, recherche, choixEtat, choixType),
        h("p", { class: "doux tres-petit" }, "Les incidents ouverts s'affichent toujours, quelle que soit leur date ; les résolus, sur la période choisie.")),
      resume, compte, corps);
    dessiner();
  }

  return { titre: "Incidents", afficher };
})();
