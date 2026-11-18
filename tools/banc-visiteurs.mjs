/* =========================================================
   Banc : les visiteurs de la boutique (4.6.0)

   Ce qu'on prouve :
     1. la boutique note sa visite : un identifiant tiré au hasard, les
        écrans, le produit et la boutique ouverts, le panier — sans le
        jeton du client, sans nom ni numéro, et une fiche ne se compte
        qu'une fois par visite ;
     2. BIZZOO Admin, superadministrateur : Statistiques mène à
        « Visiteurs » — totaux, barres par jour (jours vides compris),
        parcours, plateformes, classements ; un administrateur de
        boutique n'y entre pas ;
     3. le site du personnel : Statistiques → « Visiteurs du site »,
        pour l'administration.

   La base est simulée : seules les réponses de Supabase sont jouées.
     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-visiteurs.mjs
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-visiteurs.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const plat = (s) => String(s || "").replace(/[  ]/g, " ").replace(/\s+/g, " ").trim();
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const iso = (d) => d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
const ilYA = (n) => { const d = new Date(); d.setDate(d.getDate() - n); return iso(d); };

const STATS = {
  periode: { depuis: ilYA(6), jusqu: ilYA(0) },
  total: { visiteurs: 120, visites: 200, duree_moyenne_s: 200, ecrans_moyens: 6.5, panier: 40, commande: 10, nouveaux: 80 },
  /* Trois jours sur sept : les quatre autres comptent, à zéro. */
  jours: [{ jour: ilYA(5), visiteurs: 30, visites: 50, duree_moyenne_s: 180 },
    { jour: ilYA(2), visiteurs: 60, visites: 100, duree_moyenne_s: 220 },
    { jour: ilYA(0), visiteurs: 30, visites: 50, duree_moyenne_s: 190 }],
  plateformes: { web: 150, android: 50 },
  produits: [{ id: "p1", nom: "Pagne wax", boutique: "Marché Afi", vues: 90 }, { id: "p2", nom: "Souris Alpha", boutique: "Alpha", vues: 12 }],
  boutiques: [{ id: "b1", nom: "Marché Afi", vues: 70 }, { id: "b2", nom: "Alpha", vues: 1 }],
};

/* ------------------------------------------------------------------ */
titre("1. La boutique note sa visite, sans nom ni numéro");
{
  const BOU = [{ id: "bou_a", nom: "Alpha", secteur: "Informatique", categorie_id: "cat_hightech", icone: "portable",
    couleur: "#0B7C8C", devise: "FCFA", indicatif: "229", actif: true, ordre: 1, ouvertures: null }];
  const PRODUITS = [{ id: "p_a", code: "p_a", nom: "Souris Alpha", reference: "p_a", prix: 5000, boutique_id: "bou_a",
    categorie_id: "cat_hightech", sous_categorie_id: null, stock: 5, disponible: true, sur_commande: false, images: [],
    video: "", en_avant: false, cree_le: "2026-09-01T10:00:00Z", modifie_le: "2026-09-01T10:00:00Z" }];
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2200 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  const envois = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(() => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.removeItem("impact-boutique");
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ external: { phone: true } }) }));
  await page.route("**/rest/v1/**", (r) => {
    const req = r.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c === "rpc/noter_visite") {
      let corps = null;
      try { corps = req.postDataJSON(); } catch (_) { corps = null; }
      envois.push({ corps, entetes: req.headers() });
      return r.fulfill({ status: 204, body: "" });
    }
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    if (c.startsWith("produits")) return d(PRODUITS);
    if (c.startsWith("categories")) return d([{ id: "cat_hightech", nom: "High-tech", ordre: 1, sous_categories: [] }]);
    if (c.startsWith("paiement")) return d([{ id: 1, actif: false, fournisseur: "feexpay" }]);
    return d([]);
  });
  const aller = async (h) => { await page.evaluate((x) => { location.hash = x; }, h); await pause(1200); };
  await page.goto(BASE + "/client/index.html");
  await pause(2500);
  await aller("#/boutique/bou_a");
  await aller("#/produit/p_a");
  await aller("#/");
  await aller("#/produit/p_a");            // la même fiche, une seconde fois
  await pause(5500);                        // les envois se groupent
  const tout = envois.map((x) => x.corps).filter(Boolean);
  const vues = tout.flatMap((x) => x.des_vues || []);
  ok(tout.length >= 1, "la boutique a noté la visite (" + tout.length + " envoi(s))");
  ok(tout.every((x) => /^[a-z0-9]{12,40}$/.test(x.le_visiteur) && /^[a-z0-9]{12,40}$/.test(x.la_session)) &&
     new Set(tout.map((x) => x.le_visiteur + "/" + x.la_session)).size === 1,
    "un visiteur et une visite, des identifiants tirés au hasard");
  ok(tout.reduce((t, x) => t + x.des_ecrans, 0) >= 4 && tout.every((x) => x.la_plateforme === "web"),
    "les écrans comptés (" + tout.reduce((t, x) => t + x.des_ecrans, 0) + "), depuis « web »");
  ok(vues.filter((v) => v.g === "produit" && v.c === "p_a").length === 1, "le produit ouvert deux fois ne compte qu'une fois par visite");
  ok(vues.filter((v) => v.g === "boutique" && v.c === "bou_a").length === 1, "la boutique ouverte compte");
  ok(envois.every((x) => !x.entetes.authorization), "l'envoi part sans le jeton du client");
  const cles = new Set(tout.flatMap((x) => Object.keys(x)));
  ok([...cles].sort().join(",") === "a_commande,au_panier,des_ecrans,des_vues,la_plateforme,la_session,le_visiteur",
    "rien d'autre ne part : ni nom, ni numéro, ni adresse");
  const avant = envois.length;
  await page.evaluate(() => { if (typeof Audience !== "undefined") Audience.panier(); });
  await pause(5000);
  ok(envois.slice(avant).some((x) => x.corps && x.corps.au_panier === true), "un article au panier se retient");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* ------------------------------------------------------------------ */
