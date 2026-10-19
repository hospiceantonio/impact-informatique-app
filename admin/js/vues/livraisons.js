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

   TROIS GESTES. « Reçu » d'abord : le livreur accepte la course,
   et c'est À CE MOMENT que le client reçoit son nom et son numéro.
   Puis « Je l'ai prise » et « Je l'ai remise ». Préparer reste à
   la boutique, annuler aussi, et c'est toujours le CLIENT qui
   confirme avoir reçu.

   LA FICHE (3.59.0) est celle de l'alerte : où récupérer le colis,
   où le livrer, le numéro du destinataire, les frais, ce qui est
   déjà payé, ce qui reste à récupérer. Aucun prix d'article.
   ========================================================= */
const VueLivraisons = (() => {

  const ETATS = {
    preparee: { mot: "À prendre", classe: "badge-approvisionnement",
                bouton: "Je l'ai prise", vers: "en_livraison" },
    en_livraison: { mot: "En cours", classe: "badge-commande",
                    bouton: "Je l'ai remise", vers: "remise" },
    remise: { mot: "Remise", classe: "badge-ok", bouton: "", vers: "" },
  };

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
  function htmlLieu(titre, icone, nom, adresse, tel, indicatif, lat, lng, sansAdresse) {
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
            UI.icone("tel", "ic-sm") + Utils.echapper(complet) + "</a>"
          : "") +
      "</div>"
    );
  }

  /* Les trois montants de la course. « À récupérer » en tête, c'est ce
     qu'il réclame avant de remettre le colis. */
  function htmlMontants(c) {
    const f = c.fiche;
    const remise = c.etat === "remise";
    return (
      '<div class="lv-montants">' +
        (f.a_encaisser > 0
          ? '<div class="lv-encaisser' + (remise ? " lv-encaisse" : "") + '" data-lv="a-recuperer">' +
              UI.icone("promo", "ic-sm") + (remise ? "Récupéré : " : "À récupérer : ") +
              "<strong>" + Utils.echapper(montant(f.a_encaisser, f.devise)) + "</strong></div>"
          : '<div class="lv-encaisser lv-rien" data-lv="a-recuperer">' + UI.icone("check", "ic-sm") +
              "Rien à récupérer : tout est payé.</div>") +
        '<div class="lv-ligne-montant" data-lv="deja-paye">Déjà payé par le client : <strong>' +
          Utils.echapper(montant(f.deja_paye, f.devise)) + "</strong></div>" +
        '<div class="lv-ligne-montant" data-lv="frais">Frais de livraison : <strong>' +
          Utils.echapper(f.frais > 0 ? montant(f.frais, f.devise) : "aucun") + "</strong></div>" +
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
                "À encaisser : <strong>" + Utils.echapper(montant(c.aEncaisser)) +
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
    const aAccepter = !c.recuLe && c.etat === "preparee";
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
          "Adresse non renseignée : appelez la boutique.") +
        htmlLieu("Livrer à", "personne", l.nom, l.adresse, l.tel, l.indicatif || "229",
          null, null, "Aucune adresse donnée : appelez le destinataire.") +
        (l.note ? '<div class="lv-note">' + Utils.echapper(l.note) + "</div>" : "") +
        '<div class="lv-articles">' +
          c.articles.map((a) =>
            "<div>" + Utils.echapper(a.nom || "") +
              (a.code ? ' <span class="code-produit">' + Utils.echapper(a.code) + "</span>" : "") +
              " <strong>× " + (Number(a.quantite) || 1) + "</strong></div>").join("") +
        "</div>" +
        (aAccepter
          ? '<button type="button" class="btn lv-recu">' + UI.icone("check") + "Reçu</button>" +
            '<div class="aide" style="margin:6px 0 0">En touchant « Reçu », vous acceptez la ' +
            "course : le client reçoit votre nom et votre numéro.</div>"
          : etat.bouton
            ? '<button type="button" class="btn lv-avancer" data-vers="' + etat.vers + '">' +
              UI.icone("check") + Utils.echapper(etat.bouton) + "</button>"
            : '<div class="aide" style="margin:10px 0 0">Remise. Le client confirmera ' +
              "la réception depuis son application.</div>") +
      "</div>"
    );
  }

  async function afficher(vue) {
    UI.entete({ titre: "Mes courses", sous: "Ce que vous avez à porter",
      accueil: false,
      actions: '<button type="button" class="btn-ic" id="lv-rafraichir" ' +
        'aria-label="Actualiser">' + UI.icone("actualiser") + "</button>" +
        '<a class="btn-ic" href="#/compte" aria-label="Mon compte">' +
        UI.icone("personne") + "</a>" });

    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>' +
      "Lecture de vos courses…</div>";

    const rafraichir = UI.$("#lv-rafraichir");
    if (rafraichir) rafraichir.onclick = () => afficher(vue);

    let courses;
    try {
      courses = await Store.mesLivraisons();
    } catch (err) {
      vue.innerHTML =
        '<div class="carte"><div class="carte-titre">Courses indisponibles</div>' +
        '<p class="aide" style="margin:0">' + Utils.echapper(err.message) +
        "<br>Si le rôle livreur vient d'être mis en place, la boutique doit " +
        "exécuter le fichier supabase/role-livreur.sql.</p></div>";
      return;
    }

    if (!courses.length) {
      vue.innerHTML = UI.vide("voiture", "Aucune course pour l'instant",
        "Dès que la boutique vous confie une commande préparée, elle apparaît ici.");
      return;
    }

    /* À prendre d'abord, en cours ensuite, remises en dernier : c'est
       l'ordre dans lequel on travaille. */
    const rang = { preparee: 0, en_livraison: 1, remise: 2 };
    courses.sort((a, b) => (rang[a.etat] ?? 3) - (rang[b.etat] ?? 3) ||
      (a.recuLe ? 1 : 0) - (b.recuLe ? 1 : 0));

    const aFaire = courses.filter((c) => c.etat !== "remise").length;
    vue.innerHTML =
      '<div class="titre-section">' +
        (aFaire ? aFaire + " course" + (aFaire > 1 ? "s" : "") + " à faire"
                : "Rien à faire pour l'instant") + "</div>" +
      courses.map(htmlCourse).join("");

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

  return { afficher };
})();
