/* =========================================================
   Service worker — la coquille de l'application admin
   s'ouvre sans attendre le réseau ; les données, elles,
   vivent dans la base en ligne (jamais mises en cache).
   Incrémenter VERSION à chaque mise à jour des fichiers.
   ========================================================= */
const VERSION = "impact-admin-v76";

const FICHIERS = [
  "./",
  "./index.html",
  "./styles.css",
  /* LES POLICES DANS LA COQUILLE : sans elles, la première
     ouverture hors connexion retomberait sur la police du
     téléphone, et BIZZOO n'aurait plus l'air de BIZZOO. */
  "./polices/poppins-400.woff2",
  "./polices/poppins-500.woff2",
  "./polices/poppins-600.woff2",
  "./polices/poppins-700.woff2",
  "./manifest.webmanifest",
  "./config.js",
  "./js/utils.js",
  "./js/supabase.js",
  "./js/store.js",
  "./js/son.js",
  "./js/notifications.js",
  "./js/ui.js",
  "./js/vues/connexion.js",
  "./js/vues/accueil.js",
  "./js/vues/boutiques.js",
  "./js/vues/produits.js",
  "./js/vues/categories.js",
  "./js/vues/slider.js",
  "./js/vues/validations.js",
  "./js/vues/revendeurs.js",
  "./js/vues/clients.js",
  "./js/vues/versements.js",
  "./js/vues/codes.js",
  "./js/vues/livraisons.js",
  "./js/vues/avis.js",
  "./js/vues/sav.js",
  "./js/vues/commandes.js",
  "./js/vues/notifications.js",
  "./js/vues/statistiques.js",
  "./js/vues/historique.js",
  "./js/vues/comptes.js",
  "./js/vues/reglages.js",
  "./js/app.js",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/icon-maskable-512.png",
  "./icons/apple-touch-icon.png",
  /* Les illustrations des catégories : la liste et la fiche de
     l'admin les montrent, et la galerie de la fiche les propose. */
  "./img/categories/robe.jpg",
  "./img/categories/ordinateur.jpg",
  "./img/categories/voiture.jpg",
  "./img/categories/maison.jpg",
  "./img/categories/rouge-a-levres.jpg",
  "./img/categories/marmite.jpg",
  "./img/categories/chariot.jpg",
  "./img/categories/ecran.jpg",
  "./img/categories/nounours.jpg",
  "./img/categories/ballon.jpg",
  "./img/categories/briques.jpg",
  "./img/categories/livres.jpg",
  "./img/categories/bague.jpg",
  "./img/categories/chien.jpg",
  "./img/categories/boite-a-outils.jpg",
  "./img/categories/t-shirt.jpg",
  "./img/categories/telephone.jpg",
  "./img/categories/moto.jpg",
  "./img/categories/plante.jpg",
  "./img/categories/burger.jpg",
  "./img/categories/panier.jpg",
  "./img/categories/outils.jpg",
  "./img/categories/mallette.jpg",
  "./img/categories/poignee-de-main.jpg",
];

self.addEventListener("install", (ev) => {
  ev.waitUntil(
    caches.open(VERSION).then((cache) => cache.addAll(FICHIERS)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (ev) => {
  ev.waitUntil(
    caches.keys()
      .then((cles) => Promise.all(cles.filter((c) => c !== VERSION).map((c) => caches.delete(c))))
      .then(() => self.clients.claim())
  );
});

/* Cache d'abord (coquille locale), réseau en secours, mise à
   jour silencieuse. Les appels à la base (autre origine) ne
   passent jamais par le cache. */
self.addEventListener("fetch", (ev) => {
  const requete = ev.request;
  if (requete.method !== "GET") return;
  const url = new URL(requete.url);
  if (url.origin !== location.origin) return;

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
