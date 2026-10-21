/* =========================================================
   Paie — les fiches de paie de chaque mois.

   Le dernier jour du mois, la base calcule toute seule les
   fiches de tous les employés en poste (et l'application
   rattrape à l'ouverture un mois oublié). L'administration y
   ajoute primes, indemnités, retenues et avances ; chaque ajout
   recalcule la fiche. Le CEO valide le mois : les fiches sont
   alors figées, l'employé les voit, l'habilité les paie.

   AUCUN TAUX N'EST FOURNI. CNSS, impôt et autres cotisations
   se saisissent dans « Barèmes » et ne comptent qu'une fois
   validés par le CEO.
   ========================================================= */
const VuePaie = (() => {
  const { h } = UI;

  const STATUTS = { calculee: ["À valider", "orange"], validee: ["Validée", "bleu"], payee: ["Payée", "vert"] };
  const MODES = { especes: "Espèces", virement: "Virement", mobile_money: "Mobile Money", cheque: "Chèque" };
  const NATURES = { prime: "Prime", indemnite: "Indemnité", retenue: "Retenue" };
  const etiquette = (s) => UI.etiquette(...(STATUTS[s] || [s, ""]));

  /** « 2026-09-01 » du mois précédent si l'on est en début de mois, sinon du mois en cours. */
  function moisParDefaut() {
    const d = new Date();
    if (d.getDate() < 25) d.setMonth(d.getMonth() - 1, 1);
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-01";
  }
  const decaler = (mois, n) => {
    const [a, m] = mois.split("-").map(Number);
    const d = new Date(a, m - 1 + n, 1);
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-01";
  };

  function onglets(actif, mois) {
    const items = [["", "Fiches"]];
    if (App.estAdmin()) items.push(["elements", "Primes et retenues"], ["avances", "Avances"], ["baremes", "Barèmes"]);
    return h("div", { class: "filtres" }, items.map(([v, l]) =>
      h("button", { class: v === actif ? "actif" : "", onclick: () => {
        location.hash = "#/paie" + (v ? "/" + v : "") + (mois && v !== "baremes" && v !== "avances" ? "?mois=" + mois : "");
      } }, l)));
  }

  async function afficher(zone, morceaux, params) {
    UI.vider(zone, UI.chargement());
    const mois = params.mois || moisParDefaut();
    switch (morceaux[0]) {
      case "fiche": return fiche(zone, morceaux[1]);
      case "employe": return parEmploye(zone, morceaux[1]);
      case "elements": return elements(zone, mois);
      case "avances": return avances(zone);
      case "baremes": return baremes(zone);
      default: return fiches(zone, mois);
    }
  }

  function selecteurMois(mois, route) {
    return h("div", { class: "ligne" },
      h("button", { class: "btn-ic", "aria-label": "Mois précédent", onclick: () => { location.hash = route + "?mois=" + decaler(mois, -1); } }, UI.icone("retour")),
      h("b", { style: { minWidth: "150px", textAlign: "center" } }, UI.mois(mois)),
      h("button", { class: "btn-ic", "aria-label": "Mois suivant", disabled: decaler(mois, 1) > UI.premierDuMois(),
        onclick: () => { location.hash = route + "?mois=" + decaler(mois, 1); } }, UI.icone("chevron")));
  }

  /* ---------- Les fiches d'un mois ---------- */

  async function fiches(zone, mois) {
    const lignes = await Supabase.lire("rh_fiches_paie?select=id,employe_id,statut,brut,cotisations_salariales,impot,avances,retenues,net,charges_patronales,employe&mois=eq." + mois + "&order=employe->>nom");
    if (!zone.isConnected) return;
    const somme = (c) => lignes.reduce((t, l) => t + Number(l[c] || 0), 0);
    const aValider = lignes.filter((l) => l.statut === "calculee").length;
    const recharger = () => App.rafraichir().then(() => fiches(zone, mois));

    const actions = [];
    if (App.estAdmin()) {
      actions.push(h("button", { class: "btn btn-second", onclick: async (ev) => {
        const n = await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_generer_paie", { mois }));
        UI.succes(n + " fiche(s) calculée(s) pour " + UI.mois(mois).toLowerCase() + ".");
        recharger();
      } }, UI.icone("actualiser", "ic-sm"), lignes.length ? "Recalculer" : "Calculer la paie"));
    }
    if (App.estCeo() && aValider) {
      actions.push(h("button", { class: "btn btn-vert", onclick: async (ev) => {
        if (!await UI.confirmer("Valider les " + aValider + " fiche(s) de " + UI.mois(mois).toLowerCase() +
          " pour un net total de " + UI.fcfa(lignes.filter((l) => l.statut === "calculee").reduce((t, l) => t + Number(l.net), 0)) +
          " ? Elles seront figées, et chaque employé verra la sienne.", { valider: "Valider la paie" })) return;
        const n = await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_valider_paie", { mois }));
        UI.succes(n + " fiche(s) validée(s).");
        recharger();
      } }, UI.icone("check", "ic-sm"), "Valider la paie du mois"));
    }

    UI.vider(zone,
      onglets("", mois),
      h("div", { class: "titre-section" }, selecteurMois(mois, "#/paie"), h("div", { class: "actions" }, actions)),
      lignes.length ? h("div", { class: "tuiles" },
        h("div", { class: "tuile" }, h("b", { style: { fontSize: "17px" } }, UI.fcfa(somme("brut"))), h("span", {}, "masse salariale brute")),
        h("div", { class: "tuile" }, h("b", { style: { fontSize: "17px" } }, UI.fcfa(somme("net"))), h("span", {}, "net à payer")),
        h("div", { class: "tuile" }, h("b", { style: { fontSize: "17px" } }, UI.fcfa(somme("charges_patronales"))), h("span", {}, "charges patronales")),
        h("div", { class: "tuile" + (aValider ? " alerte" : "") }, h("b", {}, aValider), h("span", {}, "fiche(s) à valider"))) : null,
      lignes.length ? h("div", { class: "carte defile" }, h("table", { class: "tableau" },
        h("thead", {}, h("tr", {}, h("th", {}, "Employé"), h("th", { class: "nombre" }, "Brut"),
          h("th", { class: "nombre" }, "Retenues"), h("th", { class: "nombre" }, "Net"), h("th", {}, "État"), h("th", {}))),
        h("tbody", {}, lignes.map((l) => h("tr", {},
          h("td", {}, h("a", { href: "#/paie/fiche/" + l.id, class: "gras" }, UI.nomComplet(l.employe)),
            h("div", { class: "tres-petit doux" }, l.employe.matricule + (l.employe.poste ? " · " + l.employe.poste : ""))),
          h("td", { class: "nombre" }, UI.entier(l.brut)),
          h("td", { class: "nombre" }, UI.entier(Number(l.cotisations_salariales) + Number(l.impot) + Number(l.avances) + Number(l.retenues))),
          h("td", { class: "nombre gras" }, UI.entier(l.net)),
          h("td", {}, etiquette(l.statut)),
          h("td", {}, l.statut === "validee" && App.peutDecaisser()
            ? h("button", { class: "btn btn-orange btn-petit", onclick: (ev) => payer(ev.currentTarget, l, recharger) }, "Payer") : null)))),
        h("tfoot", {}, h("tr", {}, h("th", {}, "Total"), h("th", { class: "nombre" }, UI.entier(somme("brut"))),
          h("th", { class: "nombre" }, UI.entier(somme("cotisations_salariales") + somme("impot") + somme("avances") + somme("retenues"))),
          h("th", { class: "nombre" }, UI.entier(somme("net"))), h("th", {}), h("th", {})))))
        : UI.vide(App.estAdmin()
          ? "Aucune fiche pour ce mois. Elles se calculent seules le dernier jour du mois, ou tout de suite avec « Calculer la paie »."
          : "Aucune fiche validée pour ce mois."));
  }

  async function payer(bouton, l, suite) {
    const v = await UI.formulaire({ titre: "Payer " + UI.nomComplet(l.employe) + " : " + UI.fcfa(l.net), valider: "Confirmer le paiement",
      champs: [
        { nom: "mode", libelle: "Mode", type: "select", valeur: l.employe.mode_paiement || "especes",
          options: Object.entries(MODES).map(([valeur, libelle]) => ({ valeur, libelle })) },
        { nom: "reference", libelle: "Référence (n° de transaction, de virement…)" }] });
    if (!v) return;
    await UI.agir(bouton, () => Supabase.rpc("rh_payer_fiche", { fiche: l.id, mode: v.mode, reference: v.reference }), "Paiement enregistré.");
    suite();
  }

  /* ---------- Une fiche, imprimable ---------- */

  async function fiche(zone, id) {
    const [f] = await Supabase.lire("rh_fiches_paie?select=*&id=eq." + encodeURIComponent(id));
    if (!zone.isConnected) return;
    if (!f) return UI.vider(zone, UI.vide("Fiche introuvable."));
    const e = f.employe || {};
    App.titre("Paie " + UI.mois(f.mois).toLowerCase());
    const recharger = () => App.rafraichir().then(() => fiche(zone, id));

    const gains = f.lignes.filter((l) => ["base", "prime", "indemnite"].includes(l.genre));
    const retenues = f.lignes.filter((l) => ["cotisation", "impot", "retenue", "avance"].includes(l.genre));
    const taux = (t) => (t === undefined || t === null ? "" : String(t).replace(".", ",") + " %");
    const actions = [h("button", { class: "btn btn-second", onclick: () => window.print() }, UI.icone("imprimer", "ic-sm"), "Imprimer / PDF")];
    if (App.estCeo() && f.statut === "validee") {
      actions.push(h("button", { class: "btn btn-second", onclick: async (ev) => {
        if (!await UI.confirmer("Rouvrir cette fiche pour la corriger ? Elle redevient « à valider » et l'employé ne la voit plus d'ici là.")) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_rouvrir_fiche", { fiche: f.id }), "Fiche rouverte.");
        recharger();
      } }, "Rouvrir"));
    }
    if (App.peutDecaisser() && f.statut === "validee") {
      actions.push(h("button", { class: "btn btn-orange", onclick: (ev) => payer(ev.currentTarget, f, recharger) }, "Payer"));
    }

    UI.vider(zone,
      h("div", { class: "actions non-imprime" }, actions),
      f.statut === "calculee" ? h("div", { class: "avertissement non-imprime" }, "Fiche provisoire : elle attend la validation du CEO.") : null,
      h("div", { class: "fiche-paie" },
        h("div", { class: "en-tete" },
          h("div", { class: "ligne" }, h("img", { src: "icons/icon-192.png", alt: "" }),
            h("div", {}, h("div", { class: "gras", style: { fontSize: "18px" } }, "BIZZOO"), h("div", { class: "doux petit" }, "bizzoomarket.com"))),
          h("div", { class: "droite" }, h("div", { class: "gras", style: { fontSize: "16px" } }, "BULLETIN DE PAIE"),
            h("div", {}, UI.mois(f.mois)), h("div", { class: "petit" }, etiquette(f.statut)))),
        h("div", { class: "formulaire petit", style: { marginBottom: "12px" } },
          h("div", {}, h("div", { class: "doux" }, "Employé"), h("b", {}, UI.nomComplet(e)), h("div", {}, "Matricule " + (e.matricule || ""))),
          h("div", {}, h("div", { class: "doux" }, "Poste"), h("b", {}, e.poste || "—"), h("div", {}, (e.profil ? "Profil " + e.profil : ""))),
          h("div", {}, h("div", { class: "doux" }, "Statut"), h("b", {}, e.statut === "stagiaire" ? "Stagiaire" : "Employé"),
            h("div", {}, "Embauché le " + UI.date(e.date_embauche))),
          h("div", {}, h("div", { class: "doux" }, "N° CNSS"), h("b", {}, e.numero_cnss || "—"),
            h("div", {}, "Jours payés : " + f.jours_payes + " / " + f.jours_du_mois))),
        h("table", { class: "tableau" },
          h("thead", {}, h("tr", {}, h("th", {}, "Libellé"), h("th", { class: "nombre" }, "Base"), h("th", { class: "nombre" }, "Taux"),
            h("th", { class: "nombre" }, "Gains"), h("th", { class: "nombre" }, "Retenues"))),
          h("tbody", {},
            gains.map((l) => h("tr", {}, h("td", {}, l.libelle + (l.genre === "indemnite" || l.imposable === false ? " (non imposable)" : "")),
              h("td", {}), h("td", {}), h("td", { class: "nombre" }, UI.entier(l.montant)), h("td", {}))),
            h("tr", {}, h("td", { class: "gras" }, "Salaire brut"), h("td", {}), h("td", {}), h("td", { class: "nombre gras" }, UI.entier(f.brut)), h("td", {})),
            retenues.map((l) => h("tr", {}, h("td", {}, l.libelle),
              h("td", { class: "nombre" }, l.assiette !== undefined ? UI.entier(l.assiette) : ""),
              h("td", { class: "nombre" }, l.genre === "cotisation" ? taux(l.taux) : ""),
              h("td", {}), h("td", { class: "nombre" }, UI.entier(l.montant))))),
          h("tfoot", {}, h("tr", {}, h("th", {}, "Totaux"), h("th", {}), h("th", {}),
            h("th", { class: "nombre" }, UI.entier(f.brut)),
            h("th", { class: "nombre" }, UI.entier(Number(f.cotisations_salariales) + Number(f.impot) + Number(f.avances) + Number(f.retenues)))))),
        h("div", { class: "net" }, h("span", {}, "NET À PAYER"), h("span", {}, UI.fcfa(f.net))),
        h("div", { class: "petit doux", style: { marginTop: "10px" } },
          "Charges patronales : " + UI.fcfa(f.charges_patronales) + " · Coût total employeur : " + UI.fcfa(Number(f.brut) + Number(f.charges_patronales)),
          h("br"),
          f.statut === "payee" ? "Payé le " + UI.dateHeure(f.paye_le) + " par " + (MODES[f.mode_paiement] || f.mode_paiement) +
            (f.reference ? " (réf. " + f.reference + ")" : "") : "Mode de paiement prévu : " + (MODES[e.mode_paiement] || "—")),
        h("div", { class: "signatures" }, h("div", {}, "L'employeur"), h("div", {}, "L'employé"))));
  }

  async function parEmploye(zone, id) {
    const lignes = await Supabase.lire("rh_fiches_paie?select=id,mois,statut,brut,net,employe&employe_id=eq." + encodeURIComponent(id) + "&order=mois.desc");
    if (!zone.isConnected) return;
    App.titre(lignes[0] ? "Paie de " + UI.nomComplet(lignes[0].employe) : "Paie");
    UI.vider(zone, lignes.length ? h("div", { class: "liste" }, lignes.map((l) =>
      h("a", { class: "element", href: "#/paie/fiche/" + l.id },
        h("div", { class: "etire" }, h("div", { class: "gras" }, UI.mois(l.mois)), h("div", { class: "petit doux" }, "Brut " + UI.fcfa(l.brut))),
        h("b", {}, UI.fcfa(l.net)), etiquette(l.statut))))
      : UI.vide("Aucune fiche de paie."));
  }

  /* ---------- Primes, indemnités, retenues ---------- */

  async function employesEnPoste() {
    return Supabase.lire("rh_employes?select=id,nom,prenoms,matricule&etat=eq.actif&order=nom,prenoms");
  }

  async function elements(zone, mois) {
    const [lignes, employes] = await Promise.all([
      Supabase.lire("rh_elements_paie?select=*&mois=eq." + mois + "&order=cree_le"),
      employesEnPoste(),
    ]);
    if (!zone.isConnected) return;
    const nom = (id) => UI.nomComplet(employes.find((e) => e.id === id)) || "Ancien employé";
    const recharger = () => elements(zone, mois);
    UI.vider(zone,
      onglets("elements", mois),
      h("div", { class: "titre-section" }, selecteurMois(mois, "#/paie/elements"),
        h("button", { class: "btn btn-petit", onclick: async (ev) => {
          const v = await UI.formulaire({ titre: "Ajouter à la paie de " + UI.mois(mois).toLowerCase(), champs: [
            { nom: "employe_id", libelle: "Employé", type: "select", requis: true,
              options: employes.map((e) => ({ valeur: e.id, libelle: UI.nomComplet(e) + " (" + e.matricule + ")" })) },
            { nom: "nature", libelle: "Nature", type: "select", valeur: "prime",
              options: Object.entries(NATURES).map(([valeur, libelle]) => ({ valeur, libelle })) },
            { nom: "libelle", libelle: "Libellé", requis: true, indice: "Ex. : Prime de rendement, Transport, Absence du 12…" },
            { nom: "montant", libelle: "Montant (FCFA)", type: "number", min: 1, requis: true },
            { nom: "imposable", libelle: "Soumis aux cotisations et à l'impôt (primes et indemnités)", type: "checkbox", valeur: true }],
            verifier: (x) => (Number(x.montant) > 0 ? null : "Le montant doit être positif.") });
          if (!v) return;
          await UI.agir(ev.currentTarget, () => Supabase.ajouter("rh_elements_paie", {
            employe_id: v.employe_id, mois, nature: v.nature, libelle: v.libelle,
            montant: Math.round(Number(v.montant)), imposable: v.nature === "retenue" ? true : v.imposable }),
            "Ajouté. La fiche du mois est recalculée.");
          recharger();
        } }, UI.icone("plus", "ic-sm"), "Ajouter")),
      h("p", { class: "doux petit" }, "Une prime ou une retenue ajoutée ici recalcule aussitôt la fiche du mois, tant que le CEO ne l'a pas validée."),
      lignes.length ? h("div", { class: "liste" }, lignes.map((l) =>
        h("div", { class: "element" },
          h("div", { class: "etire" },
            h("div", { class: "ligne" }, h("span", { class: "gras etire" }, nom(l.employe_id)),
              h("b", { style: { color: l.nature === "retenue" ? "var(--rouge-fonce)" : "var(--vert-fonce)" } },
                (l.nature === "retenue" ? "− " : "+ ") + UI.fcfa(l.montant))),
            h("div", { class: "petit doux" }, NATURES[l.nature] + " · " + l.libelle + (l.nature !== "retenue" && !l.imposable ? " · non imposable" : ""))),
          h("button", { class: "btn-ic", "aria-label": "Supprimer", onclick: async (ev) => {
            if (!await UI.confirmer("Retirer « " + l.libelle + " » ?", { danger: true, valider: "Retirer" })) return;
            await UI.agir(ev.currentTarget, () => Supabase.supprimer("rh_elements_paie", "id=eq." + l.id), "Retiré.");
            recharger();
          } }, UI.icone("poubelle", "ic-sm")))))
        : UI.vide("Ni prime ni retenue ce mois-ci."));
  }

  /* ---------- Avances sur salaire ---------- */

  async function avances(zone) {
    const [lignes, employes] = await Promise.all([
      Supabase.lire("rh_avances?select=*&order=date_avance.desc&limit=300"),
      employesEnPoste(),
    ]);
    if (!zone.isConnected) return;
    const nom = (id) => UI.nomComplet(employes.find((e) => e.id === id)) || "Ancien employé";
    const recharger = () => avances(zone);
    UI.vider(zone,
      onglets("avances"),
      h("div", { class: "titre-section" }, h("h2", {}, "Avances sur salaire"),
        h("button", { class: "btn btn-petit", onclick: async (ev) => {
          const v = await UI.formulaire({ titre: "Nouvelle avance", champs: [
            { nom: "employe_id", libelle: "Employé", type: "select", requis: true,
              options: employes.map((e) => ({ valeur: e.id, libelle: UI.nomComplet(e) + " (" + e.matricule + ")" })) },
            { nom: "montant", libelle: "Montant (FCFA)", type: "number", min: 1, requis: true },
            { nom: "date_avance", libelle: "Versée le", type: "date", valeur: UI.aujourdhui(), requis: true },
            { nom: "mensualites", libelle: "Remboursée en combien de mois ?", type: "number", min: 1, max: 24, valeur: 1, requis: true },
            { nom: "premier_mois", libelle: "Première retenue sur la paie de", type: "month", valeur: UI.aujourdhui().slice(0, 7), requis: true },
            { nom: "motif", libelle: "Motif", type: "textarea" }],
            verifier: (x) => (Number(x.montant) > 0 && Number(x.mensualites) >= 1 && Number(x.mensualites) <= 24 ? null : "Montant positif, et de 1 à 24 mensualités.") });
          if (!v) return;
          await UI.agir(ev.currentTarget, () => Supabase.ajouter("rh_avances", {
            employe_id: v.employe_id, montant: Math.round(Number(v.montant)), date_avance: v.date_avance,
            mensualites: Number(v.mensualites), premier_mois: v.premier_mois + "-01", motif: v.motif }),
            "Avance enregistrée : elle sera retenue sur les prochaines paies.");
          recharger();
        } }, UI.icone("plus", "ic-sm"), "Nouvelle avance")),
      h("p", { class: "doux petit" }, "Chaque paie retient une mensualité, jamais au-delà de ce qui reste du salaire : le reste attend la paie suivante."),
      lignes.length ? h("div", { class: "liste" }, lignes.map((a) =>
        h("div", { class: "element" },
          h("div", { class: "etire" },
            h("div", { class: "ligne" }, h("span", { class: "gras etire" }, nom(a.employe_id)), h("b", {}, UI.fcfa(a.montant))),
            h("div", { class: "petit doux" }, "Versée le " + UI.date(a.date_avance) + " · " + a.mensualites + " mensualité(s) à partir de " +
              UI.mois(a.premier_mois).toLowerCase() + (a.motif ? " · " + a.motif : ""))),
          UI.etiquette(a.statut === "active" ? "En cours" : a.statut === "soldee" ? "Soldée" : "Annulée",
            a.statut === "active" ? "orange" : a.statut === "soldee" ? "vert" : ""),
          a.statut === "active" ? h("button", { class: "btn-ic", "aria-label": "Supprimer", onclick: async (ev) => {
            if (!await UI.confirmer("Supprimer cette avance ? Impossible si elle a déjà été retenue sur une paie validée.", { danger: true, valider: "Supprimer" })) return;
            await UI.agir(ev.currentTarget, () => Supabase.supprimer("rh_avances", "id=eq." + a.id), "Avance supprimée.");
            recharger();
          } }, UI.icone("poubelle", "ic-sm")) : null)))
        : UI.vide("Aucune avance."));
  }

  /* ---------- Barèmes ---------- */

  async function baremes(zone) {
    const [cotisations, tranches, reglages] = await Promise.all([
      Supabase.lire("rh_cotisations?select=*&order=code"),
      Supabase.lire("rh_tranches_impot?select=*&order=borne_inf"),
      Supabase.lire("rh_reglages_paie?select=*"),
    ]);
    if (!zone.isConnected) return;
    const r = reglages[0] || {};
    const ceo = App.estCeo();
    const recharger = () => App.rafraichir().then(() => baremes(zone));
    const pct = (t) => String(t).replace(".", ",") + " %";

    const editerCotisation = async (bouton, c) => {
      const v = await UI.formulaire({ titre: c ? "Modifier " + c.code : "Nouvelle cotisation", champs: [
        { nom: "code", libelle: "Code (majuscules, ex. CNSS)", requis: true, valeur: c ? c.code : "" },
        { nom: "libelle", libelle: "Libellé", requis: true, valeur: c ? c.libelle : "" },
        { nom: "taux_salarie", libelle: "Taux salarié (%)", type: "number", pas: "0.001", min: 0, max: 100, valeur: c ? c.taux_salarie : 0, requis: true },
        { nom: "taux_employeur", libelle: "Taux employeur (%)", type: "number", pas: "0.001", min: 0, max: 100, valeur: c ? c.taux_employeur : 0, requis: true },
        { nom: "plafond", libelle: "Plafond mensuel de l'assiette (FCFA, vide = aucun)", type: "number", min: 1, valeur: c && c.plafond ? c.plafond : "" },
        { nom: "stagiaires", libelle: "S'applique aussi aux stagiaires", type: "checkbox", valeur: c ? c.stagiaires : false },
        { nom: "actif", libelle: "Active", type: "checkbox", valeur: c ? c.actif : true }],
        verifier: (x) => (/^[A-Z0-9_]{2,20}$/.test(x.code.toUpperCase()) ? null : "Code : 2 à 20 lettres majuscules, chiffres ou _.") });
      if (!v) return;
      const valeurs = { code: v.code.toUpperCase(), libelle: v.libelle, taux_salarie: Number(v.taux_salarie),
        taux_employeur: Number(v.taux_employeur), plafond: v.plafond ? Math.round(Number(v.plafond)) : null,
        stagiaires: v.stagiaires, actif: v.actif };
      await UI.agir(bouton, () => c ? Supabase.modifier("rh_cotisations", "id=eq." + c.id, valeurs) : Supabase.ajouter("rh_cotisations", valeurs),
        "Enregistré : le CEO doit valider ce taux avant qu'il compte.");
      recharger();
    };

    const editerTranches = async (bouton) => {
      const texte = tranches.map((t) => t.borne_inf + " ; " + (t.borne_sup ?? "") + " ; " + t.taux).join("\n");
      const v = await UI.formulaire({ titre: "Barème de l'impôt sur le salaire",
        texte: "Une tranche par ligne : « borne inférieure ; borne supérieure ; taux % ». Montants mensuels en FCFA. " +
               "La première commence à 0, chacune commence où finit la précédente, la dernière n'a pas de borne supérieure.",
        champs: [{ nom: "tranches", libelle: "Tranches", type: "textarea", valeur: texte, indice: "0 ; 60000 ; 0\n60000 ; 150000 ; 10\n150000 ; ; 15" }],
        verifier: (x) => {
          for (const l of x.tranches.split("\n").map((s) => s.trim()).filter(Boolean)) {
            const [a, b, t] = l.split(";").map((s) => s.trim());
            if (!/^\d+$/.test(a) || (b && !/^\d+$/.test(b)) || !/^\d+([.,]\d+)?$/.test(t || "")) return "Ligne illisible : « " + l + " ».";
          }
          return null;
        } });
      if (!v) return;
      const nouvelles = v.tranches.split("\n").map((s) => s.trim()).filter(Boolean).map((l) => {
        const [a, b, t] = l.split(";").map((s) => s.trim());
        return { borne_inf: Number(a), borne_sup: b ? Number(b) : null, taux: Number(t.replace(",", ".")) };
      });
      await UI.agir(bouton, async () => {
        await Supabase.supprimer("rh_tranches_impot", "id=not.is.null");
        if (nouvelles.length) await Supabase.requete("POST", "rh_tranches_impot", nouvelles, { sansRetour: true });
      }, "Barème enregistré : le CEO doit le valider.");
      recharger();
    };

    UI.vider(zone,
      onglets("baremes"),
      h("div", { class: "info" }, "L'application ne contient aucun taux légal. Saisissez ceux que vous donne votre comptable (CNSS, impôt…) : ",
        "ils ne comptent sur les fiches qu'une fois validés par le CEO, et toute modification les renvoie à sa validation."),
      h("div", { class: "carte pile" },
        h("div", { class: "titre-section" }, h("h2", { style: { marginBottom: 0 } }, "Cotisations sociales"),
          h("button", { class: "btn btn-petit", onclick: (ev) => editerCotisation(ev.currentTarget) }, UI.icone("plus", "ic-sm"), "Ajouter")),
        cotisations.length ? h("div", { class: "defile" }, h("table", { class: "tableau" },
          h("thead", {}, h("tr", {}, h("th", {}, "Cotisation"), h("th", { class: "nombre" }, "Salarié"), h("th", { class: "nombre" }, "Employeur"),
            h("th", { class: "nombre" }, "Plafond"), h("th", {}, "État"), h("th", {}))),
          h("tbody", {}, cotisations.map((c) => h("tr", {},
            h("td", {}, h("b", {}, c.code), h("div", { class: "tres-petit doux" }, c.libelle + (c.stagiaires ? " · stagiaires compris" : ""))),
            h("td", { class: "nombre" }, pct(c.taux_salarie)), h("td", { class: "nombre" }, pct(c.taux_employeur)),
            h("td", { class: "nombre" }, c.plafond ? UI.entier(c.plafond) : "—"),
            h("td", {}, !c.actif ? UI.etiquette("Inactive") : c.valide ? UI.etiquette("Validée", "vert") : UI.etiquette("À valider", "orange")),
            h("td", {}, h("div", { class: "actions" },
              ceo && !c.valide ? h("button", { class: "btn btn-vert btn-petit", onclick: async (ev) => {
                await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_valider_cotisation", { cotisation: c.id }), "Cotisation validée.");
                recharger();
              } }, "Valider") : null,
              h("button", { class: "btn-ic", "aria-label": "Modifier", onclick: (ev) => editerCotisation(ev.currentTarget, c) }, UI.icone("crayon", "ic-sm")),
              h("button", { class: "btn-ic", "aria-label": "Supprimer", onclick: async (ev) => {
                if (!await UI.confirmer("Supprimer la cotisation " + c.code + " ? Les fiches déjà validées ne changent pas.", { danger: true, valider: "Supprimer" })) return;
                await UI.agir(ev.currentTarget, () => Supabase.supprimer("rh_cotisations", "id=eq." + c.id), "Supprimée.");
                recharger();
              } }, UI.icone("poubelle", "ic-sm")))))))))
          : UI.vide("Aucune cotisation saisie.")),
      h("div", { class: "carte pile" },
        h("div", { class: "titre-section" }, h("h2", { style: { marginBottom: 0 } }, "Impôt sur le salaire"),
          r.impot_valide ? UI.etiquette("Validé", "vert") : tranches.length ? UI.etiquette("À valider", "orange") : UI.etiquette("Non saisi")),
        tranches.length ? h("table", { class: "tableau" },
          h("thead", {}, h("tr", {}, h("th", {}, "De"), h("th", {}, "À"), h("th", { class: "nombre" }, "Taux"))),
          h("tbody", {}, tranches.map((t) => h("tr", {}, h("td", {}, UI.fcfa(t.borne_inf)),
            h("td", {}, t.borne_sup ? UI.fcfa(t.borne_sup) : "et au-delà"), h("td", { class: "nombre" }, pct(t.taux))))))
          : UI.vide("Aucune tranche saisie : aucun impôt n'est retenu."),
        h("div", { class: "formulaire" },
          h("label", { class: "champ" }, h("span", {}, "Calculé sur"),
            (() => {
              const s = h("select", {}, h("option", { value: "brut_imposable", selected: r.impot_sur === "brut_imposable" }, "le brut imposable"),
                h("option", { value: "brut_moins_cotisations", selected: r.impot_sur === "brut_moins_cotisations" }, "le brut imposable moins les cotisations du salarié"));
              s.addEventListener("change", async () => {
                await UI.agir(null, () => Supabase.modifier("rh_reglages_paie", "id=eq.true", { impot_sur: s.value }), "Réglage enregistré : le CEO doit revalider le barème.");
                recharger();
              });
              return s;
            })()),
          h("label", { class: "case" }, (() => {
            const c = h("input", { type: "checkbox", checked: !!r.impot_stagiaires });
            c.addEventListener("change", async () => {
              await UI.agir(null, () => Supabase.modifier("rh_reglages_paie", "id=eq.true", { impot_stagiaires: c.checked }), "Réglage enregistré : le CEO doit revalider le barème.");
              recharger();
            });
            return c;
          })(), "Les stagiaires paient aussi l'impôt")),
        h("div", { class: "actions" },
          h("button", { class: "btn btn-second", onclick: (ev) => editerTranches(ev.currentTarget) }, UI.icone("crayon", "ic-sm"), "Modifier les tranches"),
          ceo && tranches.length && !r.impot_valide ? h("button", { class: "btn btn-vert", onclick: async (ev) => {
            await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_valider_bareme_impot"), "Barème validé.");
            recharger();
          } }, UI.icone("check", "ic-sm"), "Valider le barème") : null)),
      h("p", { class: "doux petit" }, "Après une validation, recalculez les fiches du mois (onglet Fiches) pour qu'elles en tiennent compte."));
  }

  return { titre: "Paie", afficher };
})();
