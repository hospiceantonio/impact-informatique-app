/* =========================================================
   Mes courses — l'écran du livreur, et le seul qu'il ait.

   Il porte la marchandise, et c'est tout. Ce qu'il lui faut :
   QUOI porter, À QUI, et OÙ. Le numéro du client est
   appelable, l'adresse ouvre la carte.

   UN SEUL MONTANT APPARAÎT ICI : ce qu'il doit ENCAISSER à la
   livraison, la part du reste qui revient à sa boutique depuis
   l'acompte à la commande. Ni le prix des articles, ni le prix
   BIZZOO, ni l'acompte — et ce n'est pas une politesse d'écran :
   la fonction « mes_livraisons() » n'en rend pas d'autre. Une
   règle RLS décide quelles LIGNES on voit et les rend entières —
   seule une fonction peut choisir les colonnes, et c'est pour
   cela que le livreur passe par elle plutôt que par la table.

   LES DEMANDES (3.59.0). Dès qu'une commande est payée, elle est
   proposée à tous ses livreurs possibles — ceux de la boutique, ou
   ceux de BIZZOO pour une livraison groupée. Elles s'affichent en
   tête ; le premier qui touche « Commande reçue » la prend, les autres
   la voient disparaître.

   TROIS GESTES. « Commande reçue » d'abord : le livreur accepte la
   course, et c'est À CE MOMENT que le client reçoit son nom et son
   numéro.
   Puis « Je l'ai prise » et « Je l'ai remise ». Préparer reste à
   la boutique, annuler aussi, et c'est toujours le CLIENT qui
   confirme avoir reçu.

   LA FICHE (3.59.0) est celle de l'alerte : où récupérer le colis,
   où le livrer, le numéro du destinataire, les frais, ce qui est
   déjà payé, ce qui reste à récupérer. Aucun prix d'article.

   PLUS D'ESPÈCES (3.59.0). « Je l'ai remise » ouvre une feuille qui
   MONTRE AU CLIENT le code MoMoPay de BIZZOO et le montant, en grand. Le
   client paie depuis son téléphone et reçoit un SMS avec le numéro de la
   transaction ; le livreur le saisit, et seulement alors le colis se
   remet. L'argent arrive sur le compte de BIZZOO : le livreur n'a rien
   en main, rien à rendre. BIZZOO vérifie chaque transaction (Caisse).
   ========================================================= */
