/* =========================================================
   Les frais de livraison : 1 000 FCFA par commande, hors code promo
   =========================================================
   La base les fige et les compte (supabase/tests/99z-frais-livraison.sql).
   Ce banc regarde les ÉCRANS :

     1. LE PANIER : sous-total, « Frais de livraison », total frais
        compris, et l'acompte pris sur ce total ;
     2. LE FORMULAIRE : la ligne des frais ; un code promo retire sa
        remise des articles, pas des frais ; le bouton suit ;
     3. LA COMMANDE demande les frais à la base (« avec_frais ») ; le
        reçu les dit ;
     4. UNE BASE D'AVANT (sans la colonne) : « À convenir », comme avant ;
     5. LE SUPERADMINISTRATEUR règle les frais ; la boutique les voit
        sur la commande.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-frais-livraison.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
/* Les montants comme les écrans les écrivent : « 30 000 FCFA ». */
const F = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ") + " FCFA";
const texte = (page, sel) => page.evaluate((s) => {
  const el = document.querySelector(s);
  return el ? el.textContent.replace(/\s+/g, " ").trim() : "";
}, sel);

/* ================================================================
   L'application des clients
   ================================================================ */
const BOUTIQUES = [
  { id: "bou_a", nom: "Alpha", categorie_id: "cat_hightech", icone: "magasin", couleur: "#0047D9",
    devise: "FCFA", indicatif: "229", whatsapp: "97000001", actif: true, ordre: 1 },
  { id: "bou_b", nom: "Bêta", categorie_id: "cat_hightech", icone: "magasin", couleur: "#0047D9",
    devise: "FCFA", indicatif: "229", whatsapp: "97000002", actif: true, ordre: 2 },
];
const PRODUIT = { id: "prod_1", boutique_id: "bou_a", nom: "Ordinateur", code: "0001", prix: 300000,
  categorie_id: "cat_hightech", sous_categorie_id: "sc_x", stock: 5, disponible: true, images: [],
  cree_le: "2026-09-01T08:00:00Z", modifie_le: "2026-09-01T08:00:00Z" };
const CLIENT = { nom: "Koffi", tel: "0197000000", indicatif: "229", adresse: "Cotonou" };

/** Ce que la base répondrait à « creer_commande », selon ce qu'on lui demande. */
function reponseCommande(corps, taux, frais) {
  const f = corps.avec_frais ? frais : 0;
  const total = 300000 - (corps.code ? 30000 : 0) + f;
  const t = corps.avec_acompte ? taux : 100;
  const acompte = Math.min(total, Math.max(Math.ceil(total * t / 100), 100));
  return { id: "cmd_x", numero: "BZ-000042", total, devise: "FCFA", etat: "a_payer",
    code_promo: corps.code || "", remise: corps.code ? 30000 : 0,
    taux_acompte: t, acompte, reste: total - acompte, frais_livraison: f,
    boutiques: [{ id: "bou_a", nom: "Alpha", whatsapp: "97000001", indicatif: "229",
      montant: 300000, a_encaisser: total - acompte,
      lignes: [{ nom: "Ordinateur", code: "0001", prix: 300000, quantite: 1 }] }] };
}

/**
 * L'application, sa base, notre fonction « feexpay » et la fenêtre de
 * KkiaPay, simulées. « serveur » garde ce qui est parti, et se règle en
 * cours d'essai.
 */
