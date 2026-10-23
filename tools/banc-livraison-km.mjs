/* =========================================================
   La livraison au kilomètre, et les gains des livreurs (3.64.0)
   =========================================================
   La base calcule, fige et crédite (supabase/tests/99zzz…-livraison-
   au-km.sql). Ce banc regarde les ÉCRANS :

     1. LE PANIER : « Livraison à moto, selon la distance, dès 1 000 » ;
        le tarif du véhicule ; un produit en tricycle fait tout passer en
        tricycle ;
     2. LA FICHE PRODUIT dit le véhicule et son tarif ;
     3. LE FORMULAIRE : sans position, pas de commande ; « Utiliser ma
        position » donne la distance et les frais ; l'acompte compte les
        frais ; un lien de carte collé déplace la livraison ;
     4. LA COMMANDE part avec la destination ; le reçu dit « moto, 13,4 km » ;
     5. UNE BASE SANS POINT BIZZOO : rien ne change ;
     6. LE SUPERADMINISTRATEUR règle le point et les tarifs ;
     7. LE LIVREUR : sa course dit le véhicule, la distance, son gain ;
        « Mes gains » : solde, numéro, demande de reversement ;
     8. LE SUPERADMINISTRATEUR tranche la demande d'un livreur.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-livraison-km.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const F = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ") + " FCFA";
const plat = (s) => String(s || "").replace(/[  ]/g, " ").replace(/\s+/g, " ").trim();
/* Sans aucun blanc : les colonnes d'une ligne se touchent dans le texte. */
const serre = (s) => String(s || "").replace(/\s+/g, "");
const contient = (liste, attendu) => liste.some((l) => serre(l) === serre(attendu));
const texte = (page, sel) => page.evaluate((s) => {
  const el = document.querySelector(s);
  return el ? el.textContent : "";
}, sel).then(plat);

/* Une tuile de carte : un carré blanc, sans réseau. */
const TUILE = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=", "base64");
const sansTuiles = (page) => page.route("https://tile.openstreetmap.org/**",
  (r) => r.fulfill({ status: 200, contentType: "image/png", body: TUILE }));

/* Le point BIZZOO, et les réglages au kilomètre. */
const POINT = { latitude: 6.3654, longitude: 2.4183 };
const REGLAGES_KM = { livraison_latitude: POINT.latitude, livraison_longitude: POINT.longitude,
  livraison_adresse: "Siège BIZZOO", livraison_rayon_km: 10, livraison_coef: 1.3,
  moto_forfait: 1000, moto_prix_km: 100, tricycle_forfait: 4000, tricycle_prix_km: 500, taux_livreur: 80 };
/* 13,4 km par la route, plein nord : 4 km entamés au-delà des 10. */
const LOIN = { latitude: 6.458099, longitude: 2.4183 };
/* 7 km : le forfait. */
const PRES = { latitude: 6.413825, longitude: 2.4183 };

/* ================================================================
   L'application des clients
   ================================================================ */
const BOUTIQUES = [
  { id: "bou_a", nom: "Alpha", categorie_id: "cat_hightech", icone: "magasin", couleur: "#0047D9",
    devise: "FCFA", indicatif: "229", whatsapp: "97000001", actif: true, ordre: 1,
    mode_paiement: "acompte", taux_acompte: 10, frais_livraison: 1500 },
];
const PRODUITS = [
  { id: "prod_1", boutique_id: "bou_a", nom: "Ordinateur", code: "0001", prix: 300000,
    categorie_id: "cat_hightech", sous_categorie_id: "sc_x", stock: 5, disponible: true, images: [],
    vehicule: "moto", cree_le: "2026-09-01T08:00:00Z", modifie_le: "2026-09-01T08:00:00Z" },
  { id: "prod_frigo", boutique_id: "bou_a", nom: "Réfrigérateur", code: "0002", prix: 200000,
    categorie_id: "cat_hightech", sous_categorie_id: "sc_x", stock: 5, disponible: true, images: [],
    vehicule: "tricycle", cree_le: "2026-09-01T08:00:00Z", modifie_le: "2026-09-01T08:00:00Z" },
];
const CLIENT = { nom: "Koffi", tel: "0197000000", indicatif: "229", adresse: "Godomey" };

