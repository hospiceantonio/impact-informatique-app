/* =========================================================
   Chaque boutique : sa condition de paiement, ses frais (3.59.0)
   =========================================================
   La base calcule la part de chaque boutique à la commande
   (supabase/tests/99zzzzzzzz-conditions-boutiques.sql). Les écrans :

   APPLICATION CLIENT
     1. un panier sur deux boutiques — l'une « tout à la commande », 1 500
        de livraison ; l'autre acompte de 30 %, 500 de livraison — annonce
        le total, ce qui se paie maintenant, ce qui reste à la livraison,
        et le détail de chaque boutique ;
     2. une seule boutique, tout à la commande : rien à la livraison.

   APPLICATION VENDEUR
     3. créer une boutique demande sa condition et ses frais ; ils partent ;
     4. l'administrateur d'une boutique règle les siens dans Réglages.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-conditions-boutiques.mjs");
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

const BOU = [
  { id: "bou_tout", nom: "Alpha Tout", secteur: "Informatique", categorie_id: "cat_hightech", icone: "portable",
    couleur: "#0047D9", devise: "FCFA", indicatif: "229", actif: true, ordre: 1,
    mode_paiement: "total", taux_acompte: 10, frais_livraison: 1500 },
  { id: "bou_ac", nom: "Beta Acompte", secteur: "Maison", categorie_id: "cat_hightech", icone: "portable",
    couleur: "#0047D9", devise: "FCFA", indicatif: "229", actif: true, ordre: 2,
    mode_paiement: "acompte", taux_acompte: 30, frais_livraison: 500 },
];
const P = (id, boutique, nom, prix) => ({ id, code: id, nom, reference: id, prix, boutique_id: boutique,
  categorie_id: "cat_hightech", sous_categorie_id: null, stock: 5, disponible: true, sur_commande: false,
  images: [], video: "", en_avant: false, cree_le: "2026-09-01T10:00:00Z", modifie_le: "2026-09-01T10:00:00Z" });
const PRODUITS = [P("p_tout", "bou_tout", "Écran", 10000), P("p_ac", "bou_ac", "Chaise", 20000)];

async function ouvrirClient(panier) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2200 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((pan) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.removeItem("impact-boutique");
    localStorage.setItem("bizzoo-panier", JSON.stringify(pan));
  }, panier);
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ external: { phone: true } }) }));
  await page.route("**/rest/v1/**", (r) => {
    const c = new URL(r.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    if (c.startsWith("produits")) return d(PRODUITS);
    if (c.startsWith("categories")) return d([{ id: "cat_hightech", nom: "High-tech", ordre: 1, sous_categories: [] }]);
    if (c.startsWith("paiement")) return d([{ id: 1, actif: true, fournisseur: "feexpay", taux_acompte: 10, frais_livraison: 1000 }]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html#/panier");
  await pause(2800);
  return { ctx, page, erreurs };
}
const texte = (page) => page.evaluate(() => document.getElementById("vue").innerText.replace(/\s+/g, " "));
const sansEsp = (t) => t.replace(/[\s  ]/g, "");

titre("1. Deux boutiques, deux conditions");
{
  const o = await ouvrirClient([{ produitId: "p_tout", quantite: 1 }, { produitId: "p_ac", quantite: 1 }]);
  const ap = await o.page.evaluate(() => Paiement.apercu(0));
  ok(ap.frais === 2000 && ap.total === 32000, "frais 1 500 + 500, total 32 000 (" + ap.frais + ", " + ap.total + ")");
  ok(ap.acompte === 17650 && ap.reste === 14350,
    "maintenant 11 500 (tout) + 6 150 (30 % de 20 500) = 17 650 ; à la livraison 14 350 (" + ap.acompte + ", " + ap.reste + ")");
  const t = sansEsp(await texte(o.page));
  ok(/Àpayeràlacommande.*17650/.test(t) && /Àpayeràlalivraison14350/.test(t), "le panier l'annonce");
  ok(/selonchaqueboutique/.test(t), "« selon chaque boutique » : les taux diffèrent");
  ok(!!(await o.page.$("#pa-detail-boutiques")) && /AlphaTout.*toutàlacommande/.test(t) && /BetaAcompte.*acompte30%/.test(t),
    "le détail de chaque boutique");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

titre("2. Une seule boutique, tout à la commande");
{
  const o = await ouvrirClient([{ produitId: "p_tout", quantite: 2 }]);
  const ap = await o.page.evaluate(() => Paiement.apercu(0));
  ok(ap.total === 21500 && ap.acompte === 21500 && ap.reste === 0, "21 500, tout maintenant, rien à la livraison");
  ok(!/Àpayeràlalivraison/.test(sansEsp(await texte(o.page))), "le panier ne parle pas d'un reste");
  await o.ctx.close();
}

/* ---------- Application vendeur ---------- */
const jeton = (sub) => Buffer.from(JSON.stringify({ alg: "HS256" })).toString("base64url") + "." +
  Buffer.from(JSON.stringify({ sub })).toString("base64url") + ".s";