async function ouvrirClient({ hash = "#/panier", panier = [{ produitId: "prod_1", quantite: 1 }],
                              commandes = [], fournisseur = "feexpay", taux = 10,
                              baseAncienne = false, largeur = 390, frais = 1000 } = {}) {
  const ctx = await nav.newContext({ viewport: { width: largeur, height: 900 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    try {
      localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
      localStorage.setItem("bizzoo-commandes", JSON.stringify(a.commandes));
      if (a.panier) localStorage.setItem("bizzoo-panier", JSON.stringify(a.panier));
      localStorage.setItem("bizzoo-coordonnees", JSON.stringify(a.client));
    } catch (_) { /* une page hors de l'application */ }
  }, { commandes, panier, client: CLIENT });
  const serveur = { creations: [], feexpay: [], etat: { etat: "a_payer", remarque: "" } };

  /* La fenêtre de KkiaPay : elle note le montant demandé, puis répond
     « réussi » — un indice, comme la vraie. */
  await page.route("https://cdn.kkiapay.me/**", (route) => route.fulfill({
    status: 200, contentType: "application/javascript",
    body: "window.addSuccessListener = (f) => { window.__succes = f; };" +
          "window.addFailedListener = () => {};" +
          "window.openKkiapayWidget = (o) => { window.__kkiapay = o;" +
          "  setTimeout(() => window.__succes && window.__succes({ transactionId: 'TRX-K1' }), 60); };" }));
  await page.route("**/functions/v1/feexpay", (route) => {
    const corps = JSON.parse(route.request().postData() || "{}");
    serveur.feexpay.push(corps);
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (corps.action === "payer") return d({ ouvert: true, reference: "ref_1" });
    return d({ etat: "a_payer", attente: true, statut: "PENDING" });
  });
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x, statut = 200) => route.fulfill({ status: statut, contentType: "application/json",
      body: JSON.stringify(x) });
    if (c.startsWith("rpc/creer_commande")) {
      const corps = JSON.parse(req.postData() || "{}");
      serveur.creations.push(corps);
      /* Une base d'avant l'acompte ne connaît pas ce paramètre. */
      if (baseAncienne && "avec_acompte" in corps) {
        return d({ code: "PGRST202", message: "Could not find the function " +
          "public.creer_commande(articles, avec_acompte, client, code) in the schema cache" }, 404);
      }
      const r = reponseCommande(corps, taux, frais);
      if (baseAncienne) { delete r.acompte; delete r.taux_acompte; delete r.reste;
                          delete r.boutiques[0].a_encaisser; }
      return d(r);
    }
    if (c.startsWith("rpc/verifier_code")) return d({ ok: true, remise: 30000, raison: "" });
    if (c.startsWith("rpc/suivre_commande")) return d(serveur.etat);
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("reglages")) return d([{ compte_obligatoire: false }]);
    if (c.startsWith("paiement")) {
      const ligne = { id: 1, actif: true, fournisseur, cle_publique: fournisseur === "kkiapay" ? "pk_x" : "",
        bac_a_sable: false };
      if (!baseAncienne) ligne.taux_acompte = taux;
      /* « frais: null » : une base d'avant les frais, sans la colonne. */
      if (frais != null) ligne.frais_livraison = frais;
      return d([ligne]);
    }
    if (c.startsWith("produits")) return d([PRODUIT]);
    if (c.startsWith("boutiques")) return d(BOUTIQUES);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/client/index.html" + hash, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1800);
  return { page, ctx, erreurs, serveur };
}

const lignesTotal = (page) => page.evaluate(() =>
  [...document.querySelectorAll("#co-lignes-total .pa-total-ligne")]
    .map((l) => l.textContent.replace(/\s+/g, " ").trim()));


