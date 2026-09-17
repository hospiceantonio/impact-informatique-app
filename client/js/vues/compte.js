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

  function connexion(vue) {
    UI.entete({ titre: "Se connecter", retour: true });

    vue.innerHTML =
      '<div class="carte">' +
        '<div class="champ"><label for="cp-email">Votre e-mail</label>' +
          '<input id="cp-email" type="email" inputmode="email" autocomplete="email" ' +
            'placeholder="vous@exemple.com"></div>' +
        '<div class="champ"><label for="cp-mdp">Mot de passe</label>' +
          '<input id="cp-mdp" type="password" autocomplete="current-password" ' +
            'placeholder="Votre mot de passe"></div>' +
        '<button type="button" class="btn" id="cp-entrer">' + UI.icone("check") +
          "Se connecter</button>" +
        '<p class="aide" style="margin:10px 0 0">' +
          '<a href="#/mot-de-passe">Mot de passe oublié ?</a></p>' +
      "</div>" +
      /* Sans mot de passe à retenir, et sans adresse e-mail à avoir : au
         Bénin, beaucoup de clients ont un numéro et pas de courriel.
         Fermer la porte à ceux-là, c'est fermer la boutique. */
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("telephone", "ic-sm") +
          " Sans mot de passe</div>" +
        '<p class="aide" style="margin:0 0 10px">Recevez un code par SMS sur ' +
          "votre téléphone. Pas d'adresse e-mail à retenir.</p>" +
        '<a class="btn btn-clair" href="#/connexion-tel">' + UI.icone("telephone") +
          "Entrer avec mon numéro</a>" +
      "</div>" +
      '<div class="carte">' +
        '<div class="carte-titre">Pas encore de compte ?</div>' +
        '<p class="aide" style="margin:0 0 10px">Avec un compte, vous retrouvez vos ' +
          "commandes depuis n'importe quel téléphone.</p>" +
        '<a class="btn btn-clair" href="#/inscription">' + UI.icone("compte") +
          "Créer mon compte</a>" +
      "</div>";

    const entrer = async () => {
      const email = UI.$("#cp-email").value.trim();
      const mdp = UI.$("#cp-mdp").value;
      if (!email || !mdp) return UI.toast("Votre e-mail et votre mot de passe.", "alerte");
      const bouton = UI.$("#cp-entrer");
      bouton.disabled = true;
      try {
        await Compte.connecter(email, mdp);
        UI.toast("Bonjour !");
        repartir();
      } catch (err) {
        UI.toast(err.message, "alerte");
        bouton.disabled = false;
      }
    };

    UI.$("#cp-entrer").addEventListener("click", entrer);
    UI.$("#cp-mdp").addEventListener("keydown", (e) => { if (e.key === "Enter") entrer(); });
  }

  /* ---------- Inscription ---------- */

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
        '<div id="cp-revendeur" class="champ" hidden>' +
          '<label for="cp-message">Votre commerce</label>' +
          '<textarea id="cp-message" rows="2" maxlength="300" ' +
            'placeholder="Nom de votre boutique et où elle se trouve"></textarea>' +
          '<p class="aide" style="margin:6px 0 0">BIZZOO regarde votre demande et ' +
            "vous répond. En attendant, vous commandez au prix habituel.</p>" +
        "</div>" +
      "</div>" +
      '<div class="carte">' +
        '<div class="champ"><label for="cp-nom">Votre nom</label>' +
          '<input id="cp-nom" type="text" autocomplete="name" placeholder="Nom et prénom"></div>' +
        '<div class="champ"><label for="cp-email">Votre e-mail</label>' +
          '<input id="cp-email" type="email" inputmode="email" autocomplete="email" ' +
            'placeholder="vous@exemple.com"></div>' +
        '<div class="champ"><label for="cp-mdp">Mot de passe</label>' +
          '<input id="cp-mdp" type="password" autocomplete="new-password" ' +
            'placeholder="Six caractères au minimum"></div>' +
        '<button type="button" class="btn" id="cp-creer">' + UI.icone("compte") +
          "Créer mon compte</button>" +
      "</div>" +
      '<div class="carte">' +
        '<p class="aide" style="margin:0">Déjà un compte ? ' +
          '<a href="#/connexion">Se connecter</a></p>' +
      "</div>";

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

    UI.$("#cp-creer").addEventListener("click", async () => {
      const nom = UI.$("#cp-nom").value.trim();
      const email = UI.$("#cp-email").value.trim();
      const mdp = UI.$("#cp-mdp").value;
      const message = UI.$("#cp-message").value.trim();
      if (!email || !mdp) return UI.toast("Votre e-mail et un mot de passe.", "alerte");
      if (mdp.length < 6) return UI.toast("Six caractères au minimum.", "alerte");
      if (type === "revendeur" && !message) {
        return UI.toast("Dites-nous quel commerce vous tenez.", "alerte");
      }
      const bouton = UI.$("#cp-creer");
      bouton.disabled = true;
      try {
        const r = await Compte.inscrire(email, mdp, nom, type, message);
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
      '<div class="carte">' +
        '<p class="aide" style="margin:0 0 10px">Nous vous envoyons un code par ' +
          "SMS. Pas de mot de passe à retenir.</p>" +
        '<div class="champ"><label for="cp-tel">Votre numéro</label>' +
          '<div class="cp-tel-ligne"><span class="cp-indicatif">+229</span>' +
            '<input id="cp-tel" type="tel" inputmode="tel" autocomplete="tel-national" ' +
              'placeholder="01 97 12 15 96"></div></div>' +
        '<button type="button" class="btn" id="cp-envoyer">' + UI.icone("telephone") +
          "Recevoir mon code</button>" +
      "</div>" +
      '<div class="carte">' +
        '<p class="aide" style="margin:0">Vous avez une adresse e-mail ? ' +
          '<a href="#/connexion">Se connecter autrement</a></p>' +
      "</div>";

    UI.$("#cp-envoyer").addEventListener("click", async () => {
      const tel = UI.$("#cp-tel").value;
      const bouton = UI.$("#cp-envoyer");
      bouton.disabled = true;
      try {
        await Compte.demanderCodeConnexion(tel, "");
        ecranCode(vue, {
          tel,
          titre: "Entrer avec mon numéro",
          renvoyer: () => Compte.demanderCodeConnexion(tel, ""),
          valider: (code) => Compte.confirmerCodeConnexion(tel, code),
          apres: () => { UI.toast("Bonjour !"); repartir(); },
        });
      } catch (err) {
        UI.toast(err.message, "alerte");
        bouton.disabled = false;
      }
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

    const valider = async () => {
      const code = champ.value.replace(/\D/g, "");
      if (code.length < 4) return UI.toast("Tapez le code reçu par SMS.", "alerte");
      const bouton = UI.$("#cp-valider");
      bouton.disabled = true;
      try {
        await o.valider(code);
        o.apres();
      } catch (err) {
        UI.toast(err.message, "alerte");
        bouton.disabled = false;
        champ.select();
      }
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

  function motDePasse(vue) {
    UI.entete({ titre: "Mot de passe oublié", retour: true });
    vue.innerHTML =
      '<div class="carte">' +
        '<p class="aide" style="margin:0 0 10px">Nous vous enverrons un lien pour ' +
          "choisir un nouveau mot de passe.</p>" +
        '<div class="champ"><label for="cp-email">Votre e-mail</label>' +
          '<input id="cp-email" type="email" inputmode="email" autocomplete="email" ' +
            'placeholder="vous@exemple.com"></div>' +
        '<button type="button" class="btn" id="cp-envoyer">' + UI.icone("check") +
          "Envoyer le lien</button>" +
      "</div>";

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
    moi = moi || { nom: "", tel: "", adresse: "", tel_verifie: false };

    vue.innerHTML =
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
            : '<p class="aide" style="margin:6px 0 0">Un numéro vérifié vous rend les ' +
              "commandes passées avec lui, avant même d'avoir un compte.</p>" +
              '<button type="button" class="btn btn-clair" id="cp-verifier" ' +
                'style="margin-top:8px">' + UI.icone("telephone") +
                "Vérifier par SMS</button>") +
        "</div>" +
        '<div class="champ"><label for="cp-adresse">Adresse de livraison</label>' +
          '<input id="cp-adresse" type="text" autocomplete="street-address" value="' +
            Utils.echapper(moi.adresse || "") + '"></div>' +
        '<button type="button" class="btn" id="cp-enregistrer">' + UI.icone("check") +
          "Enregistrer</button>" +
      "</div>" +
      carteRevendeur() +
      '<div class="carte">' +
        '<a class="btn btn-clair" href="#/mes-commandes">' + UI.icone("boite") +
          "Mes commandes</a>" +
        (moi.tel_verifie
          ? '<button type="button" class="btn btn-clair" id="cp-reprendre" ' +
            'style="margin-top:10px">' + UI.icone("actualiser") +
            "Retrouver mes commandes d'avant</button>"
          : "") +
        /* Le SAV a sa propre porte : une réclamation ouverte il y a une
           semaine ne se retrouve pas en fouillant ses commandes. */
        '<a class="btn btn-clair" href="#/reclamations" style="margin-top:10px">' +
          UI.icone("alerte") + "Mes réclamations</a>" +
      "</div>" +
      '<div class="carte">' +
        '<button type="button" class="btn btn-clair" id="cp-sortir">' + UI.icone("retour") +
          "Se déconnecter</button>" +
      "</div>";

    brancherRevendeur(vue);
    brancherVerification(vue, moi);

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

  /* ---------- Compte revendeur ----------

     Quatre états, quatre écrans. Le client doit toujours savoir où il en
     est : une demande qui disparaît sans réponse est pire que pas de
     demande du tout. */

  function carteRevendeur() {
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
            'placeholder="Nom de votre boutique et où elle se trouve"></textarea></div>' +
        '<button type="button" class="btn" id="cp-rv-demander">' + UI.icone("check") +
          (refus ? "Refaire ma demande" : "Demander un compte revendeur") + "</button>" +
      "</div>"
    );
  }

  function brancherRevendeur(vue) {
    const demander = UI.$("#cp-rv-demander", vue);
    if (demander) {
      demander.addEventListener("click", async () => {
        const message = UI.$("#cp-rv-message", vue).value.trim();
        if (!message) return UI.toast("Dites-nous quel commerce vous tenez.", "alerte");
        demander.disabled = true;
        try {
          await Compte.demanderRevendeur(message);
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
    connexion, connexionTel, inscription, motDePasse, monCompte, revenirVers,
  };
})();
