/* =========================================================
   Contrôles — ce qui touche à l'argent sans que personne ne le dise.

   #/controles/reglages      : l'historique des réglages sensibles
                               (code MoMoPay, bac à sable, paiement
                               fermé, tarifs, numéros de réception) ;
                               le CEO et le superadministrateur les
                               disent « vu et approuvé » ;
   #/controles/encaissements : les restes payés à la livraison qui
                               attendent (MoMoPay pas vérifié, espèces
                               pas rendues, livraisons sans déclaration),
                               les écarts et les contestations, par
                               livreur (?p=30j, ou ?du=…&au=…) ;
   #/controles/seuils        : les seuils de ces contrôles ;
   #/controles/paiements, dettes, remboursements, gestes, codes :
                               l'argent (js/vues/argent.js).

   L'administration et le superadministrateur voient tout, montants
   compris. Un profil à qui Paramètres ouvre « controles » ne voit que
   les encaissements, en nombres et en ancienneté. C'est la base qui
   décide (rh_controles_acces) : l'écran ne fait que suivre.
   ========================================================= */
const VueControles = (() => {
  const { h } = UI;
  const ROUTE = "#/controles";
  const STATUTS = {
    momopay_a_verifier: ["MoMoPay à vérifier", "orange"],
    especes_non_remises: ["Espèces pas rendues", "orange"],
    non_declare: ["Livré sans déclaration", "rouge"],
    ecart: ["Écart dû / déclaré", "rouge"],
    conteste: ["Contesté par le client", "rouge"],
    regle: ["Réglé", "vert"],
  };
  const tuile = (valeur, libelle, alerte) => h("div", { class: "tuile" + (alerte ? " alerte" : "") }, h("b", {}, valeur), h("span", {}, libelle));
  /** « 52 h » ou « 3 j 4 h » : l'ancienneté d'un encaissement. */
  const anciennete = (heures) => {
    const n = Number(heures || 0);
    if (n < 48) return n + " h";
    const j = Math.floor(n / 24);
    return j + " j " + (n - j * 24) + " h";
  };
  const voitFiche = () => App.ouvert("livreurs") || App.ouvert("stats_livreurs") || App.estSuper();

  /* Les onglets ouverts : ceux du lot des encaissements (rh_controles_compteurs)
     et ceux de l'argent (rh_argent_compteurs). Chacun a son droit ; la base
     refuse de toute façon ce que l'écran montrerait à tort. */
  function ouverts(c, a) {
    const o = (a && a.onglets) || {};
    const items = [];
    if (c.acces === "admin") items.push(["reglages", "Réglages sensibles", c.reglages_a_approuver]);
    if (c.acces) items.push(["encaissements", "Encaissements", c.encaissements_anciens]);
    if (o.paiements) items.push(["paiements", "Paiements à rapprocher", a.paiements_a_traiter]);
    if (o.remboursements) items.push(["remboursements", "Remboursements", a.remboursements_en_retard]);
    if (o.dettes) items.push(["dettes", "À payer", a.dettes_anciennes]);
    if (o.codes) items.push(["codes", "Codes promo", 0]);
    if (o.gestes) items.push(["gestes", "Gestes Admin", 0]);
    if (c.acces === "admin") items.push(["seuils", "Seuils", 0]);
    return items;
  }

  function onglets(c, actif) {
    const items = ouverts(c, c.argent);
    return h("div", { class: "filtres" }, items.map(([v, l, n]) =>
      h("button", { class: v === actif ? "actif" : "", onclick: () => { location.hash = ROUTE + "/" + v; } },
        l, n > 0 ? h("span", { class: "pastille", style: { marginLeft: "6px" } }, n > 99 ? "99+" : n) : null)));
  }

  async function afficher(zone, morceaux, params) {
    const [c, a] = await Promise.all([
      Supabase.rpc("rh_controles_compteurs"),
      Supabase.rpc("rh_argent_compteurs").catch(() => ({})),
    ]);
    if (!zone.isConnected) return;
    const k = Object.assign({}, c || {}, { argent: a || {} });
    const items = ouverts(k, k.argent);
    if (!items.length) {
      UI.vider(zone, UI.vide("Votre compte n'a pas accès aux contrôles."));
      return;
    }
    const permis = items.map((x) => x[0]);
    const page = permis.includes(morceaux[0]) ? morceaux[0] : permis[0];
    const barre = () => onglets(k, page);
    if (page === "reglages") return reglages(zone, k, params);
    if (page === "seuils") return seuils(zone, k);
    if (page === "encaissements") return encaissements(zone, k, params);
    return VueArgent[page](zone, barre(), params);
  }

  /* ---------- Les réglages sensibles ---------- */

  async function reglages(zone, c, params) {
    const tous = params.tous === "1";
    const d = await Supabase.rpc("rh_audit_reglages_liste", { seulement_a_approuver: !tous });
    if (!zone.isConnected) return;
    const choisis = new Set();
    const approuver = h("button", { class: "btn btn-vert btn-petit", disabled: true, onclick: async (ev) => {
      const bouton = ev.currentTarget;
      if (!(await UI.confirmer("Vous avez vérifié " + choisis.size + " changement(s) : ils étaient voulus. Ils quitteront la liste des alertes.",
        { titre: "Vu et approuvé", valider: "Approuver" }))) return;
      await UI.agir(bouton, () => Supabase.rpc("rh_audit_approuver", { ids: [...choisis] }), "Changement(s) approuvé(s).");
      App.rafraichir();
      // Les compteurs relus : la pastille de l’onglet garderait sinon
      // l’ancien nombre, alors que tout vient d’être approuvé.
      afficher(zone, ["reglages"], params);
    } }, UI.icone("check", "ic-sm"), "Vu et approuvé");
    const majBouton = () => {
      approuver.disabled = choisis.size === 0;
      approuver.lastChild.textContent = choisis.size ? "Vu et approuvé (" + choisis.size + ")" : "Vu et approuvé";
    };
    const enAttente = d.changements.filter((x) => !x.approuve_le);
    const toutCocher = d.approuver && enAttente.length ? h("button", { class: "btn btn-second btn-petit", onclick: () => {
      const tousCoches = enAttente.every((x) => choisis.has(x.id));
      for (const x of enAttente) tousCoches ? choisis.delete(x.id) : choisis.add(x.id);
      zone.querySelectorAll("input[data-audit]").forEach((e) => { e.checked = choisis.has(Number(e.dataset.audit)); });
      majBouton();
    } }, "Tout cocher") : null;

    const liste = d.changements.length ? h("div", { class: "liste" }, d.changements.map((x) => {
      const coche = d.approuver && !x.approuve_le ? h("input", { type: "checkbox", "data-audit": x.id, onchange: (ev) => {
        if (ev.currentTarget.checked) choisis.add(x.id); else choisis.delete(x.id);
        majBouton();
      } }) : null;
      return h(coche ? "label" : "div", { class: "element" },
        coche,
        h("div", { class: "etire" },
          h("div", { class: "ligne" },
            h("span", { class: "gras etire" }, x.libelle + (x.boutique ? " — " + x.boutique : "")),
            x.approuve_le ? UI.etiquette("Approuvé", "vert") : UI.etiquette("À approuver", x.critique ? "rouge" : "orange")),
          h("div", { class: "petit" }, h("span", { class: "doux" }, "Avant : "), x.avant, h("span", { class: "doux" }, "  →  Après : "), h("b", {}, x.apres)),
          h("div", { class: "petit doux" }, UI.dateHeure(x.le) + " · par " + (x.par || "inconnu") +
            (x.approuve_le ? " · approuvé le " + UI.dateHeure(x.approuve_le) + (x.approuve_par ? " par " + x.approuve_par : "") : ""))));
    })) : UI.vide(tous ? "Aucun changement de réglage n'a encore été noté." : "Aucun changement en attente : tout a été vu et approuvé.");

    UI.vider(zone,
      onglets(c, "reglages"),
      h("p", { class: "doux petit" }, "Chaque changement du paiement (mode essai, paiement fermé, agrégateur, code MoMoPay, tarifs), du compte obligatoire et des numéros de réception des boutiques, avec son auteur. " +
        (d.approuver ? "Cochez ce que vous avez vérifié, puis « Vu et approuvé » : l'alerte disparaît." : "Le CEO ou le superadministrateur les approuve ; vous les lisez.") +
        " Les codes et numéros sont tronqués."),
      h("div", { class: "ligne" },
        h("div", { class: "filtres" },
          h("button", { class: tous ? "" : "actif", onclick: () => { location.hash = ROUTE + "/reglages"; } }, "À approuver (" + d.a_approuver + ")"),
          h("button", { class: tous ? "actif" : "", onclick: () => { location.hash = ROUTE + "/reglages?tous=1"; } }, "Tout l'historique")),
        h("span", { class: "etire" }),
        toutCocher, d.approuver ? approuver : null),
      liste);
  }

  /* ---------- Les encaissements ---------- */

  async function encaissements(zone, c, params) {
    const periode = VueStatistiques.periodeDe(params, "30j");
    const d = await Supabase.rpc("rh_encaissements", { depuis: periode.depuis, jusqu: periode.jusqu });
    if (!zone.isConnected) return;
    const t = d.totaux, s = d.seuils, argent = d.montants;
    const filtre = params.filtre || "tous";
    const FILTRES = [
      ["tous", "Tout"],
      ["momopay_a_verifier", "MoMoPay à vérifier"],
      ["especes_non_remises", "Espèces pas rendues"],
      ["non_declare", "Sans déclaration"],
      ["ecart", "Écarts"],
      ["conteste", "Contestés"],
    ];
    const garder = (l) => filtre === "tous" || (filtre === "ecart" ? l.ecart : filtre === "conteste" ? l.conteste : l.statut === filtre);
    const lignes = d.lignes.filter(garder);
    const suffixe = periode.suffixe || "";

    const parLivreur = d.livreurs.length ? h("div", { class: "carte defile" },
      h("h3", { style: { marginBottom: "8px" } }, "Par livreur"),
      h("table", { class: "tableau" },
        h("thead", {}, h("tr", {}, h("th", {}, "Livreur"), h("th", { class: "nombre" }, "En attente"),
          h("th", { class: "nombre" }, "Anciens"), h("th", {}, "Le plus ancien"), h("th", { class: "nombre" }, "Écarts"),
          h("th", { class: "nombre" }, "Contestés"), argent ? h("th", { class: "nombre" }, "Montant en attente") : null, h("th", {}, ""))),
        h("tbody", {}, d.livreurs.map((l) => h("tr", { class: l.au_plafond ? "en-alerte" : "" },
          h("td", {}, h("div", { class: "gras" }, l.nom), h("div", { class: "tres-petit doux" }, [l.boutique ? "Livreur de " + l.boutique : "Livreur BIZZOO", l.tel].filter(Boolean).join(" · ")),
            l.bloque ? UI.etiquette("Bloqué", "rouge") : l.au_plafond ? UI.etiquette("Plafond atteint", "rouge") : null),
          h("td", { class: "nombre" }, UI.entier(l.en_attente)),
          h("td", { class: "nombre" }, UI.entier(l.anciens)),
          h("td", {}, l.plus_ancien ? UI.dateHeure(l.plus_ancien) : "—"),
          h("td", { class: "nombre" }, UI.entier(l.ecarts)),
          h("td", { class: "nombre" }, UI.entier(l.contestes)),
          argent ? h("td", { class: "nombre" }, UI.entier(l.montant)) : null,
          h("td", {}, l.id && voitFiche() ? h("a", { class: "btn btn-second btn-petit", href: "#/liste-livreurs/" + l.id },
            l.au_plafond && !l.bloque && App.estAdmin() ? "Fiche et blocage" : "Sa fiche") : null)))))) : null;

    const detail = lignes.length ? h("div", { class: "carte defile" },
      h("h3", { style: { marginBottom: "8px" } }, "Encaissement par encaissement" + (d.lignes.length >= 500 ? " (les 500 premiers)" : "")),
      h("table", { class: "tableau" },
        h("thead", {}, h("tr", {}, h("th", {}, "Commande"), h("th", {}, "Boutique"), h("th", {}, "Livreur"), h("th", {}, "Déclaré le"),
          h("th", {}, "Depuis"), h("th", {}, "Où il en est"),
          argent ? h("th", { class: "nombre" }, "Dû") : null, argent ? h("th", { class: "nombre" }, "Déclaré") : null,
          argent ? h("th", {}, "Transaction") : null)),
        h("tbody", {}, lignes.map((l) => h("tr", { class: l.ancien ? "en-alerte" : "" },
          h("td", { class: "gras" }, App.ouvert("suivi") ? h("a", { href: "#/suivi/commande/" + encodeURIComponent(l.commande) }, l.numero || l.commande) : (l.numero || l.commande)),
          h("td", {}, l.boutique || "—"),
          h("td", {}, l.livreur),
          h("td", {}, UI.dateHeure(l.le)),
          h("td", {}, l.remis_le ? "—" : anciennete(l.heures)),
          h("td", {}, h("div", { class: "actions" },
            UI.etiquette(...(STATUTS[l.statut] || [l.statut, ""])),
            l.ecart && l.statut !== "ecart" ? UI.etiquette("Écart", "rouge") : null,
            l.conteste && l.statut !== "conteste" ? UI.etiquette("Contesté", "rouge") : null,
            l.ancien ? UI.etiquette("Ancien", "rouge") : null)),
          argent ? h("td", { class: "nombre" }, UI.entier(l.du)) : null,
          argent ? h("td", { class: "nombre" }, UI.entier(l.montant)) : null,
          argent ? h("td", {}, l.transaction || "—") : null)))))
      : UI.vide(d.lignes.length ? "Rien dans ce filtre." : "Aucun encaissement en attente, aucun écart : tout est en ordre.");

    UI.vider(zone,
      onglets(c, "encaissements"),
      UI.barrePeriode(periode, ROUTE + "/encaissements", filtre !== "tous" ? "&filtre=" + filtre : ""),
      h("p", { class: "doux petit" }, "Ce qui attend s'affiche quelle que soit la période ; les écarts et contestations, ceux de la période. " +
        "« Ancien » : un MoMoPay pas vérifié après " + s.momopay_h + " h, des espèces pas rendues après " + s.especes_h +
        " h. Un livreur est signalé à " + s.plafond_nb + " anciens. Le MoMoPay se vérifie dans BIZZOO Admin, menu Caisse (« Vérifié »)." +
        (argent ? "" : " Sans les montants, réservés à l'administration.")),
      h("div", { class: "tuiles compactes" },
        tuile(UI.entier(t.momopay_a_verifier), "MoMoPay à vérifier", t.momopay_anciens > 0),
        tuile(UI.entier(t.momopay_anciens), "dont après " + s.momopay_h + " h", t.momopay_anciens > 0),
        tuile(UI.entier(t.especes_non_remises), "espèces pas encore rendues", t.especes_anciennes > 0),
        tuile(UI.entier(t.non_declares), "livrés sans déclaration", t.non_declares > 0),
        tuile(UI.entier(t.ecarts), "écarts entre dû et déclaré", t.ecarts > 0),
        tuile(UI.entier(t.contestes), "contestés par le client", t.contestes > 0),
        tuile(UI.entier(t.verifies), "MoMoPay vérifiés sur la période"),
        tuile(t.plus_ancien ? UI.quand(t.plus_ancien) : "—", "le plus ancien en attente"),
        argent ? tuile(UI.fcfa(t.montant_a_verifier), "MoMoPay à retrouver", t.montant_a_verifier > 0) : null,
        argent ? tuile(UI.fcfa(t.montant_especes + t.montant_non_declare), "espèces et non déclarés", t.montant_especes + t.montant_non_declare > 0) : null,
        argent && t.ecart_total ? tuile(UI.fcfa(t.ecart_total), "manque (dû moins déclaré)", true) : null),
      parLivreur,
      h("div", { class: "filtres" }, FILTRES.map(([v, l]) =>
        h("button", { class: v === filtre ? "actif" : "", onclick: () => {
          location.hash = ROUTE + "/encaissements" + (suffixe || "?p=30j") + (v !== "tous" ? "&filtre=" + v : "");
        } }, l))),
      detail);
  }

  /* ---------- Les seuils ---------- */

  async function seuils(zone, c) {
    const d = await Supabase.rpc("rh_encaissements", {});
    if (!zone.isConnected) return;
    const s = d.seuils;
    const champ = (nom, libelle, aide, min, max) => {
      const e = h("input", { type: "number", min, max, value: s[nom], required: true });
      e.name = nom;
      return h("label", { class: "champ" }, h("span", {}, libelle), e, h("small", {}, aide));
    };
    const form = h("form", { class: "carte pile" },
      h("h2", {}, "Encaissements à la livraison"),
      h("div", { class: "formulaire" },
        champ("momopay_h", "MoMoPay pas vérifié (heures)", "au-delà, il devient « ancien » et lève l'alerte du suivi", 1, 720),
        champ("especes_h", "Espèces pas rendues (heures)", "au-delà, elles deviennent « anciennes »", 1, 720),
        champ("plafond_nb", "Plafond par livreur", "nombre d'encaissements anciens qui signalent le livreur", 1, 100)),
      h("div", { class: "actions" }, h("button", { class: "btn", type: "submit" }, "Enregistrer")));
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const v = (n) => Number(form.querySelector("[name=" + n + "]").value);
      await UI.agir(ev.submitter, () => Supabase.rpc("rh_controles_regler", {
        v_momopay_h: v("momopay_h"), v_especes_h: v("especes_h"), v_plafond_nb: v("plafond_nb") }), "Seuils enregistrés.");
      App.rafraichir();
    });
    const argent = await VueArgent.formSeuils().catch(() => null);
    if (!zone.isConnected) return;
    UI.vider(zone, onglets(c, "seuils"), form, argent,
      h("p", { class: "doux petit" }, "La veille des livreurs (course sans livreur, livreur sans position) se règle avec les autres délais : Suivi commandes, onglet Réglages."));
  }

  return { titre: "Contrôles", afficher };
})();