/* ------------------------------------------------------------------ */
titre("1. Le panier : les frais, le total, l'acompte");
{
  const { page, ctx, erreurs } = await ouvrirClient({ hash: "#/panier" });
  const recap = await page.evaluate(() => [...document.querySelectorAll(".pa-recap .pa-recap-ligne")]
    .map((l) => l.textContent.replace(/\s+/g, " ").trim()));
  ok(recap.includes("Frais de livraison" + F(1000)), "« Frais de livraison : 1 000 FCFA » (" + recap[1] + ")");
  ok(recap.includes("Total" + F(301000)), "le total compte les frais : 301 000 FCFA");
  ok(recap.some((l) => l.startsWith("À payer à la commande") && l.endsWith(F(30100))),
    "l'acompte de 10 % se prend sur 301 000 : 30 100 FCFA");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("2. Le formulaire : le code promo ne touche pas les frais");
{
  const { page, ctx, erreurs } = await ouvrirClient({ hash: "#/commande", taux: 100 });
  let lignes = await lignesTotal(page);
  ok(lignes.includes("Sous-total" + F(300000)) && lignes.includes("Frais de livraison" + F(1000)),
    "sous-total et frais de livraison (" + lignes.join(" | ") + ")");
  ok(lignes.includes("Total à régler" + F(301000)), "total à régler : 301 000 FCFA");
  ok(await texte(page, "#co-payer") === "Payer " + F(301000), "le bouton demande 301 000 FCFA");
  await page.fill("#co-code", "BIENVENUE10");
  await page.click("#co-code-appliquer");
  await page.waitForTimeout(500);
  lignes = await lignesTotal(page);
  ok(lignes.includes("Code BIENVENUE10− " + F(30000)) && lignes.includes("Frais de livraison" + F(1000)),
    "le code retire 30 000 des articles, les frais restent 1 000 (" + lignes.join(" | ") + ")");
  ok(lignes.includes("Total à régler" + F(271000)), "300 000 − 30 000 + 1 000 = 271 000 FCFA");
  ok(await texte(page, "#co-payer") === "Payer " + F(271000), "et le bouton suit");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("3. La commande demande les frais ; le reçu les dit");
{
  const { page, ctx, serveur, erreurs } = await ouvrirClient({ hash: "#/commande" });
  await page.click('#co-operateurs [data-reseau="MTN"]');
  await page.click("#co-payer");
  await page.waitForFunction(() => location.hash === "#/commande/cmd_x", null, { timeout: 8000 })
    .catch(() => {});
  await page.waitForTimeout(800);
  const corps = serveur.creations[0] || {};
  ok(corps.avec_frais === true && corps.avec_acompte === true,
    "« creer_commande » part avec « avec_frais » (" + JSON.stringify(corps.avec_frais) + ")");
  ok(/dont 1 000 FCFA de frais de livraison/.test(await texte(page, ".re-entete")),
    "le reçu : « dont 1 000 FCFA de frais de livraison »");
  const gardee = await page.evaluate(() => JSON.parse(localStorage.getItem("bizzoo-commandes") || "[]")[0] || {});
  ok(gardee.frais_livraison === 1000, "le téléphone garde les frais fixés par la base");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("4. Une base d'avant les frais : comme avant");
{
  const { page, ctx } = await ouvrirClient({ hash: "#/panier", frais: null });
  const recap = await page.evaluate(() => [...document.querySelectorAll(".pa-recap .pa-recap-ligne")]
    .map((l) => l.textContent.replace(/\s+/g, " ").trim()));
  ok(recap.includes("LivraisonÀ convenir avec la boutique") && recap.includes("Total" + F(300000)),
    "« Livraison : à convenir », total 300 000 (" + recap.join(" | ") + ")");
  await ctx.close();
}

/* ================================================================
   L'application admin
   ================================================================ */
const SUPER = "11111111-1111-1111-1111-111111111111";
const CHEF = "22222222-2222-2222-2222-222222222222";
const PORTEUR = "cccccccc-1111-1111-1111-111111111111";
const PROFILS = {
  [SUPER]: { id: SUPER, email: "chef@bizzoo.bj", role: "superadministrateur", actif: true,
    peut_modifier_produits: true, boutique_id: null },
  [CHEF]: { id: CHEF, email: "chef@alpha.bj", role: "administrateur", actif: true,
    peut_modifier_produits: true, boutique_id: "bou_a" },
  [PORTEUR]: { id: PORTEUR, email: "porteur@alpha.bj", nom: "Rohim", role: "livreur", actif: true,
    peut_modifier_produits: true, boutique_id: "bou_a" },
};
const COMMANDE_ADMIN = { id: "cmd_x", numero: "BZ-000042", client_nom: "Koffi", client_tel: "0197000000",
  client_indicatif: "229", client_adresse: "Cotonou", note: "", total: 300000, devise: "FCFA",
  etat: "payee", transaction_id: "t1", fournisseur_ref: "ref_1", confirme_par: "", remarque: "",
  transaction_annoncee: "", revendeur: false, paye_le: "2026-10-09T09:02:00Z",
  cree_le: "2026-10-09T09:00:00Z", taux_acompte: 10, acompte: 30000, verse: 30000,
  restes: { reste: 270000, boutiques: { bou_a: 270000 } },
  commande_lignes: [{ id: "lig_1", commande_id: "cmd_x", boutique_id: "bou_a", produit_id: "prod_1",
    nom: "Ordinateur", code: "0001", reference: "", prix: 300000, quantite: 1, etat: "preparee",
    confirme_le: null }] };

async function ouvrirAdmin({ moi, hash, paiement = null, restesConnus = true, courses = [] }) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1400 }, serviceWorkers: "block" });
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
  }, { moi, email: PROFILS[moi].email });
  const serveur = { ecritures: [], lectures: [] };
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x, statut = 200) => route.fulfill({ status: statut, contentType: "application/json",
      body: JSON.stringify(x) });
    if (req.method() !== "GET" && !c.startsWith("rpc/")) {
      serveur.ecritures.push({ methode: req.method(), chemin: c,
        corps: (() => { try { return req.postDataJSON(); } catch (_) { return null; } })() });
      return route.fulfill({ status: 204, body: "" });
    }
    serveur.lectures.push(c + u.search);
    if (c.startsWith("profils")) {
      const id = (u.searchParams.get("id") || "").replace(/^eq\./, "");
      return d(id ? [PROFILS[id]].filter(Boolean) : Object.values(PROFILS));
    }
    if (c === "rpc/mes_livraisons") return d(courses);
    if (c === "rpc/livreurs_boutique") return d([{ id: PORTEUR, email: "porteur@alpha.bj", nom: "Rohim",
      tel: "0197000011", actif: true, bizzoo: false }]);
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("commandes")) {
      const select = u.searchParams.get("select") || "";
      if (/restes/.test(select) && !restesConnus) {
        return d({ code: "42703", message: "column commandes.restes does not exist" }, 400);
      }
      if (/commande_lignes\(etat\)/.test(select)) return d([]);
      const ligne = { ...COMMANDE_ADMIN };
      if (!restesConnus) delete ligne.restes;
      return d([ligne]);
    }
    if (c.startsWith("paiement")) return d(paiement ? [paiement] : []);
    if (c.startsWith("boutiques")) return d(BOUTIQUES);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1800);
  if (hash) {
    await page.evaluate((h) => { location.hash = h; }, hash);
    await page.waitForTimeout(1600);
  }
  /* Les réglages de l'enseigne — dont le paiement — sont sous l'onglet
     « BIZZOO » de l'écran Réglages. */
  if (hash === "#/reglages" && await page.$('[data-cible="enseigne"]')) {
    await page.click('[data-cible="enseigne"]');
    await page.waitForTimeout(1200);
  }
  return { page, ctx, erreurs, serveur };
}


