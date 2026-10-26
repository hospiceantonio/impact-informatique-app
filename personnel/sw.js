/* =========================================================
   Service worker — la coquille de BIZZOO Personnel s'ouvre
   même sur un réseau faible ; les données, elles, vivent dans
   la base en ligne et ne sont JAMAIS mises en cache (salaires,
   mails : rien de cela ne doit rester dans un téléphone).
   Incrémenter VERSION à chaque mise à jour des fichiers.
   ========================================================= */
const VERSION = "bizzoo-personnel-v27";

const FICHIERS = [
  "./",
  "./index.html",
  "./styles.css",
  "./polices/poppins-400.woff2",
  "./polices/poppins-500.woff2",
  "./polices/poppins-600.woff2",
  "./polices/poppins-700.woff2",
  "./manifest.webmanifest",
  "./config.js",
  "./js/supabase.js",
  "./js/ui.js",
  "./js/xlsx.js",
  "./js/vues/connexion.js",
  "./js/vues/accueil.js",
  "./js/vues/mails.js",
  "./js/vues/discussions.js",
  "./js/vues/missions.js",
  "./js/vues/rapports.js",
  "./js/vues/depenses.js",
  "./js/vues/caisse.js",
  "./js/vues/solde.js",
  "./js/vues/prets.js",
  "./js/vues/employes.js",
  "./js/vues/profils.js",
  "./js/vues/paie.js",
  "./js/vues/statistiques.js",
  "./js/vues/suivi.js",
  "./js/vues/localiser.js",
  "./vendor/leaflet/leaflet.js",
  "./vendor/leaflet/leaflet.css",
  "./js/vues/parametres.js",
  "./js/vues/compte.js",
  "./js/app.js",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/icon-maskable-512.png",
  "./icons/apple-touch-icon.png",
];

self.addEventListener("install", (ev) => {
  ev.waitUntil(
    caches.open(VERSION)
      .then((cache) => cache.addAll(FICHIERS.map((f) => new Request(f, { cache: "reload" }))))
      .then(() => self.skipWaiting()));
});

self.addEventListener("activate", (ev) => {
  ev.waitUntil(
    caches.keys()
      .then((cles) => Promise.all(cles.filter((c) => c !== VERSION).map((c) => caches.delete(c))))
      .then(() => self.clients.claim()));
});

/* Le réseau d'abord ; la coquille gardée seulement si le réseau manque.
   Les appels à la base (autre origine) ne passent jamais par ici. */
self.addEventListener("fetch", (ev) => {
  const requete = ev.request;
  if (requete.method !== "GET") return;
  const url = new URL(requete.url);
  if (url.origin !== location.origin) return;
  ev.respondWith(
    fetch(requete)
      .then((reponse) => {
        if (reponse.ok && FICHIERS.some((f) => url.pathname.endsWith(f.replace(/^\.\//, "/")))) {
          const copie = reponse.clone();
          caches.open(VERSION).then((c) => c.put(requete, copie));
        }
        return reponse;
      })
      .catch(() => caches.match(requete).then((r) => r || caches.match("./index.html"))));
});