const jeton = (sub) => {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  return b64({ alg: "HS256" }) + "." + b64({ sub }) + ".s";
};
const SUP = "11111111-1111-1111-1111-111111111111";
const CHEF = "c6c60000-0000-0000-0000-000000000001";
const PROFILS = {
  [SUP]: { id: SUP, email: "sup@bizzoo.bj", nom: "Sup", role: "superadministrateur", actif: true, boutique_id: null, peut_modifier_produits: true },
  [CHEF]: { id: CHEF, email: "chef@alpha.bj", nom: "Chef", role: "administrateur", actif: true, boutique_id: "bou_a", peut_modifier_produits: true },
};
async function ouvrirAdmin(moi, hash) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2600 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  const appels = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: a.t, refresh_token: "r", expire_a: Date.now() + 3600000, email: a.email }));
  }, { t: jeton(moi), email: PROFILS[moi].email });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    let corps = null;
    try { corps = req.postDataJSON(); } catch (_) { corps = null; }
    if (c === "rpc/etat_connexion") return d({ equipe: true, sms_exige: false, session_confirmee: true, numero: true });
    if (c === "rpc/statistiques_visiteurs") { appels.push(corps); return d(STATS); }
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("profils")) return d([PROFILS[moi]]);
    if (c.startsWith("boutiques")) return d([{ id: "bou_a", nom: "Alpha", categorie_id: null, icone: "magasin", couleur: "#0B7C8C",
      devise: "FCFA", indicatif: "229", actif: true, ordre: 1 }]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await pause(2200);
  if (hash) { await page.evaluate((h) => { location.hash = h; }, hash); await pause(1500); }
  return { ctx, page, erreurs, appels };
}
const texte = (page, sel) => page.evaluate((s) => (document.querySelector(s) || {}).innerText || "", sel).then(plat);

