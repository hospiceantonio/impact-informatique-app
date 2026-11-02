/* =========================================================
   Banc — deux langues, français et anglais (3.73.0)

     1. les trois applications ouvrent leurs écrans en anglais : aucun
        texte français visible (hors contenus saisis, translate="no") ;
     2. le bouton FR / EN change de langue et s'en souvient ;
     3. ce qu'une boutique a écrit (nom, description d'un produit) reste
        tel quel ;
     4. en français, rien ne change : aucun texte touché ;
     5. les dates suivent la langue ; le téléphone qui parle anglais ouvre
        l'application en anglais ;
     6. langue.js est le même fichier dans les trois applications et la
        vitrine ; chaque dictionnaire est à jour.

   La base est simulée : seules les réponses de Supabase sont jouées.
   ========================================================= */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
const { chromium } = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default;
const RACINE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const BASE = process.env.BANC_URL || "http://127.0.0.1:5191";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");

/* Un texte encore français : un mot-outil ou un mot du métier, sans mot
   anglais autour (« mission », « Code », les noms propres passent). */
const FR = /(^|[^A-Za-zÀ-ÿ])(le|la|les|des|du|une|vos|votre|vous|pour|avec|sans|dans|est|sont|pas|commande|commandes|panier|boutique|boutiques|livraison|livreur|livreurs|produit|produits|employé|employés|dépense|dépenses|ajouter|voir|tout|toutes|aucun|aucune|compte|comptes|réglages|accueil|prix|à|où|être|déjà|ici|ce|cette|ces|qui|que|enregistrer|modifier|supprimer)([^A-Za-zÀ-ÿ]|$)/i;
const ANGLAIS = /\b(the|and|your|to|of|for|is|are|a|an|this|no|with)\b/i;
async function restes(page) {
  const textes = await page.evaluate(() => {
    const out = [];
    const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    let n;
    while ((n = w.nextNode())) {
      const el = n.parentElement;
      if (!el || el.closest('[translate="no"],script,style') || !el.getClientRects().length) continue;
      const s = n.data.trim();
      if (s) out.push(s);
    }
    for (const el of document.querySelectorAll("[placeholder],[aria-label],[title]")) {
      if (!el.getClientRects().length || el.closest('[translate="no"]')) continue;
      for (const a of ["placeholder", "aria-label", "title"]) { const v = el.getAttribute(a); if (v) out.push(v); }
    }
    return out;
  });
  return [...new Set(textes.filter((s) => FR.test(s) && !ANGLAIS.test(s) && !/^(vous|Missions?)$/i.test(s)))];
}

const nav = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined, args: ["--no-sandbox"] });
const erreurs = [];
async function contexte(langue, init) {
  const ctx = await nav.newContext({ viewport: { width: 1280, height: 1000 }, serviceWorkers: "block",
    locale: langue === "appareil-en" ? "en-US" : "fr-FR" });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(([l, i]) => {
    /* Une seule fois : le choix fait au bouton doit survivre au rechargement. */
    if ((l === "en" || l === "fr") && !localStorage.getItem("bizzoo-langue")) localStorage.setItem("bizzoo-langue", l);
    for (const [k, v] of Object.entries(i || {})) localStorage.setItem(k, v);
  }, [langue, init]);
  return { ctx, page };
}

/* ---------------- L'application client ---------------- */
const PROD = (id, nom, prix, o = {}) => ({ id, boutique_id: "bou_a", nom, code: "C" + id.slice(-1), prix,
  categorie_id: "cat_hightech", sous_categorie_id: "sc_x", stock: 3, disponible: true, images: [],
  description: "Très bon casque, livré avec son câble et sa housse.",
  masque: false, cree_le: "2026-10-01T08:00:00Z", modifie_le: "2026-10-01T08:00:00Z", ...o });
async function client(page) {
  await page.route("**/rest/v1/**", (route) => {
    const c = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("produits")) return d([PROD("prod_a", "Câble USB", 2000), PROD("prod_b", "Casque Bluetooth", 15000)]);
    if (c.startsWith("categories")) return d([{ id: "cat_hightech", nom: "High-tech", icone: "informatique", ordre: 1,
      sous_categories: [{ id: "sc_x", nom: "Accessoires", ordre: 1 }] }]);
    if (c.startsWith("boutiques")) return d([{ id: "bou_a", nom: "Alpha Informatique", categorie_id: "cat_hightech", icone: "magasin",
      couleur: "#0047D9", devise: "FCFA", indicatif: "229", whatsapp: "97000001", actif: true, ordre: 1 }]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    if (c.startsWith("reglages")) return d([{ compte_obligatoire: false }]);
    return d([]);
  });
}
const CFG = { "impact-config": JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }) };

