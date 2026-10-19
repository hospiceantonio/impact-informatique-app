/* =========================================================
   Service worker — l'application s'ouvre et se consulte
   hors connexion : coquille en cache, catalogue gardé par
   l'application (localStorage), photos Supabase gardées
   après le premier affichage.
   Incrémenter VERSION à chaque mise à jour des fichiers.
   ========================================================= */
const VERSION = "impact-client-v109";
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
  "./js/pixel.js",
  "./js/droits-compte.js",
  "./legal/confidentialite.html",
  "./legal/mentions-legales.html",
  "./legal/conditions.html",
  "./legal/suppression-compte.html",
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
    /* « reload » : les fichiers du SERVEUR, jamais ceux que le navigateur
       aurait gardés de son côté — sinon une nouvelle version pouvait
       ranger d'anciens fichiers. */
    caches.open(VERSION)
      .then((cache) => cache.addAll(FICHIERS.map((f) => new Request(f, { cache: "reload" }))))
      .then(() => self.skipWaiting())
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

  /* LE RÉSEAU D'ABORD, la mémoire en secours (3.59.0). Avant, la
     coquille venait du cache d'abord : un téléphone qui avait déjà ouvert
     BIZZOO recevait l'ANCIENNE version à chaque lien ouvert, et la
     nouvelle seulement à la visite suivante — c'est ce qu'on voyait en
     cliquant un lien de partage après une mise à jour du site.
     Désormais : en ligne, la version du serveur ; hors connexion, ou
     réseau trop lent (plus de 4 s), celle gardée. */
  ev.respondWith(depuisReseauDAbord(requete));
});

function depuisReseauDAbord(requete) {
  const reseau = fetch(requete, { cache: "no-cache" }).then((reponse) => {
    if (reponse && reponse.ok) {
      const copie = reponse.clone();
      caches.open(VERSION).then((cache) => cache.put(requete, copie));
    }
    return reponse;
  });
  const garde = () => caches.match(requete, { ignoreSearch: true });
  return new Promise((resoudre) => {
    let fini = false;
    const rendre = (r) => { if (!fini && r) { fini = true; resoudre(r); } };
    /* Réseau trop lent : la version gardée, sans attendre. Le réseau
       continue, et rangera la nouvelle pour la prochaine fois. */
    const delai = setTimeout(() => garde().then(rendre), 4000);
    reseau
      .then((r) => { clearTimeout(delai); rendre(r); })
      .catch(() => {
        clearTimeout(delai);
        garde().then((r) => {
          if (r) rendre(r);
          else if (!fini) { fini = true; resoudre(Response.error()); }
        });
      });
  });
}

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
