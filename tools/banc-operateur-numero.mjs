/* =========================================================
   L'opérateur suit le numéro ; un numéro n'est pas un ID (3.70.0)
   =========================================================
   LA DEMANDE. « Si quelqu'un sélectionne Moov et tape un numéro MTN,
   que la sélection se corrige en MTN. Et là où on renseigne l'ID de
   transaction, si quelqu'un tape un numéro de téléphone, que le système
   lui dise que ce n'est pas un ID. »

   Ce que le banc prouve :

     1. LA MÊME TABLE PARTOUT : client, admin et Personnel devinent le
        même opérateur pour les mêmes numéros — 10 chiffres, 8 chiffres
        à l'ancienne, avec ou sans +229. L'ancienne table du client à
        8 chiffres se trompait (« 90 » donné à Moov, « 94 » à MTN) ;
     2. UN ID N'EST PAS UN NUMÉRO : « 01 97 12 15 96 » est repéré, un
        vrai ID (« MP241029.1234.A56789 », « 7412589630 ») ne l'est pas ;
     3. AU PAIEMENT, MOOV CHOISI + NUMÉRO MTN TAPÉ → MTN, et l'écran le
        dit ; rechoisir Moov ensuite reste possible (un numéro porté
        garde son préfixe), mais l'écran prévient.

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-operateur-numero.mjs
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-operateur-numero.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

titre("1. La même table dans les trois applications");
{
  const ctx = await nav.newContext({ serviceWorkers: "block" });
  const page = await ctx.newPage();
  await page.goto(BASE + "/tools/", { waitUntil: "domcontentloaded" }).catch(() => {});
  const lire = async (fichier, nom) => {
    /* Un bloc par fichier : les trois déclarent « const Utils » / « const UI ». */
    await page.addScriptTag({ content: "{" + (await (await fetch(BASE + fichier)).text()) +
      ";window." + nom + "=" + (fichier.includes("personnel") ? "UI" : "Utils") + ";}" });
  };
  await lire("/client/js/utils.js", "UClient");
  await lire("/admin/js/utils.js", "UAdmin");
  await lire("/personnel/js/ui.js", "UPerso");
  const CAS = [
    ["0197121596", "MTN"], ["01 97 12 15 96", "MTN"], ["+229 01 97 12 15 96", "MTN"],
    ["97121596", "MTN"], ["90112233", "MTN"], ["0190112233", "MTN"],
    ["0195000000", "MOOV"], ["95000000", "MOOV"], ["94112233", "MOOV"], ["00229 01 45 11 22 33", "MOOV"],
    ["0140112233", "CELTIIS"], ["40112233", "CELTIIS"],
    ["0112345678", ""], ["1234567890", ""], ["123", ""], ["", ""],
  ];
  const rendus = await page.evaluate((cas) => cas.map(([t]) =>
    [window.UClient.reseauDuNumero(t), window.UAdmin.reseauDuNumero(t), window.UPerso.reseauDuNumero(t)]), CAS);
  const fautes = CAS.filter(([, att], i) => rendus[i].some((r) => r !== att))
    .map(([t, att], i) => t + "→" + att);
  ok(!fautes.length, "16 numéros, le même opérateur dans les trois applications" +
    (fautes.length ? " — écarts : " + fautes.join(", ") : ""));
  ok(rendus[4][0] === "MTN" && rendus[8][0] === "MOOV",
    "l'ancien format à 8 chiffres se lit juste : « 90… » MTN, « 94… » Moov");

  titre("2. Un ID de transaction n'est pas un numéro de téléphone");
  const ids = await page.evaluate(() => ({
    tel: window.UAdmin.ressembleTelephone("01 97 12 15 96"),
    tel8: window.UPerso.ressembleTelephone("97121596"),
    vrai1: window.UAdmin.ressembleTelephone("MP241029.1234.A56789"),
    vrai2: window.UClient.ressembleTelephone("7412589630"),
    vrai3: window.UAdmin.ressembleTelephone("13748576893"),
    melange: window.UAdmin.ressembleTelephone("ABC0197121596"),
    message: window.UAdmin.alerteTransaction("0197121596"),
  }));
  ok(ids.tel === "MTN" && ids.tel8 === "MTN", "« 01 97 12 15 96 » et « 97121596 » : repérés comme numéros MTN");
  ok(!ids.vrai1 && !ids.vrai2 && !ids.vrai3 && !ids.melange,
    "un vrai ID (lettres, ou chiffres hors préfixes) n'est pas pris pour un numéro");
  ok(/numéro de téléphone MTN, pas à un ID de transaction/.test(ids.message) && /validez à nouveau/.test(ids.message),
    "le message dit quoi corriger, et qu'on peut confirmer : « " + ids.message.slice(0, 70) + "… »");
  await ctx.close();
}

