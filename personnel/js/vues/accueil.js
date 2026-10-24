/* =========================================================
   Accueil — ce qui attend la personne connectée, selon son rang.
   Chaque tuile mène à l'écran où l'on agit.
   ========================================================= */
const VueAccueil = (() => {
  const { h } = UI;

  function tuile(nombre, texte, lien, alerte) {
    return h("a", { class: "tuile" + (alerte && nombre > 0 ? " alerte" : ""), href: lien },
      h("b", {}, UI.entier(nombre || 0)), h("span", {}, texte));
  }

  async function afficher(zone) {
    await App.rafraichir();
    const moi = App.moi();
    const c = App.compteurs();
    const heure = new Date().getHours();
    const salut = heure < 12 ? "Bonjour" : heure < 18 ? "Bon après-midi" : "Bonsoir";
    const rang = moi.ceo ? "CEO" : moi.administration ? "Administration" : moi.poste || "";

    const aFaire = [];
    if (App.estCeo()) {
      aFaire.push(tuile(c.employes_a_valider, "employé(s) à valider", "#/employes?filtre=en_attente", true));
      aFaire.push(tuile(c.rapports_a_valider, "rapport(s) d'activité à valider", "#/rapports?filtre=publie", true));
      aFaire.push(tuile(c.depenses_a_approuver, "dépense(s) à approuver", "#/depenses?filtre=validee_responsable", true));
      aFaire.push(tuile(c.fiches_a_valider, "fiche(s) de paie à valider", "#/paie", true));
      if (c.baremes_a_valider) aFaire.push(tuile(c.baremes_a_valider, "barème(s) de paie à valider", "#/paie/baremes", true));
    }
    if (App.estResponsable()) {
      aFaire.push(tuile(c.missions_a_repondre, "mission(s) à accepter", "#/missions?filtre=proposee", true));
      aFaire.push(tuile(c.depenses_a_valider, "dépense(s) de votre équipe à valider", "#/depenses?filtre=demandee", true));
    }
    if (App.estAdmin()) {
      aFaire.push(tuile(c.missions_a_cloturer, "rapport(s) de mission à lire", "#/missions?filtre=rapport_remis", true));
    }
    if (App.peutDecaisser()) {
      aFaire.push(tuile(c.depenses_a_decaisser, "dépense(s) à décaisser", "#/depenses?filtre=approuvee", true));
      aFaire.push(tuile(c.fiches_a_payer, "salaire(s) à payer", "#/paie", true));
    }
    aFaire.push(tuile(c.messages_non_lus, "message(s) non lu(s)", "#/discussions", true));
    aFaire.push(tuile(c.missions_en_cours, "mission(s) en cours", "#/missions?filtre=en_cours"));
    if (c.missions_en_retard) aFaire.push(tuile(c.missions_en_retard, "mission(s) en retard", "#/missions?filtre=en_cours", true));

    const raccourcis = [];
    if (App.estAdmin()) {
      raccourcis.push(h("a", { class: "btn btn-second", href: "#/employes/nouveau" }, UI.icone("plus", "ic-sm"), "Nouvel employé"));
      raccourcis.push(h("a", { class: "btn btn-second", href: "#/missions/nouvelle" }, UI.icone("plus", "ic-sm"), "Nouvelle mission"));
    }
    if (App.estResponsable()) {
      raccourcis.push(h("a", { class: "btn btn-second", href: "#/rapports/nouveau" }, UI.icone("plus", "ic-sm"), "Rapport d'activité"));
    }
    /* Tout employé demande une dépense, si Paramètres lui ouvre le menu. */
    if (App.ouvert("depenses")) {
      raccourcis.push(h("a", { class: "btn btn-second", href: "#/depenses/nouvelle" }, UI.icone("plus", "ic-sm"), "Demande de dépense"));
    }
    raccourcis.push(h("a", { class: "btn btn-second", href: "#/mails/ecrire" }, UI.icone("mail", "ic-sm"), "Écrire un mail"));

    UI.vider(zone,
      h("div", {},
        h("h2", { style: { fontSize: "21px" } }, salut + ", " + (moi.prenoms || moi.nom)),
        h("p", { class: "doux" }, [rang, moi.profil ? "Profil " + moi.profil : ""].filter(Boolean).join(" · "))),
      h("div", { class: "tuiles" }, aFaire),
      h("div", { class: "carte" }, h("h2", {}, "Raccourcis"), h("div", { class: "actions" }, raccourcis)));
  }

  return { titre: "Accueil", afficher };
})();
