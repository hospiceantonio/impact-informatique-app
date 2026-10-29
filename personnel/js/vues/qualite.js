/* =========================================================
   Qualité — comment BIZZOO sert ses clients, pas seulement
   combien elle vend.

   #/qualite/sav        : les réclamations en trois colonnes (la
                          boutique doit répondre, le client lit, BIZZOO
                          tranche), le délai de réponse et la note de
                          chaque boutique (?p=30j, ou ?du=…&au=…) ;
   #/qualite/boutiques  : la fiche qualité de chaque boutique, feu vert,
                          orange ou rouge, et « Créer une mission
                          d'accompagnement » ;
   #/qualite/catalogue  : ruptures qui coûtent des ventes, réassorts
                          dépassés, fiches incomplètes, produits masqués ;
                          « boutique appelée » se coche ;
   #/qualite/files      : ce qui attend une décision dans BIZZOO Admin ;
   #/qualite/zones      : le service par commune ou par quartier ;
   #/qualite/fidelite   : réachat, clients perdus, liste à relancer ;
   #/qualite/seuils     : les seuils (administration).

   Rien ne se décide ici : les réclamations se tranchent, les demandes se
   valident dans BIZZOO Admin. La base dit ce que chacun voit
   (rh_qualite_acces) : les ventes, les noms des clients et la liste à
   relancer ne viennent que pour l'administration.
   ========================================================= */