titre("1. L'application client en anglais : aucun texte français oublié");
{
  const { ctx, page } = await contexte("en", CFG);
  await client(page);
  await page.goto(BASE + "/client/index.html#/");
  await page.waitForTimeout(2500);
  const tous = new Map();
  for (const h of ["#/", "#/produit/prod_b", "#/categories", "#/panier", "#/connexion", "#/recherche", "#/boutique/bou_a", "#/infos"]) {
    await page.evaluate((x) => { location.hash = x; }, h);
    await page.waitForTimeout(900);
    for (const s of await restes(page)) tous.set(s, h);
  }
  ok(tous.size === 0, "8 écrans, aucun texte français" + (tous.size ? " : " + [...tous].slice(0, 4).map(([s, h]) => h + " « " + s.slice(0, 60) + " »").join(" ; ") : ""));
  await page.evaluate(() => { location.hash = "#/produit/prod_b"; });
  await page.waitForTimeout(900);
  const fiche = await page.evaluate(() => ({ nom: document.querySelector(".fiche-nom").innerText,
    desc: (document.querySelector(".fiche-description") || {}).innerText || "",
    bouton: (document.getElementById("p-ajouter") || {}).innerText || "", lang: document.documentElement.lang }));
  ok(fiche.bouton === "Add to cart" && fiche.lang === "en", "« Add to cart », et la page se déclare en anglais");
  ok(fiche.nom === "Casque Bluetooth" && /livré avec son câble/.test(fiche.desc),
    "le nom et la description écrits par la boutique restent tels quels");
  const date = await page.evaluate(() => new Date(2026, 9, 22).toLocaleDateString("fr-FR", { day: "numeric", month: "long", year: "numeric" }));
  ok(date === "22 October 2026", "les dates suivent la langue (" + date + ")");
  await ctx.close();
}

titre("2. Le bouton FR / EN : il change de langue et s'en souvient");
{
  const { ctx, page } = await contexte("fr", CFG);
  await client(page);
  await page.goto(BASE + "/client/index.html#/connexion");
  await page.waitForTimeout(2500);
  ok(await page.locator("#cp-langue .langue-choix button.actif").innerText() === "FR", "en français : FR est marqué");
  ok(/Se connecter/.test(await page.evaluate(() => document.body.innerText)), "l'écran est en français");
  await Promise.all([page.waitForNavigation({ timeout: 6000 }).catch(() => {}), page.click("#cp-langue .langue-choix button:has-text('EN')")]);
  await page.waitForTimeout(2500);
  ok(await page.evaluate(() => localStorage.getItem("bizzoo-langue")) === "en", "le choix est retenu sur l'appareil");
  ok(/Sign in/.test(await page.evaluate(() => document.body.innerText)), "la page se recharge en anglais");
  ok(await page.locator("#cp-langue .langue-choix button.actif").innerText() === "EN", "EN est marqué");
  await ctx.close();
}

titre("3. En français, rien ne change ; un téléphone en anglais ouvre en anglais");
{
  const { ctx, page } = await contexte("fr", CFG);
  await client(page);
  await page.goto(BASE + "/client/index.html#/panier");
  await page.waitForTimeout(2500);
  const t = await page.evaluate(() => document.body.innerText);
  ok(/Mon panier|Votre panier/.test(t) && !/My cart/.test(t), "en français : l'écran reste en français");
  await ctx.close();
}
{
  const { ctx, page } = await contexte("appareil-en", CFG);
  await client(page);
  await page.goto(BASE + "/client/index.html#/panier");
  await page.waitForTimeout(2500);
  ok(/cart/i.test(await page.evaluate(() => document.body.innerText)), "téléphone réglé en anglais, sans choix : l'application s'ouvre en anglais");
  await ctx.close();
}

/* ---------------- BIZZOO Admin ---------------- */
titre("4. BIZZOO Admin en anglais");
{
  const SUP = "11111111-1111-1111-1111-111111111111";
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const { ctx, page } = await contexte("en", { "impact-config": JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }),
    "impact-session": JSON.stringify({ access_token: b64({ alg: "HS256" }) + "." + b64({ sub: SUP }) + ".s", refresh_token: "r",
      expire_a: Date.now() + 3600000, email: "sup@bizzoo.bj" }) });
  const appels = [];
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request(); const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) appels.push({ f: c.slice(4), corps: (() => { try { return req.postDataJSON(); } catch (_) { return null; } })() });
    if (c === "rpc/etat_connexion") return d({ equipe: true, sms_exige: false, session_confirmee: true, numero: true });
    if (c.startsWith("profils")) return d([{ id: SUP, email: "sup@bizzoo.bj", nom: "Sup", role: "superadministrateur", actif: true,
      peut_modifier_produits: true, boutique_id: null }]);
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("boutiques")) return d([{ id: "bou_a", nom: "Alpha", actif: true, devise: "FCFA", indicatif: "229" }]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/admin/index.html");
  await page.waitForTimeout(3000);
  const tous = new Map();
  for (const h of ["#/", "#/commandes", "#/produits", "#/stock", "#/categories", "#/comptes", "#/livreurs", "#/vendeurs", "#/reglages",
    "#/reversements", "#/compte", "#/notifications", "#/statistiques", "#/boutiques", "#/codes", "#/caisse", "#/solde", "#/sav",
    "#/avis", "#/historique", "#/clients", "#/validations", "#/slider", "#/faire-livrer"]) {
    await page.evaluate((x) => { location.hash = x; }, h);
    await page.waitForTimeout(700);
    for (const s of await restes(page)) tous.set(s, h);
  }
  ok(tous.size === 0, "24 écrans, aucun texte français" + (tous.size ? " : " + [...tous].slice(0, 4).map(([s, h]) => h + " « " + s.slice(0, 60) + " »").join(" ; ") : ""));
  ok(appels.some((a) => a.f === "regler_langue" && a.corps && a.corps.langue === "en"), "connecté : la base apprend la langue du compte (regler_langue « en »)");
  const n = await page.evaluate(() => [Langue.traduire("Commande BZ-000104 — il part bientôt."),
    Langue.traduire("Récupérer : Alpha\nLivrer à : Afi — Fidjrossè\nRien à récupérer : tout est payé.")]);
  ok(n[0] === "Order BZ-000104 — it's leaving soon." && n[1] === "Pick up: Alpha\nDeliver to: Afi — Fidjrossè\nNothing to collect: everything is paid.",
    "les notifications de la base se lisent en anglais dans la cloche");
  await ctx.close();
}

