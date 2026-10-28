/* =========================================================
   « Faire livrer » : une commande prise sur WhatsApp (3.68.0)
   =========================================================
   La base crée, fait payer et propose la course
   (supabase/tests/99zzz…-commande-whatsapp.sql). Ce banc regarde
   BIZZOO Admin :

     1. « Commandes » propose « Faire livrer une commande WhatsApp » à
        l'équipe de BIZZOO qui suit les commandes — pas à une boutique ;
     2. on choisit les produits ; « Faire livrer » montre le compte ;
     3. le client ; la position, facultative ; les FRAIS saisis (BIZZOO
        les décide pour ces commandes) ; le total = articles (de la base)
        + frais ; le montant prérempli ;
     4. ce qui manque, ou un montant trop court, se dit sans rien envoyer ;
     5. validé : « faire_livrer » part avec tout, et l'écran ouvre la
        commande ;
     6. la commande WhatsApp se reconnaît dans la liste.
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-faire-livrer.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const plat = (s) => String(s || "").replace(/[  ]/g, " ").replace(/\s+/g, " ").trim();
const F = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ") + " FCFA";

const TUILE = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=", "base64");

const ADMBZ = "d7d7d7d7-0000-0000-0000-000000000001";
const CHEF = "22222222-2222-2222-2222-222222222222";
const BIO = "d7d7d7d7-0000-0000-0000-000000000005";
const SUPER = "11111111-1111-1111-1111-111111111111";
const PROFILS = {
  [ADMBZ]: { id: ADMBZ, email: "awa@bizzoo.bj", nom: "Awa", role: "administrateur", actif: true,
    boutique_id: null, peut_commandes: true, peut_modifier_produits: true, peut_faire_livrer: true },
  /* Bio suit les commandes, mais n'a pas reçu « Faire livrer ». */
  [BIO]: { id: BIO, email: "bio@bizzoo.bj", nom: "Bio", role: "administrateur", actif: true,
    boutique_id: null, peut_commandes: true, peut_modifier_produits: true, peut_faire_livrer: false },
  [SUPER]: { id: SUPER, email: "chef@bizzoo.bj", nom: "Super", role: "superadministrateur", actif: true,
    boutique_id: null, peut_commandes: true, peut_modifier_produits: true },
  [CHEF]: { id: CHEF, email: "chef@alpha.bj", nom: "Chef", role: "administrateur", actif: true,
    boutique_id: "bou_a", peut_commandes: true, peut_modifier_produits: true },
};
const BOUTIQUES = [
  { id: "bou_a", nom: "Alpha", devise: "FCFA", indicatif: "229", actif: true, ordre: 1,
    adresse: "Ganhi, rue du port", tel: "0196000011" },
  { id: "bou_b", nom: "Bêta", devise: "FCFA", indicatif: "229", actif: true, ordre: 2 },
];
const PRODUITS = [
  { id: "prod_casque", boutique_id: "bou_a", nom: "Casque", code: "0001", prix: 12000, stock: 5, disponible: true,
    images: [], cree_le: "2026-10-01T08:00:00Z", modifie_le: "2026-10-02T08:00:00Z" },
  { id: "prod_chargeur", boutique_id: "bou_b", nom: "Chargeur", code: "0002", prix: 4000, stock: 9, disponible: true,
    images: [], cree_le: "2026-10-01T08:00:00Z", modifie_le: "2026-10-03T08:00:00Z" },
  { id: "prod_cache", boutique_id: "bou_b", nom: "Article masqué", code: "0003", prix: 1000, stock: 9,
    disponible: true, masque: true, images: [], cree_le: "2026-10-01T08:00:00Z", modifie_le: "2026-10-01T08:00:00Z" },
];
const WHATSAPP = { id: "cmd_wa", numero: "BZ-000201", etat: "payee", origine: "whatsapp", confirme_par: "Awa",
  client_nom: "Koffi", client_tel: "0196700099", client_indicatif: "229", client_adresse: "Fidjrossè",
  total: 21400, acompte: 21400, verse: 21400, frais_livraison: 1400, devise: "FCFA",
  lieu_retrait: "Alpha, Ganhi — demander Rémi",
  transaction_id: "MP241027.1530.A12345", cree_le: "2026-10-27T09:00:00Z", paye_le: "2026-10-27T09:00:00Z",
  restes: { reste: 0 },
  commande_lignes: [{ id: "l1", boutique_id: "bou_a", produit_id: "prod_casque", nom: "Casque", code: "0001",
    reference: "", prix: 12000, quantite: 1, etat: "nouvelle", confirme_le: null }] };

