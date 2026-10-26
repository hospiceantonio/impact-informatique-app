/* =========================================================
   Mon compte — ma fiche (je corrige moi-même mes coordonnées),
   mes fiches de paie validées, mon mot de passe, ma boîte mail.
   ========================================================= */
const VueCompte = (() => {
  const { h } = UI;
  const STATUTS = { validee: ["Validée", "bleu"], payee: ["Payée", "vert"] };

  async function afficher(zone) {
    const moi = App.moi();
    const [[fiche], fiches, messagerie] = await Promise.all([
      Supabase.lire("rh_employes?select=*&id=eq." + moi.id),
      Supabase.lire("rh_fiches_paie?select=id,mois,statut,net&employe_id=eq." + moi.id + "&order=mois.desc&limit=24"),
      Supabase.rpc("rh_ma_messagerie").catch(() => null),
    ]);
    if (!zone.isConnected) return;
    const age = UI.age(fiche.date_naissance);

    /* Ce que l'employé complète lui-même. Son numéro, non : c'est par lui
       qu'il se connecte, l'administration le change. */
    const adresse = h("input", { value: fiche.adresse, placeholder: "Quartier, ville" });
    const emailPerso = h("input", { type: "email", value: fiche.email_perso, placeholder: "votre.adresse@exemple.com" });
    const choix = (valeur, options) => h("select", {}, options.map(([v, l]) => h("option", { value: v, selected: String(valeur ?? "") === v }, l)));
    const sexe = choix(fiche.sexe, [["", "À préciser"], ["F", "Femme"], ["M", "Homme"]]);
    const naissance = h("input", { type: "date", value: fiche.date_naissance || "" });
    const langue = h("input", { value: fiche.langue, placeholder: "Fon, Mina, Goun…" });
    const marie = h("input", { value: fiche.marie, placeholder: "Oui / Non" });
    const moto = choix(fiche.moto === null || fiche.moto === undefined ? "" : String(fiche.moto), [["", "À préciser"], ["true", "Oui"], ["false", "Non"]]);
    const boutonCoord = h("button", { class: "btn", type: "submit" }, "Enregistrer ma fiche");
    const manque = [!fiche.sexe && "votre sexe", !fiche.email_perso && "votre e-mail", !fiche.date_naissance && "votre date de naissance"].filter(Boolean);
    const coord = h("form", { class: "carte pile" },
      h("h2", {}, "Ma fiche"),
      manque.length ? h("div", { class: "avertissement" }, "À compléter : " + manque.join(", ") + ".") : null,
      h("div", { class: "formulaire" },
        h("label", { class: "champ" }, h("span", {}, "Téléphone (pour me connecter)"), h("input", { value: fiche.telephone, disabled: true }),
          h("small", {}, "Pour le changer, adressez-vous à l'administration.")),
        h("label", { class: "champ" }, h("span", {}, "E-mail"), emailPerso),
        h("label", { class: "champ" }, h("span", {}, "Sexe"), sexe),
        h("label", { class: "champ" }, h("span", {}, "Date de naissance"), naissance),
        h("label", { class: "champ" }, h("span", {}, "Lieu de résidence"), adresse),
        h("label", { class: "champ" }, h("span", {}, "Langue"), langue),
        h("label", { class: "champ" }, h("span", {}, "Marié(e)"), marie),
        h("label", { class: "champ" }, h("span", {}, "Moto"), moto)),
      h("div", { class: "actions" }, boutonCoord));
    coord.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      await UI.agir(boutonCoord, () => Supabase.modifier("rh_employes", "id=eq." + moi.id, {
        adresse: adresse.value.trim(), email_perso: emailPerso.value.trim(), sexe: sexe.value || null,
        date_naissance: naissance.value || null, langue: langue.value.trim(), marie: marie.value.trim(),
        moto: moto.value === "" ? null : moto.value === "true" }), "Fiche enregistrée.");
      afficher(zone);
    });

    /* Entré par numéro ou par e-mail, chacun peut changer son mot de passe. */
    const mdp = h("input", { type: "password", autocomplete: "new-password", minlength: 8, required: true });
    const mdp2 = h("input", { type: "password", autocomplete: "new-password", required: true });
    const boutonMdp = h("button", { class: "btn", type: "submit" }, "Changer mon mot de passe");
    const formMdp = h("form", { class: "carte pile" },
      h("h2", {}, "Mot de passe de l'application"),
      h("p", { class: "doux petit" }, "Celui avec lequel vous vous connectez ici. Le mot de passe de votre boîte mail est à part."),
      h("div", { class: "formulaire" },
        h("label", { class: "champ" }, h("span", {}, "Nouveau mot de passe (8 caractères au moins)"), mdp),
        h("label", { class: "champ" }, h("span", {}, "Le même, encore une fois"), mdp2)),
      h("div", { class: "actions" }, boutonMdp));
    formMdp.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      if (mdp.value.length < 8) return UI.echec("8 caractères au moins.");
      if (mdp.value !== mdp2.value) return UI.echec("Les deux mots de passe diffèrent.");
      await UI.agir(boutonMdp, () => Supabase.changerMotDePasse(mdp.value), "Mot de passe changé.");
      mdp.value = mdp2.value = "";
    });

    const boite = h("div", { class: "carte pile" },
      h("h2", {}, "Ma boîte mail"),
      h("p", {}, "Adresse : ", h("b", {}, fiche.email_pro || "aucune")),
      messagerie && messagerie.configuree
        ? h("p", { class: "doux petit" }, "Reliée le " + UI.dateHeure(messagerie.enregistre_le) + ".")
        : h("p", { class: "doux petit" }, "Pas encore reliée."),
      h("div", { class: "actions" },
        h("a", { class: "btn btn-second", href: "#/mails/reglage" }, messagerie && messagerie.configuree ? "Changer le mot de passe de la boîte" : "Relier ma boîte"),
        messagerie && messagerie.configuree ? h("button", { class: "btn btn-danger", onclick: async (ev) => {
          if (!await UI.confirmer("Oublier le mot de passe de votre boîte mail ? Il faudra le ressaisir pour lire vos mails ici.", { danger: true, valider: "Oublier" })) return;
          await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_oublier_ma_messagerie"), "Boîte déliée.");
          VueMails.oublier();
          App.naviguer();
        } }, "Délier") : null));

    UI.vider(zone,
      h("div", { class: "carte pile" },
        h("div", { class: "ligne" },
          h("div", { class: "avatar", style: { width: "54px", height: "54px", fontSize: "18px" } }, UI.initiales(fiche.nom, fiche.prenoms)),
          h("div", { class: "etire" }, h("h2", { style: { marginBottom: 0 } }, UI.nomComplet(fiche)),
            h("div", { class: "doux petit" }, [fiche.matricule, fiche.poste, moi.profil ? "Profil " + moi.profil : null].filter(Boolean).join(" · ")))),
        h("div", { class: "formulaire petit" },
          h("div", {}, h("div", { class: "doux" }, "Embauché le"), h("b", {}, UI.date(fiche.date_embauche))),
          h("div", {}, h("div", { class: "doux" }, "Statut"), h("b", {}, fiche.statut === "stagiaire" ? "Stagiaire" : "Employé")),
          h("div", {}, h("div", { class: "doux" }, "Âge"), h("b", {}, age !== null ? age + " ans" : "—")),
          h("div", {}, h("div", { class: "doux" }, "Salaire de base"), h("b", {}, UI.fcfa(fiche.salaire_base)))),
        h("p", { class: "doux tres-petit" }, "Une erreur sur votre fiche (nom, poste, salaire) ? Signalez-la à l'administration.")),
      h("div", { class: "carte pile" },
        h("h2", {}, "Mes fiches de paie"),
        fiches.length ? h("div", { class: "liste" }, fiches.map((f) =>
          h("a", { class: "element", href: "#/paie/fiche/" + f.id },
            h("span", { class: "etire gras" }, UI.mois(f.mois)), h("b", {}, UI.fcfa(f.net)),
            UI.etiquette(...(STATUTS[f.statut] || [f.statut, ""])))))
          : UI.vide("Aucune fiche validée pour l'instant.")),
      coord, boite, formMdp,
      h("button", { class: "btn btn-danger btn-plein", onclick: () => App.deconnecte() }, UI.icone("sortie", "ic-sm"), "Se déconnecter"));
  }

  return { titre: "Mon compte", afficher };
})();
