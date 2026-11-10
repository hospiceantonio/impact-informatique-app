/* =========================================================
   Accompagnements et espace vendeur (3.80.0)
   =========================================================
     1. LE CLIENT : « 1 Poulet + 2 Riz », le prix suit en direct, le
        panier garde les quantités, la commande n'envoie pas de prix ;
     2. un produit « Non disponible » reste visible mais ne se commande pas ;
     3. L'ÉQUIPE saisit les accompagnements d'un produit ;
     4. LE VENDEUR : photos, Disponible / Non disponible, son compte, sa
        déconnexion.

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-accompagnements-vendeur.mjs
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-accompagnements-vendeur.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const plat = (s) => String(s || "").replace(/[  ]/g, " ").replace(/\s+/g, " ").trim();
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

/* Les règles de publication : acceptées comme le ferait le gérant. */
const accepterLesRegles = () => {
  new MutationObserver(() => {
    const boite = document.querySelector(".conditions-ugc-boite");
    const accord = boite && boite.querySelector("[data-ugc-accord]");
    if (!accord || accord.checked) return;
    accord.checked = true;
    boite.querySelector("[data-ugc-valider]").click();
  }).observe(document, { childList: true, subtree: true });
};

const ADMIN = "33333333-3333-3333-3333-333333333333";
const SUPER = "11111111-1111-1111-1111-111111111111";
const V1 = "c7c7c7c7-0000-0000-0000-000000000001";
const BOU = (vendeurs) => ({ id: "bou_marche", nom: "Marché BIZZOO", secteur: "Mode", categorie_id: "cat_mode",
  icone: "magasin", couleur: "#0B5CF5", devise: "FCFA", indicatif: "229", actif: true, ordre: 1,
  taux_marge: 25, taux_revendeur: 5, revendeur_mode: "bizzoo", description: "", adresse: "Cotonou",
  tel: "0197000000", whatsapp: "0197000000", horaires: "", photos: [], telephones: [], adresses: [],
  vendeurs, part_vendeur_max: 80 });
const CATEGORIES = [{ id: "cat_mode", nom: "Mode", icone: "vetement", couleur: "#F59E0B",
  image: "", en_avant: true, ordre: 1, sous_categories: [
    { id: "sc_pagnes", categorie_id: "cat_mode", nom: "Pagnes", ordre: 1 }] }];
const PRODUITS = () => [
  { id: "prod_a", code: "100401", nom: "Pagne wax", reference: "IMP-0401", prix: 10000,
    categorie_id: "cat_mode", sous_categorie_id: "sc_pagnes", stock: 4, disponible: true, images: [],
    boutique_id: "bou_marche", cree_le: "2026-10-01T08:00:00Z", modifie_le: "2026-10-01T08:00:00Z",
    accompagnements: [{ id: "riz", nom: "Riz", prix: 1000, max: 3 }],
    produits_prive: [{ prix_grossiste: 8000, taux_marge: null, taux_revendeur: null, vendeur_id: V1, taux_vendeur: 80 }] },
  { id: "prod_ancien", code: "100402", nom: "Ancien sac", reference: "IMP-0402", prix: 5000,
    categorie_id: "cat_mode", sous_categorie_id: "sc_pagnes", stock: 2, disponible: true, images: [],
    boutique_id: "bou_marche", cree_le: "2026-09-01T08:00:00Z", modifie_le: "2026-09-01T08:00:00Z",
    produits_prive: [{ prix_grossiste: 4000, taux_marge: null, taux_revendeur: null, vendeur_id: null, taux_vendeur: null }] },
];
const VENDEURS = [{ id: V1, nom: "Afi", tel: "0197700001" }, { id: "c7c7c7c7-0000-0000-0000-000000000002", nom: "Bio", tel: "0197700002" }];
const ESPACE = {
  vendeur: { id: V1, nom: "Afi", tel: "0197700001" },
  solde: { ventes: 18000, gagne: 13640, a_venir: 8000, reverse: 10000, en_attente: 0, disponible: 3640,
    devise: "FCFA", reception: { tel: "0197700001", reseau: "MTN", titulaire: "Afi", maj_le: "2026-10-20T10:00:00Z" } },
  produits: [{ id: "prod_a", nom: "Pagne wax", code: "100401", boutique: "Marché BIZZOO", prix: 10000, taux: 80,
    part: 8000, stock: 4, sur_commande: false, vendus: 1, en_cours: 1, ventes: 10000, gagne: 8000,
    image: "https://exemple.invalid/pagne.jpg", en_pause: false },
    { id: "prod_b", nom: "Pagne bazin", code: "100403", boutique: "Marché BIZZOO", prix: 15000, taux: 80,
    part: 12000, stock: 2, sur_commande: false, vendus: 0, en_cours: 0, ventes: 0, gagne: 0,
    image: "", en_pause: true }],
  lignes: [{ le: "2026-10-28T09:00:00Z", numero: "BZ-000501", produit: "Pagne wax", quantite: 1, prix: 10000,
    taux: 80, part: 8000, statut: "disponible" }],
  versements: [{ id: 7, montant: 10000, etat: "valide", tel: "0197700001", reseau: "MTN",
    demande_le: "2026-10-27T09:00:00Z", decide_le: "2026-10-27T12:00:00Z", reference: "MP0001", motif: "" }],
};

