/* =========================================================
   Le live TikTok : le bouton de l'admin, le bandeau du client
   =========================================================
   CE QU'ON DÉFEND ICI. La base décide qui lance un live
   (supabase/tests/99y-live-tiktok.sql), la fonction Edge envoie la
   notification (supabase/functions/tests/live.mjs). Les écrans :

     1. ADMIN — l'accueil d'une boutique qui a son TikTok propose
        « Démarrer le live TikTok » ; il demande confirmation, puis
        appelle « annoncer-live » pour CETTE boutique ;
     2. ADMIN — sans compte TikTok : on dit où l'ajouter, pas de bouton ;
     3. ADMIN — pendant le live : « En live », et « Arrêter le live » ;
     4. CLIENT — l'accueil montre « X est en live sur TikTok », lien
        vers sa page TikTok ; la fiche d'une boutique, son seul live ;
     5. CLIENT — pas de live, ou base d'avant : rien, et rien ne casse.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-live-tiktok.mjs");
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

const MOI = "aaaaaaaa-0000-0000-0000-00000000000a";
const jeton = (moi) => {
  const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return b64({ alg: "HS256" }) + "." + b64({ sub: moi }) + ".s";
};
const BOUTIQUE = (tiktok) => ({ id: "bou_info", nom: "IMPACT", secteur: "Informatique",
  icone: "portable", couleur: "#0B5CF5", devise: "FCFA", indicatif: "229", actif: true,
  ordre: 1, tiktok, categorie_id: null });

async function ouvrirAdmin({ tiktok = "@impact.bj", live = null } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1600 } });
  const page = await ctx.newPage();
  const erreurs = [];
  const appels = [];
  let enCours = live;
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(({ t }) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: t, refresh_token: "r", expire_a: Date.now() + 3600000, email: "chef@impact.bj" }));
  }, { t: jeton(MOI) });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.route("**/functions/v1/**", (r) => {
    const nom = new URL(r.request().url()).pathname.split("/").pop();
    appels.push({ nom, corps: corpsDe(r.request()), auth: r.request().headers().authorization || "" });
    enCours = { boutique_id: "bou_info", nom: "IMPACT", lien: "https://www.tiktok.com/@impact.bj",
      debut: new Date().toISOString() };
    return r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({
      ok: true, deja: false, push: true, message: "Live annoncé : la notification part vers tous les téléphones." }) });
  });
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) appels.push({ nom: c.slice(4), corps: corpsDe(req) });
    if (c.startsWith("profils")) return d([{ id: MOI, email: "chef@impact.bj", role: "administrateur",
      actif: true, peut_modifier_produits: true, boutique_id: "bou_info" }]);
    if (c === "rpc/lives_en_cours") return d(enCours ? [enCours] : []);
    if (c === "rpc/arreter_live") { enCours = null; return d(1); }
    if (c.startsWith("boutiques")) return d([BOUTIQUE(tiktok)]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    if (c.startsWith("rpc/")) return d(null);
    return d([]);
  });
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await pause(2500);
  const carte = () => page.evaluate(() => {
    const z = document.getElementById("carte-live");
    return z ? { visible: !z.hidden, texte: z.innerText.replace(/\s+/g, " ") } : null;
  });
  return { ctx, page, erreurs, appels, carte };
}

titre("1. Démarrer le live, depuis l'accueil de la boutique");
{
  const o = await ouvrirAdmin();
  let c = await o.carte();
  ok(c && c.visible && /Démarrer le live TikTok/.test(c.texte), "la carte propose « Démarrer le live TikTok »");
  await o.page.click("#live-demarrer");
  await pause(300);
  const confirmation = await o.page.evaluate(() => document.body.innerText);
  ok(/Tous les clients de BIZZOO vont recevoir « IMPACT est en live sur TikTok »/.test(confirmation),
    "il demande confirmation, en disant ce que les clients recevront");
  ok(!o.appels.some((a) => a.nom === "annoncer-live"), "rien ne part avant la confirmation");
  await o.page.click("[data-role=ok]");
  await pause(1200);
  const a = o.appels.find((x) => x.nom === "annoncer-live");
  ok(a && a.corps.boutique === "bou_info" && /^Bearer .+\..+\./.test(a.auth),
    "« annoncer-live » est appelée pour CETTE boutique, avec la session (" + JSON.stringify(a && a.corps) + ")");

  titre("3. Pendant le live");
  c = await o.carte();
  ok(c && /En live sur TikTok/.test(c.texte) && /Arrêter le live/.test(c.texte),
    "la carte passe à « En live », avec « Arrêter le live » (" + (c && c.texte) + ")");
  await o.page.click("#live-arreter");
  await pause(1000);
  ok(o.appels.some((x) => x.nom === "arreter_live" && x.corps.cible === "bou_info"),
    "« Arrêter » ferme le live de cette boutique");
  c = await o.carte();
  ok(c && /Démarrer le live TikTok/.test(c.texte), "et la carte revient à « Démarrer »");
  ok(!o.erreurs.length, "aucune erreur dans la page" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

titre("2. Sans compte TikTok");
{
  const o = await ouvrirAdmin({ tiktok: "" });
  const c = await o.carte();
  ok(c && c.visible && /Ajoutez d'abord le compte TikTok/.test(c.texte) &&
     !(await o.page.$("#live-demarrer")), "on dit où l'ajouter, et pas de bouton");
  await o.ctx.close();
}

/* ---------- Le client ---------- */
const LIVES = [
  { boutique_id: "bou_b", nom: "MODE COTONOU", lien: "https://www.tiktok.com/@modecotonou", debut: "2026-10-16T18:00:00Z" },
];
const BOU_CLIENT = [
  { id: "bou_a", nom: "IMPACT", secteur: "Informatique", categorie_id: null, icone: "portable",
    couleur: "#0B5CF5", devise: "FCFA", indicatif: "229", actif: true, ordre: 1 },
  { id: "bou_b", nom: "MODE COTONOU", secteur: "Mode", categorie_id: null, icone: "tshirt",
    couleur: "#6C3FBF", devise: "FCFA", indicatif: "229", actif: true, ordre: 2, tiktok: "@modecotonou" },
];
async function ouvrirClient(hash, { lives = LIVES, statut = 200 } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1200 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(() => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.removeItem("impact-boutique");
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json",
    body: JSON.stringify({ external: { email: true, phone: true } }) }));
  await page.route("**/realtime/**", (r) => r.abort());
  await page.route("**/rest/v1/**", (r) => {
    const c = new URL(r.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x, s = 200) => r.fulfill({ status: s, contentType: "application/json", body: JSON.stringify(x) });
    if (c === "rpc/lives_en_cours") {
      return statut === 200 ? d(lives) : d({ message: "Could not find the function public.lives_en_cours" }, statut);
    }
    if (c.startsWith("boutiques")) return d(BOU_CLIENT);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html" + hash, { waitUntil: "domcontentloaded" });
  await pause(2200);
  const bandeaux = await page.evaluate(() =>
    [...document.querySelectorAll("#vue .bandeau-live")].map((a) => ({
      texte: a.innerText.replace(/\s+/g, " ").trim(), lien: a.getAttribute("href"), cible: a.target })));
  return { ctx, page, erreurs, bandeaux };
}

titre("4. Le client voit le live");
{
  const o = await ouvrirClient("#/");
  const b = o.bandeaux[0] || {};
  ok(o.bandeaux.length === 1 && /MODE COTONOU est en live sur TikTok/.test(b.texte),
    "l'accueil : « MODE COTONOU est en live sur TikTok » (" + b.texte + ")");
  ok(b.lien === "https://www.tiktok.com/@modecotonou" && b.cible === "_blank",
    "le bandeau mène à sa page TikTok, hors de l'application");
  ok(!o.erreurs.length, "aucune erreur dans la page" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}
{
  const o = await ouvrirClient("#/boutique/bou_b");
  ok(o.bandeaux.length === 1, "la fiche de la boutique en live le montre aussi");
  await o.ctx.close();
  const autre = await ouvrirClient("#/boutique/bou_a");
  ok(autre.bandeaux.length === 0, "la fiche d'une autre boutique, non");
  await autre.ctx.close();
}

titre("5. Pas de live, ou une base d'avant");
{
  const o = await ouvrirClient("#/", { lives: [] });
  ok(o.bandeaux.length === 0, "aucun live : aucun bandeau");
  await o.ctx.close();
  const avant = await ouvrirClient("#/", { statut: 404 });
  ok(avant.bandeaux.length === 0 && !avant.erreurs.length &&
     (await avant.page.evaluate(() => /IMPACT/.test(document.body.innerText))),
    "fonction inconnue : rien, et l'accueil tient");
  await avant.ctx.close();
}

await nav.close();
console.log(echecs
  ? "\n\x1b[31m" + echecs + " constat(s) en échec ✘\x1b[0m"
  : "\n\x1b[32mUn live s'annonce d'un bouton, et les clients le voient ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
