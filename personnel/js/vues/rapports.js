/* =========================================================
   Rapports d'activité — rédigés et publiés par le responsable
   de chaque profil, validés (ou rejetés, avec un commentaire)
   par le CEO. Un brouillon ne se lit que par son auteur ; un
   rapport validé se lit par tous les membres du profil.
   ========================================================= */
const VueRapports = (() => {
  const { h } = UI;

  const STATUTS = {
    brouillon: ["Brouillon", ""],
    publie: ["À valider", "orange"],
    valide: ["Validé", "vert"],
    rejete: ["Rejeté", "rouge"],
  };
  const etiquette = (s) => UI.etiquette(...(STATUTS[s] || [s, ""]));

  let annuaire = [];
  const nom = (id) => UI.nomComplet(annuaire.find((e) => e.id === id));

  async function afficher(zone, morceaux, params) {
    UI.vider(zone, UI.chargement());
    annuaire = await Supabase.rpc("rh_annuaire").catch(() => []);
    if (morceaux[0] === "nouveau") return editeur(zone);
    if (morceaux[0]) return fiche(zone, morceaux[0]);
    return liste(zone, params.filtre || "");
  }

  async function liste(zone, filtre) {
    let chemin = "rh_rapports?select=id,titre,statut,periode_debut,periode_fin,auteur_id,publie_le,profil:rh_profils(nom)&order=periode_fin.desc,cree_le.desc&limit=200";
    if (filtre) chemin += "&statut=eq." + filtre;
    const rapports = await Supabase.lire(chemin);
    if (!zone.isConnected) return;
    UI.vider(zone,
      h("div", { class: "titre-section" }, h("h2", {}, "Rapports d'activité"),
        App.estResponsable() ? h("a", { class: "btn btn-petit", href: "#/rapports/nouveau" }, UI.icone("plus", "ic-sm"), "Nouveau rapport") : null),
      h("div", { class: "filtres" }, [["", "Tous"], ["brouillon", "Brouillons"], ["publie", "À valider"], ["valide", "Validés"], ["rejete", "Rejetés"]]
        .map(([v, l]) => h("button", { class: v === filtre ? "actif" : "", onclick: () => { location.hash = "#/rapports" + (v ? "?filtre=" + v : ""); } }, l))),
      rapports.length ? h("div", { class: "liste" }, rapports.map((r) =>
        h("a", { class: "element", href: "#/rapports/" + r.id },
          h("div", { class: "etire" },
            h("div", { class: "ligne" }, h("span", { class: "gras etire coupe" }, r.titre), etiquette(r.statut)),
            h("div", { class: "petit doux" }, ((r.profil && r.profil.nom) || "") + " · " + UI.date(r.periode_debut) + " → " +
              UI.date(r.periode_fin) + " · " + nom(r.auteur_id))),
          UI.icone("chevron", "ic-sm"))))
        : UI.vide(App.estResponsable() ? "Aucun rapport. Rédigez le premier." : "Aucun rapport à afficher."));
  }

  async function editeur(zone, rapport) {
    App.titre(rapport ? "Modifier le rapport" : "Nouveau rapport");
    const mesProfils = App.moi().responsable_de || [];
    const profils = await Supabase.lire("rh_profils?select=id,nom&id=in.(" + mesProfils.join(",") + ")");
    if (!zone.isConnected) return;
    if (!profils.length) return UI.vider(zone, h("div", { class: "avertissement" }, "Seul le responsable d'un profil publie ses rapports d'activité."));
    const jour = UI.aujourdhui();
    const profil = h("select", { disabled: !!rapport }, profils.map((p) => h("option", { value: p.id, selected: rapport && rapport.profil_id === p.id }, p.nom)));
    const titre = h("input", { required: true, value: rapport ? rapport.titre : "Rapport de " + UI.mois(jour).toLowerCase() });
    const debut = h("input", { type: "date", required: true, value: rapport ? rapport.periode_debut : UI.premierDuMois(jour) });
    const fin = h("input", { type: "date", required: true, value: rapport ? rapport.periode_fin : jour });
    const contenu = h("textarea", { style: { minHeight: "260px" },
      placeholder: "Activités menées, résultats chiffrés, difficultés, besoins, prochaines étapes…" });
    contenu.value = rapport ? rapport.contenu : "";
    const enregistrer = h("button", { class: "btn btn-second", type: "submit", value: "brouillon" }, "Enregistrer le brouillon");
    const publier = h("button", { class: "btn", type: "submit", value: "publier" }, "Publier pour le CEO");
    const form = h("form", { class: "carte pile" },
      rapport && rapport.statut === "rejete" ? h("div", { class: "avertissement" }, "Rejeté par le CEO : " + rapport.commentaire) : null,
      h("div", { class: "formulaire" },
        h("label", { class: "champ" }, h("span", {}, "Profil"), profil),
        h("label", { class: "champ" }, h("span", {}, "Du"), debut),
        h("label", { class: "champ" }, h("span", {}, "Au"), fin)),
      h("label", { class: "champ" }, h("span", {}, "Titre"), titre),
      h("label", { class: "champ" }, h("span", {}, "Contenu du rapport"), contenu),
      h("div", { class: "actions" }, enregistrer, publier));
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      if (fin.value < debut.value) return UI.echec("La fin de la période précède son début.");
      const valeurs = { titre: titre.value.trim(), periode_debut: debut.value, periode_fin: fin.value, contenu: contenu.value };
      const bouton = ev.submitter || enregistrer;
      const r = await UI.agir(bouton, async () => {
        const ligne = rapport
          ? await Supabase.modifier("rh_rapports", "id=eq." + rapport.id, valeurs)
          : await Supabase.ajouter("rh_rapports", { ...valeurs, profil_id: profil.value });
        if (bouton.value === "publier") await Supabase.rpc("rh_publier_rapport", { rapport: ligne.id });
        return ligne;
      }, bouton.value === "publier" ? "Rapport publié : le CEO le validera." : "Brouillon enregistré.");
      App.rafraichir();
      location.hash = "#/rapports/" + r.id;
    });
    UI.vider(zone, form);
  }

  async function fiche(zone, id) {
    const [r] = await Supabase.lire("rh_rapports?select=*,profil:rh_profils(nom)&id=eq." + encodeURIComponent(id));
    if (!zone.isConnected) return;
    if (!r) return UI.vider(zone, UI.vide("Rapport introuvable."));
    App.titre(r.titre);
    const auteur = r.auteur_id === App.moi().id;
    const recharger = () => App.rafraichir().then(() => fiche(zone, id));
    const actions = [];
    if (auteur && ["brouillon", "rejete"].includes(r.statut)) {
      actions.push(h("button", { class: "btn btn-second", onclick: () => editeur(zone, r) }, UI.icone("crayon", "ic-sm"), "Modifier"));
      actions.push(h("button", { class: "btn", onclick: async (ev) => {
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_publier_rapport", { rapport: r.id }), "Rapport publié.");
        recharger();
      } }, "Publier pour le CEO"));
    }
    if (auteur && r.statut === "brouillon") {
      actions.push(h("button", { class: "btn btn-danger", onclick: async (ev) => {
        if (!await UI.confirmer("Supprimer ce brouillon ?", { danger: true, valider: "Supprimer" })) return;
        await UI.agir(ev.currentTarget, () => Supabase.supprimer("rh_rapports", "id=eq." + r.id), "Brouillon supprimé.");
        location.hash = "#/rapports";
      } }, UI.icone("poubelle", "ic-sm")));
    }
    if (App.estCeo() && r.statut === "publie") {
      actions.push(h("button", { class: "btn btn-vert", onclick: async (ev) => {
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_decider_rapport", { rapport: r.id, valider: true, commentaire: "" }), "Rapport validé.");
        recharger();
      } }, UI.icone("check", "ic-sm"), "Valider"));
      actions.push(h("button", { class: "btn btn-danger", onclick: async (ev) => {
        const commentaire = await UI.motif("Rejeter le rapport", "Ce qu'il faut revoir");
        if (commentaire === null) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_decider_rapport", { rapport: r.id, valider: false, commentaire }), "Rapport renvoyé au responsable.");
        recharger();
      } }, "Rejeter"));
    }
    UI.vider(zone,
      h("div", { class: "carte pile" },
        h("div", { class: "ligne" }, h("h2", { class: "etire", style: { marginBottom: 0 } }, r.titre), etiquette(r.statut)),
        h("div", { class: "petit doux" }, "Profil " + ((r.profil && r.profil.nom) || "") + " · du " + UI.date(r.periode_debut) +
          " au " + UI.date(r.periode_fin) + " · par " + nom(r.auteur_id)),
        r.publie_le ? h("div", { class: "tres-petit doux" }, "Publié le " + UI.dateHeure(r.publie_le)) : null,
        r.commentaire ? h("div", { class: r.statut === "valide" ? "info" : "avertissement" }, "CEO : " + r.commentaire) : null,
        h("div", { class: "pre" }, r.contenu || "(vide)"),
        actions.length ? h("div", { class: "actions non-imprime" }, actions,
          h("button", { class: "btn btn-second", onclick: () => window.print() }, UI.icone("imprimer", "ic-sm"))) :
          h("div", { class: "actions non-imprime" }, h("button", { class: "btn btn-second", onclick: () => window.print() }, UI.icone("imprimer", "ic-sm"), "Imprimer"))));
  }

  return { titre: "Rapports", afficher };
})();
