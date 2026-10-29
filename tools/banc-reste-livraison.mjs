/* =========================================================
   Le reste payé à la livraison, à l'écran (3.59.0)
   =========================================================
   La base garde l'encaissement (supabase/tests/99zzzzzzzzzzz-reste-
   livraison.sql). Ce banc regarde les écrans :

     1. LE LIVREUR, PLUS D'ESPÈCES : « Je l'ai remise » montre au client
        le code MoMoPay de BIZZOO et le montant, en grand ; pas de choix
        « espèces » ; sans numéro de transaction, rien ne part ; avec,
        « remettre_course(…, mobile_money, transaction) » ; la course
        remise dit « payé par MoMoPay, rien à rendre » ; sans code
        enregistré, on ne remet pas ;
     2. LA CAISSE : « MoMoPay à vérifier » en tête ; la boutique le voit,
        mais seul BIZZOO touche « Vérifié » ; l'argent liquide d'avant
        reste « à rendre » ; un modérateur n'y entre pas ;
     3. LE CLIENT : son reçu dit « Payé à la livraison », « Commande
        soldée », et « Ce n'est pas exact » appelle
        « contester_encaissement ».
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-reste-livraison.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const F = (n) => n.toLocaleString("fr-FR").replace(/ | /g, " ") + " FCFA";
const plat = (s) => s.replace(/[  ]/g, " ").replace(/\s+/g, " ");

/* ================================================================
   L'application admin
   ================================================================ */
const PORTEUR = "cccccccc-1111-1111-1111-111111111111";
const CHEF = "22222222-2222-2222-2222-222222222222";
const MODO = "33333333-2222-2222-2222-222222222222";
const SUP = "11111111-1111-1111-1111-111111111111";
const PROFILS = {
  [PORTEUR]: { id: PORTEUR, email: "porteur@alpha.bj", nom: "Kodjo", role: "livreur", actif: true,
    peut_modifier_produits: true, boutique_id: "bou_a" },
  [CHEF]: { id: CHEF, email: "chef@alpha.bj", nom: "Chef", role: "administrateur", actif: true,
    peut_modifier_produits: true, boutique_id: "bou_a" },
  [MODO]: { id: MODO, email: "modo@alpha.bj", nom: "Modo", role: "moderateur", actif: true,
    peut_modifier_produits: true, boutique_id: "bou_a" },
  [SUP]: { id: SUP, email: "sup@bizzoo.bj", nom: "Sup", role: "superadministrateur", actif: true,
    peut_modifier_produits: true, boutique_id: null },
};
const fiche = (o = {}) => ({ numero: "BZ-000090",
  retrait: { boutique: "Alpha", adresse: "Ganhi", tel: "0197111222", indicatif: "229" },
  livraison: { nom: "Afi", adresse: "Fidjrossè", note: "", tel: "97666007", indicatif: "229" },
  devise: "FCFA", frais: 1000, deja_paye: 3000, a_encaisser: 7000, encaisse: null,
  momopay: { code: "123456", nom: "BIZZOO SARL" }, ...o });
const course = (o = {}) => ({ commande_id: "cmd_r", numero: "BZ-000090", boutique_id: "bou_a",
  nom_boutique: "Alpha", client_nom: "Afi", client_tel: "97666007", client_indicatif: "229",
  client_adresse: "Fidjrossè", note: "", etat: "en_livraison",
  articles: [{ nom: "Casque", quantite: 1 }], paye_le: "2026-10-20T08:00:00Z",
  a_encaisser: 7000, fiche: fiche(), recu_le: "2026-10-20T08:05:00Z", ...o });
