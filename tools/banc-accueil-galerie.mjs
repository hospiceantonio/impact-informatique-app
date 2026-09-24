/* =========================================================
   L'accueil réordonné, et la galerie de tous les produits
   =========================================================
   CE QUE L'ENSEIGNE A DEMANDÉ, et que ce banc tient :

     1. L'ORDRE DE L'ACCUEIL : le slider en haut (sous la recherche,
        qui reste la porte d'entrée), puis HUIT catégories, l'offre du
        jour et la publicité, les boutiques partenaires, et pour finir
        « Nos produits » avec son « Voir tout » ;
     2. HUIT CATÉGORIES, même quand l'enseigne n'en a mis que quatre à
        la une : les siennes d'abord, puis celles qui ont des produits,
        puis les autres ;
     3. QUATRE BOUTIQUES PAR RANGÉE, du plus petit téléphone à
        l'ordinateur — sans que la page déborde, ni qu'un logo touche
        les bords, ni qu'un long nom rende une tuile plus haute ;
     4. LA GALERIE « Nos produits » : tout le catalogue, les derniers
        arrivés d'abord, posé par lots de vingt à mesure qu'on défile,
        photos chargées à l'approche seulement ; un bouton de secours
        là où le navigateur ne sait pas guetter le bas ;
     5. LE RETOUR D'UNE FICHE PRODUIT retombe au même endroit de la
        galerie — les cartes déjà vues sont reposées — et la galerie
        reste celle de TOUTES les boutiques ;
     6. LES POPULAIRES, quand il y a eu des ventes, se glissent avant
        « Nos produits », qui reste le dernier mot de l'accueil.

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-accueil-galerie.mjs
   ========================================================= */
import { deflateSync, crc32 } from "node:zlib";

let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-accueil-galerie.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
const CAPTURES = process.env.CAPTURES || "";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

/* Une vraie image, pour que les cartes aient une photo à charger. */
function png(r, g, b, cote = 48) {
  const morceau = (type, donnees) => {
    const t = Buffer.from(type, "ascii");
    const longueur = Buffer.alloc(4); longueur.writeUInt32BE(donnees.length);
    const somme = Buffer.alloc(4); somme.writeUInt32BE(crc32(Buffer.concat([t, donnees])) >>> 0);
    return Buffer.concat([longueur, t, donnees, somme]);
  };
  const entete = Buffer.alloc(13);
  entete.writeUInt32BE(cote, 0); entete.writeUInt32BE(cote, 4);
  entete[8] = 8; entete[9] = 2;
  const ligne = Buffer.alloc(1 + cote * 3);
  for (let x = 0; x < cote; x++) { ligne[1 + 3 * x] = r; ligne[2 + 3 * x] = g; ligne[3 + 3 * x] = b; }
  const brut = Buffer.concat(Array.from({ length: cote }, () => ligne));
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    morceau("IHDR", entete), morceau("IDAT", deflateSync(brut)), morceau("IEND", Buffer.alloc(0)),
  ]);
}
const PHOTO = png(70, 120, 200);

/* SIX BOUTIQUES : une rangée pleine de quatre, puis deux. Les noms sont
   ceux de la base en ligne, plus deux longs — c'est là qu'une tuile
   grandit ou qu'une page déborde. */
const BOUTIQUES = [
  "IMPACT INFORMATIQUE", "JouJoutheque", "CREATIS INTER", "ABC Motors",
  "LA MAISON DU MEUBLE COTONOU", "PHARMACIE",
].map((nom, i) => ({
  id: "bou_" + i, nom, secteur: "Secteur " + i, categorie_id: null, slogan: "",
  icone: "magasin", couleur: "#0B5CF5", logo: "logo_" + i + ".png", devise: "FCFA",
  indicatif: "229", actif: true, ordre: i + 1,
}));

/* QUINZE CATÉGORIES, dont QUATRE à la une — comme en ligne —, et pas
   les quatre premières : l'ordre de l'enseigne doit primer. */
const A_LA_UNE = [2, 5, 11, 13];
const CATEGORIES = Array.from({ length: 15 }, (_, i) => ({
  id: "cat_" + (i + 1), nom: "Rayon " + String(i + 1).padStart(2, "0"),
  icone: "categories", couleur: "#0B5CF5", image: "",
  en_avant: A_LA_UNE.includes(i + 1), ordre: i + 1, sous_categories: [],
}));
/* Des produits dans 2, 5, 7, 9 et 14 : les places libres iront à 7, 9
   et 14 (ils ont des produits), puis à 1 (le premier des vides). */
