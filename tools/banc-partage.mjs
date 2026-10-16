/* =========================================================
   Les liens de partage : boutique, catalogue, produit
   =========================================================
   CE QU'ON DÉFEND ICI.
     1. Un lien partagé ouvre DIRECTEMENT l'écran visé : la fiche
        d'une boutique, tout son catalogue, la fiche d'un produit.
     2. Le lien est toujours celui du site officiel, même quand on
        partage depuis une autre adresse (l'APK, une copie).
     3. Les boutons « Partager » passent par le partage du téléphone
        quand il existe (le pont Android), sinon par une feuille :
        WhatsApp, ou copier le lien.
     4. L'admin donne les mêmes liens, à copier.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-partage.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
const SITE = "https://www.bizzoomarket.com/client/#/";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const BOU = [
  { id: "bou_a", nom: "IMPACT", secteur: "Informatique", categorie_id: null, icone: "portable",
    couleur: "#0B5CF5", devise: "FCFA", indicatif: "229", actif: true, ordre: 1, whatsapp: "0197000000" },
  { id: "bou_b", nom: "MODE COTONOU", secteur: "Mode", categorie_id: null, icone: "tshirt",
    couleur: "#6C3FBF", devise: "FCFA", indicatif: "229", actif: true, ordre: 2, whatsapp: "0197000001" },
];
const produit = (id, nom, bou, prix) => ({ id, code: "1" + id.length, nom, reference: "", description: "",
  prix, ancien_prix: null, categorie_id: null, sous_categorie_id: null, stock: 5, disponible: true,
  sur_commande: false, appro_le: null, images: [], video: "", boutique_id: bou, en_avant: false,
  ordre_avant: 0, flash_fin: null, cree_le: "2026-10-01T10:00:00Z", modifie_le: "2026-10-01T10:00:00Z" });
const PRODUITS = [
  produit("prod_souris", "Souris sans fil", "bou_a", 5000),
  produit("prod_clavier", "Clavier", "bou_a", 9000),
  produit("prod_robe", "Robe wax", "bou_b", 15000),
];

async function ouvrirClient(hash, { pont = false, partageNavigateur = false } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1200 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(({ pont, partageNavigateur }) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.removeItem("impact-boutique");
    window.__partages = [];
    if (pont) window.AndroidPont = { partager: (t, x) => window.__partages.push({ par: "pont", t, x }) };
    if (!partageNavigateur) { try { delete Navigator.prototype.share; } catch (_) { /* rien */ } }
  }, { pont, partageNavigateur });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json",
    body: JSON.stringify({ external: { email: true, phone: true } }) }));
  await page.route("**/realtime/**", (r) => r.abort());
  await page.route("**/rest/v1/**", (r) => {
    const c = new URL(r.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("produits")) return d(PRODUITS);
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html" + hash, { waitUntil: "domcontentloaded" });
  await pause(1800);
  return { ctx, page, erreurs };
}

titre("1. Un lien ouvre directement l'écran visé");
{
  const o = await ouvrirClient("#/produit/prod_robe");
  ok(/Robe wax/.test(await o.page.evaluate(() => document.body.innerText)),
    "le lien d'un produit ouvre sa fiche");
  await o.ctx.close();
}
{
  const o = await ouvrirClient("#/boutique/bou_b");
  ok(/MODE COTONOU/.test(await o.page.evaluate(() => document.querySelector(".bou-fiche-nom")?.textContent || "")),
    "le lien d'une boutique ouvre sa fiche");
  await o.ctx.close();
}
{
  const o = await ouvrirClient("#/boutique/bou_b/produits");
  const texte = await o.page.evaluate(() => document.getElementById("vue").innerText);
  ok(/Robe wax/.test(texte) && !/Souris sans fil/.test(texte),
    "le lien du catalogue montre les produits de CETTE boutique, et seulement eux");
  ok(!o.erreurs.length, "aucune erreur dans la page" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

titre("2 et 3. Partager : le téléphone d'abord, sinon WhatsApp ou copier");
{
  const o = await ouvrirClient("#/produit/prod_souris", { pont: true });
  await o.page.click("#p-partager");
  await pause(200);
  const p = await o.page.evaluate(() => window.__partages);
  ok(p.length === 1 && p[0].par === "pont" && p[0].x.includes(SITE + "produit/prod_souris"),
    "dans l'application Android : le partage du téléphone, avec le lien officiel du produit");
  ok(/Souris sans fil/.test(p[0] ? p[0].x : ""), "et le nom du produit dans le message");
  await o.ctx.close();
}
{
  const o = await ouvrirClient("#/boutique/bou_a");
  await o.page.click("#bou-partager");
  await pause(300);
  const feuille = await o.page.evaluate(() => {
    const f = document.getElementById("feuille-partage");
    return f ? { lien: f.querySelector("input").value,
      wa: f.querySelector('a[href^="https://wa.me/?text="]')?.href || "" } : null;
  });
  ok(feuille && feuille.lien === SITE + "boutique/bou_a",
    "sans partage du téléphone : une feuille, avec le lien officiel de la boutique (" + (feuille && feuille.lien) + ")");
  ok(feuille && decodeURIComponent(feuille.wa).includes(SITE + "boutique/bou_a"),
    "et un bouton WhatsApp qui l'emporte");
  await o.ctx.close();
}
{
  const o = await ouvrirClient("#/boutique/bou_a/produits", { pont: true });
  const bouton = await o.page.$("#pr-partager");
  ok(!!bouton, "le catalogue d'une boutique a son bouton « Partager »");
  if (bouton) await bouton.click();
  await pause(200);
  const p = await o.page.evaluate(() => window.__partages);
  ok(p.length === 1 && p[0].x.includes(SITE + "boutique/bou_a/produits"),
    "il partage le lien du catalogue (" + (p[0] && p[0].x.split("\n").pop()) + ")");
  await o.ctx.close();
}

titre("4. L'admin donne les mêmes liens");
{
  const ctx = await nav.newContext({ viewport: { width: 390, height: 900 } });
  const page = await ctx.newPage();
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await pause(800);
  const liens = await page.evaluate(() => ({
    b: UI.lienPartage("boutique", "bou_a"),
    c: UI.lienPartage("catalogue", "bou_a"),
    p: UI.lienPartage("produit", "prod_souris"),
    html: UI.liensPartage([{ nom: "Ce produit", lien: UI.lienPartage("produit", "prod_souris") }]),
  }));
  ok(liens.b === SITE + "boutique/bou_a" && liens.c === SITE + "boutique/bou_a/produits" &&
     liens.p === SITE + "produit/prod_souris", "les trois liens sont ceux du client, au caractère près");
  ok(/data-copier="https:\/\/www\.bizzoomarket\.com\/client\/#\/produit\/prod_souris"/.test(liens.html) &&
     /wa\.me\/\?text=/.test(liens.html), "la carte propose « Copier » et « WhatsApp »");
  await ctx.close();
}

await nav.close();
console.log(echecs
  ? "\n\x1b[31m" + echecs + " constat(s) en échec ✘\x1b[0m"
  : "\n\x1b[32mUn lien partagé mène droit à la boutique, au catalogue ou au produit ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
