/* =========================================================
   BIZZOO — le compte du client

   Jusqu'ici l'application cliente ne connaissait personne : on
   commandait avec un numéro, et l'historique vivait dans le
   téléphone. Changez d'appareil, et tout disparaissait.

   Ce module tient l'identité du client, et rien d'autre. Trois
   choses méritent d'être sues avant de le lire :

   1. ON S'INSCRIT EN SE DÉCLARANT CLIENT. Le « data: { compte:
      "client" } » de l'inscription n'est pas décoratif : sans lui,
      la base fabrique pour ce compte une fiche d'équipe en
      attente, et l'acheteur se retrouve dans la liste des comptes
      de l'enseigne — où un clic distrait lui donnerait les droits
      d'un modérateur.

   2. LA FICHE CLIENT SE POSE APRÈS COUP, pas pendant
      l'inscription. Si la confirmation par e-mail est activée,
      l'inscription ne rend aucune session : il n'y a alors
      personne pour écrire la fiche. On la crée donc à la
      première connexion qui aboutit, et l'opération se rejoue
      sans dommage.

   3. LE NUMÉRO VÉRIFIÉ NE S'ÉCRIT PAS D'ICI. La base refuse
      « tel_verifie » à qui n'est pas la vérification par SMS. Ce
      module ne l'envoie jamais — et s'il le faisait, il serait
      refusé.
   ========================================================= */

