/* =========================================================
   Cinq idées des maquettes BIZZOO Market, éprouvées (4.1.0)
   =========================================================
   1. L'accueil s'ouvre sur « Bonjour 👋 » (ou « Bonsoir »), la question,
      puis la recherche — sa loupe dans un bouton turquoise.
   2. Le « + » des cartes ajoute au panier SANS ouvrir la fiche ; il
      n'existe pas pour un produit en rupture ; pour un produit à
      accompagnements, il ouvre la fiche (on y choisit).
   3. En promotion, le prix est rouge et l'ancien barré ; hors promotion,
      il garde le turquoise des prix.
   4. Le panier : « − 1 + » sur chaque ligne, et ils règlent la quantité.
   5. Le suivi en frise : l'heure sous chaque étape franchie, telle que la
      base la donne — rien pour une étape sans heure, rien au-delà de
      l'étape en cours ; sans compte par « heures_etapes_suivies », avec
      un compte par la colonne « heures_etapes » — et une base qui ne la
      connaît pas encore n'empêche pas de lire ses commandes.

     PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-idees-maquettes.mjs
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-idees-maquettes.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const CATS = [{ id: "cat_h", nom: "Informatique", icone: "portable", couleur: "#007F7C", en_avant: true,
  ordre: 1, boutique_id: null, sous_categories: [{ id: "sc_h", nom: "Tout", ordre: 1 }] }];
const BOUT = [
  { id: "bou_a", nom: "Alpha", secteur: "Informatique", categorie_id: "cat_h", ordre: 1 },
  { id: "bou_b", nom: "Bêta", secteur: "Restauration", categorie_id: "cat_h", ordre: 2 },
].map((b) => ({ ...b, icone: "magasin", couleur: "#007F7C", devise: "FCFA", indicatif: "229",
  actif: true, slogan: "", photos: [], note_moyenne: null, nb_avis: 0 }));
const P = (id, bou, nom, prix, o = {}) => ({ id, boutique_id: bou, nom, code: id.slice(-3), reference: "",
  description: "", prix, ancien_prix: null, categorie_id: "cat_h", sous_categorie_id: "sc_h",
  stock: 5, sur_commande: false, disponible: true, en_avant: false, ordre_avant: 0, images: [],
  video: "", cree_le: "2026-09-01T08:00:00Z", modifie_le: "2026-09-01T08:00:00Z",
  note_moyenne: null, nb_avis: 0, ...o });
const PROD = [
  P("prod_riz", "bou_a", "Riz parfumé 5 kg", 3500, { ancien_prix: 4000 }),
  P("prod_huile", "bou_a", "Huile végétale 1 L", 1200),
  P("prod_sucre", "bou_a", "Sucre blanc 1 kg", 1000, { stock: 0 }),
  /* Le menu du restaurant a ses accompagnements (3.80.0). */
  P("prod_menu", "bou_b", "Poulet braisé", 3000,
    { accompagnements: [{ id: "acc_alloco", nom: "Alloco", prix: 500, max: 2 }] }),
];

/** La commande, telle que ce téléphone la garde, et le suivi de la base. */
const COMMANDE = { id: "cmd_s", numero: "BZ-0S1", total: 7500, devise: "FCFA", etat: "payee", acompte: 7500,
  taux_acompte: 100, reste: 0, frais_livraison: 0,
  client: { nom: "Awa", tel: "0197000011", indicatif: "229", adresse: "Cotonou" },
  boutiques: [{ id: "bou_a", nom: "Alpha", montant: 7500,
    lignes: [{ nom: "Riz parfumé 5 kg", code: "riz", reference: "", prix: 7500, quantite: 1 }] }],
  gardeeLe: Date.now() - 3600000 };
const SUIVI = (etat) => ({ numero: "BZ-0S1", etat: "payee", total: 7500, devise: "FCFA", taux_acompte: 100,
  acompte: 7500, verse: 7500, reste: 0, restes: {}, encaissements: {}, paye_livraison: 0,
  etats: { bou_a: { etat, confirme: false } } });
const ilYa = (min) => new Date(Date.now() - min * 60000).toISOString();

