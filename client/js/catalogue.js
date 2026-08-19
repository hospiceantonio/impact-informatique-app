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

  let donnees = null;       // catalogue courant
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
      return {
        application: "impact-catalogue",
        version: 2,
        publieLe: b.maj_le || new Date().toISOString(),
        boutique: {
          nom: b.nom || "", slogan: b.slogan || "", description: b.description || "",
          tel: b.tel || "", whatsapp: b.whatsapp || "", indicatif: b.indicatif || "",
          devise: b.devise || "", adresse: b.adresse || "", horaires: b.horaires || "",
          facebook: b.facebook || "", instagram: b.instagram || "",
          tiktok: b.tiktok || "", youtube: b.youtube || "", snapchat: b.snapchat || "",
          latitude: b.latitude === null || b.latitude === undefined ? null : Number(b.latitude),
          longitude: b.longitude === null || b.longitude === undefined ? null : Number(b.longitude),
          photos: (Array.isArray(b.photos) ? b.photos : []).map(urlImagePublique),
          telephones: autresNumeros(b.telephones),
          adresses: autresAdresses(b.adresses),
        },
        boutiques: (lesBoutiques || []).map((b2) => ({
          id: b2.id,
          nom: b2.nom || "",
          secteur: b2.secteur || "",
          slogan: b2.slogan || "",
          description: b2.description || "",
          icone: b2.icone || "magasin",
          couleur: b2.couleur || "#1176D8",
          logo: b2.logo ? urlImagePublique(b2.logo) : "",
          actif: b2.actif !== false,
          ordre: b2.ordre || 0,
          tel: b2.tel || "", whatsapp: b2.whatsapp || "", indicatif: b2.indicatif || "",
          devise: b2.devise || "", adresse: b2.adresse || "", horaires: b2.horaires || "",
          facebook: b2.facebook || "", instagram: b2.instagram || "",
          tiktok: b2.tiktok || "", youtube: b2.youtube || "", snapchat: b2.snapchat || "",
          latitude: b2.latitude === null || b2.latitude === undefined ? null : Number(b2.latitude),
          longitude: b2.longitude === null || b2.longitude === undefined ? null : Number(b2.longitude),
          photos: (Array.isArray(b2.photos) ? b2.photos : []).map(urlImagePublique),
          telephones: autresNumeros(b2.telephones),
          adresses: autresAdresses(b2.adresses),
        })),
        categories: (categories || []).map((cat) => ({
          id: cat.id,
          boutiqueId: cat.boutique_id || "",
          nom: cat.nom,
          ordre: cat.ordre || 0,
          sousCategories: (cat.sous_categories || [])
            .map((s) => ({ id: s.id, nom: s.nom, ordre: s.ordre || 0 }))
            .sort((a, x) => a.ordre - x.ordre),
        })),
        produits: (produits || []).map((p) => ({
          id: p.id,
          boutiqueId: p.boutique_id || "",
          nom: p.nom,
          reference: p.reference || "",
          description: p.description || "",
          prix: Number(p.prix) || 0,
          ancienPrix: p.ancien_prix === null || p.ancien_prix === undefined ? null : Number(p.ancien_prix),
          categorieId: p.categorie_id,
          sousCategorieId: p.sous_categorie_id || "",
          stock: stockDeLigne(p),
          surCommande: !!p.sur_commande,
          enAvant: !!p.en_avant,
          ordreAvant: p.ordre_avant || 0,
          images: (Array.isArray(p.images) ? p.images : []).map(urlImagePublique),
          video: p.video ? urlImagePublique(p.video) : "",
          creeLe: Date.parse(p.cree_le || "") || 0,
          modifieLe: Date.parse(p.modifie_le || "") || 0,
          modifieLeBrut: p.modifie_le || "",   // tel quel : sert de repère aux notifications
        })),
        slides: (slides || []).map((s) => ({
          id: s.id,
          boutiqueId: s.boutique_id || "",
          image: s.image ? urlImagePublique(s.image) : "",
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
      donnees = enCache;
      source = "cache";
    }

    try {
      const frais = c ? await telechargerDepuisBase(c) : await telechargerDemo();
      const changement = donnees && JSON.stringify(frais) !== JSON.stringify(donnees);
      donnees = frais;
      source = c ? "reseau" : "demo";
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
   */
  async function rafraichir() {
    const c = configuration();
    if (!c) return false;
    let frais;
    try {
      frais = await telechargerDepuisBase(c);
    } catch (_) {
      return false; // hors connexion : on garde l'affichage actuel
    }
    const change = JSON.stringify(frais) !== JSON.stringify(donnees);
    donnees = frais;
    source = "reseau";
    ecrireCache(frais);
    signalerAndroid();
    if (change) document.dispatchEvent(new CustomEvent("catalogue:maj"));
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

  /** Une boutique par son identifiant, ouverte ou non (liens directs). */
  const laBoutique = (id) =>
    ((donnees && donnees.boutiques) || []).find((b) => b.id === id) || null;

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
    const b = boutiqueChoisie() || (donnees && donnees.boutique) || {};
    return {
      id: b.id || "",
      nom: b.nom || "IMPACT INFORMATIQUE",
      slogan: b.slogan || "Nous sommes imbattables en prix",
      description: b.description || "",
      tel: b.tel || "",
      whatsapp: b.whatsapp || b.tel || "69842516",
      indicatif: b.indicatif || "229",
      devise: b.devise || "FCFA",
      adresse: b.adresse || "",
      horaires: b.horaires || "",
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
    return ((donnees && donnees.produits) || []).filter(dansLaBoutique).map(normaliser);
  }

  /* Comme pour les rayons : un lien direct doit ouvrir la fiche même
     si la boutique visitée n'est pas encore la bonne. */
  const tousProduits = () => ((donnees && donnees.produits) || []).map(normaliser);
  const produit = (id) => tousProduits().find((p) => p.id === id) || null;

  /* Les trois états d'un produit, tels que le client les voit. */
  const STATUTS = {
    disponible: { nom: "Disponible", classe: "badge-disponible" },
    rupture: { nom: "En rupture", classe: "badge-rupture" },
    commande: { nom: "Sur commande", classe: "badge-commande" },
  };

  /**
   * « disponible » s'il reste des pièces, « rupture » s'il n'en reste
   * plus, « commande » pour un produit que la boutique ne tient pas.
   */
  function statut(p) {
    if (!p) return "rupture";
    if (p.surCommande) return "commande";
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

  function nombreParCategorie() {
    const table = {};
    for (const p of produits()) {
      table[p.categorieId] = (table[p.categorieId] || 0) + 1;
    }
    return table;
  }

  /* ---------- Slider ---------- */

  /** Les images que la boutique visitée fait défiler, dans son ordre. */
  function slides() {
    return ((donnees && donnees.slides) || [])
      .filter((s) => s.actif !== false && s.image && dansLaBoutique(s))
      .sort((a, b) => (a.ordre || 0) - (b.ordre || 0));
  }

  /**
   * Le slider de l'accueil : les images de TOUTES les boutiques ouvertes,
   * boutique par boutique dans l'ordre d'affichage, puis leur ordre à
   * elles. Chaque image sait d'où elle vient, pour mener au bon rayon.
   */
  function slidesGeneral() {
    const rangs = {};
    boutiques().forEach((b, i) => { rangs[b.id] = i; });
    return ((donnees && donnees.slides) || [])
      .filter((s) => s.actif !== false && s.image && (!s.boutiqueId || rangs[s.boutiqueId] !== undefined))
      .sort((a, b) =>
        (rangs[a.boutiqueId] || 0) - (rangs[b.boutiqueId] || 0) ||
        (a.ordre || 0) - (b.ordre || 0));
  }

  /** Les produits mis en avant de toutes les boutiques ouvertes. */
  function misEnAvantGeneral() {
    const rangs = {};
    boutiques().forEach((b, i) => { rangs[b.id] = i; });
    return tousProduits()
      .filter((p) => p.enAvant && (!p.boutiqueId || rangs[p.boutiqueId] !== undefined))
      .sort((a, b) =>
        (rangs[a.boutiqueId] || 0) - (rangs[b.boutiqueId] || 0) ||
        (a.ordreAvant || 0) - (b.ordreAvant || 0));
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

  function rechercher(terme) {
    const t = Utils.sansAccent(terme).trim();
    if (!t) return [];
    const mots = t.split(/\s+/);
    return produits()
      .filter((p) => {
        const cat = categorie(p.categorieId);
        const sc = sousCategorie(p.categorieId, p.sousCategorieId);
        const texte = Utils.sansAccent(
          p.nom + " " + (p.reference || "") + " " + (p.description || "") + " " +
          (cat ? cat.nom : "") + " " + (sc ? sc.nom : ""));
        return mots.every((mot) => texte.includes(mot));
      })
      .sort(parPrixCroissant);
  }

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
    estConfigure, majConfiguration, configuration,
    boutique, versionPubliee,
    boutiques, laBoutique, multiBoutiques, boutiqueChoisie, choisirBoutique,
    quitterBoutique, nombreParBoutique,
    categories, categorie, sousCategories, sousCategorie,
    produits, produit, produitsDeCategorie, nombreParCategorie,
    slides, slidesGeneral, misEnAvant, misEnAvantGeneral,
    nouveautes, promotions, rechercher, similaires,
    urlImage, imagePrincipale, statut, STATUTS,
    signature, signalerAndroid,
  };
})();
