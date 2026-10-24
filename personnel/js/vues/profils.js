/* =========================================================
   Profils — les équipes de BIZZOO (Marketing, Logistique…),
   chacune avec son responsable. Le responsable est choisi
   parmi les membres en poste du profil : la base l'exige.
   ========================================================= */
const VueProfils = (() => {
  const { h } = UI;
  const RUBRIQUES = [["commandes", "Commandes et ventes (volumes)"], ["livraisons", "Livraisons et livreurs"], ["sav", "Réclamations et avis"], ["suivi", "Suivi des commandes (statuts, incidents, clôture)"]];

  async function afficher(zone, morceaux) {
    UI.vider(zone, UI.chargement());
    const [profils, employes] = await Promise.all([
      Supabase.lire("rh_profils?select=*&order=nom"),
      Supabase.lire("rh_employes?select=id,nom,prenoms,poste,profil_id,etat&etat=eq.actif&order=nom"),
    ]);
    if (!zone.isConnected) return;
    if (morceaux[0]) {
      const p = profils.find((x) => x.id === morceaux[0]);
      return p ? fiche(zone, p, employes) : UI.vider(zone, UI.vide("Profil introuvable."));
    }
    const membres = (p) => employes.filter((e) => e.profil_id === p.id);
    const nom = (id) => UI.nomComplet(employes.find((e) => e.id === id));
    UI.vider(zone,
      h("div", { class: "titre-section" }, h("h2", {}, "Profils"),
        h("button", { class: "btn btn-petit", onclick: (ev) => editer(ev.currentTarget) }, UI.icone("plus", "ic-sm"), "Nouveau profil")),
      h("p", { class: "doux petit" }, "Chaque employé appartient à un profil. Le responsable du profil accepte les missions, publie les rapports d'activité et demande les dépenses."),
      profils.length ? h("div", { class: "liste" }, profils.map((p) =>
        h("a", { class: "element", href: "#/profils/" + p.id },
          h("div", { class: "avatar", style: { background: "var(--orange-clair)", color: "var(--orange-fonce)" } }, UI.icone("equipe", "ic-sm")),
          h("div", { class: "etire" },
            h("div", { class: "gras" }, p.nom),
            h("div", { class: "petit doux" }, membres(p).length + " membre(s) · Responsable : " +
              (p.responsable_id ? nom(p.responsable_id) : "aucun"))),
          UI.icone("chevron", "ic-sm"))))
        : UI.vide("Aucun profil. Créez le premier (ex. : Administration, Marketing, Logistique, Commercial)."));
  }

  async function editer(bouton, p) {
    const v = await UI.formulaire({ titre: p ? "Modifier le profil" : "Nouveau profil", champs: [
      { nom: "nom", libelle: "Nom", requis: true, valeur: p ? p.nom : "" },
      { nom: "description", libelle: "Description", type: "textarea", valeur: p ? p.description : "" }] });
    if (!v) return;
    const r = await UI.agir(bouton, () => p
      ? Supabase.modifier("rh_profils", "id=eq." + p.id, v)
      : Supabase.ajouter("rh_profils", v), p ? "Profil modifié." : "Profil créé.");
    VueDiscussions.oublier();
    const cible = "#/profils/" + (r ? r.id : p.id);
    if (location.hash === cible) App.naviguer();
    else location.hash = cible;
  }

  function fiche(zone, p, employes) {
    App.titre("Profil " + p.nom);
    const membres = employes.filter((e) => e.profil_id === p.id);
    const choix = h("select", {},
      h("option", { value: "" }, "— Aucun —"),
      membres.map((e) => h("option", { value: e.id, selected: e.id === p.responsable_id }, UI.nomComplet(e))));
    const recharger = () => App.naviguer();
    const cases = {};
    UI.vider(zone,
      h("div", { class: "carte pile" },
        h("h2", { style: { marginBottom: 0 } }, p.nom),
        p.description ? h("p", { class: "doux pre" }, p.description) : null,
        h("label", { class: "champ" }, h("span", {}, "Responsable du profil"), choix,
          h("small", {}, "Pour nommer quelqu'un, rangez-le d'abord dans ce profil (fiche de l'employé).")),
        h("div", { class: "actions" },
          h("button", { class: "btn", onclick: async (ev) => {
            await UI.agir(ev.currentTarget, () => Supabase.modifier("rh_profils", "id=eq." + p.id, { responsable_id: choix.value || null }),
              "Responsable enregistré.");
            App.rafraichir();
            recharger();
          } }, "Enregistrer le responsable"),
          h("button", { class: "btn btn-second", onclick: (ev) => editer(ev.currentTarget, p) }, UI.icone("crayon", "ic-sm"), "Renommer"),
          h("a", { class: "btn btn-second", href: "#/discussions/p:" + p.id }, UI.icone("bulle", "ic-sm"), "Discussion"),
          membres.length ? null : h("button", { class: "btn btn-danger", onclick: async (ev) => {
            if (!await UI.confirmer("Supprimer le profil « " + p.nom + " » ?", { danger: true, valider: "Supprimer" })) return;
            await UI.agir(ev.currentTarget, () => Supabase.supprimer("rh_profils", "id=eq." + p.id), "Profil supprimé.");
            location.hash = "#/profils";
          } }, UI.icone("poubelle", "ic-sm")))),
      h("div", { class: "carte pile" },
        h("h3", {}, "Ce que voit son responsable"),
        h("p", { class: "doux petit" }, "Sans aucun montant : l'argent reste à l'administration, la marge au CEO."),
        RUBRIQUES.map(([v, l]) => h("label", { class: "case" },
          cases[v] = h("input", { type: "checkbox", checked: (p.statistiques || []).includes(v) }), l)),
        h("div", { class: "actions" }, h("button", { class: "btn btn-second", onclick: async (ev) => {
          const statistiques = RUBRIQUES.map(([v]) => v).filter((v) => cases[v].checked);
          await UI.agir(ev.currentTarget, () => Supabase.modifier("rh_profils", "id=eq." + p.id, { statistiques }),
            "Rubriques enregistrées : le responsable les verra à sa prochaine ouverture.");
        } }, "Enregistrer les rubriques"))),
      h("h2", { style: { fontSize: "16px" } }, "Membres (" + membres.length + ")"),
      membres.length ? h("div", { class: "liste" }, membres.map((e) =>
        h("a", { class: "element", href: "#/employes/" + e.id },
          h("div", { class: "avatar" }, UI.initiales(e.nom, e.prenoms)),
          h("div", { class: "etire" }, h("div", { class: "gras" }, UI.nomComplet(e)), h("div", { class: "petit doux" }, e.poste || "")),
          e.id === p.responsable_id ? UI.etiquette("Responsable", "vert") : null)))
        : UI.vide("Aucun membre. Rangez des employés dans ce profil depuis leur fiche."));
  }

  return { titre: "Profils", afficher };
})();
