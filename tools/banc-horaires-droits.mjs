/* =========================================================
   Horaires des boutiques, et droits sur les produits (3.59.0)
   =========================================================
   La base refuse une commande chez une boutique fermée, et la création
   d'un produit sans habilitation (supabase/tests/99zzzzzzz-horaires.sql,
   99zzzzzz-produits-habilitation.sql). Les écrans :

   APPLICATION CLIENT
     1. les produits d'une boutique fermée en ce moment ne paraissent ni
        dans les listes ni dans la recherche ; ceux d'une boutique ouverte,
        si ;
     2. la page de la boutique fermée dit quand elle ouvre, sans vitrine ;
     3. la fiche d'un produit (lien partagé) n'a pas de panier ;
     4. le panier qui en contient ne laisse pas commander, et dit pourquoi ;
     5. « À propos » montre les horaires, jour par jour.

   APPLICATION VENDEUR
     6. créer une boutique demande ses jours et heures ; ils partent avec ;
     7. un administrateur de boutique sans habilitation n'a ni « + », ni
        « Ajouter un produit », ni formulaire ;
     8. la fiche d'un administrateur de boutique propose l'habilitation.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-horaires-droits.mjs");
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

/* « Fermée maintenant » sans dépendre de l'heure où le banc tourne :
   ouverte DEMAIN seulement, à l'heure du Bénin. */
const JOURS = ["lun", "mar", "mer", "jeu", "ven", "sam", "dim"];
const ici = new Date(Date.now() + 3600000);
const aujourdhui = (ici.getUTCDay() + 6) % 7;
const demain = JOURS[(aujourdhui + 1) % 7];
const FERMEE = { [demain]: { de: "08:00", a: "18:00" } };

const BOU = [
  { id: "bou_ouv", nom: "Alpha Ouverte", secteur: "Informatique", categorie_id: "cat_hightech",
    icone: "portable", couleur: "#0047D9", devise: "FCFA", indicatif: "229", actif: true, ordre: 1,
    ouvertures: null },
  { id: "bou_fer", nom: "Beta Fermée", secteur: "Informatique", categorie_id: "cat_hightech",
    icone: "portable", couleur: "#0047D9", devise: "FCFA", indicatif: "229", actif: true, ordre: 2,
    ouvertures: FERMEE },
];
const P = (id, boutique, nom) => ({ id, code: id, nom, reference: id, prix: 5000, boutique_id: boutique,
  categorie_id: "cat_hightech", sous_categorie_id: null, stock: 5, disponible: true, sur_commande: false,
  images: [], video: "", en_avant: false, cree_le: "2026-09-01T10:00:00Z", modifie_le: "2026-09-01T10:00:00Z" });
const PRODUITS = [P("p_ouv", "bou_ouv", "Souris Alpha"), P("p_fer", "bou_fer", "Clavier Beta")];