async function ouvrirClient({ hash = "#/panier", panier = [{ produitId: "prod_1", quantite: 1 }],
                              km = true, destination = null, geo = LOIN } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1400 }, serviceWorkers: "block",
    permissions: ["geolocation"], geolocation: geo });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    try {
      localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
      localStorage.setItem("bizzoo-panier", JSON.stringify(a.panier));
      localStorage.setItem("bizzoo-coordonnees", JSON.stringify(a.client));
      if (a.destination) localStorage.setItem("bizzoo-destination", JSON.stringify(a.destination));
    } catch (_) { /* une page hors de l'application */ }
  }, { panier, client: CLIENT, destination });
  await sansTuiles(page);
  const serveur = { creations: [] };
  await page.route("**/functions/v1/feexpay", (route) => {
    const corps = JSON.parse(route.request().postData() || "{}");
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
      return d({ id: "cmd_km", numero: "BZ-000101", total: 301400, devise: "FCFA", etat: "a_payer",
        code_promo: "", remise: 0, frais_livraison: 1400,
        livraison: { vehicule: "moto", distance_km: 13.4, km_factures: 4, frais: 1400 },
        taux_acompte: 11, acompte: 31400, reste: 270000,
        boutiques: [{ id: "bou_a", nom: "Alpha", whatsapp: "97000001", indicatif: "229",
          montant: 300000, a_encaisser: 270000,
          lignes: [{ nom: "Ordinateur", code: "0001", prix: 300000, quantite: 1 }] }] });
    }
    if (c.startsWith("rpc/suivre_commande")) return d({ etat: "a_payer", remarque: "" });
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("reglages")) return d([{ compte_obligatoire: false }]);
    if (c.startsWith("paiement")) {
      return d([{ id: 1, actif: true, fournisseur: "feexpay", cle_publique: "", bac_a_sable: false,
        taux_acompte: 10, frais_livraison: 1000,
        ...(km ? REGLAGES_KM : { livraison_latitude: null, livraison_longitude: null }) }]);
    }
    if (c.startsWith("produits")) return d(PRODUITS);
    if (c.startsWith("boutiques")) return d(BOUTIQUES);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/client/index.html" + hash, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1800);
  return { page, ctx, erreurs, serveur };
}

const recap = (page) => page.evaluate(() => [...document.querySelectorAll(".pa-recap .pa-recap-ligne")]
  .map((l) => l.textContent)).then((l) => l.map(plat));
const lignesTotal = (page) => page.evaluate(() =>
  [...document.querySelectorAll("#co-lignes-total .pa-total-ligne")].map((l) => l.textContent))
  .then((l) => l.map(plat));