async function ouvrir({ role = "administrateur", moi = ADMIN, hash = "#/produits", vendeurs = "multiples" } = {}) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 1600 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  page.on("dialog", (d) => d.accept());
  await page.addInitScript(accepterLesRegles);
  await page.addInitScript((m) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: b64({ alg: "HS256" }) + "." + b64({ sub: m }) + ".s",
      refresh_token: "r", expire_a: Date.now() + 3600000, email: "x@bizzoo.bj" }));
  }, moi);
  const produits = PRODUITS();
  const ecritures = [];
  const appels = [];
  await page.route("**/rest/v1/**", async (route) => {
    const req = route.request();
    const url = new URL(req.url());
    const c = url.pathname.replace(/^.*\/rest\/v1\//, "");
    const p = url.searchParams;
    const d = (x, status = 200) => route.fulfill({ status, contentType: "application/json", body: JSON.stringify(x) });
    let corps = null;
    try { corps = JSON.parse(req.postData() || "null"); } catch (_) { corps = null; }
    if (c.startsWith("rpc/")) {
      const fn = c.slice(4);
      appels.push({ fn, corps });
      if (fn === "vendeurs_liste") return d(VENDEURS);
      if (fn === "espace_vendeur") return d(ESPACE);
      if (fn === "ventes_vendeurs") return d([{ id: V1, nom: "Afi", tel: "0197700001", actif: true, produits: 1,
        ventes: 18000, part: 13640, commission: 4360, a_venir: 8000, reverse: 10000, en_attente: 0, disponible: 3640 }]);
      if (fn === "parts_vendeurs_historique_liste") return d([{ le: "2026-10-26T09:00:00Z", produit: "Pagne wax",
        boutique: "Marché BIZZOO", vendeur_avant: "Afi", vendeur_apres: "Afi", taux_avant: 75, taux_apres: 80,
        prix: 10000, par: "Chef" }]);
      if (fn === "reversements_vendeurs_liste") return d([{ id: 9, vendeur_id: V1, nom_vendeur: "Afi", montant: 3000,
        tel: "0197700001", reseau: "MTN", titulaire: "Afi", etat: "en_attente", demande_le: "2026-10-29T08:00:00Z",
        decide_par: "", decide_le: null, reference: "", motif: "" }]);
      if (fn === "demander_reversement_vendeur") return d(11);
      if (fn === "vendeur_produit_disponible") return d(!!(corps && corps.dispo));
      if (fn === "modifier_mon_nom") return d(String((corps && corps.nom) || "").trim());
      if (fn === "livraison_des_commandes") return d([]);
      return d(null);
    }
    if (req.method() !== "GET") {
      ecritures.push({ methode: req.method(), table: c, corps });
      if (c === "produits" && req.method() === "POST") {
        const ligne = { ...corps, code: "100499", produits_prive: [] };
        produits.push(ligne);
        return d([ligne]);
      }
      return d([]);
    }
    if (c.startsWith("profils")) {
      const moiFiche = { id: moi, email: "x@bizzoo.bj", role, actif: true, nom: "Moi",
        peut_modifier_produits: true, boutique_id: role === "administrateur" ? "bou_marche" : null };
      /* (3.72.0) La liste des comptes : l'équipe et deux vendeurs. */
      const voulu = (url.searchParams.get("id") || "").replace(/^eq\./, "");
      if (voulu) return d([moiFiche].filter((p) => p.id === voulu));
      return d([moiFiche,
        { id: "1e1e1e1e-0000-0000-0000-000000000001", email: "modo@bizzoo.bj", role: "moderateur", actif: true,
          nom: "Modo", peut_modifier_produits: true, boutique_id: "bou_marche" },
        ...VENDEURS.map((v) => ({ id: v.id, email: "", role: "vendeur", actif: true, nom: v.nom, tel: v.tel,
          peut_modifier_produits: true, boutique_id: null }))]);
    }
    if (c.startsWith("boutiques")) return d([BOU(vendeurs)]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    if (c.startsWith("categories")) return d(CATEGORIES);
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
  await page.evaluate((h) => { location.hash = h; }, hash);
  await page.waitForTimeout(1500);
  return { page, ctx, erreurs, ecritures, appels };
}
const texte = (page, sel) => page.evaluate((s) => (document.querySelector(s) || {}).innerText || "", sel).then(plat);
const toasts = (page) => page.evaluate(() =>
  [...document.querySelectorAll("#toasts .toast")].map((t) => t.textContent).join(" | ")).then(plat);
const sansErreur = (o) => ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));


/* ---------- L'application client ---------- */
const BOU_C = [{ id: "bou_resto", nom: "Maquis Chez Tanti", secteur: "Restauration", categorie_id: "cat_resto",
  icone: "couverts", couleur: "#F59E0B", devise: "FCFA", indicatif: "229", actif: true, ordre: 1, ouvertures: null }];
const PC = (id, nom, extra) => ({ id, code: id, nom, reference: id, prix: 5000, boutique_id: "bou_resto",
  categorie_id: "cat_resto", sous_categorie_id: null, stock: 20, disponible: true, sur_commande: false,
  images: [], video: "", en_avant: false, cree_le: "2026-09-01T10:00:00Z", modifie_le: "2026-09-01T10:00:00Z",
  ...(extra || {}) });
const PRODUITS_C = [
  PC("p_poulet", "Poulet braisé", { accompagnements: [{ id: "riz", nom: "Riz", prix: 1000, max: 3 },
                                                       { id: "alloco", nom: "Alloco", prix: 500, max: 2 }] }),
  PC("p_poisson", "Poisson braisé", { en_pause: true }),
];
async function ouvrirClient(hash, panier) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2200 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((pan) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.removeItem("impact-boutique");
    if (pan) localStorage.setItem("bizzoo-panier", JSON.stringify(pan));
  }, panier || null);
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.route("**/rest/v1/**", (r) => {
    const c = new URL(r.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("boutiques")) return d(BOU_C);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    if (c.startsWith("produits")) return d(PRODUITS_C);
    if (c.startsWith("categories")) return d([{ id: "cat_resto", nom: "Restauration", ordre: 1, sous_categories: [] }]);
    if (c.startsWith("paiement")) return d([{ id: 1, actif: false, fournisseur: "feexpay" }]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html" + (hash || ""));
  await page.waitForTimeout(2500);
  return { ctx, page, erreurs };
}
const vue = (page) => page.evaluate(() => document.getElementById("vue").innerText).then(plat);

titre("1. (Client) Les accompagnements : le prix suit en direct");
{
  const o = await ouvrirClient("#/produit/p_poulet");
  ok(!!(await o.page.$("#p-acc")) && /Riz/.test(await texte(o.page, "#p-acc")) && /Alloco/.test(await texte(o.page, "#p-acc")),
    "la fiche propose Riz et Alloco");
  ok(/Prix : 5 000 FCFA/.test(await texte(o.page, "#p-acc-total")), "au départ : 5 000 FCFA");
  const plus = (id) => o.page.click('.fiche-acc-ligne[data-acc="' + id + '"] [data-acc-plus]');
  await plus("riz"); await plus("riz");
  ok(/5 000 FCFA \+ 2 000 FCFA = 7 000 FCFA/.test(await texte(o.page, "#p-acc-total")),
    "2 Riz : « 5 000 + 2 000 = 7 000 FCFA », en direct (" + await texte(o.page, "#p-acc-total") + ")");
  await plus("riz"); await plus("riz");
  ok(/3 Riz au plus/.test(await toasts(o.page)) &&
     (await texte(o.page, '.fiche-acc-ligne[data-acc="riz"] [data-acc-qte]')) === "3", "pas plus que le maximum (3)");
  await o.page.click('.fiche-acc-ligne[data-acc="riz"] [data-acc-moins]');
  await o.page.click("#p-ajouter");
  await o.page.waitForTimeout(400);
  const pan = await o.page.evaluate(() => JSON.parse(localStorage.getItem("bizzoo-panier") || "[]"));
  ok(pan.length === 1 && pan[0].acc && pan[0].acc.riz === 2, "le panier garde « 2 Riz »");
  ok(await o.page.evaluate(() => JSON.stringify(Panier.articles())) ===
     JSON.stringify([{ produit_id: "p_poulet", quantite: 1, accompagnements: [{ id: "riz", quantite: 2 }] }]),
    "à la commande : le produit, et les quantités de ses accompagnements — pas de prix");
  /* Le même plat sans accompagnement : une autre ligne. */
  await o.page.evaluate(() => Panier.ajouter("p_poulet", 1));
  await o.page.evaluate(() => { location.hash = "#/panier"; });
  await o.page.waitForTimeout(1200);
  const t = await vue(o.page);
  ok(/\+ 2 Riz/.test(t) && /7 000 FCFA/.test(t) && /5 000 FCFA/.test(t), "le panier : « + 2 Riz » à 7 000, et le plat seul à 5 000");
  ok(/12 000 FCFA/.test(t), "le total compte les accompagnements (12 000)");
  ok(await o.page.evaluate(() => Panier.lignes().length) === 2, "deux lignes : avec et sans accompagnement");
  /* « + » sur la ligne aux accompagnements : elle seule monte. */
  await o.page.click('[data-panier-action="plus"][data-produit="p_poulet~riz:2"]');
  await o.page.waitForTimeout(500);
  ok(await o.page.evaluate(() => Panier.quantiteDe("p_poulet~riz:2")) === 2 &&
     await o.page.evaluate(() => Panier.quantiteDe("p_poulet")) === 1, "chaque ligne garde sa quantité");
  ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));
  await o.ctx.close();
}

