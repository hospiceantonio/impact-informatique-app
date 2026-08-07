/* =========================================================
   Réglages — boutique, compte du gérant, connexion à la
   base, sauvegarde et restauration.
   ========================================================= */
const VueReglages = (() => {

  async function afficher(vue, params) {
    UI.entete({ titre: "Réglages", sous: "Boutique, compte et sauvegarde" });

    const r = Store.lireReglages();
    const configEnDur = typeof CONFIG !== "undefined" && !!CONFIG.SUPABASE_URL;
    const configActuelle = Supabase.configuration() || { url: "", cle: "" };

    vue.innerHTML =
      /* ---------- Boutique ---------- */
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("magasin", "ic-sm") + " La boutique</div>" +
        '<p class="aide" style="margin:0 0 12px">Ces informations s\'affichent dans l\'application client ' +
          "(contact, WhatsApp de commande…). Elles sont mises à jour immédiatement.</p>" +
        UI.champTexte({ id: "r-nom", label: "Nom", valeur: r.nomBoutique, obligatoire: true }) +
        UI.champTexte({ id: "r-slogan", label: "Slogan", valeur: r.slogan,
          aide: "Affiché en bandeau rouge dans l'application client." }) +
        UI.champZone({ id: "r-description", label: "Présentation", valeur: r.description, lignes: 3 }) +
        UI.champTexte({ id: "r-whatsapp", label: "Numéro WhatsApp (commandes)", valeur: r.whatsapp,
          type: "tel", placeholder: "01 97 00 00 00",
          aide: "Les clients commandent par ce numéro depuis l'application." }) +
        UI.champTexte({ id: "r-tel", label: "Téléphone (appels)", valeur: r.tel, type: "tel",
          placeholder: "01 97 00 00 00" }) +
        '<div class="champ-duo">' +
          UI.champTexte({ id: "r-indicatif", label: "Indicatif pays", valeur: r.indicatif, placeholder: "229" }) +
          UI.champTexte({ id: "r-devise", label: "Devise", valeur: r.devise, placeholder: "FCFA" }) +
        "</div>" +
        UI.champTexte({ id: "r-adresse", label: "Adresse", valeur: r.adresse,
          placeholder: "Quartier, rue, ville" }) +
        UI.champTexte({ id: "r-horaires", label: "Horaires", valeur: r.horaires,
          placeholder: "Lun–Sam : 8h–19h" }) +
        UI.champTexte({ id: "r-facebook", label: "Page Facebook (optionnel)", valeur: r.facebook,
          placeholder: "impactinformatique" }) +
        '<button type="button" class="btn" id="r-enregistrer">' + UI.icone("check") + "Enregistrer la boutique</button>" +
      "</div>" +

      /* ---------- Compte ---------- */
      '<div class="carte" id="section-compte">' +
        '<div class="carte-titre">' + UI.icone("cle", "ic-sm") + " Compte du gérant</div>" +
        '<p class="aide" style="margin:0 0 12px">Connecté en tant que <strong>' +
          Utils.echapper(Supabase.utilisateur() || "—") + "</strong>.<br>" +
          "Le mot de passe se change dans le tableau de bord Supabase (Authentication → Users).</p>" +
        '<button type="button" class="btn btn-clair" id="c-deconnexion">Se déconnecter</button>' +
      "</div>" +

      /* ---------- Connexion à la base ---------- */
      (!configEnDur
        ? '<div class="carte" id="section-base">' +
            '<div class="carte-titre">' + UI.icone("nuage", "ic-sm") + " Connexion à la base</div>" +
            UI.champTexte({ id: "b-url", label: "Adresse du projet Supabase", valeur: configActuelle.url,
              placeholder: "https://abcdefgh.supabase.co", type: "url" }) +
            UI.champTexte({ id: "b-cle", label: "Clé « anon public »", valeur: configActuelle.cle,
              placeholder: "eyJhbGciOi…" }) +
            '<div class="btn-rangee" style="margin-top:4px">' +
              '<button type="button" class="btn" id="b-enregistrer">' + UI.icone("check") + "Enregistrer</button>" +
              '<button type="button" class="btn btn-clair" id="b-tester">' + UI.icone("actualiser") + "Tester la connexion</button>" +
            "</div>" +
            '<div id="b-resultat"></div>' +
          "</div>"
        : "") +

      /* ---------- Sauvegarde ---------- */
      '<div class="carte">' +
        '<div class="carte-titre">' + UI.icone("telecharger", "ic-sm") + " Sauvegarde</div>" +
        '<p class="aide" style="margin:0 0 12px">Les données vivent déjà en ligne, mais une copie de secours ' +
          "(produits, photos, réglages) ne coûte rien : à garder sur WhatsApp, e-mail ou carte mémoire.</p>" +
        '<div class="btn-rangee">' +
          '<button type="button" class="btn btn-clair" id="s-exporter">' + UI.icone("telecharger") + "Exporter une sauvegarde</button>" +
          '<label class="btn btn-clair" for="s-importer-fichier">' + UI.icone("televerser") + "Restaurer une sauvegarde" +
            '<input type="file" id="s-importer-fichier" accept="application/json,.json" hidden></label>' +
        "</div>" +
        '<div id="s-progression" class="aide" style="margin-top:10px"></div>' +
      "</div>" +

      /* ---------- À propos ---------- */
      '<div class="carte">' +
        '<div class="carte-titre">À propos</div>' +
        '<p class="aide" style="margin:0">' +
          "Impact Admin — gestion du catalogue IMPACT INFORMATIQUE.<br>" +
          "Base en ligne : les modifications sont visibles immédiatement par les clients." +
        "</p>" +
      "</div>";

    if (params && params.section === "compte") {
      const section = UI.$("#section-compte");
      if (section) setTimeout(() => section.scrollIntoView({ behavior: "smooth", block: "start" }), 60);
    }

    /* ---------- Boutique ---------- */
    UI.$("#r-enregistrer").onclick = async () => {
      const nom = UI.$("#r-nom").value.trim();
      if (!nom) { UI.toast("Le nom de la boutique est obligatoire.", "err"); return; }
      try {
        await Store.majReglages({
          nomBoutique: nom,
          slogan: UI.$("#r-slogan").value.trim(),
          description: UI.$("#r-description").value.trim(),
          whatsapp: UI.$("#r-whatsapp").value.trim(),
          tel: UI.$("#r-tel").value.trim(),
          indicatif: UI.$("#r-indicatif").value.trim() || "229",
          devise: UI.$("#r-devise").value.trim() || "FCFA",
          adresse: UI.$("#r-adresse").value.trim(),
          horaires: UI.$("#r-horaires").value.trim(),
          facebook: UI.$("#r-facebook").value.trim(),
        });
        UI.toast("Boutique enregistrée — visible immédiatement chez les clients.", "ok");
      } catch (err) {
        UI.toast(err.message, "err");
      }
    };

    /* ---------- Compte ---------- */
    UI.$("#c-deconnexion").onclick = async () => {
      await Supabase.deconnexion();
      location.reload();
    };

    /* ---------- Connexion à la base ---------- */
    const btnBase = UI.$("#b-enregistrer");
    if (btnBase) {
      btnBase.onclick = () => {
        const url = UI.$("#b-url").value.trim();
        const cle = UI.$("#b-cle").value.trim();
        if (!/^https:\/\//.test(url) || !cle) {
          UI.toast("Indiquez l'adresse https://… et la clé du projet.", "err");
          return;
        }
        Supabase.majConfiguration(url, cle);
        UI.toast("Connexion enregistrée", "ok");
        setTimeout(() => location.reload(), 500);
      };
      UI.$("#b-tester").onclick = async () => {
        const zone = UI.$("#b-resultat");
        zone.innerHTML = '<div class="aide" style="margin-top:10px">Test en cours…</div>';
        try {
          Supabase.majConfiguration(UI.$("#b-url").value, UI.$("#b-cle").value);
          await Supabase.testerConnexion();
          zone.innerHTML = '<div class="note-ok" style="margin-top:10px">' + UI.icone("check", "ic-sm") +
            " Base joignable — tout est en ordre.</div>";
        } catch (err) {
          zone.innerHTML = '<div class="note-attente" style="margin-top:10px">' + UI.icone("alerte", "ic-sm") + " " +
            Utils.echapper(err.message) + "</div>";
        }
      };
    }

    /* ---------- Sauvegarde ---------- */
    UI.$("#s-exporter").onclick = async () => {
      const zone = UI.$("#s-progression");
      try {
        const donnees = await Store.exporter((texte) => { zone.textContent = texte; });
        zone.textContent = "";
        const jour = new Date().toISOString().slice(0, 10);
        Utils.telecharger("impact-catalogue-" + jour + ".json", JSON.stringify(donnees));
        UI.toast("Sauvegarde téléchargée", "ok");
      } catch (err) {
        zone.textContent = "";
        UI.toast(err.message, "err");
      }
    };

    UI.$("#s-importer-fichier").addEventListener("change", async (ev) => {
      const fichier = ev.target.files && ev.target.files[0];
      ev.target.value = "";
      if (!fichier) return;
      const ok = await UI.confirmer({
        titre: "Restaurer cette sauvegarde ?",
        texte: "Le contenu du fichier « " + fichier.name + " » sera réécrit dans le catalogue en ligne " +
          "(les produits du fichier remplacent ceux qui portent le même identifiant).",
        bouton: "Restaurer",
        danger: true,
      });
      if (!ok) return;
      const zone = UI.$("#s-progression");
      try {
        const donnees = JSON.parse(await fichier.text());
        const resultat = await Store.importer(donnees, (texte) => { zone.textContent = texte; });
        zone.textContent = "";
        UI.toast(resultat.produits + " produits restaurés", "ok");
        afficher(vue, params);
      } catch (err) {
        zone.textContent = "";
        UI.toast(err.message || "Fichier illisible", "err");
      }
    });
  }

  return { afficher };
})();
