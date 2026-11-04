/* =========================================================
   Le nom des lieux (3.76.0)
   =========================================================
   La base garde les noms (supabase/tests/99…-nom-des-lieux.sql) ; la
   fonction serveur « lieu » est éprouvée à part (tools/eprouver-lieu.sh).
   Ce banc regarde les écrans :

     1. le client cherche « Tempé » : l'épingle y va, les frais suivent,
        « Livrer à : Tempé, Godomey » ; la commande porte CE lieu et le
        repère — plus l'adresse du compte (« Ita ») ;
     2. « Faire livrer » : le lieu cherché pose le point, les frais
        calculés par la base remplissent la case (modifiable, puis
        « Reprendre ce montant »), l'adresse prend le nom du lieu ;
     3. le livreur lit le quartier de chaque boutique et du client ; un
        lien de carte n'est plus recopié tel quel ; chaque boutique de la
        commande groupée a son « Colis récupéré chez … » ;
     4. la fonction absente (404) : rien ne casse.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-lieux.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const plat = (s) => String(s || "").replace(/[  ]/g, " ").replace(/\s+/g, " ").trim();
/* CAPTURES=<dossier> : une image de chaque écran, pour la documentation. */
const capture = async (page, nom, sel) => {
  if (!process.env.CAPTURES) return;
  const cible = sel ? await page.$(sel) : null;
  await (cible || page).screenshot({ path: process.env.CAPTURES + "/lieux-" + nom + ".png" });
};
const texte = (page, sel) => page.evaluate((s) =>
  [...document.querySelectorAll(s)].map((e) => e.innerText).join(" || "), sel).then(plat);

const TUILE = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=", "base64");

/* Ce que dirait OpenStreetMap, derrière la fonction « lieu ». */
const TEMPE = { latitude: 6.4012, longitude: 2.3355 };
const NOMS = {
  [TEMPE.latitude + "," + TEMPE.longitude]: "Tempé, Godomey",
  "6.37,2.42": "Ganhi, Cotonou",
  "6.38,2.43": "Missèbo, Cotonou",
  "6.39,2.36": "Sèdomey, Togoudo, Godomey",
};
const nomDe = (lat, lng) => NOMS[Number(lat) + "," + Number(lng)] || null;
async function lieuServeur(page, journal, { absent = false } = {}) {
  await page.route("**/functions/v1/lieu", (r) => {
    const corps = JSON.parse(r.request().postData() || "{}");
    journal.push(corps);
    const d = (x, statut = 200) => r.fulfill({ status: statut, contentType: "application/json", body: JSON.stringify(x) });
    if (absent) return d({ message: "Requested function was not found" }, 404);
    if (corps.action === "nommer") return d({ nom: nomDe(corps.latitude, corps.longitude), cache: false });
    if (corps.action === "chercher") {
      return d({ resultats: /temp/i.test(corps.q)
        ? [{ nom: "Tempé, Godomey", detail: "Tempé, Godomey, Abomey-Calavi, Atlantique", ...TEMPE }]
        : [] });
    }
    return d({ erreur: "action inconnue" }, 400);
  });
}

/* ================================================================
   1. L'application des clients
   ================================================================ */
const REGLAGES_KM = { livraison_latitude: 6.3654, livraison_longitude: 2.4183, livraison_adresse: "Siège BIZZOO",
  livraison_rayon_km: 6, livraison_coef: 1.3, moto_forfait: 600, moto_prix_km: 100,
  tricycle_forfait: 4000, tricycle_prix_km: 500, taux_livreur: 80, livraison_supplement_boutique: 200 };
const BOUTIQUES = [{ id: "bou_a", nom: "Alpha", categorie_id: "cat_hightech", icone: "magasin", couleur: "#0047D9",
  devise: "FCFA", indicatif: "229", whatsapp: "97000001", actif: true, ordre: 1,
  mode_paiement: "acompte", taux_acompte: 10, frais_livraison: 1500 }];
const PRODUITS = [{ id: "prod_1", boutique_id: "bou_a", nom: "Ordinateur", code: "0001", prix: 300000,
  categorie_id: "cat_hightech", sous_categorie_id: "sc_x", stock: 5, disponible: true, images: [],
  vehicule: "moto", cree_le: "2026-09-01T08:00:00Z", modifie_le: "2026-09-01T08:00:00Z" }];

