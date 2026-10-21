/* =========================================================
   Masquer un produit, à l'écran (3.59.0)
   =========================================================
   La base décide (supabase/tests/99zzzzzzzzzzzzzzzzzzz-produit-masque.sql).
   Ce banc regarde les deux applications :

     1. ADMIN : la fiche propose « Masquer le produit » — à un modérateur
        aussi, même sans le droit de modifier ; une confirmation, puis
        masquer_produit(id, true) ;
     2. un produit masqué porte « Masqué » dans la liste, et sa fiche
        propose « Réafficher le produit » ;
     3. CLIENT : le produit masqué n'apparaît nulle part — ni catalogue,
        ni recherche, ni fiche par son lien ; l'autre, si.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-produit-masque.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const jeton = (sub) => {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  return b64({ alg: "HS256" }) + "." + b64({ sub }) + ".s";
};
const MODO = "e1110000-0000-0000-0000-000000000001";
const PROD = (id, nom, o = {}) => ({ id, boutique_id: "bou_a", nom, code: "00" + id.slice(-2), prix: 5000,
  categorie_id: "cat_hightech", sous_categorie_id: "sc_x", stock: 5, disponible: true, images: [],
  masque: false, masque_par: "", masque_le: null,
  cree_le: "2026-10-01T08:00:00Z", modifie_le: "2026-10-01T08:00:00Z", ...o });
const BOU = [{ id: "bou_a", nom: "Alpha", categorie_id: "cat_hightech", icone: "magasin", couleur: "#0047D9",
  devise: "FCFA", indicatif: "229", whatsapp: "97000001", actif: true, ordre: 1 }];
const CATS = [{ id: "cat_hightech", nom: "High-tech", icone: "informatique", ordre: 1,
  sous_categories: [{ id: "sc_x", nom: "Accessoires", ordre: 1 }] }];

titre("1-2. Admin : un modérateur sans droit de modifier masque le produit");
{
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2000 } });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: a.t, refresh_token: "r", expire_a: Date.now() + 3600000, email: "modo@alpha.bj" }));
  }, { t: jeton(MODO) });
  const appels = [];
  let masque = false;
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c === "rpc/etat_connexion") return d({ equipe: true, sms_exige: false, session_confirmee: true, numero: true });
    if (c === "rpc/masquer_produit") {
      const corps = req.postDataJSON(); appels.push(corps); masque = corps.cacher; return d(corps.cacher);
    }
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("profils")) return d([{ id: MODO, email: "modo@alpha.bj", nom: "Modo", role: "moderateur",
      actif: true, peut_modifier_produits: false, boutique_id: "bou_a" }]);
    if (c.startsWith("produits")) return d([PROD("prod_01", "Casque", masque
      ? { masque: true, masque_par: "Modo", masque_le: "2026-10-20T10:00:00Z" } : {})]);
    if (c.startsWith("categories")) return d(CATS);
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  page.on("dialog", (dl) => dl.accept());
  await page.goto(BASE + "/admin/index.html#/produit/prod_01", { waitUntil: "domcontentloaded" });
  await pause(3000);
  ok(/Masquer le produit/.test(await page.evaluate(() => (document.querySelector("#p-masquer") || {}).textContent || "")),
    "la fiche propose « Masquer le produit », même sans le droit de modifier");
  await page.click("#p-masquer");
  await pause(500);
  const confirmer = await page.$('[data-role="ok"]');
  if (confirmer) await confirmer.click();
  await pause(1500);
  ok(appels.length === 1 && appels[0].cible === "prod_01" && appels[0].cacher === true,
    "masquer_produit(prod_01, true), après confirmation");
  const t = await page.evaluate(() => document.getElementById("vue").innerText);
  ok(/Masqué aux clients/.test(t) && /masqué par Modo/.test(t) && /Réafficher le produit/.test(t),
    "la fiche dit « Masqué aux clients — masqué par Modo », et propose de le réafficher");
  await page.evaluate(() => { location.hash = "#/produits"; });
  await pause(1500);
  ok(/Masqué/.test(await page.evaluate(() => document.getElementById("produits-liste").innerText)),
    "dans la liste, il porte « Masqué »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("3. Client : le produit masqué n'existe pas");
{
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2000 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(() => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
  });
  await page.route("**/rest/v1/**", (route) => {
    const c = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("produits")) return d([PROD("prod_01", "Casque masqué", { masque: true }), PROD("prod_02", "Souris visible")]);
    if (c.startsWith("categories")) return d(CATS);
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    if (c.startsWith("reglages")) return d([{ compte_obligatoire: false }]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html#/recherche", { waitUntil: "domcontentloaded" });
  await pause(3000);
  const ids = await page.evaluate(() => Catalogue.produits().map((p) => p.id));
  ok(ids.includes("prod_02") && !ids.includes("prod_01"), "le catalogue n'a que le produit visible");
  ok(await page.evaluate(() => Catalogue.produit("prod_01") === null), "la fiche du produit masqué : introuvable");
  await page.evaluate(() => { location.hash = "#/produit/prod_01"; });
  await pause(1200);
  ok(!/Casque masqué/.test(await page.evaluate(() => document.getElementById("vue").innerText)),
    "son lien partagé n'affiche pas le produit");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " ÉCHEC(S)" : "\nTout tient ✔");
process.exit(echecs ? 1 : 0);
