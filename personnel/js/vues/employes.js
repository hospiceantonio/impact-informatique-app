/* =========================================================
   Employés — le registre du personnel (administration).

   L'administration crée la fiche ; elle reste « en attente »
   jusqu'à ce que le CEO la valide. Ensuite seulement, on crée
   l'accès à l'application, avec l'adresse professionnelle.
   Les droits (administration, décaissement) et le salaire d'un
   employé en poste ne changent que par le CEO : la base refuse
   le reste, l'écran ne fait que ne pas le proposer.
   ========================================================= */
const VueEmployes = (() => {
  const { h } = UI;

  const ETATS = {
    en_attente: ["À valider", "orange"],
    actif: ["En poste", "vert"],
    refuse: ["Refusé", "rouge"],
    sorti: ["Sorti", ""],
    bloque: ["Bloqué", "rouge"],
    supprime: ["Archivé", ""],
  };
  const ACTIONS_JOURNAL = { bloque: "Bloqué", debloque: "Débloqué", supprime: "Supprimé (fiche archivée)", efface: "Effacé" };
  const MODES = { especes: "Espèces", virement: "Virement bancaire", mobile_money: "Mobile Money", cheque: "Chèque" };
  const NIVEAUX = ["Sans diplôme", "CEP", "BEPC", "CAP", "BAC", "BTS / DUT (Bac+2)", "Licence (Bac+3)", "Master (Bac+5)", "Doctorat"];
  const DOMAINE = "@bizzoomarket.com";
  const etiquette = (s) => UI.etiquette(...(ETATS[s] || [s, ""]));

  let profils = [];

  async function afficher(zone, morceaux, params) {
    UI.vider(zone, UI.chargement());
    /* Ouvert à un profil par le menu Paramètres : l’annuaire, en lecture. */
    if (!App.estAdmin()) return annuaire(zone);
    profils = await Supabase.lire("rh_profils?select=id,nom,responsable_id&order=nom");
    if (morceaux[0] === "nouveau") return formulaire(zone);
    if (morceaux[0]) return fiche(zone, morceaux[0]);
    return liste(zone, params.filtre || "actif", params.q || "");
  }

  /** L’annuaire : qui est qui, comment le joindre. Aucun salaire, aucune
      donnée personnelle : rh_annuaire() ne les donne pas. */
  async function annuaire(zone) {
    const employes = await Supabase.rpc("rh_annuaire");
    if (!zone.isConnected) return;
    const champ = h("input", { type: "search", placeholder: "Rechercher un nom, un poste, un profil" });
    const corps = h("div", {});
    const dessiner = () => {
      const q = champ.value.trim().toLowerCase();
      const visibles = employes.filter((e) => !q ||
        [e.nom, e.prenoms, e.poste, e.matricule, e.profil].join(" ").toLowerCase().includes(q));
      UI.vider(corps, visibles.length ? h("div", { class: "liste" }, visibles.map((e) =>
        h("div", { class: "element" },
          h("div", { class: "avatar" }, UI.initiales(e.nom, e.prenoms)),
          h("div", { class: "etire" },
            h("div", { class: "ligne" }, h("span", { class: "gras etire coupe" }, UI.nomComplet(e)),
              e.ceo ? UI.etiquette("CEO", "bleu") : e.administration ? UI.etiquette("Administration", "bleu") : null,
              e.responsable ? UI.etiquette("Responsable", "vert") : null),
            h("div", { class: "petit doux coupe" }, [e.matricule, e.poste, e.profil].filter(Boolean).join(" · ")),
            h("div", { class: "petit coupe" }, [e.email_pro, e.telephone].filter(Boolean).join(" · ") || "—")))))
        : UI.vide("Aucun employé ici."));
    };
    champ.addEventListener("input", dessiner);
    UI.vider(zone,
      h("div", { class: "titre-section" }, h("h2", {}, "Annuaire (" + employes.length + ")")),
      h("p", { class: "doux petit" }, "Les employés en poste, en lecture seule."),
      h("label", { class: "champ" }, champ), corps);
    dessiner();
  }

  const nomProfil = (id) => (profils.find((p) => p.id === id) || {}).nom || "—";

  async function liste(zone, filtre, recherche) {
    let chemin = "rh_employes?select=id,matricule,nom,prenoms,poste,statut,etat,profil_id,administration,ceo,peut_decaisser,compte_id,date_embauche&order=nom,prenoms";
    /* « Tous » : sauf les fiches archivées, qui ont leur filtre. */
    chemin += filtre === "tous" ? "&etat=neq.supprime" : "&etat=eq." + filtre;
    const employes = await Supabase.lire(chemin);
    if (!zone.isConnected) return;
    const champ = h("input", { type: "search", placeholder: "Rechercher un nom, un poste, un matricule", value: recherche });
    const corps = h("div", {});
    const dessiner = () => {
      const q = champ.value.trim().toLowerCase();
      const visibles = employes.filter((e) => !q ||
        [e.nom, e.prenoms, e.poste, e.matricule, nomProfil(e.profil_id)].join(" ").toLowerCase().includes(q));
      UI.vider(corps, visibles.length ? h("div", { class: "liste" }, visibles.map((e) =>
        h("a", { class: "element", href: "#/employes/" + e.id },
          h("div", { class: "avatar" }, UI.initiales(e.nom, e.prenoms)),
          h("div", { class: "etire" },
            h("div", { class: "ligne" }, h("span", { class: "gras etire coupe" }, UI.nomComplet(e)),
              e.ceo ? UI.etiquette("CEO", "bleu") : e.administration ? UI.etiquette("Administration", "bleu") : null,
              filtre === "tous" ? etiquette(e.etat) : null),
            h("div", { class: "petit doux coupe" }, [e.matricule, e.poste, nomProfil(e.profil_id),
              e.statut === "stagiaire" ? "Stagiaire" : null].filter(Boolean).join(" · "))),
          UI.icone("chevron", "ic-sm"))))
        : UI.vide("Aucun employé ici."));
    };
    champ.addEventListener("input", dessiner);
    UI.vider(zone,
      h("div", { class: "titre-section" }, h("h2", {}, "Employés"),
        h("a", { class: "btn btn-petit", href: "#/employes/nouveau" }, UI.icone("plus", "ic-sm"), "Nouvel employé")),
      h("div", { class: "filtres" }, [["actif", "En poste"], ["en_attente", "À valider"], ["bloque", "Bloqués"], ["refuse", "Refusés"], ["sorti", "Sortis"], ["supprime", "Archivés"], ["tous", "Tous"]]
        .map(([v, l]) => h("button", { class: v === filtre ? "actif" : "", onclick: () => { location.hash = "#/employes?filtre=" + v; } }, l))),
      h("label", { class: "champ" }, champ),
      h("p", { class: "doux petit" }, employes.length + " employé(s)"),
      corps);
    dessiner();
  }

  /* ---------- Créer, modifier ---------- */

  async function formulaire(zone, e) {
    App.titre(e ? "Modifier " + UI.nomComplet(e) : "Nouvel employé");
    /* Le superadministrateur modifie une fiche comme le CEO (droits, salaire). */
    const ceo = App.estCeo() || App.estSuper();
    const salaireFige = e && e.etat === "actif" && !ceo;
    const champs = {};
    const champ = (nom, libelle, entree, aide, large) => {
      champs[nom] = entree;
      return h("label", { class: "champ" + (large ? " large" : "") }, h("span", {}, libelle), entree, aide ? h("small", {}, aide) : null);
    };
    const val = (n, defaut) => (e && e[n] !== null && e[n] !== undefined ? e[n] : (defaut ?? ""));
    const choix = (nom, options, valeur) => h("select", { name: nom }, options.map(([v, l]) =>
      h("option", { value: v, selected: String(v) === String(valeur) }, l)));

    const niveaux = h("datalist", { id: "niveaux-etude" }, NIVEAUX.map((n) => h("option", { value: n })));
    const form = h("form", { class: "carte pile" },
      niveaux,
      h("h2", {}, "Identité"),
      h("div", { class: "formulaire" },
        champ("nom", "Nom *", h("input", { required: true, value: val("nom") })),
        champ("prenoms", "Prénoms", h("input", { value: val("prenoms") })),
        champ("sexe", "Sexe", choix("sexe", [["", "À préciser"], ["M", "Homme"], ["F", "Femme"]], val("sexe", ""))),
        champ("date_naissance", "Date de naissance", h("input", { type: "date", value: val("date_naissance") }), "L'âge se calcule tout seul."),
        champ("niveau_etude", "Niveau d'étude", h("input", { list: "niveaux-etude", value: val("niveau_etude") }))),
      h("h2", {}, "Contact"),
      h("div", { class: "formulaire" },
        champ("telephone", "Téléphone (sert à se connecter)", h("input", { type: "tel", value: val("telephone"), placeholder: "01 + 8 chiffres" }),
          "Il se connecte avec ce numéro et un code reçu par SMS."),
        champ("telephone_pro", "Téléphone pro", h("input", { type: "tel", value: val("telephone_pro") })),
        champ("email_pro", "E-mail professionnel", h("input", { type: "email", value: val("email_pro"), placeholder: "prenom.nom" + DOMAINE }),
          "Son adresse " + DOMAINE + " : elle sert de connexion et de boîte mail."),
        champ("email_perso", "E-mail personnel", h("input", { type: "email", value: val("email_perso") })),
        champ("adresse", "Lieu de résidence", h("input", { value: val("adresse") }))),
      h("h2", {}, "Poste"),
      h("div", { class: "formulaire" },
        champ("date_embauche", "Date d'embauche *", h("input", { type: "date", required: true, value: val("date_embauche", UI.aujourdhui()) })),
        champ("statut", "Statut *", choix("statut", [["employe", "Employé"], ["stagiaire", "Stagiaire"]], val("statut", "employe"))),
        champ("poste", "Poste", h("input", { value: val("poste"), placeholder: "Ex. : Chargé de communication" })),
        champ("profil_id", "Profil", choix("profil_id", [["", "— Aucun —"], ...profils.map((p) => [p.id, p.nom])], val("profil_id")))),
      h("h2", {}, "Rémunération"),
      h("div", { class: "formulaire" },
        champ("salaire_base", "Salaire de base mensuel (FCFA) *", h("input", { type: "number", min: 0, step: 1, required: true,
          value: val("salaire_base", 0), disabled: salaireFige }), salaireFige ? "Le salaire d'un employé en poste ne change que par le CEO." : null),
        champ("mode_paiement", "Mode de paiement", choix("mode_paiement", Object.entries(MODES), val("mode_paiement", "especes"))),
        champ("compte_paiement", "N° de compte ou de Mobile Money", h("input", { value: val("compte_paiement") })),
        champ("numero_cnss", "N° CNSS", h("input", { value: val("numero_cnss") }))),
      h("h2", {}, "Autres informations"),
      h("div", { class: "formulaire" },
        champ("equipement", "Équipement confié", h("input", { value: val("equipement"), placeholder: "Téléphone, ordinateur, tablette…" })),
        champ("langue", "Langue", h("input", { value: val("langue") })),
        champ("marie", "Marié(e)", h("input", { value: val("marie"), placeholder: "Oui / Non" })),
        champ("moto", "Moto", choix("moto", [["", "À préciser"], ["true", "Oui"], ["false", "Non"]], val("moto", "")))),
      champ("infos", "Informations complémentaires", h("textarea", {}), null, true),
      ceo ? h("div", { class: "pile" },
        h("h2", {}, "Droits (CEO)"),
        h("label", { class: "case" }, champs.administration = h("input", { type: "checkbox", checked: !!val("administration", false) }),
          "Membre de l'administration (droits sur tous les profils)"),
        /* Décaisser, c'est tenir la caisse : le gestionnaire se désigne dans Caisse. */
        h("p", { class: "doux petit" }, "Le gestionnaire de la caisse, seul à décaisser les dépenses et à payer les salaires, se désigne dans le menu Caisse.")) : null,
      !e && !ceo ? h("div", { class: "info" }, "Cette fiche partira chez le CEO pour validation.") : null,
      h("div", { class: "actions" },
        h("button", { class: "btn", type: "submit" }, e ? "Enregistrer" : "Créer la fiche"),
        h("a", { class: "btn btn-second", href: e ? "#/employes/" + e.id : "#/employes" }, "Annuler")));
    champs.infos.value = val("infos");

    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const v = {};
      for (const [nom, entree] of Object.entries(champs)) {
        if (entree.disabled) continue;
        v[nom] = entree.type === "checkbox" ? entree.checked : entree.value.trim();
      }
      if ("salaire_base" in v) {
        v.salaire_base = Math.round(Number(v.salaire_base || 0));
        if (!(v.salaire_base >= 0)) return UI.echec("Le salaire doit être un nombre de francs.");
      }
      for (const n of ["date_naissance", "profil_id", "email_pro", "sexe"]) if (v[n] === "") v[n] = null;
      if ("moto" in v) v.moto = v.moto === "" ? null : v.moto === "true";
      if (v.telephone) {
        const t = v.telephone.replace(/[^0-9]/g, "").replace(/^229(?=01)/, "");
        v.telephone = t.length === 8 ? "01" + t : t;
        if (!/^01[0-9]{8}$/.test(v.telephone)) return UI.echec("Téléphone : 01 suivi de 8 chiffres.");
      }
      if (v.email_pro) {
        v.email_pro = v.email_pro.toLowerCase();
        if (!v.email_pro.endsWith(DOMAINE) &&
            !await UI.confirmer("L'adresse « " + v.email_pro + " » n'est pas une adresse " + DOMAINE +
              ". La messagerie de l'application ne marchera pas avec elle. Continuer quand même ?")) return;
      }
      const bouton = ev.submitter;
      const ligne = await UI.agir(bouton, () => e
        ? Supabase.modifier("rh_employes", "id=eq." + e.id, v)
        : Supabase.ajouter("rh_employes", v),
        e ? "Fiche enregistrée." : (ceo ? "Employé créé." : "Fiche créée : elle attend la validation du CEO."));
      App.rafraichir();
      VueDiscussions.oublier();
      location.hash = "#/employes/" + (ligne ? ligne.id : e.id);
    });
    UI.vider(zone, form);
  }

  /* ---------- La fiche ---------- */

  async function fiche(zone, id) {
    const [[e], journal] = await Promise.all([
      Supabase.lire("rh_employes?select=*&id=eq." + encodeURIComponent(id)),
      Supabase.lire("rh_journal_employes?select=*&employe_id=eq." + encodeURIComponent(id) + "&order=id.desc").catch(() => []),
    ]);
    if (!zone.isConnected) return;
    if (!e) return UI.vider(zone, UI.vide("Employé introuvable."));
    App.titre(UI.nomComplet(e));
    const ceo = App.estCeo();
    /* Modifier une fiche : aussi le superadministrateur, comme le CEO. */
    const modifieur = ceo || App.estSuper();
    const recharger = () => App.rafraichir().then(() => fiche(zone, id));
    /* Ethnie et religion : à part, pour le CEO et le superadministrateur. */
    const sensibles = modifieur
      ? (await Supabase.lire("rh_employes_sensibles?select=*&employe_id=eq." + encodeURIComponent(id)).catch(() => []))[0] || null
      : null;
    /* Son solde et sa prochaine paie : le CEO y accorde primes et retenues. */
    const compte = modifieur && ["actif", "bloque"].includes(e.etat)
      ? await Supabase.rpc("rh_compte_employe", { qui: e.id }).catch(() => null)
      : null;
    if (!zone.isConnected) return;
    const age = UI.age(e.date_naissance);
    const octroyer = (nature) => async (ev) => {
      const bouton = ev.currentTarget;
      const v = await UI.formulaire({
        titre: (nature === "prime" ? "Accorder une prime à " : "Retenue sur le salaire de ") + UI.nomComplet(e),
        valider: nature === "prime" ? "Accorder" : "Retenir", danger: nature === "retenue",
        texte: "Elle s'inscrit sur sa prochaine paie (" + UI.mois(compte.prochain_mois) + ", versée le " + UI.date(compte.prochain_versement) + ").",
        champs: [
          { nom: "montant", libelle: "Montant (FCFA)", type: "number", min: 1, pas: 1, requis: true },
          { nom: "libelle", libelle: "Libellé (il figure sur la fiche de paie)", requis: true,
            indice: nature === "prime" ? "Prime de rendement" : "Casse de matériel" },
        ],
        verifier: (x) => (!(Number.isInteger(Number(x.montant)) && Number(x.montant) > 0) ? "Un montant en francs entiers, positif."
          : x.libelle.length < 3 ? "Un libellé de trois lettres au moins." : null),
      });
      if (!v) return;
      await UI.agir(bouton, () => Supabase.rpc("rh_octroyer", { qui: e.id, nature, montant: Number(v.montant), libelle: v.libelle }),
        nature === "prime" ? "Prime accordée." : "Retenue enregistrée.");
      recharger();
    };
    const ligne = (libelle, valeur) => h("div", {}, h("div", { class: "doux tres-petit" }, libelle), h("div", { class: "gras" }, valeur || "—"));
    const responsableDe = profils.filter((p) => p.responsable_id === e.id).map((p) => p.nom);

    const actions = [];
    if (ceo && e.etat === "en_attente") {
      actions.push(h("button", { class: "btn btn-vert", onclick: async (ev) => {
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_decider_employe", { employe: e.id, accepter: true, motif: "" }), "Employé validé.");
        recharger();
      } }, UI.icone("check", "ic-sm"), "Valider l'embauche"));
      actions.push(h("button", { class: "btn btn-danger", onclick: async (ev) => {
        const motif = await UI.motif("Refuser cette fiche", "Pourquoi ?");
        if (motif === null) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_decider_employe", { employe: e.id, accepter: false, motif }), "Fiche refusée.");
        recharger();
      } }, "Refuser"));
    }
    if (!e.ceo || modifieur) {
      if (!["sorti", "supprime"].includes(e.etat)) actions.push(h("button", { class: "btn btn-second", onclick: () => formulaire(zone, e) }, UI.icone("crayon", "ic-sm"), "Modifier"));
    }
    if (e.etat === "actif" && !e.compte_id && (!e.ceo || ceo)) {
      actions.push(h("button", { class: "btn btn-orange", onclick: (ev) => creerAcces(ev.currentTarget, e, recharger) }, UI.icone("cle", "ic-sm"), "Créer l'accès"));
    }
    if (ceo && ["actif", "bloque"].includes(e.etat) && !e.ceo) {
      actions.push(h("button", { class: "btn btn-danger", onclick: async (ev) => {
        const v = await UI.formulaire({ titre: "Sortie de " + UI.nomComplet(e), danger: true, valider: "Enregistrer la sortie",
          texte: "L'employé perd l'accès à l'application. Sa dernière paie est calculée jusqu'à la date de sortie.",
          champs: [{ nom: "le", libelle: "Date de sortie", type: "date", valeur: UI.aujourdhui(), requis: true },
                   { nom: "motif", libelle: "Motif (démission, fin de contrat…)", type: "textarea" }] });
        if (!v) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_sortie_employe", { employe: e.id, le: v.le, motif: v.motif }), "Sortie enregistrée.");
        recharger();
      } }, UI.icone("sortie", "ic-sm"), "Sortie"));
    }
    /* Bloquer, débloquer, supprimer : le CEO et le superadministrateur. */
    const peutBloquer = (App.estCeo() || App.estSuper()) && !e.ceo && e.id !== (App.moi() || {}).id;
    if (peutBloquer && e.etat === "actif") {
      actions.push(h("button", { class: "btn btn-orange", onclick: async (ev) => {
        const motif = await UI.motif("Bloquer " + UI.nomComplet(e),
          "Pourquoi ? (Il ne pourra plus ouvrir l'application ; sa paie continue.)");
        if (motif === null) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_bloquer_employe", { qui: e.id, bloquer: true, motif }), "Accès bloqué.");
        recharger();
      } }, "Bloquer"));
    }
    if (peutBloquer && e.etat === "bloque") {
      actions.push(h("button", { class: "btn btn-vert", onclick: async (ev) => {
        if (!await UI.confirmer("Débloquer " + UI.nomComplet(e) + " ? Il retrouve l'accès à l'application.", { valider: "Débloquer" })) return;
        await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_bloquer_employe", { qui: e.id, bloquer: false, motif: "" }), "Accès débloqué.");
        recharger();
      } }, UI.icone("check", "ic-sm"), "Débloquer"));
    }
    if (peutBloquer && e.etat !== "supprime") {
      actions.push(h("button", { class: "btn btn-danger", onclick: async (ev) => {
        const v = await UI.formulaire({ titre: "Supprimer " + UI.nomComplet(e), danger: true, valider: "Supprimer",
          texte: "Sans paie validée ni avance, la fiche est effacée entièrement. Sinon, elle est archivée : " +
                 "nom, matricule, n° CNSS et paie restent pour la comptabilité ; accès, messages, boîte mail et coordonnées sont effacés. " +
                 "On ne revient pas en arrière.",
          champs: [{ nom: "motif", libelle: "Motif", type: "textarea", requis: true }],
          verifier: (x) => (x.motif.trim() ? null : "Le motif est obligatoire.") });
        if (!v) return;
        const r = await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_supprimer_employe", { qui: e.id, motif: v.motif }));
        UI.succes(r === "archive" ? "Employé supprimé : sa fiche est archivée avec sa paie." : "Employé supprimé.");
        App.rafraichir();
        location.hash = "#/employes";
      } }, UI.icone("poubelle", "ic-sm"), "Supprimer"));
    }

    UI.vider(zone,
      h("div", { class: "carte pile" },
        h("div", { class: "ligne" },
          h("div", { class: "avatar", style: { width: "54px", height: "54px", fontSize: "18px" } }, UI.initiales(e.nom, e.prenoms)),
          h("div", { class: "etire" },
            h("h2", { style: { marginBottom: 0 } }, UI.nomComplet(e)),
            h("div", { class: "doux petit" }, [e.matricule, e.poste, e.statut === "stagiaire" ? "Stagiaire" : "Employé"].filter(Boolean).join(" · "))),
          etiquette(e.etat)),
        h("div", { class: "actions" },
          e.ceo ? UI.etiquette("CEO", "bleu") : null,
          e.administration && !e.ceo ? UI.etiquette("Administration", "bleu") : null,
          responsableDe.length ? UI.etiquette("Responsable : " + responsableDe.join(", "), "vert") : null,
          e.compte_id ? UI.etiquette("Accès créé", "vert") : (e.etat === "actif" ? UI.etiquette("Pas encore d'accès", "orange") : null)),
        e.etat === "refuse" && e.motif_refus ? h("div", { class: "erreur" }, "Refusée par le CEO : " + e.motif_refus) : null,
        e.etat === "sorti" ? h("div", { class: "avertissement" }, "Sorti le " + UI.date(e.date_sortie) + (e.motif_refus ? " — " + e.motif_refus : "")) : null,
        e.etat === "bloque" ? h("div", { class: "erreur" }, "Accès bloqué" +
          (journal[0] && journal[0].action === "bloque" ? " le " + UI.dateHeure(journal[0].le) + (journal[0].motif ? " — " + journal[0].motif : "") : "") +
          ". Sa paie continue.") : null,
        e.etat === "supprime" ? h("div", { class: "avertissement" }, "Fiche archivée le " + UI.date(e.date_sortie) +
          (e.motif_refus ? " — " + e.motif_refus : "") + ". Seules l'identité et la paie sont gardées.") : null,
        actions.length ? h("div", { class: "actions" }, actions) : null),
      h("div", { class: "carte" }, h("h2", {}, "Informations"),
        h("div", { class: "formulaire" },
          ligne("Sexe", e.sexe === "F" ? "Femme" : e.sexe === "M" ? "Homme" : "À préciser"),
          ligne("Date de naissance", e.date_naissance ? UI.date(e.date_naissance) + (age !== null ? " (" + age + " ans)" : "") : null),
          ligne("Niveau d'étude", e.niveau_etude),
          ligne("Téléphone (connexion)", e.telephone),
          ligne("Téléphone pro", e.telephone_pro),
          ligne("E-mail professionnel", e.email_pro),
          ligne("E-mail personnel", e.email_perso),
          ligne("Lieu de résidence", e.adresse),
          ligne("Profil", nomProfil(e.profil_id)),
          ligne("Date d'embauche", UI.date(e.date_embauche)),
          ligne("Salaire de base", UI.fcfa(e.salaire_base)),
          ligne("Paiement", MODES[e.mode_paiement] + (e.compte_paiement ? " · " + e.compte_paiement : "")),
          ligne("N° CNSS", e.numero_cnss),
          ligne("Équipement", e.equipement),
          ligne("Langue", e.langue),
          ligne("Marié(e)", e.marie),
          ligne("Moto", e.moto === true ? "Oui" : e.moto === false ? "Non" : null)),
        e.infos ? h("div", { class: "pre", style: { marginTop: "12px" } }, e.infos) : null),
      compte ? h("div", { class: "carte pile" },
        h("h2", {}, "Solde et prochaine paie"),
        h("div", { class: "formulaire" },
          ligne("Solde", UI.fcfa(compte.solde)),
          ligne("Prochaine paie", UI.mois(compte.prochain_mois) + ", versée le " + UI.date(compte.prochain_versement))),
        (compte.elements || []).length ? h("div", { class: "liste" }, compte.elements.map((x) => h("div", { class: "element" },
          h("div", { class: "etire" }, h("div", { class: "gras" }, x.libelle), h("div", { class: "petit doux" }, (x.nature === "retenue" ? "Retenue" : x.nature === "prime" ? "Prime" : "Indemnité") + " · " + UI.mois(x.mois))),
          h("b", {}, (x.nature === "retenue" ? "− " : "+ ") + UI.fcfa(x.montant)),
          h("button", { class: "btn-ic", "aria-label": "Retirer", onclick: async (ev) => {
            if (!await UI.confirmer("Retirer « " + x.libelle + " » de sa prochaine paie ?", { danger: true, valider: "Retirer" })) return;
            await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_retirer_element", { element: x.id }), "Retiré.");
            recharger();
          } }, UI.icone("poubelle", "ic-sm"))))) : h("p", { class: "doux petit" }, "Aucune prime ni retenue sur sa prochaine paie."),
        (compte.prets || []).filter((p) => p.statut === "active").map((p) =>
          h("div", { class: "info petit" }, "Prêt de " + UI.fcfa(p.montant) + " : reste " + UI.fcfa(p.reste) + ", repris sur la paie (" + UI.mois(p.premier_mois) + ").")),
        h("div", { class: "actions" },
          h("button", { class: "btn btn-second", onclick: octroyer("prime") }, UI.icone("plus", "ic-sm"), "Accorder une prime"),
          h("button", { class: "btn btn-second", onclick: octroyer("retenue") }, "Retenue sur salaire"))) : null,
      modifieur ? h("div", { class: "carte pile" },
        h("h2", {}, "Données sensibles"),
        h("p", { class: "doux tres-petit" }, "Visibles du CEO et du superadministrateur seulement : jamais de l'administration, ni de l'annuaire."),
        h("div", { class: "formulaire" },
          ligne("Ethnie", sensibles && sensibles.ethnie), ligne("Religion", sensibles && sensibles.religion)),
        h("div", { class: "actions" }, h("button", { class: "btn btn-second", onclick: async (ev) => {
          const v = await UI.formulaire({ titre: "Données sensibles", valider: "Enregistrer", champs: [
            { nom: "ethnie", libelle: "Ethnie", valeur: sensibles ? sensibles.ethnie : "" },
            { nom: "religion", libelle: "Religion", valeur: sensibles ? sensibles.religion : "" }] });
          if (!v) return;
          await UI.agir(ev.currentTarget, () => sensibles
            ? Supabase.modifier("rh_employes_sensibles", "employe_id=eq." + e.id, v)
            : Supabase.ajouter("rh_employes_sensibles", { employe_id: e.id, ...v }), "Enregistré.");
          recharger();
        } }, UI.icone("crayon", "ic-sm"), "Modifier"))) : null,
      journal.length ? h("div", { class: "carte" }, h("h2", {}, "Historique de l'accès"),
        h("div", { class: "liste" }, journal.map((j) => h("div", { class: "element" },
          h("div", { class: "etire" },
            h("div", { class: "gras" }, (ACTIONS_JOURNAL[j.action] || j.action) + " par " + (j.par_nom || "—")),
            h("div", { class: "petit doux" }, UI.dateHeure(j.le) + (j.motif ? " — " + j.motif : ""))))))) : null,
      h("div", { class: "actions" },
        h("a", { class: "btn btn-second", href: "#/paie/employe/" + e.id }, UI.icone("paie", "ic-sm"), "Paie de cet employé")));
  }

  /**
   * L'accès : un compte de connexion à l'adresse professionnelle, puis
   * le rattachement à la fiche. L'administrateur choisit le premier mot
   * de passe et le transmet lui-même à l'employé, qui le change ensuite
   * dans « Mon compte ».
   */
  async function creerAcces(bouton, e, suite) {
    if (!e.email_pro) return UI.echec("Renseignez d'abord l'e-mail professionnel (Modifier).");
    const v = await UI.formulaire({
      titre: "Créer l'accès de " + UI.nomComplet(e),
      texte: "Identifiant : " + e.email_pro + ". Choisissez un premier mot de passe et donnez-le à l'employé de vive voix ; il le changera dans « Mon compte ». " +
             "Si cette adresse a déjà un compte BIZZOO, il est simplement rattaché et garde son mot de passe.",
      valider: "Créer l'accès",
      champs: [{ nom: "mdp", libelle: "Premier mot de passe (8 caractères au moins)", type: "password", requis: true, autocomplete: "new-password" },
               { nom: "mdp2", libelle: "Le même, encore une fois", type: "password", requis: true, autocomplete: "new-password" }],
      verifier: (x) => (x.mdp.length < 8 ? "8 caractères au moins." : x.mdp !== x.mdp2 ? "Les deux mots de passe diffèrent." : null),
    });
    if (!v) return;
    await UI.agir(bouton, async () => {
      try {
        await Supabase.rpc("rh_rattacher_compte", { employe: e.id });
        UI.succes("Le compte existant de " + e.email_pro + " est rattaché.");
        return;
      } catch (err) {
        if (err.code !== "AUCUN_COMPTE") throw err;
      }
      const compte = await Supabase.creerCompte(e.email_pro, v.mdp);
      await Supabase.rpc("rh_rattacher_compte", { employe: e.id });
      UI.succes(compte.confirmationRequise
        ? "Accès créé. L'employé doit d'abord cliquer le lien reçu dans sa boîte " + e.email_pro + "."
        : "Accès créé : l'employé peut se connecter.");
    });
    suite();
  }

  return { titre: "Employés", afficher };
})();
