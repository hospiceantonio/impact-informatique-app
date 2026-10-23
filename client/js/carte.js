/* =========================================================
   Carte — une carte avec une épingle qu'on déplace du doigt
   (3.64.0, la livraison au kilomètre).

   Leaflet est embarqué dans l'application (vendor/leaflet) : rien
   à charger d'un autre site que les tuiles de la carte, celles
   d'OpenStreetMap. Il ne se charge QUE quand une carte s'ouvre —
   l'accueil n'en paie pas le poids.

   Hors connexion, les tuiles manquent : la carte reste grise, mais
   l'épingle et « Utiliser ma position » marchent toujours. Rien ne
   dépend d'elle pour commander.
   ========================================================= */
const Carte = (() => {

  /* Cotonou, quand on ne sait rien d'autre. */
  const CENTRE = { latitude: 6.3654, longitude: 2.4183 };
  let chargement = null;

  function charger() {
    if (typeof window.L !== "undefined" && window.L.map) return Promise.resolve(window.L);
    if (chargement) return chargement;
    chargement = new Promise((resoudre, rejeter) => {
      if (!document.querySelector('link[data-leaflet]')) {
        const css = document.createElement("link");
        css.rel = "stylesheet";
        css.href = "vendor/leaflet/leaflet.css";
        css.setAttribute("data-leaflet", "");
        document.head.appendChild(css);
      }
      const js = document.createElement("script");
      js.src = "vendor/leaflet/leaflet.js";
      js.onload = () => {
        if (typeof window.L === "undefined") { chargement = null; rejeter(new Error("carte")); return; }
        window.L.Icon.Default.imagePath = "vendor/leaflet/images/";
        resoudre(window.L);
      };
      js.onerror = () => { chargement = null; rejeter(new Error("La carte n'a pas pu s'ouvrir.")); };
      document.head.appendChild(js);
    });
    return chargement;
  }

  /**
   * Monte une carte dans « element ». « options » :
   *   position   { latitude, longitude } où poser l'épingle (sinon le centre) ;
   *   centre     où regarder quand il n'y a pas d'épingle ;
   *   deplace    appelé avec { latitude, longitude } quand l'épingle bouge —
   *              on la pose aussi d'un toucher sur la carte ;
   *   repere     un second point, fixe (le point BIZZOO), facultatif.
   * Rend { placer(position), detruire() }.
   */
  async function monter(element, options) {
    const o = options || {};
    const L = await charger();
    const depart = o.position || o.centre || CENTRE;
    const carte = L.map(element, { zoomControl: true, attributionControl: true })
      .setView([depart.latitude, depart.longitude], o.position ? 15 : 12);
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: "© OpenStreetMap",
    }).addTo(carte);

    if (o.repere) {
      L.circleMarker([o.repere.latitude, o.repere.longitude],
        { radius: 7, color: "#2550B7", fillColor: "#2550B7", fillOpacity: 0.9 })
        .addTo(carte).bindTooltip(o.repereNom || "Point BIZZOO");
    }

    let epingle = null;
    const signaler = () => {
      if (!epingle || typeof o.deplace !== "function") return;
      const p = epingle.getLatLng();
      o.deplace({ latitude: Number(p.lat.toFixed(6)), longitude: Number(p.lng.toFixed(6)) });
    };
    function placer(position, recentrer) {
      if (!position) return;
      const ll = [position.latitude, position.longitude];
      if (!epingle) {
        epingle = L.marker(ll, { draggable: !!o.deplace, autoPan: true }).addTo(carte);
        epingle.on("dragend", signaler);
      } else {
        epingle.setLatLng(ll);
      }
      if (recentrer !== false) carte.setView(ll, Math.max(carte.getZoom(), 15));
    }
    if (o.position) placer(o.position, false);
    if (o.deplace) {
      carte.on("click", (e) => {
        placer({ latitude: e.latlng.lat, longitude: e.latlng.lng }, false);
        signaler();
      });
    }
    /* Une carte montée dans un bloc qui vient d'apparaître mesure zéro :
       elle se recalcule une fois posée. */
    setTimeout(() => carte.invalidateSize(), 60);

    return {
      placer,
      detruire: () => { try { carte.remove(); } catch (_) { /* déjà partie */ } },
    };
  }

  return { charger, monter, CENTRE };
})();
