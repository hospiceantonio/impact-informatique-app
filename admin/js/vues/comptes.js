/* =========================================================
   Comptes — l'équipe de la boutique.

   • afficher()  : la liste et la création de comptes,
                   réservées à l'administrateur ;
   • monCompte() : sa propre fiche (mot de passe, déconnexion),
                   accessible à tout le monde.
   ========================================================= */
const VueComptes = (() => {

  const nomRole = (role) => (Store.ROLES[role] || Store.ROLES.moderateur).nom;

  const nomBoutique = (id) =>
    (Store.lireBoutique(id) || {}).nomBoutique || "boutique à choisir";

  /** Les choix de boutique proposés à un modérateur. */
  /**
   * Les boutiques à confier — et, pour le superadministrateur seul,
   * l'option « BIZZOO ».
   *
   * AUCUNE BOUTIQUE VEUT DIRE TOUTES — et cela veut dire DEUX choses
   * selon le rang. Pour un administrateur ou un modérateur, c'est un
   * compte d'enseigne : il regarde par-dessus toutes les boutiques,
   * dans la limite des interrupteurs qu'on lui laisse. Pour un
   * LIVREUR, c'est un porteur de l'enseigne : toutes les boutiques
   * peuvent lui confier une course, et il ne gagne aucun droit pour
   * autant. Les deux sont beaucoup, et c'est pour cela que seul le
   * superadministrateur peut les donner.
   */
  function optionsBoutiques(selection, avecEnseigne) {
    const liste = Store.listerBoutiques();
    if (!liste.length) return "";
    /* QUAND « BIZZOO » EST OFFERT, « Choisir… » DISPARAÎT. Garder les
       deux, c'était offrir deux façons de ne pas choisir de boutique —
       l'une volontaire, l'autre par distraction — qui auraient donné le
       même compte d'enseigne. Une seule porte, nommée. */
    const enseigne = avecEnseigne && Supabase.estSuper()
      ? '<option value="__enseigne"' + (selection ? "" : " selected") +
        ">BIZZOO — toutes les boutiques</option>"
      : "";
    return (selection || enseigne ? "" : '<option value="">Choisir…</option>') +
      enseigne +
      liste.map((b) =>
        '<option value="' + Utils.echapper(b.id) + '"' + (selection === b.id ? " selected" : "") + ">" +
        Utils.echapper(b.nomBoutique) + (b.actif ? "" : " (fermée)") + "</option>").join("");
  }

  /* Les quatre interrupteurs d'un compte d'enseigne. Ils ne paraissent
     que pour ces comptes-là : un compte de boutique est déjà borné par
     sa boutique, le superadministrateur passe au-dessus. */
  /* « defaut » dit ce que vaut l'interrupteur sur un compte neuf — et
     sert aussi à le lire : allumé par défaut se lit « pas faux »,
     éteint par défaut se lit « vrai ». Sans cette distinction, une
     colonne absente d'une base pas encore à jour allumerait tout. */
  const INTERRUPTEURS = [
    { id: "cp-d-commandes", champ: "peutCommandes", defaut: true,
      label: "Les commandes",
      aide: "Voir et faire avancer les commandes de toutes les boutiques." },
    { id: "cp-d-produits", champ: "peutModifier", defaut: true,
      label: "Le catalogue",
      aide: "Ajouter et retoucher les produits et les rayons de toutes les boutiques." },
    { id: "cp-d-boutiques", champ: "peutBoutiques", defaut: false,
      label: "Les boutiques",
      aide: "Régler une boutique : slogan, horaires, contacts, marge." },
    { id: "cp-d-finances", champ: "peutFinances", defaut: false,
      label: "Les chiffres",
      aide: "Le journal des versements et les statistiques de vente." },
  ];

  const lireInterrupteur = (compte, i) =>
    (i.defaut ? compte[i.champ] !== false : compte[i.champ] === true);

  /* CE QUE « BIZZOO » VEUT DIRE DANS CE MENU, et ce n'est pas la même
     chose selon le rang : un compte qui gouverne toutes les boutiques,
     ou un porteur qui les sert toutes. Le même mot, deux portées très
     différentes — celui qui nomme doit lire laquelle il donne. */
  const aideBoutique = (rang) => rang === "livreur"
    ? "Ce livreur ne portera que pour cette boutique-là. Choisir " +
      "<strong>BIZZOO</strong> en fait un livreur de l'enseigne : toutes les " +
      "boutiques pourront lui confier une course. Il ne gagne <strong>aucun " +
      "autre droit</strong> pour autant — ni commandes, ni catalogue, ni chiffres."
    : "Ce compte ne verra et ne touchera que cette boutique. " +
      "Choisir <strong>BIZZOO</strong> le met au-dessus de toutes, avec les " +
      "droits que vous lui laissez juste en dessous.";

  const htmlInterrupteurs = (compte) =>
    '<div id="cp-zone-enseigne" class="carte" style="box-shadow:none;padding:14px 0 0;' +
      'margin-top:6px;border-top:1px solid var(--trait)"' +
      (Store.estCompteEnseigne(compte) ? "" : " hidden") + ">" +
      '<div class="carte-titre">' + UI.icone("bouclier", "ic-sm") +
        " Ce qu'il touche chez BIZZOO</div>" +
      '<p class="aide" style="margin:-6px 0 12px">Ce compte n\'est rattaché à aucune ' +
        "boutique : il travaille sur toutes. Laissez éteint ce dont il n'a pas besoin. " +
        "<strong>Il ne crée aucun compte</strong> — cela reste à vous seul.</p>" +
      INTERRUPTEURS.map((i) => UI.interrupteur({ id: i.id, label: i.label,
        aide: i.aide, actif: lireInterrupteur(compte, i) })).join("") +
    "</div>";

  /* Ce qu'un compte de BIZZOO touche, en trois mots, dans la liste : il
     faut pouvoir répondre à « qui voit quoi ? » sans ouvrir six fiches.
     Rien d'allumé se dit — un compte sans aucun droit n'est pas une
     erreur d'affichage, c'est un compte qu'on a fermé. */
  function droitsResumes(compte) {
    const ouverts = INTERRUPTEURS
      .filter((i) => lireInterrupteur(compte, i))
      .map((i) => i.label.replace(/^Les? /, "").toLowerCase());
    return ouverts.length ? " · " + ouverts.join(", ") : " · aucun droit";
  }

  const ICONE_ROLE = {
    superadministrateur: "bouclier",
    administrateur: "cle",
    moderateur: "personne",
  };

  /* À quelle boutique ce compte appartient, en toutes lettres. Un
     livreur sans boutique est un livreur de BIZZOO — et non « boutique
     à choisir », qui l'aurait fait passer pour un compte mal rempli
     alors que c'est un choix délibéré. */
  function rattachement(compte) {
    if (compte.role === "superadministrateur") return " · toutes les boutiques";
    if (Store.estCompteEnseigne(compte)) return " · BIZZOO" + droitsResumes(compte);
    if (compte.role === "livreur" && !compte.boutiqueId) {
      return " · BIZZOO — porte pour toutes les boutiques";
    }
    return " · " + Utils.echapper(nomBoutique(compte.boutiqueId));
  }

  function htmlLigne(compte, moi) {
    /* LES DEUX RANGS QUI COMMANDENT, nommés. La règle d'avant disait
       « tout sauf modérateur », ce qui donnait au livreur la pastille
       des chefs — le seul rang de la liste qui ne décide de rien. */
    const admin = compte.role === "administrateur" ||
      compte.role === "superadministrateur";
    /* Un modérateur privé du droit de modification se voit d'un coup d'œil
       dans la liste : inutile d'ouvrir sa fiche pour le savoir. */
    const bride = compte.role === "moderateur" && !compte.peutModifier;
    return (
      '<div class="compte-ligne' + (compte.actif ? "" : " compte-inactif") + '">' +
        '<span class="compte-rond ' + (admin ? "compte-rond-admin" : "") + '">' +
          UI.icone(ICONE_ROLE[compte.role] || "personne", "ic-sm") + "</span>" +
        '<span class="compte-corps">' +
          /* LE NOM D'ABORD s'il y en a un — on cherche « Rohim » dans une
             liste, pas « porteur@impact.bj ». L'adresse reste en
             dessous : c'est avec elle qu'on se connecte. */
          '<span class="compte-email">' +
            Utils.echapper(compte.nom || compte.email || "—") +
            (moi ? ' <span class="compte-moi">vous</span>' : "") + "</span>" +
          '<span class="compte-details">' + Utils.echapper(nomRole(compte.role)) +
            rattachement(compte) +
            (compte.nom ? " · " + Utils.echapper(compte.email) : "") +
            (compte.actif ? "" : " · désactivé") +
            (bride ? " · ajout seulement" : "") + "</span>" +
        "</span>" +
        /* Pas de crayon sur un compte qu'on n'a pas le droit de toucher :
           la base le refuserait, autant ne pas le proposer. */
        (moi || !Store.gereLeCompte(compte) ? "" :
          '<button type="button" class="btn-ic btn-ic-clair" data-compte="' +
            Utils.echapper(compte.id) + '" aria-label="Modifier ce compte">' +
            UI.icone("crayon", "ic-sm") + "</button>") +
      "</div>"
    );
  }

  /* ---------- Modifier un compte existant ---------- */

  function ouvrirFiche(compte, apres) {
    /* On ne propose que les rangs qu'on a le droit de donner — et celui
       du compte, pour que le menu montre au moins ce qu'il est. */
    const rolesOfferts = Array.from(new Set(Store.rolesAttribuables().concat([compte.role])))
      .filter((cle) => Store.ROLES[cle]);

    const corps = UI.ouvrirFeuille(compte.email || "Compte",
      '<div class="champ">' +
        '<label for="cp-role">Rôle</label>' +
        '<select id="cp-role"' + (rolesOfferts.length < 2 ? " disabled" : "") + ">" +
          rolesOfferts.map((cle) =>
            '<option value="' + cle + '"' + (compte.role === cle ? " selected" : "") + ">" +
            Utils.echapper(Store.ROLES[cle].nom) + "</option>").join("") +
        "</select>" +
        '<div class="aide" id="cp-role-aide">' + Utils.echapper(Store.ROLES[compte.role].aide) + "</div>" +
      "</div>" +
      /* LE NOM ET LE NUMÉRO. « porteur@impact.bj » ne dit pas qui c'est ;
         « Rohim » si — et c'est sous ce nom qu'on le choisira dans
         « Confier à un livreur ». Le numéro sert quand le client n'est
         pas chez lui : c'est le livreur qu'on rappelle. */
      UI.champTexte({ id: "cp-nom", label: "Nom", valeur: compte.nom,
        placeholder: "Rohim",
        aide: "Affiché à la place de l'adresse e-mail, partout où on le choisit." }) +
      UI.champTexte({ id: "cp-tel", label: "Téléphone", valeur: compte.tel,
        type: "tel", placeholder: "01 97 00 00 00" }) +
      UI.interrupteur({ id: "cp-actif", label: "Compte actif", actif: compte.actif,
        aide: "Désactivé, il ne peut plus rien modifier, même en se connectant." }) +
      /* La boutique concerne administrateur et modérateur ; seul le
         super administrateur les gère toutes. */
      (Store.listerBoutiques().length
        ? '<div id="cp-zone-boutique"' +
            (compte.role === "superadministrateur" ? " hidden" : "") + ">" +
            '<div class="champ">' +
              '<label for="cp-boutique">Boutique confiée</label>' +
              '<select id="cp-boutique">' +
                optionsBoutiques(compte.boutiqueId, true) + "</select>" +
              '<div class="aide" id="cp-boutique-aide">' + aideBoutique(compte.role) + "</div>" +
            "</div>" +
            /* TOUJOURS RENDUS, simplement cachés. Les afficher seulement
               quand le compte EST déjà d'enseigne, c'était les rendre
               invisibles au moment précis où l'on en a besoin : celui
               où l'on bascule le menu sur BIZZOO. */
            htmlInterrupteurs(compte) +
          "</div>"
        : "") +
      /* Le droit de retoucher les produits ne concerne que le modérateur :
         un administrateur l'a toujours. */
      '<div id="cp-zone-modif"' + (compte.role === "moderateur" ? "" : " hidden") + ">" +
        UI.interrupteur({ id: "cp-modifier", label: "Peut modifier les produits",
          actif: compte.peutModifier !== false,
          aide: "Décoché, ce modérateur peut encore ajouter des produits, " +
            "mais plus retoucher ni supprimer ceux du catalogue." }) +
      "</div>" +
      '<div class="btn-rangee" style="margin-top:18px">' +
        '<button type="button" class="btn" id="cp-enregistrer">' + UI.icone("check") + "Enregistrer</button>" +
      "</div>" +

      '<div class="carte" style="box-shadow:none;padding:16px 0 0;margin-top:20px;border-top:1px solid var(--trait)">' +
        '<div class="carte-titre">' + UI.icone("cle", "ic-sm") + " Redonner un mot de passe</div>" +
        '<p class="aide" style="margin:-6px 0 12px">Si cette personne a oublié le sien. ' +
          "Ses sessions ouvertes se fermeront.</p>" +
        UI.champTexte({ id: "cp-mdp", label: "Nouveau mot de passe", type: "password",
          placeholder: "6 caractères minimum" }) +
        '<button type="button" class="btn btn-clair" id="cp-mdp-changer">' +
          UI.icone("cle") + "Enregistrer le mot de passe</button>" +
      "</div>" +

      '<div class="carte" style="box-shadow:none;padding:16px 0 0;margin-top:20px;border-top:1px solid var(--trait)">' +
        '<div class="carte-titre">' + UI.icone("poubelle", "ic-sm") + " Supprimer ce compte</div>" +
        '<p class="aide" style="margin:-6px 0 12px">Définitif : l\'adresse et le mot de passe ' +
          "disparaissent. Pour retirer l'accès sans effacer, désactivez plutôt le compte.</p>" +
        '<button type="button" class="btn btn-clair btn-danger-clair" id="cp-supprimer">' +
          UI.icone("poubelle") + "Supprimer définitivement</button>" +
      "</div>");

    const selecteur = UI.$("#cp-role", corps);
    const champBoutiqueMenu = UI.$("#cp-boutique", corps);
    const zoneEnseigne = UI.$("#cp-zone-enseigne", corps);

    /* Les deux menus décident ensemble de ce qu'on voit : un compte
       d'enseigne, c'est un rang de l'équipe ET aucune boutique. */
    const rafraichirZones = () => {
      const rang = selecteur.value;
      const surEnseigne = champBoutiqueMenu
        ? champBoutiqueMenu.value === "__enseigne" : !compte.boutiqueId;
      UI.$("#cp-role-aide", corps).textContent = Store.ROLES[rang].aide;
      /* L'AIDE DU MENU SUIT LE RANG. « BIZZOO » ne veut pas dire la
         même chose pour un modérateur et pour un livreur ; une phrase
         figée en aurait décrit un des deux, et trompé sur l'autre. */
      const aide = UI.$("#cp-boutique-aide", corps);
      if (aide) aide.innerHTML = aideBoutique(rang);
      /* Le droit « produits » d'un compte d'enseigne vit dans SES
         interrupteurs : l'afficher deux fois se contredirait. */
      UI.$("#cp-zone-modif", corps).hidden =
        rang !== "moderateur" || (surEnseigne && rang !== "superadministrateur");
      const zoneBoutique = UI.$("#cp-zone-boutique", corps);
      if (zoneBoutique) zoneBoutique.hidden = rang === "superadministrateur";
      if (zoneEnseigne) {
        zoneEnseigne.hidden = rang === "superadministrateur" ||
          rang === "livreur" || !surEnseigne;
      }
    };
    selecteur.onchange = rafraichirZones;
    if (champBoutiqueMenu) champBoutiqueMenu.onchange = rafraichirZones;
    rafraichirZones();

    UI.$("#cp-mdp-changer", corps).onclick = async () => {
      const bouton = UI.$("#cp-mdp-changer", corps);
      const mdp = UI.$("#cp-mdp", corps).value;
      if (mdp.length < 6) return UI.toast("Le mot de passe doit faire 6 caractères au moins.", "err");
      bouton.disabled = true;
      try {
        await Store.changerMotDePasseCompte(compte.id, mdp);
        UI.fermerFeuille();
        UI.toast("Nouveau mot de passe pour " + compte.email, "ok");
        apres();
      } catch (err) {
        UI.toast(err.message, "err");
        bouton.disabled = false;
      }
    };

    UI.$("#cp-supprimer", corps).onclick = async () => {
      UI.feuilleSansRappel();
      UI.fermerFeuille();
      const ok = await UI.confirmer({
        titre: "Supprimer " + compte.email + " ?",
        texte: "Ce compte disparaîtra définitivement : la personne ne pourra plus se connecter. " +
          "Les produits qu'elle a créés restent au catalogue.",
        bouton: "Supprimer", danger: true,
      });
      if (!ok) return;
      try {
        await Store.supprimerCompte(compte.id);
        UI.toast("Compte supprimé", "ok");
        apres();
      } catch (err) {
        UI.toast(err.message, "err");
      }
    };

    UI.$("#cp-enregistrer", corps).onclick = async () => {
      const bouton = UI.$("#cp-enregistrer", corps);
      bouton.disabled = true;
      const role = selecteur.value;
      const actif = UI.$("#cp-actif", corps).checked;
      /* Un administrateur garde toujours le droit de modifier : si le rôle
         passe à « administrateur », on remet le droit à vrai.
         SAUF POUR UN COMPTE D'ENSEIGNE : là c'est son interrupteur qui
         décide, quel que soit son rang — sinon le régler n'aurait
         servi à rien, l'enregistrement l'aurait rallumé aussitôt. */
      const zoneEns = UI.$("#cp-zone-enseigne", corps);
      const surEnseigne = zoneEns && !zoneEns.hidden;
      const peutModifier = surEnseigne
        ? UI.$("#cp-d-produits", corps).checked
        : (role === "moderateur" ? UI.$("#cp-modifier", corps).checked : true);
      const champBoutique = UI.$("#cp-boutique", corps);
      /* Le super administrateur n'appartient à aucune boutique : il circule partout.
         « __enseigne » veut dire la même chose pour un compte de BIZZOO —
         on l'écrit en clair dans le menu pour que « boutique vide » ne
         se confonde pas avec « pas encore choisie ». */
      const choix = champBoutique ? champBoutique.value : compte.boutiqueId;
      const boutiqueId = role === "superadministrateur" || choix === "__enseigne"
        ? "" : choix;
      try {
        if (role !== "superadministrateur" && champBoutique && !choix) {
          throw new Error("Choisissez la boutique confiée à ce compte.");
        }
        /* Un enregistrement par changement plutôt qu'un seul : le journal
           raconte alors précisément ce qui a changé. */
        if (role !== compte.role) await Store.majCompte(compte.id, { role });
        if (actif !== compte.actif) await Store.majCompte(compte.id, { actif });
        if (boutiqueId !== (compte.boutiqueId || "")) {
          await Store.majCompte(compte.id, { boutiqueId });
        }
        if (peutModifier !== (compte.peutModifier !== false)) {
          await Store.majCompte(compte.id, { peutModifier });
        }
        const nom = UI.$("#cp-nom", corps).value.trim();
        const tel = UI.$("#cp-tel", corps).value.trim();
        if (nom !== (compte.nom || "")) await Store.majCompte(compte.id, { nom });
        if (tel !== (compte.tel || "")) await Store.majCompte(compte.id, { tel });
        /* Les interrupteurs d'enseigne, s'ils sont à l'écran. On
           n'envoie que ce qui a bougé : le journal raconte alors
           précisément quel droit a été donné ou retiré. */
        for (const i of INTERRUPTEURS) {
          const boite = UI.$("#" + i.id, corps);
          if (!boite || i.champ === "peutModifier") continue;
          if (boite.checked !== lireInterrupteur(compte, i)) {
            await Store.majCompte(compte.id, { [i.champ]: boite.checked });
          }
        }
        UI.fermerFeuille();
        UI.toast("Compte mis à jour", "ok");
        apres();
      } catch (err) {
        UI.toast(err.message, "err");
        bouton.disabled = false;
      }
    };
  }

  /* ---------- Créer un compte ---------- */

  function ouvrirCreation(apres) {
    /* LE LIVREUR EST DANS LA LISTE, et il y manquait. On pouvait le
       nommer, mais seulement APRÈS coup : il fallait créer un
       modérateur puis changer son rang dans sa fiche. Personne ne
       devine ce détour, et le compte restait modérateur chez ceux qui
       ne l'ont pas deviné.
       L'ordre suit le plus courant, pas la hiérarchie : on crée des
       modérateurs et des livreurs tous les jours, un administrateur
       une fois. Et le menu disparaît quand il n'y a pas le choix. */
    const rangs = ["moderateur", "livreur", "administrateur", "superadministrateur"]
      .filter((cle) => Store.rolesAttribuables().includes(cle));
    if (!rangs.length) {
      UI.toast("Votre compte ne peut pas créer d'autres comptes.", "err");
      return;
    }

    const corps = UI.ouvrirFeuille("Nouveau compte",
      UI.champTexte({ id: "nc-email", label: "Adresse email", obligatoire: true,
        type: "email", placeholder: "prenom@exemple.com",
        aide: "C'est avec elle que la personne se connectera." }) +
      UI.champTexte({ id: "nc-mdp", label: "Mot de passe", obligatoire: true,
        type: "password", placeholder: "6 caractères minimum",
        aide: "À lui communiquer ; elle pourra le changer elle-même ensuite." }) +
      /* LE NOM ET LE NUMÉRO SE DONNENT ICI, pas « plus tard ». Plus
         tard n'arrive pas : le compte part en service avec son adresse
         e-mail pour seul nom, et c'est cette adresse que la boutique
         lit dans « Confier à un livreur » le jour où elle cherche qui
         appeler. */
      UI.champTexte({ id: "nc-nom", label: "Nom", placeholder: "Rohim",
        aide: "Affiché à la place de l'adresse e-mail, partout où on le choisit." }) +
      UI.champTexte({ id: "nc-tel", label: "Téléphone", type: "tel",
        placeholder: "01 97 00 00 00",
        aide: "Pour le rappeler quand le client n'est pas chez lui." }) +
      '<div class="champ">' +
        '<label for="nc-role">Rôle</label>' +
        '<select id="nc-role"' + (rangs.length < 2 ? " disabled" : "") + ">" +
          rangs.map((cle, i) =>
            '<option value="' + cle + '"' + (i === 0 ? " selected" : "") + ">" +
            Utils.echapper(Store.ROLES[cle].nom) + "</option>").join("") +
        "</select>" +
        '<div class="aide" id="nc-role-aide">' + Utils.echapper(Store.ROLES[rangs[0]].aide) + "</div>" +
      "</div>" +
      (Store.listerBoutiques().length
        ? '<div class="champ" id="nc-zone-boutique">' +
            '<label for="nc-boutique">Boutique confiée <span class="obligatoire">*</span></label>' +
            '<select id="nc-boutique"' + (Supabase.estSuper() ? "" : " disabled") + ">" +
              optionsBoutiques((Store.boutiqueCourante() || {}).id, true) + "</select>" +
            '<div class="aide" id="nc-boutique-aide">' + (Supabase.estSuper()
              ? aideBoutique(rangs[0])
              : "Vous ne créez des comptes que pour votre boutique.") + "</div>" +
          "</div>"
        : "") +
      '<div class="btn-rangee" style="margin-top:18px">' +
        '<button type="button" class="btn" id="nc-creer">' + UI.icone("plus") + "Créer le compte</button>" +
      "</div>" +
      '<div id="nc-resultat"></div>');

    const selecteur = UI.$("#nc-role", corps);
    const zoneBoutique = UI.$("#nc-zone-boutique", corps);
    selecteur.onchange = () => {
      UI.$("#nc-role-aide", corps).textContent = Store.ROLES[selecteur.value].aide;
      /* Un administrateur les gère toutes : pas de boutique à choisir. */
      if (zoneBoutique) zoneBoutique.hidden = selecteur.value === "superadministrateur";
      const aide = UI.$("#nc-boutique-aide", corps);
      if (aide && Supabase.estSuper()) aide.innerHTML = aideBoutique(selecteur.value);
    };

    UI.$("#nc-creer", corps).onclick = async () => {
      const bouton = UI.$("#nc-creer", corps);
      bouton.disabled = true;
      bouton.textContent = "Création…";
      try {
        const champBoutique = UI.$("#nc-boutique", corps);
        /* On passe le choix TEL QUEL — « __enseigne » compris. C'est le
           store qui le traduit en « aucune boutique », et lui seul :
           traduire ici ferait d'un menu oublié un compte d'enseigne. */
        const compte = await Store.creerCompte(
          UI.$("#nc-email", corps).value, UI.$("#nc-mdp", corps).value, selecteur.value,
          champBoutique ? champBoutique.value : "",
          UI.$("#nc-nom", corps).value, UI.$("#nc-tel", corps).value);
        UI.fermerFeuille();
        if (compte.confirmationRequise) {
          UI.toast("Compte créé — il doit d'abord confirmer son adresse par email.", "ok");
        } else {
          UI.toast(nomRole(compte.role) + " ajouté : " + compte.email, "ok");
        }
        apres();
      } catch (err) {
        UI.$("#nc-resultat", corps).innerHTML =
          '<p class="aide" style="color:var(--rouge);margin:12px 0 0">' + Utils.echapper(err.message) + "</p>";
        bouton.disabled = false;
        bouton.innerHTML = UI.icone("plus") + "Créer le compte";
      }
    };
  }

  /* ---------- L'équipe (administrateur) ---------- */

  async function afficher(vue) {
    UI.entete({ titre: "Comptes", retour: true, sous: "Qui peut modifier la boutique" });

    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>Lecture de l\'équipe…</div>';

    let comptes;
    try {
      comptes = await Store.listerComptes();
    } catch (err) {
      vue.innerHTML =
        '<div class="carte"><div class="carte-titre">Comptes indisponibles</div>' +
        '<p class="aide" style="margin:0">' + Utils.echapper(err.message) +
        "<br>Si les rôles viennent d'être ajoutés, exécutez le fichier supabase/schema.sql.</p></div>";
      return;
    }

    const moi = Supabase.identifiant();
    vue.innerHTML =
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("equipe", "ic-sm") + " L'équipe (" + comptes.length + ")</div>" +
        '<p class="aide" style="margin:-4px 0 12px">Le <strong>super administrateur</strong> tient ' +
          "toute l'enseigne : les boutiques, les réglages BIZZOO et les comptes. " +
          "L'<strong>administrateur</strong> a tous les droits sur SA boutique — produits, rayons, " +
          "slider, réglages et ses modérateurs. Le <strong>modérateur</strong> s'occupe des produits " +
          "et des rayons de sa boutique, rien d'autre. Le <strong>livreur</strong> ne voit que " +
          "les courses qu'on lui confie, sans aucun montant : il porte pour une boutique, ou " +
          "pour <strong>BIZZOO</strong> et alors pour toutes.</p>" +
        (comptes.length
          ? comptes.map((c) => htmlLigne(c, c.id === moi)).join("")
          : '<p class="aide" style="margin:0">Aucun compte enregistré.</p>') +
        '<button type="button" class="btn" id="cp-nouveau" style="margin-top:14px">' +
          UI.icone("plus") + "Créer un compte</button>" +
      "</div>" +
      '<div class="carte">' +
        '<div class="carte-titre">Bon à savoir</div>' +
        '<p class="aide" style="margin:0">Touchez le crayon d\'un compte pour changer son rôle, ' +
          "lui retirer ou lui rendre le droit de modifier les produits, lui redonner un " +
          "mot de passe, le désactiver ou le supprimer. Un modérateur sans ce droit " +
          "(<strong>ajout seulement</strong>) continue d'ajouter des produits mais ne peut " +
          "plus retoucher ni supprimer ceux du catalogue. Un compte " +
          "<strong>désactivé</strong> garde son adresse mais ne peut plus rien modifier ; " +
          "un compte <strong>supprimé</strong> disparaît pour de bon. " +
          "Votre propre compte n'apparaît pas : on ne se retire pas ses propres droits.</p>" +
      "</div>";

    UI.$("#cp-nouveau", vue).onclick = () => ouvrirCreation(() => afficher(vue));
    for (const bouton of UI.$$("[data-compte]", vue)) {
      bouton.onclick = () => {
        const compte = comptes.find((c) => c.id === bouton.dataset.compte);
        if (compte) ouvrirFiche(compte, () => afficher(vue));
      };
    }
  }

  /* ---------- Sa propre fiche (tout le monde) ---------- */

  async function monCompte(vue) {
    UI.entete({ titre: "Mon compte", retour: true });

    const profil = Supabase.compte();
    const role = Supabase.role();

    vue.innerHTML =
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("personne", "ic-sm") + " Connecté</div>" +
        '<p class="aide" style="margin:0">Vous êtes connecté en tant que <strong>' +
          Utils.echapper(Supabase.utilisateur() || "—") + "</strong>." +
          (role ? "<br>Rôle : <strong>" + Utils.echapper(nomRole(role)) + "</strong> — " +
            Utils.echapper(Store.ROLES[role].aide) : "") +
          ((profil && !profil.actif)
            ? '<br><span style="color:var(--rouge)">Compte désactivé : demandez à l\'administrateur de le réactiver.</span>'
            : "") +
        "</p>" +
      "</div>" +

      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("cle", "ic-sm") + " Changer mon mot de passe</div>" +
        UI.champTexte({ id: "mc-mdp", label: "Nouveau mot de passe", type: "password",
          placeholder: "6 caractères minimum" }) +
        UI.champTexte({ id: "mc-mdp2", label: "Répéter le mot de passe", type: "password" }) +
        '<button type="button" class="btn" id="mc-changer" style="margin-top:4px">' +
          UI.icone("check") + "Enregistrer le mot de passe</button>" +
        '<div id="mc-resultat"></div>' +
      "</div>" +

      '<div class="carte">' +
        '<div class="carte-titre">Quitter</div>' +
        '<button type="button" class="btn btn-clair" id="mc-deconnexion">Se déconnecter</button>' +
      "</div>";

    UI.$("#mc-changer", vue).onclick = async () => {
      const mdp = UI.$("#mc-mdp", vue).value;
      const mdp2 = UI.$("#mc-mdp2", vue).value;
      if (mdp.length < 6) return UI.toast("Le mot de passe doit faire 6 caractères au moins.", "err");
      if (mdp !== mdp2) return UI.toast("Les deux mots de passe ne sont pas identiques.", "err");
      const bouton = UI.$("#mc-changer", vue);
      bouton.disabled = true;
      try {
        await Supabase.changerMotDePasse(mdp);
        UI.$("#mc-mdp", vue).value = "";
        UI.$("#mc-mdp2", vue).value = "";
        UI.toast("Mot de passe changé", "ok");
        Store.journaliser("compte", "modification", "Mot de passe changé", Supabase.utilisateur());
      } catch (err) {
        UI.toast(err.message, "err");
      }
      bouton.disabled = false;
    };

    UI.$("#mc-deconnexion", vue).onclick = async () => {
      await Store.journaliser("compte", "deconnexion", "Déconnexion de l'application admin",
        Supabase.utilisateur());
      await Supabase.deconnexion();
      location.reload();
    };
  }

  return { afficher, monCompte };
})();
