/* =========================================================
   Un reversement, c'est des commandes entières — ou tout le solde ;
   l'administrateur de BIZZOO crée un vendeur (3.81.0)
   =========================================================
   La base décide (essais « reversements-commandes » et
   « vendeur-par-admin-bizzoo »). Ce banc regarde l'application admin :

     1. la boutique demande des commandes précises : la liste vient de la
        base, le total suit les cases cochées, la demande part avec les
        commandes ;
     2. le superadministrateur voit, sous chaque demande à traiter, ses
        commandes : client, paiement et référence, ce qui doit faire
        vérifier ; une demande traitée les montre au toucher ;
     3. l'administrateur de BIZZOO a « Nouveau vendeur » dans Comptes ;
        l'administrateur d'une boutique, non.

     PLAYWRIGHT=<chemin>/playwright-core/index.js BANC_URL=… node tools/banc-reversements-commandes.mjs
   ========================================================= */
let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js")).default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/banc-reversements-commandes.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
let echecs = 0;
const ok = (v, q) => { if (!v) echecs++; console.log((v ? "  ok     " : "  ÉCHEC  ") + q); };
const titre = (t) => console.log("\n== " + t + " ==");
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const plat = (s) => String(s || "").replace(/[  ]/g, " ").replace(/\s+/g, " ");
const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});
const jeton = (sub) => {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  return b64({ alg: "HS256" }) + "." + b64({ sub }) + ".s";
};
const CHEF = "c2c20000-0000-0000-0000-000000000001";
const ADMBZ = "c2c20000-0000-0000-0000-000000000002";
const SUP = "11111111-1111-1111-1111-111111111111";
const PROFILS = {
  [CHEF]: { id: CHEF, email: "chef@alpha.bj", nom: "Chef", role: "administrateur", actif: true, boutique_id: "bou_a", peut_modifier_produits: true },
  [ADMBZ]: { id: ADMBZ, email: "admin@bizzoo.bj", nom: "Admin BZ", role: "administrateur", actif: true, boutique_id: null, peut_modifier_produits: true },
  [SUP]: { id: SUP, email: "sup@bizzoo.bj", nom: "Sup", role: "superadministrateur", actif: true, boutique_id: null, peut_modifier_produits: true },
};
/* « vendeurs : [] » : la boutique connaît les vendeurs (base à jour). */
const BOU = [{ id: "bou_a", nom: "Alpha", categorie_id: null, icone: "magasin", couleur: "#0047D9",
  devise: "FCFA", indicatif: "229", actif: true, ordre: 1, vendeurs: "unique", part_vendeur_max: 80 }];
const RECEPTION = { tel: "0196123456", reseau: "MTN", titulaire: "Chef", maj_le: "2026-10-20T09:00:00Z", maj_par: "Chef" };
const A_REVERSER = [
  { commande_id: "cmd-1", numero: "BZ-000101", paye_le: "2026-11-01T10:00:00Z", part: 8000, reste: 8000 },
  { commande_id: "cmd-2", numero: "BZ-000102", paye_le: "2026-11-02T10:00:00Z", part: 8000, reste: 8000 },
  { commande_id: "cmd-3", numero: "BZ-000103", paye_le: "2026-11-03T10:00:00Z", part: 6000, reste: 6000 },
];
const DEMANDES = [
  { id: 7, boutique_id: "bou_a", nom_boutique: "Alpha", montant: 16000, tel: "0196123456", reseau: "MTN",
    titulaire: "Chef", etat: "en_attente", demande_par: "Chef", demande_le: "2026-11-05T10:00:00Z", decide_par: "",
    decide_le: null, reference: "", motif: "", devise: "FCFA" },
  { id: 5, boutique_id: "bou_a", nom_boutique: "Alpha", montant: 6000, tel: "0196123456", reseau: "MTN",
    titulaire: "Chef", etat: "valide", demande_par: "Chef", demande_le: "2026-11-01T10:00:00Z", decide_par: "Sup",
    decide_le: "2026-11-01T12:00:00Z", reference: "MP-1", motif: "", devise: "FCFA" },
];
const OPERATIONS = {
  7: { non_rattache: 0, commandes: [
    { commande_id: "cmd-1", numero: "BZ-000101", client: "Ablawa", paye_le: "2026-11-01T10:00:00Z", total: 10000,
      part: 8000, couvert: 8000, paiement: "feexpay", transaction: "FX-778899", confirme_par: "", origine: "application",
      alertes: [] },
    { commande_id: "cmd-2", numero: "BZ-000102", client: "Client Test", paye_le: "2026-11-02T10:00:00Z", total: 10000,
      part: 8000, couvert: 8000, paiement: "whatsapp", transaction: "WA-1", confirme_par: "chef@bizzoo.bj", origine: "whatsapp",
      alertes: ["Paiement confirmé à la main par chef@bizzoo.bj", "Le nom ou la note du client parle de test"] }] },
  5: { non_rattache: 1000, commandes: [
    { commande_id: "cmd-0", numero: "BZ-000090", client: "Codjo", paye_le: "2026-10-30T10:00:00Z", total: 7000,
      part: 5000, couvert: 5000, paiement: "feexpay", transaction: "FX-1", confirme_par: "", origine: "application",
      alertes: [] }] },
};

