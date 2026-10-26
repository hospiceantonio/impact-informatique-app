/* =========================================================
   Supabase — la base en ligne de BIZZOO, pour le personnel.

   Même base que la place de marché et BIZZOO Admin, mêmes
   appels REST que « admin/js/supabase.js », sans bibliothèque :
   - compte : le numéro de téléphone et un code reçu par SMS (chaque
     employé), ou l'e-mail et le mot de passe (l'administration) ;
   - données : tables « rh_… », sous les règles de la base ;
   - décisions : fonctions « rh_… » (rpc), qui vérifient
     elles-mêmes qui appelle ;
   - messagerie : la fonction Edge « rh-messagerie » ;
   - pièces jointes des discussions : le seau PRIVÉ « rh-pieces »,
     lu par des liens signés que la base n'accorde qu'à qui voit
     le message.

   L'écran ne décide d'aucun droit : il cache ce qui ne sert
   pas, la base refuse ce qui n'est pas permis.
   ========================================================= */
const Supabase = (() => {

  const CLE_SESSION = "bizzoo-personnel-session";

  function configuration() {
    if (typeof CONFIG === "undefined") return null;
    const url = String(CONFIG.SUPABASE_URL || "").trim().replace(/\/+$/, "");
    const cle = String(CONFIG.SUPABASE_ANON_KEY || "").trim();
    /* « http://localhost » : le seul cas sans TLS, celui des bancs d'essai. */
    if (!/^(https:\/\/|http:\/\/localhost[:/])/.test(url + "/") || !cle) return null;
    return { url, cle };
  }

  function config() {
    const c = configuration();
    if (!c) throw new Error("L'application n'est pas reliée à la base (config.js).");
    return c;
  }

  /* ---------- Session ---------- */

  /* LA CONFIANCE DANS L'APPAREIL. Entré par son numéro, l'employé
     redonne un code à chaque connexion : sa session ne vit que le temps
     de l'onglet (sessionStorage). S'il fait confiance à cet appareil,
     elle se garde 7 jours (localStorage), puis un nouveau code est
     demandé. L'entrée par e-mail et mot de passe se garde comme avant. */
  const CONFIANCE = 7 * 24 * 3600 * 1000;
  let session = null;
  try {
    session = JSON.parse(sessionStorage.getItem(CLE_SESSION) || localStorage.getItem(CLE_SESSION) || "null");
  } catch (_) { session = null; }
  if (session && session.confiance_jusqu && Date.now() > session.confiance_jusqu) {
    session = null;
    try { localStorage.removeItem(CLE_SESSION); } catch (_) { /* vide */ }
  }

  function garderSession(s) {
    session = s;
    try {
      localStorage.removeItem(CLE_SESSION);
      sessionStorage.removeItem(CLE_SESSION);
      if (s) (s.telephone && !s.confiance_jusqu ? sessionStorage : localStorage).setItem(CLE_SESSION, JSON.stringify(s));
    } catch (_) { /* stockage indisponible : la session vit le temps de l'onglet */ }
  }

  const sessionPresente = () => !!session;
  const utilisateur = () => (session ? session.email || (session.telephone ? "+" + session.telephone : null) : null);
  const parTelephone = () => !!(session && session.telephone);

  /** « XX XX XX XX », « 01XXXXXXXX », « +229 01 XX XX XX XX » : le même
      numéro, au format international de Supabase (229 + 01 + 8 chiffres). */
  function numeroInternational(tel) {
    let n = String(tel || "").replace(/[^0-9]/g, "");
    if (n.startsWith("229") && n.length >= 11) n = n.slice(3);
    if (n.length === 8) n = "01" + n;
    if (!/^01[0-9]{8}$/.test(n)) throw new Error("Numéro incomplet : 01 suivi de 8 chiffres (01 XX XX XX XX).");
    return "229" + n;
  }

  /** Porte 1 : le code par SMS — seulement pour un numéro d'employé en poste. */
  async function demanderCode(tel) {
    const numero = numeroInternational(tel);
    const c = config();
    let connu = false;
    try {
      const r = await fetch(c.url + "/rest/v1/rpc/rh_telephone_employe", {
        method: "POST", headers: { "apikey": c.cle, "Content-Type": "application/json" },
        body: JSON.stringify({ tel: numero }),
      });
      connu = (await r.json()) === true;
    } catch (_) {
      throw new Error("Impossible de joindre la base. Vérifiez votre connexion internet.");
    }
    if (!connu) throw new Error("Ce numéro n'est celui d'aucun employé de BIZZOO. Vérifiez-le, ou demandez à l'administration.");
    /* « compte: personnel » : un compte qui naît ici n'est ni un client ni
       un compte de boutique. */
    await appelAuth("otp", { phone: numero, create_user: true, data: { compte: "personnel" } });
    return numero;
  }

  /** Porte 2 : le code reçu, et la confiance dans cet appareil (7 jours). */
  async function confirmerCode(tel, code, confiance) {
    const numero = numeroInternational(tel);
    const d = await appelAuth("verify", { type: "sms", phone: numero, token: String(code || "").trim() });
    if (!d.access_token) throw new Error("Code incorrect ou expiré.");
    garderSession({ ...sessionDepuis(d, ""), telephone: numero, confiance_jusqu: confiance ? Date.now() + CONFIANCE : null });
    return numero;
  }

  async function appelAuth(chemin, corps, avecSession, methode) {
    const c = config();
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
    const d = await reponse.json().catch(() => ({}));
    if (!reponse.ok) {
      const code = d.error_code || d.error || "";
      if (code === "invalid_credentials" || code === "invalid_grant" ||
          /invalid login credentials/i.test(d.msg || d.error_description || "")) {
        throw new Error("E-mail ou mot de passe incorrect.");
      }
      if (code === "email_not_confirmed") {
        throw new Error("Adresse pas encore confirmée : ouvrez le lien reçu dans votre boîte mail professionnelle.");
      }
      if (code === "weak_password") throw new Error("Mot de passe trop faible : 8 caractères au moins.");
      if (code === "otp_expired" || /token has expired|invalid.*otp/i.test(d.msg || "")) throw new Error("Code incorrect ou expiré.");
      if (code === "over_sms_send_rate_limit" || reponse.status === 429) throw new Error("Trop de codes demandés : attendez une minute avant de réessayer.");
      if (code === "sms_send_failed") throw new Error("Le SMS n'a pas pu partir. Réessayez dans un instant.");
      throw new Error(d.msg || d.error_description || d.message || "La connexion a échoué (" + reponse.status + ").");
    }
    return d;
  }

  function sessionDepuis(d, email) {
    return {
      access_token: d.access_token,
      refresh_token: d.refresh_token,
      expire_a: d.expires_at ? d.expires_at * 1000 : Date.now() + (d.expires_in || 3600) * 1000,
      email: (d.user && d.user.email) || email,
    };
  }

  async function connexion(email, motDePasse) {
    const d = await appelAuth("token?grant_type=password", { email: email.trim().toLowerCase(), password: motDePasse });
    garderSession(sessionDepuis(d, email));
    return utilisateur();
  }

  async function deconnexion() {
    try { await appelAuth("logout", {}, true); } catch (_) { /* déjà expirée */ }
    garderSession(null);
  }

  async function assurerSession() {
    if (!session) return null;
    if (session.expire_a - Date.now() > 60000) return session;
    try {
      const d = await appelAuth("token?grant_type=refresh_token", { refresh_token: session.refresh_token });
      /* La confiance et le numéro suivent la session renouvelée. */
      garderSession({ ...session, ...sessionDepuis(d, session.email), refresh_token: d.refresh_token || session.refresh_token });
      return session;
    } catch (err) {
      if (/connexion internet/.test(err.message || "")) return session;
      garderSession(null);
      return null;
    }
  }

  async function changerMotDePasse(nouveau) {
    await assurerSession();
    await appelAuth("user", { password: nouveau }, true, "PUT");
  }

  /**
   * Crée le compte de connexion d'un employé. L'inscription publique,
   * avec la clé publiable : la clé « service_role » ne quitte jamais le
   * serveur. « compte: personnel » dit à la base que ce n'est ni un
   * client ni un compte de boutique. La session éventuellement renvoyée
   * pour le nouveau venu est jetée : l'administrateur reste connecté.
   */
  async function creerCompte(email, motDePasse) {
    const d = await appelAuth("signup", { email: email.trim().toLowerCase(), password: motDePasse,
                                          data: { compte: "personnel" } });
    const u = d.user || d;
    if (!u || !u.id) throw new Error("Le compte n'a pas pu être créé.");
    const existait = Array.isArray(u.identities) && u.identities.length === 0;
    return { id: u.id, existait, confirmationRequise: !d.access_token && !u.email_confirmed_at };
  }

  /* ---------- Base (REST) ---------- */

  async function requete(methode, chemin, corps, options) {
    const c = config();
    const o = options || {};
    const s = await assurerSession();
    if (!s) {
      const err = new Error("Session expirée : reconnectez-vous.");
      err.deconnecte = true;
      throw err;
    }
    const entetes = { "apikey": c.cle, "Authorization": "Bearer " + s.access_token };
    if (corps !== undefined) entetes["Content-Type"] = "application/json";
    if (methode === "POST" || methode === "PATCH") {
      entetes["Prefer"] = o.sansRetour ? "return=minimal" : "return=representation";
    }
    if (o.compter) entetes["Prefer"] = "count=exact";
    let reponse;
    try {
      reponse = await fetch(c.url + "/rest/v1/" + chemin, {
        method: methode, headers: entetes,
        body: corps !== undefined ? JSON.stringify(corps) : undefined,
      });
    } catch (_) {
      throw new Error("Impossible de joindre la base. Vérifiez votre connexion internet.");
    }
    if (reponse.status === 204) return null;
    const d = await reponse.json().catch(() => null);
    if (!reponse.ok) {
      const message = (d && (d.message || d.hint)) || "";
      if (reponse.status === 401 || /JWT expired/i.test(message)) {
        const err = new Error("Session expirée : reconnectez-vous.");
        err.deconnecte = true;
        throw err;
      }
      if (/Could not find the (table|function)|does not exist/i.test(message)) {
        throw new Error("La base n'a pas encore la partie « personnel » : exécutez supabase/personnel.sql dans Supabase.");
      }
      if (/row-level security|permission denied/i.test(message)) {
        throw new Error("La base refuse : votre compte n'a pas ce droit.");
      }
      if (/duplicate key/i.test(message)) {
        if (/email_pro/.test(message)) throw new Error("Cette adresse professionnelle est déjà celle d'un autre employé.");
        if (/rh_profils_nom/.test(message)) throw new Error("Un profil porte déjà ce nom.");
        throw new Error("Cet élément existe déjà.");
      }
      if (/violates foreign key/i.test(message)) {
        throw new Error("Impossible : cet élément est encore utilisé ailleurs.");
      }
      /* Les refus écrits par la base sont faits pour être lus tels quels. */
      const code = (message.match(/^([A-Z_]+) : /) || [])[1];
      const err = new Error(message.replace(/^[A-Z_]+ : /, "") || "La base a répondu « " + reponse.status + " ».");
      if (code) err.code = code;
      throw err;
    }
    return d;
  }

  const lire = (chemin) => requete("GET", chemin);
  const ajouter = (table, ligne) => requete("POST", table, ligne).then((l) => (l || [])[0]);
  const modifier = (table, filtre, valeurs) => requete("PATCH", table + "?" + filtre, valeurs).then((l) => (l || [])[0]);
  const supprimer = (table, filtre) => requete("DELETE", table + "?" + filtre);
  const rpc = (nom, parametres) => requete("POST", "rpc/" + nom, parametres || {});

  /* ---------- La fonction de messagerie ---------- */

  async function messagerie(action, corps) {
    const c = config();
    const s = await assurerSession();
    if (!s) {
      const err = new Error("Session expirée : reconnectez-vous.");
      err.deconnecte = true;
      throw err;
    }
    let reponse;
    try {
      reponse = await fetch(c.url + "/functions/v1/rh-messagerie", {
        method: "POST",
        headers: { "apikey": c.cle, "Authorization": "Bearer " + s.access_token, "Content-Type": "application/json" },
        body: JSON.stringify({ action, ...(corps || {}) }),
      });
    } catch (_) {
      throw new Error("Serveur de messagerie injoignable. Vérifiez votre connexion internet.");
    }
    const d = await reponse.json().catch(() => null);
    if (!d) throw new Error("La messagerie n'a pas répondu (" + reponse.status + "). Est-elle déployée ?");
    if (!d.ok) {
      const err = new Error(d.message || "La messagerie a refusé.");
      err.code = d.code;
      throw err;
    }
    return d;
  }

  /* ---------- Le code SMS du superadministrateur ----------
     Quand l'enseigne l'exige, un compte superadministrateur n'a ses droits
     que si sa session a rendu un code reçu par SMS : la même porte que
     BIZZOO Admin (etat_connexion, code-connexion, confirmer_code_connexion),
     et le même appareil de confiance (un mois), partagé avec Admin. */

  async function etatConnexion() {
    try {
      return await rpc("etat_connexion", {});
    } catch (err) {
      if (err && err.deconnecte) throw err;
      return null;   // base d'avant : rien n'est exigé
    }
  }

  async function demanderCodeEquipe() {
    const c = config();
    const s = await assurerSession();
    if (!s) throw new Error("Session expirée : reconnectez-vous.");
    let r;
    try {
      r = await fetch(c.url + "/functions/v1/code-connexion", {
        method: "POST",
        headers: { "apikey": c.cle, "Authorization": "Bearer " + s.access_token, "Content-Type": "application/json" },
        body: "{}",
      });
    } catch (_) {
      throw new Error("Serveur injoignable. Vérifiez votre connexion internet.");
    }
    const d = await r.json().catch(() => null);
    if (!d) throw new Error("L'envoi du code n'a pas répondu (" + r.status + ").");
    return d;
  }

  const confirmerCodeEquipe = (code) => rpc("confirmer_code_connexion", { code: String(code || "") });

  const CLE_APPAREIL = "bizzoo-appareil-confiance";
  const lireJetonAppareil = () => { try { return localStorage.getItem(CLE_APPAREIL) || ""; } catch (_) { return ""; } };
  async function reconnaitreAppareil() {
    const j = lireJetonAppareil();
    if (j.length < 32) return false;
    try { return (await rpc("reconnaitre_appareil", { jeton: j })) === true; } catch (_) { return false; }
  }
  function confierAppareil() {
    let j = lireJetonAppareil();
    if (j.length < 32) {
      const octets = new Uint8Array(32);
      crypto.getRandomValues(octets);
      j = Array.from(octets, (o) => o.toString(16).padStart(2, "0")).join("");
      try { localStorage.setItem(CLE_APPAREIL, j); } catch (_) { /* navigation privée */ }
    }
    return rpc("confier_appareil", { jeton: j, appareil: String(navigator.userAgent || "").slice(0, 120) });
  }

  /* ---------- Les pièces jointes (seau privé « rh-pieces ») ---------- */

  const SEAU = "rh-pieces";

  async function entetesStockage() {
    const c = config();
    const s = await assurerSession();
    if (!s) {
      const err = new Error("Session expirée : reconnectez-vous.");
      err.deconnecte = true;
      throw err;
    }
    return { c, entetes: { "apikey": c.cle, "Authorization": "Bearer " + s.access_token } };
  }

  /** Dépose un fichier dans le dossier de l'employé ; le chemin revient. */
  async function deposer(chemin, fichier, type) {
    const { c, entetes } = await entetesStockage();
    let reponse;
    try {
      reponse = await fetch(c.url + "/storage/v1/object/" + SEAU + "/" + chemin, {
        method: "POST", headers: { ...entetes, "Content-Type": type || "application/octet-stream" }, body: fichier,
      });
    } catch (_) {
      throw new Error("Envoi du fichier impossible. Vérifiez votre connexion internet.");
    }
    if (!reponse.ok) {
      const d = await reponse.json().catch(() => ({}));
      const m = String(d.message || d.error || "");
      if (reponse.status === 413 || /too large|maximum allowed size/i.test(m)) throw new Error("Fichier trop lourd : 50 Mo au plus.");
      if (/mime type/i.test(m)) throw new Error("Ce type de fichier ne s'envoie pas : photos, vidéos et audio seulement.");
      if (/bucket not found/i.test(m)) throw new Error("La base n'a pas encore les pièces jointes : exécutez supabase/personnel-pieces.sql.");
      if (reponse.status === 403 || /row-level security|unauthorized/i.test(m)) throw new Error("La base refuse : votre compte n'envoie pas de fichier ici.");
      throw new Error("Envoi du fichier refusé (" + reponse.status + ")" + (m ? " — " + m : "") + ".");
    }
    return chemin;
  }

  /** Des liens de lecture, valables « secondes » ; seuls ceux que la base accorde. */
  async function signer(chemins, secondes) {
    if (!chemins.length) return {};
    const { c, entetes } = await entetesStockage();
    const reponse = await fetch(c.url + "/storage/v1/object/sign/" + SEAU, {
      method: "POST", headers: { ...entetes, "Content-Type": "application/json" },
      body: JSON.stringify({ expiresIn: secondes || 3600, paths: chemins }),
    });
    const d = await reponse.json().catch(() => []);
    const liens = {};
    for (const x of Array.isArray(d) ? d : []) {
      if (x && x.signedURL && !x.error) liens[x.path] = c.url + "/storage/v1" + x.signedURL;
    }
    return liens;
  }

  /** Retire un fichier qu'aucun message ne cite (envoi raté) ; en silence. */
  async function retirer(chemin) {
    try {
      const { c, entetes } = await entetesStockage();
      await fetch(c.url + "/storage/v1/object/" + SEAU, {
        method: "DELETE", headers: { ...entetes, "Content-Type": "application/json" },
        body: JSON.stringify({ prefixes: [chemin] }),
      });
    } catch (_) { /* le ménage de l'heure le fera */ }
  }

  return {
    configuration, sessionPresente, utilisateur, parTelephone, connexion, deconnexion, assurerSession,
    demanderCode, confirmerCode,
    changerMotDePasse, creerCompte, requete, lire, ajouter, modifier, supprimer, rpc, messagerie,
    deposer, signer, retirer,
    etatConnexion, demanderCodeEquipe, confirmerCodeEquipe, reconnaitreAppareil, confierAppareil,
  };
})();
