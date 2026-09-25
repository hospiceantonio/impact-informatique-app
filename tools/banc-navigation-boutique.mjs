/* =========================================================
   La barre du bas à deux visages : BIZZOO, et une boutique
   =========================================================
   CE QUE L'ENSEIGNE A DEMANDÉ, et que ce banc tient :

     1. SUR BIZZOO, quatre onglets — Accueil, Catégories, Favoris,
        Recherche — et le compte en haut, juste avant le panier ;
     2. DANS UNE BOUTIQUE, cinq : Accueil, Catégories, Favoris,
        Recherche et « Retour à Bizzoo ». « Accueil » y mène à SA
        vitrine ; « Retour à Bizzoo » ramène à l'accueil de
        l'enseigne, et fait sortir de la boutique ;
     3. CES ONGLETS PARLENT D'ELLE : « Catégories » montre ses
        rayons, un rayon ses produits ; la recherche fouille d'abord
        chez elle, une puce l'élargit à toutes les boutiques ; les
        favoris, eux, restent tous les vôtres ;
     4. LA FICHE D'UN PRODUIT garde la barre de sa boutique, et
        « Ajouter au panier » se pose au-dessus, jamais dessus ;
     5. LE PANIER, le paiement, la confirmation traversent les
        boutiques : ils restent sans barre ;
     6. RIEN NE SE COUPE sur un téléphone de 320 px, et sur
        ordinateur le menu de gauche et l'action ne se chevauchent pas.

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-navigation-boutique.mjs
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-navigation-boutique.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

/* Deux boutiques qui vendent toutes deux de l'électronique : c'est ce
   qui dit si les rayons et la recherche d'une boutique restent les
   siens. Bêta tient en plus un rayon « Son » qu'Alpha n'a pas. */
const CATS = [
  { id: "cat_tech", nom: "Électronique", icone: "portable", couleur: "#2550B7", en_avant: true,
    ordre: 1, boutique_id: null,
    sous_categories: [{ id: "sc_pc", nom: "Ordinateurs", ordre: 1 }, { id: "sc_son", nom: "Son", ordre: 2 }] },
  { id: "cat_mode", nom: "Mode", icone: "tshirt", couleur: "#D81B60", en_avant: true,
    ordre: 2, boutique_id: null, sous_categories: [{ id: "sc_hab", nom: "Habits", ordre: 1 }] },
];
const BOUT = [
  { id: "bou_a", nom: "Alpha", secteur: "Informatique", categorie_id: "cat_tech", ordre: 1 },
  { id: "bou_b", nom: "Bêta", secteur: "Tout", categorie_id: "cat_mode", ordre: 2 },
].map((b) => ({ ...b, icone: "magasin", couleur: "#2550B7", devise: "FCFA", indicatif: "229",
  actif: true, slogan: "", photos: [], note_moyenne: null, nb_avis: 0 }));
const produit = (id, boutique, nom, cat, sc, prix) => ({ id, boutique_id: boutique, nom, code: id,
  reference: "", description: "", prix, ancien_prix: null, categorie_id: cat, sous_categorie_id: sc,
  stock: 5, sur_commande: false, disponible: true, en_avant: false, ordre_avant: 0, images: [],
  video: "", cree_le: "2026-09-01T08:00:00Z", modifie_le: "2026-09-01T08:00:00Z",
  note_moyenne: null, nb_avis: 0 });
const PROD = [
  produit("pa1", "bou_a", "Ordinateur Alpha", "cat_tech", "sc_pc", 300000),
  produit("pa2", "bou_a", "Souris Alpha", "cat_tech", "sc_pc", 5000),
  produit("pb1", "bou_b", "Casque Bêta", "cat_tech", "sc_son", 35000),
  produit("pb2", "bou_b", "Chemise Bêta", "cat_mode", "sc_hab", 9000),
  produit("pb3", "bou_b", "Ordinateur Bêta", "cat_tech", "sc_pc", 280000),
];

async function ouvrir({ hash = "", largeur = 390, hauteur = 844, panier = null, boutiques = BOUT } = {}) {
  const ctx = await nav.newContext({ viewport: { width: largeur, height: hauteur } });
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log("  ERREUR JS :", e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({
      url: "https://base-absente.invalid", cle: "cle-de-banc" }));
    localStorage.removeItem("impact-boutique");
    if (a.panier) localStorage.setItem("bizzoo-panier", JSON.stringify(a.panier));
  }, { panier });
  await page.route("**/rest/v1/**", (route) => {
    const c = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json",
      body: JSON.stringify(x) });
    if (c.startsWith("categories")) return d(CATS);
    if (c.startsWith("boutiques")) return d(boutiques);
    if (c.startsWith("produits")) return d(PROD);
    if (c.startsWith("paiement")) return d([{ id: 1, actif: false, fournisseur: "feexpay",
      cle_publique: "", bac_a_sable: true }]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA",
      indicatif: "229", whatsapp: "97000000" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200,
    contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/client/index.html" + hash, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1500);
  return { page, ctx };
}

