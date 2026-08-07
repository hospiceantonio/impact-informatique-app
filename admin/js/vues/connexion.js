/* =========================================================
   Connexion — relier l'application à la base (une fois),
   puis connexion du gérant par email + mot de passe.
   ========================================================= */
const VueConnexion = (() => {

  /* ---------- Étape 1 : relier l'application à la base ---------- */

  function configuration(vue) {
    UI.entete({ accueil: true });
    const saisie = Supabase.configurationSaisie() || {};

    vue.innerHTML =
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("cle", "ic-sm") + " Relier l'application à la base</div>" +
        '<p class="aide" style="margin:0 0 12px">Réglage à faire une seule fois : collez l\'adresse et la clé ' +
          "du projet Supabase de la boutique (Dashboard Supabase → Project Settings → API).</p>" +
        UI.champTexte({ id: "cfg-url", label: "Adresse du projet", obligatoire: true,
          valeur: saisie.url || "", placeholder: "https://abcdefgh.supabase.co", type: "url" }) +
        UI.champTexte({ id: "cfg-cle", label: "Clé « anon public »", obligatoire: true,
          valeur: saisie.cle || "", placeholder: "eyJhbGciOi…" }) +
        '<button type="button" class="btn" id="cfg-enregistrer" style="margin-top:4px">' +
          UI.icone("check") + "Enregistrer et continuer</button>" +
        '<details class="bloc-aide"><summary>Pas encore de projet Supabase ?</summary>' +
          "<ol class='aide-liste'>" +
            "<li>Créez un compte gratuit sur <strong>supabase.com</strong> puis « New project ».</li>" +
            "<li>Dans le projet : <strong>SQL Editor → New query</strong>, collez le contenu du fichier " +
              "<strong>supabase/schema.sql</strong> (fourni avec l'application) et lancez « Run ».</li>" +
            "<li><strong>Authentication → Users → Add user</strong> : créez l'email et le mot de passe du gérant " +
              "(cochez « Auto Confirm »).</li>" +
            "<li>Copiez enfin <strong>Project Settings → API</strong> : l'URL du projet et la clé « anon public ».</li>" +
          "</ol>" +
        "</details>" +
      "</div>";

    UI.$("#cfg-enregistrer").onclick = () => {
      const url = UI.$("#cfg-url").value.trim();
      const cle = UI.$("#cfg-cle").value.trim();
      if (!/^https:\/\//.test(url) || !cle) {
        UI.toast("Indiquez l'adresse https://… et la clé du projet.", "err");
        return;
      }
      Supabase.majConfiguration(url, cle);
      UI.toast("Application reliée !", "ok");
      setTimeout(() => location.reload(), 500);
    };
  }

  /* ---------- Étape 2 : connexion du gérant ---------- */

  function connexion(vue, apresConnexion) {
    UI.entete({ accueil: true });

    vue.innerHTML =
      '<div class="carte carte-connexion">' +
        UI.marque(72) +
        '<h2 style="font-size:19px;font-weight:800;margin-top:6px">Espace admin</h2>' +
        '<p class="aide" style="margin:0 0 6px;text-align:center">Connectez-vous avec le compte du gérant pour gérer le catalogue.</p>' +
        UI.champTexte({ id: "cx-email", label: "Email", type: "email", placeholder: "gerant@exemple.com" }) +
        '<div class="champ">' +
          '<label for="cx-mdp">Mot de passe</label>' +
          '<input id="cx-mdp" type="password" autocomplete="current-password">' +
        "</div>" +
        '<button type="button" class="btn" id="cx-connecter">Se connecter</button>' +
        '<div class="aide" id="cx-erreur" style="color:var(--rouge-fonce);text-align:center"></div>' +
        '<div class="aide" style="text-align:center">Mot de passe oublié ? Il se réinitialise dans le tableau de bord Supabase (Authentication → Users).</div>' +
      "</div>";

    const lancer = async () => {
      const bouton = UI.$("#cx-connecter");
      const erreur = UI.$("#cx-erreur");
      erreur.textContent = "";
      bouton.disabled = true;
      bouton.textContent = "Connexion…";
      try {
        await Supabase.connexion(UI.$("#cx-email").value.trim(), UI.$("#cx-mdp").value);
        UI.toast("Bienvenue !", "ok");
        apresConnexion();
      } catch (err) {
        erreur.textContent = err.message || "Connexion impossible.";
        bouton.disabled = false;
        bouton.textContent = "Se connecter";
      }
    };

    UI.$("#cx-connecter").onclick = lancer;
    UI.$("#cx-mdp").addEventListener("keydown", (ev) => { if (ev.key === "Enter") lancer(); });
    UI.$("#cx-email").focus();
  }

  return { configuration, connexion };
})();
