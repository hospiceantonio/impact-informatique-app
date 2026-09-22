/* =========================================================
   La photo d'une catégorie, dans les ronds de l'accueil
   =========================================================
   CE QU'ON AJOUTE. Sur la DA, les ronds des catégories de l'accueil
   portent une photo. L'enseigne la pose depuis l'admin
   (Catégories → Modifier) ; elle va dans « enseigne/categories/ »,
   le seul dossier que la base accepte pour elle.

   Ce que le banc prouve :

     1. CHEZ LE CLIENT, la photo REMPLIT le rond — sur l'accueil et
        sur l'écran « Catégories » —, par-dessus l'icône ;
     2. L'ICÔNE EN SECOURS : sans photo, ou si elle ne se charge pas
        (hors connexion, fichier retiré), le rond garde son icône et
        sa couleur — jamais un carré d'image cassée ;
     3. RIEN NE DÉBORDE à 320 px, et une base qui n'a pas encore la
        colonne donne les ronds d'avant, sans erreur ;
     4. LE CHEMIN EST ÉCHAPPÉ : la base refuse les guillemets, mais
        l'écran ne compte pas sur elle ;
     5. DANS L'ADMIN, poser, remplacer, retirer : le fichier part au
        stockage AVANT la ligne, dans le bon dossier, sous un nom que
        la base accepte, une seule fois même sur un double appui ;
        un envoi refusé n'écrit rien ; une fiche dont la photo n'a pas
        bougé n'écrit pas la colonne ;
     6. L'ANCIENNE PHOTO N'EST PAS EFFACÉE : annuler depuis le journal
        remet l'ancien chemin, et le fichier doit encore y être ;
     7. UNE BOUTIQUE VOIT la photo de son secteur, sans pouvoir la
        changer.

   CE QUE LE BANC REGARDE : ce qui est à l'écran — mesuré — et ce qui
   PART vers la base et le stockage, corps compris.

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-categories-photos.mjs
   ========================================================= */
import { deflateSync, crc32 } from "node:zlib";

let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-categories-photos.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

/* UNE VRAIE IMAGE, fabriquée ici : un PNG uni de 96 × 96. Le navigateur
   doit pouvoir la décoder — l'admin la redessine avant de l'envoyer. */
function png(r, g, b, cote = 96) {
  const morceau = (type, donnees) => {
    const t = Buffer.from(type, "ascii");
    const longueur = Buffer.alloc(4); longueur.writeUInt32BE(donnees.length);
    const somme = Buffer.alloc(4); somme.writeUInt32BE(crc32(Buffer.concat([t, donnees])) >>> 0);
    return Buffer.concat([longueur, t, donnees, somme]);
  };
  const entete = Buffer.alloc(13);
  entete.writeUInt32BE(cote, 0); entete.writeUInt32BE(cote, 4);
  entete[8] = 8; entete[9] = 2; // 8 bits, RVB
  const ligne = Buffer.alloc(1 + cote * 3);
  for (let x = 0; x < cote; x++) { ligne[1 + 3 * x] = r; ligne[2 + 3 * x] = g; ligne[3 + 3 * x] = b; }
  const brut = Buffer.concat(Array.from({ length: cote }, () => ligne));
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    morceau("IHDR", entete), morceau("IDAT", deflateSync(brut)), morceau("IEND", Buffer.alloc(0)),
  ]);
}
const ROUGE = png(214, 40, 40);

/* La taille d'un JPEG, lue dans son en-tête (le segment SOF). */
function tailleJpeg(o) {
  for (let i = 2; i + 9 < o.length;) {
    if (o[i] !== 0xff) return null;
    const m = o[i + 1];
    if (m >= 0xc0 && m <= 0xc3) return { hauteur: o.readUInt16BE(i + 5), largeur: o.readUInt16BE(i + 7) };
    i += 2 + o.readUInt16BE(i + 2);
  }
  return null;
}

/* Le chemin que la base accepte — la même règle que
   « categories_image_chemin » dans schema.sql. */
const CHEMIN_PERMIS = /^enseigne\/categories\/[A-Za-z0-9][A-Za-z0-9._-]*$/;

/* LE STOCKAGE. Une photo « cassee » répond 404 : c'est le fichier
   retiré, ou celui que le téléphone hors connexion n'a jamais vu. */