async function ouvrir(moi, hash) {
  const ctx = await nav.newContext({ viewport: { width: 390, height: 2200 }, serviceWorkers: "block" });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  page.on("dialog", (d) => d.accept());
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "c" }));
    localStorage.setItem("impact-session", JSON.stringify({
      access_token: a.t, refresh_token: "r", expire_a: Date.now() + 3600000, email: a.email }));
  }, { t: jeton(moi), email: PROFILS[moi].email });
  const rpc = [];
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const c = new URL(req.url()).pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x) => route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
    let corps = null;
    try { corps = req.postDataJSON(); } catch (_) { corps = null; }
    if (c.startsWith("rpc/")) rpc.push({ nom: c.slice(4), corps });
    if (c === "rpc/etat_connexion") return d({ equipe: true, sms_exige: false, session_confirmee: true, numero: true });
    if (c === "rpc/solde_boutique") return d({ gagne: 22000, a_venir: 0, deja_encaisse: 0, reverse: 0, en_attente: 0,
      disponible: 22000, devise: "FCFA", reception: RECEPTION });
    if (c === "rpc/reversements_liste") return d(moi === SUP ? DEMANDES : []);
    if (c === "rpc/commandes_a_reverser") return d(A_REVERSER);
    if (c === "rpc/demander_reversement_commandes") return d(9);
    if (c === "rpc/reversement_operations") return d(OPERATIONS[corps && corps.cible] || { commandes: [], non_rattache: 0 });
    if (c === "rpc/vendeurs_liste") return d([]);
    if (c.startsWith("rpc/")) return d(null);
    if (c.startsWith("profils")) return d([PROFILS[moi]]);
    if (c.startsWith("boutiques")) return d(BOU);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229" }]);
    return d([]);
  });
  await page.goto(BASE + "/admin/index.html", { waitUntil: "domcontentloaded" });
  await pause(2200);
  if (hash) { await page.evaluate((h) => { location.hash = h; }, hash); await pause(1500); }
  return { ctx, page, erreurs, rpc };
}
const texte = (page, sel) => page.evaluate((s) => (document.querySelector(s) || {}).innerText || "", sel).then(plat);
const sansErreur = (o) => ok(!o.erreurs.length, "aucune erreur JavaScript" + (o.erreurs.length ? " : " + o.erreurs[0] : ""));

titre("1. La boutique demande des commandes précises");
{
  const o = await ouvrir(CHEF, "#/solde");
  await o.page.click("#sd-demander");
  await pause(400);
  ok(/Tout mon solde — 22 000 FCFA/.test(await texte(o.page, "#feuille-corps")) &&
     /Montant demandé : 22 000 FCFA/.test(await texte(o.page, "#rv-total")),
    "« Tout mon solde — 22 000 FCFA » d'office, et le montant le dit");
  ok(!(await o.page.$("#sd-montant")) && !(await o.page.$("#gn-montant")), "plus aucun montant libre à taper");
  await o.page.click('input[name="rv-mode"][value="commandes"]');
  await pause(800);
  const c = o.rpc.find((x) => x.nom === "commandes_a_reverser");
  ok(c && c.corps.genre === "boutique" && c.corps.cible === "bou_a", "ses commandes à reverser sont lues (boutique, bou_a)");
  const liste = await texte(o.page, "#rv-commandes");
  ok(/BZ-000101/.test(liste) && /BZ-000103/.test(liste) && /6 000 FCFA/.test(liste), "les trois commandes, avec leur montant");
  ok(await o.page.$eval("#rv-envoyer", (b) => b.disabled), "rien de coché : « Envoyer » est fermé");
  await o.page.click('[data-rv-commande="cmd-1"]');
  await o.page.click('[data-rv-commande="cmd-3"]');
  await pause(200);
  ok(/Montant demandé : 14 000 FCFA/.test(await texte(o.page, "#rv-total")), "deux commandes cochées : 14 000 FCFA");
  await o.page.click("#rv-envoyer");
  await pause(1000);
  const d = o.rpc.find((x) => x.nom === "demander_reversement_commandes");
  ok(d && d.corps.genre === "boutique" && d.corps.cible === "bou_a" &&
     JSON.stringify(d.corps.commandes) === JSON.stringify(["cmd-1", "cmd-3"]),
    "la demande part avec ses commandes : cmd-1, cmd-3");
  ok(!o.rpc.some((x) => x.nom === "demander_reversement"), "et pas comme un montant");
  sansErreur(o);
  await o.ctx.close();
}