const toucher = async (page, selecteur) => {
  await page.click(selecteur);
  await page.waitForTimeout(700);
};
const aller = async (page, hash) => {
  await page.evaluate((h) => { location.hash = h; }, hash);
  await page.waitForTimeout(800);
};

/* Les onglets VISIBLES, dans l'ordre. L'espace insécable de « Retour à
   Bizzoo » redevient une espace. */
const onglets = (page) => page.evaluate(() => [...document.querySelectorAll("#tabbar > a")]
  .filter((a) => !a.hidden && getComputedStyle(a).display !== "none")
  .map((a) => a.textContent.replace(/\s+/g, " ").trim()));
const barreVisible = (page) => page.evaluate(() => {
  const b = document.getElementById("tabbar");
  return !!b && getComputedStyle(b).display !== "none";
});
const allume = (page) => page.evaluate(() =>
  [...document.querySelectorAll("#tabbar a.actif")].map((a) => a.textContent.trim()).join(","));
const hrefAccueil = (page) => page.evaluate(() =>
  document.querySelector('#tabbar a[data-tab="/"]').getAttribute("href"));
const texteVue = (page) => page.evaluate(() => document.getElementById("vue").innerText);
const sousTitre = (page) => page.evaluate(() => {
  const s = document.querySelector("#topbar .sous");
  return s ? s.innerText.trim() : "";
});
const nomsProduits = (page) => page.evaluate(() =>
  [...document.querySelectorAll("#vue .p-nom, #vue .carte-produit-nom, #vue [class*='p-carte'] h3")]
    .map((x) => x.innerText.trim()));

const BIZZOO = "Accueil,Catégories,Favoris,Recherche";
const BOUTIQUE = "Accueil,Catégories,Favoris,Recherche,Retour à Bizzoo";

