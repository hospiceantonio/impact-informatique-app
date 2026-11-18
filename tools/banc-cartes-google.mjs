/* =========================================================
   Banc : le fond des cartes — Google quand sa clé est réglée,
   OpenStreetMap sinon (4.8.0)

   Ce qu'on prouve :
     1. clé réglée : les images de la carte viennent de Google (avec la
        session et la clé), aucune d'OpenStreetMap, et la mention de
        Google est sur la carte ; la session ne se redemande pas ;
     2. pas de clé : OpenStreetMap, Google n'est jamais appelé ;
     3. Google refuse la session : OpenStreetMap ;
     4. Google refuse les images en route : au troisième refus,
        OpenStreetMap, et la session est oubliée ;
     5. BIZZOO Admin, superadministrateur : Réglages → « Cartes Google »
        vérifie la clé auprès de Google AVANT d'enregistrer ; une clé
        refusée n'est pas enregistrée ; l'administrateur d'une boutique
        n'a pas ce réglage ;
     6. le module est le même dans les trois applications.

   La base et Google sont simulés : aucun appel ne sort.
     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-cartes-google.mjs
   ========================================================= */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-cartes-google.mjs");
  process.exit(2);
}
const RACINE = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const plat = (s) => String(s || "").replace(/[  ]/g, " ").replace(/\s+/g, " ").trim();
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const CLE = "AIzaESSAI_cle-de-cartes-0000000000000000";
const PIXEL = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==", "base64");

