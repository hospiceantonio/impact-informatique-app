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

    const alertes = h("div", { class: "carte pile" }, h("h2", {}, "Alertes sur ce téléphone"), UI.chargement());
    carteAlertes(alertes);

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
      coord, alertes, boite, formMdp,
      h("button", { class: "btn btn-danger btn-plein", onclick: () => App.deconnecte() }, UI.icone("sortie", "ic-sm"), "Se déconnecter"));
  }

  /* ---------- Les alertes poussées sur le téléphone ----------
     Le navigateur s'abonne auprès de son service de push avec la clé
     publique de BIZZOO (rh_push_etat), et la base garde l'abonnement
     (rh_push_abonner). Ce qui part, et quand : la base en décide
     (types choisis, heures de silence, une fois par alerte). */

  /** La clé publique VAPID (base64url) en octets, comme la veut pushManager. */
  function octets(cle) {
    const b = cle.replace(/-/g, "+").replace(/_/g, "/");
    const brut = atob(b + "===".slice((b.length + 3) % 4));
    return Uint8Array.from(brut, (c) => c.charCodeAt(0));
  }
  const b64 = (tampon) => btoa(String.fromCharCode(...new Uint8Array(tampon))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

  async function abonnementActuel() {
    if (!("serviceWorker" in navigator) || !("PushManager" in window)) return null;
    const reg = await navigator.serviceWorker.getRegistration();
    return reg ? reg.pushManager.getSubscription() : null;
  }

  async function carteAlertes(carte) {
    const titre = h("h2", {}, "Alertes sur ce téléphone");
    let etat;
    try {
      etat = await Supabase.rpc("rh_push_etat");
    } catch (err) {
      return UI.vider(carte, titre, UI.erreur(err));
    }
    const possible = "serviceWorker" in navigator && "PushManager" in window && "Notification" in window && window.isSecureContext;
    const actuel = await abonnementActuel().catch(() => null);
    const prefs = etat.preferences || { actif: true, types: null, silence_debut: null, silence_fin: null };
    const types = etat.types || [];

    if (!etat.cle_publique) {
      return UI.vider(carte, titre, h("p", { class: "doux petit" },
        "Le service d'alertes n'est pas encore mis en marche par BIZZOO. Vos tâches restent dans « Ma file »."));
    }
    if (!possible) {
      return UI.vider(carte, titre, h("p", { class: "doux petit" },
        "Ce navigateur ne reçoit pas d'alertes. Sur Android, ouvrez BIZZOO Personnel dans Chrome ; sur iPhone, ajoutez-le d'abord à l'écran d'accueil."));
    }

    const activer = h("button", { class: "btn", onclick: async () => {
      await UI.agir(activer, async () => {
        const permission = await Notification.requestPermission();
        if (permission !== "granted") throw new Error("Les notifications sont refusées pour ce site : autorisez-les dans les réglages du navigateur.");
        const reg = await navigator.serviceWorker.ready;
        const abo = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: octets(etat.cle_publique) });
        const j = abo.toJSON();
        await Supabase.rpc("rh_push_abonner", { v_endpoint: j.endpoint, v_p256dh: j.keys.p256dh || b64(abo.getKey("p256dh")),
                                                v_auth: j.keys.auth || b64(abo.getKey("auth")) });
      }, "Alertes activées sur ce téléphone.");
      carteAlertes(carte);
    } }, "Activer les alertes sur ce téléphone");

    const couper = actuel ? h("button", { class: "btn btn-second", onclick: async () => {
      await UI.agir(couper, async () => {
        await Supabase.rpc("rh_push_desabonner", { v_endpoint: actuel.endpoint });
        await actuel.unsubscribe();
      }, "Ce téléphone ne recevra plus d'alertes.");
      carteAlertes(carte);
    } }, "Ne plus recevoir ici") : null;

    /* Les choix : en marche, les types, les heures de silence. */
    const marche = h("input", { type: "checkbox", checked: prefs.actif !== false });
    const tous = !prefs.types;
    const cases = types.map((t) => {
      const c = h("input", { type: "checkbox", value: t.type, checked: tous || prefs.types.includes(t.type) });
      return h("label", { class: "case petit" }, c, t.libelle);
    });
    const heures = (v) => h("select", {}, [h("option", { value: "", selected: v === null || v === undefined }, "—")]
      .concat(Array.from({ length: 24 }, (_, i) => h("option", { value: i, selected: v === i }, i + " h"))));
    const debut = heures(prefs.silence_debut), fin = heures(prefs.silence_fin);
    const enregistrer = h("button", { class: "btn btn-second", onclick: async () => {
      const coches = cases.map((l) => l.querySelector("input")).filter((c) => c.checked).map((c) => c.value);
      if (types.length && !coches.length) return UI.echec("Cochez au moins un type d'alerte, ou coupez les alertes.");
      if ((debut.value === "") !== (fin.value === "")) return UI.echec("Choisissez le début et la fin du silence, ou aucun des deux.");
      await UI.agir(enregistrer, () => Supabase.rpc("rh_push_regler", {
        v_actif: marche.checked, v_types: coches.length === types.length ? null : coches,
        v_silence_debut: debut.value === "" ? null : Number(debut.value), v_silence_fin: fin.value === "" ? null : Number(fin.value),
      }), "Choix enregistrés.");
    } }, "Enregistrer mes choix");

    UI.vider(carte, titre,
      h("p", { class: "doux petit" }, actuel
        ? "Ce téléphone reçoit les alertes de vos tâches (" + etat.appareils + " appareil(s) abonné(s) en tout). Le message ne contient jamais de montant ni de nom de client."
        : "Recevez une notification quand une tâche arrive dans votre file, ou quand personne n'a pris celle d'un profil que vous dirigez."),
      h("div", { class: "actions" }, actuel ? couper : activer),
      etat.preferences || actuel ? h("div", { class: "pile" },
        h("label", { class: "case" }, marche, "Alertes en marche"),
        types.length ? h("div", {}, h("div", { class: "doux petit" }, "Les alertes que je veux recevoir"), cases)
          : h("p", { class: "doux petit" }, "Aucun type d'alerte n'est confié à votre profil pour l'instant."),
        h("div", { class: "ligne petit" }, h("span", {}, "Silence de"), debut, h("span", {}, "à"), fin,
          h("span", { class: "doux" }, "(heure du Bénin)")),
        h("div", { class: "actions" }, enregistrer)) : null);
  }

  return { titre: "Mon compte", afficher };
})();
