/* =========================================================
   Prix revendeur, ou prix publics, à l'écran (3.59.0)
   =========================================================
   Un revendeur validé achète au prix BIZZOO. Dans « Mon compte », deux
   boutons choisissent ce que l'application MONTRE :

     1. par défaut, ses prix revendeur — le prix public barré à côté, et
        « Votre prix revendeur » sur la fiche ;
     2. « Prix publics » : le catalogue, la fiche et l'accueil montrent
        les prix publics, sans rien de revendeur — pour les montrer à son
        propre client ;
     3. mais le PANIER dit toujours ce qu'il paiera : ses prix revendeur ;
     4. le choix tient sur ce téléphone, et se défait ;
     5. le partage d'un produit donne toujours le prix public ;
     6. un client ordinaire n'a pas ces boutons.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-prix-revendeur.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
const jwt = (c) => b64({ alg: "HS256" }) + "." + b64(c) + ".s";
const MOI = "66660000-0000-0000-0000-000000000006";
const plat = (s) => s.replace(/[  ]/g, " ").replace(/\s+/g, " ");

const BOUTIQUES = [{ id: "bou_a", nom: "Alpha", categorie_id: "cat_hightech", icone: "magasin",
  couleur: "#0047D9", devise: "FCFA", indicatif: "229", whatsapp: "97000001", actif: true, ordre: 1 }];
const PRODUIT = { id: "prod_1", boutique_id: "bou_a", nom: "Ordinateur", code: "0001", prix: 300000,
  categorie_id: "cat_hightech", sous_categorie_id: "sc_x", stock: 5, disponible: true, images: [],
  cree_le: "2026-09-01T08:00:00Z", modifie_le: "2026-09-01T08:00:00Z" };

async function ouvrir({ revendeur = true, hash = "#/produit/prod_1" } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1800 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(({ s }) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.setItem("bizzoo-session", JSON.stringify(s));
    localStorage.setItem("bizzoo-panier", JSON.stringify([{ produitId: "prod_1", quantite: 1 }]));
    window.__partages = [];
    Object.defineProperty(navigator, "share", { configurable: true,
      value: (d) => { window.__partages.push(d); return Promise.resolve(); } });
    window.__toasts = [];
    document.addEventListener("DOMContentLoaded", () => {
      const zone = document.querySelector("#toasts");
      if (zone) new MutationObserver(() => {
        for (const t of zone.querySelectorAll(".toast")) if (!t.__vu) { t.__vu = true; window.__toasts.push(t.textContent); }
      }).observe(zone, { childList: true });
    });
  }, { s: { access_token: jwt({ sub: MOI, phone: "2290196000666", email: "" }), refresh_token: "r",
    expire_a: Date.now() + 3600000, email: "", tel: "2290196000666" } });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.route("**/rest/v1/**", (route) => {
    const c = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c === "rpc/mes_prix") return d(revendeur ? [{ produit_id: "prod_1", prix: 240000 }] : []);
    if (c === "rpc/mon_compte_livreur") return d({ livreur: false, double: false });
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("clients")) return d([{ id: MOI, nom: "Kossi", tel: "0196000666", indicatif: "229",
      tel_verifie: true, type_compte: revendeur ? "revendeur" : "client",
      revendeur_etat: revendeur ? "validee" : "aucune", adresse: "Cotonou" }]);
    if (c.startsWith("profils")) return d([]);
    if (c.startsWith("reglages")) return d([{ compte_obligatoire: false }]);
    if (c.startsWith("paiement")) return d([{ id: 1, actif: true, fournisseur: "feexpay", taux_acompte: 10,
      frais_livraison: 1000 }]);
    if (c.startsWith("produits")) return d([PRODUIT]);
    if (c.startsWith("boutiques")) return d(BOUTIQUES);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html" + hash);
  await pause(3000);
  return { ctx, page, erreurs };
}
const vue = (page) => page.evaluate(() => document.getElementById("vue").innerText).then(plat);
const aller = async (page, h) => { await page.evaluate((x) => { location.hash = x; }, h); await pause(1500); };
const sansErreur = (o) => ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));

titre("1. Par défaut : ses prix revendeur");
const o = await ouvrir();
{
  const t = await vue(o.page);
  ok(/240 000 FCFA/.test(t) && /300 000 FCFA/.test(t) && /Votre prix revendeur/.test(t),
    "la fiche : 240 000, 300 000 barré, « Votre prix revendeur »");
  await aller(o.page, "#/compte");
  const c = await vue(o.page);
  ok(/Prix affichés dans l'application/.test(c) &&
     await o.page.evaluate(() => document.querySelector("#cp-rv-prix-revendeur").getAttribute("aria-pressed") === "true"),
    "« Mon compte » : les deux boutons, « Prix revendeur » choisi");
}

titre("2. « Prix publics » : le catalogue montre les prix publics");
{
  await o.page.click("#cp-rv-prix-publics");
  await pause(500);
  ok(/prix publics/.test(await o.page.evaluate(() => (window.__toasts || []).join(" "))) &&
     await o.page.evaluate(() => document.querySelector("#cp-rv-prix-publics").getAttribute("aria-pressed") === "true"),
    "le bouton se prend, et on le dit");
  ok(/Vos commandes restent à vos prix revendeur/.test(await vue(o.page)), "la carte rappelle que les commandes restent à son prix");
  await aller(o.page, "#/produit/prod_1");
  const t = await vue(o.page);
  ok(/300 000 FCFA/.test(t) && !/240 000/.test(t) && !/Votre prix revendeur/.test(t) && !/Prix revendeur/.test(t),
    "la fiche : 300 000, rien de revendeur");
  await aller(o.page, "#/");
  ok(!/240 000/.test(await vue(o.page)), "l'accueil non plus");
}

titre("3. Le panier dit toujours ce qu'il paiera");
{
  await aller(o.page, "#/panier");
  const t = await vue(o.page);
  ok(/240 000 FCFA/.test(t) && /Total à vos prix revendeur/.test(t), "panier : 240 000, « Total à vos prix revendeur »");
}

titre("5. Le partage donne le prix public");
{
  await aller(o.page, "#/produit/prod_1");
  await o.page.click("#p-partager").catch(() => {});
  await pause(600);
  const p = await o.page.evaluate(() => window.__partages[0] || {});
  ok(/300 000/.test(plat(p.text || "")) && !/240 000/.test(p.text || ""), "le texte partagé porte 300 000, jamais 240 000");
}

titre("4. Le choix tient sur ce téléphone, et se défait");
{
  await o.page.reload();
  await pause(3000);
  ok(/300 000 FCFA/.test(await vue(o.page)) && !/Votre prix revendeur/.test(await vue(o.page)),
    "rouverte, l'application garde les prix publics");
  await aller(o.page, "#/compte");
  await o.page.click("#cp-rv-prix-revendeur");
  await pause(400);
  await aller(o.page, "#/produit/prod_1");
  ok(/240 000 FCFA/.test(await vue(o.page)) && /Votre prix revendeur/.test(await vue(o.page)),
    "« Prix revendeur » : retour à ses prix");
  sansErreur(o);
  await o.ctx.close();
}

titre("6. Un client ordinaire n'a pas ces boutons");
{
  const c = await ouvrir({ revendeur: false, hash: "#/compte" });
  ok(!(await c.page.$("#cp-rv-prix-publics")) && !/Prix affichés/.test(await vue(c.page)), "pas de boutons");
  sansErreur(c);
  await c.ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " ÉCHEC(S)" : "\nTout tient ✔");
process.exit(echecs ? 1 : 0);
