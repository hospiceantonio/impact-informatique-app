/* =========================================================
   Bilans — le bilan du matin, et l'historique.

   #/bilans : les 30 derniers bilans, le plus récent d'abord.

   Chaque matin à 7 h (heure du Bénin), la base prépare un bilan
   (rh_preparer_bilan) : ce qui attend une décision (paiements en
   litige, MoMoPay pas vérifiés, demandes d'argent en retard, réglages
   pas approuvés, réclamations, ruptures), les commandes de la veille
   et la file ; le lundi, la semaine écoulée à côté de la précédente.
   Les montants : l'administration, le CEO et le superadministrateur
   seulement ; un responsable de profil lit les nombres. La base en
   décide (rh_bilans_lire). L'Accueil en montre la carte du jour.
   ========================================================= */
const VueBilans = (() => {
  const { h } = UI;
  const n = (v) => UI.entier(v || 0);

  /** « +8 % », « −12 % », ou rien quand la semaine d'avant est à zéro. */
  function evolution(a, b) {
    if (!b) return "";
    const p = Math.round(((a - b) * 100) / b);
    return " (" + (p > 0 ? "+" : p < 0 ? "−" : "") + Math.abs(p) + " %)";
  }

  function tuile(valeur, libelle, lien, alerte) {
    return h(lien ? "a" : "div", { class: "tuile" + (alerte && Number(valeur) > 0 ? " alerte" : ""), href: lien || undefined },
      h("b", {}, typeof valeur === "number" ? n(valeur) : valeur), h("span", {}, libelle));
  }

  /** La carte d'un bilan. « montants » : null quand on n'y a pas droit. */
  function carte(b, { titre } = {}) {
    const c = b.chiffres || {};
    const m = b.montants || null;
    const v = c.veille || {};
    const f = c.file || {};
    const s = c.semaine;
    const ms = m || {};
    return h("div", { class: "carte pile" },
      h("div", { class: "ligne" }, h("h2", { class: "etire", style: { marginBottom: 0 } }, titre || ("Bilan du " + UI.dateLongue(b.jour))),
        b.hebdo ? UI.etiquette("Bilan de la semaine", "bleu") : null),
      h("p", { class: "tres-petit doux" }, "Préparé " + UI.quand(b.cree_le) + "."),
      h("h3", {}, "Ce qui attend"),
      h("div", { class: "tuiles compactes" },
        tuile(c.paiements_litige, "paiements en litige", "#/controles/paiements", true),
        tuile(c.momopay_non_verifies, "MoMoPay pas vérifiés" + (m ? " · " + UI.fcfa(ms.momopay_non_verifies) : ""), "#/controles/encaissements", true),
        tuile(c.dettes_retard, "demandes d'argent en retard" + (m ? " · " + UI.fcfa(ms.dettes_retard) : ""), "#/controles/dettes", true),
        tuile(c.remboursements_retard, "remboursements en retard", "#/controles/remboursements", true),
        tuile(c.reglages_non_approuves, "réglages pas approuvés", "#/controles/reglages", true),
        tuile(c.reclamations_souffrance, "réclamations en souffrance", "#/qualite/sav", true),
        tuile(c.ruptures_vedettes, "ruptures de produits qui se vendent", "#/qualite/catalogue", true)),
      h("h3", {}, "Hier"),
      h("div", { class: "tuiles compactes" },
        tuile(v.creees, "commandes passées"),
        tuile(v.payees, "commandes payées"),
        tuile(v.jamais_payees, "jamais payées", null, true),
        tuile(v.annulees, "annulées"),
        m ? tuile(UI.fcfa(ms.ventes_veille), "ventes payées") : null),
      s ? h("h3", {}, "La semaine écoulée") : null,
      s ? h("div", { class: "tuiles compactes" },
        tuile(n(s.payees) + evolution(s.payees, s.payees_avant), "commandes payées (" + n(s.payees_avant) + " la semaine d'avant)"),
        tuile(n(s.jamais_payees) + evolution(s.jamais_payees, s.jamais_payees_avant), "jamais payées (" + n(s.jamais_payees_avant) + " avant)"),
        tuile(n(s.reclamations) + evolution(s.reclamations, s.reclamations_avant), "réclamations (" + n(s.reclamations_avant) + " avant)"),
        m ? tuile(UI.fcfa(ms.ventes_semaine) + evolution(ms.ventes_semaine, ms.ventes_semaine_avant),
          "ventes (" + UI.fcfa(ms.ventes_semaine_avant) + " avant)") : null) : null,
      h("h3", {}, "La file de l'équipe"),
      h("div", { class: "tuiles compactes" },
        tuile(f.ouvertes, "tâches libres", "#/file", true),
        tuile(f.prises, "tâches en cours", "#/file"),
        tuile(f.escaladees, "remontées au responsable", "#/file", true)));
  }

  async function afficher(zone) {
    const d = await Supabase.rpc("rh_bilans_lire", { v_nombre: 30 });
    if (!zone.isConnected) return;
    const bilans = d.bilans || [];
    UI.vider(zone,
      h("p", { class: "doux petit" }, "Un bilan chaque matin à 7 h ; le lundi, la semaine écoulée comparée à la précédente." +
        (d.montants ? "" : " Sans les montants, réservés à l'administration.")),
      bilans.length ? h("div", { class: "pile" }, bilans.map((b) => carte(b)))
        : UI.vide("Aucun bilan pour l'instant : le premier se prépare à 7 h."));
  }

  return { titre: "Bilan du matin", afficher, carte };
})();
