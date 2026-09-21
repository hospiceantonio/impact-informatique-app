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

  /* ---------- Faut-il un compte pour aller plus loin ? ----------

     L'enseigne décide, et sa décision vit en base. Ici on ne fait que
     la lire pour dessiner le bon écran : le VRAI refus est dans
     « creer_commande », qui ne laisse rien passer même si l'on
     l'appelait sans passer par nos écrans.

     Deux conditions, pas une : la règle est allumée ET le client n'est
     pas connecté. Connecté, il ne voit aucune différence. */
  function compteRequis() {
    if (typeof Compte === "undefined") return false;
    return Compte.compteExige() && !Compte.connecte();
  }

  /* ---------- Les coordonnées, retenues d'une fois sur l'autre ---------- */

  function coordonnees() {
    /* Le compte passe devant le téléphone. C'est tout l'intérêt d'en avoir
       un : on ne retape pas ses coordonnées sur un appareil neuf. Ce qui
       manque au compte est complété par ce que ce téléphone-ci avait
       gardé. */
    const moi = (typeof Compte !== "undefined" && Compte.moi()) || null;
    try {
      const c = JSON.parse(localStorage.getItem(CLE_COORDONNEES) || "{}");
      return {
        nom: (moi && moi.nom) || c.nom || "",
        tel: (moi && moi.tel) || c.tel || "",
        indicatif: (moi && moi.indicatif) || c.indicatif || Catalogue.boutique().indicatif || "229",
        adresse: (moi && moi.adresse) || c.adresse || "",
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
        /* Dire au revendeur que ce total est déjà le sien : sans cela,
           il attend une remise à la caisse qui ne viendra pas — elle est
           déjà dans le chiffre qu'il lit. */
        (Catalogue.auxPrixRevendeur()
          ? '<div class="fiche-revendeur" style="margin:0 0 10px">' +
            UI.icone("magasin", "ic-sm") + "Total à vos prix revendeur</div>"
          : "") +
        '<p class="aide" style="margin:0 0 12px">Livraison et retrait se conviennent avec la ' +
          "boutique après la commande.</p>" +
        /* Le prévenir ICI, pas au bout du formulaire. Découvrir qu'il
           faut un compte après avoir tapé son nom, son numéro et son
           adresse, c'est le meilleur moyen de faire abandonner un
           panier plein. */
        (compteRequis()
          ? '<div class="pa-compte-requis">' + UI.icone("compte", "ic-sm") +
            "<div>Un compte BIZZOO est nécessaire pour commander. " +
            "L'étape suivante vous le proposera.</div></div>"
          : "") +
        '<button type="button" class="btn btn-orange" id="pa-commander"' +
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
     Écran 2 bis — « il faut un compte »

     Ce n'est pas une porte close, c'est une porte à ouvrir : on
     dit pourquoi, on rassure sur le panier, et on donne les trois
     façons d'entrer — dont celle par SMS, qui ne demande ni
     adresse e-mail ni mot de passe à retenir.

     Les trois mènent au même endroit : « revenirVers » pose le
     retour, et l'écran de commande revient de lui-même une fois
     le compte ouvert.
     ===================================================== */

  function inviterAuCompte(vue) {
    UI.entete({ titre: "Votre commande", retour: true });

    const devise = Panier.devise();

    vue.innerHTML =
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("compte") + "Un compte pour commander</div>" +
        '<p class="aide" style="margin:0 0 4px">BIZZOO demande désormais un compte ' +
          "avant de valider une commande. C'est lui qui vous permet de suivre " +
          "votre commande, de la retrouver depuis n'importe quel téléphone, de " +
          "donner votre avis et d'ouvrir une réclamation si quelque chose ne va pas.</p>" +
        '<p class="aide" style="margin:10px 0 0">Votre panier vous attend : ' +
          "<strong>" + Utils.echapper(Utils.fmtMontant(Panier.total(), devise)) +
          "</strong>. Rien n'en sera perdu.</p>" +
      "</div>" +

      '<div class="carte">' +
        '<a class="btn" href="#/inscription" data-vers-compte>' +
          UI.icone("compte") + "Créer mon compte</a>" +
        '<a class="btn btn-clair" href="#/connexion-tel" data-vers-compte ' +
          'style="margin-top:10px">' + UI.icone("telephone") +
          "Entrer avec mon numéro</a>" +
        '<p class="aide" style="margin:12px 0 0">Vous avez déjà un compte ? ' +
          '<a href="#/connexion" data-vers-compte>Se connecter</a></p>' +
      "</div>" +

      '<div class="carte">' +
        '<p class="aide" style="margin:0"><a href="#/panier">Revenir au panier</a> ' +
          "pour modifier ce que vous avez choisi.</p>" +
      "</div>";

    /* Quelle que soit la porte prise, on revient ici une fois entré. */
    for (const lien of UI.$$("[data-vers-compte]", vue)) {
      lien.addEventListener("click", () => VueCompte.revenirVers("#/commande"));
    }
  }

  /* =====================================================
     Écran 2 — les coordonnées, puis le paiement
     ===================================================== */

  /* Le code promo appliqué, et ce qu'il retire. C'EST UN APERÇU : la
     base recalculera tout au moment de commander, et c'est son montant
     qui fait foi. On le garde ici seulement pour l'afficher.

     Il se vide dès qu'on quitte l'écran : un code appliqué sur un panier
     qu'on a ensuite modifié ne vaut plus rien. */
  let promo = { code: "", remise: 0 };

  async function commander(vue) {
    promo = { code: "", remise: 0 };
    if (Panier.vide()) {
      location.hash = "#/panier";
      return;
    }
    if (!Paiement.connu()) await Paiement.charger();
    /* La règle avant de dessiner, comme la fiche : on ne veut pas d'un
       formulaire qui s'affiche puis se remplace sous les doigts.

       On la redemande dans deux cas seulement. Si on ne la connaît pas,
       évidemment. Et si elle dit « il faut un compte » — parce que
       c'est le seul cas où se tromper COÛTE : une règle éteinte depuis,
       gardée dans le téléphone, renverrait un client qu'on avait le
       droit de servir. L'inverse ne coûte rien : la base refusera, et
       son refus s'affiche.

       Et jamais pour un client CONNECTÉ : la règle ne le concerne pas,
       et lui imposer une attente au moment de payer serait absurde.

       Sans réponse, on garde la dernière règle connue. */
    if (typeof Compte !== "undefined" && !Compte.connecte()
        && (!Compte.reglesConnues() || Compte.compteExige())) {
      try { await Compte.chargerRegles(); } catch (_) { /* la dernière connue */ }
    }
    /* La fiche du compte avant de dessiner : sinon les champs s'affichent
       vides puis se remplissent sous les doigts du client. */
    if (typeof Compte !== "undefined" && Compte.connecte()) {
      try { await Compte.charger(); } catch (_) { /* on commandera sans */ }
    }

    /* L'enseigne exige un compte, et ce client n'en a pas : on s'arrête
       là. Le panier n'est pas touché — il l'attendra au retour, et c'est
       bien tout ce qui compte à ce moment-là. */
    if (compteRequis()) {
      inviterAuCompte(vue);
      return;
    }

    const c = coordonnees();
    const devise = Panier.devise();
    const enLigne = Paiement.disponible();
    /* FeexPay ne s'ouvre pas dans une fenêtre à lui : c'est notre serveur
       qui lance la demande, et le client la valide sur son téléphone. Il
       faut donc lui demander ici l'opérateur et le numéro qui paie. */
    const parFeexpay = enLigne && Paiement.fournisseur() === "feexpay";

    UI.entete({ titre: "Votre commande", retour: true });

    vue.innerHTML =
      (typeof Compte !== "undefined" && !Compte.connecte()
        ? '<div class="carte">' +
            '<p class="aide" style="margin:0 0 10px">Vous avez un compte BIZZOO ? ' +
              "Connectez-vous pour retrouver vos coordonnées et suivre cette " +
              "commande depuis n'importe quel téléphone.</p>" +
            '<a class="btn btn-clair" href="#/connexion" id="co-connexion">' +
              UI.icone("compte") + "Se connecter</a>" +
          "</div>"
        : "") +
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

      /* LE CODE PROMO N'A DE SENS QUE SI BIZZOO ENCAISSE. Quand le
         paiement en ligne est fermé, la commande part directement chez
         chaque boutique par WhatsApp : aucune commande n'est créée en
         base, BIZZOO ne touche rien, et il n'y a donc aucune marge sur
         laquelle prendre une remise.

         Montrer le champ quand même serait pire que de ne rien offrir :
         le client verrait 18 000 à l'écran puis enverrait un message
         disant 20 000. C'est exactement l'écart que tout ce travail
         cherche à rendre impossible. */
      (enLigne
        ? '<div class="carte" id="co-promo">' +
        '<div class="champ" style="margin:0">' +
          '<label for="co-code">Code promo <small>(si vous en avez un)</small></label>' +
          '<div class="co-code-ligne">' +
            '<input id="co-code" type="text" autocomplete="off" ' +
              'autocapitalize="characters" placeholder="Votre code">' +
            '<button type="button" class="btn btn-clair" id="co-code-appliquer">' +
              "Appliquer</button>" +
          "</div>" +
          '<div id="co-code-reponse"></div>' +
        "</div>" +
      "</div>"
        : "") +

      '<div class="carte pa-total">' +
        '<div id="co-lignes-total">' +
          '<div class="pa-total-ligne"><span>Total à régler</span><strong>' +
            Utils.echapper(Utils.fmtMontant(Panier.total(), devise)) + "</strong></div>" +
        "</div>" +
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

    /* Un client qu'on envoie se connecter depuis son panier doit revenir
       à son panier, pas à l'accueil : il était en train d'acheter. */
    const lien = UI.$("#co-connexion");
    if (lien) lien.addEventListener("click", () => VueCompte.revenirVers("#/commande"));

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

    brancherCode(vue, devise, boutonPayer);
  }

  /* -----------------------------------------------------
     Le code promo
     -----------------------------------------------------
     L'application ne calcule RIEN : elle demande à la base, qui répond
     avec la fonction que la caisse appellera ensuite. C'est la même
     règle des deux côtés — sans quoi le client verrait un montant et en
     paierait un autre. */

  /** Ce que le client paiera, remise déduite. Aperçu : la base tranche. */
  const aRegler = () => Math.max(0, Panier.total() - (promo.remise || 0));

  /** Redessine le total et le bouton après un code appliqué ou retiré. */
  function rafraichirTotal(vue, devise, boutonPayer) {
    const bloc = UI.$("#co-lignes-total", vue);
    if (bloc) {
      bloc.innerHTML = promo.remise > 0
        ? '<div class="pa-total-ligne"><span>Sous-total</span><span>' +
            Utils.echapper(Utils.fmtMontant(Panier.total(), devise)) + "</span></div>" +
          '<div class="pa-total-ligne co-remise"><span>Code ' +
            Utils.echapper(promo.code) + "</span><span>− " +
            Utils.echapper(Utils.fmtMontant(promo.remise, devise)) + "</span></div>" +
          '<div class="pa-total-ligne"><span>Total à régler</span><strong>' +
            Utils.echapper(Utils.fmtMontant(aRegler(), devise)) + "</strong></div>"
        : '<div class="pa-total-ligne"><span>Total à régler</span><strong>' +
            Utils.echapper(Utils.fmtMontant(Panier.total(), devise)) + "</strong></div>";
    }
    if (boutonPayer) {
      boutonPayer.innerHTML = UI.icone("energie") +
        "Payer " + Utils.echapper(Utils.fmtMontant(aRegler(), devise));
    }
  }

  function brancherCode(vue, devise, boutonPayer) {
    const champ = UI.$("#co-code", vue);
    const bouton = UI.$("#co-code-appliquer", vue);
    const reponse = UI.$("#co-code-reponse", vue);
    if (!champ || !bouton || !reponse) return;

    const dire = (classe, texte) => {
      reponse.innerHTML = '<div class="' + classe + '">' + Utils.echapper(texte) + "</div>";
    };

    async function appliquer() {
      const saisi = champ.value.trim();
      if (!saisi) {
        /* Champ vidé : on retire la remise. Laisser l'ancienne en place
           afficherait un montant que la caisse ne retiendrait pas. */
        promo = { code: "", remise: 0 };
        reponse.innerHTML = "";
        rafraichirTotal(vue, devise, boutonPayer);
        return;
      }
      bouton.disabled = true;
      bouton.textContent = "…";
      try {
        const r = await Paiement.verifierCode(saisi, Panier.articles());
        if (r && r.ok) {
          promo = { code: saisi.toUpperCase(), remise: Number(r.remise) || 0 };
          dire("co-code-ok",
            "Code accepté : " + Utils.fmtMontant(promo.remise, devise) + " de moins.");
        } else {
          promo = { code: "", remise: 0 };
          dire("co-code-non", (r && r.raison) || "Ce code n'est pas valable.");
        }
      } catch (err) {
        /* La base injoignable n'est pas un code refusé : on le dit
           autrement, et on ne retire rien. */
        promo = { code: "", remise: 0 };
        dire("co-code-non", "Impossible de vérifier ce code pour l'instant.");
      }
      bouton.disabled = false;
      bouton.textContent = "Appliquer";
      rafraichirTotal(vue, devise, boutonPayer);
    }

    bouton.onclick = appliquer;
    champ.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); appliquer(); }
    });
    /* Modifier le code sans réappliquer ne doit pas laisser croire que
       l'ancienne remise tient encore. */
    champ.addEventListener("input", () => {
      if (promo.code && champ.value.trim().toUpperCase() !== promo.code) {
        promo = { code: "", remise: 0 };
        reponse.innerHTML = "";
        rafraichirTotal(vue, devise, boutonPayer);
      }
    });
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
      /* Le code part avec la commande. S'il ne vaut plus rien — expiré
         entre-temps, quota atteint — la base passe la commande SANS lui
         plutôt que de la refuser : le panier est bon, c'est le code qui
         ne l'est plus. Le récapitulatif dira ce qui a été retenu. */
      commande = await Paiement.creerCommande(client, Panier.articles(), promo.code);
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

  /* Deux libellés par état, et ce n'est pas une coquetterie : sur le
     reçu, la phrase entière rassure — le client vient de payer et veut
     savoir où il en est. Dans la LISTE, elle déborde de sa colonne et
     passe à la ligne au milieu d'un mot. Le mot court y suffit : la
     phrase entière l'attend en ouvrant la commande. */
  const ETATS = {
    a_payer: { nom: "En attente de confirmation", court: "En attente", classe: "badge-commande" },
    payee: { nom: "Payée", court: "Payée", classe: "badge-disponible" },
    echouee: { nom: "Paiement non abouti", court: "Non abouti", classe: "badge-rupture" },
    annulee: { nom: "Annulée", court: "Annulée", classe: "badge-rupture" },
  };

  async function recu(vue, id) {
    /* Le téléphone d'abord : c'est instantané, et cela marche hors
       connexion. Un client qui rouvre le reçu qu'il vient de recevoir
       ne doit pas attendre un aller-retour réseau. */
    let commande = Panier.commande(id);
    UI.entete({ titre: "Commande", retour: true, sous: commande ? commande.numero : "" });

    /* Rien ici ? La commande a peut-être été passée depuis un AUTRE
       téléphone. C'est exactement ce que le compte doit rattraper : on
       va la demander à la base. Les règles de la base décident — un
       identifiant de commande qui n'est pas le sien ne rend rien. */
    if (!commande && typeof Compte !== "undefined" && Compte.connecte()) {
      vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>' +
        "Lecture de la commande…</div>";
      try {
        commande = await Compte.commande(id);
      } catch (_) { /* hors connexion, ou commande d'un autre */ }
      if (commande) {
        UI.entete({ titre: "Commande", retour: true, sous: commande.numero });
      }
    }

    if (!commande) {
      vue.innerHTML = UI.vide("alerte", "Commande introuvable",
        typeof Compte !== "undefined" && Compte.connecte()
          ? "Elle n'appartient pas à ce compte, ou la connexion manque."
          : "Elle a peut-être été passée depuis un autre téléphone. " +
            "Connectez-vous pour retrouver vos commandes.",
        '<a class="btn btn-clair" href="#/">Retour à l\'accueil</a>');
      return;
    }

    /* LES RÉGLAGES D'ABORD, L'ÉCRAN ENSUITE. Tout ce qui suit dépend de
       l'agrégateur, et « Paiement.charger() » est lancé sans être attendu
       au démarrage : un client qui rouvre l'application directement sur
       son reçu — depuis un lien, ou après l'avoir fermée — arriverait ici
       avant la réponse. On retomberait alors sur l'agrégateur par défaut,
       donc sur le mauvais texte ET sur une attente jamais lancée : sa
       commande resterait « en attente de confirmation » pour toujours,
       alors que son versement, lui, est bien passé. */
    if (!Paiement.connu()) await Paiement.charger();

    dessinerRecu(vue, commande);
    brancherSuivi(vue, commande);

    /* Le SAV, sous le reçu : c'est ici que le client est quand il
       constate un problème, et c'est cette commande-là qui prouve son
       achat. Le bloc ne s'ajoute qu'à une commande PAYÉE — avant, il
       n'y a rien à réclamer. */
    const sav = VueSAV.blocReçu(commande);
    if (sav) {
      vue.insertAdjacentHTML("beforeend", sav);
      VueSAV.remplirReçu(commande);
    }

    /* Quelques secondes passent entre le moment où le client valide et
       celui où l'encaissement est constaté : on patiente, on n'annonce
       pas. Avec KkiaPay, une transaction a été rendue au téléphone ;
       avec FeexPay il n'y en a aucune — c'est notre serveur qui ira
       demander, alors on attend dès que la commande est à payer. */
    if (commande.etat === "a_payer"
        && (commande.transaction || Paiement.fournisseur() === "feexpay")) {
      const etat = await Paiement.attendreConfirmation(commande.id, commande.client.tel);
      if (etat && (etat.etat !== commande.etat || etat.remarque)) {
        /* « majEtat » ne sait noter que ce que CE téléphone garde : une
           commande lue dans la base n'y figure pas, et il rend null. On
           met donc à jour l'objet qu'on a en main, et le téléphone en
           plus quand il la connaît. Sans cela, un reçu ouvert depuis un
           autre appareil se vidait à la confirmation du paiement. */
        commande.etat = etat.etat;
        commande.remarque = etat.remarque || "";
        Panier.majEtat(commande.id, etat.etat, { remarque: etat.remarque || "" });
        if (location.hash === "#/commande/" + id) dessinerRecu(vue, commande);
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

  /* -----------------------------------------------------
     Où en est ma commande
     -----------------------------------------------------
     Les cinq étapes que la boutique fait avancer, et — quand elle a
     déclaré avoir remis — le bouton par lequel le CLIENT le confirme.

     Ce bouton ne fait pas double emploi avec la déclaration de la
     boutique : ce sont deux paroles différentes. La boutique dit « j'ai
     remis » ; le client dit « j'ai reçu ». La base refuse à chacun de
     signer pour l'autre, et c'est tout l'intérêt — le jour d'un litige,
     il reste quelque chose à interroger. */
  const ETAPES = [
    { cle: "nouvelle", mot: "Commande reçue" },
    { cle: "vue", mot: "Vue par la boutique" },
    { cle: "preparee", mot: "Préparée" },
    { cle: "en_livraison", mot: "En livraison" },
    { cle: "remise", mot: "Remise" },
  ];

  function blocSuivi(commande, g) {
    /* Une commande qui ne vient pas de la base n'a pas d'état de
       préparation : on ne montre rien plutôt que d'inventer une étape.
       Et avant le paiement, il n'y a rien à suivre. */
    if (commande.etat !== "payee" || !g.etat) return "";
    if (g.etat === "annulee") {
      return '<div class="re-suivi re-suivi-annule">' + UI.icone("fermer", "ic-sm") +
        "<span>Cette boutique a annulé sa part de la commande.</span></div>";
    }
    const rang = ETAPES.findIndex((e) => e.cle === g.etat);
    const remise = g.etat === "remise";

    return '<div class="re-suivi">' +
      ETAPES.map((e, i) =>
        '<div class="re-etape' + (i <= rang ? " faite" : "") + '">' +
          '<span class="re-puce">' + (i <= rang ? UI.icone("check", "ic-sm") : "") + "</span>" +
          "<span>" + Utils.echapper(e.mot) + "</span>" +
        "</div>").join("") +
      (remise && g.confirme
        ? '<div class="re-recu">' + UI.icone("check", "ic-sm") +
          "<span>Vous avez confirmé avoir reçu cette commande.</span></div>"
        : remise
          ? '<button type="button" class="btn btn-clair re-confirmer" ' +
              'data-boutique="' + Utils.echapper(g.boutique.id || "") + '">' +
              UI.icone("check") + "J'ai bien reçu</button>" +
            '<p class="aide" style="margin:8px 0 0">La boutique a déclaré vous avoir ' +
              "remis cette commande. Confirmez-le pour clore de votre côté — et " +
              "n'hésitez pas à ouvrir une réclamation si ce n'est pas le cas.</p>"
          : "") +
    "</div>";
  }

  /** Brancher les boutons « J'ai bien reçu » du reçu. */
  function brancherSuivi(vue, commande) {
    for (const b of UI.$$(".re-confirmer", vue)) {
      b.onclick = async () => {
        b.disabled = true;
        try {
          await Compte.confirmerReception(commande.id, b.dataset.boutique);
          UI.toast("Merci, c'est noté.");
          /* On relit la commande plutôt que de cocher à l'écran : ce
             qui s'affiche doit venir de la base, comme le reste. */
          location.reload();
        } catch (err) {
          /* La base explique pourquoi — « rien à confirmer ici » quand
             la boutique n'a encore rien déclaré. On la cite. */
          UI.toast(err.message, "err");
          b.disabled = false;
        }
      };
    }
  }

  function dessinerRecu(vue, commande) {
    const etat = ETATS[commande.etat] || ETATS.a_payer;
    const payee = commande.etat === "payee";
    const groupes = (commande.boutiques || []).map((b) => ({
      boutique: Catalogue.boutiques().find((x) => x.id === b.id) ||
        { id: b.id, nom: b.nom, whatsapp: b.whatsapp, indicatif: b.indicatif, tel: "" },
      montant: b.montant,
      /* Où en est CETTE boutique, et si le client a déjà confirmé. Les
         deux viennent de la base ; une commande qui ne vit que sur le
         téléphone n'en sait rien, et l'écran ne montre alors pas le
         suivi plutôt que d'inventer une étape. */
      etat: b.etat || "",
      confirme: !!b.confirme,
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
          blocSuivi(commande, g) +
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

  /** Une commande, en résumé, dans la liste. */
  function resumeHtml(c) {
    /* OÙ EN EST LE COLIS PASSE AVANT L'ÉTAT DU PAIEMENT. Une commande
       payée affichait « Payée » pour toujours : préparée, partie,
       remise — rien ne bougeait dans la liste, et le client rouvrait
       le reçu ou appelait la boutique pour savoir.

       Tant qu'elle n'est pas payée, il n'y a rien à suivre : c'est
       alors le paiement qui parle, comme avant. */
    const suivi = (typeof Compte !== "undefined" && Compte.statutLivraison)
      ? Compte.statutLivraison(c) : null;
    const etat = suivi
      ? { court: suivi.mot, nom: suivi.mot, classe: suivi.classe }
      : (ETATS[c.etat] || ETATS.a_payer);
    return '<a class="carte re-resume" href="#/commande/' + Utils.echapper(c.id) + '">' +
      '<div class="re-resume-ligne">' +
      "<div><div class=\"re-resume-numero\">" + Utils.echapper(c.numero) +
        /* Une commande que la base ne connaît pas encore : elle ne vit
           que sur ce téléphone. Le dire permet de comprendre ce qu'un
           numéro vérifié irait rechercher. */
        (c.depuisLaBase ? "" :
          ' <span class="badge badge-local">' + UI.icone("telephone", "ic-sm") +
          "Ce téléphone</span>") +
      "</div>" +
      '<div class="re-resume-date">' +
        Utils.echapper(Utils.fmtDateHeure(new Date(c.gardeeLe || Date.now()).toISOString())) +
      "</div></div>" +
      '<div style="text-align:right">' +
        "<div><strong>" + Utils.echapper(Utils.fmtMontant(c.total, c.devise)) + "</strong></div>" +
        '<span class="badge ' + etat.classe + '">' +
          Utils.echapper(etat.court || etat.nom) + "</span>" +
      "</div></div>" +
      barreSuivi(suivi, c) +
    "</a>";
  }

  /* ---------- Confirmer la réception, depuis la liste ----------

     La boutique a déclaré « remis ». Il manque la parole du CLIENT, et
     elle ne se donnait qu'en ouvrant le reçu — un écran de plus pour
     un seul bouton, et beaucoup ne l'ouvraient jamais. Le bouton
     apparaît donc là où le client voit « Livré ».

     DEUX PAROLES, PAS UNE. La boutique dit « j'ai remis », le client
     dit « j'ai reçu ». La base refuse à chacun de signer pour l'autre,
     et c'est ce qui laisse quelque chose à interroger le jour d'un
     litige. Le bouton ne double donc pas la déclaration de la
     boutique : il en ajoute une autre.

     UNE COMMANDE PEUT TRAVERSER PLUSIEURS BOUTIQUES. Le statut ne dit
     « Livré » que lorsque TOUTES ont remis : confirmer ici vaut donc
     pour toutes celles qui attendent encore, et c'est bien ce que le
     client veut dire — « j'ai tout reçu ». */
  function boutonRecu(c) {
    const aConfirmer = (c.boutiques || [])
      .filter((g) => g && g.etat === "remise" && !g.confirme);
    if (!aConfirmer.length) return "";
    return (
      '<button type="button" class="btn btn-clair re-recu-btn" data-recu="' +
        Utils.echapper(c.id) + '">' + UI.icone("check", "ic-sm") +
        "J'ai bien reçu" +
        (aConfirmer.length > 1
          ? " (" + aConfirmer.length + " boutiques)" : "") +
      "</button>"
    );
  }

  /**
   * Brancher les boutons de la liste.
   *
   * LA CARTE EST UN LIEN, et le bouton vit dedans : sans
   * « preventDefault », le toucher ouvrirait la commande et la
   * confirmation se perdrait en route. C'est la même leçon que le cœur
   * des favoris.
   */
  function brancherRecus(vue, liste) {
    for (const b of UI.$$("[data-recu]", vue)) {
      b.addEventListener("click", async (ev) => {
        ev.preventDefault();
        ev.stopPropagation();
        const c = liste.find((x) => x.id === b.dataset.recu);
        if (!c) return;
        const boutiques = (c.boutiques || [])
          .filter((g) => g && g.etat === "remise" && !g.confirme);
        b.disabled = true;
        try {
          /* Une boutique après l'autre : la base signe par boutique, et
             une commande partagée en compte plusieurs. */
          for (const g of boutiques) {
            await Compte.confirmerReception(c.id, g.id);
          }
          UI.toast("Merci, c'est noté.");
          /* On relit plutôt que de cocher à l'écran : ce qui s'affiche
             doit venir de la base, comme le reste. */
          mesCommandes(vue);
        } catch (err) {
          /* La base explique pourquoi — « rien à confirmer ici » quand
             la boutique n'a encore rien déclaré. On la cite. */
          UI.toast(err.message || "Impossible pour l'instant.", "err");
          b.disabled = false;
        }
      });
    }
  }

  /* ---------- La barre de suivi, sous la commande ----------

     QUATRE PALIERS, remplis jusqu'où en est le colis. La pastille
     nomme l'étape ; la barre dit le chemin parcouru et celui qui
     reste — c'est ce qu'on veut savoir d'un coup d'œil dans une liste,
     sans ouvrir le reçu.

     Rien avant le paiement : il n'y a alors aucun chemin à montrer, et
     une barre vide sous une commande impayée se lirait comme une
     panne.

     ELLE PARLE AUSSI À QUI NE LA VOIT PAS. Une barre est une image :
     seule, elle ne dit rien à un lecteur d'écran. D'où le « role » et
     le texte qui l'accompagne — et c'est aussi ce qui la rend lisible
     quand les couleurs passent mal au soleil. */
  function barreSuivi(suivi, c) {
    if (!suivi) return "";
    const paliers = Compte.paliersLivraison();
    const ou = suivi.niveau || 1;
    return (
      '<div class="re-barre" role="img" aria-label="' +
        Utils.echapper((suivi.confirme ? "Reçu confirmé" : suivi.mot) +
          " — étape " + ou + " sur " + paliers.length) + '">' +
        '<div class="re-barre-piste">' +
          paliers.map((p, i) =>
            '<span class="re-barre-pas' + (i < ou ? " fait" : "") +
              (i === ou - 1 ? " ici" : "") + '"></span>').join("") +
        "</div>" +
        '<div class="re-barre-mots" aria-hidden="true">' +
          paliers.map((p, i) =>
            '<span class="' + (i < ou ? "fait" : "") +
              (i === ou - 1 ? " ici" : "") + '">' +
              Utils.echapper(p.court) + "</span>").join("") +
        "</div>" +
        boutonRecu(c || {}) +
      "</div>"
    );
  }

  /**
   * Mes commandes.
   *
   * DEUX SOURCES, ET IL FAUT LES DEUX. La base porte l'historique du
   * COMPTE : il suit le client d'un téléphone à l'autre, et c'est tout
   * l'intérêt d'avoir un compte. Le téléphone, lui, garde ce qu'il a vu
   * passer — y compris les commandes faites sans compte, que la base
   * n'attribue à personne tant que le numéro n'est pas vérifié.
   *
   * On montre donc les deux, la base d'abord. Et hors connexion, on
   * garde ce qu'on a : un écran vide ferait croire à un historique
   * perdu.
   */
  async function mesCommandes(vue) {
    UI.entete({ titre: "Mes commandes", retour: true });

    const local = Panier.mesCommandes();
    const connecte = typeof Compte !== "undefined" && Compte.connecte();

    if (connecte) {
      vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>' +
        "Lecture de vos commandes…</div>";
    }

    let base = [];
    let injoignable = false;
    if (connecte) {
      try {
        base = await Compte.mesCommandes();
      } catch (_) {
        injoignable = true;
      }
    }

    /* La base gagne sur le téléphone : son état est le vrai. Une
       commande payée il y a une heure peut être marquée « en attente »
       dans une copie locale qui n'a pas été rouverte depuis. */
    const vues = new Set(base.map((c) => c.id));
    const liste = base.concat(local.filter((c) => !vues.has(c.id)))
      .sort((a, b) => (b.gardeeLe || 0) - (a.gardeeLe || 0));

    if (!liste.length) {
      vue.innerHTML = UI.vide("boite", "Aucune commande",
        connecte
          ? "Vos commandes s'afficheront ici, sur tous vos téléphones."
          : "Les commandes passées depuis ce téléphone s'afficheront ici.",
        '<a class="btn" href="#/">Parcourir les boutiques</a>') +
        invitation(connecte, local);
      return;
    }

    vue.innerHTML =
      (injoignable
        ? '<div class="note-hors-ligne">' + UI.icone("wifi", "ic-sm") +
          "Hors connexion : voici ce que garde ce téléphone. Vos autres commandes " +
          "reviendront dès que la connexion revient.</div>"
        : "") +
      liste.map(resumeHtml).join("") +
      invitation(connecte, local.filter((c) => !vues.has(c.id)));

    brancherRecus(vue, liste);
  }

  /**
   * L'invitation qui va avec la situation du client, et rien d'autre.
   *
   * Sans compte : en créer un. Avec un compte mais un numéro non
   * vérifié, et des commandes qui ne vivent que sur ce téléphone : les
   * rattacher. Et quand il n'y a rien à proposer, on ne propose rien —
   * une invitation qui revient sans raison devient du décor.
   */
  function invitation(connecte, orphelines) {
    if (!connecte) {
      return '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("compte", "ic-sm") +
          " Retrouvez-les partout</div>" +
        '<p class="aide" style="margin:0 0 10px">Sans compte, cet historique vit sur ce ' +
          "téléphone seulement : changez d'appareil, et il disparaît.</p>" +
        '<a class="btn btn-clair" href="#/connexion">' + UI.icone("compte") +
          "Créer mon compte</a>" +
      "</div>";
    }
    if (!orphelines.length) return "";
    const moi = Compte.moi();
    if (moi && moi.tel_verifie) return "";
    return '<div class="carte">' +
      '<div class="carte-titre">' + UI.icone("telephone", "ic-sm") +
        " " + orphelines.length + " commande" + (orphelines.length > 1 ? "s" : "") +
        " sur ce téléphone seulement</div>" +
      '<p class="aide" style="margin:0 0 10px">Vérifiez votre numéro : les commandes ' +
        "passées avec lui rejoindront votre compte, et vous les retrouverez sur " +
        "n'importe quel téléphone.</p>" +
      '<a class="btn btn-clair" href="#/compte">' + UI.icone("telephone") +
        "Vérifier mon numéro</a>" +
    "</div>";
  }

  return { afficher, commander, recu, mesCommandes };
})();
