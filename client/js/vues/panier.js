/* =========================================================
   Panier, commande et reçu.

   Trois écrans qui se suivent :
     /panier            ce que le client a mis de côté ;
     /commande          ses coordonnées, puis le paiement ;
     /commande/<id>     le reçu, et ce qu'il en est.

   Le montant affiché ici sert à s'y retrouver. Celui qui
   engage est celui que la base renvoie au moment de créer la
   commande — elle relit le catalogue, ligne par ligne.
   ========================================================= */
const VuePanier = (() => {

  const CLE_COORDONNEES = "bizzoo-coordonnees";

  /* ---------- Les coordonnées, retenues d'une fois sur l'autre ---------- */

  function coordonnees() {
    try {
      const c = JSON.parse(localStorage.getItem(CLE_COORDONNEES) || "{}");
      return {
        nom: c.nom || "", tel: c.tel || "",
        indicatif: c.indicatif || Catalogue.boutique().indicatif || "229",
        adresse: c.adresse || "",
      };
    } catch (_) {
      return { nom: "", tel: "", indicatif: "229", adresse: "" };
    }
  }

  function garderCoordonnees(c) {
    try { localStorage.setItem(CLE_COORDONNEES, JSON.stringify(c)); } catch (_) { /* privée */ }
  }

  /* ---------- Le récapitulatif envoyé sur WhatsApp ----------
     Une boutique n'a pas à lire ce qui a été commandé ailleurs :
     chacune reçoit ses lignes à elle, et le total qui la concerne. */

  function messageBoutique(groupe, client, numero) {
    const devise = Catalogue.deviseDe(groupe.lignes[0].produit);
    /* Le code d'abord : c'est par lui que la boutique retrouve l'article
       à coup sûr, quel que soit le nom qu'elle lui donne en rayon. */
    const repere = (p) => {
      const bouts = [];
      if (p.code) bouts.push("code " + p.code);
      if (p.reference) bouts.push("réf. " + p.reference);
      return bouts.length ? " (" + bouts.join(", ") + ")" : "";
    };
    const lignes = groupe.lignes.map((l) =>
      "  • " + l.produit.nom + repere(l.produit) +
      " × " + l.quantite + " — " + Utils.fmtMontant((l.produit.prix || 0) * l.quantite, devise));
    return "Bonjour " + ((groupe.boutique && groupe.boutique.nom) || "") + " 👋\n" +
      (numero ? "Commande " + numero + "\n" : "") +
      "Je souhaite commander :\n" + lignes.join("\n") +
      "\n\nTotal : " + Utils.fmtMontant(groupe.montant, devise) +
      (client && client.nom ? "\n\nNom : " + client.nom : "") +
      (client && client.adresse ? "\nAdresse : " + client.adresse : "");
  }

  function boutonsWhatsApp(groupes, client, numero) {
    const utiles = groupes.filter((g) => g.boutique && (g.boutique.whatsapp || g.boutique.tel));
    if (!utiles.length) return "";
    return utiles.map((g) =>
      '<a class="btn btn-wa" target="_blank" rel="noopener" href="' +
        Utils.echapper(Utils.lienWhatsApp(
          g.boutique.whatsapp || g.boutique.tel,
          messageBoutique(g, client, numero),
          g.boutique.indicatif)) + '">' +
        UI.icone("whatsapp") + "Prévenir " + Utils.echapper(g.boutique.nom) + "</a>").join("");
  }

  /* =====================================================
     Écran 1 — le panier
     ===================================================== */

  async function afficher(vue) {
    const groupes = Panier.parBoutique();
    const devise = Panier.devise();

    UI.entete({
      titre: "Mon panier",
      retour: true,
      sous: Panier.vide() ? "" : Panier.nombre() + " article" + (Panier.nombre() > 1 ? "s" : ""),
      actions: Panier.vide() ? "" :
        '<button type="button" class="btn-ic" id="pa-vider" aria-label="Vider le panier">' +
          UI.icone("fermer") + "</button>",
    });

    if (Panier.vide()) {
      vue.innerHTML = UI.vide("sacoche", "Votre panier est vide",
        "Ouvrez un produit et appuyez sur « Ajouter au panier ».",
        '<a class="btn" href="#/">Parcourir les boutiques</a>' +
        (Panier.mesCommandes().length
          ? '<a class="btn btn-clair" href="#/mes-commandes" style="margin-top:10px">' +
            UI.icone("boite") + "Mes commandes</a>"
          : ""));
      return;
    }

    let html = "";
    for (const groupe of groupes) {
      html +=
        '<div class="carte pa-groupe">' +
          '<div class="pa-groupe-titre">' +
            UI.icone("magasin", "ic-sm") +
            "<span>" + Utils.echapper((groupe.boutique && groupe.boutique.nom) || "Boutique") + "</span>" +
          "</div>" +
          groupe.lignes.map(ligneHtml).join("") +
          '<div class="pa-sous-total"><span>Sous-total</span><strong>' +
            Utils.echapper(Utils.fmtMontant(groupe.montant,
              Catalogue.deviseDe(groupe.lignes[0].produit))) + "</strong></div>" +
        "</div>";
    }

    if (Panier.monnaiesMelangees()) {
      html +=
        '<div class="carte pa-avertissement">' + UI.icone("alerte", "ic-sm") +
          "<div>Votre panier mélange plusieurs monnaies. Commandez boutique par " +
          "boutique : un seul versement ne peut pas les régler ensemble.</div>" +
        "</div>";
    }

    html +=
      '<div class="carte pa-total">' +
        '<div class="pa-total-ligne"><span>Total</span><strong>' +
          Utils.echapper(Utils.fmtMontant(Panier.total(), devise)) + "</strong></div>" +
        '<p class="aide" style="margin:0 0 12px">Livraison et retrait se conviennent avec la ' +
          "boutique après la commande.</p>" +
        '<button type="button" class="btn" id="pa-commander"' +
          (Panier.monnaiesMelangees() ? " disabled" : "") + ">" +
          UI.icone("check") + "Commander</button>" +
      "</div>";

    vue.innerHTML = html;

    UI.$("#pa-vider").onclick = () => {
      Panier.vider();
      UI.toast("Panier vidé", "ok");
      location.hash = "#/";
    };
    UI.$("#pa-commander").onclick = () => { location.hash = "#/commande"; };

    for (const bouton of UI.$$("[data-panier-action]", vue)) {
      bouton.onclick = () => {
        const id = bouton.dataset.produit;
        const action = bouton.dataset.panierAction;
        if (action === "retirer") Panier.retirer(id);
        if (action === "moins") Panier.regler(id, Panier.quantiteDe(id) - 1);
        if (action === "plus") {
          if (Panier.quantiteDe(id) >= Panier.MAX_QUANTITE) {
            UI.toast("99 articles au maximum pour un même produit", "err");
            return;
          }
          Panier.regler(id, Panier.quantiteDe(id) + 1);
        }
        afficher(vue);
      };
    }
  }

  function ligneHtml(l) {
    const p = l.produit;
    const devise = Catalogue.deviseDe(p);
    return (
      '<div class="pa-ligne">' +
        '<a class="pa-ligne-img" href="#/produit/' + Utils.echapper(p.id) + '">' +
          UI.imageProduit(p, "pa-ligne-photo") + "</a>" +
        '<div class="pa-ligne-corps">' +
          '<a class="pa-ligne-nom" href="#/produit/' + Utils.echapper(p.id) + '">' +
            Utils.echapper(p.nom) + "</a>" +
          '<div class="pa-ligne-prix">' + Utils.echapper(Utils.fmtMontant(p.prix, devise)) +
            ' <span class="pa-ligne-sous">= ' +
            Utils.echapper(Utils.fmtMontant((p.prix || 0) * l.quantite, devise)) + "</span></div>" +
          '<div class="pa-compteur">' +
            '<button type="button" data-panier-action="moins" data-produit="' +
              Utils.echapper(p.id) + '" aria-label="Un de moins">−</button>' +
            "<span>" + l.quantite + "</span>" +
            '<button type="button" data-panier-action="plus" data-produit="' +
              Utils.echapper(p.id) + '" aria-label="Un de plus">+</button>' +
            '<button type="button" class="pa-retirer" data-panier-action="retirer" data-produit="' +
              Utils.echapper(p.id) + '" aria-label="Retirer">' + UI.icone("fermer", "ic-sm") + "</button>" +
          "</div>" +
        "</div>" +
      "</div>"
    );
  }

  /* =====================================================
     Écran 2 — les coordonnées, puis le paiement
     ===================================================== */

  async function commander(vue) {
    if (Panier.vide()) {
      location.hash = "#/panier";
      return;
    }
    if (!Paiement.connu()) await Paiement.charger();

    const c = coordonnees();
    const devise = Panier.devise();
    const enLigne = Paiement.disponible();
    /* FeexPay ne s'ouvre pas dans une fenêtre à lui : c'est notre serveur
       qui lance la demande, et le client la valide sur son téléphone. Il
       faut donc lui demander ici l'opérateur et le numéro qui paie. */
    const parFeexpay = enLigne && Paiement.fournisseur() === "feexpay";

    UI.entete({ titre: "Votre commande", retour: true });

    vue.innerHTML =
      '<div class="carte">' +
        '<div class="carte-titre">Où vous joindre</div>' +
        '<div class="champ"><label for="co-nom">Votre nom</label>' +
          '<input id="co-nom" type="text" autocomplete="name" placeholder="Nom et prénom" value="' +
            Utils.echapper(c.nom) + '"></div>' +
        '<div class="champ"><label for="co-tel">Téléphone</label>' +
          '<div class="champ-tel">' +
            '<input id="co-indicatif" type="tel" inputmode="numeric" aria-label="Indicatif" value="' +
              Utils.echapper(c.indicatif) + '">' +
            '<input id="co-tel" type="tel" inputmode="tel" autocomplete="tel" ' +
              'placeholder="97 00 00 00" value="' + Utils.echapper(c.tel) + '">' +
          "</div>" +
          '<p class="aide" style="margin:6px 0 0">C\'est à ce numéro que la boutique vous ' +
            "rappellera pour la livraison.</p></div>" +
        '<div class="champ"><label for="co-adresse">Adresse de livraison</label>' +
          '<input id="co-adresse" type="text" autocomplete="street-address" ' +
            'placeholder="Quartier, repère… ou « je viens retirer »" value="' +
            Utils.echapper(c.adresse) + '"></div>' +
        '<div class="champ"><label for="co-note">Un mot pour la boutique <small>(facultatif)</small></label>' +
          '<textarea id="co-note" rows="2" placeholder="Précisions sur la couleur, la taille…"></textarea></div>' +
      "</div>" +

      '<div class="carte pa-total">' +
        '<div class="pa-total-ligne"><span>Total à régler</span><strong>' +
          Utils.echapper(Utils.fmtMontant(Panier.total(), devise)) + "</strong></div>" +
        (enLigne
          ? (parFeexpay
              ? blocMobileMoney(c)
              : Paiement.bacASable()
                ? '<div class="pa-essai">' + UI.icone("alerte", "ic-sm") +
                  "<div><strong>Paiement en mode essai.</strong> Aucun argent ne sera prélevé, " +
                  "et seuls les numéros de test sont acceptés (MTN 97000000, Moov 95000000).</div></div>"
                : "") +
            '<button type="button" class="btn" id="co-payer">' + UI.icone("energie") +
              "Payer " + Utils.echapper(Utils.fmtMontant(Panier.total(), devise)) + "</button>" +
            '<p class="aide" style="margin:10px 0 0">' +
              (parFeexpay
                ? "Vous recevrez une demande de paiement sur ce numéro : validez-la avec votre " +
                  "code Mobile Money."
                : "Paiement Mobile Money ou carte, par KkiaPay.") +
              " Votre commande n'est transmise aux boutiques qu'une fois le paiement " +
              "confirmé.</p>"
          : '<button type="button" class="btn btn-wa" id="co-whatsapp">' + UI.icone("whatsapp") +
              "Envoyer la commande sur WhatsApp</button>" +
            '<p class="aide" style="margin:10px 0 0">Le paiement en ligne n\'est pas encore ouvert : ' +
              "votre commande part directement à chaque boutique, qui vous rappellera pour " +
              "le règlement et la livraison.</p>") +
      "</div>" +
      '<div id="co-liens"></div>';

    const lire = () => ({
      nom: UI.$("#co-nom").value.trim(),
      tel: UI.$("#co-tel").value.trim(),
      indicatif: UI.$("#co-indicatif").value.trim() || "229",
      adresse: UI.$("#co-adresse").value.trim(),
      note: UI.$("#co-note").value.trim(),
    });

    /* Le numéro qui paie, et l'opérateur choisi. Ils ne sont là qu'avec
       FeexPay ; ailleurs on renvoie de quoi ne rien casser. */
    const lirePaiement = () => {
      const champ = UI.$("#co-mm-tel");
      const actif = UI.$("#co-operateurs .puce.active");
      return {
        numero: champ ? champ.value.trim() : "",
        reseau: actif ? actif.dataset.reseau : "",
      };
    };

    if (parFeexpay) brancherMobileMoney();

    function verifier(client) {
      if (!/\d{6}/.test(Utils.normaliserTel(client.tel))) {
        UI.toast("Indiquez un numéro de téléphone pour vous joindre", "err");
        UI.$("#co-tel").focus();
        return false;
      }
      return true;
    }

    const boutonWa = UI.$("#co-whatsapp");
    if (boutonWa) {
      boutonWa.onclick = () => {
        const client = lire();
        if (!verifier(client)) return;
        garderCoordonnees(client);
        const groupes = Panier.parBoutique();
        UI.$("#co-liens").innerHTML =
          '<div class="carte">' +
            '<div class="carte-titre">Envoyez votre commande</div>' +
            '<p class="aide" style="margin:0 0 12px">Une boutique, un message : chacune ne reçoit ' +
              "que ce qui la concerne.</p>" +
            '<div class="btn-rangee">' + boutonsWhatsApp(groupes, client, "") + "</div>" +
          "</div>";
        UI.$("#co-liens").scrollIntoView({ behavior: "smooth", block: "nearest" });
      };
    }

    const boutonPayer = UI.$("#co-payer");
    if (boutonPayer) {
      boutonPayer.onclick = () =>
        lancerPaiement(boutonPayer, lire, verifier, parFeexpay ? lirePaiement : null);
    }
  }

  /* =====================================================
     Mobile Money : l'opérateur et le numéro qui paie
     =====================================================
     Avec FeexPay il n'y a pas de fenêtre de paiement à ouvrir : la
     demande part vers un numéro, et c'est sur son téléphone que le
     client la valide. Il faut donc savoir chez qui l'envoyer. */
  const OPERATEURS = [
    { cle: "MTN", nom: "MTN" },
    { cle: "MOOV", nom: "Moov" },
    { cle: "CELTIIS", nom: "Celtiis" },
  ];

  function blocMobileMoney(c) {
    const suggere = Paiement.operateurDuNumero(c.tel);
    return (
      '<div class="co-mm">' +
        '<div class="carte-titre" style="margin-top:4px">Payer par Mobile Money</div>' +
        '<div class="champ"><label>Opérateur</label>' +
          '<div class="puces puces-pliees" id="co-operateurs">' +
            OPERATEURS.map((o) =>
              '<button type="button" class="puce' + (o.cle === suggere ? " active" : "") +
                '" data-reseau="' + o.cle + '">' + Utils.echapper(o.nom) + "</button>").join("") +
          "</div></div>" +
        '<div class="champ"><label for="co-mm-tel">Numéro qui paie</label>' +
          '<input id="co-mm-tel" type="tel" inputmode="tel" placeholder="01 97 00 00 00" value="' +
            Utils.echapper(c.tel) + '">' +
          '<p class="aide" style="margin:6px 0 0">Ce peut être un autre numéro que le vôtre — ' +
            "celui d'un proche qui règle pour vous.</p></div>" +
      "</div>"
    );
  }

  /** L'opérateur se met à jour pendant qu'on tape, sans jamais forcer. */
  function brancherMobileMoney() {
    const puces = UI.$$("#co-operateurs .puce");
    for (const puce of puces) {
      puce.onclick = () => {
        for (const autre of puces) autre.classList.remove("active");
        puce.classList.add("active");
      };
    }
    const champ = UI.$("#co-mm-tel");
    if (!champ) return;
    champ.oninput = () => {
      const devine = Paiement.operateurDuNumero(champ.value);
      if (!devine) return;   // porté d'un réseau à l'autre : on ne devine pas
      for (const puce of puces) {
        puce.classList.toggle("active", puce.dataset.reseau === devine);
      }
    };
  }

  /**
   * Créer la commande, ouvrir le paiement, puis ATTENDRE que la base
   * confirme. On n'annonce jamais soi-même un paiement : ce que dit le
   * téléphone n'engage personne, seule la notification de KkiaPay
   * compte.
   */
  async function lancerPaiement(bouton, lire, verifier, lirePaiement) {
    const client = lire();
    if (!verifier(client)) return;

    /* Avec FeexPay, on vérifie AVANT de créer la commande : rien ne sert
       d'enregistrer un panier qu'on ne saura pas où faire payer. */
    let mm = null;
    if (lirePaiement) {
      mm = lirePaiement();
      if (!mm.reseau) {
        UI.toast("Choisissez votre opérateur Mobile Money", "err");
        return;
      }
      if (!/\d{6}/.test(Utils.normaliserTel(mm.numero))) {
        UI.toast("Indiquez le numéro qui va payer", "err");
        const champ = UI.$("#co-mm-tel");
        if (champ) champ.focus();
        return;
      }
    }

    garderCoordonnees(client);

    const libelle = bouton.innerHTML;
    bouton.disabled = true;
    bouton.innerHTML = '<span class="chargement-rond"></span>Préparation…';

    let commande;
    try {
      commande = await Paiement.creerCommande(client, Panier.articles());
    } catch (err) {
      bouton.disabled = false;
      bouton.innerHTML = libelle;
      UI.toast(err.message || "La commande n'a pas pu être enregistrée", "err");
      return;
    }

    /* Le panier tel qu'il était : le reçu doit pouvoir s'afficher même
       si le catalogue change entre-temps. */
    Panier.memoriser({
      id: commande.id, numero: commande.numero, total: commande.total,
      devise: commande.devise, etat: commande.etat || "a_payer",
      client, boutiques: commande.boutiques || [],
    });

    bouton.innerHTML = '<span class="chargement-rond"></span>Paiement…';
    let transaction = "";
    try {
      if (mm) {
        /* FeexPay : notre serveur ouvre la demande. Ce qu'il nous rend
           n'est PAS une preuve de paiement — juste « c'est parti,
           regardez votre téléphone ». */
        await Paiement.ouvrirFeexpay({
          commande: commande.id, tel: client.tel,
          numero: mm.numero, reseau: mm.reseau,
        });
        UI.toast("Validez la demande sur votre téléphone");
      } else {
        const reponse = await Paiement.payer({
          montant: commande.total, commande: commande.id,
          nom: client.nom, tel: client.indicatif + client.tel,
        });
        transaction = reponse.transactionId || "";
      }
    } catch (err) {
      bouton.disabled = false;
      bouton.innerHTML = libelle;
      /* Un paiement abandonné n'est pas une commande perdue : elle
         attend, et le reçu propose de reprendre. */
      UI.toast(err.message || "Le paiement n'a pas abouti", "err");
      location.hash = "#/commande/" + commande.id;
      return;
    }

    if (transaction) await Paiement.signalerTransaction(commande.id, transaction);
    Panier.majEtat(commande.id, "a_payer", { transaction });
    Panier.vider();
    location.hash = "#/commande/" + commande.id;
  }

  /* =====================================================
     Écran 3 — le reçu
     ===================================================== */

  const ETATS = {
    a_payer: { nom: "En attente de confirmation", classe: "badge-commande" },
    payee: { nom: "Payée", classe: "badge-disponible" },
    echouee: { nom: "Paiement non abouti", classe: "badge-rupture" },
    annulee: { nom: "Annulée", classe: "badge-rupture" },
  };

  async function recu(vue, id) {
    const commande = Panier.commande(id);
    UI.entete({ titre: "Commande", retour: true, sous: commande ? commande.numero : "" });

    if (!commande) {
      vue.innerHTML = UI.vide("alerte", "Commande introuvable",
        "Elle a peut-être été passée depuis un autre téléphone.",
        '<a class="btn btn-clair" href="#/">Retour à l\'accueil</a>');
      return;
    }

    dessinerRecu(vue, commande);

    /* Quelques secondes passent entre le moment où le client valide et
       celui où l'encaissement est constaté : on patiente, on n'annonce
       pas. Avec KkiaPay, une transaction a été rendue au téléphone ;
       avec FeexPay il n'y en a aucune — c'est notre serveur qui ira
       demander, alors on attend dès que la commande est à payer. */
    if (commande.etat === "a_payer"
        && (commande.transaction || Paiement.fournisseur() === "feexpay")) {
      const etat = await Paiement.attendreConfirmation(commande.id, commande.client.tel);
      if (etat && (etat.etat !== commande.etat || etat.remarque)) {
        const maj = Panier.majEtat(commande.id, etat.etat, { remarque: etat.remarque || "" });
        if (location.hash === "#/commande/" + id) dessinerRecu(vue, maj);
      } else if (location.hash === "#/commande/" + id) {
        const attente = UI.$("#re-attente");
        if (attente) {
          attente.innerHTML = UI.icone("horloge", "ic-sm") +
            "<div>La confirmation tarde. Si vous avez bien été débité, la boutique " +
            "recevra votre commande dès que " +
            (Paiement.fournisseur() === "feexpay" ? "FeexPay aura confirmé le versement"
                                                  : "KkiaPay l'aura signalée") +
            " — vous n'avez rien à refaire. Gardez le numéro <strong>" +
            Utils.echapper(commande.numero) + "</strong>.</div>";
        }
      }
    }
  }

  function dessinerRecu(vue, commande) {
    const etat = ETATS[commande.etat] || ETATS.a_payer;
    const payee = commande.etat === "payee";
    const groupes = (commande.boutiques || []).map((b) => ({
      boutique: Catalogue.boutiques().find((x) => x.id === b.id) ||
        { id: b.id, nom: b.nom, whatsapp: b.whatsapp, indicatif: b.indicatif, tel: "" },
      montant: b.montant,
      lignes: (b.lignes || []).map((l) => ({
        produit: { nom: l.nom, code: l.code || "", reference: l.reference, prix: l.prix },
        quantite: l.quantite,
      })),
    }));

    vue.innerHTML =
      '<div class="carte re-entete">' +
        '<div class="re-numero">' + Utils.echapper(commande.numero) + "</div>" +
        '<span class="badge ' + etat.classe + '">' + Utils.echapper(etat.nom) + "</span>" +
        '<div class="re-montant">' +
          Utils.echapper(Utils.fmtMontant(commande.total, commande.devise)) + "</div>" +
        (commande.remarque
          ? '<div class="pa-avertissement" style="margin-top:12px">' + UI.icone("alerte", "ic-sm") +
            "<div>" + Utils.echapper(commande.remarque) + "</div></div>"
          : "") +
      "</div>" +

      (payee
        ? '<div class="carte pa-confirme">' + UI.icone("check") +
            "<div><strong>Paiement confirmé.</strong> " +
            (groupes.length > 1 ? "Les boutiques concernées ont reçu" : "La boutique a reçu") +
            " votre commande dans leur compte. Elles vous rappellent au " +
            Utils.echapper(commande.client.indicatif + " " + commande.client.tel) +
            " pour la remise.</div></div>"
        : '<div class="carte pa-avertissement" id="re-attente">' +
            '<span class="chargement-rond"></span>' +
            "<div>" + (Paiement.fournisseur() === "feexpay"
              ? "Validez la demande sur votre téléphone, avec votre code Mobile Money. " +
                "Nous allons ensuite demander à FeexPay si le versement a abouti."
              : "Nous attendons la confirmation de KkiaPay. Cela prend quelques secondes.") +
            " Ne payez pas une seconde fois.</div>" +
          "</div>") +

      groupes.map((g) =>
        '<div class="carte pa-groupe">' +
          '<div class="pa-groupe-titre">' + UI.icone("magasin", "ic-sm") +
            "<span>" + Utils.echapper(g.boutique.nom || "Boutique") + "</span></div>" +
          g.lignes.map((l) =>
            '<div class="re-ligne"><span>' + Utils.echapper(l.produit.nom) +
              (l.produit.code
                ? ' <small class="re-code">code ' + Utils.echapper(l.produit.code) + "</small>"
                : "") +
              ' <small>× ' + l.quantite + "</small></span><strong>" +
              Utils.echapper(Utils.fmtMontant(l.produit.prix * l.quantite, commande.devise)) +
            "</strong></div>").join("") +
          '<div class="pa-sous-total"><span>Sous-total</span><strong>' +
            Utils.echapper(Utils.fmtMontant(g.montant, commande.devise)) + "</strong></div>" +
        "</div>").join("") +

      (payee
        ? '<div class="carte">' +
            '<div class="carte-titre">Prévenir la boutique</div>' +
            '<p class="aide" style="margin:0 0 12px">Facultatif : elle a déjà votre commande. ' +
              "Un message WhatsApp accélère souvent la préparation.</p>" +
            '<div class="btn-rangee">' +
              boutonsWhatsApp(groupes, commande.client, commande.numero) + "</div>" +
          "</div>"
        : "") +

      '<div class="carte">' +
        '<div class="btn-rangee">' +
          '<a class="btn btn-clair" href="#/mes-commandes">' + UI.icone("boite") +
            "Mes commandes</a>" +
          '<a class="btn btn-clair" href="#/">Continuer mes achats</a>' +
        "</div>" +
      "</div>";
  }

  /* =====================================================
     Écran 4 — mes commandes
     ===================================================== */

  async function mesCommandes(vue) {
    const liste = Panier.mesCommandes();
    UI.entete({ titre: "Mes commandes", retour: true });

    if (!liste.length) {
      vue.innerHTML = UI.vide("boite", "Aucune commande",
        "Les commandes que vous passerez depuis ce téléphone s'afficheront ici.",
        '<a class="btn" href="#/">Parcourir les boutiques</a>');
      return;
    }

    vue.innerHTML = liste.map((c) => {
      const etat = ETATS[c.etat] || ETATS.a_payer;
      return '<a class="carte re-resume" href="#/commande/' + Utils.echapper(c.id) + '">' +
        "<div><div class=\"re-resume-numero\">" + Utils.echapper(c.numero) + "</div>" +
        '<div class="re-resume-date">' +
          Utils.echapper(Utils.fmtDateHeure(new Date(c.gardeeLe || Date.now()).toISOString())) +
        "</div></div>" +
        '<div style="text-align:right">' +
          "<div><strong>" + Utils.echapper(Utils.fmtMontant(c.total, c.devise)) + "</strong></div>" +
          '<span class="badge ' + etat.classe + '">' + Utils.echapper(etat.nom) + "</span>" +
        "</div></a>";
    }).join("");
  }

  return { afficher, commander, recu, mesCommandes };
})();
