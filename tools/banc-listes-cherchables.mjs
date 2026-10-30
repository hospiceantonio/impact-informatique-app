/* =========================================================
   Les listes qui se cherchent (3.72.0)
   =========================================================
   Là où l'on choisit une boutique, un livreur : par ordre alphabétique,
   et un champ pour taper quelques lettres.
     1. « Créer un livreur » : la boutique se cherche ;
     2. la page « Livreurs » : par ordre alphabétique, et un champ ;
     3. la page « Boutiques » : le choix de la boutique ouverte, A → Z,
        et un champ ;
     4. « Comptes » : une section par rang (administrateurs, modérateurs),
        et des cartes vers les livreurs, les vendeurs, les revendeurs.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-listes-cherchables.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const corpsDe = (req) => { try { return req.postDataJSON(); } catch (_) { return null; } };
const jeton = (moi) => {
  const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return b64({ alg: "HS256" }) + "." + b64({ sub: moi }) + ".s";
};
const GEO = () => {
  Object.defineProperty(navigator, "geolocation", { configurable: true, value: {
    getCurrentPosition: (ok) => setTimeout(() =>
      ok({ coords: { latitude: 6.3654, longitude: 2.4183, accuracy: 12 } }), 30) } });
};

const SUPER = "11110000-0000-0000-0000-000000000001";
const MODO = "22220000-0000-0000-0000-000000000002";
const LIV_OK = "33330000-0000-0000-0000-000000000003";
const LIV_NON = "44440000-0000-0000-0000-000000000004";
const P = (id, email, role, extra) => ({ id, email, role, actif: true, peut_modifier_produits: true,
  boutique_id: role === "superadministrateur" ? null : "bou_a", nom: "", tel: "0197000000",
  ...(extra || {}) });
const PROFILS = [
  P(SUPER, "chef@bizzoo.bj", "superadministrateur"),
  ...["Zinsou", "Bello", "Ayaba", "Mensah", "Dossa"].map((n, i) =>
    P("5555000" + i + "-0000-0000-0000-00000000000" + i, n.toLowerCase() + "@bizzoo.bj", "livreur", { nom: n, boutique_id: null })),
  P(MODO, "modo@alpha.bj", "moderateur", { nom: "Awa" }),
  P(LIV_OK, "rohim@alpha.bj", "livreur", { nom: "Rohim" }),
  P(LIV_NON, "codjo@alpha.bj", "livreur", { nom: "Codjo" }),
];
/* Huit boutiques, rangées pour les clients dans un ordre qui n'est pas alphabétique. */
const BOU = ["Zoo Market", "Alpha", "Mode Afrika", "Beauté Plus", "Électro Bénin", "Garba Attitude", "Kpakpato", "Delta Shop"]
  .map((nom, i) => ({ id: i === 1 ? "bou_a" : "bou_" + i, nom, categorie_id: null, icone: "magasin", couleur: "#0047D9",
    devise: "FCFA", indicatif: "229", actif: true, ordre: i + 1 }));

async function ouvrirAdmin(moi, { hash = "", positions = { [LIV_OK]: true }, ancienne = false,
                                  revendeurs = [] } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1600 } });
  const page = await ctx.newPage();
  const erreurs = [];
  const appels = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: a.t, refresh_token: "r", expire_a: Date.now() + 3600000, email: a.email }));
  }, { t: jeton(moi), email: PROFILS.find((p) => p.id === moi).email });
  await page.addInitScript(GEO);
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x, s = 200) => route.fulfill({ status: s, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) appels.push({ nom: c.slice(4), corps: corpsDe(req) });
    if (c === "rpc/enregistrer_ma_position") { positions[moi] = true; return d({ ok: true }); }
    if (c === "rpc/revendeurs") return d(revendeurs);
    if (c === "rpc/mes_livraisons") return d([]);
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("positions_livreurs")) {
      if (ancienne) return d({ code: "42P01", message: "relation \"public.positions_livreurs\" does not exist" }, 404);
      const voulu = (u.searchParams.get("profil_id") || "").replace(/^eq\./, "");
      return d(Object.keys(positions).filter((id) => positions[id] && (!voulu || id === voulu))
        .map((id) => ({ profil_id: id, latitude: 6.36, longitude: 2.41, adresse: "Akpakpa",
          enregistre_le: "2026-10-16T08:00:00Z" })));
    }
    if (c.startsWith("profils")) {
      const id = (u.searchParams.get("id") || "").replace(/^eq\./, "");
      return d(id ? PROFILS.filter((p) => p.id === id) : PROFILS);
    }
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await pause(2000);
  if (hash) { await page.evaluate((h) => { location.hash = h; }, hash); await pause(1500); }
  return { ctx, page, erreurs, appels };
}
const texte = (page) => page.evaluate(() => document.getElementById("vue").innerText.replace(/\s+/g, " "));
const options = (page, sel) => page.$$eval(sel + " option", (o) => o.map((x) => x.textContent.trim()));

