/* =========================================================
   Le lieu de chaque vendeur (3.78.0)
   =========================================================
   La base garde la règle (supabase/tests/99…-lieux-vendeurs.sql). Ce
   banc regarde les écrans :

     1. LE SUPERADMINISTRATEUR, écran « Vendeurs » : « position manquante »
        sur un vendeur sans lieu ; sa fiche « Le lieu de … » : nom du
        commerce, numéro, adresse écrite, position (cherchée, collée,
        touchée), horaires — sans position, rien ne part ;
     2. LE CLIENT : un produit d'un vendeur fermé ne se commande pas (fiche,
        panier) ; ouvert, la livraison part de LA position du vendeur —
        deux vendeurs, deux arrêts, deux suppléments — jamais de celle de
        la boutique multivendeur ;
     3. LE LIVREUR : chaque vendeur chez qui récupérer, avec son adresse
        écrite, son numéro, ses articles — pas l'adresse de la boutique
        multivendeur ; « Colis récupéré chez les 2 vendeurs ».
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-lieux-vendeurs.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const plat = (s) => String(s || "").replace(/[  ]/g, " ").replace(/\s+/g, " ").trim();
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const texte = (page, sel) => page.evaluate((s) =>
  [...document.querySelectorAll(s)].map((e) => e.innerText).join(" || "), sel).then(plat);
const TUILE = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=", "base64");
/* CAPTURES=<dossier> : une image de chaque écran. */
const capture = async (page, nom, sel) => {
  if (!process.env.CAPTURES) return;
  const cible = sel ? await page.$(sel) : null;
  await (cible || page).screenshot({ path: process.env.CAPTURES + "/vendeurs-" + nom + ".png" });
};

const SUPER = "11111111-1111-1111-1111-111111111111";
const LIV = "cccccccc-2222-2222-2222-222222222222";
const V1 = "c7c7c7c7-0000-0000-0000-000000000001";
const V2 = "c7c7c7c7-0000-0000-0000-000000000002";
const DANTOKPA = { latitude: 6.3712, longitude: 2.4318 };

/* Tous les jours, sauf aujourd'hui (heure du Bénin). */
const JOURS = ["lun", "mar", "mer", "jeu", "ven", "sam", "dim"];
const aujourdhui = JOURS[(new Date(Date.now() + 3600000).getUTCDay() + 6) % 7];
const toujours = Object.fromEntries(JOURS.map((j) => [j, { de: "00:00", a: "24:00" }]));
const fermeAujourdhui = Object.fromEntries(JOURS.map((j) => [j, j === aujourdhui ? null : { de: "00:00", a: "24:00" }]));

/* ================================================================
   1. Le superadministrateur
   ================================================================ */