async function ouvrir({ hash = "", panier = null, commandes = null, suivi = null, heures = null,
                        session = false, base = null, largeur = 390 } = {}) {
  const ctx = await nav.newContext({ viewport: { width: largeur, height: 900 }, locale: "fr-FR", deviceScaleFactor: process.env.CAPTURES ? 2 : 1 });
  const page = await ctx.newPage();
  const erreurs = [];
  const note = { heures: 0, lectures: [] };
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "cle" }));
    localStorage.removeItem("impact-boutique");
    if (a.panier) localStorage.setItem("bizzoo-panier", JSON.stringify(a.panier));
    if (a.commandes) localStorage.setItem("bizzoo-commandes", JSON.stringify(a.commandes));
    if (a.session) {
      const b64 = (o) => btoa(JSON.stringify(o)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
      localStorage.setItem("bizzoo-session", JSON.stringify({
        access_token: b64({ alg: "HS256" }) + "." + b64({ sub: "c1000000-0000-4000-8000-000000000001", phone: "2290197000011" }) + ".s",
        refresh_token: "r", expire_a: Date.now() + 3600000, email: "", tel: "2290197000011" }));
    }
  }, { panier, commandes, session });
  await page.route("**/rest/v1/**", (route) => {
    const u = new URL(route.request().url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x, statut = 200) => route.fulfill({ status: statut, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("categories")) return d(CATS);
    if (c.startsWith("boutiques")) return d(BOUT);
    if (c.startsWith("produits")) return d(PROD);
    if (c === "rpc/suivre_commande") return d(suivi);
    if (c === "rpc/heures_etapes_suivies") { note.heures++; return d(heures); }
    if (c.startsWith("commandes") && base) {
      const select = u.searchParams.get("select") || "";
      note.lectures.push(select);
      return base(select, d);
    }
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/client/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1500);
  if (hash) {
    await page.evaluate((h) => { location.hash = h; }, hash);
    await page.waitForTimeout(1500);
  }
  return { page, ctx, erreurs, note };
}
const panierLu = (page) => page.evaluate(() => JSON.parse(localStorage.getItem("bizzoo-panier") || "[]"));

/* ------------------------------------------------------------------ */
titre("1. L'accueil : « Bonjour 👋 », la question, la recherche");
{
  const { page, ctx, erreurs } = await ouvrir();
  const a = await page.evaluate(() => {
    const vue = document.getElementById("vue");
    const s = vue.firstElementChild;
    const pil = s && s.querySelector(".recherche-pilule");
    const loupe = pil && pil.querySelector(".recherche-pilule-loupe");
    return {
      premier: !!s && s.matches(".accueil-salut"),
      titre: s ? (s.querySelector("h2") || {}).textContent || "" : "",
      question: s ? (s.querySelector(".accueil-salut-question") || {}).textContent || "" : "",
      lien: pil ? pil.getAttribute("href") : "",
      loupe: loupe ? getComputedStyle(loupe).backgroundColor : "",
      fond: s ? getComputedStyle(s).backgroundColor : "",
    };
  });
  ok(a.premier, "le bandeau du bonjour ouvre l'accueil");
  ok(/^(Bonjour|Bonsoir)\s+👋$/.test(a.titre.trim()), "« Bonjour 👋 » ou « Bonsoir 👋 » (" + a.titre.trim() + ")");
  ok(a.question.trim() === "Que souhaitez-vous acheter ?", "puis la question");
  ok(a.fond === "rgb(15, 30, 38)", "sur l'anthracite de la barre du haut (" + a.fond + ")");
  ok(a.lien === "#/recherche", "la recherche est dedans, et mène à l'écran de recherche");
  ok(a.loupe === "rgb(0, 127, 124)", "sa loupe dans un bouton turquoise (" + a.loupe + ")");
  ok(!erreurs.length, "sans erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("2. Le « + » des cartes : ajouter sans ouvrir la fiche");
{
  const { page, ctx, erreurs } = await ouvrir({ hash: "#/boutique/bou_a" });
  const v = await page.evaluate(() => [...document.querySelectorAll(".bou-vignette")].map((a) => ({
    lien: a.getAttribute("href"), plus: !!a.querySelector(".p-ajout[data-ajout]") })));
  const de = (id) => v.find((x) => x.lien === "#/produit/" + id) || {};
  ok(de("prod_riz").plus && de("prod_huile").plus, "les vignettes de la boutique ont leur « + »");
  ok(de("prod_sucre").lien && !de("prod_sucre").plus, "pas de « + » pour un produit en rupture");
  await page.click('.bou-vignette[href="#/produit/prod_huile"] .p-ajout');
  await page.waitForTimeout(400);
  let p = await panierLu(page);
  ok(p.length === 1 && p[0].produitId === "prod_huile" && p[0].quantite === 1, "un toucher : l'huile est dans le panier");
  ok(await page.evaluate(() => location.hash) === "#/boutique/bou_a", "et l'on reste sur la boutique");
  await page.click('.bou-vignette[href="#/produit/prod_huile"] .p-ajout');
  await page.waitForTimeout(300);
  p = await panierLu(page);
  ok(p.length === 1 && p[0].quantite === 2, "un second toucher : deux");
  ok(/Ajouté au panier/.test(await page.evaluate(() => document.body.innerText)), "« Ajouté au panier » le dit");
  ok(!erreurs.length, "sans erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  /* Le stock compte ce qui est déjà dans le panier. */
  const { page, ctx } = await ouvrir({ hash: "#/produits", panier: [{ produitId: "prod_riz", quantite: 5 }] });
  await page.click('.p-carte[href="#/produit/prod_riz"] .p-ajout');
  await page.waitForTimeout(400);
  const p = await panierLu(page);
  ok(p[0].quantite === 5, "au stock déjà dans le panier, le « + » n'ajoute rien");
  ok(/en stock dans votre panier/.test(await page.evaluate(() => document.body.innerText)), "et dit pourquoi");
  await ctx.close();
}
{
  const { page, ctx } = await ouvrir({ hash: "#/boutique/bou_b" });
  const sel = '.bou-vignette[href="#/produit/prod_menu"] .p-ajout';
  ok(!!(await page.$(sel)) && !(await page.$(sel + "[data-ajout]")),
    "un produit à accompagnements garde un « + », qui n'ajoute pas d'office");
  await page.click(sel);
  await page.waitForTimeout(800);
  ok(await page.evaluate(() => location.hash) === "#/produit/prod_menu", "il ouvre la fiche, où l'on choisit");
  ok((await panierLu(page)).length === 0, "et rien n'est entré au panier");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("3. Le prix en promotion, en rouge");
{
  const { page, ctx } = await ouvrir({ hash: "#/produits" });
  const c = await page.evaluate(() => {
    const prix = (id) => {
      const a = document.querySelector('.p-carte[href="#/produit/' + id + '"]');
      const x = a && a.querySelector(".prix-actuel");
      return { couleur: x ? getComputedStyle(x).color : "", barre: !!(a && a.querySelector("s.prix-ancien")) };
    };
    return { riz: prix("prod_riz"), huile: prix("prod_huile") };
  });
  ok(c.riz.couleur === "rgb(217, 45, 32)" && c.riz.barre, "en promotion : rouge, l'ancien prix barré (" + c.riz.couleur + ")");
  ok(c.huile.couleur === "rgb(0, 127, 124)" && !c.huile.barre, "hors promotion : le turquoise des prix (" + c.huile.couleur + ")");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("4. Le panier : « − 1 + » sur chaque ligne");
{
  const { page, ctx } = await ouvrir({ hash: "#/panier", panier: [{ produitId: "prod_riz", quantite: 1 }, { produitId: "prod_huile", quantite: 2 }] });
  ok((await page.$$(".pa-ligne .pa-compteur")).length === 2, "deux lignes, deux compteurs");
  await page.click('.pa-ligne [data-panier-action="plus"][data-produit="prod_riz"]');
  await page.waitForTimeout(300);
  await page.click('.pa-ligne [data-panier-action="moins"][data-produit="prod_huile"]');
  await page.waitForTimeout(300);
  const p = await panierLu(page);
  ok(p.find((l) => l.produitId === "prod_riz").quantite === 2 && p.find((l) => l.produitId === "prod_huile").quantite === 1,
    "« + » et « − » règlent la quantité de leur ligne");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("5. Le suivi en frise, avec l'heure de chaque étape");
{
  const heures = { bou_a: { nouvelle: ilYa(40), vue: ilYa(35), en_livraison: ilYa(5), remise: ilYa(1) } };
  const { page, ctx, erreurs, note } = await ouvrir({ hash: "#/commande/cmd_s", commandes: [COMMANDE],
    suivi: SUIVI("en_livraison"), heures });
  await page.waitForTimeout(1200);
  const f = await page.evaluate(() => [...document.querySelectorAll(".re-frise .re-etape")].map((e) => ({
    faite: e.classList.contains("faite"), courante: e.classList.contains("courante"),
    heure: (e.querySelector(".re-etape-heure") || {}).textContent || "" })));
  ok(note.heures >= 1, "sans compte, les heures sont demandées par le numéro (heures_etapes_suivies)");
  ok(f.length === 5 && f.filter((x) => x.faite).length === 4 && f[3].courante, "cinq étapes, quatre franchies, « En livraison » en cours");
  ok(/^\d\d:\d\d$/.test(f[0].heure) && /^\d\d:\d\d$/.test(f[1].heure) && /^\d\d:\d\d$/.test(f[3].heure),
    "l'heure sous « reçue », « vue » et « en livraison » (" + f.map((x) => x.heure || "—").join(" ") + ")");
  ok(f[2].heure === "", "rien sous « préparée » : la base n'en a pas l'heure, rien n'est inventé");
  ok(f[4].heure === "", "rien au-delà de l'étape en cours, même si une heure traîne");
  ok(!erreurs.length, "sans erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  /* Une base d'avant : la fonction n'existe pas. Le suivi reste, sans heures. */
  const { page, ctx, erreurs } = await ouvrir({ hash: "#/commande/cmd_s", commandes: [COMMANDE],
    suivi: SUIVI("preparee"), heures: null });
  await page.waitForTimeout(1200);
  const n = await page.evaluate(() => ({ faites: document.querySelectorAll(".re-frise .re-etape.faite").length,
    heures: document.querySelectorAll(".re-etape-heure").length }));
  ok(n.faites === 3 && n.heures === 0, "sans heures connues, la frise s'affiche quand même, sans heures");
  ok(!erreurs.length, "sans erreur JavaScript");
  await ctx.close();
}
{
  /* Avec un compte : la colonne « heures_etapes » vient avec la commande. */
  const ligne = (etat) => ({ boutique_id: "bou_a", produit_id: "prod_riz", nom: "Riz parfumé 5 kg", code: "riz",
    reference: "", prix: 7500, quantite: 1, etat, confirme_le: null });
  const enBase = (avecHeures) => ({ id: "cmd_s", numero: "BZ-0S1", total: 7500, devise: "FCFA", etat: "payee",
    remarque: "", note: "", cree_le: ilYa(60), revendeur: false, client_nom: "Awa", client_tel: "0197000011",
    client_indicatif: "229", client_adresse: "Cotonou", acompte: 7500, taux_acompte: 100, verse: 7500,
    restes: { reste: 0, boutiques: {} }, frais_livraison: 0, commande_lignes: [ligne("preparee")],
    ...(avecHeures ? { heures_etapes: { bou_a: { nouvelle: ilYa(40), vue: ilYa(30), preparee: ilYa(10) } } } : {}) });
  const { page, ctx, note } = await ouvrir({ hash: "#/commande/cmd_s", session: true,
    base: (select, d) => d([enBase(/heures_etapes/.test(select))]) });
  await page.waitForTimeout(1500);
  const h = await page.evaluate(() => [...document.querySelectorAll(".re-frise .re-etape-heure")].map((x) => x.textContent));
  ok(note.lectures.some((s) => /heures_etapes/.test(s)), "la lecture des commandes demande « heures_etapes »");
  ok(h.length === 3, "les trois étapes franchies portent leur heure (" + h.join(" ") + ")");
  const mots = await page.evaluate(() => [...document.querySelectorAll(".re-frise .re-etape-mot")].map((x) => x.textContent));
  if (process.env.CAPTURES) {
    const f = await page.$(".re-suivi");
    if (f) { await f.scrollIntoViewIfNeeded(); await page.screenshot({ path: process.env.CAPTURES + "/recu-frise.png" }); }
  }
  ok(mots[0] === "Commande confirmée" && mots[4] === "Livrée",
    "(4.3.0) les mots du client : « Commande confirmée » … « Livrée » (" + mots.join(", ") + ")");
  await ctx.close();
}
{
  /* (4.3.0) « Mes commandes » : l'heure sous chaque palier franchi de la
     barre — deux boutiques, l'heure est celle de la dernière. */
  const ligne = (b, etat) => ({ boutique_id: b, produit_id: "prod_riz", nom: "Riz", code: "riz",
    reference: "", prix: 3500, quantite: 1, etat, confirme_le: null });
  const quand = (h, m) => { const d = new Date(); d.setHours(h, m, 0, 0); return d.toISOString(); };
  const cmd = { id: "cmd_m", numero: "BZ-0M1", total: 7000, devise: "FCFA", etat: "payee", remarque: "", note: "",
    cree_le: quand(9, 30), revendeur: false, client_nom: "Awa", client_tel: "0197000011", client_indicatif: "229",
    client_adresse: "Cotonou", acompte: 7000, taux_acompte: 100, verse: 7000, restes: { reste: 0, boutiques: {} },
    frais_livraison: 0, commande_lignes: [ligne("bou_a", "en_livraison"), ligne("bou_b", "en_livraison")],
    heures_etapes: {
      bou_a: { nouvelle: quand(9, 36), vue: quand(9, 38), preparee: quand(9, 42), en_livraison: quand(9, 58) },
      bou_b: { nouvelle: quand(9, 36), vue: quand(9, 40), preparee: quand(9, 50), en_livraison: quand(10, 5) },
    } };
  const { page, ctx, erreurs } = await ouvrir({ hash: "#/mes-commandes", session: true,
    base: (select, d) => d(/heures_etapes/.test(select) ? [cmd] : [{ ...cmd, heures_etapes: undefined }]) });
  await page.waitForTimeout(1800);
  const b = await page.evaluate(() => [...document.querySelectorAll(".re-barre-mots span")].map((s) => ({
    mot: s.childNodes[0] ? s.childNodes[0].textContent : "",
    heure: (s.querySelector(".re-barre-heure") || {}).textContent || "" })));
  ok(b.length === 4, "la barre de la commande, quatre paliers (" + b.map((x) => x.mot).join(" ") + ")");
  ok(b[0] && b[0].heure === "09:36" && b[1].heure === "09:50" && b[2].heure === "10:05",
    "payé 09:36, préparé 09:50, en route 10:05 — l'heure de la dernière boutique (" +
    b.map((x) => x.heure || "—").join(" ") + ")");
  ok(b[3] && b[3].heure === "", "rien sous « Livré », pas encore franchi");
  /* (4.3.0) Le défaut trouvé en chemin : une règle faite pour barrer la
     ligne du reste, une fois la commande soldée, portait le même nom que
     cette barre — ses mots sortaient tous barrés et pâlis. */
  const barre = await page.evaluate(() => [...document.querySelectorAll(".re-barre-mots span")].map((x) => {
    const st = getComputedStyle(x);
    return st.textDecorationLine + "/" + st.opacity;
  }));
  ok(barre.length === 4 && barre.every((x) => !/line-through/.test(x) && /\/1$/.test(x)),
    "(4.3.0) les mots de la barre ne sont plus barrés ni pâlis (" + barre.join(", ") + ")");
  if (process.env.CAPTURES) await page.screenshot({ path: process.env.CAPTURES + "/mes-commandes-heures.png" });
  ok(!erreurs.length, "sans erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  /* La base ne connaît pas encore la colonne : elle refuse la lecture ;
     l'application relit sans elle, et les commandes s'affichent. */
  const { page, ctx, note } = await ouvrir({ hash: "#/mes-commandes", session: true,
    base: (select, d) => /heures_etapes/.test(select)
      ? d({ code: "PGRST200", message: "Could not find a relationship or column heures_etapes" }, 400)
      : d([]) });
  await page.waitForTimeout(1500);
  ok(note.lectures.some((s) => /heures_etapes/.test(s)) && note.lectures.some((s) => !/heures_etapes/.test(s)),
    "refusée, la colonne est abandonnée et la lecture refaite sans elle");
  await ctx.close();
}

await nav.close();
console.log("\n" + (echecs ? "  " + echecs + " ÉCHEC(S)" : "  Tout passe."));
process.exit(echecs ? 1 : 0);