titre("2. (Client) Un produit « Non disponible » : visible, pas commandable");
{
  const o = await ouvrirClient("#/produit/p_poisson");
  ok(!!(await o.page.$("#p-fermee")) && !(await o.page.$("#p-ajouter")) &&
     /Ce produit n'est pas disponible pour le moment/.test(await texte(o.page, "#p-fermee")) &&
     /Indisponible pour le moment/.test(await texte(o.page, "#p-fermee .btn")),
    "la fiche s'ouvre, bouton éteint « Indisponible pour le moment »");
  await o.page.evaluate(() => { location.hash = "#/"; });
  await o.page.waitForTimeout(1200);
  ok(await o.page.evaluate(() => Catalogue.produitsDeLEnseigne().map((p) => p.id).join(",")) === "p_poulet,p_poisson",
    "il reste dans le catalogue, après les produits commandables");
  await o.ctx.close();
  const o2 = await ouvrirClient("#/panier", [{ produitId: "p_poisson", quantite: 1 }, { produitId: "p_poulet", quantite: 1 }]);
  ok(!!(await o2.page.$("#pa-indisponibles")) && /Cet article n'est pas disponible pour le moment/.test(await texte(o2.page, "#pa-indisponibles")) &&
     await o2.page.evaluate(() => document.querySelector("#pa-commander").disabled),
    "le panier le dit, et la commande attend");
  ok(!o2.erreurs.length, "aucune erreur JavaScript" + (o2.erreurs.length ? " : " + o2.erreurs[0] : ""));
  await o2.ctx.close();
}

