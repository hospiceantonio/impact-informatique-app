/* =========================================================
   Banc — huit boutiques à la une, tirées au sort (3.70.0)

   L'accueil de l'application client n'affiche que HUIT boutiques
   partenaires (« Tout voir » ouvre la liste entière), tirées au sort et
   dans un ordre au hasard à CHAQUE arrivée sur l'accueil. Une mise à jour
   du catalogue, qui redessine l'écran, ne rebat pas les cartes sous les
   yeux du client.

     PLAYWRIGHT=… CHROMIUM=… BANC_URL=http://127.0.0.1:5191 node tools/banc-accueil-hasard.mjs
   ========================================================= */
const { chromium } = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default;
const BASE = process.env.BANC_URL || "http://127.0.0.1:5191";
const EXE = process.env.CHROMIUM || undefined;
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await chromium.launch(EXE ? { executablePath: EXE, args: ["--no-sandbox"] } : { args: ["--no-sandbox"] });

const boutiquesDe = (n) => Array.from({ length: n }, (_, i) => ({
  id: "bou_" + (i + 1), nom: "Boutique " + (i + 1), categorie_id: "cat_x", icone: "magasin", couleur: "#0047D9",
  devise: "FCFA", indicatif: "229", whatsapp: "9700000" + i, actif: true, ordre: i + 1 }));

async function ouvrir(n) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2400 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(() => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
  });
  const BOUTIQUES = boutiquesDe(n);
  await page.route("**/rest/v1/**", (route) => {
    const c = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("boutiques")) return d(BOUTIQUES);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    if (c.startsWith("paiement")) return d([{ id: 1, actif: false }]);
    if (c.startsWith("rpc/")) return d(null);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/client/index.html#/", { waitUntil: "domcontentloaded" });
  await pause(1800);
  return { page, ctx, erreurs };
}
const tuiles = (page) => page.$$eval(".bou-tuiles .bou-tuile", (t) => t.map((x) => x.dataset.boutique));
const aller = async (page, h) => { await page.evaluate((x) => { location.hash = x; }, h); await pause(700); };

titre("1. Huit au plus, « Tout voir » pour le reste");
{
  const { page, ctx, erreurs } = await ouvrir(12);
  const premiere = await tuiles(page);
  ok(premiere.length === 8, "12 boutiques : 8 à l'accueil (" + premiere.length + ")");
  ok(new Set(premiere).size === 8, "sans doublon");
  ok(await page.$('a[href="#/boutiques"]') !== null, "« Tout voir » mène à la liste entière");
  await aller(page, "#/boutiques");
  const toutes = await page.$$eval("[data-boutique]", (t) => new Set(t.map((x) => x.dataset.boutique)).size);
  ok(toutes === 12, "« Tout voir » : les 12 boutiques (" + toutes + ")");

  titre("2. Un nouveau tirage à chaque arrivée sur l'accueil");
  const vus = new Set([premiere.join(",")]);
  const touchees = new Set(premiere);
  for (let i = 0; i < 6; i++) {
    await aller(page, "#/");
    const t = await tuiles(page);
    vus.add(t.join(","));
    t.forEach((id) => touchees.add(id));
    await aller(page, "#/boutiques");
  }
  ok(vus.size >= 4, "7 arrivées : " + vus.size + " tirages différents (ordre ou boutiques)");
  ok(touchees.size >= 11, "au fil des visites, presque toutes les boutiques passent à la une (" + touchees.size + "/12)");
  const ordreCatalogue = premiere.every((id, i) => i === 0 || Number(id.split("_")[1]) > Number(premiere[i - 1].split("_")[1]));
  ok(!(ordreCatalogue && [...vus].every((v) => v === premiere.join(","))), "pas l'ordre du catalogue à chaque fois");

  titre("3. Une mise à jour du catalogue ne rebat pas les cartes");
  await aller(page, "#/");
  const avant = await tuiles(page);
  await page.evaluate(() => document.dispatchEvent(new CustomEvent("catalogue:maj", { detail: {} })));
  await pause(900);
  ok((await tuiles(page)).join(",") === avant.join(","), "l'écran redessiné garde les mêmes huit, dans le même ordre");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("4. Moins de huit boutiques : toutes, au hasard");
{
  const { page, ctx } = await ouvrir(3);
  const t = await tuiles(page);
  ok(t.length === 3 && new Set(t).size === 3, "3 boutiques : les 3 (" + t.join(", ") + ")");
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " échec(s)" : "\nTout passe.");
process.exit(echecs ? 1 : 0);