async function ouvrirAdmin({ moi, hash, rpc = {}, courses = [] }) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2400 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: b64({ alg: "HS256" }) + "." + b64({ sub: a.moi }) + ".s",
      refresh_token: "r", expire_a: Date.now() + 3600000, email: "x@bizzoo.bj" }));
    window.__toasts = [];
    document.addEventListener("DOMContentLoaded", () => {
      const zone = document.querySelector("#toasts") || document.body;
      new MutationObserver(() => window.__toasts.push(zone.innerText))
        .observe(zone, { childList: true, subtree: true });
    });
  }, { moi });
  await page.route("https://tile.openstreetmap.org/**",
    (r) => r.fulfill({ status: 200, contentType: "image/png", body: TUILE }));
  await page.route("**/functions/v1/lieu", (r) => {
    const corps = JSON.parse(r.request().postData() || "{}");
    const d = (x) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (corps.action === "chercher") {
      return d({ resultats: [{ nom: "Dantokpa, Cotonou", detail: "Dantokpa, Cotonou, Littoral", ...DANTOKPA }] });
    }
    return d({ nom: "Dantokpa, Cotonou" });
  });
  const serveur = { appels: [] };
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    const corps = (() => { try { return req.postDataJSON(); } catch (_) { return null; } })();
    if (c.startsWith("rpc/")) {
      const fn = c.slice(4);
      serveur.appels.push({ fn, corps });
      if (fn in rpc) return d(typeof rpc[fn] === "function" ? rpc[fn](corps) : rpc[fn]);
      if (fn === "mes_livraisons") return d(courses);
      if (fn === "courses_proposees") return d([]);
      return d(null);
    }
    if (c.startsWith("profils")) {
      const voulu = (u.searchParams.get("id") || "").replace(/^eq\./, "");
      const fiches = [
        { id: SUPER, email: "sup@bizzoo.bj", role: "superadministrateur", actif: true, nom: "Sup",
          peut_modifier_produits: true, boutique_id: null },
        { id: LIV, email: "liv@bizzoo.bj", role: "livreur", actif: true, nom: "Codjo",
          peut_modifier_produits: false, boutique_id: null, disponible: true },
        { id: V1, email: "", role: "vendeur", actif: true, nom: "Afi", tel: "0197700001", boutique_id: null },
        { id: V2, email: "", role: "vendeur", actif: true, nom: "Bio", tel: "0197700002", boutique_id: null },
      ];
      return d(voulu ? fiches.filter((p) => p.id === voulu) : fiches);
    }
    if (c.startsWith("positions_livreurs")) return d([{ profil_id: LIV, latitude: 6.37, longitude: 2.42, adresse: "Cotonou" }]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1800);
  await page.evaluate((h) => { location.hash = h; }, hash);
  await page.waitForTimeout(1800);
  return { page, ctx, erreurs, serveur };
}