async function ouvrirClient(hash, panier) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2200 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((pan) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.removeItem("impact-boutique");
    if (pan) localStorage.setItem("bizzoo-panier", JSON.stringify(pan));
  }, panier || null);
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ external: { phone: true } }) }));
  await page.route("**/rest/v1/**", (r) => {
    const c = new URL(r.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    if (c.startsWith("produits")) return d(PRODUITS);
    if (c.startsWith("categories")) return d([{ id: "cat_hightech", nom: "High-tech", ordre: 1, sous_categories: [] }]);
    if (c.startsWith("paiement")) return d([{ id: 1, actif: false, fournisseur: "feexpay" }]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html" + (hash || ""));
  await pause(2500);
  return { ctx, page, erreurs };
}
const texte = (page) => page.evaluate(() => document.getElementById("vue").innerText.replace(/\s+/g, " "));
const aller = async (page, h) => { await page.evaluate((x) => { location.hash = x; }, h); await pause(1500); };
const sansErreur = (o) => ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));

titre("1. Les produits d'une boutique fermée ne paraissent pas");
{
  const o = await ouvrirClient("#/");
  const visibles = await o.page.evaluate(() => Catalogue.produitsDeLEnseigne().map((p) => p.id));
  ok(visibles.includes("p_ouv") && !visibles.includes("p_fer"),
    "la liste des produits : celui de la boutique ouverte, pas celui de la fermée (" + visibles.join(", ") + ")");
  const trouves = await o.page.evaluate(() => Catalogue.rechercher("clavier").map((p) => p.id));
  ok(!trouves.includes("p_fer"), "la recherche ne le remonte pas");
  ok(await o.page.evaluate(() => Catalogue.prochaineOuverture(Catalogue.boutiques().find((b) => b.id === "bou_fer")))
    === "demain à 08 h 00", "« demain à 08 h 00 » : l'heure de réouverture se calcule");
  await aller(o.page, "#/boutiques");
  ok(/Fermée · ouvre demain/.test(await texte(o.page)), "la liste des boutiques la dit fermée");
  sansErreur(o);

  titre("2. La page de la boutique fermée");
  await aller(o.page, "#/boutique/bou_fer");
  const t = await texte(o.page);
  ok(!!(await o.page.$("#bou-fermee")) && /Fermée en ce moment/.test(t) && /ouvre demain/.test(t),
    "un bandeau : fermée, elle ouvre demain");
  ok(/Boutique fermée en ce moment/.test(t) && !/Clavier Beta/.test(t), "pas de vitrine");
  await aller(o.page, "#/boutique/bou_ouv");
  ok(!(await o.page.$("#bou-fermee")) &&
     (await o.page.evaluate(() => Catalogue.produits().map((p) => p.id))).includes("p_ouv"),
    "la boutique ouverte, elle, n'a pas de bandeau, et ses produits sont là");

  titre("3. La fiche d'un produit partagé");
  await aller(o.page, "#/produit/p_fer");
  ok(!!(await o.page.$("#p-fermee")) && !(await o.page.$("#p-ajouter")),
    "boutique fermée : pas de panier, l'heure de réouverture à la place");
  await aller(o.page, "#/produit/p_ouv");
  ok(!!(await o.page.$("#p-ajouter")) && !(await o.page.$("#p-fermee")), "boutique ouverte : le panier");
  sansErreur(o);
  await o.ctx.close();
}

titre("4. Le panier qui contient un produit d'une boutique fermée");
{
  const o = await ouvrirClient("#/panier", [{ produitId: "p_fer", quantite: 1 }, { produitId: "p_ouv", quantite: 1 }]);
  ok(!!(await o.page.$("#pa-fermees")) && /Beta Fermée.*fermée en ce moment/.test(await texte(o.page)),
    "le panier le dit");
  ok(await o.page.evaluate(() => document.querySelector("#pa-commander").disabled), "et ne laisse pas commander");
  sansErreur(o);
  await o.ctx.close();
}
{
  const o = await ouvrirClient("#/panier", [{ produitId: "p_ouv", quantite: 1 }]);
  ok(!(await o.page.$("#pa-fermees")) &&
     !(await o.page.evaluate(() => document.querySelector("#pa-commander").disabled)),
    "boutique ouverte : on commande");
  await o.ctx.close();
}

titre("5. « À propos » montre les horaires");
{
  const o = await ouvrirClient("#/boutique/bou_fer?onglet=apropos");
  await o.page.evaluate(() => { const b = [...document.querySelectorAll(".bou-onglet")].find((x) => x.dataset.onglet === "apropos"); if (b) b.click(); });
  await pause(800);
  const t = await texte(o.page);
  ok(!!(await o.page.$("#bou-horaires")) && /fermée en ce moment/.test(t) && /Fermé/.test(t) && /08 h 00 – 18 h 00/.test(t),
    "jour par jour, avec l'état du moment");
  await o.ctx.close();
}

/* ---------- Application vendeur ---------- */
const jeton = (sub) => Buffer.from(JSON.stringify({ alg: "HS256" })).toString("base64url") + "." +
  Buffer.from(JSON.stringify({ sub })).toString("base64url") + ".s";
const SUPER = "b1110000-0000-0000-0000-000000000001";
const CHEF = "b2220000-0000-0000-0000-000000000002";
const PR = (id, email, role, boutique, extra) => ({ id, email, role, actif: true, peut_modifier_produits: true,
  boutique_id: boutique, nom: "", tel: "0197000000", ...(extra || {}) });
async function ouvrirAdmin(moi, profils, hash) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2400 } });
  const page = await ctx.newPage();
  const erreurs = [];
  const note = { boutiques: [] };
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
      if (req.method() === "POST") { const x = corpsDe(req); note.boutiques.push(x); return d([x], 201); }
      if (req.method() === "PATCH") { const x = corpsDe(req); (note.patch = note.patch || []).push(x); return d([x]); }
      return d([{ id: "bou_a", nom: "Alpha", categorie_id: "cat_hightech", icone: "magasin", couleur: "#0047D9",
        devise: "FCFA", indicatif: "229", actif: true, ordre: 1, ouvertures: null }]);
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