async function ouvrir({ moi, hash }) {
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
      refresh_token: "r", expire_a: Date.now() + 3600000, email: a.email }));
  }, { moi, email: PROFILS[moi].email });
  await page.route("https://tile.openstreetmap.org/**",
    (r) => r.fulfill({ status: 200, contentType: "image/png", body: TUILE }));
  const serveur = { appels: [] };
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x, statut = 200) => route.fulfill({ status: statut, contentType: "application/json", body: JSON.stringify(x) });
    const corps = (() => { try { return req.postDataJSON(); } catch (_) { return null; } })();
    if (c.startsWith("rpc/")) {
      const fn = c.slice(4);
      serveur.appels.push({ fn, corps });
      if (fn === "devis_faire_livrer") {
        const sous = (corps.articles || []).reduce((s, a) =>
          s + (PRODUITS.find((p) => p.id === a.produit_id) || { prix: 0 }).prix * a.quantite, 0);
        return d({ sous_total: sous, devise: "FCFA", vehicule: "moto" });
      }
      if (fn === "faire_livrer") return d({ id: "cmd_wa", numero: "BZ-000201", total: 21400, client_relie: false,
        lieu_retrait: ((corps.client || {}).retrait || "").trim() });
      return d(null);
    }
    if (req.method() !== "GET") {
      serveur.appels.push({ fn: req.method() + " " + c, corps, chemin: c + u.search });
      const id = (u.searchParams.get("id") || "").replace(/^eq\./, "");
      if (req.method() === "PATCH" && PROFILS[id]) return d([{ ...PROFILS[id], ...corps }]);
      return route.fulfill({ status: 204, body: "" });
    }
    if (c.startsWith("profils")) {
      const id = (u.searchParams.get("id") || "").replace(/^eq\./, "");
      return d(id ? [PROFILS[id]].filter(Boolean) : Object.values(PROFILS));
    }
    if (c.startsWith("paiement")) {
      return d([{ id: 1, actif: true, fournisseur: "feexpay", livraison_latitude: 6.3654, livraison_longitude: 2.4183,
        livraison_rayon_km: 10, livraison_coef: 1.3, moto_forfait: 1000, moto_prix_km: 100,
        tricycle_forfait: 4000, tricycle_prix_km: 500, taux_livreur: 80 }]);
    }
    if (c.startsWith("produits")) return d(PRODUITS);
    if (c.startsWith("commandes")) return d([WHATSAPP]);
    if (c.startsWith("boutiques")) return d(BOUTIQUES);
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
/* CAPTURES=<dossier> : des images de chaque étape, pour la documentation. */
const capture = async (page, nom, sel) => {
  if (!process.env.CAPTURES) return;
  const cible = sel ? await page.$(sel) : null;
  await (cible || page).screenshot({ path: process.env.CAPTURES + "/" + nom + ".png", ...(cible ? {} : { fullPage: false }) });
};
const texte = (page, sel) => page.evaluate((s) => (document.querySelector(s) || {}).textContent || "", sel).then(plat);

