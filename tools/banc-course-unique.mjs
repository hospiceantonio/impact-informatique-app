/* =========================================================
   Une commande groupée, une seule course (3.72.0)
   =========================================================
   La base garde la règle (supabase/tests/99…-course-unique.sql). Ce
   banc regarde l'écran du livreur :

     1. deux boutiques : UNE carte, un seul « Commande reçue » ;
     2. acceptée : un « Colis récupéré ici » par boutique prête ;
        « Refuser » tant que rien n'est récupéré ;
     3. un colis récupéré : plus de refus, « récupérez le reste » ;
     4. tout récupéré : UNE remise, le reste de toute la commande en un
        seul paiement MoMoPay — remettre_commande, jamais remettre_course.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-course-unique.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const F = (n) => n.toLocaleString("fr-FR").replace(/ | /g, " ") + " FCFA";
const plat = (s) => s.replace(/[  ]/g, " ").replace(/\s+/g, " ");

/* ================================================================
   L'application admin
   ================================================================ */
const PORTEUR = "cccccccc-1111-1111-1111-111111111111";
const BIZ = "cccccccc-2222-2222-2222-222222222222";
const CHEF = "22222222-2222-2222-2222-222222222222";
const MODO = "33333333-2222-2222-2222-222222222222";
const SUP = "11111111-1111-1111-1111-111111111111";
const PROFILS = {
  [BIZ]: { id: BIZ, email: "biz@bizzoo.bj", nom: "Codjo", role: "livreur", actif: true,
    peut_modifier_produits: false, boutique_id: null, disponible: true },
  [PORTEUR]: { id: PORTEUR, email: "porteur@alpha.bj", nom: "Kodjo", role: "livreur", actif: true,
    peut_modifier_produits: true, boutique_id: "bou_a" },
  [CHEF]: { id: CHEF, email: "chef@alpha.bj", nom: "Chef", role: "administrateur", actif: true,
    peut_modifier_produits: true, boutique_id: "bou_a" },
  [MODO]: { id: MODO, email: "modo@alpha.bj", nom: "Modo", role: "moderateur", actif: true,
    peut_modifier_produits: true, boutique_id: "bou_a" },
  [SUP]: { id: SUP, email: "sup@bizzoo.bj", nom: "Sup", role: "superadministrateur", actif: true,
    peut_modifier_produits: true, boutique_id: null },
};
const fiche = (o = {}) => ({ numero: "BZ-000090",
  retrait: { boutique: "Alpha", adresse: "Ganhi", tel: "0197111222", indicatif: "229" },
  livraison: { nom: "Afi", adresse: "Fidjrossè", note: "", tel: "97666007", indicatif: "229" },
  devise: "FCFA", frais: 1000, deja_paye: 3000, a_encaisser: 7000, encaisse: null,
  momopay: { code: "123456", nom: "BIZZOO SARL" }, ...o });
const course = (o = {}) => ({ commande_id: "cmd_r", numero: "BZ-000090", boutique_id: "bou_a",
  nom_boutique: "Alpha", client_nom: "Afi", client_tel: "97666007", client_indicatif: "229",
  client_adresse: "Fidjrossè", note: "", etat: "en_livraison",
  articles: [{ nom: "Casque", quantite: 1 }], paye_le: "2026-10-20T08:00:00Z",
  a_encaisser: 7000, fiche: fiche(), recu_le: "2026-10-20T08:05:00Z", ...o });

const partie = (bq, nom, o = {}, f = {}) => course({ boutique_id: bq, nom_boutique: nom,
  commande_id: "cmd_g", numero: "BZ-000120", articles: [{ nom: "Article " + nom, quantite: 1 }],
  fiche: fiche({ numero: "BZ-000120", retrait: { boutique: nom, adresse: "Adresse " + nom, tel: "0197000000", indicatif: "229" },
    ...f }), ...o });

async function ouvrir(courses) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2400 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: b64({ alg: "HS256" }) + "." + b64({ sub: a.moi }) + ".s",
      refresh_token: "r", expire_a: Date.now() + 3600000, email: a.email }));
    window.__toasts = [];
    document.addEventListener("DOMContentLoaded", () => {
      const zone = document.querySelector("#toasts") || document.body;
      new MutationObserver(() => window.__toasts.push(zone.innerText))
        .observe(zone, { childList: true, subtree: true });
    });
  }, { moi: BIZ, email: PROFILS[BIZ].email });
  const serveur = { appels: [] };
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) {
      serveur.appels.push({ fn: c.slice(4), corps: (() => { try { return req.postDataJSON(); } catch (_) { return null; } })() });
    }
    if (c.startsWith("profils")) {
      const id = (u.searchParams.get("id") || "").replace(/^eq\./, "");
      return d(id ? [PROFILS[id]].filter(Boolean) : Object.values(PROFILS));
    }
    if (c.startsWith("positions_livreurs")) return d([{ profil_id: BIZ, latitude: 6.37, longitude: 2.42, adresse: "Cotonou" }]);
    if (c === "rpc/mes_livraisons") return d(courses);
    if (c === "rpc/courses_proposees") return d([]);
    if (c === "rpc/remettre_commande") return d({ lignes: 2, du: 7000 });
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1800);
  await page.evaluate(() => { location.hash = "#/livraisons"; });
  await page.waitForSelector(".lv-course", { timeout: 6000 }).catch(() => {});
  await page.waitForTimeout(400);
  return { page, ctx, erreurs, serveur };
}
const toasts = (page) => page.evaluate(() => (window.__toasts || []).join(" | "));
const texte = (page, sel) => page.evaluate((s) => [...document.querySelectorAll(s)].map((e) => e.innerText).join(" || "), sel).then(plat);

