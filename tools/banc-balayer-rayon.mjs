/* =========================================================
   Banc — balayer d'un produit à l'autre du rayon (3.73.0)

   Sur la fiche d'un produit (appli client) :
     1. une petite barre « ‹ 2 / 3 · Accessoires › » sous la photo ;
     2. un geste vers la gauche ouvre le SUIVANT du même rayon (dans
        l'ordre de l'écran du rayon : du moins cher au plus cher), vers la
        droite le PRÉCÉDENT ; au bout, on le dit et l'on reste ;
     3. « Retour » ramène à la liste d'où l'on venait, pas à travers les
        fiches balayées ;
     4. un geste sur les photos fait défiler les photos, pas les produits ;
        un geste vertical ne change rien ;
     5. les flèches font la même chose ; un produit seul dans son rayon
        n'a pas de barre ; un autre rayon n'est jamais traversé.

   Les gestes sont de vrais événements tactiles (Chrome DevTools).
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-balayer-rayon.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));

const PROD = (id, nom, prix, sc, o = {}) => ({ id, boutique_id: "bou_a", nom, code: "C" + id.slice(-1), prix,
  categorie_id: "cat_hightech", sous_categorie_id: sc, stock: 5, disponible: true, images: [],
  masque: false, cree_le: "2026-10-01T08:00:00Z", modifie_le: "2026-10-01T08:00:00Z", ...o });
/* Dans le désordre : c'est l'écran qui range, du moins cher au plus cher. */
const PRODUITS = [
  PROD("prod_c", "Clavier", 9000, "sc_x"),
  PROD("prod_a", "Câble", 2000, "sc_x"),
  PROD("prod_b", "Casque", 5000, "sc_x", { images: ["https://img.invalid/1.jpg", "https://img.invalid/2.jpg"] }),
  PROD("prod_d", "Lampe", 3000, "sc_y"),
];
const BOU = [{ id: "bou_a", nom: "Alpha", categorie_id: "cat_hightech", icone: "magasin", couleur: "#0047D9",
  devise: "FCFA", indicatif: "229", whatsapp: "97000001", actif: true, ordre: 1 }];
const CATS = [{ id: "cat_hightech", nom: "High-tech", icone: "informatique", ordre: 1,
  sous_categories: [{ id: "sc_x", nom: "Accessoires", ordre: 1 }, { id: "sc_y", nom: "Éclairage", ordre: 2 }] }];

const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const ctx = await nav.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true,
  serviceWorkers: "block" });
const page = await ctx.newPage();
const erreurs = [];
page.on("pageerror", (e) => erreurs.push(e.message));
await page.addInitScript(() => {
  localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
});
await page.route("https://img.invalid/**", (r) => r.fulfill({ status: 404, body: "" }));
await page.route("**/rest/v1/**", (route) => {
  const c = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
  const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
  if (c.startsWith("rpc/")) return d(null);
  if (c.startsWith("produits")) return d(PRODUITS);
  if (c.startsWith("categories")) return d(CATS);
  if (c.startsWith("boutiques")) return d(BOU);
  if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
  if (c.startsWith("reglages")) return d([{ compte_obligatoire: false }]);
  return d([]);
});
const cdp = await ctx.newCDPSession(page);

/** Un vrai geste du doigt, de (x1, y1) à (x2, y2). */
async function geste(x1, y1, x2, y2) {
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: x1, y: y1 }] });
  for (let i = 1; i <= 6; i++) {
    await cdp.send("Input.dispatchTouchEvent", { type: "touchMove",
      touchPoints: [{ x: x1 + (x2 - x1) * i / 6, y: y1 + (y2 - y1) * i / 6 }] });
    await pause(16);
  }
  await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await pause(700);
}
/** Le milieu du nom du produit : hors des photos. */
async function surLeNom() {
  const b = await page.locator(".fiche-nom").boundingBox();
  return { x: 195, y: b.y + b.height / 2 };
}
const etat = () => page.evaluate(() => ({
  hash: location.hash,
  nom: (document.querySelector(".fiche-nom") || {}).textContent || "",
  rang: (document.getElementById("p-rang") || {}).textContent || "",
  barre: (document.getElementById("fiche-rayon") || {}).innerText || "",
}));