titre("3. (Admin) L'équipe saisit les accompagnements");
{
  const o = await ouvrir({ role: "superadministrateur", moi: SUPER, hash: "#/produit/prod_a/modifier" });
  await o.page.waitForSelector("#p-enregistrer", { timeout: 5000 }).catch(() => {});
  ok(!!(await o.page.$("#p-accompagnements")) && await o.page.$$eval(".p-acc-ligne", (l) => l.length) === 1,
    "la carte « Accompagnements », avec Riz");
  await o.page.click("#p-acc-ajouter");
  const lignes = await o.page.$$(".p-acc-ligne");
  const derniere = lignes[lignes.length - 1];
  await (await derniere.$(".p-acc-nom")).fill("Alloco");
  await (await derniere.$(".p-acc-prix")).fill("500");
  await (await derniere.$(".p-acc-max")).fill("2");
  await o.page.click("#p-enregistrer");
  await o.page.waitForTimeout(1500);
  const ecr = o.ecritures.find((x) => x.table.startsWith("produits") && x.methode === "PATCH" && x.corps && x.corps.accompagnements);
  ok(ecr && JSON.stringify(ecr.corps.accompagnements) ===
     JSON.stringify([{ id: "riz", nom: "Riz", prix: 1000, max: 3 }, { id: "alloco", nom: "Alloco", prix: 500, max: 2 }]),
    "ils partent avec le produit : Riz (gardé) et Alloco (nouveau)" + (ecr ? "" : " — rien n'est parti"));
  sansErreur(o);
  await o.ctx.close();
}

