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

  async function deconnexion() {
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
        /* Colonne absente d'une base pas encore mise à jour : on n'enlève rien. */
        peutModifier: l.peut_modifier_produits !== false,
      };
    }
    return profil;
  }

  const compte = () => profil;
  const rolesActifs = () => rolesEnBase;
  const role = () => (profil ? profil.role : rolesEnBase ? null : "administrateur");
  const estAdmin = () => role() === "administrateur";
  /** Retoucher un produit déjà au catalogue : l'administrateur toujours,
      le modérateur si l'administrateur le lui a accordé. */
  const peutModifierProduits = () => estAdmin() || !!(profil && profil.peutModifier);
  /** Membre actif de l'équipe : sans fiche active, aucune écriture n'est permise. */
  const compteActif = () => !rolesEnBase || !!(profil && profil.actif);

  /** Renvoie une session valide (rafraîchie si besoin), sinon null. */
  async function assurerSession() {
    if (!session) return null;
    if (session.expire_a - Date.now() > 60000) return session;
    try {
      const d = await appelAuth("token?grant_type=refresh_token", { refresh_token: session.refresh_token });
      garderSession({
        access_token: d.access_token,
        refresh_token: d.refresh_token || session.refresh_token,
        expire_a: (d.expires_at ? d.expires_at * 1000 : Date.now() + (d.expires_in || 3600) * 1000),
        email: session.email,
      });
      return session;
    } catch (err) {
      if (/connexion internet/.test(err.message || "")) return session; // hors ligne : on tentera
      garderSession(null);
      return null;
    }
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
    if (corps !== undefined) entetes["Content-Type"] = "application/json";
    if (methode === "POST" && !o.sansRetour) entetes["Prefer"] = "return=representation";
    if (methode === "PATCH") entetes["Prefer"] = "return=representation";
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

  async function creerCompte(email, motDePasse) {
    const d = await appelAuth("signup", { email, password: motDePasse });
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

  /* ---------- Test ---------- */

  async function testerConnexion() {
    await requete("GET", "boutique?select=id&limit=1");
    return true;
  }

  return {
    configuration, estConfigure, majConfiguration, configurationSaisie,
    connexion, deconnexion, assurerSession, sessionPresente, utilisateur, identifiant,
    chargerProfil, compte, role, estAdmin, peutModifierProduits, compteActif, rolesActifs,
    creerCompte, changerMotDePasse, rpc,
    requete, urlImage, televerserImage, televerserVideo, supprimerImages, testerConnexion,
  };
})();
