/* =========================================================
   L'acompte à la commande, de l'écran du client à la porte
   =========================================================
   LA DEMANDE. Le client paie en ligne une part du total — 10 % par
   défaut, réglé par le superadministrateur — pour que sa commande
   parte ; le reste se paie à la livraison. Cela écarte les commandes
   fictives.

   La base calcule, fige et partage tout (supabase/acompte.sql, éprouvé
   par supabase/tests/99t-acompte.sql). Ce banc regarde ce que les
   ÉCRANS en font, et ce qui PART vers la base :

     1. LE PANIER ANNONCE l'acompte et le reste avant de commander ;
     2. LE FORMULAIRE dit ce qui se paie maintenant, et le bouton
        demande l'acompte — code promo compris ;
     3. LA COMMANDE DEMANDE L'ACOMPTE À LA BASE (« avec_acompte »), et
        FeexPay comme KkiaPay ne demandent QUE ce que la base a fixé ;
     4. LE REÇU dit l'acompte, puis « Acompte reçu » et le reste — et
        le suit quand la base confirme ;
     5. PLUSIEURS BOUTIQUES : chacune sa part, jusque dans son message ;
     6. « MES COMMANDES » dit « Acompte payé » et le reste ;
     7. SANS ACOMPTE (100 %, ou une base d'avant), tout est comme avant
        — et une base d'avant qui ne connaît pas le paramètre ne bloque
        pas la commande ;
     8. LE SUPERADMINISTRATEUR RÈGLE LE TAUX, de 1 à 100 ;
     9. LA BOUTIQUE VOIT l'acompte payé et ce qu'elle encaissera, et la
        feuille « Confier » le dit ;
    10. LE LIVREUR VOIT ce qu'il encaisse — et rien d'autre ;
    11. TOUT TIENT SUR UN PETIT TÉLÉPHONE (320 px).

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-acompte.mjs
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-acompte.mjs");
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
function reponseCommande(corps, taux) {
  const total = 300000 - (corps.code ? 30000 : 0);
  const t = corps.avec_acompte ? taux : 100;
  const acompte = Math.min(total, Math.max(Math.ceil(total * t / 100), 100));
  return { id: "cmd_x", numero: "BZ-000042", total, devise: "FCFA", etat: "a_payer",
    code_promo: corps.code || "", remise: corps.code ? 30000 : 0,
    taux_acompte: t, acompte, reste: total - acompte,
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
                              baseAncienne = false, largeur = 390 } = {}) {
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
      const r = reponseCommande(corps, taux);
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
titre("1. Le panier annonce l'acompte et le reste");
{
  const { page, ctx, erreurs } = await ouvrirClient({ hash: "#/panier" });
  const recap = await page.evaluate(() => [...document.querySelectorAll(".pa-recap .pa-recap-ligne")]
    .map((l) => l.textContent.replace(/\s+/g, " ").trim()));
  ok(recap.some((l) => l.startsWith("À payer à la commande") && l.includes("acompte de 10 %") &&
                       l.endsWith(F(30000))),
    "« À payer à la commande — acompte de 10 % : 30 000 FCFA » (" + (recap[3] || "—") + ")");
  ok(recap.some((l) => l === "À payer à la livraison" + F(270000)),
    "« À payer à la livraison : 270 000 FCFA »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("2. Le formulaire dit ce qui se paie maintenant");
{
  const { page, ctx, erreurs } = await ouvrirClient({ hash: "#/commande" });
  const lignes = await lignesTotal(page);
  ok(lignes[0] === "Total de la commande" + F(300000), "le total de la commande (" + lignes[0] + ")");
  ok(lignes[1] === "À payer maintenant acompte de 10 %" + F(30000),
    "« À payer maintenant — acompte de 10 % : 30 000 FCFA » (" + lignes[1] + ")");
  ok(lignes[2] === "Reste à payer à la livraison" + F(270000), "le reste à la livraison (" + lignes[2] + ")");
  const bouton = await texte(page, "#co-payer");
  ok(bouton === "Payer l'acompte · " + F(30000), "le bouton demande l'acompte (« " + bouton + " »)");
  const aide = await texte(page, ".pa-total .aide");
  ok(/ne payez maintenant que l'acompte/.test(aide), "et l'aide le dit avant de payer");

  /* Un code promo : l'acompte se prend sur le total remise déduite. */
  await page.fill("#co-code", "BIENVENUE10");
  await page.click("#co-code-appliquer");
  await page.waitForTimeout(500);
  const avecCode = await lignesTotal(page);
  ok(avecCode.includes("Total de la commande" + F(270000)), "avec le code : total 270 000 FCFA");
  ok(avecCode.includes("À payer maintenant acompte de 10 %" + F(27000)),
    "l'acompte suit : 27 000 FCFA (" + (avecCode.find((l) => l.startsWith("À payer")) || "—") + ")");
  ok(await texte(page, "#co-payer") === "Payer l'acompte · " + F(27000), "et le bouton aussi");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("3. La commande demande l'acompte, et FeexPay ne demande que lui");
