/* =========================================================
   Comptes revendeurs — ce que des commerçants demandent à BIZZOO.

   Un revendeur validé achète au PRIX BIZZOO : celui que la
   boutique a annoncé à la création du produit. C'est une remise
   permanente, sur tout le catalogue et dans toutes les
   boutiques — d'où la décision, et d'où cet écran.

   Valider n'est donc pas une formalité. On montre ce qu'il faut
   pour trancher : qui demande, comment le joindre, et ce qu'il
   dit de son commerce. Sans cela, approuver reviendrait à signer
   une adresse e-mail.
   ========================================================= */
const VueRevendeurs = (() => {

  const ETATS = {
    en_attente: { mot: "En attente", icone: "horloge" },
    validee: { mot: "Validé", icone: "check" },
    refusee: { mot: "Refusé", icone: "fermer" },
  };

  /**
   * Où se trouve le commerce, tel que le demandeur l'a déclaré.
   *
   * C'est une DÉCLARATION, pas une preuve : personne n'a vérifié que le
   * point posé est bien une boutique. Elle sert à décider en sachant de
   * quoi l'on parle, pas à certifier quoi que ce soit.
   */
  function blocOu(r) {
    const situe = r.latitude !== null && r.longitude !== null;
    if (!r.adresse && !situe) {
      return '<div class="aide" style="margin:0 0 10px">' +
        "Aucune adresse ni position donnée.</div>";
    }
    const carte = situe
      ? "https://www.google.com/maps/search/?api=1&query=" + r.latitude + "," + r.longitude
      : "";
    return (
      '<div class="rv-ou">' +
        UI.icone("carte", "ic-sm") +
        "<div>" +
          (r.adresse ? Utils.echapper(r.adresse) : "Position relevée, sans adresse écrite") +
          (situe
            ? '<div><a href="' + Utils.echapper(carte) + '" target="_blank" ' +
                'rel="noopener">Ouvrir la carte</a></div>'
            : "") +
        "</div>" +
      "</div>"
    );
  }

  function htmlDemande(r) {
    const etat = ETATS[r.etat] || ETATS.en_attente;
    const tel = r.tel ? "+" + r.indicatif + " " + r.tel : "";
    return (
      '<div class="carte rv-carte" data-compte="' + Utils.echapper(r.id) + '">' +
        '<div class="dem-entete">' +
          '<span class="dem-boutique">' + UI.icone("personne", "ic-sm") +
            Utils.echapper(r.nom || "(sans nom)") + "</span>" +
          '<span class="dem-quand">' + Utils.echapper(Utils.fmtDateHeure(r.demandeLe)) + "</span>" +
        "</div>" +
        '<div class="rv-contact">' +
          (r.email ? '<a href="mailto:' + Utils.echapper(r.email) + '">' +
            UI.icone("lien", "ic-sm") + Utils.echapper(r.email) + "</a>" : "") +
          (tel ? '<a href="tel:+' + Utils.echapper(r.indicatif + r.tel) + '">' +
            UI.icone("tel", "ic-sm") + Utils.echapper(tel) + "</a>" : "") +
        "</div>" +
        (r.message
          ? '<div class="rv-message">' + Utils.echapper(r.message) + "</div>"
          : '<div class="aide" style="margin:0 0 10px">Aucune précision donnée ' +
            "sur le commerce.</div>") +
        /* OÙ C'EST. Valider, c'est accorder une remise permanente sur
           tout le catalogue : on ne signe pas cela sans savoir à qui on
           a affaire. L'adresse écrite se lit, les coordonnées s'ouvrent
           d'un geste — et si le demandeur n'a rien donné, on le dit
           plutôt que de laisser un blanc qu'on interprète mal. */
        blocOu(r) +
        (r.etat === "en_attente"
          ? '<div class="btn-rangee" style="margin-top:12px">' +
              '<button type="button" class="btn" data-valider="' + Utils.echapper(r.id) + '">' +
                UI.icone("check") + "Valider</button>" +
              '<button type="button" class="btn btn-danger-clair" data-refuser="' +
                Utils.echapper(r.id) + '">' + UI.icone("fermer") + "Refuser</button>" +
            "</div>"
          : '<div class="dem-verdict dem-verdict-' +
              (r.etat === "validee" ? "approuvee" : "refusee") + '">' +
              UI.icone(etat.icone, "ic-sm") + etat.mot +
              (r.decidePar ? " par " + Utils.echapper(r.decidePar) : "") +
              (r.motif ? " — " + Utils.echapper(r.motif) : "") +
            "</div>" +
            /* Retirer un statut accordé par erreur, ou revenir sur un
               refus : la décision d'hier n'enferme personne. */
            '<div class="btn-rangee" style="margin-top:10px">' +
              (r.etat === "validee"
                ? '<button type="button" class="btn btn-danger-clair" data-refuser="' +
                  Utils.echapper(r.id) + '">' + UI.icone("fermer") +
                  "Retirer le statut</button>"
                : '<button type="button" class="btn btn-clair" data-valider="' +
                  Utils.echapper(r.id) + '">' + UI.icone("check") +
                  "Valider finalement</button>") +
            "</div>") +
      "</div>"
    );
  }

  async function afficher(vue) {
    UI.entete({ titre: "Comptes revendeurs", sous: "Qui achète au prix BIZZOO", retour: true });
    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>' +
      "Lecture des demandes…</div>";

    let demandes;
    try {
      demandes = await Store.listerRevendeurs("");
    } catch (err) {
      vue.innerHTML =
        '<div class="carte"><div class="carte-titre">Comptes revendeurs indisponibles</div>' +
        '<p class="aide" style="margin:0">' + Utils.echapper(err.message) +
        "<br>Si les comptes revendeurs viennent d'être mis en place, exécutez le " +
        "fichier supabase/comptes-revendeurs.sql.</p></div>";
      return;
    }

    const attente = demandes.filter((d) => d.etat === "en_attente");
    const traitees = demandes.filter((d) => d.etat !== "en_attente").slice(0, 30);

    vue.innerHTML =
      '<div class="carte carte-publier">' +
        '<div class="carte-titre">' + UI.icone("alerte", "ic-sm") + " " +
          (attente.length
            ? attente.length + " demande" + (attente.length > 1 ? "s" : "") + " en attente"
            : "Aucune demande en attente") + "</div>" +
        '<p class="aide" style="margin:0">Un compte validé ici achète au prix BIZZOO ' +
          "— celui que la boutique annonce en créant le produit — sur tout le " +
          "catalogue et dans toutes les boutiques. Ce qu'il a déjà commandé ne " +
          "change pas, dans un sens comme dans l'autre.</p>" +
      "</div>" +
      (attente.length ? attente.map(htmlDemande).join("") : "") +
      (traitees.length
        ? '<div class="titre-section">Déjà tranchées</div>' + traitees.map(htmlDemande).join("")
        : "") +
      (!demandes.length
        ? UI.vide("personne", "Aucune demande",
            "Les commerçants qui demandent un compte revendeur s'afficheront ici.")
        : "");

    const recharger = () => afficher(vue);

    /* Le nom sert le message de confirmation : « Valider Awa ? » se lit,
       « Valider 3f2a-… ? » ne se lit pas. */
    const nomDe = (id) => {
      const r = demandes.find((d) => d.id === id);
      return (r && (r.nom || r.email)) || "ce compte";
    };
    const compteDe = (id) => demandes.find((d) => d.id === id) || { id };

    for (const bouton of UI.$$("[data-valider]", vue)) {
      bouton.onclick = async () => {
        const id = bouton.dataset.valider;
        const ok = await UI.confirmer({
          titre: "Valider " + nomDe(id) + " ?",
          texte: "Ce compte achètera au prix BIZZOO sur tout le catalogue, " +
            "dès sa prochaine commande.",
          bouton: "Valider",
        });
        if (!ok) return;
        bouton.disabled = true;
        try {
          await Store.deciderRevendeur(compteDe(id), true, "");
          UI.toast("Compte revendeur validé", "ok");
          recharger();
        } catch (err) {
          UI.toast(err.message, "err");
          bouton.disabled = false;
        }
      };
    }

    for (const bouton of UI.$$("[data-refuser]", vue)) {
      bouton.onclick = async () => {
        const id = bouton.dataset.refuser;
        /* Un refus sans motif laisse le commerçant deviner — et
           redemander à l'identique. On demande la raison, sans l'imposer. */
        const motif = await UI.demanderTexte({
          titre: "Refuser " + nomDe(id) + " ?",
          texte: "Dites-lui pourquoi : il verra votre réponse dans l'application.",
          libelle: "Motif (facultatif)",
          bouton: "Refuser", danger: true,
        });
        if (motif === null) return;
        bouton.disabled = true;
        try {
          await Store.deciderRevendeur(compteDe(id), false, motif);
          UI.toast("Demande refusée", "ok");
          recharger();
        } catch (err) {
          UI.toast(err.message, "err");
          bouton.disabled = false;
        }
      };
    }
  }

  return { afficher };
})();