titre("2. BIZZOO Admin : le superadministrateur lit les visiteurs");
{
  const o = await ouvrirAdmin(SUP, "#/statistiques");
  ok(!!(await o.page.$('a#st-visiteurs[href="#/visiteurs"]')), "Statistiques : une carte mène aux visiteurs");
  await o.page.click("#st-visiteurs");
  await pause(1500);
  const totaux = await texte(o.page, "#vi-totaux");
  ok(/120 visiteurs/.test(totaux) && /200 visites/.test(totaux), "120 visiteurs, 200 visites");
  ok(/3 min 20 s temps moyen par visite/.test(totaux) && /6,5 écrans par visite/.test(totaux),
    "le temps moyen en clair (3 min 20 s), 6,5 écrans par visite");
  ok(/80 nouveaux visiteurs/.test(totaux), "80 nouveaux visiteurs");
  const barres = await o.page.evaluate(() => [...document.querySelectorAll("#vi-barres .vi-barre span")].map((s) => s.style.height));
  ok(barres.length === 30, "trente jours de barres par défaut, jours vides compris (" + barres.length + ")");
  await o.page.click('#vi-periodes [data-periode="7j"]');
  await pause(1200);
  const b7 = await o.page.evaluate(() => [...document.querySelectorAll("#vi-barres .vi-barre span")].map((s) => s.style.height));
  ok(b7.length === 7 && b7.filter((x) => x === "0%").length === 4 && b7[4] === "100%",
    "« 7 jours » : sept barres, quatre jours à zéro, le plus haut à 100 % (" + b7.join(" ") + ")");
  ok(o.appels.length === 2 && o.appels[1].depuis === ilYA(6) && o.appels[1].jusqu === ilYA(0), "la période demandée à la base suit le bouton");
  const parcours = await texte(o.page, "#vi-parcours");
  ok(/panier 40 · 20 %/.test(parcours) && /commande payée 10 · 5 %/.test(parcours), "le parcours : 20 % au panier, 5 % jusqu'à la commande payée");
  const pf = await texte(o.page, "#vi-plateformes");
  ok(/Le site 150 · 75 %/.test(pf) && /L'application Android 50 · 25 %/.test(pf) && !/iPhone/.test(pf), "le site 75 %, l'application Android 25 %");
  const prod = await texte(o.page, "#vi-produits");
  ok(/1\. Pagne wax 90 vues Marché Afi/.test(prod) && /2\. Souris Alpha 12 vues/.test(prod), "les produits les plus consultés, avec leur boutique");
  ok(/1\. Marché Afi 70 vues/.test(await texte(o.page, "#vi-boutiques")) && /2\. Alpha 1 vue(?!s)/.test(await texte(o.page, "#vi-boutiques")),
    "les boutiques les plus consultées (« 1 vue » au singulier)");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}
{
  const o = await ouvrirAdmin(CHEF, "#/visiteurs");
  ok(!(await o.page.$("#vi-totaux")) && !o.appels.length, "l'administrateur d'une boutique n'y entre pas : rien n'est demandé à la base");
  await o.ctx.close();
}

/* ------------------------------------------------------------------ */
titre("3. Le site du personnel : Statistiques → « Visiteurs du site »");
{
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2600 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  const appels = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(() => {
    localStorage.setItem("bizzoo-personnel-session", JSON.stringify({ access_token: "jeton", refresh_token: "r",
      email: "awa@essai.bj", expire_a: Date.now() + 3600 * 1000 }));
  });
  const REPONSES = {
    etat_connexion: { equipe: false },
    rh_tableau_de_bord: { moi: { id: "e1", prenoms: "Awa", nom: "Essai", administration: true, ceo: false, profil: "Direction" } },
    rh_caisse_acces: null, rh_compteurs_solde: {}, rh_mes_menus: [], rh_suivi_alertes_nb: 0, rh_activation: null, rh_paie_a_jour: 0,
    statistiques_visiteurs: STATS,
  };
  await page.route(/supabase\.co\//, async (route) => {
    const u = new URL(route.request().url());
    const nom = (u.pathname.match(/\/rest\/v1\/rpc\/([a-z_0-9]+)/) || [])[1];
    if (nom === "statistiques_visiteurs") { try { appels.push(route.request().postDataJSON()); } catch (_) { appels.push(null); } }
    const valeur = nom && nom in REPONSES ? REPONSES[nom] : (nom ? null : []);
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(valeur) });
  });
  await page.goto(BASE + "/personnel/#/statistiques");
  await pause(2500);
  ok(/Visiteurs du site/.test(plat(await page.evaluate(() => document.body.innerText))), "le sommaire propose « Visiteurs du site »");
  await page.goto(BASE + "/personnel/#/statistiques/visiteurs?p=7j");
  await page.waitForSelector(".graphe", { timeout: 8000 }).catch(() => {});
  await pause(600);
  const t = plat(await page.evaluate(() => document.body.innerText));
  ok(/120 visiteurs/.test(t) && /200 visites/.test(t) && /3 min 20 s temps moyen par visite/.test(t), "les totaux : 120 visiteurs, 200 visites, 3 min 20 s");
  ok(await page.locator(".graphe-colonne").count() === 7, "« Visiteurs par jour » : sept jours, jours vides compris");
  ok(/article mis au panier 40 20 %/.test(t) && /commande payée 10 5 %/.test(t), "le parcours : 20 % au panier, 5 % à la commande payée");
  ok(/Pagne wax Marché Afi 90/.test(t) && /Marché Afi 70/.test(t), "les produits et les boutiques les plus consultés");
  ok(appels.length >= 1 && appels[appels.length - 1].depuis === ilYA(6), "la période demandée à la base : 7 jours");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs
  ? "\n\x1b[31m" + echecs + " constat(s) en échec ✘\x1b[0m"
  : "\n\x1b[32mLes visites se comptent sans nom ni numéro ; l'administration et le personnel lisent les totaux ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
