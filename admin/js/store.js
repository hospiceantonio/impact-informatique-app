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

  /* ---------- Ce qui demande l'accord de l'enseigne ----------
     Ce qui représente la boutique auprès des clients : son nom, son
     logo, sa description, son adresse et ses contacts. L'administrateur
     remplit son écran comme avant ; au lieu d'être écrit, le changement
     part en demande, et l'enseigne tranche.

     Le reste lui appartient : slogan, secteur, icône, couleur, horaires,
     devise, marge, photos, vidéo, réseaux — et tout son catalogue.

     Cette liste double celle de la base (« champs_sous_validation ») ;
     c'est la base qui tranche, mais l'écran doit savoir quoi annoncer
     plutôt que de laisser tomber une erreur. */
  const CHAMPS_A_VALIDER = {
    nomBoutique: "nom",          logo: "logo",
    description: "description",  adresse: "adresse",
    latitude: "latitude",        longitude: "longitude",
    tel: "tel",                  whatsapp: "whatsapp",
    indicatif: "indicatif",      telephones: "telephones",
    adresses: "adresses",
  };
  const NOM_DU_CHAMP = {
    nomBoutique: "Nom", logo: "Logo", description: "Description",
    adresse: "Adresse", latitude: "Position", longitude: "Position",
    tel: "Téléphone", whatsapp: "WhatsApp", indicatif: "Indicatif",
    telephones: "Autres numéros", adresses: "Autres adresses",
  };

  /* Les seules tables qu'une annulation peut réécrire. « profils » n'y
     est pas et n'y sera jamais : c'est par elle que passerait une prise
     de pouvoir (voir annulerAction). */
  const TABLES_ANNULABLES = [
    "produits", "produits_prive", "categories", "sous_categories",
    "slides", "boutiques", "boutique",
    /* « profils » est acceptée, mais la base n’en laisse écrire une
       que par un superadministrateur : un modérateur ne peut donc pas
       s’en servir pour tendre un piège à celui qui clique. */
    "profils",
  ];

  const BOUTIQUE_DEFAUT = {
    nomBoutique: "BIZZOO",
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
    video: "",       // vidéo de présentation (facultative)
    telephones: [],  // autres numéros : { libelle, numero, whatsapp }
    adresses: [],    // autres adresses : { libelle, texte, latitude, longitude }
    tauxMarge: 20,   // marge appliquée par défaut au prix grossiste
    /* Ce que paie un revendeur validé. « bizzoo » : prix BIZZOO + N %.
       « public » : prix public − N %. Le taux se raffine ensuite produit
       par produit ; le mode, lui, vaut pour toute la boutique. */
    revendeurMode: "bizzoo",
    tauxRevendeur: 10,
  };

  const TAUX_MAX = 1000;   // au-delà, c'est une faute de frappe

  const MAX_PHOTOS_BOUTIQUE = 6;
  const MAX_TELEPHONES = 8;    // en plus du numéro principal
  const MAX_ADRESSES = 8;      // en plus de l'adresse principale

  let reglages = { ...BOUTIQUE_DEFAUT };
  /* L'enseigne : ses coordonnées à elle, distinctes de celles des boutiques. */
  let enseigne = { ...BOUTIQUE_DEFAUT, nomBoutique: "BIZZOO", slogan: "Toutes vos boutiques" };

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

  /**
   * Ce que paiera un revendeur validé.
   *
   * C'EST UN APERÇU, PAS LA RÈGLE. La règle vit dans la base —
   * « prix_revendeur() » — et c'est elle qui facture. Ceci n'existe que
   * pour montrer le résultat pendant la saisie, sans aller-retour avec
   * le serveur. Les deux doivent donner le même chiffre : si vous
   * touchez à l'une, touchez à l'autre.
   *
   *   'bizzoo'  prix BIZZOO + N %, arrondi aux 5 francs SUPÉRIEURS pour
   *             que la marge ne soit jamais rabotée ;
   *   'public'  prix public − N %, arrondi aux 5 francs INFÉRIEURS pour
   *             que la remise annoncée soit tenue.
   *
   * Puis deux bornes : jamais sous le prix BIZZOO, jamais au-dessus du
   * prix public — et c'est le plafond qui l'emporte quand les deux se
   * contredisent, sur une fin de série soldée sous son prix BIZZOO.
   */
  function prixRevendeur(prixVente, prixGrossiste, taux, mode) {
    const vente = Math.max(0, Math.round(Number(prixVente) || 0));
    const achat = Math.max(0, Math.round(Number(prixGrossiste) || 0));
    /* Sans prix BIZZOO, il n'y a rien à calculer : le prix public. */
    if (!achat) return vente;
    const t = Math.max(0, Math.min(100, Number(taux) || 0));
    const brut = mode === "public" ? vente * (1 - t / 100) : achat * (1 + t / 100);
    const arrondi = mode === "public"
      ? Math.floor(brut / 5) * 5
      : Math.ceil(brut / 5) * 5;
    return Math.min(vente, Math.max(arrondi, achat));
  }

  /** Le chemin inverse : quel taux mène de ce prix grossiste à ce prix public ? */
  function tauxDepuisPrix(prixGrossiste, prix) {
    const achat = Math.max(0, Math.round(Number(prixGrossiste) || 0));
    const vente = Math.max(0, Math.round(Number(prix) || 0));
    if (!achat) return null;
    return Math.round(((vente - achat) / achat) * 10000) / 100;
  }

  /* Les quatre états possibles d'un produit, et ce qu'en voit le client. */
  const STATUTS = {
    disponible: { nom: "Disponible", teinte: "vert" },
    rupture: { nom: "En rupture", teinte: "rouge" },
    commande: { nom: "Sur commande", teinte: "bleu" },
    approvisionnement: { nom: "En approvisionnement", teinte: "or" },
  };

  /* Réassort en route : la date d'arrivée est posée et pas encore
     passée. Le décompte se fait tout seul — au lendemain de la date,
     le produit repasse « En rupture » sans que personne n'y touche. */
  const APPRO_MIN = 1;
  const APPRO_MAX = 8;
  const joursAppro = (p) => (p ? Utils.joursAvant(p.approLe) : null);

  /**
   * Le délai choisi (1 à 8 jours) devient une date d'arrivée. Une date
   * plutôt qu'un nombre de jours : sans cela il faudrait décrémenter
   * chaque produit chaque nuit, et le compte serait faux dès qu'une
   * journée passe sans que l'application s'ouvre.
   */
  function dateApproDans(jours) {
    const n = Math.round(Number(jours) || 0);
    if (n < APPRO_MIN || n > APPRO_MAX) {
      throw new Error("Le délai d'approvisionnement va de " + APPRO_MIN +
        " à " + APPRO_MAX + " jours.");
    }
    return Utils.dateDansXJours(n);
  }
  const enAppro = (p) => {
    const jours = joursAppro(p);
    return jours !== null && jours >= 0;
  };

  /**
   * « disponible » quand il reste des pièces, « rupture » quand il n'en
   * reste plus, « commande » pour un produit vendu sans stock, et
   * « approvisionnement » quand un réassort est annoncé.
   */
  function statut(p) {
    if (!p) return "rupture";
    if (p.surCommande) return "commande";
    if (enAppro(p)) return "approvisionnement";
    return p.stock > 0 ? "disponible" : "rupture";
  }

  /** En vente flash : une date de fin posée, et pas encore passée. */
  const enVenteFlash = (p) => !!(p && p.flashFin && p.flashFin > Date.now());

  /**
   * Place le produit en vente flash jusqu'à `fin` (Date ou ms), ou l'en
   * retire (`fin` à null). La disparition à l'échéance est automatique :
   * le client ignore toute date passée.
   */
  async function majVenteFlash(id, fin) {
    const produit = await lireProduit(id);
    const avant = await ligneBrute("produits", id);
    if (!produit) throw new Error("Produit introuvable.");
    const quand = fin ? new Date(fin) : null;
    if (quand && (isNaN(quand.getTime()) || quand.getTime() <= Date.now())) {
      throw new Error("Choisissez une date de fin à venir.");
    }
    const lignes = await Supabase.requete("PATCH",
      "produits?id=eq." + encodeURIComponent(id),
      { flash_fin: quand ? quand.toISOString() : null, modifie_le: new Date().toISOString() });
    journaliser("produit", "modification",
      quand
        ? "Vente flash : " + produit.nom + " jusqu'au " + Utils.fmtDateHeure(quand.getTime())
        : "Vente flash retirée : " + produit.nom,
      produit.reference || produit.nom,
      aAnnuler("produits", [avant], [id]));
    return produitDepuisLigne((lignes || [])[0] || {});
  }

  /**
   * Le prix d'achat vient d'une table à part, jamais lisible avec la clé
   * publique. PostgREST le rend soit en objet, soit en tableau selon la
   * requête ; absent, le produit n'a simplement pas de prix grossiste.
   */
  function priveDepuisLigne(l) {
    const p = Array.isArray(l.produits_prive) ? l.produits_prive[0] : l.produits_prive;
    if (!p) return { prixGrossiste: 0, tauxMarge: null, tauxRevendeur: null };
    return {
      prixGrossiste: Math.max(0, Math.round(Number(p.prix_grossiste) || 0)),
      tauxMarge: p.taux_marge === null || p.taux_marge === undefined ? null : Number(p.taux_marge),
      /* À null, c'est le taux de la boutique qui s'applique — la même
         règle que « tauxMarge » juste au-dessus. */
      tauxRevendeur: p.taux_revendeur === null || p.taux_revendeur === undefined
        ? null : Number(p.taux_revendeur),
    };
  }

  function produitDepuisLigne(l) {
    const images = Array.isArray(l.images) ? l.images : [];
    const stock = stockDepuisLigne(l);
    const prive = priveDepuisLigne(l);
    return {
      id: l.id,
      nom: l.nom,
      /* Le code vient de la base et n'y retourne jamais : « ligneDepuisProduit »
         ne l'envoie pas. Même transmis, la base l'ignorerait. */
      code: l.code || "",
      reference: l.reference || "",
      description: l.description || "",
      prix: Number(l.prix) || 0,
      prixGrossiste: prive.prixGrossiste,
      tauxMarge: prive.tauxMarge,
      tauxRevendeur: prive.tauxRevendeur,
      ancienPrix: l.ancien_prix === null || l.ancien_prix === undefined ? null : Number(l.ancien_prix),
      categorieId: l.categorie_id,
      sousCategorieId: l.sous_categorie_id || "",
      stock,
      surCommande: !!l.sur_commande,
      approLe: l.appro_le || "",
      /* Fin de la vente flash (ms), ou null. Passée, elle ne compte plus. */
      flashFin: l.flash_fin ? Date.parse(l.flash_fin) || null : null,
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
      appro_le: p.approLe || null,
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
      couleur: l.couleur || "#0B5CF5",
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
      video: l.video || "",
      tauxMarge: l.taux_marge === null || l.taux_marge === undefined
        ? BOUTIQUE_DEFAUT.tauxMarge : Number(l.taux_marge),
      /* Colonnes absentes d'une base pas encore mise à jour : on retombe
         sur les valeurs de départ, qui sont celles que la base pose. */
      revendeurMode: l.revendeur_mode === "public" ? "public" : BOUTIQUE_DEFAUT.revendeurMode,
      tauxRevendeur: l.taux_revendeur === null || l.taux_revendeur === undefined
        ? BOUTIQUE_DEFAUT.tauxRevendeur : Number(l.taux_revendeur),
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
    if (!Supabase.estSuper() && cible.id !== Supabase.boutiqueDuCompte()) {
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
    /* Sans boutique attribuée, seul le superadministrateur circule. */
    if (!Supabase.estSuper() && Supabase.rolesActifs()) return "";
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
      couleur: b.couleur || "#0B5CF5",
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
      video: b.video || "",
      taux_marge: b.tauxMarge === undefined ? 20 : b.tauxMarge,
      revendeur_mode: b.revendeurMode === "public" ? "public" : "bizzoo",
      taux_revendeur: b.tauxRevendeur === undefined
        ? BOUTIQUE_DEFAUT.tauxRevendeur : b.tauxRevendeur,
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

    /* La marge de BIZZOO sur cette boutique. Un champ vide garde celle
       d'avant ; à la création, faute de mieux, celle par défaut. */
    const marge = lireTaux(donnees.tauxMarge);
    const tauxMarge = marge === null
      ? (existante ? existante.tauxMarge : BOUTIQUE_DEFAUT.tauxMarge)
      : marge;

    /* La marge sur les ventes aux revendeurs, de la même façon : un
       champ vide garde celle d'avant, et non zéro — sans quoi une
       modification de l'adresse remettrait la boutique à vendre au prix
       BIZZOO nu, sans que personne ne le demande. */
    const margeRev = lireTaux(donnees.tauxRevendeur);
    const tauxRevendeur = margeRev === null
      ? (existante ? existante.tauxRevendeur : BOUTIQUE_DEFAUT.tauxRevendeur)
      : margeRev;
    const revendeurMode = donnees.revendeurMode === "public" ? "public"
      : donnees.revendeurMode === "bizzoo" ? "bizzoo"
      : (existante ? existante.revendeurMode : BOUTIQUE_DEFAUT.revendeurMode);

    const boutique = {
      ...(existante || { ...BOUTIQUE_DEFAUT, actif: true }),
      ...donnees,
      logo,
      tauxMarge,
      tauxRevendeur,
      revendeurMode,
      nomBoutique: nom,
      id: existante ? existante.id : Utils.uid("bou"),
      ordre: existante ? existante.ordre
        : boutiques.reduce((m, b) => Math.max(m, b.ordre || 0), 0) + 1,
    };

    const ligne = ligneDepuisBoutique(boutique);
    const avant = existante ? await ligneBrute("boutiques", boutique.id) : null;
    if (existante) {
      await Supabase.requete("PATCH", "boutiques?id=eq." + encodeURIComponent(boutique.id), ligne);
      journaliser("boutique", "modification", "Boutique modifiée : " + nom, nom,
        aAnnuler("boutiques", [avant], [boutique.id]));
    } else {
      await Supabase.requete("POST", "boutiques", { id: boutique.id, ...ligne,
        cree_le: new Date().toISOString() });
      journaliser("boutique", "ajout", "Nouvelle boutique : " + nom, nom,
        aAnnuler("boutiques", [], [boutique.id]));
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
    const avant = await ligneBrute("boutiques", id);
    await Supabase.requete("PATCH", "boutiques?id=eq." + encodeURIComponent(id),
      { actif, maj_le: new Date().toISOString() });
    journaliser("boutique", actif ? "activation" : "desactivation",
      (actif ? "Boutique ouverte : " : "Boutique fermée : ") + b.nomBoutique, b.nomBoutique,
      aAnnuler("boutiques", [avant], [id]), id);
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
    journaliser("boutique", "suppression", "Boutique supprimée : " + b.nomBoutique,
      b.nomBoutique, undefined, null);
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

    /* L'enseigne d'abord : c'est elle qui accueille les clients, avant
       même qu'ils aient choisi une boutique. */
    const lignes = await Supabase.requete("GET", "boutique?select=*&id=eq.1");
    if (lignes && lignes.length) enseigne = boutiqueDepuisLigne(lignes[0]);

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
    /* Sans table des boutiques, l'ancienne ligne unique fait les deux. */
    reglages = { ...enseigne };
  }

  /* =====================================================
     L'enseigne

     BIZZOO n'est pas une boutique : c'est ce qui les réunit.
     Elle a donc ses propres coordonnées — nom, slogan, WhatsApp,
     adresse, réseaux… — que le client voit à l'accueil, avant
     d'entrer dans une boutique.
     ===================================================== */

  const lireEnseigne = () => ({ ...enseigne });

  async function majEnseigne(maj, libelleJournal) {
    const propre = { ...maj };
    if (maj.telephones !== undefined) propre.telephones = telephonesDepuisListe(maj.telephones);
    if (maj.adresses !== undefined) propre.adresses = adressesDepuisListe(maj.adresses);
    const avant = await ligneBrute("boutique", 1);
    enseigne = { ...enseigne, ...propre };
    const e = enseigne;
    await Supabase.requete("PATCH", "boutique?id=eq.1", {
      nom: e.nomBoutique,
      slogan: e.slogan,
      description: e.description,
      tel: e.tel,
      whatsapp: e.whatsapp,
      indicatif: e.indicatif,
      devise: e.devise,
      adresse: e.adresse,
      horaires: e.horaires,
      facebook: e.facebook,
      instagram: e.instagram,
      tiktok: e.tiktok,
      youtube: e.youtube,
      snapchat: e.snapchat,
      latitude: e.latitude,
      longitude: e.longitude,
      photos: e.photos || [],
      telephones: e.telephones || [],
      adresses: e.adresses || [],
      video: e.video || "",
      maj_le: new Date().toISOString(),
    });
    if (libelleJournal) {
      journaliser("boutique", "modification", libelleJournal, e.nomBoutique,
        aAnnuler("boutique", [avant], [1]), null);
    }
    return lireEnseigne();
  }

  /* ---------- Comptes de l'équipe (réservé à l'administrateur) ---------- */

  /* Trois rangs, du plus large au plus étroit. Chacun dit ce qu'il
     couvre, pour que le choix se fasse sans deviner. */
  const ROLES = {
    superadministrateur: {
      nom: "Super administrateur",
      aide: "Toute l'enseigne : les boutiques, les réglages BIZZOO et tous les comptes.",
      surToutesLesBoutiques: true,
    },
    administrateur: {
      nom: "Administrateur",
      aide: "Tout sur sa boutique : produits, rayons, slider, réglages et ses modérateurs.",
    },
    moderateur: {
      nom: "Modérateur",
      aide: "Les produits et les rayons de sa boutique, rien d'autre.",
    },
    /* LE LIVREUR N'EST PAS « L'ÉQUIPE » au sens de la base : il porte la
       marchandise, il ne tient rien. Ni catalogue, ni commandes, ni
       chiffres — et aucun montant nulle part. La base le lui refuse ;
       cette description n'est là que pour que celui qui nomme sache ce
       qu'il accorde. */
    livreur: {
      nom: "Livreur",
      aide: "Les courses qu'on lui confie, et rien d'autre : ce qu'il porte, " +
            "à qui et où. Aucun prix ne lui est montré.",
    },
  };

  /** Les rôles qu'un compte a le droit de distribuer. */
  function rolesAttribuables() {
    if (Supabase.estSuper()) {
      return ["superadministrateur", "administrateur", "moderateur", "livreur"];
    }
    /* Un administrateur nomme chez lui : des modérateurs et des livreurs. */
    return Supabase.estAdmin() ? ["moderateur", "livreur"] : [];
  }

  /* ---------- Les livraisons ----------
     Deux côtés qui ne se ressemblent pas : la BOUTIQUE confie une
     course, le LIVREUR la porte. Chacun passe par sa fonction, et la
     base décide — un livreur ne lit pas la table des commandes. */

  /** Les livreurs que cette boutique peut choisir. */
  async function listerLivreurs() {
    const lignes = await Supabase.rpcLecture("livreurs_boutique", {});
    return (lignes || []).map((l) => ({
      id: l.id, email: l.email || "", actif: l.actif !== false,
    }));
  }

  /** Confier la part d'une commande à un livreur — ou la reprendre. */
  async function confierLivraison(commande, boutique, livreur) {
    const combien = await Supabase.rpc("assigner_livreur", {
      commande, boutique, livreur: livreur || null });
    journaliser("commande", "modification",
      livreur ? "Livraison confiée" : "Livraison reprise",
      commande, undefined, boutique);
    return Number(combien) || 0;
  }

  /** Ce que le livreur connecté a à porter. AUCUN montant n'en sort. */
  async function mesLivraisons() {
    const lignes = await Supabase.rpcLecture("mes_livraisons", {});
    return (lignes || []).map((l) => ({
      commandeId: l.commande_id,
      numero: l.numero || "",
      boutiqueId: l.boutique_id || "",
      nomBoutique: l.nom_boutique || "",
      client: {
        nom: l.client_nom || "", tel: l.client_tel || "",
        indicatif: l.client_indicatif || "229",
        adresse: l.client_adresse || "", note: l.note || "",
      },
      etat: l.etat || "preparee",
      articles: Array.isArray(l.articles) ? l.articles : [],
      payeLe: l.paye_le || "",
    }));
  }

  /** « Je l'ai prise » / « Je l'ai remise ». Deux gestes, pas plus. */
  async function avancerLivraison(commande, boutique, vers) {
    const combien = await Supabase.rpc("avancer_livraison",
      { commande, boutique, vers });
    return Number(combien) || 0;
  }

  /** Ce compte est-il sous ma responsabilité ? */
  function gereLeCompte(c) {
    if (!c) return false;
    if (Supabase.estSuper()) return true;
    return Supabase.estAdmin() && c.role === "moderateur" &&
      !!c.boutiqueId && c.boutiqueId === Supabase.boutiqueDuCompte();
  }

  function compteDepuisLigne(l) {
    return {
      id: l.id,
      email: l.email || "",
      role: ROLES[l.role] ? l.role : "moderateur",
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
    if (role !== "superadministrateur" && boutiques.length) {
      attachee = boutiqueRattachee || "";
      if (!attachee) throw new Error("Choisissez la boutique confiée à ce compte.");
      if (!lireBoutique(attachee)) throw new Error("Cette boutique n'existe plus.");
    }
    if (!rolesAttribuables().includes(role)) {
      throw new Error("Vous ne pouvez pas créer un compte de ce rang.");
    }
    if (!Supabase.estSuper() && attachee !== Supabase.boutiqueDuCompte()) {
      throw new Error("Vous ne créez des comptes que pour votre boutique.");
    }

    const cree = await Supabase.creerCompte(adresse, motDePasse);
    const fiche = { id: cree.id, email: adresse, role, actif: true, boutique_id: attachee };
    await Supabase.requete("POST", "profils?on_conflict=id", fiche, { upsert: true });
    const ou = attachee ? " (" + (lireBoutique(attachee) || {}).nomBoutique + ")" : "";
    journaliser("compte", "ajout", ROLES[role].nom + " ajouté : " + adresse + ou, adresse,
      undefined, attachee || null);
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
    const avant = await ligneBrute("profils", id);
    const lignes = await Supabase.requete("PATCH", "profils?id=eq." + encodeURIComponent(id), ligne);
    const c = compteDepuisLigne((lignes || [])[0] || { id, ...ligne });
    const retour = aAnnuler("profils", [avant], [id]);
    if (maj.role) {
      journaliser("compte", "modification",
        c.email + " devient " + ROLES[c.role].nom.toLowerCase(), c.email, retour,
        c.boutiqueId || null);
    } else if (maj.actif !== undefined) {
      journaliser("compte", maj.actif ? "activation" : "desactivation",
        (maj.actif ? "Compte réactivé : " : "Compte désactivé : ") + c.email, c.email, retour,
        c.boutiqueId || null);
    } else if (maj.boutiqueId !== undefined) {
      const nom = (lireBoutique(maj.boutiqueId) || {}).nomBoutique || "toutes les boutiques";
      journaliser("compte", "modification", c.email + " s'occupe de " + nom, c.email, retour,
        c.boutiqueId || null);
    } else if (maj.peutModifier !== undefined) {
      journaliser("compte", "modification",
        (maj.peutModifier
          ? "Autorisé à modifier les produits : "
          : "Ne peut plus modifier les produits : ") + c.email, c.email, retour,
        c.boutiqueId || null);
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
      "Compte supprimé : " + ((compte && compte.email) || id), compte ? compte.email : "",
      undefined, (compte && compte.boutiqueId) || null);
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
      "Mot de passe redéfini : " + ((compte && compte.email) || id), compte ? compte.email : "",
      undefined, (compte && compte.boutiqueId) || null);
  }

  /* ---------- Journal des actions ----------
     Chaque geste du gérant laisse une trace lisible : qui, quoi, quand.
     L'écriture ne bloque jamais l'action elle-même. */

  /* ---------- De quoi annuler une action ----------
     On garde la ligne telle qu'elle était AVANT l'écriture. Annuler,
     c'est la réécrire ; et si elle n'existait pas avant, c'est la
     supprimer. Le même mécanisme sert donc pour un ajout, une
     modification et une suppression, sans code particulier. */

  /** La ligne brute d'une table, colonnes de la base telles quelles. */
  async function ligneBrute(table, id) {
    if (id === undefined || id === null || id === "") return null;
    const lignes = await Supabase.requete("GET",
      table + "?select=*&id=eq." + encodeURIComponent(id), undefined, { avecSession: true })
      .catch(() => null);
    return (lignes && lignes[0]) || null;
  }

  /**
   * Décrit ce qu'il faudra remettre en place.
   * @param table  la table concernée
   * @param avant  les lignes telles qu'elles étaient (celles qui n'existaient pas : rien)
   * @param ids    les lignes touchées par l'action
   */
  function aAnnuler(table, avant, ids) {
    return {
      table,
      avant: (avant || []).filter(Boolean).map((ligne) => ({ table, ligne })),
      ids: (ids || []).filter((id) => id !== undefined && id !== null && id !== "")
        .map((id) => ({ table, id: String(id) })),
    };
  }

  /**
   * Écrit une ligne d'historique.
   *
   * `boutiqueDeLAction` dit de quelle boutique parle la ligne — c'est
   * ce qui décide qui la lira. Sans précision, c'est celle sur
   * laquelle on travaille ; `null` dit « l'enseigne », et la ligne ne
   * se montre alors qu'au superadministrateur. La base rectifie de
   * toute façon : pour qui n'est pas superadministrateur, elle impose
   * sa boutique, quoi qu'on lui envoie.
   */
  function journaliser(famille, action, libelle, cible, retour, boutiqueDeLAction) {
    const ligne = {
      utilisateur: Supabase.utilisateur() || "",
      famille, action, libelle,
      cible: cible || "",
      boutique_id: boutiqueDeLAction === undefined
        ? (boutiqueId || null)
        : (boutiqueDeLAction || null),
      fait_le: new Date().toISOString(),
    };
    /* Une action sans « retour » reste au journal, simplement elle ne
       s'annule pas : une suppression de compte, par exemple. */
    if (retour && retour.ids && retour.ids.length) {
      ligne.cible_table = retour.table || "";
      ligne.retour = { avant: retour.avant || [], ids: retour.ids };
    }
    return Supabase.requete("POST", "journal", ligne, { sansRetour: true })
      .catch(() => { /* le journal ne doit jamais gêner le travail */ });
  }

  /**
   * Remet les choses comme elles étaient avant une action du journal.
   * Réservé au superadministrateur — la base le vérifie aussi, l'écran
   * n'est qu'une politesse.
   */
  async function annulerAction(idJournal) {
    if (!Supabase.estSuper()) {
      throw new Error("Seul un superadministrateur peut annuler une action.");
    }
    const lignes = await Supabase.requete("GET",
      "journal?select=*&id=eq." + encodeURIComponent(idJournal), undefined, { avecSession: true });
    const entree = (lignes || [])[0];
    if (!entree) throw new Error("Action introuvable.");
    if (entree.annule_le) throw new Error("Cette action a déjà été annulée.");
    const retour = entree.retour || {};
    const ids = retour.ids || [];
    if (!ids.length) throw new Error("Cette action ne peut pas être annulée.");

    /* Ce qu'une annulation a le droit de toucher. Le contenu de
       « retour » vient du journal, où TOUTE l'équipe écrit : un
       modérateur pouvait y déposer une fausse ligne au libellé anodin
       dont l'annulation — exécutée avec le compte du
       superadministrateur qui clique — l'aurait nommé
       superadministrateur à son tour. La base porte désormais le même
       garde-fou ; celui-ci évite d'en dépendre seul. */
    const interdite = ids.concat(retour.avant || [])
      .map((x) => (x || {}).table)
      .find((t) => !TABLES_ANNULABLES.includes(t));
    if (interdite !== undefined) {
      throw new Error("Cette action ne peut pas être annulée : elle vise « " +
        (interdite || "une table inconnue") + " ».");
    }

    const avant = retour.avant || [];
    for (const cible of ids) {
      const precedent = avant.find((a) =>
        a.table === cible.table && String(a.ligne && a.ligne.id) === String(cible.id));
      if (precedent) {
        await Supabase.requete("POST", cible.table + "?on_conflict=id", precedent.ligne,
          { upsert: true });
      } else {
        await Supabase.requete("DELETE",
          cible.table + "?id=eq." + encodeURIComponent(cible.id));
      }
    }

    await Supabase.requete("PATCH", "journal?id=eq." + encodeURIComponent(idJournal), {
      annule_le: new Date().toISOString(),
      annule_par: Supabase.utilisateur() || "",
    });
    /* L'annulation est elle-même une action : elle laisse sa trace, mais
       ne s'annule pas — sinon on tournerait en rond. */
    await journaliser(entree.famille || "autre", "annulation",
      "Action annulée : " + (entree.libelle || ""), entree.cible || "",
      undefined, entree.boutique_id || null);
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
      /* Annulable si on a gardé de quoi remettre les lignes en place et
         que personne ne l'a déjà fait. Les actions d'avant cette
         version n'ont rien gardé : elles ne s'annulent pas. */
      annulable: !!(l.retour && (l.retour.ids || []).length) && !l.annule_le &&
        l.action !== "annulation",
      /* Pas de versMs ici : il retombe sur « maintenant » quand la date
         manque, ce qui marquerait toutes les lignes comme annulées. */
      annuleLe: l.annule_le ? Date.parse(l.annule_le) || 0 : 0,
      annulePar: l.annule_par || "",
    }));
  }

  /* ---------- Réglages boutique ---------- */

  const lireReglages = () => ({ ...reglages });

  /* Ce qu'a donné le dernier enregistrement : rien, ou une demande
     envoyée. L'écran s'en sert pour dire ce qui s'est passé. */
  let dernierEnvoi = null;
  const dernierEnvoiValidation = () => (dernierEnvoi ? { ...dernierEnvoi } : null);

  /** Quelques colonnes d'une ligne brute, pour montrer l'avant. */
  function extraireChamps(ligne, colonnes) {
    const sortie = {};
    for (const c of colonnes) sortie[c] = ligne ? ligne[c] : null;
    return sortie;
  }

  /** Sépare ce qui s'écrit tout de suite de ce qui demande un accord. */
  function trierParValidation(maj) {
    const libre = {};
    const aValider = {};
    const noms = [];
    for (const cle of Object.keys(maj)) {
      if (!CHAMPS_A_VALIDER[cle]) { libre[cle] = maj[cle]; continue; }
      /* Une valeur inchangée ne demande rien à personne : sans cela,
         enregistrer les horaires enverrait une demande pour le nom. */
      if (JSON.stringify(maj[cle] ?? null) === JSON.stringify(reglages[cle] ?? null)) continue;
      aValider[CHAMPS_A_VALIDER[cle]] = maj[cle] ?? null;
      const nom = NOM_DU_CHAMP[cle];
      if (nom && !noms.includes(nom)) noms.push(nom);
    }
    return { libre, aValider, noms };
  }

  /** Dépose une demande. La base y met la date, l'auteur et l'état. */
  async function deposerDemande(type, apres, avant, objet, cibleId) {
    const ligne = {
      id: Utils.uid("dem"),
      boutique_id: boutiqueId,
      type,
      objet,
      avant: avant || null,
      apres,
      cible_id: cibleId || null,
    };
    await Supabase.requete("POST", "demandes", ligne, { sansRetour: true });
    journaliser("boutique", "demande", "Demande envoyée à BIZZOO : " + objet,
      reglages.nomBoutique, undefined, boutiqueId);
    dernierEnvoi = { type, objet };
    return ligne;
  }

  /* ---------- Les demandes, vues des deux côtés ---------- */

  function demandeDepuisLigne(l) {
    return {
      id: l.id,
      boutiqueId: l.boutique_id || "",
      nomBoutique: (lireBoutique(l.boutique_id) || {}).nomBoutique || "",
      type: l.type, objet: l.objet || "",
      avant: l.avant || null, apres: l.apres || {},
      cibleId: l.cible_id || "",
      demandePar: l.demande_par || "",
      demandeLe: versMs(l.demande_le),
      etat: l.etat || "en_attente",
      decidePar: l.decide_par || "",
      decideLe: l.decide_le ? Date.parse(l.decide_le) || 0 : 0,
      motif: l.motif || "",
      /* Où le demandeur dit tenir son commerce. La base a déjà écarté ce
         qui n'était pas une position : ici, c'est vrai ou c'est vide. */
      adresse: l.adresse || "",
      latitude: l.latitude === null || l.latitude === undefined ? null : Number(l.latitude),
      longitude: l.longitude === null || l.longitude === undefined ? null : Number(l.longitude),
    };
  }

  /** Les demandes. Sans état précisé, celles qui attendent. */
  async function listerDemandes(etat) {
    const lignes = await Supabase.requete("GET",
      "demandes?select=*&order=demande_le.desc" +
      (etat ? "&etat=eq." + encodeURIComponent(etat) : ""),
      undefined, { avecSession: true });
    return (lignes || []).map(demandeDepuisLigne);
  }

  /* Approuver et refuser passent par la base : elle vérifie qui
     appelle et n'écrit que les colonnes prévues. L'application ne
     touche pas elle-même à la boutique — ce serait rouvrir la porte
     que la validation vient de fermer. */
  async function approuverDemande(id) {
    await Supabase.rpc("approuver_demande", { cible: id });
    await chargerBoutiques();
  }
  const refuserDemande = (id, motif) =>
    Supabase.rpc("refuser_demande", { cible: id, raison: motif || "" });
  const retirerDemande = (id) =>
    Supabase.requete("DELETE", "demandes?id=eq." + encodeURIComponent(id));

  /* ---------- Les comptes revendeurs ----------

     Un revendeur validé achète au PRIX BIZZOO, sur tout le catalogue et
     dans toutes les boutiques. La décision engage l'enseigne entière :
     la base ne la laisse qu'au superadministrateur, et ces fonctions ne
     font que la lui présenter.

     Tout passe par la base. La liste, parce que l'adresse e-mail vit
     dans « auth.users », que personne ne lit directement. La décision,
     parce qu'écrire « validé » depuis un écran rouvrirait la porte que
     la validation vient de fermer. */

  function revendeurDepuisLigne(l) {
    return {
      id: l.id,
      nom: l.nom || "",
      email: l.email || "",
      tel: l.tel || "",
      indicatif: l.indicatif || "229",
      message: l.message || "",
      etat: l.etat || "en_attente",
      demandeLe: versMs(l.demande_le),
      decidePar: l.decide_par || "",
      decideLe: l.decide_le ? Date.parse(l.decide_le) || 0 : 0,
      motif: l.motif || "",
    };
  }

  /** Les demandes de compte revendeur. Sans état précisé, toutes. */
  async function listerRevendeurs(etat) {
    const lignes = await Supabase.rpcLecture("revendeurs", { filtre: etat || "" });
    return (lignes || []).map(revendeurDepuisLigne);
  }

  /* ---------- Les codes promo ----------
     UNE REMISE SORT DE LA MARGE DE L'ENSEIGNE : la boutique touche son
     prix BIZZOO en entier. C'est pour cela que seule l'enseigne pose un
     code — on ne laisse pas quelqu'un d'autre engager sa marge.

     « utilisations » et « coute » se comptent sur les commandes PAYÉES :
     un panier abandonné n'a rien coûté à personne. */

  function codeDepuisLigne(l) {
    return {
      code: l.code || "",
      libelle: l.libelle || "",
      mode: l.mode || "pourcent",
      valeur: Number(l.valeur) || 0,
      minimum: Number(l.minimum) || 0,
      maximum: Number(l.maximum) || 0,
      uneParClient: l.une_par_client !== false,
      fin: l.fin || "",
      actif: l.actif !== false,
      creeLe: l.cree_le || "",
      creePar: l.cree_par || "",
      utilisations: Number(l.utilisations) || 0,
      coute: Number(l.coute) || 0,
    };
  }

  async function listerCodes() {
    const lignes = await Supabase.rpcLecture("codes_promo_liste", {});
    return (lignes || []).map(codeDepuisLigne);
  }

  async function enregistrerCode(c) {
    const cle = await Supabase.rpc("enregistrer_code", {
      brut: c.code || "",
      libelle: c.libelle || "",
      mode: c.mode || "pourcent",
      valeur: Number(c.valeur) || 0,
      minimum: Number(c.minimum) || 0,
      maximum: Number(c.maximum) || 0,
      une_par_client: c.uneParClient !== false,
      fin: c.fin || null,
      actif: c.actif !== false,
    });
    /* Au journal de l'enseigne : un code engage sa marge, on doit
       pouvoir dire qui l'a posé et quand. */
    journaliser("boutique", "modification",
      (c.actif === false ? "Code promo fermé : " : "Code promo posé : ") +
        (c.code || ""),
      "Codes promo", undefined, null);
    return cle;
  }

  /** Ce que les remises ont coûté sur la période, par boutique. */
  async function remisesPeriode({ depuis, jusqu, boutique } = {}) {
    const lignes = await Supabase.rpcLecture("remises_periode", {
      depuis: depuis || null, jusqu: jusqu || null, boutique: boutique || null });
    return (lignes || []).map((l) => ({
      boutiqueId: l.boutique_id || "",
      remise: Number(l.remise) || 0,
    }));
  }

  /* ---------- Le journal des versements ----------
     Une ligne par TENTATIVE, jamais modifiée ensuite : c'est ce qui
     permet de répondre à « combien d'échecs cette semaine » et « chez
     quel opérateur ». La commande, elle, ne garde que son état actuel.

     Réservé à l'enseigne : c'est l'argent de BIZZOO qui transite. */

  /* « entre » : la ligne compte-t-elle dans l'argent réellement entré ?
     « montre » : lequel des deux montants l'écran affiche en gros.

     Les deux ne se confondent pas. Un versement arrivé pour une commande
     introuvable n'entre PAS dans le chiffre d'affaires — mais l'argent,
     lui, est bien arrivé : afficher l'attendu (zéro, puisqu'il n'y a pas
     de commande) donnerait « 0 FCFA » sur la ligne qui mérite le plus
     qu'on la regarde. Même chose pour un conflit. À l'inverse, une
     demande envoyée n'a encore rien reçu : c'est l'attendu qui la décrit. */
  const VERDICTS = {
    payee: { mot: "Encaissé", classe: "badge-ok", entre: true, montre: "recu" },
    ouverte: { mot: "Demande envoyée", classe: "badge-commande", entre: false, montre: "attendu" },
    /* L'incomplet montre l'attendu en gros, et le détail juste en
       dessous dit ce qui manque : voir « 12 000 » seul ferait croire la
       commande réglée. */
    incomplete: { mot: "Incomplet", classe: "badge-rupture", entre: false, montre: "attendu" },
    conflit: { mot: "Conflit", classe: "badge-rupture", entre: false, montre: "recu" },
    refusee: { mot: "Refusé", classe: "badge-annulee", entre: false, montre: "attendu" },
    inconnue: { mot: "Commande introuvable", classe: "badge-rupture", entre: false, montre: "recu" },
  };

  async function journalVersements({ depuis, jusqu, verdict } = {}) {
    const lignes = await Supabase.rpcLecture("versements_liste", {
      depuis: depuis || null, jusqu: jusqu || null, filtre: verdict || "" });
    return (lignes || []).map((l) => ({
      id: Number(l.id) || 0,
      commandeId: l.commande_id || "",
      numero: l.numero || "",
      fournisseur: l.fournisseur || "",
      reseau: l.reseau || "",
      reference: l.reference || "",
      transactionId: l.transaction_id || "",
      attendu: Number(l.attendu) || 0,
      recu: Number(l.recu) || 0,
      verdict: l.verdict || "inconnue",
      detail: l.detail || "",
      creeLe: l.cree_le || "",
    }));
  }

  /* Le résumé compte sur TOUTES les lignes de la période, pas sur les
     trois cents que la liste rend : « ce qui est entré cette semaine »
     ne peut pas dépendre de la longueur d'un écran. */
  async function resumeVersements({ depuis, jusqu } = {}) {
    const lignes = await Supabase.rpcLecture("versements_resume", {
      depuis: depuis || null, jusqu: jusqu || null });
    return (lignes || []).map((l) => ({
      fournisseur: l.fournisseur || "",
      reseau: l.reseau || "",
      verdict: l.verdict || "inconnue",
      combien: Number(l.combien) || 0,
      total: Number(l.total) || 0,
    }));
  }

  /* ---------- Les fiches clients ----------
     Un client appelle pour un litige : il faut le retrouver, et voir ce
     qu'il a commandé. La recherche accepte un nom ou un numéro, avec ou
     sans espaces, avec ou sans indicatif — c'est la base qui les
     rapproche, pas l'écran.

     Réservé à l'enseigne : une boutique voit déjà le nom et le numéro
     sur SES commandes, mais le fichier entier ne la regarde pas. La
     base rend zéro ligne à qui n'y a pas droit. */

  function clientDepuisLigne(l) {
    return {
      id: l.id,
      nom: l.nom || "",
      email: l.email || "",
      tel: l.tel || "",
      indicatif: l.indicatif || "229",
      telVerifie: l.tel_verifie === true,
      adresse: l.adresse || "",
      creeLe: l.cree_le || "",
      typeCompte: l.type_compte || "client",
      revendeurEtat: l.revendeur_etat || "aucune",
      revendeurAdresse: l.revendeur_adresse || "",
      revendeurLatitude: l.revendeur_latitude === null || l.revendeur_latitude === undefined
        ? null : Number(l.revendeur_latitude),
      revendeurLongitude: l.revendeur_longitude === null || l.revendeur_longitude === undefined
        ? null : Number(l.revendeur_longitude),
      commandes: Number(l.commandes) || 0,
      payees: Number(l.payees) || 0,
      totalPaye: Number(l.total_paye) || 0,
      derniere: l.derniere || "",
    };
  }

  async function listerClients(recherche) {
    const lignes = await Supabase.rpcLecture("clients_liste", {
      filtre: recherche || "", cible: null });
    return (lignes || []).map(clientDepuisLigne);
  }

  async function lireClient(id) {
    const lignes = await Supabase.rpcLecture("clients_liste", {
      filtre: "", cible: id });
    return (lignes || []).map(clientDepuisLigne)[0] || null;
  }

  /** Les commandes d'un client, celles de son compte et celles d'avant. */
  async function commandesDuClient(id) {
    const lignes = await Supabase.rpcLecture("client_commandes", { client: id });
    return (lignes || []).map((l) => ({
      id: l.id,
      numero: l.numero || "",
      creeLe: l.cree_le || "",
      payeLe: l.paye_le || "",
      etat: l.etat || "a_payer",
      total: Number(l.total) || 0,
      revendeur: l.revendeur === true,
      articles: Number(l.articles) || 0,
      boutiques: l.boutiques || "",
      /* Faux = la commande date d'avant le compte. La base la reconnaît
         au numéro vérifié ; elle se rattachera au prochain passage du
         client dans « Mes commandes ». */
      rattachee: l.rattachee === true,
    }));
  }

  /* ---------- Le service après-vente ----------

     LA BOUTIQUE D'ABORD, BIZZOO EN RECOURS. La boutique répond à ce
     qui la concerne ; elle ne CLÔT pas — c'est le client qui dit que
     son problème est réglé, ou l'enseigne qui tranche. Une boutique
     capable de fermer une réclamation fermerait toutes celles qui la
     gênent, et le SAV ne serait plus qu'un formulaire.

     L'enseigne, elle, voit tout : c'est elle le recours. Mais elle ne
     tranche que ce qui lui a été REMONTÉ — retirer un dossier des
     mains d'une boutique sans qu'on le lui demande n'est pas un
     recours, c'est une mise sous tutelle. La base le vérifie. */

  const SUJETS_SAV = {
    non_recu: "Rien reçu",
    abime: "Article abîmé",
    pas_conforme: "Pas conforme",
    incomplet: "Commande incomplète",
    autre: "Autre problème",
  };

  function reclamationDepuisLigne(l) {
    return {
      id: l.id,
      commandeId: l.commande_id || "",
      boutiqueId: l.boutique_id || "",
      nomBoutique: (lireBoutique(l.boutique_id) || {}).nomBoutique || "",
      produitId: l.produit_id || "",
      sujet: l.sujet || "autre",
      etat: l.etat || "ouverte",
      escaladeLe: l.escalade_le ? Date.parse(l.escalade_le) || 0 : 0,
      escaladeMotif: l.escalade_motif || "",
      decision: l.decision || "",
      decidePar: l.decide_par || "",
      reponduLe: l.repondu_le ? Date.parse(l.repondu_le) || 0 : 0,
      creeLe: versMs(l.cree_le),
      majLe: versMs(l.maj_le),
    };
  }

  /** Les réclamations visibles : celles de sa boutique, ou toutes. */
  async function listerReclamations(combien) {
    const lignes = await Supabase.requete("GET",
      "reclamations?select=*&order=cree_le.desc&limit=" + (Number(combien) || 100),
      undefined, { avecSession: true });
    return (lignes || []).map(reclamationDepuisLigne);
  }

  /** Le fil : ce qui a été dit, dans l'ordre. */
  async function messagesReclamation(id) {
    const lignes = await Supabase.requete("GET",
      "reclamation_messages?select=id,auteur_role,auteur_nom,texte,cree_le" +
      "&reclamation_id=eq." + encodeURIComponent(id) + "&order=cree_le.asc",
      undefined, { avecSession: true });
    return (lignes || []).map((m) => ({
      id: m.id, role: m.auteur_role || "client", nom: m.auteur_nom || "",
      texte: m.texte || "", quand: versMs(m.cree_le),
    }));
  }

  async function repondreReclamation(id, texte) {
    await Supabase.rpcLecture("repondre_reclamation", { cible: id, message: texte || "" });
    journaliser("boutique", "sav", "Réponse à une réclamation client", id);
  }

  /** Trancher un recours. Réservé à l'enseigne — la base le vérifie. */
  async function trancherReclamation(id, verdict) {
    await Supabase.rpcLecture("trancher_reclamation", { cible: id, verdict: verdict || "" });
    journaliser("boutique", "sav", "Recours tranché : " + (verdict || ""), id, undefined, null);
  }

  /* ---------- Les avis des clients ----------

     La boutique RÉPOND, elle n'efface pas. C'est la règle qui donne sa
     valeur à tout le reste : une boutique qui peut faire disparaître ce
     qui la gêne rend ses bons avis suspects par la même occasion.

     Masquer existe, mais pour ce qui n'a pas sa place — insultes,
     numéro de téléphone, règlement de comptes — et c'est l'enseigne
     seule qui en décide. La base le vérifie ; cet écran ne fait que ne
     pas proposer le bouton. */

  function avisDepuisLigne(l) {
    return {
      id: l.id,
      produitId: l.produit_id || "",
      /* Le nom du produit ne vient PAS d'ici : « lireProduit » va le
         chercher en base, et cette fonction-ci doit rester synchrone.
         L'écran l'affiche à partir de la liste qu'il a déjà — un avis
         sans produit est un avis sur la boutique, et c'est tout ce qu'il
         faut savoir pour le ranger. */
      boutiqueId: l.boutique_id || "",
      nomBoutique: (lireBoutique(l.boutique_id) || {}).nomBoutique || "",
      note: Number(l.note) || 0,
      texte: l.texte || "",
      auteur: l.auteur || "",
      reponse: l.reponse || "",
      reponseLe: l.reponse_le ? Date.parse(l.reponse_le) || 0 : 0,
      masque: !!l.masque,
      motifMasque: l.motif_masque || "",
      creeLe: versMs(l.cree_le),
    };
  }

  /** Les avis visibles par ce compte : les siens, ou tous pour l'enseigne. */
  async function listerAvis(combien) {
    const lignes = await Supabase.requete("GET",
      "avis?select=*&order=cree_le.desc&limit=" + (Number(combien) || 100),
      undefined, { avecSession: true });
    return (lignes || []).map(avisDepuisLigne);
  }

  /** Répondre — ou effacer sa réponse, en envoyant un texte vide. */
  async function repondreAvis(id, texte) {
    await Supabase.rpcLecture("repondre_avis", { cible: id, texte: texte || "" });
    journaliser("boutique", "reponse", "Réponse publiée sur un avis client", id);
  }

  /** Masquer, ou rendre. Réservé à l'enseigne — la base le vérifie. */
  async function masquerAvis(id, cacher, motif) {
    await Supabase.rpcLecture("masquer_avis",
      { cible: id, cacher: !!cacher, raison: motif || "" });
    journaliser("boutique", cacher ? "masquage" : "demasquage",
      (cacher ? "Avis masqué" : "Avis rendu public") + (motif ? " : " + motif : ""),
      id, undefined, null);
  }

  /** Valider, ou refuser avec un motif que le demandeur lira. */
  async function deciderRevendeur(compte, accord, motif) {
    await Supabase.rpcLecture("valider_revendeur",
      { cible: compte.id, accord: !!accord, raison: motif || "" });
    /* Au journal de l'enseigne, pas à celui d'une boutique : la remise
       vaut partout. */
    journaliser("compte", accord ? "validation" : "refus",
      (accord ? "Compte revendeur validé" : "Compte revendeur refusé") +
      (motif ? " : " + motif : ""),
      compte.email || compte.nom || compte.id, undefined, null);
  }

  /* =====================================================
     Les commandes des clients

     Un client remplit son panier dans l'application BIZZOO,
     paie par Mobile Money, et sa commande arrive ici. Elle se
     répartit entre les boutiques concernées : chacune ne voit
     que SES lignes — c'est la base qui le décide, pas cet
     écran.

     Rien de ce qui touche à l'argent ne s'écrit d'ici : ni le
     prix, ni le total, ni « payée ». La boutique fait avancer
     ses lignes — vue, préparée, remise —, c'est tout.
     ===================================================== */

  const ETATS_LIGNE = {
    nouvelle: { nom: "Nouvelle", classe: "badge-nouvelle", suivant: "Marquer vue" },
    vue: { nom: "Vue", classe: "badge-commande", suivant: "Marquer préparée" },
    preparee: { nom: "Préparée", classe: "badge-approvisionnement",
                suivant: "Marquer en livraison" },
    /* L'étape qui manquait : entre le comptoir et le client, la
       marchandise est QUELQUE PART. Sans elle, rien ne distinguait une
       commande prête à partir d'une commande déjà partie — et personne
       ne pouvait répondre à « où en est ma commande ? ». */
    en_livraison: { nom: "En livraison", classe: "badge-commande",
                    suivant: "Marquer remise" },
    remise: { nom: "Remise au client", classe: "badge-ok", suivant: "" },
    annulee: { nom: "Annulée", classe: "badge-annulee", suivant: "" },
  };
  /** Ce qui vient après, quand la boutique fait avancer une ligne. */
  const SUITE_LIGNE = {
    nouvelle: "vue", vue: "preparee",
    preparee: "en_livraison", en_livraison: "remise",
  };

  function commandeDepuisLigne(l) {
    const lignes = (l.commande_lignes || []).map((x) => ({
      id: x.id,
      boutiqueId: x.boutique_id || "",
      nomBoutique: (lireBoutique(x.boutique_id) || {}).nomBoutique || "",
      produitId: x.produit_id || "",
      nom: x.nom || "", code: x.code || "", reference: x.reference || "",
      prix: Number(x.prix) || 0,
      quantite: Number(x.quantite) || 1,
      etat: x.etat || "nouvelle",
      /* Quand le CLIENT a confirmé avoir reçu. Vide tant qu'il ne l'a
         pas dit — et la boutique ne peut pas le poser elle-même : la
         base le lui refuse. C'est ce qui donne du poids à sa propre
         déclaration « remise ». */
      confirmeLe: x.confirme_le || "",
    }));
    return {
      id: l.id,
      numero: l.numero || "",
      client: {
        nom: l.client_nom || "", tel: l.client_tel || "",
        indicatif: l.client_indicatif || "229",
        adresse: l.client_adresse || "",
      },
      note: l.note || "",
      /* Le total de la commande entière ; « montant » ne compte que ce
         qui revient à la boutique qui regarde. */
      total: Number(l.total) || 0,
      montant: lignes.reduce((somme, x) => somme + x.prix * x.quantite, 0),
      devise: l.devise || "FCFA",
      etat: l.etat || "a_payer",
      /* Partie au prix revendeur ? La boutique touche la même chose
         qu'à l'ordinaire — c'est BIZZOO qui laisse sa marge. Mais un
         montant deux fois plus bas que d'habitude s'explique mieux
         écrit que deviné. */
      revendeur: !!l.revendeur,
      /* Ce que KkiaPay a PROUVÉ, et ce que le téléphone du client a
         seulement AFFIRMÉ : deux choses différentes, deux colonnes. */
      transactionId: l.transaction_id || "",
      transactionAnnoncee: l.transaction_annoncee || "",
      confirmePar: l.confirme_par || "",
      remarque: l.remarque || "",
      annonceLe: l.annonce_le ? Date.parse(l.annonce_le) || 0 : 0,
      payeLe: l.paye_le ? Date.parse(l.paye_le) || 0 : 0,
      creeLe: versMs(l.cree_le),
      lignes,
    };
  }

  /**
   * Les commandes qui concernent le compte. La base ne renvoie que les
   * lignes de sa boutique : une commande partagée avec une autre
   * boutique arrive donc amputée de ce qui ne le regarde pas — c'est
   * voulu.
   *
   * `options.etat` : « payee » pour ne voir que ce qui est réglé.
   */
  async function listerCommandes(options) {
    const o = options || {};
    /* Les colonnes sont NOMMÉES, pas prises en bloc. La base ne laisse
       plus « commande_lignes(*) » à un compte connecté : le prix d'achat
       de la boutique et la marge de l'enseigne y vivent, et un acheteur
       connecté lit ses propres lignes depuis que les comptes clients
       existent. Ces deux chiffres-là arrivent par
       « statistiques_ventes() », qui vérifie qui appelle. */
    let chemin = "commandes?select=*,commande_lignes(" +
      "id,boutique_id,produit_id,nom,code,reference,prix,quantite,etat,confirme_le" +
      ")&order=cree_le.desc" +
      "&limit=" + (o.combien || 100);
    if (o.etat) chemin += "&etat=eq." + encodeURIComponent(o.etat);
    const lignes = await Supabase.requete("GET", chemin, undefined, { avecSession: true });
    return (lignes || [])
      .map(commandeDepuisLigne)
      /* Une commande dont la base n'a renvoyé aucune ligne ne parle pas
         de cette boutique : elle n'a rien à faire à l'écran. */
      .filter((c) => c.lignes.length);
  }

  /** Combien de lignes payées attendent encore d'être préparées. */
  async function commandesEnAttente() {
    const lignes = await Supabase.requete("GET",
      "commandes?select=id,etat,commande_lignes(etat)&etat=eq.payee&limit=200",
      undefined, { avecSession: true });
    let combien = 0;
    for (const c of lignes || []) {
      if ((c.commande_lignes || []).some((l) => l.etat === "nouvelle" || l.etat === "vue")) {
        combien++;
      }
    }
    return combien;
  }

  /** Faire avancer une ligne. Seul son état bouge : la base y veille. */
  async function avancerLigne(ligneId, etat) {
    await Supabase.requete("PATCH",
      "commande_lignes?id=eq." + encodeURIComponent(ligneId), { etat });
    return etat;
  }

  /**
   * Se porter garant d'un paiement que KkiaPay n'a pas confirmé. C'est
   * le filet quand la notification se perd : le superadministrateur
   * vérifie dans son tableau de bord KkiaPay, puis signe — et la
   * commande garde la trace de qui a signé.
   */
  async function confirmerPaiement(id) {
    await Supabase.rpc("confirmer_paiement", { cible: id });
    journaliser("commande", "modification",
      "Paiement confirmé à la main", id, undefined, null);
  }

  /* ---------- Le paiement en ligne ----------
     La clé publique de KkiaPay vit en base, pas dans le code : on passe
     des essais à la production sans reconstruire les applications.
     Chez KkiaPay, bac à sable et production sont deux mondes séparés —
     clés différentes, webhooks différents. Les trois interrupteurs se
     poussent ensemble. */

  async function lirePaiement() {
    const lignes = await Supabase.requete("GET", "paiement?select=*&id=eq.1");
    const l = (lignes || [])[0] || {};
    return {
      actif: l.actif === true,
      /* Base d'avant les deux agrégateurs : c'était KkiaPay. */
      fournisseur: l.fournisseur || "kkiapay",
      clePublique: l.cle_publique || "",
      bacASable: l.bac_a_sable !== false,
    };
  }

  async function majPaiement(maj) {
    const fournisseur = maj.fournisseur === "kkiapay" ? "kkiapay" : "feexpay";
    await Supabase.requete("PATCH", "paiement?id=eq.1", {
      actif: !!maj.actif,
      fournisseur,
      cle_publique: (maj.clePublique || "").trim(),
      bac_a_sable: !!maj.bacASable,
      maj_le: new Date().toISOString(),
    });
    /* Changer d'agrégateur engage l'argent de toute l'enseigne : le
       journal doit dire LEQUEL, pas seulement « modifié ». */
    const nom = fournisseur === "feexpay" ? "FeexPay" : "KkiaPay";
    journaliser("boutique", "modification",
      "Paiement en ligne " + (maj.actif ? "ouvert" : "fermé") + " — " + nom +
      (fournisseur === "kkiapay" && maj.bacASable ? " (mode essai)" : ""),
      nom, undefined, null);
  }

  /* ---------- La règle de la maison ----------
     Une seule pour l'instant : faut-il un compte pour commander ? Elle
     vaut pour toutes les boutiques de BIZZOO, et la base ne laisse que
     le superadministrateur y toucher. L'écran cache l'interrupteur aux
     autres ; c'est la règle de la base qui ferme vraiment la porte.

     Une base d'avant cette règle ne répond rien : on lit « éteint », ce
     qui est exactement l'état d'avant. */

  async function lireRegles() {
    const lignes = await Supabase.requete(
      "GET", "reglages?select=compte_obligatoire,maj_le&id=eq.1");
    const l = (lignes || [])[0] || {};
    return {
      compteObligatoire: l.compte_obligatoire === true,
      majLe: l.maj_le || "",
    };
  }

  async function majRegles(maj) {
    await Supabase.requete("PATCH", "reglages?id=eq.1", {
      compte_obligatoire: !!maj.compteObligatoire,
      maj_le: new Date().toISOString(),
    });
    /* Fermer la caisse à qui n'a pas de compte se voit tout de suite
       dans les ventes : le journal doit dire quand on l'a décidé. */
    journaliser("boutique", "modification",
      maj.compteObligatoire
        ? "Un compte est désormais exigé pour commander"
        : "La commande sans compte est de nouveau permise",
      "Règles de la maison", undefined, null);
  }

  /* ---------- Ce que chaque boutique rapporte ----------
     Les ventes réellement encaissées, produit par produit, avec le prix
     BIZZOO et la marge FIGÉS le jour de la vente. C'est la base qui
     refuse ces chiffres à qui n'est pas l'enseigne — l'écran ne fait
     que ne pas les demander. */

  async function statistiquesVentes({ depuis, jusqu, boutique } = {}) {
    const lignes = await Supabase.rpcLecture("statistiques_ventes", {
      depuis: depuis || null,
      jusqu: jusqu || null,
      boutique: boutique || null,
    });
    return (lignes || []).map((l) => ({
      boutiqueId: l.boutique_id || "",
      nomBoutique: l.nom_boutique || "",
      produitId: l.produit_id || "",
      code: l.code || "",
      nom: l.nom || "",
      quantite: Number(l.quantite) || 0,
      prixBizzoo: Number(l.prix_bizzoo) || 0,
      prixVente: Number(l.prix_vente) || 0,
      tauxMarge: l.taux_marge === null || l.taux_marge === undefined
        ? null : Number(l.taux_marge),
      totalBizzoo: Number(l.total_bizzoo) || 0,
      totalVente: Number(l.total_vente) || 0,
      benefice: Number(l.benefice) || 0,
    }));
  }

  /* ---------- Ce que MA boutique a vendu ----------
     Une seconde fonction en base, volontairement plus pauvre : ce que la
     boutique a vendu et ce qui lui revient. Pas le prix payé par le
     client, pas la marge, pas le bénéfice de l'enseigne — ces colonnes
     ne sont pas masquées ici, elles ne sortent pas de la base.

     Et pas de paramètre « boutique » non plus : la base prend toujours
     celle du compte connecté. On ne peut donc pas viser la voisine, même
     en modifiant l'application. */

  async function statistiquesBoutique({ depuis, jusqu } = {}) {
    const lignes = await Supabase.rpcLecture("statistiques_boutique", {
      depuis: depuis || null,
      jusqu: jusqu || null,
    });
    return (lignes || []).map((l) => ({
      produitId: l.produit_id || "",
      code: l.code || "",
      nom: l.nom || "",
      quantite: Number(l.quantite) || 0,
      nbVentes: Number(l.nb_ventes) || 0,
      prixBizzoo: Number(l.prix_bizzoo) || 0,
      totalBizzoo: Number(l.total_bizzoo) || 0,
    }));
  }

  /** Le filtre « seulement ma boutique », ajouté à chaque lecture. */
  const filtreBoutique = () =>
    (boutiqueId ? "boutique_id=eq." + encodeURIComponent(boutiqueId) : "");

  async function majReglages(maj, libelleJournal) {
    /* Depuis les boutiques multiples, les réglages sont ceux de la
       boutique ouverte : on écrit dans sa ligne à elle. */
    if (boutiqueId) {
      dernierEnvoi = null;
      let propre = { ...maj };
      if (maj.telephones !== undefined) propre.telephones = telephonesDepuisListe(maj.telephones);
      if (maj.adresses !== undefined) propre.adresses = adressesDepuisListe(maj.adresses);
      if (maj.tauxMarge !== undefined) {
        const taux = lireTaux(maj.tauxMarge);
        if (taux === null) throw new Error("Le taux doit être un nombre entre 0 et " + TAUX_MAX + " %.");
        propre.tauxMarge = taux;
      }
      /* La marge revendeur appartient à l'enseigne, comme la marge
         ordinaire : le verrou « boutique_verrous » refuse les deux à
         qui n'est pas superadministrateur. On ne les envoie donc que
         dans ce cas, pour éviter un refus que l'administrateur d'une
         boutique ne comprendrait pas. */
      if (maj.tauxRevendeur !== undefined && Supabase.estSuper()) {
        const taux = lireTaux(maj.tauxRevendeur);
        if (taux === null) throw new Error("Le taux revendeur doit être un nombre entre 0 et " + TAUX_MAX + " %.");
        propre.tauxRevendeur = taux;
      } else {
        delete propre.tauxRevendeur;
      }
      if (maj.revendeurMode !== undefined && Supabase.estSuper()) {
        propre.revendeurMode = maj.revendeurMode === "public" ? "public" : "bizzoo";
      } else {
        delete propre.revendeurMode;
      }

      /* Un logo neuf part d'abord au stockage : ce qui circule ensuite —
         et ce qui part en demande — n'est qu'un chemin, pas une image. */
      if (propre.logo && propre.logo.dataUrl) {
        const chemin = "boutiques/" + Utils.uid("bou") + ".jpg";
        await Supabase.televerserImage(chemin, propre.logo.dataUrl);
        propre.logo = chemin;
      } else if (propre.logo === null) {
        propre.logo = "";
      } else if (propre.logo && propre.logo.chemin !== undefined) {
        propre.logo = propre.logo.chemin || "";
      }

      const avant = await ligneBrute("boutiques", boutiqueId);

      /* Nom, logo, description, adresse, contacts : l'enseigne tranche.
         Le reste s'écrit tout de suite. La base refuserait l'écriture
         de toute façon — ici on choisit simplement le bon chemin, et on
         évite à l'administrateur une erreur qu'il ne comprendrait pas. */
      let envoiValidation = null;
      if (!Supabase.estSuper()) {
        const tri = trierParValidation(propre);
        if (tri.noms.length) {
          envoiValidation = await deposerDemande(
            "reglages", tri.aValider,
            avant ? extraireChamps(avant, Object.keys(tri.aValider)) : null,
            tri.noms.join(", "));
        }
        propre = tri.libre;
      }

      reglages = { ...reglages, ...propre };
      /* Ni « actif » ni « ordre » : ouvrir, fermer ou déplacer une
         boutique appartient à l’enseigne, et la base le refuserait à
         son administrateur. Les renvoyer tels quels risquait en outre
         d’écraser une valeur changée entre-temps. */
      const aEcrire = ligneDepuisBoutique(reglages);
      delete aEcrire.actif;
      delete aEcrire.ordre;
      /* Ce qui attend un accord ne s'écrit pas : la boutique garde son
         ancienne valeur jusqu'à la décision. */
      if (envoiValidation) {
        for (const colonne of Object.keys(envoiValidation.apres)) delete aEcrire[colonne];
      }
      if (Object.keys(aEcrire).length) {
        await Supabase.requete("PATCH", "boutiques?id=eq." + encodeURIComponent(boutiqueId),
          aEcrire);
        const index = boutiques.findIndex((b) => b.id === boutiqueId);
        if (index >= 0) boutiques[index] = { ...reglages };
        if (libelleJournal) {
          journaliser("boutique", "modification", libelleJournal, reglages.nomBoutique,
            aAnnuler("boutiques", [avant], [boutiqueId]));
        }
      }
      return lireReglages();
    }
    return majReglagesUnique(maj, libelleJournal);
  }

  /** Ancienne base, boutique unique : on écrit dans la ligne « boutique ». */
  async function majReglagesUnique(maj, libelleJournal) {
    const propre = { ...maj };
    if (maj.telephones !== undefined) propre.telephones = telephonesDepuisListe(maj.telephones);
    if (maj.adresses !== undefined) propre.adresses = adressesDepuisListe(maj.adresses);
    /* La marge n'entre plus par les réglages d'une boutique : elle
       appartient à l'enseigne, qui la pose en créant la boutique. La
       base refuserait de toute façon. */
    if (maj.tauxMarge !== undefined && Supabase.estSuper()) {
      const taux = lireTaux(maj.tauxMarge);
      if (taux === null) throw new Error("Le taux doit être un nombre entre 0 et " + TAUX_MAX + " %.");
      propre.tauxMarge = taux;
    }
    const avant = await ligneBrute("boutique", 1);
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
      video: r.video || "",
      taux_marge: r.tauxMarge,
      maj_le: new Date().toISOString(),
    });
    if (libelleJournal) {
      journaliser("boutique", "modification", libelleJournal, r.nomBoutique,
        aAnnuler("boutique", [avant], [1]));
    }
    return lireReglages();
  }

  /** URL publiques des photos de la boutique, pour l'aperçu. */
  /* Photos et vidéo se règlent de la même façon pour l'enseigne et pour
     une boutique : seule change la ligne où l'on écrit. */
  const sourceReglages = (cible) => (cible === "enseigne" ? enseigne : reglages);
  const ecrireReglages = (cible, maj, libelle) =>
    (cible === "enseigne" ? majEnseigne(maj, libelle) : majReglages(maj, libelle));

  function photosBoutique(cible) {
    return (sourceReglages(cible).photos || []).map((chemin) => ({
      id: chemin.replace(/^boutique\//, "").replace(/\.jpg$/i, ""),
      chemin,
      apercu: Supabase.urlImage(chemin),
    }));
  }

  /**
   * Enregistre les photos de l'enseigne ou d'une boutique.
   * `photosFinales` : [{ id, chemin? (en ligne), dataUrl? (nouvelle) }]
   */
  async function sauverPhotosBoutique(photosFinales, cible) {
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
    const retirees = (sourceReglages(cible).photos || []).filter((chemin) => !chemins.includes(chemin));
    await Supabase.supprimerImages(retirees);
    return ecrireReglages(cible, { photos: chemins },
      "Photos mises à jour (" + chemins.length + " photo" + (chemins.length > 1 ? "s" : "") + ")");
  }

  /** L'URL de la vidéo de présentation, pour l'aperçu dans l'admin. */
  function videoBoutique(cible) {
    const chemin = sourceReglages(cible).video || "";
    return chemin ? { chemin, url: Supabase.urlImage(chemin) } : null;
  }

  /**
   * Enregistre la vidéo de présentation. `video` vaut { chemin } pour
   * garder celle en ligne, { fichier } pour une nouvelle, null pour la
   * retirer.
   */
  async function sauverVideoBoutique(video, cible) {
    const actuelle = sourceReglages(cible).video || "";
    let chemin = "";
    if (video && video.chemin) {
      chemin = video.chemin;
    } else if (video && video.fichier) {
      const octets = video.fichier.size || 0;
      if (octets > MAX_VIDEO_MO * 1024 * 1024) {
        throw new Error("Vidéo trop lourde (" + Utils.tailleLisible(octets) + "). " +
          "Filmez une présentation plus courte : " + MAX_VIDEO_MO + " Mo au maximum.");
      }
      const extension = (video.fichier.name || "").match(/\.([a-z0-9]{2,4})$/i);
      /* Dans « boutique/ » : ce dossier est réservé à l'administrateur. */
      chemin = "boutique/" + Utils.uid("vid") + (extension ? "." + extension[1].toLowerCase() : ".mp4");
      await Supabase.televerserVideo(chemin, video.fichier);
    }
    if (actuelle && actuelle !== chemin) await Supabase.supprimerImages([actuelle]);
    return ecrireReglages(cible, { video: chemin },
      chemin ? "Vidéo de présentation mise à jour" : "Vidéo de présentation retirée");
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

    /* Un rayon, ce sont deux tables : la catégorie et ses
       sous-catégories. On garde les deux pour pouvoir revenir dessus. */
    const avantCategorie = existante ? await ligneBrute("categories", id) : null;
    const avantSous = existante
      ? await Supabase.requete("GET",
          "sous_categories?select=*&categorie_id=eq." + encodeURIComponent(id),
          undefined, { avecSession: true }).catch(() => [])
      : [];

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

    /* Les sous-catégories d'après, pour que l'annulation efface celles
       qui viennent d'être créées. */
    const apresSous = await Supabase.requete("GET",
      "sous_categories?select=id&categorie_id=eq." + encodeURIComponent(id),
      undefined, { avecSession: true }).catch(() => []);
    const retour = aAnnuler("categories", [avantCategorie], [id]);
    for (const ligne of avantSous || []) retour.avant.push({ table: "sous_categories", ligne });
    const idsSous = new Set([
      ...(avantSous || []).map((x) => x.id),
      ...(apresSous || []).map((x) => x.id),
    ]);
    for (const sousId of idsSous) retour.ids.push({ table: "sous_categories", id: String(sousId) });

    journaliser("categorie", existante ? "modification" : "ajout",
      (existante ? "Catégorie modifiée : " : "Nouvelle catégorie : ") + nom +
      " (" + voulues.length + " sous-catégorie" + (voulues.length > 1 ? "s" : "") + ")", nom,
      retour);
    return lireCategorie(id);
  }

  async function supprimerCategorie(id) {
    const produits = await produitsDeCategorie(id);
    if (produits.length) {
      throw new Error("Impossible : " + produits.length + " produit" + (produits.length > 1 ? "s" : "") +
        " se trouve" + (produits.length > 1 ? "nt" : "") + " dans cette catégorie. Déplacez-les d'abord.");
    }
    const categorie = await lireCategorie(id);
    /* La suppression emporte les sous-catégories : on les garde aussi,
       sinon annuler rendrait un rayon vide. */
    const avantCategorie = await ligneBrute("categories", id);
    const avantSous = await Supabase.requete("GET",
      "sous_categories?select=*&categorie_id=eq." + encodeURIComponent(id),
      undefined, { avecSession: true }).catch(() => []);
    await Supabase.requete("DELETE", "categories?id=eq." + encodeURIComponent(id));
    const retour = aAnnuler("categories", [avantCategorie], [id]);
    for (const ligne of avantSous || []) {
      retour.avant.push({ table: "sous_categories", ligne });
      retour.ids.push({ table: "sous_categories", id: String(ligne.id) });
    }
    journaliser("categorie", "suppression",
      "Catégorie supprimée : " + (categorie ? categorie.nom : id), categorie ? categorie.nom : "",
      retour);
  }

  /** Échange l'ordre avec la catégorie voisine (direction -1 ou +1). */
  async function deplacerCategorie(id, direction) {
    const categories = await listerCategories();
    const index = categories.findIndex((c) => c.id === id);
    const voisin = categories[index + direction];
    if (index < 0 || !voisin) return;
    const courant = categories[index];
    const avant = [await ligneBrute("categories", courant.id), await ligneBrute("categories", voisin.id)];
    await Supabase.requete("PATCH", "categories?id=eq." + encodeURIComponent(courant.id), { ordre: voisin.ordre });
    await Supabase.requete("PATCH", "categories?id=eq." + encodeURIComponent(voisin.id), { ordre: courant.ordre });
    journaliser("categorie", "ordre", "Ordre des catégories modifié : " + courant.nom, courant.nom,
      aAnnuler("categories", avant, [courant.id, voisin.id]));
  }

  /* ---------- Produits ---------- */

  /**
   * Les produits, prix d'achat compris. La lecture porte le jeton du
   * compte : la table des prix d'achat est fermée à la clé publique.
   * Sur une base pas encore mise à jour, elle n'existe pas — on la
   * laisse alors de côté plutôt que de bloquer tout le catalogue.
   */
  async function lignesProduits(suite, toutesBoutiques) {
    /* Le slider de l'enseigne peut renvoyer vers n'importe quel produit :
       il ne dépend d'aucune boutique. */
    const morceaux = [suite, toutesBoutiques ? "" : filtreBoutique()].filter(Boolean);
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

  async function listerProduits(options) {
    const lignes = await lignesProduits("order=modifie_le.desc",
      options && options.toutesBoutiques);
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
      const texte = Utils.sansAccent(p.nom + " " + (p.code || "") + " " +
        (p.reference || "") + " " + (p.description || ""));
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

    /* Le prix de vente NE SE SAISIT PAS : il découle du prix BIZZOO et
       de la marge de l'enseigne. Accepter un prix envoyé par l'écran
       rendrait les comptes de l'enseigne faux — le bénéfice ne serait
       plus la marge annoncée. */
    const prixGrossiste = Math.max(0, Math.round(Utils.lireNombre(donnees.prixGrossiste) || 0));
    if (!prixGrossiste) {
      throw new Error("Indiquez le prix BIZZOO : le prix de vente s'en déduit.");
    }
    const tauxMarge = null;   // la marge est celle de la boutique, jamais du produit
    /* Le taux REVENDEUR, lui, peut être propre à l'article. Un champ vide
       vaut « null » : c'est le taux de la boutique qui s'appliquera. */
    const tauxRevendeur = String(donnees.tauxRevendeur === undefined
      ? "" : donnees.tauxRevendeur).trim() === "" ? null : lireTaux(donnees.tauxRevendeur);
    if (donnees.tauxRevendeur !== undefined
        && String(donnees.tauxRevendeur).trim() !== "" && tauxRevendeur === null) {
      throw new Error("Le taux revendeur doit être un nombre entre 0 et " + TAUX_MAX + " %.");
    }
    const prix = prixPublic(prixGrossiste, null);
    if (prix <= 0) {
      throw new Error("Le prix de vente est vide : vérifiez le prix BIZZOO.");
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
    /* Les deux options s'excluent : un produit qu'on ne tient jamais
       n'est pas en cours de réassort. */
    const approLe = !surCommande && donnees.approJours
      ? dateApproDans(donnees.approJours)
      : "";
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
      stock: surCommande || approLe ? 0 : stock,
      surCommande,
      approLe,
      enAvant,
      ordreAvant,
      images: chemins,
      video: cheminVideo,
    };

    const ligne = ligneDepuisProduit(produit);
    /* La ligne d'avant, pour pouvoir revenir dessus. */
    const avant = existant ? await ligneBrute("produits", produit.id) : null;
    let lignes;
    if (existant) {
      lignes = await Supabase.requete("PATCH", "produits?id=eq." + encodeURIComponent(produit.id), ligne);
      journaliser("produit", "modification",
        "Produit modifié : " + produit.nom + " — " + Utils.fmtMontant(produit.prix, reglages.devise),
        produit.reference || produit.nom,
        aAnnuler("produits", [avant], [produit.id]));
    } else {
      ligne.cree_le = new Date().toISOString();
      /* Le produit naît dans la boutique ouverte, et n'en bougera plus. */
      if (boutiqueId) ligne.boutique_id = boutiqueId;
      lignes = await Supabase.requete("POST", "produits", ligne);
      journaliser("produit", "ajout",
        "Nouveau produit : " + produit.nom + " — " + Utils.fmtMontant(produit.prix, reglages.devise),
        produit.reference || produit.nom,
        aAnnuler("produits", [], [produit.id]));
    }
    await sauverPrixAchat(produit.id, prixGrossiste, tauxMarge, tauxRevendeur);
    const enregistre = produitDepuisLigne(Array.isArray(lignes) ? lignes[0] : ligne);
    return { ...enregistre, prixGrossiste, tauxMarge, tauxRevendeur };
  }

  /**
   * Le prix d'achat vit à part : une ligne par produit, écrite en même
   * temps que lui. Une base pas encore mise à jour n'en a pas la table —
   * le produit s'enregistre quand même, sans son prix d'achat.
   */
  async function sauverPrixAchat(id, prixGrossiste, tauxMarge, tauxRevendeur) {
    if (!prixAchatEnBase) return;
    try {
      await Supabase.requete("POST", "produits_prive?on_conflict=produit_id", {
        produit_id: id,
        prix_grossiste: prixGrossiste,
        taux_marge: tauxMarge,
        /* À null, c'est le taux de la boutique qui s'applique. C'est le
           cas de tous les produits tant qu'on n'en décide pas autrement. */
        taux_revendeur: tauxRevendeur === undefined ? null : tauxRevendeur,
        maj_le: new Date().toISOString(),
      }, { upsert: true });
    } catch (err) {
      if (!/produits_prive|relationship/i.test(err.message || "")) throw err;
      prixAchatEnBase = false;
    }
  }

  async function supprimerProduit(id) {
    const produit = await lireProduit(id);
    const avant = await ligneBrute("produits", id);
    /* Les photos et la vidéo restent dans le stockage : sans elles,
       annuler la suppression rendrait un produit aux images mortes.
       Elles ne pèsent que quelques centaines de kilo-octets. */
    await Supabase.requete("DELETE", "produits?id=eq." + encodeURIComponent(id));
    if (produit) {
      journaliser("produit", "suppression", "Produit supprimé : " + produit.nom,
        produit.reference || produit.nom,
        aAnnuler("produits", [avant], [id]));
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
   * Change l'état d'un produit sans repasser par le formulaire : un
   * nombre de pièces, le passage en « Sur commande », ou un réassort
   * annoncé (`approJours` de 1 à 8, ou 0 pour l'annuler).
   */
  async function majDisponibilite(id, maj) {
    const produit = await lireProduit(id);
    if (!produit) throw new Error("Produit introuvable.");
    const ligneAvant = await ligneBrute("produits", id);
    const surCommande = maj.surCommande !== undefined ? !!maj.surCommande : produit.surCommande;
    /* Les trois options s'excluent : dire l'une efface les autres. */
    let approLe = produit.approLe;
    if (maj.approJours !== undefined) approLe = maj.approJours ? dateApproDans(maj.approJours) : "";
    else if (surCommande || maj.stock !== undefined) approLe = "";
    const stock = surCommande || approLe
      ? 0
      : lireStock(maj.stock !== undefined ? maj.stock : produit.stock);
    if (stock === produit.stock && surCommande === produit.surCommande &&
        approLe === produit.approLe) {
      return produit;
    }

    await Supabase.requete("PATCH", "produits?id=eq." + encodeURIComponent(id), {
      stock,
      sur_commande: surCommande,
      appro_le: approLe || null,
      disponible: surCommande || stock > 0,
      modifie_le: new Date().toISOString(),
    });

    const avant = statut(produit);
    const apres = statut({ stock, surCommande, approLe });
    /* Un changement d'état a plus de sens dans l'historique qu'un simple chiffre. */
    const action = apres === "rupture" ? "rupture"
      : apres === "commande" ? "sur_commande"
      : apres === "approvisionnement" ? "appro"
      : (avant === "disponible" ? "stock" : "retour_stock");
    const libelle = apres === "commande"
      ? "Passé en « Sur commande » : " + produit.nom
      : apres === "approvisionnement"
        ? "En approvisionnement, arrive " +
          Utils.delaiEnMots(Utils.joursAvant(approLe)) + " : " + produit.nom
        : apres === "rupture"
          ? "En rupture : " + produit.nom
          : (avant === "disponible"
              ? "Stock : " + produit.stock + " → " + stock + " — " + produit.nom
              : "Réapprovisionné (" + stock + ") : " + produit.nom);
    journaliser("produit", action, libelle, produit.reference || produit.nom,
      aAnnuler("produits", [ligneAvant], [id]));
    return { ...produit, stock, surCommande, approLe };
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
    const avant = await ligneBrute("produits", id);
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
      produit.reference || produit.nom,
      aAnnuler("produits", [avant], [id]));
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
    /* Un échange touche deux lignes : on garde les deux, sinon annuler
       laisserait le classement de travers. */
    const avant = [await ligneBrute("produits", courant.id), await ligneBrute("produits", voisin.id)];
    const tmp = courant.ordreAvant;
    courant.ordreAvant = voisin.ordreAvant;
    voisin.ordreAvant = tmp;
    for (const p of [courant, voisin]) {
      await Supabase.requete("PATCH", "produits?id=eq." + encodeURIComponent(p.id),
        { ordre_avant: p.ordreAvant });
    }
    journaliser("produit", "ordre_slider",
      "Ordre du slider modifié : " + courant.nom + " en position " + courant.ordreAvant,
      courant.reference || courant.nom,
      aAnnuler("produits", avant, [courant.id, voisin.id]));
  }

  /* ---------- Écrans du slider ----------
     Photos et vidéos choisies une par une, dans l'ordre voulu. Chacune
     peut renvoyer vers un produit — ou n'être qu'une affiche.

     Deux sliders sans rapport l'un avec l'autre : celui de l'enseigne
     BIZZOO, qui défile sur l'accueil de l'application client, et celui
     d'une boutique, qui défile sur son écran à elle. */

  function slideDepuisLigne(l) {
    const video = l.video || "";
    return {
      id: l.id,
      chemin: l.image || "",
      apercu: l.image ? Supabase.urlImage(l.image) : "",
      video,
      videoUrl: video ? Supabase.urlImage(video) : "",
      estVideo: !!video,
      titre: l.titre || "",
      produitId: l.produit_id || "",
      ordre: l.ordre || 0,
      actif: l.actif !== false,
      portee: l.portee === "enseigne" || l.portee === "publicite" ? l.portee : "boutique",
    };
  }

  /* Ce qui appartient à l'enseigne — son slider et sa publicité — n'a
     pas de boutique ; le slider d'une boutique ne sort jamais de la
     sienne. */
  const auNiveauEnseigne = (cible) => cible === "enseigne" || cible === "publicite";
  const filtreSlides = (cible) =>
    auNiveauEnseigne(cible)
      ? "portee=eq." + cible
      : "portee=eq.boutique" + (filtreBoutique() ? "&" + filtreBoutique() : "");

  async function listerSlides(cible) {
    const lignes = await Supabase.requete("GET",
      "slides?select=*&order=ordre.asc&" + filtreSlides(cible));
    return (lignes || []).map(slideDepuisLigne);
  }

  /** « (BIZZOO) », « (Publicité BIZZOO) », ou rien pour une boutique. */
  const ditLaVitrine = (cible) =>
    cible === "publicite" ? " (Publicité BIZZOO)" : (cible === "enseigne" ? " (BIZZOO)" : "");

  const lireSlide = async (id, cible) =>
    (await listerSlides(cible)).find((s) => s.id === id) || null;

  /**
   * Enregistre un écran du slider. `donnees.media` porte la photo ou la
   * vidéo : { type:"photo", chemin } ou { type:"photo", dataUrl } pour
   * une image, { type:"video", chemin } ou { type:"video", fichier }
   * pour une vidéo. Un écran ne montre qu'un seul média.
   */
  async function sauverSlide(donnees, cible) {
    const enseigne = auNiveauEnseigne(cible);
    /* Ce qui est à l'enseigne va dans son dossier à elle : la base y
       réserve le dépôt au superadministrateur, quand « slider/ » reste
       ouvert aux administrateurs de boutique. */
    const dossier = enseigne ? "enseigne/" : "slider/";
    const existant = donnees.id ? await lireSlide(donnees.id, cible) : null;
    const liste = await listerSlides(cible);
    if (!existant && liste.length >= MAX_SLIDES) {
      throw new Error("Le slider accepte " + MAX_SLIDES + " écrans au maximum. Retirez-en un d'abord.");
    }

    const avant = existant ? await ligneBrute("slides", existant.id) : null;
    const media = donnees.media || {};
    let chemin = "";
    let cheminVideo = "";
    if (media.type === "video") {
      cheminVideo = media.chemin || "";
      if (media.fichier) {
        const octets = media.fichier.size || 0;
        if (octets > MAX_VIDEO_MO * 1024 * 1024) {
          throw new Error("Vidéo trop lourde (" + Utils.tailleLisible(octets) + "). " +
            "Le slider accepte " + MAX_VIDEO_MO + " Mo au maximum par écran.");
        }
        const extension = (media.fichier.name || "").match(/\.([a-z0-9]{2,4})$/i);
        cheminVideo = dossier + Utils.uid("vid") +
          (extension ? "." + extension[1].toLowerCase() : ".mp4");
        await Supabase.televerserVideo(cheminVideo, media.fichier);
      }
      if (!cheminVideo) throw new Error("Choisissez la vidéo à faire défiler.");
    } else {
      chemin = media.chemin || "";
      if (media.dataUrl) {
        chemin = dossier + Utils.uid("sli") + ".jpg";
        await Supabase.televerserImage(chemin, media.dataUrl);
      }
      if (!chemin) throw new Error("Choisissez la photo à faire défiler.");
    }

    const slide = {
      id: existant ? existant.id : Utils.uid("sli"),
      image: chemin,
      video: cheminVideo,
      titre: (donnees.titre || "").trim(),
      produit_id: donnees.produitId || null,
      ordre: existant ? existant.ordre : liste.reduce((m, s) => Math.max(m, s.ordre || 0), 0) + 1,
      actif: donnees.actif !== false,
      portee: enseigne ? cible : "boutique",
      /* Ce qui est à l'enseigne n'appartient à aucune boutique. */
      boutique_id: enseigne ? null : boutiqueId || null,
    };
    /* Le slider d'une boutique est sa vitrine chez le client :
       l'enseigne veut voir ce qu'on y met. Retirer un écran ou changer
       l'ordre reste libre — on n'y ajoute rien. */
    if (!enseigne && !Supabase.estSuper()) {
      await deposerDemande("slider", {
        id: slide.id, image: slide.image, video: slide.video,
        titre: slide.titre, produit_id: slide.produit_id,
        ordre: slide.ordre, actif: slide.actif,
      }, avant, (existant ? "Écran du slider modifié" : "Écran ajouté au slider") +
        (slide.titre ? " : " + slide.titre : ""), existant ? existant.id : null);
      return slideDepuisLigne(slide);
    }
    const lignes = await Supabase.requete("POST", "slides?on_conflict=id", slide, { upsert: true });

    /* L'ancien média ne sert plus à rien : on libère la place. */
    const anciens = existant
      ? [existant.chemin, existant.video].filter((c) => c && c !== chemin && c !== cheminVideo)
      : [];
    if (anciens.length) await Supabase.supprimerImages(anciens);

    const quoi = cheminVideo ? "Vidéo" : "Photo";
    journaliser("slider", existant ? "modification" : "ajout",
      (existant ? quoi + " modifiée" : quoi + " ajoutée") + ditLaVitrine(cible) +
        (cible === "publicite" ? "" : " (slider)"),
      slide.titre,
      aAnnuler("slides", [avant], [slide.id]),
      enseigne ? null : undefined);
    return slideDepuisLigne((lignes && lignes[0]) || slide);
  }

  async function supprimerSlide(id, cible) {
    const slide = await lireSlide(id, cible);
    const avant = await ligneBrute("slides", id);
    /* La photo ou la vidéo reste dans le stockage : sans elle, annuler
       le retrait rendrait un écran vide. */
    await Supabase.requete("DELETE", "slides?id=eq." + encodeURIComponent(id));
    journaliser("slider", "suppression",
      (slide && slide.estVideo ? "Vidéo retirée" : "Photo retirée") + ditLaVitrine(cible) +
        (cible === "publicite" ? "" : " (slider)"),
      slide ? slide.titre : "",
      aAnnuler("slides", [avant], [id]),
      auNiveauEnseigne(cible) ? null : undefined);
  }

  /** Monte ou descend un écran dans le slider (direction -1 ou +1). */
  async function deplacerSlide(id, direction, cible) {
    const liste = await listerSlides(cible);
    const index = liste.findIndex((s) => s.id === id);
    const voisin = liste[index + direction];
    if (index < 0 || !voisin) return;
    liste.forEach((s, i) => { s.ordre = i + 1; });
    const courant = liste[index];
    const avant = [await ligneBrute("slides", courant.id), await ligneBrute("slides", voisin.id)];
    const tmp = courant.ordre;
    courant.ordre = voisin.ordre;
    voisin.ordre = tmp;
    for (const s of [courant, voisin]) {
      await Supabase.requete("PATCH", "slides?id=eq." + encodeURIComponent(s.id), { ordre: s.ordre });
    }
    journaliser("slider", "ordre",
      "Ordre modifié : écran en position " + courant.ordre + ditLaVitrine(cible) +
        (cible === "publicite" ? "" : " (slider)"),
      courant.titre,
      aAnnuler("slides", avant, [courant.id, voisin.id]),
      auNiveauEnseigne(cible) ? null : undefined);
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
        appro_le: p.approLe || p.appro_le || null,
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
          lireTaux(p.tauxMarge),
          p.tauxRevendeur === null || p.tauxRevendeur === undefined
            ? null : lireTaux(p.tauxRevendeur));
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
    MAX_TELEPHONES, MAX_ADRESSES, TAUX_MAX, ROLES, rolesAttribuables, gereLeCompte,
    prixPublic, prixRevendeur, tauxDepuisPrix, tauxApplique, lireTaux,
    init, lireReglages, majReglages, photosBoutique, sauverPhotosBoutique,
    lireEnseigne, majEnseigne, videoBoutique, sauverVideoBoutique,
    listerBoutiques, lireBoutique, boutiqueCourante, choisirBoutique,
    sauverBoutique, basculerBoutique, deplacerBoutique, supprimerBoutique,
    journaliser, lireJournal,
    listerComptes, creerCompte, majCompte, supprimerCompte, changerMotDePasseCompte,
    listerCategories, lireCategorie, sauverCategorie, supprimerCategorie, deplacerCategorie,
    listerProduits, lireProduit, produitsDeCategorie, chercherProduits, prochaineReference,
    sauverProduit, supprimerProduit, photosDeProduit,
    listerSlides, sauverSlide, supprimerSlide, deplacerSlide,
    listerDemandes, approuverDemande, refuserDemande, retirerDemande,
    listerRevendeurs, deciderRevendeur,
    listerClients, lireClient, commandesDuClient,
    VERDICTS, journalVersements, resumeVersements,
    listerCodes, enregistrerCode, remisesPeriode,
    listerLivreurs, confierLivraison, mesLivraisons, avancerLivraison,
    listerAvis, repondreAvis, masquerAvis,
    SUJETS_SAV, listerReclamations, messagesReclamation,
    repondreReclamation, trancherReclamation,
    listerCommandes, commandesEnAttente, avancerLigne, confirmerPaiement,
    statistiquesVentes,
    statistiquesBoutique,
    ETATS_LIGNE, SUITE_LIGNE, lirePaiement, majPaiement, lireRegles, majRegles,
    dernierEnvoiValidation, CHAMPS_A_VALIDER, NOM_DU_CHAMP,
    listerEnAvant, basculerEnAvant, deplacerEnAvant, majDisponibilite, statut, STATUTS,
    annulerAction,
    enAppro, joursAppro, dateApproDans, APPRO_MIN, APPRO_MAX,
    enVenteFlash, majVenteFlash,
    statistiques, exporter, importer,
  };
})();
