/* =========================================================
   Comptes — l'équipe de la boutique.

   • afficher()  : la liste et la création de comptes,
                   réservées à l'administrateur ;
   • monCompte() : sa propre fiche (mot de passe, déconnexion),
                   accessible à tout le monde.
   ========================================================= */
const VueComptes = (() => {

  const nomRole = (role) => (Store.ROLES[role] || Store.ROLES.moderateur).nom;

  function htmlLigne(compte, moi) {
    const admin = compte.role === "administrateur";
    return (
      '<div class="compte-ligne' + (compte.actif ? "" : " compte-inactif") + '">' +
        '<span class="compte-rond ' + (admin ? "compte-rond-admin" : "") + '">' +
          UI.icone(admin ? "bouclier" : "personne", "ic-sm") + "</span>" +
        '<span class="compte-corps">' +
          '<span class="compte-email">' + Utils.echapper(compte.email || "—") +
            (moi ? ' <span class="compte-moi">vous</span>' : "") + "</span>" +
          '<span class="compte-details">' + Utils.echapper(nomRole(compte.role)) +
            (compte.actif ? "" : " · désactivé") + "</span>" +
        "</span>" +
        (moi ? "" :
          '<button type="button" class="btn-ic btn-ic-clair" data-compte="' +
            Utils.echapper(compte.id) + '" aria-label="Modifier ce compte">' +
            UI.icone("crayon", "ic-sm") + "</button>") +
      "</div>"
    );
  }

  /* ---------- Modifier un compte existant ---------- */

  function ouvrirFiche(compte, apres) {
    const corps = UI.ouvrirFeuille(compte.email || "Compte",
      '<div class="champ">' +
        '<label for="cp-role">Rôle</label>' +
        '<select id="cp-role">' +
          Object.keys(Store.ROLES).map((cle) =>
            '<option value="' + cle + '"' + (compte.role === cle ? " selected" : "") + ">" +
            Utils.echapper(Store.ROLES[cle].nom) + "</option>").join("") +
        "</select>" +
        '<div class="aide" id="cp-role-aide">' + Utils.echapper(Store.ROLES[compte.role].aide) + "</div>" +
      "</div>" +
      UI.interrupteur({ id: "cp-actif", label: "Compte actif", actif: compte.actif,
        aide: "Désactivé, il ne peut plus rien modifier, même en se connectant." }) +
      '<div class="btn-rangee" style="margin-top:18px">' +
        '<button type="button" class="btn" id="cp-enregistrer">' + UI.icone("check") + "Enregistrer</button>" +
      "</div>");

    const selecteur = UI.$("#cp-role", corps);
    selecteur.onchange = () => {
      UI.$("#cp-role-aide", corps).textContent = Store.ROLES[selecteur.value].aide;
    };

    UI.$("#cp-enregistrer", corps).onclick = async () => {
      const bouton = UI.$("#cp-enregistrer", corps);
      bouton.disabled = true;
      const role = selecteur.value;
      const actif = UI.$("#cp-actif", corps).checked;
      try {
        /* Deux enregistrements plutôt qu'un : le journal raconte alors
           précisément ce qui a changé. */
        if (role !== compte.role) await Store.majCompte(compte.id, { role });
        if (actif !== compte.actif) await Store.majCompte(compte.id, { actif });
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
    const corps = UI.ouvrirFeuille("Nouveau compte",
      UI.champTexte({ id: "nc-email", label: "Adresse email", obligatoire: true,
        type: "email", placeholder: "prenom@exemple.com",
        aide: "C'est avec elle que la personne se connectera." }) +
      UI.champTexte({ id: "nc-mdp", label: "Mot de passe", obligatoire: true,
        type: "password", placeholder: "6 caractères minimum",
        aide: "À lui communiquer ; elle pourra le changer elle-même ensuite." }) +
      '<div class="champ">' +
        '<label for="nc-role">Rôle</label>' +
        '<select id="nc-role">' +
          '<option value="moderateur" selected>' + Utils.echapper(Store.ROLES.moderateur.nom) + "</option>" +
          '<option value="administrateur">' + Utils.echapper(Store.ROLES.administrateur.nom) + "</option>" +
        "</select>" +
        '<div class="aide" id="nc-role-aide">' + Utils.echapper(Store.ROLES.moderateur.aide) + "</div>" +
      "</div>" +
      '<div class="btn-rangee" style="margin-top:18px">' +
        '<button type="button" class="btn" id="nc-creer">' + UI.icone("plus") + "Créer le compte</button>" +
      "</div>" +
      '<div id="nc-resultat"></div>');

    const selecteur = UI.$("#nc-role", corps);
    selecteur.onchange = () => {
      UI.$("#nc-role-aide", corps).textContent = Store.ROLES[selecteur.value].aide;
    };

    UI.$("#nc-creer", corps).onclick = async () => {
      const bouton = UI.$("#nc-creer", corps);
      bouton.disabled = true;
      bouton.textContent = "Création…";
      try {
        const compte = await Store.creerCompte(
          UI.$("#nc-email", corps).value, UI.$("#nc-mdp", corps).value, selecteur.value);
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
        '<p class="aide" style="margin:-4px 0 12px">L\'administrateur a tous les droits. Le modérateur ' +
          "s'occupe des produits et des catégories : ni réglages, ni comptes, ni slider.</p>" +
        (comptes.length
          ? comptes.map((c) => htmlLigne(c, c.id === moi)).join("")
          : '<p class="aide" style="margin:0">Aucun compte enregistré.</p>') +
        '<button type="button" class="btn" id="cp-nouveau" style="margin-top:14px">' +
          UI.icone("plus") + "Créer un compte</button>" +
      "</div>" +
      '<div class="carte">' +
        '<div class="carte-titre">Bon à savoir</div>' +
        '<p class="aide" style="margin:0">Un compte se désactive mais ne se supprime pas depuis ' +
          "l'application : la suppression définitive se fait dans Supabase " +
          "(Authentication → Users). Un compte désactivé ne peut plus rien modifier.</p>" +
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