async function ouvrirClient({ absent = false } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1600 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript(() => {
    try {
      localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
      localStorage.setItem("bizzoo-panier", JSON.stringify([{ produitId: "prod_1", quantite: 1 }]));
      /* L'adresse du compte dit « Ita » : c'est elle qui partait avant. */
      localStorage.setItem("bizzoo-coordonnees", JSON.stringify({ nom: "Rosine", tel: "0197000000", indicatif: "229",
        adresse: "Ita" }));
    } catch (_) { /* une page hors de l'application */ }
  });
  await page.route("https://tile.openstreetmap.org/**",
    (r) => r.fulfill({ status: 200, contentType: "image/png", body: TUILE }));
  const serveur = { creations: [], lieu: [] };
  await lieuServeur(page, serveur.lieu, { absent });
  await page.route("**/functions/v1/distance-route", (r) =>
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ actif: false }) }));
  await page.route("**/functions/v1/feexpay", (route) => {
    const corps = JSON.parse(route.request().postData() || "{}");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (corps.action === "payer") return d({ ouvert: true, reference: "ref_1" });
    return d({ etat: "a_payer", attente: true, statut: "PENDING" });
  });
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/creer_commande")) {
      serveur.creations.push(JSON.parse(req.postData() || "{}"));
      return d({ id: "cmd_l", numero: "BZ-000301", total: 301500, devise: "FCFA", etat: "a_payer",
        code_promo: "", remise: 0, frais_livraison: 1500,
        livraison: { vehicule: "moto", distance_km: 14.1, km_factures: 9, frais: 1500 },
        taux_acompte: 10, acompte: 31500, reste: 270000,
        boutiques: [{ id: "bou_a", nom: "Alpha", whatsapp: "97000001", indicatif: "229", montant: 300000,
          a_encaisser: 270000, lignes: [{ nom: "Ordinateur", code: "0001", prix: 300000, quantite: 1 }] }] });
    }
    if (c.startsWith("rpc/suivre_commande")) return d({ etat: "a_payer", remarque: "" });
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("reglages")) return d([{ compte_obligatoire: false }]);
    if (c.startsWith("paiement")) {
      return d([{ id: 1, actif: true, fournisseur: "feexpay", cle_publique: "", bac_a_sable: false,
        taux_acompte: 10, frais_livraison: 1000, ...REGLAGES_KM }]);
    }
    if (c.startsWith("produits")) return d(PRODUITS);
    if (c.startsWith("boutiques")) return d(BOUTIQUES);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/client/index.html#/commande", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1800);
  return { page, ctx, erreurs, serveur };
}

titre("1. Le client cherche « Tempé » : l'épingle y va, la commande porte ce lieu");
{
  const { page, ctx, erreurs, serveur } = await ouvrirClient();
  ok(await page.$("#co-lieu-q") !== null, "« Chercher un quartier » dans « Où livrer ? »");
  await page.fill("#co-lieu-q", "Tempé");
  await page.press("#co-lieu-q", "Enter");
  await page.waitForSelector(".lieu-resultat", { timeout: 5000 }).catch(() => {});
  ok(/Tempé, Godomey/.test(await texte(page, "#co-ou-chercher")), "un résultat : « Tempé, Godomey »");
  ok(serveur.lieu.some((x) => x.action === "chercher" && x.q === "Tempé"), "la recherche part quand on la demande");
  await page.click(".lieu-resultat");
  await page.waitForTimeout(500);
  const dest = await page.evaluate(() => JSON.parse(localStorage.getItem("bizzoo-destination") || "null"));
  ok(dest && dest.latitude === TEMPE.latitude && dest.longitude === TEMPE.longitude, "l'épingle est posée à Tempé");
  ok(await page.$("#co-carte .leaflet-marker-icon") !== null, "la carte s'ouvre, l'épingle dessus");
  ok(/km/.test(await texte(page, "#co-ou-etat")) && /FCFA/.test(await texte(page, "#co-ou-etat")),
    "les frais suivent (" + await texte(page, "#co-ou-etat") + ")");
  ok(/Livrer à : Tempé, Godomey/.test(await texte(page, "#co-ou-lieu")), "« Livrer à : Tempé, Godomey »");
  ok(/Ita/.test(await texte(page, "#co-resume")), "(le résumé du compte dit toujours « Ita »)");

  await page.fill("#co-repere", "Portail bleu après la pharmacie");
  await capture(page, "client", "#co-ou");
  await page.dispatchEvent("#co-repere", "change");
  await page.click('#co-operateurs [data-reseau="MTN"]');
  await page.click("#co-payer");
  await page.waitForFunction(() => location.hash === "#/commande/cmd_l", null, { timeout: 8000 }).catch(() => {});
  await page.waitForTimeout(500);
  const corps = serveur.creations[0] || {};
  ok(corps.client && corps.client.adresse === "Tempé, Godomey — Portail bleu après la pharmacie",
    "la commande part avec « Tempé, Godomey — Portail bleu… », plus « Ita » (" +
    JSON.stringify(corps.client && corps.client.adresse) + ")");
  ok(corps.destination && corps.destination.latitude === TEMPE.latitude, "et la destination de l'épingle");
  const gardees = await page.evaluate(() => JSON.parse(localStorage.getItem("bizzoo-coordonnees") || "{}"));
  ok(gardees.adresse === "Ita", "l'adresse du compte, elle, ne change pas");
  ok(await page.evaluate(() => localStorage.getItem("bizzoo-repere")) === "Portail bleu après la pharmacie",
    "le repère est gardé pour la prochaine fois");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  /* Rien trouvé : on le dit, et on invite à toucher la carte. */
  const { page, ctx } = await ouvrirClient();
  await page.fill("#co-lieu-q", "Zzzz");
  await page.click("#co-ou-chercher .lieu-chercher");
  await page.waitForTimeout(600);
  ok(/Aucun lieu trouvé/.test(await texte(page, "#co-ou-chercher")), "un nom inconnu : « Aucun lieu trouvé… touchez la carte »");
  await ctx.close();
}