/* ------------------------------------------------------------------ */
titre("1. Sur BIZZOO : quatre onglets, le compte en haut");
{
  const { page, ctx } = await ouvrir();
  ok((await onglets(page)).join(",") === BIZZOO,
    "Accueil, Catégories, Favoris, Recherche (" + (await onglets(page)).join(", ") + ")");
  ok(await hrefAccueil(page) === "#/", "« Accueil » mène à l'accueil de BIZZOO");
  const h = await page.evaluate(() => {
    const c = document.querySelector("#topbar .btn-compte");
    return { la: !!c, href: c ? c.getAttribute("href") : "",
      avantPanier: !!c && !!c.nextElementSibling && c.nextElementSibling.classList.contains("btn-panier") };
  });
  ok(h.la && h.href === "#/compte", "le compte est dans la barre du haut");
  ok(h.avantPanier, "juste à côté du panier");

  await toucher(page, '#tabbar a[data-tab="/recherche"]');
  ok(await page.evaluate(() => location.hash) === "#/recherche", "l'onglet Recherche ouvre la recherche");
  ok(/Recherche/.test(await allume(page)), "et s'allume");
  ok(/toutes les boutiques/i.test(await sousTitre(page)), "qui fouille toutes les boutiques (" +
    (await sousTitre(page)) + ")");
  ok(!(await page.$("#recherche-portee")), "sans puces : on n'est dans aucune boutique");

  /* Un visiteur : le compte le mène à la connexion. */
  await toucher(page, "#topbar .btn-compte");
  const ou = await page.evaluate(() => location.hash);
  ok(ou === "#/compte" || ou === "#/connexion",
    "le bouton du compte ouvre le compte — la connexion, pour un visiteur (" + ou + ")");
  ok(await page.evaluate(() => !!document.querySelector("#topbar .btn-compte.actif")),
    "il s'y allume");
  ok((await allume(page)) === "", "et aucun onglet ne se prétend allumé");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("2. Dans une boutique : cinq onglets, « Accueil » est sa vitrine");
const { page, ctx } = await ouvrir();
{
  /* Par le vrai chemin : la tuile d'une boutique, sur l'accueil. */
  await toucher(page, '#vue a[href="#/boutique/bou_a"]');
  ok(await page.evaluate(() => location.hash) === "#/boutique/bou_a", "on entre chez Alpha");
  ok(await barreVisible(page), "la barre est là, sur la vitrine");
  ok((await onglets(page)).join(",") === BOUTIQUE,
    "Accueil, Catégories, Favoris, Recherche, Retour à Bizzoo (" + (await onglets(page)).join(", ") + ")");
  ok(await hrefAccueil(page) === "#/boutique/bou_a", "« Accueil » mène à la vitrine d'Alpha");
  ok(/Accueil/.test(await allume(page)), "et s'allume sur elle");
  ok(await page.evaluate(() => !!document.querySelector("#tab-bizzoo img.tab-logo")),
    "« Retour à Bizzoo » porte le logo de BIZZOO");
  ok(await page.evaluate(() => !!document.querySelector("#topbar .btn-compte")),
    "le compte reste en haut, dans la boutique aussi");
}

/* ------------------------------------------------------------------ */
titre("3. Ses rayons, pas ceux de BIZZOO");
{
  await toucher(page, '#tabbar a[data-tab="/categories"]');
  ok(await page.evaluate(() => location.hash) === "#/categories", "l'onglet Catégories s'ouvre");
  ok((await onglets(page)).join(",") === BOUTIQUE, "sans faire sortir de la boutique");
  ok(/d'Alpha/.test(await sousTitre(page)), "« Les rayons d'Alpha » (" + (await sousTitre(page)) + ")");
  const t = await texteVue(page);
  ok(/Ordinateurs/.test(t), "son rayon Ordinateurs est là");
  ok(!/\bSon\b/.test(t) && !/Habits/.test(t), "ni « Son » ni « Habits », qu'elle ne tient pas");

  await toucher(page, '#vue a[href*="sc=sc_pc"]');
  const u = await texteVue(page);
  ok(/Ordinateur Alpha/.test(u) && /Souris Alpha/.test(u), "le rayon montre ses produits");
  ok(!/Ordinateur Bêta/.test(u), "et pas ceux de Bêta, du même rayon");
  ok(await page.evaluate(() => ![...document.querySelectorAll(".puce")]
    .some((p) => /^Son$/.test(p.innerText.trim()))), "ses puces ne proposent pas « Son »");
  ok(/Catégories/.test(await allume(page)), "« Catégories » reste allumé dans le rayon");

  await toucher(page, '#tabbar a[data-tab="/"]');
  ok(await page.evaluate(() => location.hash) === "#/boutique/bou_a",
    "« Accueil » ramène à la vitrine d'Alpha, pas à BIZZOO");
}

/* ------------------------------------------------------------------ */
titre("4. La recherche, d'abord chez elle");
{
  await toucher(page, '#tabbar a[data-tab="/recherche"]');
  ok(/Chez Alpha/.test(await sousTitre(page)), "elle se présente « Chez Alpha »");
  ok(await page.evaluate(() => {
    const p = document.querySelector('#recherche-portee .puce.active');
    return !!p && p.dataset.portee === "boutique";
  }), "la puce de la boutique est allumée");
  await page.fill("#recherche-champ", "ordinateur");
  await page.waitForTimeout(500);
  let t = await texteVue(page);
  ok(/Ordinateur Alpha/.test(t) && !/Ordinateur Bêta/.test(t), "elle ne trouve que chez Alpha");
  await toucher(page, '#recherche-portee [data-portee="partout"]');
  t = await texteVue(page);
  ok(/Ordinateur Alpha/.test(t) && /Ordinateur Bêta/.test(t),
    "« Toutes les boutiques » trouve aussi chez Bêta");
  ok(await page.inputValue("#recherche-champ") === "ordinateur", "sans effacer ce qui est tapé");
  ok((await onglets(page)).join(",") === BOUTIQUE, "et toujours dans la boutique");
}

/* ------------------------------------------------------------------ */
titre("5. Les favoris restent tous les vôtres");
{
  /* Un client connecté, un favori dans chaque boutique. */
  await page.evaluate(() => {
    Compte.connecte = () => true;
    Favoris.listeProduits = async () => ["pa1", "pb1"];
    Favoris.listeBoutiques = async () => [];
  });
  await toucher(page, '#tabbar a[data-tab="/favoris"]');
  await page.waitForTimeout(300);
  const t = await texteVue(page);
  ok(/Ordinateur Alpha/.test(t) && /Casque Bêta/.test(t),
    "celui d'Alpha ET celui de Bêta, même depuis Alpha");
  ok(!(await page.$(".fav-absents")), "aucun n'est annoncé « plus en vente »");
  ok((await onglets(page)).join(",") === BOUTIQUE && /Favoris/.test(await allume(page)),
    "dans la barre de la boutique, « Favoris » allumé");
}

/* ------------------------------------------------------------------ */
titre("6. La fiche produit garde la barre de sa boutique");
{
  await aller(page, "#/produit/pa1");
  ok(await barreVisible(page) && (await onglets(page)).join(",") === BOUTIQUE,
    "la barre de la boutique est là");
  const g = await page.evaluate(() => {
    const a = document.getElementById("barre-action");
    const b = document.getElementById("tabbar");
    if (!a || !b) return null;
    const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect();
    return { action: /Ajouter au panier/.test(a.innerText), dessus: ra.bottom <= rb.top + 1,
      ecart: Math.round(rb.top - ra.bottom) };
  });
  ok(!!g && g.action, "avec « Ajouter au panier »");
  ok(!!g && g.dessus, "posé au-dessus des onglets, jamais dessus (" + (g ? g.ecart : "?") + " px)");
}

/* ------------------------------------------------------------------ */
titre("7. « Retour à Bizzoo » fait sortir de la boutique");
{
  await toucher(page, "#tab-bizzoo");
  ok(await page.evaluate(() => location.hash) === "#/", "on revient à l'accueil de BIZZOO");
  ok(await page.evaluate(() => !localStorage.getItem("impact-boutique")), "la boutique est quittée");
  ok((await onglets(page)).join(",") === BIZZOO, "la barre retrouve ses quatre onglets");
  ok(await hrefAccueil(page) === "#/", "« Accueil » redevient celui de BIZZOO");
  await toucher(page, '#tabbar a[data-tab="/categories"]');
  const t = await texteVue(page);
  ok(/Électronique/.test(t) && /Mode/.test(t) && !/d'Alpha/.test(await sousTitre(page)),
    "« Catégories » redevient la liste de BIZZOO");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("8. Les écrans de parcours restent sans barre");
{
  const { page, ctx } = await ouvrir({ hash: "#/panier", panier: [{ produitId: "pa1", quantite: 1 }] });
  ok(!(await barreVisible(page)), "le panier n'a pas de barre");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("9. Sur un téléphone de 320 px, rien ne se coupe");
{
  const { page, ctx } = await ouvrir({ largeur: 320, hash: "#/boutique/bou_a" });
  const m = await page.evaluate(() => [...document.querySelectorAll("#tabbar > a")]
    .filter((a) => !a.hidden).map((a) => {
      const s = a.querySelector("span");
      const r = document.createRange(); r.selectNodeContents(s);
      const rs = s.getBoundingClientRect(), rb = document.getElementById("tabbar").getBoundingClientRect();
      return { texte: s.textContent.replace(/\s+/g, " "),
        coupe: r.getBoundingClientRect().width > rs.width + 0.5, deborde: rs.bottom > rb.bottom + 0.5 };
    }));
  ok(m.length === 5, "les cinq onglets sont là (" + m.length + ")");
  const coupes = m.filter((x) => x.coupe || x.deborde);
  ok(!coupes.length, "aucun libellé coupé ni sorti de la barre" +
    (coupes.length ? " — " + coupes.map((x) => x.texte).join(", ") : ""));
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("10. Sur ordinateur, le menu et l'action ne se chevauchent pas");
{
  const { page, ctx } = await ouvrir({ largeur: 1280, hauteur: 800, hash: "#/produit/pa1" });
  const g = await page.evaluate(() => {
    const b = document.getElementById("tabbar"), a = document.getElementById("barre-action");
    const rb = b.getBoundingClientRect(), ra = a ? a.getBoundingClientRect() : null;
    return { menu: rb.left < 5 && rb.height > 400,
      entrees: [...b.querySelectorAll(":scope > a")].filter((x) => !x.hidden).length,
      aDroite: !!ra && ra.left >= rb.right - 1 };
  });
  ok(g.menu && g.entrees === 5, "le menu de gauche porte les cinq entrées de la boutique");
  ok(g.aDroite, "et « Ajouter au panier » se tient à sa droite");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("11. En boutique unique, pas de « Retour à Bizzoo »");
{
  const { page, ctx } = await ouvrir({ boutiques: [] });
  ok((await onglets(page)).join(",") === BIZZOO, "quatre onglets : il n'y a pas d'enseigne où revenir");
  ok(await hrefAccueil(page) === "#/", "et « Accueil » est l'accueil");
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n  " + echecs + " ÉCHEC(S)" : "\n  Tout passe.");
process.exit(echecs ? 1 : 0);
