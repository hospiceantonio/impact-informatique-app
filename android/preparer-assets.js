/* =========================================================
   Copie les applications web dans les assets Android :
     ../client -> app/src/client/assets/www
     ../admin  -> app/src/admin/assets/www
   À lancer avant chaque build :  node preparer-assets.js
   ========================================================= */
const fs = require("fs");
const path = require("path");

const RACINE = __dirname;

/* (4.3.1) LES ANCIENS NOMS DES ICÔNES restent sur le site, avec le
   nouveau logo, pour les adresses déjà parties (voir tools/make-icons.js).
   Dans un APK, ils ne servent à rien : l'application ne lit que les noms
   neufs. On ne les embarque pas. */
const ANCIENNES_ICONES = /[\\/]icons[\\/](icon-192|icon-512|icon-maskable-512|apple-touch-icon|logo-bizzoo|icone-market-192|icone-market-512|icone-market-maskable-512|apple-touch-icon-market|logo-bizzoo-market)\.png$/;

for (const app of ["client", "admin"]) {
  const source = path.join(RACINE, "..", app);
  const cible = path.join(RACINE, "app", "src", app, "assets", "www");
  fs.rmSync(cible, { recursive: true, force: true });
  fs.mkdirSync(cible, { recursive: true });
  fs.cpSync(source, cible, {
    recursive: true,
    filter: (chemin) => !/serve\.ps1$/.test(chemin) && !ANCIENNES_ICONES.test(chemin),
  });
  const nombre = fs.readdirSync(cible).length;
  console.log(app + " -> " + path.relative(RACINE, cible) + " (" + nombre + " entrées)");
}