titre("1. Deux boutiques : une carte, un seul « Commande reçue »");
{
  const { page, ctx, erreurs, serveur } = await ouvrir([
    partie("bou_a", "Alpha", { etat: "preparee", recu_le: null, a_encaisser: 4000 }, { a_encaisser: 4000 }),
    partie("bou_b", "Bêta", { etat: "vue", recu_le: null, a_encaisser: 3000 }, { a_encaisser: 3000 })]);
  ok(await page.$$eval(".lv-course", (n) => n.length) === 1, "une seule carte pour la commande");
  const t = await texte(page, ".lv-course");
  ok(/Livraison groupée : 2 boutiques, une seule course/.test(t), "« Livraison groupée : 2 boutiques, une seule course »");
  ok(/Récupérer \(1\/2\)/i.test(t) && /Récupérer \(2\/2\)/i.test(t) && /Alpha/.test(t) && /Bêta/.test(t),
    "les deux lieux de retrait, Alpha puis Bêta");
  ok(/Article Alpha/.test(t) && /Article Bêta/.test(t), "les articles de chaque boutique");
  ok(/À payer par MoMoPay : 7 000 FCFA/.test(t), "le reste de toute la commande : 7 000 FCFA");
  ok(/1 course à faire/i.test(await texte(page, ".titre-section")), "« 1 course à faire »");
  ok(await page.$$eval(".lv-recu", (n) => n.length) === 1, "un seul « Commande reçue »");
  await page.click(".lv-recu");
  await page.waitForTimeout(600);
  ok(serveur.appels.filter((a) => a.fn === "accepter_course").length === 1, "accepter_course, une fois");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("2. Acceptée : un colis à récupérer par boutique prête");
{
  const { page, ctx, erreurs, serveur } = await ouvrir([
    partie("bou_a", "Alpha", { etat: "preparee" }),
    partie("bou_b", "Bêta", { etat: "vue" })]);
  ok(await page.$$eval(".lv-recupere", (n) => n.length) === 1, "« Colis récupéré ici » chez Alpha, prête");
  ok(/La boutique prépare le colis/.test(await texte(page, '.lv-retrait[data-boutique="bou_b"]')),
    "Bêta prépare encore : on le dit");
  ok(await page.$(".lv-refuser") !== null, "rien de récupéré : il peut encore refuser");
  ok(await page.$(".lv-remettre-tout") === null, "pas encore de remise");
  await page.click(".lv-recupere");
  await page.waitForTimeout(600);
  const a = serveur.appels.find((x) => x.fn === "avancer_livraison");
  ok(a && a.corps.commande === "cmd_g" && a.corps.boutique === "bou_a" && a.corps.vers === "en_livraison",
    "avancer_livraison(cmd_g, bou_a, en_livraison)");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("3. Un colis récupéré : plus de refus");
{
  const { page, ctx, erreurs } = await ouvrir([
    partie("bou_a", "Alpha", { etat: "en_livraison" }),
    partie("bou_b", "Bêta", { etat: "preparee" })]);
  ok(await page.$(".lv-refuser") === null, "plus de « Refuser la course »");
  ok(/Colis récupéré/.test(await texte(page, '.lv-retrait[data-boutique="bou_a"]')), "Alpha : « Colis récupéré »");
  ok(await page.$('.lv-retrait[data-boutique="bou_b"] .lv-recupere') !== null, "Bêta : à récupérer");
  ok(/livrez toute la commande en une fois/.test(await texte(page, ".lv-course")), "« livrez toute la commande en une fois »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("4. Tout récupéré : une remise, un paiement");
{
  const { page, ctx, erreurs, serveur } = await ouvrir([
    partie("bou_a", "Alpha", { etat: "en_livraison", a_encaisser: 4000 }, { a_encaisser: 4000 }),
    partie("bou_b", "Bêta", { etat: "en_livraison", a_encaisser: 3000 }, { a_encaisser: 3000 })]);
  ok(await page.$$eval(".lv-remettre-tout", (n) => n.length) === 1, "un seul « Je l'ai remise »");
  await page.click(".lv-remettre-tout");
  await page.waitForTimeout(500);
  ok(plat(await page.$eval("#lv-momo-montant", (n) => n.textContent).catch(() => "")) === "7 000 FCFA",
    "la feuille montre au client 7 000 FCFA : toute la commande");
  await page.fill("#lv-transaction", "MP7654321");
  await page.click("#lv-remettre");
  await page.waitForTimeout(1200);
  const r = serveur.appels.find((x) => x.fn === "remettre_commande");
  ok(r && r.corps.commande === "cmd_g" && r.corps.montant === 7000 && r.corps.mode === "mobile_money" &&
     r.corps.motif === "MP7654321", "remettre_commande(cmd_g, 7000, mobile_money, MP7654321)");
  ok(!serveur.appels.some((x) => x.fn === "remettre_course"), "jamais remettre_course, boutique par boutique");
  ok(/7 000 FCFA payés par MoMoPay/.test(await toasts(page)), "« Colis remis : 7 000 FCFA payés par MoMoPay »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " échec(s)" : "\nTout tient ✔");
process.exit(echecs ? 1 : 0);
