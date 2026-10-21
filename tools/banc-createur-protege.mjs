/* =========================================================
   On ne touche pas à son créateur, à l'écran (3.59.0)
   =========================================================
   La base refuse (supabase/tests/99zzzzzzzzzzzzzzzzz-createur-protege.sql).
   Ce banc regarde l'écran « Comptes » d'un superadministrateur B, créé
   par A, et qui a lui-même créé C :

     1. A porte « vous a créé », et pas de crayon ;
     2. le créateur de A (plus haut encore) non plus ;
     3. C, que B a créé, garde son crayon ;
     4. « Bon à savoir » le dit.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-createur-protege.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const jeton = (sub) => {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  return b64({ alg: "HS256" }) + "." + b64({ sub }) + ".s";
};
const ORIGINE = "c0000000-0000-0000-0000-000000000000";
const A = "c1110000-0000-0000-0000-000000000001";
const B = "c2220000-0000-0000-0000-000000000002";
const C = "c3330000-0000-0000-0000-000000000003";
const S = (id, nom, creePar) => ({ id, email: nom.toLowerCase() + "@bizzoo.bj", nom, role: "superadministrateur",
  actif: true, peut_modifier_produits: true, boutique_id: null, tel: "0197000000", cree_par: creePar,
  cree_par_nom: "", cree_le: "2026-10-01T08:00:00Z" });
const PROFILS = [S(ORIGINE, "Origine", null), S(A, "Awa", ORIGINE), S(B, "Bio", A), S(C, "Cica", B)];

console.log("\n== Le compte qui vous a créé ==");
const ctx = await nav.newContext({ viewport: { width: 390, height: 2000 } });
const page = await ctx.newPage();
const erreurs = [];
page.on("pageerror", (e) => erreurs.push(e.message));
await page.addInitScript((a) => {
  localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
  localStorage.setItem("impact-session", JSON.stringify({
    access_token: a.t, refresh_token: "r", expire_a: Date.now() + 3600000, email: "bio@bizzoo.bj" }));
}, { t: jeton(B) });
await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
await page.route("**/rest/v1/**", (route) => {
  const u = new URL(route.request().url());
  const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
  const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
  if (c === "rpc/etat_connexion") return d({ equipe: true, sms_exige: false, session_confirmee: true, numero: true });
  if (c.startsWith("rpc/")) return d(null);
  if (c.startsWith("profils")) {
    const id = (u.searchParams.get("id") || "").replace(/^eq\./, "");
    return d(id ? PROFILS.filter((p) => p.id === id) : PROFILS);
  }
  if (c.startsWith("boutiques")) return d([{ id: "bou_a", nom: "Alpha", devise: "FCFA", indicatif: "229", actif: true, ordre: 1 }]);
  if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
  return d([]);
});
await page.goto(BASE + "/admin/index.html#/comptes", { waitUntil: "domcontentloaded" });
await pause(3500);
const lignes = await page.evaluate(() => [...document.querySelectorAll(".compte-ligne")].map((l) => ({
  t: l.innerText.replace(/\s+/g, " "), crayon: l.querySelector("[data-compte]")?.dataset.compte || "" })));
const de = (nom) => lignes.find((l) => l.t.includes(nom)) || { t: "", crayon: "" };
ok(/vous a créé/i.test(de("Awa").t) && !de("Awa").crayon, "Awa, qui l'a créé : « vous a créé », pas de crayon");
ok(/vous a créé/i.test(de("Origine").t) && !de("Origine").crayon, "le créateur d'Awa non plus");
ok(de("Cica").crayon === C && !/vous a créé/i.test(de("Cica").t), "Cica, qu'il a créée : son crayon reste");
ok(/vous a créé/.test(await page.evaluate(() => document.getElementById("vue").innerText)) &&
   /ne pouvez pas modifier ses droits/.test(await page.evaluate(() => document.getElementById("vue").innerText)),
  "« Bon à savoir » le dit");
ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
await ctx.close();
await nav.close();
console.log(echecs ? "\n" + echecs + " ÉCHEC(S)" : "\nTout tient ✔");
process.exit(echecs ? 1 : 0);
