/* =========================================================
   Les boutiques à vendeurs multiples, à l'écran (3.70.0)
   =========================================================
   La base calcule et fige la part de chaque vendeur (supabase/tests/
   …-vendeurs-multiples.sql). Ce banc regarde les écrans :

     1. LA LISTE DES PRODUITS d'une boutique à vendeurs multiples dit
        combien n'ont pas encore leur vendeur, et les filtre ;
     2. LE FORMULAIRE : prix de vente, vendeur, part — et ce que touche
        le vendeur pendant la saisie ; sans vendeur ou au-delà de la
        borne, rien ne part ; sinon le produit part avec son prix, et sa
        ligne privée avec le vendeur et la part ;
     3. LA FICHE d'un produit de vendeur dit à qui il est, et sa part ;
     4. une boutique à vendeur unique garde son formulaire d'avant ;
     5. LE SUPERADMINISTRATEUR : le type dans la fiche boutique, la tuile
        « Vendeurs », le tableau des vendeurs, et leurs demandes dans
        « Reversements » ;
     6. LE VENDEUR n'a qu'un écran, « Mes ventes » : son solde, ses
        produits, ses ventes ; il demande un versement.

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-vendeurs-multiples.mjs
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-vendeurs-multiples.mjs");
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
    part: 8000, stock: 4, sur_commande: false, vendus: 1, en_cours: 1, ventes: 10000, gagne: 8000 }],
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

titre("1. La liste : les produits sans vendeur");
{
  const o = await ouvrir();
  ok(/1 produit sans vendeur/.test(await texte(o.page, "#produits-sans-vendeur")),
    "« 1 produit sans vendeur », et quoi faire (" + (await texte(o.page, "#produits-sans-vendeur")).slice(0, 60) + "…)");
  await o.page.click('[data-filtre="sansvendeur"]');
  await o.page.waitForTimeout(300);
  const t = await texte(o.page, "#produits-liste");
  ok(/Ancien sac/.test(t) && !/Pagne wax/.test(t), "le filtre « Sans vendeur » ne garde que lui");
  sansErreur(o);
  await o.ctx.close();
}

titre("2. Le formulaire : prix de vente, vendeur, part");
{
  const o = await ouvrir({ hash: "#/produit/nouveau" });
  await o.page.waitForSelector("#p-enregistrer", { timeout: 5000 });
  ok(await o.page.$("#p-prix-vente") && await o.page.$("#p-vendeur") && await o.page.$("#p-taux-vendeur") &&
     !(await o.page.$("#p-grossiste")), "prix de vente, vendeur et part — plus de « Prix BIZZOO » à saisir");
  ok(await o.page.evaluate(() => [...document.querySelectorAll("#p-vendeur option")].map((x) => x.textContent).join("|"))
       .then((s) => /Afi — 0197700001/.test(s) && /Bio/.test(s)), "les comptes vendeurs, avec leur numéro");
  await o.page.fill("#p-nom", "Sac en raphia");
  await o.page.selectOption("#p-souscategorie", "sc_pagnes");
  await o.page.fill("#p-prix-vente", "10000");
  await o.page.fill("#p-taux-vendeur", "80");
  await o.page.waitForTimeout(400);
  ok(/Le vendeur reçoit 8 000 FCFA par pièce, BIZZOO garde 2 000 FCFA/.test(await texte(o.page, "#p-marge")),
    "pendant la saisie : « Le vendeur reçoit 8 000 FCFA par pièce, BIZZOO garde 2 000 FCFA »");
  await o.page.click("#p-enregistrer");
  await o.page.waitForTimeout(700);
  ok(/Choisissez le vendeur/.test(await toasts(o.page)) && !o.ecritures.some((x) => x.table === "produits"),
    "sans vendeur : refusé à l'écran, rien ne part");
  await o.page.selectOption("#p-vendeur", V1);
  await o.page.fill("#p-taux-vendeur", "90");
  await o.page.click("#p-enregistrer");
  await o.page.waitForTimeout(700);
  ok(/entre 1 et 80 %/.test(await toasts(o.page)) && !o.ecritures.some((x) => x.table === "produits"),
    "une part de 90 % : au-delà de la borne (80 %), rien ne part");
  await o.page.fill("#p-taux-vendeur", "75,5");
  await o.page.click("#p-enregistrer");
  await o.page.waitForTimeout(1500);
  const prod = o.ecritures.find((x) => x.table === "produits" && x.methode === "POST");
  const prive = o.ecritures.find((x) => x.table.startsWith("produits_prive"));
  ok(prod && prod.corps.prix === 10000, "le produit part au prix de vente saisi (10 000)");
  ok(prive && prive.corps.vendeur_id === V1 && Number(prive.corps.taux_vendeur) === 75.5 &&
     prive.corps.prix_grossiste === 7550,
    "sa ligne privée : le vendeur, 75,5 %, et sa part 7 550 (que la base recalcule)");
  sansErreur(o);
  await o.ctx.close();
}

titre("3. La fiche d'un produit de vendeur");
{
  const o = await ouvrir({ hash: "#/produit/prod_a" });
  await o.page.waitForTimeout(800);
  const t = await texte(o.page, "#fiche-vendeur");
  ok(/Vendeur propriétaire Afi/.test(t) && /Part du vendeur 80 %/.test(t) &&
     /Le vendeur reçoit 8 000 FCFA/.test(t) && /BIZZOO garde 2 000 FCFA/.test(t),
    "« Afi », 80 %, 8 000 pour lui, 2 000 pour BIZZOO");
  sansErreur(o);
  await o.ctx.close();
}

titre("4. Une boutique à vendeur unique garde son formulaire");
{
  const o = await ouvrir({ hash: "#/produit/nouveau", vendeurs: "unique" });
  await o.page.waitForSelector("#p-enregistrer", { timeout: 5000 });
  ok(await o.page.$("#p-grossiste") && !(await o.page.$("#p-vendeur")), "le prix BIZZOO, pas de vendeur");
  ok(!(await o.page.$("#produits-sans-vendeur")), "et aucune alerte « sans vendeur »");
  await o.ctx.close();
}

titre("5. Le superadministrateur");
{
  const o = await ouvrir({ role: "superadministrateur", moi: SUPER, hash: "#/" });
  await o.page.waitForTimeout(600);
  ok(!!(await o.page.$("#ac-vendeurs")), "la tuile « Vendeurs » sur l'accueil");
  await o.page.evaluate(() => { location.hash = "#/vendeurs"; });
  await o.page.waitForTimeout(1500);
  const t = await texte(o.page, "#vue");
  ok(/Commission de BIZZOO/i.test(t) && /4 360 FCFA/.test(t) && /Afi/.test(t) && /sa part 13 640 FCFA/.test(t),
    "le tableau : Afi, sa part 13 640, la commission de BIZZOO 4 360");
  ok(/Pagne wax/.test(await o.page.evaluate(() => document.querySelector("#vv-historique").textContent)),
    "l'historique des parts (75 % → 80 %)");
  await o.page.click("[data-vendeur]");
  await o.page.waitForTimeout(900);
  ok(/Ventes livrées/.test(await texte(o.page, "#feuille-corps")) && !(await o.page.$("#feuille-corps #vd-demander")),
    "toucher un vendeur ouvre son espace — sans bouton de demande");
  await o.page.evaluate(() => UI.fermerFeuille());
  await o.page.waitForTimeout(300);
  /* (3.72.0) Le compte du vendeur se gère ici. */
  ok(await o.page.$$eval("#vv-liste [data-compte]", (b) => b.length) >= 1, "(3.72.0) chaque vendeur a son crayon « compte »");
  await o.page.click("#vv-liste [data-compte]");
  await o.page.waitForTimeout(600);
  const fiche = await o.page.evaluate(() => ({
    roles: [...document.querySelectorAll("#cp-role option")].map((x) => x.value),
    boutiqueCachee: !document.querySelector("#cp-zone-boutique") || document.querySelector("#cp-zone-boutique").hidden,
    nom: (document.querySelector("#cp-nom") || {}).value }));
  ok(fiche.roles.length === 1 && fiche.roles[0] === "vendeur" && fiche.boutiqueCachee && fiche.nom === "Afi",
    "(3.72.0) sa fiche : vendeur et rien d'autre, sans boutique (" + JSON.stringify(fiche) + ")");
  await o.page.evaluate(() => UI.fermerFeuille());
  await o.page.evaluate(() => { location.hash = "#/comptes"; });
  await o.page.waitForTimeout(1500);
  const equipe = await texte(o.page, "#vue");
  ok(!!(await o.page.$("#cp-vendeurs")) && /Les vendeurs \(2\)/i.test(equipe),
    "(3.72.0) « Comptes » : une carte « Les vendeurs (2) » vers leur écran");
  ok(/Modo/.test(equipe) && !(await o.page.$$eval(".carte .compte-ligne", (l) => l.some((x) => /Afi|Bio/.test(x.innerText)))),
    "(3.72.0) et ils ne sont plus mêlés à l'équipe");
  await o.page.click("#cp-vendeurs");
  await o.page.waitForTimeout(1200);
  ok(/#\/vendeurs$/.test(await o.page.evaluate(() => location.hash)), "(3.72.0) la carte mène à l'écran « Vendeurs »");
  await o.page.evaluate(() => { location.hash = "#/reversements"; });
  await o.page.waitForTimeout(1500);
  ok(/Vendeur — Afi/.test(await texte(o.page, "#vue")) && !!(await o.page.$('[data-valider="9"][data-vendeur]')),
    "« Reversements » : la demande du vendeur, à valider");
  await o.page.evaluate(() => { location.hash = "#/boutiques"; });
  await o.page.waitForTimeout(1200);
  const ouvert = await o.page.evaluate(() => {
    const b = document.querySelector("[data-modifier], [data-boutique]");
    if (b) b.click();
    return !!b;
  });
  await o.page.waitForTimeout(800);
  ok(ouvert && !!(await o.page.$("#bq-vendeurs")) &&
     await o.page.evaluate(() => document.querySelector("#bq-vendeurs").value) === "multiples",
    "la fiche boutique : « Type de boutique », ici à vendeurs multiples");
  sansErreur(o);
  await o.ctx.close();
}