titre("4 (client). La fonction « lieu » absente : rien ne casse");
{
  const { page, ctx, erreurs, serveur } = await ouvrirClient({ absent: true });
  await page.fill("#co-lieu-q", "Tempé");
  await page.press("#co-lieu-q", "Enter");
  await page.waitForTimeout(700);
  ok(/ne répond pas/.test(await texte(page, "#co-ou-chercher")), "la recherche dit qu'elle ne répond pas");
  /* On pose l'épingle autrement : un lien de carte. */
  await page.fill("#co-ou-lien", "6.4012, 2.3355");
  await page.dispatchEvent("#co-ou-lien", "change");
  await page.waitForTimeout(500);
  ok(/l'épingle posée sur la carte/.test(await texte(page, "#co-ou-lieu")), "sans nom : « l'épingle posée sur la carte »");
  await page.click('#co-operateurs [data-reseau="MTN"]');
  await page.click("#co-payer");
  await page.waitForFunction(() => location.hash === "#/commande/cmd_l", null, { timeout: 8000 }).catch(() => {});
  const corps = serveur.creations[0] || {};
  ok(corps.client && corps.client.adresse === "Ita", "sans nom ni repère : l'adresse saisie, comme avant");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

/* ================================================================
   2 et 3. L'administration
   ================================================================ */
const ADMBZ = "d7d7d7d7-0000-0000-0000-000000000001";
const LIV = "cccccccc-2222-2222-2222-222222222222";
const PROFILS = {
  [ADMBZ]: { id: ADMBZ, email: "awa@bizzoo.bj", nom: "Awa", role: "administrateur", actif: true,
    boutique_id: null, peut_commandes: true, peut_modifier_produits: true, peut_faire_livrer: true },
  [LIV]: { id: LIV, email: "biz@bizzoo.bj", nom: "Codjo", role: "livreur", actif: true,
    peut_modifier_produits: false, boutique_id: null, disponible: true },
};
const PRODUITS_ADMIN = [
  { id: "prod_casque", boutique_id: "bou_a", nom: "Casque", code: "0001", prix: 12000, stock: 5, disponible: true,
    images: [], cree_le: "2026-10-01T08:00:00Z", modifie_le: "2026-10-02T08:00:00Z" },
];
const fiche = (o = {}) => ({ numero: "BZ-000120",
  retrait: { boutique: "Alpha", adresse: "Ganhi", tel: "0197111222", indicatif: "229" },
  livraison: { nom: "Afi", adresse: "Fidjrossè", note: "", tel: "97666007", indicatif: "229" },
  devise: "FCFA", frais: 1000, deja_paye: 3000, a_encaisser: 7000, encaisse: null,
  momopay: { code: "123456", nom: "BIZZOO SARL" }, ...o });
const partie = (bq, nom, retrait, o = {}) => ({ commande_id: "cmd_g", numero: "BZ-000120", boutique_id: bq,
  nom_boutique: nom, client_nom: "Afi", client_tel: "97666007", client_indicatif: "229",
  client_adresse: "https://maps.app.goo.gl/AbCdEf", note: "", etat: "en_livraison",
  articles: [{ nom: "Article " + nom, quantite: 1 }], paye_le: "2026-10-20T08:00:00Z",
  a_encaisser: 3500, recu_le: "2026-10-20T08:05:00Z",
  fiche: fiche({ retrait: { boutique: nom, tel: "0197000000", indicatif: "229", ...retrait },
    livraison: { nom: "Afi", adresse: "https://maps.app.goo.gl/AbCdEf", note: "", tel: "97666007", indicatif: "229",
      latitude: 6.39, longitude: 2.36 } }), ...o });

async function ouvrirAdmin({ moi, hash, courses = [], devis = null }) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2600 }, serviceWorkers: "block" });
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
    window.__toasts = [];
    document.addEventListener("DOMContentLoaded", () => {
      const zone = document.querySelector("#toasts") || document.body;
      new MutationObserver(() => window.__toasts.push(zone.innerText))
        .observe(zone, { childList: true, subtree: true });
    });
  }, { moi, email: PROFILS[moi].email });
  await page.route("https://tile.openstreetmap.org/**",
    (r) => r.fulfill({ status: 200, contentType: "image/png", body: TUILE }));
  const serveur = { appels: [], lieu: [], routes: [] };
  await lieuServeur(page, serveur.lieu);
  await page.route("**/functions/v1/distance-route", (r) => {
    serveur.routes.push(JSON.parse(r.request().postData() || "{}"));
    return r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ actif: false }) });
  });
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    const corps = (() => { try { return req.postDataJSON(); } catch (_) { return null; } })();
    if (c.startsWith("rpc/")) serveur.appels.push({ fn: c.slice(4), corps });
    if (c === "rpc/devis_faire_livrer") return d(devis(corps));
    if (c === "rpc/faire_livrer") return d({ id: "cmd_wa", numero: "BZ-000201", total: 13600, client_relie: false,
      lieu_retrait: ((corps.client || {}).retrait || "").trim() });
    if (c === "rpc/mes_livraisons") return d(courses);
    if (c === "rpc/courses_proposees") return d([]);
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("profils")) {
      const id = (u.searchParams.get("id") || "").replace(/^eq\./, "");
      return d(id ? [PROFILS[id]].filter(Boolean) : Object.values(PROFILS));
    }
    if (c.startsWith("positions_livreurs")) return d([{ profil_id: LIV, latitude: 6.37, longitude: 2.42, adresse: "Cotonou" }]);
    if (c.startsWith("paiement")) {
      return d([{ id: 1, actif: true, fournisseur: "feexpay", ...REGLAGES_KM }]);
    }
    if (c.startsWith("produits")) return d(PRODUITS_ADMIN);
    if (c.startsWith("boutiques")) return d([{ id: "bou_a", nom: "Alpha", devise: "FCFA", indicatif: "229",
      actif: true, ordre: 1, adresse: "Ganhi", tel: "0196000011" }]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1800);
  await page.evaluate((h) => { location.hash = h; }, hash);
  await page.waitForTimeout(1600);
  return { page, ctx, erreurs, serveur };
}

