/* =========================================================
   Service worker — la coquille de l'application admin
   s'ouvre sans attendre le réseau ; les données, elles,
   vivent dans la base en ligne (jamais mises en cache).
   Incrémenter VERSION à chaque mise à jour des fichiers.
   ========================================================= */
const VERSION = "impact-admin-v86";

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
  "./js/droits-compte.js",
  "./legal/confidentialite.html",
  "./legal/mentions-legales.html",
  "./legal/conditions.html",
  "./legal/suppression-compte.html",
  "./js/supabase.js",
  "./js/store.js",
  "./js/son.js",
  "./js/notifications.js",
  "./js/ui.js",
  "./js/conditions-ugc.js",
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
  "./icons/logo-bizzoo.png",
  /* LES ICÔNES DES CATÉGORIES (3.56) : celles des trois planches
     choisies par l'enseigne. Ce sont les tuiles de l'accueil : elles
     doivent être là dès la première ouverture hors connexion. Le
     contrôle de la coquille refuse une icône oubliée ici. */
  "./img/pictos/informatique.png",
  "./img/pictos/electromenager.png",
  "./img/pictos/energie.png",
  "./img/pictos/securite.png",
  "./img/pictos/telephones.png",
  "./img/pictos/bebe-enfant.png",
  "./img/pictos/livres-education.png",
  "./img/pictos/formation.png",
  "./img/pictos/maison-deco.png",
  "./img/pictos/jardinage.png",
  "./img/pictos/bricolage.png",
  "./img/pictos/immobilier.png",
  "./img/pictos/auto-moto.png",
  "./img/pictos/transport.png",
  "./img/pictos/mode.png",
  "./img/pictos/bijoux.png",
  "./img/pictos/beaute.png",
  "./img/pictos/sante.png",
  "./img/pictos/alimentation.png",
  "./img/pictos/restauration.png",
  "./img/pictos/agriculture.png",
  "./img/pictos/tracteur.png",
  "./img/pictos/animaux.png",
  "./img/pictos/sport-loisirs.png",
  "./img/pictos/musique.png",
  "./img/pictos/artisanat.png",
  "./img/pictos/cadeau.png",
  "./img/pictos/evenementiel.png",
  "./img/pictos/bureau.png",
  "./img/pictos/materiel-pro.png",
  "./img/pictos/imprimante.png",
  "./img/pictos/grossistes.png",
  "./img/pictos/cartons.png",
  "./img/pictos/services.png",
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
