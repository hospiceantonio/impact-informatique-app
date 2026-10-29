/* =========================================================
   Supabase — connexion à la base en ligne de la boutique.

   - configuration : config.js, ou saisie dans l'application
     (gardée sur le téléphone) tant que config.js est vide ;
   - compte : le gérant se connecte par email + mot de passe
     (compte créé dans Supabase, voir supabase/schema.sql) ;
   - données : tables `boutique`, `categories`,
     `sous_categories`, `produits` (lecture publique,
     écriture réservée au compte connecté) ;
   - photos : bucket public `produits`.
   ========================================================= */
const Supabase = (() => {

  const CLE_CONFIG = "impact-config";    // configuration saisie dans l'app
  const CLE_SESSION = "impact-session";  // session du gérant
  const BUCKET = "produits";

  /* ---------- Configuration ---------- */

  function configuration() {
    let url = "", cle = "";
    try {
      const brut = localStorage.getItem(CLE_CONFIG);
      if (brut) {
        const c = JSON.parse(brut);
        url = c.url || "";
        cle = c.cle || "";
      }
    } catch (_) { /* configuration locale illisible */ }
    if (!url && typeof CONFIG !== "undefined") {
      url = CONFIG.SUPABASE_URL || "";
      cle = CONFIG.SUPABASE_ANON_KEY || "";
    }
    url = url.trim().replace(/\/+$/, "");
    cle = cle.trim();
    if (!/^https:\/\//.test(url) || !cle) return null;
    return { url, cle };
  }

  const estConfigure = () => !!configuration();

  /** Config saisie dans l'app (prioritaire sur config.js). */
  function majConfiguration(url, cle) {
    localStorage.setItem(CLE_CONFIG, JSON.stringify({
      url: (url || "").trim().replace(/\/+$/, ""),
      cle: (cle || "").trim(),
    }));
  }

  function configurationSaisie() {
    try {
      const c = JSON.parse(localStorage.getItem(CLE_CONFIG) || "null");
      return c && c.url ? c : null;
    } catch (_) { return null; }
  }

  /* ---------- Session du gérant ---------- */

  let session = null;
  try { session = JSON.parse(localStorage.getItem(CLE_SESSION) || "null"); } catch (_) { /* vide */ }

  function garderSession(s) {
    session = s;
    if (s) localStorage.setItem(CLE_SESSION, JSON.stringify(s));
    else localStorage.removeItem(CLE_SESSION);
  }

  const utilisateur = () => (session ? session.email : null);

  /** Identifiant du compte, lu dans le jeton lui-même (champ « sub »). */
  function identifiant() {
    if (!session || !session.access_token) return null;
    try {
      let charge = session.access_token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
      charge += "===".slice((charge.length + 3) % 4);
      const brut = atob(charge);
      const octets = Uint8Array.from(brut, (c) => c.charCodeAt(0));
      return JSON.parse(new TextDecoder().decode(octets)).sub || null;
    } catch (_) {
      return null;
    }
  }

  async function appelAuth(chemin, corps, avecSession, methode) {
    const c = configuration();
    if (!c) throw new Error("L'application n'est pas encore reliée à la base (voir réglages).");
    let reponse;
    try {
      reponse = await fetch(c.url + "/auth/v1/" + chemin, {
        method: methode || "POST",
        headers: {
          "apikey": c.cle,
          "Content-Type": "application/json",
          ...(avecSession && session ? { "Authorization": "Bearer " + session.access_token } : {}),
        },
        body: corps ? JSON.stringify(corps) : "{}",
      });
    } catch (_) {
      throw new Error("Impossible de joindre la base. Vérifiez votre connexion internet.");
    }
    if (reponse.status === 204) return {};
    const donnees = await reponse.json().catch(() => ({}));
    if (!reponse.ok) {
      const code = donnees.error_code || donnees.error || "";
      const texte = donnees.msg || donnees.error_description || donnees.message || "";
      /* Avant « identifiants invalides » : GoTrue range ce refus sous le
         même « invalid_grant », et ne le prononce qu'une fois le mot de
         passe vérifié. Il ne manque que le code qui confirmera le numéro. */
      if (code === "phone_not_confirmed" || /phone not confirmed/i.test(texte)) {
        const e = new Error("Numéro pas encore confirmé.");
        e.code = "phone_not_confirmed";
        throw e;
      }
      if (code === "otp_expired" || /token has expired|invalid otp/i.test(texte)) {
        throw new Error("Code incorrect ou expiré. Demandez-en un nouveau.");
      }
      if (code === "over_sms_send_rate_limit" || reponse.status === 429) {
        throw new Error("Trop de tentatives. Patientez une minute.");
      }
      if (code === "phone_exists" || code === "user_already_exists" ||
          /already registered|phone.*already/i.test(texte)) {
        throw new Error("Ce numéro ou cette adresse a déjà un compte BIZZOO.");
      }
      if (code === "invalid_credentials" || code === "invalid_grant" ||
          /invalid login credentials/i.test(donnees.msg || donnees.error_description || "")) {
        throw new Error("Email ou mot de passe incorrect.");
      }
      throw new Error(donnees.msg || donnees.error_description || donnees.message ||
        "La connexion a échoué (" + reponse.status + ").");
    }
    return donnees;
  }

  async function connexion(email, motDePasse) {
    const d = await appelAuth("token?grant_type=password", { email, password: motDePasse });
    garderSession({
      access_token: d.access_token,
      refresh_token: d.refresh_token,
      expire_a: (d.expires_at ? d.expires_at * 1000 : Date.now() + (d.expires_in || 3600) * 1000),
      email: d.user && d.user.email ? d.user.email : email,
    });
    return utilisateur();
  }

  /* ---------- Le numéro, la porte des livreurs ----------
     Numéro et mot de passe. (3.59.0) Le code reçu par SMS ne sert plus
     qu'une fois, à confirmer le numéro d'un compte qui vient d'être créé ;
     ensuite le mot de passe suffit, comme pour les clients. Avant : Le mot de passe se vérifie d'abord ; la session
     qu'il ouvre n'est pas gardée : elle attend le code, puis elle est
     fermée. C'est la session du code qui entre, et la base la reconnaît
     (« session_confirmee » : un livreur entré par code n'a pas à en
     rendre un second quand l'enseigne exige le code de l'équipe). */

  const INDICATIF = "229";
  function telInternational(brut) {
    let chiffres = String(brut || "").replace(/\D/g, "");
    if (!chiffres) return "";
    if (chiffres.startsWith("00")) chiffres = chiffres.slice(2);
    if (!chiffres.startsWith(INDICATIF)) chiffres = INDICATIF + chiffres;
    return "+" + chiffres;
  }
  /** « +229 01 97 12 15 96 » : un numéro se dicte par groupes de deux. */
  function telAffichage(brut) {
    let chiffres = String(brut || "").replace(/\D/g, "");
    if (chiffres.startsWith(INDICATIF) && chiffres.length > INDICATIF.length + 7) {
      chiffres = chiffres.slice(INDICATIF.length);
    }
    return chiffres ? "+" + INDICATIF + " " + (chiffres.match(/.{1,2}/g) || []).join(" ") : "";
  }
  /** Ce qu'on tape ressemble-t-il à un numéro plutôt qu'à un e-mail ? */
  const estNumero = (texte) => !/@/.test(texte || "") &&
    String(texte || "").replace(/\D/g, "").length >= 8;

  let attenteTel = null;

  async function connexionTelephone(tel, motDePasse) {
    const numero = telInternational(tel);
    let jetonMdp = "";
    let confirme = true;
    try {
      const d = await appelAuth("token?grant_type=password", { phone: numero, password: motDePasse });
      jetonMdp = d.access_token || "";
      /* Numéro déjà confirmé : on entre, sans code (3.59.0). */
      if (jetonMdp) {
        garderSession({
          access_token: d.access_token,
          refresh_token: d.refresh_token,
          expire_a: (d.expires_at ? d.expires_at * 1000 : Date.now() + (d.expires_in || 3600) * 1000),
          email: (d.user && d.user.email) || telAffichage(numero),
        });
        return { numero, affichage: telAffichage(numero), entre: true };
      }
    } catch (err) {
      if (err.code === "phone_not_confirmed") confirme = false;
      else if (/incorrect/.test(err.message || "")) throw new Error("Numéro ou mot de passe incorrect.");
      else throw err;
    }
    /* Un compte que l'administrateur vient de créer n'a pas encore son
       numéro confirmé : son code se redemande par « resend ». Le même
       code, validé, confirme le numéro et ouvre la session. */
    const envoyer = confirme
      ? () => appelAuth("otp", { phone: numero, create_user: false })
      : () => appelAuth("resend", { type: "sms", phone: numero });
    await envoyer();
    attenteTel = { numero, jetonMdp, envoyer };
    return { numero, affichage: telAffichage(numero) };
  }

  async function renvoyerCodeTelephone() {
    if (!attenteTel) throw new Error("Reprenez la connexion depuis le début.");
    await attenteTel.envoyer();
  }

  async function confirmerCodeTelephone(code) {
    if (!attenteTel) throw new Error("Reprenez la connexion depuis le début.");
    const d = await appelAuth("verify", {
      type: "sms", phone: attenteTel.numero, token: String(code || "").replace(/\D/g, ""),
    });
    if (!d.access_token) throw new Error("Code incorrect ou expiré.");
    garderSession({
      access_token: d.access_token,
      refresh_token: d.refresh_token,
      expire_a: (d.expires_at ? d.expires_at * 1000 : Date.now() + (d.expires_in || 3600) * 1000),
      email: (d.user && d.user.email) || telAffichage(attenteTel.numero),
    });
    /* « scope=local » : sans lui, GoTrue fermerait TOUTES les sessions du
       compte — celle du code comprise. */
    const jetonMdp = attenteTel.jetonMdp;
    attenteTel = null;
    const c = configuration();
    if (jetonMdp && c) {
      fetch(c.url + "/auth/v1/logout?scope=local", {
        method: "POST",
        headers: { "apikey": c.cle, "Authorization": "Bearer " + jetonMdp, "Content-Type": "application/json" },
        body: "{}",
      }).catch(() => { /* elle expirera d'elle-même */ });
    }
    /* L'e-mail que l'administrateur a noté sur la fiche devient, à la
       première connexion, la seconde porte du compte : GoTrue n'accepte
       qu'un identifiant à l'inscription, le numéro est passé d'abord. */
    if (!(d.user && d.user.email)) {
      try {
        const lignes = await requete("GET", "profils?select=email&id=eq." +
          encodeURIComponent((d.user && d.user.id) || ""), undefined, { avecSession: true });
        const email = ((lignes || [])[0] || {}).email || "";
        if (/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
          await appelAuth("user", { email }, true, "PUT");
        }
      } catch (_) { /* la porte e-mail attendra : le numéro suffit */ }
    }
    return utilisateur();
  }

  async function deconnexion() {
    /* (3.65.0) Ce téléphone se tait pour ce compte, tant que la session
       peut encore le dire à la base. */
    if (typeof Push !== "undefined") { try { await Push.oublier(); } catch (_) { /* vide */ } }
    if (typeof SuiviPosition !== "undefined") { SuiviPosition.arreter(); SuiviPosition.arreterPresence(); }
    try { await appelAuth("logout", {}, true); } catch (_) { /* déjà expirée */ }
    garderSession(null);
    profil = null;
  }

  /* ---------- Rôle du compte connecté ----------
     administrateur : toute l'application, et lui seul crée les comptes.
     moderateur     : les produits et les catégories.
     Tant que la table `profils` n'existe pas (base pas encore mise à
     jour), on garde le fonctionnement d'avant : le compte a tous les
     droits. Personne ne se retrouve bloqué par une migration oubliée. */

  let profil = null;
  let rolesEnBase = true;

  async function chargerProfil() {
    profil = null;
    const id = identifiant();
    if (!id) return null;
    let lignes;
    try {
      lignes = await requete("GET", "profils?select=*&id=eq." + encodeURIComponent(id), undefined,
        { avecSession: true });
    } catch (err) {
      if (/n'existent pas encore|does not exist/i.test(err.message || "")) {
        rolesEnBase = false;   // ancienne base : on ne bride rien
        return null;
      }
      throw err;
    }
    rolesEnBase = true;
    const l = (lignes || [])[0];
    if (l) {
      profil = {
        id: l.id, email: l.email || "", role: l.role, actif: l.actif !== false,
        nom: l.nom || "", tel: l.tel || "",
        /* Colonne absente d'une base pas encore mise à jour : on n'enlève rien. */
        peutModifier: l.peut_modifier_produits !== false,
        /* Boutique du modérateur ; vide pour un administrateur. */
        boutiqueId: l.boutique_id || "",
        /* Les interrupteurs d'un compte d'enseigne. Absents d'une base
           pas encore mise à jour : on prend le défaut du schéma, et
           « est_compte_enseigne() » restera faux de toute façon. */
        peutCommandes: l.peut_commandes !== false,
        peutBoutiques: l.peut_boutiques === true,
        peutFinances: l.peut_finances === true,
        /* (3.68.0) « Faire livrer » : accordé par le superadministrateur
           seul, éteint par défaut. */
        faireLivrer: l.peut_faire_livrer === true,
      };
    }
    return profil;
  }

  const compte = () => profil;
  const rolesActifs = () => rolesEnBase;
  const role = () => (profil ? profil.role : rolesEnBase ? null : "superadministrateur");
  /** Le superadministrateur : toute l'enseigne, boutiques comprises. */
  const estSuper = () => role() === "superadministrateur";
  /**
   * Un compte de BIZZOO : administrateur ou modérateur rattaché à
   * AUCUNE boutique. Il travaille sur toutes, dans la limite de ses
   * interrupteurs. Le miroir exact de « est_compte_enseigne() » en base
   * — et c'est la base qui tranche, cette fonction ne sert qu'à
   * l'écran.
   */
  const estCompteEnseigne = () => !!profil && !profil.boutiqueId &&
    (profil.role === "administrateur" || profil.role === "moderateur");
  /** Un interrupteur d'enseigne. Faux pour qui n'est pas de l'enseigne. */
  const droitEnseigne = (lequel) => {
    if (!estCompteEnseigne()) return false;
    if (lequel === "commandes") return profil.peutCommandes !== false;
    if (lequel === "boutiques") return profil.peutBoutiques === true;
    if (lequel === "finances") return profil.peutFinances === true;
    if (lequel === "produits") return profil.peutModifier !== false;
    return false;
  };
  /** (3.68.0) « Faire livrer » une commande prise sur WhatsApp : le
      superadministrateur, et les comptes de BIZZOO à qui il a accordé ce
      droit. Le miroir de « peut_faire_livrer() » en base — qui tranche. */
  const peutFaireLivrer = () => estSuper() ||
    (estCompteEnseigne() && profil.actif !== false && profil.faireLivrer === true);
  /** L'administrateur de BIZZOO (3.59.0) : un administrateur sans
      boutique. Il crée et gère les livreurs, crée les revendeurs et
      valide leurs demandes. Le miroir de « est_admin_bizzoo() ». */
  const estAdminBizzoo = () => !!profil && profil.actif && !profil.boutiqueId &&
    profil.role === "administrateur";
  /** Droits d'administration — sur toute l'enseigne, ou sur sa boutique.
      POUR UN COMPTE D'ENSEIGNE, C'EST L'INTERRUPTEUR « LES BOUTIQUES »
      QUI DÉCIDE, pas son rang : exactement ce que fait « administre() »
      en base. Sans cela, un administrateur de BIZZOO à qui l'on n'a pas
      ouvert les boutiques voyait les réglages et le slider… que la base
      lui refusait à l'enregistrement. */
  const estAdmin = () => estSuper() ||
    (estCompteEnseigne() ? droitEnseigne("boutiques") : role() === "administrateur");
  /** Passe d'une boutique à l'autre : le superadministrateur, et le
      compte d'enseigne, qui travaille sur toutes. Les autres restent
      dans la leur — et le livreur n'a pas besoin d'en ouvrir une. */
  const peutChangerDeBoutique = () => estSuper() || estCompteEnseigne();
  /** Retoucher un produit déjà au catalogue : les administrateurs toujours,
      le modérateur si on le lui a accordé. Pour un compte d'enseigne,
      c'est SON interrupteur qui décide, quel que soit son rang. */
  /* L'HABILITATION VAUT POUR TOUS (3.59.0) : créer, modifier ou
     supprimer un produit. Un administrateur de boutique ne l'a plus
     d'office ; seul le superadministrateur passe outre. Le miroir de
     « peut_modifier_produits() » en base. */
  const peutModifierProduits = () => estSuper() ||
    (estCompteEnseigne() ? droitEnseigne("produits")
                         : !!(profil && profil.actif && profil.peutModifier));
  /** Les commandes, et les chiffres : mêmes règles qu'en base. */
  /* LA CAISSE DES LIVREURS (3.59.0) : l'argent encaissé à la livraison.
     Le superadministrateur, un compte de BIZZOO qui suit les commandes ou
     les finances, l'administrateur d'une boutique — pas un modérateur.
     La base en décide de même (« tient_la_caisse »). */
  const tientLaCaisse = () => estSuper() ||
    (estCompteEnseigne() ? droitEnseigne("commandes") || droitEnseigne("finances")
                         : role() === "administrateur");
  const peutVoirCommandes = () => estSuper() ||
    (estCompteEnseigne() ? droitEnseigne("commandes") : !!profil);
  const peutVoirFinances = () => estSuper() ||
    (estCompteEnseigne() ? droitEnseigne("finances") : !!profil);
  /** La boutique confiée au compte. Vide pour un superadministrateur :
      il les gère toutes. Vide aussi pour un compte d'enseigne. */
  const boutiqueDuCompte = () => (estSuper() ? "" : (profil && profil.boutiqueId) || "");
  /** Membre actif de l'équipe : sans fiche active, aucune écriture n'est permise. */
  const compteActif = () => !rolesEnBase || !!(profil && profil.actif);

  /* ---------- Un seul rafraîchissement à la fois (3.63.0) ----------
     Les écrans qui s'ouvrent ensemble au démarrage demandaient chacun le
     leur, avec le même jeton : GoTrue remplace ce jeton à chaque usage,
     et les suivants se le voyaient refuser. Tout le monde attend donc le
     même appel. Et avant de conclure que la session est perdue, on
     relit celle que le navigateur garde : un autre onglet a pu la
     renouveler entre-temps. Même leçon que l'application cliente, où une
     session tombée en silence laissait partir des commandes sans compte. */
  let rafraichissement = null;

  function sessionGardee() {
    try { return JSON.parse(localStorage.getItem(CLE_SESSION) || "null"); } catch (_) { return null; }
  }

  async function rafraichir() {
    const rangee = sessionGardee();
    if (rangee && rangee.refresh_token && session &&
        rangee.refresh_token !== session.refresh_token) {
      session = rangee;
      if (session.expire_a - Date.now() > 60000) return session;
    }
    const courante = session;
    try {
      const d = await appelAuth("token?grant_type=refresh_token", { refresh_token: courante.refresh_token });
      garderSession({
        access_token: d.access_token,
        refresh_token: d.refresh_token || courante.refresh_token,
        expire_a: (d.expires_at ? d.expires_at * 1000 : Date.now() + (d.expires_in || 3600) * 1000),
        email: courante.email,
      });
      return session;
    } catch (err) {
      if (/connexion internet/.test(err.message || "")) return session; // hors ligne : on tentera
      const relue = sessionGardee();
      if (relue && relue.refresh_token && relue.refresh_token !== courante.refresh_token &&
          relue.expire_a - Date.now() > 60000) {
        session = relue;
        return session;
      }
      garderSession(null);
      return null;
    }
  }

  /** Renvoie une session valide (rafraîchie si besoin), sinon null. */
  async function assurerSession() {
    if (!session) return null;
    if (session.expire_a - Date.now() > 60000) return session;
    if (!rafraichissement) {
      rafraichissement = rafraichir().finally(() => { rafraichissement = null; });
    }
    return rafraichissement;
  }

  const sessionPresente = () => !!session;

  /* ---------- Base de données (REST) ---------- */

  async function requete(methode, chemin, corps, options) {
    const c = configuration();
    if (!c) throw new Error("L'application n'est pas encore reliée à la base (voir réglages).");
    const o = options || {};
    const entetes = { "apikey": c.cle };

    if ((methode === "GET" && !o.avecSession) || o.anonyme) {
      /* Lecture anonyme : la clé publiable suffit (l'en-tête Authorization
         est réservé au jeton du gérant connecté). */
    } else {
      const s = await assurerSession();
      if (!s) {
        const err = new Error("Session expirée : reconnectez-vous.");
        err.deconnecte = true;
        throw err;
      }
      entetes["Authorization"] = "Bearer " + s.access_token;
    }
    /* Seules les écritures de contenu public demandent l'accord. La
       modération, les commandes et les livraisons restent accessibles. */
    const ressource = chemin.split("?")[0];
    if (["POST", "PATCH", "PUT"].includes(methode) &&
        /^(boutique|boutiques|produits|categories|sous_categories|slides|rpc\/repondre_avis)$/.test(ressource)) {
      await ConditionsUGC.assurer();
    }
    if (corps !== undefined) entetes["Content-Type"] = "application/json";
    if (methode === "POST" && !o.sansRetour) entetes["Prefer"] = "return=representation";
    /* « sansRetour » vaut aussi pour la modification, et ce n'est pas
       une économie de réseau.

       POSTGREST ÉCRIT « returning * » QUAND ON LUI DEMANDE LA LIGNE.
       Sur une table dont la LECTURE est restreinte par colonne — et
       « commande_lignes » l'est, pour que l'équipe ne voie ni le prix
       BIZZOO ni le taux de marge —, ce « * » réclame des colonnes
       fermées, et la base refuse TOUTE la requête. L'écriture était
       pourtant permise : c'est le retour qui la faisait tomber.

       L'appelant qui n'a que faire de la ligne demande donc à ne rien
       recevoir. Cela vaut mieux que de nommer les colonnes permises :
       une colonne fermée ajoutée demain casserait de nouveau. */
    if (methode === "PATCH") {
      entetes["Prefer"] = o.sansRetour ? "return=minimal" : "return=representation";
    }
    if (o.upsert) entetes["Prefer"] = "resolution=merge-duplicates,return=representation";

    let reponse;
    try {
      reponse = await fetch(c.url + "/rest/v1/" + chemin, {
        method: methode,
        headers: entetes,
        body: corps !== undefined ? JSON.stringify(corps) : undefined,
      });
    } catch (_) {
      throw new Error("Impossible de joindre la base. Vérifiez votre connexion internet.");
    }

    if (reponse.status === 204) return null;
    const donnees = await reponse.json().catch(() => null);
    if (!reponse.ok) {
      const message = (donnees && (donnees.message || donnees.hint)) || "";
      if (reponse.status === 401) {
        const err = new Error("Session expirée : reconnectez-vous.");
        err.deconnecte = true;
        throw err;
      }
      if (reponse.status === 404 && /relation .* does not exist|Could not find the table/i.test(message)) {
        throw new Error("Les tables n'existent pas encore : exécutez supabase/schema.sql dans le projet Supabase.");
      }
      /* Une colonne manquante veut dire une base pas encore à jour :
         le gérant a un fichier SQL à passer, pas un bogue à signaler. */
      if (/Could not find the '[^']*' column|column .* does not exist/i.test(message)) {
        throw new Error("Cette nouveauté demande une mise à jour de la base : " +
          "exécutez le dernier fichier SQL dans Supabase (SQL Editor).");
      }
      if (reponse.status === 409 || /foreign key/i.test(message)) {
        throw new Error("Suppression impossible : cet élément est encore utilisé par des produits.");
      }
      if (reponse.status === 403 || /row-level security/i.test(message)) {
        /* Le même refus a deux causes bien différentes : un droit retiré au
           compte, ou une session qui n'est pas celle du gérant. On nomme
           celle qui correspond, sinon le message envoie sur une fausse piste. */
        if (/^produits/.test(chemin) && methode !== "POST" && !peutModifierProduits()) {
          throw new Error("Votre compte n'a pas le droit de modifier les produits du catalogue. " +
            "Demandez ce droit à l'administrateur.");
        }
        throw new Error("Écriture refusée par la base : votre compte n'a pas ce droit. " +
          "Voyez l'administrateur de la boutique.");
      }
      throw new Error(message || "La base a répondu « " + reponse.status + " ».");
    }
    return donnees;
  }

  /* ---------- Stockage des photos ---------- */

  function urlImage(chemin) {
    const c = configuration();
    if (!c || !chemin) return "";
    return c.url + "/storage/v1/object/public/" + BUCKET + "/" + chemin;
  }

  function blobDepuisDataUrl(dataUrl) {
    const [entete, base64] = String(dataUrl).split(",");
    const type = (entete.match(/data:([^;]+)/) || [])[1] || "image/jpeg";
    const brut = atob(base64);
    const octets = new Uint8Array(brut.length);
    for (let i = 0; i < brut.length; i++) octets[i] = brut.charCodeAt(i);
    return new Blob([octets], { type });
  }

  /** Envoie un fichier (photo ou vidéo) dans le stockage de la boutique. */
  async function televerserFichier(chemin, contenu, type, nomLisible) {
    const c = configuration();
    if (!c) throw new Error("L'application n'est pas encore reliée à la base (voir réglages).");
    const s = await assurerSession();
    if (!s) {
      const err = new Error("Session expirée : reconnectez-vous.");
      err.deconnecte = true;
      throw err;
    }
    await ConditionsUGC.assurer();
    const quoi = nomLisible || "fichier";
    let reponse;
    try {
      reponse = await fetch(c.url + "/storage/v1/object/" + BUCKET + "/" + chemin, {
        method: "POST",
        headers: {
          "apikey": c.cle,
          "Authorization": "Bearer " + s.access_token,
          "Content-Type": type || "application/octet-stream",
          "x-upsert": "true",
        },
        body: contenu,
      });
    } catch (_) {
      throw new Error("Envoi de la " + quoi + " impossible. Vérifiez votre connexion internet.");
    }
    if (!reponse.ok) {
      const d = await reponse.json().catch(() => ({}));
      if (reponse.status === 413) {
        throw new Error("La " + quoi + " est trop lourde pour la base. Choisissez un fichier plus court.");
      }
      /* Un refus des règles de sécurité ne dit rien à qui tient la boutique :
         on nomme l'étape qui bloque et ce qu'il y a à faire. */
      if (reponse.status === 403 || /row-level security|not authorized/i.test(d.message || "")) {
        throw new Error("Envoi de la " + quoi + " refusé par la base. " +
          "Votre compte n'a pas le droit d'ajouter des fichiers : " +
          "l'administrateur doit exécuter le dernier fichier SQL dans Supabase.");
      }
      throw new Error("Envoi de la " + quoi + " refusé (" + reponse.status + ")" +
        (d.message ? " — " + d.message : "") + ".");
    }
    return chemin;
  }

  const televerserImage = (chemin, dataUrl) =>
    televerserFichier(chemin, blobDepuisDataUrl(dataUrl), "image/jpeg", "photo");

  const televerserVideo = (chemin, fichier) =>
    televerserFichier(chemin, fichier, fichier.type || "video/mp4", "vidéo");

  /** Suppression silencieuse : un fichier orphelin ne bloque jamais. */
  async function supprimerImages(chemins) {
    if (!chemins || !chemins.length) return;
    const c = configuration();
    const s = await assurerSession();
    if (!c || !s) return;
    try {
      await fetch(c.url + "/storage/v1/object/" + BUCKET, {
        method: "DELETE",
        headers: {
          "apikey": c.cle,
          "Authorization": "Bearer " + s.access_token,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ prefixes: chemins }),
      });
    } catch (_) { /* au pire, la photo reste dans le stockage */ }
  }

  /* ---------- Création de comptes (administrateur) ----------
     Le compte est créé par l'inscription publique de Supabase, avec la
     clé publiable : la clé « service_role », elle, ne doit jamais quitter
     le serveur. La session renvoyée pour le nouveau venu est jetée —
     l'administrateur reste connecté sur son propre compte. */

  async function creerCompte(email, motDePasse, donnees) {
    /* « donnees » : les métadonnées du compte. Un particulier qui reçoit
       un code promo est un CLIENT (« compte: client ») : la base ne lui
       fabrique pas de fiche d'équipe en attente. */
    const d = await appelAuth("signup", donnees
      ? { email, password: motDePasse, data: donnees }
      : { email, password: motDePasse });
    const u = d.user || d;
    if (!u || !u.id) throw new Error("Le compte n'a pas pu être créé.");
    /* Supabase répond poliment même si l'adresse est déjà prise : dans ce
       cas il ne rattache aucune identité au compte renvoyé. */
    if (Array.isArray(u.identities) && u.identities.length === 0) {
      throw new Error("Cette adresse a déjà un compte.");
    }
    return {
      id: u.id,
      email: u.email || email,
      /* Sans session renvoyée, Supabase attend une confirmation par email. */
      confirmationRequise: !d.access_token && !u.email_confirmed_at,
    };
  }

  /**
   * Un compte créé par son NUMÉRO — les livreurs. Pas d'e-mail exigé :
   * GoTrue envoie au livreur un code de confirmation, et c'est sa
   * première connexion (numéro, mot de passe, code) qui le confirme.
   */
  async function creerCompteTelephone(tel, motDePasse, donnees) {
    const numero = telInternational(tel);
    const d = await appelAuth("signup", { phone: numero, password: motDePasse, data: donnees || {} });
    const u = d.user || d;
    if (!u || !u.id) throw new Error("Le compte n'a pas pu être créé.");
    if (Array.isArray(u.identities) && u.identities.length === 0) {
      throw new Error("Ce numéro a déjà un compte BIZZOO.");
    }
    return { id: u.id, tel: numero, confirmationRequise: false };
  }

  /** Change le mot de passe du compte connecté. */
  async function changerMotDePasse(nouveau) {
    await appelAuth("user", { password: nouveau }, true, "PUT");
    return true;
  }

  /**
   * Appelle une fonction SQL de la base (supprimer un compte, changer un
   * mot de passe) : ce que la clé publiable ne permet pas de faire seule.
   */
  async function rpc(nom, parametres) {
    return requete("POST", "rpc/" + nom, parametres || {}, { sansRetour: true });
  }

  /**
   * Une fonction SQL dont on veut la RÉPONSE, et non le seul succès :
   * les statistiques de ventes, par exemple. Le jeton du gérant est
   * joint — c'est lui que la base regarde pour décider.
   */
  async function rpcLecture(nom, parametres) {
    return requete("POST", "rpc/" + nom, parametres || {}, { avecSession: true });
  }

  /**
   * Appelle une fonction Edge — du code à nous, qui tourne sur le
   * serveur de Supabase. Ce n'est ni PostgREST ni la base : d'où ce
   * chemin à part.
   *
   * Le jeton du gérant part avec, et la fonction s'en sert pour demander
   * à LA BASE qui appelle. Un rôle qu'on lui enverrait dans le corps de
   * la requête ne vaudrait rien — il viendrait de cet écran.
   *
   * On rend la réponse même quand elle refuse : une fonction qui
   * explique pourquoi vaut mieux qu'un code HTTP tout seul.
   */
  async function fonctionEdge(nom, corps) {
    const c = configuration();
    if (!c) throw new Error("L'application n'est pas encore reliée à la base (voir réglages).");
    const s = await assurerSession();
    if (!s) throw new Error("Votre session a expiré : reconnectez-vous.");
    let reponse;
    try {
      reponse = await fetch(c.url + "/functions/v1/" + nom, {
        method: "POST",
        headers: {
          "apikey": c.cle,
          "Authorization": "Bearer " + s.access_token,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(corps || {}),
      });
    } catch (_) {
      throw new Error("Serveur injoignable. Vérifiez votre connexion internet.");
    }
    const d = await reponse.json().catch(() => null);
    if (d === null) {
      throw new Error("La fonction « " + nom + " » n'a rien répondu (" +
        reponse.status + "). Est-elle déployée ?");
    }
    return d;
  }

  /* ---------- Le code SMS de l'équipe ----------
     Quand l'enseigne l'exige, le mot de passe ne suffit plus : la base ne
     reconnaît aucun droit à la session tant que le code reçu par SMS n'a
     pas été rendu. Ces quatre appels sont tout ce que l'écran en sait —
     le code lui-même ne passe jamais par ici, il ne circule que par SMS. */

  /** Faut-il un code, et vers quel numéro ? Null sur une base d'avant le
      code SMS : rien n'y est exigé, l'application s'ouvre comme avant. */
  async function etatConnexion() {
    try {
      return await rpcLecture("etat_connexion", {});
    } catch (err) {
      if (err && err.deconnecte) throw err;
      if (/Could not find|does not exist|mise à jour de la base/i.test(err.message || "")) return null;
      throw err;
    }
  }

  /** Fait partir un code au numéro de la fiche. La fonction Edge répond
      même quand elle refuse, avec la raison : on la rend telle quelle. */
  const demanderCodeConnexion = () => fonctionEdge("code-connexion", {});

  /** Rend le code. La base confirme la session, ou dit pourquoi non. */
  const confirmerCodeConnexion = (code) =>
    rpcLecture("confirmer_code_connexion", { code: String(code || "") });

  /** L'interrupteur : au superadministrateur seul, et la base le vérifie. */
  const reglerSmsEquipe = (exige) => rpcLecture("regler_sms_equipe", { exige: !!exige });

  /* ---------- L'appareil de confiance (3.59.0) ----------
     Le superadministrateur qui coche « Faire confiance à cet appareil »
     n'y rend plus son code pendant un mois. L'appareil garde un jeton
     tiré au hasard ; la base n'en garde que l'empreinte. Le mot de passe
     reste demandé : la confiance ne remplace que le SMS. */
  const CLE_APPAREIL = "bizzoo-appareil-confiance";
  function lireJetonAppareil() {
    try { return localStorage.getItem(CLE_APPAREIL) || ""; } catch (_) { return ""; }
  }
  function jetonAppareil() {
    let j = lireJetonAppareil();
    if (j.length >= 32) return j;
    const octets = new Uint8Array(32);
    crypto.getRandomValues(octets);
    j = Array.from(octets, (o) => o.toString(16).padStart(2, "0")).join("");
    try { localStorage.setItem(CLE_APPAREIL, j); } catch (_) { /* navigation privée */ }
    return j;
  }
  /** Cet appareil est-il de confiance ? Vrai : la session est confirmée,
      sans SMS. Une base d'avant, ou pas de jeton : faux. */
  async function reconnaitreAppareil() {
    const j = lireJetonAppareil();
    if (j.length < 32) return false;
    try { return (await rpcLecture("reconnaitre_appareil", { jeton: j })) === true; } catch (_) { return false; }
  }
  /** Après le code : cet appareil devient de confiance pour un mois. */
  const confierAppareil = () => rpcLecture("confier_appareil", {
    jeton: jetonAppareil(), appareil: String(navigator.userAgent || "").slice(0, 120) });
  const oublierAppareils = () => rpcLecture("oublier_appareils", {});
  async function mesAppareilsConfiance() {
    try { return Number(await rpcLecture("mes_appareils_confiance", {})) || 0; } catch (_) { return 0; }
  }

  /* ---------- Test ---------- */

  async function testerConnexion() {
    await requete("GET", "boutique?select=id&limit=1");
    return true;
  }

  return {
    configuration, estConfigure, majConfiguration, configurationSaisie,
    connexion, deconnexion, assurerSession, sessionPresente, utilisateur, identifiant,
    chargerProfil, compte, role, estSuper, estAdmin, peutModifierProduits, boutiqueDuCompte,
    estCompteEnseigne, estAdminBizzoo, droitEnseigne, peutFaireLivrer, peutVoirCommandes, peutVoirFinances,
    tientLaCaisse,
    peutChangerDeBoutique, compteActif, rolesActifs,
    creerCompte, creerCompteTelephone, changerMotDePasse,
    connexionTelephone, renvoyerCodeTelephone, confirmerCodeTelephone, estNumero, telAffichage, rpc, rpcLecture, fonctionEdge,
    etatConnexion, demanderCodeConnexion, confirmerCodeConnexion, reglerSmsEquipe,
    reconnaitreAppareil, confierAppareil, oublierAppareils, mesAppareilsConfiance,
    requete, urlImage, televerserImage, televerserVideo, supprimerImages, testerConnexion,
  };
})();
