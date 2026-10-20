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
        '<p class="aide" style="margin:0 0 6px;text-align:center">Connectez-vous avec votre compte BIZZOO. ' +
          "Livreurs : votre numéro, votre mot de passe, puis le code reçu par SMS.</p>" +
        /* UN SEUL CHAMP, DEUX PORTES. Un « @ » : l'e-mail et le mot de
           passe, comme toujours. Des chiffres : le numéro, le mot de passe,
           puis un code par SMS — la porte des livreurs. */
        UI.champTexte({ id: "cx-email", label: "E-mail ou numéro de téléphone", type: "text",
          placeholder: "gerant@exemple.com ou 01 97 12 15 96" }) +
        '<div class="champ">' +
          '<label for="cx-mdp">Mot de passe</label>' +
          '<input id="cx-mdp" type="password" autocomplete="current-password">' +
        "</div>" +
        '<button type="button" class="btn" id="cx-connecter">Se connecter</button>' +
        '<div class="aide" id="cx-erreur" style="color:var(--rouge-fonce);text-align:center"></div>' +
        '<div class="aide" style="text-align:center">Mot de passe oublié ? Écrivez à <a href="mailto:contact@bizzoomarket.com">contact@bizzoomarket.com</a> pour retrouver l’accès à votre compte.</div>' +
      "</div>";

    const lancer = async () => {
      const bouton = UI.$("#cx-connecter");
      const erreur = UI.$("#cx-erreur");
      erreur.textContent = "";
      bouton.disabled = true;
      bouton.textContent = "Connexion…";
      const identifiant = UI.$("#cx-email").value.trim();
      const mdp = UI.$("#cx-mdp").value;
      if (Supabase.estNumero(identifiant)) {
        try {
          const r = await Supabase.connexionTelephone(identifiant, mdp);
          /* Numéro déjà confirmé : entré, sans code (3.59.0). */
          if (r.entre) {
            Store.journaliser("compte", "connexion", "Connexion à l'application admin", Supabase.utilisateur());
            UI.toast("Bienvenue !", "ok");
            apresConnexion();
            return;
          }
          codeTelephone(vue, r, apresConnexion);
        } catch (err) {
          erreur.textContent = err.message || "Connexion impossible.";
          bouton.disabled = false;
          bouton.textContent = "Se connecter";
        }
        return;
      }
      try {
        await Supabase.connexion(identifiant, mdp);
        Store.journaliser("compte", "connexion", "Connexion à l'application admin", Supabase.utilisateur());
        UI.toast("Bienvenue !", "ok");
        apresConnexion();
      } catch (err) {
        erreur.textContent = err.message || "Connexion impossible.";
        bouton.disabled = false;
        bouton.textContent = "Se connecter";
      }
    };

    vue.insertAdjacentHTML("beforeend", DroitsCompte.carte(false));

    UI.$("#cx-connecter").onclick = lancer;
    UI.$("#cx-mdp").addEventListener("keydown", (ev) => { if (ev.key === "Enter") lancer(); });
    UI.$("#cx-email").focus();
  }

  /* ---------- Le code du numéro (livreurs) ----------
     Le mot de passe est juste ; le code reçu par SMS ouvre la session.
     C'est Supabase qui génère, fait expirer et vérifie ce code. */
  function codeTelephone(vue, r, apresConnexion) {
    UI.entete({ accueil: true });
    vue.innerHTML =
      '<div class="carte carte-connexion" id="cx-code-tel">' +
        UI.marque(72) +
        '<h2 style="font-size:19px;font-weight:800;margin-top:6px">Votre code</h2>' +
        '<p class="aide" style="margin:0 0 6px;text-align:center">Un code à six chiffres part vers le ' +
          "<strong>" + Utils.echapper(r.affichage || "") + "</strong>. Il expire dans quelques minutes.</p>" +
        '<div class="champ"><label for="cx-code-chiffres">Code reçu par SMS</label>' +
          '<input id="cx-code-chiffres" type="text" inputmode="numeric" autocomplete="one-time-code" ' +
            'maxlength="6" placeholder="6 chiffres"></div>' +
        '<button type="button" class="btn" id="cx-code-valider">' + UI.icone("check") + "Valider</button>" +
        '<button type="button" class="btn btn-clair" id="cx-code-renvoyer" style="margin-top:10px">' +
          "Renvoyer un code</button>" +
        '<button type="button" class="btn btn-clair" id="cx-code-retour" style="margin-top:10px">' +
          "Annuler</button>" +
        '<div class="aide" id="cx-code-etat" role="status" aria-live="polite" ' +
          'style="text-align:center"></div>' +
      "</div>";

    const champ = UI.$("#cx-code-chiffres");
    const etat = UI.$("#cx-code-etat");
    champ.focus();
    let enCours = false;
    const valider = async () => {
      if (enCours) return;
      const code = champ.value.replace(/\D/g, "");
      if (code.length !== 6) { etat.textContent = "Le code a six chiffres."; return; }
      enCours = true;
      UI.$("#cx-code-valider").disabled = true;
      try {
        await Supabase.confirmerCodeTelephone(code);
      } catch (err) {
        etat.textContent = err.message || "Le code n'a pas été accepté.";
        enCours = false;
        UI.$("#cx-code-valider").disabled = false;
        return;
      }
      Store.journaliser("compte", "connexion", "Connexion par numéro et code SMS", Supabase.utilisateur());
      UI.toast("Bienvenue !", "ok");
      apresConnexion();
    };
    UI.$("#cx-code-valider").onclick = valider;
    champ.addEventListener("keydown", (ev) => { if (ev.key === "Enter") valider(); });
    champ.addEventListener("input", () => {
      champ.value = champ.value.replace(/\D/g, "").slice(0, 6);
      if (champ.value.length === 6) valider();
    });
    UI.$("#cx-code-renvoyer").onclick = async (ev) => {
      const b = ev.currentTarget;
      b.disabled = true;
      try {
        await Supabase.renvoyerCodeTelephone();
        etat.textContent = "Nouveau code envoyé.";
      } catch (err) {
        etat.textContent = err.message || "Le code n'a pas pu partir.";
      }
      setTimeout(() => { b.disabled = false; }, 30000);
    };
    UI.$("#cx-code-retour").onclick = () => connexion(vue, apresConnexion);
  }

  /* ---------- Étape 3 : le code reçu par SMS ----------
     Quand l'enseigne l'exige, le mot de passe ne suffit plus. La base ne
     reconnaît AUCUN droit à cette session tant que le code n'a pas été
     rendu : cet écran n'est pas une politesse, c'est la seule porte. */

  function codeSms(vue, etat, suite) {
    document.getElementById("tabbar").style.display = "none";
    UI.entete({ accueil: true });

    vue.innerHTML =
      '<div class="carte carte-connexion">' +
        UI.marque(72) +
        '<h2 style="font-size:19px;font-weight:800;margin-top:6px">Confirmez votre connexion</h2>' +
        (etat && etat.numero
          ? '<p class="aide" style="margin:0 0 6px;text-align:center">Compte superadministrateur : ' +
              "BIZZOO demande un code reçu par SMS. Il part au numéro de votre compte, qui finit " +
              "par <strong>" + Utils.echapper(etat.fin_numero || "") + "</strong>.</p>" +
            /* L'APPAREIL DE CONFIANCE (3.59.0) : coché, le code n'est plus
               demandé sur cet appareil pendant un mois. */
            '<label class="cx-confiance"><input type="checkbox" id="cx-confiance"> ' +
              "Faire confiance à cet appareil pendant 1 mois</label>" +
            '<div id="cx-code"></div>'
          : '<p class="aide" style="margin:0 0 6px;text-align:center">Votre compte n\'a pas de ' +
              "numéro enregistré : le code ne peut partir nulle part. Demandez à un " +
              "<strong>superadministrateur</strong> de l'ajouter dans Comptes, puis " +
              "reconnectez-vous.</p>") +
        '<button type="button" class="btn btn-clair" id="cx-sortir">Se déconnecter</button>' +
      "</div>";

    UI.$("#cx-sortir").onclick = async () => {
      await Supabase.deconnexion();
      location.reload();
    };
    if (etat && etat.numero) {
      blocCode(UI.$("#cx-code"), {
        apres: async () => {
          Store.journaliser("compte", "connexion", "Connexion confirmée par SMS",
            Supabase.utilisateur());
          const confiance = UI.$("#cx-confiance");
          if (confiance && confiance.checked) {
            try {
              await Supabase.confierAppareil();
              UI.toast("Connexion confirmée — plus de code sur cet appareil pendant 1 mois", "ok");
            } catch (err) {
              UI.toast("Connexion confirmée, mais l'appareil n'a pas pu être gardé : " + err.message, "err");
            }
          } else {
            UI.toast("Connexion confirmée", "ok");
          }
          suite();
        },
      });
    }
  }

  /**
   * Recevoir un code, le rendre. Le même bloc sert à la connexion, et au
   * superadministrateur qui s'essaie dans les Réglages avant d'exiger le
   * code de toute l'équipe : c'est le même chemin, à la lettre.
   *
   * LE CODE NE PASSE JAMAIS PAR ICI DANS L'AUTRE SENS. La fonction Edge
   * l'envoie par SMS et n'en rend que les deux derniers chiffres du
   * numéro ; c'est la personne qui le tape.
   */
  function blocCode(zone, options) {
    const o = options || {};
    zone.innerHTML =
      '<button type="button" class="btn" id="code-demander">' + UI.icone("tel") +
        Utils.echapper(o.libelle || "Recevoir le code") + "</button>" +
      '<div id="code-saisie" hidden>' +
        '<div class="champ">' +
          '<label for="code-chiffres">Code reçu par SMS</label>' +
          '<input id="code-chiffres" type="text" inputmode="numeric" pattern="[0-9 ]*"' +
            ' autocomplete="one-time-code" maxlength="9" placeholder="6 chiffres">' +
        "</div>" +
        '<button type="button" class="btn" id="code-valider">' + UI.icone("check") +
          "Valider le code</button>" +
        '<button type="button" class="btn btn-clair" id="code-renvoyer" style="margin-top:10px">' +
          "Renvoyer un code</button>" +
      "</div>" +
      '<div class="aide code-etat" id="code-etat" role="status" aria-live="polite"></div>';

    const etat = UI.$("#code-etat", zone);
    const dire = (texte, erreur) => {
      etat.textContent = texte || "";
      etat.classList.toggle("code-etat-erreur", !!erreur);
    };

    /* Le renvoi attend : la base refuserait un second code dans les
       trente secondes, autant le dire avant qu'on appuie. */
    let minuterie = null;
    const patienter = (secondes) => {
      const renvoyer = UI.$("#code-renvoyer", zone);
      let reste = Math.max(1, Math.round(secondes) || 30);
      clearInterval(minuterie);
      renvoyer.disabled = true;
      const tic = () => {
        if (!zone.isConnected) { clearInterval(minuterie); return; }
        if (reste <= 0) {
          clearInterval(minuterie);
          renvoyer.disabled = false;
          renvoyer.textContent = "Renvoyer un code";
          return;
        }
        renvoyer.textContent = "Renvoyer un code (" + reste + " s)";
        reste -= 1;
      };
      tic();
      minuterie = setInterval(tic, 1000);
    };

    const montrerSaisie = () => {
      UI.$("#code-demander", zone).hidden = true;
      UI.$("#code-saisie", zone).hidden = false;
    };

    const demander = async (bouton) => {
      bouton.disabled = true;
      dire("Envoi du code…");
      try {
        const r = await Supabase.demanderCodeConnexion();
        if (r && r.ok && r.deja) {
          dire("Cette connexion est déjà confirmée.");
          if (o.apres) o.apres();
          return;
        }
        if (!r || !r.ok) {
          dire((r && r.message) || "Le code n'a pas pu partir.", true);
          if (r && r.raison === "trop_tot") {
            montrerSaisie();
            patienter(r.attente);
          } else {
            bouton.disabled = false;
          }
          return;
        }
        montrerSaisie();
        dire("Code envoyé au numéro qui finit par " + (r.fin_numero || "…") +
          ". Il expire dans 10 minutes.");
        UI.$("#code-chiffres", zone).value = "";
        UI.$("#code-chiffres", zone).focus();
        patienter(30);
      } catch (err) {
        dire(err.message || "Le code n'a pas pu partir.", true);
        bouton.disabled = false;
      }
    };

    UI.$("#code-demander", zone).onclick = (ev) => demander(ev.currentTarget);
    UI.$("#code-renvoyer", zone).onclick = (ev) => demander(ev.currentTarget);

    const RAISONS = {
      expire: "Ce code a expiré : demandez-en un nouveau.",
      sans_code: "Ce code ne vaut plus : demandez-en un nouveau.",
      sans_session: "Votre session a expiré : déconnectez-vous et reconnectez-vous.",
    };

    const valider = async () => {
      const bouton = UI.$("#code-valider", zone);
      const code = UI.$("#code-chiffres", zone).value.replace(/\D/g, "");
      if (code.length !== 6) {
        dire("Le code a six chiffres.", true);
        return;
      }
      bouton.disabled = true;
      try {
        const r = await Supabase.confirmerCodeConnexion(code);
        if (r && r.ok) {
          clearInterval(minuterie);
          dire("Code accepté.");
          if (o.apres) o.apres();
          return;
        }
        const raison = (r && r.raison) || "";
        if (raison === "code_faux") {
          const restants = Number(r.restants) || 0;
          dire(restants > 0
            ? "Code incorrect. Il vous reste " + restants + " essai" + (restants > 1 ? "s" : "") + "."
            : "Code incorrect, et plus d'essai pour celui-ci : demandez un nouveau code.", true);
        } else {
          dire(RAISONS[raison] || "Le code n'a pas été accepté.", true);
        }
      } catch (err) {
        dire(err.message || "Le code n'a pas été accepté.", true);
      }
      bouton.disabled = false;
    };
    UI.$("#code-valider", zone).onclick = valider;
    UI.$("#code-chiffres", zone).addEventListener("keydown", (ev) => {
      if (ev.key === "Enter") valider();
    });
  }

  return { configuration, connexion, codeSms, blocCode };
})();