let recuFeexpay;
{
  recuFeexpay = await ouvrirClient({ hash: "#/commande" });
  const { page, serveur } = recuFeexpay;
  await page.click('#co-operateurs [data-reseau="MTN"]');
  await page.click("#co-payer");
  await page.waitForFunction(() => location.hash === "#/commande/cmd_x", null, { timeout: 8000 })
    .catch(() => {});
  await page.waitForTimeout(800);
  const corps = serveur.creations[0] || {};
  ok(corps.avec_acompte === true, "« creer_commande » part avec « avec_acompte » (" +
    JSON.stringify(corps.avec_acompte) + ")");
  const payer = serveur.feexpay.find((a) => a.action === "payer");
  ok(!!payer && !("montant" in payer) && !("amount" in payer),
    "la demande FeexPay ne porte AUCUN montant : c'est la base qui le donne");
  const gardee = await page.evaluate(() => JSON.parse(localStorage.getItem("bizzoo-commandes") || "[]")[0] || {});
  ok(gardee.acompte === 30000 && gardee.reste === 270000,
    "le téléphone garde l'acompte et le reste fixés par la base (" + gardee.acompte + " / " + gardee.reste + ")");
  const entete = await page.evaluate(() => [...document.querySelectorAll(".re-acompte-ligne")]
    .map((l) => l.textContent.replace(/\s+/g, " ").trim()));
  ok(entete[0] === "Acompte à payer 10 %" + F(30000), "le reçu : « Acompte à payer » (" + entete[0] + ")");
  ok(entete[1] === "Reste à payer à la livraison" + F(270000), "et le reste (" + entete[1] + ")");
}