titre("2. « Faire livrer » : le lieu cherché pose le point, les frais se calculent");
{
  /* La base : 600 de forfait jusqu'à 6 km, puis 100 le km. */
  const devis = (corps) => ({ sous_total: 12000, devise: "FCFA", vehicule: "moto",
    livraison: corps.destination
      ? { frais: 1600, distance_km: 15.2, km_factures: 10, rayon_km: 6, forfait: 600, prix_km: 100,
          nb_boutiques: 1, supplements: 0, calcul: "vol_oiseau",
          tournee: [{ boutique_id: "bou_a", nom: "Alpha", latitude: 6.37, longitude: 2.42, vers_suivante_km: 15.2 }] }
      : null });
  const { page, ctx, erreurs, serveur } = await ouvrirAdmin({ moi: ADMBZ, hash: "#/faire-livrer", devis });
  await page.waitForSelector(".fl-produit", { timeout: 6000 }).catch(() => {});
  await page.click('[data-id="prod_casque"] .fl-ajouter');
  await page.click("#fl-suivant");
  await page.waitForSelector("#fl-client", { timeout: 4000 }).catch(() => {});
  await page.waitForTimeout(500);
  ok(/Posez le point de livraison/.test(await texte(page, "#fl-frais-calcul")), "sans point : « Posez le point de livraison »");
  ok(await page.inputValue("#fl-frais") === "", "et la case des frais reste vide");
  await page.fill("#fl-lieu-q", "Tempé");
  await page.press("#fl-lieu-q", "Enter");
  await page.waitForSelector("#fl-chercher .lieu-resultat", { timeout: 5000 }).catch(() => {});
  await page.click("#fl-chercher .lieu-resultat");
  await page.waitForTimeout(1200);
  const appel = serveur.appels.filter((a) => a.fn === "devis_faire_livrer").pop() || {};
  ok(appel.corps && appel.corps.destination && appel.corps.destination.latitude === TEMPE.latitude,
    "le devis part avec le point de Tempé");
  ok(plat(await page.inputValue("#fl-frais")) === "1 600", "la case des frais : 1 600, calculés (" + await page.inputValue("#fl-frais") + ")");
  ok(/Calculés : 1 600 FCFA — 15,2 km : 600 FCFA jusqu'à 6 km \+ 10 km × 100 FCFA/.test(await texte(page, "#fl-frais-calcul")),
    "le détail : « 15,2 km : 600 FCFA jusqu'à 6 km + 10 km × 100 FCFA » (" + await texte(page, "#fl-frais-calcul") + ")");
  ok(/Livrer à : Tempé, Godomey/.test(await texte(page, "#fl-position-etat")), "« Livrer à : Tempé, Godomey »");
  ok(await page.inputValue("#fl-adresse") === "Tempé, Godomey", "l'adresse vide prend le nom du lieu");
  ok(serveur.routes.length === 1 && serveur.routes[0].origine && serveur.routes[0].origine.latitude === 6.37,
    "la distance par la route est demandée, de la boutique au client");
  ok(/13 600 FCFA/.test(await texte(page, "#fl-total")), "le total : 12 000 + 1 600 = 13 600");

  await capture(page, "faire-livrer", "#fl-position");
  await capture(page, "faire-livrer-frais", "#fl-livraison");
  /* L'équipe convient d'autre chose avec le client. */
  await page.fill("#fl-frais", "1000");
  await page.waitForTimeout(200);
  ok(/Reprendre ce montant/.test(await texte(page, "#fl-frais-calcul")), "frais tapés : « Reprendre ce montant » est proposé");
  ok(/13 000 FCFA/.test(await texte(page, "#fl-total")), "le total suit la saisie : 13 000");
  await page.click("#fl-reprendre");
  await page.waitForTimeout(200);
  ok(plat(await page.inputValue("#fl-frais")) === "1 600", "« Reprendre ce montant » : 1 600 de nouveau");
  await page.fill("#fl-frais", "1000");
  await page.fill("#fl-nom", "Koffi");
  await page.fill("#fl-tel", "0196700099");
  await page.fill("#fl-transaction", "MP241104.1200.B77777");
  await page.fill("#fl-montant", "13000");
  await page.dispatchEvent("#fl-montant", "input");
  await page.click("#fl-valider");
  await page.waitForSelector(".modale button, .confirmation button, [data-confirmer]", { timeout: 3000 }).catch(() => {});
  const confirmer = await page.$("text=Faire livrer >> nth=-1");
  if (confirmer) await confirmer.click().catch(() => {});
  await page.waitForTimeout(1200);
  const fl = serveur.appels.find((a) => a.fn === "faire_livrer");
  ok(fl && fl.corps.frais === 1000 && fl.corps.client.adresse === "Tempé, Godomey" &&
     fl.corps.destination && fl.corps.destination.latitude === TEMPE.latitude,
    "« faire_livrer » : les frais choisis (1 000), l'adresse « Tempé, Godomey », le point" +
    (fl ? "" : " — non appelé"));
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  /* Une base d'avant la 3.76.0 : pas de « livraison » dans le devis. */
  const devis = () => ({ sous_total: 12000, devise: "FCFA", vehicule: "moto" });
  const { page, ctx, erreurs } = await ouvrirAdmin({ moi: ADMBZ, hash: "#/faire-livrer", devis });
  await page.waitForSelector(".fl-produit", { timeout: 6000 }).catch(() => {});
  await page.click('[data-id="prod_casque"] .fl-ajouter');
  await page.click("#fl-suivant");
  await page.waitForSelector("#fl-client", { timeout: 4000 }).catch(() => {});
  await page.fill("#fl-adresse", "Fidjrossè, près du marché");
  await page.dispatchEvent("#fl-adresse", "change");
  await page.fill("#fl-lieu-q", "Tempé");
  await page.press("#fl-lieu-q", "Enter");
  await page.waitForSelector("#fl-chercher .lieu-resultat", { timeout: 5000 }).catch(() => {});
  await page.click("#fl-chercher .lieu-resultat");
  await page.waitForTimeout(1000);
  ok(/saisissez ceux convenus/.test(await texte(page, "#fl-frais-calcul")) && await page.inputValue("#fl-frais") === "",
    "une base d'avant : les frais restent à saisir, comme avant");
  ok(await page.inputValue("#fl-adresse") === "Fidjrossè, près du marché", "une adresse tapée n'est pas remplacée");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("3. Le livreur : le quartier de chaque lieu, un bouton par boutique");
{
  const courses = [
    partie("bou_a", "Alpha", { adresse: "Ganhi, rue du port", latitude: 6.37, longitude: 2.42 }, { etat: "preparee" }),
    partie("bou_b", "Bêta", { latitude: 6.38, longitude: 2.43 }, { etat: "preparee" }),
  ];
  const { page, ctx, erreurs, serveur } = await ouvrirAdmin({ moi: LIV, hash: "#/livraisons", courses });
  await page.waitForSelector(".lv-quartier:not([hidden])", { timeout: 6000 }).catch(() => {});
  await page.waitForTimeout(600);
  const a = await texte(page, '.lv-retrait[data-boutique="bou_a"] .lv-lieu');
  const b = await texte(page, '.lv-retrait[data-boutique="bou_b"] .lv-lieu');
  ok(/Ganhi, rue du port/.test(a) && !/Ganhi, Cotonou/.test(a),
    "Alpha : son adresse, et pas de quartier qui la répète (" + a.slice(0, 90) + ")");
  ok(/Missèbo, Cotonou/.test(b), "Bêta, sans adresse : « Missèbo, Cotonou », lu sur la carte");
  const client = await texte(page, ".lv-groupee > .lv-lieu");
  ok(/Sèdomey, Togoudo, Godomey/.test(client), "le client : « Sèdomey, Togoudo, Godomey »");
  ok(!/maps\.app\.goo\.gl/.test(client) && /Voir sur la carte/.test(client),
    "un lien de carte en guise d'adresse : « Voir sur la carte », pas le lien recopié");
  ok(serveur.lieu.filter((x) => x.action === "nommer").length === 3, "trois points, chacun demandé une fois");
  await capture(page, "livreur", ".lv-groupee");
  const boutons = await page.$$eval(".lv-recupere", (l) => l.map((x) => x.innerText.trim()));
  ok(boutons.length === 2 && /chez Alpha/.test(boutons[0]) && /chez Bêta/.test(boutons[1]),
    "un bouton par boutique : « Colis récupéré chez Alpha », « … chez Bêta »");
  await page.click('.lv-retrait[data-boutique="bou_a"] .lv-recupere');
  await page.waitForTimeout(700);
  const av = serveur.appels.filter((x) => x.fn === "avancer_livraison");
  ok(av.length === 1 && av[0].corps.boutique === "bou_a", "seule Alpha est marquée récupérée");
  ok(/Colis récupéré chez Alpha\. Reste à récupérer : Bêta\./.test(plat(await page.evaluate(() => (window.__toasts || []).join(" | ")))),
    "« Colis récupéré chez Alpha. Reste à récupérer : Bêta. »");
  /* Une seconde visite : les noms sont déjà sur le téléphone. */
  const avant = serveur.lieu.length;
  await page.evaluate(() => { location.hash = "#/compte"; });
  await page.waitForTimeout(500);
  await page.evaluate(() => { location.hash = "#/livraisons"; });
  await page.waitForTimeout(1200);
  ok(serveur.lieu.length === avant && /Missèbo, Cotonou/.test(await texte(page, '.lv-retrait[data-boutique="bou_b"]')),
    "revenu sur l'écran : les quartiers s'affichent sans redemander");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " échec(s)" : "\nLe nom des lieux : cherché, posé, lu par le livreur ✔");
process.exit(echecs ? 1 : 0);
