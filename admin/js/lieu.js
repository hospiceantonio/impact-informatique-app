/* =========================================================
   Lieu — le nom d'un point de la carte, et un lieu par son nom
   (3.76.0). Le même fichier dans l'application client et dans
   l'administration.

     Lieu.nommer({ latitude, longitude })  → « Sèdomey, Togoudo, Godomey »
                                              (ou null : jamais d'erreur)
     Lieu.chercher("Tempé")                 → [{ nom, detail, latitude, longitude }]
     Lieu.monterRecherche(element, choisir) → un champ « Chercher un lieu »
                                              et ses résultats ; « choisir »
                                              reçoit le lieu touché.

   Tout passe par la fonction serveur « lieu » (OpenStreetMap derrière
   elle, et un cache en base). Ici, un second cache, sur le téléphone :
   un point déjà nommé ne se redemande pas.

   La recherche part quand on la demande (« Chercher », ou Entrée), pas
   à chaque lettre : la source l'exige, et c'est plus clair.
   ========================================================= */
const Lieu = (() => {

  const CLE_CACHE = "bizzoo-lieux";
  const MAX_CACHE = 300;
  /* La grille de la base (0,0005°, ≈ 55 m) : deux points dans la même
     case portent le même nom. */
  const grille = (x) => Math.round(Number(x) * 2000) / 2000;
  const cle = (p) => grille(p.latitude).toFixed(4) + "," + grille(p.longitude).toFixed(4);
  const valable = (p) => !!p && isFinite(p.latitude) && isFinite(p.longitude) &&
    Number(p.latitude) !== 0 && Number(p.longitude) !== 0;

  let inactive = false;              // fonction absente : on ne redemande plus
  const enCours = new Map();

  function configuration() {
    let url = "", c = "";
    try {
      const brut = localStorage.getItem("impact-config");
      if (brut) { const x = JSON.parse(brut); url = x.url || ""; c = x.cle || ""; }
    } catch (_) { /* configuration locale illisible */ }
    if (!url && typeof CONFIG !== "undefined") {
      url = CONFIG.SUPABASE_URL || "";
      c = CONFIG.SUPABASE_ANON_KEY || "";
    }
    url = String(url).trim().replace(/\/+$/, "");
    c = String(c).trim();
    return /^https:\/\//.test(url) && c ? { url, cle: c } : null;
  }

  function lireCache() {
    try { return JSON.parse(localStorage.getItem(CLE_CACHE) || "{}") || {}; } catch (_) { return {}; }
  }
  function ecrireCache(k, nom) {
    try {
      const c = lireCache();
      delete c[k];
      c[k] = nom;
      const cles = Object.keys(c);
      for (let i = 0; i < cles.length - MAX_CACHE; i++) delete c[cles[i]];
      localStorage.setItem(CLE_CACHE, JSON.stringify(c));
    } catch (_) { /* navigation privée : on redemandera */ }
  }

  async function appeler(corps) {
    if (inactive) return null;
    const c = configuration();
    if (!c) return null;
    const arret = new AbortController();
    const minuteur = setTimeout(() => arret.abort(), 10000);
    try {
      const r = await fetch(c.url + "/functions/v1/lieu", {
        method: "POST",
        headers: { "apikey": c.cle, "Content-Type": "application/json" },
        body: JSON.stringify(corps),
        signal: arret.signal,
      });
      if (r.status === 404) { inactive = true; return null; }   // pas encore déployée
      return await r.json().catch(() => null);
    } catch (_) {
      return null;                                               // réseau : on redemandera
    } finally {
      clearTimeout(minuteur);
    }
  }

  /** Le nom déjà connu d'un point, sans rien demander (ou ""). */
  function connu(p) {
    if (!valable(p)) return "";
    return String(lireCache()[cle(p)] || "");
  }

  /** Le nom d'un point : « Quartier, Arrondissement, Ville », ou null. */
  function nommer(p) {
    if (!valable(p)) return Promise.resolve(null);
    const k = cle(p);
    const deja = connu(p);
    if (deja) return Promise.resolve(deja);
    if (enCours.has(k)) return enCours.get(k);
    const promesse = appeler({ action: "nommer", latitude: Number(p.latitude), longitude: Number(p.longitude) })
      .then((d) => {
        enCours.delete(k);
        const nom = d && typeof d.nom === "string" ? d.nom.trim() : "";
        if (!nom) return null;
        ecrireCache(k, nom);
        return nom;
      });
    enCours.set(k, promesse);
    return promesse;
  }

  /** Les lieux de ce nom au Bénin (le Grand Cotonou d'abord). */
  async function chercher(q) {
    const texte = String(q || "").replace(/\s+/g, " ").trim();
    if (texte.length < 2) return [];
    const d = await appeler({ action: "chercher", q: texte });
    if (!d) throw new Error("La recherche ne répond pas. Vérifiez la connexion, ou touchez la carte.");
    const liste = Array.isArray(d.resultats) ? d.resultats : [];
    if (!liste.length && d.message) throw new Error(d.message === "Plafond du jour atteint."
      ? "La recherche est saturée pour aujourd'hui : touchez la carte pour poser l'épingle."
      : "La recherche ne répond pas : touchez la carte pour poser l'épingle.");
    return liste.filter((x) => valable(x)).map((x) => {
      const r = { nom: String(x.nom || "").trim(), detail: String(x.detail || "").trim(),
                  latitude: Number(x.latitude), longitude: Number(x.longitude) };
      if (r.nom) ecrireCache(cle(r), r.nom);
      return r;
    });
  }

  const echapper = (s) => String(s == null ? "" : s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

  /**
   * Un champ « Chercher un lieu » et ses résultats, dans « element ».
   * « choisir » reçoit { nom, detail, latitude, longitude }.
   */
  function monterRecherche(element, choisir, options) {
    if (!element) return;
    const o = options || {};
    const id = o.id || "lieu-q";
    element.innerHTML =
      '<div class="lieu-recherche">' +
        '<input id="' + id + '" type="search" enterkeyhint="search" autocomplete="off" ' +
          'aria-label="Chercher un lieu" placeholder="' +
          echapper(o.indication || "Quartier : Tempé, Agla…") + '">' +
        '<button type="button" class="btn btn-clair lieu-chercher">Chercher</button>' +
      "</div>" +
      '<div class="lieu-resultats" role="list"></div>';
    const champ = element.querySelector("input");
    const bouton = element.querySelector(".lieu-chercher");
    const zone = element.querySelector(".lieu-resultats");
    let trouves = [];

    async function lancer() {
      const q = champ.value.trim();
      if (q.length < 2) { champ.focus(); return; }
      bouton.disabled = true;
      zone.innerHTML = '<p class="aide lieu-msg"><span class="chargement-rond"></span>Recherche…</p>';
      try {
        trouves = await chercher(q);
        zone.innerHTML = trouves.length
          ? trouves.map((x, i) =>
              '<button type="button" class="lieu-resultat" role="listitem" data-i="' + i + '">' +
                "<strong>" + echapper(x.nom || x.detail) + "</strong>" +
                (x.detail && x.detail !== x.nom ? "<span>" + echapper(x.detail) + "</span>" : "") +
              "</button>").join("")
          : '<p class="aide lieu-msg">Aucun lieu trouvé à ce nom. Essayez un quartier voisin, ' +
              "ou touchez la carte là où livrer.</p>";
      } catch (err) {
        trouves = [];
        zone.innerHTML = '<p class="aide lieu-msg">' + echapper(err.message) + "</p>";
      }
      bouton.disabled = false;
    }
    bouton.addEventListener("click", lancer);
    champ.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); lancer(); }
    });
    zone.addEventListener("click", (e) => {
      const b = e.target.closest(".lieu-resultat");
      if (!b) return;
      const x = trouves[Number(b.getAttribute("data-i"))];
      if (!x) return;
      zone.innerHTML = "";
      champ.value = "";
      if (typeof choisir === "function") choisir(x);
    });
  }

  return { nommer, connu, chercher, monterRecherche };
})();