titre("1. La barre du rayon, sous la photo");
await page.goto(BASE + "/client/index.html#/boutique/bou_a/produits", { waitUntil: "domcontentloaded" });
await pause(2500);
await page.evaluate(() => { location.hash = "#/produit/prod_b"; });
await pause(1200);
let e = await etat();
ok(e.nom === "Casque" && e.rang === "2 / 3", "le Casque est le 2e des 3 produits du rayon (" + e.rang + ")");
ok(/Accessoires/.test(e.barre) && /Balayez/.test(e.barre), "la barre nomme le rayon et invite à balayer");

titre("2. Balayer vers la gauche : le suivant ; vers la droite : le précédent");
let p = await surLeNom();
await geste(p.x + 120, p.y, p.x - 120, p.y + 10);
e = await etat();
ok(e.hash === "#/produit/prod_c" && e.nom === "Clavier" && e.rang === "3 / 3",
  "vers la gauche : le Clavier, le suivant par le prix (" + e.hash + ")");
p = await surLeNom();
await geste(p.x + 120, p.y, p.x - 120, p.y);
e = await etat();
ok(e.hash === "#/produit/prod_c", "au dernier, vers la gauche : on reste");
ok(/dernier produit de ce rayon/.test(await page.evaluate(() => document.body.innerText)), "… et on le dit");
p = await surLeNom();
await geste(p.x - 120, p.y, p.x + 120, p.y);
e = await etat();
ok(e.hash === "#/produit/prod_b" && e.rang === "2 / 3", "vers la droite : de retour au Casque (" + JSON.stringify(e) + ")");

titre("3. Un geste vertical, un geste sur les photos : pas de changement");
p = await surLeNom();
await geste(p.x + 30, p.y + 200, p.x - 20, p.y - 100);
ok((await etat()).hash === "#/produit/prod_b", "un défilement vertical ne change pas de produit");
const photo = await page.locator("#fiche-carrousel").boundingBox();
await geste(photo.x + 300, photo.y + photo.height / 2, photo.x + 60, photo.y + photo.height / 2);
ok((await etat()).hash === "#/produit/prod_b", "un geste sur les photos fait défiler les photos, pas les produits");
await page.evaluate(() => window.scrollTo(0, 0));

titre("4. Les flèches ; le premier n'a pas de « précédent »");
await page.click("#p-precedent");
await pause(800);
e = await etat();
ok(e.hash === "#/produit/prod_a" && e.nom === "Câble" && e.rang === "1 / 3", "‹ : le Câble, le moins cher");
ok(await page.locator("#p-precedent").isDisabled(), "au premier, ‹ est grisé");
await page.click("#p-suivant");
await pause(800);
ok((await etat()).hash === "#/produit/prod_b", "› : de nouveau le Casque");

titre("5. « Retour » : la liste d'où l'on venait");
await page.evaluate(() => history.back());
await pause(1200);
ok((await etat()).hash === "#/boutique/bou_a/produits",
  "un seul retour ramène à la liste, pas aux fiches balayées (" + (await etat()).hash + ")");

titre("6. Seul dans son rayon : pas de barre, pas de geste");
await page.evaluate(() => { location.hash = "#/produit/prod_d"; });
await pause(1200);
ok(!(await page.locator("#fiche-rayon").count()), "la Lampe, seule en Éclairage : pas de barre");
p = await surLeNom();
await geste(p.x + 120, p.y, p.x - 120, p.y);
ok((await etat()).hash === "#/produit/prod_d", "balayer ne mène pas dans un autre rayon");

titre("7. Hors de la fiche, le geste ne fait rien");
await page.evaluate(() => { location.hash = "#/boutique/bou_a/produits"; });
await pause(1200);
await geste(320, 500, 80, 500);
ok((await etat()).hash === "#/boutique/bou_a/produits", "sur la liste, balayer ne mène à aucune fiche");
ok(!(await page.evaluate(() => document.getElementById("vue").className)).includes("fiche-entre"),
  "l'écran suivant ne garde pas le glissé de la fiche");
ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));

await nav.close();
console.log(echecs ? "\n" + echecs + " ÉCHEC(S)" : "\nTout tient ✔");
process.exit(echecs ? 1 : 0);