const VueLivraisons = (() => {

  const ETATS = {
    preparee: { mot: "À prendre", classe: "badge-approvisionnement",
                bouton: "Je l'ai prise", vers: "en_livraison" },
    en_livraison: { mot: "En cours", classe: "badge-commande",
                    bouton: "Je l'ai remise", vers: "remise" },
    remise: { mot: "Remise", classe: "badge-ok", bouton: "", vers: "" },
    /* Prise dès le paiement : la boutique prépare encore le colis. */
    nouvelle: { mot: "En préparation", classe: "badge-commande", bouton: "", vers: "" },
    vue: { mot: "En préparation", classe: "badge-commande", bouton: "", vers: "" },
  };
  const EN_PREPARATION = ["nouvelle", "vue"];

  const telComplet = (c) => (c.tel ? "+" + c.indicatif + " " + c.tel : "");
  /* La monnaie de la boutique : « mes_livraisons() » rend le montant, pas
     la devise, et toutes les commandes d'une boutique sont dans la sienne. */
  const montant = (n, devise) =>
    Utils.fmtMontant(n, devise || (Store.lireReglages() || {}).devise || "FCFA");

  const lienCarte = (adresse, lat, lng) =>
    "https://www.google.com/maps/search/?api=1&query=" +
    encodeURIComponent(lat != null && lng != null ? lat + "," + lng : adresse);

  /* Un lieu de la fiche : qui, où (ouvre la carte), et le numéro
     appelable. */
  function htmlLieu(titre, icone, nom, adresse, tel, indicatif, lat, lng, sansAdresse, boutique, whatsapp) {
    const complet = tel ? "+" + indicatif + " " + tel : "";
    return (
      '<div class="lv-lieu">' +
        '<div class="lv-lieu-titre">' + UI.icone(icone, "ic-sm") + Utils.echapper(titre) + "</div>" +
        '<div class="lv-nom">' + Utils.echapper(nom || "(sans nom)") + "</div>" +
        (adresse || (lat != null && lng != null)
          ? '<a class="lv-ou" href="' + lienCarte(adresse, lat, lng) +
            '" target="_blank" rel="noopener">' + UI.icone("carte", "ic-sm") +
            Utils.echapper(adresse || "Voir sur la carte") + "</a>"
          : '<div class="aide">' + Utils.echapper(sansAdresse) + "</div>") +
        (complet
          ? '<a class="lv-tel" href="tel:+' + Utils.echapper(indicatif + tel) + '">' +
            UI.icone("tel", "ic-sm") +
            /* (3.70.0) LE NUMÉRO DE LA BOUTIQUE, nommé comme tel : perdu en
               route, le livreur l'appelle — ou lui écrit sur WhatsApp. */
            (boutique ? "Appeler la boutique : " : "") + Utils.echapper(complet) + "</a>" +
            (boutique
              ? '<a class="lv-tel lv-wa" target="_blank" rel="noopener" href="' +
                Utils.echapper(Utils.lienWhatsApp(whatsapp || tel, "Bonjour, je suis le livreur BIZZOO" +
                  (nom ? " pour " + nom : "") + " : ", indicatif)) + '">' +
                UI.icone("whatsapp", "ic-sm") + "Écrire à la boutique sur WhatsApp</a>"
              : "")
          : boutique
            ? '<div class="aide">Numéro de la boutique non renseigné : appelez BIZZOO.</div>'
            : "") +
      "</div>"
    );
  }

  /* (3.70.0) OÙ RÉCUPÉRER LA COMMANDE, tel que l'équipe l'a saisi dans
     « Faire livrer » : la commande a été prise sur WhatsApp, et c'est
     là qu'on a dit au livreur où passer. Il s'ajoute à la fiche de la
     boutique ; rien pour une commande passée dans l'application. */
  function htmlLieuSaisi(f) {
    const texte = String((f && f.lieu_retrait) || "").trim();
    if (!texte) return "";
    return (
      '<div class="lv-lieu lv-lieu-saisi">' +
        '<div class="lv-lieu-titre">' + UI.icone("magasin", "ic-sm") + "Où récupérer (précisé par BIZZOO)</div>" +
        '<div class="lv-note" style="white-space:pre-line">' + Utils.echapper(texte) + "</div>" +
      "</div>"
    );
  }

  /* Les trois montants de la course. « À récupérer » en tête, c'est ce
     qu'il réclame avant de remettre le colis. */
  const MODES = { especes: "espèces", mobile_money: "MoMoPay" };

  function htmlMontants(c) {
    const f = c.fiche;
    const remise = c.etat === "remise";
    const e = remise && f.encaisse && typeof f.encaisse === "object" ? f.encaisse : null;
    return (
      '<div class="lv-montants">' +
        (e
          ? '<div class="lv-encaisser lv-encaisse" data-lv="encaisse">' + UI.icone("check", "ic-sm") +
              (Number(e.montant) > 0
                ? "Payé : <strong>" + Utils.echapper(montant(e.montant, f.devise)) + "</strong>" +
                  (MODES[e.mode] ? " (" + MODES[e.mode] + ")" : "") +
                  (e.mode === "mobile_money"
                    ? '<span class="lv-rendu">' + (e.transaction
                        ? "Transaction " + Utils.echapper(e.transaction) + " — "
                        : "") + "rien à rendre, l'argent est chez BIZZOO</span>"
                    : '<span class="lv-rendu">' + (e.remis_le
                        ? "Rendu à la boutique le " + Utils.echapper(Utils.fmtDateHeure(e.remis_le))
                        : "À rendre à la boutique") + "</span>")
                : "Rien à payer") + "</div>"
          : f.a_encaisser > 0
          ? '<div class="lv-encaisser' + (remise ? " lv-encaisse" : "") + '" data-lv="a-recuperer">' +
              UI.icone("promo", "ic-sm") + (remise ? "Payé : " : "À payer par MoMoPay : ") +
              "<strong>" + Utils.echapper(montant(f.a_encaisser, f.devise)) + "</strong>" +
              (remise ? "" : '<span class="lv-rendu">Pas d\'espèces : le client paie par MoMoPay.</span>') +
              "</div>"
          : '<div class="lv-encaisser lv-rien" data-lv="a-recuperer">' + UI.icone("check", "ic-sm") +
              "Rien à récupérer : tout est payé.</div>") +
        '<div class="lv-ligne-montant" data-lv="deja-paye">Déjà payé par le client : <strong>' +
          Utils.echapper(montant(f.deja_paye, f.devise)) + "</strong></div>" +
        '<div class="lv-ligne-montant" data-lv="frais">Frais de livraison : <strong>' +
          Utils.echapper(f.frais > 0 ? montant(f.frais, f.devise) : "aucun") + "</strong></div>" +
        /* (3.64.0) Au kilomètre : le véhicule, la distance, et ce qu'il
           touchera une fois toute la commande remise. */
        (f.trajet && typeof f.trajet === "object"
          ? '<div class="lv-ligne-montant" data-lv="trajet">' + UI.icone("voiture", "ic-sm") +
              (f.trajet.vehicule === "tricycle" ? "Tricycle" : "Moto") +
              (f.trajet.distance_km != null
                ? " · " + Utils.echapper(String(f.trajet.distance_km).replace(".", ",")) + " km depuis BIZZOO"
                : "") + "</div>"
          : "") +
        (f.gain != null
          ? '<div class="lv-ligne-montant lv-gain" data-lv="gain">Votre gain : <strong>' +
              Utils.echapper(montant(f.gain, f.devise)) + "</strong></div>"
          : "") +
      "</div>"
    );
  }

  function htmlCourse(c) {
    if (c.fiche) return htmlFiche(c);
    const etat = ETATS[c.etat] || ETATS.preparee;
    const tel = telComplet(c.client);
    return (
      '<div class="carte lv-course" data-commande="' + Utils.echapper(c.commandeId) +
        '" data-boutique="' + Utils.echapper(c.boutiqueId) + '">' +
        '<div class="lv-haut">' +
          "<div>" +
            "<strong>" + Utils.echapper(c.numero || c.commandeId) + "</strong>" +
            '<div class="aide">' + Utils.echapper(c.nomBoutique) + "</div>" +
          "</div>" +
          '<span class="badge ' + etat.classe + '">' + Utils.echapper(etat.mot) + "</span>" +
        "</div>" +

        /* CE QU'IL RÉCLAME À LA PORTE, en tête de la course : c'est la
           première chose qu'il doit savoir avant de sonner. Zéro — tout
           payé en ligne —, on le dit aussi : sinon il demanderait. */
        (c.etat === "remise"
          ? (c.aEncaisser > 0
            ? '<div class="lv-encaisser lv-encaisse">Encaissé à la livraison : <strong>' +
                Utils.echapper(montant(c.aEncaisser)) + "</strong></div>"
            : "")
          : c.aEncaisser > 0
            ? '<div class="lv-encaisser">' + UI.icone("promo", "ic-sm") +
                "À payer par MoMoPay : <strong>" + Utils.echapper(montant(c.aEncaisser)) +
                "</strong></div>"
            : '<div class="lv-encaisser lv-rien">' + UI.icone("check", "ic-sm") +
                "Rien à encaisser : tout est payé.</div>") +

        '<div class="lv-articles">' +
          c.articles.map((a) =>
            "<div>" + Utils.echapper(a.nom || "") +
              (a.code ? ' <span class="code-produit">' + Utils.echapper(a.code) + "</span>" : "") +
              " <strong>× " + (Number(a.quantite) || 1) + "</strong></div>").join("") +
        "</div>" +

        '<div class="lv-client">' +
          '<div class="lv-nom">' + UI.icone("personne", "ic-sm") +
            Utils.echapper(c.client.nom || "(sans nom)") + "</div>" +
          (tel
            ? '<a class="lv-tel" href="tel:+' +
              Utils.echapper(c.client.indicatif + c.client.tel) + '">' +
              UI.icone("tel", "ic-sm") + Utils.echapper(tel) + "</a>"
            : "") +
          (c.client.adresse
            ? '<a class="lv-ou" href="https://www.google.com/maps/search/?api=1&query=' +
              encodeURIComponent(c.client.adresse) + '" target="_blank" rel="noopener">' +
              UI.icone("carte", "ic-sm") + Utils.echapper(c.client.adresse) + "</a>"
            : '<div class="aide">Aucune adresse donnée : appelez le client.</div>') +
          (c.client.note
            ? '<div class="lv-note">' + Utils.echapper(c.client.note) + "</div>"
            : "") +
        "</div>" +

        (etat.bouton
          ? '<button type="button" class="btn lv-avancer" data-vers="' + etat.vers + '">' +
            UI.icone("check") + Utils.echapper(etat.bouton) + "</button>"
          : '<div class="aide" style="margin:10px 0 0">Remise. Le client confirmera ' +
            "la réception depuis son application.</div>") +
      "</div>"
    );
  }

  /* La course avec sa fiche complète (base 3.59.0). */
  function htmlFiche(c) {
    const f = c.fiche;
    const r = f.retrait || {};
    const l = f.livraison || {};
    const aAccepter = !c.recuLe && (c.etat === "preparee" || EN_PREPARATION.includes(c.etat));
    const etat = aAccepter
      ? { mot: "Nouvelle", classe: "badge-nouvelle" }
      : ETATS[c.etat] || ETATS.preparee;
    return (
      '<div class="carte lv-course' + (aAccepter ? " lv-nouvelle" : "") +
        '" data-commande="' + Utils.echapper(c.commandeId) +
        '" data-boutique="' + Utils.echapper(c.boutiqueId) + '">' +
        '<div class="lv-haut">' +
          "<div><strong>" + Utils.echapper(f.numero || c.numero || c.commandeId) + "</strong></div>" +
          '<span class="badge ' + etat.classe + '">' + Utils.echapper(etat.mot) + "</span>" +
        "</div>" +
        htmlMontants(c) +
        htmlLieu("Récupérer le colis", "magasin", r.boutique || c.nomBoutique, r.adresse,
          r.tel, r.indicatif || "229", r.latitude, r.longitude,
          "Adresse non renseignée : appelez la boutique.", true, r.whatsapp) +
        htmlLieuSaisi(f) +
        htmlLieu("Livrer à", "personne", l.nom, l.adresse, l.tel, l.indicatif || "229",
          l.latitude, l.longitude, "Aucune adresse donnée : appelez le destinataire.") +
        (l.note ? '<div class="lv-note">' + Utils.echapper(l.note) + "</div>" : "") +
        '<div class="lv-articles">' +
          c.articles.map((a) =>
            "<div>" + Utils.echapper(a.nom || "") +
              (a.code ? ' <span class="code-produit">' + Utils.echapper(a.code) + "</span>" : "") +
              " <strong>× " + (Number(a.quantite) || 1) + "</strong></div>").join("") +
        "</div>" +
        (aAccepter
          ? '<button type="button" class="btn lv-recu">' + UI.icone("check") + "Commande reçue</button>" +
            '<div class="aide" style="margin:6px 0 0">En touchant « Commande reçue », vous acceptez ' +
            "la course : le client reçoit votre nom et votre numéro.</div>"
          : EN_PREPARATION.includes(c.etat)
            ? '<div class="aide lv-attente" style="margin:10px 0 0">La boutique prépare le colis : ' +
              "vous pourrez le prendre dès qu'il sera prêt.</div>"
          : etat.bouton
            ? '<button type="button" class="btn lv-avancer" data-vers="' + etat.vers + '">' +
              UI.icone("check") + Utils.echapper(etat.bouton) + "</button>"
            : '<div class="aide" style="margin:10px 0 0">Remise. Le client confirmera ' +
              "la réception depuis son application.</div>") +
        /* REFUSER, tant que le colis n'est pas parti avec lui (3.59.0). */
        (c.etat === "preparee" || EN_PREPARATION.includes(c.etat)
          ? '<button type="button" class="btn btn-clair btn-danger-clair lv-refuser">' +
            UI.icone("fermer") + "Refuser la course</button>"
          : "") +
      "</div>"
    );
  }

  /* Une demande ouverte : proposée à plusieurs livreurs, au premier qui
     la prend. Groupée, un lieu de retrait par boutique. */
  function htmlDemande(d) {
    const f = d.fiche;
    const l = f.livraison || {};
    const retraits = Array.isArray(f.retraits) ? f.retraits : [];
    return (
      '<div class="carte lv-course lv-demande" data-commande="' + Utils.echapper(d.commandeId) + '">' +
        '<div class="lv-haut">' +
          "<div><strong>" + Utils.echapper(f.numero || d.numero || d.commandeId) + "</strong>" +
            (f.groupee
              ? '<div class="aide">Livraison groupée : ' + retraits.length + " boutiques</div>"
              : "") +
          "</div>" +
          '<span class="badge badge-nouvelle">Demande</span>' +
        "</div>" +
        htmlMontants({ fiche: f, etat: "preparee" }) +
        retraits.map((r, i) =>
          htmlLieu(retraits.length > 1 ? "Récupérer (" + (i + 1) + "/" + retraits.length + ")"
                                       : "Récupérer le colis",
            "magasin", r.boutique, r.adresse, r.tel, r.indicatif || "229", r.latitude, r.longitude,
            "Adresse non renseignée : appelez la boutique.", true, r.whatsapp)).join("") +
        htmlLieuSaisi(f) +
        htmlLieu("Livrer à", "personne", l.nom, l.adresse, l.tel, l.indicatif || "229",
          l.latitude, l.longitude, "Aucune adresse donnée : appelez le destinataire.") +
        (l.note ? '<div class="lv-note">' + Utils.echapper(l.note) + "</div>" : "") +
        '<button type="button" class="btn lv-prendre">' + UI.icone("check") + "Commande reçue</button>" +
        /* (3.70.0) La course va d'abord au plus proche, puis aux suivants :
           qui tarde la laisse passer. */
        '<div class="aide" style="margin:6px 0 0">Touchez vite « Commande reçue » : sans réponse, ' +
          "elle passe au livreur suivant, puis à tous. Le premier qui la prend la garde, et le client " +
          "reçoit alors votre nom et votre numéro.</div>" +
      "</div>"
    );
  }

  /* Une demande prise par un autre livreur : l'écran se relit (3.59.0). */
  let vueOuverte = null;
  window.addEventListener("bizzoo:courses", () => {
    if (vueOuverte && vueOuverte.isConnected && location.hash === "#/livraisons") afficher(vueOuverte);
  });

  /* LES DEMANDES PARTIES CHEZ UN AUTRE, la dernière heure : « Déjà pris
     par … ». Elles viennent des nouvelles reçues, rien à relire. */
  function htmlDejaPrises() {
    const recentes = Notifs.toutes().filter((n) => n.type === "course_prise" &&
      n.creeLe > Date.now() - 3600000);
    if (!recentes.length) return "";
    return '<div class="carte lv-deja-prises" id="lv-deja-prises">' +
      recentes.map((n) =>
        '<div class="lv-deja-prise">' + UI.icone("voiture", "ic-sm") +
          "<span><strong>" + Utils.echapper(n.titre) + "</strong><br>" +
          Utils.echapper(n.corps) + "</span></div>").join("") +
      "</div>";
  }

  async function afficher(vue) {
    vueOuverte = vue;
    UI.entete({ titre: "Mes courses", sous: "Ce que vous avez à porter",
      accueil: false,
      actions: '<button type="button" class="btn-ic" id="lv-rafraichir" ' +
        'aria-label="Actualiser">' + UI.icone("actualiser") + "</button>" +
        /* (3.64.0) Ses gains : sa part des frais de livraison. */
        '<a class="btn-ic" href="#/gains" aria-label="Mes gains" id="lv-gains">' + UI.icone("promo") + "</a>" +
        '<a class="btn-ic" href="#/compte" aria-label="Mon compte">' +
        UI.icone("personne") + "</a>" });

    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>' +
      "Lecture de vos courses…</div>";

    const rafraichir = UI.$("#lv-rafraichir");
    if (rafraichir) rafraichir.onclick = () => afficher(vue);

    let courses;
    let demandes = [];
    let caisse = null;
    let solde = null;
    try {
      [courses, demandes, caisse, solde] = await Promise.all([Store.mesLivraisons(), Store.coursesProposees(),
        Store.maCaisse(),
        /* Une base d'avant le solde des livreurs : pas de bandeau, rien de cassé. */
        Store.soldeLivreur(null).catch(() => null)]);
      /* La sonnerie suit ce que l'écran montre (3.59.0) : « Commande
         reçue » touchée, l'écran se relit, et elle s'arrête. */
      Notifs.majAlerte(courses, demandes);
      /* Sa position suit, tant qu'une course est en cours (Localiser un livreur). */
      if (typeof SuiviPosition !== "undefined") SuiviPosition.mettreAJour(courses);
      /* (3.70.0) Et, libre ou non, sa position pour la cascade des courses. */
      if (typeof SuiviPosition !== "undefined") SuiviPosition.presence();
    } catch (err) {
      vue.innerHTML =
        '<div class="carte"><div class="carte-titre">Courses indisponibles</div>' +
        '<p class="aide" style="margin:0">' + Utils.echapper(err.message) +
        "<br>Si le rôle livreur vient d'être mis en place, la boutique doit " +
        "exécuter le fichier supabase/role-livreur.sql.</p></div>";
      return;
    }

    /* MA CAISSE : ce qu'il a encaissé et doit encore rendre, à qui. */
    const aRendre = caisse && Number(caisse.a_remettre) > 0
      ? '<div class="carte lv-caisse" id="lv-caisse">' +
          '<div class="lv-caisse-titre">' + UI.icone("promo", "ic-sm") + "Ma caisse : <strong>" +
            Utils.echapper(montant(caisse.a_remettre)) + "</strong> à rendre</div>" +
          (Array.isArray(caisse.boutiques) && caisse.boutiques.length
            ? '<div class="aide">' + caisse.boutiques.map((b) =>
                Utils.echapper((b.boutique || "Boutique") + " : " + montant(b.montant))).join(" · ") + "</div>"
            : "") +
        "</div>"
      : "";

    /* (3.66.0) MON SOLDE, toujours en tête : ce que ses courses lui ont
       rapporté — il ne le cherche plus derrière une icône. */
    const monSolde = solde
      ? '<a class="carte lv-solde" id="lv-solde" href="#/gains">' +
          '<div class="lv-solde-titre">' + UI.icone("promo", "ic-sm") + "Mon solde : <strong id=\"lv-solde-dispo\">" +
            Utils.echapper(montant(solde.disponible)) + "</strong></div>" +
          '<div class="aide">Gagné : ' + Utils.echapper(montant(solde.gagne)) +
            (solde.aVenir > 0 ? " · à venir : " + Utils.echapper(montant(solde.aVenir)) : "") +
            " — voir mes gains ›</div>" +
        "</a>"
      : "";

    if (!courses.length && !demandes.length) {
      if (aRendre || htmlDejaPrises()) {
        vue.innerHTML = monSolde + aRendre + htmlDejaPrises() + UI.vide("voiture", "Aucune course pour l'instant",
          "Dès qu'une commande vous est proposée ou confiée, elle apparaît ici.");
        return;
      }
      vue.innerHTML = monSolde + UI.vide("voiture", "Aucune course pour l'instant",
        "Dès que la boutique vous confie une commande préparée, elle apparaît ici.");
      return;
    }

    /* À prendre d'abord, en cours ensuite, remises en dernier : c'est
       l'ordre dans lequel on travaille. */
    const rang = { preparee: 0, en_livraison: 1, nouvelle: 2, vue: 2, remise: 3 };
    courses.sort((a, b) => (rang[a.etat] ?? 3) - (rang[b.etat] ?? 3) ||
      (a.recuLe ? 1 : 0) - (b.recuLe ? 1 : 0));

    const aFaire = courses.filter((c) => c.etat !== "remise").length;
    vue.innerHTML = monSolde + aRendre + htmlDejaPrises() +
      (demandes.length
        ? '<div class="titre-section" id="lv-demandes">' +
            (demandes.length > 1 ? demandes.length + " demandes de course" : "1 demande de course") +
          "</div>" + demandes.map(htmlDemande).join("")
        : "") +
      '<div class="titre-section">' +
        (aFaire ? aFaire + " course" + (aFaire > 1 ? "s" : "") + " à faire"
                : "Rien à faire pour l'instant") + "</div>" +
      courses.map(htmlCourse).join("");

    for (const b of UI.$$(".lv-prendre", vue)) {
      b.onclick = async () => {
        const carte = b.closest(".lv-demande");
        b.disabled = true;
        try {
          await Store.prendreCourse(carte.dataset.commande);
          UI.toast("La course est à vous : le client a reçu votre nom et votre numéro.");
        } catch (err) {
          UI.toast(err.message, "err");
        }
        afficher(vue);
      };
    }

    for (const b of UI.$$(".lv-refuser", vue)) {
      b.onclick = async () => {
        const carte = b.closest(".lv-course");
        const motif = await UI.demanderTexte({
          titre: "Refuser la course",
          texte: "La boutique et BIZZOO seront prévenus, et la course sera aussitôt " +
            "reproposée aux autres livreurs disponibles.",
          libelle: "Pourquoi ? (facultatif)", bouton: "Refuser la course", danger: true });
        if (motif === null) return;
        b.disabled = true;
        try {
          await Store.refuserCourse(carte.dataset.commande, motif);
          UI.toast("Course annulée : BIZZOO et la boutique sont prévenus.");
          afficher(vue);
        } catch (err) {
          UI.toast(err.message, "err");
          b.disabled = false;
        }
      };
    }

    for (const b of UI.$$(".lv-recu", vue)) {
      b.onclick = async () => {
        const carte = b.closest(".lv-course");
        b.disabled = true;
        try {
          await Store.accepterCourse(carte.dataset.commande, carte.dataset.boutique);
          UI.toast("Course acceptée : le client a reçu votre nom et votre numéro.");
          afficher(vue);
        } catch (err) {
          UI.toast(err.message, "err");
          b.disabled = false;
        }
      };
    }

    for (const b of UI.$$(".lv-avancer", vue)) {
      b.onclick = async () => {
        const carte = b.closest(".lv-course");
        /* « Je l'ai remise » : d'abord ce qu'il a encaissé. */
        if (b.dataset.vers === "remise") {
          const c = courses.find((x) => x.commandeId === carte.dataset.commande &&
            x.boutiqueId === carte.dataset.boutique);
          if (c && c.fiche) { ouvrirRemise(vue, c); return; }
        }
        b.disabled = true;
        try {
          await Store.avancerLivraison(carte.dataset.commande,
            carte.dataset.boutique, b.dataset.vers);
          UI.toast(b.dataset.vers === "remise" ? "Course remise." : "Course prise.");
          afficher(vue);
        } catch (err) {
          UI.toast(err.message, "err");
          b.disabled = false;
        }
      };
    }
  }

  /* La feuille de la remise : le montant reçu, la façon de payer, et un
     motif quand ce n'est pas ce qui était dû. */
  /* LA FEUILLE DE REMISE (3.59.0) : ce qu'on MONTRE AU CLIENT. Le code
     MoMoPay de BIZZOO et le montant, en très grand, pour qu'il les tape
     sur son téléphone. Puis le numéro de la transaction, lu sur le SMS
     qu'il reçoit : sans lui, la base ne laisse pas remettre le colis. */
  function ouvrirRemise(vue, c) {
    const f = c.fiche;
    const du = Math.max(0, Number(f.a_encaisser) || 0);
    const momo = f.momopay && typeof f.momopay === "object" ? f.momopay : {};
    const code = String(momo.code || "").trim();
    const corps = UI.ouvrirFeuille("Remettre « " + (f.numero || c.numero || "") + " »",
      (du > 0
        ? (code
          ? '<div class="lv-momo" id="lv-momo">' +
              '<div class="lv-momo-titre">Paiement MoMoPay — montrez cet écran au client</div>' +
              '<div class="lv-momo-etiquette">Code marchand</div>' +
              '<div class="lv-momo-code" id="lv-momo-code">' + Utils.echapper(code) + "</div>" +
              (momo.nom ? '<div class="lv-momo-nom">' + Utils.echapper(momo.nom) + "</div>" : "") +
              '<div class="lv-momo-etiquette">Montant à payer</div>' +
              '<div class="lv-momo-montant" id="lv-momo-montant">' + Utils.echapper(montant(du, f.devise)) + "</div>" +
            "</div>" +
            '<p class="aide" style="margin:12px 0">Le client paie ce montant à ce code MoMoPay depuis ' +
              "son téléphone, et valide avec son code secret. <strong>Pas d'espèces.</strong> Il reçoit " +
              "un SMS de confirmation : recopiez ici le numéro de la transaction.</p>" +
            '<div class="champ"><label for="lv-transaction">Numéro de la transaction (SMS du client)</label>' +
              '<input id="lv-transaction" autocomplete="off" autocapitalize="characters" maxlength="40" ' +
                'placeholder="Exemple : 1234567890"></div>' +
            '<button type="button" class="btn" id="lv-remettre">' + UI.icone("check") +
              "Paiement reçu — remettre le colis</button>"
          : '<div class="note-attente" id="lv-sans-code">' + UI.icone("alerte", "ic-sm") +
              " Le client doit payer <strong>" + Utils.echapper(montant(du, f.devise)) + "</strong> par " +
              "MoMoPay, mais BIZZOO n'a pas encore enregistré son code MoMoPay. Appelez BIZZOO avant " +
              "de remettre le colis. Pas d'espèces.</div>")
        : '<p class="aide" style="margin:0 0 12px">Rien à payer : tout est réglé.</p>' +
          '<button type="button" class="btn" id="lv-remettre">' + UI.icone("check") + "Colis remis</button>"));

    const bouton = UI.$("#lv-remettre", corps);
    if (!bouton) return;
    bouton.onclick = async () => {
      const champ = UI.$("#lv-transaction", corps);
      const transaction = champ ? champ.value.trim() : "";
      if (du > 0 && transaction.replace(/[^A-Za-z0-9]/g, "").length < 4) {
        UI.toast("Saisissez le numéro de la transaction, lu sur le SMS du client.", "err");
        if (champ) champ.focus();
        return;
      }
      bouton.disabled = true;
      try {
        await Store.remettreCourse(c.commandeId, c.boutiqueId, du, du > 0 ? "mobile_money" : "aucun", transaction);
        UI.fermerFeuille();
        UI.toast(du > 0 ? "Colis remis : " + montant(du, f.devise) + " payés par MoMoPay." : "Colis remis.");
        afficher(vue);
      } catch (err) {
        UI.toast(err.message, "err");
        bouton.disabled = false;
      }
    };
  }

  return { afficher };
})();
