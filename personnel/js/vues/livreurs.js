/* =========================================================
   Livreurs — tous les livreurs, et la fiche de chacun.

   #/liste-livreurs         : la liste, avec ce que chacun a fait sur
                              la période (?p=30j, ou ?du=…&au=…) ;
   #/liste-livreurs/<id>    : sa fiche : ses chiffres, ses courses,
                              ses refus, l'historique de ses blocages.

   L'administration peut le BLOQUER : il ne reçoit plus aucune course,
   et ses courses pas encore parties retournent aux boutiques. C'est la
   base qui décide de tout (rh_livreurs, rh_livreur_fiche,
   rh_bloquer_livreur) : qui voit ce menu, qui voit les montants, qui
   bloque.
   ========================================================= */
const VueLivreurs = (() => {
  const { h } = UI;
  const ROUTE = "#/liste-livreurs";
  const ETATS = { nouvelle: ["À récupérer", "orange"], vue: ["À récupérer", "orange"], preparee: ["Colis prêt", "orange"],
    en_livraison: ["En route", "bleu"], remise: ["Livrée", "vert"], annulee: ["Annulée", ""] };
  const nombre = (n) => (n === null || n === undefined ? "—" : UI.entier(n));
  const tuile = (valeur, libelle) => h("div", { class: "tuile" }, h("b", {}, valeur), h("span", {}, libelle));
  const vehicule = (v) => (v === "tricycle" ? "Tricycle" : "Moto");
  /* « Codjo AHOUANSOU » → « CA » : un livreur n'a qu'un nom complet. */
  const initiales = (nom) => (nom || "").trim().split(/\s+/).slice(0, 2).map((m) => m.charAt(0)).join("").toUpperCase() || "?";

  /** Les étiquettes d'un livreur : à qui il est, et où il en est. */
  function etiquettes(l) {
    return [
      l.bloque ? UI.etiquette("Bloqué", "rouge") : null,
      !l.actif ? UI.etiquette("Compte désactivé", "") : null,
      l.actif && !l.valide ? UI.etiquette("Pas encore validé", "orange") : null,
      l.en_course ? UI.etiquette("En course", "bleu") : null,
    ];
  }
  const rattache = (l) => (l.boutique ? "Livreur de " + l.boutique : "Livreur BIZZOO");

  async function afficher(zone, morceaux, params) {
    const periode = VueStatistiques.periodeDe(params, "30j");
    if (morceaux[0]) return fiche(zone, morceaux[0], periode);
    return liste(zone, periode, params);
  }

  /* ---------- La liste ---------- */

  async function liste(zone, periode, params) {
    const d = await Supabase.rpc("rh_livreurs", { depuis: periode.depuis, jusqu: periode.jusqu });
    if (!zone.isConnected) return;
    const filtre = params.filtre || "tous";
    const FILTRES = [
      ["tous", "Tous", () => true],
      ["bizzoo", "BIZZOO", (l) => !l.boutique],
      ["boutiques", "Des boutiques", (l) => !!l.boutique],
      ["course", "En course", (l) => l.en_course],
      ["bloques", "Bloqués", (l) => l.bloque],
    ];
    const garder = (FILTRES.find((f) => f[0] === filtre) || FILTRES[0])[2];
    const tous = d.livreurs;
    const champ = h("input", { type: "search", placeholder: "Rechercher un nom, un numéro, une boutique", value: params.q || "" });
    const corps = h("div", {});
    const dessiner = () => {
      const q = champ.value.trim().toLowerCase();
      const visibles = tous.filter(garder).filter((l) => !q ||
        [l.nom, l.tel, l.boutique || "BIZZOO"].join(" ").toLowerCase().includes(q));
      UI.vider(corps, visibles.length ? h("div", { class: "liste" }, visibles.map((l) =>
        h("a", { class: "element", href: ROUTE + "/" + l.id + periode.suffixe },
          h("div", { class: "avatar" }, initiales(l.nom)),
          h("div", { class: "etire" },
            h("div", { class: "ligne" }, h("span", { class: "gras etire coupe" }, l.nom), etiquettes(l)),
            h("div", { class: "petit doux coupe" }, [rattache(l), vehicule(l.vehicule), l.tel].filter(Boolean).join(" · ")),
            h("div", { class: "petit coupe" }, [
              nombre(l.courses) + " course(s)", nombre(l.livrees) + " livrée(s)",
              l.refus ? nombre(l.refus) + " refus" : null,
              d.droits.argent ? UI.fcfa(l.gains) + " gagnés" : null,
            ].filter(Boolean).join(" · "))),
          UI.icone("chevron", "ic-sm"))))
        : UI.vide(tous.length ? "Aucun livreur ici." : "Aucun livreur enregistré."));
    };
    champ.addEventListener("input", dessiner);
    const somme = (cle) => tous.reduce((s, l) => s + Number(l[cle] || 0), 0);
    UI.vider(zone,
      UI.barrePeriode(periode, ROUTE, filtre !== "tous" ? "&filtre=" + filtre : ""),
      h("div", { class: "tuiles compactes" },
        tuile(nombre(tous.length), "livreurs enregistrés"),
        tuile(nombre(tous.filter((l) => l.actif && l.valide && !l.bloque).length), "prêts à recevoir des courses"),
        tuile(nombre(tous.filter((l) => l.en_course).length), "en course maintenant"),
        tuile(nombre(tous.filter((l) => l.bloque).length), "bloqués"),
        tuile(nombre(somme("courses")), "courses sur la période"),
        tuile(nombre(somme("livrees")), "livrées sur la période"),
        d.droits.argent ? tuile(UI.fcfa(somme("gains")), "gains des livreurs") : null),
      h("div", { class: "filtres" }, FILTRES.map(([v, l]) =>
        h("button", { class: v === filtre ? "actif" : "", onclick: () => {
          location.hash = ROUTE + periode.suffixe + (v !== "tous" ? "&filtre=" + v : "");
        } }, l))),
      h("label", { class: "champ" }, champ),
      corps);
    dessiner();
  }

  /* ---------- La fiche d'un livreur ---------- */

  async function fiche(zone, id, periode) {
    const d = await Supabase.rpc("rh_livreur_fiche", { livreur: id, depuis: periode.depuis, jusqu: periode.jusqu });
    if (!zone.isConnected) return;
    const l = d.livreur, c = d.chiffres;
    App.titre(l.nom);
    const recharger = () => fiche(zone, id, periode);

    const actions = [];
    if (App.ouvert("livreurs")) {
      actions.push(h("a", { class: "btn btn-second btn-petit", href: "#/livreurs/" + l.id }, UI.icone("carte", "ic-sm"), "Voir sa position"));
    }
    if (d.droits.bloquer && !l.bloque) {
      actions.push(h("button", { class: "btn btn-danger btn-petit", onclick: async (ev) => {
        const bouton = ev.currentTarget;
        const v = await UI.formulaire({
          titre: "Bloquer " + l.nom, valider: "Bloquer", danger: true,
          texte: "Il ne recevra plus aucune course : aucune demande ne lui sera proposée, et aucune boutique ne pourra lui en confier. " +
            "Ses courses pas encore parties retournent aux boutiques ; celles déjà en route, il les termine. Vous pourrez le débloquer.",
          champs: [{ nom: "motif", libelle: "Pourquoi ? (gardé dans l'historique)", type: "textarea", requis: true }],
          verifier: (x) => (x.motif.length < 3 ? "Dites pourquoi vous le bloquez." : null),
        });
        if (!v) return;
        const r = await UI.agir(bouton, () => Supabase.rpc("rh_bloquer_livreur", { livreur: l.id, bloquer: true, motif: v.motif }));
        UI.succes(l.nom + " est bloqué." + (r && r.liberees ? " " + r.liberees + " course(s) retournée(s) aux boutiques." : ""));
        recharger();
      } }, UI.icone("alerte", "ic-sm"), "Bloquer"));
    }
    if (d.droits.bloquer && l.bloque) {
      actions.push(h("button", { class: "btn btn-vert btn-petit", onclick: async (ev) => {
        const bouton = ev.currentTarget;
        const v = await UI.formulaire({
          titre: "Débloquer " + l.nom, valider: "Débloquer",
          texte: "Il recevra de nouveau les courses de BIZZOO et de sa boutique.",
          champs: [{ nom: "motif", libelle: "Commentaire (facultatif)", type: "textarea" }],
        });
        if (!v) return;
        await UI.agir(bouton, () => Supabase.rpc("rh_bloquer_livreur", { livreur: l.id, bloquer: false, motif: v.motif }),
          l.nom + " est débloqué.");
        recharger();
      } }, UI.icone("check", "ic-sm"), "Débloquer"));
    }

    const dernierBlocage = d.blocages.find((b) => b.bloque);
    const identite = h("div", { class: "carte" },
      h("div", { class: "ligne" },
        h("div", { class: "avatar" }, initiales(l.nom)),
        h("div", { class: "etire" },
          h("div", { class: "ligne" }, h("span", { class: "gras etire" }, l.nom), etiquettes(l)),
          h("div", { class: "petit doux" }, [rattache(l), vehicule(l.vehicule), l.tel ? "+229 " + l.tel : null].filter(Boolean).join(" · ")),
          h("div", { class: "petit doux" }, "Compte créé le " + UI.date(l.cree_le) +
            (l.position ? " · dernière position " + UI.quand(l.position.le) + (l.position.adresse ? " (" + l.position.adresse + ")" : "") : "")))),
      l.bloque && dernierBlocage ? h("p", { class: "petit avertissement" },
        "Bloqué le " + UI.dateHeure(dernierBlocage.le) + " par " + dernierBlocage.par + " : « " + dernierBlocage.motif + " ». Il ne reçoit plus de course.") : null,
      actions.length ? h("div", { class: "actions" }, actions) : null);

    const tuiles = h("div", { class: "tuiles compactes" },
      tuile(nombre(c.courses), "courses"),
      tuile(nombre(c.livrees), "livrées"),
      tuile(nombre(c.en_cours), "en cours"),
      tuile(nombre(c.annulees), "annulées"),
      tuile(nombre(c.confirmees), "réception confirmée par le client"),
      tuile(nombre(c.refus), "refusées par lui"),
      tuile(c.delai_prise_minutes === null ? "—" : nombre(c.delai_prise_minutes) + " min", "pour accepter, en moyenne"),
      tuile(c.delai_livraison_heures === null ? "—" : String(c.delai_livraison_heures).replace(".", ",") + " h", "du paiement à la réception"),
      tuile(nombre(c.contestes), "encaissements contestés"),
      d.droits.argent ? tuile(UI.fcfa(c.gains), "gagnés") : null,
      d.droits.argent ? tuile(UI.fcfa(c.encaisse), "encaissés à la livraison") : null);

    const courses = d.courses.length ? h("div", { class: "carte defile" },
      h("h3", { style: { marginBottom: "8px" } }, "Ses courses" + (d.courses.length >= 50 ? " (les 50 dernières)" : "")),
      h("table", { class: "tableau" },
        h("thead", {}, h("tr", {}, h("th", {}, "Commande"), h("th", {}, "Payée le"), h("th", {}, "Boutique(s)"), h("th", {}, "Étape"),
          h("th", {}, "Acceptée"), h("th", {}, "Reçue par le client"), d.droits.argent ? h("th", { class: "nombre" }, "Gain") : null)),
        h("tbody", {}, d.courses.map((k) => h("tr", {},
          h("td", { class: "gras" }, k.numero || k.commande),
          h("td", {}, UI.dateHeure(k.paye_le)),
          h("td", {}, k.boutiques || "—"),
          h("td", {}, UI.etiquette(...(ETATS[k.etat] || [k.etat, ""]))),
          h("td", {}, k.recu_le ? UI.dateHeure(k.recu_le) : "—"),
          h("td", {}, k.confirme_le ? UI.dateHeure(k.confirme_le) : "—"),
          d.droits.argent ? h("td", { class: "nombre" }, k.gain === null ? "—" : UI.entier(k.gain)) : null)))))
      : UI.vide("Aucune course sur cette période.");

    const refus = d.refus.length ? h("div", { class: "carte" },
      h("h3", { style: { marginBottom: "8px" } }, "Courses refusées"),
      h("div", { class: "liste" }, d.refus.map((r) => h("div", { class: "element" },
        h("div", { class: "etire" },
          h("div", { class: "gras" }, (r.numero || "Commande") + (r.boutique ? " · " + r.boutique : "")),
          h("div", { class: "petit doux" }, UI.dateHeure(r.le) + (r.motif ? " · « " + r.motif + " »" : " · sans motif"))))))) : null;

    const blocages = d.blocages.length ? h("div", { class: "carte" },
      h("h3", { style: { marginBottom: "8px" } }, "Historique des blocages"),
      h("div", { class: "liste" }, d.blocages.map((b) => h("div", { class: "element" },
        b.bloque ? UI.etiquette("Bloqué", "rouge") : UI.etiquette("Débloqué", "vert"),
        h("div", { class: "etire" },
          h("div", { class: "petit" }, UI.dateHeure(b.le) + " · par " + b.par),
          b.motif ? h("div", { class: "petit doux" }, "« " + b.motif + " »") : null))))) : null;

    UI.vider(zone,
      h("div", { class: "actions" }, h("a", { class: "btn btn-second btn-petit", href: ROUTE + periode.suffixe }, "← Tous les livreurs")),
      identite,
      UI.barrePeriode(periode, ROUTE + "/" + l.id),
      h("p", { class: "doux petit" }, "Du " + UI.dateLongue(d.periode.depuis) + " au " + UI.dateLongue(d.periode.jusqu) +
        (d.droits.argent ? "" : " · sans les montants, réservés à l'administration")),
      tuiles, courses, refus, blocages);
  }

  return { titre: "Livreurs", afficher };
})();