const CAISSE = [
  { id: 11, commande_id: "c1", numero: "BZ-000091", boutique_id: "bou_a", nom_boutique: "Alpha",
    livreur_id: PORTEUR, livreur_nom: "Kodjo", livreur_tel: "0196200001", du: 7000, montant: 7000,
    mode: "especes", motif: "", encaisse_le: "2026-10-20T10:00:00Z", remis_le: null, remis_par_nom: "",
    conteste_le: null, conteste_motif: "", declare: true, devise: "FCFA" },
  { id: 12, commande_id: "c2", numero: "BZ-000092", boutique_id: "bou_a", nom_boutique: "Alpha",
    livreur_id: PORTEUR, livreur_nom: "Kodjo", livreur_tel: "0196200001", du: 6500, montant: 6500,
    mode: "mobile_money", motif: "MoMoPay — transaction MP1234567", encaisse_le: "2026-10-20T11:00:00Z",
    remis_le: null, remis_par_nom: "", conteste_le: "2026-10-20T12:00:00Z",
    conteste_motif: "J'ai payé 5 000", declare: true, devise: "FCFA" },
  { id: null, commande_id: "c3", numero: "BZ-000093", boutique_id: "bou_a", nom_boutique: "Alpha",
    livreur_id: PORTEUR, livreur_nom: "Kodjo", livreur_tel: "0196200001", du: 4000, montant: null,
    mode: "", motif: "", encaisse_le: "2026-10-19T09:00:00Z", remis_le: null, remis_par_nom: "",
    conteste_le: null, conteste_motif: "", declare: false, devise: "FCFA" },
  { id: 9, commande_id: "c0", numero: "BZ-000080", boutique_id: "bou_a", nom_boutique: "Alpha",
    livreur_id: PORTEUR, livreur_nom: "Kodjo", livreur_tel: "0196200001", du: 3000, montant: 3000,
    mode: "especes", motif: "", encaisse_le: "2026-10-18T09:00:00Z", remis_le: "2026-10-18T18:00:00Z",
    remis_par_nom: "Chef", conteste_le: null, conteste_motif: "", declare: true, devise: "FCFA" },
];

async function ouvrirAdmin({ moi, hash, courses = [], caisse = null, lignesCaisse = CAISSE }) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2000 }, serviceWorkers: "block" });
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
  const serveur = { appels: [], ecritures: [] };
  let liste = courses;
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) {
      serveur.appels.push({ fn: c.slice(4), corps: (() => { try { return req.postDataJSON(); } catch (_) { return null; } })() });
    }
    if (req.method() !== "GET" && !c.startsWith("rpc/")) {
      serveur.ecritures.push({ table: c.split("?")[0], methode: req.method(),
        corps: (() => { try { return req.postDataJSON(); } catch (_) { return null; } })() });
    }
    if (c.startsWith("paiement")) return d([{ id: 1, actif: true, fournisseur: "feexpay", taux_acompte: 10,
      frais_livraison: 1000, momopay_code: "", momopay_nom: "" }]);
    if (c.startsWith("profils")) {
      const id = (u.searchParams.get("id") || "").replace(/^eq\./, "");
      return d(id ? [PROFILS[id]].filter(Boolean) : Object.values(PROFILS));
    }
    if (c.startsWith("positions_livreurs")) return d([{ profil_id: PORTEUR, latitude: 6.37,
      longitude: 2.42, adresse: "Cadjèhoun" }]);
    if (c === "rpc/mes_livraisons") return d(liste);
    if (c === "rpc/courses_proposees") return d([]);
    if (c === "rpc/ma_caisse") return d(caisse);
    if (c === "rpc/caisse_livreurs") return d(lignesCaisse);
    if (c === "rpc/remettre_course") {
      liste = liste.map((l) => ({ ...l, etat: "remise", fiche: fiche({
        encaisse: { montant: 7000, mode: "mobile_money", encaisse_le: "2026-10-20T10:00:00Z", remis_le: null,
          transaction: "MP1234567" } }) }));
      return d({ lignes: 1 });
    }
    if (c === "rpc/marquer_remis") return d(1);
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("boutiques")) return d([{ id: "bou_a", nom: "Alpha", categorie_id: "cat_hightech",
      icone: "magasin", couleur: "#0047D9", devise: "FCFA", indicatif: "229", whatsapp: "97000001",
      actif: true, ordre: 1 }]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1800);
  if (hash) {
    await page.evaluate((h) => { location.hash = h; }, hash);
    await page.waitForTimeout(1500);
  }
  return { page, ctx, erreurs, serveur };
}
const toasts = (page) => page.evaluate(() => (window.__toasts || []).join(" | "));

