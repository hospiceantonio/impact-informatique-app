/* =========================================================
   Un appui, un envoi — et aucune photo effacée sous un autre produit
   =========================================================
   LE DÉFAUT QU'ON DÉFEND ICI. Le bilan de la base en ligne a trouvé
   deux produits EN DOUBLE, créés à 1,9 et 6,4 secondes d'écart, avec
   la même référence et la MÊME PHOTO : deux appuis sur « Ajouter le
   produit » pendant que la photo partait. Le contrôle de la référence
   ne les arrêtait pas — chaque envoi le passait avant que l'autre
   n'écrive. Et la photo étant partagée, en retirer une de la première
   fiche l'aurait effacée du stockage sous les yeux de la seconde.

   Ce que le banc prouve :

     1. UN DOUBLE APPUI NE CRÉE QU'UN PRODUIT, et n'envoie qu'une photo ;
        le bouton reste grisé pendant l'envoi ;
     2. UN REFUS REND LE BOUTON, avec un message : on peut corriger et
        réessayer, sans quitter l'écran ;
     3. RETIRER UNE PHOTO QU'UN AUTRE PRODUIT MONTRE ne l'efface pas du
        stockage ; celle qui n'est qu'à cette fiche, si. Même règle pour
        la vidéo ;
     4. AU MOINDRE DOUTE, RIEN N'EST EFFACÉ : la vérification échoue, le
        produit s'enregistre, aucun fichier ne part ;
     5. LA QUESTION POSÉE À LA BASE EST BIEN FORMÉE : la liste entre
        guillemets, l'autre produit exclu, rien d'autre ;
     6. SUPPRIMER UN PRODUIT : un refus se dit, le bouton revient ;
     7. METTRE EN AVANT : un double appui ne bascule qu'une fois ;
     8. RÉGLAGES D'UNE BOUTIQUE : un double appui ne dépose qu'UNE
        demande de validation ;
     9. CODES PROMO : un double appui n'écrit qu'une fois.

   CE QUE LE BANC REGARDE : ce qui PART vers la base et le stockage.

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-envoi-unique.mjs
   ========================================================= */
import { deflateSync, crc32 } from "node:zlib";

let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-envoi-unique.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

