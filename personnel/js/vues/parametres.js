/* =========================================================
   Paramètres — réservé à l'administration.

   #/parametres                 : les accès aux menus ;
   #/parametres/acces/<profil>  : les accès d'un profil ;
   #/parametres/entreprise      : l'en-tête des bulletins de paie ;
   #/parametres/autres          : les autres réglages, là où ils sont.

   Un menu s'ouvre à un profil pour son responsable seul, ou pour
   tous ses membres. C'est la base (rh_acces_menus, rh_regler_acces)
   qui applique ces accès : l'écran ne fait que les régler.
   ========================================================= */
const VueParametres = (() => {
  const { h } = UI;

  /** Les menus réglables : clé, libellé, ce qu'ils ouvrent. */
  const GROUPES = [
    ["Travail", [
      ["mails", "Mails", "La boîte professionnelle de chacun."],
      ["discussions", "Discussions", "La discussion du profil et les messages directs."],
      ["missions", "Missions", "Les missions du profil ; le responsable les accepte et rend le rapport."],
      ["rapports", "Rapports", "Le responsable publie ; les membres lisent les rapports validés."],
      ["depenses", "Dépenses", "Demander une dépense ; le responsable valide, puis le CEO, puis l'habilité décaisse."],
    ]],
    ["Commandes", [
      ["suivi", "Suivi des commandes", "Statuts, alertes, incidents, export Excel : sans les montants."],
      ["livreurs", "Localiser un livreur", "La carte des livreurs en course, et leur distance au client."],
      ["controles", "Contrôles des encaissements", "MoMoPay à vérifier, espèces pas rendues, écarts, par livreur : nombres et ancienneté, sans les montants."],
    ]],
    ["Caisse", [
      ["caisse", "Caisse (consultation)", "Le solde et les mouvements de la caisse, sans rien y faire. L'administration ne la voit pas d'office."],
    ]],
    ["Statistiques (sans les montants)", [
      ["stats_commandes", "Commandes", "Payées, passées, en attente, jour par jour."],
      ["stats_boutiques", "Boutiques qui vendent le plus", "Le classement des boutiques."],
      ["stats_produits", "Produits les plus vendus", "Les articles qui partent le plus."],
      ["stats_livraisons", "Livraisons", "Livrés, à livrer, annulés, délai moyen."],
      ["stats_livreurs", "Livreurs", "Ce que chaque livreur a livré."],
      ["stats_sav", "Service après-vente et avis", "Réclamations, avis et notes des clients."],
    ]],
    ["Employés", [
      ["employes", "Annuaire des employés", "En lecture : nom, poste, profil, contact pro. Aucun salaire."],
    ]],
  ];
  const MENUS = GROUPES.flatMap(([, items]) => items);
  const CHOIX = [["ferme", "Fermé"], ["responsable", "Responsable"], ["membres", "Tous les membres"]];
  const COURT = { ferme: "—", responsable: "Resp.", membres: "Tous" };

  function onglets(actif) {
    const items = [["", "Accès aux menus"], ["entreprise", "Entreprise"], ["autres", "Autres réglages"]];
    return h("div", { class: "filtres" }, items.map(([v, l]) =>
      h("button", { class: v === actif ? "actif" : "", onclick: () => { location.hash = "#/parametres" + (v ? "/" + v : ""); } }, l)));
  }

  async function afficher(zone, morceaux) {
    UI.vider(zone, UI.chargement());
    switch (morceaux[0]) {
      case "entreprise": return entreprise(zone);
      case "autres": return autres(zone);
      case "acces": return acces(zone, morceaux[1]);
      default: return acces(zone, null);
    }
  }

  /* ---------- Les accès aux menus ---------- */

  async function acces(zone, profilId) {
    const [profils, lignes] = await Promise.all([
      Supabase.lire("rh_profils?select=id,nom,responsable_id&order=nom"),
      Supabase.lire("rh_acces_menus?select=profil_id,menu,qui"),
    ]);
    if (!zone.isConnected) return;
    if (!profils.length) {
      return UI.vider(zone, onglets(""),
        UI.vide("Aucun profil. Créez d'abord les profils (Marketing, Logistique…) dans le menu Profils."),
        h("div", { class: "actions" }, h("a", { class: "btn btn-second", href: "#/profils" }, "Aller aux profils")));
    }
    const p = profils.find((x) => x.id === profilId) || profils[0];
    const etat = (profil, menu) => {
      const l = lignes.find((x) => x.profil_id === profil && x.menu === menu);
      return l ? l.qui : "ferme";
    };

    /* Un groupe de boutons radio par menu. */
    const choix = {};
    const ligneMenu = ([cle, libelle, texte, responsableSeul]) => {
      const nom = "acces-" + cle;
      choix[cle] = CHOIX.map(([v]) => h("input", { type: "radio", name: nom, value: v,
        checked: etat(p.id, cle) === v, disabled: responsableSeul && v === "membres" }));
      return h("tr", {},
        h("td", {}, h("div", { class: "gras" }, libelle), h("div", { class: "doux tres-petit" }, texte)),
        choix[cle].map((radio, i) => h("td", { class: "centre" },
          h("label", { class: "radio", title: CHOIX[i][1] }, radio))));
    };

    const enregistrer = async (ev) => {
      const reglage = {};
      for (const [cle] of MENUS) reglage[cle] = (choix[cle].find((r) => r.checked) || {}).value || "ferme";
      await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_regler_acces", { cible: p.id, choix: reglage }),
        "Accès du profil « " + p.nom + " » enregistrés : ils comptent dès la prochaine ouverture de l'application.");
      acces(zone, p.id);
    };

    UI.vider(zone,
      onglets(""),
      h("p", { class: "doux petit" },
        "Choisissez un profil, puis, menu par menu : fermé, ouvert à son responsable seul, ou à tous ses membres. ",
        "L'administration voit toujours tout. Profils, Paie et Paramètres restent à l'administration."),
      h("div", { class: "filtres" }, profils.map((x) =>
        h("button", { class: x.id === p.id ? "actif" : "", onclick: () => { location.hash = "#/parametres/acces/" + x.id; } }, x.nom))),
      p.responsable_id ? null : h("div", { class: "avertissement" },
        "Ce profil n'a pas de responsable : ce qui est ouvert au « responsable » ne sert à personne pour l'instant."),
      h("div", { class: "carte defile", style: { padding: "0" } },
        h("table", { class: "tableau tableau-acces" },
          /* Sur téléphone, les titres courts : les trois choix tiennent sans défiler. */
          h("thead", {}, h("tr", {}, h("th", {}, "Menu"), CHOIX.map(([v, l]) => h("th", { class: "centre" },
            h("span", { class: "long" }, l), h("span", { class: "court" }, v === "ferme" ? "Fermé" : COURT[v]))))),
          GROUPES.map(([groupe, items]) => h("tbody", {},
            h("tr", { class: "groupe" }, h("td", { colspan: "4" }, groupe)),
            items.map(ligneMenu))))),
      h("div", { class: "actions" },
        h("button", { class: "btn", onclick: enregistrer }, UI.icone("check", "ic-sm"), "Enregistrer les accès de « " + p.nom + " »")),
      h("h2", { style: { fontSize: "16px", marginTop: "8px" } }, "Vue d'ensemble"),
      h("div", { class: "carte defile", style: { padding: "0" } },
        h("table", { class: "tableau tableau-acces" },
          h("thead", {}, h("tr", {}, h("th", {}, "Menu"), profils.map((x) => h("th", { class: "centre" }, x.nom)))),
          h("tbody", {}, MENUS.map(([cle, libelle]) => h("tr", {},
            h("td", {}, libelle),
            profils.map((x) => {
              const v = etat(x.id, cle);
              return h("td", { class: "centre" }, v === "ferme" ? h("span", { class: "doux" }, COURT[v])
                : UI.etiquette(COURT[v], v === "membres" ? "vert" : "bleu"));
            })))))),
      h("p", { class: "doux tres-petit" }, "Resp. : le responsable du profil seul · Tous : tous les membres du profil."));
  }

  /* ---------- L'entreprise ---------- */

  const CHAMPS = [
    ["raison_sociale", "Raison sociale", true], ["site", "Site internet"], ["adresse", "Adresse"],
    ["telephone", "Téléphone"], ["email", "Adresse électronique"], ["ifu", "IFU"], ["rccm", "RCCM"],
    ["cnss_employeur", "N° employeur CNSS"],
  ];

  async function entreprise(zone) {
    const [e] = await Supabase.lire("rh_entreprise?select=*");
    if (!zone.isConnected) return;
    if (!e) return UI.vider(zone, onglets("entreprise"), UI.vide("Les paramètres de l'entreprise ne sont pas encore installés dans la base."));
    const champs = {};
    const form = h("form", { class: "carte pile" },
      h("div", { class: "formulaire" }, CHAMPS.map(([cle, libelle, requis]) =>
        h("label", { class: "champ" }, h("span", {}, libelle + (requis ? " *" : "")),
          champs[cle] = h("input", { value: e[cle] || "", maxlength: cle === "raison_sociale" ? "120" : "200", required: !!requis })))),
      h("div", { class: "actions" }, h("button", { class: "btn", type: "submit" }, UI.icone("check", "ic-sm"), "Enregistrer")));
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const valeurs = {};
      for (const [cle] of CHAMPS) valeurs[cle] = champs[cle].value.trim();
      if (!valeurs.raison_sociale) return UI.echec("La raison sociale est obligatoire.");
      await UI.agir(form.querySelector("button[type=submit]"),
        () => Supabase.modifier("rh_entreprise", "id=eq.true", valeurs),
        "Informations de l'entreprise enregistrées.");
      entreprise(zone);
    });
    UI.vider(zone,
      onglets("entreprise"),
      h("p", { class: "doux petit" }, "Ces informations s'impriment en tête des bulletins de paie. Laissez vide ce que vous ne voulez pas imprimer."),
      form,
      e.modifie_le ? h("p", { class: "doux tres-petit" }, "Dernière modification le " + UI.dateHeure(e.modifie_le) + ".") : null);
  }

  /* ---------- Les autres réglages, là où ils vivent ---------- */

  function autres(zone) {
    const lien = (href, icone, titre, texte) => h("a", { class: "element", href },
      UI.icone(icone), h("div", { class: "etire" }, h("div", { class: "gras" }, titre), h("div", { class: "petit doux" }, texte)),
      UI.icone("chevron", "ic-sm"));
    UI.vider(zone,
      onglets("autres"),
      h("div", { class: "liste" },
        lien("#/suivi/reglages", "suivi", "Suivi des commandes : délais et zones",
          "Au bout de combien d'heures une commande passe en alerte ; les zones reconnues dans les adresses."),
        lien("#/paie/baremes", "paie", "Paie : barèmes CNSS et impôt",
          "Saisis par l'administration, validés par le CEO avant de compter."),
        lien("#/profils", "profils", "Profils et responsables",
          "Les équipes, leur responsable et leurs membres."),
        lien("#/employes", "equipe", "Employés : rôles et droits",
          "Administration, décaissement, salaire : sur la fiche de chacun, validés par le CEO."),
        lien("#/compte", "mail", "Ma boîte mail",
          "Le mot de passe de votre adresse professionnelle, gardé chiffré.")));
  }

  return { titre: "Paramètres", afficher };
})();