titre("1. « Faire livrer » s'ouvre depuis les commandes — pour l'équipe de BIZZOO");
{
  const { page, ctx, erreurs } = await ouvrir({ moi: ADMBZ, hash: "#/commandes" });
  ok(await page.$("#cmd-faire-livrer") !== null, "l'administrateur de BIZZOO voit « Faire livrer une commande WhatsApp »");
  await capture(page, "1-commandes");
  const carte = plat(await page.evaluate(() => (document.querySelector('[data-commande="cmd_wa"]') || {}).textContent || ""));
  ok(/WhatsApp/.test(carte) && /payée sur WhatsApp, saisie par Awa/.test(carte),
    "une commande WhatsApp le dit, avec qui l'a saisie (" + carte.slice(0, 80) + "…)");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  const { page, ctx } = await ouvrir({ moi: CHEF, hash: "#/commandes" });
  ok(await page.$("#cmd-faire-livrer") === null, "l'administrateur d'une boutique ne l'a pas");
  await page.evaluate(() => { location.hash = "#/faire-livrer"; });
  await page.waitForTimeout(1200);
  ok(await page.evaluate(() => location.hash) !== "#/faire-livrer", "et l'écran lui est fermé s'il y va quand même");
  await ctx.close();
}

{
  /* Bio suit les commandes, mais n'a pas le droit « Faire livrer ». */
  const { page, ctx } = await ouvrir({ moi: BIO, hash: "#/commandes" });
  ok(await page.$("#cmd-faire-livrer") === null, "un administrateur de BIZZOO SANS le droit ne voit pas l'option");
  await page.evaluate(() => { location.hash = "#/faire-livrer"; });
  await page.waitForTimeout(1200);
  ok(await page.evaluate(() => location.hash) !== "#/faire-livrer", "et l'écran lui est fermé s'il tape l'adresse");
  await ctx.close();
}
{
  const { page, ctx } = await ouvrir({ moi: ADMBZ, hash: "#/" });
  ok(await page.$('a[href="#/faire-livrer"]') !== null, "Awa, qui a le droit, l'a aussi depuis l'accueil");
  await ctx.close();
}

titre("1 bis. Le superadministrateur accorde le droit, et lui seul");
{
  const { page, ctx, serveur } = await ouvrir({ moi: SUPER, hash: "#/comptes" });
  await page.click(`[data-compte="${BIO}"]`).catch(() => {});
  await page.waitForTimeout(600);
  ok(await page.$("#cp-d-faire-livrer") !== null && !(await page.$eval("#cp-d-faire-livrer", (b) => b.checked).catch(() => true)),
    "dans la fiche de Bio : l'interrupteur « Faire livrer », éteint");
  await page.$eval("#cp-zone-enseigne", (z) => z.scrollIntoView()).catch(() => {});
  await capture(page, "4-droit-faire-livrer", "#cp-zone-enseigne");
  await page.click('label[for="cp-d-faire-livrer"]');
  await page.click("#cp-enregistrer");
  await page.waitForTimeout(900);
  const ecrit = serveur.appels.find((a) => /^PATCH profils/.test(a.fn) && a.corps && "peut_faire_livrer" in a.corps);
  if (!ecrit) console.log("    (appels : " + JSON.stringify(serveur.appels.filter((a) => !/^rpc|GET/.test(a.fn))).slice(0, 400) +
    " ; coché : " + await page.$eval("#cp-d-faire-livrer", (b) => b.checked).catch(() => "?") +
    " ; toasts : " + plat(await page.evaluate(() => (document.querySelector("#toasts") || {}).textContent || "")) + ")");
  ok(ecrit && ecrit.corps.peut_faire_livrer === true && ecrit.chemin.includes(BIO), "allumé et enregistré : le droit part vers la base");
  await ctx.close();
}

titre("2. Choisir les produits");
const { page, ctx, erreurs, serveur } = await ouvrir({ moi: ADMBZ, hash: "#/faire-livrer" });
await page.waitForSelector(".fl-produit", { timeout: 6000 }).catch(() => {});
const noms = await page.$$eval(".fl-produit strong", (l) => l.map((x) => x.textContent));
ok(noms.includes("Casque") && noms.includes("Chargeur") && !noms.includes("Article masqué"),
  "les produits de toutes les boutiques, sans le produit masqué (" + noms.join(", ") + ")");
