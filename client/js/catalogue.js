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
  const NB_EN_AVANT = 5;

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

  async function lireTable(c, chemin, signal) {
    const reponse = await fetch(c.url + "/rest/v1/" + chemin, {
      headers: { "apikey": c.cle },
      signal,
    });
    if (!reponse.ok) throw new Error("Catalogue indisponible (" + reponse.status + ")");
    return reponse.json();
  }

  async function telechargerDepuisBase(c) {
    const controleur = new AbortController();
    const minuterie = setTimeout(() => controleur.abort(), 15000);
    try {
      const [boutiques, categories, produits] = await Promise.all([
        lireTable(c, "boutique?select=*&id=eq.1", controleur.signal),
        lireTable(c, "categories?select=*,sous_categories(*)&order=ordre.asc", controleur.signal),
        lireTable(c, "produits?select=*&order=modifie_le.desc", controleur.signal),
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
          facebook: b.facebook || "",
          latitude: b.latitude === null || b.latitude === undefined ? null : Number(b.latitude),
          longitude: b.longitude === null || b.longitude === undefined ? null : Number(b.longitude),
          photos: (Array.isArray(b.photos) ? b.photos : []).map(urlImagePublique),
        },
        categories: (categories || []).map((cat) => ({
          id: cat.id,
          nom: cat.nom,
          ordre: cat.ordre || 0,
          sousCategories: (cat.sous_categories || [])
            .map((s) => ({ id: s.id, nom: s.nom, ordre: s.ordre || 0 }))
            .sort((a, x) => a.ordre - x.ordre),
        })),
        produits: (produits || []).map((p) => ({
          id: p.id,
          nom: p.nom,
          reference: p.reference || "",
          description: p.description || "",
          prix: Number(p.prix) || 0,
          ancienPrix: p.ancien_prix === null || p.ancien_prix === undefined ? null : Number(p.ancien_prix),
          categorieId: p.categorie_id,
          sousCategorieId: p.sous_categorie_id || "",
          disponible: p.disponible !== false,
          enAvant: !!p.en_avant,
          ordreAvant: p.ordre_avant || 0,
          images: (Array.isArray(p.images) ? p.images : []).map(urlImagePublique),
          video: p.video ? urlImagePublique(p.video) : "",
          creeLe: Date.parse(p.cree_le || "") || 0,
          modifieLe: Date.parse(p.modifie_le || "") || 0,
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
    if (change) document.dispatchEvent(new CustomEvent("catalogue:maj"));
    return change;
  }

  const pret = () => !!donnees;
  const depuisCache = () => source === "cache";
  const modeDemo = () => source === "demo";

  /* ---------- Boutique ---------- */

  function boutique() {
    const b = (donnees && donnees.boutique) || {};
    return {
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
      latitude: typeof b.latitude === "number" ? b.latitude : null,
      longitude: typeof b.longitude === "number" ? b.longitude : null,
      photos: Array.isArray(b.photos) ? b.photos : [],
    };
  }

  const versionPubliee = () => (donnees ? donnees.publieLe : null);

  /* ---------- Catégories ---------- */

  function categories() {
    const liste = (donnees && donnees.categories) || [];
    return liste.slice().sort((a, b) => (a.ordre || 0) - (b.ordre || 0));
  }

  const categorie = (id) => categories().find((c) => c.id === id) || null;

  function sousCategories(categorieId) {
    const c = categorie(categorieId);
    if (!c || !Array.isArray(c.sousCategories)) return [];
    return c.sousCategories.slice().sort((a, b) => (a.ordre || 0) - (b.ordre || 0));
  }

  function sousCategorie(categorieId, scId) {
    return sousCategories(categorieId).find((s) => s.id === scId) || null;
  }

  /* ---------- Produits ---------- */

  function produits() {
    return ((donnees && donnees.produits) || []).map((p) => ({
      ...p,
      disponible: p.disponible !== false,
      images: Array.isArray(p.images) ? p.images : [],
      video: p.video || "",
    }));
  }

  const produit = (id) => produits().find((p) => p.id === id) || null;

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

  /** Les produits mis en avant par la boutique (5 au maximum, ordonnés). */
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
    categories, categorie, sousCategories, sousCategorie,
    produits, produit, produitsDeCategorie, nombreParCategorie,
    misEnAvant, nouveautes, promotions, rechercher, similaires,
    urlImage, imagePrincipale,
  };
})();
