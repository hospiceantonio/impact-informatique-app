/* =========================================================
   Prêts et retraits — ce qui attend le CEO et la caisse.

   - Le CEO valide (ou refuse) les demandes de prêt, et tranche les
     reversements FeexPay « incertains » après avoir regardé le
     tableau de bord FeexPay. Il voit aussi le solde de chacun.
   - Le gestionnaire de la caisse décaisse les prêts validés et sert
     les retraits : par FeexPay (« Envoyer »), ou à la caisse. Jamais
     les siens.

   La base décide de tout (rh_prets_retraits, rh_decider_pret…) ;
   l'envoi FeexPay passe par la fonction Edge « rh-reversement »,
   qui seule détient le jeton.
   ========================================================= */
const VuePrets = (() => {
  const { h } = UI;
  const numero = (r) => "R-" + String(r.numero).padStart(4, "0");
  const etiquette = (table, s) => UI.etiquette(...(table[s] || [s, ""]));
  const dixMinutes = (r) => r.traite_le && Date.now() - UI.enDate(r.traite_le).getTime() > 10 * 60 * 1000;

  async function afficher(zone) {
    UI.vider(zone, UI.chargement());
    const d = await Supabase.rpc("rh_prets_retraits", {});
    if (!zone.isConnected) return;
    const recharger = () => App.rafraichir().then(() => afficher(zone));
    const { STATUTS_RETRAIT, STATUTS_PRET, NOM_RESEAU } = VueSolde;
    const moi = d.moi;

    const pret = (p) => {
      const actions = [];
      if (d.chef && p.statut === "demandee") {
        actions.push(h("button", { class: "btn btn-vert btn-petit", onclick: async (ev) => {
          if (!await UI.confirmer("Valider le prêt de " + UI.fcfa(p.montant) + " à " + p.nom + " ? La caisse le lui remettra, et sa prochaine paie le reprendra en une fois.", { valider: "Valider" })) return;
          await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_decider_pret", { pret: p.id, accepter: true, raison: "" }), "Prêt validé : il attend la caisse.");
          recharger();
        } }, UI.icone("check", "ic-sm"), "Valider"));
        actions.push(h("button", { class: "btn btn-danger btn-petit", onclick: async (ev) => {
          const raison = await UI.motif("Refuser le prêt", "Pourquoi ?");
          if (raison === null) return;
          await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_decider_pret", { pret: p.id, accepter: false, raison }), "Prêt refusé.");
          recharger();
        } }, "Refuser"));
      }
      if (d.gestion && p.statut === "validee" && p.employe_id !== moi) {
        actions.push(h("button", { class: "btn btn-orange btn-petit", onclick: async (ev) => {
          const v = await VueCaisse.repartir({ titre: "Décaisser le prêt de " + p.nom + " : " + UI.fcfa(p.montant), montant: Number(p.montant), valider: "Confirmer le décaissement" });
          if (!v) return;
          await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_decaisser_pret", { pret: p.id, repartition: v.repartition, reference: v.reference }),
            "Prêt décaissé : il sera repris sur sa prochaine paie.");
          recharger();
        } }, UI.icone("argent", "ic-sm"), "Décaisser"));
      }
      return h("div", { class: "element" },
        h("div", { class: "etire" },
          h("div", { class: "ligne" }, h("span", { class: "gras etire" }, p.nom + " · " + UI.fcfa(p.montant)), etiquette(STATUTS_PRET, p.statut)),
          h("div", { class: "petit doux" }, p.motif + " · demandé le " + UI.date(p.cree_le)),
          d.gestion && p.statut === "validee" && p.employe_id === moi
            ? h("div", { class: "petit avertissement" }, "C'est votre propre prêt : le CEO doit désigner quelqu'un d'autre pour le décaisser.") : null,
          actions.length ? h("div", { class: "actions" }, actions) : null));
    };

    const retrait = (r) => {
      const actions = [];
      const sien = r.employe_id === moi;
      if (d.gestion && r.statut === "demande" && !sien) {
        if (r.moyen === "feexpay") {
          actions.push(h("button", { class: "btn btn-petit", onclick: async (ev) => {
            const autre = r.telephone_fiche && r.telephone !== r.telephone_fiche;
            if (!await UI.confirmer("Envoyer " + UI.fcfa(r.montant) + " à " + r.nom + " sur " + (NOM_RESEAU[r.reseau] || r.reseau) + " " + r.telephone + " ?" +
              (autre ? " Attention : ce n'est pas le numéro de sa fiche (" + r.telephone_fiche + ")." : "") +
              " L'argent part du compte FeexPay de BIZZOO.", { valider: "Envoyer" })) return;
            const reponse = await UI.agir(ev.currentTarget, () => Supabase.reverser("envoyer", { retrait: r.id }));
            if (reponse) {
              const s = reponse.statut;
              (s === "echoue" || s === "incertain" ? UI.echec : UI.succes)(reponse.message
                || (s === "paye" ? "Versé : FeexPay l'a confirmé." : "Envoyé à FeexPay : le versement est en cours."));
            }
            recharger();
          } }, UI.icone("envoyer", "ic-sm"), "Envoyer par FeexPay"));
        }
        actions.push(h("button", { class: "btn btn-orange btn-petit", onclick: async (ev) => {
          const v = await VueCaisse.repartir({ titre: "Remettre " + UI.fcfa(r.montant) + " à " + r.nom, montant: Number(r.montant), valider: "Confirmer le paiement" });
          if (!v) return;
          await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_servir_retrait", { retrait: r.id, repartition: v.repartition, reference: v.reference }),
            "Retrait payé : il sort de la caisse.");
          recharger();
        } }, UI.icone("argent", "ic-sm"), "Payer à la caisse"));
      }
      if ((d.gestion || d.chef) && r.statut === "demande" && !sien) {
        actions.push(h("button", { class: "btn btn-danger btn-petit", onclick: async (ev) => {
          const raison = await UI.motif("Refuser le retrait", "Pourquoi ? (le montant revient sur son solde)");
          if (raison === null) return;
          await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_refuser_retrait", { retrait: r.id, raison }), "Retrait refusé.");
          recharger();
        } }, "Refuser"));
      }
      if (r.statut === "envoye" || (r.statut === "incertain" && r.reference)) {
        actions.push(h("button", { class: "btn btn-second btn-petit", onclick: async (ev) => {
          const reponse = await UI.agir(ev.currentTarget, () => Supabase.reverser("verifier", { retrait: r.id }));
          const issue = reponse && reponse.issues && reponse.issues[r.id];
          UI.succes(issue === "paye" ? "FeexPay confirme : versé." : issue === "echoue" ? "FeexPay dit : échoué. Le montant est revenu sur le solde."
            : "Toujours en cours chez FeexPay.");
          recharger();
        } }, UI.icone("actualiser", "ic-sm"), "Vérifier"));
      }
      if (d.chef && (r.statut === "incertain" || (r.statut === "envoi" && dixMinutes(r)))) {
        const trancher = (paye) => async (ev) => {
          const constat = await UI.motif(paye ? "Déclarer ce reversement payé" : "Rien n'est parti",
            "Ce que vous avez vu dans le tableau de bord FeexPay (référence, statut)");
          if (constat === null) return;
          await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_retrait_trancher", { retrait: r.id, paye, constat }),
            paye ? "Retrait déclaré payé." : "Retrait rendu : le montant est revenu sur son solde.");
          recharger();
        };
        actions.push(h("button", { class: "btn btn-vert btn-petit", onclick: trancher(true) }, "Il est payé"));
        actions.push(h("button", { class: "btn btn-danger btn-petit", onclick: trancher(false) }, "Rien n'est parti"));
      }
      return h("div", { class: "element" },
        h("div", { class: "etire" },
          h("div", { class: "ligne" }, h("span", { class: "gras etire" }, r.nom + " · " + UI.fcfa(r.montant)), etiquette(STATUTS_RETRAIT, r.statut)),
          h("div", { class: "petit doux" }, [numero(r), r.moyen === "feexpay" ? (NOM_RESEAU[r.reseau] || "Mobile Money") + " " + r.telephone : "À la caisse",
            "demandé le " + UI.dateHeure(r.demande_le), r.reference ? "réf. " + r.reference : ""].filter(Boolean).join(" · ")),
          r.motif ? h("div", { class: "petit" }, r.motif) : null,
          r.statut === "incertain" ? h("div", { class: "petit avertissement" },
            "On ne sait pas si l'argent est parti : regardez le tableau de bord FeexPay avant de trancher. Ne le renvoyez pas, il partirait deux fois.") : null,
          d.gestion && sien && r.statut === "demande" ? h("div", { class: "petit avertissement" }, "C'est votre propre retrait : quelqu'un d'autre doit le servir.") : null,
          actions.length ? h("div", { class: "actions" }, actions) : null));
    };

    const enCours = (d.retraits || []).filter((r) => ["demande", "envoi", "envoye", "incertain"].includes(r.statut));
    const conclus = (d.retraits || []).filter((r) => !enCours.includes(r));
    UI.vider(zone,
      h("div", { class: "carte pile" }, h("h2", {}, "Prêts à traiter"),
        (d.prets || []).length ? h("div", { class: "liste" }, d.prets.map(pret)) : UI.vide("Aucun prêt en attente.")),
      h("div", { class: "carte pile" }, h("h2", {}, "Retraits en cours"),
        enCours.length ? h("div", { class: "liste" }, enCours.map(retrait)) : UI.vide("Aucun retrait en attente.")),
      conclus.length ? h("div", { class: "carte pile" }, h("h2", {}, "Retraits des 30 derniers jours"),
        h("div", { class: "liste" }, conclus.map(retrait))) : null,
      d.chef && d.soldes ? h("div", { class: "carte pile" }, h("h2", {}, "Le solde de chacun"),
        h("div", { class: "defile" }, h("table", { class: "tableau" },
          h("thead", {}, h("tr", {}, h("th", {}, "Employé"), h("th", { class: "nombre" }, "Solde"))),
          h("tbody", {}, d.soldes.map((s) => h("tr", {},
            h("td", {}, h("a", { href: "#/employes/" + s.employe_id }, s.nom)), h("td", { class: "nombre" }, UI.fcfa(s.solde))))),
          h("tfoot", {}, h("tr", {}, h("th", {}, "Total dû aux employés"),
            h("th", { class: "nombre" }, UI.fcfa(d.soldes.reduce((t, s) => t + Number(s.solde), 0)))))))) : null);
  }

  return { titre: "Prêts et retraits", afficher };
})();