ok(/Choisissez les produits/.test(await texte(page, "#fl-barre")), "rien de choisi : pas encore de « Faire livrer »");
await page.click('[data-id="prod_casque"] .fl-ajouter');
await page.click('[data-id="prod_chargeur"] .fl-ajouter');
await page.click('[data-id="prod_chargeur"] .fl-plus');
await page.fill("#fl-recherche", "cas");
await page.waitForTimeout(200);
ok(/3 articles/.test(await texte(page, "#fl-barre")) && /20 000 FCFA hors livraison/.test(await texte(page, "#fl-barre")),
  "« 3 articles · 20 000 FCFA hors livraison »");
ok((await page.$$(".fl-produit.fl-choisi")).length === 2, "les produits choisis restent visibles pendant la recherche");
await page.fill("#fl-recherche", "");
await page.waitForTimeout(200);
await capture(page, "2-produits");
await page.click("#fl-suivant");
await page.waitForSelector("#fl-client", { timeout: 4000 }).catch(() => {});

titre("3. Le client, les frais saisis, le total");
const recap = await texte(page, "#fl-recap");
ok(/1 × Casque/.test(recap) && /2 × Chargeur/.test(recap) && /Bêta/.test(recap), "le récapitulatif, boutique par boutique");
await page.waitForSelector("#fl-total", { timeout: 4000 }).catch(() => {});
const serre = (s) => s.replace(/\s+/g, "");
ok(/Articles20000FCFA/.test(serre(await texte(page, "#fl-devis"))) && /àsaisir/.test(serre(await texte(page, "#fl-devis"))) &&
   (await texte(page, "#fl-total")) === "—", "les articles (20 000, de la base) ; les frais restent à saisir");
ok(/Où livrer \(facultatif\)/.test(await texte(page, "#fl-position")) &&
   /Aucune position/.test(await texte(page, "#fl-position-etat")), "la position est facultative");
ok(/touchera 80 %/.test(await texte(page, "#fl-livraison")), "« le livreur en touchera 80 % » est dit à la saisie des frais");
/* (3.70.0) Où le livreur récupère la commande : proposé d'après les
   boutiques des produits, une ligne par boutique. */
const propose = await page.inputValue("#fl-retrait");
ok(propose === "Alpha — Ganhi, rue du port — Tél. +229 0196000011\nBêta",
  "« Où récupérer » est proposé d'après les boutiques des produits (" + JSON.stringify(propose) + ")");
ok(/Où le livreur récupère la commande/.test(await texte(page, "#fl-retrait-carte")), "la case a son titre");
ok(await page.getAttribute("#fl-retrait", "maxlength") === "500", "500 caractères au plus, comme en base");
await page.fill("#fl-nom", "Koffi");
await page.fill("#fl-tel", "01 96 70 00 99");
await page.fill("#fl-adresse", "Fidjrossè, près du marché");
await page.fill("#fl-frais", "1500");
await page.waitForTimeout(200);
ok((await texte(page, "#fl-total")) === F(21500) && /Livraisonàmoto1500FCFA/.test(serre(await texte(page, "#fl-devis"))),
  "1 500 de frais saisis : total 21 500 FCFA");
ok((await page.inputValue("#fl-montant")).replace(/\s/g, "") === "21500", "le montant payé suit le total");

await page.fill("#fl-transaction", "MP241027.1530.A12345");
await capture(page, "3-client-et-paiement", "#vue");
await page.fill("#fl-transaction", "");
titre("4. Ce qui manque se dit, sans rien envoyer");
await page.fill("#fl-retrait", "");
await page.click("#fl-valider");
await page.waitForTimeout(300);
ok(/où le livreur récupère la commande/.test(await texte(page, "#fl-erreur")),
  "sans lieu de retrait : « Indiquez où le livreur récupère la commande… »");