/* ------------------------------------------------------------------ */
titre("5. Le superadministrateur règle les frais ; la boutique les voit");
{
  const paiement = { id: 1, actif: true, fournisseur: "feexpay", cle_publique: "", bac_a_sable: false,
    taux_acompte: 10, frais_livraison: 1000 };
  const { page, ctx, serveur, erreurs } = await ouvrirAdmin({ moi: SUPER, hash: "#/reglages", paiement });
  await page.waitForSelector("#pay-frais", { timeout: 6000 }).catch(() => {});
  await page.waitForTimeout(600);
  const vu = await page.evaluate(() => ({
    visible: !!document.querySelector("#pay-bloc-frais") && !document.querySelector("#pay-bloc-frais").hidden,
    valeur: (document.querySelector("#pay-frais") || {}).value }));
  ok(vu.visible && vu.valeur === "1000", "« Frais de livraison » montre 1 000 (" + vu.valeur + ")");
  await page.fill("#pay-frais", "abc");
  await page.click("#pay-enregistrer");
  await page.waitForTimeout(500);
  ok(!serveur.ecritures.some((e) => e.chemin.startsWith("paiement")), "une saisie invalide : rien ne part");
  await page.fill("#pay-frais", "1 500");
  await page.click("#pay-enregistrer");
  await page.waitForTimeout(800);
  const envoi = serveur.ecritures.find((e) => e.chemin.startsWith("paiement"));
  ok(!!envoi && envoi.corps && envoi.corps.frais_livraison === 1500,
    "1 500 part vers la base (" + JSON.stringify(envoi && envoi.corps && envoi.corps.frais_livraison) + ")");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  COMMANDE_ADMIN.frais_livraison = 1000;
  COMMANDE_ADMIN.total = 301000;
  const { page, ctx } = await ouvrirAdmin({ moi: CHEF, hash: "#/commandes" });
  await page.waitForTimeout(600);
  ok(/dont 1 000 FCFA de livraison/.test(await page.evaluate(() => document.body.innerText)),
    "la carte de la commande : « dont 1 000 FCFA de livraison »");
  await ctx.close();
}

await nav.close();
console.log(echecs
  ? "\n\x1b[31m" + echecs + " constat(s) en échec ✘\x1b[0m"
  : "\n\x1b[32mLes frais de livraison s'ajoutent au total, et aucun code ne les touche ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