titre("2. Le superadministrateur voit d'où vient l'argent");
{
  const o = await ouvrir(SUP, "#/reversements");
  await pause(800);
  const z = await texte(o.page, '[data-ops-id="7"]');
  ok(/2 commandes — 16 000 FCFA/.test(z), "la demande à traiter : 2 commandes, 16 000 FCFA, d'office");
  ok(/BZ-000101/.test(z) && /Ablawa/.test(z) && /FeexPay — référence FX-778899/.test(z),
    "BZ-000101 : Ablawa, FeexPay et sa référence");
  ok(/1 commande à vérifier avant d'envoyer/.test(z) && /Paiement confirmé à la main par chef@bizzoo.bj/.test(z) &&
     /parle de test/.test(z), "BZ-000102 : à vérifier — confirmé à la main, client « test »");
  ok(!!(await o.page.$('[data-ops-id="7"] a[href="#/commandes/cmd-1"]')), "le numéro ouvre la commande");
  ok(!o.rpc.some((x) => x.nom === "reversement_operations" && x.corps.cible === 5),
    "une demande déjà traitée ne se lit pas d'office");
  await o.page.click("#rv-faits summary");
  await o.page.click('[data-ops-id="5"] [data-ops-voir]');
  await pause(700);
  const z5 = await texte(o.page, '[data-ops-id="5"]');
  ok(/BZ-000090/.test(z5) && /1 000 FCFA ne viennent d'aucune commande remise/.test(z5),
    "au toucher : sa commande, et ce qui ne vient d'aucune commande");
  sansErreur(o);
  await o.ctx.close();
}

titre("3. L'administrateur de BIZZOO crée un vendeur");
{
  const o = await ouvrir(ADMBZ, "#/comptes");
  await pause(500);
  ok(!!(await o.page.$("#cp-nouveau-vendeur")), "Comptes : « Nouveau vendeur »");
  ok(!(await o.page.$('a#cp-vendeurs[href="#/vendeurs"]')), "sans l'écran des vendeurs, qui reste au superadministrateur");
  await o.page.click("#cp-nouveau-vendeur");
  await pause(500);
  ok(/Nouveau vendeur/.test(await texte(o.page, "#feuille")) || /Nouveau vendeur/.test(await o.page.evaluate(() => document.body.innerText)),
    "la feuille « Nouveau vendeur » s'ouvre");
  sansErreur(o);
  await o.ctx.close();
}
{
  const o = await ouvrir(SUP, "#/comptes");
  await pause(500);
  ok(!!(await o.page.$('a#cp-vendeurs[href="#/vendeurs"]')) && !(await o.page.$("#cp-nouveau-vendeur")),
    "le superadministrateur garde son écran des vendeurs");
  await o.ctx.close();
}
{
  const o = await ouvrir(CHEF, "#/comptes");
  await pause(500);
  ok(!(await o.page.$("#cp-nouveau-vendeur")) && !(await o.page.$("#cp-vendeurs")),
    "l'administrateur d'une boutique : ni l'un ni l'autre");
  await o.ctx.close();
}

await nav.close();
console.log(echecs
  ? "\n\x1b[31m" + echecs + " constat(s) en échec ✘\x1b[0m"
  : "\n\x1b[32mUn reversement se rattache à ses commandes ; l'administrateur de BIZZOO crée un vendeur ✔\x1b[0m");
process.exit(echecs ? 1 : 0);
