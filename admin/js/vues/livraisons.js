/* =========================================================
   Mes courses — l'écran du livreur, et le seul qu'il ait.

   Il porte la marchandise, et c'est tout. Ce qu'il lui faut :
   QUOI porter, À QUI, et OÙ. Le numéro du client est
   appelable, l'adresse ouvre la carte.

   AUCUN MONTANT N'APPARAÎT ICI, et ce n'est pas une politesse
   d'écran : la fonction « mes_livraisons() » n'en rend aucun.
   Ni le prix payé, ni le prix BIZZOO. Une règle RLS décide
   quelles LIGNES on voit et les rend entières — seule une
   fonction peut choisir les colonnes, et c'est pour cela que
   le livreur passe par elle plutôt que par la table.

   DEUX GESTES, PAS TROIS. « Je l'ai prise » et « Je l'ai
   remise ». Préparer reste à la boutique, annuler aussi, et
   c'est toujours le CLIENT qui confirme avoir reçu.
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

  function htmlCourse(c) {
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
    courses.sort((a, b) => (rang[a.etat] ?? 3) - (rang[b.etat] ?? 3));

    const aFaire = courses.filter((c) => c.etat !== "remise").length;
    vue.innerHTML =
      '<div class="titre-section">' +
        (aFaire ? aFaire + " course" + (aFaire > 1 ? "s" : "") + " à faire"
                : "Rien à faire pour l'instant") + "</div>" +
      courses.map(htmlCourse).join("");

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