titre("1. Le livreur : MoMoPay, plus d'espèces");
{
  const { page, ctx, erreurs, serveur } = await ouvrirAdmin({ moi: PORTEUR, courses: [course()],
    caisse: { a_remettre: 3000, courses: 1, boutiques: [{ boutique: "Alpha", montant: 3000 }] } });
  await page.waitForSelector(".lv-course", { timeout: 6000 }).catch(() => {});
  const avant = plat(await page.evaluate(() => (document.querySelector(".lv-course") || {}).innerText || ""));
  ok(/À payer par MoMoPay : 7 000 FCFA/.test(avant) && /Pas d'espèces/.test(avant),
    "la course : « À payer par MoMoPay : 7 000 FCFA — pas d'espèces »");
  await page.click('.lv-avancer[data-vers="remise"]');
  await page.waitForTimeout(500);
  const f = await page.evaluate(() => ({
    code: (document.querySelector("#lv-momo-code") || {}).textContent || "",
    montant: (document.querySelector("#lv-momo-montant") || {}).textContent || "",
    especes: !!document.querySelector('[data-mode="especes"]') || /En espèces/.test(document.body.innerText),
    nom: /BIZZOO SARL/.test((document.querySelector("#lv-momo") || {}).textContent || "") }));
  ok(f.code === "123456" && plat(f.montant) === "7 000 FCFA" && f.nom,
    "la feuille montre au client le code MoMoPay 123456, BIZZOO SARL, et 7 000 FCFA");
  ok(!f.especes, "pas de choix « En espèces »");
  await page.click("#lv-remettre");
  await page.waitForTimeout(400);
  ok(/ID de la transaction/.test(await toasts(page)) &&
     !serveur.appels.some((a) => a.fn === "remettre_course"), "sans numéro de transaction : on le demande, rien ne part");
  /* (3.70.0) Le numéro du client recopié à la place de l'ID du SMS. */
  await page.fill("#lv-transaction", "01 97 00 00 00");
  await page.waitForTimeout(150);
  ok(/numéro de téléphone MTN, pas à un ID de transaction/.test(
       await page.$eval(".note-saisie", (n) => (n.hidden ? "" : n.textContent)).catch(() => "")),
    "un numéro tapé à la place de l'ID : la feuille le dit pendant la saisie");
  await page.click("#lv-remettre");
  await page.waitForTimeout(400);
  ok(/numéro de téléphone, pas l'ID/.test(await toasts(page)) &&
     !serveur.appels.some((a) => a.fn === "remettre_course"), "et le premier appui s'arrête là-dessus, rien ne part");
  await page.fill("#lv-transaction", "MP 1234567");
  await page.click("#lv-remettre");
  await page.waitForTimeout(1500);
  const appel = serveur.appels.find((a) => a.fn === "remettre_course");
  ok(appel && appel.corps.commande === "cmd_r" && appel.corps.boutique === "bou_a" &&
     appel.corps.montant === 7000 && appel.corps.mode === "mobile_money" && appel.corps.motif === "MP 1234567",
    "remettre_course(cmd_r, bou_a, 7000, mobile_money, « MP 1234567 »)");
  ok(!serveur.appels.some((a) => a.fn === "avancer_livraison"), "et pas l'ancien « Je l'ai remise » muet");
  const t = plat(await page.evaluate(() => (document.querySelector(".lv-course") || {}).innerText || ""));
  ok(/Payé : 7 000 FCFA \(MoMoPay\)/.test(t) && /Transaction MP1234567/.test(t) && /rien à rendre/.test(t),
    "la course remise : « Payé : 7 000 FCFA (MoMoPay) — Transaction MP1234567 — rien à rendre »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  const { page, ctx, serveur } = await ouvrirAdmin({ moi: PORTEUR,
    courses: [course({ fiche: fiche({ momopay: { code: "", nom: "" } }) })] });
  await page.waitForSelector(".lv-course", { timeout: 6000 }).catch(() => {});
  await page.click('.lv-avancer[data-vers="remise"]');
  await page.waitForTimeout(400);
  ok(await page.evaluate(() => !!document.querySelector("#lv-sans-code") && !document.querySelector("#lv-remettre")),
    "BIZZOO n'a pas de code MoMoPay : on le dit, et pas de bouton pour remettre");
  ok(!serveur.appels.some((a) => a.fn === "remettre_course"), "rien ne part");
  await ctx.close();
}
{
  const { page, ctx, serveur } = await ouvrirAdmin({ moi: PORTEUR,
    courses: [course({ a_encaisser: 0, fiche: fiche({ a_encaisser: 0, deja_paye: 10000 }) })] });
  await page.waitForSelector(".lv-course", { timeout: 6000 }).catch(() => {});
  await page.click('.lv-avancer[data-vers="remise"]');
  await page.waitForTimeout(400);
  ok(await page.evaluate(() => !document.querySelector("#lv-momo") &&
    /Rien à payer/.test(document.body.innerText)), "tout payé : « Rien à payer », pas de code");
  await page.click("#lv-remettre");
  await page.waitForTimeout(1200);
  const appel = serveur.appels.find((a) => a.fn === "remettre_course");
  ok(appel && appel.corps.montant === 0 && appel.corps.mode === "aucun", "remettre_course(…, 0, aucun)");
  await ctx.close();
}