titre("6. Créer une boutique demande ses horaires");
{
  const profils = [PR(SUPER, "chef@bizzoo.bj", "superadministrateur", null)];
  const o = await ouvrirAdmin(SUPER, profils, "#/boutiques");
  await o.page.click("#bq-nouvelle");
  await pause(700);
  ok(!!(await o.page.$("#bq-ouvertures")), "le formulaire a ses jours et heures");
  await o.page.fill("#bq-nom", "Gamma");
  await o.page.evaluate(() => {
    const s = document.querySelector("#bq-categorie");
    if (s && s.options.length > 1) s.value = s.options[1].value;
    else if (s) { const opt = new Option("High-tech", "cat_hightech"); s.add(opt); s.value = "cat_hightech"; }
    for (const c of document.querySelectorAll("#bq-ouvertures [data-ouvert]")) c.checked = false;
  });
  await o.page.click("#bq-enregistrer");
  await pause(800);
  ok(!o.note.boutiques.length, "aucun jour ouvert : rien ne part");
  await o.page.evaluate(() => {
    const lun = document.querySelector('#bq-ouvertures [data-jour="lun"]');
    lun.querySelector("[data-ouvert]").checked = true;
    lun.querySelector("[data-de]").value = "09:00";
    lun.querySelector("[data-a]").value = "17:30";
  });
  await o.page.click("#bq-enregistrer");
  await pause(800);
  /* Les règles de publication, acceptées une fois : c'est un autre écran. */
  if (await o.page.$("[data-ugc-accord]")) {
    await o.page.check("[data-ugc-accord]");
    await o.page.click("[data-ugc-valider]");
  }
  await pause(1500);
  const b = o.note.boutiques[0] || {};
  ok(b.ouvertures && b.ouvertures.lun && b.ouvertures.lun.de === "09:00" && b.ouvertures.lun.a === "17:30" &&
     b.ouvertures.dim === null, "les horaires partent avec la boutique (" + JSON.stringify(b.ouvertures) + ")");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

titre("7. Un administrateur de boutique sans habilitation");
{
  const profils = [PR(CHEF, "chef@alpha.bj", "administrateur", "bou_a", { peut_modifier_produits: false })];
  const o = await ouvrirAdmin(CHEF, profils, "#/produits");
  ok(await o.page.evaluate(() => getComputedStyle(document.querySelector("#tabbar .tab-cta")).visibility) === "hidden",
    "le « + » de la barre est masqué");
  ok(!(await o.page.$('#vue a[href="#/produit/nouveau"]')), "pas de « Ajouter un produit »");
  await o.page.evaluate(() => { location.hash = "#/produit/nouveau"; });
  await pause(1200);
  ok(/Produits non autorisés/.test(await o.page.evaluate(() => document.getElementById("vue").innerText)),
    "le formulaire dit qu'il faut l'habilitation");
  await o.ctx.close();
}
{
  const profils = [PR(CHEF, "chef@alpha.bj", "administrateur", "bou_a", { peut_modifier_produits: true })];
  const o = await ouvrirAdmin(CHEF, profils, "#/produits");
  ok(await o.page.evaluate(() => getComputedStyle(document.querySelector("#tabbar .tab-cta")).visibility) !== "hidden",
    "habilité : le « + » est là");
  await o.ctx.close();
}

titre("8. La fiche d'un administrateur de boutique propose l'habilitation");
{
  const profils = [PR(SUPER, "chef@bizzoo.bj", "superadministrateur", null),
    PR(CHEF, "chef@alpha.bj", "administrateur", "bou_a", { nom: "Chef Alpha" })];
  const o = await ouvrirAdmin(SUPER, profils, "#/comptes");
  await o.page.click('[data-compte="' + CHEF + '"]');
  await pause(700);
  ok(await o.page.evaluate(() => { const z = document.querySelector("#cp-zone-modif"); return !!z && !z.hidden; }) &&
     /Peut créer et modifier les produits/.test(await o.page.evaluate(() => document.body.innerText)),
    "« Peut créer et modifier les produits », pour un administrateur aussi");
  await o.ctx.close();
}

titre("9. L'administrateur de boutique pose ses horaires dans Réglages");
{
  const profils = [PR(CHEF, "chef@alpha.bj", "administrateur", "bou_a", { nom: "Chef Alpha" })];
  const o = await ouvrirAdmin(CHEF, profils, "#/reglages");
  ok(!!(await o.page.$("#r-sans-horaires")) && !!(await o.page.$("#r-ouvertures")),
    "sans horaires encore : on l'y invite, et l'éditeur est là");
  await o.page.evaluate(() => {
    const dim = document.querySelector('#r-ouvertures [data-jour="dim"]');
    dim.querySelector("[data-ouvert]").checked = true;
    dim.querySelector("[data-de]").value = "10:00";
    dim.querySelector("[data-a]").value = "14:00";
    document.querySelector("#r-enregistrer").click();
  });
  await pause(1500);
  if (await o.page.$("[data-ugc-accord]")) {
    await o.page.check("[data-ugc-accord]");
    await o.page.click("[data-ugc-valider]");
    await pause(1500);
  }
  const ecrit = (o.note.patch || []).find((x) => x && x.ouvertures) || {};
  ok(ecrit.ouvertures && ecrit.ouvertures.dim && ecrit.ouvertures.dim.de === "10:00" &&
     ecrit.ouvertures.lun && ecrit.ouvertures.lun.de === "08:00",
    "ses horaires s'enregistrent (" + JSON.stringify(ecrit.ouvertures) + ")");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " constat(s) en échec." : "\nTous les constats sont bons.");
process.exit(echecs ? 1 : 0);