titre("3. Au paiement : Moov choisi, numéro MTN tapé → MTN, et l'écran le dit");
{
  const COMMANDE = { id: "cmd_x", numero: "BZ-000042", total: 300000, devise: "FCFA", etat: "a_payer",
    client: { nom: "Koffi", tel: "0197000000", indicatif: "229", adresse: "Cotonou" },
    boutiques: [{ id: "bou_a", nom: "Alpha", montant: 300000,
      lignes: [{ nom: "Ordinateur", prix: 300000, quantite: 1 }] }] };
  const ctx = await nav.newContext({ viewport: { width: 390, height: 900 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((c) => {
    try {
      localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" }));
      localStorage.setItem("bizzoo-commandes", JSON.stringify([c]));
      localStorage.setItem("bizzoo-coordonnees", JSON.stringify({
        nom: "Koffi", tel: "0197000000", indicatif: "229", adresse: "Cotonou" }));
    } catch (_) { /* hors de l'application */ }
  }, COMMANDE);
  await page.route("**/functions/v1/feexpay", (r) => r.fulfill({ status: 200, contentType: "application/json",
    body: JSON.stringify({ etat: "a_payer", echoue: true, erreur: "Refusé." }) }));
  await page.route("**/rest/v1/**", (route) => {
    const c = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/suivre_commande")) return d({ etat: "a_payer", remarque: "" });
    if (c.startsWith("rpc/")) return d([]);
    if (c.startsWith("paiement")) return d([{ id: 1, actif: true, fournisseur: "feexpay", cle_publique: "", bac_a_sable: false }]);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/client/index.html#/commande/cmd_x", { waitUntil: "domcontentloaded" });
  const pret = await page.waitForSelector("#re-attente #co-mm-tel", { timeout: 9000 }).then(() => true, () => false);
  ok(pret, "le reçu propose de payer : opérateur et numéro");
  if (pret) {
    const actif = () => page.evaluate(() =>
      (document.querySelector("#re-attente .pay-methode.active") || {}).dataset?.reseau || "");
    const note = () => page.evaluate(() => {
      const n = document.querySelector("#re-attente #co-mm-note");
      return n && !n.hidden ? n.textContent : "";
    });
    await page.click('#re-attente [data-reseau="MOOV"]');
    ok(await actif() === "MOOV" && /numéro MTN/.test(await note()),
      "Moov choisi pour un numéro MTN : l'écran prévient (« " + (await note()) + " »)");
    await page.fill("#re-attente #co-mm-tel", "");
    await page.type("#re-attente #co-mm-tel", "01 66 00 11 22");
    ok(await actif() === "MTN", "un numéro MTN tapé : l'opérateur repasse sur MTN (" + await actif() + ")");
    ok(/Opérateur corrigé : ce numéro est un numéro MTN/.test(await note()), "et l'écran le dit : « " + (await note()) + " »");
    await page.fill("#re-attente #co-mm-tel", "0195000000");
    ok(await actif() === "MOOV", "un numéro Moov : Moov (" + await actif() + ")");
    await page.fill("#re-attente #co-mm-tel", "0140000000");
    ok(await actif() === "CELTIIS", "un numéro Celtiis : Celtiis (" + await actif() + ")");
    await page.click('#re-attente [data-reseau="MTN"]');
    ok(await actif() === "MTN" && /numéro Celtiis/.test(await note()),
      "on peut encore rechoisir (numéro porté) — l'écran prévient seulement");
  }
  ok(!erreurs.length, "aucune erreur dans la page" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

titre("4. La liste vient de la base : un préfixe ajouté y est pris aussitôt");
{
  /* La base connaît « 01 30 » → MTN, que la liste intégrée ignore. */
  const LISTE = [{ prefixe: "30", operateur: "MTN" }, { prefixe: "97", operateur: "MTN" },
    { prefixe: "95", operateur: "MOOV" }, { prefixe: "40", operateur: "CELTIIS" }];
  const essai = async (reponse) => {
    const ctx = await nav.newContext({ serviceWorkers: "block" });
    const page = await ctx.newPage();
    await page.addInitScript(() => {
      try { localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "k" })); }
      catch (_) { /* vide */ }
    });
    await page.route("**/rest/v1/**", (route) => {
      const c = new URL(route.request().url()).pathname.replace(/^.*\/rest\/v1\//, "");
      if (c.startsWith("prefixes_operateurs")) return reponse(route);
      if (c.startsWith("boutique")) return route.fulfill({ status: 200, contentType: "application/json",
        body: JSON.stringify([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]) });
      return route.fulfill({ status: 200, contentType: "application/json", body: "[]" });
    });
    await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
    await page.goto(BASE + "/client/index.html", { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(1500);
    const r = await page.evaluate(() => ({ trente: Utils.reseauDuNumero("0130112233"),
      mtn: Utils.reseauDuNumero("0197112233"), garde: (() => {
        try { return JSON.parse(localStorage.getItem("bizzoo-prefixes-operateurs") || "[]").length; }
        catch (_) { return -1; } })() }));
    await ctx.close();
    return r;
  };
  const avec = await essai((route) => route.fulfill({ status: 200, contentType: "application/json",
    body: JSON.stringify(LISTE) }));
  ok(avec.trente === "MTN", "« 01 30 » ajouté dans la base : le client le reconnaît MTN (" + avec.trente + ")");
  ok(avec.garde === 4, "et garde la liste pour la prochaine ouverture hors connexion");
  const sans = await essai((route) => route.fulfill({ status: 404, contentType: "application/json",
    body: JSON.stringify({ message: "relation does not exist" }) }));
  ok(sans.mtn === "MTN" && sans.trente === "",
    "base d'avant, sans la table : la liste intégrée reste en service (97 → MTN, 30 inconnu)");
  const vide = await essai((route) => route.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
  ok(vide.mtn === "MTN", "une liste vide ne remplace rien");
}

titre("5. Le superadmin ajoute un préfixe dans Réglages");
{
  const SUPER = "11111111-1111-1111-1111-111111111111";
  const PROFIL = { id: SUPER, email: "chef@bizzoo.bj", role: "superadministrateur", actif: true,
    peut_modifier_produits: true, boutique_id: null };
  const BOUTIQUES = [{ id: "bou_a", nom: "Alpha", categorie_id: "cat_hightech", icone: "magasin",
    couleur: "#0047D9", devise: "FCFA", indicatif: "229", actif: true, ordre: 1 }];
  let liste = [{ prefixe: "97", operateur: "MTN" }, { prefixe: "95", operateur: "MOOV" },
    { prefixe: "40", operateur: "CELTIIS" }];
  const appels = [];
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2400 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  page.on("dialog", (d) => d.accept());
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o))))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: b64({ alg: "HS256" }) + "." + b64({ sub: a.moi }) + ".s",
      refresh_token: "r", expire_a: Date.now() + 3600000, email: a.email }));
  }, { moi: SUPER, email: PROFIL.email });
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    if (c.startsWith("rpc/regler_prefixe_operateur")) {
      const corps = req.postDataJSON();
      appels.push(corps);
      const p = String(corps.prefixe).replace(/\D/g, "").replace(/^01(?=\d{2}$)/, "");
      liste = liste.filter((l) => l.prefixe !== p);
      if (corps.operateur) liste.push({ prefixe: p, operateur: corps.operateur });
      return d({ prefixe: p, operateur: corps.operateur || null });
    }
    if (c.startsWith("rpc/")) return d(null);
    if (req.method() !== "GET") return route.fulfill({ status: 204, body: "" });
    if (c.startsWith("prefixes_operateurs")) return d(liste);
    if (c.startsWith("profils")) return d([PROFIL]);
    if (c.startsWith("boutiques")) return d(BOUTIQUES);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1800);
  await page.evaluate(() => { location.hash = "#/reglages"; });
  await page.waitForTimeout(1600);
  if (await page.$('[data-cible="enseigne"]')) {
    await page.click('[data-cible="enseigne"]');
    await page.waitForTimeout(1400);
  }
  const vu = await page.waitForSelector("#prefixe-enregistrer", { timeout: 6000 }).then(() => true, () => false);
  ok(vu, "la carte « Préfixes des opérateurs » est là, avec la liste de la base");
  if (vu) {
    const texteSection = async () => (await page.textContent("#section-prefixes")).replace(/\s+/g, " ");
    ok(/01 97/.test(await texteSection()) && /01 95/.test(await texteSection()), "chaque préfixe sous son opérateur");
    await page.fill("#prefixe-nouveau", "01 30");
    await page.selectOption("#prefixe-operateur", "MTN");
    await page.click("#prefixe-enregistrer");
    await page.waitForTimeout(1200);
    ok(appels.length === 1 && appels[0].prefixe === "01 30" && appels[0].operateur === "MTN",
      "« 01 30 » + MTN : regler_prefixe_operateur(« 01 30 », MTN)");
    ok(/01 30/.test(await texteSection()), "la liste se relit : 01 30 y est");
    ok(await page.evaluate(() => Utils.reseauDuNumero("0130112233")) === "MTN",
      "et cette application s'en sert aussitôt");
    await page.click('[data-prefixe="30"]');
    await page.waitForTimeout(1200);
    ok(appels.length === 2 && appels[1].prefixe === "30" && appels[1].operateur === "",
      "toucher un préfixe le retire (après confirmation)");
  }
  ok(!erreurs.length, "aucune erreur JavaScript" + (erreurs.length ? " : " + erreurs[0] : ""));
  await ctx.close();
}

await nav.close();
console.log(echecs ? "\n\x1b[31m" + echecs + " échec(s)\x1b[0m"
  : "\n\x1b[32mL'opérateur suit le numéro, et un numéro n'est pas pris pour un ID ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
