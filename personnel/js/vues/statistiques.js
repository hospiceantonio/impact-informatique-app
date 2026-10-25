/* =========================================================
   Statistiques — commandes, boutiques, produits, livraisons,
   livreurs, SAV et avis de BIZZOO, chacun sur sa page, avec
   son choix de période.

   #/statistiques               : le sommaire des sous-menus ;
   #/statistiques/<sous-menu>   : une page, période dans l'adresse
                                  (?p=30j, ou ?du=…&au=…), gardée
                                  d'un sous-menu à l'autre.

   C'est la base (rh_statistiques) qui décide de ce que chacun
   voit : le CEO tout, marge comprise ; l'administration tout
   sauf la marge ; les autres, les seuls sous-menus que le menu
   Paramètres ouvre à leur profil, sans aucun montant. Un chiffre absent de la
   réponse n'est donc jamais affiché : l'écran ne cache rien,
   il n'a simplement rien reçu.
   ========================================================= */
const VueStatistiques = (() => {
  const { h } = UI;

  /** Les sous-menus, et la rubrique de la base dont chacun dépend. */
  const SOUS_MENUS = [
    { cle: "commandes", libelle: "Commandes", rubrique: "commandes", icone: "argent",
      texte: "Payées, passées, en attente, articles vendus, jour par jour" },
    { cle: "boutiques", libelle: "Boutiques qui vendent le plus", rubrique: "commandes", icone: "profils",
      texte: "Le classement des boutiques sur la période" },
    { cle: "produits", libelle: "Produits les plus vendus", rubrique: "commandes", icone: "paie",
      texte: "Les articles qui partent le plus" },
    { cle: "livraisons", libelle: "Livraisons", rubrique: "livraisons", icone: "mission",
      texte: "Livrés, à livrer, annulés, délai moyen" },
    { cle: "livreurs", libelle: "Livreurs", rubrique: "livraisons", icone: "equipe",
      texte: "Ce que chaque livreur a livré" },
    { cle: "sav", libelle: "Service après-vente et avis", rubrique: "sav", icone: "bulle",
      texte: "Réclamations, avis et notes des clients" },
    /* Les statistiques internes (rh_finances), mois par mois : l'administration ;
       revenus et résultat, le CEO et le superadministrateur. */
    { cle: "salaires", libelle: "Salaires", interne: "admin", icone: "paie",
      texte: "La masse salariale mois par mois : brut, net, charges, coût employeur, avances" },
    { cle: "depenses", libelle: "Dépenses", interne: "admin", icone: "argent",
      texte: "Demandées, approuvées, décaissées, par mois et par profil" },
    { cle: "effectifs", libelle: "Effectifs", interne: "admin", icone: "equipe",
      texte: "Qui travaille chez BIZZOO : profils, statuts, âges, embauches et sorties" },
    { cle: "activite", libelle: "Missions et rapports", interne: "admin", icone: "mission",
      texte: "Missions rendues à temps ou en retard, rapports validés" },
    { cle: "revenus", libelle: "Revenus et résultat", interne: "revenus", icone: "stats",
      texte: "Ce que gagne BIZZOO, moins les salaires et les dépenses (CEO et superadministrateur)" },
  ];

  const ETATS_LIGNE = { nouvelle: "Nouvelle", vue: "Vue par la boutique", preparee: "Préparée",
    en_livraison: "En livraison", remise: "Livrée", annulee: "Annulée" };
  const ETATS_SAV = { ouverte: "Ouverte", repondue: "Répondue", resolue: "Résolue",
    escaladee: "Escaladée vers BIZZOO", tranchee: "Tranchée par BIZZOO" };
  const SUJETS_SAV = { non_recu: "Non reçu", abime: "Abîmé", pas_conforme: "Pas conforme",
    incomplet: "Incomplet", autre: "Autre" };

  /** Les sous-menus que ce compte peut ouvrir (la base tranche de toute façon). */
  const permis = () => SOUS_MENUS.filter((s) => App.sousMenusStatistiques().includes(s.cle));

  const iso = (d) => d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  function periodes() {
    const j = new Date();
    const moinsJours = (n) => { const d = new Date(j); d.setDate(d.getDate() - n); return iso(d); };
    const debutMois = new Date(j.getFullYear(), j.getMonth(), 1);
    const debutMoisPrec = new Date(j.getFullYear(), j.getMonth() - 1, 1);
    const finMoisPrec = new Date(j.getFullYear(), j.getMonth(), 0);
    return [
      ["7j", "7 jours", moinsJours(6), iso(j)],
      ["30j", "30 jours", moinsJours(29), iso(j)],
      ["mois", "Ce mois", iso(debutMois), iso(j)],
      ["moisprec", "Mois dernier", iso(debutMoisPrec), iso(finMoisPrec)],
      ["annee", "Cette année", j.getFullYear() + "-01-01", iso(j)],
    ];
  }

  /** La période demandée par l'adresse, et ce qu'il faut recopier dans les liens. */
  function periodeDe(params, defaut) {
    const liste = periodes();
    const choix = liste.find((p) => p[0] === params.p) || (params.du ? null : liste.find((p) => p[0] === (defaut || "30j")));
    const depuis = choix ? choix[2] : params.du;
    const jusqu = choix ? choix[3] : (params.au || iso(new Date()));
    const suffixe = choix ? "?p=" + choix[0] : "?du=" + depuis + "&au=" + jusqu;
    return { liste, choix, depuis, jusqu, suffixe };
  }

  const nombre = (n) => (n === null || n === undefined ? "—" : UI.entier(n));
  const tuile = (valeur, libelle, petit) => h("div", { class: "tuile" },
    h("b", { style: petit ? { fontSize: "17px" } : null }, valeur), h("span", {}, libelle));
  const montant = (v) => (v === null || v === undefined ? null : UI.fcfa(v));

  async function afficher(zone, morceaux, params) {
    const ouverts = permis();
    const sous = ouverts.find((s) => s.cle === morceaux[0]);
    /* Les chiffres internes se lisent par mois : l'année par défaut. */
    const periode = periodeDe(params, sous && sous.interne ? "annee" : "30j");
    if (morceaux[0] && !sous) {
      UI.vider(zone, UI.vide("Ce sous-menu n'existe pas, ou votre compte n'y a pas accès."));
      return;
    }
    if (!sous) return sommaire(zone, ouverts, periode);

    App.titre(sous.libelle);
    const route = "#/statistiques/" + sous.cle;
    const corps = h("div", { class: "pile" }, UI.chargement());
    UI.vider(zone,
      /* Les sous-menus : on passe de l'un à l'autre en gardant la période. */
      h("div", { class: "filtres" }, ouverts.map((s) =>
        h("button", { class: s.cle === sous.cle ? "actif" : "", onclick: () => { location.hash = "#/statistiques/" + s.cle + periode.suffixe; } },
          s.libelle))),
      UI.barrePeriode(periode, route),
      corps);
    /* Sur téléphone, la bande des sous-menus montre celui qu’on lit. */
    const actif = zone.querySelector(".filtres .actif");
    if (actif) actif.scrollIntoView({ inline: "center", block: "nearest" });

    if (sous.interne) {
      const fi = await Supabase.rpc("rh_finances", { depuis: periode.depuis, jusqu: periode.jusqu });
      if (!corps.isConnected) return;
      const page = INTERNES[sous.cle];
      UI.vider(corps, h("p", { class: "doux petit" }, "Mois entiers, de " + UI.mois(fi.periode.depuis).toLowerCase() +
        " à " + UI.mois(fi.periode.jusqu).toLowerCase() + "."),
        (sous.cle === "revenus" && !fi.revenus) ? UI.vide("Réservé au CEO et au superadministrateur.") : page(fi, periode));
      return;
    }
    const s = await Supabase.rpc("rh_statistiques", { depuis: periode.depuis, jusqu: periode.jusqu });
    if (!corps.isConnected) return;
    const blocs = [h("p", { class: "doux petit" }, "Du " + UI.dateLongue(s.periode.depuis) + " au " + UI.dateLongue(s.periode.jusqu) +
      (s.droits.argent ? "" : " · sans les montants, réservés à l'administration"))];
    const PAGES = { commandes, boutiques, produits, livraisons, livreurs, sav };
    const donnees = s[sous.rubrique];
    if (!donnees) blocs.push(UI.vide("Votre compte n'a pas accès à cette rubrique."));
    else blocs.push(...PAGES[sous.cle](donnees, s.droits));
    UI.vider(corps, blocs);
  }

  /** Le sommaire : une tuile par sous-menu. */
  function sommaire(zone, ouverts, periode) {
    UI.vider(zone,
      h("p", { class: "doux" }, "Choisissez ce que vous voulez voir. La période se règle sur chaque page."),
      ouverts.length ? h("div", { class: "liste" }, ouverts.map((s) =>
        h("a", { class: "element", href: "#/statistiques/" + s.cle + periode.suffixe },
          h("div", { class: "avatar", style: { background: "var(--bleu-50)", color: "var(--bleu-800)" } }, UI.icone(s.icone, "ic-sm")),
          h("div", { class: "etire" }, h("div", { class: "gras" }, s.libelle), h("div", { class: "petit doux" }, s.texte)),
          UI.icone("chevron", "ic-sm"))))
        : UI.vide("Votre compte n'a accès à aucune statistique."));
  }

  function tableau(titre, entetes, lignes) {
    const garder = entetes.map((e) => e !== null);
    return h("div", { class: "carte defile" },
      titre ? h("h3", { style: { marginBottom: "8px" } }, titre) : null,
      h("table", { class: "tableau" },
        h("thead", {}, h("tr", {}, entetes.filter((e, i) => garder[i]).map((e, i) =>
          h("th", { class: i === 0 ? "" : "nombre" }, e)))),
        h("tbody", {}, lignes.map((l) => h("tr", {}, l.filter((_, i) => garder[i]).map((v, i) =>
          h("td", { class: i === 0 ? "" : "nombre" }, v)))))));
  }

  /* ---------- Commandes ---------- */

  function commandes(c, droits) {
    const tuiles = [
      tuile(nombre(c.payees), "commandes payées"),
      tuile(nombre(c.articles), "articles vendus"),
      tuile(nombre(c.creees), "commandes passées"),
      tuile(nombre(c.a_payer), "en attente de paiement"),
      tuile(nombre(c.echouees), "échouées ou annulées"),
      tuile(nombre(c.revendeurs), "par des revendeurs"),
    ];
    if (droits.argent) {
      tuiles.unshift(tuile(montant(c.montant), "encaissé sur les commandes payées", true));
      tuiles.splice(1, 0, tuile(montant(c.panier_moyen), "panier moyen", true));
      tuiles.push(tuile(montant(c.frais_livraison), "frais de livraison", true), tuile(montant(c.remises), "remises (codes promo)", true));
    }
    if (droits.marge) {
      tuiles.splice(1, 0, h("div", { class: "tuile alerte" }, h("b", { style: { fontSize: "17px" } }, montant(c.benefice)),
        h("span", {}, "marge de BIZZOO (CEO seul)")));
      tuiles.push(tuile(montant(c.reverse_boutiques), "reversé aux boutiques", true));
    }
    const sortie = [h("div", { class: "tuiles" }, tuiles)];
    if (c.par_jour.length) sortie.push(courbe(c.par_jour, droits.argent));
    else sortie.push(UI.vide("Aucune commande payée sur cette période."));
    return sortie;
  }

  /** Des barres, une par jour : le nombre de commandes payées. */
  function courbe(jours, argent) {
    const max = Math.max(1, ...jours.map((j) => j.payees));
    return h("div", { class: "carte" },
      h("h3", { style: { marginBottom: "10px" } }, "Commandes payées par jour"),
      h("div", { style: { display: "flex", alignItems: "flex-end", gap: "3px", height: "140px", overflowX: "auto" } },
        jours.map((j) => h("div", {
          title: UI.date(j.jour) + " : " + j.payees + " commande(s)" + (argent && j.montant !== null ? " · " + UI.fcfa(j.montant) : ""),
          style: { flex: "1 0 10px", minWidth: "10px", maxWidth: "36px", height: Math.max(4, Math.round(j.payees / max * 130)) + "px",
                   background: "var(--bleu)", borderRadius: "4px 4px 0 0" } }))),
      h("div", { class: "ligne tres-petit doux", style: { justifyContent: "space-between", marginTop: "4px" } },
        h("span", {}, UI.date(jours[0].jour)), h("span", {}, UI.date(jours[jours.length - 1].jour))));
  }

  /* ---------- Boutiques qui vendent le plus ---------- */

  function boutiques(c, droits) {
    if (!c.boutiques.length) return [UI.vide("Aucune vente sur cette période.")];
    return [tableau(null,
      ["Boutique", "Commandes", "Articles", droits.argent ? "Ventes (FCFA)" : null, droits.marge ? "Marge (FCFA)" : null],
      c.boutiques.map((b, i) => [(i + 1) + ". " + (b.boutique || "—"), nombre(b.commandes), nombre(b.articles),
        droits.argent ? UI.entier(b.ventes) : null, droits.marge ? UI.entier(b.benefice) : null])),
      h("p", { class: "doux tres-petit" }, "Les 10 premières, classées par nombre d'articles vendus.")];
  }

  /* ---------- Produits les plus vendus ---------- */

  function produits(c, droits) {
    if (!c.produits.length) return [UI.vide("Aucune vente sur cette période.")];
    return [tableau(null,
      ["Produit", "Articles", droits.argent ? "Ventes (FCFA)" : null],
      c.produits.map((p, i) => [(i + 1) + ". " + (p.code ? p.code + " · " : "") + p.produit, nombre(p.articles),
        droits.argent ? UI.entier(p.ventes) : null])),
      h("p", { class: "doux tres-petit" }, "Les 10 premiers, classés par nombre d'articles vendus.")];
  }

  /* ---------- Livraisons ---------- */

  function livraisons(l) {
    const delai = l.delai_moyen_heures === null ? "—"
      : l.delai_moyen_heures < 48 ? String(l.delai_moyen_heures).replace(".", ",") + " h"
      : (Math.round(l.delai_moyen_heures / 24 * 10) / 10).toString().replace(".", ",") + " j";
    const sortie = [
      h("div", { class: "tuiles" },
        tuile(nombre(l.livrees), "articles livrés"),
        tuile(nombre(l.confirmees), "réceptions confirmées par le client"),
        tuile(nombre(l.en_cours), "à livrer"),
        tuile(nombre(l.annulees), "annulés"),
        tuile(delai, "délai moyen paiement → « je l'ai reçu » du client")),
    ];
    const etats = Object.entries(l.par_etat || {});
    if (etats.length) {
      sortie.push(tableau("Où en sont les articles payés", ["État", "Articles"],
        etats.sort((a, b) => b[1] - a[1]).map(([e, n]) => [ETATS_LIGNE[e] || e, nombre(n)])));
    }
    return sortie;
  }

  /* ---------- Livreurs ---------- */

  function livreurs(l, droits) {
    if (!l.livreurs.length) return [UI.vide("Aucune course confiée à un livreur sur cette période.")];
    return [tableau(null, ["Livreur", "Commandes", "Articles livrés", droits.argent ? "Gains (FCFA)" : null],
      l.livreurs.map((x) => [x.livreur, nombre(x.commandes), nombre(x.livrees), droits.argent ? UI.entier(x.gains) : null]))];
  }

  /* ---------- SAV et avis ---------- */

  function sav(s) {
    const sortie = [
      h("div", { class: "tuiles" },
        tuile(nombre(s.reclamations), "réclamations"),
        tuile(nombre(s.avis), "avis déposés"),
        tuile(s.note_moyenne === null ? "—" : String(s.note_moyenne).replace(".", ",") + " / 5", "note moyenne"),
        tuile(nombre(s.avis_masques), "avis masqués")),
    ];
    const etats = Object.entries(s.par_etat || {});
    if (etats.length) sortie.push(tableau("Réclamations par état", ["État", "Nombre"], etats.map(([e, n]) => [ETATS_SAV[e] || e, nombre(n)])));
    const sujets = Object.entries(s.par_sujet || {});
    if (sujets.length) sortie.push(tableau("Réclamations par motif", ["Motif", "Nombre"],
      sujets.sort((a, b) => b[1] - a[1]).map(([e, n]) => [SUJETS_SAV[e] || e, nombre(n)])));
    const notes = s.notes || {};
    if (Object.keys(notes).length) {
      sortie.push(tableau("Répartition des notes", ["Note", "Avis"],
        [5, 4, 3, 2, 1].map((n) => ["★".repeat(n), nombre(notes[n] || 0)])));
    }
    return sortie;
  }

  /* =========================================================
     Les statistiques internes : salaires, dépenses, effectifs,
     missions et rapports, revenus et résultat (rh_finances).
     ========================================================= */

  const fcfa = (v) => UI.fcfa(v || 0);
  const somme = (liste, cle) => liste.reduce((t, x) => t + Number(x[cle] || 0), 0);
  const moisCourt = (iso) => new Date(iso + "T00:00:00").toLocaleDateString("fr-FR", { month: "short", year: "2-digit" });
  const virgule = (n) => (n === null || n === undefined ? "—" : String(n).replace(".", ","));
  const tuileMontant = (v, libelle, couleur) => h("div", { class: "tuile" + (couleur === "alerte" ? " alerte" : "") },
    h("b", { style: { fontSize: "17px", color: couleur === "rouge" ? "var(--rouge-fonce)" : couleur === "vert" ? "var(--vert-fonce)" : null } }, fcfa(v)),
    h("span", {}, libelle));

  /** Des barres, une par mois ; négatives en rouge, sous la ligne. */
  function barresMois(titre, lignes, cle) {
    const valeurs = lignes.map((l) => Number(l[cle] || 0));
    const max = Math.max(1, ...valeurs.map(Math.abs));
    const negatif = valeurs.some((v) => v < 0);
    const haut = negatif ? 70 : 130;
    return h("div", { class: "carte" },
      h("h3", { style: { marginBottom: "10px" } }, titre),
      h("div", { style: { display: "flex", gap: "4px", overflowX: "auto" } }, lignes.map((l, i) => {
        const v = valeurs[i];
        const barre = h("div", { title: UI.mois(l.mois) + " : " + fcfa(v),
          style: { height: Math.max(v ? 3 : 0, Math.round(Math.abs(v) / max * haut)) + "px", width: "100%",
                   background: v < 0 ? "var(--rouge)" : "var(--bleu)", borderRadius: v < 0 ? "0 0 4px 4px" : "4px 4px 0 0" } });
        return h("div", { style: { flex: "1 0 28px", minWidth: "28px", maxWidth: "56px", display: "flex", flexDirection: "column", alignItems: "center" } },
          h("div", { style: { height: haut + "px", width: "100%", display: "flex", alignItems: "flex-end" } }, v >= 0 ? barre : null),
          negatif ? h("div", { style: { height: haut + "px", width: "100%", borderTop: "1px solid var(--trait)" } }, v < 0 ? barre : null) : null,
          h("div", { class: "tres-petit doux", style: { marginTop: "4px", whiteSpace: "nowrap" } }, moisCourt(l.mois)));
      })));
  }

  /** Un tableau, et le même en Excel. */
  function tableauExportable(titre, nomFichier, colonnes, lignes) {
    const bouton = h("button", { class: "btn btn-petit btn-second", onclick: () => {
      Xlsx.telecharger(nomFichier + ".xlsx", [{ nom: titre.slice(0, 31), colonnes: colonnes.map((c) => ({ titre: c[0], largeur: c[2] || 16, type: c[1] })),
        lignes: lignes.map((l) => l.map((v, i) => (colonnes[i][1] === "fcfa" || colonnes[i][1] === "nombre") ? Number(v || 0) : v)) }]);
    } }, UI.icone("telecharger", "ic-sm"), "Excel");
    return h("div", { class: "carte defile" },
      h("div", { class: "ligne", style: { marginBottom: "8px" } }, h("h3", { class: "etire" }, titre), bouton),
      h("table", { class: "tableau" },
        h("thead", {}, h("tr", {}, colonnes.map((c, i) => h("th", { class: i ? "nombre" : "" }, c[0])))),
        h("tbody", {}, lignes.map((l) => h("tr", {}, l.map((v, i) => h("td", { class: i ? "nombre" : "" },
          colonnes[i][1] === "fcfa" ? UI.entier(v) : colonnes[i][1] === "nombre" ? UI.entier(v) : v))))),
        lignes.length > 1 && colonnes.some((c) => c[1] === "fcfa") ? h("tfoot", {}, h("tr", {}, colonnes.map((c, i) =>
          h("th", { class: i ? "nombre" : "" }, i === 0 ? "Total" : c[1] === "fcfa" || c[3] ? UI.entier(lignes.reduce((t, l) => t + Number(l[i] || 0), 0)) : "")))) : null));
  }

  function salaires(fi, periode) {
    const s = fi.salaires;
    const pm = s.par_mois;
    const provisoires = somme(pm, "provisoires");
    return [
      h("div", { class: "tuiles" },
        tuileMontant(somme(pm, "cout"), "coût employeur (brut + charges)", "alerte"),
        tuileMontant(somme(pm, "brut"), "salaires bruts"),
        tuileMontant(somme(pm, "net"), "nets à payer"),
        tuileMontant(somme(pm, "charges"), "charges patronales"),
        tuileMontant(somme(pm, "cotisations") + somme(pm, "impot"), "cotisations et impôt retenus"),
        tuileMontant(somme(pm, "paye"), "déjà payés", "vert"),
        tuileMontant(somme(pm, "a_payer"), "validés, pas encore payés", somme(pm, "a_payer") ? "rouge" : null),
        tuileMontant(s.avances_accordees, s.avances_nombre + " avance(s) accordée(s)"),
        tuileMontant(s.avances_encours, "avances encore à rembourser")),
      provisoires ? h("p", { class: "avertissement" }, provisoires + " fiche(s) encore à valider par le CEO (" + fcfa(somme(pm, "net_provisoire")) +
        " nets) : elles ne comptent pas dans ces chiffres.") : null,
      barresMois("Coût employeur par mois", pm, "cout"),
      tableauExportable("Masse salariale par mois", "BIZZOO_salaires_" + periode.depuis + "_au_" + periode.jusqu,
        [["Mois", "texte", 14], ["Fiches", "nombre", 8], ["Brut", "fcfa"], ["Cotisations", "fcfa"], ["Impôt", "fcfa"], ["Avances", "fcfa"],
         ["Retenues", "fcfa"], ["Net", "fcfa"], ["Charges patronales", "fcfa"], ["Coût employeur", "fcfa"], ["Payé", "fcfa"]],
        pm.map((m) => [UI.mois(m.mois), m.fiches, m.brut, m.cotisations, m.impot, m.avances, m.retenues, m.net, m.charges, m.cout, m.paye])),
      s.par_profil.length ? tableauExportable("Par profil", "BIZZOO_salaires_par_profil",
        [["Profil", "texte", 24], ["Employés", "nombre", 10], ["Fiches", "nombre", 8], ["Brut", "fcfa"], ["Net", "fcfa"], ["Coût employeur", "fcfa"]],
        s.par_profil.map((p) => [p.profil, p.effectif, p.fiches, p.brut, p.net, p.cout])) : null,
      s.par_statut.length ? tableauExportable("Employés et stagiaires", "BIZZOO_salaires_par_statut",
        [["Statut", "texte", 16], ["Personnes", "nombre", 10], ["Brut", "fcfa"], ["Coût employeur", "fcfa"]],
        s.par_statut.map((p) => [p.statut === "stagiaire" ? "Stagiaires" : "Employés", p.effectif, p.brut, p.cout])) : null,
    ];
  }

  const STATUTS_DEPENSE = { demandee: "Demandée", approuvee: "Approuvée", refusee: "Refusée", decaissee: "Décaissée", annulee: "Annulée" };
  function depenses(fi, periode) {
    const d = fi.depenses;
    const pm = d.par_mois;
    return [
      h("div", { class: "tuiles" },
        tuileMontant(somme(pm, "montant_decaisse"), somme(pm, "decaissees") + " dépense(s) décaissée(s)", "alerte"),
        tuileMontant(somme(pm, "montant_demande"), somme(pm, "demandees") + " demande(s) sur la période"),
        tuileMontant(somme(pm, "approuvees"), "approuvé par le CEO"),
        tuileMontant(d.en_attente.montant, d.en_attente.nombre + " demande(s) qui attendent le CEO", d.en_attente.nombre ? "rouge" : null),
        tuileMontant(d.a_decaisser.montant, d.a_decaisser.nombre + " approuvée(s), à décaisser", d.a_decaisser.nombre ? "rouge" : null),
        tuile(virgule(d.delai_decision_jours) + (d.delai_decision_jours === null ? "" : " j"), "délai moyen de décision du CEO")),
      barresMois("Décaissé par mois", pm, "montant_decaisse"),
      tableauExportable("Dépenses par mois", "BIZZOO_depenses_" + periode.depuis + "_au_" + periode.jusqu,
        [["Mois", "texte", 14], ["Demandes", "nombre", 10], ["Montant demandé", "fcfa"], ["Approuvé", "fcfa"], ["Refusées", "nombre", 10],
         ["Décaissées", "nombre", 10], ["Montant décaissé", "fcfa"]],
        pm.map((m) => [UI.mois(m.mois), m.demandees, m.montant_demande, m.approuvees, m.refusees, m.decaissees, m.montant_decaisse])),
      d.par_profil.length ? tableauExportable("Décaissé par profil", "BIZZOO_depenses_par_profil",
        [["Profil", "texte", 24], ["Dépenses", "nombre", 10], ["Montant", "fcfa"]],
        d.par_profil.map((p) => [p.profil, p.nombre, p.montant])) : null,
      d.plus_grosses.length ? tableauExportable("Les plus grosses dépenses décaissées", "BIZZOO_plus_grosses_depenses",
        [["Objet", "texte", 34], ["Profil", "texte", 20], ["Décaissée le", "texte", 14], ["Montant", "fcfa"]],
        d.plus_grosses.map((x) => ["N° " + x.numero + " · " + x.objet, x.profil, UI.date(x.le), x.montant])) : null,
    ];
  }

  const ETATS_EMPLOYE = { actif: "En poste", bloque: "Bloqués", en_attente: "À valider", refuse: "Refusés", sorti: "Sortis", supprime: "Archivés" };
  function effectifs(fi) {
    const e = fi.effectifs;
    const anciennete = e.anciennete_moyenne_mois === null ? "—" : Number(e.anciennete_moyenne_mois) >= 12
      ? virgule(Math.round(e.anciennete_moyenne_mois / 12 * 10) / 10) + " an(s)" : virgule(e.anciennete_moyenne_mois) + " mois";
    const repartition = (titre, objet, noms) => {
      const lignes = Object.entries(objet || {}).sort((a, b) => b[1] - a[1]);
      return lignes.length ? tableau(titre, ["", "Personnes"], lignes.map(([k, n]) => [(noms && noms[k]) || k, nombre(n)])) : null;
    };
    return [
      h("div", { class: "tuiles" },
        tuile(nombre(e.en_poste), "en poste (bloqués compris)"),
        tuile(fcfa(e.masse_base), "masse des salaires de base", true),
        tuile(fcfa(e.salaire_base_moyen), "salaire de base moyen", true),
        tuile(e.age_moyen === null ? "—" : virgule(e.age_moyen) + " ans", "âge moyen"),
        tuile(anciennete, "ancienneté moyenne")),
      e.par_profil.length ? tableauExportable("Par profil", "BIZZOO_effectifs_par_profil",
        [["Profil", "texte", 24], ["Personnes", "nombre", 10], ["Salaires de base", "fcfa"]],
        e.par_profil.map((p) => [p.profil, p.effectif, p.masse_base])) : null,
      repartition("Statut", e.par_statut, { employe: "Employés", stagiaire: "Stagiaires" }),
      repartition("Sexe", e.par_sexe, { M: "Hommes", F: "Femmes", NR: "Non renseigné" }),
      repartition("Niveau d'étude", e.par_niveau),
      repartition("Toutes les fiches, par état", e.par_etat, ETATS_EMPLOYE),
      tableau("Embauches et sorties par mois", ["Mois", "Embauches", "Sorties"],
        e.mouvements.map((m) => [UI.mois(m.mois), nombre(m.embauches), nombre(m.sorties)])),
    ];
  }

  const STATUTS_MISSION = { proposee: "Proposées", acceptee: "Acceptées", refusee: "Refusées", rapport_remis: "Rapport remis",
    a_reprendre: "À reprendre", cloturee: "Clôturées" };
  const STATUTS_RAPPORT = { brouillon: "Brouillons", publie: "Publiés, à valider", valide: "Validés", rejete: "Rejetés" };
  function activite(fi) {
    const a = fi.activite;
    const cloturees = Number(a.cloturees_a_temps) + Number(a.cloturees_en_retard);
    return [
      h("div", { class: "tuiles" },
        tuile(nombre(a.missions), "missions créées sur la période"),
        tuile(cloturees ? Math.round(a.cloturees_a_temps / cloturees * 100) + " %" : "—", "clôturées rendues à temps"),
        tuile(nombre(a.cloturees_en_retard), "rendues en retard"),
        h("div", { class: "tuile" + (a.en_retard_aujourdhui ? " alerte" : "") }, h("b", {}, nombre(a.en_retard_aujourdhui)), h("span", {}, "en retard aujourd'hui")),
        tuile(a.delai_reponse_heures === null ? "—" : virgule(a.delai_reponse_heures) + " h", "délai moyen de réponse du responsable"),
        tuile(nombre(a.rapports), "rapports d'activité publiés"),
        tuile(a.delai_validation_jours === null ? "—" : virgule(a.delai_validation_jours) + " j", "délai moyen de validation par le CEO")),
      Object.keys(a.missions_par_statut).length ? tableau("Missions par étape", ["Étape", "Missions"],
        Object.entries(a.missions_par_statut).map(([k, n]) => [STATUTS_MISSION[k] || k, nombre(n)])) : UI.vide("Aucune mission créée sur la période."),
      a.missions_par_profil.length ? tableau("Missions par profil", ["Profil", "Créées", "Clôturées", "Refusées", "En cours"],
        a.missions_par_profil.map((p) => [p.profil, nombre(p.creees), nombre(p.cloturees), nombre(p.refusees), nombre(p.en_cours)])) : null,
      Object.keys(a.rapports_par_statut).length ? tableau("Rapports d'activité", ["Étape", "Rapports"],
        Object.entries(a.rapports_par_statut).map(([k, n]) => [STATUTS_RAPPORT[k] || k, nombre(n)])) : null,
    ];
  }

  function revenus(fi, periode) {
    const r = fi.revenus;
    const resultat = somme(r, "resultat");
    return [
      h("div", { class: "tuiles" },
        tuileMontant(somme(r, "revenus"), "revenus de BIZZOO", "alerte"),
        tuileMontant(somme(r, "salaires"), "salaires (coût employeur)"),
        tuileMontant(somme(r, "depenses"), "dépenses décaissées"),
        tuileMontant(resultat, "résultat estimé", resultat < 0 ? "rouge" : "vert"),
        tuileMontant(somme(r, "encaisse"), somme(r, "commandes") + " commande(s) payée(s) : encaissé"),
        tuileMontant(somme(r, "reverse_boutiques"), "reversé aux boutiques"),
        tuileMontant(somme(r, "marge"), "marge sur les produits"),
        tuileMontant(somme(r, "frais_livraison"), "frais de livraison payés par les clients"),
        tuileMontant(somme(r, "gains_livreurs"), "gains versés aux livreurs"),
        tuileMontant(somme(r, "remises"), "remises (codes promo)")),
      h("p", { class: "doux petit" }, "Revenus = marge sur les produits + frais de livraison − remises − gains des livreurs. ",
        "Résultat = revenus − salaires (fiches validées : brut + charges patronales) − dépenses décaissées. ",
        "C'est une estimation de gestion, pas une comptabilité : les autres charges (loyer, impôts sur les bénéfices…) n'y sont que si elles passent par les dépenses."),
      barresMois("Résultat par mois", r, "resultat"),
      tableauExportable("Revenus et résultat par mois", "BIZZOO_revenus_resultat_" + periode.depuis + "_au_" + periode.jusqu,
        [["Mois", "texte", 14], ["Commandes", "nombre", 10], ["Encaissé", "fcfa"], ["Reversé boutiques", "fcfa"], ["Marge", "fcfa"],
         ["Frais de livraison", "fcfa"], ["Remises", "fcfa"], ["Gains livreurs", "fcfa"], ["Revenus", "fcfa"], ["Salaires", "fcfa"],
         ["Dépenses", "fcfa"], ["Résultat", "fcfa"]],
        r.map((m) => [UI.mois(m.mois), m.commandes, m.encaisse, m.reverse_boutiques, m.marge, m.frais_livraison, m.remises,
          m.gains_livreurs, m.revenus, m.salaires, m.depenses, m.resultat])),
    ];
  }

  const INTERNES = { salaires, depenses, effectifs, activite, revenus };

  return { titre: "Statistiques", afficher, SOUS_MENUS };
})();
