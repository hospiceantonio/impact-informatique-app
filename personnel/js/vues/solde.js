/* =========================================================
   Mon solde — l'argent que BIZZOO doit à chaque employé.

   Le 10 du mois, la paie validée du mois écoulé s'y verse
   (salaire + primes − retenues − prêt). L'employé retire ensuite
   tout ou partie de son solde, quand il veut : par Mobile Money
   (le gestionnaire de la caisse l'envoie par FeexPay) ou à la
   caisse. Il y demande aussi un prêt, que le CEO valide et que la
   caisse décaisse ; la paie suivante le reprend en une fois.

   La base tient tout (rh_compte_employe, rh_demander_retrait…) :
   un retrait ne dépasse jamais le solde, et personne ne s'écrit
   « payé » — seul FeexPay, ou la caisse, en décide.
   ========================================================= */
const VueSolde = (() => {
  const { h } = UI;

  const STATUTS_RETRAIT = {
    demande: ["En attente", "orange"], envoi: ["Envoi en cours", "bleu"], envoye: ["Envoyé, en cours", "bleu"],
    incertain: ["À vérifier par le CEO", "orange"], paye: ["Payé", "vert"], echoue: ["Échoué, rendu", "rouge"],
    refuse: ["Refusé, rendu", "rouge"], annule: ["Annulé", ""],
  };
  const STATUTS_PRET = {
    demandee: ["Chez le CEO", "orange"], validee: ["À décaisser", "bleu"], active: ["En cours", "bleu"],
    soldee: ["Remboursé", "vert"], refusee: ["Refusé", "rouge"], annulee: ["Annulé", ""],
  };
  const RESEAUX = [["mtn", "MTN Mobile Money"], ["moov", "Moov Money"], ["celtiis", "Celtiis Cash"]];
  const NOM_RESEAU = Object.fromEntries(RESEAUX);
  /* Le réseau que suggère un numéro (la table commune, UI.reseauDuNumero) :
     pour PROPOSER, jamais pour interdire — un numéro porté garde son
     préfixe. */
  const reseauDuNumero = (tel) => (UI.reseauDuNumero(tel) || "MTN").toLowerCase();
  const etiquette = (table, s) => UI.etiquette(...(table[s] || [s, ""]));
  const numero = (r) => "R-" + String(r.numero).padStart(4, "0");

  async function afficher(zone) {
    UI.vider(zone, UI.chargement());
    const c = await Supabase.rpc("rh_compte_employe", {});
    if (!zone.isConnected) return;
    const recharger = () => App.rafraichir().then(() => afficher(zone));
    const solde = Number(c.solde);
    const enAttente = (c.prets || []).some((p) => ["demandee", "validee"].includes(p.statut));

    const retirer = async (ev) => {
      const bouton = ev.currentTarget;
      const v = await UI.formulaire({
        titre: "Retirer de mon solde", valider: "Demander le retrait",
        texte: "Disponible : " + UI.fcfa(solde) + ". Par Mobile Money, le gestionnaire de la caisse vous l'envoie ; à la caisse, il vous le remet.",
        champs: [
          { nom: "montant", libelle: "Montant (FCFA)", type: "number", min: 1, max: solde, pas: 1, requis: true, valeur: solde > 0 ? solde : "" },
          { nom: "moyen", libelle: "Comment", type: "select", valeur: "feexpay",
            options: [{ valeur: "feexpay", libelle: "Par Mobile Money, sur mon numéro" }, { valeur: "caisse", libelle: "À la caisse" }] },
          { nom: "telephone", libelle: "Numéro Mobile Money", type: "tel", valeur: c.telephone || "", indice: "01 + 8 chiffres",
            aide: "Le numéro du compte Mobile Money qui recevra l'argent." },
          { nom: "reseau", libelle: "Réseau", type: "select", valeur: reseauDuNumero(c.telephone),
            options: RESEAUX.map(([v, l]) => ({ valeur: v, libelle: l })) },
        ],
        /* (3.70.0) Le réseau suit le numéro tapé : un numéro MTN avec
           « Moov » choisi repasse sur MTN. On peut le rechoisir ensuite. */
        quandSaisie: (nom, champs) => {
          if (nom !== "telephone" || !champs.reseau) return;
          const op = UI.reseauDuNumero(champs.telephone.value);
          if (op) champs.reseau.value = op.toLowerCase();
        },
        verifier: (x) => {
          const n = Number(x.montant);
          if (!Number.isInteger(n) || n <= 0) return "Un montant en francs entiers, positif.";
          if (n > solde) return "Votre solde n'a que " + UI.fcfa(solde) + ".";
          if (x.moyen === "feexpay") {
            if (n < 50) return "Par Mobile Money, 50 FCFA au moins.";
            const t = x.telephone.replace(/\D/g, "").replace(/^229(?=01)/, "");
            if (!/^(01)?[0-9]{8}$/.test(t)) return "Le numéro : 01 suivi de 8 chiffres.";
          }
          return null;
        },
      });
      if (!v) return;
      await UI.agir(bouton, () => Supabase.rpc("rh_demander_retrait", {
        montant: Number(v.montant), moyen: v.moyen, reseau: v.moyen === "feexpay" ? v.reseau : null,
        telephone: v.moyen === "feexpay" ? v.telephone : "" }),
        v.moyen === "feexpay" ? "Retrait demandé : le gestionnaire de la caisse va vous l'envoyer." : "Retrait demandé : passez à la caisse.");
      recharger();
    };

    const emprunter = async (ev) => {
      const bouton = ev.currentTarget;
      const v = await UI.formulaire({
        titre: "Demander un prêt", valider: "Envoyer la demande",
        texte: "Le CEO valide votre demande, la caisse vous remet l'argent, et votre prochaine paie le reprend en une fois.",
        champs: [
          { nom: "montant", libelle: "Montant (FCFA)", type: "number", min: 1, pas: 1, requis: true },
          { nom: "motif", libelle: "Pourquoi ?", type: "textarea", requis: true },
        ],
        verifier: (x) => (!(Number.isInteger(Number(x.montant)) && Number(x.montant) > 0) ? "Un montant en francs entiers, positif."
          : x.motif.length < 3 ? "Dites pourquoi vous demandez ce prêt." : null),
      });
      if (!v) return;
      await UI.agir(bouton, () => Supabase.rpc("rh_demander_pret", { montant: Number(v.montant), motif: v.motif }), "Demande envoyée au CEO.");
      recharger();
    };

    const elements = c.elements || [];
    UI.vider(zone,
      h("div", { class: "carte pile" },
        h("div", { class: "doux petit" }, "Mon solde"),
        h("div", { style: { fontSize: "30px", fontWeight: 700, color: solde < 0 ? "var(--rouge, #c62828)" : "var(--bleu-900)" } }, UI.fcfa(solde)),
        h("div", { class: "petit doux" }, "Prochaine paie : " + UI.mois(c.prochain_mois) + ", versée ici le " + UI.date(c.prochain_versement) +
          " si le CEO l'a validée."),
        solde < 0 ? h("div", { class: "avertissement" }, "Votre solde est négatif : des retenues ont dépassé votre salaire. Il se reprend sur vos prochains versements.") : null,
        h("div", { class: "actions" },
          h("button", { class: "btn", disabled: solde <= 0, onclick: retirer }, UI.icone("argent", "ic-sm"), "Retirer"),
          h("button", { class: "btn btn-second", disabled: enAttente, title: enAttente ? "Vous avez déjà un prêt en attente" : "",
            onclick: emprunter }, UI.icone("plus", "ic-sm"), "Demander un prêt"))),

      elements.length ? h("div", { class: "carte pile" },
        h("h2", {}, "Sur ma prochaine paie"),
        h("div", { class: "liste" }, elements.map((x) => h("div", { class: "element" },
          h("div", { class: "etire" }, h("div", { class: "gras" }, x.libelle), h("div", { class: "petit doux" }, UI.mois(x.mois))),
          h("b", { style: { color: x.nature === "retenue" ? "var(--rouge, #c62828)" : "" } }, (x.nature === "retenue" ? "− " : "+ ") + UI.fcfa(x.montant)))))) : null,

      h("div", { class: "carte pile" },
        h("h2", {}, "Mes retraits"),
        (c.retraits || []).length ? h("div", { class: "liste" }, c.retraits.map((r) => h("div", { class: "element" },
          h("div", { class: "etire" },
            h("div", { class: "ligne" }, h("span", { class: "gras etire" }, UI.fcfa(r.montant)), etiquette(STATUTS_RETRAIT, r.statut)),
            h("div", { class: "petit doux" }, [numero(r), r.moyen === "feexpay" ? (NOM_RESEAU[r.reseau] || "Mobile Money") + " · " + r.telephone : "À la caisse",
              UI.dateHeure(r.demande_le)].join(" · ")),
            r.motif ? h("div", { class: "petit" }, r.motif) : null),
          r.statut === "demande" ? h("button", { class: "btn btn-second btn-petit", onclick: async (ev) => {
            if (!await UI.confirmer("Annuler ce retrait de " + UI.fcfa(r.montant) + " ? Le montant revient sur votre solde.", { valider: "Annuler le retrait" })) return;
            await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_annuler_retrait", { retrait: r.id }), "Retrait annulé.");
            recharger();
          } }, "Annuler") : null)))
          : UI.vide("Aucun retrait.")),

      h("div", { class: "carte pile" },
        h("h2", {}, "Mes prêts"),
        (c.prets || []).length ? h("div", { class: "liste" }, c.prets.map((p) => h("div", { class: "element" },
          h("div", { class: "etire" },
            h("div", { class: "ligne" }, h("span", { class: "gras etire" }, UI.fcfa(p.montant)), etiquette(STATUTS_PRET, p.statut)),
            h("div", { class: "petit doux" }, [p.motif, "demandé le " + UI.date(p.cree_le),
              p.statut === "active" ? "reste " + UI.fcfa(p.reste) + ", repris sur la paie (" + UI.mois(p.premier_mois) + ")" : ""].filter(Boolean).join(" · ")),
            p.motif_refus ? h("div", { class: "petit" }, "CEO : " + p.motif_refus) : null),
          p.statut === "demandee" ? h("button", { class: "btn btn-second btn-petit", onclick: async (ev) => {
            if (!await UI.confirmer("Retirer cette demande de prêt ?", { valider: "Retirer" })) return;
            await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_annuler_pret", { pret: p.id }), "Demande retirée.");
            recharger();
          } }, "Retirer") : null)))
          : UI.vide("Aucun prêt.")),

      h("div", { class: "carte pile" },
        h("h2", {}, "Mouvements"),
        (c.mouvements || []).length ? h("div", { class: "defile" }, h("table", { class: "tableau" },
          h("thead", {}, h("tr", {}, h("th", {}, "Date"), h("th", {}, "Libellé"), h("th", { class: "nombre" }, "Montant"), h("th", { class: "nombre" }, "Solde"))),
          h("tbody", {}, c.mouvements.map((m) => h("tr", {},
            h("td", {}, UI.dateHeure(m.le)), h("td", {}, m.libelle),
            h("td", { class: "nombre", style: { color: m.sens === "debit" ? "var(--rouge, #c62828)" : "var(--vert, #2e7d32)" } },
              (m.sens === "debit" ? "− " : "+ ") + UI.entier(m.montant)),
            h("td", { class: "nombre" }, UI.entier(m.solde)))))))
          : UI.vide("Aucun mouvement : votre premier salaire arrivera ici le 10.")));
  }

  return { titre: "Mon solde", afficher, STATUTS_RETRAIT, STATUTS_PRET, NOM_RESEAU };
})();
