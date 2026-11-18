/* =========================================================
   Le fond des cartes (4.8.0) — Google quand sa clé est réglée,
   OpenStreetMap sinon.

   Les cartes de BIZZOO sont dessinées par Leaflet (embarqué). Ce
   module ne choisit que LE FOND : les images de la carte.

   - Une clé de cartes est réglée (BIZZOO Admin → Réglages →
     « Cartes Google ») : les images viennent de Google (Map Tiles
     API, le service que Google prévoit pour un afficheur comme
     Leaflet), avec sa mention obligatoire.
   - Pas de clé, Google qui refuse, hors connexion : celles
     d'OpenStreetMap, comme avant. Une carte ne reste jamais vide
     à cause de Google.

   LA CLÉ EST PUBLIQUE PAR NATURE : le navigateur la joint à chaque
   image. Elle n'a rien à voir avec la clé du serveur ; chez Google,
   on la limite aux adresses de BIZZOO et à « Map Tiles API ».

   Ce fichier est le même dans les trois applications (client, admin,
   personnel) : modifier l'original (client), puis recopier.
   ========================================================= */
const FondCarte = (() => {
  const CLE_MEMOIRE = "bizzoo-fond-carte";
  const OSM = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";
  let cleConnue;          // undefined : pas encore demandée ; "" : aucune

  /** Où est la base : la configuration saisie, sinon celle du fichier. */
  function base() {
    let url = "", cle = "";
    try {
      const c = JSON.parse(localStorage.getItem("impact-config") || "null");
      if (c) { url = c.url || ""; cle = c.cle || ""; }
    } catch (_) { /* illisible */ }
    if (!url && typeof CONFIG !== "undefined") {
      url = CONFIG.SUPABASE_URL || "";
      cle = CONFIG.SUPABASE_ANON_KEY || "";
    }
    url = String(url).trim().replace(/\/+$/, "");
    cle = String(cle).trim();
    return url && cle ? { url, cle } : null;
  }
  const dansLeDelai = (promesse, ms) => Promise.race([promesse,
    new Promise((_, rejeter) => setTimeout(() => rejeter(new Error("délai")), ms))]);

  /** La clé des cartes, lue une fois par ouverture de l'application. */
  async function cleDesCartes() {
    if (cleConnue !== undefined) return cleConnue;
    const b = base();
    if (!b) { cleConnue = ""; return ""; }
    try {
      const r = await dansLeDelai(fetch(b.url + "/rest/v1/cartes_reglage?select=cle_tuiles&id=eq.1",
        { headers: { apikey: b.cle } }), 4000);
      const l = r.ok ? await r.json() : [];
      cleConnue = String((Array.isArray(l) && l[0] && l[0].cle_tuiles) || "").trim();
    } catch (_) {
      /* Base d'avant, hors connexion : pas de clé pour cette fois-ci. */
      return "";
    }
    return cleConnue;
  }

  /** La session de Google : demandée une fois, gardée jusqu'à son terme. */
  async function session(cle) {
    try {
      const m = JSON.parse(localStorage.getItem(CLE_MEMOIRE) || "null");
      if (m && m.cle === cle && m.session && Number(m.fin) > Date.now() + 3600000) return m.session;
    } catch (_) { /* illisible */ }
    const r = await dansLeDelai(fetch("https://tile.googleapis.com/v1/createSession?key=" + encodeURIComponent(cle), {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ mapType: "roadmap", language: "fr-FR", region: "BJ" }),
    }), 6000);
    if (!r.ok) throw new Error("Google : " + r.status);
    const d = await r.json();
    if (!d || !d.session) throw new Error("Google : pas de session");
    try {
      localStorage.setItem(CLE_MEMOIRE, JSON.stringify({ cle, session: d.session,
        fin: Number(d.expiry) > 0 ? Number(d.expiry) * 1000 : Date.now() + 86400000 }));
    } catch (_) { /* mémoire pleine : on redemandera */ }
    return d.session;
  }
  const oublierSession = () => { try { localStorage.removeItem(CLE_MEMOIRE); } catch (_) { /* rien */ } };

  function poserOsm(L, carte) {
    return L.tileLayer(OSM, { maxZoom: 19, attribution: "© OpenStreetMap" }).addTo(carte);
  }

  /**
   * Pose le fond sur « carte ». Rend "google" ou "osm". Ne lève jamais :
   * au moindre refus de Google, le fond d'OpenStreetMap prend la place.
   */
  async function poser(L, carte) {
    let cle = "";
    try { cle = await cleDesCartes(); } catch (_) { cle = ""; }
    if (!cle) { poserOsm(L, carte); return "osm"; }
    let jeton;
    try { jeton = await session(cle); } catch (_) { poserOsm(L, carte); return "osm"; }
    const calque = L.tileLayer("https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}?session=" +
      encodeURIComponent(jeton) + "&key=" + encodeURIComponent(cle),
      { maxZoom: 20, attribution: '<span class="fond-google" translate="no">Google</span> · Données cartographiques © Google' }).addTo(carte);
    /* Google refuse en route (clé retirée, quota, session morte) : au
       troisième refus, OpenStreetMap — et la session est oubliée. */
    let refus = 0;
    let tombe = false;
    calque.on("tileerror", () => {
      if (tombe || ++refus < 3) return;
      tombe = true;
      oublierSession();
      try { carte.removeLayer(calque); } catch (_) { /* déjà partie */ }
      try { poserOsm(L, carte); } catch (_) { /* carte fermée */ }
    });
    calque.on("tileload", () => { refus = 0; });
    return "google";
  }

  return { poser, cleDesCartes, oublier: () => { cleConnue = undefined; oublierSession(); } };
})();