titre("6. Le vendeur : un seul écran, « Mes ventes »");
{
  const o = await ouvrir({ role: "vendeur", moi: V1, hash: "#/" });
  await o.page.waitForTimeout(800);
  ok(await o.page.evaluate(() => location.hash) === "#/ventes", "l'accueil le mène à « Mes ventes »");
  const t = await texte(o.page, "#vue");
  ok(/3 640 FCFA/.test(t) && /Ventes livrées 18 000 FCFA/.test(t) && /En attente \(payé, pas encore livré\) 8 000 FCFA/.test(t),
    "son solde : 3 640 disponibles, 18 000 de ventes, 8 000 en attente");
  ok(/Pagne wax/.test(t) && /part 80 % = 8 000 FCFA/.test(t) && /Vendus : 1/.test(t), "ses produits : part, vendus");
  ok(/BZ-000501/.test(t) && /Disponible/.test(t) && !/Rosine|Godomey/.test(t), "ses ventes, sans aucun client");
  ok(await o.page.evaluate(() => getComputedStyle(document.getElementById("tabbar")).display === "none"),
    "pas de barre du bas : il n'a que cet écran");
  await o.page.evaluate(() => { location.hash = "#/produits"; });
  await o.page.waitForTimeout(1200);
  ok(await o.page.evaluate(() => location.hash) === "#/ventes", "« Produits » : renvoyé à « Mes ventes »");
  await o.page.click("#vd-demander");
  await o.page.waitForTimeout(500);
  await o.page.fill("#gn-montant", "3000");
  await o.page.click("#gn-envoyer");
  await o.page.waitForTimeout(900);
  const dem = o.appels.find((a) => a.fn === "demander_reversement_vendeur");
  ok(dem && dem.corps.montant === 3000, "« Demander un versement » : 3 000, à BIZZOO");
  sansErreur(o);
  await o.ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " constat(s) en échec.\n"
  : "\nLes vendeurs multiples tiennent, de la boutique au vendeur ✔\n");
process.exit(echecs ? 1 : 0);
