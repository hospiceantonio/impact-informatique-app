/* =========================================================
   BIZZOO — les écrans du compte client

   Trois écrans, et une règle qui les traverse : on ne ferme
   jamais la porte du magasin. Un client peut regarder, chercher,
   remplir son panier sans compte ; le compte lui apporte de
   retrouver ses commandes sur n'importe quel téléphone, de ne
   plus retaper ses coordonnées, et — plus tard — de donner son
   avis et d'ouvrir une réclamation.
   ========================================================= */

const VueCompte = (() => {

  /* Où revenir une fois connecté. Un client qu'on envoie se connecter
     depuis son panier doit retrouver son panier, pas l'accueil. */
  let retour = "";
  const revenirVers = (adresse) => { retour = adresse || ""; };

  function repartir() {
    const ou = retour || "#/compte";
    retour = "";
    location.hash = ou;
  }

  /* ---------- Connexion ---------- */

  /* ---------- Ce qui vivait dans l'onglet « Infos » ----------
     La barre du bas de la DA n'a que quatre onglets : les infos de
     BIZZOO, son contact WhatsApp et l'actualisation du catalogue
     descendent ici, sous « Compte » — connecté ou non, car on peut
     vouloir écrire à BIZZOO sans avoir de compte. */
  function carteBizzoo() {
    const maison = Catalogue.enseigne();
    const wa = maison.whatsapp
      ? Utils.lienWhatsApp(maison.whatsapp,
          "Bonjour " + (maison.nom || "BIZZOO") + ", je souhaite un renseignement.", maison.indicatif)
      : "";
    return (
      '<div class="carte cp-bizzoo">' +
        '<a class="ligne-info" href="#/infos">' +
          '<span class="rond-bleu">' + UI.icone("infos") + "</span>" +
          "<span><strong>À propos de BIZZOO</strong><br><small>Contacts, réseaux, " +
            "installer l'application</small></span>" +
          UI.icone("chevron", "ic-sm") +
        "</a>" +
        (wa
          ? '<a class="ligne-info" target="_blank" rel="noopener" href="' + Utils.echapper(wa) + '">' +
              '<span class="rond-wa">' + UI.icone("whatsapp") + "</span>" +
              "<span><strong>Nous contacter</strong><br><small>Écrire à BIZZOO sur WhatsApp</small></span>" +
              UI.icone("chevron", "ic-sm") +
            "</a>"
          : "") +
        '<button type="button" class="ligne-info" id="cp-actualiser">' +
          '<span class="rond-bleu">' + UI.icone("actualiser") + "</span>" +
          "<span><strong>Actualiser le catalogue</strong><br><small>Les derniers prix et " +
            "produits des boutiques</small></span>" +
        "</button>" +
      "</div>" + DroitsCompte.carte(Compte.connecte())
    );
  }

  function brancherCarteBizzoo() {
    const bouton = UI.$("#cp-actualiser");
    if (!bouton) return;
    bouton.onclick = async () => {
      bouton.disabled = true;
      const rond = bouton.querySelector(".ic");
      if (rond) rond.classList.add("tourne-seul");
      let change = false;
      try { change = await Live.verifier(); } catch (_) { /* hors connexion */ }
      if (rond) rond.classList.remove("tourne-seul");
      bouton.disabled = false;
      UI.toast(change ? "Catalogue mis à jour" : "Catalogue déjà à jour", "ok");
    };
  }

  /* LE NUMÉRO D'ABORD (3.59.0). Le SMS ouvert, on entre avec son numéro,
     son mot de passe ET un code reçu par SMS. Pas d'adresse e-mail à
     avoir — au Bénin, beaucoup de clients ont un numéro et pas de
     courriel. L'e-mail, facultatif, s'ajoute dans « Mon compte » : c'est
     la seconde porte, e-mail et mot de passe, pour le jour où le
     téléphone n'est pas là.

     Le SMS fermé, rien ne change : l'e-mail et le mot de passe reviennent
     devant. LES DEUX VERSIONS SONT DESSINÉES, l'une marquée « data-sms »,
     l'autre « data-sans-sms » et cachée ; « masquerSiSmsFerme » garde la
     bonne — et, dans le doute, c'est le SMS. */
  function connexion(vue) {
    UI.entete({ titre: "Se connecter", retour: true });

    vue.innerHTML =
      '<div class="carte" data-sms>' + porteNumero() + "</div>" +
      '<div class="carte" data-sms>' +
        '<p class="aide" style="margin:0">Pas accès à votre téléphone, ou compte ouvert ' +
          'avec une adresse e-mail ? <a href="#/connexion-email" id="cp-ancien">Entrer avec ' +
          "mon e-mail</a></p>" +
      "</div>" +
      '<div class="carte" data-sans-sms hidden>' + formulaireEmail() + "</div>" +
      '<div class="carte">' +
        '<div class="carte-titre">Pas encore de compte ?</div>' +
        '<p class="aide" style="margin:0 0 10px">Avec un compte, vous retrouvez vos ' +
          "commandes depuis n'importe quel téléphone.</p>" +
        '<a class="btn btn-clair" href="#/inscription">' + UI.icone("compte") +
          "Créer mon compte</a>" +
      "</div>" +
      carteBizzoo();
    brancherCarteBizzoo();
    brancherPorteNumero(vue);
    brancherEmail(vue);
    Compte.masquerSiSmsFerme(vue);
  }

  /* ---------- La seconde porte : l'e-mail ----------
     Le téléphone n'est pas là — perdu, déchargé, hors réseau : l'e-mail
     et le mot de passe du compte suffisent, SANS CODE. C'est le choix de
     BIZZOO : une porte de secours qu'un code envoyé au téléphone absent
     fermerait aussitôt. Encore faut-il avoir ajouté son e-mail dans
     « Mon compte ».

     Un compte d'avant, ouvert avec un e-mail et sans numéro, passe aussi
     par ici — et confirme alors son numéro, une fois. */
  function connexionEmail(vue) {
    UI.entete({ titre: "Avec mon e-mail", retour: true });

    vue.innerHTML =
      '<div class="carte" data-sms>' +
        '<p class="aide" style="margin:0">Votre téléphone n\'est pas avec vous ? Entrez ' +
          "avec l'e-mail ajouté dans « Mon compte » et votre mot de passe — sans code. " +
          "Un compte ouvert avec un e-mail, sans numéro, confirmera son numéro une fois.</p>" +
      "</div>" +
      '<div class="carte">' + formulaireEmail() + "</div>" +
      '<div class="carte" data-sms>' +
        '<p class="aide" style="margin:0">Votre téléphone est là ? ' +
          '<a href="#/connexion">Entrer avec mon numéro</a></p>' +
      "</div>";
    brancherEmail(vue);
    Compte.masquerSiSmsFerme(vue);
  }

  /** Le formulaire e-mail et mot de passe — le même aux deux portes. */
  function formulaireEmail() {
    return (
      '<div class="champ"><label for="cp-email">Votre e-mail</label>' +
        '<input id="cp-email" type="email" inputmode="email" autocomplete="email" ' +
          'placeholder="vous@exemple.com"></div>' +
      '<div class="champ"><label for="cp-mdp">Mot de passe</label>' +
        '<input id="cp-mdp" type="password" autocomplete="current-password" ' +
          'placeholder="Votre mot de passe"></div>' +
      '<button type="button" class="btn" id="cp-entrer">' + UI.icone("check") +
        "Se connecter</button>" +
      '<p class="aide" style="margin:10px 0 0">' +
        '<a href="#/mot-de-passe">Mot de passe oublié ?</a></p>'
    );
  }

  function brancherEmail(vue) {
    const bouton = UI.$("#cp-entrer", vue);
    if (!bouton) return;
    const entrer = async () => {
      const email = UI.$("#cp-email", vue).value.trim();
      const mdp = UI.$("#cp-mdp", vue).value;
      if (!email || !mdp) return UI.toast("Votre e-mail et votre mot de passe.", "alerte");
      bouton.disabled = true;
      try {
        const r = await Compte.connecter(email, mdp);
        /* Le mot de passe est bon, mais le compte n'a pas encore de
           numéro confirmé : il n'entre qu'après le code. « Annuler » le
           laisse dehors — la session qui attendait est oubliée. */
        if (r && r.numero) {
          confirmerNumero(vue, { tel: r.tel, annuler: true, apres: repartir });
          return;
        }
        UI.toast("Bonjour !");
        repartir();
      } catch (err) {
        UI.toast(err.message, "alerte");
        bouton.disabled = false;
      }
    };
    bouton.addEventListener("click", entrer);
    UI.$("#cp-mdp", vue).addEventListener("keydown", (e) => { if (e.key === "Enter") entrer(); });
  }

  /* ---------- Le numéro, et sa porte ---------- */

  /** Le champ du numéro, avec son indicatif — le même sur tous les écrans. */
  function champNumero(valeur) {
    return (
      '<div class="champ"><label for="cp-tel">Votre numéro</label>' +
        '<div class="cp-tel-ligne"><span class="cp-indicatif">+229</span>' +
          '<input id="cp-tel" type="tel" inputmode="tel" autocomplete="tel-national" ' +
            'placeholder="01 97 12 15 96" value="' + Utils.echapper(valeur || "") + '"></div></div>'
    );
  }

  /** Entrer avec son numéro : le numéro, le mot de passe, puis le code. */
  function porteNumero() {
    return (
      '<div class="carte-titre">' + UI.icone("telephone", "ic-sm") + " Avec mon numéro</div>" +
      '<p class="aide" style="margin:0 0 10px">Votre numéro et votre mot de passe, puis le ' +
        "code que nous vous envoyons par SMS.</p>" +
      champNumero("") +
      '<div class="champ"><label for="cp-mdp-tel">Mot de passe</label>' +
        '<input id="cp-mdp-tel" type="password" autocomplete="current-password" ' +
          'placeholder="Votre mot de passe"></div>' +
      '<button type="button" class="btn" id="cp-envoyer">' + UI.icone("check") +
        "Se connecter</button>" +
      '<p class="aide" style="margin:10px 0 0">' +
        '<a href="#/mot-de-passe" id="cp-oubli">Mot de passe oublié, ou pas encore de ' +
          "mot de passe ?</a></p>"
    );
  }

  function brancherPorteNumero(vue) {
    const bouton = UI.$("#cp-envoyer", vue);
    if (!bouton) return;
    const envoyer = async () => {
      const tel = UI.$("#cp-tel", vue).value;
      const mdp = UI.$("#cp-mdp-tel", vue).value;
      if (Compte.telNational(tel).length < 8) return UI.toast("Tapez votre numéro.", "alerte");
      if (!mdp) return UI.toast("Tapez votre mot de passe.", "alerte");
      bouton.disabled = true;
      try {
        const r = await Compte.connecterTelephone(tel, mdp);
        ecranCode(vue, {
          tel,
          titre: "Se connecter",
          renvoyer: r.renvoyer,
          valider: (code) => Compte.confirmerCodeConnexion(tel, code),
          apres: (res) => apresEntree(vue, {}, res),
        });
      } catch (err) {
        UI.toast(err.message, "alerte");
        bouton.disabled = false;
      }
    };
    bouton.addEventListener("click", envoyer);
    for (const id of ["#cp-tel", "#cp-mdp-tel"]) {
      UI.$(id, vue).addEventListener("keydown", (e) => { if (e.key === "Enter") envoyer(); });
    }
  }

  /**
   * Juste entré par son numéro. Ce qui peut rester à faire, dans l'ordre :
   * le nom que la fiche n'a pas, la demande de revendeur choisie à
   * l'inscription — puis repartir d'où l'on venait.
   *
   * « Créer mon compte » avec un numéro qui en a déjà un ouvre CE compte :
   * on le dit, plutôt que d'annoncer une naissance qui n'a pas eu lieu.
   */
  async function apresEntree(vue, o, r) {
    const nouveau = !!(r && r.nouveau);
    let moi = Compte.moi();
    if (o.nom && moi && !moi.nom) {
      try { moi = await Compte.enregistrerNom(o.nom); } catch (_) { /* demandé plus bas */ }
    }
    let demandee = false;
    /* Une demande déjà en cours, ou un statut déjà acquis, ne se refait
       pas : on écraserait le message que BIZZOO est en train de lire. */
    if (o.revendeur && !["validee", "en_attente"].includes(Compte.etatRevendeur())) {
      try {
        await Compte.demanderRevendeur(o.revendeur.message, o.revendeur.position);
        demandee = true;
      } catch (_) {
        UI.toast("Votre compte est ouvert, mais la demande de revendeur n'est pas " +
          "partie : refaites-la depuis Mon compte.", "alerte");
      }
    }
    /* La publicité : la naissance du compte — le module ne la compte
       qu'une fois, et jamais pour un retour —, puis la demande partie. */
    Pixel.entreeParCode(r && r.utilisateur, o.revendeur ? "revendeur" : "client");
    if (demandee) Pixel.demandeRevendeur();
    const mot = o.inscription && !nouveau ? "Ce numéro avait déjà son compte : vous y êtes."
      : demandee ? "Bienvenue ! Votre demande est partie."
      : nouveau ? "Bienvenue !" : "Bonjour !";
    const finir = () => { UI.toast(mot); repartir(); };
    /* Un compte sans nom — né à la porte « Se connecter », qui n'en
       demande pas : on le demande maintenant, une fois. Un compte de
       l'équipe n'a pas de fiche client, et rien à remplir ici. */
    moi = Compte.moi();
    if (moi && !String(moi.nom || "").trim()) {
      demanderNom(vue, finir);
      return;
    }
    finir();
  }

  /** Le nom d'un compte qui vient de naître par SMS. */
  function demanderNom(vue, suite) {
    UI.entete({ titre: "Votre nom" });
    vue.innerHTML =
      '<div class="carte" id="cp-nommer">' +
        '<div class="carte-titre">Comment vous appelez-vous ?</div>' +
        '<p class="aide" style="margin:0 0 10px">Votre nom accompagne vos commandes : ' +
          "c'est à lui que la boutique et le livreur vous reconnaissent.</p>" +
        '<div class="champ"><label for="cp-nom">Votre nom</label>' +
          '<input id="cp-nom" type="text" autocomplete="name" placeholder="Nom et prénom"></div>' +
        '<button type="button" class="btn" id="cp-nommer-ok">' + UI.icone("check") +
          "Continuer</button>" +
      "</div>" +
      '<p class="aide" style="text-align:center"><a href="#" id="cp-nommer-tard">Plus tard</a></p>';

    const champ = UI.$("#cp-nom", vue);
    const bouton = UI.$("#cp-nommer-ok", vue);
    champ.focus();
    const valider = async () => {
      const nom = champ.value.trim();
      if (!nom) return UI.toast("Votre nom, s'il vous plaît.", "alerte");
      bouton.disabled = true;
      try {
        await Compte.enregistrerNom(nom);
        suite();
      } catch (err) {
        UI.toast(err.message, "alerte");
        bouton.disabled = false;
      }
    };
    bouton.addEventListener("click", valider);
    champ.addEventListener("keydown", (e) => { if (e.key === "Enter") valider(); });
    UI.$("#cp-nommer-tard", vue).addEventListener("click", (e) => { e.preventDefault(); suite(); });
  }

  /* ---------- Confirmer son numéro, une fois ----------

     Pour un compte ouvert avec un e-mail, avant le SMS. Deux chemins y
     mènent : la connexion par e-mail — la session attend alors, voir
     Compte.connecter —, et un compte déjà connecté sur ce téléphone, à
     qui « Mon compte » et la commande le demandent. Ensuite, son numéro
     lui suffit pour entrer.

     Les commandes passées avec ce numéro avant le compte le rejoignent
     dans la foulée : c'est ce que la vérification a toujours ouvert. */
  function confirmerNumero(vue, o) {
    UI.entete({ titre: "Confirmer mon numéro", retour: true });
    vue.innerHTML =
      '<div class="carte" id="cp-confirmer-numero">' +
        '<div class="carte-titre">' + UI.icone("telephone", "ic-sm") +
          " Une étape, une seule fois</div>" +
        '<p class="aide" style="margin:0 0 10px">BIZZOO ouvre désormais les comptes avec un ' +
          "numéro, un mot de passe et un code reçu par SMS. Confirmez celui de votre compte : " +
          "la prochaine fois, vous entrerez avec lui.</p>" +
        champNumero(o.tel || "") +
        '<button type="button" class="btn" id="cp-envoyer">' + UI.icone("telephone") +
          "Recevoir mon code</button>" +
      "</div>" +
      (o.annuler
        ? '<p class="aide" style="text-align:center">' +
            '<a href="#/connexion" id="cp-renoncer">Annuler</a></p>'
        : "");

    const renoncer = UI.$("#cp-renoncer", vue);
    if (renoncer) renoncer.addEventListener("click", () => Compte.abandonnerAttente());

    const bouton = UI.$("#cp-envoyer", vue);
    const envoyer = async () => {
      const tel = UI.$("#cp-tel", vue).value;
      if (Compte.telNational(tel).length < 8) return UI.toast("Tapez votre numéro.", "alerte");
      bouton.disabled = true;
      try {
        await Compte.demanderCodeNumero(tel);
        ecranCode(vue, {
          tel,
          titre: "Confirmer mon numéro",
          renvoyer: () => Compte.demanderCodeNumero(tel),
          valider: (code) => Compte.confirmerCodeNumero(tel, code),
          apres: async () => {
            let combien = 0;
            try { combien = await Compte.rattacherMesCommandes(); }
            catch (_) { /* Mon compte le reproposera */ }
            UI.toast("Numéro confirmé." + (combien > 0
              ? " " + combien + " commande" + (combien > 1 ? "s" : "") + " retrouvée" +
                (combien > 1 ? "s" : "") + "."
              : ""));
            o.apres();
          },
        });
      } catch (err) {
        UI.toast(err.message, "alerte");
        bouton.disabled = false;
      }
    };
    bouton.addEventListener("click", envoyer);
    UI.$("#cp-tel", vue).addEventListener("keydown", (e) => { if (e.key === "Enter") envoyer(); });
  }

  /* ---------- Inscription ---------- */

  /* ---------- Où se trouve le commerce ----------

     Le même bloc sert deux fois : à l'inscription, et quand un client
     déjà là demande à devenir revendeur. On le fabrique donc une fois,
     avec un préfixe d'identifiants, plutôt que de le recopier — deux
     copies finissent toujours par diverger.

     LES DEUX SONT OBLIGATOIRES : un revendeur VALIDE SON COMPTE en
     activant sa position.
       l'adresse écrite, qui est ce qui permet vraiment de trouver au
         Bénin — un quartier, un repère ;
       la position du téléphone (géolocalisation), relevée par le bouton.

     Sans elles, la demande ne part pas — et BIZZOO ne pourrait pas la
     valider : la base le refuse. */

  /** La position est-elle complète : relevée ET une adresse écrite ? */
  const positionComplete = (p) => !!p && p.latitude !== null && p.latitude !== undefined &&
    p.longitude !== null && p.longitude !== undefined && String(p.adresse || "").trim().length >= 3;
  const MANQUE_POSITION = "Activez votre position (bouton « Activer ma position ») et indiquez " +
    "votre adresse : c'est ce qui valide votre compte revendeur.";

  function blocPosition(p, valeurs) {
    const v = valeurs || {};
    return (
      '<div class="champ"><label for="' + p + '-adresse">Où se trouve votre commerce</label>' +
        '<input id="' + p + '-adresse" type="text" maxlength="200" ' +
          'placeholder="Quartier, repère… ex. Dantokpa, face à la pharmacie" value="' +
          Utils.echapper(v.adresse || "") + '">' +
        '<p class="aide" style="margin:6px 0 0">C\'est ce qui permet de vous trouver.</p>' +
      "</div>" +
      '<button type="button" class="btn btn-clair" id="' + p + '-relever">' +
        UI.icone("itineraire") + "Activer ma position</button>" +
      '<div id="' + p + '-etat"></div>'
    );
  }

  /**
   * Branche le bloc, et rend une fonction qui lit ce qu'il contient.
   * Les coordonnées vivent ici, dans cette fermeture : les poser dans
   * des champs cachés reviendrait à les laisser retaper à la main, et
   * une position tapée à la main n'en est pas une.
   */
  function brancherPosition(vue, p, valeurs) {
    let latitude = (valeurs && valeurs.latitude) || null;
    let longitude = (valeurs && valeurs.longitude) || null;

    const zone = UI.$("#" + p + "-etat", vue);
    const dire = (texte, type) => {
      if (!zone) return;
      zone.innerHTML = texte
        ? '<p class="aide" style="margin:8px 0 0' +
            (type === "err" ? ";color:var(--rouge)" : "") + '">' +
            Utils.echapper(texte) + "</p>"
        : "";
    };
    const direPosee = (precision) => dire(
      "Position enregistrée" +
      (precision ? " (à environ " + precision + " m près)" : "") + ".");

    if (latitude !== null && longitude !== null) direPosee(0);

    const bouton = UI.$("#" + p + "-relever", vue);
    if (bouton) {
      bouton.addEventListener("click", async () => {
        bouton.disabled = true;
        dire("Relevé de la position…");
        try {
          const pos = await Compte.positionActuelle();
          latitude = pos.latitude;
          longitude = pos.longitude;
          direPosee(pos.precision);
        } catch (err) {
          dire(err.message, "err");
        }
        bouton.disabled = false;
      });
    }

    const lien = UI.$("#" + p + "-lien", vue);
    if (lien) {
      lien.addEventListener("input", () => {
        const pos = Compte.positionDuLien(lien.value);
        if (!pos) return;
        latitude = pos.latitude;
        longitude = pos.longitude;
        dire("Position lue dans le lien.");
      });
    }

    return () => {
      const champ = UI.$("#" + p + "-adresse", vue);
      return {
        adresse: champ ? champ.value.trim() : "",
        latitude, longitude,
      };
    };
  }

  function inscription(vue) {
    UI.entete({ titre: "Créer mon compte", retour: true });

    /* Deux sortes de comptes, et le choix se fait ici — pas plus tard,
       dans un réglage que personne ne trouve. Un revendeur qui s'inscrit
       comme client ordinaire paierait le prix de la vitrine sans savoir
       qu'il pouvait faire autrement. */
    vue.innerHTML =
      '<div class="carte">' +
        '<div class="carte-titre">Vous achetez…</div>' +
        '<div class="cp-choix">' +
          choixCompte("client", "sacoche", "Pour moi",
            "Le prix affiché en boutique.") +
          choixCompte("revendeur", "magasin", "Pour revendre",
            "Le prix BIZZOO, après validation.") +
        "</div>" +
        '<div id="cp-revendeur" hidden>' +
          '<div class="champ"><label for="cp-message">Votre commerce</label>' +
            '<textarea id="cp-message" rows="2" maxlength="300" ' +
              'placeholder="Nom de votre boutique et ce que vous revendez"></textarea></div>' +
          blocPosition("cp-pos") +
          '<p class="aide" style="margin:10px 0 0">BIZZOO regarde votre demande et ' +
            "vous répond. En attendant, vous commandez au prix habituel.</p>" +
        "</div>" +
      "</div>" +
      /* LE NOM, LE NUMÉRO, UN MOT DE PASSE — puis le code : c'est tout
         ce que coûte un compte quand le SMS est ouvert. L'e-mail viendra
         plus tard, s'il vient. Sans SMS, l'e-mail et le mot de passe
         d'avant reviennent — le nom reste au-dessus des deux. */
      '<div class="carte">' +
        '<div class="champ"><label for="cp-nom">Votre nom</label>' +
          '<input id="cp-nom" type="text" autocomplete="name" placeholder="Nom et prénom"></div>' +
        "<div data-sms>" +
          champNumero("") +
          '<div class="champ"><label for="cp-mdp-nouveau">Choisissez un mot de passe</label>' +
            '<input id="cp-mdp-nouveau" type="password" autocomplete="new-password" ' +
              'placeholder="Six caractères au minimum"></div>' +
          '<div class="champ"><label for="cp-mdp-encore">Le même, une seconde fois</label>' +
            '<input id="cp-mdp-encore" type="password" autocomplete="new-password"></div>' +
          '<button type="button" class="btn" id="cp-creer-tel">' + UI.icone("compte") +
            "Créer mon compte</button>" +
          '<p class="aide" style="margin:10px 0 0">Un code part par SMS pour confirmer ' +
            "votre numéro. Votre e-mail, facultatif, s'ajoute plus tard dans « Mon compte ».</p>" +
        "</div>" +
        "<div data-sans-sms hidden>" +
          '<div class="champ"><label for="cp-email">Votre e-mail</label>' +
            '<input id="cp-email" type="email" inputmode="email" autocomplete="email" ' +
              'placeholder="vous@exemple.com"></div>' +
          '<div class="champ"><label for="cp-mdp">Mot de passe</label>' +
            '<input id="cp-mdp" type="password" autocomplete="new-password" ' +
              'placeholder="Six caractères au minimum"></div>' +
          '<button type="button" class="btn" id="cp-creer">' + UI.icone("compte") +
            "Créer mon compte</button>" +
        "</div>" +
      "</div>" +
      '<div class="carte">' +
        '<p class="aide" style="margin:0">Déjà un compte ? ' +
          '<a href="#/connexion">Se connecter</a></p>' +
      "</div>";
    Compte.masquerSiSmsFerme(vue);

    let type = "client";
    const marquer = () => {
      for (const b of UI.$$("[data-type]", vue)) {
        b.classList.toggle("cp-choisi", b.dataset.type === type);
        b.setAttribute("aria-pressed", b.dataset.type === type ? "true" : "false");
      }
      UI.$("#cp-revendeur").hidden = type !== "revendeur";
    };
    for (const b of UI.$$("[data-type]", vue)) {
      b.addEventListener("click", () => { type = b.dataset.type; marquer(); });
    }
    marquer();

    /* Le bloc de position est dessiné même quand il est caché : le
       brancher une fois suffit, et ce qu'il a relevé survit à un
       aller-retour entre les deux sortes de comptes. */
    const lirePosition = brancherPosition(vue, "cp-pos");

    /* Par le numéro. Ce qui a été choisi plus haut — revendeur, son
       commerce, sa position — se lit AVANT l'écran du code : celui-ci
       remplace le formulaire, et ses champs avec. La demande part une
       fois le compte ouvert, avec sa session (voir apresEntree). */
    const creerTel = UI.$("#cp-creer-tel", vue);
    if (creerTel) {
      creerTel.addEventListener("click", async () => {
        const nom = UI.$("#cp-nom", vue).value.trim();
        const tel = UI.$("#cp-tel", vue).value;
        const mdp = UI.$("#cp-mdp-nouveau", vue).value;
        const message = UI.$("#cp-message", vue).value.trim();
        if (!nom) return UI.toast("Votre nom, s'il vous plaît.", "alerte");
        if (Compte.telNational(tel).length < 8) return UI.toast("Tapez votre numéro.", "alerte");
        if (mdp.length < 6) return UI.toast("Mot de passe : six caractères au minimum.", "alerte");
        /* Tapé à l'aveugle, sur un téléphone : une seconde saisie évite de
           fermer la porte avec une clé qu'on n'a jamais vue. */
        if (UI.$("#cp-mdp-encore", vue).value !== mdp) {
          return UI.toast("Les deux mots de passe ne sont pas identiques.", "alerte");
        }
        if (type === "revendeur" && !message) {
          return UI.toast("Dites-nous quel commerce vous tenez.", "alerte");
        }
        if (type === "revendeur" && !positionComplete(lirePosition())) {
          return UI.toast(MANQUE_POSITION, "alerte");
        }
        const revendeur = type === "revendeur" ? { message, position: lirePosition() } : null;
        creerTel.disabled = true;
        try {
          await Compte.inscrireTelephone(tel, mdp, nom);
          ecranCode(vue, {
            tel,
            titre: "Créer mon compte",
            renvoyer: () => Compte.renvoyerCodeInscription(tel),
            valider: (code) => Compte.confirmerCodeConnexion(tel, code),
            apres: (r) => apresEntree(vue, { nom, revendeur, inscription: true }, r),
          });
        } catch (err) {
          UI.toast(err.message, "alerte");
          creerTel.disabled = false;
        }
      });
    }

    /* Par l'e-mail — seulement quand le SMS est fermé. */
    const creer = UI.$("#cp-creer", vue);
    if (!creer) return;
    creer.addEventListener("click", async () => {
      const nom = UI.$("#cp-nom").value.trim();
      const email = UI.$("#cp-email").value.trim();
      const mdp = UI.$("#cp-mdp").value;
      const message = UI.$("#cp-message").value.trim();
      if (!email || !mdp) return UI.toast("Votre e-mail et un mot de passe.", "alerte");
      if (mdp.length < 6) return UI.toast("Six caractères au minimum.", "alerte");
      if (type === "revendeur" && !message) {
        return UI.toast("Dites-nous quel commerce vous tenez.", "alerte");
      }
      if (type === "revendeur" && !positionComplete(lirePosition())) {
        return UI.toast(MANQUE_POSITION, "alerte");
      }
      const bouton = creer;
      bouton.disabled = true;
      try {
        const r = await Compte.inscrire(email, mdp, nom, type, message,
          type === "revendeur" ? lirePosition() : null);
        /* Le compte existe, confirmation par e-mail ou non. Un revendeur
           a, en plus, déposé sa demande. */
        Pixel.inscription(type);
        if (type === "revendeur") Pixel.demandeRevendeur();
        if (r.confirmation) {
          /* BIZZOO demande une confirmation par e-mail : il n'y a pas de
             session, donc rien à afficher d'autre que la marche à suivre. */
          vue.innerHTML =
            '<div class="carte pa-confirme">' + UI.icone("check") +
              "<div><strong>Compte créé.</strong> Ouvrez l'e-mail que nous venons " +
              "d'envoyer à <strong>" + Utils.echapper(email) + "</strong> pour le " +
              "confirmer, puis revenez vous connecter.</div></div>" +
            (type === "revendeur"
              ? '<div class="carte"><p class="aide" style="margin:0">Votre demande de ' +
                "compte revendeur partira chez BIZZOO dès votre première connexion.</p></div>"
              : "") +
            '<a class="btn btn-clair" href="#/connexion">Se connecter</a>';
          return;
        }
        UI.toast(r.revendeur ? "Bienvenue ! Votre demande est partie." : "Bienvenue !");
        /* Comme après une connexion : on revient d'où l'on venait. Un
           client envoyé ici depuis son panier le retrouve, plein. */
        repartir();
      } catch (err) {
        UI.toast(err.message, "alerte");
        bouton.disabled = false;
      }
    });
  }

  /* ---------- Entrer par son numéro ----------

     Deux temps sur un seul écran : le numéro, puis le code. Les séparer
     en deux adresses ferait perdre le numéro à qui touche « retour »
     pendant qu'il cherche le SMS — et c'est exactement ce qu'on fait,
     tous, en attendant un code. */

  function connexionTel(vue) {
    UI.entete({ titre: "Entrer avec mon numéro", retour: true });

    vue.innerHTML =
      '<div class="carte">' + porteNumero() + "</div>" +
      '<div class="carte">' +
        '<p class="aide" style="margin:0">Vous aviez ouvert votre compte avec une ' +
          'adresse e-mail ? <a href="#/connexion-email">Entrer avec mon e-mail</a></p>' +
      "</div>";
    brancherPorteNumero(vue);

    /* Arrivé ici par un ancien lien alors que le SMS est fermé : on le
       dit, et on montre les autres portes, plutôt qu'un formulaire qui
       n'aboutirait pas. Seulement si le formulaire est encore là — le
       client a pu, entre-temps, recevoir son code ou changer d'écran. */
    Compte.smsDisponible().then((ouvert) => {
      if (ouvert !== false || !UI.$("#cp-envoyer", vue)) return;
      vue.innerHTML =
        '<div class="carte" id="cp-sms-ferme">' +
          '<div class="carte-titre">' + UI.icone("telephone", "ic-sm") +
            " Pas encore ouvert</div>" +
          '<p class="aide" style="margin:0 0 10px">Les codes par SMS ne sont pas encore ' +
            "ouverts chez BIZZOO. En attendant, entrez avec votre e-mail et votre " +
            "mot de passe.</p>" +
          '<a class="btn" href="#/connexion">' + UI.icone("check") + "Se connecter</a>" +
          '<a class="btn btn-clair" href="#/inscription" style="margin-top:10px">' +
            UI.icone("compte") + "Créer mon compte</a>" +
        "</div>";
    });
  }

  /**
   * L'écran du code, partagé par les deux portes : entrer par son
   * numéro, et vérifier son numéro depuis son compte. Un seul écran pour
   * les deux — le client ne voit aucune différence, et il n'y en a
   * aucune de son côté.
   */
  function ecranCode(vue, o) {
    UI.entete({ titre: o.titre, retour: true });

    vue.innerHTML =
      '<div class="carte">' +
        '<p class="aide" style="margin:0 0 12px">Un code à six chiffres part vers le ' +
          "<strong>" + Utils.echapper(Compte.telAffichage(o.tel)) + "</strong>. " +
          "Il expire dans quelques minutes.</p>" +
        '<div class="champ"><label for="cp-code">Votre code</label>' +
          '<input id="cp-code" class="cp-code" type="text" inputmode="numeric" ' +
            'autocomplete="one-time-code" maxlength="6" placeholder="000000"></div>' +
        '<button type="button" class="btn" id="cp-valider">' + UI.icone("check") +
          "Valider</button>" +
        '<p class="aide" style="margin:12px 0 0">Rien reçu ? ' +
          '<a href="#" id="cp-renvoyer">Renvoyer le code</a></p>' +
      "</div>";

    const champ = UI.$("#cp-code");
    champ.focus();

    /* UNE VALIDATION À LA FOIS. Le sixième chiffre valide tout seul ; une
       touche « Entrée » juste derrière renverrait le même code, déjà
       consommé — et le client lirait « code incorrect » au moment même où
       il vient d'entrer. */
    let enCours = false;
    const valider = async () => {
      if (enCours) return;
      const code = champ.value.replace(/\D/g, "");
      if (code.length < 4) return UI.toast("Tapez le code reçu par SMS.", "alerte");
      const bouton = UI.$("#cp-valider");
      enCours = true;
      bouton.disabled = true;
      let r;
      try {
        r = await o.valider(code);
      } catch (err) {
        UI.toast(err.message, "alerte");
        enCours = false;
        bouton.disabled = false;
        champ.select();
        return;
      }
      /* Le code est passé : ce qui suit ne rouvre pas la saisie, même s'il
         échoue — le même code ne servirait plus à rien. */
      try { await o.apres(r); } catch (err) { UI.toast(err.message, "alerte"); }
    };

    UI.$("#cp-valider").addEventListener("click", valider);
    champ.addEventListener("keydown", (e) => { if (e.key === "Enter") valider(); });
    /* Six chiffres tapés : on valide sans attendre qu'on cherche le
       bouton. Le code n'a qu'une seule forme possible. */
    champ.addEventListener("input", () => {
      champ.value = champ.value.replace(/\D/g, "").slice(0, 6);
      if (champ.value.length === 6) valider();
    });

    UI.$("#cp-renvoyer").addEventListener("click", async (e) => {
      e.preventDefault();
      try {
        await o.renvoyer();
        UI.toast("Nouveau code envoyé.");
      } catch (err) {
        UI.toast(err.message, "alerte");
      }
    });
  }

  /** Une des deux cartes du choix « pour moi / pour revendre ». */
  function choixCompte(valeur, icone, titre, aide) {
    return (
      '<button type="button" class="cp-carte" data-type="' + valeur + '" aria-pressed="false">' +
        UI.icone(icone) +
        "<strong>" + Utils.echapper(titre) + "</strong>" +
        "<small>" + Utils.echapper(aide) + "</small>" +
      "</button>"
    );
  }

  /* ---------- Mot de passe oublié ---------- */

  function motDePasse(vue, params) {
    UI.entete({ titre: "Mot de passe oublié", retour: true });
    /* Revenu d'un lien qui n'a pas abouti : on le dit d'abord, en
       clair, et le formulaire juste dessous en renvoie un neuf. */
    const perime = params && params.lien === "perime";
    vue.innerHTML =
      (perime
        ? '<div class="carte pa-avertissement" id="cp-lien-perime">' + UI.icone("alerte", "ic-sm") +
            "<div><strong>Ce lien n'est plus valable.</strong> Il a expiré, ou il a " +
            "déjà servi. Demandez-en un nouveau ci-dessous.</div></div>"
        : "") +
      /* PAR LE NUMÉRO, d'abord : un code reçu par SMS, et l'on choisit
         son mot de passe. C'est aussi la porte des comptes ouverts par
         SMS avant les mots de passe — ils n'en ont jamais eu. */
      (perime ? "" :
      '<div class="carte" data-sms id="cp-oubli-tel">' +
        '<div class="carte-titre">' + UI.icone("telephone", "ic-sm") + " Avec mon numéro</div>" +
        '<p class="aide" style="margin:0 0 10px">Un code par SMS, puis vous choisissez ' +
          "votre mot de passe.</p>" +
        champNumero("") +
        '<button type="button" class="btn" id="cp-oubli-envoyer">' + UI.icone("telephone") +
          "Recevoir mon code</button>" +
      "</div>") +
      '<div class="carte">' +
        '<p class="aide" style="margin:0 0 10px">Avec votre e-mail : nous vous enverrons un ' +
          "lien pour choisir un nouveau mot de passe.</p>" +
        '<div class="champ"><label for="cp-email">Votre e-mail</label>' +
          '<input id="cp-email" type="email" inputmode="email" autocomplete="email" ' +
            'placeholder="vous@exemple.com"></div>' +
        '<button type="button" class="btn" id="cp-envoyer">' + UI.icone("check") +
          "Envoyer le lien</button>" +
      "</div>";
    Compte.masquerSiSmsFerme(vue);

    const parTel = UI.$("#cp-oubli-envoyer", vue);
    if (parTel) {
      parTel.addEventListener("click", async () => {
        const tel = UI.$("#cp-tel", vue).value;
        if (Compte.telNational(tel).length < 8) return UI.toast("Tapez votre numéro.", "alerte");
        parTel.disabled = true;
        try {
          await Compte.demanderCodeOubli(tel);
          ecranCode(vue, {
            tel,
            titre: "Mot de passe oublié",
            renvoyer: () => Compte.demanderCodeOubli(tel),
            valider: (code) => Compte.confirmerCodeConnexion(tel, code),
            /* Entré par le code seul : on ne repart pas sans mot de
               passe — c'est lui qui, avec le code, ouvrira la suite. */
            apres: (r) => choisirMotDePasse(vue, {
              texte: "Choisissez le mot de passe de votre compte. Vous entrerez désormais " +
                "avec votre numéro, ce mot de passe, et un code reçu par SMS.",
              suite: () => apresEntree(vue, {}, r),
            }),
          });
        } catch (err) {
          UI.toast(err.message, "alerte");
          parTel.disabled = false;
        }
      });
    }

    UI.$("#cp-envoyer").addEventListener("click", async () => {
      const email = UI.$("#cp-email").value.trim();
      if (!email) return UI.toast("Votre e-mail.", "alerte");
      const bouton = UI.$("#cp-envoyer");
      bouton.disabled = true;
      try {
        await Compte.motDePasseOublie(email);
      } catch (_) { /* on ne dit pas si l'adresse existe : voir plus bas */ }
      /* On répond la même chose que l'adresse existe ou non. Dire
         « compte inconnu » permettrait de deviner qui a un compte chez
         BIZZOO, un e-mail à la fois. */
      vue.innerHTML =
        '<div class="carte pa-confirme">' + UI.icone("check") +
          "<div>Si un compte existe avec cette adresse, le lien vient d'y être " +
          "envoyé. Pensez à regarder les indésirables.</div></div>" +
        '<a class="btn btn-clair" href="#/connexion">Retour à la connexion</a>';
    });
  }

  /* ---------- Le nouveau mot de passe ----------
     On y arrive par le lien de « Mot de passe oublié » : la session que
     le lien apporte est déjà ouverte (Compte.lireRetourEmail). Sans
     elle, il n'y a rien à changer ici, et l'on renvoie en demander un.

     PAS DE FLÈCHE DE RETOUR : l'écran d'avant, c'est la messagerie, ou
     la page de Supabase qui a vérifié le lien — y revenir rejouerait un
     lien déjà consommé. */
  function nouveauMotDePasse(vue) {
    UI.entete({ titre: "Nouveau mot de passe" });
    if (!Compte.connecte()) {
      location.hash = "#/mot-de-passe?lien=perime";
      return;
    }
    const qui = Compte.identite();
    choisirMotDePasse(vue, {
      texte: "Choisissez le mot de passe de votre compte" +
        (qui ? " " + qui : "") + ".",
      tard: () => { location.hash = "#/"; },
      suite: async () => {
        /* Le lien ouvre une session comme le ferait le mot de passe : un
           compte sans numéro confirmé le confirme ici, comme à la porte
           e-mail. */
        let aConfirmer = false;
        try { aConfirmer = await Compte.numeroAConfirmer(); } catch (_) { /* on entre */ }
        if (aConfirmer) {
          try { await Compte.charger(); } catch (_) { /* le client tapera son numéro */ }
          confirmerNumero(vue, {
            tel: (Compte.moi() || {}).tel || "",
            apres: () => { location.hash = "#/compte"; },
          });
          return;
        }
        location.hash = "#/compte";
      },
    });
  }

  /**
   * Le formulaire du mot de passe — après le lien e-mail, après le code
   * de « Mot de passe oublié », et depuis « Mon compte ». La session est
   * déjà ouverte : on ne fait que poser la clé.
   */
  function choisirMotDePasse(vue, o) {
    UI.entete({ titre: o.titre || "Nouveau mot de passe" });
    vue.innerHTML =
      '<div class="carte" id="cp-choisir-mdp">' +
        '<p class="aide" style="margin:0 0 10px">' + Utils.echapper(o.texte || "") + "</p>" +
        '<div class="champ"><label for="cp-nouveau">Nouveau mot de passe</label>' +
          '<input id="cp-nouveau" type="password" autocomplete="new-password" ' +
            'placeholder="Six caractères au minimum"></div>' +
        '<div class="champ"><label for="cp-encore">Le même, une seconde fois</label>' +
          '<input id="cp-encore" type="password" autocomplete="new-password"></div>' +
        '<button type="button" class="btn" id="cp-changer">' + UI.icone("check") +
          "Enregistrer le mot de passe</button>" +
      "</div>" +
      '<p class="aide" style="text-align:center"><a href="#/" id="cp-mdp-tard">Plus tard</a></p>';

    const suite = () => (o.suite ? o.suite() : (location.hash = "#/compte"));
    UI.$("#cp-mdp-tard").addEventListener("click", (e) => {
      e.preventDefault();
      if (o.tard) o.tard(); else suite();
    });
    UI.$("#cp-changer").addEventListener("click", async () => {
      const nouveau = UI.$("#cp-nouveau").value;
      if (nouveau.length < 6) return UI.toast("Six caractères au minimum.", "alerte");
      /* Tapé à l'aveugle, sur un téléphone : une seconde saisie évite de
         fermer la porte avec une clé qu'on n'a jamais vue. */
      if (UI.$("#cp-encore").value !== nouveau) {
        return UI.toast("Les deux saisies ne sont pas identiques.", "alerte");
      }
      const bouton = UI.$("#cp-changer");
      bouton.disabled = true;
      try {
        await Compte.changerMotDePasse(nouveau);
      } catch (err) {
        UI.toast(err.message, "err");
        bouton.disabled = false;
        return;
      }
      UI.toast("Mot de passe enregistré.", "ok");
      try { await suite(); } catch (err) { UI.toast(err.message, "alerte"); }
    });
  }

  /* ---------- Mon compte ---------- */

  async function monCompte(vue) {
    if (!Compte.connecte()) {
      revenirVers("#/compte");
      location.hash = "#/connexion";
      return;
    }

    UI.entete({ titre: "Mon compte", retour: true });
    vue.innerHTML = '<div class="carte"><span class="chargement-rond"></span></div>';

    /* On relit la fiche à chaque visite : c'est ainsi qu'un revendeur
       apprend que BIZZOO l'a validé, sans fermer l'application. */
    let moi = null;
    try {
      moi = await Compte.charger(true);
      await Compte.chargerPrix();
    } catch (_) { /* on affichera vide */ }
    /* À PART, et surtout pas dans le « try » ci-dessus : un compte de
       l'équipe n'a PAS de fiche client — la base refuse qu'un compte
       soit les deux — et « charger » peut donc échouer. Dans la même
       parenthèse, la question ne serait jamais posée, et la carte
       n'apparaîtrait pas pour ceux-là mêmes à qui elle s'adresse. */
    try { await Compte.chargerEquipe(); } catch (_) { /* on ne propose rien */ }
    /* UN LIVREUR N'EST PAS UN ACHETEUR (3.59.0) : ni « Devenir revendeur »,
       ni « Mes commandes », ni « Retrouver mes commandes d'avant ». Ses
       courses prennent la place de ses commandes. */
    try { await Compte.chargerLivreur(); } catch (_) { /* base d'avant : rien ne change */ }
    const livreur = Compte.estLivreur();
    const double = Compte.estDoubleLivreur();
    moi = moi || { nom: "", tel: "", adresse: "", tel_verifie: false };
    /* Un compte e-mail d'avant le SMS, resté connecté sur ce téléphone :
       son numéro est à confirmer, une fois. La carte passe devant tout le
       reste, et remplace l'invitation plus discrète sous le champ. */
    let aConfirmer = false;
    if (!livreur) {
      try { aConfirmer = await Compte.numeroAConfirmer(); } catch (_) { /* on ne demande rien */ }
    }

    vue.innerHTML =
      (double
        ? '<div class="carte cp-numero-requis" id="cp-double-livreur">' +
            '<div class="carte-titre">' + UI.icone("alerte", "ic-sm") +
              " Ce numéro est celui d'un livreur</div>" +
            '<p class="aide" style="margin:0 0 10px">Ce compte client a été ouvert avec le numéro ' +
              "d'un livreur BIZZOO. Un livreur n'achète pas et ne revend pas sur BIZZOO : entrez " +
              "avec votre <strong>compte livreur</strong> pour retrouver vos courses.</p>" +
            '<button type="button" class="btn" id="cp-double-sortir">' + UI.icone("retour") +
              "Me déconnecter</button>" +
          "</div>"
        : "") +
      carteEspaceVendeur() +
      (aConfirmer
        ? '<div class="carte cp-numero-requis" id="cp-numero-requis">' +
            '<div class="carte-titre">' + UI.icone("telephone", "ic-sm") +
              " Confirmez votre numéro</div>" +
            '<p class="aide" style="margin:0 0 10px">BIZZOO ouvre désormais les comptes ' +
              "avec un numéro et un code reçu par SMS. Confirmez celui de ce compte, une " +
              "fois : ensuite, vous entrerez avec lui, votre mot de passe et un code. C'est " +
              "aussi ce qui vous permet de commander.</p>" +
            '<button type="button" class="btn" id="cp-confirmer">' + UI.icone("telephone") +
              "Confirmer mon numéro</button>" +
          "</div>"
        : "") +
      '<div class="carte">' +
        '<div class="carte-titre">' + Utils.echapper(Compte.identite()) + "</div>" +
        '<div class="champ"><label for="cp-nom">Votre nom</label>' +
          '<input id="cp-nom" type="text" autocomplete="name" value="' +
            Utils.echapper(moi.nom || "") + '"></div>' +
        '<div class="champ"><label for="cp-tel">Téléphone</label>' +
          '<input id="cp-tel" type="tel" inputmode="tel" autocomplete="tel" value="' +
            Utils.echapper(moi.tel || "") + '"' + (moi.tel_verifie ? " disabled" : "") + ">" +
          (moi.tel_verifie
            ? '<p class="aide cp-verifie" style="margin:6px 0 0">' + UI.icone("check", "ic-sm") +
              " Numéro vérifié. Il sert à retrouver vos commandes.</p>"
            : aConfirmer || livreur ? ""
            : '<div data-sms><p class="aide" style="margin:6px 0 0">Un numéro vérifié vous rend les ' +
              "commandes passées avec lui, avant même d'avoir un compte.</p>" +
              '<button type="button" class="btn btn-clair" id="cp-verifier" ' +
                'style="margin-top:8px">' + UI.icone("telephone") +
                "Vérifier par SMS</button></div>") +
        "</div>" +
        '<div class="champ"><label for="cp-adresse">Adresse de livraison</label>' +
          '<input id="cp-adresse" type="text" autocomplete="street-address" value="' +
            Utils.echapper(moi.adresse || "") + '"></div>' +
        '<button type="button" class="btn" id="cp-enregistrer">' + UI.icone("check") +
          "Enregistrer</button>" +
      "</div>" +
      carteConnexion() +
      /* Les gains d'un code de particulier : la place seulement, remplie
         si la base dit que ce compte a un code. */
      '<div class="carte cp-gains" id="cp-gains" hidden></div>' +
      (livreur ? "" : carteRevendeur() + carteOuRevendeur()) +
      '<div class="carte">' +
        (livreur
          ? '<a class="btn btn-clair" href="#/mes-courses" id="cp-mes-courses">' + UI.icone("boite") +
              "Mes courses</a>"
          : '<a class="btn btn-clair" href="#/mes-commandes">' + UI.icone("boite") +
              "Mes commandes</a>") +
        (moi.tel_verifie && !livreur
          ? '<button type="button" class="btn btn-clair" id="cp-reprendre" ' +
            'style="margin-top:10px">' + UI.icone("actualiser") +
            "Retrouver mes commandes d'avant</button>"
          : "") +
        /* Le SAV a sa propre porte : une réclamation ouverte il y a une
           semaine ne se retrouve pas en fouillant ses commandes. */
        '<a class="btn btn-clair" href="#/reclamations" style="margin-top:10px">' +
          UI.icone("alerte") + "Mes réclamations</a>" +
        /* Les favoris et les adresses : deux listes qui n'appartiennent
           qu'au client, et que la base ferme à tout le monde d'autre,
           l'enseigne comprise. */
        '<a class="btn btn-clair" href="#/favoris" style="margin-top:10px">' +
          UI.icone("coeur") + "Mes favoris</a>" +
        '<a class="btn btn-clair" href="#/adresses" style="margin-top:10px">' +
          UI.icone("lieu") + "Mes adresses</a>" +
      "</div>" +
      carteBizzoo() +
      '<div class="carte">' +
        '<button type="button" class="btn btn-clair" id="cp-sortir">' + UI.icone("retour") +
          "Se déconnecter</button>" +
      "</div>";

    brancherCarteBizzoo();
    brancherRevendeur(vue);
    brancherEspaceVendeur(vue);
    brancherOuRevendeur(vue);
    brancherVerification(vue, moi);
    brancherConnexion(vue);
    Compte.masquerSiSmsFerme(vue);
    remplirGains(vue, moi);

    const sortirDouble = UI.$("#cp-double-sortir", vue);
    if (sortirDouble) {
      sortirDouble.addEventListener("click", async () => {
        await Compte.deconnecter();
        location.hash = "#/connexion";
      });
    }

    const confirmer = UI.$("#cp-confirmer", vue);
    if (confirmer) {
      confirmer.addEventListener("click", () => {
        /* Le numéro tel qu'il est dans le champ : le client a pu le
           corriger juste avant de toucher le bouton. */
        const champ = UI.$("#cp-tel", vue);
        confirmerNumero(vue, {
          tel: (champ && champ.value) || moi.tel || "",
          apres: () => monCompte(vue),
        });
      });
    }

    UI.$("#cp-enregistrer").addEventListener("click", async () => {
      const bouton = UI.$("#cp-enregistrer");
      bouton.disabled = true;
      try {
        await Compte.enregistrer({
          nom: UI.$("#cp-nom").value,
          tel: UI.$("#cp-tel").value,
          adresse: UI.$("#cp-adresse").value,
        });
        UI.toast("Enregistré.");
      } catch (err) {
        UI.toast(err.message, "alerte");
      }
      bouton.disabled = false;
    });

    UI.$("#cp-sortir").addEventListener("click", async () => {
      await Compte.deconnecter();
      UI.toast("À bientôt.");
      location.hash = "#/";
    });
  }

  /* ---------- Comment j'entre : e-mail de secours, mot de passe ----------

     L'e-mail n'est jamais exigé. Ajouté ici, il devient la seconde
     porte : e-mail et mot de passe, sans code, pour le jour où le
     téléphone n'est pas là. Sans lui, perdre son téléphone, c'est
     attendre de retrouver sa carte SIM. */
  function carteConnexion() {
    const email = Compte.courriel();
    return (
      '<div class="carte" id="cp-connexion">' +
        '<div class="carte-titre">' + UI.icone("compte", "ic-sm") + " Mes accès</div>" +
        (email
          ? '<p class="aide" style="margin:0 0 10px">E-mail de secours : <strong>' +
              Utils.echapper(email) + "</strong>. Sans votre téléphone, entrez avec lui " +
              "et votre mot de passe.</p>"
          : '<p class="aide" style="margin:0 0 10px">Ajoutez votre e-mail (facultatif) : ' +
              "si votre téléphone n'est pas là, vous entrerez avec lui et votre mot de " +
              "passe, sans code.</p>") +
        '<div class="champ"><label for="cp-email-secours">' +
          (email ? "Changer d'e-mail" : "Votre e-mail") + "</label>" +
          '<input id="cp-email-secours" type="email" inputmode="email" autocomplete="email" ' +
            'placeholder="vous@exemple.com"></div>' +
        '<button type="button" class="btn btn-clair" id="cp-email-ajouter">' + UI.icone("check") +
          (email ? "Changer mon e-mail" : "Ajouter mon e-mail") + "</button>" +
        '<button type="button" class="btn btn-clair" id="cp-mdp-changer" style="margin-top:10px">' +
          UI.icone("compte") + "Changer mon mot de passe</button>" +
      "</div>"
    );
  }

  function brancherConnexion(vue) {
    const ajouter = UI.$("#cp-email-ajouter", vue);
    if (ajouter) {
      ajouter.addEventListener("click", async () => {
        const champ = UI.$("#cp-email-secours", vue);
        const adresse = champ.value.trim();
        if (!adresse) return UI.toast("Tapez votre adresse e-mail.", "alerte");
        ajouter.disabled = true;
        try {
          const r = await Compte.ajouterEmail(adresse);
          if (r.applique) {
            UI.toast("E-mail enregistré.", "ok");
            monCompte(vue);
            return;
          }
          /* Supabase demande de cliquer le lien : l'adresse n'est celle du
             compte qu'après. On le dit, sinon le client croirait sa porte
             de secours ouverte. */
          UI.toast("Ouvrez le message envoyé à " + adresse + " pour confirmer.", "ok");
          champ.value = "";
        } catch (err) {
          UI.toast(err.message, "alerte");
        }
        ajouter.disabled = false;
      });
    }
    const changer = UI.$("#cp-mdp-changer", vue);
    if (changer) {
      changer.addEventListener("click", () => choisirMotDePasse(vue, {
        titre: "Mon mot de passe",
        texte: "Choisissez votre nouveau mot de passe.",
        suite: () => monCompte(vue),
      }));
    }
  }

  /* ---------- Mes courses (un livreur) ----------

     Un livreur n'a pas de commandes : il a des courses. La liste vient de
     la base (« mes_livraisons ») : celles à livrer, et celles livrées ces
     deux derniers jours. Pour les faire avancer, c'est l'espace vendeur.

     LA FICHE (3.59.0), la même que l'alerte : où récupérer le colis, où
     le livrer, le numéro du destinataire, les frais, le déjà-payé, ce
     qui reste à récupérer. Et « Reçu » : le livreur accepte la course,
     et c'est à ce moment que le client reçoit son nom et son numéro. */
  const ETAT_COURSE = { preparee: "À récupérer", en_livraison: "En livraison", remise: "Livrée" };

  async function mesCourses(vue) {
    UI.entete({ titre: "Mes courses", retour: true });
    if (!Compte.connecte()) { location.hash = "#/connexion"; return; }
    vue.innerHTML = '<div class="carte"><span class="chargement-rond"></span></div>';
    try { await Compte.chargerLivreur(); } catch (_) { /* on lira quand même */ }
    if (Compte.estDoubleLivreur()) {
      vue.innerHTML =
        '<div class="carte" id="cp-courses-double"><p class="aide" style="margin:0">Vos courses sont ' +
          "dans votre <strong>compte livreur</strong>. Déconnectez-vous, puis entrez avec lui.</p></div>";
      return;
    }
    if (!Compte.estLivreur()) { location.hash = "#/mes-commandes"; return; }
    let courses = [];
    try { courses = await Compte.mesCourses(); }
    catch (err) {
      vue.innerHTML = '<div class="carte"><p class="aide" style="margin:0">' +
        Utils.echapper(err.message) + "</p></div>";
      return;
    }
    const lienCarte = (adresse, lat, lng) =>
      "https://www.google.com/maps/search/?api=1&query=" +
      encodeURIComponent(lat != null && lng != null ? lat + "," + lng : adresse);
    const lieu = (titre, nom, adresse, tel, indicatif, lat, lng) =>
      '<div class="cp-course-lieu"><small>' + Utils.echapper(titre) + "</small>" +
        "<strong>" + Utils.echapper(nom || "") + "</strong>" +
        (adresse || (lat != null && lng != null)
          ? '<a href="' + Utils.echapper(lienCarte(adresse, lat, lng)) + '" target="_blank" rel="noopener">' +
            Utils.echapper(adresse || "Voir sur la carte") + "</a>"
          : "") +
        (tel ? '<a href="' + Utils.echapper(Utils.lienTel(tel, indicatif || "229")) + '">' +
          Utils.echapper(Compte.telAffichage(tel, indicatif || "229")) + "</a>" : "") +
      "</div>";
    const carteFiche = (c) => {
      const f = c.fiche;
      const r = f.retrait || {};
      const l = f.livraison || {};
      const m = (x) => Utils.echapper(Utils.fmtMontant(Number(x) || 0, f.devise || "FCFA"));
      const articles = (c.articles || []).map((a) => (a.quantite || 1) + " × " + a.nom).join(", ");
      const aAccepter = !c.recu_le && c.etat === "preparee";
      return (
        '<div class="carte cp-course" data-course="' + Utils.echapper(c.commande_id) +
          '" data-boutique="' + Utils.echapper(c.boutique_id || "") + '">' +
          '<div class="carte-titre">Commande ' + Utils.echapper(f.numero || c.numero || c.commande_id) +
            ' <small class="cp-course-etat">' +
            Utils.echapper(aAccepter ? "Nouvelle" : ETAT_COURSE[c.etat] || c.etat) + "</small></div>" +
          (Number(f.a_encaisser) > 0
            ? '<p class="cp-course-recuperer">' + (c.etat === "remise" ? "Récupéré" : "À récupérer") +
              " : <strong>" + m(f.a_encaisser) + "</strong></p>"
            : '<p class="cp-course-recuperer cp-course-rien">Rien à récupérer : tout est payé.</p>') +
          '<p class="aide" style="margin:4px 0 0">Déjà payé : <strong>' + m(f.deja_paye) +
            "</strong> · Frais de livraison : <strong>" +
            (Number(f.frais) > 0 ? m(f.frais) : "aucun") + "</strong></p>" +
          lieu("Récupérer le colis", r.boutique || c.nom_boutique, r.adresse, r.tel, r.indicatif,
            r.latitude, r.longitude) +
          lieu("Livrer à", l.nom, l.adresse, l.tel, l.indicatif, null, null) +
          (l.note ? '<p class="aide" style="margin:4px 0 0">' + Utils.echapper(l.note) + "</p>" : "") +
          (articles ? '<p class="aide" style="margin:6px 0 0">' + Utils.echapper(articles) + "</p>" : "") +
          (aAccepter
            ? '<button type="button" class="btn cp-course-recu" style="margin-top:10px">' +
              UI.icone("check") + "Reçu</button>" +
              '<p class="aide" style="margin:6px 0 0">En touchant « Reçu », vous acceptez la course : ' +
              "le client reçoit votre nom et votre numéro.</p>"
            : "") +
        "</div>"
      );
    };
    const carte = (c) => {
      if (c.fiche && typeof c.fiche === "object") return carteFiche(c);
      const articles = (c.articles || []).map((a) => (a.quantite || 1) + " × " + a.nom).join(", ");
      return (
        '<div class="carte cp-course" data-course="' + Utils.echapper(c.commande_id) + '">' +
          '<div class="carte-titre">Commande ' + Utils.echapper(c.numero || c.commande_id) +
            ' <small class="cp-course-etat">' + Utils.echapper(ETAT_COURSE[c.etat] || c.etat) + "</small></div>" +
          '<p class="aide" style="margin:0">' + Utils.echapper(c.nom_boutique || "") + "</p>" +
          '<p style="margin:6px 0 0"><strong>' + Utils.echapper(c.client_nom || "") + "</strong> — " +
            Utils.echapper(c.client_adresse || "") + "</p>" +
          (articles ? '<p class="aide" style="margin:4px 0 0">' + Utils.echapper(articles) + "</p>" : "") +
          (Number(c.a_encaisser) > 0
            ? '<p style="margin:4px 0 0">À encaisser : <strong>' +
                Utils.echapper(Utils.fmtMontant(Number(c.a_encaisser), "FCFA")) +
              "</strong></p>"
            : "") +
        "</div>"
      );
    };
    const aFaire = courses.filter((c) => c.etat !== "remise");
    const faites = courses.filter((c) => c.etat === "remise");
    vue.innerHTML =
      '<div class="carte-titre" style="margin:4px 4px 8px">À livrer (' + aFaire.length + ")</div>" +
      (aFaire.length ? aFaire.map(carte).join("")
        : '<div class="carte"><p class="aide" style="margin:0">Aucune course à livrer.</p></div>') +
      '<div class="carte-titre" style="margin:16px 4px 8px">Livrées (' + faites.length + ")</div>" +
      (faites.length ? faites.map(carte).join("")
        : '<div class="carte"><p class="aide" style="margin:0">Aucune course livrée ces deux derniers jours.</p></div>') +
      carteEspaceVendeur();
    brancherEspaceVendeur(vue);
    for (const b of UI.$$(".cp-course-recu", vue)) {
      b.onclick = async () => {
        const c = b.closest(".cp-course");
        b.disabled = true;
        try {
          await Compte.accepterCourse(c.dataset.course, c.dataset.boutique);
          UI.toast("Course acceptée : le client a reçu votre nom et votre numéro.");
          mesCourses(vue);
        } catch (err) {
          UI.toast(err.message, "err");
          b.disabled = false;
        }
      };
    }
  }

  /* ---------- Mes gains : le code d'un particulier ----------

     BIZZOO a confié un code à cette personne. Chaque commande passée avec
     lui et LIVRÉE lui rapporte sa commission. Elle voit ici son solde, ce
     qui l'a fait, et demande un retrait vers son Mobile Money ; BIZZOO
     verse, puis le marque. Le solde se calcule en base, jamais ici. */

  const ETATS_RETRAIT = { demande: "En cours", payee: "Versé", refusee: "Refusé" };

  async function remplirGains(vue, moi) {
    const zone = UI.$("#cp-gains", vue);
    if (!zone) return;
    let d = null;
    try { d = await Paiement.soldeParrain(); } catch (_) { /* base d'avant : rien */ }
    if (!d || !zone.isConnected) return;
    const devise = (Catalogue.boutique() || {}).devise || "FCFA";
    const m = (x) => Utils.echapper(Utils.fmtMontant(Number(x) || 0, devise));
    const codes = (d.codes || []).filter((c) => c.actif !== false).map((c) => c.code);
    zone.hidden = false;
    zone.innerHTML =
      '<div class="carte-titre">' + UI.icone("cadeau", "ic-sm") + " Mes gains</div>" +
      (codes.length
        ? '<p class="aide" style="margin:0 0 10px">Votre code : <strong class="cp-gains-code">' +
            Utils.echapper(codes.join(", ")) + "</strong>. Chaque commande livrée avec lui " +
            "vous rapporte votre commission.</p>"
        : "") +
      '<div class="cp-gains-solde"><small>Disponible</small><strong id="cp-solde">' +
        m(d.solde) + "</strong></div>" +
      '<div class="cp-gains-detail">' +
        "<span>Gagné " + m(d.gagne) + "</span>" +
        "<span>Versé " + m(d.retire) + "</span>" +
        (Number(d.en_attente) > 0 ? "<span>En cours " + m(d.en_attente) + "</span>" : "") +
      "</div>" +
      (Number(d.solde) >= 500
        ? '<button type="button" class="btn" id="cp-retrait-ouvrir" style="margin-top:12px">' +
            UI.icone("telephone") + "Retirer vers Mobile Money</button>"
        : '<p class="aide" style="margin:10px 0 0">Un retrait est possible dès 500 ' +
            Utils.echapper(devise) + ".</p>") +
      '<div id="cp-retrait" hidden style="margin-top:12px">' +
        '<div class="champ"><label for="cp-retrait-montant">Montant</label>' +
          '<input id="cp-retrait-montant" inputmode="numeric" value="' +
            (Number(d.solde) || 0) + '"></div>' +
        '<div class="champ"><label for="cp-retrait-numero">Numéro Mobile Money</label>' +
          '<input id="cp-retrait-numero" type="tel" inputmode="tel" value="' +
            Utils.echapper((moi && moi.tel) || "") + '"></div>' +
        '<div class="champ"><label for="cp-retrait-reseau">Réseau</label>' +
          '<select id="cp-retrait-reseau"><option value="MTN">MTN MoMo</option>' +
            '<option value="Moov">Moov Money</option><option value="Celtiis">Celtiis Cash</option>' +
          "</select></div>" +
        '<button type="button" class="btn" id="cp-retrait-envoyer">' + UI.icone("check") +
          "Demander le retrait</button>" +
        '<p class="aide" style="margin:8px 0 0">BIZZOO vous verse le montant, puis le ' +
          "marque ici. En attendant, il n'est plus disponible.</p>" +
      "</div>" +
      ((d.gains || []).length || (d.retraits || []).length
        ? '<div class="cp-gains-liste">' +
            (d.retraits || []).map((r) =>
              '<div class="cp-gains-ligne"><span>Retrait · ' +
                Utils.echapper(ETATS_RETRAIT[r.etat] || r.etat) +
                (r.etat === "refusee" && r.motif ? " — " + Utils.echapper(r.motif) : "") +
              "</span><strong>− " + m(r.montant) + "</strong></div>").join("") +
            (d.gains || []).map((g) =>
              '<div class="cp-gains-ligne"><span>Commande ' + Utils.echapper(g.numero || "") +
                " · " + Utils.echapper(String(g.taux).replace(".", ",")) + " %</span>" +
                "<strong>+ " + m(g.montant) + "</strong></div>").join("") +
          "</div>"
        : '<p class="aide" style="margin:10px 0 0">Pas encore de commission : elle arrive ' +
            "quand une commande passée avec votre code est livrée.</p>");

    const ouvrir = UI.$("#cp-retrait-ouvrir", zone);
    if (ouvrir) {
      ouvrir.addEventListener("click", () => {
        UI.$("#cp-retrait", zone).hidden = false;
        ouvrir.hidden = true;
        const op = Paiement.operateurDuNumero(UI.$("#cp-retrait-numero", zone).value);
        if (/moov/i.test(op)) UI.$("#cp-retrait-reseau", zone).value = "Moov";
        else if (/celtiis/i.test(op)) UI.$("#cp-retrait-reseau", zone).value = "Celtiis";
      });
    }
    const envoyer = UI.$("#cp-retrait-envoyer", zone);
    if (envoyer) {
      envoyer.addEventListener("click", async () => {
        const montant = Number(String(UI.$("#cp-retrait-montant", zone).value).replace(/\D/g, ""));
        const numero = UI.$("#cp-retrait-numero", zone).value.trim();
        if (!(montant >= 500)) return UI.toast("Un retrait est de 500 " + devise + " au moins.", "alerte");
        if (montant > Number(d.solde)) return UI.toast("C'est plus que votre solde.", "alerte");
        if (numero.replace(/\D/g, "").length < 8) return UI.toast("Votre numéro Mobile Money.", "alerte");
        envoyer.disabled = true;
        try {
          await Paiement.demanderRetrait(montant, numero, UI.$("#cp-retrait-reseau", zone).value);
          UI.toast("Demande envoyée : BIZZOO vous verse le montant.");
          remplirGains(vue, moi);
        } catch (err) {
          envoyer.disabled = false;
          UI.toast(err.message, "alerte");
        }
      });
    }
  }

  /* ---------- Compte revendeur ----------

     Quatre états, quatre écrans. Le client doit toujours savoir où il en
     est : une demande qui disparaît sans réponse est pire que pas de
     demande du tout. */

  /* ---------- L'espace vendeur ----------

     Deux applications, et c'est voulu : l'écran des marges ne doit pas
     être à deux touches de celui que le client regarde par-dessus
     l'épaule du vendeur. Mais un vendeur qui a ouvert BIZZOO ne devrait
     pas avoir à ressortir chercher une icône sur l'écran d'accueil.

     Cette carte n'apparaît QUE pour un compte de l'équipe, et elle
     n'ouvre aucune porte : BIZZOO Admin redemande de s'identifier, et
     c'est la base qui décide ensuite. Elle épargne un geste, rien de
     plus. */

  const pontAndroid = () =>
    (typeof AndroidPont !== "undefined" && AndroidPont) || null;

  function carteEspaceVendeur() {
    if (typeof Compte === "undefined" || !Compte.estEquipe()) return "";
    const pont = pontAndroid();
    /* Sur le téléphone, on sait si l'application est installée. Sur le
       web, il n'y a pas de pont : on ouvre la version en ligne à côté. */
    const installee = pont && typeof pont.espaceVendeurPresent === "function"
      ? (() => { try { return pont.espaceVendeurPresent(); } catch (_) { return false; } })()
      : true;

    return (
      '<div class="carte cp-vendeur">' +
        '<div class="carte-titre">' + UI.icone("magasin", "ic-sm") +
          " Espace vendeur</div>" +
        '<p class="aide" style="margin:0 0 12px">' +
          (installee
            ? "Ce compte est un compte de l'équipe BIZZOO. Vos produits, vos " +
              "commandes et vos réglages sont dans l'application vendeur."
            : "Ce compte est un compte de l'équipe BIZZOO, mais l'application " +
              "vendeur n'est pas installée sur ce téléphone.") +
        "</p>" +
        (installee
          ? '<button type="button" class="btn" id="cp-vendeur-ouvrir">' +
              UI.icone("partager") + "Ouvrir l\'espace vendeur</button>"
          : "") +
      "</div>"
    );
  }

  function brancherEspaceVendeur(vue) {
    const bouton = UI.$("#cp-vendeur-ouvrir", vue);
    if (!bouton) return;
    bouton.addEventListener("click", () => {
      const pont = pontAndroid();
      if (pont && typeof pont.ouvrirEspaceVendeur === "function") {
        try { pont.ouvrirEspaceVendeur(); return; } catch (_) { /* on essaiera le web */ }
      }
      /* Hors du téléphone : les deux applications sont servies côte à
         côte, et l'admin est le dossier voisin. */
      try { window.open(window.BizzooIOS ? "https://www.bizzoomarket.com/admin/" : "../admin/", "_blank", "noopener"); }
      catch (_) { UI.toast("Ouvrez l'application BIZZOO Admin.", "alerte"); }
    });
  }

  /* ---------- Où se trouve mon commerce ----------

     Une demande déposée sans position n'est pas perdue : on peut la
     compléter après coup, et sans redemander quoi que ce soit à BIZZOO.

     C'est important pour un revendeur DÉJÀ VALIDÉ : refaire une demande
     pour corriger une adresse lui ferait perdre son statut le temps
     qu'on la regarde — et ses prix avec. « enregistrerPosition » ne
     touche que ces trois champs, et la décision de l'enseigne tient.

     L'écran montre d'abord ce qui est enregistré, et n'ouvre le
     formulaire que si on le demande : quelqu'un qui a déjà donné son
     adresse n'a pas à retomber sur trois champs à chaque visite. */

  function carteOuRevendeur() {
    const etat = Compte.etatRevendeur();
    /* En « aucune » et « refusee », le formulaire de demande porte déjà
       le bloc : une deuxième carte ferait doublon. */
    if (etat !== "validee" && etat !== "en_attente") return "";

    const pos = Compte.positionRevendeur();
    const situe = pos.latitude !== null && pos.longitude !== null;
    const rien = !pos.adresse && !situe;
    /* UNE DEMANDE EN ATTENTE SANS POSITION COMPLÈTE ne peut pas être
       validée : on le dit, et le formulaire est déjà ouvert. */
    const aCompleter = etat === "en_attente" && !positionComplete(pos);
    const carte = situe
      ? "https://www.google.com/maps/search/?api=1&query=" + pos.latitude + "," + pos.longitude
      : "";

    return (
      '<div class="carte' + (aCompleter ? " cp-ou-requis" : "") + '" id="cp-ou">' +
        '<div class="carte-titre">' + UI.icone("itineraire", "ic-sm") +
          (aCompleter ? " Validez votre compte : votre position" : " Où se trouve votre commerce") +
          "</div>" +
        (aCompleter
          ? '<p class="aide" style="margin:0 0 12px"><strong>BIZZOO ne peut pas valider votre ' +
            "demande sans votre position.</strong> Indiquez votre adresse, puis touchez « Activer " +
            "ma position ».</p>"
          : "") +
        (rien
          ? '<p class="aide" style="margin:0 0 12px">Vous ne l\'avez pas encore dit. ' +
            "C'est ce qui permet à BIZZOO de vous trouver, et de vous livrer.</p>"
          : '<div class="cp-ou-actuel">' +
              (pos.adresse
                ? Utils.echapper(pos.adresse)
                : "Position relevée, sans adresse écrite") +
              (situe
                ? '<div><a href="' + Utils.echapper(carte) + '" target="_blank" ' +
                  'rel="noopener">Voir sur la carte</a></div>'
                : "") +
            "</div>") +
        '<button type="button" class="btn btn-clair" id="cp-ou-ouvrir"' +
          (aCompleter ? " hidden" : "") + ">" +
          UI.icone("carte") + (rien ? "Ajouter ma position" : "Modifier") + "</button>" +
        '<div id="cp-ou-edition"' + (aCompleter ? "" : " hidden") + ' style="margin-top:14px">' +
          blocPosition("cp-ou-pos", pos) +
          '<button type="button" class="btn" id="cp-ou-enregistrer" style="margin-top:12px">' +
            UI.icone("check") + "Enregistrer</button>" +
        "</div>" +
      "</div>"
    );
  }

  function brancherOuRevendeur(vue) {
    const ouvrir = UI.$("#cp-ou-ouvrir", vue);
    const edition = UI.$("#cp-ou-edition", vue);
    if (!ouvrir || !edition) return;

    const lirePosition = brancherPosition(vue, "cp-ou-pos", Compte.positionRevendeur());
    /* Le formulaire s'ouvre, le bouton s'efface : deux façons d'appeler
       la même chose côte à côte n'aident personne. */
    ouvrir.addEventListener("click", () => {
      edition.hidden = false;
      ouvrir.hidden = true;
    });

    const enregistrer = UI.$("#cp-ou-enregistrer", vue);
    if (!enregistrer) return;
    enregistrer.addEventListener("click", async () => {
      if (!positionComplete(lirePosition())) return UI.toast(MANQUE_POSITION, "alerte");
      enregistrer.disabled = true;
      try {
        await Compte.enregistrerPosition(lirePosition());
        UI.toast("C'est enregistré.");
        monCompte(vue);
      } catch (err) {
        UI.toast(err.message, "alerte");
        enregistrer.disabled = false;
      }
    });
  }

  function carteRevendeur() {
    /* Un compte de l'équipe ne devient pas revendeur : la base refuse
       qu'un compte soit des deux côtés à la fois. Lui proposer le
       formulaire l'enverrait le remplir pour se faire refuser. */
    if (typeof Compte !== "undefined" && Compte.estEquipe()) return "";

    const etat = Compte.etatRevendeur();

    if (etat === "validee") {
      return (
        '<div class="carte cp-revendeur-ok">' +
          '<div class="carte-titre">' + UI.icone("magasin", "ic-sm") +
            " Compte revendeur</div>" +
          '<p class="aide" style="margin:0 0 10px">Vous achetez au prix BIZZOO. ' +
            "Les prix affichés dans l'application sont déjà les vôtres.</p>" +
          '<button type="button" class="btn btn-clair" id="cp-rv-annuler">' +
            "Revenir à un compte client</button>" +
        "</div>"
      );
    }

    if (etat === "en_attente") {
      return (
        '<div class="carte">' +
          '<div class="carte-titre">' + UI.icone("horloge", "ic-sm") +
            " Demande de compte revendeur</div>" +
          '<p class="aide" style="margin:0 0 10px">BIZZOO regarde votre demande. ' +
            "En attendant, vous commandez au prix habituel — et vos commandes " +
            "restent les vôtres.</p>" +
          '<button type="button" class="btn btn-clair" id="cp-rv-annuler">' +
            "Retirer ma demande</button>" +
        "</div>"
      );
    }

    const refus = etat === "refusee";
    return (
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("magasin", "ic-sm") +
          (refus ? " Demande non retenue" : " Vous achetez pour revendre ?") + "</div>" +
        (refus && Compte.motifRevendeur()
          ? '<p class="cp-rv-motif">' + Utils.echapper(Compte.motifRevendeur()) + "</p>"
          : "") +
        '<p class="aide" style="margin:0 0 10px">' +
          (refus
            ? "Vous pouvez refaire une demande en complétant ce qui manquait."
            : "Un compte revendeur achète au prix BIZZOO, sur tout le catalogue. " +
              "Dites-nous quel commerce vous tenez : BIZZOO décide et vous répond.") +
        "</p>" +
        '<div class="champ"><label for="cp-rv-message">Votre commerce</label>' +
          '<textarea id="cp-rv-message" rows="2" maxlength="300" ' +
            'placeholder="Nom de votre boutique et ce que vous revendez"></textarea></div>' +
        blocPosition("cp-rv-pos", Compte.positionRevendeur()) +
        '<button type="button" class="btn" id="cp-rv-demander">' + UI.icone("check") +
          (refus ? "Refaire ma demande" : "Demander un compte revendeur") + "</button>" +
      "</div>"
    );
  }

  function brancherRevendeur(vue) {
    const demander = UI.$("#cp-rv-demander", vue);
    if (demander) {
      const lirePosition = brancherPosition(vue, "cp-rv-pos", Compte.positionRevendeur());
      demander.addEventListener("click", async () => {
        const message = UI.$("#cp-rv-message", vue).value.trim();
        if (!message) return UI.toast("Dites-nous quel commerce vous tenez.", "alerte");
        if (!positionComplete(lirePosition())) return UI.toast(MANQUE_POSITION, "alerte");
        demander.disabled = true;
        try {
          await Compte.demanderRevendeur(message, lirePosition());
          Pixel.demandeRevendeur();
          UI.toast("Demande envoyée à BIZZOO.");
          monCompte(vue);
        } catch (err) {
          UI.toast(err.message, "alerte");
          demander.disabled = false;
        }
      });
    }

    const annuler = UI.$("#cp-rv-annuler", vue);
    if (annuler) {
      annuler.addEventListener("click", async () => {
        annuler.disabled = true;
        try {
          await Compte.annulerRevendeur();
          UI.toast("Vous êtes de nouveau un compte client.");
          monCompte(vue);
        } catch (err) {
          UI.toast(err.message, "alerte");
          annuler.disabled = false;
        }
      });
    }
  }

  /* ---------- Vérifier son numéro depuis son compte ----------

     Ce que cela ouvre : les commandes passées avec ce numéro AVANT
     d'avoir un compte. C'est pour cela que le drapeau ne s'écrit pas
     depuis l'application — il suffirait sinon de taper le numéro d'un
     voisin pour lire ses achats et son adresse. */

  function brancherVerification(vue, moi) {
    const bouton = UI.$("#cp-verifier", vue);
    if (bouton) {
      bouton.addEventListener("click", async () => {
        const tel = UI.$("#cp-tel", vue).value;
        if (Compte.telNational(tel).length < 8) {
          return UI.toast("Tapez votre numéro avant de le vérifier.", "alerte");
        }
        bouton.disabled = true;
        try {
          await Compte.demanderCodeNumero(tel);
          ecranCode(vue, {
            tel,
            titre: "Vérifier mon numéro",
            renvoyer: () => Compte.demanderCodeNumero(tel),
            valider: (code) => Compte.confirmerCodeNumero(tel, code),
            apres: async () => {
              UI.toast("Numéro vérifié.");
              await proposerRattachement(vue);
            },
          });
        } catch (err) {
          UI.toast(err.message, "alerte");
          bouton.disabled = false;
        }
      });
    }

    /* Un numéro vérifié dont les commandes d'avant n'ont pas encore été
       réclamées : on le propose, plutôt que de le laisser deviner. */
    const reprendre = UI.$("#cp-reprendre", vue);
    if (reprendre) {
      reprendre.addEventListener("click", () => proposerRattachement(vue));
    }
    return moi;
  }

  /**
   * Retrouver ses commandes d'avant le compte.
   *
   * La base ne remonte pas au-delà de dix-huit mois : les opérateurs
   * recyclent les numéros, et hériter d'une ligne ne doit pas faire
   * hériter du passé de son ancien titulaire. On le dit quand il n'y a
   * rien à reprendre, sinon l'absence de résultat passerait pour une
   * panne.
   */
  async function proposerRattachement(vue) {
    try {
      const combien = await Compte.rattacherMesCommandes();
      if (combien > 0) {
        UI.toast(combien + " commande" + (combien > 1 ? "s" : "") + " retrouvée" +
          (combien > 1 ? "s" : "") + ".");
      } else {
        UI.toast("Aucune commande à reprendre sur ce numéro.");
      }
    } catch (err) {
      UI.toast(err.message, "alerte");
    }
    monCompte(vue);
  }

  return {
    connexion, connexionTel, connexionEmail, inscription, motDePasse, nouveauMotDePasse,
    monCompte, revenirVers, confirmerNumero, mesCourses,
  };
})();