titre("2. La caisse : MoMoPay à vérifier par BIZZOO");
{
  const { page, ctx, erreurs, serveur } = await ouvrirAdmin({ moi: CHEF, hash: "#/caisse" });
  await page.waitForSelector("#cs-a-verifier", { timeout: 6000 }).catch(() => {});
  const t = plat(await page.evaluate(() => document.getElementById("vue").innerText));
  ok(/MoMoPay à vérifier : 6 500 FCFA/i.test(t) && /MoMoPay — transaction MP1234567/.test(t),
    "« MoMoPay à vérifier : 6 500 FCFA », avec la transaction");
  ok(!(await page.$(".cs-verifier")) && /BIZZOO les vérifie/.test(t),
    "la boutique le voit, mais ne peut pas le marquer vérifié");
  ok(/À rendre par les livreurs : 7 000 FCFA/i.test(t), "l'argent liquide d'avant : « À rendre : 7 000 FCFA »");
  ok(/Contesté par le client : « J'ai payé 5 000 »/.test(t) && /Contestés par le client \(1\)/i.test(t),
    "la contestation du client");
  ok(/Remis sans déclaration \(1\)/i.test(t) && /BZ-000093/.test(t), "la remise sans déclaration, à vérifier");
  ok(await page.evaluate(() => !!document.querySelector("#cs-rendus")) && /Déjà rendu ou vérifié \(1/i.test(t),
    "ce qui est déjà rendu, replié");
  await page.click(".cs-rendre");
  await page.waitForTimeout(400);
  await page.click('[data-role="ok"]');
  await page.waitForTimeout(1200);
  const appel = serveur.appels.find((a) => a.fn === "marquer_remis");
  ok(appel && JSON.stringify(appel.corps.ids) === "[11]", "« Argent reçu du livreur » : marquer_remis([11])");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  const { page, ctx, erreurs, serveur } = await ouvrirAdmin({ moi: SUP, hash: "#/caisse" });
  await page.waitForSelector(".cs-verifier", { timeout: 6000 }).catch(() => {});
  ok(!!(await page.$(".cs-verifier")), "BIZZOO a le bouton « Vérifié sur le compte MoMoPay »");
  await page.click(".cs-verifier");
  await page.waitForTimeout(400);
  await page.click('[data-role="ok"]');
  await page.waitForTimeout(1200);
  const appel = serveur.appels.find((a) => a.fn === "marquer_remis");
  ok(appel && JSON.stringify(appel.corps.ids) === "[12]", "« Vérifié » : marquer_remis([12])");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  const { page, ctx } = await ouvrirAdmin({ moi: CHEF, hash: "#/" });
  await page.waitForTimeout(800);
  ok(await page.evaluate(() => !!document.querySelector('#ac-caisse[href="#/caisse"]')),
    "l'accueil de l'administrateur mène à la caisse");
  await ctx.close();
}
{
  const { page, ctx, serveur } = await ouvrirAdmin({ moi: MODO, hash: "#/caisse" });
  await page.waitForTimeout(800);
  ok(/Réservé à l'administrateur/.test(await page.evaluate(() => document.getElementById("vue").innerText)) &&
     !serveur.appels.some((a) => a.fn === "caisse_livreurs"), "un modérateur : « Réservé à l'administrateur »");
  await ctx.close();
}

titre("4. Les Réglages : le code MoMoPay de BIZZOO");
{
  const { page, ctx, erreurs, serveur } = await ouvrirAdmin({ moi: SUP, hash: "#/reglages" });
  /* Les réglages de l'enseigne sont sous leur onglet. */
  if (await page.$('[data-cible="enseigne"]')) {
    await page.click('[data-cible="enseigne"]');
    await page.waitForTimeout(800);
  }
  await page.waitForSelector("#momo-code", { timeout: 6000 }).catch(() => {});
  ok(!!(await page.$("#momo-code")), "le superadministrateur a la carte « MoMoPay — le reste à la livraison »");
  await page.fill("#momo-code", " 123 456 ");
  await page.fill("#momo-nom", "BIZZOO SARL");
  await page.click("#momo-enregistrer");
  await page.waitForTimeout(1200);
  const w = serveur.ecritures.find((x) => x.table === "paiement" && x.methode === "PATCH");
  ok(w && w.corps.momopay_code === "123456" && w.corps.momopay_nom === "BIZZOO SARL",
    "enregistré : momopay_code 123456, BIZZOO SARL");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  const { page, ctx } = await ouvrirAdmin({ moi: CHEF, hash: "#/reglages" });
  await page.waitForTimeout(800);
  ok(!(await page.$("#momo-code")), "un administrateur de boutique ne la voit pas");
  await ctx.close();
}

/* ================================================================
   L'application client
   ================================================================ */
const CLIENT = { nom: "Afi", tel: "97666007", indicatif: "229", adresse: "Fidjrossè" };
const COMMANDE = { id: "cmd_r", numero: "BZ-000090", total: 10000, devise: "FCFA", etat: "payee",
  acompte: 3000, taux_acompte: 30, verse: 3000, reste: 7000, frais_livraison: 1000, client: CLIENT,
  boutiques: [{ id: "bou_a", nom: "Alpha", whatsapp: "97000001", indicatif: "229", montant: 9000,
    a_encaisser: 7000, lignes: [{ nom: "Casque", prix: 9000, quantite: 1 }] }] };

async function ouvrirClient({ suivi }) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2000 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
    localStorage.setItem("bizzoo-commandes", JSON.stringify([a.commande]));
    localStorage.setItem("bizzoo-coordonnees", JSON.stringify(a.client));
    window.__toasts = [];
    document.addEventListener("DOMContentLoaded", () => {
      const zone = document.querySelector("#toasts") || document.body;
      new MutationObserver(() => window.__toasts.push(zone.innerText))
        .observe(zone, { childList: true, subtree: true });
    });
  }, { commande: COMMANDE, client: CLIENT });
  const serveur = { appels: [] };
  let etat = suivi;
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/")) {
      serveur.appels.push({ fn: c.slice(4), corps: (() => { try { return req.postDataJSON(); } catch (_) { return null; } })() });
    }
    if (c === "rpc/suivre_commande") return d(etat);
    if (c === "rpc/contester_encaissement") {
      etat = { ...etat, encaissements: { bou_a: { ...etat.encaissements.bou_a, conteste: true } } };
      return d(1);
    }
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("reglages")) return d([{ compte_obligatoire: false }]);
    if (c.startsWith("paiement")) return d([{ actif: true, fournisseur: "feexpay", taux_acompte: 10 }]);
    return d([]);
  });
  await page.goto(BASE + "/client/index.html#/commande/cmd_r");
  await page.waitForTimeout(3000);
  return { page, ctx, erreurs, serveur };
}

