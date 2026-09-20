/* =========================================================
   Commandes — ce que les clients ont acheté et payé.

   Une commande peut concerner plusieurs boutiques ; chacune
   ne voit que SES lignes. Ce n'est pas cet écran qui le
   décide : la base ne renvoie rien d'autre.

   Rien de ce qui touche à l'argent ne se modifie ici. La
   boutique fait avancer ses lignes — vue, préparée, remise —
   et rappelle le client. Le reste est déjà joué.
   ========================================================= */
const VueCommandes = (() => {

  /** « il y a 5 min », « il y a 2 h », « hier », sinon la date. */
  function depuis(ms) {
    const minutes = Math.round((Date.now() - ms) / 60000);
    if (minutes < 1) return "à l'instant";
    if (minutes < 60) return "il y a " + minutes + " min";
    const heures = Math.floor(minutes / 60);
    if (heures < 24) return "il y a " + heures + " h";
    if (heures < 48) return "hier";
    return Utils.fmtDateHeure(new Date(ms).toISOString());
  }

  /** Le récapitulatif de SA part, prêt à partir sur le WhatsApp du client. */
  function messageClient(c) {
    const lignes = c.lignes.map((l) =>
      "  • " + l.nom + (l.code ? " (code " + l.code + ")" : "") +
      " × " + l.quantite + " — " +
      Utils.fmtMontant(l.prix * l.quantite, c.devise));
    return "Bonjour" + (c.client.nom ? " " + c.client.nom : "") + " 👋\n" +
      "Votre commande " + c.numero + " est bien arrivée chez nous :\n" +
      lignes.join("\n") +
      "\n\nMontant : " + Utils.fmtMontant(c.montant, c.devise) +
      "\n\nQuand souhaitez-vous la recevoir ?";
  }

  function htmlLigne(l, devise) {
    const etat = Store.ETATS_LIGNE[l.etat] || Store.ETATS_LIGNE.nouvelle;
    const suite = Store.SUITE_LIGNE[l.etat];
    return (
      '<div class="cmd-ligne">' +
        '<div class="cmd-ligne-corps">' +
          '<div class="cmd-ligne-nom">' + Utils.echapper(l.nom) +
            ' <span class="cmd-quantite">× ' + l.quantite + "</span></div>" +
          '<div class="cmd-ligne-sous">' +
            (l.code ? '<span class="code-produit">' + Utils.echapper(l.code) + "</span> · " : "") +
            (l.reference ? "Réf. " + Utils.echapper(l.reference) + " · " : "") +
            Utils.echapper(Utils.fmtMontant(l.prix * l.quantite, devise)) +
          "</div>" +
        "</div>" +
        '<div class="cmd-ligne-etat">' +
          '<span class="badge ' + etat.classe + '">' + Utils.echapper(etat.nom) + "</span>" +
          (suite
            ? '<button type="button" class="btn-mini" data-avancer="' + Utils.echapper(l.id) +
              '" data-etat="' + suite + '">' + Utils.echapper(etat.suivant) + "</button>"
            : "") +
          /* CE QUE LE CLIENT A DIT, quand il l'a dit. « Remise » est
             votre déclaration ; ceci est la sienne. Les deux ensemble
             closent la commande — et le jour d'un litige, c'est cette
             ligne-là qu'on regarde. La base vous interdit de la poser
             vous-même, et c'est ce qui lui donne sa valeur. */
          (l.confirmeLe
            ? '<span class="cmd-confirme">' + UI.icone("check", "ic-sm") +
              "Reçu confirmé " + Utils.echapper(Utils.fmtDateHeure(l.confirmeLe)) + "</span>"
            : l.etat === "remise"
              ? '<span class="cmd-attente-client">En attente de sa confirmation</span>'
              : "") +
        "</div>" +
      "</div>"
    );
  }

  function htmlCommande(c) {
    const payee = c.etat === "payee";
    const attendue = c.etat === "a_payer";
    /* Un numéro se lit, se dicte et se recopie : on l'espace comme on le
       dirait, plutôt que d'aligner onze chiffres d'affilée. */
    const tel = "+" + c.client.indicatif + " " +
      c.client.tel.replace(/(\d{2})(?=\d)/g, "$1 ").trim();
    /* Toutes les lignes de la boutique sont-elles derrière elle ? */
    const soldee = c.lignes.every((l) => l.etat === "remise" || l.etat === "annulee");

    return (
      '<div class="carte cmd-carte' + (soldee ? " cmd-soldee" : "") + '">' +
        '<div class="cmd-entete">' +
          "<div><div class=\"cmd-numero\">" + Utils.echapper(c.numero) +
            /* Une commande partie au prix revendeur le dit : c'est ce
               qui explique un montant plus bas que d'habitude pour la
               même marchandise. La boutique, elle, touche autant — c'est
               BIZZOO qui laisse sa marge. */
            (c.revendeur
              ? ' <span class="badge badge-revendeur">' + UI.icone("personne", "ic-sm") +
                "Revendeur</span>"
              : "") + "</div>" +
            '<div class="cmd-quand">' + Utils.echapper(depuis(c.creeLe)) + "</div></div>" +
          '<div style="text-align:right">' +
            '<div class="cmd-montant">' +
              Utils.echapper(Utils.fmtMontant(c.montant, c.devise)) + "</div>" +
            (c.montant !== c.total
              ? '<div class="cmd-part">sur ' +
                Utils.echapper(Utils.fmtMontant(c.total, c.devise)) + " au total</div>"
              : "") +
          "</div>" +
        "</div>" +

        (payee
          ? '<div class="cmd-etat cmd-etat-payee">' + UI.icone("check", "ic-sm") +
              "<span>Payée" + (c.payeLe ? " " + Utils.echapper(depuis(c.payeLe)) : "") +
              (c.confirmePar
                ? " — confirmée à la main par " + Utils.echapper(c.confirmePar)
                : " — confirmée par KkiaPay") + "</span></div>"
          : '<div class="cmd-etat cmd-etat-attente">' + UI.icone("horloge", "ic-sm") +
              "<span>" + (c.etat === "annulee" ? "Annulée"
                : c.etat === "echouee" ? "Paiement non abouti"
                : c.transactionAnnoncee
                  ? "Le client dit avoir payé — non confirmé par KkiaPay"
                  : "En attente de paiement") + "</span></div>") +

        (c.remarque
          ? '<div class="cmd-etat cmd-etat-alerte">' + UI.icone("alerte", "ic-sm") +
            "<span>" + Utils.echapper(c.remarque) + "</span></div>"
          : "") +

        '<div class="cmd-client">' +
          '<div class="cmd-client-nom">' + UI.icone("personne", "ic-sm") +
            Utils.echapper(c.client.nom || "Client") + "</div>" +
          '<a class="cmd-client-tel" href="' + Utils.echapper(Utils.lienTel(c.client.tel, c.client.indicatif)) + '">' +
            UI.icone("tel", "ic-sm") + Utils.echapper(tel) + "</a>" +
          (c.client.adresse
            ? '<div class="cmd-client-adresse">' + UI.icone("carte", "ic-sm") +
              Utils.echapper(c.client.adresse) + "</div>"
            : "") +
          (c.note
            ? '<div class="cmd-note">« ' + Utils.echapper(c.note) + " »</div>"
            : "") +
        "</div>" +

        '<div class="cmd-lignes">' + c.lignes.map((l) => htmlLigne(l, c.devise)).join("") + "</div>" +

        '<div class="btn-rangee" style="margin-top:12px">' +
          '<a class="btn btn-wa" target="_blank" rel="noopener" href="' +
            Utils.echapper(Utils.lienWhatsApp(c.client.tel, messageClient(c), c.client.indicatif)) +
            '">' + UI.icone("whatsapp") + "Écrire au client</a>" +
          (attendue && Supabase.estSuper() && c.transactionAnnoncee
            ? '<button type="button" class="btn btn-clair" data-confirmer="' +
                Utils.echapper(c.id) + '">' + UI.icone("check") +
                "Confirmer le paiement à la main</button>"
            : "") +
        "</div>" +
        (attendue && c.transactionAnnoncee
          ? '<p class="aide" style="margin:10px 0 0">Transaction annoncée par le client : ' +
            "<strong>" + Utils.echapper(c.transactionAnnoncee) + "</strong>. C'est une " +
            "affirmation, pas une preuve : retrouvez-la dans votre tableau de bord " +
            "KkiaPay avant de confirmer.</p>"
          : "") +
      "</div>"
    );
  }

  async function afficher(vue) {
    UI.entete({ titre: "Commandes", sous: "Ce que les clients ont acheté", retour: true });
    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>' +
      "Lecture des commandes…</div>";

    let commandes;
    try {
      commandes = await Store.listerCommandes();
    } catch (err) {
      vue.innerHTML =
        '<div class="carte"><div class="carte-titre">Commandes indisponibles</div>' +
        '<p class="aide" style="margin:0">' + Utils.echapper(err.message) +
        "<br>Si les achats intégrés viennent d'être mis en place, exécutez le fichier " +
        "supabase/schema.sql dans Supabase.</p></div>";
      return;
    }

    const payees = commandes.filter((c) => c.etat === "payee");
    const aFaire = payees.filter((c) =>
      c.lignes.some((l) => l.etat === "nouvelle" || l.etat === "vue"));
    const faites = payees.filter((c) => !aFaire.includes(c));
    /* Les commandes non payées n'intéressent que l'enseigne : une
       boutique n'a pas à courir après un panier abandonné. */
    const attente = Supabase.estSuper()
      ? commandes.filter((c) => c.etat !== "payee"
          && (c.transactionAnnoncee || c.remarque))
      : [];

    if (!commandes.length) {
      vue.innerHTML = UI.vide("boite", "Aucune commande pour le moment",
        "Les commandes payées par les clients dans l'application BIZZOO " +
        "s'afficheront ici, avec leurs coordonnées.");
      return;
    }

    vue.innerHTML =
      '<div class="carte carte-publier">' +
        '<div class="carte-titre">' + UI.icone("boite", "ic-sm") + " " +
          (aFaire.length
            ? aFaire.length + " commande" + (aFaire.length > 1 ? "s" : "") + " à préparer"
            : "Rien à préparer") + "</div>" +
        '<p class="aide" style="margin:0">Faites avancer chaque article — vue, préparée, ' +
          "remise — pour savoir où vous en êtes. Les prix sont figés : ce qui a été vendu " +
          "est vendu.</p>" +
      "</div>" +
      (aFaire.length ? aFaire.map(htmlCommande).join("") : "") +
      (attente.length
        ? '<div class="titre-section">Paiements à vérifier</div>' +
          attente.map(htmlCommande).join("")
        : "") +
      (faites.length
        ? '<div class="titre-section">Déjà remises</div>' +
          faites.slice(0, 20).map(htmlCommande).join("")
        : "");

    for (const bouton of UI.$$("[data-avancer]", vue)) {
      bouton.onclick = async () => {
        bouton.disabled = true;
        try {
          await Store.avancerLigne(bouton.dataset.avancer, bouton.dataset.etat);
          await afficher(vue);
        } catch (err) {
          UI.toast(err.message, "err");
          bouton.disabled = false;
        }
      };
    }

    for (const bouton of UI.$$("[data-confirmer]", vue)) {
      bouton.onclick = async () => {
        const sur = await UI.confirmer({
          titre: "Confirmer ce paiement ?",
          texte: "À ne faire QUE si vous avez retrouvé la transaction dans votre tableau " +
            "de bord KkiaPay et que l'argent est bien arrivé. La commande portera votre " +
            "nom : on verra qu'elle n'a pas été confirmée par la banque.",
          bouton: "J'ai vérifié, confirmer",
        });
        if (!sur) return;
        bouton.disabled = true;
        try {
          await Store.confirmerPaiement(bouton.dataset.confirmer);
          UI.toast("Paiement confirmé — la boutique peut préparer", "ok");
          await afficher(vue);
        } catch (err) {
          UI.toast(err.message, "err");
          bouton.disabled = false;
        }
      };
    }
  }

  return { afficher };
})();
