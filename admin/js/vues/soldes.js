/* =========================================================
   Le solde de la boutique, et ses reversements (3.59.0)

   TOUT L'ARGENT ARRIVE CHEZ BIZZOO — l'acompte en ligne, le reste
   par MoMoPay. Chaque boutique a donc chez BIZZOO un SOLDE : ses
   ventes livrées, au prix BIZZOO (commission de BIZZOO déduite).

     #/solde         la boutique : son solde, d'où il vient, le
                     numéro qui recevra les fonds, « Demander un
                     reversement », et l'historique ;
     #/reversements  le superadministrateur : les demandes de toutes
                     les boutiques. Il envoie l'argent, puis touche
                     « Envoyé » avec la référence de la transaction —
                     ou refuse, avec un motif.

   La base calcule et décide (« solde_boutique », « demander_
   reversement », « decider_reversement ») ; l'écran ne fait que
   montrer.
   ========================================================= */
const VueSoldes = (() => {
  const e = Utils.echapper;
  const m = (n, devise) => Utils.fmtMontant(Number(n) || 0, devise || "FCFA");
  const ETATS = {
    en_attente: { mot: "En attente de BIZZOO", classe: "badge-commande" },
    valide: { mot: "Envoyé", classe: "badge-ok" },
    refuse: { mot: "Refusé", classe: "badge-rupture" },
  };
  const RESEAUX = [["MTN", "MTN"], ["MOOV", "Moov"], ["CELTIIS", "Celtiis"]];
  const gereLesFonds = () => Supabase.estSuper() ||
    (Supabase.role() === "administrateur" && !Supabase.estCompteEnseigne());

  function htmlDemande(r, avecBoutique) {
    const etat = ETATS[r.etat] || ETATS.en_attente;
    return '<div class="sd-ligne" data-reversement="' + e(String(r.id)) + '">' +
      '<div class="sd-ligne-haut">' +
        "<strong>" + e(m(r.montant, r.devise)) + "</strong>" +
        '<span class="badge ' + etat.classe + '">' + e(etat.mot) + "</span>" +
      "</div>" +
      (avecBoutique ? '<div class="sd-boutique">' + e(r.nomBoutique) + "</div>" : "") +
      '<div class="aide">Vers ' + e(r.reseau) + " " + e(r.tel) +
        (r.titulaire ? " (" + e(r.titulaire) + ")" : "") +
        " — demandé le " + e(Utils.fmtDateHeure(r.demandeLe)) +
        (r.demandePar ? " par " + e(r.demandePar) : "") + "</div>" +
      (r.etat === "valide"
        ? '<div class="aide">Envoyé le ' + e(Utils.fmtDateHeure(r.decideLe)) + " — référence " +
            "<strong>" + e(r.reference) + "</strong></div>"
        : r.etat === "refuse"
          ? '<div class="aide sd-refus">Refusé le ' + e(Utils.fmtDateHeure(r.decideLe)) +
              (r.motif ? " : « " + e(r.motif) + " »" : "") + "</div>"
          : "") +
    "</div>";
  }

  /* ---------- La boutique ---------- */
  async function afficher(vue) {
    UI.entete({ titre: "Solde de la boutique", sous: "Ce que BIZZOO vous doit", retour: true });
    const boutique = Store.boutiqueCourante();
    if (!Supabase.tientLaCaisse() || !boutique) {
      vue.innerHTML = UI.vide("promo", "Réservé à l'administrateur",
        "Le solde d'une boutique se consulte par son administrateur, et par BIZZOO.");
      return;
    }
    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>Lecture du solde…</div>';
    let solde, demandes;
    try {
      [solde, demandes] = await Promise.all([Store.soldeBoutique(boutique.id), Store.reversements(boutique.id)]);
    } catch (err) {
      vue.innerHTML = '<div class="carte"><div class="carte-titre">Solde indisponible</div>' +
        '<p class="aide" style="margin:0">' + e(err.message) +
        "<br>S'il vient d'être mis en place, exécutez le fichier supabase/soldes-boutiques.sql.</p></div>";
      return;
    }
    const d = solde.devise;
    const r = solde.reception;
    const peut = gereLesFonds();
    vue.innerHTML =
      '<div class="carte sd-solde" id="sd-solde">' +
        '<div class="sd-etiquette">Disponible</div>' +
        '<div class="sd-montant" id="sd-disponible">' + e(m(solde.disponible, d)) + "</div>" +
        '<div class="sd-details">' +
          "<div><span>Ventes livrées (prix BIZZOO)</span><strong>" + e(m(solde.gagne, d)) + "</strong></div>" +
          (solde.dejaEncaisse
            ? "<div><span>Déjà encaissé en espèces</span><strong>− " + e(m(solde.dejaEncaisse, d)) + "</strong></div>"
            : "") +
          "<div><span>Déjà reversé</span><strong>− " + e(m(solde.reverse, d)) + "</strong></div>" +
          (solde.enAttente
            ? "<div><span>Demande en attente</span><strong>− " + e(m(solde.enAttente, d)) + "</strong></div>"
            : "") +
          "<div class=\"sd-a-venir\"><span>À venir (payé, pas encore livré)</span><strong>" +
            e(m(solde.aVenir, d)) + "</strong></div>" +
        "</div>" +
        '<p class="aide" style="margin:10px 0 0">Une vente compte une fois <strong>remise au client</strong>, ' +
          "au prix BIZZOO de chaque article — la commission de BIZZOO déduite. Les frais de " +
          "livraison n'en font pas partie.</p>" +
        (peut
          ? '<button type="button" class="btn" id="sd-demander" style="margin-top:12px"' +
              (solde.disponible > 0 && r ? "" : " disabled") + ">" +
              "Demander un reversement</button>" +
            (!r ? '<p class="aide" style="margin:8px 0 0">Réglez d\'abord le numéro qui recevra les fonds.</p>' : "")
          : "") +
      "</div>" +

      '<div class="carte" id="sd-reception">' +
        '<div class="carte-titre">' + UI.icone("tel", "ic-sm") + " Numéro de réception des fonds</div>" +
        (r
          ? '<p style="margin:0 0 6px"><strong>' + e(r.reseau) + " " + e(r.tel) + "</strong>" +
              (r.titulaire ? " — " + e(r.titulaire) : "") + "</p>" +
            '<p class="aide" style="margin:0 0 10px">Réglé le ' + e(Utils.fmtDateHeure(r.majLe)) +
              (r.majPar ? " par " + e(r.majPar) : "") + ". BIZZOO est prévenu de chaque changement.</p>"
          : '<p class="aide" style="margin:0 0 10px">Aucun numéro : BIZZOO ne saurait pas où vous envoyer l\'argent.</p>') +
        (peut
          ? '<button type="button" class="btn btn-clair" id="sd-regler">' + UI.icone("crayon") +
              (r ? "Changer le numéro" : "Régler le numéro") + "</button>"
          : "") +
      "</div>" +

      '<div class="titre-section">Reversements</div>' +
      (demandes.length
        ? '<div class="carte">' + demandes.map((x) => htmlDemande(x, false)).join("") + "</div>"
        : '<div class="carte"><p class="aide" style="margin:0">Aucun reversement pour l\'instant.</p></div>');

    const regler = UI.$("#sd-regler", vue);
    if (regler) regler.onclick = () => feuilleReception(boutique.id, r, () => afficher(vue));
    const demander = UI.$("#sd-demander", vue);
    if (demander) demander.onclick = () => feuilleDemande(boutique.id, solde, () => afficher(vue));
  }

  function feuilleReception(boutiqueId, r, apres) {
    const corps = UI.ouvrirFeuille("Numéro de réception",
      '<p class="aide" style="margin:0 0 12px">Le numéro Mobile Money sur lequel BIZZOO enverra vos ' +
        "reversements. BIZZOO est prévenu de chaque changement.</p>" +
      '<div class="champ"><label>Réseau</label><div class="st-filtres" id="sd-reseaux">' +
        RESEAUX.map(([v, nom]) => '<button type="button" class="puce' + (r && r.reseau === v ? " active" : "") +
          '" data-reseau="' + v + '">' + nom + "</button>").join("") + "</div></div>" +
      UI.champTexte({ id: "sd-tel", label: "Numéro", type: "tel", valeur: r ? r.tel : "",
        placeholder: "01 97 00 00 00" }) +
      UI.champTexte({ id: "sd-titulaire", label: "Au nom de (facultatif)", valeur: r ? r.titulaire : "",
        placeholder: "Le nom du compte Mobile Money" }) +
      '<button type="button" class="btn" id="sd-enregistrer">' + UI.icone("check") + "Enregistrer</button>");
    let reseau = r ? r.reseau : "";
    for (const b of UI.$$("[data-reseau]", corps)) {
      b.onclick = () => {
        reseau = b.dataset.reseau;
        for (const x of UI.$$("[data-reseau]", corps)) x.classList.toggle("active", x === b);
      };
    }
    const bouton = UI.$("#sd-enregistrer", corps);
    bouton.onclick = async () => {
      bouton.disabled = true;
      try {
        await Store.reglerReception(boutiqueId, UI.$("#sd-tel", corps).value, reseau, UI.$("#sd-titulaire", corps).value);
        UI.fermerFeuille();
        UI.toast("Numéro de réception enregistré.", "ok");
        apres();
      } catch (err) {
        UI.toast(err.message, "err");
        bouton.disabled = false;
      }
    };
  }

  function feuilleDemande(boutiqueId, solde, apres) {
    const r = solde.reception;
    const corps = UI.ouvrirFeuille("Demander un reversement",
      '<p class="aide" style="margin:0 0 12px">Disponible : <strong>' + e(m(solde.disponible, solde.devise)) +
        "</strong>. BIZZOO l'enverra sur <strong>" + e(r.reseau) + " " + e(r.tel) + "</strong>" +
        (r.titulaire ? " (" + e(r.titulaire) + ")" : "") + ", puis le validera ici.</p>" +
      UI.champMontant({ id: "sd-montant", label: "Montant à reverser", valeur: solde.disponible }) +
      '<button type="button" class="btn" id="sd-envoyer">' + UI.icone("check") + "Envoyer la demande</button>");
    const bouton = UI.$("#sd-envoyer", corps);
    bouton.onclick = async () => {
      const montant = Math.round(Utils.lireNombre(UI.$("#sd-montant", corps).value) || 0);
      bouton.disabled = true;
      try {
        await Store.demanderReversement(boutiqueId, montant);
        UI.fermerFeuille();
        UI.toast("Demande envoyée : BIZZOO est prévenu.", "ok");
        apres();
      } catch (err) {
        UI.toast(err.message, "err");
        bouton.disabled = false;
      }
    };
  }

  /* ---------- Le superadministrateur ---------- */
  async function reversements(vue) {
    UI.entete({ titre: "Reversements", sous: "Les demandes des boutiques", retour: true });
    if (!Supabase.estSuper()) {
      vue.innerHTML = UI.vide("promo", "Réservé au superadministrateur",
        "Seul le superadministrateur envoie et valide les reversements.");
      return;
    }
    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>Lecture des demandes…</div>';
    let liste;
    try {
      liste = await Store.reversements(null);
    } catch (err) {
      vue.innerHTML = '<div class="carte"><p class="aide" style="margin:0">' + e(err.message) + "</p></div>";
      return;
    }
    const attente = liste.filter((r) => r.etat === "en_attente");
    const faits = liste.filter((r) => r.etat !== "en_attente");
    vue.innerHTML =
      '<div class="titre-section" id="rv-attente">' +
        (attente.length ? attente.length + " demande" + (attente.length > 1 ? "s" : "") + " à traiter" : "Aucune demande à traiter") +
      "</div>" +
      (attente.length
        ? attente.map((r) => '<div class="carte">' + htmlDemande(r, true) +
            '<p class="aide" style="margin:8px 0">Envoyez l\'argent sur ce numéro, puis notez la référence de la transaction.</p>' +
            '<div class="btn-rangee">' +
              '<button type="button" class="btn" data-valider="' + e(String(r.id)) + '">' + UI.icone("check") + "Envoyé</button>" +
              '<button type="button" class="btn btn-clair btn-danger-clair" data-refuser="' + e(String(r.id)) + '">' +
                UI.icone("fermer") + "Refuser</button>" +
            "</div></div>").join("")
        : "") +
      (faits.length
        ? '<details class="carte" id="rv-faits"><summary class="carte-titre">Déjà traités (' + faits.length + ")</summary>" +
            faits.map((r) => htmlDemande(r, true)).join("") + "</details>"
        : "");
    for (const b of UI.$$("[data-valider]", vue)) {
      b.onclick = async () => {
        const ref = await UI.demanderTexte({ titre: "Reversement envoyé",
          texte: "Notez la référence de la transaction Mobile Money envoyée.", libelle: "Référence", bouton: "Valider" });
        if (ref === null) return;
        b.disabled = true;
        try {
          await Store.deciderReversement(Number(b.dataset.valider), true, ref, "");
          UI.toast("Reversement validé : la boutique est prévenue.", "ok");
          reversements(vue);
        } catch (err) { UI.toast(err.message, "err"); b.disabled = false; }
      };
    }
    for (const b of UI.$$("[data-refuser]", vue)) {
      b.onclick = async () => {
        const motif = await UI.demanderTexte({ titre: "Refuser le reversement",
          texte: "Dites pourquoi : la boutique le verra. Le montant revient à son solde.",
          libelle: "Motif", bouton: "Refuser", danger: true });
        if (motif === null) return;
        b.disabled = true;
        try {
          await Store.deciderReversement(Number(b.dataset.refuser), false, "", motif);
          UI.toast("Demande refusée.", "ok");
          reversements(vue);
        } catch (err) { UI.toast(err.message, "err"); b.disabled = false; }
      };
    }
  }

  return { afficher, reversements };
})();
