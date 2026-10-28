/* =========================================================
   Contrôles — l'argent : cinq onglets du menu Contrôles.

   #/controles/paiements      : les paiements à rapprocher (client
                                peut-être débité, versement en conflit,
                                « j'ai payé » sans suite) et les paiements
                                confirmés à la main ; on note qui a traité ;
   #/controles/dettes         : ce que BIZZOO doit payer aux boutiques,
                                aux livreurs, aux parrains ;
   #/controles/remboursements : les clients à rembourser après une
                                annulation payée ; on note le remboursement ;
   #/controles/gestes         : le journal des gestes faits dans BIZZOO Admin ;
   #/controles/codes          : les codes promo, le parrainage, les abus.

   Rien ne se décide ici sur l'argent de la place de marché : confirmer un
   paiement ou valider un reversement se fait dans BIZZOO Admin. Les
   montants ne viennent que pour l'administration : c'est la base qui
   les retire (« montants » vaut false), l'écran ne fait que suivre.
   ========================================================= */
const VueArgent = (() => {
  const { h } = UI;
  const ROUTE = "#/controles";

  const MOTIFS = {
    debite_non_paye: ["Client débité, commande à payer", "rouge"],
    conflit: ["Versement en conflit", "rouge"],
    incomplet: ["Versement incomplet", "orange"],
    annonce_sans_preuve: ["« J'ai payé » sans preuve", "orange"],
    inconnu: ["Agrégateur sans réponse", "orange"],
    manuel: ["Confirmé à la main", "bleu"],
  };
  const NOTES = { en_cours: "En cours", regle: "Réglé", sans_suite: "Sans suite" };
  const MODES = { mobile_money: "Mobile Money", especes: "Espèces", virement: "Virement", autre: "Autre" };
  const RAISONS = {
    suppression: ["Suppression", "rouge"],
    argent: ["Argent", "rouge"],
    compte: ["Compte", "orange"],
    nuit: ["La nuit", "orange"],
    rafale: ["En rafale", "orange"],
    annule: ["Annulé ensuite", "bleu"],
  };
  const TYPES = { boutique: "Boutique", livreur: "Livreur", parrain: "Parrain" };

  const tuile = (valeur, libelle, alerte) => h("div", { class: "tuile" + (alerte ? " alerte" : "") }, h("b", {}, valeur), h("span", {}, libelle));
  const nb = (n) => UI.entier(n || 0);
  /** « 52 h » ou « 3 j 4 h ». */
  const depuis = (heures) => {
    const n = Number(heures || 0);
    if (n < 48) return n + " h";
    const j = Math.floor(n / 24);
    return j + " j " + (n - j * 24) + " h";
  };
  const lienCommande = (id, numero) => App.ouvert("suivi")
    ? h("a", { href: "#/suivi/commande/" + encodeURIComponent(id) }, numero || id) : (numero || id);
  const filtres = (items, actif, aller) => h("div", { class: "filtres" }, items.map(([v, l]) =>
    h("button", { class: v === actif ? "actif" : "", onclick: () => aller(v) }, l)));
  const tableau = (titre, entetes, lignes) => h("div", { class: "carte defile" },
    titre ? h("h3", { style: { marginBottom: "8px" } }, titre) : null,
    h("table", { class: "tableau" },
      h("thead", {}, h("tr", {}, entetes.filter(Boolean).map(([t, nombre]) => h("th", { class: nombre ? "nombre" : "" }, t)))),
      h("tbody", {}, lignes)));
  const montantsCaches = (argent) => argent ? null : " Sans les montants, réservés à l'administration.";

  /* ---------- Les paiements à rapprocher ---------- */

  async function paiements(zone, barre, params) {
    const periode = VueStatistiques.periodeDe(params, "30j");
    const d = await Supabase.rpc("rh_paiements", { depuis: periode.depuis, jusqu: periode.jusqu });
    if (!zone.isConnected) return;
    const t = d.totaux, argent = d.montants;
    const filtre = params.filtre || "a_traiter";
    const garder = (l) => filtre === "tous" || (filtre === "a_traiter" ? l.a_traiter : filtre === "manuel" ? l.motif === "manuel" : !l.a_traiter && l.motif !== "manuel");
    const lignes = d.lignes.filter(garder);
    const aller = (v) => { location.hash = ROUTE + "/paiements" + (periode.suffixe || "?p=30j") + "&filtre=" + v; };

    const noter = async (l, bouton) => {
      const r = await UI.formulaire({
        titre: "Noter ce qui a été fait — " + (l.numero || l.commande),
        texte: "La note dit qui a traité ce paiement, et comment. Elle ne confirme rien : si le client a bien payé, la confirmation se fait dans BIZZOO Admin, sur la commande.",
        champs: [
          { nom: "statut", libelle: "Où en est-il", type: "select", requis: true, valeur: (l.traitement && l.traitement.statut) || "en_cours",
            options: Object.entries(NOTES).map(([valeur, libelle]) => ({ valeur, libelle })) },
          { nom: "commentaire", libelle: "Ce qui a été fait", type: "textarea", requis: true,
            indice: "Client rappelé, paiement retrouvé chez FeexPay, transmis à l'administration…" },
        ],
        valider: "Enregistrer",
        verifier: (v) => (v.commentaire.length < 3 ? "Dites en quelques mots ce qui a été fait." : null),
      });
      if (!r) return;
      await UI.agir(bouton, () => Supabase.rpc("rh_rapprocher", { cible: l.commande, v_statut: r.statut, v_commentaire: r.commentaire }), "Note enregistrée.");
      App.rafraichir();
      paiements(zone, barre, params);
    };

    const detail = lignes.length ? tableau("Paiement par paiement" + (d.lignes.length >= 500 ? " (les 500 premiers)" : ""), [
      ["Commande"], ["Client"], ["Problème"], ["Depuis"], ["Paiement"],
      argent && ["Total", true], argent && ["Reçu", true], argent && ["Transaction"],
      ["Traité"], [""],
    ], lignes.map((l) => h("tr", { class: l.a_traiter && l.motif !== "annonce_sans_preuve" ? "en-alerte" : "" },
      h("td", { class: "gras" }, lienCommande(l.commande, l.numero)),
      h("td", {}, h("div", {}, l.client || "—"), h("div", { class: "tres-petit doux" }, l.tel || "")),
      h("td", {}, UI.etiquette(...(MOTIFS[l.motif] || [l.motif, ""]))),
      h("td", {}, depuis(l.heures)),
      h("td", { class: "petit" }, [l.fournisseur, l.reseau, l.verdict ? "dernier verdict : " + l.verdict : null,
        l.tentatives ? l.tentatives + " tentative(s)" : null, l.confirme_par ? "garant : " + l.confirme_par : null].filter(Boolean).join(" · ") || "—",
        argent && (l.remarque || l.detail) ? h("div", { class: "tres-petit doux" }, [l.remarque, l.detail].filter(Boolean).join(" — ")) : null),
      argent ? h("td", { class: "nombre" }, UI.entier(l.total)) : null,
      argent ? h("td", { class: "nombre" }, l.recu === null || l.recu === undefined ? "—" : UI.entier(l.recu)) : null,
      argent ? h("td", { class: "petit" }, l.transactions || "—") : null,
      h("td", { class: "petit" }, l.traitement
        ? [UI.etiquette(NOTES[l.traitement.statut] || l.traitement.statut, l.traitement.statut === "en_cours" ? "orange" : "vert"),
           h("div", {}, l.traitement.commentaire),
           h("div", { class: "tres-petit doux" }, (l.traitement.par || "inconnu") + " · " + UI.dateHeure(l.traitement.le))]
        : (l.a_traiter ? "Personne encore" : "—")),
      h("td", {}, l.motif !== "manuel" ? h("button", { class: "btn btn-second btn-petit", onclick: (ev) => noter(l, ev.currentTarget) }, "Noter") : null))))
      : UI.vide(d.lignes.length ? "Rien dans ce filtre." : "Aucun paiement à rapprocher : tout est en ordre.");

    UI.vider(zone, barre,
      UI.barrePeriode(periode, ROUTE + "/paiements", "&filtre=" + filtre),
      h("p", { class: "doux petit" }, "Les clients peut-être débités dont la commande ne le dit pas : à rappeler avant qu'ils ne se plaignent. " +
        "Ce qui attend s'affiche quelle que soit la période (60 jours au plus). « J'ai payé » sans preuve : après " + d.seuils.annonce_min + " min. " +
        "La confirmation du paiement se fait dans BIZZOO Admin ; ici, on note qui a traité et comment." +
        (argent ? "" : " Numéros masqués et sans les montants, réservés à l'administration.")),
      h("div", { class: "tuiles compactes" },
        tuile(nb(t.a_traiter), "à traiter", t.a_traiter > 0),
        tuile(nb(t.debite_non_paye), "clients débités, commande à payer", t.debite_non_paye > 0),
        tuile(nb((t.conflit || 0) + (t.incomplet || 0)), "versements en conflit ou incomplets", (t.conflit || 0) + (t.incomplet || 0) > 0),
        tuile(nb(t.annonce_sans_preuve), "« j'ai payé » sans preuve"),
        tuile(nb(t.inconnu), "agrégateur sans réponse"),
        tuile(nb(t.manuel), "confirmés à la main sur la période"),
        tuile(t.plus_ancien ? UI.quand(t.plus_ancien) : "—", "le plus ancien à traiter"),
        argent ? tuile(UI.fcfa(t.montant_a_traiter), "en jeu dans ce qui attend", t.montant_a_traiter > 0) : null,
        argent ? tuile(UI.fcfa(t.montant_manuel), "confirmés à la main") : null),
      filtres([["a_traiter", "À traiter"], ["traites", "Traités"], ["manuel", "Confirmés à la main"], ["tous", "Tout"]], filtre, aller),
      detail);
  }

  /* ---------- Ce que BIZZOO doit payer ---------- */

  async function dettes(zone, barre, params) {
    const periode = VueStatistiques.periodeDe(params, "30j");
    const d = await Supabase.rpc("rh_dettes", { depuis: periode.depuis, jusqu: periode.jusqu });
    if (!zone.isConnected) return;
    const t = d.totaux, argent = d.montants, j = d.seuils.dette_j;

    const demandes = d.demandes.length ? tableau("Demandes en attente", [
      ["Pour"], ["Qui"], ["Demandée le"], ["Depuis"], argent && ["Montant", true],
    ], d.demandes.map((x) => h("tr", { class: x.ancienne ? "en-alerte" : "" },
      h("td", {}, TYPES[x.type] || x.type),
      h("td", { class: "gras" }, x.nom || "—"),
      h("td", {}, UI.dateHeure(x.le)),
      h("td", {}, h("div", { class: "actions" }, x.jours + " j", x.ancienne ? UI.etiquette("Ancienne", "rouge") : null)),
      argent ? h("td", { class: "nombre" }, UI.entier(x.montant)) : null)))
      : UI.vide("Aucune demande en attente : personne n'attend d'argent de BIZZOO.");

    const comptes = d.comptes.length ? tableau("Compte par compte", [
      ["Pour"], ["Qui"], ["Demandes", true], ["Anciennes", true], ["La plus ancienne"],
      argent && ["Demandé", true], argent && ["Dû sans demande", true], argent && ["À venir", true],
    ], d.comptes.map((x) => h("tr", { class: x.anciennes > 0 ? "en-alerte" : "" },
      h("td", {}, TYPES[x.type] || x.type),
      h("td", { class: "gras" }, x.nom || "—"),
      h("td", { class: "nombre" }, nb(x.demandes)),
      h("td", { class: "nombre" }, nb(x.anciennes)),
      h("td", {}, x.plus_ancienne ? UI.dateHeure(x.plus_ancienne) : "—"),
      argent ? h("td", { class: "nombre" }, UI.entier(x.attente)) : null,
      argent ? h("td", { class: "nombre" }, UI.entier(x.disponible)) : null,
      argent ? h("td", { class: "nombre" }, UI.entier(x.a_venir)) : null))) : null;

    UI.vider(zone, barre,
      UI.barrePeriode(periode, ROUTE + "/dettes"),
      h("p", { class: "doux petit" }, "Ce que BIZZOO doit aujourd'hui : les reversements demandés par les boutiques, les gains demandés par les livreurs, " +
        "les retraits demandés par les parrains, et ce qui leur est dû sans avoir encore été demandé. Une demande devient « ancienne » après " + j + " jour(s). " +
        "La décision (valider, refuser) se prend dans BIZZOO Admin. La période ne sert qu'au théorique et à ce qui a été versé." +
        (montantsCaches(argent) || "")),
      h("div", { class: "tuiles compactes" },
        argent ? tuile(UI.fcfa(t.reel), "dette réelle aujourd'hui", t.reel > 0) : null,
        tuile(nb(t.demandes), "demandes en attente", t.anciennes > 0),
        tuile(nb(t.anciennes), "dont plus de " + j + " jour(s)", t.anciennes > 0),
        tuile(nb(t.demandes_boutiques) + " · " + nb(t.demandes_livreurs) + " · " + nb(t.demandes_parrains), "boutiques · livreurs · parrains"),
        tuile(t.plus_ancienne ? UI.quand(t.plus_ancienne) : "—", "la plus ancienne"),
        argent ? tuile(UI.fcfa(t.attente_boutiques + t.attente_livreurs + t.attente_parrains), "demandé, en attente") : null,
        argent ? tuile(UI.fcfa(t.disponible_boutiques + t.disponible_livreurs + t.disponible_parrains), "dû sans demande") : null,
        argent ? tuile(UI.fcfa(t.a_venir_boutiques), "à venir (articles pas encore livrés)") : null,
        argent ? tuile(UI.fcfa(t.theorique_periode), "théorique de la période (prix BIZZOO des articles payés)") : null,
        argent ? tuile(UI.fcfa(t.verse_periode), "réellement versé sur la période") : null),
      argent ? h("p", { class: "doux petit" }, "Boutiques : livré au prix BIZZOO, moins les espèces qu'elles ont déjà touchées, moins leurs reversements. " +
        "Livreurs : gains crédités, moins leurs reversements. Parrains : commissions, moins leurs retraits.") : null,
      demandes, comptes);
  }

  /* ---------- Les remboursements ---------- */

  async function remboursements(zone, barre, params) {
    const periode = VueStatistiques.periodeDe(params, "30j");
    const d = await Supabase.rpc("rh_remboursements_liste", { depuis: periode.depuis, jusqu: periode.jusqu });
    if (!zone.isConnected) return;
    const t = d.totaux, argent = d.montants;
    const filtre = params.filtre || "a_rembourser";
    const garder = (l) => filtre === "tous" || (filtre === "en_retard" ? l.en_retard : filtre === "rembourse" ? l.statut === "rembourse" : l.statut !== "rembourse");
    const lignes = d.lignes.filter(garder);
    const aller = (v) => { location.hash = ROUTE + "/remboursements" + (periode.suffixe || "?p=30j") + "&filtre=" + v; };

    const noter = async (l, bouton) => {
      const r = await UI.formulaire({
        titre: "Remboursement fait — " + (l.numero || l.commande),
        texte: "Il reste " + UI.fcfa(l.reste) + " à rendre au client. Notez ce qui lui a été rendu, et comment : la référence de la transaction prouve le remboursement.",
        champs: [
          { nom: "montant", libelle: "Montant rendu (FCFA)", type: "number", requis: true, min: 1, max: l.reste, valeur: l.reste },
          { nom: "mode", libelle: "Comment", type: "select", requis: true, valeur: "mobile_money",
            options: Object.entries(MODES).map(([valeur, libelle]) => ({ valeur, libelle })) },
          { nom: "reference", libelle: "Référence de la transaction", aide: "obligatoire pour Mobile Money et virement" },
          { nom: "note", libelle: "Note", type: "textarea" },
        ],
        valider: "Enregistrer",
        verifier: (v) => {
          const m = Number(v.montant);
          if (!(m > 0)) return "Le montant doit être positif.";
          if (m > l.reste) return "Il ne reste que " + UI.fcfa(l.reste) + " à rendre.";
          if ((v.mode === "mobile_money" || v.mode === "virement") && v.reference.length < 4) return "Notez la référence de la transaction.";
          return null;
        },
      });
      if (!r) return;
      await UI.agir(bouton, () => Supabase.rpc("rh_rembourser", {
        cible: l.commande, v_montant: Number(r.montant), v_mode: r.mode, v_reference: r.reference, v_note: r.note }), "Remboursement noté.");
      App.rafraichir();
      remboursements(zone, barre, params);
    };

    const STATUTS = { a_rembourser: ["À rembourser", "orange"], partiel: ["Remboursé en partie", "orange"], rembourse: ["Remboursé", "vert"] };
    const detail = lignes.length ? tableau("Commande par commande", [
      ["Commande"], ["Client"], ["Annulé"], ["Boutique"], ["Depuis"], ["Où il en est"],
      argent && ["Dû", true], argent && ["Rendu", true], argent && ["Reste", true], ["Remboursements"], [""],
    ], lignes.map((l) => h("tr", { class: l.en_retard ? "en-alerte" : "" },
      h("td", { class: "gras" }, lienCommande(l.commande, l.numero),
        l.etat === "annulee" ? h("div", { class: "tres-petit doux" }, "commande entière annulée") : null),
      h("td", {}, h("div", {}, l.client || "—"), h("div", { class: "tres-petit doux" }, l.tel || "")),
      h("td", { class: "petit" }, l.annule_le ? UI.dateHeure(l.annule_le) : "date inconnue",
        h("div", { class: "tres-petit doux" }, l.annule_par ? "par " + l.annule_par : "auteur inconnu (annulation ancienne)")),
      h("td", { class: "petit" }, l.boutiques || "—"),
      h("td", {}, l.jours + " j"),
      h("td", {}, h("div", { class: "actions" }, UI.etiquette(...(STATUTS[l.statut] || [l.statut, ""])),
        l.en_retard ? UI.etiquette("En retard", "rouge") : null)),
      argent ? h("td", { class: "nombre" }, UI.entier(l.du)) : null,
      argent ? h("td", { class: "nombre" }, UI.entier(l.rendu)) : null,
      argent ? h("td", { class: "nombre" }, UI.entier(l.reste)) : null,
      h("td", { class: "petit" }, l.faits.length ? l.faits.map((f) => h("div", {},
        (MODES[f.mode] || f.mode) + (argent ? " · " + UI.fcfa(f.montant) + (f.reference ? " · " + f.reference : "") : "") +
        " — " + UI.dateHeure(f.le) + (f.par ? ", " + f.par : ""))) : "—"),
      h("td", {}, argent && l.reste > 0 ? h("button", { class: "btn btn-second btn-petit", onclick: (ev) => noter(l, ev.currentTarget) }, "Noter le remboursement") : null))))
      : UI.vide(d.lignes.length ? "Rien dans ce filtre." : "Aucun client à rembourser.");

    const boutiques = d.boutiques.length ? tableau("Boutiques qui annulent après paiement (sur la période)", [
      ["Boutique"], ["Articles annulés", true], ["Commandes touchées", true], argent && ["Valeur annulée", true],
    ], d.boutiques.map((b) => h("tr", {},
      h("td", { class: "gras" }, b.boutique), h("td", { class: "nombre" }, nb(b.lignes)), h("td", { class: "nombre" }, nb(b.commandes)),
      argent ? h("td", { class: "nombre" }, UI.entier(b.valeur)) : null))) : null;

    UI.vider(zone, barre,
      UI.barrePeriode(periode, ROUTE + "/remboursements", "&filtre=" + filtre),
      h("p", { class: "doux petit" }, "Quand un article ou une commande déjà payés sont annulés et que le client a versé plus que ce qui lui sera servi, " +
        "il entre seul dans cette file. Il passe « en retard » après " + d.seuils.remboursement_j + " jour(s) sans remboursement noté. " +
        "Qui a annulé n'est connu que pour les annulations faites depuis la mise en place de ce contrôle." +
        (argent ? "" : " Numéros masqués et sans les montants : l'administration note les remboursements.")),
      h("div", { class: "tuiles compactes" },
        tuile(nb(t.a_rembourser), "clients à rembourser", t.a_rembourser > 0),
        tuile(nb(t.en_retard), "en retard", t.en_retard > 0),
        tuile(nb(t.rembourses), "remboursés sur la période"),
        tuile(t.plus_ancien ? UI.quand(t.plus_ancien) : "—", "le plus ancien à rembourser"),
        argent ? tuile(UI.fcfa(t.reste_total), "reste à rendre", t.reste_total > 0) : null,
        argent ? tuile(UI.fcfa(t.rendu_periode), "rendu sur la période") : null),
      filtres([["a_rembourser", "À rembourser"], ["en_retard", "En retard"], ["rembourse", "Remboursés"], ["tous", "Tout"]], filtre, aller),
      detail, boutiques);
  }

  /* ---------- Les gestes faits dans BIZZOO Admin ---------- */

  async function gestes(zone, barre, params) {
    const periode = VueStatistiques.periodeDe(params, "7j");
    const famille = params.famille || "";
    const sensibles = params.sensibles === "1";
    const d = await Supabase.rpc("rh_gestes", { depuis: periode.depuis, jusqu: periode.jusqu,
      v_famille: famille || null, v_sensibles: sensibles });
    if (!zone.isConnected) return;
    const t = d.totaux;
    const extra = (f, s) => (f ? "&famille=" + encodeURIComponent(f) : "") + (s ? "&sensibles=1" : "");
    const aller = (f, s) => { location.hash = ROUTE + "/gestes" + (periode.suffixe || "?p=7j") + extra(f, s); };

    const auteurs = d.auteurs.length ? tableau("Qui a fait quoi", [["Compte"], ["Gestes", true], ["Sensibles", true], ["Le dernier"]],
      d.auteurs.map((a) => h("tr", { class: a.sensibles > 0 ? "en-alerte" : "" },
        h("td", { class: "gras" }, a.qui), h("td", { class: "nombre" }, nb(a.gestes)), h("td", { class: "nombre" }, nb(a.sensibles)),
        h("td", {}, UI.dateHeure(a.dernier))))) : null;

    const liste = d.lignes.length ? h("div", { class: "liste" }, d.lignes.map((x) => h("div", { class: "element" + (x.raisons.length ? " en-alerte" : "") },
      h("div", { class: "etire" },
        h("div", { class: "ligne" },
          h("span", { class: "gras etire" }, x.libelle || (x.famille + " — " + x.action)),
          h("div", { class: "actions" }, x.raisons.map((r) => UI.etiquette(...(RAISONS[r] || [r, ""]))))),
        h("div", { class: "petit doux" }, [UI.dateHeure(x.le), x.qui || "compte inconnu", x.famille + " · " + x.action,
          x.boutique, x.annule_le ? "annulé le " + UI.dateHeure(x.annule_le) + (x.annule_par ? " par " + x.annule_par : "") : null].filter(Boolean).join(" · ")),
        x.retour ? h("details", { class: "petit" }, h("summary", {}, "État d'avant"), h("pre", { class: "tres-petit", style: { whiteSpace: "pre-wrap", wordBreak: "break-all" } }, x.retour)) : null))))
      : UI.vide("Aucun geste sur cette période" + (famille || sensibles ? " dans ce filtre." : "."));

    UI.vider(zone, barre,
      UI.barrePeriode(periode, ROUTE + "/gestes", extra(famille, sensibles)),
      h("div", { class: "carte compacte" }, h("p", { class: "petit" },
        h("b", {}, "Ce journal est écrit par l'écran de BIZZOO Admin. "),
        "Une modification faite ailleurs (éditeur SQL de Supabase, fonctions du serveur, accès direct à la base) n'y figure pas. " +
        "Sensible : une suppression, un compte, un prix, une marge ou un paiement, un geste la nuit (22 h – 6 h), un geste annulé ensuite, " +
        "ou dix gestes ou plus du même compte dans la même heure." + (d.tout_voir ? "" : " L'état d'avant chaque geste est réservé au CEO."))),
      h("div", { class: "tuiles compactes" },
        tuile(nb(t.gestes), "gestes"),
        tuile(nb(t.sensibles), "sensibles", t.sensibles > 0),
        tuile(nb(t.suppressions), "suppressions", t.suppressions > 0),
        tuile(nb(t.argent), "touchent à l'argent", t.argent > 0),
        tuile(nb(t.nuit), "faits la nuit", t.nuit > 0),
        tuile(nb(t.annules), "annulés ensuite"),
        tuile(nb(t.auteurs), "comptes")),
      h("div", { class: "filtres" },
        h("button", { class: sensibles ? "actif" : "", onclick: () => aller(famille, !sensibles) }, sensibles ? "Sensibles seulement ✓" : "Sensibles seulement"),
        h("button", { class: famille ? "" : "actif", onclick: () => aller("", sensibles) }, "Toutes les familles"),
        d.familles.map((f) => h("button", { class: f.famille === famille ? "actif" : "", onclick: () => aller(f.famille, sensibles) },
          f.famille + " (" + f.nb + ")"))),
      auteurs, liste);
  }

  /* ---------- Les codes promo et le parrainage ---------- */

  async function codes(zone, barre, params) {
    const periode = VueStatistiques.periodeDe(params, "30j");
    const d = await Supabase.rpc("rh_codes_surveillance", { depuis: periode.depuis, jusqu: periode.jusqu });
    if (!zone.isConnected) return;
    const t = d.totaux, argent = d.montants;

    const abus = d.abus.length ? h("div", { class: "carte pile" },
      h("h3", {}, "Abus probables"),
      h("div", { class: "liste" }, d.abus.map((a) => h("div", { class: "element en-alerte" },
        h("div", { class: "etire" },
          h("div", { class: "ligne" }, h("span", { class: "gras etire" }, a.code + " — " + a.detail),
            UI.etiquette(a.type === "propre_code" ? "Son propre code" : a.comptes + " comptes", "rouge")),
          h("div", { class: "petit doux" }, nb(a.commandes) + " commande(s) : " + a.liste.join(", ") +
            (a.numeros.length ? " · numéros " + a.numeros.filter(Boolean).join(", ") : "") +
            (argent ? " · remises " + UI.fcfa(a.remise) : ""))))))) : null;

    const listeCodes = d.codes.length ? tableau("Code par code", [
      ["Code"], ["État"], ["Usages", true], ["Clients", true], ["Au total", true],
      argent && ["Valeur"], argent && ["Coût", true], argent && ["Ventes", true], argent && ["Commissions", true],
    ], d.codes.map((c) => h("tr", { class: c.signalements > 0 ? "en-alerte" : "" },
      h("td", {}, h("div", { class: "gras" }, c.code), c.libelle ? h("div", { class: "tres-petit doux" }, c.libelle) : null,
        c.particulier ? UI.etiquette("Parrain", "bleu") : null, c.signalements > 0 ? UI.etiquette("Signalé", "rouge") : null),
      h("td", { class: "petit" }, (c.actif ? "actif" : "inactif") + (c.fin ? " · jusqu'au " + UI.date(c.fin) : "") +
        (c.maximum ? " · " + c.maximum + " max." : "")),
      h("td", { class: "nombre" }, nb(c.usages)),
      h("td", { class: "nombre" }, nb(c.clients)),
      h("td", { class: "nombre" }, nb(c.usages_total)),
      argent ? h("td", {}, c.mode === "montant" ? UI.fcfa(c.valeur) : c.valeur !== null && c.valeur !== undefined ? Number(c.valeur) + " %" : "—") : null,
      argent ? h("td", { class: "nombre" }, UI.entier(c.cout)) : null,
      argent ? h("td", { class: "nombre" }, UI.entier(c.ventes)) : null,
      argent ? h("td", { class: "nombre" }, UI.entier(c.commissions)) : null)))
      : UI.vide("Aucun code utilisé ni actif.");

    const parrains = d.parrains.length ? tableau("Les parrains", [
      ["Codes"], argent && ["Nom"], ["Numéro"], ["Usages", true], ["Retraits demandés", true],
      argent && ["Commissions (période)", true], argent && ["Commissions (total)", true], argent && ["Retiré", true], argent && ["Reste dû", true],
    ], d.parrains.map((p) => h("tr", { class: p.propre_code ? "en-alerte" : "" },
      h("td", {}, h("div", { class: "gras" }, p.codes), p.propre_code ? UI.etiquette("Use son propre code", "rouge") : null),
      argent ? h("td", {}, p.nom || "—") : null,
      h("td", {}, p.tel || "—"),
      h("td", { class: "nombre" }, nb(p.usages)),
      h("td", { class: "nombre" }, nb(p.demandes)),
      argent ? h("td", { class: "nombre" }, UI.entier(p.commissions_periode)) : null,
      argent ? h("td", { class: "nombre" }, UI.entier(p.commissions_total)) : null,
      argent ? h("td", { class: "nombre" }, UI.entier(p.retire)) : null,
      argent ? h("td", { class: "nombre" }, UI.entier(p.disponible)) : null))) : null;

    UI.vider(zone, barre,
      UI.barrePeriode(periode, ROUTE + "/codes"),
      h("p", { class: "doux petit" }, "Les commandes payées avec un code sur la période. Abus probables : un même code, plusieurs comptes et une même position " +
        "(à 100 m près) ou une même adresse de livraison ; un parrain qui achète avec son propre code. Les numéros ne montrent que leurs 4 derniers chiffres. " +
        "Un code expiré qu'un client tente encore n'est noté nulle part." + (montantsCaches(argent) || "")),
      h("div", { class: "tuiles compactes" },
        tuile(nb(t.usages), "commandes avec un code"),
        tuile(nb(t.codes), "codes utilisés"),
        tuile(nb(t.clients), "clients"),
        tuile(nb(t.abus), "abus probables", t.abus > 0),
        argent ? tuile(UI.fcfa(t.cout), "coût des remises") : null,
        argent ? tuile(UI.fcfa(t.ventes), "ventes avec un code") : null,
        argent ? tuile(UI.fcfa(t.commissions), "commissions des parrains") : null),
      abus, listeCodes, parrains);
  }

  /* ---------- Les seuils de l'argent (dans l'onglet Seuils) ---------- */

  async function formSeuils() {
    const s = await Supabase.rpc("rh_argent_seuils");
    const champ = (nom, libelle, aide, min, max) => {
      const e = h("input", { type: "number", min, max, value: s[nom], required: true });
      e.name = nom;
      return h("label", { class: "champ" }, h("span", {}, libelle), e, h("small", {}, aide));
    };
    const form = h("form", { class: "carte pile" },
      h("h2", {}, "Paiements, dettes et remboursements"),
      h("div", { class: "formulaire" },
        champ("annonce_min", "« J'ai payé » sans preuve (minutes)", "au-delà, le paiement est à rapprocher", 5, 1440),
        champ("dette_j", "Demande d'argent ancienne (jours)", "reversement, gains ou retrait qui attend trop", 1, 60),
        champ("remboursement_j", "Remboursement en retard (jours)", "après l'annulation, sans remboursement noté", 1, 60)),
      h("div", { class: "actions" }, h("button", { class: "btn", type: "submit" }, "Enregistrer")));
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const v = (n) => Number(form.querySelector("[name=" + n + "]").value);
      await UI.agir(ev.submitter, () => Supabase.rpc("rh_argent_regler", {
        v_annonce_min: v("annonce_min"), v_dette_j: v("dette_j"), v_remboursement_j: v("remboursement_j") }), "Seuils enregistrés.");
      App.rafraichir();
    });
    return form;
  }

  return { paiements, dettes, remboursements, gestes, codes, formSeuils };
})();
