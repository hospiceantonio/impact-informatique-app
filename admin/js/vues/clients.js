/* =========================================================
   Fiches clients — retrouver quelqu'un, et voir ce qu'il a
   commandé.

   Un client appelle : « j'ai commandé mardi, rien n'est
   arrivé ». Sans cet écran, il fallait parcourir les commandes
   une à une en espérant tomber sur son numéro.

   RÉSERVÉ À L'ENSEIGNE, et c'est délibéré. Une boutique voit
   déjà le nom et le numéro sur SES commandes ; lui ouvrir la
   liste entière, ce serait lui remettre le fichier clients de
   toutes les autres. La base rend zéro ligne à qui n'y a pas
   droit — masquer l'écran n'est ici qu'une politesse.

   ON NE MODIFIE RIEN D'ICI. Un compte se corrige depuis le
   compte lui-même : c'est le client qui change son nom, son
   numéro ou son adresse. L'enseigne regarde, appelle, et
   tranche un litige avec les commandes sous les yeux.
   ========================================================= */
const VueClients = (() => {

  /* La recherche part au repos après une courte pause : on ne veut pas
     une requête par lettre tapée. */
  const PAUSE_FRAPPE = 350;

  let recherche = "";
  let minuteur = null;

  /* Les classes viennent de la feuille de style de l'application : en
     inventer une ici donnerait un badge sans couleur, et on ne le verrait
     qu'à l'écran. */
  const ETATS = {
    payee: { mot: "Payée", classe: "badge-ok" },
    a_payer: { mot: "À payer", classe: "badge-commande" },
    echouee: { mot: "Échouée", classe: "badge-rupture" },
    annulee: { mot: "Annulée", classe: "badge-annulee" },
  };

  const telComplet = (c) => (c.tel ? "+" + c.indicatif + " " + c.tel : "");

  /** Ce que le compte a demandé à BIZZOO, s'il a demandé quelque chose. */
  function mentionRevendeur(c) {
    if (c.revendeurEtat === "validee") return "Revendeur";
    if (c.revendeurEtat === "en_attente") return "Revendeur — en attente";
    if (c.revendeurEtat === "refusee") return "Revendeur — refusé";
    return "";
  }

  /* ---------- La liste ---------- */

  function htmlLigne(c, devise) {
    const mention = mentionRevendeur(c);
    return (
      '<a class="carte cl-ligne" href="#/client/' + Utils.echapper(c.id) + '">' +
        '<div class="cl-ligne-haut">' +
          '<span class="cl-nom">' + UI.icone("personne", "ic-sm") +
            Utils.echapper(c.nom || "(sans nom)") + "</span>" +
          (c.telVerifie
            ? '<span class="cl-verifie" title="Numéro vérifié par SMS">' +
                UI.icone("check", "ic-sm") + "</span>"
            : "") +
        "</div>" +
        '<div class="cl-ligne-bas">' +
          "<span>" + Utils.echapper(telComplet(c) || "aucun numéro") + "</span>" +
          (mention ? '<span class="cl-mention">' + Utils.echapper(mention) + "</span>" : "") +
        "</div>" +
        '<div class="cl-chiffres">' +
          "<span>" + c.commandes + " commande" + (c.commandes > 1 ? "s" : "") + "</span>" +
          "<span>" + c.payees + " payée" + (c.payees > 1 ? "s" : "") + "</span>" +
          "<strong>" + Utils.echapper(Utils.fmtMontant(c.totalPaye, devise)) + "</strong>" +
        "</div>" +
      "</a>"
    );
  }

  async function afficher(vue) {
    const devise = Store.lireReglages().devise;

    UI.entete({ titre: "Fiches clients",
      sous: "Retrouver quelqu'un, et ses commandes", retour: true });

    vue.innerHTML =
      /* « champ » est le gabarit de l'application : sans lui, l'étiquette
         reste collée à côté du cadre au lieu de se poser au-dessus. */
      '<div class="carte">' +
        '<div class="champ">' +
          '<label for="cl-recherche">Rechercher</label>' +
          '<input id="cl-recherche" type="search" autocomplete="off" ' +
            'placeholder="Un nom, ou un numéro" value="' +
            Utils.echapper(recherche) + '">' +
          '<div class="aide">Le numéro se tape comme on le lit : avec ou sans ' +
            "espaces, avec ou sans l'indicatif.</div>" +
        "</div>" +
      "</div>" +
      '<div id="cl-corps"><div class="chargement"><span class="chargement-rond"></span>' +
        "Lecture des comptes…</div></div>";

    const champ = UI.$("#cl-recherche", vue);
    champ.oninput = () => {
      clearTimeout(minuteur);
      minuteur = setTimeout(() => {
        recherche = champ.value.trim();
        charger(vue, devise);
      }, PAUSE_FRAPPE);
    };
    /* Le curseur revient où il était : on tape souvent en regardant
       les résultats défiler. */
    champ.focus();
    champ.setSelectionRange(champ.value.length, champ.value.length);

    await charger(vue, devise);
  }

  async function charger(vue, devise) {
    const corps = UI.$("#cl-corps", vue);
    if (!corps) return;
    let clients;
    try {
      clients = await Store.listerClients(recherche);
    } catch (err) {
      corps.innerHTML =
        '<div class="carte"><div class="carte-titre">Fiches indisponibles</div>' +
        '<p class="aide" style="margin:0">' + Utils.echapper(err.message) +
        "<br>Si les fiches clients viennent d'être mises en place, exécutez le " +
        "fichier supabase/fiche-client.sql.</p></div>";
      return;
    }

    if (!clients.length) {
      corps.innerHTML = recherche
        ? UI.vide("personne", "Personne à ce nom ni à ce numéro",
            "Essayez avec moins de caractères : la recherche cherche un morceau, " +
            "pas le mot exact.")
        : UI.vide("personne", "Aucun compte client pour l'instant",
            "Les comptes apparaissent ici dès qu'un client s'inscrit dans " +
            "l'application BIZZOO.");
      return;
    }

    corps.innerHTML =
      '<div class="titre-section">' + clients.length +
        " compte" + (clients.length > 1 ? "s" : "") +
        (clients.length >= 200 ? " (les 200 plus récents)" : "") + "</div>" +
      clients.map((c) => htmlLigne(c, devise)).join("");
  }

  /* ---------- La fiche ---------- */

  function htmlCommande(v, devise) {
    const etat = ETATS[v.etat] || ETATS.a_payer;
    return (
      '<div class="carte cl-cmd">' +
        '<div class="cl-cmd-haut">' +
          "<div>" +
            '<strong>' + Utils.echapper(v.numero || v.id) + "</strong>" +
            '<div class="aide">' + Utils.echapper(Utils.fmtDateHeure(v.creeLe)) +
              (v.boutiques ? " — " + Utils.echapper(v.boutiques) : "") + "</div>" +
          "</div>" +
          '<span class="badge ' + etat.classe + '">' + Utils.echapper(etat.mot) + "</span>" +
        "</div>" +
        '<div class="cl-cmd-bas">' +
          "<span>" + v.articles + " ligne" + (v.articles > 1 ? "s" : "") + "</span>" +
          (v.revendeur ? '<span class="cl-mention">Prix revendeur</span>' : "") +
          "<strong>" + Utils.echapper(Utils.fmtMontant(v.total, devise)) + "</strong>" +
        "</div>" +
        /* Une commande d'avant le compte : la base la reconnaît au numéro
           vérifié, mais elle ne portera le compte qu'au prochain passage
           du client dans « Mes commandes ». Le dire évite de croire à une
           anomalie. */
        (v.rattachee ? "" :
          '<div class="aide" style="margin:8px 0 0">Passée avant la création du ' +
          "compte. Elle s'y rattachera d'elle-même à sa prochaine ouverture de " +
          "l'application.</div>") +
      "</div>"
    );
  }

  /** Où se trouve son commerce, s'il en a déclaré un. */
  function blocCommerce(c) {
    if (c.revendeurEtat === "aucune") return "";
    const situe = c.revendeurLatitude !== null && c.revendeurLongitude !== null;
    if (!c.revendeurAdresse && !situe) return "";
    const carte = situe
      ? "https://www.google.com/maps/search/?api=1&query=" +
        c.revendeurLatitude + "," + c.revendeurLongitude
      : "";
    return (
      '<div class="rv-ou">' +
        UI.icone("carte", "ic-sm") +
        "<div>" +
          (c.revendeurAdresse
            ? Utils.echapper(c.revendeurAdresse)
            : "Position relevée, sans adresse écrite") +
          (situe
            ? '<div><a href="' + Utils.echapper(carte) + '" target="_blank" ' +
                'rel="noopener">Ouvrir la carte</a></div>'
            : "") +
        "</div>" +
      "</div>"
    );
  }

  async function fiche(vue, id) {
    const devise = Store.lireReglages().devise;

    UI.entete({ titre: "Fiche client", sous: "", retour: true });
    vue.innerHTML =
      '<div class="chargement"><span class="chargement-rond"></span>' +
      "Lecture de la fiche…</div>";

    let c, commandes;
    try {
      c = await Store.lireClient(id);
      /* La fiche d'abord : sans elle, les commandes n'ont rien à
         illustrer, et l'écran doit dire pourquoi il est vide. */
      commandes = c ? await Store.commandesDuClient(id) : [];
    } catch (err) {
      vue.innerHTML =
        '<div class="carte"><div class="carte-titre">Fiche indisponible</div>' +
        '<p class="aide" style="margin:0">' + Utils.echapper(err.message) + "</p></div>";
      return;
    }

    if (!c) {
      vue.innerHTML = UI.vide("personne", "Ce compte n'existe plus",
        "Il a peut-être été supprimé depuis. Revenez à la liste pour en " +
        "chercher un autre.");
      return;
    }

    UI.entete({ titre: c.nom || "(sans nom)",
      sous: telComplet(c) || "aucun numéro", retour: true });

    const mention = mentionRevendeur(c);
    const tel = telComplet(c);

    vue.innerHTML =
      '<div class="carte cl-fiche">' +
        '<div class="cl-contact">' +
          (tel
            ? '<a href="tel:+' + Utils.echapper(c.indicatif + c.tel) + '">' +
              UI.icone("tel", "ic-sm") + Utils.echapper(tel) +
              (c.telVerifie ? " — vérifié" : " — non vérifié") + "</a>"
            : '<span class="aide">Aucun numéro</span>') +
          (c.email
            ? '<a href="mailto:' + Utils.echapper(c.email) + '">' +
              UI.icone("lien", "ic-sm") + Utils.echapper(c.email) + "</a>"
            : "") +
        "</div>" +
        (c.adresse
          ? '<div class="aide" style="margin:0 0 10px">' + UI.icone("carte", "ic-sm") +
            " " + Utils.echapper(c.adresse) + "</div>"
          : "") +
        (mention ? '<div class="cl-mention">' + Utils.echapper(mention) + "</div>" : "") +
        blocCommerce(c) +
        '<div class="aide" style="margin:10px 0 0">Compte ouvert le ' +
          Utils.echapper(Utils.fmtDateHeure(c.creeLe)) + ".</div>" +
      "</div>" +

      '<div class="carte carte-publier st-resume">' +
        '<div class="st-resume-grand">' +
          "<small>Ce qu'il a dépensé</small>" +
          "<strong>" + Utils.echapper(Utils.fmtMontant(c.totalPaye, devise)) + "</strong>" +
        "</div>" +
        '<div class="st-resume-detail deux">' +
          "<div><small>Commandes</small><span>" + c.commandes + "</span></div>" +
          "<div><small>Payées</small><span>" + c.payees + "</span></div>" +
        "</div>" +
      "</div>" +

      (commandes.length
        ? '<div class="titre-section">Ses commandes</div>' +
          commandes.map((v) => htmlCommande(v, devise)).join("")
        : UI.vide("boite", "Aucune commande",
            "Ce compte existe, mais rien n'a encore été commandé depuis."));

    /* Ce qui n'est PAS ici, et volontairement : aucun bouton pour
       modifier le compte. Un nom, un numéro et une adresse se corrigent
       depuis le compte du client — la base refuse d'ailleurs à
       l'enseigne de les écrire. */
  }

  return { afficher, fiche };
})();
