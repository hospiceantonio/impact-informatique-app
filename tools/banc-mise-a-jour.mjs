/* =========================================================
   Une mise à jour du site se voit dès le lien suivant
   =========================================================
   Le constat qui a fait naître ce banc : après une mise à jour du site,
   un lien de partage ouvert sur un téléphone qui connaissait déjà
   BIZZOO montrait l'ANCIENNE version. Le service worker servait sa
   coquille gardée AVANT le réseau.

   Le banc rejoue la scène, pour chacune des deux applications :
     1. première visite (version A) : le service worker s'installe ;
     2. le site passe en version B ; on rouvre le lien : B, tout de suite ;
     3. le serveur coupé : l'application s'ouvre encore, depuis la mémoire.

   Sur une adresse locale, les applications refusent exprès d'installer
   leur service worker (voir app.js). Le banc travaille donc sur une
   COPIE, où ce refus est levé — les fichiers du dépôt ne sont pas
   touchés.
   ========================================================= */
import fs from "fs";
import os from "os";
import path from "path";
import { spawn } from "child_process";
import { fileURLToPath } from "url";

let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-mise-a-jour.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const RACINE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));

const COPIE = fs.mkdtempSync(path.join(os.tmpdir(), "bizzoo-maj-"));
const PORT = 5300 + Math.floor(Math.random() * 400);
let serveur = null;
const demarrer = async () => {
  serveur = spawn("python3", ["-m", "http.server", String(PORT), "--bind", "127.0.0.1", "--directory", COPIE],
    { stdio: "ignore" });
  await pause(800);
};
const arreter = async () => { if (serveur) serveur.kill(); serveur = null; await pause(400); };

const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

for (const appli of ["client", "admin"]) {
  titre("L'application " + appli);
  fs.rmSync(path.join(COPIE, appli), { recursive: true, force: true });
  fs.cpSync(path.join(RACINE, appli), path.join(COPIE, appli), { recursive: true });
  const app = path.join(COPIE, appli, "js", "app.js");
  const source = fs.readFileSync(app, "utf8");
  const leve = source.replace(/const enLocal = \[/, "const enLocal = false && [");
  ok(leve !== source, "copie : le refus des adresses locales est levé");
  fs.writeFileSync(app, leve);
  const page_ = path.join(COPIE, appli, "index.html");
  const marquer = (v) => {
    const s = fs.readFileSync(page_, "utf8").replace(/<meta name="banc-version" content="[^"]*">/, "");
    fs.writeFileSync(page_, s.replace("<head>", '<head><meta name="banc-version" content="' + v + '">'));
  };

  await demarrer();
  const ctx = await nav.newContext();
  const page = await ctx.newPage();
  const url = "http://127.0.0.1:" + PORT + "/" + appli + "/index.html#/";
  const lire = () => page.evaluate(() => (document.querySelector('meta[name="banc-version"]') || {}).content || "");

  marquer("A");
  await page.goto(url);
  await pause(1000);
  /* L'application enregistre son service worker en fin de démarrage —
     qui attend la base, absente ici. On l'enregistre comme elle le
     ferait, sans attendre. */
  await page.evaluate(() => navigator.serviceWorker.register("sw.js"));
  await pause(5000);
  ok(await page.evaluate(() => !!navigator.serviceWorker.controller),
    "première visite : le service worker est en place");

  marquer("B");
  await page.goto("about:blank");
  await page.goto(url);
  await pause(1500);
  const v = await lire();
  ok(v === "B", "le site mis à jour, le lien rouvert montre la NOUVELLE version (" + v + ")");

  await arreter();
  await page.goto("about:blank");
  await page.goto(url).catch(() => {});
  await pause(1500);
  const h = await lire();
  ok(h === "B", "serveur coupé : l'application s'ouvre encore, depuis la mémoire (" + h + ")");
  await ctx.close();
}

await nav.close();
fs.rmSync(COPIE, { recursive: true, force: true });
console.log(echecs ? "\n" + echecs + " constat(s) en échec." : "\nTous les constats sont bons.");
process.exit(echecs ? 1 : 0);