/* Une vraie image, que l'admin puisse décoder puis recompresser. */
function png(r, g, b, cote = 96) {
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
const ROUGE = png(214, 40, 40);

const MOI = "33333333-3333-3333-3333-333333333333";
const BOU = { id: "bou_jouet", nom: "JouJoutheque", secteur: "Jouets", categorie_id: "cat_jeux",
  icone: "magasin", couleur: "#0B5CF5", devise: "FCFA", indicatif: "229", actif: true, ordre: 1,
  taux_marge: 10, taux_revendeur: 5, revendeur_mode: "bizzoo", description: "", adresse: "Cotonou",
  tel: "0197000000", whatsapp: "0197000000", horaires: "", photos: [], telephones: [], adresses: [] };
const CATEGORIES = [{ id: "cat_jeux", nom: "Jeux & Jouets", icone: "jouet", couleur: "#F59E0B",
  image: "", en_avant: true, ordre: 1, sous_categories: [
    { id: "sc_puzzle", categorie_id: "cat_jeux", nom: "Puzzles", ordre: 1 },
    { id: "sc_eveil", categorie_id: "cat_jeux", nom: "Éveil", ordre: 2 },
  ] }];
const il = (min) => new Date(Date.now() - min * 60000).toISOString();

/* Deux fiches JUMELLES, comme en ligne : même photo, créées à deux
   secondes d'écart. Et une troisième, seule avec sa vidéo. */
const PRODUITS = () => [
  { id: "prod_a", code: "100220", nom: "Simulated cash", reference: "IMP-0152", prix: 12100,
    categorie_id: "cat_jeux", sous_categorie_id: "sc_eveil", stock: 3, disponible: true,
    images: ["pho_partagee.jpg", "pho_propre.jpg"], video: "vid_partagee.mp4",
    boutique_id: "bou_jouet", en_avant: false, ordre_avant: 0, cree_le: il(60), modifie_le: il(60),
    produits_prive: [{ prix_grossiste: 11000, taux_marge: null, taux_revendeur: null }] },
  { id: "prod_b", code: "100221", nom: "Simulated cash", reference: "IMP-0152", prix: 12100,
    categorie_id: "cat_jeux", sous_categorie_id: "sc_eveil", stock: 3, disponible: true,
    images: ["pho_partagee.jpg"], video: "vid_partagee.mp4",
    boutique_id: "bou_jouet", en_avant: false, ordre_avant: 0, cree_le: il(59), modifie_le: il(59),
    produits_prive: [{ prix_grossiste: 11000, taux_marge: null, taux_revendeur: null }] },
  { id: "prod_c", code: "100250", nom: "Puzzle", reference: "IMP-0180", prix: 3850,
    categorie_id: "cat_jeux", sous_categorie_id: "sc_puzzle", stock: 1, disponible: true,
    images: ["pho_puzzle.jpg"], video: "vid_seule.mp4",
    boutique_id: "bou_jouet", en_avant: false, ordre_avant: 0, cree_le: il(30), modifie_le: il(30),
    produits_prive: [{ prix_grossiste: 3500, taux_marge: null, taux_revendeur: null }] },
];

/* Ce que PostgREST ferait d'un filtre « ov » ou « in » : on le lit ici
   comme lui, guillemets compris — une liste mal formée ne trouverait
   rien, et le banc le verrait. */
const liste = (brut, ouvrant, fermant) => {
  if (!brut.startsWith(ouvrant) || !brut.endsWith(fermant)) return null;
  return brut.slice(1, -1).split(",").map((v) => v.trim().replace(/^"(.*)"$/, "$1"));
};

async function ouvrir({ role = "administrateur", hash = "#/produits", options = {} } = {}) {
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
      refresh_token: "r", expire_a: Date.now() + 3600000, email: "chef@joujou.bj" }));
  }, MOI);

  const produits = PRODUITS();
  const ecritures = [];
  const stockage = [];
  const questions = [];

  await page.route("**/storage/v1/object/**", async (route) => {
    const req = route.request();
    const url = new URL(req.url());
    if (url.pathname.includes("/object/public/")) {
      return route.fulfill({ status: 200, body: ROUGE, headers: { "Content-Type": "image/png" } });
    }
    let corps = null;
    try { corps = JSON.parse(req.postData() || "null"); } catch (_) { corps = null; }
    stockage.push({ methode: req.method(),
      chemin: decodeURIComponent(url.pathname.replace(/^.*\/storage\/v1\/object\/produits\/?/, "")), corps });
    /* Un envoi lent : c'est pendant ce temps qu'un second appui partait. */
    if (req.method() === "POST") await new Promise((r) => setTimeout(r, 600));
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
      ecritures.push({ methode, table: c, requete: url.search, corps });
      if (c === "produits" && methode === "POST") {
        await new Promise((r) => setTimeout(r, 400));
        if (options.refuserProduit) {
          return d({ message: "Le rayon choisi n'existe plus." }, 400);
        }
        const ligne = { ...corps, code: "100300", produits_prive: [] };
        produits.push(ligne);
        return d([ligne]);
      }
      if (c.startsWith("produits") && methode === "PATCH") {
        await new Promise((r) => setTimeout(r, 300));
        const id = (p.get("id") || "").replace(/^eq\./, "");
        const i = produits.findIndex((x) => x.id === id);
        if (i >= 0) produits[i] = { ...produits[i], ...corps };
        return d(i >= 0 ? [produits[i]] : []);
      }
      if (c.startsWith("produits") && methode === "DELETE") {
        await new Promise((r) => setTimeout(r, 300));
        if (options.refuserSuppression) {
          return d({ message: "permission denied for table produits" }, 403);
        }
        return d([]);
      }
      if (c === "rpc/enregistrer_code") {
        await new Promise((r) => setTimeout(r, 400));
        return d("RENTREE10");
      }
      if (c === "demandes") await new Promise((r) => setTimeout(r, 400));
      return d([]);
    }

    if (c.startsWith("profils")) return d([{ id: MOI, email: "chef@joujou.bj", role, actif: true,
      peut_modifier_produits: true, boutique_id: role === "superadministrateur" ? null : "bou_jouet" }]);
    if (c.startsWith("boutiques")) return d([BOU]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    if (c.startsWith("categories")) return d(CATEGORIES);
    if (c.startsWith("produits")) {
      /* La question qui décide d'un effacement. */
      if (p.has("images") || p.has("video")) {
        questions.push(url.search);
        if (options.verificationEnPanne) return d({ message: "upstream timeout" }, 504);
        const sauf = (p.get("id") || "").replace(/^neq\./, "");
        const ov = p.has("images") ? liste((p.get("images") || "").replace(/^ov\./, ""), "{", "}") : null;
        const dans = p.has("video") ? liste((p.get("video") || "").replace(/^in\./, ""), "(", ")") : null;
        const trouves = produits.filter((x) => x.id !== sauf &&
          ((ov && (x.images || []).some((i) => ov.includes(i))) || (dans && dans.includes(x.video))));
        return d(trouves.map((x) => (p.has("images") ? { images: x.images } : { video: x.video })));
      }
      if (p.get("select") === "reference") return d(produits.map((x) => ({ reference: x.reference })));
      const id = (p.get("id") || "").replace(/^eq\./, "");
      if (id) return d(produits.filter((x) => x.id === id));
      return d(produits);
    }
    if (c.startsWith("rpc/codes_promo_liste") || c.startsWith("codes_promo")) return d([]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1500);
  await page.evaluate((h) => { location.hash = h; }, hash);
  await page.waitForTimeout(1500);
  return { page, ctx, erreurs, ecritures, stockage, questions, produits };
}

const toast = (page) => page.evaluate(() =>
  [...document.querySelectorAll("#toasts .toast")].map((t) => t.textContent).join(" | "));
const doubleAppui = (page, selecteur) => page.evaluate((s) => {
  const b = document.querySelector(s);
  b.click(); b.click();
}, selecteur);
const effacements = (stockage) => stockage.filter((e) => e.methode === "DELETE")
  .flatMap((e) => (e.corps && e.corps.prefixes) || []);

/* ================= Le produit ================= */

titre("Un double appui sur « Ajouter le produit » ne crée qu'un produit");
{
  const { page, ctx, erreurs, ecritures, stockage } = await ouvrir({ hash: "#/produit/nouveau" });
  await page.waitForSelector("#p-enregistrer", { timeout: 5000 });
  await page.fill("#p-nom", "Early éducation device");
  await page.fill("#p-grossiste", "6000");
  await page.selectOption("#p-souscategorie", "sc_eveil");
  await page.setInputFiles("#photo-fichier", { name: "jouet.png", mimeType: "image/png", buffer: png(40, 120, 200) });
  await page.waitForSelector("#photos-zone .photo-boite img", { timeout: 4000 });
  await doubleAppui(page, "#p-enregistrer");
  await page.waitForTimeout(150);
  const pendant = await page.evaluate(() => {
    const b = document.querySelector("#p-enregistrer");
    return b ? b.disabled : null;
  });
  ok(pendant === true, "pendant l'envoi, le bouton est grisé");
  await page.waitForTimeout(2500);
  const creations = ecritures.filter((e) => e.methode === "POST" && e.table === "produits");
  const photos = stockage.filter((e) => e.methode === "POST");
  ok(creations.length === 1, "un seul produit créé (" + creations.length + ")");
  ok(photos.length === 1, "une seule photo au stockage (" + photos.length + ")");
  ok(creations[0] && photos[0] && creations[0].corps.images[0] === photos[0].chemin,
    "le produit désigne la photo envoyée");
  ok(await page.evaluate(() => /^#\/produit\/prod_/.test(location.hash)),
    "après l'envoi, on est sur la fiche du produit créé");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("Un refus rend le bouton, avec un message");
{
  const { page, ctx, ecritures } = await ouvrir({ hash: "#/produit/nouveau",
    options: { refuserProduit: true } });
  await page.waitForSelector("#p-enregistrer", { timeout: 5000 });
  await page.fill("#p-nom", "Puzzle 1000 pièces");
  await page.fill("#p-grossiste", "3500");
  await page.selectOption("#p-souscategorie", "sc_puzzle");
  await page.click("#p-enregistrer");
  await page.waitForTimeout(1500);
  const t = await toast(page);
  ok(/rayon choisi n'existe plus/.test(t), "le refus se dit (« " + t.slice(0, 60) + " »)");
  ok(await page.evaluate(() => {
    const b = document.querySelector("#p-enregistrer");
    return !!b && !b.disabled && location.hash === "#/produit/nouveau";
  }), "on reste sur le formulaire, le bouton de nouveau utilisable");
  ok(ecritures.filter((e) => e.methode === "POST" && e.table === "produits").length === 1,
    "un seul essai est parti");
  await ctx.close();
}

titre("Retirer une photo partagée avec un autre produit ne l'efface pas");
{
  const { page, ctx, erreurs, stockage, questions, ecritures } = await ouvrir({ hash: "#/produit/prod_a/modifier" });
  await page.waitForSelector("#p-enregistrer", { timeout: 5000 });
  /* Les deux photos retirées, et la vidéo avec. */
  while (await page.$("#photos-zone [data-retirer]")) {
    await page.click("#photos-zone [data-retirer]");
  }
  await page.click("[data-video-retirer]");
  /* LES JUMELLES EN LIGNE PORTENT LA MÊME RÉFÉRENCE : l'application
     refuse d'enregistrer l'une tant qu'on ne l'a pas changée. C'est ce
     que la boutique rencontrera d'abord. */
  await page.click("#p-enregistrer");
  await page.waitForTimeout(1500);
  const refus = await toast(page);
  ok(/IMP-0152.*déjà utilisée/.test(refus) && !ecritures.some((e) => e.methode === "PATCH"),
    "tant que la référence est celle de la jumelle, rien ne s'écrit (« " + refus.slice(0, 60) + "… »)");
  ok(!stockage.some((e) => e.methode === "DELETE") && !questions.length,
    "et rien ne s'efface : le refus arrive avant");
  await page.fill("#p-reference", "IMP-0153");
  await page.click("#p-enregistrer");
  await page.waitForTimeout(2000);
  const efface = effacements(stockage);
  ok(efface.includes("pho_propre.jpg"), "celle qui n'était qu'à cette fiche est effacée");
  ok(!efface.includes("pho_partagee.jpg"), "celle que l'autre fiche montre reste au stockage");
  ok(!efface.includes("vid_partagee.mp4"), "la vidéo partagée aussi");
  const patch = ecritures.find((e) => e.methode === "PATCH" && e.table === "produits");
  ok(patch && patch.corps.images.length === 0 && patch.corps.video === "",
    "la fiche, elle, ne les désigne plus");
  const q = questions.join(" ");
  ok(questions.length === 2 && q.includes("id=neq.prod_a"),
    "deux questions à la base, qui écartent la fiche elle-même (" + questions.length + ")");
  ok(questions.some((s) => decodeURIComponent(s).includes('images=ov.{"pho_partagee.jpg","pho_propre.jpg","vid_partagee.mp4"}')),
    "la liste des photos part entre guillemets, dans un tableau");
  ok(questions.some((s) => decodeURIComponent(s).includes('video=in.("pho_partagee.jpg","pho_propre.jpg","vid_partagee.mp4")')),
    "et la même liste pour la vidéo");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("Une vidéo qui n'est qu'à cette fiche part bien");
{
  const { page, ctx, stockage } = await ouvrir({ hash: "#/produit/prod_c/modifier" });
  await page.waitForSelector("#p-enregistrer", { timeout: 5000 });
  await page.click("[data-video-retirer]");
  await page.click("#p-enregistrer");
  await page.waitForTimeout(2000);
  const efface = effacements(stockage);
  ok(efface.length === 1 && efface[0] === "vid_seule.mp4", "seule sa vidéo est effacée (" + efface.join() + ")");
  await ctx.close();
}

titre("La vérification échoue : rien n'est effacé, le produit s'enregistre");
{
  const { page, ctx, stockage, ecritures } = await ouvrir({ hash: "#/produit/prod_a/modifier",
    options: { verificationEnPanne: true } });
  await page.waitForSelector("#p-enregistrer", { timeout: 5000 });
  await page.click('#photos-zone [data-retirer="1"]');
  await page.fill("#p-reference", "IMP-0153");
  await page.click("#p-enregistrer");
  await page.waitForTimeout(2000);
  ok(!stockage.some((e) => e.methode === "DELETE"), "aucun effacement ne part");
  const patch = ecritures.find((e) => e.methode === "PATCH" && e.table === "produits");
  ok(patch && patch.corps.images.join() === "pho_partagee.jpg",
    "la modification est enregistrée quand même : un fichier de trop se rattrape");
  ok(await page.evaluate(() => location.hash === "#/produit/prod_a"), "on revient sur la fiche");
  await ctx.close();
}

titre("Garder toutes ses photos n'interroge personne");
{
  const { page, ctx, stockage, questions } = await ouvrir({ hash: "#/produit/prod_a/modifier" });
  await page.waitForSelector("#p-enregistrer", { timeout: 5000 });
  await page.fill("#p-nom", "Simulated cash (billets)");
  await page.fill("#p-reference", "IMP-0153");
  await page.click("#p-enregistrer");
  await page.waitForTimeout(2000);
  ok(!questions.length && !stockage.some((e) => e.methode === "DELETE"),
    "rien à effacer : ni question, ni effacement");
  await ctx.close();
}

titre("Supprimer un produit : un refus se dit, le bouton revient");
{
  const { page, ctx } = await ouvrir({ hash: "#/produit/prod_b/modifier",
    options: { refuserSuppression: true } });
  await page.waitForSelector("#p-supprimer", { timeout: 5000 });
  await page.click("#p-supprimer");
  await page.waitForTimeout(400);
  /* Le bouton de confirmation de la feuille « Supprimer ce produit ? ». */
  await page.click("[data-role=ok]");
  await page.waitForTimeout(1500);
  const t = await toast(page);
  ok(/permission denied|refus|droit/i.test(t), "le refus se dit (« " + t.slice(0, 70) + " »)");
  ok(await page.evaluate(() => {
    const b = document.querySelector("#p-supprimer");
    return !!b && !b.disabled && /\/modifier$/.test(location.hash);
  }), "on reste sur la fiche, le bouton de nouveau utilisable");
  await ctx.close();
}

titre("Mettre en avant : un double appui ne bascule qu'une fois");
{
  const { page, ctx, ecritures } = await ouvrir({ hash: "#/produit/prod_c" });
  await page.waitForSelector("#p-basculer-avant", { timeout: 5000 });
  await doubleAppui(page, "#p-basculer-avant");
  await page.waitForTimeout(2000);
  const bascules = ecritures.filter((e) => e.methode === "PATCH" && e.table === "produits");
  ok(bascules.length === 1 && bascules[0].corps.en_avant === true,
    "une seule écriture, et c'est la bonne (" + bascules.length + ")");
  await ctx.close();
}

/* ================= Les réglages de la boutique ================= */

titre("Réglages : un double appui ne dépose qu'une demande");
{
  const { page, ctx, erreurs, ecritures } = await ouvrir({ hash: "#/reglages" });
  await page.waitForSelector("#r-enregistrer", { timeout: 5000 });
  await page.fill("#r-nom", "JouJouthèque Cotonou");
  await doubleAppui(page, "#r-enregistrer");
  await page.waitForTimeout(150);
  const pendant = await page.evaluate(() => document.querySelector("#r-enregistrer").disabled);
  ok(pendant === true, "pendant l'envoi, le bouton est grisé");
  await page.waitForTimeout(2000);
  const demandes = ecritures.filter((e) => e.methode === "POST" && e.table === "demandes");
  ok(demandes.length === 1, "une seule demande pour le superadmin (" + demandes.length + ")");
  ok(demandes[0] && demandes[0].corps.apres && demandes[0].corps.apres.nom === "JouJouthèque Cotonou",
    "elle porte le nouveau nom");
  ok(await page.evaluate(() => { const b = document.querySelector("#r-enregistrer"); return !!b && !b.disabled; }),
    "le bouton revient ensuite : l'écran reste ouvert");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("Réglages : les autres boutons, un envoi chacun");
{
  const { page, ctx, ecritures } = await ouvrir({ hash: "#/reglages" });
  await page.waitForSelector("#rs-enregistrer", { timeout: 5000 });
  await page.fill("#rs-facebook", "joujoutheque");
  await doubleAppui(page, "#rs-enregistrer");
  await page.waitForTimeout(1500);
  const reseaux = ecritures.filter((e) => e.methode === "PATCH" && e.table.startsWith("boutiques"));
  ok(reseaux.length === 1, "réseaux sociaux : une écriture (" + reseaux.length + ")");

  await page.fill("#loc-lat", "6.3654");
  await page.fill("#loc-lng", "2.4183");
  await doubleAppui(page, "#loc-enregistrer");
  await page.waitForTimeout(1500);
  const positions = ecritures.filter((e) => e.methode === "POST" && e.table === "demandes");
  ok(positions.length === 1, "position : une demande (" + positions.length + ")");
  await ctx.close();
}

/* ================= Les codes promo ================= */

titre("Codes promo : un double appui n'écrit qu'une fois");
{
  const { page, ctx, erreurs, ecritures } = await ouvrir({ role: "superadministrateur", hash: "#/codes" });
  await page.click("#cd-nouveau");
  await page.waitForSelector("#cd-enregistrer", { timeout: 5000 });
  await page.fill("#cd-code", "RENTREE10");
  await page.fill("#cd-valeur", "10");
  await doubleAppui(page, "#cd-enregistrer");
  await page.waitForTimeout(1800);
  const rpc = ecritures.filter((e) => e.table === "rpc/enregistrer_code");
  ok(rpc.length === 1, "un seul enregistrement (" + rpc.length + ")");
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " constat(s) en échec." : "\nTous les constats sont bons.");
process.exit(echecs ? 1 : 0);