await page.fill("#fl-retrait", "Alpha, Ganhi — demander Rémi\nBêta : marché Dantokpa, porte 3");
await page.fill("#fl-frais", "");
await page.click("#fl-valider");
await page.waitForTimeout(300);
ok(/frais de livraison convenus/.test(await texte(page, "#fl-erreur")), "sans frais : « Indiquez les frais de livraison… »");
await page.fill("#fl-frais", "1500");
await page.click("#fl-valider");
await page.waitForTimeout(300);
ok(/référence de la transaction/.test(await texte(page, "#fl-erreur")), "sans référence : « Saisissez la référence… »");
await page.fill("#fl-transaction", "MP241027.1530.A12345");
await page.fill("#fl-montant", "20000");
await page.click("#fl-valider");
await page.waitForTimeout(300);
ok(/a payé 20 000 FCFA, mais la commande coûte 21 500 FCFA/.test(await texte(page, "#fl-erreur")),
  "un montant trop court : refusé à l'écran");
ok(!serveur.appels.some((a) => a.fn === "faire_livrer"), "et rien n'est parti vers la base");

titre("5. Validé : la commande part, l'écran l'ouvre");
await page.fill("#fl-montant", "21500");
await page.selectOption("#fl-reseau", "MOOV");
await page.click("#fl-valider");
await page.waitForSelector("[data-role=ok]", { timeout: 3000 }).catch(() => {});
ok(/Koffi/.test(await texte(page, ".feuille, [role=dialog], body")) && /1 500 FCFA de livraison/.test(await texte(page, "body")),
  "une confirmation reprend le client, les frais et le montant");
ok(/À récupérer : Alpha, Ganhi — demander Rémi ; Bêta : marché Dantokpa, porte 3/.test(await texte(page, "body")),
  "et où le livreur récupère la commande");
await page.click("[data-role=ok]");
await page.waitForFunction(() => location.hash === "#/commandes/cmd_wa", null, { timeout: 6000 }).catch(() => {});
const envoi = serveur.appels.find((a) => a.fn === "faire_livrer");
const cps = (envoi && envoi.corps) || {};
ok(cps.transaction === "MP241027.1530.A12345" && cps.montant === 21500 && cps.reseau === "MOOV" && cps.frais === 1500,
  "les frais saisis, la référence, le montant et le réseau partent (" + JSON.stringify(cps).slice(0, 120) + "…)");
ok(cps.client && cps.client.nom === "Koffi" && cps.client.adresse === "Fidjrossè, près du marché" &&
   cps.client.tel === "01 96 70 00 99", "le client part tel que saisi");
ok(cps.destination === null, "sans position : elle n'est pas exigée");
ok(cps.client && cps.client.retrait === "Alpha, Ganhi — demander Rémi\nBêta : marché Dantokpa, porte 3",
  "le lieu de retrait part avec la commande, tel que saisi");
ok(JSON.stringify(cps.articles) === JSON.stringify([{ produit_id: "prod_casque", quantite: 1 },
  { produit_id: "prod_chargeur", quantite: 2 }]), "et les articles, avec leurs quantités");
ok(await page.evaluate(() => location.hash) === "#/commandes/cmd_wa", "l'écran ouvre la commande créée");
await page.waitForSelector(".cmd-retrait", { timeout: 4000 }).catch(() => {});
ok(/À récupérer : Alpha, Ganhi — demander Rémi/.test(await texte(page, ".cmd-retrait")),
  "la commande dit où le livreur la récupère");
ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
await ctx.close();

await nav.close();
console.log(echecs
  ? "\n\x1b[31m" + echecs + " constat(s) en échec ✘\x1b[0m"
  : "\n\x1b[32mUne commande WhatsApp entre dans BIZZOO comme les autres ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
