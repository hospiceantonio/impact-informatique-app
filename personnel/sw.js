/* =========================================================
   Service worker — la coquille de BIZZOO Personnel s'ouvre
   même sur un réseau faible ; les données, elles, vivent dans
   la base en ligne et ne sont JAMAIS mises en cache (salaires,
   mails : rien de cela ne doit rester dans un téléphone).
   Incrémenter VERSION à chaque mise à jour des fichiers.
   ========================================================= */
const VERSION = "bizzoo-personnel-v39";

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
  "./js/vues/incidents.js",
  "./js/vues/localiser.js",
  "./js/vues/livreurs.js",
  "./js/vues/argent.js",
  "./js/vues/controles.js",
  "./js/vues/qualite.js",
  "./js/vues/file.js",
  "./js/vues/bilans.js",
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

/* UNE ALERTE POUSSÉE (fonction Edge « rh-push ») : le message arrive
   chiffré, le navigateur le déchiffre et nous le remet. On l'affiche tel
   quel : la base n'y met ni montant ni nom de client. Une même tâche ne
   s'empile pas : son étiquette (tag) est la clé de la tâche, si bien que
   l'escalade ou l'alerte revenue remplace la notification précédente. */
self.addEventListener("push", (ev) => {
  let d = {};
  try { d = ev.data ? ev.data.json() : {}; } catch (_) { d = { corps: ev.data ? ev.data.text() : "" }; }
  ev.waitUntil(self.registration.showNotification(d.titre || "BIZZOO Personnel", {
    body: d.corps || "Une tâche vous attend dans « Ma file ».",
    icon: "./icons/icon-192.png",
    badge: "./icons/icon-192.png",
    tag: "rh-" + (d.tache || d.id || "alerte"),
    data: { lien: typeof d.lien === "string" && d.lien.startsWith("#/") ? d.lien : "#/file" },
  }));
});

/* Le toucher : l'application déjà ouverte va sur la file ; sinon elle s'ouvre dessus. */
self.addEventListener("notificationclick", (ev) => {
  ev.notification.close();
  const cible = new URL("./" + ((ev.notification.data && ev.notification.data.lien) || "#/file"), self.registration.scope).href;
  ev.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((fenetres) => {
    for (const f of fenetres) {
      if (f.url.startsWith(self.registration.scope) && "focus" in f) {
        return f.focus().then(() => f.navigate(cible)).catch(() => null);
      }
    }
    return self.clients.openWindow(cible);
  }));
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
