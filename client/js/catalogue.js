/* =========================================================
   Catalogue — lecture du catalogue de la boutique.

   Source normale : la base Supabase (config.js), mise à jour
   en direct par l'application admin. Une copie du dernier
   catalogue vu est gardée sur le téléphone (localStorage)
   pour consulter hors connexion.

   Tant que config.js n'est pas rempli, l'application tourne
   en mode démonstration (demo-catalogue.json embarqué).
   ========================================================= */
const Catalogue = (() => {

  const CLE_CACHE = "impact-catalogue";
  const CLE_CONFIG = "impact-config";   // configuration saisie dans l'app (page Infos)
  const NB_EN_AVANT = 5;               // produits qui défilent après les images

  /* Deux catalogues, et il faut les tenir séparés.
       « brutes »  — ce qui arrive de la base : les prix de la vitrine.
                     C'est LUI qu'on garde sur le téléphone.
       « donnees » — le même, aux prix du compte connecté. Un revendeur
                     validé y voit le prix BIZZOO.
     Sans cette séparation, la copie locale garderait les prix
     revendeur : se déconnecter ne les rendrait pas, et le téléphone
     montrerait ces prix à qui l'emprunte. */
  let brutes = null;        // le catalogue tel qu'il arrive
  let donnees = null;       // le même, aux prix du compte connecté
  let prixCompte = null;    // id de produit → prix, pour ce compte-ci
  let source = "aucune";    // "aucune" | "cache" | "reseau" | "demo"

  /* ---------- Configuration Supabase ---------- */

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

  function majConfiguration(url, cle) {
    localStorage.setItem(CLE_CONFIG, JSON.stringify({
      url: (url || "").trim().replace(/\/+$/, ""),
      cle: (cle || "").trim(),
    }));
    localStorage.removeItem(CLE_CACHE);
  }

  /* ---------- Copie locale ---------- */

  function lireCache() {
    try {
      const brut = localStorage.getItem(CLE_CACHE);
      if (!brut) return null;
      const d = JSON.parse(brut);
      return d && d.application === "impact-catalogue" ? d : null;
    } catch (_) {
      return null;
    }
  }

  function ecrireCache(d) {
    try {
      localStorage.setItem(CLE_CACHE, JSON.stringify(d));
    } catch (_) { /* stockage plein : on garde juste la version en mémoire */ }
  }

  /* ---------- Les prix du compte connecté ----------

     Un revendeur validé par BIZZOO achète au prix BIZZOO. La base lui
     sert ses prix par « mes_prix() » — et c'est la MÊME règle qui
     facture la commande, sinon il verrait un montant et en paierait
     un autre.

     Ce qui n'a pas de prix revendeur garde le prix de la vitrine : un
     produit dont la boutique n'a pas renseigné son prix BIZZOO ne
     devient gratuit pour personne. */

  function appliquerPrix() {
    if (!brutes) { donnees = null; return; }
    if (!prixCompte || !prixCompte.size) { donnees = brutes; return; }
    donnees = Object.assign({}, brutes, {
      produits: (brutes.produits || []).map((p) => {
        const prix = prixCompte.get(p.id);
        if (prix === undefined || prix === p.prix) return p;
        /* Un prix revendeur n'est pas une promotion : pas de prix barré,
           sinon tout le catalogue se retrouverait en « bonnes affaires ».
           On garde le prix public à part, pour pouvoir le montrer. */
        return Object.assign({}, p, {
          prix, ancienPrix: null, prixPublic: p.prix, prixRevendeur: true,
        });
      }),
    });
  }

  /**
   * Poser (ou retirer) les prix du compte connecté. Appelée à la
   * connexion, à la déconnexion, et quand la validation d'un revendeur
   * arrive. Redessine l'écran si quelque chose a bougé.
   */
  function definirPrixCompte(liste) {
    const avant = prixCompte;
    prixCompte = null;
    if (Array.isArray(liste) && liste.length) {
      prixCompte = new Map();
      for (const l of liste) {
        const prix = Number(l && (l.prix !== undefined ? l.prix : l.p));
        const id = l && (l.produit_id || l.id);
        if (id && isFinite(prix) && prix >= 0) prixCompte.set(String(id), Math.round(prix));
      }
      if (!prixCompte.size) prixCompte = null;
    }
    const change = (avant ? avant.size : 0) !== (prixCompte ? prixCompte.size : 0)
      || (prixCompte && [...prixCompte].some(([id, prix]) => !avant || avant.get(id) !== prix));
    appliquerPrix();
    if (change && donnees) document.dispatchEvent(new CustomEvent("catalogue:maj"));
    return change;
  }

  /** Ce compte voit-il des prix qui lui sont propres ? */
  const auxPrixRevendeur = () => !!(prixCompte && prixCompte.size);

  /* ---------- Lecture de la base Supabase ---------- */

  /**
   * Le stock d'un produit. Une base d'avant la gestion de stock, ou une
   * copie hors connexion plus ancienne, n'a que l'ancien oui/non : il
   * vaut alors 1 ou 0.
   */
  function stockDeLigne(p) {
    const brut = p.stock;
    if (brut === null || brut === undefined) return p.disponible === false ? 0 : 1;
    return Math.max(0, Math.round(Number(brut) || 0));
  }

  async function lireTable(c, chemin, signal) {
    const reponse = await fetch(c.url + "/rest/v1/" + chemin, {
      headers: { "apikey": c.cle },
      signal,
    });
    if (!reponse.ok) throw new Error("Catalogue indisponible (" + reponse.status + ")");
    return reponse.json();
  }

  /* Les autres numéros et les autres adresses de la boutique. Le gérant
     en ajoute autant qu'il veut depuis l'application admin ; ici on ne
     garde que les lignes réellement utilisables. */

  const nombreOuNull = (v) => (typeof v === "number" && isFinite(v) ? v : null);

  function autresNumeros(liste) {
    return (Array.isArray(liste) ? liste : [])
      .map((t) => ({
        libelle: String((t && t.libelle) || "").trim(),
        numero: String((t && t.numero) || "").trim(),
        whatsapp: !!(t && t.whatsapp),
      }))
      .filter((t) => /\d/.test(t.numero));
  }

  function autresAdresses(liste) {
    return (Array.isArray(liste) ? liste : [])
      .map((a) => ({
        libelle: String((a && a.libelle) || "").trim(),
        texte: String((a && a.texte) || "").trim(),
        latitude: nombreOuNull(a && a.latitude),
        longitude: nombreOuNull(a && a.longitude),
      }))
      .filter((a) => a.texte);
  }

  async function telechargerDepuisBase(c) {
    const controleur = new AbortController();
    const minuterie = setTimeout(() => controleur.abort(), 15000);
    try {
      const [boutiques, categories, produits, slides, lesBoutiques] = await Promise.all([
        lireTable(c, "boutique?select=*&id=eq.1", controleur.signal),
        lireTable(c, "categories?select=*,sous_categories(*)&order=ordre.asc", controleur.signal),
        lireTable(c, "produits?select=*&order=modifie_le.desc", controleur.signal),
        lireTable(c, "slides?select=*&order=ordre.asc", controleur.signal),
        /* Les secteurs de l'enseigne. Base pas encore mise à jour :
           l'application retombe sur la boutique unique d'avant. */
        lireTable(c, "boutiques?select=*&order=ordre.asc", controleur.signal).catch(() => []),
      ]);
      const b = (boutiques && boutiques[0]) || {};
      const urlImagePublique = (chemin) =>
        c.url + "/storage/v1/object/public/produits/" + chemin;
      /* LE ROND D'UNE CATÉGORIE : une illustration qui voyage avec
         l'application (« img/categories/… ») se lit sur place, sans
         réseau ; une photo déposée par l'enseigne, dans le seau. */
      const urlImageCategorie = (chemin) =>
        /^img\/categories\//.test(chemin) ? chemin : urlImagePublique(chemin);
      return {
        application: "impact-catalogue",
        version: 2,
        publieLe: b.maj_le || new Date().toISOString(),
        boutique: {
          nom: b.nom || "", slogan: b.slogan || "", description: b.description || "",
          tel: b.tel || "", whatsapp: b.whatsapp || "", indicatif: b.indicatif || "",
          devise: b.devise || "", adresse: b.adresse || "", horaires: b.horaires || "",
          siteWeb: b.site_web || "",
          facebook: b.facebook || "", instagram: b.instagram || "",
          tiktok: b.tiktok || "", youtube: b.youtube || "", snapchat: b.snapchat || "",
          latitude: b.latitude === null || b.latitude === undefined ? null : Number(b.latitude),
          longitude: b.longitude === null || b.longitude === undefined ? null : Number(b.longitude),
          photos: (Array.isArray(b.photos) ? b.photos : []).map(urlImagePublique),
          telephones: autresNumeros(b.telephones),
          adresses: autresAdresses(b.adresses),
          video: b.video ? urlImagePublique(b.video) : "",
        },
        boutiques: (lesBoutiques || []).map((b2) => ({
          id: b2.id,
          nom: b2.nom || "",
          secteur: b2.secteur || "",
          /* Le secteur STRUCTUREL : la catégorie de BIZZOO où se range
             la boutique. « secteur » juste au-dessus n'est que le texte
             affiché sous son nom. */
          categorieId: b2.categorie_id || "",
          slogan: b2.slogan || "",
          description: b2.description || "",
          icone: b2.icone || "magasin",
          couleur: b2.couleur || "#2550B7",
          logo: b2.logo ? urlImagePublique(b2.logo) : "",
          actif: b2.actif !== false,
          ordre: b2.ordre || 0,
          tel: b2.tel || "", whatsapp: b2.whatsapp || "", indicatif: b2.indicatif || "",
          devise: b2.devise || "", adresse: b2.adresse || "", horaires: b2.horaires || "",
          siteWeb: b2.site_web || "",
          facebook: b2.facebook || "", instagram: b2.instagram || "",
          tiktok: b2.tiktok || "", youtube: b2.youtube || "", snapchat: b2.snapchat || "",
          latitude: b2.latitude === null || b2.latitude === undefined ? null : Number(b2.latitude),
          longitude: b2.longitude === null || b2.longitude === undefined ? null : Number(b2.longitude),
          photos: (Array.isArray(b2.photos) ? b2.photos : []).map(urlImagePublique),
          telephones: autresNumeros(b2.telephones),
          adresses: autresAdresses(b2.adresses),
          video: b2.video ? urlImagePublique(b2.video) : "",
          /* La note et le nombre d'avis viennent de la base, tenus par
             elle : l'écran les lit, il ne les additionne pas. Sans cela,
             dessiner une carte demanderait de charger tous les avis de
             tous les produits. */
          note: b2.note_moyenne === null || b2.note_moyenne === undefined
            ? null : Number(b2.note_moyenne),
          nbAvis: Number(b2.nb_avis) || 0,
        })),
        categories: (categories || []).map((cat) => ({
          id: cat.id,
          boutiqueId: cat.boutique_id || "",
          nom: cat.nom,
          /* La pastille ronde de l'écran « Catégories ». Une base pas
             encore mise à jour n'a pas ces colonnes : la catégorie
             garde alors l'icône passe-partout plutôt qu'un rond vide. */
          icone: cat.icone || "categories",
          couleur: cat.couleur || "#2550B7",
          /* La photo du rond, posée par l'enseigne ; sans elle — ou sur
             une base qui n'a pas encore la colonne —, l'icône suffit. */
          image: cat.image ? urlImageCategorie(cat.image) : "",
          enAvant: cat.en_avant === true,
          ordre: cat.ordre || 0,
          sousCategories: (cat.sous_categories || [])
            .map((s) => ({ id: s.id, nom: s.nom, ordre: s.ordre || 0 }))
            .sort((a, x) => a.ordre - x.ordre),
        })),
        produits: (produits || []).map((p) => ({
          id: p.id,
          boutiqueId: p.boutique_id || "",
          nom: p.nom,
          /* Le code vient de la base et n'en bouge jamais ; la référence
             appartient à la boutique. Deux choses différentes. */
          code: p.code || "",
          reference: p.reference || "",
          description: p.description || "",
          prix: Number(p.prix) || 0,
          ancienPrix: p.ancien_prix === null || p.ancien_prix === undefined ? null : Number(p.ancien_prix),
          categorieId: p.categorie_id,
          sousCategorieId: p.sous_categorie_id || "",
          stock: stockDeLigne(p),
          surCommande: !!p.sur_commande,
          approLe: p.appro_le || "",
          flashFin: p.flash_fin ? Date.parse(p.flash_fin) || null : null,
          enAvant: !!p.en_avant,
          ordreAvant: p.ordre_avant || 0,
          images: (Array.isArray(p.images) ? p.images : []).map(urlImagePublique),
          video: p.video ? urlImagePublique(p.video) : "",
          creeLe: Date.parse(p.cree_le || "") || 0,
          modifieLe: Date.parse(p.modifie_le || "") || 0,
          modifieLeBrut: p.modifie_le || "",   // tel quel : sert de repère aux notifications
          /* Idem pour un produit : la note est calculée par la base à
             chaque avis, et voyage avec le catalogue. */
          note: p.note_moyenne === null || p.note_moyenne === undefined
            ? null : Number(p.note_moyenne),
          nbAvis: Number(p.nb_avis) || 0,
        })),
        slides: (slides || []).map((s) => ({
          id: s.id,
          boutiqueId: s.boutique_id || "",
          /* « enseigne »  : le slider de BIZZOO, en haut de l'accueil.
             « publicite » : ce que BIZZOO met en avant plus bas sur
                             l'accueil — affiches et produits choisis
                             dans n'importe quelle boutique.
             « boutique »  : le slider d'une boutique, sur son écran. */
          portee: s.portee === "enseigne" || s.portee === "publicite" ? s.portee : "boutique",
          image: s.image ? urlImagePublique(s.image) : "",
          video: s.video ? urlImagePublique(s.video) : "",
          titre: s.titre || "",
          produitId: s.produit_id || "",
          ordre: s.ordre || 0,
          actif: s.actif !== false,
        })),
      };
    } finally {
      clearTimeout(minuterie);
    }
  }

  async function telechargerDemo() {
    const reponse = await fetch("demo-catalogue.json");
    if (!reponse.ok) throw new Error("Catalogue de démonstration introuvable");
    const d = await reponse.json();
    if (!d || d.application !== "impact-catalogue") throw new Error("Catalogue invalide");
    return d;
  }

  /* ---------- Notifications Android ---------- */

  /**
   * Repère du catalogue affiché : identifiant et date du produit
   * modifié en dernier. La vérification de fond d'Android compare
   * exactement la même chaîne (VerificateurCatalogue.java).
   */
  function signature() {
    const liste = (donnees && donnees.produits) || [];
    if (!liste.length) return "";
    let recent = liste[0];
    for (const p of liste) {
      if ((p.modifieLe || 0) > (recent.modifieLe || 0)) recent = p;
    }
    if (!recent.modifieLeBrut) return "";
    return String(recent.id) + "|" + recent.modifieLeBrut;
  }

  /** « Ceci, le client vient de le voir » : pas de notification pour rien. */
  function signalerAndroid() {
    const sig = signature();
    if (!sig) return;
    try {
      if (typeof AndroidPont !== "undefined" && AndroidPont.majDerniereVue) {
        AndroidPont.majDerniereVue(sig);
      }
    } catch (_) { /* version web ou ancienne application : rien à signaler */ }
  }

  /**
   * Charge le catalogue : la copie locale d'abord (affichage
   * immédiat), puis la base en ligne. Renvoie true si des
   * données sont disponibles. Émet "catalogue:maj" quand une
   * version plus récente arrive du réseau.
   */
  async function charger() {
    const c = configuration();
    const enCache = c ? lireCache() : null;
    if (enCache) {
      brutes = enCache;
      appliquerPrix();
      source = "cache";
    }

    try {
      const frais = c ? await telechargerDepuisBase(c) : await telechargerDemo();
      const changement = brutes && JSON.stringify(frais) !== JSON.stringify(brutes);
      brutes = frais;
      appliquerPrix();
      source = c ? "reseau" : "demo";
      /* On garde les prix de la vitrine, jamais ceux du compte. */
      if (c) ecrireCache(frais);
      signalerAndroid();
      if (changement && enCache) {
        document.dispatchEvent(new CustomEvent("catalogue:maj"));
      }
    } catch (_) {
      /* hors connexion : on reste sur la copie locale si elle existe */
    }
    return !!donnees;
  }

  /**
   * Recharge le catalogue depuis la base sans rien casser à l'écran.
   * Émet "catalogue:maj" uniquement si quelque chose a changé.
   * Renvoie true dans ce cas.
   *
   * « silencieux » : l'appelant redessine lui-même, et a quelque chose
   * à dire. Sans cela, l'écran se redessinait deux fois et « Catalogue
   * mis à jour » recouvrait l'explication qu'on venait de donner.
   */
  async function rafraichir(options) {
    const c = configuration();
    if (!c) return false;
    let frais;
    try {
      frais = await telechargerDepuisBase(c);
    } catch (_) {
      return false; // hors connexion : on garde l'affichage actuel
    }
    const change = JSON.stringify(frais) !== JSON.stringify(brutes);
    brutes = frais;
    appliquerPrix();
    source = "reseau";
    ecrireCache(frais);
    signalerAndroid();
    if (change && !(options && options.silencieux)) {
      document.dispatchEvent(new CustomEvent("catalogue:maj"));
    }
    return change;
  }

  const pret = () => !!donnees;
  const depuisCache = () => source === "cache";
  const modeDemo = () => source === "demo";

  /* =====================================================
     Les boutiques

     L'application réunit plusieurs secteurs d'activité. L'accueil
     les présente en icônes ; on entre dans l'une d'elles et tout
     l'écran — rayons, produits, coordonnées — ne parle plus que
     d'elle. Le choix se retient d'une visite à l'autre.
     ===================================================== */

  const CLE_BOUTIQUE = "impact-boutique";
  let boutiqueId = "";
  try { boutiqueId = localStorage.getItem(CLE_BOUTIQUE) || ""; } catch (_) { /* privée */ }

  /** Les boutiques ouvertes aux clients, dans l'ordre voulu par le gérant. */
  function boutiques() {
    return ((donnees && donnees.boutiques) || [])
      .filter((b) => b.actif !== false)
      .slice()
      .sort((a, b) => (a.ordre || 0) - (b.ordre || 0));
  }

  /** Vrai dès que la base connaît des boutiques : sinon, on garde l'ancien mode. */
  const multiBoutiques = () => boutiques().length > 0;

  /** La boutique visitée. Sans choix valable, la première ouverte. */
  function boutiqueChoisie() {
    if (!multiBoutiques()) return null;
    const choisie = boutiques().find((b) => b.id === boutiqueId);
    return choisie || null;
  }

  function choisirBoutique(id) {
    const cible = boutiques().find((b) => b.id === id);
    boutiqueId = cible ? cible.id : "";
    try {
      if (boutiqueId) localStorage.setItem(CLE_BOUTIQUE, boutiqueId);
      else localStorage.removeItem(CLE_BOUTIQUE);
    } catch (_) { /* navigation privée */ }
    return cible || null;
  }

  const quitterBoutique = () => choisirBoutique("");

  /** Le filtre appliqué au catalogue : rien à filtrer en mode boutique unique. */
  const dansLaBoutique = (x) => {
    const b = boutiqueChoisie();
    return !b || !x.boutiqueId || x.boutiqueId === b.id;
  };

  /* ---------- Boutique ---------- */

  function boutique() {
    /* Une boutique choisie parle en son nom ; sinon, c'est l'enseigne. */
    const choisie = boutiqueChoisie();
    const b = choisie || (donnees && donnees.boutique) || {};
    return {
      id: b.id || "",
      nom: b.nom || "BIZZOO",
      /* Sur l'accueil de l'enseigne, aucune boutique ne parle : afficher
         le slogan de l'une d'elles tromperait sur les autres. */
      slogan: !choisie && multiBoutiques() ? "" : (b.slogan || ""),
      description: b.description || "",
      tel: b.tel || "",
      whatsapp: b.whatsapp || b.tel || "69842516",
      indicatif: b.indicatif || "229",
      devise: b.devise || "FCFA",
      adresse: b.adresse || "",
      horaires: b.horaires || "",
      siteWeb: b.siteWeb || "",
      facebook: b.facebook || "",
      instagram: b.instagram || "",
      tiktok: b.tiktok || "",
      youtube: b.youtube || "",
      snapchat: b.snapchat || "",
      latitude: typeof b.latitude === "number" ? b.latitude : null,
      longitude: typeof b.longitude === "number" ? b.longitude : null,
      photos: Array.isArray(b.photos) ? b.photos : [],
      telephones: autresNumeros(b.telephones),
      adresses: autresAdresses(b.adresses),
      video: b.video || "",
      /* La note que les acheteurs lui ont donnée À ELLE : la livraison,
         l'accueil, le sérieux. Pas la moyenne de ses produits — ce sont
         deux questions différentes, et les mélanger rendrait les deux
         illisibles. L'enseigne, elle, ne se note pas : on note des
         boutiques, pas une galerie marchande. */
      note: choisie && typeof choisie.note === "number" ? choisie.note : null,
      nbAvis: choisie ? (choisie.nbAvis || 0) : 0,
      /* Vrai quand on parle de l'enseigne et non d'une boutique. */
      estEnseigne: !choisie,
    };
  }

  /**
   * L'enseigne BIZZOO elle-même, quelle que soit la boutique visitée.
   * C'est à elle qu'écrit l'onglet « Contact » : le client s'adresse à
   * la maison, pas au rayon où il se trouvait par hasard.
   *
   * Pas de numéro inventé ici, contrairement à `boutique()` : sans
   * numéro renseigné, l'onglet disparaît plutôt que d'ouvrir WhatsApp
   * sur personne.
   */
  function enseigne() {
    const b = (donnees && donnees.boutique) || {};
    return {
      nom: b.nom || "BIZZOO",
      /* LE SLOGAN DE BIZZOO, et pas celui d'une boutique. « boutique() »
         le vide exprès sur l'accueil de l'enseigne — celui d'une
         boutique y tromperait sur les autres —, mais la barre du haut
         a besoin de celui de la maison précisément là. On le prend
         donc ici, où il n'y a aucun doute sur qui parle. */
      slogan: b.slogan || "",
      siteWeb: b.siteWeb || "",
      whatsapp: b.whatsapp || b.tel || "",
      tel: b.tel || "",
      indicatif: b.indicatif || "229",
    };
  }

  const versionPubliee = () => (donnees ? donnees.publieLe : null);

  /* ---------- Catégories ---------- */

  function categories() {
    const liste = ((donnees && donnees.categories) || []).filter(dansLaBoutique);
    return liste.slice().sort((a, b) => (a.ordre || 0) - (b.ordre || 0));
  }

  /* Un lien direct vers un rayon peut arriver avant tout choix de
     boutique : on retrouve la catégorie même hors de la boutique en cours. */
  const toutesCategories = () => ((donnees && donnees.categories) || []).slice();
  const categorie = (id) => toutesCategories().find((c) => c.id === id) || null;

  function sousCategories(categorieId) {
    const c = categorie(categorieId);
    if (!c || !Array.isArray(c.sousCategories)) return [];
    return c.sousCategories.slice().sort((a, b) => (a.ordre || 0) - (b.ordre || 0));
  }

  function sousCategorie(categorieId, scId) {
    return sousCategories(categorieId).find((s) => s.id === scId) || null;
  }

  /* ---------- Produits ---------- */

  const normaliser = (p) => ({
    ...p,
    stock: stockDeLigne(p),
    surCommande: !!p.surCommande,
    images: Array.isArray(p.images) ? p.images : [],
    video: p.video || "",
  });

  function produits() {
    /* UNE BOUTIQUE FERMÉE DISPARAÎT DU CLIENT, ses articles avec. Ce
       filtre-là manquait : tant que « Promotions » entrait d'autorité
       dans la première boutique, la question ne se posait pas. Elle
       réunit maintenant toutes les boutiques, et une fermée n'a rien à
       y faire. */
    const ouvertes = {};
    boutiques().forEach((b) => { ouvertes[b.id] = true; });
    return ((donnees && donnees.produits) || [])
      .filter(dansLaBoutique)
      .filter((p) => !multiBoutiques() || !p.boutiqueId || ouvertes[p.boutiqueId])
      .map(normaliser);
  }

  /* Comme pour les rayons : un lien direct doit ouvrir la fiche même
     si la boutique visitée n'est pas encore la bonne. */
  const tousProduits = () => ((donnees && donnees.produits) || []).map(normaliser);
  const produit = (id) => tousProduits().find((p) => p.id === id) || null;

  /* Les quatre états d'un produit, tels que le client les voit. */
  const STATUTS = {
    disponible: { nom: "Disponible", classe: "badge-disponible" },
    rupture: { nom: "En rupture", classe: "badge-rupture" },
    commande: { nom: "Sur commande", classe: "badge-commande" },
    approvisionnement: { nom: "En approvisionnement", classe: "badge-approvisionnement" },
  };

  /* Réassort annoncé : la date d'arrivée est posée et pas encore
     passée. Le décompte se fait tout seul, jour après jour ; passée la
     date, le produit repasse « En rupture » sans rien demander. */
  const joursAppro = (p) => (p ? Utils.joursAvant(p.approLe) : null);
  const enAppro = (p) => {
    const jours = joursAppro(p);
    return jours !== null && jours >= 0;
  };

  /**
   * « disponible » s'il reste des pièces, « rupture » s'il n'en reste
   * plus, « commande » pour un produit que la boutique ne tient pas,
   * « approvisionnement » pour un produit qui arrive.
   */
  function statut(p) {
    if (!p) return "rupture";
    if (p.surCommande) return "commande";
    if (enAppro(p)) return "approvisionnement";
    return p.stock > 0 ? "disponible" : "rupture";
  }

  /** Du moins cher au plus cher ; à prix égal, par ordre alphabétique. */
  function parPrixCroissant(a, b) {
    const ecart = (Number(a.prix) || 0) - (Number(b.prix) || 0);
    if (ecart) return ecart;
    return Utils.sansAccent(a.nom).localeCompare(Utils.sansAccent(b.nom), "fr");
  }

  function produitsDeCategorie(categorieId, scId) {
    return produits()
      .filter((p) => p.categorieId === categorieId && (!scId || p.sousCategorieId === scId))
      .sort(parPrixCroissant);
  }


  /** Les derniers arrivés d'abord ; à date égale, du moins cher au plus cher. */
  const parNouveaute = (a, b) => (b.creeLe || 0) - (a.creeLe || 0) || parPrixCroissant(a, b);

  /**
   * Tout ce que l'enseigne vend, boutiques ouvertes confondues : c'est
   * l'onglet Produits. Une boutique peut être demandée pour n'en garder
   * qu'elle — les puces en haut de l'écran. `tri` : « recents » pour les
   * derniers arrivés d'abord (« Nos produits » de l'accueil), sinon du
   * moins cher au plus cher.
   */
  function produitsDeLEnseigne(idBoutique, tri) {
    const ouvertes = {};
    boutiques().forEach((b) => { ouvertes[b.id] = true; });
    return tousProduits()
      .filter((p) => !multiBoutiques() || !p.boutiqueId || ouvertes[p.boutiqueId])
      .filter((p) => !idBoutique || p.boutiqueId === idBoutique)
      .sort(tri === "recents" ? parNouveaute : parPrixCroissant);
  }

  /**
   * LA LISTE DE BIZZOO, dans l'ordre que l'enseigne lui a donné.
   *
   * Ce n'est plus une collection de rayons de boutiques : c'est un
   * MENU, le même pour tout le monde, et c'est ce qui permet à
   * l'acheteur de s'y retrouver d'un commerce à l'autre. Les
   * catégories vides restent dedans — le menu d'une place de marché
   * annonce ce qu'on peut y chercher, pas seulement ce qui s'y trouve
   * aujourd'hui, et leur écran dit lui-même qu'il se remplira.
   */
  function categoriesBizzoo() {
    const comptes = {};
    for (const p of produitsDeLEnseigne()) {
      if (p.categorieId) comptes[p.categorieId] = (comptes[p.categorieId] || 0) + 1;
    }
    return toutesCategories()
      .slice()
      .sort((a, b) => (a.ordre || 0) - (b.ordre || 0))
      .map((c) => ({ categorie: c, compte: comptes[c.id] || 0 }));
  }

  /** Celles que l'enseigne montre sur l'accueil : les autres attendent. */
  const categoriesEnAvant = () =>
    categoriesBizzoo().filter((r) => r.categorie.enAvant);

  /**
   * Les rayons d'une catégorie TELS QUE LES BOUTIQUES LES TIENNENT.
   *
   * C'est le second étage de l'écran « Catégories » : on ouvre
   * « Mode & Vêtements » et on voit ce que les boutiques de ce secteur
   * proposent vraiment. Un rayon vide n'y figure pas — sur une place de
   * marché, c'est une porte qui ne mène nulle part.
   */
  function rayonsDeLaCategorie(categorieId) {
    const comptes = {};
    for (const p of produitsDeLEnseigne()) {
      if (p.categorieId === categorieId && p.sousCategorieId) {
        comptes[p.sousCategorieId] = (comptes[p.sousCategorieId] || 0) + 1;
      }
    }
    return sousCategories(categorieId)
      .filter((s) => comptes[s.id])
      .map((s) => ({ sousCategorie: s, compte: comptes[s.id] }));
  }

  /**
   * Les rayons de la boutique visitée : ses sous-catégories tenues.
   *
   * « Les catégories d'une boutique » n'existent plus en tant que
   * telles ; ce sont les rayons du secteur de BIZZOO où elle se range,
   * et seulement ceux où elle a quelque chose.
   */
  function rayonsDeLaBoutique() {
    /* Sans liste de boutiques — le catalogue de démonstration, ou une
       base d'avant — « boutiqueChoisie() » ne rend rien. On part donc
       des PRODUITS EN VUE, qui sont déjà filtrés à la boutique
       visitée : le résultat est le même, et il tient dans les deux cas. */
    const b = boutiqueChoisie();
    const enVue = b ? produitsDeLEnseigne(b.id) : produits();
    const comptes = {};
    for (const p of enVue) {
      if (p.sousCategorieId) comptes[p.sousCategorieId] = (comptes[p.sousCategorieId] || 0) + 1;
    }
    const sortie = [];
    for (const c of toutesCategories()) {
      for (const s of sousCategories(c.id)) {
        if (comptes[s.id]) {
          sortie.push({ sousCategorie: s, compte: comptes[s.id], categorieId: c.id });
        }
      }
    }
    return sortie;
  }

  /** Un écran de slider montre quelque chose et n'est pas masqué. */
  const ecranVisible = (s) => s.actif !== false && (s.image || s.video);

  /** Les écrans que la boutique visitée fait défiler, dans son ordre. */
  function slides() {
    const b = boutiqueChoisie();
    return ((donnees && donnees.slides) || [])
      .filter((s) => ecranVisible(s) && s.portee !== "enseigne" &&
        (!b ? !s.boutiqueId : s.boutiqueId === b.id))
      .sort((a, b2) => (a.ordre || 0) - (b2.ordre || 0));
  }

  /**
   * Le slider de l'accueil : les photos et vidéos de l'enseigne BIZZOO,
   * composées dans ses réglages, et elles seules. Les boutiques n'y
   * envoient plus rien — chacune garde le sien pour son écran.
   */
  function slidesGeneral() {
    return ((donnees && donnees.slides) || [])
      .filter((s) => ecranVisible(s) && s.portee === "enseigne")
      .sort((a, b) => (a.ordre || 0) - (b.ordre || 0));
  }

  /**
   * La publicité de BIZZOO, sur l'accueil de l'enseigne : des affiches
   * — photos ou vidéos — et des produits choisis dans n'importe quelle
   * boutique. Elle a pris la place des ventes flash, qui appartiennent
   * désormais aux boutiques et s'annoncent sur leur écran à elles.
   *
   * Une annonce qui renvoie vers un produit disparu, ou vers une
   * boutique fermée, s'efface d'elle-même : mieux vaut un écran plus
   * court qu'une promesse qu'on ne peut pas tenir.
   */
  function publicites() {
    const ouvertes = {};
    boutiques().forEach((b) => { ouvertes[b.id] = true; });
    return ((donnees && donnees.slides) || [])
      .filter((s) => s.actif !== false && s.portee === "publicite")
      .filter((s) => {
        if (!s.produitId) return !!(s.image || s.video);
        const p = produit(s.produitId);
        return !!p && (!multiBoutiques() || !p.boutiqueId || ouvertes[p.boutiqueId]);
      })
      .sort((a, b) => (a.ordre || 0) - (b.ordre || 0));
  }

  /** En vente flash : une fin posée, pas encore passée. */
  const enVenteFlash = (p) => !!(p && p.flashFin && p.flashFin > Date.now());

  /**
   * Les ventes flash de la boutique visitée, la plus pressée d'abord.
   * Une vente flash appartient à la boutique qui la fait : elle
   * s'annonce sur son écran à elle, et non sur l'accueil de BIZZOO —
   * là, c'est la publicité de l'enseigne qui parle.
   */
  function ventesFlash() {
    return produits()
      .filter(enVenteFlash)
      .sort((a, b) => (a.flashFin || 0) - (b.flashFin || 0));
  }

  /** Combien de produits dans chaque boutique — affiché sous son icône. */
  function nombreParBoutique() {
    const table = {};
    for (const p of tousProduits()) {
      if (p.boutiqueId) table[p.boutiqueId] = (table[p.boutiqueId] || 0) + 1;
    }
    return table;
  }

  /** Les produits mis en avant, qui défilent à la suite des images. */
  function misEnAvant() {
    return produits()
      .filter((p) => p.enAvant)
      .sort((a, b) => (a.ordreAvant || 0) - (b.ordreAvant || 0))
      .slice(0, NB_EN_AVANT);
  }

  function nouveautes(n = 8) {
    return produits()
      .sort((a, b) => (b.creeLe || 0) - (a.creeLe || 0))
      .slice(0, n);
  }

  function promotions() {
    return produits()
      .filter((p) => Utils.remisePourcent(p.ancienPrix, p.prix) !== null)
      .sort(parPrixCroissant);
  }

  /**
   * La plus forte remise en cours, en pourcentage — ou null.
   *
   * C'EST CE CHIFFRE QU'ANNONCE LE BANDEAU DE L'ACCUEIL, et il se
   * calcule sur les prix réellement affichés. Écrire « jusqu'à -40 % »
   * en dur serait plus simple et plus faux : le jour où la dernière
   * promotion se termine, l'accueil continuerait de la promettre, et
   * le client qui s'est déplacé ne la trouverait nulle part. Un
   * bandeau qui ment coûte plus cher que pas de bandeau.
   */
  function meilleureRemise() {
    let haut = 0;
    for (const p of promotions()) {
      const r = Utils.remisePourcent(p.ancienPrix, p.prix);
      if (r !== null && r > haut) haut = r;
    }
    return haut > 0 ? haut : null;
  }

  /**
   * Ce qui se vend le mieux, servi par la base.
   *
   * La base rend un ORDRE — des identifiants, sans les quantités : un
   * classement public ne doit pas livrer à chaque commerçant les
   * volumes de vente de son voisin. On retrouve donc la marchandise
   * dans le catalogue déjà chargé, et on écarte ce qui n'y est plus.
   *
   * Ouvert aux visiteurs : c'est l'accueil, il s'affiche avant qu'on
   * se connecte — d'où la clé publique plutôt qu'un jeton.
   */
  async function produitsPopulaires(combien) {
    const c = configuration();
    if (!c) return [];
    let lignes;
    try {
      const reponse = await fetch(c.url + "/rest/v1/rpc/produits_populaires", {
        method: "POST",
        headers: { "apikey": c.cle, "Content-Type": "application/json" },
        body: JSON.stringify({ limite: combien || 8 }),
      });
      if (!reponse.ok) return [];
      lignes = await reponse.json();
    } catch (_) {
      /* Hors connexion, ou base d'avant ce chantier : la rangée ne
         s'affiche pas, et le reste de l'accueil tient debout. */
      return [];
    }
    if (!Array.isArray(lignes)) return [];
    const parId = new Map(produits().map((p) => [p.id, p]));
    return lignes.map((l) => parId.get(l && l.produit_id)).filter(Boolean);
  }

  /* ---------- Recherche ----------
     Ce qu'on attend d'une recherche dans une enseigne à plusieurs
     boutiques : taper quelques lettres et voir ce qui s'en approche,
     où que ce soit. Trois règles en découlent.

     1. Quelques lettres suffisent : « ordi » trouve « Ordinateur ».
     2. Un seul des mots tapés suffit : « ordinateur portable » sort
        aussi les ordinateurs qui ne sont pas des portables — mais
        après ceux qui le sont. Exiger tous les mots ne rendait plus
        rien dès qu'on en tapait un de trop.
     3. On cherche dans TOUTES les boutiques ouvertes, pas seulement
        celle qu'on visite : le client cherche un produit, il ne sait
        pas encore qui le vend.

     Le classement suit L'ENDROIT où le mot a été trouvé, dans cet
     ordre : le nom, le rayon, le sous-rayon, le code, la référence,
     la description. C'est un ordre STRICT — un produit trouvé par son
     nom passe devant un produit trouvé par son rayon, quel que soit
     le nombre de mots retrouvés. Sans quoi trois mots dans une
     description finiraient par battre le titre exact. */

  const CHAMPS_RECHERCHE = ["nom", "categorie", "sousCategorie",
                            "code", "reference", "description"];

  /* La finesse départage à l'intérieur d'un rang ; elle ne doit jamais
     faire franchir la frontière du rang suivant. */
  const LARGEUR_RANG = 1000;
  const DEBUT_NOM = 6;   // le nom commence par le mot
  const DEBUT_MOT = 3;   // ... ou c'est le début d'un des mots du nom
  const COMPLET = 2.5;   // tout retrouver vaut mieux que la moitié

  /** Les six endroits où l'on cherche, déjà mis à plat. */
  function champsDeRecherche(p) {
    const cat = categorie(p.categorieId);
    const sc = sousCategorie(p.categorieId, p.sousCategorieId);
    return {
      nom: Utils.sansAccent(p.nom),
      categorie: Utils.sansAccent(cat ? cat.nom : ""),
      sousCategorie: Utils.sansAccent(sc ? sc.nom : ""),
      code: Utils.sansAccent(p.code || ""),
      reference: Utils.sansAccent(p.reference || ""),
      description: Utils.sansAccent(p.description || ""),
    };
  }

  /** Ce que vaut un produit pour les mots cherchés. Zéro : il ne sort pas. */
  function noteRecherche(p, mots) {
    const champs = champsDeRecherche(p);
    let meilleur = CHAMPS_RECHERCHE.length;   // aucun endroit trouvé
    let trouves = 0;
    let finesse = 0;

    for (const mot of mots) {
      let rang = -1;
      for (let i = 0; i < CHAMPS_RECHERCHE.length; i++) {
        if (champs[CHAMPS_RECHERCHE[i]].includes(mot)) { rang = i; break; }
      }
      if (rang < 0) continue;
      trouves++;
      if (rang < meilleur) meilleur = rang;
      finesse += CHAMPS_RECHERCHE.length - rang;
      if (rang === 0) {
        if (champs.nom.startsWith(mot)) finesse += DEBUT_NOM;
        else if (champs.nom.includes(" " + mot) || champs.nom.includes("-" + mot)) {
          finesse += DEBUT_MOT;
        }
      }
    }
    if (!trouves) return 0;

    /* L'endroit le plus fort donne le rang ; le reste ne fait que
       départager à l'intérieur, jamais changer de rang. */
    const rangDuProduit = (CHAMPS_RECHERCHE.length - meilleur) * LARGEUR_RANG;
    const detail = finesse * (trouves === mots.length ? COMPLET : 1);
    return rangDuProduit + Math.min(LARGEUR_RANG - 1, detail);
  }

  function rechercher(terme) {
    const t = Utils.sansAccent(terme).trim();
    if (!t) return [];
    const mots = t.split(/\s+/).filter(Boolean);
    const ouvertes = {};
    boutiques().forEach((b) => { ouvertes[b.id] = true; });
    return tousProduits()
      /* Une boutique fermée ne vend plus : ses produits n'ont pas à
         remonter dans les résultats. */
      .filter((p) => !multiBoutiques() || !p.boutiqueId || ouvertes[p.boutiqueId])
      .map((p) => ({ produit: p, note: noteRecherche(p, mots) }))
      .filter((x) => x.note > 0)
      .sort((a, b) => b.note - a.note || parPrixCroissant(a.produit, b.produit))
      .map((x) => x.produit);
  }

  /** D'où vient un produit. La recherche traversant les boutiques, il
      faut pouvoir dire laquelle le vend — et dans quelle monnaie. */
  const boutiqueDuProduit = (p) =>
    (p && p.boutiqueId ? boutiques().find((b) => b.id === p.boutiqueId) : null) || null;

  /** La devise d'un produit : celle de sa boutique, sinon celle affichée. */
  const deviseDe = (p) => {
    const b = boutiqueDuProduit(p);
    return (b && b.devise) || boutique().devise;
  };

  /** Produits proches : même sous-catégorie d'abord, puis même catégorie. */
  function similaires(p, n = 4) {
    if (!p) return [];
    const autres = produits().filter((x) => x.id !== p.id);
    const memeSc = autres.filter((x) =>
      x.categorieId === p.categorieId && p.sousCategorieId && x.sousCategorieId === p.sousCategorieId);
    const memeCat = autres.filter((x) =>
      x.categorieId === p.categorieId && !memeSc.includes(x));
    return memeSc.concat(memeCat).slice(0, n);
  }

  /* ---------- Images ---------- */

  /** Les images du catalogue sont des URL complètes ; on tolère les anciens chemins. */
  function urlImage(chemin) {
    if (!chemin) return "";
    if (/^(https?:|data:)/.test(chemin)) return chemin;
    return String(chemin).replace(/^\.?\//, "");
  }

  const imagePrincipale = (p) => (p && p.images && p.images.length ? urlImage(p.images[0]) : "");

  return {
    charger, rafraichir, pret, depuisCache, modeDemo,
    definirPrixCompte, auxPrixRevendeur,
    estConfigure, majConfiguration, configuration,
    boutique, enseigne, versionPubliee,
    boutiques, multiBoutiques, boutiqueChoisie, choisirBoutique,
    quitterBoutique, nombreParBoutique,
    categories, categorie, sousCategories, sousCategorie,
    produits, produit, produitsDeCategorie,
    categoriesBizzoo, categoriesEnAvant, rayonsDeLaCategorie,
    rayonsDeLaBoutique, produitsDeLEnseigne,
    slides, slidesGeneral, publicites, misEnAvant,
    enVenteFlash, ventesFlash,
    nouveautes, promotions, meilleureRemise, produitsPopulaires,
    rechercher, similaires,
    boutiqueDuProduit, deviseDe,
    urlImage, imagePrincipale, statut, STATUTS, enAppro, joursAppro,
    signature, signalerAndroid,
  };
})();