async function brancherStockage(page, envois) {
  await page.route("**/storage/v1/object/**", async (route) => {
    const req = route.request();
    const url = new URL(req.url());
    if (url.pathname.includes("/object/public/")) {
      if (/cassee/.test(url.pathname)) return route.fulfill({ status: 404, body: "" });
      return route.fulfill({ status: 200, body: ROUGE, headers: { "Content-Type": "image/png" } });
    }
    const chemin = decodeURIComponent(url.pathname.replace(/^.*\/storage\/v1\/object\/produits\/?/, ""));
    const corps = req.postDataBuffer() || Buffer.alloc(0);
    envois.push({ quand: envois.length, methode: req.method(), chemin,
      type: req.headers()["content-type"] || "", corps,
      jpeg: corps.length > 2 && corps[0] === 0xff && corps[1] === 0xd8 });
    if (envois.refuser && req.method() === "POST") {
      return route.fulfill({ status: 403, contentType: "application/json",
        body: JSON.stringify({ message: "new row violates row-level security policy" }) });
    }
    /* Un envoi lent : c'est pendant ce temps qu'un second appui ferait
       partir une seconde photo. */
    if (req.method() === "POST") await new Promise((r) => setTimeout(r, 500));
    return route.fulfill({ status: 200, contentType: "application/json",
      body: JSON.stringify({ Key: "produits/" + chemin }) });
  });
}

/* ================= CHEZ LE CLIENT ================= */

const CAT = [
  { id: "cat_0", nom: "Mode & Vêtements", icone: "tshirt", couleur: "#D81B60",
    image: "enseigne/categories/cat_photo0.jpg" },
  { id: "cat_1", nom: "High-Tech", icone: "portable", couleur: "#0B5CF5",
    image: "enseigne/categories/cat_cassee1.jpg" },
  { id: "cat_2", nom: "Maison & Jardin", icone: "maison", couleur: "#0F9D58", image: "" },
  ...Array.from({ length: 5 }, (_, i) => ({ id: "cat_" + (i + 3), nom: "Rayon " + (i + 3),
    icone: "categories", couleur: "#0B5CF5", image: "" })),
].map((c, i) => ({ ...c, en_avant: true, ordre: i + 1, sous_categories: [] }));