const RAYONS_PLEINS = ["cat_2", "cat_5", "cat_7", "cat_9", "cat_14"];
const HUIT_ATTENDUES = ["cat_2", "cat_5", "cat_11", "cat_13", "cat_7", "cat_9", "cat_14", "cat_1"];

/* SOIXANTE-CINQ PRODUITS : quatre lots de vingt, le dernier incomplet.
   Chacun arrivé à une date différente — l'ordre de la galerie se vérifie
   à la minute près. */
const NB = 65;
const t0 = Date.parse("2026-09-01T08:00:00Z");
const PRODUITS = Array.from({ length: NB }, (_, i) => ({
  id: "prod_" + String(i).padStart(3, "0"),
  code: String(100000 + i), nom: "Article " + String(i).padStart(3, "0"),
  reference: "REF-" + i, description: "",
  prix: 1000 + ((i * 37) % 50) * 500,
  ancien_prix: i === 7 ? 25000 : null,
  boutique_id: "bou_" + (i % BOUTIQUES.length),
  categorie_id: RAYONS_PLEINS[i % RAYONS_PLEINS.length], sous_categorie_id: null,
  stock: 5, disponible: true, sur_commande: false, appro_le: null, flash_fin: null,
  images: ["pho_" + i + ".png"], video: "", en_avant: false, ordre_avant: 0,
  cree_le: new Date(t0 + i * 60000).toISOString(),
  modifie_le: new Date(t0 + i * 60000).toISOString(),
}));
/* Le plus récent est le dernier créé : 064, 063, 062… */
const RECENTS = PRODUITS.slice().sort((a, b) => Date.parse(b.cree_le) - Date.parse(a.cree_le))
  .map((p) => p.id);

const SLIDES = [
  { id: 1, portee: "enseigne", image: "slide_1.png", titre: "Rentrée", ordre: 1, actif: true },
  { id: 2, portee: "enseigne", image: "slide_2.png", titre: "", ordre: 2, actif: true },
  { id: 3, portee: "publicite", image: "pub_1.png", titre: "Affiche BIZZOO", ordre: 1, actif: true },
];

