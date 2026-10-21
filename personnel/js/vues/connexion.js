/* =========================================================
   Connexion — l'e-mail professionnel et le mot de passe de
   l'application. Puis, pour un compte qui n'est pas (encore)
   un employé en poste : pourquoi, et quoi faire.
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

  function afficher(zone, suite) {
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
        "Mot de passe oublié ? Demandez à l'administration de BIZZOO de vous en donner un nouveau."));
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
   * et ce compte est superadministrateur (il devient le CEO) ; ou ce
   * compte n'a rien à faire ici.
   */
  function sansFiche(zone, tableau, suite, deconnexion) {
    const sortir = h("button", { class: "btn btn-second btn-plein", onclick: deconnexion }, "Se déconnecter");
    if (tableau.amorce_possible) {
      const erreur = h("div", { class: "erreur", hidden: true });
      const nom = h("input", { required: true, placeholder: "Nom de famille" });
      const prenoms = h("input", { placeholder: "Prénoms" });
      const sexe = h("select", {}, h("option", { value: "M" }, "Homme"), h("option", { value: "F" }, "Femme"));
      const bouton = h("button", { class: "btn btn-plein btn-orange", type: "submit" }, "Je suis le CEO de BIZZOO");
      const form = h("form", { class: "pile" },
        h("div", { class: "info" }, "Personne n'est encore inscrit dans BIZZOO Personnel. ",
          "Votre compte est superadministrateur de BIZZOO : vous pouvez en devenir le CEO. ",
          "C'est le CEO qui valide ensuite les employés, les rapports, les dépenses et la paie. ",
          "Cette porte se ferme dès qu'un CEO existe."),
        h("label", { class: "champ" }, h("span", {}, "Nom"), nom),
        h("label", { class: "champ" }, h("span", {}, "Prénoms"), prenoms),
        h("label", { class: "champ" }, h("span", {}, "Sexe"), sexe),
        erreur, bouton, sortir);
      form.addEventListener("submit", async (ev) => {
        ev.preventDefault();
        bouton.disabled = true;
        try {
          await Supabase.rpc("rh_devenir_ceo", { nom: nom.value.trim(), prenoms: prenoms.value.trim(), sexe: sexe.value });
          suite();
        } catch (err) {
          erreur.textContent = err.message;
          erreur.hidden = false;
          bouton.disabled = false;
        }
      });
      UI.vider(zone, cadre(form));
      return;
    }
    const texte = tableau.en_attente
      ? "Votre fiche existe, mais vous n'êtes pas (ou plus) en poste : elle attend la validation du CEO, ou votre accès a été fermé."
      : "Ce compte n'est relié à aucun employé de BIZZOO. Si vous êtes employé, demandez à l'administration de créer votre accès avec votre adresse professionnelle.";
    UI.vider(zone, cadre(h("div", { class: "pile" },
      h("div", { class: "avertissement" }, texte),
      h("p", { class: "doux petit" }, "Connecté en tant que " + (Supabase.utilisateur() || "?")),
      h("button", { class: "btn btn-plein", onclick: suite }, "Vérifier de nouveau"),
      sortir)));
  }

  return { afficher, sansFiche };
})();