titre("4. (Vendeur) Photos, Disponible / Non disponible, compte, déconnexion");
{
  const o = await ouvrir({ role: "vendeur", moi: V1, hash: "#/ventes" });
  await o.page.waitForTimeout(800);
  ok(await o.page.$$eval("#vd-produits img.vd-photo", (x) => x.length) === 1 &&
     await o.page.$$eval("#vd-produits .vd-photo-vide", (x) => x.length) === 1, "la photo de chaque produit (ou son icône)");
  ok(/Disponible/.test(await texte(o.page, '[data-produit="prod_a"] .vd-dispo')) &&
     /Non disponible/.test(await texte(o.page, '[data-produit="prod_b"] .vd-dispo')), "l'état de chacun");
  await o.page.click('[data-produit="prod_a"] .vd-dispo');
  await o.page.waitForTimeout(700);
  const a = o.appels.find((x) => x.fn === "vendeur_produit_disponible");
  ok(a && a.corps.produit === "prod_a" && a.corps.dispo === false, "un geste : « Pagne wax » non disponible");
  ok(!!(await o.page.$("#vd-compte")) && !!(await o.page.$("#vd-deconnexion")) && !!(await o.page.$("#vd-profil")),
    "« Mon compte » en haut, « Modifier mon profil » et « Se déconnecter » en bas");
  await o.page.click("#vd-profil");
  await o.page.waitForTimeout(1200);
  ok(!!(await o.page.$("#mc-nom")) && !!(await o.page.$("#mc-mdp")) && !!(await o.page.$("#mc-deconnexion")),
    "Mon compte : son nom, son mot de passe, la déconnexion");
  await o.page.fill("#mc-nom", "Afi Pagnes");
  await o.page.click("#mc-nom-enregistrer");
  await o.page.waitForTimeout(700);
  const n = o.appels.find((x) => x.fn === "modifier_mon_nom");
  ok(n && n.corps.nom === "Afi Pagnes" && /Nom enregistré : Afi Pagnes/.test(await toasts(o.page)), "« Nom enregistré : Afi Pagnes »");
  sansErreur(o);
  await o.ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " constat(s) en échec.\n"
  : "\nAccompagnements et espace vendeur tiennent ✔\n");
process.exit(echecs ? 1 : 0);
