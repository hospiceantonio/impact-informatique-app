/* =========================================================
   Store — logique métier au-dessus de la base Supabase.

   Catégorie : { id, nom, ordre, sousCategories: [{ id, nom, ordre }] }
   Produit   : { id, nom, description, prix, ancienPrix,
                 categorieId, sousCategorieId, disponible,
                 enAvant, ordreAvant, images: [chemins],
                 vignette (URL), creeLe, modifieLe }

   Tout est enregistré directement en ligne : l'application
   client des visiteurs voit les modifications immédiatement.
   ========================================================= */
const Store = (() => {

  const MAX_EN_AVANT = 5;   // le slider client affiche 5 produits
  const MAX_PHOTOS = 4;

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
  };

  let reglages = { ...BOUTIQUE_DEFAUT };

  /* ---------- Correspondance base <-> application ---------- */

  const versMs = (iso) => {
    const t = Date.parse(iso || "");
    return isNaN(t) ? Date.now() : t;
  };

  function produitDepuisLigne(l) {
    const images = Array.isArray(l.images) ? l.images : [];
    return {
      id: l.id,
      nom: l.nom,
      reference: l.reference || "",
      description: l.description || "",
      prix: Number(l.prix) || 0,
      ancienPrix: l.ancien_prix === null || l.ancien_prix === undefined ? null : Number(l.ancien_prix),
      categorieId: l.categorie_id,
      sousCategorieId: l.sous_categorie_id || "",
      disponible: l.disponible !== false,
      enAvant: !!l.en_avant,
      ordreAvant: l.ordre_avant || 0,
      images,
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
      disponible: p.disponible,
      en_avant: p.enAvant,
      ordre_avant: p.ordreAvant,
      images: p.images,
      modifie_le: new Date().toISOString(),
    };
  }

  function boutiqueDepuisLigne(l) {
    return {
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
    };
  }

  /* ---------- Démarrage ---------- */

  async function init() {
    if (!Supabase.estConfigure()) {
      const err = new Error("Configuration requise");
      err.nonConfigure = true;
      throw err;
    }
    const lignes = await Supabase.requete("GET", "boutique?select=*&id=eq.1");
    if (lignes && lignes.length) reglages = boutiqueDepuisLigne(lignes[0]);
  }

  /* ---------- Réglages boutique ---------- */

  const lireReglages = () => ({ ...reglages });

  async function majReglages(maj) {
    reglages = { ...reglages, ...maj };
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
      maj_le: new Date().toISOString(),
    });
    return lireReglages();
  }

  /* ---------- Catégories ---------- */

  async function listerCategories() {
    const lignes = await Supabase.requete("GET",
      "categories?select=*,sous_categories(*)&order=ordre.asc");
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
      await Supabase.requete("POST", "categories", { id, nom, ordre });
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

    return lireCategorie(id);
  }

  async function supprimerCategorie(id) {
    const produits = await produitsDeCategorie(id);
    if (produits.length) {
      throw new Error("Impossible : " + produits.length + " produit" + (produits.length > 1 ? "s" : "") +
        " se trouve" + (produits.length > 1 ? "nt" : "") + " dans cette catégorie. Déplacez-les d'abord.");
    }
    await Supabase.requete("DELETE", "categories?id=eq." + encodeURIComponent(id));
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
  }

  /* ---------- Produits ---------- */

  async function listerProduits() {
    const lignes = await Supabase.requete("GET", "produits?select=*&order=modifie_le.desc");
    return (lignes || []).map(produitDepuisLigne);
  }

  async function lireProduit(id) {
    const lignes = await Supabase.requete("GET", "produits?select=*&id=eq." + encodeURIComponent(id));
    return lignes && lignes.length ? produitDepuisLigne(lignes[0]) : null;
  }

  async function produitsDeCategorie(categorieId) {
    const lignes = await Supabase.requete("GET",
      "produits?select=*&categorie_id=eq." + encodeURIComponent(categorieId));
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
  async function prochaineReference() {
    const produits = await listerProduits();
    let max = 0;
    for (const p of produits) {
      const m = /^IMP-(\d+)$/i.exec((p.reference || "").trim());
      if (m) max = Math.max(max, parseInt(m[1], 10));
    }
    return "IMP-" + String(max + 1).padStart(4, "0");
  }

  /**
   * Crée ou met à jour un produit.
   * `photosFinales` : liste ordonnée [{ id, chemin?, dataUrl? }] —
   * `chemin` pour une photo déjà en ligne, `dataUrl` pour une nouvelle.
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

    const prix = Math.round(Utils.lireNombre(donnees.prix));
    if (prix <= 0) throw new Error("Indiquez le prix de vente.");

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
        throw new Error("Déjà " + MAX_EN_AVANT + " produits mis en avant (le maximum du slider). Retirez-en un d'abord.");
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
    if (existant) {
      const retirees = (existant.images || []).filter((chemin) => !chemins.includes(chemin));
      await Supabase.supprimerImages(retirees);
    }

    const produit = {
      id: existant ? existant.id : Utils.uid("prod"),
      nom,
      reference,
      description: (donnees.description || "").trim(),
      prix,
      ancienPrix,
      categorieId: donnees.categorieId,
      sousCategorieId,
      disponible: donnees.disponible !== false,
      enAvant,
      ordreAvant,
      images: chemins,
    };

    const ligne = ligneDepuisProduit(produit);
    let lignes;
    if (existant) {
      lignes = await Supabase.requete("PATCH", "produits?id=eq." + encodeURIComponent(produit.id), ligne);
    } else {
      ligne.cree_le = new Date().toISOString();
      lignes = await Supabase.requete("POST", "produits", ligne);
    }
    return produitDepuisLigne(Array.isArray(lignes) ? lignes[0] : ligne);
  }

  async function supprimerProduit(id) {
    const produit = await lireProduit(id);
    if (produit) await Supabase.supprimerImages(produit.images || []);
    await Supabase.requete("DELETE", "produits?id=eq." + encodeURIComponent(id));
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

  /* ---------- Mise en avant (le slider client) ---------- */

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
        throw new Error("Déjà " + MAX_EN_AVANT + " produits mis en avant (le maximum du slider). Retirez-en un d'abord.");
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
    return produit;
  }

  async function basculerDisponible(id) {
    const produit = await lireProduit(id);
    if (!produit) throw new Error("Produit introuvable.");
    await Supabase.requete("PATCH", "produits?id=eq." + encodeURIComponent(id), {
      disponible: !produit.disponible,
      modifie_le: new Date().toISOString(),
    });
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
  }

  /* ---------- Statistiques ---------- */

  async function statistiques() {
    const [categories, produits] = await Promise.all([listerCategories(), listerProduits()]);
    return {
      categories: categories.length,
      produits: produits.length,
      enAvant: produits.filter((p) => p.enAvant).length,
      promotions: produits.filter((p) => Utils.remisePourcent(p.ancienPrix, p.prix) !== null).length,
      ruptures: produits.filter((p) => p.disponible === false).length,
      photos: produits.reduce((n, p) => n + (p.images || []).length, 0),
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
        disponible: p.disponible !== false,
        en_avant: !!p.enAvant,
        ordre_avant: p.ordreAvant || 0,
        images: chemins,
        modifie_le: new Date().toISOString(),
      }, { upsert: true });
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
    MAX_EN_AVANT, MAX_PHOTOS,
    init, lireReglages, majReglages,
    listerCategories, lireCategorie, sauverCategorie, supprimerCategorie, deplacerCategorie,
    listerProduits, lireProduit, produitsDeCategorie, chercherProduits, prochaineReference,
    sauverProduit, supprimerProduit, photosDeProduit,
    listerEnAvant, basculerEnAvant, deplacerEnAvant, basculerDisponible,
    statistiques, exporter, importer,
  };
})();