async function ouvrir({ largeur = 360, hauteur = 800, hash = "#/", populaires = [],
                        sansObservateur = false } = {}) {
  const ctx = await nav.newContext({ viewport: { width: largeur, height: hauteur },
    serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((sans) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.removeItem("impact-boutique");
    /* Un navigateur qui ne sait pas guetter le bas : c'est le bouton
       « Afficher plus » qui doit prendre le relais. */
    if (sans) { try { delete window.IntersectionObserver; } catch (_) { window.IntersectionObserver = undefined; } }
  }, sansObservateur);

  const photos = [];
  await page.route("**/storage/v1/object/public/**", (r) => {
    photos.push(new URL(r.request().url()).pathname.split("/").pop());
    return r.fulfill({ status: 200, body: PHOTO, headers: { "Content-Type": "image/png" } });
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json",
    body: JSON.stringify({ external: { email: true, phone: false } }) }));
  await page.route("**/rest/v1/**", (r) => {
    const c = new URL(r.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/produits_populaires")) return d(populaires.map((id) => ({ produit_id: id })));
    if (c.startsWith("rpc/")) return d([]);
    if (c.startsWith("reglages")) return d([{ compte_obligatoire: false }]);
    if (c.startsWith("paiement")) return d([{ id: 1, actif: false }]);
    if (c.startsWith("produits")) return d(PRODUITS);
    if (c.startsWith("categories")) return d(CATEGORIES);
    if (c.startsWith("slides")) return d(SLIDES);
    if (c.startsWith("boutiques")) return d(BOUTIQUES);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", slogan: "Toutes vos boutiques",
      devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html" + hash, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1800);
  return { page, ctx, erreurs, photos };
}

const aller = async (page, hash, attente = 1300) => {
  await page.evaluate((h) => { location.hash = h; }, hash);
  await page.waitForTimeout(attente);
};
const capture = async (page, nom) => {
  if (CAPTURES) await page.screenshot({ path: CAPTURES + "/" + nom + ".png", fullPage: true });
};

/* L'ordre des blocs de l'accueil, relevé sur les enfants directs de la vue. */
const plan = (page) => page.evaluate(() => {
  const vue = document.getElementById("vue");
  const enfants = [...vue.children];
  const rang = (test) => enfants.findIndex(test);
  const titreDe = (texte) => rang((x) => x.matches(".section-titre") &&
    x.querySelector("h2") && x.querySelector("h2").textContent.trim() === texte);
  return {
    pilule: rang((x) => x.matches(".recherche-pilule")),
    slider: rang((x) => x.matches(".slider")),
    ronds: rang((x) => x.matches(".cat-ronds")),
    offre: rang((x) => x.matches(".offre-jour")),
    titrePub: titreDe("Publicité"),
    pub: rang((x) => x.matches(".pub-rangee")),
    titreBoutiques: titreDe("Nos boutiques partenaires"),
    tuiles: rang((x) => x.matches(".bou-tuiles")),
    titrePopulaires: titreDe("Produits populaires"),
    titreProduits: titreDe("Nos produits"),
    grille: rang((x) => x.matches(".p-grille")),
    voirTout: rang((x) => x.id === "accueil-voir-tout"),
    dernier: enfants.length - 1,
    enfants: enfants.length,
  };
});

/* Combien de tuiles par rangée : on relève le « top » de chacune. */
const tuilesParRangee = (page) => page.evaluate(() => {
  const par = new Map();
  for (const c of document.querySelectorAll(".bou-tuiles .bou-tuile")) {
    const y = Math.round(c.getBoundingClientRect().top);
    par.set(y, (par.get(y) || 0) + 1);
  }
  return [...par.entries()].sort((a, b) => a[0] - b[0]).map((x) => x[1]);
});

const cartes = (page) => page.evaluate(() =>
  [...document.querySelectorAll("#galerie .p-carte")].map((a) =>
    a.getAttribute("href").replace("#/produit/", "")));

/* ================================================================== */
titre("1. L'accueil dans l'ordre demandé");
{
  const { page, ctx, erreurs } = await ouvrir();
  await capture(page, "accueil-360");
  const m = await plan(page);
  ok(m.pilule === 0, "la recherche reste la porte d'entrée, tout en haut");
  ok(m.slider === m.pilule + 1, "le slider vient aussitôt : premier bloc de contenu");
  ok(m.ronds === m.slider + 1, "les catégories juste sous le slider");
  ok(m.offre > m.ronds && m.titrePub > m.offre && m.pub === m.titrePub + 1,
    "puis l'offre du jour, puis la publicité");
  ok(m.titreBoutiques > m.pub && m.tuiles === m.titreBoutiques + 1,
    "les boutiques partenaires viennent APRÈS l'offre du jour et la publicité");
  ok(m.titreProduits > m.tuiles && m.grille === m.titreProduits + 1 && m.voirTout === m.grille + 1,
    "puis « Nos produits », ses cartes et son bouton");
  ok(m.voirTout === m.dernier, "« Voir tout » ferme l'accueil : rien après lui");
  ok(m.titrePopulaires === -1, "sans ventes, pas de rangée « Produits populaires »");

  const ronds = await page.evaluate(() =>
    [...document.querySelectorAll(".cat-ronds .cat-rond-lien")].map((a) =>
      a.getAttribute("href").replace("#/categorie/", "")));
  ok(ronds.length === 8, "HUIT catégories, pas quatre (" + ronds.length + ")");
  ok(ronds.join(",") === HUIT_ATTENDUES.join(","),
    "les quatre de l'enseigne d'abord, puis celles qui ont des produits, puis les autres (" +
    ronds.join(", ") + ")");
  const rangees = await page.evaluate(() => {
    const par = new Map();
    for (const c of document.querySelectorAll(".cat-ronds .cat-rond-lien")) {
      const y = Math.round(c.getBoundingClientRect().top);
      par.set(y, (par.get(y) || 0) + 1);
    }
    return [...par.values()];
  });
  ok(rangees.join("+") === "4+4", "deux rangées de quatre (" + rangees.join("+") + ")");

  /* La seule remise du décor : 25 000 barrés sur l'article 007. */
  const remise = Math.round((PRODUITS[7].ancien_prix - PRODUITS[7].prix) / PRODUITS[7].ancien_prix * 100);
  const offre = await page.$eval(".offre-jour", (e) => e.textContent).catch(() => "");
  ok(new RegExp("Jusqu'à\\s*−" + remise + "\\s*%").test(offre),
    "l'offre du jour annonce la vraie remise (−" + remise + " %)");

  const produits = await page.evaluate(() => ({
    ids: [...document.querySelectorAll("#vue > .p-grille .p-carte")].map((a) =>
      a.getAttribute("href").replace("#/produit/", "")),
    boutiques: [...document.querySelectorAll("#vue > .p-grille .p-carte-boutique")].length,
    bouton: (document.querySelector("#accueil-voir-tout") || {}).textContent || "",
    lien: (document.querySelector("#accueil-voir-tout") || { getAttribute: () => "" }).getAttribute("href"),
    lienTitre: [...document.querySelectorAll(".section-titre")]
      .filter((t) => /Nos produits/.test(t.textContent))
      .map((t) => (t.querySelector(".section-lien") || { getAttribute: () => "" }).getAttribute("href"))[0],
  }));
  ok(produits.ids.length === 8 && produits.ids.join(",") === RECENTS.slice(0, 8).join(","),
    "« Nos produits » : les huit derniers arrivés, du plus récent au plus ancien");
  ok(produits.boutiques === 8, "chaque carte dit de quelle boutique elle vient");
  ok(/Voir tout — 65 produits/.test(produits.bouton) && produits.lien === "#/nos-produits" &&
     produits.lienTitre === "#/nos-produits",
    "le bouton « Voir tout — 65 produits » (et le lien du titre) ouvrent la galerie");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("1 bis. Les populaires se glissent avant « Nos produits »");
{
  const { page, ctx, erreurs } = await ouvrir({ populaires: ["prod_010", "prod_020", "prod_030"] });
  await page.waitForTimeout(600);
  const m = await plan(page);
  ok(m.titrePopulaires > m.tuiles && m.titreProduits === m.titrePopulaires + 2,
    "« Produits populaires » arrive entre les boutiques et « Nos produits »");
  ok(m.voirTout === m.dernier, "et « Voir tout » reste le dernier mot de l'accueil");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("2. Quatre boutiques par rangée, à toutes les largeurs");
for (const L of [320, 360, 390, 430, 768, 1280]) {
  const { page, ctx } = await ouvrir({ largeur: L });
  const r = await tuilesParRangee(page);
  ok(r.join("+") === "4+2", "à " + L + " px : " + r.join("+") + " (six boutiques)");
  if (L === 320 || L === 360) {
    await capture(page, "accueil-" + L);
    const m = await page.evaluate(() => {
      const tuiles = [...document.querySelectorAll(".bou-tuiles .bou-tuile")];
      const g = document.querySelector(".bou-tuiles").getBoundingClientRect();
      const hauteurs = new Set();
      let deborde = 0, serre = 0;
      for (const t of tuiles) {
        const r = t.getBoundingClientRect();
        if (r.left < g.left - 1 || r.right > g.right + 1) deborde++;
        const logo = t.querySelector(".bou-logo").getBoundingClientRect();
        if (logo.width > r.width - 16 || Math.abs(logo.width - logo.height) > 1) serre++;
        hauteurs.add(Math.round(r.height));
      }
      return { deborde, serre, hauteurs: [...hauteurs],
        page: document.documentElement.scrollWidth,
        logo: Math.round(tuiles[0].querySelector(".bou-logo").getBoundingClientRect().width),
        tuile: Math.round(tuiles[0].getBoundingClientRect().width) };
    });
    ok(m.deborde === 0 && m.page <= L, "rien ne déborde, la page ne défile pas de côté (" +
      m.page + " px)");
    ok(m.serre === 0, "chaque logo reste carré et garde de l'air (" + m.logo + " px dans " +
      m.tuile + " px)");
    ok(m.hauteurs.length === 1, "toutes les tuiles ont la même hauteur, long nom ou pas (" +
      m.hauteurs.join(", ") + ")");
    /* « JouJoutheque » se coupait en « JouJoutheq / ue » : un nom d'un
       seul mot tient sur UNE ligne, quitte à finir par « … ». */
    const lignes = await page.evaluate(() => {
      const tuile = [...document.querySelectorAll(".bou-tuile")]
        .find((a) => /JouJoutheque/.test(a.textContent));
      const r = document.createRange();
      r.selectNodeContents(tuile.querySelector(".bou-tuile-nom"));
      return new Set([...r.getClientRects()].map((x) => Math.round(x.top))).size;
    });
    ok(lignes === 1, "un nom d'un seul mot ne se coupe pas en deux (" + lignes + " ligne)");
  }
  await ctx.close();
}

/* ================================================================== */
titre("3. « Voir tout » : la galerie se remplit en défilant");
{
  const { page, ctx, erreurs, photos } = await ouvrir();
  const accueil = await page.evaluate(() =>
    [...document.querySelectorAll("#vue > .p-grille .p-carte")].map((a) =>
      a.getAttribute("href").replace("#/produit/", "")));
  await page.click("#accueil-voir-tout");
  await page.waitForTimeout(1500);
  ok(await page.evaluate(() => location.hash) === "#/nos-produits", "le bouton ouvre #/nos-produits");
  const entete = await page.evaluate(() => ({
    titre: (document.querySelector("#topbar h1, .topbar h1") || {}).textContent || "",
    sous: (document.querySelector("#topbar .sous, .topbar .sous") || {}).textContent || "",
  }));
  ok(/Nos produits/.test(entete.titre) && /65 produits dans toutes les boutiques/.test(entete.sous),
    "« Nos produits — 65 produits dans toutes les boutiques »");
  await capture(page, "galerie-360");

  let ids = await cartes(page);
  ok(ids.length === 20, "un premier lot de vingt cartes (" + ids.length + ")");
  ok(ids.slice(0, 8).join(",") === accueil.join(","),
    "les huit premières sont celles de l'accueil, dans le même ordre");
  ok(ids.join(",") === RECENTS.slice(0, 20).join(","), "les derniers arrivés d'abord");
  const vues = new Set(photos.filter((f) => /^pho_/.test(f)));
  ok(vues.size <= 20 && vues.size < NB,
    "les photos ne se chargent qu'à l'approche : " + vues.size + " sur " + NB);
  ok(await page.evaluate(() =>
    [...document.querySelectorAll("#galerie img")].every((i) => i.getAttribute("loading") === "lazy")),
    "chaque photo de la galerie est en « lazy »");

  for (const attendu of [40, 60, 65]) {
    await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
    await page.waitForTimeout(700);
    ids = await cartes(page);
    ok(ids.length === attendu, "au bas de la page, le lot suivant arrive tout seul : " + ids.length);
  }
  ok(new Set(ids).size === NB && ids.join(",") === RECENTS.join(","),
    "les 65 produits, chacun une fois, dans l'ordre");
  const fin = await page.evaluate(() => ({
    texte: (document.querySelector(".galerie-fin") || {}).textContent || "",
    bouton: !!document.querySelector("#galerie-plus"),
  }));
  ok(/Vous avez tout vu : 65 produits/.test(fin.texte) && !fin.bouton,
    "au bout : « Vous avez tout vu », et plus de bouton");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("3 bis. Sans guetteur de défilement : le bouton de secours");
{
  const { page, ctx, erreurs } = await ouvrir({ hash: "#/nos-produits", sansObservateur: true });
  ok(await page.evaluate(() => typeof window.IntersectionObserver) !== "function",
    "(le navigateur de ce décor ne sait pas guetter le bas)");
  ok((await cartes(page)).length === 20, "vingt cartes d'abord");
  await page.click("#galerie-plus");
  await page.waitForTimeout(300);
  ok((await cartes(page)).length === 40, "« Afficher plus » en pose vingt de plus");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("3 ter. Sur un très grand écran, la galerie se remplit sans attendre le pouce");
{
  /* UN LOT NE SUFFIT PAS À REMPLIR L'ÉCRAN, ni même deux : le guetteur
     n'est prévenu qu'au CHANGEMENT (« il entre en vue ») ; resté en vue
     après un lot, il se tairait, et la galerie attendrait un défilement
     qui ne vient pas — l'écran est déjà plus grand qu'elle. */
  const { page, ctx } = await ouvrir({ largeur: 1280, hauteur: 4000, hash: "#/nos-produits" });
  await page.waitForTimeout(1800);
  const m = await page.evaluate(() => {
    const suite = document.querySelector("#galerie-suite");
    return {
      n: document.querySelectorAll("#galerie .p-carte").length,
      haut: suite ? Math.round(suite.getBoundingClientRect().top) : 0,
      ecran: window.innerHeight,
    };
  });
  ok(m.n > 40, "plus de deux lots sont venus d'eux-mêmes (" + m.n + ")");
  ok(m.n === NB || m.haut > m.ecran + 900 - 2,
    "et la galerie ne s'arrête que lorsque le bas est vraiment loin (" + m.haut + " px, écran " +
    m.ecran + " px) — ou qu'il n'y a plus rien");
  await ctx.close();
}

/* ================================================================== */
titre("4. Le retour d'une fiche produit retombe au même endroit");
/* D'ABORD SANS GUETTEUR : la galerie ne peut alors grandir qu'au bouton.
   Si le retour ne reposait pas d'emblée les cartes déjà vues, rien ne
   viendrait les rajouter, et la hauteur mémorisée n'existerait plus —
   c'est ce qui isole le mécanisme. Ensuite, le cas ordinaire. */
for (const sansObservateur of [true, false]) {
  const { page, ctx, erreurs } = await ouvrir({ hash: "#/nos-produits", sansObservateur });
  for (let i = 0; i < 2; i++) {
    if (sansObservateur) {
      await page.click("#galerie-plus");
      await page.waitForTimeout(300);
    } else {
      await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
      await page.waitForTimeout(700);
    }
  }
  const avant = (await cartes(page)).length;
  const cible = RECENTS[44];
  await page.evaluate((id) => {
    document.querySelector('#galerie .p-carte[href="#/produit/' + id + '"]')
      .scrollIntoView({ block: "center" });
  }, cible);
  await page.waitForTimeout(400);
  const hauteur = await page.evaluate(() => window.scrollY);
  await page.click('#galerie .p-carte[href="#/produit/' + cible + '"] .p-carte-nom');
  await page.waitForTimeout(1300);
  ok(await page.evaluate(() => location.hash) === "#/produit/" + cible, "la fiche du 45ᵉ produit s'ouvre");
  await page.goBack();
  await page.waitForTimeout(1600);
  const apres = await page.evaluate(() => ({
    hash: location.hash, y: window.scrollY,
    n: document.querySelectorAll("#galerie .p-carte").length,
    boutiques: new Set([...document.querySelectorAll("#galerie .p-carte-boutique")]
      .map((b) => b.textContent.trim())).size,
    /* Le produit ouvert a fait entrer dans SA boutique ; la galerie la
       quitte au retour — sans quoi la recherche ouverte depuis elle ne
       porterait plus que sur cette boutique-là. */
    chez: Catalogue.boutiqueChoisie() ? Catalogue.boutiqueChoisie().id : "",
  }));
  const quoi = sansObservateur ? " (sans guetteur)" : "";
  ok(apres.hash === "#/nos-produits" && apres.n >= avant,
    "retour dans la galerie, les " + avant + " cartes déjà vues reposées (" + apres.n + ")" + quoi);
  ok(Math.abs(apres.y - hauteur) <= 60, "à la même hauteur (" + hauteur + " → " + apres.y + " px)" + quoi);
  ok(apres.boutiques === BOUTIQUES.length && apres.chez === "",
    "et c'est toujours la galerie de TOUTES les boutiques — pas celle du produit ouvert" + quoi);
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("5. Le catalogue d'une boutique se remplit de la même façon");
{
  const { page, ctx, erreurs } = await ouvrir({ hash: "#/boutique/bou_0" });
  await aller(page, "#/produits", 1400);
  const m = await page.evaluate(() => {
    const liens = [...document.querySelectorAll("#galerie .p-carte")];
    return {
      n: liens.length,
      etiquettes: document.querySelectorAll("#galerie .p-carte-boutique").length,
      titre: (document.querySelector("#topbar h1, .topbar h1") || {}).textContent || "",
    };
  });
  const tous = PRODUITS.filter((p) => p.boutique_id === "bou_0");
  ok(m.n === Math.min(20, tous.length) && m.etiquettes === 0 && /Produits/.test(m.titre),
    "la boutique visitée seule, par lot (" + m.n + " sur " + tous.length + "), sans étiquette de boutique");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " constat(s) en échec." : "\nTous les constats sont bons.");
process.exit(echecs ? 1 : 0);