/** Une page de la boutique, avec la base et Google simulés. */
async function ouvrirClient(o = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 900 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  const vus = { google: [], osm: [], sessions: 0, reglage: 0 };
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(() => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.route("**/rest/v1/**", (r) => {
    const c = new URL(r.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("cartes_reglage")) { vus.reglage++; return d([{ cle_tuiles: o.cle === undefined ? CLE : o.cle }]); }
    if (c.startsWith("boutique") && !c.startsWith("boutiques")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("https://tile.googleapis.com/**", (r) => {
    const u = new URL(r.request().url());
    if (u.pathname === "/v1/createSession") {
      vus.sessions++;
      if (o.sessionRefusee) return r.fulfill({ status: 403, contentType: "application/json", body: JSON.stringify({ error: { message: "API not enabled" } }) });
      return r.fulfill({ status: 200, contentType: "application/json",
        body: JSON.stringify({ session: "session-essai", expiry: String(Math.floor(Date.now() / 1000) + 14 * 86400) }) });
    }
    vus.google.push(u.pathname + u.search);
    if (o.imagesRefusees) return r.fulfill({ status: 403, body: "" });
    return r.fulfill({ status: 200, contentType: "image/png", body: PIXEL });
  });
  await page.route("https://tile.openstreetmap.org/**", (r) => {
    vus.osm.push(r.request().url());
    return r.fulfill({ status: 200, contentType: "image/png", body: PIXEL });
  });
  await page.goto(BASE + "/client/index.html");
  await pause(2000);
  const monter = async () => {
    const fond = await page.evaluate(async () => {
      const d = document.createElement("div");
      d.className = "essai-carte";
      d.style.cssText = "width:360px;height:300px;position:fixed;top:0;left:0;z-index:99999";
      document.body.appendChild(d);
      await Carte.monter(d, { position: { latitude: 6.37, longitude: 2.42 } });
      return [...d.querySelectorAll(".leaflet-control-attribution")].map((x) => x.innerText).join(" ");
    });
    await pause(1500);
    return plat(fond);
  };
  return { ctx, page, erreurs, vus, monter };
}
const sansErreur = (o) => ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));

titre("1. Clé réglée : les cartes de Google");
{
  const o = await ouvrirClient();
  const mention = await o.monter();
  ok(o.vus.google.length > 0 && !o.vus.osm.length, "les images viennent de Google (" + o.vus.google.length + "), aucune d'OpenStreetMap");
  ok(o.vus.google.every((u) => /^\/v1\/2dtiles\/\d+\/\d+\/\d+\?session=session-essai&key=AIzaESSAI/.test(u)),
    "chaque image porte la session et la clé des cartes");
  ok(/Google/.test(mention) && /© Google/.test(mention), "la mention de Google est sur la carte (« " + mention + " »)");
  ok(o.vus.sessions === 1, "une session demandée à Google");
  await o.monter();
  ok(o.vus.sessions === 1 && o.vus.reglage === 1, "une seconde carte : ni la session ni la clé ne sont redemandées");
  sansErreur(o);
  await o.ctx.close();
}

titre("2. Pas de clé : OpenStreetMap");
{
  const o = await ouvrirClient({ cle: "" });
  const mention = await o.monter();
  ok(o.vus.osm.length > 0 && !o.vus.google.length && !o.vus.sessions, "les images viennent d'OpenStreetMap ; Google n'est jamais appelé");
  ok(/OpenStreetMap/.test(mention) && !/Google/.test(mention), "la mention est celle d'OpenStreetMap");
  sansErreur(o);
  await o.ctx.close();
}

titre("3. Google refuse la session : OpenStreetMap");
{
  const o = await ouvrirClient({ sessionRefusee: true });
  const mention = await o.monter();
  ok(o.vus.sessions === 1 && o.vus.osm.length > 0 && !o.vus.google.length, "session refusée : la carte s'affiche quand même, en OpenStreetMap");
  ok(/OpenStreetMap/.test(mention), "avec sa mention");
  sansErreur(o);
  await o.ctx.close();
}

titre("4. Google refuse les images en route : OpenStreetMap prend la place");
{
  const o = await ouvrirClient({ imagesRefusees: true });
  await o.monter();
  await pause(800);
  ok(o.vus.google.length >= 3 && o.vus.osm.length > 0, "après trois refus, les images d'OpenStreetMap (" + o.vus.google.length + " refus, " + o.vus.osm.length + " images)");
  ok(await o.page.evaluate(() => !localStorage.getItem("bizzoo-fond-carte")), "et la session de Google est oubliée");
  ok(/OpenStreetMap/.test(plat(await o.page.evaluate(() => [...document.querySelectorAll(".essai-carte .leaflet-control-attribution")].map((x) => x.innerText).join(" ")))),
    "la mention suit");
  sansErreur(o);
  await o.ctx.close();
}

titre("5. BIZZOO Admin : Réglages → « Cartes Google »");
const jeton = (sub) => {
  const b64 = (x) => Buffer.from(JSON.stringify(x)).toString("base64url");
  return b64({ alg: "HS256" }) + "." + b64({ sub }) + ".s";
};
const SUP = "11111111-1111-1111-1111-111111111111";
const CHEF = "c8c80000-0000-0000-0000-000000000001";
const PROFILS = {
  [SUP]: { id: SUP, email: "sup@bizzoo.bj", nom: "Sup", role: "superadministrateur", actif: true, boutique_id: null, peut_modifier_produits: true },
  [CHEF]: { id: CHEF, email: "chef@alpha.bj", nom: "Chef", role: "administrateur", actif: true, boutique_id: "bou_a", peut_modifier_produits: true },
};
async function ouvrirAdmin(moi, googleAccepte) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 9000 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  const appels = [];
  let cle = "";
  page.on("pageerror", (e) => erreurs.push(e.message));
  page.on("dialog", (d) => d.accept());
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: a.t, refresh_token: "r", expire_a: Date.now() + 3600000, email: a.email }));
  }, { t: jeton(moi), email: PROFILS[moi].email });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.route("https://tile.googleapis.com/**", (r) => googleAccepte()
    ? r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ session: "s", expiry: "9999999999" }) })
    : r.fulfill({ status: 403, contentType: "application/json", body: JSON.stringify({ error: { message: "Map Tiles API has not been used in project" } }) }));
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    let corps = null;
    try { corps = req.postDataJSON(); } catch (_) { corps = null; }
    if (c === "rpc/etat_connexion") return d({ equipe: true, sms_exige: false, session_confirmee: true, numero: true });
    if (c === "rpc/regler_cle_cartes") { appels.push(corps); cle = corps.cle; return d(!!cle); }
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("cartes_reglage")) return d([{ cle_tuiles: cle }]);
    if (c.startsWith("profils")) return d([PROFILS[moi]]);
    if (c.startsWith("boutiques")) return d([{ id: "bou_a", nom: "Alpha", categorie_id: null, icone: "magasin", couleur: "#0B7C8C",
      devise: "FCFA", indicatif: "229", actif: true, ordre: 1 }]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await pause(2200);
  await page.evaluate(() => { location.hash = "#/reglages"; });
  await pause(1800);
  /* Les réglages de l'enseigne (le superadministrateur choisit quoi régler). */
  if (await page.$('[data-cible="enseigne"]')) {
    await page.click('[data-cible="enseigne"]');
    await pause(1600);
  }
  return { ctx, page, erreurs, appels };
}
{
  let accepte = false;
  const o = await ouvrirAdmin(SUP, () => accepte);
  const carte = () => o.page.evaluate(() => (document.querySelector("#section-cartes") || {}).innerText || "").then(plat);
  ok(/Cartes Google/.test(await carte()) && /OpenStreetMap/.test(await carte()), "la carte « Cartes Google » : aujourd'hui OpenStreetMap");
  ok(/Map Tiles API/.test(await carte()) && /www\.bizzoomarket\.com/.test(await carte()) && /appassets\.androidx\.dev/.test(await carte()),
    "elle dit quoi activer, et à quels sites limiter la clé");
  await o.page.fill("#cartes-cle", CLE);
  await o.page.click("#cartes-enregistrer");
  await pause(1200);
  ok(/Google refuse cette clé \(403\)/.test(await carte()) && /Map Tiles API has not been used/.test(await carte()) && !o.appels.length,
    "Google refuse la clé : on le dit, avec sa raison, et rien n'est enregistré");
  accepte = true;
  await o.page.click("#cartes-enregistrer");
  await pause(1500);
  ok(o.appels.length === 1 && o.appels[0].cle === CLE, "Google l'accepte : la clé est enregistrée");
  ok(/celles de Google/.test(await carte()) && /AIza…0000/.test(await carte()) && !(await carte()).includes(CLE),
    "la carte le dit, clé masquée (AIza…0000)");
  await o.page.click("#cartes-retirer");
  await pause(1500);
  ok(o.appels.length === 2 && o.appels[1].cle === "" && /OpenStreetMap/.test(await carte()), "« Revenir à OpenStreetMap » la retire");
  sansErreur(o);
  await o.ctx.close();
}
{
  const o = await ouvrirAdmin(CHEF, () => true);
  ok(!(await o.page.$("#section-cartes")), "l'administrateur d'une boutique n'a pas ce réglage");
  await o.ctx.close();
}

titre("6. Le même module dans les trois applications");
{
  const lire = (f) => fs.readFileSync(path.join(RACINE, f), "utf8");
  const original = lire("client/js/fond-carte.js");
  ok(lire("admin/js/fond-carte.js") === original && lire("personnel/js/fond-carte.js") === original,
    "admin et personnel portent la copie exacte de client/js/fond-carte.js");
  ok(["client", "admin", "personnel"].every((a) => lire(a + "/index.html").includes('src="js/fond-carte.js"') && lire(a + "/sw.js").includes('"./js/fond-carte.js"')),
    "il est chargé par les trois pages, et gardé hors connexion");
}

await nav.close();
console.log(echecs
  ? "\n\x1b[31m" + echecs + " constat(s) en échec ✘\x1b[0m"
  : "\n\x1b[32mLes cartes sont celles de Google quand sa clé est réglée, d'OpenStreetMap sinon — jamais vides ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