titre("3. Le client voit son reste payé, et peut le contester");
{
  const suivi = { numero: "BZ-000090", etat: "payee", total: 10000, devise: "FCFA", reste: 7000,
    restes: { bou_a: 7000 }, paye_livraison: 7000,
    encaissements: { bou_a: { montant: 7000, mode: "mobile_money", encaisse_le: "2026-10-20T13:30:00Z",
      livreur: "Kodjo", conteste: false } } };
  const { page, ctx, erreurs, serveur } = await ouvrirClient({ suivi });
  await page.waitForSelector(".re-encaisse:not([hidden])", { timeout: 6000 }).catch(() => {});
  const z = plat(await page.evaluate(() => (document.querySelector(".re-encaisse") || {}).innerText || ""));
  ok(/Payé à la livraison/i.test(z) && /7 000 FCFA/.test(z) && /à Kodjo/.test(z) && /par MoMoPay/.test(z),
    "« Payé à la livraison : 7 000 FCFA — à Kodjo, par MoMoPay »");
  const tete = plat(await page.evaluate(() => (document.querySelector(".re-entete") || {}).innerText || ""));
  ok(/Commande soldée/.test(tete) && /Soldée/.test(tete), "« Commande soldée », et le badge « Soldée »");
  await page.click(".re-contester");
  await page.fill(".re-contester-zone textarea", "J'ai payé 5 000 seulement");
  await page.click(".re-contester-envoyer");
  await page.waitForTimeout(1500);
  const appel = serveur.appels.find((a) => a.fn === "contester_encaissement");
  ok(appel && appel.corps.commande === "cmd_r" && appel.corps.boutique === "bou_a" &&
     appel.corps.motif === "J'ai payé 5 000 seulement" && appel.corps.tel === "97666007",
    "« Ce n'est pas exact » : contester_encaissement(cmd_r, bou_a, motif, numéro)");
  ok(/signalé un problème/.test(await page.evaluate(() => document.querySelector(".re-encaisse").innerText)),
    "puis « Vous avez signalé un problème »");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}
{
  const suivi = { numero: "BZ-000090", etat: "payee", total: 10000, devise: "FCFA", reste: 7000,
    restes: { bou_a: 7000 } };
  const { page, ctx, erreurs } = await ouvrirClient({ suivi });
  await page.waitForTimeout(500);
  ok(await page.evaluate(() => document.querySelector(".re-encaisse").hidden &&
    /Reste à payer à la livraison/.test(document.body.innerText) && !/soldée/i.test(document.body.innerText)),
    "pas encore livré, ou base d'avant : « Reste à payer à la livraison », rien d'autre");
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n" + echecs + " ÉCHEC(S)" : "\nTout tient ✔");
process.exit(echecs ? 1 : 0);
