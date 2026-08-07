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

  async function appelAuth(chemin, corps, avecSession) {
    const c = configuration();
    if (!c) throw new Error("L'application n'est pas encore reliée à la base (voir réglages).");
    let reponse;
    try {
      reponse = await fetch(c.url + "/auth/v1/" + chemin, {
        method: "POST",
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
  }

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

    if (methode === "GET" || o.anonyme) {
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
        throw new Error("Écriture refusée par la base : connectez-vous avec le compte du gérant.");
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

  async function televerserImage(chemin, dataUrl) {
    const c = configuration();
    if (!c) throw new Error("L'application n'est pas encore reliée à la base (voir réglages).");
    const s = await assurerSession();
    if (!s) {
      const err = new Error("Session expirée : reconnectez-vous.");
      err.deconnecte = true;
      throw err;
    }
    let reponse;
    try {
      reponse = await fetch(c.url + "/storage/v1/object/" + BUCKET + "/" + chemin, {
        method: "POST",
        headers: {
          "apikey": c.cle,
          "Authorization": "Bearer " + s.access_token,
          "Content-Type": "image/jpeg",
          "x-upsert": "true",
        },
        body: blobDepuisDataUrl(dataUrl),
      });
    } catch (_) {
      throw new Error("Envoi de la photo impossible. Vérifiez votre connexion internet.");
    }
    if (!reponse.ok) {
      const d = await reponse.json().catch(() => ({}));
      throw new Error(d.message || "Envoi de la photo refusé (" + reponse.status + ").");
    }
    return chemin;
  }

  /** Suppression silencieuse : une photo orpheline ne bloque jamais. */
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

  /* ---------- Test ---------- */

  async function testerConnexion() {
    await requete("GET", "boutique?select=id&limit=1");
    return true;
  }

  return {
    configuration, estConfigure, majConfiguration, configurationSaisie,
    connexion, deconnexion, assurerSession, sessionPresente, utilisateur,
    requete, urlImage, televerserImage, supprimerImages, testerConnexion,
  };
})();