const SUPER = "c1110000-0000-0000-0000-000000000001";
const CHEF = "c2220000-0000-0000-0000-000000000002";
const PR = (id, email, role, boutique) => ({ id, email, role, actif: true, peut_modifier_produits: true,
  boutique_id: boutique, nom: "", tel: "0197000000" });
async function ouvrirAdmin(moi, profils, hash) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2600 } });
  const page = await ctx.newPage();
  const erreurs = [];
  const note = { post: [], patch: [] };
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    localStorage.setItem("impact-session", JSON.stringify({ access_token: a.t, refresh_token: "r",
      expire_a: Date.now() + 3600000, email: a.email }));
  }, { t: jeton(moi), email: profils.find((p) => p.id === moi).email });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x, s = 200) => route.fulfill({ status: s, contentType: "application/json", body: JSON.stringify(x) });
    if (c === "rpc/etat_connexion") return d({ equipe: true, sms_exige: false, session_confirmee: true, numero: true });
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("boutiques")) {
      if (req.method() === "POST") { const x = corpsDe(req); note.post.push(x); return d([x], 201); }
      if (req.method() === "PATCH") { const x = corpsDe(req); note.patch.push(x); return d([x]); }
      return d([{ id: "bou_a", nom: "Alpha", categorie_id: "cat_hightech", icone: "magasin", couleur: "#0047D9",
        devise: "FCFA", indicatif: "229", actif: true, ordre: 1, ouvertures: { lun: { de: "08:00", a: "19:00" } },
        mode_paiement: "acompte", taux_acompte: 10, frais_livraison: 1000 }]);
    }
    if (c.startsWith("categories")) return d([{ id: "cat_hightech", nom: "High-tech", ordre: 1, sous_categories: [] }]);
    if (c.startsWith("profils")) {
      const id = (u.searchParams.get("id") || "").replace(/^eq\./, "");
      return d(id ? profils.filter((p) => p.id === id) : profils);
    }
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/admin/index.html");
  await pause(2200);
  if (hash) { await page.evaluate((h) => { location.hash = h; }, hash); await pause(1500); }
  return { ctx, page, erreurs, note };
}
const accepterConditions = async (page) => {
  if (await page.$("[data-ugc-accord]")) {
    await page.check("[data-ugc-accord]");
    await page.click("[data-ugc-valider]");
    await pause(1500);
  }
};

titre("3. Créer une boutique : sa condition et ses frais");
{
  const o = await ouvrirAdmin(SUPER, [PR(SUPER, "chef@bizzoo.bj", "superadministrateur", null)], "#/boutiques");
  await o.page.click("#bq-nouvelle");
  await pause(700);
  ok(!!(await o.page.$("#bq-mode")) && !!(await o.page.$("#bq-frais")), "le formulaire demande la condition et les frais");
  await o.page.fill("#bq-nom", "Gamma");
  await o.page.evaluate(() => {
    const s = document.querySelector("#bq-categorie");
    if (s && s.options.length > 1) s.value = s.options[1].value;
  });
  await o.page.selectOption("#bq-mode", "acompte");
  await o.page.fill("#bq-taux", "150");
  await o.page.click("#bq-enregistrer");
  await pause(700);
  ok(!o.note.post.length, "un acompte de 150 % : rien ne part");
  await o.page.fill("#bq-taux", "25");
  await o.page.fill("#bq-frais", "2000");
  await o.page.click("#bq-enregistrer");
  await pause(800);
  await accepterConditions(o.page);
  await pause(800);
  const b = o.note.post[0] || {};
  ok(b.mode_paiement === "acompte" && b.taux_acompte === 25 && b.frais_livraison === 2000,
    "elles partent avec la boutique (" + [b.mode_paiement, b.taux_acompte, b.frais_livraison].join(", ") + ")");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

titre("4. L'administrateur d'une boutique règle les siennes");
{
  const o = await ouvrirAdmin(CHEF, [PR(CHEF, "chef@alpha.bj", "administrateur", "bou_a")], "#/reglages");
  ok(!!(await o.page.$("#r-mode")) && await o.page.inputValue("#r-frais") === "1000", "ses réglages actuels sont là");
  await o.page.selectOption("#r-mode", "total");
  ok(await o.page.evaluate(() => document.querySelector("#r-bloc-taux").hidden), "« tout à la commande » : pas de taux");
  await o.page.fill("#r-frais", "0");
  await o.page.click("#r-enregistrer");
  await pause(1200);
  await accepterConditions(o.page);
  const e = o.note.patch.find((x) => x && x.mode_paiement) || {};
  ok(e.mode_paiement === "total" && e.frais_livraison === 0, "tout à la commande, livraison offerte : enregistré");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " constat(s) en échec." : "\nTous les constats sont bons.");
process.exit(echecs ? 1 : 0);
