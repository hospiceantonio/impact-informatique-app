/* =========================================================
   Reversements (3.73.0) — les demandes d'argent des boutiques, des
   livreurs et des vendeurs, au CEO et au profil « Comptabilité ».

   #/reversements : ce qui attend, puis ce qui est tranché ; filtres par
   état et par demandeur, recherche. « Envoyé » note la référence de la
   transaction Mobile Money, « Refuser » un motif — les mêmes fonctions
   que BIZZOO Admin → Reversements. La base ne rend ces listes qu'au CEO,
   à la comptabilité (rh_reversements_acces) et au superadministrateur,
   et refuse à tout autre de trancher : le menu n'est qu'une porte, la
   serrure est en base. Seul le CEO place quelqu'un dans la comptabilité.
   ========================================================= */
const VueReversements = (() => {
  const { h } = UI;

  const ETATS = { en_attente: ["À traiter", "orange"], valide: ["Envoyé", "vert"], refuse: ["Refusé", "rouge"] };
  const QUI = { boutique: "Boutique", livreur: "Livreur", vendeur: "Vendeur" };
  const DECIDER = { boutique: "decider_reversement", livreur: "decider_reversement_livreur",
    vendeur: "decider_reversement_vendeur" };
  const plier = (t) => String(t || "").normalize("NFD").replace(/[̀-ͯ]/g, "")
    .toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();

  /** Les trois listes, en une : chaque demande sait d'où elle vient. */
  async function lire() {
    const [boutiques, livreurs, vendeurs] = await Promise.all([
      Supabase.rpc("reversements_liste", { cible: null }),
      Supabase.rpc("reversements_livreurs_liste", {}).catch(() => []),
      Supabase.rpc("reversements_vendeurs_liste", {}).catch(() => [])]);
    const liste = [
      ...(boutiques || []).map((r) => ({ ...r, qui: "boutique", nom: r.nom_boutique || "Boutique" })),
      ...(livreurs || []).map((r) => ({ ...r, qui: "livreur", nom: r.nom_livreur || "Livreur", devise: "FCFA" })),
      ...(vendeurs || []).map((r) => ({ ...r, qui: "vendeur", nom: r.nom_vendeur || "Vendeur", devise: "FCFA" }))];
    /* Le nom du compte MoMo noté à la création d'un livreur : MoMo doit
       afficher ce nom-là avant qu'on envoie. */
    const ids = [...new Set(liste.filter((r) => r.qui === "livreur" && r.livreur_id).map((r) => r.livreur_id))];
    if (ids.length) {
      try {
        const fiches = await Supabase.rpc("noms_momo", { ids });
        const noms = new Map((fiches || []).map((f) => [f.id, f.momo_nom || ""]));
        for (const r of liste) if (r.qui === "livreur") r.momo_nom = noms.get(r.livreur_id) || "";
      } catch (_) { /* une base d'avant : pas de nom à comparer */ }
    }
    return liste.sort((a, b) => (a.etat === "en_attente" ? 0 : 1) - (b.etat === "en_attente" ? 0 : 1) ||
      String(b.demande_le).localeCompare(String(a.demande_le)));
  }

  async function afficher(zone) {
    if (!App.traiteReversements()) {
      UI.vider(zone, h("div", { class: "carte pile" }, h("h2", {}, "Reversements"),
        UI.vide("Réservé au CEO et à la comptabilité. Le CEO place le comptable dans le profil « Comptabilité » (menu Profils).")));
      return;
    }
    UI.vider(zone, UI.chargement());
    const toutes = await lire();
    if (!zone.isConnected) return;
    const recharger = () => { App.rafraichir(); afficher(zone); };

    const recherche = h("input", { type: "search", class: "recherche", "aria-label": "Rechercher",
      placeholder: "Rechercher : boutique, livreur, vendeur, numéro, référence…" });
    const choixEtat = h("select", { "aria-label": "État" },
      [["en_attente", "À traiter"], ["traites", "Déjà traités"], ["", "Toutes"]].map(([v, l]) => h("option", { value: v }, l)));
    const choixQui = h("select", { "aria-label": "Demandeur" }, h("option", { value: "" }, "Tous les demandeurs"),
      Object.entries(QUI).map(([v, l]) => h("option", { value: v }, l + "s")));
    const resume = h("div", {});
    const corps = h("div", {});

    const filtrees = () => {
      const q = plier(recherche.value);
      return toutes.filter((r) =>
        (!choixEtat.value || (choixEtat.value === "traites" ? r.etat !== "en_attente" : r.etat === choixEtat.value)) &&
        (!choixQui.value || r.qui === choixQui.value) &&
        (!q || plier([r.nom, r.tel, r.reseau, r.titulaire, r.reference, r.motif, r.decide_par].join(" ")).includes(q)));
    };

    const decider = async (r, accord, bouton) => {
      let reference = "";
      let motif = "";
      if (accord) {
        const v = await UI.formulaire({ titre: "Reversement envoyé — " + UI.fcfa(r.montant),
          texte: "Envoyé sur " + r.reseau + " " + r.tel + (r.titulaire ? " (" + r.titulaire + ")" : "") +
            ". Notez la référence de la transaction Mobile Money.",
          valider: "Valider", champs: [{ nom: "reference", libelle: "Référence de la transaction", requis: true }],
          verifier: (x) => (String(x.reference || "").replace(/[^A-Za-z0-9]/g, "").length < 4
            ? "Notez la référence de la transaction (au moins 4 caractères)." : null) });
        if (!v) return;
        reference = v.reference.trim();
        /* Un numéro de téléphone recopié à la place de la référence : on le
           dit, et l'on redemande une confirmation. */
        if (UI.ressembleTelephone(reference) &&
            !(await UI.confirmer(UI.alerteTransaction(reference) + " Valider quand même ?", { titre: "Vérifiez la référence" }))) return;
      } else {
        motif = await UI.motif("Refuser le reversement — " + UI.fcfa(r.montant),
          "Pourquoi ? " + (QUI[r.qui] || "Le demandeur") + " le verra ; le montant revient à son solde.");
        if (motif === null) return;
      }
      await UI.agir(bouton, () => Supabase.rpc(DECIDER[r.qui], { cible: r.id, accord, reference, motif }),
        accord ? "Reversement validé : le demandeur est prévenu." : "Demande refusée.");
      recharger();
    };

    /* (3.81.0) LES COMMANDES D'UNE DEMANDE : d'où vient l'argent, et ce qui
       doit faire vérifier avant de l'envoyer (client « test », paiement
       confirmé à la main…). Une demande à traiter les montre d'office. */
    const PAIEMENTS = { feexpay: "FeexPay", kkiapay: "KkiaPay" };
    const paiement = (c) => (PAIEMENTS[c.paiement]
      ? PAIEMENTS[c.paiement] + (c.transaction ? " — référence " + c.transaction : "")
      : c.confirme_par ? "Confirmé à la main"
      : c.transaction ? "Référence " + c.transaction : "Paiement sans référence");
    const renduCommandes = (o) => {
      const liste = (o && o.commandes) || [];
      const total = liste.reduce((t, c) => t + Number(c.couvert || 0), 0);
      const doutes = liste.filter((c) => (c.alertes || []).length).length;
      return h("div", { class: "commandes-reversement" },
        h("div", { class: "gras" }, liste.length
          ? liste.length + " commande" + (liste.length > 1 ? "s" : "") + " — " + UI.fcfa(total)
          : "Aucune commande ne correspond à cette demande."),
        doutes ? h("div", { class: "avertissement" }, doutes + (doutes > 1 ? " commandes à vérifier" : " commande à vérifier") +
          " avant d'envoyer.") : null,
        liste.map((c) => h("div", { class: "ligne-commande" + ((c.alertes || []).length ? " a-verifier" : "") },
          h("div", {}, h("b", {}, c.numero || c.commande_id), " · " + (c.client || "Client") + " · " +
            UI.fcfa(c.couvert) + " · payée le " + UI.dateHeure(c.paye_le)),
          h("div", { class: "doux" }, paiement(c) + (Number(c.couvert) < Number(c.part)
            ? " · sur une part de " + UI.fcfa(c.part) : "")),
          (c.alertes || []).map((x) => h("div", { class: "alerte-commande" }, x)))),
        Number(o && o.non_rattache) > 0
          ? h("div", { class: "avertissement" }, UI.fcfa(o.non_rattache) +
              " ne viennent d'aucune commande remise : vérifiez avant d'envoyer.")
          : null);
    };
    const blocCommandes = (r) => {
      const zone = h("div", { class: "commandes-zone" });
      const charger = async () => {
        UI.vider(zone, UI.chargement());
        try {
          UI.vider(zone, renduCommandes(await Supabase.rpc("reversement_operations", { genre: r.qui, cible: r.id })));
        } catch (err) {
          UI.vider(zone, h("div", { class: "avertissement" }, err.message));
        }
      };
      if (r.etat === "en_attente") charger();
      else UI.vider(zone, h("button", { class: "btn btn-petit", onclick: charger }, "Voir les commandes"));
      return zone;
    };

    const element = (r) => {
      const [mot, couleur] = ETATS[r.etat] || ETATS.en_attente;
      const ecart = r.qui === "livreur" && r.titulaire && r.momo_nom && plier(r.titulaire) !== plier(r.momo_nom);
      return h("div", { class: "element reversement", "data-reversement": r.qui + ":" + r.id },
        h("div", { class: "etire" },
          h("div", { class: "ligne" },
            h("span", { class: "gras etire" }, UI.fcfa(r.montant) + " · " + (QUI[r.qui] || "") + " — " + r.nom),
            UI.etiquette(mot, couleur)),
          h("div", { class: "petit doux" }, ["Vers " + r.reseau + " " + r.tel + (r.titulaire ? " (" + r.titulaire + ")" : ""),
            "demandé le " + UI.dateHeure(r.demande_le), r.demande_par ? "par " + r.demande_par : ""].filter(Boolean).join(" · ")),
          r.qui === "livreur" && r.etat === "en_attente"
            ? h("div", { class: "petit" + (ecart || !r.momo_nom ? " avertissement" : "") },
                r.momo_nom
                  ? "Nom du compte MoMo enregistré : " + r.momo_nom + (ecart
                      ? " — le livreur a indiqué « " + r.titulaire + " » : ce n'est pas le même nom."
                      : " — vérifiez que MoMo affiche ce nom avant d'envoyer.")
                  : "Aucun nom de compte MoMo enregistré pour ce livreur : notez-le dans sa fiche (BIZZOO Admin → Livreurs).")
            : null,
          blocCommandes(r),
          r.etat === "valide" ? h("div", { class: "petit" }, "Envoyé le " + UI.dateHeure(r.decide_le) +
            (r.decide_par ? " par " + r.decide_par : "") + " — référence " + (r.reference || "—")) : null,
          r.etat === "refuse" ? h("div", { class: "petit" }, "Refusé le " + UI.dateHeure(r.decide_le) +
            (r.decide_par ? " par " + r.decide_par : "") + (r.motif ? " : « " + r.motif + " »" : "")) : null,
          r.etat === "en_attente" ? h("div", { class: "actions" },
            h("button", { class: "btn btn-vert btn-petit", onclick: (ev) => decider(r, true, ev.currentTarget) },
              UI.icone("check", "ic-sm"), "Envoyé"),
            h("button", { class: "btn btn-danger btn-petit", onclick: (ev) => decider(r, false, ev.currentTarget) },
              UI.icone("fermer", "ic-sm"), "Refuser")) : null));
    };

    const dessiner = () => {
      const liste = filtrees();
      const attente = toutes.filter((r) => r.etat === "en_attente");
      UI.vider(resume, h("div", { class: "tuiles compactes" },
        h("div", { class: "tuile" + (attente.length ? " alerte" : "") }, h("b", {}, String(attente.length)), h("span", {}, "à traiter")),
        h("div", { class: "tuile" }, h("b", {}, UI.fcfa(attente.reduce((t, r) => t + Number(r.montant || 0), 0))), h("span", {}, "demandés"))));
      UI.vider(corps, liste.length ? h("div", { class: "liste" }, liste.map(element))
        : UI.vide(choixEtat.value === "en_attente" ? "Aucune demande à traiter." : "Aucune demande ne correspond."));
    };
    for (const e of [recherche, choixEtat, choixQui]) e.addEventListener(e === recherche ? "input" : "change", dessiner);

    UI.vider(zone,
      h("div", { class: "carte pile" },
        h("h2", {}, "Reversements"),
        h("p", { class: "doux petit" }, "Les demandes d'argent des boutiques, des livreurs et des vendeurs. Envoyez l'argent " +
          "sur le numéro indiqué, puis notez la référence de la transaction. Réservé au CEO et à la comptabilité."),
        resume,
        h("div", { class: "barre-compacte" }, recherche, choixEtat, choixQui)),
      corps);
    dessiner();
  }

  return { titre: "Reversements", afficher };
})();
