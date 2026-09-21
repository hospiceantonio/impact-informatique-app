/* =========================================================
   Le panneau des notifications, côté client.

   GROUPÉES PAR TYPE, comme demandé : on veut savoir DE QUOI il
   s'agit avant de savoir laquelle. « Trois colis livrés » se
   lit d'un coup ; trois lignes mélangées à six autres, non.

   UN DOIGT, UNE DESTINATION. Toucher une notification la marque
   lue ET mène à l'opération concernée — la commande, pas une
   liste où il faudrait la retrouver. C'est la base qui a posé
   le lien au moment des faits : l'écran ne le devine pas.

   ET ELLES NE S'EFFACENT PAS. Aucune règle de suppression
   n'existe en base, pour personne. Une notification gênante se
   marque lue ; elle ne disparaît pas de l'histoire.
   ========================================================= */
const VueNotifications = (() => {
  const e = Utils.echapper;

  /* Le nom que porte chaque famille à l'écran, et son icône. Un type
     inconnu — une version de l'application plus ancienne que la base —
     retombe sur « Autres » plutôt que de ne rien afficher. */
  const FAMILLES = {
    commande_payee:        { nom: "Paiements",   icone: "check" },
    commande_preparee:     { nom: "Colis prêts", icone: "boite" },
    commande_en_livraison: { nom: "En route",    icone: "voiture" },
    commande_remise:       { nom: "Livrés",      icone: "check" },
    reception_confirmee:   { nom: "Réceptions",  icone: "check" },
    commande_annulee:      { nom: "Annulations", icone: "alerte" },
    course_confiee:        { nom: "Courses",     icone: "voiture" },
  };
  const famille = (type) => FAMILLES[type] || { nom: "Autres", icone: "cloche" };

  function htmlUne(n) {
    return (
      '<a class="notif' + (n.lue ? " notif-lue" : "") + '" href="' +
        e(n.lien || "#/") + '" data-notif="' + e(String(n.id)) + '">' +
        '<span class="notif-rond">' + UI.icone(famille(n.type).icone, "ic-sm") + "</span>" +
        '<span class="notif-corps">' +
          '<span class="notif-titre">' + e(n.titre) + "</span>" +
          (n.corps ? '<span class="notif-texte">' + e(n.corps) + "</span>" : "") +
          '<span class="notif-quand">' + e(Utils.ilYA(n.creeLe)) + "</span>" +
        "</span>" +
        (n.lue ? "" : '<span class="notif-point" aria-hidden="true"></span>') +
      "</a>"
    );
  }

  function htmlListe(liste) {
    if (!liste.length) {
      return UI.vide("cloche", "Rien de neuf",
        "Vous serez prévenu ici dès qu'une de vos commandes avance.");
    }
    /* On groupe SANS perdre l'ordre : les familles sortent dans
       l'ordre de leur notification la plus récente, pas alphabétique —
       ce qui vient d'arriver se lit en premier. */
    const ordre = [];
    const groupes = new Map();
    for (const n of liste) {
      const cle = famille(n.type).nom;
      if (!groupes.has(cle)) { groupes.set(cle, []); ordre.push(cle); }
      groupes.get(cle).push(n);
    }
    return ordre.map((cle) => {
      const groupe = groupes.get(cle);
      const neuves = groupe.filter((n) => !n.lue).length;
      return UI.titreSection(cle + (neuves ? " (" + neuves + ")" : "")) +
        '<div class="notif-groupe">' + groupe.map(htmlUne).join("") + "</div>";
    }).join("");
  }

  function brancher(vue) {
    for (const a of UI.$$("[data-notif]", vue)) {
      a.addEventListener("click", () => {
        /* On ne retient PAS le doigt : le lien fait son travail, et la
           notification se marque lue en chemin. Retenir puis naviguer
           à la main ajouterait une latence qu'on verrait. */
        Notifs.marquerLue(a.dataset.notif);
      });
    }
    const tout = UI.$("#notif-tout-lu", vue);
    if (tout) {
      tout.onclick = async () => {
        tout.disabled = true;
        const combien = await Notifs.toutMarquerLu();
        UI.toast(combien ? combien + " notification" + (combien > 1 ? "s" : "") +
          " marquée" + (combien > 1 ? "s" : "") + " lue" + (combien > 1 ? "s" : "")
          : "Tout était déjà lu.");
        afficher(vue);
      };
    }
    const son = UI.$("#notif-son", vue);
    if (son) {
      son.onchange = () => {
        Son.activer(son.checked);
        if (son.checked) Son.troisBips();
      };
    }
  }

  async function afficher(vue) {
    UI.entete({ titre: "Notifications", retour: true,
      sous: "Où en sont vos commandes" });

    if (!Compte.connecte()) {
      vue.innerHTML = UI.vide("cloche", "Créez un compte pour être prévenu",
        "Sans compte, nous n'avons personne à prévenir quand votre commande avance.") +
        '<a class="btn" href="#/connexion" style="margin-top:14px">Se connecter</a>';
      return;
    }

    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>' +
      "Lecture de vos notifications…</div>";
    await Notifs.recharger();

    const liste = Notifs.toutes();
    const nonLues = liste.filter((n) => !n.lue).length;

    vue.innerHTML =
      (nonLues
        ? '<button type="button" class="btn btn-clair" id="notif-tout-lu" ' +
          'style="margin-bottom:14px">' + UI.icone("check") +
          "Tout marquer lu (" + nonLues + ")</button>"
        : "") +
      htmlListe(liste) +
      /* LE SON SE RÈGLE ICI, et pas dans un écran de réglages qu'on
         n'ouvre jamais : c'est en recevant un bip de trop qu'on veut
         le couper, et c'est ici qu'on arrive alors. */
      '<div class="carte" style="margin-top:18px">' +
        '<label class="adr-case"><input type="checkbox" id="notif-son"' +
          (Son.actif() ? " checked" : "") + "> Trois bips à chaque nouvelle</label>" +
        '<p class="aide" style="margin:8px 0 0">Sur cet appareil seulement. ' +
          "Le son ne part qu'une fois l'application touchée au moins une " +
          "fois — les navigateurs l'exigent, et c'est pour éviter qu'une " +
          "page se mette à sonner toute seule.</p>" +
      "</div>";

    brancher(vue);
  }

  return { afficher };
})();
