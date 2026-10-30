/* =========================================================
   Accueil — tableau de bord : publication, aperçu du slider
   (images puis produits mis en avant), derniers produits.
   ========================================================= */
const VueAccueil = (() => {

  async function afficher(vue) {
    const admin = Supabase.estAdmin();
    const enseigne = Supabase.estCompteEnseigne();
    const icone = (href, label, nom) =>
      '<a class="btn-ic" href="' + href + '" aria-label="' + label + '">' + UI.icone(nom) + "</a>";

    /* LE COMPTE DE BIZZOO A SA PROPRE RANGÉE. Ni historique ni comptes :
       la base ne lui en rend rien. Les commandes selon son interrupteur,
       les réglages selon « Les boutiques » — sinon son compte. Les avis
       et les réclamations toujours : il répond pour toutes les boutiques,
       et sans ces icônes il n'aurait aucun chemin vers eux. */
    UI.entete({ accueil: true, actions: enseigne
      ? (Supabase.peutVoirCommandes() ? icone("#/commandes", "Commandes", "boite") : "") +
        /* (3.68.0) « Faire livrer », pour qui en a reçu le droit — même
           sans l'interrupteur « Les commandes ». */
        (Supabase.peutFaireLivrer() ? icone("#/faire-livrer", "Faire livrer une commande WhatsApp", "whatsapp") : "") +
        icone("#/avis", "Avis des clients", "etoile") +
        icone("#/sav", "Réclamations", "alerte") +
        (admin ? icone("#/reglages", "Réglages", "reglages")
               : icone("#/compte", "Mon compte", "personne"))
      : admin
      ? '<a class="btn-ic" href="#/commandes" aria-label="Commandes">' + UI.icone("boite") + "</a>" +
        '<a class="btn-ic" href="#/historique" aria-label="Historique">' + UI.icone("horloge") + "</a>" +
        '<a class="btn-ic" href="#/comptes" aria-label="Comptes">' + UI.icone("equipe") + "</a>" +
        '<a class="btn-ic" href="#/reglages" aria-label="Réglages">' + UI.icone("reglages") + "</a>"
      : '<a class="btn-ic" href="#/commandes" aria-label="Commandes">' + UI.icone("boite") + "</a>" +
        /* Le modérateur n'a ni les réglages ni la carte d'accueil de
           l'enseigne : sans cette icône, il n'aurait aucun chemin vers
           les avis de sa boutique une fois la file vide. */
        '<a class="btn-ic" href="#/avis" aria-label="Avis des clients">' + UI.icone("etoile") + "</a>" +
        '<a class="btn-ic" href="#/sav" aria-label="Réclamations">' + UI.icone("alerte") + "</a>" +
        '<a class="btn-ic" href="#/compte" aria-label="Mon compte">' + UI.icone("personne") + "</a>" });

    const [stats, slides, produits, demandes, commandes, revendeurs, avis, sav] = await Promise.all([
      Store.statistiques(),
      admin ? Store.listerSlides().catch(() => []) : Promise.resolve([]),
      Store.listerProduits(),
      /* Les demandes de validation. La table peut ne pas exister encore
         — le SQL n'a peut-être pas été exécuté : l'accueil ne doit pas
         tomber pour autant. */
      admin ? Store.listerDemandes().catch(() => []) : Promise.resolve([]),
      /* Les commandes payées qui attendent d'être préparées. Même
         prudence : une base d'avant les achats intégrés n'a pas la table. */
      Store.commandesEnAttente().catch(() => 0),
      /* Les commerçants qui demandent à acheter au prix BIZZOO. Eux
         aussi attendent une réponse, et cette réponse n'appartient
         qu'à l'enseigne. */
      Supabase.estSuper() || Supabase.estAdminBizzoo()
        ? Store.listerRevendeurs("en_attente").catch(() => [])
        : Promise.resolve([]),
      /* Les avis des clients. Un avis sans réponse est un client qui
         attend, et c'est ce que liront les clients suivants. */
      Store.listerAvis(100).catch(() => []),
      /* Les réclamations. Un client qui attend une réponse depuis deux
         jours peut déjà saisir BIZZOO : rien ne doit passer avant. */
      Store.listerReclamations(100).catch(() => []),
    ]);
    const enAttente = demandes.filter((d) => d.etat === "en_attente");

    let html = "";

    /* ---- Les commandes qui attendent ----
       C'est le message que la boutique reçoit dans son compte : un
       client a payé, il attend sa marchandise. Rien ne doit passer
       avant à l'écran. */
    if (commandes) {
      html +=
        '<a class="carte carte-commandes" href="#/commandes">' +
          '<div class="carte-titre">' + UI.icone("boite", "ic-sm") + " " +
            commandes + " commande" + (commandes > 1 ? "s" : "") + " payée" +
            (commandes > 1 ? "s" : "") + " à préparer</div>" +
          '<p class="aide" style="margin:0">Un client a réglé sa commande et attend. ' +
            "Touchez pour voir ce qu'il faut préparer et ses coordonnées.</p>" +
        "</a>";
    }

    /* ---- Ce qui attend une décision ----
       Au superadministrateur, ce que les boutiques demandent ; à
       l'administrateur d'une boutique, où en sont ses propres demandes.
       Une demande oubliée, c'est une boutique qui attend. */
    if (enAttente.length) {
      const combien = enAttente.length + " demande" + (enAttente.length > 1 ? "s" : "");
      html += Supabase.estSuper()
        ? '<a class="carte carte-publier" href="#/validations">' +
            '<div class="carte-titre">' + UI.icone("alerte", "ic-sm") + " " +
              combien + " en attente</div>" +
            '<p class="aide" style="margin:0">Des boutiques veulent changer leur nom, ' +
              "leur logo, leurs contacts ou leur slider. Touchez pour voir et trancher.</p>" +
          "</a>"
        : '<div class="note-attente">' + UI.icone("horloge", "ic-sm") + " " +
            combien + " en attente de validation par BIZZOO : " +
            Utils.echapper(enAttente.map((d) => d.objet).join(" · ")) + "</div>";
    }

    /* ---- Les commerçants qui veulent le prix BIZZOO ----
       Une demande de compte revendeur n'attend pas une boutique : elle
       attend l'enseigne, et personne d'autre ne la verra. */
    /* ---- L'administrateur de BIZZOO : livreurs et revendeurs (3.59.0) ----
       Ses deux écrans, à portée de main : il crée les livreurs et les
       revendeurs, et valide les demandes. */
    if (Supabase.estAdminBizzoo() && !Supabase.estSuper()) {
      html +=
        '<div class="carte" id="ac-livreurs-revendeurs">' +
          '<div class="carte-titre">' + UI.icone("voiture", "ic-sm") + " Livreurs, revendeurs, modérateurs</div>" +
          '<p class="aide" style="margin:0 0 10px">Créez les comptes des livreurs et des ' +
            "revendeurs, validez les demandes de compte revendeur — et créez des modérateurs, " +
            "que le superadministrateur validera.</p>" +
          '<div class="btn-rangee">' +
            '<a class="btn btn-clair" href="#/livreurs">' + UI.icone("voiture") + "Les livreurs</a>" +
            '<a class="btn btn-clair" href="#/revendeurs">' + UI.icone("personne") + "Les revendeurs</a>" +
            /* (3.63.0) Demande du CEO : il crée les modérateurs. */
            '<a class="btn btn-clair" href="#/comptes" id="ac-moderateurs">' + UI.icone("equipe") +
              "Les modérateurs</a>" +
          "</div>" +
        "</div>";
    }
    /* ---- L'administrateur d'une boutique : ses livreurs, et les
       revendeurs qu'il peut créer (3.59.0) ---- */
    if (Supabase.estAdmin() && !Supabase.estSuper() && !Supabase.estCompteEnseigne()) {
      html +=
        '<div class="carte" id="ac-livreurs-revendeurs">' +
          '<div class="carte-titre">' + UI.icone("voiture", "ic-sm") + " Livreurs et revendeurs</div>" +
          '<p class="aide" style="margin:0 0 10px">Créez les livreurs de votre boutique et des ' +
            "comptes revendeurs ; BIZZOO valide les revendeurs.</p>" +
          '<div class="btn-rangee">' +
            '<a class="btn btn-clair" href="#/livreurs">' + UI.icone("voiture") + "Les livreurs</a>" +
            '<a class="btn btn-clair" href="#/revendeurs">' + UI.icone("personne") + "Créer un revendeur</a>" +
          "</div>" +
        "</div>";
    }
    if (revendeurs.length) {
      const combien = revendeurs.length + " demande" + (revendeurs.length > 1 ? "s" : "");
      html +=
        '<a class="carte carte-publier" href="#/revendeurs">' +
          '<div class="carte-titre">' + UI.icone("personne", "ic-sm") + " " +
            combien + " de compte revendeur</div>" +
          '<p class="aide" style="margin:0">' +
            Utils.echapper(revendeurs.slice(0, 3).map((r) => r.nom || r.email)
              .filter(Boolean).join(" · ")) +
            (revendeurs.length > 3 ? " …" : "") +
            " — un compte validé achète au prix BIZZOO. Touchez pour trancher.</p>" +
        "</a>";
    }

    /* ---- Les réclamations qui attendent ----
       Avant les avis, avant tout le reste après les commandes : un
       client qui réclame a déjà payé, et il attend. Passé 48 heures
       sans réponse, il peut saisir BIZZOO. */
    const savOuverts = sav.filter((r) => r.etat === "ouverte");
    const savRecours = sav.filter((r) => r.etat === "escaladee");
    if (savOuverts.length || savRecours.length) {
      html +=
        '<a class="carte carte-publier" href="#/sav">' +
          '<div class="carte-titre">' + UI.icone("alerte", "ic-sm") + " " +
            (savRecours.length
              ? savRecours.length + " recours chez BIZZOO"
              : savOuverts.length + " réclamation" +
                (savOuverts.length > 1 ? "s" : "") + " sans réponse") + "</div>" +
          '<p class="aide" style="margin:0">' +
            (savRecours.length && savOuverts.length
              ? "Et " + savOuverts.length + " sans réponse. "
              : "") +
            "Répondez sous 48 heures : passé ce délai, le client peut demander " +
            "à BIZZOO de trancher.</p>" +
        "</a>";
    }

    /* ---- Les avis auxquels personne n'a répondu ----
       Répondre, même à un mauvais avis, se voit : c'est ce que lisent
       les clients suivants. Un avis laissé sans réponse aussi. */
    const sansReponse = avis.filter((a) => !a.reponse && !a.masque);
    if (sansReponse.length) {
      html +=
        '<a class="carte carte-publier" href="#/avis">' +
          '<div class="carte-titre">' + UI.icone("etoile", "ic-sm") + " " +
            sansReponse.length + " avis sans réponse</div>" +
          '<p class="aide" style="margin:0">' +
            Utils.echapper(sansReponse.slice(0, 2)
              .map((a) => (a.auteur || "Un client") + " : " + a.note + "/5").join(" · ")) +
            (sansReponse.length > 2 ? " …" : "") +
            " — votre réponse s'affiche sous l'avis, pour tout le monde.</p>" +
        "</a>";
    }

    /* ---- La boutique sur laquelle on travaille ----
       Avec plusieurs secteurs, il faut savoir en un coup d'œil où l'on
       est : tout ce qui suit ne concerne que cette boutique-là. */
    const courante = Store.boutiqueCourante();
    if (courante) {
      /* Le super administrateur et le compte de BIZZOO passent d'une
         boutique à l'autre ; les autres restent dans la leur. */
      const peutChanger = Supabase.peutChangerDeBoutique();
      html +=
        '<a class="carte carte-boutique-active"' +
          (peutChanger ? ' href="#/boutiques"' : "") + ">" +
          VueBoutiques.pastille(courante) +
          "<span><strong>" + Utils.echapper(courante.nomBoutique) + "</strong><br>" +
          "<small>" + (peutChanger
            ? "Boutique ouverte — touchez pour en changer"
            : Utils.echapper(courante.secteur || "Votre boutique")) +
          (courante.actif ? "" : " · fermée aux clients") + "</small></span>" +
          (peutChanger ? UI.icone("chevron", "ic-sm") : "") +
        "</a>";
      /* Le live TikTok : la place, remplie une fois l'écran posé. */
      if (admin) html += '<div class="carte carte-live" id="carte-live" hidden></div>';
    }

    /* ---- Le stock ----
       Chaque vente payée se décompte toute seule : ce qui reste à voir,
       c'est ce qui manque — avant que le client ne le voie. La carte se
       fait pressante quand il y a une rupture ou un stock bas, et reste
       un simple chemin vers l'écran Stock quand tout va bien. */
    const ruptures = produits.filter((p) => Store.statut(p) === "rupture").length;
    const stockBas = produits.filter((p) =>
      Store.statut(p) === "disponible" && p.stock <= Store.STOCK_BAS).length;
    if (produits.length) {
      const pressant = ruptures || stockBas;
      const quoi = [
        ruptures ? ruptures + " produit" + (ruptures > 1 ? "s" : "") + " en rupture" : "",
        stockBas ? stockBas + " bientôt épuisé" + (stockBas > 1 ? "s" : "") : "",
      ].filter(Boolean).join(" · ");
      html +=
        '<a class="carte' + (pressant ? " carte-publier" : "") + '" id="carte-stock" href="#/stock' +
          (ruptures ? "?filtre=rupture" : stockBas ? "?filtre=bas" : "") + '">' +
          '<div class="carte-titre">' + UI.icone(pressant ? "alerte" : "boite", "ic-sm") + " " +
            (pressant ? quoi : "Stock de la boutique") + "</div>" +
          '<p class="aide" style="margin:0">' +
            (pressant
              ? "Chaque vente payée se décompte toute seule. Touchez pour voir ce qui manque" +
                (Supabase.peutModifierProduits() ? " et saisir un arrivage." : ".")
              : "Tout est en stock. Chaque vente payée se décompte toute seule" +
                (Supabase.peutModifierProduits()
                  ? " — touchez pour saisir un arrivage ou corriger un chiffre."
                  : ".")) +
          "</p>" +
        "</a>";
    }

    /* ---- Les ventes encaissées ----
       La question qu'on se pose en ouvrant l'application. Mais pas la
       même selon qui ouvre : l'enseigne veut savoir ce qu'elle garde,
       une boutique ce qui lui revient. Deux écrans, deux fonctions en
       base — ici on n'annonce à chacun que le sien.

       ET AU COMPTE DE BIZZOO, AUCUN : la première fonction est au
       superadministrateur seul, la seconde part de la boutique du
       compte, et il n'en a pas. La carte l'aurait mené à un refus. */
    if (!enseigne) html += Supabase.estSuper()
      ? '<a class="carte carte-benefice" href="#/statistiques">' +
          '<div class="carte-titre">' + UI.icone("promo", "ic-sm") +
            " Ce que rapportent les boutiques</div>" +
          '<p class="aide" style="margin:0">Les ventes encaissées, produit par produit : ' +
            "prix BIZZOO, marge, prix de vente et bénéfice. Filtrable par boutique et par " +
            "période.</p>" +
        "</a>"
      : '<a class="carte carte-benefice" href="#/statistiques">' +
          '<div class="carte-titre">' + UI.icone("promo", "ic-sm") +
            " Ce que vend votre boutique</div>" +
          '<p class="aide" style="margin:0">Vos ventes encaissées, produit par produit, ' +
            "et ce qui vous revient au prix BIZZOO. Sur 7 jours, 30 jours, le mois ou " +
            "depuis le début.</p>" +
        "</a>";

    /* ---- La caisse des livreurs (3.59.0) ----
       L'argent que les livreurs encaissent à la livraison, jusqu'à ce
       qu'ils le rendent. */
    if (Supabase.tientLaCaisse()) {
      html +=
        '<a class="carte" href="#/caisse" id="ac-caisse">' +
          '<div class="carte-titre">' + UI.icone("promo", "ic-sm") +
            " Caisse des livreurs</div>" +
          '<p class="aide" style="margin:0">Le reste payé à la livraison : ce que chaque ' +
            "livreur a encaissé, et ce qu'il doit encore vous rendre.</p>" +
        "</a>";
    }

    /* ---- Le solde de la boutique, et les reversements (3.59.0) ---- */
    if (Supabase.tientLaCaisse() && Store.boutiqueCourante() && !Supabase.estSuper()) {
      html +=
        '<a class="carte" href="#/solde" id="ac-solde">' +
          '<div class="carte-titre">' + UI.icone("promo", "ic-sm") + " Solde de la boutique</div>" +
          '<p class="aide" style="margin:0">Vos ventes livrées, commission de BIZZOO déduite, et ' +
            "vos demandes de reversement.</p>" +
        "</a>";
    }
    if (Supabase.estSuper()) {
      html +=
        '<a class="carte" href="#/reversements" id="ac-reversements">' +
          '<div class="carte-titre">' + UI.icone("promo", "ic-sm") + " Reversements aux boutiques</div>" +
          '<p class="aide" style="margin:0">Les demandes des boutiques : envoyez l\'argent, puis ' +
            "validez avec la référence de la transaction.</p>" +
        "</a>" +
        (Store.boutiqueCourante()
          ? '<a class="carte" href="#/solde" id="ac-solde">' +
              '<div class="carte-titre">' + UI.icone("promo", "ic-sm") + " Solde de « " +
                Utils.echapper(Store.boutiqueCourante().nomBoutique) + " »</div>" +
              '<p class="aide" style="margin:0">Ce que BIZZOO doit à cette boutique.</p>' +
            "</a>"
          : "") +
        /* (3.70.0) Les vendeurs des boutiques à vendeurs multiples. */
        (Store.connaitVendeurs()
          ? '<a class="carte" href="#/vendeurs" id="ac-vendeurs">' +
              '<div class="carte-titre">' + UI.icone("magasin", "ic-sm") + " Vendeurs</div>" +
              '<p class="aide" style="margin:0">Les vendeurs des boutiques à vendeurs multiples : leurs ' +
                "ventes, leur part, la commission de BIZZOO, l'historique des parts.</p>" +
            "</a>"
          : "");
    }

    /* ---- Retrouver un client, et suivre l'argent ----
       Deux écrans de l'enseigne seule : une boutique voit déjà ses
       propres acheteurs sur ses commandes, et ses ventes encaissées
       dans « Ce que vend votre boutique ». */
    if (Supabase.estSuper()) {
      html +=
        '<a class="carte" href="#/clients">' +
          '<div class="carte-titre">' + UI.icone("personne", "ic-sm") +
            " Fiches clients</div>" +
          '<p class="aide" style="margin:0">Retrouver quelqu\'un par son nom ou son ' +
            "numéro, et voir ses commandes — celles de son compte, et celles d'avant.</p>" +
        "</a>" +
        '<a class="carte" href="#/versements">' +
          '<div class="carte-titre">' + UI.icone("energie", "ic-sm") +
            " Journal des versements</div>" +
          '<p class="aide" style="margin:0">Ce qui est réellement entré, par ' +
            "opérateur, et les tentatives qui ont raté — une ligne par essai.</p>" +
        "</a>" +
        '<a class="carte" href="#/codes">' +
          '<div class="carte-titre">' + UI.icone("cadeau", "ic-sm") +
            " Codes promo</div>" +
          '<p class="aide" style="margin:0">Une remise sort de votre marge : la ' +
            "boutique touche son prix BIZZOO en entier. Voyez ce que chaque code " +
            "vous coûte.</p>" +
        "</a>";
    }

    /* ---- Chiffres clés ---- */
    html +=
      '<div class="stats">' +
        '<a class="stat" href="#/produits">' +
          '<span class="stat-valeur">' + stats.produits + "</span>" +
          '<span class="stat-label">Produit' + (stats.produits > 1 ? "s" : "") + "</span>" +
        "</a>" +
        '<a class="stat" href="#/categories">' +
          '<span class="stat-valeur">' + stats.categories + "</span>" +
          '<span class="stat-label">Catégorie' + (stats.categories > 1 ? "s" : "") + "</span>" +
        "</a>" +
        (admin
          ? '<a class="stat" href="#/slider">' +
              '<span class="stat-valeur">' + (stats.slides + stats.enAvant) + "</span>" +
              '<span class="stat-label">Slider</span>' +
            "</a>"
          : '<span class="stat">' +
              '<span class="stat-valeur">' + stats.promotions + "</span>" +
              '<span class="stat-label">Promotion' + (stats.promotions > 1 ? "s" : "") + "</span>" +
            "</span>") +
      "</div>";

    /* ---- Catalogue en direct ---- */
    html +=
      '<div class="carte carte-publier">' +
        '<div class="carte-titre">' + UI.icone("nuage", "ic-sm") + " Catalogue en ligne</div>" +
        '<div class="note-ok" style="margin-bottom:0">' + UI.icone("check", "ic-sm") +
          " Vos modifications sont enregistrées directement en ligne : l'application client les affiche immédiatement." +
        "</div>" +
      "</div>";

    /* ---- Slider : les images libres, puis les produits mis en avant ---- */
    const enAvant = produits
      .filter((p) => p.enAvant)
      .sort((a, b) => (a.ordreAvant || 0) - (b.ordreAvant || 0));
    const images = slides.filter((s) => s.actif);
    const ecrans = images.map((s) => ({ apercu: s.apercu, video: s.videoUrl, produit: false }))
      .concat(enAvant.map((p) => ({ apercu: p.vignette, video: "", produit: true })));

    if (admin) {
      html += '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("image", "ic-sm") + " Slider — à la une (" +
          ecrans.length + ")</div>" +
        '<p class="aide" style="margin:-4px 0 12px">' +
          images.length + " écran" + (images.length > 1 ? "s" : "") +
          " puis " + enAvant.length + " produit" + (enAvant.length > 1 ? "s" : "") +
          " mis en avant, dans cet ordre, en haut de l'écran de cette boutique. " +
          "L'accueil de l'application, lui, fait défiler le slider de BIZZOO " +
          "(Réglages → BIZZOO).</p>";

      if (ecrans.length) {
        html += '<div class="slider-apercu">' +
          ecrans.map((e, i) =>
            '<a class="slider-apercu-img" href="#/slider" aria-label="Écran ' + (i + 1) + ' du slider">' +
              (e.video
                ? '<video src="' + Utils.echapper(e.video) + '" muted playsinline preload="metadata"></video>'
                : e.apercu
                  ? '<img src="' + Utils.echapper(e.apercu) + '" alt="">'
                  : '<span class="slider-apercu-vide">' + UI.icone("image", "ic-sm") + "</span>") +
              (e.produit ? '<span class="slide-etiquette slide-etiquette-produit">Produit</span>' : "") +
            "</a>").join("") +
        "</div>";
      } else {
        html += '<p class="aide" style="margin:0 0 12px">Le slider est vide : vos clients ne verront rien à la une.</p>';
      }
      html += '<a class="btn btn-clair" style="margin-top:10px" href="#/slider">' +
        UI.icone("image") + (ecrans.length ? "Gérer le slider" : "Composer le slider") + "</a>" +
      "</div>";
    }

    /* ---- Dernières actions (administrateur) ---- */
    let journal = [];
    /* Le journal ne montre que des lignes de boutique : au compte de
       BIZZOO, la base n'en rend aucune. Inutile de le lui demander. */
    if (admin && !enseigne) {
      try { journal = await Store.lireJournal(4, 0); } catch (_) { /* table pas encore créée */ }
    }
    if (journal.length) {
      html += '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("horloge", "ic-sm") + " Dernières actions</div>" +
        journal.map((e) =>
          '<div class="histo-ligne histo-compact">' +
            '<span class="histo-corps">' +
              '<span class="histo-libelle">' + Utils.echapper(e.libelle) + "</span>" +
              '<span class="histo-details">' + Utils.echapper(Utils.fmtDateHeure(e.date)) +
                (e.utilisateur ? " · " + Utils.echapper(e.utilisateur) : "") + "</span>" +
            "</span>" +
          "</div>").join("") +
        '<a class="btn btn-clair" style="margin-top:10px" href="#/historique">' +
          UI.icone("horloge") + "Voir tout l'historique</a>" +
      "</div>";
    }

    /* ---- Derniers produits ---- */
    html += '<div class="carte">' +
      '<div class="carte-titre">Derniers produits modifiés</div>';
    if (produits.length) {
      const categories = await Store.listerCategories();
      const nomCategorie = (p) => {
        const c = categories.find((x) => x.id === p.categorieId);
        if (!c) return "À CLASSER";
        const sc = (c.sousCategories || []).find((x) => x.id === p.sousCategorieId);
        return sc ? c.nom + " · " + sc.nom : c.nom;
      };
      html += produits.slice(0, 5).map((p) => UI.ligneProduit(p, nomCategorie(p))).join("");
      if (produits.length > 5) {
        html += '<a class="btn btn-clair" style="margin-top:10px" href="#/produits">Voir les ' + produits.length + " produits</a>";
      }
    } else {
      html += UI.vide("boite", "Aucun produit pour l'instant",
        "Ajoutez votre premier produit avec le bouton + en bas de l'écran.");
    }
    html += "</div>";

    vue.innerHTML = html;
    if (courante) remplirLive(vue, courante);
  }

  /* ---------- Le live TikTok ----------
     « Démarrer le live TikTok » : tous les téléphones où BIZZOO est
     installée reçoivent une notification, qui ouvre la page TikTok de la
     boutique. Pendant le live, l'application et le site montrent un
     bandeau « En live ». */
  async function remplirLive(vue, courante) {
    const zone = UI.$("#carte-live", vue);
    if (!zone) return;
    let live = null;
    try { live = await Store.liveEnCours(courante.id); } catch (_) {
      return;   // base d'avant le live : on ne propose rien
    }
    if (!zone.isConnected) return;
    zone.hidden = false;
    const tiktok = String(courante.tiktok || "").trim();
    if (live) {
      const depuis = new Date(live.debut);
      zone.innerHTML =
        '<div class="carte-titre"><span class="live-point"></span> En live sur TikTok</div>' +
        '<p class="aide" style="margin:0 0 12px">Depuis ' +
          Utils.echapper(depuis.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" })) +
          ". Les clients voient le bandeau « En live » dans l'application et sur le site.</p>" +
        '<button type="button" class="btn btn-clair btn-danger-clair" id="live-arreter">' +
          UI.icone("fermer") + "Arrêter le live</button>";
      UI.$("#live-arreter", zone).onclick = async (e) => {
        e.target.disabled = true;
        try {
          await Store.arreterLive(courante.id);
          UI.toast("Live arrêté.");
        } catch (err) { UI.toast(err.message, "err"); }
        remplirLive(vue, courante);
      };
      return;
    }
    zone.innerHTML =
      '<div class="carte-titre">' + UI.icone("video", "ic-sm") + " Live TikTok</div>" +
      (tiktok
        ? '<p class="aide" style="margin:0 0 12px">Vous passez en direct sur TikTok ? Prévenez ' +
            "tous les clients : une notification arrive sur chaque téléphone où BIZZOO est " +
            "installée, et l'ouvrir mène droit à votre page TikTok. Trois lives par jour au " +
            "plus.</p>" +
          '<button type="button" class="btn" id="live-demarrer">' + UI.icone("video") +
            "Démarrer le live TikTok</button>"
        : '<p class="aide" style="margin:0">Ajoutez d\'abord le compte TikTok de la boutique ' +
            'dans <a href="#/reglages">Réglages</a> (réseaux sociaux) : c\'est la page que la ' +
            "notification ouvrira.</p>");
    const bouton = UI.$("#live-demarrer", zone);
    if (!bouton) return;
    bouton.onclick = async () => {
      const sur = await UI.confirmer({
        titre: "Démarrer le live TikTok ?",
        texte: "Tous les clients de BIZZOO vont recevoir « " + courante.nomBoutique +
          " est en live sur TikTok ». Lancez votre live sur TikTok d'abord.",
        bouton: "Prévenir les clients",
      });
      if (!sur) return;
      bouton.disabled = true;
      try {
        const r = await Store.demarrerLive(courante.id);
        UI.toast(r.message || "Live annoncé.", r.push === false && !r.deja ? "alerte" : undefined);
      } catch (err) {
        UI.toast(err.message, "err");
      }
      remplirLive(vue, courante);
    };
  }

  return { afficher };
})();