titre("1. Le superadministrateur : le lieu de chaque vendeur");
{
  const VENTES = [V1, V2].map((id, i) => ({ id, nom: i ? "Bio" : "Afi", tel: "019770000" + (i + 1), actif: true,
    produits: 1, ventes: 0, part: 0, commission: 0, a_venir: 0, reverse: 0, en_attente: 0, disponible: 0 }));
  const { page, ctx, erreurs, serveur } = await ouvrirAdmin({ moi: SUPER, hash: "#/vendeurs", rpc: {
    ventes_vendeurs: VENTES, parts_vendeurs_historique_liste: [],
    lieux_vendeurs: [{ vendeur_id: V2, nom: "Sacs Bio", tel: "0197700022", adresse: "Missèbo, face à la pharmacie",
      latitude: 6.36, longitude: 2.43, horaires: true }],
    lieu_vendeur: { nom: "", tel: "", indicatif: "229", adresse: "", latitude: null, longitude: null,
      ouvertures: null, connu: false },
    enregistrer_lieu_vendeur: (c) => ({ ...c.lieu, connu: true }),
  } });
  await page.waitForSelector(".vv-rangee", { timeout: 6000 }).catch(() => {});
  const afi = await texte(page, '.vv-rangee:has([data-vendeur="' + V1 + '"])');
  const bio = await texte(page, '.vv-rangee:has([data-vendeur="' + V2 + '"])');
  ok(/Position manquante/.test(afi), "Afi, sans lieu : « Position manquante » (" + afi.slice(0, 80) + ")");
  ok(/Missèbo, face à la pharmacie/.test(bio) && !/Position manquante/.test(bio), "Bio : son adresse, sans alerte");
  await capture(page, "liste", "#vv-liste");
  await page.click('[data-lieu="' + V1 + '"]');
  await page.waitForSelector("#vl-enregistrer", { timeout: 5000 }).catch(() => {});
  ok(/Position manquante/.test(await texte(page, "#vl-etat")), "la fiche s'ouvre : position manquante");
  ok(await page.$("#vl-ouvertures") !== null, "les jours et heures du vendeur, comme une boutique");
  await page.fill("#vl-nom", "Pagnes Afi");
  await page.fill("#vl-tel", "01 97 70 00 11");
  await page.fill("#vl-adresse", "Dantokpa, allée 4, porte bleue");
  await page.click("#vl-enregistrer");
  await page.waitForTimeout(400);
  ok(/Posez la position du vendeur/.test(await texte(page, "#vl-erreur")) &&
     !serveur.appels.some((a) => a.fn === "enregistrer_lieu_vendeur"),
    "sans position : « Posez la position du vendeur », rien ne part");
  await page.fill("#vl-lieu-q", "Dantokpa");
  await page.press("#vl-lieu-q", "Enter");
  await page.waitForSelector("#vl-chercher .lieu-resultat", { timeout: 5000 }).catch(() => {});
  await page.click("#vl-chercher .lieu-resultat");
  await page.waitForTimeout(500);
  ok(/Dantokpa, Cotonou/.test(await texte(page, "#vl-etat")), "le quartier cherché pose sa position");
  await capture(page, "fiche", ".feuille");
  await page.click("#vl-enregistrer");
  await page.waitForTimeout(800);
  const e = (serveur.appels.find((a) => a.fn === "enregistrer_lieu_vendeur") || {}).corps || {};
  ok(e.cible === V1 && e.lieu && e.lieu.latitude === DANTOKPA.latitude && e.lieu.longitude === DANTOKPA.longitude,
    "enregistré pour Afi, à SA position (Dantokpa)");
  ok(e.lieu && e.lieu.nom === "Pagnes Afi" && e.lieu.adresse === "Dantokpa, allée 4, porte bleue" &&
     /0197700011|01 97 70 00 11/.test(e.lieu.tel), "avec son commerce, son adresse écrite, son numéro");
  ok(e.lieu && e.lieu.ouvertures && typeof e.lieu.ouvertures.lun === "object", "et ses horaires");
  ok(/Lieu du vendeur enregistré/.test(plat(await page.evaluate(() => (window.__toasts || []).join(" | ")))),
    "« Lieu du vendeur enregistré »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* ================================================================
   2. Le client
   ================================================================ */
const REGLAGES_KM = { livraison_latitude: 6.3654, livraison_longitude: 2.4183, livraison_adresse: "Siège BIZZOO",
  livraison_rayon_km: 2, livraison_coef: 1.0, moto_forfait: 600, moto_prix_km: 100,
  tricycle_forfait: 4000, tricycle_prix_km: 500, taux_livreur: 80, livraison_supplement_boutique: 200 };
/* La boutique multivendeur, loin de tout : sa position ne doit pas compter. */
const BOUTIQUES = [{ id: "bou_marche", nom: "Marché BIZZOO", categorie_id: "cat_mode", icone: "magasin",
  couleur: "#0047D9", devise: "FCFA", indicatif: "229", whatsapp: "97000001", actif: true, ordre: 1,
  mode_paiement: "total", taux_acompte: 100, frais_livraison: 0, latitude: 7.0, longitude: 2.0 }];
const PRODUITS = [
  { id: "prod_a", boutique_id: "bou_marche", nom: "Pagne wax", code: "0001", prix: 10000, categorie_id: "cat_mode",
    sous_categorie_id: "sc_x", stock: 5, disponible: true, images: [], vehicule: "moto",
    cree_le: "2026-09-01T08:00:00Z", modifie_le: "2026-09-01T08:00:00Z" },
  { id: "prod_b", boutique_id: "bou_marche", nom: "Sac cuir", code: "0002", prix: 12000, categorie_id: "cat_mode",
    sous_categorie_id: "sc_x", stock: 5, disponible: true, images: [], vehicule: "moto",
    cree_le: "2026-09-01T08:00:00Z", modifie_le: "2026-09-01T08:00:00Z" },
];
const CLIENT_LOIN = { latitude: 6.4500, longitude: 2.4318 };

async function ouvrirClient({ hash, panier, points, destination = null }) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1600 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    try {
      localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
      localStorage.setItem("bizzoo-panier", JSON.stringify(a.panier));
      localStorage.setItem("bizzoo-coordonnees", JSON.stringify({ nom: "Rosine", tel: "0197000000", indicatif: "229" }));
      if (a.destination) localStorage.setItem("bizzoo-destination", JSON.stringify(a.destination));
    } catch (_) { /* une page hors de l'application */ }
  }, { panier, destination });
  await page.route("https://tile.openstreetmap.org/**",
    (r) => r.fulfill({ status: 200, contentType: "image/png", body: TUILE }));
  await page.route("**/functions/v1/**", (r) =>
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ actif: false, nom: null }) }));
  await page.route("**/rest/v1/**", (route) => {
    const c = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c === "rpc/points_retrait") return d(points);
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("reglages")) return d([{ compte_obligatoire: false }]);
    if (c.startsWith("paiement")) {
      return d([{ id: 1, actif: true, fournisseur: "feexpay", cle_publique: "", bac_a_sable: false,
        taux_acompte: 100, frais_livraison: 0, ...REGLAGES_KM }]);
    }
    if (c.startsWith("produits")) return d(PRODUITS);
    if (c.startsWith("boutiques")) return d(BOUTIQUES);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/client/index.html" + hash, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(2200);
  return { page, ctx, erreurs };
}
const POINTS = (ouvAfi) => [
  { id: V1, nom: "Pagnes Afi", latitude: DANTOKPA.latitude, longitude: DANTOKPA.longitude, ouvertures: ouvAfi,
    produits: ["prod_a"] },
  { id: V2, nom: "Sacs Bio", latitude: null, longitude: null, ouvertures: null, produits: ["prod_b"] },
];

