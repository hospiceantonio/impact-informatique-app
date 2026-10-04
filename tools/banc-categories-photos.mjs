/* =========================================================
   Les icônes et la photo d'une catégorie
   =========================================================
   CE QU'ON VÉRIFIE (3.56). La tuile d'une catégorie montre l'une
   des icônes des trois planches choisies par l'enseigne — reprises
   telles quelles —, rangées dans l'application (« img/pictos/ »). L'enseigne peut poser une photo
   par-dessus depuis l'admin (Catégories → Modifier) ; elle va dans
   « enseigne/categories/ », le seul dossier que la base accepte pour
   elle.

   Ce que le banc prouve :

     1. CHEZ LE CLIENT, chaque tuile montre l'icône que la base lui
        donne, lue à côté de la page — sur l'accueil et sur l'écran
        « Catégories » ; une photo la RECOUVRE, l'icône reste dessous ;
     2. L'ICÔNE EN SECOURS : sans photo, ou si elle ne se charge pas
        (hors connexion, fichier retiré), la tuile garde son icône —
        jamais un carré d'image cassée ; une icône choisie avant la
        3.56 garde son dessin d'un trait, une icône inconnue retombe
        sur celle des rayons : jamais une tuile vide ;
     3. LES ILLUSTRATIONS EN 3D D'AVANT (« img/categories/… », que la
        base en ligne garde pour les applications installées) ne
        s'affichent plus, et ne sont même pas demandées ;
     4. RIEN NE DÉBORDE à 320 px, et une base qui n'a pas encore les
        colonnes donne l'icône des rayons, sans erreur ;
     5. LE CHEMIN EST ÉCHAPPÉ : la base refuse les guillemets, mais
        l'écran ne compte pas sur elle ;
     6. LA LISTE DE BIZZOO telle que schema.sql la sème montre
        chacune son icône ;
     7. DANS L'ADMIN, la fiche propose les trente-quatre icônes, dans
        l'ordre des catégories, et celle
        qu'on choisit part vers la base — sans réécrire ni la couleur
        ni la photo ; une illustration d'avant n'est jamais effacée en
        passant ; poser, remplacer, retirer une photo : le fichier part
        au stockage AVANT la ligne, dans le bon dossier, une seule fois
        même sur un double appui ; un envoi refusé n'écrit rien ;
     8. L'ANCIENNE PHOTO N'EST PAS EFFACÉE : annuler depuis le journal
        remet l'ancien chemin, et le fichier doit encore y être ;
     9. UNE BOUTIQUE VOIT la tuile de son secteur, sans pouvoir la
        changer ;
    10. LES DEUX APPLICATIONS ONT LES MÊMES ICÔNES, octet pour octet,
        et la même liste dans leur code.

   CE QUE LE BANC REGARDE : ce qui est à l'écran — mesuré — et ce qui
   PART vers la base et le stockage, corps compris.

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-categories-photos.mjs
   ========================================================= */
import { deflateSync, crc32 } from "node:zlib";
import { readFileSync, readdirSync } from "node:fs";

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

/* LES RÈGLES DE PUBLICATION (depuis la 3.54.1). Avant sa première
   écriture de contenu, un compte les accepte dans une fenêtre. Le banc
   les accepte comme le ferait le gérant — case cochée, « Accepter et
   publier » — sans quoi la fenêtre attendrait, aucune écriture ne
   partirait, et le banc croirait à une panne de l'écran qu'il éprouve.
   Il ne fige aucun numéro de version des règles : c'est la fenêtre
   qu'il accepte, quelle que soit la version qu'elle présente. */
const accepterLesRegles = () => {
  new MutationObserver(() => {
    const boite = document.querySelector(".conditions-ugc-boite");
    const accord = boite && boite.querySelector("[data-ugc-accord]");
    if (!accord || accord.checked) return;
    accord.checked = true;
    boite.querySelector("[data-ugc-valider]").click();
  }).observe(document, { childList: true, subtree: true });
};
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


/* LES ICÔNES DES APPLICATIONS : les fichiers du client, le fond de tuile
   attendu (« --tuile »), et la liste que chaque code tient. */
const RACINE = new URL("..", import.meta.url).pathname;
const ICONES = readdirSync(RACINE + "client/img/pictos").filter((f) => f.endsWith(".png"))
  .map((f) => f.slice(0, -4)).sort();
