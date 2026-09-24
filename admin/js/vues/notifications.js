/* =========================================================
   Le panneau des notifications, côté boutique.

   GROUPÉES PAR TYPE : devant vingt lignes, on veut savoir DE
   QUOI il s'agit avant de savoir laquelle. « Quatre commandes
   payées » se lit d'un coup.

   UN DOIGT, UNE DESTINATION. Toucher une notification la marque
   lue ET ouvre la commande concernée — pas une liste où il
   faudrait la retrouver. C'est la base qui a posé le lien au
   moment des faits.

   ET ELLES NE S'EFFACENT PAS. Aucune règle de suppression
   n'existe en base, pour personne : une notification gênante se
   marque lue, elle ne disparaît pas de l'histoire.
   ========================================================= */
const VueNotifications = (() => {
  const e = Utils.echapper;

  const FAMILLES = {
    commande_payee:        { nom: "Commandes payées",   icone: "chariot" },
    commande_preparee:     { nom: "Colis prêts",        icone: "boite" },
    commande_en_livraison: { nom: "En livraison",       icone: "voiture" },
    commande_remise:       { nom: "Remises au client",  icone: "check" },
    reception_confirmee:   { nom: "Réceptions confirmées", icone: "check" },
    commande_annulee:      { nom: "Annulations",        icone: "alerte" },
    course_confiee:        { nom: "Courses confiées",   icone: "voiture" },
    /* Le stock, que chaque vente payée décompte toute seule. */
    stock_epuise:          { nom: "Ruptures de stock",  icone: "boite" },
    stock_insuffisant:     { nom: "Stock insuffisant",  icone: "alerte" },
    stock_a_verifier:      { nom: "Stock à vérifier",   icone: "alerte" },
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
      return '<div class="carte"><p class="aide" style="margin:0">Rien de neuf. ' +
        "Vous serez prévenu ici dès qu'une commande avance.</p></div>";
    }
    /* On groupe SANS perdre l'ordre : les familles sortent dans l'ordre
       de leur notification la plus récente, pas alphabétique — ce qui
       vient d'arriver se lit en premier. */
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
      return '<div class="carte-titre" style="margin:18px 0 8px">' + e(cle) +
          (neuves ? ' <span class="badge badge-commande">' + neuves + "</span>" : "") +
        "</div>" +
        '<div class="notif-groupe">' + groupe.map(htmlUne).join("") + "</div>";
    }).join("");
  }

  function brancher(vue) {
    for (const a of UI.$$("[data-notif]", vue)) {
      a.addEventListener("click", () => { Notifs.marquerLue(a.dataset.notif); });
    }
    const tout = UI.$("#notif-tout-lu", vue);
    if (tout) {
      tout.onclick = async () => {
        tout.disabled = true;
        const combien = await Notifs.toutMarquerLu();
        UI.toast(combien ? combien + " notification" + (combien > 1 ? "s" : "") +
          " marquée" + (combien > 1 ? "s" : "") + " lue" + (combien > 1 ? "s" : "")
          : "Tout était déjà lu.", "ok");
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
      sous: "Ce qui vient d'arriver" });

    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>' +
      "Lecture…</div>";
    await Notifs.recharger();

    const liste = Notifs.toutes();
    const nonLues = liste.filter((n) => !n.lue).length;

    vue.innerHTML =
      (nonLues
        ? '<button type="button" class="btn btn-clair" id="notif-tout-lu">' +
          UI.icone("check") + "Tout marquer lu (" + nonLues + ")</button>"
        : "") +
      htmlListe(liste) +
      /* LE SON SE RÈGLE ICI, et pas dans un écran de réglages qu'on
         n'ouvre jamais : c'est en recevant un bip de trop qu'on veut le
         couper, et c'est ici qu'on arrive alors. */
      '<div class="carte" style="margin-top:20px">' +
        UI.interrupteur({ id: "notif-son", label: "Trois bips à chaque nouvelle",
          actif: Son.actif(),
          aide: "Sur cet appareil seulement. Le son ne part qu'une fois " +
            "l'application touchée au moins une fois — les navigateurs " +
            "l'exigent, pour éviter qu'une page se mette à sonner seule." }) +
      "</div>";

    brancher(vue);
  }

  return { afficher };
})();
