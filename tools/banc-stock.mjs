/* =========================================================
   Le stock suit les ventes — et personne ne vend ce qui n'est plus là
   =========================================================
   CE QUE LA BASE FAIT DÉJÀ, et que prouve supabase/tests/99q :
   une commande payée ôte ses pièces, une annulation les rend, et
   « creer_commande » refuse une quantité qui dépasse le stock.

   CE QUE CE BANC PROUVE, À L'ÉCRAN :

   Côté client
     1. LA FICHE PRODUIT S'ARRÊTE AU STOCK : le « + » ne dépasse pas ce
        qui reste, en comptant ce qui est déjà au panier ; « Plus que N
        en stock » quand il en reste peu ; un produit sur commande n'a
        pas de limite ; un produit en rupture n'a pas de bouton ;
     2. LE PANIER SE RAMÈNE AU STOCK DU MOMENT : une quantité devenue
        trop grande est ramenée, et on le dit ; un article épuisé bloque
        « Passer la commande » jusqu'à ce qu'on le retire ; le « + »
        s'arrête au stock ;
     3. ON N'ARRIVE PAS AU PAIEMENT AVEC UN ARTICLE ÉPUISÉ ;
     4. UN REFUS DE LA BASE — une autre vente est passée entre-temps —
        ramène au panier, catalogue relu, quantité corrigée.

   Côté boutique
     5. L'ÉCRAN STOCK : le plus urgent en tête, les filtres comptés, la
        recherche, le filtre venu d'une notification ;
     6. CHANGER UN CHIFFRE : un appui, un envoi, écrit SUR LE CHIFFRE VU
        (« stock=eq.N ») ;
     7. UNE VENTE PAYÉE PENDANT LA SAISIE n'est pas écrasée — ni avant
        l'envoi, ni pendant : l'écran dit le nouveau chiffre, et le
        prochain appui part de lui ;
     8. LE FORMULAIRE PRODUIT ne renvoie le stock que si on l'a changé :
        retoucher la description ne rend pas les pièces vendues ;
     9. SANS LE DROIT DE MODIFIER, l'écran se lit sans se modifier ;
    10. L'ACCUEIL, LA LISTE DES PRODUITS ET LES NOTIFICATIONS y mènent ;
    11. DÉFAIRE UNE RETOUCHE DU PRODUIT (historique) garde le stock du
        moment ; défaire une action SUR le stock remet l'ancien chiffre.

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-stock.mjs
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-stock.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

const il = (min) => new Date(Date.now() - min * 60000).toISOString();
const dans = (jours) => new Date(Date.now() + jours * 86400000).toISOString().slice(0, 10);
const BOUTIQUE = { id: "bou_info", nom: "Impact Informatique", secteur: "Informatique",
  categorie_id: "cat_ht", icone: "portable", couleur: "#0047D9", devise: "FCFA", indicatif: "229",
  actif: true, ordre: 1, taux_marge: 10, taux_revendeur: 5, revendeur_mode: "bizzoo",
  description: "", adresse: "Cotonou", tel: "0197000000", whatsapp: "0197000000", horaires: "",
  photos: [], telephones: [], adresses: [] };
const CATEGORIES = [{ id: "cat_ht", nom: "High-tech", icone: "portable", couleur: "#0047D9",
  image: "", en_avant: true, ordre: 1, sous_categories: [
    { id: "sc_acc", categorie_id: "cat_ht", nom: "Accessoires", ordre: 1 },
  ] }];

/* Un seul catalogue pour les deux applications : ce que la boutique
   voit, le client le voit aussi. */
let rang = 0;
const produit = (id, nom, stock, extra = {}) => ({
  id, code: String(100100 + (++rang)), nom, reference: "IMP-0" + (500 + rang),
  description: "", prix: 7500, ancien_prix: null,
  categorie_id: "cat_ht", sous_categorie_id: "sc_acc", stock,
  disponible: stock > 0 || !!extra.sur_commande, sur_commande: false, appro_le: null,
  images: [], video: "", boutique_id: "bou_info", en_avant: false, ordre_avant: 0,
  flash_fin: null, cree_le: il(600), modifie_le: il(600 - rang),
  produits_prive: [{ prix_grossiste: 6800, taux_marge: null, taux_revendeur: null }],
  ...extra,
});
const CATALOGUE = () => {
  rang = 0;
  return [
    produit("prod_souris", "Souris sans fil", 2),                                  // bientôt épuisé
    produit("prod_cable", "Câble USB-C", 12),                                      // en stock
    produit("prod_ecran", "Écran 24 pouces", 0),                                   // en rupture
    produit("prod_serveur", "Serveur rack", 0, { sur_commande: true, disponible: true }),
    produit("prod_onduleur", "Onduleur 650 VA", 0, { appro_le: dans(3) }),         // réassort
    produit("prod_clavier", "Clavier Bluetooth", 3),                               // bientôt épuisé
  ];
};

const toast = (page) => page.evaluate(() =>
  [...document.querySelectorAll("#toasts .toast, .toast")].map((t) => t.textContent).join(" | "));