const FOND_TUILE = "rgb(234, 240, 247)";
const listeDuCode = (fichier) => {
  const m = readFileSync(RACINE + fichier, "utf8").match(/const PICTOS = \[([\s\S]*?)\];/);
  return m ? [...m[1].matchAll(/\[?\s*"([a-z-]+)"/g)].map((x) => x[1]).sort() : [];
};

titre("Les mêmes icônes dans les deux applications");
{
  ok(ICONES.length === 34, "trente-quatre icônes dans le client (" + ICONES.length + ")");
  const admin = readdirSync(RACINE + "admin/img/pictos").filter((f) => f.endsWith(".png")).sort();
  ok(admin.join() === ICONES.map((n) => n + ".png").join(), "les mêmes fichiers dans l'admin");
  ok(ICONES.every((n) => readFileSync(RACINE + "client/img/pictos/" + n + ".png")
      .equals(readFileSync(RACINE + "admin/img/pictos/" + n + ".png"))),
    "octet pour octet");
  for (const fichier of ["client/js/ui.js", "admin/js/ui.js", "admin/js/vues/categories.js"]) {
    ok(listeDuCode(fichier).join() === ICONES.join(),
      fichier + " connaît exactement ces trente-quatre-là");
  }
}

/* ================= CHEZ LE CLIENT ================= */

const CAT = [
  /* Une photo posée par l'enseigne, qui se charge. */
  { id: "cat_0", nom: "Mode & Vêtements", icone: "mode", image: "enseigne/categories/cat_photo0.jpg" },
  /* Une photo qui ne vient pas (fichier retiré, ou hors connexion). */
  { id: "cat_1", nom: "High-Tech", icone: "informatique", image: "enseigne/categories/cat_cassee1.jpg" },
  /* Son icône, rien d'autre. */
  { id: "cat_2", nom: "Maison & Jardin", icone: "maison-deco", image: "" },
  /* Une illustration en 3D d'avant la 3.56, gardée en base. */
  { id: "cat_3", nom: "Auto & Moto", icone: "auto-moto", image: "img/categories/voiture.jpg" },
  /* Une icône choisie avec une admin d'avant la 3.56. */
  { id: "cat_4", nom: "Catégorie d'avant", icone: "tshirt", image: "" },
  /* Une icône que personne ne sait dessiner. */
  { id: "cat_5", nom: "Inconnue", icone: "n-existe-pas", image: "" },
  /* Deux des nouvelles planches. « cadeau » est AUSSI le nom d'une icône
     d'un trait d'avant la 3.56 : c'est celle de la planche qui l'emporte. */
  { id: "cat_6", nom: "Bébé & Enfants", icone: "bebe-enfant", image: "" },
  { id: "cat_7", nom: "Cadeaux & Fêtes", icone: "cadeau", image: "" },
].map((c, i) => ({ ...c, couleur: "#0B5CF5", en_avant: true, ordre: i + 1, sous_categories: [] }));

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
       tuiles — ne se montre pas. */
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

/* Ce que montre chaque tuile : son icône (chargée, et laquelle), et la
   photo — là, chargée, par-dessus, et la recouvrant tout entière ? */
const lireTuiles = (page, selecteur) => page.evaluate((sel) => {
  return [...document.querySelectorAll(sel)].map((tuile) => {
    const r = tuile.getBoundingClientRect();
    const photo = tuile.querySelector("img[data-secours]");
    const icone = tuile.querySelector("img.picto");
    const trait = tuile.querySelector("svg.ic use");
    const style = getComputedStyle(tuile);
    const auCentre = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    const rp = photo ? photo.getBoundingClientRect() : null;
    const ri = icone ? icone.getBoundingClientRect() : null;
    return {
      photo: photo ? photo.getAttribute("src") : null,
      chargee: !!(photo && photo.complete && photo.naturalWidth > 0),
      auDessus: !!(photo && auCentre === photo),
      couvre: !!(rp && Math.abs(rp.width - r.width) < 1.5 && Math.abs(rp.height - r.height) < 1.5 &&
                 Math.abs(rp.left - r.left) < 1.5 && Math.abs(rp.top - r.top) < 1.5),
      cover: photo ? getComputedStyle(photo).objectFit === "cover" : false,
      coupe: style.overflow === "hidden" && parseFloat(style.borderTopLeftRadius) > 0,
      icone: icone ? icone.getAttribute("src") : null,
      iconeChargee: !!(icone && icone.complete && icone.naturalWidth > 0),
      iconeVisible: !!(ri && ri.width > 20 && ri.height > 20),
      trait: trait ? trait.getAttribute("href") : null,
      attributs: photo ? [...photo.attributes].map((a) => a.name) : [],
      largeur: Math.round(r.width),
      fond: style.backgroundColor,
    };
  });
}, selecteur);

const deborde = (page) => page.evaluate(() =>
  document.documentElement.scrollWidth > document.documentElement.clientWidth + 1);

/* Toutes les images demandées sous « categories/ » ou « pictos/ ». */
const demandes = (page) => page.evaluate(() => performance.getEntriesByType("resource")
  .map((e) => e.name).filter((n) => /\/(categories|pictos)\//.test(n)));

const verifierTuiles = (t, ou) => {
  const [photo, cassee, seule, illustration, avant, inconnue, bebe, cadeau] = t;
  ok(photo && /\/storage\/v1\/object\/public\/produits\/enseigne\/categories\/cat_photo0\.jpg$/
      .test(photo.photo || ""), ou + " : la photo vient du stockage public (" + (photo && photo.photo) + ")");
  ok(photo && photo.chargee && photo.auDessus && photo.couvre && photo.cover,
    ou + " : elle est chargée, PAR-DESSUS l'icône, et la recouvre entière sans être déformée");
  ok(photo && photo.coupe, ou + " : la tuile la coupe à ses coins arrondis");
  ok(photo && photo.icone === "img/pictos/mode.png" && photo.iconeChargee,
    ou + " : l'icône reste dessous, prête à reparaître");
  ok(cassee && cassee.photo === null && cassee.icone === "img/pictos/informatique.png" &&
     cassee.iconeChargee && cassee.iconeVisible,
    ou + " : une photo qui ne vient pas s'efface, et l'icône reparaît");
  ok(seule && seule.photo === null && seule.icone === "img/pictos/maison-deco.png" && seule.iconeChargee,
    ou + " : sans photo, l'icône que la base lui donne");
  ok(illustration && illustration.photo === null && illustration.icone === "img/pictos/auto-moto.png" &&
     illustration.iconeChargee,
    ou + " : une illustration en 3D d'avant ne s'affiche plus : l'icône la remplace");
  ok(avant && avant.icone === null && avant.trait === "#i-tshirt",
    ou + " : une icône choisie avant la 3.56 garde son dessin d'un trait");
  ok(inconnue && inconnue.icone === null && inconnue.trait === "#i-categories",
    ou + " : une icône inconnue retombe sur celle des rayons — jamais une tuile vide");
  ok(bebe && bebe.icone === "img/pictos/bebe-enfant.png" && bebe.iconeChargee,
    ou + " : les icônes des nouvelles planches se chargent aussi");
  ok(cadeau && cadeau.icone === "img/pictos/cadeau.png" && cadeau.iconeChargee && cadeau.trait === null,
    ou + " : « cadeau », nom d'une icône d'un trait d'avant, montre celle de la planche");
};

for (const L of [390, 320]) {
  titre("L'accueil à " + L + " px : les tuiles des catégories");
  const { page, ctx, erreurs } = await ouvrirClient(L);
  const fonds = await page.evaluate(() =>
    [...document.querySelectorAll(".cat-tuile-lien")].map((a) => getComputedStyle(a).backgroundColor));
  const t = await lireTuiles(page, ".cat-tuile");
  ok(t.length === 8, "huit tuiles sur l'accueil (" + t.length + ")");
  ok(fonds.length === 8 && fonds.every((f) => f === FOND_TUILE),
    "toutes sur le même fond bleu-gris, celui de l'image (" + fonds[0] + ")");
  verifierTuiles(t, "accueil " + L);
  const lues = await demandes(page);
  ok(!lues.some((n) => /img\/categories\//.test(n)),
    "aucune illustration d'avant n'est même demandée");
  ok(lues.filter((n) => /\/pictos\//.test(n)).every((n) => n.startsWith(BASE + "/client/img/pictos/")),
    "les icônes sont lues à côté de la page, jamais dans le seau");
  ok(!(await deborde(page)), "rien ne déborde à " + L + " px");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  if (L === 390) {
    await page.screenshot({ path: (process.env.CAPTURES || "/tmp") + "/categories-icones-accueil.png",
      clip: await page.evaluate(() => {
        const r = document.querySelector(".cat-tuiles").getBoundingClientRect();
        return { x: 0, y: Math.max(0, r.top + scrollY - 40), width: innerWidth, height: r.height + 60 };
      }) }).catch(() => {});
  }
  await ctx.close();
}

titre("L'écran « Catégories » : la même tuile, en petit");
{
  const { page, ctx, erreurs } = await ouvrirClient(360, { route: "#/categories" });
  const t = await lireTuiles(page, ".cat-ligne .cat-pastille");
  ok(t.length === 8, "huit lignes, chacune sa pastille (" + t.length + ")");
  ok(t.every((x) => x.fond === FOND_TUILE), "toutes sur le fond des tuiles (" + (t[0] && t[0].fond) + ")");
  verifierTuiles(t, "Catégories");
  ok(!(await deborde(page)), "rien ne déborde");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("Une base qui n'a pas encore les colonnes");
{
  const vieilles = CAT.map(({ image, icone, ...reste }) => reste);
  const { page, ctx, erreurs } = await ouvrirClient(390, { categories: vieilles });
  const t = await lireTuiles(page, ".cat-tuile");
  ok(t.length === 8 && t.every((x) => x.photo === null && x.trait === "#i-categories"),
    "les huit tuiles montrent l'icône des rayons");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* LA LISTE DE BIZZOO TELLE QUE LA BASE LA SÈME, lue dans schema.sql :
   c'est SA correspondance catégorie → icône qu'on éprouve, pas une
   copie qui pourrait s'en écarter. */
const SEMENCE = [...readFileSync(new URL("../supabase/schema.sql", import.meta.url), "utf8")
  .matchAll(/\('(cat_\w+)',\s*null,\s*'([^']+)',\s*'([\w-]+)',\s*'(#[0-9A-Fa-f]{6})',\s*(true|false),\s*(\d+),\s*'([^']*)'\)/g)]
  .map((m) => ({ id: m[1], nom: m[2], icone: m[3], couleur: m[4], en_avant: m[5] === "true",
    ordre: Number(m[6]), image: m[7], sous_categories: [] }));

titre("La liste de BIZZOO : chacune son icône");
{
  ok(SEMENCE.length === 29, "schema.sql sème vingt-neuf catégories (" + SEMENCE.length + ")");
  ok(SEMENCE.every((c) => ICONES.includes(c.icone) && c.image === ""),
    "chacune avec une icône de l'application, sans image");
  const { page, ctx, erreurs } = await ouvrirClient(390, { categories: SEMENCE });
  const t = await lireTuiles(page, ".cat-tuile");
  const vedettes = SEMENCE.filter((x) => x.en_avant);
  ok(t.length === vedettes.length, "les " + vedettes.length + " de l'accueil (" + t.length + ")");
  ok(t.every((x, i) => x.icone === "img/pictos/" + vedettes[i].icone + ".png" && x.iconeChargee),
    "chaque tuile porte l'icône que la base lui donne, chargée");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
  const { page: p2, ctx: c2 } = await ouvrirClient(360, { categories: SEMENCE, route: "#/categories" });
  const l = await lireTuiles(p2, ".cat-ligne .cat-pastille");
  const triees = SEMENCE.slice().sort((a, b) => a.ordre - b.ordre);
  ok(l.length === 29 && l.every((x, i) => x.icone === "img/pictos/" + triees[i].icone + ".png" && x.iconeChargee),
    "l'écran « Catégories » : les vingt-neuf, chacune son icône (" + l.length + ")");
  await p2.screenshot({ path: (process.env.CAPTURES || "/tmp") + "/categories-icones-liste.png" })
    .catch(() => {});
  await c2.close();
}

titre("Le chemin est échappé, même si la base le laissait passer");
{
  const piege = CAT.map((c, i) => i === 0
    ? { ...c, image: 'enseigne/categories/x.jpg" onload="window.__pris=1' } : c);
  const { page, ctx } = await ouvrirClient(390, { categories: piege });
  const t = await lireTuiles(page, ".cat-tuile");
  ok(t[0] && t[0].attributs.every((a) => a !== "onload"),
    "aucun attribut ne s'ajoute à la photo (" + (t[0] ? t[0].attributs.join(", ") : "—") + ")");
  ok(await page.evaluate(() => window.__pris === undefined), "et rien ne s'exécute");
  const piegeIcone = CAT.map((c, i) => i === 2 ? { ...c, icone: 'x" onload="window.__pris=2' } : c);
  const { page: p2, ctx: c2 } = await ouvrirClient(390, { categories: piegeIcone });
  const t2 = await lireTuiles(p2, ".cat-tuile");
  ok(t2[2] && t2[2].trait === "#i-categories" && await p2.evaluate(() => window.__pris === undefined),
    "une icône piégée retombe sur celle des rayons, sans rien exécuter");
  await ctx.close();
  await c2.close();
}

/* ================= DANS L'ADMIN ================= */

const MOI = "11111111-1111-1111-1111-111111111111";
const CAT_ADMIN = () => [
  { id: "cat_mode", nom: "Mode & Vêtements", icone: "mode", couleur: "#D81B60",
    image: "enseigne/categories/cat_photo0.jpg", en_avant: true, ordre: 1, sous_categories: [] },
  { id: "cat_tech", nom: "High-Tech", icone: "informatique", couleur: "#0B5CF5",
    image: "enseigne/categories/cat_cassee1.jpg", en_avant: true, ordre: 2, sous_categories: [] },
  { id: "cat_maison", nom: "Maison & Jardin", icone: "maison-deco", couleur: "#0F9D58",
    image: "", en_avant: false, ordre: 3, sous_categories: [] },
  /* Une illustration d'avant la 3.56, gardée pour les applications installées. */
  { id: "cat_auto", nom: "Auto & Moto", icone: "auto-moto", couleur: "#001450",
    image: "img/categories/voiture.jpg", en_avant: true, ordre: 4, sous_categories: [] },
  /* Une icône choisie avec une admin d'avant la 3.56. */
  { id: "cat_vieille", nom: "Catégorie d'avant", icone: "tshirt", couleur: "#6C3FBF",
    image: "", en_avant: false, ordre: 5, sous_categories: [] },
];

async function ouvrirAdmin({ role = "superadministrateur", refuser = false } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 900 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(accepterLesRegles);
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
const choix = (page) => page.evaluate(() => {
  const boutons = [...document.querySelectorAll("#cat-icones button")];
  return {
    nombre: boutons.length,
    cles: boutons.map((b) => b.dataset.icone),
    chargees: boutons.filter((b) => { const i = b.querySelector("img.picto"); return i && i.complete && i.naturalWidth > 0; }).length,
    actives: boutons.filter((b) => b.classList.contains("actif")).map((b) => b.dataset.icone),
    noms: boutons.map((b) => b.getAttribute("aria-label")),
  };
});

titre("Admin : la liste montre l'icône, et la photo par-dessus");
{
  const { page, ctx, erreurs } = await ouvrirAdmin();
  const p = await lireTuiles(page, ".cat-bloc .cat-pastille");
  ok(p.length === 5, "cinq catégories (" + p.length + ")");
  ok(p.every((x) => x.fond === FOND_TUILE), "toutes sur le fond des tuiles du client");
  ok(p[0] && p[0].chargee && p[0].auDessus && p[0].couvre && p[0].coupe && p[0].icone === "img/pictos/mode.png",
    "la pastille de « Mode » montre sa photo par-dessus son icône");
  ok(p[1] && p[1].photo === null && p[1].icone === "img/pictos/informatique.png" && p[1].iconeChargee,
    "celle qui ne se charge pas s'efface : l'icône reste");
  ok(p[2] && p[2].photo === null && p[2].icone === "img/pictos/maison-deco.png" && p[2].iconeChargee,
    "« Maison », sans photo, montre son icône");
  ok(p[3] && p[3].photo === null && p[3].icone === "img/pictos/auto-moto.png",
    "« Auto & Moto » : l'illustration d'avant ne s'affiche pas, l'icône si");
  ok(p[4] && p[4].icone === null && p[4].trait === "#i-tshirt",
    "une icône d'avant garde son dessin d'un trait");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("Admin : choisir l'une des trente-quatre icônes");
{
  const { page, ctx, erreurs, envois, ecritures } = await ouvrirAdmin();
  await modifier(page, "cat_auto");
  await page.waitForTimeout(600);
  const g = await choix(page);
  ok(g.nombre === 34 && g.cles.slice().sort().join() === ICONES.join(),
    "la fiche propose les trente-quatre icônes (" + g.nombre + ")");
  ok(g.chargees === 34, "toutes existent dans l'admin, et se chargent (" + g.chargees + ")");
  ok(g.noms.slice(0, 4).join("|") === "Informatique|Électroménager|" +
     "Énergie solaire & Électricité|Sécurité & Surveillance" && g.noms[g.noms.length - 1] === "Services",
    "dans l'ordre des catégories, sous les noms des planches : le high-tech d'abord, les services à la fin");
  ok(new Set(g.noms).size === g.noms.length && g.noms.every((n) => n && n.trim()),
    "chacune son nom, sans doublon");
  ok(g.cles.indexOf("tracteur") === g.cles.indexOf("agriculture") + 1 &&
     g.cles.indexOf("cartons") === g.cles.indexOf("grossistes") + 1,
    "le tracteur et les cartons juste après l'icône qu'ils remplacent au besoin");
  ok(g.actives.join() === "auto-moto", "celle de la catégorie est allumée (" + g.actives.join() + ")");
  ok(await page.evaluate(() => !document.querySelector("#cat-couleurs, #cat-illustrations")),
    "ni couleur ni galerie d'illustrations à choisir : les tuiles ont toutes le même fond");
  ok(await page.evaluate(() => !document.querySelector(".cat-photo-boite img") &&
      !!document.querySelector("#cat-photo .photo-ajout")),
    "l'illustration d'avant n'est pas montrée comme une photo : on peut en ajouter une");
  await page.click('#cat-icones [data-icone="services"]');
  ok((await choix(page)).actives.join() === "services", "un appui sur une autre l'allume");
  await page.evaluate(() => document.querySelector("#cat-icones").scrollIntoView({ block: "start" }));
  await page.screenshot({ path: (process.env.CAPTURES || "/tmp") + "/categories-icones-admin.png" })
    .catch(() => {});
  await enregistrer(page);
  const patch = patchDe(ecritures, "cat_auto")[0];
  ok(patch && patch.corps && patch.corps.icone === "services", "l'icône choisie part vers la base");
  ok(patch && patch.corps && !("image" in patch.corps),
    "l'illustration d'avant n'est pas effacée : les applications installées la montrent encore");
  ok(patch && patch.corps && !("couleur" in patch.corps), "la couleur n'est pas réécrite");
  ok(!envois.length, "rien ne part au stockage");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("Admin : une catégorie d'avant garde son icône");
{
  const { page, ctx, ecritures } = await ouvrirAdmin();
  await modifier(page, "cat_vieille");
  const g = await choix(page);
  ok(g.nombre === 35 && g.actives.join() === "tshirt",
    "son icône d'avant s'ajoute aux trente-quatre, allumée (" + g.nombre + ", " + g.actives.join() + ")");
  await page.fill("#cat-nom", "Catégorie renommée");
  await enregistrer(page);
  const patch = patchDe(ecritures, "cat_vieille")[0];
  ok(patch && patch.corps && patch.corps.icone === "tshirt" && patch.corps.nom === "Catégorie renommée",
    "renommée, elle garde son icône : rien ne la remplace en silence");
  await ctx.close();
}

titre("Admin : une nouvelle catégorie, avec son icône");
{
  const { page, ctx, envois, ecritures } = await ouvrirAdmin();
  await page.click("#cat-ajouter");
  await page.waitForSelector("#cat-icones button", { timeout: 4000 });
  ok((await choix(page)).actives.length === 0, "aucune n'est allumée d'avance");
  await page.fill("#cat-nom", "Animalerie");
  await page.click('#cat-icones [data-icone="animaux"]');
  await enregistrer(page);
  const post = ecritures.find((e) => e.methode === "POST" && e.table === "categories");
  ok(post && post.corps && post.corps.icone === "animaux" && post.corps.couleur === "#2550B7",
    "elle naît avec l'icône choisie, et le bleu de BIZZOO en couleur");
  ok(post && post.corps && !("image" in post.corps) && !envois.length, "sans photo, sans rien envoyer au stockage");
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
  ok(/Photo de la tuile \(facultative\)/.test(champ.label) && champ.ajouter,
    "la fiche offre « Photo de la tuile (facultative) », à ajouter");
  await page.setInputFiles("#cat-photo-fichier", { name: "maison.png", mimeType: "image/png", buffer: png(40, 120, 60, 900) });
  await page.waitForSelector(".cat-photo-boite img", { timeout: 4000 });
  const apercu = await page.evaluate(() => {
    const img = document.querySelector(".cat-photo-boite img");
    return { coins: getComputedStyle(img).borderRadius, croix: !!document.querySelector("#cat-photo-retirer") };
  });
  ok(apercu.coins === "26%" && apercu.croix, "l'aperçu a les coins arrondis de la tuile, avec sa croix");
  await enregistrer(page);
  const depots = envois.filter((e) => e.methode === "POST");
  const patch = patchDe(ecritures, "cat_maison")[0];
  ok(depots.length === 1, "une photo part au stockage (" + depots.length + ")");
  const d = depots[0] || {};
  ok(CHEMIN_PERMIS.test(d.chemin || ""), "dans « enseigne/categories/ », sous un nom que la base accepte (" + d.chemin + ")");
  ok(d.type === "image/jpeg" && d.jpeg, "en JPEG, recompressée par l'application");
  /* La photo choisie fait 900 px de côté : il n'en part que 480. */
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

titre("Admin : une photo par-dessus une illustration d'avant");
{
  const { page, ctx, envois, ecritures } = await ouvrirAdmin();
  await modifier(page, "cat_auto");
  await page.setInputFiles("#cat-photo-fichier", { name: "auto.png", mimeType: "image/png", buffer: png(20, 40, 160) });
  await page.waitForSelector(".cat-photo-boite img", { timeout: 4000 });
  await enregistrer(page);
  const depots = envois.filter((e) => e.methode === "POST");
  const patch = patchDe(ecritures, "cat_auto")[0];
  ok(depots.length === 1 && patch && patch.corps && patch.corps.image === depots[0].chemin,
    "la photo remplace l'illustration d'avant : toutes les applications la montrent");
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
  ok(patch && patch.corps && patch.corps.image === "", "la ligne est vidée : la tuile retrouve son icône");
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
  ok(patch && patch.corps && patch.corps.nom === "Mode" && patch.corps.icone === "mode",
    "le nouveau nom part, avec la même icône");
  ok(patch && patch.corps && !("image" in patch.corps) && !("couleur" in patch.corps),
    "ni la photo ni la couleur ne sont écrites : elles n'ont pas bougé");
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
  await page.click('#cat-icones [data-icone="beaute"]');
  await page.setInputFiles("#cat-photo-fichier", { name: "beaute.png", mimeType: "image/png", buffer: png(200, 90, 150) });
  await page.waitForSelector(".cat-photo-boite img", { timeout: 4000 });
  await enregistrer(page);
  const depots = envois.filter((e) => e.methode === "POST");
  const post = ecritures.find((e) => e.methode === "POST" && e.table === "categories");
  ok(post && post.corps && post.corps.nom === "Beauté" && post.corps.image === (depots[0] || {}).chemin &&
     CHEMIN_PERMIS.test(post.corps.image || "") && post.corps.icone === "beaute",
    "la catégorie naît avec son icône et sa photo (" + (post && post.corps && post.corps.image) + ")");
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

titre("Admin : une boutique voit la tuile de son secteur, sans la changer");
{
  const { page, ctx, erreurs } = await ouvrirAdmin({ role: "administrateur" });
  const p = await lireTuiles(page, ".cat-bloc .cat-pastille");
  ok(p.length === 1 && p[0].chargee && p[0].auDessus && p[0].icone === "img/pictos/mode.png",
    "la pastille de son secteur montre sa photo, l'icône dessous");
  ok(await page.evaluate(() => !document.querySelector("[data-modifier], #cat-ajouter")),
    "et rien pour la modifier");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs
  ? "\n\x1b[31m" + echecs + " constat(s) en échec\x1b[0m"
  : "\n\x1b[32mLes icônes et la photo des catégories tiennent ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
