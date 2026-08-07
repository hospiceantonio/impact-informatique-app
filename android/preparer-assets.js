/* =========================================================
   Copie les applications web dans les assets Android :
     ../client -> app/src/client/assets/www
     ../admin  -> app/src/admin/assets/www
   À lancer avant chaque build :  node preparer-assets.js
   ========================================================= */
const fs = require("fs");
const path = require("path");

const RACINE = __dirname;

for (const app of ["client", "admin"]) {
  const source = path.join(RACINE, "..", app);
  const cible = path.join(RACINE, "app", "src", app, "assets", "www");
  fs.rmSync(cible, { recursive: true, force: true });
  fs.mkdirSync(cible, { recursive: true });
  fs.cpSync(source, cible, {
    recursive: true,
    filter: (chemin) => !/serve\.ps1$/.test(chemin),
  });
  const nombre = fs.readdirSync(cible).length;
  console.log(app + " -> " + path.relative(RACINE, cible) + " (" + nombre + " entrées)");
}
