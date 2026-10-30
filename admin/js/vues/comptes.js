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
    const enseigne = avecEnseigne && (Supabase.estSuper() || Supabase.estAdminBizzoo())
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
    /* (3.68.0) Accordé par le superadministrateur SEUL : un autre compte
       ne voit même pas l'interrupteur, et la base refuserait. */
    { id: "cp-d-faire-livrer", champ: "faireLivrer", defaut: false, superSeulement: true,
      label: "Faire livrer",
      aide: "Saisir une commande prise et payée sur WhatsApp : elle entre dans BIZZOO et part aux livreurs." },
  ];
  const interrupteursVisibles = () => INTERRUPTEURS.filter((i) => !i.superSeulement || Supabase.estSuper());

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
      interrupteursVisibles().map((i) => UI.interrupteur({ id: i.id, label: i.label,
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

  /* QUI L'A CRÉÉ, ET QUAND. La base l'écrit au moment de la création ;
     cet écran ne fait que le lire. Un compte né hors de l'application —
     dans le tableau de bord de Supabase, ou inscrit seul — n'a pas de
     créateur, et on le dit plutôt que de laisser un blanc. */
  function traceCreation(compte) {
    const quand = compte.creeLe
      ? "Créé le " + Utils.fmtDateHeure(compte.creeLe)
      : "Date de création inconnue";
    return quand + (compte.creeParNom
      ? " par " + compte.creeParNom
      : " — hors de l'application");
  }

  /* SON NUMÉRO : c'est là que part le code de connexion par SMS. « Jamais
     confirmé » n'est pas une faute — personne n'y a encore reçu de code ;
     « sans numéro », en revanche, ferme la porte le jour où l'enseigne
     exige le code. */
  function etatNumero(compte) {
    const chiffres = String(compte.tel || "").replace(/\D/g, "");
    if (chiffres.length < 8) return '<span class="compte-numero-manque">sans numéro</span>';
    return compte.telVerifie
      ? '<span class="compte-numero-ok">numéro vérifié</span>'
      : "numéro jamais confirmé par un code";
  }

  function htmlLigne(compte, moi) {
    /* LES DEUX RANGS QUI COMMANDENT, nommés. La règle d'avant disait
       « tout sauf modérateur », ce qui donnait au livreur la pastille
       des chefs — le seul rang de la liste qui ne décide de rien. */
    const admin = compte.role === "administrateur" ||
      compte.role === "superadministrateur";
    /* Un modérateur privé du droit de modification se voit d'un coup d'œil
       dans la liste : inutile d'ouvrir sa fiche pour le savoir. */
    const bride = ["moderateur", "administrateur"].includes(compte.role) && !!compte.boutiqueId &&
      !compte.peutModifier;
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
            (moi ? ' <span class="compte-moi">vous</span>' : "") +
            /* (3.59.0) Celui qui vous a créé — ou plus haut : on ne touche
               pas à ses droits. */
            (Store.estMonCreateur(compte) ? ' <span class="compte-moi compte-createur">vous a créé</span>' : "") +
            "</span>" +
          '<span class="compte-details">' + Utils.echapper(nomRole(compte.role)) +
            rattachement(compte) +
            (compte.nom ? " · " + Utils.echapper(compte.email) : "") +
            (compte.aValider ? " · à valider par le superadministrateur"
              : compte.actif ? "" : " · désactivé") +
            (bride ? " · ajout seulement" : "") + "</span>" +
          '<span class="compte-trace">' + Utils.echapper(traceCreation(compte)) +
            " · " + etatNumero(compte) + "</span>" +
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
    /* LES LIVREURS SE GÈRENT À PART (écran « Livreurs ») : un livreur
       reste livreur, et un compte de l'équipe ne le devient pas d'ici. */
    /* (3.72.0) LES VENDEURS AUSSI : un vendeur reste vendeur, et un compte
       de l'équipe ne le devient pas d'ici (écran « Vendeurs »). */
    const rolesOfferts = compte.role === "livreur" ? ["livreur"]
      : compte.role === "vendeur" ? ["vendeur"]
      : Array.from(new Set(Store.rolesAttribuables().concat([compte.role])))
          .filter((cle) => Store.ROLES[cle] && cle !== "livreur" && cle !== "vendeur");

    const corps = UI.ouvrirFeuille(compte.email || "Compte",
      '<p class="aide" style="margin:0 0 14px">' + Utils.echapper(traceCreation(compte)) +
        " · " + etatNumero(compte) + "</p>" +
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
        type: "tel", placeholder: "01 97 00 00 00",
        aide: "C'est là que part son code de connexion par SMS. Le changer annule " +
          "sa vérification : le prochain code partira au nouveau numéro." }) +
      /* (3.64.0) Son véhicule : le tricycle porte les gros colis. */
      (compte.role === "livreur" && compte.vehicule !== undefined
        ? '<div class="champ"><label for="cp-vehicule">Véhicule</label>' +
          '<select id="cp-vehicule">' +
            '<option value="moto"' + (compte.vehicule === "tricycle" ? "" : " selected") + ">Moto</option>" +
            '<option value="tricycle"' + (compte.vehicule === "tricycle" ? " selected" : "") + ">Tricycle</option>" +
          "</select>" +
          '<div class="aide">Une commande en tricycle (gros colis) n\'est proposée qu\'aux livreurs en tricycle.</div>' +
        "</div>"
        : "") +
      /* (3.72.0) Le nom de son compte MoMo, comparé avant chaque reversement. */
      (compte.role === "livreur" && compte.momoNom !== undefined
        ? UI.champTexte({ id: "cp-momo-nom", label: "Nom du compte MoMo", valeur: compte.momoNom,
            placeholder: "Tel qu'il s'affiche chez MoMo",
            aide: "Avant de lui reverser ses gains, on vérifie que MoMo affiche bien ce nom." })
        : "") +
      /* (3.63.0) UN COMPTE À VALIDER : seul le superadministrateur
         l'active, et l'activer le valide. Son créateur le voit attendre. */
      (compte.aValider && !Supabase.estSuper()
        ? '<p class="aide" style="margin:4px 0 14px">' + UI.icone("horloge", "ic-sm") +
            " En attente de validation : le superadministrateur l'activera.</p>"
        : UI.interrupteur({ id: "cp-actif", label: compte.aValider ? "Valider et activer ce compte" : "Compte actif",
            actif: compte.actif,
            aide: compte.aValider
              ? "Créé par " + (compte.creeParNom || "un administrateur de BIZZOO") +
                ". Activez-le pour le valider."
              : "Désactivé, il ne peut plus rien modifier, même en se connectant." })) +
      /* La boutique concerne administrateur et modérateur ; seul le
         super administrateur les gère toutes. */
      (Store.listerBoutiques().length
        ? '<div id="cp-zone-boutique"' +
            (compte.role === "superadministrateur" || compte.role === "vendeur" ? " hidden" : "") + ">" +
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
      /* L'HABILITATION AUX PRODUITS (3.59.0) : créer, modifier,
         supprimer. Elle vaut pour le modérateur ET l'administrateur d'une
         boutique — un administrateur ne l'a plus d'office. */
      '<div id="cp-zone-modif"' + (["moderateur", "administrateur"].includes(compte.role) ? "" : " hidden") + ">" +
        UI.interrupteur({ id: "cp-modifier", label: "Peut créer et modifier les produits",
          actif: compte.peutModifier !== false,
          aide: "Décoché, ce compte ne crée plus de produit, et ne retouche ni ne " +
            "supprime ceux du catalogue." }) +
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
    const champBoutiqueMenu = UI.cherchable(UI.$("#cp-boutique", corps), { placeholder: "Rechercher une boutique…" });
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
        !["moderateur", "administrateur"].includes(rang) || (surEnseigne && rang !== "superadministrateur");
      const zoneBoutique = UI.$("#cp-zone-boutique", corps);
      if (zoneBoutique) zoneBoutique.hidden = rang === "superadministrateur" || rang === "vendeur";
      if (zoneEnseigne) {
        zoneEnseigne.hidden = rang === "superadministrateur" ||
          rang === "livreur" || rang === "vendeur" || !surEnseigne;
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
      const caseActif = UI.$("#cp-actif", corps);
      const actif = caseActif ? caseActif.checked : compte.actif;
      /* Un administrateur garde toujours le droit de modifier : si le rôle
         passe à « administrateur », on remet le droit à vrai.
         SAUF POUR UN COMPTE D'ENSEIGNE : là c'est son interrupteur qui
         décide, quel que soit son rang — sinon le régler n'aurait
         servi à rien, l'enregistrement l'aurait rallumé aussitôt. */
      const zoneEns = UI.$("#cp-zone-enseigne", corps);
      const surEnseigne = zoneEns && !zoneEns.hidden;
      const peutModifier = surEnseigne
        ? UI.$("#cp-d-produits", corps).checked
        : (["moderateur", "administrateur"].includes(role) ? UI.$("#cp-modifier", corps).checked : true);
      const champBoutique = UI.$("#cp-boutique", corps);
      /* Le super administrateur n'appartient à aucune boutique : il circule partout.
         « __enseigne » veut dire la même chose pour un compte de BIZZOO —
         on l'écrit en clair dans le menu pour que « boutique vide » ne
         se confonde pas avec « pas encore choisie ». */
      const choix = champBoutique ? champBoutique.value : compte.boutiqueId;
      /* (3.72.0) Un vendeur n'est rattaché à aucune boutique : ses produits le sont. */
      const sansBoutique = role === "superadministrateur" || role === "vendeur";
      const boutiqueId = sansBoutique || choix === "__enseigne" ? "" : choix;
      try {
        if (!sansBoutique && champBoutique && !choix) {
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
        const champVehicule = UI.$("#cp-vehicule", corps);
        if (champVehicule && champVehicule.value !== (compte.vehicule || "moto")) {
          await Store.majCompte(compte.id, { vehicule: champVehicule.value });
        }
        const champMomo = UI.$("#cp-momo-nom", corps);
        if (champMomo && champMomo.value.trim() !== (compte.momoNom || "")) {
          await Store.majCompte(compte.id, { momoNom: champMomo.value });
        }
        /* Les interrupteurs d'enseigne, s'ils sont à l'écran. On
           n'envoie que ce qui a bougé : le journal raconte alors
           précisément quel droit a été donné ou retiré. */
        for (const i of interrupteursVisibles()) {
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

  /* (3.70.0) « vendeur » : le compte d'un vendeur des boutiques à vendeurs
     multiples — par son numéro, comme un livreur, et sans boutique. */
  function ouvrirCreation(apres, livreur, vendeur, rangImpose) {
    const parTel = livreur || vendeur;
    /* LE LIVREUR EST DANS LA LISTE, et il y manquait. On pouvait le
       nommer, mais seulement APRÈS coup : il fallait créer un
       modérateur puis changer son rang dans sa fiche. Personne ne
       devine ce détour, et le compte restait modérateur chez ceux qui
       ne l'ont pas deviné.
       L'ordre suit le plus courant, pas la hiérarchie : on crée des
       modérateurs et des livreurs tous les jours, un administrateur
       une fois. Et le menu disparaît quand il n'y a pas le choix. */
    /* LES LIVREURS ONT LEUR PROPRE BOUTON (écran « Livreurs ») : ici,
       l'un ou l'autre, jamais mélangés. */
    /* (3.72.0) Depuis la section d'un rang (« Créer un modérateur »), le
       rang est fixé d'avance. */
    const rangs = (livreur ? ["livreur"] : vendeur ? ["vendeur"]
      : rangImpose ? [rangImpose]
      : ["moderateur", "administrateur", "superadministrateur"])
      .filter((cle) => Store.rolesAttribuables().includes(cle));
    if (!rangs.length) {
      UI.toast(livreur ? "Votre compte ne peut pas créer de livreur."
        : vendeur ? "Seul le superadministrateur crée un vendeur (et la base doit être à jour)."
        : "Votre compte ne peut pas créer d'autres comptes.", "err");
      return;
    }

    /* UN LIVREUR ENTRE PAR SON NUMÉRO : numéro, mot de passe, puis un
       code reçu par SMS. Son e-mail est facultatif — s'il en a un, il
       devient sa porte de secours, sans code. L'équipe garde l'e-mail. */
    const TITRES = { administrateur: "Nouvel administrateur", moderateur: "Nouveau modérateur",
      superadministrateur: "Nouveau superadministrateur" };
    const corps = UI.ouvrirFeuille(livreur ? "Nouveau livreur" : vendeur ? "Nouveau vendeur"
      : (rangImpose && TITRES[rangImpose]) || "Nouveau compte",
      (parTel
        ? UI.champTexte({ id: "nc-tel", label: "Téléphone", type: "tel", obligatoire: true,
            placeholder: "01 97 00 00 00",
            aide: vendeur
              ? "C'est avec lui qu'il se connectera à BIZZOO Admin : son numéro et son mot de passe. " +
                "Il y verra ses produits, ses ventes et ce qui lui revient."
              : "C'est avec lui qu'il se connectera : son numéro, son mot de passe, puis " +
                "un code reçu par SMS. C'est aussi le numéro qu'on appelle quand le client " +
                "n'est pas chez lui." })
        : UI.champTexte({ id: "nc-email", label: "Adresse email", obligatoire: true,
            type: "email", placeholder: "prenom@exemple.com",
            aide: "C'est avec elle que la personne se connectera." })) +
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
      (parTel
        ? UI.champTexte({ id: "nc-email", label: "Adresse e-mail (facultatif)",
            type: "email", placeholder: "prenom@exemple.com",
            aide: "Sa porte de secours : sans son téléphone, il entrera avec cet e-mail " +
              "et son mot de passe, sans code." })
        : UI.champTexte({ id: "nc-tel", label: "Téléphone", type: "tel", obligatoire: true,
            placeholder: "01 97 00 00 00",
            aide: "C'est là que partira son code de connexion par SMS — et le numéro " +
              "qu'on appelle quand le client n'est pas chez lui." })) +
      '<div class="champ"' + (parTel ? " hidden" : "") + ">" +
        '<label for="nc-role">Rôle</label>' +
        '<select id="nc-role"' + (rangs.length < 2 ? " disabled" : "") + ">" +
          rangs.map((cle, i) =>
            '<option value="' + cle + '"' + (i === 0 ? " selected" : "") + ">" +
            Utils.echapper(Store.ROLES[cle].nom) + "</option>").join("") +
        "</select>" +
        '<div class="aide" id="nc-role-aide">' + Utils.echapper(Store.ROLES[rangs[0]].aide) + "</div>" +
      "</div>" +
      (Store.listerBoutiques().length && !vendeur
        ? '<div class="champ" id="nc-zone-boutique">' +
            '<label for="nc-boutique">Boutique confiée <span class="obligatoire">*</span></label>' +
            '<select id="nc-boutique"' + (Supabase.estSuper() || Supabase.estAdminBizzoo() ? "" : " disabled") + ">" +
              optionsBoutiques((Store.boutiqueCourante() || {}).id, true) + "</select>" +
            '<div class="aide" id="nc-boutique-aide">' + (Supabase.estSuper() || Supabase.estAdminBizzoo()
              ? aideBoutique(rangs[0])
              : "Vous ne créez des comptes que pour votre boutique.") + "</div>" +
          "</div>"
        : "") +
      (livreur ? '<div class="champ"><label for="nc-vehicule">Véhicule</label>' +
          '<select id="nc-vehicule">' +
            '<option value="moto"' + ("" === "tricycle" ? "" : " selected") + ">Moto</option>" +
            '<option value="tricycle"' + ("" === "tricycle" ? " selected" : "") + ">Tricycle</option>" +
          "</select>" +
          '<div class="aide">Une commande en tricycle (gros colis) n\'est proposée qu\'aux livreurs en tricycle.</div>' +
        "</div>" : "") +
      /* (3.72.0) LE NOM DU COMPTE MOMO, noté par l'équipe : avant de lui
         reverser ses gains, on le compare au nom que MoMo affiche. Le
         livreur ne peut pas le changer lui-même. */
      (livreur
        ? UI.champTexte({ id: "nc-momo-nom", label: "Nom du compte MoMo", obligatoire: true,
            placeholder: "Tel qu'il s'affiche chez MoMo",
            aide: "Le nom du titulaire du compte Mobile Money qui recevra ses gains. Avant chaque " +
              "reversement, on vérifie que MoMo affiche bien ce nom." })
        : "") +
      (livreur
        ? '<p class="aide" style="margin:12px 0 0">À sa première connexion à BIZZOO Admin, le ' +
            "livreur devra <strong>valider son compte en enregistrant sa position</strong> " +
            "(localisation du téléphone et adresse). Avant cela, aucune course ne peut lui " +
            "être confiée.</p>"
        : "") +
      '<div class="btn-rangee" style="margin-top:18px">' +
        '<button type="button" class="btn" id="nc-creer">' + UI.icone("plus") +
          (livreur ? "Créer le livreur" : vendeur ? "Créer le vendeur" : "Créer le compte") + "</button>" +
      "</div>" +
      '<div id="nc-resultat"></div>');

    /* (3.72.0) Les boutiques par ordre alphabétique, et un champ pour la trouver. */
    UI.cherchable(UI.$("#nc-boutique", corps), { placeholder: "Rechercher une boutique…" });
    const selecteur = UI.$("#nc-role", corps);
    const zoneBoutique = UI.$("#nc-zone-boutique", corps);
    selecteur.onchange = () => {
      UI.$("#nc-role-aide", corps).textContent = Store.ROLES[selecteur.value].aide;
      /* Un administrateur les gère toutes : pas de boutique à choisir. */
      if (zoneBoutique) zoneBoutique.hidden = selecteur.value === "superadministrateur";
      const aide = UI.$("#nc-boutique-aide", corps);
      if (aide && (Supabase.estSuper() || Supabase.estAdminBizzoo())) aide.innerHTML = aideBoutique(selecteur.value);
    };

    UI.$("#nc-creer", corps).onclick = async () => {
      const bouton = UI.$("#nc-creer", corps);
      const champMomo = UI.$("#nc-momo-nom", corps);
      if (champMomo && champMomo.value.trim().length < 2) {
        UI.toast("Saisissez le nom du compte MoMo du livreur.", "err");
        champMomo.focus();
        return;
      }
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
        /* (3.64.0) Le tricycle se pose juste après : le compte naît « moto ». */
        const champVehicule = UI.$("#nc-vehicule", corps);
        if (livreur && champVehicule && champVehicule.value === "tricycle" && compte.id) {
          try { await Store.majCompte(compte.id, { vehicule: "tricycle" }); }
          catch (err) { UI.toast("Livreur créé, mais son véhicule n'a pas pu être réglé : " + err.message, "err"); }
        }
        /* (3.72.0) Son nom de compte MoMo, juste après : le compte naît sans. */
        if (champMomo && compte.id) {
          try { await Store.majCompte(compte.id, { momoNom: champMomo.value }); }
          catch (err) { UI.toast("Livreur créé, mais le nom du compte MoMo n'a pas pu être enregistré : " + err.message, "err"); }
        }
        UI.fermerFeuille();
        if (compte.aValider) {
          UI.toast(nomRole(compte.role) + " créé : il attend la validation du superadministrateur.", "ok");
        } else if (compte.confirmationRequise) {
          UI.toast("Compte créé — il doit d'abord confirmer son adresse par email.", "ok");
        } else {
          UI.toast(nomRole(compte.role) + " ajouté : " + (compte.email || compte.tel || compte.nom), "ok");
        }
        apres();
      } catch (err) {
        UI.$("#nc-resultat", corps).innerHTML =
          '<p class="aide" style="color:var(--rouge);margin:12px 0 0">' + Utils.echapper(err.message) + "</p>";
        bouton.disabled = false;
        bouton.innerHTML = UI.icone("plus") + (livreur ? "Créer le livreur" : vendeur ? "Créer le vendeur" : "Créer le compte");
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
    /* LES LIVREURS NE SONT PLUS MÉLANGÉS À L'ÉQUIPE : ils ont leur écran,
       leur bouton de création et leur gestion. */
    const nbLivreurs = comptes.filter((c) => c.role === "livreur").length;
    /* (3.72.0) LES VENDEURS NON PLUS : leur écran, leur bouton, leur fiche. */
    const nbVendeurs = comptes.filter((c) => c.role === "vendeur").length;
    comptes = comptes.filter((c) => c.role !== "livreur" && c.role !== "vendeur");
    /* (3.72.0) Les rangs de l'équipe, chacun sa section, par ordre alphabétique. */
    const nomDe = (c) => String(c.nom || c.email || c.tel || "");
    const parRang = (rang) => comptes.filter((c) => c.role === rang)
      .sort((a, b) => nomDe(a).localeCompare(nomDe(b), "fr", { sensitivity: "base" }));
    const SECTIONS = [
      { rang: "administrateur", titre: "Les administrateurs", icone: "equipe", creer: "Créer un administrateur",
        aide: "Tous les droits sur SA boutique — produits, rayons, slider, réglages et ses modérateurs. " +
          "Sans boutique, c'est un administrateur de BIZZOO.",
        vide: "Aucun administrateur." },
      { rang: "moderateur", titre: "Les modérateurs", icone: "equipe", creer: "Créer un modérateur",
        aide: "Les produits et les rayons de sa boutique, rien d'autre. Sans boutique, il travaille pour BIZZOO.",
        vide: "Aucun modérateur." },
      { rang: "superadministrateur", titre: "Les superadministrateurs", icone: "cle", creer: "Créer un superadministrateur",
        aide: "Ils tiennent toute l'enseigne : les boutiques, les réglages de BIZZOO et les comptes.",
        vide: "Aucun autre superadministrateur." },
    ];
    /* Les revendeurs ont leur écran : ceux qui y entrent le trouvent d'ici. */
    const voitRevendeurs = Supabase.estSuper() || Supabase.estAdminBizzoo() ||
      (Supabase.estAdmin() && !Supabase.estCompteEnseigne());
    let nbRevendeurs = null;
    if (voitRevendeurs) {
      try { nbRevendeurs = (await Store.listerRevendeurs("")).length; } catch (_) { nbRevendeurs = null; }
    }
    /* (3.63.0) LES COMPTES À VALIDER, en tête : créés par un
       administrateur de BIZZOO, ils attendent le superadministrateur. */
    const aValider = comptes.filter((c) => c.aValider);
    const adminBizzoo = Supabase.estAdminBizzoo() && !Supabase.estSuper();
    vue.innerHTML =
      (Supabase.estSuper() && aValider.length
        ? '<div class="carte">' +
            '<div class="carte-titre">' + UI.icone("horloge", "ic-sm") + " À valider (" +
              aValider.length + ")</div>" +
            '<p class="aide" style="margin:-4px 0 12px">Créés par un administrateur de BIZZOO. ' +
              "Ils ne peuvent rien faire tant que vous ne les avez pas validés.</p>" +
            aValider.map((c) =>
              '<div class="compte-a-valider">' + htmlLigne(c, false) +
                '<button type="button" class="btn btn-mini" data-valider="' + Utils.echapper(c.id) + '">' +
                  "Valider</button></div>").join("") +
          "</div>"
        : "") +
      (Store.rolesAttribuables().includes("livreur")
        ? '<a class="carte carte-livreurs" href="#/livreurs">' +
            '<div class="carte-titre">' + UI.icone("voiture", "ic-sm") + " Les livreurs (" +
              nbLivreurs + ")</div>" +
            '<p class="aide" style="margin:0">Ils se créent et se gèrent à part : touchez ici ' +
              "pour les voir, en ajouter un, et savoir qui a validé sa position.</p>" +
          "</a>"
        : "") +
      (Store.rolesAttribuables().includes("vendeur")
        ? '<a class="carte carte-livreurs" id="cp-vendeurs" href="#/vendeurs">' +
            '<div class="carte-titre">' + UI.icone("magasin", "ic-sm") + " Les vendeurs (" +
              nbVendeurs + ")</div>" +
            '<p class="aide" style="margin:0">Ceux des boutiques à vendeurs multiples se créent et se ' +
              "gèrent à part : touchez ici pour les voir, en ajouter un, modifier leur compte, " +
              "et suivre leurs ventes.</p>" +
          "</a>"
        : "") +
      /* (3.72.0) UNE SECTION PAR RANG : les administrateurs, les modérateurs
         (et les superadministrateurs pour qui les voit), chacun avec sa liste,
         sa recherche et son bouton ; les livreurs, les vendeurs et les
         revendeurs ont leur écran, une carte y mène. */
      (adminBizzoo
        ? '<p class="aide" style="margin:0 0 12px">Vous créez des <strong>modérateurs</strong>, ' +
            "pour une boutique ou pour BIZZOO. Chacun attend que le <strong>superadministrateur" +
            "</strong> le valide : d'ici là, vous pouvez le retoucher ou le retirer. Voici ceux " +
            "que vous avez créés.</p>"
        : "") +
      SECTIONS.map((sct) => {
        const membres = parRang(sct.rang);
        const peutCreer = Store.rolesAttribuables().includes(sct.rang);
        if (!membres.length && !peutCreer && sct.rang === "superadministrateur") return "";
        return '<div class="carte cp-section" id="cp-section-' + sct.rang + '">' +
          '<div class="carte-titre">' + UI.icone(sct.icone, "ic-sm") + " " + sct.titre + " (" + membres.length + ")</div>" +
          '<p class="aide" style="margin:-4px 0 12px">' + sct.aide + "</p>" +
          (membres.length > 5
            ? '<input type="search" class="recherche-liste cp-chercher" data-section="' + sct.rang + '" autocomplete="off" ' +
                'placeholder="Rechercher : nom, numéro, e-mail…" aria-label="Rechercher dans ' + Utils.echapper(sct.titre) + '">' +
              '<div class="aide recherche-liste-vide" hidden>Aucun compte ne correspond.</div>'
            : "") +
          (membres.length
            ? membres.map((c) => '<div class="cp-trouvable" data-cherche="' +
                Utils.echapper(Utils.sansAccent([c.nom, c.email, c.tel].filter(Boolean).join(" "))) + '">' +
                htmlLigne(c, c.id === moi) + "</div>").join("")
            : '<p class="aide" style="margin:0">' + sct.vide + "</p>") +
          (peutCreer
            ? '<button type="button" class="btn btn-clair" data-creer-rang="' + sct.rang + '" style="margin-top:12px">' +
                UI.icone("plus") + sct.creer + "</button>"
            : "") +
        "</div>";
      }).join("") +
      (voitRevendeurs
        ? '<a class="carte carte-livreurs" id="cp-revendeurs" href="#/revendeurs">' +
            '<div class="carte-titre">' + UI.icone("promo", "ic-sm") + " Les revendeurs" +
              (nbRevendeurs === null ? "" : " (" + nbRevendeurs + ")") + "</div>" +
            '<p class="aide" style="margin:0">Ils achètent au prix revendeur : ils se créent, se valident ' +
              "et se gèrent dans leur propre écran. Touchez ici.</p>" +
          "</a>"
        : "") +
      (comptes.length || Store.rolesAttribuables().some((r) => ["moderateur", "administrateur", "superadministrateur"].includes(r))
        ? '<div class="btn-rangee"><button type="button" class="btn" id="cp-nouveau">' +
            UI.icone("plus") + "Créer un compte</button></div>"
        : "") +
      '<div class="carte">' +
        '<div class="carte-titre">Bon à savoir</div>' +
        '<p class="aide" style="margin:0">Touchez le crayon d\'un compte pour changer son rôle, ' +
          "lui retirer ou lui rendre le droit de modifier les produits, lui redonner un " +
          "mot de passe, le désactiver ou le supprimer. Un modérateur sans ce droit " +
          "(<strong>ajout seulement</strong>) continue d'ajouter des produits mais ne peut " +
          "plus retoucher ni supprimer ceux du catalogue. Un compte " +
          "<strong>désactivé</strong> garde son adresse mais ne peut plus rien modifier ; " +
          "un compte <strong>supprimé</strong> disparaît pour de bon. " +
          "Votre propre compte n'apparaît pas : on ne se retire pas ses propres droits. " +
          "Ni le compte qui <strong>vous a créé</strong> (ni ceux au-dessus de lui) : " +
          "vous ne pouvez pas modifier ses droits.</p>" +
      "</div>";

    const nouveau = UI.$("#cp-nouveau", vue);
    if (nouveau) nouveau.onclick = () => ouvrirCreation(() => afficher(vue), false);
    for (const b of UI.$$("[data-creer-rang]", vue)) {
      b.onclick = () => ouvrirCreation(() => afficher(vue), false, false, b.dataset.creerRang);
    }
    for (const champ of UI.$$(".cp-chercher", vue)) {
      champ.oninput = () => {
        const section = champ.closest(".cp-section");
        const q = Utils.sansAccent(champ.value.trim());
        let vus = 0;
        for (const el of UI.$$(".cp-trouvable", section)) {
          el.hidden = !!q && !el.dataset.cherche.includes(q);
          if (!el.hidden) vus++;
        }
        UI.$(".recherche-liste-vide", section).hidden = vus > 0;
      };
    }
    for (const bouton of UI.$$("[data-valider]", vue)) {
      bouton.onclick = async () => {
        bouton.disabled = true;
        try {
          await Store.majCompte(bouton.dataset.valider, { actif: true });
          UI.toast("Compte validé", "ok");
          afficher(vue);
        } catch (err) {
          UI.toast(err.message, "err");
          bouton.disabled = false;
        }
      };
    }
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
          /* UN COMPTE DE BIZZOO N'EST PAS L'ADMINISTRATEUR D'UNE BOUTIQUE :
             l'aide de son rang le décrirait à tort. Ce qui dit ce qu'il
             peut faire, ce sont ses interrupteurs — on les lui montre. */
          (role ? "<br>Rôle : <strong>" + Utils.echapper(nomRole(role)) +
            (Supabase.estCompteEnseigne() ? " de BIZZOO" : "") + "</strong> — " +
            Utils.echapper(Supabase.estCompteEnseigne()
              ? "toutes les boutiques" + droitsResumes(profil)
              : Store.ROLES[role].aide) : "") +
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
          UI.icone("check") + "Enregistrer</button>" +
        '<div id="mc-resultat"></div>' +
      "</div>" +

      '<div class="carte">' +
        '<div class="carte-titre">Quitter</div>' +
        '<button type="button" class="btn btn-clair" id="mc-deconnexion">Se déconnecter</button>' +
      "</div>" + DroitsCompte.carte(true);

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

  /* ---------- Les livreurs (écran à part) ----------
     Créés par leur propre bouton, listés à part, avec ce qui compte pour
     eux : pour quelle boutique ils portent, leur numéro, et s'ils ont
     VALIDÉ leur compte en enregistrant leur position. */

  async function livreurs(vue) {
    UI.entete({ titre: "Livreurs", retour: true, sous: "Qui porte, et d'où" });
    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>Lecture des livreurs…</div>';
    /* DEUX REGARDS (3.59.0). Le superadministrateur et l'administrateur
       de BIZZOO GÈRENT : tous les livreurs, leur fiche, « Créer un
       livreur ». L'administrateur d'une boutique REGARDE ceux qui lui
       sont assignés : les livreurs de sa boutique, et ceux de BIZZOO qui
       portent pour toutes — sans rien modifier, la base ne le lui permet
       pas. */
    const gere = Supabase.estSuper() || Supabase.estAdminBizzoo();
    /* (3.59.0) L'ADMINISTRATEUR D'UNE BOUTIQUE CRÉE ET GÈRE LES SIENS — les
       livreurs de SA boutique. Ceux de BIZZOO, il les voit sans y toucher. */
    const chezMoi = !gere && Supabase.estAdmin() && !Supabase.estCompteEnseigne();
    let comptes, positions;
    try {
      const deBizzoo = () => Store.listerLivreurs().then((l) => l.map((c) => ({
        id: c.id, email: c.email, nom: c.nom, tel: c.tel, actif: c.actif, role: "livreur",
        boutiqueId: c.bizzoo ? "" : Supabase.boutiqueDuCompte(), bizzoo: c.bizzoo })));
      [comptes, positions] = await Promise.all([
        gere ? Store.listerComptes()
          : chezMoi
            ? Promise.all([Store.listerComptes(), deBizzoo()]).then(([miens, tous]) =>
                miens.filter((c) => c.role === "livreur")
                  .concat(tous.filter((c) => c.bizzoo)))
            : deBizzoo(),
        Store.positionsLivreurs()]);
    } catch (err) {
      vue.innerHTML = '<div class="carte"><div class="carte-titre">Livreurs indisponibles</div>' +
        '<p class="aide" style="margin:0">' + Utils.echapper(err.message) + "</p></div>";
      return;
    }
    /* (3.72.0) Par ordre alphabétique : on cherche un nom, pas un rang. */
    const nomDe = (c) => String(c.nom || c.email || c.tel || "");
    const liste = comptes.filter((c) => c.role === "livreur")
      .sort((a, b) => nomDe(a).localeCompare(nomDe(b), "fr", { sensitivity: "base" }));
    const valides = positions ? liste.filter((c) => positions[c.id]).length : 0;
    const ligne = (c) => {
      const p = positions && positions[c.id];
      /* La position d'un livreur de BIZZOO n'est pas montrée à une
         boutique : il porte pour toutes, sa boutique c'est l'enseigne. */
      const etat = !positions ? ""
        : !gere && c.bizzoo
          ? '<div class="livreur-position">' + UI.icone("voiture", "ic-sm") +
              " Livreur de BIZZOO : il porte pour toutes les boutiques.</div>"
        : p
          ? '<div class="livreur-position livreur-position-ok">' + UI.icone("check", "ic-sm") +
              " Position validée le " + Utils.echapper(Utils.fmtDateHeure(p.enregistre_le)) +
              (p.adresse ? " — " + Utils.echapper(p.adresse) : "") +
              ' · <a href="https://www.google.com/maps?q=' + Number(p.latitude) + "," +
                Number(p.longitude) + '" target="_blank" rel="noopener">voir sur la carte</a></div>'
          : '<div class="livreur-position livreur-position-manque">' + UI.icone("alerte", "ic-sm") +
              " Position pas encore validée : aucune course ne peut lui être confiée.</div>";
      /* (3.64.0) Le tricycle se dit : c'est à lui qu'iront les gros colis. */
      const vehicule = c.vehicule === "tricycle"
        ? '<div class="livreur-position">' + UI.icone("voiture", "ic-sm") +
            " En tricycle : il reçoit aussi les commandes de gros colis.</div>"
        : "";
      return '<div class="livreur-bloc" data-cherche="' +
        Utils.echapper(Utils.sansAccent([c.nom, c.email, c.tel].filter(Boolean).join(" "))) + '">' + (gere || (chezMoi && !c.bizzoo) ? htmlLigne(c, false) : ligneLecture(c)) +
        etat + vehicule + "</div>";
    };
    vue.innerHTML =
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("voiture", "ic-sm") + " Les livreurs (" + liste.length + ")</div>" +
        '<p class="aide" style="margin:-4px 0 12px">Le livreur ne voit que les courses qu\'on ' +
          "lui confie, sans aucun montant. Il porte pour une boutique, ou pour " +
          "<strong>BIZZOO</strong> et alors pour toutes. Il <strong>valide son compte en " +
          "enregistrant sa position</strong> à sa première connexion" +
          (positions ? " — " + valides + " sur " + liste.length + " l'ont fait" : "") + ".</p>" +
        (liste.length > 5
          ? '<input type="search" class="recherche-liste" id="lv-chercher" autocomplete="off" ' +
              'placeholder="Rechercher un livreur : nom, numéro…" aria-label="Rechercher un livreur">' +
            '<div class="aide recherche-liste-vide" id="lv-aucun" hidden>Aucun livreur ne correspond.</div>'
          : "") +
        (liste.length ? liste.map(ligne).join("")
          : '<p class="aide" style="margin:0">Aucun livreur pour l\'instant.</p>') +
        (gere || chezMoi
          ? '<button type="button" class="btn" id="lv-nouveau" style="margin-top:14px">' +
              UI.icone("plus") + "Créer un livreur</button>" +
            (chezMoi
              ? '<p class="aide" style="margin:10px 0 0">Vous créez les livreurs de votre boutique. ' +
                  "Un livreur de BIZZOO, qui porte pour toutes, se demande à BIZZOO.</p>"
              : "")
          : '<p class="aide" style="margin:12px 0 0">Un nouveau livreur se demande à BIZZOO : ' +
              "le superadministrateur ou un administrateur de BIZZOO le crée.</p>") +
      "</div>";
    const chercher = UI.$("#lv-chercher", vue);
    if (chercher) {
      chercher.oninput = () => {
        const q = Utils.sansAccent(chercher.value.trim());
        let vus = 0;
        for (const bloc of UI.$$(".livreur-bloc[data-cherche]", vue)) {
          bloc.hidden = !!q && !bloc.dataset.cherche.includes(q);
          if (!bloc.hidden) vus++;
        }
        UI.$("#lv-aucun", vue).hidden = vus > 0;
      };
    }
    if (!gere && !chezMoi) return;
    UI.$("#lv-nouveau", vue).onclick = () => ouvrirCreation(() => livreurs(vue), true);
    for (const bouton of UI.$$("[data-compte]", vue)) {
      bouton.onclick = () => {
        const compte = liste.find((c) => c.id === bouton.dataset.compte);
        if (compte) ouvrirFiche(compte, () => livreurs(vue));
      };
    }
  }

  /** Une ligne à lire seulement : le nom, le numéro pour l'appeler. */
  function ligneLecture(c) {
    const tel = String(c.tel || "").trim();
    return (
      '<div class="compte-ligne">' +
        "<div><strong>" + Utils.echapper(c.nom || c.email || "Livreur") + "</strong>" +
          (c.actif === false ? ' <small class="compte-inactif">(désactivé)</small>' : "") +
          (tel ? '<div class="aide" style="margin:2px 0 0"><a href="tel:' +
            Utils.echapper(tel.replace(/[^\d+]/g, "")) + '">' + Utils.echapper(tel) + "</a></div>" : "") +
        "</div>" +
      "</div>"
    );
  }

  /* ---------- Le livreur valide son compte ----------
     À la connexion, avant tout le reste : sa position (la localisation du
     téléphone) et son adresse. La base refuse de lui confier une course
     tant qu'il ne l'a pas fait. */

  function validerPosition(vue, suite) {
    UI.entete({ titre: "Validez votre compte" });
    vue.innerHTML =
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("carte", "ic-sm") + " Enregistrez votre position</div>" +
        '<p class="aide" style="margin:0 0 12px">Pour recevoir des courses, votre compte de ' +
          "livreur doit être validé : indiquez votre adresse, puis activez la localisation " +
          "de votre téléphone.</p>" +
        UI.champTexte({ id: "vp-adresse", label: "Votre adresse", obligatoire: true,
          placeholder: "Quartier, repère… ex. Akpakpa, face au marché",
          aide: "C'est ce qui permet de vous situer." }) +
        '<button type="button" class="btn" id="vp-activer">' + UI.icone("carte") +
          "Activer ma position</button>" +
        '<div id="vp-etat"></div>' +
      "</div>" +
      '<div class="carte"><a class="btn btn-clair" href="#/compte">' + UI.icone("personne") +
        "Mon compte</a></div>";
    const etat = UI.$("#vp-etat", vue);
    const dire = (texte, err) => {
      etat.innerHTML = '<p class="aide" style="margin:10px 0 0' + (err ? ";color:var(--rouge)" : "") +
        '">' + Utils.echapper(texte) + "</p>";
    };
    const bouton = UI.$("#vp-activer", vue);
    bouton.onclick = () => {
      const adresse = UI.$("#vp-adresse", vue).value.trim();
      if (adresse.length < 3) {
        dire("Indiquez d'abord votre adresse : quartier, repère.", true);
        UI.$("#vp-adresse", vue).focus();
        return;
      }
      if (!navigator.geolocation) {
        dire("Ce téléphone ne permet pas de relever la position.", true);
        return;
      }
      bouton.disabled = true;
      dire("Relevé de la position…");
      navigator.geolocation.getCurrentPosition(async (pos) => {
        try {
          await Store.enregistrerMaPosition({ latitude: pos.coords.latitude,
            longitude: pos.coords.longitude, adresse, precision: pos.coords.accuracy });
          UI.toast("Compte validé : votre position est enregistrée.", "ok");
          suite();
        } catch (err) {
          dire(err.message, true);
          bouton.disabled = false;
        }
      }, (err) => {
        dire(err.code === 1
          ? "Autorisation refusée : autorisez la localisation pour BIZZOO Admin dans les réglages du téléphone, puis réessayez."
          : "Position introuvable : activez la localisation (GPS) et sortez à l'air libre, puis réessayez.", true);
        bouton.disabled = false;
      }, { enableHighAccuracy: true, timeout: 20000, maximumAge: 0 });
    };
  }

  return { afficher, monCompte, livreurs, validerPosition,
    /* (3.70.0) Le compte d'un vendeur, depuis l'écran « Vendeurs ». */
    creerVendeur: (apres) => ouvrirCreation(apres, false, true),
    /* (3.72.0) La fiche du compte d'un vendeur, depuis l'écran « Vendeurs ». */
    ficheCompte: (compte, apres) => ouvrirFiche(compte, apres) };
})();