titre("1. « Créer un livreur » : la boutique se cherche");
{
  const o = await ouvrirAdmin(SUPER, { hash: "#/livreurs" });
  await o.page.click("#lv-nouveau");
  await pause(500);
  const liste = await options(o.page, "#nc-boutique");
  ok(liste[0] === "BIZZOO — toutes les boutiques", "« BIZZOO — toutes les boutiques » reste en tête");
  const noms = liste.slice(1);
  ok(JSON.stringify(noms) === JSON.stringify(noms.slice().sort((a, b) => a.localeCompare(b, "fr", { sensitivity: "base" }))),
    "les boutiques par ordre alphabétique (" + noms.join(", ") + ")");
  ok(!!(await o.page.$("#nc-boutique-chercher")), "un champ « Rechercher une boutique… » au-dessus");
  await o.page.fill("#nc-boutique-chercher", "garba");
  await pause(200);
  ok(JSON.stringify(await options(o.page, "#nc-boutique")) === JSON.stringify(["Garba Attitude"]) &&
     await o.page.$eval("#nc-boutique", (s) => s.value) === "bou_5",
    "« garba » : seule Garba Attitude reste, et elle est choisie");
  await o.page.fill("#nc-boutique-chercher", "electro");
  await pause(200);
  ok(await o.page.$eval("#nc-boutique", (s) => s.value) === "bou_4", "sans accent : « electro » trouve Électro Bénin");
  await o.page.fill("#nc-boutique-chercher", "xyz");
  await pause(200);
  ok(await o.page.$eval("#nc-boutique + .recherche-liste-vide", (n) => !n.hidden) &&
     await o.page.$eval("#nc-boutique", (s) => s.value) === "bou_4", "rien ne correspond : on le dit, le choix reste");
  await o.page.fill("#nc-boutique-chercher", "");
  await pause(200);
  ok((await options(o.page, "#nc-boutique")).length === 9, "champ vidé : toute la liste revient");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

titre("2. La page « Livreurs » : A → Z, et un champ");
{
  const o = await ouvrirAdmin(SUPER, { hash: "#/livreurs" });
  const noms = await o.page.$$eval(".livreur-bloc", (n) => n.map((x) => x.innerText.trim().split("\n")[0].trim()));
  ok(JSON.stringify(noms) === JSON.stringify(noms.slice().sort((a, b) => a.localeCompare(b, "fr", { sensitivity: "base" }))),
    "par ordre alphabétique (" + noms.join(", ") + ")");
  await o.page.fill("#lv-chercher", "mens");
  await pause(200);
  const vus = await o.page.$$eval(".livreur-bloc", (b) => b.filter((x) => !x.hidden).map((x) => x.innerText));
  ok(vus.length === 1 && /Mensah/.test(vus[0]), "« mens » : Mensah seul");
  await o.page.fill("#lv-chercher", "0197");
  await pause(200);
  ok((await o.page.$$eval(".livreur-bloc", (b) => b.filter((x) => !x.hidden).length)) > 1, "par le numéro aussi");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

titre("3. La page « Boutiques » : la boutique ouverte, A → Z, et un champ");
{
  const o = await ouvrirAdmin(SUPER, { hash: "#/boutiques" });
  const vignettes = await o.page.$$eval(".bou-vignette span:last-child", (n) => n.map((x) => x.textContent.trim()));
  ok(JSON.stringify(vignettes) === JSON.stringify(vignettes.slice().sort((a, b) => a.localeCompare(b, "fr", { sensitivity: "base" }))),
    "le choix de la boutique ouverte, A → Z (" + vignettes.join(", ") + ")");
  await o.page.fill("#bq-chercher", "mode");
  await pause(200);
  const vues = await o.page.$$eval(".bou-vignette", (b) => b.filter((x) => !x.hidden).map((x) => x.innerText.trim()));
  ok(vues.length === 1 && /Mode Afrika/.test(vues[0]), "« mode » : Mode Afrika seule");
  await o.page.fill("#bq-chercher", "zzzz");
  await pause(200);
  ok(await o.page.$eval("#bq-aucune", (n) => !n.hidden), "rien : « Aucune boutique ne correspond »");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

titre("4. « Comptes » : une section par rang, des cartes vers les autres");
{
  const o = await ouvrirAdmin(SUPER, { hash: "#/comptes" });
  const sections = await o.page.$$eval(".cp-section", (c) => c.map((x) => x.id));
  ok(sections.includes("cp-section-administrateur") && sections.includes("cp-section-moderateur"),
    "des sections « Les administrateurs » et « Les modérateurs » (" + sections.join(", ") + ")");
  const modos = await o.page.$eval("#cp-section-moderateur", (c) => c.innerText);
  ok(/Awa/.test(modos) && !/Rohim|Zinsou/.test(modos), "les modérateurs à part, sans livreur");
  ok(!!(await o.page.$('a[href="#/livreurs"]')) && !!(await o.page.$("#cp-revendeurs")),
    "des cartes vers les livreurs et les revendeurs");
  await o.page.click('[data-creer-rang="moderateur"]');
  await pause(500);
  const f = await o.page.evaluate(() => ({
    titre: document.body.innerText.includes("Nouveau modérateur"),
    rangs: [...document.querySelectorAll("#nc-role option")].map((x) => x.value) }));
  ok(f.titre && f.rangs.length === 1 && f.rangs[0] === "moderateur", "« Créer un modérateur » : le rang est fixé");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " échec(s)" : "\nTout tient ✔");
process.exit(echecs ? 1 : 0);
