/* =========================================================
   Connexion — chaque employé entre avec son numéro de téléphone
   et le code reçu par SMS ; il peut faire confiance à son appareil
   pendant 7 jours. L'administration garde, au choix, son e-mail et
   son mot de passe. Puis, pour un compte qui n'est pas (encore) un
   employé en poste : pourquoi, et quoi faire.
   ========================================================= */
const VueConnexion = (() => {
  const { h } = UI;

  function cadre(...contenu) {
    return h("div", { class: "ecran-connexion" },
      h("div", { class: "carte" },
        h("div", { class: "marque" }, h("img", { src: "icons/icon-192.png", alt: "" }),
          h("h1", { style: { fontSize: "20px" } }, "BIZZOO Personnel"),
          h("p", { class: "doux petit" }, "L'espace interne des employés de BIZZOO")),
        ...contenu));
  }

  /** Le numéro, puis le code. */
  function afficher(zone, suite) {
    const erreur = h("div", { class: "erreur", hidden: true });
    const montrer = (err) => { erreur.textContent = err.message || String(err); erreur.hidden = false; };
    const tel = h("input", { type: "tel", name: "tel", autocomplete: "tel", inputmode: "tel", required: true,
      placeholder: "01 XX XX XX XX" });
    const bouton = h("button", { class: "btn btn-plein", type: "submit" }, "Recevoir mon code par SMS");
    const form = h("form", { class: "pile" },
      h("label", { class: "champ" }, h("span", {}, "Votre numéro de téléphone"), tel,
        h("small", {}, "Le numéro donné à BIZZOO, avec 01 devant (01 + 8 chiffres).")),
      erreur, bouton,
      h("button", { class: "btn btn-second btn-plein", type: "button", onclick: () => parEmail(zone, suite) },
        "Se connecter avec une adresse e-mail"));
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      erreur.hidden = true;
      bouton.disabled = true;
      try {
        const numero = await Supabase.demanderCode(tel.value);
        code(zone, suite, numero);
      } catch (err) {
        montrer(err);
      } finally {
        bouton.disabled = false;
      }
    });
    UI.vider(zone, cadre(form));
    tel.focus();
  }

  function code(zone, suite, numero) {
    const erreur = h("div", { class: "erreur", hidden: true });
    const saisie = h("input", { type: "text", inputmode: "numeric", autocomplete: "one-time-code", required: true,
      maxlength: 8, placeholder: "123456", style: { letterSpacing: "4px", fontSize: "20px", textAlign: "center" } });
    const confiance = h("input", { type: "checkbox" });
    const bouton = h("button", { class: "btn btn-plein", type: "submit" }, "Se connecter");
    const renvoyer = h("button", { class: "btn btn-second", type: "button", disabled: true }, "Renvoyer le code");
    let attente = 60;
    const minuterie = setInterval(() => {
      if (!renvoyer.isConnected || --attente <= 0) {
        clearInterval(minuterie);
        renvoyer.disabled = false;
        renvoyer.textContent = "Renvoyer le code";
        return;
      }
      renvoyer.textContent = "Renvoyer le code (" + attente + " s)";
    }, 1000);
    renvoyer.addEventListener("click", async () => {
      renvoyer.disabled = true;
      try {
        await Supabase.demanderCode(numero);
        UI.succes("Nouveau code envoyé.");
      } catch (err) {
        erreur.textContent = err.message;
        erreur.hidden = false;
      }
      setTimeout(() => { renvoyer.disabled = false; }, 60000);
    });
    const form = h("form", { class: "pile" },
      h("p", { class: "doux petit" }, "Un code vient de partir par SMS au +" + numero.slice(0, 3) + " " +
        numero.slice(3).replace(/(\d{2})(?=\d)/g, "$1 ") + "."),
      h("label", { class: "champ" }, h("span", {}, "Le code reçu"), saisie),
      h("label", { class: "case" }, confiance, "Faire confiance à cet appareil pendant 7 jours"),
      h("p", { class: "doux tres-petit" }, "Sans cela, un nouveau code vous sera demandé à chaque connexion. Ne cochez pas sur un téléphone ou un ordinateur partagé."),
      erreur, bouton,
      h("div", { class: "ligne" }, renvoyer,
        h("button", { class: "btn btn-second", type: "button", onclick: () => afficher(zone, suite) }, "Changer de numéro")));
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      erreur.hidden = true;
      bouton.disabled = true;
      try {
        await Supabase.confirmerCode(numero, saisie.value, confiance.checked);
        /* Le compte rejoint la fiche qui porte ce numéro. */
        try {
          await Supabase.rpc("rh_rattacher_par_telephone");
        } catch (err) {
          await Supabase.deconnexion();
          throw err;
        }
        suite();
      } catch (err) {
        erreur.textContent = err.message;
        erreur.hidden = false;
      } finally {
        bouton.disabled = false;
      }
    });
    UI.vider(zone, cadre(form));
    saisie.focus();
  }

  /** Le superadministrateur confirme sa connexion par un code SMS. */
  function codeEquipe(zone, etat, suite, plusTard, deconnexion) {
    const erreur = h("div", { class: "erreur", hidden: true });
    const info = h("p", { class: "doux petit" });
    const saisie = h("input", { type: "text", inputmode: "numeric", autocomplete: "one-time-code", maxlength: 9,
      placeholder: "6 chiffres", style: { letterSpacing: "4px", fontSize: "20px", textAlign: "center" } });
    const confiance = h("input", { type: "checkbox" });
    const demander = h("button", { class: "btn btn-plein", type: "button" }, "Recevoir le code");
    const valider = h("button", { class: "btn btn-plein", type: "submit" }, "Valider le code");
    const etape2 = h("div", { class: "pile", hidden: true },
      h("label", { class: "champ" }, h("span", {}, "Le code reçu par SMS"), saisie),
      h("label", { class: "case" }, confiance, "Faire confiance à cet appareil pendant 1 mois"),
      valider);
    const dire = (texte, ko) => { erreur.hidden = !ko; erreur.textContent = ko ? texte : ""; info.textContent = ko ? info.textContent : texte; };
    demander.addEventListener("click", async () => {
      demander.disabled = true;
      try {
        const r = await Supabase.demanderCodeEquipe();
        if (r && r.ok && r.deja) return suite();
        if (!r || !r.ok) {
          dire((r && r.message) || "Le code n'a pas pu partir.", true);
          if (r && r.raison === "trop_tot") etape2.hidden = false;
          demander.disabled = false;
          return;
        }
        etape2.hidden = false;
        demander.textContent = "Renvoyer un code";
        dire("Code envoyé au numéro qui finit par " + (r.fin_numero || "…") + ". Il expire dans 10 minutes.");
        saisie.focus();
        setTimeout(() => { demander.disabled = false; }, 30000);
      } catch (err) {
        dire(err.message, true);
        demander.disabled = false;
      }
    });
    const form = h("form", { class: "pile" },
      h("h2", { style: { fontSize: "18px", textAlign: "center" } }, "Confirmez votre connexion"),
      etat.numero
        ? h("p", { class: "doux petit" }, "Compte superadministrateur : BIZZOO demande un code reçu par SMS au numéro de votre compte, qui finit par " + (etat.fin_numero || "…") + ". Sans lui, vous entrez sans vos droits de superadministrateur (la caisse, notamment).")
        : h("p", { class: "avertissement" }, "Votre compte n'a pas de numéro enregistré : le code ne peut partir nulle part. Ajoutez-le dans BIZZOO Admin (Comptes)."),
      info, erreur,
      etat.numero ? demander : null, etape2,
      h("button", { class: "btn btn-second btn-plein", type: "button", onclick: plusTard }, "Plus tard (sans mes droits de superadministrateur)"),
      h("button", { class: "btn btn-second btn-plein", type: "button", onclick: deconnexion }, "Se déconnecter"));
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const code = saisie.value.replace(/\D/g, "");
      if (code.length !== 6) return dire("Le code a six chiffres.", true);
      valider.disabled = true;
      try {
        const r = await Supabase.confirmerCodeEquipe(code);
        if (r && r.ok) {
          if (confiance.checked) await Supabase.confierAppareil().catch(() => UI.echec("Connexion confirmée, mais l'appareil n'a pas pu être gardé."));
          return suite();
        }
        const raison = (r && r.raison) || "";
        dire(raison === "code_faux"
          ? (Number(r.restants) > 0 ? "Code incorrect. Il vous reste " + r.restants + " essai(s)." : "Code incorrect, plus d'essai : demandez un nouveau code.")
          : raison === "expire" || raison === "sans_code" ? "Ce code ne vaut plus : demandez-en un nouveau."
          : raison === "sans_session" ? "Votre session a expiré : déconnectez-vous et reconnectez-vous."
          : "Le code n'a pas été accepté.", true);
      } catch (err) {
        dire(err.message, true);
      } finally {
        valider.disabled = false;
      }
    });
    UI.vider(zone, cadre(form));
  }

  /** L'e-mail et le mot de passe : l'administration, et qui en a un. */
  function parEmail(zone, suite) {
    const erreur = h("div", { class: "erreur", hidden: true });
    const email = h("input", { type: "email", name: "email", autocomplete: "username", required: true,
      placeholder: "prenom.nom@bizzoomarket.com" });
    const mdp = h("input", { type: "password", name: "mdp", autocomplete: "current-password", required: true });
    const bouton = h("button", { class: "btn btn-plein", type: "submit" }, "Se connecter");
    const form = h("form", { class: "pile" },
      h("label", { class: "champ" }, h("span", {}, "E-mail professionnel"), email),
      h("label", { class: "champ" }, h("span", {}, "Mot de passe"), mdp),
      erreur, bouton,
      h("p", { class: "doux tres-petit" },
        "Mot de passe oublié ? Demandez à l'administration de BIZZOO de vous en donner un nouveau."),
      h("button", { class: "btn btn-second btn-plein", type: "button", onclick: () => afficher(zone, suite) },
        "Se connecter avec mon numéro de téléphone"));
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      erreur.hidden = true;
      bouton.disabled = true;
      try {
        await Supabase.connexion(email.value, mdp.value);
        suite();
      } catch (err) {
        erreur.textContent = err.message;
        erreur.hidden = false;
      } finally {
        bouton.disabled = false;
      }
    });
    UI.vider(zone, cadre(form));
    email.focus();
  }

  /**
   * Connecté, mais pas employé en poste. Trois cas : la fiche attend la
   * validation du CEO ; BIZZOO n'a encore personne dans l'application
   * et ce compte est superadministrateur (il devient le CEO, ou le
   * désigne) ; ou ce
   * compte n'a rien à faire ici.
   */
  function sansFiche(zone, tableau, suite, deconnexion) {
    const sortir = h("button", { class: "btn btn-second btn-plein", onclick: deconnexion }, "Se déconnecter");
    if (tableau.amorce_possible) {
      amorce(zone, suite, sortir);
      return;
    }
    const texte = tableau.bloque
      ? "Votre accès à BIZZOO Personnel est bloqué. Adressez-vous au CEO ou à l'administration."
      : tableau.en_attente
      ? "Votre fiche existe, mais vous n'êtes pas (ou plus) en poste : elle attend la validation du CEO, ou votre accès a été fermé."
      : "Ce compte n'est relié à aucun employé de BIZZOO. Si vous êtes employé, demandez à l'administration de créer votre accès avec votre adresse professionnelle.";
    UI.vider(zone, cadre(h("div", { class: "pile" },
      h("div", { class: "avertissement" }, texte),
      h("p", { class: "doux petit" }, "Connecté en tant que " + (Supabase.utilisateur() || "?")),
      h("button", { class: "btn btn-plein", onclick: suite }, "Vérifier de nouveau"),
      sortir)));
  }

  /**
   * Le tout premier lancement. Le superadministrateur qui installe
   * l'application n'est pas forcément le CEO : soit il l'est, soit il
   * désigne le CEO par son adresse professionnelle (et peut s'inscrire
   * dans l'administration pour tout préparer en attendant).
   */
  function amorce(zone, suite, sortir) {
    const erreur = h("div", { class: "erreur", hidden: true });
    const sexe = () => h("select", {}, h("option", { value: "M" }, "Homme"), h("option", { value: "F" }, "Femme"));
    const champ = (libelle, entree, aide) => h("label", { class: "champ" }, h("span", {}, libelle), entree,
      aide ? h("small", {}, aide) : null);
    const zoneFormulaire = h("div", {});
    const montrerErreur = (err) => { erreur.textContent = err.message || String(err); erreur.hidden = false; };

    /* « Je suis le CEO » */
    function moiCeo() {
      const nom = h("input", { required: true, placeholder: "Nom de famille" });
      const prenoms = h("input", { placeholder: "Prénoms" });
      const s = sexe();
      const bouton = h("button", { class: "btn btn-plein btn-orange", type: "submit" }, "Je deviens le CEO");
      const form = h("form", { class: "pile" },
        champ("Nom", nom), champ("Prénoms", prenoms), champ("Sexe", s), bouton);
      form.addEventListener("submit", async (ev) => {
        ev.preventDefault();
        erreur.hidden = true;
        bouton.disabled = true;
        try {
          await Supabase.rpc("rh_devenir_ceo", { nom: nom.value.trim(), prenoms: prenoms.value.trim(), sexe: s.value });
          suite();
        } catch (err) {
          montrerErreur(err);
          bouton.disabled = false;
        }
      });
      UI.vider(zoneFormulaire, form);
      nom.focus();
    }

    /* « Désigner le CEO » */
    function designer() {
      const nom = h("input", { required: true, placeholder: "Nom de famille du CEO" });
      const prenoms = h("input", { placeholder: "Prénoms du CEO" });
      const s = sexe();
      const email = h("input", { type: "email", required: true, placeholder: "ceo@bizzoomarket.com" });
      const mdp = h("input", { type: "password", autocomplete: "new-password", minlength: 8 });
      const mdp2 = h("input", { type: "password", autocomplete: "new-password" });
      const moiAussi = h("input", { type: "checkbox", checked: true });
      const moiNom = h("input", { placeholder: "Votre nom de famille" });
      const moiPrenoms = h("input", { placeholder: "Vos prénoms" });
      const moiSexe = sexe();
      const blocMoi = h("div", { class: "pile" },
        champ("Votre nom", moiNom), champ("Vos prénoms", moiPrenoms), champ("Votre sexe", moiSexe));
      moiAussi.addEventListener("change", () => { blocMoi.hidden = !moiAussi.checked; });
      const bouton = h("button", { class: "btn btn-plein btn-orange", type: "submit" }, "Désigner le CEO");
      const form = h("form", { class: "pile" },
        h("h3", {}, "Le CEO"),
        champ("Nom", nom), champ("Prénoms", prenoms), champ("Sexe", s),
        champ("Son e-mail professionnel", email, "C'est avec cette adresse qu'il se connectera."),
        champ("Son premier mot de passe (8 caractères au moins)", mdp,
          "Donnez-le-lui de vive voix ; il le changera dans « Mon compte ». Laissez vide s'il a déjà un compte BIZZOO à cette adresse."),
        champ("Le même, encore une fois", mdp2),
        h("label", { class: "case" }, moiAussi, "M'inscrire aussi dans l'administration, pour préparer les profils et les employés"),
        blocMoi,
        bouton);
      form.addEventListener("submit", async (ev) => {
        ev.preventDefault();
        erreur.hidden = true;
        if (mdp.value && mdp.value.length < 8) return montrerErreur(new Error("Le mot de passe doit faire 8 caractères au moins."));
        if (mdp.value !== mdp2.value) return montrerErreur(new Error("Les deux mots de passe diffèrent."));
        if (moiAussi.checked && !moiNom.value.trim()) return montrerErreur(new Error("Indiquez votre nom pour vous inscrire dans l'administration."));
        bouton.disabled = true;
        const parametres = {
          nom: nom.value.trim(), prenoms: prenoms.value.trim(), sexe: s.value, email_pro: email.value.trim().toLowerCase(),
          moi_nom: moiAussi.checked ? moiNom.value.trim() : null,
          moi_prenoms: moiAussi.checked ? moiPrenoms.value.trim() : "",
          moi_sexe: moiAussi.checked ? moiSexe.value : null,
        };
        try {
          try {
            await Supabase.rpc("rh_designer_ceo", parametres);
          } catch (err) {
            /* Le CEO n'a pas encore de compte : on le crée, puis on recommence. */
            if (err.code !== "AUCUN_COMPTE") throw err;
            if (!mdp.value) throw new Error("Cette adresse n'a pas encore de compte : choisissez-lui un premier mot de passe.");
            const compte = await Supabase.creerCompte(parametres.email_pro, mdp.value);
            await Supabase.rpc("rh_designer_ceo", parametres);
            if (compte.confirmationRequise) {
              UI.toast("Le CEO devra d'abord cliquer le lien reçu dans sa boîte " + parametres.email_pro + ".");
            }
          }
          UI.succes("Le CEO est désigné.");
          suite();
        } catch (err) {
          montrerErreur(err);
          bouton.disabled = false;
        }
      });
      UI.vider(zoneFormulaire, form);
      nom.focus();
    }

    UI.vider(zone, cadre(h("div", { class: "pile" },
      h("div", { class: "info" }, "Personne n'est encore inscrit dans BIZZOO Personnel. ",
        "Votre compte est superadministrateur de BIZZOO : c'est à vous d'installer le CEO. ",
        "Le CEO valide ensuite les employés, les rapports, les dépenses et la paie. ",
        "Cette porte se ferme dès qu'un CEO existe."),
      h("div", { class: "actions" },
        h("button", { class: "btn btn-second", type: "button", onclick: designer }, "Désigner le CEO"),
        h("button", { class: "btn btn-second", type: "button", onclick: moiCeo }, "Je suis le CEO")),
      zoneFormulaire, erreur, sortir)));
    designer();
  }

  return { afficher, sansFiche, codeEquipe };
})();
