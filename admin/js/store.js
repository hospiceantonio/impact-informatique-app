/* =========================================================
   Store — logique métier au-dessus de la base Supabase.

   Catégorie : { id, nom, ordre, sousCategories: [{ id, nom, ordre }] }
   Produit   : { id, nom, description, prix, ancienPrix,
                 categorieId, sousCategorieId, stock, surCommande,
                 enAvant, ordreAvant, images: [chemins],
                 vignette (URL), creeLe, modifieLe }

   Tout est enregistré directement en ligne : l'application
   client des visiteurs voit les modifications immédiatement.
   ========================================================= */
const Store = (() => {

  const MAX_SLIDES = 8;     // images libres du slider de l'application client
  const MAX_EN_AVANT = 5;   // produits qui défilent à la suite des images
  const MAX_PHOTOS = 4;
  const MAX_VIDEO_MO = 40;  // au-delà, l'envoi devient trop long au téléphone

  const BOUTIQUE_DEFAUT = {
    nomBoutique: "IMPACT INFORMATIQUE",
    slogan: "Nous sommes imbattables en prix",
    description: "",
    tel: "",
    whatsapp: "69842516",
    indicatif: "229",
    devise: "FCFA",
    adresse: "",
    horaires: "",
    facebook: "",
    instagram: "",
    tiktok: "",
    youtube: "",
    snapchat: "",
    latitude: null,
    longitude: null,
    photos: [],      // chemins des photos de la boutique
    telephones: [],  // autres numéros : { libelle, numero, whatsapp }
    adresses: [],    // autres adresses : { libelle, texte, latitude, longitude }
    tauxMarge: 20,   // marge appliquée par défaut au prix grossiste
  };

  const TAUX_MAX = 1000;   // au-delà, c'est une faute de frappe

  const MAX_PHOTOS_BOUTIQUE = 6;
  const MAX_TELEPHONES = 8;    // en plus du numéro principal
  const MAX_ADRESSES = 8;      // en plus de l'adresse principale

  let reglages = { ...BOUTIQUE_DEFAUT };

  /* Faux tant que la table des prix d'achat n'existe pas : le catalogue
     fonctionne alors comme avant, prix public seul. */
  let prixAchatEnBase = true;

  /* ---------- Correspondance base <-> application ---------- */

  const versMs = (iso) => {
    const t = Date.parse(iso || "");
    return isNaN(t) ? Date.now() : t;
  };

  /**
   * Le stock d'un produit. Sur une base d'avant la gestion de stock, la
   * colonne n'existe pas : l'ancien « disponible » vaut alors 1 ou 0.
   */
  function stockDepuisLigne(l) {
    if (l.stock === null || l.stock === undefined) return l.disponible === false ? 0 : 1;
    return Math.max(0, Math.round(Number(l.stock) || 0));
  }

  /** Nombre saisi au clavier : « 12 », « 12 » ou vide. */
  const lireStock = (valeur) => Math.max(0, Math.round(Utils.lireNombre(valeur) || 0));

  /* ---------- Marge : du prix grossiste au prix public ----------
     La boutique achète à un prix grossiste, y ajoute une marge en
     pourcentage, et c'est le résultat — le prix public — que voient les
     clients. Le taux de la boutique s'applique partout, sauf sur les
     produits qui portent le leur. */

  /** Un taux saisi au clavier : « 20 », « 20,5 » ou vide (= celui de la boutique). */
  function lireTaux(valeur) {
    if (valeur === "" || valeur === null || valeur === undefined) return null;
    const n = Number(String(valeur).replace(",", ".").replace(/[^\d.-]/g, ""));
    if (!isFinite(n) || n < 0 || n > TAUX_MAX) return null;
    return Math.round(n * 100) / 100;
  }

  /** Le taux qui s'applique vraiment à un produit. */
  const tauxApplique = (taux) => (taux === null || taux === undefined ? reglages.tauxMarge : taux);

  /** Prix public = prix grossiste + marge, arrondi au franc. */
  function prixPublic(prixGrossiste, taux) {
    const achat = Math.max(0, Math.round(Number(prixGrossiste) || 0));
    if (!achat) return 0;
    return Math.round(achat * (1 + tauxApplique(taux) / 100));
  }

  /** Le chemin inverse : quel taux mène de ce prix grossiste à ce prix public ? */
  function tauxDepuisPrix(prixGrossiste, prix) {
    const achat = Math.max(0, Math.round(Number(prixGrossiste) || 0));
    const vente = Math.max(0, Math.round(Number(prix) || 0));
    if (!achat) return null;
    return Math.round(((vente - achat) / achat) * 10000) / 100;
  }

  /* Les trois états possibles d'un produit, et ce qu'en voit le client. */
  const STATUTS = {
    disponible: { nom: "Disponible", teinte: "vert" },
    rupture: { nom: "En rupture", teinte: "rouge" },
    commande: { nom: "Sur commande", teinte: "bleu" },
  };

  /**
   * « disponible » quand il reste des pièces, « rupture » quand il n'en
   * reste plus, « commande » pour un produit vendu sans stock.
   */
  function statut(p) {
    if (!p) return "rupture";
    if (p.surCommande) return "commande";
    return p.stock > 0 ? "disponible" : "rupture";
  }

  /**
   * Le prix d'achat vient d'une table à part, jamais lisible avec la clé
   * publique. PostgREST le rend soit en objet, soit en tableau selon la
   * requête ; absent, le produit n'a simplement pas de prix grossiste.
   */
  function priveDepuisLigne(l) {
    const p = Array.isArray(l.produits_prive) ? l.produits_prive[0] : l.produits_prive;
    if (!p) return { prixGrossiste: 0, tauxMarge: null };
    return {
      prixGrossiste: Math.max(0, Math.round(Number(p.prix_grossiste) || 0)),
      tauxMarge: p.taux_marge === null || p.taux_marge === undefined ? null : Number(p.taux_marge),
    };
  }

  function produitDepuisLigne(l) {
    const images = Array.isArray(l.images) ? l.images : [];
    const stock = stockDepuisLigne(l);
    const prive = priveDepuisLigne(l);
    return {
      id: l.id,
      nom: l.nom,
      reference: l.reference || "",
      description: l.description || "",
      prix: Number(l.prix) || 0,
      prixGrossiste: prive.prixGrossiste,
      tauxMarge: prive.tauxMarge,
      ancienPrix: l.ancien_prix === null || l.ancien_prix === undefined ? null : Number(l.ancien_prix),
      categorieId: l.categorie_id,
      sousCategorieId: l.sous_categorie_id || "",
      stock,
      surCommande: !!l.sur_commande,
      enAvant: !!l.en_avant,
      ordreAvant: l.ordre_avant || 0,
      images,
      video: l.video || "",
      videoUrl: l.video ? Supabase.urlImage(l.video) : "",
      vignette: images.length ? Supabase.urlImage(images[0]) : null,
      creeLe: versMs(l.cree_le),
      modifieLe: versMs(l.modifie_le),
    };
  }

  function ligneDepuisProduit(p) {
    return {
      id: p.id,
      nom: p.nom,
      reference: p.reference,
      description: p.description,
      prix: p.prix,
      ancien_prix: p.ancienPrix,
      categorie_id: p.categorieId,
      sous_categorie_id: p.sousCategorieId || null,
      stock: p.surCommande ? 0 : p.stock,
      sur_commande: !!p.surCommande,
      disponible: !!p.surCommande || p.stock > 0,
      en_avant: p.enAvant,
      ordre_avant: p.ordreAvant,
      images: p.images,
      video: p.video || "",
      modifie_le: new Date().toISOString(),
    };
  }

  /* Une coordonnée saisie à la main : « 6,3654 » vaut « 6.3654 ». */
  function coordonnee(valeur, borne) {
    if (valeur === "" || valeur === null || valeur === undefined) return null;
    const n = Number(String(valeur).replace(",", "."));
    return isFinite(n) && n >= -borne && n <= borne ? n : null;
  }

  /**
   * Les autres numéros de la boutique. Un numéro sans chiffres ne sert à
   * personne : il disparaît. Le libellé est ce que lit le client
   * (« Atelier », « Service après-vente »…).
   */
  function telephonesDepuisListe(liste) {
    return (Array.isArray(liste) ? liste : [])
      .map((t) => ({
        libelle: String((t && t.libelle) || "").trim().slice(0, 40),
        numero: String((t && t.numero) || "").trim().slice(0, 30),
        whatsapp: !!(t && t.whatsapp),
      }))
      .filter((t) => /\d/.test(t.numero))
      .slice(0, MAX_TELEPHONES);
  }

  /** Les autres adresses, chacune avec sa position facultative. */
  function adressesDepuisListe(liste) {
    return (Array.isArray(liste) ? liste : [])
      .map((a) => ({
        libelle: String((a && a.libelle) || "").trim().slice(0, 40),
        texte: String((a && a.texte) || "").trim().slice(0, 200),
        latitude: coordonnee(a && a.latitude, 90),
        longitude: coordonnee(a && a.longitude, 180),
      }))
      .filter((a) => a.texte)
      .slice(0, MAX_ADRESSES);
  }

  function boutiqueDepuisLigne(l) {
    return {
      id: l.id || "",
      secteur: l.secteur || "",
      icone: l.icone || "magasin",
      couleur: l.couleur || "#1176D8",
      logo: l.logo || "",
      logoUrl: l.logo ? Supabase.urlImage(l.logo) : "",
      actif: l.actif !== false,
      ordre: l.ordre || 0,
      nomBoutique: l.nom || BOUTIQUE_DEFAUT.nomBoutique,
      slogan: l.slogan || BOUTIQUE_DEFAUT.slogan,
      description: l.description || "",
      tel: l.tel || "",
      whatsapp: l.whatsapp || "",
      indicatif: l.indicatif || "229",
      devise: l.devise || "FCFA",
      adresse: l.adresse || "",
      horaires: l.horaires || "",
      facebook: l.facebook || "",
      instagram: l.instagram || "",
      tiktok: l.tiktok || "",
      youtube: l.youtube || "",
      snapchat: l.snapchat || "",
      latitude: l.latitude === null || l.latitude === undefined ? null : Number(l.latitude),
      longitude: l.longitude === null || l.longitude === undefined ? null : Number(l.longitude),
      photos: Array.isArray(l.photos) ? l.photos : [],
      /* Colonnes absentes d'une base pas encore mise à jour : liste vide. */
      telephones: telephonesDepuisListe(l.telephones),
      adresses: adressesDepuisListe(l.adresses),
      tauxMarge: l.taux_marge === null || l.taux_marge === undefined
        ? BOUTIQUE_DEFAUT.tauxMarge : Number(l.taux_marge),
    };
  }

  /* =====================================================
     Les boutiques

     L'application couvre plusieurs secteurs : une boutique par
     secteur, chacune avec son catalogue, ses rayons et son slider.
     L'administrateur passe de l'une à l'autre ; le modérateur reste
     dans la sienne, sans même savoir que les autres existent.
     ===================================================== */

  const CLE_BOUTIQUE = "impact-admin-boutique";

  let boutiques = [];        // toutes les boutiques, dans l'ordre
  let boutiqueId = "";       // celle sur laquelle on travaille

  async function chargerBoutiques() {
    const lignes = await Supabase.requete("GET", "boutiques?select=*&order=ordre.asc,cree_le.asc");
    boutiques = (lignes || []).map(boutiqueDepuisLigne);
    return boutiques;
  }

  const listerBoutiques = () => boutiques.map((b) => ({ ...b }));
  const boutiqueCourante = () => boutiques.find((b) => b.id === boutiqueId) || null;
  const lireBoutique = (id) => boutiques.find((b) => b.id === id) || null;

  /**
   * Choisit la boutique sur laquelle on travaille. Un modérateur ne peut
   * pas en sortir : la base le lui refuserait de toute façon.
   */
  function choisirBoutique(id) {
    const cible = lireBoutique(id);
    if (!cible) throw new Error("Cette boutique n'existe plus.");
    if (!Supabase.estAdmin() && cible.id !== Supabase.boutiqueDuCompte()) {
      throw new Error("Votre compte ne gère que la boutique « " +
        ((lireBoutique(Supabase.boutiqueDuCompte()) || {}).nomBoutique || "qui lui est confiée") + " ».");
    }
    boutiqueId = cible.id;
    reglages = { ...cible };
    try { localStorage.setItem(CLE_BOUTIQUE, boutiqueId); } catch (_) { /* navigation privée */ }
    return reglages;
  }

  /** La boutique retenue au démarrage : celle du compte, ou la dernière ouverte. */
  function boutiqueDeDepart() {
    const duCompte = Supabase.boutiqueDuCompte();
    if (duCompte && lireBoutique(duCompte)) return duCompte;
    if (!Supabase.estAdmin() && Supabase.rolesActifs()) return "";
    let memorisee = "";
    try { memorisee = localStorage.getItem(CLE_BOUTIQUE) || ""; } catch (_) { /* sans importance */ }
    if (memorisee && lireBoutique(memorisee)) return memorisee;
    return (boutiques[0] || {}).id || "";
  }

  function ligneDepuisBoutique(b) {
    return {
      nom: b.nomBoutique,
      secteur: b.secteur || "",
      slogan: b.slogan || "",
      description: b.description || "",
      icone: b.icone || "magasin",
      couleur: b.couleur || "#1176D8",
      logo: b.logo || "",
      actif: b.actif !== false,
      ordre: b.ordre || 0,
      tel: b.tel || "",
      whatsapp: b.whatsapp || "",
      indicatif: b.indicatif || "229",
      devise: b.devise || "FCFA",
      adresse: b.adresse || "",
      horaires: b.horaires || "",
      facebook: b.facebook || "",
      instagram: b.instagram || "",
      tiktok: b.tiktok || "",
      youtube: b.youtube || "",
      snapchat: b.snapchat || "",
      latitude: b.latitude === undefined ? null : b.latitude,
      longitude: b.longitude === undefined ? null : b.longitude,
      photos: b.photos || [],
      telephones: b.telephones || [],
      adresses: b.adresses || [],
      taux_marge: b.tauxMarge === undefined ? 20 : b.tauxMarge,
      maj_le: new Date().toISOString(),
    };
  }

  /** Crée une boutique ou modifie son identité. Réservé à l'administrateur. */
  async function sauverBoutique(donnees) {
    const nom = (donnees.nomBoutique || "").trim();
    if (!nom) throw new Error("Le nom de la boutique est obligatoire.");
    const existante = donnees.id ? lireBoutique(donnees.id) : null;

    /* Logo : une image neuve part au stockage, sinon on garde l'ancienne. */
    let logo = existante ? existante.logo : "";
    if (donnees.logo && donnees.logo.dataUrl) {
      logo = "boutiques/" + Utils.uid("bou") + ".jpg";
      await Supabase.televerserImage(logo, donnees.logo.dataUrl);
    } else if (donnees.logo === null) {
      logo = "";
    }

    const boutique = {
      ...(existante || { ...BOUTIQUE_DEFAUT, actif: true }),
      ...donnees,
      logo,
      nomBoutique: nom,
      id: existante ? existante.id : Utils.uid("bou"),
      ordre: existante ? existante.ordre
        : boutiques.reduce((m, b) => Math.max(m, b.ordre || 0), 0) + 1,
    };

    const ligne = ligneDepuisBoutique(boutique);
    if (existante) {
      await Supabase.requete("PATCH", "boutiques?id=eq." + encodeURIComponent(boutique.id), ligne);
      journaliser("boutique", "modification", "Boutique modifiée : " + nom, nom);
    } else {
      await Supabase.requete("POST", "boutiques", { id: boutique.id, ...ligne,
        cree_le: new Date().toISOString() });
      journaliser("boutique", "ajout", "Nouvelle boutique : " + nom, nom);
    }

    await chargerBoutiques();
    if (boutiqueId === boutique.id) reglages = { ...(lireBoutique(boutiqueId) || reglages) };
    return lireBoutique(boutique.id);
  }

  /** Ouvre ou ferme une boutique : fermée, elle disparaît de l'app client. */
  async function basculerBoutique(id) {
    const b = lireBoutique(id);
    if (!b) throw new Error("Cette boutique n'existe plus.");
    const actif = !b.actif;
    await Supabase.requete("PATCH", "boutiques?id=eq." + encodeURIComponent(id),
      { actif, maj_le: new Date().toISOString() });
    journaliser("boutique", actif ? "activation" : "desactivation",
      (actif ? "Boutique ouverte : " : "Boutique fermée : ") + b.nomBoutique, b.nomBoutique);
    await chargerBoutiques();
    if (boutiqueId === id) reglages = { ...(lireBoutique(id) || reglages) };
    return lireBoutique(id);
  }

  /** Monte ou descend une boutique dans l'ordre d'affichage du client. */
  async function deplacerBoutique(id, sens) {
    const liste = boutiques.slice().sort((a, b) => (a.ordre || 0) - (b.ordre || 0));
    const i = liste.findIndex((b) => b.id === id);
    const j = i + (sens === "haut" ? -1 : 1);
    if (i < 0 || j < 0 || j >= liste.length) return listerBoutiques();
    const tmp = liste[i]; liste[i] = liste[j]; liste[j] = tmp;
    for (let k = 0; k < liste.length; k++) {
      if (liste[k].ordre !== k + 1) {
        await Supabase.requete("PATCH", "boutiques?id=eq." + encodeURIComponent(liste[k].id),
          { ordre: k + 1 });
      }
    }
    return chargerBoutiques();
  }

  /**
   * Supprime une boutique : son catalogue, ses rayons et son slider
   * partent avec elle (la base s'en charge en cascade).
   */
  async function supprimerBoutique(id) {
    const b = lireBoutique(id);
    if (!b) throw new Error("Cette boutique n'existe plus.");
    if (boutiques.length <= 1) {
      throw new Error("C'est la dernière boutique : l'application doit en garder au moins une.");
    }
    await Supabase.requete("DELETE", "boutiques?id=eq." + encodeURIComponent(id));
    journaliser("boutique", "suppression", "Boutique supprimée : " + b.nomBoutique, b.nomBoutique);
    await chargerBoutiques();
    if (boutiqueId === id) choisirBoutique((boutiques[0] || {}).id);
    return listerBoutiques();
  }

  /* ---------- Démarrage ---------- */

  async function init() {
    if (!Supabase.estConfigure()) {
      const err = new Error("Configuration requise");
      err.nonConfigure = true;
      throw err;
    }
    await Supabase.chargerProfil();   // le rôle du compte : ce qu'il a le droit de faire
    try {
      await chargerBoutiques();
    } catch (err) {
      /* Base pas encore mise à jour : on retombe sur la boutique unique. */
      if (!/boutiques|does not exist|mise à jour de la base/i.test(err.message || "")) throw err;
      boutiques = [];
    }
    if (boutiques.length) {
      const depart = boutiqueDeDepart();
      if (depart) {
        boutiqueId = depart;
        reglages = { ...lireBoutique(depart) };
      }
      return;
    }
    const lignes = await Supabase.requete("GET", "boutique?select=*&id=eq.1");
    if (lignes && lignes.length) reglages = boutiqueDepuisLigne(lignes[0]);
  }

  /* ---------- Comptes de l'équipe (réservé à l'administrateur) ---------- */

  const ROLES = {
    administrateur: { nom: "Administrateur", aide: "Toute l'application : produits, catégories, réglages, comptes." },
    moderateur: { nom: "Modérateur", aide: "Produits et catégories uniquement." },
  };

  function compteDepuisLigne(l) {
    return {
      id: l.id,
      email: l.email || "",
      role: l.role === "administrateur" ? "administrateur" : "moderateur",
      actif: l.actif !== false,
      peutModifier: l.peut_modifier_produits !== false,
      boutiqueId: l.boutique_id || "",
      creeLe: versMs(l.cree_le),
    };
  }

  async function listerComptes() {
    const lignes = await Supabase.requete("GET",
      "profils?select=*&order=role.asc,email.asc", undefined, { avecSession: true });
    return (lignes || []).map(compteDepuisLigne);
  }

  /**
   * Crée le compte dans Supabase, puis lui donne son rôle. La fiche existe
   * déjà — la base la pose à la création du compte — il ne reste qu'à
   * l'activer et à inscrire le rôle voulu.
   */
  async function creerCompte(email, motDePasse, role, boutiqueRattachee) {
    const adresse = String(email || "").trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(adresse)) throw new Error("Indiquez une adresse email valide.");
    if (String(motDePasse || "").length < 6) throw new Error("Le mot de passe doit faire 6 caractères au moins.");
    if (!ROLES[role]) throw new Error("Choisissez le rôle du compte.");

    /* Un modérateur travaille dans une boutique et une seule ;
       un administrateur les gère toutes, il n'en porte donc aucune. */
    let attachee = null;
    if (role === "moderateur" && boutiques.length) {
      attachee = boutiqueRattachee || "";
      if (!attachee) throw new Error("Choisissez la boutique confiée à ce modérateur.");
      if (!lireBoutique(attachee)) throw new Error("Cette boutique n'existe plus.");
    }

    const cree = await Supabase.creerCompte(adresse, motDePasse);
    const fiche = { id: cree.id, email: adresse, role, actif: true, boutique_id: attachee };
    await Supabase.requete("POST", "profils?on_conflict=id", fiche, { upsert: true });
    const ou = attachee ? " (" + (lireBoutique(attachee) || {}).nomBoutique + ")" : "";
    journaliser("compte", "ajout", ROLES[role].nom + " ajouté : " + adresse + ou, adresse);
    return { ...compteDepuisLigne(fiche), confirmationRequise: cree.confirmationRequise };
  }

  async function majCompte(id, maj) {
    /* Les noms de l'application ne sont pas ceux de la base. */
    const ligne = { ...maj };
    if (maj.peutModifier !== undefined) {
      ligne.peut_modifier_produits = !!maj.peutModifier;
      delete ligne.peutModifier;
    }
    if (maj.boutiqueId !== undefined) {
      ligne.boutique_id = maj.boutiqueId || null;
      delete ligne.boutiqueId;
    }
    const lignes = await Supabase.requete("PATCH", "profils?id=eq." + encodeURIComponent(id), ligne);
    const c = compteDepuisLigne((lignes || [])[0] || { id, ...ligne });
    if (maj.role) {
      journaliser("compte", "modification",
        c.email + " devient " + ROLES[c.role].nom.toLowerCase(), c.email);
    } else if (maj.actif !== undefined) {
      journaliser("compte", maj.actif ? "activation" : "desactivation",
        (maj.actif ? "Compte réactivé : " : "Compte désactivé : ") + c.email, c.email);
    } else if (maj.boutiqueId !== undefined) {
      const nom = (lireBoutique(maj.boutiqueId) || {}).nomBoutique || "toutes les boutiques";
      journaliser("compte", "modification", c.email + " s'occupe de " + nom, c.email);
    } else if (maj.peutModifier !== undefined) {
      journaliser("compte", "modification",
        (maj.peutModifier
          ? "Autorisé à modifier les produits : "
          : "Ne peut plus modifier les produits : ") + c.email, c.email);
    }
    return c;
  }

  /**
   * Supprime définitivement un compte : sa fiche et son identifiant de
   * connexion. Passe par une fonction de la base, seule habilitée.
   */
  async function supprimerCompte(id) {
    const liste = await listerComptes();
    const compte = liste.find((c) => c.id === id);
    await Supabase.rpc("supprimer_compte", { cible: id });
    journaliser("compte", "suppression",
      "Compte supprimé : " + ((compte && compte.email) || id), compte ? compte.email : "");
  }

  /** L'administrateur redonne un mot de passe à un membre de l'équipe. */
  async function changerMotDePasseCompte(id, nouveau) {
    if (String(nouveau || "").length < 6) {
      throw new Error("Le mot de passe doit faire 6 caractères au moins.");
    }
    const liste = await listerComptes();
    const compte = liste.find((c) => c.id === id);
    await Supabase.rpc("changer_mot_de_passe", { cible: id, nouveau });
    journaliser("compte", "modification",
      "Mot de passe redéfini : " + ((compte && compte.email) || id), compte ? compte.email : "");
  }

  /* ---------- Journal des actions ----------
     Chaque geste du gérant laisse une trace lisible : qui, quoi, quand.
     L'écriture ne bloque jamais l'action elle-même. */

  function journaliser(famille, action, libelle, cible) {
    const ligne = {
      utilisateur: Supabase.utilisateur() || "",
      famille, action, libelle,
      cible: cible || "",
      fait_le: new Date().toISOString(),
    };
    return Supabase.requete("POST", "journal", ligne, { sansRetour: true })
      .catch(() => { /* le journal ne doit jamais gêner le travail */ });
  }

  /** Les dernières actions, de la plus récente à la plus ancienne.
      Le journal n'est pas public : la lecture porte le jeton du compte. */
  async function lireJournal(limite = 100, decalage = 0) {
    const lignes = await Supabase.requete("GET",
      "journal?select=*&order=fait_le.desc&limit=" + limite + "&offset=" + decalage,
      undefined, { avecSession: true });
    return (lignes || []).map((l) => ({
      id: l.id,
      date: versMs(l.fait_le),
      utilisateur: l.utilisateur || "",
      famille: l.famille || "autre",
      action: l.action || "",
      libelle: l.libelle || "",
      cible: l.cible || "",
    }));
  }

  /* ---------- Réglages boutique ---------- */

  const lireReglages = () => ({ ...reglages });

  /** Le filtre « seulement ma boutique », ajouté à chaque lecture. */
  const filtreBoutique = () =>
    (boutiqueId ? "boutique_id=eq." + encodeURIComponent(boutiqueId) : "");

  async function majReglages(maj, libelleJournal) {
    /* Depuis les boutiques multiples, les réglages sont ceux de la
       boutique ouverte : on écrit dans sa ligne à elle. */
    if (boutiqueId) {
      const propre = { ...maj };
      if (maj.telephones !== undefined) propre.telephones = telephonesDepuisListe(maj.telephones);
      if (maj.adresses !== undefined) propre.adresses = adressesDepuisListe(maj.adresses);
      if (maj.tauxMarge !== undefined) {
        const taux = lireTaux(maj.tauxMarge);
        if (taux === null) throw new Error("Le taux doit être un nombre entre 0 et " + TAUX_MAX + " %.");
        propre.tauxMarge = taux;
      }
      reglages = { ...reglages, ...propre };
      await Supabase.requete("PATCH", "boutiques?id=eq." + encodeURIComponent(boutiqueId),
        ligneDepuisBoutique(reglages));
      const index = boutiques.findIndex((b) => b.id === boutiqueId);
      if (index >= 0) boutiques[index] = { ...reglages };
      if (libelleJournal) journaliser("boutique", "modification", libelleJournal, reglages.nomBoutique);
      return lireReglages();
    }
    return majReglagesUnique(maj, libelleJournal);
  }

  /** Ancienne base, boutique unique : on écrit dans la ligne « boutique ». */
  async function majReglagesUnique(maj, libelleJournal) {
    const propre = { ...maj };
    if (maj.telephones !== undefined) propre.telephones = telephonesDepuisListe(maj.telephones);
    if (maj.adresses !== undefined) propre.adresses = adressesDepuisListe(maj.adresses);
    if (maj.tauxMarge !== undefined) {
      const taux = lireTaux(maj.tauxMarge);
      if (taux === null) throw new Error("Le taux doit être un nombre entre 0 et " + TAUX_MAX + " %.");
      propre.tauxMarge = taux;
    }
    reglages = { ...reglages, ...propre };
    const r = reglages;
    await Supabase.requete("PATCH", "boutique?id=eq.1", {
      nom: r.nomBoutique,
      slogan: r.slogan,
      description: r.description,
      tel: r.tel,
      whatsapp: r.whatsapp,
      indicatif: r.indicatif,
      devise: r.devise,
      adresse: r.adresse,
      horaires: r.horaires,
      facebook: r.facebook,
      instagram: r.instagram,
      tiktok: r.tiktok,
      youtube: r.youtube,
      snapchat: r.snapchat,
      latitude: r.latitude,
      longitude: r.longitude,
      photos: r.photos || [],
      telephones: r.telephones || [],
      adresses: r.adresses || [],
      taux_marge: r.tauxMarge,
      maj_le: new Date().toISOString(),
    });
    if (libelleJournal) journaliser("boutique", "modification", libelleJournal, r.nomBoutique);
    return lireReglages();
  }

  /** URL publiques des photos de la boutique, pour l'aperçu. */
  function photosBoutique() {
    return (reglages.photos || []).map((chemin) => ({
      id: chemin.replace(/^boutique\//, "").replace(/\.jpg$/i, ""),
      chemin,
      apercu: Supabase.urlImage(chemin),
    }));
  }

  /**
   * Enregistre les photos de la boutique.
   * `photosFinales` : [{ id, chemin? (en ligne), dataUrl? (nouvelle) }]
   */
  async function sauverPhotosBoutique(photosFinales) {
    const photos = (photosFinales || []).slice(0, MAX_PHOTOS_BOUTIQUE);
    const chemins = [];
    for (const photo of photos) {
      if (photo.chemin) {
        chemins.push(photo.chemin);
      } else if (photo.dataUrl) {
        const chemin = "boutique/" + (photo.id || Utils.uid("bou")) + ".jpg";
        await Supabase.televerserImage(chemin, photo.dataUrl);
        chemins.push(chemin);
      }
    }
    const retirees = (reglages.photos || []).filter((chemin) => !chemins.includes(chemin));
    await Supabase.supprimerImages(retirees);
    return majReglages({ photos: chemins },
      "Photos de la boutique mises à jour (" + chemins.length + " photo" + (chemins.length > 1 ? "s" : "") + ")");
  }

  /* ---------- Catégories ---------- */

  async function listerCategories() {
    const lignes = await Supabase.requete("GET",
      "categories?select=*,sous_categories(*)&order=ordre.asc" +
      (filtreBoutique() ? "&" + filtreBoutique() : ""));
    return (lignes || []).map((c) => ({
      id: c.id,
      nom: c.nom,
      ordre: c.ordre || 0,
      sousCategories: (c.sous_categories || [])
        .map((s) => ({ id: s.id, nom: s.nom, ordre: s.ordre || 0 }))
        .sort((a, b) => a.ordre - b.ordre),
    }));
  }

  async function lireCategorie(id) {
    const categories = await listerCategories();
    return categories.find((c) => c.id === id) || null;
  }

  async function sauverCategorie(donnees) {
    const nom = (donnees.nom || "").trim();
    if (!nom) throw new Error("Le nom de la catégorie est obligatoire.");

    const existantes = await listerCategories();
    const existante = donnees.id ? existantes.find((c) => c.id === donnees.id) : null;

    const id = existante ? existante.id : Utils.uid("cat");
    const ordre = existante
      ? existante.ordre
      : existantes.reduce((m, c) => Math.max(m, c.ordre || 0), 0) + 1;

    if (existante) {
      await Supabase.requete("PATCH", "categories?id=eq." + encodeURIComponent(id), { nom, ordre });
    } else {
      /* Un rayon appartient à la boutique ouverte. */
      await Supabase.requete("POST", "categories",
        boutiqueId ? { id, boutique_id: boutiqueId, nom, ordre } : { id, nom, ordre });
    }

    /* Sous-catégories : aligner la base sur la liste finale. */
    const voulues = (donnees.sousCategories || [])
      .map((s, i) => ({ id: s.id || null, nom: (s.nom || "").trim(), ordre: i + 1 }))
      .filter((s) => s.nom);
    const anciennes = existante ? existante.sousCategories : [];
    const gardees = new Set(voulues.filter((s) => s.id).map((s) => s.id));

    for (const ancienne of anciennes) {
      if (!gardees.has(ancienne.id)) {
        await Supabase.requete("DELETE", "sous_categories?id=eq." + encodeURIComponent(ancienne.id));
      }
    }
    for (const s of voulues) {
      if (s.id) {
        const avant = anciennes.find((x) => x.id === s.id);
        if (!avant || avant.nom !== s.nom || avant.ordre !== s.ordre) {
          await Supabase.requete("PATCH", "sous_categories?id=eq." + encodeURIComponent(s.id),
            { nom: s.nom, ordre: s.ordre });
        }
      } else {
        await Supabase.requete("POST", "sous_categories",
          { id: Utils.uid("sc"), categorie_id: id, nom: s.nom, ordre: s.ordre });
      }
    }

    journaliser("categorie", existante ? "modification" : "ajout",
      (existante ? "Catégorie modifiée : " : "Nouvelle catégorie : ") + nom +
      " (" + voulues.length + " sous-catégorie" + (voulues.length > 1 ? "s" : "") + ")", nom);
    return lireCategorie(id);
  }

  async function supprimerCategorie(id) {
    const produits = await produitsDeCategorie(id);
    if (produits.length) {
      throw new Error("Impossible : " + produits.length + " produit" + (produits.length > 1 ? "s" : "") +
        " se trouve" + (produits.length > 1 ? "nt" : "") + " dans cette catégorie. Déplacez-les d'abord.");
    }
    const categorie = await lireCategorie(id);
    await Supabase.requete("DELETE", "categories?id=eq." + encodeURIComponent(id));
    journaliser("categorie", "suppression",
      "Catégorie supprimée : " + (categorie ? categorie.nom : id), categorie ? categorie.nom : "");
  }

  /** Échange l'ordre avec la catégorie voisine (direction -1 ou +1). */
  async function deplacerCategorie(id, direction) {
    const categories = await listerCategories();
    const index = categories.findIndex((c) => c.id === id);
    const voisin = categories[index + direction];
    if (index < 0 || !voisin) return;
    const courant = categories[index];
    await Supabase.requete("PATCH", "categories?id=eq." + encodeURIComponent(courant.id), { ordre: voisin.ordre });
    await Supabase.requete("PATCH", "categories?id=eq." + encodeURIComponent(voisin.id), { ordre: courant.ordre });
    journaliser("categorie", "ordre", "Ordre des catégories modifié : " + courant.nom, courant.nom);
  }

  /* ---------- Produits ---------- */

  /**
   * Les produits, prix d'achat compris. La lecture porte le jeton du
   * compte : la table des prix d'achat est fermée à la clé publique.
   * Sur une base pas encore mise à jour, elle n'existe pas — on la
   * laisse alors de côté plutôt que de bloquer tout le catalogue.
   */
  async function lignesProduits(suite) {
    const morceaux = [suite, filtreBoutique()].filter(Boolean);
    const fin = morceaux.length ? "&" + morceaux.join("&") : "";
    if (prixAchatEnBase) {
      try {
        return await Supabase.requete("GET", "produits?select=*,produits_prive(*)" + fin,
          undefined, { avecSession: true });
      } catch (err) {
        if (!/produits_prive|relationship/i.test(err.message || "")) throw err;
        prixAchatEnBase = false;
      }
    }
    return Supabase.requete("GET", "produits?select=*" + fin, undefined, { avecSession: true });
  }

  async function listerProduits() {
    const lignes = await lignesProduits("order=modifie_le.desc");
    return (lignes || []).map(produitDepuisLigne);
  }

  async function lireProduit(id) {
    const lignes = await lignesProduits("id=eq." + encodeURIComponent(id));
    return lignes && lignes.length ? produitDepuisLigne(lignes[0]) : null;
  }

  async function produitsDeCategorie(categorieId) {
    const lignes = await lignesProduits("categorie_id=eq." + encodeURIComponent(categorieId));
    return (lignes || []).map(produitDepuisLigne);
  }

  function chercherProduits(produits, terme) {
    const t = Utils.sansAccent(terme).trim();
    if (!t) return produits;
    return produits.filter((p) => {
      const texte = Utils.sansAccent(p.nom + " " + (p.reference || "") + " " + (p.description || ""));
      return t.split(/\s+/).every((mot) => texte.includes(mot));
    });
  }

  /** Prochaine référence libre au format IMP-0001, IMP-0002… */
  /**
   * La prochaine référence libre. Elle se compte sur TOUTES les boutiques :
   * deux produits de rayons différents ne doivent jamais porter le même
   * numéro, sinon une commande WhatsApp devient ambiguë.
   */
  async function prochaineReference() {
    const lignes = await Supabase.requete("GET", "produits?select=reference");
    let max = 0;
    for (const l of lignes || []) {
      const m = /^IMP-(\d+)$/i.exec(String(l.reference || "").trim());
      if (m) max = Math.max(max, parseInt(m[1], 10));
    }
    return "IMP-" + String(max + 1).padStart(4, "0");
  }

  /**
   * Crée ou met à jour un produit.
   * `photosFinales` : liste ordonnée [{ id, chemin?, dataUrl? }] —
   * `chemin` pour une photo déjà en ligne, `dataUrl` pour une nouvelle.
   * `donnees.video` : { chemin } (inchangée), { fichier } (nouvelle) ou null.
   */
  async function sauverProduit(donnees, photosFinales) {
    const existant = donnees.id ? await lireProduit(donnees.id) : null;

    const nom = (donnees.nom || "").trim();
    if (!nom) throw new Error("Le nom du produit est obligatoire.");

    let reference = (donnees.reference || "").trim();
    if (!reference) reference = await prochaineReference();
    const tous = await listerProduits();
    const doublon = tous.find((x) => x.reference &&
      x.reference.toLowerCase() === reference.toLowerCase() && x.id !== (existant && existant.id));
    if (doublon) {
      throw new Error("La référence « " + reference + " » est déjà utilisée par « " + doublon.nom + " ».");
    }

    /* Prix d'achat et taux : le prix public en découle, sauf s'il a été
       arrondi à la main — c'est alors celui-là qui fait foi. */
    const prixGrossiste = Math.max(0, Math.round(Utils.lireNombre(donnees.prixGrossiste) || 0));
    const tauxMarge = prixGrossiste ? lireTaux(donnees.tauxMarge) : null;

    const prix = donnees.prix === "" || donnees.prix === null || donnees.prix === undefined
      ? prixPublic(prixGrossiste, tauxMarge)
      : Math.round(Utils.lireNombre(donnees.prix));
    if (prix <= 0) {
      throw new Error(prixGrossiste
        ? "Le prix public est vide : vérifiez le prix grossiste et le taux."
        : "Indiquez le prix de vente.");
    }
    if (prixGrossiste && prix < prixGrossiste) {
      throw new Error("Le prix public (" + Utils.fmtMontant(prix, reglages.devise) +
        ") est inférieur au prix grossiste (" + Utils.fmtMontant(prixGrossiste, reglages.devise) +
        ") : vous vendriez à perte.");
    }

    let ancienPrix = donnees.ancienPrix === "" || donnees.ancienPrix === null || donnees.ancienPrix === undefined
      ? null : Math.round(Utils.lireNombre(donnees.ancienPrix));
    if (!ancienPrix) ancienPrix = null;
    if (ancienPrix !== null && ancienPrix <= prix) {
      throw new Error("Le prix barré doit être supérieur au prix actuel (c'est l'ancien prix).");
    }

    if (!donnees.categorieId) throw new Error("Choisissez une catégorie.");
    const categorie = await lireCategorie(donnees.categorieId);
    if (!categorie) throw new Error("Cette catégorie n'existe plus.");
    let sousCategorieId = donnees.sousCategorieId || "";
    if (categorie.sousCategories.length && !categorie.sousCategories.some((s) => s.id === sousCategorieId)) {
      throw new Error("Choisissez une sous-catégorie.");
    }
    if (!categorie.sousCategories.length) sousCategorieId = "";

    const enAvant = !!donnees.enAvant;
    let ordreAvant = existant ? existant.ordreAvant || 0 : 0;
    if (enAvant && !(existant && existant.enAvant)) {
      const autres = (await listerEnAvant()).filter((p) => p.id !== (existant && existant.id));
      if (autres.length >= MAX_EN_AVANT) {
        throw new Error("Déjà " + MAX_EN_AVANT + " produits dans le slider (le maximum). Retirez-en un d'abord.");
      }
      ordreAvant = autres.reduce((m, p) => Math.max(m, p.ordreAvant || 0), 0) + 1;
    }
    if (!enAvant) ordreAvant = 0;

    /* Photos : envoyer les nouvelles, retirer celles enlevées. */
    const photos = (photosFinales || []).slice(0, MAX_PHOTOS);
    const chemins = [];
    for (const photo of photos) {
      if (photo.chemin) {
        chemins.push(photo.chemin);
      } else if (photo.dataUrl) {
        const chemin = (photo.id || Utils.uid("pho")) + ".jpg";
        await Supabase.televerserImage(chemin, photo.dataUrl);
        chemins.push(chemin);
      }
    }
    /* Vidéo de présentation : une seule par produit. */
    let cheminVideo = "";
    const video = donnees.video;
    if (video && video.chemin) {
      cheminVideo = video.chemin;
    } else if (video && video.fichier) {
      const octets = video.fichier.size || 0;
      if (octets > MAX_VIDEO_MO * 1024 * 1024) {
        throw new Error("Vidéo trop lourde (" + Utils.tailleLisible(octets) + "). " +
          "Filmez une présentation plus courte : " + MAX_VIDEO_MO + " Mo au maximum.");
      }
      const extension = (video.fichier.name || "").match(/\.([a-z0-9]{2,4})$/i);
      cheminVideo = Utils.uid("vid") + (extension ? "." + extension[1].toLowerCase() : ".mp4");
      await Supabase.televerserVideo(cheminVideo, video.fichier);
    }

    if (existant) {
      const retirees = (existant.images || []).filter((chemin) => !chemins.includes(chemin));
      if (existant.video && existant.video !== cheminVideo) retirees.push(existant.video);
      await Supabase.supprimerImages(retirees);
    }

    const surCommande = !!donnees.surCommande;
    const stock = lireStock(donnees.stock);
    const produit = {
      id: existant ? existant.id : Utils.uid("prod"),
      nom,
      reference,
      description: (donnees.description || "").trim(),
      prix,
      prixGrossiste,
      tauxMarge,
      ancienPrix,
      categorieId: donnees.categorieId,
      sousCategorieId,
      stock: surCommande ? 0 : stock,
      surCommande,
      enAvant,
      ordreAvant,
      images: chemins,
      video: cheminVideo,
    };

    const ligne = ligneDepuisProduit(produit);
    let lignes;
    if (existant) {
      lignes = await Supabase.requete("PATCH", "produits?id=eq." + encodeURIComponent(produit.id), ligne);
      journaliser("produit", "modification",
        "Produit modifié : " + produit.nom + " — " + Utils.fmtMontant(produit.prix, reglages.devise),
        produit.reference || produit.nom);
    } else {
      ligne.cree_le = new Date().toISOString();
      /* Le produit naît dans la boutique ouverte, et n'en bougera plus. */
      if (boutiqueId) ligne.boutique_id = boutiqueId;
      lignes = await Supabase.requete("POST", "produits", ligne);
      journaliser("produit", "ajout",
        "Nouveau produit : " + produit.nom + " — " + Utils.fmtMontant(produit.prix, reglages.devise),
        produit.reference || produit.nom);
    }
    await sauverPrixAchat(produit.id, prixGrossiste, tauxMarge);
    const enregistre = produitDepuisLigne(Array.isArray(lignes) ? lignes[0] : ligne);
    return { ...enregistre, prixGrossiste, tauxMarge };
  }

  /**
   * Le prix d'achat vit à part : une ligne par produit, écrite en même
   * temps que lui. Une base pas encore mise à jour n'en a pas la table —
   * le produit s'enregistre quand même, sans son prix d'achat.
   */
  async function sauverPrixAchat(id, prixGrossiste, tauxMarge) {
    if (!prixAchatEnBase) return;
    try {
      await Supabase.requete("POST", "produits_prive?on_conflict=produit_id", {
        produit_id: id,
        prix_grossiste: prixGrossiste,
        taux_marge: tauxMarge,
        maj_le: new Date().toISOString(),
      }, { upsert: true });
    } catch (err) {
      if (!/produits_prive|relationship/i.test(err.message || "")) throw err;
      prixAchatEnBase = false;
    }
  }

  async function supprimerProduit(id) {
    const produit = await lireProduit(id);
    if (produit) {
      const fichiers = (produit.images || []).slice();
      if (produit.video) fichiers.push(produit.video);
      await Supabase.supprimerImages(fichiers);
    }
    await Supabase.requete("DELETE", "produits?id=eq." + encodeURIComponent(id));
    if (produit) {
      journaliser("produit", "suppression", "Produit supprimé : " + produit.nom,
        produit.reference || produit.nom);
    }
  }

  /** Photos d'un produit, prêtes pour le formulaire et la visionneuse. */
  async function photosDeProduit(produitId) {
    const produit = await lireProduit(produitId);
    return ((produit && produit.images) || []).map((chemin) => ({
      id: chemin.replace(/\.jpg$/i, ""),
      chemin,
      apercu: Supabase.urlImage(chemin),
    }));
  }

  /**
   * Change l'état d'un produit sans repasser par le formulaire :
   * un nombre de pièces, ou le passage en « Sur commande ».
   */
  async function majDisponibilite(id, maj) {
    const produit = await lireProduit(id);
    if (!produit) throw new Error("Produit introuvable.");
    const surCommande = maj.surCommande !== undefined ? !!maj.surCommande : produit.surCommande;
    const stock = surCommande ? 0 : lireStock(maj.stock !== undefined ? maj.stock : produit.stock);
    if (stock === produit.stock && surCommande === produit.surCommande) return produit;

    await Supabase.requete("PATCH", "produits?id=eq." + encodeURIComponent(id), {
      stock,
      sur_commande: surCommande,
      disponible: surCommande || stock > 0,
      modifie_le: new Date().toISOString(),
    });

    const avant = statut(produit);
    const apres = statut({ stock, surCommande });
    /* Un changement d'état a plus de sens dans l'historique qu'un simple chiffre. */
    const action = apres === "rupture" ? "rupture"
      : apres === "commande" ? "sur_commande"
      : (avant === "disponible" ? "stock" : "retour_stock");
    const libelle = apres === "commande"
      ? "Passé en « Sur commande » : " + produit.nom
      : apres === "rupture"
        ? "En rupture : " + produit.nom
        : (avant === "disponible"
            ? "Stock : " + produit.stock + " → " + stock + " — " + produit.nom
            : "Réapprovisionné (" + stock + ") : " + produit.nom);
    journaliser("produit", action, libelle, produit.reference || produit.nom);
    return { ...produit, stock, surCommande };
  }

  /* ---------- Produits mis en avant ----------
     Ils défilent dans le slider à la suite des images libres. */

  async function listerEnAvant() {
    const produits = await listerProduits();
    return produits
      .filter((p) => p.enAvant)
      .sort((a, b) => (a.ordreAvant || 0) - (b.ordreAvant || 0));
  }

  async function basculerEnAvant(id) {
    const produit = await lireProduit(id);
    if (!produit) throw new Error("Produit introuvable.");
    if (!produit.enAvant) {
      const actuels = (await listerEnAvant()).filter((p) => p.id !== id);
      if (actuels.length >= MAX_EN_AVANT) {
        throw new Error("Déjà " + MAX_EN_AVANT + " produits dans le slider (le maximum). Retirez-en un d'abord.");
      }
      produit.enAvant = true;
      produit.ordreAvant = actuels.reduce((m, p) => Math.max(m, p.ordreAvant || 0), 0) + 1;
    } else {
      produit.enAvant = false;
      produit.ordreAvant = 0;
    }
    await Supabase.requete("PATCH", "produits?id=eq." + encodeURIComponent(id), {
      en_avant: produit.enAvant,
      ordre_avant: produit.ordreAvant,
      modifie_le: new Date().toISOString(),
    });
    journaliser("produit", produit.enAvant ? "mise_en_avant" : "retrait_avant",
      (produit.enAvant ? "Ajouté au slider client : " : "Retiré du slider client : ") + produit.nom,
      produit.reference || produit.nom);
    return produit;
  }

  /** Monte ou descend un produit dans le slider (direction -1 ou +1). */
  async function deplacerEnAvant(id, direction) {
    const liste = await listerEnAvant();
    const index = liste.findIndex((p) => p.id === id);
    const voisin = liste[index + direction];
    if (index < 0 || !voisin) return;
    liste.forEach((p, i) => { p.ordreAvant = i + 1; });
    const courant = liste[index];
    const tmp = courant.ordreAvant;
    courant.ordreAvant = voisin.ordreAvant;
    voisin.ordreAvant = tmp;
    for (const p of [courant, voisin]) {
      await Supabase.requete("PATCH", "produits?id=eq." + encodeURIComponent(p.id),
        { ordre_avant: p.ordreAvant });
    }
    journaliser("produit", "ordre_slider",
      "Ordre du slider modifié : " + courant.nom + " en position " + courant.ordreAvant,
      courant.reference || courant.nom);
  }

  /* ---------- Images libres du slider ----------
     Choisies une par une, dans l'ordre voulu. Chacune peut renvoyer
     vers un produit — ou n'être qu'une affiche. */

  function slideDepuisLigne(l) {
    return {
      id: l.id,
      chemin: l.image || "",
      apercu: l.image ? Supabase.urlImage(l.image) : "",
      titre: l.titre || "",
      produitId: l.produit_id || "",
      ordre: l.ordre || 0,
      actif: l.actif !== false,
    };
  }

  async function listerSlides() {
    const lignes = await Supabase.requete("GET", "slides?select=*&order=ordre.asc" +
      (filtreBoutique() ? "&" + filtreBoutique() : ""));
    return (lignes || []).map(slideDepuisLigne);
  }

  const lireSlide = async (id) => (await listerSlides()).find((s) => s.id === id) || null;

  /**
   * Enregistre une image du slider. `donnees.image` est soit une image
   * déjà en ligne ({ chemin }), soit une nouvelle ({ dataUrl }).
   */
  async function sauverSlide(donnees) {
    const existant = donnees.id ? await lireSlide(donnees.id) : null;
    const liste = await listerSlides();
    if (!existant && liste.length >= MAX_SLIDES) {
      throw new Error("Le slider accepte " + MAX_SLIDES + " images au maximum. Retirez-en une d'abord.");
    }

    const image = donnees.image || {};
    let chemin = image.chemin || (existant ? existant.chemin : "");
    if (image.dataUrl) {
      chemin = "slider/" + Utils.uid("sli") + ".jpg";
      await Supabase.televerserImage(chemin, image.dataUrl);
    }
    if (!chemin) throw new Error("Choisissez l'image à faire défiler.");

    const slide = {
      id: existant ? existant.id : Utils.uid("sli"),
      image: chemin,
      titre: (donnees.titre || "").trim(),
      produit_id: donnees.produitId || null,
      ordre: existant ? existant.ordre : liste.reduce((m, s) => Math.max(m, s.ordre || 0), 0) + 1,
      actif: donnees.actif !== false,
    };
    /* Le slider appartient à la boutique ouverte : l'accueil du client
       réunit ensuite ceux de toutes les boutiques ouvertes. */
    if (boutiqueId) slide.boutique_id = boutiqueId;
    const lignes = await Supabase.requete("POST", "slides?on_conflict=id", slide, { upsert: true });

    /* L'ancienne image ne sert plus à rien : on libère la place. */
    if (existant && existant.chemin && existant.chemin !== chemin) {
      await Supabase.supprimerImages([existant.chemin]);
    }
    journaliser("slider", existant ? "modification" : "ajout",
      existant ? "Image du slider modifiée" : "Image ajoutée au slider",
      slide.titre);
    return slideDepuisLigne((lignes && lignes[0]) || slide);
  }

  async function supprimerSlide(id) {
    const slide = await lireSlide(id);
    await Supabase.requete("DELETE", "slides?id=eq." + encodeURIComponent(id));
    if (slide && slide.chemin) await Supabase.supprimerImages([slide.chemin]);
    journaliser("slider", "suppression", "Image retirée du slider", slide ? slide.titre : "");
  }

  /** Monte ou descend une image dans le slider (direction -1 ou +1). */
  async function deplacerSlide(id, direction) {
    const liste = await listerSlides();
    const index = liste.findIndex((s) => s.id === id);
    const voisin = liste[index + direction];
    if (index < 0 || !voisin) return;
    liste.forEach((s, i) => { s.ordre = i + 1; });
    const courant = liste[index];
    const tmp = courant.ordre;
    courant.ordre = voisin.ordre;
    voisin.ordre = tmp;
    for (const s of [courant, voisin]) {
      await Supabase.requete("PATCH", "slides?id=eq." + encodeURIComponent(s.id), { ordre: s.ordre });
    }
    journaliser("slider", "ordre", "Ordre du slider modifié : image en position " + courant.ordre,
      courant.titre);
  }

  /* ---------- Statistiques ---------- */

  async function statistiques() {
    const [categories, produits] = await Promise.all([listerCategories(), listerProduits()]);
    return {
      categories: categories.length,
      produits: produits.length,
      slides: (await listerSlides().catch(() => [])).length,
      enAvant: produits.filter((p) => p.enAvant).length,
      promotions: produits.filter((p) => Utils.remisePourcent(p.ancienPrix, p.prix) !== null).length,
      ruptures: produits.filter((p) => statut(p) === "rupture").length,
      photos: produits.reduce((n, p) => n + (p.images || []).length, 0),
      videos: produits.filter((p) => p.video).length,
    };
  }

  /* ---------- Sauvegarde / restauration ---------- */

  async function telechargerEnBase64(url) {
    const reponse = await fetch(url);
    if (!reponse.ok) throw new Error("Photo inaccessible");
    const blob = await reponse.blob();
    return new Promise((resolve, reject) => {
      const lecteur = new FileReader();
      lecteur.onload = () => resolve(lecteur.result);
      lecteur.onerror = () => reject(new Error("Photo illisible"));
      lecteur.readAsDataURL(blob);
    });
  }

  async function exporter(progression) {
    const dire = progression || (() => {});
    const [categories, produits] = await Promise.all([listerCategories(), listerProduits()]);
    const exportProduits = [];
    let fait = 0;
    for (const p of produits) {
      fait++;
      dire("Récupération des photos… (" + fait + "/" + produits.length + ")");
      const photos = [];
      for (const chemin of p.images || []) {
        try {
          photos.push({ chemin, dataUrl: await telechargerEnBase64(Supabase.urlImage(chemin)) });
        } catch (_) { /* photo manquante : on continue */ }
      }
      exportProduits.push({ ...p, vignette: undefined, photos });
    }
    return {
      application: "impact-admin",
      version: 2,
      exporteLe: new Date().toISOString(),
      boutique: lireReglages(),
      categories,
      produits: exportProduits,
    };
  }

  async function importer(donnees, progression) {
    const dire = progression || (() => {});
    if (!donnees || donnees.application !== "impact-admin" || !Array.isArray(donnees.produits)) {
      throw new Error("Ce fichier n'est pas une sauvegarde de l'application.");
    }

    /* Sauvegardes v1 (ancien format local) : retrouver les photos. */
    const photosV1 = {};
    if (donnees.version === 1 && Array.isArray(donnees.photos)) {
      for (const photo of donnees.photos) {
        (photosV1[photo.produitId] = photosV1[photo.produitId] || []).push(photo);
      }
    }

    dire("Enregistrement des catégories…");
    for (const c of donnees.categories || []) {
      await Supabase.requete("POST", "categories?on_conflict=id",
        { id: c.id, nom: c.nom, ordre: c.ordre || 0 }, { upsert: true });
      for (const s of c.sousCategories || []) {
        await Supabase.requete("POST", "sous_categories?on_conflict=id",
          { id: s.id, categorie_id: c.id, nom: s.nom, ordre: s.ordre || 0 }, { upsert: true });
      }
    }

    let fait = 0;
    for (const p of donnees.produits) {
      fait++;
      dire("Enregistrement des produits… (" + fait + "/" + donnees.produits.length + ")");
      const photos = donnees.version === 1
        ? (photosV1[p.id] || []).map((photo) => ({ chemin: photo.id + ".jpg", dataUrl: photo.dataUrl }))
        : (p.photos || []);
      const chemins = [];
      for (const photo of photos) {
        if (photo.dataUrl) {
          try {
            await Supabase.televerserImage(photo.chemin, photo.dataUrl);
            chemins.push(photo.chemin);
          } catch (_) { /* photo perdue : on garde le produit */ }
        }
      }
      await Supabase.requete("POST", "produits?on_conflict=id", {
        id: p.id,
        nom: p.nom,
        reference: p.reference || "",
        description: p.description || "",
        prix: Number(p.prix) || 0,
        ancien_prix: p.ancienPrix || null,
        categorie_id: p.categorieId,
        sous_categorie_id: p.sousCategorieId || null,
        stock: p.stock === undefined ? (p.disponible === false ? 0 : 1) : p.stock,
        sur_commande: !!p.surCommande,
        disponible: !!p.surCommande ||
          (p.stock === undefined ? p.disponible !== false : p.stock > 0),
        en_avant: !!p.enAvant,
        ordre_avant: p.ordreAvant || 0,
        images: chemins,
        modifie_le: new Date().toISOString(),
      }, { upsert: true });
      /* Le prix d'achat suit le produit, s'il figurait dans la sauvegarde. */
      if (p.prixGrossiste) {
        await sauverPrixAchat(p.id, Math.max(0, Math.round(Number(p.prixGrossiste) || 0)),
          lireTaux(p.tauxMarge));
      }
    }

    const boutique = donnees.boutique || (donnees.reglages ? {
      nomBoutique: donnees.reglages.nomBoutique,
      slogan: donnees.reglages.slogan,
      description: donnees.reglages.description,
      tel: donnees.reglages.tel,
      whatsapp: donnees.reglages.whatsapp,
      indicatif: donnees.reglages.indicatif,
      devise: donnees.reglages.devise,
      adresse: donnees.reglages.adresse,
      horaires: donnees.reglages.horaires,
      facebook: donnees.reglages.facebook,
    } : null);
    if (boutique) await majReglages(boutique);

    return {
      categories: (donnees.categories || []).length,
      produits: donnees.produits.length,
    };
  }

  return {
    MAX_SLIDES, MAX_EN_AVANT, MAX_PHOTOS, MAX_VIDEO_MO, MAX_PHOTOS_BOUTIQUE,
    MAX_TELEPHONES, MAX_ADRESSES, TAUX_MAX, ROLES,
    prixPublic, tauxDepuisPrix, tauxApplique, lireTaux,
    init, lireReglages, majReglages, photosBoutique, sauverPhotosBoutique,
    listerBoutiques, lireBoutique, boutiqueCourante, choisirBoutique,
    sauverBoutique, basculerBoutique, deplacerBoutique, supprimerBoutique,
    journaliser, lireJournal,
    listerComptes, creerCompte, majCompte, supprimerCompte, changerMotDePasseCompte,
    listerCategories, lireCategorie, sauverCategorie, supprimerCategorie, deplacerCategorie,
    listerProduits, lireProduit, produitsDeCategorie, chercherProduits, prochaineReference,
    sauverProduit, supprimerProduit, photosDeProduit,
    listerSlides, sauverSlide, supprimerSlide, deplacerSlide,
    listerEnAvant, basculerEnAvant, deplacerEnAvant, majDisponibilite, statut, STATUTS,
    statistiques, exporter, importer,
  };
})();