const Compte = (() => {
  const CLE_SESSION = "bizzoo-session";

  let session = null;
  try { session = JSON.parse(localStorage.getItem(CLE_SESSION) || "null"); } catch (_) { /* vide */ }

  let fiche = null;     // la ligne « clients », une fois lue
  const ecouteurs = [];

  function garder(s) {
    session = s;
    try {
      if (s) localStorage.setItem(CLE_SESSION, JSON.stringify(s));
      else localStorage.removeItem(CLE_SESSION);
    } catch (_) { /* navigation privée : la session vivra le temps de l'onglet */ }
    if (!s) fiche = null;
    prevenir();
  }

  /** Prévenir l'application qu'on vient d'entrer ou de sortir. */
  const surChangement = (f) => { ecouteurs.push(f); };
  const prevenir = () => ecouteurs.forEach((f) => { try { f(); } catch (_) { /* rien */ } });

  /* ---------- Dialogue avec l'authentification ---------- */

  async function appelAuth(chemin, corps, avecSession, methode) {
    const c = Catalogue.configuration();
    if (!c) throw new Error("L'application n'est pas reliée à la base.");
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
      throw new Error("Impossible de joindre BIZZOO. Vérifiez votre connexion internet.");
    }
    if (reponse.status === 204) return {};
    const d = await reponse.json().catch(() => ({}));
    if (!reponse.ok) {
      /* Les messages de GoTrue sont en anglais et parlent de « credentials ».
         Le client, lui, veut savoir quoi corriger. */
      const code = d.error_code || d.error || "";
      const texte = d.msg || d.error_description || d.message || "";
      if (code === "invalid_credentials" || code === "invalid_grant"
          || /invalid login credentials/i.test(texte)) {
        throw new Error("E-mail ou mot de passe incorrect.");
      }
      if (code === "user_already_exists" || /already registered/i.test(texte)) {
        throw new Error("Un compte existe déjà avec cet e-mail. Connectez-vous.");
      }
      if (code === "weak_password" || /password/i.test(texte) && /least|court/i.test(texte)) {
        throw new Error("Mot de passe trop court : six caractères au minimum.");
      }
      if (code === "over_email_send_rate_limit" || reponse.status === 429) {
        throw new Error("Trop de tentatives. Patientez une minute.");
      }
      throw new Error(texte || "La connexion a échoué (" + reponse.status + ").");
    }
    return d;
  }

  function depuisReponse(d, email) {
    if (!d.access_token) return null;
    garder({
      access_token: d.access_token,
      refresh_token: d.refresh_token,
      expire_a: d.expires_at ? d.expires_at * 1000 : Date.now() + (d.expires_in || 3600) * 1000,
      email: (d.user && d.user.email) || email || "",
    });
    return session;
  }

  /** Une session valable, rafraîchie si besoin — ou null. */
  async function assurerSession() {
    if (!session) return null;
    if (session.expire_a - Date.now() > 60000) return session;
    try {
      const d = await appelAuth("token?grant_type=refresh_token",
        { refresh_token: session.refresh_token });
      garder({
        access_token: d.access_token,
        refresh_token: d.refresh_token || session.refresh_token,
        expire_a: d.expires_at ? d.expires_at * 1000 : Date.now() + (d.expires_in || 3600) * 1000,
        email: session.email,
      });
      return session;
    } catch (err) {
      /* Hors ligne, on garde la session : elle vaut peut-être encore, et la
         perdre obligerait le client à se reconnecter pour rien. */
      if (/connexion internet/.test(err.message || "")) return session;
      garder(null);
      return null;
    }
  }

  /** Le jeton à joindre à un appel, ou "" si personne n'est connecté. */
  async function jeton() {
    const s = await assurerSession();
    return s ? s.access_token : "";
  }

  const connecte = () => !!session;
  const courriel = () => (session ? session.email : "");

  /* ---------- Entrer, sortir ---------- */

  async function inscrire(email, motDePasse, nom) {
    /* « compte: client » part dans les métadonnées du compte. C'est ce que
       la base lit pour NE PAS fabriquer une fiche d'équipe en attente. */
    const d = await appelAuth("signup", {
      email: String(email || "").trim(),
      password: motDePasse,
      data: { compte: "client", nom: String(nom || "").trim() },
    });

    /* Confirmation par e-mail activée : pas de session, rien à écrire
       encore. Le client confirmera, puis se connectera — et c'est là que
       sa fiche sera posée. */
    if (!depuisReponse(d, email)) return { confirmation: true };

    await assurerFiche(nom);
    return { confirmation: false };
  }

  async function connecter(email, motDePasse) {
    const d = await appelAuth("token?grant_type=password", {
      email: String(email || "").trim(), password: motDePasse,
    });
    depuisReponse(d, email);
    await assurerFiche("");
    return courriel();
  }

  async function deconnecter() {
    try { await appelAuth("logout", {}, true); } catch (_) { /* déjà expirée */ }
    garder(null);
  }

  /** Renvoyer le courriel de réinitialisation. */
  async function motDePasseOublie(email) {
    await appelAuth("recover", { email: String(email || "").trim() });
  }

  /* ---------- La fiche client ---------- */

  async function rest(methode, chemin, corps, entetesEnPlus) {
    const c = Catalogue.configuration();
    const t = await jeton();
    if (!c || !t) throw new Error("Vous n'êtes pas connecté.");
    let reponse;
    try {
      reponse = await fetch(c.url + "/rest/v1/" + chemin, {
        method: methode,
        headers: {
          "apikey": c.cle,
          "Authorization": "Bearer " + t,
          "Content-Type": "application/json",
          ...(entetesEnPlus || {}),
        },
        body: corps ? JSON.stringify(corps) : undefined,
      });
    } catch (_) {
      throw new Error("Impossible de joindre BIZZOO. Vérifiez votre connexion internet.");
    }
    const d = await reponse.json().catch(() => null);
    if (!reponse.ok) {
      throw new Error((d && (d.message || d.hint)) || "L'enregistrement a échoué.");
    }
    return d;
  }

  /**
   * Poser la fiche client si elle manque.
   *
   * Elle manque dans deux cas : la confirmation par e-mail retardait
   * l'écriture, ou le compte a été créé ailleurs. L'opération se rejoue
   * sans dommage — un conflit veut dire « déjà là », pas « raté ».
   */
  async function assurerFiche(nom) {
    const s = await assurerSession();
    if (!s) return null;
    try {
      const existe = await rest("GET", "clients?select=*&limit=1");
      if (existe && existe.length) { fiche = existe[0]; return fiche; }
    } catch (_) { /* on tentera l'écriture */ }

    const id = identifiant();
    if (!id) return null;
    try {
      const cree = await rest("POST", "clients",
        { id, nom: String(nom || "").trim() },
        { "Prefer": "return=representation,resolution=ignore-duplicates" });
      fiche = (cree && cree[0]) || null;
    } catch (_) {
      /* Déjà posée entre-temps, ou refusée : on relit plutôt que d'insister. */
      try {
        const relu = await rest("GET", "clients?select=*&limit=1");
        fiche = (relu && relu[0]) || null;
      } catch (__) { fiche = null; }
    }
    return fiche;
  }

  /** L'identifiant du compte, lu dans le jeton lui-même (champ « sub »). */
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

  const moi = () => fiche;

  async function charger() {
    if (!session) return null;
    if (fiche) return fiche;
    return await assurerFiche("");
  }

  /**
   * Enregistrer ce que le client a le droit de changer.
   *
   * « tel_verifie » n'y figure pas, et ce n'est pas un oubli : la base le
   * refuserait, et c'est très bien ainsi — ce drapeau ouvrira l'accès aux
   * commandes passées avec ce numéro.
   */
  async function enregistrer({ nom, tel, adresse }) {
    const id = identifiant();
    if (!id) throw new Error("Vous n'êtes pas connecté.");
    const champs = {
      nom: String(nom || "").trim().slice(0, 120),
      tel: String(tel || "").replace(/\D/g, "").slice(0, 20),
      adresse: String(adresse || "").trim().slice(0, 300),
      maj_le: new Date().toISOString(),
    };
    /* Un numéro déjà vérifié ne se change pas : on ne le renvoie même pas,
       sinon la base refuserait tout l'enregistrement pour cette seule
       raison — et le client ne pourrait plus corriger son adresse. */
    if (fiche && fiche.tel_verifie) delete champs.tel;

    const maj = await rest("PATCH", "clients?id=eq." + encodeURIComponent(id), champs,
      { "Prefer": "return=representation" });
    fiche = (maj && maj[0]) || fiche;
    return fiche;
  }

  return {
    connecte, courriel, identifiant, moi, charger,
    inscrire, connecter, deconnecter, motDePasseOublie,
    enregistrer, assurerSession, jeton, surChangement,
  };
})();