/* ------------------------------------------------------------------ */
titre("1. Le panier : « dès 1 000 », selon la distance ; le tricycle l'emporte");
{
  const { page, ctx, erreurs } = await ouvrirClient({ hash: "#/panier" });
  const r = await recap(page);
  ok(contient(r, "Livraison à moto selon la distance dès " + F(1000)),
    "« Livraison à moto — selon la distance — dès 1 000 FCFA » (" + r.join(" | ") + ")");
  ok(contient(r, "Total hors livraison " + F(300000)), "le total, hors livraison tant qu'on ne sait pas où");
  ok(/Livraison à moto : 1 000 FCFA jusqu'à 10 km, 100 FCFA par km au-delà\./.test(await texte(page, "#pa-tarif")),
    "le tarif de la moto est écrit");
  ok(!r.some((l) => /Frais de livraison/.test(l)), "plus de frais de la boutique (1 500)");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  const { page, ctx } = await ouvrirClient({ hash: "#/panier",
    panier: [{ produitId: "prod_1", quantite: 1 }, { produitId: "prod_frigo", quantite: 1 }] });
  const r = await recap(page);
  ok(contient(r, "Livraison en tricycle selon la distance dès " + F(4000)),
    "un réfrigérateur dans le panier : tricycle, dès 4 000 FCFA");
  ok(/Livraison en tricycle : 4 000 FCFA jusqu'à 10 km, 500 FCFA par km au-delà\./.test(await texte(page, "#pa-tarif")),
    "« Livraison en tricycle : 4 000 FCFA jusqu'à 10 km, 500 FCFA par km au-delà. »");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("2. La fiche produit dit le véhicule");
{
  const { page, ctx, erreurs } = await ouvrirClient({ hash: "#/produit/prod_frigo" });
  ok(/Livraison en tricycle : 4 000 FCFA jusqu'à 10 km, 500 FCFA par km au-delà/.test(await texte(page, ".fiche-livraison")),
    "le réfrigérateur : « Livraison en tricycle : 4 000 FCFA jusqu'à 10 km… »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  const { page, ctx } = await ouvrirClient({ hash: "#/produit/prod_1" });
  ok(/Livraison à moto : 1 000 FCFA jusqu'à 10 km, 100 FCFA par km au-delà/.test(await texte(page, ".fiche-livraison")),
    "l'ordinateur : à moto");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("3. Le formulaire : la position d'abord, puis les frais");
{
  const { page, ctx, serveur, erreurs } = await ouvrirClient({ hash: "#/commande" });
  ok(/Indiquez où livrer/.test(await texte(page, "#co-ou-etat")), "« Où livrer ? » attend une position");
  await page.click('#co-operateurs [data-reseau="MTN"]');
  await page.click("#co-payer");
  await page.waitForTimeout(600);
  ok(serveur.creations.length === 0, "sans position, « Payer » ne crée aucune commande");
  ok(/Utiliser ma position/.test(await texte(page, "#toasts")), "et le dit : « touchez Utiliser ma position »");

  await page.click("#co-ma-position");
  await page.waitForFunction(() => /km/.test((document.querySelector("#co-ou-etat") || {}).textContent || ""),
    null, { timeout: 8000 }).catch(() => {});
  ok(/Livraison à moto · 13,4 km · 1 400 FCFA/.test(await texte(page, "#co-ou-etat")),
    "ma position : « Livraison à moto · 13,4 km · 1 400 FCFA » (" + await texte(page, "#co-ou-etat") + ")");
  ok(await page.$("#co-carte .leaflet-marker-icon") !== null, "la carte s'ouvre, l'épingle posée");
  let lignes = await lignesTotal(page);
  ok(contient(lignes, "Livraison à moto 13,4 km " + F(1400)), "le total compte 1 400 de livraison (" + lignes.join(" | ") + ")");
  ok(lignes.some((l) => l.startsWith("À payer maintenant") && l.endsWith(F(31400))),
    "en ligne : 30 000 d'acompte + 1 400 de frais = 31 400");
  ok(contient(lignes, "Reste à payer à la livraison " + F(270000)), "à la porte : 270 000, sans frais");
  ok(/31 400 FCFA/.test(await texte(page, "#co-payer")), "le bouton demande 31 400 FCFA");

  /* Livré ailleurs : un lien de carte collé. */
  await page.fill("#co-ou-lien", "https://www.google.com/maps/@" + PRES.latitude + "," + PRES.longitude + ",15z");
  await page.dispatchEvent("#co-ou-lien", "change");
  await page.waitForTimeout(400);
  ok(/Livraison à moto · 7 km · 1 000 FCFA/.test(await texte(page, "#co-ou-etat")),
    "un lien de carte collé : 7 km, le forfait (" + await texte(page, "#co-ou-etat") + ")");

  /* Retour à ma position, puis on paie. */
  await page.click("#co-ma-position");
  await page.waitForFunction(() => /13,4/.test((document.querySelector("#co-ou-etat") || {}).textContent || ""),
    null, { timeout: 8000 }).catch(() => {});
  await page.click("#co-payer");
  await page.waitForFunction(() => location.hash === "#/commande/cmd_km", null, { timeout: 8000 }).catch(() => {});
  await page.waitForTimeout(800);
  const corps = serveur.creations[0] || {};
  ok(corps.destination && corps.destination.latitude === LOIN.latitude && corps.destination.longitude === LOIN.longitude,
    "« creer_commande » part avec la destination (" + JSON.stringify(corps.destination) + ")");
  ok(/dont 1 400 FCFA de frais de livraison \(moto, 13,4 km\)/.test(await texte(page, ".re-entete")),
    "le reçu : « dont 1 400 FCFA de frais de livraison (moto, 13,4 km) »");
  const gardee = await page.evaluate(() => JSON.parse(localStorage.getItem("bizzoo-commandes") || "[]")[0] || {});
  ok(gardee.livraison && gardee.livraison.vehicule === "moto", "le téléphone garde le véhicule et la distance");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  /* La position gardée de la dernière fois : rien à refaire. */
  const { page, ctx } = await ouvrirClient({ hash: "#/commande", destination: PRES });
  ok(/Livraison à moto · 7 km · 1 000 FCFA/.test(await texte(page, "#co-ou-etat")),
    "la position de la dernière commande est reprise : 7 km, 1 000");
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("4. Sans point BIZZOO : comme avant");
{
  const { page, ctx, erreurs } = await ouvrirClient({ hash: "#/panier", km: false });
  const r = await recap(page);
  ok(contient(r, "Frais de livraison " + F(1500)), "les frais de la boutique, 1 500 (" + r.join(" | ") + ")");
  ok(!(await page.$("#pa-tarif")), "aucun tarif au kilomètre");
  await ctx.close();
  const b = await ouvrirClient({ hash: "#/commande", km: false });
  ok(!(await b.page.$("#co-ou")), "pas de « Où livrer ? »");
  ok(!erreurs.length && !b.erreurs.length, "aucune erreur JavaScript");
  await b.ctx.close();
}

/* ================================================================
   L'application admin
   ================================================================ */
const SUPER = "11111111-1111-1111-1111-111111111111";
const PORTEUR = "cccccccc-1111-1111-1111-111111111111";
const PROFILS = {
  [SUPER]: { id: SUPER, email: "chef@bizzoo.bj", role: "superadministrateur", actif: true,
    peut_modifier_produits: true, boutique_id: null },
  [PORTEUR]: { id: PORTEUR, email: "lamine@bizzoo.bj", nom: "Lamine", role: "livreur", actif: true,
    peut_modifier_produits: true, boutique_id: null, vehicule: "moto" },
};

async function ouvrirAdmin({ moi, hash, rpc = {}, paiement = null }) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2200 }, serviceWorkers: "block" });
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
  await sansTuiles(page);
  const serveur = { ecritures: [], appels: [] };
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x, statut = 200) => route.fulfill({ status: statut, contentType: "application/json",
      body: JSON.stringify(x) });
    const corps = (() => { try { return req.postDataJSON(); } catch (_) { return null; } })();
    if (c.startsWith("rpc/")) {
      const fn = c.slice(4);
      serveur.appels.push({ fn, corps });
      if (rpc[fn] !== undefined) return d(typeof rpc[fn] === "function" ? rpc[fn](corps) : rpc[fn]);
      return d(null);
    }
    if (req.method() !== "GET") {
      serveur.ecritures.push({ methode: req.method(), chemin: c, corps });
      return route.fulfill({ status: 204, body: "" });
    }
    if (c.startsWith("profils")) {
      const id = (u.searchParams.get("id") || "").replace(/^eq\./, "");
      return d(id ? [PROFILS[id]].filter(Boolean) : Object.values(PROFILS));
    }
    if (c.startsWith("positions_livreurs")) return d([{ profil_id: PORTEUR, latitude: 6.37,
      longitude: 2.42, adresse: "Cadjèhoun" }]);
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
  if (hash === "#/reglages" && await page.$('[data-cible="enseigne"]')) {
    await page.click('[data-cible="enseigne"]');
    await page.waitForTimeout(1400);
  }
  return { page, ctx, erreurs, serveur };
}