const aller = async (page, hash, attente = 1300) => {
  await page.evaluate((h) => { location.hash = h; }, hash);
  await page.waitForTimeout(attente);
};

/* =====================================================
   Le client
   ===================================================== */

async function ouvrirClient({ panier = null, options = {} } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1400 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((panier) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.removeItem("impact-boutique");
    if (panier) localStorage.setItem("bizzoo-panier", JSON.stringify(panier));
  }, panier);

  const produits = CATALOGUE();
  const commandes = [];
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json",
    body: JSON.stringify({ external: { email: true, phone: false } }) }));
  await page.route("**/rest/v1/**", (r) => {
    const req = r.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x, status = 200) => r.fulfill({ status, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/creer_commande")) {
      commandes.push(JSON.parse(req.postData() || "{}"));
      /* LA VENTE D'À CÔTÉ : elle est payée pendant que ce client remplit
         son formulaire. La base refuse, et le catalogue relu le dira. */
      if (options.venteVoisine) {
        const p = produits.find((x) => x.id === options.venteVoisine.id);
        p.stock = options.venteVoisine.reste;
        p.disponible = p.stock > 0;
        return d({ message: "Plus que " + p.stock + " en stock pour « " + p.nom +
          " » : réduisez la quantité dans votre panier." }, 400);
      }
      return d({ id: "cmd_1", numero: "BZ-000001", total: 7500, devise: "FCFA", etat: "a_payer" });
    }
    if (c.startsWith("rpc/")) return d([]);
    if (c.startsWith("reglages")) return d([{ compte_obligatoire: false }]);
    if (c.startsWith("paiement")) return d([{ id: 1, actif: true, fournisseur: "kkiapay",
      cle_publique: "pk_essai", bac_a_sable: true }]);
    if (c.startsWith("produits")) return d(produits);
    if (c.startsWith("categories")) return d(CATEGORIES);
    if (c.startsWith("boutiques")) return d([BOUTIQUE]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1500);
  return { page, ctx, erreurs, produits, commandes };
}

const lirePanier = (page) => page.evaluate(() => {
  try { return JSON.parse(localStorage.getItem("bizzoo-panier") || "[]"); } catch (_) { return null; }
});
const quantiteAuPanier = async (page, id) => {
  const l = (await lirePanier(page)).find((x) => x.produitId === id);
  return l ? l.quantite : 0;
};
const affichee = (page) => page.evaluate(() => {
  const q = document.querySelector("#p-quantite");
  return q ? Number(q.textContent) : null;
});

titre("1. La fiche produit s'arrête au stock");
{
  const { page, ctx, erreurs } = await ouvrirClient();
  await aller(page, "#/produit/prod_clavier", 1500);
  const bas = await page.$eval("#p-stock-bas", (e) => e.textContent).catch(() => "");
  ok(/Plus que 3 en stock/.test(bas), "il en reste 3 : la fiche le dit (« " + bas.trim() + " »)");
  await page.click("#p-plus");
  await page.click("#p-plus");
  ok(await affichee(page) === 3, "le « + » monte jusqu'à 3");
  await page.click("#p-plus");
  ok(await affichee(page) === 3 && /Plus que 3 en stock/.test(await toast(page)),
    "un quatrième « + » ne passe pas, et dit pourquoi (« " + (await toast(page)) + " »)");
  await page.click("#p-ajouter");
  await page.waitForTimeout(200);
  ok(await quantiteAuPanier(page, "prod_clavier") === 3, "les 3 pièces sont au panier");
  await page.click("#p-plus");
  ok(/déjà les 3 pièces en stock dans votre panier/.test(await toast(page)),
    "avec tout le stock au panier, le « + » s'arrête dès 1 (« " + (await toast(page)) + " »)");
  await page.click("#p-ajouter");
  await page.waitForTimeout(200);
  ok(await quantiteAuPanier(page, "prod_clavier") === 3, "et « Ajouter » n'ajoute rien de plus");

  await aller(page, "#/produit/prod_cable", 1200);
  ok(!(await page.$("#p-stock-bas")), "12 en stock : pas d'alerte « Plus que »");

  await aller(page, "#/produit/prod_serveur", 1200);
  for (let i = 0; i < 11; i++) await page.click("#p-plus");
  await page.click("#p-ajouter");
  await page.waitForTimeout(200);
  ok(await quantiteAuPanier(page, "prod_serveur") === 12,
    "un produit SUR COMMANDE n'a pas de limite de stock (12 au panier)");

  await aller(page, "#/produit/prod_ecran", 1200);
  ok(!(await page.$("#p-ajouter")), "un produit en rupture n'a pas de bouton « Ajouter au panier »");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("2. Le panier se ramène au stock du moment");
{
  /* Rempli hier : depuis, deux souris sont parties et l'écran est épuisé. */
  const { page, ctx, erreurs } = await ouvrirClient({ panier: [
    { produitId: "prod_souris", quantite: 5 },
    { produitId: "prod_ecran", quantite: 1 },
    { produitId: "prod_clavier", quantite: 1 },
  ] });
  await aller(page, "#/panier", 1500);
  const avis = await page.$eval("#pa-stock", (e) => e.textContent).catch(() => "");
  ok(/Plus disponible : « Écran 24 pouces »/.test(avis), "l'article épuisé est nommé");
  ok(/« Souris sans fil » : il n'en reste que 2, la quantité est ramenée à 2/.test(avis),
    "la quantité trop grande est ramenée, et on le dit");
  ok(await quantiteAuPanier(page, "prod_souris") === 2, "le panier gardé sur le téléphone suit (2)");
  ok(await page.$eval("#pa-commander", (b) => b.disabled), "« Passer la commande » est grisé");
  ok(/En rupture — retirez-le pour commander/.test(await page.evaluate(() => document.body.innerText)),
    "la ligne épuisée dit quoi faire");

  await page.click('[data-panier-action="plus"][data-produit="prod_souris"]');
  ok(/Plus que 2 en stock/.test(await toast(page)) && await quantiteAuPanier(page, "prod_souris") === 2,
    "le « + » de la souris s'arrête au stock");
  await page.click('[data-panier-action="plus"][data-produit="prod_clavier"]');
  await page.waitForTimeout(150);
  await page.click('[data-panier-action="plus"][data-produit="prod_clavier"]');
  await page.waitForTimeout(150);
  await page.click('[data-panier-action="plus"][data-produit="prod_clavier"]');
  ok(await quantiteAuPanier(page, "prod_clavier") === 3 && /Plus que 3 en stock/.test(await toast(page)),
    "le clavier monte à 3, pas au-delà");
  await page.click('[data-panier-action="plus"][data-produit="prod_ecran"]');
  ok(/en rupture : retirez-le/.test(await toast(page)), "le « + » d'un article épuisé le dit en clair");
  await page.click('[data-panier-action="moins"][data-produit="prod_clavier"]');
  await page.waitForTimeout(150);
  ok(await quantiteAuPanier(page, "prod_clavier") === 2, "descendre marche toujours");
  await page.click('[data-panier-action="retirer"][data-produit="prod_ecran"]');
  await page.waitForTimeout(300);
  ok(!(await page.$eval("#pa-commander", (b) => b.disabled)),
    "l'article épuisé retiré, « Passer la commande » revient");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("3. Pas de formulaire de paiement avec un article épuisé");
{
  const { page, ctx, commandes } = await ouvrirClient({ panier: [
    { produitId: "prod_cable", quantite: 1 }, { produitId: "prod_ecran", quantite: 1 },
  ] });
  await aller(page, "#/commande", 1500);
  ok(await page.evaluate(() => location.hash) === "#/panier", "un lien direct vers la commande ramène au panier");
  ok(/n'est plus disponible/.test(await toast(page)), "et dit pourquoi");
  ok(!commandes.length, "rien n'est parti vers la base");
  await ctx.close();
}

titre("4. Refus de la base : une autre vente est passée entre-temps");
{
  const { page, ctx, erreurs, commandes } = await ouvrirClient({
    panier: [{ produitId: "prod_clavier", quantite: 3 }],
    options: { venteVoisine: { id: "prod_clavier", reste: 1 } },
  });
  await aller(page, "#/commande", 1800);
  await page.fill("#co-nom", "Awa");
  await page.fill("#co-tel", "97000123");
  await page.fill("#co-adresse", "Cotonou, Haie Vive");
  await page.click("#co-payer");
  await page.waitForTimeout(2200);
  ok(commandes.length === 1 && commandes[0].articles[0].quantite === 3,
    "la commande est partie avec 3 claviers, comme le panier");
  ok(/Plus que 1 en stock pour « Clavier Bluetooth »/.test(await toast(page)),
    "le refus de la base s'affiche tel quel (« " + (await toast(page)).slice(0, 60) + "… »)");
  ok(await page.evaluate(() => location.hash) === "#/panier", "retour au panier");
  const avis = await page.$eval("#pa-stock", (e) => e.textContent).catch(() => "");
  ok(/il n'en reste que 1, la quantité est ramenée à 1/.test(avis) &&
     await quantiteAuPanier(page, "prod_clavier") === 1,
    "catalogue relu : la quantité est ramenée à ce qui reste, et on le dit");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("4 bis. Une vente passe pendant que le client remplit le formulaire");
{
  /* Le temps réel relit le catalogue sous ses doigts, comme « live.js ». */
  const { page, ctx, erreurs, produits, commandes } = await ouvrirClient({
    panier: [{ produitId: "prod_clavier", quantite: 3 }, { produitId: "prod_cable", quantite: 1 }] });
  await aller(page, "#/commande", 1800);
  ok(!!(await page.$("#co-payer")), "le formulaire de commande est ouvert");
  const clavier = produits.find((x) => x.id === "prod_clavier");
  clavier.stock = 2;
  await page.evaluate(() => Catalogue.rafraichir());
  await page.waitForTimeout(1800);
  ok(await page.evaluate(() => location.hash) === "#/panier",
    "la quantité ne tient plus : retour au panier, avant de payer un autre total");
  const avis = await page.$eval("#pa-stock", (e) => e.textContent).catch(() => "");
  ok(/« Clavier Bluetooth » : il n'en reste que 2, la quantité est ramenée à 2/.test(avis),
    "et le panier dit ce qui a changé");

  /* Un autre changement du catalogue redessine le panier : le message
     reste tant que le client n'a pas touché à son panier. */
  produits.find((x) => x.id === "prod_cable").prix = 7000;
  await page.evaluate(() => Catalogue.rafraichir());
  await page.waitForTimeout(1500);
  ok(/ramenée à 2/.test(await page.$eval("#pa-stock", (e) => e.textContent).catch(() => "")),
    "un second dessin de l'écran ne fait pas disparaître le message");

  await page.click("#pa-commander");
  await page.waitForTimeout(1500);
  ok(await page.evaluate(() => location.hash) === "#/commande" && !!(await page.$("#co-payer")),
    "« Passer la commande » mène cette fois au formulaire (pas de boucle)");
  ok(!commandes.length, "et rien n'est parti tant que le client n'a pas payé");

  await aller(page, "#/panier", 1300);
  await page.click('[data-panier-action="moins"][data-produit="prod_clavier"]');
  await page.waitForTimeout(400);
  ok(!(await page.$("#pa-stock")), "dès que le client touche à son panier, le message s'en va");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* =====================================================
   La boutique
   ===================================================== */

const MOI = "55555555-5555-5555-5555-555555555555";

async function ouvrirAdmin({ role = "administrateur", peutModifier = true, hash = "#/stock",
                             catalogue = CATALOGUE, options = {} } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1100 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((moi) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: b64({ alg: "HS256" }) + "." + b64({ sub: moi }) + ".s",
      refresh_token: "r", expire_a: Date.now() + 3600000, email: "chef@impact.bj" }));
  }, MOI);

  const produits = catalogue();
  const ecritures = [];
  const stockage = [];
  const ordre = [];
  const vente = { aLEcriture: options.venteALEcriture || null };
  await page.route("**/storage/v1/object/**", async (route) => {
    const req = route.request();
    if (new URL(req.url()).pathname.includes("/object/public/")) {
      return route.fulfill({ status: 404, body: "" });
    }
    let corps = null;
    try { corps = JSON.parse(req.postData() || "null"); } catch (_) { corps = null; }
    stockage.push({ methode: req.method(), corps });
    ordre.push(req.method() + " stockage");
    return route.fulfill({ status: 200, contentType: "application/json", body: "{}" });
  });
  await page.route("**/rest/v1/**", async (route) => {
    const req = route.request();
    const url = new URL(req.url());
    const c = url.pathname.replace(/^.*\/rest\/v1\//, "");
    const p = url.searchParams;
    const d = (x, status = 200) => route.fulfill({ status, contentType: "application/json", body: JSON.stringify(x) });
    const methode = req.method();

    if (methode !== "GET") {
      let corps = null;
      try { corps = JSON.parse(req.postData() || "null"); } catch (_) { corps = req.postData(); }
      ecritures.push({ methode, table: c, requete: decodeURIComponent(url.search), corps });
      if (c === "produits" && methode === "PATCH") {
        ordre.push("PATCH produits");
        await new Promise((r) => setTimeout(r, 250));
        const id = (p.get("id") || "").replace(/^eq\./, "");
        const i = produits.findIndex((x) => x.id === id);
        /* Une vente payée À L'INSTANT où la boutique écrit. */
        if (vente.aLEcriture && i >= 0 && produits[i].id === vente.aLEcriture.id) {
          produits[i].stock = vente.aLEcriture.reste;
          vente.aLEcriture = null;
        }
        /* Le filtre « stock=eq.N », lu comme PostgREST le lirait. */
        const garde = p.get("stock");
        if (i < 0 || (garde !== null && Number(garde.replace(/^eq\./, "")) !== produits[i].stock)) {
          return d([]);
        }
        produits[i] = { ...produits[i], ...corps };
        return d([produits[i]]);
      }
      if (c === "produits" && methode === "POST" && p.get("on_conflict")) return d([corps]);
      return d([]);
    }

    if (c.startsWith("profils")) return d([{ id: MOI, email: "chef@impact.bj", role, actif: true,
      peut_modifier_produits: peutModifier,
      boutique_id: role === "superadministrateur" ? null : "bou_info" }]);
    if (c.startsWith("boutiques")) return d([BOUTIQUE]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    if (c.startsWith("categories")) return d(CATEGORIES);
    if (c.startsWith("journal") && p.get("id")) {
      const e = (options.journal || {})[(p.get("id") || "").replace(/^eq\./, "")];
      return d(e ? [e] : []);
    }
    if (c.startsWith("notifications")) return d(options.notifications || []);
    if (c.startsWith("produits")) {
      if (p.get("select") === "reference") return d(produits.map((x) => ({ reference: x.reference })));
      const id = (p.get("id") || "").replace(/^eq\./, "");
      if (id) return d(produits.filter((x) => x.id === id));
      return d(produits);
    }
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1500);
  await aller(page, hash, 1500);
  return { page, ctx, erreurs, ecritures, produits, stockage, ordre, vente };
}

const lignes = (page) => page.evaluate(() =>
  [...document.querySelectorAll("#stock-liste .ligne")].map((l) => ({
    id: l.dataset.stock || (l.dataset.nav || "").replace("#/produit/", ""),
    modifiable: !!l.dataset.stock,
    chiffre: (l.querySelector(".stock-chiffre") || {}).textContent || "",
    classe: ((l.querySelector(".stock-chiffre") || {}).className || ""),
    note: (l.querySelector(".ligne-stock") || {}).textContent || "",
  })));
const puces = (page) => page.evaluate(() =>
  [...document.querySelectorAll("#stock-filtres .puce")].map((b) =>
    (b.classList.contains("active") ? "*" : "") + b.textContent));
const envoisStock = (ecritures) => ecritures.filter((e) => e.methode === "PATCH" && e.table === "produits");
const ouvrirLigne = async (page, id) => {
  await page.click('#stock-liste [data-stock="' + id + '"]');
  await page.waitForSelector("#stock-valeur", { timeout: 4000 });
};

titre("5. L'écran Stock : le plus urgent en tête");
{
  const { page, ctx, erreurs } = await ouvrirAdmin();
  const entete = await page.evaluate(() => ({
    titre: (document.querySelector("#topbar h1") || {}).textContent,
    sous: (document.querySelector("#topbar .sous") || {}).textContent,
  }));
  ok(entete.titre === "Stock" && entete.sous === "1 en rupture · 2 bientôt épuisés",
    "l'en-tête résume ce qui manque (« " + entete.sous + " »)");
  const l = await lignes(page);
  ok(l.map((x) => x.id).join(",") ===
     "prod_ecran,prod_souris,prod_clavier,prod_cable,prod_onduleur,prod_serveur",
    "rupture, puis bientôt épuisés (du plus bas au plus haut), puis le reste");
  ok(l[0].chiffre === "0" && /stock-rupture/.test(l[0].classe) && l[0].note === "En rupture",
    "la rupture en rouge : 0, « En rupture »");
  ok(l[1].chiffre === "2" && /stock-bas/.test(l[1].classe) && l[1].note === "Bientôt épuisé",
    "le stock bas en orange : 2, « Bientôt épuisé »");
  ok(l[3].chiffre === "12" && /stock-ok/.test(l[3].classe), "le stock confortable en vert : 12");
  ok(l[4].chiffre === "" && /^Arrive dans 3 jours/.test(l[4].note), "le réassort dit quand il arrive");
  ok(l[5].chiffre === "" && l[5].note === "Sans stock", "le produit sur commande n'a pas de chiffre");
  ok((await puces(page)).join(" | ") ===
     "*Tout (6) | En rupture (1) | Bientôt épuisés (2) | En stock (1) | En approvisionnement (1) | Sur commande (1)",
    "les filtres sont comptés");

  await page.click('#stock-filtres [data-filtre="bas"]');
  ok((await lignes(page)).map((x) => x.id).join(",") === "prod_souris,prod_clavier",
    "« Bientôt épuisés » n'en garde que deux");
  await page.fill("#stock-recherche", "clav");
  await page.waitForTimeout(400);
  ok((await lignes(page)).map((x) => x.id).join(",") === "prod_clavier", "la recherche s'y ajoute");
  await page.fill("#stock-recherche", "");
  await page.click('#stock-filtres [data-filtre=""]');
  await page.waitForTimeout(300);
  ok((await lignes(page)).length === 6, "« Tout » les rend toutes");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("5 bis. Le filtre arrive avec le lien");
{
  const { page, ctx } = await ouvrirAdmin({ hash: "#/stock?filtre=rupture" });
  ok((await lignes(page)).map((x) => x.id).join(",") === "prod_ecran" &&
     (await puces(page)).includes("*En rupture (1)"),
    "« #/stock?filtre=rupture » pose le doigt sur ce qui manque");
  await aller(page, "#/stock?filtre=nimportequoi");
  ok((await lignes(page)).length === 6 && (await puces(page))[0] === "*Tout (6)",
    "un filtre inconnu retombe sur « Tout »");
  await ctx.close();
}

titre("6. Changer un chiffre : un appui, un envoi, sur le chiffre vu");
{
  const { page, ctx, erreurs, ecritures, produits } = await ouvrirAdmin();
  await ouvrirLigne(page, "prod_souris");
  const actuel = await page.$eval("#stock-actuel", (e) => e.textContent);
  ok(/Actuellement : 2 en stock/.test(actuel) && await page.$eval("#stock-valeur", (e) => e.value) === "2",
    "la feuille part du chiffre relu en base (« " + actuel + " »)");
  await page.fill("#stock-valeur", "7");
  await page.evaluate(() => { const b = document.querySelector("#stock-enregistrer"); b.click(); b.click(); });
  await page.waitForTimeout(150);
  ok(await page.evaluate(() => [...document.querySelectorAll("#feuille-corps button")].every((b) => b.disabled)),
    "pendant l'envoi, les boutons de la feuille sont grisés");
  await page.waitForTimeout(1500);
  const envois = envoisStock(ecritures);
  ok(envois.length === 1, "un double appui n'envoie qu'une fois (" + envois.length + ")");
  ok(envois[0] && /id=eq\.prod_souris/.test(envois[0].requete) && /stock=eq\.2/.test(envois[0].requete),
    "l'écriture est gardée par le chiffre vu (« " + (envois[0] || {}).requete + " »)");
  ok(envois[0] && envois[0].corps.stock === 7 && envois[0].corps.disponible === true,
    "7 pièces, et le produit redevient disponible");
  ok(/Stock : 7 en boutique/.test(await toast(page)), "le succès se dit");
  const l = await lignes(page);
  const souris = l.find((x) => x.id === "prod_souris");
  ok(souris && souris.chiffre === "7" && /stock-ok/.test(souris.classe) &&
     produits.find((x) => x.id === "prod_souris").stock === 7,
    "la liste se relit : la souris passe « En stock », 7");
  ok(await page.evaluate(() => document.querySelector("#feuille").hidden), "la feuille est refermée");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("7. Une vente payée pendant la saisie n'est pas écrasée");
{
  const { page, ctx, erreurs, ecritures, produits } = await ouvrirAdmin({
    options: { venteALEcriture: { id: "prod_cable", reste: 11 } } });

  /* a. La vente passe pendant que la feuille est ouverte. */
  await ouvrirLigne(page, "prod_clavier");
  produits.find((x) => x.id === "prod_clavier").stock = 1;
  await page.fill("#stock-valeur", "10");
  await page.click("#stock-enregistrer");
  await page.waitForTimeout(1200);
  ok(!envoisStock(ecritures).length, "rien n'est écrit par-dessus la vente");
  ok(/a changé pendant que vous le modifiiez.*maintenant de 1/.test(await toast(page)),
    "l'écran le dit, avec le chiffre du moment");
  const actuel = await page.$eval("#stock-actuel", (e) => e.textContent);
  ok(/1 en stock/.test(actuel) && /vient de changer/.test(actuel), "la feuille montre le nouveau chiffre");
  ok(await page.$eval("#stock-valeur", (e) => e.value) === "10" &&
     !(await page.$eval("#stock-enregistrer", (b) => b.disabled)),
    "ce qui a été tapé reste là, et le bouton revient");
  await page.click("#stock-enregistrer");
  await page.waitForTimeout(1300);
  let envois = envoisStock(ecritures);
  ok(envois.length === 1 && /stock=eq\.1/.test(envois[0].requete) && envois[0].corps.stock === 10,
    "le second appui part du nouveau chiffre (stock=eq.1 → 10)");

  /* b. La vente passe ENTRE la relecture et l'écriture. */
  await ouvrirLigne(page, "prod_cable");
  await page.fill("#stock-valeur", "20");
  await page.click("#stock-enregistrer");
  await page.waitForTimeout(1500);
  envois = envoisStock(ecritures);
  ok(envois.length === 2 && /stock=eq\.12/.test(envois[1].requete) &&
     produits.find((x) => x.id === "prod_cable").stock === 11,
    "l'écriture gardée par « 12 » ne touche rien : la base est à 11");
  ok(/maintenant de 11/.test(await toast(page)) &&
     /11 en stock/.test(await page.$eval("#stock-actuel", (e) => e.textContent)),
    "l'écran le dit, et se remet à 11");
  await page.click("#stock-enregistrer");
  await page.waitForTimeout(1300);
  envois = envoisStock(ecritures);
  ok(envois.length === 3 && /stock=eq\.11/.test(envois[2].requete) &&
     produits.find((x) => x.id === "prod_cable").stock === 20,
    "le second appui écrit 20 sur 11");

  /* c. Un produit sur commande n'a pas de stock qui bouge : pas de garde. */
  await ouvrirLigne(page, "prod_serveur");
  await page.fill("#stock-valeur", "4");
  await page.click("#stock-enregistrer");
  await page.waitForTimeout(1300);
  envois = envoisStock(ecritures);
  ok(envois.length === 4 && !/stock=eq/.test(envois[3].requete) &&
     envois[3].corps.stock === 4 && envois[3].corps.sur_commande === false,
    "passer un produit sur commande à 4 pièces s'écrit sans garde");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("8. Le formulaire produit ne rend pas les pièces vendues");
{
  const { page, ctx, erreurs, ecritures, produits } = await ouvrirAdmin({ hash: "#/produit/prod_souris/modifier" });
  await page.waitForSelector("#p-enregistrer", { timeout: 5000 });
  /* La souris se vend pendant qu'on retouche la description. */
  produits.find((x) => x.id === "prod_souris").stock = 1;
  await page.fill("#p-description", "Souris 2,4 GHz, pile fournie.");
  await page.click("#p-enregistrer");
  await page.waitForTimeout(1800);
  let envois = envoisStock(ecritures);
  ok(envois.length === 1 && !("stock" in envois[0].corps) && !("disponible" in envois[0].corps),
    "le stock n'a pas été touché : il ne part pas");
  ok(envois[0] && envois[0].corps.description === "Souris 2,4 GHz, pile fournie.", "la description, si");
  ok(produits.find((x) => x.id === "prod_souris").stock === 1, "la vente reste décomptée (1)");
  ok(/^#\/produit\/prod_souris$/.test(await page.evaluate(() => location.hash)), "retour à la fiche");

  /* Le stock changé à la main PENDANT une vente. */
  await aller(page, "#/produit/prod_clavier/modifier", 1500);
  produits.find((x) => x.id === "prod_clavier").stock = 2;
  await page.fill("#p-stock", "9");
  await page.click("#p-enregistrer");
  await page.waitForTimeout(1500);
  envois = envoisStock(ecritures);
  ok(envois.length === 1, "rien n'est écrit par-dessus la vente");
  ok(/maintenant de 2/.test(await toast(page)) &&
     /Stock actuel en base : 2/.test(await page.$eval("#p-stock-change", (e) => e.textContent).catch(() => "")),
    "le formulaire dit le chiffre du moment, sous le champ");
  ok(await page.$eval("#p-stock", (e) => e.value) === "9" &&
     !(await page.$eval("#p-enregistrer", (b) => b.disabled)),
    "la saisie reste, le bouton revient");
  await page.click("#p-enregistrer");
  await page.waitForTimeout(1800);
  envois = envoisStock(ecritures);
  ok(envois.length === 2 && /stock=eq\.2/.test(envois[1].requete) && envois[1].corps.stock === 9,
    "le second appui écrit 9 sur 2");

  /* Changer de mode remet le stock à zéro, comme avant. */
  await aller(page, "#/produit/prod_cable/modifier", 1500);
  await page.click("label[for='p-sur-commande'], #p-sur-commande").catch(() => {});
  await page.evaluate(() => {
    const c = document.querySelector("#p-sur-commande");
    if (!c.checked) { c.checked = true; c.dispatchEvent(new Event("change")); }
  });
  await page.click("#p-enregistrer");
  await page.waitForTimeout(1800);
  envois = envoisStock(ecritures);
  ok(envois.length === 3 && envois[2].corps.sur_commande === true && envois[2].corps.stock === 0 &&
     !/stock=eq/.test(envois[2].requete),
    "passer « Sur commande » remet le stock à 0, sans garde");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("8 bis. Un refus ne laisse rien derrière lui : aucune photo effacée");
{
  const avecPhotos = () => CATALOGUE().map((p) => (p.id === "prod_souris"
    ? { ...p, images: ["pho_souris_1.jpg", "pho_souris_2.jpg"] } : p));
  const { page, ctx, erreurs, ecritures, produits, stockage, ordre, vente } = await ouvrirAdmin({
    hash: "#/produit/prod_souris/modifier", catalogue: avecPhotos });
  await page.waitForSelector("#photos-zone [data-retirer]", { timeout: 5000 });
  await page.click("#photos-zone [data-retirer]");
  const effaces = () => stockage.filter((e) => e.methode === "DELETE")
    .flatMap((e) => (e.corps && e.corps.prefixes) || []);

  /* a. Une vente passe pendant qu'on retire la photo et change le stock. */
  produits.find((x) => x.id === "prod_souris").stock = 1;
  await page.fill("#p-stock", "8");
  await page.click("#p-enregistrer");
  await page.waitForTimeout(1500);
  ok(!envoisStock(ecritures).length && !effaces().length,
    "le stock a bougé : la fiche ne s'écrit pas, et la photo retirée reste au stockage");

  /* b. Une autre vente, cette fois à l'instant même de l'écriture. */
  vente.aLEcriture = { id: "prod_souris", reste: 0 };
  await page.click("#p-enregistrer");
  await page.waitForTimeout(1800);
  ok(envoisStock(ecritures).length === 1 && !effaces().length &&
     /maintenant de 0/.test(await toast(page)),
    "l'écriture gardée ne touche rien, et la photo reste encore");

  /* c. Le troisième appui passe : la fiche d'abord, le fichier ensuite. */
  await page.click("#p-enregistrer");
  await page.waitForTimeout(2200);
  const envois = envoisStock(ecritures);
  ok(envois.length === 2 && /stock=eq\.0/.test(envois[1].requete) && envois[1].corps.stock === 8 &&
     envois[1].corps.images.join() === "pho_souris_2.jpg",
    "la fiche s'écrit : 8 pièces, une seule photo");
  ok(effaces().join() === "pho_souris_1.jpg", "la photo retirée part du stockage");
  ok(ordre.lastIndexOf("DELETE stockage") > ordre.lastIndexOf("PATCH produits"),
    "et seulement APRÈS l'écriture de la fiche (" + ordre.join(" → ") + ")");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("9. Sans le droit de modifier : l'écran se lit");
{
  const { page, ctx, erreurs } = await ouvrirAdmin({ role: "moderateur", peutModifier: false });
  const l = await lignes(page);
  ok(l.length === 6 && l.every((x) => !x.modifiable), "toutes les lignes sont là, aucune ne s'édite");
  ok(/consulte\s+le stock sans le modifier/.test(await page.evaluate(() => document.body.innerText)),
    "l'écran dit pourquoi, et à qui demander");
  await page.click('#stock-liste .ligne[data-nav="#/produit/prod_ecran"]');
  await page.waitForTimeout(1200);
  ok(await page.evaluate(() => location.hash) === "#/produit/prod_ecran" &&
     await page.evaluate(() => document.querySelector("#feuille").hidden),
    "toucher une ligne ouvre la fiche, pas la feuille de stock");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("10. L'accueil, les produits et les notifications y mènent");
{
  const notifications = [
    { id: 1, type: "stock_epuise", titre: "Rupture de stock", destinataire: MOI,
      corps: "Écran 24 pouces : plus aucune pièce après la commande BZ-000123.",
      lien: "#/stock?filtre=rupture", lue: false, sonne: false, cree_le: il(3) },
    { id: 2, type: "stock_insuffisant", titre: "Stock insuffisant", destinataire: MOI,
      corps: "Commande BZ-000124 payée, mais il manque des pièces : Clavier Bluetooth (2 vendus, 0 en stock).",
      lien: "#/commandes/cmd_124", lue: false, sonne: true, cree_le: il(5) },
    { id: 3, type: "stock_a_verifier", titre: "Stock à vérifier", destinataire: MOI,
      corps: "Commande BZ-000125 payée, mais le stock de Câble USB-C n'a pas pu être décompté.",
      lien: "#/stock", lue: false, sonne: true, cree_le: il(8) },
  ];
  const { page, ctx, erreurs } = await ouvrirAdmin({ hash: "#/", options: { notifications } });
  const carte = await page.evaluate(() => {
    const c = document.querySelector("#carte-stock");
    return c && { lien: c.getAttribute("href"), pressant: c.classList.contains("carte-publier"),
      texte: c.textContent };
  });
  ok(carte && carte.lien === "#/stock?filtre=rupture" && carte.pressant &&
     /1 produit en rupture · 2 bientôt épuisés/.test(carte.texte),
    "l'accueil annonce la rupture, et mène au filtre");

  await aller(page, "#/produits");
  ok(!!(await page.$('#topbar a[href="#/stock"]')), "la liste des produits a son chemin vers le stock");

  await aller(page, "#/notifications", 1800);
  const groupes = await page.evaluate(() =>
    [...document.querySelectorAll(".carte-titre")].map((t) => t.textContent.replace(/\d+$/, "").trim()));
  ok(["Ruptures de stock", "Stock insuffisant", "Stock à vérifier"].every((g) => groupes.includes(g)) &&
     !groupes.includes("Autres"),
    "les trois alertes de stock ont leur famille (" + groupes.join(", ") + ")");
  await page.click('[data-notif="1"]');
  await page.waitForTimeout(1500);
  ok(await page.evaluate(() => location.hash) === "#/stock?filtre=rupture" &&
     (await lignes(page)).map((x) => x.id).join(",") === "prod_ecran",
    "toucher « Rupture de stock » ouvre l'écran Stock sur ce qui manque");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();

  const toutVa = () => CATALOGUE().map((p) =>
    (p.sur_commande || p.appro_le ? p : { ...p, stock: 20, disponible: true }));
  const calme = await ouvrirAdmin({ hash: "#/", catalogue: toutVa });
  const carteCalme = await calme.page.evaluate(() => {
    const c = document.querySelector("#carte-stock");
    return c && { lien: c.getAttribute("href"), pressant: c.classList.contains("carte-publier"),
      texte: c.textContent };
  });
  ok(carteCalme && carteCalme.lien === "#/stock" && !carteCalme.pressant &&
     /Stock de la boutique/.test(carteCalme.texte),
    "tout en stock : la carte reste, sans alarme");
  await calme.ctx.close();
}

titre("11. Défaire une retouche garde le stock du moment");
{
  const souris = CATALOGUE().find((p) => p.id === "prod_souris");
  const entree = (id, action) => ({ id, famille: "produit", action, libelle: "…", cible: "IMP-0501",
    annule_le: null, retour: {
      avant: [{ table: "produits", ligne: { ...souris, nom: "Souris (ancien nom)", stock: 5 } }],
      ids: [{ table: "produits", id: "prod_souris" }] } });
  const { page, ctx, erreurs, ecritures } = await ouvrirAdmin({
    role: "superadministrateur", hash: "#/",
    options: { journal: { J1: entree("J1", "modification"), J2: entree("J2", "stock") } } });
  const essai = (id) => page.evaluate(async (id) => {
    try { await Store.annulerAction(id); return ""; } catch (e) { return e.message; }
  }, id);
  const remise = () => ecritures.filter((e) => e.methode === "POST" && /on_conflict=id/.test(e.requete) &&
    e.table === "produits").pop();

  ok(await essai("J1") === "", "l'action se défait");
  let r = remise();
  ok(r && r.corps.nom === "Souris (ancien nom)" && r.corps.stock === 2 && r.corps.disponible === true,
    "une retouche défaite remet le nom d'avant, mais garde le stock du moment (2, pas 5)");
  ok(await essai("J2") === "", "une action sur le stock se défait aussi");
  r = remise();
  ok(r && r.corps.stock === 5, "et celle-là remet bien l'ancien chiffre (5)");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " constat(s) en échec." : "\nTous les constats sont bons.");
process.exit(echecs ? 1 : 0);