titre("2. Le client : les heures et la position de chaque vendeur");
{
  const { page, ctx, erreurs } = await ouvrirClient({ hash: "#/produit/prod_a", panier: [], points: POINTS(fermeAujourdhui) });
  ok(/Vendeur « Pagnes Afi » fermé en ce moment/.test(await texte(page, "#p-fermee")) && !(await page.$("#p-ajouter")) &&
     await page.evaluate(() => { const b = document.querySelector("#p-fermee .btn"); return !!b && b.disabled; }),
    "Pagnes Afi fermée aujourd'hui : « Vendeur « Pagnes Afi » fermé en ce moment », bouton éteint");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  const { page, ctx } = await ouvrirClient({ hash: "#/panier", panier: [{ produitId: "prod_a", quantite: 1 }],
    points: POINTS(fermeAujourdhui) });
  ok(/Pagnes Afi est fermé en ce moment/.test(await texte(page, "#pa-vendeurs-fermes")) &&
     await page.$eval("#pa-commander", (b) => b.disabled).catch(() => false),
    "au panier : « Pagnes Afi est fermé en ce moment », la commande attend");
  await ctx.close();
}
{
  /* Ouverts : deux vendeurs = deux arrêts. Afi à Dantokpa (6,3712), Bio
     sans position (le point BIZZOO, 6,3654) ; le client au nord (6,45).
     Jamais depuis la boutique multivendeur (7,0 ; 2,0). */
  const { page, ctx, erreurs } = await ouvrirClient({ hash: "#/commande", destination: CLIENT_LOIN,
    panier: [{ produitId: "prod_a", quantite: 1 }, { produitId: "prod_b", quantite: 1 }], points: POINTS(toujours) });
  const km = await texte(page, ".pa-km");
  ok(/Sacs Bio → Pagnes Afi → vous|Pagnes Afi → Sacs Bio → vous/.test(km),
    "la tournée passe par les deux vendeurs (" + km + ")");
  ok(/dont 400 FCFA pour 2 boutiques/.test(km), "deux arrêts : 2 × 200 de supplément");
  const dist = Number((km.match(/(\d+,\d) km/) || [])[1]?.replace(",", "."));
  ok(dist > 8 && dist < 12, "la distance part des vendeurs, pas de la boutique multivendeur (" + dist + " km)");
  await capture(page, "client", "#co-lignes-total");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* ================================================================
   3. Le livreur
   ================================================================ */
titre("3. Le livreur : chez chaque vendeur, à son adresse");
{
  const vendeurs = [
    { vendeur_id: V1, nom: "Pagnes Afi", adresse: "Dantokpa, allée 4, porte bleue", tel: "0197700011",
      indicatif: "229", latitude: DANTOKPA.latitude, longitude: DANTOKPA.longitude,
      articles: [{ nom: "Pagne wax", quantite: 2 }] },
    { vendeur_id: V2, nom: "Sacs Bio", adresse: "Missèbo, face à la pharmacie", tel: "0197700022",
      indicatif: "229", latitude: null, longitude: null, articles: [{ nom: "Sac cuir", quantite: 1 }] },
  ];
  const fiche = { numero: "BZ-000777", devise: "FCFA", frais: 1600, deja_paye: 33600, a_encaisser: 0, encaisse: null,
    retrait: { boutique: "Marché BIZZOO", adresse: "Siège du marché, Ganhi", tel: "0197000000", indicatif: "229",
      latitude: 7.0, longitude: 2.0, vendeurs },
    livraison: { nom: "Rosine", adresse: "Tempé, Godomey", note: "", tel: "97666123", indicatif: "229" } };
  const course = (o) => ({ commande_id: "cmd_v", numero: "BZ-000777", boutique_id: "bou_marche",
    nom_boutique: "Marché BIZZOO", client_nom: "Rosine", client_tel: "97666123", client_indicatif: "229",
    client_adresse: "Tempé", note: "", etat: "preparee", paye_le: "2026-11-05T08:00:00Z", a_encaisser: 0,
    recu_le: "2026-11-05T08:05:00Z",
    articles: [{ nom: "Pagne wax", quantite: 2 }, { nom: "Sac cuir", quantite: 1 }], fiche, ...o });
  /* Une commande groupée : le marché, et une autre boutique. */
  const autre = course({ boutique_id: "bou_autre", nom_boutique: "Alpha", articles: [{ nom: "Casque", quantite: 1 }],
    fiche: { ...fiche, retrait: { boutique: "Alpha", adresse: "Ganhi", tel: "0197111222", indicatif: "229" } } });
  const { page, ctx, erreurs } = await ouvrirAdmin({ moi: LIV, hash: "#/livraisons", courses: [course({}), autre] });
  await page.waitForSelector(".lv-course", { timeout: 6000 }).catch(() => {});
  await page.waitForTimeout(400);
  const marche = await texte(page, '.lv-retrait[data-boutique="bou_marche"]');
  ok(/boutique multivendeur/.test(marche) && /Pagnes Afi/.test(marche) && /Sacs Bio/.test(marche),
    "le marché : « boutique multivendeur », puis Pagnes Afi et Sacs Bio");
  ok(/Dantokpa, allée 4, porte bleue/.test(marche) && /Missèbo, face à la pharmacie/.test(marche),
    "l'adresse écrite de chaque vendeur");
  ok(/0197700011/.test(marche) && /0197700022/.test(marche), "le numéro de chaque vendeur");
  ok(/Pagne wax × 2/.test(marche) && /Sac cuir × 1/.test(marche), "ce qu'il prend chez chacun");
  ok(!/Siège du marché, Ganhi/.test(marche), "pas l'adresse de la boutique multivendeur : tout a son vendeur");
  const lien = await page.$eval('.lv-retrait[data-boutique="bou_marche"] .lv-vendeur a.lv-ou',
    (a) => a.getAttribute("href")).catch(() => "");
  ok(/6\.3712%2C2\.4318|6\.3712,2\.4318/.test(lien), "« Voir sur la carte » mène à LA position du vendeur (" + lien.slice(-30) + ")");
  ok(/Colis récupéré chez les 2 vendeurs/.test(await texte(page, '.lv-retrait[data-boutique="bou_marche"] .lv-recupere')),
    "« Colis récupéré chez les 2 vendeurs »");
  await capture(page, "livreur", ".lv-groupee");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " échec(s)" : "\nChaque vendeur a son lieu : ses heures, sa position, son adresse ✔");
process.exit(echecs ? 1 : 0);