async function ouvrirClient(largeur, { categories = CAT, route = "#/" } = {}) {
  const ctx = await nav.newContext({ viewport: { width: largeur, height: 1600 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(() => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.removeItem("impact-boutique");
  });
  await brancherStockage(page, []);
  await page.route("**/rest/v1/**", (r) => {
    const c = new URL(r.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("categories")) return d(categories);
    /* UNE BOUTIQUE AU MOINS : sans elle, l'application est en mode
       « boutique unique », et l'accueil de l'enseigne — celui des
       ronds — ne se montre pas. */
    if (c.startsWith("boutiques")) return d([{ id: "bou_1", nom: "Chic Cotonou", secteur: "Mode",
      categorie_id: "cat_0", icone: "magasin", couleur: "#0B5CF5", logo: "", devise: "FCFA",
      indicatif: "229", actif: true, ordre: 1 }]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html" + route, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(2200);
  return { page, ctx, erreurs };
}

/* Ce que montre chaque rond : la photo est-elle là, chargée, par-dessus
   l'icône, et le recouvre-t-elle tout entier ? */
const lireRonds = (page, selecteur) => page.evaluate((sel) => {
  return [...document.querySelectorAll(sel)].map((rond) => {
    const r = rond.getBoundingClientRect();
    const img = rond.querySelector("img");
    const ic = rond.querySelector("svg");
    const style = getComputedStyle(rond);
    const auCentre = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    const ri = img ? img.getBoundingClientRect() : null;
    return {
      lien: (rond.closest("a") || {}).getAttribute ? rond.closest("a").getAttribute("href") : "",
      photo: img ? img.getAttribute("src") : null,
      chargee: !!(img && img.complete && img.naturalWidth > 0),
      auDessus: !!(img && auCentre === img),
      couvre: !!(ri && Math.abs(ri.width - r.width) < 1.5 && Math.abs(ri.height - r.height) < 1.5 &&
                 Math.abs(ri.left - r.left) < 1.5 && Math.abs(ri.top - r.top) < 1.5),
      coupe: style.overflow === "hidden" && (style.borderRadius === "50%" ||
             parseFloat(style.borderTopLeftRadius) >= r.width / 2 - 0.5),
      cover: img ? getComputedStyle(img).objectFit === "cover" : false,
      icone: !!(ic && ic.getBoundingClientRect().width > 0),
      attributs: img ? [...img.attributes].map((a) => a.name) : [],
      largeur: Math.round(r.width),
    };
  });
}, selecteur);

const deborde = (page) => page.evaluate(() =>
  document.documentElement.scrollWidth > document.documentElement.clientWidth + 1);

for (const L of [390, 320]) {
  titre("L'accueil à " + L + " px : la photo dans le rond");
  const { page, ctx, erreurs } = await ouvrirClient(L);
  const ronds = await lireRonds(page, ".cat-rond-da");
  ok(ronds.length === 8, "huit ronds sur l'accueil (" + ronds.length + ")");
  const [avec, cassee, sans] = ronds;
  ok(avec && /\/storage\/v1\/object\/public\/produits\/enseigne\/categories\/cat_photo0\.jpg$/
      .test(avec.photo || ""), "la photo vient du stockage public (" + (avec && avec.photo) + ")");
  ok(avec && avec.chargee, "elle est chargée");
  ok(avec && avec.auDessus, "elle est PAR-DESSUS l'icône : c'est elle qu'on touche au centre du rond");
  ok(avec && avec.couvre && avec.cover, "elle remplit le rond entier, recadrée sans être déformée");
  ok(avec && avec.coupe, "le rond la coupe en cercle (" + (avec && avec.largeur) + " px)");
  ok(avec && avec.icone, "l'icône reste dessous, prête à reparaître");
  ok(cassee && cassee.photo === null && cassee.icone,
    "une photo qui ne vient pas s'efface : l'icône et sa couleur restent");
  ok(sans && sans.photo === null && sans.icone, "sans photo, le rond d'avant");
  ok(!(await deborde(page)), "rien ne déborde à " + L + " px");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  if (L === 390) {
    await page.screenshot({ path: (process.env.CAPTURES || "/tmp") + "/categories-photos-accueil.png",
      clip: await page.evaluate(() => {
        const r = document.querySelector(".cat-ronds").getBoundingClientRect();
        return { x: 0, y: Math.max(0, r.top + scrollY - 40), width: innerWidth, height: r.height + 60 };
      }) }).catch(() => {});
  }
  await ctx.close();
}

titre("L'écran « Catégories » : la même photo, la même règle");
{
  const { page, ctx, erreurs } = await ouvrirClient(360, { route: "#/categories" });
  const ronds = await lireRonds(page, ".cat-ligne .cat-rond-couleur");
  ok(ronds.length === 8, "huit lignes, chacune sa pastille (" + ronds.length + ")");
  const [avec, cassee, sans] = ronds;
  ok(avec && avec.chargee && avec.auDessus && avec.couvre && avec.coupe,
    "la photo remplit la pastille ronde, par-dessus l'icône");
  ok(cassee && cassee.photo === null && cassee.icone, "la photo absente du stockage laisse l'icône");
  ok(sans && sans.photo === null && sans.icone, "sans photo, l'icône sur sa couleur");
  ok(!(await deborde(page)), "rien ne déborde");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("Une base qui n'a pas encore la colonne");
{
  const vieilles = CAT.map(({ image, ...reste }) => reste);
  const { page, ctx, erreurs } = await ouvrirClient(390, { categories: vieilles });
  const ronds = await lireRonds(page, ".cat-rond-da");
  ok(ronds.length === 8 && ronds.every((r) => r.photo === null && r.icone),
    "les huit ronds d'avant, chacun son icône");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("Le chemin est échappé, même si la base le laissait passer");
{
  const piege = CAT.map((c, i) => i === 0
    ? { ...c, image: 'enseigne/categories/x.jpg" onload="window.__pris=1' } : c);
  const { page, ctx } = await ouvrirClient(390, { categories: piege });
  const ronds = await lireRonds(page, ".cat-rond-da");
  ok(ronds[0] && ronds[0].attributs.every((a) => a !== "onload"),
    "aucun attribut ne s'ajoute à l'image (" + (ronds[0] ? ronds[0].attributs.join(", ") : "—") + ")");
  ok(await page.evaluate(() => window.__pris === undefined), "et rien ne s'exécute");
  await ctx.close();
}

/* ================= DANS L'ADMIN ================= */

const MOI = "11111111-1111-1111-1111-111111111111";
const CAT_ADMIN = () => [
  { id: "cat_mode", nom: "Mode & Vêtements", icone: "tshirt", couleur: "#D81B60",
    image: "enseigne/categories/cat_photo0.jpg", en_avant: true, ordre: 1, sous_categories: [] },
  { id: "cat_tech", nom: "High-Tech", icone: "portable", couleur: "#0B5CF5",
    image: "enseigne/categories/cat_cassee1.jpg", en_avant: true, ordre: 2, sous_categories: [] },
  { id: "cat_maison", nom: "Maison & Jardin", icone: "maison", couleur: "#0F9D58",
    image: "", en_avant: false, ordre: 3, sous_categories: [] },
];

async function ouvrirAdmin({ role = "superadministrateur", refuser = false } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 900 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((moi) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: b64({ alg: "HS256" }) + "." + b64({ sub: moi }) + ".s",
      refresh_token: "r", expire_a: Date.now() + 3600000, email: "enseigne@bizzoo.bj" }));
  }, MOI);

  const categories = CAT_ADMIN();
  const envois = [];
  envois.refuser = refuser;
  const ecritures = [];
  await brancherStockage(page, envois);
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const url = new URL(req.url());
    const c = url.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (req.method() !== "GET") {
      let corps = null;
      try { corps = JSON.parse(req.postData() || "null"); } catch (_) { corps = req.postData(); }
      ecritures.push({ quand: envois.length, methode: req.method(), table: c, requete: url.search, corps });
      return d([]);
    }
    if (c.startsWith("profils")) return d([{ id: MOI, email: "enseigne@bizzoo.bj", role, actif: true,
      peut_modifier_produits: true, boutique_id: role === "superadministrateur" ? null : "bou_mode" }]);
    if (c.startsWith("categories")) {
      const id = (url.searchParams.get("id") || "").replace(/^eq\./, "");
      return d(id ? categories.filter((x) => x.id === id) : categories);
    }
    if (c.startsWith("boutiques")) return d([{ id: "bou_mode", nom: "Chic Cotonou", categorie_id: "cat_mode",
      icone: "magasin", couleur: "#0B5CF5", devise: "FCFA", indicatif: "229", actif: true, ordre: 1 }]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1500);
  await page.evaluate(() => { location.hash = "#/categories"; });
  await page.waitForTimeout(1500);
  return { page, ctx, erreurs, envois, ecritures };
}

const modifier = async (page, id) => {
  await page.click('[data-modifier="' + id + '"]');
  await page.waitForSelector("#cat-photo", { timeout: 4000 });
};
const enregistrer = async (page) => {
  await page.click("#cat-enregistrer");
  await page.waitForTimeout(1600);
};
const patchDe = (ecritures, id) => ecritures.filter((e) =>
  e.methode === "PATCH" && e.table === "categories" && e.requete.includes("eq." + id));
const journal = (ecritures) => ecritures.filter((e) => e.table === "journal")
  .map((e) => (e.corps && e.corps.libelle) || "");

titre("Admin : la liste montre la photo, et l'icône en secours");
{
  const { page, ctx, erreurs } = await ouvrirAdmin();
  const p = await lireRonds(page, ".cat-bloc .cat-pastille");
  ok(p.length === 3, "trois catégories (" + p.length + ")");
  ok(p[0] && p[0].chargee && p[0].auDessus && p[0].couvre && p[0].coupe,
    "la pastille de « Mode » montre sa photo, ronde, par-dessus l'icône");
  ok(p[1] && p[1].photo === null && p[1].icone, "celle qui ne se charge pas s'efface : l'icône reste");
  ok(p[2] && p[2].photo === null && p[2].icone, "« Maison », sans photo, garde son icône");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("Admin : poser une photo sur une catégorie qui n'en a pas");
{
  const { page, ctx, erreurs, envois, ecritures } = await ouvrirAdmin();
  await modifier(page, "cat_maison");
  const champ = await page.evaluate(() => {
    const zone = document.querySelector("#cat-photo").closest(".champ");
    return { label: zone.querySelector("label").textContent,
      ajouter: !!zone.querySelector(".photo-ajout input[type=file]") };
  });
  ok(/Photo du rond \(facultative\)/.test(champ.label) && champ.ajouter,
    "la fiche offre « Photo du rond (facultative) », à ajouter");
  await page.setInputFiles("#cat-photo-fichier", { name: "maison.png", mimeType: "image/png", buffer: png(40, 120, 60, 900) });
  await page.waitForSelector(".cat-photo-boite img", { timeout: 4000 });
  const apercu = await page.evaluate(() => {
    const img = document.querySelector(".cat-photo-boite img");
    return { rond: getComputedStyle(img).borderRadius, croix: !!document.querySelector("#cat-photo-retirer") };
  });
  ok(apercu.rond === "50%" && apercu.croix, "l'aperçu est rond, comme chez le client, avec sa croix");
  await enregistrer(page);
  const depots = envois.filter((e) => e.methode === "POST");
  const patch = patchDe(ecritures, "cat_maison")[0];
  ok(depots.length === 1, "une photo part au stockage (" + depots.length + ")");
  const d = depots[0] || {};
  ok(CHEMIN_PERMIS.test(d.chemin || ""), "dans « enseigne/categories/ », sous un nom que la base accepte (" + d.chemin + ")");
  ok(d.type === "image/jpeg" && d.jpeg, "en JPEG, recompressée par l'application");
  /* La photo choisie fait 900 px de côté : il n'en part que 480, de
     quoi remplir le plus grand rond sur l'écran le plus fin. */
  const t = d.corps ? tailleJpeg(d.corps) : null;
  ok(t && t.largeur === 480 && t.hauteur === 480,
    "réduite à 480 px (" + (t ? t.largeur + " × " + t.hauteur : "illisible") + ")");
  ok(patch && patch.corps && patch.corps.image === d.chemin, "la ligne désigne ce fichier-là");
  ok(patch && patch.quand >= 1, "le fichier est parti AVANT la ligne");
  ok(!envois.some((e) => e.methode === "DELETE"), "rien n'est effacé du stockage");
  ok(journal(ecritures).some((l) => /photo ajoutée/.test(l)), "le journal le dit : « photo ajoutée »");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("Admin : retirer la photo");
{
  const { page, ctx, envois, ecritures } = await ouvrirAdmin();
  await modifier(page, "cat_mode");
  const avant = await page.evaluate(() => (document.querySelector(".cat-photo-boite img") || {}).src || "");
  ok(/enseigne\/categories\/cat_photo0\.jpg$/.test(avant), "la fiche montre la photo en place");
  await page.click("#cat-photo-retirer");
  ok(await page.evaluate(() => !!document.querySelector("#cat-photo .photo-ajout")),
    "la croix la retire de la fiche : on peut en ajouter une autre");
  await enregistrer(page);
  const patch = patchDe(ecritures, "cat_mode")[0];
  ok(patch && patch.corps && patch.corps.image === "", "la ligne est vidée : le rond retrouve son icône");
  ok(!envois.length, "rien ne part au stockage, et rien n'en est effacé — annuler la remettra");
  ok(journal(ecritures).some((l) => /photo retirée/.test(l)), "le journal le dit : « photo retirée »");
  await ctx.close();
}

titre("Admin : remplacer la photo");
{
  const { page, ctx, envois, ecritures } = await ouvrirAdmin();
  await modifier(page, "cat_mode");
  await page.click("#cat-photo-retirer");
  await page.setInputFiles("#cat-photo-fichier", { name: "mode.png", mimeType: "image/png", buffer: png(30, 30, 200) });
  await page.waitForSelector(".cat-photo-boite img", { timeout: 4000 });
  await enregistrer(page);
  const depots = envois.filter((e) => e.methode === "POST");
  const patch = patchDe(ecritures, "cat_mode")[0];
  ok(depots.length === 1 && CHEMIN_PERMIS.test(depots[0].chemin), "la nouvelle part dans le bon dossier");
  ok(patch && patch.corps && patch.corps.image === (depots[0] || {}).chemin &&
     patch.corps.image !== "enseigne/categories/cat_photo0.jpg",
    "la ligne désigne la nouvelle — un nouveau nom : aucun téléphone ne garde l'ancienne en cache");
  ok(!envois.some((e) => e.methode === "DELETE"),
    "l'ancienne reste au stockage : annuler depuis le journal doit la retrouver");
  ok(journal(ecritures).some((l) => /photo changée/.test(l)), "le journal le dit : « photo changée »");
  await ctx.close();
}

titre("Admin : renommer sans toucher à la photo");
{
  const { page, ctx, envois, ecritures } = await ouvrirAdmin();
  await modifier(page, "cat_mode");
  await page.fill("#cat-nom", "Mode");
  await enregistrer(page);
  const patch = patchDe(ecritures, "cat_mode")[0];
  ok(patch && patch.corps && patch.corps.nom === "Mode", "le nouveau nom part");
  ok(patch && patch.corps && !("image" in patch.corps),
    "la colonne de la photo n'est pas écrite : elle n'a pas bougé");
  ok(!envois.length, "rien ne part au stockage");
  ok(!journal(ecritures).some((l) => /photo/.test(l)), "et le journal ne parle pas de photo");
  await ctx.close();
}

titre("Admin : une nouvelle catégorie, avec sa photo");
{
  const { page, ctx, envois, ecritures } = await ouvrirAdmin();
  await page.click("#cat-ajouter");
  await page.waitForSelector("#cat-photo", { timeout: 4000 });
  await page.fill("#cat-nom", "Beauté");
  await page.setInputFiles("#cat-photo-fichier", { name: "beaute.png", mimeType: "image/png", buffer: png(200, 90, 150) });
  await page.waitForSelector(".cat-photo-boite img", { timeout: 4000 });
  await enregistrer(page);
  const depots = envois.filter((e) => e.methode === "POST");
  const post = ecritures.find((e) => e.methode === "POST" && e.table === "categories");
  ok(post && post.corps && post.corps.nom === "Beauté" && post.corps.image === (depots[0] || {}).chemin &&
     CHEMIN_PERMIS.test(post.corps.image || ""), "la catégorie naît avec sa photo (" + (post && post.corps && post.corps.image) + ")");
  ok(post && !("boutique_id" in post.corps), "et n'appartient à aucune boutique");
  await ctx.close();
}

titre("Admin : un double appui n'envoie qu'une photo");
{
  const { page, ctx, envois } = await ouvrirAdmin();
  await modifier(page, "cat_maison");
  await page.setInputFiles("#cat-photo-fichier", { name: "maison.png", mimeType: "image/png", buffer: png(40, 120, 60) });
  await page.waitForSelector(".cat-photo-boite img", { timeout: 4000 });
  /* Deux appuis dans la même seconde, pendant que la photo part. */
  await page.evaluate(() => { const b = document.querySelector("#cat-enregistrer"); b.click(); b.click(); });
  await page.waitForTimeout(1800);
  const depots = envois.filter((e) => e.methode === "POST");
  ok(depots.length === 1, "une seule photo au stockage (" + depots.length + ")");
  await ctx.close();
}

titre("Admin : un envoi refusé n'écrit rien");
{
  const { page, ctx, envois, ecritures } = await ouvrirAdmin({ refuser: true });
  await modifier(page, "cat_maison");
  await page.setInputFiles("#cat-photo-fichier", { name: "maison.png", mimeType: "image/png", buffer: png(40, 120, 60) });
  await page.waitForSelector(".cat-photo-boite img", { timeout: 4000 });
  await enregistrer(page);
  const toast = await page.evaluate(() => (document.querySelector("#toasts .toast") || {}).textContent || "");
  ok(envois.filter((e) => e.methode === "POST").length === 1, "l'envoi a été tenté");
  ok(!patchDe(ecritures, "cat_maison").length, "aucune ligne n'est écrite : rien ne désigne une photo absente");
  ok(/refusé/.test(toast), "on le dit (« " + toast.slice(0, 60) + "… »)");
  ok(await page.evaluate(() => {
    const b = document.querySelector("#cat-enregistrer");
    return !!b && !b.disabled && !document.querySelector("#feuille").hidden;
  }), "la fiche reste ouverte, le bouton de nouveau utilisable");
  await ctx.close();
}

titre("Admin : une boutique voit la photo de son secteur, sans la changer");
{
  const { page, ctx, erreurs } = await ouvrirAdmin({ role: "administrateur" });
  const p = await lireRonds(page, ".cat-bloc .cat-pastille");
  ok(p.length === 1 && p[0].chargee && p[0].auDessus, "la pastille de son secteur montre la photo");
  ok(await page.evaluate(() => !document.querySelector("[data-modifier], #cat-ajouter")),
    "et rien pour la modifier");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs
  ? "\n\x1b[31m" + echecs + " constat(s) en échec\x1b[0m"
  : "\n\x1b[32mLa photo des catégories tient ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
