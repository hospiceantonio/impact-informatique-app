/* =========================================================
   Service worker — l'application s'ouvre et se consulte
   hors connexion : coquille en cache, catalogue gardé par
   l'application (localStorage), photos Supabase gardées
   après le premier affichage.
   Incrémenter VERSION à chaque mise à jour des fichiers.
   ========================================================= */
const VERSION = "impact-client-v52";
const CACHE_PHOTOS = "impact-client-photos-v1";

const FICHIERS = [
  "./",
  "./index.html",
  "./styles.css",
  "./manifest.webmanifest",
  "./config.js",
  "./demo-catalogue.json",
  "./js/utils.js",
  "./js/catalogue.js",
  "./js/panier.js",
  "./js/paiement.js",
  "./js/live.js",
  "./js/ui.js",
  "./js/vues/accueil.js",
  "./js/vues/categories.js",
  "./js/vues/produit.js",
  "./js/vues/produits.js",
  "./js/vues/panier.js",
  "./js/vues/recherche.js",
  "./js/vues/infos.js",
  "./js/app.js",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/icon-maskable-512.png",
  "./icons/apple-touch-icon.png",
];

self.addEventListener("install", (ev) => {
  ev.waitUntil(
    caches.open(VERSION).then((cache) => cache.addAll(FICHIERS)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (ev) => {
  ev.waitUntil(
    caches.keys()
      .then((cles) => Promise.all(
        cles.filter((c) => c !== VERSION && c !== CACHE_PHOTOS).map((c) => caches.delete(c))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (ev) => {
  const requete = ev.request;
  if (requete.method !== "GET") return;
  const url = new URL(requete.url);

  /* Photos du stockage Supabase : cache d'abord, réseau en secours. */
  if (url.origin !== location.origin) {
    if (url.pathname.includes("/storage/v1/object/public/")
        && !/\.(mp4|mov|webm|3gp|mkv|avi)$/i.test(url.pathname)) {
      ev.respondWith(
        caches.match(requete).then((enCache) =>
          enCache ||
          fetch(requete).then((reponse) => {
            if (reponse && (reponse.ok || reponse.type === "opaque")) {
              const copie = reponse.clone();
              caches.open(CACHE_PHOTOS).then((cache) => cache.put(requete, copie));
            }
            return reponse;
          })
        )
      );
    }
    return; // le reste (base de données…) ne passe jamais par le cache
  }

  /* Coquille de l'application : cache d'abord, mise à jour silencieuse. */
  ev.respondWith(
    caches.match(requete, { ignoreSearch: true }).then((enCache) => {
      const depuisReseau = fetch(requete)
        .then((reponse) => {
          if (reponse && reponse.ok) {
            const copie = reponse.clone();
            caches.open(VERSION).then((cache) => cache.put(requete, copie));
          }
          return reponse;
        })
        .catch(() => enCache);
      return enCache || depuisReseau;
    })
  );
});