/* ------------------------------------------------------------------ */
titre("5. Le superadministrateur règle le point BIZZOO et les tarifs");
{
  const paiement = { id: 1, actif: true, fournisseur: "feexpay", cle_publique: "", bac_a_sable: false,
    taux_acompte: 10, frais_livraison: 1000, ...REGLAGES_KM, livraison_latitude: null, livraison_longitude: null };
  const { page, ctx, serveur, erreurs } = await ouvrirAdmin({ moi: SUPER, hash: "#/reglages", paiement });
  await page.waitForSelector("#km-enregistrer", { timeout: 6000 }).catch(() => {});
  ok(/Pas encore en service/.test(await texte(page, "#section-km")), "« Pas encore en service » tant que le point manque");
  ok((await page.inputValue("#km-moto-forfait").catch(() => "")) === "1000" &&
     (await page.inputValue("#km-tri-km").catch(() => "")) === "500", "les tarifs : moto 1 000, tricycle 500 / km");
  await page.click("#km-enregistrer");
  await page.waitForTimeout(400);
  ok(!serveur.ecritures.some((e) => e.chemin.startsWith("paiement")), "sans point : rien ne part");
  /* Le point posé d'un toucher sur la carte. */
  const carte = await page.$("#km-carte");
  const boite = carte && await carte.boundingBox();
  if (boite) await page.mouse.click(boite.x + boite.width / 2, boite.y + boite.height / 2);
  await page.waitForTimeout(300);
  ok(/^6\.\d+$/.test(await page.inputValue("#km-lat").catch(() => "")), "un toucher sur la carte pose le point");
  await page.fill("#km-lat", String(POINT.latitude));
  await page.fill("#km-lng", String(POINT.longitude));
  await page.fill("#km-taux", "120");
  await page.click("#km-enregistrer");
  await page.waitForTimeout(400);
  ok(!serveur.ecritures.some((e) => e.chemin.startsWith("paiement")), "une part du livreur à 120 % : refusée");
  await page.fill("#km-taux", "80");
  await page.fill("#km-moto-km", "150");
  await page.click("#km-enregistrer");
  await page.waitForTimeout(800);
  const envoi = serveur.ecritures.find((e) => e.chemin.startsWith("paiement"));
  const c = (envoi && envoi.corps) || {};
  ok(c.livraison_latitude === POINT.latitude && c.livraison_longitude === POINT.longitude &&
     c.moto_prix_km === 150 && c.taux_livreur === 80 && c.tricycle_forfait === 4000,
    "le point et les tarifs partent vers la base (" + JSON.stringify(c).slice(0, 160) + ")");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("6. Le livreur : sa course, son gain ; « Mes gains »");
{
  const course = { commande_id: "cmd_km", numero: "BZ-000101", boutique_id: "bou_a", nom_boutique: "Alpha",
    client_nom: "Koffi", client_tel: "97666005", client_indicatif: "229", client_adresse: "Godomey",
    note: "", etat: "en_livraison", articles: [{ nom: "Ordinateur", code: "0001", quantite: 1 }],
    paye_le: "2026-10-22T08:00:00Z", a_encaisser: 0, recu_le: "2026-10-22T08:05:00Z",
    fiche: { numero: "BZ-000101",
      retrait: { boutique: "Alpha", adresse: "Ganhi", tel: "0197111222", indicatif: "229" },
      livraison: { nom: "Koffi", adresse: "Godomey", note: "", tel: "97666005", indicatif: "229",
        latitude: LOIN.latitude, longitude: LOIN.longitude },
      devise: "FCFA", frais: 1400, deja_paye: 301400, a_encaisser: 0,
      trajet: { vehicule: "moto", distance_km: 13.4 }, gain: 1120 } };
  let solde = { gagne: 1120, a_venir: 1120, reverse: 0, en_attente: 0, disponible: 1120, taux: 80,
    devise: "FCFA", reception: null,
    courses: [{ commande_id: "cmd_v", numero: "BZ-000090", frais: 1400, taux: 80, montant: 1120,
      credite_le: "2026-10-21T10:00:00Z", vehicule: "moto", distance_km: 13.4 }] };
  const demandes = [];
  const { page, ctx, serveur, erreurs } = await ouvrirAdmin({ moi: PORTEUR, hash: "#/livraisons", rpc: {
    mes_livraisons: [course], courses_proposees: [], ma_caisse: null, mon_compte_livreur: { livreur: true },
    solde_livreur: () => solde,
    reversements_livreurs_liste: () => demandes,
    regler_reception_livreur: (c) => {
      solde = { ...solde, reception: { tel: "0197500002", reseau: c.reseau, titulaire: c.titulaire, maj_le: "2026-10-23T09:00:00Z" } };
      return { tel: "0197500002", reseau: c.reseau };
    },
    demander_reversement_livreur: (c) => {
      demandes.push({ id: 7, livreur_id: PORTEUR, nom_livreur: "Lamine", montant: c.montant, tel: "0197500002",
        reseau: "MTN", titulaire: "", etat: "en_attente", demande_le: "2026-10-23T09:05:00Z" });
      solde = { ...solde, en_attente: c.montant, disponible: solde.disponible - c.montant };
      return 7;
    },
  } });
  await page.waitForSelector(".lv-course", { timeout: 6000 }).catch(() => {});
  ok(/Moto · 13,4 km depuis BIZZOO/.test(await texte(page, '[data-lv="trajet"]')), "sa course : « Moto · 13,4 km depuis BIZZOO »");
  ok(/Votre gain : 1 120 FCFA/.test(await texte(page, '[data-lv="gain"]')), "« Votre gain : 1 120 FCFA »");
  ok(await page.$('.lv-course a.lv-ou[href*="6.458099"]') !== null, "« Livrer à » ouvre la carte sur le point exact du client");

  await page.click("#lv-gains");
  await page.waitForSelector("#gn-solde", { timeout: 6000 }).catch(() => {});
  ok(await texte(page, "#gn-disponible") === F(1120), "Mes gains : 1 120 FCFA disponibles");
  ok(/Gagné \(80 % des frais\)/.test(await texte(page, "#gn-solde")), "« Gagné (80 % des frais) »");
  ok(await page.$eval("#gn-demander", (b) => b.disabled).catch(() => false), "sans numéro, « Demander » est fermé");
  ok(/BZ-000090/.test(await page.evaluate(() => document.body.innerText)), "ses courses payées sont listées");
  await page.click("#gn-regler");
  await page.waitForTimeout(400);
  await page.click('[data-reseau="MTN"]');
  await page.fill("#gn-tel", "97 50 00 02");
  await page.click("#gn-enregistrer");
  await page.waitForTimeout(1200);
  ok(serveur.appels.some((a) => a.fn === "regler_reception_livreur" && a.corps.reseau === "MTN"),
    "son numéro part vers la base");
  await page.click("#gn-demander");
  await page.waitForTimeout(400);
  await page.fill("#gn-montant", "1000");
  await page.click("#gn-envoyer");
  await page.waitForTimeout(1200);
  ok(serveur.appels.some((a) => a.fn === "demander_reversement_livreur" && a.corps.montant === 1000),
    "il demande 1 000 FCFA");
  ok(/En attente de BIZZOO/.test(await page.evaluate(() => document.body.innerText)), "sa demande paraît, en attente");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* ------------------------------------------------------------------ */
titre("7. Le superadministrateur tranche la demande d'un livreur");
{
  const demande = { id: 7, livreur_id: PORTEUR, nom_livreur: "Lamine", montant: 1000, tel: "0197500002",
    reseau: "MTN", titulaire: "Lamine B.", etat: "en_attente", demande_le: "2026-10-23T09:05:00Z" };
  const { page, ctx, serveur, erreurs } = await ouvrirAdmin({ moi: SUPER, hash: "#/reversements", rpc: {
    reversements_liste: [], reversements_livreurs_liste: [demande],
    decider_reversement_livreur: "valide" } });
  await page.waitForTimeout(600);
  ok(/Livreur — Lamine/.test(await page.evaluate(() => document.body.innerText)), "la demande de Lamine, marquée « Livreur »");
  await page.click('[data-valider="7"]');
  await page.waitForTimeout(400);
  await page.fill("#saisie-motif", "MTN-778899").catch(() => {});
  await page.click("[data-role=ok]").catch(() => {});
  await page.waitForTimeout(1000);
  const appel = serveur.appels.find((a) => a.fn === "decider_reversement_livreur");
  ok(!!appel && appel.corps.cible === 7 && appel.corps.accord === true && appel.corps.reference === "MTN-778899",
    "« Envoyé » appelle decider_reversement_livreur, avec la référence (" + JSON.stringify(appel && appel.corps) + ")");
  ok(!serveur.appels.some((a) => a.fn === "decider_reversement"), "pas la fonction des boutiques");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs
  ? "\n\x1b[31m" + echecs + " constat(s) en échec ✘\x1b[0m"
  : "\n\x1b[32mLa livraison se compte au kilomètre, et le livreur touche sa part ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