const VueQualite = (() => {
  const { h } = UI;
  const ROUTE = "#/qualite";
  const ONGLETS = [
    ["sav", "SAV et satisfaction"],
    ["boutiques", "Boutiques"],
    ["catalogue", "Catalogue"],
    ["files", "Files d'attente"],
    ["zones", "Zones"],
    ["fidelite", "Fidélité"],
  ];
  const SUJETS = { non_recu: "Non reçu", abime: "Abîmé", pas_conforme: "Pas conforme", incomplet: "Incomplet", autre: "Autre" };
  const COLONNES = [
    ["boutique", "La boutique doit répondre", "Personne ne lui a encore répondu, ou le client a réécrit depuis sa réponse."],
    ["client", "En attente du client", "La boutique a répondu : le client lit, clôt ou fait appel à BIZZOO."],
    ["bizzoo", "À trancher par BIZZOO", "Le client a fait appel : la décision se prend dans BIZZOO Admin, menu SAV."],
  ];
  const PROBLEMES = {
    vue_lente: "Voit tard ses commandes",
    non_vues: "Commandes payées jamais vues",
    preparation_lente: "Prépare lentement",
    annulations: "Annule trop d'articles",
    reclamations: "Trop de réclamations",
    ruptures: "Trop de produits épuisés",
    note: "Note basse",
    horaires: "Pas d'horaires d'ouverture",
  };
  const FEUX = { rouge: ["Rouge", "rouge"], orange: ["Orange", "orange"], vert: ["Vert", "vert"] };
  const ANOMALIES = {
    ruptures: ["rupture", "Ruptures qui coûtent des ventes"],
    appro_depasse: ["appro", "Réapprovisionnement dépassé"],
    sans_photo: ["photo", "Fiches sans photo"],
    sans_categorie: ["categorie", "Fiches sans catégorie"],
    masques: ["masque", "Masqués depuis longtemps"],
  };

  const tuile = (valeur, libelle, alerte) => h("div", { class: "tuile" + (alerte ? " alerte" : "") }, h("b", {}, valeur), h("span", {}, libelle));
  const virgule = (n) => (n === null || n === undefined ? "—" : String(n).replace(".", ","));
  const pct = (n) => (n === null || n === undefined ? "—" : virgule(n) + " %");
  /** « 30 h » ou « 3 j 4 h » : une attente. */
  const attente = (n) => {
    if (n === null || n === undefined) return "—";
    const x = Math.round(Number(n));
    if (x < 48) return virgule(Math.round(Number(n) * 10) / 10) + " h";
    const j = Math.floor(x / 24);
    return j + " j " + (x - j * 24) + " h";
  };
  const note = (n) => (n === null || n === undefined ? "—" : virgule(Number(n).toFixed(1)) + " / 5");
  /** Un lien vers l'écran de BIZZOO Admin qui décide. */
  const versAdmin = (route, libelle) => h("a", { class: "btn btn-second btn-petit", href: "../admin/#/" + route, target: "_blank", rel: "noopener" },
    "Ouvrir dans Admin" + (libelle ? " — " + libelle : ""));

  /* Le relevé des notes, à l'ouverture, au plus une fois toutes les 6 h :
     sans pg_cron, c'est lui qui garde l'historique des notes. */
  let releve = 0;

  async function afficher(zone, morceaux, params) {
    const c = await Supabase.rpc("rh_qualite_compteurs");
    if (!zone.isConnected) return;
    if (!c || !c.acces) {
      UI.vider(zone, UI.vide("Votre compte n'a pas accès au menu Qualité."));
      return;
    }
    if (Date.now() - releve > 6 * 3600 * 1000) {
      releve = Date.now();
      Supabase.rpc("rh_notes_releve").catch(() => {});
    }
    const admin = c.acces === "admin";
    const items = ONGLETS.concat(admin ? [["seuils", "Seuils"]] : []);
    const page = items.some((x) => x[0] === morceaux[0]) ? morceaux[0] : "sav";
    const pastilles = {
      sav: (c.sav_sans_reponse || 0) + (c.sav_escalades || 0),
      catalogue: c.ruptures_a_appeler || 0,
      files: c.files_en_retard || 0,
    };
    const barre = h("div", { class: "filtres" }, items.map(([v, l]) =>
      h("button", { class: v === page ? "actif" : "", onclick: () => { location.hash = ROUTE + "/" + v; } }, l,
        pastilles[v] > 0 ? h("span", { class: "pastille", style: { marginLeft: "6px" } }, pastilles[v] > 99 ? "99+" : pastilles[v]) : null)));
    const PAGES = { sav, boutiques, catalogue, files, zones, fidelite, seuils };
    await PAGES[page](zone, barre, params, admin);
    const actif = zone.querySelector(".filtres .actif");
    if (actif) actif.scrollIntoView({ inline: "center", block: "nearest" });
  }

  /* ---------- SAV et satisfaction ---------- */

  async function sav(zone, barre, params, admin) {
    const periode = VueStatistiques.periodeDe(params, "30j");
    const d = await Supabase.rpc("rh_satisfaction", { depuis: periode.depuis, jusqu: periode.jusqu });
    if (!zone.isConnected) return;
    const t = d.totaux, s = d.seuils;
    const ALERTES = { sans_reponse: "Sans réponse depuis plus de " + s.reponse_h + " h", escalade_en_attente: "Pas tranchée depuis plus de " + s.decision_h + " h" };

    const carteReclamation = (r) => h("div", { class: "element", style: r.alerte ? { boxShadow: "inset 3px 0 0 var(--orange)" } : null },
      h("div", { class: "etire" },
        h("div", { class: "ligne" }, h("span", { class: "gras etire coupe" }, r.boutique),
          UI.etiquette(SUJETS[r.sujet] || r.sujet, r.sujet === "non_recu" ? "rouge" : "")),
        h("div", { class: "petit doux" }, ["Commande " + (r.commande || "—"), r.client].filter(Boolean).join(" · ")),
        h("div", { class: "petit" }, "Attend depuis " + attente(r.heures) + " · ouverte le " + UI.dateHeure(r.cree_le)),
        r.motif ? h("div", { class: "tres-petit doux" }, "Motif de l'appel : " + r.motif) : null,
        r.alerte ? UI.etiquette(ALERTES[r.alerte] || r.alerte, "rouge") : null));

    const colonnes = h("div", { class: "grille" }, COLONNES.map(([cle, titre, aide]) => {
      const liste = d.reclamations.filter((r) => r.colonne === cle);
      return h("div", { class: "carte pile" },
        h("div", { class: "ligne" }, h("h3", { class: "etire", style: { margin: 0 } }, titre), UI.etiquette(UI.entier(liste.length), liste.some((r) => r.alerte) ? "rouge" : "bleu")),
        h("p", { class: "tres-petit doux", style: { margin: 0 } }, aide),
        liste.length ? h("div", { class: "liste" }, liste.slice(0, 50).map(carteReclamation)) : UI.vide("Rien ici."),
        liste.length > 50 ? h("p", { class: "tres-petit doux" }, "Les 50 premières sur " + liste.length + ".") : null);
    }));

    const parBoutique = d.boutiques.length ? h("div", { class: "carte defile" },
      h("h3", { style: { marginBottom: "8px" } }, "Par boutique"),
      h("table", { class: "tableau" },
        h("thead", {}, h("tr", {}, h("th", {}, "Boutique"), h("th", { class: "nombre" }, "Réclamations"), h("th", { class: "nombre" }, "Répondues"),
          h("th", {}, "Délai de réponse"), h("th", {}, "Le plus long"), h("th", { class: "nombre" }, "Sans réponse"),
          h("th", { class: "nombre" }, "Escaladées"), h("th", {}, "Note"), h("th", {}, "Il y a 30 j"), h("th", {}, "8 semaines"))),
        h("tbody", {}, d.boutiques.map((b) => h("tr", { class: b.chute || b.sans_reponse > 0 ? "en-alerte" : "" },
          h("td", {}, h("div", { class: "gras" }, b.boutique), b.chute ? UI.etiquette("Note en chute", "rouge") : null),
          h("td", { class: "nombre" }, UI.entier(b.reclamations)),
          h("td", { class: "nombre" }, UI.entier(b.repondues)),
          h("td", {}, attente(b.delai_reponse_h)),
          h("td", {}, attente(b.delai_reponse_max_h)),
          h("td", { class: "nombre" }, UI.entier(b.sans_reponse)),
          h("td", { class: "nombre" }, UI.entier(b.escaladees)),
          h("td", {}, note(b.note), h("div", { class: "tres-petit doux" }, UI.entier(b.nb_avis) + " avis")),
          h("td", {}, note(b.note_avant), b.variation !== null && b.variation !== undefined
            ? h("div", { class: "tres-petit", style: { color: b.variation < 0 ? "var(--rouge-fonce)" : "var(--vert-fonce)" } },
              (b.variation > 0 ? "+" : "") + virgule(Number(b.variation).toFixed(1)))
            : null),
          h("td", { class: "tres-petit doux" }, (b.semaines || []).map((x) => x.note === null ? "—" : virgule(Number(x.note).toFixed(1))).join(" · ")))))))
      : null;

    UI.vider(zone,
      barre,
      UI.barrePeriode(periode, ROUTE + "/sav"),
      h("p", { class: "doux petit" }, "Les réclamations ouvertes s'affichent quelle que soit la période ; les délais et le tableau par boutique, ceux des réclamations ouvertes sur la période. " +
        "Alerte : une boutique qui n'a pas répondu après " + s.reponse_h + " h, un appel à BIZZOO pas tranché après " + s.decision_h + " h. " +
        "La note : celle d'aujourd'hui, et celle d'il y a 30 jours (relevée chaque jour, ou recalculée sur les avis quand le relevé manque) ; une baisse de " +
        virgule(s.note_chute) + " point ou plus est signalée. Tout se décide dans BIZZOO Admin, menu SAV." +
        (admin ? "" : " Sans le nom des clients, réservé à l'administration.")),
      h("div", { class: "tuiles compactes" },
        tuile(UI.entier(t.boutique), "la boutique doit répondre", t.sans_reponse > 0),
        tuile(UI.entier(t.sans_reponse), "sans réponse au-delà de " + s.reponse_h + " h", t.sans_reponse > 0),
        tuile(UI.entier(t.client), "en attente du client"),
        tuile(UI.entier(t.bizzoo), "à trancher par BIZZOO", t.escalades_en_retard > 0),
        tuile(UI.entier(t.escalades_en_retard), "pas tranchées au-delà de " + s.decision_h + " h", t.escalades_en_retard > 0),
        tuile(UI.entier(t.creees), "réclamations sur la période"),
        tuile(attente(t.delai_reponse_h), "délai moyen de réponse"),
        tuile(attente(t.delai_decision_h), "délai moyen de décision")),
      h("div", { class: "actions" }, versAdmin("sav", "SAV")),
      colonnes,
      parBoutique);
  }

  /* ---------- La fiche qualité des boutiques ---------- */

  async function boutiques(zone, barre, params, admin) {
    const periode = VueStatistiques.periodeDe(params, "30j");
    const d = await Supabase.rpc("rh_qualite_boutiques", { depuis: periode.depuis, jusqu: periode.jusqu });
    if (!zone.isConnected) return;
    const s = d.seuils;
    const filtre = params.feu || "tous";
    const liste = d.boutiques.filter((b) => filtre === "tous" || b.feu === filtre);
    const compte = (f) => d.boutiques.filter((b) => b.feu === f).length;

    /* La mission se prépare dans le formulaire existant, prérempli : on
       la relit, on choisit le profil et l'échéance, on la crée. */
    const mission = (b) => {
      const titre = "Accompagner la boutique " + b.boutique;
      const lignes = (b.problemes || []).map((p) => "- " + (PROBLEMES[p] || p));
      const description = "Fiche qualité du " + UI.date(d.periode.depuis) + " au " + UI.date(d.periode.jusqu) + " :\n" + lignes.join("\n") +
        "\n\nObjectif : appeler la boutique, comprendre, et revenir avec un plan.";
      location.hash = "#/missions/nouvelle?titre=" + encodeURIComponent(titre) + "&description=" + encodeURIComponent(description);
    };

    const fiche = (b) => h("div", { class: "carte pile", style: b.feu !== "vert" ? { boxShadow: "inset 3px 0 0 var(--" + (b.feu === "rouge" ? "rouge" : "orange") + ")" } : null },
      h("div", { class: "ligne" },
        h("h3", { class: "etire", style: { margin: 0 } }, b.boutique),
        !b.actif ? UI.etiquette("Fermée", "") : null,
        UI.etiquette(...FEUX[b.feu])),
      h("div", { class: "tuiles compactes" },
        tuile(attente(b.delai_vue_h), "pour voir une commande", (b.problemes || []).includes("vue_lente")),
        tuile(attente(b.delai_preparation_h), "pour la préparer", (b.problemes || []).includes("preparation_lente")),
        tuile(pct(b.annulation_pct), UI.entier(b.annulees) + " article(s) annulé(s) sur " + UI.entier(b.lignes), (b.problemes || []).includes("annulations")),
        tuile(UI.entier(b.reclamations), "réclamation(s) pour " + UI.entier(b.commandes) + " commande(s)", (b.problemes || []).includes("reclamations")),
        tuile(pct(b.rupture_pct), UI.entier(b.ruptures) + " épuisé(s) sur " + UI.entier(b.produits), (b.problemes || []).includes("ruptures")),
        tuile(note(b.note), UI.entier(b.nb_avis) + " avis", (b.problemes || []).includes("note")),
        tuile(b.horaires ? "Oui" : "Non", "horaires d'ouverture", !b.horaires),
        admin ? tuile(UI.fcfa(b.ventes), "ventes de la période") : null),
      (b.problemes || []).length ? h("div", { class: "actions" }, b.problemes.map((p) => UI.etiquette(PROBLEMES[p] || p, b.feu === "rouge" ? "rouge" : "orange"))) : null,
      b.non_vues ? h("div", { class: "petit" }, UI.entier(b.non_vues) + " article(s) payé(s) jamais vu(s) depuis plus de " + s.qualite_vue_h + " h.") : null,
      App.estAdmin() && b.feu !== "vert" ? h("div", { class: "actions" },
        h("button", { class: "btn btn-second btn-petit", onclick: () => mission(b) }, UI.icone("mission", "ic-sm"), "Créer une mission d'accompagnement")) : null);

    UI.vider(zone,
      barre,
      UI.barrePeriode(periode, ROUTE + "/boutiques", filtre !== "tous" ? "&feu=" + filtre : ""),
      h("p", { class: "doux petit" }, "Comment chaque boutique sert ses clients, sur les commandes payées de la période. Un signal : voir une commande en plus de " +
        s.qualite_vue_h + " h en moyenne, la préparer en plus de " + s.qualite_preparation_h + " h, plus de " + s.annulation_pct + " % d'articles annulés, plus de " +
        s.reclamation_pct + " réclamations pour 100 commandes, plus de " + s.rupture_pct + " % de produits épuisés, une note sous " + virgule(s.note_min) +
        ", pas d'horaires. Rouge à deux signaux ou plus, orange à un." + (admin ? "" : " Les ventes sont réservées à l'administration.")),
      h("div", { class: "filtres" }, [["tous", "Toutes (" + d.boutiques.length + ")"], ["rouge", "Rouges (" + compte("rouge") + ")"],
        ["orange", "Orange (" + compte("orange") + ")"], ["vert", "Vertes (" + compte("vert") + ")"]].map(([v, l]) =>
        h("button", { class: v === filtre ? "actif" : "", onclick: () => {
          location.hash = ROUTE + "/boutiques" + (periode.suffixe || "?p=30j") + (v !== "tous" ? "&feu=" + v : "");
        } }, l))),
      liste.length ? h("div", { class: "pile" }, liste.map(fiche)) : UI.vide("Aucune boutique ici."));
  }

  /* ---------- La santé du catalogue ---------- */

  async function catalogue(zone, barre, params) {
    const d = await Supabase.rpc("rh_catalogue_anomalies");
    if (!zone.isConnected) return;
    const t = d.totaux;
    const choix = ANOMALIES[params.voir] ? params.voir : "ruptures";
    const [anomalie, titre] = ANOMALIES[choix];
    const liste = d[choix] || [];

    const caseAppel = (p) => {
      const coche = h("input", { type: "checkbox", checked: !!p.appel });
      coche.addEventListener("change", async () => {
        let mot = "";
        if (coche.checked) {
          // Pas UI.motif : il rend la note obligatoire (et le bouton rouge), alors que
          // l'appel se note même sans réponse de la boutique ; la base accepte une note vide.
          const r = await UI.formulaire({ titre: "Boutique appelée", valider: "Noter l'appel",
            champs: [{ nom: "note", libelle: "Ce qu'elle a dit (facultatif)", type: "textarea" }] });
          if (r === null) { coche.checked = false; return; }
          mot = (r.note || "").trim();
        }
        coche.disabled = true;
        try {
          await Supabase.rpc("rh_catalogue_appeler", { cible_produit: p.id, cible_anomalie: anomalie, appele: coche.checked, v_note: mot || "" });
          UI.succes(coche.checked ? "Appel noté." : "Appel retiré.");
          App.rafraichir();
          afficher(zone, ["catalogue"], params);
        } catch (err) {
          coche.checked = !coche.checked;
          coche.disabled = false;
          UI.echec(err);
        }
      });
      return h("label", { class: "ligne petit", style: { gap: "6px" } }, coche, "Boutique appelée");
    };

    const detail = (p) => {
      if (choix === "ruptures") return "Vendus en 30 jours : " + UI.entier(p.vendus_30j) + " (rang " + UI.entier(p.rang) + ") · dernière vente " + UI.dateHeure(p.derniere_vente) +
        (p.appro_le ? " · réassort prévu le " + UI.date(p.appro_le) + (p.retard_j ? " (dépassé de " + p.retard_j + " j)" : "") : "");
      if (choix === "appro_depasse") return "Réassort prévu le " + UI.date(p.appro_le) + " : dépassé de " + p.retard_j + " jour(s) · vendus en 30 jours : " + UI.entier(p.vendus_30j);
      if (choix === "masques") return p.masque_le ? "Masqué le " + UI.date(p.masque_le) + " (" + p.jours + " jours)" + (p.masque_par ? " par " + p.masque_par : "") : "Masqué avant que la date soit notée";
      return "";
    };

    UI.vider(zone,
      barre,
      h("p", { class: "doux petit" }, "Aujourd'hui. Une rupture « coûte » quand le produit épuisé (ni « sur commande », ni masqué) s'est vendu au moins " + d.seuils.populaire_min +
        " fois en 30 jours ; les mieux vendus d'abord. Un produit masqué compte après " + d.seuils.masque_j + " jours. « Boutique appelée » vaut 7 jours. Le stock se corrige dans BIZZOO Admin, par la boutique."),
      h("div", { class: "tuiles compactes" },
        tuile(UI.entier(t.ruptures), "ruptures qui coûtent des ventes", t.ruptures_a_appeler > 0),
        tuile(UI.entier(t.ruptures_a_appeler), "pas encore appelées", t.ruptures_a_appeler > 0),
        tuile(UI.entier(t.epuises), "produits épuisés en tout"),
        tuile(UI.entier(t.appro_depasse), "réassorts dépassés", t.appro_depasse > 0),
        tuile(UI.entier(t.sans_photo), "fiches sans photo"),
        tuile(UI.entier(t.sans_categorie), "fiches sans catégorie"),
        tuile(UI.entier(t.masques), "masqués depuis longtemps")),
      h("div", { class: "filtres" }, Object.entries(ANOMALIES).map(([v, [, l]]) =>
        h("button", { class: v === choix ? "actif" : "", onclick: () => { location.hash = ROUTE + "/catalogue?voir=" + v; } }, l))),
      liste.length ? h("div", { class: "carte pile" },
        h("h3", { style: { margin: 0 } }, titre),
        h("div", { class: "liste" }, liste.map((p) => h("div", { class: "element", style: !p.appel && choix === "ruptures" ? { boxShadow: "inset 3px 0 0 var(--orange)" } : null },
          h("div", { class: "etire" },
            h("div", { class: "ligne" }, h("span", { class: "gras etire coupe" }, p.produit), p.code ? h("span", { class: "tres-petit doux" }, "Code " + p.code) : null),
            h("div", { class: "petit doux" }, p.boutique),
            detail(p) ? h("div", { class: "petit" }, detail(p)) : null,
            p.appel ? h("div", { class: "tres-petit doux" }, "Appelée le " + UI.dateHeure(p.appel.le) + (p.appel.par ? " par " + p.appel.par : "") + (p.appel.note ? " : « " + p.appel.note + " »" : "")) : null),
          caseAppel(p)))))
        : UI.vide("Rien à signaler ici."));
  }

  /* ---------- Les files d'attente de décision ---------- */

  async function files(zone, barre) {
    const d = await Supabase.rpc("rh_files_attente");
    if (!zone.isConnected) return;
    UI.vider(zone,
      barre,
      h("p", { class: "doux petit" }, "Ce qui attend une décision dans BIZZOO Admin. Une file passe en rouge quand sa demande la plus ancienne attend plus que son seuil. " +
        "Le délai moyen de décision est celui des 30 derniers jours (la base ne date pas la validation d'un compte d'équipe)."),
      h("div", { class: "pile" }, d.files.map((f) => h("div", { class: "carte pile", style: f.rouge ? { boxShadow: "inset 3px 0 0 var(--rouge)" } : null },
        h("div", { class: "ligne" }, h("h3", { class: "etire", style: { margin: 0 } }, f.libelle),
          UI.etiquette(f.nombre ? UI.entier(f.nombre) + " en attente" : "Vide", f.rouge ? "rouge" : f.nombre ? "orange" : "vert")),
        h("div", { class: "tuiles compactes" },
          tuile(f.plus_ancienne ? UI.quand(f.plus_ancienne) : "—", "la plus ancienne", f.rouge),
          tuile(attente(f.attente_moyenne_h), "attente moyenne"),
          tuile(UI.entier(f.en_retard), "au-delà de " + f.seuil_h + " h", f.en_retard > 0),
          tuile(attente(f.delai_decision_h), "délai moyen de décision")),
        h("div", { class: "actions" }, versAdmin(f.route, f.ecran))))));
  }

  /* ---------- Le service par zone ---------- */

  async function zones(zone, barre, params) {
    const periode = VueStatistiques.periodeDe(params, "30j");
    const niveau = params.niveau === "quartier" ? "quartier" : "commune";
    const d = await Supabase.rpc("rh_statistiques_zones", { depuis: periode.depuis, jusqu: periode.jusqu, niveau });
    if (!zone.isConnected) return;
    const tous = d.zones.reduce((s, z) => s + z.commandes, 0);
    UI.vider(zone,
      barre,
      UI.barrePeriode(periode, ROUTE + "/zones", "&niveau=" + niveau),
      h("div", { class: "filtres" }, [["commune", "Par commune"], ["quartier", "Par quartier"]].map(([v, l]) =>
        h("button", { class: v === niveau ? "actif" : "", onclick: () => { location.hash = ROUTE + "/zones" + (periode.suffixe || "?p=30j") + "&niveau=" + v; } }, l))),
      h("p", { class: "doux petit" }, "Les commandes payées de la période, par zone du suivi des commandes (corrigée par l'administration, sinon lue dans l'adresse). " +
        "Délai : du paiement à la réception confirmée par le client (ou à la remise déclarée), commandes entièrement livrées ; « lente » au-delà de " + d.zone_lent_h +
        " h. Distance et tricycle : commandes livrées au kilomètre (depuis la 3.64.0). " + UI.entier(tous) + " commande(s)."),
      d.zones.length ? h("div", { class: "carte defile" },
        h("table", { class: "tableau" },
          h("thead", {}, h("tr", {}, h("th", {}, niveau === "commune" ? "Commune" : "Quartier"), h("th", { class: "nombre" }, "Commandes"),
            h("th", { class: "nombre" }, "Livrées"), h("th", {}, "Délai moyen"), h("th", {}, "Lentes"), h("th", {}, "Échecs, retours"),
            h("th", {}, "Non reçues"), h("th", {}, "Distance moyenne"), h("th", {}, "Tricycle"))),
          h("tbody", {}, d.zones.map((z) => h("tr", { class: z.lentes_pct >= 20 || z.non_recus > 0 || z.echecs > 0 ? "en-alerte" : "" },
            h("td", { class: "gras" }, z.zone),
            h("td", { class: "nombre" }, UI.entier(z.commandes)),
            h("td", { class: "nombre" }, UI.entier(z.livrees)),
            h("td", {}, attente(z.delai_moyen_h)),
            h("td", {}, UI.entier(z.lentes) + (z.lentes_pct !== null ? " (" + pct(z.lentes_pct) + ")" : "")),
            h("td", {}, UI.entier(z.echecs) + " (" + pct(z.echecs_pct) + ")"),
            h("td", {}, UI.entier(z.non_recus) + " (" + pct(z.non_recus_pct) + ")"),
            h("td", {}, z.distance_moyenne_km !== null ? virgule(z.distance_moyenne_km) + " km" : "—"),
            h("td", {}, pct(z.tricycle_pct)))))))
        : UI.vide("Aucune commande payée sur la période."));
  }

  /* ---------- La fidélité des clients ---------- */

  async function fidelite(zone, barre, params, admin) {
    const periode = VueStatistiques.periodeDe(params, "30j");
    const d = await Supabase.rpc("rh_statistiques_clients", { depuis: periode.depuis, jusqu: periode.jusqu });
    if (!zone.isConnected) return;
    const t = d.totaux;
    const rachat = (n, p) => (n === null || n === undefined ? h("span", { class: "doux" }, "à venir") : UI.entier(n) + " (" + pct(p) + ")");

    const cohortes = d.cohortes.length ? h("div", { class: "carte defile" },
      h("h3", { style: { marginBottom: "8px" } }, "Cohortes : le mois du premier achat, et le retour"),
      h("table", { class: "tableau" },
        h("thead", {}, h("tr", {}, h("th", {}, "Premier achat"), h("th", { class: "nombre" }, "Nouveaux clients"),
          h("th", {}, "Rachat le mois suivant"), h("th", {}, "2 mois après"), h("th", {}, "3 mois après"), h("th", {}, "Revenus depuis"),
          admin ? h("th", { class: "nombre" }, "Valeur de la cohorte") : null)),
        h("tbody", {}, d.cohortes.map((c) => h("tr", {},
          h("td", { class: "gras" }, UI.mois(c.mois)),
          h("td", { class: "nombre" }, UI.entier(c.nouveaux)),
          h("td", {}, rachat(c.m1, c.m1_pct)),
          h("td", {}, rachat(c.m2, c.m2_pct)),
          h("td", {}, rachat(c.m3, c.m3_pct)),
          h("td", {}, UI.entier(c.revenus) + " (" + pct(c.revenus_pct) + ")"),
          admin ? h("td", { class: "nombre" }, UI.fcfa(c.valeur)) : null))))) : UI.vide("Aucun premier achat sur les 12 derniers mois.");

    const relance = admin && d.relance ? h("div", { class: "carte defile" },
      h("h3", { style: { marginBottom: "4px" } }, "À relancer : sans commande depuis " + d.inactif_j + " jours"),
      h("p", { class: "tres-petit doux" }, "Les plus fidèles d'abord (200 au plus). Le numéro est masqué : la commande citée se retrouve dans BIZZOO Admin, avec le client. Comptes supprimés exclus."),
      d.relance.length ? h("table", { class: "tableau" },
        h("thead", {}, h("tr", {}, h("th", {}, "Client"), h("th", {}, "Numéro"), h("th", { class: "nombre" }, "Commandes"), h("th", {}, "Dernière"),
          h("th", { class: "nombre" }, "Sans commande depuis"), h("th", { class: "nombre" }, "A dépensé"))),
        h("tbody", {}, d.relance.map((r) => h("tr", {},
          h("td", { class: "gras" }, r.nom || "—"),
          h("td", {}, r.tel || "—"),
          h("td", { class: "nombre" }, UI.entier(r.commandes)),
          h("td", {}, (r.derniere_commande || "—") + " · " + UI.date(r.dernier)),
          h("td", { class: "nombre" }, UI.entier(r.jours) + " j"),
          h("td", { class: "nombre" }, UI.fcfa(r.depense))))))
        : UI.vide("Personne à relancer.")) : null;

    UI.vider(zone,
      barre,
      UI.barrePeriode(periode, ROUTE + "/fidelite"),
      h("p", { class: "doux petit" }, "Un client, c'est son compte, ou à défaut son numéro. Seules les commandes payées comptent. Les cohortes couvrent les 12 mois qui finissent avec la période ; « à venir » : le mois n'est pas encore terminé (le mois en cours ne compte qu'une fois fini)." +
        (admin ? "" : " La valeur des clients et la liste à relancer sont réservées à l'administration.")),
      h("div", { class: "tuiles compactes" },
        tuile(UI.entier(t.actifs_periode), "clients sur la période"),
        tuile(UI.entier(t.nouveaux_periode), "nouveaux sur la période"),
        tuile(UI.entier(t.clients), "clients en tout"),
        tuile(pct(t.fideles_pct), "ont acheté plus d'une fois"),
        tuile(UI.entier(t.perdus_60), "sans commande depuis 60 jours", t.perdus_60 > 0),
        tuile(UI.entier(t.perdus_90), "sans commande depuis 90 jours", t.perdus_90 > 0),
        tuile(UI.entier(t.comptes_supprimes), "comptes supprimés (clients qui avaient acheté)")),
      cohortes,
      relance);
  }

  /* ---------- Les seuils ---------- */

  async function seuils(zone, barre) {
    /* Les seuils, et les libellés des files tels que la base les nomme. */
    const [valeurs, f] = await Promise.all([Supabase.rpc("rh_qualite_seuils"), Supabase.rpc("rh_files_attente")]);
    if (!zone.isConnected) return;
    const champs = [];
    const champ = (nom, libelle, aide, min, max, pas) => {
      const e = h("input", { type: "number", min, max, step: pas || 1, value: valeurs[nom], required: true });
      champs.push([nom, e, pas ? Number : (v) => Math.round(Number(v))]);
      return h("label", { class: "champ" }, h("span", {}, libelle), e, h("small", {}, aide));
    };
    const filesChamps = f.files.map((x) => {
      const e = h("input", { type: "number", min: 1, max: 720, value: (valeurs.files_h || {})[x.cle] || x.seuil_h, required: true });
      return [x.cle, e, h("label", { class: "champ" }, h("span", {}, x.libelle + " (heures)"), e)];
    });
    const form = h("form", { class: "carte pile" },
      h("h2", {}, "SAV"),
      h("div", { class: "formulaire" },
        champ("reponse_h", "Réclamation sans réponse (heures)", "au-delà, alerte « sans réponse »", 1, 720),
        champ("decision_h", "Appel à BIZZOO pas tranché (heures)", "au-delà, alerte « escalade en attente »", 1, 720),
        champ("note_chute", "Chute de la note en 30 jours", "en points, de 0,1 à 4", 0.1, 4, 0.1)),
      h("h2", {}, "Fiche des boutiques"),
      h("div", { class: "formulaire" },
        champ("qualite_vue_h", "Pour voir une commande (heures)", "délai moyen au-delà duquel c'est un signal", 1, 720),
        champ("qualite_preparation_h", "Pour la préparer (heures)", "délai moyen, une fois vue", 1, 720),
        champ("annulation_pct", "Articles annulés (%)", "", 1, 100),
        champ("reclamation_pct", "Réclamations pour 100 commandes", "", 1, 100),
        champ("rupture_pct", "Produits épuisés (%)", "", 1, 100),
        champ("note_min", "Note minimale", "de 1 à 5", 1, 5, 0.1)),
      h("h2", {}, "Catalogue"),
      h("div", { class: "formulaire" },
        champ("populaire_min", "Ventes en 30 jours pour une rupture « qui coûte »", "", 1, 1000),
        champ("masque_j", "Masqué depuis (jours)", "", 1, 365)),
      h("h2", {}, "Files d'attente"),
      h("div", { class: "formulaire" }, filesChamps.map((x) => x[2])),
      h("h2", {}, "Zones et fidélité"),
      h("div", { class: "formulaire" },
        champ("zone_lent_h", "Livraison « lente » (heures)", "du paiement à la livraison", 1, 720),
        champ("inactif_j", "Client à relancer après (jours)", "sans commande, de 30 à 365", 30, 365)),
      h("div", { class: "actions" }, h("button", { class: "btn", type: "submit" }, "Enregistrer")));
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const choix = {};
      for (const [nom, e, lire] of champs) choix[nom] = lire(e.value);
      choix.files_h = Object.fromEntries(filesChamps.map(([cle, e]) => [cle, Math.round(Number(e.value))]));
      await UI.agir(ev.submitter, () => Supabase.rpc("rh_qualite_regler", { choix }), "Seuils enregistrés.");
      App.rafraichir();
    });
    UI.vider(zone, barre, h("p", { class: "doux petit" }, "Des valeurs de départ, à régler. Elles servent aux alertes, aux feux des boutiques et aux pastilles du menu."), form);
  }

  return { titre: "Qualité", afficher };
})();