/* ------------------------------------------------------------------ */
titre("4. La base confirme : « Acompte reçu », et le reste");
{
  const { page, ctx, serveur, erreurs } = recuFeexpay;
  serveur.etat = { numero: "BZ-000042", etat: "payee", total: 300000, devise: "FCFA", remarque: "",
    taux_acompte: 10, acompte: 30000, verse: 30000, reste: 270000, restes: { bou_a: 270000 } };
  const confirme = await page.waitForFunction(() => /Commande confirmée/.test(document.body.innerText),
    null, { timeout: 12000 }).then(() => true, () => false);
  ok(confirme, "« Commande confirmée ! » dès que la base le dit");
  const badge = await texte(page, ".re-entete .badge");
  ok(badge === "Acompte payé", "le badge dit « Acompte payé », pas « Payée » (" + badge + ")");
  ok(/Acompte reçu\./.test(await texte(page, ".pa-confirme")), "« Acompte reçu. »");
  ok(/Le reste se paie à la livraison/.test(await texte(page, ".pa-confirme")),
    "« Le reste se paie à la livraison »");
  ok((await texte(page, ".re-heros")).includes("Le reste, " + F(270000) + ", se paie à la livraison"),
    "la coche dit le reste : 270 000 FCFA");
  const payeLigne = await page.evaluate(() =>
    (document.querySelector(".re-acompte-ligne") || {}).textContent.replace(/\s+/g, " ").trim());
  ok(payeLigne === "Acompte payé 10 %" + F(30000), "« Acompte payé : 30 000 FCFA » (" + payeLigne + ")");
  const lien = await page.evaluate(() => {
    const a = document.querySelector(".btn-wa");
    return a ? decodeURIComponent(a.getAttribute("href")) : "";
  });
  ok(lien.includes("Acompte payé en ligne. Reste à payer à la livraison : " + F(270000)),
    "le message WhatsApp à la boutique dit ce qu'elle encaissera");
  const gardee = await page.evaluate(() => JSON.parse(localStorage.getItem("bizzoo-commandes") || "[]")[0] || {});
  ok(gardee.verse === 30000 && gardee.reste === 270000, "le téléphone note le versé et le reste");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("5. KkiaPay ne demande que l'acompte");
{
  const { page, ctx, serveur, erreurs } = await ouvrirClient({ hash: "#/commande", fournisseur: "kkiapay" });
  await page.click("#co-payer");
  await page.waitForFunction(() => location.hash === "#/commande/cmd_x", null, { timeout: 8000 })
    .catch(() => {});
  const montant = await page.evaluate(() => (window.__kkiapay || {}).amount);
  ok(serveur.creations[0] && serveur.creations[0].avec_acompte === true, "la commande demande l'acompte");
  ok(montant === 30000, "la fenêtre KkiaPay demande 30 000, pas 300 000 (" + montant + ")");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("6. Plusieurs boutiques : chacune sa part");
{
  const commande = { id: "cmd_y", numero: "BZ-000043", total: 400000, devise: "FCFA", etat: "payee",
    acompte: 40000, taux_acompte: 10, verse: 40000, reste: 360000, client: CLIENT,
    boutiques: [
      { id: "bou_a", nom: "Alpha", whatsapp: "97000001", indicatif: "229", montant: 300000,
        a_encaisser: 270000, lignes: [{ nom: "Ordinateur", prix: 300000, quantite: 1 }] },
      { id: "bou_b", nom: "Bêta", whatsapp: "97000002", indicatif: "229", montant: 100000,
        a_encaisser: 90000, lignes: [{ nom: "Écran", prix: 100000, quantite: 1 }] }] };
  const { page, ctx, erreurs } = await ouvrirClient({ hash: "#/commande/cmd_y", commandes: [commande],
    panier: null });
  const parts = await page.evaluate(() => [...document.querySelectorAll(".re-a-livrer")]
    .map((l) => l.textContent.replace(/\s+/g, " ").trim()));
  ok(parts.length === 2 && parts[0] === "À payer à sa livraison" + F(270000) &&
     parts[1] === "À payer à sa livraison" + F(90000),
    "chaque boutique dit ce qu'on lui donnera (" + parts.join(" | ") + ")");
  const messages = await page.evaluate(() => [...document.querySelectorAll(".btn-wa")]
    .map((a) => decodeURIComponent(a.getAttribute("href"))));
  ok(messages.length === 2 && messages[0].includes(F(270000)) && !messages[0].includes(F(90000)) &&
     messages[1].includes(F(90000)),
    "et chaque message WhatsApp ne porte que la part de sa boutique");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("7. « Mes commandes » dit l'acompte et le reste");
{
  const payee = { id: "cmd_x", numero: "BZ-000042", total: 300000, devise: "FCFA", etat: "payee",
    acompte: 30000, verse: 30000, reste: 270000, client: CLIENT, gardeeLe: Date.now(),
    boutiques: [{ id: "bou_a", nom: "Alpha", montant: 300000, a_encaisser: 270000, lignes: [] }] };
  const { page, ctx, erreurs } = await ouvrirClient({ hash: "#/mes-commandes", commandes: [payee],
    panier: null });
  const carte = await texte(page, ".re-resume");
  ok(/Acompte payé/.test(carte), "le badge : « Acompte payé »");
  ok(carte.includes("reste " + F(270000) + " à la livraison"), "et « reste 270 000 FCFA à la livraison »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("8. Sans acompte, tout est comme avant");
{
  const { page, ctx } = await ouvrirClient({ hash: "#/commande", taux: 100 });
  const lignes = await lignesTotal(page);
  ok(lignes.length === 1 && lignes[0] === "Total à régler" + F(300000),
    "à 100 % : « Total à régler », seul (" + lignes.join(" | ") + ")");
  ok(await texte(page, "#co-payer") === "Payer " + F(300000), "et « Payer 300 000 FCFA »");
  await ctx.close();
}
{
  /* Une base d'avant : la colonne manque, « creer_commande » ne connaît
     pas le paramètre. La commande passe quand même, en entier. */
  const { page, ctx, serveur, erreurs } = await ouvrirClient({ hash: "#/commande", fournisseur: "kkiapay",
    baseAncienne: true });
  ok(await texte(page, "#co-payer") === "Payer " + F(300000), "base d'avant : le bouton demande le total");
  await page.click("#co-payer");
  await page.waitForFunction(() => location.hash === "#/commande/cmd_x", null, { timeout: 8000 })
    .catch(() => {});
  ok(serveur.creations.length === 2 && "avec_acompte" in serveur.creations[0] &&
     !("avec_acompte" in serveur.creations[1]),
    "le paramètre inconnu est retiré, et la commande repart sans lui (" + serveur.creations.length + " appels)");
  const montant = await page.evaluate(() => (window.__kkiapay || {}).amount);
  ok(montant === 300000, "KkiaPay demande le total, comme la base le veut (" + montant + ")");
  ok(!(await page.$(".re-acompte")), "et le reçu ne parle d'aucun acompte");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("11. Sur un petit téléphone (320 px)");
{
  const { page, ctx } = await ouvrirClient({ hash: "#/commande", largeur: 320 });
  const m = await page.evaluate(() => {
    const b = document.querySelector("#co-payer");
    return { page: document.documentElement.scrollWidth, bouton: b ? b.scrollWidth <= b.clientWidth + 1 : false,
      lignes: [...document.querySelectorAll("#co-lignes-total .pa-total-ligne")]
        .every((l) => l.scrollWidth <= l.clientWidth + 1) };
  });
  ok(m.page <= 320, "rien ne déborde de l'écran (" + m.page + " px)");
  ok(m.bouton, "« Payer l'acompte · 30 000 FCFA » tient dans son bouton");
  ok(m.lignes, "et les lignes du total tiennent dans la carte");
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
titre("8 bis. Le superadministrateur règle le taux, de 1 à 100");
{
  const paiement = { id: 1, actif: true, fournisseur: "feexpay", cle_publique: "", bac_a_sable: false,
    taux_acompte: 10 };
  const { page, ctx, serveur, erreurs } = await ouvrirAdmin({ moi: SUPER, hash: "#/reglages", paiement });
  await page.waitForSelector("#pay-acompte", { timeout: 6000 }).catch(() => {});
  await page.waitForTimeout(600);
  const vu = await page.evaluate(() => ({
    visible: !!document.querySelector("#pay-bloc-acompte") && !document.querySelector("#pay-bloc-acompte").hidden,
    valeur: (document.querySelector("#pay-acompte") || {}).value }));
  ok(vu.visible && vu.valeur === "10", "« Acompte à la commande » montre 10 % (" + vu.valeur + ")");

  await page.fill("#pay-acompte", "0");
  await page.click("#pay-enregistrer");
  await page.waitForTimeout(600);
  ok(!serveur.ecritures.some((e) => e.chemin.startsWith("paiement")), "0 % est refusé : rien ne part");
  ok(/entre 1 et 100/.test(await page.evaluate(() => document.body.innerText)), "et l'écran dit pourquoi");

  await page.fill("#pay-acompte", "15");
  await page.click("#pay-enregistrer");
  await page.waitForTimeout(800);
  const envoi = serveur.ecritures.find((e) => e.chemin.startsWith("paiement"));
  ok(!!envoi && envoi.corps && envoi.corps.taux_acompte === 15,
    "15 % part vers la base (" + JSON.stringify(envoi && envoi.corps && envoi.corps.taux_acompte) + ")");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  /* Une base d'avant : pas de colonne, pas de champ, et rien d'inconnu
     n'est envoyé. */
  const paiement = { id: 1, actif: true, fournisseur: "feexpay", cle_publique: "", bac_a_sable: false };
  const { page, ctx, serveur } = await ouvrirAdmin({ moi: SUPER, hash: "#/reglages", paiement });
  await page.waitForTimeout(800);
  ok(await page.evaluate(() => document.querySelector("#pay-bloc-acompte").hidden),
    "base d'avant : le champ n'apparaît pas");
  await page.click("#pay-enregistrer");
  await page.waitForTimeout(800);
  const envoi = serveur.ecritures.find((e) => e.chemin.startsWith("paiement"));
  ok(!!envoi && !("taux_acompte" in (envoi.corps || {})), "et l'enregistrement n'envoie pas de taux");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("9. La boutique voit l'acompte payé et ce qu'elle encaissera");
{
  const { page, ctx, serveur, erreurs } = await ouvrirAdmin({ moi: CHEF, hash: "#/commandes" });
  ok(serveur.lectures.some((l) => /^commandes\?select=\*,restes/.test(l)),
    "la liste demande « restes » à la base");
  const bloc = await texte(page, ".cmd-acompte");
  ok(bloc.includes("Acompte payé en ligne (10 %)"), "« Acompte payé en ligne (10 %) »");
  ok(bloc.includes("À encaisser à la livraison : " + F(270000)), "« À encaisser à la livraison : 270 000 FCFA »");
  const wa = await page.evaluate(() => decodeURIComponent((document.querySelector(".cmd-wa") || {}).href || ""));
  ok(wa.includes("À payer à la livraison : " + F(270000)), "le message au client dit ce qu'il donnera à la porte");

  await page.click("[data-confier]");
  await page.waitForTimeout(900);
  const feuille = await page.evaluate(() => document.body.innerText);
  ok(feuille.includes("ce qu'il doit encaisser à la livraison : " + F(270000)),
    "« Confier » dit au livreur ce qu'il encaissera");
  ok(!/Aucun montant/.test(feuille), "et ne dit plus « Aucun montant »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  const { page, ctx, erreurs } = await ouvrirAdmin({ moi: CHEF, hash: "#/commandes", restesConnus: false });
  ok(!!(await page.$(".cmd-carte")), "base d'avant : la liste s'affiche quand même, sans « restes »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("10. Le livreur voit ce qu'il encaisse, et rien d'autre");
{
  const course = (o) => ({ commande_id: "cmd_x", numero: "BZ-000042", boutique_id: "bou_a",
    nom_boutique: "Alpha", client_nom: "Koffi", client_tel: "0197000000", client_indicatif: "229",
    client_adresse: "Cotonou", note: "", etat: "preparee",
    articles: [{ nom: "Ordinateur", code: "0001", quantite: 1 }], paye_le: "2026-10-09T09:02:00Z", ...o });
  const courses = [
    course({ a_encaisser: 270000 }),
    course({ commande_id: "cmd_z", numero: "BZ-000044", etat: "en_livraison", a_encaisser: 0 }),
    course({ commande_id: "cmd_w", numero: "BZ-000040", etat: "remise", a_encaisser: 5000 }),
  ];
  const { page, ctx, erreurs } = await ouvrirAdmin({ moi: PORTEUR, courses });
  await page.waitForSelector(".lv-course", { timeout: 6000 }).catch(() => {});
  const cartes = await page.evaluate(() => [...document.querySelectorAll(".lv-course")].map((c) => ({
    numero: c.querySelector("strong").textContent,
    encaisser: (c.querySelector(".lv-encaisser") || {}).textContent || "",
    texte: c.textContent })));
  const de = (n) => cartes.find((c) => c.numero === n) || { encaisser: "", texte: "" };
  ok(de("BZ-000042").encaisser.replace(/\s+/g, " ").trim() === "À encaisser : " + F(270000),
    "à prendre : « À encaisser : 270 000 FCFA »");
  ok(/Rien à encaisser : tout est payé/.test(de("BZ-000044").encaisser),
    "tout payé en ligne : « Rien à encaisser »");
  ok(de("BZ-000040").encaisser.replace(/\s+/g, " ").trim() === "Encaissé à la livraison : " + F(5000),
    "remise : « Encaissé à la livraison »");
  ok(!cartes.some((c) => c.texte.includes(F(300000))), "le prix de l'ordinateur n'apparaît nulle part");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " ÉCHEC(S)" : "\nTout tient ✔");
process.exit(echecs ? 1 : 0);
