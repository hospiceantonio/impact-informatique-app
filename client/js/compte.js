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
      if (code === "over_email_send_rate_limit"
          || code === "over_sms_send_rate_limit" || reponse.status === 429) {
        throw new Error("Trop de tentatives. Patientez une minute.");
      }
      /* Les refus propres au SMS. Le premier est le plus important : un
         code expiré ou mal tapé ne doit pas se lire « identifiants
         invalides », sinon le client va chercher son mot de passe. */
      if (code === "otp_expired" || /token has expired|otp/i.test(texte)) {
        throw new Error("Code incorrect ou expiré. Demandez-en un nouveau.");
      }
      if (code === "sms_send_failed" || /sms/i.test(code)) {
        /* Le message vient de notre propre fonction de livraison : elle
           sait dire « crédit épuisé » ou « numéro refusé ». Le rendre tel
           quel vaut mieux que de le remplacer par une généralité. */
        throw new Error(texte || "L'envoi du SMS a échoué. Réessayez dans un instant.");
      }
      if (code === "phone_exists" || /phone.*already/i.test(texte)) {
        throw new Error("Ce numéro est déjà utilisé par un autre compte.");
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
      /* Un compte créé par SMS n'a PAS d'adresse e-mail — et Supabase y
         met une chaîne VIDE, pas « null ». Sans le numéro gardé ici, la
         page « Mon compte » d'un tel client afficherait un identifiant
         vide, et l'on chercherait du côté des droits de lecture. */
      tel: (d.user && d.user.phone) || "",
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

  /* ---------- Le numéro, dans les trois formes qu'il prend ----------

     Il en a trois, et les confondre coûte cher :

       « 0197121596 »     — ce que le client tape, et ce que BIZZOO range
                            dans « clients.tel » et « commandes.client_tel ».
       « +2290197121596 » — ce que GoTrue EXIGE en entrée. Sans le « + »,
                            il refuse.
       « 2290197121596 »  — ce que GoTrue RANGE, sans le « + ». Relire
                            « user.phone » et le renvoyer tel quel à la
                            vérification échoue, toujours.

     D'où la normalisation systématique à l'entrée : on ne fait jamais
     confiance à la forme qu'on vient de lire. */

  const INDICATIF = "229";

  function telInternational(brut, indicatif) {
    const ind = indicatif || INDICATIF;
    let chiffres = String(brut || "").replace(/\D/g, "");
    if (!chiffres) return "";
    if (chiffres.startsWith("00")) chiffres = chiffres.slice(2);
    if (!chiffres.startsWith(ind)) chiffres = ind + chiffres;
    return "+" + chiffres;
  }

  /** La partie nationale : la forme que BIZZOO range. */
  function telNational(brut, indicatif) {
    const ind = indicatif || INDICATIF;
    let chiffres = String(brut || "").replace(/\D/g, "");
    if (chiffres.startsWith("00")) chiffres = chiffres.slice(2);
    if (chiffres.startsWith(ind) && chiffres.length > ind.length) {
      chiffres = chiffres.slice(ind.length);
    }
    return chiffres;
  }

  /** « +229 01 97 12 15 96 » : un numéro se dicte par groupes de deux. */
  function telAffichage(brut, indicatif) {
    const national = telNational(brut, indicatif);
    if (!national) return "";
    return "+" + (indicatif || INDICATIF) + " " +
      (national.match(/.{1,2}/g) || []).join(" ");
  }

  /**
   * Ce qu'on écrit en haut de « Mon compte ».
   *
   * LE PIÈGE : sur un compte créé par SMS, Supabase met une chaîne VIDE
   * dans « email », pas « null ». Un « email || tel » fonctionne, mais un
   * « email ?? tel » — le réflexe — donnerait la chaîne vide, et l'écran
   * n'afficherait aucun identifiant. Le compte marcherait, les commandes
   * s'afficheraient, et l'on chercherait du côté des droits de lecture.
   */
  function identite() {
    if (!session) return "";
    const adresse = session.email || "";
    if (adresse) return adresse;
    return telAffichage(session.tel || (fiche && fiche.tel) || "");
  }

  /* ---------- Entrer, sortir ---------- */

  async function inscrire(email, motDePasse, nom, type, message) {
    /* « compte: client » part dans les métadonnées du compte. C'est ce que
       la base lit pour NE PAS fabriquer une fiche d'équipe en attente.
       « type » et « revendeur » les rejoignent : ils portent le choix du
       formulaire jusqu'à la première connexion, confirmation par e-mail
       comprise. Une demande, rien de plus — c'est BIZZOO qui valide. */
    const d = await appelAuth("signup", {
      email: String(email || "").trim(),
      password: motDePasse,
      data: {
        compte: "client",
        nom: String(nom || "").trim(),
        type: type === "revendeur" ? "revendeur" : "client",
        revendeur: type === "revendeur" ? String(message || "").trim().slice(0, 300) : "",
      },
    });

    /* Confirmation par e-mail activée : pas de session, rien à écrire
       encore. Le client confirmera, puis se connectera — et c'est là que
       sa fiche sera posée. */
    if (!depuisReponse(d, email)) return { confirmation: true };

    await assurerFiche(nom);
    return { confirmation: false, revendeur: estRevendeurEnAttente() };
  }

  async function connecter(email, motDePasse) {
    const d = await appelAuth("token?grant_type=password", {
      email: String(email || "").trim(), password: motDePasse,
    });
    depuisReponse(d, email);
    await assurerFiche("");
    await chargerPrix();
    return courriel();
  }

  async function deconnecter() {
    try { await appelAuth("logout", {}, true); } catch (_) { /* déjà expirée */ }
    garder(null);
    /* Le catalogue redevient celui de tout le monde, séance tenante :
       les prix revendeur ne restent pas à l'écran une fois sorti. */
    if (typeof Catalogue !== "undefined") Catalogue.definirPrixCompte(null);
  }

  /** Renvoyer le courriel de réinitialisation. */
  async function motDePasseOublie(email) {
    await appelAuth("recover", { email: String(email || "").trim() });
  }

  /* ---------- Entrer, ou se vérifier, par SMS ----------

     NOUS N'ÉCRIVONS AUCUN CODE. Ni table, ni hachage, ni expiration, ni
     compteur de tentatives : Supabase Auth sait déjà tout cela, et le
     fait dans un schéma que cette application ne peut pas toucher. Notre
     part se limite à LIVRER le SMS, et c'est une fonction du serveur qui
     s'en charge — jamais celle-ci.

     Deux portes, un seul mécanisme :

       — sans compte, le numéro EST l'identifiant. Le premier code
         validé crée le compte ;
       — avec un compte e-mail, le numéro se CONFIRME. Le code validé
         pose « phone_confirmed_at », et la base en tire « tel_verifie ».

     Dans les deux cas, c'est GoTrue qui écrit la vérité. L'application
     ne fait que demander. */

  /** Porte 1 — demander un code pour entrer par son numéro. */
  async function demanderCodeConnexion(tel, nom) {
    const numero = telInternational(tel);
    if (numero.length < 9) throw new Error("Numéro incomplet.");
    await appelAuth("otp", {
      phone: numero,
      create_user: true,
      /* « compte: client » suit la même règle que l'inscription par
         e-mail : sans lui, la base fabriquerait pour ce compte une fiche
         d'équipe en attente, et l'acheteur se retrouverait dans la liste
         des comptes de l'enseigne. */
      data: { compte: "client", nom: String(nom || "").trim() },
    });
    return numero;
  }

  /** Porte 1 — valider le code, et entrer. */
  async function confirmerCodeConnexion(tel, code) {
    const numero = telInternational(tel);
    const d = await appelAuth("verify", {
      type: "sms", phone: numero, token: String(code || "").trim(),
    });
    if (!depuisReponse(d, "")) throw new Error("Code incorrect ou expiré.");
    await assurerFiche("");
    await chargerPrix();
    return session;
  }

  /** Porte 2 — demander un code pour vérifier son numéro, déjà connecté. */
  async function demanderCodeNumero(tel) {
    const numero = telInternational(tel);
    if (numero.length < 9) throw new Error("Numéro incomplet.");
    /* « PUT /user » enregistre le numéro en attente et fait partir le
       code. Le numéro n'est PAS encore celui du compte : il ne le
       devient qu'au code validé. */
    await appelAuth("user", { phone: numero }, true, "PUT");
    return numero;
  }

  /**
   * Porte 2 — valider le code.
   *
   * Le drapeau « tel_verifie » n'est jamais envoyé d'ici : c'est un
   * déclencheur de la base qui le pose, en lisant ce que GoTrue vient
   * d'écrire. Le renvoi de la fiche dit donc la vérité — y compris
   * lorsqu'elle est décevante : si le numéro est déjà vérifié sur un
   * autre compte, la base refuse de le transférer, et « tel_verifie »
   * reste faux.
   */
  async function confirmerCodeNumero(tel, code) {
    const numero = telInternational(tel);
    const d = await appelAuth("verify", {
      type: "phone_change", phone: numero, token: String(code || "").trim(),
    });
    /* La vérification rend une nouvelle session : on la garde, sinon le
       jeton en main ignorerait le numéro tout juste confirmé. */
    if (d && d.access_token) depuisReponse(d, session ? session.email : "");
    const a_jour = await charger(true);
    if (a_jour && !a_jour.tel_verifie) {
      throw new Error(
        "Ce numéro est déjà vérifié sur un autre compte BIZZOO. " +
        "Utilisez ce compte-là, ou un autre numéro.");
    }
    return a_jour;
  }

  /** Retrouver les commandes passées avec ce numéro, avant le compte. */
  async function rattacherMesCommandes() {
    const combien = await rest("POST", "rpc/rattacher_mes_commandes", {});
    return Number(combien) || 0;
  }

  /* ---------- L'historique, celui qui suit le client ----------

     Jusqu'ici « Mes commandes » lisait le téléphone. Changez d'appareil,
     perdez-le, videz son stockage — et l'historique disparaissait. C'est
     précisément ce que le compte devait résoudre.

     Ce que la base rend ici, c'est ce que les RÈGLES de la base laissent
     lire : « commandes lecture client » ne montre qu'une commande dont
     « client_id » est le compte connecté. Il n'y a donc rien à filtrer
     de ce côté-ci, et rien à vérifier : demander les commandes d'un
     autre ne rend aucune ligne.

     Les commandes rentrent dans la forme que les écrans attendent déjà —
     celle que « creer_commande » rend au moment de commander. Un reçu
     lu depuis la base et un reçu gardé sur le téléphone s'affichent donc
     par le même code. */

  /** Le nom d'une boutique, tel que le catalogue le connaît. */
  function boutiqueDe(id) {
    if (typeof Catalogue === "undefined") return null;
    return (Catalogue.boutiques() || []).find((b) => b.id === id) || null;
  }

  /**
   * Une ligne de « commandes » remise dans la forme des écrans.
   *
   * Les lignes sont regroupées par boutique, comme au moment de
   * commander : une commande peut traverser plusieurs boutiques de
   * l'enseigne, et le client veut savoir qui prépare quoi.
   */
  function commandeDepuisBase(l) {
    const parBoutique = new Map();
    for (const x of (l.commande_lignes || [])) {
      const cle = x.boutique_id || "";
      if (!parBoutique.has(cle)) {
        const b = boutiqueDe(cle);
        parBoutique.set(cle, {
          id: cle,
          nom: (b && b.nom) || "Boutique",
          whatsapp: (b && b.whatsapp) || "",
          indicatif: (b && b.indicatif) || "229",
          montant: 0,
          lignes: [],
        });
      }
      const groupe = parBoutique.get(cle);
      const prix = Number(x.prix) || 0;
      const quantite = Number(x.quantite) || 1;
      groupe.montant += prix * quantite;
      groupe.lignes.push({
        nom: x.nom || "", code: x.code || "", reference: x.reference || "",
        prix, quantite,
      });
    }

    return {
      id: l.id,
      numero: l.numero || "",
      total: Number(l.total) || 0,
      devise: l.devise || "FCFA",
      etat: l.etat || "a_payer",
      remarque: l.remarque || "",
      client: {
        nom: l.client_nom || "", tel: l.client_tel || "",
        indicatif: l.client_indicatif || "229",
        adresse: l.client_adresse || "", note: l.note || "",
      },
      boutiques: [...parBoutique.values()].sort((a, b) => b.montant - a.montant),
      /* La date de la BASE, pas celle du téléphone : c'est la même pour
         tous les appareils du client, et c'est la seule qui ait un sens
         pour une commande qu'il n'a pas passée d'ici. */
      gardeeLe: Date.parse(l.cree_le || "") || 0,
      revendeur: !!l.revendeur,
      /* Ce qui vient de la base ne se réécrit pas sur le téléphone. */
      depuisLaBase: true,
    };
  }

  const CHAMPS_COMMANDE =
    "id,numero,total,devise,etat,remarque,note,cree_le,revendeur," +
    "client_nom,client_tel,client_indicatif,client_adresse," +
    "commande_lignes(boutique_id,nom,code,reference,prix,quantite)";

  /** Les commandes de ce compte, les plus récentes d'abord. */
  async function mesCommandes(combien) {
    if (!session) return [];
    const lignes = await rest("GET",
      "commandes?select=" + CHAMPS_COMMANDE +
      "&order=cree_le.desc&limit=" + (Number(combien) || 50));
    return (lignes || []).map(commandeDepuisBase);
  }

  /** Une commande précise — pour un reçu que ce téléphone n'a pas gardé. */
  async function commande(id) {
    if (!session || !id) return null;
    const lignes = await rest("GET",
      "commandes?select=" + CHAMPS_COMMANDE +
      "&id=eq." + encodeURIComponent(id) + "&limit=1");
    return lignes && lignes.length ? commandeDepuisBase(lignes[0]) : null;
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
    /* Le choix fait au formulaire, retrouvé dans les métadonnées : c'est
       le seul endroit où il ait survécu à la confirmation par e-mail. */
    const demande = demandeDeLInscription();
    try {
      const cree = await rest("POST", "clients",
        {
          id,
          nom: String(nom || "").trim() || demande.nom,
          type_compte: demande.type,
          revendeur_message: demande.message,
        },
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

  /** Le contenu du jeton lui-même : identifiant, et métadonnées du compte. */
  function contenuDuJeton() {
    if (!session || !session.access_token) return null;
    try {
      let charge = session.access_token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
      charge += "===".slice((charge.length + 3) % 4);
      const brut = atob(charge);
      const octets = Uint8Array.from(brut, (c) => c.charCodeAt(0));
      return JSON.parse(new TextDecoder().decode(octets));
    } catch (_) {
      return null;
    }
  }

  /** L'identifiant du compte, lu dans le jeton lui-même (champ « sub »). */
  function identifiant() {
    const c = contenuDuJeton();
    return (c && c.sub) || null;
  }

  /**
   * Ce que le compte a demandé à l'inscription, retrouvé dans ses
   * métadonnées.
   *
   * Pourquoi passer par là plutôt que d'écrire la fiche tout de suite ?
   * Parce qu'avec la confirmation par e-mail, l'inscription ne rend
   * aucune session : la fiche ne se pose qu'à la première connexion,
   * des heures plus tard. Le choix « revendeur » doit survivre à ce
   * trajet, et les métadonnées du compte le portent.
   *
   * Ces métadonnées viennent du téléphone, donc ne valent RIEN de plus
   * qu'une demande — la base ne leur accorde que « en_attente ».
   */
  function demandeDeLInscription() {
    const c = contenuDuJeton() || {};
    const m = c.user_metadata || c.raw_user_meta_data || {};
    return {
      type: m.type === "revendeur" ? "revendeur" : "client",
      nom: String(m.nom || "").trim(),
      message: String(m.revendeur || "").trim(),
    };
  }

  const moi = () => fiche;

  /**
   * La fiche du compte. Avec « relire », on repasse par la base :
   * c'est ainsi qu'un revendeur apprend que BIZZOO l'a validé, sans
   * avoir à fermer et rouvrir l'application.
   */
  async function charger(relire) {
    if (!session) return null;
    if (fiche && !relire) return fiche;
    if (relire) fiche = null;
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

  /* ---------- Client ordinaire, ou revendeur ----------

     Un revendeur achète pour revendre : validé par BIZZOO, il paie le
     PRIX BIZZOO — celui que la boutique a annoncé à la création du
     produit.

     Ce module ne fait que DEMANDER. « revendeur_etat » n'est jamais
     envoyé d'ici, et la base le refuserait : il n'y a pas deux façons
     d'obtenir le statut, il y a la décision de BIZZOO. */

  const ETATS = { aucune: "", en_attente: "en_attente", validee: "validee", refusee: "refusee" };

  const etatRevendeur = () =>
    (fiche && ETATS[fiche.revendeur_etat] !== undefined ? fiche.revendeur_etat : "aucune");
  const estRevendeur = () => etatRevendeur() === "validee";
  const estRevendeurEnAttente = () => etatRevendeur() === "en_attente";
  const motifRevendeur = () => (fiche && fiche.revendeur_motif) || "";

  /** Demander à devenir revendeur. Renvoie la fiche mise à jour. */
  async function demanderRevendeur(message) {
    const id = identifiant();
    if (!id) throw new Error("Vous n'êtes pas connecté.");
    const maj = await rest("PATCH", "clients?id=eq." + encodeURIComponent(id),
      {
        type_compte: "revendeur",
        revendeur_message: String(message || "").trim().slice(0, 300),
        maj_le: new Date().toISOString(),
      },
      { "Prefer": "return=representation" });
    fiche = (maj && maj[0]) || fiche;
    await chargerPrix();
    return fiche;
  }

  /** Y renoncer, et redevenir un client ordinaire. */
  async function annulerRevendeur() {
    const id = identifiant();
    if (!id) throw new Error("Vous n'êtes pas connecté.");
    const maj = await rest("PATCH", "clients?id=eq." + encodeURIComponent(id),
      { type_compte: "client", maj_le: new Date().toISOString() },
      { "Prefer": "return=representation" });
    fiche = (maj && maj[0]) || fiche;
    await chargerPrix();
    return fiche;
  }

  /**
   * Aller chercher les prix de ce compte-ci et les poser sur le
   * catalogue.
   *
   * La base répond zéro ligne à qui n'est pas revendeur validé : c'est
   * le même appel pour tout le monde, et l'application n'a donc pas à
   * savoir d'avance qui elle sert. Hors connexion, on ne touche à
   * rien — le catalogue local reste consultable.
   */
  async function chargerPrix() {
    if (typeof Catalogue === "undefined") return false;
    if (!session) return Catalogue.definirPrixCompte(null);
    try {
      const prix = await rest("POST", "rpc/mes_prix", {});
      return Catalogue.definirPrixCompte(Array.isArray(prix) ? prix : null);
    } catch (_) {
      /* Base injoignable ou fonction pas encore installée : on garde ce
         qui est affiché. Mieux vaut un prix public qu'un écran vide. */
      return false;
    }
  }

  return {
    connecte, courriel, identite, identifiant, moi, charger,
    inscrire, connecter, deconnecter, motDePasseOublie,
    enregistrer, assurerSession, jeton, surChangement,
    etatRevendeur, estRevendeur, estRevendeurEnAttente, motifRevendeur,
    demanderRevendeur, annulerRevendeur, chargerPrix,
    telInternational, telNational, telAffichage,
    demanderCodeConnexion, confirmerCodeConnexion,
    demanderCodeNumero, confirmerCodeNumero, rattacherMesCommandes,
    mesCommandes, commande,
  };
})();