/* ---------------- BIZZOO Personnel ---------------- */
titre("5. BIZZOO Personnel en anglais");
{
  const { ctx, page } = await contexte("en", { "bizzoo-personnel-session": JSON.stringify({ access_token: "j", refresh_token: "r",
    email: "a@b.bj", expire_a: Date.now() + 3600000 }) });
  const R = { etat_connexion: { equipe: false }, rh_tableau_de_bord: { moi: { id: "e1", prenoms: "Awa", nom: "Essai", administration: true,
    ceo: true, super: true, profil: "Direction" } }, rh_mes_menus: [], rh_compteurs_solde: {}, rh_reversements_acces: true,
    rh_suivi_alertes_nb: 0, rh_incidents_ouverts_nb: 0, rh_paie_a_jour: 0 };
  await page.route(/supabase\.co\//, (r) => { const n = (new URL(r.request().url()).pathname.match(/rpc\/([a-z_0-9]+)/) || [])[1];
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(n && n in R ? R[n] : (n ? null : [])) }); });
  await page.goto(BASE + "/personnel/");
  await page.waitForTimeout(2500);
  const routes = await page.evaluate(() => [...document.querySelectorAll("#menu-lateral a[data-route]")].map((a) => a.dataset.route));
  const tous = new Map();
  for (const r of routes) {
    await page.evaluate((x) => { location.hash = "#/" + x; }, r);
    await page.waitForTimeout(600);
    for (const s of await restes(page)) tous.set(s, r);
  }
  ok(routes.length >= 15, routes.length + " menus parcourus");
  ok(tous.size === 0, "aucun texte français" + (tous.size ? " : " + [...tous].slice(0, 4).map(([s, h]) => h + " « " + s.slice(0, 60) + " »").join(" ; ") : ""));
  ok(await page.locator("#menu-lateral .langue-choix").count() === 1, "le bouton FR / EN est au pied du menu");
  await ctx.close();
}

/* ---------------- La vitrine ---------------- */
titre("6. La vitrine et les pages légales");
{
  const { ctx, page } = await contexte("en");
  await page.goto(BASE + "/index.html");
  await page.waitForTimeout(1200);
  ok(await page.locator(".langue-flottant").count() === 1, "un bouton FR / EN flottant");
  const r1 = await restes(page);
  await page.goto(BASE + "/legal/confidentialite.html");
  await page.waitForTimeout(1000);
  const r2 = await restes(page);
  ok(!r1.length && !r2.length, "l'accueil du site et la politique de confidentialité, en anglais" +
    ([...r1, ...r2].length ? " : « " + [...r1, ...r2][0].slice(0, 60) + " »" : ""));
  await ctx.close();
}

titre("7. Un seul langue.js ; des dictionnaires à jour");
{
  const original = fs.readFileSync(path.join(RACINE, "client/js/langue.js"), "utf8");
  ok(["admin/js/langue.js", "personnel/js/langue.js", "vitrine/langue.js"].every((f) => fs.readFileSync(path.join(RACINE, f), "utf8") === original),
    "les copies sont identiques à client/js/langue.js (tools/synchroniser-langue.sh)");
  const manques = ["client", "admin", "personnel", "vitrine"].map((a) => {
    try { return [a, JSON.parse(fs.readFileSync(path.join(RACINE, "i18n", a + ".a-traduire.json"), "utf8")).length]; }
    catch (_) { return [a, -1]; }
  });
  ok(manques.every(([, n]) => n === 0), "aucun texte en attente de traduction (" + manques.map(([a, n]) => a + " " + n).join(", ") + ")");
}
ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));

await nav.close();
console.log(echecs ? "\n" + echecs + " ÉCHEC(S)" : "\nTout tient ✔");
process.exit(echecs ? 1 : 0);
