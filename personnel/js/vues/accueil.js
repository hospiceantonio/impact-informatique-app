/* =========================================================
   Accueil — ce qui attend la personne connectée, selon son rang,
   puis la place de marché d'un coup d'œil (rh_accueil_chiffres) :
   le mois en cours et aujourd'hui. La base décide de qui voit
   les nombres, les montants et la marge ; sans droit, cette
   partie n'apparaît pas. Chaque tuile mène à l'écran où l'on agit.
   ========================================================= */
const VueAccueil = (() => {
  const { h } = UI;

  function tuile(nombre, texte, lien, alerte) {
    return h("a", { class: "tuile" + (alerte && nombre > 0 ? " alerte" : ""), href: lien },
      h("b", {}, UI.entier(nombre || 0)), h("span", {}, texte));
  }

  /** Un chiffre de la place de marché : un nombre, ou un montant (null = pas de droit). */
  function chiffre(valeur, texte, lien, { fcfa, alerte, note } = {}) {
    if (valeur === null || valeur === undefined) return null;
    const affiche = note ? String(valeur).replace(".", ",") + " / 5" : fcfa ? UI.fcfa(valeur) : UI.entier(valeur);
    return h(lien ? "a" : "div", { class: "tuile" + (alerte && Number(valeur) > 0 ? " alerte" : ""), href: lien || undefined },
      h("b", {}, affiche), h("span", {}, texte));
  }

  /** Les chiffres de BIZZOO, par rubrique. */
  function placeDeMarche(x) {
    const c = x.commandes, l = x.livraisons, k = x.clients, b = x.boutiques, p = x.produits;
    const stats = (s) => "#/statistiques/" + s + "?p=mois";
    const rubrique = (titre, tuiles) => {
      const pleines = tuiles.filter(Boolean);
      return pleines.length ? h("div", { class: "rubrique-accueil" }, h("h3", {}, titre), h("div", { class: "tuiles" }, pleines)) : null;
    };
    return h("div", { class: "carte pile" },
      h("h2", {}, "BIZZOO en " + UI.mois(x.mois).toLowerCase()),
      rubrique("Commandes", [
        chiffre(c.payees_mois, "commandes payées ce mois", stats("commandes")),
        chiffre(c.payees_jour, "payées aujourd'hui", "#/suivi?p=jour"),
        chiffre(c.recues_mois, "commandes reçues ce mois", "#/suivi?p=mois"),
        chiffre(c.a_payer_mois, "en attente de paiement", "#/suivi?p=mois", { alerte: true }),
        chiffre(c.annulees_mois, "annulées ou échouées", "#/suivi?p=mois"),
        chiffre(c.articles_mois, "articles vendus", stats("produits")),
        chiffre(c.revendeurs_mois, "commandes de revendeurs"),
        chiffre(c.ventes_mois, "ventes du mois", stats("commandes"), { fcfa: true }),
        chiffre(c.ventes_jour, "ventes d'aujourd'hui", null, { fcfa: true }),
        chiffre(c.panier_moyen, "panier moyen", null, { fcfa: true }),
        chiffre(c.frais_livraison_mois, "frais de livraison encaissés", null, { fcfa: true }),
        chiffre(c.remises_mois, "remises (codes promo)", null, { fcfa: true }),
        chiffre(c.marge_mois, "marge de BIZZOO", stats("revenus"), { fcfa: true }),
      ]),
      rubrique("Livraisons", [
        chiffre(l.confirmees_mois, "livraisons confirmées par le client ce mois", stats("livraisons")),
        chiffre(l.a_preparer, "articles à préparer", "#/suivi?p=30j", { alerte: true }),
        chiffre(l.pretes, "prêts, en attente du livreur", "#/suivi?p=30j"),
        chiffre(l.en_livraison, "en cours de livraison", "#/livreurs"),
        chiffre(l.livrees_sans_confirmation, "livrés, sans confirmation du client", "#/suivi?p=30j", { alerte: true }),
        chiffre(l.livreurs, "livreurs inscrits", stats("livreurs")),
        chiffre(l.livreurs_en_course, "livreurs en course", "#/livreurs"),
      ]),
      rubrique("Clients", [
        chiffre(k.total, "clients inscrits"),
        chiffre(k.nouveaux_mois, "nouveaux clients ce mois"),
        chiffre(k.nouveaux_jour, "nouveaux aujourd'hui"),
        chiffre(k.acheteurs_mois, "clients ayant acheté ce mois"),
        chiffre(k.verifies, "numéros vérifiés"),
        chiffre(k.revendeurs, "revendeurs"),
        chiffre(k.revendeurs_en_attente, "demandes de revendeur en attente", null, { alerte: true }),
      ]),
      rubrique("Boutiques et produits", [
        chiffre(b.total, "boutiques enregistrées", stats("boutiques")),
        chiffre(b.actives, "boutiques ouvertes"),
        chiffre(b.nouvelles_mois, "nouvelles boutiques ce mois"),
        chiffre(b.ayant_vendu_mois, "boutiques ayant vendu ce mois", stats("boutiques")),
        chiffre(p.total, "produits en ligne", stats("produits")),
        chiffre(p.disponibles, "produits disponibles"),
        chiffre(p.ruptures, "produits en rupture de stock", null, { alerte: true }),
        chiffre(p.nouveaux_mois, "nouveaux produits ce mois"),
        chiffre(p.masques, "produits masqués"),
      ]),
      rubrique("Avis et service après-vente", [
        chiffre(x.avis.mois, "avis reçus ce mois", stats("sav")),
        x.avis.note_moyenne === null ? null : chiffre(x.avis.note_moyenne, "note moyenne des avis", stats("sav"), { note: true }),
        chiffre(x.sav.ouvertes, "réclamations à traiter", stats("sav"), { alerte: true }),
        chiffre(x.sav.mois, "réclamations ce mois", stats("sav")),
      ]));
  }

  async function afficher(zone) {
    const [, marche] = await Promise.all([App.rafraichir(), Supabase.rpc("rh_accueil_chiffres").catch(() => null)]);
    if (!zone.isConnected) return;
    /* Le bilan du matin : seulement si la base me l'ouvre (administration,
       responsables de profil) ; elle ôte elle-même les montants. */
    const f = App.file() || {};
    const bilans = f.bilan ? await Supabase.rpc("rh_bilans_lire", { v_nombre: 1 }).catch(() => null) : null;
    if (!zone.isConnected) return;
    const bilan = bilans && bilans.bilans && bilans.bilans[0];
    const aujourdhui = UI.aujourdhui();
    const carteBilan = bilan ? h("div", {},
      VueBilans.carte(bilan, { titre: bilan.jour === aujourdhui ? "Bilan du jour" : "Dernier bilan (" + UI.date(bilan.jour) + ")" }),
      h("a", { class: "petit", href: "#/bilans" }, "Voir l'historique des bilans")) : null;
    const moi = App.moi();
    const c = App.compteurs();
    const heure = new Date().getHours();
    const salut = heure < 12 ? "Bonjour" : heure < 18 ? "Bon après-midi" : "Bonsoir";
    const rang = moi.ceo ? "CEO" : moi.administration ? "Administration" : moi.poste || "";

    const aFaire = [];
    if (f.acces) {
      aFaire.push(tuile((f.a_prendre || 0), "tâche(s) libre(s) dans ma file", "#/file", true));
      if (f.a_moi) aFaire.push(tuile(f.a_moi, "tâche(s) que j'ai prise(s)", "#/file"));
      if (f.escalades) aFaire.push(tuile(f.escalades, "tâche(s) que personne n'a prise(s)", "#/file", true));
    }
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
    }
    /* Les prêts et retraits : le CEO valide, la caisse sert. */
    const s = App.compteursSolde() || {};
    if (s.menu) {
      if (s.prets_a_valider) aFaire.push(tuile(s.prets_a_valider, "prêt(s) à valider", "#/prets", true));
      if (s.prets_a_decaisser) aFaire.push(tuile(s.prets_a_decaisser, "prêt(s) à décaisser", "#/prets", true));
      if (s.retraits_a_servir) aFaire.push(tuile(s.retraits_a_servir, "retrait(s) de salaire à servir", "#/prets", true));
      if (s.retraits_incertains) aFaire.push(tuile(s.retraits_incertains, "reversement(s) à vérifier", "#/prets", true));
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

    /* UN RÉGLAGE SENSIBLE CHANGÉ (code MoMoPay, mode essai…) reste en
       rouge ici tant que le CEO ou le superadministrateur ne l'a pas
       approuvé dans Contrôles. */
    const k = App.controles() || {};
    const alerteReglage = k.reglages_a_approuver > 0 && k.dernier ? h("a", { class: "alerte-rouge", href: "#/controles/reglages" },
      UI.icone("alerte"),
      h("div", { class: "etire" },
        h("b", {}, k.dernier.libelle),
        h("div", { class: "petit" }, "Par " + (k.dernier.par || "inconnu") + ", le " + UI.dateHeure(k.dernier.le) +
          (k.reglages_a_approuver > 1 ? " · " + k.reglages_a_approuver + " changements à vérifier" : "") +
          (k.approuver ? " · touchez pour vérifier et approuver" : " · en attente du CEO"))),
      UI.icone("chevron", "ic-sm")) : null;
    if (k.encaissements_anciens > 0) {
      aFaire.push(tuile(k.encaissements_anciens, "encaissement(s) à la livraison en attente depuis trop longtemps", "#/controles/encaissements", true));
    }
    /* L'argent : un client peut-être débité, un remboursement qui tarde,
       une demande d'argent qui attend trop. */
    const ar = App.argent() || {};
    if (ar.paiements_a_traiter > 0) {
      aFaire.push(tuile(ar.paiements_a_traiter, "paiement(s) à rapprocher", "#/controles/paiements", true));
    }
    if (ar.remboursements_en_retard > 0) {
      aFaire.push(tuile(ar.remboursements_en_retard, "remboursement(s) en retard", "#/controles/remboursements", true));
    }
    if (ar.dettes_anciennes > 0) {
      aFaire.push(tuile(ar.dettes_anciennes, "demande(s) d'argent qui attendent trop", "#/controles/dettes", true));
    }

    UI.vider(zone,
      alerteReglage,
      h("div", {},
        h("h2", { style: { fontSize: "21px" } }, salut + ", " + (moi.prenoms || moi.nom)),
        h("p", { class: "doux" }, [rang, moi.profil ? "Profil " + moi.profil : ""].filter(Boolean).join(" · "))),
      h("div", { class: "tuiles" }, aFaire),
      carteBilan,
      marche ? placeDeMarche(marche) : null,
      h("div", { class: "carte" }, h("h2", {}, "Raccourcis"), h("div", { class: "actions" }, raccourcis)));
  }

  return { titre: "Accueil", afficher };
})();
