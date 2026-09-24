/* =========================================================
   Service worker — l'application s'ouvre et se consulte
   hors connexion : coquille en cache, catalogue gardé par
   l'application (localStorage), photos Supabase gardées
   après le premier affichage.
   Incrémenter VERSION à chaque mise à jour des fichiers.
   ========================================================= */
const VERSION = "impact-client-v83";
const CACHE_PHOTOS = "impact-client-photos-v1";

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
  "./demo-catalogue.json",
  "./js/utils.js",
  "./js/catalogue.js",
  /* « compte.js » et « vues/compte.js » manquaient à cette liste depuis
     qu'ils existent : hors connexion, l'application se chargeait sans
     eux et « Compte » n'était pas défini. Une liste de fichiers à tenir
     à la main finit toujours par mentir — voir la note en fin de
     fichier. */
  "./js/compte.js",
  "./js/avis.js",
  "./js/sav.js",
  "./js/favoris.js",
  "./js/son.js",
  "./js/notifications.js",
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
  "./js/vues/compte.js",
  "./js/vues/avis.js",
  "./js/vues/sav.js",
  "./js/vues/favoris.js",
  "./js/vues/notifications.js",
  "./js/app.js",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/icon-maskable-512.png",
  "./icons/apple-touch-icon.png",
  /* LES ILLUSTRATIONS DES CATÉGORIES, dans la coquille : ce sont les
     ronds de l'accueil, et ils doivent être là dès la première
     ouverture hors connexion. Tenues à jour avec
     « tools/illustrations-categories.py » — le contrôle de la
     coquille refuse une image oubliée ici. */
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

/* =========================================================
   UNE LISTE À TENIR À LA MAIN FINIT PAR MENTIR.

   « compte.js » et « vues/compte.js » ont vécu deux étapes hors
   de cette liste : l'application les chargeait par le réseau
   sans jamais les mettre en cache, et hors connexion
   « Compte » n'était pas défini.

   Le contrôle « tools/coquille-complete.sh » compare désormais
   les balises « script » de index.html à cette liste, et
   s'arrête sur le premier écart. Un oubli ne dépend plus de qui
   relit.
   ========================================================= */
